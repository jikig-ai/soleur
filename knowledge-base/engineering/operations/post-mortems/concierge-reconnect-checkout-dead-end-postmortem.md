---
title: "Concierge repo-checkout recovery dead-end (reconnect could not re-clone)"
date: 2026-06-16
incident_pr: 5409
incident_window: "2026-06-16 08:57–12:46 CEST"
recovery_at: "2026-06-16 (fix merged in PR #5409)"
suspected_change: "Concierge repo-readiness dispatch gate (#5394/#5395, merged 2026-06-16) gated on repo_status without a recovery path; reconnect (detect-installation) never re-cloned"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/UX dead-end, no personal-data breach (the only data touched is repo_status + a sanitized git error reason); no Art. 9 special-category data, no unauthorized access, no exfiltration. GDPR gate ran on the diff: no Critical finding."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `human` — Operator did this directly.

# Incident Overview

The founder, dogfooding the just-shipped Concierge connect-repo flow (#5392/#5395, merged earlier the same day), hit a state where the workspace repo checkout was missing/errored and **no in-product action could recover it**. Clicking "Reconnect in Settings → Repository" — the exact remediation the error message prescribed — only re-verified the GitHub App and never re-cloned, so the next dispatch showed the identical error. The morning also produced a Sentry cluster (08:57–09:01) from the post-clone auto-sync.

## Status

resolved

## Symptom

Concierge replied "Repository setup failed: … Reconnect in Settings → Repository" / "workspace directory doesn't exist on disk" and would not route to any file-touching workflow. Reconnecting did not change the outcome.

## Incident Timeline

- **Start time (detected):** 2026-06-16 08:57 CEST (Sentry cluster)
- **End time (recovered):** 2026-06-16 (PR #5409 merged)
- **Duration (MTTR):** ~hours (same-day dogfooding → fix)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-16 06:57Z | Sentry high-priority alerts fired: RuntimeAuthError + GH013 on POST /api/repo/setup. |
| human | 2026-06-16 10:46Z | Founder retried "Fix issue 4826" in Concierge; dispatch dead-ended at the readiness gate. |
| agent | 2026-06-16 ~11:00Z | Root-caused: gate throws before self-heal; reconnect cannot re-clone; auto-sync push/lease failures. Fixed in PR #5409. |

## Participants and Systems Involved

Concierge dispatch (`cc-dispatcher.ts`), repo-setup route (`/api/repo/setup`), reconnect path (`/api/repo/detect-installation`), the headless `/soleur:sync` agent, BYOK lease. Single affected user: the founder (tenant zero).

## Detection (+ MTTD)

- **How detected:** external/manual — founder dogfooding + Sentry high-priority email alerts.
- **MTTD:** minutes (Sentry alerted within the failing window).

## Triggered by

user (founder action: connect/reconnect repository in the Concierge).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Readiness gate throws on repo_status=error before the on-disk self-heal runs | gate at cc-dispatcher.ts:1568 upstream of ensureWorkspaceRepoCloned:1697 | none | confirmed |
| Reconnect button cannot re-clone | detect-installation has zero repo_status/provision/setup refs; only /api/repo/setup clones | none | confirmed |
| Auto-sync push + BYOK lease race produce the Sentry cluster | GH013 from a raw push; RuntimeAuthError from byok-lease, both via the post-clone startAgentSession | none | confirmed |

## Resolution

PR #5409: (1) dispatch self-heals an error/stale-cloning workspace via the idempotent `ensureWorkspaceRepoCloned` under a SECURITY DEFINER lock RPC, then re-evaluates; (2) reconnect re-triggers `/api/repo/setup` with a reachability guard + bounded status poll; (3) headless sync commits-local / worktree→PR (no raw push to a protected branch; GH013 → degraded status); (4) auto-sync trigger retries lease/auth-unavailable with bounded backoff and never corrupts `repo_status`.

## Recovery verification

Full web-platform vitest shard green (10,334 tests); new self-heal + RPC + reconnect + auto-sync suites green; migration applies via `web-platform-release.yml#migrate` on merge; self-heal observability queryable via Sentry issue search (`feature:cc-dispatcher op:repo-readiness-self-heal`) with no SSH.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. Why did the user stay stuck? The readiness gate blocked dispatch on `repo_status=error`. → 2. Why didn't it recover? The error branch threw before the in-dispatch self-heal could run (short-circuit-guard-before-recovery anti-pattern). → 3. Why didn't Reconnect fix it? `detect-installation` only re-verifies the GitHub App; it never re-clones — only `/api/repo/setup` does. → 4. Why did the recent fixes (#5392/#5395) not cover this? They gated dispatch at the DB layer (`repo_status=ready`) but didn't re-hydrate the on-disk checkout or wire reconnect to re-clone. → 5. Why the Sentry cluster? The post-clone auto-sync raw-pushed a protected branch (GH013) and raced the BYOK lease (RuntimeAuthError) with no retry.

## Versions of Components

- **Version(s) that triggered the outage:** Concierge connect-repo as of #5395 (2026-06-16).
- **Version(s) that restored the service:** PR #5409.

## Impact details

### Services Impacted

Concierge connect-repo → dispatch recovery path (onboarding→work). No data-plane or billing impact.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: tenant-zero (founder) only — full recovery-loop dead-end until fix; no other users on the surface.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: the affected user is also the install owner; reconnect was a no-op for recovery.

### Revenue Impact

None (pre-revenue; single internal user).

### Team Impact

~hours of founder + agent time, same day.

## Lessons Learned

### Where we got lucky

The only affected user was the founder dogfooding, so the dead-end was caught immediately rather than by a paying customer.

### What went well

Sentry high-priority alerts fired in-window; root cause traced from code + Sentry in one pass; fix shipped same day with a 10-agent review.

### What went wrong

The #5392/#5395 readiness gates closed the dispatch race at the DB layer but left two recovery paths broken (in-dispatch self-heal was gated upstream; reconnect could not re-clone), and the post-clone auto-sync had no push-protection handling or lease retry.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
