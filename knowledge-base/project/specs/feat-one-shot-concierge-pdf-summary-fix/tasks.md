# Tasks — fix(cc-concierge): durable PDF summary + suppress raw Bash modal

Plan: `knowledge-base/project/plans/2026-05-06-fix-cc-concierge-pdf-summary-and-bash-modal-plan.md`
Branch: `feat-one-shot-concierge-pdf-summary-fix`
Worktree: `.worktrees/feat-one-shot-concierge-pdf-summary-fix/`

## Phase 1 — `pdf-text-extract.ts` helper (TDD)

- [ ] 1.1 Write failing unit tests at `apps/web-platform/test/pdf-text-extract.test.ts` covering the 8 scenarios in the plan (small PDF, cap-truncated, corrupted, password-protected, empty, oversize input, basic text fidelity, page-count return).
- [ ] 1.2 Synthesize minimal PDF byte-array fixtures inline in the test file (no committed `.pdf` binaries — `cq-test-fixtures-synthesized-only`).
- [ ] 1.3 Implement `apps/web-platform/server/pdf-text-extract.ts` exporting `extractPdfText(buffer, capChars): Promise<{ text, truncated, pageCount } | null>` using `pdfjs-dist/legacy/build/pdf.mjs` with lazy import, `isEvalSupported: false`, `doc.destroy()`-in-finally. Cap input buffer at 15 MB; do NOT set `onPassword` (encrypted PDFs reject cleanly).
- [ ] 1.4 Verify `bun test apps/web-platform/test/pdf-text-extract.test.ts` is green.

## Phase 2 — Wire into `kb-document-resolver.ts`

- [ ] 2.1 Extend `resolveConciergeDocumentContext` PDF branch: `readFile(fullPath)` as Buffer (not utf-8), call `extractPdfText`, on success return `{ artifactPath, documentKind: "pdf", documentContent: text }`; on `null` fall through to existing `{ artifactPath, documentKind: "pdf" }` (Read directive).
- [ ] 2.2 Mirror failures to Sentry via `reportSilentFallback({ feature: "kb-concierge-context", op: "extractPdfText", extra: { userId, pathBasename, pageCount, truncated } })`.
- [ ] 2.3 Extend `apps/web-platform/test/cc-dispatcher-concierge-context.test.ts` with PDF-extraction scenarios (success, corrupted, oversize-cap fall-through).

## Phase 3 — Lock-step prompt-builder parity

- [ ] 3.1 Extend `buildSoleurGoSystemPrompt` `documentKind === "pdf"` branch in `apps/web-platform/server/soleur-go-runner.ts` to inline `documentContent` via the same `<document>...</document>` wrapper the `documentKind === "text"` branch uses (sanitizer + `</document>` escape + 50 KB cap).
- [ ] 3.2 Mirror the same change in `apps/web-platform/server/agent-runner.ts` artifact-injection block (~L580-632) — leader-side parity for the PDF-with-content branch.
- [ ] 3.3 Update `apps/web-platform/test/read-tool-pdf-capability.test.ts` with new scenarios (PDF-with-content inline, oversize fall-through, no-exclusion-list-on-inline-path).
- [ ] 3.4 Update `apps/web-platform/test/agent-runner-system-prompt.test.ts` parity assertions (the `supports PDF files` substring grep) for the new inline branch.
- [ ] 3.5 Verify `git grep "supports PDF files"` returns ≥4 matches (≥2 source + ≥2 test).

## Phase 4 — `cc-dispatcher.ts` toolset narrowing

- [ ] 4.1 Add `CC_PATH_ALLOWED_TOOLS = ["Read", "Glob", "Grep", "LS", "NotebookRead", "TodoWrite", "ExitPlanMode"]` near the top of `apps/web-platform/server/cc-dispatcher.ts`.
- [ ] 4.2 Pass `allowedTools: CC_PATH_ALLOWED_TOOLS` from `realSdkQueryFactory` to `buildAgentQueryOptions`.
- [ ] 4.3 Update `apps/web-platform/test/agent-runner-query-options.test.ts` cc-path snapshot — assert `allowedTools` is present and excludes `Bash`/`Edit`/`Write`. Legacy snapshot unchanged.
- [ ] 4.4 Add a regression test in `apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` (or similar) that constructs the cc-path Query and pins `allowedTools` shape.

## Phase 5 — Telemetry + reproduction verification

- [ ] 5.1 Add a Sentry breadcrumb in `kb-document-resolver.ts` capturing `{ pageCount, truncated, textBytes, pathBasename }` (PII-redacted; basename only) when `extractPdfText` runs.
- [ ] 5.2 Local reproduction: seed a workspace with a representative PDF under `knowledge-base/`, run `bun dev`, open KB UI on the PDF, ask "summarize this PDF", confirm content-grounded response with zero approval modals.
- [ ] 5.3 Capture Playwright MCP screenshot of the successful summary for the PR body.

## Phase 6 — Follow-through issue filing

- [ ] 6.1 File issue `chore(safe-bash): widen cc-path safe-bash allowlist for KB exploration parity with Claude Code plugin` (Post-MVP / Later).
- [ ] 6.2 File issue `feat(cc-chat): replace raw Bash approval modal with intent-shaped UX in Concierge surface` (Post-MVP / Later).
- [ ] 6.3 Create the parent GitHub issue tracking THIS plan's bug (currently `TBD` in YAML frontmatter); update plan frontmatter `issue:` field with the assigned number.

## Phase 7 — Ship

- [ ] 7.1 `tsc --noEmit` clean.
- [ ] 7.2 Multi-agent review (≥9 agents per `rf-review-finding-default-fix-inline`); 0 P1; all findings either fixed inline or filed as scope-out.
- [ ] 7.3 PR body uses `Closes #<plan-issue>`, `Ref #3332` (size-cap UX), `Ref #3243` (cc-dispatcher decomposition).
- [ ] 7.4 PR body Brand-Survival section captures CPO sign-off (carry-forward + explicit toolset-narrowing re-sign).
- [ ] 7.5 `user-impact-reviewer` review pass.
- [ ] 7.6 Post-merge: prod manual verification with the user's bug-report fixture.
