---
feature: strategy-review-cadence
issue: 1005
status: draft
created: 2026-03-22
---

# feat: Strategy Document Review Cadence System (#1005)

## Summary

Standardize review metadata across strategy documents, create a CI cron to detect staleness, then use the new system to drive a business validation update with cascading review of dependent documents.

## Phase 1: Frontmatter Schema Migration

**Goal:** Add standardized frontmatter to all strategy docs in product/, marketing/, sales/.

**Schema:**

```yaml
---
last_updated: YYYY-MM-DD
last_reviewed: YYYY-MM-DD
review_cadence: monthly|quarterly
owner: CPO|CMO|CRO
depends_on:
  - knowledge-base/product/business-validation.md
---
```

**Files to update (missing or partial frontmatter):**

| File | Current State | Action |
|------|--------------|--------|
| `knowledge-base/product/competitive-intelligence.md` | Has `last_reviewed` only | Add `last_updated`, `review_cadence: quarterly`, `owner: CPO`, `depends_on` |
| `knowledge-base/marketing/campaign-calendar.md` | Has `last_updated` only | Add `last_reviewed`, `review_cadence: monthly`, `owner: CMO` |
| `knowledge-base/marketing/validation-outreach-template.md` | No frontmatter | Add full schema, `review_cadence: quarterly`, `owner: CPO` |
| `knowledge-base/marketing/case-study-distribution-plan.md` | No frontmatter | Add full schema, `review_cadence: quarterly`, `owner: CMO` |
| `knowledge-base/product/business-validation.md` | Missing `owner`, `depends_on` | Add `owner: CPO` (no upstream deps — this is the root) |
| `knowledge-base/marketing/brand-guide.md` | Missing `owner`, `depends_on` | Add `owner: CMO`, `depends_on: [business-validation.md]` |
| `knowledge-base/product/roadmap.md` | Complete | Add `depends_on: business-validation.md` if missing |
| All 6 sales battlecards | Have schema but no `owner`, no `depends_on` | Add `owner: CRO` |

**Implementation:** Use Python (`scripts/backfill-frontmatter.py` exists) for safe YAML writing. Per learning: bash+awk+sed causes silent corruption on write; Python+PyYAML is safer.

**Ownership assignments:**

| Domain | Owner | Documents |
|--------|-------|-----------|
| Product | CPO | business-validation, competitive-intelligence, roadmap, pricing-strategy |
| Marketing | CMO | brand-guide, marketing-strategy, content-strategy, campaign-calendar, case-study-distribution-plan, seo-refresh-queue |
| Sales | CRO | All battlecards |

## Phase 2: Scheduled Strategy Review Workflow

**Goal:** Create `scheduled-strategy-review.yml` that detects overdue documents weekly.

**Approach:** Bash script (not claude-code-action) — staleness detection is deterministic date arithmetic, no LLM needed. Cheaper, faster, testable.

**Files to create:**

1. `scripts/strategy-review-check.sh` — Parses frontmatter, computes staleness, creates GitHub issues
2. `.github/workflows/scheduled-strategy-review.yml` — Calls the script weekly

**Script logic (`strategy-review-check.sh`):**

```
For each .md file in knowledge-base/{product,marketing,sales}/:
  1. Parse frontmatter via awk counter pattern (reuse content-publisher.sh functions)
  2. Extract review_cadence and last_reviewed
  3. Skip files without review_cadence (not opted in)
  4. Compute days since last_reviewed
  5. If overdue (monthly > 30 days, quarterly > 90 days):
     - Check for existing open issue with same title (dedup)
     - Create GitHub issue with label scheduled-strategy-review
```

**Critical learning to apply:** The overdue-document-skip bug (learning 2026-03-02). The condition must NOT skip negative `days_until` values — those are the overdue cases that matter most. Only skip documents more than N days in the future.

**Workflow structure** (follow `scheduled-competitive-analysis.yml` template):

- Cron: `'0 8 * * 1'` (Monday 08:00 UTC)
- `workflow_dispatch` for manual runs
- Concurrency group: `schedule-strategy-review`
- Permissions: `issues: write`, `contents: read`
- Label pre-creation step: `gh label create scheduled-strategy-review`
- Discord notification on failure

**No claude-code-action needed** — this is a pure bash workflow, not an agent workflow. Simpler, cheaper, and avoids the token-revocation and allowedTools gotchas.

## Phase 3: Business Validation Update

**Goal:** Record the user research finding in business-validation.md, re-assess affected gates.

**User research finding (2026-03-22):**

- Source: 5+ conversations with solo founders
- Finding: Users reject the plugin delivery mechanism
  - Plugin too limiting (want visual UI, dashboards, mobile access)
  - Don't use Claude Code (assumes a tool they don't use)
  - Want standalone product (accessible anywhere, not tied to a dev tool)

**Gate-by-gate impact (from CPO assessment):**

| Gate | Impact | Update |
|------|--------|--------|
| Problem (Gate 1) | None | Problem is delivery-mechanism-agnostic |
| Customer (Gate 2) | Medium | Beachhead "Claude Code power users" is challenged. Re-evaluate. |
| Competitive Landscape (Gate 3) | High | Shift from plugin ecosystem to cross-platform competitive set |
| Demand Evidence (Gate 4) | High | First real signal beyond dogfogging. Record prominently. Upgrades from 1-2 to 5+ conversations. |
| Business Model (Gate 5) | Medium | Native cross-platform changes cost structure significantly |
| Minimum Viable Scope (Gate 6) | High | Breadth validated, delivery vehicle challenged. MVP may not be "built." |
| Verdict | Reinforced | PIVOT now has two dimensions: validate thesis AND validate delivery format |

**Implementation:** Read the full document, apply updates to each affected gate, update `last_updated` and `last_reviewed` to 2026-03-22.

## Phase 4: Cascade Review

**Goal:** Update all documents that depend on business-validation.md.

**Dependency chain (from brainstorm):**

```
business-validation.md (UPDATED)
├── brand-guide.md → CMO reviews positioning
├── roadmap.md → CPO reviews phase structure
├── pricing-strategy.md → CPO reviews pricing framing
├── marketing-strategy.md → CMO reviews strategy alignment
├── content-strategy.md → CMO reviews content positioning
└── competitive-intelligence.md → CPO reviews competitive framing
```

**Implementation:** Spawn domain leaders in parallel via Task tool:

- `Task CPO: "Review and update roadmap.md, pricing-strategy.md, and competitive-intelligence.md in light of the business validation update (2026-03-22: plugin delivery mechanism invalidated, users want native cross-platform). Update last_reviewed and last_updated fields."`
- `Task CMO: "Review and update brand-guide.md, marketing-strategy.md, and content-strategy.md in light of the business validation update. Update last_reviewed and last_updated fields."`

Both run in parallel. Each agent reads the updated business-validation.md first, then reviews their documents.

## Implementation Order

| Step | Phase | Description | Deps |
|------|-------|-------------|------|
| 1 | Phase 1 | Add/standardize frontmatter on all strategy docs | None |
| 2 | Phase 2 | Create `scripts/strategy-review-check.sh` | Phase 1 (needs frontmatter to parse) |
| 3 | Phase 2 | Create `scheduled-strategy-review.yml` workflow | Script from step 2 |
| 4 | Phase 3 | Update business-validation.md with user research | Phase 1 (needs frontmatter fields) |
| 5 | Phase 4 | Cascade review via parallel CPO + CMO agents | Phase 3 (needs updated validation) |
| 6 | — | Commit, push, create PR | All phases complete |

## Learnings to Apply

| Learning | Application |
|----------|-------------|
| Overdue-document-skip bug | Never skip negative `days_until` in staleness checks |
| awk counter pattern | `awk '/^---$/{c++; next} c==1'` for frontmatter parsing |
| `grep \|\| true` under pipefail | All grep-in-pipeline calls need `\|\| true` |
| `var=$((var + 1))` not `((var++))` | Arithmetic under `set -euo pipefail` |
| Python for YAML write, bash for read | Use `backfill-frontmatter.py` pattern for migration |
| Heredoc indentation in Actions | Left-align heredoc content in `run:` blocks |
| `$GITHUB_OUTPUT` sanitization | Use `printf 'key=%s\n'` with `tr -d '\n\r'` |
| Label-based retry prevention | Dedup issues by checking `gh issue list` before creating |

## Acceptance Criteria

- [ ] All strategy docs in product/, marketing/, sales/ have standardized frontmatter
- [ ] `scripts/strategy-review-check.sh` correctly identifies overdue documents
- [ ] `scheduled-strategy-review.yml` runs weekly and creates issues for stale docs
- [ ] business-validation.md updated with 2026-03-22 user research finding
- [ ] All 6 dependent documents reviewed and updated via cascade
- [ ] Workflow tested via `gh workflow run` after merge
