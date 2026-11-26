#!/usr/bin/env bash

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)" || exit 1
cd -- "$ROOT" || exit 1
BIN=./lemipc
PROBE="$ROOT/tests/ipc_probe"
team_count="${1:-2}"
mode="${2:-}"
if [[ ! $team_count =~ ^[2-7]$ ]]; then
	printf 'Demo: team count must be between 2 and 7.\n' >&2
	exit 1
fi
player_count=$((team_count * 2))
matchup=2
for ((team = 2; team <= team_count; team++)); do
	matchup+=' vs 2'
done
winner_pattern="^Team [1-$team_count] wins$"
LOG_DIR="$(mktemp -d /tmp/lemipc-demo.XXXXXX)" || exit 1
pids=()
logs=()
eliminated=()
interrupted=0
starting_player=0
display_invited=0
msgq_sent=0
msgq_received=0

active_players() {
	jobs -pr
	jobs -ps
}

signal_players() {
	local pid
	for pid in $(active_players); do
		kill "-$1" "$pid" 2>/dev/null
	done
}

cleanup() {
	local deadline=$((SECONDS + 3)) pid
	trap '' INT TERM HUP
	if [ -n "$(active_players)" ]; then
		signal_players TERM
		signal_players CONT
		while [ -n "$(active_players)" ] && [ "$SECONDS" -lt "$deadline" ]; do
			sleep 0.1
		done
		signal_players KILL
	fi
	for pid in "${pids[@]}"; do
		wait "$pid" 2>/dev/null
	done
	if [ "$display_invited" = 1 ]; then
		printf 'If the board is still open, press Ctrl-C in the left terminal.\n'
	fi
	rm -f -- "${logs[@]}"
	rmdir -- "$LOG_DIR"
}

fail() {
	printf 'Demo: %s\n' "$1" >&2
	exit 1
}

check_interrupt() {
	if [ "$interrupted" != 0 ]; then
		printf '\nDemo interrupted. Stopping demo players.\n' >&2
		exit "$interrupted"
	fi
}

handle_interrupt() {
	interrupted="$1"
	[ "$starting_player" = 1 ] || check_interrupt
}

# Linux ftok uses the project byte and the low bits of the device and inode.
check_session_key() {
	local identity device inode key
	identity="$(stat -c '%d %i' -- .)" || return 1
	read -r device inode <<< "$identity"
	key=$(( (76 << 24) | ((device & 255) << 16) | (inode & 65535) ))
	awk -v key="$key" '$1 == key { occupied = 1 } END { exit occupied }' \
		/proc/sysvipc/shm /proc/sysvipc/sem /proc/sysvipc/msg
}

start_player() {
	local team="$1" number deadline pid log
	number=$((${#pids[@]} + 1))
	check_interrupt
	log="$LOG_DIR/player-$number.log"
	logs+=("$log")
	starting_player=1
	LEMIPC_PLAYERS="$player_count" "$BIN" "$team" >"$log" 2>&1 &
	pid=$!
	pids+=("$pid")
	starting_player=0
	check_interrupt
	deadline=$((SECONDS + 5))
	while [ "$SECONDS" -lt "$deadline" ]; do
		check_interrupt
		if grep -sE "^Player [0-9]+ joined team $team$" "$log"; then
			return 0
		fi
		if ! grep -qx "$pid" <<< "$(active_players)"; then
			cat -- "$log" >&2
			fail "Player $number (Team $team) exited before joining."
		fi
		sleep 0.05
	done
	cat -- "$log" >&2
	fail "Timed out waiting for player $number (Team $team) to join."
}

show_eliminations() {
	local i
	for i in "${!logs[@]}"; do
		if [ -z "${eliminated[$i]}" ] \
			&& grep -m1 -E '^Player [0-9]+ was eliminated$' "${logs[$i]}"; then
			eliminated[$i]=1
		fi
	done
}

show_msgq_activity() {
	local snapshot sender receiver
	[[ $msgq_sent == 1 && $msgq_received == 1 ]] && return
	snapshot="$(awk -v id="$queue_id" '$2 == id { print $6, $7; exit }' /proc/sysvipc/msg)"
	read -r sender receiver <<< "$snapshot"
	if [[ $msgq_sent == 0 && -n $sender && " ${pids[*]} " == *" $sender "* ]]; then
		printf 'MSGQ %s: successful send observed (player PID %s).\n' "$queue_id" "$sender"
		msgq_sent=1
	fi
	if [[ $msgq_received == 0 && -n $receiver && " ${pids[*]} " == *" $receiver "* ]]; then
		printf 'MSGQ %s: successful receive observed (player PID %s).\n' "$queue_id" "$receiver"
		msgq_received=1
	fi
}

kill_demo_player() {
	local deadline=$((SECONDS + 5)) index pid player status
	while ! grep -qsE '^Player [0-9]+ \(team [12]\) moved$' "${logs[@]}"; do
		[ "$SECONDS" -lt "$deadline" ] || fail "No player moved before the SIGKILL demonstration."
		sleep 0.05
	done
	for index in 2 3; do
		pid="${pids[$index]}"
		if grep -qx "$pid" <<< "$(active_players)"; then
			break
		fi
		pid=
	done
	[ -n "$pid" ] || fail "No Team 2 player is still running."
	read -r _ player _ <"${logs[$index]}"
	printf 'Press Enter to send SIGKILL to Player %s (Team 2, PID %s). Watch the board on the left.\n' "$player" "$pid"
	if ! IFS= read -r -t 20; then
		fail "No confirmation received for SIGKILL."
	fi
	grep -qx "$pid" <<< "$(active_players)" && kill -KILL "$pid" 2>/dev/null \
		|| fail "Player $player exited before SIGKILL."
	wait "$pid" 2>/dev/null
	status=$?
	unset 'pids[index]'
	[ "$status" = 137 ] || fail "Player $player exited with status $status instead of SIGKILL."
	printf 'Player %s (Team 2) exited by SIGKILL. Watch the survivors on the board.\n' "$player"
}

check_kill_demo_cleanup() {
	local deadline=$((SECONDS + 5)) shm queue sem kind id status remaining
	read -r shm queue sem _ <<< "$session_ids"
	while :; do
		remaining=()
		for kind in shm sem queue; do
			case "$kind" in
				shm) id="$shm" ;;
				sem) id="$sem" ;;
				queue) id="$queue" ;;
			esac
			"$PROBE" "$kind" "$id"
			status=$?
			[ "$status" = 1 ] || remaining+=("$kind=$id")
		done
		if [ "${#remaining[@]}" = 0 ]; then
			printf 'IPC cleanup PASS: SHM %s, SEM %s and MSGQ %s are gone.\n' "$shm" "$sem" "$queue"
			return
		fi
		[ "$SECONDS" -lt "$deadline" ] || fail "IPC cleanup could not be confirmed: ${remaining[*]}."
		sleep 0.1
	done
}

finish_match() {
	local deadline=$((SECONDS + 120)) pid status winner failed=0
	while [ -n "$(active_players)" ]; do
		check_interrupt
		show_eliminations
		show_msgq_activity
		[ "$SECONDS" -lt "$deadline" ] || fail "Match timed out after 120 seconds."
		sleep 0.2
	done
	check_interrupt
	show_msgq_activity
	[ "$msgq_sent" = 1 ] || printf 'MSGQ %s: no send observed.\n' "$queue_id"
	[ "$msgq_received" = 1 ] || printf 'MSGQ %s: no receive observed.\n' "$queue_id"
	for pid in "${pids[@]}"; do
		wait "$pid"
		status=$?
		if [ "$status" != 0 ]; then
			printf 'Demo: Player process %s exited with status %s.\n' "$pid" "$status" >&2
			failed=1
		fi
	done
	pids=()
	show_eliminations
	winner="$(grep -hE "$winner_pattern" "${logs[@]}" | sort -u)"
	if [ "$failed" = 1 ] || [[ ! $winner =~ $winner_pattern ]]; then
		fail "The match did not finish cleanly with one confirmed winner."
	fi
	printf '%s.\n' "$winner"
}

trap cleanup EXIT
trap 'handle_interrupt 130' INT
trap 'handle_interrupt 143' TERM
trap 'handle_interrupt 129' HUP

check_session_key || fail "Could not confirm an unused IPC key for $ROOT. Close any existing session before running the demo."
start_player 1
session_ids="$("$PROBE")" || fail "Could not inspect the new session."
read -r _ queue_id _ creator <<< "$session_ids"
[ "$creator" = "${pids[0]}" ] || fail "The joined session was created by another process."
[[ $queue_id =~ ^[0-9]+$ ]] || fail "Could not identify the session's message queue."
printf 'MSGQ %s ready. Inspect it with: ipcs -q -i %s\n' "$queue_id" "$queue_id"

printf '\nIn the left terminal, run this command:\n'
printf '    cd %q && ./lemipc 0\n\n' "$ROOT"
display_invited=1
printf 'Press Enter when the board is visible to start the %s match.\n' "$matchup"
if ! IFS= read -r; then
	check_interrupt
	fail "Input closed before the match started."
fi
check_interrupt
if ! grep -qx "${pids[0]}" <<< "$(active_players)" \
	|| [ "$("$PROBE")" != "$session_ids" ]; then
	fail "The first player or its session is no longer available."
fi

start_player 1
for ((team = 2; team <= team_count; team++)); do
	start_player "$team"
	start_player "$team"
done
printf 'All %d players have joined. The match has started.\n' "$player_count"
if [ "$mode" = --kill-player ]; then
	kill_demo_player
fi
finish_match
if [ "$mode" = --kill-player ]; then
	check_kill_demo_cleanup
fi
