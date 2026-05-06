# Tasks — fix(cc-pdf): #3253 PDF Reader misreport

Derived from `knowledge-base/project/plans/2026-05-05-fix-cc-pdf-read-capability-prompt-plan.md`.

## Phase 1 — RED (tests first)

1. **Read existing test patterns** before authoring new tests.
   - 1.1. Read `apps/web-platform/test/soleur-go-runner-narration.test.ts` — pattern for directive-embedding asserts.
   - 1.2. Read `apps/web-platform/test/agent-runner-system-prompt.test.ts` — find or design a build-only test seam for the leader prompt.

2. **Author `apps/web-platform/test/read-tool-pdf-capability.test.ts`** with five scenarios (deepen-pass updated — purely positive directive, anti-priming guard, symmetry test):
   - 2.1. Scenario 1 — `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` is exported, non-empty (>80 chars).
   - 2.2. Scenario 2 — directive contains positive anchors `Read tool`, `PDF`, and `supports PDF files`. Anti-priming guard: directive does NOT match `/\b(do not|never|not installed)\b/i`. (No negative-list anchors — purely positive per 2026 prompt-engineering best practice.)
   - 2.3. Scenario 3 — `buildSoleurGoSystemPrompt()` baseline (no args) embeds the directive verbatim. Also assert it's present with `documentKind: "text"` artifact (proves it lives in baseline, not artifact branch).
   - 2.4. Scenario 5 (new) — `buildSoleurGoSystemPrompt({ artifactPath: "research.pdf", documentKind: "pdf" })` contains BOTH the new baseline directive AND the existing assertive "currently viewing the PDF document" directive. Pins symmetry against a future edit that "merges" them and accidentally drops the baseline.

3. **Author Scenario 4** in `apps/web-platform/test/agent-runner-system-prompt.test.ts` — reuse the existing harness:
   - 3.1. New `test()` adjacent to lines 146-238 — runs `runAgentSession` with no `context`, captures `mockQuery.mock.calls[0][0].systemPrompt`, asserts it contains the directive.
   - 3.2. **No `buildLeaderSystemPrompt` extraction needed** (deepen-pass finding — R4 retired). The existing test pattern captures `systemPrompt` end-to-end.

4. **Run the suite — confirm RED.**
   - 4.1. `bun test apps/web-platform/test/read-tool-pdf-capability.test.ts` — must fail on missing export.
   - 4.2. Phase-1 commit: `test: failing tests for #3253 PDF capability directive`.

## Phase 2 — GREEN (minimum implementation)

5. **Add `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` constant** in `apps/web-platform/server/soleur-go-runner.ts`:
   - 5.1. Place the export near `PRE_DISPATCH_NARRATION_DIRECTIVE` (around line 79).
   - 5.2. Verbatim wording from plan §"Proposed Directive Wording" — **purely positive, two sentences** (declarative-then-imperative). No negation tokens.
   - 5.3. Re-run Scenarios 1, 2 — should pass.

6. **Embed in `buildSoleurGoSystemPrompt` baseline:**
   - 6.1. Insert into the `baseline` array (lines 470-478) between `PRE_DISPATCH_NARRATION_DIRECTIVE` and the Skill-tool dispatch sentence.
   - 6.2. Keep one blank line on each side for prompt readability.
   - 6.3. Re-run Scenario 3 — should pass.

7. **Embed in the leader system prompt** in `apps/web-platform/server/agent-runner.ts`:
   - 7.1. Add `import { READ_TOOL_PDF_CAPABILITY_DIRECTIVE } from "@/server/soleur-go-runner"`.
   - 7.2. Append the directive to the leader baseline (after the AskUserQuestion sentence, line 591) and before the artifact-context branches.
   - 7.3. **No extraction needed** (R4 retired per deepen pass). Use the existing test harness in `agent-runner-system-prompt.test.ts` directly.
   - 7.4. Re-run Scenario 4 — should pass.

8. **Confirm full test suite passes.**
   - 8.1. `bun test apps/web-platform/test/read-tool-pdf-capability.test.ts apps/web-platform/test/agent-runner-system-prompt.test.ts apps/web-platform/test/soleur-go-runner-narration.test.ts`.
   - 8.2. `bun run typecheck`. `bun run lint`.
   - 8.3. Phase-2 commit: `fix(cc-pdf): declare Read PDF capability in baseline system prompts`.

## Phase 3 — REFACTOR / Polish

9. **Single-source-of-truth audit.**
   - 9.1. `rg "READ_TOOL_PDF_CAPABILITY_DIRECTIVE" apps/web-platform/` — confirm only ONE definition (in `soleur-go-runner.ts`), all other call sites are imports.
   - 9.2. Confirm no duplicate string-literal in `agent-runner.ts` (search for any substring of the directive).

10. **Telemetry breadcrumb (NO CODE — documentation only).**
    - 10.1. Add a one-line comment near the constant referencing the deferred runtime-intercept option (see plan §Sharp Edges). Do NOT inline a counter or interceptor.

11. **Deepen-plan + plan-review carry.**
    - 11.1. Address findings from `soleur:deepen-plan` (Phase 4 of plan workflow).
    - 11.2. Apply any plan-review changes (DHH / Kieran / code-simplicity) before /work.

## Phase 4 — Compound + Ship

12. **Run `/soleur:compound`** to capture any session learnings (e.g., negative-list framing, sibling-builder parity).

13. **Open PR via `/soleur:ship`.**
    - 13.1. Title: `fix(cc-pdf): inconsistent "PDF Reader doesn't seem installed" message`.
    - 13.2. Body includes `Closes #3253`.
    - 13.3. CPO sign-off recorded in PR body (per `requires_cpo_signoff: true`).
    - 13.4. Labels: `bug`, `priority/p3-low`, `semver:patch` (carry from issue).

14. **Review pipeline.**
    - 14.1. `user-impact-reviewer` runs at review time per AGENTS.md `hr-weigh-every-decision-against-target-user-impact` (single-user-incident threshold).
    - 14.2. Address any review findings inline per `rf-review-finding-default-fix-inline`.
    - 14.3. Resolve all open review threads before merging.

15. **Auto-merge + post-merge.**
    - 15.1. `gh pr merge <number> --squash --auto`. Poll `gh pr view <number> --json state --jq .state` until `MERGED`.
    - 15.2. `cleanup-merged`.
    - 15.3. Verify Vercel deploy + the docs/release workflow succeed (per `wg-after-a-pr-merges-to-main-verify-all`).

## Out of Scope (deferred / non-goals)

- Model swap. Out per plan.
- Runtime intercept of refusal-shape strings. Out per plan; future-work breadcrumb only.
- Telemetry counter for misreport occurrences. Out per plan; file as separate issue if needed post-deploy.
- PDF parsing pipeline changes (`pdf-linearize.ts`, `kb-upload-payload.ts`). Out — they handle KB upload; the bug is agent self-knowledge, not parsing.
- Sibling issues (#3250, #3251, #3252). Each ships in its own plan/PR.
