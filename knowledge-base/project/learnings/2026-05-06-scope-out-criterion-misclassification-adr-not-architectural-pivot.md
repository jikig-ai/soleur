---
date: 2026-05-06
category: workflow
component: review-skill
related_pr: 3271
related_issue: 3232
tags: [scope-out, second-reviewer-concur, ADR, architectural-pivot, contested-design]
---

# Learning: Scope-out criterion misclassification — ADR work fails architectural-pivot; misclassified-but-legitimate deferrals should re-file, not absorb

## Problem

PR #3271 (`feat-theme-toggle`) had four scope-out candidates from a 10-agent multi-agent review. Each was filed for `code-simplicity-reviewer` second-reviewer concur per `plugins/soleur/skills/review/SKILL.md` §5. Two of four DISSENTED:

1. **ADR for custom-vs-`next-themes`** — claimed `architectural-pivot`. Reviewer dissented: "the architecture is *already chosen and shipping in this PR*; writing an ADR for a chosen path is not changing a cross-codebase pattern, it's documentation. The 'cross-cutting infra implications' describe the cost of *reversing* the decision later, not the cost of *recording* it now."
2. **Brand-token parity (brand-guide.md ↔ globals.css)** — claimed `architectural-pivot`. Reviewer dissented on the criterion (parity test/codegen aren't a cross-codebase pattern shift) but explicitly noted the underlying deferral was legitimate under `contested-design` (review agents independently named ≥2 approaches with differentiated trade-offs and recommended a design cycle).

Default rule when `code-simplicity-reviewer` dissents: flip to fix-inline.

## Solution

Two distinct recovery patterns:

**(a) Fix-inline absorption.** When the dissent reveals the work was small enough to absorb in the PR, just do it. The ADR for custom-vs-`next-themes` was ~1 markdown file (60 lines) capturing tradeoffs the strategist had already articulated in the review snapshot. Writing it inline (`knowledge-base/engineering/architecture/decisions/ADR-024-custom-theme-provider-vs-next-themes.md`) cost ~10 minutes; deferring it would have meant the decision context decayed before the issue was picked up.

**(b) Re-file under the correct criterion.** When the dissent is on the *label* rather than the underlying deferral, re-file with a fresh concur cycle. The brand-token parity finding was structurally a `contested-design` (two valid approaches, agent-surfaced, requires stakeholder input) — re-filing under that criterion produced a clean CONCUR.

What does NOT work: absorbing an `architectural-pivot`-misclassified-but-truly-`contested-design` finding inline. The "fix-inline" default assumes the work is small. Brand-token parity isn't — it's either a new monorepo package + build pipeline, or a brittle markdown-table parser test. Either is non-trivial. Re-file, don't absorb.

## Key Insight

The four scope-out criteria from `review/SKILL.md` are NOT mutually exclusive in claim space — but they ARE mutually exclusive in *strict applicability*. A dissent on `architectural-pivot` doesn't mean "no scope-out is valid"; it means "this specific criterion doesn't fit." The first-line `DISSENT:` reason is load-bearing — if it identifies a different criterion that does fit, the right move is re-file, not absorb.

**Filing heuristic:**
- `architectural-pivot` requires the *fix itself* to change a cross-codebase pattern. ADRs documenting an *already-chosen* path don't qualify — they're documentation work. ADRs designing a *future* pattern shift do qualify.
- `contested-design` requires the review agent (not author) to name ≥2 concrete approaches with differentiated trade-offs AND recommend a design cycle outside the PR. "Two ways to do this" alone isn't enough — the trade-off must be on durability/cost/complexity, not just style.

## Session Errors

1. **CSP regression test pinned wrong source token.** The no-FOUC script source uses `dataset.theme` (JS API); my test asserted `data-theme` (DOM attribute name). Test failed on first run. **Recovery:** updated the assertion to match the source token. **Prevention:** when asserting on script-body source strings via `renderToStaticMarkup`, paste the exact source token, not the DOM attribute name it eventually produces.

2. **ARIA keyboard-nav initially converted toggle-button-group → radiogroup semantics.** First implementation changed `role="group"` + `aria-pressed` to `role="radiogroup"` + `role="radio"` + `aria-checked`, which would have broken `theme-toggle.test.tsx` (which uses `getByRole("button")` and `aria-pressed`). **Recovery:** reverted role/aria changes, kept the arrow-key handler. **Prevention:** when a review says "X-style keyboard nav" for an existing component, check whether they want full ARIA-pattern conversion or just keyboard behaviour added — verify against existing tests *before* writing code.

3. **Tried to invoke compound via a non-existent shell script path.** Ran `bash ../../plugins/soleur/skills/compound/scripts/run-compound.sh`. **Recovery:** invoked via `Skill` tool. **Prevention:** AGENTS.md `wg-before-every-commit-run-compound-skill` literally says "skill: soleur:compound" — invoke the skill, don't shell out.

4. **Subagent's tokenization promoted neutral CTAs to gold-accent CTAs.** `bg-white text-black hover:bg-neutral-200` → `bg-soleur-accent-gold-fill text-soleur-text-on-accent hover:opacity-90`. This is a brand-meaning shift (neutral CTA pattern → brand-accent CTA pattern), not a pure tokenization. The agent flagged it explicitly in its report. **Recovery:** accepted as brand-aligned (gold is the brand accent). **Prevention:** when a tokenization sweep delegates to a subagent, the prompt should explicitly call out CTA-class changes as a separate decision the agent must surface, not absorb into "tokenization heuristics."

5. **`placeholder:text-soleur-text-secondary` inconsistent with `placeholder:text-soleur-text-muted` elsewhere.** Caught by pattern-recognition review of the sweep. **Recovery:** changed to `text-muted` (one-line fix). **Prevention:** subagent prompts for tokenization sweeps should include "use `text-muted` for placeholder, not `text-secondary`" as an explicit rule, since the muting convention varies by token semantics.

## Tags

category: workflow / scope-out / review-skill
module: review-skill, scope-out-second-reviewer-concur
