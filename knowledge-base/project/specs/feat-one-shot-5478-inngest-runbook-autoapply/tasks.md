---
title: "Tasks — fix: inngest runbook cutover Step 0 + auto-apply -target wiring"
issue: 5478
ref: 5450
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-17-fix-inngest-runbook-cutover-step0-and-autoapply-wiring-plan.md
date: 2026-06-17
---

# Tasks

Derived from `knowledge-base/project/plans/2026-06-17-fix-inngest-runbook-cutover-step0-and-autoapply-wiring-plan.md`. Pure-docs + 2-line workflow change; no code, no tests added.

## Phase 1 — Gap 1: runbook Step 0 (docs)

- [ ] 1.1 Read `knowledge-base/engineering/operations/runbooks/inngest-server.md` § Cutover procedure (lines ~270–311), § Key rotation (lines 114–123 — the in-file canonical `doppler run ... --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra apply` form to match), and § Fresh-host bootstrap `-chdir` shape (line 72).
- [ ] 1.1a IMPORTANT (deepen-plan finding): Step 0 MUST keep the explicit `terraform init -input=false` + the two bare-AWS `export AWS_ACCESS_KEY_ID/_SECRET` lines even though the § Key rotation precedent omits them. Rotation assumes a warm shell; a cutover Step 0 may be the operator's first apply of the session (cold shell), and without the R2 exports `init`/backend auth silently fails. Do NOT simplify Step 0 to match the terser rotation block.
- [ ] 1.2 Prepend **Step 0 — Provision the Redis secret** before the existing step 1 ("Quiesce arming"), using the canonical `prd_terraform` triplet (bare-AWS exports → `terraform init -input=false` → `doppler run ... --name-transformer tf-var -- terraform apply -target=random_password.inngest_redis_password_prd -target=doppler_secret.inngest_redis_password_prd`) plus a read-only `doppler secrets get INNGEST_REDIS_PASSWORD ... --plain` presence confirmation. No `ssh`. (AC1, AC2, AC3)
- [ ] 1.3 Tighten the section intro sentence ("Run these steps in order…") to reference Step 0 as the secret-provisioning precondition; keep the existing 7 steps verbatim below it. (AC4)

## Phase 2 — Gap 2: workflow auto-apply wiring

- [ ] 2.1 Read `.github/workflows/apply-web-platform-infra.yml` Terraform-plan step (lines 246–354), confirming the inngest target block ends at line 346 and the `hcloud_firewall.*` block follows.
- [ ] 2.2 Insert two `-target=` lines (each with trailing `\`) immediately after line 346 (`doppler_secret.inngest_heartbeat_url_prd`) and before `hcloud_firewall.web`:
      `-target=random_password.inngest_redis_password_prd \` and `-target=doppler_secret.inngest_redis_password_prd \`. (AC5, AC6)

## Phase 3 — Verification

- [ ] 3.1 `actionlint .github/workflows/apply-web-platform-infra.yml` clean (no new errors vs main). (AC6)
- [ ] 3.2 `grep -c 'target=random_password.inngest_redis_password_prd\|target=doppler_secret.inngest_redis_password_prd' .github/workflows/apply-web-platform-infra.yml` == 2. (AC5)
- [ ] 3.3 `git diff --stat main` shows exactly two files changed (runbook + workflow). (AC7)
- [ ] 3.4 Regression anchors still pass unchanged: `bash apps/web-platform/infra/inngest.test.sh`, `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`, `bash tests/scripts/test-destroy-guard-regex-parity.sh`.
- [ ] 3.5 PR body: `Closes #5478`, `Ref #5450`; note the no-guard-suite-sweep finding (contrast #4591) so review does not re-litigate.

## Phase 4 — Post-merge (automated)

- [ ] 4.1 Confirm the merge fires `apply-web-platform-infra.yml` (workflow-path trigger) and its plan includes the two redis-password targets. (AC8)
- [ ] 4.2 `doppler secrets get INNGEST_REDIS_PASSWORD -p soleur -c prd --plain` returns a non-empty 48-char value. (AC9)
