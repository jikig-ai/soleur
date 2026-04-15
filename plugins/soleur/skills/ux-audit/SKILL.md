---
name: ux-audit
description: This skill should be used when auditing live web-platform UI for decay. Screenshots bot routes, delegates to ux-design-lead audit mode, dedupes, files capped issues.
---

# ux-audit

Recurring UX-review agent loop. Scheduled via `.github/workflows/scheduled-ux-audit.yml` on push to `main` under `apps/web-platform/{app,components}/**` and a monthly `0 9 1 * *` cron. Can be run locally in dry-run mode for calibration.

**Architecture:** thin orchestrator (this skill) → delegates screenshot analysis to the `ux-design-lead` agent in audit mode. Mirrors the `soleur:competitive-analysis` / `competitive-intelligence` split.

## Invocation

**Primary:** the scheduled workflow (`.github/workflows/scheduled-ux-audit.yml`) runs this skill via `claude-code-action`. That's the production path.

**Local / dev:** invoke from a Claude Code session (terminal, IDE, web) with Doppler secrets loaded into the environment. The skill is registered as `soleur:ux-audit`:

```bash
# Load credentials (one terminal session)
doppler run -c prd_scheduled -- \
  doppler run -c prd --fallback-only -- \
  claude

# Then inside Claude Code, invoke the skill via its slash form:
/soleur:ux-audit
# Or with a single-route override:
/soleur:ux-audit --route /dashboard
```

**From another agent:** use the Skill tool:

```text
Skill(skill: "soleur:ux-audit")
Skill(skill: "soleur:ux-audit", args: "--route /dashboard")
```

Dry-run toggle: export `UX_AUDIT_DRY_RUN=true` before launching Claude Code (or set it via `workflow_dispatch.inputs.dry_run` in the workflow). The skill reads the env var at runtime.

Env vars required (loaded from Doppler `prd_scheduled`, falling back to `prd`):

- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SITE_URL` — from `prd`
- `UX_AUDIT_BOT_EMAIL`, `UX_AUDIT_BOT_PASSWORD` — from `prd_scheduled`
- `UX_AUDIT_DRY_RUN` — `true` writes findings JSON to stdout + workflow artifact; `false` files issues
- `GH_TOKEN` — for `gh issue create` / `gh issue list`

Single dry-run knob: `workflow_dispatch.inputs.dry_run` → `UX_AUDIT_DRY_RUN` env. One plumbing path.

## Constants (inline, not configurable)

- `CAP_OPEN_ISSUES = 20` — global cap on open `ux-audit`-labeled issues; skill refuses to file when reached
- `CAP_PER_RUN = 5` — severity-ranked top-N findings filed per run
- `CAP_PER_ROUTE = 2` — no single route may contribute more than 2 findings to the top-N, so anonymous funnel pages (login/signup) cannot monopolize output and crowd out bot-authenticated dashboard findings. Ref #2378.
- `FINDING_CATEGORIES = ["real-estate", "ia", "consistency", "responsive", "comprehension"]` — dedup hash keys on this exact set

## Workflow

### 1. Load route list + bot creds

Read [route-list.yaml](./references/route-list.yaml). Each route has `{path, auth, fixture_prereqs, viewport}`. If `--route <path>` is passed (dev affordance), filter to that single route.

### 2. Global-cap check

```bash
OPEN_COUNT=$(gh issue list --label ux-audit --state open --json number --jq 'length')
if [ "$OPEN_COUNT" -ge 20 ]; then
  echo "::warning::Global ux-audit cap reached ($OPEN_COUNT open). Refusing to file new issues."
  exit 0
fi
```

### 3. Per-route screenshot capture

For each route:

1. If `auth: bot`, invoke [bot-signin.ts](./scripts/bot-signin.ts) once per run (the storage-state file is reused across routes). Script writes the Supabase SSR auth cookie to `${GITHUB_WORKSPACE}/tmp/ux-audit/storage-state.json` (absolute path, per [hr-mcp-tools-playwright-etc-resolve-paths]).
2. Verify route `fixture_prereqs` are satisfied. If `kb_workspace_deferred` appears in `fixture_prereqs`, log `route skipped: missing prereq kb_workspace_deferred (tracked in #2351)` and continue. The [bot-fixture.ts](./scripts/bot-fixture.ts) `seed` subcommand idempotently satisfies `tcs_accepted`, `billing_active`, and `chat_conversations`.
3. Launch Playwright MCP. Use `browser_navigate` + `browser_take_screenshot` at the route's `viewport` size. Save PNG to `${GITHUB_WORKSPACE}/tmp/ux-audit/<route-slug>.png` (slug `/dashboard/kb` → `dashboard-kb`).
4. If navigation/screenshot fails for a single route, log `::warning::route capture failed: <path>` and continue — one route failure does not abort the run.

### 4. Delegate to ux-design-lead (audit mode)

Invoke `ux-design-lead` via the Task tool with a prompt containing:

```text
mode: audit
viewport: {w: 1440, h: 900}
routes: [{path: "/dashboard", ...}, ...]
screenshots: ["/absolute/path/to/dashboard.png", ...]
```

Parse the agent's output as JSON. If parsing fails: log `::error::malformed agent output for route <path>` and skip that route's findings. Do NOT retry — the parse-guard isolates a bad run instead of looping.

### 5. Dedup (single-layer hash search)

For each finding, compute the hash via [dedup-hash.ts](./scripts/dedup-hash.ts): `sha256(utf8("{route}|{selector}|{category}"))`. Empty selector coarsens to `*`.

Check against existing issues (open OR closed) in a single search:

```bash
EXISTS=$(gh issue list --label ux-audit --state all --search "ux-audit-hash: $HASH" --json number --jq 'length')
if [ "$EXISTS" -gt 0 ]; then
  echo "dedup-suppressed: $HASH"
  continue
fi
```

Closed issues count. If the founder wants to resurface a closed finding, they reopen it. No time-based expiry.

### 6. Severity-rank + cap

Sort surviving findings by severity (`critical` > `high` > `medium` > `low`) then stable by `route`. Then apply `CAP_PER_ROUTE = 2`: walk the sorted list and drop any finding that would be the 3rd+ entry for a route already seen. Finally, take the top `CAP_PER_RUN = 5` of what remains.

The per-route cap runs **before** the global cap so dropped anonymous-route findings free up slots for dashboard findings rather than the reverse. If fewer than 5 findings survive both caps, file what remains — the output is intentionally under-filled rather than padded with dropped-route duplicates.

### 7. File issues (or dry-run to stdout)

**Dry run** (`UX_AUDIT_DRY_RUN=true`): write the capped findings array as JSON to stdout AND to `${GITHUB_WORKSPACE}/tmp/ux-audit/findings.json` (workflow uploads as an artifact). Do not call `gh issue create`.

**File mode** (`UX_AUDIT_DRY_RUN=false`): for each finding, write a body file under `${GITHUB_WORKSPACE}/tmp/ux-audit/body-<hash>.md` containing:

```markdown
**Route:** `<route>`
**Category:** `<category>`
**Severity:** `<severity>`

<description>

**Fix hint:** <fix_hint>

**Screenshot:** attached below.

<!-- ux-audit-hash: <64-hex> -->
```

Then (via `env:` vars, never inline per [hr-in-github-actions-run-blocks-never-use]):

```bash
gh issue create \
  --title "ux: $TITLE" \
  --body-file "$BODY_FILE" \
  --label ux-audit,agent:ux-design-lead,domain/product \
  --milestone "Post-MVP / Later"
```

Attach the screenshot to the issue via `gh api /repos/:owner/:repo/issues/:number -f body=...` after creation (GitHub's issue-attachment upload requires a multipart POST against the issue ID, not available on `gh issue create`).

### 8. Cleanup

Call `browser_close` to release the Playwright session (per [cq-after-completing-a-playwright-task-call]). Leave `storage-state.json` in place — it's gitignored and the workflow runner is ephemeral.

## Bot fixture spec

Managed by [bot-fixture.ts](./scripts/bot-fixture.ts) (DB-only v1). Seeds idempotently via `conversations.session_id` markers.

Satisfies (sets on `public.users`):

- `tc_accepted_version = '1.0.0'` (matches current `TC_VERSION`), `tc_accepted_at = NOW()`
- `onboarding_completed_at = NOW()`
- `subscription_status = 'active'`, synthetic `stripe_customer_id='cus_ux_audit_fixture'`, `stripe_subscription_id='sub_ux_audit_fixture'`, `current_period_end = NOW() + 365d`

Creates:

- 2 `conversations` rows with `session_id` keys `ux-audit-fixture-conv-1|2` (CMO + CTO domain leaders)
- 3 + 4 `messages` rows across the 2 conversations

Does NOT create:

- KB files — deferred to #2351 (files live in GitHub workspace, not Supabase). `/dashboard/kb` audits empty state; fixture_prereqs marker `kb_workspace_deferred` skips the route.
- Team members — no team-members table exists in Phase 1 schema
- Service integrations — no services table exists

**Fixture invariants** (audited during every seed):

- Only `ux-audit-bot@jikigai.com` appears as a real email. `@example.com` and placeholder Stripe IDs are the only synthetic strings.
- No real API keys, no real payment info, no strings matching `sk_live_`, `cus_[A-Za-z0-9]{14,}`, or GitHub `ghp_` / `ghs_` patterns.

## References

- [route-list.yaml](./references/route-list.yaml) — route manifest (path, auth, fixture_prereqs, viewport)
- [bot-fixture.ts](./scripts/bot-fixture.ts) — seed/reset bot DB state
- [bot-signin.ts](./scripts/bot-signin.ts) — sign in, write Playwright storageState
- [dedup-hash.ts](./scripts/dedup-hash.ts) — canonical finding-hash computation
- Agent: `plugins/soleur/agents/product/design/ux-design-lead.md` (`## UX Audit (Screenshots)` section)
