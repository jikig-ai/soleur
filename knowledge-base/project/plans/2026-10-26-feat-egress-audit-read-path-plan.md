---
title: "feat: workspace-visible egress audit log, PR2 read path and view"
date: 2026-10-26
slug: feat-egress-audit-read-path
branch: feat-egress-audit-read-path
issue: 9545
closes: 9545
type: feature
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-egress-audit-read-path/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-10-25-egress-audit-read-path-brainstorm.md
wireframe: knowledge-base/product/design/settings/egress-audit-log.pen
---

# feat: workspace-visible egress audit log, PR2 read path and view

## Overview

PR1 of #9545 (merged 2026-10-15) collects per-workspace egress counts into `workspace_egress_audit_rollup` (migration 162) with no reader. PR2 adds the member-facing read side:

1. One migration, numbered at the last rebase (`NNN_egress_audit_summary_rpc`, see Phase 0), adding the `SECURITY DEFINER` function `get_egress_audit_summary`, callable by current workspace members only. No SELECT policy, no table grant.
2. A server-side loader (`server/egress-audit-read.ts`) that calls the RPC through the cookie client and returns a tagged result. There is **no HTTP route** (CTO ruling 2026-10-26, reversing the brainstorm's thin-route decision: nothing consumes it).
3. A server-rendered destination page `/dashboard/settings/scope-grants/egress-audit` — host table, filter chips (links), truncated notice, error and three empty states (wireframes `07-01..07-21`, amended in Phase 5).
4. Card changes on Scope Grants "Agent web access": a "View egress audit log" link in both toggle states, a "Last request: X ago" hint, and the enable-dialog copy replaced.
5. The public-document, DPIA t6 and ADR-288 changes that make the PR1 text true for a live viewer.

## Research Insights

**Premise validation (Phase 0.6, corrected by the sharp-edges pass).** Held: #9545 OPEN, draft PR #11115 open, migration 162 (rollup), `is_workspace_member`, `withUserRateLimit`, `reportSilentFallback`, flag `egress-audit-collection` and ADR-288 exist on `origin/main`; no `get_egress_audit_summary` or egress read surface exists. **Corrected:** migration number 164 is *not* free: `origin/main` stops at 163, but open draft PRs #10901 and #10905 carry `164_git_data_erasure_pending.sql`, and branch `feat-one-shot-codex-web-live-paths` carries 165 through at least 173. The ordinal is therefore chosen at the last rebase as max-over-all-`origin/*`-refs plus one (Phase 0, AC12).

**Property List (Phase 0.6b).**

- P1. A current workspace member can read their own workspace's 30-day egress summary through the RPC; no other role or tenant can execute it (pending invitee, removed member, other tenant, anon, service role).
- P2. The view never presents counts or hosts as complete, and never shows a person or session.
- P3. An error is never rendered as an empty log; the empties are distinguishable.
- P4. History stays readable after web access is switched off (ruling D).
- P5. A member who opens the enable dialog is told, truthfully, what is recorded and who can see it.

**Cut List.** (mechanism → property → what already covers it)

- New member SELECT policy on the rollup → P1 → covered by the RPC (a policy would make the table a directly readable viewer).
- New read-side feature flag → P1/P4 → covered by the per-org ingest flag (data only exists where collection is on).
- Separate "last request" RPC for the card → covered by the same RPC with `p_limit = 0`.
- `GET /api/workspace/egress-audit`, client fetch state machine, `withUserRateLimit`, 429 state, abort guard → covered by a server-rendered page calling the RPC directly (CTO F1; two panel reviewers).
- `p_window` parameter (24h/7d) → no ask; the window is fixed at 30 days (three reviewers; a window argument is an additive change later).
- Workspace-name header and `workspace` response block → covered by the fail-loud workspace reader (CTO F3).
- Function-level `statement_timeout` → proved a no-op (CTO F2).
- `bytes_out`, session counts, per-member attribution, CSV export, time-range selector, 24h count → out of scope (brainstorm).

**Verified code facts (file anchors on `origin/main`).**

- Rollup columns, PK and CHECKs: `162_workspace_egress_audit_rollup.sql` (PK `(workspace_id, bucket_start, requested_host, decision, source_host)`; `decision IN ('allowed','denied','other')`; host regex excludes `(`, and `(other)` is the one literal exception). RLS on, zero policies, `REVOKE ALL FROM PUBLIC, anon, authenticated`; `service_role` keeps its default table access.
- Overflow: once a (workspace, bucket) holds 500 rows, new keys fold into `requested_host = '(other)'` keeping the event's `decision` and `source_host`; merges use `GREATEST`/`LEAST`, never `SUM`. One overflow row exists per (bucket, decision, source_host) and each stored count is already a lower bound.
- Retention: daily purge by `last_seen` older than 30 days (cron `30 4 * * *`), so rows can live about a day past 30 days; the read bounds the window itself.
- No toggle join on read: `web_egress` is read only at ingest and in the requester-erase refusal. Toggle-off skips new writes and deletes nothing, so P4 holds without work.
- RPC conventions: `138_agent_engine_runs.sql` (`is_workspace_member(..., auth.uid())`, `42501`, `search_path = public, pg_temp`, REVOKE PUBLIC+anon, GRANT authenticated); `158_workspace_web_egress.sql`. `REQUIRED_REVOKE_ROLES` = public, anon, authenticated (`test/migration-lint/definer-grants.ts`). Every authenticated-callable definer must be registered: add an `ATTACK_SQL` entry in `test/rls-fuzz/rpc-cases.ts`.
- Workspace resolution: `resolveCurrentWorkspaceId` falls back to the user's own id on null or error. `readWorkspaceIdFromDb(userId, supabase)` (`server/workspace-resolver.ts`) returns null for an absent pointer and throws on a read error, never falling back; `app/api/dashboard/settings/agent-engine/route.ts` already maps both to 503. Neither validates membership; only the RPC does.
- Flag: `getRuntimeFlag(name, identity)` (`lib/feature-flags/server.ts`) reads `identity.orgId`; the ingest evaluates it per workspace org with `role: "prd"`. It never throws on a Flagsmith outage (falls back to the env mirror, 0 in prd, cached 30s), so an outage reads "off" for ingest and read side alike. The root provider uses the caller's oldest-membership org and scope-grants page reads pass `orgId: null`, so neither fits.
- Postgres: a function-level `SET statement_timeout` (and a body-level `SET LOCAL`) does not re-arm the timer of the already-running outer statement (CTO proof on Postgres 17: a 3s `pg_sleep` under a 1s function setting ran 3.00s; an outer 2s timeout won). The RPC's real bound is the role/PostgREST timeout plus its structural bounds.
- Page conventions: `scope-grants/page.tsx` already calls RPCs server-side through the cookie client; `settings/loading.tsx` streams a skeleton; `(dashboard)/error.tsx` exists but would replace the settings shell, so expected outcomes render in place. Settings shell highlights a tab by `pathname.startsWith`, so a child route under `scope-grants/` keeps the Scope Grants tab active. Internal links use `NavLink` (nav-pending channel, ADR-255).
- Tests: live-DB suites `test/rls-fuzz/*.integration.test.ts`, gated `RLS_FUZZ_LOCAL=1`, run in CI by `.github/workflows/rls-authz-fuzz.yml` (egress step floor `numPassedTests >= 15`; the file already has 21 cases). `bun test` matches nothing in `apps/web-platform` (`bunfig.toml` ignores all); run `cd apps/web-platform && ./node_modules/.bin/vitest run <file>`; `bun run test:rls-fuzz` is fine. Harness: `harness-fixture.ts` (`asTenant`, `attackAs`, `seedTwoTenant` with co-member C); no pending-invitee or removed-member fixture exists.

**Institutional learnings applied.**

- `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` — explicit REVOKE from PUBLIC, anon, authenticated and service_role; prove it with a live call.
- `2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind.md` — mocked clients cannot prove a member can call the RPC; test it live as `authenticated`.
- `2026-07-11-rls-migration-verify-savepoint-and-signature-scope.md` — a raised 42501 aborts the transaction; assert SQLSTATE exactly inside a SAVEPOINT.
- `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md` — deny-test arguments must be schema-valid.
- `2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md` — RPC in its own migration; any `docs/legal` edit needs a `LEGAL_DOC_SHAS` re-pin and date-mirror sync.
- `2026-04-12-silent-rls-failures-in-team-names.md` — loading, error and empty stay distinct.
- `2026-07-18-rls-initplan-wrap-breaks-verify-sentinels-and-dev-prod-policy-divergence.md` — verify sentinels use deparsed forms.
- `2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md` — a fault that can repeat per page load uses the debounced mirror.
- `2026-05-30-migration-number-collision-and-stale-plan-current-state.md` — probe every pushed branch, not only `origin/main`.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| Migration 164 is next | 164 is claimed by drafts #10901/#10905; 165-173+ by the codex branch | Number chosen at the last rebase (Phase 0, AC12) |
| "thin `GET` route over the RPC" (brainstorm, spec TR2) | No consumer needs it; the page can call the RPC directly like the existing Scope Grants page | CTO F1: no route; loader + server page; TR2 amended |
| Brainstorm: "verify `resolveCurrentWorkspaceId` re-validates membership" | It does not and falls back to the user's own id | Loader uses the fail-loud `readWorkspaceIdFromDb`; null → "unbound" state, throw → "unavailable"; RPC never called in either case; membership stays enforced only by the RPC |
| PR1 toggle join "may drop rows when web access is off" | Only new writes are skipped; nothing is deleted on toggle-off | No change; the RPC joins neither `web_egress` nor the flag; AC3 asserts history stays readable |
| CTO ruling: overflow "one row per decision" | Stored overflow is one per (bucket, decision, source_host) | RPC sums overflow across buckets and sources, grouped by `decision` only (a sum of lower bounds is a lower bound) |
| Spec TR1: `statement_timeout 5s` header | Proved a no-op for the running statement | Removed from RPC, AC1 and the shape test; bound = role timeout + `p_limit` ≤ 500 + PK-led range scan; AC records `authenticated`'s `rolconfig` and a worst-case `EXPLAIN ANALYZE` |
| RPC takes a window enum (CTO ruling in brainstorm) | UI fixes 30d; three reviewers flag dead surface in a definer function | Window hard-coded to 30 days; a parameter is an additive migration if ever needed |
| Spec FR5: notice when the flag is "on for the workspace's org" | Root provider = oldest-membership org; page reads pass `orgId: null` | One shared helper `isEgressAuditCollectionOn(orgId)` in `server/egress-audit-collection.ts` (used by ingest, loader and page); outage reads "off" for ingest and read side alike, so hidden notice and "Recording isn't on" are both true at that moment |
| Wireframe e2: "Recording since <date>" and "Agents haven't contacted any site" | No recording-start date is stored; "haven't contacted" contradicts best-effort capture | Wireframe delta: "No requests recorded yet", no date; body "Nothing has been recorded yet. Requests can take a few minutes to appear." plus Refresh |
| Wireframe: "history stays available until Nov 25, 2026" | Rows expire individually about 30 days after they were recorded; no stored source for the date | No date anywhere: "Records are deleted about 30 days after they were recorded." e3: "Nothing recorded in the last 30 days. Web access is off, so nothing new is recorded." |
| Wireframe header "…whether each request was allowed" and summary "N sites listed" | "each" overpromises; "sites listed" is tied to a cap that counts (host, outcome) pairs | Subtitle "Sites your workspace's agents contacted in about the last 30 days, with the outcome of each (best-effort)."; summary "At least N requests · at least M blocked"; truncation "200 most recent entries" |
| ADR-288, `targets.ts`, `server.ts` flag comment, 162 header, C4 `model.c4` text, `dsar-export-allowlist.ts` rationale, `egress-audit-dsar.md:11`: "member SELECT policy lands in PR2", "dark", "nothing reads the table" | Superseded by the RPC-only ruling; 162 cannot be edited (immutability lint; its `COMMENT ON TABLE` text is pinned by `verify/162`) | Amend ADR-288; fix the source comments, C4 text and runbook line; leave 162 and its table comment untouched |

## User-Brand Impact

**If this lands broken, the user experiences:** a member opening Scope Grants sees an egress log that is empty when it should show activity (or shows activity as "complete"), or an error page — eroding trust in the one control that tells them what their agents contacted.

**If this leaks, the user's workflow is exposed via:** a cross-workspace, pending-invitee or removed-member read of `get_egress_audit_summary` — revealing which external hosts one workspace's agents contacted, which can disclose what a founder asked an agent to research.

**Brand-survival threshold:** single-user incident.

CPO sign-off: granted, conditional (plan review 2026-10-26). It is withheld if: the live-DB negative cases are not in the required `rls-authz-fuzz` CI; the view or dialog copy merges without CLO sign-off; any per-member, session or `source_host` field reaches the page; or the `egress-audit-collection` flag flip is bundled into this PR. These four are ACs below. `soleur:engineering:review:user-impact-reviewer` runs at review.

## Design (resolved forks)

Every technical fork below is either a CTO ruling (brainstorm, or plan review 2026-10-26) or derives from the verified facts above; none is an operator question.

### D1. RPC contract

```sql
get_egress_audit_summary(
  p_workspace_id uuid,
  p_limit        integer DEFAULT 200,   -- clamped 0..500; 0 = last-request probe only
  p_decision     text    DEFAULT NULL   -- NULL | 'allowed' | 'denied' | 'other'
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
```

- Authz first: `IF auth.uid() IS NULL OR NOT is_workspace_member(p_workspace_id, auth.uid()) THEN RAISE EXCEPTION … USING ERRCODE = '42501'`. A bad `p_decision` raises `22023`.
- Window (fixed 30 days): `bucket_start >= now() - interval '30 days' - interval '15 minutes' AND last_seen >= now() - interval '30 days'` — a PK-led range scan; the `last_seen` bound excludes rows the daily purge has not removed yet. No `statement_timeout` clause (proved ineffective).
- `p_limit = 0`: returns only `{ window, summary: { last_request_at } }` from a single `MAX(last_seen)` over the window; count fields are null, `rows`/`overflow` are empty arrays, `truncated` is false. This is the card's hint read.
- `p_limit > 0`: returns `{ window: {start,end}, truncated, summary: { request_count_min, blocked_request_count_min, last_request_at }, rows: [{host, decision, request_count, last_seen}], overflow: [{decision, request_count, last_seen}] }`.
  - `rows`: real hosts only (`requested_host <> '(other)'`), grouped by `(host, decision)`, `SUM(request_count)`, `MAX(last_seen)`, ordered `last_seen DESC, host`, limited to `p_limit`. `truncated := p_limit > 0 AND (groups > p_limit)`. `source_host` is never exposed.
  - `overflow`: the `(other)` rows grouped by `decision`, summed across buckets and sources.
  - `rows` and `overflow` are `COALESCE(jsonb_agg(...), '[]'::jsonb)` so an empty window yields arrays, not NULL.
  - `p_decision` filters `rows` and `overflow`; `summary` is always over the unfiltered window.
- Grants: `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE … TO authenticated;`. No table grant, no policy. Own migration file (lint-regex learning). The verify sentinel also records `SELECT rolconfig FROM pg_roles WHERE rolname = 'authenticated'` (the effective timeout bound).
- `.down.sql`: `DROP FUNCTION IF EXISTS get_egress_audit_summary(uuid, integer, text)`.
- Sizing bound (measured in Phase 1, not asserted): worst case 500 rows per bucket × ~2,880 buckets in 30 days ≈ 1.4M rows. Phase 1 runs `EXPLAIN ANALYZE` on that seed; the result goes in the PR description. If the `p_limit = 0` probe exceeds about 100 ms, the hint switches to a descending-bucket PK probe (a hint-only change).

### D2. Loader `server/egress-audit-read.ts` (no route)

- Inputs: the cookie Supabase client, the user id, a decision enum (`all | allowed | blocked | other`, mapped `blocked → denied`). **No workspace id input.** Never throws for an expected outcome; it catches, calls `reportSilentFallback` (feature `egress-audit-read`, reason code only, no host or workspace data), and returns a tagged union:
  - `{kind: "ready", data, collection: true | false | "unknown"}`
  - `{kind: "forbidden"}` — RPC raised `42501` (removed member or stale pointer). Expected; not mirrored.
  - `{kind: "unbound"}` — `readWorkspaceIdFromDb` returned null.
  - `{kind: "unavailable"}` — any throw, RPC error or timeout (mirrored, error level).
- Workspace id comes only from `readWorkspaceIdFromDb(userId, supabase)` (fail-loud); on null or throw the RPC is **not** called.
- `collection`: reads `workspaces.organization_id` with the cookie client and calls `isEgressAuditCollectionOn(orgId)` (D5). An org-lookup failure or a throw yields `"unknown"`. `webAccess` comes from `get_workspace_web_egress` (null for a non-member is handled).
- The RPC call carries an `AbortSignal.timeout` bound (its own constant, about 2.5 s for the hint, longer for the page; not the identity-select constant).

### D3. Destination page and view

- Route `app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx`, `export const dynamic = "force-dynamic"`; `searchParams` is awaited (Next 16: it is a Promise); an unknown `decision` falls back to `all` (no 400). Back link and filter chips use `NavLink`; the settings shell and its streamed `loading.tsx` skeleton are unchanged. The filter lives in the URL.
- `components/settings/egress-audit-view.tsx` is presentational (props = the loader union). A small client island provides "Try again" / "Refresh" via `router.refresh()` inside `usePendingAction`. Chips are a `nav` of `NavLink`s with `aria-current="page"` and a filled selected style (no glyph — the outcome column already uses a check icon for Allowed).
- Render by kind:
  - `forbidden` → "You no longer have access to this workspace." with the workspace-switcher link; no rows.
  - `unbound` → "We couldn't determine your workspace." with the switcher link.
  - `unavailable` → "Couldn't load the egress audit log. This is a loading error, not an empty log." with Try again (`role="alert"`).
  - `ready` precedence: (1) rows or overflow present → populated (web-off notice when `!webAccess`); (2) no rows, a decision filter is active and `summary.request_count_min > 0` → filtered-empty ("No <Allowed|Blocked|Other> requests in the last 30 days" + "Show all"; chips stay visible); (3) no rows and `collection === false` → "Recording isn't on for this workspace"; (4) no rows and `collection === "unknown"` → the `unavailable` rendering (never "isn't on" on an unknown); (5) no rows and `collection === true` → "No requests recorded yet" + Refresh, or, when `!webAccess`, "Nothing recorded in the last 30 days. Web access is off, so nothing new is recorded."
  - The best-effort/visibility banner shows whenever rows are shown or `collection` is true; it is hidden only on the "Recording isn't on" empty (nothing recorded), so a member looking at rows always sees the disclosure.
- Copy: forbidden words (complete, every connection, tamper-proof, sessions) never appear; all counts read "at least N" (legal wording; the column header says "Requests (minimum)"); no calendar date appears in any retention sentence ("deleted about 30 days after they were recorded"). Row labels `denied → Blocked`, `other → Other`; outcome = icon + text + colour. Overflow row "Other hosts, not listed individually" + tooltip "Counts are minimums and may be lower than actual activity." Truncation: "Showing the 200 most recent entries." (and "…Blocked entries" when filtered); no duplicate footer.
- Accessibility: result count in an `aria-live="polite"` region; icons `aria-hidden`; error `role="alert"`; overflow tooltip is a focusable button with `aria-describedby` and a tap alternative; contrast of red Blocked and grey Other/overflow checked on `$bg`/`$surface`; times use `<time datetime title=<absolute>>`.
- Long hosts: `overflow-wrap: anywhere`, full host in `title`, plain text (never an auto-link); ingest allows `[a-z0-9._:\[\]-]` up to 253 chars, so IPv6 literals and punycode appear as stored.

### D4. Card (Scope Grants page + `WebEgressToggle`)

- The page keeps its existing owner/`resolveWebEgress` flow (pre-existing, out of scope) and adds, started concurrently right after the workspace id resolves via `readWorkspaceIdFromDb` and awaited last: the RPC call with `p_limit = 0` (bounded by `AbortSignal.timeout` of about 2.5 s) and the collection check. On null, throw, timeout or any error: the hint and recording notice are hidden, the link still renders (the destination handles those cases), and the failure is mirrored with `mirrorWarnWithDebounce` (reasons `hint_timeout`, `hint_rpc_error`). A `42501` is an expected denial and is not mirrored.
- Passes `lastRequestAt: string | null` and `recordingNoticeEnabled: boolean` to the toggle.
- Replaces the two stale comments with a `NavLink` "View egress audit log" to the destination in **both** toggle states, for owners and non-owners.
- "Last request: X ago" is rendered client-side from the ISO timestamp (no server/client time mismatch); no live refresh in v1.
- Enable dialog: the sentence "Every outbound request is logged with workspace attribution." is removed. When `recordingNoticeEnabled`, the dialog shows the ruled notice (wireframe `07-02`); otherwise no recording sentence. CLO sign-off on that text is a merge gate.

### D5. Shared collection check

`server/egress-audit-collection.ts` exports `isEgressAuditCollectionOn(orgId): Promise<boolean>`, evaluating `getRuntimeFlag("egress-audit-collection", { userId: null, role: "prd", orgId, email: null, subscriptionStatus: null })`. `egress-audit-ingest.ts` swaps its inline call for the helper (behaviour identical), so ingest, loader and page cannot drift. The ingest's flag comment (`lib/feature-flags/server.ts`) is amended: a second read site now exists.

## Files to Create

- `apps/web-platform/supabase/migrations/NNN_egress_audit_summary_rpc.sql` and `.down.sql`
- `apps/web-platform/supabase/verify/NNN_egress_audit_summary_rpc.sql`
- `apps/web-platform/test/supabase-migrations/NNN-egress-audit-summary-rpc.test.ts` (text lint: definer, search_path, 42501, grants, no table grant or policy; no timeout assertion)
- `apps/web-platform/server/egress-audit-read.ts`, `server/egress-audit-collection.ts`
- `apps/web-platform/lib/egress-audit/summary.ts` (types, decision/label mapping, "at least" formatting)
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx`
- `apps/web-platform/components/settings/egress-audit-view.tsx` and a small client island for retry/refresh
- `apps/web-platform/test/egress-audit-read-loader.test.ts`, `test/egress-audit-view.test.tsx`, `test/web-egress-toggle.test.tsx`

## Files to Edit

- `apps/web-platform/test/rls-fuzz/egress-audit-rollup.integration.test.ts` (read-path cases; keep the file so the CI step stays valid) and `test/rls-fuzz/harness-fixture.ts` (pending-invitee and removed-member seeds)
- `apps/web-platform/test/rls-fuzz/rpc-cases.ts` (`ATTACK_SQL` entry) and `test/rls-fuzz/targets.ts` (stale comment about a PR2 member policy)
- `.github/workflows/rls-authz-fuzz.yml` — **mandatory**: raise the egress step floor from `numPassedTests >= 15` to `>= (21 + N_new)`, `N_new` counted at work time
- `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` and `components/settings/web-egress-toggle.tsx` (link, hint, flag prop, dialog copy; remove the stale comments)
- `apps/web-platform/server/egress-audit-ingest.ts` (use the shared helper) and `lib/feature-flags/server.ts` (flag comment)
- `apps/web-platform/server/dsar-export-allowlist.ts` (rationale for the rollup table says "dark in PR1")
- `infra/sentry/issue-alerts.tf` and `alert-reference.json` (add an alert for feature `egress-audit-read`; confirm the existing rule shape first)
- Legal and compliance (Phase 4.3), with exact paths:
  - `docs/legal/privacy-policy.md` (4.7, 7), `docs/legal/acceptable-use-policy.md` (5.8), `docs/legal/data-protection-disclosure.md` (2.3(ag) and the "ahead of" wording at lines ~21 and ~230), `docs/legal/gdpr-policy.md` (3.16, 8.4)
  - mirrors `plugins/soleur/docs/pages/legal/{privacy-policy,acceptable-use-policy,data-protection-disclosure,gdpr-policy}.md`; `apps/web-platform/lib/legal/legal-doc-shas.ts` (re-pin) and the SHA gate inputs; Eleventy date mirrors
  - `knowledge-base/legal/article-30-register.md` (PA-2, PA-8, PA-37 "declared ahead of collection"); the DPIA addendum `knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md` (new t6 re-screen section; its "no member read" sentences near lines 47, 125, 174, 243, 271); `knowledge-base/legal/audits/2026-10-counsel-review-9545.md` (~line 71); `compliance-posture.md` (t6 row); `knowledge-base/engineering/operations/runbooks/egress-audit-dsar.md` (line ~11 "dark until PR2", plus one line that the view does not satisfy an Art. 15 request)
  - the sweep that finds the rest: `git grep -n -i -E 'no (workspace )?member can read|nothing reads|member SELECT policy|until PR2|lands in PR2' -- knowledge-base docs/legal apps/web-platform/server` — every hit is read and decided
- `knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md` (amendment) and the archived PR1 plan `knowledge-base/project/plans/archive/20261015-142700-2026-10-15-feat-workspace-egress-audit-log-plan.md` (amendment note per TR5)
- C4: `knowledge-base/engineering/architecture/diagrams/model.c4` (edit the text next to the egress-audit ingest edge that says the table is dark and nothing reads it; add `webapp -> supabase` read and member→webapp edges), `views.c4` if an element must render, and the regenerated `model.likec4.json` (byte-compared by `plugins/soleur/test/c4-model-freshness.test.sh`)
- `knowledge-base/product/design/settings/egress-audit-log.pen` and screenshots (Phase 5)
- `knowledge-base/product/roadmap.md` / issue milestone: #9545 sits on "Post-MVP / Later" while Phase 4 is active; place it in a phase or record why it ships out of phase (`wg-every-feature-listed-in-a-roadmap-phase`)

## Implementation Phases

Tests come first in every phase (`cq-write-failing-tests-before`). Phases 4.3 (legal) and 5 (wireframe copy) have no dependency on Phases 1-3 and start on day one in parallel; a **copy freeze** at the end of Phase 5 precedes the legal text, which quotes the view and dialog copy. The `LEGAL_DOC_SHAS` re-pin and date-mirror sync run once, after the last rebase.

### Phase 0 — Preflight

- Choose the migration number: `git fetch origin` then, across **all** remote refs, `for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree --name-only $r apps/web-platform/supabase/migrations/; done | grep -oE '/[0-9]{3}_' | sort -u | tail -3`; `NNN` = highest + 1. Re-run after every rebase and immediately before merge.
- The Postgres timeout reproduction is not repeated (the CTO proved it); record `SELECT rolconfig FROM pg_roles WHERE rolname='authenticated'` in the verify script.
- Tracking issues are filed: #11237 (`action-required`: retention approval, team-workspace role decision with an Art. 28 instrument and standalone LIA, Art. 21 sufficiency, owner notice live at least 7 days, flag flip; the flip carries an `Automation:` line, the flag-set-role skill with a typed operator confirmation as the final write) and #11238 (deferred time-range selector and 24h count). The PR body references them as `Ref #11237` and `Ref #11238`.
- Milestone placement for #9545 per the roadmap (see Files to Edit).

### Phase 1 — Database (red → green)

1. Write the failing live-DB cases in `egress-audit-rollup.integration.test.ts`, the shape test and the `ATTACK_SQL` entry.
2. Migration + down + verify sentinel per D1.
3. Run `bun run test:rls-fuzz` against the local Supabase stack and `cd apps/web-platform && ./node_modules/.bin/vitest run test/migration-rpc-grants.test.ts`.
4. Run `EXPLAIN ANALYZE` on the worst-case seed (D1) and keep the result for the PR description.

### Phase 2 — Loader and shared helper

1. Failing loader tests (mocked client): null workspace → `unbound` and the RPC not called; reader throw → `unavailable` and the RPC not called; `42501` → `forbidden` (not mirrored); other error and abort → `unavailable` (mirrored once, reason code only); a forged `?workspace`, `?workspaceId` or `?orgId` is ignored; `collection` tri-state including `"unknown"`; `webAccess` null handled.
2. Implement `server/egress-audit-collection.ts` (swap the ingest call) and `server/egress-audit-read.ts` per D2/D5.

### Phase 3 — UI

1. Failing component tests for the view (every kind and precedence branch in D3, error ≠ empty, filtered-empty, truncated wording, overflow label, "at least" everywhere, Blocked/Other labels, banner rule, no date and no forbidden word in rendered text, chips as `NavLink` with `aria-current`) and for `WebEgressToggle` (link in both states, hint shown/hidden, dialog copy by prop).
2. Implement the page, view, island and card/dialog changes per D3/D4. Follow `components/ui/README.md` (Button primitive, `NavLink`, `usePendingAction`).
3. Run the unit and component projects and `tsc`.

### Phase 4 — Records and documents

1. ADR-288 amendment; fix `targets.ts`, the flag comment, `dsar-export-allowlist.ts`, the runbook line and the archived-plan note.
2. C4: read `model.c4`, `views.c4`, `spec.c4` in full; edit the falsified text and add the read edges; regenerate `model.likec4.json`; run `c4-code-syntax`, `c4-render`, `c4-model-freshness` and `c4-count-parity` tests.
3. Legal/compliance: CLO-led edits and the grep sweep (Files to Edit); DPIA t6 section (verify the CNIL Art. 35(4) list wording — merge gate); SHA re-pin and mirror gates; open the CLO review at the start, not the end (it is the long pole). If CLO sign-off stalls, the code is inert while the flag is off and the legal commits may stack as a second PR.
4. Sentry: add the `egress-audit-read` alert and its reference entry.

### Phase 5 — Wireframe deltas (parallel with Phases 1-2; copy freeze at the end)

Apply to `egress-audit-log.pen` (desktop and mobile): (a) subtitle, summary line (no "sites listed"), truncation wording with the footer duplicate removed; (b) populated-web-off notice and e2/e3 copy, no dates, e2 gains Refresh; (c) hide the banner on the "Recording isn't on" empty only; (d) selected chip is filled with no glyph; (e) two new frames per platform: 403 ("You no longer have access to this workspace") and filtered-empty with "Show all" (`07-22`..`07-25`). No workspace-name line, no 429 frame. Re-export the changed frames, verify `agent-web-access.pen` is still 88861 bytes and `egress-audit-log.pen` has no `fileToken` before commit (gitleaks flags the adapter's UUID). Open the `.pen` only while it is tracked (the hook refuses an untracked path).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "PR2: egress audit log read path" | D1, D2, Phases 1-2 | mapped |
| 2 | "a 'View egress audit log' link on the Scope Grants 'Agent web access' card, wired to a destination view" | D3, D4, Phase 3 | mapped |
| 3 | "'Last request: X ago'" on the card | D1 (`p_limit = 0`), D4 | mapped |
| 4 | "the DPIA t6 re-screen, and the public-document changes the viewer makes true" | Phase 4.3 | mapped |
| 5 | "typed overflow field instead of an '(other)' row, decision 'other' shown as a third visible state" | D1, D3 | mapped |
| 6 | "enable-dialog copy replaced and gated on egress-audit-collection (plan must confirm how the flag reaches the component)" | D4, D5 | mapped |
| 7 | "migration 164" | D1, Phase 0 | mapped — number changed: 164 is claimed by open PRs, chosen at the last rebase |
| 8 | "host list and decision filter only, fixed 30-day window" (brainstorm, operator scope) | D1, D3 | mapped — the filter is kept (operator scope); it is implemented as URL links, not a client fetch |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| RPC `p_decision` parameter | "decision filter" (brainstorm scope) | asked |
| `summary` block and `p_limit = 0` hint read | "'Last request: X ago'" | asked |
| `collection` tri-state and web-off ladder | "three empty states" (spec FR3) | asked |
| Shared `isEgressAuditCollectionOn` helper | "plan must confirm how the flag reaches the component" | asked |
| ADR-288 amendment, source-comment and C4 text fixes | "Amend the archived PR1 plan and ADR-288" (spec TR5) | asked |
| Filtered-empty line, forbidden/unbound/unavailable states, accessibility list, chip selected style | — | inferred — justification: spec-flow blockers 3-4 and important 6-8, 15-18; without them a removed member, a failed workspace lookup or an empty filter result renders a wrong or misleading state |
| Wireframe copy deltas and 4 new frames | — | inferred — justification: reconciliation found strings with no data source or self-contradiction; shipping them would state something untrue |
| Sentry alert for `egress-audit-read` | — | inferred — justification: `hr-observability-as-plan-quality-gate`; no rule exists on `main` |
| Enablement tracker issue | — | inferred — justification: `wg-block-pr-ready-on-undeferred-operator-steps`; `Closes #9545` would otherwise drop the only open tracker |

### Split Assessment

One PR. The slices share one contract (the RPC jsonb) and one legal text; the document phase is a merge gate of this PR per the spec. The enablement steps are explicitly not in this PR.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `get_egress_audit_summary` exists with `SECURITY DEFINER`, `SET search_path = public, pg_temp`, a membership check raising `42501`, grants only to `authenticated`; no table grant and no SELECT policy added; no `statement_timeout` clause; `NNN` is the highest number on any `origin/*` ref plus one (shape test asserts the rest).
- [ ] AC2 — Live DB (`bun run test:rls-fuzz`, required `rls-authz-fuzz` CI): current member of W reads W's rows and totals; a member of another workspace, a pending invitee and a removed member each get exactly SQLSTATE `42501` (SAVEPOINT, schema-valid args); `anon` and `service_role` cannot execute; direct `SELECT` as `authenticated` is a permission error; a service-role positive control proves rows exist; co-member C passes while non-member D is denied.
- [ ] AC3 — Aggregation: sums across buckets and `source_host`; `truncated` true only when `p_limit > 0` and groups exceed it; `p_limit = 0` returns only `last_request_at` (counts null, arrays empty); overflow grouped by decision, excluded from `rows` and the limit; `p_decision` filters rows and overflow; arrays are `[]` (not NULL) on an empty window; window edges (just inside and just outside 30 days, and a purge-lagged row older than 30 days is excluded); a workspace with web access off still returns its history.
- [ ] AC3a — Measured bound: `EXPLAIN ANALYZE` on the worst-case seed is recorded in the PR description; `authenticated`'s `rolconfig` timeout is recorded by the verify script; if the `p_limit = 0` probe exceeds about 100 ms the hint uses the PK probe.
- [ ] AC4 — `ATTACK_SQL` entry added; `migration-rpc-grants` and `lint-migration-immutability` pass; the CI floor in `rls-authz-fuzz.yml` is raised to `>= (21 + N_new)`.
- [ ] AC5 — Loader: null workspace → `unbound`, reader throw → `unavailable`, neither calls the RPC; `42501` → `forbidden` and is not mirrored; other errors and aborts → `unavailable` with exactly one Sentry event (feature `egress-audit-read`, reason code only, no host or workspace data); forged `?workspace`/`?workspaceId`/`?orgId` ignored; the page sets `force-dynamic`; no `GET` route exists for this feature.
- [ ] AC6 — View: error is never rendered as empty; the ladder in D3 holds (including `collection === "unknown"` → error rendering); forbidden/unbound states clear all rows; filter chips are `NavLink`s with `aria-current`; every count reads "at least N"; overflow label and tooltip exact; Allowed/Blocked/Other each have icon + text + colour; the banner is hidden only on the "Recording isn't on" empty; no forbidden word and no calendar date in any rendered retention sentence (assertion over rendered text).
- [ ] AC6a — Accessibility: result count in an `aria-live="polite"` region; icons `aria-hidden`; error `role="alert"`; overflow tooltip reachable by keyboard and tap; long and IPv6 hosts wrap without horizontal scroll at 390px; contrast of Blocked/Other/overflow text verified.
- [ ] AC7 — Card: link present in both toggle states for owner and non-owner; hint shown only when `last_request_at` exists, hidden (link kept) on null, throw, timeout or error; a `42501` on the hint is not mirrored; the dialog no longer contains "Every outbound request is logged" and shows the recording notice only when `recordingNoticeEnabled`.
- [ ] AC8 — `tsc`, unit and component projects green (run with vitest, not `bun test`); `NATIVE_BUTTON_BASELINE` not raised.
- [ ] AC9 — ADR-288 amended (no member SELECT policy, read path deliberately not flag-gated, `decision` CHECK exists, overflow is a separate typed field, no route); `targets.ts`, flag comment, `dsar-export-allowlist.ts`, runbook line, C4 text corrected; archived-plan note added; C4 read edges added with `model.likec4.json` regenerated; `c4-model-freshness`, `c4-render`, `c4-code-syntax` and `c4-count-parity` green.
- [ ] AC10 — Legal/compliance merge gates: the t6 re-screen is a new DPIA addendum section with the CNIL Art. 35(4) wording verified; every document in Files to Edit is updated with mirrors, `LEGAL_DOC_SHAS` re-pin and date-mirror sync; the grep sweep's hits are all decided; CLO sign-off recorded for the view copy and the dialog notice.
- [ ] AC11 — Wireframe deltas applied and re-exported; `agent-web-access.pen` still 88861 bytes; `egress-audit-log.pen` has no `fileToken`.
- [ ] AC12 — Migration `NNN` re-verified against all `origin/*` refs (Phase 0 command) immediately before merge and after every rebase.
- [ ] AC13 — PR body: `Closes #9545` and `Ref #11237` for the enablement tracker and `Ref #11238` for the deferred selector; states the flag flip is not part of this PR (CPO withhold condition); no per-member, session or `source_host` field reaches the page (CPO withhold condition); the live-DB negative cases run in the required CI (CPO withhold condition).
- [ ] AC14 — Sentry alert for `egress-audit-read` added with its reference entry; #9545 milestone placed per the roadmap.

### Post-merge (operator)

- Enablement remains gated per `egress-audit-enable.md` and tracked in #11237: retention approval, team-workspace role decision with an Art. 28 instrument and standalone LIA, Art. 21 sufficiency, owner notice live at least 7 days, operator authorization to flip `egress-audit-collection`. None is executed by this PR. Automation: the flag flip uses the `flag-set-role` skill (typed confirmation is the final write).

## Domain Review

**Domains relevant:** Product, Engineering, Legal

### Engineering (CTO)

**Status:** reviewed (brainstorm rulings; plan-review rulings 2026-10-26 on route-vs-page, timeout, workspace reader, hint cost, flag helper)
**Assessment:** RPC-only read path; typed overflow; `other` as a third visible state; server-rendered page, no route; no `statement_timeout` claim; fail-loud workspace reader; bounded card hint; one shared collection helper. Repo research and plan review corrected the resolver, flag-identity, overflow-granularity, migration-number and timeout assumptions — all absorbed above.

### Legal (CLO)

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** Members may read; t6 re-screen concludes "no full DPIA, conditional"; the CNIL Art. 35(4) wording, the document changes with mirrors and SHA re-pin, and the view and dialog copy are merge gates (AC10). CLO sign-off on the dialog notice and view copy is pending.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:design:ux-design-lead (wireframes committed in brainstorm and approved by the operator 2026-10-26; plan-review design lens), soleur:product:spec-flow-analyzer, soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** yes

#### Findings

CPO: small read-only workspace-level view that does not count or watch people; no creep in the data model; sign-off granted subject to four withhold conditions (AC2/AC4, AC10, AC13); roadmap placement to fix (AC14); new frames cut to 403 and filtered-empty. Spec-flow (21 gaps, 4 blockers): no data source for "recording since" and a wrong "kept until <date>" → copy deltas and no dates; silent resolver fallback → fail-loud reader (replaces the planned workspace-name header); missing 403/timeout states and empty-state precedence → D3; accessibility and long hosts → AC6a. UX lens: filled chip instead of a glyph (adopted), banner shown unless nothing is recorded (adopted), mobile banner collapse and "N+" count style deferred (the "at least" form is the legal wording; the title "Egress audit log" is the operator's own issue wording). Non-owner flow: the card and link already render read-only for members; the erasure link targets the privacy policy's data-subject-rights section (anchor set during the CLO edits). The enable dialog's inline focus handling is pre-existing and out of scope.

## Open Code-Review Overlap

None. All 98 open `code-review` issues were searched (body contains the path) against every path in `## Files to Edit` as listed at draft time; none names any of them. Re-run at work time for the paths added since (`dsar-export-allowlist.ts`, `egress-audit-ingest.ts`, `infra/sentry/*`, the legal mirrors).

## Observability

```yaml
liveness_signal:
  what: request-scoped read path; no cron or daemon is introduced
  cadence: per page render
  alert_target: Sentry (feature egress-audit-read)
  configured_in: apps/web-platform/server/egress-audit-read.ts
error_reporting:
  destination: Sentry via reportSilentFallback (feature "egress-audit-read", reason codes only); debounced warn mirror for the card hint
  fail_loud: the page renders the unavailable state with role="alert", never an empty log
failure_modes:
  - mode: RPC error or abort on the destination page
    detection: reportSilentFallback event, reason rpc_error / rpc_timeout
    alert_route: Sentry issue alert on feature egress-audit-read (added in this PR)
  - mode: workspace pointer absent or its read throws
    detection: unbound state rendered; read throw mirrored, reason workspace_read_error
    alert_route: Sentry issue alert on feature egress-audit-read
  - mode: removed member or stale pointer (42501)
    detection: forbidden state rendered; not mirrored (expected denial)
    alert_route: none (expected)
  - mode: card hint read fails or times out
    detection: debounced warn mirror, reason hint_timeout / hint_rpc_error
    alert_route: Sentry issue alert on feature egress-audit-read
logs:
  where: Sentry events
  retention: Sentry project default
discoverability_test:
  command: bash -c "grep -q 'const FEATURE = \"egress-audit-read\"' apps/web-platform/server/egress-audit-read.ts && echo ok"
  expected_output: "ok"
```

Notes: the feature tag is pinned as one `const FEATURE = "egress-audit-read"` line so the probe is exact by construction. The effective query bound is the `authenticated` role's timeout plus `p_limit`, the PK-led scan and the page's abort signal — not a function-level setting.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-288 (status stays `adopting`): the member read path is a `SECURITY DEFINER` RPC, **no member SELECT policy**, **no HTTP route**, deliberately **not gated** on `egress-audit-collection` or `web_egress` (history stays readable after toggle-off); `decision` has a CHECK; overflow is a separate typed field; no function-level timeout. Update its Alternatives Considered row "Member SELECT policy in PR1" to record that the policy was replaced by the RPC, not deferred to PR2. The status flips to `accepted` only after PR2 merges and the owner notice has been live (an enablement step, not this PR).

### C4 views

The implementer reads all three `.c4` files in full and enumerates before editing: (a) external human actor — the workspace member reader (confirm it is already modeled as a workspace user actor and whether its description still holds); (b) external system — none new; (c) data store — the rollup table (modeled with PR1's write edge); (d) actor-to-surface access relationship — member → webapp read edge and webapp → supabase read edge, both new. Edit the text beside the existing ingest edge that says the table is dark and nothing reads it. Add the `view … include` line if a new element is introduced; regenerate `model.likec4.json`; run the C4 tests.

### Sequencing

The ADR amendment describes the target state now; the `adopting → accepted` flip is the documented post-enablement transition already in ADR-288, not a postponed issue.

## Encryption Posture

Not applicable: the migration adds one function over an existing table and introduces no persistent store and no new cross-component connection (the app-to-Supabase path and the rollup table are PR1's, with their posture already recorded). Stated here so `deepen-plan` can confirm the skip; the `.sql` detection regex fires on file path alone.

## Guard Contract

### Guard 1 — workspace-member read authorization of the egress summary

**Property.** Only a current member of workspace W can read W's egress audit rows, through exactly one surface (the RPC); no other role or tenant can execute it, and `authenticated` has no direct table access. (`service_role` keeps its pre-existing table access from PR1; the guarantee here is about the read surface this PR adds.)

**Assembly.** Every path to the rollup rows this PR adds or touches: (1) the RPC body's `is_workspace_member` check; (2) the function's EXECUTE grants for PUBLIC, anon, authenticated, service_role (Supabase default privileges re-grant, so all four are named); (3) direct table access by `authenticated` (no grant, RLS on, zero policies); (4) the loader `server/egress-audit-read.ts`, which must take the workspace id only from the fail-loud reader and never from `searchParams`; (5) the Scope Grants page's `p_limit = 0` card read, a second call site of the same RPC; (6) any later migration that adds a policy or grant to the table (the shape test pins the grant and policy set). The chokepoint is the RPC; sites 4 and 5 are its only callers and both are asserted.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Caught by |
|---|---|---|
| 1 | Remove the `is_workspace_member` check from the RPC | live DB: other-tenant, pending invitee, removed member |
| 2 | Add `GRANT EXECUTE … TO anon` (or leave the default `PUBLIC` grant) | live DB anon call + shape test grant assertions |
| 3 | Add `GRANT EXECUTE … TO service_role` | shape test + live DB service_role call |
| 4 | Add a member `SELECT` policy to the table | shape test (policy set pinned) + live DB direct-SELECT case |
| 5 | Loader or page reads the workspace id from `searchParams` | loader test with a forged `?workspaceId` that differs from the session pointer |
| 6 | Loader swaps the fail-loud reader for `resolveCurrentWorkspaceId` | null and throw tests assert the RPC is not called |
| 7 | Card or loader swaps the cookie client for a service-role client | loader and page tests assert the cookie client is the one passed to the RPC |
| 8 | Add a second member after a compliant first (co-member C of W) and a non-member D | live DB: C passes, D denied (a check that stops at the first member is the same defect) |
| 9 | Guard's own dispatch: drop the new live-DB cases | the raised CI floor `>= (21 + N_new)` fails, and the `ATTACK_SQL` registry test fails if the function is unregistered |
| 10 | A non-member call returns rows or spends aggregate time before denial (membership check moved after the aggregate) | a live case: a non-member call returns exactly `42501`, no payload, and completes under the cheap-denial bound (a case that observes the window, not a text-order assertion) |

**Harness rows.** (H1) Make the harness seed return no co-member: the suite must go RED on its own fixture self-check (the `Fixture self-check` block in `seedTwoTenant`, `harness-fixture.ts`). (H2) Replace the live-DB cases with always-true assertions: the raised CI floor plus the service-role positive control (rows exist, a member reads them) must go RED. Must-PASS non-canonical inputs: a member who joined after the rows were written reads them (pre-join history is visible by design); a member of a workspace with web access off reads its history.

**Anchor.** The shape test pins the table's grant and policy set and the function's grant set against values in the migration set, so a PR that weakens the RPC must also edit the test; the independent anchors are the `ATTACK_SQL` registry and the live-DB suite run by the required `rls-authz-fuzz` workflow with its raised floor, which a single diff cannot satisfy by editing only the migration.

## Test Scenarios

1. Member reads: seeded rows → expected hosts, decisions, sums, "at least" copy.
2. Cross-tenant: tenant B calls with tenant A's id → `42501`, zero rows; the service-role control sees A's rows.
3. Pending invitee and removed member → `42501`.
4. Stale pointer pinned to a non-member → loader `forbidden`; the page shows "You no longer have access" and no rows.
5. Null pointer → `unbound`; pointer read throws → `unavailable`; the RPC is not called in either case.
6. Web access off with history → rows still returned; the notice says records are deleted about 30 days after they were recorded (no date).
7. Flag off, no rows → "Recording isn't on"; flag unknown, no rows → the error rendering; flag on + web on, no rows → "No requests recorded yet" + Refresh; flag on + web off, no rows → "Nothing recorded in the last 30 days. Web access is off…".
8. 201+ groups → `truncated`, "Showing the 200 most recent entries"; overflow rows present and excluded from the 200.
9. Decision filter with a match, and with zero matches while the window has requests → filtered-empty with "Show all"; an unknown `?decision=` value behaves as `all`.
10. RPC error and abort → error state with Try again; refresh refetches.
11. Card: both toggle states show the link; hint present with data, absent without, absent on null/timeout/error; dialog copy per prop.
12. Rendered-text assertion: none of "complete", "every connection", "tamper-proof", "session" appears in view or dialog copy; no calendar date in any retention sentence.

## Risks and Sharp Edges

- **Migration number collisions.** 164 through at least 173 are claimed on open branches; pick `NNN` at the last rebase and re-check immediately before merge.
- **Wrong-reason denial tests.** Use schema-valid UUIDs and assert SQLSTATE `42501` exactly.
- **Default privileges.** `REVOKE … FROM PUBLIC` alone is not enough on Supabase; the live anon/service_role calls are the proof.
- **No timeout guarantee in the function.** The bound is structural plus the role timeout; the measured `EXPLAIN` figure and the recorded `rolconfig` are the evidence, not a header clause.
- **Legal gates are the long pole.** Edits to `docs/legal` re-pin SHAs and date mirrors; run the gates before pushing; CLO sign-off can block merge independent of code.
- **Overflow counts are very loose lower bounds** (GREATEST merge). Never present a total; copy and tooltip say "at least".
- **Verify sentinel for 162 pins the table comment text**, so the stale "PR2 member policy" comment on the table stays; corrections live in ADR-288 and the new migration's header.
- **Flag lag.** `getRuntimeFlag` caches 30 s per process; the dialog notice can lag the ingest by that window (single-node today).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
