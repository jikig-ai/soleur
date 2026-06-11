---
title: "feat: model-launch-review skill — recurring per-model-release audit + model-ID auto-fix"
date: 2026-06-11
issue: 5100
parent_issue: 3791
adjacent_issue: 5106
brainstorm: knowledge-base/project/brainstorms/2026-06-11-model-launch-review-brainstorm.md
spec: knowledge-base/project/specs/feat-model-launch-review/spec.md
branch: feat-model-launch-review
draft_pr: 5157
lane: single-domain
brand_survival_threshold: not-applicable
requires_cpo_signoff: false
domains_assessed: [Engineering]
---

# feat: model-launch-review skill — recurring per-model-release audit ✨

## Overview

Build `/soleur:model-launch-review`: a CLI-invoked skill that audits the per-Anthropic-
model-release checklist, **auto-fixes the one mechanical-bulk item (model-ID swaps)** and
opens a **CI-gated PR under operator identity**, while **flagging** the judgment/low-demand
items (claude-code-action pin freshness, pricing-table drift, tier-map re-eval, dormant
deferred work) in the PR body for human sign-off. A lightweight detection step is appended
to an existing scheduled workflow (`rule-audit.yml`) that files/updates a single idempotent
`model-drift` issue when config drifts or claude-code-action flips its default model —
closing the dormant-trigger gap (#3791's "pricing change" re-eval never fired when Fable 5
shipped). ADR-053:41 already names `model-launch-review` as the per-release re-pin trigger.

**Premise (verified live):** #3791 closed via PR #5096 (merged 2026-06-10). Re-eval
condition 1 (tiering PR merged) satisfied; condition 2 (next model release) not yet fired —
the ideal window to build the harness while the manual checklist is fresh.

## Plan-Review Revisions (2026-06-11, DHH + Kieran + code-simplicity, all applied)

The first draft was ~35-40% over-scoped for a p3-low auditor. Applied cuts:
- **Cut** the thinking-shape dimension (audits nothing — zero `thinking`/`output_config`
  params in config; the fact lives in the checklist now).
- **Cut** the pre-PR Anthropic compatibility probe + its AC (CI + operator review already
  gate; removes an ANTHROPIC_API_KEY runtime dependency from the skill).
- **Pricing → flag-only** (billing constant with ambiguous source $0.8 vs $1; never auto-edit).
- **Pin-sync → flag-only**, auto-bump ONLY when coupled to a model-ID `--model` swap in the
  same workflow file (#2540 invariant); both pins are currently fresh at v1.0.101.
- **Net auto-fix surface = model-ID swaps only.** Everything else flagged.
- Correctness fixes: provision the `model-drift` label; narrow tier-map audit off
  `PIN_ALLOWLIST`; specify the cron's new-model signal; frozen fixtures for ACs;
  `contents: read` on the host; RED test alongside Phase 1; conditional budget bump.

## Research Reconciliation — Spec vs. Codebase

| Spec/Brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| FR4 cites rule `cq-claude-code-action-pin-freshness` | **Retired 2026-04-24** (`scripts/retired-rule-ids.txt:80`); moved to `plugins/soleur/skills/ship/references/ci-workflow-authoring.md` | Cite the ci-workflow-authoring reference; skill automates that prose rule (flag-only). Drop dead rule-ID. |
| TR1/Decision 6: pricing only in `claude-api` harness skill | Pricing IS in repo: `agent-on-spawn-requested.ts:79-102` `MODEL_PRICING` (sonnet+haiku; Haiku input `0.8`; header "CFO refreshes") + kb/ADR/AGENTS prose | **Flag-only** (never auto-edit a billing constant); the $0.8/$1 delta is a human reconciliation, surfaced not applied. |
| FR4/FR6: per-tier thinking-API shape at `agent-runner-query-options.ts`/`agent-prefill-guard.ts` | **Zero** `thinking`/`output_config`/`budget_tokens` in config; for CI the shape rides the claude-code-action pin's SDK | **Dimension cut from v1**; one-line fact captured in the checklist. |
| FR7/Open Q1: reuse `kb-drift-walker.yml` | kb-drift-walker has **no `issues: write`**, POSTs HMAC JSON to an ingest route | Host on **`rule-audit.yml`** (`issues: write`, governance theme, repo checked out), borrowing `scheduled-terraform-drift.yml:151,180-184` find-or-update idiom. |
| #2540 "coupled triple" is the dominant surface | claude-code-action pins in **2 workflows**, both fresh at `v1.0.101`. Dominant surface = server-side model IDs (16+ Inngest literals + `leader-prompts/constants.ts`) | Auto-fix = model-IDs; pin-bump only coupled to a workflow `--model` swap (#2540). |
| Tier-map is a TS constant; audit `PIN_ALLOWLIST` vs pricing | ADR-053 rejected a `TIER_PINS` map. `workflow-model-pins.test.ts` `PIN_ALLOWLIST` (12 entries) maps step-key→tier-alias (`classify:sonnet`) — **not pricing-sensitive** | Tier-map re-eval (flag-only) targets the cron model literals + ADR-053/AGENTS prose; `PIN_ALLOWLIST` is a **don't-mutate invariant** (AC8) only. |
| Cron "detects new model shipped" | A pure in-repo grep can only find stale IDs already committed — it cannot see Fable-5-shipped | Cron new-model signal = scan `gh api repos/anthropics/claude-code-action/releases` for a default-model flip / new model ID since last tick (in-reach, no ANTHROPIC_API_KEY). Plus config-drift grep. |

**Live drift (dev smoke only, NOT a CI AC — the skill zeroes it):** 5 Inngest crons +
6 skill-reference `.md` lines carry `claude-opus-4-7` (vs `claude-opus-4-8`).

## Dependencies / Boundary with #5106 (OPEN)

#5106 centralizes the scattered cron model literals into `apps/web-platform/server/inngest/
model-tiers.ts`; its re-eval fires *"when #5100 lands and needs a single re-pin surface."*
**Decision: ship #5100 against the current scattered surface; do NOT depend on or fold in
#5106** — #5106's deferral record states it has *"zero shared code/runtime/deploy surface
with the plugin PR"* (deliberate split at 5-agent review). The skill's grep inventory (with
2026-02-22 undercount safeguards) handles scattered literals today; when #5106 lands, the
model-ID grep target collapses to the registry (future simplification). Use `Ref #5106`.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — internal/CI tooling. A
wrong model-ID auto-edit would break a *scheduled workflow* (operator-visible CI failure),
never an end-user surface.
**If this leaks, the user's data is exposed via:** N/A — the skill edits repo config and
calls `gh api`; no user data, credentials, or PII in scope.
**Brand-survival threshold:** none (internal tooling; no sensitive-path diff). Fail-safety
is handled by PR + CI gate + explicit allowlist + deletion guard + post-edit re-grep.

## Implementation Phases

### Phase 0 — Preconditions (verify; never trust memory)
- Resolve the current model landscape from the `claude-api` skill table + a pinned official-
  docs URL. **Do NOT hard-code prices in the plan/script** — read at runtime; for pricing
  (flag-only) report the in-code value vs source and let a human reconcile $0.8 vs $1.
- Fresh full-repo `git grep` of every known model ID (current + stale: opus-4-6/4-7,
  `claude-3*`, `*-20250514`, `anthropic/`-prefixed variants); re-derive class counts
  (config / test-fixture / archive) and **set the deletion-guard `N` from this count** (not
  from this plan's numbers).
- Confirm `rule-audit.yml` `permissions` (add `contents: read` alongside `issues: write`);
  read `scheduled-terraform-drift.yml:151,180-184` find-or-update idiom.
- Provision the label: `gh label create model-drift --color FBCA04 --description "stale model IDs / pin / pricing drift" --force` (idempotent) — `gh issue create --label` FAILS on a nonexistent label.

### Phase 1 — Skill scaffold + RED test (audit core, read-only)
- `plugins/soleur/skills/model-launch-review/SKILL.md` — third-person `description:`, audit
  orchestration, **inlined 5-item checklist + auto-fix-vs-flag matrix + official-docs URL +
  inventory globs** (no separate `references/` dir). Explicit auth precondition:
  interactive `gh` auth required to open the PR; headless/cron invocation files an issue, not
  a PR (else a bot-token PR skips CI — 2026-03-02 learning). Follow `gdpr-gate` (scripts-heavy
  audit) + `fix-issue` (PR-opening) exemplars.
- `scripts/audit-models.sh` — deterministic audit; no silent green (all-clear enumerates
  every check). Three check groups:
  1. **model-ID inventory** (auto-fixable) — classify config vs fixture vs archive; flag
     stale IDs; re-grep variant formats post-scan (2026-02-22).
  2. **pin freshness** (flag) — `gh api .../releases` tip vs each pinned SHA's commit date;
     flag >3wk stale; respect per-workflow pin isolation; resolve every SHA via `gh api`.
  3. **pricing + tier-map + dormant** (flag) — report `MODEL_PRICING` row drift (never edit);
     re-check cron model literals + ADR-053/AGENTS prose vs new pricing; run `gh issue list
     --state open --search "deferred model OR pricing"`.
- Author the **failing** parity test + minimal synthesized fixtures alongside this phase
  (`cq-write-failing-tests-before`).

### Phase 2 — Auto-fix engine (model-IDs only)
- Swap stale model IDs in config via an **explicit file allowlist + deletion guard (abort
  >N)**; **never `git add -A`** (−107k destructive-PR precedent). Update coupled test
  fixtures (`apps/web-platform/test/**`) in the same change so CI stays green. Post-edit
  re-grep for residual stale/variant IDs.
- **Coupled pin-bump (#2540):** only when a model `--model` value is swapped in a claude-
  code-action workflow, bump that workflow's pin in lockstep; otherwise leave pins (flagged).

### Phase 3 — PR mechanism (operator identity → CI runs)
- `worktree-manager.sh create` + `gh pr create` under operator gh auth (NOT `GITHUB_TOKEN`/
  App — so CI + CLA run). Explicit `git config user.name/email` if committing in CI context.
- PR body = model-ID diff + a **flag section** (pin freshness, pricing drift incl. $0.8/$1,
  tier-map judgment, dormant deferred issues). `Ref #5100`, `Ref #5106`.

### Phase 4 — Cron-host detection (reuse existing cron)
- Append a detection step to `rule-audit.yml` running `audit-models.sh --detect`
  (config-drift grep + claude-code-action default-model-flip scan). Add `contents: read`.
  On signal: **find-or-update one** `model-drift` issue (idempotent across ticks — no
  duplicate pile-up; 2026-04-24 drift-as-feature), borrowing terraform-drift's create-or-
  comment idiom. The cron **files an issue, never a PR**.

### Phase 5 — Budget (conditional)
- After Phases 1-3 finalize the `description:`, **measure** cumulative words
  (`bun test plugins/soleur/test/components.test.ts`). Only if it fails, bump
  `SKILL_DESCRIPTION_WORD_BUDGET` (currently 2009; ~1 word headroom) by the new description's
  exact count, citing #5100 (per #5021/#4742 precedent); show before/after. Prefer a tight
  description that fits — do not bump by default (`cq-skill-description-budget-headroom`).

### Phase 6 — Tests (RED-first; fixtures frozen)
- `plugins/soleur/test/model-launch-review.test.ts` over **synthesized, frozen** fixtures
  only (`cq-test-fixtures-synthesized-only`): stale-ID detection, config/fixture/archive
  classification, no-silent-green, allowlist + deletion-guard abort, model-ID-is-the-only-
  auto-fix-dimension (pin/pricing/tier-map never enter the auto-fix set), coupled pin-bump-
  only-on-`--model`-swap. A **frozen** copy of the opus-4-7 drift is the smoke fixture (the
  live sites get zeroed once the skill runs, so the AC must not scan live HEAD).
- CI sentinel for the cron step (`git config` lines present; punctuation-safe substring).

### Phase 7 — Docs / compliance
- Plugin Skill Compliance Checklist (`plugins/soleur/AGENTS.md`); `/soleur:release-docs`
  updates `plugin.json` description + README counts at ship (NOT manual version bump —
  `wg-never-bump-version-files`). Satisfy `hr-new-skills-agents-or-user-facing`.

## Files to Create
- `plugins/soleur/skills/model-launch-review/SKILL.md` (checklist inlined)
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`
- `plugins/soleur/test/model-launch-review.test.ts`
- `plugins/soleur/skills/model-launch-review/test/fixtures/` (minimal synthesized stale-config + stale-fixture pair; frozen opus-4-7 smoke copy)

## Files to Edit
- `.github/workflows/rule-audit.yml` — add `contents: read`; append `--detect` step + find-or-update `model-drift` issue (copy `git config` precedent from a sibling scheduled workflow).
- `plugins/soleur/test/components.test.ts` — budget cap bump **only if** the measured description exceeds headroom (Phase 5).

> Auto-fix *runtime targets* (model-ID config files) are documented in the SKILL.md inlined
> checklist, not edited by this plan — the skill edits them at invocation.

## Acceptance Criteria

### Pre-merge (PR)
- AC1: Against a **frozen synthesized fixture** with stale IDs, `audit-models.sh` reports each stale config ID and classifies it mechanical-auto-fixable; counts asserted against the fixture, not live HEAD.
- AC2: A synthesized config file + a fixture file + an archive file each carrying the same stale ID → only the config hit is auto-fixable; fixture/archive never reported as targets.
- AC3: All-clear run still enumerates all checks (no silent green).
- AC4: Pin-freshness check resolves the action release tip + each pinned SHA date via `gh api` (output shown) and is **flag-only** (does not mutate pins unless a coupled `--model` swap occurs).
- AC5: Auto-fix uses an explicit allowlist + deletion guard; a seeded >N-deletion condition aborts. No `git add -A` anywhere (`grep` gate in test).
- AC6: **Model-ID is the only auto-fix dimension** — test asserts pin/pricing/tier-map/dormant findings never enter the auto-fix set.
- AC7: `bun test plugins/soleur/test/workflow-model-pins.test.ts` stays green (tier-map flag never mutates `PIN_ALLOWLIST`).
- AC8: `bun test plugins/soleur/test/components.test.ts` passes (description within budget, or cap bumped by exact word count with before/after in diff).
- AC9: New skill satisfies the plugin compliance checklist (third-person description ≤1024 chars; scripts/test linked); SKILL.md states the interactive-gh-auth precondition.
- AC10: Coupled pin-bump fires only when a workflow `--model` value is swapped (synthesized test).

### Post-merge (operator)
- AC11: `model-drift` label exists; `rule-audit.yml` next run (or `gh workflow run rule-audit.yml`) files/updates exactly one `model-drift` issue when drift exists; a re-run does not create a duplicate. *Verify: `gh run list --workflow rule-audit.yml` + `gh issue list --label model-drift`.*

## Observability

```yaml
liveness_signal:
  what: rule-audit.yml model-drift detection step run history
  cadence: "0 9 1,15 * *" (twice-monthly, inherited from host)
  alert_target: GitHub Actions run status + the find-or-update model-drift issue
  configured_in: .github/workflows/rule-audit.yml
error_reporting:
  destination: GitHub Actions step failure annotation (audit script exits non-zero on internal error)
  fail_loud: true (no silent green; gh api failures abort the step, not skip)
failure_modes:
  - mode: gh api rate-limit / network on pin-freshness or release-flip scan
    detection: non-zero exit + step annotation
    alert_route: GH Actions failed-run notification
  - mode: model-ID grep false-negative (inventory undercount)
    detection: post-edit re-grep for variant formats; parity-test fixture
    alert_route: PR CI failure (residual stale ID)
  - mode: duplicate tracking issues across ticks
    detection: find-or-update idempotency test
    alert_route: AC11 verification
logs:
  where: GitHub Actions run logs for rule-audit.yml
  retention: GitHub default (90 days)
discoverability_test:
  command: "gh run list --workflow rule-audit.yml --limit 5 && gh issue list --label model-drift --state open"
  expected_output: recent run rows; at most one open model-drift issue
```

## Domain Review

**Domains relevant:** Engineering

### Engineering
**Status:** reviewed
**Assessment:** Internal CI/tooling skill. No UI surface (Files to Create are SKILL.md +
script + test). Product/UX Gate = NONE. No regulated-data surface → GDPR gate skipped. No
new infra (rides existing `rule-audit.yml`; no ANTHROPIC_API_KEY after probe cut) → IaC gate
skipped; permission reuse documented in Observability. Finance touch (pricing/tier) is
flag-only audit, not spend-deciding → not a blocking domain.

### Product/UX Gate
**Tier:** none — no user-facing surface created or modified.

## Open Code-Review Overlap
None. (`gh issue list --label code-review --state open` — no open scope-out names
`plugins/soleur/skills/model-launch-review/**`, `rule-audit.yml`, or `components.test.ts`.)
Adjacent OPEN #5106 is a deliberate split — `Ref`, do not `Closes`.

## Risks & Mitigations / Sharp Edges
- **Auto-fix blast radius** (16+ scattered model-ID sites): allowlist + deletion guard (N from Phase 0 re-grep) + post-edit re-grep + coupled-fixture update + CI gate. Never `git add -A`.
- **GITHUB_TOKEN PR ≠ CI-gated**: skill must `gh pr create` under operator identity; SKILL.md states this; cron files an issue only (2026-03-02).
- **SHA/version from memory is wrong**: resolve every pin SHA + release tag via `gh api` in-pass; show output (2026-04-18 precedent).
- **Pricing is flag-only**: never auto-edit `MODEL_PRICING` (billing constant; $0.8/$1 source ambiguous; opus row absent — defer to #5106).
- **`model-drift` label must exist** before any `gh issue create --label` (Phase 0 provisions it).
- **Cron new-model signal** is the claude-code-action default-model-flip scan, not an Anthropic poll — config-drift covers in-repo staleness; the flip scan covers brand-new-model awareness.
- **Tier-map flag must not mutate** `workflow-model-pins.test.ts` `PIN_ALLOWLIST` (clo-attestation-class) — flag-only.
- **Dormant-trigger justification**: a standalone watcher was rejected for #3791 as over-engineering; this clears the bar via (a) recurring #2540 production 4xx = empirical demand, (b) reuse of an existing cron = no new infra.

## Test Scenarios
1. Stale-ID config vs fixture vs archive classification (synthesized).
2. No-silent-green enumeration on all-clear.
3. Allowlist/deletion-guard abort on seeded mass-deletion.
4. Model-ID is the only auto-fix dimension (pin/pricing/tier-map flagged, never mutated).
5. Coupled pin-bump only on workflow `--model` swap.
6. Cron find-or-update idempotency (no duplicate issues).
7. Budget test green (within budget or bumped by exact count).
8. Frozen opus-4-7 smoke fixture → non-empty, all classified mechanical.
