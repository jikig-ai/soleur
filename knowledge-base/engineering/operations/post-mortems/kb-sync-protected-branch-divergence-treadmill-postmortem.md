---
title: "KB-sync silently undelivered on protected default branches (divergence treadmill)"
date: 2026-06-16
incident_pr: 5427
incident_window: "latent — pre-dates detection; no single window"
recovery_at: "2026-06-16 (PR #5427 merge + deploy)"
suspected_change: "session-sync.ts syncPush bare `git push` onto a protected default (long-standing)"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - re-eval signal: PR #5423's selfHealNonFastForward re-heals a diverged clone every session, leaving a permanent soleur/recovered-kb-sync-<ts> ref each time — the recurring ref accumulation surfaced the undelivered-writes root cause
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

For users whose connected-repo default branch is **protected**, Concierge's post-session knowledge-base auto-commit could never be delivered. `syncPush` (`apps/web-platform/server/session-sync.ts`) staged the `knowledge-base/**` allowlist, committed onto the checked-out default branch, then issued a bare `git push` — which the protected branch rejects (`GH006`). The commit was stranded as an un-pushable orphan on the local default; PR #5423's downstream `selfHealNonFastForward` then re-healed the diverged clone every subsequent session, leaving a permanent `soleur/recovered-kb-sync-<ts>` ref each time (the "divergence treadmill"). Net user-visible effect: their session knowledge-base writes never reached their repo, with no signal.

## Status

resolved — PR #5427 routes the protected-branch case to a durable `soleur/kb-sync` side branch + PR in the user's own repo.

## Symptom

Protected-repo users' `knowledge-base/**` writes silently never appear in their connected repo after a session; accumulating `soleur/recovered-kb-sync-*` refs on the clone.

## Incident Timeline

- **Start time (detected):** 2026-06-16 (re-eval of PR #5423's recovered-ref accumulation)
- **End time (recovered):** 2026-06-16 (PR #5427)
- **Duration (MTTR):** latent until detection; fixed same day as detection

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-16 | Re-eval of #5423's recovered-kb-sync-* ref accumulation surfaced the undelivered-writes root cause; filed #5426. |
| agent | 2026-06-16 | Brainstorm → plan → work → PR #5427 (classifyPushError + runProtectedFallback). |

## Participants and Systems Involved

Concierge session-sync (`syncPush`), the GitHub App installation token path (`gitWithInstallationAuth`), the user's connected GitHub repo with branch protection on its default branch.

## Detection (+ MTTD)

- **How detected:** internal re-eval of a sibling fix (#5423) whose recovered-ref accumulation was the observable tell — not an alert (no alert existed for this class, which is the gap #5427's `kb-sync.protected-fallback-failed` Sentry op now closes).
- **MTTD (mean time to detect):** unbounded (latent; no detector existed prior).

## Triggered by

system — a protected default branch on the user's connected repo (a legitimate repo policy) rejecting the bare push.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Bare `git push` onto a protected default is rejected and the commit is stranded | `GH006` rejection class; #5423's recovered-ref churn re-healing the same divergence every session | none | confirmed |

## Resolution

On a push rejection classified `protected_branch`, `runProtectedFallback` accretes the latest KB tree onto a durable `soleur/kb-sync` side branch in the user's own repo (tree-overlay, conflict-free, latest-KB-wins), opens/updates a non-draft never-auto-merged PR into the resolved default branch, then resets local default to `origin/<default>` — only after the side-branch push + PR succeed (failure preserves the commit on default for next-session retry).

## Recovery verification

Post-deploy: Sentry op `kb-sync.push-protected-fallback` (feature `session-sync`) fires with a PR url on a protected-repo session, and `self-heal-recovered-diverged` stops recurring for the affected workspace (plan §Phase 5). No locally-curlable surface exists for a per-session event — the Sentry op query is the verification.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did protected-repo KB writes not arrive? The bare `git push` was rejected by branch protection.
2. Why was the commit then lost? It was stranded as an un-pushable orphan on the local default with no alternate delivery path.
3. Why no alternate path? `syncPush` only ever attempted a direct push onto default; `runConnectedRepoGit` forbids branch/push/reset, so no side-branch route existed.
4. Why undetected for so long? No observability distinguished a protected-branch rejection from a transient push failure — both fell into the generic best-effort `syncPush` catch.
5. Why did it surface now? PR #5423's `selfHealNonFastForward` made the divergence *visible* as accumulating `recovered-kb-sync-*` refs, prompting the re-eval that found the trigger.

## Versions of Components

- **Version(s) that triggered the outage:** all releases prior to PR #5427 (long-standing `syncPush` behaviour).
- **Version(s) that restored the service:** PR #5427.

## Impact details

### Services Impacted

Concierge knowledge-base sync for connected repos with a protected default branch.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user (protected-repo connected): KB writes silently undelivered after each session; work appears lost.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none beyond the authenticated-user impact above.

### Revenue Impact

None directly; brand/trust risk (product appears to lose user work) — the `single-user incident` threshold.

### Team Impact

One brainstorm→plan→work→ship cycle.

## Lessons Learned

### Where we got lucky

PR #5423's recovered-ref accumulation made an otherwise-silent class observable, prompting detection.

### What went well

The fix is conflict-free (tree-overlay) and lossless (ordered reset); multi-agent review confirmed the ordering invariant and the precedent-diff vs `selfHealNonFastForward`.

### What went wrong

A push-rejection class with a known cause (branch protection) had no dedicated observability and no recovery path for ~the product's lifetime.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5428 | One-time sweep of accumulated `soleur/recovered-kb-sync-*` branches left by #5423's self-heal. | open |
| #5429 | In-product KB-sync status surface (writes-awaiting-merge) so a protected-repo user sees the pending PR without reading their repo. | open |
