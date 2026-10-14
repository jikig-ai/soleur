---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: "#8604"
status: brainstorm-complete
created: 2026-09-23
---

# Feature: Grok research stubs drop the Claude model alias

## Problem Statement

`plugins/soleur/scripts/sync-grok-agent-compat.ts` copies each Claude agent's `model` into `.grok/agents/<id>.md`. For the five engineering research agents that value is `haiku`. On Grok Build 1.0.41 that alias is not a catalog model: the session warns and keeps the session default (`grok-4.7`). The word `cheap` warns the same way. ADR-110 decision 4 still forbids changing the Claude sources off `haiku` until a harness accepts semantic tiers in agent spawn.

## Goals

- The five Grok research stubs no longer contain a `model` line.
- Regenerating the stubs is idempotent: `--check` passes after the generator change.
- Claude research agents remain `model: haiku`.
- Stubs that already say `model: inherit` are unchanged.
- ADR-110 records the 2026-09-23 measurement and this choice.

## Non-Goals

- Changing Claude agent frontmatter to `cheap` or `inherit`.
- Writing `model: grok-4.5` (or any other catalog slug) into Grok stubs.
- Changing how the headless CLI sends `SetSessionModel` after loading an agent profile.
- Making `spawn_subagent` select a project agent type. That argument is absent from the current tool schema.

## Functional Requirements

### FR1: Research stubs inherit

The five files `.grok/agents/soleur-engineering-research-{best-practices-researcher,framework-docs-researcher,git-history-analyzer,learnings-researcher,repo-research-analyst}.md` have frontmatter `name` and `description` and no `model` key.

### FR2: Generator matches the stubs

`compatStubMarkdown` omits `model` when the source frontmatter is a Claude alias (`haiku`, `sonnet`, `opus`, `fable`). `inherit` is still written as `model: inherit`. `bun run plugins/soleur/scripts/sync-grok-agent-compat.ts --check` exits 0.

### FR3: Claude sources unchanged

`plugins/soleur/agents/engineering/research/*.md` still contain `model: haiku`.

### FR4: ADR-110 addendum

An addendum dated 2026-09-23 states that Grok 1.0.41 ignores `haiku` and `cheap` with a catalog warning, recognizes `grok-4.5` then can have it overwritten by the headless client's `SetSessionModel`, and that the chosen fix is to omit `model` on the Grok research stubs. It also states that `subagent_model_inheritance` was unset (documented default off) and that the session's spawn tool exposed neither a `model` argument nor an agent-type argument. Decision 4 is unchanged.

## Technical Requirements

### TR1: Drift test

An existing compat-stub drift test (or the `--check` path it wraps) fails if a research stub regains `model: haiku` or if a new Claude alias is copied verbatim into a Grok stub.

### TR2: No new runtime dependency

The generator stays a local file transform. It does not call the Grok CLI and does not read `TIER_MAPS` to emit a slug.
