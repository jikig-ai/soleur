#!/usr/bin/env bash
# Fixture tests for post-dispatch-watch-gate.sh.
#
# The gate's whole value is that it turns a SILENT omission into a loud one, so the cases that
# matter most are the ones where it must STAY QUIET: a gate that nags on ordinary commands gets
# tuned out, and a tuned-out gate is the same silence it was built to remove.
#
# Fixtures synthesized (cq-test-fixtures-synthesized-only); the dispatch shapes are the verbatim
# ones from 2026-08-19 (gh workflow run cutover-inngest.yml, gh pr merge --auto).
set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/post-dispatch-watch-gate.sh"
PASS=0; FAIL=0; TOTAL=0
[[ -x "$HOOK" ]] || { echo "FATAL: hook not executable" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git missing"; exit 0; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
: "${WORK:?fixture dir is empty; git -C <empty> would retarget this write}"
git -C "$WORK" init -q
STATE_DIR="$WORK/.git"

bash_payload() { jq -nc --arg c "$1" --arg d "$WORK" '{tool_name:"Bash",cwd:$d,session_id:"t",tool_input:{command:$c}}'; }
monitor_payload() { jq -nc --arg d "$WORK" '{tool_name:"Monitor",cwd:$d,session_id:"t",tool_input:{command:"watch"}}'; }

nag_of() { jq -r '.systemMessage // ""' <<<"${1:-{\}}" 2>/dev/null; }
ok()   { printf '  PASS: %s\n' "$1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

reset() { rm -f "$STATE_DIR/soleur-pending-dispatch"; }

echo "== post-dispatch-watch-gate =="

# --- D1: a dispatch records, and the NEXT call nags -------------------------------------------
reset
bash_payload 'gh workflow run cutover-inngest.yml -f op=execute' | "$HOOK" >/dev/null 2>&1
[[ -s "$STATE_DIR/soleur-pending-dispatch" ]] && ok "D1a dispatch recorded a pending entry" || bad "D1a dispatch not recorded"
out=$(bash_payload 'echo hello' | "$HOOK" 2>/dev/null)
grep -q 'NO Monitor armed' <<<"$(nag_of "$out")" && ok "D1b next tool call nags" || bad "D1b no nag on the next call"

# --- D2: the dispatch call itself must NOT nag (nothing missed yet) ---------------------------
reset
out=$(bash_payload 'gh workflow run build-inngest-bootstrap-image.yml' | "$HOOK" 2>/dev/null)
[[ -z "$(nag_of "$out")" ]] && ok "D2 the dispatch call itself is silent" || bad "D2 nagged on the dispatch itself"

# --- D3: other dispatch shapes ----------------------------------------------------------------
for c in 'gh pr merge 7599 --squash --auto' 'gh run rerun 31981236668 --failed'; do
  reset
  bash_payload "$c" | "$HOOK" >/dev/null 2>&1
  [[ -s "$STATE_DIR/soleur-pending-dispatch" ]] && ok "D3 recorded: ${c:0:28}" || bad "D3 missed: ${c:0:28}"
done

# --- R1: a Monitor clears it ------------------------------------------------------------------
reset
bash_payload 'gh workflow run x.yml' | "$HOOK" >/dev/null 2>&1
monitor_payload | "$HOOK" >/dev/null 2>&1
[[ ! -s "$STATE_DIR/soleur-pending-dispatch" ]] && ok "R1 Monitor clears pending" || bad "R1 Monitor did not clear"
out=$(bash_payload 'echo after-monitor' | "$HOOK" 2>/dev/null)
[[ -z "$(nag_of "$out")" ]] && ok "R1b silent after a Monitor" || bad "R1b still nagging after a Monitor"

# --- R2: a FOREGROUND read also clears (else the gate trains you to ignore it) -----------------
for c in 'gh run view 32293319145 --json status' 'gh pr checks 7599'; do
  reset
  bash_payload 'gh workflow run x.yml' | "$HOOK" >/dev/null 2>&1
  bash_payload "$c" | "$HOOK" >/dev/null 2>&1
  [[ ! -s "$STATE_DIR/soleur-pending-dispatch" ]] && ok "R2 foreground read clears: ${c:0:22}" || bad "R2 did not clear: ${c:0:22}"
done

# --- Q1: ordinary commands never nag on a clean slate -----------------------------------------
reset
quiet=1
for c in 'ls -la' 'git status --short' 'bun test foo.test.ts' 'gh issue view 7462'; do
  out=$(bash_payload "$c" | "$HOOK" 2>/dev/null)
  [[ -n "$(nag_of "$out")" ]] && quiet=0
done
(( quiet == 1 )) && ok "Q1 ordinary commands are silent" || bad "Q1 nagged on an ordinary command"

# --- Q2: a combined dispatch-and-read line does not arm a nag it already answered --------------
reset
bash_payload 'gh workflow run x.yml && gh run view 123 --json status' | "$HOOK" >/dev/null 2>&1
[[ ! -s "$STATE_DIR/soleur-pending-dispatch" ]] && ok "Q2 dispatch+foreground-read in one line is resolved" || bad "Q2 armed a nag for a line that read its own result"

# --- N1: non-git cwd must not explode ----------------------------------------------------------
out=$(jq -nc '{tool_name:"Bash",cwd:"/nonexistent-xyz",tool_input:{command:"gh workflow run x.yml"}}' | "$HOOK" 2>&1; echo "rc=$?")
grep -q 'rc=0' <<<"$out" && ok "N1 non-git cwd fails open" || bad "N1 non-git cwd errored"

# --- Q3: a MENTION inside a quoted body is not a dispatch ---------------------------------------
# This is where 140 rows of this rule's own telemetry came from. The gate greps the raw command,
# so any line that merely QUOTES a dispatch -- a grep for it, a test fixture containing it, a
# commit message about it -- armed the nag, and `grep -oE 'gh pr merge [0-9]+'` then labelled the
# row with the quoted fixture's PR number. Measured on the operator ledger before this fix:
# 140 rows whose command_snippet is the fixture string `gh pr merge 123`, none of which
# dispatched anything. Ten sibling hooks already strip bodies before matching; this one did not.
reset
for c in \
  "grep -rn 'gh pr merge 123 --squash --auto' .claude/hooks/" \
  "git commit -m 'docs: explain gh pr merge --auto'" \
  "printf '%s' \"gh workflow run deploy.yml\" > fixture.txt" \
; do
  reset
  bash_payload "$c" | "$HOOK" >/dev/null 2>&1
  if [[ -s "$STATE_DIR/soleur-pending-dispatch" ]]; then
    bad "Q3 a quoted MENTION armed a nag: $c"
  else
    ok "Q3 quoted mention is not a dispatch: ${c:0:40}..."
  fi
done

# --- Q4: stripping must not disarm a REAL dispatch ----------------------------------------------
# The other direction. A strip aggressive enough to blank the command would make every Q3 arm pass
# while silently deleting the gate, so each real shape is re-driven after the fix.
for c in \
  'gh workflow run cutover-inngest.yml -f op=execute' \
  'gh pr merge 7849 --squash --auto' \
  'gh run rerun 12345' \
; do
  reset
  bash_payload "$c" | "$HOOK" >/dev/null 2>&1
  if [[ -s "$STATE_DIR/soleur-pending-dispatch" ]]; then
    ok "Q4 real dispatch still arms: ${c:0:40}"
  else
    bad "Q4 stripping DISARMED a real dispatch: $c"
  fi
done

# --- V1: anti-vacuity ---------------------------------------------------------------------------
if [[ "$TOTAL" -eq 18 ]]; then ok "V1 full inventory ran (18 checks incl. this)"; else bad "V1 expected 18, ran $((TOTAL+1))"; fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
(( FAIL > 0 )) && exit 1
echo "OK"
