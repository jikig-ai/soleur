# Tasks: CMO Autonomous Execution

**Plan:** [2026-03-16-feat-cmo-autonomous-execution-plan.md](../../plans/2026-03-16-feat-cmo-autonomous-execution-plan.md)
**Issue:** #638
**Branch:** feat/cmo-autonomous-execution

## Batch 1: SEO/AEO Audit + Growth Execution (zero prerequisites)

### 1.1 Create scheduled-seo-aeo-audit.yml
- [x] Read `.github/workflows/scheduled-competitive-analysis.yml` for template reference
- [x] Create `.github/workflows/scheduled-seo-aeo-audit.yml`
  - [x] Cron: `0 10 * * 1` (Monday 10:00 UTC)
  - [x] Concurrency: `schedule-seo-aeo-audit`
  - [x] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [x] Step 1: `actions/checkout` (SHA-pinned)
  - [x] Step 2: `setup-node` + `npm ci`
  - [x] Step 3: Pre-create label `scheduled-seo-aeo-audit`
  - [x] Step 4: `claude-code-action` — model `claude-sonnet-4-6`, max-turns 40, timeout 30min
    - [x] Prompt includes AGENTS.md override text
    - [x] Prompt invokes `/soleur:seo-aeo fix`
    - [x] Prompt includes git add/commit/push with rebase retry
    - [x] Prompt includes issue creation
    - [x] AllowedTools: `Bash,Read,Write,Edit,Glob,Grep`
  - [x] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-seo-aeo-audit.yml`

### 1.2 Create scheduled-growth-execution.yml
- [x] Create `.github/workflows/scheduled-growth-execution.yml`
  - [x] Cron: `0 10 1,15 * *` (1st and 15th, 10:00 UTC)
  - [x] Concurrency: `schedule-growth-execution`
  - [x] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [x] Step 1: `actions/checkout` (SHA-pinned)
  - [x] Step 2: `setup-node` + `npm ci`
  - [x] Step 3: Pre-create label `scheduled-growth-execution`
  - [x] Step 4: `claude-code-action` — model `claude-sonnet-4-6`, max-turns 40, timeout 30min
    - [x] Prompt includes AGENTS.md override text
    - [x] Prompt: read SEO refresh queue Priority 1 items
    - [x] Prompt: run `/soleur:growth fix <page-path>` on each stale page
    - [x] Prompt: build + validate before pushing
    - [x] Prompt: git add/commit/push with rebase retry
    - [x] Prompt: create issue
    - [x] AllowedTools: `Bash,Read,Write,Edit,Glob,Grep,WebSearch`
  - [x] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-growth-execution.yml`

## Batch 2: Content-Writer Headless + Content Generator

### 2.1 Add --headless support to content-writer skill
- [x] Read `plugins/soleur/skills/content-writer/SKILL.md`
- [x] Read `plugins/soleur/skills/social-distribute/SKILL.md` lines 12-14 for headless pattern reference
- [x] Add argument parsing: detect `--headless` in `$ARGUMENTS`, set `HEADLESS_MODE=true`
- [x] Update argument format documentation
- [x] Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-Accept when all citations PASS/SOURCED
- [x] Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-Abort when any citation is FAIL (create issue with failed citations)

### 2.2 Create scheduled-content-generator.yml
- [x] Create `.github/workflows/scheduled-content-generator.yml`
  - [x] Cron: `0 10 * * 2,4` (Tuesday + Thursday 10:00 UTC)
  - [x] Concurrency: `schedule-content-generator`
  - [x] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [x] Step 1: `actions/checkout` (SHA-pinned)
  - [x] Step 2: `setup-node` + `npm ci`
  - [x] Step 3: Pre-create label `scheduled-content-generator`
  - [x] Step 4: `claude-code-action` — model `claude-sonnet-4-6`, max-turns 40, timeout 45min
    - [x] Prompt includes AGENTS.md override text
    - [x] Prompt: read SEO refresh queue, identify unwritten item (no `generated_date`)
    - [x] Prompt: if all items written, create "queue exhausted" issue and exit
    - [x] Prompt: invoke `/soleur:content-writer <topic> --headless`
    - [x] Prompt: invoke `/soleur:social-distribute <article-path> --headless`
    - [x] Prompt: set `publish_date = today`, `status: scheduled` in distribution file
    - [x] Prompt: build site (`npx @11ty/eleventy`) to validate article
    - [x] Prompt: update queue item with `generated_date: YYYY-MM-DD`
    - [x] Prompt: git add/commit/push with rebase retry
    - [x] Prompt: create issue
    - [x] AllowedTools includes `Task` (for sub-agent delegation in skills)
  - [x] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-content-generator.yml`

## Batch 3: Validation & Ship

### 3.1 End-to-end validation
- [ ] Trigger SEO/AEO audit via workflow_dispatch, verify issue created
- [ ] Trigger content generator via workflow_dispatch, verify article + distribution file committed
- [ ] Verify content-publisher picks up the generated distribution file (next 14:00 UTC run)
- [ ] Trigger growth execution via workflow_dispatch, verify keyword fixes committed

### 3.2 Deferred work — create follow-up issues
- [x] Create issue: "feat: KPI remediation dispatcher — auto-trigger workflows on miss" (#640)
- [x] Create issue: "feat: Content generator queue exhaustion fallback via growth plan" (#641)

### 3.3 Ship
- [ ] Run `/soleur:compound` to capture learnings
- [ ] Run `/soleur:ship` to create PR with semver label
