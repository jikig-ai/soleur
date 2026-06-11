---
title: "Tasks: auto-approve brainstorm Phase 0.1 user-impact gate"
issue: 5175
branch: feat-one-shot-5175-phase01-auto-brand-critical
lane: cross-domain
plan: ../../plans/2026-06-11-chore-brainstorm-auto-approve-phase01-brand-critical-plan.md
---

# Tasks — chore(brainstorm): auto-approve Phase 0.1 user-impact gate

Derived from `knowledge-base/project/plans/2026-06-11-chore-brainstorm-auto-approve-phase01-brand-critical-plan.md`. Pure prose edit to one skill file; no application code, no new tests.

## Phase 1 — Rewrite Phase 0.1 (substantive edit)

- [ ] 1.1 In `plugins/soleur/skills/brainstorm/SKILL.md`, delete Step 1's `AskUserQuestion` framing call (Header/Question/multi-select note/6-preset options list) in the `### Phase 0.1: User-Impact Framing` section.
- [ ] 1.2 Delete Step 2's keyword tables (user-data/auth lens + infra/data-store lens) and the `If any keyword matches / If no keyword matches` branch.
- [ ] 1.3 Replace with an unconditional block: set `USER_BRAND_CRITICAL=true` (no prompt, no parse) with a one-line rationale citing #5175.
- [ ] 1.4 Synthesize the `## User-Brand Impact` block: artifact = the feature's named surface (DYNAMIC, derived from the feature description — not a static literal), vector = generic, threshold = `single-user incident`.
- [ ] 1.5 Keep the announce line (reword to note auto/per-#5175).
- [ ] 1.6 KEEP Step 3 telemetry emit (`emit_incident hr-weigh-every-decision-against-target-user-impact applied`) verbatim.
- [ ] 1.7 Update the line-103 comment so it no longer describes a "fired vs asked" distinction (now always fires); state the accepted constant-ratio tradeoff. Do NOT delete the emit.
- [ ] 1.8 Keep Step 4 (Phase 3.5 persist contract); reword "reflecting the operator's answer" → "reflecting the synthesized framing".
- [ ] 1.9 Keep the `**Why:**` #2887 paragraph; optionally append one sentence on the #5175 unconditional change.

## Phase 2 — Cross-reference alignment

- [ ] 2.1 Update `brainstorm/SKILL.md` Phase 0.4 line-113 skip rationale ("The framing question was already answered" → "Phase 0.1 unconditionally sets it; lane fixed to cross-domain — no prompt"). Lane auto-set is EXISTING behavior.
- [ ] 2.2 (Optional) Light prose touch to `brainstorm-domain-config.md` lines 16–18 opener ("When brainstorm Phase 0.1 sets…" → "always sets…"). No logic change. Skip if the existing wording reads correctly under always-true.

## Phase 3 — Self-consistency verification

- [ ] 3.1 `grep -n "USER_BRAND_CRITICAL=false\|no keyword matches\|If any keyword" plugins/soleur/skills/brainstorm/SKILL.md` → zero hits.
- [ ] 3.2 `grep -c "emit_incident hr-weigh-every-decision-against-target-user-impact applied" plugins/soleur/skills/brainstorm/SKILL.md` → exactly 1.
- [ ] 3.3 `grep -n "## User-Brand Impact" plugins/soleur/skills/brainstorm/SKILL.md` → present in Step 2 + Step 4.
- [ ] 3.4 Read Phase 0.1 + 0.4 (lines ~63–127) end-to-end: no "ask the question" prose; unconditional set unambiguous; artifact dynamic.
- [ ] 3.5 Run smoke tests: `bun test plugins/soleur/test/mandatory-wireframes-hardening.test.ts`, `bash plugins/soleur/test/lane-frontmatter.test.sh`, `bun test plugins/soleur/test/components.test.ts` → all pass. (Use `package.json scripts.test` runner if `bun` is not configured.)
- [ ] 3.6 `git diff --name-only` confirms only `brainstorm/SKILL.md` (+ optionally `brainstorm-domain-config.md`) and this plan/spec/tasks are touched; NO `feat-agents-md-*` spec, NO `feat-operator-weekly-digest` file.

## Phase 4 — Ship

- [ ] 4.1 PR body: `Closes #5175`, `## Changelog` section, `semver:patch` label.
