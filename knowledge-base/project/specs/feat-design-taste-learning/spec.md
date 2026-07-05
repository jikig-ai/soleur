---
feature: design-taste-learning
lane: cross-domain
brand_survival_threshold: single-user incident
epic: 5983
closes: 5990
rides: 5989
status: spec
date: 2026-07-05
brainstorm: knowledge-base/project/brainstorms/2026-07-05-design-taste-learning-brainstorm.md
---

# Spec: Design taste-learning — multi-variant + committed taste-profile

## Problem Statement

Soleur's design surfaces (`frontend-design` skill, `ux-design-lead` agent) generate a
single design take with no memory of the operator's preferences across sessions. gstack's
`design-shotgun` fans out multiple variants and learns taste, but stores state per-machine
(`~/.gstack`) using multiple models — both incompatible with Soleur's committed-knowledge,
all-Claude (ADR-053) frame. This is Wave 3 · FR7 of epic #5983; it rides the FR6 declarative
context-injection mechanism (#5989, landed PR #6035, ADR-086) so the learned profile is loaded
without any bespoke loader.

## Goals

- Fan out N design variants in parallel, each seeded a distinct aesthetic direction.
- Persist a committed `taste-profile` in `knowledge-base/` that learns from operator selections,
  with decaying confidence and contradiction-flagging.
- Load the taste-profile into future design sessions via FR6 (skill) / direct-Read (agent).

## Non-Goals

- No home-dir / per-machine state (`~/.gstack`-style). Repo-committed only.
- No multi-model fan-out (all-Claude per ADR-053).
- No scheduled decay cron — decay is recomputed at write time.
- No new product UI surface (this is tooling that generates UI; Phase 3.55 wireframes N/A).
- No external egress of the taste-profile (CLO gate — keep it PII-free).

## Functional Requirements

- **FR1 — Multi-variant fan-out.** On a design request, generate N variants (default 3,
  parameterizable) via N parallel `Agent`-tool sub-agents, each seeded a distinct aesthetic
  direction from `frontend-design`'s existing aesthetic list. Present the slate for operator
  selection. Applies to both the `frontend-design` skill (coded UI) and the `ux-design-lead`
  agent (`.pen` wireframes).
- **FR2 — Committed taste-profile.** Create/maintain `knowledge-base/product/design/taste-profile.md`.
  Each entry is keyed by a design **axis** (e.g. density, ornamentation, palette-temperature) and
  carries: `value`, `confidence` (0–1), `last_reinforced` (date), and `evidence` (the selections
  that reinforced it). PII-free — record the aesthetic choice, not the content being designed.
- **FR3 — Learning on selection.** When the operator selects a variant, record it as evidence on
  the relevant axes and bump the matching entry's confidence.
- **FR4 — Decaying confidence (write-time).** At the start of each design session, recompute and
  rewrite decayed confidence from `last_reinforced` (FR6 injects a static pointer, so decay cannot
  be computed at load time). Decay must be deterministic.
- **FR5 — Contradiction-flagging + auto-supersede.** When a new selection contradicts an existing
  entry on the same axis, **detect and log the contradiction event (the flag fires)**, then resolve
  by superseding the old entry with the newer selection.
- **FR6-load — Load via FR6 / direct-Read.** Add `knowledge-base/product/design/taste-profile.md`
  to the `frontend-design` skill's `context_queries:` frontmatter (loaded via the #5989 hook). Add
  an explicit "Read the taste-profile before designing" directive to the `ux-design-lead` agent body
  (the Skill-matcher hook does not reach agents).

## Technical Requirements

- **TR1 — Ride FR6, no bespoke loader.** The load path for the skill is `context_queries` only; do
  not add any new context-loading mechanism. Reuse ADR-086's contract (committed, `git ls-files`-
  tracked, under `knowledge-base/`).
- **TR2 — Deterministic decay in any script.** If a workflow/script computes decay, it must not use
  `Date.now()`/`new Date()` (unavailable in workflow scripts) — pass the date in.
- **TR3 — Shared-consistency write.** Both surfaces must write the taste-profile with identical
  schema + decay + contradiction semantics (OQ1: shared jq+bash helper vs. documented schema —
  resolve at plan time).
- **TR4 — Rebase base.** Rebase the branch onto current `origin/main` (with PR #6035) before
  implementation so the FR6 hook + `context_queries` idiom are present.
- **TR5 — Fail-safe writes.** A malformed/failed taste-profile write must not corrupt the artifact
  or block the design flow (write atomically; validate before commit).

## Acceptance Criteria (from #5990)

1. Multi-variant design variants are generated.
2. `taste-profile` is persisted to `knowledge-base/` AND loaded via FR6 (skill) / direct-Read (agent).
3. The contradiction flag fires on a conflicting selection.

## Dependency Graph

```
#5989 (FR6, landed) ──▶ #5990 (FR7, this spec)
```

## Open Questions (carried from brainstorm)

- OQ1 shared write helper vs documented schema
- OQ2 exact decay curve + half-life
- OQ3 contradiction axis vocabulary (fixed enum vs free-form)
- OQ4 record rejected variants as negative evidence? → **deferred v2**
- OQ5 rebase base onto origin/main (also TR4) → **done**

## v1 Reshape (post-plan-review, 2026-07-05) — authoritative

A 7-agent plan-review panel + fable advisor reshaped v1 (operator User-Challenge decision:
*context-keyed, recency*). These supersede the FRs above where they conflict. Full rationale:
`knowledge-base/project/plans/2026-07-05-feat-design-taste-learning-plan.md`.

- **FR2/FR4 revised:** entries are keyed by `(context, axis) → value` and ordered by **recency**
  (`last_reinforced`, tie-break `reinforce_count`) — the numeric 90-day "decaying confidence"
  is **removed** (it mis-labeled linear-to-zero decay and, context-blind, caused the profile to
  thrash). This is a deliberate, operator-approved deviation from #5990's literal
  "decaying confidence" wording; recency is the honest realization of the intent
  ("fades unless reinforced") without false precision.
- **FR5 revised:** contradiction fires only within the **same** `(context, axis)` — an operator
  preferring `minimalist@dashboard` and `maximalist@landing-page` is context-conditioned taste,
  not a contradiction. The flag still fires (issue AC preserved), scoped correctly.
- **FR6-load revised:** consumers run `taste-profile-update.sh --validate` before biasing and
  fall back to no-bias on failure (ADR-086 content-trust enforced at the **consume** path, not
  just the writer). The shared helper is hoisted to `plugins/soleur/scripts/`.
- **Agent write revised:** `ux-design-lead` (isolated Task subagent, no operator) **reads** the
  profile only; the **wireframe-approval orchestrator gate** (brainstorm 3.55b / plan 2.5 §4b)
  captures the operator's pick and does the write.
- **New TR (content-trust):** ALL model-supplied write tokens are validated — closed allowlists
  for `context` + `axis`, sanitized `^[a-z][a-z0-9-]*$` for `value`, `^\d{4}-\d{2}-\d{2}$` for date.
- **Deferred to v2:** axis decomposition (density/color-temp/type sub-axes), negative-evidence
  learning, web-Concierge FR6 skill-load port.
