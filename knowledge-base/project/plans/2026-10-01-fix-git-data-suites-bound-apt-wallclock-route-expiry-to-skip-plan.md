---
title: "fix(ci): bound the in-container apt wall-clock in the git-data suites and route expiry to the declared skip"
date: 2026-10-01
slug: git-data-suites-bound-apt-wallclock-route-expiry-to-skip
branch: feat-one-shot-9379-git-data-apt-timeout
issue: 9379
closes: 9379
lane: cross-domain
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: none
---

# fix(ci): bound the in-container apt wall-clock in the git-data suites and route expiry to the declared skip

## Overview

Infra Validation leg `deploy-script-tests (1/4)` has been red on every branch and on `main` since about
14:58 UTC on 2026-10-01 because `git-data-runcmd-rehearsal.test.sh` (bound 600 s) and
`git-data-ownership.test.sh` (bound 300 s) hit their per-suite wall-clock bound with `rc=124`.
Both suites boot an `ubuntu:24.04` container and run `apt-get` inside it. The "bounded apt" loop from
#8744 bounds the number of attempts (3, with `Acquire::Retries=5` inside each call) but not the elapsed
time, so one slow or stalled archive fetch can consume a whole suite budget and the outcome is a bare
`rc=124` kill instead of the declared decline the suites already define for "the apt archive's state at
that instant".

This change puts one wall-clock budget on every in-container apt cycle, shared across all containers a
suite spawns, and makes budget expiry produce exactly the outcome an apt exhaustion produces today: a
scrubbed log tail, a named cause line, the bare `FIXTURE_APT_FAILED` marker, and exit 100. The existing
routing then does the rest: skip-eligible arms in the rehearsal suite reach `arm_skip`, and the ownership
runtime arm becomes a counted declared skip on a TIMEOUT cause (an apt error stays a failure). What this
guarantees is a bounded, attributable outcome, not a green leg: the rehearsal's primary arms stay hard by
ADR-188 and fail fast with a named cause during a sustained outage. Code-only: no production ruleset,
Terraform apply, or workflow dispatch is touched.

**Plan review applied (2026-10-01).** Four reviewers (DHH, Kieran, code-simplicity, CTO). Cut:
cutover-access (its docker run is already host-bounded by `timeout -k 10 480 docker run` plus
`docker rm -f`, below its 600 s bound, and it is not in the red set), the `run-registered-suites.sh` comment
edit (no count changes), 13 `TRACE` lines, the `GD_APT_CALL_CAP` and `GD_APT_SITE_BUDGET` knobs, the
three-way cause taxonomy, mutation rows for structural wiring and the suite-on-suite harness row. Fixed: a
missing lib could launder into the environment decline, five sites flattened the helper's rc, the acceptance
greps, the 13 -> 12 container count, the ownership skip keyed on any `FIXTURE_APT_FAILED`, `dpkg` state after a
kill. Taste items are in `decision-challenges.md`.

## Research Reconciliation — Issue vs. Codebase and CI Artifacts

| Issue / brief claim | Reality (measured) | Plan response |
|---|---|---|
| "`git-data-runcmd-rehearsal` suite log is empty (0 lines) at the kill, so it never printed its first row." | The suite is silent on success by design: `pass()` only increments a counter (`git-data-runcmd-rehearsal.test.sh:24`), and only `fail()` and the final summary print. An empty log at a 600 s kill means "no failure had been recorded yet", not "stalled at the first docker run". Artifact `infra-suite-logs-0` of run 36885018496: `.meta` = `124 600 7`, `.log` = 0 bytes. | The stall location is not known from the artifact. The arm function prints one `GD_APT: armed` stderr line and every apt decline prints `since_arm`, so the next occurrence is attributable. Do not assume the first container is the one that hung. |
| "`git-data-ownership` goes silent at the runtime arm." | Confirmed for run 36880585583 (`.meta` = `124 300 0`, log ends at S9c). But on `main` run 36885018496 the same suite PASSED in 98 s, i.e. the docker+apt arm completed on a degraded archive roughly an order of magnitude slower than healthy. | The failure mode is both "slow" and "stalled". A wall-clock budget covers both; a per-attempt count covers neither. |
| "The suite already defines `arm_skip` (exit 100) for this case." | True only for the rehearsal's T5 mutation, T17 mutation and S1 family (five `^arm_skip` call sites plus four `did-not-run) arm_skip` arms). T5 primary, T17 healthy (`run_case`) and the R4 driver are deliberately NOT skip-eligible (ADR-188; a roster guard fails if T5 primary becomes eligible). In `git-data-ownership.test.sh` the apt-exhaustion branch (`FIXTURE_APT_FAILED || DRC=125`, line ~360) calls `_runtime_skip`, which under `CI=true` is a FAILURE (`fail` + `exit 1`), not a skip. | Rehearsal: keep the ADR-188 roster; primary arms fail fast with a named cause instead of being killed. Ownership: split a TIMEOUT-caused apt exhaustion out of the CI-failing `_runtime_skip` into a counted declared skip (ADR-188 ownership axis: the archive's state is owned by nobody); an apt error and rc 125 stay failures. See D2. |
| "The 'bounded' apt loop is in #8744, in the ownership runtime arm." | The same unbounded cycle exists at 7 in-container sites: ownership (1), cutover-access (1), rehearsal `run_case`, T5 mutation, T17 mutation (3 loops), the S1 `sshd-drive.sh` driver (bare, no loop), the R4 `r4-drive.sh` driver (`Retries=3`, no outer loop). Cutover-access's docker run is already host-bounded (line ~2829). `cloud-init-inngest-provision-unit.test.sh` Tier B has its own loop (bound 540, no incident). | Fix the 6 sites in the two incident suites (ownership 1, rehearsal 5) through ONE shared helper. Cutover-access and provision-unit are acknowledged, not changed (Deferrals). |

## Premise Validation (Phase 0.6)

- Issue #9379 is OPEN, no closing PR (`gh issue view 9379 --json state,closedByPullRequestsReferences`).
- Cited facts checked on `origin/main`: both suites exist; `_SUITE_BOUNDS` in
  `apps/web-platform/infra/run-registered-suites.sh` pins rehearsal=600, ownership=300;
  ADR-188 (`knowledge-base/engineering/architecture/decisions/ADR-188-*.md`) is the governing decision.
- Mechanism vs ADR corpus: the mechanism (bound the time, route to the declared skip) is what ADR-188
  already prescribes for apt. The mechanism the same corpus REJECTED is a pre-baked fixture image
  (`2026-08-13-test-remove-rehearsal-apt-dependency-plan.md` "Why the image was cut": value measured at
  ~0, and it would remove the apt-under-`set -e` RED that T5 relies on). That rejection is why this plan
  bounds apt rather than removing it. One caveat the earlier plan did not have: it measured "0 of the 10
  failures in the last 100 runs were this step"; this incident is sustained, so the failure-rate premise
  behind the cut has moved. The cut is not reversed here; monitor #8856 (skip-persistence probe, open) is
  the existing observer that decides when the image becomes owed.
- Own capability claim checked (`hr-verify-repo-capability-claim-before-assert`): "the suites have no
  elapsed-time bound on apt" was verified by grepping every `apt-get` in the suites rather than asserted
  from the issue; the same grep is what showed cutover-access is host-bounded.

## Research Insights

**Property List (what must be true afterwards).**

- P1. An in-container apt cycle cannot consume more than a fixed wall-clock budget, regardless of how many
  attempts, retries or containers are involved.
- P2. Budget expiry is indistinguishable, to every existing consumer, from apt exhaustion today:
  bare `FIXTURE_APT_FAILED` line on stderr, container exit 100, scrubbed tail first, cause line before the
  marker. No consumer's classifier needs to learn a new rc.
- P3. For an apt-induced stall, a suite's worst-case total is strictly below its `_SUITE_BOUNDS` entry with
  margin, so the outcome is the suite's own verdict and log, never `rc=124`. (A stall in the image pull is
  outside P3; see the Cut List.)
- P4. A slow-but-succeeding apt cycle still passes (the budget must not convert the 98 s ownership run into
  a failure).
- P5. A genuine harness defect (OOM-killed apt, rc 137 with no timeout; a missing or unsourceable helper) is
  NOT converted into the environment decline (the S1 driver comment records the first hazard).
- P6. The skip roster of ADR-188 does not widen for the rehearsal: no primary arm becomes skip-eligible.
  (Ownership's runtime arm gains a counted decline on a timeout cause, recorded in the ADR amendment.)

**Cut List (mechanism proposed or considered, buys no uncovered property).**

| Mechanism | Property | What already covers it / why cut |
|---|---|---|
| Raise `_SUITE_BOUNDS` for the two suites | P3 | Does not bound anything; the leg has a 15 min `timeout-minutes` shared across suites run `-P4`. Cut. |
| Pre-baked fixture image | P1 | Cut by the 2026-08-13 measured review (value ~0; would drop the apt-under-`set -e` RED). Not re-litigated. |
| Pre-pull the pinned image once with a host timeout | P1 for a pull stall | No evidence the pull is the stall (ownership passed in 98 s on the same runner class). The arm line plus `since_arm` will show which stage consumed the time; add it only if they say so. Recorded as a Taste item. |
| Make T5 primary / T17 healthy / R4 skip-eligible | "skip that arm" | Weakens a supply-chain guard (T5) by an ADR amendment inside a CI-flake fix; fails P6. User-Challenge in `decision-challenges.md`, default = keep hard. |
| Cutover-access wiring and its skip split | none in the incident | Its docker run already has `timeout -k 10 480` plus `docker rm -f`; it is not in the red set. Deferred. |
| `run-registered-suites.sh` comment edit | none | No docker site is added, so "8 invocations from 6 source sites" and "five of the six fail closed" stay true. Cut. |
| 13 per-site `TRACE` lines, `GD_APT_CALL_CAP`, `GD_APT_SITE_BUDGET` fallback, `timeout`/`budget-exhausted`/`apt-error` trio | attribution | The cause line carries `stage`, `elapsed`, `since_arm`; the arm line marks arm time; the suite `.meta` already records seconds. A per-call cap only buys a retry after a stall, which `Acquire::http::Timeout=20` already covers. A silent self-armed fallback would hide a forgotten `-e`. Cut. |
| A `gd_docker_run` wrapper injecting mount and env | per-site wiring | Would shrink the three-part per-site obligation, but the rehearsal's meta-guards read its own `docker run` text (site derivations, heredoc counts); a refactor there is a larger risk than the derived assembly row. Taste item. |
| A per-site (not shared) budget | P3 | 12 serial apt containers in the rehearsal suite: 12 x budget exceeds 600 s for any budget large enough to survive a slow day. A shared deadline makes the worst case independent of site count. Kept the shared form. |

**Files and symbols consulted.** `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (apt loops at
`run_case`, T5 mutation, T17 mutation; S1 `sshd-drive.sh` heredoc; R4 `r4-drive.sh` heredoc; `arm_skip`;
`_T5M_ENV_RCS`, `_T17M_ENV_RCS`, `_S1_ENV_RCS` (all `100 125`); the floor at 92; `_SKIP_CEILING=10` and the
`arm_skip` roster guard), `git-data-ownership.test.sh` (runtime arm, `_runtime_skip`, floor 39),
`git-data-cutover-access.test.sh` (read for sibling shape; host-bounded docker run),
`run-registered-suites.sh` (`_SUITE_BOUNDS`, executor writes `.log/.meta/.trow` per suite),
`.github/workflows/infra-validation.yml` (`deploy-script-tests` matrix, `timeout-minutes: 15`).

**Institutional learnings applied.**
`2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md`
(re-derive counts rather than carry them); ADR-188 amendments for #7572 and #7535 (the pattern for making
an arm skip-eligible and what that costs); ADR-166 / AP-021 (offer a classification, never assert a cause
that was not measured: the cause line says `timeout` only when elapsed time proves it).

**Artifact evidence.** Run 36885018496 `infra-suite-logs-0`: rehearsal `.meta` `124 600 7`, `.log` empty;
ownership `.meta` `0 98 0`, PASS. Run 36880585583: ownership `.meta` `124 300 0`, log ends at S9c.
Last green main run 36846969994 pre-dates the incident. Healthy cost per the earlier plan:
88-123 s for the whole rehearsal step, ~7 s per container.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly. The change is confined to CI test
harnesses under `apps/web-platform/infra/`; no product runtime, no host configuration and no shipped
cloud-init payload changes. The failure mode is a developer-facing one: a red or falsely green infra gate.

**If this leaks, the user's data is exposed via:** no user data is touched. The one confidentiality
property in scope is the existing credential scrub on apt error tails (apt text can embed
`user:pass@host` behind an authenticated proxy); the helper must carry that scrub verbatim and a unit row
asserts it.

**Brand-survival threshold:** none

threshold: none, reason: the diff touches CI test harness files under `apps/web-platform/infra/`
(a sensitive-path prefix) but changes only test-time apt timing and skip routing; it ships no host,
secret, or product-runtime change, and the guards it touches stay hard for every primary arm.

## Open Code-Review Overlap

None. Checked `gh issue list --label code-review --state open` (two-stage `jq --arg`) against every file in
Files to Edit and Files to Create; no open code-review issue names any of them. Related but not
code-review-labelled: #8856 (skip-persistence monitor) and #7672 (its streak-cache follow-through) are the
existing observers of the skip this change makes more reachable; acknowledged, not folded in.

## Decisions

- **D1. One shared helper, not six edits.** Six in-container sites repeat the same cycle with different retry
  counts (5, 5, 5, 5, 3, none). Drift between copies is how #8744 left the time dimension unbounded
  at some and not others. One sourced file defines the budget once and can be unit-tested on the host with a
  stubbed `apt-get`, no docker.
- **D2. Skip routing follows ADR-188's ownership axis, and stops short of the primaries.**
  Skip-eligible rehearsal arms already route rc 100 to `arm_skip` (all three env-rc allowlists are
  `100 125`); the helper returns 100 on a timeout so they need no change. Ownership gets a counted declared
  skip only when the container's `FIXTURE_APT_CAUSE` says `timeout` (a deterministic apt error such as a
  renamed package must stay a CI failure, or Guard 3's runtime rows R1-R10 would be skipped forever behind a
  green check); docker absent and rc 125 stay CI failures. The skip adds exactly `RUNTIME_ROWS` (10) to
  `SKIPPED` with no `fail()` and prints a `::warning::` annotation so the decline is visible on the PR check,
  not only in a log artifact. T5 primary, T17 healthy and R4 remain hard: they fail fast with a named cause
  instead of being killed. The honest consequence: during a SUSTAINED archive outage the rehearsal leg can
  still be red, but in minutes, attributable, and without starving the other suites on the leg. Whether to
  widen eligibility is a User-Challenge, not decided here.
- **D3. Shared deadline, armed lazily.** The host arms `GD_APT_DEADLINE` (absolute epoch seconds) once, at
  the first docker site, so earlier non-docker work does not burn it, and passes it to every container with
  `-e GD_APT_DEADLINE`. Later containers after expiry fail fast (no apt call) with the same marker. The
  budget is wall-clock since arming, so it also covers non-apt container time; the numbers are calibrated in
  Phase 4 rather than assumed.
- **D4. Return-code policy: timeout maps to 100, apt's own rc is preserved, and call sites pass it through.**
  Mapping every non-zero to 100 is the defect the S1 driver comment documents (an OOM-killed 137 would
  become a green skip). The helper classifies a timeout only when `timeout` fired (rc 124, or rc 137 after
  its `-k` kill, AND elapsed >= allotted; an OOM kill landing exactly at expiry is misread, negligible);
  anything else returns apt's own rc. Loop sites use `|| exit $?` (not `|| exit 100`), which is stricter than
  today at the three `bash -c` sites (a 137 there is now a harness-defect FAIL, as it already is at S1).
- **D5. Sourcing failure is a harness defect, never the environment decline.** `. /work/apt-bounded.sh` is
  its own statement with `|| exit 97` (R4: `|| fixture_fail`), never part of an `&&` chain that ends in
  `|| exit 100`; 100 is in every classifier's environment allowlist and would launder a missing mount into a
  green skip. An unset `GD_APT_DEADLINE` is the same class (`: "${GD_APT_DEADLINE:?}"` exits non-zero), so
  there is no silent self-armed fallback that would hide a forgotten `-e`.
- **D6. S1 and R4 gain the retry loop** they lack today (S1 bare; R4 `Retries=3` only). Intended: they share
  the budget, so the extra attempts cannot extend the worst case.

## Files to Create

- `apps/web-platform/infra/lib/apt-bounded.sh` — sourced, not executed. Two halves: host
  `gd_apt_deadline_arm <seconds>` (idempotent; honours `GD_APT_SUITE_BUDGET` as an override used only by
  the Phase 4 reproduction; prints one `GD_APT: armed ...` stderr line) and container
  `gd_apt_install_bounded <pkg>...` plus the credential scrub. Helper discipline: explicit rc capture in the
  `else` branch (`$?` after `fi` is 0), `return` not `exit`, no shell-option changes (callers run it under
  `||`, where errexit is suppressed, and R4 runs `set -uo pipefail` without `-e`). `lib/` already holds the
  non-test `mutation-scorer.sh`, so the registered-suites glob (`*.test.sh`) does not pick it up.
- `apps/web-platform/infra/apt-bounded.test.sh` — host-only unit suite (stub `apt-get` on `PATH`, real
  `timeout`), auto-registered by presence. About 8 behavior rows plus ONE derived assembly row. Carries its
  own anti-vacuity floor emitted by `printf` + `exit 1`, never through `pass()`/`fail()` (ADR-193).
- `knowledge-base/project/specs/feat-one-shot-9379-git-data-apt-timeout/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9379-git-data-apt-timeout/decision-challenges.md`

## Files to Edit

- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — replace the in-container apt blocks at the
  three `bash -c` loop sites (`run_case`, T5 mutation, T17 mutation), the S1 `sshd-drive.sh` apt lines and
  the R4 `r4-drive.sh` apt lines with the two-statement helper call (D5); add
  `-v <lib>:/work/apt-bounded.sh:ro` and `-e GD_APT_DEADLINE` to the five docker sites that run apt
  (`run_case`, T5 mutation, T17 mutation, `_s1_run`, R4); add the lib to EVERY mount-source existence guard
  (the existing three at T5 mutation, T17 mutation and `_s1_run`, plus a new one for `run_case` and R4, which
  have none) so a missing lib cannot be misread as docker rc 125. R4 keeps its
  `GIT_DATA_REHEARSAL_INJECT` lines (`apt-update`, `apt-install`) ahead of the helper call, and S1 keeps its
  `FIXTURE-FAIL` message lines. No assertion is added or removed in this file, so the floor (92), the
  `arm_skip` stanza and `_SKIP_CEILING` are untouched by design; the work phase re-derives that by running
  the suite (see Phase 0 item 3).
- `apps/web-platform/infra/git-data-ownership.test.sh` — helper call in `drive.sh`, mount + `-e`, and split
  the `elif ... FIXTURE_APT_FAILED ... || DRC = 125` branch into two: a timeout-caused apt decline goes to
  `_apt_decline` (adds `RUNTIME_ROWS` to `SKIPPED`, no `fail()`, `::warning::` annotation); rc 125 and an
  apt-error cause stay on the CI-failing `_runtime_skip` / `fail`. Floor 39 (`-lt`) is met because declared
  skips count toward it.
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`
  — append `## Amendment — 2026-10-01 (#9379)`: the time dimension of the apt decline, the shared
  deadline, and the ownership axis applied to the ownership runtime arm on a timeout cause.

## Implementation Phases

### Phase 0 — Evidence capture (read-only)

1. Re-run the artifact listing for run 36885018496 and the next failing run on this branch and record, for
   the rehearsal and ownership suites, `.meta` rc/seconds. These are existing CI artifacts; no dispatch.
2. Derive, do not carry, the numbers the budgets rest on: the in-container apt site count
   (`grep -nE '^[[:space:]]*(if )?apt-get (update|install)'` over the two suites, comments excluded) and the
   worst-case serial container count in the rehearsal suite when every apt cycle fails (12 apt-bearing
   container invocations expected: 2 `run_case`, T5 mutation, T17 mutation, 7 `_s1_run`, R4; R1's docker
   run has no apt).
3. Re-derive the total declared-skip cost on a total stall. The `^arm_skip` call-site grep sees 5 sites, but
   four `did-not-run) arm_skip ...` arms (S1 G6 mutation, three S2 arms) are invisible to it; summed they may
   exceed `_SKIP_CEILING=10`, in which case a total stall adds a second, spurious "skip ceiling exceeded"
   FAIL. Measure it in Phase 4. If it fires, raising the ceiling is an itemised stanza edit in the rehearsal
   suite and is done there, not assumed.

### Phase 1 — RED: the host unit suite (`cq-write-failing-tests-before`)

Write `apt-bounded.test.sh` first, against a helper that does not exist yet; every row must be seen RED.
Stub `apt-get` modes via env: `ok`, `fail`, `hang` (sleep 300, spawn a child `sleep` to prove group kill),
`slow` (sleep N then succeed), `fail-then-ok`, `oom` (exit 137 immediately). Use `GD_APT_DEADLINE` values of
a few seconds so the suite stays fast. Rows: healthy; hang bounded + no orphan + last stderr line exactly
`FIXTURE_APT_FAILED`; pre-expired deadline invokes no apt; fail-then-ok; slow within budget; oom keeps its
rc; credential scrub; unset deadline is a loud non-zero, not a silent fallback.

### Phase 2 — GREEN: the helper

`gd_apt_install_bounded`:

- remaining = `GD_APT_DEADLINE - now`; `: "${GD_APT_DEADLINE:?}"` (no fallback, D5); if remaining <= 0,
  make no apt call.
- each attempt runs the whole cycle under ONE `timeout -k 5 <remaining> bash -c 'apt-get update ... &&
  apt-get install ...'` with `-o Acquire::Retries=5 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20`,
  output appended to `/tmp/apt-fixture.log`. One timeout per attempt removes the per-call cap, the clamp
  arithmetic and the AND-OR `set -e` hazard (the `&&` is the final status inside the `bash -c`). Up to 3
  attempts, backoff 10 s / 30 s clamped to the remaining budget. After a timeout kill, run
  `dpkg --configure -a` (under a short `timeout`) before the next attempt: a kill mid-dpkg leaves "dpkg was
  interrupted" state that would fail attempts 2 and 3 for a different reason.
- on exhaustion: the 20-line credential-scrubbed tail (the two existing `sed` expressions, verbatim), then
  `FIXTURE_APT_CAUSE: <timeout|apt-error> stage=<update|install> attempt=N elapsed=Ss since_arm=Ts rc=R`
  (`since_arm` shows whether this site consumed the budget or inherited an expired one), then the bare
  `FIXTURE_APT_FAILED` line; all on stderr (docker demuxes streams, so the marker must share the stream of
  the diagnostics it follows). Return 100 for `timeout` (including a budget already expired), apt's own rc
  otherwise.

### Phase 3 — Wire the two suites

Replace each in-container apt block with two statements: `. /work/apt-bounded.sh || exit 97`, then
`gd_apt_install_bounded <pkgs> || exit $?` (R4: `|| fixture_fail ...` for both; S1 re-raises the rc). Add the
mount, `-e GD_APT_DEADLINE`, and the existence-guard entry. Arm with `gd_apt_deadline_arm` at the first
docker site (lazy): 300 in the rehearsal suite (12 apt containers, bound 600) and 150 in ownership (bound
300). These are constants set once in each suite; calibrate them from the Phase 4 measurement of the apt
share of a healthy run (the 98 s degraded ownership pass leaves 150 s only ~1.5x of headroom). Apply the
ownership skip split.

### Phase 4 — Real-docker stall reproduction (verification, not committed)

A throwaway `docker` shim earlier on `PATH`: for `docker run` it rewrites argv to insert
`-e http_proxy=http://192.0.2.1:3128` (TEST-NET-1, unroutable, so connections hang) immediately after the
`run` subcommand and execs the real docker; `GD_APT_SUITE_BUDGET=<n>` (host env) shortens the arm for a quick
pass, then one run at the real budgets. Record before/after wall-clock for each suite under `CI=true`:

- ownership: expected exit 0 with `SKIP runtime arm` and the `::warning::` line, total at most the 150 s
  budget plus the static arm and rows (before: hangs past 300 s).
- rehearsal: expected a bounded run ending in its own verdict (named failures for T5 primary / T17 healthy /
  R4, declared skips for the eligible arms), total about the 300 s budget plus non-apt container time (state
  the measured number), below 600 s with margin, never rc=124; record whether the skip ceiling fires
  (Phase 0 item 3).
- a healthy real-network run, recording each container's apt elapsed, to calibrate the budgets and to show
  the slow-day claim P4 beyond the stub.

Paste the measured numbers into the PR body. This is the command that measures the claim "a stall now
costs at most the budget"; the saving is a bound, not a speed-up, and is stated as such.

### Phase 5 — ADR amendment and verification

ADR-188 amendment; run the two edited suites plus `apt-bounded.test.sh`,
`git-data-render-strip-parity.test.sh`, `scripts/guard-vacuity-floor.test.sh`, and
`bash apps/web-platform/infra/run-registered-suites.sh --list` to confirm the new suite is derived. Re-derive
and paste the rehearsal totals; do not rely on the floor staying at 92 by memory.

## Guard Contract

### Guard 1 — apt wall-clock bound and declared-decline routing

**Property.** No in-container apt cycle in the two incident suites can outlive the suite's shared apt
deadline by more than the kill grace, and when it expires the container exits with the same marker and rc an
apt exhaustion produces today, while a non-timeout apt failure keeps its own rc and a missing or unsourceable
helper is never classed as the environment decline.

**Assembly.** The property quantifies over every in-container apt invocation in
`git-data-ownership.test.sh` (`drive.sh`) and `git-data-runcmd-rehearsal.test.sh` (`run_case`, T5 mutation and
T17 mutation `bash -c` blocks, the S1 `sshd-drive.sh` heredoc, the R4 `r4-drive.sh` heredoc). The chokepoint
is `gd_apt_install_bounded`. The assembly row is derived, not listed: in each of the two files the number of
non-comment `docker run` sites that mount `apt-bounded.sh` equals the number that pass `GD_APT_DEADLINE`, and
no line carries a raw `apt-get update|install` in command position (anchored on command position, so the R4
`INJECT` test lines and `fixture_fail` message strings are not matched).

**Mutation matrix.**

| # | Edit (must drive RED) | Targets |
|---|---|---|
| 1 | Delete the `timeout` wrapper in the helper | the bound: the hang row exceeds budget |
| 2 | Compute remaining once before the loop instead of per attempt | shared deadline: the pre-expired-deadline row invokes apt |
| 3 | Map every non-zero apt rc to 100 | P5: the `oom` row (rc 137, elapsed ~0) must NOT return 100 |
| 4 | Drop the credential scrub `sed` | confidentiality row (proxy credentials in the log) |
| 5 | Move the marker line before the diagnostics | order row: last stderr line is exactly `FIXTURE_APT_FAILED` |
| 6 | Return after the first failed attempt | retry row: `fail-then-ok` reaches rc 0 (a second member after a compliant first) |
| 7 | Neuter the suite's row dispatch so it runs zero rows | the guard's own dispatch: the floor (`printf` + `exit 1`) fires on "0 checked" |

**Harness rows.** Must-PASS inputs that are not the canonical case: `slow` (sleeps within budget, then
succeeds, so the bound cannot reject a slow day) and `fail-then-ok` (retry preserved). The suite-side RED row
is mutation 7.

**Anchor.** No stored value is compared (behavior is measured against the stub). The per-suite budgets
(300 / 150) are constants whose adequacy is a Phase 4 measurement against the `_SUITE_BOUNDS` literals,
recorded in the PR body, not a cross-file parse inside the unit suite.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-188 (status `adopting`; it already carries per-arm amendments for #7572 and #7535). New
`## Amendment — 2026-10-01 (#9379)`: (1) the decline's TIME bound: a shared apt deadline, expiry = exit 100 +
marker, no new rc; (2) the ownership axis applied to one more runtime arm (ownership: a timeout-caused apt
exhaustion becomes a counted declared skip; docker absent, rc 125 and an apt error stay CI failures); (3) T5
primary, T17 healthy and R4 are explicitly not widened. Added to `## Alternatives Considered`: raise the
suite bounds (rejected), per-site budget (rejected on the 12-container arithmetic), primary-arm eligibility
(not taken; User-Challenge). No new ADR ordinal is claimed, so no ordinal collision is possible.

### C4 views

No C4 impact. Checked against all three of `model.c4`, `views.c4`, `spec.c4` (read, not keyword-grepped):
external human actors, none added; external systems and vendors touched are the Ubuntu apt archive and the
Docker image registry as consumed by a CI job, and neither is modeled today (the only matching tokens are the
unrelated ghcr/zot registry elements and an "archive" substring in a notifications store description); no
container or data store is touched; no actor-to-surface access relationship changes. Derived cardinalities
embedded in edge prose are not affected (no monitor, workflow, or heartbeat count moves);
`plugins/soleur/test/c4-count-parity.test.sh` is run in Phase 5 as the evidence rather than reasoning.

### Sequencing

The amendment describes the target state and ships in this PR.

## Observability

```yaml
liveness_signal:
  what: "Each git-data suite's terminal summary line and its per-suite .meta rc/seconds in the infra-suite-logs artifact; every apt decline additionally prints FIXTURE_APT_CAUSE then FIXTURE_APT_FAILED"
  cadence: "every pull request and every push to main (Infra Validation deploy-script-tests)"
  alert_target: "Infra Validation main-failure notification job (infra-validation.yml, the notify job on a red main run) and the rehearsal skip-persistence monitor #8856 for the skip-eligible arms"
  configured_in: ".github/workflows/infra-validation.yml; scripts/followthroughs/t5-skip-persistence-bound-7510.sh"
error_reporting:
  destination: "the suite log (stderr) preserved as infra-suite-logs-<leg> and the PR check annotation; no Sentry, because this is test-time code with no runtime process"
  fail_loud: "a budget expiry cannot pass silently: skip-eligible arms print SKIP (loud) and add to Skipped: N with a NOTE; primary arms print FAIL with the cause line; the ownership decline prints a ::warning:: annotation that Guard 3's runtime rows did not adjudicate"
failure_modes:
  - mode: "archive stalls for the whole budget"
    detection: "FIXTURE_APT_CAUSE: timeout in the container stdout captured by the suite, echoed in the SKIP or FAIL detail"
    alert_route: "suite log artifact; ::warning:: annotation on the PR check for the ownership decline; #8856 monitor for T5/S1/T17 skips"
  - mode: "a docker site forgets to pass GD_APT_DEADLINE or mount the lib"
    detection: "an unset deadline exits non-zero at once (no fallback) and apt-bounded.test.sh's derived assembly row fails at PR time"
    alert_route: "PR check"
  - mode: "stall is in the image pull, not apt"
    detection: "the arm line's timestamp versus the first cause line's since_arm shows time spent before apt ran; rc 125 or an untouched deadline"
    alert_route: "suite log artifact"
logs:
  where: "per-suite .log/.meta/.trow under the infra-suite-logs-<leg> artifact (run-registered-suites.sh executor)"
  retention: "GitHub Actions artifact retention for the workflow (default)"
discoverability_test:
  command: "grep -n FIXTURE_APT_CAUSE apps/web-platform/infra/lib/apt-bounded.sh"
  expected_output: "FIXTURE_APT_CAUSE"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash apps/web-platform/infra/apt-bounded.test.sh` exits 0 and prints its own terminal summary with a
      floor; every row of the Guard Contract matrix was observed RED against a mutated helper or suite copy
      (the PR body lists the seven rows and their observed RED).
- [ ] The two edited suites exit 0 locally with docker available:
      `bash apps/web-platform/infra/git-data-ownership.test.sh` and
      `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`; the rehearsal terminal line's total
      equals the pre-change total (assertions neither added nor removed), re-derived from a run of the
      as-written file.
- [ ] Phase 4 stall reproduction recorded in the PR body with measured seconds: ownership ends in a declared
      skip, rehearsal ends in its own verdict, both below their `_SUITE_BOUNDS` entry minus 120 s, neither
      with `rc=124`; the skip-ceiling question (Phase 0 item 3) is answered with the measured number.
- [ ] No raw in-container apt call remains in command position:
      `grep -nE '^[[:space:]]*(if[[:space:]]+)?(timeout[[:space:]]+[^[:space:]]+[[:space:]]+)?apt-get[[:space:]]+(update|install)' apps/web-platform/infra/git-data-ownership.test.sh apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`
      prints no line, and the dispatch is non-vacuous: the count of non-comment lines matching
      `gd_apt_install_bounded` over those two files equals the 6 sites (ownership 1, rehearsal 5), derived by
      the same grep in the unit suite's assembly row.
- [ ] The helper never maps a non-timeout rc to 100 (Guard row 3 / `oom` stub), and a missing lib exits 97
      (not 100) at a loop site.
- [ ] `git diff --name-only origin/main...HEAD` contains only paths under
      `apps/web-platform/infra/` and `knowledge-base/`; no `.tf`, `.github/workflows/`, ruleset, or
      cloud-init file.
- [ ] ADR-188 amendment present: `grep -n 'Amendment — 2026-10-01' knowledge-base/engineering/architecture/decisions/ADR-188-*.md` prints one line.
- [ ] `bash apps/web-platform/infra/run-registered-suites.sh --list` lists `apt-bounded.test.sh`.
- [ ] `bash scripts/guard-vacuity-floor.test.sh`, `git-data-render-strip-parity.test.sh` and
      `plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] The three Deferrals are filed as three separate GitHub issues and linked in the PR body.

### Post-merge (agent-verified, a read-only `gh run` query; no dispatch)

- [ ] The next `main` Infra Validation run shows `deploy-script-tests (1/4)` concluding with neither suite at
      `rc=124` (read the leg's `.meta` from the `infra-suite-logs` artifact).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to CI test harnesses.

## Test Scenarios

1. Healthy archive: helper returns 0, update then install each invoked once with the timeout options.
2. Archive hangs: stub sleeps past the budget; helper returns 100 within budget plus kill grace; no orphan
   child process remains; last stderr line is exactly `FIXTURE_APT_FAILED`.
3. Deadline already passed (a prior container consumed it): helper returns 100 without invoking apt.
4. Transient failure then success: returns 0 (retry kept).
5. Slow but within budget: returns 0.
6. OOM-kill shape (rc 137, near-zero elapsed): returns 137, not 100.
7. Credentials in the apt log: absent from the emitted tail.
8. `GD_APT_DEADLINE` unset: non-zero exit, no apt call.
9. Ownership suite under `CI=true` with a stalled archive: declared skip, exit 0, floor still met; with a
   deterministic apt error instead: CI failure.
10. Rehearsal suite with a stalled archive: skip-eligible arms print `SKIP (loud)`, primary arms print
    `FAIL` with the cause line, run ends before 600 s.

## Risks and Sharp Edges

- **The rehearsal suite carries meta-guards that read its own text** (roster of `arm_skip` call sites,
  heredoc-aware trap counting, docker-site derivations, the floor, `_SKIP_CEILING`). The edit replaces text
  inside heredocs and `bash -c` blocks; run the whole suite after each site, not once at the end.
- **A budget too small turns a slow day into a failure for the primary arms.** The rehearsal budget (300 s)
  is about 2.5x the slowest measured healthy whole-step time (123 s) and the ownership budget (150 s) is
  above the 98 s degraded pass; the apt-only share of those figures is unmeasured, which is why Phase 4
  records it before the constants are final.
- **A shared wall-clock deadline also counts non-apt container time and image pulls.** A slow earlier
  container can leave a later primary arm with an expired budget. This is the intended trade (it keeps the
  worst case independent of site count); `since_arm` in the cause line makes it diagnosable.
- **`timeout` kills the process group; a kill mid-dpkg leaves interrupted state.** The helper runs
  `dpkg --configure -a` after a timeout kill; the `hang` stub spawns a child to prove no orphan survives.
- **The decline is more reachable after this change** (ownership skips under CI on a timeout; rehearsal
  skip-eligible arms skip instead of being killed). Persistence of the ownership decline is observed only by
  the `::warning::` annotation; extending the #8856 probe to it is deferred (c).
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6; this one declares `none` with a scope-out reason.
- Do not add counted assertions to the rehearsal suite to cover the new wiring; put them in
  `apt-bounded.test.sh`. A new assertion there moves a floor that three PRs in four days have already
  mis-derived.

## Deferrals (three separate issues, filed at work time, milestone from `knowledge-base/product/roadmap.md`)

- (a) Whether T5 primary / T17 healthy / R4 become skip-eligible (ADR-188 amendment); re-evaluate if a
  sustained archive outage keeps the rehearsal leg red. Re-evaluation trigger: the #8856 probe reporting a
  skip streak, or two consecutive main runs red on a primary-arm apt cause line.
- (b) The unbounded apt loop in `cloud-init-inngest-provision-unit.test.sh` Tier B (own bound 540 s, no
  incident) and in `git-data-cutover-access.test.sh` (docker run already host-bounded at 480 s; its
  `_runtime_skip` is CI-failing and its floor is exact, so any change needs its own accounting).
- (c) Extend the skip-persistence probe to the ownership `SKIP runtime arm` line.
