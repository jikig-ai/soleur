---
title: Tasks for CI Required ruleset widening via Terraform
date: 2026-05-16
lane: cross-domain
plan: knowledge-base/project/plans/2026-05-16-feat-ci-required-ruleset-widening-via-terraform-plan.md
---

# Tasks — CI Required ruleset widening via Terraform

Derived from
`knowledge-base/project/plans/2026-05-16-feat-ci-required-ruleset-widening-via-terraform-plan.md`.

## Phase 0 — Operator preconditions (one-time, manual)

These tasks run on the operator's workstation, not in CI. They are
required BEFORE Phase 1 implementation tasks begin.

- [ ] **0.1** Mint a fine-grained GitHub PAT (`Administration: Read+Write`
  on `jikig-ai/soleur`, 90-day expiry, named
  `terraform-infra-github-rulesets`).
- [ ] **0.2** Stash the PAT in Doppler `prd_terraform` as
  `GH_RULESET_PAT` via
  `doppler secrets set GH_RULESET_PAT='<token>' -p soleur -c prd_terraform`.
- [ ] **0.3** Verify the PAT with
  `GH_TOKEN=$(doppler secrets get GH_RULESET_PAT -p soleur -c prd_terraform --plain) gh api repos/jikig-ai/soleur/rulesets/14145388 | jq '.id'` →
  returns `14145388`.
- [ ] **0.4** Capture live state as import oracle:
  `gh api repos/jikig-ai/soleur/rulesets/14145388 > /tmp/ruleset-live-pre-import.json`.

## Phase 1 — Scaffold `infra/github/` Terraform root

- [ ] **1.1** Create `infra/github/main.tf` with R2 backend
  (`key = "github/terraform.tfstate"`) + `github` provider block.
- [ ] **1.2** Create `infra/github/versions.tf` pinning
  `integrations/github` to `~> 6.10` (per
  `2026-03-19-github-ruleset-stale-bypass-actors.md`).
- [ ] **1.3** Create `infra/github/variables.tf` (`gh_token`,
  `gh_owner` default `jikig-ai`, `gh_repo` default `soleur`,
  `actions_integration_id` default `15368`, `codeql_integration_id`
  default `57789`).
- [ ] **1.4** Create `infra/github/ruleset-ci-required.tf` declaring
  exactly 14 `required_check` blocks (5 baseline + 9 new), 2
  `bypass_actors` blocks, `~DEFAULT_BRANCH` condition,
  `enforcement = "active"`,
  `strict_required_status_checks_policy = true`,
  `do_not_enforce_on_create = false`.
- [ ] **1.5** Create `infra/github/outputs.tf` exposing `ruleset_id`
  and `ruleset_url`.
- [ ] **1.6** Create `infra/github/.gitignore` mirroring
  `apps/web-platform/infra/.gitignore`.
- [ ] **1.7** Create `infra/github/README.md` with the canonical
  operator runbook (Phases 0-5 per the plan body).
- [ ] **1.8** `terraform fmt -recursive infra/github/` to normalize.

## Phase 2 — Import (operator-driven, post-merge)

- [ ] **2.1** `cd infra/github/`; export R2 backend creds
  (AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY from
  `prd_terraform` — raw, NOT tf-var-transformed);
  `terraform init -input=false`.
- [ ] **2.2** Import existing ruleset:
  `doppler run -p soleur -c prd_terraform --name-transformer tf-var --
   terraform import github_repository_ruleset.ci_required soleur:14145388`.
- [ ] **2.3** Run plan-diff probe; halt if diff is not exactly
  `before_count: 5, after_count: 14, actions: ["update"]`.
- [ ] **2.4** `terraform apply tfplan.binary` (operator-attested).
- [ ] **2.5** Verify post-apply: `gh api repos/jikig-ai/soleur/rulesets/14145388
  | jq '.rules[0].parameters.required_status_checks | length'` → `14`.

## Phase 3 — GDPR Article 30 register PA12 entry

- [ ] **3.1** Append `## Processing Activity 12 — GitHub
  branch-protection state custody (CI policy substrate)` to
  `knowledge-base/legal/article-30-register.md` between PA11 and the
  Vendor / Sub-Processor Mapping section. All 8 limbs filled per
  plan body §Phase 3.

## Phase 4 — `infra-validation.yml` extension (3 coordinated edits)

- [ ] **4.1** Extend `paths:` filter to include `infra/**`.
- [ ] **4.2** Refactor `detect-changes` to handle both
  `apps/*/infra/` and `infra/*` pathspecs. Verify with the fixture
  test in plan body §Phase 4.2.
- [ ] **4.3** Verify in PR CI run that `infra/github` appears in the
  `validate` matrix output (post-push observation, not a pre-push
  authoring step).

## Phase 5 — ADR-032 (architecture decision record)

- [ ] **5.1** Create
  `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md`
  mirroring ADR-031 (sentry-as-iac) shape (~30 lines).

## Phase 6 — Follow-up issues (file, post-merge)

- [ ] **6.1** File `secret-scan: confirm allowlist-diff parser
  widening (#3888) now blocked at merge gate post-ruleset-widening`
  (labels: `priority/p3-low`, `domain/engineering`).
- [ ] **6.2** File `secret-scan: add 'secret-scan smoke matrix
  complete' rollup job + require in CI Required ruleset` (labels:
  `priority/p3-low`, `domain/engineering`, `type/chore`).
- [ ] **6.3** File `ci: add 'pr-quality-guards rollup' job + require
  in CI Required ruleset` (labels: same as above).
- [ ] **6.4** File `ci: investigate whether 'CodeQL' parent check
  already aggregates 'Analyze (*)' subjobs` (labels: same).
- [ ] **6.5** File `ci: enumerate docs + perf gates and evaluate
  required-check candidates` (labels: same).
- [ ] **6.6** `gh issue close 3888` AFTER Phase 2.5 confirms apply
  success; comment referencing this PR.

## Tests

This is an infra-only change. The "test" triplet:

1. **Static:** `terraform validate` in CI via
   `infra-validation.yml` (gates AC6).
2. **Plan-diff:** Phase 2.3 `terraform show -json` jq probe
   (gates AC15 post-merge).
3. **Live:** Phase 2.5 `gh api ... | jq '... | length'` returns
   `14` (gates AC16 post-merge).
