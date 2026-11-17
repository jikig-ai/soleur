---
title: "chore: Fable 5.2 model launch (claude-fable-5-2)"
date: 2026-11-09
slug: fable-5-2-model-launch
branch: feat-fable-5-2-upgrade
issue: 12513
lane: cross-domain
type: chore
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore: Fable 5.2 model launch (claude-fable-5-2)

## Overview

Fable 5.2 (`claude-fable-5-2`, released 2026-11-09) replaces Fable 5.1 in Soleur's model-launch tooling and policy docs. Fable reaches users only through the `model: fable` alias on the two ADR-083 consult gates, so no pin changes; whether the alias resolves to 5.2 on the pinned CLI 2.1.311 is unverified (#12514). What moves is the audit's stale-ID table, its tests, and the recorded pricing basis. Article items (fast mode, preserved thinking, orchestrator role, effort) are evaluated and rejected with reasons. The CLI bump is deferred (#12514). Brainstorm: `knowledge-base/project/brainstorms/2026-11-09-fable-5-2-upgrade-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-fable-5-2-upgrade/spec.md`.

## Research Insights

**Premise validation.** No cited issue is a work target. `#12514` (deferred CLI bump) is open and is only referenced. `audit-models.sh` run in the worktree: item 1 "none — config model IDs are current", item 2b all three tier models present in pinned CLI 2.1.311. Mechanism check against the ADR corpus: ADR-053 (Fable 5.1 re-tier review) says "The upgrade remains free (the `model: fable` alias is version-agnostic)"; ADR-083 bounds Fable to two gates; neither rejects the planned changes. Collision pre-check: no open PR names the plan's files; code-review overlap query returned no hits for any planned file.

**Property List.** (P1) A config file carrying any superseded Fable id is detected and rewritten to `claude-fable-5-2` in one hop. (P2) The recorded pricing basis matches the official pricing page for every row it quotes. (P3) The rejected article items are recorded with reasons so the next launch does not re-derive them.

**Cut List.** CLI bump: buys no property (no fable id is sent as an argv value) and is covered by #12514's flip condition. `MODEL_PRICING` edit: no fable row exists in `agent-on-spawn-requested.ts`, and it is a billing constant. `TIER_MAPS`/`harness-model-map.ts` edit: the `advisor: "fable"` alias is version-agnostic.

**Pricing re-derived 2026-11-09** from `https://platform.claude.com/docs/en/about-claude/pricing` (all rows read, none inherited), $/MTok:

| model | input | 5m write | 1h write | cache read | output |
|---|---|---|---|---|---|
| Fable 5.2 | 8 | 10 | 16 | 0.20 | 40 |
| Fable 5.1 | 10 | 12.50 | 20 | 0.25 | 50 |
| Opus 5.5 | 4 | 5 | 8 | 0.20 | 20 |
| Sonnet 5.5 | 2 | 2.50 | 4 | 0.10 | 10 |
| Haiku 5.5 (up to 100K prompt) | 0.10 | 0.125 | 0.20 | 0.01 | 0.50 |

Fast mode Fable 5.2: 16 input / 80 output. Multiples vs Fable 5.2 (derived from these rows): Opus 5.5 2× on input and output with equal cache read; Sonnet 5.5 4× on input and output, 2× on cache read; Haiku 5.5 80× on the short-prompt card. Cache read is the dominant line item of a Task spawn per ADR-053's 2026-09-03 measurement, so the $0.25 → $0.20 drop is the Fable 5.1 → 5.2 delta that matters; no per-spawn dollar figure is restated here.

**Vendor claims, not measured here:** up to 30% faster than 5.1, about 55% fewer safety-classifier blocks.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Retarget `AUTOFIX_PAIRS` | Only `claude-fable-5=claude-fable-5-1` exists; `claude-fable-5-1` is not yet a source id | Retarget it and add `claude-fable-5-1=claude-fable-5-2` |
| ADR-083 or ADR-110 addendum | ADR-110 has no Fable 5.1 mention; ADR-083 names Fable as the consult tier | Addendum goes in ADR-083 |
| Test file update | Fixture `CURRENT = "claude-fable-5-1"` asserts the current id is untouched; after the change that id is stale and would be rewritten | Change the fixture's current id to `claude-fable-5-2` |

## Implementation Phases

### Phase 1 — Tests first (`cq-write-failing-tests-before`)

In `plugins/soleur/test/model-launch-review.test.ts`, before touching the script:

0. Pair-count floor: the test asserts a minimum pair count (read the exact line before editing); raise it by one (10 → 11) and update its comment. Fix the comment near the prefix test that says `claude-fable-5-1` is not itself a source id.
1. `CURRENT_IDS`: `claude-fable-5-1` → `claude-fable-5-2`; update the comment block above it (5.1 moved out at the 5.2 launch, 2026-11-09).
2. `SUPERSEDED` map (the `every superseded id is still a source pair` test): `"claude-fable-5": "claude-fable-5-2"` and add `"claude-fable-5-1": "claude-fable-5-2"`.
3. Synthetic prefix test: the `.replace()` source string `'  "claude-fable-5=claude-fable-5-1"\n'` (and its replacement) → `claude-fable-5-2`.
4. Sed-anchor fixture: `CURRENT = "claude-fable-5-1"` (before and expected) → `"claude-fable-5-2"`, so the fixture still asserts that the current id does not grow a second suffix. Add `STALE_FABLE = "claude-fable-5-1"` expecting exactly `"claude-fable-5-2"` (never `-5-2-1`).
5. New named test `fable 5 / 5.1 / 5.2 converge in one --fix run`: one file holding `claude-fable-5`, `claude-fable-5-1` and `claude-fable-5-2` ends with exactly `claude-fable-5-2` three times, plus a dated variant `claude-fable-5-1-20261101` that stays untouched (boundary rule).
6. Update the floor-failure message string `claude-fable-5=claude-fable-5-1` in the prefix test.

Run the test file before Phase 2: expect RED on the `SUPERSEDED` pair test (`claude-fable-5-1` has no pair yet), the synthetic-prefix injection test (its `.replace()` source string is absent from the script) and the new convergence test. A silent GREEN means the edits are not reaching the assertions.

### Phase 2 — Retarget the pair table

In `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` (`AUTOFIX_PAIRS`): replace `"claude-fable-5=claude-fable-5-1"` with `"claude-fable-5=claude-fable-5-2"` and add `"claude-fable-5-1=claude-fable-5-2"`. Refresh the prose comments that name `claude-fable-5-1` as the *current* id (around the `ID_BOUNDARY` block and the `--fix` sed comment) to say `claude-fable-5-2` where they mean the current successor; leave history that describes the 5.1 event as written. Fix the `audit-models.sh` comment (the `assert_single_hop does NOT catch either shape` sentence) that says `claude-fable-5-1` is not itself a source id; after this change it is one. No closing paren inside any comment in the array (the test parser reads to the first one). Re-run the test file: GREEN. Run `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` and `--detect`: no findings, exit 0.

### Phase 3 — Skill doc

`plugins/soleur/skills/model-launch-review/SKILL.md`: add `→ Fable 5.2` to the release-history list (line 17 area), and one sentence in step 2 naming the test surfaces a new pair must also touch (`CURRENT_IDS`, the `SUPERSEDED` map, the synthetic-prefix source string and the sed-anchor fixture), so the next launch does not rediscover them. Line 190's `claude-fable-5` → `claude-fable-5-1` account stays as history; append a clause that the 5.2 launch retargeted the same pair to `claude-fable-5-2`. The `description:` frontmatter is untouched, so no description-budget change.

### Phase 4 — ADR-053 addendum (pricing basis)

Append `## Addendum — 2026-11-09 (Fable 5.2 launch)` to `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`, following the Opus 5.5 and Haiku 5.5 addenda: the re-derived pricing table above, the multiples, the cache-read delta ($0.25 → $0.20) without per-spawn dollar figures, and the verdict "no pin moves; list price only; alias resolution on pinned CLI 2.1.311 unverified (#12514)". State that `MODEL_PRICING` is untouched because no Fable id appears under `apps/web-platform/server/`. Label the 30% and 55% figures as vendor claims. Cross-link the ADR-083 addendum.

### Phase 5 — ADR-083 addendum (rejections)

Append `## Addendum — 2026-11-09 (Fable 5.2)` to `ADR-083-scoped-strong-model-consult-at-decision-gates.md` (Ruled by CTO agent, 2026-11-09): Advisor role unchanged (the two gates stay the only Fable sites); orchestrator role not adopted (would expand the gate set beyond the admission rule); fast mode not adopted (2× price, spend increase needing operator authorization); preserved thinking not adopted (no consumer); `AUDIT_EFFORT` unaffected (Sonnet/Haiku tier; Fable 5.2's Medium default in Claude Code noted); Mythos 5.2 not usable (no public API ID, vetted organizations only). Also add a one-line `Superseded 2026-11-09` pointer in ADR-083 next to its Context line that quotes Fable 5 at $10/$50, pointing at the ADR-053 addendum, and cross-link the two addenda.

### Phase 6 — Policy basis

`plugins/soleur/AGENTS.md` Model Selection Policy "Pricing basis" paragraph: refresh to 2026-11-09 — Fable 5.2 is 2× Opus 5.5, 4× Sonnet 5.5, 80× Haiku 5.5 on the short card; Fable 5.2 cache read is $0.20 (Fable 5.1: $0.25), equal to Opus 5.5 and 2× Sonnet 5.5; drop the "same per token as Fable 5" sentence in favor of the 5.1 → 5.2 delta, and point to the ADR-053 addendum for the full table instead of restating rows. The paragraph's closing claim that the ADR-083 consult is a cold spawn with "~0" cache reads contradicts ADR-053's 2026-09-03 measurement (Task spawns are cache-read dominated); replace it with the measured statement and cite ADR-053. Say the figures are list price and alias resolution on CLI 2.1.311 is unverified. Keep it one paragraph.

### Phase 7 — Verify

Run `model-launch-review.test.ts`, `harness-model-map.test.ts` and `fable-consult-gates.test.ts`; rerun `audit-models.sh` (all items); `git grep -n 'claude-fable-5-1'` and `git grep -n 'Fable 5\.1'` (outside archives) must each be dispositioned: pair table and intentional test stale-id rows (keep), `SKILL.md` and ADR-053/083 historical sections and post-mortems (history, keep), `plugins/soleur/AGENTS.md` (Phase 6 target). Any other hit is fixed or listed in the PR body.

## Files to Edit

- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`
- `plugins/soleur/test/model-launch-review.test.ts`
- `plugins/soleur/skills/model-launch-review/SKILL.md`
- `plugins/soleur/AGENTS.md`
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`
- `knowledge-base/engineering/architecture/decisions/ADR-083-scoped-strong-model-consult-at-decision-gates.md`

## Files to Create

None.

## Open Code-Review Overlap

None (open `code-review` issues queried; no body names any planned file).

## Acceptance Criteria

- [ ] `AUTOFIX_PAIRS` contains `claude-fable-5=claude-fable-5-2` and `claude-fable-5-1=claude-fable-5-2`; no pair targets `claude-fable-5-1` (`audit-models.sh:AUTOFIX_PAIRS`; `assert_single_hop` exits 0).
- [ ] `plugins/soleur/test/model-launch-review.test.ts` passes, with the `SUPERSEDED` map, `CURRENT_IDS`, the synthetic-prefix source string and the sed-anchor fixture all on `claude-fable-5-2`, and a fixture proving a stale `claude-fable-5-1` is rewritten to `claude-fable-5-2` byte-exactly.
- [ ] `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` reports no stale config ids and exits 0; `--detect` exits 0.
- [ ] `SKILL.md` release list names Fable 5.2; its `description:` is byte-identical to `main` (`git diff main -- plugins/soleur/skills/model-launch-review/SKILL.md` shows no `description:` line).
- [ ] ADR-053 addendum lists the price rows in the table above (Fable 5.2, Fable 5.1, Opus 5.5, Sonnet 5.5, Haiku 5.5 short card), each matching the pricing page fetched 2026-11-09, and labels the 30% and 55% claims as vendor claims.
- [ ] ADR-083 addendum records the six rejections/non-changes with the reason for each and `Ruled by CTO agent, 2026-11-09`.
- [ ] `plugins/soleur/AGENTS.md` pricing basis is dated 2026-11-09 and quotes the 5.2 multiples; no remaining "Fable 5.1 is 2× Opus" sentence.
- [ ] Both pricing-basis texts (ADR-053 addendum, `plugins/soleur/AGENTS.md`) say the 5.2 figures are Anthropic's list price and that `fable` alias resolution on pinned CLI 2.1.311 is unverified (tracked in #12514); neither states that 5.2 is in effect for consults (CPO condition, 2026-11-09).
- [ ] `git grep -inwE 'fable|claude-fable[-0-9a-z]*' -- 'apps/web-platform/server/**/*.ts'` returns no hit, recorded in the ADR-053 addendum as the reason `MODEL_PRICING` is untouched.
- [ ] `harness-model-map.test.ts` and `fable-consult-gates.test.ts` pass unchanged.

## User-Brand Impact

**If this lands broken, the user experiences:** a stale or wrong stale-ID rewrite silently pointing a config model id at a nonexistent model, so an operator-key cron or leader call fails or misroutes spend.
**If this leaks, the user's workflow is exposed via:** no data path is touched; the exposure is a wrong price or id recorded in policy docs that a later launch inherits (the inherited Sonnet cache-read figure of 2026-10-08 is the precedent).
**Brand-survival threshold:** single-user incident

CPO sign-off: yes, 2026-11-09, with the condition recorded in the acceptance criteria above; `soleur:engineering:review:user-impact-reviewer` runs at review.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO ruling carried forward from the brainstorm (2026-11-09): defer the CLI bump, adopt only the pricing re-derivation, reject fast mode, preserved thinking and the orchestrator role. No UI surface, no personal data, no new infrastructure.

## Observability, Encryption, IaC, ADR/C4, Guard Contract

Skipped with reasons: the change retargets a data table in an existing audit script and edits docs, with no new error path, store, connection, infrastructure or guard (Phases 2.8-2.12 do not fire). The two ADR addenda record decisions already ruled; they do not make a new architectural decision, so no C4 view changes (checked: no actor, system or access relationship is added or moved).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled.
- The test parser reads `AUTOFIX_PAIRS` up to the first closing paren: no `)` in comments inside the array.
- Do not write a dated id literal for a retired model into `constants.ts`-style config comments; describe it in prose (`audit-models.sh --detect` flags it).
- Pricing rows are re-derived from the fetched page, not copied from ADR-053's earlier tables (the Sonnet cache-read figure was inherited wrong once).
