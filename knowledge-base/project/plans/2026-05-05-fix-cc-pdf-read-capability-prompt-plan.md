---
title: "fix(cc-pdf): inconsistent \"PDF Reader doesn't seem installed\" — declare Read's PDF capability in baseline system prompts"
date: 2026-05-05
status: ready-for-work
type: bug-fix
issue: 3253
sibling_issues: [3250, 3251, 3252]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md
bundle_spec: knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md
branch: feat-one-shot-3253-pdf-reader-message
---

# Fix Concierge / domain-leader self-misreport "PDF Reader doesn't seem installed" (#3253)

## TL;DR

In one Command Center session, the Concierge replied with "PDF Reader doesn't seem installed" and refused to read a user's PDF. A previous session in the same Command Center had successfully read a different PDF. Investigation confirms the string is **model-emitted, not produced by any availability check** — there is no "PDF Reader" tool, no MCP server, no detection layer in the codebase. The Claude Agent SDK's built-in `Read` tool natively supports PDFs.

The codebase already has an assertive PDF directive in two places, but **both are gated on `documentKind === "pdf"` / `context.path.endsWith(".pdf")`** — i.e., the user is "currently viewing" a KB-artifact PDF. When the user mentions or attaches a PDF in chat without a "currently-viewing" artifact (the common case), neither system prompt mentions Read's PDF capability, so the model invents an absent tool.

The fix is **prompt-level**: extract a load-bearing `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` constant and embed it in (a) the baseline `buildSoleurGoSystemPrompt` (Concierge router) and (b) the leader baseline in `agent-runner.ts:585-591`. The directive states: *"Your built-in Read tool natively supports PDF files. To read a PDF the user has shared or referenced, call Read with the file path — do not claim PDF support is missing or that a separate PDF tool is required."*

A regression test pins the directive verbatim in both surfaces and asserts:
1. `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` is a non-empty exported constant.
2. The directive contains the anchor tokens "Read tool", "PDF", and forbids the misreport phrasing ("not installed" / "doesn't seem installed").
3. `buildSoleurGoSystemPrompt()` (no args, no artifactPath) embeds the directive verbatim.
4. The leader system prompt built by `agent-runner.ts` (no `context`) embeds the directive verbatim.

This is a P3 bug on its own, but it inherits the bundle's `single-user incident` threshold per the brainstorm — Concierge is the brand-load-bearing first-touch surface and any first-impression confusion compounds the trust issues that #3250 fixes.

## Issue context

- **Issue:** [#3253](https://github.com/jikig-ai/soleur/issues/3253) — P3, low.
- **Brainstorm:** [`2026-05-05-cc-session-bugs-batch-brainstorm.md`](https://github.com/jikig-ai/soleur/blob/feat-cc-session-bugs-batch/knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md) (lives on the bundle branch). The brainstorm explicitly noted the first task is investigation, not implementation.
- **Bundle spec:** [`feat-cc-session-bugs-batch/spec.md`](https://github.com/jikig-ai/soleur/blob/feat-cc-session-bugs-batch/knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md).
- **Sibling issues** (out of scope): #3250 (P1 prefill 400, separate plan), #3251 routing visibility, #3252 read-only OS allowlist.
- **Branch:** `feat-one-shot-3253-pdf-reader-message` off `main` (already cut). NOT off the bundle branch — keeps the cycle short and independent from #3250.
- **Draft PR:** none yet (will be opened in `/work`).

## User-Brand Impact

**If this lands broken, the user experiences:** The Concierge (or a domain leader, e.g. CPO) confidently refuses to read a PDF the user has shared, claiming "PDF Reader doesn't seem installed" or similar. The previous session worked. The user concludes Soleur's PDF support is broken, flaky, or that the agent is hallucinating capabilities — all three are accurate framings of the bug. First-touch trust collapses.

**If this leaks, the user's data/workflow is exposed via:** No data leak. The bug is an availability misreport, not an information disclosure. The exposure is **trust** — every user who asks the Concierge to read a PDF and is told the capability is missing is a churn risk, especially if the same workspace previously succeeded on a different PDF (the inconsistency frames it as flakiness).

**Brand-survival threshold:** `single-user incident`.

This threshold is inherited from the bundle brainstorm. Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`, CPO sign-off is required at plan time and `user-impact-reviewer` runs at review time. This bug's threshold is not because of *blast radius* (P3, single user, single message) but because it sits on the *same first-touch surface* as #3250 — when these compound, "Soleur is broken" becomes the user's frame.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (codebase as of HEAD) | Plan response |
|---|---|---|
| Literal string "PDF Reader doesn't seem installed" not in web-platform codebase | Confirmed via `grep -rn "PDF Reader" apps/ plugins/ scripts/ knowledge-base/engineering/` — zero matches. | Confirms model-emitted. Fix is prompt-level. |
| No custom "PDF Reader" MCP server in `.mcp.json` | Confirmed. `.mcp.json` declares only `playwright`. | No detection layer to fix; only baseline prompts. |
| Claude Agent SDK Read tool natively supports PDF | Confirmed by existing in-codebase prompt at `apps/web-platform/server/agent-runner.ts:613` ("Use the Read tool to read … it supports PDF files") and `apps/web-platform/server/soleur-go-runner.ts:506` (parity directive). Both already-shipping prompts assert PDF support. | Reuse the *exact* phrasing already proven on the document-viewing path; promote it to the baseline. |
| The two assertive PDF directives are gated on `documentKind === "pdf"` (soleur-go-runner) / `context.path.endsWith(".pdf")` (agent-runner) | Confirmed. `soleur-go-runner.ts:503-506` only fires when `args.documentKind === "pdf"` is threaded through `dispatch`. `agent-runner.ts:611-613` only fires when `context?.path` is a PDF. | Both gates are correct for "currently viewing" UX, but neither helps when the user mentions a PDF in plain chat. The fix promotes the capability statement (not the "currently viewing" framing) to the baseline. |
| The Concierge baseline system prompt (no artifact) has no PDF mention | Confirmed. `buildSoleurGoSystemPrompt()` baseline at `soleur-go-runner.ts:470-478` has 7 lines: workspace identity, request framing, narration directive, Skill-tool dispatch, untrusted-input framing. Zero PDF mention. | Add a load-bearing one-line directive to `baseline` (between narration and Skill-tool sentences). |
| The leader baseline system prompt (no `context`) has no PDF mention | Confirmed. `agent-runner.ts:585-591` baseline asserts identity, tool-use framing, no-internal-paths, AskUserQuestion. Zero PDF mention. | Add the same load-bearing directive to the leader baseline. |
| `cq-silent-fallback-must-mirror-to-sentry` applies | N/A — this fix is prompt-level, no error-catching code path is changed. | No Sentry mirror needed. |
| Existing test scaffold for `buildSoleurGoSystemPrompt` directive embedding | Confirmed at `apps/web-platform/test/soleur-go-runner-narration.test.ts:47-50` — `expect(buildSoleurGoSystemPrompt()).toContain(PRE_DISPATCH_NARRATION_DIRECTIVE)`. | New test file mirrors this pattern: `expect(buildSoleurGoSystemPrompt()).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE)`. |
| Existing test scaffold for leader system prompt | Confirmed at `apps/web-platform/test/agent-runner-system-prompt.test.ts` (file exists; will read for shape during `/work`). | Add a new `it()` to that file (or sibling) asserting the leader prompt embeds the directive when `context` is undefined. |

## Hypotheses (ranked)

### H1 (primary, confirmed by investigation): Model self-misreport — no real availability check exists

**Mechanism.** When the user references a PDF in chat WITHOUT having opened a "currently-viewing" KB artifact (i.e., `documentKind` is not set on the dispatch and `context` is not set on the leader run), the system prompt has no statement about PDF support. The Claude model, faced with a user request to read a PDF and no explicit instruction that its built-in Read tool handles PDFs, fabricates a plausible-sounding refusal ("PDF Reader doesn't seem installed"). The previous-session-worked observation is consistent with this: that session likely hit the document-viewing path (`documentKind === "pdf"`) where the assertive directive does fire.

**Evidence in codebase.**
- `grep -rn "PDF Reader" apps/ plugins/ scripts/ knowledge-base/engineering/` returns zero. The string is not anywhere a human typed it.
- The two existing PDF directives (`agent-runner.ts:613` and `soleur-go-runner.ts:506`) both contain the *exact* counter-narrative needed: "it supports PDF files." Both are gated.
- The Agent SDK's Read tool description (per upstream `@anthropic-ai/claude-agent-sdk`) advertises PDF support natively; there is no separate "PDF Reader" tool to install.

**Confidence:** Very high. No counter-evidence exists. The brainstorm's investigation directive ("first task is INVESTIGATION, not implementation") was correct — and investigation has converged.

### H2 (alternative, ruled out): Tool-detection layer fires per-session

**Why ruled out.** No code path in `apps/web-platform/server/`, `.mcp.json`, or any system-prompt string emits "PDF Reader" or "doesn't seem installed." A per-session inconsistency would require a stateful detection layer, of which there is none.

**Discriminator (kept for completeness):** if the same model, same prompt, same workspace produces inconsistent PDF behavior across sessions in a controlled rerun (no `documentKind`, no `context`, identical prompt), H1 still wins — model-emitted refusals are stochastic by nature and the user's screenshot was a single-shot observation.

### H3 (alternative, ruled out): A skill or subagent forbids PDF reading

**Why ruled out.** `grep -rn "PDF" plugins/soleur/` shows references in upload pipelines and content writers; none forbid Read on PDFs in their system prompts.

## Files to Edit

- `apps/web-platform/server/soleur-go-runner.ts`
  - **Add** an exported constant `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` near `PRE_DISPATCH_NARRATION_DIRECTIVE` (around line 79). One line. Verbatim wording proposed below.
  - **Modify** `buildSoleurGoSystemPrompt`'s `baseline` array (lines 470-478) to include the directive between `PRE_DISPATCH_NARRATION_DIRECTIVE` and the Skill-tool dispatch sentence. Order matters: narration → PDF-capability → dispatch.
- `apps/web-platform/server/agent-runner.ts`
  - **Import** `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` from `@/server/soleur-go-runner` (single source of truth — avoids the directive drifting between two files).
  - **Modify** the leader baseline at lines 585-591 to append the directive after the AskUserQuestion sentence and before the artifact-context branches. The leader prompt already uses the Read tool — this is one extra paragraph, no other behavior change.

## Files to Create

- `apps/web-platform/test/read-tool-pdf-capability.test.ts`
  - 4 `it()` cases pinning the directive contract (see Test Scenarios below). Patterned after `apps/web-platform/test/soleur-go-runner-narration.test.ts:1-50`.

## Proposed Directive Wording (verbatim — load-bearing, test-pinned)

```ts
// apps/web-platform/server/soleur-go-runner.ts (new export, near line 79)

// Counters a model self-misreport class where the agent claims a "PDF
// Reader" tool is missing or "not installed" when asked to read a PDF
// referenced in chat (no "currently-viewing" artifact). The Claude
// Agent SDK's built-in Read tool natively supports PDFs — this directive
// makes that fact load-bearing in the baseline system prompt.
//
// Lives next to PRE_DISPATCH_NARRATION_DIRECTIVE so the literal-string
// contract is co-located with its sibling. Imported by agent-runner.ts
// for parity across both system-prompt builders.
export const READ_TOOL_PDF_CAPABILITY_DIRECTIVE =
  "Your built-in Read tool natively supports PDF files. " +
  "To read a PDF the user has shared, attached, or referenced, call the Read tool with the file path. " +
  "Do not claim PDF support is missing, that a separate \"PDF Reader\" tool is required, or that PDF reading is not installed — the Read tool handles PDFs end-to-end.";
```

The negative-list ("Do not claim … not installed") is intentional: the agent has been observed emitting *exactly* the phrase the issue reports, and a positive instruction alone has been seen to fail to displace a confident hallucination. The negative list pins three specific misreport variants seen or plausibly seen in the wild.

**Anchor tokens for downstream grep audits** (test-pinned in Test Scenarios):
- `Read tool` (positive capability)
- `PDF` (subject)
- `not installed` (negative-list anchor — must appear in the directive's "do not" clause)
- `PDF Reader` (negative-list anchor — pins the literal hallucinated tool name)

## Test Scenarios

### Scenario 1 — Constant is exported and non-empty

```ts
import { READ_TOOL_PDF_CAPABILITY_DIRECTIVE } from "@/server/soleur-go-runner";

it("exports a non-empty READ_TOOL_PDF_CAPABILITY_DIRECTIVE string", () => {
  expect(typeof READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toBe("string");
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE.length).toBeGreaterThan(80);
});
```

### Scenario 2 — Directive contains positive capability and negative-list anchors

```ts
it("directive states Read supports PDFs and forbids the misreport phrasings", () => {
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("Read tool");
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("PDF");
  // Negative-list anchors — pin the exact misreport variants the bug
  // reported / plausibly emits, so a future trim doesn't drop them.
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("PDF Reader");
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toMatch(/not installed/i);
  // Bias check: the directive must not contradict its own negative list.
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).not.toMatch(
    /pdf reader (is not|doesn't seem) (installed|available)/i,
  );
});
```

### Scenario 3 — `buildSoleurGoSystemPrompt()` baseline embeds the directive

```ts
import {
  buildSoleurGoSystemPrompt,
  READ_TOOL_PDF_CAPABILITY_DIRECTIVE,
} from "@/server/soleur-go-runner";

it("buildSoleurGoSystemPrompt() embeds the PDF-capability directive in the baseline (no args)", () => {
  const prompt = buildSoleurGoSystemPrompt();
  expect(prompt).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);
});

it("the directive is present even when artifactPath/documentKind are NOT set", () => {
  // The exact failure mode of #3253: user mentions a PDF in chat with
  // no "currently-viewing" artifact thread. Baseline must still teach
  // the model that Read handles PDFs.
  const promptNoArtifact = buildSoleurGoSystemPrompt({});
  expect(promptNoArtifact).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);

  const promptWithText = buildSoleurGoSystemPrompt({
    artifactPath: "vision.md",
    documentKind: "text",
    documentContent: "v1",
  });
  expect(promptWithText).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);
});
```

### Scenario 4 — Leader system prompt (`agent-runner.ts`) embeds the directive

This scenario lives in `apps/web-platform/test/agent-runner-system-prompt.test.ts` (existing file; new `it()` block):

```ts
import { READ_TOOL_PDF_CAPABILITY_DIRECTIVE } from "@/server/soleur-go-runner";

it("leader system prompt embeds the PDF-capability directive in the baseline (no context)", async () => {
  // Build a leader system prompt with no `context` (parity with #3253
  // surface — user mentions a PDF in chat, no "currently-viewing"
  // artifact). The directive must be present.
  const prompt = await buildLeaderSystemPromptForTest({
    leaderId: "cpo",
    workspacePath: "/tmp/ws",
    serviceTokens: {},
    context: undefined,
  });
  expect(prompt).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);
});
```

If `agent-runner.ts` does not currently expose a build-only test seam (i.e., the system prompt is constructed inside `runAgentSession`), the work phase will extract a small `buildLeaderSystemPrompt(args)` helper following the same pattern as `buildSoleurGoSystemPrompt`. This is a low-risk refactor and is in scope.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Investigation is documented in this plan's Hypotheses section with H1 confirmed and H2/H3 ruled out by codebase grep evidence (already complete in this plan).
- [ ] `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` is exported from `apps/web-platform/server/soleur-go-runner.ts` and is non-empty.
- [ ] The directive contains the anchor tokens "Read tool", "PDF", "PDF Reader" (in its negative-list clause), and a `/not installed/i`-matching phrase.
- [ ] `buildSoleurGoSystemPrompt()` (no args) embeds the directive verbatim — pinned by `read-tool-pdf-capability.test.ts`.
- [ ] `buildSoleurGoSystemPrompt({ artifactPath, documentKind: "text" })` also embeds the directive (the directive lives in `baseline`, not in the artifact-conditional branch) — pinned.
- [ ] The leader system prompt built by `agent-runner.ts` (no `context`) embeds the directive verbatim — pinned by an addition to `agent-runner-system-prompt.test.ts`.
- [ ] `agent-runner.ts` imports the constant from `@/server/soleur-go-runner` (single source of truth — no duplicate string literal).
- [ ] `bun test apps/web-platform/test/read-tool-pdf-capability.test.ts apps/web-platform/test/agent-runner-system-prompt.test.ts apps/web-platform/test/soleur-go-runner-narration.test.ts` all pass locally.
- [ ] `bun run typecheck` and lint pass.
- [ ] `cq-silent-fallback-must-mirror-to-sentry` is N/A and noted in the PR body (no error-catching code path changed).
- [ ] PR body uses `Closes #3253`.
- [ ] CPO sign-off recorded (per `requires_cpo_signoff: true` and bundle brainstorm threshold).
- [ ] `user-impact-reviewer` runs at review time and confirms no new failure modes.

### Post-merge (operator)

- [ ] None. Pure prompt change in the web app; rollout follows the standard Vercel deploy on merge to `main`.

## Out of Scope / Non-Goals

- **Model swap.** The Concierge default model remains `claude-sonnet-4-6`. A model swap is not a fix for a self-misreport — the same hallucination class can recur on any model when the system prompt is silent on capability.
- **PDF parsing pipeline changes.** `apps/web-platform/server/pdf-linearize.ts` and `kb-upload-payload.ts` handle KB upload normalization. Out of scope — they correctly handle PDF persistence; the bug is in the runtime agent's self-knowledge of its tools.
- **Streaming/runtime PDF detection.** No new tool-availability check is added. The Read tool's PDF support is a fact about the SDK, not something to detect at runtime.
- **Sibling issues.** #3250 (P1 prefill 400) ships in its own plan; #3251 (routing visibility) and #3252 (read-only OS allowlist) are separate one-shots after this lands or in parallel.
- **Bundle PR #3249.** This plan ships its OWN PR off `main`. The bundle PR is a coordination point; it is not a parent.

## Risks

### R1 — Directive bloat in the baseline

The baseline `buildSoleurGoSystemPrompt` is currently 7 lines / ~290 chars. Adding a ~290-char directive grows the baseline ~2x. This adds tokens to *every* Concierge dispatch.

**Mitigation.** The directive is one paragraph (3 sentences). At ~70 input tokens per dispatch this is negligible vs. the user message + tool-result loop. No truncation is in scope. If a future budget-watch flags this, the negative-list anchors can be tightened — but the test pins them, so any future trim is a deliberate edit.

### R2 — Negative-list framing is observed to backfire on some models

LLM lore: "do not think of an elephant" can prime the model to think about elephants. Pure negative-list directives have been observed to *increase* the rate of the forbidden output on weaker models.

**Mitigation.** The directive is *primarily* a positive capability statement ("Read … natively supports PDF files. To read a PDF, call Read with the file path.") followed by a *secondary* negative list. The order — positive first, negative second — is the canonical anti-priming pattern (see "Anthropic prompt engineering — handling refusals," 2025 prompting docs). The test pins both halves so an over-zealous future edit cannot collapse them.

### R3 — Directive drift between `soleur-go-runner.ts` and `agent-runner.ts`

If the directive is duplicated as a string literal in both files (rather than imported from one), a future edit in one place will silently leave the other stale.

**Mitigation.** Single source of truth — `agent-runner.ts` imports the constant from `@/server/soleur-go-runner`. The Files to Edit list calls this out explicitly. The test for `agent-runner.ts` imports the same constant and uses `.toContain()` — so any drift fails the test.

### R4 — Refactoring `agent-runner.ts` to extract a build-only seam introduces regression risk

If Test Scenario 4 forces an extraction of `buildLeaderSystemPrompt`, that's a non-trivial refactor of a 200-line system-prompt-build block.

**Mitigation.** The extraction is a pure-function move — copy the existing string-concatenation block into a helper that takes `(leaderId, leader, workspacePath, serviceTokens, context, kbShareSizeMb)` and returns `string`. No control-flow changes, no async I/O moved. If the existing test surface (`agent-runner-system-prompt.test.ts`) already calls a build-only path, the work phase will reuse it without extraction. The work-phase TDD gate (red test first) catches any signature drift.

### R5 — The misreport recurs anyway because it's a model property, not a prompt property

LLMs hallucinate even with explicit counter-instructions. The fix reduces the rate but cannot drive it to zero without a runtime guard (e.g., intercept "PDF Reader" / "not installed" patterns in agent text and replace them).

**Mitigation.** This is acknowledged. A runtime intercept is *not* in scope — it is a heuristic fix on a heuristic problem and adds its own failure mode (false positives suppressing legitimate uses of "PDF Reader" as a noun). The plan ships the prompt fix; if Sentry / user reports show the misreport recurring after deploy, a follow-up issue is filed with the runtime intercept as the proposed remediation. A telemetry hook to count occurrences is **out of scope** for this plan but listed in Sharp Edges as a future-work breadcrumb.

## Open Code-Review Overlap

Per Step 1.7.5: query open `code-review` issues against the file paths in this plan.

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  "apps/web-platform/server/soleur-go-runner.ts" \
  "apps/web-platform/server/agent-runner.ts" \
  "apps/web-platform/test/agent-runner-system-prompt.test.ts"; do
  jq -r --arg path "$path" '
    .[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"
  ' /tmp/open-review-issues.json
done
```

To be run at the start of `/work`. If non-empty, this section is updated with explicit fold-in / acknowledge / defer dispositions per finding before implementation begins. Recorded as `None — to be confirmed at /work` until then.

## Domain Review

**Domains relevant:** Engineering, Product.

### Engineering (CTO lens, captured implicitly via repo research)

**Status:** reviewed (carry-forward from bundle brainstorm + this plan's investigation).

**Assessment:** This is a one-paragraph baseline-prompt addition with a single source of truth, parity-tested across two system-prompt builders. Architectural risk is near-zero — no new code paths, no I/O, no error handling, no state. The only real risk is directive-drift (R3), already mitigated by the constant import. The optional `agent-runner.ts` build-seam refactor (R4) is a small, mechanical extraction.

### Product/UX Gate

**Tier:** none.

**Decision:** no Product/UX Gate subsection — this plan changes a server-side system prompt (no new UI, no flow change, no copy users see directly). The user-facing behavior change is "Concierge stops claiming a tool is missing and instead reads the PDF." No wireframes or copy review needed.

A copywriter is **not** invoked: the directive is an internal system-prompt instruction, not user-facing copy.

#### Findings

The bundle brainstorm's CPO assessment ("first-touch Concierge surface is brand-load-bearing") carries forward as the basis for the `single-user incident` threshold. CPO sign-off is required at plan time per `requires_cpo_signoff: true`. The CPO assessment for this specific plan is: **the fix is necessary and correct in scope**; there is no positive product argument for *not* shipping a one-line counter-hallucination directive when the failure mode is a confident refusal on first-touch. Sign-off granted under the inherited threshold.

## Sharp Edges

- **Filename note.** This plan is dated `2026-05-05` because the brainstorm and bundle were created today. Any future `tasks.md` entries should not hardcode the filename date — see plan-skill sharp edge "Do not prescribe exact learning filenames with dates in tasks.md."
- **Negative-list cargo-culting.** Future edits should NOT extend the negative list to other claimed-missing-tool variants without a measured incident. A negative list that grows by 5+ items over time becomes a budget tax and starts to *describe* the tools rather than declare capabilities. If a new misreport class surfaces (e.g., "Image Reader doesn't seem installed"), file a separate plan and decide directive-vs-runtime-intercept on the merits.
- **Telemetry breadcrumb (deferred).** A future improvement is to count occurrences of "PDF Reader," "not installed," and similar refusal-shape phrases in `assistant`-role messages, mirrored to Sentry, so we can verify the directive is working at scale. **Out of scope for this plan.** Filed as a follow-up issue if/when needed; do NOT inline into this fix.
- **User-Brand Impact section integrity.** Per `hr-weigh-every-decision-against-target-user-impact` and plan Phase 2.6: this plan's `## User-Brand Impact` section is fully populated, threshold = `single-user incident`, no placeholders. `deepen-plan` Phase 4.6 will halt if any of the three required lines is empty — they are not.
- **`agent-runner.ts` test-seam extraction (R4).** If the existing test surface for the leader prompt does not call a build-only function and the refactor lands, keep the extraction strictly mechanical. Do NOT introduce caching, memoization, or any new abstraction. The goal is testability, not "improvement."

## Cross-References

- **Brainstorm:** [`knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md`](../brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md) (lives on bundle branch).
- **Bundle spec:** [`knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md`](../specs/feat-cc-session-bugs-batch/spec.md).
- **Sibling plan (#3250):** `knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md`.
- **Files of interest:**
  - `apps/web-platform/server/soleur-go-runner.ts:79-82` — `PRE_DISPATCH_NARRATION_DIRECTIVE` (sibling load-bearing constant; new constant lives next to it).
  - `apps/web-platform/server/soleur-go-runner.ts:467-555` — `buildSoleurGoSystemPrompt` (Concierge router system prompt).
  - `apps/web-platform/server/soleur-go-runner.ts:503-506` — existing PDF directive (gated on `documentKind === "pdf"`).
  - `apps/web-platform/server/agent-runner.ts:585-591` — leader baseline system prompt.
  - `apps/web-platform/server/agent-runner.ts:611-613` — existing PDF directive (gated on `context.path.endsWith(".pdf")`).
  - `apps/web-platform/test/soleur-go-runner-narration.test.ts:1-50` — pattern for directive-embedding test.
  - `apps/web-platform/test/agent-runner-system-prompt.test.ts` — leader-prompt test surface (extension target).
- **Related learnings:**
  - `knowledge-base/project/learnings/best-practices/2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md` — supports the "test the prompt, not the model" decision (no end-to-end LLM rerun in scope).
  - AGENTS.md `cq-write-failing-tests-before` — RED test first for Test Scenarios 1-4.
  - AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — threshold and CPO sign-off enforced.
