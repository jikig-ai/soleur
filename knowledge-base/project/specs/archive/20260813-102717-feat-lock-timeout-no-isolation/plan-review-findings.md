---
date: 2026-08-12
plan: knowledge-base/project/plans/2026-08-12-fix-instrument-advisory-lock-wait-plan.md
issue: 7484
panel_requested: [dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto]
panel_completed: [dhh-rails-reviewer, code-simplicity-reviewer, spec-flow-analyzer, cto]
panel_failed: [kieran-rails-reviewer, architecture-strategist]
failure_reason: "weekly API limit reached mid-run (resets 2026-08-16)"
---

# Plan-review findings — instrument the advisory-lock wait

Four of six reviewers returned. **Two died on the weekly API limit and their lenses are
UNCOVERED** — recorded here so a later session inherits the gap rather than assuming a clean panel:

- **kieran-rails-reviewer** (strict correctness + convention) — never returned. Its assigned
  questions included the EPOCHREALTIME arithmetic duplication across lib/script, the `wait_ms > 1000`
  boundary against 2000 ms test timeouts, and the arm-15 grep interaction.
- **architecture-strategist** (blast radius) — never returned. Its assigned questions included the
  full consumer enumeration of `scripts/lib/test-contention.sh`, whether the TR1 boundary is drawn
  correctly, and whether adding globals further erodes ADR-133 Decision 1's stated "observe-only"
  property.

Neither gap blocks the consolidation below — the surviving four converged hard and several of their
findings independently cover the same ground — but a re-review of those two lenses is owed before
this ships.

## The finding that reframes the plan (4 independent confirmations)

**`TEST_TIMING_LOG` is never set in any automated path.** Confirmed by CTO, DHH, spec-flow, and an
independent orchestrator grep. Every assignment in the tree is a test arm pointing it at a per-arm
sandbox path *specifically to keep rows out of the operator's real log*:

- `scripts/test-all-infra-coverage-notice.test.sh` (two sites)
- `scripts/test-all-killed-classification.test.sh`
- `plugins/soleur/test/fanout-suite-scope.test.sh`

Zero hits in `.github/workflows/**`, zero in `plugins/soleur/skills/**`, zero in `.claude/`. CI runs
the gate but sets nothing — and it would not matter, because `tc_acquire` returns at the CI exemption
before it ever waits, so every CI row would read `lock=skipped_ci wait_ms=0`.

**Consequence:** property **P2** ("the acquire-vs-timeout ratio is derivable across runs") is
unreachable as specified, and P2 justified roughly half the plan's machinery. The one time this log
produced real data is recorded in ADR-133's own second addendum: one full-gate run, by hand, with
`SOLEUR_TEST_FORCE_ALL=1`.

spec-flow added the sharpest framing: `_emit_bytes_probe` shipped **yesterday** under the identical
gate, #7454 item 1 already names its output as a re-evaluation trigger, and nothing reads a
`bytes_tmp=` row either. This plan would ship the second instance of the same open loop — in a repo
that already carries
`knowledge-base/project/learnings/2026-08-11-the-pr-that-fixed-unmeasured-verdicts-shipped-unmeasured-verdicts.md`.

## The plan's central claim is falsified (spec-flow G2)

The Overview claimed the recorded rows would decide between **(a)** raising `TC_LOCK_TIMEOUT` and
**(b)** short-circuiting a futile wait on holder age. They cannot:

- **Contended rows are right-censored by construction.** The timeout is fixed at 900 s and this PR
  forbids changing it, so every `lock=contended` row reads `wait_ms ≈ 900000`. N such rows cannot
  distinguish a holder that released at 901 s from one that held 2,700 s — and "would 1800 s have
  succeeded?" is precisely the question censoring destroys. Option (a) is unanswerable from this data.
- **Option (b) needs the holder's age; the row measures the waiter.** The Cut List removed the only
  mechanism that would carry it, candidly and for a defensible reason — but the consequence follows.

What the row genuinely answers: *does the wait ever pay off, and what is the longest wait that was
redeemed?* The action that most directly supports is **lowering** the timeout to just above the
longest redeemed wait — neither (a) nor (b), and awkward against a Non-Goals list that bars changing
the value.

spec-flow also noted the plan already contains a datum it treats as missing: if the holder is a full
gate run (~2,700 s) and the budget is 900 s, a wait entered against a freshly-started holder is
provably futile **today**, with no new data. What is genuinely unmeasured is *where in its run the
holder is* — the cut field again.

## Severity-ordered findings

### P0 — the emitter can wedge the gate it measures (spec-flow G7)

`scripts/test-all.sh` installs a stub `tc_acquire() { :; }` when the lib is absent or fails to parse.
That stub sets no globals. The `unset` sentinel is initialised *inside the lib's* `tc_acquire`, so on
this path `TC_LOCK_OUTCOME` is not the sentinel — it is an unset shell variable. `test-all.sh` runs
`set -euo pipefail`, so an emitter reading `$TC_LOCK_OUTCOME` without a `:-` default **aborts the
whole gate**. An instrument wedging the run it measures is exactly what the plan's own Observability
section says must never happen, and Guard 1's property quantifies over `tc_acquire`'s exit paths so it
structurally cannot see the stub.

### P1 — D4's justification is factually wrong (code-simplicity; spec-flow G8 concurs)

D4 argued the banner correction matters because `work/SKILL.md`'s trustworthiness grep "reports
contention that did not happen." That grep matches the **token** `LOCK_CONTENDED`, not the message
text — and its inline comment says the anchor was chosen deliberately. Correcting the prose after the
colon leaves the token intact, so the grep still fires. **The fix as planned does not fix the harm it
cites.**

spec-flow added that D4 as written *reduces* signal: the corrected banner would match neither
`LOCK_CONTENDED` nor the `[contention] BANNER <NAME>:` pattern, so a fully inert lock layer becomes
invisible to the very consumer D4 invoked as justification.

### P1 — two row fields have no writer (spec-flow G4)

- **`timeout_s`**: `tc_acquire` opens with `local timeout_s="${2:-$TC_LOCK_TIMEOUT}"` — a **local**. An
  emitter in `test-all.sh` can only read the global default, never the effective argument. Latent
  today (the one production call site passes no `$2`) but wrong the day any call site passes an
  explicit timeout — which is exactly the scenario OQ1 cites as the field's whole purpose. No AC and
  no mutation row covered it either.
- **`timing=unavailable`**: the `EPOCHREALTIME` guard lives in the lib; the flag prints from
  `test-all.sh`; no phase step exports a global carrying it. Mutation row 4 asserts against a signal
  nothing creates.

### P1 — AC12 is unsatisfiable by any arm the plan describes (code-simplicity)

AC12 needs `lock=acquired` **with `wait_ms > 1000`** produced deterministically. Arm 10 acquires a
*free* lock (near-zero). Arm 11's holder sleeps 12 s past a 2 s timeout (never acquires). Neither
yields a slow *success*. Needs a new fixture — a holder that **releases mid-wait** (e.g. `sleep 2`
under a 6 s timeout). Worth adding regardless of other cuts: a slow acquire is the single outcome the
whole PR exists to prove reachable.

### P1 — classification thresholds are never assigned (code-simplicity; spec-flow G5, G6)

`AC2`'s `≈ timeout_s` and `AC4`'s "near-zero" have no numeric predicate anywhere in the plan, and the
enum has no member for the middle band (a non-zero return at 400 s of 900 s). The implementer would
pick a constant at the keyboard, and either pick corrupts the one ratio the PR exists to produce.
D5 compounds it: on a host where `EPOCHREALTIME` is empty, classification-by-elapsed-time is
*impossible* and both labels would be fabrications — on the exact platform D5 was written for.

### P2 — no timestamp on the row (spec-flow G3)

The decision bar's "≥2 distinct calendar days" is not computable from the artifact. No
`TEST_TIMING_LOG` row carries a timestamp and there is no `date`/`EPOCHSECONDS` call on any timing
write path; `__run_boundary_start__` is undated too.

### P2 — the follow-up has no home (spec-flow G9, verified against live GitHub)

#7454 is OPEN, but item 3 is scoped to *"replace the cross-worktree advisory mutex with admission
control on actual `/tmp` headroom"*, with the multi-run budget as its trigger. It says nothing about
`TC_LOCK_TIMEOUT`-vs-holder-age, nothing about `__lock_wait__`, nothing about the OQ2 bar. The plan is
right that #7454's bar must not be imported — but the consequence is the deferred question has no
tracker, no owner, and no cadence.

## Convergent cuts — both panels fired on the same scope

Per the skill's rule (*"when BOTH panels fire on the same scope, prefer delete over fix"*):

| Mechanism | DHH | code-simplicity | CTO | Verdict |
|---|---|---|---|---|
| Elapsed-time classification (#3) | cut | cut (HIGH) | cut | **CUT** — unanimous. Derivable from `wait_ms` + `timeout_s`, both already recorded; forces two unassigned thresholds. |
| D4 banner correction (#5) | keep-cheap | cut (does not fix stated harm) | — | **CUT as justified**; replace with the token-level fix below. |
| `unset` sentinel **arm** + positive control (#2b) | cut | cut | — | **CUT** the arm; **KEEP** the one-line init. |
| `timing=unavailable` dedicated arm (#8) | cut | cut | cut | **CUT** the arm; keep the field only if a row survives. |
| Three of four new arms (#9) | cut | cut | — | **CUT.** |
| `precondition_failed` enum | cut | cut (YAGNI) | cut | **CUT** — replaced by an exact `command -v flock` check feeding the EXISTING `LOCK_UNAVAILABLE` outcome. No new vocabulary, no threshold. |

## What every reviewer independently endorsed

- **Measurement before mechanism is correct.** DHH explicitly ring-fenced this from the size critique:
  the two candidate fixes point opposite ways, the deciding datum genuinely does not exist, and the
  docker-healthcheck learning is the right precedent for what happens if you guess.
- **The banner is lying and that is a real bug** — `still held after ${timeout_s}s` prints
  unconditionally on the `99` path. The cheap and honest repair is to **print the duration actually
  measured instead of asserting one that was not**, which needs no enum and no threshold.
- **D2's lib-exclusion reasoning is sound** (code-simplicity) — the arms `source` the lib, so a
  lib-resident writer could pollute the operator's real log.

## Unresolved — routed to the operator

The four reviewers **disagree** on how to answer G1, and the disagreement is a genuine scope question,
not a technical one. Recorded in `decision-challenges.md`.
