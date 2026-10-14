---
title: "Concierge strand: the only Inngest function that runs on the operator's surface could not re-clone a corrupt .git (definitive fix; two prior fixes targeted the wrong layer)"
date: 2026-06-30
incident_pr: 5730
incident_window: "recurring across 2026-06-29 → 2026-06-30; survived two merged fixes"
recovery_at: "2026-06-30 (PR #5730 merged → deploy-push triggers reconcile → re-clone)"
suspected_change: "reconcile-on-push readiness gated on dir-existence, sync only pulls/resets — never re-clones"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - "/workspaces/<id>/.git missing or corrupt on the operator's containerized agent surface"
  - "workspace-reconcile-on-push fires on push but cannot recover a non-valid .git"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — after operator menu-ack.
- `human` — operator did it directly.

# Incident Overview

The operator's containerized `/soleur:go` agent repeatedly stranded on `fatal: not a git repository`. It took THREE PRs to resolve, the first two on the wrong layer:

- **#5716** (warm-dispatch await, absent `.git`) and **#5584** (validity-not-presence, corrupt `.git`) both targeted the **cc-dispatcher** web-chat path. Merged + deployed; the operator still stranded.
- Production Sentry showed **zero** cc-dispatcher events on the affected workspace while the deploy was confirmed live — proving that path never runs on the operator's surface. The path that DOES run is the Inngest **`workspace-reconcile-on-push`** function (26× on `754ee124`), which gated readiness on directory existence (not `.git` validity) and whose `workspace-sync` only pulls/resets — **never re-clones**. So a missing/corrupt `.git` was a permanent trap.
- **#5730** (this PR) is the definitive fix: gate reconcile readiness on `isValidGitWorkTree`; re-clone an invalid/absent `.git` via the destruction-safe `ensureWorkspaceRepoCloned`.

## Status

resolved

## Symptom

`git status` → "not a git repository" inside `/workspaces/<id>`; `/soleur:go` Step 0.0 stops. `repo_status='ready'`, `repo_last_synced_at` frozen, reconcile firing fruitlessly on every push.

## Incident Timeline

- **Detected:** 2026-06-29 (operator report), recurring.
- **Recovered:** 2026-06-30 (PR #5730 merge → deploy-push → reconcile re-clones).
- **MTTR:** ~1 day (extended by two wrong-layer fixes).

| Actor | Time | Action |
|---|---|---|
| human | 2026-06-29/30 | Reports the strand recurs after #5716 then #5584. |
| agent | 2026-06-30 | Queries prod Sentry → zero cc-dispatcher events → identifies the Inngest reconcile surface as the real path. |
| agent | 2026-06-30 | Ships #5730 (validity-aware re-clone in reconcile-on-push); deploy-push heals `754ee124`. |

## Participants and Systems Involved

Inngest `workspace-reconcile-on-push` + `workspace-sync`; the shared `ensureWorkspaceRepoCloned` primitive; operator workspace `754ee124` (repo `jikig-ai/soleur`); single live operator.

## Detection (+ MTTD)

- **How detected:** operator report; then a **Sentry breadcrumb search** was the decisive diagnostic (zero events on the path being "fixed").
- **MTTD:** the wrong-layer fixes delayed accurate detection by ~2 ship cycles.

## Triggered by

system — an on-disk `.git` left missing/corrupt (host reclaim / interrupted clone), on a surface whose only recovery function couldn't re-clone.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| cc-dispatcher self-heal bug (#5716/#5584) | symptom shape | ZERO cc-dispatcher Sentry events; operator still strands post-deploy | rejected (wrong layer) |
| reconcile-on-push can't re-clone a non-valid `.git` | 26× reconcile events on the workspace; dir-existence gate + pull/reset-only sync | — | confirmed |

## Resolution

`workspace-reconcile-on-push` readiness now gates on `isValidGitWorkTree`; an invalid/absent `.git` is re-cloned via `ensureWorkspaceRepoCloned` (destructive `rm` fenced behind the positive empty-corrupt fingerprint — never destroys un-pushed commits). Recovery is push-triggered; this PR's own deploy-push fires the reconcile that heals `754ee124`. PR #5730.

## Recovery verification

`tsc` clean; full `vitest run` green (11003 tests); 5 review agents + semgrep (no P1/P2; destructive-rm safety re-confirmed). No-SSH recovery check: `kb_sync_history` row for `754ee124` with `recovered=true` after the post-deploy push (AC12).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Strand? `.git` invalid on the operator's surface. → 2. Not recovered? The only function firing there (reconcile-on-push) couldn't re-clone. → 3. Why? Readiness gated on dir-existence, sync only pulls/resets. → 4. Why two prior fixes missed it? They were diagnosed from the symptom + code-reading and shipped to cc-dispatcher — a path that never runs on this surface. → 5. Why undetected? No runtime exec-path verification (a Sentry breadcrumb search) before shipping; the zero-events signal was only checked on the third report.

## Versions of Components

- **Triggered:** web-platform with dir-existence reconcile readiness.
- **Restored:** PR #5730.

## Impact details

### Services Impacted

The operator's containerized `/soleur:go` for any workspace with a missing/corrupt `.git`.

### Customer Impact (by role)

- Prospect / Legal-signer / Admin / Billing / OAuth-owner: none.
- Authenticated app user: the single live operator stranded across multiple sessions; extended by two ineffective fixes.

### Revenue Impact

None (pre-revenue, single operator).

### Team Impact

Three PRs + two wrong-layer ships' worth of churn before the correct layer was identified.

## Lessons Learned

### Where we got lucky

The fix is push-triggered and the workspace is connected to the heavily-pushed dev repo, so the fix's own deploy-push self-heals the operator without a manual step.

### What went well

The destructive-rm safety primitive was reused unchanged (re-reviewed safe); the eventual Sentry exec-path check was decisive.

### What went wrong

Two merged+deployed fixes targeted a path that emits zero events on the affected surface. Diagnosis relied on symptom + code-reading, never on runtime evidence of which code actually runs — the single most important miss. Captured as a plan-skill Sharp Edge + learning (verify the fixed code path executes on the affected surface, via Sentry, before shipping a recurring-symptom fix).

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
