---
title: "Revert #4913 service-role fallback + wire KB db-error alert (PIR #4913 follow-ups)"
date: 2026-06-04
type: fix
branch: feat-one-shot-revert-4913-fallback-db-error-alert
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related:
  - PIR: knowledge-base/engineering/operations/post-mortems/generate-link-tenant-mint-regression-postmortem.md
  - PR #4913 (the fallback to revert)
  - PR #4920 (#4918 — the KB tenant-mint alert this follow-up mirrors)
  - PR #4922 (the real workspace_id NOT-NULL insert fix)
  - PR #4919 (#4914 — per-cause fallback on authenticateAndResolveKbPath; scope question)
---

# Revert #4913 service-role fallback + wire KB db-error alert 🐛

## Enhancement Summary

**Deepened on:** 2026-06-04
**Sections enhanced:** Phase 1, Acceptance Criteria, Infrastructure (IaC)
**Verification passes run:** premise-validation (all 3 PRs MERGED), verify-the-negative
(4 load-bearing claims grepped against code), precedent-diff (4.4), hard gates 4.6/4.7/4.8/4.9
(all pass).

### Key Improvements
1. **Corrected the allowlist-gate claim.** Read `service-role-allowlist-gate.sh` in full:
   the gate is DIRECTIONAL (fails only on un-allowlisted importers), NOT atomic. The earlier
   draft overstated "import removal + allowlist line removal must be in the same commit."
   Removing the stale allowlist line is cleanliness/hygiene, not CI-forced.
2. **Pinned the precedent diff.** The new `kb_db_error` rule is a field-verified 1:1 clone
   of `chat_message_save_failure`; frequency 13 confirmed free.
3. **Verified the op vocabulary.** `kb-share.ts` emits `feature=kb-share` ops
   `create/list/preview/preview-invariant/revoke` — the alert filter set is grounded, not paraphrased.

### New Considerations Discovered
- The user's stated rationale ("fallback worked around the workspace_id bug; #4922 fixed it")
  is **inaccurate** — the fallback guards a tenant-mint `RuntimeAuthError`, a different path.
  It is dead code because the PIR proved the mint failure was a *misdiagnosis* (mint works in
  prod), not because #4922 fixed the insert. The PR body must carry the accurate rationale.
- **Scope is genuinely open:** #4914 is CLOSED but #4919 MERGED a fallback for
  `authenticateAndResolveKbPath` anyway. The whole-mint-fallback-family revert (plan default)
  is the only scope that lets the `createServiceClient` import + allowlist line be dropped
  cleanly. CPO sign-off should confirm scope before /work.
- Do NOT `git revert -m` #4913 mechanically — it would delete the `reportSilentFallback`
  emit that the #4920 alert keys on. Hand-revert, preserving the emit.

---


> Spec lacks valid `lane:` — defaulted in frontmatter to `cross-domain` only if the
> spec is later found to omit it (TR2 fail-closed). This plan sets `lane: cross-domain`
> explicitly (touches app server code + Terraform/Sentry infra + tests).

## Overview

Two PIR #4913 follow-ups, both already enumerated as action items in the
post-mortem (`## Follow-ups` lines 102-103):

1. **Revert the now-dead service-role fallback** PR #4913 added to
   `resolveUserKbRoot` (`apps/web-platform/server/kb-route-helpers.ts`), restoring
   the tenant-only boundary and removing the unjustified `.service-role-allowlist`
   re-introduction. The PIR's confirmed root-cause analysis proved the tenant-JWT
   mint was a **misdiagnosis** — it works fine in prod (a real founder JWT was
   minted and the `.from("users")…single()` self-read returned the row with no
   error). The real cause was the missing `workspace_id` on NOT-NULL inserts,
   fixed in #4922. So the mint-failure branch the fallback guards is dead code on
   the share/read path.

2. **Wire a KB db-error alert** so a constraint that "breaks every insert" (the
   23502 NOT-NULL class that caused this incident, and the 42501 RLS class that
   caused the 3-week chat outage #4831) **pages on first occurrence** instead of
   sitting latent ~19 days. The signal already exists — `createShare`'s db-error
   path at `kb-share.ts:340` calls `reportSilentFallback(feature:"kb-share",
   op:"create")` — but no Sentry issue-alert is wired to it. This mirrors #4920's
   `kb_tenant_mint_silent_fallback` rule exactly (op-scoped `sentry_issue_alert`,
   apply-created, added to `apply-sentry-infra.yml` `-target` set, pinned by a
   cross-artifact op-contract test).

This is a **deletion + follow-the-pattern** change. No new tech, no new
infrastructure root, no UI. The hard part is the two mechanical couplings the
revert creates (below), which a naive `git revert` would silently break.

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS / user framing) | Codebase reality (verified) | Plan response |
|---|---|---|
| "The fallback was added to work around the missing `workspace_id` on NOT-NULL inserts." | **Partially inaccurate.** The fallback in `resolveUserKbRoot` (`kb-route-helpers.ts:273-287`) guards a `RuntimeAuthError` from `getFreshTenantClient` (tenant-JWT mint: `jwt_mint`/`rotation`/`denied_jti`) — a *different* failure path than the missing-`workspace_id` insert bug. It is dead code not because #4922 fixed the insert, but because the PIR proved the mint failure **never actually occurred in prod** (misdiagnosis, PIR §Root-cause-hypothesis: REJECTED). | Revert is still correct (dead code), but for the PIR's reason (misdiagnosis), not the user's stated reason (workspace_id fix). The PR body must state the accurate rationale so a future reader does not conclude the mint can never fail. |
| "Remove the service-role escape hatch from `resolveUserKbRoot`." | `kb-route-helpers.ts` also hosts `authenticateAndResolveKbPath`, which got its OWN per-cause service-role fallback in **PR #4919** (`:79-122`), importing the same `createServiceClient`. Issue #4914 (the file-route fallback) is **CLOSED**, yet #4919 shipped a fallback for it anyway. | **OPEN SCOPE DECISION** (see Sharp Edges + Open Questions). The user names only `resolveUserKbRoot`. The PIR (line 109) says close #4914 "as based-on-misdiagnosis." Plan default: **revert BOTH** mint-fallback paths in the file (the whole misdiagnosis-derived family), which lets us drop the `createServiceClient` import + the `.service-role-allowlist` line entirely. Deepen-plan + CPO sign-off confirm or narrow. |
| "Alert on the DB insert/constraint error rate the way #4920 alerted." | #4920 (`kb_tenant_mint_silent_fallback`) filters `feature=="kb-route-helpers"` AND `op IS_IN (resolveUserKbRoot.tenant-mint, authenticateAndResolveKbPath.tenant-mint, kb-sync.tenant-mint)`. The db-error insert signal is a DIFFERENT feature/op family: `feature=="kb-share"`, `op IS_IN (create, list, revoke, preview, preview-invariant)` from `kb-share.ts`. | New alert rule `kb_db_error` (or `kb_share_db_error`) filters the `kb-share` family. The `create` op is the 23502 "breaks every insert" path. Same `sentry_issue_alert` shape, distinct `frequency` (next free value), op-contract test. |
| "Removing the fallback is a clean revert." | The #4920 op-contract test (`sentry-kb-tenant-mint-alert-op-contract.test.ts:53`) ASSERTS `resolveUserKbRoot.tenant-mint` exists as a literal in `kb-route-helpers.ts`, and the #4920 alert's `IS_IN` filter (`issue-alerts.tf:519`) lists it. Removing the emit silently breaks that test AND leaves a dead slug in the live alert. | The revert MUST also update `issue-alerts.tf` (drop the dead slug from `kb_tenant_mint_silent_fallback`'s `IS_IN`) and the op-contract test (drop the corresponding `OP_SLUGS` row). If `authenticateAndResolveKbPath.tenant-mint` is also reverted, drop that slug too. |

## User-Brand Impact

**If this lands broken, the user experiences:**
- (Revert) If the revert removes the `reportSilentFallback` emit *without* preserving it, the
  #4920 tenant-mint alert and the new db-error alert lose their signal — a future
  insert-breaking migration sits latent again (the exact #4913 failure mode).
- (Revert, worst case) If the scope decision wrongly removes a fallback path that is load-bearing,
  a tenant-mint failure could 503 the "Generate link" / file-mutation surface — but the PIR
  proves the mint does not fail in prod, so this is a latent-not-active regression.
- (Alert) If the alert filter mis-keys (wrong `feature`/`op` slug, wrong `action_match`), the
  next "breaks every insert" constraint failure pages no one — the latent-19-days outcome recurs.

**If this leaks, the user's data is exposed via:** N/A directly — but the *point*
of the revert is to REMOVE a service-role read path. Restoring the tenant-only
boundary on `resolveUserKbRoot` strengthens cross-tenant isolation (the
service-role fallback, though hard-scoped `.eq("id", userId)`, is a broader
credential than the tenant-scoped read it replaces).

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. The threshold is
> inherited from the PIR (`brand_survival_threshold: single-user incident`):
> a mis-wired alert re-opens the precise single-user dead-end the PIR documents,
> and a wrong-scope revert touches the tenant-isolation boundary. Invoke CPO
> domain leader (or confirm CPO reviewed the PIR) before work. `user-impact-reviewer`
> runs at review-time per `review/SKILL.md`.

## Implementation Phases

> Phase order is load-bearing: the emit-site edits (Phase 1) change the `op`-slug
> contract that the alert filter + op-contract test (Phase 2/3) assert on. Do the
> emit change first, then reconcile the dependent alert/test artifacts.

### Phase 0 — Preconditions (verify before editing)

- [ ] `grep -n "createServiceClient" apps/web-platform/server/kb-route-helpers.ts` — confirm
      the 2 fallback call-sites (`:114` authenticate, `:283` resolve) + the import (`:4`).
- [ ] `grep -n "kb-route-helpers.ts" apps/web-platform/.service-role-allowlist` — confirm
      the #4913 re-introduction line is present (it is the LAST entry).
- [ ] Read `apps/web-platform/test/sentry-kb-tenant-mint-alert-op-contract.test.ts:53-70`
      and confirm the 3 `OP_SLUGS` rows + which are emitted from `kb-route-helpers.ts`.
- [ ] `grep -n "frequency" apps/web-platform/infra/sentry/issue-alerts.tf | grep -oE '= [0-9]+'`
      — enumerate the TAKEN frequency set (currently 5,10,11,12,15,30,60,61,62). Pick the
      next free integer for the new db-error rule (likely **13**) to avoid Sentry POST-time
      exact-duplicate dedup.
- [ ] CPO sign-off recorded (single-user-incident threshold gate).
- [ ] **Resolve the scope decision** (revert `resolveUserKbRoot` only, or the whole
      mint-fallback family incl. `authenticateAndResolveKbPath` #4919). Default: whole family.

### Phase 1 — Revert the service-role fallback (Follow-up 1)

`apps/web-platform/server/kb-route-helpers.ts`:

- [ ] In `resolveUserKbRoot`'s `catch (mintErr)` block (`:276-287`): replace the
      `tenant = createServiceClient()` fallback with the **pre-#4913 behavior** — return
      a 503 `{ error: "Workspace not ready" }` (the shape #4913's diff deleted; see PR
      #4913 diff `:246-271`). **PRESERVE the `reportSilentFallback(...op:"resolveUserKbRoot.tenant-mint")`
      call** so the #4920 alert keeps its signal. Re-`throw mintErr` for non-`RuntimeAuthError`.
- [ ] **If scope = whole family:** apply the symmetric revert to `authenticateAndResolveKbPath`
      (`:102-122`) — drop the `jwt_mint`/`rotation` service-role branch; on `RuntimeAuthError`,
      `reportSilentFallback` then return the pre-#4919 503/403. Keep `denied_jti` fail-closed
      (it already returned 403). Preserve the `op:"authenticateAndResolveKbPath.tenant-mint"` emit.
- [ ] Remove the now-unused `createServiceClient` from the `@/lib/supabase/server` import
      (`:4`) — **only if BOTH call-sites are gone** (`grep -c createServiceClient` must be 0
      after the edits, else keep the import; `cq-ref-removal-sweep-cleanup-closures`).
- [ ] Update the in-file comment blocks (`:79-101`, `:252-272`) to reflect the reverted
      tenant-only behavior + the misdiagnosis rationale.

`apps/web-platform/.service-role-allowlist`:

- [ ] **If `createServiceClient` is fully removed from `kb-route-helpers.ts`:** delete the
      `#4913` comment block + the `apps/web-platform/server/kb-route-helpers.ts` line
      (the file's last entry, added by #4913). This is CODEOWNERS-gated (`@deruelle`,
      `.github/CODEOWNERS:45`) — the revert PR will require owner review.
      **[Deepened correction] The gate is DIRECTIONAL, not atomic.**
      `service-role-allowlist-gate.sh` (read in full) FAILs only when a file *imports*
      `createServiceClient`/`getServiceClient` and is NOT in the allowlist (`:48-64`). It
      does NOT fail on a stale allowlist entry (a path listed but no longer importing) — that
      is tolerated. So there is **no hard requirement** that the import removal and the
      allowlist-line removal land in the same commit; CI stays green either way. The
      allowlist-line removal is a **cleanliness + boundary-hygiene** step (and CODEOWNERS-gated
      so the security owner sees the boundary shrink), NOT a gate-forced one. Do it in the same
      PR for a clean revert, but it is not load-bearing for CI. (Earlier plan draft overstated
      this as a same-commit atomicity requirement — corrected here.)
- [ ] **If scope = `resolveUserKbRoot` only** (import stays for `authenticateAndResolveKbPath`):
      leave the allowlist line, but update its comment to note only the file-route fallback
      remains. (This is the narrower, weaker outcome — flagged for CPO.)

`apps/web-platform/test/kb-route-helpers.test.ts`:

- [ ] Revert the #4913 fallback tests (the `mockServiceFrom` / `mockGetFreshTenantClient`
      mint-failure-fallback assertions, #4913 diff `:7-160`). Replace with the pre-#4913
      assertion: a `RuntimeAuthError` from `getFreshTenantClient` → 503, `reportSilentFallback`
      still fired. Keep `denied_jti`→403 for the file-route helper if that path is retained.
      (`cq-write-failing-tests-before`: write the reverted RED assertion first.)

### Phase 2 — Reconcile the #4920 alert + op-contract test (coupling from Phase 1)

`apps/web-platform/infra/sentry/issue-alerts.tf` — `kb_tenant_mint_silent_fallback` block (`:494-541`):

- [ ] The alert's `IS_IN` value (`:519`) currently lists 3 slugs. The emit sites still
      EXIST (we preserved them in Phase 1) — so **no slug needs removal** if the emits are
      kept. CONFIRM the 3 `reportSilentFallback(op:"…tenant-mint")` calls survive Phase 1;
      if the scope decision dropped an emit, drop the matching slug here + in the test. The
      alert still fires on a real (if rare) mint failure — that is correct and desirable
      (it is a notification layer, independent of whether a fallback recovers availability).

`apps/web-platform/test/sentry-kb-tenant-mint-alert-op-contract.test.ts`:

- [ ] If any `…tenant-mint` emit slug was removed in Phase 1, remove its `OP_SLUGS` row
      (`:53-70`) and let the `IS_IN`-join assertion (`:95`) recompute. If all 3 emits are
      preserved, this file is unchanged — assert that with a no-op run of the suite.

### Phase 3 — Wire the KB db-error alert (Follow-up 2)

`apps/web-platform/infra/sentry/issue-alerts.tf` — new APPLY-CREATED rule
`sentry_issue_alert.kb_db_error` (mirror `kb_tenant_mint_silent_fallback`'s shape):

- [ ] `name = "kb-db-error"`, `action_match = "any"`, `filter_match = "all"`,
      `frequency = <next free>` (Phase 0; likely 13).
- [ ] `conditions_v2 = [first_seen_event, reappeared_event, regression_event]` (mutually
      exclusive lifecycle states; "any" — re-pages on recurrence after the founder resolves).
- [ ] `filters_v2`: `feature == "kb-share"` AND
      `op IS_IN "create,list,revoke,preview,preview-invariant"` (the `kb-share.ts` db-error
      emit slugs; `create` is the 23502 path). **Verify the exact op-slug set** by grepping
      `kb-share.ts` at work time — do not hardcode from this plan
      (`paraphrase-without-verification`). NOTE: scope the IS_IN to the db-error ops only;
      `preview` self-failures are also db-class so included.
- [ ] `actions_v2 = notify_email{IssueOwners→ActiveMembers}` (repo convention; N=1 accepted
      risk, mirror the comment block at `kb_tenant_mint_silent_fallback:523-528`). These
      events carry only hashed userId + op + documentPath — no cross-tenant content.
- [ ] `lifecycle { ignore_changes = [environment] }`.
- [ ] Block-level comment documenting WHY op-scoped (feature `kb-share` spans several ops;
      a feature-only filter would not over-page since all kb-share db-error ops are
      operator-actionable — but confirm there is no high-volume benign op before choosing
      feature-only vs op-scoped). **Open design question for deepen-plan:** feature-only
      (simpler, future-proof) vs op-scoped (this plan's default). Resolve against the
      actual `kb-share` op vocabulary.

`.github/workflows/apply-sentry-infra.yml`:

- [ ] Add `-target=sentry_issue_alert.kb_db_error` to the `terraform plan` `-target` set
      (`:214-218`, after `kb_tenant_mint_silent_fallback`). Apply-created rules MUST be
      `-target`ed (the untargeted apply is scoped to monitors). No import step (no
      pre-existing Sentry rule).

`apps/web-platform/test/sentry-kb-db-error-alert-op-contract.test.ts` (NEW):

- [ ] Cross-artifact op/feature contract test, mirroring
      `sentry-kb-tenant-mint-alert-op-contract.test.ts` structure verbatim: read the
      `kb_db_error` resource block from `issue-alerts.tf`, read `kb-share.ts`, assert
      `feature == "kb-share"` appears on both sides and each `op` slug exists in BOTH the
      emit file AND the alert's IS_IN block (block-scoped, not whole-file). Pins both filter
      dimensions against rename drift (the #4920 learning
      `2026-06-04-cross-artifact-contract-test-scope-filter-assertions-to-the-resource-block.md`).

### Phase 4 — Close out follow-up tracking

- [ ] PR body: `Ref` (NOT `Closes`) the PIR follow-up items + the alert-to-file note (PIR
      `## Action Items` line 108 "supersedes the narrower #4918 tenant-mint-only framing").
      Mention #4914 should be confirmed-closed as misdiagnosis-based.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -c "createServiceClient" apps/web-platform/server/kb-route-helpers.ts` returns
      the expected count (0 if whole-family revert; 1 import + 1 call if `resolveUserKbRoot`-only).
- [ ] If whole-family: `grep -c "kb-route-helpers.ts" apps/web-platform/.service-role-allowlist`
      returns 0 (cleanliness — NOT gate-forced; see Phase 1 deepened correction).
- [ ] `bash apps/web-platform/scripts/service-role-allowlist-gate.sh` exits 0 (the directional
      gate: passes once `kb-route-helpers.ts` no longer imports `createServiceClient`,
      regardless of whether the stale allowlist line was also removed).
- [ ] `resolveUserKbRoot` returns 503 `{ error: "Workspace not ready" }` on `RuntimeAuthError`
      (asserted by reverted test in `kb-route-helpers.test.ts`), with `reportSilentFallback`
      still fired (assert the mock was called with `op:"resolveUserKbRoot.tenant-mint"`).
- [ ] The 3 `…tenant-mint` op slugs the #4920 alert filters on (`issue-alerts.tf:519`) each
      still resolve to a live emit site — verified by the existing op-contract test passing
      (or its `OP_SLUGS` updated 1:1 with any removed emit).
- [ ] New `sentry_issue_alert.kb_db_error` block exists with `feature=="kb-share"` filter and
      an `op IS_IN` value whose every comma-separated slug is grep-found in `kb-share.ts`.
- [ ] `apply-sentry-infra.yml` `-target` set contains `sentry_issue_alert.kb_db_error`.
- [ ] New op-contract test `sentry-kb-db-error-alert-op-contract.test.ts` passes and its
      block-scoping slice (`indexOf(RESOURCE_DECL)` → next `\nresource `) is non-empty.
- [ ] The new rule's `frequency` is unique across all `sentry_issue_alert` blocks in the file
      (`grep -oE 'frequency *= *[0-9]+' issue-alerts.tf | sort | uniq -d` returns empty).
- [ ] `terraform validate` (or `terraform fmt -check`) passes on `apps/web-platform/infra/sentry/`
      — run via the Phase 0 doppler `prd_terraform` triplet OR a no-creds `validate` (config-phase
      schema check needs no backend). The new rule must satisfy `actions_v2 ≥ 1` (jianyuan/sentry
      beta2 config-phase requirement).
- [ ] Full web-platform vitest shard green for the edited test files.

### Post-merge (operator → automated)

- [ ] `apply-sentry-infra.yml` fires on merge (path-filter matches `issue-alerts.tf`) and
      `terraform apply` creates `kb_db_error` in Sentry. **Automation:** the workflow IS the
      apply — no manual step. Verify via the Post-apply summary + a read-only
      `assert`-style probe if one is added (optional; the BYOK rules have one).
- [ ] Confirm #4914 is closed (it already is — CLOSED) and add a closing note that #4919's
      fallback was reverted as misdiagnosis-derived (if whole-family scope chosen).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — threshold gate).

### Engineering (CTO)

**Status:** reviewed (planner assessment; deepen-plan domain agents confirm)
**Assessment:** Pure code-deletion + IaC-follow-the-pattern. Two mechanical couplings
(allowlist/CODEOWNERS gate; #4920 op-contract test) are the only non-obvious risk; both
are enumerated as explicit phases. No new Terraform root, no new secret, no new runtime
process. The alert is apply-created via an existing, gated workflow.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no user-facing surface created or modified. The revert removes a server-side
fallback (no UI), and the alert is an operator notification. No `.tsx`/`page.tsx`/`layout.tsx`
in Files to Edit → mechanical UI-surface override does NOT fire.

CPO is invoked only for the single-user-incident **sign-off** (User-Brand Impact gate), not
for a UX review.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/issue-alerts.tf` — add 1 `sentry_issue_alert.kb_db_error`
  (apply-created, NOT import-only). Provider `jianyuan/sentry @ 0.15.0-beta2` (already pinned
  in the existing lockfile; no provider change).
- No new variables. Reuses the existing `var.sentry_org` + `data.sentry_project.web_platform`.

### Apply path
- (a) **apply-created via existing workflow.** `apply-sentry-infra.yml` already triggers on
  `issue-alerts.tf` changes (`:48`) and applies via the `-target` set. Add the new resource
  address to the `-target` list. The PR-merge IS the human authorization
  (`hr-menu-option-ack-not-prod-write-auth`); no operator SSH, no dashboard click. Blast radius:
  one new Sentry issue-alert; zero destroy (destroy-guard enforces). No downtime.

### Distinctness / drift safeguards
- `lifecycle { ignore_changes = [environment] }` (provider recomputes `environment` on read for
  project-wide rules — matches every sibling apply-created rule).
- Distinct `frequency` avoids Sentry POST-time exact-duplicate dedup.
- `dev != prd`: Sentry IaC targets the prd `jikigai-eu` org only (ADR-031); no dev Sentry project.

### Vendor-tier reality check
- Sentry issue-alerts are available on the current paid tier (the 9 existing `sentry_issue_alert`
  rules prove it). No free-tier gate needed (unlike `betteruptime_policy`).

### Precedent diff (deepen-plan Phase 4.4)

The new `kb_db_error` rule is NOT novel — it is a 1:1 clone of the apply-created,
op-scoped sibling `chat_message_save_failure` (`issue-alerts.tf:349-396`), verified
field-by-field at deepen time:

| Attribute | `chat_message_save_failure` (precedent) | `kb_db_error` (new) |
|---|---|---|
| `action_match` | `"any"` | `"any"` (same — lifecycle conditions are mutually exclusive) |
| `filter_match` | `"all"` | `"all"` |
| `conditions_v2` | first_seen + reappeared + regression | same |
| `frequency` | `10` | `13` (next free; taken set = 5,10,11,12,15,30,60,61,62) |
| feature filter | `cc-dispatcher` | `kb-share` |
| op filter | `IS_IN "tenant-mint.persistUserMessage,…"` | `IS_IN "create,list,revoke,preview,preview-invariant"` |
| `actions_v2` | notify_email IssueOwners→ActiveMembers | same (N=1 accepted risk comment) |
| `lifecycle.ignore_changes` | `[environment]` | `[environment]` |

No pattern is invented; the only deltas are the feature/op filter values and the
distinct frequency. The op set was verified by `grep -oE 'op: "[^"]*"' kb-share.ts`
→ exactly `create, list, preview, preview-invariant, revoke` (all `feature: "kb-share"`,
9 emit sites). Scheduled-work check: N/A — this plan adds no cron/Inngest job.

## Observability

```yaml
liveness_signal:
  what: "kb_db_error Sentry issue-alert fires on first kb-share db-error event"
  cadence: "event-driven (first_seen + reappeared + regression)"
  alert_target: "Sentry email → IssueOwners→ActiveMembers (solo founder)"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf (kb_db_error block)"
error_reporting:
  destination: "Sentry (existing reportSilentFallback → captureException in kb-share.ts)"
  fail_loud: "yes — db-error path already throws/500s + captures; this adds the notification"
failure_modes:
  - mode: "Alert filter mis-keys (wrong feature/op slug)"
    detection: "sentry-kb-db-error-alert-op-contract.test.ts (CI, cross-artifact)"
    alert_route: "CI red on the contract test"
  - mode: "Revert silently drops a tenant-mint emit, darkening the #4920 alert"
    detection: "existing sentry-kb-tenant-mint-alert-op-contract.test.ts (CI)"
    alert_route: "CI red"
  - mode: "New rule not -targeted → never applied"
    detection: "apply-sentry-infra.yml Post-apply summary + (optional) assert probe"
    alert_route: "GitHub Actions failure / absent rule"
logs:
  where: "pino (createChildLogger) + Sentry breadcrumbs, already present"
  retention: "Sentry default project retention"
discoverability_test:
  command: "doppler run -p soleur -c prd_terraform -- terraform -chdir=apps/web-platform/infra/sentry plan -target=sentry_issue_alert.kb_db_error  # expect: 0 changes after apply"
  expected_output: "No changes. Your infrastructure matches the configuration."
```

## Test Scenarios

- `resolveUserKbRoot` + `RuntimeAuthError("jwt_mint")` → returns 503, `reportSilentFallback`
  called with `op:"resolveUserKbRoot.tenant-mint"`, NO `createServiceClient` invoked.
- (whole-family) `authenticateAndResolveKbPath` + `RuntimeAuthError("rotation")` → 503,
  emit fired, no service-role client.
- (whole-family) `authenticateAndResolveKbPath` + `RuntimeAuthError("denied_jti")` → 403,
  emit fired (fail-closed preserved).
- op-contract test (new): each `kb-db-error` IS_IN slug ∈ `kb-share.ts` AND ∈ the resource block.
- op-contract test (existing #4920): unchanged-green (or 1:1 updated if an emit was dropped).

## Open Questions (for deepen-plan + CPO)

1. **Scope:** revert `resolveUserKbRoot` only (user's literal ask) or the whole mint-fallback
   family incl. `authenticateAndResolveKbPath` (#4919)? PIR line 109 favors whole-family
   ("close #4914 as based-on-misdiagnosis"). Whole-family is the only scope that lets us drop
   the import + allowlist line cleanly. **Plan default: whole-family.** Needs CPO confirm.
2. **Alert filter granularity:** op-scoped `IS_IN (create,list,revoke,preview,preview-invariant)`
   (this plan's default, mirrors #4920) vs `feature=="kb-share"`-only (simpler, future-proof).
   Resolve against the full `kb-share` op vocabulary — is any op high-volume-benign?
3. **`kb-upload` coverage:** the upload route's db-error (kb_files insert) emit slug — does it
   share `feature=="kb-share"` or a different feature? If different and it is also a 23502-class
   insert, the alert should cover it too (the incident swept push_subscriptions + conversations
   + kb_files, not just kb_share_links). Grep the upload + push-subscription + repo-setup emit
   features at work time.

## Open Code-Review Overlap

None — no open `code-review`-labeled issues touch `kb-route-helpers.ts`, `kb-share.ts`,
`issue-alerts.tf`, `apply-sentry-infra.yml`, or the op-contract tests at plan time (verify
with the Phase-1.7.5 `gh issue list --label code-review` query at deepen-plan).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails
  `deepen-plan` Phase 4.6 — this plan's section is populated (threshold: single-user incident).
- **Allowlist + import atomicity:** `service-role-allowlist-gate.sh` FAILS if a `createServiceClient`
  import and its `.service-role-allowlist` line do not move together in one commit. The import
  REMOVAL and the allowlist line REMOVAL must be in the same commit (inverse of the gate's
  add-direction, same enforcement).
- **Do NOT remove the `reportSilentFallback` emit when reverting the fallback.** The fallback
  (the `createServiceClient` line) is dead code; the EMIT (`reportSilentFallback`) is the
  #4920 alert's signal and must survive. A naive `git revert -m` of #4913 would delete the emit
  too (it was added in the same diff) — apply the revert by hand, preserving the emit + returning
  the pre-#4913 503.
- **Frequency uniqueness:** the new `kb_db_error` rule's `frequency` must not collide with the
  taken set (5,10,11,12,15,30,60,61,62) or Sentry POST-time dedup folds it into a sibling rule.
- **op-contract block-scoping:** the new test MUST slice the `kb_db_error` resource block (not
  whole-file `toContain`) so a slug deleted from THIS rule while lingering in a comment/sibling
  rule still fails CI (the #4920 learning).

## Plan Review

After writing, `/plan_review` runs DHH + Kieran + code-simplicity. Given the
`single-user incident` threshold, deepen-plan (data-integrity-guardian +
security-sentinel + architecture-strategist) is also warranted to validate the
tenant-boundary revert + the alert-darkening coupling — plan-review is structurally
blind to those substance-level findings.
