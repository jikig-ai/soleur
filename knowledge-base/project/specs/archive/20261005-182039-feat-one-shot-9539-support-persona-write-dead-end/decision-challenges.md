# Decision Challenges — feat-one-shot-9539-support-persona-write-dead-end

Findings from the 5-seat plan-review panel (2026-10-05) that route to the operator because they argue for scope beyond the issue's stated fix. The pipeline proceeded without them; `ship` Phase 6 renders this file and files the `action-required` issue.

## UC-1 — Persistent escape row in the support panel chrome (covers the incident's verbatim shape)

**Finding (ux-design-lead F2):** The shipped affordance is deny-triggered — it fires only when a denied tool call records an escalation. The motivating #9539 incident ran `git branch <name>` (auto-approved by `safe-bash.ts` as "read-only") and then declined writes in prose — no deny, no flag, no link. Replayed verbatim under this plan, the dead-end repeats, mitigated only by directive copy (AC8). A persistent low-key escape row in the support panel chrome (e.g. a composer-adjacent "App help only · Ask an agent →" line) would cover 100% of dead-end turns deterministically, including prose declines.

**Why this is a User-Challenge, not Mechanical:** it adds a `components/**/*.tsx` surface — a scope expansion beyond the issue's acceptance notes ("hand off OR clearly explain"), which triggers the BLOCKING `wg-ui-feature-requires-pen-wireframe` gate (a `.pen` wireframe becomes mandatory) and changes the PR's size/review class.

**Options:**

- **(a) Accept residual (shipped state):** deny-triggered affordance + directive copy. The verbatim incident replays without a link but with stronger prose guidance. Zero added surface.
- **(b) Persistent escape row:** ~10 LoC `.tsx` copy-level row, covers every turn including prose declines. Requires a `.pen` wireframe first.
- **(c) Record escalation on write-shaped safe-allowlisted Bash** (`git branch` create/delete/rename under support): in-mechanism but folds into the already-recommended safe-bash follow-up issue — tightening that allowlist deserves its own review.

**Pipeline disposition:** proceeded with (a); AC8 carries the prose-decline coverage and the plan's `## Dependencies & Risks` names the residual explicitly.
