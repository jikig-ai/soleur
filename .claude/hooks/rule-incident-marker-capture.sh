#!/usr/bin/env bash
# Rule-application marker capture — ADR-179 decision 9 (#7450).
#
# Wired as a PostToolUse hook on the `Bash` matcher in .claude/settings.json.
#
# WHY THIS EXISTS. Twenty sites in customer-facing payload markdown used to run
#     source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh" && emit_incident …
# to record that a rule had been applied. `source` executes into the CURRENT shell, and
# `review/SKILL.md` instructs `gh pr checkout`, so on the review path that git root is the
# CONTRIBUTOR's tree: a same-named file in a hostile PR ran in the reviewer's shell.
#
# ${CLAUDE_PLUGIN_ROOT} cannot anchor the target, because incidents.sh is deliberately NOT
# payload — it writes Soleur's own rule-corpus telemetry, which ADR-179 decision 4 reason 1
# says "does not and should not exist on a customer machine". Both instruments ADR-179
# sanctions were therefore blocked, and the CTO ruling dissolved that by rejecting the
# framing: decision 1 governs PATHS, and nothing requires a capability to be expressed as
# a path. So the payload now emits an INERT MARKER and this monorepo-only hook performs
# the privileged emission. There is no operand to shadow, which is why this satisfies
# decision 5 (fail-closed in isolation) more completely than any other site governed by
# that ADR: under line-wise extraction the payload's invocation degrades to printing a
# string.
#
# POSTTOOLUSE, NOT PRETOOLUSE — deliberate, do not switch. PreToolUse counts INTENT;
# the construction it replaces counted EXECUTION. Switching would over-count relative to
# every row already in the corpus and break comparability across the migration.
#
# THE MARKER IS UNTRUSTED INPUT. It is emitted by payload markdown, and on the review path
# that markdown is contributor-writable. So the rule id is validated against a CLOSED
# corpus and the note is sanitised to a fixed charset before either reaches jq. That is
# the whole point of the design: the worst case a hostile PR can now achieve drops from
# arbitrary code execution in the reviewer's shell to a REJECTED TELEMETRY ROW.
#
# Kill-switch: SOLEUR_DISABLE_RULE_MARKER_CAPTURE=1
# Fire-and-forget: always exits 0, never blocks a tool call.

set -uo pipefail

[[ "${SOLEUR_DISABLE_RULE_MARKER_CAPTURE:-}" == "1" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$CMD" ]] || exit 0
# Cheap reject before any parsing work — the overwhelming majority of Bash calls
# carry no marker at all.
[[ "$CMD" == *SOLEUR_RULE_APPLIED* ]] || exit 0

# Repo root. CLAUDE_PROJECT_DIR is set by the harness for hook processes (the wiring in
# settings.json interpolates it), which is what makes it safe here — it is supplied by
# the harness, not by the tree under review. The fallback is this hook's OWN location,
# which is layout-invariant and likewise not CWD-derived. `git rev-parse` is deliberately
# absent: it is the construct this hook exists to remove.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)}"
[[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]] || exit 0

RULES_FILE="$REPO_ROOT/AGENTS.rules.md"
INCIDENTS_LIB="$REPO_ROOT/.claude/hooks/lib/incidents.sh"
[[ -f "$INCIDENTS_LIB" ]] || exit 0

# Rule-id validation, MIRRORING scripts/rule-metrics-aggregate.sh (#7853). This used to be
# a hand-maintained allowlist of synthetic prefixes (te-, gdpr-gate-, context-reviewed-,
# net-issue-flow, cost-of-filing-, plus one exact id) copied from that aggregator, and the
# two drifted whenever either side gained an emitter. Both now key on ONE fact instead:
# does the id CLAIM to be an AGENTS.md rule?
#
#   - No section prefix  -> it never claimed corpus membership. The aggregator drops such
#     ids from its orphan gate structurally, so accepting one here can never manufacture
#     an orphan, and a new hook needs no edit on either side.
#   - Section-prefixed    -> it claims to be a rule, so it must BE one: the closed-corpus
#     grep against AGENTS.rules.md still governs, unchanged.
#
# The invariant this preserves is directional: an id accepted here must be one the
# aggregator would not call an orphan. One rejected here is simply never recorded, which
# is why the strict direction is safe (a retired id is exempt there and rejected here).
#
# SECURITY NOTE, stated rather than glossed. The marker is contributor-writable, so this
# widening does enlarge what a hostile PR can land: previously an attacker-chosen id had
# to sit under one of five reserved prefixes, now any shape-valid id with no section
# prefix is accepted. The bound is unchanged in KIND — an unattributed telemetry row with
# a sanitised, 160-char-capped note, which no rule-metrics consumer reads and which the
# orphan gate ignores by construction. What the closed corpus still buys, and what case 2
# of the companion suite fixtures, is that an attacker CANNOT forge a row attributed to a
# rule: a `cq-`/`hr-`/`wg-`-prefixed id absent from AGENTS.rules.md is still rejected.
#
# The companion assertion in .claude/hooks/rule-incident-marker-capture.test.sh pins that
# the section-prefix regex below is shared verbatim with the aggregator.
_valid_rule() {
  local r="$1"
  [[ "$r" =~ ^[a-z0-9][a-z0-9-]{2,79}$ ]] || return 1
  # SHARED SECTION-PREFIX REGEX — keep byte-identical with the test() call in
  # scripts/rule-metrics-aggregate.sh; the companion suite greps for this literal.
  [[ "$r" =~ ^(hr|wg|cq|rf|pdr|cm)- ]] || return 0
  # Closed corpus: an id that claims to be a rule must be a real AGENTS.rules.md rule.
  grep -qF "[id: ${r}]" "$RULES_FILE" 2>/dev/null
}

# shellcheck source=/dev/null
source "$INCIDENTS_LIB" 2>/dev/null || exit 0
declare -F emit_incident >/dev/null 2>&1 || exit 0

# One marker per line. The note runs to the closing quote of the emitting `echo`, or to
# end of line — never across it, so a second marker cannot be swallowed by the first.
while IFS= read -r marker; do
  [[ -n "$marker" ]] || continue
  rule="${marker#*rule=}"
  rule="${rule%% *}"
  note="${marker#*note=}"

  _valid_rule "$rule" || continue

  # Sanitise to a fixed charset before this reaches jq inside emit_incident. Mirrors the
  # allowlist already committed in incidents.sh's own _emit_drop_sentinel.
  note="$(printf '%s' "$note" | tr -cd '[:alnum:][:space:]._,:;()/@#|<>=+-' 2>/dev/null | tr -s '[:space:]' ' ')"
  note="${note:0:160}"

  emit_incident "$rule" applied "$note" "" PostToolUse >/dev/null 2>&1 || true
done < <(grep -oE "SOLEUR_RULE_APPLIED rule=[A-Za-z0-9._-]+ note=[^'\"]*" <<<"$CMD" 2>/dev/null || true)

exit 0
