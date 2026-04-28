---
title: "Postmortem: app.soleur.ai/dashboard error.tsx outage"
date: 2026-04-28
incident_pr: 3014
incident_window: "TBD (operator fills in: Sentry first-seen → fix-deploy time)"
suspected_change: "PR #3007 — JWT-claims guardrails for NEXT_PUBLIC_SUPABASE_ANON_KEY"
brand_threshold: single-user incident
status: open (operator fills in once Phase 1 + Phase 2 are complete)
triggers:
  - dashboard error boundary
  - inlined supabase claim
  - canary swap broken bundle
  - module-load throw
  - validate-anon-key throw
  - validate-url throw
---

## Actor key

Each step below is tagged with one of:

- **`agent`** — fully agent-executable, no human action needed.
- **`agent-with-ack`** — agent runs the command non-interactively, but the
  per-command ack rule (AGENTS.md `hr-menu-option-ack-not-prod-write-auth`)
  requires explicit operator approval of the exact command before execution.
- **`human`** — genuinely human-only (visual sign-off, OAuth consent,
  CAPTCHA, payment surface).

# Postmortem: /dashboard error.tsx outage

## Symptom

Every authenticated visitor to `app.soleur.ai/dashboard` rendered the
Next.js `app/error.tsx` boundary ("Something went wrong / An unexpected
error occurred / Try again"). Sign-in succeeded, but every post-auth
landing failed. No Sentry alerts fired, no canary rollback. Detected
operator-side via direct browser report.

## Three failures, one incident

1. **Production fix** — recent change broke `/dashboard`.
2. **Observability gap** — Sentry / pino / Cloudflare alerts did not fire.
3. **Canary gap** — the canary upgrade promoted the broken bundle to prod;
   `/health` returned 200 throughout.

The PR for this postmortem (#3014) ships the **structural** fixes
(observability migration, segment-scoped error boundary, layered canary
probe set, preflight Check 7). Phase 1 (diagnose root cause) and Phase 2
(hot-fix prod) are operator-driven below — every command is a destructive
or sensitive prod read/write that requires explicit per-command approval
per AGENTS.md `hr-menu-option-ack-not-prod-write-auth`.

## Root-cause hypothesis (verify in Phase 1)

PR #3007 (commit `7d556531`) added `assertProdSupabaseAnonKey` and
`assertProdSupabaseUrl` calls at module load in
`apps/web-platform/lib/supabase/client.ts`. The validators are
**client-bundle only** — `lib/supabase/server.ts`, `service.ts`, and
`middleware.ts` do not invoke them. So:

- The HTML for `/dashboard` arrives at the browser successfully (SSR
  uses the server module).
- Client hydration imports `@/lib/supabase/client`; module-load throws
  on the first failed claim.
- React renders the closest error boundary (root `app/error.tsx`).
- `/health` is middleware-bypassed and never imports the client module —
  the canary probe passes regardless.

The most likely failure modes (Phase 1 disambiguates):

| Hypothesis | Description |
|---|---|
| H1 | Inlined anon-key fails one of: 3-segment shape, `iss=supabase`, `role=anon`, canonical 20-char ref, or the placeholder-prefix denylist |
| H1a | CI Validate step ran on a different value than the docker-build arg |
| H1b | Custom-domain CNAME resolution regressed at CI time (`api.soleur.ai`) |
| H2 | Inlined URL fails canonical hostname / placeholder check |
| H3 | Sentry DSN missing or not inlined (explains the alert silence) |
| H6 | Unrelated regression (PR #2994 OAuth classifier or PR #2994 SW cache bump) |

## Phase 1 — Diagnose (read-only)

Do **not** begin Phase 2 until one of H1/H1a/H1b/H2/H3/H6 is confirmed
with concrete evidence.

### 1.1 Sentry digest review — `agent-with-ack`

Prefer the Sentry REST API (token in Doppler `prd` as `SENTRY_API_TOKEN`)
over the web UI:

```bash
ORG=jikig-ai
PROJECT=soleur-web-platform
SINCE=$(git log -1 --format=%cI 7d556531)
curl -fsSL -H "Authorization: Bearer $SENTRY_API_TOKEN" \
  "https://sentry.io/api/0/projects/${ORG}/${PROJECT}/events/?statsPeriod=24h&query=feature:dashboard-error-boundary OR feature:supabase-validator-throw"
```

Capture: digest, redacted error.message, stack trace, count, first-seen.

Web-UI fallback (`human`): if `SENTRY_API_TOKEN` is unavailable, filter the
prod project in the Sentry UI to events since the suspect deploy and copy
the same fields.

If zero events appear AND the page is broken, **H3 is confirmed** — the
DSN is missing or not inlined; skip to 1.4.

### 1.2 Direct browser console capture (Playwright MCP) — `agent`

```
mcp__playwright__browser_navigate https://app.soleur.ai/dashboard
mcp__playwright__browser_console_messages
```

The browser console carries the unminified error message which pinpoints
the exact assertion that fired (e.g. `NEXT_PUBLIC_SUPABASE_ANON_KEY ref="…" does not match canonical 20-char shape`).

### 1.3 Inspect deployed bundle for inlined claims — `agent`

Reuses `plugins/soleur/skills/preflight/SKILL.md` Check 5 Step 5.4 logic:

```bash
curl -fsSL -A "Mozilla/5.0" https://app.soleur.ai/login -o /tmp/postmortem-login.html
CHUNK=$(grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' /tmp/postmortem-login.html | head -1)
curl -fsSL "https://app.soleur.ai${CHUNK}" -o /tmp/postmortem-chunk.js
JWT=$(grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' /tmp/postmortem-chunk.js | head -1)
PAYLOAD=$(printf '%s' "$JWT" | cut -d. -f2)
PAD=$(( (4 - ${#PAYLOAD} % 4) % 4 ))
if [[ $PAD -gt 0 ]]; then PADDED="$PAYLOAD$(printf '=%.0s' $(seq 1 $PAD))"; else PADDED="$PAYLOAD"; fi
JSON=$(printf '%s' "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null)
printf '%s' "$JSON" | jq -r '"iss=\(.iss) role=\(.role) ref=\(.ref)"'
```

The decoded claims show what the bundle is asserting against. Compare to
the Doppler `prd` value and the GitHub repo secret (1.5).

### 1.4 Sentry DSN presence + bundle inlining — `agent-with-ack`

Two Bash steps (curl does NOT shell-expand `*` over HTTP — discover the
chunk URL via the same pattern as 1.3):

```bash
doppler secrets get NEXT_PUBLIC_SENTRY_DSN -p soleur -c prd --plain
```

```bash
curl -fsSL -A "Mozilla/5.0" https://app.soleur.ai/login -o /tmp/postmortem-login.html
MAIN_CHUNK=$(grep -oE '/_next/static/chunks/main-[a-zA-Z0-9_-]+\.js' /tmp/postmortem-login.html | head -1)
curl -fsSL "https://app.soleur.ai${MAIN_CHUNK}" \
  | grep -oE 'https://[a-z0-9]+@[a-z0-9.-]+sentry\.io/[0-9]+' | head -1
```

If the Doppler value exists but the bundle does NOT contain the DSN, the
build-arg pipeline drops it — verify `reusable-release.yml` build-args
include `NEXT_PUBLIC_SENTRY_DSN`.

### 1.5 Doppler + GitHub-secret state — `agent-with-ack`

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain
doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain
gh secret list -R jikig-ai/soleur --json name,updatedAt
dig +short +time=2 +tries=1 CNAME api.soleur.ai
```

### 1.6 Prod container env diff (read-only) — `agent-with-ack`

```bash
ssh prod-web docker inspect soleur-web-platform \
  --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep -E '^NEXT_PUBLIC_SUPABASE_|^NEXT_PUBLIC_SENTRY_'
```

Note: container env affects server-side reads only; the client bundle is
already inlined. This step exists for completeness and Phase 2's restart.

### 1.7 Decision gate — `agent`

Fill in the **Confirmed Root Cause** section below. The conclusion MUST
cite specific artifacts (Sentry event ID, browser-console transcript,
chunk URL with grep output) — never "I think it's H1." If the cause is
H6 (an unrelated regression), regenerate the plan with the correct root
cause before Phase 2.

## Confirmed Root Cause

(Operator fills in after Phase 1.)

- Hypothesis confirmed: **TBD**
- Evidence (Sentry event ID, browser console, bundle grep): **TBD**
- Failed assertion (or non-validator stack frame): **TBD**

## Phase 2 — Hot-fix (`agent-with-ack` for every step)

**Critical:** the validator is client-bundle / build-time inlined. A
`docker restart` alone will NOT fix the deployed bundle. The fix requires
a NEW build via `web-platform-release.yml`.

### 2.1 Determine the fix shape

| Phase 1 finding | Action |
|---|---|
| Doppler `prd` correct, bundle has wrong inlined value | Trigger re-build of latest main |
| Doppler `prd` is wrong | `doppler secrets set NEXT_PUBLIC_SUPABASE_ANON_KEY=<canonical> -p soleur -c prd`, then re-build |
| GitHub repo secret is wrong | `gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY -R jikig-ai/soleur < /dev/stdin`, then re-build |
| Sentry DSN missing in bundle | Update `reusable-release.yml` build-args, then re-build |

### 2.2 Trigger a new release build

```bash
gh workflow run web-platform-release.yml --ref main
gh run list --workflow=web-platform-release.yml --limit 1 --json status,conclusion
```

Poll until complete. The new bundle's CI Validate step will re-assert the
JWT claims; if it fails again, the secret is still wrong and step 2.1
was misdiagnosed.

### 2.3 Verify canary swap and recovery

```bash
ssh prod-web journalctl -u docker -n 200 | grep DEPLOY
```

Look for `final_write_state 0 "ok"`. If `canary_failed` appears, the new
layered probe set caught the regression — this is the **gate-closed**
success path.

### 2.4 Verify recovery via Playwright MCP — `agent` + `human` sign-off

Agent-driven render check:

```
mcp__playwright__browser_navigate https://app.soleur.ai/dashboard
mcp__playwright__browser_take_screenshot
```

Agent assertion: the rendered HTML must NOT contain `data-error-boundary=`
(the structured marker emitted by `components/error-boundary-view.tsx`).

Human sign-off: visual review of the screenshot — confirm Command Center
renders correctly, not the boundary.

## Recovery Verification

(Operator fills in.)

- New release tag: **TBD**
- Canary swap log line: **TBD**
- Playwright screenshot: **TBD**
- Re-run of Phase 1 step 1.3 (inlined-JWT check passes): **TBD**

## Why both gates failed

| Gate | Why it missed | Fix shipped in #3014 |
|---|---|---|
| Canary `/health` probe | `/health` is middleware-bypassed and never imports `lib/supabase/client.ts`. Inlined-bundle bugs sail through. | Layered probes for `/login` + `/dashboard` + body-content sentinel rejection. Preflight Check 7 enforces presence on every diff that touches `ci-deploy.sh`. |
| Sentry alerts | (Operator confirms via Phase 1.4.) Either DSN missing in bundle, no alert rule on `feature: dashboard-error-boundary`, OR client SDK queue not flushed before page unload. | `app/error.tsx` migrated to `reportSilentFallback`; new `(dashboard)/error.tsx` segment boundary with `segment: dashboard` tag; `lib/supabase/client.ts` wraps validator throws to emit Sentry **before** re-throwing. |
| Cloudflare 5xx alerts | Page returns HTTP 200 (the error boundary IS the rendered output, not a server 5xx). | Out of scope — the layered canary probe + synthetic check (Phase 4.6, deferred) replaces this signal. |

## Follow-up issues

| ID | Description | Automation path |
|---|---|---|
| D1 | Layer 2 canary headless-browser probe (chromium-in-canary). | Playwright in a scheduled GH Actions workflow OR chromium added to the canary image; agent-implementable. |
| D2 | Synthetic auth fixture for full /dashboard render verification in canary. | Doppler-stored test JWT + Playwright; agent-implementable. |
| D3 | Cloudflare worker for error-boundary HTML detection (belt-and-suspenders). | Cloudflare Workers MCP / Terraform; agent-implementable. |
| D4 | Sentry settings drift detection cron (mirroring `scheduled-cf-token-expiry-check.yml`). | Scheduled GH Action + Sentry REST API; agent-implementable. |
| D5 | Landed in #3014 — `apps/web-platform/infra/canary-bundle-claim-check.sh` is wired into ci-deploy.sh as Layer 3. | n/a — closed. |
| D6 | Sentry alert rule on `feature: "supabase-validator-throw"` and `feature: "dashboard-error-boundary"` (event.count > 10 in 1m). | Sentry REST API (`/api/0/projects/{org}/{project}/rules/`); agent-implementable. |
| D7 | Synthetic auth-flow check hitting `/dashboard` from a signed-in fixture every 5 min. | **Agent-automatable**: scheduled GH Actions workflow (mirrors `scheduled-cf-token-expiry-check.yml`) + Playwright MCP + Doppler-stored test fixture. NOT a third-party SaaS dependency — implement in-tree. |

(Agent: file each as a GitHub issue with the appropriate milestone and link back here. Each row's "Automation path" column names the implementation route — agent-implementable rows do NOT need human-only labelling.)

## References

- PR #3007 — added `assertProdSupabaseAnonKey` (the change under suspicion)
- PR #2975 — `validate-url.ts` precedent
- AGENTS.md `hr-menu-option-ack-not-prod-write-auth`
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`
- AGENTS.md `hr-weigh-every-decision-against-target-user-impact`
- `apps/web-platform/lib/supabase/client.ts` — module-load throw site (now wrapped)
- `apps/web-platform/infra/ci-deploy.sh` — canary probe set (now layered)
- `knowledge-base/engineering/ops/runbooks/canary-probe-set.md` — canary contract
