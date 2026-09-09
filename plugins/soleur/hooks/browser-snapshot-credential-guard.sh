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

# Fast path, before any subprocess. The deny predicate requires the literal
# `agent-browser`, and JSON escaping cannot alter it, so it survives verbatim in
# the envelope. This short-circuits ~every Bash call in a session without
# spawning jq -- which matters because this hook is registered on the Bash
# matcher and also loads on the hosted platform surface, so it runs on EVERY
# Bash tool call, not only on browser ones.
[[ "$INPUT" == *agent-browser* ]] || exit 0

# The redactor is anchored on its FILENAME, not on a bare word like "python3" or
# "redact". The assertion is on the anchor: a look-alike command name that does
# not redact must not satisfy the allow-predicate.
REDACTOR_ANCHOR='redact-a11y-snapshot'

# Portable remedy path. `${CLAUDE_PLUGIN_ROOT}` resolves to the installed plugin
# on a customer machine, where a repo-relative path does not exist at all -- the
# operator would get `python3: can't open file`, and the natural next move is the
# screenshot escape, which this very message says is unsafe for the one class
# with a recorded incident.
REDACTOR_CMD='python3 "${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}"/skills/agent-browser/scripts/redact-a11y-snapshot.py'

# `jq` unusable is NOT the same condition as a malformed envelope, and must not
# get the same silent pass. Without this branch a machine whose jq is missing OR
# BROKEN runs with the guard entirely off, forever, with no signal -- while
# SKILL.md tells the agent the gate exists, so its own reasoning defers to a
# control that is not there.
#
# Detected by RESULT, not by `command -v`: a jq that is present and exits
# non-zero (wrong build, missing shared library, exec-format error) passes a
# presence check and then fails exactly like an absent one. The first revision
# of this branch used `command -v` and the suite caught it.
jq_rc=0
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || jq_rc=$?
if [[ $jq_rc -ne 0 ]]; then
  if grep -qE 'agent-browser([[:space:]]+[^|;&]*)?[[:space:]]snapshot\b' <<<"$INPUT" 2>/dev/null \
     && ! grep -qF "$REDACTOR_ANCHOR" <<<"$INPUT" 2>/dev/null; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED (degraded mode): jq is unusable on this machine (exit %s), so this hook cannot parse the tool envelope and fell back to a raw scan of stdin. That scan sees an unrouted `agent-browser snapshot`. Install a working jq, or route the snapshot through the redactor: %s"}}\n' "$jq_rc" "$REDACTOR_CMD"
  fi
  exit 0
fi

[[ "$TOOL" == "Bash" ]] || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -z "$CMD" ]] && exit 0

# Split into sequential segments. A pipe is NOT a separator -- it is what carries
# a snapshot into the redactor, so it must stay inside the segment being judged.
#
# A bare `&` IS a separator, and omitting it was a live bypass: the whole command
# stayed one segment, the segment contained the anchor, and an unrouted second
# invocation rode through. ADR-213 and the Article 30 register both assert this
# guard is judged per shell segment, so that claim was false as written.
#
# `2>&1` is protected first -- its `&` is a redirect, not a separator, and the
# approved form depends on it.
SPLIT="$(printf '%s' "$CMD" \
  | sed -E 's/>&/\x01/g' \
  | sed -E 's/(&&|\|\||;|&)/\n/g' \
  | sed -E 's/\x01/>&/g')"

offending=0
reason_detail=''
while IFS= read -r seg; do
  # HERESTRING throughout (#6992/#7024): `grep -q` on a PIPE can die of SIGPIPE
  # under pipefail and read as "no match", which in a policy gate is fail-OPEN.
  #
  # `snapshot` is word-anchored, so `screenshot` is never caught here.
  grep -qE 'agent-browser([[:space:]]+[^|;&]*)?[[:space:]]snapshot\b' <<<"$seg" 2>/dev/null || continue

  # The allow-predicate is NOT "the anchor appears somewhere". Substring
  # presence was satisfied by a trailing COMMENT, and by a `tee` that writes the
  # unredacted tree to disk on its way to the redactor -- which is precisely the
  # sink this hook's own deny text names.
  if ! grep -qE '\|[^|]*'"$REDACTOR_ANCHOR" <<<"$seg" 2>/dev/null; then
    offending=1
    reason_detail='the redactor is not downstream of a pipe in this command'
    break
  fi
  if grep -qE '(^|[|[:space:]])tee([[:space:]]|$)' <<<"$seg" 2>/dev/null; then
    offending=1
    reason_detail='`tee` writes the UNREDACTED snapshot to disk before the redactor sees it'
    break
  fi
  # A file redirect of the snapshot itself, e.g. `snapshot -i > raw.txt`.
  # `2>&1` was protected above and does not match.
  if grep -qE '[^0-9<>]>[^&|]' <<<"$seg" 2>/dev/null; then
    offending=1
    reason_detail='this command redirects the snapshot to a file, which bypasses the redactor'
    break
  fi
done <<<"$SPLIT"

[[ $offending -eq 1 ]] || exit 0

reason="BLOCKED: this \`agent-browser snapshot\` is not routed through the credential redactor — ${reason_detail}.

An accessibility snapshot serializes the VALUE of input fields. A value you never typed — a password manager's autofill, a static \`value=\`, or a generated-credential panel — is rendered into the transcript and into any snapshot file written to disk. Nothing about the call looks credential-adjacent, which is why this is a gate and not a guideline (#7947).

Route it through the redactor:

  agent-browser snapshot -i 2>&1 | ${REDACTOR_CMD}

Or take a screenshot instead, which is safe for a \`type=password\` field — the browser renders it as dots.

MEASURED CAVEAT, because the obvious advice is wrong here: a screenshot is NOT safe for a generated-credential panel (a readonly \`type=text\` box named \"Token\", \"API key\", …). The browser renders those in clear, so the screenshot leaks exactly as the snapshot does. On a page showing a freshly-minted credential, capture neither — read the value with \`agent-browser get value <sel>\` into a file and shred it.

The redactor is defense-in-depth on one sink. It does not make snapshotting a credential page safe: it cannot see a localised field name, a credential outside a text-input role, or a value split across segmented inputs."

jq -nc --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' 2>/dev/null

exit 0
