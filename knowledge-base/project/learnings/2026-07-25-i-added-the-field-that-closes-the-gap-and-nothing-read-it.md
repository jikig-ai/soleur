---
title: I added the field that closes the gap, and nothing read it
date: 2026-07-25
category: best-practices
issue: 6178
pr: 6933
tags: [observability, false-clean, guard-design, review, test-vacuity, dead-remediation]
---

# I added the field that closes the gap, and nothing read it

## Problem

PR #6933 exists because `op=verify` — the last gate on the Inngest dedicated-host cutover —
had never produced a verdict across eleven dispatches. Its scan window could not be exhausted,
and the probe is fail-loud on non-exhaustion, so every run died emitting no run set.

The fix narrowed the window and anchored it on a trustworthy instant. Narrowing, however, makes
a *new* failure reachable: a clean verdict over a scan that looked at nothing. So the same PR
taught the probe to report the server's own `totalCount`, precisely so the consumer could tell
**"no duplicates found"** from **"nothing was looked at"** — two identical strings and opposite
facts.

`grep -n total_count .github/workflows/cutover-inngest.yml` → **zero hits.**

The producer shipped. The consumer was never written. `exactly-once VERIFIED` printed
unconditionally, including at `RUN_COUNT=0` — and that verdict authorizes closing the issue and
**deleting the rollback snapshot**. The PR body asserted the gap was closed. Five review agents
found it independently.

## Root cause

**A field added to close a gap closes nothing until something reads it — and the PR that adds
the field is the PR least likely to notice, because the author has already mentally banked the
fix.** The producer-side change is the part that feels like the work: parsing `totalCount`,
threading it into the emitted object, adding it to the markers. Writing the four-line consumer
is an afterthought, and its absence is invisible to every local signal — `tsc` has nothing to
say, both suites were green, shellcheck was clean, CI was 72/0, and my own 11-mutation battery
reported all-caught.

It is invisible because **no test asserts a negative that spans two files.** The probe's suite
verifies the probe emits the field. The workflow's suite verifies the workflow's own assertions.
Nothing asks "does anyone consume this?" — the question lives in the seam.

The same session produced three more instances of one shape: **I asserted a property instead of
measuring it, and the assertion was about my own work.**

## Solution

Gate the verdict in code, not in an operator's attention:

```bash
TOTAL_COUNT=$(echo "$BODY" | jq -r '.total_count // "absent"')
if [[ "$TOTAL_COUNT" == "0" || "$TOTAL_COUNT" == "unknown" || "$TOTAL_COUNT" == "absent" || "$RUN_COUNT" -eq 0 ]]; then
  echo "::error::2.6 VACUOUS SCAN — refusing to report a verdict. total_count=$TOTAL_COUNT run_count=$RUN_COUNT ..."
  exit 1
fi
```

`// "absent"` is load-bearing: a bare `.total_count` on a body lacking the field yields the
**string** `"null"`, which matches none of the gate's literals — so a partial GraphQL error
would sail straight through the gate meant to catch it.

And **qualify** a clean result rather than printing one string for materially different claims —
a verdict over a scoped population, an overridden window, or an anchor weaker than the on-host
row is not the same claim as a full fsm-anchored scan.

## Key insight

**When a PR adds a field whose entire purpose is to let a consumer make a distinction, grep the
consumer for it in the same PR.** A producer-only change leaves the gap exactly as open as it
was, while the PR body, the ADR, and the acceptance criteria all describe it as closed. The
cheapest gate is one line:

```bash
git diff origin/main...HEAD | grep -oE '^\+.*"(\w+)":' | # fields this PR starts emitting
  while read -r f; do echo "$f: $(git grep -c "$f" -- <consumer-paths>)"; done
```

Any `0` is a field that exists only to be described.

Three corollaries from the same session, all the same shape — *asserting instead of measuring,
about my own work*:

1. **A replacement remediation is dead advice until you trace its precedence.** I removed
   "raise the deadline" (arithmetically capped, so it can never help) and replaced it with "set
   `CUTOVER_WINDOW_FROM`" — a variable the resolver consults **only when the primary anchor is
   absent**, i.e. inert on the normal path. Following it changed the window by nothing and the
   next dispatch aborted identically. *Fixing a dead-advice defect is exactly when you are most
   likely to ship another one*, because the relief of removing the old one substitutes for
   checking the new one. Trace the new lever's precedence to the value it claims to change.

2. **A vocabulary copied from another file cannot be validated by per-member spot-checks.** The
   anchor greps seven FSM transition reasons; I shipped six. The missing one,
   `unexpected-exit(from=…)`, is the ERR-trap terminal transition and the **only** row emitted
   when the scheduler starts successfully but the subsequent flag write fails — so omitting it
   returns a *later* row and narrows the window, the unsafe direction. It hid from my
   vocabulary grep because its interpolated `(from=…)` suffix broke the extraction pattern.
   "Does it grep `flip-complete`?" can never detect a *missing* member. The fix is a
   **cross-file parity test** that derives the expected set from the emitter, so a reason added
   there fails here. Mutation-verified: dropping the grep now reddens 2 assertions.

3. **Verifying an AC with a variant of its command verifies a different, weaker claim.** AC9
   says `grep -c 'function discovery'`. I ran `grep -c 'function.discovery\|FUNCTION-DISCOVERY'`
   and reported it satisfied. The literal command returns **0**. A case-insensitive or
   alternation-widened grep is not a convenience — it is a different predicate, and the AC is
   the contract. Run the AC's bytes.

**On mutation batteries.** Mine ran 11 mutations and reported all-caught. A dedicated
test-design pass then found **16 survivors**, the worst being that my own wiring assertions were
file-scoped and could not distinguish a call from a comment — so reverting `op=verify` to the
200-day window, with a one-line comment quoting the old call, kept the suite at 291/291. *The
defect the PR exists to remove was reinstatable at full green.* A green battery is evidence
about the mutations you thought of, and the ones you don't think of cluster in the code you just
wrote.

## Prevention

- **Producer/consumer sweep:** when a diff starts emitting a new field, assert a consumer exists
  in the same diff. Zero consumers = the gap is open.
- **Non-vacuity in code:** a verdict that depends on a human noticing a field is operator
  diligence, not a guard. If a clean result can be produced over an empty scan, the empty scan
  must hard-fail.
- **Parity over spot-checks:** any set copied across a file boundary needs a test that derives
  the expected members from the source of truth.
- **Run the AC's literal command**, never a normalized variant.
- **Assert the mutation landed** before believing a mutation result — a failed `sed` reports the
  baseline count, which reads exactly like "the guard caught nothing to catch". Run the sandbox
  baseline first and require it green; a red baseline voids every result.

## Session Errors

1. **`total_count` emitted but never consumed** — the field added to close the false-clean gap
   had zero readers; `exactly-once VERIFIED` printed at `RUN_COUNT=0`. *Recovery:* hard-fail
   gate + qualified verdicts in both arms. **Prevention:** producer/consumer sweep on every
   newly-emitted field (above).
2. **`unexpected-exit` omitted from the transition set** — interpolated `(from=…)` suffix hid it
   from the vocabulary grep; the omission narrows the window (unsafe direction). *Recovery:*
   added the grep + a cross-file emitter-parity test. **Prevention:** derive copied vocabularies
   from their source of truth.
3. **Replacement remediation was itself dead** — named a variable inert on the primary path.
   *Recovery:* added a distinct override variable that outranks the derived anchor.
   **Prevention:** trace the new lever's precedence to the value it claims to change.
4. **Verified AC9 with a masking grep variant** — the AC's literal command returns 0.
   *Recovery:* reworded the ADR so the literal passes. **Prevention:** run the AC's bytes.
5. **Wiring assertions were file-scoped** — a one-line comment restored green after reverting the
   PR's core fix. *Recovery:* arm-scoped, comment-stripped extraction with exact counts.
   **Prevention:** anchor on the syntactic construct within the owning scope, never a file grep.
6. **`total_count` test re-typed the SUT's jq expression** — tautological; the drop-the-fallback
   mutation survived. *Recovery:* extract the expression from the arm and execute that.
   **Prevention:** never retype the thing under test into the test.
7. **A mutation did not land** (target line ends in `\`), and the suite reported the baseline —
   indistinguishable from "caught nothing". *Recovery:* asserted landing via `diff -q`.
   **Prevention:** already the documented rule; it fired correctly here.
8. **Vacuous RED** — the over-budget fixture omitted `page-2`, so `exit 1` came from a missing
   fixture rather than the gate. *Recovery:* completed the corpus so the un-gated path exits 0.
   **Prevention:** confirm the un-gated path *succeeds* before trusting a RED.
9. **My own comment kept AC3 red** — the explanatory comment quoted the forbidden imperative.
   *Recovery:* reworded to drop the literal. **Prevention:** `cq-assert-anchor-not-bare-token`.
10. **Perl extraction broke on apostrophes** in new comments (`jq's`), yielding programs that
    failed to **compile** (exit 3) — misreadable as the runtime crash (exit 5) under study.
    *Recovery:* anchored the extraction on the jq invocation, then on `fromdateiso8601`.
    **Prevention:** anchor quote-pairing extractions on a construct, not on global quote parity.
11. **PR body said "it does not close #6178"** — GitHub's close parser is word-boundary based and
    **negation does not help**; this would have auto-closed the issue that must stay open pending
    AC-V4. *Recovery:* reworded to "rather than closing issue #6178". **Prevention:** run the
    auto-close scan over the PR body, not just commit messages.
12. **Trap-ownership rule (c) tripped** — 3 new `mktemp` allocations tipped a file carrying 6
    pre-existing unowned ones. *Recovery:* one owning trap for all 9 (class-b census 99→98).
    **Prevention:** the full-suite exit gate caught it; keep running it before ship.
13. *(one-off)* `$PROBE.test.sh` where `$PROBE` already ended in `.sh` — bogus path, twice.
14. *(one-off)* `ci-deploy` hit my 300s timeout (rc=124) and was briefly read as a failure; it
    passes 184/184 at 900s.

## Related

- ADR-143 — Trust anchor for the cutover coexistence window
- ADR-106 §4 (amended) — scan bounding; the "never narrowed" clause retired for the runs scan
- [[2026-07-19-my-own-mutation-battery-was-the-false-confidence]]
- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]]
- [[2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr]]
