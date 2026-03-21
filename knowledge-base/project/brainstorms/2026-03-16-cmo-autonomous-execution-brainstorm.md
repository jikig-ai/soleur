# CMO Autonomous Execution — Brainstorm

**Date:** 2026-03-16
**Status:** Complete
**Participants:** Founder, Claude

## What We're Building

Four independent scheduled GitHub Actions workflows that close the CMO's execution automation gaps. Today the CMO can orchestrate strategy interactively and the system can publish pre-scheduled content, but it cannot:

1. Run SEO/AEO audits on a schedule
2. Autonomously generate new content from the content strategy
3. Execute growth strategy actions (keyword fixes, gap analysis) without being invoked
4. Self-remediate when weekly analytics detects a KPI miss

## Why This Approach

**Independent workflows over unified orchestrator.** Each workflow follows the proven `scheduled-*.yml` pattern already battle-tested in this repo (daily-triage, bug-fixer, content-publisher, community-monitor, competitive-analysis). Independent workflows are:

- Independently testable via `workflow_dispatch`
- Failure-isolated (one failing doesn't block others)
- Incrementally deployable (ship one at a time)
- Debuggable (single-purpose logs)

Cascading (Approach 3 — event-driven pipeline) can be layered on top once the individual pieces prove reliable.

**Full autonomy model.** The founder chose full autonomy: agents auto-fix, auto-generate, and auto-commit to main. Human reviews via git history and GitHub issues after the fact. This matches the solo-founder constraint where every manual approval step is a context switch that delays execution.

## Key Decisions

### 1. Scheduled SEO/AEO Audit + Fix (`scheduled-seo-aeo-audit.yml`)

| Attribute | Decision |
|-----------|----------|
| **Schedule** | Weekly, Monday 10:00 UTC |
| **Mode** | Fix mode — auto-apply fixes and commit to main |
| **Skill** | `/soleur:seo-aeo fix` |
| **Model** | Sonnet (technical audit doesn't need creative reasoning) |
| **Output** | Commit fixes to main + GitHub issue documenting findings and fixes |
| **Timeout** | 30 minutes |
| **Max turns** | 40 |
| **Tools** | Bash, Read, Write, Edit, Glob, Grep |

**What it fixes autonomously:**

- JSON-LD validity and @type correctness
- Meta tags (canonical, OG, Twitter cards, descriptions)
- AI discoverability (llms.txt, robots.txt AI crawler rules)
- E-E-A-T signals (author attribution, dates)
- Sitemap completeness
- Heading hierarchy and descriptive link text

**Post-fix:** Runs `npx @11ty/eleventy` to build, then `scripts/validate-seo.sh _site` to validate.

### 2. Autonomous Content Generator (`scheduled-content-generator.yml`)

| Attribute | Decision |
|-----------|----------|
| **Schedule** | Twice weekly: Tuesday 10:00 UTC + Thursday 10:00 UTC |
| **Topic source** | SEO refresh queue (`knowledge-base/marketing/seo-refresh-queue.md`) — highest priority unwritten item |
| **Model** | Opus (creative writing + brand voice alignment requires best model) |
| **Skill chain** | Read queue → `/soleur:content-writer` → `/soleur:social-distribute` |
| **Output** | Article committed to main + distribution content file with next available publish_date |
| **Timeout** | 45 minutes |
| **Max turns** | 50 |
| **Tools** | Bash, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Task |

**Full pipeline per run:**

1. Read `seo-refresh-queue.md`, identify highest-priority item not yet written
2. Run `content-writer` with topic, reading brand guide for voice alignment
3. Fact-check via fact-checker agent (built into content-writer Phase 2.5)
4. Generate distribution content file (Discord + X/Twitter variants) via `social-distribute`
5. Set `publish_date` to next available Tue/Thu, `status: scheduled`
6. Commit article + distribution file to main
7. Create GitHub issue documenting what was generated

**Topic exhaustion:** If all items in SEO refresh queue are written, fall back to `growth plan` to discover new keyword opportunities and generate from those.

### 3. Scheduled Growth Execution (`scheduled-growth-execution.yml`)

| Attribute | Decision |
|-----------|----------|
| **Schedule** | Biweekly, Friday 10:00 UTC |
| **Skill** | `/soleur:growth fix` on pages from SEO refresh queue |
| **Model** | Sonnet |
| **Output** | Keyword-optimized pages committed to main + issue with changes |
| **Timeout** | 30 minutes |
| **Max turns** | 40 |
| **Tools** | Bash, Read, Write, Edit, Glob, Grep, WebSearch |

**What it does:**

- Reads SEO refresh queue for "Update immediately" items
- Runs `growth fix` on each page (keyword injection, meta description rewrite, FAQ addition)
- Validates changes against brand guide voice
- Builds site and validates with `validate-seo.sh`
- Commits fixes to main

### 4. KPI Miss Remediation (`scheduled-kpi-remediation.yml`)

| Attribute | Decision |
|-----------|----------|
| **Schedule** | Monday 08:00 UTC (2 hours after weekly analytics at 06:00) |
| **Trigger condition** | Only acts if weekly analytics detected a KPI miss |
| **Action on miss** | Full remediation sweep: growth fix + new article + SEO fix |
| **Model** | Sonnet for growth/SEO fix, Opus for content generation |
| **Output** | All fixes committed to main + comprehensive remediation issue |
| **Timeout** | 45 minutes |
| **Max turns** | 60 |
| **Tools** | Bash, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Task |

**Remediation cascade (on KPI miss):**

1. Run `growth fix` on the 3-5 highest-traffic pages (improve existing content)
2. Generate a new article targeting the weakest content gap (drive new traffic)
3. Run `seo-aeo fix` on all docs pages (technical SEO sweep)
4. Create comprehensive GitHub issue: "KPI Remediation — Week of YYYY-MM-DD"

**KPI miss detection:** Read the latest `knowledge-base/community/` or check for issues with `scheduled-weekly-analytics` label from the current week. If `kpi_miss=true` in the weekly analytics output, trigger the cascade.

**No-miss behavior:** If no KPI miss, skip all actions and create a brief "No remediation needed" issue for audit trail.

## Schedule Overview

| Day | Time (UTC) | Workflow | Notes |
|-----|-----------|----------|-------|
| Mon | 06:00 | Weekly Analytics (existing) | Detects KPI miss |
| Mon | 08:00 | **KPI Remediation (new)** | Acts on miss |
| Mon | 10:00 | **SEO/AEO Audit + Fix (new)** | Weekly technical SEO |
| Tue | 10:00 | **Content Generator (new)** | Article #1 of the week |
| Tue | 14:00 | Content Publisher (existing) | Publishes scheduled content |
| Thu | 10:00 | **Content Generator (new)** | Article #2 of the week |
| Thu | 14:00 | Content Publisher (existing) | Publishes scheduled content |
| Fri | 10:00 | **Growth Execution (new, biweekly)** | Keyword optimization |

## Open Questions

1. **Topic tracking:** How does the content generator mark an SEO refresh queue item as "written"? Proposal: add a `status: written` field or `generated_date` to each item in the queue file.
2. **Content quality gate:** With full autonomy, there's no pre-publish review. Should we add a post-publish audit that checks the generated article against brand guide compliance and creates an issue if violations are found?
3. **Cost monitoring:** Opus runs twice weekly will cost more than all other scheduled workflows combined. Should we add a monthly cost tracking mechanism?
4. **Distribution timing:** Content is generated Tue/Thu at 10:00, but the publisher runs at 14:00. If the generator sets `publish_date = today`, the article publishes same day. If it sets `publish_date = next Tue/Thu`, there's a 2-7 day delay. Which is preferred?
5. **Retry logic:** Weekly analytics failed today (07:10 UTC, re-ran manually at 09:04). Should the new workflows include retry logic (re-run on failure after 30 min)?
