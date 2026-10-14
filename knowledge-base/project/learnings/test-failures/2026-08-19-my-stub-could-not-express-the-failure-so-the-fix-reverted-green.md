---
category: test-failures
module: sentry-iac
problem_type: test_failure
symptom: "Two shipped fixes revert cleanly with the whole suite green, because no fixture can express the failure they prevent"
issues: [7590]
date: 2026-08-19
---

# My stub could not express the failure, so the fix reverted green

## Problem

A PR shipped two fixes to `sentry-monitors-audit.sh`, both with tests, both
with a green suite. Reverting either left the suite green:

1. `curl_retry` re-sending a **non-idempotent POST** on a transport failure.
2. A 128 KB `MAX_ARG_STRLEN` ceiling in the pagination accumulator.

Neither was an oversight in *which* tests were written. Both were the fixture
space being structurally unable to reach the defect.

## Root cause

**Fix 1 — the stub ended in `exit 0`.** `mk_curl_stub` is a PATH-shimmed fake
that can express any HTTP status, any response header, any body. Its last line
was an unconditional `exit 0`, so `rc` inside `curl_retry` was `0` in every
fixture the suite owned. Every T18 case perturbed the *status* axis. The
transport axis — curl's own non-zero exit, e.g. `28` on `--max-time` — did not
exist as a thing a test could produce.

That axis is where the defect lived, and the code's own comment said so: a
timed-out POST whose write already landed server-side is the case observed in
production, whereas a status-bearing 5xx at least proves the server answered.

**Fix 2 — the fixtures were 90 bytes.** `T20` followed two pages and asserted
they merged. Both pages were ~90 B. The accumulator bug only fires when a single
argv entry exceeds `MAX_ARG_STRLEN` (32 × 4096 = **131072 B**), so reverting the
file-backed accumulator to
`acc=$(jq -n --argjson a "$acc" --argjson b "$body" '$a + $b')` stayed green.
Separately, dropping `?per_page=100` also stayed green, because the URL still
contained `cursor=` and that was the only thing asserted.

## Solution

Add the missing axis rather than more cases on the axis you already have.

- **Transport axis.** An optional 4th field, `exit_code`, on the stub's respond
  spec; non-zero means exit before writing headers or body, which is what a
  real `--max-time` abort leaves behind. `T18e` (safe GET, exit 28 → 3 attempts)
  and `T18f` (write, exit 28 → 1 attempt).
- **Two fixtures for a disjunction.** `curl_retry` marks a request unsafe by
  **either** an explicit `CURL_RETRY_UNSAFE=1` **or** an argv inference. One
  fixture satisfying both proves the set is non-empty and nothing else — drop
  either signal and it stays green. `T18f` fixtures each alone.
- **Stub the clock, but record its argv.** `sleep` is shimmed on PATH so the
  3-attempt test runs instantly, and the stub appends `"$*"` to a file which the
  test asserts equals `5 10`. A no-op `sleep` would have made the test fast and
  silently voided the backoff contract.
- **Fixture-size precondition.** `T20f` generates two 159 KB pages and asserts
  `page1_bytes > 131072` **before** running the SUT, failing as an explicit
  *fixture defect* otherwise. Without that, a later trim of the fixture would
  quietly turn `T20f` back into a duplicate of `T20`.

## Mutation evidence

Sandbox copies, each mutation `diff -q`-verified as landed, unmutated control
green at 36/36 first:

| Mutation | Axis | Result |
|---|---|---|
| remove the transport idempotency break | transport × unsafe | T18f RED |
| never retry on transport failure | transport × safe | T18e RED (1 attempt) |
| propagate `rc` out of `curl_retry` | never-exit contract | T18e RED (`rc=28`) |
| backoff 5 → 1 | backoff schedule | T18e RED (sleeps `1 2`) |
| ignore `CURL_RETRY_UNSAFE` | declaration alone | T18f RED, **inferred arm still 1/0** |
| ignore the argv inference | inference alone | T18f RED, **declared arm still 1/0** |
| revert to `--argjson` | accumulator | T20f RED (`rc=126`, died on page 1) |
| drop `?per_page=100` | page size | T20f RED — **`rc=0`, both pages fetched** |

The last row is the shape to remember: the mutation changed nothing observable
anywhere else in the suite. Only an assertion aimed directly at it can see it.

## The companion trap: a test that passes for a reason its name denies

In the same session, `assert-byok-rules-exist.test.sh` T6 was
`"missing SENTRY_PROJECT exits non-zero"`. The org-scoped URL migration removed
that variable's only consumer, so the `:?` guard went with it — and **T6 kept
passing**. With no fixture injected, the run reaches the live fetch and trips
the `SENTRY_API_HOST` guard instead. Non-zero for a different reason.

It surfaced only because a new T10 asserted the opposite ("runs with
`SENTRY_PROJECT` unset") and both were green. Two tests asserting contradictory
things while both pass means one is lying.

The fix is to anchor on the **message**, not just `rc != 0`:

```bash
if [[ $rc -ne 0 ]] && grep -q 'SENTRY_API_HOST must be set' <<<"$out"; then
```

Proof it is load-bearing: restoring the removed `SENTRY_PROJECT` guard reds
**both** T6 and T10; removing the `SENTRY_API_HOST` guard reds T6 alone with
`unbound variable` instead of the named message.

## Key insight

**Ask what your fixtures cannot express, not how many you have.** Three distinct
guards in one PR were vacuous for the same reason — the fixture space had no
member on the axis the defect lived on — and each looked like a well-tested
change. The tells: a stub whose exit status is a constant, a numeric threshold
whose fixtures are orders of magnitude below it, and an `rc != 0` assertion
where more than one code path can produce non-zero.

## Session Errors

- **I nearly shipped T6.** A passing test whose name described a guard that no
  longer existed. **Prevention:** when you delete a guard, grep the suite for
  the guard's name and confirm the test that covers it goes RED — a test named
  after a deleted guard must fail, and if it does not, it was never testing it.

## Related

- [2026-07-30-every-green-signal-i-had-certified-a-gate-with-six-fail-open-paths.md](../2026-07-30-every-green-signal-i-had-certified-a-gate-with-six-fail-open-paths.md)
  — the sibling case for PATH-shimmed fakes that dispatch on `$1` only. Same
  family: the seam sits above the code under test, so the query shape ships
  unpinned. This file adds the *exit-status* axis to that one's *argv* axis.
- [integration-issues/2026-08-19-a-vendor-brownout-is-not-a-flake-and-the-header-said-so-all-along.md](../integration-issues/2026-08-19-a-vendor-brownout-is-not-a-flake-and-the-header-said-so-all-along.md)
  — why the transport axis mattered here in the first place.
