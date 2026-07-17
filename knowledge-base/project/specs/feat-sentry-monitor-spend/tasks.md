---
feature: feat-sentry-monitor-spend
issue: 6589
pr: 6582
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-17-fix-sentry-iac-delete-path-plan.md
---

# Tasks — Sentry IaC delete path (#6589)

Derived from the **post-review (v2)** plan. Read the plan first — several v1 assumptions were
falsified at review and the corrections are load-bearing.

**Test commands (verified):** `cd apps/web-platform && npm run test:ci` (vitest) ·
`cd apps/web-platform && npm run typecheck` (tsc). **Never** `npm run -w …` — the root
`package.json` has no `workspaces` field. `tests/scripts/*.sh` are **not** vitest-collected; run
them with `bash <path>`.

**Terraform (plan-time gotcha, do not rediscover):** the provider reads a **raw** `SENTRY_AUTH_TOKEN`
env var. `doppler run --name-transformer tf-var` mangles it to `TF_VAR_sentry_auth_token` and the
provider then dies with `failed to perform health check`. Export raw:
`SENTRY_AUTH_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (R2 backend), plus
`TF_VAR_sentry_org` / `TF_VAR_sentry_project` / `TF_VAR_sentry_region`.

---

## Phase 1 — Raise the PAYG cap (ships alone; no code; decoupled from this PR)

- [ ] 1.1 Confirm with the operator before any billing write (`hr-menu-option-ack-not-prod-write-auth` — the brainstorm menu selection is **not** write authorization).
- [ ] 1.2 Attempt (a): API write of `onDemandMaxSpend` 5000 → 7500 with `SENTRY_IAC_AUTH_TOKEN`. Expect 403 — `customers/` GET returns 200 but `ondemand-budgets/` GET returns **403**.
- [ ] 1.3 On 403, attempt (b): Playwright the Sentry billing settings page. Record `playwright-attempt: navigated <URL>; reached <named human gate>`.
- [ ] 1.4 Only if (b) reaches a real human gate (CAPTCHA/OTP/TOTP/passkey/push-MFA/payment-card): file an `action-required` issue and **do not block the PR** (`wg-block-pr-ready-on-undeferred-operator-steps`).
- [ ] 1.5 **AC1 (post-merge):** `GET /api/0/customers/jikigai-eu/` → `onDemandMaxSpend == 7500`.

## Phase 2 — Correct the expense ledger

- [ ] 2.1 `knowledge-base/operations/expenses.md:37` — `Amount` `40.00` → `71.22`.
- [ ] 2.2 Replace the stale note ("~$11 expected PAYG … verify actual draw on the 2026-06-17 invoice") with `$29 base + $42.22 PAYG (49 × $0.78 + 4 × $1.00, monitor-count-driven, fixed) = $71.22`.
- [ ] 2.3 **AC2:** Amount reads `71.22`; the arithmetic is present; the stale TODO string is gone.
- [ ] 2.4 Must land **before** PR-ready (`wg-record-recurring-vendor-expense-before-ready`).

## Phase 3 + Phase 4 — Contract change + its 11 consumers (**ONE commit**)

> Producer and consumers of a contract line must land together. Do not split.

### Phase 3 — the contract

- [ ] 3.1 (RED) Add the AC11 regression test: assert no `-target=` in any `terraform plan`/`apply` invocation in `apply-sentry-infra.yml`; assert the scope guard sources types from `.tf ∪ state`; assert a synthesized-fixture plan JSON with a removed block yields `resource_deletes: 1` through the jq filter.
- [ ] 3.2 (GREEN) Delete the 71 `-target=` lines (`apply-sentry-infra.yml:196-261`).
- [ ] 3.3 Keep `[ack-destroy]` (`:297-306`) and `[skip-sentry-apply]` (`:84-91`) **byte-for-byte** (TR4). Verify with `bash tests/scripts/test-destroy-guard-regex-parity.sh` (**AC4**).
- [ ] 3.4 Delete the stale `kb_tenant_mint_silent_fallback` comment (`:186-192`).
- [ ] 3.5 Widen `paths:` (`:44-52`) → `apps/web-platform/infra/sentry/**`. **Load-bearing:** 4.2 removes `missingTarget`, the only gate for declared-but-never-applied; the path filter must then cover every `.tf`.
- [ ] 3.6 **Add the `pull_request` plan job** on the same paths, running the read-only full-root plan. Fail with a message naming the destroyed addresses **and** the literal `[ack-destroy]`. **This is the change that removes the footgun** — without it a bad delete goes red only *after* merge and the orphan survives (byte-identical to #6074).
- [ ] 3.7 **AC14:** the job fails on a synthesized destroying plan and passes otherwise.
- [ ] 3.8 Add `resource_creates` to `tests/scripts/lib/destroy-guard-filter-sentry.jq` (~3 lines). Gate: fail when a created address has **no matching added `resource` block** in the triggering diff. **Not** a blanket `[ack-create]` — that fires on the normal add-a-monitor flow and trains ack-blindness.

### Phase 4 — the 11 consumers

- [ ] 4.1 `tests/scripts/test-destroy-guard-sentry-scope-guard.sh:35-48` — extractor source becomes **`types(*.tf) ∪ types(terraform state list)`**. A `.tf`-only source is **vacuous in the direction of the bug** (a state-only type is invisible). Preserve empty→FAIL.
- [ ] 4.2 Same file — parameterize the input (`SENTRY_TF_DIR="${SENTRY_TF_DIR:-$REPO_ROOT/apps/web-platform/infra/sentry}"`); `WORKFLOW` is hardcoded at `:32-33` with no injection point, so **AC6 is otherwise untestable**.
- [ ] 4.3 **AC6:** guard passes with the new extractor **and FAILs** when `SENTRY_TF_DIR` points at an empty dir.
- [ ] 4.4 `sentry-monitor-iac-parity.test.ts:134-206` — delete `applyTargetResourceIds()` + `missingTarget`; **keep `missingMonitor`**.
- [ ] 4.5 `function-registry-count.test.ts:27,35,44,55` — count from `.tf`, not the `-target=` regex.
- [ ] 4.6 Convert the six op-contract tests from `-target=` membership to "declared in `issue-alerts.tf`":
  - [ ] `sentry-inbox-action-required-alert-op-contract.test.ts:45,49`
  - [ ] `sentry-kb-sync-silent-failure-alert-op-contract.test.ts:107-113`
  - [ ] `sentry-kb-sync-protected-fallback-alert-op-contract.test.ts:90-96`
  - [ ] `sentry-zot-mirror-fallback-alert-op-contract.test.ts:321-325`
  - [ ] `sentry-web-terminal-boot-fatal-op-contract.test.ts:81-85`
  - [ ] `sentry-outbound-email-alert-op-contract.test.ts:59-63`
- [ ] 4.7 `tests/scripts/test-destroy-guard-counter-sentry.sh:17-34` — **delete** the stale `-target=` recipe (do not refresh it).
- [ ] 4.8 `destroy-guard-filter-sentry.jq:8,31-36` — update CURRENT SCOPE; note the `sentry_issue_alert` coverage widening 2 → 22.
- [ ] 4.9 `.github/workflows/infra-validation.yml:37-39` — stale allowlist prose.
- [ ] 4.10 `apps/web-platform/infra/sentry/uptime-monitors.tf:21-27` — stale allowlist prose.
- [ ] 4.11 **AC3:** `grep -cE '^\s*-target=' .github/workflows/apply-sentry-infra.yml` → `0`.
- [ ] 4.12 Full suite green: `cd apps/web-platform && npm run test:ci` + `npm run typecheck`.

### Phase 3/4 exit gate

- [ ] 4.13 **AC5:** re-run the read-only full-root plan. The **delete SET** must equal exactly `{sentry_cron_monitor.scheduled_ghcr_token_minter, sentry_issue_alert.kb_tenant_mint_silent_fallback}` (identity, not a count — a *different* pair also satisfies `count==2`). **AND** `resource_creates == 0`. **AND** all 22 `sentry_issue_alert` addresses are `no-op`.

## Phase 5 — Destroy the dead resources

- [ ] 5.1 (5a) Merge with `[ack-destroy]` on the merge commit → the push-to-main apply destroys `scheduled_ghcr_token_minter` + `kb_tenant_mint_silent_fallback`.
- [ ] 5.2 **AC7:** confirm `scheduled_github_app_drift_guard` is still declared **and active** (CLO hard constraint — `article-30-register.md:303` claims drift "is detected hourly").
- [ ] 5.3 (5c) Probe the token's `monitor:admin` DELETE scope. **Do not assume it** — the same token 403'd on `ondemand-budgets/`.
- [ ] 5.4 (5c) `curl -X DELETE` uptime monitor id `1422253` (Sentry-only; never in Terraform state, so Terraform cannot destroy it). On 403 → Playwright → escalate.
- [ ] 5.5 **AC10 (post-merge):** `sentry-monitors-audit.sh` reports **0** Class D orphans.

## Phase 6 — Class D orphan detection

- [ ] 6.1 (RED) Test: a live monitor with no `.tf` block is reported as Class D **and** exits non-zero.
- [ ] 6.2 (GREEN) `apps/web-platform/scripts/sentry-monitors-audit.sh` — add Class D after `monitor_slugs` (~`:290`); report at `:433-461`.
- [ ] 6.3 **Fail-closed (load-bearing):** every existing orphan branch only `printf`s; all `exit 1`s are token gates / API failures. Class D **must exit non-zero** or it is a detector wired to nothing.
- [ ] 6.4 **TR3:** read liveness from `environments[].lastCheckIn` — **NOT** the list endpoint's `lastCheckIn` (that field does not exist there and yields a false "never checked in" for every monitor).
- [ ] 6.5 Preserve the 4-gate token check (`:93-166`) + DSN residency guard (`:168-220`).
- [ ] 6.6 Emit `SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=… created=… last_checkin=… cost_usd=…` to stdout.

## Phase 7 — Records

- [ ] 7.1 **Append** `Amendment (2026-07-17, #6589)` to `ADR-031-sentry-as-iac.md`. Do **not** rewrite `## Decision` — the file records changes as dated appends.
- [ ] 7.2 The amendment MUST name and retire **clause (b)** of the 2026-07-13 #6374 amendment (`:276-289`) and explain **why it is safe**: clause (b) existed because `-target=` scoping made *declared ≠ applied*; under full-root **declared ≡ applied by construction**, so the invariant is preserved and only its enforcement mechanism becomes unnecessary. Record the `paths:` widening (3.5) as what keeps that true. Without this, a future reader concludes #6589 broke a P1-derived invariant.
- [ ] 7.3 Record the rejected alternatives in the amendment (hand-maintained allowlist; derive-from-state ∪ config — *identity-equal to no `-target`*; block-removal lint).
- [ ] 7.4 `knowledge-base/engineering/architecture/diagrams/model.c4:271` — update the `paths:` enumeration (3.5 widened it).
- [ ] 7.5 File the follow-ups: OQ4 (5b producers dead vs unwired), growth gate (nothing caps new monitors at `reserved = 1`), scope-guard/counter-test consolidation.
</content>
