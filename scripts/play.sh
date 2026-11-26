#!/usr/bin/env bash
# Starts one lemipc process per team argument, then shows the board, telling
# the viewer what happens at each step.
# Usage: scripts/play.sh [team ...]        (default: 1 1 2 2)
# Ctrl+C asks every player to leave; the last one removes the IPC objects.

cd "$(dirname "$0")/.." || exit 1	# one directory = one game (ftok ".")
BIN=./lemipc
LOGS=logs
teams=("$@")
[ "${#teams[@]}" -gt 0 ] || teams=(1 1 2 2)

# Range checks belong to ./lemipc (parse_team); a rejected team is caught
# after launch. Only 0 is refused here: it opens the display, not a player.
for team in "${teams[@]}"; do
	if [[ "$team" =~ ^0+$ ]]; then
		echo "play: 0 opens the display, it is not a team" >&2
		exit 1
	fi
done
if [ "${#teams[@]}" -lt 2 ]; then
	echo "play: a match needs at least 2 players" >&2
	exit 1
fi
if [ ! -x "$BIN" ]; then
	echo "play: $BIN not found, run make first" >&2
	exit 1
fi

step() { printf '\n[%s] %s\n' "$1" "$2"; }

# The board redraws the whole screen, so let the viewer read first.
pause() {
	if [ -t 0 ]; then
		printf '\n    Press Enter to %s... ' "$1"
		read -r _
	fi
}

mkdir -p "$LOGS" && rm -f "$LOGS"/player-*.log
export LEMIPC_PLAYERS="${#teams[@]}"
pids=()

stop_players() {
	trap - INT TERM
	kill -INT "${pids[@]}" 2>/dev/null
	wait "${pids[@]}" 2>/dev/null
}
trap 'stop_players; exit 130' INT TERM

step 1 "Before the game"
./scripts/ipcs.sh | sed 's/^/    /'

step 2 "Launching ${#teams[@]} players (teams: ${teams[*]})"
echo "    Each player is its own ./lemipc process; nothing forks."
echo "    LEMIPC_PLAYERS=${#teams[@]}: the match starts once everyone has joined."
# Logs are named by launch order only: the team string is whatever the user
# typed, and ./lemipc accepts ids far longer than a file name may be.
log_of() {
	printf '%s/player-%d.log' "$LOGS" "$(($1 + 1))"
}

for index in "${!teams[@]}"; do
	log="$(log_of "$index")"
	"$BIN" "${teams[$index]}" >"$log" 2>&1 &
	pids+=("$!")
	echo "    pid $! -> ./lemipc '${teams[$index]}'   (output: $log)"
done

# Wait until every player has joined or ./lemipc has rejected one. A missing
# player would leave the others waiting forever for the roster, so stop them.
# 400 players take about 30s to join, so allow 5s plus 0.1s per player.
rejected=()
joined=0
deadline=$((SECONDS + 5 + ${#teams[@]} / 10))
while [ "$SECONDS" -lt "$deadline" ]; do
	joined=0
	rejected=()
	for index in "${!teams[@]}"; do
		log="$(log_of "$index")"
		if grep -qs '^Usage: ' "$log"; then
			rejected+=("$index")
		elif grep -qs ' joined team ' "$log"; then
			joined=$((joined + 1))
		fi
	done
	[ "${#rejected[@]}" -eq 0 ] && [ "$joined" -lt "${#teams[@]}" ] || break
	sleep 0.1
done
if [ "${#rejected[@]}" -gt 0 ]; then
	for index in "${rejected[@]}"; do
		echo "play: ./lemipc rejected team '${teams[$index]}':" >&2
		sed 's/^/    /' "$(log_of "$index")" >&2
	done
fi
if [ "${#rejected[@]}" -gt 0 ] || [ "$joined" -lt "${#teams[@]}" ]; then
	[ "${#rejected[@]}" -gt 0 ] \
		|| echo "play: only $joined of ${#teams[@]} players joined in time" >&2
	echo "play: asking the other players to leave" >&2
	stop_players
	./scripts/ipcs.sh | sed 's/^/    /'
	exit 1
fi

step 3 "The first player created the shared resources"
./scripts/ipcs.sh | sed 's/^/    /'

step 4 "Showing the board with ./lemipc 0"
echo "    The display is a read-only client: it never creates or changes the"
echo "    game, and copies the board under the semaphore. Digits are teams,"
echo "    '.' is empty. A player surrounded by 2 of one enemy team leaves."
echo "    Ctrl+C asks every player to leave the board."
pause "show the board"
"$BIN" 0
wait "${pids[@]}"

step 5 "Every player has left"
echo "    Results from $LOGS/ (after Ctrl+C, the last team on the board"
echo "    still counts as the winner):"
grep -h -E 'wins|eliminated' "$LOGS"/player-*.log | sort | uniq -c | sed 's/^/    /'

step 6 "After the game: the last process removed every IPC object"
./scripts/ipcs.sh | sed 's/^/    /'
