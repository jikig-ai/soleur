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

# --- V1: anti-vacuity ---------------------------------------------------------------------------
if [[ "$TOTAL" -eq 12 ]]; then ok "V1 full inventory ran (12 checks incl. this)"; else bad "V1 expected 12, ran $((TOTAL+1))"; fi

echo ""
echo "=== $PASS/$TOTAL passed ==="
(( FAIL > 0 )) && exit 1
echo "OK"
