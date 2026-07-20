#!/usr/bin/env bash
#
# net-issue-flow.sh — BLOCKING per-PR net-issue-flow gate.
#
# Contract
# --------
#   usage:  net-issue-flow.sh [PR_NUMBER]
#   stdout: a human-readable CLOSING / FILED / NET block, always emitted,
#           enumerating the actual issue numbers behind each count.
#   exit 0: NET <= 0, or an override is present, or a transient failure
#           (fail-OPEN — see below).
#   exit 1: NET > 0 and no override. THE BLOCKING PATH.
#
# Threshold
# ---------
# Blocks at NET > 0: every PR must close at least as many issues as it files.
# NOT NET > +1. At the measured ~132 merged PRs/week, a +1 allowance authorizes
# +132 issues/week against an observed +144/week — it would cut backlog growth
# by ~8% and then report success. NET > 0 is the only threshold that flattens
# the queue. Pinned by case 4 of plugins/soleur/test/net-issue-flow.test.sh.
#
# Why the FILED query looks the way it does
# -----------------------------------------
# Four independently-measured defects each make a BLOCKING gate silently
# always-pass — which is strictly worse than the advisory surface it replaces,
# because it also carries the authority of having passed:
#   1. `--search` returns EMPTY cross-repo under a GitHub App / action token.
#   2. `gh issue list` defaults to --limit 30 (measured 30 returned vs 271 real).
#   3. The `(Ref|Closes|Fixes) #N` keyword filter matches only ~40% of real
#      filings; a bare `#N` mention is the common shape.
#   4. `--label deferred-scope-out` covers only ~8% of what PRs actually file.
# So: no --search, --limit 500, --state all, no label filter, bare-#N matching,
# and a client-side full-ISO createdAt comparison (never `cut -c1-10`, which
# collapses same-day precision).
#
# Override
# --------
# Escape hatch is deliberate, not default. Architectural-pivot deferrals can be
# legitimately net-positive:
#   - PR body carries `<!-- gate-override: net-issue-flow -->` plus a one-line
#     justification per filed issue, or
#   - SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1 in the environment.
#
# Fail-open, not fail-silent
# --------------------------
# A gh/API error yields exit 0 so an outage cannot wedge every merge — but each
# fail-open emits telemetry via emit_incident. A gate that fails open silently
# is indistinguishable from a gate that passes.
#
# The fail-open event_type is `warn`, NOT `transient`: rule-metrics-aggregate.sh
# counts only deny/bypass/applied/warn, so a `transient` row would increment
# nothing — and the operator could not tell "gate never fired" from "gate
# fail-opened on every invocation", which is precisely the claim above.
#
set -uo pipefail
export LC_ALL=C

MARKER='<!-- gate-override: net-issue-flow -->'
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Telemetry. Never wrap emit_incident in $(...) or a pipe — its output IS the
# telemetry write.
_incidents="$REPO_ROOT/.claude/hooks/lib/incidents.sh"
if [[ -r "$_incidents" ]]; then
  # shellcheck disable=SC1090
  source "$_incidents" 2>/dev/null || true
fi
_emit() {
  if declare -F emit_incident >/dev/null 2>&1; then
    emit_incident "net-issue-flow" "$1" "$2" || true
  fi
}

_fail_open() {
  printf '\n'
  printf 'net-issue-flow: TRANSIENT — could not compute net flow (%s).\n' "$1"
  printf '  Failing OPEN so an API outage cannot wedge every merge.\n'
  printf '  This is recorded as telemetry, not swallowed.\n'
  _emit warn "net-issue-flow fail-open: $1"
  exit 0
}

if [[ "${SOLEUR_SKIP_NET_ISSUE_FLOW_GATE:-0}" == "1" ]]; then
  printf 'net-issue-flow: SKIPPED via SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1.\n'
  _emit bypass "net-issue-flow skipped via env"
  exit 0
fi

PR_NUMBER="${1:-}"
if [[ -z "$PR_NUMBER" ]]; then
  PR_NUMBER="$(gh pr view --json number --jq .number 2>/dev/null)" \
    || _fail_open "could not resolve PR number"
fi
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || _fail_open "PR number is not a positive integer: '$PR_NUMBER'"

PR_BODY="$(gh pr view "$PR_NUMBER" --json body --jq .body 2>/dev/null)" \
  || _fail_open "could not read PR #${PR_NUMBER} body"

PR_CREATED_AT="$(gh pr view "$PR_NUMBER" --json createdAt --jq .createdAt 2>/dev/null)" \
  || _fail_open "could not read PR #${PR_NUMBER} createdAt"
[[ -n "$PR_CREATED_AT" ]] || _fail_open "PR #${PR_NUMBER} createdAt was empty"

# --- CLOSING: issues this PR closes via close-keywords in its body -----------
CLOSING_NUMS="$(printf '%s\n' "$PR_BODY" \
  | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' \
  | grep -oE '[0-9]+' \
  | sort -un || true)"
CLOSING=0
[[ -n "$CLOSING_NUMS" ]] && CLOSING="$(printf '%s\n' "$CLOSING_NUMS" | grep -c . || true)"

# --- FILED: issues created after this PR that bare-reference it --------------
# No --search, no label filter, --state all, --limit 500. See header.
ISSUES_JSON="$(gh issue list --state all --limit 500 --json number,body,createdAt 2>/dev/null)" \
  || _fail_open "could not list issues"
[[ -n "$ISSUES_JSON" ]] || _fail_open "issue list returned empty"

FILED_NUMS="$(printf '%s' "$ISSUES_JSON" | jq -r \
  --arg pr "$PR_NUMBER" \
  --arg since "$PR_CREATED_AT" \
  '[ .[]
     | select((.createdAt // "") >= $since)
     | select((.body // "") | test("(^|[^0-9A-Za-z])#" + $pr + "([^0-9]|$)"))
     | .number ] | sort | unique | .[]' 2>/dev/null)" \
  || _fail_open "could not parse issue list"
FILED=0
[[ -n "$FILED_NUMS" ]] && FILED="$(printf '%s\n' "$FILED_NUMS" | grep -c . || true)"

NET=$(( FILED - CLOSING ))

# --- Display: always emitted, enumerating the actual numbers -----------------
_fmt() { if [[ -z "$1" ]]; then printf 'none'; else printf '%s' "$(printf '#%s ' $1 | sed 's/ $//')"; fi; }
printf '\n'
printf 'PR #%s net-issue-flow:\n' "$PR_NUMBER"
printf '  Closing: %s  (%s)\n' "$CLOSING" "$(_fmt "$CLOSING_NUMS")"
printf '  Filing:  %s  (%s)\n' "$FILED" "$(_fmt "$FILED_NUMS")"
printf '  Net:     %+d  (positive = backlog growth)\n' "$NET"

if [[ "$NET" -le 0 ]]; then
  printf '\nnet-issue-flow: PASS (net <= 0).\n'
  _emit applied "net-issue-flow pass net=${NET} pr=${PR_NUMBER}"
  exit 0
fi

# --- NET > 0: override or block ---------------------------------------------
# Strip fenced code blocks before the marker match, mirroring the soak gate's
# corpus handling. The BLOCKED message below PRINTS the literal marker, so an
# agent that pastes a gate failure into the PR description as context would
# otherwise smuggle in its own override — reported as OVERRIDDEN with a bypass
# event, while nothing in the body reads as a deliberate decision. Same
# self-override class the hook header guards against for spec files, via a
# different corpus path.
PR_BODY_SCAN="$(printf '%s\n' "$PR_BODY" | awk '
  /^[[:space:]]*```/ { in_fence = !in_fence; next }
  !in_fence { print }
')"

if printf '%s' "$PR_BODY_SCAN" | grep -qF -- "$MARKER"; then
  printf '\nnet-issue-flow: OVERRIDDEN via the gate-override marker in the PR body.\n'
  printf '  Net is +%d; the override is recorded as a deliberate decision.\n' "$NET"
  _emit bypass "net-issue-flow overridden net=${NET} pr=${PR_NUMBER}"
  exit 0
fi

printf '\n'
printf 'net-issue-flow: BLOCKED — this PR is net-positive (+%d) on the issue queue.\n' "$NET"
printf '\n'
printf 'Every PR must close at least as many issues as it files. Filing is free;\n'
printf 'closing is expensive, and the queue grows by roughly the difference.\n'
printf '\n'
printf 'Resolve via one of:\n'
printf '  (a) Fix inline — fold the filed work into THIS PR. The cost-of-filing\n'
printf '      auto-flip (<=100 lines AND <=4 files) already covers most of it.\n'
printf '  (b) Close something — if a filed issue supersedes an open one, close it.\n'
printf '  (c) Override — add to the PR body:\n'
printf '        %s\n' "$MARKER"
printf '      plus a one-line justification per filed issue, or run with\n'
printf '      SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1.\n'
_emit deny "net-issue-flow blocked net=${NET} pr=${PR_NUMBER}"
exit 1
