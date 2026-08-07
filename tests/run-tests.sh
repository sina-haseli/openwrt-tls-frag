#!/bin/sh
# Test runner. Usage: run-tests.sh [unit|integration]
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUITE=${1:-unit}
DIR="$ROOT/tests/$SUITE"

[ -d "$DIR" ] || { echo "no such suite: $SUITE"; exit 1; }

RC=0
for t in "$DIR"/test_*.sh; do
	[ -f "$t" ] || continue
	printf '\n== %s\n' "$(basename "$t")"
	if ! ROOT="$ROOT" sh "$t"; then
		RC=1
	fi
done

printf '\n'
if [ "$RC" -eq 0 ]; then
	echo "ALL SUITES PASSED"
else
	echo "SUITE FAILURES"
fi
exit "$RC"
