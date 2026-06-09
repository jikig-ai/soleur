---
title: "Concierge workspace clone used the stored (wrong-scope) GitHub App installation → gh-403 → No Git Repository in Workspace"
date: 2026-06-08
incident_pr: 5041
incident_window: "2026-06-08 (surfaced via founder dogfooding shortly after #5031 merged 15:26 CEST)"
recovery_at: "2026-06-08 (on merge of #5041)"
suspected_change: "PR #5031 (9556f1f4a) hardened the installation self-heal computation but did not move the clone consumer onto it"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability: hosted Concierge could not bootstrap a workspace (clone failed → no .git)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability incident, no personal-data breach; the failure path mints/logs no token (hr-github-app-auth-not-pat) and exposes no personal data (Recital 26 pseudonymized userId only in observability payloads)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

A founder dogfooding the hosted Concierge asked it to "fix issue 4826". The Concierge returned a self-diagnosis that it could not proceed, citing two blocking errors: (1) every `gh` API call returned `403 Forbidden`, and (2) the workspace at `/workspaces/<uuid>` contained no git repository, so `worktree-manager.sh create` failed with "No Git Repository in Workspace". The two errors were a single cascade. This came immediately after PR #5031 ("harden Concierge gh-403 installation self-heal") merged — the founder reported "still facing this even after the recent fix".

## Status

resolved — fixed in the source PR (#5041); the workspace clone now consumes the self-healed installation.

## Symptom

Hosted Concierge one-shot pipeline halts at workspace bootstrap: `git clone` 403s on the connected org repo, the workspace is left `.git`-less, and any worktree/branch/commit operation fails with "No Git Repository in Workspace". The Concierge surfaces both the gh-403 and the no-git-repo as separate blockers.

## Incident Timeline

- **Start time (detected):** 2026-06-08, founder dogfooding (~16:36 CEST per the reported screenshot)
- **End time (recovered):** 2026-06-08, on merge of #5041
- **Duration (MTTR):** same-session fix (root-caused, fixed, reviewed, shipped in one autonomous pipeline)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-08 ~14:36 | Founder reports the Concierge still fails after #5031 (screenshot: gh-403 + No Git Repository in Workspace). |
| agent | 2026-06-08 | Root cause traced: clone runs before the self-heal computes `effectiveInstallationId` and consumes the stored install. |
| agent | 2026-06-08 | Fix (hoist self-heal above clone, pass `effectiveInstallationId`), regression tests, 8-agent review, ship via #5041. |

## Participants and Systems Involved

`apps/web-platform/server/cc-dispatcher.ts` (`realSdkQueryFactory`), `ensure-workspace-repo.ts` (clone), `github-app.ts` (installation-token mint + `findRepoOwnerInstallationForUser` entitlement gate), `git-auth.ts`. Hosted Concierge dispatch path only.

## Detection (+ MTTD)

- **How detected:** external/manual — founder dogfooding the hosted Concierge (not a monitor). The relevant Sentry signal (`feature:cc-dispatcher op:self-heal-skip` + `feature:ensure-workspace-repo op:clone`) exists but was not the detection trigger.
- **MTTD:** effectively immediate on the dogfooding session; the underlying defect was latent in #5031 (the clone never consumed the self-heal it added).

## Triggered by

system — a code-ordering defect: #5031 added the self-heal computation but positioned it after the clone, so the clone (the precondition for all git work) kept reading the stored install.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Clone uses the stored (wrong-scope) installation because it runs before the self-heal | `cc-dispatcher.ts` clone passed bare `installationId` at the call site; `effectiveInstallationId` computed ~64 lines later; mint + C4 already consumed it | none | confirmed |

## Resolution

In-function ordering correction: hoist the owner/repo parse + the installation self-heal block above `ensureWorkspaceRepoCloned`, and pass `effectiveInstallationId` (the entitled, self-healed install) into the clone. In every non-promotion branch `effectiveInstallationId === installationId`, so the clone never gains access beyond the existing #4946 entitlement gate. Regression coverage asserts the clone receives OWNER on a heal and STORED on deny/already-correct/probe-throw.

## Recovery verification

Pre-merge: `installation self-heal` mismatch test RED against `main`, GREEN after the reorder; full web-platform vitest (8993 passed) + `scripts/test-all.sh` (102/102 suites); 8-agent review with the entitlement-gate invariant verified by 4 independent agents. Post-merge: `web-platform-release.yml` container restart deploys the fix; residual clone 403s would surface in Sentry `feature:ensure-workspace-repo op:clone` co-occurring with `op:self-heal-skip` (entitlement-deny, expected) — a clone failure WITHOUT a self-heal-skip would indicate regression.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the Concierge fail?** `git clone` 403'd → workspace left `.git`-less → worktree-manager found no repo.
2. **Why did `git clone` 403?** It authenticated with the stored GitHub App installation (a cross-account/personal install holding only `issues: read` on the org repo).
3. **Why the stored install and not the entitled one?** The clone (`ensureWorkspaceRepoCloned`) ran before the installation self-heal computed `effectiveInstallationId`.
4. **Why did #5031 not fix this?** #5031 hardened the self-heal *computation* (transient-robust probe, observability) but did not move the clone — the one consumer positioned earlier in the function — onto the computed value. The mint and the C4 write tool already consumed it, so the symptom (`gh issue create` 403) looked addressed.
5. **Why was the missed consumer not caught?** The fix was validated against the consumer the symptom named (the token mint), not against *every* consumer of the computed value. The clone's failure surfaced two layers downstream as an unrelated-looking "No Git Repository in Workspace".

**Final root cause:** a fix that hardens a *computed value* must sweep *every consumer* of that value — especially consumers positioned before the computation. The clone was the latent missed consumer.

## Versions of Components

- **Version(s) that triggered the outage:** the deploy carrying #5031 (clone still on stored install).
- **Version(s) that restored the service:** the deploy carrying #5041.

## Impact details

### Services Impacted

Hosted Concierge workspace bootstrap (clone/worktree). No data plane, auth, or billing surface touched.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: a founder whose connected org repo is owned by an installation distinct from their stored personal install could not bootstrap a Concierge workspace (clone 403 → no git repo → pipeline dead-in-the-water). Scope: single-user dogfooding; no evidence of broader cohort impact.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: the affected class — only when the entitled repo-owner installation differs from the stored install.

### Revenue Impact

None (pre-revenue; dogfooding).

### Team Impact

One autonomous pipeline session to root-cause, fix, review, and ship.

## Lessons Learned

### Where we got lucky

The defect was caught immediately via dogfooding rather than by an external user, and the fail-soft clone (no throw into the conversation) meant the Concierge degraded with a clear diagnostic instead of crashing.

### What went well

The self-heal observability #5031 added (`op:self-heal-skip`) and the `.git`-LAST success sentinel made the cascade unambiguous to trace. The entitlement gate (#4946) meant the fix could never widen access — the reorder was provably safe.

### What went wrong

#5031's fix hardened the computation but left the clone consumer on the stale value, so the brand-survival path (workspace bootstrap) never benefited from the hardening it appeared to deliver.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
