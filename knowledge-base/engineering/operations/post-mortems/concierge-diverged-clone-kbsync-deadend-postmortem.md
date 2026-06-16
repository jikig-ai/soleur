---
title: "Concierge workspace permanently dead-ends on a diverged kb-sync clone with un-pushed commits"
date: 2026-06-16
incident_pr: 5423
incident_window: "2026-06-16 13:54 UTC (first observed Sentry event) → automated on #5423 deploy"
recovery_at: "automated on first POST /api/kb/sync after #5423 deploys"
suspected_change: "the 2026-06-16 concierge reconnect/self-heal fix (release 3c8849655) — its post-clone auto-sync commits knowledge-base/** onto the default branch; a protected-branch push rejection strands the commit"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

A connected Concierge workspace whose repo clone had **diverged from `origin/<default>` with un-pushed
local commits** was permanently trapped: every `POST /api/kb/sync` re-fired `selfHealNonFastForward()`'s
abort, **Reconnect did nothing**, and the dispatch readiness gate reported "workspace isn't ready". This is
an **availability/durability** incident (the knowledge base silently stopped syncing and there was no
in-product recovery), not a data-disclosure incident.

## Status

resolved — the code fix in #5423 recovers the trapped state automatically on the next kb/sync after deploy.

## Symptom

- **Error:** `self-heal aborted: un-pushed local commits present` at `POST /api/kb/sync`
- **Sentry op:** `self-heal-aborted-dirty` (feature `kb-route-helpers`), release `web-platform@0.140.0`
- **Operator report:** workspace stuck; clicking **Reconnect** does NOT recover; "workspace isn't ready".

## Incident Timeline

- **Start time (detected):** 2026-06-16 13:54 UTC (first observed Sentry event)
- **End time (recovered):** automated on first `POST /api/kb/sync` after #5423 deploys
- **Duration (MTTR):** code fix authored same day; production self-heals on next sync post-deploy

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-16 13:54 | Sentry `self-heal-aborted-dirty` cluster + operator report of stuck workspace. |
| human | 2026-06-16 ~15:57 | Operator reported "reconnecting the repo doesn't self-heal" with the debug stream + Sentry payload. |
| agent | 2026-06-16 | Root-caused the `.git`-present-but-diverged gap; authored the branch-aside recovery (#5423). |

## Participants and Systems Involved

`apps/web-platform` Concierge: `workspace-sync.ts` (kb/sync self-heal), `session-sync.ts` (auto-sync trigger),
`repo-readiness-self-heal.ts` + `use-reconnect.ts` (re-clone paths). No external vendor involved.

## Detection (+ MTTD)

- **How detected:** Sentry alert (`pino-mirror` capture) + direct operator report. Monitoring caught it.
- **MTTD:** the abort fires on the first post-strand kb/sync, so detection is effectively immediate per event.

## Triggered by

system — the post-clone auto-sync stranding a commit on the protected default branch.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| kb/sync self-heal aborts on un-pushed commits and nothing ever clears the divergence | `selfHealNonFastForward` returns abort when `rev-list --count @{u}..HEAD > 0`; Sentry op matches | none | confirmed |
| Reconnect can't recover because it's `.git`-absent / `repo_status==="ready"` gated | `use-reconnect.ts` only re-clones when `repo_status !== "ready"`; a diverged clone stays "ready" | none | confirmed |

## Resolution

`selfHealNonFastForward` now, on `localCommits > 0` with HEAD on the **default branch**, branches the
un-pushed commits aside (`git branch soleur/recovered-kb-sync-<ts> HEAD`) **before** `git reset --hard
origin/<default>` — provably non-destructive (the branch ref is a gc-root). Feature-branch and detached-HEAD
divergence still abort to protect genuine agent work, the latter with a distinct
`op:self-heal-aborted-detached-head` slug. Recovery emits a queryable `op:self-heal-recovered-diverged` WARN.

## Recovery verification

Post-deploy, the trapped workspace's next `POST /api/kb/sync` emits `op:self-heal-recovered-diverged`
(feature `kb-route-helpers`) and the workspace unblocks — verifiable via a read-only Sentry issue search,
no SSH. A genuine recovery failure keeps the existing error-level `op:self-heal-failed` page. Unit coverage:
`apps/web-platform/test/kb-route-helpers.test.ts` (recovery + ordering + detached + phantom-unchanged).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was the workspace stuck?** Every kb/sync aborted on un-pushed local commits.
2. **Why did it abort?** The self-heal protects un-pushed work by refusing to `reset --hard` when commits exist.
3. **Why were there un-pushed commits?** The post-clone auto-sync auto-commits `knowledge-base/**` onto the
   checked-out default branch, then a bare `git push`; a protected-branch push rejection strands the commit.
4. **Why didn't Reconnect recover it?** The re-clone path is `.git`-absent / `repo_status==="ready"` gated; a
   diverged clone exists and stays "ready", so Reconnect short-circuits to a no-op.
5. **Why was there no recovery at all?** The same-day reconnect/self-heal fix (3c8849655) closed the
   `.git`-**absent** case but not the `.git`-**present-but-diverged** case — a disjoint failure state.

## Versions of Components

- **Version(s) that triggered the outage:** `web-platform@0.140.0` (release `3c8849655`)
- **Version(s) that restored the service:** the release containing #5423

## Impact details

### Services Impacted

Concierge knowledge-base sync (`POST /api/kb/sync`) and dispatch readiness for the affected workspace.

### Customer Impact (by role)

- Prospect: none
- Authenticated app user: **high** — knowledge base silently stops syncing; Concierge says "workspace isn't ready"; Reconnect does nothing; no in-product recovery (non-technical users have no escape).
- Legal-document signer: none
- Admin via Access: none
- Billing customer: none
- OAuth installation owner: none

### Revenue Impact

None direct; brand-survival risk on the core onboarding→work path.

### Team Impact

One operator-reported incident; same-day root cause + fix.

## Lessons Learned

### Where we got lucky

The un-pushed commits were `knowledge-base/**`-only auto-sync data (regenerable), so even the pre-fix abort
preserved no irrecoverable work — and the fix's branch-aside makes preservation provable regardless.

### What went well

Sentry + operator report gave immediate detection; the existing `op` slug taxonomy pinned the failing path.

### What went wrong

A same-day fix for "checkout missing/errored" did not consider the adjacent "checkout present but diverged"
state, leaving a second dead-end. The trigger (auto-commit onto a protected default branch) is still live.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #5426 | Root-cause: stop auto-committing knowledge-base/** onto the protected default branch (session-sync trigger) + bound recovery-branch retention. | open |
