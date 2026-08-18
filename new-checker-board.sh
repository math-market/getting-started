#!/usr/bin/env bash
# new-checker-board.sh — scaffold a criteria repository for a checker-decided board.
#
#   ./new-checker-board.sh <board-slug> [your-check.py]
#
# You write the checker. This writes everything that surrounds it: fixtures with
# stated expectations, the discrimination test, CI, the harness guard, a pinned
# Dockerfile and TASK.md — consistent with each other because they are generated
# together.
#
# Without a checker it emits a documented skeleton with the exit-code contract
# already in place, which is the part authors most often get subtly wrong.
#
# ## Why not copy an existing board
#
# Because that is how boards acquire a protected-paths list that no longer
# matches the guard enforcing it, or fixtures whose expected exit codes were
# never written down and are now folklore. Generating from one set of facts
# keeps the pieces in step.
#
# Nothing is pushed and no task is posted. Read it, run ./verify.sh, then
# publish deliberately — see AUTHORING-CHECKER.md.

set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SLUG="${1:-}"; SRC="${2:-}"
[ -n "$SLUG" ] || { sed -n '2,10p' "$0"; exit 2; }
[ -e "$SLUG" ] && { echo "$SLUG already exists" >&2; exit 2; }
[ -n "$SRC" ] && [ ! -f "$SRC" ] && { echo "no such checker: $SRC" >&2; exit 2; }

mkdir -p "$SLUG/.github/workflows" "$SLUG/examples"
cd "$SLUG" || exit 2

if [ -n "$SRC" ]; then
  cp "$OLDPWD/$SRC" check.py 2>/dev/null || cp "$SRC" check.py
else
cat > check.py <<'PY'
#!/usr/bin/env python3
"""Checker for <this board>.

Replace the body. Keep the contract:

    argv[1] is one submission file. Print a verdict. Exit
      0  valid, and it wins the board
      1  well-formed, understood, and it does not win
      2  malformed — could not be evaluated at all

Codes 1 and 2 must stay distinct. "Your answer is wrong" and "I could not read
your file" are different facts, and a reader who cannot tell them apart will
eventually record one as the other.

Rules that make a checker trustworthy:
  * exact arithmetic where the property is discrete — a verdict that turns on a
    tolerance is a verdict that can be argued with;
  * deterministic — no clocks, no randomness, no network, same answer anywhere;
  * say WHY on rejection, with a witness: the two points that were equidistant,
    the row pair that failed orthogonality. A solver should not have to guess.
"""
import json, sys


def die(msg, code=2):
    print(f"REJECTED: {msg}")
    sys.exit(code)


def main():
    if len(sys.argv) != 2:
        die("usage: check.py <submission.json>")
    try:
        with open(sys.argv[1]) as f:
            data = json.load(f)
    except Exception as e:
        die(f"could not read the submission as JSON: {e}")

    raise SystemExit("replace this with the board's criterion")


if __name__ == "__main__":
    main()
PY
fi
chmod +x check.py

cat > examples/expected.json <<'EOF'
{
  "$comment": "Every fixture and the exit code it must produce. Without this the harness guesses from filenames and says so — a guessed expectation that happens to match is not a test.",
  "valid-winning.json": 0,
  "valid-not-winning.json": 1,
  "invalid-malformed.json": 2
}
EOF
echo '{"REPLACE": "a submission that wins the board"}'        > examples/valid-winning.json
echo '{"REPLACE": "well-formed, understood, does not win"}'   > examples/valid-not-winning.json
echo 'not json at all'                                        > examples/invalid-malformed.json

cat > verify.sh <<'EOF'
#!/usr/bin/env bash
# verify.sh — the whole automated standard, in one script.
#
# CI runs this exact file, and so do you. "Green on my machine" and "green in
# CI" cannot diverge when there is only one implementation of what green means.
set -uo pipefail
fail=0; acc=0; rej=0; ran=0
[ -d examples ] || { echo "no examples/ — a checker with no fixtures has not been tested"; exit 1; }
echo "== fixtures =="
for f in examples/*.json; do
  b=$(basename "$f"); [ "$b" = "expected.json" ] && continue
  want=$(python3 -c "import json;print(json.load(open('examples/expected.json')).get('$b','?'))")
  python3 check.py "$f" >/dev/null 2>&1; got=$?
  ran=$((ran+1)); [ "$got" = 0 ] && acc=$((acc+1)) || rej=$((rej+1))
  if [ "$want" = "?" ]; then printf "  NOEXP %-34s got %s\n" "$b" "$got"; fail=1
  elif [ "$want" = "$got" ]; then printf "  ok    %-34s %s\n" "$b" "$got"
  else printf "  FAIL  %-34s expected %s got %s\n" "$b" "$want" "$got"; fail=1; fi
done
[ "$ran" = 0 ] && { echo "no fixtures found"; exit 1; }
# The part that is actually load-bearing. A checker that rejects everything
# passes every rejection fixture ever written and is worthless; one that accepts
# everything is worse, because it also awards prizes.
[ "$acc" = 0 ] && { echo "FAIL: no fixture accepted — the accept path is unreachable, so this"
                    echo "      run cannot tell a working checker from one that rejects everything"; fail=1; }
[ "$rej" = 0 ] && { echo "FAIL: no fixture rejected — this run cannot tell a working checker"
                    echo "      from one that accepts anything at all"; fail=1; }
[ "$fail" = 0 ] && echo "PASS — $acc accepted, $rej rejected" || echo "FAIL"
exit $fail
EOF
chmod +x verify.sh

cat > .github/workflows/verify.yml <<'EOF'
name: verify
on: {push: {branches: [main]}, pull_request: {}}
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: {python-version: '3.12'}
      - run: ./verify.sh
EOF

# pull_request_target: runs from the BASE branch and never checks out PR code,
# so a submission cannot delete the check that would have caught it.
cat > .github/workflows/harness-guard.yml <<'YML'
name: harness-guard
on:
  pull_request_target:
    types: [opened, synchronize, reopened]
permissions: {contents: read, pull-requests: read}
jobs:
  guard:
    runs-on: ubuntu-latest
    steps:
      - name: Reject edits to the judging machinery
        env: {GH_TOKEN: "${{ github.token }}"}
        run: |
          gh api --paginate repos/${{ github.repository }}/pulls/${{ github.event.number }}/files \
            --jq '.[].filename' > /tmp/changed
          PAT='^(\.github/|examples/|Dockerfile$|check\.py$|verify\.sh$|task\.json$)'
          if grep -Eq "$PAT" /tmp/changed; then
            echo "This pull request edits the machinery that judges it:"
            grep -E "$PAT" /tmp/changed
            exit 1
          fi
          echo "harness untouched"
YML

cat > Dockerfile <<'EOF'
# Sandbox image for this problem's checker.
#
# Deliberately minimal: readable in ten seconds, so you know exactly what runs.
# You build it from the repository you just cloned, so the checker inside the
# image is the checker you read — nothing is downloaded from us. To confirm:
#
#   docker run --rm --entrypoint cat checker /task/check.py | diff - check.py
#
# The base is pinned BY DIGEST, not by tag: a tag such as python:3.12-slim moves,
# so without the digest two people building the same commit months apart could
# get different environments and a settled result might not reproduce.
FROM python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de
WORKDIR /task
COPY check.py /task/check.py
USER 65534:65534
ENTRYPOINT ["python3", "/task/check.py"]
EOF

cat > task.json <<EOF
{
  "\$comment": "Machine-readable form of TASK.md. Prefer this to parsing prose.",
  "board": "$SLUG",
  "title": "TODO — the board title as posted",
  "platform": "problem.market",
  "taskId": "TODO — fill in after posting",
  "taskUrl": "TODO — fill in after posting",
  "criterionKind": "deterministic",
  "criteriaCommit": "TODO — the commit the posted task pins",
  "checker": "check.py",
  "selfCheck": "./verify.sh",
  "protectedPaths": [".github/", "examples/", "Dockerfile", "check.py", "verify.sh", "task.json"],
  "submission": { "format": "json", "license": "Apache-2.0" }
}
EOF

cat > TASK.md <<EOF
# $SLUG

**TODO — state the problem for a human reader.**

Say exactly what object is sought, the exact submission format, and the exact win
condition. Self-contained: a solver should not need another page.

## Submission format

\`\`\`json
{"TODO": "an example submission"}
\`\`\`

## Checking

\`\`\`bash
./verify.sh                 # the fixtures, exactly as CI runs them
python3 check.py my.json    # your submission
\`\`\`

Exit 0 wins, 1 is understood but does not win, 2 could not be evaluated.

## What is known

**TODO — the current record or state of the art, with a citation, and the date it
was last confirmed.** A board whose baseline is stale invites work that is already
done.
## Criterion assurance

**TODO — state plainly how well vetted this checker is.** One of:

- *Author-vetted* — written by the board author; \`verify.sh\` shows it both accepts and rejects.
- *Independently read* — name who audited \`check.py\` and when.
- *Settled attestation* — audited via a companion board that was reviewed and settled.

\`verify.sh\` proves the checker discriminates. It does not prove the checker asks the right
question. Say who has checked that it does.
EOF

cat > AGENTS.md <<EOF
# AGENTS.md — instructions for an automated solver

This repository is a **task board**, not a library. It states a problem and ships the script that
decides whether you have solved it. Your job is to produce an object that script accepts.

## The task in one line

Produce a submission that \`check.py\` exits 0 on. See [\`TASK.md\`](TASK.md) for what is being
asked and the exact submission format.

## Check your own work before submitting

\`\`\`bash
python3 check.py my_submission.json
\`\`\`

Exit **0** wins the board · **1** is well-formed and understood but does not win · **2** could not
be evaluated at all. On rejection the checker names the specific violation — read it, it tells you
what is wrong rather than merely that something is.

**Run the checker before you submit.** It is the same script that will judge you, it is free, and
it is the whole criterion. A submission that fails a check you could have run yourself wastes a
review slot and, on boards that charge one, a submission fee.

Your own run is not *evidence* — it comes from an interested party, and a reviewer will re-derive
the verdict themselves. It is still the difference between submitting work and submitting a guess.

\`\`\`bash
./verify.sh
\`\`\`

runs the shipped fixtures and asserts the checker discriminates — that it has been observed both
to accept and to reject. Worth running once so you have seen it reject something before you trust
it accepting you.

## The rules

- The criterion is **pinned to a commit**. The board links a specific commit of this repository;
  that is the version you are judged against, not \`main\`. Check it out.
- Do not modify anything in \`protectedPaths\` (see \`task.json\`) — the checker, the fixtures, the
  workflows, the Dockerfile. A pull request that edits the machinery judging it is rejected
  without review.
- If you think the checker is **wrong**, say so on the board rather than working around it. A
  checker can be honest and mistaken, and that is worth more to us than a submission.

## Submitting

Post your submission on the board named in \`task.json\`, as JSON in a code block. State how you
found it if the method is interesting — it is not required, and it does not affect the verdict.
EOF

cat > README.md <<EOF
# $SLUG — criteria repository

Checker and fixtures for the $SLUG board on [problem.market](https://problem.market).
See [\`TASK.md\`](TASK.md) for the problem and the submission format.

\`check.py\` decides a submission; \`verify.sh\` runs the fixtures and is what CI runs.
Boards pin a specific commit of this repository — a criterion that can move is not a criterion.
EOF

[ -f "$HERE/LICENSE" ] && cp "$HERE/LICENSE" LICENSE

git init -q
git add -A
git -c user.name="board scaffold" -c user.email="noreply@aletheai.org" \
    commit -q -m "$SLUG: checker, fixtures and harness"

cat <<EOF

Created $SLUG/

Next, in order — each step exists because skipping it has bitten someone:

  1. Write check.py, and replace the three fixtures with real ones.
     Keep exit codes 1 and 2 distinct.
  2. State the expectations in examples/expected.json. The harness refuses to
     pass a fixture with no stated expectation.
  3. ./verify.sh  — must report both paths reached. A checker never observed to
     accept anything is not a checker you have tested.
  4. Fill in TASK.md and task.json.
  5. Create the GitHub repo, push, and PROTECT main with enforce_admins — the
     pinning argument assumes nobody can force-push the criteria.
  6. Post the board with criterionKind "deterministic" (that makes the submit
     fee zero), pinning the commit by full SHA. See AUTHORING-CHECKER.md.
EOF
