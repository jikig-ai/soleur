---
module: cc-soleur-go
date: 2026-05-07
problem_type: integration_issue
component: server-prompt-builder + dispatcher-wire-path
symptoms:
  - "User would see 'I see 0 pages — too long' on every triggering case instead of the actual page count"
  - "tsc --noEmit clean, full vitest suite green, but the user-facing copy is wrong"
root_cause: typed_optional_field_wire_drop
severity: critical
tags: [typescript, dispatcher, wire-path, multi-agent-review, user-impact-reviewer]
related_prs: [3430, 3429, 3438]
related_issues: [3429, 3436, 3437, 3438]
---

# Learning: typed-optional-field wire-drop survives compile + tests, caught only by user-impact-reviewer

## Problem

PR #3430 added a new HARD class `too_many_pages` to the Concierge PDF
extract-error partition. The directive copy interpolates a page count:
`"I see {N} pages — that's too long for me to read in one go."` The page
count flows from `extractPdfMetadata` (resolver) → `documentExtractMeta:
{ numPages: 403 }` (resolver return value) → through the dispatcher →
into the runner's `BuildSoleurGoSystemPromptArgs.documentExtractMeta?.numPages`
→ rendered into the directive.

Every link of that chain was implemented and unit-tested:

- `kb-document-resolver.ts` set `documentExtractMeta` correctly (tested in
  `kb-document-resolver-pdf-page-gate.test.ts`).
- `soleur-go-runner.ts` consumed `args.documentExtractMeta?.numPages`
  correctly (tested in `pdf-unreadable-directive.test.ts` /
  `cc-concierge-pdf-summarize-e2e.test.ts`).
- The intermediate `cc-dispatcher.ts dispatchSoleurGo` hop did NOT plumb
  the field at all. It destructured a fixed field set from
  `DispatchSoleurGoArgs`, then explicitly enumerated the same set into
  `runner.dispatch({...})`. `documentExtractMeta` was missing from BOTH
  the `args` interface AND the destructure-then-pass call site.

**Compile passed** because every interface in the chain had
`documentExtractMeta` declared as `?: ...` (optional). **Test suite
passed** because no integration test exercised the full
resolver→dispatcher→runner→prompt path with a real `numPages` value.
The runner's `args.documentExtractMeta?.numPages ?? 0` defensive read
covered for the missing field — by reading 0.

User-visible outcome (had it shipped): every Manning-shaped PDF would
have produced `"I see 0 pages — that's too long for me to read in one
go"`. The whole point of the bridge fix — naming the page count
specifically so the user gets a meaningful refusal — was silently
defeated.

## Solution

Two structural changes (commit `e473ecf7` after multi-agent review of
PR #3430):

1. **Add the field at every wire hop.** `DispatchSoleurGoArgs` (the
   ws-handler-facing typed args), the destructure inside
   `dispatchSoleurGo`, and the `runner.dispatch({...})` call site.
   Three single-line edits in `apps/web-platform/server/cc-dispatcher.ts`.

2. **Pin the wire path with a regression test.** Added
   `"forwards documentExtractMeta to runner.dispatch (#3429 wire-drop
   regression — caught by user-impact-reviewer on PR #3430)"` to
   `apps/web-platform/test/cc-dispatcher.test.ts`. The test stubs
   `runner` via `__setCcRunnerForTests`, calls `dispatchSoleurGo` with
   `documentExtractMeta: { numPages: 403 }`, and asserts the value
   reaches the runner's `dispatch` arg. A future field-addition that
   forgets the dispatcher hop now fails this test.

## Key Insight

### Insight 1 — Optional-and-typed fields silently drop through explicit destructure-and-pass hops

TypeScript's `?` on every interface field protects the type-safety
contract but defeats wire-completeness checking. When a destructure
omits a field, the rest of the destructure shape is unaffected; when
the explicit-pass call site omits the same field, no compile error
fires. The omitted field becomes `undefined` at the destination, and
defensive defaults (`?? 0`, `?? ""`, `?? null`) absorb the omission
into a "valid but wrong" output.

**Generalization**: When threading a new typed field through more than
one hop in a dispatch chain (interface → destructure → forward), grep
for every mention of the *most-derived consumer interface name* and
add the field at each site in the same edit cycle. Same class as
`cq-union-widening-grep-three-patterns` (consumer-side) and
`cq-ref-removal-sweep-cleanup-closures` (cleanup-closures), but for
the *forward-direction* dispatch chain.

### Insight 2 — `user-impact-reviewer`'s "name artifact + name vector" methodology reliably catches wire-drops; LLM-architecture review and unit tests do not

Out of 11 review agents on this PR:

- `architecture-strategist`, `pattern-recognition-specialist`,
  `code-quality-analyst`, `security-sentinel`, `data-integrity-guardian`,
  `agent-native-reviewer`, `git-history-analyzer`, `performance-oracle`,
  `test-design-reviewer`, `semgrep-sast` — **all cleared the wire-drop**.
  Each found other useful issues (P2/P3 severity), but none caught the
  P1.
- `user-impact-reviewer` — **caught the P1** explicitly by enumerating
  "if `documentExtractMeta` is dropped between resolver and runner
  (wire drift)" as a concrete failure-mode artifact, then verifying
  against the diff: `cc-dispatcher.ts` does not destructure or forward
  `documentExtractMeta`.

The methodology that found it is the user-impact-reviewer's mandate:
"name a concrete user-facing artifact (here: the directive copy
"I see {N} pages") and enumerate every vector by which the artifact
could fail (here: wire drift in the dispatcher hop)." This forces a
trace through the actual dispatch chain, not a check of any single
file's local correctness.

**Generalization**: Plans with `single-user incident` brand-survival
threshold MUST invoke `user-impact-reviewer` at review time. Other
review agents check local properties (correctness of one file, taste,
performance bounds); user-impact-reviewer checks end-to-end user-facing
outcomes via concrete vectors. The two are complementary, not
redundant. See also
`knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
and
`knowledge-base/project/learnings/2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md`.

### Insight 3 — Lifecycle-of-typed-data tests beat unit tests for wire chains

Every unit test on the resolver and the runner separately passed.
Unit tests are local — they verify "given the right input, this
component produces the right output." Wire chains have integration
properties: "given a producer in component A, the field survives
hops B → C → D unmodified." This requires a test that drives the
producer (or stubs it) and asserts on the consumer's view of the
field.

The added regression test (`forwards documentExtractMeta to
runner.dispatch`) is a lifecycle-of-typed-data test: it stubs the
runner so the assertion can read `dispatch.mock.calls[0][0]`, drives
`dispatchSoleurGo` with the field, and asserts the field's identity
at the consumer boundary. This is the cheapest test that closes the
wire-drop class for this specific field.

**Generalization**: Whenever a typed field crosses more than one
explicit-pass call site, write at least one test that asserts the
field's identity at the consumer boundary by stubbing the consumer
and inspecting its received args. Unit-tested-in-isolation correctness
of producer + consumer is not sufficient.

## Session Errors

1. **`vi.doMock` mock leaks across describe blocks in same file** —
   The `lazy_import_failed` test used `vi.doMock("pdfjs-dist/...")`
   to make the lazy import throw, then `vi.doUnmock` + `vi.resetModules`
   to clean up. The mock leaked into the subsequent `extractPdfMetadata`
   describe block (and even into earlier `extractPdfText` tests under
   vitest's hoisting), causing 8 cascading test failures.
   **Recovery**: split the mock-based tests into a dedicated file
   (`pdf-text-extract-mocked.test.ts`) so vitest's per-file isolation
   handles containment.
   **Prevention**: when a test needs to mock an in-process dynamic
   import via `vi.doMock`, isolate the test in its own file. Same
   pattern as the existing `cc-concierge-pdf-summarize-e2e.test.ts`
   (separate file for tests that mock `@/server/pdf-text-extract`).

2. **`vi.useFakeTimers()` + `vi.advanceTimersByTimeAsync()` could not
   advance a setTimeout queued behind an `await import()`** —
   First version of the metadata-timeout test used fake timers; the
   inner `loadingTask.promise` was a real never-resolving Promise,
   the timeout setTimeout was queued in the fake-timer pool, but
   `advanceTimersByTimeAsync(METADATA_READ_TIMEOUT_MS + 100)` did
   not advance time enough to fire the inner setTimeout — vitest's
   5s test default fired first and the test hung.
   **Recovery**: switched to real timers with an explicit per-test
   timeout cap (`{ timeout: METADATA_READ_TIMEOUT_MS + 2000 }`).
   Pays 3s of wall-clock once per suite run.
   **Prevention**: when a SUT does `await import("...")` followed by
   a `Promise.race([..., setTimeout(...)])`, the dynamic-import
   microtask defers the setTimeout queue past the
   `advanceTimersByTimeAsync` trigger window. Real timers are the
   reliable shape; document the wall-clock cost in the test comment.

3. **Mock factory on the consumer's import surface forgot to spread
   the real module** — `cc-dispatcher-concierge-context.test.ts`
   mocked `@/server/pdf-text-extract` and listed only the symbols
   the test then-current code used (`extractPdfText`). When the PR
   added `extractPdfMetadata` + `LARGE_PDF_PAGE_THRESHOLD` imports
   to `kb-document-resolver.ts`, the mock factory's missing exports
   surfaced as `undefined` at the call site → "is not a function"
   → outer try-catch → returned `read_failed` instead of
   `oversized_buffer`.
   **Recovery**: extended the mock factory inline; later refactored
   both this file AND `kb-document-resolver-pdf-page-gate.test.ts`
   to `vi.importActual` + spread + override-only-the-spies, so future
   field/symbol additions stay in lockstep with source.
   **Prevention**: prefer `vi.mock(path, async () => { const actual =
   await vi.importActual<...>(path); return { ...actual, [overrides]
   }; })` over enumerating module exports manually. Same class as
   `cq-raf-batching-sweep-test-helpers` and the data-layer mock chain
   sweep — but for module mocks instead of method chains.

4. **`kb-pdf-cap-alignment` drift-guard regex caught the new metadata
   ceiling literal** — Originally wrote
   `METADATA_READ_BYTE_CEILING_BYTES = 60 * 1024 * 1024`, which the
   `/\d+\s*\*\s*1024\s*\*\s*1024/` drift-guard test in
   `kb-pdf-cap-alignment.test.ts` rejected as a forbidden shadow
   constant for the extractor cap (Hypothesis A regression guard from
   #3337/#3338).
   **Recovery**: switched to bit-shift form `60 << 20` (later `40 << 20`
   per perf-oracle review). Documented inline that the bit-shift
   sidesteps the drift-guard intentionally because the metadata-read
   ceiling is a SEPARATE concern from the extractor cap.
   **Prevention**: when introducing a new byte cap in a file under a
   drift-guard, read the guard's regex first and pick a shape that
   doesn't trip it. Bit-shift `n << 20` (== n MiB) is a clean shape
   for byte caps and self-documents the unit.

5. **P1 wire-drop in `cc-dispatcher.ts dispatchSoleurGo`** — The
   dispatcher destructured fields explicitly and missed
   `documentExtractMeta`; runner saw `undefined`; would have rendered
   "I see 0 pages" on every triggering case. Caught by
   `user-impact-reviewer` post-implementation.
   **Recovery**: plumbed the field through the args interface,
   destructure, and `runner.dispatch()` invocation; added regression
   test `cc-dispatcher.test.ts > forwards documentExtractMeta to
   runner.dispatch`.
   **Prevention**: see Insight 1 + Insight 3 above. Add a
   lifecycle-of-typed-data test whenever a typed field crosses more
   than one explicit-pass dispatch hop.

6. **Misleading test name `lazy_import_failed`** — The test in
   `pdf-text-extract-mocked.test.ts` was titled
   `"returns { error: 'lazy_import_failed' } when getDocument throws"`
   but actually exercised the post-import-throw path (which surfaces
   as `parse_error`). `vi.mock`'s factory IS the import — vitest
   invokes it synchronously, errors propagate, and inducing import
   REJECTION (the actual `lazy_import_failed` branch trigger) is
   structurally impossible with this harness.
   **Recovery**: renamed the describe block + test to honestly
   reflect "post-import getDocument throw → parse_error path"; left
   true `lazy_import_failed` direct coverage as an open follow-up
   (#3438 stays open).
   **Prevention**: when a test name promises coverage of a specific
   code path, verify the test actually exercises that path before
   merging. False-coverage signals are worse than acknowledged gaps.

## Tags
category: integration_issue
module: cc-soleur-go
