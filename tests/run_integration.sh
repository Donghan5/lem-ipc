#!/usr/bin/env bash
# Each match has its own working directory, child processes, and IPC IDs.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/lemipc"
PROBE="$ROOT/tests/ipc_probe"
PLAYER_LINE='^(Player [0-9]+ (joined team [0-9]+|\(team [0-9]+\) moved|was eliminated)|Team [0-9]+ wins)$'
WORK="$(mktemp -d)" || exit 1
PASS=0
FAIL=0
XFAIL=0
XPASS=0
PIDS=()
declare -A EXPECTED_EXIT PROCESS_LOG OWNED_IPC EVAL_CHECKS EVAL_DETAILS

new_match() {
	DIR="$(mktemp -d "$WORK/t.XXXXXX")" || exit 1
	PIDS=()
	MATCH_PIDS=()
	EXPECTED_EXIT=()
	PROCESS_LOG=()
	IPC_IDS=
}

launch() {
	local log="$1" expected="$2"
	shift 2
	(
		cd "$DIR" || exit 1
		if [ -n "$log" ]; then
			exec >>"$log" 2>&1
		fi
		exec env --default-signal=INT LEMIPC_PLAYERS="$expected" "$@"
	) &
	PID=$!
	PIDS+=("$PID")
	MATCH_PIDS+=("$PID")
	PROCESS_LOG[$PID]=${log:-child}
}

wait_for_log() {
	local pattern="$1" file="$2" attempt
	for ((attempt = 0; attempt < 100; attempt++)); do
		grep -qsE "$pattern" "$DIR/$file" && return 0
		sleep 0.05
	done
	return 1
}

remember_ipc() {
	local ids shm queue sem creator pid
	[ -n "$IPC_IDS" ] && return 0
	ids="$(cd "$DIR" && "$PROBE")" || return 1
	read -r shm queue sem creator <<< "$ids"
	[[ $shm =~ ^[0-9]+$ && $queue =~ ^[0-9]+$ && $sem =~ ^[0-9]+$ ]] || return 1
	for pid in "${MATCH_PIDS[@]}"; do
		if [ "$creator" = "$pid" ]; then
			IPC_IDS="$shm $queue $sem"
			OWNED_IPC[$IPC_IDS]=1
			return 0
		fi
	done
	return 1
}

# Inspect the recorded IDs before any fallback removal.
inspect_ipc() {
	local expected="$1" remove="${2:-0}" kind label id flag status result
	local shm queue sem status_after all_absent=1 details=()
	IPC_OK=1
	read -r shm queue sem <<< "$IPC_IDS"
	for kind in shm sem queue; do
		case "$kind" in
			shm) label=SHM; id="$shm"; flag=m ;;
			sem) label=SEM; id="$sem"; flag=s ;;
			queue) label=MSGQ; id="$queue"; flag=q ;;
		esac
		"$PROBE" "$kind" "$id" 2>>"$DIR/ipc-diagnostics"
		status=$?
		status_after=$status
		result=PASS
		if [ "$status" != "$expected" ]; then
			result=FAIL
			IPC_OK=0
			printf '%s ID %s: expected probe status %s, got %s (0 = present, 1 = absent)\n' \
				"$label" "${id:-unknown}" "$expected" "$status" >>"$DIR/ipc-diagnostics"
			if [ "$remove" = 1 ] && [ "$status" = 0 ]; then
				ipcrm "-$flag" "$id" >>"$DIR/ipc-diagnostics" 2>&1
				"$PROBE" "$kind" "$id" 2>>"$DIR/ipc-diagnostics"
				status_after=$?
				if [ "$status_after" = 1 ]; then
					result="FAIL (ID $id, fallback removed)"
				else
					result="FAIL (ID $id, fallback failed)"
				fi
			else
				result="FAIL (ID ${id:-unknown})"
			fi
		fi
		[ "$status_after" = 1 ] || all_absent=0
		if [ "${VERBOSE:-0}" = 1 ]; then
			printf '%s ID %s: %s (expected probe status %s)\n' \
				"$label" "${id:-unknown}" "$result" "$expected" >>"$DIR/ipc-trace"
		fi
		details+=("$label $result")
	done
	if [ "$all_absent" = 1 ] && [ -n "$IPC_IDS" ]; then
		unset 'OWNED_IPC[$IPC_IDS]'
	fi
	IPC_DETAIL="${details[*]}"
}

signal_tracked() {
	local signal="$1" pid ok=0
	shift
	for pid in "$@"; do
		if kill "-$signal" "$pid" 2>/dev/null; then
			case "$signal" in
				KILL) EXPECTED_EXIT[$pid]=137 ;;
			esac
		else
			ok=1
		fi
	done
	return "$ok"
}

signal_players() {
	local signal="$1" pid active
	active=$'\n'$(jobs -pr; jobs -ps)$'\n'
	for pid in "${PIDS[@]}"; do
		if [[ $active == *$'\n'"$pid"$'\n'* ]]; then
			kill "-$signal" "$pid" 2>/dev/null
		fi
	done
}

collect_players() {
	local limit="$1" deadline pid status expected
	local problems=()
	deadline=$((SECONDS + limit))
	while [ -n "$(jobs -pr; jobs -ps)" ] && [ "$SECONDS" -lt "$deadline" ]; do
		sleep 0.1
	done
	EXITS_OK=1
	if [ -n "$(jobs -pr; jobs -ps)" ]; then
		signal_players KILL
		EXITS_OK=0
		problems+=("timeout after ${limit}s")
	fi
	for pid in "${PIDS[@]}"; do
		wait "$pid" 2>/dev/null
		status=$?
		expected="${EXPECTED_EXIT[$pid]:-0}"
		if [ "$status" != "$expected" ]; then
			EXITS_OK=0
			problems+=("${PROCESS_LOG[$pid]} PID $pid exited $status (expected $expected)")
		fi
	done
	PIDS=()
	if [ "$EXITS_OK" = 0 ]; then
		PROCESS_RESULT=FAIL
		printf '%s\n' "${problems[@]}" >>"$DIR/process-diagnostics"
	elif [ "${PROCESS_RESULT:-N/A}" != FAIL ]; then
		PROCESS_RESULT=PASS
	fi
} 2>/dev/null

cleanup_all() {
	local ids
	if [ "${#PIDS[@]}" -gt 0 ]; then
		remember_ipc
		signal_players KILL
		collect_players 1
	fi
	for ids in "${!OWNED_IPC[@]}"; do
		IPC_IDS="$ids"
		inspect_ipc 1 1
	done
	rm -rf "$WORK"
}
trap cleanup_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

color_statuses() {
	if [[ ! -t 1 || ${TERM:-} == dumb || -n ${NO_COLOR:-} ]]; then
		cat
		return
	fi
	sed -E \
		-e $'s/\\b(PASS|XPASS|ok)\\b/\e[32m\\1\e[0m/g' \
		-e $'s/\\bFAIL\\b/\e[31m&\e[0m/g' \
		-e $'s/\\b(SKIP|XFAIL)\\b/\e[33m\\1\e[0m/g' \
		-e $'s/\\bN\/A\\b/\e[90m&\e[0m/g'
}

report() { # name result_ok known_fail note
	local name="$1" ok="$2" known="$3" note="$4" status
	if [ "${EVAL_MODE:-0}" = 1 ]; then
		status=PASS
		if [ "$ok" != 1 ]; then
			status=FAIL
			EVAL_FAILED=1
		fi
		EVAL_CHECKS[$name]="$status"
		EVAL_DETAILS[$name]="$note"
		if [ "${VERBOSE:-0}" = 1 ]; then
			printf '%s %s\n' "$status" "$name" >>"$DIR/checks"
		fi
		return
	fi
	if [ "$ok" = 1 ] && [ "$known" = 1 ]; then
		XPASS=$((XPASS + 1)); status=XPASS; note="(known bug now fixed!)"
	elif [ "$ok" = 1 ]; then
		PASS=$((PASS + 1)); status=ok
	elif [ "$known" = 1 ]; then
		XFAIL=$((XFAIL + 1)); status=XFAIL
	else
		FAIL=$((FAIL + 1)); status=FAIL
	fi
	printf '  %-5s %-42s %s\n' "$status" "$name" "$note" | color_statuses
}

check_cleanup() {
	local name="$1"
	inspect_ipc 1 1
	report "$name" "$IPC_OK" 0 "$IPC_DETAIL"
}

# Capture IPC IDs while the first player is still waiting for the roster.
start_first() {
	launch "$@"
	wait_for_log ' joined team ' "$1" && remember_ipc
}

test_invalid_args() {
	local ok=1 a
	new_match
	for a in "" "a" "-1" "+1" "1a" " 1" "2147483648"; do
		( cd "$DIR" && timeout 3 "$BIN" "$a" >/dev/null 2>&1 )
		[ "$?" = 1 ] || ok=0
	done
	( cd "$DIR" && timeout 3 "$BIN" >/dev/null 2>&1 )
	[ "$?" = 1 ] || ok=0
	( cd "$DIR" && timeout 3 "$BIN" 1 2 >/dev/null 2>&1 )
	[ "$?" = 1 ] || ok=0
	report "invalid_args_rejected" "$ok" 0 ""
}

test_invalid_env() {
	local ok=1 v
	new_match
	for v in 0 1 401 99999 "" abc 2x -5; do
		( cd "$DIR" && LEMIPC_PLAYERS="$v" timeout 3 "$BIN" 1 >/dev/null 2>&1 )
		[ "$?" = 1 ] || ok=0
	done
	report "invalid_env_rejected" "$ok" 0 ""
}

test_display_without_session() {
	local ok=0
	new_match
	( cd "$DIR" && timeout 3 "$BIN" 0 >/dev/null 2>&1 )
	[ "$?" = 1 ] && ok=1
	report "display_without_session_fails" "$ok" 0 ""
}

test_match_and_cleanup() {
	local memory="${1:-0}" first_ok=0 ok=0
	new_match
	prepare_memory "$memory"
	start_checked p1.log 3 1 && first_ok=1
	launch_checked p2.log 3 1
	launch_checked p3.log 3 2
	wait_for_log ' joined team ' p3.log
	inspect_ipc 0
	[ "$first_ok" = 1 ] && ok=$IPC_OK
	report "one_shm_sem_and_msq_per_match" "$ok" 0 "$IPC_DETAIL"
	collect_players 60
	ok=0
	grep -qh '^Team 1 wins$' "$DIR/p1.log" "$DIR/p2.log" && ok=$EXITS_OK
	report "match_declares_a_winner" "$ok" 0 ""
	ok=0
	grep -q '^Player [0-9]* was eliminated$' "$DIR/p3.log" && ok=1
	report "losing_player_is_eliminated" "$ok" 0 ""
	check_cleanup "ipcs_clean_after_normal_match"
}

test_signal_withdraws() {
	local signal="$1" name="${1,,}" ready=0 sent=0
	new_match
	prepare_memory "${EVAL_MODE:-0}"
	start_checked s1.log 4 1 && ready=1
	launch_checked s2.log 4 2
	if wait_for_log ' joined team ' s2.log && signal_tracked "$signal" "${PIDS[@]}"; then
		sent=1
	fi
	collect_players 5
	[ "$ready" = 1 ] && [ "$sent" = 1 ] || EXITS_OK=0
	report "sig${name}_stops_every_player" "$EXITS_OK" 0 ""
	check_cleanup "ipcs_clean_after_sig${name}_withdrawal"
}

test_over_join_refused() {
	local ok=0
	new_match
	start_first o1.log 2 "$BIN" 1
	launch o2.log 2 "$BIN" 2
	if wait_for_log ' joined team ' o2.log; then
		( cd "$DIR" && timeout 5 "$BIN" 1 >o3.log 2>&1 )
		[ "$?" = 1 ] && grep -q "closed to new players" "$DIR/o3.log" && ok=1
	fi
	report "over_join_refused" "$ok" 0 ""
	signal_players INT
	collect_players 5
	check_cleanup "ipcs_clean_after_late_join"
}

test_simultaneous_launch() {
	local team index=0 ids ok=0
	new_match
	for team in 1 1 2 2; do
		index=$((index + 1))
		launch "race.$index.log" 4 "$BIN" "$team"
	done
	wait_for_log ' joined team ' race.1.log
	remember_ipc
	collect_players 60
	ids="$(grep -ho '^Player [0-9]* joined' "$DIR"/race.*.log | sort -u | wc -l)"
	[ "$ids" = 4 ] && ok=1
	report "simultaneous_launch_no_duplicate_ids" "$ok" 0 "distinct ids=$ids/4"
	ok=0
	grep -qhE '^Team [12] wins$' "$DIR"/race.*.log && ok=$EXITS_OK
	report "simultaneous_launch_match_terminates" "$ok" 0 ""
	check_cleanup "ipcs_clean_after_simultaneous_launch"
}

test_display_renders_grid() {
	local ok=0
	new_match
	start_first d1.log 3 "$BIN" 1
	( cd "$DIR" && timeout 2 "$BIN" 0 >view.log 2>&1 )
	# A complete frame contains 20 consecutive rows of width 20.
	awk '
		length == 20 && /^[.1-7]+$/ { if (++rows == 20) found = 1; next }
		{ rows = 0 }
		END { exit !found }
	' "$DIR/view.log" && ok=1
	report "display_renders_20x20_grid" "$ok" 0 ""
	ok=0
	grep -qE '^[.1-7]*1[.1-7]*$' "$DIR/view.log" && ok=1
	report "display_shows_team_digits" "$ok" 0 ""
	signal_players INT
	collect_players 5
	check_cleanup "ipcs_clean_after_display"
}

# FAQ: no specific limit on the number of teams, so ids past 7 must play.
test_large_team_ids() {
	local memory="${1:-0}" ok=0
	new_match
	prepare_memory "$memory" "first player of each team"
	start_checked big8.log 3 8
	launch_checked big42a.log 3 42
	launch big42b.log 3 "$BIN" 42
	wait_for_log ' joined team 42$' big42b.log
	( cd "$DIR" && timeout 2 "$BIN" 0 >view.log 2>&1 )
	grep -q '^Player [0-9]* joined team 8$' "$DIR/big8.log" \
		&& grep -q '^Player [0-9]* joined team 42$' "$DIR/big42a.log" && ok=1
	report "teams_8_and_42_join" "$ok" 0 ""
	ok=0
	grep -qE '(^| )42( |$)' "$DIR/view.log" \
		&& grep -qE '(^| )+8( |$)' "$DIR/view.log" && ok=1
	report "display_shows_multi_digit_teams" "$ok" 0 ""
	collect_players 60
	ok=0
	grep -qhE '^Team (8|42) wins$' "$DIR"/big*.log && ok=$EXITS_OK
	report "large_team_match_terminates" "$ok" 0 ""
	check_cleanup "ipcs_clean_after_large_team_match"
}

# The subject needs two players of one team to eliminate anyone, so a
# one-on-one match never ends by itself: both keep moving until Ctrl-C.
test_one_on_one_stalemate() {
	local memory="${1:-0}" ok=0 moved
	new_match
	prepare_memory "$memory"
	start_checked duel1.log 2 1
	launch_checked duel2.log 2 2
	wait_for_log ' joined team 2$' duel2.log
	sleep 5
	moved="$(grep -c ' moved$' "$DIR"/duel1.log "$DIR"/duel2.log | awk -F: '$2 > 0' | wc -l)"
	if [ "$moved" = 2 ] && [ "$(jobs -pr | wc -l)" = 2 ] \
		&& ! grep -qE 'eliminated|wins' "$DIR"/duel1.log "$DIR"/duel2.log; then
		ok=1
	fi
	report "one_on_one_never_ends" "$ok" 0 "players still moving after 5s=$moved/2"
	signal_players INT
	collect_players 10
	report "one_on_one_stops_on_sigint" "$EXITS_OK" 0 ""
	check_cleanup "ipcs_clean_after_one_on_one"
}

test_stress_20_players() {
	local i team joined ok=0
	new_match
	start_first big.01.log 20 "$BIN" 1
	for ((i = 2; i <= 20; i++)); do
		team=1
		[ "$i" -gt 10 ] && team=2
		launch "big.$i.log" 20 "$BIN" "$team"
	done
	collect_players 90
	joined="$(grep -ho '^Player [0-9]* joined' "$DIR"/big.*.log | sort -u | wc -l)"
	[ "$joined" = 20 ] && ok=1
	report "stress_20_players_all_join" "$ok" 0 "joined=$joined/20"
	ok=0
	grep -qhE '^Team [12] wins$' "$DIR"/big.*.log && ok=$EXITS_OK
	report "stress_20_players_terminates" "$ok" 0 ""
	check_cleanup "ipcs_clean_after_stress"
}

launch_stress_roster() {
	local deadline="$1" team slot count
	start_checked stress.1.1.log 400 1 || return 1
	for ((team = 1; team <= 7; team++)); do
		count=57
		[ "$team" != 1 ] || count=58
		for ((slot = 1; slot <= count; slot++)); do
			[ "$team.$slot" != 1.1 ] || continue
			[ "$SECONDS" -lt "$deadline" ] || return 1
			if [ "$slot" = 1 ]; then
				launch_checked "stress.$team.$slot.log" 400 "$team"
			else
				launch "stress.$team.$slot.log" 400 "$BIN" "$team"
			fi
		done
	done
}

stress_roster() {
	awk '
		/^Player [0-9]+ joined team [1-7]$/ {
			name = FILENAME
			sub(/^.*\//, "", name)
			split(name, file, "[.]")
			if (seen_file[FILENAME]++ || seen_id[$2]++ || $2 < 1 || $2 > 400 				|| $NF != file[2])
				bad = 1
			else {
				joined++
				teams[$NF]++
			}
		}
		END {
			printf "%d/400 unique players; teams", joined
			for (team = 1; team <= 7; team++) {
				printf " %d=%d", team, teams[team]
				if (teams[team] != (team == 1 ? 58 : 57))
					bad = 1
			}
			if (joined != 400 || bad)
				exit 1
		}
	' "$DIR"/stress.*.log
}

stress_result() {
	printf '%-12s %s %s\n' "$1" "$2" "$3" | color_statuses
}

run_stress() {
	local deadline roster progress result=0 ready=0 started=$SECONDS lifecycle process
	new_match
	prepare_memory 1
	printf '== stress: 7 teams, 400 player processes ==\n'
	deadline=$((SECONDS + 30))
	if launch_stress_roster "$deadline"; then
		while [ "$SECONDS" -lt "$deadline" ]; do
			if roster="$(stress_roster 2>/dev/null)"; then
				ready=1
				break
			fi
			sleep 0.1
		done
	fi
	if [ "$ready" = 1 ]; then
		stress_result "Join" PASS "$roster"
		deadline=$((SECONDS + 30))
		while [ "$SECONDS" -lt "$deadline" ]; do
			progress="$(awk '/ (moved|was eliminated)$/ { print; exit }' "$DIR"/stress.*.log)"
			[ -z "$progress" ] || break
			sleep 0.1
		done
		if [ -n "$progress" ]; then
			stress_result "Progress" PASS "$progress"
		else
			stress_result "Progress" FAIL "no move or elimination observed within 30s"
			result=1
		fi
	else
		roster="$(stress_roster 2>/dev/null)"
		stress_result "Join" FAIL "${roster:-no join logs}; expected full roster within 30s"
		stress_result "Progress" SKIP "full roster did not join"
		result=1
	fi

	remember_ipc
	signal_players INT
	collect_players 15
	if [ "$EXITS_OK" = 1 ]; then
		stress_result "Shutdown" PASS "${#MATCH_PIDS[@]} players reaped after SIGINT (15s limit)"
	else
		stress_result "Shutdown" FAIL "timeout or unexpected exit status"
		cat "$DIR/process-diagnostics"
		result=1
	fi
	MEMORY_LABEL="Valgrind, first player per team (${#MEMORY_CHECKS[@]}/400 players)"
	check_memory
	printf '%-12s %s\n' Memory "$MEMORY_RESULT" | color_statuses
	if [[ $MEMORY_RESULT == FAIL* ]]; then
		[ ! -s "$DIR/memory-diagnostics" ] || cat "$DIR/memory-diagnostics"
		result=1
	elif [ "${VERBOSE:-0}" = 1 ] && [ "$MEMORY_ENABLED" = 1 ]; then
		for process in "${MEMORY_CHECKS[@]}"; do
			cat "$DIR/$process.vg"
		done
	fi
	inspect_ipc 1 1
	if [ "$IPC_OK" = 1 ]; then
		stress_result "IPC cleanup" PASS "$IPC_DETAIL"
	else
		stress_result "IPC cleanup" FAIL "$IPC_DETAIL"
		cat "$DIR/ipc-diagnostics"
		result=1
	fi
	if [ "$ready" != 1 ]; then
		awk '!/^Player / && NF { print FILENAME ": " $0 }' "$DIR"/stress.*.log 2>/dev/null | head -10
	fi

	lifecycle="$ROOT/tests/test_ipc_lifecycle"
	if timeout --kill-after=2s 15s "$lifecycle" >"$DIR/lock-recovery.log" 2>&1 \
		&& grep -qE '^  ok +waiter_acquires_and_releases_lock_after_sigkill$' "$DIR/lock-recovery.log"; then
		stress_result "Lock recovery" PASS "blocked waiter acquired the semaphore after lock-owner SIGKILL"
	else
		stress_result "Lock recovery" FAIL "waiter recovery was not verified within 15s"
		result=1
	fi
	if [ "${VERBOSE:-0}" = 1 ] || [ "$result" != 0 ]; then
		cat "$DIR/lock-recovery.log"
	fi
	printf 'Elapsed: %ds\n' "$((SECONDS - started))"
	return "$result"
}

test_cleanup_after_sigkill() {
	local victim status survivor_ok=0
	new_match
	start_first k1.log 3 "$BIN" 1
	victim=$PID
	launch k2.log 3 "$BIN" 2
	if wait_for_log ' joined team ' k2.log && kill -KILL "$victim" 2>/dev/null; then
		wait "$victim" 2>/dev/null
		status=$?
		[ "$status" = 137 ] && survivor_ok=1
		PIDS=("$PID")
	fi
	signal_players INT
	collect_players 5
	[ "$EXITS_OK" = 1 ] || survivor_ok=0
	report "sigkill_scenario_completed" "$survivor_ok" 0 ""
	check_cleanup "ipc_cleanup_after_sigkill"
}

test_sigkill_during_match() {
	local victim winner=0 ready=0 killed=0
	new_match
	prepare_memory 1 "survivor only"
	start_checked survivor.log 2 1 && ready=1
	launch victim.log 2 "$BIN" 2
	victim=$PID
	if wait_for_log ' moved$' victim.log && signal_tracked KILL "$victim"; then
		killed=1
	else
		signal_players INT
	fi
	collect_players 10
	if [ "$ready" = 1 ] && [ "$killed" = 1 ] && grep -qx 'Team 1 wins' "$DIR/survivor.log"; then
		winner=$EXITS_OK
	fi
	report "sigkill_during_match_survivor_wins" "$winner" 0 ""
	check_cleanup "ipc_cleanup_after_running_sigkill"
	finish_memory
}

# The victim's parent execs sleep, which never calls wait(): once killed, the
# victim stays a zombie, and kill(pid, 0) still succeeds on it.
test_zombie_opponent_reaped() {
	local holder victim zombie=0 winner=0
	new_match
	start_first zsurvivor.log 2 "$BIN" 1
	(
		cd "$DIR" || exit 1
		LEMIPC_PLAYERS=2 "$BIN" 2 >zvictim.log 2>&1 &
		exec sleep 30
	) &
	holder=$!
	if wait_for_log ' moved$' zvictim.log; then
		victim="$(pgrep -P "$holder" -x lemipc)"
		if [ -n "$victim" ] && kill -KILL "$victim"; then
			sleep 0.2
			[[ "$(ps -o stat= -p "$victim")" == Z* ]] && zombie=1
			wait_for_log '^Team 1 wins$' zsurvivor.log && winner=1
		fi
	fi
	kill -KILL "$holder" 2>/dev/null
	wait "$holder" 2>/dev/null
	signal_players INT
	collect_players 5
	report "zombie_opponent_is_a_zombie" "$zombie" 0 ""
	[ "$zombie" = 1 ] && [ "$EXITS_OK" = 1 ] || winner=0
	report "zombie_opponent_reaped_survivor_wins" "$winner" 0 ""
	check_cleanup "ipc_cleanup_after_zombie_opponent"
}

test_stale_session_replaced() {
	local victim stale_ids replacement_ok=0
	new_match
	start_first stale.log 4 "$BIN" 1
	victim=$PID
	stale_ids=$IPC_IDS
	if kill -KILL "$victim"; then
		wait "$victim" 2>/dev/null
		PIDS=()
		IPC_IDS=
		start_first replacement.log 3 "$BIN" 2
		if grep -qx 'Player 1 joined team 2' "$DIR/replacement.log" \
			&& [ -n "$stale_ids" ] && [ -n "$IPC_IDS" ] && [ "$stale_ids" != "$IPC_IDS" ]; then
			replacement_ok=1
		fi
	fi
	report "stale_session_replaced" "$replacement_ok" 0 ""
	local replacement_ids=$IPC_IDS
	IPC_IDS=$stale_ids
	check_cleanup "stale_session_ipcs_removed"
	IPC_IDS=$replacement_ids
	signal_players INT
	collect_players 5
	check_cleanup "replacement_session_ipcs_removed"
}

test_display_closes_last() {
	local player ready=0 attached=0 killed=0 closed=0
	new_match
	prepare_memory "${EVAL_MODE:-0}" "display; killed player N/A"
	start_first display-player.log 4 "$BIN" 1 && ready=1
	player=$PID
	launch_checked last-display.log 4 0
	if wait_for_log 'Waiting for players' last-display.log; then
		inspect_ipc 0
		[ "$ready" = 1 ] && attached=$IPC_OK
		signal_tracked KILL "$player" && killed=1
	else
		signal_players INT
	fi
	collect_players 5
	if [ "$killed" = 1 ] && grep -qx 'Session closed.' "$DIR/last-display.log"; then
		closed=$EXITS_OK
	fi
	report "display_renders_while_player_is_attached" "$attached" 0 ""
	report "last_display_exits_after_player_sigkill" "$closed" 0 ""
	check_cleanup "ipc_cleanup_after_last_display"
}

test_output_not_garbled() {
	local team bad total attempt ok=0
	new_match
	{
		for team in 1 1 2 2; do
			launch "" 4 "$BIN" "$team"
		done
	} >"$DIR/shared.log" 2>&1
	for ((attempt = 0; attempt < 100; attempt++)); do
		remember_ipc && break
		sleep 0.05
	done
	collect_players 60
	total="$(sed '/^$/d' "$DIR/shared.log" | wc -l)"
	bad="$(sed '/^$/d' "$DIR/shared.log" | grep -cvE "$PLAYER_LINE")"
	report "shared_output_match_completed" "$EXITS_OK" 0 ""
	[ "$total" -ge 4 ] && [ "$bad" = 0 ] && ok=1
	report "player_lines_never_garbled" "$ok" 0 "malformed=$bad/$total lines"
	check_cleanup "ipcs_clean_after_shared_output"
}

test_valgrind_match() {
	if ! command -v valgrind >/dev/null; then
		printf '  SKIP  %-42s %s\n' "valgrind_clean_match" "(valgrind not installed)" | color_statuses
		return
	fi
	test_match_and_cleanup 1
	finish_memory
}

# `lemipc N | head -1` closes stdout under the player: the next line it prints
# raises SIGPIPE, which must end the match cleanly instead of killing it.
test_closed_stdout_cleans_up() {
	local ready=0 ok=0
	new_match
	if mkfifo "$DIR/p1.fifo" "$DIR/p2.fifo"; then
		launch p1.log 2 head -n 1 p1.fifo
		launch "" 2 sh -c 'exec "$1" 1 >p1.fifo' sh "$BIN"
		wait_for_log ' joined team ' p1.log && remember_ipc && ready=1
		launch p2.log 2 head -n 1 p2.fifo
		launch "" 2 sh -c 'exec "$1" 2 >p2.fifo' sh "$BIN"
		collect_players 15
		[ "$ready" = 1 ] && ok=$EXITS_OK
	fi
	report "closed_stdout_ends_match_cleanly" "$ok" 0 ""
	check_cleanup "ipcs_clean_after_closed_stdout"
}

# Two players of one team die in the same instant: the survivors must reap
# both in one pass, win, and clean up.
test_simultaneous_deaths() {
	local first second third fourth winner=0
	new_match
	start_first d1.log 4 "$BIN" 1
	first=$PID
	launch d2.log 4 "$BIN" 1
	second=$PID
	launch d3.log 4 "$BIN" 2
	third=$PID
	launch d4.log 4 "$BIN" 2
	fourth=$PID
	if wait_for_log ' moved$' d4.log && kill -KILL "$third" "$fourth"; then
		wait "$third" "$fourth" 2>/dev/null
		PIDS=("$first" "$second")
		collect_players 10
		grep -qx 'Team 1 wins' "$DIR/d1.log" "$DIR/d2.log" && winner=$EXITS_OK
	fi
	if [ "${#PIDS[@]}" -gt 0 ]; then
		signal_players KILL
		collect_players 1
	fi
	report "simultaneous_deaths_survivors_win" "$winner" 0 ""
	check_cleanup "ipcs_clean_after_simultaneous_deaths"
}

# SIGKILL cannot be caught, so a match where everyone is killed leaves its
# session behind; the next run in that directory must reclaim it and play.
test_all_killed_then_rerun() {
	local stale_ids rerun_ids ready=0 killed=0 replayed=0
	new_match
	prepare_memory "${EVAL_MODE:-0}" "replay players; killed players N/A"
	start_first k1.log 4 "$BIN" 1 && ready=1
	launch k2.log 4 "$BIN" 1
	launch k3.log 4 "$BIN" 2
	launch k4.log 4 "$BIN" 2
	if wait_for_log ' moved$' k4.log && signal_tracked KILL "${PIDS[@]}"; then
		killed=1
	else
		signal_players INT
	fi
	collect_players 5
	[ "$EXITS_OK" = 1 ] && [ "$ready" = 1 ] || killed=0
	report "all_players_killed_and_reaped" "$killed" 0 ""
	inspect_ipc 0
	report "running_session_left_by_sigkill" "$IPC_OK" 0 "${EVAL_MODE:+$IPC_DETAIL}"
	stale_ids=$IPC_IDS
	IPC_IDS=
	start_checked r1.log 3 1
	rerun_ids=$IPC_IDS
	IPC_IDS=$stale_ids
	check_cleanup "killed_running_session_reclaimed"
	IPC_IDS=$rerun_ids
	launch_checked r2.log 3 1
	launch_checked r3.log 3 2
	collect_players 60
	if grep -qx 'Team 1 wins' "$DIR/r1.log" "$DIR/r2.log" && [ -n "$IPC_IDS" ] \
		&& [ "$IPC_IDS" != "$stale_ids" ]; then
		replayed=$EXITS_OK
	fi
	report "rerun_after_sigkill_plays_full_match" "$replayed" 0 ""
	check_cleanup "ipcs_clean_after_rerun"
}

prepare_memory() {
	MEMORY_CHECKS=()
	MEMORY_RESULT=N/A
	MEMORY_ENABLED=0
	MEMORY_LABEL="${2:-}"
	if [ "$1" = 1 ]; then
		if command -v valgrind >/dev/null; then
			MEMORY_ENABLED=1
		else
			MEMORY_RESULT="SKIP (Valgrind unavailable${MEMORY_LABEL:+; $MEMORY_LABEL})"
		fi
	fi
}

launch_checked() {
	local log="$1" expected="$2" team="$3"
	local runner=("$BIN")
	if [ "$MEMORY_ENABLED" = 1 ]; then
		MEMORY_CHECKS+=("${log%.log}")
		runner=(env LC_ALL=C valgrind --leak-check=full --show-leak-kinds=definite,indirect,possible
			--errors-for-leak-kinds=definite,indirect,possible --error-exitcode=42
			"--log-file=$DIR/${log%.log}.vg" "$BIN")
	fi
	launch "$log" "$expected" "${runner[@]}" "$team"
}

start_checked() {
	launch_checked "$@"
	wait_for_log ' joined team ' "$1" && remember_ipc
}

valgrind_counts() {
	awk '
		/All heap blocks were freed/ { definite = indirect = possible = 0 }
		/definitely lost:/ { definite = $4 }
		/indirectly lost:/ { indirect = $4 }
		/possibly lost:/ { possible = $4 }
		/ERROR SUMMARY:/ { errors = $4 }
		END {
			gsub(/,/, "", errors); gsub(/,/, "", definite)
			gsub(/,/, "", indirect); gsub(/,/, "", possible)
			print errors == "" ? "unknown" : errors,
				definite == "" ? "unknown" : definite,
				indirect == "" ? "unknown" : indirect,
				possible == "" ? "unknown" : possible
		}
	' "$1"
}

check_memory() {
	local process errors definite indirect possible counts
	local findings=()
	[ "$MEMORY_ENABLED" = 1 ] || return 0
	for process in "${MEMORY_CHECKS[@]}"; do
		counts="$(valgrind_counts "$DIR/$process.vg" 2>/dev/null)" || counts="unknown unknown unknown unknown"
		read -r errors definite indirect possible <<< "$counts"
		if [ "$errors $definite $indirect $possible" != "0 0 0 0" ]; then
			findings+=("$process: errors=$errors, definite=${definite}B, indirect=${indirect}B, possible=${possible}B")
			cat "$DIR/$process.vg" >>"$DIR/memory-diagnostics" 2>/dev/null
		fi
	done
	if [ "${#findings[@]}" -gt 0 ]; then
		MEMORY_RESULT="FAIL (${findings[*]})"
	else
		MEMORY_RESULT="PASS (${MEMORY_LABEL:-${MEMORY_CHECKS[*]}})"
	fi
}

finish_memory() {
	check_memory
	case "$MEMORY_RESULT" in
	FAIL*)
		report "valgrind_memory_check" 0 0 "$MEMORY_RESULT"
		if [ "${EVAL_MODE:-0}" = 0 ]; then
			cat "$DIR/memory-diagnostics"
		fi
		;;
	PASS*)
		report "valgrind_memory_check" 1 0 "$MEMORY_RESULT"
		;;
	SKIP*)
		if [ "${EVAL_MODE:-0}" = 0 ]; then
			printf '  %s\n' "$MEMORY_RESULT" | color_statuses
		fi
		;;
	esac
}

EVAL_SCENARIOS=(normal-win sigint-withdrawal sigkill-survivor all-killed-recovery display-last
	large-teams one-on-one-stalemate)
EVAL_TITLES=(
	"Normal match"
	"Ctrl-C withdrawal (SIGINT)"
	"Kill one player (SIGKILL)"
	"Kill all players and restart"
	"Display exits last"
	"Team ids past 7"
	"One-on-one stalemate"
)
EVAL_EXPECTED=(
	"Team 1 wins, team 2 is eliminated, and the players remove all IPC."
	"Both players exit normally after SIGINT and remove all IPC."
	"After play starts, the victim exits on SIGKILL and the survivor wins and removes all IPC."
	"After play starts, SIGKILL leaves all three IDs behind. Relaunch in the same directory, reclaim those IDs, and finish a new match."
	"The display renders while the player is attached, then closes and removes all IPC after the player is killed."
	"Teams 8 and 42 join (the FAQ sets no team limit), the display widens its tiles for 42, one team wins, and the players remove all IPC."
	"With one player per team nobody can be eliminated, so both keep moving. Ctrl-C then stops both players and removes all IPC."
)

list_eval() {
	local i
	for i in "${!EVAL_SCENARIOS[@]}"; do
		[ "$i" = 0 ] || printf '\n'
		printf '[%d] %s (%s)\n    %s\n' "$((i + 1))" "${EVAL_TITLES[$i]}" \
			"${EVAL_SCENARIOS[$i]}" "${EVAL_EXPECTED[$i]}"
	done
}

print_eval_check() {
	local label="$1" check="$2" success="$3" failure="$4"
	if [ "${EVAL_CHECKS[$check]}" = PASS ]; then
		printf '    %-8s %s\n' "$label" "$success"
	else
		printf '    %-8s FAIL: %s%s\n' "$label" "$failure" "${EVAL_DETAILS[$check]:+ ${EVAL_DETAILS[$check]}}"
	fi
}

print_eval_game() {
	case "$1" in
		normal-win)
			print_eval_check Game: match_declares_a_winner 'Team 1 won.' 'Team 1 win was not confirmed.'
			print_eval_check '' losing_player_is_eliminated 'The team 2 player was eliminated.' 'Team 2 elimination was not confirmed.'
			if [ "${EVAL_CHECKS[one_shm_sem_and_msq_per_match]}" = FAIL ]; then
				print_eval_check IPC: one_shm_sem_and_msq_per_match '' 'Could not verify all three IPC resources during play.'
			fi
			;;
		sigint-withdrawal)
			print_eval_check Game: sigint_stops_every_player 'Both players exited normally after Ctrl-C.' 'Could not confirm both players withdrew normally after SIGINT.'
			;;
		sigkill-survivor)
			print_eval_check Game: sigkill_during_match_survivor_wins 'One player was killed. The survivor won.' 'Could not confirm the SIGKILL and survivor win.'
			;;
		all-killed-recovery)
			print_eval_check Game: all_players_killed_and_reaped 'All players in the running match were killed and reaped.' 'Could not confirm all players were killed and reaped.'
			print_eval_check '' rerun_after_sigkill_plays_full_match 'Team 1 won the replay.' 'Could not confirm a completed replay with fresh IPC IDs.'
			;;
		display-last)
			print_eval_check Game: display_renders_while_player_is_attached 'The display rendered while the player was attached.' 'Could not verify the display rendered with a player attached.'
			print_eval_check '' last_display_exits_after_player_sigkill 'After the player was killed, the display closed last.' 'Could not confirm the display closed after the player was killed.'
			;;
		large-teams)
			print_eval_check Game: teams_8_and_42_join 'Players of teams 8 and 42 joined.' 'Could not confirm teams 8 and 42 joined.'
			print_eval_check '' display_shows_multi_digit_teams 'The display showed 8 and 42 in widened tiles.' 'Could not find both team ids on the display.'
			print_eval_check '' large_team_match_terminates 'The match ended with a winner.' 'Could not confirm a winner.'
			;;
		one-on-one-stalemate)
			print_eval_check Game: one_on_one_never_ends 'After 5s both players were still moving, with no elimination or winner.' 'The one-on-one match did not stay in a stalemate.'
			print_eval_check '' one_on_one_stops_on_sigint 'Ctrl-C stopped both players normally.' 'Could not confirm both players stopped after SIGINT.'
			;;
	esac
}

print_eval_ipc() {
	local cleanup
	case "$1" in
		normal-win) cleanup=ipcs_clean_after_normal_match ;;
		sigint-withdrawal) cleanup=ipcs_clean_after_sigint_withdrawal ;;
		sigkill-survivor) cleanup=ipc_cleanup_after_running_sigkill ;;
		display-last) cleanup=ipc_cleanup_after_last_display ;;
		large-teams) cleanup=ipcs_clean_after_large_team_match ;;
		one-on-one-stalemate) cleanup=ipcs_clean_after_one_on_one ;;
		all-killed-recovery)
			print_eval_check IPC: running_session_left_by_sigkill 'Old SHM, SEM and MSGQ remained after SIGKILL.' 'Old resources after SIGKILL.'
			print_eval_check '' killed_running_session_reclaimed 'The restart removed the old SHM, SEM and MSGQ.' 'Old resources on restart.'
			print_eval_check '' ipcs_clean_after_rerun 'The replay removed its new SHM, SEM and MSGQ at exit.' 'New resources at replay exit.'
			return
			;;
	esac
	print_eval_check IPC: "$cleanup" 'SHM, SEM and MSGQ removed at exit.' 'Resource cleanup at exit.'
}

print_eval_logs() {
	local log
	for log in "$DIR"/process-diagnostics "$DIR"/ipc-diagnostics "$DIR"/memory-diagnostics; do
		[ -s "$log" ] || continue
		printf '    %s\n' "${log##*/}"
		sed 's/^/        /' "$log"
	done
	if [ "${VERBOSE:-0}" = 1 ]; then
		printf '    Checks:\n'
		sed 's/^/        /' "$DIR/checks" | color_statuses
		for log in "$DIR"/*.log "$DIR"/*.vg "$DIR"/ipc-trace; do
			[ -f "$log" ] || continue
			printf '    %s\n' "${log##*/}"
			sed 's/^/        /' "$log"
		done
	fi
}

run_eval_scenario() {
	local i="$1" name
	name="${EVAL_SCENARIOS[$i]}"
	EVAL_FAILED=0
	EVAL_CHECKS=()
	EVAL_DETAILS=()
	PROCESS_RESULT=N/A
	case "$name" in
		normal-win) test_match_and_cleanup 1 ;;
		sigint-withdrawal) test_signal_withdraws INT ;;
		sigkill-survivor) test_sigkill_during_match ;;
		all-killed-recovery) test_all_killed_then_rerun ;;
		display-last) test_display_closes_last ;;
		large-teams) test_large_team_ids 1 ;;
		one-on-one-stalemate) test_one_on_one_stalemate 1 ;;
	esac
	if [ "$name" != sigkill-survivor ]; then
		finish_memory
	fi
	EVAL_RESULT=PASS
	if [ "$EVAL_FAILED" = 1 ] || [ "$PROCESS_RESULT" != PASS ]; then
		EVAL_RESULT=FAIL
	elif [[ $MEMORY_RESULT == SKIP* ]]; then
		EVAL_RESULT=SKIP
	fi
	{
		printf '[%d] %s — %s\n' "$((i + 1))" "${EVAL_TITLES[$i]}" "$EVAL_RESULT"
		print_eval_game "$name"
		if [ "$PROCESS_RESULT" != PASS ]; then
			printf '    Process: %s\n' "$PROCESS_RESULT"
		fi
		printf '    Memory:  Valgrind %s\n' "${MEMORY_RESULT/Valgrind unavailable/unavailable}"
		print_eval_ipc "$name"
	} | color_statuses
	print_eval_logs
}

run_eval() {
	local selected="$1" i passed=0 failed=0 skipped=0 total=0
	EVAL_MODE=1
	for i in "${!EVAL_SCENARIOS[@]}"; do
		if [ -z "$selected" ] || [ "$selected" = "${EVAL_SCENARIOS[$i]}" ]; then
			[ "$total" = 0 ] || printf '\n'
			run_eval_scenario "$i"
			total=$((total + 1))
			case "$EVAL_RESULT" in
				PASS) passed=$((passed + 1)) ;;
				FAIL) failed=$((failed + 1)) ;;
				SKIP) skipped=$((skipped + 1)) ;;
			esac
		fi
	done
	if [ "$total" = 0 ]; then
		printf 'Unknown scenario "%s". Run make eval-list.\n' "$selected" >&2
		return 2
	fi
	if [ -z "$selected" ]; then
		printf '\n%d of %d scenarios passed.' "$passed" "$total"
		[ "$failed" = 0 ] || printf ' %d failed.' "$failed"
		[ "$skipped" = 0 ] || printf ' %d skipped.' "$skipped"
		printf '\n'
	fi
	[ "$failed" = 0 ]
}

if [ "${1:-}" = --eval-list ]; then
	list_eval
	exit 0
fi

if [ ! -x "$BIN" ] || [ ! -x "$PROBE" ]; then
	echo "integration: build lemipc and ipc_probe with make integration" >&2
	exit 1
fi

if [ "${1:-}" = --eval ]; then
	run_eval "${2:-}"
	exit "$?"
fi

if [ "${1:-}" = --stress ]; then
	run_stress
	exit "$?"
fi

echo "== integration: real processes + System V IPC =="
test_invalid_args
test_invalid_env
test_display_without_session
test_match_and_cleanup
for signal in INT TERM HUP QUIT; do test_signal_withdraws "$signal"; done
test_over_join_refused
test_simultaneous_launch
test_display_renders_grid
test_large_team_ids
test_one_on_one_stalemate
test_stress_20_players
test_cleanup_after_sigkill
test_sigkill_during_match
test_zombie_opponent_reaped
test_closed_stdout_cleans_up
test_stale_session_replaced
test_simultaneous_deaths
test_all_killed_then_rerun
test_display_closes_last
test_output_not_garbled
test_valgrind_match

echo
echo "-- integration: $PASS passed, $FAIL failed, $XFAIL xfail (known bugs), $XPASS xpass"
if [ "$XPASS" -gt 0 ]; then
	echo "   XPASS means a known bug is fixed: drop its known-fail flag in $0"
fi
[ "$FAIL" -eq 0 ]
