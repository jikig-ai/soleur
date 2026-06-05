---
feature: feat-one-shot-4976-c4-render-off-tree
issue: 4976
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-05-fix-c4-render-off-tree-plan.md
---

# Tasks — Render `model.likec4.json` off-tree (Option A)

Single atomic PR. TDD: adapt/write the failing test, then make it green. Phases ordered by
contract-dependency (producer `renderC4Model` return-type change lands before the consumer
`rerenderAndCommit` change) so no phase leaves dead code.

## Phase 0 — Preconditions (verify-before-code)

- [ ] 0.1 Confirm `renderC4Model`'s only production caller is `rerenderAndCommit`:
  `git grep -n 'renderC4Model' apps/web-platform` → expect def/export in `c4-render.ts`,
  import+call in `c4-writer.ts`, mock in `c4-writer-rerender.test.ts`, import in
  `c4-render.test.ts`. No other caller.
- [ ] 0.2 Confirm GET `/project` is the sole on-disk reader of `model.likec4.json`:
  `git grep -nE 'C4_MODEL_JSON|model\.likec4\.json' apps/web-platform --include='*.ts'`;
  verify only `project/route.ts` does an `fs.open`/`readFile` of it.
- [ ] 0.3 Confirm runner + path collection: `apps/web-platform/vitest.config.ts` `include`
  collects `test/**/*.test.ts`; invoke via `./node_modules/.bin/vitest run <paths>`.

## Phase 1 — `c4-render.ts`: return bytes, drop the tracked-path publish (producer)

- [ ] 1.1 Widen `RenderResult` success variant to
  `{ ok: true; durationMs: number; json: string }`.
- [ ] 1.2 In `renderToValidatedModel`: bind the validated read into
  `const raw = await readFile(tmpOut, "utf8")`, `JSON.parse(raw)` for validation, and on
  validated success return `{ ok: true, durationMs: run.durationMs, json: raw }`. Return the
  raw `utf8` string (do NOT re-`JSON.stringify`) so committed bytes are byte-identical to the
  validated artifact.
- [ ] 1.3 Delete the tracked-file publish machinery: `realPath`, `stagePath`, the
  `copyFile`+`rename` publish, and the trailing `rm(stagePath, …)` cleanup. Keep the
  `mkdtemp` temp-dir + `rm(dir, …)` lifecycle (still needed for the spawn `-o` target).
- [ ] 1.4 Remove now-unused imports (`copyFile`, `rename`, `basename` if unreferenced) — let
  `tsc`/lint confirm.
- [ ] 1.5 Update the module header + function-doc prose (was: "copy onto the real
  model.likec4.json … where the GET reads it and the caller commits it") to the new contract
  (return the validated bytes; the writer commits them and the resync pull lands them on
  disk).

## Phase 2 — `c4-render.test.ts`: assert the new contract (producer test)

- [ ] 2.1 Replace the copyFile/rename publish assertions with: success result is `ok:true`
  and `res.json` equals the staged `VALID_MODEL`; assert `copyFile`/`rename` NOT called.
- [ ] 2.2 Drop the `STAGE`/`REAL_JSON` fixtures and the `copyFile`/`rename` entries from
  `fsMock`; keep `mkdtemp`/`readFile`/`rm`.
- [ ] 2.3 In every failure case (empty-elements, non-object elements, non-JSON, non-zero
  exit, spawn_error, timeout): assert the result has no `json` field and no publish occurred.
- [ ] 2.4 Leave the spawn/argv/env scope assertions unchanged.

## Phase 3 — `c4-writer.ts`: commit the returned bytes (consumer)

- [ ] 3.1 After `renderC4Model` + the `!render.ok` early-return, use `render.json`: cap-check
  `Buffer.byteLength(render.json, "utf8") > MAX_C4_MODEL_BYTES` →
  `reportSilentFallback(op:"commit-json", extra:{ userId, relativePath, size })` + return
  `{ rerendered:false }` (preserves AC2c).
- [ ] 3.2 Delete the `open(jsonAbsPath, O_NOFOLLOW)` + `handle.stat()` + `handle.readFile()`
  + `handle.close()` block and the `jsonAbsPath` construction. Remove now-unused
  `open`/`constants as fsConstants`/`join` imports if unreferenced (verify `join` is not
  used elsewhere).
- [ ] 3.3 Keep the rest of the commit flow byte-for-byte: `githubApiGet` blob-sha,
  `githubApiPost(... jsonFilePath ...)`, the `op:"manual"` `syncWorkspace` resync + its
  `!resync.ok` `reportSilentFallback(op:"resync")`, and the success
  `logger.info({ event:"c4_rerender", … durationMs: render.durationMs })`.
- [ ] 3.4 Update the `rerenderAndCommit` doc comment to reflect the new
  "renderC4Model returns the validated bytes; we commit them; the resync pull lands the
  committed bytes on the clone" contract.

## Phase 4 — `c4-writer-rerender.test.ts`: adapt the consumer mock (consumer test)

- [ ] 4.1 Change the `renderC4Model` mock default to resolve
  `{ ok:true, durationMs:12, json:'{"_stage":"layouted"}' }`.
- [ ] 4.2 Remove the `node:fs/promises` `open` mock + the `stat`/`readFile`/`close`
  FileHandle fakes. Resize the AC2c oversized case to size the mocked `render.json` above
  4 MB (e.g. `json: "x".repeat(8 * 1024 * 1024)`) instead of mocking `stat.size`.
- [ ] 4.3 Keep AC1/AC2/AC2b/AC2d/AC2e/AC3/OUT_OF_SCOPE/first-sync-failure assertions; verify
  the JSON-commit assertion (`endsWith("/diagrams/model.likec4.json")`) still holds.
- [ ] 4.4 Add an assertion (AC1 or a sibling test) that the writer commits the bytes returned
  by `renderC4Model` (JSON-commit `content` base64-decodes to `render.json`), pinning the
  new producer→consumer contract.

## Phase 5 — Verify

- [ ] 5.1 `./node_modules/.bin/vitest run test/c4-render.test.ts test/c4-writer-rerender.test.ts
  test/kb-route-helpers.test.ts` (from `apps/web-platform/`) → all green; confirm the
  `kb-route-helpers.test.ts` self-heal tests passed WITHOUT edit.
- [ ] 5.2 `npx tsc --noEmit` (web-platform) → clean.
- [ ] 5.3 Run the broader server suite scoped to changed-area files to catch any incidental
  importer.

## Definition of Done

- [ ] AC1–AC9 (plan, Pre-merge) all met.
- [ ] `kb-route-helpers.test.ts` self-heal suite green with zero edits (AC8).
- [ ] No tracked-path write remains in `c4-render.ts`; no on-disk model re-read remains in
  `c4-writer.ts`.
- [ ] PR body references `Closes #4976`; dogfood verification stays tracked by #4966 (not
  re-filed).
