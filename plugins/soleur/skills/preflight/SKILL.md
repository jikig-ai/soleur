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

Run these six checks (plus the Not-Bare-Repo assertion) as parallel Bash tool calls. Each returns PASS, FAIL, or SKIP.

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

### Check 5: Production Bundle Supabase Host

**Path-gated:** only runs when `git diff --name-only origin/main...HEAD` contains any of `apps/web-platform/lib/supabase/client.ts`, `apps/web-platform/lib/supabase/validate-url.ts`, `apps/web-platform/lib/supabase/validate-anon-key.ts`, `apps/web-platform/Dockerfile`, `.github/workflows/reusable-release.yml`, or `apps/web-platform/scripts/verify-required-secrets.sh`. Otherwise return **SKIP** with note: "No build-arg surface changes detected."

**Note:** Complements Check 4. Check 4 enforces Doppler dev/prd isolation; Check 5 covers the GitHub-repo-secrets surface that feeds the prod Docker build (`secrets.NEXT_PUBLIC_SUPABASE_URL` and `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` in `reusable-release.yml`). The two sources can drift — see `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md` (URL class) and `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md` (anon-key class).

**Step 5.1: Discover the candidate chunk set.**

Webpack chunking is not stable across releases — the inlined Supabase init may live in the login page chunk, in a numeric shared chunk (`/_next/static/chunks/8237-*.js`), or in a layout chunk. Hardcoding a single path produces SKIP-on-chunking-change, which silently disables the gate (issue #3010). Discover the candidate set dynamically by enumerating every chunk URL the login HTML references — that is the authoritative "what /login loads" surface.

Run as separate Bash calls (no command substitution per skill convention):

```bash
curl -fsSL --max-time 10 -A "Mozilla/5.0" https://app.soleur.ai/login -o /tmp/preflight-login.html
```

```bash
grep -oE '/_next/static/chunks/[^"]+\.js' /tmp/preflight-login.html | sort -u | head -20 > /tmp/preflight-candidates.txt
```

The cap of 20 is generous (current prod loads 13 chunks); if ever hit on a future release, prefer raising the cap over reverting to the hardcoded login-chunk path. The grep matches both `<script src=...>` and `<link rel=preload href=...>` references — both are valid candidates.

If the `curl` fails (rc != 0) or `/tmp/preflight-candidates.txt` is empty, return **SKIP** with note: "Could not fetch /login HTML or could not locate any /_next/static/chunks references."

**Step 5.2: Probe each candidate chunk for Supabase shapes.**

The Supabase host string and the inlined anon-key JWT may live in DIFFERENT chunks (verified 2026-04-29 against current prod: `8237-*.js` carries the JWT but contains zero `supabase.co` host strings). Track `host_union` (every chunk's supabase-host hits) and `jwt_chunk` (the first chunk with a JWT) independently. Always traverse the full candidate list — bail-early would skip chunks that may carry a placeholder-host leak (matrix row 6).

This block is operator-executed under the skill's `set -euo pipefail` convention. Failed `curl` per chunk and `grep` rc=1 on no-match must NOT abort the loop — the gate-level SKIP/FAIL decision is made from the accumulated state at end-of-loop, not from per-iteration rc.

```bash
mkdir -p /tmp/preflight-chunks
host_union=""
jwt_chunk=""
while IFS= read -r chunk_path; do
  # Defense-in-depth: validate chunk_path is a clean Next.js static-chunks subpath
  # before interpolating into the curl URL (no `..`, no `@`, no `?`, no whitespace).
  [[ "$chunk_path" =~ ^/_next/static/chunks/[A-Za-z0-9_/().-]+\.js$ ]] || continue
  base=$(basename "$chunk_path")
  curl -fsSL --max-time 10 --max-filesize 5242880 "https://app.soleur.ai${chunk_path}" -o "/tmp/preflight-chunks/${base}" || continue
  hosts=$(grep -oE 'https?://([a-z0-9.-]*supabase\.co|api\.soleur\.ai)' "/tmp/preflight-chunks/${base}" | sort -u || true)
  if [[ -n "$hosts" ]]; then
    host_union="${host_union}${hosts}"$'\n'
  fi
  if [[ -z "$jwt_chunk" ]]; then
    jwt=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "/tmp/preflight-chunks/${base}" | head -1 || true)
    if [[ -n "$jwt" ]]; then
      jwt_chunk="/tmp/preflight-chunks/${base}"
    fi
  fi
done < /tmp/preflight-candidates.txt

printf '%s' "$host_union" | sort -u
printf 'jwt_chunk=%s\n' "${jwt_chunk:-<none>}"
```

The redirected-stdin form (`< /tmp/preflight-candidates.txt`) is required — piping (`cat ... | while read`) scopes loop variables to a subshell and loses `host_union` / `jwt_chunk` at loop exit. The `--max-filesize 5242880` (5 MB) cap defends against a misbehaving CDN response filling tmpfs across 20 fetches. The strict path regex rejects `..`, `@`, `?`, and whitespace before any string interpolation into the curl URL — a defense-in-depth gate even though the source HTML is served by our own CDN. Full traversal (no early-break) ensures placeholder-host leaks in late-candidate chunks are still detected (matrix row 6).

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
git diff --name-only origin/main...HEAD | grep -E "$SENSITIVE_PATH_RE"
```

Run as two separate Bash calls (assignment, then the piped `git`/`grep`). The regex covers every Next.js attack surface (`middleware.ts`, every `app/api/**` route, security/CSP/auth/session/legal libraries, infra Terraform under `apps/*/infra/`, all Doppler-aware shell scripts, and every credential-handling workflow even when `doppler` is not in the filename).

If `grep` exits non-zero (no match), return **SKIP** with note: "No sensitive paths touched."

**Step 6.2: Fetch the PR body to a private temp file.**

Use `mktemp` so the path is not predictable on multi-user hosts (defends against tmp-symlink attacks per general POSIX best practice). Two separate Bash calls (no command substitution):

```bash
PR_BODY_FILE=$(umask 077 && mktemp -t preflight-pr-body.XXXXXXXX.md)
```

```bash
gh pr view --json body --jq .body > "$PR_BODY_FILE"
```

Trap exit so the temp file is removed: `trap 'rm -f "$PR_BODY_FILE"' EXIT`. If `gh pr view` fails (no PR exists for the current branch), return **SKIP** with note: "No PR available — section validation deferred to next preflight run after PR creation."

**Step 6.3: Resolve the canonical compliance source (PR body OR linked plan file).**

The `## User-Brand Impact` section may live in the PR body itself (typical for short PRs) OR in a plan file referenced from the PR body (typical for plans authored via `/soleur:plan`). Both signals are valid per `plugins/soleur/skills/review/SKILL.md` `<conditional_agents>` block. Resolve a single check input by stripping noise from the PR body and concatenating any referenced plan file.

```bash
# 6.3a: strip HTML comments and fenced code blocks from PR body before any regex match
SCRUBBED_BODY=$(awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; next} !f{print}' "$PR_BODY_FILE" \
  | perl -0777 -pe 's/<!--.*?-->//gs')
```

```bash
# 6.3b: extract any linked plan file path (knowledge-base/project/plans/*.md) from the scrubbed body
PLAN_PATH=$(printf '%s' "$SCRUBBED_BODY" | grep -Eo 'knowledge-base/project/plans/[^[:space:])"`'\'']+\.md' | head -n 1 || true)
```

```bash
# 6.3c: build the combined check input
COMBINED=$(mktemp -t preflight-combined.XXXXXXXX.md)
printf '%s\n' "$SCRUBBED_BODY" > "$COMBINED"
if [[ -n "$PLAN_PATH" && -f "$PLAN_PATH" ]]; then
  awk 'BEGIN{f=0} /^[[:space:]]*```/{f=!f; next} !f{print}' "$PLAN_PATH" \
    | perl -0777 -pe 's/<!--.*?-->//gs' >> "$COMBINED"
fi
trap 'rm -f "$PR_BODY_FILE" "$COMBINED"' EXIT
```

The `awk` pass strips fenced code blocks (so an HTML/markdown example inside ` ``` ` cannot fool a substring match). The `perl -0777` pass strips HTML comments (`<!-- ... -->` including multi-line). Anything inside fences/comments cannot appear in `$COMBINED`.

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

**Path-gated:** only runs when `git diff --name-only origin/main...HEAD` includes BOTH a regression-fix marker (a commit subject starting with `fix(`, `fix:`, or `hotfix`) AND any file under `apps/web-platform/lib/supabase/`, `apps/web-platform/sentry.client.config.ts`, `apps/web-platform/lib/auth/`, `apps/web-platform/lib/byok/`, or `apps/web-platform/components/error-boundary-view.tsx`. Otherwise return **SKIP** with note: "No client-bundle regression-fix surface detected."

**Rationale:** Content-hashed Next.js chunks normally invalidate cache automatically — new content → new filename → SW cache miss → fresh fetch. But the SW at `apps/web-platform/public/sw.js` uses a cache-first strategy under a single `CACHE_NAME` for `/_next/static/**`, and old broken chunks remain cached under their old filenames until either (a) browser eviction, or (b) the activate handler purges them via a `CACHE_NAME` bump. After PR #3014 deployed v0.58.0 with a corrected validator, users still saw the dashboard error.tsx because their SW was serving cached PR #3007 chunks. Without bumping `CACHE_NAME`, a regression fix to the inlined client bundle relies on every user manually clearing site data — unacceptable for an auth-tree outage.

**Step 8.1: Detect regression-fix commit subject.**

```bash
git log origin/main..HEAD --pretty=%s | grep -iE '^(fix\(|fix:|hotfix)' | head -1
```

If empty, return **SKIP** with note: "No fix(...) commit on branch."

**Step 8.2: Detect client-bundle surface in diff.**

```bash
git diff --name-only origin/main...HEAD | grep -E '^apps/web-platform/(lib/(supabase|auth|byok)/|sentry\.client\.config\.ts|components/error-boundary-view\.tsx)' | head -1
```

If empty, return **SKIP** with note: "No client-bundle surface touched."

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

### Check 7: Canary Probe Set Covers Authenticated Surface

**Path-gated:** only runs when `git diff --name-only origin/main...HEAD` contains `apps/web-platform/infra/ci-deploy.sh`. Otherwise return **SKIP** with note: "ci-deploy.sh untouched."

**Rationale:** The legacy canary probed only `/health`, which is middleware-bypassed and never imports `lib/supabase/client.ts`. A broken inlined `NEXT_PUBLIC_SUPABASE_*` value would pass canary and ship to prod (PR #3014 incident class). The canary contract — documented in `knowledge-base/engineering/ops/runbooks/canary-probe-set.md` — requires probes for every public route (`/login`) AND auth-gated entry (`/dashboard`) PLUS a body-content sentinel rejection.

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
