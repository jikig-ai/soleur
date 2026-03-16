# Tasks: CMO Autonomous Execution

**Plan:** [2026-03-16-feat-cmo-autonomous-execution-plan.md](../../plans/2026-03-16-feat-cmo-autonomous-execution-plan.md)
**Issue:** #638
**Branch:** feat/cmo-autonomous-execution

## Phase 1: Skill Preparation

### 1.1 Add --headless support to content-writer skill
- [ ] Read `plugins/soleur/skills/content-writer/SKILL.md`
- [ ] Read `plugins/soleur/skills/social-distribute/SKILL.md` lines 12-14 for headless pattern reference
- [ ] Add argument parsing: detect `--headless` in `$ARGUMENTS`, set `HEADLESS_MODE=true`
- [ ] Update argument format documentation
- [ ] Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-Accept when all citations PASS/SOURCED
- [ ] Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-Abort when any citation is FAIL (create issue with failed citations)
- [ ] Verify content-writer works interactively (existing behavior unchanged)
- [ ] Verify `/soleur:content-writer <topic> --headless` completes without AskUserQuestion

## Phase 2: Analytics Modification

### 2.1 Add KPI miss persistence to weekly analytics
- [ ] Read `scripts/weekly-analytics.sh`
- [ ] Add `kpi_miss: true|false` to analytics snapshot markdown frontmatter
- [ ] Add `kpi_miss` field to trend-summary row format
- [ ] Verify `test-weekly-analytics.sh` still passes (if it exists)
- [ ] Verify weekly analytics workflow still runs correctly via `workflow_dispatch`

## Phase 3: Workflow 1 — SEO/AEO Audit

### 3.1 Create scheduled-seo-aeo-audit.yml
- [ ] Read `.github/workflows/scheduled-competitive-analysis.yml` for template reference
- [ ] Create `.github/workflows/scheduled-seo-aeo-audit.yml`
  - [ ] Cron: `0 10 * * 1` (Monday 10:00 UTC)
  - [ ] Concurrency: `schedule-seo-aeo-audit`
  - [ ] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [ ] Step 1: `actions/checkout` (SHA-pinned)
  - [ ] Step 2: `setup-node` + `npm ci`
  - [ ] Step 3: Pre-create label `scheduled-seo-aeo-audit`
  - [ ] Step 4: `claude-code-action` — model `claude-sonnet-4-6`, max-turns 40, timeout 30min
    - [ ] Prompt includes AGENTS.md override text
    - [ ] Prompt invokes `/soleur:seo-aeo fix`
    - [ ] Prompt includes git add/commit/push with rebase retry
    - [ ] Prompt includes issue creation with dedup check
  - [ ] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-seo-aeo-audit.yml`

## Phase 4: Workflow 2 — Content Generator

### 4.1 Create scheduled-content-generator.yml
- [ ] Create `.github/workflows/scheduled-content-generator.yml`
  - [ ] Cron: `0 10 * * 2,4` (Tuesday + Thursday 10:00 UTC)
  - [ ] Concurrency: `schedule-content-generator`
  - [ ] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [ ] Step 1: `actions/checkout` (SHA-pinned)
  - [ ] Step 2: Pre-create label `scheduled-content-generator`
  - [ ] Step 3: `claude-code-action` — model `claude-opus-4-6`, max-turns 50, timeout 45min
    - [ ] Prompt includes AGENTS.md override text
    - [ ] Prompt: read SEO refresh queue, identify unwritten item (no `generated_date`)
    - [ ] Prompt: fallback to `/soleur:growth plan` if all items written
    - [ ] Prompt: invoke `/soleur:content-writer <topic> --headless`
    - [ ] Prompt: invoke `/soleur:social-distribute <article-path> --headless`
    - [ ] Prompt: set `publish_date = today`, `status: scheduled` in distribution file
    - [ ] Prompt: update queue item with `generated_date: YYYY-MM-DD`
    - [ ] Prompt: git add/commit/push with rebase retry
    - [ ] Prompt: create issue with dedup check
    - [ ] AllowedTools includes `Task` (for sub-agent delegation in skills)
  - [ ] Step 4: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-content-generator.yml`

## Phase 5: Workflow 3 — Growth Execution

### 5.1 Create scheduled-growth-execution.yml
- [ ] Create `.github/workflows/scheduled-growth-execution.yml`
  - [ ] Cron: `0 10 1,15 * *` (1st and 15th, 10:00 UTC)
  - [ ] Concurrency: `schedule-growth-execution`
  - [ ] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [ ] Step 1: `actions/checkout` (SHA-pinned)
  - [ ] Step 2: `setup-node` + `npm ci`
  - [ ] Step 3: Pre-create label `scheduled-growth-execution`
  - [ ] Step 4: `claude-code-action` — model `claude-sonnet-4-6`, max-turns 40, timeout 30min
    - [ ] Prompt includes AGENTS.md override text
    - [ ] Prompt: read SEO refresh queue Priority 1 items
    - [ ] Prompt: run `/soleur:growth fix <page-path>` on each stale page
    - [ ] Prompt: build + validate before pushing
    - [ ] Prompt: git add/commit/push with rebase retry
    - [ ] Prompt: create issue with dedup check
  - [ ] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-growth-execution.yml`

## Phase 6: Workflow 4 — KPI Remediation

### 6.1 Create scheduled-kpi-remediation.yml
- [ ] Create `.github/workflows/scheduled-kpi-remediation.yml`
  - [ ] Cron: `0 8 * * 1` (Monday 08:00 UTC)
  - [ ] Concurrency: `schedule-kpi-remediation`
  - [ ] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [ ] Step 1: `actions/checkout` (SHA-pinned)
  - [ ] Step 2: `setup-node` + `npm ci`
  - [ ] Step 3: Pre-create label `scheduled-kpi-remediation`
  - [ ] Step 4: `claude-code-action` — model `claude-sonnet-4-6`, max-turns 60, timeout 45min
    - [ ] Prompt includes AGENTS.md override text
    - [ ] Prompt: read `knowledge-base/marketing/analytics/trend-summary.md`
    - [ ] Prompt: check latest row for KPI miss (Status "below-target" or `kpi_miss: true`)
    - [ ] Prompt: if miss — cascade: growth fix on top pages + content-writer + seo-aeo fix
    - [ ] Prompt: if no miss — create "No remediation needed" issue
    - [ ] Prompt: git add/commit/push with rebase retry
    - [ ] Prompt: create comprehensive issue with all actions taken
    - [ ] AllowedTools includes `Task` and `WebSearch,WebFetch`
  - [ ] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-kpi-remediation.yml`

## Phase 7: Validation & Ship

### 7.1 End-to-end validation
- [ ] Trigger SEO/AEO audit via workflow_dispatch, verify issue created
- [ ] Trigger content generator via workflow_dispatch, verify article + distribution file committed
- [ ] Verify content-publisher picks up the generated distribution file (next 14:00 UTC run)
- [ ] Trigger growth execution via workflow_dispatch, verify keyword fixes committed
- [ ] Trigger KPI remediation via workflow_dispatch with a trend-summary showing "below-target"
- [ ] Trigger KPI remediation via workflow_dispatch with a trend-summary showing "on-target"

### 7.2 Ship
- [ ] Run `/soleur:compound` to capture learnings
- [ ] Run `/soleur:ship` to create PR with semver label
