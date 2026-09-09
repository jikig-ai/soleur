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

# Every .claude/hooks/*.test.sh sources this, enforced by
# incident-sandbox-coverage.test.sh. It is inert for a suite that never emits an
# incident, and the population is deliberately ALL suites rather than "those that
# emit" -- a population derived by naming convention silently excludes whatever
# does not follow it.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

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
# 3 deny + 4 allow + 5 registration + 2 reason-content rows,
# + 7 review rows (round 1) + 5 review rows (round 2) = 26.
# MIN_ASSERTIONS is bound ADJACENT to the floor block at the bottom of this
# file, not here: scripts/guard-vacuity-floor.test.sh builds its mutant by
# slicing the floor block and widening BACKWARD over contiguous simple
# assignments only. A threshold declared up here is unbound in that slice, so
# the mutant dies on `set -u` BEFORE reaching the floor and the floor is scored
# unconstructible -- which is indistinguishable from a floor that does not fire.

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
  local label="$1" cmd="$2" out rc
  cases=$((cases + 1))
  out="$(envelope "$cmd" | bash "$HOOK" 2>/dev/null)"; rc=$?
  # rc and emptiness are both asserted: a hook that ERRORS on every ordinary
  # Bash call in the session produces no decision, which a `!= deny` test reads
  # as a clean allow.
  if [[ $rc -ne 0 ]]; then
    bad "$label — hook exited $rc on an allowed command"
  elif [[ -n "$out" ]]; then
    bad "$label — expected no decision, got: ${out:0:60}"
  else
    ok "$label"
  fi
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

# ---- Review rows (round 1): every one was a live bypass ----
RED='python3 "${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}"/skills/agent-browser/scripts/redact-a11y-snapshot.py'

# `tee` writes the UNREDACTED tree to disk on its way to the redactor -- the
# exact sink the deny text names. Substring-presence allowed it.
assert_deny 'tee to disk alongside the redactor' \
  "agent-browser snapshot -i | tee /tmp/leak.txt | $RED"

# A bare `&` is a shell separator. Omitting it from the splitter left the whole
# command as ONE segment, so the anchor from the first invocation covered an
# unrouted second one. ADR-213 and the Art.30 register both assert per-segment
# judgement, so this was a false claim in a legal record until fixed.
assert_deny 'bare & separator, second invocation unrouted' \
  "agent-browser snapshot -i | $RED & agent-browser snapshot -i > /tmp/leak.txt"

# A trailing COMMENT satisfied a bare substring check.
assert_deny 'comment mentioning the redactor does not satisfy the guard' \
  'agent-browser snapshot -i > /tmp/leak.txt # redact-a11y-snapshot'

# A file redirect bypasses the pipe entirely.
assert_deny 'redirect to a file' 'agent-browser snapshot -i > /tmp/leak.txt'

# Flags may precede the verb.
assert_deny '--headed form' 'agent-browser --headed snapshot -i'

# The remedy must resolve on a CUSTOMER machine. A repo-relative path does not
# exist there, so the operator gets `can't open file` and the only remaining
# move is the screenshot the same message says is unsafe.
cases=$((cases + 1))
portable="$(envelope 'agent-browser snapshot -i' | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
if [[ "$portable" == *'CLAUDE_PLUGIN_ROOT'* ]]; then
  ok 'deny reason prescribes a plugin-root-relative path (resolves on a customer machine)'
else
  bad 'deny reason prescribes a repo-relative path — unresolvable on every customer install'
fi

# `jq` absent is not the same condition as a malformed envelope. Without a
# degraded branch the guard is silently off, forever, on that machine.
cases=$((cases + 1))
JQSHIM="$(mktemp -d)"
# Owning trap (ADR-129): the explicit `rm -rf` below only runs if we reach it,
# and a `bad ... exit` between here and there would leak the shim directory.
trap 'rm -rf "$JQSHIM"' EXIT
printf '#!/bin/sh\nexit 127\n' > "$JQSHIM/jq"; chmod +x "$JQSHIM/jq"
degraded="$(envelope 'agent-browser snapshot -i' | PATH="$JQSHIM:$PATH" bash "$HOOK" 2>/dev/null)"
rm -rf "$JQSHIM"
if [[ "$degraded" == *'"deny"'* && "$degraded" == *'degraded'* ]]; then
  ok 'jq absent: denies in degraded mode rather than silently allowing'
else
  bad 'jq absent: the guard silently allows (guard off, no signal, on a machine SKILL.md tells the agent is protected)'
fi

# ---- Review rows (round 2): separator cardinality and the stated contract ----

# Four separators, two exercised. `;` and `||` had no row, so truncating the
# splitter to `&&|&` survived while both became live bypasses.
assert_deny 'separator: ; with an unrouted second invocation' \
  "agent-browser snapshot -i | $RED ; agent-browser snapshot --json"
assert_deny 'separator: || with an unrouted second invocation' \
  "agent-browser snapshot -i | $RED || agent-browser snapshot --json"

# The header states "any parse failure exits 0 with no decision" -- a contract
# with zero coverage until now, so hard-failing on a malformed envelope (which
# would block EVERY Bash call in the session) survived.
cases=$((cases + 1))
empty_rc=0; printf '' | bash "$HOOK" >/dev/null 2>&1 || empty_rc=$?
cases2_rc=0; printf 'not json at all' | bash "$HOOK" >/dev/null 2>&1 || cases2_rc=$?
if [[ $empty_rc -eq 0 && $cases2_rc -eq 0 ]]; then
  ok 'malformed/empty envelope: exits 0 with no decision (does not block every Bash call)'
else
  bad "malformed envelope must fail open (empty rc=$empty_rc, non-json rc=$cases2_rc)"
fi

cases=$((cases + 1))
ks="$(envelope 'agent-browser snapshot -i' | SOLEUR_DISABLE_SNAPSHOT_GUARD=1 bash "$HOOK" 2>/dev/null)"
if [[ -z "$ks" ]]; then
  ok 'kill-switch: SOLEUR_DISABLE_SNAPSHOT_GUARD=1 disables the deny'
else
  bad 'kill-switch did not disable the guard'
fi

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

# Exact-filename anchor here too. The shipped-manifest row was hardened in
# round 1 and these two were left on the substring form, so a rename to
# `...-guard-TYPO.sh` in BOTH this file and the README passed while this
# checkout's own registration pointed at a script that does not exist.
cases=$((cases + 1))
LOCAL_CMD="$(jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty' "$LOCAL_SETTINGS" 2>/dev/null \
  | grep -F 'browser-snapshot-credential-guard' || true)"
if [[ "$LOCAL_CMD" == *"/hooks/browser-snapshot-credential-guard.sh" ]]; then
  ok 'registered in this checkout (.claude/settings.json) with the exact filename'
else
  bad "NOT registered in .claude/settings.json with the exact filename (got '${LOCAL_CMD:-<none>}')"
fi

cases=$((cases + 1))
LOCAL_RESOLVED="${LOCAL_CMD//\"\$CLAUDE_PROJECT_DIR\"/$REPO_ROOT}"
if [[ -n "$LOCAL_CMD" && -x "$LOCAL_RESOLVED" ]]; then
  ok 'this checkout registration resolves to an existing executable'
else
  bad "this checkout registration does not resolve (tried '${LOCAL_RESOLVED:-<none>}')"
fi

cases=$((cases + 1))
if grep -q 'browser-snapshot-credential-guard\.sh' "$README" 2>/dev/null; then
  ok 'documented in .claude/hooks/README.md'
else
  bad 'missing a row in .claude/hooks/README.md'
fi

# ---- Ship-gate consult rows: two live redirect bypasses, one portability
# defect, and two legitimate forms the guard was wrongly denying. ----

# F6 -- the old redirect pattern was `[^0-9<>]>[^&|]`, which excluded a DIGIT
# before the `>` and a `|` after it. Both of these were measured ALLOWED: the
# raw tree went to a file and the redactor saw a copy.
assert_deny 'F6a fd-numbered redirect `1>` writes the raw tree to a file' \
  "agent-browser snapshot -i 1>/tmp/leak.txt | ${RED}"
assert_deny 'F6b clobber redirect `>|` writes the raw tree to a file' \
  "agent-browser snapshot -i >|/tmp/leak.txt | ${RED}"
assert_deny 'F6c append redirect `>>` writes the raw tree to a file' \
  "agent-browser snapshot -i >>/tmp/leak.txt | ${RED}"

# The other direction: a sink DOWNSTREAM of the redactor handles redacted
# bytes and must not be denied. Without the prefix scoping these were denied,
# which pushes an operator toward the unrouted form to get their file.
assert_allow 'F6d redirect AFTER the redactor is redacted output, not a leak' \
  "agent-browser snapshot -i | ${RED} > /tmp/safe.txt"
assert_allow 'F6e tee AFTER the redactor is redacted output, not a leak' \
  "agent-browser snapshot -i | ${RED} | tee /tmp/safe.txt"

# F4 -- the segment splitter must not depend on GNU sed. `\n` in a sed
# REPLACEMENT and `\x01` in a sed PATTERN are GNU extensions; under BSD sed
# (the macOS default) nothing splits, the whole command becomes one segment,
# and every chained bypass below is allowed while this suite stays green on
# Linux. That is unreproducible on this host, so it is pinned at the source:
# the splitter must not be a sed pipeline using those escapes.
cases=$((cases + 1))
splitter="$(sed -n '/^SPLIT=/,/^)\{0,1\}.\{0,2\}$/p' "$HOOK" 2>/dev/null | head -20)"
if [[ -z "$splitter" ]]; then
  bad 'F4 could not locate the SPLIT= assignment to check it for GNU-only escapes'
elif grep -qE "sed .*\\\\(n|x[0-9a-fA-F])" <<<"$splitter"; then
  bad 'F4 segment splitter uses a GNU-only sed escape (\n or \xNN) -- inert on BSD sed'
else
  ok 'F4 segment splitter avoids GNU-only sed escapes (portable to BSD sed)'
fi

# F4b -- and the behaviour that portability protects: `>&` must survive the
# split round-trip intact. In awk gsub an unescaped `&` in the replacement
# means "the matched text", so a missing backslash silently corrupts `2>&1`
# into `2>1` -- which would turn the approved form into a file redirect.
cases=$((cases + 1))
rt="$(printf '%s' 'a snapshot -i 2>&1 | red && b snapshot' | awk '
  { gsub(/>&/, "\001"); gsub(/&&|\|\||;|&/, "\n"); gsub(/\001/, ">\\&"); print }' | head -1)"
if [[ "$rt" == *'2>&1'* ]]; then
  ok 'F4b splitter round-trip preserves `2>&1` (the & is escaped in the replacement)'
else
  bad "F4b splitter round-trip corrupted the redirect: got '${rt}'"
fi

# F2 -- the `diff snapshot` subcommand. This is the surface where the two
# controls combined into a hole: the hook ALLOWED the routed form (the anchor
# is after a pipe) while the redactor was a no-op on it, so the guard admitted
# a command that redacted nothing. The redactor half is fixed in its own suite;
# these pin that the hook covers the subcommand at all.
assert_deny 'F2c unrouted `agent-browser diff snapshot`' \
  'agent-browser diff snapshot'
assert_deny 'F2d unrouted `agent-browser diff snapshot --json`' \
  'agent-browser diff snapshot --json'

printf '\n%d passed, %d failed, %d cases\n' "$pass" "$fail" "$cases"
if [[ $((pass + fail)) -ne $cases ]]; then
  printf '[FATAL] vacuity accounting: pass+fail (%d) != cases (%d)\n' "$((pass + fail))" "$cases" >&2; exit 1
fi
MIN_ASSERTIONS=35
if [[ $cases -lt $MIN_ASSERTIONS ]]; then
  printf '[FATAL] vacuity floor: only %d cases executed, expected at least %d\n' "$cases" "$MIN_ASSERTIONS" >&2; exit 1
fi
[[ $fail -eq 0 ]] || exit 1
exit 0
