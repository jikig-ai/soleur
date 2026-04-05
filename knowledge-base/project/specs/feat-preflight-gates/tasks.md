# Tasks: Pre-flight Validation Gates

Source plan: `knowledge-base/project/plans/2026-04-05-feat-preflight-validation-gates-plan.md`

## Phase 1: Skill Skeleton and All Checks

### 1.1 Create skill directory and SKILL.md skeleton

- [ ] Create `plugins/soleur/skills/preflight/` directory
- [ ] Write `SKILL.md` with YAML frontmatter (`name: preflight`, third-person description)
- [ ] Add headless mode detection and `$ARGUMENTS` parsing
- [ ] Add Phase 0: Context Detection (branch check, base branch detection)

### 1.2 Implement Assertion: Not-Bare-Repo

- [ ] `git rev-parse --is-bare-repository` -- if `true`, return FAIL and abort
- [ ] If false (worktree), return PASS

### 1.3 Implement Check 1: DB Migration Status

- [ ] Detect new migration files: `git diff --name-only origin/main...HEAD -- '*/supabase/migrations/*.sql'`
- [ ] Detect schema-touching code changes (grep for CREATE TABLE, ALTER TABLE)
- [ ] Verify migration application via Supabase REST API (read-only GET only, credentials from Doppler `prd`)
- [ ] Return SKIP when no migration files and no schema changes, or when credentials missing
- [ ] Return FAIL when unapplied migration or missing migration detected
- [ ] Return PASS when all migrations applied

### 1.4 Implement Check 2: Security Headers & Parity

- [ ] Detect web-facing and infra file changes in PR diff (`.tsx`, `.css`, `.html`, `middleware.ts`, `next.config.*`, `.tf`, `Dockerfile`, `nginx*`, `.github/workflows/*`)
- [ ] Return SKIP when no relevant files changed, or no production URL available
- [ ] Fetch response headers from production via single `curl -sI` call
- [ ] Validate mandatory headers: CSP, X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy
- [ ] Validate CSP directives (no unsafe-inline without nonce, strict-dynamic present)
- [ ] Validate cookie attributes (Secure, HttpOnly, SameSite) if set-cookie headers present
- [ ] Return FAIL when CSP or HSTS missing, PASS when all valid

### 1.5 Implement go/no-go report

- [ ] Collect results from 2 checks + 1 assertion into structured report
- [ ] Format as markdown table: Check | Result (PASS/FAIL/SKIP)
- [ ] Overall: any FAIL aborts, all PASS/SKIP continues
- [ ] Headless mode: abort on FAIL with error details
- [ ] Interactive mode: on FAIL, present findings and ask "Fix and retry, or abort?"

## Phase 2: Ship Pipeline Integration

### 2.1 Add Phase 5.4 to ship SKILL.md

- [ ] Insert Phase 5.4 section between Phase 5 (Final Checklist) and Phase 5.5 (Pre-Ship Review Gates)
- [ ] Wire `skill: soleur:preflight` invocation
- [ ] Forward `--headless` flag when `HEADLESS_MODE=true`
- [ ] On FAIL: abort ship pipeline with error details
- [ ] On all PASS/SKIP: continue to Phase 5.5

## Phase 3: Documentation and Registration

### 3.1 Register skill and update counts

- [ ] Add preflight to `docs/_data/skills.js` SKILL_CATEGORIES
- [ ] Run `bash scripts/sync-readme-counts.sh` to update README counts
- [ ] Verify docs build: `npx @11ty/eleventy --input=docs --dryrun`
