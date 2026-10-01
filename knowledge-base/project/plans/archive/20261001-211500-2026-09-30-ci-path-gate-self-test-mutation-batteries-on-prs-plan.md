---
title: "ci: path-gate the self-test mutation batteries on PRs"
type: chore
date: 2026-09-30
slug: ci-path-gate-self-test-mutation-batteries-on-prs
branch: feat-one-shot-9323-path-gate-mutation-batteries
issue: 9323
lane: cross-domain
priority: p2
requires_cpo_signoff: false
---

<!-- Spec lacks valid lane: -- defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this branch. -->

## Enhancement Summary

**Deepened on:** 2026-09-30
**Gates run:** User-Brand Impact (4.6, threshold `none`), Observability (4.7), PAT-shape (4.8), Guard Contract (4.11, lint green); 4.4/4.55/4.9/4.10 not triggered (no scheduled job, downtime, UI, or persistent store).
**Agents:** architecture-strategist, spec-flow-analyzer, test-design-reviewer, observability-coverage-reviewer, plus a verify-the-negative sweep (all six negative/existence claims confirmed).

### Key improvements folded in

1. **Trust root named and narrowed.** On a pull_request run the PR's own runner evaluates the PR's own predicate. Added an in-runner canary (Proposed Solution 2b) for the accident class; the adversarial class is a stated residual (CODEOWNERS is not enforced: the CI Required ruleset carries no code-owner review rule, so an entry would be inert).
2. **Enumerate is never gated.** `--enumerate`/`--enumerate-commands` consumers (shard-totality, linter census, fanout-suite-scope, battery-tag-authorship stream counts) inherit `CI` and `GITHUB_EVENT_NAME` inside PR jobs; the PR arm is inert under `_ENUMERATE==1` (ADR-242 decision 5 precedent) so the enumerate stream stays byte-identical.
3. **Guard 2 scoped honestly.** cf-tunnel copies `scripts/` and `.github/` wholesale and test-all-affected hardlinks all of `scripts/`: a literal-operand closure would red or force directory prefixes that defeat the gate. Guard 2 checks explicit file operands only and exempts whole-directory/corpus operands through a declared allowlist with reasons (ADR-181's "copy set vs dependencies" precedent).
4. **test-all-affected is honestly broad.** Its census sandbox hardlinks all of `scripts/`; the measured arm-rate of a `scripts/` prefix is 54% of the last 300 commits, so its saving is the smaller (~46%). Declared by dependency (runner, three libs, the linter, itself), with the copy-set blind spot named in the ADR.
5. **Escape path and recovery specified.** A break that escapes is caught by the per-SHA push run (which also blocks that SHA's deploy, ADR-217) and the 6-h monitor; the fix PR must widen the declaring array, and that edit is itself a machinery path that arms every battery. `workflow_dispatch` of ci.yml is the documented force-full lever. Bot PRs never run the real legs (synthetic checks), before or after this change.
6. **Guard suite mechanics specified** (mutate copies in `$TMP` with count==1 scoped substitutions, env isolation, positive `RECORDED_SUITE` assertions, per-battery table, runtime budget) and the matrix rebalanced.
7. **Follow-through hardened** (escape-rate check, exit-2 on too few runs, merge-SHA-pinned window, gate-touching and bot PRs excluded, directive shape) and the discoverability script made sandbox-safe (falls back to `HEAD` when `origin/main` is absent).

### New considerations discovered

- The ADR-181/ADR-242/ADR-183 statements that become false are more numerous than first listed (see Files to Edit); the `_diff_touches` header and `_suite_affected` FAIL-SAFE comments also assert "CI runs everything".
- Each new else-arm must also increment `_relevance_declined` (it drives the epilogue's force-all hint).

## Overview

Pull-request CI runs every registered script suite on every PR, because `_diff_touches` in
`scripts/test-all.sh` returns true unconditionally when `CI` is set (ADR-181 property 4). A handful of
slow self-test mutation batteries therefore dominate runner time on PRs that never touch what those
batteries mutate. With the runner-concurrency cap as the binding constraint, runner-minutes become queue
wait for every open PR, and strict up-to-date branch protection turns each queued PR into a restart.

This plan makes the batteries run on a **pull_request** CI run only when the PR diff touches their
subject paths (or the gate machinery itself), keeps the full battery on every other CI event and on the
6-hourly `main-health-monitor`, and records the coverage split and its residual in a new ADR that amends
ADR-181 property 4 and ADR-242 decision 1.

Scope of the gated set in this PR (five genuine mutation batteries named in the issue's top tier or already
carrying a relevance predicate; six registrations because `-a`/`-b` are two halves of one battery):

| Battery (registration label) | Group / leg | Measured (issue) | Has relevance array today |
|---|---|---|---|
| `tests/scripts/registry-gate-mutation-battery` | heavy | 494 s | yes (`REGISTRY_BATTERY_PATHS`) |
| `scripts/lint-orphan-test-suites-mutations-a` / `-b` | light | 439 / 443 s | no |
| `scripts/battery-tag-authorship-mutations` | heavy | 401 s | no |
| `scripts/test-all-affected` | light | 349 s | no |
| `scripts/cf-tunnel-liveness-gate-mutations` | light | ~189 s | yes (`CF_TUNNEL_BATTERY_PATHS`) |

Not in this PR (tracked as a deferral, see Non-Goals): `orphan-process-reaper-mutations` (it already has a
declared affected edge set; a second array would shadow it), the remaining next-tier suites that are not mutation
batteries (`betterstack-roundtrip-latency`, `playwright-mcp-redact-proxy`, `test-contention`,
`git-data-birth-readiness-gate`, `sentry-alert-live-fidelity`, `monitor-pr-checks`), and the other
already-relevance-gated suites (`c4-from-components`, `.github/scripts/test/run-all.sh`, webplat app arm).

## Research Insights

**Premise Validation (Phase 0.6).** Checked: issue #9323 is OPEN, no closing PR. `_diff_touches` exists on
`origin/main` at `scripts/test-all.sh` (CI bypass is the unconditional `if [[ -n "${CI:-}" ]]; then return 0; fi`).
The issue says "the affected-declarations index already models consumed edges": true
(`scripts/lib/test-affected-paths.sh` `AFFECTED_CONSUMED_EDGES`, ADR-242), but four of the batteries in the
issue's top tier (`-a`, `-b`, tag-authorship-mutations, test-all-affected) are currently classified `ALWAYS_ON` there,
not `edge:*` (registry and cf-tunnel already are consumed edges), so "derive subject paths from the
index" is not free -- see Research Reconciliation. ADR corpus check: ADR-181 property 4 ("a decline is
UNREACHABLE under CI") and its Alternatives row "A CI assertion that no skip occurred -- REJECTED" are the
mechanism this plan reverses **for pull_request events only**; ADR-181 also already REJECTED "a new nightly
workflow for the gated set -- it already exists" (`main-health-monitor.yml`, 6-hourly, full un-gated). ADR-242
decision 1 says "CI keeps the full battery" -- amended here. ADR-176-style mechanism minimality applied below.

**Property List (Phase 0.6b).**
P1. A PR whose diff touches none of a battery's subject paths does not pay that battery's runner time.
P2. A PR that touches a subject path (or renames/deletes one, or edits the battery, or edits the gate
    machinery) still runs the battery on the PR.
P3. Every skip is a counted, printed verdict -- never an absence (ADR-181 properties 1-2).
P4. `push` to main, `merge_group`, `workflow_dispatch`, and `main-health-monitor` run every battery; a red
    battery on main pages through the same channel a red test uses today.
P5. The subject sets cannot silently rot: a dependency a battery gains later widens what arms it.
P6. Undeterminable diff, a non-PR or unset event name, or a missing declaration fails closed to RUN.
P7. The saving is measured, not asserted (issue AC4).

**Cut List (Phase 0.6b).**

- New nightly / push-to-main "run all batteries" workflow -> P4 -> already covered: `ci.yml` `push: [main]`
  runs with `GITHUB_EVENT_NAME=push` (full), and `main-health-monitor.yml` runs `bash scripts/test-all.sh` (full,
  `TEST_GROUP=all`, every 6 h via Inngest `cron-main-health-monitor`, files a `ci/main-broken` P1 on red).
  ADR-181 already rejected the same workflow. No `.github/workflows/*.yml` is added, so no C4 cardinality moves.
- An explicit `SOLEUR_PR_BATTERY_GATE` env flag bound in `ci.yml` -> P4/P6 -> CUT in plan review:
  `GITHUB_EVENT_NAME` is already authoritative and equally fail-closed; the binding would need its own YAML wire guard.
- A new banner / `GITHUB_STEP_SUMMARY` writer, a linter call-site census for the flag, a runbook section ->
  P3 -> CUT: `skip_suite` + the BREAKDOWN line already give a counted, printed verdict (ADR-181); a lost flag is
  caught behaviourally.
- Gating the reaper battery now -> CUT: its affected edge array already exists; deferred.
- A second predicate function (`_pr_gate_touches`) -> P1/P2 -> CUT. `_diff_touches` already owns the
  substring-match, fail-safe, rename-source and untracked arms; a second function would drift from it (CTO
  assessment concurred). Parameterise the existing one with a call-site flag instead.
- A separate relevance manifest / `--explain` mode -> already REJECTED in ADR-181.
- A CI assertion "no battery was skipped on main" -> already REJECTED in ADR-181 (would red the monitor).
- Re-sharding -> issue states shards are balanced; resharding alone buys nothing.
- Job-level skip (`if:` on the heavy legs) -> CUT: the heavy legs are a required chain (`test` needs
  `test-scripts-heavy`), a job-level skip would make the required context unreported-vs-skipped semantics part
  of the design; the legs still cost setup but the battery minutes (the ~15 of ~20 saved) are recovered.

**Value-Proposition Measurement (Phase 0.6c).** Replay of the candidate subject sets against the last 300
first-parent commits of `origin/main` (one `git log --name-only` call, matched with the same substring
semantics as `_diff_touches`): runner-core set (`test-all.sh`, `test-relevance-paths.sh`,
`test-affected-paths.sh`, `ci.yml`, `suite-shard-legs*`) arms on **21%** of commits; registry battery set on
**4%**; tag-authorship set on **18%**; lint-orphan set including the whole `.github/workflows/` prefix on
**38%** (the linter greps every workflow for `bash <suite>` registrations, so the prefix is honest; narrowing
is a follow-up). Reproduction command: `bash scripts/ci-battery-gate-replay.sh --commits 300` (created by this
plan, Phase 3). Expected saving: roughly 25-30 suite-minutes per PR run before the ~20 runner-minute target is
re-measured on real runners post-merge (AC below). The issue's own figures (~35 of 89 suite-minutes) are the
ceiling, not the forecast -- the core-set 21% arm-rate means the machinery-touching PRs still pay.

**Institutional learnings applied.** ADR-181 (declines are counted verdicts; predicates as data; fail-CLOSED
source), ADR-242 (selection uncertainty fails toward coverage; `runner-changed` degrades to full), ADR-188
(a decline reachable under CI must not infer), ADR-196, ADR-217 (per-SHA concurrency on main: every main push
gets its own full verdict), learning `2026-04-01-ci-quality-gates-and-test-failure-visibility.md` (main-health
monitor is the backstop), learning `2026-09-21-a-conflict-starved-merge-ref-reads-as-ci-never-ran.md`
(a PR with a conflicting merge ref runs no CI at all, so the diff base is always a clean merge ref),
#9173/#9197 (an end-of-block registration is the only insertion that shifts no existing suite's positional
shard parity; `test-all-affected` s1/s2 measured `ran=0` when a mid-block insert flipped leg assignment).

**Related issues / PRs.** #7942 (two `*.mutation.sh` batteries in plugins/soleur/test run in no gate -- adjacent,
not this); #7454 (test-pipeline efficiency follow-ups); #9173/#9197 (shard-parity regression).

## Research Reconciliation -- Spec vs. Codebase

| Issue / brief claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "CI runs every registered suite on every PR, because `_diff_touches` short-circuits under `CI`" | True: `scripts/test-all.sh` `_diff_touches` returns 0 on `CI`, `SOLEUR_TEST_FORCE_ALL=1`, `_FULL_GATE==1` | Keep the two force arms first; carve the `CI` arm out only when `GITHUB_EVENT_NAME == pull_request` and the call site opted in (`--pr-gated`) |
| "the affected-declarations index already models consumed edges" | Only five relevance arrays are `AFFECTED_CONSUMED_EDGES`; `lint-orphan-test-suites-mutations-a/-b`, `battery-tag-authorship-mutations`, `test-all-affected` are `ALWAYS_ON_SUITES` ("runner-SUT property suites") | Move these four labels from `ALWAYS_ON` to consumed edges once they own a `*_PATHS` array (lint `-a`/`-b` share one); record the ADR-242 amendment (their verdict is computed on sandbox copies of named files, not the live tree) |
| "Each battery declares its subject paths; derive from what it sources, not a hand list" | The batteries source/copy via `cp "$REPO_ROOT/..."` and globs (`.github/workflows/*.yml`) that the affected classifier's derive rungs do not fully reach; ADR-181 rejected set-equality because declarations come in four shapes | Declared `*_PATHS` arrays (existing pattern, six-site recipe) **plus a lint that asserts derived-closure subset-of declared** (Guard 2), so the declared list cannot fall behind what the battery sources |
| "Run all batteries on push to main and nightly" | `ci.yml` already runs on `push: [main]` and `main-health-monitor` runs 6-hourly, both CI=true with no diff gate | No new workflow (Cut List); ADR states the existing pair IS the backstop (`push` and `workflow_dispatch` event names are not `pull_request`); AC verifies neither workflow file changes |
| "a red battery on main pages the same way a red test does today" | `main-health-monitor.yml` files `ci/main-broken` P1 on any failure/cancelled/skipped outcome | Verified by reading the workflow; no change |
| Shard balance (agent research claimed skipping "breaks shard parity") | `skip_suite` applies the identical `_shard_selects` filter as `run_suite` and counts in `suites`; registrations and positions are unchanged, only execution is skipped. The real parity hazard is *adding a registration mid-block* (#9173) | The only new registration (the guard suite) goes LAST in its block and a matrix row pins s1/s2 `ran>0` |

## Problem Statement / Motivation

See issue #9323: ~58% of CI runner time is `test-scripts`; five self-tests of the gate machinery hold ~40% of
script suite time; queue wait averages 18 min (31 max); CI wall clock 41-64 min against ~10 min of shard
execution; PR #9286 took three full restarts. The binding constraint is runner concurrency.

## Proposed Solution

1. **Event discriminator, fail-closed, no new flag.** `_diff_touches` already runs only under `CI`; the new
   arm additionally requires `GITHUB_EVENT_NAME == pull_request`, which Actions sets on every job. Any other
   value (`push`, `merge_group`, `workflow_dispatch`, `schedule`, unset) means today's behaviour (run). No
   `ci.yml` binding is added (plan review cut the explicit env flag: the event name is already authoritative
   and equally fail-closed, and a binding would need its own YAML-lexing wire guard). Verified at plan time:
   the only workflows that execute `test-all.sh` are `ci.yml` and `main-health-monitor.yml`; the five others
   that mention it do so in comments only. `main-health-monitor` is dispatched (`workflow_dispatch`), so it
   stays full by construction.
2. **One predicate, one call-site opt-in.** `_diff_touches --pr-gated "${X_PATHS[@]}"`: when the first
   argument is `--pr-gated` it is consumed, and the `CI` short-circuit is skipped iff `CI` is set AND
   `GITHUB_EVENT_NAME == pull_request`. `SOLEUR_TEST_FORCE_ALL=1` and `--full` still win first. Everything after
   falls through the existing fail-safe (`_diff_detect_ok`, `_diff_head_ok`) and substring-match arms. The
   opt-in keeps c4-from-components, `.github/scripts/test/run-all.sh` and the webplat app arm un-gated on PRs
   (out of scope). **Two linter consumers pin the old call shape and must be widened in the same change**
   (plan review, verified against the files): `scripts/lint-orphan-test-suites.sh` DE-REFERENCE ANCHOR
   (`ref_re='_diff_touches "\$\{'"$arr_name"'\[@\]\}"'`) and the `RUNNER_ARRAYS` derivation in
   `scripts/test-all-infra-coverage-notice.test.sh` (`grep -oE '_diff_touches +"?\$\{[A-Z0-9_]+\[@\]'`); each
   gains an optional `( +--pr-gated)?`. The `want` dispatch-floor regex (`_diff_touches +[^#]*\$\{...`) already
   tolerates the flag and counts call sites, not registrations.
   **2b. Enumerate is never gated; in-runner canary (deepen-plan).** The PR arm is inert when `_ENUMERATE == 1`
   (`--enumerate` / `--enumerate-commands` answer "what is registered", ADR-242 decision 5), so the enumerate
   stream that shard-totality, the linter census, fanout-suite-scope and battery-tag-authorship consume stays
   byte-identical under `CI=1 GITHUB_EVENT_NAME=pull_request`. Before the first gated call on a PR run, a ~8-line
   canary evaluates the predicate against a fabricated `_diff_names` (one containing `scripts/test-all.sh`, one
   unrelated); if the machinery name does not return run or the unrelated name does not decline, the runner
   prints `PR_GATE_CANARY_FAILED` and forces run-all for the rest of the run. This defeats an accidental
   predicate regression at runtime, not an adversarial coordinated edit (see the trust-root residual in the ADR).
   Every new else-arm also increments `_relevance_declined` (it drives the epilogue's force-all hint).
3. **Gate-machinery degrade.** A diff touching `scripts/test-all.sh`, `scripts/lib/test-relevance-paths.sh`,
   `scripts/lib/test-affected-paths.sh`, `.github/workflows/ci.yml` or `scripts/suite-shard-legs*.tsv` arms
   every battery (each array lists them, exactly as the arrays already self-include the predicate file).
4. **Subject sets**: three new arrays in `scripts/lib/test-relevance-paths.sh` (`LINT_ORPHAN_BATTERY_PATHS`
   shared by `-a`/`-b`, `TAG_AUTHORSHIP_BATTERY_PATHS`, `TEST_ALL_AFFECTED_BATTERY_PATHS`), each self-including
   its battery file and the predicate file; existing `REGISTRY_BATTERY_PATHS` / `CF_TUNNEL_BATTERY_PATHS` call
   sites gain `--pr-gated`. **Call-site shape (plan review P0):** the `-a` and `-b` registrations
   (adjacent at `scripts/test-all.sh` ~3932-3933) share ONE `if _diff_touches --pr-gated "${LINT_ORPHAN_BATTERY_PATHS[@]}"`
   wrapping both `run_suite` lines, with two `skip_suite` calls in the else arm -- two separate `if` sites over
   one array would make the linter's derived `want` (10) exceed `RELEVANCE_ARRAYS` (9) and red. Result: five
   call sites over five arrays.
5. **Counted, printed skip (no new surface).** Declines reuse `skip_suite` (label, reason `relevance`, exact
   rerun command) and the existing BREAKDOWN line (`... N skipped (declined -- not relevant to this diff)`).
   No new banner and no `GITHUB_STEP_SUMMARY` writer (plan review cut both as duplicating ADR-181's verdict).
6. **Full coverage on main**: nothing to build; ADR-262 records that `push`/`merge_group`/dispatch/monitor run
   everything, the detection latency of a PR-escaping break (push CI run on the merge SHA -- minutes; monitor --
   up to 6 h), and that no merge queue is enforced (verified 2026-09-30: `gh api repos/jikig-ai/soleur/rulesets/14145388`
   lists only a `required_status_checks` rule), so a semantic interaction between two concurrently-open PRs
   surfaces on the main push run, attributed to a commit. The 6-hourly monitor is the issue's "nightly".
7. **Measured follow-through.** A soak-gated follow-through script enrolls the post-merge re-measure.

## Technical Considerations

- **Diff base on PRs.** Both jobs check out `refs/pull/N/merge` with `fetch-depth: 0`, so
  `origin/main...HEAD` is merge-base(`origin/main`, merge commit)..merge commit = exactly the PR's changes even
  if `main` advanced after the ref was built (merge-base is an ancestor of the new tip). A stacked PR with a
  non-main base over-includes the base branch's changes -- the safe (run) direction. `ci.yml`'s header forbids an
  `event_name == 'pull_request'` gate on required-context JOBS; this plan adds none (the discriminator lives in
  the runner script, every job still reports).
- **Rename/delete.** `_diff_names` already appends `--name-status -M` rename sources; a rename below the
  similarity threshold is delete+add and both paths land in the blob. A delete-only diff on a declared path
  matches by substring, which is correct because the predicate consumes the diff, not the tree.
- **`test` aggregator / required checks.** A relevance decline exits 0; `test-scripts*` results are
  `success`; the marker reads `N-k/N suites passed` with the BREAKDOWN line, byte-compatible with ADR-181.
  No required-context semantics change (no `if:` on any job). Nothing in `.github/workflows/` greps the marker.
- **Local behaviour change (deliberate, uniform).** The three new arrays are ordinary relevance predicates, so a
  local non-CI run also declines those batteries on an irrelevant diff (like the registry battery since ADR-181).
  Their `ALWAYS_ON` classification is withdrawn (four labels: `-a`, `-b`, tag-authorship-mutations,
  test-all-affected); `_suite_affected`'s EXEMPT LABELS list gains them (their own gate runs first; the list's
  "Six registrations" comment is already stale at seven entries -- update the count). `_affected_classify` reads
  `AFFECTED_CONSUMED_EDGES` rows on the `--affected` pre-pass regardless of EXEMPT (plan review verified at
  `scripts/test-all.sh` ~2421), so the four consumed-edge rows ARE read. `--full` and
  `SOLEUR_TEST_FORCE_ALL=1` keep the legacy force-all semantics. The ADR-242 amendment must answer why these were
  ALWAYS_ON ("a property of the runner / the whole registration set"): their verdict is computed on a sandbox copy
  of named files, not on the live tree.
- **ALWAYS_ON floor.** `_MIN_ALWAYS_ON_DECLARED=100` is a hand-typed literal (~145 entries today); removing four
  leaves ~141, so no floor moves and nothing is re-derived. Confirm by running the orphan linter.
- **Shard manifest.** No label is added or renamed except the new guard suite; add it to
  `scripts/suite-shard-legs.tsv` via `python3 scripts/regenerate-shard-manifest.py` dry-run first
  (per the ci.yml header), register it **last in its block**, and confirm `test-all-affected` s1/s2 still report
  `ran>0`.
- **Toolchain parity.** No new runtime in either job; `scripts-shard-runtime-coverage` needs no change.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-262** (provisional ordinal -- free on every `origin/*` ref at plan time; re-verify across all remote
refs immediately before merge): *"PR CI path-gates the self-test mutation batteries; push, merge_group,
dispatch and the main-health monitor run everything."* Status `active`, `amends: ADR-181 (property 4, Scope),
ADR-242 (decision 1)`. About one page: the event-discriminator contract and its fail-closed semantics; the
call-site opt-in (`--pr-gated`); the gated set and the admission rule (a self-test of gate/test machinery whose
verdict is a property of named files); the coverage split table (event -> runs all / gated); the **named
residuals** -- (R1) a break in a battery outside its declared subject set surfaces on the merge-SHA push run (which
also blocks that SHA's deploy, ADR-217) or the 6-h monitor, not on the PR; the remediation PR must widen the
declaring array, which is itself a machinery path and arms every battery on that PR; no merge queue is enforced;
`workflow_dispatch` of ci.yml is the force-full lever; (R2) trust root -- a pull_request run executes the PR's own
runner and predicate, so a coordinated edit of the predicate, the canary and the guard suite is undetectable
in-repo (the canary covers accidents; CODEOWNERS is inert because the ruleset has no code-owner review rule); (R3)
blind spots by construction -- a battery whose subject is a whole directory or corpus (cf-tunnel copies `scripts/` and
`.github/`; test-all-affected hardlinks `scripts/`; the lint battery reads `git ls-files '*.test.sh'`) is declared by
dependency, not copy set (ADR-181 precedent), so an edit to an undeclared member of such a corpus is an R1 escape;
(R4) bot PRs carry synthetic checks and never run the real legs, before or after this change; Alternatives Considered, only those not already rejected in
ADR-181: job-level path filters (required contexts would be unreported), an explicit env flag (the event name is
already authoritative), adopting the affected classifier wholesale on CI (changes selection of ~500 suites, a
blast radius the issue does not ask for); the rest cite ADR-181. Create via `soleur:architecture create`.

### C4 views

**No C4 impact, with the completeness check performed.** Read `model.c4`, `views.c4`, `spec.c4` under
`knowledge-base/engineering/architecture/diagrams/`. Checked: (a) external human actors -- none added
(operators/reviewers already modeled); (b) external systems/vendors -- none added or removed (GitHub Actions
and Sentry edges exist; no new workflow is introduced, so the `github -> sentry` cron/workflow cardinalities
do not move); (c) containers/data stores -- none touched; (d) actor-surface access relationships -- none
change. The plan MUST run `bash plugins/soleur/test/c4-count-parity.test.sh` green before ship (no workflow or
monitor is added, so the expectation is unchanged), and cite the result in the PR.

### Sequencing

The ADR describes the target state and ships in this PR; there is no soak-gated slice that postpones it. The
measured saving is a follow-through, not an ADR precondition.

## Files to Edit

- `scripts/test-all.sh` -- `_diff_touches` gains the `--pr-gated` arm; five call sites (`REGISTRY_BATTERY_PATHS`,
  `CF_TUNNEL_BATTERY_PATHS` + the three new, lint-a/-b under one `if`) gain the flag and `skip_suite` else-arms
  for the new ones; add the four labels to `_suite_affected`'s EXEMPT LABELS case (and fix its count comment).
  Runner edits degrade `--affected` to full (`runner-changed`) for this PR by design.
- `scripts/lib/test-relevance-paths.sh` -- three new `*_PATHS` arrays with provenance comments; update the
  six-site header to name the `--pr-gated` flag as site 3's second form; add prefixes to
  `TEST_RELEVANCE_PREFIXES` only if a declared path is not already under one.
- `scripts/lib/test-affected-paths.sh` -- withdraw the four labels from `ALWAYS_ON_SUITES`; add four consumed
  edges (`"<label>|<ARRAY>"`) to `AFFECTED_CONSUMED_EDGES`.
- `scripts/lint-orphan-test-suites.sh` -- `RELEVANCE_ARRAYS` gains three rows with path-count floors; widen the
  DE-REFERENCE ANCHOR `ref_re` to accept `( --pr-gated)?`; add the Guard 2 closure check (see Guard Contract).
- `scripts/test-all-infra-coverage-notice.test.sh` -- `GATED` gains four rows (site 6: one per label, `-a`/`-b`
  share an array) AND the `RUNNER_ARRAYS` derivation regex gains `( +--pr-gated)?` (without it the
  `GATED`-vs-runner comparison FATALs on an empty derivation).
- `scripts/suite-shard-legs.tsv` -- add the new guard suite label (regenerated, not hand-edited).
- `knowledge-base/engineering/architecture/decisions/ADR-181-local-gate-declines-are-counted-verdicts.md` and
  `ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` -- `amended_by` frontmatter +
  one-paragraph amendment pointing at ADR-262. Statements that become false (plan-review/deepen verified): ADR-181
  "a decline is UNREACHABLE under CI" (property 4), "local-run optimisation only ... CI runs everything by
  construction" (Scope), "CI runs them regardless" (Consequences); ADR-242 "CI keeps the full battery" (decision 1),
  "the merge gate is unchanged: CI's required `test` runs the full battery on the PR head", "the serial battery still
  runs on CI" and the accepted-residual bound "CI's full battery on the PR head, which remains the authoritative
  merge gate"; ADR-183's "no local run is the merge gate" wording; and ADR-242's ALWAYS_ON rationale
  ("runner-SUT ... whole registration set") for the four labels. The same "CI runs everything" claims in the
  `_diff_touches` header and the `_suite_affected` FAIL-SAFE comment in `scripts/test-all.sh` are rewritten.
- `scripts/test-all-group-affected.test.sh`, `scripts/test-all-affected.test.sh`: only if their CI-arm
  assertions (`CI=1` => no decline) need the `GITHUB_EVENT_NAME` unset/non-PR control row; they must not change
  meaning. `.github/workflows/ci.yml` is NOT edited (no binding); confirm with `git diff --stat` at ship.

## Files to Create

- `scripts/test-all-pr-battery-gate.test.sh` -- the guard suite (Guard 1 matrix below); sandbox git repo with an
  `origin/main` and a PR-shaped branch, driven with `CI=1 GITHUB_EVENT_NAME=pull_request`; registered LAST in its
  block in `scripts/test-all.sh`'s `scripts` group, classified `ALWAYS_ON` (runner-SUT).
- `scripts/ci-battery-gate-replay.sh` -- <= 30 lines, read-only, no fetch; falls back to `HEAD` when `origin/main`
  is absent (preflight Check 10 runs it in a sandbox with the repo read-only) and prints the `run_rate` header
  unconditionally so the fallback path still satisfies the probe: replays the declared arrays against the last N first-parent
  commits of `origin/main` with one `git log --name-only`, prints `battery<TAB>run_rate` per array. Kept (a
  reviewer recommended cutting it for a pasted one-liner) because it is the `discoverability_test` command that
  must exist in THIS PR's tree (runnable locally, no credentials), it supplies the pre-merge forecast the ADR
  quotes, and a stale or too-narrow array shows up as a run-rate drift.
- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` -- exit 0 when the post-merge soak holds (see
  Observability); reuse an existing `scripts/followthroughs/*` shape, keep it short.
- `knowledge-base/engineering/architecture/decisions/ADR-262-pr-ci-path-gates-the-self-test-mutation-batteries.md`.
- `knowledge-base/project/specs/feat-one-shot-9323-path-gate-mutation-batteries/tasks.md` (plan skill).

## Open Code-Review Overlap

Checked 87 open `code-review` issues against every path in the Files lists (two-stage `gh ... --json` then
`jq --arg`). Three matches, all acknowledged:

- #8659 (test-helpers composed EXIT trap leaks the incident sandbox on direct runs; names `scripts/test-all.sh`):
  **Acknowledge** -- a different concern (suite trap composition), not touched by the predicate change; remains open.
- #7942 (two `*.mutation.sh` batteries in `plugins/soleur/test/` run in no gate; names `scripts/test-all.sh`):
  **Acknowledge** -- about unregistered suites, orthogonal to gating registered ones; any battery registered
  there later could opt in via `--pr-gated`.
- #8800 (census sandbox shares inodes with the live repo; names `scripts/lib/test-affected-paths.sh` and
  `scripts/test-all-affected.test.sh`): **Acknowledge** -- this plan edits `test-affected-paths.sh` (ALWAYS_ON
  withdrawal, consumed edges) but does not touch the census sandbox construction; the guard suite builds its
  own fixtures with `cp` of files, never hardlinks (`cp -al`) into the live tree. Remains open.

## Implementation Phases

### Phase 0 -- Spikes (no product code; answers recorded in the PR)

1. Confirm `bash scripts/test-all.sh --print-affected-set` (used by the linter's census arm) can emit the derived
   edge set for one label outside `--affected` mode; if it cannot cheaply, Guard 2 falls back to asserting the
   battery's own `"$REPO_ROOT/<path>"` / `source` literal operands are a subset of the array (record which path
   was taken and the fallback's known blind spot: globs such as `.github/workflows/*.yml` are covered only by the
   directory-prefix entry).
2. Replay (`scripts/ci-battery-gate-replay.sh`, written first) each candidate array against 300 commits; record
   run-rates in the PR and quote ONLY its output in ADR-262.
3. Enumerate-consumer audit: run `CI=1 GITHUB_EVENT_NAME=pull_request bash scripts/test-all.sh --enumerate-commands`
   on a docs-only fixture branch before and after the change; the output must be byte-identical (the PR arm is
   inert under `_ENUMERATE`). Run each enumerate consumer (`scripts-shard-totality`, the orphan linter census,
   `fanout-suite-scope`, `battery-tag-authorship`, and the nine suites that set `CI=1` and invoke the runner)
   under that env on the docs-only fixture.
4. Declare test-all-affected's subject set by dependency: `scripts/test-all.sh`, the three libs it copies
   (`test-relevance-paths.sh`, `test-affected-paths.sh`, `repo-write-boundary.sh`), `scripts/lint-orphan-test-suites.sh`,
   its own file; record the census sandbox's whole-`scripts/` hardlink copy as the named R3 blind spot. Measured
   arm-rate of a `scripts/` prefix instead is 54% (163/300) -- the fallback if the dependency set proves unsound.

### Phase 1 -- Write the matrix first, then RED tests (`cq-write-failing-tests-before`)

Author `scripts/test-all-pr-battery-gate.test.sh` from the Guard Contract below before touching
`test-all.sh`; it must fail on `origin/main`'s runner (no PR arm exists).

### Phase 2 -- Predicate + arrays (GREEN)

`_diff_touches --pr-gated`; three arrays; five call sites; `skip_suite` arms; affected-index edits; linter rows
and regex widenings; `GATED` rows and `RUNNER_ARRAYS` regex; EXEMPT list.

### Phase 3 -- Measurement tooling + registration

`ci-battery-gate-replay.sh`; follow-through script; shard manifest regen; register the guard suite last in its
block; verify s1/s2 `ran>0`.

### Phase 4 -- ADR + amendments

ADR-262 (via `soleur:architecture`), ADR-181/ADR-242 amendment stanzas. Run `c4-count-parity`.

### Phase 5 -- Verification

Full `bash scripts/test-all.sh --full` once (this PR touches the runner, so `--affected` degrades to full
anyway); `scripts-shard-totality` and the `shard-totality-mutations` job; on this PR's own CI run, because the
diff touches `test-all.sh`, every battery must RUN (self-proof of the machinery-degrade arm); file the deferral
issues (Non-Goals) with milestone from the roadmap; write the plan-review Taste/User-Challenge items to
`decision-challenges.md` (already done at plan time).

## Guard Contract

### Guard 1 -- PR battery gate (discriminator, predicate, call sites)

**Property.** On a `pull_request` CI run a gated battery is declined if and only if the PR's net diff (including
rename sources) contains none of the battery's subject paths and none of the gate-machinery paths; every other
arm -- `push`, `merge_group`, `workflow_dispatch`, `main-health-monitor`, local `--full`,
`SOLEUR_TEST_FORCE_ALL=1`, `CI` unset, unset/other `GITHUB_EVENT_NAME`, undeterminable diff -- runs it.

**Assembly.** The chokepoint is `_diff_touches` in `scripts/test-all.sh`; the members are the five
`_diff_touches --pr-gated` call sites (registry, cf-tunnel, lint-a/-b under one `if`, tag-authorship,
test-all-affected) over five arrays, and the `skip_suite` else-arm at each. Members are discovered by the
behavioural arm (it drives the real runner with stubbed registrations and counts `[skip]` lines), not by this
list -- a sixth `--pr-gated` site that the arm does not exercise reds the floor row.

**Suite mechanics (deepen-plan, test-design review).** The suite never touches the live runner (sibling shards are
executing it): it copies `scripts/test-all.sh` and `scripts/lib/*` into `$TMP`, applies each mutant to the COPY with a
block-scoped `sub_once` that asserts exactly one substitution (the five call sites are near-identical, so an
unscoped `s///` lands on the wrong site), checks the mutant landed with a region-scoped grep and `bash -n`, and
grades a mutant caught ONLY when it fails its named arm (a syntax-broken mutant reds everything and must not read
as caught). Every arm runs under `env -u CI -u GITHUB_EVENT_NAME -u TEST_GROUP -u 'SOLEUR_*' -u 'TEST_SHARD*' -u 'GIT_*'`
then sets exactly what the arm needs; `tc_acquire`/`tc_preamble` are neutered as in the group-affected precedent so a
sibling-run refusal cannot depend on concurrent sessions; `_diff_detect_ok` is NOT neutered (row 3 would be vacuous).
Registrations are replaced by a recorder emitting `RECORDED_SUITE:<label>`; every RUN assertion requires that
positive line exactly once (absence of `[skip]` also describes an rc=4 or an empty selection), with a floor on the
recorded total, and uses `TEST_GROUP=all` (the batteries span the light and heavy groups). An instrument control
runs first: the pristine runner must go green on every arm before any mutant is read. Runtime: each mutant runs
only its discriminating arm, arms run in parallel, and the pristine arm is timed first against a 60 s budget.

**Mutation matrix.** Each row is an edit that MUST drive the named check RED. Labels asserted are the SIX
registration labels (lint `-a` and `-b` emit two `[skip]` lines from one site).

| # | Mutation (applied to the `$TMP` copy) | Must red | Class |
|---|---|---|---|
| 1 | Predicate mutated to always-decline under the PR arm | arm: a diff touching one battery's own file must RUN exactly that battery's labels (and the canary line appears on the mutant) | declines-everything |
| 2 | Predicate mutated to always-run under the PR arm | arm: docs-only diff must DECLINE all six labels with counted `[skip]` lines | vacuous gate (saves nothing) |
| 3 | Fail-safe arm removed, for `_diff_detect_ok` AND separately `_diff_head_ok` | arm: no `origin/main` ref / failing `git diff HEAD` => all run | undeterminable diff declines |
| 4 | Event test loosened (honors any non-empty `GITHUB_EVENT_NAME`, or ignores it) | arm: `push`, `merge_group`, `workflow_dispatch`, `schedule`, unset => all run | gate reaches main / monitor |
| 5 | Bypass ignores `CI` | arm: `GITHUB_EVENT_NAME=pull_request` with `CI=""` (set-but-empty) and unset => local semantics; `CI=1` with event unset => all run | local leak |
| 6 | Gate-machinery path removed from ONE array, one mutant per array (five mutants) | arm: a diff touching only `scripts/test-all.sh` must RUN that array's labels | machinery edit declines a battery |
| 7 | **Lost opt-in:** one call site reverts to bare `_diff_touches`, one mutant per site (five) | arm: PR-event docs-only diff; the reverted site's labels RUN and every other label declines | allowlisted battery never gated |
| 8 | **Dispatch self-check:** suite exercises 0 gated sites | floor: the site set is DERIVED by grepping `_diff_touches --pr-gated` in the runner and compared by SET EQUALITY with the expected labels (a sixth site the arm does not exercise reds); "0 checked" is not green | vacuous dispatch |
| 9 | Rename-only / delete-only diff of a declared SUT path; rename below the similarity threshold (delete+add) | arm must RUN | rename/delete slips the predicate |
| 10 | Enumerate gated: drop the `_ENUMERATE` inertness | arm: `CI=1 GITHUB_EVENT_NAME=pull_request --enumerate-commands` on a docs-only diff emits zero `SUITE_COMMAND_DECLINED` and is byte-identical to the event-unset stream | enumerate consumers break under PR env |
| 11 | Canary deleted, then predicate mutated to always-decline | arm: the battery must RUN and `PR_GATE_CANARY_FAILED` must print on the always-decline mutant with the canary present; with the canary deleted row 1 reds | canary vacuous |
| 12 | **Per-battery isolation table:** touch each battery's own file in turn | arm: that battery (only) RUNs, the others decline; covers a typo in any single array | array typo invisible to a one-battery test |

Rows owned elsewhere (asserted by their existing owners, listed so the contract is complete): `skip_suite` else-arm
deleted at a site -> `GATED` harness + linter site-4 check; guard-suite registration moved mid-block -> the
existing `test-all-affected` s1/s2 `ran>0` row; the "natural repair" (editing `test-all.sh` or `ci.yml` to force a
run) edits a machinery path and so arms every battery on that PR (row 6).

**Harness rows.** (H1) Replace the suite's `pass()` with a no-op: the negative-control arm exits non-zero, and an
explicit `passed >= floor` line refuses `0 passed, 0 failed`. (H2) Must-PASS, non-canonical inputs: a diff touching
ONLY `scripts/zot-mirror-diagnosis.sh` (a registry array member that is not the canonical SUT) must RUN the registry
battery; a docs-only diff must DECLINE; a file whose path merely *contains* a subject path as a substring elsewhere
must RUN (over-match is the safe direction); a stacked-PR fixture (base branch not `main`) over-includes and RUNs.

**Anchor.** The declared arrays are a stored value compared to the thing they protect (what each battery
sources); one commit can edit both. What moves outside the commit: Guard 2 derives the closure from the
battery's own source at lint time (not from the array), the ADR's admission rule bounds which suites may carry
`--pr-gated`, and every array self-includes its battery file so teaching a battery a new target re-arms it on
the same PR. The consumers of the selection lists, quoted so they are not inert: `_diff_touches` at each call
site (`if _diff_touches --pr-gated "${X_PATHS[@]}"; then`) and `scripts/lint-orphan-test-suites.sh`
(`RELEVANCE_ARRAYS`, the `ref_re` anchor).

### Guard 2 -- Subject-set closure (declared arrays cannot fall behind the battery)

**Property.** For every PR-gated battery, every repo path the battery sources, copies, or invokes is contained
in its declared array (exactly, or under a directory-prefix entry).

**Assembly.** Quantifies over all PR-gated arrays in `RELEVANCE_ARRAYS` and, per array, over the EXPLICIT FILE
operands of the battery file and the files it sources (whole-directory and corpus operands -- cf-tunnel's
`cp -a "$REPO_ROOT/scripts"` and `.github`, test-all-affected's `cp -al scripts/.`, the lint battery's
`git ls-files '*.test.sh'` -- are exempted through a declared allowlist entry with a written reason, per ADR-181's
"dependencies, not copy sets" rule, and named as ADR-262 residual R3): derived edges via `--print-affected-set` when Phase 0 spike 1 shows it works, else
`"$REPO_ROOT/<path>"` / `source` literal operands. Members drift; the assembly is the battery's source. Scope
note: two reviewers recommended cutting this guard; the issue's own risk mitigation ("derive subject paths from
what each battery actually sources") is the operator's stated direction, so it stays, bounded by the spike and
the fallback (recorded in `decision-challenges.md` as a User-Challenge).

**Mutation matrix.**

| # | Mutation | Must red |
|---|---|---|
| 1 | Add `cp "$REPO_ROOT/scripts/newthing.sh" ...` to a battery without touching its array | closure lint |
| 2 | Remove a declared path the battery still copies | closure lint |
| 3 | Replace a declared file entry with a directory that does not contain it | closure lint |
| 4 | Gate set emptied to `()` | vacuity guard (non-empty + self-including) |
| 5 | **Dispatch:** closure lint iterates zero batteries | floor on batteries checked (>= 4 labels) |
| 6 | **Second member:** a second `cp` added after a compliant first | closure lint (stops-at-first-member check) |

**Must-PASS (non-canonical).** A battery whose extra operand is a directory prefix already in the array passes; a
battery operand that is a `$TMPDIR` path (not a repo path) is ignored.

**Anchor.** The closure is computed from the battery source, which a diff editing only the array cannot change.

## Acceptance Criteria

### Functional

- [ ] ADR-262 exists, `amends` ADR-181 and ADR-242, contains the event/coverage table, the named residual
      (including "no merge queue enforced", with the ruleset read as evidence), the admission rule, and the
      alternatives not already rejected in ADR-181.
- [ ] With `CI=1 GITHUB_EVENT_NAME=pull_request` and a simulated docs-only diff, each of the five gated call sites
      prints `[skip] <label> (relevance)` and the run exits 0; the BREAKDOWN line counts them. Evidence: the
      guard suite's behavioural arm (pre-merge). A real docs-only PR showing the `[skip]` lines is post-merge
      evidence (this PR touches `test-all.sh`, so it cannot be that run): the first docs-only PR after merge is
      checked by `soleur:postmerge`/QA with `gh run view <id> --log | grep -F '[skip]'`, and the follow-through's
      runner-minute saving cannot hold unless declines occur.
- [ ] The same diff with `GITHUB_EVENT_NAME` = `push` / `merge_group` / `workflow_dispatch` / `schedule` / unset
      runs every battery; with `CI` unset it behaves as a local run; `--full` and `SOLEUR_TEST_FORCE_ALL=1` run
      every battery.
- [ ] A diff touching `scripts/test-all.sh`, `scripts/lib/test-relevance-paths.sh`,
      `scripts/lib/test-affected-paths.sh` or `.github/workflows/ci.yml` runs every battery (this PR itself).
- [ ] Under `CI=1 GITHUB_EVENT_NAME=pull_request` on a docs-only fixture, `--enumerate-commands` is byte-identical to
      the event-unset stream and every enumerate consumer (shard-totality, linter census, fanout-suite-scope,
      battery-tag-authorship) is green.
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0, reporting the new arrays in `RELEVANCE_ARRAYS`, the widened
      de-reference anchor, and the Guard 2 closure check over >= 4 batteries;
      `bash scripts/test-all-infra-coverage-notice.test.sh` exits 0 with the widened `RUNNER_ARRAYS` regex.
- [ ] `.github/workflows/ci.yml` is unchanged by this PR (`git diff origin/main...HEAD --stat -- .github/workflows/ci.yml`
      prints nothing) and `main-health-monitor.yml` is unchanged.
- [ ] `bash scripts/ci-battery-gate-replay.sh --commits 300` prints per-battery run-rates; recorded in the PR body.

### Non-Functional

- [ ] `plugins/soleur/test/c4-count-parity.test.sh` green; no `.github/workflows/*.yml` added.
- [ ] `plugins/soleur/test/scripts-shard-totality.test.sh` and the `shard-totality-mutations` job green;
      `test-all-affected` s1/s2 report `ran>0`.
- [ ] `scripts/test-all-pr-battery-gate.test.sh` (mutation matrix rows 1-12 + harness rows H1-H2, instrument control first) green and
      every row demonstrably RED against its mutant (evidence: row-by-row output in the PR).
- [ ] No battery is classified both `ALWAYS_ON` and consumed-edge (orphan linter census green).

### Quality Gates

- [ ] Post-merge follow-through enrolled (Observability section): tracker #9323 carries
      `<!-- soleur:followthrough script=scripts/followthroughs/pr-battery-gate-saving-9323.sh earliest=<merge+7d> secrets=GH_TOKEN -->`
      and the `follow-through` label; PR body says `Ref #9323` (not `Closes`), because the issue's AC4
      (runner-minutes saved >= 20 per PR CI run; `test-scripts` mean queue wait <= 10 min at similar load) is
      verifiable only after merge. The script checks the runner-minute criterion and reports queue wait as
      informational (load is not controllable).
- [ ] Deferral issues filed (Non-Goals) with re-evaluation criteria and roadmap milestone.

## Test Scenarios

### Acceptance tests (RED phase targets)

- Given `CI=1`, `GITHUB_EVENT_NAME=pull_request`, a sandbox `origin/main`, and a branch changing only `README.md`,
  when the runner executes with only the gated registrations stubbed, then each of the five call sites prints
  `[skip]` and `suites` includes them.
- Given the same but the branch changes `scripts/registry-pull-path-health.sh`, then the registry battery RUNS and
  the other four decline.
- Given the branch changes `scripts/lib/test-relevance-paths.sh`, then all five RUN.
- Given no `origin/main` ref, then all five RUN.

### Regression

- `test-all-infra-coverage-notice`, `test-all-group-affected`, `test-all-affected`: CI-arm assertions still hold
  with `GITHUB_EVENT_NAME` unset or non-PR.
- Local `--affected`: a diff touching a lint-orphan subject selects the battery; an irrelevant diff declines it
  as `relevance` with the ADR-181 rerun line (this is the deliberate local change).

### Edge cases

- Rename below the similarity threshold (delete+add) of a subject path; delete-only; new file under a subject
  prefix that no array names (must DECLINE -- and is caught by Guard 2 only if a battery sources it);
  stacked PR (non-main base) over-includes (harness row H2). Bot PRs created with `GITHUB_TOKEN` carry synthetic checks and never run the real legs before or after this change (R4); their verification is the push run only.

### Integration verification (for `soleur:qa`)

- After the PR is opened: the `test-scripts` and `test-scripts-heavy` logs show `0 skipped` for the five batteries
  (the PR touches `test-all.sh`). A second, docs-only PR shows `[skip] ... (relevance)` lines for them:
  `gh run view <id> --log | grep -F '[skip]'`.

## User-Brand Impact

**If this lands broken, the user experiences:** a green PR that never ran a self-test battery, so a regression in
the gate machinery (registry authorization gate, orphan-suite linter) reaches `main` and is reported on the
merge-SHA push run or the next monitor cycle instead of on the PR -- a maintainer-facing delay, not an
end-user-facing outage.
**If this leaks, the user's [data / workflow / money] is exposed via:** no user data is touched; the change reads
git diffs and writes CI log lines. The sole exposure is to the maintainers' workflow (a missed regression in
tooling that guards infra authorization), bounded by the main push run and the 6-hourly monitor.
**Brand-survival threshold:** none. `threshold: none, reason: CI-only change to internal test selection; no
user data, credentials, or production runtime path is modified, and full coverage is retained on push/monitor.`

## Observability

```yaml
liveness_signal:
  what: "[skip] <label> (relevance) lines and the BREAKDOWN 'N skipped (declined -- not relevant to this diff)' count in each test-scripts/test-scripts-heavy leg log; main-health-monitor heartbeat for the full-coverage backstop"
  cadence: "every pull_request CI run (gate); every 6 h (monitor backstop)"
  alert_target: "main-health-monitor files ci/main-broken P1 on red; Sentry missed-check-in on the monitor heartbeat"
  configured_in: "scripts/test-all.sh (skip_suite); .github/workflows/main-health-monitor.yml"
error_reporting:
  destination: "CI job result (required check `test`) on PR and on the merge-SHA push run; ci/main-broken issue from the monitor"
  fail_loud: "a declined battery that would have failed surfaces as a red push-to-main CI run for the merge SHA (per-SHA concurrency, ADR-217) and a red monitor run; an undeterminable diff or non-PR event runs the battery (fails toward coverage)"
failure_modes:
  - mode: "subject array stale or too narrow -> battery declines forever on PRs"
    detection: "Guard 2 closure lint in lint-orphan-test-suites (PR-time); run-rate drift in scripts/ci-battery-gate-replay.sh; post-merge, the red merge-SHA push run (workflow run log, `::error::` annotations) or the monitor's ci/main-broken issue"
    alert_route: "red lint-orphan-test-suites suite in required `test` on the PR that introduced the drift; red push run / ci/main-broken for an escape"
  - mode: "predicate regression on a PR run (accident class) -> machinery edit declines a battery"
    detection: "in-runner canary prints PR_GATE_CANARY_FAILED and forces run-all (runner stdout in the job log)"
    alert_route: "visible in the PR's required `test` job log; guard-suite rows 1 and 11 cover it pre-merge"
  - mode: "discriminator matches a non-PR event -> full backstop silently gated"
    detection: "guard-suite behavioural rows 4-5 (push, merge_group, workflow_dispatch, schedule, unset, CI unset)"
    alert_route: "red required `test` on the PR that edits the predicate"
  - mode: "break escapes via a path outside every declared set"
    detection: "merge-SHA push CI run runs all batteries; main-health-monitor every 6 h"
    alert_route: "red push run / ci/main-broken P1 (same channel as a red test today)"
  - mode: "diff undeterminable"
    detection: "fail-safe arm runs the battery (guard-suite row 3); suite-timings artifacts carry `skip=relevance` rows and the runner's `_relevance_declined` counter (scripts/test-all.sh) for every decline"
    alert_route: "none needed (fails toward coverage); the battery's own [skip] line is absent"
logs:
  where: "GitHub Actions job logs for ci.yml test-scripts / test-scripts-heavy; suite-timings-scripts-* artifacts record skip=relevance rows"
  retention: "GitHub default (90 d); timings artifacts 14 d"
discoverability_test:
  command: "bash scripts/ci-battery-gate-replay.sh --commits 60"
  expected_output: "run_rate"
```

### Soak follow-through enrollment

`scripts/followthroughs/pr-battery-gate-saving-9323.sh` follows the followthrough convention
(`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`): xtrace-refusal prologue (exit 78),
no `: "${VAR:?}"` (banned by `scripts/lint-followthrough-varq-ban.sh`), exit 0 = soak holds, 1 = fails, 2 = transient.
Window pinned to runs whose head is after the merge SHA; excludes cancelled runs, bot PRs (no real legs) and PRs
that touch any machinery path; needs >= 20 qualifying runs else exit 2 (never a fail). Exit 0 requires (a) mean
billable runner-minutes per run (sum over `test-scripts*` jobs) at least 20 below the pinned pre-change baseline
(76 runner-min per run, measured 2026-09-30 on 15 runs, recorded in the script header with its producing command)
AND (b) the escape-rate check: no `ci.yml` push run for the merge SHA of those PRs is red where the PR run was
green. Mean `test-scripts` queue wait is printed as informational and never affects the exit code. Failure action:
the sweeper comments on #9323 and the operator decides between widening arrays and reverting the PR arm. The
directive's `earliest` is a full ISO timestamp (`YYYY-MM-DDTHH:MM:SSZ`) at column 0 outside any code fence, set
at ship time to merge + 7 d; the probe must exist in the main checkout before the tracker is annotated. Directive
on tracker #9323: `earliest=<merge+7d>`, `secrets=GH_TOKEN`; no new secret wiring beyond the sweeper's existing
`GH_TOKEN`.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Gating only on the pull_request event is correct; `merge_group`/`push`/`workflow_dispatch` keep the
full run. Prefer parameterising `_diff_touches` over a second predicate (adopted). Risks: silent coverage loss on
PRs (mitigation: Guard 2 closure lint), derived edges evaluated only at HEAD so delete/rename of a sourced file
could decline (mitigation: the predicate consumes the diff blob incl. rename sources, and a delete-only row is in
the matrix), shard/leg starvation after #9173/#9197 (mitigation: last-in-block registration + s1/s2 `ran>0`
row), red landing on main with up-to-6 h latency (recorded as the named residual; the merge-SHA push run narrows
it to minutes). No required-check hazard: a relevance decline exits 0 and no job `if:` changes. State the
merge-queue fact in the ADR (verified: not enforced).

No Product/UX, marketing, legal, finance, sales or support implications: internal CI tooling; no user-facing
surface (mechanical UI-surface override: no path in Files matches `ui-surface-terms.md`).

## Plan Review Record (2026-09-30)

Panel: DHH, Kieran, code-simplicity (3-agent baseline; threshold `none`). Both the simplification and the
correctness axes fired on the guard apparatus, so cuts were preferred to fixes.

- **Applied (mechanical):** Kieran P0s (linter anchor `ref_re`, `RUNNER_ARRAYS` regex, single `if` for `-a`/`-b`,
  "5 sites over 5 arrays"); floor claim corrected (`_MIN_ALWAYS_ON_DECLARED` is a hand literal, no re-derive);
  reaper battery cut (already has `AFFECTED_SCRIPTS_ORPHAN_PROCESS_REAPER_MUTATIONS_PATHS`; a second array would
  shadow it); explicit env flag cut in favour of `GITHUB_EVENT_NAME` (no `ci.yml` edit, no YAML wire guard, rows
  1-3/18/19 dissolved); banner + `GITHUB_STEP_SUMMARY` cut; linter `--pr-gated` census cut (a lost flag is caught
  behaviourally by row 7); runbook edit cut; matrix trimmed 19 -> 12 rows; merge-queue fact verified against the
  ruleset; EXEMPT-list comment count; consumed-edge rows confirmed read.
- **Surfaced for the operator (`decision-challenges.md`):** Guard 2 kept despite two cut recommendations (issue's
  own mitigation); `ci-battery-gate-replay.sh` kept despite two cut recommendations (needed as the
  `discoverability_test` command); reaper battery deferred although named in the issue's next tier.

## Non-Goals / Deferrals (each gets a GitHub issue at work time)

- Gating the `orphan-process-reaper-mutations` battery (100-165 s tier): it already has a declared affected edge
  set; fold it into the gate set after the post-merge measurement, reusing that array rather than a second one.
- Extending `--pr-gated` to the non-mutation next-tier suites (`betterstack-roundtrip-latency`,
  `playwright-mcp-redact-proxy`, `test-contention`, `git-data-birth-readiness-gate`, `sentry-alert-live-fidelity`,
  `monitor-pr-checks`) -- re-evaluate after the post-merge measurement shows the remaining top-N by runner-minute;
  milestone: Post-MVP / Later.
- Extending to the already relevance-gated `c4-from-components`, `.github/scripts/test/run-all.sh`, webplat app
  arm -- requires per-suite CI-home review (ADR-181 addendum section 7 withdrew an undercounted "one CI home").
- Narrowing the `.github/workflows/` prefix in the lint-orphan array to the workflow files the linter actually
  parses (would cut the 38% arm-rate) -- needs linter-side enumeration of consumed workflow files.
- Merge queue adoption (would make the gate fully closed pre-merge) -- out of scope; recorded in ADR residual.

## Risks

- **A gated battery's subject set is wrong.** Guard 2 + self-inclusion + the full push/monitor backstop; the
  residual is named in the ADR rather than denied.
- **Local behaviour change for four suites** (they now decline locally on irrelevant diffs): intentional and
  uniform; `--full` is the lever; ADR-242 amendment records it.
- **This PR edits the runner**, so it runs every battery (self-proof), and `--affected` degrades to full locally.
- **Trust root (R2):** a pull_request run executes the PR's own runner and predicate; the canary covers accidents, not a
  coordinated adversarial edit, and CODEOWNERS is inert (no code-owner review rule in the CI Required ruleset). Named in ADR-262.
- **test-all-affected saves less than the issue assumes:** its census sandbox hardlinks all of `scripts/`; declared by
  dependency (saving ~80%) with a measured fallback of a `scripts/` prefix (54% arm-rate, saving ~46%).
- **Positional shard parity** when registering the guard suite: last-in-block, s1/s2 `ran>0` row.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries placeholder text fails `deepen-plan` Phase 4.6;
  this one declares threshold `none` with a reason.
- Every `--pr-gated` site needs the `skip_suite` else-arm; `skip_suite` and `run_suite` apply the same
  `_shard_selects` filter, so a per-leg denominator cannot disagree.
- Do NOT put a `*.test.sh` path literal on a `run_suite` line; the predicate is referenced by array name
  (ADR-181 rejected the inline form).
- A relevance array must contain its own battery file and `scripts/lib/test-relevance-paths.sh`.
- `git log --first-parent` replay counts squash-merge commits; a PR's own diff is the same set -- do not replay
  with `--no-merges` over merge commits.
- Re-verify the ADR ordinal across EVERY `origin/*` ref (not only `origin/main`) immediately before merge and
  after each sync; ADR-262 was free on all remote refs at plan time (2026-09-30). If renumbered, sweep
  `plans/` and `specs/` for the old ordinal in the same edit.
- The run-rates quoted in Research Insights came from an ad-hoc replay (a one-off `git log --name-only` tally).
  The published procedure is `scripts/ci-battery-gate-replay.sh`; re-run it once before any number is written
  into ADR-262 or the PR body, and use ITS figures (definitions can diverge: "touches" here is substring-match on
  the diff blob including rename sources, not `--diff-filter`).
- `discoverability_test.command` is executed by preflight Check 10 under a 15 s cap with a shell-active reject
  (no `|;&<>$` or backticks); the replay script takes `--commits 60` and performs one `git log`.
- The linter/harness regex widenings (`( +--pr-gated)?`) are load-bearing: without them the orphan linter and
  the coverage-notice harness red on the first run with misleading "declared but consumes nothing" / FATAL text.
- Run `npx markdownlint-cli2` on this plan and `tasks.md` before the Session Summary (hard tabs, MD032).

## References

- Issue #9323; ADR-181, ADR-183, ADR-188, ADR-196, ADR-217, ADR-242.
- `scripts/test-all.sh` (`_diff_touches`, `skip_suite`, `_suite_affected`, epilogue),
  `scripts/lib/test-relevance-paths.sh`, `scripts/lib/test-affected-paths.sh`,
  `scripts/lint-orphan-test-suites.sh` (`RELEVANCE_ARRAYS`, `ref_re`), `scripts/test-all-infra-coverage-notice.test.sh`
  (`GATED`, `RUNNER_ARRAYS`), `.github/workflows/ci.yml` (`test-scripts`, `test-scripts-heavy`, `test`),
  `.github/workflows/main-health-monitor.yml`.
