# Tasks: Pre-flight Validation Gates

Source plan: `knowledge-base/project/plans/2026-04-05-feat-preflight-validation-gates-plan.md`

## Phase 1: Skill Skeleton and All Checks

### 1.1 Create skill directory and SKILL.md skeleton

- [ ] Create `plugins/soleur/skills/preflight/` directory
- [ ] Write `SKILL.md` with YAML frontmatter (`name: preflight`, third-person description, ~26 words)
- [ ] Add headless mode detection: strip `--headless` from `$ARGUMENTS`, set `HEADLESS_MODE`
- [ ] Add Phase 0: Context Detection (branch safety check -- abort if on main/master)
- [ ] Follow no-command-substitution convention: two separate Bash calls for get-then-use patterns

### 1.2 Implement Assertion: Not-Bare-Repo

- [ ] `git rev-parse --is-bare-repository` -- if `true`, return FAIL and abort
- [ ] If false (worktree), return PASS
- [ ] This runs first (fail-fast before checks that would produce confusing git errors)

### 1.3 Implement Check 1: DB Migration Status

- [ ] Detect new migration files: `git diff --name-only origin/main...HEAD -- '*/supabase/migrations/*.sql'`
- [ ] Parse SQL files for table/column pairs: grep for `ADD COLUMN`, `CREATE TABLE` patterns
- [ ] Get Supabase credentials: `doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain` (separate Bash call)
- [ ] Get service role key: `doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain` (separate Bash call)
- [ ] Verify each column via Supabase REST API: `curl -sf "<URL>/rest/v1/<table>?select=<column>&limit=1"` with auth headers
- [ ] Handle duplicate migration numbers (project has two `007_` files)
- [ ] Return SKIP when no migration files and no schema changes, or when credentials missing
- [ ] Return FAIL when column query returns 400 (column not found) or when code references new columns with no migration
- [ ] Return PASS when all migrations verified or no migrations in PR

### 1.4 Implement Check 2: Security Headers & Parity

- [ ] Detect web-facing and infra file changes in PR diff (`.tsx`, `.css`, `.html`, `middleware.ts`, `next.config.*`, `.tf`, `Dockerfile`, `nginx*`, `.github/workflows/*`)
- [ ] Get production URL: `doppler secrets get NEXT_PUBLIC_SITE_URL -p soleur -c prd --plain` (separate Bash call)
- [ ] Return SKIP when no relevant files changed, or no production URL available
- [ ] Fetch response headers via `curl -sI <URL>/` (use `/` not `/health` -- health endpoint skips CSP)
- [ ] Validate 9 headers from `security-headers.ts`: CSP, X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy, Permissions-Policy, COOP, CORP, X-DNS-Prefetch-Control
- [ ] Validate CSP directive structure: `strict-dynamic` present, no standalone `unsafe-inline` (ignore nonce values)
- [ ] Validate cookie attributes (Secure, HttpOnly, SameSite) if set-cookie headers present
- [ ] Ignore Cloudflare-injected headers (`cf-ray`, `server: cloudflare`) -- expected in production
- [ ] Return FAIL when CSP or HSTS missing, PASS when all critical headers valid

### 1.5 Implement go/no-go report

- [ ] Collect results from 2 checks + 1 assertion into structured report
- [ ] Format as markdown table: Check | Result (PASS/FAIL/SKIP) | Details
- [ ] Overall: any FAIL aborts, all PASS/SKIP continues
- [ ] Headless mode: abort on FAIL with error details, no prompt
- [ ] Interactive mode: on FAIL, present findings and ask "Fix and retry, or abort?"
- [ ] End with `## Preflight Complete` continuation marker for ship orchestrator

## Phase 2: Ship Pipeline Integration

### 2.1 Add Phase 5.4 to ship SKILL.md

- [ ] Insert Phase 5.4 section between Phase 5 (Final Checklist) and Phase 5.5 (Pre-Ship Review Gates)
- [ ] Wire `skill: soleur:preflight` invocation (via Skill tool, not bash)
- [ ] Forward `--headless` flag when `HEADLESS_MODE=true`
- [ ] On FAIL: abort ship pipeline with error details
- [ ] On all PASS/SKIP: continue to Phase 5.5
- [ ] Keep section to ~10-15 lines (thin orchestration layer)

## Phase 3: Documentation and Registration

### 3.1 Register skill and update counts

- [ ] Add `preflight: "Workflow"` to SKILL_CATEGORIES in `plugins/soleur/docs/_data/skills.js`
- [ ] Also add missing `postmerge: "Workflow"` and `qa: "Workflow"` (discovered during deepening)
- [ ] Update skill count comment (currently says "62 skills")
- [ ] Run `bash scripts/sync-readme-counts.sh` to update README counts
- [ ] Verify docs build: `cd plugins/soleur/docs && npm install && npx @11ty/eleventy --dryrun`
