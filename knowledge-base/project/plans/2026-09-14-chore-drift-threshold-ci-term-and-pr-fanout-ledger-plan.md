---
title: "chore: raise the drift alert to the honest merge-to-deploy path, and bound the per-PR CI fan-out with a ledger instead of a merge queue"
type: chore
date: 2026-09-14
slug: chore-drift-threshold-ci-term-and-pr-fanout-ledger
branch: feat-one-shot-drift-threshold-ci-term-and-merge-queue
priority: P2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore: raise the drift alert to the honest merge-to-deploy path, and bound the per-PR CI fan-out with a ledger instead of a merge queue

## Enhancement Summary

**Deepened on:** 2026-09-14
**Sections enhanced:** Decisions, Item 1 design, Item 2 design, Files to Create, Observability,
Guard Contract, Research Insights (learnings)
**Research agents used:** architecture-strategist, test-design-reviewer, security-sentinel,
observability-coverage-reviewer, pattern-recognition-specialist, git-history-analyzer (live
attribution sweep), verify-the-negative sweep (10 claims), best-practices-researcher (GitHub
Actions concurrency / `!cancelled()` / Free-plan limits, doc-cited), learnings-researcher (second
pass). Gates 4.6–4.11 passed; 4.5 fired on the `timeout-minutes` token only (telemetry emitted,
no network symptom).

### Key Improvements

1. `encryption-posture` is removed from the fold — ci.yml's #6901 note says it was extracted so
   its green streak is attributable for the #6907 soak toward a required check (ADR-140); the fold
   is now three jobs (25 → 22), and every count in the plan was reconciled.
2. Mutators anchor the real `timeout-minutes` key with `re.M` and each RED axis greps its expected
   crit, so a mutation landing in a comment 200 lines below the key cannot score as caught; the
   must-PASS rows are `release → 70` (absorbed by the `max`) and a boundary value DERIVED from the
   control child, not a pinned 65.
3. The discoverability probe is a 2-line wrapper (`scripts/prod-version-drift-b9-probe.sh`) because
   preflight Check 10 rejects shell-active characters and env-prefix tokens and its 15 s sandbox is
   under the full 26 s run; the `resolve-target`-timeout failure mode now names the real route
   (release-outcome email + Sentry; not Slack).
4. Ledger `cancel` rule accepts `false` (a live value on `apply-sentry-infra.yml`), the group-shape
   rule lists the accepted ref expressions, A7's floor is in the exact shape
   `guard-vacuity-floor.test.sh` recognises with a direct-echo body, Part B uses a fresh
   `mktemp -d` per mutant and re-invokes the child with a parts/floor override.
5. Conventions: ADR-032 gets a `## Amendment — 2026-09-14 (#PR)` section (house style), ADR-216
   a `### Addendum 2026-09-14 —` section, ADR-217 a blockquote after its existing Correction; the
   ledger carries a `# Format:` line; the `resolve-target` ceiling comment opens in ci.yml's
   two-line measured-max shape; folded step names carry `(…, #PR)`.

### New Considerations Discovered

- The "live poll usually succeeds at 15 m" sentence was wrong: `reusable-release.yml` records an
  observed release max of ~24 m. A live poll now reads as "fails closed on any release over 15 m
  — a false non-delivery email is the intended loud warning".
- Two serialisers stay outside the B9 formula and are now named at the site: the
  `release-<component>` concurrency group (release N+1 queues behind N) and runner-queue wait.
- `secret-scan.yml`'s weekly schedule arm keys on main HEAD's SHA and shares the push-arm group; a
  same-SHA rerun can drop a pending weekly scan — recorded in the ledger row, not fixed (AC9 keeps
  byte-equality with ci.yml's block).
- `codeql-1537-revisit-watch.yml` finds its tracking issue by the `merge-queue-revisit` label, not
  by number; #5840 is today's holder.
- `plugins/soleur/scripts/grok-pre-push-gate.sh` mirrors the fast ci.yml jobs by script call, not
  job name, so the fold leaves it and `workflow-fidelity.test.ts` untouched.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this
branch; the domain sweep below was run semantically (Engineering only).

## Overview

Two decisions left over from the `workflow_run` deploy split (ADR-217, merged 2026-09-12 as
`36d3cc50a`). Both are decisions on already-measured numbers, not research. No GitHub issue is the
work target and none is filed by this plan.

**Item 1 — decided: option (a), raise the threshold and make B9 honest.**
`scripts/prod-version-drift-check.sh` alerts when the oldest undeployed commit on `main` is older
than `DRIFT_SUSTAINED_THRESHOLD_MIN = 207`. Check B9 in the sibling test asserts that constant
stays at or above the pipeline's declared critical path, so a ceiling raise can never silently
outrun the alert. Since the deploy split, CI is serial inside the merge-to-deploy path and every
`ci.yml` job declares a ceiling, so CI's 70-minute declared path is a real, assertable term. B9
still leaves it out because including it makes the honest path 265 minutes against a 207-minute
alert. This plan puts the CI term into B9 under one formula stated at every site, lowers the
provably-dead `resolve-target` ceiling from 60 to 15 minutes (measured 12–14 s across the last
nine `workflow_run`-arm runs), raises the constant to **225** (= 220 + 5), and makes the CI-budget
creep detector in `web-platform-release.yml` partition the same threshold the same way, so the
raise does not loosen it (CI's share stays 75 m; soft ceiling 52.5 m).

**Item 2 — decided: option (b), reduce the fan-out and move the lever to filing time. The merge
queue (option (a)) is not adoptable.** Twenty-three workflows declare a `pull_request` trigger;
roughly 56 declared jobs run on every PR push; the organisation is on the GitHub Free plan (20
concurrent hosted jobs), and the runner pool is the binding constraint on 76% of `main` CI runs. A
merge queue was enabled on 2026-06-30 (PR #5800) and deadlocked `main` within five minutes
because CodeQL default setup never posts a status on `merge_group` refs; `github/codeql-action#1537`
is still open (verified 2026-09-14), the advanced-setup workaround was prototyped and removed
(#5811/#5812), and ADR-032's 2026-07-01 amendment records the standing decision. This plan
re-affirms that decision with one new factor (a queue adds a full CI run per merge on the resource
that is already binding), takes the two reductions that are in scope and safe — three always-run
runner slots folded out of `ci.yml`, and superseded-push cancellation on the five stateless per-PR
workflows that lack it (up to 19 orphaned jobs reclaimed per force-push) — and adds a ledger + test
so no workflow can add a per-PR trigger without naming its consequence: the shape ADR-216 gave the
issue backlog.

## Research Reconciliation — Args vs. Codebase

| Claim in the brief | Reality on `origin/main` (2026-09-14) | Plan response |
|---|---|---|
| `DRIFT_SUSTAINED_THRESHOLD_MIN = 207`; ci.yml path 70; release 60; resolve-target 60; migrate 30; verify 15; deploy 90 | Verified by reading the files and by `DRIFT_TEST_PARTS=AB bash scripts/prod-version-drift-check.test.sh`: `B9 threshold (207m) >= release declared critical path (195m)`, `B9c ... derived (70m)` | Numbers carried unchanged |
| Honest path = `70 + max(60,60) + 135 = 265` | 265 is right, but the tree carries THREE different formulas for the same path: the `.sh` header and the `deploy` job comment say `max(release, CI-to-test, resolve-target) + 135 = 205`; B9 computes `max(release, resolve-target) + 135 = 195`; the brief adds CI in front. The physically correct model under ADR-217 D3(b) — the deploy arm queues behind the push-arm release run on a shared concurrency group and is dispatched by CI completion, then `resolve-target` runs serially (CTO confirmed: `release` is `if: != 'workflow_run'`, `resolve-target` is `if: != 'push'`) — is `max(ci, release) + resolve-target + migrate + verify + deploy` = `max(70,60) + 60 + 135 = 265` | One formula at every site (see Item 1 design). Same number today; differs from the brief's form only under mutations |
| "lowering resolve-target's 60m poll ceiling does not move B9" | Under the brief's form it does not; under the physical form it does. Measured on the last nine `workflow_run`-arm runs (`gh api .../runs/<id>/jobs`, `resolve-target` `started_at→completed_at`): 12–14 s, every run. Its 60 was sized "= the release ceiling" only because it sat inside a `max()`, which the formula above voids. ADR-217 D3(b) declares the poll dead by construction | Lower it to 15 (≥ 60x measured, the #8020 floor). If the poll ever went live, any release over 15 m (observed max ~24 m) fails LOUD here as a non-delivery email rather than silently waiting an hour. Path becomes `70 + 15 + 135 = 220` |
| Raise the threshold to "~270" | With `resolve-target` at 15 the honest path is 220, so 225 (+5 slack) is the constant; 270 would be 45 m of alert latency paid for a 13-second job's ceiling | 225 |
| `CI_BUDGET_MIN = 207 - 135 = 72` is CI's share (ADR-217 D4) | The workflow subtracts only migrate+verify+deploy; it omits the `resolve-target` term that follows CI. On a bare threshold raise the soft ceiling would loosen | Subtract `resolve-target` too: share = 225 − 15 − 135 = 75, soft ceiling 52.5 m (was 72 → 50.4 m) |
| "merge queue on main: NOT configured" | True, and it was configured once: PR #5800 (2026-06-30) deadlocked `main` in ~5 min; kill-switch applied same day; PIR at `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`; ADR-032 amendment 2026-07-01: "queue stays OFF; CodeQL stays a blocking required check"; `codeql-1537-revisit-watch.yml` polls the upstream issue monthly and pings the open issue labelled `merge-queue-revisit` (#5840 today — the workflow resolves it by label, not by number) | Option 2(a) is blocked, not chosen. Decision recorded in a new ADR that amends ADR-032 |
| "a merge queue requires merge_group triggers on the required-check workflows — enumerate and add" | Already done by PR-1 (#5784): every producer of the 22 `@15368` contexts in ruleset 14145388 (ci.yml, pr-quality-guards.yml, secret-scan.yml, dependency-review.yml, legal-doc-cross-document-gate.yml, tenant-integration.yml, apply-sentry-infra.yml, skill-security-scan-pr-trailer.yml) carries `merge_group:`. The CLA ruleset's two producers (cla.yml, cla-evidence.yml) do not, by design — the removed `merge-queue-cla-synthetics.yml` covered them. `CodeQL@57789` cannot | No trigger work. The enumeration is recorded as evidence in the ADR |
| Rulesets Terraform-managed? | Yes: `infra/github/ruleset-ci-required.tf` (ruleset 14145388), auto-applied by `apply-github-infra.yml`; the `merge_queue` block is deliberately absent under a "Merge queue REVERTED" comment | No ruleset change in this PR |
| "23 workflows fire on pull_request" | 23 files declare the trigger (21 `pull_request` + 2 `pull_request_target`). Per PR push (`synchronize`): 21 fire (board-status-sync and cleanup-unmerged-bot-branches are `types:`-gated to open/close events); 8 of the 21 are path-filtered; `claude-code-review.yml` is `disabled_manually` — a state held on GitHub's side, invisible in the tree — since 2026-02-12. Declared jobs across the 13 non-path-filtered firing files: 58 (56 excluding the disabled workflow) | Fold three 0.2 m single-script `ci.yml` jobs into the existing 11-step `lint-bot-statuses` job; add PR-only `cancel-in-progress` where it is safe; ledger every firing workflow including the disabled one |
| "audit the 23 for ones that could be push-only, path-filtered, or merged" | `constraint-gates.yml` looked like a path-filter candidate (self-gates on `apps/web-platform/**` inside the job) but its body is parity-locked to the constraint-scaffold template by `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` check 4, and the always-run shape is the template's stated design (promotable to a required check without a pending-forever `paths:` deadlock). Deleting `claude-code-review.yml` would silently stale `knowledge-base/legal/article-30-register.md` PA-33's dated member snapshot ("6 files / 7 job-level surfaces"; the entry argues a disabled-but-keyed workflow is still a member) with no parity test to catch it | Neither is changed. Both are ledgered with the reason. The lever the audit did find: `pr-quality-guards.yml` (10 jobs), `secret-scan.yml` (6), `dependency-review.yml`, `legal-doc-cross-document-gate.yml`, `skill-security-scan-pr-trailer.yml` have NO concurrency block, so a superseded push leaves their runs orphaned on the 20-slot pool; `ci.yml` already cancels PR runs per ref |
| "PR lost NINE consecutive merge attempts ... CONFLICTING" | PR #7990: `ready_for_review` 2026-09-10T13:55Z, merged 2026-09-12T00:09Z, 11 `head_ref_force_pushed` events, 21 commits to `main` in the window (median gap ~1.6 h). The timeline cannot distinguish BEHIND from CONFLICTING; the PR touched `knowledge-base/INDEX.md`, `ship/SKILL.md` and `ci.yml`, all high-churn | Not re-derived. Noted because a queue removes only the BEHIND fraction; a textual conflict needs a rebase under any mechanism |

## Decisions

### Item 1 — (a): include the CI term, lower `resolve-target` to 15, raise `DRIFT_SUSTAINED_THRESHOLD_MIN` 207 → 225

**Why (a) and not (d).** B9's purpose is that a ceiling raise reddens the suite instead of silently
outrunning the alert. Under (d) the suite stays green on a quantity it knows is short, which is
the exact class the 2026-09-10 learning names ("every instrument I used to judge my own guards
agreed with them"). The cost of (a) is 18 minutes of worst-case alert latency on a probe whose own
delivery interval was measured at 61–243 minutes (schedule jitter, recorded in the `.sh` header)
and whose declared path is ~4–6x every observed run (CI median 25 m, max 40 m). The fast
non-delivery channels (ADR-217 D3's `ci_not_green` email + Slack) are unchanged. (b) and (c) —
lowering `ci.yml`'s 60 m `test-scripts` leg (#8006 territory, `TEST_TIMING_LOG` data) or the
pre-existing 60 m release / 90 m deploy ceilings — remain measure-first and out of scope.

**Why `resolve-target` is in scope after all.** The brief carried it as "worth lowering for
honesty but does not move B9". That was true of the test's current formula and is not true of the
honest one, and the measurement took one bounded command: 12–14 s on nine consecutive runs. A
15-minute ceiling is derived the way #8020 derived every `ci.yml` ceiling (≥ 3x measured, floor
10–15 m). If a future edit ever un-couples the arms and makes the liveness poll live again
(ADR-217 D3 says that would happen "with no other warning"), a release slower than 15 m —
`reusable-release.yml` records an observed max of ~24 m against its 60 m ceiling — trips
`resolve-target`, `release-outcome` classifies it as non-delivery and emails the operator: a
FALSE non-delivery alarm, and that is the intended loud warning D3 said was absent. The job
comment must say exactly that ("fails closed on any release over 15 m; observed max ~24 m"), not
"usually succeeds" — the 15 is sized for today's dead poll (the ceiling clock starts when the job
starts, after the group wait), never for a live one.

**Why 225.** 220 + 5. The slack covers rounding of the declared terms only; runner-queue wait,
back-to-back serialisation and push-to-start latency sit outside every job timeout (the `.sh`
header's `SCOPE (#7160)` paragraph), and the CTO's reading is adopted verbatim: the constant's
comment must say the slack is not a bound on those, or the next reader assumes 225 is the whole
story. Harvesting to exactly 220 is rejected for the reason the header gives about 207: it
re-creates the #7902 trap one layer out.

**One formula, every site.** `crit = max(ci_declared_path, release_ceiling) + resolve-target +
migrate + verify-migrations + deploy`. It is the tightest bound valid wherever `resolve-target +
migrate + verify-migrations` dominates `verify-doppler-secrets` (60 vs 10 today; the parallel
`verify-doppler-secrets` branch stays value-blind by design — B8e pins the `needs:` closure and
the existing comment at the site already names the dominated term). The brief's additive form
under-counts when both release and resolve-target exceed CI; the `.sh` header's
`max(ci, release, rt)` puts resolve-target in parallel with CI, which `workflow_run` dispatch
makes impossible. Two serialisers stay OUTSIDE the formula and are named as such at the B9
comment and in the ADR-217 addendum: `reusable-release.yml`'s `release-<component>` group
(`cancel-in-progress: false` — release N+1 queues behind release N, and the deploy arm inherits
that wait), and runner-queue wait — the `.sh` header's `SCOPE (#7160)` paragraph, which the 5 m
slack does not pretend to cover. The `.sh` header, B9's Python, the workflow's `CI_BUDGET_MIN`
step, the `resolve-target` and `deploy` job comments, and `reusable-release.yml`'s "COUPLED
(#7160)" note all state the formula by term name.

### Item 2 — (b): reduce the fan-out, ledger the generator; the queue stays off

**Why not (a).** Three independent facts; the first alone is binding:

1. **It was tried and it deadlocked `main`.** PR #5800, 2026-06-30, 14-minute outage of the merge
   path, kill-switch applied. Root cause: CodeQL default setup fires on `push`/`pull_request` only;
   the `CodeQL@57789` required context never posts on a `merge_group` ref. `codeql-action#1537`
   open since 2023, last upstream comment 2026-05-22, verified open 2026-09-14
   (`gh api repos/github/codeql-action/issues/1537 --jq .state` → `open`). The advanced-setup
   workaround (a `merge_group` no-op job re-pointed as the required context) was prototyped in
   #5811 and removed in #5812; ADR-032 says "Do NOT restore it as a fix" and the upstream thread's
   last comment calls it "only half the issue". Re-adoption means making a blocking SAST gate
   advisory — a security-posture reversal this chore has no mandate for.
2. **It adds load to the binding resource.** A queue dispatches a full `merge_group` CI run
   (~57 declared jobs) per candidate on top of the `pull_request` run and the `push` run: three
   full runs per merged PR instead of two, on a Free-plan pool of 20 concurrent jobs where runner
   availability already dominates 76% of runs (ci.yml dispatch note, 29-run cohort). The brief's
   own diagnosis is that queue depth inflates effective CI time; the queue would deepen it.
3. **`check_response_timeout_minutes` would have to exceed measured start spread.** The dispatch
   note measured a 28-minute maximum start spread on a drained group; the recorded queue params
   set the response timeout at 15 minutes and note that under-setting it dequeues a green PR.

**What reopens the queue** (named, per the definition of done): (i) `codeql-action#1537` closes
with native `merge_group` status reporting — `codeql-1537-revisit-watch.yml` pings the open issue labelled `merge-queue-revisit` (#5840 today)
monthly; (ii) a deliberate operator decision to make CodeQL advisory (ADR-032 re-adoption recipe
(b)); (iii) an organisation plan change that lifts the concurrent-job pool (Free 20 → Team 60),
which removes factor 2. None is a technical fork this pipeline can take on its own.

**What (b) does here**, with the measured effect stated plainly:

| Change | Effect on the pool | Reasoning |
|---|---|---|
| Fold `readme-counts`, `lint-conversations-update-callsites`, `rule-metrics-shape` into `lint-bot-statuses` as three more steps | −3 declared jobs per push, PR and `main` alike (25 → 22 `ci.yml` jobs; 56 → 53 declared jobs across the non-path-filtered firing workflows, excluding the disabled workflow's 2) | Each is checkout + one script, 0.2 m measured over 10 `main` runs (#8020), no `needs:`, no permissions, not a required context, not referenced by any test as a job. `lint-bot-statuses` is already the repo's 11-step advisory-lint bucket (0.7 m measured, 15 m ceiling); the merged job stays under 2 m |
| PR-only `cancel-in-progress` on `pr-quality-guards.yml`, `secret-scan.yml`, `dependency-review.yml`, `legal-doc-cross-document-gate.yml`, `skill-security-scan-pr-trailer.yml` (ci.yml's exact block: per-ref on `pull_request`, per-SHA otherwise, cancel only on `pull_request`) | up to −19 orphaned jobs per superseded push (PR #7990 was force-pushed 11 times) | All five are stateless lint/scan jobs with no external state to leave half-written. `ci.yml` already does this. NOT applied to `tenant-integration.yml` (holds the dev-Supabase mutex; a mid-run cancel can leave fixture residue), `infra-validation.yml` and `apply-sentry-infra.yml` (terraform plan against a remote backend; a cancel mid-plan can leave a state lock), `constraint-gates.yml` (parity-locked) — each ledgered with that reason |
| `scripts/pr-fanout-ledger.txt` + `plugins/soleur/test/pr-fanout-ledger.test.sh` | 0 today; every future row must name its consequence | The generator-side gate. A workflow that fires on a PR push without a ledger row, a row whose workflow no longer fires, a workflow whose declared job count exceeds its row, or a `paths`/`cancel` flag that disagrees with the file, reddens the `test` check |
| `claude-code-review.yml` — kept, ledgered | 0 (disabled on GitHub's side since 2026-02-12; the trigger is still in the tree) | Deleting it silently stales PA-33's member snapshot in the Article 30 register, which has no parity test; the ledger row makes the off-tree disablement visible instead |
| `constraint-gates.yml` — no change | 0 | Parity-locked to the constraint-scaffold template; always-run is the template's promotable-to-required design |

Not done, recorded in the ledger header as the next candidate: consolidating the remaining advisory
`ci.yml` jobs (`lint-webplat`, `shard-totality-mutations`, the two `Detect ...`-gated jobs) —
heavier, `needs:`/`if:`-shaped, not 0.2 m; measure before touching.

## Item 1 — design

### `scripts/prod-version-drift-check.sh`

- `DRIFT_SUSTAINED_THRESHOLD_MIN=207` → `225`.
- Header block (the paragraph beginning "The longest LEGITIMATE commit-to-deployed latency"):
  replace the stale `max(release 60, CI-to-test 70, resolve-target 60) + ... = 205` narrative with
  the one formula and its reading of ADR-217 D3(b). Add a dated paragraph in the same voice as the
  `195 -> 207 (#7902)` one: `207 -> 225 (2026-09-14, ADR-217 D4 addendum)` — the CI term enters
  B9, `resolve-target` drops 60 → 15 on measurement, the constant moves **in the same commit** as
  B9's formula and the workflow's budget partition (B9 asserts threshold ≥ path; the workflow
  asserts `CI_DECLARED_PATH <= CI_BUDGET_MIN`; a split reds one side in between), the 5 m slack
  covers rounding only and queue wait stays empirical, and the 18-minute cost sits inside the
  probe's measured 61–243 minute delivery interval.
- No apostrophes in any comment that is interpolated into the workflow or the test's Python (the
  existing NOTE FOR EDITORS applies).

### `scripts/prod-version-drift-check.test.sh`

- Python extractor: replace the `ci_declared_path is NOT in this sum` comment with a dated decision
  comment naming option (a) and the formula, and compute
  `crit = max(ci_declared_path, release_ceiling) + job_timeout("resolve-target")` then add
  `migrate`, `verify-migrations`, `deploy`. Keep `ci_declared_path` derived exactly as today (the
  memoised longest `needs:` path over all `ci.yml` jobs, 360 default for an undeclared job). Keep
  the `NOTE FOR EDITORS: no apostrophes` discipline.
- B9 pass/fail strings: keep the `B9 threshold` prefix (Part C matches `FAIL: <label>` by prefix);
  rename the object from "release declared critical path" to "declared merge-to-deploy critical
  path". Update the comment above B9 (the `max(release, CI-to-test, resolve-target)` sentence) to
  the one formula.
- B9b/B9c unchanged (baseline 0; B9c now also protects B9's CI term from a blind extractor).
- B9 FAIL text carries the remedy at the site (the reader is an agent on a red PR): `raise
  DRIFT_SUSTAINED_THRESHOLD_MIN in scripts/prod-version-drift-check.sh to >= <crit>m in the SAME
  commit as the ceiling raise and add a dated line to its header; the workflow re-derives
  CI_BUDGET_MIN from it, no other edit`. The `B9 threshold` prefix stays (assert it: one Part C
  axis greps its own expected label out of the live test text, so a rename un-couples loudly).
- Part C: every mutator is VALUE-AGNOSTIC — it matches `timeout-minutes: \d+` inside the named
  `^  <job>:` block and writes the new value (`re.subn`, `count=1`, `assert n == 1` so a
  non-landing mutation fails the mutator, not the byte-diff). That is what makes the RED-first
  run in Phase 1 real: the axes must land on the tree BEFORE the formula change and SURVIVE.
  Every mutator anchors `^    timeout-minutes:\s*\d+\s*$` (`re.M`) inside the `^  <job>:` block —
  the `resolve-target` block carries the literal `` `timeout-minutes: 60` `` in a comment 200 lines
  below the real key, so a bare-text match can land in prose. Each RED axis greps BOTH `FAIL: B9
  threshold` AND its expected `>= <crit>` figure (275 / 280 / 290 today, read back from the child's
  own `RELEASE_CRITICAL_PATH_MIN` emit) so a mutation that lands on the wrong job is
  distinguishable from the intended one. Three RED axes and, via a sibling
  `mutate_and_assert_green` helper (same sandbox + landing check; asserts child exit 0 AND greps
  the `PASS: B9 threshold (…) >= … (<expected>m)` line, since exit 0 alone is satisfied by a child
  that never reached Part B), two must-PASS rows:
  - `axis13-raise-ci-test-scripts-ceiling`, `rel=.github/workflows/ci.yml`: `test-scripts` →
    `130`. GREEN before this change (the CI term is absent) — proves the term is in the sum.
  - `axis14-raise-resolve-target-ceiling`, `rel=.github/workflows/web-platform-release.yml`:
    `resolve-target` → `70`. GREEN before this change (`max(60,70) + 135 = 205 ≤ 207`) — proves
    the term is additive, not inside a `max()`.
  - `axis15-raise-release-ceiling`, `rel=.github/workflows/reusable-release.yml`: `jobs.release`
    → `130`. A second member after a compliant first: release now exceeds CI in the `max`.
  - `green1-release-absorbed-by-max`: `reusable-release.yml` `jobs.release` → `70` must PASS
    (`max(70,70)` absorbs it; the brief's additive form would have read 275 and reddened). A
    "lower a term" row was considered and dropped: lowering a term of a monotone sum can never red
    a green control, so it discriminates nothing.
  - `green2-test-scripts-at-boundary`: `test-scripts` → the value that puts crit exactly at the
    threshold, DERIVED in the harness from the control child's emits (`THRESH_MIN − (crit −
    ci_declared_path) − test`, = 65 today) so a legitimate future ceiling move does not turn a
    must-PASS row into a confusing red; the fail text names the seven terms.
- Floors: `MIN_C` 13 → 18 and `MIN_ASSERTIONS` 151 → 156 (the file asserts
  `MIN_ASSERTIONS == MIN_A + MIN_B + MIN_C`).

### `.github/workflows/web-platform-release.yml`

- `resolve-target` job: `timeout-minutes: 60` → `15`; rewrite its ceiling comment (the "60 = the
  `release` job's own ceiling ... must not EXCEED" block) opening in ci.yml's canonical two-line
  shape — `# 15m — measured max 14s over 9 successful workflow_run runs ending 2026-09-14 (#<PR>);`
  / `# >=60x headroom. Was 60m (= the release ceiling, sized for a max() B9 no longer uses).` —
  so the derivation is auditable without re-running the loop; the term is
  additive in B9 now, so it is sized on its own execution: 3x the measured max rounds to under a
  minute, and 15 is the #8020 floor convention every `ci.yml` ceiling already uses. Consequence,
  not sizing: a live poll (arms un-coupled) fails closed here at 15 m instead of waiting an hour,
  which is the loud warning ADR-217 D3 wanted. The comment cites the constant and B9 by NAME and
  carries no derived pipeline number.
- "Derive the CI budget and check for creep" step: `RT=$(job_ceiling "$REL" resolve-target)`;
  add `resolve-target:$RT` to the emptiness loop; `CI_BUDGET_MIN=$(( THRESHOLD - RT - M - V - D ))`
  (= 225 − 15 − 30 − 15 − 90 = 75 on the 2026-09-14 tree). Rewrite the `TWO DIFFERENT
  QUANTITIES` comment to name the terms (`DRIFT_SUSTAINED_THRESHOLD_MIN minus resolve-target,
  migrate, verify-migrations, deploy`) with NO numeric reading — the step prints the live values,
  and a number in a comment is the stale-comment liability the tree already carries three of.
  The `::error::`/`::warning::` texts spell out the subtraction with the live values and name
  `resolve-target`. State in the comment that the release ceiling is
  deliberately NOT read here — `CI_BUDGET_MIN` is CI's share under `max(ci, release)`, and B9 is
  the site that asserts the full path including release — so nobody "fixes" it with a callee read.
- `deploy` job comment (the `max(release 60, CI-to-test 70, resolve-target 60) ... = 205` block):
  the one formula by term NAME, "computed by B9 in scripts/prod-version-drift-check.test.sh
  against DRIFT_SUSTAINED_THRESHOLD_MIN" — no numbers; keep the "RAISING any of these fails that
  suite" sentence.
- Soft ceiling stays `CI_BUDGET_MIN * 60 * 7 / 10` → 3150 s (52.5 m; was 3024 s).

### `.github/workflows/reusable-release.yml`

- The "COUPLED (#7160)" comment above `jobs.release.timeout-minutes: 60`: "Deleting this line
  raises the computed path to 495" → "Deleting this line reads as the GitHub 360 default and reds
  B9 by name" — no number.

### `.github/workflows/scheduled-prod-version-drift.yml`

- The comment reading "threshold 195m + up to ..." (end-to-end detection paragraph) is a third
  stale restatement; make it "threshold `DRIFT_SUSTAINED_THRESHOLD_MIN` + up to ...". Comment-only;
  the drift suite's sandbox copies this file, and no assertion reads the sentence.

### `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` — GUARD 5

- G5-21 input loop: `for jobname in migrate verify-migrations deploy resolve-target` (asserts the
  call form `job_ceiling "$REL" resolve-target)`). No new row, so the suite's itemised floor
  (67) is unchanged.
- G5-18: tighten its regex from `CI_BUDGET_MIN=\$\(\(\s*THRESHOLD` to
  `CI_BUDGET_MIN=\$\(\(\s*THRESHOLD - RT - M - V - D` — the partition names `RT`, so dropping
  the term silently is caught; the row's fail text names the four terms and says the order is
  pinned deliberately (the partition is the property).

### ADR-217 Decision 4 addendum, ADR-212 pointer (no new ADR)

- ADR-217: a `> **Addendum (2026-09-14).**` block after the existing Correction: option (a), the
  one formula, the numbers (`crit = 220`, threshold 225, `resolve-target` 15, `CI_BUDGET_MIN = 75`,
  soft ceiling 52.5 m), the cost (18 m on a 61–243 m delivery interval), the slack statement, and
  the rejected options one line each. Correct the `CI_BUDGET_MIN = 207 − (30 + 15 + 90) = 72`
  bullet in place with a strike-through note pointing at the addendum (do not silently rewrite).
- ADR-212: one dated line under its `= 72` blockquote pointing at the ADR-217 addendum.

## Item 2 — design

### Fold three `ci.yml` jobs into `lint-bot-statuses`

Insert three steps into `lint-bot-statuses` BEFORE `Install actionlint (pinned, sha-verified)` (a
network fetch that can flake must not sit upstream of them), each carrying the deleted job's
step-level `env:` and `run:` VERBATIM, `if: ${{ !cancelled() }}` so a red earlier step does not
mask them (each reports independently under its own name, which is what `gh run view
--log-failed` and `/soleur:postmerge` read), and a step name that preserves the old job name as a
searchable token:

```yaml
      - name: readme-counts (README component counts match filesystem, #<PR>)
        if: ${{ !cancelled() }}
        run: bash scripts/sync-readme-counts.sh --check
      - name: lint-conversations-update-callsites (R8, #<PR>)
        if: ${{ !cancelled() }}
        run: bash scripts/lint-conversations-update-callsites.sh
      - name: rule-metrics-shape (validate rule-metrics.json, #<PR>)
        if: ${{ !cancelled() }}
        env:
          METRICS_FILE: knowledge-base/project/rule-metrics.json
        run: |
          <the existing multi-line run: block, unchanged>
```

`plugins/soleur/scripts/grok-pre-push-gate.sh` mirrors the fast ci.yml jobs by NAME
(`run_step "readme-counts" ...`, `run_step "lint-conversations-update-callsites" ...`) and
`plugins/soleur/test/workflow-fidelity.test.ts` asserts the gate contains `readme-counts`; both
mirror the SCRIPT invocations, not the job structure, so they stay unchanged and keep passing —
the folded step names carry the same tokens for exactly this kind of reader.

**`encryption-posture` is deliberately NOT folded** (security review): ci.yml's own note (#6901) says
the job was EXTRACTED from `lint-bot-statuses` so its status is attributable to the sweep alone —
the prerequisite for the measure-then-arm soak toward a required check (ADR-140 amendment
2026-07-24; #6907 OPEN). Folding it back would reset that streak and reverse ADR-140 without an
addendum. `rule-metrics-shape`'s
`env: METRICS_FILE:` is load-bearing: its `run:` opens with
`if [[ ! -f "$METRICS_FILE" ]]; then ... exit 0`, so a fold that drops the env block makes the
check exit 0 forever on an empty path (caught at plan review). Delete the three job blocks. Read
`lint-bot-statuses`'s checkout `with:` first and keep it (the three scripts are full-tree lints,
indifferent to depth). Update the job's ceiling comment (`measured max 0.7m`) to note the three
folded steps (each 0.2 m; the job goes from 11 to 14 steps); keep `timeout-minutes: 15`. The
dispatch note's
"measured over the 23 jobs with NO `needs:`" is a dated measurement — leave the figure, append
"(20 after the 2026-09-14 fold)".

### PR-only cancellation on the five stateless per-PR workflows

Add ci.yml's workflow-level block verbatim (same comment pointer to ADR-217 D1) to
`pr-quality-guards.yml`, `secret-scan.yml`, `dependency-review.yml`,
`legal-doc-cross-document-gate.yml`, `skill-security-scan-pr-trailer.yml`:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

`secret-scan.yml` and `pr-quality-guards.yml` also carry `merge_group:` and `secret-scan.yml` runs
on `push` to `main` — the per-SHA arm with `cancel-in-progress: false` covers both, exactly as
ci.yml's does. `secret-scan.yml`'s `labeled`/`unlabeled` types re-run the whole workflow, so a
label event superseding a `synchronize` run is the intended outcome. Both files are `@deruelle`
CODEOWNERS rows (the operator is the author of this PR).

### `scripts/pr-fanout-ledger.txt`

Plain text, `#` comments, tab-separated columns, mirroring `scripts/required-checks.txt`'s shape:

```text
# scripts/pr-fanout-ledger.txt — every workflow that fires on a PULL REQUEST PUSH.
#
# "Fires on a PR push" = declares on.pull_request or on.pull_request_target with no
# `types:` or with `synchronize` in `types:`. Workflows gated to opened/closed only
# are not in the generator and have no row.
#
# jobs = the workflow's DECLARED job count — an upper bound on runner slots per push
# (if:-skipped jobs are declared but consume nothing). paths = yes when the trigger
# carries a paths/paths-ignore filter (a pull_request.branches filter is NOT a paths
# filter; such a workflow is still ledgered as firing). cancel = yes ONLY when a
# superseded push actually cancels the run: cancel-in-progress is `true` or ci.yml's
# `${{ github.event_name == 'pull_request' }}` ternary (the two accepted spellings —
# any other expression fails A4c), AND the group expression references `github.ref`
# or `github.event.pull_request.number` (a per-SHA group never cancels a superseded
# push, so it is `no` however cancel-in-progress reads). Workflow-level or job-level
# blocks both count. consequence = what breaks if this does not run on every PR push,
# or why cancel is no; a row with no consequence is a row that should not exist.
# Columns are TAB-separated (unlike required-checks.txt, which is one name per line);
# a row with any other field count fails A-parse by line number.
#
# The test (plugins/soleur/test/pr-fanout-ledger.test.sh) reddens on: a firing workflow
# with no row; a row whose workflow no longer fires; a workflow declaring MORE jobs than
# its row; a paths or cancel flag that disagrees with the file. Growth requires editing
# this file, and editing this file requires naming the consequence (ADR-216 shape;
# ADR-216 addendum 2026-09-14). The jobs column is a CEILING: lower it when a workflow
# shrinks; raise it only with a named consequence. A reader who raises a row to match a
# file that GREW has reversed the ratchet. Next reduction candidate, measure first: the
# remaining advisory ci.yml jobs.
#
# Format: <workflow><TAB><jobs><TAB><paths><TAB><cancel><TAB><consequence>   (comment lines: leading-# only)
# workflow	jobs	paths	cancel	consequence
ci.yml	22	no	yes	required contexts per scripts/required-checks.txt (ADR-032 ABI) plus their needs; advisory lints ride in lint-bot-statuses
pr-quality-guards.yml	10	no	yes	required contexts markdown-lint + Bash fixture tests for guard scripts (ADR-032 ABI)
secret-scan.yml	6	no	yes	required contexts gitleaks scan / lint fixture content / allowlist-diff / rename-guard / waiver discipline (ADR-032 ABI); the weekly schedule arm keys on main HEAD's SHA and so shares the push-arm group — a same-SHA rerun of the push run can drop a pending weekly scan (no heartbeat on this workflow)
apply-sentry-infra.yml	5	no	no	required context sentry-destroy-required, always-run aggregator over a path-gated plan (#6589); no cancel: terraform plan holds a backend state lock
tenant-integration.yml	3	no	no	required context tenant-integration-required, always-run aggregator over a path-gated suite (#5585); no cancel: holds the dev-Supabase mutex, a mid-run cancel leaves fixture residue
dependency-review.yml	1	no	yes	required context dependency-review (ADR-032 ABI)
legal-doc-cross-document-gate.yml	1	no	yes	required context enforce (#4384)
skill-security-scan-pr-trailer.yml	1	no	yes	required context skill-security-scan PR gate (#3542 R15)
cla.yml	1	no	no	CLA Required ruleset context cla-check (pull_request_target); no cancel: privileged trigger, keep its run shape untouched
cla-evidence.yml	1	no	no	CLA Required ruleset context cla-evidence (pull_request_target); same
constraint-gates.yml	1	no	no	ADR-071 L1 import-boundary dogfood; always-run by template design (promotable to required without a paths deadlock); body parity-locked to the constraint-scaffold template, so no concurrency block either
pr-auto-close-scanner.yml	1	no	yes	#3407 auto-close keyword scan must see every commit message because the squash commit is built from them
claude-code-review.yml	2	no	no	disabled on GitHub's side since 2026-02-12 (state not in the tree); kept because it is Art. 30 register PA-33 member (6); re-enable or delete only with a dated register correction
fix-constraints-stage-a.yml	1	yes	no	ADR-074 stage-A recovery, path-filtered to the target app; cancel-in-progress is true but the group is per head SHA (one paid agent dispatch per SHA), so a superseded push never cancels it
gdpr-gate-self-test.yml	3	yes	no	gdpr-gate fixture self-test, path-filtered to the skill
infra-validation.yml	9	yes	no	terraform validate/fmt/plan over infra roots, path-filtered; no cancel: plan holds a backend state lock
rls-authz-fuzz.yml	1	yes	yes	RLS fuzz, path-filtered to migrations/policies; cancels per ref already
sentry-audit-gate.yml	1	yes	no	Sentry IaC audit, path-filtered to apps/web-platform/infra/sentry
skill-security-scan-corpus.yml	1	yes	no	corpus scan, path-filtered to the scanner's rules/scripts
validate-vector-config.yml	1	yes	no	vector.toml validation, path-filtered
vendor-pin-verify.yml	1	yes	no	vendored-pin verification, path-filtered
```

The `jobs`, `paths` and `cancel` columns are written from the live tree at work time (`python3`
over PyYAML); the values above are the 2026-09-14 reading and the work phase must re-derive them,
not copy them. Consequence text is a shape requirement (non-empty, ≥ 4 words), not a semantic one
— the discipline ADR-216 states for its own gate.

### `plugins/soleur/test/pr-fanout-ledger.test.sh`

Auto-discovered by `scripts/test-all.sh`'s `plugins/soleur/test/*.test.sh` glob; runs in the
`test-scripts` shard that rolls up into the required `test` check. Bash + PyYAML (the dependency
the drift test and c4-count-parity already use). Env overrides `PR_FANOUT_WORKFLOWS_DIR` and
`PR_FANOUT_LEDGER` so Part B can run against a temp copy. Enumerator edge cases, each with a
Part B row or a fixture: list-form and string-form `on:`; PyYAML's `on` → `True` key;
`pull_request: null` (`ci.yml`, `legal-doc-cross-document-gate.yml` parse to `None` — always
`(v or {})`); `types:` as a string; `concurrency:` as a string shorthand; job-level
`concurrency` (cancel = any of workflow-level or job-level); `pull_request_target`.

Part A (live tree):

- A0 vacuity floor: the enumerator finds ≥ 15 firing workflows (today 21). Enforced with a direct
  `[[ "$found" -lt 15 ]] && { echo FAIL...; exit 1; }`, never through `fail`, so
  `scripts/guard-vacuity-floor.test.sh`'s neutered-machinery sweep can construct its mutant.
- A1 every firing workflow has a ledger row (message names the file and the three honest exits:
  add a row naming the consequence; drop `pull_request`; gate `types:` to open/close).
- A-parse every non-comment ledger line has exactly 5 TAB-separated fields (message: `line N:
  expected 5 TAB-separated columns, got M (spaces are not separators)`; A1's message shows one
  example row verbatim).
- A2 every ledger row names a file that exists and fires (message: "row for X but X does not fire
  on a PR push — delete the row, or restore the trigger").
- A3 declared jobs ≤ row (message: "N declared, row allows M — raise the row and name why; do not
  delete the job to satisfy the ledger").
- A4 `paths` flag equality; A4b `cancel` flag equality per the header's definition (cancel form
  AND group shape; the group rule accepts `github.ref`, `github.head_ref`, `github.ref_name`,
  `github.event.number`, `github.event.pull_request.number`); A4c a `cancel-in-progress` value
  that is not `true`, `false` or the ci.yml ternary fails closed (`false` is a live value —
  `apply-sentry-infra.yml` — so it must be accepted or the baseline reds), and the message prints
  the accepted spellings verbatim. A4/A4b messages: "edit the row or the file, and name why".
- A5 consequence ≥ 4 words.
- A7 assertion-count floor in the shape the vacuity meta-guard recognises — `MIN_CASES=<n>` (the
  sibling suites' `MIN_ROWS` idiom) and `if [[ "$CASES" -lt "$MIN_CASES" ]]` over a counter the
  suite itself increments at every call site (`CASES=$((CASES+1))`), whose body is a direct
  `echo "FAIL: only $CASES assertions ran (floor $MIN_CASES)" >&2; exit 1` — never routed through
  `fail`, because `scripts/guard-vacuity-floor.test.sh` neuters `fail` in its mutant and classifies
  a floor that still reports as FIRES; bump its `MIN_FIRING_SUITES` 38 → 39 so the new suite is
  counted. A0 stays a direct `exit 1` after asserting `found` matches `^[0-9]+$` (a computed
  count, deliberately outside the meta-guard's population) so an unreadable tree cannot reach
  `print_results` at all.

Part B (mutation battery; each mutant gets its OWN fresh `mktemp -d -t pr-fanout.XXXXXXXX` copy of
`.github/workflows/` + the ledger, `trap 'rm -rf' EXIT`, so a deleted file in one row cannot leak
into the next; each mutant must fail on the named row, and the must-PASS rows grep the row's
`PASS:` line — `PASS: A1 … firing / … ledgered`, `PASS: A3` — not just exit 0): see the Guard
Contract. The child is re-invoked with `PR_FANOUT_PARTS=A PR_FANOUT_MIN_CASES=0` (recursion guard
+ floor override, the drift suite's `DRIFT_TEST_PARTS`/`DRIFT_MIN_*` idiom). Local `pass()`/
`fail()` helpers with `A0`/`B1` row prefixes as in `scripts/prod-version-drift-check.test.sh`
(`plugins/soleur/test/test-helpers.sh` defines `assert_*` and `print_results`, not `pass`/`fail`);
the floor is A7's inline counter check.

### Decision records: dated addenda, no new ADR

Two reviewers independently found that the queue decision already has a home (ADR-032's
2026-06-30 amendment + 2026-07-01 correction, the PIR, the README re-adoption checklist, the
monthly watcher) and that the ledger is the second instance of ADR-216's mechanism. A new ADR
would restate both and buy an ordinal race (218 is branch-claimed). So:

- **ADR-032**, a new `## Amendment — 2026-09-14 (#<PR>): the queue stays off — capacity factor and
  reopener (iii)` section (the file's house style: `## Amendment — YYYY-MM-DD (#NNNN)` x4; the
  blockquote form is reserved for corrections/rulings) carrying only what
  is new — the capacity factor (a queue adds a full `merge_group` run per merge on a Free-plan
  20-slot pool that already binds 76% of runs; `check_response_timeout_minutes` vs the measured
  28-minute start spread), reopener (iii) plan capacity alongside the existing (a)/(b), the
  producer/`merge_group` enumeration as of this date (22 `@15368` contexts wired, CLA pair not,
  `CodeQL@57789` cannot), and the pointer to the ADR-216 addendum for what was done instead.
- **ADR-216**, new section `### Addendum 2026-09-14 — the second instance: the per-PR workflow
  generator`: the generator/finite-resource/symptom row, the fold (−3 declared jobs), the
  cancellation set and its three exclusions with reasons, the ledger + test as the filing-time
  lever (shape check, not semantic — the same discipline as the issue gate), and the two things
  deliberately not done (path-filtering `constraint-gates.yml` — parity-locked; deleting the
  disabled workflow — PA-33 member snapshot).
- **ADR-217** Decision 4 addendum (a `> **Addendum (2026-09-14).**` blockquote directly after the
  existing `> **Correction (2026-09-10).**` — locally consistent) and the one-line ADR-212
  pointer, as in Item 1.

`knowledge-base/INDEX.md` is unaffected (no new file).

## Files to Edit

| File | Change |
|---|---|
| `scripts/prod-version-drift-check.sh` | `DRIFT_SUSTAINED_THRESHOLD_MIN=225`; header formula + dated 207→225 paragraph |
| `scripts/prod-version-drift-check.test.sh` | B9 formula `max(ci, release) + resolve-target + ...`; dated decision comment; B9 labels + remedy text; three RED axes + two must-PASS rows (`mutate_and_assert_green`); `MIN_C`/`MIN_ASSERTIONS` |
| `.github/workflows/web-platform-release.yml` | `resolve-target` `timeout-minutes` 60 → 15 + comment; budget step reads `resolve-target`, `CI_BUDGET_MIN = THRESHOLD - RT - M - V - D`; comments and messages; `deploy` job comment |
| `.github/workflows/reusable-release.yml` | the "COUPLED (#7160)" comment: no computed-path figure, names B9 |
| `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` | G5-21 loop gains `resolve-target`; G5-18 regex tightened to the `- RT - M - V - D` partition |
| `.github/workflows/ci.yml` | delete jobs `readme-counts`, `lint-conversations-update-callsites`, `rule-metrics-shape` (NOT `encryption-posture` — #6901/#6907 soak); insert their steps into `lint-bot-statuses`; ceiling comment; dispatch-note parenthetical |
| `.github/workflows/pr-quality-guards.yml`, `secret-scan.yml`, `dependency-review.yml`, `legal-doc-cross-document-gate.yml`, `skill-security-scan-pr-trailer.yml` | workflow-level PR-only `concurrency` block (ci.yml's verbatim) |
| `knowledge-base/engineering/architecture/decisions/ADR-217-...md` | Decision 4 addendum; correct the `= 72` bullet |
| `knowledge-base/engineering/architecture/decisions/ADR-212-deploy-gate-measures-its-own-gated-quantity.md` | one dated pointer line under the `= 72` blockquote |
| `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` | dated addendum under the 2026-06-30 amendment (capacity factor, reopener (iii), producer enumeration, pointer) |
| `knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md` | `### Addendum 2026-09-14` — the second instance (per-PR workflow generator), the fold, the cancel set, the ledger |
| `.github/workflows/scheduled-prod-version-drift.yml` | comment: "threshold 195m" → the constant by name |
| `scripts/guard-vacuity-floor.test.sh` | `MIN_FIRING_SUITES` 38 → 39 |

## Files to Create

| File | Purpose |
|---|---|
| `scripts/pr-fanout-ledger.txt` | the per-PR fan-out ledger (format above) |
| `plugins/soleur/test/pr-fanout-ledger.test.sh` | the ledger gate + its mutation battery |
| `scripts/prod-version-drift-b9-probe.sh` | 2-line Parts-AB wrapper (`DRIFT_TEST_PARTS=AB exec bash "$(dirname "$0")/prod-version-drift-check.test.sh"`) — the preflight Check 10 discoverability probe; `scripts/lint-orphan-test-suites.sh` globs `*.test.sh`, so a non-`.test.sh` name keeps it out of the suite registry |

No file is deleted. No ruleset, secret, or infrastructure resource changes; the IaC routing gate
(Phase 2.8) does not fire — every edit is to workflow YAML, test scripts and knowledge-base
documents.

## Implementation Phases

Contract-changing edits land before their consumers, and the Item 1 sites land in ONE commit (B9
asserts threshold ≥ path; the workflow asserts `CI_DECLARED_PATH <= CI_BUDGET_MIN`; a split
reddens one of them in between).

### Phase 0 — preconditions (read, no edits)

1. `DRIFT_TEST_PARTS=AB bash scripts/prod-version-drift-check.test.sh 2>&1 | grep -E "B9|B8e"` →
   `B9 threshold (207m) >= release declared critical path (195m)`, `B9c ... (70m)`.
2. `gh api repos/github/codeql-action/issues/1537 --jq .state` → `open` (if `closed`, STOP: the
   Item 2 premise changed; re-plan against ADR-032's re-adoption recipe rather than shipping the
   ledger as the answer).
3. Confirm `fix-constraints-stage-a.yml` still carries a per-head-SHA group and
   `rls-authz-fuzz.yml` a per-ref group with `cancel-in-progress: true` (the two rows whose
   `cancel` value the header's group-shape rule decides).

### Phase 1 — Item 1, RED first

1. Write the three RED axes, the `mutate_and_assert_green` helper and the two must-PASS rows;
   bump `MIN_C`/`MIN_ASSERTIONS`; run `DRIFT_TEST_PARTS=C bash scripts/prod-version-drift-check.test.sh`
   → `axis13` must FAIL ("child exit 0 (SURVIVED)") because the CI term is not yet in the sum;
   `axis14` likewise (`max(60,70) + 135 = 205 ≤ 207` — the term is inside a `max()` today);
   `axis15` is already caught (release is in the current `max`), and both green rows already
   pass — so the RED-first evidence is axes 13 and 14 only. Record the output.
2. Edit G5 in `workflow-run-deploy-invariants.test.sh` (loop token + tightened G5-18); run it →
   G5-18 and the `resolve-target` call-form row FAIL.
3. In ONE commit: threshold 225; B9 formula + comments + labels; `resolve-target` 60 → 15 + its
   comment; the workflow budget step; the `deploy` comment; the reusable-release comment; the `.sh`
   header. **Run every suite against the STAGED tree before `git commit`** (Parts A, B, C;
   `workflow-run-deploy-invariants`; `resolve-target-decision`) → all green; `B9 threshold (225m)
   >= declared merge-to-deploy critical path (220m)`; `axis13`/`axis14`/`axis15` "caught by B9
   threshold". Only then commit. Comments at every site cite the terms by NAME
   (`DRIFT_SUSTAINED_THRESHOLD_MIN`, `resolve-target`'s `timeout-minutes`, ...) and carry the
   numeric reading once, dated — the workflow already derives `THRESHOLD` at runtime via
   `read_threshold` (G5-18 asserts it), so the only literal that moves is the `.sh` constant.
4. `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh` and
   `bash plugins/soleur/test/resolve-target-decision.test.sh` → green.
5. `actionlint .github/workflows/web-platform-release.yml .github/workflows/reusable-release.yml`
   (reuse the pinned install line from `lint-bot-statuses`), and `bash -n` over the budget step's
   extracted `run:` body (`$W/budget.blk` from the G5 extractor) — never `bash -n` on the YAML.
6. ADR-217 D4 addendum; ADR-212 pointer.

### Phase 2 — Item 2, RED first

1. Write `scripts/pr-fanout-ledger.txt` with rows for the CURRENT tree (21 rows; `ci.yml` 25;
   `cancel=no` on the five target workflows and on `fix-constraints-stage-a.yml`; `cancel=yes` on
   `rls-authz-fuzz.yml` and `pr-auto-close-scanner.yml`), then the test with Part A only; run →
   green (the baseline proves the enumerator reads the real tree; a red here means the header's
   rules and the tree disagree — fix the rule, never the tree). Write Part B; run → every mutant
   caught. Bump `MIN_FIRING_SUITES` in `scripts/guard-vacuity-floor.test.sh` and run it.
2. Fold the three `ci.yml` jobs into `lint-bot-statuses`; run the test → A3 does NOT redden (fewer
   jobs than the row is allowed); lower the `ci.yml` row 25 → 22 so the ratchet holds the new
   floor. `actionlint .github/workflows/ci.yml`; `bash plugins/soleur/test/ci-concurrency-key.test.sh`.
3. Add the concurrency block to the five workflows; run the test → A4b reddens on all five
   (ledger still says `no`); flip the rows to `yes` → green. (This is the harness proving A4b live,
   recorded in the PR body.) `actionlint` the five files.
4. `DRIFT_TEST_PARTS=B bash scripts/prod-version-drift-check.test.sh` again → B9b `0 <= 0` and B9c
   still `70m` (the longest path is unchanged: `test-scripts 60 → test 10`).
5. ADR-032 addendum + ADR-216 addendum (no new file; no INDEX regeneration).
6. `bash plugins/soleur/test/c4-count-parity.test.sh` and
   `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` → green.

### Phase 3 — whole-battery and evidence

1. `bash scripts/test-all.sh` (the full scripts group; the drift suite, the deploy-invariants
   suite, the new ledger suite, the parity suite and the vacuity-floor meta-guard all run here).
   In CI the group is split across the three `test-scripts` matrix legs; the two halves of the
   Item 1 invariant (B9 and G5) may land on different legs, and every leg feeds the single
   required `test` aggregator, so a red on either side reddens the same check — no
   cross-assertion is needed.
2. `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-14-chore-drift-threshold-ci-term-and-pr-fanout-ledger-plan.md`
   → 0 failures.
3. PR body carries: the RED-first outputs (axis13/axis14 SURVIVED → caught; G5-18 red → green;
   the ledger A4b flip), the before/after declared-job count over the non-path-filtered firing
   workflows (56 → 53, excluding the disabled workflow's 2; 19 cancellable on a superseded push),
   and the `resolve-target` measurement.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The worst case is internal:
  a wrong `CI_BUDGET_MIN` arithmetic or a too-low `resolve-target` ceiling reddens `resolve-target`
  on the `workflow_run` arm and blocks a production deploy until fixed (the fail-closed shape of
  #7902 — loud, and the `release-outcome` email names it), or a wrong ledger row reddens the `test`
  check on every PR until the row is corrected. Both are one-line fixes on files this PR owns.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data path is touched;
  no secret is added, moved or read.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches .github/workflows/, scripts/, plugins/soleur/test/ and knowledge-base/ only — CI machinery and an internal alert threshold; no request path, no persisted user data, no legal surface.`

## Observability

```yaml
liveness_signal:
  what: "the drift check's own Sentry cron heartbeat (scheduled-prod-version-drift.yml, sentry-heartbeat composite) — unchanged by this plan; the threshold it evaluates moves 207 -> 225"
  cadence: "*/30 * * * * (GitHub schedule, measured 61-243 min effective)"
  alert_target: "GitHub issue + operator email on DRIFT_SUSTAINED / CHECK_ERROR (workflow B3c/B3d alerting steps)"
  configured_in: ".github/workflows/scheduled-prod-version-drift.yml; apps/web-platform/infra/sentry/cron-monitors.tf"

error_reporting:
  destination: "GitHub Actions run logs + the `::error::` annotation in web-platform-release.yml's budget step (resolve-target job) — fail-closed on an underived budget; release-outcome email on any non-delivery"
  fail_loud: "resolve-target job red with `CI declares Nm ... but the pipeline budget allows only Mm (DRIFT_SUSTAINED_THRESHOLD_MIN 225 minus resolve-target 15 minus migrate 30 ...)`, or red at its 15 m ceiling if the liveness poll ever goes live"

failure_modes:
  - mode: "threshold moved without the CI term landing (or vice versa) — B9 red on every PR"
    detection: "scripts/prod-version-drift-check.test.sh B9 in the test-scripts shard (required `test` check) — workflow run log (gh run view --log-failed) + PR check annotation"
    alert_route: "PR check red; nothing merges"
  - mode: "budget partition drifts from B9's partition (workflow subtracts a different set than the test)"
    detection: "workflow-run-deploy-invariants.test.sh G5-21 (resolve-target call form) + tightened G5-18 — workflow run log (gh run view --log-failed) + PR check annotation"
    alert_route: "PR check red"
  - mode: "resolve-target exceeds its new 15 m ceiling on a real run"
    detection: "job lands as needs.resolve-target.result cancelled/failure with SKIP_REASON empty; release-outcome's classify() failure|cancelled arm fills FAILED and the Resend step fires (web-platform-release.yml, Classify the run outcome)"
    alert_route: "release-outcome email + Sentry non-delivery mirror; NOT Slack — notify-gated's if: keys on CI conclusion or an enumerated skip_reason, and a ceiling trip sets neither"
  - mode: "a new workflow adds pull_request without a ledger row, or a cancel/paths flag drifts"
    detection: "pr-fanout-ledger.test.sh A1/A4/A4b in the test-scripts shard — workflow run log (gh run view --log-failed) + PR check annotation"
    alert_route: "PR check red with the file named and the honest exits listed"
  - mode: "ledger enumerator goes blind (workflows dir unreadable / PyYAML absent)"
    detection: "A0 vacuity floor (< 15 firing workflows found) exits 1 directly — workflow run log + PR check annotation"
    alert_route: "PR check red"

logs:
  where: "GitHub Actions job logs (test-scripts shard; resolve-target job on the release workflow)"
  retention: "90 days (GitHub default)"

discoverability_test:
  command: "bash scripts/prod-version-drift-b9-probe.sh"
  expected_output: "PASS: B9 threshold (225m) >= declared merge-to-deploy critical path (220m)"
  # scripts/prod-version-drift-b9-probe.sh is a 2-line repo-relative wrapper committed in this PR:
  #   DRIFT_TEST_PARTS=AB exec bash "$(dirname "$0")/prod-version-drift-check.test.sh"
  # Preflight Check 10 rejects shell-active characters (| > &) and env-prefix first tokens, and
  # its 15 s sandbox timeout is under the full ABC run (26 s measured; more with the new rows);
  # Parts AB run in ~2 s. Check 10 substring-matches expected_output, so no grep is needed.
  # Deployed state == main's tree (scheduled-prod-version-drift.yml runs the checker from
  # checkout), so this probe of the tree IS the probe of the live checker.
post_merge_confirmation: "gh run view <next scheduled-prod-version-drift run id> --log | grep 'threshold 225m' (emitted only when an undeployed commit exists; /soleur:postmerge reads it — credentialed, so outside Check 10)"
```

## Architecture Decision (ADR/C4)

### ADR

- **ADR-217 — amend** Decision 4 with the dated addendum (Item 1). Same ADR, no new ordinal (the
  CTO's reading, adopted).
- **ADR-032 — amend** with a dated addendum (queue stays off; new capacity factor; reopener
  (iii)). **ADR-216 — amend** with a dated addendum (the second instance of the ledger +
  filing-time lever). No new ADR: both decisions already have an owning record, and a new ordinal
  would restate them and race a branch-claimed 218.

### C4 views

No C4 impact, and the check was made against all three model files, not by grepping the feature's
noun: the external actors are the operator (already modelled as `founder`) and GitHub (already
modelled as the external `github` system with CI/CD in its description); no new vendor, store, or
container; no actor↔surface access relationship changes. The `github -> sentry` edge's embedded
counts (C1/C2/C3/C5 in `plugins/soleur/test/c4-count-parity.test.sh`) derive from
`actions/sentry-heartbeat` users, schedule keys, and `monitor-slug` values — none of the touched
workflows or folded jobs carry any of them (`grep -c` = 0 on each), and the gate was run green at
plan time (`ALL TESTS PASSED`). The `github -> resend` C7 emitter count is likewise untouched.

### Sequencing

None — the ADR describes the state this PR ships, `status: accepted`.

## Guard Contract

### Guard 1 — B9 honest merge-to-deploy path

**Property.** `DRIFT_SUSTAINED_THRESHOLD_MIN` is never smaller than the pipeline's declared
merge-to-deploy critical path, where that path is `max(ci.yml longest needs-path, release ceiling)
+ resolve-target + migrate + verify-migrations + deploy`, every term read from the tree.

**Assembly.** The chokepoint is the Python extractor in `scripts/prod-version-drift-check.test.sh`
(the block ending `emit("RELEASE_CRITICAL_PATH_MIN", crit)`), which reads: every job's
`timeout-minutes` and `needs:` in `.github/workflows/ci.yml` (memoised longest path, 360 default
for an undeclared job); `jobs.release.uses` in `web-platform-release.yml` resolved to the callee
`reusable-release.yml`'s `jobs.release.timeout-minutes`; and `resolve-target`, `migrate`,
`verify-migrations`, `deploy` `timeout-minutes` in `web-platform-release.yml`. The threshold is
read from `scripts/prod-version-drift-check.sh` by A0d. B8e pins the `needs:` closure to `deploy`
so a topology change cannot route around the sum. `make_sandbox` must copy `ci.yml` and the
resolved callee, or every Part C child reads the 360 default (B9c reds on a blind CI extractor).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `ci.yml` `test-scripts` → `130` (axis13) | RED — `FAIL: B9 threshold` |
| 2 | `resolve-target` → `70` (axis14; the term is additive) | RED — `FAIL: B9 threshold` (220 → 275) |
| 3 | `reusable-release.yml` `jobs.release` → `130` (axis15; a second member after a compliant first: release now exceeds CI in the `max`) | RED — `FAIL: B9 threshold` (220 → 280) |
| 4 | delete `deploy`'s `timeout-minutes` line (reads as 360) | RED — `FAIL: B9 threshold` (pre-existing behaviour; verified once at work time, not shipped) |
| 5 | remove `ci.yml` from `make_sandbox` (the guard's own dispatch: CI term unreadable) | RED — `FAIL: B9c` in every child, C0 control red (verified once at work time) |
| 6 | `jobs.release` → `70` (green1) | must PASS (`max(70,70)` absorbs it; 220 ≤ 225) — non-canonical green |
| 7 | `test-scripts` → the derived boundary value (65 today; green2) | must PASS (225 ≤ 225); 130 is the RED edge axis13 proves |
| 8 | harness row: in the test, change B9's `-ge` to `-le` | RED — the live tree (225 vs 220) fails B9 (verified once at work time) |

Rows 1–3, 6, 7 ship as Part C rows. Rows 4, 5, 8 are one-time verifications during the work
phase, recorded in the PR body; they are not shipped because they mutate the harness itself or
re-prove pre-existing behaviour.

### Guard 2 — PR fan-out ledger

**Property.** Every workflow that fires on a pull-request push has a ledger row that names its
consequence, bounds its declared job count and records its `paths` and `cancel` shape, and no
ledger row outlives its workflow.

**Assembly.** The chokepoint is the PyYAML enumerator in
`plugins/soleur/test/pr-fanout-ledger.test.sh` over `${PR_FANOUT_WORKFLOWS_DIR:-.github/workflows}/*.yml`:
a file is "firing" when `on.pull_request` or `on.pull_request_target` is present (dict, list or
string form of `on:`; PyYAML's `True` key) and `types` is absent or contains `synchronize`; its job
count is `len(jobs)`; its `paths` flag is the presence of `paths`/`paths-ignore` under that
trigger; its `cancel` flag is whether the workflow-level `concurrency.cancel-in-progress` is `true`
or the `event_name == 'pull_request'` ternary. The ledger is
`${PR_FANOUT_LEDGER:-scripts/pr-fanout-ledger.txt}`, comment-stripped, tab-split. Both sides are
derived independently — the real set never comes from the ledger's own row count.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | add `zz-new.yml` with `on: pull_request` and one job, no row | RED — A1 names `zz-new.yml` |
| 2 | add a 23rd job to `ci.yml` (a second member after the compliant 22) | RED — A3 `23 declared, row allows 22` |
| 3 | delete the `pr-quality-guards.yml` row | RED — A1 |
| 4 | delete `secret-scan.yml` from the copy, keep its row | RED — A2 ghost row |
| 5 | flip `infra-validation.yml`'s `paths` flag to `no` in the ledger | RED — A4 |
| 6 | remove the `concurrency:` block from the copy's `pr-quality-guards.yml`, keep `cancel=yes` | RED — A4b |
| 6b | rewrite the copy's `pr-quality-guards.yml` group to a per-SHA key, keep `cancel=yes` | RED — A4b (group shape) |
| 6c | set `cancel-in-progress: ${{ github.event_name != 'push' }}` in the copy | RED — A4c names the two accepted spellings |
| 6d | replace a row's tabs with spaces | RED — A-parse names the line |
| 7 | blank the consequence on `cla.yml`'s row | RED — A5 |
| 8 | point `PR_FANOUT_WORKFLOWS_DIR` at an empty dir (own dispatch) | RED — A0 exits 1 with `0 < 15` |
| 9 | must PASS: add `zz-closed.yml` with `types: [closed]` and no row (a landed diff, mirroring `cleanup-unmerged-bot-branches.yml`) | PASS — `PASS: A1 … firing / … ledgered` unchanged |
| 10 | must PASS: `ci.yml` row set to 25 while the file declares 22 | PASS — the row is an upper bound |
| 11 | harness row: in the test, make A1 compare against the ledger's own set instead of the enumerator | RED — row 1 goes green, proving the enumerator is load-bearing |

Rows 1–10 (with 6b–6d) ship as Part B of the suite; row 11 is a one-time verification during
the work phase, recorded in the PR body.

### Guard 3 — workflow CI-budget partition

**Property.** `CI_BUDGET_MIN` in `web-platform-release.yml` is `DRIFT_SUSTAINED_THRESHOLD_MIN`
minus the ceilings of every job that follows CI on the deploy arm (`resolve-target`, `migrate`,
`verify-migrations`, `deploy`), and CI's declared path is asserted `<=` it.

**Assembly.** The single `run:` block of the step named `Derive the CI budget and check for creep`
in the `resolve-target` job; `read_threshold` (grep over the `.sh`), `job_ceiling` (awk over the
workflow's own job blocks), `run_declared_path` (awk longest path over `ci.yml`). Asserted by GUARD
5 of `plugins/soleur/test/workflow-run-deploy-invariants.test.sh`, which extracts exactly that step
into `$W/budget.blk` and greps the call forms.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | drop `- RT` from the `CI_BUDGET_MIN` arithmetic | RED — the partition-shape row |
| 2 | delete the `job_ceiling "$REL" resolve-target` call (second member after the three compliant reads) | RED — G5-21 names `resolve-target` |
| 3 | delete the whole budget step (own dispatch) | RED — G5 "derivation step was not found" |
| 4 | replace `THRESHOLD=$(read_threshold)` with `THRESHOLD=225` | RED — G5-18 |

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Item 1 (d): keep 207, date the exclusion, name a compensating control | Leaves a guard green on a quantity it knows is short; the only compensating control would be the workflow's own headroom assertion, which has the same omission. Rejected on the 2026-09-10 learning |
| Item 1: raise to 270 and leave `resolve-target` at 60 | Pays 45 m of alert latency for the ceiling of a 13-second job whose poll ADR-217 declares dead by construction; the 60 was sized to equal `release` only because it sat inside a `max()` |
| Item 1: derive the threshold from the ceilings instead of pinning it | Rejected by ADR-212 D3 / ADR-217 D4 already ("an unowned number"); the pinned constant + B9 is the owned form |
| Item 1: keep the brief's `ci + max(release, rt)` form | Under-counts when both release and resolve-target exceed CI; the physical form is tighter and valid everywhere, and equals the same number today |
| Item 2 (a) queue with CodeQL made advisory | Reverses a blocking SAST gate; ADR-032 records the trade as bad; not this chore's mandate |
| Item 2 (a) queue with advanced-setup `merge_group` no-op | Tried (#5811), removed (#5812); ADR-032: "Do NOT restore it as a fix"; upstream calls it half a fix; also disables default setup as a side effect |
| Item 2 (c) accept | A bet on load (3/2 today, 186/6 three days ago), and it does nothing about the generator |
| Path-filter `constraint-gates.yml` | Parity-locked to the constraint-scaffold template; the always-run shape is the template's promotable-to-required design |
| Delete `claude-code-review.yml` | Stales PA-33's dated member snapshot in the Article 30 register with no parity test; a legal-document correction for a zero-slot saving |
| Cancel-in-progress on `tenant-integration`, `infra-validation`, `apply-sentry-infra` | Mutex / backend state-lock holders; a mid-run cancel can leave residue or a stale lock. Ledgered as `cancel=no` with the reason |
| Fold the remaining advisory `ci.yml` jobs too (incl. `encryption-posture`) | `lint-webplat` needs Node + install; `shard-totality-mutations`, the two `Detect ...`-gated jobs and `critical-css-gate` are `if:`/`needs:`-shaped; `encryption-posture` is on a #6907 soak toward required; measure first — recorded in the ledger header as the next candidate |
| A `PreToolUse` hook at the workflow-file write (ADR-216's literal mechanism) | The filing site for a workflow is the file itself and it is always reviewed by the `test` check on the PR; a CI test at that boundary is the same lever without a hook |

## Risks

| Risk | Mitigation |
|---|---|
| The Item 1 sites land in separate commits and one side reds | Phase 1 step 3 is one commit; the `.sh` header records why |
| `resolve-target` at 15 m trips on a real run | Measured 12–14 s on nine runs; the job does one jobs-API read, one artifact download and the budget step. If it trips, the deploy fails closed and `release-outcome` emails — the same loud shape as any other ceiling; re-derive at ≥ 3x the observed max |
| `job_ceiling` awk mis-reads `resolve-target` (block anchoring) | Verified at plan time: `  resolve-target:` at 2-space indent with `    timeout-minutes:` at 4-space; G5-21 asserts the call form; the next `main` merge's `workflow_run` arm logs `CI_BUDGET_MIN=75` |
| Folding steps into `lint-bot-statuses` changes which step name a failure surfaces under | Each folded step keeps the old job name as the leading token of its step name; `scripts/lint-diagnosis-claims.sh` and `cla-evidence-timestamp.yml` reference the job only in comments |
| A PR-only cancel on `secret-scan.yml` cancels a `synchronize` run when a `labeled` event fires | Intended: the label run re-runs every job on the same head; the override-label path (#3160/#3323) is exactly the case that wants the re-run to win |
| The ledger's `jobs` column drifts as `ci.yml` grows legitimately | That is the ratchet working: the edit that adds a job also edits the row and its consequence |
| `codeql-action#1537` closes mid-pipeline | Phase 0 step 2 re-checks; the monthly watcher pings the `merge-queue-revisit`-labelled issue (#5840 today) |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `grep -c '^DRIFT_SUSTAINED_THRESHOLD_MIN=225$' scripts/prod-version-drift-check.sh` → `1`.
- [ ] AC2 `DRIFT_TEST_PARTS=AB bash scripts/prod-version-drift-check.test.sh 2>&1 | grep -E '^  PASS: B9 threshold'` → `  PASS: B9 threshold (225m) >= declared merge-to-deploy critical path (220m)`.
- [ ] AC3 `DRIFT_TEST_PARTS=ABC bash scripts/prod-version-drift-check.test.sh > /tmp/drift.out 2>&1; echo rc=$?; grep -cE '^  PASS: C-axis1[345].* caught by B9 threshold' /tmp/drift.out; grep -cE '^  PASS: C-green[12]' /tmp/drift.out` → `rc=0`, `3`, `2`.
- [ ] AC4 `grep -c 'ci_declared_path is NOT in this sum' scripts/prod-version-drift-check.test.sh` → `0`, and `grep -cE 'crit = max\(ci_declared_path, release_ceiling\) \+ job_timeout\("resolve-target"\)' scripts/prod-version-drift-check.test.sh` → `1`.
- [ ] AC5 `awk '/^  resolve-target:/{f=1} f&&/^    timeout-minutes:/{print $2; exit}' .github/workflows/web-platform-release.yml` → `15`.
- [ ] AC6 `awk '/- name: Derive the CI budget/{f=1} f&&/^      - name: /&&!/Derive the CI budget/{exit} f&&/^  [a-zA-Z0-9_-]+:$/{exit} f' .github/workflows/web-platform-release.yml | grep -cE 'CI_BUDGET_MIN=\$\(\(\s*THRESHOLD - RT - M - V - D'` → `1` (the job-boundary exit mirrors G5's own extractor).
- [ ] AC7 `bash plugins/soleur/test/workflow-run-deploy-invariants.test.sh 2>&1 | tail -3` → `0 failed`; `grep -c 'for jobname in migrate verify-migrations deploy resolve-target' plugins/soleur/test/workflow-run-deploy-invariants.test.sh` → `1`; `grep -c 'THRESHOLD - RT - M - V - D' plugins/soleur/test/workflow-run-deploy-invariants.test.sh` → `1`.
- [ ] AC8 `python3 -c "import yaml;d=yaml.safe_load(open('.github/workflows/ci.yml'));j=d['jobs'];print(len(j), 'encryption-posture' in j, all(k not in j for k in ['readme-counts','lint-conversations-update-callsites','rule-metrics-shape']))"` → `22 True True`; `awk '/^  lint-bot-statuses:/{f=1} f&&/^  [a-z]/&&!/lint-bot-statuses/{exit} f' .github/workflows/ci.yml | grep -cE '^      - name: (readme-counts|lint-conversations-update-callsites|rule-metrics-shape)'` → `3`; the same awk piped to `grep -c 'METRICS_FILE: knowledge-base/project/rule-metrics.json'` → `1`; piped to `grep -c 'if: \${{ !cancelled() }}'` → `3`.
- [ ] AC9 for each of `pr-quality-guards secret-scan dependency-review legal-doc-cross-document-gate skill-security-scan-pr-trailer`: `python3 -c "import yaml,sys;d=yaml.safe_load(open('.github/workflows/'+sys.argv[1]+'.yml'));c=yaml.safe_load(open('.github/workflows/ci.yml'))['concurrency'];print(d['concurrency']==c)" <name>` → `True` (group AND cancel byte-equal to ci.yml's — a `github.ref`-only group on `secret-scan.yml`'s `push: main` arm would re-serialise `main`, the #7931 class).
- [ ] AC10 `test -e .github/workflows/claude-code-review.yml && grep -c $'^claude-code-review.yml\t' scripts/pr-fanout-ledger.txt` → `1` (kept and ledgered).
- [ ] AC11 `bash plugins/soleur/test/pr-fanout-ledger.test.sh 2>&1 | tail -3` → `Failed: 0`, ≥ 15 Part A rows and ≥ 13 Part B mutants reported caught; `bash scripts/guard-vacuity-floor.test.sh 2>&1 | tail -2` → green with the new suite in its population (`MIN_FIRING_SUITES=39`).
- [ ] AC12 the enumerator's firing-workflow count equals the ledger's row count: `bash plugins/soleur/test/pr-fanout-ledger.test.sh 2>&1 | grep -E '^  PASS: A1 '` reports `21 firing / 21 ledgered` on the 2026-09-14 tree (the row prints both numbers).
- [ ] AC13 `bash plugins/soleur/test/ci-concurrency-key.test.sh`, `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash plugins/soleur/test/resolve-target-decision.test.sh` each exit 0.
- [ ] AC14 `grep -c '^## Amendment — 2026-09-14' knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` → `1`; `grep -c '^### Addendum 2026-09-14' knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md` → `1`; `grep -c '^> \*\*Addendum (2026-09-14)' knowledge-base/engineering/architecture/decisions/ADR-217-*.md` → `1` (the struck `= 72` bullet says "see the addendum below", never the heading literal); `grep -c '2026-09-14' knowledge-base/engineering/architecture/decisions/ADR-212-deploy-gate-measures-its-own-gated-quantity.md` → `1`; `ls knowledge-base/engineering/architecture/decisions/ | grep -c 'ADR-219'` → `0`.
- [ ] AC15 `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-14-chore-drift-threshold-ci-term-and-pr-fanout-ledger-plan.md` → 0 failures.
- [ ] AC16 `bash scripts/test-all.sh` exits 0 (full scripts group, including `scripts/guard-vacuity-floor.test.sh` classifying the new suite's floor).
- [ ] AC17 the PR body contains the RED-first evidence: the `axis13`/`axis14` `SURVIVED` lines from before the formula change, G5-18 red before the workflow edit, the ledger A4b flip from Phase 2 step 3, the one-time rows (Guard 1 rows 4/5/8, Guard 2 row 11), and the nine-run `resolve-target` measurement.
- [ ] AC18 no `gh api` mutation, no ruleset change, no issue filed, nothing deleted, no new ADR: `git diff --name-only --diff-filter=D origin/main...HEAD | wc -l` → `0`; `git diff --name-only origin/main...HEAD | grep -c '^infra/'` → `0`; `git diff --name-only --diff-filter=A origin/main...HEAD | grep -c 'decisions/ADR-'` → `0`.

No post-merge operator steps. The next scheduled drift run evaluates 225 automatically; the next
`main` merge's `workflow_run` arm reports `CI_BUDGET_MIN=75` in the `resolve-target` log
(`/soleur:postmerge` reads it: `gh run view <id> --log | grep -m1 'CI_BUDGET_MIN='`).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agreed with the Item 1 model (`max(ci, release) + resolve-target + ...` is a
correction, not a re-sizing; confirmed the arm `if:` guards) and with not adopting the queue
("the binary constraint is CodeQL-required; the load argument is correct but secondary"). Four
findings, all adopted: (1) the 5 m slack must be described as rounding only — queue wait is
unmodeled; (2) lowering `resolve-target` is not measure-first once the term is additive — measured
here (12–14 s) and folded in, moving the constant to 225 instead of 270; (3) stale formula sites
this PR must touch: the `resolve-target` and `deploy` job comments, the budget step's `::error::`
text and header, ADR-212's `72` citation — all in Files to Edit; (4) path-filtering
`constraint-gates.yml` is a wrong-shape change (parity test check 4; promotable-to-required
design) — dropped; deleting `claude-code-review.yml` has three touch points including a legal
register enumeration — dropped and ledgered instead. CTO also named the lever the first draft
missed: PR-only `cancel-in-progress` on the stateless per-PR workflows (~33 orphaned jobs per
superseded push on the CTO's count of five; 19 after excluding the three state-holding ones) —
adopted with the exclusions recorded. CTO's enumeration found 21 `pull_request` files vs the
brief's 23: the difference is the two `pull_request_target` CLA workflows; the ledger test handles
both keys. Complexity: small for both items.

### Plan review panel (2026-09-14) — applied

Five reviewers (DHH, Kieran, code-simplicity, CTO devex lens, spec-flow) plus a scoped advisor
consult. Mechanical findings applied in this revision: `rule-metrics-shape`'s step-level `env:`
carried into the fold (Kieran, spec-flow — the check would otherwise exit 0 forever); folded
steps carry `if: ${{ !cancelled() }}` and sit before the actionlint network fetch (CTO,
spec-flow); `cancel` column redefined by cancel form AND group shape, with `rls-authz-fuzz.yml`
→ `yes` and `fix-constraints-stage-a.yml` → `no` (per-SHA group) (Kieran, spec-flow); A4c fail-
closed on any other cancel expression, A-parse row, A2/A4 messages, ci.yml row cites
`required-checks.txt` (CTO); value-agnostic Part C mutators so the RED-first run is real, the
deploy axis dropped, a release axis and two shipped must-PASS rows added, hand-run rows reduced
to three one-time verifications (DHH, code-simplicity, Kieran); G5-18 tightened instead of a new
row (code-simplicity); B9 FAIL text carries the remedy (CTO, spec-flow); numeric readings live
in the `.sh` constant/header and the ADR addenda only, every other site cites by name (DHH, CTO,
advisor); AC6 job-boundary exit, AC8/AC9/AC11/AC14/AC3 anchors (Kieran); vacuity floor in the
meta-guard's recognised shape + `MIN_FIRING_SUITES` bump (Kieran, spec-flow); `scheduled-prod-
version-drift.yml`'s stale `195m` comment added (spec-flow); ADR-219 replaced by dated addenda to
ADR-032 and ADR-216 (DHH, code-simplicity); Phase 0 re-measurement and the ruleset probes dropped
(DHH, code-simplicity); AC9 asserts the whole concurrency block equals ci.yml's (spec-flow).

Surfaced, not applied — see `knowledge-base/project/specs/<branch>/decision-challenges.md`:
DHH's P0 to delete the ledger + test outright (a cut of operator-requested scope — the brief
names "require a named consequence before adding a per-PR workflow" as the lever — so it is a
User-Challenge, not a mechanical edit).

## Test Scenarios

- Given the merged tree, when `DRIFT_TEST_PARTS=ABC bash scripts/prod-version-drift-check.test.sh` runs, then B9 passes at 225 ≥ 220 and the three new axes report caught by `B9 threshold`.
- Given `ci.yml` with `test-scripts` at 66, when Part B runs, then B9 fails (`226 > 225`); at 65 it passes (the boundary).
- Given `reusable-release.yml` `jobs.release` at 130, when Part B runs, then B9 fails (`280`), proving the `max(ci, release)` arm; at 70 it passes (absorbed by the max).
- Given the workflow budget step on a `workflow_run` event with the merged tree, when it runs, then it logs `CI_BUDGET_MIN=75 ci_jobs_without_ceiling=0 soft_ceiling_s=3150` and asserts `70 <= 75`.
- Given a new file `.github/workflows/zz-new.yml` with `on: pull_request`, when the ledger suite runs, then A1 fails naming `zz-new.yml` and listing the three exits.
- Given `ci.yml` grows to 23 jobs with the ledger row at 22, when the suite runs, then A3 fails with `23 declared, row allows 22`.
- Given `pr-quality-guards.yml` loses its `concurrency:` block with the row still `cancel=yes`, when the suite runs, then A4b fails.
- Given `cleanup-unmerged-bot-branches.yml` (`types: [closed]`), when the suite runs, then it is neither required to have a row nor flagged.
- Given an empty `PR_FANOUT_WORKFLOWS_DIR`, when the suite runs, then it exits 1 at A0 before any row.
- Given two pushes to the same PR branch 30 s apart, when `pr-quality-guards.yml` dispatches, then the first run shows `cancelled` and only the second completes (observed on this PR's own CI).
- Given `fix-constraints-stage-a.yml` (cancel `true`, per-head-SHA group), when the suite runs, then its row's `cancel=no` is accepted (group shape rule) and a mutant that keys the group on `github.ref` with the row still `no` reddens A4b.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open --json number,title,body --limit 200`
(65 issues) matched none of the planned paths (`scripts/prod-version-drift-check.sh`,
`scripts/prod-version-drift-check.test.sh`, `.github/workflows/web-platform-release.yml`,
`.github/workflows/ci.yml`, `.github/workflows/claude-code-review.yml`,
`plugins/soleur/test/workflow-run-deploy-invariants.test.sh`, `infra/github/ruleset-ci-required.tf`,
`ADR-217`, `ADR-032`).

## Research Insights

### Premise Validation (Phase 0.6)

Checked: the five numbers in the brief (files + a live Part A/B run — hold); the "merge queue not
configured" claim (holds, with the exercised-and-reverted history the brief omits: PR #5800,
kill-switch, PIR, ADR-032 amendment, #5811/#5812 prototype); `codeql-action#1537` state (open,
`gh api`, 2026-09-14); live ruleset 14145388 (23 required contexts: 22 `@15368` + `CodeQL@57789`,
`strict: true`, one rule type) and 13304872 (`cla-check`, `cla-evidence`); CodeQL default setup
(`state: configured`, extended suite, 5 languages); every `@15368` producer carries `merge_group:`
(PR-1 #5784) — CLA producers do not, by design; `infra/github/` is the Terraform owner of the
rulesets; the org plan (`free`); the 23 `pull_request`/`pull_request_target` workflows and their
`types:`/`paths:`/`concurrency:` shapes; `claude-code-review.yml` `disabled_manually`; PR #7990's
timeline (11 force-pushes, 21 `main` commits in the window); `resolve-target`'s real duration
(12–14 s, nine runs). Stale: the brief's formula is one of three inconsistent formulas in the tree
(see Reconciliation); the brief's "resolve-target does not move B9" is exactly true only under the
test's current form. No cited issue is the work target; none is created.

### Property List (Phase 0.6b)

- P1 The drift alert threshold is at or above the declared merge-to-deploy path, with CI's declared
  path as a term, and a raise of any ceiling on that path reddens CI.
- P2 The CI creep detector's soft ceiling does not loosen as a side effect of the threshold move.
- P3 The per-PR runner load is smaller than today by a measured amount.
- P4 No workflow can add a per-PR-push trigger without a recorded, named consequence, and the
  record cannot go stale silently.
- P5 The decision not to adopt a merge queue is recorded with what would reopen it.

### Cut List (Phase 0.6b)

- Merge queue on `main` → P3/P4-adjacent (the BEHIND race) → cut: blocked by CodeQL (ADR-032, PIR),
  worsens P3 on a 20-slot pool; replaced by the reopener list (P5).
- `merge_group:` trigger sweep → P4 → cut: already done by #5784 for every required producer.
- Ruleset edit (`merge_queue` rule via Terraform or `gh api`) → cut with the queue.
- Path-filter `constraint-gates.yml` → P3 → cut: parity-locked, and the always-run shape is the
  template's design.
- Delete `claude-code-review.yml` → P3 → cut: zero live slots saved; stales PA-33.
- A `PreToolUse` filing hook for workflows → P4 → cut: the `test` check on the PR is the same
  lever without a hook.

### Relevant files

- `scripts/prod-version-drift-check.sh` — `DRIFT_SUSTAINED_THRESHOLD_MIN=207` and the header
  narrative (`195 -> 207 (#7902)` paragraph; the "longest LEGITIMATE" formula paragraph; the
  `SCOPE (#7160)` paragraph on unmodeled queue wait).
- `scripts/prod-version-drift-check.test.sh` — B8/B9 extractor (`crit = max(release_ceiling,
  job_timeout("resolve-target"))`), B9/B9b/B9c rows, `mutate_and_assert_red` (mutator gets the
  sandbox file path as `sys.argv[1]`; expected label matched as `FAIL: <prefix>`), `make_sandbox`
  (copies ci.yml and the callee resolved from `jobs.release.uses`), floors
  `MIN_ASSERTIONS=151 MIN_A=57 MIN_B=81 MIN_C=13` with a sum invariant.
- `.github/workflows/web-platform-release.yml` — `resolve-target` job (`if: always() &&
  github.event_name != 'push'`, `timeout-minutes: 60` with the "60 = the release job's own
  ceiling" comment); `Derive the CI budget and check for creep` step; `job_ceiling()` awk anchors
  `^  <job>:` / `^    timeout-minutes:`; `CI_BUDGET_MIN=$(( THRESHOLD - M - V - D ))`; the
  `deploy` job's `= 205` comment.
- `.github/workflows/reusable-release.yml` — `jobs.release.timeout-minutes: 60` with the
  "COUPLED (#7160)" note.
- `.github/workflows/ci.yml` — 25 jobs, all with ceilings (#8020); `merge_group:` trigger with the
  #5780 invariant comment; the per-SHA/per-ref concurrency block (ADR-217 D1) with its
  measurement table; `lint-bot-statuses` is the 11-step advisory-lint job (`rule-metrics-shape`
  carries a step-level `env: METRICS_FILE:` its `run:` depends on).
- `.github/workflows/{pr-quality-guards,secret-scan,dependency-review,legal-doc-cross-document-gate,skill-security-scan-pr-trailer}.yml`
  — no `concurrency:` block today; `secret-scan.yml` `types:` includes `labeled`/`unlabeled`.
- `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` — GUARD 5 rows (G5-18, G5-21,
  G5-19, G5-20); `REUSABLE=` var exists for callee reads.
- `plugins/soleur/test/ci-concurrency-key.test.sh` — checks ci.yml only.
- `infra/github/ruleset-ci-required.tf`, `infra/github/README.md` — the reverted `merge_queue`
  block and the re-adoption checklist; `scripts/create-ci-required-ruleset.sh` (DR restore) is in
  lockstep with it.
- `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`.
- `knowledge-base/legal/article-30-register.md` — PA-33 dated member snapshot names
  `claude-code-review.yml` as a member and argues disabled-but-keyed workflows stay members.
- `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` — root `constraint-gates.yml`
  body must equal the substituted template body (check 4).
- `scripts/test-all.sh` — `SUITE_GLOBS` includes `plugins/soleur/test/*.test.sh` (auto-discovery);
  `scripts/lint-orphan-test-suites.sh` diffs tracked suites against the globs.
- `scripts/guard-vacuity-floor.test.sh` — the meta-guard that constructs a neutered-`fail` mutant
  for every suite whose floor it can recognise; the new suite's floor must be `[[ $n -lt N ]]`
  shaped and exit directly.
- `plugins/soleur/test/c4-count-parity.test.sh` — compact suite shape to mirror (PASS/FAIL counters,
  `print_results`).
- `scripts/required-checks.txt` + `plugins/soleur/test/required-checks-canonical-parity.test.sh` —
  the ledger precedent (comment-stripped text, real set derived independently).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-10-every-instrument-i-used-to-judge-my-own-guards-agreed-with-them.md`
  — "when a mechanism is replaced, every quantity it was measured in is suspect"; the reason (d)
  is rejected and the reason every formula site is unified.
- `knowledge-base/project/learnings/best-practices/2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md`
  — enumerate producers at the JOB level across ALL rulesets; applied as evidence, not as work.
- `knowledge-base/project/learnings/2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md`
  — never `.rules[0]`; the plan's probes use `select(.type==...)`.
- `knowledge-base/project/learnings/2026-08-14-every-defect-was-a-guard-that-could-not-fail-and-no-instrument-found-more-than-two.md`
  — each guard has an own-dispatch row and a second-member row; Guards 1 and 2 have harness rows.
- `knowledge-base/project/learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`
  — the ledger separates always-fire, `types:`-gated and path-filtered populations rather than
  one flat count; the A1 message names three honest exits.
- `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`
  — A0 vacuity floor and B9c: "clean" must be distinguishable from "never ran".
- `knowledge-base/project/learnings/2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md`
  — the A3 (`declared <= row`) and A0/A7 floors need off-diagonal fixtures: Guard 2 row 2 (over by
  one), row 10 (row over-states by four), and an A7 mutant at `CASES` = floor − 1 AND floor + 1,
  so `<` is distinguishable from `!=`.
- `knowledge-base/project/learnings/workflow-patterns/2026-08-01-alert-step-and-its-fallback-died-together-guard-fallbacks-with-not-cancelled.md`
  — the folded steps carry `!cancelled()`, never the implicit `success()`; none reads another
  step's output, so no cross-step `env:` guard is needed.
- `knowledge-base/project/learnings/2026-03-20-github-required-checks-skip-ci-synthetic-status.md`
  — no required context is added or renamed, so no synthetic-status change; the folded jobs are
  not contexts.

### Conventions (AGENTS.md)

`hr-verify-repo-capability-claim-before-assert` (the queue premise was grepped, not assumed);
`hr-ship-message-no-operator-checklist` (no operator steps); `cq-assert-anchor-not-bare-token`
(ACs anchor on call forms and clause text); `cq-cite-content-anchor-not-line-number`;
`hr-never-run-commands-with-unbounded-output`; plan Phase 2.10's architecture-decision gate
(migrated out of AGENTS.md in PR #8034 — the ADR-032, ADR-216 and ADR-217 addenda are in-scope tasks).

### Community discovery

Functional-discovery searched three registries; zero overlapping artifacts (no GitHub Actions
fan-out ledger or merge-queue tooling indexed). Nothing installed.

## References

- ADR-217 (`knowledge-base/engineering/architecture/decisions/ADR-217-...md`) Decisions 3–4
- ADR-212 Decisions 3–4 (creep detector, no unowned constants)
- ADR-032 amendment 2026-06-30 / correction 2026-07-01 (merge queue)
- ADR-216 (machinery ledger, filing-time lever)
- PR #7990 (the deploy split), PR #5800 / #5811 / #5812 (queue enable, prototype, removal), #5780 (tracking), #5840 (re-adoption ping target, found by its `merge-queue-revisit` label)
- `github/codeql-action#1537`
- #8006 (matrix-leg balance — input for the out-of-scope option 1(b)); #8007 (announcement gating — context only)
