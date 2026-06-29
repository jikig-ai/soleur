---
title: "fix: reconcile (entitlement-scoped, solo-only) ready workspaces with NULL github_installation_id"
issue: 5675
type: bug
date: 2026-06-29
branch: feat-one-shot-5675-null-install-reconcile-gap
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_adrs: [ADR-044]
related_issues: [5580, 4543, 4717, 4712, 5470, 5437]
---

# fix: reconcile (entitlement-scoped, solo-only) ready workspaces with NULL `github_installation_id` (#5675)

## Enhancement Summary

**Deepened on:** 2026-06-29
**Sections enhanced:** Overview, Premise, Implementation, ACs, Observability, ADR, Risks
**Review agents used:** data-integrity-guardian, security-sentinel, architecture-strategist, user-impact-reviewer, code-simplicity-reviewer, observability-coverage-reviewer, mechanical verify-negative/precedent grep.

### Key improvements (all 7 agents folded in)
1. **HIGH (security + data-integrity + architecture, unanimous):** the v1 resolver
   (`findInstallationByAccountLogin(owner)` + `checkRepoAccess`) is the exact pattern this
   codebase already rejected for credential binding — `checkRepoAccess` passes for the org's
   **full-write** install regardless of whether the workspace owner is *entitled* to it, so an
   org-owned repo would over-grant a cross-tenant write credential. **Fix:** resolve via the
   connect-path's **entitlement-scoped** `resolveReachableInstallationIds(service, ownerUserId,
   ownerGithubLogin)` → `resolveOwningInstallationForRepo(reachable, owner, repo)`.
2. **P1 (data-integrity):** arm-1's scan includes **team** workspaces, which `detect-installation`
   says must **never** be auto-detected. **Fix:** backfill **solo workspaces only**
   (`workspaces.id == users.id`); team / no-resolvable-owner findings → skip.
3. **Premise correction (observability):** the `workspace_sync_health` Sentry alert filters on
   `feature` **only** (level-agnostic), and Sentry **folds** the 33 occurrences into one issue —
   so the v1 "demote to a debounced non-paging warn" plan was a **no-op** (5-min debounce is moot
   at daily cadence; a warn still trips the feature-only rule). **Fix:** drop the signal-demotion
   entirely; keep the existing folded `reportSilentFallback` for the unresolvable case (stays
   visible, no daily flood), and let a reconciled workspace clear the signal naturally by dropping
   out of the next scan.
4. **MEDIUM (architecture):** reuse the canonical `writeRepoColsToWorkspace(service, workspaceId,
   { github_installation_id })` write boundary (it already accepts the column and has 0-row-match
   Sentry mirroring) instead of a new `backfillInstall` writer — zero net-new write sites, inherits
   observability.
5. **Simplicity:** collapse the outcome union 4→3 (`reconciled | skip | transient`), inline the
   decision helper (no sibling file), drop the redundant reconciled breadcrumb, treat malformed
   `repo_url` as a `skip(malformed-repo-url)` outcome (review-corrected from the initial "arm-3 silent count-skip" to KEEP the visible `op:ready-null-installation` signal — a stuck workspace stays visible).
6. **P2 (data-integrity):** per-workspace `step.run(\`backfill-${id}\`)` boundary for Inngest-replay
   determinism (the write now has side effects).

### New considerations discovered
- The load-bearing correctness invariant: the backfilled id MUST equal the `installation.id` GitHub
  sends in future push webhooks for that repo. The entitlement-scoped resolver guarantees this (it
  returns the owner's owning install for the repo, which is the push-webhook install);
  `checkRepoAccess` alone does not.
- The "founder KB froze ~5 weeks" incident is a **solo personal repo** — exactly the case the
  solo-only + entitlement-scoped fix covers; org-repo over-grant is excluded.

## Overview

A workspace in `repo_status='ready'` whose `workspaces.github_installation_id IS NULL` is
**unreachable by the push-driven reconcile** (`workspace-reconcile-on-push.ts:171-172` filters
`WHERE github_installation_id = <push.installation.id> AND repo_url = …`, so a NULL-install row never
matches). The daily probe `cron-workspace-sync-health` detects this class (arm-1) and reports each
finding to Sentry via `reportSilentFallback` (`op:ready-null-installation`) — a deliberate read-only
backstop built after this exact state froze the founder's own KB for ~5 weeks. The probe **reports
but never resolves**, so a genuine ready+NULL-install workspace stays frozen indefinitely (Sentry
folds the recurring occurrences into a single standing issue — 33 occurrences as of
2026-06-29T06:23Z ≈ **one workspace stuck ~33 days**, not 33 distinct alerts).

This plan turns arm-1 from a pure reporter into an **entitlement-scoped, solo-only reconciler**:

- **Resolve (solo only):** for each ready+NULL-install **solo** workspace, resolve the installation
  the *owner is entitled to reach* for that repo — `resolveReachableInstallationIds` (scoped to the
  owner's `user_id` + `github_username`) → `resolveOwningInstallationForRepo` — and **backfill**
  `workspaces.github_installation_id` via the canonical `writeRepoColsToWorkspace` boundary. The
  workspace becomes reachable by reconcile and the standing Sentry signal clears on the next scan.
- **Skip (keep the visible signal):** when the install is genuinely unresolvable (owner not
  entitled, app uninstalled, listing empty), or the workspace is a **team** workspace (never
  auto-detect its install), keep the existing folded `reportSilentFallback` — it stays visible as
  one standing issue (no daily flood, since Sentry folds it) and surfaces the actionable re-auth need.
- **No-op on transient:** a degraded GitHub probe leaves the row untouched and self-recovers next fire.

It **never flips `repo_status`** (carrying forward only the narrow ADR-044 "never persist
`repo_status=error`" sub-rule — see Architecture Decision).

## Premise Validation (Phase 0.6)

**The issue's monitor attribution is wrong; the underlying gap is real; the resolution mechanism
needs the entitlement gate.**

- **Cited issues/PRs hold.** #5675 OPEN; #5580 merged 2026-06-18 (`63bfa9be0`); ADR-044 `accepted`
  with a 2026-06-18 amendment on exactly the null-install-vs-not-connected distinction.
- **Error-string provenance (key correction).** The string `"ready workspace has NULL
  github_installation_id — unreachable by reconcile"` is at `cron-workspace-sync-health.ts:136`
  (`op: "ready-null-installation"`) — **NOT** `cron-follow-through-monitor.ts`. Deliberate
  `reportSilentFallback`.
- **Schedule/timestamp confirm the source.** `cron-workspace-sync-health` runs `23 6 * * *` = 06:23
  UTC daily, matching "last seen 06:23Z" exactly. `cron-follow-through-monitor` runs `0 9 * * 1-5`
  and is an unrelated Claude-agent processing `follow-through`-labeled issues — no install logic.
- **"posts error check-ins every fire" is doubly imprecise.** The cron does not crash; its heartbeat
  posts `ok: scan.ok` (true). The "error" is a Sentry *issue* that Sentry *folds* into one — not 33
  separate pages.
- **Mechanism vs ADR corpus (refined by deepen review).** ADR-044's end-state endorses resolving the
  install from the repo, **but only via the entitlement-bounded connect flow** (user-token-scoped).
  The 2026-06-18 dispatch amendment **rejected** binding the install on a null-install divergence at
  the *dispatch* path (membership-deny case), because un-gated binding re-opens the credential-leak
  surface. This plan resolves the tension: the cron reads the **true** NULL (service-role, not
  membership-deny), resolves **only within the owner's entitlement-scoped reachable installs**, and
  writes **only solo** workspaces — so it does not re-open the surface the amendment closed.
- **Capability claims verified at plan time:** `resolveReachableInstallationIds(service, userId,
  githubLogin): Promise<number[]>` (`reachable-installations.ts:33`),
  `resolveOwningInstallationForRepo(ids, owner, repo): Promise<number|null>` (`:108`),
  `writeRepoColsToWorkspace(service, workspaceId, patch)` with `github_installation_id` in
  `WorkspaceRepoCols` + 0-row Sentry mirror (`workspace-repo-mirror.ts:63`), `isSoloWorkspace =
  activeWorkspaceId === user.id` (`repo/setup/route.ts:247`), `users.github_username` read
  (`repo/setup/route.ts:121`). All confirmed.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| `cron-follow-through-monitor` / `scheduled-follow-through` failing at 09:00 weekdays | Error string is at `cron-workspace-sync-health.ts:136`; that cron runs 06:23 UTC daily. `scheduled-follow-through` has no install logic. | Fix `cron-workspace-sync-health` arm-1; do not touch the follow-through monitor. Record mis-attribution in PR body. |
| Monitor "fails / posts error check-ins every fire" | Heartbeat posts `ok:true`; the "error" is a `reportSilentFallback` Sentry issue that Sentry **folds** into one standing issue. | Reframe: the defect is non-resolution (KB frozen), not paging fatigue. |
| Resolve the install "from the repo" (issue + ADR end-state) | The connect flow resolves via **entitlement-scoped** `resolveReachableInstallationIds`+`resolveOwningInstallationForRepo`; bare `findInstallationByAccountLogin` is never called directly because it over-grants org installs. | Use the entitlement-scoped resolver. Backfill solo workspaces only. |
| "explicitly skip-with-reason so it no-ops cleanly instead of erroring" | The signal already folds to one issue; the alert is feature-only/level-agnostic, so demoting the level is a no-op. | Drop signal-demotion; keep the folded visible signal for the unresolvable case. Resolution (not demotion) is the fix. |
| Cron is read-only (`.service-role-allowlist:246-254`: "performs NO writes") | True today. | Adds the credential backfill via `writeRepoColsToWorkspace`. Update the allowlist rationale. |

## Hypotheses

The Phase 1.4/4.5 network-outage gate fired on the substring **`unreachable`**. **False trigger:**
"unreachable by reconcile" is **query-filter** unreachability (a NULL-install row never matches the
reconcile's `WHERE github_installation_id = …` predicate), not an L3/L7 network failure. No SSH,
host, egress IP, or firewall is in this path (the cron runs in-process in the Next.js container over
the existing Supabase client). No `hr-ssh-diagnosis-verify-firewall` telemetry is emitted — no
network diagnosis is being performed.

**Network-Outage Deep-Dive (layer status):** L3 firewall — N/A (no host/egress). L3 DNS/routing —
N/A. L7 TLS/proxy — N/A. L7 application — the only "reachability" is the SQL predicate; verified by
reading `workspace-reconcile-on-push.ts:171-172`. No gaps to close.

Producer hypotheses for *why a ready+NULL-install row exists* (fix is producer-agnostic; informs the
required-on-signal producer follow-up): (1) legacy pre-GitHub-App connection (predates the
entitlement gate — most likely, and exactly why solo+entitlement-scoping is needed); (2)
incomplete/failed re-auth where `repo_status='ready'` but the install write was skipped; (3) mig-080
solo backfill landed `repo_url` while the source install was NULL.

## User-Brand Impact

**If this lands broken, the user experiences:** their KB silently never syncs (stale tree forever) —
the ~5-week founder-KB freeze the probe exists to catch.

**If this leaks, the user's repo-access credential is exposed via:** `github_installation_id` is a
GitHub App installation-token grant (repo write access, also consumed by agent dispatch for
issue/PR/push). The exposure vector is **over-binding an org's full-write install onto a workspace
whose owner is not entitled** (e.g. an outside read-only collaborator). Mitigated structurally and
decisively by the deepen revision: resolution is **entitlement-scoped to the owner's reachable
installs** (`resolveReachableInstallationIds` keyed on the owner's `user_id`+`github_username`) and
**restricted to solo workspaces** (team installs are never auto-detected); the write is keyed on the
workspace's own server-derived id via the canonical `writeRepoColsToWorkspace` boundary. An install
the owner cannot reach is never resolved, so it can never be bound.

**Single-user freeze/visibility vectors (user-impact review) and their disposition:**
- *Wrong install bound* → prevented by entitlement-scoping + solo-only (see above).
- *Install NOT backfilled when resolvable (page-cap/degraded false-negative)* → fail-safe (no wrong
  write). On an **all-degraded** sweep the outcome is `transient`: no write AND no per-fire Sentry
  occurrence — the fire is captured only in the `{reconciled,skipped,transient}` Better Stack
  step-return count (`alert_route: none`, per the Observability table). It is **not** silently dark in
  the freeze sense: a `transient` fire does **not** clear the pre-existing standing folded
  `op:ready-null-installation` issue, and a permanent darkening would require a *permanent* GitHub 5xx
  for that repo's probe (not a steady state — it self-recovers to `reconciled`/`needs-reauth` on the
  next fire once the probe is healthy).
- *Genuinely-broken workspace darkened* → does NOT happen: **every** unresolvable skip reason
  (`needs-reauth`, `team-workspace-never-auto-detect`, AND `malformed-repo-url`) keeps the existing
  feature-tagged `op:ready-null-installation` Sentry issue (the alert is feature-only, so it stays
  notification-covered). The v1 "demote to non-paging" idea — which WOULD have darkened it — is
  dropped, and the malformed-repo-url subset is **not** silenced (a ready+NULL-install workspace is
  stuck regardless of why it is unresolvable; review-driven correction of the earlier "mirror arm-3
  silent-skip" note).
- *Next-push latency after backfill (low-activity repo)* → see the immediate-resync scope-out
  (rewritten below to not assume high activity).

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` (`requires_cpo_signoff: true`).
> `user-impact-reviewer` re-runs at review-time.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- `grep -nA6 "resolveReachableInstallationIds\|resolveOwningInstallationForRepo" apps/web-platform/server/reachable-installations.ts` — confirm signatures.
- Confirm `writeRepoColsToWorkspace` accepts `github_installation_id` and mirrors 0-row to Sentry (`apps/web-platform/server/workspace-repo-mirror.ts`).
- Confirm `cron-workspace-sync-health.ts` is on `.service-role-allowlist` (line 254).
- Read arm-3's slug parser + silent-skip (`cron-workspace-sync-health.ts:361-369`) to reuse the pattern.

### Phase 1 — Entitlement-scoped, solo-only decision helper (RED first)
- Extend the arm-1 scan to also fetch, per finding, the owner identity needed for solo classification + resolution. Solo workspaces satisfy `workspaces.id == users.id` (ADR-038 N2); join `users` by the finding id to get `github_username` (stays a `users` read per ADR-044). A finding whose id is **not** a `users.id` (team workspace) → not solo.
- Add an inline top-level helper (mirroring the in-file `scanReadyWorkspaces` pattern — **no sibling file**), injected-deps shaped, returning a **3-outcome** union: `{ kind: "reconciled", installId } | { kind: "skip", reason } | { kind: "transient" }`.
- Decision table per finding:
  1. **Not solo (team / id not a users.id)** → `skip` (reason `team-workspace-never-auto-detect`). No write.
  2. Derive `owner/repo` from `repo_url` (reuse arm-3's slug parser, extracted to a shared `parseOwnerRepo` helper). Falsy owner|repo → `skip`, reason `malformed-repo-url`. **Review-driven correction:** unlike arm-3's silent went-quiet `continue`, arm-1 KEEPS the visible `op:ready-null-installation` signal for the malformed case — a ready+NULL-install workspace is genuinely stuck regardless of why it is unresolvable, so silencing it would re-introduce the freeze blind spot (data-integrity + user-impact review L2/Finding-1).
  3. `reachable = resolveReachableInstallationIds(service, ownerUserId, ownerGithubLogin)`.
     - empty → `skip` (reason `needs-reauth`; owner has no reachable install for the app).
  4. `install = resolveOwningInstallationForRepo(reachable, owner, repo)`.
     - `null` after non-empty reachable → `skip` (reason `needs-reauth` if conclusively absent, or `transient` if the probe degraded — `resolveOwningInstallationForRepo` keeps probing on `degraded` and returns null inconclusively; treat an all-degraded sweep as `transient`).
     - install id → `{ kind: "reconciled", installId: install }`.
- Write failing unit tests for every arm BEFORE implementation (`cq-write-failing-tests-before`), including the **negative** test: an org-owned repo whose owner is NOT entitled (not in reachable) → `skip`/`needs-reauth`, **no write**.

### Phase 2 — Wire the decision into arm-1, per-workspace step boundary
- Replace the `report-unreachable-workspaces` step. For each finding, run the helper inside its **own** `step.run(\`reconcile-${workspaceId}\`, …)` so each backfill memoizes independently and a mid-loop throw does not re-probe/re-write others (ADR-033 I5; the step now has side effects).
- On `reconciled`: call `writeRepoColsToWorkspace(service, workspaceId, { github_installation_id: installId })` (inherits 0-row detection + Sentry mirror; this also satisfies the backfill-failure observability path — the helper mirrors DB errors). Optional CAS hardening: a concurrent connect-flow write is benign because the resolver is value-idempotent (it resolves the owner's same owning install); if desired, add an `onlyIfNull` guard to the helper, but it is not load-bearing at solo/internal scale.
- On `skip` (EVERY reason — `team-workspace-never-auto-detect`, `needs-reauth`, AND `malformed-repo-url`): keep the existing `reportSilentFallback(op:"ready-null-installation", extra:{ workspaceId, repoUrl, reason })` (folds to one standing issue; carry the `reason` in `extra` for discriminability). **Do not** demote the level and **do not** edit `infra/sentry/issue-alerts.tf`.
- On `transient`: no write, no signal; counted in the deterministic step return.
- Aggregate into the deterministic return `{ reconciled, skipped, transient }` (ADR-033 I5); arms 2 & 3 unchanged in code.
- Update the file header: arm-1 now performs an entitlement-scoped, solo-only credential backfill via `writeRepoColsToWorkspace` (still never flips `repo_status`).

### Phase 3 — `.service-role-allowlist` rationale update
- Update the `cron-workspace-sync-health.ts` rationale (lines 246-254): no longer "performs NO writes" — it now performs an entitlement-scoped, solo-only `github_installation_id` backfill via `writeRepoColsToWorkspace`, server-keyed on the finding's own id. Path line stays (no CODEOWNERS-gated addition).

### Phase 4 — ADR-044 amendment + sentinel sweep
- Author the ADR-044 amendment (see Architecture Decision) — honest exception-carve + reconciliation with the 2026-06-18 rejected option + "arc COMPLETE" acknowledgement.
- `hr-write-boundary-sentinel-sweep`: confirm the only `github_installation_id` write reachable from the cron routes through `writeRepoColsToWorkspace` (server-keyed). `hr-type-widening-cross-consumer-grep`: the column already exists in `WorkspaceRepoCols`; confirm no consumer assumed this path never populates it.

### Phase 5 — Verify
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-workspace-sync-health.test.ts`
- service-role-allowlist CI gate (path present).

### Required-on-signal (promoted from optional per architecture review)
- **Producer investigation.** If the `skip(needs-reauth)` or `transient` count stays non-zero after a one-week soak, the write-path that mints `ready`+NULL rows MUST be investigated (the cron is a backstop, not the fix-of-record). File the tracking issue now; close it only if the soak shows zero residual.

### Out of scope (deferred — tracking issue)
- **Immediate re-sync after backfill.** Backfill makes the workspace reachable by the **next** push; it does not sync the current HEAD. Triggering an immediate reconcile needs a push-shaped payload and expands blast radius. Deferred. Honest latency bound (rewritten per user-impact review): for a **low-activity** repo the un-frozen sync can lag days until the next push; accepted at p2 because (a) the very next push does a full default-branch-HEAD reconcile (catches up everything accumulated), and (b) arm-3 (went-quiet) now correctly DETECTS the lag once the install resolves and emits the visible went-quiet signal. File the tracking issue.

## Files to Edit
- `apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts` — solo classification + entitlement-scoped resolution + per-workspace `step.run` backfill via `writeRepoColsToWorkspace`; inline 3-outcome helper; header update; deterministic step return.
- `apps/web-platform/.service-role-allowlist` — update rationale (now performs the backfill write).
- `apps/web-platform/test/server/inngest/cron-workspace-sync-health.test.ts` — new arm-1 scenarios incl. the org-repo-not-entitled negative test and the team-workspace skip.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amendment.

## Files to Create
- None. (The decision helper stays inline per the simplicity review; the writer is the existing `writeRepoColsToWorkspace`.)

## Acceptance Criteria

### Pre-merge (PR)
- AC1: a ready+NULL-install **solo** workspace whose owner's reachable installs include the repo's owning install → `reconciled`; `writeRepoColsToWorkspace` is called with `{ github_installation_id: <that install> }` keyed on the finding id (unit test asserts the writer spy args).
- AC2 (**negative, load-bearing**): an org-owned repo whose owner is **not** in `resolveReachableInstallationIds` → `skip(needs-reauth)`, writer spy **not** called. This is the cross-tenant-over-grant guard.
- AC3: a **team** workspace finding (id not a `users.id`) → `skip(team-workspace-never-auto-detect)`, no write.
- AC4: empty reachable → `skip(needs-reauth)`; all-degraded owning probe → `transient`, no write, no signal. Malformed `repo_url` → `skip(malformed-repo-url)` that KEEPS the visible `op:ready-null-installation` signal (no write, no resolver call, but the stuck workspace stays visible — review-corrected from silent-skip).
- AC5: the backfill routes through `writeRepoColsToWorkspace` (single write boundary; sentinel sweep shows zero net-new write sites) and runs inside a per-workspace `step.run`.
- AC6: arm-1 step returns deterministic `{ reconciled, skipped, transient }`; arms 2 & 3 unchanged in code; a workspace backfilled by arm-1 does **not** spuriously fire arm-2/arm-3 in the same invocation (regression test for the intra-fire mutation).
- AC7: the `skip` path keeps `reportSilentFallback(op:"ready-null-installation")` (no level demotion, no `issue-alerts.tf` edit) — the signal stays visible.
- AC8: `tsc --noEmit` + `vitest run test/server/inngest/cron-workspace-sync-health.test.ts` pass (from `apps/web-platform`, via `./node_modules/.bin/`).
- AC9: `.service-role-allowlist` rationale updated; CI service-role-allowlist gate passes.
- AC10: ADR-044 amendment authored (exception-carve + reconciliation); PR body uses `Ref #5675`, records the monitor mis-attribution.

### Post-merge (operator)
- AC11: After the next `23 6 * * *` fire, confirm reconciled solo workspaces drop out of the scan — read the standing `op:ready-null-installation` Sentry issue by its short-id (`doppler run -p soleur -c prd -- scripts/sentry-issue.sh <issue-id>`; the id is surfaced by `/soleur:postmerge` Phase 3.8's Sentry-warning step) and confirm its occurrence count stops climbing. Read-only API, SSH-free (`hr-no-dashboard-eyeball-pull-data-yourself`). (`sentry-issue.sh` reads one issue by positional id — it has no `--query` flag.)
- AC12: Confirm `reconciled` workspaces now carry a non-NULL `github_installation_id` (read-only prod query, `DATABASE_URL_POOLER`). Close #5675 only after the signal plateaus.
- AC13: If `needs-reauth`/`transient` count is non-zero after the soak, open/keep the producer-investigation issue (required-on-signal).

## Observability

```yaml
liveness_signal:
  what: cron-workspace-sync-health end-of-job heartbeat (unchanged)
  cadence: daily 23 6 * * * UTC
  alert_target: Sentry cron monitor slug "cron-workspace-sync-health"
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry via reportSilentFallback (scan failures + skip/needs-reauth findings + backfill DB errors mirrored by writeRepoColsToWorkspace)
  fail_loud: scan-query DB errors page (op=scan); unresolvable findings keep the visible feature-tagged issue (op=ready-null-installation); backfill write errors mirror via writeRepoColsToWorkspace's 0-row/error path
failure_modes:
  - mode: backfill write fails or 0-row (workspace deleted between scan and write)
    detection: writeRepoColsToWorkspace's existing Sentry mirror (workspace-repo-mirror.ts)
    alert_route: Sentry issue (feature=workspace-sync-health)
  - mode: owner not entitled / app uninstalled (genuinely unresolvable)
    detection: skip(needs-reauth) keeps reportSilentFallback op=ready-null-installation
    alert_route: Sentry issue, folded — stays visible, no daily flood (alert is feature-only, level-agnostic)
  - mode: team workspace in scan set
    detection: skip(team-workspace-never-auto-detect), counted in step return + existing report
    alert_route: Sentry issue (feature-tagged), visible
  - mode: GitHub probe/listing degraded (token/network/5xx)
    detection: transient, counted in step return; self-recovers next fire
    alert_route: none (Better Stack step-return counts)
logs:
  where: pino -> Better Stack (step-return {reconciled,skipped,transient} at info)
  retention: per existing Better Stack retention
discoverability_test:
  # Point-in-time, no-SSH, no-cred: 401 is the Inngest serve HMAC challenge, which
  # proves the cron-workspace-sync-health function is registered + serving (its
  # error path reports to Sentry via the wired observability middleware). The
  # standing-signal *plateau* is inherently a multi-fire soak, so it lives in the
  # AC11/AC12 post-deploy observation (follow-through), not a single-shot probe.
  # (The prior `sentry-issue.sh --query …` command never ran: that script takes a
  # positional <issue-id> and rejects `--query` with exit 64 — caught by preflight
  # Check 10, which executes the command instead of only checking field presence.)
  command: 'curl -sS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/api/inngest'
  expected_output: "401"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-044** with a dated subsection: *"Amendment 2026-06-29 — periodic backstop reconciles
ready+NULL-install (entitlement-scoped, solo-only)."* It must:
- **Decision:** `cron-workspace-sync-health` arm-1 backfills `workspaces.github_installation_id` for
  **solo** workspaces only, resolving the install via the **entitlement-scoped** connect-path
  resolver (`resolveReachableInstallationIds` keyed on the owner's `user_id`+`github_username` →
  `resolveOwningInstallationForRepo`); team workspaces and unresolvable findings keep the existing
  visible Sentry signal.
- **Honest exception-carve (architecture Finding C):** this carries forward only the narrow *"never
  persist `repo_status=error`"* sub-rule of the 2026-06-18 zero-write rule — it is **not** "zero
  workspaces writes." A *populating* `github_installation_id` write is safe here (unlike the dispatch
  path) because: (a) the cron reads the **true** NULL via service-role, not a membership-deny NULL;
  (b) resolution is entitlement-scoped to the owner's reachable installs (does **not** widen the
  credential RPC, the option the 2026-06-18 amendment rejected); (c) it is solo-only (no shared-row
  cross-tenant corruption). State this distinction explicitly.
- **Reconcile against the rejected option:** the 2026-06-18 "widen `resolve_workspace_installation_id`
  to return the install on membership-deny" rejection stands; this amendment does the opposite of
  widening — it resolves server-side within entitlement scope and never exposes the credential to a
  non-member.
- **Acknowledge "arc COMPLETE":** the column-ownership decision remains complete; this amends the
  *operational reconciliation consequence*, not the ownership grain.
- **Alternatives:** (a) demote-only signal — rejected (leaves KB frozen; and the feature-only alert
  makes level-demotion a no-op); (b) bare `findInstallationByAccountLogin` — rejected (over-grants org
  installs, cross-tenant escalation); (c) flip `repo_status='error'` — rejected (blanks the KB tree).

### C4 views
**No C4 impact.** Enumeration against `model.c4`, `views.c4`, `spec.c4`:
- **Actors:** affected user is a workspace Owner — covered by the `founder` actor (`model.c4:8-9`,
  multi-Owner). No new actor.
- **External systems:** GitHub (install resolution + repo probe) is the existing `github` system
  (`model.c4:171`); edges `engine -> github` / `api -> github` already modeled. No new vendor.
- **Stores:** `workspaces.github_installation_id` write hits the existing `supabase` database
  (`model.c4:139`); the column is below model granularity. No new store.
- **Access relationships:** a service-role read+write of `workspaces.github_installation_id` is
  code-granularity, below the C4 component grain — consistent with every prior ADR-044 amendment's
  "captured in ADR prose, not a `.c4` edit." `grep` of `knowledge-base/**/*.c4` for
  `installation`/`reconcile`/`sync-health`/`adr-044` is empty. Confirmed by the architecture-strategist
  review (the went-quiet arm already calls GitHub + writes Supabase from this container with no `.c4`
  change).

### Sequencing
Same PR. No schema change, no migration, no soak gate on the code (the credential RPC is unmodified).
AC11-AC13 are observation-only.

## Domain Review

**Domains relevant:** Engineering (CTO).

Backend Inngest-cron behavioral fix with a credential-column write + ADR amendment. No UI surface →
Product/UX Gate = **NONE**. No finance/legal/marketing/sales/ops/support impact.

### Engineering (CTO)
**Status:** reviewed (deepen-plan, 6 review agents + 1 mechanical grep).
**Assessment:** The locus (cron) and altitude (backfill) are endorsed by the architecture review. The
load-bearing correctness/security issue — un-gated install resolution over-granting org credentials —
was caught by 3 independent agents (security HIGH, data-integrity P1, architecture HIGH) and is
resolved by the entitlement-scoped + solo-only revision, which is exactly the connect-flow's own
resolution path. CPO sign-off required (single-user-incident threshold).

### Product/UX Gate
**Tier:** none — no user-facing surface.

## Open Code-Review Overlap

None. No open `code-review`-labeled scope-out touches `cron-workspace-sync-health.ts`,
`.service-role-allowlist`, `workspace-repo-mirror.ts`, or ADR-044 at plan-write time.

## Risks & Mitigations / Sharp Edges
- **Cross-tenant credential over-grant (was the v1 defect).** Resolved: entitlement-scoped resolver +
  solo-only. The negative AC2 pins it. Do NOT revert to bare `findInstallationByAccountLogin` (its
  docstring states `checkRepoAccess` cannot tell the owning install from a collaborator install —
  `github-app.ts:552-559`).
- **Precedent-diff (Phase 4.4).** Credential-column write precedent: `writeRepoColsToWorkspace`
  (`workspace-repo-mirror.ts:63`) is the canonical boundary — keyed on `eq("id", workspaceId)`,
  accepts `github_installation_id`, has 0-row Sentry mirror. The plan **calls** it (no new writer).
  Resolution precedent: `repo/setup/route.ts:151-160` uses the exact
  `resolveReachableInstallationIds`+`resolveOwningInstallationForRepo` pair. No novel pattern.
- **Inngest replay determinism.** Per-workspace `step.run` boundary; the write is value-idempotent
  (resolves the owner's same owning install).
- **Intra-fire arm coupling.** Arm-1 now mutates state arms 2/3 read later in the same invocation;
  AC6 regression test asserts a backfilled workspace does not spuriously fire arm-2/arm-3 same fire.
- **`needs-reauth` false-negative (page-cap/degraded listing).** Fail-safe (no wrong write); the
  workspace keeps the visible folded signal, never silently dark.
- **Do NOT edit `infra/sentry/issue-alerts.tf`.** The feature-only alert already folds the signal;
  level-demotion is a no-op and a narrowed op/level filter would risk darkening the unresolvable
  signal (the original 5-week-freeze failure mode).
- **Do NOT flip `repo_status`.** Carries forward the narrow ADR-044 sub-rule.
- **An empty `## User-Brand Impact` would fail deepen-plan Phase 4.6** (filled above).
- **Test-runner discipline.** `./node_modules/.bin/vitest run <path>` + `./node_modules/.bin/tsc --noEmit` from `apps/web-platform` (no `npm run -w`, no bare `bun test`).

## Test Scenarios
1. solo, owner-entitled, owning install resolves → `reconciled`, `writeRepoColsToWorkspace` called with the resolved install id keyed on the finding id.
2. **solo, org-owned repo, owner NOT in reachable installs → `skip(needs-reauth)`, no write** (the cross-tenant over-grant guard — load-bearing).
3. team workspace finding (id not a users.id) → `skip(team-workspace-never-auto-detect)`, no write.
4. empty reachable → `skip(needs-reauth)`; all-degraded owning probe → `transient`, no write/signal; malformed repo_url → `skip(malformed-repo-url)` keeping the visible signal (no write, no resolver call).
5. backfill write 0-row / DB error → mirrored by `writeRepoColsToWorkspace`, row left NULL, not counted `reconciled`.
6. scan-query DB error → pages via `reportSilentFallback` op=scan (unchanged); arms 2/3 still run; heartbeat fires.
7. a workspace backfilled by arm-1 does not spuriously fire arm-2 (stale-sync) or arm-3 (went-quiet) in the same invocation.
8. deterministic step return `{reconciled,skipped,transient}` (replay safety).

## References
- ADR-044 (`knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`), esp. the 2026-06-18 membership-deny amendment.
- `knowledge-base/project/learnings/2026-06-18-multi-workspace-per-installation-breaks-founder-resolve-and-ready-clone.md`.
- `knowledge-base/project/learnings/workflow-patterns/2026-05-22-plan-review-and-deepen-plan-catch-different-issue-classes.md` (deepen-plan domain agents caught the entitlement-gate issue plan-review/structural agents would miss — exactly this case).
