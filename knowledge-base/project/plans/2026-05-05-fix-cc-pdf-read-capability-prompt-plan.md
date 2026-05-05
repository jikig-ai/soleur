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

## Enhancement Summary

**Deepened on:** 2026-05-05

**Sections enhanced:** Proposed Directive Wording, Test Scenarios, Risks (R2 + R4), Sharp Edges, Cross-References.

**Research sources used:**
- WebSearch — 2025-2026 prompt-engineering best-practices corpus (Lakera, k2view, Gadlet, buildmvpfast). Convergent finding: **negative instructions actively underperform** at scale; "do not / never" framings overtrigger Claude and produce worse results in 2026.
- WebFetch — Gadlet "Why Positive Prompts Outperform Negative Ones with LLMs" — three independent benchmarks (InstructGPT scaling, NeQA, multi-model GPT-3/GPT-Neo) all show negation handling does NOT improve with scale. Recommended pattern: **convert negatives to positive directives entirely** ("Always lowercase names" not "Don't uppercase names").
- Codebase grep — confirmed the existing in-codebase PDF directives at `agent-runner.ts:613` and `soleur-go-runner.ts:506` are already **purely positive** ("This is a PDF file. Use the Read tool — it supports PDF files"). They have shipped successfully for the document-viewing path; symmetry argues the baseline directive should follow the same shape.
- Local learning — `knowledge-base/project/learnings/2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md`. Same surface, same builder family (`buildSoleurGoSystemPrompt`), different gap (PR #3213 closed the gated-PDF context drop; this plan closes the *baseline*-PDF capability gap). Both gaps share a root cause: **the cc-soleur-go cutover left the baseline thinner than the legacy `agent-runner.ts` baseline assumed it was**.
- Local learning — `knowledge-base/project/learnings/2026-02-13-agent-prompt-sharp-edges-only.md`. Embed only sharp edges; do NOT include knowledge Claude has from training. The PDF-capability fact is exactly a sharp edge — the model otherwise hallucinates a missing tool.
- Test-shape audit — `apps/web-platform/test/agent-runner-system-prompt.test.ts:135-238`. The existing tests already capture `mockQuery.mock.calls[0][0].systemPrompt` end-to-end via `runAgentSession`. **No build-only seam extraction is needed** for Scenario 4 — Risk R4 drops to near-zero.

### Key Improvements

1. **Directive wording rewritten as purely positive.** The 2026 prompt-engineering corpus is unambiguous: pure-positive directives outperform mixed positive+negative. The original draft's negative list ("Do not claim … not installed") was self-undermining (priming the exact phrase the bug emits). New wording matches the existing in-codebase pattern at `soleur-go-runner.ts:506` verbatim — already proven on the gated path. **Anchor tokens for the test contract simplified accordingly:** keep `Read tool`, `PDF`, `supports PDF files` (positive); drop `not installed` and `PDF Reader` negative-list pins.
2. **Test contract aligned with existing `agent-runner-system-prompt.test.ts` pattern.** Scenario 4 now uses the existing end-to-end harness (`runAgentSession` + `mockQuery.mock.calls[0][0].systemPrompt`) — no `buildLeaderSystemPrompt` extraction needed. Risk R4 retired.
3. **Anchor-token grep audit added to Acceptance Criteria.** A `rg "Read tool" apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` post-edit must show the new directive's tokens AND keep all five existing PDF-aware mentions intact (no accidental deletions).
4. **Symmetry test added.** New Test Scenario 5: when `documentKind === "pdf"` IS set, the system prompt contains BOTH the new baseline directive AND the existing assertive "currently viewing" directive — the two are non-conflicting and additive. This pins against a future edit that "merges" them and accidentally drops the baseline.
5. **Cross-builder import unification.** `agent-runner.ts` imports `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` from `@/server/soleur-go-runner` — single source of truth, matches the existing pattern where `cc-dispatcher.ts` references `buildSoleurGoSystemPrompt` from the same module (line 691 docstring).

### New Considerations Discovered

- **Sibling-baseline gap class.** The cc-soleur-go cutover (PR #2901) replaced a 200-line `agent-runner.ts` system-prompt builder with a 5-line `buildSoleurGoSystemPrompt` baseline. Several capability statements that were implicit in the legacy leader-baseline ("you are a leader using tools to read knowledge-base files") are absent from the cc-soleur-go baseline — PDFs are one such gap, and PR #3213 closed the *gated* artifact-context gap. A follow-up audit is warranted: are there other capability declarations that the legacy leader prompt asserted (e.g., "use the Edit tool for in-place updates", "use Write to create new files") that the new Concierge baseline is silent on? **Out of scope for this plan**; filed as a Sharp Edge breadcrumb only — the symptom that would justify a follow-up is another model-emitted "tool X doesn't seem installed" report.
- **Capability-declaration tone consistency.** The existing baseline (`PRE_DISPATCH_NARRATION_DIRECTIVE` and the dispatch sentences) uses imperative voice ("Before invoking the Skill tool, emit a one-line text block"). The new directive should match — **declarative-then-imperative** ("Your built-in Read tool natively supports PDF files. Use the Read tool with the file path to read a PDF the user has shared, attached, or referenced."). The original draft mixed declarative + negative-list, breaking tonal consistency.
- **Test fragility from anchor-token over-pinning.** The original plan pinned five anchor tokens including two negative-list anchors. After the rewrite, the test pins three positive anchors only (`Read tool`, `PDF`, `supports PDF files`) plus a length floor. This is more robust to future wording revisions while still rejecting any accidental deletion.
- **`agent-runner.ts` end-to-end test cost.** The existing `agent-runner-system-prompt.test.ts` runs `runAgentSession` with ~60 lines of mock setup. Adding one `it()` to it costs ~5 lines (one assert against `options.systemPrompt`) — much cheaper than the originally proposed `buildLeaderSystemPrompt` extraction, which would have touched ~80 lines of `agent-runner.ts`. Scenario 4 cost reduced.
- **AGENTS.md `cq-agents-md-why-single-line` does NOT trigger.** This plan adds no new AGENTS.md rule. The fix is a domain-scoped edit (system-prompt layer); the learning file at `/work` time will document the negative-vs-positive framing finding without an AGENTS.md addition.

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

// Counters a model self-misreport class where the agent claims a separate
// "PDF Reader" tool is missing when asked to read a PDF referenced in
// chat (no "currently-viewing" artifact). The Claude Agent SDK's
// built-in Read tool natively supports PDFs — this directive makes that
// fact load-bearing in the baseline system prompt. Wording mirrors the
// existing assertive directive at soleur-go-runner.ts:506 / agent-runner.ts:613,
// which has shipped successfully on the document-viewing path.
//
// Lives next to PRE_DISPATCH_NARRATION_DIRECTIVE so the literal-string
// contract is co-located with its sibling. Imported by agent-runner.ts
// for parity across both system-prompt builders.
export const READ_TOOL_PDF_CAPABILITY_DIRECTIVE =
  "Your built-in Read tool natively supports PDF files. " +
  "To read a PDF the user has shared, attached, or referenced, " +
  "call the Read tool with the file path — it handles PDFs end-to-end.";
```

**Why purely positive** (deepen-pass finding): The 2026 prompt-engineering corpus (Lakera, k2view, Gadlet citing InstructGPT/NeQA benchmarks) converges on the same conclusion — **negative instructions ("do not", "never") underperform at scale and overtrigger Claude**. The original draft's negative list ("Do not claim PDF support is missing … not installed") is exactly the anti-pattern. It also primes the model with the very phrase the bug emits, which can backfire. The corrected wording follows the codebase's own existing pattern at `soleur-go-runner.ts:506` — purely declarative-then-imperative — which has shipped successfully on the gated PDF path.

**Anchor tokens for downstream grep audits** (test-pinned in Test Scenarios):
- `Read tool` (positive capability anchor)
- `PDF` (subject anchor)
- `supports PDF files` (load-bearing capability claim — exact substring shared with `soleur-go-runner.ts:506` and `agent-runner.ts:613`)

## Test Scenarios

### Scenario 1 — Constant is exported and non-empty

```ts
import { READ_TOOL_PDF_CAPABILITY_DIRECTIVE } from "@/server/soleur-go-runner";

it("exports a non-empty READ_TOOL_PDF_CAPABILITY_DIRECTIVE string", () => {
  expect(typeof READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toBe("string");
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE.length).toBeGreaterThan(80);
});
```

### Scenario 2 — Directive is purely positive and pins the load-bearing capability claim

```ts
it("directive states Read supports PDFs (purely positive — no negation)", () => {
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("Read tool");
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("PDF");
  // Load-bearing capability claim — exact substring shared with the
  // existing assertive directives at soleur-go-runner.ts:506 and
  // agent-runner.ts:613 (so a single substring grep audits all three).
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).toContain("supports PDF files");
  // Anti-priming guard: the directive MUST NOT contain negation tokens
  // ("do not", "never", "not installed"). Per 2026 prompt-engineering
  // best practice (Lakera/Gadlet/k2view), negation underperforms at
  // scale and overtriggers Claude. A future edit that re-introduces
  // "Do not claim …" must fail this test.
  expect(READ_TOOL_PDF_CAPABILITY_DIRECTIVE).not.toMatch(/\b(do not|never|not installed)\b/i);
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

Lives in `apps/web-platform/test/agent-runner-system-prompt.test.ts` as a new `test()` block. Reuses the existing harness (no extraction needed):

```ts
import { READ_TOOL_PDF_CAPABILITY_DIRECTIVE } from "@/server/soleur-go-runner";

test("leader system prompt embeds the PDF-capability directive in the baseline (no context)", async () => {
  // Mirrors the existing tests at lines 146-238: spin up runAgentSession
  // with no `context` (parity with #3253 — user mentions a PDF in chat
  // with no "currently-viewing" artifact) and inspect the systemPrompt
  // captured by the mocked SDK query.
  await runAgentSessionForTest({ /* baseline args, no context */ });
  const options = mockQuery.mock.calls[0][0];
  expect(options.systemPrompt).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);
});
```

**No `buildLeaderSystemPrompt` extraction is needed** (deepen-pass finding). The existing test file at `apps/web-platform/test/agent-runner-system-prompt.test.ts:135-238` already captures `mockQuery.mock.calls[0][0].systemPrompt` end-to-end via `runAgentSession`. Risk R4 (refactor risk from the original plan) is retired.

### Scenario 5 — Symmetry: baseline directive + gated directive coexist when artifact IS a PDF

```ts
test("buildSoleurGoSystemPrompt with documentKind: pdf contains BOTH baseline directive AND gated directive", () => {
  // Future-proof against a "merge the two PDF mentions" refactor that
  // accidentally drops one. The baseline directive teaches the model
  // about Read's PDF capability in general; the gated directive
  // additionally tells it which specific PDF the user is viewing.
  // Both must be present on the gated path.
  const prompt = buildSoleurGoSystemPrompt({
    artifactPath: "research.pdf",
    documentKind: "pdf",
  });
  expect(prompt).toContain(READ_TOOL_PDF_CAPABILITY_DIRECTIVE);  // baseline
  expect(prompt).toContain("currently viewing the PDF document"); // gated
});
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Investigation is documented in this plan's Hypotheses section with H1 confirmed and H2/H3 ruled out by codebase grep evidence (already complete in this plan).
- [ ] `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` is exported from `apps/web-platform/server/soleur-go-runner.ts` and is non-empty.
- [ ] The directive contains the anchor tokens "Read tool", "PDF", and the substring "supports PDF files" (shared verbatim with the existing assertive directives at `soleur-go-runner.ts:506` and `agent-runner.ts:613`).
- [ ] The directive does NOT contain negation tokens (`/\b(do not|never|not installed)\b/i`) — pinned by Scenario 2's anti-priming guard.
- [ ] **Anchor-grep audit:** `rg "supports PDF files" apps/web-platform/server/{soleur-go-runner,agent-runner}.ts` returns at least three hits (the new constant + the two existing directive call sites). No accidental deletion of either existing directive.
- [ ] `buildSoleurGoSystemPrompt()` (no args) embeds the directive verbatim — pinned by `read-tool-pdf-capability.test.ts`.
- [ ] `buildSoleurGoSystemPrompt({ artifactPath, documentKind: "text" })` also embeds the directive (the directive lives in `baseline`, not in the artifact-conditional branch) — pinned.
- [ ] The leader system prompt built by `agent-runner.ts` (no `context`) embeds the directive verbatim — pinned by an addition to `agent-runner-system-prompt.test.ts`.
- [ ] `agent-runner.ts` imports the constant from `@/server/soleur-go-runner` (single source of truth — no duplicate string literal).
- [ ] `bun test apps/web-platform/test/read-tool-pdf-capability.test.ts apps/web-platform/test/agent-runner-system-prompt.test.ts apps/web-platform/test/soleur-go-runner-narration.test.ts apps/web-platform/test/soleur-go-runner.test.ts apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` all pass locally. Sibling builders that consume `buildSoleurGoSystemPrompt` are included as a drift-guard.
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

### R2 — Negation-priming risk (closed by the deepen-pass rewrite)

**Original concern.** A negative list ("Do not claim PDF support is missing … not installed") can prime the model to emit the very phrase it forbids — and the 2026 prompt-engineering corpus (Lakera, k2view, Gadlet citing InstructGPT/NeQA benchmarks) shows negation-handling does NOT improve with model scale.

**Mitigation (applied in deepen pass).** The directive is now **purely positive** ("Your built-in Read tool natively supports PDF files. To read a PDF the user has shared, attached, or referenced, call the Read tool with the file path — it handles PDFs end-to-end."). The wording mirrors `soleur-go-runner.ts:506` and `agent-runner.ts:613` — both already shipped successfully with positive-only framing. Scenario 2 includes an anti-priming guard (`expect(...).not.toMatch(/\b(do not|never|not installed)\b/i)`) so a future edit re-introducing negation fails the test.

**Residual.** None. The directive is now strictly an additive capability declaration; any priming is *toward* the desired behavior (calling Read on PDFs), not *toward* the misreport phrase.

### R3 — Directive drift between `soleur-go-runner.ts` and `agent-runner.ts`

If the directive is duplicated as a string literal in both files (rather than imported from one), a future edit in one place will silently leave the other stale.

**Mitigation.** Single source of truth — `agent-runner.ts` imports the constant from `@/server/soleur-go-runner`. The Files to Edit list calls this out explicitly. The test for `agent-runner.ts` imports the same constant and uses `.toContain()` — so any drift fails the test.

### R4 — Refactoring `agent-runner.ts` to extract a build-only seam (RETIRED in deepen pass)

**Original concern.** If Scenario 4 required a build-only test seam, an extraction of `buildLeaderSystemPrompt` would touch ~80 lines of `agent-runner.ts` system-prompt construction.

**Status: retired.** The deepen-pass audit of `apps/web-platform/test/agent-runner-system-prompt.test.ts` (lines 135-238) confirms the file already runs `runAgentSession` end-to-end with mocks and captures `mockQuery.mock.calls[0][0].systemPrompt`. Scenario 4 reuses this harness exactly — no extraction required. Net change to `agent-runner.ts` is one import line + one string concatenation (`systemPrompt += "\n\n" + READ_TOOL_PDF_CAPABILITY_DIRECTIVE`).

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
- **`agent-runner.ts` test-seam extraction (R4 retired).** The deepen pass confirmed the existing `agent-runner-system-prompt.test.ts` harness captures `systemPrompt` end-to-end via `runAgentSession`. No extraction needed. If a future edit feels tempted to extract a `buildLeaderSystemPrompt` helper "for cleanliness," DO NOT — pinning the assertion to the SDK call site is closer to what users hit in production.
- **Negative-instruction temptation.** When future capability directives are added (e.g., "Image Reader doesn't seem installed"-class), do NOT default to a negative list. Match the existing positive-only pattern. Scenario 2's anti-priming guard (`/\b(do not|never|not installed)\b/i` reject) is a one-rule reminder; it pins THIS directive only — do not blanket-extend it across the codebase, but DO use it as the template when adding the next sibling.
- **Sibling-baseline gap audit (deferred).** The deepen pass surfaced that the cc-soleur-go cutover left the baseline thinner than the legacy `agent-runner.ts` baseline assumed. PR #3213 closed the gated-PDF context drop; this plan closes the baseline-PDF capability gap. **If a third "tool X doesn't seem installed" report surfaces post-merge** (e.g., for Edit, Write, Glob, or Grep), file a follow-up issue to do a complete sweep of capability statements that the legacy leader prompt asserted vs. the new Concierge baseline. Do NOT speculatively add capability declarations for tools that are NOT being misreported — that is exactly the AGENTS.md-bloat anti-pattern this codebase has rules against.

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
  - `knowledge-base/project/learnings/2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md` — sibling gap (gated-PDF context drop) closed by PR #3213. Same builder family, same root cause class (cc-soleur-go cutover thinner than legacy baseline).
  - `knowledge-base/project/learnings/2026-02-13-agent-prompt-sharp-edges-only.md` — embed only sharp edges Claude would otherwise get wrong. PDF-capability fact qualifies (model otherwise hallucinates a missing tool).
  - AGENTS.md `cq-write-failing-tests-before` — RED test first for Test Scenarios 1-5.
  - AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — threshold and CPO sign-off enforced.
- **Deepen-pass external sources** (web research, 2026):
  - [Lakera — Prompt Engineering Guide 2026](https://www.lakera.ai/blog/prompt-engineering-guide) — on positive vs. negative instructions and avoiding aggressive formatting.
  - [Gadlet — Why Positive Prompts Outperform Negative Ones with LLMs](https://gadlet.com/posts/negative-prompting/) — three benchmarks (InstructGPT, NeQA, multi-model) showing negation underperforms at scale.
  - [k2view — Prompt engineering techniques: Top 6 for 2026](https://www.k2view.com/blog/prompt-engineering-techniques/) — convergent recommendation: "stick with straightforward, positive instructions."
