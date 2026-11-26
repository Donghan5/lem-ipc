#!/usr/bin/env bash
# Read only: lists the System V IPC objects this user owns, the way an
# evaluator checks with ipcs, and says what each one is for in lemipc.
# It never removes anything.

user="$(id -un)"
total=0
keys=()

for kind in m s q; do
	case "$kind" in
		m) name="Shared memory   " role="the board: map, players, team counts, phase" ;;
		s) name="Semaphore arrays" role="one semaphore (value 1): only one player touches the board at a time" ;;
		q) name="Message queues  " role="teammates share their target; mtype = team number" ;;
	esac
	listing="$(LC_ALL=C ipcs "-$kind")"
	rows="$(awk -v user="$user" '$3 == user' <<< "$listing")"
	count="$(grep -c . <<< "$rows")"
	total=$((total + count))
	echo "$name: $count  ($role)"
	if [ "$count" -gt 0 ]; then
		awk '$1 == "key"' <<< "$listing" | sed 's/^/    /'
		sed 's/^/    /' <<< "$rows"
		while read -r key _; do keys+=("$key"); done <<< "$rows"
	fi
done

if [ "$total" -eq 0 ]; then
	echo "-- $user owns 0 IPC objects: nothing is left behind."
	exit 0
fi
echo "-- $user owns $total IPC object(s)."
if [ "$total" -eq 3 ] && [ "$(printf '%s\n' "${keys[@]}" | sort -u | wc -l)" -eq 1 ]; then
	echo "   One game: all three share key ${keys[0]} = ftok(\".\"), so every player"
	echo "   started in the same directory joins it, and leftovers can be found again."
fi
echo "   The last process to leave removes them. After kill -9 of every player,"
echo "   the next ./lemipc started in the same directory reclaims them."
