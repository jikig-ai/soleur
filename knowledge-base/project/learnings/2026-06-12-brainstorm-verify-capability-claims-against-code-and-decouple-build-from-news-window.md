# Learning: Verify "we already do all of this" capability claims against shipped code, and decouple capability-builds from decaying news windows

## Problem

Brainstorm #5088 proposed adopting Addy Osmani's "loop engineering" framework and publishing a blog
asserting "Soleur **is** this architecture, applied beyond code." The issue body framed all of
Osmani's 5 building blocks + external memory as already-true cross-domain. Taken at face value, the
blog would have claimed full autonomous loop engineering across marketing/legal/finance/ops — a claim
a prospect could test and find false (single-user brand incident under the always-on user-brand-critical
gate).

A second tension surfaced mid-brainstorm: the operator wanted to "fix the missing elements first so we
can claim full support," but the blog's entire value is a news hook with a ~2-3 week decay window.
Build-first would have overrun the window the content depends on.

## Solution

**Pattern 1 — Spawn an engineering/CTO verifier to grep each capability claim against shipped code
BEFORE it is published.** The CTO agent checked each Osmani element against the repo:
- TRUE cross-domain: Worktrees (`skills/git-worktree`), Skills (86, 8 domains), External memory
  (`knowledge-base/` across 9 domains), MCP connectors (but 4 git-committed in `plugin.json` vs.
  runtime-available — distinguish "shipped" from "available").
- FALSE / engineering-only: Automations (9 `scheduled-*.yml` run deterministic scripts; **zero invoke
  `claude-code-action`** — no business-domain agent crons) and maker/checker verifiers (~15 agents,
  all in `engineering/review/`; only marketing + legal have business-domain checkers).

So 2 of 6 elements were over-claims. The blog was rewritten to an **honest-hedge** posture: substrate
(memory/skills/connectors) spans every department; autonomous loop + verification are "proven in
engineering, generalizing outward."

**Pattern 2 — Decouple the capability-build from the timely content.** Rather than block the news-hook
blog on closing the 2 gaps, the build was split into follow-up issue #5212 (wire business-domain
scheduled agent crons via the existing `schedule` skill; add verifier agents to ops/product/support).
The honest-hedge blog ships now; closing #5212 later unlocks an honest "fully cross-domain" v2 post.

## Key Insight

When a positioning/marketing brainstorm imports an external framework's vocabulary and asserts "we
already do all of this," the issue body's capability claims are aspirational framing, not verified
fact. Treat them like any other premise: spawn a code-grounded verifier (CTO/repo-research) to confirm
each claim element-by-element against shipped code before it reaches a public surface. And when the
content rides a decaying news window, decouple the (slower) capability-build into a tracked follow-up
so timeliness isn't held hostage to completeness — ship the honest version now, claim the full version
when it's true.

## Session Errors

- **Blog-frontmatter glob miss (one-off)** — first read targeted `knowledge-base/marketing/distribution-content/`
  numbered files expecting Eleventy blog frontmatter; the dated blog posts with frontmatter live in
  `plugins/soleur/docs/blog/2026-*.md`. Recovery: re-ran with the correct glob. Prevention: for blog
  frontmatter conventions, glob `plugins/soleur/docs/blog/2026-*.md` (dated posts), not the marketing
  distribution-content dir. No recurrence vector beyond this path assumption — not worth a rule.

## Tags
category: workflow-patterns
module: brainstorm
issue: 5088
related: 5212
