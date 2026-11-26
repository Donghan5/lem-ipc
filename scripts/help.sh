#!/usr/bin/env bash
# Prints make help from the Makefile itself, so the text lives next to each
# target and changes with it.
# Usage: scripts/help.sh <makefile> [target]
#   no target: grouped one-line summary (##@ groups, "target: ... ## text")
#   target:    the "#>" block written right above that target's rule

makefile="${1:-Makefile}"
target="${2:-}"

if [ -z "$target" ]; then
	echo "Usage: make [target] [VARIABLE=value]"
	awk -F ':.*## ' '
		/^##@ / { printf "\n%s\n", substr($0, 5) }
		/^[a-z0-9-]+:.*## / { printf "  %-12s %s\n", $1, $2 }
	' "$makefile"
	echo
	echo "Details: make help T=<target>   (e.g. make help T=demo)"
	echo "By hand: LEMIPC_PLAYERS=4 ./lemipc <team>    board: ./lemipc 0"
	exit 0
fi

# Collect consecutive "#>" lines; print them when the next rule is <target>.
awk -v target="$target" '
	/^#>/ { block = block substr($0, (length($0) > 2 && substr($0, 3, 1) == " ") ? 4 : 3) "\n"; next }
	{
		split($0, rule, ":")
		if (rule[1] == target && $0 ~ /^[a-z0-9-]+:/) {
			found = 1
			if (block == "")
				exit 2
			printf "%s", block
			exit 0
		}
		block = ""
	}
	END { if (!found) exit 3 }
' "$makefile"
status=$?
case "$status" in
	0) ;;
	2) awk -F ':.*## ' -v t="$target" '$1 == t { print "make " t ": " $2 }' "$makefile" ;;
	*)
		echo "make help: no target named '$target'." >&2
		echo "Targets:" $(awk -F ':.*## ' '/^[a-z0-9-]+:.*## / { print $1 }' "$makefile") >&2
		exit 1
		;;
esac
