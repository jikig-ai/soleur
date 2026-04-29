---
module: System
date: 2026-04-29
problem_type: integration_issue
component: authentication
symptoms:
  - "curl -sI on /auth/v1/authorize returns HTTP 405 (Allow: GET)"
  - "curl on /auth/v1/settings returns HTTP 401 with external: { google: null } when no apikey header"
  - "Sentry POST /api/0/.../rules/ rejects EventFrequencyCondition.interval=10m with HTTP 400"
  - "Two Sentry rules can share the same name; match-by-name idempotency picks one arbitrarily"
  - "GitHub Actions heredoc bodies preserve leading whitespace; 4+ leading spaces render the issue body as a code block"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags:
  - supabase-auth
  - sentry-api
  - github-actions
  - synthetic-probe
  - api-contract
  - heredoc
related_prs:
  - 3030
related_issues:
  - 2997
---

# Supabase Auth probe + Sentry rule API quirks

Five external-API contract gotchas surfaced while building the synthetic
OAuth probe + Sentry alert rules for #2997. Each one was prescribed by
the plan's research subagent verbatim from API docs that didn't reflect
runtime behavior, and each one would have caused silent paging or
rendering breakage in production.

## Quirks

### 1. `GET /auth/v1/authorize` rejects HEAD with 405

Supabase Auth's OAuth `/authorize` endpoint declares `Allow: GET`. A
`curl -sI` (HEAD) probe returns:

```
HTTP/2 405
allow: GET
```

A probe using `-sI` would page ops every cron tick. Use a full GET with
`--max-redirs 0` instead — `-w '%{redirect_url}'` still captures the
Location header without following the redirect:

```bash
curl -s --max-time 10 --max-redirs 0 -o /dev/null \
  -w '%{http_code} %{redirect_url}' \
  "https://api.soleur.ai/auth/v1/authorize?provider=google&redirect_to=..."
```

### 2. `GET /auth/v1/settings` requires the anon `apikey` header

Without `apikey`, the endpoint returns HTTP 401 with body
`{"external": {"google": null, "github": null, ...}}`. With it, you get
the real provider-enabled flags:

```bash
curl -s -H "apikey: $NEXT_PUBLIC_SUPABASE_ANON_KEY" \
  "https://api.soleur.ai/auth/v1/settings" \
  | jq '.external'
# {"google": true, "github": true, "apple": false, ...}
```

The anon key is shipped in the client bundle (it is the
`NEXT_PUBLIC_SUPABASE_ANON_KEY` env), so passing it to a GitHub Actions
workflow via `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` is no broader leak
than its baseline scope. The existing `gh secret list` already exposes
this name.

### 3. Sentry `EventFrequencyCondition.interval` enum is closed

`POST /api/0/projects/{org}/{project}/rules/` rejects intervals outside
`{1m, 5m, 15m, 1h, 1d, 1w, 30d}` with HTTP 400. The issue body for
#2997 prescribed `10m`, which is not in the set; the configurator must
prescribe `15m` (next-larger valid value, conservative on paging) and
ratchet docs must reference the closed enum. Same set applies to
`EventUniqueUserFrequencyCondition.interval`.

Filed live in the configurator script's comment header so a future
editor can't reintroduce `10m` without seeing the warning.

### 4. Sentry rule name uniqueness is NOT enforced

The Sentry web UI lets users duplicate a rule name (e.g., clone
`auth-per-user-loop` to test a higher threshold). The API reflects both
copies in `GET /rules/`. A naive `match-by-name → .[0].id` upsert
silently picks one and updates it; the other keeps stale config and
continues paging (or failing to page) under the same name with zero
operator signal.

Fix: count matches and fail-closed when `count > 1`:

```bash
match_ids=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<<"$rules_json")
match_count=$(printf '%s' "$match_ids" | grep -c .)
if (( match_count > 1 )); then
  echo "ERROR: ${match_count} rules named '${name}' found — refusing to mutate." >&2
  exit 1
fi
```

### 5. GHA heredoc bodies preserve leading whitespace

Bash heredoc bodies inside a YAML `run: |` block are indented at the
YAML-block level (typically 10 spaces). Without `<<-` and tabs, those
spaces are preserved literally in the captured `$BODY`. GitHub markdown
treats 4+ leading spaces as a code block, so:

```bash
BODY=$(cat <<ISSUE_BODY
## Synthetic OAuth probe failed
- **Failure mode:** ${FAIL_MODE}
ISSUE_BODY
)
gh issue create --body "$BODY"
```

renders the entire body as `<pre>` instead of a list — defeating the
paging goal. Two safe alternatives:

- Build the body with `printf` into a tempfile, use `--body-file`:
  ```bash
  BODY_FILE=$(mktemp)
  trap 'rm -f "$BODY_FILE"' EXIT
  { printf '## Title\n\n'; printf -- '- **Field:** %s\n' "$VAL"; } > "$BODY_FILE"
  gh issue create --body-file "$BODY_FILE"
  ```
- Use `<<-` with hard tabs (works but YAML editors often expand tabs).

The `--body-file` form is preferred because it also avoids `gh issue`
double-interpolation of `${VAR}` inside body strings.

## Solution

PR #3030 adds:

- `.github/workflows/scheduled-oauth-probe.yml` — uses GET + `--max-redirs 0`
  for `/authorize`, sources `apikey` from `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY`
  for `/settings`, builds issue bodies with `printf` + `--body-file`.
- `apps/web-platform/scripts/configure-sentry-alerts.sh` — duplicate-name
  guard on the upsert lookup, prescribes only valid intervals.
- `apps/web-platform/test/auth/sentry-tag-coverage.test.ts` — drift-guard
  ensuring every Supabase auth verb call site carries `feature:auth` +
  `op:<verb>` tags so the alert filters work.
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — L3-first
  triage gate plus failure-mode taxonomy and accepted-interval enum.

## Prevention

1. **External-API plan claims must include a runtime verification step.**
   The plan subagent prescribed `-sI` on `/authorize` and omitted `apikey`
   on `/settings` based on docs alone. Both behaviors only surface when
   you actually `curl` the prod endpoint. Plan skill Sharp Edges should
   require a curl-against-prod check for any synthetic-probe scope.
2. **Sentry alert-rule writes should always include a duplicate-name
   pre-check.** Idempotent upserts that match-by-name without a count
   guard are a silent-failure trap.
3. **GHA heredocs should default to `--body-file`.** Adding new workflow
   steps that compose `gh issue create` bodies with heredocs has been
   wrong twice now (this PR + earlier reviewers flagging it). Make
   `printf into tempfile + --body-file` the canonical pattern in the
   workflow library.

## Session Errors

These pipeline-level errors surfaced during PR #3030's session and feed
back into the workflow definitions that produced them.

- **Plan research falsely claimed `signup/page.tsx` already had Sentry mirror.** The
  plan asserted "All four source files already carry feature:auth tags per
  PR #2994" — but `app/(auth)/signup/page.tsx` had no `reportSilentFallback`
  call at all. The drift-guard test would have failed on `main` without an
  inline fix. **Recovery:** added the mirror to `signup/page.tsx` matching
  `login/page.tsx`'s pattern. **Prevention:** plan Phase 1.1 should `git
  grep` for the literal symbol claimed (`feature:\s*"auth"`) on every
  source file referenced, not trust the prior PR's coverage description.
- **Plan prescribed `curl -sI` on `/auth/v1/authorize`.** Caught by
  pattern-recognition reviewer; verified live to return 405. **Recovery:**
  replaced with GET + `--max-redirs 0` in the inline review-fix commit.
  **Prevention:** plan Sharp Edges entry "for synthetic probes, verify
  HTTP method support against the live endpoint before prescribing -I /
  -X HEAD; many APIs decorate Allow: GET only." (See route-to-definition
  proposal below.)
- **Plan omitted `apikey` header on `/auth/v1/settings`.** Caught by
  pre-merge QA dry-run, not by any reviewer. **Recovery:** added
  `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY` to the workflow env and the
  curl `apikey` header. **Prevention:** QA skill should treat any new
  scheduled-probe workflow as a target for live curl verification before
  merge, not just a docs sanity check.
- **Plan's heredoc body had 10-space leading indent rendering as code
  block.** Caught by security reviewer reading the file. **Recovery:**
  rewrote body composition to use `printf` into a tempfile +
  `--body-file`. **Prevention:** workflow style reference (or actionlint
  custom rule) should reject heredoc-into-`gh issue create --body
  "$BODY"` patterns in favor of `--body-file`.
- **First `Write` of `scheduled-oauth-probe.yml` was advisory-blocked.**
  Plugin security hook returned an advisory message that read like a
  deny; first attempt did not write. **Recovery:** retried the same
  Write after re-reading the hook's intent (env: vars already in use);
  second attempt succeeded. **Prevention:** the plugin hook's text
  should distinguish "advisory reminder" from "denied" more clearly so
  the model doesn't over-correct.
- **(Forwarded from session-state.md, Plan phase)** Plan-phase Write tool
  wrote files to the bare repo path instead of the worktree — recovered
  via `mv`. **Prevention:** plan skill should always pass absolute
  worktree paths to Write/Edit when running inside a worktree, not
  relative paths.
- **(Forwarded)** Context7 MCP quota exhausted during plan deepening.
  **Recovery:** pivoted to WebFetch + WebSearch for Sentry API docs.
  **Prevention:** none — quota exhaustion is a hard external limit; the
  WebFetch fallback worked.
- **Bash CWD doesn't persist between Bash tool calls.** Caused one
  `cd: No such file or directory` after a fresh shell. **Recovery:**
  chained `cd <abs-path> && <cmd>` per call. **Prevention:** already
  encoded in AGENTS.md `cq-for-local-verification-of-apps-doppler`-style
  rules; recurrence is an attention slip, not a missing rule.

## References

- PR #3030 — implementation
- Issue #2997 — feature spec
- PR #2994 — Sentry mirroring on auth ops (the contract this drift-guard
  protects)
- `knowledge-base/project/learnings/integration-issues/sentry-api-boolean-search-not-supported-20260406.md`
  — companion Sentry quirk (search syntax)
- `knowledge-base/project/learnings/best-practices/2026-04-28-sentry-payload-pii-and-client-observability-shim.md`
  — companion learning on Sentry payload PII guard (used in signup mirror)
