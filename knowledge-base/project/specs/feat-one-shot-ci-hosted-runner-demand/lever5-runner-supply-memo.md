---
title: "Lever 5 options memo: CI runner supply (decision memo, nothing provisioned)"
date: 2026-10-07
issue: 9721
reviewed_by: soleur:engineering:cto
status: memo
---

# Lever 5: CI runner supply options

Scope: a short options memo routed through the CTO agent. It recommends an order and the conditions
for any supply change. **It provisions nothing and decides nothing**; ADR-276 Decision 1 and 8 record
the demand-first rule and the supply gate, and a supply change needs its own ADR.

## Verified facts

- Org `jikig-ai` is on the Team plan (`gh api orgs/jikig-ai --jq .plan.name` returns `team`); the
  repository is public; `gh api repos/jikig-ai/soleur/actions/runners` returns `total_count` 0.
- GitHub documents standard hosted-runner concurrency as Team 60 and Enterprise 500; larger runners
  are a separate pool at 1000 on Team (docs.github.com `actions/reference/limits`, fetched 2026-10-07).
- Live fork-PR approval policy (`gh api repos/jikig-ai/soleur/actions/permissions/fork-pr-contributor-approval`,
  read 2026-10-07): `first_time_contributors`. The strict value is `all_external_contributors` (public OpenAPI schema `actions-fork-pr-contributor-approval`, enum: `first_time_contributors_new_to_github`, `first_time_contributors`, `all_external_contributors`).
- Pricing (docs.github.com `billing/reference/actions-runner-pricing`, fetched 2026-10-07): standard
  Linux 2-core $0.006 per minute and free on public repositories; larger runners are not free on
  public repositories: Linux 2-core Advanced $0.006, 4-core $0.012, 8-core $0.022 per minute.
- The ledger (`knowledge-base/operations/expenses.md`) holds `GitHub Team (jikig-ai, 1 seat)` at
  $4 per month, upgraded 2026-09-22, and no Enterprise price. Hetzner server prices already in the
  ledger: CX33 (4 shared vCPU, 8 GB) 9.17 USD per month, CPX22 (2 vCPU, 4 GB) 21.05.
- Measured demand, window 2026-10-07 13:04Z to 19:04Z, runner-bound jobs only: 7,456 runner
  job-minutes; mean 21.4, p90 57 and peak 60 concurrent jobs; 22% of the window's minutes at 55+
  concurrent (at the 60-job cap itself a re-run found 0.6%, and 12.5% at 58 or more; the cap is account-wide, see ADR-276 Context). The `test-scripts` family is 45% of all job-minutes (3,368 across PR, merge_group and
  push runs). Re-measure with the Stage 1 census before any spend; one working-day window is not a
  month.

## Options, in the CTO's recommended order

Labels are S-A to S-D (supply options) so they cannot be confused with ADR-276's local Options A to D:
ADR-276's chosen Option C corresponds to S-D here, and its Option A spans S-A to S-C.

| Rank | Option | Cost model (assumptions stated) | Main risk |
|---|---|---|---|
| 1 | S-D. Demand levers only (stages 1 to 4 of the plan) | $0 new spend | Failures surface later; carried by kill-switches and an escape metric |
| 2 | S-C. Plan upgrade to Enterprise (500 concurrent) | **Unknown.** The ledger holds only the Team row; a quote, seat minimum and term are needed. Seats are 1 today, so a per-seat price could be the cheapest supply lever. | A sales minimum or term could erase the advantage; standard runners stay free on public repos, so no per-minute cost |
| 3 | S-B. Larger runners, hybrid only (separate 1000-job pool) | Per 1,000 baseline job-minutes: 2-core $6, 4-core $12, 8-core $22 with no speedup; about $6 if 4-core runs the work 2x faster (linear speedup is an assumption to measure). For the measured window, moving only `test-scripts` (3,368 min) to 4-core is about $40 with no speedup. Cancelled minutes bill too. | Moves a free resource to a metered one; "larger" may not mean more cores below 8-core (probe `nproc` on a free runner first); needs a spend cap and a repo variable that flips `runs-on` back |
| 4 | S-A. Ephemeral self-hosted runners on Hetzner | Hourly-billed hosts at ledger prices: a CX33 is about $0.0126 per hour; an always-on pool at the measured mean (21.4 hosts) is about $196 per month, a pool at the 60-host peak about $550 (indicative only: they extrapolate a one-day, 6h mean to a month, and a pool at the mean cannot absorb the p90 or the peak; any headroom above the mean scales the first figure linearly), excluding engineering time and the autoscaler. Ephemeral per-job hosts cost less at idle. Hourly rounding is unverified. | See the security conditions; server quota is unmeasured and the ledger records slot and stock failures; an autoscaler is a new service needing Sentry and Better Stack coverage |

## Security conditions for any self-hosted path (all required)

1. Ephemeral and JIT only (`generate-jitconfig`): one job per host, destroyed after the job, no
   persistent runner token or registration PAT on the host.
2. Registration through a dedicated minimal GitHub App with only the org "Self-hosted runners: write"
   permission (rule `hr-github-app-auth-not-pat`), not the `soleur-ai` App. The key lives in the
   Doppler Tier-B config (ADR-241), main-only.
3. A runner group restricted to this repository with an explicit workflow list, managed in
   `infra/github` as code; confirm workflow restriction is available on the Team plan first. Record
   "Allow public repositories" on that group as a deliberate risk acceptance; JIT config names the
   group id (never the Default group); the workflow restriction pins refs, and whether it accepts the
   `refs/pull/N/merge` and `gh-readonly-queue/main/...` shapes is unverified; the org "Self-hosted
   runners: write" permission can register a runner into any group, so the restriction guards
   consumption, not registration, and the autoscaler holding that App key never shares a host with
   runners. The org runner-groups API needs `admin:org`, so group state is unverified here.
4. Routing is derived from each workflow's triggers, not from a named list: a workflow may use
   self-hosted only if its `on:` is a subset of {`merge_group`, `push` limited to `main`, `schedule`,
   `workflow_dispatch`}. The boundary is the runner-group workflow restriction pinned to
   `refs/heads/main` (condition 3), which also stops a `workflow_dispatch` run from a non-default ref;
   a test that fails any self-hosted `runs-on` in a workflow with another trigger is hygiene, not the
   boundary, because a PR can edit both the workflow and the test. The test also covers
   `workflow_call` workflows (`reusable-release.yml` today), whose `runs-on` follows the caller's
   trigger, and requires every `push` trigger to be limited to `main` (all 25 current ones are).
   Counts on this tree come from a YAML-aware parse of the `on:` keys of `.github/workflows/*.yml`
   (`python3 -I` with PyYAML; a bare `on` key parses as boolean True): `pull_request_target` 3
   (`cla.yml`, `cla-evidence.yml`, `dev-ledger-reconcile.yml`), `issues` 4 (`auto-label-security.yml`,
   `board-status-sync.yml`, `follow-through-closure-guard.yml`,
   `inngest-watchdog-restart-dispatch.yml`), `issue_comment` 2 and `workflow_run` 4. Anyone on GitHub
   can fire the `issue_comment` workflows and `auto-label-security.yml` (opened or edited issues);
   the other `issues` triggers need triage or write access and `workflow_run` follows main-branch
   workflows. Fork PRs never route to self-hosted. The fork-PR approval policy is currently
   `first_time_contributors` and must be set to `all_external_contributors`, verified through the
   API, before any routing change.
5. A separate Hetzner project and token, no attachment to the prod private network, egress deny to
   prod hosts, the metadata endpoint and git-data; runner hosts hold no Doppler token and no prod
   credentials.
6. Runners are replaced, never patched (`hr-prod-host-config-change-immutable-redeploy`); no SSH
   runbooks (`hr-no-ssh-fallback-in-runbooks`); diagnosis comes from Sentry or Better Stack.
7. A repository variable flips `runs-on` back to `ubuntu-latest`; an offline pool must never stall a
   required merge-queue context.

`merge_group` and `push` are not "trusted refs": they carry unreviewed PR content, auto-merge is on and
no required-review rule exists, so self-hosted there is code execution by whoever can get a PR green.
The control is secret-free, network-isolated, single-use hosts.

Migration order if ever adopted: `merge_group` and `push` main only, secret-free jobs only; never the
release or deploy jobs, secret-bearing jobs, `pull_request_target` or fork PRs; label-gated internal
PRs only after a clean soak. Agent-authored PRs execute on the runner, so the user-impact reviewer
runs on any plan for option S-A (brand-survival threshold `single-user incident` if a secret leaks).

## IaC routing

New root such as `apps/ci-runners/infra` (state isolation and a separate hcloud token so a runner
compromise cannot reach the prod hcloud plan credential) with the R2 backend, key
`ci-runners/terraform.tfstate` (`hr-every-new-terraform-root-must-include-an`), no operator-mint
variable defaults (`hr-tf-variable-no-operator-mint-default`), registered in the infra-validation
suites; the runner group and workflow allowlist live in the existing `infra/github` root;
fresh-host bootstrap reachable from `terraform apply`
(`hr-fresh-host-provisioning-reachable-from-terraform-apply`). Creating the Hetzner project and its
token has no API: a single bootstrap step, planned as such. Ledger rows go through ops-advisor first.

## To measure before deciding

30-day queue-wait distribution per job family and the share of wall time at 55+ running; whether
merge-queue entries time out or only run slowly; job-minutes by family over 30 days; cancelled-minute
share per event; fan-out per merged PR after stages 1 to 4 land; `nproc` and runtime scaling on one
shard; Hetzner quota and stock by datacenter; the Enterprise quote with seat minimum and term.

## Decision statement carried into ADR-276

CI runner supply is raised only after demand levers are exhausted. Self-hosted runners are not adopted
for a public repository unless they are ephemeral, JIT-registered through a dedicated minimal GitHub
App, restricted to one runner group and an explicit workflow list, and confined to secret-free jobs on
post-gate but unreviewed refs (`merge_group`, `push`), with a repository-variable fallback to GitHub-hosted. Larger runners are a metered,
flippable hybrid for the heaviest job families only.

## CTO blocking concerns (recorded)

Public-repo code execution on owned hardware plus agent-authored PRs (hard gate on the conditions
above); unverified Hetzner quota and stock; an autoscaler is a new service with an owner and an
observability duty; a required context must never go missing when a runner label changes; runner
image drift from `ubuntu-latest` (Playwright, docker toolchains); Enterprise price unknown; larger
runner spend needs a cap and an alert.
