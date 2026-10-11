---
title: "fix: bot-opened weakness-digest PRs must get real CI runs and a merge-group report without a manual approval"
date: 2026-10-11
slug: bot-digest-pr-ci-runs-held-for-approval
type: fix
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
branch: feat-one-shot-bot-digest-pr-ci-runs-held-for-approval
issue: 9454
---

## Overview

The weekly weakness-miner workflow opens a digest PR as `github-actions[bot]` (the default workflow
token). On 2026-10-11 that PR's own workflow runs were created held and the queue entry never
received merge-group runs, so the entry sat awaiting checks until the queue removed it after about
62 minutes. This plan moves the PR author and auto-merge actor of that workflow onto a GitHub App
installation token, the identity under which other bot PRs in this repo already flow through the
queue, and adds a guard that keeps a future caller from reverting it.

## Research Insights

### Premise Validation (Phase 0.6)

Cited artifacts, each re-read on 2026-10-11:

- `#9454` is OPEN (merge-queue adoption tracker, ADR-270 `adopting`). Item 4 of its canary list is the
  weakness-miner bot PR. It must stay open; this plan uses `Ref #9454` only.
- `#10019` is CLOSED (auto-filed stall watchdog issue for PR 10013). It is linked as prose in the PR body and
  is not reopened or closed by this change.
- PR 10013 (`ci/weakness-digest-2026-10-11`, author `app/github-actions`) is MERGED at 18:42:32Z, as the
  brief says.
- `.github/workflows/weakness-miner.yml` and `.github/actions/bot-pr-with-synthetic-checks/action.yml` exist
  on `origin/main`. The composite has exactly one caller (`git grep "uses: ./.github/actions/bot-pr-with-synthetic-checks" -- .github` returns
  `weakness-miner.yml` only; `main-health-monitor.yml` and `merge-queue-cla-synthetics.yml` only cite it in comments).
- Audit of workflows that create PRs (per the required-check sharp edge): `git grep -ln "gh pr create\|create-pull-request" -- .github/workflows .github/actions` lists the composite (and its
  CHANGELOG), `cla-evidence-timestamp.yml`, `cleanup-unmerged-bot-branches.yml`, `fix-constraints-stage-b.yml` and `git-data-rung2-rehearsal.yml`; only the composite is in scope (see Phase 5).
- ADR corpus check for the mechanism (App-token PR authorship): ADR-232 section 3 already decides this
  for the inngest pin-bump PRs ("`GITHUB_TOKEN` cannot author the PR", amended by #9262 to the
  `soleur-infra` App). No ADR rejects it. ADR-232's rejected-alternatives text names a PAT, which is the
  only rejected identity here. ADR-270 is not touched.

### What the evidence shows (the lever is real, but the brief's causal story is half-right)

| Observation (command or record) | Result |
|---|---|
| `gh api repos/jikig-ai/soleur/actions/permissions` | `enabled: true`, `allowed_actions: all`; repo is PUBLIC |
| `.../actions/permissions/fork-pr-contributor-approval` | `approval_policy: first_time_contributors`. No setting distinguishes bot actors, and the least-strict value is a different tier of the same fork-contributor control, so no repo setting is a verified lever |
| `.../actions/permissions/fork-pr-workflows-private-repos` | HTTP 422 "not allowed for public repositories" |
| Runs on `ci/weakness-digest-2026-10-11` head `a55ddac1` | 7 `pull_request` runs created 12:10:35Z, actor `github-actions[bot]`, later `run_attempt 2` re-run by `deruelle` (the approval) |
| `merge_group` runs for `gh-readonly-queue/main/pr-10013-*` between 12:10 and 13:20 | **zero**, while five other queue groups (PRs 10002 and 9938 twice each, PR 9991 once) got 7 runs each in the same window |
| PR 10013 timeline | first `added_to_merge_queue` by `github-actions[bot]` 12:10:50Z, `removed_from_merge_queue` by `github-merge-queue[bot]` 13:12:19Z; second entry added by `deruelle` 18:11:52Z had 7 `merge_group` runs at 18:12:11Z and merged 18:42:32Z |
| Control A: PR 10027 (`soleur/inngest-pin-v1.1.50`, author `app/soleur-infra`, branch pushed and PR created and auto-merge armed and queue-entered all as `soleur-infra[bot]`) | 7 `pull_request` runs at PR creation, all executed (`CI` success); `merge_group` runs at 15:14Z; merged 15:33Z |
| Control B: PR 9982 (author `app/soleur-ai`, community-monitor) | same shape: real PR runs, `added_to_merge_queue` by `soleur-ai[bot]`, merged |
| Prior weakness digests (PRs 9479 and older) | merged about 1 minute after creation (pre-queue, synthetic checks satisfied the ruleset; runs failed with 0 jobs, unnoticed) |

Discriminating observation (plan-review): PR 10013's SECOND queue entry was added by `deruelle` while the PR author was still `github-actions[bot]`,
and it received `merge_group` runs. So the variable that flipped `merge_group` dispatch is the enqueuer (or the approved state of the PR runs), not the PR author alone.
The fix therefore moves the enqueuer, the PR creator and the pusher together, which is exactly Control A's configuration.

Two symptoms, one identity. The brief says the required `test` check "never existed". On the PR head it did exist
(the composite posts a synthetic `test`); what never existed was `test` on the **merge_group candidate**,
because the queue produced no `merge_group` runs for an entry that `github-actions[bot]` armed. The held
`pull_request` runs are a second, independent symptom of the same cause (events attributed to the
workflow token are not run as normal). The evidence cannot separate "held PR runs alone stalled it" from
"no merge_group dispatch alone stalled it", and the plan does not need to: Controls A and B show that a PR whose creator
and auto-merge actor is a GitHub App installation gets real PR runs and real merge_group runs. ADR-232 section 3 and the
existing `lint-bot-synthetic-completeness.sh` header already state the same fact ("App token triggers real CI").

### Property List (Phase 0.6b)

1. A weakness-digest PR's `pull_request` workflow runs start and finish without a human approving them.
2. Its merge-queue entry receives `merge_group` runs for every required context, so the entry cannot sit
   awaiting checks because of its author's identity.
3. A later edit that makes any caller of the bot-PR composite author PRs as the workflow token again turns a
   check red before merge.
4. The existing content-safety ceiling, the single-path allowlist, the off-main refusal and the CLA/synthetic
   chain keep working unchanged.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| Step that approves held runs via `POST /actions/runs/{id}/approve` using the workflow token | 1 only | **Cut.** It cannot buy 2 (no `merge_group` dispatch for a workflow-token entry), a workflow approving its own runs defeats the control, and the endpoint is documented for fork-contributor runs, so it is unverified for this case |
| Repo Actions setting change (fork-PR contributor approval policy) | none verified | **Cut.** The policy is already the stricter-than-minimum tier and is keyed on contributor status, not on bots; loosening it on a public repo widens the attack surface for every outside PR to fix one bot |
| Dropping the synthetic check-runs now that real CI runs | none of 1-4 | **Cut, tracked.** Synthetic posts are harmless duplicates (they are posted on `github.token`, which the ruleset's 15368 match requires); removing them touches the fabricated-green chain (ADR-139, parity test 8, `lint-bot-synthetic-completeness.sh`) and needs its own decision. Filed as a deferral issue (Phase 5) |
| A post-create probe step that polls for `action_required` runs and fails the workflow | 3 partly | **Cut.** The existing `merge-queue-stall-check.yml` watchdog already detects this class (it filed #10019 in 50 minutes); the guard below catches the regression before merge |
| Keeping the branch push on the checkout (workflow-token) credential | none | **Cut after plan-review.** Control A pushed, created and armed all as the App; the split-credential arrangement differs in one unmeasured variable and the job runs only weekly with no pre-merge exercise path (`infra-privileged` is main-only), so a wrong guess costs a week. The App-credential push is adopted (Proposed Solution 2), using the env-only extra-header pattern of `.github/scripts/bump-inngest-bootstrap-pin.sh` so the token is on no argv and not in `.git/config` |

### Relevant files (all verified present)

- `.github/workflows/weakness-miner.yml` (the only caller), `.github/actions/bot-pr-with-synthetic-checks/action.yml`
  and its `CHANGELOG.md`
- `.github/actions/mint-infra-app-token/action.yml` and its two precedent callers
  `.github/workflows/build-inngest-bootstrap-image.yml` (job `bump-cloud-init-pin`, mint step at the
  "Mint soleur-infra App token (contents+pull_requests write on soleur)" step) and
  `.github/workflows/mint-inngest-bootstrap-tag.yml` (job `mint`: `if: github.ref == 'refs/heads/main'`,
  `environment: infra-privileged`, `persist-credentials: false`)
- `tests/scripts/test-infra-privileged-tier-census.sh` (row G7f counts exactly three callers; "a fourth is a deliberate, dated edit here")
- `tests/scripts/test-weakness-miner.sh` (registered in `scripts/test-all.sh`; already pins `add-paths`)
- `plugins/soleur/test/required-checks-canonical-parity.test.sh`, `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (Group 4 consumer table)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (edge `github -> doppler`, "SINCE #9262 two unattended App-token consumers")

### Institutional learnings applied

- `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`: synthetic check-runs must be posted
  under the default `GITHUB_TOKEN` (integration 15368); an App token posts under a different id and silently fails the
  ruleset match. So `gh-token` stays `github.token` and only the PR-write identity moves.
- `2026-07-23-fabricated-green-unreachability-must-be-rederived-per-gate.md` and `ADR-139`: the digest path is inside
  the credential-path scanner's scope, so the earned-green block in the composite stays untouched.
- `2026-10-04-the-credential-switch-was-small-and-its-fixes-and-runbook-commands-were-the-defects.md`: prove mint
  behaviour from the rendered `app-token` notice annotation, not by grepping whole logs.
- `2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface.md`: App authors read as `<slug>[bot]` (GraphQL) and
  `app/<slug>` (REST). `cla.yml` already allowlists `soleur-infra[bot]` (line 62).
- `security-issues/git-trace-and-fork-pr-leak-bot-automation-20260919.md`: an `x-access-token` push remote leaks through `GIT_TRACE*`;
  the env-only extra header and the `GIT_TRACE*` unset are why the push does not use a token URL.

## Open Code-Review Overlap

Two open `code-review` issues cite files near the plan:

- #3593 (extract a child composite for posting synthetic checks) touches `.github/actions/bot-pr-with-synthetic-checks`.
  **Acknowledge.** Different concern (composite decomposition); this plan adds one input and per-command token wiring, and does not
  restructure the synthetic-post loop.
- #3595 (YAML-aware bot-workflow enumeration for audit/lint parity) names `scripts/audit-bot-codeql-coverage.sh`. **Acknowledge.**
  That script is not edited here; its consumer impact is handled by the deferral issue in Phase 5.

## Problem Statement

`weakness-miner.yml` calls the composite with `gh-token: ${{ github.token }}`. Everything the composite does as a PR actor
(`gh pr create`, label edit, `gh pr merge --auto`) is therefore attributed to `github-actions[bot]`. Before the merge queue that
only meant "no CI, synthetic checks cover it" (digest PRs merged in about a minute). With the queue (#9454) the PR needs real
`merge_group` runs, and the 2026-10-11 instance (PR 10013) shows an entry armed by the workflow token never received them, and its
own `pull_request` runs were created held. Each Sunday's digest is therefore expected to stall until a human intervenes
(one instance measured; recurrence is likely, not proven).

## Proposed Solution

Author the digest PR as the `soleur-infra` GitHub App, exactly as the inngest pin-bump already does (ADR-232 section 3): the App creates the PR, arms auto-merge, enters the queue
and pushes the branch (Control A's configuration). Keep only the synthetic check-run posts on the workflow token, because the ruleset's 15368 match requires that identity.

1. `weakness-miner.yml`: job `mine` gains `if: github.ref == 'refs/heads/main'`, `environment: infra-privileged` and a `timeout-minutes` raised above the sum of its step caps (today `5`;
   the added Doppler install and mint steps alone carry 2 minutes each, so use 12 and give the new steps their own `timeout-minutes`). The checkout step gains `persist-credentials: false`
   (as `mint-inngest-bootstrap-tag.yml` does) so no credential sits in `.git/config` while `scripts/weakness-miner.sh` runs. Steps in order: checkout, `Run weakness-miner`, install the Doppler CLI
   (reuse the pinned `DopplerHQ/cli-action` SHA of `mint-inngest-bootstrap-tag.yml`), mint a scoped installation token with `./.github/actions/mint-infra-app-token` (narrow shape: no
   `doppler-project`, `doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}`, installation `166065653`, permissions `{"contents":"write","pull_requests":"write"}`, repositories `soleur`),
   then the composite with `pr-token: ${{ steps.<mint-id>.outputs.token }}` and `gh-token: ${{ github.token }}`. No separate "token present" step: the mint composite already refuses an empty
   `doppler-token` with a routable `::error::`. Workflow `permissions:` become `contents: read` and `checks: write` (the App now pushes and writes PRs).
2. `bot-pr-with-synthetic-checks/action.yml`: new input `pr-token`. At the very top of the run step, BEFORE the "No changes to commit" early exit (so a misconfiguration is not hidden on an
   unchanged week), refuse an empty `pr-token` and a `pr-token` byte-equal to `gh-token`, with a fixed message naming this issue and never printing either value. `git push`, `gh pr create`,
   `gh pr edit --add-label` and `gh pr merge --squash --auto` run under the PR token: `gh` reads it as `GH_TOKEN="$PR_TOKEN"` per command; `git push` carries it as an
   `Authorization: basic` extra header in the per-command `GIT_CONFIG_COUNT/KEY_0/VALUE_0` environment (header built by `printf ... | base64` into an unexported shell variable, never on an
   argument list, `GIT_TRACE*` and `GIT_CURL_VERBOSE` unset), copied from `git_remote` in `.github/scripts/bump-inngest-bootstrap-pin.sh`. The `check-runs` POST loop keeps `gh-token`.
   Update the description's "PRs created with GITHUB_TOKEN don't re-trigger workflows" sentence. `CHANGELOG.md` gets a v4 entry (one line on migration: the single in-repo caller moves in the same change).
3. A static guard in the EXISTING `tests/scripts/test-weakness-miner.sh` (registered in `scripts/test-all.sh`, so it runs inside the required `test` aggregate): a new function that derives every
   workflow step calling the composite (floor of one) and asserts the identity wiring (Guard Contract below). One home, not two.
4. Governance and records the census and the C4 parity gate force: census row G7f caller count 3 to 4 (dated edit), runbook Group 4 row, C4 edge prose, ADR-232 amendment, ADR-241 amendment-log line.

No repo setting is required and no human click is needed: `DOPPLER_TOKEN_INFRA_APP` already exists on the `infra-privileged` environment (verified: environment secrets are
`DOPPLER_TOKEN_INFRA_APP`, `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN_WRITE`; branch policy `main` only), and the App installation already holds `contents:write` and
`pull_requests:write` (the pin-bump PRs created today prove it). The composite's only caller applies no labels, so the App's lack of `issues:write` is not exercised; a future caller passing
`labels` would hit it (Sharp Edges).

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "the required `test` check never existed" | `test` existed on the PR head (synthetic); it was absent on the `merge_group` candidate because no `merge_group` run was dispatched for the bot-armed entry. Held `pull_request` runs are a second symptom | Fix moves PR creator, pusher and auto-merge actor together; AC verifies both symptoms on the next real run |
| "repo Actions fork-PR/approval settings" may be a lever | Policy `first_time_contributors`, not bot-aware; the private-repo fork setting does not exist for public repos | No setting changes; recorded in the Cut List |
| "a step that approves held runs" | Cannot produce `merge_group` runs; self-approval defeats the gate | Cut |
| "open the digest PR under a GitHub App installation token" | Proven by controls A and B; precedent composite and census exist | Adopted |
| Brief implies one place to fix | The census hard-codes 3 composite callers; C4 prose says "two unattended App-token consumers" and describes their source; the runbook table lists Tier-B consumers | Phase 3 updates all of them, otherwise `test` goes red |

## Implementation Phases

### Phase 1 - Guard first (tests before the change)

1.1 Add `t_workflow_pr_identity` to `tests/scripts/test-weakness-miner.sh` and its small mutation battery against the CURRENT tree. It must be RED against today's `weakness-miner.yml`
    (`gh-token: ${{ github.token }}`, no `pr-token`, no environment). Parse YAML with `python3` + PyYAML as the census does; derive the caller population from `.github/workflows/*.yml`
    (override env var for the workflows directory, used by the battery); include one built-in positive control (a known-bad fixture must be RED, a known-good non-canonical fixture GREEN)
    before any verdict.
1.2 Keep the new function static (no network, no git fixtures) so it adds well under a second to the suite.

### Phase 2 - Composite and caller

2.1 Edit the composite as in Proposed Solution 2. Do not touch the earned-green blocks, the allowlist or the off-main refusal. Validate the composite's `run:` body with `bash -n` on an extracted copy;
    do NOT run `actionlint` on `action.yml` (it emits spurious schema errors against the action schema).
2.2 Edit `weakness-miner.yml` as in Proposed Solution 1; correct its header comment (the "Uses only GITHUB_TOKEN" line becomes false). `actionlint` on this workflow only.
2.3 `CHANGELOG.md` v4 entry.

### Phase 3 - Governance that goes red otherwise

3.1 `tests/scripts/test-infra-privileged-tier-census.sh`: G7f caller count `3` to `4` (the line-1642 comment and the line-1744 `!= 3` check and its message) with a dated comment (2026-10-11, #9454 item 4,
    `weakness-miner.yml::mine`). Run the whole census before and after and diff the row list; every other row must be unchanged. The narrow shape and a scalar `environment: infra-privileged`
    already satisfy G7f, G1b and G1c per review.
3.2 `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: add a Group 4 row for `weakness-miner.yml::mine` (schedule and workflow_dispatch; `infra-privileged`;
    `DOPPLER_TOKEN_INFRA_APP`; writes PRs and branches only; tier B).
3.3 `model.c4`: edge `github -> doppler`. Read all three `.c4` files first. Edit more than the count: the sentence "two unattended App-token consumers ... build-inngest-bootstrap-image.yml's
    bump-cloud-init-pin and mint-inngest-bootstrap-tag.yml's mint" and the follow-on "those two consumers read the NARROW Doppler project ... neither job holds ..." both name the set, and the
    "composite's third caller, apply-github-infra.yml" sentence stays true. Regenerate the tracked `model.likec4.json` (it is tracked; find the generator with `git grep -n "likec4.json"`).
    Run `bash plugins/soleur/test/c4-count-parity.test.sh` and the c4 syntax and render tests.
3.4 ADR-232 dated amendment and ADR-241 amendment-log line (see Architecture Decision). ADR-270 and the canary-log runbook row for item 4
    (`knowledge-base/engineering/operations/runbooks/merge-queue-canary-log.md`) are NOT edited: that row records a measurement and stays as it is until a later bot PR is measured.

### Phase 4 - Verification before PR

4.1 `bash tests/scripts/test-weakness-miner.sh` GREEN and each battery row RED; `bash tests/scripts/test-infra-privileged-tier-census.sh`,
    `plugins/soleur/test/required-checks-canonical-parity.test.sh`, `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`,
    `python3 scripts/lint-guard-contract.py <this plan>`.
4.2 The composite now binds a live credential in an inline script: run `bash scripts/lint-shell-trace-credential-refusal.test.sh` and `bash tests/scripts/test-argv-bearer-sweep.sh` and confirm
    neither scope widens onto `action.yml`; if one does, satisfy it the way `bump-inngest-bootstrap-pin.sh` does (xtrace refusal prologue, `_bearer_ok` shape check).
4.3 PR body: `Ref #9454`, one prose sentence mentioning the 2026-10-11 stall-watchdog issue (10019, closed; not reopened or closed here), no close keyword near either number,
    no statement that ADR-270 is accepted.

### Phase 5 - Tracking issues (deferrals must not be invisible)

- File A: "App-authored weakness-digest PRs now run real CI: retire the synthetic check-runs, move digest-class PR authorship to a lower-grant App if one is created, and census the other
  workflows that open PRs with the workflow token" (`git grep -ln "gh pr create\|create-pull-request" -- .github/workflows` lists `cla-evidence-timestamp.yml`,
  `cleanup-unmerged-bot-branches.yml`, `fix-constraints-stage-b.yml`, `git-data-rung2-rehearsal.yml`; none was in the stall evidence). Re-evaluate on 2026-11-01 or after two measured Sunday runs,
  whichever is later; touches ADR-139, parity test 8, `lint-bot-synthetic-completeness.sh`. Milestone from `knowledge-base/product/roadmap.md`.
- File B: "`scripts/audit-bot-codeql-coverage.sh` samples `--author app/github-actions`; weakness digests are now `app/soleur-infra`" (advisory audit loses its only live sample as old PRs age out of
  the 100-PR window; widen the author filter; relates to #3595).
- Link both from the PR body as prose; neither blocks this PR.

### Post-merge measurement (carried by #9454 item 4, not by this PR)

The next scheduled run is Sunday 2026-10-18 06:00 UTC; `gh workflow run weakness-miner.yml --ref main` produces a PR earlier only when the digest content changed (otherwise the composite exits
"No changes to commit" and the measurement is "not evaluable, re-measure on the next run"). The post-merge phase of the session that ships this PR arms a Monitor on the dispatched run (per
`hr-dispatch-async-must-arm-watch`) and reads the facts below; a later session picks up the Sunday run from #9454 item 4. The facts-only comment on #9454 says "measured" or "not evaluable",
never "canary closed", and #9454 stays open. A follow-through enrollment is deliberately not used: the sweeper closes its tracker on success, and #9454 also tracks items 5 and 6.

## Files to Edit

- `.github/workflows/weakness-miner.yml`
- `.github/actions/bot-pr-with-synthetic-checks/action.yml`
- `.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md`
- `tests/scripts/test-weakness-miner.sh`
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` and `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (tracked, regenerated)
- `knowledge-base/engineering/architecture/decisions/ADR-232-inngest-bootstrap-pin-bumps-are-authored-by-the-publish-workflow.md`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-bot-digest-pr-ci-runs-held-for-approval/tasks.md`

All paths were checked with `git ls-files`; `tests/scripts/test-weakness-miner.sh` is registered at `scripts/test-all.sh` (`run_suite "tests/scripts/weakness-miner"`).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "make bot-opened digest PRs' CI runs start without manual approval" | Proposed Solution 1-2, Phase 2 | mapped |
| 2 | "First VERIFY which lever is real" | Research Insights evidence table, Cut List | mapped |
| 3 | "Prefer a code/workflow fix reviewable in a PR (e.g. open the digest PR under a GitHub App installation token per hr-github-app-auth-not-pat" | Phase 2 | mapped |
| 4 | "if only a setting works, state the exact click/API call and who must run it" | Research Insights: no setting is a verified lever; none required | mapped (condition not met) |
| 5 | "Add a test or lint guarding the fix where feasible" | Phase 1, Guard Contract | mapped |
| 6 | "no close keywords for #9454 in the PR (use `Ref #9454`)" | Phase 4.3, AC | mapped |
| 7 | "do NOT post a \"canary closed\" comment; no stage PR cites ADR-270 accepted as canary evidence" | Phase 4.3, post-merge note, ADR-270 and canary-log untouched | mapped |
| 8 | "S2/S3 soaks (CI_PUSH_DEDUPE, CI_DRAFT_LIGHT) untouched; cutting S2 to 3 days is NOT approved; do not hand-sync BEHIND PRs" | `ci.yml` and repository variables not in Files to Edit | mapped |
| 9 | "link it in the PR body as prose, do not reopen or close it" | Phase 4.3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `weakness-miner.yml` edit | "open the digest PR under a GitHub App installation token" | asked |
| composite `pr-token` input, App push | "open the digest PR under a GitHub App installation token" (the PR write and push happen inside the composite) | asked |
| guard function in `test-weakness-miner.sh` | "Add a test or lint guarding the fix where feasible" | asked |
| census G7f 3 to 4 | - | inferred - justification: the census fails `test` otherwise (a fourth caller is a "deliberate, dated edit" by its own contract) |
| runbook Group 4 row | - | inferred - justification: the runbook is the credential inventory the census cross-checks (ADR-241 D2) |
| C4 edge prose and JSON | - | inferred - justification: `c4-count-parity` gates the "two unattended App-token consumers" count |
| ADR-232 amendment and ADR-241 log line | - | inferred - justification: gate `wg-architecture-decision-is-a-plan-deliverable` (the decision extends ADR-232 to a second workflow and adds a Tier-B consumer) |
| two deferral issues | - | inferred - justification: deferral-tracking rule (a deferred item without an issue is invisible) |

### Split Assessment

- Subsystems touched: 3 (`.github/` workflow and composite, `tests/`, `knowledge-base/` records)
- Planned files: 10 | Estimated changed lines: about 250 plus the regenerated JSON
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `weakness-miner.yml` job `mine` has `if: github.ref == 'refs/heads/main'`, `environment: infra-privileged`, a `timeout-minutes` greater than the sum of its step caps, and the checkout step has
      `persist-credentials: false`. The mint step uses `./.github/actions/mint-infra-app-token` in the narrow shape with permissions exactly `{"contents":"write","pull_requests":"write"}`, repositories `soleur`,
      sits after `Run weakness-miner` and before the composite step; the composite receives `pr-token` from that step's `token` output and `gh-token: ${{ github.token }}`; workflow `permissions:` are
      `contents: read` and `checks: write` only.
- [ ] The composite declares `pr-token`; its first statements refuse an empty value and a value equal to `gh-token` before the no-change early exit; `git push`, `gh pr create`, `gh pr edit` and `gh pr merge`
      run under the PR token; the `check-runs` POST runs under `gh-token`. Command:
      `git diff -U0 origin/main -- .github/actions/bot-pr-with-synthetic-checks/action.yml | grep -E '^[+-].*(GITLEAKS_|lint-fixture-content|lint-credential-path-literals|ALLOWED_PATHS|GITHUB_REF)'` prints nothing
      (earned-green, allowlist and off-main blocks untouched).
- [ ] `bash tests/scripts/test-weakness-miner.sh` is green on the branch, and each Guard Contract mutation row turns it RED (battery output in the PR).
- [ ] The census, `required-checks-canonical-parity.test.sh`, `lint-bot-synthetic-completeness.test.sh`, `c4-count-parity.test.sh`, the c4 syntax and render tests, `lint-shell-trace-credential-refusal.test.sh`
      and `test-argv-bearer-sweep.sh` are green; `bash scripts/lint-orphan-test-suites.sh` reports no orphan.
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-11-fix-bot-digest-pr-ci-runs-held-for-approval-plan.md` exits 0 and reports one entry.
- [ ] ADR-232 carries an amendment dated 2026-10-11 whose wording states the evidence, not a proven rule (see Architecture Decision); ADR-241's amendment log carries one line;
      `git diff --stat origin/main -- knowledge-base/engineering/architecture/decisions/ADR-270* knowledge-base/engineering/operations/runbooks/merge-queue-canary-log.md` is empty.
- [ ] `gh pr view --json body --jq .body | grep -inE '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#(9454|10019)'` prints nothing, and the body contains `Ref #9454`.
- [ ] No change to `.github/workflows/ci.yml`, to repository variables `CI_PUSH_DEDUPE` or `CI_DRAFT_LIGHT`, or to any Actions repo setting.
- [ ] The two deferral issues exist and are linked from the PR body.

### Post-merge (measured on the first run that produces a PR; recorded as facts on #9454)

- [ ] If the run prints "No changes to commit", record "not evaluable" and re-measure on the next scheduled run; do not infer success from the mint step alone.
- [ ] The run's `app-token` notice reads `app=soleur-infra installation=166065653 permissions={"contents":"write","pull_requests":"write"}`.
- [ ] The PR author is the App: `gh pr view <N> --json author --jq .author.login` prints `app/soleur-infra` (REST/CLI spelling; `soleur-infra[bot]` is the same identity on the GraphQL surface).
- [ ] No held run: `gh api "repos/jikig-ai/soleur/actions/runs?head_sha=<sha>&per_page=100" --jq '[.workflow_runs[]|select(.status=="action_required")]|length'` prints `0`, the head's
      `pull_request` `CI` run has `conclusion` `success`, and every context in `scripts/required-checks.txt` has a `success` check-run on the head (a real failure beside a synthetic success is recorded as a fact
      for deferral issue A, not hidden).
- [ ] The PR timeline shows `added_to_merge_queue` by `soleur-infra[bot]`, then `merge_group` runs for `gh-readonly-queue/main/pr-<N>-*`, and the PR merges with no `merge-queue-stall` issue filed within
      90 minutes of PR creation.
- [ ] If the PR runs are still held although the push, PR and auto-merge all ran as the App, stop: the identity premise is wrong; open a new investigation, do not widen the allowlist or loosen a setting.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. The weekly digest PR for maintainers fails to open (the mint or composite step fails loudly and the failure email fires) or stalls in the queue as it did on 2026-10-11, delaying a doc refresh that only informs a maintainer's triage.
- **If this leaks, the user's workflow is exposed via:** a minted `soleur-infra` installation token (scope `contents:write`, `pull_requests:write` on this one repository, one hour) if a step echoed it; the mint composite masks it, the token exists only as a step output consumed by the composite, and the miner script runs before it exists. The broader exposure is the Doppler read token and the App key behind it: the App grant includes `administration:write` and `secrets:write`, scoping is enforced by the mint composite's exact-grant check rather than by the credential, so a compromised step in this job could mint a wider token. That is the same exposure the three existing callers carry, not a new class; the ADR-232 amendment states it.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI automation on a single path of derived markdown; the token scope equals what the existing pin-bump job holds and the environment is main-only, so a defect costs maintainer time, not a user's data or money.

`threshold: none, reason: the touched paths are .github workflow and composite files plus tests and records; no user data, auth flow, schema or payment surface is read or written, and the new caller reuses an already-approved token scope on a main-only environment.`

## Observability

```yaml
liveness_signal:
  what: "Scheduled: Weakness Miner workflow run (weekly) and the digest PR it opens, as GitHub Actions run records"
  cadence: "weekly, Sunday 06:00 UTC"
  alert_target: "ops email via the existing notify-ops-email failure step; merge-queue-stall issue from the stall watchdog"
  configured_in: ".github/workflows/weakness-miner.yml (failure step) and .github/workflows/merge-queue-stall-check.yml"

error_reporting:
  destination: "GitHub Actions run annotations plus ops email (RESEND_API_KEY already wired in weakness-miner.yml)"
  fail_loud: "::error::mint-infra-app-token and ::error::bot-pr-with-synthetic-checks pr-token lines fail the step; the workflow failure email fires"

failure_modes:
  - mode: "App token mint fails (Doppler read, missing environment secret, grant mismatch)"
    detection: "the mint composite exits non-zero with a sanitized ::error:: naming DOPPLER_TOKEN_INFRA_APP and the runbook; the job fails before any branch push"
    alert_route: "ops email from the failure step"
  - mode: "pr-token empty or equal to gh-token (a caller regression)"
    detection: "composite refuses before any git or gh write, on changed and unchanged weeks alike; the static guard is red in the required test aggregate before merge"
    alert_route: "PR check failure; ops email if it reaches a scheduled run"
  - mode: "PR still stalls in the queue (held runs or no merge_group dispatch)"
    detection: "merge-queue-stall-check.yml files a merge-queue-stall issue after its 45 minute threshold"
    alert_route: "GitHub issue labelled action-required and merge-queue-stall"
  - mode: "digest unchanged"
    detection: "composite prints 'No changes to commit' and exits 0 (expected, not a failure)"
    alert_route: "none"

logs:
  where: "GitHub Actions run logs for weakness-miner.yml and the PR timeline"
  retention: "GitHub Actions default retention (90 days)"

discoverability_test:
  command: "grep -cF 'pr-token: ${{ steps.' .github/workflows/weakness-miner.yml"
  expected_output: "1"
```

## Guard Contract

### Guard 1 - bot-PR author identity

**Property.** Every caller of the bot-PR composite supplies a PR-write token minted in the same job by the `soleur-infra` App composite (scoped to `contents:write` and `pull_requests:write` on `soleur`, in the `infra-privileged` environment) and supplies the workflow token only as the synthetic-check identity, and the composite itself performs its push and its three PR writes under the PR token and its check-run posts under the workflow token.

**Assembly.** The population is derived, never listed: every job step in `.github/workflows/*.yml` whose `uses` resolves to `./.github/actions/bot-pr-with-synthetic-checks`, floor of at least one caller. The chokepoints are two. (a) The caller side: the step's `with:` block (`pr-token`, `gh-token`), the job's `environment:`, and the ordering and scope of the mint step relative to the composite step in the same job. (b) The composite side: the push and the three PR-write command sites (`gh pr create`, `gh pr edit --add-label`, `gh pr merge --squash --auto`) and the single check-run POST loop, read from the comment-stripped `run:` body. A guard scoped to the one caller that exists today would miss the second caller the property quantifies over, so the guard evaluates every derived member, not the first.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | In `weakness-miner.yml`, set `pr-token:` to `${{ github.token }}` | RED |
| 2 | In `weakness-miner.yml`, delete the `pr-token:` line | RED |
| 3 | Move the mint step after the composite step in the same job | RED |
| 4 | Remove `environment: infra-privileged` from the job | RED |
| 5 | Add a second compliant job that calls the composite, then a third that passes `${{ github.token }}` as `pr-token` (a check that stops at the first member passes this) | RED |
| 6 | Point the guard at a workflows directory with zero callers (its dispatch override) | RED (floor: "0 callers checked" must fail, not pass) |
| 7 | In the composite, drop the `GH_TOKEN="$PR_TOKEN"` prefix from `gh pr merge`, then separately from `gh pr create` | RED (two rows) |
| 8 | In the composite, run the `git push` without the PR-token header (back to the checkout credential) | RED |
| 9 | In the composite, run the `check-runs` POST under `PR_TOKEN` (a different integration id fails the ruleset match) | RED |
| 10 | In the composite, delete the empty and equality refusal | RED |

**Harness rows.** (H1) The guard's own positive control: a synthetic known-bad caller is evaluated before any verdict and must come back RED, otherwise the guard aborts, so a blind population walk cannot report green. (H2) A must-PASS input that differs from the canonical in permitted ways: a caller whose mint step id is `appmint` instead of `mint`, with unrelated steps between mint and composite, `pr-token` spelled `${{steps.appmint.outputs.token}}` (no inner spaces), in a differently named workflow file and job; it must come back GREEN, so a guard that rejects everything is caught.

**Anchor.** Not applicable: the guard compares structure to structure, with no stored hash, manifest row or count. The only count is the floor of one caller, paired with per-member evaluation (set identity would force every legitimate new caller to edit the guard, the wrong cost for a property every caller must satisfy anyway). The census G7f exact caller count is the existing, separately reviewed anchor that a new caller needs a dated edit.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-232** (dated amendment 2026-10-11, #9454 item 4), as an amendment rather than a new ADR because the decision is the same one extended to a second workflow (taste: a new ADR is the alternative; recorded in `decision-challenges.md`).
State the evidence, not a proven rule: workflow-token-armed queue entries received no `merge_group` runs and their PR runs were held; the same PR's second entry, armed by a human, did get runs, so the enqueuer is a
discriminating variable and the author-versus-enqueuer split is not separated by the data; the App configuration (Control A) works end to end. Therefore the weakness-miner digest PR is authored, pushed, and armed by the `soleur-infra` App, and the
workflow token keeps only the check-run posts. State the exposure honestly: the minted token is scoped, but the Doppler read token behind the mint reads the App key, whose grant includes `administration:write`
and `secrets:write`; scoping is a property of the composite, the same exposure the other three callers carry. Name the trigger for revisiting: if a lower-grant App for digest-class PRs is created, this caller moves (deferral issue A).
Add one line to **ADR-241**'s Amendment log naming the fourth composite caller (`weakness-miner.yml::mine`, narrow source, `infra-privileged`). ADR-270 stays `adopting` and is not edited or cited as accepted. ADR-032 is not edited.

### C4 views

Planning-time check: the `model.c4` `github -> doppler` edge (line 702 at the time of writing) is the one edge whose prose names the App-token consumers; a grep of all three `.c4` files for `weakness`, `mint-infra`, `bot-pr` and `soleur-infra` found no other element or edge about this workflow. This is a grep, not a read, so the implementer must still read all three files in full before concluding. Enumeration for this feature:
(a) external human actors: none new; (b) external systems: GitHub (already `github`), Doppler (already `doppler`), the `soleur-infra` App (already described on the `github -> doppler` and `github -> soleurMarketplace` edges); (c) data stores: none;
(d) actor-to-surface access relationships: the set "two unattended App-token consumers on infra-privileged" and its follow-on sentence change to three. Edit that edge's prose in `model.c4`, regenerate the tracked `model.likec4.json`, and confirm `views.c4`
and `spec.c4` need no edit (no new element or relationship, so no `view ... include` change). Run `plugins/soleur/test/c4-count-parity.test.sh` (it gates derived cardinalities in edge prose) plus the c4 syntax and render tests.

### Sequencing

The ADR amendment and the C4 edit ship in this PR. The decision is fully true at merge (no soak-gated slice).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an engineering CI/tooling change with no product, legal, marketing, finance, sales, support or operations-vendor surface. (Engineering review ran in plan-review.)

## Test Scenarios

- Given today's tree, when the guard function runs, then it is RED naming the missing `pr-token` (proves it sees the bug before the fix).
- Given the fixed tree, then GREEN with a printed per-caller line and the suite summary `0 failed`.
- Given a fixture workflow where `pr-token` is `${{ secrets.GITHUB_TOKEN }}`, then RED (the secrets spelling of the same identity).
- Given a fixture composite whose `git push` carries no PR-token header, then RED.
- Given the census with a fourth caller, then G7f is GREEN; a fifth caller is RED.
- Post-merge: see the measured bullets above.

## Dependencies & Risks

- **R1: the identity premise is inferred, not directly experimented.** Controls A and B and the human-armed second entry support it; no pre-merge run is possible (`infra-privileged` is main-only; a dispatch needs the file on the default branch). The post-merge criteria include an explicit "premise wrong" stop. The branch push now runs as the App so the configuration matches Control A in every variable.
- **R2: real PR CI now runs on the digest PR** (one `pull_request` CI run per week, mostly short-circuited by the docs path in `detect-changes`). The synthetic checks remain and are redundant; how the ruleset evaluates a real failure beside a synthetic success is unmeasured, hence the post-merge fact check and deferral issue A.
- **R3: `infra-privileged` is main-only.** A dispatch from another ref is refused by the environment, by the job `if`, and by the composite's off-main refusal.
- **R4: the miner script and the credential share a job.** Checkout uses `persist-credentials: false`, the token is minted after the miner step, and the composite is repo code from `main`; exposure equals the pin-bump job's.
- **R5: consumers of the PR author identity.** `scripts/audit-bot-codeql-coverage.sh` filters `--author app/github-actions` (advisory; deferral issue B). `cleanup-unmerged-bot-branches.yml` keys on the `ci/` head prefix, so it keeps working. `cla.yml` already allowlists `soleur-infra[bot]`; the merge-queue CLA verify reads check-runs by name under integration 15368, and PR 10027 (same identity) passed it.
- **R6: constraint compliance.** `ci.yml`, `CI_PUSH_DEDUPE`, `CI_DRAFT_LIGHT` and every Actions setting are untouched; no BEHIND PR is hand-synced; the PR carries no close keyword for #9454.
- **R7: a git extra-header with the persisted checkout header would double the Authorization header (HTTP 400).** Avoided by `persist-credentials: false`; the guard asserts it.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one carries `none` with the scope-out reason line.
- The census G7f count is `3` today; changing it is a dated edit by its own contract, and fixture rows in that file may assume three callers. Run it before the change and diff the row list.
- The App has no `issues:write`; a future composite caller that passes `labels` (via `gh pr edit --add-label`) would fail at the label step. The only caller passes none.
- `lint-guard-contract.py` matches `^##\s+Guard\s+Contract\b`; do not append a revision under a differently named heading.
- The earned-green block is not a place to tidy: ADR-139's parity test 8 asserts it exists.
- Never echo the minted token; read it only through `steps.<id>.outputs.token`. No `set -x` in the composite with `PR_TOKEN` set.
- Pipeline note: no spec.md exists for this one-shot branch, so `lane:` defaulted to `cross-domain` (fail-closed).
