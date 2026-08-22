#!/usr/bin/env bash
# run-checker.sh — run a problem's checker against a submission, in a sandbox
# that the problem cannot configure.
#
#   ./run-checker.sh <checker.py> <submission-file> \
#        [--commit <sha>] [--sha256 <hash>] [--pip pkg==ver,...] [--base <image@sha256:...>]
#        [--no-sandbox]
#
# --no-sandbox skips Docker and runs the checker directly as you. Provenance is
# still verified, because that governs whether the VERDICT is right, which is a
# different question from whether your machine is safe. Use it when you have
# read the checker, or accept the attestation in vetted.json.
#
# Pass --commit with the board's pinned criteria commit. Without it the checker
# is sandboxed but its provenance is unverified, and a compromised checker can
# return a false verdict from inside a perfect sandbox.
#
# Why this exists rather than the run-checker.sh shipped inside each problem:
#
#   A sandbox whose parameters travel with the untrusted artifact is not a
#   sandbox. A problem repository's own Dockerfile and runner configure the very
#   isolation they are supposed to provide, and `docker build` executes arbitrary
#   commands AS ROOT at build time — before any container exists. Reading a short
#   Dockerfile is a real precaution but it is not enforcement.
#
#   So this script never uses the problem's Dockerfile. It mounts the checker
#   script read-only into a base image it chooses itself, and applies isolation
#   flags the problem cannot influence. The only thing crossing from the problem
#   into execution is one Python file, and that file runs with no network, no
#   writable filesystem and no capabilities.
#
#   When a problem needs libraries, it *declares* them — a base image digest and
#   a pip list, as data — and this script builds a Dockerfile it wrote itself.
#   A declaration is a far smaller attack surface than an arbitrary build script.
#
# You are running code from this repository, so read it. It is short on purpose.

set -uo pipefail

# Exit codes. The checker's own verdict passes through untouched; everything
# that is NOT a verdict gets a code of its own.
#
#   0  the checker accepted the submission
#   1  the checker rejected it
#   2  the checker could not parse it
#   3  provenance failed — what would have run is not what the board pinned
#   4  this runner could not run at all (no docker, missing file, build failed)
#
# 3 and 4 are deliberately distinct from 2. "The sandbox never started" and "the
# submission was malformed" are different events, and a caller that cannot tell
# them apart will eventually record one as the other — reading an infrastructure
# failure as a verdict on someone's work.

# Pinned by digest, not by tag: a tag moves, and two people running the same
# checker months apart would then get different environments.
DEFAULT_BASE="python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de"

CHECK=""; SUB=""; PIP=""; BASE="$DEFAULT_BASE"; COMMIT=""; WANT_SHA=""; NOSANDBOX=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pip)    PIP="$2"; shift 2 ;;
    --base)   BASE="$2"; shift 2 ;;
    --commit) COMMIT="$2"; shift 2 ;;
    --sha256) WANT_SHA="$2"; shift 2 ;;
    --no-sandbox) NOSANDBOX=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) if [ -z "$CHECK" ]; then CHECK="$1"; elif [ -z "$SUB" ]; then SUB="$1"; else
         echo "unexpected argument: $1" >&2; exit 4; fi; shift ;;
  esac
done
[ -z "$CHECK" ] || [ -z "$SUB" ] && {
  echo "usage: run-checker.sh <checker.py> <submission-file> [--pip pkg==ver,...] [--base image@sha256:...]" >&2
  exit 4; }
[ -f "$CHECK" ] || { echo "no such checker: $CHECK" >&2; exit 4; }
[ -f "$SUB" ]   || { echo "no such submission: $SUB" >&2; exit 4; }

CHECK_ABS="$(cd "$(dirname "$CHECK")" && pwd)/$(basename "$CHECK")"
SUB_ABS="$(cd "$(dirname "$SUB")" && pwd)/$(basename "$SUB")"

# ---------------------------------------------------------------- provenance
#
# The sandbox protects your machine from the checker. It does nothing about the
# checker being WRONG. If a problem repository is compromised, an attacker edits
# check.py so that it accepts an invalid submission, and a perfect sandbox will
# faithfully run that and report a false verdict.
#
# The defence is the pinned criteria commit. An attacker who compromises the
# repository can change `main`, but cannot change what sits at a given commit
# without breaking git's content addressing. So the question worth asking is not
# "is this file safe to run" but "is this the file the board committed to".
if [ -n "$COMMIT" ]; then
  dir=$(dirname "$CHECK_ABS")
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || {
    echo "--commit given but this is not a git repository" >&2; exit 4; }
  # Ask git for the repo-relative path rather than computing it by string
  # surgery: on macOS /var is a symlink to /private/var, so the two spellings of
  # the same directory do not share a prefix.
  rel=$(git -C "$dir" ls-files --full-name -- "$(basename "$CHECK_ABS")" | head -1)
  [ -n "$rel" ] || { echo "$(basename "$CHECK_ABS") is not tracked in this repository" >&2; exit 4; }
  git -C "$root" cat-file -e "${COMMIT}^{commit}" 2>/dev/null || {
    echo "the pinned commit ${COMMIT} is not present locally." >&2
    echo "  A shallow clone or a downloaded archive will not contain it; re-clone in full." >&2
    exit 4; }
  if ! git -C "$root" show "${COMMIT}:${rel}" 2>/dev/null | diff -q - "$CHECK_ABS" >/dev/null; then
    echo "PROVENANCE FAILED: $rel does not match the pinned commit ${COMMIT:0:12}." >&2
    echo "  What you are about to run is not what the board committed to." >&2
    echo "  Do not trust its verdict. Investigate before proceeding." >&2
    exit 3
  fi
  echo "provenance: $rel matches pinned commit ${COMMIT:0:12}"
elif [ -n "$WANT_SHA" ]; then
  got=$(shasum -a 256 "$CHECK_ABS" | cut -d" " -f1)
  [ "$got" = "$WANT_SHA" ] || {
    echo "PROVENANCE FAILED: sha256 is $got, expected $WANT_SHA" >&2; exit 3; }
  echo "provenance: sha256 matches (${WANT_SHA:0:16}…)"
else
  echo "WARNING: no --commit or --sha256 given, so the checker's provenance is" >&2
  echo "         unverified. The sandbox will contain it, but a compromised or" >&2
  echo "         edited checker can still return a false verdict. A referee" >&2
  echo "         settling a board should always pass --commit." >&2
fi

# ------------------------------------------------------------ lightweight path
#
# Docker is the heaviest prerequisite we impose, and the sandbox it provides
# protects your machine — not the correctness of the verdict. Those are separate
# concerns, and the provenance check above, which is the one that governs
# correctness, costs nothing and has already run.
#
# So: if you have read the checker, or it is recorded in vetted.json and you
# accept that attestation, you may run it directly as yourself.
if [ "$NOSANDBOX" = "1" ]; then
  HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  sha=$(shasum -a 256 "$CHECK_ABS" | cut -d" " -f1)
  note=$(python3 - "$HERE/vetted.json" "$sha" <<'PYV' 2>/dev/null
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: raise SystemExit
for e in d.get("entries",[]):
    if e.get("sha256")==sys.argv[2]:
        if e.get("reviewedBy"):
            print(f"reviewed by {e['reviewedBy']} on {e['reviewedOn']}")
        elif e.get("auditedClean"):
            print("AUDITED-ONLY")
        raise SystemExit
PYV
)
  case "$note" in
    "") echo "NOT VETTED: this checker is not in vetted.json. Read it before running" >&2
        echo "            it as yourself, or drop --no-sandbox." >&2 ;;
    "AUDITED-ONLY")
        echo "vetted.json: audited clean by audit-checker.py, but NO PERSON has" >&2
        echo "             signed for it. An automated audit is not a security" >&2
        echo "             boundary — see audit-checker.py's own header." >&2 ;;
    *)  echo "vetted.json: $note" ;;
  esac
  echo "running directly, no sandbox — the checker executes as you"
  exec python3 "$CHECK_ABS" "$SUB_ABS"
fi

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 4; }
docker info >/dev/null 2>&1 || { echo "the docker daemon is not responding" >&2; exit 4; }


IMAGE="$BASE"
BUILT=""
if [ -n "$PIP" ]; then
  # A Dockerfile WE write, from the declaration. The problem's Dockerfile, if it
  # has one, is never read.
  ctx=$(mktemp -d); trap 'rm -rf "$ctx"; [ -n "$BUILT" ] && docker image rm -f "$BUILT" >/dev/null 2>&1' EXIT
  {
    echo "FROM $BASE"
    echo "RUN pip install --no-cache-dir $(echo "$PIP" | tr ',' ' ')"
    echo "USER 65534:65534"
  } > "$ctx/Dockerfile"
  echo "building an environment from the declaration:  $PIP"
  BUILT="checker-env-$$"
  docker build -q -t "$BUILT" "$ctx" >/dev/null || { echo "environment build failed" >&2; exit 4; }
  IMAGE="$BUILT"
fi

# The submission and the checker both enter read-only; a verdict on stdout is the
# only thing that leaves.
docker run --rm \
  --network none \
  --read-only \
  --memory 512m --cpus 1 --pids-limit 64 \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --user 65534:65534 \
  -v "$CHECK_ABS:/task/check.py:ro" \
  -v "$SUB_ABS:/data/submission:ro" \
  "$IMAGE" python3 /task/check.py /data/submission
#x
