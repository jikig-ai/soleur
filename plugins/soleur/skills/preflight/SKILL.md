---
name: preflight
description: "This skill should be used when running pre-ship checks on migrations, security headers, and lockfiles."
---

# preflight Skill

**Purpose:** Validate technical readiness of code changes before a PR is created, catching the class of bugs that only appear in production context -- unapplied database migrations, CSP violations from injected scripts, and bare-repo stale file reads.

**CRITICAL: No command substitution.** Never use `$()` in Bash commands. When a step says "get value X, then use it in command Y", run them as **two separate Bash tool calls** -- first get the value, then use it literally in the next call.

## Headless Mode Detection

If `$ARGUMENTS` contains `--headless`, set `HEADLESS_MODE=true`. Strip `--headless` from `$ARGUMENTS` before processing remaining args.

When `HEADLESS_MODE=true`:

- On any FAIL: abort with error details, no prompt
- On all PASS/SKIP: continue silently

## Phase 0: Context Detection

Run `git rev-parse --abbrev-ref HEAD` to get the current branch name.

**Branch safety check (defense-in-depth):** If the branch is `main` or `master`, abort immediately with: "Error: preflight cannot run on main/master. Checkout a feature branch first."

## Phase 1: Run All Checks in Parallel

Run these four checks (plus the Not-Bare-Repo assertion) as parallel Bash tool calls. Each returns PASS, FAIL, or SKIP.

### Assertion: Not-Bare-Repo

This assertion runs first conceptually (fail-fast) but executes in parallel with the checks.

```bash
git rev-parse --is-bare-repository
```

- If the result is `true`: **FAIL** -- "Running from bare repo root. Create a worktree first."
- If the result is `false`: **PASS**

### Check 1: DB Migration Status

**Step 1.1: Detect new migration files in this branch.**

```bash
git diff --name-only origin/main...HEAD -- '*/supabase/migrations/*.sql'
```

If no migration files are found, return **SKIP**.

**Step 1.2: Parse migration SQL for table/column pairs.**

For each migration file found in Step 1.1, extract table and column names:

```bash
grep -iE 'ADD COLUMN|CREATE TABLE' <migration_file>
```

Parse the output to extract `<table> <column>` pairs. The project uses `ALTER TABLE public.<table> ADD COLUMN IF NOT EXISTS <column> <type>` patterns.

**Step 1.3: Get Supabase credentials from Doppler.**

Run these as two separate Bash calls (no command substitution):

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
```

```bash
doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain
```

If either credential is missing, return **SKIP** with note: "Supabase credentials not available in Doppler prd config."

**Step 1.4: Verify each column via Supabase REST API.**

For each table/column pair extracted in Step 1.2, issue a read-only GET request:

```bash
curl -sf "<SUPABASE_URL>/rest/v1/<table>?select=<column>&limit=1" -H "apikey: <SERVICE_ROLE_KEY>" -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
```

- A **200 response** (even empty `[]`) confirms the column exists -- migration is applied.
- A **400 response** with "column does not exist" confirms the migration was **NOT applied**.

**IMPORTANT:** Use only GET requests. The service role key has full write access -- never issue POST, PUT, PATCH, or DELETE.

**Result:**

- **PASS** -- No migrations in PR, or all migrations verified as applied
- **FAIL** -- Unapplied migration found (column query returned 400)
- **SKIP** -- No migration files in PR, or credentials unavailable

### Check 2: Security Headers and Parity

**Step 2.1: Detect relevant file changes.**

```bash
git diff --name-only origin/main...HEAD
```

Check if any changed files match these patterns: `.tsx`, `.css`, `.html`, `middleware.ts`, `next.config.*`, `.tf`, `Dockerfile`, `nginx*`, `.github/workflows/*`.

If no relevant files changed, return **SKIP**.

**Step 2.2: Get production URL from Doppler.**

```bash
doppler secrets get NEXT_PUBLIC_APP_URL -p soleur -c prd --plain
```

If no URL is available, return **SKIP** with note: "Production URL not available."

**Step 2.3: Fetch response headers.**

Fetch headers from the root page (not `/health` -- the health endpoint skips CSP):

```bash
curl -sI <PRODUCTION_URL>/
```

**Step 2.4: Validate mandatory security headers.**

Check the response against the project's security header policy derived from `apps/web-platform/lib/security-headers.ts`:

| Header | Expected Value | Severity if Missing |
|--------|---------------|-------------------|
| Content-Security-Policy | Contains `strict-dynamic` + nonce | FAIL |
| X-Frame-Options | `DENY` | FAIL |
| X-Content-Type-Options | `nosniff` | FAIL |
| Strict-Transport-Security | `max-age=63072000; includeSubDomains; preload` | FAIL |
| Referrer-Policy | `strict-origin-when-cross-origin` | PASS (non-critical) |
| Permissions-Policy | Contains `camera=(), microphone=()` | PASS (non-critical) |
| Cross-Origin-Opener-Policy | `same-origin` | PASS (non-critical) |
| Cross-Origin-Resource-Policy | `same-origin` | PASS (non-critical) |
| X-DNS-Prefetch-Control | `on` | PASS (non-critical) |

**Step 2.5: Validate CSP directive structure.**

CSP is generated per-request in middleware.ts with a per-request nonce via `crypto.randomUUID()`. Validate the CSP structure, not the specific nonce value:

- Verify `strict-dynamic` is present in `script-src`
- Verify no standalone `unsafe-inline` without `strict-dynamic` override
- Parse CSP as directive-level tokens

**Notes:**

- Cloudflare-injected headers (`cf-ray`, `server: cloudflare`) are expected in production -- ignore them.
- The `/health` endpoint explicitly skips CSP in middleware -- always fetch `/` for the full header set.
- **Limitation (v1):** This check validates the current production deployment, not the branch under review. It catches existing header regressions but cannot detect regressions introduced by the current PR until after deployment. Preview deployments would enable pre-merge header validation (deferred to v2).

**Result:**

- **PASS** -- All critical headers present and valid (CSP, X-Frame-Options, X-Content-Type-Options, HSTS)
- **FAIL** -- Any critical header missing or invalid
- **SKIP** -- No relevant file changes or no production URL available

### Check 3: Lockfile Consistency

**Step 3.1: Detect lockfile modifications in this branch.**

```bash
git diff --name-status origin/main...HEAD -- '*/bun.lock' '*/package-lock.json' 'bun.lock' 'package-lock.json'
```

This returns status letters (M=modified, A=added, D=deleted) alongside file paths. If no output, return **SKIP**.

Only lockfiles with status **M** (modified) trigger the consistency check. Added (A) or deleted (D) lockfiles are one-time structural changes that do not require sibling updates.

**Step 3.2: For each modified lockfile, verify its sibling.**

For each lockfile with status M in the Step 3.1 output:

1. Extract the directory path (e.g., `apps/web-platform` from `apps/web-platform/bun.lock`). For root-level lockfiles (`bun.lock` or `package-lock.json` with no path prefix), use the repository root directory.
2. Determine the sibling: if the modified file is `bun.lock`, the sibling is `package-lock.json` (and vice versa).
3. Check if the sibling exists in the working tree (separate Bash call):

```bash
test -f <directory>/package-lock.json && echo "exists" || echo "missing"
```

4. If the sibling does NOT exist (single-lockfile directory), skip this file -- no consistency check needed.
5. If the sibling exists (dual-lockfile directory), check whether the sibling also appears in the Step 3.1 output (any status: M, A, or D). If the sibling is NOT in the diff at all, report **FAIL**: "`<directory>/` modified `bun.lock` but not `package-lock.json`. Both lockfiles must be updated together (see AGENTS.md dual-lockfile rule). Run `npm install` in `<directory>/` to regenerate `package-lock.json`." (If `package-lock.json` was modified without `bun.lock`, say: "Run `bun install` in `<directory>/` to regenerate `bun.lock`.")

If multiple files fail, report each one. Any single failure means the overall check result is FAIL.

**Result:**

- **PASS** -- All modified lockfiles in dual-lockfile directories have consistent sibling updates
- **FAIL** -- One or more dual-lockfile directories have a modified lockfile without its sibling updated (message names each directory and missing file)
- **SKIP** -- No lockfile changes in this branch

### Check 4: Environment Isolation

**Always runs (no path-pattern gate).** Enforces `hr-dev-prd-distinct-supabase-projects`: dev and prd Doppler configs must resolve to different Supabase project refs.

**Step 4.1: Fetch dev and prd Supabase URLs.**

Run as separate Bash calls (no command substitution per skill convention):

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c dev --plain
```

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
```

If either call fails or returns empty, return **SKIP** with note: "Doppler unavailable or NEXT_PUBLIC_SUPABASE_URL unset."

**Step 4.2: Resolve project ref for each URL.**

The single chokepoint is the canonical-hostname regex `^[a-z0-9]{20}\.supabase\.co$`. Both branches below MUST converge on a hostname matching that regex before Step 4.3 runs.

1. Strip the `https://` prefix and any trailing path; keep the bare host.
2. If the bare host already matches the canonical regex, use it directly.
3. Otherwise (custom domain), resolve via `dig`:

   ```bash
   dig +short CNAME <host>
   ```

   Capture the exit code separately. Strict-mode resilience: do not pipe through `|| true` — that masks SERVFAIL/network errors as "no record" and silently disables the gate. Branch on the captured rc:

   - `rc == 0` and output non-empty: candidate hostname is the CNAME target (strip trailing dot).
   - `rc == 0` and output empty: no CNAME exists. Fall back to `dig +short A <host>`. If the A-record resolves to a Supabase IP range, **FAIL** with: "Custom domain `<host>` uses A-record-only Supabase routing. Check 4 cannot prove project ref. Configure CNAME-based custom domain or temporarily set Doppler `<config>.NEXT_PUBLIC_SUPABASE_URL` to the bare `<ref>.supabase.co` form for the isolation check." A-records are rare for Supabase custom domains; failing is correct because SKIPping fails-open the security gate.
   - `rc != 0`: SERVFAIL, NXDOMAIN, network error, etc. Return **SKIP** with diagnostic: "dig exit `<rc>` for `<host>` — DNS resolution unavailable; isolation check inconclusive." (SKIP only when the diagnostic is genuinely undetermined; A-record-only is determined and FAILs.)
4. Verify the resulting hostname matches `^[a-z0-9]{20}\.supabase\.co$`. If it does not, **FAIL** with: "Resolved hostname `<host>` is not a canonical Supabase project endpoint. Refusing to compare on a non-canonical name (subdomain-bypass guard)." This catches inputs like `<ref>.supabase.co.evil.com` that pass step 1 but fail the anchored regex.

The 20-char first label of a canonical hostname IS the project ref — extract via the literal first label or by stripping `.supabase.co`.

**Step 4.3: Compare project refs.**

If `dev_ref == prd_ref`, **FAIL** with: "Environment isolation violation: dev and prd resolve to the same Supabase project ref `<ref>`. See issue #2887."

Otherwise **PASS**.

**Result:**

- **PASS** -- dev and prd resolve to distinct project refs
- **FAIL** -- refs match (single-DB blast radius), hostname is not a canonical Supabase endpoint, or custom domain uses A-record-only routing
- **SKIP** -- Doppler unavailable, NEXT_PUBLIC_SUPABASE_URL unset in either config, or DNS resolution failed (`dig` rc != 0)

## Phase 2: Aggregate Go/No-Go Report

After all checks complete, aggregate results into a structured report:

```markdown
## Preflight Results

| Check | Result | Details |
|-------|--------|---------|
| Not-Bare-Repo | PASS/FAIL | <details> |
| DB Migration Status | PASS/FAIL/SKIP | <details> |
| Security Headers | PASS/FAIL/SKIP | <details> |
| Lockfile Consistency | PASS/FAIL/SKIP | <details> |
| Environment Isolation | PASS/FAIL/SKIP | <details> |

**Overall: PASS / FAIL**
```

### If any FAIL

**Headless mode:** Abort with: "Preflight FAILED. See results above. Fix the issues and re-run `/ship`."

**Interactive mode:** Present findings table, then use **AskUserQuestion tool**:

- Question: "Preflight found issues. How to proceed?"
- Options:
  1. "Fix and retry" -- fix the issues, then re-run preflight from Phase 1
  2. "Abort" -- stop the pipeline

### If all PASS or SKIP

Print the summary table and continue.

## Preflight Complete

Preflight validation passed. Return control to the calling orchestrator.
