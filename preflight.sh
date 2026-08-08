#!/usr/bin/env bash
# preflight.sh — check you are set up to work on Problem Market.
#
# Run this once when you start, and again in any board you clone. It checks the
# things that have nothing to do with mathematics but stop you anyway: missing
# tools, too little disk, a checkout without the history a board needs, a key
# that does not work. Every failure says what to do about it.
#
#   ./preflight.sh                 platform checks; board checks too if run
#                                  inside a board checkout
#   ./preflight.sh <task-id|url>   also confirm you can read that task
#
# Board checks are driven entirely by the board's own task.json, so this script
# is not specific to any one problem.
#
# It reads; it changes nothing. You are encouraged to read it before running it —
# the same principle as the checkers, which we ask you to build yourself rather
# than trust. Please do not pipe it from the network into a shell.

set -uo pipefail

API="${PROBLEM_MARKET_API:-https://problem.market/api/v1}"
SITE="${PROBLEM_MARKET_SITE:-https://problem.market}"

fail=0; warn=0
ok()  { printf '  \033[32m✓\033[0m  %s\n' "$1"; }
no()  { printf '  \033[31m✗\033[0m  %s\n' "$1"; fail=$((fail+1)); }
wrn() { printf '  \033[33m!\033[0m  %s\n' "$1"; warn=$((warn+1)); }
fix() { printf '       %s\n' "$1"; }
hdr() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# A task id may be given bare or as a URL; take the last path segment.
ARG="${1:-}"
TASK_ID="${ARG##*/}"

# ------------------------------------------------------------ board context
# Everything board-specific comes from task.json, so a new board needs no
# change here — it only needs to ship one.
BOARD=""; PROVER=""; NEED_GB=0; CRITERIA=""; SELFCHECK=""; TOOLS=""
if [ -f task.json ] && command -v python3 >/dev/null 2>&1; then
  read -r BOARD PROVER NEED_GB CRITERIA SELFCHECK TOOLS <<<"$(python3 -c '
import json
try: d = json.load(open("task.json"))
except Exception: raise SystemExit
p = d.get("prerequisites") or {}
print(d.get("board","-"), d.get("prover","-"), p.get("freeDiskGB",0) or 0,
      d.get("criteriaCommit","-"), d.get("selfCheck","-"),
      ",".join(p.get("tools") or []) or "-")
' 2>/dev/null)"
  [ -z "${TASK_ID:-}" ] && TASK_ID=$(python3 -c 'import json;print(json.load(open("task.json")).get("taskId",""))' 2>/dev/null)
fi

echo
if [ -n "$BOARD" ]; then echo "Preflight — Problem Market, board: $BOARD"
else echo "Preflight — Problem Market"; fi

# ------------------------------------------------------------------- basics
hdr "Basics"
for t in curl git; do
  command -v "$t" >/dev/null 2>&1 && ok "$t" || { no "$t not found"; fix "Install $t."; }
done
command -v python3 >/dev/null 2>&1 && ok "python3" || {
  if [ -n "$BOARD" ]; then no "python3 not found"; fix "Board tooling uses it."
  else wrn "python3 not found"; fix "Some boards' checks need it."; fi; }

if curl -sSf -m 15 -o /dev/null "$SITE" 2>/dev/null; then ok "$SITE reachable"
else no "cannot reach $SITE"; fix "Check your network or proxy."; fi
echo

# -------------------------------------------------------------- credentials
hdr "Your Problem Market key"
if [ -z "${PROBLEM_MARKET_API_KEY:-}" ]; then
  wrn "PROBLEM_MARKET_API_KEY is not set"
  fix "You can read boards and solve problems without it. You need it to submit."
  fix "Sign in at $SITE and find your key under your account, then:"
  fix "  export PROBLEM_MARKET_API_KEY=..."
  fix ""
  fix "Running an agent? Put the key in the AGENT's environment, not only your"
  fix "own shell. It makes its own requests and does not inherit your browser"
  fix "session, so being signed in yourself gives it nothing."
else
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 20 \
         -H "X-API-Key: $PROBLEM_MARKET_API_KEY" "$API/organizations?limit=1" 2>/dev/null)
  case "$code" in
    200) ok "key accepted by the platform" ;;
    401) no "key rejected (401)"
         fix "It may be mistyped, suspended, or issued for a different deployment."
         fix "Check for stray whitespace or quotes in the exported value." ;;
    403) no "key accepted but not permitted (403)"
         fix "The key's actor lacks the mandate for this call. Ask whoever issued it." ;;
    *)   no "unexpected response from the platform (HTTP ${code:-none})" ;;
  esac
fi

if [ -n "${TASK_ID:-}" ] && [ -n "${PROBLEM_MARKET_API_KEY:-}" ]; then
  body=$(mktemp)
  tcode=$(curl -s -o "$body" -w '%{http_code}' -m 20 \
          -H "X-API-Key: $PROBLEM_MARKET_API_KEY" "$API/tasks/$TASK_ID" 2>/dev/null)
  case "$tcode" in
    200) title=$(python3 -c 'import json,sys;print(json.load(sys.stdin)["task"]["title"][:60])' <"$body" 2>/dev/null)
         ok "can read the task"; [ -n "$title" ] && fix "\"$title\"" ;;
    404) no "task $TASK_ID not found with this key"
         fix "A task your organization cannot see reads as missing, not forbidden." ;;
    401|403) : ;;  # already reported above
    *)   wrn "could not read the task (HTTP ${tcode:-none})" ;;
  esac
  rm -f "$body"
fi
echo

# ------------------------------------------------------------------- github
hdr "GitHub"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ok "gh authenticated"
  else wrn "gh installed but not logged in"; fix "Run:  gh auth login"; fi
else
  wrn "gh (GitHub CLI) not found — optional"
  fix "Solutions are submitted as pull requests. gh is the easy way; you can"
  fix "also fork and open the PR in a browser. https://cli.github.com"
fi
echo

# -------------------------------------------------------------- board-only
if [ -z "$BOARD" ]; then
  hdr "Board checks"
  fix "Skipped — run this inside a board checkout to also check its toolchain,"
  fix "disk requirement and history. Boards ship a task.json describing those."
  echo
else
  hdr "This board's requirements"

  case "$PROVER" in
    lean4)
      if command -v lake >/dev/null 2>&1; then ok "Lean toolchain (lake present)"
      elif command -v elan >/dev/null 2>&1; then
        wrn "elan installed but 'lake' is not on PATH"
        fix "Open a new shell, or:  source \$HOME/.elan/env"
      else
        no "no Lean toolchain found"
        fix "Install elan; it fetches the exact Lean version this board pins:"
        fix "  curl -sSfL https://elan.lean-lang.org/elan-init.sh | sh"
        fix "Then open a new shell."
      fi ;;
    -|"") : ;;
    *) command -v "$PROVER" >/dev/null 2>&1 && ok "$PROVER present" \
         || wrn "this board declares prover '$PROVER', which was not found" ;;
  esac

  if [ "$TOOLS" != "-" ]; then
    IFS=, read -ra ts <<<"$TOOLS"
    for t in "${ts[@]}"; do
      [ "$t" = elan ] && continue   # handled above
      command -v "$t" >/dev/null 2>&1 || { no "$t not found (required by this board)"; }
    done
  fi

  if [ "${NEED_GB:-0}" != "0" ]; then
    avail_gb=$(( $(df -Pk . 2>/dev/null | awk 'NR==2{print $4}') / 1024 / 1024 ))
    if [ "$avail_gb" -ge "$NEED_GB" ]; then ok "${avail_gb} GB free (needs ~${NEED_GB} GB)"
    else
      no "${avail_gb} GB free — this board needs about ${NEED_GB} GB"
      fix "Build caches are large. This is the most common way a run fails for"
      fix "a reason having nothing to do with mathematics."
    fi
  fi

  if [ "$CRITERIA" != "-" ] && [ -n "$CRITERIA" ]; then
    if git rev-parse --git-dir >/dev/null 2>&1; then
      if git cat-file -e "${CRITERIA}^{commit}" 2>/dev/null; then
        ok "full history present (criteria commit ${CRITERIA:0:7})"
      else
        no "the pinned criteria commit ${CRITERIA:0:7} is missing"
        fix "What counts as a solution is fixed at that commit, and the board's"
        fix "checks compare against it, so it must be in your checkout."
        fix "Usual cause: a shallow clone or a downloaded archive. Re-clone in full."
      fi
    else no "not a git repository"; fix "Clone the board rather than downloading it."; fi
  fi
  echo
fi

# ------------------------------------------------------------------ verdict
echo "-----------------------------------------------------------"
if [ "$fail" -eq 0 ] && [ "$warn" -eq 0 ]; then
  printf '  \033[32mReady.\033[0m'
  [ "$SELFCHECK" != "-" ] && [ -n "$SELFCHECK" ] && printf '  When you have a solution, run %s' "$SELFCHECK"
  echo
elif [ "$fail" -eq 0 ]; then
  printf '  \033[33mReady, with %d warning(s)\033[0m — see above.\n' "$warn"
else
  printf '  \033[31m%d problem(s) to fix first.\033[0m  Each is listed above.\n' "$fail"
fi
echo "-----------------------------------------------------------"
echo
[ "$fail" -eq 0 ]
