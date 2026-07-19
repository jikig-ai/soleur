# Learning: a mutation battery I wrote proved 7/7 RED — nine mutations I never conceived of all survived

**Date:** 2026-07-19
**Issue:** #6441 (ADR-114 §I1 first-boot NIC-wait gate) · PR #6708
**Category:** test-failures
**Module:** apps/web-platform/infra

## Problem

I shipped a boot-ordering gate with what looked like unusually strong evidence: a behavioural
harness that *extracted and executed* the baked helper against a stub `ip` (rather than
grepping for literals), a non-vacuity guard that hard-FATALs if the extraction comes back
empty, a positive control on a count assertion, and a **7-mutation battery, all RED**.

A review pass ran nine mutations I had not thought of. **All nine survived green**, including:

- Deleting the wait loop's `break` — so every real NIC attach would emit `private_nic_timeout`.
- `grep -qwF` → `grep -qF` — dropping the word-boundary guard entirely.
- `ip -4 -o addr show` → `ip -o link show` — a probe that can never match anything.
- `while [ "$n" -lt 30 ]` → `-lt 1`, and `sleep 2` → `sleep 600`.
- Removing `user_data` from the resource's `ignore_changes` while adding a decoy elsewhere.
- Deleting the `host_creates` HALT tripwire that the safety argument actually rested on.

The battery was not weak. It was **complete with respect to the mutations I imagined**, and
that is a different property than coverage — one that is indistinguishable from coverage when
you are the person who wrote both the code and the mutations.

## Root cause

Every surviving mutation reduces to the same shape, and it is one this repo has now documented
three times: **a claim quantified over a set the fixture only ever sampled once.**

| Contract the test claimed | What the fixture actually sampled |
|---|---|
| "waits for the NIC to appear" (temporal) | **static** stubs only — address present at t=0, or absent forever. The transition, which is the entire reason the gate exists, was never driven. |
| "`-w` prevents `10.0.1.1` matching inside `10.0.1.10`" (bidirectional) | one direction — expect `.10` / host holds `.1`, which fails with **or without** `-w`. The dangerous direction (expect `.1` / host holds `.10`, where plain `grep -F` returns a false READY) was absent. |
| "a probe fault is NEVER reported as absence" (whole fault space) | one door — `command -v` resolution failure. An `ip` that *runs and exits non-zero* — the likeliest real fault — still reported absence. |
| "probes with `-4 -o addr show`" (call shape) | an **argv-blind** stub that emitted its heredoc whatever arguments arrived. |
| "waits 30 × 2 s" (the quantity the design rests on) | `sleep` stubbed to a no-op and never counted. |
| "no `-target=` reaches web-1" (a set of spellings, across a set of workflows) | one spelling (single-quoted), one workflow. |

The temporal case is the sharpest. A guard whose contract is *change over time* — a wait, a
retry, a debounce, a convergence, a backoff — is only ever probed at **t=0 and t=∞** by static
fixtures. Both endpoints can be correct while every transition is broken, and no amount of
mutation *of the code* surfaces it if the *fixture space* has no transition in it.

## Solution

Fixture-space additions, each killing a specific survivor:

- **A stateful stub** that reports the address only from invocation N onward, plus an assertion
  that ready was reached *via* the loop (`sleep` invoked ≥ 1) and that the loop **broke** rather
  than running the full bound (`< 30`).
- **A counting `sleep` stub**: `printf '%s\n' "$1" >> "$SLEEP_LOG"`, asserted at exactly 30
  entries, each `2`. Exact equality is right here — it is a loop-bound constant, not a
  wall-clock measurement, so it is stable *and* discriminating.
- **argv validation in the stub**: `if [ "$*" != "-4 -o addr show" ]; then exit 2; fi`. This is
  what converts a convenient contract into the real one.
- **The reversed direction** of the substring fixture.
- **All four probe-fault doors** (unresolvable / non-zero exit / missing `grep` / empty arg).

Implementation fixes the fixtures forced out into the open:

- `[ -n "$EXPECTED" ] || { soleur-boot-emit private_nic_probe_fault warning; exit 0; }` —
  `grep -qwF -- ""` matches **every** line, so an empty argument emitted `private_nic_ready`:
  positive evidence that a check passed which was never performed.
- Capture the probe's exit separately from the match (`if OUT=$(...); then`), with a
  `probe_ran` flag, because a pipeline reports only `grep`'s status.
- Drop `seq`: an unresolvable `seq` yields an **empty word list**, so the loop body runs zero
  times and the helper reports a 60 s timeout it never waited.

## Key insight

**A mutation battery measures the tests against the mutations its author conceived of. Its green
is evidence about the battery, not about the tests** — and the author of the code is the worst
possible author of its mutations, because the same blind spot generates both.

The mechanical question that finds these without needing a second party:

> For each contract sentence in the header, what is the SET it quantifies over — and how many
> distinct members does the fixture actually instantiate?

If the answer is "one", the assertion is a sample, not a proof. Applied per row of the table
above, that question finds all six gaps in about a minute.

Corollary for temporal contracts specifically: **if the property is "X changes over time",
a fixture that is constant in time cannot test it, no matter how many code mutations it kills.**

## Second theme: three false claims, all in load-bearing prose

Independent of the test gaps, three assertions shipped that nothing verified:

1. *"This is the first PR to edit `soleur-host-bootstrap.sh` since the coherence guard was
   added."* — **false**; `git log` shows 7 edits since. Transcribed from the plan without
   checking. It changed no conclusion, which is exactly what made it easy to write and easy to
   miss: unearned confidence with no failing consequence.
2. *"An `ExecStartPre` would consume the downstream gate's budget and detonate its `|| exit 1`."*
   — premise true, **conclusion invalid**: `cloudflared service install` runs `systemctl start`,
   which blocks, so the budgets are sequential under either shape. The real hazard is
   `TimeoutStartSec` spanning `ExecStartPre`+`ExecStart`. The rejection survived on other
   grounds; the stated reason did not.
3. *"The gate converts the pathological case from silent to observed."* — the emitted stages
   matched **no** `tagged_event` filter among 26 alert rules, and because the emitter sends one
   shared message for every stage, they raised no new-issue notification either. Emitting into
   a bucket nobody reads is not observability.

All three are the same failure: **a claim whose falsity would break nothing.** The test for
prose is identical to the test for a guard — *if this were false, what would fail?* If the
answer is "nothing", it is documentation, not wiring, and it should be either deleted or
wired. #3 was wired (a dedicated Sentry rule + an emit/route lockstep assertion). #1 was
deleted. #2 was corrected in place with the correction recorded, because the wrong version had
already shipped in a commit message and a code comment.

## Session Errors

1. **A negative assert I wrote was vacuous.** Over-escaping through `eval` made
   `! grep -qE "…-target='hcloud_server\.web\[\"web-1\"\]'"` unmatchable, so it passed against a
   workflow that genuinely targeted web-1. — *Recovery:* count a fixed string **outside** the
   `eval` and compare integers, plus a positive control. — *Prevention:* never put a
   backslash-heavy regex inside an `eval`'d assert string; compute outside, assert on the
   variable. Mutation-test every negative assert.
2. **The AC8 assertion tested the wrong property entirely.** "web-1 is in no `-target=`,
   therefore no create" is invalid — `-target` is transitive at the resource level, as the
   workflow states in its own comments. — *Recovery:* assert the `host_creates > 0` HALT that
   actually guarantees it. — *Prevention:* for any "X cannot happen" assert, name the mechanism
   that prevents X and assert **that**, not a correlate of it.
3. **Empty-argument guard dropped from a mirrored precedent.** — *Prevention:* when a comment
   says "mirrors `<file>`", diff against that file rather than trusting the mirror claim.
4. **Probe execution failure conflated with absence** (items 5–7 above). — *Prevention:* when a
   header claims a property over a fault space, enumerate the fault space and test each member.
5. **`model.c4` self-contradiction created by a partial sweep** — flipped two of three web-2
   descriptions. — *Prevention:* when correcting a claim, grep the whole file for the claim
   *family*, not the sentence being edited.
6. **Foreground full-suite run hit the 10-minute tool ceiling.** — *Recovery:* re-ran
   backgrounded. — *Prevention:* run `scripts/test-all.sh` backgrounded by default under load;
   read the real exit from the log, since a trailing `echo` masks the runner's status.
7. **My own failure-grep false-positived twice** — `T14 failed reopen emits…` matched
   `[0-9]+ failed`, and `SOLEUR_GIT_WORKTREE_VERIFY_FAILED` matched `FAILED`. I nearly misread a
   clean run as dirty. — *Prevention:* when grepping a test log for failures, anchor on the
   runner's own summary line, not on substrings that appear in test *names*.
8. **A mutation failed to apply and reported the baseline.** — *Recovery:* the harness asserted
   the mutation landed (`git diff --quiet`) and printed **"MUTATION DID NOT LAND (treat as
   UN-RUN)"** instead of a pass. — *Prevention:* this guard is mandatory; a failed `sed`
   otherwise prints the baseline count, which is indistinguishable from "nothing to catch".
9. Transient `ENOSPC` on the agent temp filesystem (one-off; self-resolved).
10. A hook blocked a plan edit for manual-infrastructure framing when the text merely *described*
    pre-existing state. — *Recovery:* reworded to state the fact without operator framing rather
    than acking past the gate. — *Prevention:* none needed; the gate behaved correctly and the
    conservative response was cheap.
11. Forwarded from plan phase: the first draft put the timeout emit in a caller-side `||` arm
    while the helper exits 0, making it unemittable; two ACs used `grep -c … == 0`, which exits
    1 on the passing case.

## Prevention

- For any guard whose contract is **temporal**, require a fixture that is *not* constant in
  time before calling the guard tested.
- For any **bidirectional** guard (`-w`, ordering, comparison), test the direction where the
  weaker implementation gives a **false positive**, not just the direction that happens to fail
  either way.
- Stubs must validate the call shape they stand in for; an argv-blind stub silently voids the
  call-shape contract.
- Quantities the design rests on (budgets, bounds, retry counts) must be **counted**, not
  stubbed away — otherwise the number in the comment is unverified.
- Treat "my mutation battery is green" as a statement about the battery. Ask the set-cardinality
  question per contract sentence, or have a second party author the mutations.

## Related

- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
  — **an independent PR (#6588) hit this same class on the SAME DAY**, landing on `main` while this
  branch was in review (pulled in by a Phase 7 BEHIND sync). Two unrelated features, two authors'
  self-graded batteries, both vacuous, both caught only by an outside party. That is no longer a
  coincidence worth documenting a third time — it is the argument for a *mechanical* gate. Its
  answer is a two-producer count (assert the derived set's cardinality against the producer's);
  this one's is fixture-space cardinality. They are the same question asked of different sets:
  *how many distinct members does the check actually instantiate?*
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — the same class; that one's
  gate is "enumerate the SUT's functions and confirm each is called". **Insufficient here:**
  every function *was* called. The gap was fixture-space cardinality, not call coverage.
- `2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md` — the generalized
  form. This session is its **third** recurrence, which per that learning's own conclusion means
  the disposition is a mechanical gate rather than another prose rule.
- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
  — the anchoring sibling (items 1, 2 and 5 of the Session Errors above).
- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md` — the
  probe-fault doctrine this gate cites and half-implemented.

## Tags

category: test-failures
module: apps/web-platform/infra
