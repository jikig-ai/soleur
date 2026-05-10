---
title: gdpr-gate skill — tasks
date: 2026-05-10
plan: knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-skill-plan.md
spec: knowledge-base/project/specs/feat-compliance-skills-eval/spec.md
adr: knowledge-base/engineering/architecture/decisions/ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md
issue: 3502
pr: 3501
branch: feat-compliance-skills-eval
worktree: .worktrees/feat-compliance-skills-eval/
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: ready-for-work
---

# Tasks: `gdpr-gate` skill

Tasks derive from `knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-skill-plan.md` (post-review). Single PR (#3501). 6 phases. ACs ↔ Plan AC IDs preserved for traceability.

## Phase 1 — Preconditions + Skill Scaffold + Lifted Files (TDD RED)

### 1.1 Preconditions (~30 min)

- [ ] **1.1.1** — Re-read brainstorm `## Domain Assessments → Product (CPO)` and record the verbatim CPO assessment quote in `/work` Phase 0 log (carry-forward sign-off, not re-spawn).
- [ ] **1.1.2** — Run `bun test plugins/soleur/test/components.test.ts 2>&1 | head -n 80`; verify cumulative skill-description budget has ≥30 words headroom before adding `gdpr-gate` description. If <30 words, halt and file chore PR per `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`.
- [ ] **1.1.3** — Run `wc -c AGENTS.md`; verify ≥600 bytes headroom (current baseline ~24,618 bytes, target ≤37,000).
- [ ] **1.1.4** — Verify Sprinto upstream commit SHA reachable: `gh api repos/goSprinto/compliance-skills/commits/7b58d68461cb1fc033a063e34cc9de63d0b4144b --jq .sha`. If drifted, re-pin in NOTICE.
- [ ] **1.1.5** — Run lefthook glob audit: `git ls-files | grep -E '^(apps/web-platform/supabase/migrations/|apps/web-platform/(lib|server)/.*auth|apps/web-platform/app/api/|.*\.sql$)' | wc -l`. Confirm ≥1 match for each branch.
- [ ] **1.1.6** — Confirm TDD gate: AC20 test scaffolding lands before any SKILL.md prose (RED before GREEN).

### 1.2 Skill scaffold + RED test

- [ ] **1.2.1** — Create directory tree `plugins/soleur/skills/gdpr-gate/{,references/,references/layers/,scripts/}`.
- [ ] **1.2.2** — Write `plugins/soleur/skills/gdpr-gate/SKILL.md`: frontmatter (`name: gdpr-gate`, ≤30-word/≤300-char description starting "This skill"), ≤500 lines, sections: When-to-invoke, Disclaimer (always first), 5 mandatory v1 checks, Output format (Critical/Important/Suggestion), Critical-finding escalation, Path globs (canonical regex), First-run on existing codebase. Use `[name](./references/<file>.md)` markdown link convention. **AC1**.
- [ ] **1.2.3** — Write FAILING `plugins/soleur/test/gdpr-gate.test.ts` with assertions for AC20(a)-(e); assert FR4.5 = Critical, FR4.1-4.4 = Important. Run `bun test plugins/soleur/test/gdpr-gate.test.ts` → expect RED.
- [ ] **1.2.4** — Verify components.test.ts still passes after the new SKILL.md description lands (no regression on cumulative word budget). **AC21**.

### 1.3 Lift 5 active-layer files + write 2 from scratch + NOTICE

- [ ] **1.3.1** — Lift `pii-detector/patterns/fields.md` (blob `c1bb748...`) → `references/fields.md`; prepend attribution header line 1; append Art. 9 special-category fields (political, religious, union, sexual orientation, genetic).
- [ ] **1.3.2** — Lift `pii-detector/rules/leakage-vectors.md` (blob `15a46e5...`) → `references/leakage-vectors.md`; prepend attribution header verbatim.
- [ ] **1.3.3** — Lift `pii-detector/layers/api-layer.md` (blob `9d32021...`) → `references/layers/api-layer.md`; prepend attribution header verbatim.
- [ ] **1.3.4** — Lift `pii-detector/layers/data-in-transit.md` (blob `6c9eeab...`) → `references/layers/data-in-transit.md`; prepend attribution header; append Chapter V cross-border transfer check.
- [ ] **1.3.5** — Lift `pii-detector/layers/data-lifecycle.md` (blob `a073ef2...`) → `references/layers/data-lifecycle.md`; prepend attribution header; rewrite DL-04 export to GDPR Art. 20 + CCPA.
- [ ] **1.3.6** — Vendor-surface scrub: `rg -i 'sprinto\.com|utm_source=Claude|powered by sprinto|sprinto logo' plugins/soleur/skills/gdpr-gate/references/`. Expect zero hits (per brainstorm scrub list — none of the 5 active-layer source files contain vendor surface). **AC5**.
- [ ] **1.3.7** — Write `references/non-negotiables.md` from scratch (GDPR Art. 5/6/9/25/32 first-class; CCPA + HIPAA secondary).
- [ ] **1.3.8** — Write `references/legal-consent.md` from scratch (ePrivacy + Art. 7/13/14/35).
- [ ] **1.3.9** — Write `NOTICE` with 5 active-layer rows (no fold-layer rows in v1) — schema per plan §Phase 1 step 6. **AC2**.
- [ ] **1.3.10** — Verify each lifted file (5 files) has the literal attribution header on line 1: `head -n 1 plugins/soleur/skills/gdpr-gate/references/{fields.md,leakage-vectors.md,layers/{api-layer,data-in-transit,data-lifecycle}.md}`. **AC4**.

## Phase 2 — Lefthook hook + canonical regex + ADR amendment

- [ ] **2.1** — Build canonical regex; document in SKILL.md `## Path globs (canonical)` as single source of truth.
- [ ] **2.2** — Write `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`, source `.claude/hooks/lib/incidents.sh`, always `exit 0`, advisory line to stderr per plan template). **AC6**.
- [ ] **2.3** — Add `gdpr-gate-advisory` entry to `lefthook.yml` (priority 6, glob array form per gobwas semantics, `run: bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh {staged_files}`). **AC7**.
- [ ] **2.4** — Verify hook via `lefthook run pre-commit` against a fixture commit touching `apps/web-platform/supabase/migrations/test_fixture.sql`; confirm advisory printed and exit 0.
- [ ] **2.5** — Amend `knowledge-base/engineering/architecture/decisions/ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md`: drop NFR-027 row, drop NFR-030 row, move never-delete framing to AP-009 alignment, append `## Amendments` section dated 2026-05-10 logging the reconciliation. **AC18**.

## Phase 3 — Plan / Work / Ship / Brainstorm / Review / Legal-Audit Integration

- [ ] **3.1** — Add Phase 2.7 to `plugins/soleur/skills/plan/SKILL.md` between 2.6 and 3 (per plan §Phase 3 step 1 prose). **AC8**.
- [ ] **3.2** — Add single-pass Phase 2.8 to `plugins/soleur/skills/work/SKILL.md` at end of Phase 2 (after per-task TDD loop completes, before Phase 2.5). Amend spec FR2 wording in `knowledge-base/project/specs/feat-compliance-skills-eval/spec.md` line 46. **AC9**.
- [ ] **3.3** — Add `gdpr-gate critical-finding-acknowledgment` block to `plugins/soleur/skills/ship/SKILL.md` Phase 5.5 between COO Expense-Tracking and Deploy Pipeline Fix Drift gates (full block per plan §Phase 3 step 3). **AC10**.
- [ ] **3.4** — Extend CLO Task Prompt in `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` with the gdpr-gate recommendation line. **AC11**.
- [ ] **3.5** — Add `gdpr-gate` to `plugins/soleur/skills/review/SKILL.md` conditional-agent block; **canonical boundary disambiguation prose lives here only** (the three-agent boundary text). **AC13**.
- [ ] **3.6** — Add cross-reference note to `plugins/soleur/skills/legal-audit/SKILL.md`: "If `gdpr-gate` flags a new PII column (Art. 9 or otherwise), run this skill against the privacy policy to verify disclosure." **AC17**.

## Phase 4 — Agent boundary cross-refs + AGENTS.md rule + README sync

- [ ] **4.1** — Add single-line cross-reference to `plugins/soleur/agents/engineering/review/data-integrity-guardian.md`: "Boundary vs gdpr-gate: see `plugins/soleur/skills/review/SKILL.md` §boundaries." **AC14**.
- [ ] **4.2** — Add identical cross-reference to `plugins/soleur/agents/engineering/review/security-sentinel.md`. **AC15**.
- [ ] **4.3** — `clo.md` — **NO EDIT** (AC16 dropped; CLO already reads `compliance-posture.md`).
- [ ] **4.4** — Insert AGENTS.md Hard Rule `[id: hr-gdpr-gate-on-regulated-data-surfaces]` (≤600 bytes) after the existing user-impact rule. Run `python3 scripts/lint-rule-ids.py` and verify `wc -c AGENTS.md ≤ 37000`. **AC12**.
- [ ] **4.5** — Add header comment block to `knowledge-base/legal/compliance-posture.md` documenting Active Items row schema and gate-CLO handshake (no row write). **AC23**.
- [ ] **4.6** — Run `scripts/sync-readme-counts.sh`; verify the script's diff lands a `gdpr-gate` row in the appropriate subsection (no manual edit). **AC22**.

## Phase 5 — Test + Multi-Agent Review + Token-Budget Verification

- [ ] **5.1** — Flesh out `plugins/soleur/test/gdpr-gate.test.ts` per AC20(a)-(e). Run `bun test plugins/soleur/` → all GREEN.
- [ ] **5.2** — Run `lefthook run pre-commit` against fixture commits; verify glob-match and no-glob-match paths.
- [ ] **5.3** — Token-budget verification (in-test, no committed fixture): synthesized 10-row schema diff (1 Art. 9 hit) + 2k-char plan excerpt; assert Anthropic SDK `response.usage.input_tokens ≤ 4000` AND `response.usage.output_tokens ≤ 1500`. **AC24**.
- [ ] **5.4** — Push branch: `git push -u origin feat-compliance-skills-eval` (re-push current state per `rf-before-spawning-review-agents-push-the`).
- [ ] **5.5** — Run `/soleur:review`; verify multi-agent fan-out includes data-integrity-guardian, security-sentinel, architecture-strategist, code-simplicity-reviewer, dhh-rails-reviewer, kieran-rails-reviewer, **`user-impact-reviewer` (REQUIRED — `single-user incident` threshold)**, and `gdpr-gate` self-invocation. **AC25**.
- [ ] **5.6** — Resolve review findings inline per `rf-review-finding-default-fix-inline`; scope-out criteria per `plugins/soleur/skills/review/SKILL.md` §5.
- [ ] **5.7** — Verify all rule-IDs cited in plan/SKILL.md/AGENTS.md rule/ADR amendment exist in AGENTS.md and not in `scripts/retired-rule-ids.txt` (Sharp-Edges verification command). **AC26**.

## Phase 6 — Compound + Ship + v2 Follow-up Issues

- [ ] **6.1** — Run `skill: soleur:compound` to capture session learnings.
- [ ] **6.2** — File 3 v2 follow-up issues (per AC-PM-2):
  - "Add gdpr-gate as preflight Check 10 (Q1 follow-up)" — `domain/engineering`, `priority/p3-low`, milestone "Post-MVP / Later".
  - "Define version-pin policy for lifted Sprinto files (Q3 follow-up)" — `domain/legal`, `priority/p3-low`, milestone "Post-MVP / Later".
  - "Implement gdpr-gate v2 layers + repo-scan mode" — `domain/engineering`, `priority/p3-low`, milestone "Post-MVP / Later".
- [ ] **6.3** — Run `/soleur:ship`. Verify Phase 5.5 gates fire correctly (CMO content-opportunity, CMO website framing, gdpr-gate-acknowledgment skips silently because v1 introduces no Critical findings — Critical reserved for Art. 9 column matches per FR4.5). PR body uses `Ref #3502` (NOT `Closes #3502`). Squash-merge label `feat:minor`. **AC27**.
- [ ] **6.4** — Post-merge: update `compliance-posture.md` `last_updated` frontmatter on `main`; verify CI green via `gh run list --workflow plugin-component-test.yml --limit 1`; smoke-test `/soleur:gdpr-gate` against `main` HEAD on the spec file. **AC-PM-1, AC-PM-3, AC-PM-4**.

## Resume Prompt

```
/soleur:work knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-skill-plan.md
Branch: feat-compliance-skills-eval. Worktree: .worktrees/feat-compliance-skills-eval/. Issue: #3502. PR: #3501. Plan reviewed (3-agent fan-out applied 8 fixes); ADR-026 + brainstorm + spec all on disk; ready for Phase 1 §Preconditions then RED.
```
