#!/usr/bin/env bash
# PreToolUse hook on Bash.
# Denies an `agent-browser ... snapshot` that is not routed through the
# accessibility-snapshot redactor.
#
# WHY (#7947, measured -- see
# knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md):
# an accessibility snapshot serializes the VALUE of input fields. A value the
# agent never supplied -- a password manager's autofill, a static value=, a JS
# assignment, or a generated-credential panel -- is rendered into the transcript
# and into any snapshot file written to disk. Nothing about the call looks
# credential-adjacent: the natural reason to snapshot a login page is to find
# out whether the flow advanced.
#
# Measured, and this is why the hook exists rather than a prose rule:
#   * agent-browser 0.22.3 masks type=password (bullets) but renders a readonly
#     type=text credential panel -- the "Token" class -- in CLEAR. That class
#     has already fired in this repo (2026-05-19 Sentry token scope probe).
#   * The Playwright MCP renders BOTH in clear.
#
# This hook covers the Bash path only. Property P7 ("the guards hold without the
# acting agent having to remember them") is achieved HERE and is NOT achieved on
# the Playwright-MCP runtime path, where the interceptor is deferred. That gap is
# stated rather than implied.
#
# Disposition is DENY, not rewrite: ADR-162 permits exactly one PreToolUse
# rewriter and grep-rewrite.sh holds it. Two hooks emitting updatedInput for the
# same call have undefined precedence and one rewrite is silently discarded.
#
# Fail-open by construction: any parse failure exits 0 with no decision. A hook
# that hard-fails on a malformed envelope would block every Bash call.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$TOOL" == "Bash" ]] || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -z "$CMD" ]] && exit 0

# The redactor is anchored on its FILENAME, not on a bare word like "python3" or
# "redact". The assertion is on the anchor: a look-alike command name that does
# not redact must not satisfy the allow-predicate.
REDACTOR_ANCHOR='redact-a11y-snapshot'

# Split into sequential segments on && || ; and newline. A pipe is NOT a
# separator -- it is what carries a snapshot into the redactor, so it must stay
# inside the segment being judged.
#
# Judging per segment is what catches the chained form where only the first
# invocation is piped: a whole-command grep for the redactor would see one hit
# and allow both.
mapfile -t SEGMENTS < <(printf '%s' "$CMD" | sed -E 's/(\&\&|\|\||;)/\n/g')

offending=0
for seg in "${SEGMENTS[@]}"; do
  # HERESTRING throughout (#6992/#7024, .claude/hooks/grep-q-pipe-guard.test.sh):
  # `grep -q` on a PIPE can die of SIGPIPE under pipefail and read as "no match",
  # which in a policy gate is fail-OPEN. A herestring has no producer to kill.
  #
  # `snapshot` is word-anchored. "screenshot" does not contain it, so the
  # screenshot escape route is never caught by this predicate.
  grep -qE 'agent-browser([[:space:]]+[^|;&]*)?[[:space:]]snapshot\b' <<<"$seg" 2>/dev/null || continue

  # This segment takes a snapshot. Is it routed through the redactor?
  if grep -qF "$REDACTOR_ANCHOR" <<<"$seg" 2>/dev/null; then
    continue
  fi
  offending=1
  break
done

[[ $offending -eq 1 ]] || exit 0

reason="BLOCKED: this \`agent-browser snapshot\` is not routed through the credential redactor.

An accessibility snapshot serializes the VALUE of input fields. A value you never typed — a password manager's autofill, a static \`value=\`, or a generated-credential panel — is rendered into the transcript and into any snapshot file written to disk. Nothing about the call looks credential-adjacent, which is why this is a gate and not a guideline (#7947).

Route it through the redactor:

  agent-browser snapshot -i 2>&1 | python3 plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py

Or take a screenshot instead, which is safe for a \`type=password\` field — the browser renders it as dots.

MEASURED CAVEAT, because the obvious advice is wrong here: a screenshot is NOT safe for a generated-credential panel (a readonly \`type=text\` box named \"Token\", \"API key\", …). The browser renders those in clear, so the screenshot leaks exactly as the snapshot does. On a page showing a freshly-minted credential, capture neither — read the value with \`agent-browser get value <sel>\` into a file and shred it.

The redactor is defense-in-depth on one sink. It does not make snapshotting a credential page safe: it cannot see a localised field name, a credential outside a text-input role, or a value split across segmented inputs."

jq -nc --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null

exit 0
