---
feature: wikiskill-skill-evolution
plan: knowledge-base/project/plans/2026-09-18-feat-wikiskill-pattern-wiki-phase-1-plan.md
issue: '#8281'
closes: '#8274'
deferred_to: '#8293'
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-09-18
---

# Tasks — observable proposer + allowlist fix

Scope is the plan's Steps 0–3 only. The pattern layer is deferred to **#8293** (gated).

## Phase 1 — Setup / preconditions

- [ ] 1.1 Confirm `knowledge-base/project/promotion-config.yml` still reads `enabled: true`.
      If it does not, record that — it alone would explain ten weeks of silence.
- [ ] 1.2 Record the current `TARGET_ALLOW_RE` value and its two permitted target shapes
      (`cron-compound-promote.ts:217-218`).
- [ ] 1.3 Re-read the 7 terminal returns and their line numbers; they are the census floor.

## Phase 2 — Guards first (RED before GREEN)

- [ ] 2.1 Write `test/server/inngest/cron-compound-promote-outcome-census.test.ts` (Guard 1):
      walk the handler's `return {` statements, bucket classified vs unclassified,
      assert `unclassified == 0 && classified >= 7`, and fail when the scanner yields `[]`.
- [ ] 2.2 Confirm 2.1 is RED against current `main` (no markers exist yet).
- [ ] 2.3 Write `test/server/inngest/cron-compound-promote-allowlist.test.ts` (Guard 2) with all
      six mutation rows: `x/` prefix, no-`+++`-header, two-file second-forbidden, **rename source**,
      **copy source**, stubbed-empty derivation.
- [ ] 2.4 Add the must-PASS control: a legitimate two-file diff (`AGENTS.rules.md` + a `SKILL.md`)
      must apply. Include one RED fixture written from scratch, not derived from the canonical.
- [ ] 2.5 Confirm rows 1, 2 and 4 are RED against current `main` (they reproduce live bypasses).

## Phase 3 — Core implementation

- [ ] 3.1 Emit `SOLEUR_COMPOUND_PROMOTE_OUTCOME` at **WARN**, inlined (no new module).
      Fields: `status`, `corpus_count`, `clusters_proposed`, `clusters_opened`,
      `refusals: string[]`, `corpus_input_bytes`, `refusal_detail` (≤20 `{cluster_hash, reason}`).
- [ ] 3.2 Call it on all 7 terminal paths (:469, :496, :514, :569, :642, :821, :837).
- [ ] 3.3 Append a reason to `refusals` at each existing refusal site — no new log lines, no
      per-reason counter state.
- [ ] 3.4 Replace the `+++ b/` filter with derivation from `git apply --summary` **+**
      `--numstat -z`, including rename/copy **source** paths.
- [ ] 3.5 Refuse when the derived path set is empty.
- [ ] 3.6 Confirm every Guard 1 and Guard 2 row now behaves as its matrix requires.

## Phase 4 — Verification

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` green.
- [ ] 4.2 `git diff origin/main...HEAD --name-only` touches nothing under
      `knowledge-base/project/learnings/`.
- [ ] 4.3 Write `scripts/followthroughs/compound-promote-outcome-8281.sh` — exit 0 only when a
      marker row exists from a **scheduled** run after the merge; exit 1 while waiting.
- [ ] 4.4 Add the `soleur:followthrough` directive + `follow-through` label to #8281.

## Phase 5 — Post-merge (probe-verified, no operator step)

- [ ] 5.1 Fire `cron/compound-promote.manual-trigger` (already allowlisted — no code change),
      invoked through the harness adapter (`lib/harness.ts` `invokeSkill()`), not a slash literal:
      **Claude** Skill tool `soleur:trigger-cron` · **Grok** `/trigger-cron` · **Devin**
      `/soleur:trigger-cron` · **Codex** `$soleur:trigger-cron`.
- [ ] 5.2 Read the marker from Better Stack and record `status` + `refusals` on #8281.
      **This is the deliverable.**
- [ ] 5.3 Post the measured cause to #8293 so its gate can be evaluated against evidence.
