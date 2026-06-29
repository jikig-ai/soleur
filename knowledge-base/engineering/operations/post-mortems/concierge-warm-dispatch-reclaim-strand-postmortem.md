---
title: "Concierge warm-dispatch strands the operator on a reclaimed workspace (no git checkout)"
date: 2026-06-29
incident_pr: 5716
incident_window: "recurring; last observed 2026-06-29 16:52 UTC"
recovery_at: "2026-06-29 (PR #5716 merged)"
suspected_change: "warm-dispatch reprovision was fire-and-forget; pre-existing gap exposed by sandbox/workspace reclaim"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - workspace reclaim (filesystem wiped, .git gone) mid-conversation
  - warm Concierge dispatch turn (reused SDK query; cold-path self-heal does not re-run)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The operator's Concierge `/soleur:go` flow repeatedly failed: the agent's bubblewrap sandbox `chdir`'d into a `/workspaces/<id>` with no git checkout, `git status` returned `fatal: not a git repository`, and `go.md` Step 0.0 honest-stopped with "your workspace isn't ready." Multiple prior ADR-044 self-heal/resolver PRs (#5409, #5435, #5546, #5580) targeted the same symptom and it persisted — because they hardened the COLD dispatch path, while the operator's failures rode the WARM path.

## Correction (2026-06-29, added in PR #5584)

The root cause stated below (warm-dispatch fire-and-forget re-clone of an **absent** `.git`) is a real, fixed latent bug — but it was **not** the operator's specific recurring failure. Live evidence (dispatch **proceeded** into the workspace with `repo_status='ready'` and NO reclaim message) shows `existsSync('.git')` was **true**: a **present-but-invalid** `.git`. That is the presence-not-validity gap fixed by PR #5584, whose PIR (`concierge-corrupt-worktree-validity-strand-postmortem.md`) is the accurate root-cause record for the operator's incident. This PR (#5716) and #5584 are two fixes for the same operator-strand class via two distinct mechanisms (absent-`.git` race vs corrupt-`.git` presence-check).

## Status

resolved

## Symptom

Concierge turn strands on `fatal: not a git repository`; `go.md` Step 0.0 reports the workspace isn't ready. Recurs across fresh-looking conversations. `gh` API works (token minted), so the workspace IS connected — only the on-disk checkout is missing.

## Incident Timeline

- **Start time (detected):** 2026-06-29 ~16:52 UTC (operator report; symptom recurring for an unknown prior window)
- **End time (recovered):** 2026-06-29 (PR #5716 merged)
- **Duration (MTTR):** same-session diagnosis → fix (hours)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-29 16:52 | Operator reports "still failing despite all fix attempts" with the debug stream (workspace `/workspaces/754ee124-…`). |
| agent | 2026-06-29 | Matched the failing id to open issue #5591; pulled live prod data; found the two operator workspaces point at DIFFERENT repos (de-dup contraindicated) and the real cause is a warm-dispatch re-clone race. |
| agent | 2026-06-29 | Filed #5715, implemented + reviewed fix (PR #5716), corrected #5591. |

## Participants and Systems Involved

Web platform Concierge dispatch (`cc-dispatcher.ts`, `cc-reprovision.ts`, `soleur-go-runner.ts`); the operator's reclaimed workspace `754ee124` (repo `jikig-ai/soleur`); single live operator (dogfooding).

## Detection (+ MTTD)

- **How detected:** external/manual — operator report. No monitor fired (the warm path's fire-and-forget re-clone had no breadcrumb when it lost the race; AC11 now adds one).
- **MTTD (mean time to detect):** unknown — symptom recurred before the explicit report.

## Triggered by

system — a workspace/sandbox reclaim that wipes `/workspaces/<id>` between turns.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Duplicate-workspace data anomaly (#5591) | operator owns two "My Workspace" rows | live data: the two rows point at DIFFERENT repos (soleur vs chatte) — not same-repo dupes | rejected |
| Warm-dispatch re-clone races the sandbox | cold path awaits the clone; warm path fires `void reprovisionWorkspaceOnDispatch(userId)` at `cc-dispatcher.ts:2899` | — | confirmed |

## Resolution

Gate the warm Concierge dispatch on the re-clone the same way the cold path already does: `await reprovisionWorkspaceOnDispatch(userId)` before `runner.dispatch` on warm turns, with the `.git` short-circuit hoisted INTO `reprovisionWorkspaceOnDispatch` so one membership-verified resolve feeds both the stat and the clone (LEADER precedent `agent-runner.ts:1148`). A genuine `"failed"` re-clone short-circuits to the honest reclaim message instead of spawning the agent into a `.git`-less workspace (AC10); the forced-slow-path is now observable (AC11). PR #5716 / #5715.

## Recovery verification

`tsc --noEmit` clean; full `vitest run` green (10981 tests); new regression suite `cc-dispatcher-warm-reclone-await.test.ts` (RED on `origin/main`, GREEN after fix) plus an unmocked-`existsSync` discriminator test. Six review agents + semgrep concurred (no P1/P2). The deployed fix's runtime recovery is request-driven (next warm turn re-clones before dispatch).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the agent strand? Its sandbox CWD had no `.git`. → 2. Why no `.git`? The workspace was reclaimed and not re-cloned before the turn reached the sandbox. → 3. Why not re-cloned in time? The warm-dispatch re-clone (`reprovisionWorkspaceOnDispatch`) was fire-and-forget, not awaited. → 4. Why fire-and-forget? It mirrored the warm `resolveBashAutonomous` resolve; only the COLD factory awaited the clone, and warm turns never re-enter the factory. → 5. Why did prior fixes miss it? They hardened the cold-path self-heal/resolver; the warm timing gap was a different layer.

## Versions of Components

- **Version(s) that triggered the outage:** web-platform at/around the ADR-044 self-heal series (#5409–#5580); warm path fire-and-forget since the per-dispatch reprovision landed (#5339/#5340).
- **Version(s) that restored the service:** PR #5716.

## Impact details

### Services Impacted

Concierge `/soleur:go` dispatch (the operator's core workflow) on warm turns after a reclaim.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: the single live operator could not run Concierge tasks (turn stranded) on affected warm turns.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none (connection intact; only on-disk checkout missing).

### Revenue Impact

None (pre-revenue; single dogfooding operator).

### Team Impact

Operator friction + repeated failed sessions; engineering time to diagnose across a heavily-defended subsystem.

## Lessons Learned

### Where we got lucky

The failing workspace id in the debug stream matched an open issue (#5591) verbatim — the cheapest symptom→issue join key. Pulling live data caught a stale "same repo" premise before a destructive de-dup.

### What went well

Live-data verification stopped a workspace-destroying de-dup; multi-agent review confirmed the single-resolve design closes the probe/clone divergence without access-widening.

### What went wrong

The warm path shipped a fire-and-forget recovery with no breadcrumb, so the race was invisible to Sentry; four prior fixes targeted the wrong layer because the warm/cold split wasn't enumerated.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
