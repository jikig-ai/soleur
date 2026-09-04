#!/usr/bin/env bash
# Sibling suite for doppler-secrets-delete-redirect.sh.
#
# Written for #7164: this hook was one of two in-scope hooks with NO sibling
# suite, so nothing asserted its characteristic decision and a break in its
# wiring would have been silent. The hook-input migration is exactly the kind of
# change that needs a per-hook canary underneath it.
#
# Guard under test: `doppler secrets delete|set|upload` without a stdout
# redirect denies, because the CLI prints ALL remaining secrets to stdout.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Applied to EVERY hook suite, not just ones whose hook is a sibling .sh:
# security_reminder_hook is a .py, so pairing by filename missed it and it
# kept writing the real ledger. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/doppler-secrets-delete-redirect.sh"

PASS=0; FAIL=0
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

# ADR-129 rule (c): ONE owning trap for every tempfile this suite allocates.
# Per-case sandboxes are children of this root, so a case that dies mid-assertion
# cannot leak — /tmp is a machine-global tmpfs shared with sibling worktrees.
HIC_TMPROOT="$(mktemp -d -t dsdrroot.XXXXXXXX)"
trap 'rm -rf "$HIC_TMPROOT"' EXIT

# Non-git temp CWD so branch-dependent sibling gates cannot mask this one (#5192).
decision_of() {
  local payload="$1" tmp out
  tmp="$(mktemp -d -p "$HIC_TMPROOT")"
  out="$(cd "$tmp" && printf '%s' "$payload" | INCIDENTS_REPO_ROOT="$tmp" bash "$HOOK" 2>/dev/null)"
  rm -rf "$tmp"
  [[ -z "${out//[[:space:]]/}" ]] && { echo "<none>"; return; }
  echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null || echo "<jq-fail>"
}
mk() { jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
check() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "PASS: $label → $got"
  else FAIL=$((FAIL+1)); echo "FAIL: $label"; echo "  want: $want"; echo "  got:  $got"; fi
}

# --- the characteristic decision -------------------------------------------
check "delete without redirect denies" "deny" \
  "$(decision_of "$(mk 'doppler secrets delete FOO -p soleur -c dev')")"
check "set without redirect denies" "deny" \
  "$(decision_of "$(mk 'doppler secrets set FOO=bar -p soleur -c dev')")"
check "upload without redirect denies" "deny" \
  "$(decision_of "$(mk 'doppler secrets upload f.env -p soleur -c dev')")"

# --- the escape hatch the deny message names must actually work ------------
check "delete WITH > /dev/null allows" "<none>" \
  "$(decision_of "$(mk 'doppler secrets delete FOO -p soleur -c dev > /dev/null')")"
check "set WITH 1> /dev/null allows" "<none>" \
  "$(decision_of "$(mk 'doppler secrets set FOO=bar -p soleur -c dev 1> /dev/null')")"

# --- non-triggering commands -----------------------------------------------
check "doppler secrets get allows" "<none>" \
  "$(decision_of "$(mk 'doppler secrets get FOO -p soleur -c dev --plain')")"
check "unrelated command allows" "<none>" "$(decision_of "$(mk 'ls -la')")"

# --- #7164: the envelope contract ------------------------------------------
# An ARRAY tool_input.command previously rendered across lines, matched no
# anchored pattern above, and slipped the guard. This hook is not the designated
# ask responder, so it stays silent on stdout — but it must NOT proceed as if it
# had seen an empty command, and it must record the fault.
check "ARRAY command: no decision emitted (non-responder)" "<none>" \
  "$(decision_of "$(jq -nc '{tool_name:"Bash", tool_input:{command:["doppler","secrets","delete","FOO"]}}')")"

root="$(mktemp -d -p "$HIC_TMPROOT")"
( cd "$root" && jq -nc '{tool_name:"Bash", tool_input:{command:["doppler","secrets","delete","FOO"]}}' \
    | INCIDENTS_REPO_ROOT="$root" bash "$HOOK" >/dev/null 2>&1 )
if [[ -f "$root/.claude/.rule-incidents.jsonl" ]] \
   && grep -q 'hook-input-' "$root/.claude/.rule-incidents.jsonl" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS: ARRAY command records a hook-input fault (no silent disarm)"
else
  FAIL=$((FAIL+1)); echo "FAIL: ARRAY command disarmed the guard with no record"
fi
rm -rf "$root"

echo
echo "=== doppler-secrets-delete-redirect: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
