---
title: "feat: pre-flight validation gates eliminating post-merge surprises"
type: feat
date: 2026-04-05
issue: "#1242"
semver: minor
---

# Pre-flight Validation Gates

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
    +---> Check 1: DB Migration Status     (inline shell + conditional data-migration-expert Task)
    +---> Check 2: Production Parity        (inline Playwright MCP + curl)
    +---> Check 3: Security Header Audit    (inline curl + conditional security-sentinel Task)
    +---> Check 4: File Freshness           (inline shell -- deterministic)
    |
    v
Aggregate go/no-go report
    |
    v
/soleur:ship Phase 5.5 (continues)
```

### Check Details

#### Check 1: DB Migration Status

**Purpose:** Detect schema changes that lack migrations or migrations that have not been applied.

**Steps:**

1. `git diff --name-only origin/main...HEAD -- '*/supabase/migrations/*.sql'` -- detect new migration files in PR
2. `git diff --name-only origin/main...HEAD -- '*.sql' '*.ts'` -- detect schema-touching code changes (CREATE TABLE, ALTER TABLE patterns)
3. If migration files exist, verify they are applied to production via Supabase REST API:
   - Get credentials from Doppler (`doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain`)
   - Query for columns/tables added by each migration
   - Report `APPLIED` or `NOT_APPLIED` per migration
4. If code changes reference new columns/tables but no migration file exists, flag as `MISSING_MIGRATION`
5. **Conditional agent:** If migration files exist AND contain complex transformations (CASE, UPDATE...SET, data backfill patterns), spawn `data-migration-expert` via Task for code review

**Severity mapping:**

- `NOT_APPLIED`: CRITICAL (blocks merge)
- `MISSING_MIGRATION`: WARNING (may be intentional -- existing column usage)
- Complex migration without review: WARNING

#### Check 2: Production Parity

**Purpose:** Compare the PR's changes against the production environment to catch environment-specific issues.

**Steps:**

1. Detect if the PR touches web-facing files (`.tsx`, `.css`, `.html`, `middleware.ts`, `next.config.*`)
2. If no web-facing files changed, skip with `N/A`
3. If web-facing files changed:
   a. Check if production URL is available (`DEPLOY_URL` env var or Doppler `prd` config)
   b. Use `curl -sI` to fetch production response headers
   c. Check for CSP header presence and `strict-dynamic` directive
   d. Check for third-party script injections by comparing `Content-Security-Policy` against documented policy
   e. **Conditional Playwright:** If Playwright MCP is available AND a dev server is running, navigate to affected pages and check `browser_console_messages` for CSP violations or errors
4. If no production URL is available, skip with a warning (not all branches deploy previews)

**Severity mapping:**

- CSP violation detected: HIGH
- Console errors on affected pages: HIGH
- No production URL available: INFO (skip)

#### Check 3: Security Header Audit

**Purpose:** Validate response headers against the project's security policy.

**Steps:**

1. Detect if the PR touches middleware, config, or infrastructure files (`middleware.ts`, `next.config.*`, `.tf`, `Dockerfile`, `nginx*`, `.github/workflows/*`)
2. If no relevant files changed, skip with `N/A`
3. If relevant files changed:
   a. Fetch headers from production (or dev server) via `curl -sI`
   b. Check mandatory headers: `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `Strict-Transport-Security`, `Referrer-Policy`
   c. Validate CSP directive completeness (no `unsafe-inline` without nonce, `strict-dynamic` present)
   d. Check cookie attributes (`Secure`, `HttpOnly`, `SameSite`)
   e. **Conditional agent:** If CSP or HSTS issues are detected, spawn `security-sentinel` via Task for deeper analysis
4. Compare against documented security policy in `knowledge-base/engineering/` if it exists

**Severity mapping:**

- Missing CSP: CRITICAL
- Missing HSTS: HIGH
- Missing X-Frame-Options: MEDIUM
- Cookie without Secure flag: HIGH

#### Check 4: File Freshness

**Purpose:** Verify that all file reads during the current session used `git show HEAD:<path>` rather than stale filesystem reads from the bare repo.

**Steps:**

1. This is a **deterministic inline check** -- no agent needed
2. Check if the current context is a worktree or the bare repo root:
   - `git rev-parse --is-bare-repository`
   - If bare: WARNING -- file reads from this directory are stale
   - If worktree: verify worktree is up to date with its tracking branch
3. Check that critical files match their git HEAD versions:
   - `git diff HEAD -- AGENTS.md CLAUDE.md` -- if non-empty, working tree is dirty
   - `git diff origin/main...HEAD --stat` -- verify the diff reflects the expected changes
4. Verify no stale `node_modules/` or build artifacts from a different branch:
   - `git log -1 --format=%H -- bun.lock package.json` vs current lockfile hash

**Severity mapping:**

- Bare repo without worktree: CRITICAL (must use worktree)
- Dirty working tree with uncommitted changes: WARNING
- Stale lockfile: WARNING

## Technical Considerations

### Agent Token Budget

The agent description word count is at 2,552 (limit 2,500). Adding 4 new agents would increase this by approximately 200+ words. Instead:

- **Reuse existing agents:** `data-migration-expert`, `security-sentinel` are invoked via Task tool with specific prompts when LLM reasoning is needed
- **Inline checks for deterministic logic:** File freshness and migration status checks are shell commands with binary pass/fail outcomes -- agents add unnecessary latency
- **No new agent files created:** Zero impact on the system prompt token budget

### Parallelism

All 4 checks are independent and can run in parallel. However, the constitution limits parallel subagent fan-out to max 5. Since only Checks 1 and 3 conditionally spawn agents (and the inline checks are fast shell commands), the maximum concurrent agents is 2 -- well within limits.

**Execution strategy:**

1. Run all 4 inline check preambles in parallel (shell commands to detect relevance)
2. For checks that are relevant, run the detailed validation (may include agent spawn)
3. Aggregate results into the go/no-go report

### Integration with Ship Pipeline

The skill integrates at **Phase 5.4** -- after Phase 5 (Final Checklist) and before Phase 5.5 (Pre-Ship Review Gates). This placement is intentional:

- Phase 5 confirms artifacts are committed and tests pass
- Phase 5.4 (preflight) validates technical readiness of the code changes
- Phase 5.5 validates domain/business readiness (CMO, COO gates)
- Phase 6 creates the PR

The ship skill will invoke preflight as: `skill: soleur:preflight`

### Headless Mode

When `$ARGUMENTS` contains `--headless`:

- Skip interactive confirmations
- On CRITICAL findings: abort the ship pipeline with error details
- On WARNING/HIGH findings: log them but continue (CI gate catches these)
- On INFO findings: log silently

### Graceful Degradation

| Missing Prerequisite | Behavior |
|---------------------|----------|
| No Supabase credentials in Doppler | Skip migration verification with WARNING |
| No production URL | Skip parity and header checks with INFO |
| Playwright MCP unavailable | Skip browser console check with WARNING |
| No migration files in PR | Skip Check 1 entirely |
| No web-facing files in PR | Skip Checks 2-3 entirely |
| No middleware/config changes | Skip Check 3 header audit |

## Non-Goals

- **Preview deployments:** This plan does not create or manage preview environments. It checks against the existing production URL or local dev server.
- **Visual regression testing:** Screenshot comparison is handled by `/soleur:test-browser`. Preflight checks console errors and headers, not visual layout.
- **Automated migration application:** Preflight detects unapplied migrations but does not apply them. Application is a manual step or handled by `/ship` Phase 7 Step 3.6.
- **New agent creation:** No new agent `.md` files are created due to the token budget constraint.

## Implementation Phases

### Phase 1: Skill Skeleton and Inline Checks (foundation)

**Files:**

- `plugins/soleur/skills/preflight/SKILL.md` -- skill definition with YAML frontmatter and all 4 checks
- No scripts or reference files needed initially -- all logic is inline in the SKILL.md

**Tasks:**

- [ ] Create `plugins/soleur/skills/preflight/` directory
- [ ] Write SKILL.md with frontmatter (`name: preflight`, `description: "This skill should be used when..."`)
- [ ] Implement Check 4 (File Freshness) -- simplest, pure inline shell
- [ ] Implement Check 1 (DB Migration Status) -- inline shell + conditional agent Task
- [ ] Implement Check 3 (Security Header Audit) -- inline curl + conditional agent Task
- [ ] Implement Check 2 (Production Parity) -- inline curl + conditional Playwright
- [ ] Implement go/no-go report aggregation with severity table
- [ ] Add headless mode detection and argument parsing

### Phase 2: Ship Pipeline Integration

**Files:**

- `plugins/soleur/skills/ship/SKILL.md` -- add Phase 5.4 invocation

**Tasks:**

- [ ] Add Phase 5.4 section to ship SKILL.md between Phase 5 and Phase 5.5
- [ ] Wire `skill: soleur:preflight` invocation with headless mode forwarding
- [ ] Add CRITICAL finding abort logic (blocks Phase 6 PR creation)
- [ ] Add WARNING/HIGH finding passthrough logic (logged but non-blocking)

### Phase 3: Documentation and Registration

**Files:**

- `docs/_data/skills.js` -- register new skill in SKILL_CATEGORIES
- `plugins/soleur/README.md` -- update skill count (via `sync-readme-counts.sh`)

**Tasks:**

- [ ] Register preflight in `docs/_data/skills.js` SKILL_CATEGORIES
- [ ] Run `bash scripts/sync-readme-counts.sh` to update counts
- [ ] Verify docs build: `npx @11ty/eleventy --input=docs --dryrun` (after `npm install`)

## Acceptance Criteria

### Functional Requirements

- [ ] `/soleur:preflight` runs all 4 checks and produces a structured go/no-go report
- [ ] Check 1 detects new migration files and verifies their application status via Supabase REST API
- [ ] Check 1 conditionally spawns `data-migration-expert` for complex migrations
- [ ] Check 2 detects web-facing file changes and checks production headers
- [ ] Check 2 conditionally uses Playwright MCP for console error detection
- [ ] Check 3 validates security headers against documented policy
- [ ] Check 3 conditionally spawns `security-sentinel` for deep analysis
- [ ] Check 4 detects bare repo context and stale working tree files
- [ ] CRITICAL findings abort the ship pipeline in both headless and interactive mode
- [ ] WARNING/HIGH findings are reported but do not block
- [ ] All checks gracefully degrade when prerequisites are missing

### Non-Functional Requirements

- [ ] No new agent files created (agent description budget constraint)
- [ ] All checks can run in parallel (no sequential dependencies between checks)
- [ ] Total preflight execution time under 60 seconds for PRs with no relevant changes (all checks skip)
- [ ] Follows SKILL.md conventions: YAML frontmatter, third-person description, headless mode support

## Test Scenarios

### Check 1: DB Migration Status

- Given a PR with new files in `supabase/migrations/`, when preflight runs, then each migration is checked against production Supabase and reported as APPLIED or NOT_APPLIED
- Given a PR with no migration files, when preflight runs, then Check 1 is skipped with "N/A"
- Given a PR with code referencing a new column but no migration file, when preflight runs, then a MISSING_MIGRATION warning is reported
- Given Supabase credentials are missing from Doppler, when preflight runs, then Check 1 reports a WARNING and continues

### Check 2: Production Parity

- Given a PR touching `.tsx` files and a production URL is available, when preflight runs, then response headers are fetched and CSP is validated
- Given a PR with no web-facing changes, when preflight runs, then Check 2 is skipped with "N/A"
- Given no production URL is configured, when preflight runs, then Check 2 reports INFO and continues

### Check 3: Security Header Audit

- Given a PR modifying `middleware.ts`, when preflight runs, then all mandatory security headers are checked
- Given a missing CSP header, when preflight runs, then a CRITICAL finding is reported
- Given a PR with no middleware or config changes, when preflight runs, then Check 3 is skipped

### Check 4: File Freshness

- Given the session is running from a bare repo (not a worktree), when preflight runs, then a CRITICAL finding is reported
- Given the worktree has uncommitted changes, when preflight runs, then a WARNING is reported
- Given a clean worktree with all changes committed, when preflight runs, then Check 4 passes

### Integration

- Given preflight reports a CRITICAL finding, when running inside `/ship`, then the pipeline aborts before Phase 6 (PR creation)
- Given preflight reports only WARNING findings, when running inside `/ship`, then the pipeline continues to Phase 5.5
- Given all checks are N/A (no relevant changes), when preflight runs, then it completes in under 60 seconds with an all-clear report
- Given `--headless` mode, when a CRITICAL finding is detected, then the skill aborts without prompting

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
| All checks as inline shell in ship SKILL.md | No new files, simplest | Ship SKILL.md is already 750 lines, mixing concerns | Rejected -- separation of concerns |
| CI workflow instead of skill | Runs on every PR automatically | Cannot reuse existing agents, no Playwright MCP, no Doppler access in CI without service tokens | Rejected -- wrong execution context |
| Extend postmerge skill | Already exists with similar checks | Different timing (post-merge vs pre-merge), different purpose (verify deploy vs validate readiness) | Rejected -- complementary, not replacement |

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
