# Learning: when a render gate uses `.some(predicate)`, write a test that distinguishes it from `.length > 0`

## Problem

PR #3276 added a strip-rendering gate `routeSource && respondingLeaders.some((id) => id !== CC_ROUTER_LEADER_ID)`. The test suite (5 tests, RED→GREEN, deepen-planned) had T2/T3 exercising the truthy branch and T4 exercising the falsy `routeSource === null` short-circuit. All 5 passed RED→GREEN as expected.

`test-design-reviewer` flagged at PR review: no test exercised `routeSource="auto"` with `respondingLeaders=["cc_router"]` only. Without it, the gate could regress to `respondingLeaders.length > 0` and the suite would pass identically — the `some()` predicate was not load-bearing in the test suite, only in the spec.

## Solution

T6 added: `routeSource: "auto"` + assistant message with `leaderId: "cc_router"` only + `activeLeaderIds: []`. Asserts `queryByTestId("routed-leaders-strip")` is null. T6 fails if the gate is weakened to `length > 0` — the strip would render with an empty leader list.

```ts
it("T6 — strip is hidden when only cc_router responded (load-bearing some() predicate)", async () => {
  wsReturn = createWebSocketMock({
    messages: [
      { id: "u1", role: "user", content: "hello", type: "text" },
      { id: "a1", role: "assistant", content: "handled", leaderId: "cc_router", type: "text" },
    ],
    routeSource: "auto",
    activeLeaderIds: [],
  });
  await renderFull();
  expect(screen.queryByTestId("routed-leaders-strip")).not.toBeInTheDocument();
});
```

## Key Insight

**TDD's RED-distinguishes-gate-absent-from-gate-present rule applies to predicate refinements, not just to introducing a new gate.** Existing AGENTS.md rule `cq-write-failing-tests-before` cites this for sequencing primitives ("count === 2 while two slots are held"). The same logic applies when a render gate refines `.length > 0` into `.some(specificPredicate)`: at least one test must input a value that satisfies the trivial counter but not the specific predicate. Otherwise the predicate is decoration — the test suite tolerates either form.

The `cc_router`-filter case is a mirror of the bare-Concierge regression #3225 the plan was designed to prevent: there too, an "obvious" predicate (don't render Concierge) was load-bearing in the spec but easy to weaken without test coverage.

## Why deepen-plan missed it

The deepened plan correctly identified that T4 was "PASS-already" pre-implementation (the strip was always gated on `routeSource`). It did not extend that audit one step further: which other branches of the gate are not load-bearing? `routeSource=auto + responders=[cc_router only]` is the same shape — the `some()` predicate is not exercised in any direction by T1-T5.

## Prevention

When a code change introduces or modifies a render gate of the form `cond && collection.some(predicate)`:

1. List the falsy-branch inputs that satisfy `cond && collection.length > 0` but FAIL the predicate.
2. For each, write a test asserting the gate evaluates false.
3. If zero such inputs exist, the `.some(predicate)` is equivalent to `.length > 0` — simplify the code rather than write a vacuous test.

Apply at plan-time (in the Phase 1 RED test list), not at review-time. Reviewer catches are a fallback, not the design.

## Session Errors

1. **Plan-file Edit raced with sed** — Recovery: re-read before re-edit. Prevention: when interleaving `sed -i` with `Edit`, the Edit tool's "modified since read" guard is sufficient; just re-read on failure.
2. **Bash CWD did not persist between calls** — Recovery: chain `cd <abs> && <cmd>` in a single Bash call. Prevention: already covered by AGENTS.md.
3. **`user-impact-reviewer` and `semgrep-sast` hit Anthropic usage limits during review** — Recovery: security-sentinel's verdict ("single-user-incident threshold not engaged for pure presentational refactor") plus manual verification of the plan's `## User-Brand Impact` section + plan-time CPO sign-off covered the gap. Prevention: when a plan declares `single-user incident` BUT the actual diff has no data/auth/credentials/PII surface, the threshold is over-declared and the gating reviewer can be safely substituted by security-sentinel + manual section-readback. Capture this pattern in the user-impact-reviewer agent definition so future invocations include the substitution rule.

## Tags

category: best-practices
module: test-design
related: cq-write-failing-tests-before, hr-weigh-every-decision-against-target-user-impact, #3225, #3251
