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
  `gh api repos/jikig-ai/soleur/rulesets/14145388 | jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks | length'`
  returned `14` at PR #3886 adoption (now `16`; the #5780 `merge_queue` sibling
  makes positional `.rules[0]` unsafe — select-by-type is required, matching the
  apply-verify probe).

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

## Amendment — 2026-06-30 (#5780): adopt a GitHub merge queue for `main`

**Status of this sub-decision: adopting** (flip to `accepted` once the
post-enablement canary below passes). The parent ADR remains `accepted`.

> **2026-07-01 incident + correction (read first).** The first enablement
> (PR #5800) DEADLOCKED `main`: the merge queue requires the `CodeQL` status
> context (GHAS, integration_id 57789), but GitHub CodeQL **default setup does
> not run on `merge_group`** (only `push`/`pull_request`), so every queue entry
> stalled `AWAITING_CHECKS` on a CodeQL result that never posted. All 15 OTHER
> required contexts DID report on the temp ref — PR-1's wiring was correct; the
> sole gap was CodeQL-on-`merge_group`. Reverted via the kill-switch (remove the
> `merge_queue` rule) within ~14 min. The parenthetical "(CodeQL is
> default-setup)" in this amendment's original Phase-2 text was the load-bearing
> wrong assumption — default setup is **structurally incompatible** with a
> required-`CodeQL` merge queue.
>
> **Root cause is a GitHub platform limitation, NOT our config (corrected
> 2026-07-01 after investigation).** The real blocker is
> [`github/codeql-action#1537`](https://github.com/github/codeql-action/issues/1537)
> — *"GitHub merge queue builds don't report CodeQL status"* — **open since Feb
> 2023, last updated 2026-05-22, no ETA** (GitHub code-scanning maintainer,
> on-thread). CodeQL runs its analysis on `merge_group` but does **not** report
> the code-scanning **status context** on the temp ref. This is true for BOTH
> default AND advanced setup — so the earlier "migrate to advanced setup with
> `on: merge_group`" idea does **not** fix it (the analysis runs; the required
> `CodeQL` *status* still never posts). The most-endorsed comment on #1537 (15
> 👍): *"there is no way to select different required checks for the branch
> protection rules and those required by the merge queue"* — a ruleset's required
> checks apply to both direct-merge and the queue, so CodeQL cannot be
> required-for-PRs-but-exempt-in-queue. Every known workaround disables CodeQL
> for merge groups entirely.
>
> **Decision (2026-07-01): queue stays OFF; CodeQL stays a blocking required
> check.** The choice is binary and unavoidable:
> - **CodeQL required (blocks merge) ⇒ no merge queue** ← chosen. The BEHIND-race
>   starvation #5780 targeted is already mitigated by `/ship`'s auto-sync loop
>   (both PR #5800 and the kill-switch PR #5811 merged cleanly through it).
> - **Merge queue ⇒ CodeQL must be dropped from the ruleset's required checks**
>   (advisory only — still runs + raises code-scanning alerts, but no longer
>   blocks a merge). Rejected: trading a blocking SAST gate for marginally
>   smoother merges over the working auto-sync loop is a bad trade.
>
> An advanced-setup `codeql.yml` was prototyped in PR #5811 and removed in #5812
> (it also auto-disabled default setup, leaving main with no CodeQL producer —
> re-enabled default setup to recover). **Do NOT restore it as a "fix" — it does
> not solve #1537.** The ONLY correct re-adoption triggers are: (a) GitHub
> resolves `codeql-action#1537` (native merge-queue CodeQL status), OR (b) a
> deliberate decision to make CodeQL advisory (remove it from
> `required_status_checks`, then re-add the `merge_queue` rule — no CodeQL setup
> migration needed).
>
> **PR-1 observability workflows were removed after the revert (restore on
> re-adoption).** `merge-queue-stall-check.yml` and `merge-queue-cla-synthetics.yml`
> were deleted as dead weight once the queue was off (the stall probe polled a
> null queue every 30 min; the CLA synthetics only fire on `merge_group`, which
> never occurs without a live queue). They are preserved in git history and are
> part of the re-adoption checklist below — the forward-looking mentions of them
> in this amendment's Observability / canary sections describe that
> to-be-restored target state, not currently-live workflows. The standing
> `codeql-1537-revisit-watch.yml` (added post-revert) is the live watcher that
> pings issue #5840 when `codeql-action#1537` closes. PIR:
> `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`.
> Generalized lesson: a plan recovered from disk after a subagent crash carries
> its "verify X before shipping" Phase-0 gates as UNVERIFIED claims — re-run the
> empirical probes, do not inherit them as done. Second lesson: verify a vendor
> capability against its own issue tracker (#1537) before designing a fix around
> it (`hr-verify-repo-capability-claim-before-assert`).

### Decision

Adopt a **GitHub merge queue** for `main`, modeled in this same IaC root via the
`integrations/github` provider's `merge_queue` rule block (a second rule sibling
to `required_status_checks` inside `github_repository_ruleset.ci_required`). The
block is supported on the locked provider **6.12.1** (schema re-probed at /work;
all 7 fields present), so the queue is declarative IaC — no provider bump, no
UI-only drift, no violation of `hr-all-infrastructure-provisioning-servers`.

**Problem it solves.** The `CI Required` ruleset sets
`strict_required_status_checks_policy = true` — a PR must be up-to-date with
`main` before it can merge. On an active day `main` merges faster than a
web-platform PR's CI converges (~8 min for the heavy jobs), so the PR is flipped
`BEHIND`, CI restarts, and it can never converge by manual `update-branch`.
Admin-merge (`gh pr merge --admin`) was the escape hatch but it *bypasses* the
very up-to-date guarantee the strict policy exists to provide. The queue
serializes merges and builds each candidate against the projected post-merge
state, so "up-to-date" is satisfied **by construction** — keeping the
strict-policy intent while removing the starvation and the need for routine
admin-merge.

### Chosen params + rationale

Set only the value-bearing decisions in `merge_queue {}`; leave
`max_entries_to_build` and `min_entries_to_merge_wait_minutes` at provider
default (inert at `max/min_entries_to_merge = 1`):

| Param | Value | Why |
| --- | --- | --- |
| `merge_method` | `SQUASH` | Matches the repo's existing `gh pr merge --squash`. |
| `grouping_strategy` | `ALLGREEN` | Safe default; per-candidate bisection benefit is mostly latent at merge-one-at-a-time volume but costs nothing. |
| `max_entries_to_merge` | `1` | Merge one candidate at a time (the no-batching decision for a bursty, low-volume repo). |
| `min_entries_to_merge` | `1` | Merge as soon as a single candidate is green (low latency). |
| `check_response_timeout_minutes` | `15` | **The one value that genuinely matters.** An under-set timeout *dequeues a green PR*, re-introducing the starvation we are fixing. 15 is a starting point premised on the ~8-min critical path; the `merge_group` build runs the FULL required suite, so re-derive from the observed slowest-required-check p95 (target `timeout >= 1.5x slowest`). |

### The hard precondition — `merge_group` wiring (PR-1, #5784)

The real work was not the Terraform block — it was the **`merge_group` wiring**,
landed in the sequenced predecessor PR-1 (#5784). A merge queue dispatches a
`merge_group` event against a temporary `gh-readonly-queue/main/*` ref. A
required check whose workflow never fires on `merge_group` leaves the queue entry
**permanently pending → the queue stalls forever** (the merge-queue analogue of
the `[skip ci]` / path-filter deadlock). PR-1 added `merge_group:` to all 7
producer workflows; the 8th producer, CodeQL, cannot report a `merge_group`
status at all **(the deadlock cause — see the 2026-07-01 incident note above;
`codeql-action#1537`)**. This is NOT fixable by switching CodeQL to advanced
setup — the code-scanning *status* is unreported on `merge_group` regardless of
setup mode, so the required `CodeQL` context can never post on a queue temp ref.
The queue is therefore incompatible with a required CodeQL check until GitHub
resolves #1537. PR-1 also fixed
the apply-verify `rules[0]` → `select(.type==…)` fragility, and added the
observability + CLA-synthetic workflows.

**Two-PR sequencing is load-bearing:** PR-1 (triggers + verify fix) merged
**first** (2026-06-30); PR-2 (this `merge_queue` block) merges **second** and
enables the queue. `merge_group` only ever fires *after* the queue is live on
`main`, so enabling and verifying cannot happen in the same merge.

### Generalized contract clause

ADR-032's existing "verify runs-on-every-PR before requiring a check" clause
(the §Negative / §Decision contract) **generalizes to "verify
runs-on-every-`merge_group` before relying on the queue."** A required context
that does not report on the queue's temp ref is the new permanent-pending
failure mode. This clause is the merge-queue analogue of the original
permanent-pending-gate risk and must be honored by any future required-check
addition.

### New failure mode + observability

- **Permanent-pending queue stall** (a required check missing `merge_group`):
  detected by the standing `merge-queue-stall-check.yml` probe (PR-1) — a
  GH-Actions cron (~30 min) that queries `mergeQueue.entries`, computes
  `now - enqueuedAt`, and files a `merge-queue-stall` issue on any entry past
  `check_response_timeout_minutes + buffer`. This is the active liveness signal,
  not operator-eyeballing.
- **`merge_queue` rule drift** (block removed/mangled outside Terraform — the
  provider has 6.x nested-block history): detected by `scheduled-terraform-drift.yml`'s
  `infra/github` matrix entry (added in PR-2, CTO B-2). `terraform plan` here
  also catches a *silently-disabled* queue (rule removed → no entries → the
  stall probe is blind, so it cannot see this case on its own).
- **Bot-PR synthetics** (CLA contexts can't run on `merge_group`): re-posted on
  the temp ref by `merge-queue-cla-synthetics.yml` (PR-1). **Trust model:** the
  synthetic is sound because (1) the queue *entry* gate already required the real
  CLA contexts green on the PR head before admission, and (2) the legal evidence
  record is written to R2 Object Lock at CLA *sign* time, not merge-group time —
  so the synthetic is a CI-gate signal on a throwaway ref, never a substitute for
  the evidence. `main` is gated by TWO rulesets (CI Required + CLA Required).

### Kill switch + DR / clobber notes

- **Kill switch:** remove the `merge_queue` block from `ruleset-ci-required.tf`
  and re-apply — reverts to pre-queue behavior. This is `0 destroy` (a rule-block
  removal, not a `required_check` removal), so the destroy-guard does NOT flag it
  — intended: the kill-switch must not be `[ack-destroy]`-gated.
- **Destroy-guard:** adding the `merge_queue` block is also `0 destroy` (no
  `required_check` removed); PR-2's first plan is `0 to add, 1 to change,
  0 to destroy` (in-place ruleset update). No regression fixture is added — the
  existing filter is provably safe for a rule *addition*.
- **DR-restore clobber (P1-3):** `scripts/create-ci-required-ruleset.sh` (the
  documented from-scratch restore path) now restores the `merge_queue` rule too,
  with a sync guard requiring its params to track the `.tf`. Omitting it would
  silently disable the queue after a from-scratch DR restore until the next TF
  apply.

### Admin-merge after the queue

A queue does **not** auto-remove admin bypass (`bypass_actors` is untouched;
admins can still `--admin` past the queue). Admin-merge is now the
**queue-bypass-of-last-resort**, not a routine workaround. Down-scoping
`bypass_actors` is out of scope for this PR and tracked as a possible follow-up.

### Vendor-tier note

GitHub merge queue requires Team/Enterprise for *private* repos (free on public
repos). `jikig-ai/soleur` is public, so the queue is available on the current
plan tier; the `terraform apply` enables it without a plan upgrade.

### Post-enablement canary (flip `adopting` → `accepted` when all pass)

These are post-merge verifications — the queue only fires `merge_group` after
the queue rule is re-applied:

- **Blocked by `codeql-action#1537` — this canary CANNOT pass while CodeQL is a
  required check.** CodeQL does not report a status context on `merge_group`
  (any setup mode), so a queued entry can never satisfy the required `CodeQL`
  check. Do not attempt re-enablement until EITHER GitHub resolves #1537, OR
  CodeQL is deliberately removed from `required_status_checks` (advisory mode).
  The remaining canary items below apply only after one of those preconditions
  holds.
- `apply-github-infra.yml` ran green on the re-enable merge; summary shows the
  required_status_checks count (16) via the `select(.type==…)` probe.
- Discoverability:
  `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[] | select(.type=="merge_queue")] | length'`
  → `1` (App-auth token; asserts the rule is APPLIED, not that the queue drains).
- **Canary human PR:** a trivial PR enters the queue (not direct-merge), all 18
  required contexts (16 CI Required + 2 CLA Required: `cla-check`, `cla-evidence`)
  report on the `merge_group` temp ref incl. `CodeQL`, and it merges without
  stalling.
- **Canary bot PR:** a `rule-metrics-aggregate.yml` bot PR flows through the
  queue without stalling (CLA synthetics cover its CLA contexts).
- **Stall probe live:** `merge-queue-stall-check.yml` has run ≥1 green cycle.
- **Ruleset drift:** `scheduled-terraform-drift.yml` `infra/github` plan is clean
  (`plan → apply → plan` shows no `merge_queue` drift).
