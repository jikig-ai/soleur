---
date: 2026-06-02
category: bug-fixes
tags: [stale-claim, premise-validation, pencil, subagent-prompt, ux-wireframes, verify-before-assert]
issue: 4819
pr: 4817
---

# The "pencil-setup can't auto-install / Pencil is GUI-only" false-premise incident

## What happened

While brainstorming the mandatory-UX-wireframes feature, the orchestrator asserted two **false**
limiting claims about repo capabilities, with no verification:

1. "pencil-setup only registers the MCP server; it can't auto-install Pencil."
2. "Pencil is GUI-only" — **baked as a load-bearing premise into a CTO subagent prompt.**

Both are false. `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh:419`
(`attempt_headless_install()`) runs `npm install --prefix ~/.local @pencil.dev/cli` — a headless,
no-sudo, no-display install — and auths via `PENCIL_CLI_KEY` from Doppler `soleur/dev`. The
headless `.pen` authoring path works. The CTO agent self-corrected on finding the headless
adapter, but the corrected conclusion only surfaced because a second pass happened to look; the
false premise had already biased the first spawn and was invisible to the user.

## Why the existing machinery missed it

The repo's extensive premise-validation machinery (brainstorm Phase 1 verify-block, plan Phase
0.6, Phase 1.7 reconciliation) was **artifact-scoped** — it validated *cited* references (issue
bodies, specs, plans, PRs). It had zero coverage for:

- the orchestrator's **own** spontaneous capability claims ("X can't do Y"), and
- premises **injected into subagent prompts** (which bias the agent AND are invisible to the user).

This is the same defect class as `2026-04-22-...paraphrase-without-verification...` and
`2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification.md`, generalized from artifacts
to the orchestrator's own assertions. See [[2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification]]
and the ux-design-lead fabrication precedent [[2026-04-19-ux-design-lead-headless-stub-fabrication]].

## The fix (PR #4817 / #4819)

- **One merged hard rule** `hr-verify-repo-capability-claim-before-assert` (AGENTS.core.md):
  before asserting — in your own output OR a subagent prompt — a limiting/negative claim about a
  repo tool/skill/script/flag, grep/read the source first or phrase it as a question.
- **Semantic trigger, not a word-list.** Plan review (spec-flow) caught that a hedge-word matcher
  would NOT have caught the motivating bug — "Pencil is GUI-only" contains no hedge word. The
  trigger is any limiting capability claim about a repo artifact; hedge words (only/can't/doesn't)
  are non-exhaustive examples.
- Premise-validation phases (brainstorm Phase 1 block, plan Phase 0.6) gained a one-line
  cross-reference to the rule covering the orchestrator's own option-bounding claims.

## Takeaways

- A limiting premise in a subagent prompt is doubly dangerous: it biases the agent's search AND is
  invisible to the user, who never sees the spawn prompt.
- When merging two rules to fit a byte budget (FR7+FR8 → one rule), a semantic trigger covering
  both surfaces is both cheaper and more correct than two word-list-triggered rules.
- The cheapest verification of "tool X can't do Y" is one grep of X's source — the same discipline
  the repo already applied to cited artifacts, now extended to the orchestrator's own claims.
