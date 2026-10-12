---
title: "ci: S4 PR affected-only suite set, e2e classifier fallback fix, shard-totality-mutations path gate"
date: 2026-10-12
slug: ci-pr-affected-only-gating
branch: feat-ci-path-filtering
issue: 9729
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
amends: [ADR-276, ADR-262, ADR-183]
---

# ci: S4 PR affected-only suite set, e2e classifier fallback fix, shard-totality-mutations path gate

## Overview

Doc-only PRs (PR 10097: one `knowledge-base/**` markdown file) run most of the CI battery on the 60-concurrent hosted-runner pool. This plan un-parks S4 (#9729, ADR-276 stage 4): on `pull_request` only, run the affected suite set plus the always-on ratchets; `merge_group`, push, `workflow_dispatch` and schedule keep the full battery. It also fixes the `e2e` classifier fallback and path-gates `shard-totality-mutations`.

Brainstorm: `knowledge-base/project/brainstorms/2026-10-12-ci-path-aware-gating-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-ci-path-filtering/spec.md`. Operator decisions carried in: S4 un-parked; the S2 (#9818) and S3 census gate waived 2026-10-12; detective post-merge probe for the `--admin` residual; e2e fix and shard-totality gate bundled.

**Recommended landing order (three PRs, each dark behind the kill-switch until the ADR amendment activates it):**

| PR | Phases | Saves | Needs aggregator edit |
|---|---|---|---|
| A | 1 (e2e fix), 1.4 (shard-totality gate) | about 4.2 + 10.7 job-min per PR run | no |
| B | 2 (selection job), 3 (group-level gating + aggregator tolerance), ADR-276 amendment | about 15.3 + 2.4 + 3.0 + 2.4 job-min per doc-only PR run | yes |
| C | 4 (per-suite selection in `test-scripts` shards), 5 (jobs-API reduced-run read, admin and probe controls) | the 119.2 job-min `test-scripts` family, 73% of the diff-sensitive cost | no (reads PR B's output) |

Figures are the latest successful full PR run (`CI` run 38222769030: 164.4 job-min; `test-scripts` 119.2, `test-webplat` 15.3, `shard-totality` 10.7, `e2e` 4.2, `test-scripts-heavy` 3.0, `test-bun` 2.4, `web-platform-build` 2.4), measured by the research agent with the jobs API, runner-bound jobs only.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality (verified on this branch) | Plan response |
|---|---|---|
| "e2e already skips KB-only diffs" (CTO) | `scripts/ci-e2e-classify.sh` allowlists `knowledge-base/**`, but all 14 of the last 14 KB-only merged PRs' `e2e` check-runs carry the annotation `e2e classification fell back to enum-failed`, then `applicable=true` (PRs 10079, 10059, 10040, 10013, 9982, 9937, 9924, 9923, 9816, 9807, 9778, 9749, 9722, 9683). The skip has never fired in that window | Phase 1: reproduce, fix, make the failure legible |
| "adding `--affected` to the CI legs selects the affected set" (S4 draft) | CI never selects by diff: the pre-pass runs only when `TEST_GROUP==all` (`scripts/test-all.sh:3745`); shard legs run with a group name, so `_aff_ready` stays 0 (1461) and the chokepoint selects everything (1686, 2650). `--affected` on a leg is a no-op | Phase 2 and 4: once-per-run selection job plus a label-keyed consumer in the runner |
| `admin-merge-ready.sh` and `battery-owed.sh` live under `scripts/` | They are `plugins/soleur/scripts/admin-merge-ready.sh` and `plugins/soleur/skills/ship/scripts/battery-owed.sh`; `plugins/soleur/scripts/ci-head-verdict.sh` also reads the `test` row | Files-to-Edit uses the real paths |
| The index and the runner-changed detector are read from a trusted base copy | The runner sources its libs relative to itself (`test-all.sh:981, 1000-1004`), i.e. the PR tree; the detector (3752-3756) matches only `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`. A `pull_request` run also executes the PR's own `ci.yml`, so a base copy of the runner protects little | **Reversed by operator decision (2026-10-12), recorded in the ADR amendment:** no base-ref copy; widen the full-battery trigger list so any edit to a selector input means full (Phase 2). Unknown suites run (fail closed) |
| `shard-totality-mutations` can use `_diff_touches --pr-gated` | `_diff_touches` is a shell predicate inside `test-all.sh`; a `ci.yml` job `if:` cannot call it. The job is not required and not in the `test` aggregator's `needs` | Phase 1.4: job-level `if:` on a `detect-changes` output (extend the existing job) |
| The `[full]` marker is a `run-name` suffix (ADR-276 Decision 2, #9729) | `run-name` is fixed at run creation, so it cannot see the job outcomes, a variable flip mid-run, or a re-run's changed variable; interpolating a PR title would let a PR spoof it (reviewed by five panels) | **Replaced by operator decision (2026-10-12), recorded in the ADR amendment:** consumers read the PR head run's jobs through the API (Phase 5.1); no `run-name`, no spike on `vars` support |

## Research Insights

**Premise Validation.** Checked on `origin/main` after fetch: `scripts/ci-e2e-classify.sh`, `scripts/lib/test-relevance-paths.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`, `scripts/required-checks.txt` exist; `scripts/admin-merge-ready.sh` and `scripts/battery-owed.sh` do not (relocated, see above). #9729 OPEN (p3-low, `meta/machinery`); #9721 CLOSED (tracker); #9818 (S2 soak) and #9730 (S5) OPEN; ADR-270 `status: accepted` so ADR-276 3(h) holds. Recent main merges touching the selector (#9945, #9824, #10025, #9990) are local-fast-tier work and do not change the CI path. The 2026-09-25 plan `2026-09-25-feat-ci-path-gating-plan.md` (#8897) already path-gated the file-scoped workflows (tenant-integration, vendor-pin, sentry), so no other PR-triggered workflow is in scope here.

**Property List.**
1. A doc-only or low-blast-radius PR consumes materially fewer hosted-runner minutes on `pull_request`.
2. A reduced PR run can never be read as a full one by any merge authority (`merge_group`, push-to-main deploy arm, `admin-merge-ready.sh`, `battery-owed.sh`, `post-merge-monitor.yml`).
3. Any unknown (selection error, unresolvable diff, absent artifact, unknown suite label, switch not exactly `on`) runs the full battery.
4. The `e2e` skip decision is observable: a fallback names its cause.
5. The merge-queue candidate run stays the full-battery authority.

**Cut List.**
- Synthetic status posting / workflow-level `paths-ignore` -> property 2 is already served by a job-level `if:` plus aggregator tolerance; ADR-276 Decision 4 rejects the synthetic option and a path-gated required context wedges every PR.
- A hand-written `knowledge-base/**` skip list -> the 240-row `scripts/test-affected-kb-consumers.baseline.txt` and the content-keyed whole-tree edge show the tree is read; the selector is the single source of truth.
- A per-leg `--affected` pre-pass -> about 86 s per leg; one selection job per run serves all legs.
- Gating `test-scripts` as a whole group -> the always-on ratchets run inside it; selection must be per suite (Phase 4).
- A `[full]` `run-name` marker (spoofable by a PR title, fixed before job outcomes and variable flips exist, needs a `vars` spike) -> the jobs-API read (Phase 5.1) serves property 2 with no new producer. Operator decision 2026-10-12.
- A trusted base-ref runner copy -> a widened full-battery trigger list serves property 3 (a PR cannot widen its own skips) without a checkout, a failure path or a root-override; a `pull_request` run executes the PR's own `ci.yml` anyway. Operator decision 2026-10-12.
- Tolerating `skipped` generally in the aggregator -> ADR-276 3(a) requires each tolerated skip reason to be named.

**Institutional learnings applied.** `2026-03-20-github-required-checks-skip-ci-synthetic-status.md` (job-level `if:` plus an always-run aggregator, never workflow `paths:`); `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md` (an empty diff base on `merge_group` is a vacuous green; selectors fail closed); `2026-09-21-every-gate-this-pr-added-failed-open-on-the-input-it-could-not-measure.md` (a failed diff must give a non-skip verdict, never a default skip); `2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md` (`continue-on-error` on the job, empty outputs mean full battery); `2026-10-12-docs-only-ci-skip-premise-is-false-when-tests-read-the-kb.md`; `workflow-issues/2026-10-10-a-text-pin-on-a-gate-step-is-not-the-gate-and-each-fix-needed-its-own-executed-pin.md` (execute the gate against failing input with a mutant, text pins certify spelling only); `merge-queue-ejections-two-causes-and-fix-pr-guard-survivors-20261005.md` (`TEST_GROUP=affected` leaked into nested suites, do not widen that variable). Gap: no learning covers an admin merge bypassing the queue; Phase 5 verifies it with the API.

**Value measurement.** Command: `gh api repos/jikig-ai/soleur/actions/runs/38222769030/jobs?per_page=100` (runner_id != 0, summed per job family) gives the 164.4 job-min baseline above. The saving per PR class is hypothesis until Phase 2's replay measures it (`scripts/ci-pr-affected-replay.sh`, Phase 4); ADR-276 measured affected selection at 27% of suite-minutes for a docs diff (2026-10-07).

**Hypotheses for the e2e fallback** (`## Hypotheses`, ranked; Phase 1 reproduces before fixing).
1. `git diff` fails with "detected dubious ownership" inside the `mcr.microsoft.com/playwright` container (checkout writes as one uid, the step runs as root, or the reverse); stderr is discarded by `2>/dev/null` so the cause is invisible.
2. `origin/${GITHUB_BASE_REF}` is not a resolvable ref in that container's clone.
3. `git show origin/main:scripts/ci-e2e-classify.sh` fails for the same ownership reason.
4. The `mcr.microsoft.com/playwright:v1.58.2-jammy` image has no `git`: `actions/checkout` then falls back to a REST tarball with no `.git`, every `git diff` fails, and 14 of 14 fallbacks is consistent with that. `safe.directory` would not fix it; the fix would be running the classifier on a host runner or installing git. H4 is checked first because it is the cheapest to test (`git --version` in the container).
Not hypotheses: `scripts/ci-e2e-classify.sh` is present on `origin/main`; `fetch-depth: 0` is set for `pull_request`.

## User-Brand Impact

**If this lands broken, the user experiences:** a regression that a reduced PR run waved through reaches `main` and then production (a broken page, an auth or billing path) because the affected selection skipped the suite that would have caught it; or every PR wedges because a required context never reports.
**If this leaks, the user's [workflow] is exposed via:** an `--admin` merge that skips the merge queue and lands an affected-only-green PR; the push-to-main run still runs the full battery and the deploy arm waits on it, so the residual is a red `main` (caught by the ADR-270 post-merge alert) rather than a silently bad deploy.
**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true`. CPO sign-off is owed before `soleur:work` starts: the brainstorm spawned the CTO only (CI-internal lever, no product surface), so the sign-off has not been collected. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

### ADR
No new ADR. Append `## Amendment 2026-10-12 (S4, #9729)` to ADR-276 (kill-switch `CI_PR_AFFECTED`, exit criterion, census link, the recorded waiver of the S2/S3 census gate, stage-status line `S4 amended`) in PR B, before any switch is flipped (Decision 3(g)). Add pointer amendments to ADR-262 (its "No merge queue is enforced" premise and its admission rule are reversed for the PR arm) and ADR-183, and an `amends:` frontmatter key on each. ADR-276 Decisions 3(a)-(h) and Decision 5 are the governing text; this plan implements them, with two recorded reversals of the S4 gate text (the `[full]` run-name marker and the trusted base-ref copy, both replaced 2026-10-12; see Research Reconciliation). The amendment states these reversals and that B skips whole groups through job-level `if:` (not in-runner declines counted per ADR-181).

### C4 views
No C4 impact. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): the change adds no external human actor, no external system or vendor, no container or data store, and no actor-to-surface access relationship; CI workflows appear only as counted edges. The plan adds no workflow file (the probe is a step in the existing `post-merge-monitor.yml`) and no Sentry monitor, so `plugins/soleur/test/c4-count-parity.test.sh` must stay green; run it in PR B and C (AC10).

### Sequencing
The ADR amendment lands with PR B and describes the target state; activation (the repository variable becoming exactly `on`) is a separate authorized step in the same lane as S2 and S3, never part of a PR.

## Implementation Phases

### Phase 1 — e2e classifier fallback (PR A; independent)
1.1 **Diagnose first, from PR A's own CI run (no local container needed).** In the `Classify e2e applicability` step of `.github/workflows/ci.yml`, capture `git diff` and `git show` stderr instead of `2>/dev/null`, and print in the `::warning::` the stderr, `git --version` (H4), the workspace owner versus `id -u`, the base SHA and the changed-file count. PR A's own run edits `ci.yml`, so the classify step runs there and its annotation names the cause (the fallback branch fires on every PR today).
1.2 **Fix per the measured cause** in the same PR (H1: `git config --global --add safe.directory "$GITHUB_WORKSPACE"` before the diff; H4: run the classifier on a host runner or install git in the step). Keep every unresolved case fail-closed to `applicable=true`. The PR body states the measured cause.
1.3 **PR A is not dark.** It restores the already-merged #8450 design (fail-closed allowlist, base-ref classifier) rather than adding a policy, and the `shard-totality-mutations` gate drops a non-required self-test; neither has a switch. Rollback is a revert of PR A, and the ADR-276 amendment (PR B) records both as the S1-style exemption: non-required or already-designed contexts that move no required context or merge authority.
1.4 **Gate `shard-totality-mutations`.** Extend the existing `detect-changes` job with an output `shard_totality` that is `true` on non-PR events and on a PR diff touching the battery's subject paths (derive the list from what `plugins/soleur/test/scripts-shard-totality-mutations.sh` mutates: `scripts/test-all.sh`, `.github/workflows/ci.yml`, `scripts/scripts-shard-totality.test.sh`, `scripts/suite-shard-legs.tsv`, the heavy manifest, the battery itself); the job's `if:` gains `&& needs.detect-changes.outputs.shard_totality != 'false'` (fail closed on empty). `detect-changes` currently `exit 0`s after emitting only `docs=true` on non-PR events, so the edit must also emit `shard_totality=true` on that early path. Derive the path list from the battery at build time (read the files `plugins/soleur/test/scripts-shard-totality-mutations.sh` mutates) and pin that derivation in a test so the list cannot drift. Not required and not in the aggregator, so no aggregator edit.
1.5 Update the exact-text pins (`scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`) and add an executed pin: the step body run in a fixture repo where `git diff` fails must print the stderr text and emit `applicable=true`.

**PR A outcome (implemented 2026-10-12; commit `1aaa12f739`).** The measured root cause of the e2e fallback is none of H1-H4: the e2e checkout used `fetch-depth: ${{ github.event_name == 'pull_request' && 0 || 1 }}`, and `0` is falsy in an Actions expression, so the ternary evaluated to `1` on every event. Every PR was a depth-1 clone, `origin/<base>` never resolved, and the classifier fell back (verified from the job log of PR 10079: `fetch ... --depth=1`, and `git version 2.34.1` present, which refutes H4). The `'0'` string fixes it; the old text pin certified the spelling. Deviations from the plan text, both deliberate: (1) the `shard-totality-mutations` gate is an in-job classify step (modelled on e2e), not a `detect-changes` output plus a job-level `if:`, because the job's `if:`/`needs:` text is pinned verbatim by `ci-push-dedupe.test.sh` and `ci-draft-light.test.sh` (a verified trade: the job still takes a runner for the checkout, the roughly 3-minute battery per leg is what is saved); (2) its classifier is a fail-closed markdown-only allowlist (`scripts/ci-shard-totality-classify.sh`), not a derived subject-path list, so no list can drift. The local affected-test gate was queued sixth behind sibling sessions' runs and was stopped; the substitute is the pin suites, the two new suites, the shard-totality guard, the merge-group probe, and the fixture ratchets (all green), plus a 7-mutant battery (7 of 7 killed); CI's full battery is the merge authority.

### Phase 2 — once-per-run selection job (PR B; dark)
A new `pr-selection` job (`if: github.event_name == 'pull_request'`, job-level `continue-on-error: true`, `timeout-minutes` written alone on its line, `fetch-depth: 0`). It runs the selector once from the PR tree (there is no base-ref copy: the widened trigger list below makes an edit to any selector input a full run), maps selected suite labels to groups, and emits outputs: `mode` (`full|affected`), `skip_legs` (comma-delimited, subset of the three skippable groups), `active` (`true` only when the switch is exactly `on` and the mode is `affected`). With the switch unset it only annotates `would_skip` and every gated job runs (the draft-light dark shape). A diff it cannot resolve, a runner edit, an unknown suite, any error: `mode=full`, `skip_legs` empty. Hardening folded in from review:
- **Bind to the head.** The job emits `head_sha` and `base_sha` (the base SHA is resolved once and pinned for both the diff and the index); the gated jobs and the aggregator treat `needs.pr-selection.outputs.head_sha != github.event.pull_request.head.sha` as full (a "Re-run failed jobs" reuses cached outputs against a moved base).
- **Diff form.** `git diff --name-status --no-renames` against the pinned base; any Added, Deleted or Renamed (old or new path) file outside known doc paths is non-skippable.
- **Widened full-battery trigger list.** The existing runner-edit detector (`scripts/test-all.sh:3752-3756`) matches only two paths and does not cover `ci.yml`. The job's own list adds `.github/workflows/ci.yml`, `scripts/ci-pr-selection.sh`, `scripts/lib/**`, `scripts/suite-shard-legs.tsv`, the heavy manifest, `scripts/test-affected-kb-consumers.baseline.txt`, `scripts/ci-e2e-classify.sh`, and anything `scripts/test-all.sh` sources (derived by a test, not listed by hand).
- **Draft and ready.** The job runs on drafts too; on a light draft the Option R arm exits 1 before the tolerance is reached, so both arms cannot fire as green. `ready_for_review` is a new run, so it computes a fresh selection.
- **Bounds.** `timeout-minutes: 10` written alone on its line (the release budget awk reads that shape), `fetch-depth: 0`, `continue-on-error: true`.
- **Spike S-b:** measure what the pre-pass needs (dependencies, the 86 s wall) before fixing the job's shape.

### Phase 3 — group-level gating and aggregator tolerance (PR B)
Three groups are gateable: `test-webplat`, `test-bun`, `test-scripts-heavy`. `web-platform-build` stays ungated: it carries an explicit "every pull request" npm-registry resolution check (`ci.yml` ~1094, pinned by `test/c4-likec4-version-pin.test.ts`). `e2e` is not skipped here (its in-job classifier owns it, fixed in Phase 1); `test-scripts` is never skipped as a whole (Phase 4). Each gated job gains `needs: [..., pr-selection]` and an `if:` term that skips it only when `github.event_name == 'pull_request'`, the head SHA matches, and the leg is in `skip_legs` by a delimited match (`contains(format(',{0},', needs.pr-selection.outputs.skip_legs), ',test-bun,')`, so `test-scripts` never matches `test-scripts-heavy`); the existing `!cancelled()` / push-dedupe / draft-light terms are kept verbatim. `active` is computed once in bash (exactly `on`, case-sensitive) and emitted as `true`/`false`; no `${{ }}` expression ever compares the variable (expression `==` is case-insensitive). The `test` aggregator adds `pr-selection` to its `needs`, receives `SKIP_LEGS`, `ACTIVE` and `HEAD_SHA_OK` through `env:` (the body then reads no job output directly; update `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`'s pin of that surface) and gains one named tolerance, `PR-AFFECTED-SKIP`: a `skipped` result is accepted for a leg only when `EVENT_NAME == pull_request`, `ACTIVE == true`, the head matches and the leg is in `SKIP_LEGS` (same delimited match in bash); every other `skipped` still sets `fail=1`; `encryption-posture` is never tolerated. The `Option R` draft arm is untouched. The ruleset context names and `scripts/required-checks.txt` do not change.

### Phase 4 — per-suite selection in the shard legs (PR C)
**Phase 4.0 go/no-go gate (precedes any Phase 4 code).** Spikes S-b (pre-pass dependencies, wall time on the critical path of every PR) and S-c (label keying) are measured, and the replay result is recorded; Phase 4 proceeds only if the replay escape rate is under 2% and the pre-pass cost does not erase the saving (the saving is 23 suite-min against an 86 s pre-pass). If the gate fails, PR C ships Phase 5 only and Phase 4 is re-decided. `pr-selection` emits the label-keyed selection (`AFFECTED_SELECTED` rows carry label, selected flag, class and edges; `scripts/test-all.sh:4010-4021`; a skip list only, `skip_labels`) as a job output rather than an artifact, so there is no download step, no parser in every leg and no missing-artifact failure mode; each `test-scripts` and `test-scripts-heavy` leg receives it through `env:` and the runner gains a consumer that skips a suite only when its label is listed; an empty list, unknown label or PR-added suite runs. Adding `needs: pr-selection` to the `test-scripts` matrix puts the pre-pass on the critical path of every PR; measure it in S-b. The existing chokepoint keys by ordinal from the all-walk (1686, 3872), so Phase 4 adds label keying (spike S-c). The always-on ratchets (`lint-rule-bodies-live`, `lint-legal-registers-live`, `generate-kb-index-live`, the registration battery) are never skippable. Replay: extend the existing `scripts/ci-battery-gate-replay.sh` (it already owns the 300-commit first-parent loop and the `origin/main` fallback) with the selector; `--print-selection` over the last 300 first-parent commits against suite failures; the escape rate must be under 2% (break-even about 12 to 16%).

### Phase 5 — marker, admin control, census (PR C)
5.1 **Reduced-run read (no `run-name`, no marker).** `pr-selection` has one extra step named `pr-affected-active` that runs (conclusion `success`) only when `active == true`. A PR head run is *full-verified* iff the newest completed `pull_request` `CI` run on the head SHA concluded `success`, none of `test-webplat`, `test-bun`, `test-scripts-heavy` has conclusion `skipped`, and the `pr-affected-active` step is not `success` (jobs API: job and step names and conclusions, head SHA, event; not a check name posted by a `checks: write` token, and not a title). A PR that edits `.github/workflows/` is already refused by `admin-merge-ready.sh` as UNTRUSTED-CI, so it cannot drop the step to look full.
5.2 `plugins/soleur/scripts/admin-merge-ready.sh` and `plugins/soleur/scripts/ci-head-verdict.sh` require, in addition to a green `test`, a full-verified PR head run (5.1) or a `merge_group` success on that SHA. `battery-owed.sh`, the deploy `workflow_run` arm and `post-merge-monitor.yml` are checked so a reduced run is never read as full.
5.3 Detective probe `plugins/soleur/scripts/ci-full-battery-audit.sh`, invoked as a step of the existing `post-merge-monitor.yml`: for each merge commit on `main` with no `merge_group` run on that SHA (a bypass merge), require a full-verified PR head run (5.1); else emit `SOLEUR_FULL_BATTERY_ESCAPE sha=... pr=...`. Counted in `scripts/ci-demand-census.sh` (PR `CI` job-min by mode, escape count).
5.4 Verify with the API (the learnings corpus has no entry) that `gh pr merge --admin` skips the merge queue before relying on that sentence in the ADR amendment.
5.5 **Activation lock.** `pr-selection` forces `active=false` through a literal sentinel until PR C removes it in its last commit, so PR B alone is never activatable (CPO condition 1). Activation also requires AC6 (replay escape under 2%), Guard 3 merged, and a pre-activation baseline census recorded in the ADR amendment.
5.6 **Consumers of a green `test`.** Enumerate by grep every reader (`plugins/soleur/scripts/monitor-pr-checks.sh`, ship Phase 7, `drain-prs`, `battery-owed.sh`, `post-merge-monitor.yml`, `web-platform-release.yml`) and tie each to the `merge_group` backstop; `web-platform-release.yml` re-checks `WR_EVENT == push` on its `workflow_run` arm, so a reduced PR run never feeds the deploy arm (verified by the architecture review; a test pins it).
5.7 **Page and own the escape.** `SOLEUR_FULL_BATTERY_ESCAPE` routes to Better Stack with a named responder recorded in the ADR amendment; an unowned count does not bound a single-user incident (CPO condition 4).

## Open Code-Review Overlap

Open `code-review` issues naming planned files: #8659 and #7942 (`scripts/test-all.sh`), #8800 (`scripts/lib/test-affected-paths.sh`). **Acknowledge** all three: separate concerns (EXIT-trap leaks, two unrun mutation batteries, a census sandbox fixture). They stay open. None names `ci.yml`, `ci-e2e-classify.sh`, the admin-merge scripts or `required-checks.txt`.

## Domain Review

**Domains relevant:** Engineering

### Engineering
**Status:** reviewed (carried forward from the brainstorm CTO assessment, re-verified against the repo)
**Assessment:** job-level `if:` plus a named aggregator tolerance is the only shape that keeps every required context reporting; the safe KB skip set is derived from the selector and the 240-row baseline; build it as an ADR-276 stage amendment; `shard-totality-mutations` gate and the e2e fix are independent and low risk. Marketing, Operations, Product, Legal, Sales, Finance, Support: no implications for an internal CI lever. Product/UX Gate: NONE (no user-facing surface; no new component or page files).

## Test Scenarios

- Doc-only PR (one `knowledge-base/project/learnings/*.md`): `pr-selection` emits `mode=affected`, `skip_legs` names the four groups, `test` concludes `success` with the `PR-AFFECTED-SKIP` line printed, `e2e` job reports `applicable=false`.
- Same diff with `CI_PR_AFFECTED` unset or `ON`: every gated job runs, `would_skip` annotated, `test` green on full results.
- PR editing `scripts/test-all.sh`, `ci.yml` or an affected-index file: `mode=full`.
- `merge_group` and `push` and `workflow_dispatch`: `pr-selection` skipped, `skip_legs` empty, full battery, and the 5.1 read reports full-verified.
- `pr-selection` fails or times out (`continue-on-error`): empty outputs, full battery.
- A leg skipped but not named in `skip_legs`: aggregator exits 1 (`SKIPPED — the leg did not run`).
- `git diff` fails inside the e2e container: stderr and base SHA printed, `applicable=true`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 PR A: the e2e fallback cause is reproduced and stated in the PR body; the step prints the git stderr, base SHA and file count on any fallback; an executed pin runs the step body under a failing-`git diff` fixture (RED row R1).
- [ ] AC2 PR A: `shard-totality-mutations` skips on a PR whose diff touches none of the subject paths derived from the battery, runs on any touch and on every non-PR event; empty `detect-changes` output runs it.
- [ ] AC3 PR B: `pr-selection` is `continue-on-error`, PR-only, emits only literal `true`/`false`/comma lists, and with the switch unset changes no job's execution (a dark-run diff of job conclusions on a fixture PR is empty).
- [ ] AC4 PR B: the aggregator tolerates a skip only under the `PR-AFFECTED-SKIP` conditions; `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` executes the body over synthetic triples including every Guard 1 row.
- [ ] AC5 PR B: ADR-276 amendment (S4, `CI_PR_AFFECTED`, exit criterion, census link, waiver note, stage-status line) plus pointer amendments to ADR-262 and ADR-183 and `amends:` frontmatter are in the PR.
- [ ] AC6 PR C: replay over the last 300 first-parent commits shows escape rate under 2%; the receipt reads the diff (not `--print-affected-set`, which prints registration classes).
- [ ] AC7 PR C: `admin-merge-ready.sh` reports not-ready on a green `test` whose head SHA has no full-verified run (a gated job skipped, or the `pr-affected-active` step succeeded) and ready on a full-verified run or a `merge_group` success (fixture rows in `admin-merge-ready.test.sh`).
- [ ] AC8 PR C: `ci-full-battery-audit.sh` flags a bypass merge without a full-verified PR run and stays silent for a queue merge (fixtures).
- [ ] AC9 The pin tests pass: `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`, `plugins/soleur/test/ci-concurrency-key.test.sh`, `scripts/probe-merge-group-coverage.sh`.
- [ ] AC10 `plugins/soleur/test/c4-count-parity.test.sh` green; `scripts/required-checks.txt` and the ruleset context names unchanged (`git diff origin/main -- scripts/required-checks.txt` empty).

### Post-merge (operator-independent verification)
- [ ] AC11 After PR A merges, the next KB-only PR's `e2e` check-run annotation reads `applicable=false` (not `enum-failed`); verified by the annotation API.
- [ ] AC12 After activation, over a 6-hour window `scripts/ci-demand-census.sh` reports mean PR `CI` job-min per run down at least 20% against the pre-activation baseline recorded in the ADR amendment (ADR-276 measured 99.8 mean across all PR runs on 2026-10-07; a full PR run measured 164.4 on 2026-10-12; the amendment fixes ONE baseline definition before activation) and zero unaccounted `SOLEUR_FULL_BATTERY_ESCAPE`; stop rule: close the stage if the replay escape rate exceeds 12%. The stop rule is also an operator-visible kill criterion written into the ADR amendment (CPO condition 2).
- [ ] AC13 CPO sign-off conditions are met: B and C stay dark and activation is locked (5.5); kill criterion in the ADR; escape paging and named responder (5.7); `soleur:engineering:review:user-impact-reviewer` runs at review and verifies the deploy arm cannot read a reduced PR run as full.

## Observability

```yaml
liveness_signal:
  what: scripts/ci-demand-census.sh PR CI job-minutes per run by mode (full|affected) and the count of SOLEUR_FULL_BATTERY_ESCAPE markers
  cadence: per post-merge-monitor run and on demand
  alert_target: Better Stack marker SOLEUR_FULL_BATTERY_ESCAPE (post-merge-monitor.yml step output)
  configured_in: .github/workflows/post-merge-monitor.yml, scripts/ci-demand-census.sh
error_reporting:
  destination: ::warning:: / ::notice:: annotations (ci-pr-selection, ci-e2e-classify) plus the step summary; the aggregator prints each tolerated skip by name
  fail_loud: yes (any unknown runs the full battery and prints the reason; the aggregator exits 1 on an unnamed skip)
failure_modes:
  - mode: pr-selection errors or times out
    detection: annotation ci-pr-selection reason=lever_error and empty skip_legs
    alert_route: census reports mode=full runs; no merge risk (full battery)
  - mode: reduced run read as full by a merge authority
    detection: admin-merge-ready.sh / ci-head-verdict.sh full-verified read (5.1); ci-full-battery-audit.sh
    alert_route: SOLEUR_FULL_BATTERY_ESCAPE marker
  - mode: e2e classifier falls back again
    detection: ::warning:: with git stderr and base SHA
    alert_route: census counts enum-failed per PR class
logs:
  where: GitHub Actions step summaries and annotations (jobs API)
  retention: 90 days (GitHub default)
discoverability_test:
  command: bash scripts/ci-demand-census.sh --selftest
  expected_output: SELFTEST_OK
```

## Guard Contract

### Guard 1 — aggregator skip tolerance (`PR-AFFECTED-SKIP`)
**Property.** A `skipped` leg turns the `test` aggregator green only on a `pull_request` run with `active == true` for a leg named in `skip_legs`; every other skip reds it, and `encryption-posture` is never tolerated.
**Assembly.** Every code path that can make a required leg read `skipped`: the `needs.*.result` entries in `ci.yml` (`test-webplat`, `test-bun`, `test-scripts`, `test-scripts-heavy`, `web-platform-build`, `encryption-posture`), the aggregator loop, and the `Option R` draft arm; the chokepoint is the single loop body in the `test` job, so every leg flows through the same tolerance test.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Expect |
|---|---|---|
| G1-1 | `skipped` for a leg absent from `skip_legs` on a PR run | exit 1 |
| G1-2 | `skipped` for a listed leg on `merge_group` (and `push`) | exit 1 |
| G1-3 | `skipped` for a listed leg with `active` empty or `false` | exit 1 |
| G1-4 | `skipped` for `encryption-posture` even when listed | exit 1 |
| G1-5 | second leg skipped and unlisted after a compliant first listed skip | exit 1 |
| G1-6 | aggregator extracted but zero synthetic triples run (dispatch) | suite fails (anti-vacuity floor) |
| G1-7 | `test-scripts` listed but only `test-scripts-heavy` skipped (substring trap), and stale `HEAD_SHA_OK=false` with a listed skip | exit 1 |

Harness rows: H1 mutate the suite (delete the `PR-AFFECTED-SKIP` arm from the body under test) and require RED; must-PASS input that is not the canonical: a listed skip on a PR run with an extra whitespace-padded `skip_legs`. Anchor: the tolerance conditions live in `ci.yml`; a `pull_request` run executes the PR's own `ci.yml`, so the guard proves consistency, not integrity; `merge_group` (the full battery on the candidate tree) is the real authority, and the pin suites run against the PR tree.

### Guard 2 — selection fails closed
**Property.** Any unknown in the selection path yields `mode=full` with empty `skip_legs`.
**Assembly.** `pr-selection` (diff resolution, runner-edit detector, base-copy checkout, label mapping, artifact upload), and the leg-side consumer (artifact download, label lookup).

**Mutation matrix.**

| # | Mutation | Expect |
|---|---|---|
| G2-1 | `git diff` fails (unresolvable base) | `mode=full` |
| G2-2 | runner edit (`scripts/test-all.sh`) in the diff | `mode=full` |
| G2-3 | suite added by the PR (label absent from the base index) | suite runs |
| G2-4 | artifact missing or unparseable on a leg | leg runs everything |
| G2-5 | `CI_PR_AFFECTED` set to `ON` or ` on` | `active=false` |
| G2-6 | job exits before emitting (dispatch row: zero outputs) | gated jobs run |
| G2-7 | base moves between the first run and a re-run (cached `head_sha`/`base_sha` stale) | full battery |
| G2-8 | the PR renames a suite file or edits `scripts/ci-pr-selection.sh` / `ci.yml` | `mode=full` |

Harness rows: H2 break the job's `fetch-depth` and require G2-1 RED-equivalent (full); must-PASS: a legitimately doc-only diff selects `affected`. Anchor: any edit to a selector input (G2-8) means `mode=full`, so a PR cannot widen its own skips; the trigger list is derived from what `scripts/test-all.sh` sources, not listed by hand.

### Guard 3 — reduced-run read (full-verified)
**Property.** A merge authority treats a head SHA as full-battery-verified only if a completed `success` PR `CI` run on that SHA shows no skipped gated job and no successful `pr-affected-active` step, or a `merge_group` run succeeded on that SHA.
**Assembly.** `plugins/soleur/scripts/admin-merge-ready.sh`, `plugins/soleur/scripts/ci-head-verdict.sh`, `plugins/soleur/skills/ship/scripts/battery-owed.sh`, `monitor-pr-checks.sh`, `post-merge-monitor.yml`, `ci-full-battery-audit.sh`; the read is one shared function so every consumer flows through the same predicate.

**Mutation matrix.**

| # | Mutation | Expect |
|---|---|---|
| G3-1 | green `test`, run shows `test-bun` skipped | not-ready |
| G3-2 | green `test`, `pr-affected-active` step concluded success | not-ready |
| G3-3 | full-looking run on a different head SHA | not-ready |
| G3-4 | run still in progress, or conclusion `failure` | not-ready |
| G3-5 | second consumer (`battery-owed.sh` or `monitor-pr-checks.sh`) reads a reduced run as full | suite RED |
| G3-6 | `pr-selection` job missing from the run entirely (a PR that removed it) | not-ready |

Harness rows: H3 stub `gh` returning an empty jobs list must be NOT-ready; must-PASS: a `merge_group` success on the SHA with no PR run is ready, and a PR run with all gated jobs concluded success and no active step is ready. Anchor: the read uses job and step names and conclusions from the jobs API on head SHA and event, never a title and never a check name (a `checks: write` token can post any check name).

## Files to Edit
- `.github/workflows/ci.yml` (e2e step, `detect-changes`, `shard-totality-mutations` `if:`, `pr-selection` job, gated `needs`/`if:`, aggregator, the `pr-affected-active` step)
- `scripts/test-all.sh` (label-keyed consumer, `--print-selection` group output)
- `scripts/ci-battery-gate-replay.sh` (selector mode) and its test
- `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`
- `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`
- `plugins/soleur/scripts/admin-merge-ready.sh`, `plugins/soleur/scripts/admin-merge-ready.test.sh`, `plugins/soleur/scripts/ci-head-verdict.sh`
- `plugins/soleur/skills/ship/scripts/battery-owed.sh` (consumer check; edit only if it reads a reduced run as full)
- `.github/workflows/post-merge-monitor.yml`, `scripts/ci-demand-census.sh` and its test
- `knowledge-base/engineering/architecture/decisions/ADR-276-*.md`, `ADR-262-*.md`, `ADR-183-*.md`

## Files to Create
- `scripts/ci-pr-selection.sh` (+ `.test.sh`): the selection driver used by `pr-selection`
- `plugins/soleur/scripts/ci-full-battery-audit.sh` (+ `.test.sh`): the detective probe

## Risks and Sharp Edges
- **A reduced green read as full.** Mitigated by Guards 1 and 3, the merge_group authority, and the detective probe; the residual (a human or other-token `--admin` merge, a bypass actor editing the ruleset) is counted, not closed.
- **Pin tests.** The exact-text `if:` pins in `ci-push-dedupe.test.sh` and `ci-draft-light.test.sh` change; update them in the same PR and execute each against a mutant.
- **Label keying** (spikes S-b, S-c) are unbuilt; PR C may reveal that per-suite selection needs the runner refactor to be its own change.
- **`merge_group` must never skip a leg:** `pr-selection` is skipped off `pull_request`, so `skip_legs` is empty there; assert it in the pin.
- **A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6;** this plan carries the section and `requires_cpo_signoff: true`.
- Nothing in this plan provisions infrastructure; the switch is a repository variable under the ADR-276 activation lane.
