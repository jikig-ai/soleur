---
title: "feat: pre-flight validation gates eliminating post-merge surprises"
type: feat
date: 2026-04-05
issue: "#1242"
semver: minor
---

# Pre-flight Validation Gates

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 4 (Check 1, Check 2, Ship Integration, Implementation Phase 1)
**Sources used:** 8 project learnings, codebase analysis (security-headers.ts, middleware.ts, migration files, skills.js)

### Key Improvements

1. Concrete SQL parsing patterns for migration verification with exact Supabase REST API query format
2. Exact header validation list derived from `apps/web-platform/lib/security-headers.ts` (9 headers, not 5)
3. Edge case handling for Doppler token scope mismatch (learning: `2026-03-29`)
4. Ship integration pattern aligned with existing Phase N.5 convention (learning: `2026-03-27`)
5. Skills.js registration category identified: "Workflow" (alongside ship, deploy, one-shot)

## Overview

A `/soleur:preflight` skill that runs as a mandatory gate before `/ship`, spawning parallel validation checks to catch the class of bugs that only appear in production context -- unapplied database migrations, CSP violations from injected scripts, stale file reads, and security header misconfigurations. Integrates at Phase 5.4 in the ship pipeline.

## Problem Statement

Multiple sessions have revealed issues that only surface after merge or deploy:

- **Unapplied migrations:** `010_tag_and_route.sql` was committed but never applied to production Supabase, causing `NOT NULL` constraint failures on every Command Center session start (learning: `2026-03-28-unapplied-migration-command-center-chat-failure.md`)
- **CSP violations in production:** Cloudflare-injected scripts break `strict-dynamic` CSP in production but not locally (learning: `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`)
- **Stale file reads:** Review agents read from the bare repo filesystem instead of `git show HEAD:<path>`, producing reviews based on outdated content (learning: `2026-03-13-bare-repo-stale-files-and-working-tree-guards.md`)
- **Silent release failures:** Docker builds broke because `package-lock.json` was not regenerated alongside `bun.lock`, causing 5 consecutive release run failures (learning: `2026-03-29-post-merge-release-workflow-verification.md`)

The ship skill already has Phase 5.5 (domain review gates) and Phase 7 (post-merge verification), but nothing validates the technical readiness of the actual code changes before the PR is created.

## Proposed Solution

Create a new `plugins/soleur/skills/preflight/SKILL.md` that runs 4 validation checks. The critical architectural decision is to **not create new agents** -- the agent description budget is already at 2,552 words (over the 2,500 limit). Instead, use a combination of:

1. **Inline deterministic checks** (shell commands with pass/fail outcomes) for freshness and migration status -- per constitution: "Prefer inline instructions over Task agents for deterministic checks"
2. **Existing agents via Task tool** for analysis that requires LLM reasoning (security-sentinel for header analysis, data-migration-expert for migration code review)
3. **Inline Playwright MCP** for production parity browser checks

### Architecture

```text
/soleur:ship Phase 5.4
    |
    v
/soleur:preflight
    |
    +---> Check 1: DB Migration Status          (inline shell + Supabase REST API)
    +---> Check 2: Security Headers & Parity    (inline curl, header validation)
    +---> Assertion: Not-Bare-Repo               (3-line inline check)
    |
    v
Aggregate go/no-go report (PASS / FAIL / SKIP per check)
    |
    v
/soleur:ship Phase 5.5 (continues)
```

**v2 deferred:** Conditional agent spawning (data-migration-expert, security-sentinel), Playwright console error checks, lockfile consistency validation. See "Deferred to v2" section below.

### Check Details

#### Check 1: DB Migration Status

**Purpose:** Detect schema changes that lack migrations or migrations that have not been applied.

**Steps:**

1. `git diff --name-only origin/main...HEAD -- '*/supabase/migrations/*.sql'` -- detect new migration files in PR
2. `git diff --name-only origin/main...HEAD -- '*.sql' '*.ts'` -- detect schema-touching code changes (grep for CREATE TABLE, ALTER TABLE patterns)
3. If migration files exist, verify they are applied to production via Supabase REST API:
   - Get credentials from Doppler (`doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain`)
   - Use only `GET` requests (read-only) -- the service role key has full access, so write operations must never be issued
   - Query for columns/tables added by each migration
   - Report `APPLIED` or `NOT_APPLIED` per migration
4. If code changes reference new columns/tables but no migration file exists, flag as `MISSING_MIGRATION`

**Result:** PASS (no migrations, or all applied), FAIL (unapplied migration found), SKIP (no migration files and no schema changes)

**Research Insights (Check 1):**

**Migration SQL parsing pattern.** Migrations in this project use `ALTER TABLE public.<table> ADD COLUMN IF NOT EXISTS <column> <type>` (see `013_repo_error.sql`). The skill should extract table/column pairs with:

```bash
grep -iE 'ADD COLUMN|CREATE TABLE' <migration_file> | sed -E 's/.*public\.([a-z_]+).*ADD COLUMN[^a-z]*([a-z_]+).*/\1 \2/'
```

**Supabase REST API verification.** Query each extracted column via PostgREST:

```bash
curl -sf "<SUPABASE_URL>/rest/v1/<table>?select=<column>&limit=1" \
  -H "apikey: <SERVICE_ROLE_KEY>" -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
```

A 200 response (even `[]` for empty tables) confirms the column exists. A 400 with `column <name> does not exist` confirms the migration was NOT applied. This is the exact pattern from the `2026-03-28-unapplied-migration` learning and ship Phase 7 Step 3.6.

**Doppler credential safety.** Use `doppler secrets get -p soleur -c prd --plain` (not `-c dev`). Per learning `2026-03-29-doppler-service-token-config-scope-mismatch`, the `-c` flag is ignored with service tokens. Since this runs locally (not CI), the personal CLI token is used, so `-c prd` works correctly. If running in CI in the future, a `DOPPLER_TOKEN_PRD` service token would be needed.

**Edge case: duplicate migration numbers.** The project has two files starting with `007_` (`007_remediate_fabricated_tc_accepted_at.sql` and `007_remove_tc_accepted_metadata_trust.sql`). The check should iterate over all files returned by `git diff`, not assume unique numbering.

#### Check 2: Security Headers & Parity

**Purpose:** Validate production response headers against the project's security policy and detect environment-specific issues (merged from original Checks 2 and 3 -- both fetch the same URL).

**Steps:**

1. Detect if the PR touches web-facing or infrastructure files (`.tsx`, `.css`, `.html`, `middleware.ts`, `next.config.*`, `.tf`, `Dockerfile`, `nginx*`, `.github/workflows/*`)
2. If no relevant files changed, SKIP
3. If relevant files changed:
   a. Check if production URL is available (`DEPLOY_URL` env var or Doppler `prd` config for `NEXT_PUBLIC_SITE_URL`)
   b. Fetch headers via single `curl -sI` call
   c. Validate mandatory headers: `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `Strict-Transport-Security`, `Referrer-Policy`
   d. Validate CSP directive completeness (no `unsafe-inline` without nonce, `strict-dynamic` present)
   e. Check cookie attributes (`Secure`, `HttpOnly`, `SameSite`) if set-cookie headers are present
   f. Compare CSP against documented policy if `knowledge-base/engineering/` has a security policy file
4. If no production URL is available, SKIP with a note (not all branches deploy previews)

**Result:** PASS (all headers present and valid), FAIL (missing CSP or HSTS), SKIP (no relevant files or no URL)

**Interactive escalation (not v1):** In v2, if CSP or HSTS issues are detected, spawn `security-sentinel` via Task for deeper analysis.

**Research Insights (Check 2):**

**Exact header checklist from codebase.** `apps/web-platform/lib/security-headers.ts` returns 9 headers (not the 5 originally planned). The complete validation list:

| Header | Expected Value | Severity if Missing |
|--------|---------------|-------------------|
| Content-Security-Policy | Contains `strict-dynamic` + nonce (from middleware.ts) | FAIL |
| X-Frame-Options | `DENY` | FAIL |
| X-Content-Type-Options | `nosniff` | FAIL |
| Strict-Transport-Security | `max-age=63072000; includeSubDomains; preload` | FAIL |
| Referrer-Policy | `strict-origin-when-cross-origin` | PASS (non-critical) |
| Permissions-Policy | Contains `camera=(), microphone=()` | PASS (non-critical) |
| Cross-Origin-Opener-Policy | `same-origin` | PASS (non-critical) |
| Cross-Origin-Resource-Policy | `same-origin` | PASS (non-critical) |
| X-DNS-Prefetch-Control | `on` | PASS (non-critical) |

**CSP is generated per-request in middleware.ts** (not static in next.config.ts). The middleware generates a per-request nonce via `crypto.randomUUID()` and calls `buildCspHeader()`. When checking with `curl -sI`, the CSP header will contain a nonce that is valid for that single request. The check should verify the CSP structure (directives present, no `unsafe-inline` without nonce override by `strict-dynamic`) rather than comparing exact nonce values.

**Health endpoint exclusion.** The middleware explicitly skips CSP for `/health` (`if (pathname === "/health") return NextResponse.next()`). The check should fetch a page path (e.g., `/`) rather than `/health` to get the full header set.

**Production URL resolution.** The production URL can be obtained from Doppler: `doppler secrets get NEXT_PUBLIC_SITE_URL -p soleur -c prd --plain`. This is more reliable than `DEPLOY_URL` which may not be set locally.

**Curl pattern for header capture.** Per learning `2026-03-14-curl-response-header-capture-pattern`, use `curl -sI` for header-only requests (HEAD method). For the full response including both headers and body: `curl -D /tmp/headers.txt -s -o /dev/null`. The `-sI` approach is simpler and sufficient since we only need headers.

#### Assertion: Not-Bare-Repo

**Purpose:** Verify the session is running from a worktree, not the bare repo root.

This is a 3-line inline assertion, not a full check. The worktree system and `worktree-write-guard.sh` hook already prevent most stale-file issues. This assertion is defense-in-depth.

**Steps:**

1. `git rev-parse --is-bare-repository` -- if `true`, FAIL immediately
2. If false (worktree): PASS

**Result:** PASS (in worktree) or FAIL (bare repo -- abort)

### Deferred to v2

The following capabilities are explicitly deferred to reduce v1 complexity. A tracking issue will be created at ship time.

- **Conditional agent spawning:** Spawn `data-migration-expert` for complex migrations and `security-sentinel` for header issues. v1 uses inline checks only.
- **Playwright console checks:** Use `browser_console_messages` to detect CSP violations on affected pages. Deferred because the dev server may not be running at Phase 5.4.
- **Lockfile consistency:** Compare `bun.lock` and `package-lock.json` timestamps/hashes against `package.json`. Deferred because CI already catches this via `npm ci` in Docker builds.
- **4-tier severity system:** CRITICAL/HIGH/WARNING/INFO with per-check mapping tables. v1 uses simple PASS/FAIL/SKIP.

## Technical Considerations

### Agent Token Budget

The agent description word count is at 2,552 (limit 2,500). No new agents are created in v1. All checks are inline shell commands and curl calls. Agent spawning (data-migration-expert, security-sentinel) is deferred to v2.

### Parallelism

Both checks and the assertion are independent and can run in parallel via separate Bash tool calls. No subagent fan-out is needed in v1 -- all logic is inline.

**Execution strategy:**

1. Run both checks and the assertion in parallel (shell commands)
2. Aggregate results into the go/no-go report (PASS/FAIL/SKIP per check)

### Integration with Ship Pipeline

The skill integrates at **Phase 5.4** -- after Phase 5 (Final Checklist) and before Phase 5.5 (Pre-Ship Review Gates). This placement is intentional:

- Phase 5 confirms artifacts are committed and tests pass
- Phase 5.4 (preflight) validates technical readiness of the code changes
- Phase 5.5 validates domain/business readiness (CMO, COO gates)
- Phase 6 creates the PR

The ship skill will invoke preflight as: `skill: soleur:preflight`

**Research Insights (Ship Integration):**

**Phase N.5 convention.** Per learning `2026-03-27-skill-defense-in-depth-gate-pattern`, defense-in-depth gates follow the Phase N.5 naming pattern. Phase 5.4 is slightly unconventional (not N.5) but appropriate here because Phase 5.5 already exists. The placement between Phase 5 (checklist) and Phase 5.5 (domain gates) is correct.

**Ship integration pattern.** Per learning `2026-02-12-ship-integration-pattern-for-post-merge-steps`, ship should remain a thin orchestration layer. The preflight skill is a standalone skill that ship conditionally invokes -- this matches the established pattern. The Phase 5.4 section in ship SKILL.md should be approximately 10-15 lines: invoke the skill, check the result, abort or continue.

**No command substitution.** Ship SKILL.md uses the "no `$()` in Bash commands" pattern throughout. The preflight invocation must follow the same convention -- invoke via the Skill tool, not via bash.

**Continuation marker convention.** Per constitution line 49, sub-skills that return control to an orchestrator must output a structured continuation marker. The preflight skill should end with a heading like `## Preflight Complete` followed by the results table, so the ship skill can detect completion vs. mid-turn abort.

### Headless Mode

When `$ARGUMENTS` contains `--headless`:

- Skip interactive confirmations
- On any FAIL: abort with error details (no "Fix and retry" prompt)
- On all PASS/SKIP: continue silently

When interactive:

- On any FAIL: present findings table, ask "Fix and retry, or abort?"
- On all PASS/SKIP: print summary table, continue

### Graceful Degradation

If a check cannot run (missing credentials, no URL, no relevant files), it returns SKIP. One code path, not six.

| Missing Prerequisite | Behavior |
|---------------------|----------|
| No Supabase credentials in Doppler | Check 1 returns SKIP |
| No production URL | Check 2 returns SKIP |
| No migration files in PR | Check 1 returns SKIP |
| No web-facing or infra files in PR | Check 2 returns SKIP |

## Non-Goals

- **Preview deployments:** This plan does not create or manage preview environments. It checks against the existing production URL or local dev server.
- **Visual regression testing:** Screenshot comparison is handled by `/soleur:test-browser`. Preflight checks headers, not visual layout.
- **Automated migration application:** Preflight detects unapplied migrations but does not apply them. Application is a manual step or handled by `/ship` Phase 7 Step 3.6.
- **New agent creation:** No new agent `.md` files are created due to the token budget constraint.
- **Lockfile consistency checking:** The `bun.lock` / `package-lock.json` dual-lockfile issue is already caught by CI (`npm ci` in Docker builds). Adding a local check would duplicate CI enforcement.

## Implementation Phases

### Phase 1: Skill Skeleton and All Checks (single phase -- small scope)

**Files:**

- `plugins/soleur/skills/preflight/SKILL.md` -- skill definition with YAML frontmatter, 2 checks + 1 assertion

**Tasks:**

- [x] Create `plugins/soleur/skills/preflight/` directory
- [x] Write SKILL.md with frontmatter (`name: preflight`, `description: "This skill should be used when..."`)
- [x] Implement Assertion: Not-Bare-Repo (3 lines)
- [x] Implement Check 1: DB Migration Status (inline shell + Supabase REST API)
- [x] Implement Check 2: Security Headers & Parity (inline curl + header validation against 9-header checklist)
- [x] Implement go/no-go report (PASS/FAIL/SKIP table)
- [x] Add headless mode detection and `$ARGUMENTS` parsing
- [x] Add interactive mode: on FAIL, present findings and ask "Fix and retry, or abort?"
- [x] Add `## Preflight Complete` continuation marker at end of successful run

**Research Insights (Phase 1):**

**SKILL.md structure.** The skill should follow the established pattern from ship/postmerge. Skeleton:

```yaml
---
name: preflight
description: "This skill should be used when validating technical readiness before shipping. It checks database migration status, security headers, and execution context."
---
```

**Headless mode per convention.** Per learning `2026-03-03-headless-mode-skill-bypass-convention`, the headless flag is detected in `$ARGUMENTS`, stripped before processing remaining args, and forwarded to any child skill invocations. The pattern is bottom-up: each skill handles its own flag.

**No command substitution rule.** Per ship SKILL.md: "Never use `$()` in Bash commands. When a step says 'get value X, then use it in command Y', run them as two separate Bash tool calls." The preflight SKILL.md must follow this same convention for Doppler credential retrieval and curl commands.

**Skill description budget.** Per learning `2026-03-30-skill-description-word-budget-awareness`, skill descriptions must stay under 1,024 characters and target approximately 30 words. The description above is 26 words.

**Skills.js registration.** The skill should be registered in `plugins/soleur/docs/_data/skills.js` under the "Workflow" category (alongside `ship`, `deploy`, `one-shot`, `postmerge`). Add: `preflight: "Workflow"` to `SKILL_CATEGORIES`. Note: `postmerge` is not currently in the SKILL_CATEGORIES map -- it should be added simultaneously.

### Phase 2: Ship Pipeline Integration

**Files:**

- `plugins/soleur/skills/ship/SKILL.md` -- add Phase 5.4 invocation

**Tasks:**

- [x] Add Phase 5.4 section to ship SKILL.md between Phase 5 and Phase 5.5
- [x] Wire `skill: soleur:preflight` invocation with headless mode forwarding
- [x] On FAIL: abort ship pipeline with error details (both headless and interactive)
- [x] On all PASS/SKIP: continue to Phase 5.5

### Phase 3: Documentation and Registration

**Files:**

- `plugins/soleur/docs/_data/skills.js` -- register new skill in SKILL_CATEGORIES
- `plugins/soleur/README.md` -- update skill count (via `sync-readme-counts.sh`)

**Tasks:**

- [ ] Register `preflight` in `plugins/soleur/docs/_data/skills.js` SKILL_CATEGORIES under "Workflow"
- [ ] Also register `postmerge` and `qa` -- both exist as skills but are missing from SKILL_CATEGORIES (discovered during deepening)
- [ ] Update the skill count comment at top of SKILL_CATEGORIES (currently says "62 skills")
- [ ] Run `bash scripts/sync-readme-counts.sh` to update README counts
- [ ] Verify docs build: `cd plugins/soleur/docs && npm install && npx @11ty/eleventy --dryrun`

## Acceptance Criteria

### Functional Requirements

- [ ] `/soleur:preflight` runs 2 checks + 1 assertion and produces a PASS/FAIL/SKIP report
- [ ] Check 1 detects new migration files and verifies their application status via Supabase REST API (read-only GET requests only)
- [ ] Check 2 detects web-facing/infra file changes and validates production security headers
- [ ] Assertion detects bare repo context and aborts
- [ ] FAIL in any check aborts the ship pipeline
- [ ] All PASS/SKIP continues the pipeline
- [ ] Checks return SKIP when prerequisites are missing (credentials, URL, relevant files)
- [ ] Interactive mode: on FAIL, present findings and ask "Fix and retry, or abort?"
- [ ] Headless mode: on FAIL, abort with error details

### Non-Functional Requirements

- [ ] No new agent files created (agent description budget constraint)
- [ ] All checks can run in parallel (no sequential dependencies)
- [ ] Total preflight execution time under 30 seconds for PRs with no relevant changes (all checks skip)
- [ ] Follows SKILL.md conventions: YAML frontmatter, third-person description, headless mode support

## Test Scenarios

### Check 1: DB Migration Status

- Given a PR with new files in `supabase/migrations/`, when preflight runs, then each migration is checked against production Supabase and reported as APPLIED or NOT_APPLIED
- Given a PR with no migration files and no schema changes, when preflight runs, then Check 1 returns SKIP
- Given a PR with code referencing a new column but no migration file, when preflight runs, then Check 1 returns FAIL with MISSING_MIGRATION detail
- Given Supabase credentials are missing from Doppler, when preflight runs, then Check 1 returns SKIP

### Check 2: Security Headers & Parity

- Given a PR touching `.tsx` files and a production URL is available, when preflight runs, then response headers are fetched and all mandatory headers are validated
- Given a PR with no web-facing or infra changes, when preflight runs, then Check 2 returns SKIP
- Given no production URL is configured, when preflight runs, then Check 2 returns SKIP
- Given a PR modifying `middleware.ts` and a missing CSP header in production, when preflight runs, then Check 2 returns FAIL

### Assertion: Not-Bare-Repo

- Given the session is running from a bare repo (not a worktree), when preflight runs, then the assertion returns FAIL and the skill aborts
- Given the session is running from a worktree, when preflight runs, then the assertion returns PASS

### Integration

- Given preflight reports any FAIL, when running inside `/ship`, then the pipeline aborts before Phase 6 (PR creation)
- Given preflight reports all PASS/SKIP, when running inside `/ship`, then the pipeline continues to Phase 5.5
- Given all checks return SKIP (no relevant changes), when preflight runs, then it completes in under 30 seconds with an all-clear report
- Given `--headless` mode, when a FAIL is detected, then the skill aborts without prompting
- Given interactive mode, when a FAIL is detected, then the skill presents findings and asks "Fix and retry, or abort?"

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** This is an internal engineering tooling improvement -- a new skill that validates technical readiness before shipping. No external services are created, no user-facing UI is involved, and no new infrastructure is provisioned. The architectural decision to reuse existing agents rather than creating new ones is sound given the agent description token budget constraint (2,552/2,500 words). The integration point at Phase 5.4 in the ship pipeline is correct -- after tests pass but before domain review and PR creation.

### Product/UX Gate

Not applicable -- this is an internal developer tool with no user-facing UI components.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| 4 new dedicated agents | Clean separation of concerns, reusable | Exceeds agent token budget (2,552 already over 2,500), adds ~200 words | Rejected -- budget constraint |
| 4 checks with conditional agent spawning | More thorough analysis | Over-engineered for v1; agent spawning is rare-case complexity | Deferred to v2 |
| All checks as inline shell in ship SKILL.md | No new files, simplest | Ship SKILL.md is already 750 lines, mixing concerns | Rejected -- separation of concerns |
| CI workflow instead of skill | Runs on every PR automatically | Cannot reuse existing agents, no Playwright MCP, no Doppler access in CI without service tokens | Rejected -- wrong execution context |
| Extend postmerge skill | Already exists with similar checks | Different timing (post-merge vs pre-merge), different purpose (verify deploy vs validate readiness) | Rejected -- complementary, not replacement |
| Migration check only (v1) | Simplest possible, highest value | Headers/CSP caused real production issues too; omitting feels like under-building | Rejected -- both checks have production evidence |

## Edge Cases Discovered During Research

1. **Migration with IF NOT EXISTS:** The `ADD COLUMN IF NOT EXISTS` pattern means the REST API query will succeed even if the migration was re-run. This is the correct behavior -- the check verifies the column exists, not whether the specific migration was applied.

2. **CSP nonce rotation:** Each curl request gets its own nonce. The check must validate CSP directive structure (`strict-dynamic` present, no standalone `unsafe-inline`), not the specific nonce value. Parse CSP as directive-level tokens.

3. **Production URL may use Cloudflare proxy:** Response headers from `curl -sI` may include Cloudflare-injected headers (`cf-ray`, `server: cloudflare`). These are expected and should not trigger failures. The check validates security headers only, not infrastructure headers.

4. **No production URL for plugin-only changes:** PRs that only touch `plugins/soleur/` have no web deployment. Check 2 correctly returns SKIP when no production URL exists.

5. **Middleware CSP vs next.config headers:** CSP is set in middleware.ts (per-request nonce). Other 8 security headers are set in `next.config.ts` via `buildSecurityHeaders()`. Both appear in the same curl response. The check does not need to distinguish their source.

6. **Skill invocation from bare repo root:** If someone runs `/ship` from the bare repo root (violating worktree convention), the Not-Bare-Repo assertion fires before any checks that would fail with confusing git errors. This is the correct fail-fast ordering.

## Rollback Plan

If the preflight skill causes false positives that block shipping:

1. Remove Phase 5.4 from `plugins/soleur/skills/ship/SKILL.md` (one-line deletion)
2. The preflight skill remains available as a standalone tool but is no longer mandatory
3. No data loss, no infrastructure changes, no external service dependencies

## References

- Issue: [#1242](https://github.com/jikig-ai/soleur/issues/1242)
- Related: [#1236](https://github.com/jikig-ai/soleur/issues/1236) (combined sprint + CI triage)
- Learning: `2026-03-28-unapplied-migration-command-center-chat-failure.md`
- Learning: `2026-03-27-csp-strict-dynamic-requires-dynamic-rendering.md`
- Learning: `2026-03-13-bare-repo-stale-files-and-working-tree-guards.md`
- Learning: `2026-03-29-post-merge-release-workflow-verification.md`
- Existing skill: `plugins/soleur/skills/postmerge/SKILL.md` (complementary post-merge verification)
- Existing skill: `plugins/soleur/skills/ship/SKILL.md` (integration target)
- Existing agent: `plugins/soleur/agents/engineering/review/data-migration-expert.md`
- Existing agent: `plugins/soleur/agents/engineering/review/security-sentinel.md`

## Plan Review [Updated 2026-04-05]

Three reviewers assessed this plan. Applied changes based on consensus:

1. **Merged Checks 2 and 3** into single "Security Headers & Parity" -- both fetched the same URL
2. **Reduced Check 4 to 3-line assertion** -- worktrees already prevent stale file reads
3. **Deferred conditional agent spawning to v2** -- inline checks are sufficient
4. **Simplified severity to PASS/FAIL/SKIP** -- 4-tier system was premature
5. **Cut Playwright from v1** -- dev server may not be running at Phase 5.4
6. **Added lockfile consistency as explicit non-goal** -- CI already catches this
7. **Added interactive mode FAIL behavior** -- "Fix and retry, or abort?"
8. **Added production API safety note** -- read-only GET requests only
