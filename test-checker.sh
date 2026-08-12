#!/usr/bin/env bash
# test-checker.sh — does this checker actually discriminate?
#
#   ./test-checker.sh <problem-repo-dir> [--commit <sha>] [--no-sandbox]
#
# A checker that rejects everything passes every "this must be rejected" test
# ever written, and is worthless. A checker that accepts everything is worse:
# it is worthless *and* it awards prizes. Neither is caught by running the
# checker once and seeing a sensible answer, which is what an author naturally
# does.
#
# So this runs every fixture in examples/ through the canonical sandbox and
# asserts three things:
#
#   1. each fixture gets the exit code it is supposed to get;
#   2. at least one fixture is ACCEPTED  — the accept path exists and is reachable;
#   3. at least one fixture is REJECTED  — the reject path exists and is reachable.
#
# (2) and (3) are the ones that matter. A board whose checker has never been
# observed to do both has not been tested, however many fixtures it has.
#
# Expected exit codes come from examples/expected.json:
#
#   {"valid-winning.json": 0, "valid-not-winning.json": 1, "invalid-loop.json": 2}
#
#   0 = accepted (wins the board) · 1 = valid but does not win · 2 = unreadable
#
# Without that file the codes are GUESSED from filenames, and it says so loudly
# — a guessed expectation that happens to match is not a test.

set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$HERE/run-checker.sh"

REPO=""; PASSTHRU=()
while [ $# -gt 0 ]; do
  case "$1" in
    --commit|--sha256|--pip|--base) PASSTHRU+=("$1" "$2"); shift 2 ;;
    --no-sandbox) PASSTHRU+=("$1"); shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) REPO="$1"; shift ;;
  esac
done
[ -n "$REPO" ] || { echo "usage: test-checker.sh <problem-repo-dir>" >&2; exit 2; }
REPO=$(cd "$REPO" && pwd) || exit 2
CHECK="$REPO/check.py"
[ -f "$CHECK" ] || { echo "no check.py in $REPO" >&2; exit 2; }
EX="$REPO/examples"
[ -d "$EX" ] || { echo "no examples/ directory in $REPO — nothing to test against." >&2
                  echo "A checker with no fixtures has not been tested." >&2; exit 2; }
[ -x "$RUNNER" ] || { echo "cannot find the canonical runner at $RUNNER" >&2; exit 2; }

MANIFEST="$EX/expected.json"
GUESSING=0
if [ ! -f "$MANIFEST" ]; then
  GUESSING=1
  echo "WARNING: no examples/expected.json — expected exit codes are being GUESSED"
  echo "         from filenames. Write the manifest; a guess that happens to match"
  echo "         is not a test. See --help."
  echo
fi

expected_for() {   # name -> expected code, or "?" when unknown
  local n="$1"
  if [ "$GUESSING" = "0" ]; then
    python3 -c "
import json,sys
d=json.load(open('$MANIFEST'))
print(d.get('$n','?'))" 2>/dev/null || echo "?"
  else
    case "$n" in
      *invalid*|*bad*|*malformed*) echo 2 ;;
      *not-winning*|*notwinning*)  echo 1 ;;
      *valid*|*win*|*accept*)      echo 0 ;;
      *)                           echo "?" ;;
    esac
  fi
}

pass=0; fail=0; unknown=0; accepted=0; rejected=0; ran=0
printf "%-34s %-8s %-8s %s\n" "fixture" "expected" "actual" "result"
printf "%-34s %-8s %-8s %s\n" "------" "--------" "------" "------"

for f in "$EX"/*; do
  base=$(basename "$f")
  [ "$base" = "expected.json" ] && continue
  [ -f "$f" ] || continue
  want=$(expected_for "$base")
  out=$("$RUNNER" "$CHECK" "$f" "${PASSTHRU[@]+"${PASSTHRU[@]}"}" 2>&1)
  got=$?
  ran=$((ran+1))

  # 3 and 4 are the runner's own codes, not verdicts. Judged by exit code, not
  # by matching text: the first version of this grepped for "provenance" and hit
  # the word inside a *warning*, so every run was misreported as a failure.
  if [ "$got" = "3" ] || [ "$got" = "4" ]; then
    printf "%-34s %-8s %-8s %s\n" "$base" "$want" "$got" \
      "$([ "$got" = 3 ] && echo "PROVENANCE FAILED" || echo "COULD NOT RUN")"
    echo "    $(echo "$out" | grep -v "^ " | head -1)"
    fail=$((fail+1)); continue
  fi

  case "$got" in
    0) accepted=$((accepted+1)) ;;
    *) rejected=$((rejected+1)) ;;
  esac

  if [ "$want" = "?" ]; then
    printf "%-34s %-8s %-8s %s\n" "$base" "?" "$got" "NO EXPECTATION"
    unknown=$((unknown+1))
  elif [ "$want" = "$got" ]; then
    printf "%-34s %-8s %-8s %s\n" "$base" "$want" "$got" "ok"
    pass=$((pass+1))
  else
    printf "%-34s %-8s %-8s %s\n" "$base" "$want" "$got" "MISMATCH"
    echo "    $(echo "$out" | tail -2 | tr '\n' ' ')"
    fail=$((fail+1))
  fi
done

echo
[ "$ran" = "0" ] && { echo "no fixtures found in $EX" >&2; exit 2; }

# The part that is actually load-bearing.
verdict=0
if [ "$accepted" = "0" ]; then
  # On a record board you CANNOT ship a winning fixture: a submission that beats
  # the baseline is the answer to the board, and publishing it settles it. So the
  # accept path has to be demonstrated another way — a unit test that reaches the
  # branch with the threshold lowered. That is a legitimate substitute; having
  # neither is not.
  if [ -f "$REPO/tests/test_accept.py" ]; then
    if (cd "$REPO" && python3 tests/test_accept.py >/dev/null 2>&1); then
      echo "No fixture wins the board — correct for a record board, since a winning"
      echo "example would BE the record. The accept path is instead demonstrated by"
      echo "tests/test_accept.py, which passes."
      accepted=1
    else
      echo "FAIL: no fixture was accepted AND tests/test_accept.py does not pass."
      echo "      Nothing here shows the checker can accept anything."
      verdict=1
    fi
  else
    echo "FAIL: no fixture was ACCEPTED and there is no tests/test_accept.py."
    echo "      Every fixture was rejected, so this run cannot distinguish a working"
    echo "      checker from one that rejects everything. Either ship a fixture that"
    echo "      wins, or — on a record board, where a winning fixture would give away"
    echo "      the record — add tests/test_accept.py reaching the branch directly."
    verdict=1
  fi
fi
if [ "$rejected" = "0" ]; then
  echo "FAIL: no fixture was REJECTED. Every fixture was accepted, so this run"
  echo "      cannot distinguish a working checker from one that accepts"
  echo "      everything — including submissions that prove nothing."
  verdict=1
fi
if [ "$verdict" = "0" ]; then
  echo "Both paths reached: $accepted accepted, $rejected rejected."
fi

[ "$fail" != "0" ] && { echo "$fail fixture(s) did not do what was expected."; verdict=1; }
[ "$unknown" != "0" ] && echo "$unknown fixture(s) had no stated expectation and were not checked."
[ "$GUESSING" = "1" ] && echo "Expectations were guessed from filenames — write examples/expected.json."

exit $verdict
