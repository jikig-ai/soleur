# Tasks: CMO Autonomous Execution

**Plan:** [2026-03-16-feat-cmo-autonomous-execution-plan.md](../../plans/2026-03-16-feat-cmo-autonomous-execution-plan.md)
**Issue:** #638
**Branch:** feat/cmo-autonomous-execution

## Batch 1: SEO/AEO Audit + Growth Execution (zero prerequisites)

### 1.1 Create scheduled-seo-aeo-audit.yml
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
    - [ ] Prompt includes issue creation
    - [ ] AllowedTools: `Bash,Read,Write,Edit,Glob,Grep`
  - [ ] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-seo-aeo-audit.yml`

### 1.2 Create scheduled-growth-execution.yml
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
    - [ ] Prompt: create issue
    - [ ] AllowedTools: `Bash,Read,Write,Edit,Glob,Grep,WebSearch`
  - [ ] Step 5: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-growth-execution.yml`

## Batch 2: Content-Writer Headless + Content Generator

### 2.1 Add --headless support to content-writer skill
- [ ] Read `plugins/soleur/skills/content-writer/SKILL.md`
- [ ] Read `plugins/soleur/skills/social-distribute/SKILL.md` lines 12-14 for headless pattern reference
- [ ] Add argument parsing: detect `--headless` in `$ARGUMENTS`, set `HEADLESS_MODE=true`
- [ ] Update argument format documentation
- [ ] Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-Accept when all citations PASS/SOURCED
- [ ] Phase 3 approval gate: if `HEADLESS_MODE=true`, auto-Abort when any citation is FAIL (create issue with failed citations)

### 2.2 Create scheduled-content-generator.yml
- [ ] Create `.github/workflows/scheduled-content-generator.yml`
  - [ ] Cron: `0 10 * * 2,4` (Tuesday + Thursday 10:00 UTC)
  - [ ] Concurrency: `schedule-content-generator`
  - [ ] Permissions: `contents: write`, `issues: write`, `id-token: write`
  - [ ] Step 1: `actions/checkout` (SHA-pinned)
  - [ ] Step 2: `setup-node` + `npm ci`
  - [ ] Step 3: Pre-create label `scheduled-content-generator`
  - [ ] Step 4: `claude-code-action` — model `claude-sonnet-4-6`, max-turns 40, timeout 45min
    - [ ] Prompt includes AGENTS.md override text
    - [ ] Prompt: read SEO refresh queue, identify unwritten item (no `generated_date`)
    - [ ] Prompt: if all items written, create "queue exhausted" issue and exit
    - [ ] Prompt: invoke `/soleur:content-writer <topic> --headless`
    - [ ] Prompt: invoke `/soleur:social-distribute <article-path> --headless`
    - [ ] Prompt: set `publish_date = today`, `status: scheduled` in distribution file
    - [ ] Prompt: build site (`npx @11ty/eleventy`) to validate article
    - [ ] Prompt: update queue item with `generated_date: YYYY-MM-DD`
    - [ ] Prompt: git add/commit/push with rebase retry
    - [ ] Prompt: create issue
    - [ ] AllowedTools includes `Task` (for sub-agent delegation in skills)
  - [ ] Step 4: Discord failure notification (conditional)
- [ ] Test via `gh workflow run scheduled-content-generator.yml`

## Batch 3: Validation & Ship

### 3.1 End-to-end validation
- [ ] Trigger SEO/AEO audit via workflow_dispatch, verify issue created
- [ ] Trigger content generator via workflow_dispatch, verify article + distribution file committed
- [ ] Verify content-publisher picks up the generated distribution file (next 14:00 UTC run)
- [ ] Trigger growth execution via workflow_dispatch, verify keyword fixes committed

### 3.2 Deferred work — create follow-up issues
- [ ] Create issue: "feat: KPI remediation dispatcher — auto-trigger workflows on miss"
- [ ] Create issue: "feat: Content generator queue exhaustion fallback via growth plan"

### 3.3 Ship
- [ ] Run `/soleur:compound` to capture learnings
- [ ] Run `/soleur:ship` to create PR with semver label
