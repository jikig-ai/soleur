---
title: "fix: git-data-runcmd-rehearsal T5 mutation arm reports 'vacuous' when the mutant never executed"
date: 2026-08-12
slug: fix-t5-mutation-arm-network-flake
branch: feat-one-shot-7291-t5-mutation-network-flake
issue: 7291
closes: 7291
lane: cross-domain
type: bug
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# fix: the T5 mutation arm reports "vacuous" when the mutant never executed

## Enhancement Summary

**Deepened on:** 2026-08-12 · **Passes:** 6-agent plan review, then a verify-the-negative sweep and
a precedent-diff sweep.

### Key improvements

1. **Scope cut by roughly two thirds.** Plan v1's suite-wide container-setup refactor was removed
   after the simplification and correctness panels both fired on it; the retry it contained was
   replaced by a deferred image pre-bake, which measurement showed to be the better remedy.
2. **A prior-art miss corrected.** ADR-177, ADR-181 and AP-021/ADR-166 already govern multi-valued
   test verdicts. The ADR is reframed from standalone to `amends: ADR-181`. (At review the "reversal" framing was
   corrected to a second carve-out, and its axis from computability to contractual ownership.)
3. **Three false claims of my own found and fixed** — sibling-suite count, skip-counter precedent,
   and ADR coverage. All three are recorded rather than quietly corrected.
4. **Four hard-failure states routed** that v1 named in prose and never gave a verdict.

### Gate record (deepen-plan halts)

| Gate | Outcome |
|---|---|
| 4.5 Network-outage | **Evaluated, non-trigger.** The keyword scan matches 4 times, all substring false positives: ADR-181's quoted word "UNREACHABLE" (×2) and the `/run/sshd` directory path in the deferred pre-bake note (×2). No network-connectivity symptom is diagnosed — the CI container's apt fetch is a dependency, not a diagnosis subject, and the plan explicitly defers rather than diagnoses it. |
| 4.55 Downtime & cutover | Skipped — no serving surface, no reboot/replace, no lock-taking DDL. |
| 4.6 User-Brand Impact | Pass — section present, threshold `aggregate pattern`, no placeholders. |
| 4.7 Observability | **HALTED on the first run** — `error_reporting` was missing from the v2 rewrite. Added; all five fields now present, no placeholders, probe verb `bash` is allowlisted. |
| 4.8 PAT-shaped variable | Pass — no matches. |
| 4.9 UI wireframe | Skipped — no UI-surface file in Files to Edit/Create. |
| 4.10 Encryption posture | Skipped — no persistent store, no new cross-component connection. |
| 4.11 Guard Contract | Pass — `lint-guard-contract.py` green; adequacy read confirms the Assembly names a chokepoint (not a member snapshot) and explicitly names the two out-of-scope invokers, and the matrix carries an own-dispatch row and a second-member row. |

### New considerations discovered at deepen time

- **rc-discard is a four-member class, not a one-off.** 4 of 6 `docker run` invocations end `|| true`.
  Deferred deliberately rather than swept, and recorded so the class is not mistaken for closed.
- Every other load-bearing structural claim in the plan was re-verified independently and confirmed
  (15-claim sweep; see Verified environment facts).

## Overview

`apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` carries an anti-vacuity arm for T5. T5
asserts that a wrong `DOPPLER_SHA256` aborts the runcmd chain before `tar`/`chmod`, and proves that
assertion is not vacuous by re-running the case with the driver's `set -e` neutered: with errexit
gone the chain must continue and print `CHMOD_RAN`. When `CHMOD_RAN` is absent, the arm reports

```
FAIL: T5 MUTATION: without set -e the chain still did not reach chmod — T5's check is vacuous
```

That verdict conflates two states. "The mutant ran and did not reach chmod" is a real finding. "The
mutant never ran at all" is not — it is an absence of evidence, and the arm cannot tell them apart
because it discards the container's exit code (`|| true`) and reads a single marker.

This plan gives the arm the evidence to discriminate: an execution marker emitted by the driver the
suite itself authors, a captured container exit code, and a counted SKIP verdict reachable only when
that marker's absence is *positively corroborated* rather than assumed. The FAIL direction the arm
exists for is preserved, and every deterministic failure that is not a transient environment failure
stays a hard failure.

**Scope is one arm, deliberately.** Plan v1 also refactored the suite's container-invocation contract
across all six `docker run` sites. Six reviewers converged on cutting it; the retry and the
image pre-bake are deferred with named re-evaluation criteria. See `## Plan Review Revisions`.

## Research Reconciliation — Issue Premise vs. Measured Reality

| Issue claim | Measured reality | Plan response |
|---|---|---|
| "the chain aborts **earlier** — at curl, not at the checksum — so `CHMOD_RAN` never prints" | **REFUTED.** In the mutant errexit is gone and the instrumentation is `;`-chained (`chmod +x /usr/local/bin/doppler; echo CHMOD_RAN`). Probe A2 ran the block shape in `ubuntu:24.04` with `--network none` and no curl: `tar`/`chmod`/`rm` all errored and **`CHMOD_RAN` still printed**. | The download is not the discriminator. Discriminate on whether the *driver* executed. |
| "serve the tarball from a local fixture for the mutant arm" | Hardens a dependency measurement shows is not failing, and costs T5 the fidelity its comment claims. | **CUT.** |
| "reds a **required check**" | **NOT SUPPORTED.** The suite runs in `deploy-script-tests` in `.github/workflows/infra-validation.yml`. All four live rulesets enumerated via `gh api repos/:owner/:repo/rulesets/<id>`; their 21+2+0+0 required-status-check contexts contain no `deploy-script-tests` and no `infra-validation`. It is a PR check, not merge-blocking. | Keep the fix; right-size the framing. The triage cost is real; "blocks merge" is not. |
| "the driver's own output already distinguishes a download failure from a checksum failure" | Partly false. `curl`'s and `sha256sum`'s stderr both redirect into `$GIT_DATA_RUNCMD_DETAIL` **inside the container**, which the harness never reads back. Only `tar`/`chmod` stderr reaches captured stdout. | The evidence must be *added*, not merely read. |

**A sufficient mechanism WAS measured.** Probe B ran the arm's exact container shape
(`set -e; apt-get update … && apt-get install …; bash /work/drive.sh`) with `--network none`:
**rc=100, stdout empty**. The outer `set -e` aborts on the apt failure, `drive.sh` never runs, no
marker prints, and `|| true` discards the 100. That reproduces the symptom exactly.

**The actual cause of the two observed failures remains UNKNOWN.** The deciding datum was discarded
by `|| true` and is unrecoverable. Probe B shows a setup failure is *sufficient*, not that it was
*actual*. Other sufficient causes are indistinguishable after the fact: the `docker pull` (measured
rc **125**) and the 5-second capture-server poll (`exit 2`, printing `FIXTURE: capture server never
bound :8099`). Per
`knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`
no row reads CONFIRMED — which is why the remedy is evidence plus an honest verdict, and why the
retry and pre-bake are deferred rather than built.

One further datum, load-bearing for the design: in the observed failures the T5 **primary** arm
passed while the **mutation** arm did not execute. Two containers, identical setup, seconds apart,
different outcomes — consistent with a transient hitting one of six independent network windows.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 7291` — `OPEN`, `closedByPullRequestsReferences` empty.
- Target file exists (1453 lines). Issue line hints checked against content anchors: the T5 block
  sits at the `── T5 — a WRONG checksum must ABORT before tar/chmod ──` banner (correct); the floor
  is the `if [ "$total" -lt 44 ]` guard (~45 lines below where the issue pointed, which is where its
  explanatory comment begins).
- Registration confirmed in `.github/workflows/infra-validation.yml`, `deploy-script-tests` job.

### Prior art — corrected after review

**Plan v1 asserted "No ADR records the `_skip()` CI doctrine". That was wrong, and the mechanism of
the error is recorded because it will recur:** the corpus grep used case-sensitive `SKIP` plus
feature nouns, and the governing ADRs use `skip_suite`/`skipped` in lower case. Two independent
reviewers caught it. Verified:

- **ADR-177 — "a terminated suite is UNRESOLVED, not failed."** Establishes a *third* result class
  beside pass/fail in a test runner, on the grounds that a non-executing run rendering identically
  to a failing one trains the reader to discount that suite's failures. This plan's thesis, already
  accepted, one level up.
- **ADR-181 — "local gate declines are counted verdicts."** Frontmatter `amends: ADR-177`. Ships a
  `skip_suite` helper incrementing both the denominator and a `skipped` counter, plus a BREAKDOWN
  summary line. This plan's counter-plus-honest-floor design, already built.
- **AP-021 / ADR-166** (principles register): *"a verdict must never collapse 'could not check' into
  'bad' (the DEAD/UNVERIFIABLE/UNMEASURED distinction calls for different, sometimes opposite,
  operator actions)"*. This is the registered principle the fix applies.

**ADR-181 property 4 is directly contradicted by this plan** and the contradiction must be argued,
not skipped: *"A decline is UNREACHABLE under CI, not merely detected."* ADR-181's reasoning is that
a *relevance* decline is deterministic and therefore always avoidable in CI. A container-setup
failure is neither. That distinction is the ADR's whole burden — see `## Architecture Decision`.

### Property List (Phase 0.6b)

- **P1** — A run in which the T5 mutant could not execute must not be reported as FAIL.
- **P2** — A run in which the mutant did execute and did not reach the chmod marker must still FAIL.
- **P3** — The assertion floor stays honest: a non-executed arm is neither counted as a pass nor
  allowed to silently drop `total` below the floor.
- **P4** — The rate of reddening an unrelated PR goes down for the **observed** failure mode.
  Deliberately not claimed for unobserved modes.
- **P5** — The skip verdict is bounded; a suite that can skip everything and stay green is as
  vacuous as a guard that passes vacuously.
- **P6** — A deterministic, actionable defect (a fixture that cannot bind, a missing capture) stays a
  hard failure and is never absorbed into the skip.

### Cut List

| Mechanism | Property | Disposition |
|---|---|---|
| Download-vs-checksum discrimination *(issue)* | P1 | **CUT** — Probe A2 printed `CHMOD_RAN` with the download fully failed. |
| Local tarball fixture *(issue)* | hermeticity | **CUT** — wrong dependency; costs T5 its fidelity. |
| SKIP-with-reason + honest floor *(issue)* | P1+P3 | **KEPT**, precondition redefined to "the driver executed". |
| Entry sentinel via python transform + landing guard | P1 | **CUT for a simpler mechanism.** The python pass needs `s.count(old) != 1` and a landing guard because it rewrites a *foreign extracted file*. `drive.sh` is a heredoc **the suite authors**, so one `echo` above its `. /work/doppler-dl.sh` buys the same discrimination. |
| Shared setup helper across 6 sites | P4 | **DEFERRED** — see Deferred Scope. Only 3 of 6 share the measured shape. |
| Bounded retry with backoff | P4 | **DEFERRED**, and it would have *destroyed* the frequency evidence: a success on attempt 2 is a green run with no record a retry happened. If it ever lands it must emit `SETUP_RETRIED attempt=N`. |
| Reserved sentinel exit code | P1 for `run_case` | **CUT** — an unmanaged number space (live: 0, 1, 2, 3, 100, 125/126/127) guarded only by prose. |
| Invoker-parity assertion | none | **CUT, and it was red on day one.** `grep -c 'docker run'` returns **8**, not 6 — two occurrences are prose, and one of those already says "four" (stale since the count reached six), which is in-file proof that hand-maintained counts in this file drift undetected. |
| `run_case()` skip-eligibility | P1 elsewhere | **DEFERRED** — in isolation a net regression. See Revisions R4. |
| "At least one container arm executed" floor | P5 | **CUT** — subsumed by the ceiling at one skip-eligible arm, and the evidence it would read is destroyed by each arm's own `rm -rf "$TMP/out"`. |
| `::warning::` CI annotation | none | **CUT** — ADR-181's precedent is a counted BREAKDOWN line, not an annotation; and it sat in doctrinal tension with the `_skip()` block beside it. |
| Pairwise primary/mutant skip gate *(reviewer proposal)* | P5 | **CUT as a gate, ADOPTED as evidence.** Gating SKIP on "the primary arm also failed to execute" would convert the **observed** flake into a FAIL, since the primary passed in both observed cases. The asymmetry is real signal, so it is *reported in the skip reason* rather than used to deny the skip. |

**Existing mechanisms checked against the property list** (`hr-verify-repo-capability-claim-before-assert`):

- `_skip()` implements "a gate that cannot run must not report success". It does **not** buy P1: it
  is whole-suite, pre-flight, and `exit`s.
- **`git-lock-chardevice-sweep.test.sh` already ships a counter idiom** — `SKIPPED=0`,
  `SKIPPED=$((SKIPPED + 1))`, `echo "Skipped: $SKIPPED"`. Plan v1 claimed no sibling maintained a
  skip counter; that was false.
- **`infra-config-apply.test.sh` ships a RICHER precedent, and it is the one this plan follows.**
  Found at deepen time; it is the closer match on every axis this plan needs, and adopting it
  changes the design rather than merely re-citing it:
  - `SKIPPED_ASSERTIONS=0` — **denominated in assertion cost, not in arms.** One skip site
    increments by 4 (`SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 4))`), because that arm would have
    made four assertions. This resolves the ceiling's unit ambiguity outright and is
    forward-compatible with the deferred `run_case()` extension, where a single skipped case
    suppresses several follow-on assertions at once.
  - Each skip site carries a **comment declaring its assertion cost** (`# 1: the single "the lint
    FLAGS the pre-fix handler" assertion the taken branch would make.`), so the number is auditable
    at the site rather than only at the floor.
  - The floor already compares the **sum**: `if [[ $((PASS + SKIPPED_ASSERTIONS)) -lt
    "$APPLY_MIN_ASSERTIONS" ]]` — precisely this plan's `passes + fails + SKIPPED` design, already
    in the repo.
  - It emits a **breakdown NOTE** when any skip fired: `NOTE: $SKIPPED_ASSERTIONS assertion(s) were
    declared-skipped by loud SKIP arms — this run is weaker than a full one.` This is a better
    mechanism than the `::warning::` annotation v1 cut — it is in-repo precedent, carries no
    doctrinal tension with the `_skip()` block, and makes a degraded run legible in the same place
    the counts are read.

  **So the counter, the assertion-cost denomination, the sum-floor and the degraded-run NOTE are all
  pre-existing.** Only the ceiling is new to this plan.
- **`git-data-rung2-rehearsal.test.sh` is a counter-precedent and must be distinguished.** It uses
  the doctrine sentence as a per-arm **failure detail** at two sites (`fail "python3 absent — the
  workflow-contract arms did NOT run" "a gate that cannot run must not report success"`). That is a
  per-arm, mid-run, dependency-shaped verdict that chose FAIL. The distinction: a missing `python3`
  is deterministic and actionable by the runner's provisioning; a transient container-setup failure
  is neither. This is the same line ADR-181 property 4 draws.
- The D1 arm's `pass; pass   # dash absent: keep the cardinality floor honest` buys P3 by **counting
  a non-execution as a pass** — precisely what the issue forbids. A precedent to deliberately not
  follow, with the reason written into the new code's comment.
- `run_case()` already captures the container rc immediately after its `docker run`. The T5 mutation
  arm is a hand-inlined copy that dropped the capture. P1's rc requirement is met by **restoring an
  existing pattern**.

### Corrected factual record (plan v1 errors, verified)

1. v1 claimed four sibling suites replicate the `_skip()` doctrine, naming two that contain **zero**
   `_skip` occurrences. Measured: the doctrine sentence is in **2** files
   (`git-data-runcmd-rehearsal.test.sh`, `git-data-emit.test.sh`); a `_skip()` function is defined in
   **4** (those two plus `tests/scripts/test-zot-inventory.sh` and
   `tests/scripts/test-zot-inventory-assert-marker.sh`).
2. v1 claimed no sibling maintains a skip counter. False — see above.
3. v1 claimed no ADR governs this. False — ADR-177/181/166.

All three were my own unverified claims, in the plan that criticised the issue for exactly that.

### Institutional learnings applied

- `.../2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the
  origin of ADR-180; a guard's window narrower than the property it names.
- `.../2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` — *"'Zero hits' and
  'I queried nothing' are byte-identical outputs."* The arm's exact defect; the execution marker is
  the positive control, and P6 exists because the marker's own absence needs corroboration in turn.
- `.../2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`.
- `.../2026-08-12-i-proved-the-transform-and-left-its-application-and-its-size-unpinned.md` — *"a
  floor number is not a fingerprint of a suite"*; and its other half, *pin the transform's
  application to the artifact that ships* — which is why the marker is asserted on the **mounted**
  `drive.noerrexit.sh`, not on the source heredoc.
- `.../2026-08-05-i-built-a-cadence-on-a-bot-that-never-ran-and-my-battery-certified-the-gate.md` §11
  — the original 4-pass/2-fail measurement that produced #7291.

### Conventions and constraints

- `bash` harness under `set -uo pipefail`, `pass()`/`fail()` counters, hard assertion floor.
- **Two guard classes, only one moves the floor:** counted guards call `pass`/`fail`; structural
  guards hard-exit (`echo "FAIL: …" >&2; exit 1`) and never increment `total`.
- **`#7005` prohibition, documented in-file:** no `head … | grep -q` under `set -uo pipefail` — the
  producer takes SIGPIPE (141), pipefail promotes it, and the guard fails **open** exactly when it
  matches. New greps follow the in-file `$(grep -c … || true)` idiom (`grep -c` returns 1 on zero
  matches, which `set -u` would then turn into an empty-string comparison).
- A function named `skip()` would sit one underscore from `_skip()`, which **exits the whole suite**
  with the opposite meaning. The reporter is named `arm_skip()`; `_skip()` is not renamed.
- `local` is invalid outside a function. The T5 mutation arm is top-level inside a bare `if/else/fi`,
  so the rc capture is a **plain assignment** (`rc=$?` on the line immediately after the redirect) —
  `local` there errors, leaves the variable unset, and the next read trips `set -u` and kills the
  suite mid-run.
- `bunfig.toml`/vitest are irrelevant — invoked as `bash apps/web-platform/infra/…test.sh`.

### Verified environment facts (plan-time probes)

| Probe | Setup | Result |
|---|---|---|
| A2 | Mutant driver, `--network none`, curl absent | `tar`/`chmod`/`rm` error; **`CHMOD_RAN` printed**; rc=1 |
| B | Arm's exact container command, `--network none` | **rc=100, stdout empty**; `drive.sh` never invoked |
| C | `docker run` against a nonexistent image | **rc=125** — distinguishable from 100 |

Structural facts verified by direct read:

- `run_case()` has exactly **two** callers (T5 primary `want=1`, T17 healthy `want=0`). Not "others".
- **Four of the six `docker run` invocations discard their exit code with a trailing `|| true`** — the
  T5 mutation arm, the T17 mutation arm, the R1 mutation arm and R4. Only the two that flow through
  `run_case()` capture rc. A reviewer asserted the T5 arm was the *only* `|| true` site; it is not,
  and the correction matters: it makes rc-discarding a **class** with four members rather than a
  one-off, which is further support for fixing the named instance now and extending deliberately
  (Deferred Scope) rather than claiming the class is closed by this PR.
- The `drive.sh` heredoc ends `. /work/doppler-dl.sh` immediately before its `DRIVE` terminator; the
  `FIXTURE: capture server never bound :8099` guard sits earlier in the same heredoc.
- The **T17 mutation arm discards its container output** (`' >/dev/null 2>&1 || true`).
- `_s1_run()` is a **second** shared invoker (two call sites) deriving its verdict by parsing
  `STAGE_RC=` from stdout.
- Three in-script `docker build` precedents exist (`cloud-init-plugin-seed.test.sh`,
  `inngest-bootstrap-mirror-only.test.sh`, `sandbox-canary-regression.test.sh`) — relevant to the
  deferred pre-bake, whose v1 rejection rationale ("a new image, a new build step, a new registry
  dependency") was false on all three counts.

## Research Reconciliation — Spec vs. Codebase

No spec.md for this branch (entered via `/soleur:one-shot` without a brainstorm). `lane:` defaults to
`cross-domain` fail-closed.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` piped to a
standalone `jq --arg path` containment scan for `git-data-runcmd-rehearsal`: **None.**

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — a CI test harness. The downstream
artifact is the git-data host's supply-chain abort guard. If the SKIP condition is over-widened,
T5's anti-vacuity arm becomes reachable-but-never-asserted, and a future regression letting an
**unverified Doppler tarball be `chmod +x`'d and executed as root** on the host that stores users'
bare git repos would ship with a green suite — the pre-#6982 behaviour the guard prevents returning.

**If this leaks:** no new exposure vector. One test file plus planning artifacts; no secret, no
store, no network surface, no user-reachable code path.

**Brand-survival threshold:** `aggregate pattern` — the blast radius is a *future* regression
shipping undetected, not a single-user incident caused by this PR. No per-PR CPO sign-off required.

## Guard Contract

### Guard 1 — the T5 mutation-arm verdict discriminator

**Property.** The T5 mutation arm reports FAIL when the mutant executed and did not reach the chmod
marker; reports SKIP only when the container's own output positively corroborates that the driver
never ran; and reports PASS only on the marker itself. Every other state — a missing or empty
capture, a fixture that could not bind, a mutation that did not land — remains a hard failure.

**Assembly.** The property quantifies over the **single container-invocation chokepoint** of the T5
mutation arm: the `docker run` whose exit code and combined output land in `$TMP/out/stdout`. Four
signals flow through that one capture and the verdict reads all of them — `CHMOD_RAN`, the execution
marker emitted by the mounted driver, the `FIXTURE:` literal, and the captured exit code.

**Two other invokers exist and are explicitly OUT of scope**, named so the assembly is structural
rather than a snapshot: `run_case()` (2 callers) and `_s1_run()` (2 callers). Both carry a related
exposure; both are deferred, not overlooked. A future PR extending the verdict to them must
re-derive this assembly, because each has follow-on assertions reading the invocation's globals that
would otherwise pass vacuously.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Environment healthy; neuter the sourced block so the driver runs and returns before chmod | **FAIL**, not SKIP. P2 — the SKIP branch cannot swallow a genuine vacuity. |
| 2 | Force container setup to fail with a **bogus package name** (not `--network none`, which would also break the download and conflate two changes) | **SKIP**; `SKIPPED_ASSERTIONS` increments to exactly 1; floor still met. P1. |
| 3 | Delete the execution-marker line, environment healthy | **FAIL.** The marker's absence must not read as non-execution when the run in fact succeeded. Without this row the marker could vanish and every later run would SKIP. |
| 4 | Pre-bind :8099 so the driver exits at the `FIXTURE:` guard | **FAIL**, never SKIP. P6. |
| 5 | Truncate/remove `$TMP/out/stdout` before the verdict evaluates | **FAIL.** A missing measurement is a harness bug, not an environment skip — this is the #7291 defect one level up, and the row that stops the fix relocating the bug. |
| 6 | *(own dispatch)* Delete the skip-ceiling assertion | **RED** — the assertion is **counted**, so removing it drops `total` below the floor. |
| 7 | *(second member)* Add a second `arm_skip` call site without raising the ceiling, then force both | **RED** at the ceiling — proves it counts members rather than stopping at the first. |
| 8 | Restore `set -e` so the mutation does not land | **FAIL** at the arm's existing pre-branch, preserved unchanged. |

**Stated residual, not papered over.** *Raising* the ceiling constant is not mechanically
detectable — any source-level grep asserting its value would be text-matching rather than behaviour,
the antipattern this contract rejects, and the in-file `"four plain docker run"` comment (which was stale since
the real count reached six) is measured proof that hand-maintained numbers here drift silently. The
mitigation is procedural and declared: the ceiling's value and derivation live in the floor's
itemisation comment, where the file's culture already forces review of any count change. Plan v1's
matrix claimed "delete **or raise** ⇒ RED"; the raise half had no failing direction — the ADR-180
defect appearing inside the artifact invoking ADR-180.

## Implementation Phases

### Phase 1 — Capture the deciding datum (probe-first)

1. Add one execution-marker `echo` to the `drive.sh` heredoc, immediately above its
   `. /work/doppler-dl.sh` line and **below** the capture-server guard, so a fixture failure stays
   distinguishable from a setup failure.
2. Assert the marker on the **mounted** artifact `$TMP/drive.noerrexit.sh` (produced by the arm's
   `sed 's/^set -e$/true/'`), not on the source heredoc — pinning the transform's *application*, not
   just its correctness. Structural (hard-exit) class, so the floor does not move.
3. Replace the trailing `|| true` on the arm's `docker run` with a plain `rc=$?` assignment on the
   next line, restoring the pattern `run_case()` already uses. Not `local` — the arm is top-level.
4. Emit the captured rc and the tail of `$TMP/out/stdout` in **every** verdict branch, with the
   measured rc classes named: 125 = docker CLI/image pull, 100 = apt under the container's outer
   `set -e`, 2 = the capture-server guard. Per **AP-021/ADR-166** the message must name only what
   was measured: the verdict is derived from marker absence, so the reason states that and *offers*
   the rc's class rather than asserting a cause the arm did not observe.
5. Record whether the T5 **primary** arm executed (its marker observation, captured into a variable
   before the arm's `rm -rf "$TMP/out"` destroys the evidence) and include it in the skip reason.
   Evidence only — never a gate. See the Cut List entry for why.

### Phase 2 — The counted verdict, and an honest floor

1. Add a `SKIPPED_ASSERTIONS` counter (renamed from the plan's original `SKIPPED` at review — see
   AC7) and an `arm_skip()` reporter alongside `pass()`/`fail()`, following
   `git-lock-chardevice-sweep.test.sh`'s existing idiom (uppercase counter, `Skipped: N` in the
   summary) and ADR-181's counted-verdict vocabulary rather than minting a third taxonomy.
2. Add the capture-integrity precondition **before** the verdict branch: a missing or empty
   `$TMP/out/stdout` with rc 0 is a harness defect — hard `fail`, never skip (Guard row 5).
3. Rewrite the verdict as an ordered branch. The order is load-bearing and must be commented:
   - `CHMOD_RAN` present ⇒ `pass`.
   - `FIXTURE:` literal present ⇒ `fail` (deterministic, actionable — P6, row 4).
   - execution marker absent ⇒ `arm_skip` with rc, rc-class, and the primary-arm asymmetry note.
   - otherwise ⇒ `fail`, message extended to state the driver *did* run.
   Testing the marker before `CHMOD_RAN` would skip a slow-but-successful run; before `FIXTURE:` it
   would absorb a fixture defect.
4. Change the floor's total to `passes + fails + SKIPPED`.
5. Add the ceiling as a **counted** assertion (`SKIPPED <= 1`, one skip-eligible arm), derivation in
   a comment — Guard row 6 depends on it being counted.
6. Raise the floor by **+1** for that one counted assertion (44 → 45 as planned; rebased to 46 → 47
   after #7501 raised the base mid-flight), with a `RAISED` stanza in the
   file's existing itemisation style. Nothing else in Phases 1-2 is counted: the marker guard and the
   capture-integrity precondition are structural, and the verdict branch re-shapes the arm's single
   existing assertion.
7. Extend the summary line to report `Skipped: N`. **The resolved-suite-path half was CUT at
   review (AC11)** — each summary line already opens with its own suite name, so the claimed
   44-vs-44 ambiguity never existed, and after this PR the floors differ (44 vs 45) as well.
8. **Amend the B5 doctrine comment in the same edit.** The `_skip()` banner asserts a two-valued
   world and becomes self-contradictory the moment `arm_skip()` lands. This file's culture treats a
   comment that no longer describes the code as a defect; the amended block states the three
   mechanical conditions and cites the ADR.

### Phase 3 — Prove the mutation matrix

Execute all eight Guard 1 rows against the real suite and record the observed verdict. Rows are
driven by temporary local edits, reverted before commit.

## Deferred Scope

Each was cut at review, not overlooked. Per `wg-when-deferring-a-capability-create-a` each gets a
tracking issue with its re-evaluation criterion.

| Deferred | Why | Re-evaluation criterion |
|---|---|---|
| **rc-discard in the other three arms** (`|| true` on the T17 mutation, R1 mutation and R4 `docker run`s) | Measured at deepen time: 4 of 6 invocations discard rc, so this is a four-member class, not a one-off. Fixing the three unnamed members here would repeat plan v1's error of building past the evidence. | Ship with the `run_case`/`_s1_run` verdict extension, which needs the same skip-propagation work. |
| **Pre-bake the container image** (preferred over retry) | Attacks the measured sufficient cause with more leverage than a retry: collapses 6 apt transactions to 1 and makes the *healthy* path faster, where a retry makes the *degraded* path slower. v1's rejection ("new image / new build step / new registry dependency") was false on all three counts — three in-script `docker build` precedents exist, none pushes to a registry, none touches the workflow. | The first post-merge SKIP. Must carry a `[ ! -d /run/sshd ]` in-arm assertion: S1's finding depends on that directory not existing at runcmd time, and installing `openssh-server` at build time changes when it could appear. |
| Bounded retry on container setup | Built against a cause measurement showed sufficient but never actual — and it would convert the most likely occurrence class from visible to invisible, destroying the frequency signal Phase 1 exists to collect. | Only if pre-bake lands and the flake persists. Must emit `SETUP_RETRIED attempt=N` counted and surfaced. |
| Skip verdict for `run_case()` and `_s1_run()` | In isolation a **net regression** — see Revisions R4. | Ship with per-caller skip propagation for every follow-on assertion, ceiling denominated in assertions not arms. |
| Giving the T17 mutation arm a stdout capture | It discards output entirely, so it cannot participate in any marker scheme. | Prerequisite for extending the verdict beyond T5. |
| **P4 persistence bound** | The three mechanical conditions bound a skip *per run*; nothing bounds it *across* runs. An arm skipping on 100% of runs forever satisfies all three. ADR-181 paired its decline with a compensating un-gated run every 6h; this plan has no analogue. | Observation window: if the arm SKIPs on more than 1 in 20 post-merge runs, the skip is masking a persistent defect and the pre-bake is owed immediately. |

## Architecture Decision (ADR/C4)

### ADR — ADR-188, amending ADR-181

**Create `ADR-188`, frontmatter `amends: ADR-181`, `related_adrs: [ADR-177, ADR-180, ADR-166]`**,
matching the convention ADR-181/182/184 already use. Plan v1 proposed a standalone ADR on the
premise that no ADR governed the area; that premise was false, and a third independently-derived
verdict taxonomy is exactly the divergence an ADR should prevent.

The ADR's burden is **one argued reversal**: ADR-181 property 4 holds that *"a decline is
UNREACHABLE under CI, not merely detected"*, reasoning that a *relevance* decline is deterministic
and therefore always avoidable in CI. This plan makes a decline reachable under CI. The distinction
to argue: a relevance decline is a property of the diff and is always computable; a container-setup
failure is a property of the network at that instant and is not. The ADR must also reconcile with
**AP-021/ADR-166** (a message may only name a cause the job measured) and record the
`git-data-rung2-rehearsal.test.sh` per-arm-FAIL counter-precedent with the deterministic-vs-transient
line that distinguishes it.

**Ordinal history — the provisional check fired, as designed.** At plan time `ADR-186` was verified
free across all 67 `origin/*` refs (max observed ADR-185). By implementation time it was **taken**:
`ADR-186-infra-config-gate-freshness-depends-on-whether-a-push-was-expected.md` merged to
`origin/main` in the interim, and `ADR-187` had also landed on a ref. Re-derived against freshly
fetched refs, `ADR-188` is free and is the ordinal this plan ships; the rename plus every reference
in the suite, this plan and `decision-challenges.md` were swept in one edit.

References carrying `ADR-186` in the `feat-one-shot-7104-apply-verify-repost-recovery` plan and
tasks are a **different** feature's ADR and were deliberately left untouched — a blanket
find-and-replace across the repo would have rewritten another session's record.

Re-derive again immediately before merge: this ordinal is provisional for exactly the reason above,
and the re-derivation must run against fetched refs, never a local `ls` (the local corpus lags
origin).

### C4 views

**No C4 impact.** All three model files read in full; the enumeration the completeness mandate
requires:

- **(a) External human actors** — the model declares `founder`, `emailSender`, `betaContact`,
  `contributor`. Only `contributor` is touched (their PR check run is the flake's observable
  surface); already modelled with a CI-isolation description that this change does not falsify.
- **(b) External systems / vendors** — the harness reaches Docker Hub, the Ubuntu apt archive, and
  GitHub Releases. `github` is modelled; Docker Hub and the apt archive are not, deliberately — the
  model scopes to runtime product topology and declares no CI-runner element (no Actions container,
  no build-time fixture registry beyond `ghcr`/`zotRegistry`, which serve runtime images). These are
  pre-existing fixture dependencies this plan neither adds nor removes.
- **(c) Containers / data stores** — none. `gitDataStore` is the suite's subject, but this plan
  changes one arm's verdict logic, not the store, its posture, or the birth-readiness gate.
- **(d) Actor ↔ surface access relationships** — none.
- **`views.c4`** declares three views (`context`, `containers of platform`,
  `components of platform.plugin`); none includes a CI-harness element, so no `include` line changes.

## Observability

```yaml
liveness_signal:
  what: the suite's summary line, extended with Skipped:N plus a breakdown NOTE on a degraded run
  cadence: every PR and every push to main whose diff matches apps/*/infra/**
  alert_target: the deploy-script-tests job in .github/workflows/infra-validation.yml
  configured_in: .github/workflows/infra-validation.yml (the step invoking the suite)
error_reporting:
  destination: the GitHub Actions step's own non-zero exit, surfaced as a red deploy-script-tests check on the PR; every FAIL writes its reason and detail to stderr in the suite's existing fail() format, and every SKIP writes its reason plus the captured docker rc
  fail_loud: true
failure_modes:
  - mode: the mutant executed and did not reach the chmod marker
    detection: execution marker present, FIXTURE literal absent, CHMOD_RAN absent
    alert_route: FAIL, non-zero suite exit, red deploy-script-tests step
  - mode: the driver never ran
    detection: execution marker absent with a non-empty capture; the reason carries the docker rc and its measured class (100 apt / 125 pull) offered as classification, never asserted as cause (AP-021)
    alert_route: SKIP, counted in Skipped:N in the summary line
  - mode: the capture server could not bind (deterministic fixture defect)
    detection: the FIXTURE literal, tested before the marker branch
    alert_route: FAIL — explicitly excluded from the skip verdict
  - mode: the capture file is missing or empty while the container exited 0
    detection: the capture-integrity precondition ahead of the verdict branch
    alert_route: FAIL — a missing measurement is a harness bug, never an environment skip
  - mode: skips exceed the declared ceiling
    detection: counted assertion comparing SKIPPED against the ceiling
    alert_route: FAIL, non-zero suite exit
  - mode: the mutation did not land
    detection: the arm's existing pre-branch, preserved unchanged
    alert_route: FAIL
logs:
  where: GitHub Actions run logs for the deploy-script-tests job
  retention: 90 days (repository default)
discoverability_test:
  command: bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh
  expected_output: "git-data-runcmd-rehearsal: 47 passed, 0 failed, Skipped: 0 (47 assertions)"
```

First token is `bash`, on the preflight Check 10 allowlist. Requires docker, terraform and python3 —
the dependencies `_skip()` already gates — and no credentials, so no `credentials_required` is owed.

## Files to Edit

- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — all of Phases 1-2.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-188-*.md` (ordinal provisional).

## Acceptance Criteria

### Pre-merge (PR)

1. The arm's rc is captured and **used**: the rc variable appears in each of the arm's verdict
   messages. Asserted as a positive property, not as the absence of the `|| true` string — deleting
   `|| true` without capturing rc would satisfy the negative form.
2. The `drive.sh` heredoc emits an execution marker above `. /work/doppler-dl.sh` and below the
   capture-server guard, and a structural guard asserts it on the **mounted** `drive.noerrexit.sh`.
3. The verdict branch tests, in order: `CHMOD_RAN`, `FIXTURE:`, marker, else fail — with the ordering
   rationale commented. Verified by reading the branch and by Guard rows 1-4.
4. A capture-integrity precondition precedes the branch and hard-fails on a missing/empty capture
   with rc 0 (Guard row 5).
5. The existing "mutation did not land" pre-branch survives unchanged, so the arm contributes
   exactly 1 to `total` on **every** path — the invariant the floor comment already narrates for S1
   and R1. Guard row 8.
6. All eight Guard rows executed against the real suite, each producing the required verdict,
   recorded in the PR body with observed output.
7. **AMENDED at review (#7291).** A counted skip reporter exists alongside `pass()`/`fail()`,
   `_skip()` is not renamed, and the name collision is avoided. The counter is named
   **`SKIPPED_ASSERTIONS`**, NOT the plan's original `SKIPPED`: `git-lock-chardevice-sweep.test.sh`'s
   `SKIPPED` counts **arms** (one increment for an arm carrying six assertions) and that suite has
   no assertion floor, so reusing the identifier would import no compatibility while putting two
   different denominations behind one name in one directory. The `Skipped: N` summary spelling still
   matches the sibling; only the variable diverges, following `infra-config-apply.test.sh`.
8. The ceiling is a counted assertion with its derivation in a comment; `total` is
   `passes + fails + SKIPPED`.
9. The floor is main's floor **+1** — **47** after the #7501 rebase — with a `RAISED` itemisation
   stanza in the file's existing style. Stated as a delta because the base moved mid-flight.
10. The B5 doctrine comment block is amended in the same commit and cites the ADR.
11. **AMENDED at review (#7291) — the suite-path clause is WITHDRAWN, its premise was false.** The
    summary line carries passes, fails and `Skipped: N`, asserted against the emitted format rather
    than a particular count. The original criterion also demanded a derived suite path, justified by
    "`git-data-emit.test.sh` carries the identical floor and a count alone does not identify the
    suite". Both halves are false: each summary line already opens with its own suite name
    (`git-data-emit:` vs `git-data-runcmd-rehearsal:`), so the count was never the identifier; and
    after this PR the floors are 44 vs 45, so they are not identical either. The derived path was a
    `git rev-parse` subshell buying no information, and was cut.
12. **Environment smoke (labelled separately, ambient by nature).** A healthy local run reports
    `47 passed, 0 failed, Skipped: 0`. Recorded as an environment observation, **not** a diff
    property — a concurrent sibling container can flip the skip count without a line of the diff
    changing (`cq-ac-must-not-depend-on-concurrent-sessions`).
13. A run with setup forced to fail via a bogus package name reports the arm as SKIP, exits 0, floor
    still met, `Skipped: 1`.
14. `bash -n` on the file is clean. Unconditional — no "if available" clause, which would fail open
    exactly as the B5 doctrine forbids. `shellcheck` output, if present, is advisory only.
15. New greps follow the in-file `#7005` prohibition (no `head … | grep -q`) and the
    `$(grep -c … || true)` idiom.
16. `ADR-188-*.md` exists with `amends: ADR-181`, argues the reversal of ADR-181 property 4,
    reconciles with AP-021/ADR-166, and records the rung-2 counter-precedent. Its ordinal is unique
    among `ADR-*.md` on the merge base and no other file in the PR names a different ordinal. (The
    pre-merge re-derivation against fetched refs is a ship step, not an AC — an AC whose outcome
    another PR can flip is not an acceptance criterion.)
17. **AMENDED at review.** Every `## Deferred Scope` row is dispositioned — but three were
    RESOLVED rather than filed, which is the better outcome and the one the CONCUR gate forced.
    Filed: #7565 (P1, discovered defect), #7572 (the S1 instance, as a bug not an asymmetry),
    #7574 (persistence bound, criterion 3, follow-through wired). Resolved-not-filed: the `-ne`
    floor and the INCONCLUSIVE rename (both rejected with reasons recorded in the code and the
    ADR), and the bounded retry (wontfix, folded into #7535). Pre-bake points at #7535 rather
    than restating it.
18. The PR body carries `Closes #7291`.

### Post-merge (operator)

None. Every step is automatable in-session and in CI.

## Test Scenarios

Every scenario is *mutation → guard reddens*, not *command → terminal output*.

| # | Mutation | Expected |
|---|---|---|
| 1 | Block neutered to return before chmod, environment healthy | FAIL |
| 2 | Setup forced to fail via a bogus package name | SKIP; exit 0; floor met; `Skipped: 1` |
| 3 | Execution-marker line deleted, environment healthy | FAIL, not SKIP |
| 4 | Capture server pre-bound so the driver exits at `FIXTURE:` | FAIL, not SKIP |
| 5 | `$TMP/out/stdout` truncated before the verdict evaluates | FAIL, not SKIP |
| 6 | Skip-ceiling assertion deleted | Suite non-zero (floor no longer met) |
| 7 | Second `arm_skip` call site added without raising the ceiling; both forced | Suite non-zero at the ceiling |
| 8 | `set -e` restored so the mutation does not land | FAIL at the existing pre-branch |
| 9 | Marker present on the source heredoc but stripped from the mounted artifact | Structural guard hard-exits |
| 10 | Nothing mutated (control) | `47 passed, 0 failed, Skipped: 0`, exit 0 (the suite-path suffix was cut at review — see AC11; the count is 47 after the #7501 rebase) |

## Risks & Mitigations

- **SKIP becomes the new vacuity.** The dominant risk. Mitigated by requiring *positive
  corroboration* rather than mere absence: the skip is reachable only past the capture-integrity
  precondition and the `FIXTURE:` test, with Guard rows 3, 4 and 5 as its demonstrated failing
  directions, and the counted ceiling bounding the rest.
- **The fix relocates the bug one level up.** The original defect was "absence of a marker read as a
  finding". A naive fix reads absence of the *new* marker the same way. Rows 3 and 5 and the separate
  capture-integrity step exist for exactly this.
- **P4 is bounded per-run, not across runs.** An arm skipping every run satisfies every condition.
  Deferred with a defined observation window (>1 in 20 ⇒ the pre-bake is owed).
- **The actual cause remains UNKNOWN**, so this may not eliminate the flake. Mitigated by phase
  ordering and by Deferred Scope naming the exact evidence that triggers the pre-bake.
- **P4 is bought only for the observed mode.** A setup failure in the T5 *primary* arm or T17 still
  fails the suite, because extending the verdict there is a net regression without skip propagation.
  Deliberate, deferred, tracked.
- **Floor drift.** The floor moves by +1 with the one counted assertion (46 → 47 post-rebase);
  floor and itemisation
  comment must move together.

## Plan Review Revisions

Six reviewers ran against v1 (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO/devex). Every factual claim below was independently re-verified before
applying.

- **R1 — three false claims in v1, corrected.** Four sibling suites replicating the doctrine (really
  2 files); no sibling maintains a skip counter (`git-lock-chardevice-sweep.test.sh` does); no ADR
  governs this (ADR-177/181/166 do). See Corrected factual record.
- **R2 — prior-art miss, and its mechanism recorded.** A case-sensitive grep on `SKIP` missed
  ADR-181, whose title is literally about counted skips. The ADR is reframed from standalone to
  `amends: ADR-181` with an argued reversal of its property 4.
- **R3 — Phase 3 cut in full.** The simplification panel (DHH, code-simplicity) and the correctness
  panel (spec-flow) all fired on one scope; per the consolidation rule that means delete, not fix.
  Dissolved the invoker-parity assertion (red on day one — `grep -c 'docker run'` returns 8, not 6,
  two being prose), the reserved exit code, the setup helper, the floor contradiction, Guard 2
  entirely, and four scenarios.
- **R4 — `run_case()` skip-eligibility was a net regression; deferred.** Its two callers run
  follow-on assertions against the globals `run_case` sets. On a skipped case T5's two capture greps
  fail spuriously and — decisively — T5's `grep -q 'CHMOD_RAN' … else pass` and T17's
  `[ -s "$CAPTURE" ] … else pass` both **pass vacuously**, certifying an abort and a clean healthy
  run that never happened. Today's rc-mismatch failure is the only signal those are garbage.
- **R5 — the retry would have destroyed its own evidence.** A success on attempt 2 is a green run
  with no record a retry occurred, deleting the frequency signal Phase 1 exists to collect.
  Deferred behind the pre-bake, which removes the cause instead of hiding it.
- **R6 — pre-bake un-cut.** v1 rejected it on three grounds, all measured false; it is now the
  *preferred* deferred remedy, with the `/run/sshd` fidelity assumption converted into a checked
  in-arm assertion.
- **R7 — four hard-failure states routed.** A fixture that cannot bind, a missing/empty capture, a
  vanished marker, and a mutation that did not land were each named in v1's prose and never routed.
- **R8 — the ceiling's un-raisable half removed**; residual stated, with the in-file stale
  `"four plain docker run"` comment cited as measured proof the drift risk is real (and corrected in this PR).
- **R9 — bounds reduced from three to one.** The "at least one container arm executed" floor was not
  computable as specified — every arm `rm -rf "$TMP/out"` destroys the evidence it would read.
- **R10 — the pairwise primary/mutant gate was proposed and rejected with a reason.** Gating SKIP on
  the primary arm also failing to execute would convert the **observed** flake into a FAIL. Adopted
  as reported evidence instead.
- **R11 — ambient ACs split.** v1's exact-count AC is now a deterministic format property plus a
  separately-labelled environment smoke; the `shellcheck` "if available" clause is gone; the ADR
  re-derivation moved from an AC to a ship step.
- **R12 — bash correctness.** `skip()` → `arm_skip()`; `local` → plain assignment (invalid
  top-level, and under `set -u` it kills the suite mid-run); the `#7005` SIGPIPE prohibition and the
  `$(grep -c … || true)` idiom made explicit; the marker asserted on the mounted artifact.
- **R13 — `::warning::` cut**, superseded by ADR-181's counted-BREAKDOWN precedent.
- **R14 — B5 doctrine comment amendment added to Phase 2**, which no v1 phase covered.

## Surfaced Decision (not auto-applied)

The CTO review proposed dropping the SKIP verdict entirely: sentinel absent ⇒ **FAIL with a message
naming non-execution and printing the rc**. The argument is that on a non-merge-blocking check a
loud, correctly-attributed FAIL costs the same triage cycle as a SKIP and buys zero new vocabulary.

This contradicts the operator's stated direction in #7291 (*"On a download failure the honest verdict
is SKIP-with-reason (or a retry), not FAIL"*), so per ADR-084 it is a **User-Challenge** and is not
auto-applied. It is persisted to
`knowledge-base/project/specs/feat-one-shot-7291-t5-mutation-network-flake/decision-challenges.md`
for `ship` to render into the PR body and file as an `action-required` issue. The plan proceeds with
SKIP as the issue directs — a position AP-021/ADR-166 independently supports ("a verdict must never
collapse 'could not check' into 'bad'").

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Retry the whole arm on a missing marker | Cannot distinguish the two states either; retrying a genuine vacuity three times still FAILs. |
| Local tarball fixture | Measured to harden the wrong dependency; costs T5 its supply-chain fidelity. |
| `pass` on non-execution (the D1 `pass; pass` precedent) | Exactly the vacuity the issue forbids; the reason is written into the code comment so a later author does not copy it here. |
| Drop the mutation arm, rely on the primary assertion | Removes the only proof `CHMOD_RAN` is reachable, returning T5 to the tautology the instrumentation fixed. |
| Suite-wide setup helper + retry + reserved exit code (v1 Phase 3) | Cut at review — unconfirmed cause, 3 of 6 sites share the shape, `run_case()` half a net regression. |
| Pairwise primary/mutant skip gate | Would convert the observed flake into a FAIL; adopted as evidence, not as a gate. |
| Standalone ADR with no parent | v1's approach; would have minted a third verdict taxonomy beside ADR-177 and ADR-181. |

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change confined to a CI test harness. The mechanical UI-surface override did
not fire: neither `## Files to Edit` nor `## Files to Create` matches any UI-surface term or glob.
