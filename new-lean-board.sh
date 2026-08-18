#!/usr/bin/env bash
# new-lean-board.sh — scaffold a Lean criteria repository for a new board.
#
#   ./new-lean-board.sh <board-slug> <StatementFile.lean>
#   ./new-lean-board.sh --repin <board-dir>      after correcting a statement
#
# You write the theorem. This writes everything that judges it: the statement
# lock, the CI, the harness guard, the reviewer script and task.json — all
# consistent with each other, because they are generated together from one set
# of facts rather than copied from another board and edited.
#
# Copying an existing board is the obvious approach and it is how boards get
# subtly wrong: a stale criteria SHA, a protectedPaths list that no longer
# matches the guard, a statement file named in three places and renamed in two.
#
# ## The part that is not obvious
#
# `check-statement.sh` compares a submission against the statement **at a pinned
# commit**. That commit cannot be known while you are writing the file that goes
# into it. So this script commits twice:
#
#   1. everything, with the criteria SHA left as a placeholder;
#   2. the same tree with the SHA of commit (1) filled in.
#
# Pinning commit (1) is correct: the statement file is byte-identical in both,
# and `check-statement.sh` reads only the statement out of the pinned commit.
# Getting this backwards — pinning the second commit, or pinning `main` — is the
# single most common way to publish a board whose standard can still move.
#
# Nothing is pushed and no task is posted. Read the result, run ./verify.sh, and
# publish deliberately.

set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --repin <dir> exists because fixing a statement after a failed build is the
# NORMAL case, not an exception: the scaffold pins at creation, so any later edit
# to the statement leaves the pin aimed at a version that no longer exists. A
# board pinned to a statement that does not compile is unsolvable, because the
# statement is the one thing a submitter may not touch.
if [ "${1:-}" = "--repin" ]; then
  D="${2:?usage: new-lean-board.sh --repin <board-dir>}"
  cd "$D" || exit 2
  git diff --quiet && git diff --cached --quiet || {
    echo "uncommitted changes in $D — commit the corrected statement first" >&2; exit 2; }
  SHA=$(git rev-parse HEAD)
  spec=$(python3 -c "import json;print(json.load(open('task.json'))['statementFile'])")
  python3 - "$SHA" <<'PYP'
import sys, re, json
sha = sys.argv[1]
s = open("check-statement.sh").read()
open("check-statement.sh","w").write(re.sub(r'^CRITERIA=.*$', f'CRITERIA="{sha}"', s, flags=re.M))
d = json.load(open("task.json")); d["criteriaCommit"] = sha
json.dump(d, open("task.json","w"), indent=2)
PYP
  git add -A
  git -c user.name="board scaffold" -c user.email="noreply@aletheai.org" \
      commit -q -m "re-pin criteria commit ${SHA:0:12}"
  echo "re-pinned $spec to $SHA"
  ./check-statement.sh
  exit $?
fi

SLUG="${1:-}"; SPEC="${2:-}"
[ -n "$SLUG" ] && [ -n "$SPEC" ] || { sed -n '2,12p' "$0"; exit 2; }
[ -f "$SPEC" ] || { echo "no such statement file: $SPEC" >&2; exit 2; }
case "$SPEC" in *.lean) ;; *) echo "the statement file must be a .lean file" >&2; exit 2 ;; esac

SPECBASE=$(basename "$SPEC")
DEST="$SLUG"
[ -e "$DEST" ] && { echo "$DEST already exists" >&2; exit 2; }

# The theorem name is read out of the file rather than asked for, so task.json
# cannot disagree with the Lean source about what is being proved.
THM=$(grep -oE '^ *(theorem|lemma) +[A-Za-z_][A-Za-z0-9_.'"'"']*' "$SPEC" | head -1 | awk '{print $2}')
NS=$(grep -oE '^namespace +[A-Za-z_][A-Za-z0-9_.]*' "$SPEC" | head -1 | awk '{print $2}')
[ -n "$THM" ] || { echo "could not find a theorem in $SPEC" >&2; exit 2; }
FULL="${NS:+$NS.}$THM"

grep -q "sorry" "$SPEC" || {
  echo "WARNING: $SPECBASE contains no 'sorry'." >&2
  echo "         A board is a statement with its proof missing. If the proof is" >&2
  echo "         already there, there is nothing to solve." >&2; }

TOOLCHAIN=$(cat lean-toolchain 2>/dev/null || echo "leanprover/lean4:v4.33.0-rc1")
MATHLIB_REV="${TOOLCHAIN##*:}"

mkdir -p "$DEST/.github/workflows"
cp "$SPEC" "$DEST/$SPECBASE"
cp "$HERE/preflight.sh" "$DEST/preflight.sh" 2>/dev/null || true
[ -f "$HERE/LICENSE" ] && cp "$HERE/LICENSE" "$DEST/LICENSE"

echo "$TOOLCHAIN" > "$DEST/lean-toolchain"
cat > "$DEST/lakefile.toml" <<EOF
name = "$SLUG"
defaultTargets = ["${SPECBASE%.lean}"]

[[require]]
name = "mathlib"
scope = "leanprover-community"
rev = "$MATHLIB_REV"

[[lean_lib]]
name = "${SPECBASE%.lean}"
EOF

cat > "$DEST/.gitignore" <<'EOF'
.lake/
axiom-report.txt
EOF

# ---------------------------------------------------------------- statement lock
sed -e "s|@SPEC@|$SPECBASE|g" -e "s|@SLUG@|$SLUG|g" > "$DEST/check-statement.sh" <<'CHK'
#!/usr/bin/env bash
# check-statement.sh — is this a proof of the theorem we actually posted?
#
# A green build and a clean axiom report only establish that the submitter
# proved *something* honestly. They say nothing about whether it is *our*
# theorem: adding a hypothesis that makes the statement trivially true passes
# every other check we run. This is the check that catches that, and it is the
# reason the others can be trusted.
#
# Compares the locked region of the statement file — everything from the top of
# the file down to and including the `:= by` that opens the proof, so imports,
# namespace, opens, variables and the theorem signature — against the criteria
# commit pinned by the posted task. Comments and blank lines are ignored; a
# submitter may annotate freely, but the code may not move.
#
#   Usage:  ./check-statement.sh [git-ref]     (default: the working tree)

set -uo pipefail

SPEC="@SPEC@"
CRITERIA="__CRITERIA_COMMIT__"
REF="${1:-}"

spec_of() {
python3 -c '
import sys, re
src = sys.stdin.read()
src = re.sub(r"/-.*?-/", "", src, flags=re.S)   # block comments
src = re.sub(r"--[^\n]*", "", src)              # line comments
out = []
for line in src.split("\n"):
    line = line.rstrip()
    if not line.strip():
        continue
    out.append(line)
    if line.endswith(":= by"):
        break
print("\n".join(out))
'
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# The criteria commit may be absent in a shallow CI checkout; fetch on demand.
git cat-file -e "$CRITERIA^{commit}" 2>/dev/null || git fetch -q --depth=1 origin "$CRITERIA" 2>/dev/null

if ! git show "$CRITERIA:$SPEC" 2>/dev/null | spec_of > "$tmp/locked"; then
  echo "check-statement: could not read $SPEC at criteria commit $CRITERIA" >&2
  echo "  This check compares your statement against the commit the posted task" >&2
  echo "  pins, so it needs that commit present locally. It is missing." >&2
  echo "  Usual cause: a shallow clone, a tarball, or an export rather than a" >&2
  echo "  full clone. Re-clone the repository in full." >&2
  exit 2
fi
[ -s "$tmp/locked" ] || { echo "check-statement: locked statement came back empty" >&2; exit 2; }

if [ -n "$REF" ]; then
  git show "$REF:$SPEC" | spec_of > "$tmp/actual"
else
  spec_of < "$SPEC" > "$tmp/actual"
fi

if diff -q "$tmp/locked" "$tmp/actual" >/dev/null 2>&1; then
  echo "check-statement: OK — statement identical to criteria commit ${CRITERIA:0:7}"
  exit 0
fi

echo "check-statement: FAILED — the statement is not the one that was posted." >&2
echo "  (< locked at ${CRITERIA:0:7}   > as submitted)" >&2
diff "$tmp/locked" "$tmp/actual" | sed 's/^/  /' >&2
exit 1
CHK

# ---------------------------------------------------------------- verify
sed -e "s|@THM@|$FULL|g" -e "s|@LIB@|${SPECBASE%.lean}|g" > "$DEST/verify.sh" <<'VER'
#!/usr/bin/env bash
# verify.sh — the whole automated standard, in one script.
#
# CI runs this exact file, and so do you. "Green on my machine" and "green in
# CI" cannot diverge when there is only one implementation of what green means.
#
# Exit 0 means the mechanical half of review will pass. It does NOT mean the
# statement says what the board claims it says — see AGENTS.md.

set -uo pipefail
fail=0

echo "== statement =="
./check-statement.sh || fail=1

echo "== build =="
lake exe cache get >/dev/null 2>&1 || echo "  (cache unavailable; building from source will be slow)"
lake build || { echo "build FAILED"; exit 1; }

echo "== axioms =="
# The axiom report is the real check for sorry/admit/native_decide, not a text
# search: a sorry anywhere beneath the theorem shows up as sorryAx transitively,
# and native_decide shows up as Lean.ofReduceBool. Text search sees neither
# through a helper lemma in another file.
cat > .axiom_check.lean <<'EOF'
import @LIB@
#print axioms @THM@
EOF
lake env lean .axiom_check.lean > axiom-report.txt 2>&1
rm -f .axiom_check.lean
cat axiom-report.txt

if grep -q "sorryAx\|Lean.ofReduceBool" axiom-report.txt; then
  echo "FAILED: the proof depends on sorry or native_decide"; fail=1
elif grep -q "depends on axioms: \[propext, Classical.choice, Quot.sound\]" axiom-report.txt; then
  echo "axioms OK — exactly the three Mathlib itself rests on"
elif grep -q "does not depend on any axioms" axiom-report.txt; then
  echo "axioms OK — none"
else
  # Absence of a recognised report is not evidence of cleanliness.
  echo "FAILED: could not read a clean axiom report. Treat as unverified."; fail=1
fi

[ "$fail" = 0 ] && echo "PASS" || echo "FAIL"
exit $fail
VER

# ---------------------------------------------------------------- CI
cat > "$DEST/.github/workflows/verify.yml" <<'EOF'
name: verify
on:
  push: {branches: [main]}
  pull_request:
jobs:
  build-and-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: {fetch-depth: 0}   # the statement check needs the criteria commit
      - name: Install elan
        run: |
          curl -sSfL https://elan.lean-lang.org/elan-init.sh | sh -s -- -y --default-toolchain none
          echo "$HOME/.elan/bin" >> $GITHUB_PATH
      - name: Verify
        run: ./verify.sh
      - uses: actions/upload-artifact@v4
        if: always()
        with: {name: axiom-report, path: axiom-report.txt}
EOF

# The guard runs from the BASE branch (pull_request_target) and never checks out
# or executes PR code — otherwise a submission could delete the check that would
# have caught it.
cat > "$DEST/.github/workflows/harness-guard.yml" <<EOF
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
        env: {GH_TOKEN: "\${{ github.token }}"}
        run: |
          gh api --paginate \\
            repos/\${{ github.repository }}/pulls/\${{ github.event.number }}/files \\
            --jq '.[].filename' > /tmp/changed
          if grep -Eq '^(\\.github/|tests/|Dockerfile\$|run-checker\\.sh\$|check-statement\\.sh\$|verify\\.sh\$|review\\.sh\$|preflight\\.sh\$|task\\.json\$|lakefile\\.toml\$|lean-toolchain\$|lake-manifest\\.json\$)' /tmp/changed; then
            echo "This pull request edits the machinery that judges it:"
            grep -E '^(\\.github/|tests/|Dockerfile\$|run-checker\\.sh\$|check-statement\\.sh\$|verify\\.sh\$|review\\.sh\$|preflight\\.sh\$|task\\.json\$|lakefile\\.toml\$|lean-toolchain\$|lake-manifest\\.json\$)' /tmp/changed
            exit 1
          fi
          echo "harness untouched"
EOF

# ---------------------------------------------------------------- task.json
cat > "$DEST/task.json" <<EOF
{
  "\$comment": "Machine-readable form of TASK.md. Prefer this to parsing prose.",

  "board": "$SLUG",
  "title": "TODO — the board title as posted",
  "platform": "problem.market",
  "taskId": "TODO — fill in after posting",
  "taskUrl": "TODO — fill in after posting",
  "tier": "proof",
  "status": "open",

  "criteriaCommit": "__CRITERIA_COMMIT__",
  "\$comment_criteria": "The commit the posted task pins. What counts as a solution was fixed here and cannot move; the statement is compared against this commit, not against main.",

  "prover": "lean4",
  "toolchain": "$TOOLCHAIN",
  "dependencies": [
    { "name": "mathlib", "scope": "leanprover-community", "rev": "$MATHLIB_REV" }
  ],
  "additionalDependenciesAllowed": false,

  "statementFile": "$SPECBASE",
  "theorem": "$FULL",
  "statementLocked": true,

  "winConditions": {
    "statementUnchanged": true,
    "buildsClean": true,
    "allowedAxioms": ["propext", "Classical.choice", "Quot.sound"],
    "forbidden": ["sorry", "admit", "native_decide"]
  },

  "protectedPaths": [
    ".github/", "lakefile.toml", "lean-toolchain", "lake-manifest.json",
    "check-statement.sh", "verify.sh", "review.sh"
  ],

  "preflight": "./preflight.sh",
  "selfCheck": "./verify.sh",
  "setup": ["lake exe cache get", "lake build"],

  "submission": {
    "method": "pull-request",
    "repository": "https://github.com/math-market/$SLUG",
    "license": "Apache-2.0"
  }
}
EOF

cat > "$DEST/AGENTS.md" <<EOF
# AGENTS.md — instructions for an automated solver

This repository is a **task board**, not a library. It contains one theorem with
its proof missing. Your job is to supply the proof.

## The task in one line

Replace the single \`sorry\` in \`$SPECBASE\` with a proof, changing nothing else
about the statement.

## Before you start

Run \`./preflight.sh\`. You need **elan**, **git** and **python3**, and about
**8 GB** of free disk — the Mathlib cache unpacks to roughly 7.4 GB.

## The rules

- The statement is **locked**: everything from the top of the file through the
  \`:= by\` must stay byte-identical to the criteria commit. Adding a hypothesis
  is a different theorem, not a partial solution.
- No \`sorry\`, no \`admit\`, no \`native_decide\`. Enforced through the axiom
  report, which sees these transitively — a helper lemma in another file does
  not hide them.
- Do not touch anything in \`protectedPaths\` (see \`task.json\`). A pull request
  that edits the machinery judging it is rejected without review.

## Checking your work

\`\`\`bash
./verify.sh
\`\`\`

The identical script CI runs. Exit 0 means the mechanical half of review passes.

## Submitting

Fork, close the \`sorry\` on a branch, get \`./verify.sh\` to pass, open a pull
request, and submit the PR URL as your solution on the board.
EOF

cat > "$DEST/TASK.md" <<EOF
# $SLUG

**TODO — state the theorem informally here, for a human reader.**

Say what is being proved, in words, with a reference. This text is what a
reviewer compares the formal statement against when judging *faithfulness* —
whether \`$FULL\` really is the theorem this board claims. That judgement is
not mechanical and is the half a script cannot do, so this section is
load-bearing rather than decorative.

The formal statement is in [\`$SPECBASE\`](./$SPECBASE); the machine-readable
rules are in [\`task.json\`](./task.json); solvers should read
[\`AGENTS.md\`](./AGENTS.md).
## Criterion assurance

**TODO — state plainly how well vetted this statement is.** One of:

- *Author-vetted only* — written by the board author, compiles against the pinned toolchain, no
  independent review. Honest and common; say so.
- *Peer-attested* — a named mathematician has attested it renders the informal theorem.
- *Settled attestation* — attested via a companion board that was itself reviewed and settled.

A locked statement makes a submission fully checkable regardless: a proof here proves *the stated
theorem*. This section tells a reader whether the stated theorem is the intended one, and who is
accountable for that judgement. Do not leave it blank — a board that says nothing implies more
than one that admits to being author-vetted.
EOF

chmod +x "$DEST"/*.sh 2>/dev/null

# ---------------------------------------------------------------- two-phase pin
cd "$DEST" || exit 2
git init -q
git add -A
git -c user.name="board scaffold" -c user.email="noreply@aletheai.org" \
    commit -q -m "$SLUG: locked statement and verification harness"
CRIT=$(git rev-parse HEAD)

# Fill the pin with the commit that CONTAINS the statement — see the header.
for f in check-statement.sh task.json; do
  python3 - "$f" "$CRIT" <<'PY'
import sys
p, sha = sys.argv[1], sys.argv[2]
s = open(p).read().replace("__CRITERIA_COMMIT__", sha)
open(p, "w").write(s)
PY
done
git add -A
git -c user.name="board scaffold" -c user.email="noreply@aletheai.org" \
    commit -q -m "$SLUG: pin criteria commit ${CRIT:0:12}"

echo
echo "Created $DEST/"
echo "  statement   $SPECBASE  ->  $FULL"
echo "  criteria    $CRIT"
echo "  toolchain   $TOOLCHAIN"
echo
echo "The statement file is byte-identical at the pinned commit and at HEAD, so"
echo "the pin is stable. Verify that rather than trust it:"
echo "    cd $DEST && ./check-statement.sh && ./verify.sh"
echo
echo "Then, before posting: fill in the TODOs in TASK.md and task.json, push to"
echo "GitHub, and post the board pinning criteria commit ${CRIT:0:12}."
