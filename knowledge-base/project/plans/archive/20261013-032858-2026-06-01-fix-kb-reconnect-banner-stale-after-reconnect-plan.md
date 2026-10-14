---
title: "fix(kb): reconnect banner persists after successful workspace-shared reconnect"
issue: TBD
parent: 4712
branch: feat-one-shot-kb-sync-banner-stale-after-reconnect
date: 2026-06-01
type: fix
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

# 🐛 fix(kb): "can't sync — reconnect" banner persists after a successful reconnect

🐛 **Type:** bug · **Surface:** KB layout reconnect banner (#4712) + settings ProjectSetupCard · **Related:** #4712 (banner feature), #4726 (went-quiet detection), #4736/#4728 (workspace_id discriminator), ADR-044 (workspace-scoped install credential)

## Enhancement Summary

**Deepened on:** 2026-06-01 · **Sections enhanced:** Research Reconciliation, Risks (precedent-diff gate 4.4), Research Insights
**Gates run inline (no subagent tooling in this environment):** 4.6 User-Brand Impact (PASS — section present, threshold `aggregate pattern`), 4.7 Observability (PASS — 5 fields, no ssh in `discoverability_test.command`), 4.8 PAT-shaped variable scan (PASS — none), 4.5 network-outage (N/A — no real trigger), 4.4 precedent-diff gate, live PR/issue-state checks for every cited number.

### Key Improvements
1. **#4712 confirmed CLOSED — and its title is the smoking gun.** Live check: #4712 = *"KB sync (#4706 follow-ups): UI reconnect affordance for **NULL-install workspaces** + stale-last-sync heuristic"* (CLOSED). The banner was purpose-built for NULL-install workspaces; this bug is its predicate over-firing on the *workspace-shared-but-user-column-NULL* sub-case. Confirms the fix is a predicate refinement of an existing, intended feature — not a new build.
2. **Precedent-diff gate satisfied.** The capability expression (`users.github_installation_id || resolveInstallationId(userId)`) is NOT novel — it is the established canonical form at `app/api/kb/sync/route.ts:101-106`. The fix adopts the precedent verbatim rather than inventing a new capability check. Side-by-side in Risks below.
3. **Placement de-risked at plan time.** Grep confirmed the only `.tsx` importer of `lib/repo-status` is the server component `settings/page.tsx` — no client importer exists, so the async resolver lands in `lib/repo-status.ts` with no client-bundle risk.

### New Considerations Discovered
- **Cite #4706 as a PR, not an issue.** Live check: #4706 is a MERGED **PR** (*"reconcile ignored repos with connected workspaces + detect ready-but-unreachable workspaces"*), and #4728 is an OPEN **issue** (not yet a merged feature). Citations corrected.
- **`resolveInstallationId` returns `Promise<number | null>`** (verified `resolve-installation-id.ts:30-33`), so `wsInstall == null` is the correct null-check (loose `==`, matching the existing `repoNeedsReconnect` convention for null-or-undefined). No symbol collision: `resolveNeedsReconnect` does not exist anywhere in `apps/web-platform`.

## Overview

The orange reconnect banner (`This project can't sync — reconnect to restore Knowledge Base updates…`) stays displayed even after a reconnect succeeds and syncing visibly resumes (operator screenshot: `INDEX.md`, `kb-categories.txt`, `kb-tags.txt` all synced "1m ago").

**Root cause — signal divergence between "can sync" and "the banner's predicate".** The banner is driven by `repoNeedsReconnect(repo_status, github_installation_id)` (`apps/web-platform/lib/repo-status.ts:12`), which returns `true` when `repo_status === "ready" && users.github_installation_id == null`. But the **actual sync-capability** of the workspace does **not** depend on `users.github_installation_id` — it depends on the *workspace-scoped* installation credential resolved via the `resolve_workspace_installation_id` SECURITY DEFINER RPC (ADR-044, migration 079), surfaced by `resolveInstallationId(userId)` (`apps/web-platform/server/resolve-installation-id.ts:30`).

For an **org-owned or workspace-shared install** (the ADR-044 membership case), `users.github_installation_id` is **NULL by design** and is deliberately never written:

- `POST /api/repo/detect-installation` returns `{ installed: true }` for a *membership-reachable* install (`route.ts:186-199`) **without** writing `users.github_installation_id` — and on the unique-constraint path (`route.ts:144-166`) the UPDATE silently no-ops (logged `info`, "shared via workspace membership"), again leaving the column NULL.
- Sync resumes anyway: the push-webhook reconcile (`workspace-reconcile-on-push.ts:165`) selects workspaces by the **org install id** from the webhook payload, and the manual `/api/kb/sync` route (`route.ts:101-106`) falls back to `resolveInstallationId(userId)` when `users.github_installation_id` is falsy.

So files update "1m ago" (sync works via the workspace credential) while `repoNeedsReconnect("ready", null)` stays `true` forever (banner reads the *user* column). The client side is **not** the bug: `useReconnect` → `onReconnected` → `refreshTree` (`use-kb-layout-state.tsx:100`) correctly re-fetches `/api/kb/tree` and re-derives `needsReconnect` from the server response. The server simply re-returns `true` because its predicate reads the wrong column.

**The fix:** make the banner predicate read the **same sync-capability signal the sync path uses** — i.e., treat the workspace as connected when *either* `users.github_installation_id` is set *or* a workspace-scoped installation credential resolves. The `kb/sync` route already encodes the canonical "true capability" expression (`users.github_installation_id || resolveInstallationId(userId)`); the banner must adopt it instead of reading the user column alone.

## Research Reconciliation — Spec vs. Codebase

| Bug-report claim | Codebase reality | Plan response |
|---|---|---|
| "Banner's clear condition is not re-evaluated after reconnect" | Partially true *as a symptom*. Client `refreshTree` DOES re-evaluate (`use-kb-layout-state.tsx:100`); the server predicate re-returns `true` because it reads `users.github_installation_id`, which the reconnect never sets for workspace-shared installs. | Fix is **server-side predicate**, not client re-fetch wiring. No client change needed. |
| "Likely related to #4726 went-quiet detection" | #4726 is Sentry-only, **no UI** (PR body: "no UI"). It does not touch the banner. | Out of scope. Cite as related context only. |
| "Likely related to feat-one-shot-4728-kb-sync-workspace-id" | #4736/#4728 adds an optional `workspace_id` to `kb_sync_history` rows; **reader-inert, no banner touch**. | Orthogonal. The shared underlying theme is "the per-user column is the wrong granularity once workspaces are shared" — this plan fixes the *banner* read of that signal; #4728 fixes the *history-row* attribution. No file overlap. |
| Banner predicate lives in one place | Two derivation sites import `repoNeedsReconnect`: `app/api/kb/tree/route.ts:39` and `app/(dashboard)/dashboard/settings/page.tsx:37`. The helper's own doc forbids inline re-derivation. | Fix must keep a single shared predicate; both sites updated to feed it the capability signal. |

## User-Brand Impact

**If this lands broken, the user experiences:** a permanent, false "your Knowledge Base can't sync" alarm on a KB that is in fact syncing every push — eroding trust in every other status signal the product shows, and prompting needless repeated reconnect clicks (each a GitHub OAuth round-trip). Conversely, if over-corrected, a genuinely broken sync (the #4706 5-week silent freeze) shows *no* banner — the regression the #4712 banner exists to prevent.

**If this leaks, the user's data/workflow is exposed via:** N/A — read-only signal derivation; no new data surface, no new write, no PII. The install-id is already read on these paths.

**Brand-survival threshold:** aggregate pattern. (A single stale banner is an annoyance, not an incident; the brand cost accrues across every workspace-shared/org-install user, which is the growing majority as multi-tenant workspaces land. No single-user incident class — sync itself is unaffected either way.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Predicate reflects true capability.** A user with `repo_status='ready'`, `users.github_installation_id IS NULL`, but a resolvable workspace-scoped install (RPC returns a non-null id) yields `needsReconnect === false` from BOTH derivation sites (`/api/kb/tree` and `settings/page`). Verified by a test that stubs the capability inputs and asserts the boolean.
- [x] **AC2 — The #4706 freeze still alarms.** A user with `repo_status='ready'`, `users.github_installation_id IS NULL`, AND no resolvable workspace install (RPC returns null) yields `needsReconnect === true`. The banner MUST still appear for the genuine silent-freeze class. (verify-the-negative)
- [x] **AC3 — Personal-install path unchanged.** `repo_status='ready'` + non-null `users.github_installation_id` → `needsReconnect === false` (no extra RPC call needed; short-circuit before resolving the workspace credential to avoid a redundant DB round-trip on the common path).
- [x] **AC4 — Non-ready statuses unchanged.** `not_connected`/`error`/`cloning` → `needsReconnect === false` regardless of install id (existing `repo-status.test.ts` cases still pass verbatim).
- [x] **AC5 — Single source of truth preserved.** `grep -rn "repo_status === \"ready\"" apps/web-platform --include=*.ts --include=*.tsx | grep -v repo-status.ts` returns zero inline re-derivations (the helper doc forbids them; the fix must not introduce a second).
- [x] **AC6 — `tsc --noEmit` clean** for `apps/web-platform`.
- [x] **AC7 — Existing reconnect-banner + kb-layout + repo-status suites pass:** `./node_modules/.bin/vitest run test/components/kb/kb-reconnect-banner.test.tsx test/kb-layout.test.tsx test/lib/repo-status.test.ts` (run from `apps/web-platform/`).

## Implementation Phases

### Phase 0 — Preconditions (grep-verify before coding)

0.1 Confirm the capability fallback expression in the sync route is current: `sed -n '101,114p' apps/web-platform/app/api/kb/sync/route.ts` shows `installationId = userData.github_installation_id; if (!installationId) installationId = await resolveInstallationId(userId)`.
0.2 Confirm `resolveInstallationId(userId)` returns `number | null` and is import-safe from a route module (it is — already dynamically imported by `kb/sync`).
0.3 Confirm both predicate callers and their available columns: `kb/tree/route.ts` already SELECTs `github_installation_id` and has `user.id`; `settings/page.tsx` already SELECTs it and has `user.id`. Both can resolve the workspace credential.
0.3b **Placement resolved (grep ran at plan time):** `grep -rln "@/lib/repo-status" apps/web-platform --include=*.tsx` returns ONLY `app/(dashboard)/dashboard/settings/page.tsx`, which is a **server component** (`export default async function SettingsPage()` — no `"use client"` directive). All three importers of `lib/repo-status` (`kb/tree/route.ts`, `settings/page.tsx`, `test/lib/repo-status.test.ts`) are server-side. **Therefore the async resolver can live in `lib/repo-status.ts` directly** — no genuine client importer exists, so bundling `resolveInstallationId`'s server deps will not break a client build. The `server/repo-status.ts` fallback in Files-to-Create is NOT needed.
0.4 Confirm vitest globs so the new test lands where the runner collects it: `lib/**/*.test.ts` and `test/**/*.test.ts` (node project), `test/**/*.test.tsx` (jsdom). A pure-predicate test belongs at `test/lib/` (matches `test/**/*.test.ts`).

### Phase 1 — RED: failing test for the workspace-shared case

Extend `apps/web-platform/test/lib/repo-status.test.ts` (or a new sibling if the predicate signature changes shape) with the AC1/AC2 cases. Because the new capability check is *async* (it calls the RPC), the cleanest shape is **NOT** to make `repoNeedsReconnect` itself async (it is a pure boolean used in two server contexts) — instead introduce a thin async resolver at the route/page layer and keep `repoNeedsReconnect` pure. See Phase 2 for the chosen shape; write the RED test against that shape.

### Phase 2 — GREEN: introduce a capability-aware reconnect resolver

**Design decision (keep the pure predicate; add an async capability resolver).** `repoNeedsReconnect` stays a pure `(repoStatus, installationId) => boolean`. Add a single shared async helper — `resolveNeedsReconnect(repoStatus, userInstallationId, userId)` in `apps/web-platform/lib/repo-status.ts` (or a server-only sibling `server/repo-status.ts` if `lib/` must stay client-safe — verify `lib/repo-status.ts` has no client importers via `grep -rn "@/lib/repo-status" apps/web-platform --include=*.tsx` before adding a server import; `resolveInstallationId` pulls in server-only Supabase, so the async resolver MUST live server-side). The resolver:

```ts
// pseudocode — server-only module
export async function resolveNeedsReconnect(
  repoStatus: string | null,
  userInstallationId: number | bigint | null | undefined,
  userId: string,
): Promise<boolean> {
  // Short-circuit: non-ready or personal install set → cheap, no RPC (AC3/AC4)
  if (repoStatus !== "ready") return false;
  if (userInstallationId != null) return false;
  // ready + null user-column → only NOW pay the workspace-credential read (AC1/AC2)
  const wsInstall = await resolveInstallationId(userId);
  return wsInstall == null;
}
```

Then:
- `app/api/kb/tree/route.ts:39` — replace `repoNeedsReconnect(repo_status, github_installation_id)` with `await resolveNeedsReconnect(repo_status, github_installation_id, user.id)`.
- `app/(dashboard)/dashboard/settings/page.tsx:37` — same substitution with `user.id`.

Keep `repoNeedsReconnect` exported and used *inside* `resolveNeedsReconnect` for the pure-boolean portion (and its existing unit tests stay green, AC4). This preserves the single-source-of-truth invariant the helper doc mandates.

### Research Insights

**Verify-the-negative (deepen 4.45) — both load-bearing negative claims confirmed by grep:**
- "Client re-derivation is correct; bug is server-side" → `use-kb-layout-state.tsx:189` (`refreshTree: fetchTree`) + `:100` (`setNeedsReconnect(data.needsReconnect === true)`). `refreshTree` IS `fetchTree`; on reconnect it re-fetches `/api/kb/tree` and re-derives from the server response. **Confirmed** — client clears correctly; the server re-returns `true`.
- "No client importer of `lib/repo-status` → async resolver is bundle-safe in `lib/`" → the sole `.tsx` importer `settings/page.tsx` has zero `"use client"` directives (it is `export default async function SettingsPage()`). **Confirmed** — server-only importers.

**Implementation detail — null-check polarity matches existing convention.** `resolveInstallationId` returns `Promise<number | null>`. Use loose `wsInstall == null` (mirrors `repoNeedsReconnect`'s documented loose-`== null` intent for null-or-undefined) so a `null` RPC result (non-member / no install / RPC error already reported to Sentry) → `return true` → banner shows. This is the fail-toward-alarm default (see Sharp Edges).

**Edge case — concurrent personal + workspace install.** If a user later acquires a personal install (`users.github_installation_id` set) while also being a workspace member, AC3's short-circuit returns `false` before the RPC — correct and cheaper. No double-resolution.

### Phase 3 — REFACTOR / verify

- Run AC5 grep (no inline re-derivation introduced).
- Run AC6 `tsc --noEmit`.
- Run AC7 suites.

## Files to Edit

- `apps/web-platform/lib/repo-status.ts` — add `resolveNeedsReconnect` async capability resolver; keep `repoNeedsReconnect` pure. **Placement resolved at plan time (Phase 0.3b):** the only `.tsx` importer is the server component `settings/page.tsx`; all importers are server-side, so the async resolver lives here directly (no client-bundle risk).
- `apps/web-platform/app/api/kb/tree/route.ts` — call the async resolver with `user.id`.
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` — call the async resolver with `user.id`.
- `apps/web-platform/test/lib/repo-status.test.ts` — add AC1/AC2 cases for `resolveNeedsReconnect` (workspace-shared install resolves → false; no install resolves → true).

## Files to Create

- (none) — placement resolved to existing `lib/repo-status.ts` (Phase 0.3b).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned 50 open items; none reference `repo-status.ts`, `kb/tree/route.ts`, `settings/page.tsx`, or the reconnect banner.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a read-only signal-derivation correction on an existing UI affordance. No new user-facing surface (the banner already exists), no schema change, no new write, no auth-flow change, no regulated-data surface. Product/UX gate: NONE (modifies the *visibility condition* of an existing banner, adds no new component or flow). GDPR gate (2.7): skipped — no regulated-data surface touched; the install-id is already read on these exact paths. IaC gate (2.8): skipped — pure code change against already-provisioned surface.

## Observability

```yaml
liveness_signal:
  what: "needsReconnect derivation runs on every /api/kb/tree GET and settings page render"
  cadence: "per request (KB layout mount + settings load)"
  alert_target: "n/a — synchronous request-path boolean, no background producer"
  configured_in: "app/api/kb/tree/route.ts, app/(dashboard)/dashboard/settings/page.tsx"
error_reporting:
  destination: "Sentry via existing reportSilentFallback in resolveInstallationId (server/resolve-installation-id.ts:44,58) — RPC failure already mirrors"
  fail_loud: "yes — resolveInstallationId already reports RPC/tenant errors to Sentry; a failed credential read returns null, which surfaces the banner (fail-toward-alarm, matches #4706 intent)"
failure_modes:
  - mode: "RPC resolve_workspace_installation_id transiently fails"
    detection: "reportSilentFallback feature=resolve-installation-id op=rpc-read (existing)"
    alert_route: "Sentry"
  - mode: "false-negative (banner hidden while sync truly broken)"
    detection: "resolveInstallationId returns null on real failure → resolver returns true → banner shows (fail-toward-alarm); plus #4726 went-quiet Sentry arm independently detects silent freeze"
    alert_route: "in-product banner + Sentry went-quiet arm"
  - mode: "false-positive (banner shown while sync works) — THE BUG BEING FIXED"
    detection: "AC1 test; manual repro per operator screenshot"
    alert_route: "n/a after fix"
logs:
  where: "existing logger in kb/tree route (kb/tree: unexpected error) + Sentry breadcrumbs"
  retention: "Sentry default"
discoverability_test:
  command: curl -sS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/kb/tree
  expected_output: 307 or 401
  note: "SSH-free liveness probe — an unauthenticated GET to the route that derives needsReconnect redirects (307) or 401s, proving the route is live. The needsReconnect logic itself is covered by the unit + route suites (cd apps/web-platform; ./node_modules/.bin/vitest run test/lib/resolve-needs-reconnect.test.ts test/lib/repo-status.test.ts test/api/kb-tree.test.ts)."
```

## Hypotheses

(No SSH/network-outage trigger keywords matched — section omitted per Phase 1.4 unless reviewer requests.)

## Sharp Edges

- **Keep `repoNeedsReconnect` pure.** It is imported and unit-tested as a synchronous boolean in two places and documented as the single source of truth. Do not make it `async` — wrap it in the new async resolver instead. Making it async would force `await` into the pure-unit test surface and ripple into any future synchronous caller.
- **Short-circuit before the RPC.** The common path (personal install set, or non-ready status) must NOT pay an extra `resolveInstallationId` DB round-trip on every KB-tree fetch. Resolve the workspace credential ONLY in the `ready && user-column-null` branch. (AC3 enforces this ordering.)
- **Fail toward the alarm, not away from it.** If the workspace-credential RPC errors or returns null, treat the workspace as needing reconnect (show the banner). The #4712 banner exists to catch the #4706 silent freeze; a false-positive banner is an annoyance, a false-negative is the incident class. `resolveInstallationId` already returns `null` on error (it catches and reports to Sentry), so `wsInstall == null → return true` is the correct fail-open-to-alarm default. Do NOT add a try/catch that swallows to `false`.
- **`lib/` vs `server/` placement is load-bearing.** `resolveInstallationId` pulls in server-only Supabase + `getFreshTenantClient`. If the async resolver lands in `lib/repo-status.ts` and any client component imports that module, the bundler will try to pull server deps into the client and break the build. Grep for client importers of `@/lib/repo-status` first; if any exist, put the async resolver in a server-only module and import `repoNeedsReconnect` (the pure half) into it.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold = aggregate pattern.)

## Risks & Mitigations — Precedent-Diff Gate (deepen Phase 4.4)

**Pattern-bound behavior:** "resolve the GitHub-App installation credential for a workspace whose `users.github_installation_id` is NULL." This is NOT novel — there is an established sibling precedent. Side-by-side:

| | Precedent (`app/api/kb/sync/route.ts:101-106`) | This plan (`resolveNeedsReconnect`) |
|---|---|---|
| Cheap path | `let installationId = userData.github_installation_id` | `if (userInstallationId != null) return false` |
| Fallback | `if (!installationId) installationId = await resolveInstallationId(userId)` | `const wsInstall = await resolveInstallationId(userId)` |
| Verdict | `if (!installationId) → 409 "Workspace not connected"` | `return wsInstall == null` (true → banner shown) |

The plan adopts the precedent's fallback (`resolveInstallationId(userId)`) verbatim. The only difference is the verdict polarity (the sync route *blocks*; the banner *shows an alarm*), which is intentional and correct. **No novel pattern is introduced.** Risk of divergence from the precedent: low — both now key off the same workspace-scoped credential, which is the entire point of the fix (collapse the two-signal divergence into one signal).

**Residual risk — added DB round-trip.** The `ready && user-column-null` branch adds one `resolveInstallationId` RPC call per `/api/kb/tree` fetch and per settings render *for the affected cohort only* (workspace-shared installs). Mitigation: the short-circuit (AC3) ensures the common personal-install path pays nothing. The RPC is the same one `kb/sync` already calls, membership-checked and SECURITY DEFINER — no new attack surface.

## Premise Validation

Live-checked every cited reference (state + title):

- **#4712** — CLOSED PR, *"KB sync (#4706 follow-ups): UI reconnect affordance for NULL-install workspaces + stale-last-sync heuristic"*. This is the banner's origin; the title confirms it was built for NULL-install workspaces — this bug is that intended feature over-firing on the workspace-shared sub-case. **Cite as `Ref #4712`** (closed; do not re-open).
- **#4726** — MERGED PR, went-quiet detection, Sentry-only, **no UI** (PR body: "no UI"). Related context only; not the bug site.
- **#4728** — OPEN **issue** (`workspace_id discriminator`); its work lives in OPEN PR **#4736**. Reader-inert optional `workspace_id` on `kb_sync_history` rows — orthogonal to the banner predicate, zero file overlap.
- **#4706** — MERGED **PR** (not an issue), *"reconcile ignored repos with connected workspaces + detect ready-but-unreachable workspaces"* — the original 5-week-freeze fix this banner backstops.

The banner copy, predicate, and both derivation sites were verified present on the working tree (`reconnect-notice.tsx`, `lib/repo-status.ts:12`, `kb/tree/route.ts:39`, `settings/page.tsx:37`). The reconnect→refreshTree→re-derive client wiring was verified intact (`use-kb-layout-state.tsx:100`), confirming the bug is the *server predicate*, not the client clear-condition — so this is a behavioral fix to existing, present code, not a build-the-missing-feature plan. **PR-body issue link:** there is no open issue for this bug yet; if one is filed, use `Closes #N` (pre-merge code fix, not an ops-remediation — auto-close at merge is correct).
