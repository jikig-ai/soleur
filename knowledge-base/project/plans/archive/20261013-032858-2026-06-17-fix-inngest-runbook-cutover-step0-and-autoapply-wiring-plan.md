---
title: "fix: inngest runbook cutover Step 0 + auto-apply -target wiring for Redis secret"
type: fix
issue: 5478
ref: 5450
branch: feat-one-shot-5478-inngest-runbook-autoapply
lane: cross-domain
requires_cpo_signoff: false
date: 2026-06-17
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: Step 0 routes secret provisioning THROUGH Terraform (doppler_secret.inngest_redis_password_prd is a real .tf resource applied via the canonical `terraform apply`), and the Gap-2 workflow edit IS the auto-apply IaC wiring. The `doppler secrets set INNGEST_CUTOVER_QUIESCE=...` lines are pre-existing runtime feature-flag toggles (not infra provisioning) quoted verbatim from the already-shipped #5459 runbook — not new manual steps introduced by this plan. No new .tf resource or cloud-init reshape is required. -->

# 🐛 fix: inngest runbook cutover Step 0 + auto-apply `-target` wiring for the Redis secret

**Closes #5478.** Two post-merge gaps surfaced while verifying #5459 (durable Supabase Postgres + self-hosted Redis Inngest backend, tracked by #5450). Both are small follow-ups bundled into one PR: a runbook prose edit and a 2-line workflow target-list addition. Neither is blocking #5450 Phase 2 — the #5450 tracker comment already carries the correct cutover sequence; this PR syncs the **canonical** runbook and closes the auto-apply maintainability gap.

## Overview

- **Gap 1 (docs):** The `inngest-server.md` § Cutover procedure starts at step 1 = "Quiesce arming", silently assuming both backend secrets already exist in Doppler prd. But `INNGEST_REDIS_PASSWORD` is **not** created at merge time (see Research Reconciliation). Without a leading `terraform apply` to mint it, the step-4 `deploy inngest` brings inngest-server up with an empty `--redis-uri` password → fails closed at the `verify_inngest_health` HARD gate. Fix: prepend an explicit **Step 0 — terraform apply (prd_terraform) → confirm `INNGEST_REDIS_PASSWORD` present** to the procedure, keeping the existing 7 steps intact below it.
- **Gap 2 (workflow):** The two Redis-password resources are absent from the `apply-web-platform-infra.yml` plan-step `-target=` allow-list, so they do NOT auto-reconcile on merge (the 12 other inngest resources DO). Add the two `-target=` lines so the secret auto-applies on the next infra-touching merge and a future `terraform taint` rotation lands without a manual full apply.

This is a `MINIMAL`-tier plan: a single prose edit to one runbook section plus two lines added to one workflow file. No code, no migration, no schema, no new infra.

## Research Reconciliation — Spec vs. Codebase

All premises in the issue body were verified against the worktree at plan time. None were stale.

| Claim (issue #5478) | Reality (verified) | Plan response |
| --- | --- | --- |
| `random_password.inngest_redis_password_prd` exists in inngest.tf | ✅ `apps/web-platform/infra/inngest.tf:145` | Use this exact address in the Gap-2 target line |
| `doppler_secret.inngest_redis_password_prd` exists in inngest.tf | ✅ `apps/web-platform/infra/inngest.tf:150` (`name = "INNGEST_REDIS_PASSWORD"`, config `prd`, `ignore_changes = [value]`) | Use this exact address in the Gap-2 target line |
| Those two resources are absent from the workflow `-target=` allow-list | ✅ Plan step lines `332-346` target the 6 `random_id` + 6 `doppler_secret` inngest keys + heartbeat/policy/heartbeat-url, but NOT the two redis-password addresses | Append both after the existing inngest block (after line 346), before the `hcloud_firewall.*` block |
| `INNGEST_POSTGRES_URI` is present (set out-of-band), Redis password absent post-merge | ✅ inngest.tf comments confirm POSTGRES_URI is provisioned out-of-band and intentionally NOT a TF resource (`inngest.tf:162-176`); the redis password is a TF `doppler_secret` only reconciled when its target is in the apply allow-list | Step 0 mints only `INNGEST_REDIS_PASSWORD`; POSTGRES_URI is a precondition, not a Step-0 product |
| Runbook § Cutover procedure starts at "Quiesce arming" | ✅ `inngest-server.md:278` step 1 = **Quiesce arming**; no terraform-apply precondition before it | Prepend Step 0 |
| `verify_inngest_health` fails closed on empty `--redis-uri` | ✅ `inngest-server.md:297-298` — HARD gate fails deploy if `--postgres-uri` set but `--redis-uri` absent OR `inngest-redis.service` inactive | Step-0 prose cites this as the failure mode it prevents |
| Workflow line "~253" documents the allow-list-maintenance convention | ✅ `apply-web-platform-infra.yml:252-256` ALLOW-LIST MAINTENANCE comment: new `*.tf` resources should get a matching `-target=<addr>` | Follow this convention verbatim |
| Adding two `-target=` lines needs a sibling guard-suite update | ❌ No test asserts the workflow target-list count. `test-destroy-guard-counter-web-platform.sh` exercises the destroy-guard **jq filter** against fixtures (not the target list); `test-destroy-guard-regex-parity.sh` checks regex parity, not membership. `inngest.test.sh:234-235` asserts the two resources exist in inngest.tf (unaffected by the workflow edit). | No test sweep required for Gap 2 (contrast #4591, where a Sentry scope-guard suite DID assert membership). State this explicitly so review does not re-litigate. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — these are operator-facing artifacts (a runbook and a CI allow-list). The *downstream* risk this PR removes: an operator running the cutover from the canonical runbook hits a failed `deploy inngest` (empty `--redis-uri` → `verify_inngest_health` fail-closed) and a reminder-delivery outage window until they diagnose the missing secret. Reminders (`reminder.scheduled`) are the user-facing artifact behind inngest; a botched cutover delays them.

**If this leaks, the user's data is exposed via:** N/A — no new secret is created or printed by this PR. Step 0 mints `INNGEST_REDIS_PASSWORD` via the existing `random_password` resource (`special = false`, masked Doppler secret); the runbook text references the secret by name only, never its value.

**Brand-survival threshold:** none.

`threshold: none, reason: docs + CI-allowlist change touches no schema/auth/API/regulated surface and creates/prints no secret; downstream cutover-failure risk is operator-facing and self-healing once Step 0 runs.`

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (Gap 1 — Step 0 present):** `knowledge-base/engineering/operations/runbooks/inngest-server.md` § Cutover procedure has a new leading **Step 0** that (a) runs the canonical `terraform apply` against `prd_terraform`, and (b) confirms `INNGEST_REDIS_PASSWORD` is present in Doppler prd before proceeding. Verify: `awk '/^### Cutover procedure/{f=1} f&&/Step 0|^0\./{print; exit}' knowledge-base/engineering/operations/runbooks/inngest-server.md` returns a non-empty line referencing the secret provisioning.
- [x] **AC2 (Gap 1 — canonical TF invocation):** Step 0's command block uses the canonical `prd_terraform` triplet verbatim (per learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`): the two bare-AWS R2-backend `export`s (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` via `doppler secrets get ... --plain`), `terraform init -input=false`, then `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply ...` scoped with `-target=random_password.inngest_redis_password_prd -target=doppler_secret.inngest_redis_password_prd`. Verify: the new block contains both `-target=` redis addresses AND a `--name-transformer tf-var` apply.
- [x] **AC3 (Gap 1 — confirm-present command, no SSH):** Step 0 includes a read-only presence check `doppler secrets get INNGEST_REDIS_PASSWORD -p soleur -c prd --plain` (or equivalent read-only probe) that does NOT use `ssh`. Verify: the Step-0 block contains no `ssh ` token (`hr-no-ssh-fallback-in-runbooks`).
- [x] **AC4 (Gap 1 — existing steps intact):** The pre-existing 7 cutover steps (Quiesce arming → Rollback tripwire) are preserved verbatim in order below the new Step 0. Verify: no step body text is lost (diff review); the seven existing numbered steps remain (Step 0 precedes step 1).
- [x] **AC5 (Gap 2 — two target lines added):** `apply-web-platform-infra.yml` Terraform-plan step contains `-target=random_password.inngest_redis_password_prd` AND `-target=doppler_secret.inngest_redis_password_prd`. Verify: `grep -c 'target=random_password.inngest_redis_password_prd\|target=doppler_secret.inngest_redis_password_prd' .github/workflows/apply-web-platform-infra.yml` returns `2`, both inside the `terraform plan` block (placed after line 346 `doppler_secret.inngest_heartbeat_url_prd`, before the `hcloud_firewall.*` block).
- [x] **AC6 (Gap 2 — workflow still valid):** `actionlint .github/workflows/apply-web-platform-infra.yml` passes (no new errors vs. main). The two added lines carry the trailing `\` line-continuation of the surrounding `-target=` lines and are placed BEFORE the `hcloud_firewall.web` target (the list terminator `hcloud_firewall_attachment.web` has no trailing `\` and must not be disturbed). Verify via actionlint + visual diff.
- [x] **AC7 (no over-reach):** `git diff --stat main` shows exactly two files changed: the runbook and the workflow. No `.tf`, no test, no other file.

### Post-merge (operator / automated)

- [ ] **AC8 (auto-apply reconciles):** This PR's workflow edit itself triggers `apply-web-platform-infra.yml` on merge (line 71 lists the workflow file path as a trigger). The apply run includes the two redis-password targets in its plan. Automation: the PR merge fires the workflow — no operator step. Verify the run's Post-apply summary + plan output shows the two new targets either created (first time) or no-op (already present from a prior manual apply). `Automation: handled by the merge-triggered apply-web-platform-infra.yml run.`
- [ ] **AC9 (secret present):** After AC8's run, `doppler secrets get INNGEST_REDIS_PASSWORD -p soleur -c prd --plain` returns a non-empty 48-char value. Automation: single `doppler secrets get` read (no SSH, no dashboard) — bake into post-merge verification per the automation-feasibility gate; do NOT punt to operator dashboard-watching.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — § Cutover procedure (around line 270–311): prepend **Step 0** with the canonical `prd_terraform` apply triplet scoped to the two redis-password targets + the read-only `INNGEST_REDIS_PASSWORD` presence confirmation; keep the existing 7 steps intact below it. Tighten the section intro ("Run these steps in order…") to reference Step 0 as the secret-provisioning precondition.
- `.github/workflows/apply-web-platform-infra.yml` — Terraform-plan step (`-target=` allow-list, currently ending the inngest block at line 346): insert two lines —
  ```
              -target=random_password.inngest_redis_password_prd \
              -target=doppler_secret.inngest_redis_password_prd \
  ```
  immediately after line 346 (`-target=doppler_secret.inngest_heartbeat_url_prd \`) and before the `hcloud_firewall.web` target. Both lines carry the trailing `\` (they are mid-list, not the terminator).

## Files to Create

None.

## Open Code-Review Overlap

None — no open `code-review`-labeled issues touch these two files (queried at plan time; the two paths are an operations runbook and an infra-apply workflow, neither in any open review scope-out).

## Step-0 prose (proposed canonical text)

The Step-0 block MUST use the canonical `prd_terraform` triplet (the bare-AWS exports are load-bearing — `tf-var` name-transforming the R2-backend creds silently breaks S3-backend auth; see learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`). Match the existing § Fresh-host bootstrap `-chdir` form (`inngest-server.md:72`):

````markdown
0. **Provision the Redis secret** (one-time precondition — `INNGEST_REDIS_PASSWORD` is NOT created at
   merge time; the `apply-web-platform-infra.yml` allow-list now reconciles it on the next infra merge,
   but for an immediate cutover run, apply it explicitly here). `INNGEST_POSTGRES_URI` is already present
   (set out-of-band, see inngest.tf). From the repo root:
   ```bash
   export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID  -p soleur -c prd_terraform --plain)
   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
   terraform -chdir=apps/web-platform/infra init -input=false
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform -chdir=apps/web-platform/infra apply \
       -target=random_password.inngest_redis_password_prd \
       -target=doppler_secret.inngest_redis_password_prd
   # Confirm the secret now exists (read-only, no SSH):
   doppler secrets get INNGEST_REDIS_PASSWORD -p soleur -c prd --plain   # → 48-char URL-safe value
   ```
   If the value is already present (a prior auto-apply or manual run minted it), this is a clean no-op —
   proceed to step 1.
````

Verify the exact `-chdir` / triplet form against the runbook + workflow at /work time before pasting.

### Research Insights (deepen-plan, 2026-06-17)

**Precedent-diff gate (Phase 4.4) — in-runbook canonical form found.** The runbook ALREADY contains the canonical apply form this plan adopts. § Key rotation (`inngest-server.md:114-123`) uses verbatim:
```
doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra apply
```
and § Fresh-host bootstrap (`:72`) + § Heartbeat-miss (`:102`) use the `terraform -chdir=apps/web-platform/infra ...` shape. This is a STRONGER precedent than the cross-runbook drift learning — Step 0 should match this in-file form exactly (`--name-transformer tf-var` + `-chdir`), so the runbook stays internally consistent.

**Load-bearing deviation — Step 0 keeps the explicit bare-AWS R2 exports; the rotation precedent omits them (intentional).** The § Key rotation block does NOT prepend the two `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...` lines or a `terraform init` — it assumes a WARM operator shell where `.terraform/` already cached the R2 backend creds from a prior `init` (a rotation is rarely the first command of a session). Step 0 of a **cutover** can plausibly be the operator's FIRST apply of the session (cold shell), so Step 0 MUST keep the explicit `init` + bare-AWS exports (per learning `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`) — without them the R2/S3 backend silently fails to authenticate at `init`. This is a deliberate divergence from the rotation precedent, not a copy error. /work should NOT "simplify" Step 0 to match the terser rotation block. (Note: the rotation block's omission is arguably a latent rough edge of its own, but fixing it is out of scope here — flag only.)

**AC6 tooling confirmed available.** `actionlint` is on PATH at v1.7.7 (verified at deepen time). AC6's `actionlint .github/workflows/apply-web-platform-infra.yml` is executable at /work time — no fallback needed. Composite-action caveat (the `actionlint`-rejects-`action.yml` Sharp Edge) does NOT apply: the target is a true workflow (`on:` + `jobs:`), not a composite action.

**No PAT-shaped variable, no UI surface, no new infra (gates 4.8/4.9/2.8 pass).** The plan introduces no `var.*_token`/`var.*_pat`, touches no `components/**`/`app/**/page.tsx`, and adds no `.tf` resource (only references two existing addresses by name in a `-target=` line + runbook prose). Phase 4.7 observability skip is correct (pure-docs + CI-allowlist).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — operations runbook + infrastructure-apply-workflow change. No product/UI surface, no legal/regulated data, no marketing/sales/finance/support implication. Engineering (operations) is the sole owner and author of the change.

## Observability

Skipped per Phase 2.9: this plan is **pure-docs + a CI allow-list addition**. Files-to-Edit are a `knowledge-base/**` runbook and a `.github/workflows/*.yml` allow-list line — neither is a code-class file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` (inngest.tf is NOT modified — only referenced by address), nor `plugins/*/scripts/`. No new error path, log call, or failure mode is introduced. The auto-apply run's existing Post-apply summary (`apply-web-platform-infra.yml:562-579`) already provides the observability surface for the workflow change.

## Infrastructure (IaC)

No `## Infrastructure (IaC)` reshape required (`<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` in frontmatter). Phase 2.8 reviewed: the plan introduces NO new infrastructure — it adds two `-target=` lines to an **existing** Terraform-apply workflow so two **already-defined** resources auto-reconcile, and documents an apply of those same resources via the canonical `prd_terraform` IaC path. The Step-0 runbook command routes through Terraform (`doppler_secret.inngest_redis_password_prd` is a real `.tf` resource); it is NOT an operator SSH / dashboard-click / out-of-band `doppler secrets set` of a provisioned value. The `doppler secrets set INNGEST_CUTOVER_QUIESCE=...` lines quoted in the existing steps are pre-existing runtime feature-flag toggles (shipped in #5459), not infra provisioning. The Gap-2 workflow edit IS the auto-apply IaC wiring the issue asks for — the correct posture, not a violation.

## Architecture Decision (ADR/C4)

Skipped per Phase 2.10: this plan makes no architectural decision. It syncs a runbook to the already-shipped #5459 architecture (durable Inngest backend, ADR-030 closure) and closes an auto-apply allow-list gap. No ownership/tenancy move, no new substrate, no resolver/trust-boundary change, no ADR reversal. A competent engineer reading the existing ADRs + C4 is NOT misled after this ships — the architecture is unchanged; only its operator documentation and CI reconciliation catch up.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold `none` with a non-empty scope-out reason.)
- **Mid-list `-target=` insertion, not list-terminator:** the last target in the plan step (`hcloud_firewall_attachment.web`, line 348) is the only line with NO trailing `\`. The two new lines MUST go BEFORE the `hcloud_firewall.*` block (right after line 346) and carry trailing `\`. Appending after the terminator would dangle a `\` or break the shell continuation. Verify with `actionlint` (AC6) and a `bash -c` extraction of the `run:` block.
- **Canonical TF triplet is load-bearing:** the two bare-AWS `export`s before `terraform init` are NOT optional. Omitting `--name-transformer tf-var` on the apply yields ~13 `No value for required variable` errors; passing the R2 creds THROUGH `tf-var` mangles them to `TF_VAR_aws_*` and the S3 backend silently fails to authenticate. Copy the triplet verbatim from the existing § Fresh-host bootstrap / drift-runbook precedent — do not paraphrase. (Learning: `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`.)
- **No guard-suite sweep needed (verified, contrast #4591):** unlike the Sentry uptime-monitor target extension (where `test-destroy-guard-sentry-scope-guard.sh` mechanically asserted target-list membership), the web-platform workflow has NO test asserting its `-target=` set count or membership. The destroy-guard counter/regex tests exercise the jq filter against fixtures, independent of the target list. `inngest.test.sh:234-235` asserts the two resources exist in `inngest.tf` and is unaffected by the workflow edit. State this in the PR body so review does not re-open the question.
- **`Closes #5478` is correct (not `Ref`):** both gaps are PR-shippable artifacts — the workflow merge itself fires the apply (no separate operator prod-write is needed to *satisfy* the AC). This is NOT a `type: ops-remediation` plan where the fix runs post-merge by an operator hand, so `wg-use-closes-n-in-pr-body-not-title-to`'s ops-remediation carve-out does not apply. AC8/AC9 are verification of the auto-apply, which happens automatically on merge. Use `Closes #5478` in the PR body; keep `Ref #5450` for the umbrella.

## Test Scenarios

No new automated test is added (pure-docs + allow-list line). Verification is the AC set above:
- `actionlint .github/workflows/apply-web-platform-infra.yml` (AC6) — run at /work time, must be clean.
- `grep` assertions in AC1–AC5, AC7 — deterministic, run at /work AC-check time.
- Post-merge AC8/AC9 — automatic apply run + single `doppler secrets get` read.

Existing tests that MUST still pass unchanged (regression anchors, not edited): `apps/web-platform/infra/inngest.test.sh`, `tests/scripts/test-destroy-guard-counter-web-platform.sh`, `tests/scripts/test-destroy-guard-regex-parity.sh`.
