---
title: PR CI path-gates the self-test mutation batteries; push, merge_group, dispatch and the main-health monitor run everything
status: active
date: 2026-09-30
amends: ADR-181, ADR-242
related_adrs: [ADR-181, ADR-183, ADR-188, ADR-217, ADR-242]
amended_by:
  - "ADR-276 S4 (2026-10-14, #9729) — the premise R1 'No merge queue is enforced' and the PR-arm admission rule are reversed for the PR arm once S4 is activated (dark and locked until then); see ## Amendment — 2026-10-14"
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
   authoritative and equally fail-closed. **The variable is ambient, so it is inherited:** any suite that
   re-executes the runner under `CI` (the coverage-notice, group-affected and runtime-ceiling suites do)
   must clear `GITHUB_EVENT_NAME` as it clears `CI`, or the nested runner takes the PR arm inside a
   pull_request job. The first CI run of this change failed on exactly that.
2. **Every other arm runs the suite.** `push`, `merge_group`, `workflow_dispatch`, `schedule`, an unset
   event, `--full`, `SOLEUR_TEST_FORCE_ALL=1`, `CI` unset-by-design for local runs, and an undeterminable
   diff all behave as before. `main-health-monitor` is dispatched, so it stays full.
3. **The gated set** is the six registrations of five batteries, each with a declared array in
   `scripts/lib/test-relevance-paths.sh`:

   | Battery | Array | Measured arm-rate (last 300 first-parent commits) |
   |---|---|---|
   | `tests/scripts/registry-gate-mutation-battery` | `REGISTRY_BATTERY_PATHS` | 22% |
   | `scripts/cf-tunnel-liveness-gate-mutations` | `CF_TUNNEL_BATTERY_PATHS` | 24% |
   | `scripts/lint-orphan-test-suites-mutations-a` / `-b` | `LINT_ORPHAN_BATTERY_PATHS` | 35% |
   | `scripts/battery-tag-authorship-mutations` | `TAG_AUTHORSHIP_BATTERY_PATHS` | 24% |
   | `scripts/test-all-affected` | `TEST_ALL_AFFECTED_BATTERY_PATHS` | 20% |

   Source: `bash scripts/ci-battery-gate-replay.sh --commits 300` (substring match over the commit's
   name-status blob, rename sources included — the same semantics as `_diff_touches`; the window is the
   ten days to 2026-10-01, so re-run it before quoting). Weighted by the issue's measured battery seconds
   this is ~28 of ~39 battery suite-minutes saved per PR CI run on average, against the issue's ~35
   ceiling. **These are runner-minutes, not wall-clock:** the always-on guard suite adds about a minute to
   the light shard it sits on, and a PR's critical path is its slowest leg, which carries no battery, so
   time-to-green improves through lower queue wait rather than shorter legs. The figure is a forecast; the
   post-merge follow-through measures it.
4. **Admission rule.** A suite may carry `--pr-gated` only if it is a self-test of the gate or test
   machinery whose verdict is a property of NAMED files. Three batteries score sandbox copies of those
   files; tag-authorship and test-all-affected also drive the live tree or the real runner for their
   control and census arms, so their arrays name the inputs and the live-tree reads are residual R3. Behavioural suites over product code do not qualify. Every array contains its own battery
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
  `required_status_checks` rule). Branch protection is strict, so a PR is retested on a merge ref that
  contains everything merged before it — but a battery is still judged on the PR's OWN diff, so a subject
  edit that merged earlier does not arm it. An escape therefore surfaces on the main push run, attributed
  to a commit. **Main stays red until a fix PR widens the array:** later PRs that do not touch the array
  decline the same battery and merge green over a red main.
- **R2 — trust root.** A pull_request run executes the PR's own runner and predicate. The canary covers
  an accidental regression; a coordinated edit of the predicate, the canary and the guard suite is
  undetectable in-repo. CODEOWNERS would be inert: the ruleset has no code-owner review rule.
- **R3 — corpus blind spots by construction.** A battery whose subject is a whole tree is declared by
  dependency, not copy set (ADR-181): cf-tunnel copies `scripts/` and `.github/`, test-all-affected
  hardlinks all of `scripts/`, the lint battery materialises `git ls-files '*.test.sh'`, and the
  tag-authorship battery walks the runner's closure (and reads ADR-207, `scripts/lib/scratch-root.sh` and
  `scripts/lib/test-contention.sh`, which the runner sources). An edit to an undeclared member of such a
  corpus is an R1 escape. The linter's allowlist names each whole-tree operand with its reason, and Guard 2
  sees only literal `$REPO_ROOT/` and `${ROOT}/` operands: paths built in a loop or from a variable are
  invisible to it, so a declared array is only as complete as its battery's literal text.
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

## Amendment — 2026-10-14 (S4 PR B, #9729, ADR-276)

Pointer only. Two things this record assumes are reversed for the PR arm by ADR-276 Decision 5, as implemented by its `## Amendment 2026-10-14 (S4 PR B, #9729)`: (1) the Residuals premise "No merge queue is enforced" (R1; ADR-270 enforces it, so the `merge_group` candidate run, not the PR run, is the full-battery authority), and (2) the Decision 4 admission rule and the two rejected Alternatives that follow from it (job-level gating of the heavy legs, the affected classifier on CI), because the PR arm grows from the five self-test batteries here to the affected set. The reversal takes effect only when ADR-276's `CI_PR_AFFECTED` switch is activated, which PR B does not do (it ships dark and locked); until then this record describes the PR arm as written. The five batteries' own decisions, arrays and guards are unchanged.

## Amendment — 2026-11-12 (#9340, next-tier admissions)

**Decision 4 is widened, not replaced.** The original rule admitted only "a self-test of the gate or
test machinery whose verdict is a property of NAMED files." The widened rule is:

> A suite may carry `--pr-gated` when its verdict is a property of a **closed, declarable edge
> set** — a relevance array whose every element is named, tracked-or-committed, and justified —
> and when it is not a live-external verdict. The machinery self-test clause is unchanged and now
> applies to every admitted array: each carries its own suite file, `scripts/lib/test-relevance-paths.sh`,
> and the `PR_GATE_MACHINERY_PATHS` spread, so a diff touching the gate re-arms every gated suite.

"Closed, declarable" means the array's elements exhaust what the suite's verdict reads: a suite
whose SUT glob-expands a directory it does not consume, or shells out to a live external service
(BetterStack, Sentry, the network) for its verdict, does not qualify on the first clause and fails
the second outright. Suites admitted under this rule keep every other Decision property: the
decline is a counted `skip_suite` verdict, enumeration stays inert, and the three guards below
quantify over them for free.

**Admissions** (arm rates from `bash scripts/ci-battery-gate-replay.sh`, 300 first-parent commits
against `origin/main`, measured 2026-11-12 — the window moves, re-run before quoting; re-measured
2026-11-13 after the replay gained `--diff-merges=first-parent` — previously merge commits counted
in the denominator while never being able to arm — and all nine rates below were unchanged, while
the pre-existing batteries moved to REGISTRY 33% / CF_TUNNEL 36% / LINT_ORPHAN 42% / TAG_AUTHORSHIP
33% / TEST_ALL_AFFECTED 31% / ORPHAN_PROCESS_REAPER 34%. **All arm rates are lower bounds**:
rebase-merged multi-commit PRs replay as their individual commits, so a PR whose union diff arms a
battery but whose per-commit diffs each miss it still reads as unarmed — single-commit replay
under-counts multi-commit-PR arming on `pull_request`):

| Suite | Array | Arm rate | Notes |
|---|---|---|---|
| `plugins/soleur/test/c4-from-components.test.sh` | `C4_PRODUCER_PATHS` | 32% | gained `PR_GATE_MACHINERY_PATHS`; gated inside its glob-loop special-case |
| `plugins/soleur/test/monitor-pr-checks.test.sh` | `MONITOR_PR_CHECKS_PATHS` | 34% | glob-loop special-case; Guard-2 no-operand exemption (SUT resolved via `DIR=plugins/`) |
| `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` | `PLAYWRIGHT_MCP_REDACT_PROXY_PATHS` | 32% | glob-loop special-case; `.mcp.json`/`plugin.json` elements needed root-file prefixes in `TEST_RELEVANCE_PREFIXES` |
| `tests/scripts/git-data-birth-readiness-gate` | `GIT_DATA_BIRTH_READINESS_GATE_PATHS` | 35% | explicit `if` block replacing the bare registration |
| `tests/scripts/betterstack-roundtrip-latency` | `BETTERSTACK_ROUNDTRIP_LATENCY_PATHS` | 30% | verdict is the recorded-fixture projection, not the live call — the live half stays ungated by name |
| `scripts/test-contention` | `TEST_CONTENTION_PATHS` | 30% | explicit `if` block |
| `tests/scripts/sentry-alert-live-fidelity` | `SENTRY_ALERT_LIVE_FIDELITY_PATHS` | 33% | committed CAPTURE fixture under `knowledge-base/project/specs` — needed a new prefix entry |
| `.github/scripts/test/run-all.sh` | `GITHUB_SCRIPTS_SUITE_PATHS` | 70% | `.github`+`plugins/soleur` directory edges keep it hot; its required-workflow home (`guard-script-fixture-tests`) still runs it on every PR, so the decline buys local/PR-runner time, never coverage |
| `apps/web-platform [unit]` | `WEBPLAT_APP_PATHS` | 63% | repo-wide+component stays ungated; the `merge_group` backstop plus the ungated sibling keep full-tree coverage |

**Declines.** No candidate measured near a ~100% arm rate in this window; had one, it would have
been left ungated — a predicate that fires on every diff is a decline that never lands, and
gating it buys complexity for nothing. The two pre-existing hot arrays above (63–70%) were
admitted anyway because each carries an ungated CI home or sibling leg that makes the decline
costless in coverage terms; their gating saves runner minutes only.

**The `.github/workflows` edge is narrowed, not widened.** `LINT_ORPHAN_BATTERY_PATHS` previously
declared the whole `.github/workflows` directory. The battery's corpus is the set of workflows
whose text names `.test.sh` — the only workflows that can change registration surfaces 5/6 — so
the directory element is replaced by a committed sorted enumeration,
`scripts/lint-orphan-consumed-workflows.txt` (61 members at admission, including
`merge-bypass-audit.yml`, which over-arms until it references a suite). Completeness in the only
direction that matters is checked always-on inside `scripts/lint-orphan-test-suites.sh`: any
`.github/workflows/*.yml` matching `grep -lE '\.test\.sh'` that is missing from the enumeration
is an error. That arm is deliberately ungated — it cannot be declined by the gate it protects —
and the enumeration file is itself an element of the array, so the diff that updates it re-arms
the battery.

**Registration bookkeeping.** `scripts/merge-bypass-audit.test.sh` (#12666, sibling stream) is
registered explicitly in `scripts/test-all.sh` — ungated, like every registration surface.
`TEST_RELEVANCE_PREFIXES` gained `.mcp.json` and `knowledge-base/project/specs` so untracked
members of the new arrays remain visible to the predicate while uncommitted.
