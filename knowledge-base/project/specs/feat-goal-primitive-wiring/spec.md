---
title: /goal Primitive as Operator Escape Hatch
status: draft
date: 2026-05-15
lane: cross-domain
brand_survival_threshold: single-user incident
related_brainstorm: knowledge-base/project/brainstorms/2026-05-15-goal-primitive-operator-escape-hatch-brainstorm.md
---

# Spec: /goal Primitive as Operator Escape Hatch

## Problem Statement

Claude Code's `/goal` primitive (v2.1.139+) sets a session-scoped completion condition: a fast-model evaluator reads the transcript after each turn and decides yes/no on whether the work is done. Soleur agents and operators currently have no guidance on when to reach for `/goal` vs. Soleur's existing autonomous-loop infrastructure (the ralph-loop Stop hook + `<promise>DONE</promise>` marker + per-skill exit-code / CLI-output gates).

Without guidance:

1. Agents propose `/goal` retrofits into skills that already have stricter completion mechanisms (this brainstorm started exactly that way).
2. Operators reach for `/goal` for ad-hoc autonomous work but write conditions the transcript-only evaluator cannot verify, recreating the pseudo-handoff failure class Soleur paid for 4 documented times.
3. Runaway-spend risk goes unmitigated — operators don't see Soleur-vetted condition recipes with built-in turn caps.

## Goals

- Disambiguate `/goal` from existing Soleur autonomous-loop infrastructure for both agents and operators.
- Provide 4–6 vetted condition recipes covering common ad-hoc autonomous-work patterns, each with a hardcoded turn cap.
- Surface the transcript-only evaluator gotchas (and Soleur's documented pseudo-handoff incidents) prominently, so operators understand the failure mode before they type a condition.
- Declare a minimum Claude Code version floor (v2.1.139+) where Soleur's `/goal` guidance applies.

## Non-Goals

- **Retrofitting `/goal` into any existing Soleur autonomous skill** (`one-shot`, `test-fix-loop`, `drain-labeled-backlog`, `resolve-todo-parallel`, `resolve-pr-parallel`, `work`). Each already has a better-than-`/goal` completion mechanism.
- **A `soleur:goal` wrapper skill.** CC supplies `/goal` directly; wrapping it for cosmetic preamble adds maintenance burden.
- **Per-operator first-use ack persistence.** Recipe library + docs page provides the necessary pre-flight transparency.
- **Modifications to Soleur's existing Stop hook (`plugins/soleur/hooks/stop-hook.sh`).** Porting `/goal`'s natural-language-condition idea into stop-hook.sh is a separate future brainstorm.

## Functional Requirements

**FR1.** A docs page MUST exist at `plugins/soleur/docs/pages/goal-primitive.md` containing:

- **FR1.1** When to use `/goal` vs. Soleur skills (decision matrix or equivalent).
- **FR1.2** A "transcript-only evaluator gotchas" section that names Soleur's documented pseudo-handoff incidents (referenced learnings) and explains why structured markers / exit codes / CLI-output checks are preferred when available.
- **FR1.3** 4–6 vetted condition recipes. Each recipe MUST (a) name a structured marker the evaluator can verify (exit code, `gh` empty result, file count, regex on command output) rather than fuzzy natural-language outcome; (b) end with `or stop after N turns` where N ≤ 40.
- **FR1.4** A "this consumes your Anthropic API budget" disclosure paragraph aligned with CLO recommendation.
- **FR1.5** Cross-reference to Soleur's existing ralph-loop Stop hook + `<promise>DONE</promise>` marker so operators know `/goal` is the secondary, manual layer atop Soleur-native infrastructure.

**FR2.** `plugins/soleur/AGENTS.md` MUST gain a short paragraph (≤120 words) under an appropriate section (e.g., under workflow gates or a new "Primitive choice" subsection) instructing agents to NOT propose `/goal` retrofits for skills with existing stricter completion mechanisms, and pointing both agents and operators at the new docs page.

**FR3.** Claude Code minimum version (v2.1.139+) MUST be declared in at least:

- **FR3.1** `plugins/soleur/.claude-plugin/plugin.json` description field (the canonical floor declaration site, per repo-research finding that no engines field exists today).
- **FR3.2** The new `goal-primitive.md` docs page itself (so operators reading the page know the floor).
- **FR3.3** Optionally `README.md` install instructions if a relevant section exists; otherwise the docs page is sufficient.

**FR4.** A 30-minute spike MUST verify whether `/goal` can be set from inside a Soleur skill invoked via the Skill tool (vs. only from the operator's top-level slash command). The result MUST be reflected in the docs page — either with a working "from inside a Soleur skill" example, or with an explicit "use only from your shell, not inside a skill" caveat.

## Technical Requirements

**TR1.** No new code, hook, script, or skill. The deliverable is a markdown docs page + an AGENTS.md edit + a plugin.json description edit. If the spike (FR4) reveals a need for any wrapper, this becomes a Non-Goal violation and the spec MUST be revisited rather than silently expanded.

**TR2.** All recipes in FR1.3 MUST be exercisable in headless mode (`claude -p "/goal …"`) as well as interactive. Test each recipe against the headless invocation form before merging; failures imply the condition is not transcript-verifiable in the expected way.

**TR3.** The docs page MUST follow Eleventy front-matter conventions used by other pages under `plugins/soleur/docs/pages/` so it renders in the existing docs site.

**TR4.** AGENTS.md edit MUST follow the existing rule-id pattern (`hr-…`, `wg-…`, `cq-…`, `cm-…`) if it adds a hard rule, or be placed under an existing section heading without an ID if it is a soft pointer. Decide at plan time which is more appropriate; default to soft pointer to avoid AGENTS.md rule-corpus bloat.

## User-Brand Impact

- **Artifact at risk:** the operator's own Anthropic API budget and trust in Soleur after a `/goal`-induced runaway-spend incident.
- **Vector:** poorly-bounded condition the evaluator never rules "yes" on (e.g., naming a fuzzy outcome the transcript can't verify, omitting a turn cap, or naming a marker that doesn't actually land in the transcript). Loop continues turn after turn.
- **Threshold:** single-user incident. One operator's multi-hundred-dollar runaway spike following a Soleur-suggested condition pattern is enough to break the trust contract.
- **Defenses encoded in this spec:**
  1. Every shipped recipe (FR1.3) carries a hardcoded `or stop after N turns` clause with N ≤ 40.
  2. The transcript-only evaluator gotchas section (FR1.2) appears in the docs page BEFORE the recipe library — the operator reads the failure-mode warning before reaching the copy-paste recipes.
  3. The "consumes your API budget" disclosure (FR1.4) provides explicit operator-facing acknowledgement.
  4. The AGENTS.md edit (FR2) prevents agents from proposing `/goal` retrofits into skills that already have stricter completion mechanisms — preventing a future agent-written PR from reintroducing the failure surface.

## Acceptance Criteria

- The docs page renders at the expected URL on the Soleur docs site.
- The page contains all five FR1.x subsections.
- The 4–6 recipes each: (a) name a structured marker, (b) include the turn cap, (c) work in headless mode against a real example invocation.
- `plugins/soleur/.claude-plugin/plugin.json` description string includes the CC min-version note (FR3.1).
- `plugins/soleur/AGENTS.md` contains the routing paragraph (FR2).
- The Skill-tool spike result (FR4) is reflected in the docs page.
- No new skill / hook / script / wrapper code lands.
