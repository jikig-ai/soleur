---
title: pdfjs-dist bundling reorder breaks Node-only module init
date: 2026-05-07
category: runtime-errors
module: apps/web-platform/server
tags: [bundling, esbuild, nextjs, pdfjs-dist, server-external-packages, dommatrix]
related_issues: [3410, 3338, 3342, 3353, 3391, 3393, 3422]
sentry: e8225a569fcd4b07a460b5b1bb2a5ee7
---

# pdfjs-dist bundling reorder breaks Node-only module init

## Problem

Sentry event `e8225a569fcd4b07a460b5b1bb2a5ee7` (2026-05-07, prod, Node v22.22.1) fired:

```
ReferenceError: DOMMatrix is not defined
    at __init (file:///app/dist/server/index.cjs)
    at extractPdfText (file:///app/dist/server/index.cjs)
    at resolveConciergeDocumentContext (...)
```

Every Concierge PDF summarize call had been silently degrading to the "PDF unreadable" content-grounded fallback prompt for the lifetime of #3338 (~3 weeks). Same latent failure on `kb_share_preview` via `readPdfMetadata`, which logs at WARN level and was easy to filter out.

## Root Cause

`pdfjs-dist@5`'s legacy entry runs a Node-only polyfill block at module init:

```js
if (isNodeJS) {
  const require = process.getBuiltinModule("module").createRequire(import.meta.url);
  const canvas = require("@napi-rs/canvas");
  if (!globalThis.DOMMatrix) globalThis.DOMMatrix = canvas?.DOMMatrix;
  // ... ImageData, Path2D
}
```

When `pdfjs-dist/legacy/build/pdf.mjs` is evaluated by Node's loader as a discrete ESM module, this block runs in correct order before any class definition references `DOMMatrix`.

When esbuild bundles pdfjs into a CJS file, the module's top-level becomes a `__init` function whose statement order is hoisted/reordered by the bundler. Some class definition or static prop referencing `DOMMatrix` ends up evaluated before the polyfill block. The polyfill never runs (or runs late), and `DOMMatrix` is undefined when the consumer hits a `class Foo { static p = new DOMMatrix(...) }`-shaped reference.

The bug only manifests:
1. When `pdfjs-dist` is bundled (not externalized).
2. In the production bundle path — vitest's source-only Node ESM evaluation cannot reach it.

The dev server (`npm run dev`) escapes via `--packages=external`. The custom server (`build:server`) bundles whatever is not in `--external`, and pdfjs-dist was missing from that list. Next.js's `serverExternalPackages` auto-opts out `canvas`, `sharp`, `@react-pdf/renderer`, `pino`, etc. — but **not** `pdfjs-dist`.

## Solution

Two coordinated edits (NOT three — see "Why not Next.js serverExternalPackages" below):

1. **`apps/web-platform/package.json:scripts.build:server`** — add `--external:pdfjs-dist`. Bundle dropped 2.9 MB → 1.9 MB. This is the proven fix for the production Sentry event (`/app/dist/server/index.cjs` is the esbuild output; the bundled-server regression test reproduces the failure with the EXACT prod flag set).
2. **`apps/web-platform/server/pdfjs-input.ts`** — extract `toPdfjsData(buffer)` for the Buffer→Uint8Array no-copy view (pdfjs@5 rejects Buffer despite `Buffer extends Uint8Array`). Folds in #3342.

### Why not Next.js `serverExternalPackages`

The architecture-strategist review hypothesized that adding `pdfjs-dist` to `next.config.ts:serverExternalPackages` was load-bearing for the `app/api/kb/share/route.ts` → `kb-share.ts` → `readPdfMetadata` path (a Next.js Route Handler bundled by webpack independently of esbuild). The first commit included that change; CI's `web-platform-build` job rejected it: `next build` failed compiling `components/kb/pdf-preview.tsx` (a `"use client"` component dynamically imported with `ssr: false`) because the worker reference `new URL("pdfjs-dist/build/pdf.worker.min.mjs", import.meta.url).toString()` cannot resolve when pdfjs-dist is treated as an external package. The Sentry event's stack frame is `/app/dist/server/index.cjs : __init` — the esbuild custom-server output, not a Next.js Route Handler chunk. The Route Handler path may or may not exhibit the same init-reorder bug under webpack 5; it has not produced a Sentry event. Defer until evidence, then choose a different mechanism (`transpilePackages`, restructure the worker URL, etc.).

Plus two new bundled-server regression tests (`apps/web-platform/test/{pdf-text-extract,kb-preview-metadata}.bundled-server.test.ts`) that reproduce the exact production failure path:

- Read externals from `package.json:scripts.build:server` at runtime — drop `--external:pdfjs-dist` and the helper throws.
- Bundle a fixture entry with esbuild's programmatic API.
- Spawn Node against the resulting CJS.
- Wrap entry output in `<<<RESULT_BEGIN>>>...<<<RESULT_END>>>` delimiters because pino + pdfjs warnings + Sentry init share stdout.
- Outfile lives inside `apps/web-platform/dist/test-bundle/` so Node's upward `node_modules` resolution finds externalized packages.

## Key Insight

**When a Node-only library has a side-effectful module init (polyfills, native bindings, register-a-fake-worker, env detection), externalize it from any bundler whose output Sentry has actually witnessed throwing.** The esbuild custom-server bundle (`dist/server/index.cjs`) was the proven failure path; the Next.js webpack server bundle was a hypothesis.

The two-bundler topology matters: when adding the SAME library to BOTH externalize lists, verify that no client-side consumer references the package via `new URL("<pkg>/sub/path", import.meta.url)` — `serverExternalPackages` interferes with webpack's asset-URL resolution at compile time, even for files behind `dynamic({ ssr: false })`. The architecture-strategist's "defense-in-depth always" instinct produced a pre-merge `web-platform-build` failure; "fix the proven path, defer the hypothetical" was correct.

The bundled-server regression test pattern is reusable: read externals from production `package.json` at runtime, bundle in-process, exec via `spawnSync(process.execPath, ...)`, parse delimited JSON from stdout. This catches a class of bugs that vitest's source-only path structurally cannot reach. Helper lives at `apps/web-platform/test/helpers/bundled-server.ts`.

## Session Errors

1. **Bundle outfile in `/tmp/` produced `Cannot find module '@sentry/nextjs'`** — the spawned Node process couldn't resolve externalized packages because `/tmp/` has no upward `node_modules`. **Recovery:** write outfile inside `apps/web-platform/dist/test-bundle/` so Node's resolver walks up to `apps/web-platform/node_modules`. **Prevention:** documented in `test/helpers/bundled-server.ts:96-98`.

2. **`Unexpected non-whitespace character after JSON at position 30`** — entry wrote `JSON.stringify(result)` to stdout, but pino logger + pdfjs `Warning: Cannot polyfill DOMMatrix` lines also wrote to stdout. **Recovery:** wrap the JSON in `<<<RESULT_BEGIN>>>...<<<RESULT_END>>>` and regex-extract from the combined stdout. **Prevention:** documented in `bundled-server.ts:75` (`RESULT_DELIMITER_RE`).

3. **System default Node was 21.7.3** which lacks `process.getBuiltinModule` (added in Node 22.3+). Both pre- and post-fix bundled-server tests failed identically until I switched to nvm Node 22.22.2 (matching prod). **Recovery:** `source ~/.nvm/nvm.sh && nvm use 22.22.2`. **Prevention:** discoverable from the test stderr (`Warning: Cannot access the require function: TypeError: process.getBuiltinModule is not a function`); engines field in `package.json` already pins `>=22.3.0`.

4. **Module-load `rmSync(TEST_BUNDLE_DIR, ...)` cleanup raced between parallel vitest workers** — test passed in isolation, failed in full suite when sibling worker rmSync'd the parent dir while my entry bundle was still being written. **Recovery:** remove the cleanup; rely on per-call `mkdtempSync` + `finally rmSync` of the worker's own subdir only. **Prevention:** `bundled-server.ts:84-87` warns future contributors that a parallel-worker rmSync of the shared parent is unsafe.

5. **`gh milestone list` is not a valid `gh` subcommand** — used `gh api repos/{owner}/{repo}/milestones --jq '.[] | "\(.number): \(.title)"'` instead. **Prevention:** verify `gh <cmd> --help` before chaining; one-off, no rule needed.

6. **Bash CWD doesn't persist between tool calls** — already covered by AGENTS.md sharp edges; recovered by chaining `cd <abs> && <cmd>` in a single Bash call.

7. **CI `web-platform-build` job failed post-PR-ready** because adding `pdfjs-dist` to `next.config.ts:serverExternalPackages` broke `next build` compilation of the client-side `components/kb/pdf-preview.tsx` worker URL `new URL("pdfjs-dist/build/pdf.worker.min.mjs", import.meta.url).toString()`. Local `npm run typecheck` (which is `tsc --noEmit`) and `vitest run` did NOT exercise `next build`, so the break was invisible until CI. **Recovery:** revert the `serverExternalPackages` change; keep the esbuild externalize (which is the actual proven fix for the Sentry event). **Prevention:** when adding a package to `serverExternalPackages`, run `cd apps/web-platform && npm run build` locally before committing — `tsc --noEmit` does NOT exercise webpack's module resolution. This is a class-mate of `cq-nextjs-route-files-http-only-exports` — webpack-specific failures only surface at `next build` time. Considered AGENTS.md placement: domain-scoped (only applies to `apps/web-platform/next.config.ts`), so the rule lives in this learning + the inline comment in `next.config.ts`, not in AGENTS.md.

## Cross-References

- `apps/web-platform/server/pdfjs-input.ts` — shared `toPdfjsData` helper
- `apps/web-platform/test/helpers/bundled-server.ts` — bundled-server test harness
- `apps/web-platform/next.config.ts:16-22` — `serverExternalPackages` with rationale
- `knowledge-base/project/learnings/2026-04-18-server-bundle-transitive-next-headers-leak.md` — same failure class (transitive imports survive bundling)
- `knowledge-base/project/learnings/2026-04-23-render-time-scrub-sentinels-and-client-bundle-boundaries.md` — bundle boundaries change runtime semantics
- #3422 — deferred-scope-out: Dockerfile `require.resolve` assertion follow-up
