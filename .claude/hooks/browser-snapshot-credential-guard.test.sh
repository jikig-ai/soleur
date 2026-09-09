#!/usr/bin/env bash
# Self-tests for the agent-browser snapshot PreToolUse interceptor (#7947).
#
# Auto-globbed by scripts/test-all.sh via .claude/hooks/*.test.sh -- carries NO
# run_suite line.
#
# Envelope-driven: every case feeds a synthesized PreToolUse JSON envelope on
# stdin and asserts the emitted decision. The emitted decision is the only thing
# a stdin/stdout hook can be held to.
#
# Case list is the Guard 3 mutation matrix from the plan, plus a registration
# case covering BOTH manifests -- the shipped one is what decides whether a
# Soleur operator receives this enforcement at all (property P7).
set -uo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
# The hook lives in the PLUGIN, not in .claude/hooks/: ${CLAUDE_PLUGIN_ROOT}
# resolves into the installed plugin directory, so a script under .claude/
# would never reach a customer. The suite stays here because
# .claude/hooks/*.test.sh is an auto-globbed suite path and
# plugins/soleur/hooks/ is not.
HOOK="$REPO_ROOT/plugins/soleur/hooks/browser-snapshot-credential-guard.sh"
PLUGIN_MANIFEST="$REPO_ROOT/plugins/soleur/hooks/hooks.json"
LOCAL_SETTINGS="$REPO_ROOT/.claude/settings.json"
README="$REPO_ROOT/.claude/hooks/README.md"

pass=0; fail=0; cases=0
# 3 deny rows + 4 allow rows + 5 registration rows + 2 reason-content rows = 14.
MIN_ASSERTIONS=14

ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# Instrument self-test: drive both verdict helpers, then zero the counters so
# the deliberate failure does not colour the verdict or break reconciliation.
_p0=$pass; _f0=$fail
ok  "instrument self-test: ok() increments"
bad "instrument self-test: bad() increments (EXPECTED, not a real failure)"
if [[ $pass -ne $((_p0 + 1)) || $fail -ne $((_f0 + 1)) ]]; then
  printf 'INSTRUMENT BROKEN: ok()/bad() did not both move\n' >&2; exit 1
fi
pass=0; fail=0; cases=0

if [[ ! -x "$HOOK" ]]; then
  printf 'FAIL - hook missing or not executable at %s\n' "$HOOK"
  printf '\nRED: the interceptor does not exist yet. Expected pre-implementation state.\n'
  exit 1
fi

envelope() { jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
decision() { envelope "$1" | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }

assert_deny() {
  local label="$1" cmd="$2" d
  cases=$((cases + 1)); d="$(decision "$cmd")"
  [[ "$d" == "deny" ]] && ok "$label" || bad "$label — expected deny, got '$d'"
}

assert_allow() {
  local label="$1" cmd="$2" d
  cases=$((cases + 1)); d="$(decision "$cmd")"
  [[ "$d" != "deny" ]] && ok "$label" || bad "$label — expected allow, got deny"
}

# ---- Deny rows (Guard 3 M1-M3) ----
assert_deny 'M1 bare `agent-browser snapshot -i`' \
  'agent-browser snapshot -i'

assert_deny 'M2 wrapped form (bash -c) is not missed by a ^ anchor' \
  "bash -c 'cd /tmp && agent-browser snapshot -i'"

assert_deny 'M3 chained &&, only the FIRST is piped' \
  'agent-browser snapshot -i | python3 plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py && agent-browser snapshot --json'

# ---- Allow rows (Guard 3 H2-H3) ----
assert_allow 'H2 approved pipe form with 2>&1' \
  'agent-browser snapshot -i 2>&1 | python3 plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py'

assert_allow 'H2b approved pipe form without 2>&1 (stderr carries no node content -- measured)' \
  'agent-browser snapshot -i | python3 plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py'

assert_allow 'H3 `agent-browser screenshot` is not banned' \
  'agent-browser screenshot /tmp/x.png'

assert_allow 'H3b `agent-browser open` is not banned' \
  'agent-browser open https://example.com'

# ---- Reason content: the deny must name BOTH escape routes ----
cases=$((cases + 1))
reason="$(envelope 'agent-browser snapshot -i' | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
# Anchored on the PRESCRIPTIVE phrase, not the bare token "screenshot" --
# the reason also uses that word in its caveat paragraph, so a bare-token
# check stays green after the prescription itself is deleted
# (cq-assert-anchor-not-bare-token; caught by mutation M5).
if [[ "$reason" == *"redact-a11y-snapshot.py"* && "$reason" == *"take a screenshot instead"* ]]; then
  ok 'deny reason names the redactor path and prescribes the screenshot alternative'
else
  bad 'deny reason must name the redactor path AND prescribe "take a screenshot instead"'
fi

# The measured caveat is load-bearing: a screenshot is NOT safe for a readonly
# type=text credential panel, which is the class with a recorded in-repo
# incident. A deny that prescribes a screenshot without it is actively wrong.
cases=$((cases + 1))
if [[ "$reason" == *"NOT safe for a generated-credential panel"* ]]; then
  ok 'deny reason carries the measured screenshot caveat'
else
  bad 'deny reason must state that a screenshot is NOT safe for a credential panel'
fi

# ---- Registration rows (Guard 3 M4) ----
# The SHIPPED manifest is the one that decides whether a customer gets this.
# Exact-filename anchor: `test("browser-snapshot-credential-guard")` is a
# SUBSTRING match, so a registration renamed to `...-guard-TYPO.sh` satisfies it
# while shipping a path that does not exist. Mutation M7 rode straight through
# the substring form. Anchor on the terminal filename instead.
cases=$((cases + 1))
SHIPPED_CMD="$(jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty' "$PLUGIN_MANIFEST" 2>/dev/null \
  | grep -F 'browser-snapshot-credential-guard' || true)"
if [[ "$SHIPPED_CMD" == *"/hooks/browser-snapshot-credential-guard.sh" ]]; then
  ok 'registered in the SHIPPED plugin manifest with the exact filename'
else
  bad "NOT registered in plugins/soleur/hooks/hooks.json with the exact filename (got '${SHIPPED_CMD:-<none>}') — a customer receives no enforcement (P7)"
fi

# The registered command must resolve to a file that exists and is executable.
# A manifest entry pointing at a missing script dispatches nothing, silently.
cases=$((cases + 1))
RESOLVED="${SHIPPED_CMD/\$\{CLAUDE_PLUGIN_ROOT\}/$REPO_ROOT/plugins/soleur}"
if [[ -n "$SHIPPED_CMD" && -x "$RESOLVED" ]]; then
  ok 'shipped registration resolves to an existing executable'
else
  bad "shipped registration does not resolve to an executable (tried '${RESOLVED:-<none>}')"
fi

cases=$((cases + 1))
if jq -e '.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command | select(test("browser-snapshot-credential-guard"))' \
     "$PLUGIN_MANIFEST" >/dev/null 2>&1; then
  ok 'shipped registration selects the Bash matcher'
else
  bad 'shipped registration must use matcher "Bash"'
fi

cases=$((cases + 1))
if jq -e '.hooks.PreToolUse[]?.hooks[]?.command | select(test("browser-snapshot-credential-guard"))' \
     "$LOCAL_SETTINGS" >/dev/null 2>&1; then
  ok 'registered in this checkout (.claude/settings.json)'
else
  bad 'NOT registered in .claude/settings.json'
fi

cases=$((cases + 1))
if grep -q 'browser-snapshot-credential-guard' "$README" 2>/dev/null; then
  ok 'documented in .claude/hooks/README.md'
else
  bad 'missing a row in .claude/hooks/README.md'
fi

printf '\n%d passed, %d failed, %d cases\n' "$pass" "$fail" "$cases"
if [[ $((pass + fail)) -ne $cases ]]; then
  printf 'VACUITY: pass+fail (%d) != cases (%d)\n' "$((pass + fail))" "$cases" >&2; exit 1
fi
if [[ $cases -lt $MIN_ASSERTIONS ]]; then
  printf 'VACUITY: %d cases below floor %d\n' "$cases" "$MIN_ASSERTIONS" >&2; exit 1
fi
[[ $fail -eq 0 ]] || exit 1
exit 0
