---
module: KB Viewer / Type System
date: 2026-04-18
problem_type: integration_issue
component: tooling
symptoms:
  - "Variant added to SharedContentKind; file-preview + classify-response switches updated, shared page if-ladder silently accepts new variant without handler"
  - "CONTENT_TYPE_MAP and classifyByContentType drift silently when one is extended without the other — nothing but a jsdoc comment enforces parity"
  - "TextPreview HEAD-first fetch broke 2 tests that mocked global.fetch with a single-response factory"
root_cause: incomplete_setup
resolution_type: code_fix
severity: medium
tags: [typescript, discriminated-union, if-ladder, exhaustive-switch, config-parity, test-mocks, refactor, multi-agent-review]
---

# Learning: Widening discriminated unions must audit if-ladders, not just switches; config/classifier pairs need a parity test

## Problem

PR #2531 widened `SharedContentKind` to include `"text"` and extracted a shared
`classifyByContentType` classifier. The plan's Phase 5 exhaustiveness audit grepped
for `const _exhaustive: never` and verified the two switch-based consumers
(`classify-response.ts`, `file-preview.tsx`) had `case "text"` arms.

The audit missed the third consumer: `app/shared/[token]/page.tsx` used an
**if-ladder on `data.kind`** to dispatch render branches. The author added a
manual `{data?.kind === "text" && <TextPreview … />}` branch, so behavior was
correct. But the ladder has no compile-time exhaustiveness rail — a future
sixth variant will compile cleanly and render nothing on the shared page.

Separately, `CONTENT_TYPE_MAP` (in `kb-limits.ts`) and `classifyByContentType`
(in `kb-file-kind.ts`) are a two-table pair: extending one without the other
silently routes the new MIME through `"download"`. The only guard was a jsdoc
comment saying "extend both."

Review agents caught both gaps. A performance agent separately caught a P1:
`TextPreview` buffered the entire `.txt` body via `res.text()` before first
paint, and `MAX_BINARY_SIZE` permits 50 MB `.txt` uploads.

## Root Cause

1. **Exhaustive-switch grep doesn't cover if-ladders.** The `const _exhaustive:
   never` pattern only appears inside `switch`/`default`. Page-level JSX that
   dispatches via `{data?.kind === "X" && …}` chains is invisible to this grep
   and to the compiler. Widening a union is type-safe *only* where exhaustive
   narrowing is explicit.

2. **Parity comments are not parity tests.** The jsdoc on `kb-limits.ts`
   instructed extenders to update both `CONTENT_TYPE_MAP` and
   `classifyByContentType`. No code enforced it — a new entry on one side
   defaults to `"download"` on the other, silently.

3. **Network contract changed in isolation.** Adding a HEAD pre-flight to
   `TextPreview` without updating the 3 tests that mocked `global.fetch` with
   a single `mockResolvedValue` broke the tests — the mock responded the same
   way to HEAD and GET, so HEAD returned `text: undefined` and blew up the
   size check. Same failure class as `cq-raf-batching-sweep-test-helpers`
   (timer batching broke rAF-unaware tests), generalized to network mocks.

## Solution

### If-ladder → switch with `: never` rail

Convert any `data.kind`-dispatching JSX cascade to a `renderContent(data)`
helper that uses a `switch` with a `default: { const _exhaustive: never =
data; … }` arm. The compiler then fails on union widening.

```tsx
function renderSharedContent(data: SharedData) {
  switch (data.kind) {
    case "markdown": return <MarkdownRenderer content={data.content} />;
    case "pdf":      return <PdfPreview src={data.src} filename={data.filename} />;
    case "image":    return <img src={data.src} alt="..." />;
    case "text":     return <TextPreview src={data.src} filename={data.filename} />;
    case "download": return <DownloadCard {...data} />;
    default: {
      const _exhaustive: never = data;
      void _exhaustive;
      return null;
    }
  }
}
```

### Config-map ↔ classifier parity test

When a `Record<K, V1>` config drives a classifier that returns a second
type `V2`, encode the expected mapping as a table the test owns:

```ts
const EXPECTED_KIND_BY_EXT: Record<string, Exclude<FileKind, "markdown">> = {
  ".png": "image",
  ".pdf": "pdf",
  ".txt": "text",
  ".docx": "download",
  // …one entry per CONTENT_TYPE_MAP key
};

it("every CONTENT_TYPE_MAP entry has an expected kind in the parity table", () => {
  expect(Object.keys(CONTENT_TYPE_MAP).sort())
    .toEqual(Object.keys(EXPECTED_KIND_BY_EXT).sort());
});

it.each(Object.entries(EXPECTED_KIND_BY_EXT))(
  "classifyByContentType for %s maps to the expected kind",
  (ext, expected) => {
    const disposition = ext === ".docx" ? "attachment" : "inline";
    expect(classifyByContentType(CONTENT_TYPE_MAP[ext], disposition)).toBe(expected);
  },
);
```

Two assertions: presence (adding a key to the config without the table fails)
and correctness (classifier drift fails). Cheaper and louder than a jsdoc
comment.

### Pre-flight fetch → test-mock sweep

Before adding a HEAD (or OPTIONS, or any pre-flight) call, grep for the
component's existing `global.fetch = vi.fn().mockResolvedValue(...)` patterns
and rewrite each to be method-aware:

```ts
global.fetch = vi.fn((_url: string, init?: { method?: string }) => {
  if (init?.method === "HEAD") {
    return Promise.resolve({
      ok: true,
      headers: new Headers({ "content-length": "19" }),
    } as Response);
  }
  return Promise.resolve({ ok: true, text: () => Promise.resolve("...") } as Response);
}) as typeof fetch;
```

## Key Insight

The existing "update exhaustive switches when widening a union" rule
(integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md) is
necessary but not sufficient — if-ladders on the discriminator are a second
consumer class with weaker compile-time protection. Fixing the skill: grep
must also find `data.kind === "..."` and `data?.kind === "..."` chains, OR
the code must be refactored to remove if-ladders on discriminated unions.

Parity between two tables (config → classifier, enum → renderer, input
schema → output schema) degrades silently when only a comment enforces it.
Convert the comment into a table the test iterates, with both a
presence-check and a mapping-check assertion. This pattern is reusable for
any two-source-of-truth coupling.

Multi-agent review continues to earn its keep on refactor PRs, not just
feature PRs. Of 10 review agents spawned, performance-oracle caught the
50 MB buffer (P1), code-simplicity-reviewer + pattern-recognition caught
the dead narrowing (P1), architecture-strategist caught the missing rail
(P2), code-quality-analyst caught the duplicated JSX (P2). Each was a
real-world-shippable defect in green-CI code.

## Session Errors

1. **TextPreview HEAD-first broke existing test mocks** — Added HEAD size
   guard without updating `file-preview.test.tsx`'s three `global.fetch`
   mocks, which used a single `mockResolvedValue` factory. HEAD returned a
   response shape missing `text`, triggering the component's error fallback
   instead of rendering the body. Recovery: rewrote mocks as method-aware
   arrow functions. **Prevention:** When a component gains a pre-flight
   fetch (HEAD, OPTIONS, preflight), sweep its test file's `global.fetch =
   vi.fn()` patterns in the same edit. Same failure class as
   `cq-raf-batching-sweep-test-helpers`.

## Prevention

- After widening a discriminated union, grep for **three** consumer patterns,
  not one: (a) `const _exhaustive: never`, (b) `\.kind === "`, (c)
  `\?\.kind === "`. Any hit on (b) or (c) without a corresponding `case`
  handler is a latent silent-drop. Prefer refactoring if-ladders to
  `switch`-with-rail helpers.
- When a two-table coupling exists (config → classifier, schema → handler,
  enum → renderer), write a presence+mapping parity test that iterates the
  config keys. Do not rely on jsdoc.
- When a component grows a pre-flight fetch, update its test-mock factories
  to be method-aware in the same commit. Single-response `mockResolvedValue`
  patterns break on the second request.
- Continue to run multi-agent review on refactor PRs — the defect classes
  they catch (dead-code narrowing, missing exhaustiveness rails,
  progressive-rendering gaps) still slip through green CI.

## Cross-references

- `knowledge-base/project/learnings/integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md` — original exhaustive-switch learning (scope: switches only; this learning extends to if-ladders)
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — multi-agent review catches P1s in shipped code
- AGENTS.md rule `cq-raf-batching-sweep-test-helpers` — analogous test-helper-sweep rule for rAF/timer changes
- AGENTS.md rule `cq-progressive-rendering-for-large-assets` — the 50 MB TextPreview buffer is the exact failure mode this rule targets
- PR #2531, commit `cb2fc425` (review fixes)

## Tags

category: integration-issues
module: KB Viewer / Type System
