<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix: Un-wedge the Sentry Terraform root — 410 on sentry_issue_alert reads (provider bump; sentry_alert migration as fallback)"
issue: 6636
type: fix
classification: infrastructure-iac
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-17
branch: feat-one-shot-6636-sentry-alert-migration
spec: knowledge-base/project/specs/feat-one-shot-6636-sentry-alert-migration/tasks.md
---

# fix: Sentry retired the legacy issue-alert read API (410) — un-wedge the sentry Terraform root (#6636)

## ⚠️ Decision Headline (read first)

The issue asks to **migrate all 23 `sentry_issue_alert` resources to `sentry_alert`** (with the provider bump as an "alternative to evaluate"). The evidence inverts that ordering:

1. **The provider bump is the low-blast-radius fix and should be attempted FIRST.** Sentry's 410 is on the legacy issue-alert **read** endpoint; the pinned provider (`jianyuan/sentry 0.15.0-beta2`, 2026-05-06) predates the release that reworks `sentry_issue_alert` reads. Bumping to the latest stable (candidate `0.15.4`) is a **provider-version-only change** — no state surgery, no resource rewrite, zero risk of dropping a live paging rule. It resolves ADR-031's own `re-evaluate on first stable v0.15.0` note.
2. **The `sentry_alert` migration is NOT recommended and remains blocked for the same reason #4610 found in May.** External research (framework-docs-researcher, 2026-07-17) re-confirms that even in the latest stable, `sentry_alert` **requires `monitor_ids`** and has **no `project` attribute** — it is a monitor-bound, org-level resource. The 23 alerts are project-wide issue/frequency rules bound to no monitor. Faithful migration would require binding every rule to a synthetic/default project monitor (a semantic change) AND 23× cross-type state surgery under the now-live full-root destroy-guarded apply — precisely the "drop live paging" brand-survival risk the issue warns against.

**BUT the load-bearing fact — "a provider bump clears the 410" — is a claim to MEASURE, not to trust.** The 410 is a server-side retirement; a provider version can only clear it by pointing the read at a still-live endpoint, and the research agent hedged on whether it truly does. Therefore **Phase 0 is a hard measurement gate**: bump, `terraform plan` against live Sentry state, and confirm the 410 is gone AND the full-root plan is a clean no-op. If — and only if — the bump does NOT clear the 410, the plan falls to **Option B (migration)**, specified in full below.

This is a **User-Challenge** to the issue's stated direction (recorded in `knowledge-base/project/specs/feat-one-shot-6636-sentry-alert-migration/decision-challenges.md` for `ship` to surface as an `action-required` issue). CPO sign-off is required at plan time (single-user-incident threshold — these are the auth + BYOK Art. 33 paging rules).

## Enhancement Summary (deepen-plan)

**Deepened on:** 2026-07-17
**Method:** Inline (headless one-shot subagent). Provider facts from framework-docs-researcher (registry + release-notes research); machinery facts from direct reads of `apply-sentry-infra.yml`, ADR-031, `destroy-guard-filter-sentry.jq`, README, and a full schema-variety sweep of the 23 resources.

**Mechanical gates (all PASS, none halted):**
- 4.6 User-Brand Impact — present, threshold `single-user incident`.
- 4.7 Observability — 5 fields present, `discoverability_test.command` is SSH-free.
- 4.8 PAT-shaped variable — clean (no `var.*_token`, no literal PAT; `SENTRY_AUTH_TOKEN`/`SENTRY_IAC_AUTH_TOKEN` are provider env vars, not PAT-shaped TF vars).
- 4.9 UI-wireframe — no UI surface (Files-to-Edit are `.tf`/`.hcl`/`.md`/`.jq`/`.sh` only; a raw grep false-matches the negation prose in Domain Review — there is no `.tsx`/`page.tsx`/`layout.tsx` in scope, so no `.pen` is required).
- 4.55 Downtime & Cutover — no trigger: a provider-version bump takes no serving surface offline, runs no reboot/replace/DB-lock, and the live Sentry alerts keep firing server-side throughout (only Terraform *management* is affected). Option B's `state rm`+`import` likewise causes no serving downtime.
- 4.5 Network-Outage — no trigger: the sentry root is a SaaS provider with no `provisioner`/`connection ssh` block; "410" is not an SSH/L3 symptom.

### Key improvements over the round-1 plan
1. **Load-bearing framing inverted with a measurement gate:** the recommended fix is the provider bump (Option A), not the 23-resource migration — but "a bump clears the 410" is proven at Phase 0 by a real `terraform plan`, never on the research's version claim.
2. **Lockfile regeneration made explicit** as the #1 way Option A silently breaks CI (`init -lockfile=readonly` refuses uncommitted checksums).
3. **`state mv` correctly ruled impossible**; Option B uses refresh-free `state rm`+`import` (the only primitive that survives a live 410) with the destroy-guard extension sequenced first.

### New considerations discovered during deepen
- The break is CI-fatal *only because of* #6589's same-day full-root switch — this dates the incident precisely and explains why the 23 alerts were latent-but-safe before.
- `removed {}` blocks are likely DOA (plan/apply refresh hits the 410); `state rm` is the safe primitive — flagged as a Phase-0 verification, not an assumption.

## Research Insights & Precedent-Diff (Phase 4.4)

### Precedent-Diff — pattern-bound behaviors (all have in-repo precedent; none novel)
- **`terraform import` / `state rm` for this root (Option B):** precedent is `apps/web-platform/infra/sentry/README.md` §First-time-import + §Import rollback — the exact `terraform import "sentry_issue_alert.<res>" "<org>/<project>/<id>"` form and the `state rm` partial-failure recovery loop. Option B reuses this shape for `sentry_alert` (import-id format re-verified at B.0/B.3).
- **Destroy-guard nested-clause (Option B):** precedent is `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (the `github_repository_ruleset`/`cloudflare_ruleset` array-of-blocks pattern) — the sentry filter's header explicitly says "mirror the pattern in destroy-guard-filter-web-platform.jq; do NOT introduce walk()". A `sentry_alert` clause follows it byte-for-byte in shape.
- **`init -lockfile=readonly` (both options):** precedent is the two `Terraform init` steps in `apply-sentry-infra.yml` (plan_pr + apply jobs) — both use `-lockfile=readonly`, so the committed lock is load-bearing.
- **No novel pattern is introduced by Option A** (a version pin + lockfile regen is the most mechanical IaC change class).

### Research Insight — lockfile regeneration is the sharpest edge in Option A
The apply workflow (both the PR gate and the main apply) runs `terraform init -input=false -lockfile=readonly`, which **refuses to download a provider whose checksum is absent** from `.terraform.lock.hcl` (workflow comment L505-509: "defends against a malicious republish of the pinned beta provider version"). The current lock carries **3 `h1:` hashes + 12 `zh:` hashes** for `0.15.0-beta2`. Regenerate with `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64` (CI is `ubuntu-24.04` → `linux_amd64` is mandatory; the two darwin platforms mirror the existing 3-hash set for local dev). Commit the regenerated lock in the SAME PR as the `versions.tf` bump — a `versions.tf` change without a matching lock fails CI init before any plan runs.

### Research Insight — the 410 is server-side, so "measure, don't trust the version"
Sentry's 410 is a *server-side retirement* of `GET /projects/{org}/{project}/rules/{id}/`. A provider version can clear it ONLY by pointing `sentry_issue_alert`'s read at a still-live endpoint (research names a post-beta2 rework, hedged). This is unverifiable from registry docs alone against a live-retired endpoint — hence Phase 0.4 observes a real `terraform plan` returning no 410 before Option A is adopted. If the latest stable still 410s, the honest outcome is Option B, not a higher version pin.

## Overview

`apps/web-platform/infra/sentry/` manages the platform's larger paging plane as IaC (ADR-031): **23 `sentry_issue_alert`** (`issue-alerts.tf`), **49 `sentry_cron_monitor`** (`cron-monitors.tf`), **4 `sentry_uptime_monitor`** (`uptime-monitors.tf`). The provider is pinned `jianyuan/sentry 0.15.0-beta2`.

As of ~2026-07-17 18:00–20:00Z Sentry retired the legacy issue-alert **read** API (`GET /projects/{org}/{project}/rules/{id}/`), which now returns `410 {"message":"This API no longer exists."}`. The beta2 provider's `sentry_issue_alert` resource reads via that endpoint, so **every one of the 23 reads fails and `terraform plan` aborts for the whole root**.

This break became CI-fatal because of **#6589 (2026-07-17, same day)**: the apply workflow was changed to plan the **FULL ROOT** (no `-target=`), so `terraform plan` now refreshes every resource — including all 23 `sentry_issue_alert` — on both the PR-time `sentry-destroy-required` gate and the push-to-main apply. Before #6589 the issue-alerts were outside the `-target=` allow-list and never planned; the 410 was latent. Now:

- The **required** `sentry-destroy-required` PR gate fails closed for every PR touching the sentry surface (verified on PR #6622, which merely adds 2 alerts).
- `apply-sentry-infra.yml` on `main` fails on its next run (last green 2026-07-17T17:55Z, before the break).
- Live prod alerts keep firing (they exist server-side); only Terraform *management* is broken.

The fix must restore `terraform plan` to a clean full-root no-op so both the PR gate and the main apply go green — without destroying any live alert.

## Research Reconciliation — Issue framing vs. codebase / provider reality

| #6636 claim / framing | Reality (measured / researched) | Plan response |
|---|---|---|
| "Full-root migration of all 23 alert resources to `sentry_alert` … careful `terraform state mv` / import" | `sentry_alert` in the **latest** provider still **requires `monitor_ids`** and has **no `project` attribute** (org-level, monitor-bound) — re-confirmed 2026-07-17, same blocker as #4610 (ADR-031 amendment 2026-05-29). Cross-type `state mv` is impossible (disjoint schemas: `sentry_issue_alert` has `project`+`conditions_v2`+`filters_v2`+`actions_v2`+`frequency`; `sentry_alert` has `monitor_ids`+`trigger_conditions`+`action_filters`+`frequency_minutes`). | Migration is Option B (fallback), NOT the recommended path. It is only reached if the bump fails to clear the 410. It requires monitor-binding (semantic change) + 23× `state rm`+`import`, not `state mv`. |
| "Alternative to evaluate: bump `jianyuan/sentry` to a version whose `sentry_issue_alert` uses the current API" | Latest stable is a candidate `0.15.4` (2026-07-03). Research reports the `sentry_issue_alert` read path was reworked after beta2 (candidate fix `0.15.3`). This is a **provider-only** change: no state mutation, no resource rewrite. | **Recommended (Option A).** Attempt first; gate adoption on a Phase 0 measurement that the 410 is actually gone and the plan is a clean no-op. |
| "23 alert resources" | Confirmed: `grep -c '^resource "sentry_issue_alert"' issue-alerts.tf` → 23 (4 import-only auth_* + BYOK/chat/others TF-owned; README.md still says "6 issue alerts" — stale, grew to 23). | Both paths operate on all 23. README count is corrected as a side-effect. |
| "re-check `sentry_cron_monitor` / `sentry_uptime_monitor` for the same retirement" | The 410 is specific to the legacy issue-alert **rules** endpoint. Crons + Uptime use separate current API surfaces. But a provider bump could introduce schema drift on any type. | Phase 0's full-root `terraform plan` measurement covers all three types: any non-no-op on cron/uptime is caught before merge. |
| ADR-031: "Defer migration … until provider GA"; "Pinned to the exact beta version; re-evaluate on first stable v0.15.0" | The stable line (0.15.x) now exists. The defer's *migration* rationale (monitor_ids blocker) still holds; the *pin* rationale (beta) is resolved by the bump. | ADR-031 is amended: bump beta2 → stable; migration deferral RE-AFFIRMED (blocker persists). |

## User-Brand Impact

**If this lands broken, the user experiences:** the platform's larger paging plane stays un-manageable — new/changed alerts and monitors cannot be applied, and every unrelated PR touching the sentry surface stays blocked by the red required gate. Under Option B done wrong, one of the 23 rules (the auth-abuse detectors, `byok-art-33-breach` GDPR Art. 33 breach detector, `chat-message-save-failure`, `web_terminal_boot_fatal`, `workspaces_luks_drift`, etc.) could be dropped from Sentry during state surgery → a real incident goes **unpaged**.

**If this leaks, the user's data / workflow is exposed via:** N/A for the fix itself (no PII in provider version or alert config). The exposure vector is the **absence** of alerting, not a leak — a dropped `byok-art-33-breach` rule means a cross-tenant BYOK breach never starts the Art. 33 72h clock.

**Brand-survival threshold:** single-user incident. A single founder whose auth surface is attacked, or whose data is cross-tenant-leaked via BYOK, while a paging rule is silently dropped is a brand-survival event. The recommended path (Option A, provider bump) makes **no state change and drops no paging**, which is the primary reason it is recommended over Option B.

> CPO sign-off required at plan time before `/work` begins (production auth + Art. 33 paging rules). `user-impact-reviewer` is invoked at review-time. If Option B is reached, its state-surgery blast radius requires re-confirmation of the sign-off.

## Alternative Approaches Considered

| Option | What | State surgery? | Drops live paging? | Verdict |
|---|---|---|---|---|
| **A — Provider bump (recommended)** | Bump `jianyuan/sentry` beta2 → latest stable in `versions.tf` + regenerate `.terraform.lock.hcl`; keep all 23 `sentry_issue_alert` as-is. `terraform plan` reads via the fixed provider → clean full-root no-op → both gates green. | **None** | No | **Ship if Phase 0 confirms the 410 clears + plan is no-op.** Lowest blast radius; resolves ADR-031's beta pin. |
| **B — Migrate to `sentry_alert` (fallback)** | Rewrite all 23 to `sentry_alert` bound to a project default/issue-stream monitor (data source); `terraform state rm` the 23 `sentry_issue_alert` (refresh-free, safe under 410) then `import` the 23 `sentry_alert`. | **23× rm + 23× import** | Risk if mis-sequenced | **Only if A fails to clear the 410.** Requires monitor-binding (semantic change) + verified data-source support; high blast radius under single-user-incident threshold. |
| **C — Pin + revert to REST script** | Roll the sentry root back to the pre-IaC `configure-sentry-alerts.sh` upserter (ADR-031 escape hatch), mark ADR-031 rejected. | State teardown | No (script keeps rules) | **Last resort** if BOTH A and B are unworkable (e.g., no provider version reads without 410 AND `sentry_alert` cannot bind). Loses drift detection + the #6589 destroy safety. |

**Deferral tracking:** the `sentry_alert` migration (Option B) stays deferred by ADR-031 whenever Option A ships. The deferral's re-evaluation criterion is updated: "re-attempt when `sentry_alert` gains a `project` attribute OR drops the `monitor_ids` requirement for project-wide issue alerts." No new deferral issue is filed (ADR-031 already tracks it); the User-Challenge is recorded in `decision-challenges.md`.

## Implementation Phases

### Phase 0 — Measurement gate (decides A vs B; no edit until this passes)

This is the load-bearing phase. Nothing downstream is trusted until measured against **live Sentry state**. Requires the R2 backend creds (Doppler `prd_terraform` `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) + the Sentry IaC token. Local invocation uses the canonical form in `apps/web-platform/infra/sentry/README.md` §Local invocation.

- [ ] **0.1 Reproduce the break** on the pinned provider: `cd apps/web-platform/infra/sentry && terraform init -input=false && terraform plan` → confirm the `410 "This API no longer exists"` on `sentry_issue_alert` reads. Capture one verbatim error line into the spec's evidence file.
- [ ] **0.2 Enumerate available versions** (bounded, read-only): `curl -s https://registry.terraform.io/v1/providers/jianyuan/sentry/versions | jq -r '.versions[].version' | tail -20`. Pick the **lowest stable version ≥ current that plausibly reworks the issue-alert read** (research names `0.15.3`; latest is `0.15.4`). Do NOT trust the research's exact version/date/PR — the registry list is authoritative here.
- [ ] **0.3 Bump + upgrade** in a scratch working copy: set `version = "<chosen>"` in `versions.tf`, run `terraform init -upgrade`, regenerate `.terraform.lock.hcl` for the CI platform set (see Sharp Edge: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64` to match the 3 existing `h1:` hashes; CI runs `ubuntu-24.04` = `linux_amd64`, which is mandatory).
- [ ] **0.4 MEASURE (the decision datum):** `terraform validate` (expect exit 0, deprecation warnings allowed) then `terraform plan -no-color`. Record **both**:
  - (a) **410 cleared?** No `sentry_issue_alert` read returns 410.
  - (b) **Plan shape?** Full-root plan is a clean **no-op** (0 to add, 0 to change, 0 to destroy) across all three resource types. Any drift on `sentry_issue_alert` (v2-attribute shape change between beta2 and stable), `sentry_cron_monitor`, or `sentry_uptime_monitor` is surfaced HERE.
- [ ] **0.5 Decision fork:**
  - **410 cleared AND plan no-op (or only `ignore_changes`-masked drift)** → **Option A**. Proceed to Phase A.
  - **410 cleared BUT non-trivial drift** (provider changed a `_v2` attribute the 23 resources set, or cron/uptime schema shifted) → **Option A + targeted attribute/`lifecycle` reconciliation** so the plan returns to no-op. Enumerate each drifting resource; do NOT accept a plan that would `apply` a real change without the `[ack-destroy]`/create-gate reasoning.
  - **410 NOT cleared by any available stable version** → **Option B** (Phase B). Record the measurement proving no version clears the read.
- [ ] **0.6 Guard/tooling probe (both options):** `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` (baseline `[ok]`); confirm `grep -c 'sentry_issue_alert\|sentry_alert' apps/web-platform/scripts/sentry-monitors-audit.{sh,test.sh}` → 0 (audit tooling is REST-based, resource-type-agnostic; no edit for a version bump).

### Phase A — Provider bump (recommended path)

- [ ] **A.1** `versions.tf`: `version = "0.15.0-beta2"` → `version = "<chosen stable>"`; update the header comment ("Pinned to v0.15.0-beta2 — beta. Re-evaluate on first stable…") to record the resolved stable pin + the #6636 410 rationale + that `sentry_alert` migration stays deferred (monitor_ids blocker persists).
- [ ] **A.2** `.terraform.lock.hcl`: commit the regenerated lock (new `version`, `constraints`, and the full `h1:`/`zh:` hash set for ALL platforms in the current lock — the apply workflow uses `terraform init -lockfile=readonly`, which REFUSES a provider whose checksum is absent; a lock missing `linux_amd64` breaks CI init).
- [ ] **A.3** If Phase 0.5 found `ignore_changes`-maskable drift on the 23 alerts, adjust `lifecycle.ignore_changes` per resource so the plan is no-op; if the provider renamed/reshaped a `_v2` attribute, update the affected resource bodies to the new shape (grep all 23 for the attribute; treat as a `hr-type-widening-cross-consumer-grep`-class sweep).
- [ ] **A.4** `README.md`: correct the stale "6 issue alerts" → 23 (4 import-only auth_* + 19 TF-owned) while here; update the §Local invocation `de.sentry.io` note only if Phase 0 shows it is wrong (per ADR-031 the API host is the org-subdomain, not `de.sentry.io` — README §First-time-import prose predates the 2026-05-17 host correction; correct if touched).
- [ ] **A.5** Amend ADR-031 (see §Architecture Decision).

### Phase B — Migrate to `sentry_alert` (fallback; only if Phase 0 proves no version clears the 410)

Reached ONLY when Phase 0 measurement shows no available stable provider reads `sentry_issue_alert` without a 410. This path is high-blast-radius; re-obtain CPO sign-off before executing.

- [ ] **B.0 Verify the target is expressible** (do NOT skip — this is #4610's blocker): dump `terraform providers schema -json` for the chosen version and confirm whether `sentry_alert` still requires `monitor_ids` / lacks `project`, AND whether the data sources `sentry_project_error_monitor` / `sentry_project_issue_stream_monitor` (research-named; UNVERIFIED) exist and yield a monitor id that lets a project-wide issue/frequency rule fire faithfully. If `sentry_alert` cannot represent a pure-frequency rule (e.g. `zot_mirror_fallback_rate` — `event_frequency` only, no lifecycle trigger) without changing its fired-event semantics, Option B is NOT faithful → escalate to Option C.
- [ ] **B.1 Translate all 23** `sentry_issue_alert` → `sentry_alert`, mapping per research: lifecycle conditions (`first_seen_event`/`reappeared_event`/`regression_event`) → `trigger_conditions`; frequency conditions (`event_frequency`/`event_unique_user_frequency`) + `tagged_event`/`level` filters → `action_filters[].conditions`; `filter_match` → `action_filters[].logic_type`; `actions_v2` + `frequency` → `action_filters[].actions` + `frequency_minutes`; bind `monitor_ids` to the project default/issue-stream monitor data source. Preserve every `name` byte-for-byte (operator dashboard queries + `assert-byok-rules-exist.sh` `EXPECTED_RULES` depend on names).
- [ ] **B.2 State surgery (refresh-free FIRST):** `terraform state rm sentry_issue_alert.<each>` for all 23 — a pure state op that does NOT call the provider read, so it succeeds despite the 410 and does NOT delete the server-side alert. Do NOT use `removed {}` blocks unless Phase 0 proves `plan`/`apply` does not refresh the removed resource (a refresh hits the 410 and aborts the whole apply — the declarative path is likely DOA here; `state rm` is the safe primitive).
- [ ] **B.3 Import:** `terraform import sentry_alert.<each> <import-id>` for all 23 (import-id format per B.0 — research suggests org-level `org-slug/alert-id`, UNVERIFIED; confirm against the provider docs for the chosen version). Import reads via the NEW alert API (live), so it works. On partial failure, follow README §Import rollback (state rm the partials, do NOT apply).
- [ ] **B.4 Execution vehicle (no-SSH):** state surgery cannot run from an operator SSH (there is no human-run path — ADR-031/#6589). It runs via a one-time `workflow_dispatch` job on `apply-sentry-infra.yml` (or a dedicated one-shot migration workflow) that performs `state rm` → `import` → `plan` (expect no-op) with the same Doppler R2 + `SENTRY_IAC_AUTH_TOKEN` plumbing the apply job uses. Sequence it BEFORE the merge that lands the `sentry_alert` blocks, or the post-merge full-root apply will try to CREATE 23 alerts (duplicates) — the create-gate would catch it, but do not rely on that as the plan.
- [ ] **B.5 Destroy-guard extension (load-bearing for B):** `sentry_alert.action_filters[]` carries array-of-blocks (`conditions[]`, `actions[]`). BEFORE any `sentry_alert` enters the full-root plan, extend `tests/scripts/lib/destroy-guard-filter-sentry.jq` with a `select(.type == "sentry_alert")` nested-clause counting `action_filters[].conditions[]` + `action_filters[].actions[]` + `trigger_conditions[]` shrink, extend `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` to allow `sentry_alert`, and update `tests/scripts/test-destroy-guard-counter-sentry.sh` + a fixture. (Per ADR-031 amendment 2026-05-29 Sharp Edge — the guard is `.tf ∪ state`-scoped and a new nested-block type slips it silently.)
- [ ] **B.6** Amend ADR-031 to `sentry_alert`-adopted; update `assert-byok-rules-exist.sh` only if names change (they must not).

### Phase 2 — Verification (both options; read-only, no extra prod write)

- [ ] `terraform validate` → exit 0.
- [ ] `terraform plan` full-root → **no-op** (0/0/0), no 410, across `sentry_issue_alert` (A) / `sentry_alert` (B) + all `sentry_cron_monitor` + `sentry_uptime_monitor`.
- [ ] `terraform fmt -check` clean on every edited `.tf`.
- [ ] `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` → `[ok]` (A: unchanged; B: after the `sentry_alert` clause lands).
- [ ] `bash tests/scripts/test-sentry-full-root-apply.sh` and `bash tests/scripts/test-destroy-guard-counter-sentry.sh` → pass.
- [ ] The PR's own `sentry-destroy-required` gate is GREEN (self-verifying: the committed lockfile lets CI `init -lockfile=readonly` + full-root plan succeed).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `cd apps/web-platform/infra/sentry && terraform validate` exits 0 (deprecation warnings allowed under A; absent under B).
- [ ] **AC2:** `terraform plan -no-color` returns **no 410** and a clean full-root plan (`Plan: 0 to add, 0 to change, 0 to destroy`, or a plan whose only non-no-op entries are individually enumerated + justified in the PR body). Evidence pasted into the PR body per `hr-no-dashboard-eyeball-pull-data-yourself`.
- [ ] **AC3 (Option A):** `versions.tf` pins a stable `jianyuan/sentry` version (no `-beta` suffix) and `.terraform.lock.hcl` contains that version's hashes for `linux_amd64` (assert: `grep -q '"<chosen>"' .terraform.lock.hcl` AND the lock has ≥3 `h1:` hashes). No `*.tfstate` diff in the PR.
- [ ] **AC4:** `git grep -c 'sentry_issue_alert\|sentry_alert' apps/web-platform/scripts/sentry-monitors-audit.sh apps/web-platform/scripts/sentry-monitors-audit.test.sh` → 0 (audit tooling is REST-based; unchanged by a version bump — Option A no-op; Option B leaves it unchanged too).
- [ ] **AC5:** `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` → `[ok]`; `bash tests/scripts/test-destroy-guard-counter-sentry.sh` → pass (Option B: after the `sentry_alert` jq clause + fixture land).
- [ ] **AC6:** `terraform fmt -check` clean on every edited `.tf`.
- [ ] **AC7:** ADR-031 amended (dated 2026-07-17, #6636) recording the bump + the RE-AFFIRMED `sentry_alert` deferral (Option A) — or the adoption (Option B). `Ref #6636` in the PR body (NOT `Closes` — see Sharp Edge on ops-remediation, but this fix is code-only and self-verifying, so `Closes #6636` is acceptable IFF the PR merge fully resolves the break with no post-merge operator step; use `Ref` if Option B's state surgery is a separate pre-merge workflow_dispatch).
- [ ] **AC8:** README.md "6 issue alerts" corrected to 23.

### Post-merge (operator)

- [ ] **None for Option A.** Automation: not feasible because there is nothing to run — the PR merge triggers `apply-sentry-infra.yml`'s full-root apply, which converges to no-op automatically; the PR gate already proved the plan is clean. Verify via the Actions run of `apply-sentry-infra.yml` (green) — no SSH, no dashboard.
- [ ] **Option B only:** the one-time `state rm`+`import` runs as a `workflow_dispatch` job (Phase B.4) BEFORE the merge; its Actions log is the evidence. Not an SSH/operator-console step.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — single-user-incident threshold, no UI surface)

### Engineering (CTO) — inline
**Status:** reviewed (inline; Task domain-leader spawn deferred to the one-shot review phase)
**Assessment:** IaC-only change against an already-provisioned Sentry surface. Option A is a provider-version bump + lockfile regen — no new infra, secret, or vendor; the existing `apply-sentry-infra.yml` full-root apply is the delivery vehicle (no new workflow, no SSH). The only real risk in A is provider schema drift on the 23 `_v2` bodies or on cron/uptime, fully surfaced by the Phase 0 measurement before merge. Option B is genuinely high-risk (23× state surgery, monitor-binding semantics, destroy-guard extension) and is correctly gated behind a measurement proving A is impossible.

### Product/UX Gate
**Tier:** none (no user-facing UI surface — no file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`)
**Decision:** N/A — infrastructure/tooling change. User-brand impact (auth + Art. 33 paging continuity) is captured in `## User-Brand Impact` and drives the single-user-incident threshold + CPO sign-off, not a UX gate.

## Infrastructure (IaC)

### Terraform changes
- **Files (Option A):** `apps/web-platform/infra/sentry/versions.tf` (version pin), `.terraform.lock.hcl` (regenerated), optionally `issue-alerts.tf` (only if Phase 0 shows `_v2` drift), `README.md` (count fix). No `main.tf`/`variables.tf` provider-auth change.
- **Files (Option B, additional):** `issue-alerts.tf` (full rewrite → `sentry_alert`), `tests/scripts/lib/destroy-guard-filter-sentry.jq`, `tests/scripts/test-destroy-guard-sentry-scope-guard.sh`, `tests/scripts/test-destroy-guard-counter-sentry.sh` + fixture, a one-shot migration workflow step.
- **Provider:** `jianyuan/sentry` `0.15.0-beta2` → chosen stable. `required_version >= 1.6` unchanged (CI `TERRAFORM_VERSION: 1.10.5`).
- **Sensitive variables:** none added. `SENTRY_IAC_AUTH_TOKEN` (GitHub repo secret, exported as `SENTRY_AUTH_TOKEN`) + R2 creds (Doppler `prd_terraform`) — unchanged. No new `TF_VAR_*`, no operator mint.

### Apply path
- **Option A:** cloud-init N/A. Delivery is the existing **push-to-main full-root apply** (`apply-sentry-infra.yml`) — the PR merge IS the apply trigger; it consumes the committed lockfile via `init -lockfile=readonly` and converges to no-op. Expected downtime: none (no resource changes). Blast radius: the full state key is in the plan universe (full-root), but with 0 changes the apply is inert.
- **Option B:** taint/replace NOT used. State surgery (`state rm`+`import`) via one-time `workflow_dispatch` BEFORE merge, then the normal apply converges. Blast radius: 23 resources detached + re-imported; the destroy guard + `[ack-destroy]` gate governs any accidental delete/create.

### Distinctness / drift safeguards
- `dev != prd`: N/A (single Sentry org `jikigai-eu`; no dev/prd Sentry split per ADR-031).
- `lifecycle.ignore_changes` on the import-only auth_* rules stays as-is (Option A); adjusted only if Phase 0 proves a `_v2` reshape.
- State storage: R2 backend, `use_lockfile = false`. A bump lands NO secret in state (no resource created). The `use_lockfile = false` unlocked-write window (ADR-031 accepted consequence) is unchanged; do not run a manual apply while CI applies.
- Drift detection for this root is still absent (tracked by **#6612** — needs raw-`SENTRY_AUTH_TOKEN` plumbing, not a matrix line). Not in scope; the bump does not change that gap.

### Vendor-tier reality check
- N/A — no resource creation, no free-tier gate. The chosen provider version is a stable public registry release (no paid tier).

## Observability

```yaml
liveness_signal:
  what: "apply-sentry-infra.yml full-root plan+apply returns to a clean no-op (0/0/0, no 410); the 23 issue alerts + 49 cron + 4 uptime monitors remain manageable and keep firing"
  cadence: "per-PR (sentry-destroy-required gate) + per-push-to-main (apply job)"
  alert_target: "GitHub Actions run status (required check sentry-destroy-required); post-apply assert-byok-rules-exist.sh pages IssueOwners/ActiveMembers if a BYOK rule vanishes"
  configured_in: ".github/workflows/apply-sentry-infra.yml; apps/web-platform/infra/sentry/versions.tf"
error_reporting:
  destination: "GitHub Actions (plan/apply exit code); Sentry itself for rule fires"
  fail_loud: "terraform plan/apply non-zero exit fails the required gate; a 410 is a hard plan failure, not a warning — the whole gate goes red"
failure_modes:
  - mode: "chosen provider version still 410s on issue-alert reads"
    detection: "Phase 0.4 terraform plan measurement BEFORE any merge"
    alert_route: "decision fork to Option B; no merge until a no-op plan is achieved"
  - mode: "provider bump introduces _v2 / cron / uptime schema drift (silent apply of a real change)"
    detection: "Phase 0.4 full-root plan shows non-no-op; PR-gate plan is the CI enforcement"
    alert_route: "sentry-destroy-required required check (red) + [ack-destroy]/create-gate on any delete/create"
  - mode: "Option B state surgery drops a live paging rule"
    detection: "assert-byok-rules-exist.sh post-apply liveness (fail-closed, by name); sentry-monitors-audit.sh Class A/C"
    alert_route: "apply job fails; audit report to knowledge-base/legal/audits/"
logs:
  where: "GitHub Actions run logs (plan/apply); Sentry dashboard for rule fires"
  retention: "GitHub Actions default; Sentry default"
discoverability_test:
  command: "cd apps/web-platform/infra/sentry && terraform init -input=false && terraform plan -no-color; echo exit=$?"
  expected_output: "no '410 This API no longer exists'; Plan: 0 to add, 0 to change, 0 to destroy; exit=0"
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-031** (`knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`) — this is a change to a recorded decision (the `Provider source` section pins beta2 with "re-evaluate on first stable v0.15.0"; the 2026-05-29 amendment recorded the `sentry_alert` migration deferral). Add `Amendment (2026-07-17, #6636)`:
- Option A: provider bumped beta2 → `<chosen stable>` to clear the Sentry 410 issue-alert-read retirement; `## Decision` `Provider source` updated to the stable pin. The `sentry_alert` migration deferral is **RE-AFFIRMED** — the latest stable STILL requires `monitor_ids` + lacks `project`, so project-wide frequency rules remain unmigratable without a semantic change. Re-evaluation criterion updated to "when `sentry_alert` gains `project` or drops the `monitor_ids` requirement for project alerts."
- Option B (if reached): ADR-031 flips to `sentry_alert`-adopted, records the monitor-binding approach + the destroy-guard extension, and supersedes the 2026-05-29 deferral amendment.
This is an in-scope plan task (amend, not a follow-up issue).

### C4 views
**No C4 impact — enumeration checked against all three `.c4` files** (`model.c4`, `views.c4`, `spec.c4`, read 2026-07-17):
- **External human actors:** the only actor Sentry touches is `founder` (`sentry -> founder` paging edge, model.c4:452) — unchanged; a provider bump adds no correspondent/recipient.
- **External systems / vendors:** `sentry` system already modeled (model.c4:273) with inbound edges `hetzner -> sentry`, `webapp -> sentry`, `github -> sentry` and outbound `sentry -> founder`. No new vendor, endpoint, or data store. `betterstack` (the second paging plane) unchanged.
- **Containers / data stores:** none added (provider version is not a container).
- **Access relationships:** unchanged — no owner/tenancy edge shifts.
Therefore no `.c4` edit and no `views.c4 include` change is required. **Observed pre-existing drift (out of scope, flagged not fixed):** `model.c4:451` still describes `apply-sentry-infra.yml`'s "`paths:` filter is the 3 rule files, not the whole root" — falsified by #6589 (contradicted by model.c4:275 which correctly says FULL-ROOT). This was introduced by #6589, not #6636; correct it only if the C4 is touched for another reason.

### Sequencing
Option A is true at merge (the bump clears the 410 immediately). Option B's ADR flip is true only after the state surgery converges; author it `status: adopting` if the surgery is a separate pre-merge step.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` grepped for `infra/sentry`, `sentry_issue_alert`, `sentry_alert`, `apply-sentry`:
- **#3829** — "review: CI gate enforcing 'new Sentry monitor type → sentry-scrub.ts must change'". **Acknowledge** (different concern: monitor-type → PII-scrub carve-out, not the 410/provider bump). Not folded in; remains open.

No other overlap. (Check ran; result recorded.)

## Sharp Edges

- **`terraform init -lockfile=readonly` refuses any provider whose checksum is absent from `.terraform.lock.hcl`.** The apply job AND the PR gate both use it. A lock regenerated on a single platform (missing `linux_amd64`) breaks CI init even though it works locally. Regenerate with `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64` (mirror the 3 `h1:` hashes already present) and commit the lock in the SAME PR as the `versions.tf` bump.
- **"A provider bump clears the 410" is a MEASURED claim, not a researched one.** The 410 is a server-side retirement; a provider version clears it only by reading a still-live endpoint, and the research agent hedged ("should", "likely"). Phase 0.4 must observe a real `terraform plan` with no 410 before Option A is adopted — do not merge on the research's version claim alone. If the latest stable still 410s, the honest outcome is Option B (or C), not "bump harder."
- **`sentry_alert` is still monitor-bound in the latest stable (the #4610 blocker persists).** Do NOT read the deprecation message "migrate to `sentry_alert`" as "the migration is a drop-in." `sentry_alert` requires `monitor_ids` and has no `project` attribute; a project-wide frequency rule (e.g. `zot_mirror_fallback_rate`, `event_frequency` only, no lifecycle trigger) cannot populate `trigger_conditions` faithfully without a synthetic monitor — a semantic change, not a rename.
- **Cross-type `state mv` is impossible; use refresh-free `state rm` + `import`, in that order.** `sentry_issue_alert` and `sentry_alert` share zero routing attributes. `state mv` would leave every attribute unconfigured. `state rm` is a pure state op that does NOT call the provider read → it is the ONLY primitive that works while the 410 is live. `removed {}` blocks are likely DOA (a `plan`/`apply` refresh of the removed resource hits the 410) — verify before relying on them.
- **Option B must extend the destroy guard BEFORE `sentry_alert` enters the plan.** `sentry_alert.action_filters[]` carries array-of-blocks; the `.jq` filter counts nested-block shrink per-type with NO `walk()`. A `sentry_alert` without a `select(.type == "sentry_alert")` clause has its block shrink counted as 0 and slips the guard (ADR-031 2026-05-29 Sharp Edge; the scope guard is `.tf ∪ state`-scoped and enforced by `test-destroy-guard-sentry-scope-guard.sh`).
- **Full-root means every resource is read — including cron + uptime.** A bump that fixes issue-alert reads but drifts a `sentry_cron_monitor`/`sentry_uptime_monitor` attribute produces a real apply change on 49+4 resources. Phase 0.4's plan covers all three types; do not scope the measurement to issue alerts.
- **`README.md` §First-time-import prose uses `de.sentry.io` for the API host** — that host is ingest-only and 404s the API per ADR-031's Cluster/Host Glossary + the 2026-05-17 slug-rewrite learning. The provider `base_url` (main.tf) is correctly the org-subdomain. Correct the README host only if the file is touched; do not introduce a `de.sentry.io` API call anywhere.
- **`Closes #6636` vs `Ref #6636`:** Option A is code-only + self-verifying (merge → auto-apply no-op) → `Closes #6636` is correct. Option B's state surgery is a separate pre-merge `workflow_dispatch` → use `Ref #6636` and close the issue after the surgery + apply converge (ops-remediation class, `wg-use-closes-n-in-pr-body-not-title-to`).
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan` Phase 4.6 — this section is filled (single-user incident, auth + Art. 33 paging continuity).

## Test Scenarios

- **Happy (A):** bump + regen lock → `terraform validate` exit 0 → `terraform plan` full-root no 410, `0/0/0` → PR `sentry-destroy-required` green → merge → `apply-sentry-infra.yml` green no-op.
- **Drift (A):** bump surfaces a `_v2` reshape → Phase 0.4 plan shows N changes → reconcile bodies/`ignore_changes` → re-plan no-op before merge.
- **Fallback (B):** no stable clears the 410 → translate 23 → `state rm` (refresh-free, survives 410) → `import` → destroy-guard extended → plan no-op.
- **Negative:** no `*.tfstate` committed diff (A); the PR gate's own plan proves no 410 (self-verifying); `assert-byok-rules-exist.sh` still lists all TF-owned BYOK/chat rules by name post-apply.
- **Guard:** `test-destroy-guard-sentry-scope-guard.sh` `[ok]`; `test-destroy-guard-counter-sentry.sh` pass; `test-sentry-full-root-apply.sh` pass.
