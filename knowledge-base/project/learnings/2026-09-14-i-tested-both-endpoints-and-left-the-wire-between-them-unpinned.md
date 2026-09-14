---
module: System
date: 2026-09-14
problem_type: test_failure
component: testing_framework
symptoms:
  - "Reverting the PR's central change left the whole suite green at 66/66"
  - "A diagnostic that never throws could still hang, escalating a non-blocking failure into a blocking one"
  - "A repo-global ratchet reddened CI that ten file-selected targeted suites could not see"
  - "A helper unit-tested in isolation with nothing asserting it was ever called"
root_cause: missing_validation
resolution_type: test_fix
severity: high
synced_to: [review, work]
tags: [seam, wire-vs-endpoints, mutation-testing, ratchets, diagnostics, timeout, log-injection]
---

# I tested both endpoints and left the wire between them unpinned

## Problem

#7969: `live-verify` emitted `CANT-RUN:for: Timeout 20000ms exceeded — waiting for
getByRole('textbox').first() to be visible`. Consistent with three causes,
distinguishes none. PR #8092 added a helper that reports the page state instead.

The helper was good. **Everything around it was wrong in ways a green suite could
not see**, and a six-agent review found sixteen findings — every one in the
verification or in what the diagnostic could *do* on the failure path. None in
the field choice.

## Key insight — three classes, each reusable

### 1. The endpoints were asserted and the WIRE was not

`waitFailureState` had eight unit tests. The two call sites were inline
`try/catch`. **Reverting either call site to a bare `await …waitFor(…)` left the
whole suite green at 66/66** — a unit test observes the helper, never whether
anything calls it.

This is not "add a test for the call site". A unit test *structurally cannot*
see a call site. Two things are needed:

- a **seam** — extract the wiring into a function, so the wiring itself is
  drivable (`awaitVisibleOrDiagnose`); and
- a **source-level assertion** that no bare form survives outside the seam,
  comment-stripped and anchored on the call form, because the file documents
  the very construct it forbids (`cq-assert-anchor-not-bare-token`).

Litmus for any PR: *name the edit that reverts this PR's central change. Which
test reds?* If the answer is none, the PR's thesis is pinned by nothing.

### 2. "Never throws" and "never hangs" are different invariants, and only one was stated

`page.title()` and `Locator.count()` accept **no timeout** and evaluate in the
renderer. `safe()` bounded exceptions and not time.

The failure mode is the part worth carrying: a wedged renderer is *one of the
hypotheses the diagnostic exists to separate*. Unbounded, it would blow the
job's `timeout-minutes`, emit **no RESULT line at all**, and the workflow
escalates that absence to `BLOCK=1`.

> A diagnostic on the failure path can convert a clean non-blocking failure into
> a blocking one carrying **less** information than the thing it replaced.

So for any code that runs *only* when something has already failed, the contract
is **never throws AND always returns**. And the fixture must model a HANG
(`new Promise(() => {})`), not only a rejection — a rejection-only fake pins the
wrong half.

### 3. Repo-global ratchets are invisible to file-based suite selection

Twice this session, CI reddened on a ratchet that every targeted suite missed:
`no-control-regex 19→20` here, and three on #7997 (`guard-vacuity-floor`,
`lint-diagnosis-claims`, `fixture-relative-assert`).

The cause is structural, not carelessness. Targeted suites are chosen by
grepping which suites *reference the changed files*. A ratchet counts a property
across the whole tree and references **nothing** — so that selection method can
never find one. It is a blind spot of the method, not of the effort.

Practical rule: a change that adds a test, a floor, an assertion, a regex, or an
operator-facing message should expect to move a repo-global counter, and the
remedy is the code, never the baseline — these ratchet DOWN only.

## Solution

| defect | fix |
|---|---|
| the wire unpinned | `awaitVisibleOrDiagnose` seam + a comment-stripped source guard |
| never-hangs unstated and untrue | every field races a 3s ceiling; fixture models a hang |
| a path segment can be a credential | allowlist the emitted path, reduce anything else to its first segment |
| `JSON.stringify` is a C0-only strip | scrub U+2028/U+2029/DEL before stringify (escapes only) |
| `nav.status()` throws on a closed target | wrapped — the throw skipped `signOut()`, leaving a **production** principal's session alive |
| the diagnostic re-derived `"textbox"` independently of the wait | one exported `COMPOSER_ROLE`, asserted by recording what the page was asked for |
| the signal landed on a green job | `::warning::` + full reason in the step summary |

Mutation-verified, control green 91/91: nine mutants that previously survived
now redden, including reverting the call site and reverting the redaction.

## Session Errors

**1. I inferred a commit rate from a count.** Seeing "17 commits behind" I
concluded main moved ~17 commits/hour and called auto-merge structurally unable
to converge. Measured: **0.4 commits/hour**, 43-minute median gap, CI 26–39 min.
The commits had accumulated over two days.
**Prevention:** a count is not a rate; divide by a measured span before diagnosing.

**2. I claimed path truncation guards against a credential in the URL.** It
guards the query and fragment. A path SEGMENT can itself be the credential
(`/shared/<token>`), and no redaction rule matches those.
**Prevention:** name the component the control actually covers, not "the URL".

**3. I claimed `redact()` backstops `?code=`.** Its rules cover
`access_token|refresh_token|provider_token|apikey` — **not** `code=`, which is
what Supabase PKCE uses. The path cut was the sole control, described as a
second line of defence.
**Prevention:** read the rule list before citing it as a backstop.

**4. I called `rail` noise in the composer context.** It is the most
discriminating field there: `rail=1 textboxes=0` is "shell hydrated, composer
missing"; `rail=0` is "shell never hydrated". Deleting it would have re-merged
two causes.
**Prevention:** before calling a field redundant, state which two hypotheses it
separates.

**5. My `scrubLine` shipped a control-char regex** that tripped
`no-control-regex` and moved a down-only ratchet.
**Prevention:** see class 3 — expect new regex/messages to move a global counter.

**6. I armed a duplicate monitor** on a target one was already watching.
**Prevention:** the supersede hook lists live watches; stop the old one first.

**7. My first M8 mutation was contrived** — it kept the seam call in a dead
`if (false)` branch, so it proved nothing and reported SURVIVED.
**Prevention:** a mutation must leave a *working, weaker* program; assert it
lands on the construct, not merely that bytes changed.

## Related

- [[2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live]] — same session, #7997; the prefix-pin and call-site-never-reached classes
- [[2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran]]
- #7969 (open — the underlying CANT-RUN is not fixed), PR #8092, #5840 (merge-queue BEHIND race)
