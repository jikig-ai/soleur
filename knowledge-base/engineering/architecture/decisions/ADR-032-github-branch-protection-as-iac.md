---
title: "ADR-032 — GitHub branch-protection ruleset as IaC"
status: accepted
date: 2026-05-16
plan: knowledge-base/project/plans/2026-05-16-feat-ci-required-ruleset-widening-via-terraform-plan.md
spec: knowledge-base/project/specs/feat-one-shot-pr-3888-ruleset-required-checks-widening/tasks.md
issue: 3888
supersedes: none
related:
  - ADR-006-terraform-remote-backend-r2.md
  - ADR-031-sentry-as-iac.md
---

# ADR-032 — GitHub branch-protection ruleset as IaC

## Status

Accepted (2026-05-16).

## Context

PR #3886 merged on 2026-05-16T13:59:41Z with the `lint fixture content` CI job
reporting `"conclusion": "FAILURE"` in the status-check rollup. The merge
proceeded because that job was not in the `CI Required` ruleset's
`required_status_checks` list (5 baseline entries: `test`,
`dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate`).

The ruleset itself was created via the GitHub UI (ruleset id 14145388) and
mutated ad-hoc; there is no IaC trail for the policy that gates merges to
`main`. AGENTS.md `hr-all-infrastructure-provisioning-servers` mandates
Terraform for branch protections, but no `infra/github/` Terraform root
existed. Closing the documented merge-through failure mode requires both
(a) widening the required-check set to cover the secret-scan family + the
non-secret-scan correctness gates (`lockfile-sync`,
`service-role-allowlist-gate`, `tc-document-sha-guard`), and (b) bringing
the ruleset into IaC so future widenings are PR-reviewable.

Eight further secret-scan and guard-script jobs run on every PR
unconditionally but are not currently required; any one of them could fail
and merge silently, as `lint fixture content` did on #3886.

## Decision

Adopt the `integrations/github` Terraform provider (pinned `~> 6.10` per
repo-local learning `2026-03-19-github-ruleset-stale-bypass-actors.md`)
and create a new `infra/github/` Terraform root with R2 backend
(`github/terraform.tfstate`). Adopt the existing ruleset 14145388 into
Terraform state via `terraform import`, then widen
`required_status_checks` from 5 to 14 entries:

- **Tier 1** (6 jobs, secret-scan + guard-script-fixture): `gitleaks scan`,
  `lint fixture content`, `allowlist-diff (.gitleaks.toml paths surface)`,
  `rename-guard (allowlist destinations)`,
  `waiver discipline (issue:#NNN trailer)`,
  `Bash fixture tests for guard scripts`.
- **Tier 2** (3 jobs, correctness gates from `ci.yml`): `lockfile-sync`,
  `service-role-allowlist-gate`, `tc-document-sha-guard`.

All 9 new jobs run unconditionally on every PR (verified via
`.github/workflows/secret-scan.yml`, `.github/workflows/pr-quality-guards.yml`,
and `.github/workflows/ci.yml` — none has a `paths:` filter that would
cause the job not to report). Failing to verify "runs on every PR" before
requiring a check produces a permanent-pending merge gate; this is the
single largest operational risk and is documented in the ADR-032 contract
clause below.

### Per-root location

`infra/github/` at the repo root, NOT under `apps/web-platform/infra/`.
Branch protection is a repo-level concern affecting every workstream
(plugin, web-platform, telegram-bridge, docs), so placing the state key
under a single app would mis-signal ownership for a future multi-app
reorg. State key is `github/terraform.tfstate` to namespace cleanly under
the shared `soleur-terraform-state` bucket.

### Authentication

Fine-grained PAT named `terraform-infra-github-rulesets`, scoped to the
single repo `jikig-ai/soleur` with `Administration: Read+Write` only.
Stored in Doppler `prd_terraform/GH_RULESET_PAT` (NOT `GITHUB_TOKEN` —
that name collides with the magic variable Actions populates). At apply
time, `doppler run --name-transformer tf-var --` rewrites the env to
`TF_VAR_gh_token`, which the provider consumes via the sensitive
`gh_token` variable. The provider marks `token` sensitive, so the value
never lands in state plaintext.

### Apply discipline

Apply is operator-only. The auto-apply patterns in
`apply-deploy-pipeline-fix.yml` and `apply-sentry-infra.yml` (which run
`terraform apply -target=…` on push-to-main) do NOT apply here because
the ruleset mutation is a write-to-prod-policy event requiring single
human attestation per `hr-menu-option-ack-not-prod-write-auth`.

The mandatory pre-apply gate is the `terraform show -json | jq` probe
that asserts the diff is exactly:

```text
before_count: 5,
after_count:  14,
actions:      ["update"]
```

with zero other property changes. Any deviation (a bypass-actor diff,
condition tweak, integration_id phantom drift) signals that the import
surfaced unmanaged state the Terraform config does not yet model — the
operator reconciles by editing the config to match live state BEFORE
applying, never by applying the unreviewed diff.

## Consequences

### Positive

- **Auditable trail.** Every future change to `required_status_checks`,
  `bypass_actors`, or `conditions` lands as a PR with a `terraform plan`
  in the comment thread. The `scheduled-terraform-drift.yml` matrix
  (existing) picks this root up automatically once `infra/github/`
  appears in the directory walk.
- **Reproducible posture.** A `terraform destroy` + `terraform apply`
  cycle recreates the ruleset byte-for-byte; the existing UI-only state
  was not reproducible.
- **Aggregation.** Future Tier-3 widenings (the deferred `smoke (*)`
  matrix rollup, the `Block *` family rollup, docs/perf gates) become
  per-PR edits to `ruleset-ci-required.tf` rather than untracked UI
  clicks.

### Negative

- **Job-name fragility.** The 14 `context` strings in
  `ruleset-ci-required.tf` are literal job `name:` fields. A workflow
  rename (e.g. `lint fixture content` → `lint-fixture-content`) silently
  un-requires the check until this resource is updated in the same PR.
  This ADR documents the contract: job-name renames must include a
  paired `infra/github/` update. A future hook could enforce this; not
  in scope here.
- **Provider rough edges (v6.x).** Issues #2317 (integration_id drift),
  #2467 (`required_check` Required-vs-API), #2504 (bypass_actors
  ordering drift), #2536 (OrganizationAdmin actor_id 1↔0), #2952
  (bypass_actors removal silently no-ops) touch this PR's surface. The
  `~> 6.10` pin is the floor per the cited repo-local learning; the
  Phase 2.3 plan-diff probe catches any of the above producing
  unexpected diff at import time.
- **PAT rotation cadence.** 90-day FGPAT expiry means a 4-times-per-year
  manual mint + Doppler rotation step. Calendar reminder at +75 days.
  A `scheduled-gh-token-expiry-check.yml` sibling to
  `scheduled-cf-token-expiry-check.yml` is a Tier-3 follow-up.

## Escape hatches

If any of the following triggers fire, revert the import + apply:

- **`terraform import` fails 3+ times** with provider-incompatible
  schema. Action: keep the UI as source-of-truth, mark this ADR
  `status: rejected`, revert `infra/github/` and the
  `infra-validation.yml` extension.
- **Phase 2.3 plan-diff shows >1 unrelated property change** that the
  operator cannot reconcile via config edits (e.g. provider rejects
  `actor_id = 0` AND `actor_id = 1` AND `actor_id = null` for
  OrganizationAdmin). Action: add
  `lifecycle.ignore_changes = [bypass_actors]` as the documented
  escape hatch (mirrors ADR-031's `ignore_changes` posture on imported
  Sentry rules); document the diff for next provider upgrade.
- **A required-check entry produces a permanent-pending merge gate**
  (the job is not running on the PR for any reason). Action: remove
  the entry from `ruleset-ci-required.tf`, file a follow-up to
  investigate why the job didn't fire, re-add once root-caused.

## Validation gate

This ADR is validated by:

- **AC3:** `grep -c '^      required_check {' infra/github/ruleset-ci-required.tf` → `14`.
- **AC4 / AC5:** every new `context` string appears as a literal job
  `name:` field in `.github/workflows/{secret-scan,ci,pr-quality-guards}.yml`.
- **AC6 / AC7:** `terraform validate` passes for `infra/github/` under
  the extended `infra-validation.yml` matrix.
- **AC15 (post-merge):** `terraform plan` shows exactly the 9-addition
  diff (`before_count: 5, after_count: 14, actions: ["update"]`) with
  no other changes.
- **AC16 (post-apply):**
  `gh api repos/jikig-ai/soleur/rulesets/14145388 | jq '.rules[0].parameters.required_status_checks | length'`
  returns `14`.

## DHH dissent (kept for re-evaluation)

A DHH-style review would argue that one UI-only ruleset with 5 entries
on a solo-operator repo is not worth a 7-file Terraform root + 30-line
ADR. The decision rejected this because (a) the documented merge-through
failure (#3886) is itself the evidence that UI-only management produces
silent-policy-drift, (b) the deferred Tier-3 expansions (smoke rollup,
Block-family rollup, docs/perf gates) are roadmap-blocked behind an IaC
substrate, and (c) the cost is one-time scaffolding amortized across
every future widening. **Re-evaluate trigger:** if no Tier-3 widening
lands within 90 days AND no further merge-through events occur, the
dissent becomes the operative reframe and `infra/github/` can be
collapsed back to UI management with a `status: rejected` post-script
here.
