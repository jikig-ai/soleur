---
title: PR CI path-gates the self-test mutation batteries; push, merge_group, dispatch and the main-health monitor run everything
status: active
date: 2026-09-30
amends: ADR-181, ADR-242
related_adrs: [ADR-181, ADR-183, ADR-217, ADR-242]
issue: 9323
---

# ADR-262: PR CI path-gates the self-test mutation batteries (#9323)

## Context

`scripts/test-all.sh` under `CI` ran every registered suite on every pull request, because
`_diff_touches` returned true unconditionally when `CI` was set (ADR-181 property 4). Five self-test
mutation batteries therefore cost runner time on PRs that never touched what they mutate. Measured on
2026-09-30 (issue #9323): `test-scripts` is ~58% of CI runner minutes, those batteries hold ~40% of script
suite time, and runner concurrency is the binding constraint — runner minutes turn directly into queue
wait, and strict up-to-date branch protection turns each queued PR into a restart.

## Decision

1. **A pull_request run declines a gated battery when the diff touches none of its subject paths.**
   `_diff_touches --pr-gated <array>` skips the `CI` bypass only when `CI` is set **and**
   `GITHUB_EVENT_NAME == pull_request` **and** the call is not an enumeration **and** the in-runner
   canary has not tripped. It is a call-site opt-in: every other `_diff_touches` caller keeps ADR-181's
   contract. No `ci.yml` change and no new env flag — the event name Actions sets is already
   authoritative and equally fail-closed.
2. **Every other arm runs the suite.** `push`, `merge_group`, `workflow_dispatch`, `schedule`, an unset
   event, `--full`, `SOLEUR_TEST_FORCE_ALL=1`, `CI` unset-by-design for local runs, and an undeterminable
   diff all behave as before. `main-health-monitor` is dispatched, so it stays full.
3. **The gated set** is the six registrations of five batteries, each with a declared array in
   `scripts/lib/test-relevance-paths.sh`:

   | Battery | Array | Measured arm-rate (last 300 first-parent commits) |
   |---|---|---|
   | `tests/scripts/registry-gate-mutation-battery` | `REGISTRY_BATTERY_PATHS` | 23% |
   | `scripts/cf-tunnel-liveness-gate-mutations` | `CF_TUNNEL_BATTERY_PATHS` | 26% |
   | `scripts/lint-orphan-test-suites-mutations-a` / `-b` | `LINT_ORPHAN_BATTERY_PATHS` | 38% |
   | `scripts/battery-tag-authorship-mutations` | `TAG_AUTHORSHIP_BATTERY_PATHS` | 26% |
   | `scripts/test-all-affected` | `TEST_ALL_AFFECTED_BATTERY_PATHS` | 21% |

   Source: `bash scripts/ci-battery-gate-replay.sh --commits 300` (substring match over the commit's
   name-status blob, rename sources included — the same semantics as `_diff_touches`). Weighted by the
   issue's measured battery seconds this is ~27 of ~39 battery suite-minutes saved per PR CI run on
   average, against the issue's ~35 ceiling. The figure is a forecast; the post-merge follow-through
   measures it.
4. **Admission rule.** A suite may carry `--pr-gated` only if it is a self-test of the gate or test
   machinery whose verdict is a property of named files (computed on sandbox copies, not on the live
   tree). Behavioural suites over product code do not qualify. Every array contains its own battery
   file, `scripts/lib/test-relevance-paths.sh`, and the shared `PR_GATE_MACHINERY_PATHS` (the runner, the
   affected index, `ci.yml`, the shard manifests), so editing the gate arms every gated battery on that PR.
5. **A decline is a counted, printed verdict** (`skip_suite`, ADR-181 properties 1–2). Nothing new is
   added to the summary; the BREAKDOWN line already counts it.
6. **Enumeration is never gated.** `--enumerate`/`--enumerate-commands` answer "what is registered"
   (ADR-242 decision 5); the PR arm is inert under them so shard-totality and the census linter read a
   byte-identical stream under the PR environment.
7. **Three guards hold it.** `scripts/test-all-pr-battery-gate.test.sh` drives a copy of the runner from a
   fixture repo and mutates it (Guard 1); `scripts/lint-orphan-test-suites.sh` derives the `--pr-gated`
   arrays from the runner and checks each battery's explicit `$REPO_ROOT/<path>` operands against its
   array, with a written-reason allowlist for whole-tree operands (Guard 2); the in-runner canary prints
   `PR_GATE_CANARY_FAILED` and forces run-all if the predicate misclassifies a fabricated diff.

## Coverage split

| Event | Gated batteries |
|---|---|
| `pull_request` | run only when the diff touches a subject or machinery path |
| `push` to `main` (per-SHA run, ADR-217), `merge_group`, `workflow_dispatch`, `schedule` | **run** |
| `main-health-monitor` (6-hourly, dispatched) | **run**; files `ci/main-broken` P1 on red |
| local `--full`, `SOLEUR_TEST_FORCE_ALL=1` | **run** |

`workflow_dispatch` of `ci.yml` is the documented force-full lever.

## Residuals (named, not denied)

- **R1 — an escape is caught on the push run, not the PR.** A change that breaks a battery without
  touching its declared paths merges green and reds on the merge-SHA push run (which also blocks that
  SHA's deploy, ADR-217) or the 6-hourly monitor. The fix PR must widen the declaring array; that edit
  touches `scripts/lib/test-relevance-paths.sh`, which arms every gated battery on that PR. **No merge
  queue is enforced** (read 2026-09-30: ruleset 14145388 `CI Required` carries only a
  `required_status_checks` rule), so a semantic interaction between two concurrently open PRs surfaces on
  the main push run, attributed to a commit.
- **R2 — trust root.** A pull_request run executes the PR's own runner and predicate. The canary covers
  an accidental regression; a coordinated edit of the predicate, the canary and the guard suite is
  undetectable in-repo. CODEOWNERS would be inert: the ruleset has no code-owner review rule.
- **R3 — corpus blind spots by construction.** A battery whose subject is a whole tree is declared by
  dependency, not copy set (ADR-181): cf-tunnel copies `scripts/` and `.github/`, test-all-affected
  hardlinks all of `scripts/`, the lint battery materialises `git ls-files '*.test.sh'`, and the
  tag-authorship battery walks the runner's closure. An edit to an undeclared member of such a corpus is an
  R1 escape. The allowlist in the linter names each one with its reason.
- **R4 — bot PRs.** PRs authored with `GITHUB_TOKEN` carry synthetic checks and never run the real legs,
  before and after this change; their verification is the push run.

## Alternatives considered

Only those not already rejected in ADR-181 (a nightly workflow for the gated set, a CI "no skip occurred"
assertion and a relevance manifest are rejected there):

- **Job-level path filters on the heavy legs** — rejected: the legs are a required chain, so a skipped job
  would put unreported-versus-skipped semantics into the required context.
- **An explicit `SOLEUR_PR_BATTERY_GATE` binding in `ci.yml`** — rejected: `GITHUB_EVENT_NAME` is already
  authoritative; a binding needs its own YAML wire guard and adds a way to be wrong.
- **Adopting the affected classifier wholesale on CI** — rejected: it changes selection for ~500 suites, a
  blast radius the issue does not ask for.
- **A second predicate function** — rejected: `_diff_touches` already owns the substring, fail-safe,
  rename-source and untracked arms; a copy would drift.

## Consequences

- Four labels leave `ALWAYS_ON_SUITES` and become consumed edges (ADR-242 amendment): their verdict is
  computed on sandbox copies of named files, so a declared array is a better edge than "the whole tree".
- Locally, the three newly gated batteries now decline on an irrelevant diff too, like the registry
  battery since ADR-181; `--full` is the lever.
- A PR that edits the runner, the relevance or affected libraries, `ci.yml` or a shard manifest runs every
  battery, including this PR (the self-proof of the machinery arm).
- The saving is measured, not asserted: `scripts/followthroughs/pr-battery-gate-saving-9323.sh` re-measures
  billable runner minutes and checks the push runs for escapes after the soak.

## References

ADR-181, ADR-183, ADR-217, ADR-242; issue #9323; `scripts/test-all.sh` (`_diff_touches`), `scripts/lib/test-relevance-paths.sh`,
`scripts/lint-orphan-test-suites.sh`, `scripts/test-all-pr-battery-gate.test.sh`, `scripts/ci-battery-gate-replay.sh`.
