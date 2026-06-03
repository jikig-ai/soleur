---
title: "Generate-link button silently broken by tenant-mint dependency (PR #3854 regression)"
date: 2026-06-04
incident_pr: 4913
incident_window: "2026-05-16 → 2026-06-04 (~19 days)"
recovery_at: "on merge of PR #4913"
suspected_change: "PR #3854 (#3244 PR-C tenant migration, merged 2026-05-16)"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - system
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

The "Generate link" button in the KB document Share popover silently stopped producing public share links. Clicking it returned the user to the identical idle panel instead of rendering the `/shared/<token>` link + Copy/Revoke controls. The regression was introduced ~19 days earlier by PR #3854 (the `#3244` PR-C tenant-scoped-query migration) and ran unnoticed in production until the founder hit it while dogfooding.

## Status

resolved — fix landed in PR #4913 (service-role fallback on tenant-mint failure).

## Symptom

Clicking "Generate link" bounced back to the "Generate a public link to share this document with anyone." idle panel with no error toast. The popover *opened* normally (the GET/`checkShare` path was unaffected), which masked the failure as "nothing happens on click" rather than an obvious error.

## Incident Timeline

- **Start time (detected):** 2026-06-04 (founder report via screenshot)
- **End time (recovered):** on merge of PR #4913
- **Duration (MTTR):** ~hours from report to fix (≈19 days latent in prod before detection)

| Actor | Time (UTC) | Action |
|---|---|---|
| system | 2026-05-16 | PR #3854 merges; `POST /api/kb/share` read path now depends on a tenant-JWT mint that 503s on failure. |
| human | 2026-06-04 | Founder reports the dead "Generate link" button (screenshot). |
| agent | 2026-06-04 | Root cause traced via git archaeology to PR #3854 `route.ts:37`; service-role fallback implemented + tested (PR #4913). |
| agent | 2026-06-04 | Multi-agent review (security/user-impact/test-design/code-quality) — `denied_jti` fallback ceiling verified sound. |

## Participants and Systems Involved

`apps/web-platform` Next.js API routes (`/api/kb/share`, `/api/kb/upload`), `server/kb-route-helpers.ts` (`resolveUserKbRoot`), `lib/supabase/tenant.ts` (`getFreshTenantClient` / `mintFounderJwt`), Supabase GoTrue (JWT mint), the per-founder mint ceiling (migration 048, 60/hr).

## Detection (+ MTTD)

- **How detected:** external/manual — founder dogfooding, not monitoring. The failure DID emit a `reportSilentFallback` Sentry signal on each mint failure, but no alert routed it to attention and no one was watching the share-POST 503 rate.
- **MTTD:** ~19 days (merge 2026-05-16 → report 2026-06-04).

## Triggered by

system — a sibling migration PR changed a helper signature, swapping a reliable service-role read for a failure-prone tenant-JWT mint on a user-facing path.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| `resolveUserKbRoot` 503s on tenant-mint failure | `route.ts:37` diff in #3854; client resets to idle on non-ok | — | confirmed |
| Deterministic RLS block on the self-SELECT | — | RLS policy `auth.uid()=id` permits the self-read under a successful mint | ruled out |
| Field rename (`kbRoot`) | — | both old/new helper return `kbRoot`; no drift | ruled out |

## Resolution

On `RuntimeAuthError`, `resolveUserKbRoot` now falls back to a service-role read of the caller's own `users` row (`.eq("id", userId)`) instead of returning 503. The same `workspace_status === "ready"` + `extras` validation runs on the fallback, so a genuinely not-ready workspace still 503s. `reportSilentFallback` still fires so a chronically-failing mint stays visible. Carries `extras` through, covering `POST /api/kb/upload`.

## Recovery verification

Pre-merge: new RED→GREEN tests in `kb-route-helpers.test.ts` (4 cases fail against pre-fix code, pass after); full webplat vitest shard green (8483 passed). Post-merge: the plan's Playwright probe (open KB doc → Share → Generate link → assert active state with `/shared/<token>`) runs against the deployed app.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the button do nothing?** The `POST /api/kb/share` handler returned 503 and the client `generateLink` callback resets to idle on any non-ok response.
2. **Why did the handler 503?** `resolveUserKbRoot` threw/caught a `RuntimeAuthError` from `getFreshTenantClient` and mapped it to a 503 "Workspace not ready".
3. **Why did `getFreshTenantClient` fail?** It performs a full GoTrue `generateLink + verifyOtp` JWT mint gated by a 60/hr per-founder ceiling — a heavyweight, rate-limited, failure-prone dependency.
4. **Why was a JWT mint in the path at all?** PR #3854 changed the self-row `workspace_path` read from a service-role read to a tenant-scoped read for isolation, but the privileged *write* (`createShare`) on this path was already service-role — so the tenant scoping bought no isolation benefit while adding a failure mode.
5. **Why did it go unnoticed for ~19 days?** The failure emitted a Sentry breadcrumb but no alert was wired to the share-POST 503 / mint-failure rate, and the popover still opened (GET path healthy), masking the break as "nothing happens."

## Versions of Components

- **Version(s) that triggered the outage:** the build shipping PR #3854 (merged 2026-05-16).
- **Version(s) that restored the service:** the build shipping PR #4913.

## Impact details

### Services Impacted

KB document public-link generation (`POST /api/kb/share`) and KB upload (`POST /api/kb/upload`) — both 503'd whenever the tenant mint failed (ceiling trip or GoTrue hiccup).

### Customer Impact (by role)

- Prospect: none (auth-gated feature).
- Authenticated app user: **primary impact** — could not generate a public share link for any KB document, and KB uploads could fail, whenever the tenant mint failed. Silent (no error surfaced).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none (no charge path).
- OAuth installation owner: indirect — `repo_url`/`github_installation_id` reads via the upload path were affected on mint failure.

### Revenue Impact

None directly; brand/trust cost of a silently-broken core sharing feature for the founder (tenant-zero), brand-survival threshold `single-user incident`.

### Team Impact

One founder-reported bug; ~one session to root-cause + fix.

## Lessons Learned

### Where we got lucky

- The fix was a verbatim re-introduction of the pre-#3854 service-role read (byte-identical query shape), so column parity was guaranteed and the blast radius was tiny.
- The privileged write was already service-role, so the fallback introduced no new privilege — the `denied_jti` ceiling held without re-architecture.

### What went well

- Git archaeology pinned the exact regression commit/line quickly; the asymmetry (GET healthy, POST broken) confirmed the locus.
- The existing `reportSilentFallback` plumbing meant the fix could restore availability *and* keep the underlying mint failure observable.

### What went wrong

- A migration optimizing for isolation introduced a heavyweight, rate-limited dependency into a user-facing read path **whose write was already service-role** — no isolation benefit, pure new failure surface.
- No alert was wired to the share-POST 503 / tenant-mint-failure rate, so a Sentry-visible signal went unwatched for ~19 days.
- The client treats *any* non-ok as "reset to idle" with no error toast, turning a server 503 into an invisible dead-end.

## Follow-ups

- [ ] Apply the same mint-failure resilience to `authenticateAndResolveKbPath` (file PATCH/DELETE routes), with a per-cause `denied_jti` adjudication — tracked in #4914.
- [ ] Wire an alert on the `resolveUserKbRoot.tenant-mint` / `authenticateAndResolveKbPath.tenant-mint` `reportSilentFallback` rate so a recurring mint failure pages instead of sitting latent.
- [ ] Consider surfacing a user-facing error toast on a genuine share 503 (client `share-popover.tsx`) so a real not-ready state is not an invisible idle bounce.

## Action Items

- #4914 — file-route tenant-mint fallback (already filed; `type/chore` + `deferred-scope-out`).
- Alert on tenant-mint `reportSilentFallback` rate — to file as a `type/chore` observability item (no existing alert covers the share/upload mint-failure rate).
