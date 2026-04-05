# Tasks: Pre-flight Validation Gates

Source plan: `knowledge-base/project/plans/2026-04-05-feat-preflight-validation-gates-plan.md`

## Phase 1: Skill Skeleton and Inline Checks

### 1.1 Create skill directory and SKILL.md skeleton

- [ ] Create `plugins/soleur/skills/preflight/` directory
- [ ] Write `SKILL.md` with YAML frontmatter (`name: preflight`, third-person description)
- [ ] Add headless mode detection and `$ARGUMENTS` parsing
- [ ] Add Phase 0: Context Detection (branch check, base branch detection)

### 1.2 Implement Check 4: File Freshness (inline shell)

- [ ] Detect bare repo vs worktree context (`git rev-parse --is-bare-repository`)
- [ ] Check working tree cleanliness (`git diff HEAD -- AGENTS.md CLAUDE.md`)
- [ ] Verify expected diff against origin/main
- [ ] Report severity: CRITICAL (bare repo), WARNING (dirty), PASS (clean)

### 1.3 Implement Check 1: DB Migration Status

- [ ] Detect new migration files: `git diff --name-only origin/main...HEAD -- '*/supabase/migrations/*.sql'`
- [ ] Detect schema-touching code changes (grep for CREATE TABLE, ALTER TABLE)
- [ ] Verify migration application via Supabase REST API (credentials from Doppler `prd`)
- [ ] Conditional: spawn `data-migration-expert` Task for complex migrations
- [ ] Graceful degradation when Doppler credentials are missing

### 1.4 Implement Check 3: Security Header Audit

- [ ] Detect middleware/config/infrastructure file changes in PR diff
- [ ] Fetch response headers from production/dev via `curl -sI`
- [ ] Validate mandatory headers: CSP, X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy
- [ ] Validate CSP directives (no unsafe-inline without nonce, strict-dynamic present)
- [ ] Validate cookie attributes (Secure, HttpOnly, SameSite)
- [ ] Conditional: spawn `security-sentinel` Task when issues detected
- [ ] Graceful degradation when no URL is available

### 1.5 Implement Check 2: Production Parity

- [ ] Detect web-facing file changes (`.tsx`, `.css`, `.html`, `middleware.ts`, `next.config.*`)
- [ ] Fetch production response headers via `curl -sI`
- [ ] Compare CSP header against documented policy
- [ ] Conditional: use Playwright MCP `browser_console_messages` for CSP violation detection
- [ ] Graceful degradation when Playwright/production URL unavailable

### 1.6 Implement go/no-go report aggregation

- [ ] Collect results from all 4 checks into structured report
- [ ] Severity table: CRITICAL/HIGH/WARNING/INFO per check
- [ ] Overall verdict: PASS (no CRITICAL), FAIL (any CRITICAL)
- [ ] Format as markdown table for readability
- [ ] Headless mode: abort on CRITICAL, continue on WARNING

## Phase 2: Ship Pipeline Integration

### 2.1 Add Phase 5.4 to ship SKILL.md

- [ ] Insert Phase 5.4 section between Phase 5 (Final Checklist) and Phase 5.5 (Pre-Ship Review Gates)
- [ ] Wire `skill: soleur:preflight` invocation
- [ ] Forward `--headless` flag when `HEADLESS_MODE=true`
- [ ] On CRITICAL: abort ship pipeline with error details
- [ ] On WARNING/HIGH: log findings, continue to Phase 5.5

## Phase 3: Documentation and Registration

### 3.1 Register skill and update counts

- [ ] Add preflight to `docs/_data/skills.js` SKILL_CATEGORIES
- [ ] Run `bash scripts/sync-readme-counts.sh` to update README counts
- [ ] Verify docs build: `npx @11ty/eleventy --input=docs --dryrun`
