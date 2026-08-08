#!/usr/bin/env bash
# run-checker.sh — run a problem's checker against a submission, in a sandbox
# that the problem cannot configure.
#
#   ./run-checker.sh <checker.py> <submission-file> [--pip pkg==ver,...] [--base <image@sha256:...>]
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

# Pinned by digest, not by tag: a tag moves, and two people running the same
# checker months apart would then get different environments.
DEFAULT_BASE="python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de"

CHECK=""; SUB=""; PIP=""; BASE="$DEFAULT_BASE"
while [ $# -gt 0 ]; do
  case "$1" in
    --pip)  PIP="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) if [ -z "$CHECK" ]; then CHECK="$1"; elif [ -z "$SUB" ]; then SUB="$1"; else
         echo "unexpected argument: $1" >&2; exit 2; fi; shift ;;
  esac
done
[ -z "$CHECK" ] || [ -z "$SUB" ] && {
  echo "usage: run-checker.sh <checker.py> <submission-file> [--pip pkg==ver,...] [--base image@sha256:...]" >&2
  exit 2; }
[ -f "$CHECK" ] || { echo "no such checker: $CHECK" >&2; exit 2; }
[ -f "$SUB" ]   || { echo "no such submission: $SUB" >&2; exit 2; }

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "the docker daemon is not responding" >&2; exit 2; }

CHECK_ABS="$(cd "$(dirname "$CHECK")" && pwd)/$(basename "$CHECK")"
SUB_ABS="$(cd "$(dirname "$SUB")" && pwd)/$(basename "$SUB")"

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
  docker build -q -t "$BUILT" "$ctx" >/dev/null || { echo "environment build failed" >&2; exit 2; }
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
