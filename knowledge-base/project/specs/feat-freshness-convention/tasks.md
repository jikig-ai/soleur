---
lane: cross-domain
tracks_issue: 5999
plan: knowledge-base/project/plans/2026-07-05-feat-freshness-last-reviewed-integrity-gate-plan.md
last_updated: 2026-07-05
---

# Tasks: Freshness `last_reviewed` Integrity Gate (#5999)

Phase order is contract-before-consumer. **Phase 3 must precede Phase 4** (else the budget lint goes RED when frontmatter is added).

## Phase 0 — Preconditions
- [ ] 0.1 Re-measure B_ALWAYS (`wc -c AGENTS.md + AGENTS.core.md` vs 23000).
- [ ] 0.2 Confirm `follow-through-directive-gate.sh` + `lib/incidents.sh` (`emit_incident`, `strip_command_bodies`) API.
- [ ] 0.3 Re-grep automated `last_reviewed` writers; confirm brainstorm `SKILL.md:121` is the sole one.

## Phase 1 — Bump helper (contract)
- [ ] 1.1 Create `scripts/bump-frontmatter-updated.py` (reuse `frontmatter_lib.py`; writes `last_updated` only; no `last_reviewed` setter).
- [ ] 1.2 Create `scripts/test_bump_frontmatter_updated.py` (last_updated written; last_reviewed untouched; missing-frontmatter handled).

## Phase 2 — Integrity gate
- [ ] 2.1 Create `.claude/hooks/context-reviewed-gate.sh` (PreToolUse Bash; deny staged `last_reviewed:` bumps without `Context-Reviewed:` trailer; fail-open otherwise).
- [ ] 2.2 Create `.claude/hooks/context-reviewed-gate.test.sh` (deny/allow/last_updated-only/non-commit/malformed cases).
- [ ] 2.3 Register the hook in `.claude/settings.json` (PreToolUse→Bash).

## Phase 3 — Frontmatter-strip (enables Phase 4)
- [ ] 3.1 Edit `session-rules-loader.sh`: strip leading `---…---` from each sidecar before concat (~L128-158); preserve fail-closed + ≤200B header.
- [ ] 3.2 Add loader test: injected context has rule text but NOT `last_reviewed:`.
- [ ] 3.3 Edit `lint-agents-rule-budget.py`: strip `AGENTS.core.md` frontmatter before byte count (match loader; comment the coupling).
- [ ] 3.4 Edit `lint-agents-rule-budget.test.sh`: assert `AGENTS.core.md` frontmatter excluded from B_ALWAYS.

## Phase 4 — Rule layer under the clock
- [ ] 4.1 Add `last_reviewed: 2026-07-05`, `review_cadence: monthly`, `owner:` frontmatter to `AGENTS.core.md`.
- [ ] 4.2 Confirm `lint-agents-rule-budget.py` green (B_ALWAYS unaffected).

## Phase 5 — Fix Phase 0.25 self-violation
- [ ] 5.1 Edit `plugins/soleur/skills/brainstorm/SKILL.md:121`: `last_updated`-only; cite ADR-085; use the bump helper.
- [ ] 5.2 Grep roadmap-reconcile module + sibling skills for other `last_reviewed` auto-bumps; fix in kind.

## Phase 6 — Extend overdue-review scan
- [ ] 6.1 Edit `.github/workflows/review-reminder.yml`: add repo-root `AGENTS.core.md` to the `find` feed; fix the slug branch for the non-`knowledge-base/` path.

## Phase 7 — ADR + C4
- [ ] 7.1 Create `ADR-085-freshness-last-reviewed-integrity-gate.md` via `/soleur:architecture` (boundary + mechanism + reuse rationale + C4-none enumeration). Re-verify ordinal at ship.

## Phase 8 — Verify
- [ ] 8.1 Run test suite (`package.json scripts.test`) + all new `.test.sh` + both lints.
- [ ] 8.2 Walk AC1–AC8.
