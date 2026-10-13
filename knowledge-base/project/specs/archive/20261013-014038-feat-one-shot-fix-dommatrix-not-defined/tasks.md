# Tasks: fix-pdfjs-dommatrix-bundled-server

Plan: `knowledge-base/project/plans/2026-05-07-fix-pdfjs-dommatrix-bundled-server-plan.md`

Sentry: `e8225a569fcd4b07a460b5b1bb2a5ee7` (handled, prod, Node v22.22.1, op `extractPdfText.import`)

## Phase 0 — Setup

- 0.1 Confirm worktree `feat-one-shot-fix-dommatrix-not-defined` exists (DONE)
- 0.2 Verify Sentry event tags via `gh api` or Sentry web UI (DONE — runtime Node v22.22.1, server `5ef4c60309e8`, Debian 12.13)
- 0.3 Reproduce locally:
  - `npm --prefix apps/web-platform run build:server`
  - `grep -c "DOMMatrix" apps/web-platform/dist/server/index.cjs` — expect non-zero (baseline; pdfjs is bundled)
  - Note baseline `dist/server/index.cjs` size for PR body

## Phase 1 — RED tests (failing-test gate)

- 1.1 Create `apps/web-platform/test/fixtures/tiny-pdf.ts`
  - Single-page synthetic PDF, ~1 KB
  - Constant export: `TINY_PDF_BUFFER: Buffer` (base64-decoded at module load)
  - One text run: `"Hello PDF"` so `getTextContent()` returns it
- 1.2 Create `apps/web-platform/test/fixtures/extract-entry.ts`
  - Imports `extractPdfText` from `@/server/pdf-text-extract`
  - Imports `TINY_PDF_BUFFER` from `./tiny-pdf`
  - Top-level await: `const r = await extractPdfText(TINY_PDF_BUFFER, 8000); process.stdout.write(JSON.stringify(r));`
- 1.3 Create `apps/web-platform/test/fixtures/metadata-entry.ts`
  - Same shape; calls `readPdfMetadata` with a Readable stream wrapping the fixture buffer
- 1.4 Create `apps/web-platform/test/pdf-text-extract.bundled-server.test.ts`
  - Import esbuild's `build` API
  - Bundle `extract-entry.ts` with EXACT flags from `package.json:scripts.build:server` (parse via `JSON.parse(fs.readFileSync("package.json"))` and substitute entry/outfile)
  - Spawn `node /tmp/extract-bundle.cjs`
  - Parse JSON from stdout
  - Assert `result.error === undefined` AND `typeof result.text === "string"` AND `result.text.length > 0`
  - Per-test timeout: 30s
  - **Expected RED:** before fix, stderr contains `ReferenceError: DOMMatrix is not defined`; assertion fails because `result.error === "lazy_import_failed"`
- 1.5 Create `apps/web-platform/test/kb-preview-metadata.bundled-server.test.ts`
  - Same bundle-and-exec shape for `metadata-entry.ts`
  - Assert `result.kind === "pdf"` AND `result.numPages === 1`
  - **Expected RED:** before fix, returns `null` (warnSilentFallback path)
- 1.6 `vitest run apps/web-platform/test/pdf-text-extract.bundled-server.test.ts apps/web-platform/test/kb-preview-metadata.bundled-server.test.ts` — confirm both fail RED
- 1.7 Commit: `test: add bundled-server pdfjs regression tests (failing)`

## Phase 2 — GREEN edits

- 2.1 Edit `apps/web-platform/package.json:scripts.build:server`
  - Add `--external:pdfjs-dist` (verified flag form via `npx esbuild --help` and Context7)
- 2.2 Edit `apps/web-platform/next.config.ts`
  - Add `"pdfjs-dist"` to `serverExternalPackages` array
  - Verified type-def `serverExternalPackages?: string[]` in `next/dist/server/config-shared.d.ts`
- 2.3 Edit `apps/web-platform/server/kb-preview-metadata.ts:88-92` (folds in #3342)
  - Replace `data: buffer` with the no-copy Uint8Array view from `pdf-text-extract.ts:124-132`
  - Update stale comment ("pdfjs accepts it directly" → corrected)
- 2.4 Re-run Phase 1 tests — both must PASS (GREEN)
- 2.5 Commit: `fix: externalize pdfjs-dist in esbuild + Next.js server bundles`

## Phase 3 — Verification

**Tier A — static (instant):**

- 3.1 `grep -E '\\-\\-external:pdfjs-dist' apps/web-platform/package.json` — exactly 1 match
- 3.2 `grep -E '"pdfjs-dist"' apps/web-platform/next.config.ts` — exactly 1 match (inside serverExternalPackages)
- 3.3 `npm --prefix apps/web-platform run typecheck` — clean

**Tier B — bundle inspection (~10s):**

- 3.4 `npm --prefix apps/web-platform run build:server` — succeeds
- 3.5 `grep -c "DOMMatrix" apps/web-platform/dist/server/index.cjs` — expect `0`
- 3.6 `grep -c "pdfjsVersion = 5\\." apps/web-platform/dist/server/index.cjs` — expect `0`
- 3.7 `ls -lh apps/web-platform/dist/server/index.cjs` — record before/after sizes
- 3.8 `npm --prefix apps/web-platform run build` — Next.js build succeeds
- 3.9 `grep -rl "pdfjsVersion = 5" apps/web-platform/.next/server/ 2>/dev/null | head` — expect empty

**Tier C — runtime tests:**

- 3.10 `npm --prefix apps/web-platform run test:ci` — full suite green
- 3.11 Phase 4 Docker smoke test below

## Phase 4 — Docker smoke test

- 4.1 `docker build -t soleur-web-platform:dommatrix-fix --build-arg NEXT_PUBLIC_SUPABASE_URL=... --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=... --build-arg NEXT_PUBLIC_SENTRY_DSN=... apps/web-platform/`
  (creds via `doppler secrets get ... -p soleur -c dev --plain`)
- 4.2 `docker run --rm -e NODE_ENV=production soleur-web-platform:dommatrix-fix node -e '<extract harness>'`
  — must exit 0 with non-empty `result.text`
- 4.3 Compare image size vs. baseline (informational; bundle drops ~2-3 MB)

## Phase 5 — Plan review + work commit

- 5.1 `git push -u origin feat-one-shot-fix-dommatrix-not-defined` (rf-before-spawning-review-agents-push-the-branch)
- 5.2 Run `skill: soleur:review` (multi-agent panel)
- 5.3 Apply review findings inline (rf-review-finding-default-fix-inline)
- 5.4 Commit any review-driven fixes

## Phase 6 — PR + ship

- 6.1 PR title: `fix(kb-concierge): externalize pdfjs-dist to fix DOMMatrix ReferenceError in bundled server`
- 6.2 PR body sections:
  - Summary (Sentry event link)
  - Root cause (1-paragraph)
  - Fix (3 edits enumerated)
  - Verification (Tier A/B/C results pasted)
  - Bundle size before/after
  - `Closes #3342` (folded-in)
  - `Ref Sentry e8225a569fcd4b07a460b5b1bb2a5ee7`
  - `Ref #3338` `Ref #3353` `Ref #3377`
- 6.3 `gh pr create ...`
- 6.4 `gh pr merge <N> --squash --auto`
- 6.5 Poll until MERGED (`gh pr view <N> --json state --jq .state`)
- 6.6 Run `skill: soleur:ship` (Phase 5.5 gates)

## Phase 7 — Post-merge verification

- 7.1 Watch Sentry `op:extractPdfText.import` — expect 0 events in 24h post-deploy
- 7.2 Watch Sentry `op:preview-pdf-parse` (WARN level) — expect drop vs. baseline
- 7.3 Test real Concierge PDF summarize in prod (or staging if available)
- 7.4 Close #3377 with verification screenshot
- 7.5 Capture compound learning: "Externalize Node-only parsers (pdfjs/sharp/canvas-likes) at BOTH esbuild --external AND Next.js serverExternalPackages — webpack and esbuild are independent bundlers"
- 7.6 `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`
