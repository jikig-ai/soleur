---
module: web-platform
date: 2026-05-06
problem_type: best_practice
component: review_workflow
symptoms:
  - "Multi-agent review flagged P1 'literal-hex propagation' on a className swap"
  - "Initial cross-cutting-refactor scope-out filing got DISSENTed by code-simplicity-reviewer"
  - "Plan author had Non-Goal'd tokenization with a piecemeal-migration rationale that the review-time exacerbation check overrode"
root_cause: scope_out_exacerbation_misapplication
severity: medium
tags: [scope-out, exacerbation-rule, theme-tokens, tokenization, review-workflow, fix-inline]
related:
  - 2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md
  - 2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot.md
  - 2026-05-06-token-on-accent-vs-text-primary-on-status-backgrounds.md
pr: "#3330"
issue_followup: "#3334"
---

# Tokenize-on-touch when theme tokens already exist for the literal pattern

## Problem

PR #3330 was a 4-line className swap on `apps/web-platform/components/kb/kb-chat-trigger.tsx`. The user pointed at the dashboard "New conversation" empty-state CTA (`apps/web-platform/app/(dashboard)/dashboard/page.tsx:526`) as the source-of-truth and asked to "match this kind of filled button." The dashboard CTA uses literal-hex Tailwind classes (`bg-gradient-to-r from-[#D4B36A] to-[#B8923E]`).

The plan deliberately Non-Goal'd tokenization with rationale: "piecemeal migration risks third tokenized variant diverging from the literal-hex pair." The author's logic was: only consolidate ALL three sites at once, otherwise we get three competing patterns (literal-hex × 2, tokenized × 1).

That rationale was author-initiated and survived plan + deepen-plan. It got overridden at review time by:
- pattern-recognition-specialist (P1): codebase has `--soleur-accent-gradient-{start,end}` tokens registered in `apps/web-platform/app/globals.css` `@theme` (lines 58-59, 82-83, 110-111, 136-137) but completely unused. This PR was the 4th site to inline-copy the literal hex when the canonical answer was already defined.
- code-simplicity-reviewer DISSENT on the initial scope-out filing: "this PR is actively adding the 3rd copy. That's the textbook disqualifier for `pre-existing-unrelated`, and the same logic — 'this PR is actively adding the 3rd copy' — undercuts the cross-cutting framing."

## Solution

**Tokenize on touch.** When a PR is about to mirror an existing literal-hex / literal-class pattern AND a registered theme token already corresponds to that exact value, the simplest fix-inline path is to use the token at the new call site:

- Single-file edit (no scope expansion).
- Activates the dormant token for the first time, reducing the number of literal-hex copies (3 → 2) instead of growing them (3 → 4).
- Visual parity with the user's source-of-truth is preserved when the token resolves to the same hex value.
- Future cross-codebase consolidation (the dashboard sites + any other abstractions) becomes a smaller, tractable cleanup PR rather than a rolling cleanup-or-tokenize debate at every callsite.

In this PR the change was:

```diff
- const baseClass =
-   "inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-r from-[#D4B36A] to-[#B8923E] px-3 py-1.5 text-xs font-semibold text-soleur-text-on-accent transition-opacity hover:opacity-90";
+ const baseClass =
+   "inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-3 py-1.5 text-xs font-semibold text-soleur-text-on-accent transition-opacity hover:opacity-90";
```

The genuine cross-cutting consolidation (dashboard `page.tsx:526` + `:623` literal-hex sites, `apps/web-platform/components/ui/gold-button.tsx` 135° diagonal mismatch, token alignment) was filed as a fresh `cross-cutting-refactor` scope-out (#3334) and CONCUR'd by code-simplicity-reviewer.

## Key Insight

Plan-time scope-out rationales like "avoid piecemeal migration" can be defensible BUT they fail the review-time exacerbation check (AGENTS.md scope-out criterion 4) when:

1. The PR introduces a NEW call site of the pattern (`git diff origin/main...HEAD -- <file> | grep '^+' | grep <pattern>` returns ≥1 line), AND
2. A simpler fix-inline path exists that does NOT require touching multiple files (e.g., a registered-but-unused theme token, a one-file abstraction adoption, a single-callsite refactor).

The exacerbation rule is intentionally strict: it removes the judgment loophole "is this really scope-out?" for findings the PR itself introduces. When both conditions above hold, the only correct disposition is fix-inline, even if the plan author preferred deferral.

The "piecemeal migration creates a third variant" argument is conditionally valid — it applies when the would-be tokenization at the new site IS the only tokenization for the foreseeable future. It does NOT apply when:
- The token registration already exists in `globals.css` `@theme`,
- The new site is the FIRST tokenized usage (so there's no "third variant" yet — there's just one tokenized site and the legacy literal-hex sites are already a debt the codebase carries),
- Future consolidation work is filed as a tracked issue (so the cleanup is not actually deferred forever — it's deferred in a way that future PRs will pick up).

In short: prefer the **single-file fix that activates dormant infrastructure** over the **multi-file refactor that consolidates everything in one go**, when both achieve the same downstream goal. The first ships now and lets the second land independently; the second blocks the first on a planning cycle.

## Prevention

When reviewing a PR that mirrors an existing pattern from elsewhere in the codebase:

1. **Run the exacerbation check** — `git diff origin/main...HEAD -- <file> | grep '^+' | grep <pattern>` — BEFORE filing any scope-out under `pre-existing-unrelated` or `cross-cutting-refactor`. If ≥1 hit, the PR is exacerbating, not preserving.
2. **Search for dormant infrastructure** before propagating a literal pattern: grep `globals.css` for `@theme`-registered tokens, grep `components/ui/` for existing abstractions, grep `lib/` for canonical helpers. If a registered-but-unused token / abstraction exists for the exact pattern, the fix-inline cost is one-line; the cost of NOT taking it is one more callsite to migrate later.
3. **Distinguish "match the visual" from "match the implementation"** when interpreting user intent. If the user pointed at a specific button and said "match this kind of filled button," they want the visual. The implementation (literal hex vs token) is at agent discretion as long as the rendered output is identical.

## Session Errors

1. **Plan prescribed `bun test` but the project uses `vitest`.** Plan's Phase 2 Verify steps and tasks.md said `bun test apps/web-platform/test/...`. Running the command produced "filters did not match any test files" because `bun test` discovery against the `apps/web-platform` cwd doesn't match the actual test runner. Recovery: switched to `./node_modules/.bin/vitest run <files>` after reading `apps/web-platform/package.json scripts.test`. **Prevention:** plan/deepen-plan should grep the affected app's `package.json scripts.test` (and existence of `vitest.config.*`, `bun.lockb`, etc.) before prescribing test invocations in plan output. Currently the skills freelance the test runner from a repo-wide convention; tooling drift between plan-time grepping and reality is silent until execution.

2. **Initial scope-out filing failed the exacerbation rule.** I drafted a `cross-cutting-refactor` filing for the trigger's literal-hex propagation. code-simplicity-reviewer DISSENTed: "this PR is actively adding the 3rd copy" — exacerbation, not preservation. Recovery: tokenize inline (single-file fix); re-file the GENUINE cross-cutting consolidation (dashboard sites + GoldButton) as a fresh scope-out, which CONCUR'd. **Prevention:** the review skill's Step 1 (synthesis) should explicitly run the exacerbation `git diff` check whenever a finding is being routed to `pre-existing-unrelated` or `cross-cutting-refactor`. The current rule text describes the check; making it a mechanical step in the review skill catches it before the simplicity reviewer has to.

3. **Dev server failed to start due to pre-existing Sentry instrumentation ESM/CJS error.** `Compiled /instrumentation in 2.5s` then `ReferenceError: require is not defined in ES module scope`. Pre-existing on `main`, unrelated to this PR. **Prevention:** not actionable in this session; tracked separately as a dev-environment bug. AC6 visual verification deferred to operator review on Vercel preview.

## See Also

- `knowledge-base/project/learnings/2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md` — the original exacerbation-rule learning that this case re-ratifies.
- `knowledge-base/project/learnings/2026-05-06-scope-out-criterion-misclassification-adr-not-architectural-pivot.md` — same-day learning on scope-out criterion choice (ADR misclassification as architectural-pivot). Pair this with that one: both are scope-out gotchas the simplicity reviewer caught at filing time.
- `knowledge-base/project/learnings/2026-05-06-token-on-accent-vs-text-primary-on-status-backgrounds.md` — same-day token-semantics learning that the deepen-plan reconciled when verifying `--soleur-text-on-accent` resolves to `#1a1612` cross-theme.
