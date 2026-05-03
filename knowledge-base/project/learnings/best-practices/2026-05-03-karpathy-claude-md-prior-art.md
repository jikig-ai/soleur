---
name: karpathy-claude-md-prior-art
description: Karpathy's 4-rule CLAUDE.md (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution) maps to existing Claude Code system-prompt defaults plus our AGENTS.md/skill enforcement. Recorded as confirmation of posture, not as new rules — adding them verbatim would duplicate upstream guidance and burn the AGENTS.md byte budget without behavior change.
type: best-practice
tags: [agents-md, prior-art, byte-budget, placement-gate, prompt-engineering]
category: best-practices
module: AGENTS.md
---

# Karpathy CLAUDE.md — Prior Art for Our Posture

## Source

- Article: "The 4 Lines Every CLAUDE.md Needs" (Yanli Liu, Level Up Coding,
  Apr 2026) — <https://levelup.gitconnected.com/the-4-lines-every-claude-md-needs-2717a46866f6>
- Origin file: `forrestchang/andrej-karpathy-skills/CLAUDE.md` —
  <https://github.com/forrestchang/andrej-karpathy-skills/blob/main/CLAUDE.md>
- Distilled from Andrej Karpathy's January 2026 observations on LLM coding
  pitfalls.

## The Four Rules

1. **Think Before Coding** — "Don't assume. Don't hide confusion. Surface
   tradeoffs." State assumptions, present multiple interpretations rather
   than picking silently, suggest simpler approaches, stop and ask when
   unclear.
2. **Simplicity First** — "Minimum code that solves the problem. Nothing
   speculative." No unrequested features, single-use abstractions,
   configurability, or error handling for impossible scenarios.
3. **Surgical Changes** — "Touch only what you must. Clean up only your own
   mess." No drive-by improvements to unrelated sections, no refactor of
   working code, no deletion of pre-existing dead code.
4. **Goal-Driven Execution** — "Define success criteria. Loop until
   verified." Convert vague tasks into measurable goals with explicit
   verification steps.

## Why We're Not Adding Them to AGENTS.md

The Claude Code system prompt — which loads every turn before AGENTS.md —
already enforces three of the four:

- **Simplicity First / Surgical Changes** → "Don't add features, refactor,
  or introduce abstractions beyond what the task requires. A bug fix
  doesn't need surrounding cleanup; a one-shot operation doesn't need a
  helper. Don't design for hypothetical future requirements."
- **No speculative error handling** → "Don't add error handling, fallbacks,
  or validation for scenarios that can't happen. Trust internal code and
  framework guarantees. Only validate at system boundaries."
- **Surface tradeoffs / push back** → covered by AGENTS.md
  `cm-challenge-reasoning-instead-of` ("Challenge reasoning instead of
  validating. No flattery. If something looks wrong, say so.").

The remaining angle — **Goal-Driven Execution / verification loops** — is
domain-scoped to our `/work`, `/ship` Phase 7, and TDD gate
(`cq-write-failing-tests-before`), not a cross-cutting AGENTS.md invariant.

## Why Adding Them Verbatim Would Be a Net Negative

- **Byte budget.** `cq-agents-md-why-single-line` caps AGENTS.md at
  ~37 KB; ETH Zurich measured 10–22 % per-turn token overhead from rule
  blocks. Re-stating upstream defaults burns budget for zero behavior
  change.
- **No incident anchor.** `wg-every-session-error-must-produce-either`
  requires every rule to point to a real PR or learning via `**Why:**`.
  Generic aphorisms have no anchor and decay into noise.
- **Placement gate.** `cq-agents-md-tier-gate` routes already-enforced
  guidance to a one-line pointer in the owning skill, not a duplicate rule.

## When This Note Becomes Load-Bearing

- A future contributor proposes adding the 4 rules (or a subset) to
  AGENTS.md. Link this file as the rationale for the no-op decision.
- The Claude Code system prompt drops or weakens its simplicity/surgical
  defaults in a future release. At that point, the relevant rule(s) become
  AGENTS.md-eligible — re-evaluate against `cq-agents-md-tier-gate` then,
  not now.

## Related

- AGENTS.md rules: `cq-agents-md-why-single-line`,
  `cq-agents-md-tier-gate`, `cm-challenge-reasoning-instead-of`,
  `cq-write-failing-tests-before`.
- Compound skill: `Route-Learning-to-Definition` step (placement gate
  authority).
