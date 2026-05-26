# Tasks — feat-one-shot-sidebar-pdf-summarize-out-of-boundary

Plan: `knowledge-base/project/plans/2026-05-06-fix-sidebar-pdf-summarize-out-of-boundary-plan.md`
Issue: #3376 (post-#3353 reproduction follow-through)
Closes: #3383
Refs: #3342

## Phase 0 — RED tests (verify each bug is independently observable)

- [ ] 0.1 — Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts`. Confirm 8 failures with `lazy_import_failed` (Bug C). Document the exact failure shape in plan §Phase 0.
- [ ] 0.2 — Add a failing sandbox test in `apps/web-platform/test/sandbox-relative-paths.test.ts`: `isPathInWorkspace("knowledge-base/test.pdf", fakeWorkspace)` returns false pre-fix even though the file exists in the workspace.
- [ ] 0.3 — Add a failing resolver test in `apps/web-platform/test/kb-document-resolver-pdf-extract.test.ts` (or extend existing): when `readFile` throws ENOENT, the resolver returns `{ artifactPath, documentKind: "pdf" }` (no `documentExtractError`) AND no Sentry mirror is called. Both assertions are RED pre-fix.

## Phase 1 — Bug C: Node engine alignment

- [ ] 1.1 — Add `"engines": { "node": ">=22.3.0" }` to `apps/web-platform/package.json`. Verified rationale: `process.getBuiltinModule()` was added in Node 22.3.0 (and 20.16.0).
- [ ] 1.2 — Document the Node ≥ 22.3 floor in `apps/web-platform/CONTRIBUTING.md` or `README.md` (verify which file exists first via `ls`).
- [ ] 1.3 — Add a Sentry mirror to the `extractPdfText` lazy-import catch (`pdf-text-extract.ts:96-98`) tagged `op: "extractPdfText.import"` with `nodeVersion` + `message` extras.
- [ ] 1.4 — Re-run `vitest run test/pdf-text-extract.test.ts`. Expect 0 failures.

## Phase 2 — Bug B: Resolver readFile-error must use the typed-error path

- [ ] 2.1 — Add `"read_failed"` to `PdfExtractErrorClass` (`pdf-text-extract.ts:56`).
- [ ] 2.2 — Run the three consumer-grep patterns (`cq-union-widening-grep-three-patterns`):
  - `rg "const _exhaustive: never" apps/web-platform/server/ apps/web-platform/lib/`
  - `rg "\.error === \"" apps/web-platform/server/ apps/web-platform/lib/`
  - `rg "\?\.error === \"" apps/web-platform/server/ apps/web-platform/lib/`
- [ ] 2.3 — Add `case "read_failed":` to `unreadableCopyForClass()` (`soleur-go-runner.ts:164`). User-facing copy: NEVER mentions "workspace", "boundary", or sandbox-internal concepts.
- [ ] 2.4 — Rewrite `kb-document-resolver.ts:235-240` PDF readFile catch: surface `documentExtractError: "read_failed"` AND mirror to Sentry with `op: "extractPdfText.readFile"`.
- [ ] 2.5 — Rewrite `kb-document-resolver.ts:254-266` text readFile catch: return `{}` (no-context) AND mirror to Sentry with `op: "readFile"`.
- [ ] 2.6 — Verify Phase 0.3 RED test now GREEN.
- [ ] 2.7 — Run `cc-dispatcher-concierge-context.test.ts` to confirm no regression from the text-file shape change.

## Phase 3 — Bug A: Directive injects absolute paths + sandbox tolerates relative paths

- [ ] 3.0a — Widen `buildPdfGatedDirective` signature to `(displayPath, absolutePath, noAskClause)`. Update the body to inject `absolutePath` in the `Use the Read tool to read "..."` substring.
- [ ] 3.0b — Update caller `soleur-go-runner.ts:703` (cc path): compute `path.join(workspacePath, safeArtifactPath)` and pass both. Note: `workspacePath` is not currently a `BuildSoleurGoSystemPromptArgs` field — thread it through `DispatchArgs` → `buildSoleurGoSystemPrompt`. Watch for surface widening implications (test seam in `agent-runner-query-options.test.ts` may need updating).
- [ ] 3.0c — Update caller `agent-runner.ts:752` (legacy PDF gated): same shape.
- [ ] 3.0d — Update text-too-large branch `soleur-go-runner.ts:722` to inject the absolute path. Same caller widening.
- [ ] 3.0e — Update text-too-large branch `agent-runner.ts:763` to inject the absolute path.
- [ ] 3.0f — Lock-step parity check: `git grep "Use the Read tool to read"` shows 3 source matches, all using the absolute-path variable.
- [ ] 3.1 — Widen `isPathInWorkspace` (`sandbox.ts:110`): if `filePath` is relative, `path.resolve(workspacePath, filePath)` BEFORE `realpathSync`. Refactor `resolveRealPath` accordingly.
- [ ] 3.2 — Verify both layers (sandbox-hook + canUseTool) reach the new code (no signature changes).
- [ ] 3.3 — Audit the 4 existing `isPathInWorkspace(...)` call sites for behavior preservation:
  - `sandbox-hook.ts:24` (file tools — paths from agent input, accepts both forms)
  - `permission-callback.ts:347-360` (canUseTool — paths from agent input, accepts both forms)
  - `kb-document-resolver.ts:143` (`fullPath` is already absolute via `path.join`)
  - `agent-runner.ts:744` (`fullPath` is already absolute via `path.join`)
- [ ] 3.4 — Verify Phase 0.2 RED test now GREEN. Add the path-traversal counter-tests in the same file: `..`-traversal still returns false; absolute outside workspace still returns false; absolute inside workspace still returns true.

## Phase 4 — Regression tests (lock-in)

- [ ] 4.1 — `apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts` — successful extraction → inline-body directive (NOT gated). Synthesize PDF via `makeMinimalPdf(...)`. Mock queryFactory to capture systemPrompt.
- [ ] 4.2 — Same file — `readFile` failure → `unreadable` directive with `read_failed` copy (NOT gated). Assert the system prompt does NOT contain "outside" / "workspace boundary".
- [ ] 4.3 — Bug A1 substring assertion: every directive's `Use the Read tool to read "..."` contains an absolute path (matches `/^Use the Read tool to read "\/[^"]+"/`).
- [ ] 4.4 — (Deferred to follow-through if e2e harness too brittle) Playwright e2e: open a real KB PDF, ask for summary, assert reply contains a real summary OR a content-grounded reply with no "workspace boundary" string. Zero `review_gate` WS frames on the wire.

## Phase 5 — Observability + follow-through

- [ ] 5.1 — Confirm Sentry op tags wired: `extractPdfText.readFile`, `extractPdfText.import`. Verify breadcrumb shape via unit test.
- [ ] 5.2 — Post-merge: re-run user's exact reproduction (`Au Chat Potan - Presentation Projet-10.pdf`, prompt "Can you please summarize this document?"). Post the result on issue #3376 and close it.
- [ ] 5.3 — PR body contains `Closes #3383, #3376` and `Ref #3342`.
- [ ] 5.4 — Verify Vercel deploy succeeded and the new `engines.node` constraint did not break the build.

## Cross-cutting

- [ ] CPO sign-off captured at plan-time per `single-user incident` threshold (User-Brand Impact section).
- [ ] `compound` skill run before commit; `preflight` Check 6 (User-Brand Impact gate) passes.
- [ ] `user-impact-reviewer` invoked at PR review time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.
