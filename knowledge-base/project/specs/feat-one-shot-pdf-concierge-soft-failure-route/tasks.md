# Tasks — feat-one-shot-pdf-concierge-soft-failure-route

Derived from `knowledge-base/project/plans/2026-05-07-fix-pdf-concierge-soft-failure-route-plan.md`.

## Phase 1 — Typed soft-failure predicate

- [ ] 1.1 Add `PDF_SOFT_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass>` containing `oversized_buffer | corrupted | parse_error | lazy_import_failed | read_failed` to `apps/web-platform/server/soleur-go-runner.ts` (above `buildSoleurGoSystemPrompt`).
- [ ] 1.2 Add `PDF_HARD_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass>` containing `encrypted | empty_text`.
- [ ] 1.3 Add `_AssertPartitionTotal` compile-time rail asserting the two sets partition `PdfExtractErrorClass` exhaustively.
- [ ] 1.4 Add `isPdfSoftFailure(errorClass)` predicate function.

## Phase 2 — Routing predicate

- [ ] 2.1 In `soleur-go-runner.ts:771` PDF branch, change the `if (args.documentExtractError)` body to partition on `isPdfSoftFailure(safeErrorClass)`. Soft → `buildPdfGatedDirective(safeArtifactPath, absoluteReadPath, NO_ASK)`. Hard → `buildPdfUnreadableDirective(safeArtifactPath, NO_ASK, safeErrorClass)`.
- [ ] 2.2 Update the comment block at lines 761–770 to describe the partition (text from plan Phase 4).
- [ ] 2.3 Verify `agent-runner.ts` is unchanged (`git diff --stat apps/web-platform/server/agent-runner.ts` empty).
- [ ] 2.4 Verify `buildPdfGatedDirective` / `buildPdfUnreadableDirective` factory bodies + lead constants are byte-identical pre/post.

## Phase 3 — Tests (RED-first per `cq-write-failing-tests-before`)

- [ ] 3.1 Flip `pdf-unreadable-directive.test.ts` soft-class assertions: `oversized_buffer`, `corrupted`, `parse_error`, `lazy_import_failed` — assert `PDF_GATED_DIRECTIVE_LEAD` present, `PDF_UNREADABLE_DIRECTIVE_LEAD` absent, keep `expectNoCascade(prompt)`.
- [ ] 3.2 Add `read_failed` soft-class test in `pdf-unreadable-directive.test.ts` (currently uncovered there).
- [ ] 3.3 Keep `encrypted` / `empty_text` tests as-is (hard route).
- [ ] 3.4 Update precedence test (line 160–176) to use the soft-class lead substring; add a hard-class twin using `encrypted`.
- [ ] 3.5 Flip `cc-concierge-pdf-summarize-e2e.test.ts` Phase 4.2: `read_failed` → assert gated lead present, unreadable lead absent, `"workspace boundary"` substring still absent. Drop the `read_failed`-specific copy assertion (gated directive is generic).
- [ ] 3.6 Add per-class describe block in `read-tool-pdf-capability.test.ts` walking `SOFT_CLASSES` and `HARD_CLASSES` exhaustively (test code in plan Phase 3c).
- [ ] 3.7 Run `bun run typecheck` — expect 0 new errors.
- [ ] 3.8 Run project test suite — expect 0 failures (baseline + flipped/added tests pass).

## Phase 4 — Compound + ship

- [ ] 4.1 Run `skill: soleur:compound` before commit (per `wg-before-every-commit-run-compound-skill`).
- [ ] 4.2 Capture session learning in `knowledge-base/project/learnings/<topic>.md` — partition-design + Anthropic Files API capability split. (Directory + topic only; date picked at write-time per `cq-do-not-prescribe-tasks-md-dates`.)
- [ ] 4.3 Multi-agent review: invoke `architecture-strategist`, `agent-native-reviewer`, `user-impact-reviewer`, `code-simplicity-reviewer` per `rf-review-finding-default-fix-inline`.
- [ ] 4.4 Address review findings inline.
- [ ] 4.5 CPO sign-off recorded (per `requires_cpo_signoff: true`).
- [ ] 4.6 Open PR with `Ref #3384` (or `Closes #<N>` if a tracking issue is filed). Apply semver:patch label.
- [ ] 4.7 Post-merge: manual reproduction on `Manning Book - Effective Platform Engineering.pdf` and `Au Chat Potan - Presentation Projet-10.pdf`. Capture screenshots.
- [ ] 4.8 Post-merge: 7-day Sentry sweep on `op:extractPdfText` breadcrumbs (informational).
