---
name: model-launch-review
lane: single-domain
plan: knowledge-base/project/plans/2026-06-11-feat-model-launch-review-skill-plan.md
issue: 5100
branch: feat-model-launch-review
---

# Tasks: model-launch-review skill

Derived from the finalized (post-plan-review) plan. Auto-fix surface = **model-IDs only**;
pin/pricing/tier-map/dormant = **flag-only**.

## Phase 0 — Preconditions (verify; never trust memory)
- [ ] 0.1 Resolve current model landscape from `claude-api` skill table + pinned official-docs URL (no hard-coded prices).
- [ ] 0.2 Fresh full-repo `git grep` of every model ID (current + stale: opus-4-6/4-7, `claude-3*`, `*-20250514`, `anthropic/`-prefixed); re-derive config/fixture/archive counts.
- [ ] 0.3 Set deletion-guard `N` from the 0.2 count.
- [ ] 0.4 Confirm `rule-audit.yml` permissions; plan `contents: read` + `issues: write`.
- [ ] 0.5 Read `scheduled-terraform-drift.yml:151,180-184` find-or-update idiom.
- [ ] 0.6 `gh label create model-drift --color FBCA04 --description "..." --force` (idempotent).

## Phase 1 — Skill scaffold + RED test
- [ ] 1.1 `SKILL.md` (third-person description; inlined 5-item checklist + auto-fix-vs-flag matrix + docs URL + inventory globs; interactive-gh-auth precondition note).
- [ ] 1.2 `scripts/audit-models.sh` check group 1: model-ID inventory (classify; flag stale; post-scan variant re-grep).
- [ ] 1.3 `audit-models.sh` check group 2: pin freshness (flag-only; `gh api` tip vs SHA date; per-workflow isolation).
- [ ] 1.4 `audit-models.sh` check group 3: pricing + tier-map + dormant (flag-only; `MODEL_PRICING` drift report; cron-literal/prose re-eval; `gh issue list --search "deferred model OR pricing"`).
- [ ] 1.5 No-silent-green: all-clear enumerates every check.
- [ ] 1.6 Author FAILING parity test + minimal synthesized fixtures (`cq-write-failing-tests-before`).

## Phase 2 — Auto-fix engine (model-IDs only)
- [ ] 2.1 Model-ID swap via explicit file allowlist + deletion guard (abort >N); never `git add -A`.
- [ ] 2.2 Update coupled test fixtures (`apps/web-platform/test/**`) in same change; post-edit re-grep for residuals.
- [ ] 2.3 Coupled pin-bump (#2540): only when a workflow `--model` value is swapped.

## Phase 3 — PR mechanism (operator identity → CI runs)
- [ ] 3.1 `worktree-manager.sh create` + `gh pr create` under operator gh auth (not GITHUB_TOKEN); `git config user.*` if committing in CI.
- [ ] 3.2 PR body: model-ID diff + flag section (pin freshness, pricing incl. $0.8/$1, tier-map, dormant). `Ref #5100`, `Ref #5106`.

## Phase 4 — Cron-host detection (rule-audit.yml)
- [ ] 4.1 Add `contents: read`; append `audit-models.sh --detect` step (config-drift grep + claude-code-action default-model-flip scan).
- [ ] 4.2 Find-or-update one `model-drift` issue (idempotent; terraform-drift create-or-comment idiom); files issue, never PR.
- [ ] 4.3 CI sentinel: `git config` lines present; punctuation-safe substring.

## Phase 5 — Budget (conditional)
- [ ] 5.1 Measure cumulative description words (`bun test plugins/soleur/test/components.test.ts`).
- [ ] 5.2 Only if over: bump `SKILL_DESCRIPTION_WORD_BUDGET` by exact new-description count, cite #5100, show before/after.

## Phase 6 — Tests (RED-first; frozen fixtures)
- [ ] 6.1 `plugins/soleur/test/model-launch-review.test.ts`: detection, classification, no-silent-green, allowlist/deletion-guard abort, model-ID-only-auto-fix, coupled-pin-bump-only-on-`--model`-swap.
- [ ] 6.2 Frozen opus-4-7 smoke fixture (do not scan live HEAD).

## Phase 7 — Docs / compliance
- [ ] 7.1 Plugin Skill Compliance Checklist (`plugins/soleur/AGENTS.md`).
- [ ] 7.2 `/soleur:release-docs` updates `plugin.json` description + README counts at ship (no manual version bump).
- [ ] 7.3 Satisfy `hr-new-skills-agents-or-user-facing`.
