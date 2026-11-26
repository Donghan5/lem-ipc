#!/usr/bin/env bash

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)" || exit 1
BIN="$ROOT/lemipc"
PROBE="$ROOT/tests/ipc_probe"
SESSION="$(mktemp -d /tmp/lemipc-demo.XXXXXX)" || exit 1
pids=()
logs=()
eliminated=()
interrupted=0
starting_player=0
display_invited=0

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
	rmdir -- "$SESSION"
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
	identity="$(stat -c '%d %i' -- "$SESSION")" || return 1
	read -r device inode <<< "$identity"
	key=$(( (76 << 24) | ((device & 255) << 16) | (inode & 65535) ))
	awk -v key="$key" '$1 == key { occupied = 1 } END { exit occupied }' \
		/proc/sysvipc/shm /proc/sysvipc/sem /proc/sysvipc/msg
}

start_player() {
	local team="$1" number deadline pid log
	number=$((${#pids[@]} + 1))
	check_interrupt
	log="$SESSION/player-$number.log"
	logs+=("$log")
	starting_player=1
	(
		cd -- "$SESSION" || exit 1
		exec env LEMIPC_PLAYERS=4 "$BIN" "$team"
	) >"$log" 2>&1 &
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

finish_match() {
	local deadline=$((SECONDS + 120)) pid status winner failed=0
	while [ -n "$(active_players)" ]; do
		check_interrupt
		show_eliminations
		[ "$SECONDS" -lt "$deadline" ] || fail "Match timed out after 120 seconds."
		sleep 0.2
	done
	check_interrupt
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
	winner="$(grep -hE '^Team [12] wins$' "${logs[@]}" | sort -u)"
	if [ "$failed" = 1 ] || [[ ! $winner =~ ^Team\ [12]\ wins$ ]]; then
		fail "The match did not finish cleanly with one confirmed winner."
	fi
	printf '%s.\n' "$winner"
}

trap cleanup EXIT
trap 'handle_interrupt 130' INT
trap 'handle_interrupt 143' TERM
trap 'handle_interrupt 129' HUP

check_session_key || fail "Could not confirm an unused IPC key for $SESSION."
start_player 1
session_ids="$(cd -- "$SESSION" && "$PROBE")" || fail "Could not inspect the new session."
read -r _ _ _ creator <<< "$session_ids"
[ "$creator" = "${pids[0]}" ] || fail "The joined session was created by another process."

printf '\nIn the left terminal, run this command:\n'
printf '    (cd %q && %q 0)\n\n' "$SESSION" "$BIN"
display_invited=1
printf 'Press Enter when the board is visible to start the 2 vs 2 match.\n'
if ! IFS= read -r; then
	check_interrupt
	fail "Input closed before the match started."
fi
check_interrupt
if ! grep -qx "${pids[0]}" <<< "$(active_players)" \
	|| [ "$(cd -- "$SESSION" && "$PROBE")" != "$session_ids" ]; then
	fail "The first player or its session is no longer available."
fi

start_player 1
start_player 2
start_player 2
printf 'All four players have joined. The match has started.\n'
finish_match
