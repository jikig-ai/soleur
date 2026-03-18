# Spec: CMO Autonomous Execution

**Status:** Draft
**Branch:** feat/cmo-autonomous-execution
**Brainstorm:** [2026-03-16-cmo-autonomous-execution-brainstorm.md](../../brainstorms/2026-03-16-cmo-autonomous-execution-brainstorm.md)

## Problem Statement

The CMO domain has mature skills and agents for marketing execution, but they require manual invocation. Six scheduled workflows exist for reporting and publishing, but none for proactive execution. The system detects problems (KPI misses, SEO degradation) without acting on them.

## Goals

- **G1:** Automated weekly SEO/AEO technical audits with auto-fix on the docs site
- **G2:** Autonomous content generation from the SEO refresh queue, twice weekly
- **G3:** Scheduled growth strategy execution (keyword optimization) biweekly
- **G4:** Automatic remediation when weekly analytics detects KPI misses
- **G5:** Full end-to-end content pipeline: generate article → create distribution file → auto-publish via existing content-publisher

## Non-Goals

- Unified CMO orchestrator workflow (deferred — independent workflows first)
- Event-driven cascading between workflows (deferred — layer on once individual workflows prove reliable)
- Email/newsletter automation (no infrastructure exists)
- Pricing model automation (requires founder decision)
- Automated social media engagement/replies (out of scope)

## Functional Requirements

- **FR1:** `scheduled-seo-aeo-audit.yml` runs weekly Monday 10:00 UTC, invokes `/soleur:seo-aeo fix`, commits fixes to main, creates GitHub issue with findings
- **FR2:** `scheduled-content-generator.yml` runs Tue + Thu 10:00 UTC, reads SEO refresh queue for highest-priority unwritten topic, generates article via content-writer (Opus model), generates distribution content file via social-distribute, commits both to main
- **FR3:** `scheduled-growth-execution.yml` runs biweekly Friday 10:00 UTC, runs `growth fix` on pages from SEO refresh queue, commits keyword optimizations to main
- **FR4:** `scheduled-kpi-remediation.yml` runs Monday 08:00 UTC, checks for KPI miss from weekly analytics, if miss detected: runs growth fix on top pages + generates new article + runs seo-aeo fix
- **FR5:** Content generator sets `publish_date` and `status: scheduled` in distribution files so the existing content-publisher workflow auto-publishes
- **FR6:** All workflows create GitHub issues documenting actions taken, with `scheduled-*` labels for audit trail
- **FR7:** All workflows include Discord failure notifications following existing pattern
- **FR8:** All workflows support `workflow_dispatch` for manual testing
- **FR9:** Content generator falls back to `growth plan` for topic discovery when SEO refresh queue is exhausted

## Technical Requirements

- **TR1:** Follow existing `scheduled-*.yml` workflow patterns (concurrency groups, label pre-creation, AGENTS.md override, SHA-pinned actions)
- **TR2:** Use claude-code-action@v1 (SHA `64c7a0ef71df67b14cb4471f4d9c8565c61042bf`)
- **TR3:** Content generator uses Opus model; all others use Sonnet
- **TR4:** All workflows commit directly to main with explicit AGENTS.md override in prompt
- **TR5:** Respect existing cron spacing (no two workflows within 15 minutes of each other)
- **TR6:** KPI remediation must detect miss from weekly analytics output (read latest issue or analytics artifact)
- **TR7:** Content generator must read brand guide for voice alignment (built into content-writer skill)
- **TR8:** All workflows must be idempotent (re-runs don't produce duplicate content or double-fix)

## Acceptance Criteria

- [ ] SEO/AEO audit runs weekly and commits at least one fix cycle (verified via workflow run history)
- [ ] Content generator produces a publishable article with correct Eleventy frontmatter and JSON-LD schema
- [ ] Distribution content file is auto-generated with valid frontmatter (publish_date, channels, status: scheduled)
- [ ] Growth execution improves keyword presence on targeted pages (verified via before/after diff)
- [ ] KPI remediation triggers only on actual KPI miss (verified by checking weekly analytics state)
- [ ] All workflows create properly labeled GitHub issues
- [ ] All workflows can be triggered manually via `workflow_dispatch`
- [ ] Content publisher successfully publishes auto-generated distribution files on schedule
