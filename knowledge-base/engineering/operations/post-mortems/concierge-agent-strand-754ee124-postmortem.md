---
title: "Concierge /soleur:go strands on 'not a git repository' for workspace 754ee124"
date: 2026-06-30
incident_pr: 5790
incident_window: "2026-06-29 → 2026-06-30 (recurring; ongoing until post-deploy operator-surface repro)"
recovery_at: "pending post-merge operator-surface repro (AC12, tracked by #5733)"
suspected_change: "agent-surface dispatch readiness self-heal gated on lstat (isValidGitWorkTree) not git rev-parse, + agent_readiness_self_stop observability emitted host-side (outside the agent's bwrap denyRead mount) so the real strand was unobservable"
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - operator-report
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — Claude Code did this after operator confirmation.
- `human` — Operator did this directly.

# Incident Overview

The operator's flagship Concierge `/soleur:go` agent repeatedly stranded on
`fatal: not a git repository` for workspace `754ee124` (→ `jikig-ai/soleur`).
Three prior server-side fixes (#5716, #5584, #5730) and a fourth (#5734) merged +
deployed without healing the surface; the operator confirmed the strand persisted
AFTER the #5734 deploy. The flagship product surface was non-functional for the
affected workspace with no observable server-side signal.

## Status

ongoing — code fix ships in PR #5790; full recovery is gated on the post-merge
operator-surface repro on `754ee124` (AC12), tracked by #5733.

## Symptom

`/soleur:go` dispatches against `/workspaces/754ee124` (a dir the DB reports
`repo_status=ready`) but the agent's in-bwrap `git rev-parse` finds no valid work
tree → the agent self-stops with the "workspace isn't ready / Settings → Repository"
honest-stop. No `agent_readiness_self_stop` Sentry event fired despite the strand.

## Root Cause

Two composed gaps (confirmed via live prod Supabase + Sentry, not code-reading):

1. **Heal gated on the wrong signal.** The dispatch/reprovision/reconcile self-heal
   gated on lstat `isValidGitWorkTree`, which returns `true` for a `.git` whose
   contents are invalid to `git rev-parse` (file-pointer / corrupt `dir-valid`). So
   the heal never fired for the H2 shape the operator actually hit.
2. **Observability blind on the real strand.** `reportAgentReadinessSelfStop` ran a
   host-side `git rev-parse`, which executes OUTSIDE the agent's frozen bwrap
   `denyRead:["/workspaces"]` mount — it can pass while the agent's in-sandbox probe
   fails. The strand was therefore unobservable server-side (zero events), which is
   why three prior fixes "emitted zero events on the agent surface."

H3 (wrong active workspace) was RULED OUT: `user_session_state.current_workspace_id
== 754ee124` for all members. The #5591 "owner-less" premise was REFUTED: 2 legit
`role=owner` rows (a `.maybeSingle()` ≥2-row false positive, fixed by #5734).

## Resolution

PR #5790: a host `git rev-parse` confirm gated behind lstat across all 3 gates
(shared `evaluateAgentReadiness`, fail-OPEN on inconclusive), a C2 in-sandbox
observability backstop that fires from the agent's OWN rev-parse result (robust to
the unconfirmed on-disk `.git` shape), and promotion of `source`/`gitKind` to
searchable Sentry tags. Never-destroy-populated invariant preserved (honest-block,
no re-clone of populated dirs).

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5733 | Post-deploy operator-surface repro: retry `/soleur:go` on `754ee124`; confirm no strand + a queryable `agent_readiness_self_stop` (host pre-heal OR C2 backstop). PASS → close #5733; FAIL → capture the now-observable `.git` shape and open a data-driven follow-up. | open |
