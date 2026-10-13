---
title: "feat: CMO Autonomous Execution"
type: feat
date: 2026-03-16
---

# CMO Autonomous Execution

[Updated 2026-03-16 — applied review feedback: eliminated Phase 2 + Phase 6, dropped queue exhaustion fallback, dropped issue dedup, switched to Sonnet, added build validation to content generator, reframed as delivery batches]

## Overview

Close three automation gaps in the CMO domain by creating three scheduled GitHub Actions workflows + one skill modification. Today the CMO can orchestrate strategy interactively and publish pre-scheduled content, but cannot run SEO audits, generate content, or execute growth fixes autonomously.

## Problem Statement

Six scheduled workflows exist for reporting and publishing, but none for proactive execution. The system detects problems without acting on them. Every marketing action requires the solo founder to manually invoke skills — a context switch that delays execution and leaves the content strategy unexecuted.

## Proposed Solution

Three independent `scheduled-*.yml` workflows following the proven claude-code-action pattern, plus `--headless` support for the `content-writer` skill. KPI miss remediation deferred — the existing weekly analytics Discord notification is sufficient for the founder to manually trigger the standalone workflows when needed.

## Technical Approach

### Architecture

```
Mon 06:00  weekly-analytics (existing) ─── detects KPI miss, Discord alert
Mon 10:00  seo-aeo-audit (new) ────────── /soleur:seo-aeo fix → commit to main
Tue 10:00  content-generator (new) ────── queue → content-writer → social-distribute → commit
Tue 14:00  content-publisher (existing) ── publishes distribution files
Thu 10:00  content-generator (new) ────── same pipeline
Thu 14:00  content-publisher (existing) ── publishes distribution files
Fri 10:00  growth-execution (new, biweekly) ── /soleur:growth fix → commit
```

All new workflows use `claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (v1), commit directly to main with AGENTS.md override, and follow existing patterns (concurrency groups, label pre-creation, Discord failure notifications, SHA-pinned actions).

### Key Design Decisions

| Decision | Resolution | Rationale |
|----------|-----------|-----------|
| Topic tracking | Agent updates SEO refresh queue with `generated_date: YYYY-MM-DD` per item after writing | Lowest friction; queue stays single source of truth |
| Content-writer approval gate | Add `--headless` support matching social-distribute pattern | Required for CI; auto-accept on PASS citations, abort on FAIL |
| KPI miss response | Deferred — rely on existing Discord alert for manual triage | All three reviewers agreed: a 60-turn cascade re-implementing the other workflows is overengineered. The founder can manually dispatch the standalone workflows on miss. |
| Concurrent pushes | Per-workflow concurrency + `git pull --rebase && git push` retry | Matches competitive-analysis and community-monitor patterns |
| Publish date | Same-day (`publish_date = today`) | Full autonomy model; founder reviews via git history |
| Node.js for builds | `setup-node` + `npm ci` step before claude-code-action | Required for `npx @11ty/eleventy` in seo-aeo fix, growth fix, and content generator |
| Content generator model | Sonnet (not Opus) | Brand guide + fact-checker provide quality guardrails. Upgrade if quality is measurably lacking. |
| Queue exhaustion | Create issue "SEO refresh queue exhausted — add more topics" and exit | 19+ items = 10+ weeks at 2/week. Build the `growth plan` fallback when the queue is actually running low. |
| Distribution file naming | Slug-based (no numeric prefix) | Matches current social-distribute convention |
| Rollback on breakage | Internal validation (build + validate-seo.sh before push) | seo-aeo fix already does this; content generator must also validate |

### Implementation Batches

#### Batch 1: SEO/AEO Audit + Growth Execution (zero prerequisites)

Ship immediately — these workflows invoke skills that already run autonomously (no approval gates).

##### 1a. Scheduled SEO/AEO Audit (`scheduled-seo-aeo-audit.yml`)

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

**Success criteria:** `gh workflow run scheduled-seo-aeo-audit.yml` completes, commits SEO fixes (or validates no issues), creates labeled issue.

##### 1b. Scheduled Growth Execution (`scheduled-growth-execution.yml`)

```yaml
name: "Scheduled: Growth Execution"
on:
  schedule:
    - cron: '0 10 1,15 * *'  # 1st and 15th of month, 10:00 UTC
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

#### Batch 2: Content-Writer Headless + Content Generator (depends on Batch 1 for pattern validation)

##### 2a. Content-Writer Headless Mode

Add `--headless` support to `plugins/soleur/skills/content-writer/SKILL.md`:

- Detect `--headless` in `$ARGUMENTS`, set `HEADLESS_MODE=true`
- Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-select **Accept** when fact-checker returns all PASS/SOURCED, auto-**Abort** when any FAIL citation detected
- Match the established pattern in `plugins/soleur/skills/social-distribute/SKILL.md` (lines 12-14, 234, 312)

**Files to modify:**

- `plugins/soleur/skills/content-writer/SKILL.md` — add headless detection + bypass logic

**Success criteria:** `/soleur:content-writer <topic> --headless` completes without AskUserQuestion, writes article to disk.

##### 2b. Scheduled Content Generator (`scheduled-content-generator.yml`)

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
2. `setup-node` + `npm ci` (for Eleventy build validation)
3. Pre-create `scheduled-content-generator` label
4. `claude-code-action` with:
   - Model: `claude-sonnet-4-6`
   - Max turns: 40
   - Timeout: 45 min
   - Tools: `Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Task`
   - Prompt:
     1. AGENTS.md override
     2. Read `knowledge-base/marketing/seo-refresh-queue.md`
     3. Identify highest-priority item without a `generated_date` field
     4. If all items have `generated_date`, create an issue "SEO refresh queue exhausted — add more topics" and exit
     5. Run `/soleur:content-writer <topic> --headless`
     6. Run `/soleur:social-distribute <article-path> --headless`
     7. Set `publish_date` to today, `status: scheduled`, `channels: discord, x` in distribution file
     8. Build site (`npx @11ty/eleventy`) to validate the new article renders correctly
     9. Update SEO refresh queue: add `generated_date: YYYY-MM-DD` to the written item
     10. `git add` article + distribution file + updated queue, commit, push (with rebase retry)
     11. Create GitHub issue: `[Scheduled] Content Generator - YYYY-MM-DD`
4. Discord failure notification (conditional)

**Files to create:**

- `.github/workflows/scheduled-content-generator.yml`

**Success criteria:** Manual dispatch produces an article in `plugins/soleur/docs/blog/`, a distribution file in `knowledge-base/marketing/distribution-content/`, updates the SEO refresh queue, and the Eleventy build succeeds.

#### Batch 3: KPI Remediation Dispatcher (optional, deferred)

Add a lightweight `gh workflow run` dispatcher to the existing `scheduled-weekly-analytics.yml`. When `kpi_miss=true`, dispatch the three standalone workflows. No claude-code-action needed — just 5 lines of shell.

This is explicitly deferred from this PR. Track as a follow-up issue.

## Acceptance Criteria

### Functional Requirements

- [ ] SEO/AEO audit runs weekly Monday 10:00 UTC, auto-fixes technical SEO issues, commits to main
- [ ] Content generator runs Tue + Thu 10:00 UTC, produces article + distribution file, commits to main
- [ ] Growth execution runs biweekly, applies keyword optimizations to stale pages
- [ ] Content-writer skill supports `--headless` flag (auto-accept, abort on FAIL citations)
- [ ] Distribution files have valid frontmatter (`publish_date`, `channels`, `status: scheduled`)
- [ ] Existing content-publisher auto-publishes generated distribution files
- [ ] SEO refresh queue items are marked with `generated_date` after content generation
- [ ] Content generator validates Eleventy build before pushing
- [ ] All workflows create labeled GitHub issues for audit trail
- [ ] All workflows support `workflow_dispatch` for manual testing

### Non-Functional Requirements

- [ ] All actions SHA-pinned per repo security policy
- [ ] All workflows include Discord failure notifications
- [ ] All workflows use concurrency groups (no self-overlap)
- [ ] Push operations include `git pull --rebase` retry
- [ ] All workflows include `setup-node` + `npm ci` for Eleventy builds
- [ ] Content generator includes `Task` in allowedTools (for sub-agent delegation)

## Test Scenarios

### SEO/AEO Audit

- Given the docs site has JSON-LD issues, when the audit runs, then fixes are committed and an issue documents findings
- Given no SEO issues exist, when the audit runs, then validate-seo.sh passes and a "no issues found" issue is created
- Given the Eleventy build fails after fixes, when the audit runs, then no commit is made and Discord is notified

### Content Generator

- Given the SEO refresh queue has unwritten items, when the generator runs, then an article + distribution file are committed and the queue item is marked with `generated_date`
- Given all queue items have `generated_date`, when the generator runs, then an "SEO refresh queue exhausted" issue is created and no article is generated
- Given the fact-checker returns FAIL citations, when running in `--headless` mode, then the content-writer aborts and no article is committed
- Given the Eleventy build fails with the new article, when the generator runs, then no commit is made and Discord is notified

### Growth Execution

- Given the SEO refresh queue has Priority 1 stale pages, when growth execution runs, then keyword optimizations are applied and the build validates
- Given no stale pages exist, when growth execution runs, then a "no pages to optimize" issue is created

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Content-writer headless mode produces low-quality content | Citation verification still runs; fact-checker aborts on FAIL. Post-publish review via git history. |
| SEO fix or content generation breaks the site build | Internal validation (build + validate-seo.sh) before push in all three workflows |
| Two workflows push to main simultaneously | Per-workflow concurrency + rebase retry. Schedule staggering (2+ hour gaps) |
| Agent halts mid-pipeline (skill handoff stall) | Avoid halt language in prompts. Use explicit continuation instructions. |
| Node.js version drift on ubuntu-latest | Pin setup-node to LTS version |
| Content quality degrades with Sonnet | Monitor first few articles. Upgrade to Opus if quality drops. Brand guide + fact-checker are model-independent guardrails. |

## Deferred Work

- **KPI remediation dispatcher** — Add `gh workflow run` dispatch to weekly-analytics for automated response to KPI misses. Track as separate issue.
- **Queue exhaustion fallback** — Add `growth plan` topic discovery when SEO refresh queue runs dry (~10+ weeks away). Track as separate issue.
- **Cost monitoring** — Monthly Opus/Sonnet usage tracking. Not needed at Sonnet pricing.

## References & Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-03-16-cmo-autonomous-execution-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cmo-autonomous-execution/spec.md`
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
- Blog frontmatter: inherit layout from `blog.json`, don't duplicate (`2026-03-05-eleventy-blog-post-frontmatter-pattern.md`)
- Citation verification: no naked numbers (`2026-03-06-blog-citation-verification-before-publish.md`)
- Content discovery: awk frontmatter parsing pattern (`2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`)
