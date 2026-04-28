---
module: web-platform/chat-input
date: 2026-04-28
problem_type: test_failure
component: testing_framework
symptoms:
  - "Intermittent CI failure: 'Unable to find an element with the text: 50%' in chat-input-attachments.test.tsx"
  - "Test passes 14/14 in isolation but flakes 1/N in full-suite parallel run"
  - "Sibling tests in 'send with attachments' describe block also flake on different CI runs"
root_cause: async_timing
resolution_type: test_fix
severity: medium
tags: [vitest, flake, xmlhttprequest, manual-trigger, negative-space-assertion, cross-file-leak, user-event, react-batching]
---

# chat-input-attachments XHR-progress flake — manual-trigger pattern + negative-space assertion

## Problem

`apps/web-platform/test/chat-input-attachments.test.tsx > "send with attachments"
> "shows incremental progress during XHR upload"` flakes intermittently on CI.
Symptom: `await waitFor(() => expect(screen.getByText("50%"))...)` times out
even though the file passes 14/14 in isolation. First failure on CI run
24586094406 (#2524); recurred on post-merge of unrelated PRs #2516 and #2740
(comment thread on duplicate #2470). Sibling tests in the same describe block
were also reported as flaky on different runs.

## Root Cause

The pre-fix mock structure scheduled three real-clock timers:

```ts
mockXhr.send.mockImplementation(() => {
  setTimeout(() => mockXhr.upload.onprogress?.({ loaded: 50, total: 100 }), 0);
  setTimeout(() => mockXhr.upload.onprogress?.({ loaded: 100, total: 100 }), 10);
  setTimeout(() => mockXhr.onload?.(), 20);
});
```

On a slow CI worker (loaded vitest pool, GC pressure), all three timers fire
in the same macrotask flush. React's automatic batching then collapses the
three `setAttachments` updates (50 → 100 → cleared-on-onload) into a single
commit, and the intermediate "50%" text never appears in the DOM. The
`waitFor` polling never sees it.

This is the same class of issue as the `kb-chat-sidebar` family fixed by PR
#2819 — but PR #2819's fix targeted cross-file `fetch` stub leaks via
`originalFetch` capture-and-restore in `setup-dom.ts`. The XHR-progress flake
is a per-test timing race, not a cross-file leak; both layers are real and
both needed fixing.

## Solution

Two layers in one PR (#2976):

### Layer 1 — Manual-trigger pattern (primary fix)

Replace real-clock setTimeouts with explicit trigger functions called between
`await waitFor(...)` assertions:

```ts
let fireProgress50: () => void;
let fireProgress100: () => void;
let completeUpload: () => void;
mockXhr.send.mockImplementation(() => {
  fireProgress50 = () => mockXhr.upload.onprogress?.({ loaded: 50, total: 100 });
  fireProgress100 = () => mockXhr.upload.onprogress?.({ loaded: 100, total: 100 });
  completeUpload = () => mockXhr.onload?.();
});

// userEvent calls trigger xhr.send() synchronously inside Promise executor —
// triggers are populated by the time keyboard("{Enter}") resolves.
await userEvent.keyboard("{Enter}");

fireProgress50!();
await waitFor(() => expect(screen.getByText("50%")).toBeInTheDocument());

// Negative-space assertion: pin the regression class
expect(screen.queryByText("Uploaded")).not.toBeInTheDocument();

fireProgress100!();
await waitFor(() => expect(screen.getByText("Uploaded")).toBeInTheDocument());

completeUpload!();
```

Pattern was already proven on the file's existing `"shows 'Uploaded' text
when progress reaches 100%"` test (which was non-flaky); the fix extends it
to all six sibling tests in the describe block to prevent the same flake
class from surfacing in a sibling on the next CI run.

### Layer 2 — XHR cross-file leak guard (proactive)

Mirror PR #2819's `originalFetch` capture-and-restore for `XMLHttpRequest` in
`apps/web-platform/test/setup-dom.ts`:

```ts
const originalXHR: typeof XMLHttpRequest | undefined =
  typeof globalThis !== "undefined" ? globalThis.XMLHttpRequest : undefined;
// ...
afterAll(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  if (originalFetch && typeof globalThis !== "undefined") {
    globalThis.fetch = originalFetch;
  }
  if (originalXHR && typeof globalThis !== "undefined") {
    globalThis.XMLHttpRequest = originalXHR;
  }
  vi.useRealTimers();
  resetBrowserLikeGlobals();
});
```

Today the leak is **latent** — both XHR-stubbing files (`chat-input-attachments`,
`file-tree-upload`) use `vi.stubGlobal`, which `vi.unstubAllGlobals()` already
restores. The proactive `originalXHR` capture prevents a future raw
`globalThis.XMLHttpRequest = vi.fn(...)` assignment (the pattern used for
`fetch` in four `kb-layout-*` files today) from regressing the same class.

`apps/web-platform/test/setup-dom-leak-guard.test.ts` now asserts both the
capture token (`originalXHR`) AND the restore line
(`globalThis.XMLHttpRequest = originalXHR`) stay in the source, mirroring the
new symmetric assertion for `globalThis.fetch = originalFetch`.

## Why Not Fake Timers

`vi.useFakeTimers()` would also fix the timing race, but `@testing-library/user-event`
v14 internally calls `setTimeout(0)` for keystroke pacing. Mixing fake timers
with `userEvent` requires `vi.useFakeTimers({ shouldAdvanceTime: true })` plus
manual `vi.advanceTimersByTime()` between every `userEvent.type` /
`userEvent.keyboard`. The `await user.click()` / `await user.type` calls hang
otherwise — confirmed by:

- testing-library/react-testing-library #1197
- testing-library/user-event #833
- testing-library/react-testing-library #1198

The manual-trigger pattern keeps real timers everywhere and only controls the
XHR mock — strictly simpler. A top-of-file comment in
`chat-input-attachments.test.tsx` documents this trap so a future author
doesn't reach for fake timers.

## Generalizable Pattern: Negative-Space Assertion for Transient State

When fixing a flake test where the bug is "intermediate state X never
rendered," the post-fix assertions must distinguish gated from ungated. The
positive-space assertion (`getByText("50%")`) alone is insufficient — if a
future change re-introduces React batching, the brief intermediate render
during `waitFor` polling would still satisfy the assertion, then immediately
get replaced by "Uploaded".

Pin the regression class with a negative-space check **between** the two
state transitions:

```ts
fireProgress50!();
await waitFor(() => expect(screen.getByText("50%")).toBeInTheDocument());

expect(screen.queryByText("Uploaded")).not.toBeInTheDocument(); // <-- pin

fireProgress100!();
await waitFor(() => expect(screen.getByText("Uploaded")).toBeInTheDocument());
```

This is the same shape as the rule in
`knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`
("the test must distinguish gate-absent from gate-present") but applied to
React-render ordering rather than concurrency primitives. The two patterns
generalize: any test for transient state needs an intermediate-state
assertion that would fail if the state were skipped entirely.

## Prevention

- **For new XHR-progress tests:** start from the manual-trigger pattern; do
  not introduce real-clock `setTimeout(N)` for event scheduling.
- **For new tests on transient React state:** add a negative-space assertion
  between transitions to pin the intermediate render.
- **For new global-stubbing test files:** if a new global beyond `fetch` and
  `XMLHttpRequest` (e.g., `WebSocket`, `EventSource`, `Worker`) is stubbed
  via raw assignment in any file, extend the `setup-dom.ts` capture-restore
  pattern in the same PR — the `setup-dom-leak-guard.test.ts` drift assertions
  will catch the omission.
- **For sibling-test sweeps:** when fixing a flake, do NOT fix only the
  actively-failing test. Apply the fix to every sibling in the same describe
  block that shares the failure class (per `cq-vitest-setup-file-hook-scope`
  precedent and the `kb-chat-sidebar` family).

## Verification

- 14/14 isolated runs of `chat-input-attachments.test.tsx` pass
- 23/23 with the leak-guard suite (9 it.each rows, up from 6)
- 3/3 consecutive parallel runs of the full app suite — chat-input file was 0
  failures in every run (other unrelated test families surfaced their own
  pre-existing flakes; failure set shifted across runs, classic flake
  signature, no regressions introduced)

## Cross-References

- PR #2976 — this fix
- PR #2819 — `originalFetch` precedent that this PR mirrors for XHR
- Issue #2524 — primary failure report
- Issue #2470 — duplicate (broader symptom: "50% progress text times out in
  full-suite run")
- `knowledge-base/project/learnings/test-failures/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md` —
  architecture rationale for the `setup-dom.ts` capture-and-restore pattern
- `knowledge-base/project/learnings/test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` —
  the gated-vs-ungated assertion pattern that the negative-space check applies
  to React-render ordering
- `knowledge-base/project/learnings/2026-04-12-testing-transient-react-state-in-async-flows.md` —
  the manual-trigger pattern source (already documented for the same file's
  "Uploaded" test)
- `knowledge-base/project/learnings/ui-bugs/xhr-upload-progress-and-state-ordering-20260413.md` —
  context on why XHR-with-progress is the production design
- AGENTS.md `cq-vitest-setup-file-hook-scope` — the rule that places the new
  restore in `afterAll`, not `afterEach`
- AGENTS.md `cq-code-comments-symbol-anchors-not-line-numbers` — the rule the
  code comment cross-reference follows (refers to `originalFetch` by symbol)
- AGENTS.md `cq-raf-batching-sweep-test-helpers` — adjacent rule explaining
  why fake timers were not chosen

## Session Errors

**Error 1: Initial test rewrite missed sibling that already had partial-manual structure**

The plan AC stated "No `setTimeout(...)` calls remain in the 'send with
attachments' describe block (grep verification: `rg setTimeout` returns
zero)". My first rewrite pass touched the six explicitly-listed tests but
left:
- The existing `"shows 'Uploaded' text when progress reaches 100%"` test,
  which had a stray `setTimeout(0)` for the progress=100 trigger (the test
  was partially-manual already and was cited as the precedent pattern).
- A literal `setTimeout(0/10/20)` token inside an explanatory comment.

**Recovery:** ran `rg setTimeout test/chat-input-attachments.test.tsx` after
the rewrite, found 2 hits, swept both.

**Prevention:** when an AC specifies `rg <token>` returns zero, run that grep
**before** declaring the rewrite complete — don't assume sibling tests are
out of scope just because they were already partial. Apply the AC's
verification command as the loop terminator, not the final check. Same class
as `cq-when-a-command-exits-non-zero-or-prints` (treat the verification
command's output as load-bearing, not advisory).

**Error 2: Plan subagent initially cited line numbers in code comments**

Forwarded from session-state.md (plan phase, pre-compaction). Plan subagent
prescribed a code comment in `setup-dom.ts` that referenced `originalFetch`
by line number. Caught and corrected during the plan pass per
`cq-code-comments-symbol-anchors-not-line-numbers`.

**Recovery:** corrected to symbol-anchor reference (`originalFetch` by name).

**Prevention:** existing rule `cq-code-comments-symbol-anchors-not-line-numbers`
already covers this. The plan/deepen-plan skill could remind the subagent of
this rule before drafting code comments — minor enforcement gap, but the
human-loop catch was fast.

**Error 3: deepen-plan subagent could not spawn Task agents**

Forwarded from session-state.md. Inside the plan-pipeline subagent context,
the Task tool was not exposed, so the subagent could not delegate to research
sub-subagents as the deepen-plan skill prescribes.

**Recovery:** subagent fell back to direct WebSearch + library-source
verification, producing structurally equivalent external evidence.

**Prevention:** deepen-plan skill could document that when running inside a
nested subagent (e.g., one-shot plan-phase), Task may be unavailable, and
provide the WebSearch fallback explicitly. Low priority — the fallback path
worked and produced the same evidence quality.
