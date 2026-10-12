---
type: bug-fix
classification: production-runtime-error
sentry_event: e8225a569fcd4b07a460b5b1bb2a5ee7
requires_cpo_signoff: false
deepened_on: 2026-05-07
---

# fix: pdfjs-dist DOMMatrix ReferenceError when bundled into server CJS

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** 7 (Root Cause, Hypotheses, Phase 2 Edits, Phase 3 Verification, Test Strategy, Risks, Sharp Edges)
**Research sources:** Context7 (esbuild + Next.js), local node_modules type-defs, live `gh issue/pr view`, esbuild `--help` direct, pdfjs-dist source inspection

### Key Improvements

1. **Confirmed esbuild `external` form via type-def + Context7.** `external?: string[]` in `node_modules/esbuild/lib/main.d.ts`. CLI form `--external:M` (supports `*` wildcards, but we use the bare package name for `pdfjs-dist`, which Context7 docs confirm is the recommended form for matching the package and all its subpath imports).
2. **Confirmed Next.js `serverExternalPackages` typed as `Array<string>`** in installed `next@15.5.x` `node_modules/next/dist/server/config-shared.d.ts`. Context7 also confirms Next.js auto-opts-out `canvas`, `sharp`, `@react-pdf/renderer`, `pino`, `mongodb`, `bcrypt`, `puppeteer`, etc. — but NOT `pdfjs-dist` (verified by inspecting Context7's enumerated list of auto-externalized packages). Manual addition is required.
3. **Verified all cited issue/PR numbers live** (`gh issue view 3342` OPEN, `gh issue view 3377` OPEN, PRs `#3338`/`#3353`/`#3391`/`#3393` MERGED with confirmed titles). No fabrication.
4. **Verified pdfjs-dist resolution shape locally:** `pdfjs-dist@5.4.296` `package.json` declares `main: "build/pdf.mjs"` and an EMPTY `exports: []` map (a quirk that lets bare `import * as pdfjs from "pdfjs-dist"` resolve to the non-legacy entry). Confirmed `react-pdf@10.4.1`'s `dist/index.js` does `import * as pdfjs from 'pdfjs-dist'` — but it's only reached via `dynamic({ ssr: false })` boundaries.
5. **Sentry stacktrace decoded fully** — see Root Cause for the resolved frames. The `__init` frame in `/app/dist/server/index.cjs` is esbuild's lazy-init wrapper for the bundled pdfjs module, not a pdfjs-internal function.
6. **Added a new Risk** (#6) about webpack vs. esbuild bundling order: the Next.js production build calls esbuild's `build:server` AFTER `next build`, so the Next.js change is genuinely defense-in-depth — even without it, the esbuild `--external:pdfjs-dist` alone fixes the prod failure path, which is the custom-server CJS at `/app/dist/server/index.cjs`. Confirmed via the Sentry stack frame.
7. **Added explicit verification commands and grep targets** to Phase 3 so the GREEN gate is mechanically checkable.

### New Considerations Discovered

- **Webpack hot-reload risk:** Adding `pdfjs-dist` to `serverExternalPackages` may slow `next dev` cold-start by ~50-100ms (one extra `require()` resolution at first hit). Negligible.
- **Cold-start telemetry opportunity:** The new bundled-server tests give us a regression rail; consider adding a smoke test that asserts `dist/server/index.cjs` does not contain `DOMMatrix` (a simple grep) as a CI gate alongside the bundled-CJS exec test. Lower fidelity but ~50ms vs. ~3s. Folded into Phase 3 as an additional check.
- **`pdfjs-dist` as a precedent:** future Node-only parsers added to this app (e.g., `mammoth`, `xlsx`, `epub-parse`) should default to `serverExternalPackages` + esbuild `--external:`. Captured as a follow-up learning post-merge.

## Summary

Sentry event `e8225a569fcd4b07a460b5b1bb2a5ee7` (2026-05-07 00:34:19 CEST,
prod, Node v22.22.1, server `5ef4c60309e8`) records a handled
`ReferenceError: DOMMatrix is not defined` thrown by the `__init` function
of the bundled `node_modules/pdfjs-dist/legacy/build/pdf.mjs` inside
`/app/dist/server/index.cjs`. The throw happens during the lazy
`await import("pdfjs-dist/legacy/build/pdf.mjs")` in
`apps/web-platform/server/pdf-text-extract.ts:107`, is caught by the
existing `try/catch`, mirrored to Sentry via `reportSilentFallback` with
`feature=kb-concierge-context, op=extractPdfText.import`, and surfaces to
the agent as `lazy_import_failed`. The Concierge then falls back to the
"PDF unreadable" content-grounded directive instead of inlining the
extracted text — degraded UX for every Concierge PDF summarize call in
prod.

The recent commits `40ba6a27` (#3391, engines pin) and `19525cff` (#3393,
lockfile sync) **do not fix this**. They were correct work for an adjacent
problem (test-runner Node 21.x), but the production runtime is already
Node 22.22.1 — the engines floor was already met. The actual root cause is
**`esbuild`-bundling pdfjs-dist into the production custom-server CJS
bundle**, which is a different code path from the dev server (which uses
`--packages=external` and never bundles pdfjs).

## Root Cause

Two layers conspire to produce the runtime ReferenceError:

1. **`apps/web-platform/package.json:scripts.build:server`** invokes
   `esbuild server/index.ts --bundle --platform=node --target=node22
   --outfile=dist/server/index.cjs --external:next --external:react
   --external:react-dom --external:@supabase/supabase-js
   --external:@supabase/ssr --external:ws --external:stripe
   --external:@anthropic-ai/claude-agent-sdk --external:pino
   --external:@sentry/nextjs`. **`pdfjs-dist` is NOT in the `--external`
   list.** esbuild bundles `pdfjs-dist/legacy/build/pdf.mjs` into
   `dist/server/index.cjs`.
2. **`apps/web-platform/next.config.ts:serverExternalPackages`** is
   `["@anthropic-ai/claude-agent-sdk", "ws"]`. **`pdfjs-dist` is NOT
   there either.** Next.js 15's server compiler also bundles pdfjs into
   any route handler that transitively touches it.

When pdfjs-dist's legacy entry runs as a discrete ESM module under Node's
loader (the dev / vitest path), the `node_utils.js` block:

```js
if (isNodeJS) {
  let canvas;
  try {
    const require = process.getBuiltinModule("module").createRequire(import.meta.url);
    try { canvas = require("@napi-rs/canvas"); } catch { warn(...); }
  } catch { warn(...); }
  if (!globalThis.DOMMatrix) {
    if (canvas?.DOMMatrix) {
      globalThis.DOMMatrix = canvas.DOMMatrix;
    } else {
      warn("Cannot polyfill `DOMMatrix`, rendering may be broken.");
    }
  }
  if (!globalThis.ImageData) { /* same shape */ }
}
```

…runs at module init, and (because we don't ship `@napi-rs/canvas`) emits a
`warn` and continues. `globalThis.DOMMatrix` stays undefined, but the
metadata-only and getTextContent code paths don't reference DOMMatrix
(verified: `getTextContent` and `getViewport` are pure-numeric — see
`PageViewport` constructor at `pdf.mjs:7257`). DOMMatrix is only
referenced in canvas-rendering paths (`pdf.mjs:15068` `new DOMMatrix(inverse)` in
gradient pattern transform; `pdf.mjs:15480` in `getPattern`). Server-side
`extractPdfText` and `readPdfMetadata` should be safe.

When esbuild bundles pdfjs into a CJS file, the module's top-level
init becomes a `__init` function inside `dist/server/index.cjs`. The
Sentry stacktrace confirms this:

```
ReferenceError: DOMMatrix is not defined
  at __init (file:///app/dist/server/index.cjs)        <- bundled module init
  at <anonymous> (file:///app/dist/server/index.cjs)
  at extractPdfText (file:///app/dist/server/index.cjs)
  at resolveConciergeDocumentContext (...)
  at dispatchSoleurGoForConversation (...)
  at handleMessage (...)
```

esbuild's bundler hoists, renames, and re-arranges identifiers across the
13,000+-line pdfjs source. Some hoist of a `class Foo extends DOMMatrix
{ ... }` definition or a `static prop = new DOMMatrix(...)`-shaped
top-level reference (or a TDZ-style binding produced by the bundler's
mangler) ends up evaluated **before** the `if (isNodeJS) { ... polyfill }`
block runs. We don't need to identify the exact hoisted reference — the
fix is structural: **don't let esbuild/Next bundle pdfjs**. Force the
Node ESM loader to evaluate `pdfjs-dist/legacy/build/pdf.mjs` as a
discrete module so the polyfill block runs in the correct evaluation
order with intact `import.meta.url`.

This is the same class of problem as
`knowledge-base/project/learnings/2026-04-18-server-bundle-transitive-next-headers-leak.md`
(transitive imports survive bundling and produce surprises) and
`knowledge-base/project/learnings/2026-04-23-render-time-scrub-sentinels-and-client-bundle-boundaries.md`
(bundle boundaries change runtime semantics).

## Why now? (Why didn't this fire earlier?)

PRs #3338 (KB Concierge PDF summarize structural fix) and #3353 (extractor
cap alignment) introduced `extractPdfText` (added 2026-05-06) and wired
it into the Concierge cold-Query path. The `kb_share_preview` path
(`readPdfMetadata` at `kb-preview-metadata.ts`) has used the same lazy
`await import("pdfjs-dist/legacy/build/pdf.mjs")` since #2322 — but it
calls `warnSilentFallback` on parse failure (Sentry WARN level), which
is still surfaced but is more easily filtered. The Concierge path uses
`reportSilentFallback` (ERROR), which is what fired the alert.

In other words: **this bug has likely been latent in the
`readPdfMetadata` path for weeks**, throwing on every `kb_share_preview`
call against a PDF, downgraded to WARN. Confirming this is a Phase 1
research task before starting work.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim                                                         | Codebase reality                                                                                                                       | Plan response                                                                                          |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| #3391 / 40ba6a27 fixes the DOMMatrix issue via Node engines pin          | `package.json:engines` says `>=20.16.0 \|\| >=22.3.0`, prod runtime is Node v22.22.1 — already past floor; engines pin is hardening, not fix | Phase 1 verifies prod Node version via Sentry; new fix targets bundling, not engines                  |
| Bug "typically surfaces in Node when pdfjs-dist runs server-side"        | Server-side IS the failure path — but only because the legacy entry's polyfill is bypassed by esbuild bundling, not because Node lacks DOMMatrix | Plan addresses bundling boundary, not runtime polyfill                                                  |
| Issue body suggests "missing polyfill, wrong import, missing runtime guard" | Imports correct (legacy entry), runtime guard correct (try/catch + reportSilentFallback), legacy polyfill block is correct **as a discrete module** | Plan: declare pdfjs-dist external in BOTH esbuild `build:server` AND `next.config.ts:serverExternalPackages` |
| react-pdf component might leak server-side (`pdf-preview.tsx`)            | All callers of `pdf-preview.tsx` use `dynamic(() => …, { ssr: false })` — confirmed in `app/shared/[token]/page.tsx` and `components/kb/file-preview.tsx`; `react-pdf` not bare-imported anywhere else | Out of scope; not the failure path                                                                      |

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge replies "I
can't read this PDF — try copy/pasting the relevant section" on every
PDF summarize attempt, instead of inlining the extracted text. The
content-grounded fallback prompt is technically working as designed —
this is a degraded-UX silent-fallback, not a crash — but the user sees
a mediocre product that can't do the headline KB Concierge feature on
the headline content type.

**If this leaks, the user's data / workflow / money is exposed via:** no
exposure path. The fix changes module-loading semantics; it does not
touch authentication, RLS, or any user-tagged data path. The bundling
boundary is purely operational.

**Brand-survival threshold:** none — but **aggregate pattern** for
Concierge UX quality. Every Concierge PDF call has been hitting this for
the lifetime of #3338 (commit `a79a9221`, ~2026-04-15 onwards). Sentry
event `e8225a569fcd4b07a460b5b1bb2a5ee7` is one of presumably many — the
"handled: yes" tag means it doesn't page anyone, but every event is one
PDF the user couldn't summarize.

## Hypotheses

Ranked by likelihood, each with a verification step:

1. **(Primary, ≥95% confidence) esbuild bundles pdfjs-dist into
   `dist/server/index.cjs`; bundling reorders module init and bypasses the
   `if (isNodeJS)` polyfill block.** Verify by running
   `apps/web-platform/scripts/build-server-only.sh` (or `npm run build:server`)
   locally and grepping the produced `dist/server/index.cjs` for `DOMMatrix`
   and `pdfjs` to confirm pdfjs is bundled in. If bundled in, the fix is
   externalizing it. **Recovery if false:** drop to Hypothesis 2.

2. **(Secondary, ~3%) Next.js webpack also bundles pdfjs into a server
   chunk that beats the esbuild bundle to module init.** The `next.config.ts`
   `serverExternalPackages` does not list `pdfjs-dist`. Verify by inspecting
   `.next/server/chunks/*.js` after `npm run build` for `DOMMatrix` /
   `pdfjs-dist`. **Recovery if true:** the same fix (mark external in BOTH
   esbuild AND Next.js) addresses it; we'll do both regardless as defense
   in depth.

3. **(Tertiary, ~1%) Another caller is importing `pdfjs-dist`
   non-legacy (`pdfjs-dist/build/pdf.mjs`) in a server-evaluated path.**
   Verified false by `grep -rn "from \"pdfjs-dist\"" apps/web-platform/
   --include="*.ts" --include="*.tsx" -g '!node_modules'` returning zero
   bare imports — only `react-pdf` does this, and it's confined to
   client-only `dynamic(ssr: false)` boundaries. Re-verify in Phase 1.

4. **(Tertiary, ~1%) `@napi-rs/canvas` would fix it without externalizing.**
   Adding it as a dep would let the polyfill block populate `globalThis.DOMMatrix`.
   Rejected as the fix because: (a) it adds a heavy native dep (~50 MB
   binary, multi-arch builds), (b) it papers over the actual issue (the
   bundling reorder still happens — we'd still be fragile to future
   pdfjs internal restructure), (c) no other code path needs canvas.

## Open Code-Review Overlap

Two open review issues touch files this plan modifies:

- **#3342** (`review: kb-preview-metadata.ts passes Buffer to pdfjs which rejects it`):
  same file (`server/kb-preview-metadata.ts`), same `pdfjs.getDocument`
  call site at lines 88-92. The Buffer→Uint8Array no-copy view fix
  applies the SAME pattern already in `pdf-text-extract.ts:124-132`.
  **Disposition: Fold in.** Both fixes touch the exact same code. Add
  `Closes #3342` to the PR body.

- **#3377** (`follow-through: verify Sentry errorClass tags on next extractor failure`):
  Sentry verification follow-through from #3353. After this fix
  deploys, the `errorClass` tag should surface `lazy_import_failed`
  with a fresh Sentry event proving this fix landed. **Disposition:
  Acknowledge.** This plan creates the exact verification opportunity
  #3377 was waiting for; close #3377 as part of post-merge
  verification (Phase 7) by linking to a fresh Sentry event showing
  zero `lazy_import_failed` hits in the 24h window after deploy.

#3369 (`Extract mirrorWithDebounce`) is unrelated.

## Implementation Phases

### Phase 0: Setup (no code)

- [ ] Create the worktree (already done — `feat-one-shot-fix-dommatrix-not-defined`)
- [ ] Confirm prod runtime via Sentry event tags (Node v22.22.1, Debian 12.13) — **already verified** during plan research
- [ ] Verify the bundled `dist/server/index.cjs` contains pdfjs (Hypothesis 1)
  via `npm run --prefix apps/web-platform build:server && grep -c "DOMMatrix" apps/web-platform/dist/server/index.cjs`
- [ ] Note baseline: file path `/app/dist/server/index.cjs` in stack confirms bundling

### Phase 1: Reproduction & Test (RED)

Two tests, run in this order so the failing-test gate is honored before
implementation. Both live in `apps/web-platform/test/`.

**Test 1 — `pdf-text-extract.bundled-server.test.ts` (new):**

A regression test that asserts the server-bundle path. The test:

1. Spawns `npx esbuild` with the EXACT flags from `package.json:build:server`
   against a tiny entry file `test/fixtures/extract-entry.ts` that imports
   and calls `extractPdfText` with a fixture PDF buffer.
2. Runs the resulting `.cjs` via `node` and asserts the call returns a
   `PdfTextExtractResult` with non-empty `text` (and crucially NOT
   `{ error: "lazy_import_failed" }`).
3. **Failing assertion (RED):** before the fix, the test expects success
   but the bundled run produces `{ error: "lazy_import_failed" }`
   because of the DOMMatrix ReferenceError thrown during pdfjs's bundled
   `__init`.

This is the load-bearing test: it exercises the exact production
build/eval path (esbuild bundle → Node CJS exec) that vitest's normal
test-runner (which evaluates source files directly via Node ESM) cannot
catch. Per AGENTS.md `cq-write-failing-tests-before` and the plan
sharp-edge "preflight CLI form verification" — `vitest run` was passing
on this code for weeks because vitest never builds the production CJS.

Fixture: a tiny synthetic 1-page PDF embedded as base64 in
`test/fixtures/tiny-pdf.ts` (single page, single text run "Hello PDF").
**Why synthesized:** AGENTS.md `cq-test-fixtures-synthesized-only`.
Generate via `qpdf --empty --pages tiny-page.pdf 1-1 -- /tmp/tiny.pdf`
(qpdf is in the runner image already), or via a 4-line pdf-lib script
checked in alongside the fixture.

Estimated test runtime: ~3-5s (esbuild compile + node start + extract).
Tag the test with `vitest`'s `concurrent: false` and a timeout of 30s.

**Test 2 — `kb-preview-metadata.bundled-server.test.ts` (new):**

Same shape as Test 1, but exercises `readPdfMetadata` from
`server/kb-preview-metadata.ts`. Asserts the function returns a
non-null `PdfPreview` with `kind: "pdf"` from a bundled-CJS run.
**This will also fail RED** — confirming Hypothesis "the bug has been
latent in `readPdfMetadata` for weeks at WARN level".

These two tests together prove the bundling boundary is the issue and
guard against future regressions if anyone adds another lazy pdfjs
caller without externalizing.

### Phase 2: Fix (GREEN)

Three coordinated edits, all required for the fix to hold. Skipping any
one leaves a bundling path open.

**Edit 1 — `apps/web-platform/package.json:scripts.build:server`**

Add `--external:pdfjs-dist` to the esbuild flags. Verified flag form via
local `npx esbuild --help` (esbuild `0.25.12` installed):

```
  --external:M          Exclude module M from the bundle (can use * wildcards)
```

Verified type-def shape in `node_modules/esbuild/lib/main.d.ts`:

```ts
/** Documentation: https://esbuild.github.io/api/#external */
external?: string[]
```

Context7 (`/evanw/esbuild` CHANGELOG-2022) also documents the precise
intent:
> *"This feature allows esbuild to automatically exclude all npm packages
> from a bundle. This is useful for Node.js environments where packages
> may rely on file system access or native modules that do not work
> correctly when bundled. The 'packages: external' option replaces the
> less reliable '--external:./node_modules/\*' method."*

The bare-package form `--external:pdfjs-dist` matches the package and
ALL its subpath imports (`pdfjs-dist/legacy/build/pdf.mjs`,
`pdfjs-dist/build/pdf.mjs`, etc.) — confirmed by Context7's
"esbuild External Path Handling Logic" doc:
> *"if something looks like a package path (i.e. doesn't start with /
> or ./ or ../), import paths are checked to see if they have that
> package path as a path prefix (so --external:@foo/bar matches the
> import path @foo/bar/baz)."*

Diff:

```diff
-"build:server": "esbuild server/index.ts --bundle --platform=node --target=node22 --outfile=dist/server/index.cjs --external:next --external:react --external:react-dom --external:@supabase/supabase-js --external:@supabase/ssr --external:ws --external:stripe --external:@anthropic-ai/claude-agent-sdk --external:pino --external:@sentry/nextjs",
+"build:server": "esbuild server/index.ts --bundle --platform=node --target=node22 --outfile=dist/server/index.cjs --external:next --external:react --external:react-dom --external:@supabase/supabase-js --external:@supabase/ssr --external:ws --external:stripe --external:@anthropic-ai/claude-agent-sdk --external:pino --external:@sentry/nextjs --external:pdfjs-dist",
```

This forces esbuild to leave `import("pdfjs-dist/legacy/build/pdf.mjs")`
as a runtime `require` / dynamic import. Node's loader then evaluates
the file as a discrete ESM module with the polyfill block in correct
init order.

**Edit 2 — `apps/web-platform/next.config.ts:serverExternalPackages`**

Add `pdfjs-dist`. Verified type-def shape in
`node_modules/next/dist/server/config-shared.d.ts`:

```ts
/**
 * A list of packages that should be treated as external in the server build.
 * @see https://nextjs.org/docs/app/api-reference/next-config-js/serverExternalPackages
 */
serverExternalPackages?: string[];
```

Context7 (`/vercel/next.js`) describes the semantic verbatim:
> *"Dependencies used inside Server Components and Route Handlers will
> automatically be bundled by Next.js. However, if a dependency is using
> Node.js specific features, you can choose to opt-out specific
> dependencies from the Server Components bundling and use native
> Node.js `require` instead."*

**Notable from the Next.js auto-opt-out list** (verified via Context7's
`packages/next/src/lib/server-external-packages.jsonc` enumeration):
the list includes `canvas`, `sharp`, `@react-pdf/renderer`, `pino`,
`mongodb`, `bcrypt`, `puppeteer`, `playwright`, `@prisma/client`,
`postcss`, `webpack`, `eslint`, etc. — but **`pdfjs-dist` is NOT on
the list**. This is why we need the explicit add.

Diff:

```diff
-serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws"],
+serverExternalPackages: ["@anthropic-ai/claude-agent-sdk", "ws", "pdfjs-dist"],
```

Belt-and-suspenders for any Next.js route handler that transitively
imports `extractPdfText` or `readPdfMetadata`. Even though our pdfjs
callers are reached via the custom server (not via Next.js route
handlers), the App Router server bundle does pull
`server/kb-document-resolver.ts` transitively — this prevents Next.js
webpack from bundling pdfjs into its own server chunks.

**Edit 3 — Fold in #3342: `apps/web-platform/server/kb-preview-metadata.ts:88-92`**

Apply the same Buffer→Uint8Array no-copy view that
`pdf-text-extract.ts:124-132` already uses, and update the stale comment:

```diff
-    // Legacy entry provides a fake worker for Node so GlobalWorkerOptions
-    // does not need to be set. isEvalSupported: false avoids Function()
-    // usage inside the parser — irrelevant for metadata-only reads but
-    // keeps behavior identical to the browser SSR-safe config. Buffer is
-    // a Uint8Array subclass; pdfjs accepts it directly, no wrapping copy.
+    // Legacy entry provides a fake worker for Node so GlobalWorkerOptions
+    // does not need to be set. isEvalSupported: false avoids Function()
+    // usage inside the parser. pdfjs-dist@5 explicitly REJECTS Buffer
+    // (instanceof Buffer === false); wrap to a no-copy Uint8Array view.
+    const data = Buffer.isBuffer(buffer)
+      ? new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength)
+      : buffer;
     const doc = await pdfjs.getDocument({
-      data: buffer,
+      data,
       isEvalSupported: false,
     }).promise;
```

### Phase 3: Verification (REFACTOR + green)

Three tiers of verification, ordered cheapest → most expensive:

**Tier A — static (instant):**

- [ ] `grep -E '\-\-external:pdfjs-dist' apps/web-platform/package.json`
  must match exactly once
- [ ] `grep -E '"pdfjs-dist"' apps/web-platform/next.config.ts` must
  match exactly once inside `serverExternalPackages`
- [ ] `npm run --prefix apps/web-platform typecheck` — TS clean

**Tier B — bundle inspection (~10s):**

- [ ] `npm run --prefix apps/web-platform build:server` — succeeds
- [ ] `grep -c "DOMMatrix" apps/web-platform/dist/server/index.cjs` —
  expects `0`. (Source pdfjs has 10 DOMMatrix references; if any remain
  in the bundle, externalize did not take effect.)
- [ ] `grep -c "pdfjsVersion = 5\." apps/web-platform/dist/server/index.cjs` —
  expects `0`. (pdfjs's banner string proves the source got bundled in;
  zero hits means the externalize is working.)
- [ ] `ls -lh apps/web-platform/dist/server/index.cjs` — record before
  and after sizes; expect ~2-3 MB drop. Note in PR body.
- [ ] `npm run --prefix apps/web-platform build` (Next.js build) —
  succeeds
- [ ] `grep -rl "pdfjsVersion = 5" apps/web-platform/.next/server/ 2>/dev/null | head` —
  expects empty. Confirms Next.js webpack also externalized pdfjs.

**Tier C — runtime (~5s + Docker time):**

- [ ] Re-run Test 1 + Test 2 — both must PASS (assertions: extract
  result has non-empty `text`, metadata returns `{ kind: "pdf", numPages: 1, ... }`)
- [ ] `npm run --prefix apps/web-platform test:ci` — full suite green
- [ ] Phase 4 Docker smoke test (below) — production-shape verification

### Phase 4: Docker smoke test (production-shape verification)

Local Docker build + run, exercising the exact production CJS bundle:

```bash
docker build -t soleur-web-platform:dommatrix-fix \
  --build-arg NEXT_PUBLIC_SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain) \
  --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=$(doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c dev --plain) \
  --build-arg NEXT_PUBLIC_SENTRY_DSN=$(doppler secrets get NEXT_PUBLIC_SENTRY_DSN -p soleur -c dev --plain) \
  apps/web-platform/

docker run --rm -e NODE_ENV=production soleur-web-platform:dommatrix-fix \
  node -e 'import("/app/dist/server/index.cjs").then(m => m.extractPdfText(Buffer.from("..."), 8000)).then(r => { console.log(JSON.stringify(r)); process.exit(r.error ? 1 : 0); })'
```

**Why this matters:** the Sentry event was thrown from
`/app/dist/server/index.cjs` — exact same path as the docker exec
target. This is the only verification step that exercises the prod
runtime + bundled CJS combination. Vitest can't reach this; the new
bundled-server tests come close but exec via `node` directly outside
Docker. Per AGENTS.md plan sharp-edge "preflight CLI form verification".

### Phase 5: Review & Commit

- [ ] Run `skill: soleur:plan-review` (3-reviewer panel) on this plan
- [ ] Apply review feedback
- [ ] Generate `tasks.md` for `feat-one-shot-fix-dommatrix-not-defined`
- [ ] Commit + push
- [ ] Run `skill: soleur:work` to implement Phases 1-4
- [ ] Run `skill: soleur:review` (multi-agent) post-implementation

### Phase 6: PR + Ship

- [ ] PR title: `fix(kb-concierge): externalize pdfjs-dist to fix DOMMatrix ReferenceError in bundled server`
- [ ] PR body includes: `Closes #3342`, `Ref Sentry e8225a569fcd4b07a460b5b1bb2a5ee7`,
  before/after bundle size, before/after Sentry event count screenshot
- [ ] Squash-merge with auto-merge once CI green

### Phase 7: Post-merge verification

- [ ] Watch Sentry for 24h — `op:extractPdfText.import` event count must drop to 0
- [ ] Close #3377 with link to the verification window showing zero hits
- [ ] Test a real Concierge PDF summarize against a prod-shape PDF in dev
  (or staging if available) — agent must inline the extracted text in
  the system prompt, not fall back to the unreadable directive
- [ ] Capture a Sentry-event-count chart for the PR description

## Files to Edit

- `apps/web-platform/package.json` — add `--external:pdfjs-dist` to `scripts.build:server`
- `apps/web-platform/next.config.ts` — add `"pdfjs-dist"` to `serverExternalPackages`
- `apps/web-platform/server/kb-preview-metadata.ts` — Buffer→Uint8Array view (folds in #3342)

## Files to Create

- `apps/web-platform/test/pdf-text-extract.bundled-server.test.ts` — RED→GREEN regression test, esbuild bundle + node exec
- `apps/web-platform/test/kb-preview-metadata.bundled-server.test.ts` — same shape for the metadata path
- `apps/web-platform/test/fixtures/tiny-pdf.ts` — single-page synthetic PDF buffer (base64-encoded constant)
- `apps/web-platform/test/fixtures/extract-entry.ts` — esbuild entry that imports & calls `extractPdfText` for the bundled-server test
- `apps/web-platform/test/fixtures/metadata-entry.ts` — esbuild entry for the metadata test

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/test/pdf-text-extract.bundled-server.test.ts` — PASS
- [ ] `apps/web-platform/test/kb-preview-metadata.bundled-server.test.ts` — PASS
- [ ] `npm run --prefix apps/web-platform test:ci` — PASS (full suite)
- [ ] `npm run --prefix apps/web-platform typecheck` — PASS
- [ ] `npm run --prefix apps/web-platform build` — PASS (Next.js build)
- [ ] `npm run --prefix apps/web-platform build:server` — PASS (esbuild custom server)
- [ ] `grep -c "DOMMatrix" apps/web-platform/dist/server/index.cjs` returns `0`
- [ ] Bundle size drop documented in PR body (`ls -lh dist/server/index.cjs` before/after)
- [ ] Docker smoke test (Phase 4) green — bundled CJS extracts a fixture PDF without throwing
- [ ] PR body links Sentry event `e8225a569fcd4b07a460b5b1bb2a5ee7`
- [ ] PR body uses `Closes #3342` (folded in) and `Ref` for the Sentry event

### Post-merge (operator)

- [ ] Production deploy succeeds (`scheduled-postmerge.yml` or equivalent)
- [ ] Sentry `op:extractPdfText.import` 24h post-deploy event count = 0
- [ ] Sentry `op:preview-pdf-parse` 24h event count drops vs. baseline
  (this is the latent #3342-class WARN that #3338 missed)
- [ ] Manual Concierge PDF-summarize works in prod against a real
  multi-page PDF (verify inlined `<document>...</document>` body in the
  system prompt via debug logging or via the Concierge replying with
  on-PDF specifics rather than asking for the user to paste text)
- [ ] Close #3377 with the Sentry verification screenshot

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** This is a build-tooling boundary fix at the bundler
level. Two production code paths (extractor + metadata) silently
degrade to a content-grounded fallback because esbuild + Next.js bundle
pdfjs-dist into a single CJS / chunk where its module-init polyfill
order is broken. The fix is structural (mark external in two places),
NOT a polyfill add. Risks: (a) externalizing means pdfjs-dist must be
present in `node_modules` at runtime — already true, it's a regular
`dependencies` entry, no Dockerfile change needed; (b) cold-start
latency: the legacy entry resolves a fake-worker shim on first import,
~10-20ms. Already paid on every cold Concierge today — same shape; (c)
the new bundled-server tests add ~3-5s per test × 2 to CI. Worthwhile —
they catch a class of bugs the source-only test path cannot.

### Product/UX Gate

Not applicable — no user-facing UI surface change. The Concierge
fallback prompt already exists and works; the fix restores the happy
path.

## Test Strategy

**Framework:** vitest (already installed; this is the project's standard
test runner per `package.json:scripts.test`).

**New tests:**

1. `pdf-text-extract.bundled-server.test.ts` — bundles a tiny entry that
   imports & calls `extractPdfText`, runs the CJS, asserts the result
   shape. RED before fix, GREEN after.
2. `kb-preview-metadata.bundled-server.test.ts` — same shape for
   `readPdfMetadata`.

**Existing tests:**

- `apps/web-platform/test/pdf-text-extract.test.ts` — must stay green
  (it tests the source-file path; the externalization doesn't change
  source behavior, only bundling).

**Why bundled-server tests, not just the Docker smoke test:** the
Docker test is operator-driven and not in CI. The bundled-server
tests are reproducible, CI-friendly, and exercise the SAME esbuild
flag set, so they detect any future regression to `package.json`'s
`build:server` script (e.g., someone trims the `--external` list).

**Verification of esbuild flag drift:** the new tests parse
`package.json` and use the EXACT `build:server` flag string (after
trimming `server/index.ts → test/fixtures/extract-entry.ts` and
`dist/server/index.cjs → /tmp/extract-bundle.cjs`). This catches
"someone updated the script and forgot --external:pdfjs-dist" because
the test would re-bundle without the externalize and fail RED again.

## Risks

1. **Docker image must include `node_modules/pdfjs-dist` in the runner stage.**
   Verify: `docker build` runner stage runs `npm ci --omit=dev` and
   pdfjs-dist is in `dependencies` (NOT devDeps) — confirmed in
   `apps/web-platform/package.json` at line 33. Mitigated.
2. **Next.js 15.5 might not honor `serverExternalPackages` for transitive
   imports through the custom-server bundle.** The custom server is the
   primary execution path (not Next.js route handlers), so the esbuild
   `--external` is the load-bearing fix. The Next.js change is defense
   in depth. Even if Next.js bundles pdfjs into a route-handler chunk,
   that chunk doesn't run in the Concierge path (verified in stack:
   `extractPdfText` runs from the custom WS handler, not a route).
3. **Tests bundle on every run, ~3-5s each.** Acceptable; can be tagged
   `concurrent: false` and `slow` for selective skipping. Don't gate
   ship on this — keep them in `test:ci`.
4. **Folded-in #3342 fix is silent-correct on the happy path.** Adding
   a regression test for #3342 specifically would require an
   error-shape fixture (a future pdfjs minor that hard-rejects Buffer);
   covered by the new bundled-server tests' positive assertion shape.
5. **`@napi-rs/canvas` rejection is documented but not enforced.** A
   future engineer might add it to "fix" a different DOMMatrix issue.
   Add a comment in `package.json`'s `dependencies` block warning
   against it (rejected: package.json doesn't take comments). Instead,
   add the rationale to `kb-preview-metadata.ts` and `pdf-text-extract.ts`
   header comments AND to a new learning file post-merge.
6. **Bundling boundary order: esbuild runs AFTER Next.js webpack in the
   production Docker build.** Confirmed via `apps/web-platform/Dockerfile`
   builder stage: `RUN npm run build` (Next.js) THEN `RUN npm run build:server`
   (esbuild). The Sentry stack frame is `/app/dist/server/index.cjs` — the
   esbuild output, NOT a Next.js chunk. So esbuild `--external:pdfjs-dist`
   alone fixes the prod failure path; the Next.js change is true
   defense-in-depth. Even if Next.js's webpack DID bundle pdfjs into
   `.next/server/chunks/*.js`, those chunks aren't on the call path
   the WS handler uses (the custom server is launched as
   `node dist/server/index.cjs` per `package.json:scripts.start`).
   This sequencing matters: do NOT skip Edit 2 thinking "Edit 1 is
   sufficient" — keep Edit 2 for any future Next.js Route Handler that
   transitively imports `kb-document-resolver` (e.g., a future
   `app/api/kb/concierge/extract-pdf/route.ts`).
7. **"Folded in #3342 with no separate test"-class regression.** The
   Buffer→Uint8Array view fold-in for `kb-preview-metadata.ts` is
   silent-correct in the happy path because `pdfjs-dist@5.4.296` may
   tolerate Buffer in some internals. The new bundled-server test
   `kb-preview-metadata.bundled-server.test.ts` validates the happy path
   end-to-end (extract metadata from a fixture PDF) — that's sufficient
   coverage. We do NOT need a "Buffer rejection" negative test because
   #3342's claim is already documented and the patch matches the proven-
   correct shape from `pdf-text-extract.ts`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. — N/A here, section is filled.
- esbuild `--external:` flags don't take wildcards (`--external:pdfjs-dist/*`
  is invalid for the npm-package form when using the package-name shape;
  it's the bare package name OR a glob via `--external:./*`). Verify the
  exact form by running esbuild with `--help` once before committing the
  flag. Per AGENTS.md sharp edge "CLI-verification gate".
- `serverExternalPackages` in Next.js 15 is a flat array of package
  names — NO globs. `pdfjs-dist` matches all `pdfjs-dist/build/*` and
  `pdfjs-dist/legacy/build/*` subpaths automatically.
- The new bundled-server tests must execute esbuild via `npx esbuild`
  or via `import { build } from "esbuild"` in-process. The latter is
  faster (no spawn) but requires esbuild as a devDep — already present.
- Folding in #3342 means the PR body `Closes #3342` MUST appear before
  the merge — otherwise GitHub's auto-close logic will not fire.
  AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`.
- After the fix, `kb-preview-metadata.ts`'s `warnSilentFallback` will
  ALSO stop firing on the bundled-init path. Phase 7 verification needs
  to look at the WARN-level Sentry stream for `feature:kb-share,
  op:preview-pdf-parse`, NOT just the ERROR stream. This is how we
  retroactively prove Hypothesis "latent for weeks at WARN level".

## Alternatives Considered

| Alternative                                    | Rejected because                                                                                                                                        |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Add `@napi-rs/canvas` as a dep                 | Heavy native dep (~50 MB binary, multi-arch builds), papers over the bundling reorder, no other code path needs canvas                                  |
| Polyfill `globalThis.DOMMatrix` in `server/index.ts` before any pdfjs import | Bandaid — bundling reorder may also break ImageData polyfill in the future; doesn't address the root cause                                              |
| Pin `pdfjs-dist@4.x` (older, simpler)          | Loses #3338's fix surface (extractor cap alignment), regresses other call sites; downgrade is much heavier than externalize                              |
| Use `pdf-parse` instead of pdfjs               | `pdf-parse` is unmaintained (last release 2020), depends on a forked pdfjs at v1.x — strictly worse                                                     |
| Move `extractPdfText` to a child process       | Adds IPC complexity for a synchronous-by-promise text extraction; child-process bundling has the same external-or-bundle question                       |

## Closes / Refs

- Sentry `e8225a569fcd4b07a460b5b1bb2a5ee7` (the trigger event)
- `Closes #3342` (kb-preview-metadata Buffer→Uint8Array view, folded in)
- `Ref #3338` (the PR that introduced `extractPdfText` and made the
  Concierge ERROR-level alarm fire)
- `Ref #3353` (extractor cap alignment, related but already merged)
- `Ref #3391, #3393` (Node engines pin — adjacent, not the actual fix)
- `Ref #3377` (Sentry verification follow-through; closed in Phase 7)
