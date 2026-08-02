#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` and `gh pr merge` when the PR is
# net-positive on the issue queue (NET > 0) with no override.
#
# Mechanical twin of ship/SKILL.md §"Net-Issue-Flow Gate (blocking)". Closes the
# bypass class where the agent skips /ship Phase 5.5 and goes straight to
# `gh pr ready` / `gh pr merge`.
#
# Why: the net-issue-flow surface ran ADVISORY for three months and was
# trivially skipped. Measured over the 7 days to 2026-07-20: 269 issues filed
# against 132 merged PRs, 125 closed, queue +144/week to 1,024 open. An
# advisory display of that asymmetry does not correct it.
#
# ALL counting logic lives in plugins/soleur/skills/ship/scripts/net-issue-flow.sh.
# This hook delegates and translates the exit code — it does NOT re-implement
# the query. Two implementations of the same threshold would drift, and the
# drifting copy would be the one that runs.
#
# Corpus note (deliberate): the override marker is read from the PR BODY ONLY.
# This hook does NOT expand linked `specs/**.md` files into its corpus, unlike
# the soak-followthrough precedent. Inheriting that would let the gate find its
# own override marker inside committed evidence/spec files and silently
# self-override — invisible to the acceptance criteria.
#
# Command matching (2.3): `gh pr (ready|merge)` — deliberately WIDER than the
# soak gate's `merge\s+.*--auto`, which misses `--squash` (merge queue) and
# `--admin`. Both are real merge surfaces.
#
# Early-exit ordering (2.3b) — each early exit is a bypass path, so the order is
# load-bearing:
#   1. command does not match          -> exit 0 (not our surface)
#   2. env override                    -> exit 0 (deliberate, announced)
#   3. gate script missing/not exec    -> exit 0 (fail-open: infra, not policy)
#   4. delegated script exit != 1      -> exit 0 (pass or transient fail-open)
#   5. delegated script exit == 1      -> DENY
# The hook cds into the payload .cwd (when absolute and existing) before
# delegating, matching every sibling ship gate. The delegated script resolves
# the PR from the process cwd, so skipping this makes the gate silently
# fail-open whenever the session cwd is not the PR's worktree.
#
# Fail-open conditions (exit 0 silently or with a note):
#   - command is not `gh pr ready` / `gh pr merge`
#   - SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1
#   - gate script absent or not executable
#   - gate script times out (RC=124) — fails open but NOT silently: it emits a
#     `warn` row so "never fired" is distinguishable from "timed out every run"
#   - gh unauthenticated / no PR yet (the script itself fails open)
#
# Fail-closed condition (deny + emit_incident):
#   - the delegated script exits 1 (NET > 0, no override marker in the PR body)

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Strip commit bodies/heredocs so a commit message *documenting* the command is
# not mistaken for one (#5192).
if command -v strip_command_bodies >/dev/null 2>&1; then
  SCAN=$(strip_command_bodies "$CMD")
else
  SCAN="$CMD"
fi

if ! grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge)(\s|$|&&|\|\||;)' <<<"$SCAN"; then
  exit 0
fi

if [[ "${SOLEUR_SKIP_NET_ISSUE_FLOW_GATE:-}" == "1" ]]; then
  exit 0
fi

# The SCRIPT PATH resolves from the project dir (it is the same checkout
# regardless of which worktree the command runs in). The WORKING DIRECTORY must
# still be the payload .cwd: the delegated script resolves the PR via
# `gh pr view` and `gh issue list`, both of which read the repo/branch from the
# process cwd. Resolving only the script path and inheriting the hook process's
# cwd is a real bypass — a session started in the main checkout that then runs
# `gh pr merge` against a feature worktree would resolve NO PR, fail open, and
# never block. That is the exact class this gate exists to close, so it is not
# left to convention: the suite asserts .cwd is honored.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
GATE="$PROJECT_DIR/plugins/soleur/skills/ship/scripts/net-issue-flow.sh"
[[ -x "$GATE" ]] || exit 0

if [[ "$WORK_DIR" == /* ]] && [[ -d "$WORK_DIR" ]]; then
  cd "$WORK_DIR" 2>/dev/null || exit 0
fi

# Budget. The gate's dominant cost is `gh issue list --limit 500` (~4-5 s over 5
# sequential paginated REST calls) plus two `gh pr view` calls; measured wall
# clock on the unmodified gate spans 5.7-8.1 s across hosts (7.7-8.1 s measured
# at plan time, 5.7-6.3 s re-measured at implementation time on a second host --
# the spread IS the hazard). Against the previous `timeout 8`
# that is a coin flip: a timed-out run returns 124, which the `-eq 1` test below
# translates to `exit 0` — no deny, no telemetry, indistinguishable from a pass.
# A BLOCKING gate that intermittently always-passes is strictly worse than the
# advisory surface it replaced, because it also carries the authority of having
# passed. 25 s leaves headroom for the exemption pass (~1 s) and API jitter.
#
# The probe, not a hardcoded `timeout`: `timeout(1)` is not universally present,
# and hardcoding it makes a host without coreutils return 127 — which this
# hook's `-eq 1` test also translates to a silent `exit 0`. Precedent:
# .claude/hooks/supabase-loopback-warn.sh, which documents exactly that rc-127
# dark tripwire. With TO=() empty, the gate simply runs unbounded — slow beats
# silently absent.
TO=()
command -v timeout >/dev/null 2>&1 && TO=(timeout 25)

OUT="$("${TO[@]+"${TO[@]}"}" bash "$GATE" 2>&1)"
RC=$?

# A timeout is not a policy verdict, so it still fails OPEN — but it must not
# fail SILENT. This emit is deliberately ABOVE the `-eq 1` early exit: below it,
# the line would be present in the file and never reached, which is precisely
# the mutation the hook suite's incident-file assertion exists to catch.
#
# `warn`, not `transient`: rule-metrics-aggregate.sh counts only
# deny/bypass/applied/warn, so a `transient` row would increment nothing and the
# operator could not distinguish "gate never fired" from "gate timed out on
# every invocation" — the same defect class this gate's own header condemns.
# Its OWN rule_id, not the shared `net-issue-flow` one. The gate script already
# emits `net-issue-flow` + warn for every generic fail-open (gh outage, empty
# issue list), so sharing the id would conflate "the API was down" with "the
# gate ran too long and was killed" — two conditions with different fixes,
# collapsed into one number. That is the same "cannot tell never-fired from
# fail-opened" defect this file's header condemns, one level down. Measured on
# real local telemetry before the split: 8 warns, none of them separable.
# Still `net-issue-flow*`-prefixed, so the aggregator's orphan exemption covers it.
if [[ "$RC" -eq 124 ]]; then
  if declare -F emit_incident >/dev/null 2>&1; then
    emit_incident net-issue-flow-timeout warn "gate exceeded the 25s ceiling — failed open" 2>/dev/null || true
  fi
fi

[[ "$RC" -eq 1 ]] || exit 0

REASON="Net-issue-flow gate: BLOCKED — this PR files more issues than it closes.

${OUT}

Every PR must close at least as many issues as it files. Filing is free;
closing is expensive, and the queue grows by roughly the difference. The
measured rate to 2026-07-20 was 2.04 filed per merged PR against 0.95 closed —
a queue growing +144/week.

Resolve via one of:
  (a) Fix inline — fold the filed work into THIS PR. The cost-of-filing
      auto-flip (<=100 lines AND <=4 files) already covers most findings.
      NOTE this is a SIZE test: if the blocker is AUTHORITY (an operator-only
      credential or production decision), (a) does not apply however small the
      diff would be. See (d).
  (b) Close something — if a filed issue supersedes an open one, close it and
      add the 'Closes #N' keyword to the PR body.
  (c) Override — add '<!-- gate-override: net-issue-flow -->' plus a one-line
      justification per filed issue to the PR body, or run with
      SOLEUR_SKIP_NET_ISSUE_FLOW_GATE=1. This is the GENERAL hatch, not an
      architectural-pivot-only one: pivots qualify, and so do filings forced by
      a SKILL.md phase mandate with no rule id, and discovered defects in
      another subsystem that must stay separate. State the real reason — a
      hatch that must be mis-described to be used gets used without being read.
  (d) Mandated filing — the issue was REQUIRED by a rule carrying
      [mandates-filing] in AGENTS.rules.md. Put 'Mandated-By: <rule-id>' on its
      own line in the ISSUE body, a 'Tracks #<issue>' companion in the PR body,
      and leave the issue OPEN. The gate output above lists the rules that
      qualify; if yours is not listed, (d) is unavailable — use (c) and say so
      rather than guessing an id. The exemption never reduces the Filing:
      count; it is reported on its own line.

See ship/SKILL.md section 'Net-Issue-Flow Gate (blocking)'."

emit_incident net-issue-flow deny "blocked net-positive PR at gh pr ready/merge" 2>/dev/null || true

jq -n --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
