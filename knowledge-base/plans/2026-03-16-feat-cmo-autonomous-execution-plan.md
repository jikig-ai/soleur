---
title: "feat: CMO Autonomous Execution"
type: feat
date: 2026-03-16
---

# CMO Autonomous Execution

## Overview

Close four automation gaps in the CMO domain by creating four independent scheduled GitHub Actions workflows + one skill modification. Today the CMO can orchestrate strategy interactively and publish pre-scheduled content, but cannot run SEO audits, generate content, execute growth fixes, or remediate KPI misses autonomously.

## Problem Statement

Six scheduled workflows exist for reporting and publishing, but none for proactive execution. The system detects problems without acting on them. Every marketing action requires the solo founder to manually invoke skills — a context switch that delays execution and leaves the content strategy unexecuted.

## Proposed Solution

Four independent `scheduled-*.yml` workflows following the proven claude-code-action pattern, plus `--headless` support for the `content-writer` skill.

## Technical Approach

### Architecture

```
Mon 06:00  weekly-analytics (existing) ─── writes analytics snapshot + trend-summary
Mon 08:00  kpi-remediation (new) ──────── reads trend-summary → cascade if miss
Mon 10:00  seo-aeo-audit (new) ────────── /soleur:seo-aeo fix → commit to main
Tue 10:00  content-generator (new) ────── queue → content-writer → social-distribute → commit
Tue 14:00  content-publisher (existing) ── publishes distribution files
Thu 10:00  content-generator (new) ────── same pipeline
Thu 14:00  content-publisher (existing) ── publishes distribution files
Fri 10:00  growth-execution (new, biweekly) ── /soleur:growth fix → commit
```

All new workflows use `claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (v1), commit directly to main with AGENTS.md override, and follow existing patterns (concurrency groups, label pre-creation, Discord failure notifications, SHA-pinned actions).

### Key Design Decisions (from SpecFlow analysis)

| Decision | Resolution | Rationale |
|----------|-----------|-----------|
| Topic tracking | Agent updates SEO refresh queue with `generated_date: YYYY-MM-DD` per item after writing | Lowest friction; queue stays single source of truth |
| Content-writer approval gate | Add `--headless` support matching social-distribute pattern | Required for CI; auto-accept on PASS citations, abort on FAIL |
| KPI miss detection | Read `trend-summary.md` latest row Status column | No cross-workflow state needed; trend-summary is committed to main by analytics PR |
| Concurrent pushes | Per-workflow concurrency + `git pull --rebase && git push` retry | Matches competitive-analysis and community-monitor patterns |
| Publish date | Same-day (`publish_date = today`) | Full autonomy model; founder reviews via git history |
| Node.js for builds | `setup-node` + `npm ci` step before claude-code-action | Required for `npx @11ty/eleventy` in seo-aeo fix and growth fix |
| Growth fix scope in KPI remediation | Read analytics snapshot Top Pages table | Available data; no Plausible API key needed in workflow |
| Queue exhaustion fallback | Run `growth plan` then `content-writer` in same run | Full autonomy expects output every run |
| Distribution file naming | Slug-based (no numeric prefix) | Matches new social-distribute convention |
| Rollback on breakage | Internal validation (build + validate-seo.sh before push) | seo-aeo fix already does this; safer than post-merge revert |
| Issue deduplication | Date-based title + agent checks for existing open issue before creating | Prevents duplicate issues on re-runs |

### Implementation Phases

#### Phase 1: Skill Preparation (content-writer headless mode)

Add `--headless` support to `plugins/soleur/skills/content-writer/SKILL.md`:

- Detect `--headless` in `$ARGUMENTS`, set `HEADLESS_MODE=true`
- Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-select **Accept** when fact-checker returns all PASS/SOURCED, auto-**Abort** when any FAIL citation detected
- Match the established pattern in `plugins/soleur/skills/social-distribute/SKILL.md` (lines 12-14, 234, 312)

**Files to modify:**
- `plugins/soleur/skills/content-writer/SKILL.md` — add headless detection + bypass logic

**Success criteria:** `/soleur:content-writer <topic> --headless` completes without AskUserQuestion, writes article to disk.

#### Phase 2: KPI Miss Persistence (weekly analytics modification)

Modify the weekly analytics to persist KPI miss state in a format readable by the remediation workflow:

- Add `kpi_miss: true|false` field to the analytics snapshot markdown file (`knowledge-base/marketing/analytics/YYYY-MM-DD-weekly-analytics.md`)
- Add `kpi_miss: true|false` to `trend-summary.md` latest row (already has Status column — augment with explicit boolean)

**Files to modify:**
- `scripts/weekly-analytics.sh` — add `kpi_miss` to snapshot frontmatter and trend-summary row

**Success criteria:** After weekly analytics runs, `grep 'kpi_miss:' knowledge-base/marketing/analytics/$(date +%Y-%m-%d)-weekly-analytics.md` returns a value.

#### Phase 3: Workflow 1 — Scheduled SEO/AEO Audit (`scheduled-seo-aeo-audit.yml`)

Lowest complexity, no approval gate blockers. Validates the workflow pattern before building the others.

**Workflow structure:**
```yaml
name: "Scheduled: SEO/AEO Audit"
on:
  schedule:
    - cron: '0 10 * * 1'  # Monday 10:00 UTC
  workflow_dispatch: {}
concurrency:
  group: schedule-seo-aeo-audit
  cancel-in-progress: false
permissions:
  contents: write
  issues: write
  id-token: write
```

**Steps:**
1. `actions/checkout` (SHA-pinned)
2. `setup-node` + `npm ci` (for Eleventy build)
3. Pre-create `scheduled-seo-aeo-audit` label
4. `claude-code-action` with:
   - Model: `claude-sonnet-4-6`
   - Max turns: 40
   - Timeout: 30 min
   - Tools: `Bash,Read,Write,Edit,Glob,Grep`
   - Prompt: AGENTS.md override + `/soleur:seo-aeo fix` + commit instructions + issue creation
5. Discord failure notification (conditional)

**Files to create:**
- `.github/workflows/scheduled-seo-aeo-audit.yml`

**Success criteria:** `gh workflow run scheduled-seo-aeo-audit.yml` completes, commits at least one SEO fix, creates labeled issue.

#### Phase 4: Workflow 2 — Scheduled Content Generator (`scheduled-content-generator.yml`)

Most complex workflow. Depends on Phase 1 (content-writer headless).

**Workflow structure:**
```yaml
name: "Scheduled: Content Generator"
on:
  schedule:
    - cron: '0 10 * * 2,4'  # Tuesday + Thursday 10:00 UTC
  workflow_dispatch: {}
concurrency:
  group: schedule-content-generator
  cancel-in-progress: false
permissions:
  contents: write
  issues: write
  id-token: write
```

**Steps:**
1. `actions/checkout` (SHA-pinned)
2. Pre-create `scheduled-content-generator` label
3. `claude-code-action` with:
   - Model: `claude-opus-4-6`
   - Max turns: 50
   - Timeout: 45 min
   - Tools: `Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Task`
   - Prompt:
     1. AGENTS.md override
     2. Read `knowledge-base/marketing/seo-refresh-queue.md`
     3. Identify highest-priority item without a `generated_date` field
     4. If all items have `generated_date`, fall back to `/soleur:growth plan` for topic discovery
     5. Run `/soleur:content-writer <topic> --headless`
     6. Run `/soleur:social-distribute <article-path> --headless`
     7. Set `publish_date` to today, `status: scheduled` in distribution file
     8. Update SEO refresh queue: add `generated_date: YYYY-MM-DD` to the written item
     9. `git add` article + distribution file + updated queue, commit, push (with rebase retry)
     10. Create GitHub issue: `[Scheduled] Content Generator - YYYY-MM-DD`
     11. Check for existing open issue with same title before creating (dedup)
4. Discord failure notification (conditional)

**Files to create:**
- `.github/workflows/scheduled-content-generator.yml`

**Success criteria:** Manual dispatch produces an article in `plugins/soleur/docs/blog/`, a distribution file in `knowledge-base/marketing/distribution-content/`, and updates the SEO refresh queue.

#### Phase 5: Workflow 3 — Scheduled Growth Execution (`scheduled-growth-execution.yml`)

**Workflow structure:**
```yaml
name: "Scheduled: Growth Execution"
on:
  schedule:
    - cron: '0 10 1,15 * *'  # 1st and 15th of month, 10:00 UTC (biweekly)
  workflow_dispatch: {}
concurrency:
  group: schedule-growth-execution
  cancel-in-progress: false
permissions:
  contents: write
  issues: write
  id-token: write
```

**Steps:**
1. `actions/checkout` (SHA-pinned)
2. `setup-node` + `npm ci` (for build validation)
3. Pre-create `scheduled-growth-execution` label
4. `claude-code-action` with:
   - Model: `claude-sonnet-4-6`
   - Max turns: 40
   - Timeout: 30 min
   - Tools: `Bash,Read,Write,Edit,Glob,Grep,WebSearch`
   - Prompt:
     1. AGENTS.md override
     2. Read `knowledge-base/marketing/seo-refresh-queue.md`, find Priority 1 "Update immediately" items
     3. For each stale page: run `/soleur:growth fix <page-path>`
     4. Build site (`npx @11ty/eleventy`), validate (`bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`)
     5. Commit all changes, push (with rebase retry)
     6. Create GitHub issue: `[Scheduled] Growth Execution - YYYY-MM-DD`
5. Discord failure notification (conditional)

**Files to create:**
- `.github/workflows/scheduled-growth-execution.yml`

**Success criteria:** Manual dispatch applies keyword optimizations to at least one page, builds successfully, creates issue.

#### Phase 6: Workflow 4 — Scheduled KPI Remediation (`scheduled-kpi-remediation.yml`)

Depends on Phase 2 (KPI miss persistence). Most complex orchestration — cascades three actions on miss.

**Workflow structure:**
```yaml
name: "Scheduled: KPI Remediation"
on:
  schedule:
    - cron: '0 8 * * 1'  # Monday 08:00 UTC
  workflow_dispatch: {}
concurrency:
  group: schedule-kpi-remediation
  cancel-in-progress: false
permissions:
  contents: write
  issues: write
  id-token: write
```

**Steps:**
1. `actions/checkout` (SHA-pinned)
2. `setup-node` + `npm ci`
3. Pre-create `scheduled-kpi-remediation` label
4. `claude-code-action` with:
   - Model: `claude-sonnet-4-6`
   - Max turns: 60
   - Timeout: 45 min
   - Tools: `Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Task`
   - Prompt:
     1. AGENTS.md override
     2. Read `knowledge-base/marketing/analytics/trend-summary.md`
     3. Find the latest row. If Status contains "below-target" or row has `kpi_miss: true`:
        - a) Read the latest analytics snapshot for Top Pages. Run `/soleur:growth fix` on the top 3-5 page paths.
        - b) Read `seo-refresh-queue.md`, pick highest-priority unwritten item. Run `/soleur:content-writer <topic> --headless`. Run `/soleur:social-distribute <article-path> --headless`. Set `publish_date = today`.
        - c) Run `/soleur:seo-aeo fix`
        - d) Commit all changes (with rebase retry)
        - e) Create issue: `[Scheduled] KPI Remediation - YYYY-MM-DD` with details of all actions taken
     4. If no KPI miss: create issue `[Scheduled] KPI Remediation - YYYY-MM-DD: No remediation needed`
5. Discord failure notification (conditional)

**Files to create:**
- `.github/workflows/scheduled-kpi-remediation.yml`

**Success criteria:** Manual dispatch with a trend-summary showing "below-target" triggers the full cascade. Manual dispatch with "on-target" creates a no-op issue.

## Acceptance Criteria

### Functional Requirements

- [ ] SEO/AEO audit runs weekly Monday 10:00 UTC, auto-fixes technical SEO issues, commits to main
- [ ] Content generator runs Tue + Thu 10:00 UTC, produces article + distribution file, commits to main
- [ ] Growth execution runs biweekly, applies keyword optimizations to stale pages
- [ ] KPI remediation runs Mon 08:00 UTC, triggers cascade only on actual KPI miss
- [ ] Content-writer skill supports `--headless` flag (auto-accept, abort on FAIL citations)
- [ ] Distribution files have valid frontmatter (`publish_date`, `channels`, `status: scheduled`)
- [ ] Existing content-publisher auto-publishes generated distribution files
- [ ] SEO refresh queue items are marked with `generated_date` after content generation
- [ ] All workflows create labeled GitHub issues for audit trail (with dedup)
- [ ] All workflows support `workflow_dispatch` for manual testing

### Non-Functional Requirements

- [ ] All actions SHA-pinned per repo security policy
- [ ] All workflows include Discord failure notifications
- [ ] All workflows use concurrency groups (no self-overlap)
- [ ] Push operations include `git pull --rebase` retry for concurrent push conflicts
- [ ] Workflows that build Eleventy include `setup-node` + `npm ci`
- [ ] Content generator and KPI remediation include `Task` in allowedTools (for sub-agent delegation)

## Test Scenarios

### SEO/AEO Audit
- Given the docs site has JSON-LD issues, when the audit runs, then fixes are committed and an issue documents findings
- Given no SEO issues exist, when the audit runs, then validate-seo.sh passes and a "no issues found" issue is created
- Given the Eleventy build fails, when the audit runs, then no commit is made and Discord is notified

### Content Generator
- Given the SEO refresh queue has unwritten items, when the generator runs, then an article + distribution file are committed and the queue item is marked with `generated_date`
- Given all queue items have `generated_date`, when the generator runs, then it falls back to `growth plan` for topic discovery
- Given the fact-checker returns FAIL citations, when running in `--headless` mode, then the content-writer aborts and no article is committed
- Given the generator runs twice on the same day, when checking the queue, then only one article is generated (idempotency via `generated_date`)

### Growth Execution
- Given the SEO refresh queue has Priority 1 stale pages, when growth execution runs, then keyword optimizations are applied and the build validates
- Given no stale pages exist, when growth execution runs, then a "no pages to optimize" issue is created

### KPI Remediation
- Given weekly analytics detected a KPI miss (trend-summary shows "below-target"), when remediation runs, then growth fix + new article + SEO fix are all applied
- Given no KPI miss occurred, when remediation runs, then a "No remediation needed" issue is created
- Given the analytics PR has not merged yet, when remediation checks trend-summary, then it reads the last available data and defaults to "no miss"

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Content-writer headless mode produces low-quality content | Citation verification still runs; fact-checker aborts on FAIL. Post-publish review via git history. |
| Opus cost escalation (twice-weekly at 50 turns) | `max-turns` cap limits worst case. Monitor via Anthropic dashboard. |
| Weekly analytics PR not merged before KPI remediation | Remediation reads last available trend-summary data; defaults to "no miss" on missing data |
| Two workflows push to main simultaneously | Per-workflow concurrency + rebase retry. Schedule staggering (2+ hour gaps) |
| SEO fix breaks the site build | Internal validation (build + validate-seo.sh) before push. Deploy-docs workflow runs post-push. |
| Agent halts mid-pipeline (skill handoff stall) | Avoid halt language in prompts. Use explicit continuation instructions. |
| Node.js version drift on ubuntu-latest | Pin setup-node to LTS version |

## References & Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-16-cmo-autonomous-execution-brainstorm.md`
- Spec: `knowledge-base/specs/feat-cmo-autonomous-execution/spec.md`
- Issue: #638
- Existing workflow pattern: `.github/workflows/scheduled-competitive-analysis.yml`
- SEO skill: `plugins/soleur/skills/seo-aeo/SKILL.md`
- Content-writer skill: `plugins/soleur/skills/content-writer/SKILL.md`
- Social-distribute headless pattern: `plugins/soleur/skills/social-distribute/SKILL.md:12-14,234,312`
- Weekly analytics script: `scripts/weekly-analytics.sh`
- SEO refresh queue: `knowledge-base/marketing/seo-refresh-queue.md`
- Distribution content format: `knowledge-base/marketing/distribution-content/01-legal-document-generation.md`

### Institutional Learnings Applied

- Token revocation: all persistence inside agent prompt (`2026-03-02-claude-code-action-token-revocation-breaks-persist-step.md`)
- Auto-push vs PR: direct push for bot content (`2026-03-02-github-actions-auto-push-vs-pr-for-bot-content.md`)
- Headless mode convention: `--headless` for skills, `--yes` for scripts (`2026-03-03-headless-mode-skill-bypass-convention.md`)
- Pipeline continuation stalls: avoid halt language (`2026-03-03-pipeline-continuation-stalls.md`)
- Schedule template gaps: include `--allowedTools`, `--max-turns`, `id-token: write` (`2026-02-27-schedule-skill-template-gaps-first-consumer.md`)
- Multi-agent cascade checklist: `Task` in allowedTools, explicit write targets (`2026-03-02-multi-agent-cascade-orchestration-checklist.md`)
- GITHUB_OUTPUT sanitization: `tr -d '\n\r'` for untrusted values (`2026-03-05-github-output-newline-injection-sanitization.md`)
- Blog frontmatter: inherit layout from `blog.json`, don't duplicate (`2026-03-05-eleventy-blog-post-frontmatter-pattern.md`)
- Citation verification: no naked numbers (`2026-03-06-blog-citation-verification-before-publish.md`)
- Content discovery: awk frontmatter parsing pattern (`2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`)
