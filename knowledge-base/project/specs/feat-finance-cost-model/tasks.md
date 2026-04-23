# Tasks: feat-finance-cost-model

**Plan:** [../../../plans/2026-04-23-docs-finance-cost-model-and-roadmap-sync-plan.md](../../../plans/2026-04-23-docs-finance-cost-model-and-roadmap-sync-plan.md)
**Spec:** [spec.md](./spec.md)
**Branch:** `feat-finance-cost-model`
**PR:** #2835
**Issue:** #1053

## Phase 1 — Author cost-model.md (via budget-analyst)

- [ ] 1.1 Re-read `knowledge-base/operations/expenses.md` frontmatter and tables. If `last_updated` has advanced past 2026-04-19, use the newer date for inline anchors; else use `2026-04-19`.
- [ ] 1.2 Spawn `budget-analyst` (Task) with the scoped authoring prompt. Prompt must pin:
  - Frontmatter per spec FR1.
  - 9 sections per spec FR2 (Monthly Burn, Per-User Infrastructure Cost, Break-Even Analysis, Scaling Triggers, Gross Margin at Scale, Pricing Gate #4 Status, Open Questions, References — plus frontmatter counts as the 9th).
  - R&D vs product-COGS split (~$491/mo all-in, ~$91/mo COGS; break-even ~11 / ~2-3 users at $49/mo).
  - Inline anchor convention per FR3 (`[expenses.md@YYYY-MM-DD]`).
  - BYOK architectural-commitment note verbatim.
  - Stripe fee drag (1.5 % + EUR 0.25 per EU charge) in Break-Even and Gross Margin.
  - Partial Gate #4 framing (affordability only; CPO/CTO hold buildability).
  - Reference the 2026-04-19 conversation-slot memo, ADR-004, expenses.md, pricing-strategy.md, roadmap.md Phase 4.10 + Pricing section.
- [ ] 1.3 Structural verification — frontmatter has all 5 keys; 9 `##` headings present; zero free-floating numbers.
- [ ] 1.4 Gross Margin at Scale shows math (not just "~80%") and names Stripe fee drag.
- [ ] 1.5 Pricing Gate #4 Status section names the CPO/CTO buildability handoff.
- [ ] 1.6 References section lists all 5 targets.

## Phase 2 — Roadmap narrative sync

- [ ] 2.1 Re-grep `roadmap.md` for "CFO" and "Infrastructure cost model" anchors; confirm or correct line numbers vs plan (L63, L64, L404, L416 at plan time).
- [ ] 2.2 Edit CFO burn line (plan-time L63) to the R&D/COGS split formulation (see plan Phase 2.2 for exact target text).
- [ ] 2.3 Edit CFO artifact line (plan-time L64) to reflect cost-model.md shipped.
- [ ] 2.4 Edit Pricing Gate #4 status row (plan-time L404) to "Partial. Affordability documented in `finance/cost-model.md` (~$91/mo COGS, break-even 2-3 users). Buildability pending CPO/CTO assessment."
- [ ] 2.5 Edit cost-model action item (plan-time L416) disposition to "Shipped 2026-04-23 (#2835, partial — Gate #4 buildability remains)."
- [ ] 2.6 Update roadmap `## Current State` section — add "Financial posture" sub-bullet naming both burn scopes and cross-linking to `finance/cost-model.md`.
- [ ] 2.7 Advance `roadmap.md` frontmatter `last_updated` to 2026-04-23; append one line to the bottom generator log naming this PR.

## Phase 3 — Back-links

- [ ] 3.1 `operations/expenses.md` — append "Finance consumer: [finance/cost-model.md](../finance/cost-model.md) — derived monthly burn and break-even model. Refresh on every category subtotal shift >10 % (see cost-model.md `review_cadence`)." below the tables.
- [ ] 3.2 `product/pricing-strategy.md:152` — update Gate 4 Status: "Not assessed" → "Partial — see [finance/cost-model.md](../finance/cost-model.md) (affordability); buildability pending CPO/CTO".
- [ ] 3.3 `product/pricing-strategy.md:25` — append "(cost model now lives in [finance/cost-model.md](../finance/cost-model.md))" at sentence end.

## Phase 4 — Markdownlint + cross-ref sweep

- [ ] 4.1 Run `npx markdownlint-cli2 --fix` passing specific file paths only (cost-model.md, roadmap.md, expenses.md, pricing-strategy.md) per `cq-markdownlint-fix-target-specific-paths`. Zero errors required.
- [ ] 4.2 Re-read any table that `markdownlint --fix` touched — cell spacing can shift per `cq-always-run-npx-markdownlint-cli2-fix-on`.
- [ ] 4.3 Grep every relative `.md` link in cost-model.md; verify each target resolves on disk. Zero BROKEN entries required.
- [ ] 4.4 Grep cost-model.md numeric figures (`\$[0-9]+|\b[0-9]+(?:\.[0-9]+)?%|EUR [0-9]+`); confirm each has an `[expenses.md@YYYY-MM-DD]` anchor within 40 chars.

## Phase 5 — Ship

- [ ] 5.1 Run `skill: soleur:compound` before commit per `wg-before-every-commit-run-compound-skill`.
- [ ] 5.2 Commit: `docs(finance): add cost-model.md; sync roadmap narrative (#1053)` with Co-Authored-By trailer.
- [ ] 5.3 Push.
- [ ] 5.4 Update PR #2835 body: remove draft; add `## Summary`, `## Changelog` (semver:patch), `## Test plan`. Body says "Partially addresses #1053", NOT "Closes".
- [ ] 5.5 Set `semver:patch` label on PR #2835.
- [ ] 5.6 `gh pr ready 2835 && gh pr merge 2835 --squash --auto`; poll to MERGED per `wg-after-marking-a-pr-ready`.
- [ ] 5.7 Verify release/deploy workflows succeed post-merge per `wg-after-a-pr-merges-to-main` (docs-only; no deploy expected; confirm no red CI).
- [ ] 5.8 Operator reviews + closes #1053 if satisfied with partial framing (does NOT auto-close).
- [ ] 5.9 `worktree-manager.sh cleanup-merged`.

## Phase 6 — Post-merge observation (calendared, not blocking)

- [ ] 6.1 30–60 days post-merge: check `gh issue list --label strategy-review` for an auto-generated cost-model.md review issue. If absent, file a new issue to either (a) add the deferred AGENTS.md workflow gate, or (b) extend the strategy-review-cadence cron to include `knowledge-base/finance/` targets. Tracked as plan post-merge AC #2.
