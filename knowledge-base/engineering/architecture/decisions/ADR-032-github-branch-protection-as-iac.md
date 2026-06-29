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

**Revised 2026-05-25 (PR #4384):** migrated from PAT auth to App-installation
auth per `hr-github-app-auth-not-pat`. The current model uses the `soleur-ai`
App (id `3261325`, installation `122213433`) — see §"Required-check
inventory" below and `infra/github/main.tf`.

The original PAT framing (kept for audit):

> Fine-grained PAT named `terraform-infra-github-rulesets`, scoped to the
> single repo `jikig-ai/soleur` with `Administration: Read+Write` only.
> Was stored in Doppler `prd_terraform/GH_RULESET_PAT` (NOT `GITHUB_TOKEN` —
> that name collides with the magic variable Actions populates). At apply
> time, `doppler run --name-transformer tf-var --` rewrote the env to
> `TF_VAR_gh_token`, which the provider consumed via the sensitive
> `gh_token` variable. The provider marked `token` sensitive, so the value
> never landed in state plaintext.

### Apply discipline

**Revised 2026-05-16 (PR #3903):** the original "operator-only" framing
below is superseded. Apply now runs automatically in CI on merge to
`main` via [`.github/workflows/apply-github-infra.yml`](../../../../.github/workflows/apply-github-infra.yml),
matching the boundary ADR-031 drew for `apps/web-platform/infra/sentry/`.
**The PR merge is the human attestation** per `hr-menu-option-ack-not-prod-write-auth`
— same satisfaction the rule accepts for Sentry cron-monitor terraform.
The original framing was a `/ship` Phase 7 misclassification
(`manual_because: oauth-consent-screen` conflated the one-time PAT mint
with the per-apply attestation); the systemic fix is tracked in #3910.

This revision tightens the "mirrors ADR-031" framing in two ways the
PR #3903 body must NOT overstate:

1. ADR-031 scopes the Sentry auto-apply to `-target=sentry_cron_monitor.*`
   because that root manages BOTH cron-monitors (auto-applied) AND
   issue-alerts (import-only). `infra/github/` manages a single resource
   (`github_repository_ruleset.ci_required`) so the apply step does not
   need `-target` scoping — the full-root apply is the scoped apply by
   construction. Future additions to this root require revisiting the
   scoping decision.
2. ADR-031's apply ran from day one. ADR-032 originally rejected
   auto-apply, then this revision reverses that. The reversal is
   contained to this root and does NOT loosen the boundary anywhere
   else; `hr-menu-option-ack-not-prod-write-auth` continues to require
   single human attestation for any production-write that lacks a
   reviewed-PR-merge equivalent (e.g., DNS rotation, secret rotation,
   manual server restarts).

Defense-in-depth: CODEOWNERS pins `/infra/github/` and
`/.github/workflows/apply-github-infra.yml` to `@deruelle` so a leaked
`DOPPLER_TOKEN` alone is insufficient to push a ruleset change — the
malicious PR must first land a CODEOWNER-approved review.

The mandatory pre-apply gate (the `terraform show -json | jq` probe
asserting ALL THREE contract dimensions: actions, before_count,
after_count) is preserved — it now runs in CI as the destroy-guard step
inside the apply workflow, gated by `[ack-destroy]` in the merge commit
message for any plan with deletes. The probe shape is unchanged:

```text
{"actions":["update"],"before_count":5,"after_count":14}
```

`before_count` and `actions` are load-bearing because an `after_count`
of 14 alone passes for any 14-element collection, including one produced
by an unexpected `replace` instead of `update`. Any deviation (a
bypass-actor diff, condition tweak, integration_id phantom drift)
signals that the import surfaced unmanaged state the Terraform config
does not yet model — the workflow fails closed and an operator
reconciles by editing the config to match live state BEFORE applying,
never by applying the unreviewed diff.

**Kill switch:** include `[skip-github-apply]` on its own line in the
merge commit message to bypass the auto-apply for that merge.

#### Original framing (superseded — preserved for audit)

> Apply is operator-only. The auto-apply patterns in
> `apply-deploy-pipeline-fix.yml` and `apply-sentry-infra.yml` (which
> run `terraform apply -target=…` on push-to-main) do NOT apply here
> because the ruleset mutation is a write-to-prod-policy event
> requiring single human attestation per
> `hr-menu-option-ack-not-prod-write-auth`.

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

- **Job-name fragility.** The 16 `context` strings in
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
  **Superseded 2026-05-25 (PR #4384):** the PAT auth model was migrated
  to `app_auth` (`soleur-ai` App id `3261325`, installation `122213433`)
  per active `hr-github-app-auth-not-pat`. App credentials do not rotate
  operator-side — the rotation-cadence negative is closed. Re-introducing
  any `var.gh_token`-shape PAT variable is a regression.

### Required-check inventory (Tier 3 — added 2026-05-25 via PR #4384)

| Tier | Context | Workflow | jobs.\<name\> | integration_id |
| --- | --- | --- | --- | --- |
| 3 | `enforce` | `.github/workflows/legal-doc-cross-document-gate.yml` | `enforce` | 15368 (Actions) |

The `enforce` job posts on every PR (the `paths:` trigger filter was
removed in PR #4384 atomically with the required-status promotion); the
existing `surface_hit=false` short-circuit in the job body keeps non-DSAR
PRs at O(seconds). Bot PRs created via `GITHUB_TOKEN` (no workflow
re-trigger) carry the required `enforce` check via the
`bot-pr-with-synthetic-checks` composite action's `CHECK_NAMES` array
AND the two inline-synthetic workflows (`scheduled-content-publisher.yml`,
`scheduled-compound-promote.yml`); `scripts/lint-bot-synthetic-completeness.sh`
fails closed if a future inline-synthetic workflow omits `enforce`.

## Escape hatches

If any of the following triggers fire, revert the import + apply:

- **`terraform import` returns a non-transient schema-shape error not
  enumerated in `2026-03-19-github-ruleset-stale-bypass-actors.md` or
  provider issues #2317 / #2467 / #2504 / #2536 / #2952.** Transient
  failures (network, 502, rate-limit) do not trigger this hatch — retry
  with backoff. Action: keep the UI as source-of-truth, mark this ADR
  `status: rejected`, revert `infra/github/` and the
  `infra-validation.yml` extension.
- **Phase 2.3 plan-diff surfaces `bypass_actors` churn the operator
  cannot suppress.** Concretely: the operator has tried
  `actor_id = 0`, then `actor_id = 1`, then `actor_id = null` for the
  OrganizationAdmin block (in that order), and the plan still shows a
  non-empty diff on that block. Action: add
  `lifecycle.ignore_changes = [bypass_actors]` as the documented escape
  hatch (mirrors ADR-031's `ignore_changes` posture on imported Sentry
  rules); document the diff for the next provider upgrade.
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

## Sharp Edges (added 2026-05-25 via PR #4384)

1. **Job-rename without paired Terraform edit silently un-requires the
   gate.** The `enforce` `context` string in `infra/github/ruleset-ci-required.tf`
   is the LITERAL `jobs.enforce:` job name at
   `.github/workflows/legal-doc-cross-document-gate.yml:36`, NOT the
   workflow display name (`Legal-doc cross-document gate`). A future
   rename of `jobs.enforce:` MUST include a paired Terraform edit in
   the SAME PR; same contract as the Tier-1 / Tier-2 entries documented
   in §Negative — Job-name fragility.
2. **PAT-auth supersession (`hr-github-app-auth-not-pat`).**
   `infra/github/main.tf` migrated from PAT auth (the eliminated
   `var.gh_token`) to `app_auth` in PR #4384 per the active hard rule.
   Re-introducing any `var.gh_token`-shape variable in any future PR is
   a regression. Sibling `apps/web-platform/infra/main.tf:72-79` is the
   reference pattern. The corresponding workflow change
   (`.github/workflows/apply-github-infra.yml` fetches `GITHUB_APP_ID +
   GITHUB_APP_PRIVATE_KEY` from Doppler `prd_terraform`, not the
   deprecated `GH_RULESET_PAT`) MUST stay aligned with the provider
   block — drift means apply-time `401 Unauthorized`.

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

## Amendment — 2026-06-29 (#5585): 15 → 16, first path-filtered required check

`required_status_checks` widened 15 → 16 by adding
`tenant-integration-required`. Count history: PR #3886 imported 5 → 14;
PR #4385 added `enforce` (→ 15) without updating the "14" wording in this
ADR's body or the `.tf` header (a pre-existing off-by-one — the live ruleset
and `.tf` both held 15 before #5585); #5585 makes it 16. The current-state grep
(`grep -c '^      required_check {' infra/github/ruleset-ci-required.tf`)
now returns `16`. The import-time figures recorded above (`before_count: 5,
after_count: 14`) are the historical PR #3886 adoption diff and are left
unchanged as that record.

**New pattern — always-run aggregator gate job for a path-filtered required
check.** The prior 14 checks all run unconditionally on every PR. The
dev-Supabase tenant-isolation suite (`.github/workflows/tenant-integration.yml`)
is path-filtered (it must not burn dev-Supabase rate budget on the ~95% of PRs
that don't touch the isolation surface), so it cannot be made required directly:
GitHub never reports a status context for a workflow filtered out by `on.paths`,
leaving a required check "Expected — Waiting" forever and blocking unrelated PRs.

The pattern that resolves this (mirrors `ci.yml`'s `detect-changes` + `test`
aggregator): the workflow always triggers (no `on.paths`); a cheap
`detect-changes` job decides whether the heavy suite runs; the heavy job is
gated `if: needs.detect-changes.outputs.tenant == 'true'`; and an always-run
`tenant-integration-required` job (`if: always()`) is the registered required
context. Its verdict is **fail-closed** — it passes only when
`detect-changes` succeeded AND the suite is `success` or `skipped`, so a
`detect-changes` failure (which marks the heavy job `skipped`) does NOT green
the gate. The verdict lives in `scripts/tenant-integration-gate-verdict.sh`
(unit-tested, five branches). `tenant-integration-required` is thus the first
**conditionally-skipped-but-required** check; the job-name contract (Negative
consequence above) applies — renaming the gate job silently un-requires it.

Bot/cron PRs (GITHUB_TOKEN, no CI trigger) satisfy it via the synthetic
check-run in `.github/actions/bot-pr-with-synthetic-checks/action.yml`
(`CHECK_NAMES`) and the `scripts/required-checks.txt` SSOT, identical to the
other integration_id-15368 checks.

**Anchor-surface coverage (the sharp edge of a path-filtered REQUIRED check).**
Once a path-filtered check is REQUIRED, a GREEN result is an *authoritative
certification* — "isolation verified" — not a silent skip. Its `detect-changes`
anchors must therefore cover the **surface the suite actually verifies**, not
merely the cheap-trigger `on.paths` it inherited. #5585 review (user-impact P1)
caught that the suite imports `@/lib/supabase/tenant` and exercises the
RLS-bypassing service-role client, yet `lib/supabase/`, `middleware.ts`, and the
shared `test/helpers/` fixtures were unanchored — a regression there would have
skipped to an authoritative GREEN. The anchors were widened to the isolation
surface (plus the extracted verdict script, anti-bypass) before merge.

Two boundaries are **deliberately left unanchored** and accepted:
- `app/api/**/route.ts` — anchoring all routes would run the heavy dev-Supabase
  suite on the majority of PRs, defeating the rate-budget purpose that is the
  entire reason for the shim. Route-level isolation relies on the now-anchored
  `lib/supabase/` clients + DB RLS policies (migrations, anchored).
- Bot/GITHUB_TOKEN PRs satisfy the check via a blind synthetic GREEN (suite never
  runs) — the standard repo-wide posture for all 16 checks. Accepted because the
  synthetic-posting bot workflows touch docs/metrics, not the isolation surface.

General rule for future path-filtered required checks: **the anchor set is part
of the security contract, not just a cost optimization** — audit it against the
verified surface, and document every accepted gap.
