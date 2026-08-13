---
date: 2026-08-12
topic: test-all.sh advisory lock — 900 s wait that delivers no isolation
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
related_issues: ["#7454", "#7476", "#7376", "#7432"]
related_adrs: ["ADR-133"]
---

# Brainstorm — the advisory lock waits 900 s and serialises nothing

## Origin: what this is NOT

Entry was `/soleur:go 7454`. Issue #7454 is a consolidated deferred-scope-out tracker holding
three post-MVP follow-ups, each with an explicit re-evaluation trigger. **All three triggers were
verified against live state on 2026-08-12 and none had fired.** Rather than re-derive deferrals the
2026-08-11 post-mortem already recorded, this brainstorm scopes a *different* finding — one that
lives only inside the ADR-133 addendum and is tracked in no issue.

### Trigger verification (2026-08-12)

| #7454 item | Trigger as written | Verified state | Fired? |
|---|---|---|---|
| 1. Bounded parallelism for top-level bash suites | `#7376` closes, OR the `bytes_tmp=`/`bytes_tmpdir=` probe identifies the interference mechanism | #7376 **OPEN**, no closing PR; its follow-through sweeper `earliest=2026-08-13` has not had a first sweep. Probe landed (`scripts/test-all.sh:155`) but merged 2026-08-11 and has identified nothing. Second open gate the issue does not name: **#7432**, which records removal of the `JOBS: 1` stopgap as "deadlocked today" with hypotheses H2 (capacity) and H4 (polling-deadline) both **UNKNOWN** | **NO** |
| 2. Session-level "already green" memo | An input model that can see untracked producer/consumer pairs like `_site/` | Nothing shipped in the ~19 h since PR #7441 merged. The `_site/` producer/consumer pair (`scripts/validate-blog-links.sh` reads, `plugins/soleur/test/seo-aeo-drift-guard.test.ts` builds) still stands. Issue explicitly forbids re-attempting a tracked-tree hash | **NO** |
| 3. Multi-run advisory-lock experiment | Can run without a one-full-gate budget cap | Operator budget decision; not sanctioned this session | **NO** |

Operator decision: leave all three deferred, scope the untracked finding instead.

## What We're Building

Instrumentation for the cross-worktree advisory lock in `scripts/test-all.sh`, so the next session
inherits **data** rather than an argument about what the lock is actually doing.

Concretely: record lock-wait duration and outcome on **both** `tc_acquire` exit paths, and disclose
the possible wait in the banner up front. No mechanism change.

## The finding

ADR-133 Addendum 2026-08-11, section *"The sharper finding: the lock is not currently serialising
anything"*:

> The run queued on `tc_acquire` for the **full 900 s `TC_LOCK_TIMEOUT`** and then proceeded, while
> **three sibling runs executed concurrently** — 3,775 s, 5,787 s and 5,763 s elapsed at the moment
> of the probe, against a ~45-minute uncontended baseline. Because the lock is advisory and proceeds
> on timeout, it is charging every session up to 15 minutes of delay while delivering no isolation.

The ADR reframes its own open question: *"It is not 'mutex versus admission control'; it is why a
mutex that proceeds on timeout is being relied on as a mutex."* That reframing is recorded in no
issue — #7454 item 3 still frames the question as the superseded mutex-vs-admission-control one.

### Why the timeout cannot serialise, mechanically

`TC_LOCK_TIMEOUT` is a constant (900 s, `scripts/lib/test-contention.sh:51`) that must exceed a
quantity it has no relation to: the holder's *remaining* critical section. A full gate is ~2,700 s
uncontended and was measured at 5,787 s contended. A wait budget of ~33% (uncontended) to ~15%
(contended) of its own critical section cannot serialise a second waiter reliably.

It is also **self-reinforcing**: every waiter that times out and proceeds lengthens the holder's
run, which makes the next waiter likelier to time out too.

**Archaeology:** the 900 s value entered in PR #6828 (2026-07-22, `fix(test): parallel-worktree
test-all.sh contention`). That PR's body documents the lock's semantics in detail — advisory,
proceeds on timeout, CI-exempt, kill switch — and **records no derivation for 900**. The value is
also documented nowhere operator-facing: it appears only in ADR-133, one learning, and an archived
plan. No runbook, no skill, no `--help`.

## Why This Approach

**The wait is not uniformly wasted, and nobody knows the ratio.** A waiter acquires whenever the
holder finishes within 900 s of its arrival. Against a 2,700 s+ critical section that is a minority
of arrival times — but the actual acquire-vs-timeout ratio is **unmeasured**, and the two candidate
fixes point in opposite directions depending on it:

- *Shorten / short-circuit* assumes the wait rarely succeeds.
- *Lengthen* assumes it should always succeed.

Choosing between them without the ratio is a guess. ADR-133's own Decision item 1 — *"Instrumentation
ships ahead of every fix"* — already governs this, and the learnings corpus backs it
(`2026-05-20-stale-budget-framing-in-issue-body-triggers-scope-pivot-churn.md`: re-measure before
re-plan; `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`).

### The load-bearing negative

Lock-wait duration is recorded **nowhere** today. `tc_acquire` prints one status line per outcome
with no elapsed time (`test-contention.sh:534, 541, 546, 552, 557, 562`). `TEST_TIMING_LOG` carries
per-suite ms, per-suite tmpfs entry deltas and the new `bytes_tmp=`/`bytes_tmpdir=` deltas — but
nothing about the wait. `session-state.sh`'s `acquire_lock` (`:112`) is a blocking `flock -w` that
returns only a status code.

`tc_preamble` computes sibling elapsed times, i.e. *how long each sibling has been running* — not
how long **this** run waited. The two are routinely conflated; they are different measurements.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Scope = the ADR-133 addendum finding only. #7454's three items stay deferred, untouched | All three triggers verified unfired 2026-08-12 (table above) |
| D2 | Approach A: instrument only, no mechanism change this PR | The acquire-vs-timeout ratio is unmeasured and the two candidate fixes point opposite ways |
| D3 | Fail-open is **kept**. ADR-133 Decision item 3 is unchanged | The corpus backs it for non-security dev tooling provided the choice is explicit and documented (`2026-03-20-middleware-error-handling-fail-open-vs-closed.md`), which ADR-133 does. Only the *duration* was ever in question |
| D4 | Abort-on-timeout is **off the table** | ADR-133 Alternatives Considered already REJECTED "Make the lock blocking (abort on timeout)" — "strictly worse than the status quo" |
| D5 | Record as a further **ADR-133 addendum**, not a new ADR | This amends Decision 3's parameters/observability, not its mechanism |
| D6 | Disclose the possible wait in the banner **up front** | A 15-minute delay discovered at minute 14 reads as a hang; announced at minute 0 it reads as a queue. Mitigates the agent-harness-kill risk the CTO flagged |
| D7 | Mechanism change (raise timeout vs futile-wait short-circuit) deferred with an evidence trigger | Filed as a follow-up issue; trigger is the telemetry this PR ships |
| D8 | Brand-survival threshold recorded honestly as a poor fit | See User-Brand Impact below — do not rubber-stamp |

## Non-Goals

- **`/tmp`-headroom admission control**, including the "headroom bypass on top of the mutex" the
  ADR-133 addendum names as follow-up. A bypass *is* admission control and inherits the same TOCTOU
  and non-monotonic-degradation objections. Gated behind #7454 item 3's evidence bar.
- Concurrency-N semaphores, per-suite locks, fair-share queueing, defaulting the lock off — all
  mechanism replacement.
- Any change to `#7376` / `#7432`'s parallel-suite flake work.
- Changing the CI exemption or the `SOLEUR_DISABLE_SESSION_STATE` kill switch.

## Open Questions

1. **What granularity does the telemetry need?** A `TEST_TIMING_LOG` row is the obvious channel
   (it already carries the `bytes_tmp=` boundary rows), but the wait happens *before* any suite runs,
   so it is a run-boundary datum, not a per-suite one. Plan should settle the row shape.
2. **How many runs before the ratio is decidable?** Not a statistical claim — we need enough
   arrivals-while-held to see both outcomes at least once. Plan should state a floor rather than
   leaving "enough" undefined.
3. **Does the same instrumentation belong on `session-state.sh`'s `acquire_lock`** (shared by four
   skills wrapping `gh pr merge --auto` at `with_lock merge-main 600`), or only at the `tc_acquire`
   layer? Widening touches a shared primitive — ADR-178 territory.

## User-Brand Impact

- **Artifact:** the `scripts/test-all.sh` cross-worktree advisory lock (ADR-133) and its
  `TC_LOCK_TIMEOUT` wait — specifically the `tc_acquire` path in `scripts/lib/test-contention.sh`.
- **Vector:** internal only. Operator terminal and autonomous agent sessions. No customer surface,
  no shipped runtime path, no data at risk. The worst outcome is latency on the ship critical path.
- **Threshold:** `single-user incident` is recorded per policy, **but the CPO's assessment is that
  it is a poor fit and it is recorded here rather than rubber-stamped.** That threshold exists to
  catch things where one user hitting it damages trust in the product; nobody outside the build loop
  can hit this. The only truthful brand hook is second-order — slower gates slow customer fixes —
  and that does not meet "incident." Downstream reviewers should weigh it as throughput and
  API-budget cost, not brand risk.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Neither a design defect nor correct-as-is — a **calibration** defect. Fail-open is right
and should be kept; the duration is the whole fault, plus one real design gap: the waiter has no view
of holder identity or age, so it cannot distinguish "holder started 60 s ago" from "holder has
4,000 s left". Smallest correct move is to instrument the wait first, because `LOCK_ACQUIRED` prints
no elapsed time and therefore *nobody knows whether the wait ever succeeds*. Flagged that the two
candidate knobs point opposite ways and must not both ship. Also noted ADR-133's false-RED protection
is the **banner**, not the lock — banners fire regardless of timeout.

### Product (CPO)

**Summary:** Real cost, worth a PR now — a strictly dominated path, since the run ends up unisolated
either way and merely arrives 15 minutes later. Rated cost-of-inaction medium (recurring, on critical
path), risk low, scope small, coupling to #7454 **none**. Sequencing verdict: do this **before**
#7376/#7432, because a 900 s no-op tax on every evidence run directly slows the soak those issues
need, and long lock waits shift run overlap — a confound in the very timing measurements #7376
depends on. Explicitly declined to rubber-stamp the brand threshold.

### Legal (CLO)

**Summary:** No legal, compliance, regulatory or licensing surface — assessment spawned by the forced
triad policy, not by a detected trigger, and the CLO declined to manufacture a finding. One narrow
pre-existing hygiene item confirmed by reading the file: `test-contention.sh` prints absolute
worktree paths from `readlink /proc/<pid>/cwd`, plus core count, load average and MemAvailable, with
no redaction pass — so a pasted preamble discloses home-directory layout and branch-named worktrees.
Mitigated by `/home/jean` already appearing in ~650 tracked files and by the CI short-circuit making
this operator-local output. **Recommendation: not a gate.** Opportunistic only — see below.

## Capability Gaps

None. Every mechanism this brainstorm proposes already exists in-repo; the gap is a missing
measurement, not a missing capability.

Evidence for the "wait duration is unrecorded" claim (the one load-bearing negative): read of
`scripts/lib/test-contention.sh` `tc_acquire` (`:527-564`, all six output sites), `scripts/test-all.sh`
`TEST_TIMING_LOG` writes (`:61-69`, `:149-156`), and `scripts/lib/session-state.sh` `acquire_lock`
(`:90-120`) — none emit an elapsed time for acquisition.

## Opportunistic (not required)

If the chosen implementation touches the `tc_acquire` `printf` sites anyway, making the sibling-path
output repo-relative (stripping the worktree root prefix) is a free hygiene win per the CLO note. It
is **not** a requirement and must not expand the diff on its own.

## Productize Candidate

None. This is a one-off calibration/observability fix, not a recurring work pattern.
