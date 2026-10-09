---
title: "ci: skip the duplicate push-to-main CI run when a merge_group run already passed on the same SHA (S2, ADR-276)"
date: 2026-10-09
slug: ci-skip-duplicate-push-main-run-s2
branch: feat-one-shot-9512-skip-duplicate-push-ci
issue: 9512
closes: 9512
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# ci: skip the duplicate push-to-main CI run when a merge_group run already passed on the same SHA (S2, ADR-276)

## Enhancement Summary

**Deepened on:** 2026-10-09. **Agents used:** architecture-strategist, spec-flow-analyzer, security-sentinel, observability-coverage-reviewer (deepen pass); repo-research-analyst, learnings-researcher, functional-discovery, DHH, Kieran, code-simplicity, CTO devex lens (plan and plan review). Mechanical gates run and green: user-brand impact, observability schema and verb gate, PAT-shape grep, encryption posture (no store or connection), guard contract lint (2 entries), scope check, cited PR and issue states, label and milestone existence, AGENTS.md rule ids, `knowledge-base/` path existence.

1. **Security:** the vouching run is now bound to `event == merge_group`, the repository and the workflow path (a branch an author names `gh-readonly-queue/main/x` could otherwise vouch through a `pull_request` or `workflow_dispatch` run); `$GITHUB_OUTPUT` and annotations carry only literals and validated numbers.
2. **Budget:** the release workflow's CI budget step leaves a slack of 5 minutes against the longest `needs:` path (70 of 75); the new job is set to 3, not 5.
3. **Operations:** PM-0 (the push path first runs on `main`, not in the PR), a rollback path (PM-6), a probe that evaluates a wrong elision on every sweep, observes elision from job conclusions, computes its own mean cost (the census refuses live mode in CI) and requires an exit-census marker before the sweeper closes the tracker.
4. **Eligibility:** the 92 of 94 match is on final conclusions; the proof reads the `merge_group` run at push time, so the share already completed then is measured in Phase 1.
5. **Observability:** platform-reported `would-elide` step conclusion, layer citations, and a discoverability command that counts the eight gated conditions instead of a YAML key.

## Overview

Stage S2 of ADR-276: remove the second full execution of the `CI` workflow that follows every queue
merge, keyed per head SHA on a green `merge_group` run, while the push run keeps producing the
`success` conclusion the deploy arm needs. The stage also collects the post-merge evidence stage S1
(#9727) left outstanding.

## Research Insights

### Premise validation (Phase 0.6)

Checked on 2026-10-09: #9512 open (labels `priority/p2-medium`, `deferred-automation`, `meta/machinery`); its
four comments read (the 2026-10-07 ranking and preconditions, the deepen-pass correction that an all-skipped
run concludes `skipped`, and the S1 handoff, comment 6067548697). #9727 is CLOSED (its PR #9772 merged
2026-10-09T01:11:37Z), so S1's evidence is posted as comments on a closed issue. #9728, #9729, #9730 open.
Draft PR #9808 exists for this branch. ADR corpus grep for the mechanism: ADR-276 Decision 2 already names
both designs and the stop rule; ADR-217 Decision 2 holds the "verdict never crosses as a value" rule and the
trigger; ADR-270 holds the squash-queue shape. No ADR rejects keyed elision, so nothing re-scopes.
`origin/main` is `01d2b5a0d8`, the same commit as this branch's base (no drift). No new ADR is created (the
ordinal question does not arise): the deliverables are an ADR-276 S2 amendment and an ADR-217 amendment.

Stale premise corrected: #9512 says "13 of 15 push SHAs match, the 2 non-matches are bypass commits". Re-derived
on 2026-10-09 from the API (commands under Measured state): of the 94 completed push runs of the most recent
100 (2026-10-05T12:43:16Z to 2026-10-09T07:07:17Z), 92 have a `success` `merge_group` run with the same head
SHA and 2 have a `failure` one. Those 2 are queue merges, not bypasses: PR #9698 (`7f23ff853f`) and PR #9554
(`ed6a77b868`); in both the red job is the advisory `lint-bot-statuses`, the queue merged anyway, and the push
run then concluded `success`. So "the merge_group run for this SHA concluded success" is a stricter proof than
"the merge happened through the queue", and the design keys on the run conclusion, not on queue membership.

### Property List (Phase 0.6b)

1. A push-to-`main` `CI` run for a commit whose identical SHA already passed a full `merge_group` `CI` run
   consumes a small fraction of the runner minutes it consumes today.
2. The push run's conclusion still means "this SHA is green" to every consumer: `success` only if the battery
   ran green or the elision proof held for that exact SHA; a deploy of a SHA that no run vouched for is impossible.
3. Elision is keyed per exact head SHA, and every unknown (variable not exactly `on`, event not `push`, any API
   error, no match, a non-`success` conclusion, a gated job that did not conclude `success`) runs the full battery.
4. Dark launch and a kill-switch: merging changes no verdict; unsetting the variable restores today's behaviour.
5. Every claimed saving has a before and after figure from the committed census script (ADR-276 Decision 7).
6. Each trust-model change is recorded before it takes effect: an ADR-276 S2 amendment and an ADR-217 amendment.
7. The evidence S1 (#9727) deferred is collected and attached, with the secret-scan smoke ran, skipped and
   runner-less split and the 80% net criterion.

### Cut List (Phase 0.6b)

| Mechanism | Property it buys | What already covers it, or why cut |
|---|---|---|
| Static removal of the push run | 1 | Rejected by ADR-276 Option B and #9512 ("never a static removal"); the deploy arm needs a push `success` and direct pushes and `--admin` merges have no `merge_group` run |
| Re-key the deploy `workflow_run` arm on the `merge_group` completion (design 2) | 1 | Cut. The `merge_group` completion fires before the queue advances `main`, direct pushes still need the push arm (two arms to maintain), and it rewrites the ADR-217 trigger in a 2,660-line workflow. Comparison in Architecture Decision |
| Reuse `scripts/main-push-duplicate-skip.sh` as-is | 3 | Cut. It proves coverage from a `pull_request` run plus tree identity; a `merge_group` run for the same head SHA is the same commit, so SHA equality is the identity and no tree proof is needed. A new script keyed on the `merge_group` run is smaller. The precedent's fail-open shape (every error emits `false`) and its jobs-API prefix match are reused |
| Gate every job in `ci.yml` | 1 | Cut. The eight gated jobs (seven heavy stems and the `test` aggregator) are 94% of a push run's minutes (959.86 of 1,017.88 over the 7 baseline runs); gating the other 14 cheap guards that run on push adds 14 more edit sites to a guard's assembly for 6% of the minutes |
| A tolerance arm in the `test` aggregator | 2 | Cut (plan review, DHH). `test` is required for `pull_request` and `merge_group` only; gating `test` with the same condition leaves its body byte-identical and removes a second skip-tolerance from the repo's most load-bearing check |
| A per-stem coverage loop over the `merge_group` run's jobs | 3 | Cut (plan review, DHH and simplicity). The run conclusion `success` plus the `test` job `success` already implies every leg ran, because the aggregator concludes red on any skipped leg; the coupling is pinned by a mutation row |
| A shadow or experiment phase | 4 | Cut by the parent plan. The proof is computed in every push run while the variable is unset (a `would_elide` annotation), which is the dark phase |
| A new workflow file for the attestation | 2 | Cut. The workflow name `CI` is the trigger key of two `workflow_run` consumers and must stay one workflow; a job inside `ci.yml` keeps it |
| Tree-identity or ancestry proof | 3 | Cut. SHA equality of the `merge_group` head and the push head is the strongest identity available (a commit id commits to tree, parents and message) |
| Fallback unfiltered run listing when the filtered search lags | 3 | Cut. A lagging search can only miss a match, which means a full run (the safe direction); the dark-phase `would_elide` rate measures the miss rate |

### Measured state (re-derived 2026-10-09, API reads at plan time; the work phase commits them as files)

Keying (commands: `gh api "repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?event=push&branch=main&per_page=100"`
and `gh api --paginate "repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?event=merge_group&per_page=100"`,
both written to files, then `jq -s` over the files, never `--paginate` with `--jq` aggregates):

| Quantity | Value |
|---|---|
| Push `CI` runs listed / completed | 100 / 94 (2026-10-05T12:43:16Z to 2026-10-09T07:07:17Z) |
| `merge_group` `CI` runs listed (paginated) | 168 |
| Completed push runs whose head SHA has a `success` `merge_group` run | 92 of 94 (97.9%) |
| Completed push runs whose head SHA has only a `failure` `merge_group` run | 2 (PR #9698, PR #9554; red job `lint-bot-statuses`) |
| Push runs that concluded non-success, all on SHAs with a green `merge_group` run | 8 of 94: `e2e` 3, `test-scripts (5/8)` 2, `test` 2 (runs of 2026-10-05, SHAs `b6f73ca726` and `61756987b4`), one with no failed job listed |

The last row is the cost of the design and is the loudest finding of the research: the push run is a second
sample that turned red on about 1 in 12 queue-merged SHAs, each of which blocked that SHA's deploy
(`ci_not_green`) and paged. Elision removes that sample by construction. Whether those 8 were flakes or real
regressions the queue missed is classified in the work phase (does the next push run on `main` fail the same job)
and recorded in the ADR amendment as a named residual; it is not assumed here either way.

Push-run cost by job stem (the 7 push runs created 2026-10-07T13:04Z to 19:04Z, the parent plan's window;
runner-bound, non-skipped, `completed_at - started_at`; total 1,017.88 job-minutes, the census reports 1,017.9
over the same 7 runs, 145.41 per run):

| Stem group | Job-minutes over 7 runs | Share |
|---|---|---|
| `test-scripts` 631.97, `test-scripts-heavy` 117.45, `test-webplat` 81.22, `shard-totality-mutations` 65.40, `e2e` 29.38, `web-platform-build` 18.75, `test-bun` 15.27, `test` 0.42 (the gated set of eight) | 959.86 | 94.3% |
| Everything else: 14 cheap guards that run on push (2 more are PR-only) | 58.02 (8.29 per run) | 5.7% |

Derived targets (recomputed from these inputs in the work phase): an elided run costs about 8.29 plus the
attestation job (under 0.5), about 8.5 per run, a 94% cut against 145.41. The stage's net criterion is a mean
push `CI` cost of at most 20% of 145.41, which is 29.08 job-minutes per run. With a share f of runs that cannot
be elided (2 of 94 today, 2.1%), the mean is f x 145.41 + (1 - f) x 8.5, and the criterion holds while f is at
most (29.08 - 8.5) / (145.41 - 8.5) = 15.0%. Expected mean at today's f: about 11.4, a 92% cut, worth about 940
job-minutes per 6 h (7 runs x (145.41 - 11.4)) against the 7,456 to 9,045 totals the parent plan and the S1
baseline report for that window (10% to 13%).

### Consumers of the push-event `CI` run on `main` (census, grepped on this branch)

| Consumer | Reads | Effect of an elided `success` run |
|---|---|---|
| `.github/workflows/web-platform-release.yml` `resolve-target`, the `# ── workflow_run arm` block (`not_main`, `not_push`, `ci_not_green` clean skips) | `workflow_run.conclusion == success`, `head_branch == main`, `event == push` only; never CI job names | Unchanged. The release verdict is the `release / release` job of its own push-arm run (ADR-217 Decision 2) |
| `.github/workflows/web-platform-release.yml`, step "Derive the CI budget and check for creep" | the STRUCTURE of `ci.yml` (`run_declared_path`, `undeclared_jobs`): hard-fails if the longest declared `needs:` path exceeds `CI_BUDGET_MIN`; B9 in `scripts/prod-version-drift-check.test.sh` asserts the same arithmetic against `DRIFT_SUSTAINED_THRESHOLD_MIN` (225) | `push-dedupe` lengthens the longest path by its `timeout-minutes`; Phase 2 computes the slack first (found by plan review) |
| `.github/workflows/post-merge-monitor.yml` | the CI conclusion, only for `[bot-fix]` commits | Unchanged (`success` verifies, `failure` reverts, `skipped` is inert) |
| `plugins/soleur/scripts/deploy-arm.sh` (`evaluate`, the `actions/workflows/ci.yml/runs?head_sha=` read) | status, conclusion, created, started and updated timestamps of the push run | `CI=success` is reported; run duration shrinks, which only affects the creep warning |
| `scripts/followthroughs/pr-battery-gate-saving-9323.sh` (the `push run for $sha` read) | push conclusion as the ADR-262 escape detector | An elided `success` can hide nothing the full `merge_group` battery did not already see; noted in the ADR amendment |
| `scripts/followthroughs/ci-leg-balance-9232.sh`, `deploy-script-tests-legs-8736.sh` | success push runs, per-leg timing artifacts | Elided runs carry no leg artifacts and drop out of the sample; the work phase reads both to confirm they fail soft (NOT YET) rather than red |
| `scripts/regenerate-shard-manifest.py` (`green_main_runs(workflow="ci.yml", n=5)`) | the five most recent successful `main` runs and their leg-timing artifacts | Elided runs are `success` with no timing artifacts; after activation most of the newest five could be elided. The work phase reads its `allow_empty` handling and filters to non-elided runs (display of the skipped gated jobs) |
| Artifact readers (`download-artifact`, `run-id:` in any workflow other than `ci.yml`) | grepped 2026-10-09: only `fix-constraints-stage-b.yml` (its own stage-a run) and `apply-web-platform-infra.yml` (its own plan artifact) | None reads a `ci.yml` push run's artifacts |
| `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`, `postmerge` skill | `gh run list --branch main --workflow CI` | Read-only docs; the work phase greps them for a "test job ran" assumption |
| `main-health-monitor.yml`, `codeql-main-alert-gate.yml` | not consumers (dispatch-only; its own push trigger) | None |

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-10-09-my-scripted-adr-rewrite-cut-the-file-at-the-wrong-match-and-every-gate-passed.md`: append-only amendments are written with the Edit tool at a unique anchor, or, if scripted, with a line-start `re.M` match, an assertion of exactly one match, and `git diff origin/main -- <file>` read for its deletion count.
- `2026-09-23-non-required-did-not-mean-decoupled-and-my-canonicalizer-rewrote-its-own-evidence.md`: any failing job turns the run conclusion non-success and blocks the deploy; the new job must fail open to a green run without failing it (`continue-on-error` on the proof step, `elide` defaults to false).
- `best-practices/2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md` and the `ci.yml` header: never put an `event_name == 'pull_request'` gate on a required job. The new condition runs the gated jobs on every event except an elided push.
- `2026-10-04-a-queue-candidate-trust-check-premised-on-an-unmeasured-commit-shape.md`: the squash candidate is a single-parent commit whose parent is the previous candidate; the design therefore keys on SHA equality, which the 92 of 94 measurement confirms, not on a PR-head relation.
- `2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`: a `grep | head` that matches nothing aborts a `run:` step under the default `pipefail`; every substitution in the new script is guarded.
- `2026-07-28-a-ten-run-sample-said-unreachable-and-the-defect-was-live-at-two-percent.md` and the grep-q-pipe-guard: no new `| grep -q` pipes in `scripts/*.test.sh`; use `grep -cE ... >/dev/null`.
- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`: the new suites carry an independent producer count and a positive control.
- `2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md`: the probe's signal handling, if any, is verified empirically and run in a loaded-machine loop before commit.

## Research Reconciliation: brief and issue vs. codebase

| Claim | Reality (checked on this branch) | Plan response |
|---|---|---|
| #9512: "13 of 15 push SHAs match; the 2 non-matches are bypass commits" | 92 of 94 match; the 2 non-matches are queue merges whose `merge_group` run concluded `failure` on the advisory `lint-bot-statuses` job (Research Insights) | Key on the run conclusion `success`, not on queue membership; both cases fall back to a full push run |
| #9512 precondition (1): "measure whether an all-skipped `ci.yml` run concludes `success`" | Already measured in the parent plan: an all-skipped run concludes `skipped` (8 `Post-Merge Monitor`, 7 `Cleanup unmerged bot branches` runs). The deploy arm needs `success` (`ci_not_green` otherwise) | No new measurement. The elided run keeps real jobs, `push-dedupe` and the 14 ungated cheap guards, so the run cannot be all-skipped. A first-run canary confirms the conclusion once on a real run |
| Comment 2: "reuse `scripts/main-push-duplicate-skip.sh` with care" | Its proof is a `pull_request` run plus tree identity; it never reads `merge_group` and it matches a draft-light run | Not reused (Cut List). Its fail-open shape and prefix match are copied; its draft concern disappears because the key is the `merge_group` run, which S3 never lightens |
| Comment 2 / precondition (3): "`ci.yml` is at its ceiling of 24 jobs, a new job needs a ledger bump" | `scripts/pr-fanout-ledger.txt` row `ci.yml 24`; `plugins/soleur/test/pr-fanout-ledger.test.sh` asserts declared jobs <= row | One new job (`push-dedupe`): row 24 to 25 with a named consequence (skipped without a runner on `pull_request` and `merge_group`) |
| Precondition (4): "dark launch behind a repository variable (unset means run)" | `gh variable list` shows only `GIT_DATA_ROOT_STATE_MIGRATED` and `WATCHDOG_ARMED`; precedent in `scheduled-supabase-watchdog.yml` (exact-value compare in the step shell, unset means detect-only) | Variable `CI_PUSH_DEDUPE`, accepted value exactly `on`, compared in the step shell |
| The `test` aggregator "tolerates skips" | It does not: a `skipped` leg prints `SKIPPED` and sets `fail=1`. `test` is a required context whose name is fixed (ADR-032), required for `pull_request` and `merge_group` only | No tolerance arm. `test` itself is one of the eight gated jobs and is skipped on an elided push; its body stays byte-identical. The run stays `success` because `push-dedupe` and the 14 ungated guards succeed |
| ADR-276 Status: "no stage PR that changes CI behaviour (S2, S3, S4) may merge while the file reads `proposed`" | The brief says the ADR stays `proposed`; the CTO approval comment that flips it has not been given | Conflict recorded in `decision-challenges.md` (User-Challenge). Default is the brief: the PR keeps `proposed` and merges dark, because with the variable unset no verdict moves; the behaviour change is the activation step, which is gated on the file reading `adopting` (Phase 5). The amendment states this reading so it is challengeable |
| S1 handoff (comment 6067548697): "append the `S1 live` line in S2's own amendment" | The brief says the S1 census is a post-merge task of S2 | Honour the brief: the amendment records S1 evidence as owed; the `S1 live` line is appended by a docs-only follow-up after the census is attached (the S1 amendment allows "a docs commit if S2 does not follow") |

## Open Code-Review Overlap

Open `code-review` issues whose body names a file this plan edits: #8659 and #7942 (`scripts/test-all.sh`),
#8800 (`scripts/lib/test-affected-paths.sh` and `scripts/followthroughs`: a census sandbox that shares inodes
or symlinks with the live repo), #3321 (`.github/CODEOWNERS`, a learnings-subtree concern), #8496 and #8435
(`scripts/followthroughs`, unrelated probes), #3220 (`web-platform-release.yml`, migration postmerge checks).
Disposition: **Acknowledge** all; none sits on the lines this plan edits and each is a different concern.
One constraint is taken from #8800: the new suites build their fixtures in `mktemp -d` copies and never
symlink or hard-link into the live repo. No open `code-review` issue names `ci.yml`, `pr-fanout-ledger.txt`,
`ci-test-aggregator-diagnosis.test.sh`, ADR-217 or ADR-276.

## Proposed Solution

### Design chosen: a keyed attestation job inside `ci.yml` (design 1 of ADR-276 Decision 2)

One new job, `push-dedupe`, with job-level `if: github.event_name == 'push'` (so on `pull_request`,
`merge_group` and `workflow_dispatch` it is skipped without taking a runner), `timeout-minutes: 3` (written alone on its line: the
release workflow's `run_declared_path` awk reads `timeout-minutes: N` with nothing after it, and a trailing comment would
make the job count as undeclared at 360 minutes; see Phase 2 for the budget arithmetic), `permissions: actions: read`, an output `elide`, and
one inline step (extracted and executed by the suite, the `secret-scan-smoke-gate` pattern, no checkout). The
step runs with `continue-on-error: true`, its own step-level `timeout-minutes: 2` and `timeout 20` around each
`gh` call (a hung read must end the step, not the job: a job timeout concludes the run `failure` and the deploy
sees `ci_not_green`), and `env:` of `GH_TOKEN: ${{ github.token }}`, `GH_REPO: ${{ github.repository }}`,
`SHA: ${{ github.sha }}`, `EVENT_NAME`, `REF`, `RUN_ATTEMPT` and `SWITCH: ${{ vars.CI_PUSH_DEDUPE }}`. The step:

1. Writes `elide=false` to `$GITHUB_OUTPUT` first, before any read, so a crash leaves the safe value; every `gh`
   call and `jq` substitution is guarded (the default shell is `pipefail`).
2. Refuses unless `EVENT_NAME == push`, `REF == refs/heads/main`, `RUN_ATTEMPT == 1` (a human re-run is never
   elided: it exists to re-test), and the SHA is 40 hex (reason codes `not_push`, `not_main`, `rerun`, `bad_sha`).
3. Lists `ci.yml` runs with `event=merge_group&head_sha=<sha>` (one read, `per_page=100`), then selects client-side
   a run with `event == merge_group`, `status == completed`, `conclusion == success`, `head_sha == <sha>`,
   `path == .github/workflows/ci.yml`, `head_repository.full_name == $GH_REPO` and `head_branch` starting with
   `gh-readonly-queue/main/` (the search parameters are advisory; the client-side re-check is the proof, and the
   `event` and repository checks are what stop a `pull_request` or `workflow_dispatch` run on a branch the author
   named `gh-readonly-queue/main/x` from vouching; the branch prefix is only a secondary filter). None selected is
   `no_mg_success`.
4. Reads that run's jobs (`per_page=100`, `filter=latest`) and requires a job named exactly `test` with conclusion
   `success`. Why one job and not a stem list: the `test` aggregator already concludes red when any of its five
   legs is `skipped` (its loop sets `fail=1` on every non-`success` result), and the run conclusion `success`
   already excludes a failed `e2e` or `shard-totality-mutations`. The coupling is deliberate and pinned: a later
   stage that teaches the aggregator to tolerate `skipped` on `merge_group` must also restore a per-stem check
   here (a mutation row below fails if the aggregator ever tolerates `skipped` for a gated leg on `merge_group`).
   A missing job (including a listing that truncates past 100 jobs) is `no_test_job`, never coverage.
5. `would_elide=true` when all of that holds. `elide=true` only when additionally `SWITCH == "on"` (compared in the
   shell; the variable enters through `env:`, never inline in `run:`). It writes `elide=true` last.
6. Emits one `::notice title=ci-push-dedupe::sha=... would_elide=... elide=... reason=... mg_run=...` annotation
   (a human-readable audit line; nothing machine-reads it as evidence; a `::warning::` with reason `proof_error` on any
   API failure) and a step summary line. Injection discipline: `$GITHUB_OUTPUT` receives only the literals
   `elide=true`, `elide=false`, `would_elide=true` or `would_elide=false`, never an API value; `mg_run` is validated
   against `^[0-9]+$`; reason codes come from a fixed enum; no `display_title`, `head_branch`, job name or `gh`
   stderr is ever echoed into an annotation, summary or output (they are attacker-controlled PR titles and branch
   names); `set -x` is forbidden in the body. A second step, `would-elide`, with `if: steps.proof.outputs.would_elide
   == 'true'`, makes the dark-phase verdict readable from the jobs API `steps[]` (a platform-reported conclusion,
   not an annotation to eyeball). Job `permissions` is exactly `actions: read`, `GH_TOKEN` appears only in the proof
   step's `env:`, and the job has no `uses:`, checkout or `secrets.*`.

The gated jobs are eight: `test-webplat`, `test-bun`, `test-scripts`, `test-scripts-heavy`, `web-platform-build`,
`shard-totality-mutations`, `e2e` and the `test` aggregator. Each gets `needs: [push-dedupe]` (for `test`, appended
to its existing list) and the canonical condition
`${{ !cancelled() && (github.event_name != 'push' || needs.push-dedupe.outputs.elide != 'true') }}`; the `test`
job keeps its `always()` instead of `!cancelled()` (`always() && (github.event_name != 'push' || ...)`), so its
status semantics off the push event are unchanged. The `test` aggregator's body, `env:` and loop stay byte-identical
(its header forbids widening the most load-bearing required check), and no tolerance arm is added: on an elided
push the aggregator itself is skipped. `test` is required for `pull_request` and `merge_group` only, never for a
push to `main`, and no consumer in the census reads a `test` row on a `main` commit.

Properties of the condition: off the `push` event it is always true, so no required context can go missing on
`pull_request` or `merge_group` (a skipped `push-dedupe` is not a failed need, because the condition carries a
status function); on `push` an empty, absent or failed output also reads as "run". The expression is pinned as one
canonical string per job; its truth table is evaluated by the suite's own evaluator, and the authoritative oracle
is the live canary on this PR's own `pull_request` and `merge_group` runs (the eight jobs run and `push-dedupe`
is skipped), because the evaluator encodes the rule it is testing.

On an elided run the live jobs are `push-dedupe` and the 14 ungated cheap guards; the run concludes `success`, so
`web-platform-release.yml`'s `workflow_run` arm sees `success` exactly as today. A comment above `push-dedupe`
and the ledger row's consequence text say: a new heavy job must join the gated set; the parity suite enforces the
set.

### Alternative compared and rejected: re-key the deploy trigger on `merge_group` (design 2)

| Criterion | Design 1 (attestation job, chosen) | Design 2 (deploy keyed on `merge_group`, drop the push run) |
|---|---|---|
| ADR-217 impact | Narrow amendment: the meaning of `WR_CONCLUSION == success` becomes "the battery ran green or an identical-SHA `merge_group` run vouched for it"; the release verdict is untouched (still the `release / release` jobs-API read) | Rewrites the Decision 2 trigger; the `workflow_run` arm would listen to a second event shape |
| Ordering | The push run exists after `main` advanced, as today | A `merge_group` completion fires before the queue fast-forwards `main`; a deploy keyed on it can run for a SHA not yet on `main` |
| Non-queue commits | Handled by construction: no `merge_group` run means no match, so the full run executes | Direct pushes and `--admin` merges have no `merge_group` run, so a push arm must be kept anyway: two arms |
| Blast radius | `ci.yml` (one job, eight conditions) | `web-platform-release.yml` (2,660 lines, identity binding, concurrency group, `release-outcome`, `notify-gated`) |
| Stop rule (ADR-276 Decision 2) | Verdict stays per SHA: the run is per SHA (per-SHA concurrency group), the proof is keyed on `github.sha` | Not applicable |

The stop rule stays binding: if the work phase finds the verdict cannot be kept per SHA (for example the first
real elided run does not conclude `success`, or `resolve-target` reacts to the skipped rows), stop, leave the
variable unset, and close the stage.

### Effect on queue-merge latency and cost (dark and live)

Off the `push` event the new job is skipped at workflow start and takes no runner, so a `pull_request` or
`merge_group` run pays no extra queue wait (the canary on this PR's own runs compares gated-job start delays with a
recent run). On `push` the gated jobs wait for `push-dedupe`, even with the variable unset: the dark merge adds one
small runner job and a serial wait to every push run's critical path. That is a timing and cost change, not a
verdict change, and the amendment says so (the Status reading in Research Reconciliation). Once live, an elided
run completes in a few minutes instead of 14 to 23, which moves the deploy trigger earlier by the same amount.

## Architecture Decision (ADR/C4)

### ADR

Two amendments, both authored in this plan's PR before the stage can take effect (the variable stays unset until
Phase 5), both append-only. No new ADR is created.

1. **ADR-276 `## Amendment 2026-10-09 (S2, #9512)`**, appended at the end of the file after the S1 amendment. It
   records: the delivered design and the rejected design 2 (the table above); the kill-switch (`CI_PUSH_DEDUPE`,
   accepted value exactly `on`, unset means run; its 30-day removal trigger from Decision 3(c)/(d) and the
   Principle Alignment carve-out); the entry gate as answered (the all-skipped conclusion is `skipped`; at least
   one real job always runs); the exit criterion and numeric target of Decision 3(e) (mean push `CI` cost over ALL
   push runs after activation, elided or not, at most 29.08 job-minutes per run, 20% of the 145.41 baseline, net of
   the attestation job, plus zero elided SHAs without a green `merge_group` run) and the stop rule; how to measure
   (the census command) and how to roll back (unset the variable for behaviour; revert the PR to remove the job
   and the conditions; the `push-dedupe` job and the `needs` edges stay until a revert); the named residual (the
   lost second sample: 8 of 94 push runs red on SHAs with a green `merge_group` run in the measured window, stated
   as a protection traded away, with the Phase 1 classification of the 8 as a measured fact, not a hope); the
   ADR-276 Status reading (merge dark under `proposed`; the dark merge changes timing and cost of push runs, not
   a verdict; activation gated on `adopting`; challengeable); the S1 evidence ownership update; the Stage status
   line (`- 2026-10-09 S2 amended`). Status stays `proposed`.
   The amendment also says in so many words that it NARROWS ADR-276 Decision 2's own sentence ("an attestation job
   that reads a `merge_group` conclusion and lets the push run conclude `success` manufactures a push verdict from
   another run's value, against ADR-217"): ADR-217's trust ladder covers the release verdict, the artifact values
   and run discovery, and the CI conclusion is only the `workflow_run` trigger, so the reconciliation is a scope
   clarification of Decision 2, not a Decision change, and it names the ejected-candidate case (a candidate that
   passed the full battery and later reaches `main` outside the queue was still tested on the identical tree).
2. **ADR-217 `## Amendment 2026-10-09 (S2, #9512)`** appended after `## References`, plus
   `amended_by: [ADR-276]` in its frontmatter (the convention used by the ADRs that already carry the key). It
   records that ADR-217's prohibition is about substituting an artifact value for the `release.result` jobs-API
   read and that this is unchanged; that the CI conclusion the deploy arm reads can now be attested by an
   identical-SHA `merge_group` run, read from the jobs API by the attestation job at run time and failing open to
   a full run; and that this is a named exception to "the verdict never crosses as a value" for the CI verdict
   only. It adds one row to the trust-ladder table for the CI gate: source is the `workflow_run` conclusion,
   attested by a jobs-API read of an identical-`head_sha` `merge_group` run, identity from `github.sha`, failing open.

Anti-truncation procedure for both (the S1 review learning): use the Edit tool at a unique anchor, not a
scripted rewrite. If a script is used, match line-start anchors with `re.M`, assert exactly one match before
cutting, then read `git diff origin/main -- <file>` and require the deletion count to be 0 for ADR-276 and
for ADR-217 apart from the one frontmatter line.

### C4 views

Read in full: `model.c4` (934 lines, read in chunks by a subagent), `views.c4` and `spec.c4`. Enumeration against
the change: (a) external human actors: none added (`founder` and `contributor` already touch `github`); (b)
external systems: none added (`github`, `ghcr`, `zotRegistry`, `sentry`, `resend`, `cloudflare`, `doppler`,
`anthropic`, `hetzner`, `sigstore` already modeled; the change alters when existing `ci.yml` jobs run); (c)
containers or data stores: none touched; (d) actor-to-surface access relationships: none changed. Hosted
runners, the merge queue, `merge_group` and `workflow_run` are not elements, so nothing is falsified; the
sentence "ci.yml real-turn gates" on the `github -> anthropic` edge describes capability, not frequency. The
derived cardinalities embedded in edge prose (`github -> sentry`: 15 workflows, 9 schedule-fired, 6
dispatch-only, 62 cron monitors, 17 and 45; `github -> resend`: fourteen emitters) move only if the new job uses
`actions/sentry-heartbeat`, a `monitor-slug:` or a Resend call, and it uses none. `plugins/soleur/test/c4-count-parity.test.sh`
was run on this branch: 13 passed, 0 failed. **No C4 edit.**

### Sequencing

The amendments are the first two commits of the work phase (before any `.github/` edit), so the record of
decisions precedes the behaviour. The stage takes effect when the variable is set to `on`, which is after merge,
after the shadow gate in Phase 5 and only on the operator's explicit go.

## Implementation Phases

### Phase 0 - Tests first (cq-write-failing-tests-before)

1. `scripts/ci-push-dedupe.test.sh`: extract-and-execute suite (below), RED against the unmodified `ci.yml`
   (no `push-dedupe` job: every parity and proof row fails; this is the failing-test commit). Register it in
   `scripts/test-all.sh` only (the `run_suite` line) in the same commit so no unregistered-suite lint fires; Phase 3
   completes the remaining registrations.
2. Extend `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`: its W2 pins exactly 6 `needs` legs, which
   becomes 6 legs plus the non-leg `push-dedupe`; add a row that the aggregator body, `env:` and loop are
   unchanged by this stage (RED until the wiring exists).

### Phase 1 - Measurement files and the two ADR amendments (before any workflow edit)

1. Commit `knowledge-base/project/specs/feat-one-shot-9512-skip-duplicate-push-ci/measurements/keying-2026-10-09.tsv`
   (per push run: run id, SHA, created, conclusion, matching `merge_group` run id and conclusion, and for the
   matched run the `test` job conclusion, which measures the coverage rate of the proof's one job check, and the
   `merge_group` run's `updated_at` against the push run's `created_at`, because the proof reads the run when
   `push-dedupe` starts: the share of matched SHAs whose `merge_group` run had already COMPLETED is the real
   eligibility rate, since the queue merges on required checks while an advisory job may still be running, and it
   enters Property 1 and the PM-2 go), produced by
   the two API reads in Research Insights written to files plus one jobs read per matched run; and
   `push-cost-baseline.tsv` (the `ci.yml` `push` STEM rows of `bash scripts/ci-demand-census.sh --start
   2026-10-07T13:04:00Z --end 2026-10-07T19:04:00Z --workflow ci.yml --summary`, fetched once; the 145.41 and 29.08
   figures are recomputed from this file by the amendment's author, not copied from this plan). Classify the 8
   push-only reds with two reads each (does the next push run on `main` fail the same job; did a re-run of the same
   SHA go green): the result is a figure the amendment's residual and the PM-2 go depend on, and it is evidence, not
   proof, of flake versus escape.
2. Append the ADR-276 S2 amendment, then the ADR-217 amendment, each with the anti-truncation procedure; read
   `git diff origin/main -- <file>` and require 0 deletions (ADR-217: 1 changed frontmatter line).
3. Run `bash scripts/check-adr-ordinals.sh` and the markdown lint for the two files; commit.

### Phase 2 - The workflow change

1. Compute the release workflow's CI budget BEFORE editing: `web-platform-release.yml`'s "Derive the CI budget
   and check for creep" step runs `run_declared_path` over `ci.yml` and `exit 1`s when the longest `needs:` path
   exceeds `CI_BUDGET_MIN`, and `scripts/prod-version-drift-check.test.sh` (B9) asserts the same arithmetic against
   `DRIFT_SUSTAINED_THRESHOLD_MIN` (225 today). Every gated job now needs `push-dedupe`, so the longest path grows by
   its `timeout-minutes`. Plan-time measurement (the release workflow's own awk run over the unedited tree): the longest
   path is 70 (`test-scripts` 60 plus `test` 10) against `CI_BUDGET_MIN` 75 (225 minus the 150 of release ceilings
   resolve-target 15, migrate 30, verify-migrations 15, deploy 90; re-verify the 90), so the slack is 5 and a
   `push-dedupe` of 5 would leave zero. The job is set to 3 (path 73, slack 2). Re-run that awk function and B9 on
   the edited tree and record both numbers in the amendment; if either goes red, move the threshold in the same
   commit per the header rule in `prod-version-drift-check.sh`.
2. Add `push-dedupe` to `.github/workflows/ci.yml` (job, step body as specified), the eight `needs` and `if` edits
   (for each of the eight, record the existing `if:` first and AND the new condition onto it; today `test` carries
   `always()` and the other seven carry none), and the comment above the job. Pin every action by the file's SHA convention (the job uses no `uses:`).
3. Raise `scripts/pr-fanout-ledger.txt` row `ci.yml` from 24 to 25; append to its consequence text: `+1
   push-dedupe (S2, #9512/ADR-276): push-only job, skipped without a runner on pull_request and merge_group; a new
   heavy job must join the gated set (scripts/ci-push-dedupe.test.sh enforces it)`. Verify
   `yaml.safe_load(ci.yml)['jobs']` is 25 (the ledger's own MERGE NOTE says to set the value from the tree).
4. Run the suite to GREEN; run `plugins/soleur/test/pr-fanout-ledger.test.sh`,
   `plugins/soleur/test/ci-concurrency-key.test.sh`, `plugins/soleur/test/workflow-run-deploy-invariants.test.sh`,
   `scripts/prod-version-drift-check.test.sh`.

### Phase 3 - Soak probe and its registration

1. `scripts/followthroughs/ci-push-dedupe-soak-9512.sh` and `.test.sh` (exit contract 0 PASS, 1 FAIL, 2 NOT YET, 3
   CANNOT ESTABLISH, 78 refused under xtrace with a token, as the sibling `pr-battery-gate-saving-9323.sh`). The
   activation time is the variable's own `updated_at` (`gh api repos/{owner}/{repo}/actions/variables/CI_PUSH_DEDUPE`);
   an unreadable variable is exit 3; an unset one is exit 2 (NOT YET, "not activated") unless any run is OBSERVED
   elided with no readable repo variable or before its `updated_at` (an org-level or environment variable), which
   is FAIL. FAIL takes precedence over NOT YET on every sweep (criterion (a) is evaluated daily, so a wrong elision
   is reported within a day, not after seven), and the probe computes the mean push cost itself from the jobs API
   with the census's counted-job definition (the census refuses live mode in CI, so the sweeper cannot call it).
   More than 30 days after the merge with the variable still unset, it exits 1 with "activate, or revert the job".
   PASS also requires an `S2-EXIT-CENSUS: <url>` marker comment on the tracker (the agent attaches the exit census,
   PM-4), because the sweeper closes the tracker itself on exit 0. Over all push runs of `ci.yml` created after it:
   (a) an "elided" run is one OBSERVED to be elided: `push-dedupe` concluded `success` and `test-scripts` concluded
   `skipped` in the run's jobs (not a self-reported annotation, which could fail to emit); each such run must have,
   recomputed independently from the `merge_group` runs listing (not by reusing the proof code), a completed
   `success` `merge_group` run with the same head SHA, else FAIL; (b) the mean runner-bound job-minutes over ALL
   those push runs, elided or not, is at most 29.08 (from the census, net of the attestation job), else FAIL; (c)
   fewer than 10 elided runs or fewer than 7 days since activation is NOT YET. It declares `secrets=GH_TOKEN`.
2. Follow-through tracker issue (filed in the work phase, before the PR is marked ready; milestone `Post-MVP / Later`,
   labels `follow-through`, `type/chore`, `domain/engineering`, `meta/machinery`, body `User-Impact:` and
   `Fix-Size:` lines) carrying the `<!-- soleur:followthrough script=scripts/followthroughs/ci-push-dedupe-soak-9512.sh
   earliest=<filing date> secrets=GH_TOKEN -->` directive (the convention says earliest is the filing date, never far
   future; the probe itself returns NOT YET until activation plus 7 days), validated by the sweeper's directive parser
   in dry-run before the PR is marked ready, and a PM-0 to PM-6 checklist in the body (owner: the ship agent for
   PM-0 and PM-1, the activating agent for PM-2 to PM-6).
   This tracker, not #9512 (closed by the PR), is where Decision 7's "post-merge census attached to the stage's own
   tracking issue" is satisfied; the deviation is recorded in the amendment, as S1 recorded its own.
3. Registrations, mirroring the S1 commit that added two suites: `scripts/test-all.sh` (`run_suite` lines appended
   last in the scripts block), `python3 scripts/regenerate-shard-manifest.py --incremental --write`
   (`scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`), and an `AFFECTED_*_PATHS` edge block in
   `scripts/lib/test-affected-paths.sh` for each new suite (the suites name `.github/workflows/ci.yml`,
   `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `scripts/pr-fanout-ledger.txt`,
   `scripts/required-checks.txt` and the ADR paths; a test naming a `knowledge-base/` path needs a covering edge
   or a row in `scripts/test-affected-kb-consumers.baseline.txt`). `ci.yml` is already owned in CODEOWNERS
   (`/.github/workflows/ci.yml @deruelle`); add `/scripts/ci-push-dedupe.test.sh` and
   `/scripts/followthroughs/ci-push-dedupe-soak-9512.sh` there too (security review: the proof and its voucher
   could otherwise be weakened by a commit that touches only the suite or the probe). Before PM-2, read the `main`
   ruleset for `require_code_owner_review` and record the result in the amendment; an admin merge bypasses
   CODEOWNERS, so the residual is detective (the probe), not preventive.

### Phase 4 - Direct pre-push verification (not `test-all.sh --affected`, which queues behind sibling worktrees)

Run detached with output to a file, then wait with the Monitor tool (an until-loop on the output file's final
marker line), never a Bash `run_in_background` poll:
`scripts/ci-push-dedupe.test.sh`, `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`,
`plugins/soleur/test/pr-fanout-ledger.test.sh`, `plugins/soleur/test/ci-concurrency-key.test.sh`,
`plugins/soleur/test/workflow-run-deploy-invariants.test.sh`, `scripts/prod-version-drift-check.test.sh`,
`scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`, `scripts/test-affected-kb-consumers.test.sh`,
`.claude/hooks/grep-q-pipe-guard.test.sh` (no new `| grep -q` pipes in `scripts/*.test.sh`; use
`| grep -cE ... >/dev/null`), `scripts/guard-vacuity-floor.test.sh`, `python3 scripts/lint-guard-contract.py <this plan>`,
`bash scripts/check-adr-ordinals.sh`, `plugins/soleur/test/c4-count-parity.test.sh`. Any suite that uses `timeout`,
`sleep`, `date` arithmetic, signals or process groups is first run 50 times under a loaded machine (one busy loop
per core) and must show 0 failures.

### Phase 5 - Post-merge (see the dedicated section)

## Guard Contract

### Guard 1 - Push-run elision (the `push-dedupe` proof, the eight conditions, the unchanged aggregator)

**Property.** A push `CI` run on `main` skips the gated jobs only when the proof step's output is the string
`true`, which it emits only for a first-attempt `push` event on `main`, with the variable exactly `on`, and a
completed `success` run of EVENT `merge_group` on a `gh-readonly-queue/main/` branch of this repository's `ci.yml`,
whose head SHA equals this run's SHA and whose `test` job concluded `success`; on every other event or state every gated job runs and the aggregator classifies results exactly as before.

**Assembly.** The chokepoint for the decision is the single `elide` output of the `push-dedupe` step: nothing
else may skip a gated job on the push event. Three structures must agree, and the suite derives each from the
parsed `ci.yml`, not from a remembered list: (1) the set of jobs whose `if:` references
`needs.push-dedupe.outputs.elide` (the gated set, eight today) against a pinned constant in the suite, in both
directions, so a missing condition and an extra one each fail; (2) the `needs:` of every gated job contains
`push-dedupe`, and the `test` aggregator's body, `env:` and loop are byte-identical to the pinned digest (no
tolerance arm exists to drift); (3) the proof's coverage claim: it demands only the `test` job, which is sound
because the aggregator concludes red on any `skipped` leg, so the suite also executes the extracted aggregator
body over a `merge_group` triple with one leg `skipped` and requires a non-zero exit (the coupling is pinned at
its source). A fourth structure is the guard's reach into other jobs: none of the eight gated jobs may carry
`continue-on-error: true` (other jobs in the file do, e.g. `harness-discovery`, and are out of scope), and none of the
seven gated jobs outside the aggregator's `needs` (`e2e`, `shard-totality-mutations`, and the legs the run
conclusion alone vouches for) may gain an `if:` other than the elision condition, because a later `if:` that skips
them on `merge_group` would make a `success` run vouch for a leg that never ran. Consumers that read the resulting run conclusion are a census (Research Insights), not a
recollection. Event shapes: `push` (main first attempt, main re-run, other ref), `pull_request` (including fork),
`merge_group`, `workflow_dispatch`. Value shapes of the variable: unset, empty, `on`, `ON`, ` on `, `On`, `true`,
`1`. Proof-input shapes: no `merge_group` run, several runs (a re-run), a run for another SHA returned by a lagging
search, a run on another branch prefix, an `in_progress` or `cancelled` or `failure` or `skipped` conclusion, the
`test` job missing, skipped or failed, a listing that truncates before `test`, a `gh` failure or hang on either
read, malformed JSON.

**Mutation matrix.**

| # | Mutation (must go RED) | Targets |
|---|---|---|
| 1 | Accept the variable as `ON`, ` on `, `On`, `true`, `1`, empty or unset (one run per value) | only the exact string `on` enables elision |
| 2 | Drop the `EVENT_NAME == push`, the `REF == refs/heads/main` or the `RUN_ATTEMPT == 1` refusal (one at a time), with everything else true; include `EVENT_NAME` values `pull_request`, `merge_group` and `workflow_dispatch` | elision exists only on a first-attempt push to `main`; a dispatched full run is never elided |
| 3 | Accept `in_progress`, `cancelled`, `failure` or `skipped` as the `merge_group` conclusion | only a completed `success` run counts |
| 4 | Drop the client-side `head_sha ==` re-check (feed a lagging search that returns a run for another SHA) | the search parameter is advisory; the re-check is the proof |
| 5 | Drop the `gh-readonly-queue/main/` branch-prefix check (feed a green run on another branch with the right SHA) | only a queue run vouches |
| 6 | Treat the `test` job as covered when it is missing, `skipped`, or only a `test-scripts`-prefixed job exists | the empty-haystack and prefix-collision class |
| 7 | Make the `gated_empty`-style dispatch vacuous: extract zero `push-dedupe` steps, or an empty gated set, and expect the suite to pass | the suite's own dispatch refuses 0 checked and counts the executed proof rows against the reason codes (an independent producer count) |
| 8 | Add a ninth job with the condition, or remove it from one of the eight, or leave `push-dedupe` out of one gated `needs:` | parity in both directions, and a check that does not stop at the first member |
| 9 | Replace `!cancelled()` by `success()` (or drop it) in one gated condition; drop the `github.event_name != 'push'` disjunct (a defence-in-depth row: on reachable states `elide` is empty off push, so it goes red only on the synthetic (`pull_request`, `elide=true`) row) | off the push event a skipped `push-dedupe` must not skip a required context; the live canary is the authoritative oracle for this row |
| 10 | Edit the aggregator: tolerate `skipped` for a gated leg, add an `ELIDE` env, or add an arm | the aggregator stays byte-identical, and the proof's one-job coverage claim stays true |
| 11 | REORDER: write `elide=true` before the `test` job check or before the variable check, with a `gh` stub that fails the jobs read (the property is about ORDER: the true value is written last, observed inside the window) | `elide=true` is the last write |
| 12 | Move the default `elide=false` write after the first `gh` call; remove `continue-on-error: true`, the step-level `timeout-minutes`, or the job output mapping (asserted statically on the parsed YAML, since a runner step cannot be killed from the harness) | a failed or hung proof is a full run, never a red run (a job-level failure, such as a lost runner, is an accepted fail-closed path: the gated jobs still run and the deploy waits on a red run) |
| 13 | Drop the `event == merge_group`, the `head_repository.full_name` or the `path` re-check: feed a green `pull_request` run, then a green `workflow_dispatch` run, each on a branch named `gh-readonly-queue/main/x` with the right SHA and `test` success; and a harness row that removes `event=merge_group` from the query so only the client-side check can carry the proof | a branch name an author controls cannot vouch; the server-side filter is not the proof |
| 14 | Feed `display_title` and `head_branch` set to `x\nelide=true` and `::error::pwn`, and a `gh` stderr containing a newline | `$GITHUB_OUTPUT` holds exactly one `elide=` line whose value matches the verdict, `mg_run` matches `^[0-9]+$`, and no fixture string reaches an annotation, summary or output |
| 15 | Static pins on the parsed YAML: job `permissions` other than exactly `{actions: read}`; `GH_TOKEN` in any env but the proof step's; a `uses:`, checkout or `secrets.` reference in the job; `set -x` in the body; a gated job with `continue-on-error`; a non-gated-set job gaining the condition | least privilege and the reach of the guard |

Harness rows: replace the extracted proof body with a stub that prints `elide=true` (the suite must fail on the
must-be-false rows); replace the `gh` shim with one that returns the canonical fixture for every call (rows 3 to 6
must still fail, proving the shim is routed and not a catch-all). Must-PASS inputs that are NOT the canonical
fixture and that the contract permits: two `merge_group` runs for the SHA (an older `failure` and a newer
`success`, in reverse listing order); a green run whose job list is in a different order and carries an extra
advisory job concluding `skipped`; the variable `on` with surrounding quotes stripped by the Actions env mapping.

**Anchor.** The proof compares a live API reading, not a stored value, so no stored-value anchor applies. The
independent anchors are: the soak probe's recomputation from the runs listing (a different code path) over
OBSERVED job conclusions, the release verdict that this change does not touch (the `release / release` jobs-API
read keeps the deploy per SHA), and CODEOWNERS review of `.github/workflows/ci.yml` (`/.github/workflows/ci.yml
@deruelle`), which is the control against a commit that weakens the proof and the `merge_group` run together,
because both read the same file. That limit is stated, not closed: the `merge_group` run uses the candidate's own
`ci.yml`.

### Guard 2 - The soak probe verdict

**Property.** The probe exits 0 only when at least 10 elided push runs and 7 days since the variable's activation
are observed, every elided run (observed from job conclusions) has an independently recomputed green `merge_group`
run for its SHA, and the mean push `CI` cost over all push runs since activation is at most 29.08 job-minutes per
run; absence of evidence is never a pass.

**Assembly.** One script, `scripts/followthroughs/ci-push-dedupe-soak-9512.sh`; its inputs (the variable's
`updated_at`, the push runs listing, each run's jobs, the `merge_group` listing, the census figure); and the
sweeper contract (`scripts/followthroughs` exit codes 0, 1, 2, 3 and 78). Every API read is a member of the
assembly; a read that fails is exit 3, never a quiet zero.

**Mutation matrix.**

| # | Mutation (must go RED) | Targets |
|---|---|---|
| 1 | Zero elided runs in the window returns 0 | the probe's own dispatch: zero checked is NOT YET (2), never PASS |
| 2 | An elided run whose SHA has no `success` `merge_group` run returns 0 | the independent recomputation |
| 3 | A second elided run lacking a match after a compliant first returns 0 | a check that stops at the first member |
| 4 | Compute the mean over elided runs only (about 8.5) so a window dominated by non-elided runs above 29.08 returns 0; flip the comparison so 29.08 returns non-zero | the criterion is over ALL push runs; 29.08 itself is a must-PASS row |
| 5 | A `gh` failure on the jobs, variable or listing read returns 0 or 1 | exit 3, the sweeper retries |
| 6 | Take "elided" from the `ci-push-dedupe` annotation instead of observed job conclusions (feed a run with gated jobs skipped and no annotation) | the probe cannot go blind when the annotation fails to emit |
| 7 | Feed an elided run with the repo variable unset or `updated_at` later than the run (an org-level variable); feed NOT YET conditions together with a wrong elision | FAIL, and FAIL takes precedence over NOT YET |
| 8 | Feed 10 clean elided runs, 7 days and a mean of 20, with no `S2-EXIT-CENSUS:` marker comment | exit 2, not PASS (the sweeper closes the tracker on exit 0) |

Harness rows: replace the recomputation with a stub that always matches (the suite must fail row 2); must-PASS
input differing from the canonical: elided runs listed newest-first and a `merge_group` listing split across two
pages.

**Anchor.** The thresholds (10 runs, 7 days, 29.08) are constants in a script that a single commit could edit
together with the code that checks them; the independent anchor is the ADR-276 S2 amendment, which states the same
numbers and is reviewed as an ADR edit (a merge-base diff of the amendment line shows a weakening).

## Observability

```yaml
liveness_signal:
  what: the push-dedupe job of every push CI run on main (job conclusion, and the ci-push-dedupe annotation with elide, would_elide, reason code and merge_group run id), plus the soak follow-through probe
  cadence: every push run (about 25 per day measured) and the daily follow-through sweep
  alert_target: the S2 follow-through tracker issue (follow-through label) and the existing release-outcome and notify-gated Slack and email channels for a non-delivered deploy
  configured_in: .github/workflows/ci.yml (push-dedupe job) and scripts/followthroughs/ci-push-dedupe-soak-9512.sh
error_reporting:
  destination: workflow annotations (notice with a reason code; a warning on an API failure) and the follow-through sweeper comment
  fail_loud: false for the proof step by design (a failed proof must run the full battery, never redden the run); true for the soak probe (exit 3 on an unreadable source)
failure_modes:
  - mode: a push run is elided for a SHA with no green merge_group run
    detection: layer 6 (workflow run log and jobs API): the soak probe recomputes the match from the runs listing for every run it OBSERVES as elided (gated jobs skipped), evaluated on every sweep; the proof suite pins the refusal rows
    alert_route: probe FAIL on the tracker issue; the agent unsets CI_PUSH_DEDUPE
  - mode: the proof never elides (API errors, search lag, queue method change) so the saving silently disappears
    detection: layer 6 (workflow run log and jobs API): the mean push CI cost over all push runs (criterion b of the probe), the `would-elide` step conclusions in the jobs API, and a `::warning::` with reason `proof_error` on any API failure
    alert_route: probe FAIL or NOT YET on the tracker; the share of elided runs is printed with the verdict
  - mode: an elided run concludes success but the deploy arm does not fire or clean-skips with ci_not_green
    detection: layer 6 (workflow run log): PM-0 and PM-3 check the resolve-target outcome for the SHA; ongoing, the existing release-outcome `ci_not_green` non-delivery classification (Slack and email), whose paging on this state the work phase confirms by reading the job before activation
    alert_route: notify-gated and release-outcome Slack and email
  - mode: a defect that the removed second sample would have caught reaches main
    detection: layer 6 does not apply (undetectable by construction after activation); the pre-change rate (8 of 94, classified in the measurement file) is the recorded baseline
    alert_route: named residual in the ADR amendment and the operator's go at PM-2; S5 (#9730) decides whether a scheduled full run on main is worth its cost
logs:
  where: GitHub Actions run logs and check-run annotations; measurement files committed under the feature spec directory
  retention: GitHub default run retention (90 days); the committed measurement files do not expire
discoverability_test:
  command: grep -c -e 'if: .*needs.push-dedupe.outputs.elide' .github/workflows/ci.yml
  expected_output: 8
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed (carry-forward plus a plan-review devex pass)
**Assessment:** The CTO agent reviewed the staged rollout and the S2 row in the parent plan (PR #9722) and the
ADR-276 Decision 2 comparison of the two designs. This plan resolves that comparison in favour of the keyed
attestation job, adds the second-sample finding the parent plan did not have (8 of 94 push runs red on
queue-merged SHAs), and keeps activation behind an explicit go and the ADR reading `adopting`. The plan-review
devex pass asked for: the second sample stated as a protection traded away (done in the amendment text), a
measured fact rather than a hope about the 8 reds (Phase 1 classification), the Status question at the top of the
PR body (Acceptance Criteria), and a note that a new heavy job must join the gated set (comment and ledger text).
The remaining CTO-owned decision is the `proposed` to `adopting` flip, recorded as a User-Challenge in
`knowledge-base/project/specs/feat-one-shot-9512-skip-duplicate-push-ci/decision-challenges.md`.

No product, UX, marketing, legal, finance, sales or support surface is touched. No new vendor, store or
connection is introduced (the job reads the repository's own Actions API with the workflow token). No UI path
appears in Files to Create or Files to Edit, so the mechanical UI-surface override does not fire.

## User-Brand Impact

- **If this lands broken, the user experiences:** an unverified commit reaches the deployed web app because a
  push run was elided without a vouching run, or a deploy that never fires because the elided run did not conclude
  `success`; the first is bounded by the proof requiring a green full-battery run of the identical SHA and by
  failing open to a full run, the second by the first-run canary and the stop rule.
- **If this leaks, the user's workflow is exposed via:** no data surface; the job holds a read-only `actions`
  token and reads run metadata of the same public repository.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the change moves when an already-passed battery re-runs, not who can
  read what; the exposure needs a wrong `true` from the proof, which the matrix and the independent probe
  recomputation guard, and which the unchanged `release / release` verdict would not catch. A single-user incident
  needs a data or credential surface, which this stage does not touch.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement S2 of ADR-276 ... issue #9512 — skip the duplicate push-to-main CI run when a merge_group run already passed on the same SHA." | Proposed Solution, Phase 2 | mapped |
| 2 | "PR (draft #9808 already exists) body must contain "Closes #9512"" and end with the Claude Code line | Acceptance Criteria (Pre-merge) | mapped |
| 3 | "Append a dated ADR-276 S2 amendment BEFORE the stage takes effect (ADR stays "proposed")" | Architecture Decision, Phase 1 | mapped |
| 4 | "after any scripted rewrite run `git diff <base> -- <file>` and check deletion count, anchor cuts on line-start matches and assert one match" | Architecture Decision (anti-truncation procedure), Phase 1 | mapped |
| 5 | "S2 also OWNS the post-merge evidence S1 deferred: run scripts/ci-demand-census.sh over a closed post-merge window (>= 6 h ...) and report smoke ran/skipped/runnerless split ... plus the 80% net criterion; attach to #9727 and #9512" | Post-merge PM-1 | mapped |
| 6 | "Never cd into the main checkout ... leave its uncommitted .mcp.json and staged scripts/followthroughs/watchdog-debounce-soak-9686.sh alone" | Constraints (all commands run from the worktree) | mapped |
| 7 | "poll with the Monitor tool, never Bash run_in_background; no git stash, no force-push; provision nothing for lever 5" | Phase 4, Constraints | mapped |
| 8 | "Pre-push the work phase must run directly (detached, output to a file ...): scripts/test-affected-kb-consumers.test.sh, .claude/hooks/grep-q-pipe-guard.test.sh ..., scripts/guard-vacuity-floor.test.sh, plus own suites" | Phase 4 | mapped |
| 9 | "A new test naming a knowledge-base path needs a covering edge in scripts/lib/test-affected-paths.sh or a row in scripts/test-affected-kb-consumers.baseline.txt" | Phase 3 item 3 | mapped |
| 10 | "Signal/clock/process-group tests need a loaded-machine loop before commit" | Phase 4 | mapped |
| 11 | "Recompute every figure an ADR decision depends on from committed data" | Phase 1 item 1 (measurement files) | mapped |
| 12 | "commits end with "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"" | Acceptance Criteria (Pre-merge) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `push-dedupe` job, gated conditions | "skip the duplicate push-to-main CI run when a merge_group run already passed on the same SHA" | asked (ask 1) |
| Variable `CI_PUSH_DEDUPE` and the `would_elide` annotation | "Dark launch behind a repository variable" (issue comment 6045271231) | asked (the issue's precondition 4) |
| Soak probe, its suite and the follow-through tracker | "dark launch behind a repository variable ... 7 days ... Exit: zero SHAs elided without a green `merge_group` run" (ADR-276 stage table S2 row) | asked (ADR-276); the probe is the enrollment `soleur:plan` Phase 2.9.1 requires for a soak-gated close |
| Measurement files | "Recompute every figure an ADR decision depends on from committed data" | asked (ask 11) |
| Classification of the 8 push-only reds | "Recompute every figure an ADR decision depends on from committed data" | asked (ask 11): the ADR residual states the 8-of-94 figure and its meaning, so the figure's interpretation is part of what the decision depends on |
| ADR-217 amendment | "Both S2 designs change ADR-217, so S2's PR appends an ADR-217 amendment whichever wins" (ADR-276 Decision 2) | asked (ADR-276) |

### Split Assessment

- Subsystems touched: 4 roots (`.github`, `scripts`, `plugins`, `knowledge-base`)
- Planned files: 20 | Estimated changed lines: about 1,600 (the proof suite about 900, the probe and its suite about 400, `ci.yml` about 100, ADR prose about 120, registrations about 50)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. The root count and the line estimate cross the thresholds, but the pieces are one
  mechanism (the proof and its conditions cannot ship without the suite that pins them, nor the probe without
  the jobs it reads), the registrations are mechanical, and the stage is one lever per PR by ADR-276 design. A
  split would put the workflow change in a PR whose guard lives in another.

## Files to Create

- `scripts/ci-push-dedupe.test.sh` (proof body extracted and executed, parity, truth table, matrix)
- `scripts/followthroughs/ci-push-dedupe-soak-9512.sh`
- `scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh`
- `knowledge-base/project/specs/feat-one-shot-9512-skip-duplicate-push-ci/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9512-skip-duplicate-push-ci/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-9512-skip-duplicate-push-ci/measurements/keying-2026-10-09.tsv`
- `knowledge-base/project/specs/feat-one-shot-9512-skip-duplicate-push-ci/measurements/push-cost-baseline.tsv`

## Files to Edit

- `.github/workflows/ci.yml` (the `push-dedupe` job, eight gated jobs including the `test` aggregator's `needs` and `if` only)
- `scripts/pr-fanout-ledger.txt` (row `ci.yml` 24 to 25)
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` (W2 cardinality and the byte-identity row)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (append the S2 amendment and one Stage-status line; Status stays `proposed`)
- `knowledge-base/engineering/architecture/decisions/ADR-217-the-deploy-fires-on-cis-completion-event-and-the-verdict-never-crosses-as-a-value.md` (append the amendment, add `amended_by`)
- `scripts/test-all.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/lib/test-affected-paths.sh`, `scripts/test-affected-kb-consumers.baseline.txt` (registrations; the baseline only if the covering-edge route is not enough)
- Read in Phase 2 and edited only if they assume a ran `test` job or a full push run: `scripts/followthroughs/pr-battery-gate-saving-9323.sh`, `scripts/followthroughs/ci-leg-balance-9232.sh`, `scripts/followthroughs/deploy-script-tests-legs-8736.sh`, `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`, `plugins/soleur/skills/postmerge/SKILL.md`; run, not edited: `scripts/prod-version-drift-check.test.sh`

## Acceptance Criteria

### Functional Requirements

#### Pre-merge (PR)

- [ ] The PR body's first line answers "does merging THIS alone mutate production?": it adds one small job to every push run and gates eight jobs on its output, which changes push-run structure, timing and the release workflow's declared CI path, but moves no verdict and elides nothing while `CI_PUSH_DEDUPE` is unset (activation is the separate, authorized step). It then carries the ADR-276 Status question (merge dark under `proposed`, activation gated on `adopting`, the CTO flip pending), then `Closes #9512`, and ends with the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; every commit ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- [ ] The ADR-276 S2 amendment and the ADR-217 amendment exist, were committed before the first `.github/` edit (`git log --reverse --format=%h -- <ADR files> .github/workflows/ci.yml` lists the ADRs first), ADR-276 `status:` is still `proposed`, and `git diff origin/main -- <each ADR>` shows 0 deleted lines (ADR-217: the one frontmatter line).
- [ ] `grep -c -e 'if: .*needs.push-dedupe.outputs.elide' .github/workflows/ci.yml` prints 8 (one single-line `if:` per gated job; the discoverability command), `grep -cE '^  push-dedupe:' .github/workflows/ci.yml` prints 1; `yaml.safe_load(ci.yml)['jobs']` has 25 entries equal to the `ci.yml` ledger row; `plugins/soleur/test/pr-fanout-ledger.test.sh` passes.
- [ ] Every one of the eight gated jobs carries the canonical condition and `needs` containing `push-dedupe`; the aggregator body, `env:` and loop are byte-identical; the proof step carries `continue-on-error: true`, a step-level timeout and `GH_TOKEN` (suite parity rows green, both directions).
- [ ] The release workflow's CI budget is computed before and after: `bash scripts/prod-version-drift-check.test.sh` (B9) passes and the `push-dedupe` `timeout-minutes` leaves the longest `needs:` path within `CI_BUDGET_MIN`.
- [ ] With the variable unset the push run is unchanged in verdict: this PR's own `pull_request` run and the queue's `merge_group` run are green with `push-dedupe` skipped (no runner) and the eight gated jobs run, with job `started_at - created_at` no later than the median of the last 5 runs plus 60 seconds (read with `gh run view --json jobs`); this canary is the authority for the `event != push` half of the condition, not the suite's evaluator, and it says nothing about the push half, which PM-0 covers on `main`.
- [ ] This PR's own `secret-scan.yml` `pull_request` run shows `smoke-relevance` succeeded and the `smoke (...)` row skipped (S1's false arm, handoff step 2), provided the PR touches no subject path; run id recorded on #9727 and #9512.
- [ ] `python3 scripts/lint-guard-contract.py` passes on this plan (2 guard entries), `bash scripts/check-adr-ordinals.sh` passes, `bash plugins/soleur/test/c4-count-parity.test.sh` passes (no C4 edit).
- [ ] The Phase 4 suites pass when run directly, output kept in a file; the loaded-machine loop (50 runs, 0 failures) is recorded for any suite using `timeout`, `sleep`, `date` arithmetic, signals or process groups.
- [ ] The follow-through tracker issue exists with the directive and `follow-through` label.
- [ ] The ADR-276 Status reading is handled: either the CTO approval comment exists and the amendment cites it, or the amendment states that the PR merges dark under `proposed` and that activation waits for `adopting`; ship surfaces `decision-challenges.md`.

#### Post-merge (Phase 5; each item has a command and an expected result)

- [ ] PM-1 S1 evidence census (below) attached to #9727 and #9512.
- [ ] PM-0 first push run on `main` verified; PM-2 shadow gate passed and the variable activated on an explicit go; PM-3 first-run canary green; PM-4 7-day soak and exit census attached to the tracker (the `S2-EXIT-CENSUS:` marker the probe requires); PM-5 status lines appended by a docs-only PR; PM-6 is the rollback path, exercised only on a stop.

### Non-Functional Requirements

- [ ] Fail-open everywhere the proof is uncertain: no row of the matrix lets an unknown produce `elide=true`.
- [ ] No new `${{ ... }}` interpolation of untrusted input into a `run:` script: the variable and the event fields enter through `env:`.
- [ ] NFR register assessment (`soleur:architecture assess`): no change to a recorded NFR (availability of the deploy path is unchanged by construction; the stop rule covers the one way it could change).

### Quality Gates

- [ ] The suites carry an independent producer count and a positive control; `scripts/guard-vacuity-floor.test.sh` passes with the new suites registered.
- [ ] Review (`soleur:review`) and the founder-stated check are handled by the ship pipeline.

## Post-merge follow-through (Phase 5)

Nothing here blocks the merge; each item is an agent task with a command, and the one authorization-gated step is
named. PM-1 does not depend on S2's own mechanism and does not gate PM-2 to PM-4.

- **PM-0 - the push path, first run on `main` (owner: the ship agent, immediately after the merge).** The pre-merge
  canary on this PR's `pull_request` and `merge_group` runs exercises only the `event != push` half of the condition;
  the push half first runs on `main`, and a job-level failure there turns the run red and blocks that SHA's deploy
  (`ci_not_green`). Command: `gh run list --workflow ci.yml --event push --branch main -L 1 --json databaseId,conclusion`,
  then `gh run view <id> --json jobs`. Expected: `push-dedupe` succeeded, the `would-elide` step recorded, the reason
  `switch_off`, all eight gated jobs ran, the run concluded `success`, and `resolve-target` did not report
  `ci_not_green`. On any deviation: revert the PR at once.
- **PM-1 - S1 evidence (owned by S2).** After the S2 PR merges, run over a closed window that started at or after
  2026-10-09T01:11:37Z (runs started earlier used the old `secret-scan.yml`): at least 6 hours, for example
  `bash scripts/ci-demand-census.sh --start 2026-10-09T02:00:00Z --end 2026-10-09T08:00:00Z --workflow secret-scan.yml
  --summary > /var/tmp/ci-census-s1.txt` (that window is already closed at plan time; `--end` is exclusive, at most
  12 hours per window; a 6 h window takes about 15 minutes, so wait with the Monitor tool on the output file). Then
  `grep -E '^(REPO|WINDOW|TOTAL|RUNS|JOBS|WORKFLOW)|^STEM'$'\t''secret-scan'` on it, check `wc -c` under 60000, and
  post inside a fenced text block on #9727 and #9512: the `STEM secret-scan.yml pull_request smoke` and
  `smoke-relevance` rows (ran, skipped, runner-less split) and the KEY lines. Compute the 80% net criterion as in
  the S1 amendment: (`smoke` + `smoke-relevance` minutes) / completed `secret-scan.yml` `pull_request` runs, against
  the 0.584 job-minutes per run target (80% below the 2.92 baseline); report it with the hit share and skip share.
  The S1 amendment asks for at least 48 hours or 100 pull-request runs: if the 6 h window has fewer than 100 runs,
  label the result preliminary and extend with consecutive non-overlapping windows (sum `TOTAL_JOB_SECONDS` and the
  `runs_*` columns, recompute per-run figures from the sums) until the floor is met, then post the extension.
- **PM-2 - shadow gate, then activation.** With the variable unset, every push run already annotates `would_elide`.
  When at least 10 push runs after the merge have annotations over at least 24 hours (about 25 push runs per day
  are measured, so the 10-run floor alone could miss a quiet period), and an independent recomputation shows zero
  `would_elide=true` without a green `merge_group` run and `would_elide=true` for every queue-merged SHA whose
  `merge_group` run was green, post the evidence together with the Phase 1 classification of the 8 push-only reds
  and ask for the operator's explicit go (`hr-menu-option-ack-not-prod-write-auth`: plan approval is not
  authorization to change what the deploy gate trusts). Before asking, read the `main` ruleset for
  `require_code_owner_review` and report the result. A reproducible push-only red (the same job fails on the next
  push run) means do not activate until User-Challenge Taste 1 is answered. On the go, and only if ADR-276 reads
  `adopting`, the agent runs `gh variable set CI_PUSH_DEDUPE --body on --repo jikig-ai/soleur` (repository scope, never `-o`/`--org`),
  reads it back with `gh variable get` and requires exactly `on`, and comments the `updated_at` on the tracker.
- **PM-3 - first-run canary.** The first push run with `elide=true` after activation (a direct push or `--admin`
  merge is a full run and does not exercise elision): `push-dedupe` annotation `elide=true` with a
  `merge_group` run id; the `CI` run `success`; the `web-platform-release.yml` `workflow_run` arm resolved to a
  deploy or to its normal path clean skip, never `ci_not_green`; `deploy-arm.sh` reports `CI=success`. On any
  deviation: `gh variable delete CI_PUSH_DEDUPE` and apply the stop rule.
- **PM-4 - soak and exit census.** The follow-through sweeper runs the probe daily; at exit, run the census for
  `--workflow ci.yml` over the soak (consecutive windows), compute the mean push `CI` cost against 29.08, attach to
  the tracker; on PASS append `S2 live`.
- **PM-6 - rollback.** `gh variable delete CI_PUSH_DEDUPE --repo jikig-ai/soleur`, read back, then comment the
  deletion time on the tracker and close it as stopped. In-flight runs are safe (the variable is read once at
  `push-dedupe` start; an already written `elide=true` still has its green `merge_group` run; a job not yet started
  reads it as unset). The dark `push-dedupe` job then keeps costing one small serial job per push run, so the
  stop rule also files a revert PR with an owner and a date; the 30-day removal clock does not start without
  `S2 live`.
- **PM-5 - status lines.** One docs-only PR appends to the ADR-276 Stage status list: `S1 live` (citing the PM-1
  comment) or `S1 criterion not met` with the figures, then `S2 live` after PM-4. The variable's 30-day removal
  trigger starts at `S2 live`, owned by the agent that appends that line (a dated comment on the tracker).

## Test Scenarios

### Acceptance Tests (RED phase targets)

1. Proof body, canonical fixture (one green `merge_group` run, `test` job `success`, variable `on`, first-attempt push on main): `elide=true`, reason `ok`.
2. Same fixture with the variable unset: `elide=false`, `would_elide=true`, reason `switch_off`.
3. The Guard 1 matrix rows 1 to 12 each produce their expected verdict; every reason code is reached at least once.
4. Aggregator extracted body over a `merge_group` triple with one gated leg `skipped`: non-zero exit (the coupling the proof relies on).
5. Truth table of the canonical condition over (event, elide, need result): true on every non-push row.
6. Parity: parsed gated set equals the pinned set of eight; the aggregator body digest is unchanged.

### Regression Tests

- `ci-test-aggregator-diagnosis.test.sh` existing rows unchanged in outcome (W2 now counts the non-leg need); `pr-fanout-ledger.test.sh`, `ci-concurrency-key.test.sh`, `workflow-run-deploy-invariants.test.sh`, `prod-version-drift-check.test.sh` unchanged in outcome.

### Edge Cases

- A re-run of a push run ("re-run all jobs" is never elided, reason `rerun`; "re-run failed jobs" of an already elided run keeps the skipped gated jobs skipped and does not re-run `push-dedupe`, documented in the amendment and the `settle-then-admin-merge` doc; each completed attempt re-fires `workflow_run`, existing behaviour that PM-3 confirms causes no double deploy); a squash-method change (SHA no longer equal: reason `no_mg_success`, full run); a `merge_group` run older than log retention; two pushes in quick succession (separate per-SHA groups); a `workflow_dispatch` full run (never elided).

### Integration Verification (for `soleur:qa`)

- **Pre-merge, on the PR's own runs:** `gh run view <pr-or-merge-group-run> --json jobs` shows `push-dedupe` skipped and the eight gated jobs run.
- **Post-merge:** PM-2 and PM-3.

## Risks and Sharp Edges

- **The second sample is lost.** 8 of 94 push runs were red on queue-merged SHAs (flake or escape, classified in Phase 1). After activation a SHA that would have shown red deploys instead. This is the cost of the stage, recorded as a named residual and as a protection traded away; S5 (#9730) owns whether a scheduled full run on `main` is worth buying back, and the operator decides at PM-2 with the classification in hand.
- **The release workflow's CI budget reads `ci.yml`'s structure.** `push-dedupe` lengthens the longest declared `needs:` path (70 today) by its `timeout-minutes`; the budget step hard-fails the deploy arm if the path exceeds `CI_BUDGET_MIN` (75 today), and B9 in `prod-version-drift-check.test.sh` asserts the same arithmetic. The current slack is 5, so a 5-minute job leaves zero and any later bump of `test-scripts` or `test` trips the deploy gate; the job is set to 3. The awk reads only `timeout-minutes: N` alone on a line.
- **A hung proof must not redden the run.** A job timeout concludes the run `failure` and blocks the deploy (`ci_not_green`); the step carries its own timeout and `timeout 20` around each `gh` call, and `continue-on-error`.
- **A required context left pending is the worst failure.** The condition's `!cancelled()` (and `always()` for `test`) and `github.event_name != 'push'` terms exist for that; mutation row 9 pins them and the live canary on this PR's own runs is the oracle. `ci.yml`'s header forbids event gates on required jobs: this is not one (it is true on every event except an elided push).
- **`needs` on a skipped job.** Without a status function in the `if:`, a gated job whose need was skipped is itself skipped, which on `pull_request` would drop every required context. Row 9.
- **One-job coverage couples the proof to the aggregator.** If a later stage lets the aggregator tolerate `skipped` on `merge_group`, the proof must regain a per-stem check; Guard 1 assembly item 3 and row 10 pin the coupling.
- **The `merge_group` run may still be running when the push run starts.** The queue merges on required checks while an advisory job can still be in progress; the proof then reads `no_mg_success` and the push run is full (safe), but the eligible share can be lower than the 92 of 94 final-conclusion match. Phase 1 measures the share completed before the push run was created, and the 15.0% break-even and the PM-2 go use that share.
- **GitHub search lag** can only hide a match (a full run). The shadow phase measures the miss rate; no fallback listing is built.
- **Squash-method dependency.** SHA equality between the queue candidate and `main` holds because the queue fast-forwards with `merge_method = SQUASH`; a method change makes every push run a full run (safe) and is visible as a probe criterion (b) failure.
- **`merge_group` runs use the candidate's `ci.yml`.** A PR that weakens the proof also weakens the run that vouches for it; CODEOWNERS on `ci.yml` is the control, stated in the Anchor.
- **Variable semantics.** Accepted value exactly `on`, compared in the shell (the Actions `==` is case-insensitive); the variable enters through `env:`, never inline in `run:`; no Terraform resource manages it (the ADR-276 AP-001 carve-out); 30-day removal trigger from `S2 live`.
- **Ledger.** Set the `ci.yml` row from the tree (`yaml.safe_load(...)['jobs']`), not by adding one to a remembered number; the row's MERGE NOTE records why.
- **Followthrough probes that sample push runs** (`ci-leg-balance-9232`, `deploy-script-tests-legs-8736`) lose elided runs from their sample; they must report NOT YET, not red, when their sample shrinks.
- **A plan whose `## User-Brand Impact` section is empty, omits the threshold, or contains placeholder text fails `deepen-plan`.** This one carries all three lines.
- **Constraints for the work phase.** Run every command from the worktree; do not touch the main checkout's uncommitted `.mcp.json` or its staged `scripts/followthroughs/watchdog-debounce-soak-9686.sh`; no `git stash`; no force-push; provision nothing for lever 5.

## Plan Review Outcome

Panel: DHH, Kieran, code-simplicity (per mechanism) and the CTO agent under a devex lens (brand-survival
threshold `aggregate pattern`: three-agent baseline plus the named devex reviewer).

| Finding | Source | Class | Disposition |
|---|---|---|---|
| Release workflow's CI budget step and B9 read `ci.yml`'s `needs:` structure; the new job lengthens the longest path | Kieran | mechanical | Applied: consumer census row, Phase 2 step 1 (compute slack first), B9 in Phases 2 and 4, Risks |
| A hung proof can still redden the run (job timeout), `GH_TOKEN` and repo missing from the step env | Kieran | mechanical | Applied: step-level timeout, `timeout 20` per `gh` call, env list, matrix row 12 |
| Probe takes "elided" from the annotation; criterion (b) ambiguous; no activation source | Kieran, CTO | mechanical | Applied: elided is observed from job conclusions, mean over ALL push runs, activation from the variable's `updated_at`; Guard 2 rows 4 and 6 |
| Drop the aggregator tolerance arm; gate `test` itself | DHH | mechanical | Applied: eight gated jobs, aggregator byte-identical, Guard 1 row 10 |
| Replace the per-stem loop with the `test` job check | DHH, simplicity | mechanical | Applied, with the coupling pinned (assembly item 3, row 10) |
| Prune overlapping matrix rows | DHH, simplicity | mechanical | Applied: 16 rows to 12; row 9 marks the `event != push` disjunct as defence in depth |
| Require `run_attempt == 1` for elision | Kieran | taste | Applied (cheap, fails toward a full run) |
| Fold the PM-2 shadow gate into PM-4 | DHH, simplicity | taste | Not applied: PM-2 is the single explicit operator go (`hr-menu-option-ack-not-prod-write-auth`) and the only gate before the deploy trigger changes; wording tightened (10 runs over 24 hours) |
| Drop the 8-red classification as unasked | DHH, simplicity | taste | Not applied: asked via "recompute every figure an ADR decision depends on"; the classification feeds the residual and the PM-2 go (CTO and Kieran asked for it as a gate) |
| Drop or shrink the soak probe | DHH, simplicity | taste | Not applied: a soak-gated close needs an enrolled probe (plan Phase 2.9.1, ship Phase 5.5); shrunk to four-to-six rows and the ADR-pin ceremony removed |
| Drop the CODEOWNERS line | simplicity | mechanical | Applied |
| Maintenance cost of three hand-synced structures; comment and ledger text | CTO | mechanical | Applied: two structures remain (gated set, `needs`), comment above the job, ledger consequence text |
| Status question at the top of the PR body; dark merge changes timing | CTO, Kieran, simplicity | mechanical | Applied: Acceptance Criteria, Latency section, amendment wording |
| Move PM-1 to its own tracker; automate PM-5 | CTO | taste | Not applied: the brief ties PM-1 to S2; stated as independent of PM-2 to PM-4 instead; PM-5 stays one docs PR |
| Reuse `main-push-duplicate-skip.sh` with a mode | DHH | taste | Not applied: its proof (PR association, tree identity, PR run) shares nothing with a `merge_group` SHA match; recorded in the Cut List |
| Counts: 14 cheap guards, about 25 push runs per day | Kieran | mechanical | Applied |
