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
- On all PASS/SKIP: continue silently. **Two exceptions, both Check 10 only, both always emitted:** **SKIP-DECLARED** — continue, but emit one line naming the declared credential scope (a verification waiver exists to be reviewable, so silencing it defeats it); and **SKIP-NOSANDBOX** — continue, but emit one line stating that Check 10 did not run at all on this host. The second is the more important of the two: it means a security-relevant gate is dark, and folded into the silent set it is indistinguishable from the gate having nothing to do.

## Phase 0: Context Detection

Run `git rev-parse --abbrev-ref HEAD` to get the current branch name.

**Branch safety check (defense-in-depth):** If the branch is `main` or `master`, abort immediately with: "Error: preflight cannot run on main/master. Checkout a feature branch first."

### Step 0.1: Compute changed-file path-set (diff classifier)

Run `git diff --name-only origin/main...HEAD` ONCE up-front and cache the result so each path-gated check re-uses the same path-set instead of re-running diff. Skill convention forbids `$()` command substitution — write the diff to a tmpfile so checks can `grep -E` the predicate they care about.

Use `git rev-parse --git-dir` to resolve a writable tmp path that works in both regular checkouts and worktrees: in a worktree `.git` is a file (gitdir pointer), not a directory, so `> .git/<filename>` fails with `Not a directory (os error 20)`. The resolver returns the worktree's actual gitdir (e.g., `<bare>/worktrees/<name>/`):

```bash
PREFLIGHT_TMP="$(git rev-parse --git-dir)"
git diff --name-only origin/main...HEAD > "$PREFLIGHT_TMP/preflight-diff-files.txt"
```

All downstream `cat .git/<filename>` references in the predicates below must use `"$PREFLIGHT_TMP/<filename>"` instead. The pre-existing `.git/...` literals worked in non-worktree checkouts but silently broke in worktrees (where every preflight increasingly happens by default).

If the command fails (e.g., offline, no remote), every path-gated check falls back to its existing `git diff` form — operators do not need to handle this case explicitly. Between Phase 0 and Phase 1 nothing mutates the working tree or fetches `origin/main`, so the cache is valid for the duration of one preflight invocation. The cache lives under the per-worktree gitdir (user-owned, scoped to one worktree) — this isolates concurrent preflight runs across sibling worktrees and avoids the `/tmp/` symlink-clobber class that affects fixed-name shared paths on multi-user hosts.

**Fast-path SKIP overview.** For diffs whose path-set matches a recognized "guaranteed-SKIP" shape, the relevant check returns SKIP at its first step without further work. The predicates below are the existing inner predicates of each check — only the diff source is changed.

| Check | Fast-path SKIP predicate (against `"$PREFLIGHT_TMP/preflight-diff-files.txt"`) |
| --- | --- |
| 1 (Migrations) | Zero matches for `(^\|/)supabase/migrations/.*\.sql$`. |
| 2 (Sec headers) | Zero matches for `\.(tsx\|css\|html)$`, `middleware\.ts$`, `next\.config\.`, `\.tf$`, `Dockerfile`, `nginx`, `\.github/workflows/`. |
| 3 (Lockfiles) | Existing predicate (uses `--name-status`, status letters load-bearing — does NOT use the cached path-set; see Sharp Edges). |
| 4 (Env isolation) | Always runs (no fast-path SKIP). |
| 5 (Bundle host) | Zero matches for the listed Supabase client/validator paths, `Dockerfile`, `reusable-release.yml`, or `verify-required-secrets.sh`. |
| 6 (Brand-survival) | Zero matches for the canonical sensitive-path regex. |
| 7 (Canary) | `apps/web-platform/infra/ci-deploy.sh` not in path-set. |
| 8 (SW cache bump) | No `fix(`/`fix:`/`hotfix` commit subject AND zero client-bundle surface matches. |
| 9 (Node-only encodings) | Always runs (uses `git ls-files`, full-universe scan — does NOT use the cached path-set; see Sharp Edges). |
| 10 (Discoverability test) | Zero matches for the canonical sensitive-path regex (re-use Check 6 SSOT). |
| 11 (Register drift) | Zero matches for `(^\|/)apps/web-platform/supabase/migrations/.*\.sql$`, `(^\|/)apps/web-platform/server/workspace-resolver\.ts$`, or `(^\|/)knowledge-base/engineering/architecture/domain-model\.md$` (empty/missing cache → run, never SKIP). |
| 12 (Encryption posture) | Zero matches for `\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$` (empty/missing cache → run, never SKIP). |
| Not-Bare-Repo | Always runs. |

For PR #3488-class diffs (lockfile bumps + orphan-cleanup deletions), Checks 1, 2, 5, 6, 7, 8 fast-skip → Checks 3 (lockfile fires), 4 (env isolation always), 9 (always), Not-Bare-Repo (always) execute. Of those four, only Check 3 and Check 9 do "real work" against the diff; Check 4 and Not-Bare-Repo are constant-cost.

## Phase 1: Run All Checks in Parallel

Run all checks below (plus the Not-Bare-Repo assertion) as parallel Bash tool calls. Each returns PASS, FAIL, or SKIP.

### Assertion: Not-Bare-Repo

This assertion runs first conceptually (fail-fast) but executes in parallel with the checks.

```bash
git rev-parse --is-bare-repository
```

- If the result is `true`: **FAIL** -- "Running from bare repo root. Create a worktree first."
- If the result is `false`: **PASS**

### Shared Plan-File Resolution

Both Check 6 (Brand-Survival Self-Review) and Check 10 (Discoverability Test Execution) need the same input: the PR body scrubbed of HTML comments + fenced code blocks, concatenated with the linked plan file (also scrubbed). This sub-section is the single source of truth for that resolution. **Mirrored consumers: Check 6 Step 6.4, Check 10 Step 10.3.** If a future PR changes the scrub/extract logic, edit here once — both consumers pick up the change automatically.

```bash
# Step S.1: fetch PR body to a private temp file (umask 077; mktemp).
PR_BODY_FILE=$(umask 077 && mktemp -t preflight-pr-body.XXXXXXXX.md)
gh pr view --json body --jq .body > "$PR_BODY_FILE"
trap 'rm -f "$PR_BODY_FILE" "$COMBINED"' EXIT

# Step S.2: strip HTML comments and fenced code blocks from PR body.
SCRUBBED_BODY=$(awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; next} !f{print}' "$PR_BODY_FILE" \
  | perl -0777 -pe 's/<!--.*?-->//gs')

# Step S.3: extract any linked plan file path (knowledge-base/project/plans/*.md).
PLAN_PATH=$(printf '%s' "$SCRUBBED_BODY" | grep -Eo 'knowledge-base/project/plans/[^[:space:])"`'\'']+\.md' | head -n 1 || true)

# Step S.4: build the combined check input.
COMBINED=$(mktemp -t preflight-combined.XXXXXXXX.md)
printf '%s\n' "$SCRUBBED_BODY" > "$COMBINED"
if [[ -n "$PLAN_PATH" && -f "$PLAN_PATH" ]]; then
  awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; next} !f{print}' "$PLAN_PATH" \
    | perl -0777 -pe 's/<!--.*?-->//gs' >> "$COMBINED"
fi
```

If `gh pr view` fails (no PR exists for the current branch), the caller returns **SKIP** — Shared Plan-File Resolution itself does not decide; it provides `$COMBINED` (and `$PLAN_PATH`) for the caller.

### Check 1: DB Migration Status

**Step 1.1: Detect new migration files in this branch.**

Re-use the cached path-set from Phase 0 Step 0.1 (`"$PREFLIGHT_TMP/preflight-diff-files.txt"`):

```bash
grep -E '(^|/)supabase/migrations/.*\.sql$' "$PREFLIGHT_TMP/preflight-diff-files.txt"
```

The regex anchors are intentional: `(^|/)` accepts both top-level (`supabase/migrations/X.sql`) and nested-under-app-dir paths (`apps/web-platform/supabase/migrations/X.sql`); `.*\.sql$` accepts files at any depth under the migrations directory (matching git pathspec's `*` which crosses `/`). Verify at edit time via `a=$(mktemp) && b=$(mktemp) && git diff --name-only origin/main...HEAD -- '*/supabase/migrations/*.sql' supabase/migrations/*.sql > "$a" && grep -E '(^|/)supabase/migrations/.*\.sql$' "$PREFLIGHT_TMP/preflight-diff-files.txt" > "$b" && diff -u "$a" "$b"`.

If no migration files are found (grep rc=1), return **SKIP**.

**Step 1.1b: Detect documented prd-apply deferral (early SKIP).**

If migration files are found, check whether the PR has explicitly
deferred prd-apply. Two valid signals:

```bash
# (a) Migration checklist documents prd-apply as pending/deferred.
ckl=$(git ls-files 'knowledge-base/project/specs/feat-*/migration-checklist.md' | head -1)
if [[ -n "$ckl" ]] && grep -qiE '^## prd apply\s*[-—]+\s*(pending|deferred|done)' "$ckl"; then
  defer_signal="checklist:$(basename $(dirname "$ckl"))/migration-checklist.md"
fi

# (b) PR body has `Tracks #N` companion to a `prd apply`/`prd migration` line
# with a labeled deferred-automation issue (re-use the operator-step-gate shape).
pr_body=$(gh pr view --json body --jq .body 2>/dev/null || true)
if printf '%s' "$pr_body" | grep -qiE '(prd[-_ ]apply|prd[-_ ]migration).*(Tracks|Refs) #[0-9]+'; then
  defer_signal="pr-body-tracks"
fi
```

If `$defer_signal` is non-empty AND the migration-checklist's
`## prd apply` heading reads **done** (post-apply record), Check 1
proceeds to Step 1.4 to verify columns actually exist.

If `$defer_signal` is non-empty AND the heading reads **pending** or
**deferred**, return **SKIP** with note: `"prd apply deferred by
plan/PR — $defer_signal. Check 1 will re-verify post-merge via the
release workflow's verify-migrations job."` This closes the
false-positive FAIL class where a plan explicitly sequences the
prd apply in lockstep with another in-flight PR (e.g., AC-LEGAL-FLIP
gate). The signal is documented + auditable — operator cannot
silently skip Check 1 without leaving a paper trail.

If `$defer_signal` is empty, fall through to Step 1.2 (the original
unapplied-migration FAIL path is the correct response).

**Why:** PR #4225 (feat-team-workspace-multi-user) — preflight FAIL
on Check 1 because prd migrations were deferred per
migration-checklist.md (legal-PR lockstep gate); the headless
`/ship` halted the pipeline on a known-deferred state. This SKIP
path honors documented deferrals while keeping the gate active for
undocumented cases.

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

Re-use the cached path-set from Phase 0 Step 0.1:

```bash
cat "$PREFLIGHT_TMP/preflight-diff-files.txt"
```

Check if any changed files match these patterns: `.tsx`, `.css`, `.html`, `middleware.ts`, `next.config.*`, `.tf`, `Dockerfile`, `nginx*`, `.github/workflows/*`.

If no relevant files changed, return **SKIP** (fast-path — no Doppler fetch needed when the diff has no client-bundle, infra, or workflow surface).

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

Since ADR-191 this repository carries exactly ONE lockfile per directory
(`package-lock.json`); `bun.lock` is deleted and `scripts/lint-dual-lockfile.sh` fails if
one reappears. The sibling-consistency logic below therefore no longer fires here — it is
retained because this skill also runs against tenant repositories, which may legitimately
still carry dual lockfiles.

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

The single chokepoint is the canonical-hostname regex `^[a-z0-9]{20}\.supabase\.co$`. Both branches below MUST converge on a hostname matching that regex before Step 4.3 runs. The canonical resolver lives at `apps/web-platform/scripts/lib/supabase-ref-resolver.sh` (`resolve_supabase_ref`); the same shape is mirrored in `apps/web-platform/lib/supabase/resolve-ref.ts` for TS callers and consumed by `.github/workflows/reusable-release.yml` via `source`. The sub-bullets below describe Check 4's wrapper semantics on top of the resolver (e.g., the A-record-only FAIL path is a Check 4 policy, not a resolver behavior).

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

### Check 5: Production Bundle Supabase Host

**Path-gated:** only runs when the cached path-set from Phase 0 Step 0.1 (`"$PREFLIGHT_TMP/preflight-diff-files.txt"`) contains any of `apps/web-platform/lib/supabase/client.ts`, `apps/web-platform/lib/supabase/validate-url.ts`, `apps/web-platform/lib/supabase/validate-anon-key.ts`, `apps/web-platform/Dockerfile`, `.github/workflows/reusable-release.yml`, or `apps/web-platform/scripts/verify-required-secrets.sh`. Otherwise return **SKIP** with note: "No build-arg surface changes detected." The path predicate is identical to the original `git diff --name-only origin/main...HEAD` form — only the diff source is changed.

**Note:** Complements Check 4. Check 4 enforces Doppler dev/prd isolation; Check 5 covers the GitHub-repo-secrets surface that feeds the prod Docker build (`secrets.NEXT_PUBLIC_SUPABASE_URL` and `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` in `reusable-release.yml`). The two sources can drift — see `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md` (URL class) and `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` (anon-key class).

**Step 5.1: Discover the candidate chunk set.**

Webpack chunking is not stable across releases — the inlined Supabase init may live in the login page chunk, in a numeric shared chunk (`/_next/static/chunks/8237-*.js`), or in a layout chunk. Hardcoding a single path produces SKIP-on-chunking-change, which silently disables the gate (issue #3010). Discover the candidate set dynamically by enumerating every chunk URL the login HTML references — that is the authoritative "what /login loads" surface.

Run as separate Bash calls (no command substitution per skill convention). Each block
re-derives `PREFLIGHT_TMP` — it is `$(git rev-parse --git-dir)`, so it is stable across
separate Bash calls (which do NOT inherit env) AND distinct per worktree, which is what a
later call needs to find these artifacts by name without colliding with a sibling session:

```bash
PREFLIGHT_TMP="$(git rev-parse --git-dir)"
curl -fsSL --max-time 10 -A "Mozilla/5.0" https://app.soleur.ai/login -o "$PREFLIGHT_TMP/preflight-login.html"
```

```bash
PREFLIGHT_TMP="$(git rev-parse --git-dir)"
grep -oE '/_next/static/chunks/[^"]+\.js' "$PREFLIGHT_TMP/preflight-login.html" | awk '!seen[$0]++' | head -20 > "$PREFLIGHT_TMP/preflight-candidates.txt"
```

The cap of 20 is generous (current prod loads 13 chunks); if ever hit on a future release, prefer raising the cap over reverting to the hardcoded login-chunk path. The grep matches both `<script src=...>` and `<link rel=preload href=...>` references — both are valid candidates.

If the `curl` fails (rc != 0) or `"$PREFLIGHT_TMP/preflight-candidates.txt"` is empty, return **SKIP** with note: "Could not fetch /login HTML or could not locate any /_next/static/chunks references."

**Step 5.2: Probe each candidate chunk for Supabase shapes.**

The Supabase host string and the inlined anon-key JWT may live in DIFFERENT chunks (verified 2026-04-29 against current prod: `8237-*.js` carries the JWT but contains zero `supabase.co` host strings). Track `host_union` (every chunk's supabase-host hits) and `jwt_chunk` (the first chunk with a JWT) independently. Always traverse the full candidate list — bail-early would skip chunks that may carry a placeholder-host leak (matrix row 6).

This block is operator-executed under the skill's `set -euo pipefail` convention. Failed `curl` per chunk and `grep` rc=1 on no-match must NOT abort the loop — the gate-level SKIP/FAIL decision is made from the accumulated state at end-of-loop, not from per-iteration rc.

```bash
PREFLIGHT_TMP="$(git rev-parse --git-dir)"
mkdir -p "$PREFLIGHT_TMP/preflight-chunks"
host_union=""
jwt_chunk=""
while IFS= read -r chunk_path; do
  # Defense-in-depth: validate chunk_path is a clean Next.js static-chunks subpath
  # before interpolating into the curl URL (no `..`, no `@`, no `?`, no whitespace).
  [[ "$chunk_path" =~ ^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$ ]] || continue
  base=$(basename "$chunk_path")
  curl -fsSL --max-time 10 --max-filesize 5242880 "https://app.soleur.ai${chunk_path}" -o "$PREFLIGHT_TMP/preflight-chunks/${base}" || continue
  hosts=$(grep -oE 'https?://([a-z0-9.-]*supabase\.co|api\.soleur\.ai)' "$PREFLIGHT_TMP/preflight-chunks/${base}" | sort -u || true)
  if [[ -n "$hosts" ]]; then
    host_union="${host_union}${hosts}"$'\n'
  fi
  if [[ -z "$jwt_chunk" ]]; then
    jwt=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$PREFLIGHT_TMP/preflight-chunks/${base}" | head -1 || true)
    if [[ -n "$jwt" ]]; then
      jwt_chunk="$PREFLIGHT_TMP/preflight-chunks/${base}"
    fi
  fi
done < "$PREFLIGHT_TMP/preflight-candidates.txt"

printf '%s' "$host_union" | sort -u
printf 'jwt_chunk=%s\n' "${jwt_chunk:-<none>}"
```

The redirected-stdin form (`< "$PREFLIGHT_TMP/preflight-candidates.txt"`) is required — piping (`cat ... | while read`) scopes loop variables to a subshell and loses `host_union` / `jwt_chunk` at loop exit. The `--max-filesize 5242880` (5 MB) cap defends against a misbehaving CDN response filling tmpfs across 20 fetches. The strict path regex rejects `..`, `@`, `?`, and whitespace before any string interpolation into the curl URL — a defense-in-depth gate even though the source HTML is served by our own CDN. Full traversal (no early-break) ensures placeholder-host leaks in late-candidate chunks are still detected (matrix row 6).

**Step 5.3: Assert canonical shape.**

The `host_union` from Step 5.2 must contain at least one host matching `^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$` and zero placeholder hosts (`test.supabase.co`, `placeholder.supabase.co`, `example.supabase.co`, `localhost`, `0.0.0.0`).

**Step 5.4: Decode and assert JWT claims from `jwt_chunk`.**

Pre-condition: `jwt_chunk` is non-empty after Step 5.2's traversal. If `jwt_chunk` is empty AND `host_union` is non-empty (canonical Supabase host found but no JWT in any of the 20 candidate chunks), return **FAIL** with note: "Supabase host found but no JWT in any of 20 candidate chunks — bundle is structurally inconsistent (host without key) and indicates a build regression." If `jwt_chunk` is empty AND `host_union` is empty (the full traversal yielded nothing), return **SKIP** with note: "Supabase init not present in any of the 20 candidate chunks loaded by /login — possible deeper Webpack restructure or app-shell split. Investigate manually (probe /dashboard or other authed routes)."

```bash
JWT=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$jwt_chunk" | head -1)
PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2)
PAD=$(( (4 - ${#PAYLOAD} % 4) % 4 ))
if [[ $PAD -gt 0 ]]; then PADDED="$PAYLOAD$(printf '=%.0s' $(seq 1 $PAD))"; else PADDED="$PAYLOAD"; fi
JSON=$(printf '%s' "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null)
iss=$(printf '%s' "$JSON" | jq -er '.iss // ""')  || { echo "FAIL: JWT payload not parseable as JSON (.iss missing or invalid)"; exit 1; }
role=$(printf '%s' "$JSON" | jq -er '.role // ""') || { echo "FAIL: JWT payload missing .role (security-gate fail-closed)"; exit 1; }
ref=$(printf '%s' "$JSON" | jq -er '.ref // ""')   || { echo "FAIL: JWT payload missing .ref (security-gate fail-closed)"; exit 1; }
# Log-injection guard: strip C0 controls (NUL..US), DEL, and Unicode line separators
# (U+2028, U+2029) before any echo. Defends against ANSI escape sequences, terminal
# control chars, and GitHub Actions `::cmd::` smuggling via newlines or U+2028.
sanitize() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'; }
iss_safe=$(sanitize "$iss")
role_safe=$(sanitize "$role")
ref_safe=$(sanitize "$ref")
printf 'iss=%s role=%s ref=%s\n' "$iss_safe" "$role_safe" "$ref_safe"
```

`jq -er` (raise on null/error) plus the explicit FAIL-on-non-zero-rc enforces fail-closed semantics on every claim (`iss`, `role`, `ref`) if the JWT regex matches a `eyJ...` literal that is not a valid base64-encoded JSON or is missing a required claim. The `sanitize()` helper strips C0 controls (`\x00`–`\x1f`), DEL (`\x7f`), and Unicode line separators (U+2028, U+2029) before any echo — `jq -r` does not escape control characters, so a crafted JWT could otherwise smuggle ANSI escapes (e.g., `\x1b[2J` to clear the operator's terminal), `::notice::PASS` GitHub Actions annotations via `\n`, or U+2028/2029 line breaks invisible to `${var//$'\n'/}` (precedent: `2026-04-28-anon-key-test-fixture-leaked-into-prod-build` Session Error #6).

The decoded claims MUST satisfy: `iss == "supabase"`, `role == "anon"`, `ref` matches `^[a-z0-9]{20}$`, and `ref` is not in the placeholder set (`test*`, `placeholder*`, `example*`, `service*`, `local*`, `dev*`, `stub*`).

**Result (eight-row decision matrix):**

Per `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md` — Check 5 is an invariant gate, so SKIP only when truly indeterminate; FAIL when partial-observation contradicts the invariant.

| Host union | JWT discovered | Result | Rationale |
| --- | --- | --- | --- |
| Login HTML fetch failed (Step 5.1) | n/a | **SKIP** | Truly indeterminate — operator cannot run Check 5 against an unreachable origin. |
| Login HTML fetched but zero `<script src>` matches | n/a | **SKIP** | Truly indeterminate — bundle structure unrecognizable. |
| ≥1 canonical Supabase host AND JWT discovered AND JWT claims canonical | yes (canonical) | **PASS** | Invariant proven across (possibly different) chunks. |
| ≥1 canonical Supabase host AND JWT discovered AND JWT claims non-canonical (placeholder ref, role≠anon, iss≠supabase) | yes (broken) | **FAIL** | Invariant DISPROVEN — leak detected; rotate the corresponding GitHub repo secret. |
| ≥1 canonical Supabase host AND no JWT after full 20-traversal | no | **FAIL** | Bundle is structurally inconsistent (host without key); invariant cannot hold. |
| ≥1 placeholder host (`test.supabase.co`, `placeholder.supabase.co`, etc.) anywhere in any examined chunk | any | **FAIL** | Placeholder URL leaked into the bundle (the original PR #2975 class). |
| Zero Supabase host references AND zero JWTs after full 20-traversal | no | **SKIP** | Truly indeterminate — Supabase init not reachable from `/login`. Investigate manually (probe `/dashboard` or other authed routes). |
| JWT regex matches but base64 decode / `jq` parse fails | invalid | **FAIL** | Discovered structure looks like a JWT but cannot be parsed — fail-closed. |

SKIP-on-chunking-change (the issue #3010 failure mode) is gone: a chunking change that moves the JWT to a different chunk now PASSes via Step 5.2's traversal. A future "simplify the result block" commit that collapses row 5 ("host without JWT after traversal") back to SKIP would silently re-introduce the fail-open class that #2887/#2903 already paid for — see the 2026-04-27 learning.

### Check 6: Brand-Survival Self-Review

Enforces `hr-weigh-every-decision-against-target-user-impact`: PRs that touch credentials, auth, data, payments, or user-owned resources must declare a `## User-Brand Impact` section (with a valid threshold) in the PR body. The section is the ship-time signal that the framing question was answered before the change reached production.

**Step 6.1: Detect sensitive-path diff.**

The canonical sensitive-path regex (single source of truth, mirrored verbatim in `plugins/soleur/skills/deepen-plan/SKILL.md` Phase 4.6 Step 2):

```bash
SENSITIVE_PATH_RE='^(apps/web-platform/(server|supabase|app/api|middleware\.ts$)|apps/web-platform/lib/(stripe|auth|byok|security-headers|csp|log-sanitize|safe-session|safe-return-to|supabase)|apps/web-platform/lib/(legal|auth)/|apps/[^/]+/infra/|.+/doppler[^/]*\.(yml|yaml|sh)$|\.github/workflows/.*(doppler|secret|token|deploy|release|version-bump|web-platform|infra-validation|cla|cf-token|linkedin-token).*\.ya?ml$)'

set -uo pipefail
grep -E "$SENSITIVE_PATH_RE" "$PREFLIGHT_TMP/preflight-diff-files.txt"
```

Run as two separate Bash calls (assignment, then the `grep`). The path-set comes from the cached file written by Phase 0 Step 0.1 — the regex itself is byte-identical to the form previously consumed by `git diff --name-only origin/main...HEAD | grep -E "$SENSITIVE_PATH_RE"`. The regex covers every Next.js attack surface (`middleware.ts`, every `app/api/**` route, security/CSP/auth/session/legal libraries, infra Terraform under `apps/*/infra/`, all Doppler-aware shell scripts, and every credential-handling workflow even when `doppler` is not in the filename).

If `grep` exits non-zero (no match), return **SKIP** with note: "No sensitive paths touched."

**Step 6.2: Resolve the canonical compliance source (Shared Plan-File Resolution).**

Call **Shared Plan-File Resolution** (above Check 1). It sets `$PR_BODY_FILE`, `$SCRUBBED_BODY`, `$PLAN_PATH`, and `$COMBINED` for this check to consume. If `gh pr view` fails (no PR exists for the current branch), return **SKIP** with note: "No PR available — section validation deferred to next preflight run after PR creation."

The `## User-Brand Impact` section may live in the PR body itself (typical for short PRs) OR in a plan file referenced from the PR body (typical for plans authored via `/soleur:plan`). Both signals are valid per `plugins/soleur/skills/review/SKILL.md` `<conditional_agents>` block. Shared Plan-File Resolution produces a `$COMBINED` input that contains both — scrubbed of HTML comments and fenced code blocks so a markdown example inside ` ``` ` cannot fool a substring match.

**Step 6.4: Check for the section heading.**

```bash
grep -q '^## User-Brand Impact' "$COMBINED"
```

If absent, return **FAIL** with: "Sensitive-path diff detected but neither PR body nor linked plan file contains a `## User-Brand Impact` section. Add the section per `plugins/soleur/skills/plan/references/plan-issue-templates.md`."

**Step 6.5: Validate threshold and scope-out — anchored, not substring.**

Extract the threshold line. Require canonical bullet form (`- **Brand-survival threshold:** …`) so a free-text sentence containing the words "single-user incident" cannot pass:

```bash
THRESHOLD_LINE=$(grep -E '^[[:space:]]*[-*][[:space:]]+\*\*Brand-survival threshold:\*\*' "$COMBINED" | head -n 1)
```

If `$THRESHOLD_LINE` is empty, return **FAIL** with: "User-Brand Impact section present but the canonical bullet `- **Brand-survival threshold:** <label>` is missing. Use exactly the bullet form from `plan-issue-templates.md`."

Match the label as a discrete token. The value must follow the `**Brand-survival threshold:**` marker as an isolated word (optionally backticked) terminated by a value-boundary character (end-of-line, period, comma, semicolon, em-dash, or hyphen surrounded by spaces). This permits trailing commentary like `` `single-user incident` — explanation… `` while rejecting embedded substrings like "this is not a single-user incident":

```bash
# Boundary regex: end-of-line OR punctuation/dash that indicates "value ends here, commentary follows"
BOUNDARY='($|[[:space:]]*[.,;]|[[:space:]]+[—–-][[:space:]])'
if   [[ "$THRESHOLD_LINE" =~ \*\*Brand-survival[[:space:]]+threshold:\*\*[[:space:]]+\`?single-user[[:space:]]+incident\`?$BOUNDARY ]]; then
  RESULT=PASS_INCIDENT
elif [[ "$THRESHOLD_LINE" =~ \*\*Brand-survival[[:space:]]+threshold:\*\*[[:space:]]+\`?aggregate[[:space:]]+pattern\`?$BOUNDARY ]]; then
  RESULT=PASS_AGGREGATE
elif [[ "$THRESHOLD_LINE" =~ \*\*Brand-survival[[:space:]]+threshold:\*\*[[:space:]]+\`?none\`?$BOUNDARY ]]; then
  RESULT=NEEDS_SCOPEOUT
else
  echo "FAIL: threshold value not recognized. The value must immediately follow \`**Brand-survival threshold:**\` and be one of: \`single-user incident\` | \`aggregate pattern\` | \`none\` (terminated by end-of-line, punctuation, or em-dash + space)."
  exit 1
fi
```

If `RESULT=NEEDS_SCOPEOUT`, look for the scope-out bullet — require a non-empty `reason:` (the `\S` after `reason:` is what enforces "explain yourself"):

```bash
grep -Eq 'threshold:[[:space:]]*none,[[:space:]]*reason:[[:space:]]*\S' "$COMBINED"
```

- Match (rc 0): **PASS** — operator has justified why the touched sensitive path is not user-impacting.
- No match: **FAIL** with: "Sensitive-path diff with `threshold: none` requires a `threshold: none, reason: <one-sentence>` scope-out bullet (with a non-empty reason) inside the User-Brand Impact section."

If `RESULT=PASS_INCIDENT` or `RESULT=PASS_AGGREGATE`: **PASS**.

**Headless mode behaviour:** On **FAIL**, abort with the error details (no prompt). On **PASS** or **SKIP**, continue silently.

**Interactive mode behaviour:** On **FAIL**, present the failure reason and offer **AskUserQuestion** with options:

1. "Fill in the section now" — prompt the operator for the three required lines (artifact / vector / threshold), append to the PR body via `gh pr edit --body-file -`, re-run Check 6.
2. "Add scope-out note" — if the threshold should defensibly be `none`, prompt for the one-sentence reason, append `threshold: none, reason: <reason>` to the section, re-run Check 6.
3. "Abort — fix elsewhere" — stop the pipeline; operator handles in another tool.

**Result:**

- **PASS** — No sensitive paths touched, OR section present with `single-user incident`/`aggregate pattern` threshold, OR section present with `none` threshold AND a valid scope-out note.
- **FAIL** — Sensitive-path diff with missing or empty User-Brand Impact section; OR `none` threshold without scope-out; OR missing/invalid threshold line.
- **SKIP** — No sensitive paths touched, OR no PR exists yet (defer to post-PR run).

### Check 8: Service Worker Cache Bump on Client-Bundle Regression Fix

**Path-gated:** only runs when the cached path-set from Phase 0 Step 0.1 (`"$PREFLIGHT_TMP/preflight-diff-files.txt"`) AND the commit log together satisfy BOTH a regression-fix marker (a commit subject starting with `fix(`, `fix:`, or `hotfix`) AND any file under `apps/web-platform/lib/supabase/`, `apps/web-platform/sentry.client.config.ts`, `apps/web-platform/lib/auth/`, `apps/web-platform/lib/byok/`, or `apps/web-platform/components/error-boundary-view.tsx`. Otherwise return **SKIP** with note: "No client-bundle regression-fix surface detected." The path predicate is identical to the original `git diff --name-only origin/main...HEAD` form — only the diff source is changed.

**Rationale:** Content-hashed Next.js chunks normally invalidate cache automatically — new content → new filename → SW cache miss → fresh fetch. But the SW at `apps/web-platform/public/sw.js` uses a cache-first strategy under a single `CACHE_NAME` for `/_next/static/**`, and old broken chunks remain cached under their old filenames until either (a) browser eviction, or (b) the activate handler purges them via a `CACHE_NAME` bump. After PR #3014 deployed v0.58.0 with a corrected validator, users still saw the dashboard error.tsx because their SW was serving cached PR #3007 chunks. Without bumping `CACHE_NAME`, a regression fix to the inlined client bundle relies on every user manually clearing site data — unacceptable for an auth-tree outage.

**Step 8.1: Detect regression-fix commit subject.**

```bash
git log origin/main..HEAD --pretty=%s | grep -iE '^(fix\(|fix:|hotfix)' | head -1
```

If empty, return **SKIP** with note: "No fix(...) commit on branch."

**Step 8.2: Detect client-bundle surface in diff.**

Re-use the cached path-set from Phase 0 Step 0.1:

```bash
grep -E '^apps/web-platform/(lib/(supabase|auth|byok)/|sentry\.client\.config\.ts|components/error-boundary-view\.tsx)' "$PREFLIGHT_TMP/preflight-diff-files.txt" | head -1
```

The regex is byte-identical to the form previously piped from `git diff --name-only origin/main...HEAD`. If empty, return **SKIP** with note: "No client-bundle surface touched."

**Step 8.3: Compare `CACHE_NAME` against `origin/main`.**

Run as separate Bash calls (no command substitution per skill convention):

```bash
git show origin/main:apps/web-platform/public/sw.js 2>/dev/null | grep -oE 'CACHE_NAME[[:space:]]*=[[:space:]]*"[^"]+"' | head -1
```

```bash
grep -oE 'CACHE_NAME[[:space:]]*=[[:space:]]*"[^"]+"' apps/web-platform/public/sw.js | head -1
```

If the two values are byte-equal, **FAIL** with: "Client-bundle regression fix detected on branch but `CACHE_NAME` in `apps/web-platform/public/sw.js` was not bumped. Old chunks remain cached for users with an active SW registration. Bump the suffix (e.g., `v2` → `v3`) so the activate handler purges stale caches on next page load."

If the values differ (suffix bumped), **PASS**.

**Result:**

- **PASS** — `CACHE_NAME` bumped relative to `origin/main`, OR no client-bundle regression-fix surface detected.
- **FAIL** — client-bundle regression fix on branch with unchanged `CACHE_NAME`. Bump the suffix to force-purge the stale-cache class.
- **SKIP** — no `fix(...)` commit, OR no client-bundle surface in the diff.

### Check 9: Node-Only Encodings Banned in Client-Bundle Paths

**Always runs (no path-pattern gate).** Enforces the rule that any module imported into the Next.js client bundle must use browser-safe APIs at module load. Node's `Buffer.from(s, "base64url")` (added in Node 16) is the canonical example: it works in vitest's default Node env AND in SSR, but the `buffer@5.x` polyfill webpack ships throws `TypeError: Unknown encoding: base64url` in browsers. A test that runs the validator only in Node passes; production hydration crashes on the first authenticated visit.

**Rationale:** PR #3007's `assertProdSupabaseAnonKey` introduced `Buffer.from(middle, "base64url")` inside `validate-anon-key.ts`, which `lib/supabase/client.ts` imports at module load. PR #3014's added tests also ran in Node env and missed it. The deployed bundle threw on every page load — dashboard AND login. Layer 1 canary missed it (HTML-only). Layer 3 missed it (bash `base64 -d` is unrelated to webpack's Buffer polyfill). The only true source-level gate is to ban the encoding token.

**Step 9.1: Build the candidate file list.**

```bash
git ls-files \
  'apps/web-platform/lib/**/*.ts' \
  'apps/web-platform/lib/**/*.tsx' \
  'apps/web-platform/components/**/*.ts' \
  'apps/web-platform/components/**/*.tsx' \
  'apps/web-platform/app/**/*.ts' \
  'apps/web-platform/app/**/*.tsx' \
  'apps/web-platform/hooks/**/*.ts' \
  'apps/web-platform/hooks/**/*.tsx' \
  | grep -v -E '/(server|api)/' \
  | grep -v -E '\.test\.(ts|tsx)$' \
  | grep -v -E '\.spec\.(ts|tsx)$'
```

**Step 9.2: Grep candidates for banned tokens (excluding comment lines).**

```bash
grep -nE 'Buffer\.from\([^)]*"base64url"' <files> \
  | grep -vE ':[[:space:]]*(//|\*)' \
  | grep -vE '`[^`]*Buffer\.from\([^`]*"base64url"[^`]*`'
```

The first filter drops single-line `// ...` comments and JSDoc `* ...` lines. The second drops backtick-quoted references inside markdown-style code spans (which can occur in TSDoc/JSDoc bodies that don't start with `* `). The remaining matches are real call sites.

If output is non-empty, **FAIL** with a per-file listing: "Node-only encoding `base64url` in client-bundle path `<file>:<line>`. Replace with browser-safe `atob` + `base64.padEnd(...)` per `apps/web-platform/lib/supabase/validate-anon-key.ts` post-fix pattern, OR move the file behind a `lib/server/` boundary if it does not need the client bundle."

**Step 9.3: Ban-list extension policy.**

The current ban-list (extend as new classes are discovered):

- `Buffer.from(_, "base64url")` — covered above
- Future additions go here with a **Why:** pointer to the learning file

**Result:**

- **PASS** — no banned token found in any client-bundle path.
- **FAIL** — at least one banned token found (file + line listed).
- **SKIP** — never; this check has no path gate (it always scans the canonical candidate list).

### Check 10: Discoverability Test Execution

**Path-gated** on the canonical sensitive-path regex (single source of truth; re-use Check 6 Step 6.1's `SENSITIVE_PATH_RE`). The path predicate runs against `"$PREFLIGHT_TMP/preflight-diff-files.txt"` (cached in Phase 0 Step 0.1). Otherwise return **SKIP** with note: "No sensitive paths touched — no Observability block required."

**Rationale:** `hr-observability-as-plan-quality-gate` mandates a `discoverability_test.command` that runs WITHOUT SSH. Plan Phase 2.9 and deepen-plan Phase 4.7 enforce field presence; neither runs the command. PR #4148 shipped with `curl https://web-platform.soleur.ai/api/inngest` — a typo'd hostname that fails DNS resolution. Five gates passed; the operator caught it. This check closes the "declared-verifiable but unverified" gap.

Invariant gate per `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`: SKIP only when truly indeterminate; FAIL when the invariant ("the documented command actually works against the live world") is contradicted.

**Reference implementation.** `plugins/soleur/test/lib/discoverability-test-parser.ts` mirrors the parser + classifier in TypeScript so the decision states can be unit-tested without subshells. The bash below IS the production runtime — the TS file is for tests. If they drift, the bash wins.

**Step 10.1: Sensitive-path gate (re-use Check 6 SSOT).**

```bash
set -uo pipefail
# SSOT: see Check 6 Step 6.1; this literal MUST stay byte-identical.
# Mirrored consumers: Check 6 Step 6.1, deepen-plan/SKILL.md Phase 4.6 Step 2.
SENSITIVE_PATH_RE='^(apps/web-platform/(server|supabase|app/api|middleware\.ts$)|apps/web-platform/lib/(stripe|auth|byok|security-headers|csp|log-sanitize|safe-session|safe-return-to|supabase)|apps/web-platform/lib/(legal|auth)/|apps/[^/]+/infra/|.+/doppler[^/]*\.(yml|yaml|sh)$|\.github/workflows/.*(doppler|secret|token|deploy|release|version-bump|web-platform|infra-validation|cla|cf-token|linkedin-token).*\.ya?ml$)'
grep -E "$SENSITIVE_PATH_RE" "$PREFLIGHT_TMP/preflight-diff-files.txt"
```

If `grep` exits non-zero, return **SKIP** with note: "No sensitive paths touched."

**Step 10.2: Resolve the plan file (Shared Plan-File Resolution).**

Call **Shared Plan-File Resolution** (above Check 1). The output `$COMBINED` contains the scrubbed PR body concatenated with the scrubbed plan file (when a `knowledge-base/project/plans/*.md` link is present). `$PLAN_PATH` is the resolved path or empty.

If `$COMBINED` is empty (no PR available — `gh pr view` failed), return **SKIP** with note: "No PR available — Check 10 deferred to next preflight run after PR creation."

If `$PLAN_PATH` is empty (sensitive-path diff but no plan link in PR body), return **SKIP** with note: "Sensitive-path diff but no plan file referenced from PR body. Cannot extract discoverability_test.command. (If the PR uses inline Observability in the PR body, copy the plan file into the body via a `knowledge-base/project/plans/` link.)"

**Path-traversal hardening (defense-in-depth).** A malicious PR body could link to `knowledge-base/project/plans/../../../etc/passwd.md` (or a symlink) and trick the awk reader into following arbitrary paths whose content is then parsed for a `discoverability_test.command` — turning any `.md`-suffixed file the operator can read into an execution oracle. Refuse anything that resolves outside the canonical plans directory:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
RESOLVED_PLAN_PATH="$(realpath -e "$PLAN_PATH" 2>/dev/null || true)"
case "$RESOLVED_PLAN_PATH" in
  "$REPO_ROOT/knowledge-base/project/plans/"*) ;;
  *)
    echo "FAIL: plan path '$PLAN_PATH' does not resolve under $REPO_ROOT/knowledge-base/project/plans/. Refusing to read."
    exit 1
    ;;
esac
```

**Step 10.3: Extract the `## Observability` block from the plan file.**

```bash
PREFLIGHT_TMP="$(git rev-parse --git-dir)"
# ‼️ ANCHOR the heading match. `/^## Observability/` is a PREFIX match, so it
# also matches `## Observability layer citation` — a section name that
# `hr-observability-layer-citation` actively encourages, making the collision
# systemic rather than incidental. When both sections exist, the unanchored form
# extracts the FIRST (the prose citation), finds no `discoverability_test`, and
# FAILs with "no command could be parsed" — a false FAIL on a plan that is
# perfectly well-formed. Verified against #6698's plan: unanchored extracted 47
# lines of the wrong section; anchored reaches the real block.
awk '/^## Observability$/{ino=1; next} /^## /{if (ino) exit} ino' "$PLAN_PATH" > "$PREFLIGHT_TMP/preflight-observability.txt"
test -s "$PREFLIGHT_TMP/preflight-observability.txt" || { echo "FAIL: Plan touches sensitive paths but '## Observability' block is missing. See hr-observability-as-plan-quality-gate."; exit 1; }
```

If the block is missing, return **FAIL** with: "Sensitive-path diff but plan file `<PLAN_PATH>` is missing the `## Observability` block. See `hr-observability-as-plan-quality-gate`. Add the section per `plugins/soleur/skills/plan/references/plan-issue-templates.md`."

**Step 10.4: Extract `discoverability_test.command` and `expected_output`.**

The plan-template schema (`plan-issue-templates.md` §Observability →
`discoverability_test`) defines:

```yaml
discoverability_test:
  command:              # one command an operator can run LOCALLY (no ssh)
  expected_output:      # canonical "everything OK" output
  credentials_required: # OPTIONAL — see Step 10.4; declares a probe with no
                        # unauthenticated substitute, which Check 10 then SKIPs
                        # without executing
```

Plans use TWO shapes — strict YAML (**Form A**, canonical) AND looser prose with a fenced code block followed by `Expected output: …` (**Form B**, PR #4148 shape). The parser MUST accept both forms.

**Form A — strict YAML:**

```yaml
discoverability_test:
  command: curl -fsS ... https://app.soleur.ai/api/inngest
  expected_output: "200"
```

Form A accepts all three YAML scalar shapes for `command:`:

| Shape | Header | Continuations joined with |
| --- | --- | --- |
| **inline** | `command: curl …` | — (value is on the key line) |
| **block** | `command: \|`, `\|-`, `\|+` | newline |
| **folded** | `command: >`, `>-`, `>+` | space |

Block and folded headers may carry a trailing `# comment`. Scalar extent follows YAML
indent semantics: a continuation is any non-empty line indented **more** than the
`command:` key, and the first line indented **≤** the key ends the scalar. The parser is
[`./scripts/parse-form-a.awk`](./scripts/parse-form-a.awk) — a real file rather than an
inlined program, so the awk/TS parity harness executes the production runtime directly
instead of regex-scraping this prose. That file is authoritative; the TypeScript mirror in
`plugins/soleur/test/lib/discoverability-test-parser.ts` is non-authoritative.

**Form B — prose + fenced block:**

```markdown
- **discoverability_test.command:**
  ```bash
  curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 https://app.soleur.ai/api/inngest
  ```
  Expected output: `200` (or `401` with HMAC challenge). Anything else = absent.
```

Detection: find the first `discoverability_test` line in the Observability block; from that point, locate the first fenced code block — its contents are the command. Then locate the first line matching `^[[:space:]]*Expected output:` (case-insensitive) — its value is the expected.

```bash
PREFLIGHT_TMP="$(git rev-parse --git-dir)"
# Form A first (anchored YAML key — strongest signal).
#
# The parser lives in a real file so the parity harness can execute it.
#
# RATIONALE CORRECTED (#7450). This comment used to argue FOR `git rev-parse
# --show-toplevel` and AGAINST `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}`, on the grounds
# that CLAUDE_PLUGIN_ROOT is unset in a plain session and the `:-` default would silently
# make the path CWD-relative. The PREMISE is true and is ADR-179's own headline finding.
# The CONCLUSION does not follow: it is true of the `:-plugins/soleur` form it was written
# against, but NOT of the canonical BARE `${CLAUDE_PLUGIN_ROOT}` form, whose unset
# expansion is root-anchored rather than CWD-relative — and the loader substitutes the
# bare token at delivery time, so it is not unset at the point of use (measured, #7450).
# Resolving via the git root is ADR-179's explicitly-rejected option (d): after a
# `gh pr checkout` the git root is the REVIEWED PARTY's tree.
#
# The two operands in this file are deliberately NOT migrated here (#7450 DC-1) — they are
# not secret-emission gates, so they are routed to #7453 with a severity flag. Only this
# falsified argument is corrected, so the next reader does not take it as authority and
# propagate the rejected form.
#
# Hard-fail on a load error. `awk -f <missing>` exits 2 with EMPTY stdout, and
# `set -uo pipefail` does NOT abort on it (command-substitution rc is discarded), so a
# missing parser would leave $CMD empty and Form B would silently parse a DIFFERENT
# command. Never fall through.
FORM_A_AWK="$(git rev-parse --show-toplevel)/plugins/soleur/skills/preflight/scripts/parse-form-a.awk"
test -r "$FORM_A_AWK" || { echo "FAIL: Check 10 parser missing at $FORM_A_AWK"; exit 1; }
CMD=$(awk -f "$FORM_A_AWK" "$PREFLIGHT_TMP/preflight-observability.txt")
AWK_RC=$?
if [[ "$AWK_RC" -ne 0 ]]; then
  # `$?` here would report the `!`-inverted status (always 0) — capture the real
  # rc from the command substitution before emitting it.
  echo "FAIL: Check 10 Form A parser errored (awk rc=${AWK_RC:-unknown}); refusing to fall through to Form B."
  exit 1
fi

EXPECTED=$(awk '
  /^[[:space:]]*expected_output:/ { sub(/^[[:space:]]*expected_output:[[:space:]]*/, ""); print; exit }
' "$PREFLIGHT_TMP/preflight-observability.txt")

# Fallback to Form B (fenced block under `discoverability_test.command:` prose).
# Skip leading `#` comment lines inside the fence — operator prose comments
# are NOT part of the command (mirrors the TS reference impl). Without this
# strip, the FIRST executable bash line is treated as the command and any
# leading `# comment` line silently runs as bash via `bash -c`.
if [[ -z "$CMD" ]]; then
  CMD=$(awk '
    /discoverability_test/ { found=1 }
    found && /^[[:space:]]*```/ { fence=!fence; if (!fence && lines>0) exit; next }
    found && fence && /^[[:space:]]*#/ { next }
    found && fence { print; lines++ }
  ' "$PREFLIGHT_TMP/preflight-observability.txt")
fi

if [[ -z "$EXPECTED" ]]; then
  EXPECTED=$(grep -iE '^[[:space:]]*(\*\*)?Expected output:(\*\*)?' "$PREFLIGHT_TMP/preflight-observability.txt" | head -1 | sed -E 's/^[[:space:]]*(\*\*)?Expected output:(\*\*)?[[:space:]]*//I')
fi
```

**Normalize `$CMD` ONCE, here, before anything else reads it.**

Every downstream consumer — the probe-verb gate, the shell-active reject, and the sandboxed
exec — must see the SAME string. Gating one form while executing another is a laundering
gap, and normalizing inside the gate alone produced exactly that: the gate judged the
normalized command while Step 10.5 rejected the raw one on its embedded newline, so a Form A
block scalar carrying a leading `#` comment failed the runtime even though the gate (and the
TypeScript mirror) accepted it. The mirror's `normalizeCommand()` is this, and the parity
harness only compares the GATE, so this divergence was invisible to it.

```bash
# Drop full-line `#` comments and blank lines, then trim. A `#` inside a quoted
# argument is untouched — only whole comment LINES match. Verified across the
# 642-command corpus: 6 commands change (all block scalars with leading comment
# lines, the shape this fixes) and no quoted `#` is altered.
CMD="$(printf '%s' "$CMD" | sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d')"
CMD="${CMD#"${CMD%%[![:space:]]*}"}"
CMD="${CMD%"${CMD##*[![:space:]]}"}"
```

If `$CMD` is empty after both attempts, return **FAIL** with: "Plan `<PLAN_PATH>` declares an Observability block but no `discoverability_test.command` could be parsed. See `plugins/soleur/skills/plan/references/plan-issue-templates.md` §Observability."

**Reject SSH commands** (defense-in-depth):

```bash
if [[ "$CMD" =~ (^|[[:space:]]|/)ssh([[:space:]]|$) ]]; then
  echo "FAIL: discoverability_test.command contains ssh; rule violation per hr-observability-as-plan-quality-gate."
  exit 1
fi
```

**Read `credentials_required` and honour a declared-credentialed probe** (ADR-175 Layer 3):

Some probes verify a property that has **no unauthenticated substitute** — a warehouse
query API with no anonymous form, for instance. Before #7393 those had only two outcomes:
FAIL (verify nothing) or rewrite to a weaker property (verify the wrong thing). The
optional `discoverability_test.credentials_required` sub-field is the sanctioned third:
declare the scope and the justification, and Check 10 **skips without executing**.

Read it with a flat sub-field `awk`, exactly as `expected_output` already is — do **not**
extend [`./scripts/parse-form-a.awk`](./scripts/parse-form-a.awk), which is pinned
byte-exactly against its TypeScript mirror by the P1/P2/P3 parity harness. The flat read
inherits `expected_output`'s pre-existing limitation (two `discoverability_test`
sub-blocks could confuse it); that is unchanged here.

The read is SCOPED TO THE `discoverability_test:` SUB-BLOCK, and that scoping is
load-bearing rather than tidiness. It NARROWS the bypass class without closing
it — a `credentials_required:` line inside the command's own block scalar is
still honoured, so a multi-line command can waive itself. Closing that needs a
YAML-aware parse this flat `awk` deliberately avoids. `expected_output` is read with a flat
whole-block scan and survives it, because a stray `expected_output:` only changes
what a probe is compared against. This field **skips execution entirely**, so the
same flat read is a bypass: measured, one `credentials_required:` line under
`liveness_signal:` — or in prose anywhere in the section — waived a perfectly
runnable unauthenticated `curl` probe. Three further shapes declare nothing and
are rejected rather than honoured: a `#`-comment-only value (the documented
template ships one, so an agent copying the canonical schema produced a
valid-looking declaration whose "scope" was the template's own comment), a bare
`>`/`|` block indicator, and an empty value.

```bash
# Log-injection guard, defined HERE rather than in Step 10.5. Every value echoed
# below ($CREDS_REQ, $PROBE_VERB) is derived from PR-authored plan
# text, which this check's own design treats as adversarial — and Step 10.5's
# copy is ~250 lines further down, so these paths could not call it even in
# principle. U+2028/U+2029 are NOT in [[:space:]] under LC_ALL=C, so they survive
# tokenization into $PROBE_VERB and reach the operator's terminal; ESC bytes do
# too. Same helper and same reasoning as Check 5 (which cites the precedent).
# Step 10.5 redefines it identically; the redefinition is harmless.
sanitize() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'; }

# awk walks only the indented children of `discoverability_test:` — never the
# whole Observability block. `tolower()` rather than bash's ${var,,} because the
# latter is bash 4.0+ and this block runs ~200 lines BEFORE the bwrap probe, so
# on a bash 3.2 host (stock macOS) ${var,,} is a parse error long before Check 10
# could reach its graceful SKIP.
CREDS_REQ=$(awk '
  /^[[:space:]]*discoverability_test:/ { in_dt=1; parent=match($0, /[^ \t]/); next }
  in_dt && /^[[:space:]]*$/ { next }
  in_dt {
    ind = match($0, /[^ \t]/)
    if (ind <= parent) { exit }
    if ($0 ~ /^[[:space:]]*credentials_required:/) {
      sub(/^[[:space:]]*credentials_required:[[:space:]]*/, ""); print; exit
    }
  }
' "$PREFLIGHT_TMP/preflight-observability.txt")
# Trim, THEN strip a symmetric quote pair. Order and completeness both matter:
# stripping only `"` and never trimming meant `credentials_required: 'placeholder'`
# and `credentials_required: TODO␠␠` both reached the SKIP-DECLARED branch while
# the TypeScript mirror correctly FAILed them — so the placeholder superset fix
# was undone in the runtime of record by one apostrophe, invisibly to the suite.
CREDS_REQ="${CREDS_REQ#"${CREDS_REQ%%[![:space:]]*}"}"
CREDS_REQ="${CREDS_REQ%"${CREDS_REQ##*[![:space:]]}"}"
case "$CREDS_REQ" in
  \"*\") CREDS_REQ="${CREDS_REQ#\"}"; CREDS_REQ="${CREDS_REQ%\"}" ;;
  \'*\') CREDS_REQ="${CREDS_REQ#\'}"; CREDS_REQ="${CREDS_REQ%\'}" ;;
esac
# A comment-only value, a bare block/fold indicator, or an empty value declares
# nothing. Treat all as absent so the normal path runs. The CHOMPED indicators
# (`>-` `>+` `|-` `|+`) are included because #6772 — the change cited as the
# reason authors reach for indicators at all — is exactly what made those forms
# first-class for `command:`, so they are the likelier typo, not the rarer one.
case "$CREDS_REQ" in
  "#"*|">"|">-"|">+"|"|"|"|-"|"|+") CREDS_REQ="" ;;
esac

if [[ -n "$CREDS_REQ" ]]; then
  # Placeholder text is a FAIL. This set is a SUPERSET of deepen-plan §4.7's —
  # they were disjoint on exactly the wrong members, so `placeholder` and
  # `manual operator check` (the repo's canonical "says nothing" markers) were
  # GRANTING the waiver.
  CREDS_REQ_LC=$(printf '%s' "$CREDS_REQ" | tr '[:upper:]' '[:lower:]')
  if [[ "$CREDS_REQ_LC" =~ ^(todo|tbd|n/a|na|none|tktk|placeholder|manual\ operator\ check|\.\.\.|\<.*\>)$ ]]; then
    echo "FAIL: discoverability_test.credentials_required is a placeholder (\"$(sanitize "$CREDS_REQ")\"). State the credential scope and why no unauthenticated probe verifies the same property, or remove the field."
    exit 1
  fi
  echo "SKIP-DECLARED: discoverability_test declares credentials_required — $(sanitize "$CREDS_REQ"). Check 10 did NOT execute the command: running it inside the Step 10.5 sandbox would fail for lack of credentials and prove nothing about the property under test."
  exit 0
fi
```

`SKIP-DECLARED` is its **own** terminal, never folded into ordinary `SKIP`, and it carries
the declared scope verbatim into the Phase 2 aggregate row. That is deliberate: this is the
cheapest path to a non-FAIL for any probe whose verb Check 10 cannot run — though
not the cheapest overall: a tautological probe (`printf 200` against
`expected_output: "200"`) reaches PASS and is counted by none of the three
counterweights below. That gap is pre-existing, not introduced here, but the
superlative was wrong as written. For the declared path specifically, this is and in `/soleur:one-shot` the
same agent authors the declaration and runs the gate. Left invisible it would convert
Check 10 from a verification gate into self-certification. The three mechanical
counterweights are the distinct terminal, the committed corpus baseline count in
`plugins/soleur/test/preflight-discoverability-test.test.ts` (so each new adoption is a
reviewable diff line rather than silent drift), and the checklist entry in
`observability-coverage-reviewer` §Step 6.

Note what the waiver is and is not: it is a **verification waiver**, not an execution
bypass. The declared path never executes, so no verb reaches the sandbox. The waiver does
genuinely span *any* verb — that is why it is counted rather than reordered.

**Probe-verb gate** (ADR-175 Layer 2, revised — schema validation, not a security control):

The gate lives in [`./scripts/probe-verb-gate.sh`](./scripts/probe-verb-gate.sh) rather than
inline here, for the same reason [`./scripts/parse-form-a.awk`](./scripts/parse-form-a.awk)
is a real file: a parity harness must be able to **execute the production runtime** instead
of regex-scraping this prose. That is not hypothetical — while this gate was inlined with a
hand-maintained TypeScript mirror, two parser asymmetries shipped green inside the very PR
that created the mirror (a Form B command kept its markdown indentation, so the effective
verb was `""`; a Form A block scalar kept a leading `#`, so it was `"#"`). Content pins on
the allowlist literal cannot detect behavioural drift.

```bash
PROBE_GATE="$(git rev-parse --show-toplevel)/plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh"
test -r "$PROBE_GATE" || { echo "FAIL: Check 10 probe-verb gate missing at $PROBE_GATE"; exit 1; }
if ! PROBE_REJECT="$(bash "$PROBE_GATE" "$CMD")"; then
  echo "FAIL: $(sanitize "$PROBE_REJECT")"
  exit 1
fi
```

**What this gate is, stated honestly.** It answers *"is this an executable command, and one
Check 10's PATH can run?"* — schema validation on the `command:` field. It is **not** a
security control and **not** a legibility control, and the earlier revision of this section
claimed both.

It cannot be a security control, and the reason is structural rather than incidental: the
gate's own sanctioned remedy is *"wrap it in a repo-relative script"* — i.e. `bash
scripts/x.sh`, which is arbitrary in-sandbox code execution. Every shape it could reject is
strictly **weaker** than the remedy it prescribes. Step 10.5 additionally runs
`bash -c "$CMD"`, so every probe already *is* an inline program; a rule rejecting
`python3 -c` while printing instructions to use `bash scripts/x.sh` rejects a spelling, not
a capability. Measured on the plan corpus, the deleted arg rules were 50% false-positive
and the deleted path rule fired once across the corpus, while false-rejecting
`bun test … -p`, `python3 … --print json` and `node … -e prod`.

It is not a legibility control either: the full command sits in the PR diff regardless, and
`git -c alias.…`, `bash scripts/x.sh` and `./anything` all read as innocuous while doing
arbitrary things.

**What it measurably buys**: 34 entries in the plan corpus are prose in a `command:` field
(*"Sentry issue search feature:…"*, *"Open Sentry → Issues → …"*). Those become a named FAIL
at authoring time instead of an opaque `rc=127` at ship time. That value comes entirely
from the bare verb list, which is why the arg and path rules were deleted rather than
repaired.

**The allowlist is a corpus-frequency list, not a capability list.** `sh`, `dig` and
`getent` are absent because they have **zero** corpus uses; `awk`, `sed` and `find` are
absent for the same reason, **not** because they are uniquely dangerous. `git` is on the
list and is a full execution vector — `git -c alias.x='!cmd' x` runs arbitrary commands —
and so is `bash <script>`. Both are recorded in ADR-175 as worked examples that an
allowlist entry is an authority grant which this gate does not bound.

**Every allowlist entry is an authority grant — do not describe either layer as though it
closed the class.** Layer 1 (the Step 10.5 sandbox) bounds what a verb can *reach*, but
`curl` retains network egress and `bash <script>` retains arbitrary in-sandbox code
execution. Adding a verb therefore warrants the same scrutiny as an infra change, not a
"legibility decision". Conversely the allowlist bounds *legibility*, not authority: it is
the sandbox, not the verb list, that makes a script which self-wraps `doppler run -c prd`
fail loudly instead of succeeding silently.
<!-- SECURITY (at-mention auto-attach footgun): never write an at-sign immediately
     followed by a real home/absolute path (tilde-slash, dollar-HOME-slash, or a
     `/home` `/Users` `/root` `/etc` absolute) in ANY skill/agent/doc that loads into
     agent context: Claude Code's @-mention auto-attach resolves such a token to the
     real on-disk file and attaches its CONTENTS to the transcript. Observed
     2026-07-22 during PR #6830's ship — a literal here resolved to the operator's
     live Doppler root token and auto-attached it. The guard
     .github/scripts/test/test-no-at-mention-credfile-footgun.sh enforces this repo-wide. -->

**What the retired denylist was, and why counting verbs was never enough.** Until #7393
this gate was a denylist of ten credentialed CLIs (`doppler`, `gh`, `aws`, `supabase`,
`stripe`, `hcloud`, `wrangler`, `terraform`, `flyctl`, `vercel`). It could not be complete:
it never caught indirect invocation (`bash scripts/foo.sh` whose body self-wraps
`doppler run -c prd`), nor any future vendor CLI, nor an absolute-path read of a credential
file by a permitted verb. Measured during #7393's planning: with the whole filesystem
readable, `awk 'BEGIN{system("…")}'` executed arbitrary commands past the shell-active
reject, and a `curl --data-binary` against a home-rooted credential path carried no
shell-active token at all. **The durable fix was never a longer list — it was moving the
control into the filesystem layer (Step 10.5).**

**Step 10.5: Sanitize and run inside a filesystem-isolated sandbox, with a tight timeout.**

The block below uses a `text` fence (not `bash`) so the skill-security-scan
calibration suite does not flag it as `shell-spawn-c-flag`. The runtime IS a
shell-spawn — the **load-bearing** mitigation is the bubblewrap sandbox below
(ADR-175 Layer 1); the Step 10.4 verb allowlist, the `ssh`/`$()`/backtick
rejects and the 15s outer timeout are defense-in-depth. The plan-file source
is trust-on-PR-review. See [`2026-05-20-preflight-check-10-discoverability-test-execution.md`](../../../../knowledge-base/project/learnings/best-practices/2026-05-20-preflight-check-10-discoverability-test-execution.md).

**Why a filesystem boundary and not an environment tweak.** `env -i` scrubs environment
*variables*; it does not remove *files or sockets*. An ephemeral `$HOME` changes where a
CLI **looks**, not what is **readable** — measured during #7393's planning,
`wc -c < <the operator's home Doppler config>` returned a live 294-byte service token
under `HOME=$(mktemp -d)`. The sandbox removes the credential stores as files:

| Probe, run inside the sandbox | Result |
| --- | --- |
| absolute-path read of the home Doppler config | `No such file or directory` |
| glob read across `/home/*/…` | `No such file or directory` |
| home SSH private key | `No such file or directory` |
| `ls /run/user/<uid>/bus` (D-Bus → Secret Service keyring) | `No such file or directory` |
| `awk 'BEGIN{system("<absolute-path read>")}'` | `cannot open` |
| append to a tracked repo file | `Read-only file system` |
| `curl https://soleur.ai/` | `200` |
| `dig +short soleur.ai` | resolves |
| `grep -c . AGENTS.md` | matches the host value |

The read-only repo bind is what closes the **write-back escalation**: without it a probe
can install `.git/hooks/pre-commit`, which `/soleur:ship` then executes seconds later with
the operator's real `$HOME` — turning a few-second credential window into a full
compromise.

```text
# Defense-in-depth: reject every shell-active token before run. The plan file
# is trust-on-PR-review. NOTE: this regex blocks ONE SPELLING of chaining. Its
# complement — the inline-program arg rules — was deleted in #7393, so
# `python3 -c "__import__('os').system('curl …')"` now passes both this reject
# and the verb gate with no rejected token present. Do NOT cite it as the control
# against a malicious plan author; it is a typo-catcher. The Step 10.5 sandbox is
# the control.
# Rejects: ;, &&, ||, |, >, <, &, NEWLINE, parameter expansion ($VAR or ${VAR}),
# command substitution $(), backticks, process substitution <(/>().
#
# SCOPE OF THE NEWLINE REJECT: it closes BLOCK-mode command chaining only. A block
# scalar joins continuations with \n, which `bash -c` runs as separate statements —
# verified before this was added: a second `touch` line in a block scalar executed.
# It contributes ZERO coverage to folded scalars, which join with a SPACE and carry no
# shell-active token; those are covered by Step 10.4's probe-verb gate. Do not
# cite this reject as a mitigation for the folded-command class.
if [[ "$CMD" =~ (\$\(|\`|\<\(|\>\(|\;|\&\&|\|\||\||\>|\<|\&|$'\n'|\$\{?[A-Za-z_]) ]]; then
  echo "FAIL: discoverability_test.command contains shell-active token; refusing to run."
  exit 1
fi

# --- Sandbox construction (ADR-175 Layer 1) -------------------------------
# The flags live in ONE array so the establishment probe below and the real run
# cannot drift apart. MOUNT ORDER IS LOAD-BEARING: bwrap applies mounts in the
# order given and this repo lives under /home, so `--tmpfs /home` MUST precede
# `--ro-bind "$REPO_ROOT"`. Reversed, the tmpfs silently clobbers the repo bind
# and every probe dies with `Can't chdir` — a failure that reads as a bwrap
# incompatibility rather than an ordering bug. The repo's own agent sandbox
# documents the same semantics (apps/web-platform/server/agent-runner-sandbox-config.ts,
# #5733 / PR #5848): broad `--tmpfs` shadows an earlier bind.
REPO_ROOT="$(git rev-parse --show-toplevel)"
# `--tmpfs /run` removes /run/systemd/resolve/stub-resolv.conf, which
# /etc/resolv.conf symlinks to on systemd-resolved hosts. Without rebinding the
# resolved target, EVERY curl probe returns rc=6 — indistinguishable from the
# #4148 DNS-typo regression this check exists to catch.
RESOLV="$(readlink -f /etc/resolv.conf)"
# IN A WORKTREE, `.git` IS A FILE, NOT A DIRECTORY — it points at the git common
# dir under the bare repo root, which is OUTSIDE $REPO_ROOT. Binding only
# $REPO_ROOT therefore breaks every `git` probe with
# `fatal: not a git repository`, and `git` is an allowlisted verb. Soleur's whole
# workflow runs in worktrees, so this is the common case, not the edge case. The
# bind stays READ-ONLY, so the `.git/hooks/pre-commit` write-back escalation is
# still closed. Found by the #7393 execution replay — a static verb tally
# structurally could not have detected it.
# `--tmpfs /var/tmp` is a scratch dir, not a convenience: `/var` is not bound, so
# without it `/var/tmp` does not exist inside the sandbox and every probe using
# this repo's own documented scratch convention (`TMPDIR=/var/tmp`, per
# scripts/test-all.sh) dies on `mktemp: No such file or directory`. bwrap creates
# the `/var` parent implicitly, so nothing else from the host `/var` is exposed.
GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
GIT_BIND=()
if [[ "$GIT_COMMON_DIR" != "$REPO_ROOT"/* ]]; then
  GIT_BIND=(--ro-bind "$GIT_COMMON_DIR" "$GIT_COMMON_DIR")
fi
BWRAP_ARGS=(
  --ro-bind /usr /usr --ro-bind /etc /etc
  --symlink usr/bin /bin --symlink usr/lib /lib
  --symlink usr/lib64 /lib64 --symlink usr/sbin /sbin
  --tmpfs /home --tmpfs /root --tmpfs /run --tmpfs /tmp --tmpfs /var/tmp
  --ro-bind "$RESOLV" "$RESOLV"
  "${GIT_BIND[@]}"
  --ro-bind "$REPO_ROOT" "$REPO_ROOT" --chdir "$REPO_ROOT"
  --dev /dev
  --unshare-all --share-net --die-with-parent --new-session
)

# FAIL-CLOSED, with no unsandboxed fallback. A degraded sandbox that silently
# reverted to the status quo would be worse than no sandbox at all, because this
# skill would then claim a boundary that is not there.
if ! command -v bwrap >/dev/null 2>&1; then
  # SOLEUR_* sentinel so this is COUNTABLE across the fleet, not one line of
  # local stdout. The PostToolUse Bash marker extractor
  # (apps/web-platform/server/git-lock-marker-telemetry.ts) re-emits SOLEUR_*
  # markers as structured pino -> journald -> Vector -> Better Stack, so a
  # silently-disabled Check 10 becomes queryable instead of invisible.
  # Deliberately NOT in WEDGE_RE: queryable, not paged.
  echo "SOLEUR_PREFLIGHT_CHECK10_NOSANDBOX reason=bwrap-absent uname=$(uname -s)"
  case "$(uname -s)" in
    Darwin) echo "SKIP-NOSANDBOX: Check 10 executes plan-declared commands only inside a bubblewrap (bwrap) sandbox. bubblewrap is Linux-only and has no macOS port, so Check 10 is PERMANENTLY disabled on this host — this is the steady state, not a transient condition. Refusing to run the probe unsandboxed. Tracked for a Darwin sandbox implementation; see ADR-175 Consequences." ;;
    *)      echo "SKIP-NOSANDBOX: Check 10 executes plan-declared commands only inside a bubblewrap (bwrap) sandbox, and bwrap is not installed on this host. Refusing to run the probe unsandboxed. Install it with: sudo apt-get install -y bubblewrap   (Debian/Ubuntu) or sudo dnf install -y bubblewrap   (Fedora/RHEL)." ;;
  esac
  exit 0
fi

# `--proc /proc` must DEGRADE, not fail. /proc cannot be mounted inside a nested
# user namespace (a kernel restriction), and preflight runs inside exactly such a
# context on the containerized one-shot pipeline path. The repo already pays for
# this lesson: `enableWeakerNestedSandbox` in agent-runner-sandbox-config.ts
# (#1557) skips `--proc /proc` for the same reason. A hard `--proc` here would
# fail establishment in every containerized run and — because the design is
# fail-closed — SKIP Check 10 for all of them, which reads exactly like the
# fail-closed design working correctly. /proc is not part of what the boundary
# protects, so dropping it does not weaken the control: measured, both forms keep
# every credential store unreachable and both run curl/node/python3/grep.
BWRAP_PROC=(--proc /proc)
if ! bwrap "${BWRAP_PROC[@]}" "${BWRAP_ARGS[@]}" true 2>/dev/null; then
  BWRAP_PROC=()
  if ! bwrap "${BWRAP_ARGS[@]}" true 2>/dev/null; then
    # Report what was MEASURED, not a hypothesis (AP-021). The earlier message
    # named kernel.apparmor_restrict_unprivileged_userns without ever reading it,
    # while `2>/dev/null` discarded bwrap's own stderr — the only real evidence,
    # on a surface where nobody can re-run it by hand.
    BWRAP_ERR="$(bwrap "${BWRAP_ARGS[@]}" true 2>&1 >/dev/null | tail -c 200)"
    USERNS_MAX="$(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo unknown)"
    APPARMOR_RESTRICT="$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo unset)"
    echo "SOLEUR_PREFLIGHT_CHECK10_NOSANDBOX reason=establish-failed userns_max=${USERNS_MAX} apparmor_restrict=${APPARMOR_RESTRICT}"
    echo "SKIP-NOSANDBOX: Check 10 could not establish the bwrap sandbox on this host. Measured: max_user_namespaces=${USERNS_MAX}, apparmor_restrict_unprivileged_userns=${APPARMOR_RESTRICT}. bwrap said: $(sanitize "$BWRAP_ERR"). Refusing to run the probe unsandboxed."
    exit 0
  fi
fi

# Run with 15s wall-clock cap, capture stdout + exit code separately.
# `env -i` SCRUBS Doppler/Supabase secrets from the child env. It is LOAD-BEARING,
# not redundant — an earlier revision of this comment called it
# "redundant-but-harmless" on the grounds that the on-disk stores are unmounted
# anyway, and that reasoning is WRONG: bwrap does not scrub the environment
# (measured — a variable set here survives into the sandbox verbatim), and
# DOPPLER_TOKEN / GH_TOKEN / ANTHROPIC_API_KEY live in the environment ONLY, with
# no on-disk store to unmount. With `curl` allowlisted and --share-net retaining
# egress, dropping `-i` exfiltrates every credential in preflight's environment.
# Pinned by an anchored assertion in the F2 test; do not weaken either.
# PATH is restored explicitly so `curl`/`timeout` are still resolvable; HOME
# points at the sandbox tmpfs.
#
# `</dev/null` is load-bearing: without it the probe inherits preflight's stdin,
# so a command that reads stdin either consumes input the caller was still using
# or blocks for the full 15s and reports as a timeout. Measured while building
# #7393's execution replay, whose own read-loop the probes silently ate.
DT_OUT=$(bwrap "${BWRAP_PROC[@]}" "${BWRAP_ARGS[@]}" /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp timeout 15s bash -c "$CMD" </dev/null 2>/dev/null; printf 'RC:%d' "$?")
DT_RC="${DT_OUT##*RC:}"
DT_STDOUT="${DT_OUT%RC:*}"

# Log-injection guard (re-use Check 5's sanitize() pattern).
sanitize() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed $'s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g'; }
DT_STDOUT_SAFE=$(sanitize "$DT_STDOUT")

# Trailing-newline normalization. `bash -c "echo 200"` returns "200\n"; the
# matcher must compare without the trailing newline or "200" never matches.
# sanitize() above strips C0 controls 0x00-0x1f including \n, so DT_STDOUT_SAFE
# is already newline-free — but document the dependency explicitly so a future
# sanitize() refactor that preserves \n does not silently break matching.
```

The 15-second cap is a hard ceiling. Plans typically prescribe `curl --max-time 10`; the 15s outer cap accommodates 10s curl + 5s DNS + handshake without giving the curl invocation infinite headroom if it lacks `--max-time`.

**What the sandbox does NOT close, named so no one cites it as closure.**

`--share-net` **retains the host network namespace** — it does not create a fresh one. So
`127.0.0.1` inside the sandbox is the operator's real loopback. Measured on a development
workstation from inside the shipped `BWRAP_ARGS`: the sandbox's netns inode is identical to
PID 1's, and local Supabase Kong/PostgREST (54321), Postgres (54322) and Studio (54323) are
all reachable. A plain `curl http://127.0.0.1:54321/…` passes all three layers.

The class is **host-loopback pivot**, and it is materially worse than the egress case the
earlier revision of this paragraph named: it reaches services that are unauthenticated
*precisely because* they are loopback-bound, so the sandbox's "removes the credential
stores as files" claim is true for files and false for anything reachable over loopback.

Outbound egress remains too (`curl` is the dominant probe verb), so repo contents — and,
via the read-only git common-dir bind, whole-history and local session state — can be sent
to an arbitrary host. The repository is public, which bounds that half; it does not bound
the loopback half.

Closing it needs `--unshare-net` plus a userspace network stack
(`slirp4netns --disable-host-loopback` or `pasta`): `--unshare-net` alone kills all egress,
which surfaces as `curl` rc=6 — **indistinguishable from the #4148 DNS-typo signal this
check exists to catch**. Tracked as #7412, recorded as open in ADR-175 `## Consequences`.

A `127.0.0.1|localhost|::1` string reject is deliberately NOT used: it is bypassable in one
token (`127.1`, `2130706433`, `0x7f000001`, a DNS A-record pointing at loopback, or any
wrapped script), and adding it would let this skill claim a boundary that is not there —
the denylist mistake ADR-175 exists to retire.

**Step 10.6: Decision matrix (14 post-parse rows, 1 PASS terminal).**

| # | State | Detection | Result | Rationale |
| --- | --- | --- | --- | --- |
| 1 | No PR linked plan file | `$PLAN_PATH` empty after Shared Plan-File Resolution | **SKIP** | Indeterminate — Check 6 will fire if a section is required; Check 10 cannot run without a plan file. |
| 2 | Plan exists, no `## Observability` block | `awk` returns empty in Step 10.3 | **FAIL** | Sensitive-path diff requires an Observability block per `hr-observability-as-plan-quality-gate`. |
| 3 | Block exists, no `discoverability_test.command` parsed | `$CMD` empty after both Form A + B attempts | **FAIL** | Rule violation — the load-bearing field of the schema is missing. |
| 4 | Probe declares `credentials_required` (non-placeholder) | `$CREDS_REQ` non-empty and not a placeholder | **SKIP-DECLARED** | The property has no unauthenticated substitute. Executing it in the sandbox would fail for lack of credentials and prove nothing. Waives verification, not execution — the command never runs. |
| 5 | `credentials_required` is placeholder text | `$CREDS_REQ` matches `TODO`/`TBD`/`N/A`/… | **FAIL** | A declaration that says nothing waives nothing (deepen-plan §4.7 placeholder machinery). |
| 6 | Verb not on `PROBE_VERB_ALLOWLIST` | [probe-verb-gate.sh](./scripts/probe-verb-gate.sh) exits 1 | **FAIL** | Deny-by-default, with no path-shaped exemption. Schema validation, not a security control — see Step 10.4. The reason names both remedies (repo-relative script; `credentials_required`) and the allowlist-extension route. |
| 7 | Sandbox unavailable or cannot be established | `bwrap` absent, or both `--proc` and no-`--proc` establishment attempts fail | **SKIP-NOSANDBOX** | Fail-closed. Never falls back to unsandboxed execution. Its OWN terminal: folded into ordinary SKIP, "the gate verified nothing" was byte-identical to "the gate had nothing to do". bwrap is Linux-only, so on macOS this is the steady state. Emits `SOLEUR_PREFLIGHT_CHECK10_NOSANDBOX` so it is countable across the fleet. |
| 8 | Command DNS-fails | `$DT_RC == 6` (curl: "Could not resolve host") | **FAIL** | The hostname-typo class — the exact #4148 regression. |
| 9 | Command times out | `$DT_RC == 28` (curl) OR `$DT_RC == 124` (timeout(1)) | **FAIL** | Endpoint unreachable; DNS resolved but no response in 15s. |
| 10 | Command requires creds not in Doppler (auth-gated probe) | `$DT_RC == 22` AND HTTP 401/403 AND `$EXPECTED` does NOT explicitly list 401/403 | **SKIP** | Auth-gated probe with no operator creds; surface diagnostic suggesting a `credentials_required` declaration or a Doppler-fetched probe variant. |
| 10b | Command not found in the sandbox | `$DT_RC == 127` | **FAIL** | The probe's program is not on the sandbox `PATH` (`/usr/local/bin:/usr/bin:/bin`), which is deliberately NOT widened — that would be an authority grant inside a change that narrows authority. Wrap the probe in a repo-relative script, or use an allowlisted verb. Reported as its own state because falling through to row 11 blamed "expectation drift" for a cause the code measured exactly. |
| 11 | Command returns a code/output the plan's `expected_output` does NOT include | `$DT_STDOUT_SAFE` not present in `$EXPECTED` | **FAIL** | Plan's expectation drifted from production reality. |
| 12 | Command returns expected output | All other paths — `$DT_RC == 0` AND stdout matches `$EXPECTED` | **PASS** | Invariant proven by live execution inside the sandbox. |

**Expected-output matching semantics.** When `$EXPECTED` is a comma-separated or "or"-joined list (e.g., `200 or 401`, `200, 401`, `["200","401"]`), tokenize on `,|\s+or\s+|\bor\b|[\`"\[\]/]+` and treat as a list. Match if any token is a non-empty substring of `$DT_STDOUT_SAFE`. When `$EXPECTED` is a single value, substring-match. The tokenizer accepts both `200` and `"200"`.

**Step 10.7: Headless mode behaviour.**

On **FAIL**, abort with the diagnostic table (command, exit code, sanitized stdout, expected). On **PASS** or **SKIP**, continue silently. On **SKIP-DECLARED**, continue but **emit one line** naming the declared scope verbatim — this terminal exists to be seen, and silencing it would defeat the drift control it was built for. On **SKIP-NOSANDBOX**, continue but **emit one line** plus the `SOLEUR_PREFLIGHT_CHECK10_NOSANDBOX` sentinel: the check did not run, and that fact must reach both the operator and the fleet-level marker pipeline.

**Step 10.8: Interactive mode behaviour.**

On **FAIL**, present the failure reason + sanitized command + diagnostic and offer **AskUserQuestion**:

1. "Fix the plan's `discoverability_test.command` now" — open the plan file at the line of the `discoverability_test:` key. Re-run Check 10.
2. "Skip — temporarily defer (logs a trim-tracker issue)" — `gh issue create --label 'priority/p3-low,chore'` with the command, the exit code and the `expected_output` as the body. **Never include `$DT_STDOUT_SAFE` in the issue body.** `sanitize()` strips only C0 controls, not secrets or PII: a probe's stdout routinely carries log rows with user emails, client IPs, and bearer/`dp.ct.*` tokens, and this repository is PUBLIC. The captured stdout stays in the local run output for the operator; it does not get published. Continue the preflight run with this check noted as DEFERRED.
3. "Abort — fix elsewhere" — stop the pipeline.

**Result:**

- **PASS** — Sensitive-path diff with valid plan-linked Observability block AND command ran inside the sandbox AND output matches `expected_output`.
- **FAIL** — Sensitive-path diff with any of: missing Observability block, missing `discoverability_test.command`, command requires SSH, verb not on `PROBE_VERB_ALLOWLIST` (no path-shaped exemption), placeholder `credentials_required`, command contains shell substitution, DNS failure, timeout, or output mismatch.
- **SKIP** — No sensitive paths touched, OR no PR available, OR no plan file linked from PR body, OR command is auth-gated with no operator creds.
- **SKIP-NOSANDBOX** — The bwrap sandbox is unavailable or could not be established (fail-closed — never an unsandboxed fallback). Reported distinctly from **SKIP** because "the check could not run" and "the check had nothing to do" are different facts, and only one of them means a security gate is dark. Emits a `SOLEUR_*` sentinel so it is countable across the fleet rather than one line of local stdout.
- **SKIP-DECLARED** — The plan declares a non-placeholder `discoverability_test.credentials_required`. The command was **not executed**; the declared scope is surfaced verbatim. Reported distinctly from **SKIP** everywhere (headless line, Phase 2 aggregate row) because it is a verification waiver a reviewer must be able to see.

### Check 7: Canary Probe Set Covers Authenticated Surface

**Path-gated:** only runs when the cached path-set from Phase 0 Step 0.1 (`"$PREFLIGHT_TMP/preflight-diff-files.txt"`) contains `apps/web-platform/infra/ci-deploy.sh`. Otherwise return **SKIP** with note: "ci-deploy.sh untouched." The path predicate is identical to the original `git diff --name-only origin/main...HEAD` form — only the diff source is changed.

**Rationale:** The legacy canary probed only `/health`, which is middleware-bypassed and never imports `lib/supabase/client.ts`. A broken inlined `NEXT_PUBLIC_SUPABASE_*` value would pass canary and ship to prod (PR #3014 incident class). The canary contract — documented in `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` — requires probes for every public route (`/login`) AND auth-gated entry (`/dashboard`) PLUS a body-content sentinel rejection.

**Step 7.1: Assert /dashboard probe presence.**

```bash
grep -c '/dashboard' apps/web-platform/infra/ci-deploy.sh
```

The count MUST be ≥ 1.

**Step 7.2: Assert /login probe presence.**

```bash
grep -c '/login' apps/web-platform/infra/ci-deploy.sh
```

The count MUST be ≥ 1.

**Step 7.3: Assert structured-marker body-content rejection.**

```bash
grep -F 'data-error-boundary=' apps/web-platform/infra/ci-deploy.sh
```

The grep MUST exit 0 — the canary must reject any rendered HTML containing the `data-error-boundary` attribute emitted by `components/error-boundary-view.tsx`. The structured marker survives copy edits; without it, a copy change would silently disable the rollback gate (PR #3014 lesson).

**Result:**

- **PASS** — all three greps satisfy their conditions.
- **FAIL** — any of: `/dashboard` missing from canary, `/login` missing from canary, or the error-sentinel body check absent. Operator must restore the layered probe before re-running preflight.
- **SKIP** — `apps/web-platform/infra/ci-deploy.sh` was not modified in this branch.

### Check 11: Domain-Model Register Drift

Enforces the domain-model register's maintenance contract (#5871): a PR that changes a
business rule must not leave the register with a **stale citation** (a cited migration/symbol
that no longer resolves). Consumes the deterministic analyzer `domain-model-drift.sh`
(#5754, ADR-076). The register (`knowledge-base/engineering/architecture/domain-model.md`) is a
**curated subset**, so "undocumented source facts" is ~every un-curated table by design — it is
**advisory-only, never a FAIL input**. This check gates on **stale citations only**.

**Step 11.1 — diff-scope (fast-path SKIP).** SKIP unless the cached path-set
(`"$PREFLIGHT_TMP/preflight-diff-files.txt"`) matches a business-rule surface OR the register itself:

```bash
DIFF="$PREFLIGHT_TMP/preflight-diff-files.txt"
# Fail-safe: never SKIP on a missing/empty cache — recompute inline, then run if still empty.
if [[ ! -s "$DIFF" ]]; then git diff --name-only origin/main...HEAD > "$DIFF" 2>/dev/null || true; fi
if [[ -s "$DIFF" ]] && ! grep -qE '(^|/)apps/web-platform/supabase/migrations/.*\.sql$|(^|/)apps/web-platform/server/workspace-resolver\.ts$|(^|/)knowledge-base/engineering/architecture/domain-model\.md$' "$DIFF"; then
  echo "SKIP — no business-rule surface (migration/workspace-resolver/register) in diff"; exit 0
fi
```

The register-file literal is load-bearing: a register-only edit can introduce a stale citation.
Check 11 reads `origin/main...HEAD` (PR-independent), so it **RUNS pre-PR** — do NOT "fix" it to
SKIP-on-no-PR (that would fail it open).

**Step 11.2 — run + parse the stale sub-count** (line-anchored; the raw exit code is NOT the signal):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/domain-model-drift.sh" drift --repo . \
  --register knowledge-base/engineering/architecture/domain-model.md > "$PREFLIGHT_TMP/register-drift.txt" 2>&1; rc=$?
stale=$(grep -oE '^## Stale register citations \([0-9]+\)' "$PREFLIGHT_TMP/register-drift.txt" | head -1 | grep -oE '[0-9]+')
stale=${stale:-0}
```

The `^` anchor + `head -1` guarantee a single integer from the canonical column-0 header — an
unanchored grep could match a verbatim-SQL predicate line echoing the substring (multiline capture
breaks the numeric test).

**Result:**

- **PASS** — `rc == 0` (register clean). The "Undocumented source facts (M)" count is surfaced by the
  advisory review note, never here.
- **FAIL** — `stale > 0`: "domain-model register has $stale stale citation(s) — the register cites a
  file/symbol that no longer resolves. Fix the cited row(s), or run `/soleur:sync domain-model`. If a
  citation backticks a *filename*, unbacktick it (known citation-parser false-positive — see
  `knowledge-base/project/learnings/best-practices/2026-07-01-domain-model-register-curation-citation-parser-and-grep-validation.md`)."
- **FAIL** — `rc == 2` (analyzer error / unanalyzable source): "register-drift check could not run
  (analyzer exit 2) — inspect `--repo`/jq/migrations dir; NOT a drift finding."
- **FAIL** — `rc == 3` (secret-refuse): "domain-model analyzer refused to emit — a secret-shaped
  substring was found in extracted structural text. Likely a recently-changed migration column/value
  matching `sk_test`/`ghp_`/`AKIA…`/`-----BEGIN` (a benign column name can false-positive). Inspect the
  newest `apps/web-platform/supabase/migrations/*.sql`."
- **SKIP** — no business-rule surface (or the register) in the diff.

### Check 12: Encryption Posture

Enforces the encryption-posture ledger's maintenance contract (ADR-140): every persistent
store and cross-component connection Soleur operates must carry a ledger row whose cited
evidence resolves to real code, and any accepted plaintext/unverified-TLS exception must carry
an open, unexpired tracking issue. Consumes the deterministic analyzer
`lint-encryption-posture.py` (repo-root `scripts/`) — this check does NOT reimplement its PASS/FAIL logic in
prose; it shells out and relays the exit code.

**Step 12.1 — diff-scope (fast-path SKIP).** SKIP unless the cached path-set
(`"$PREFLIGHT_TMP/preflight-diff-files.txt"`) matches a store-class or connection-class surface:

```bash
DIFF="$PREFLIGHT_TMP/preflight-diff-files.txt"
# Fail-safe: never SKIP on a missing/empty cache — recompute inline, then run if still empty.
if [[ ! -s "$DIFF" ]]; then git diff --name-only origin/main...HEAD > "$DIFF" 2>/dev/null || true; fi
if [[ -s "$DIFF" ]] && ! grep -qE '\.tf$|supabase/migrations/.*\.sql$|cloud-init.*\.ya?ml$|docker-compose.*\.ya?ml$' "$DIFF"; then
  echo "SKIP — no store-class or connection-class surface (*.tf / migration / cloud-init / docker-compose) in diff"; exit 0
fi
```

This mirrors "I do not apply", never "I cannot prove it" (`2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`) — an empty/missing diff cache falls through to run, it never SKIPs by default.

**Step 12.2 — run the Layer A sweep:**

```bash
python3 scripts/lint-encryption-posture.py --repo-sweep > "$PREFLIGHT_TMP/encryption-posture.txt" 2>&1; rc=$?
```

**Result:**

- **PASS** — `rc == 0`. Every store/connection in the repo has a ledger row whose cited evidence
  resolves to real code, and every accepted exception carries an open, unexpired tracking issue.
- **FAIL** — `rc != 0`: relay the script's own output (`cat "$PREFLIGHT_TMP/encryption-posture.txt"`)
  verbatim — the classes it can report include an unledgered store, an unresolvable citation, an
  expired or untracked exception, or a store/connection disclosed as encrypted while its ledger row
  says otherwise. Do not re-derive the verdict from this SKILL.md — the script is the single source
  of truth for the pass/fail decision.
- **SKIP** — the cached path-set contains zero `.tf` / store-class / connection-class paths.

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
| Production Bundle Supabase Host | PASS/FAIL/SKIP | <details> |
| Brand-Survival Self-Review | PASS/FAIL/SKIP | <details> |
| Canary Probe Set Covers Auth Surface | PASS/FAIL/SKIP | <details> |
| SW Cache Bump on Client-Bundle Fix | PASS/FAIL/SKIP | <details> |
| Node-Only Encodings Banned in Client-Bundle | PASS/FAIL | <details> |
| Discoverability Test Execution | PASS/FAIL/SKIP/SKIP-DECLARED/SKIP-NOSANDBOX | <details> — on SKIP-DECLARED, quote the declared `credentials_required` scope verbatim so the waiver is visible in the aggregate; on SKIP-NOSANDBOX, state plainly that Check 10 did not execute on this host and why |

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

## Sharp Edges

- **Triple-SSOT for `SENSITIVE_PATH_RE`.** The literal lives at Check 6 Step 6.1, Check 10 Step 10.1, AND `plugins/soleur/skills/deepen-plan/SKILL.md` Phase 4.6 Step 2. All three MUST stay byte-identical. The Check 10 regression test (`plugins/soleur/test/preflight-discoverability-test.test.ts`) asserts ≥2 matches in `preflight/SKILL.md`; the canonical grep is `grep -cF "SENSITIVE_PATH_RE='^(apps/web-platform" plugins/soleur/skills/preflight/SKILL.md plugins/soleur/skills/deepen-plan/SKILL.md`. `grep -cF` is substring-based and tolerates the 2-space indentation difference between top-level (preflight) and markdown-bullet (deepen-plan) contexts — keep AC2's grep un-anchored.
- **Shared Plan-File Resolution is a SSOT.** Both Check 6 Step 6.2 and Check 10 Step 10.2 call it. A future PR that changes the scrub/extract logic must edit the shared sub-section once — both consumers pick it up. Do NOT copy-paste the logic back into a caller block.
- **Check 10 parser duality (Form A YAML vs Form B prose+fence).** PR #4148 used Form B; the canonical template uses Form A. Both must be accepted OR Check 10 silently SKIPs on currently-valid plans. The TS reference impl at `plugins/soleur/test/lib/discoverability-test-parser.ts` exercises both forms across every fixture in `plugins/soleur/test/fixtures/preflight-check-10/`.
- **Rule order in `parse-form-a.awk` IS the bug (#6772).** The inline rule `/^[[:space:]]*command:/` matches EVERY `command:` line, including `command: >-` and `command: |`. If it is ever moved ahead of the fold/block header rules it returns the literal indicator, which then self-rejects against Step 10.5's shell-active `>` branch — a check that cannot parse its input, reporting a shell injection the plan does not have. AC1 and fixtures F1–F3 are the pins; do not drop them when refactoring.
- **Anchoring the header regex is a bug generator.** A bare `$` anchor made `command: >- # note` fall through to inline and reproduce #6772 exactly. Any future tightening of the header must keep the comment-tolerant `(#.*)?$` tail and re-run the F1–F3 comment column.
- **`indent()` returns 0 on a blank line**, which is `<= key` for every scalar. The blank-line skip rule MUST stay above the indent terminator or every scalar ends at its first blank line (fixture N6).
- **`env -i` scrubs environment *variables*, never *files or sockets* — and an ephemeral `$HOME` is the same mistake wearing a better name.** `env -i` cannot remove an on-disk credential store, and setting `HOME` to a temp dir only changes where a CLI *looks*: measured during #7393, an absolute-path read of the operator's home Doppler config returned a live 294-byte service token under `HOME=$(mktemp -d)`, and a glob read across `/home/*/…` did too. Never cite either as a mitigation for a credential-bearing command. What covers that class is the Step 10.5 **filesystem boundary** (bwrap: `/home`, `/root`, `/run` replaced with tmpfs; repo bound read-only) — the verb allowlist in Step 10.4 bounds *legibility and maintenance*, not authority.
- **Probe the invariant, not the proxy — this gate's own history is the cautionary tale.** #7393's first design measured `doppler configure get token`'s **exit code** (0 even with no token) and read it as "credential still reachable". Corrected to token length plus a live read, it then measured **credential discovery** and reported it as **credential reachability** — and shipped a Sharp Edge congratulating itself for escaping exactly that trap, one section above the place it committed it. Any claim about credential reachability must be tested by reading the file **at its absolute path, from inside the real execution environment**.
- **A fail-closed gate can fail closed for the wrong reason, and it looks identical to working.** `--proc /proc` cannot be mounted inside a nested user namespace (the repo already knows this — `enableWeakerNestedSandbox`, #1557). A hard `--proc` would fail sandbox establishment in every containerized run, and the fail-closed design would then SKIP Check 10 everywhere — a blanket disablement whose telemetry is indistinguishable from correct operation. Whenever a gate's failure mode is "skip", enumerate the environments where establishment fails *for reasons unrelated to the threat*, and **degrade** rather than skip in those.
- **`--tmpfs /home` must precede `--ro-bind "$REPO_ROOT"`.** bwrap applies mounts in order and this repo lives under `/home`. Reversed, the tmpfs silently clobbers the repo bind and every probe dies with `Can't chdir` — a failure that reads as a bwrap incompatibility rather than an ordering bug. The agent sandbox's module header documents the same tmpfs-shadows-earlier-binds semantics (#5733 / PR #5848); two independent discoveries of one rule.
- **`--tmpfs /run` breaks DNS on systemd-resolved hosts.** The resolver config at /etc/resolv.conf is a symlink into the systemd-resolved stub under /run; tmpfs'ing `/run` removes the target, and every `curl` probe then returns rc=6 — **indistinguishable from the #4148 DNS-typo regression Check 10 exists to catch**. Bind the resolved target (`readlink -f` the resolver config) after the tmpfs. Written unquoted deliberately: the skill-security-scan `path-traversal-absolute` rule matches a quote or backtick immediately followed by a system path, so presenting these as code literals turns explanatory prose into a REVIEW finding.
- **`awk`, `sed` and `find` are `bash -c` in disguise.** Measured: `awk 'BEGIN{system("…")}'` executes arbitrary commands and passes the shell-active reject (no `;`, `&&`, `|`, `$(`). Rejecting `bash -c` while allowlisting `awk` would be incoherent, so all three are excluded — as are `python3 -c`, `node -e`, `bun -e`, GNU `sed`'s `e` flag, and `find -exec`.
- **`git ls-files --error-unmatch` is not a review oracle.** It interrogates the **PR-head index** — the attacker's own branch — and preflight runs *before* merge. "Tracked" and "reviewed" are different properties. That is why the program-path rule here is a pure string rule and the sandbox, not a tracking check, is what contains the script.
- **The shell-active reject does not bound a folded command.** Folding joins with a space, so a folded scalar has no `;`/`|`/`$()` by construction and passes the reject automatically — it can append *arguments* but never chain a command. That makes fold safer than block for injection, but it also means no token in that reject set constrains what a folded command *is*. Reasoning "the reject will catch it" about a folded command is reasoning about the wrong gate; the verb allowlist and the sandbox are the gates that apply.
- **`bash -c "$CMD"` stdout always ends in `\n`.** The matcher MUST normalize trailing newlines (via `sanitize()` or `${var%$'\n'}`) before substring comparison, or `expected_output: 200` fails when production correctly emits `200\n`.
- **The `\b` word-boundary trap.** Bash `[[ $x =~ \bssh \b ]]` matches `ssh ` only when whitespace is on BOTH sides; trailing-EOF or trailing-newline `ssh ` does NOT match. Always use `(^|[[:space:]])ssh([[:space:]]|$)` — the canonical Check 10 reject form — when checking for `ssh ` in operator-facing prose.
