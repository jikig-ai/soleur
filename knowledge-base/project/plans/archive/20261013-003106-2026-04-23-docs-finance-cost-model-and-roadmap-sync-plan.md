---
name: finance-cost-model-and-roadmap-sync
description: Implementation plan for issue #1053 — create knowledge-base/finance/cost-model.md as a derived summary of operations/expenses.md, sync roadmap narrative, and add back-links. AGENTS.md workflow gate deferred per plan review.
type: plan
date: 2026-04-23
issue: "#1053"
pr: "#2835"
branch: feat-finance-cost-model
status: ready-for-review
---

# Plan: Finance Cost Model and Roadmap Narrative Sync

**Issue:** #1053 (OPEN, P2-medium, milestone "Phase 4 (Validate + Scale)")
**Brainstorm:** [knowledge-base/project/brainstorms/2026-04-23-finance-cost-model-brainstorm.md](../brainstorms/2026-04-23-finance-cost-model-brainstorm.md)
**Spec:** [knowledge-base/project/specs/feat-finance-cost-model/spec.md](../specs/feat-finance-cost-model/spec.md)
**Semver:** `patch` — documentation-only, no new skill/agent/command, no AGENTS.md rule.

## Overview

Create `knowledge-base/finance/cost-model.md` as a derived view over the authoritative expense ledger (`knowledge-base/operations/expenses.md`). In the same PR, sync the roadmap narrative that carries the stale Feb-2026 CFO burn figure (EUR 35-44, break-even 1-2 users) to the reconciled R&D/tooling vs product-COGS split (~$491/mo all-in, ~$91/mo product-COGS, break-even ~11 / ~2-3 users). Add back-links from dependent docs. Freshness is enforced by cost-model.md's own frontmatter (`review_cadence: monthly`, `depends_on: [operations/expenses.md, product/pricing-strategy.md]`) plus the existing strategy-review-cadence cron — no new AGENTS.md rule, no new hooks.

## Research Reconciliation — Spec vs. Codebase

The spec was drafted from brainstorm-era findings. A plan-time grep over the current tree surfaced three corrections that must land in this plan:

| Spec claim                                                                                  | Reality (grepped 2026-04-23)                                                                                                                                    | Plan response                                                                                                                                |
| ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| FR4 — "update `product/roadmap.md` L63 + L397"                                              | L63 is correct (CFO burn line). **L397 is not a CFO line.** The Pricing Gate #4 status row is at **L404**; the cost-model action item is at **L416**.          | Phase 2 edits L63, L404, L416, and L64 (second CFO line — also stale). Use grep-for-anchors rather than line numbers at work time.            |
| FR5 — "`product/pricing-strategy.md` Gate #4 section references finance/cost-model.md"      | Gate #4 lives at `pricing-strategy.md:152` (`\| Infrastructure ready \| … \| Not assessed \|`). Status is literally "Not assessed". Pivot context is at L25.    | Phase 3 updates the Status column to a partial-addressal phrasing and adds a reference link from L25 (where pivot escalates Gate #4 urgency). |
| Brainstorm — "expenses.md ledger `last_updated: 2026-04-19`"                                | `head -3 operations/expenses.md` at plan time: `last_updated: 2026-03-18`. The ledger frontmatter is stale vs the 2026-04-19 content update.                    | cost-model.md inline anchors use `[expenses.md@2026-04-19]` to match content date, not frontmatter date. Phase 1 confirms this at work time.  |
| Spec FR6 — "add one AGENTS.md Workflow Gate rule"                                           | AGENTS.md at 40084 / 40000 byte warn threshold; adding ~220 bytes crosses further. Freshness is already served by frontmatter + strategy-review-cadence cron.   | **FR6 deferred** per plan review (simpler path — see §Alternative Approaches). Spec FR6 moved to Non-Goals.                                   |

## Files to Create

- `knowledge-base/finance/cost-model.md` — the living cost model (FR1, FR2, FR3 from spec).

## Files to Edit

- `knowledge-base/product/roadmap.md` — L63 + L64 (CFO narrative lines), L404 (Pricing Gate #4 status row), L416 (cost-model action item disposition), `## Current State` section (prominent numbers), `last_updated` frontmatter.
- `knowledge-base/operations/expenses.md` — add one "Finance consumer" back-link line (FR5).
- `knowledge-base/product/pricing-strategy.md` — L152 Gate #4 status column update + L25 reference link (FR5).

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` run against all four planned file paths (cost-model.md, roadmap.md, expenses.md, pricing-strategy.md) returned zero matches at plan time.

## Domain Review

**Domains relevant:** Finance.

### Finance (CFO)

**Status:** reviewed (carried forward from brainstorm 2026-04-23)
**Assessment:** CFO recommended the Approach A derived-summary structure (single file, 8 sections, inline anchors), flagged the Feb-2026 burn figure as ~10× off the current ledger and prescribed the R&D/COGS split, declined sibling finance docs as premature, positioned cost-model.md as partial addressal of Pricing Gate #4 (affordability only — buildability stays with CPO/CTO), and delegated sole authorship to **budget-analyst**.

**Brainstorm-recommended specialists:** `budget-analyst` — deferred to `/soleur:work` via user decision at plan time. `revenue-analyst` and `financial-reporter` explicitly NOT delegated (pre-revenue).

### Product/UX Gate

**Tier:** NONE — no new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files; pure markdown documentation.

## Acceptance Criteria

### Pre-merge (PR)

1. `knowledge-base/finance/cost-model.md` exists with FR1 frontmatter (`last_updated: 2026-04-23`, `last_reviewed: 2026-04-23`, `review_cadence: monthly`, `owner: cfo`, `depends_on: [knowledge-base/operations/expenses.md, knowledge-base/product/pricing-strategy.md]`) and all eight FR2 sections.
2. Every numeric figure in cost-model.md carries an inline `[expenses.md@2026-04-19]` anchor. Verified by `grep -oP '\$[0-9]+|\b[0-9]+(?:\.[0-9]+)?%|EUR [0-9]+' cost-model.md` — every hit has a following anchor within 40 chars.
3. `product/roadmap.md` L63 + L64 CFO lines rewritten to the R&D/COGS split formulation; L404 Gate #4 status row updated to partial-addressal; L416 action-item disposition updated; `## Current State` section updated with the new numbers; `last_updated` frontmatter advanced to 2026-04-23.
4. `product/pricing-strategy.md:152` Gate #4 status column updated from "Not assessed" to "Partially addressed — affordability documented in `finance/cost-model.md`; buildability pending CPO/CTO assessment"; L25 adds a `finance/cost-model.md` reference.
5. `operations/expenses.md` has a "Finance consumer: [finance/cost-model.md]" back-link line.
6. `npx markdownlint-cli2 --fix` passes cleanly on **only** the changed files. No repo-wide glob.
7. All cross-references resolve (`grep -oE '\[.+?\]\([^)]+\.md\)' cost-model.md` → every target exists on disk).
8. PR body says "Partially addresses #1053" (not `Closes`). Gate #4 buildability remains open.

### Post-merge (operator)

1. Issue #1053 — review the Task list; if the founder agrees the "partial Gate #4" framing satisfies the original intent, close the issue manually. Do NOT rely on auto-close.
2. Observe for 30–60 days whether the strategy-review-cadence cron opens a monthly review issue for cost-model.md. If no such cron exists or fires (verify via `gh issue list --label strategy-review` after a month), file a new issue to either add the AGENTS.md workflow gate (reversing this plan's deferral) or add cost-model.md to the cron's target list.
3. No production systems touched. No terraform, no migrations, no workflow runs to verify.

## Implementation Phases

### Phase 1 — Author `knowledge-base/finance/cost-model.md` via `budget-analyst`

- [ ] 1.1 Re-read `operations/expenses.md` frontmatter + tables. If the COO has advanced the `last_updated` past 2026-04-19, use the newer date for inline anchors; otherwise use 2026-04-19 (content date).
- [ ] 1.2 Spawn `budget-analyst` (Task) with a scoped prompt instantiating FR1, FR2, FR3 from the spec. Prompt must include: the reconciled burn split numbers from the brainstorm, exact frontmatter fields, the 9 required sections, the inline-anchor convention, the BYOK architectural-commitment phrasing.
- [ ] 1.3 Verify output structurally: frontmatter complete; 9 `##` section headings present; zero free-floating numbers (every numeric figure followed within 40 chars by `[expenses.md@YYYY-MM-DD]`).
- [ ] 1.4 Verify §Gross Margin at Scale **shows the math** (not just "~80%") and acknowledges Stripe fee drag (1.5 % + EUR 0.25 per EU charge).
- [ ] 1.5 Verify §Pricing Gate #4 Status explicitly names the CPO/CTO buildability handoff.
- [ ] 1.6 Verify References section lists all five targets (expenses.md, pricing-strategy.md, roadmap.md Phase 4.10 + Pricing section, ADR-004-byok-encryption-model.md, `finance/memos/2026-04-19-conversation-slot-economics-cfo-reconsult.md`).

### Phase 2 — Roadmap narrative sync

- [ ] 2.1 Re-grep `roadmap.md` for "CFO" and "Infrastructure cost model" to confirm current line anchors (other PRs may have shifted them between plan-time and work-time).
- [ ] 2.2 Edit L63 CFO burn line. Target: `| **CFO** | ~$91/mo product COGS (break-even 2-3 users at $49/mo), ~$491/mo all-in (break-even ~11 users). BYOK eliminates per-user LLM cost. Dev-tooling (Claude Code Max, Copilot) classed R&D, not COGS — see finance/cost-model.md. | No structural change. Confirmed pricing gate sequencing is correct. |`
- [ ] 2.3 Edit L64 CFO artifact line: "No finance artifacts exist. Need cost model." → "Finance cost model shipped in #2835 (2026-04-23). Pricing Gate #4 partially addressed."
- [ ] 2.4 Edit L404 Gate #4 status row: "CFO assessed: EUR 35-44/month burn, break-even at 1-2 users" → "Partial. Affordability documented in `finance/cost-model.md` (~$91/mo COGS, break-even 2-3 users). Buildability pending CPO/CTO assessment."
- [ ] 2.5 Edit L416 action item disposition: "Before P4" → "Shipped 2026-04-23 (#2835, partial — Gate #4 buildability remains)."
- [ ] 2.6 Update the roadmap's `## Current State` section with the new numbers so operators citing the roadmap see the split, not just the tables: add a "Financial posture" sub-bullet naming the two burn scopes and cross-linking to `finance/cost-model.md`.
- [ ] 2.7 Advance `last_updated` frontmatter to 2026-04-23 and append one line to the bottom generator log naming this PR.

### Phase 3 — Back-links from dependent docs

- [ ] 3.1 `operations/expenses.md` — append one line below the tables: `**Finance consumer:** [finance/cost-model.md](../finance/cost-model.md) — derived monthly burn and break-even model. Refresh on every category subtotal shift >10 % (see cost-model.md`review_cadence`).`
- [ ] 3.2 `product/pricing-strategy.md:152` — update the Status column of the Gate 4 row: "Not assessed" → "Partial — see [finance/cost-model.md](../finance/cost-model.md) (affordability); buildability pending CPO/CTO".
- [ ] 3.3 `product/pricing-strategy.md:25` — append a parenthetical reference at the end of the sentence: "(cost model now lives in [finance/cost-model.md](../finance/cost-model.md))".

### Phase 4 — Markdownlint + cross-ref sweep

- [ ] 4.1 `npx markdownlint-cli2 --fix knowledge-base/finance/cost-model.md knowledge-base/product/roadmap.md knowledge-base/operations/expenses.md knowledge-base/product/pricing-strategy.md` — pass specific paths per `cq-markdownlint-fix-target-specific-paths`.
- [ ] 4.2 For every relative `.md` link in cost-model.md, verify the target exists (grep + test script documented in AC 7). Zero BROKEN lines required.
- [ ] 4.3 Re-read cost-model.md tables after `markdownlint --fix` per `cq-always-run-npx-markdownlint-cli2-fix-on` (tables can shift cell spacing).

### Phase 5 — Ship

- [ ] 5.1 Run `skill: soleur:compound` before commit per `wg-before-every-commit-run-compound-skill`.
- [ ] 5.2 Commit: `docs(finance): add cost-model.md; sync roadmap narrative (#1053)`. Include Co-Authored-By.
- [ ] 5.3 Push.
- [ ] 5.4 Update PR #2835 body: remove draft status, add `## Summary`, `## Changelog` (semver:patch), `## Test plan` (markdownlint passed; cross-refs resolve; numbers traceable to ledger). Body MUST say "Partially addresses #1053", NOT "Closes".
- [ ] 5.5 Set `semver:patch` label on PR #2835.
- [ ] 5.6 `gh pr ready 2835 && gh pr merge 2835 --squash --auto` — poll until MERGED per `wg-after-marking-a-pr-ready`.
- [ ] 5.7 After merge, verify release/deploy workflows succeed per `wg-after-a-pr-merges-to-main`. Docs-only PR should not trigger deploy; confirm no red CI.
- [ ] 5.8 Operator closes #1053 if satisfied with the partial framing.
- [ ] 5.9 `worktree-manager.sh cleanup-merged`.

## Test Plan

No automated tests — documentation change. Verification is structural and mechanical:

- Markdownlint clean on every changed file (AC 6).
- Every cross-reference target resolves on disk (AC 7, scripted grep).
- Every numeric figure in cost-model.md has an inline anchor within 40 chars (AC 2, scripted grep).
- Roadmap `last_updated` matches cost-model.md `last_updated` within 24 hours.

## Risks

- **Concurrent expenses.md edits.** If the COO advances the ledger during this PR, inline anchors in cost-model.md race against the new ledger date. Mitigation: Phase 1.1 re-reads the ledger date immediately before Phase 1.2 authoring.
- **Partial-addressal framing misread as "closed".** Operators may see "finance cost model shipped" and auto-close Gate #4. Mitigation: AC #8 forces PR body to say "Partially addresses"; roadmap L416 disposition explicitly names the remaining buildability work; Phase 2.6 prominently surfaces both burn scopes in `## Current State`.
- **External comms citing the old number.** After merge, a founder writing a blog post, investor update, or pitch deck may cite the EUR 35-44 figure from memory. The roadmap change will lag recall. Mitigation: Phase 2.6 `## Current State` entry ensures any "what's the burn?" reader lands on the split numbers; Phase 5.4 PR body prominently names the reconciliation as the change.
- **Line numbers drift at implementation time.** Another PR could touch roadmap.md between plan-merge and work-start. Mitigation: Phase 2.1 re-greps for "CFO" and "Infrastructure cost model" anchors rather than relying on line numbers.
- **budget-analyst agent output deviates from spec.** The agent may produce different section ordering, skip the BYOK architectural-commitment note, or fabricate numbers not in the ledger. Mitigation: Phase 1.3–1.6 are structural verifications; Phase 2 explicitly pins the break-even numbers the agent must have used. If verification fails, iterate on the agent prompt rather than hand-editing — the prompt is the source of reproducibility.
- **Freshness rot without AGENTS.md rule.** FR6 deferral bets that frontmatter + strategy-review-cadence cron is sufficient. If the cron is absent or doesn't cover `finance/` yet, cost-model.md may go stale silently. Mitigation: post-merge AC #2 adds a 30–60 day observation window; if the cron doesn't fire a review issue, a follow-up PR adds either the AGENTS.md rule or extends the cron's target list.

## Non-Goals

- No sibling finance docs (`revenue-model.md`, `burn-rate.md`, `break-even.md`, `pricing-model.md`). Deferred by CFO; pre-revenue; premature.
- No absorption of the 2026-04-19 conversation-slot memo. It stays as a dated decision record under `finance/memos/`.
- **No AGENTS.md workflow gate rule.** Spec FR6 deferred per plan review (originally proposed in the brainstorm's decision #9 refresh mechanism). Rationale: (a) byte budget already over 40 KB warn threshold; (b) existing `strategy-review-cadence` frontmatter system + `/ship` Phase 5.5 COO gate covers freshness for this file class; (c) the rule can be added later with no migration cost if observation proves it necessary. See Post-merge AC #2 for the observation trigger.
- No new hook (`.claude/hooks/finance-freshness.sh`). Same rationale as the AGENTS.md rule.
- No CFO-cron scheduled agent. Monthly refresh is a human-driven review cadence.
- No external-facing cost disclosure. cost-model.md is internal-first.
- No claim that cost-model.md closes Pricing Gate #4. Partial addressal only.
- No compression of `hr-never-fake-git-author` (736 bytes, pre-existing over-cap). That cleanup belongs in its own PR.

## Alternative Approaches Considered

| Approach                                                                                | Why rejected                                                                                                                                                                                                  |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ship with the AGENTS.md workflow gate inline (spec FR6 as written)                      | Plan-review flagged: adds ~220 bytes to a file already 84 bytes over the 40 KB warn threshold, forces a compression follow-up, duplicates freshness enforcement already provided by frontmatter + strategy-review cron. Deferred to observation-triggered follow-up (post-merge AC #2). |
| Compress `hr-never-fake-git-author` inline to free budget for the new rule             | Entangles a finance-doc PR with a hard-rule edit that deserves its own review cycle. Out of scope.                                                                                                            |
| Invoke `budget-analyst` at plan time                                                   | Premature — would generate content during planning, confusing the plan → work → review seam. User deferred to `/soleur:work` at plan time.                                                                    |
| Put the Workflow Gate rule in `/ship` Phase 5.5 COO gate instead of AGENTS.md           | COO gate fires on new-service signups, not on ledger-category-total shifts. Wrong trigger surface.                                                                                                            |
| Defer the roadmap sync to a follow-up PR                                               | Leaves roadmap contradicting cost-model.md on merge day. Per `wg-when-moving-github-issues-between`, roadmap is canonical — merging cost-model.md with stale roadmap creates three conflicting sources of truth. |
| Full finance-dir scaffold (revenue-model stub, burn-rate stub, break-even standalone)   | CFO-validated YAGNI; pre-revenue; stubs rot per `strategy-review-cadence-system` learning.                                                                                                                    |
