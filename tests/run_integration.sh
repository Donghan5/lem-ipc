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

new_match() {
	DIR="$(mktemp -d "$WORK/t.XXXXXX")" || exit 1
	PIDS=()
	MATCH_PIDS=()
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
}

wait_for_log() {
	local pattern="$1" file="$2" attempt
	for ((attempt = 0; attempt < 100; attempt++)); do
		grep -qE "$pattern" "$DIR/$file" && return 0
		sleep 0.05
	done
	return 1
}

remember_ipc() {
	local ids shm queue sem creator pid
	[ -n "$IPC_IDS" ] && return 0
	ids="$(cd "$DIR" && "$PROBE")" || return 1
	read -r shm queue sem creator <<< "$ids"
	for pid in "${MATCH_PIDS[@]}"; do
		if [ "$creator" = "$pid" ]; then
			IPC_IDS="$shm $queue $sem"
			return 0
		fi
	done
	return 1
}

# Match the exact IDs stored on this match's shared board.
reap_ipc() {
	local shm queue sem kind id flag status
	local leaked=() errors=()
	if [ -z "$IPC_IDS" ]; then
		remember_ipc || { echo "session IDs unavailable"; return 2; }
	fi
	read -r shm queue sem <<< "$IPC_IDS"
	for kind in shm queue sem; do
		case "$kind" in
			shm) id="$shm"; flag=m ;;
			queue) id="$queue"; flag=q ;;
			sem) id="$sem"; flag=s ;;
		esac
		"$PROBE" "$kind" "$id"
		status=$?
		case "$status" in
			0)
				leaked+=("$kind:$id")
				ipcrm "-$flag" "$id"
				"$PROBE" "$kind" "$id"
				[ "$?" = 1 ] || errors+=("$kind:$id still present or unreadable")
				;;
			1) ;;
			*) errors+=("$kind:$id could not be inspected") ;;
		esac
	done
	if [ "${#errors[@]}" -gt 0 ]; then
		echo "${errors[*]}"
		return 2
	fi
	if [ "${#leaked[@]}" -gt 0 ]; then
		echo "removed leaked objects: ${leaked[*]}"
		return 1
	fi
	echo "shm, queue and sem absent"
}

signal_players() {
	local signal="$1" pid active
	active="$(jobs -pr; jobs -ps)"
	for pid in "${PIDS[@]}"; do
		if grep -qx "$pid" <<< "$active"; then
			kill "-$signal" "$pid" 2>/dev/null
		fi
	done
}

collect_players() {
	local limit="$1" deadline pid status
	deadline=$((SECONDS + limit))
	while [ -n "$(jobs -pr; jobs -ps)" ] && [ "$SECONDS" -lt "$deadline" ]; do
		sleep 0.1
	done
	EXITS_OK=1
	if [ -n "$(jobs -pr; jobs -ps)" ]; then
		signal_players KILL
		EXITS_OK=0
	fi
	for pid in "${PIDS[@]}"; do
		wait "$pid" 2>/dev/null
		status=$?
		[ "$status" = 0 ] || EXITS_OK=0
		if [ "$pid" = "${VALGRIND_PID:-}" ]; then
			VALGRIND_STATUS="$status"
		fi
	done
	PIDS=()
}

cleanup_all() {
	if [ "${#PIDS[@]}" -gt 0 ]; then
		remember_ipc
		signal_players KILL
		collect_players 1
		reap_ipc >/dev/null
	fi
	rm -rf "$WORK"
}
trap cleanup_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

report() { # name result_ok known_fail note
	local name="$1" ok="$2" known="$3" note="$4"
	if [ "$ok" = 1 ] && [ "$known" = 1 ]; then
		XPASS=$((XPASS + 1)); printf '  XPASS %-42s %s\n' "$name" "(known bug now fixed!)"
	elif [ "$ok" = 1 ]; then
		PASS=$((PASS + 1)); printf '  ok    %-42s %s\n' "$name" "$note"
	elif [ "$known" = 1 ]; then
		XFAIL=$((XFAIL + 1)); printf '  XFAIL %-42s %s\n' "$name" "$note"
	else
		FAIL=$((FAIL + 1)); printf '  FAIL  %-42s %s\n' "$name" "$note"
	fi
}

check_cleanup() {
	local name="$1" expected_fail="${2:-0}" detail status ok=0
	detail="$(reap_ipc)"
	status=$?
	[ "$status" = 0 ] && ok=1
	[ "$status" = 2 ] && expected_fail=0
	report "$name" "$ok" "$expected_fail" "$detail"
}

# Capture IPC IDs while the first player is still waiting for the roster.
start_first() {
	launch "$@"
	wait_for_log ' joined team ' "$1" && remember_ipc
}

test_invalid_args() {
	local ok=1 a
	new_match
	for a in "" "8" "12" "a" "-1" "99"; do
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
	local ok=0
	new_match
	start_first p1.log 3 "$BIN" 1
	launch p2.log 3 "$BIN" 1
	launch p3.log 3 "$BIN" 2
	collect_players 60
	grep -qh '^Team 1 wins$' "$DIR"/p*.log && ok=$EXITS_OK
	report "match_declares_a_winner" "$ok" 0 ""
	ok=0
	grep -q '^Player [0-9]* was eliminated$' "$DIR/p3.log" && ok=1
	report "losing_player_is_eliminated" "$ok" 0 ""
	check_cleanup "ipcs_clean_after_normal_match"
}

test_sigint_withdraws() {
	new_match
	start_first s1.log 4 "$BIN" 1
	launch s2.log 4 "$BIN" 2
	wait_for_log ' joined team ' s2.log
	signal_players INT
	collect_players 5
	report "sigint_stops_every_player" "$EXITS_OK" 0 ""
	check_cleanup "ipcs_clean_after_sigint_withdrawal"
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
	check_cleanup "ipc_cleanup_after_sigkill" "$survivor_ok"
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
	report "player_lines_never_garbled" "$ok" "$EXITS_OK" "malformed=$bad/$total lines"
	check_cleanup "ipcs_clean_after_shared_output"
}

test_valgrind_match() {
	if ! command -v valgrind >/dev/null; then
		printf '  skip  %-42s %s\n' "valgrind_clean_match" "(valgrind not installed)"
		return
	fi
	local ok=0
	new_match
	start_first v.log 3 valgrind -q --leak-check=full \
		--errors-for-leak-kinds=definite,indirect,possible --error-exitcode=42 "$BIN" 1
	VALGRIND_PID=$PID
	launch v2.log 3 "$BIN" 1
	launch v3.log 3 "$BIN" 2
	collect_players 120
	[ "$VALGRIND_STATUS" = 0 ] && ok=$EXITS_OK
	report "valgrind_clean_match" "$ok" 0 "exit=$VALGRIND_STATUS"
	unset VALGRIND_PID VALGRIND_STATUS
	check_cleanup "ipcs_clean_after_valgrind"
}

if [ ! -x "$BIN" ] || [ ! -x "$PROBE" ]; then
	echo "integration: build lemipc and ipc_probe with make integration" >&2
	exit 1
fi

echo "== integration: real processes + System V IPC =="
test_invalid_args
test_invalid_env
test_display_without_session
test_match_and_cleanup
test_sigint_withdraws
test_over_join_refused
test_simultaneous_launch
test_display_renders_grid
test_stress_20_players
test_cleanup_after_sigkill
test_output_not_garbled
test_valgrind_match

echo
echo "-- integration: $PASS passed, $FAIL failed, $XFAIL xfail (known bugs), $XPASS xpass"
if [ "$XPASS" -gt 0 ]; then
	echo "   XPASS means a known bug is fixed: drop its known-fail flag in $0"
fi
[ "$FAIL" -eq 0 ]
