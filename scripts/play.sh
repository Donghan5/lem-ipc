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

for team in "${teams[@]}"; do
	if ! [[ "$team" =~ ^[1-9][0-9]{0,8}$ ]]; then
		echo "play: teams are positive numbers, got '$team'" >&2
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
for index in "${!teams[@]}"; do
	log="$LOGS/player-$((index + 1))-team-${teams[$index]}.log"
	"$BIN" "${teams[$index]}" >"$log" 2>&1 &
	pids+=("$!")
	echo "    pid $! -> ./lemipc ${teams[$index]}   (output: $log)"
done

# The display never creates the session, so let a player create it first.
for _ in $(seq 50); do
	grep -qs ' joined team ' "$LOGS"/player-*.log && break
	sleep 0.1
done

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
