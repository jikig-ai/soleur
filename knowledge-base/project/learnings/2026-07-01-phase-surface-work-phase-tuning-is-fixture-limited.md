---
title: A phase-surface "regression" can be inherent fan-out ambiguity, not surface noise — and an eval can't tune what its fixture can't resolve
date: 2026-07-01
tags: [eval-harness, phase-surface-hint, fixture-size, tool-selection, work-phase, statistical-power, three-coupling, 5772]
category: best-practices
issue: 5772
prs: [5794]
---

# A phase-surface "regression" can be inherent ambiguity; an eval can't tune what its fixture can't resolve

Closing out #5772 lever 1, the documented follow-up was: "the `work→review` phase hint
regresses — the work-phase surface foregrounds `qa`, which competes with `review`. Worth
tuning `.claude/phase-surface-map.json`'s work entry, with an eval re-run to confirm."
Investigating before editing showed the tuning is **not safely actionable**, for two
reusable reasons.

## 1. The "obvious" fix is contradicted by the eval's own golden data

The intuitive edit — drop `soleur:qa` from the `work` phase's `relevant_skills` — is wrong.
`qa` is a *legitimate* work-phase outcome, present in the golden set:

- `tool-selection.jsonl:6` — phase `work`, golden `review` ("implementation complete… multi-agent pass to catch bugs")
- `tool-selection.jsonl:7` — phase `work`, golden `qa` ("UI change under app/(dashboard)… auth-seeded headless browser gate before review")
- `tool-selection.jsonl:8` — phase `work`, golden `test-fix-loop` ("six failing specs… iterate until green")

The work phase legitimately fans out to **three** different next-skills. Removing `qa`
helps line 6 but regresses line 7 — a wash at best. The "competition" the handoff described
is **inherent situational ambiguity** that the *situation text* disambiguates, not surface
noise the map can cleanly delete. **Lesson: before deleting an entry from a routing/surface
map to fix a "regression," grep the eval's golden tasks for that entry as a legitimate label.
If it appears, the regression is fan-out ambiguity, not noise.**

## 2. The fixture is too thin to validate a *subtle* tuning — fixture-limited, not just budget-limited

Even a non-deleting tweak (reorder, strengthen the `→ usually review` heuristic, annotate
`qa` as UI-conditional) can't be validated: the fixture has exactly **one** work→review case
and **one** work→qa case. `promptfoo eval --repeat 5` across the model grid would produce
single-case noise, not a statistically actionable delta. The eval-harness is also opt-in /
not CI-wired (API-budget gate, `hr-autonomous-loop-skill-api-budget-disclosure`) — so
spending budget to run it now buys a number you can't act on. **Lesson: an eval can only
resolve a tuning whose effect exceeds its per-cell fixture noise. The prerequisite for tuning
work→review is EXPANDING the work-phase golden tasks (several review-cases + qa-cases) first,
not running the eval at current fixture size.**

## 3. The surface is a THREE-coupling, not two

Any phase-surface tuning must edit three files in lockstep — the parity tests enforce two,
the third is silent:

- `.claude/phase-surface-map.json` (canonical, CLI hook reads it)
- `apps/web-platform/server/phase-surface-map.ts` (bundled web copy; `phase-surface-map-parity.test.ts` deep-equals it to the JSON)
- `plugins/soleur/skills/eval-harness/prompts/tool-selection-skill.txt:10` (hardcodes its own work-phase list — **no parity test couples it to the map**, so it drifts silently)

**Lesson: when a value is bundle-duplicated for a runtime that can't read the canonical
source, check whether the *eval prompt* also hardcodes it. The eval is a third copy with no
gate — tune the map and forget the prompt and the eval measures a stale surface.**

## AC11 (the lever-1 value-realization check) was satisfiable without a new run

Related close-out: AC11 asked to confirm the `[phase-scope]` `additionalContext` reaches the
model and that Skill fires at >1 phase transition. Both were already answered — the #5768
Phase 0 live transcript probe (ADR-070:39) plus the #5792 behavioral eval (+6.7pts) prove
delivery, and `soleur-go-runner.ts`'s `currentWorkflow`-locks-on-first-Skill-call structure
proves per-phase firing. The success path emits no telemetry by design (`phase-surface-hook.ts:76`;
only the error path reports via `reportSilentFallback`), so Sentry can't confirm a *specific*
live run — that's an intentional hot-path/fail-open choice, not a gap. **Lesson: an
"observational" QA item may already be answered by a prior probe + a behavioral eval; check
those before treating it as needing a fresh live run.**

See also `[[2026-06-30-eval-fixture-bug-inverts-gate-verdict-and-web-vs-cli-skill-shape]]`
and `[[2026-06-30-posttooluse-skill-additionalcontext-is-the-autonomous-safe-phase-injection-vehicle]]`.
