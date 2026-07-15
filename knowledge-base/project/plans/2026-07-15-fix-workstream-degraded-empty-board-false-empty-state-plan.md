---
title: "fix: Workstream board false 'No issues' flash on a degraded read"
type: bug
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
branch: feat-one-shot-workstream-degraded-empty-board
created: 2026-07-15
---

# 🐛 fix: Workstream board intermittently shows "No issues to display" on a degraded read

## Enhancement Summary

**Deepened on:** 2026-07-15
**Agents:** code-simplicity-reviewer, architecture-strategist, observability-coverage-reviewer,
user-impact-reviewer, learnings-researcher (+ premise validation, precedent grep).

### Key improvements from the deepen pass
1. **P2 observability gap closed (arch P1):** the P2 degrade is mirrored only at **WARN** level
   under `feature:repo-scope` (ADR-059 flood remediation), NOT `feature:workstream`. Added a
   workstream-tagged mirror at the P2 throw site so the board's own degrade is queryable under
   `feature:workstream op:repo-unresolved` and its AC9 discoverability doesn't depend on a shared
   quiet WARN signal.
2. **User-impact FINDING 2 folded in (client guard):** "+ New Issue" is clickable during a
   first-load degrade (`error && !data`); an optimistic create whose POST then fails rolls back to
   `{issues:[]}` → **resurrects the exact EmptyState this PR removes**. Fix: disable New-Issue
   creation while the board failed to load with no data. Plan is no longer strictly "server-only."
3. **User-impact FINDING 1 corrected (arch/UX):** the permanent-revoke scope-out reason was
   FALSE (reconnect guidance on the write surface is unreachable when columns never render).
   Corrected the reason + deferred an in-surface reconnect affordance (tracking issue).
4. **SWR retry facts corrected:** `swr-config.ts` sets no `errorRetryCount`/`shouldRetryOnError`
   → **indefinite** retry with exponential backoff (not "~5× then stops"). Transient self-heals;
   permanent-revoke becomes a persistent honest error (bounded by backoff).
5. **Extraction safety (arch P2):** preserve the WARN-vs-ERROR split when extracting
   `readCurrentRepoUrlResult` (tenant-mint → `warnSilentFallback`; query-error →
   `reportSilentFallback`) — unifying them regresses the ADR-059 false-positive flood.
6. **Precedent + learnings grounded:** direct precedent for the `error && data` banner mechanism
   (`2026-06-26-swr-refresh-failed-keep-stale-data-use-error-and-data.md`) and the anti-pattern
   class (`2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md`).

## Overview

The Workstream kanban board (`components/workstream/workstream-board.tsx`) intermittently
renders the empty state **"No issues to display"** even when the connected repo has issues.
The screenshot capturing it shows the flash **while "Refreshing…" is active** — i.e. during a
SWR revalidation — and it self-heals on a subsequent refresh, which is why it happens
"sometimes."

**Root cause (confirmed by code read):** `server/workstream/get-workstream-issues.ts`
returns `[]` (which the route serves as **HTTP 200**) for a **DEGRADED read** — not only for
the honest-empty case. SWR treats a 200 as success and **replaces** the cached `data` with the
empty payload, so the board's `issues.length === 0` branch (line 572) renders `<EmptyState>`,
clobbering the previously-loaded issues. A 200-with-`[]` is indistinguishable, to the client,
from a genuinely-empty repo.

Two degraded paths reach that `[]`:

| Path | Location | Trigger | Currently returns |
|------|----------|---------|-------------------|
| **P1 — installation unresolvable** | `get-workstream-issues.ts:107-117` | repo connected, but `resolveEffectiveInstallationId` → `null` (revoked/lost grant OR transient RPC blip) | `[]` + `reportSilentFallback` |
| **P2 — repoUrl null-from-error** | `get-workstream-issues.ts:99` (via `getCurrentRepoUrl`) | `getFreshTenantClient` throws `RuntimeAuthError` (cold **token cache**) or the `workspaces` query errors (cold **connection pool**) — `getCurrentRepoUrl` **fails-open to `null`** | `[]` (honest-empty path) |

**The bug report scoped the fix to P1 only. Research shows that is insufficient.** On the
exact "right after a backend deploy/restart: cold connection pool + cold token cache" scenario
the report describes, the **most likely** failure is a `RuntimeAuthError` from
`getFreshTenantClient` inside `getCurrentRepoUrl` — which returns `null` and exits at
**line 99 (P2)**, never reaching line 107. A P1-only fix would leave the dominant instance of
the reported bug unfixed and it would re-surface. This plan fixes **both** paths.

**Design constraint honored:** the empty-vs-throw split is load-bearing for observability
(`cq-silent-fallback-must-mirror-to-sentry`). The Sentry mirror is **preserved at every
degrade point** (the mirror-of-record for BOTH the HTTP route caller and the agent-tool
caller); `[]` is **reserved strictly for** "no repo connected" and genuine zero-issue repos.

**Premise validation (Phase 0.6):** PR #6308 (`feat(workstream): edit body/labels/…`) is
MERGED (2026-07-15) and touched `workstream-board.tsx` (+61) but the empty-vs-throw logic in
`get-workstream-issues.ts` predates it (originates #5659 / #5898). Bug is **pre-existing**, as
the report states. All cited files/lines verified present on the working branch. No external
premises stale.

## Research Reconciliation — Report vs. Codebase

| Report claim | Codebase reality | Plan response |
|--------------|------------------|---------------|
| Degraded-empty enters only at `get-workstream-issues.ts:107-117` (P1) | `getCurrentRepoUrl` (`server/current-repo-url.ts`) **fails-open to `null`** on `RuntimeAuthError` (tenant-mint blip → `warnSilentFallback`) and on `workspaces` query error (→ `reportSilentFallback`). That `null` collapses to `[]` at **line 99 (P2)** — the more likely cold-start path. | Fix **both** P1 and P2. P2 needs a degrade-aware read that does NOT change `getCurrentRepoUrl`'s shared contract (12 consumers). |
| Fix direction (A) throw → 502; (B) `degraded:true` flag | Route GET `catch` already returns **502** on any throw (`route.ts:47-53`); SWR has **no `keepPreviousData`** but its default **retains `data` on an error** and replaces it on a 200 → a throw is exactly what keeps prior issues on screen. The `refreshFailed` amber banner ("Couldn't refresh — showing the last loaded issues.") **already exists** (`workstream-board.tsx:537-541`). | **Adopt Option A.** It reuses the existing 502 path + SWR error-semantics + existing banner with **zero client changes and zero response-type widening**. Reject Option B (fights SWR's data model, widens `IssuesResponse`, needs new client merge/ref state). |
| `hr-type-widening-cross-consumer-grep` if the response/return type widens | `getWorkstreamIssues` return type stays `WorkstreamIssue[]` (it throws, not widens). `getCurrentRepoUrl` signature stays `Promise<string \| null>`. | **No shared type widens.** The new `readCurrentRepoUrlResult` variant is additive; `getCurrentRepoUrl` becomes a thin wrapper over it — 12 consumers untouched. |

## User-Brand Impact

**If this lands broken, the user experiences:** the Workstream board flashing "No issues to
display" (with a "+ New Issue" call-to-action) on a repo that actually has open issues — reading
as data loss / a broken product on a trust surface the founder dogfoods daily.

**If this leaks, the user's data is exposed via:** N/A — this change is control-flow only
(throw vs. return `[]`). It moves **no** data across a boundary, adds **no** new read/write, and
reads only `workspaces.repo_url` (a non-credential column already in the `authenticated` grant).
No new exposure vector.

**Brand-survival threshold:** single-user incident. The board is a per-user trust surface and a
mis-implementation could regress it (e.g. throwing on honest-empty would replace a calm empty
state with an error card, or breaking one of `getCurrentRepoUrl`'s 12 consumers would ripple
across the WS resume / agent-runner / dispatcher). `requires_cpo_signoff: true` → confirm CPO
review before `/work`. `user-impact-reviewer` runs at review time.

## Recommended Design (Option A+)

Reserve `[]` for honest-empty; **throw a typed `WorkstreamDegradedError` on every degrade**;
keep the Sentry mirror at each degrade point (covers HTTP + agent callers uniformly).

### 1. New typed error — `WorkstreamDegradedError`
Mirror the existing `WorkstreamWriteError extends Error` convention
(`server/workstream/mutate-workstream-issue.ts:63`), but simpler — no `status`/`code` (the route
always 502s). Place it in `lib/workstream.ts` — **confirmed client-safe**: that module's header
declares it a leaf ("no React, no `components/` import, node-unit-testable"), so a bare
`class WorkstreamDegradedError extends Error` adds no server-only import to the client bundle.
**Sole purpose (per simplicity review):** the class exists ONLY so the route can `instanceof`-skip
its re-capture (step 4) and so a mirror-precedes-throw test can target it — it carries no
independent runtime weight (client/SWR see only the 502; the agent tool returns `isError` for any
throw). Keep it as a minimal pair with the route guard; do not add fields "just in case."

### 2. Degrade-aware repo read — additive, no cross-consumer change
In `server/current-repo-url.ts`, extract the existing body of `getCurrentRepoUrl` into:

```ts
// NEW: surfaces WHY the url is null so a degrade can be told apart from "no repo".
export async function readCurrentRepoUrlResult(
  userId: string,
  workspaceId?: string | null,
): Promise<{ url: string | null; degraded: boolean }> {
  // RuntimeAuthError (tenant-mint blip)  → warnSilentFallback (KEEP) → { url: null, degraded: true }
  // workspaces query `error`             → reportSilentFallback (KEEP) → { url: null, degraded: true }
  // data null / empty repo_url           → { url: null, degraded: false }   // honest: no repo
  // normalized url                       → { url, degraded: false }
}

// UNCHANGED signature + fail-open behavior for ALL 12 existing consumers:
export async function getCurrentRepoUrl(
  userId: string, workspaceId?: string | null,
): Promise<string | null> {
  return (await readCurrentRepoUrlResult(userId, workspaceId)).url;
}
```

The two transient branches **already mirror to Sentry** — those calls stay exactly as-is (they
are the observability of record). **Preserve the WARN-vs-ERROR split (arch P2 / ADR-059):** the
`RuntimeAuthError` tenant-mint branch (`current-repo-url.ts:45`) uses `warnSilentFallback` and
the `workspaces` query-error branch (`:65`) uses `reportSilentFallback` — this split is
load-bearing (#5290 / ADR-059 stream-replay false-positive-flood remediation). A careless
extract-method that unifies them regresses the flood. `getCurrentRepoUrl`'s docstring contract
("null for no-repo OR transient error, callers treat identically, fail-closed") is preserved
verbatim for its **~11 call sites across 10 files** (`cc-dispatcher`, `conversations-tools`,
`ws-handler`, `session-sync`, `resolve-c4-eligible`, `agent-runner`, `mutate-workstream-issue`,
`cc-reprovision`, `chat/thread-info` route, `conversations` route; `ensure-workspace-repo:102` is
a comment, not a call). Grep-confirmed: **none inspects *why* the value is null**, and the one
site that reasons about it (`ws-handler.ts:1524-1535`) documents that it deliberately treats both
null-reasons identically and does NOT emit (to avoid double-count). **No `hr-type-widening` sweep
needed** — the shared symbol is unchanged.

### 3. `get-workstream-issues.ts` — throw on degrade, `[]` only on honest-empty
```ts
const { url: repoUrl, degraded } = await readCurrentRepoUrlResult(userId);
if (degraded) {
  // P2: transient resolve failure. It is ALSO mirrored upstream at WARN under
  // feature:repo-scope (ADR-059), but that shared quiet signal is not queryable under the
  // board's own feature. Mirror a workstream-scoped event so the board degrade is
  // independently discoverable (arch P1), THEN throw (mirror-precedes-throw invariant —
  // the route skips re-capture, the agent tool does no capture of its own).
  reportSilentFallback(new Error("current repo unresolved (degraded read)"), {
    feature: "workstream", op: "repo-unresolved", extra: { userId },
  });
  throw new WorkstreamDegradedError("workstream read degraded: current repo unresolved");
}
const parsed = parseConnectedRepo(repoUrl);
if (!parsed) return []; // honest empty: no repo connected  (UNCHANGED)
...
if (installationId === null) {
  // P1: repo connected but no installation resolvable. KEEP the Sentry mirror, then THROW.
  reportSilentFallback(new Error("no installation for connected repo"), {
    feature: "workstream", op: "no-installation", extra: { userId },
  });
  throw new WorkstreamDegradedError("workstream read degraded: no installation for connected repo");
}
// ... listRepoIssues (already throws on GitHub failure) → genuine [] iff repo has zero issues
```
Update the file-header "Empty-vs-throw" doc block to state the new contract: **`[]` ⟺
(no repo connected) OR (repo has genuinely zero issues); every degrade THROWS.**

### 4. Route — avoid a double Sentry event (optional, recommended)
`app/api/workstream/issues/route.ts` GET `catch` already returns 502 on any throw — **no
behavioral change required**. Because the degrade is now mirrored at the source, skip the
route's re-`captureException` for the marked error to avoid double-counting (the codebase cares
about this — see `ws-handler.ts:1525` "would double-count"):
```ts
} catch (e) {
  if (!(e instanceof WorkstreamDegradedError)) {
    Sentry.captureException(e, { tags: { surface: "workstream-issues" } });
  }
  return NextResponse.json({ error: "workstream_query_error" }, { status: 502 });
}
```
(Genuine GitHub-LIST failures — non-`WorkstreamDegradedError` — keep their route-level capture.)

### 5. Client — for the REPORTED bug, no change; plus ONE minimal guard (FINDING 2)
The reported bug ("No issues" flash **while Refreshing**, i.e. a revalidation with **prior data**
on screen) is fixed **server-only**: on a 502 SWR keeps `data`, sets `error` → `refreshFailed`
true → the **existing** amber banner "Couldn't refresh — showing the last loaded issues." + prior
columns stay. **No EmptyState flash.** ✅ (Direct precedent: the `refreshFailed = error != null &&
data != null` mechanism is already wired — see Research Insights.)

Render ladder for the secondary first-load-degrade cases (no prior `data`):
- **502 on first-ever load:** `error && !data` → `<ErrorCard>` with Retry (honest; SWR retries
  **indefinitely with exponential backoff** — `swr-config.ts` sets no `errorRetryCount` — plus
  `revalidateOnFocus`, so a warming backend self-heals ErrorCard → columns).
- **200 `[]` (honest-empty / zero-issue repo):** `<EmptyState>` — correct, unchanged.

**FINDING 2 — fold-in (one-line client guard).** During a first-load degrade (`error && !data`),
the top "+ New Issue" `GoldButton` is still clickable (disabled only by `readOnly`,
`workstream-board.tsx:528-534`). An optimistic create runs `mutate((cur)=>({issues:[temp,…]}))`
→ `data` becomes non-null → the `error && !data` guard flips false; if the create POST then fails
against the same cold backend, the rollback sets `{issues:[]}` (`:194-200`) → the board renders
`<EmptyState>` under the amber banner — **resurrecting the exact false-empty this PR removes**.
Fix: disable New-Issue creation while the board failed to load with no data:
```ts
const firstLoadFailed = error != null && data == null;
// on BOTH the toolbar GoldButton (:528) and the EmptyState button (:642):
disabled={readOnly || firstLoadFailed}
```
This is the only client change; it is tiny and closes the one path that re-introduces the symptom.

### 6. Agent-tool parity (bonus, no new code)
`workstream_issues_list` (`server/workstream/workstream-tools.ts:102-113`) already try/catches
`getWorkstreamIssues` and returns `isError: true` with `workstream_query_error`. A degrade now
becomes a **loud `isError`** to the agent instead of a misleading `{ issues: [] }` ("no
issues"). Add a test asserting this.

## Research Insights

**Institutional learnings (applied):**
- `knowledge-base/project/learnings/2026-06-26-swr-refresh-failed-keep-stale-data-use-error-and-data.md`
  — **direct precedent, same component.** The `refreshFailed = error != null && data != null`
  banner is already wired; a 502 makes SWR set `error` while retaining `data`, so the banner lights
  automatically and SWR auto-clears `error` on the next success (no manual reset). Also the test
  recipe used by AC7: shared `SwrTestProvider` (`shouldRetryOnError:false`, `dedupingInterval:0`),
  drive failure via `global.fetch → {ok:false}`, do NOT race the `mutate()` promise, `tsc --noEmit`
  before committing.
- `knowledge-base/project/learnings/2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md`
  — the anti-pattern class: "a degrade that always succeeds emits no failure." Returning `[]`/200
  on a degraded read is exactly this; reserving `[]` for honest-empty + emitting a loud 502 + a
  monitored marker is the prescribed remedy.
- `knowledge-base/project/learnings/2026-03-20-supabase-silent-error-return-values.md` /
  `2026-03-20-middleware-error-handling-fail-open-vs-closed.md` /
  `2026-03-20-supabase-trigger-fallback-parity.md` — the fail-open→fail-closed choice must be
  explicit and documented per call; degraded/fallback branches deserve primary-path rigor.
- `knowledge-base/project/learnings/2026-07-05-content-starvation-absence-of-work-is-not-an-error.md`
  — keep "empty / healthy / failed" as three separable signals; classify the empty case explicitly,
  never fall through.

**Precedent-diff (Phase 4.4):** typed-error precedent `WorkstreamWriteError extends Error`
(`mutate-workstream-issue.ts:63`) — `WorkstreamDegradedError` mirrors the shape (minus
`status`/`code`). Additive-accessor precedent: `getCurrentRepoStatus` already coexists with
`getCurrentRepoUrl` in the same module as a sibling reader — the wrapper pattern is idiomatic here.
No novel pattern.

## Alternative Approaches Considered

| Approach | Verdict |
|----------|---------|
| **Option B — `degraded:true` flag on the response** | **Rejected.** Widens `IssuesResponse` (touch route + client + `hr-type-widening` grep), and fights SWR: by the time the client sees `degraded:true`, SWR has already replaced `data` with the empty payload, so keeping prior issues needs a new last-good ref + custom merge. More code, more surface, worse. |
| **Fix P1 (line 107) only, per the report** | **Rejected.** Leaves P2 (line 99, the dominant cold-start path) unfixed → bug re-surfaces. |
| **Change `getCurrentRepoUrl` to throw / return a discriminated result for all callers** | **Rejected.** 12 consumers rely on the intentional fail-closed-to-`null` "disconnect semantics" (`ws-handler.ts:1525` documents it). High blast radius, violates the fail-open design other surfaces depend on. The additive `readCurrentRepoUrlResult` variant gets the signal with zero consumer churn. |
| **Add SWR `keepPreviousData`** | **Rejected.** Doesn't fix the root cause — a degraded **200** would still overwrite good data with `[]` (a success, not the SWR "previous-data-on-error" case). Also a global SWR-config change with cross-surface blast radius. |

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 — P2 degrade throws + mirrors (mirror-precedes-throw):** `getWorkstreamIssues` throws
      `WorkstreamDegradedError` when `readCurrentRepoUrlResult` returns `{ url: null, degraded:
      true }`, **and** asserts (spy) a `reportSilentFallback({ feature: "workstream", op:
      "repo-unresolved" })` fired **before** the throw. Since the route skips re-capture for the
      typed error, this source mirror is the SOLE Sentry event on both callers — pin it (obs G2).
      Cover both underlying triggers (`RuntimeAuthError` tenant-mint and `workspaces` query error).
- [ ] **AC2 — P1 degrade throws + mirrors:** when `resolveEffectiveInstallationId` → `null` on a
      connected repo, `getWorkstreamIssues` calls `reportSilentFallback({ op: "no-installation" })`
      (asserted spy) **and** throws `WorkstreamDegradedError` (was: returned `[]`).
- [ ] **AC3 — honest-empty preserved:** `{ url: null, degraded: false }` (no repo) → returns `[]`
      (no throw); a connected repo whose `listRepoIssues` yields `[]` → returns `[]` (no throw).
- [ ] **AC4 — `getCurrentRepoUrl` unchanged:** existing `current-repo-url.test.ts` passes
      unmodified; a test asserts the wrapper returns `.url` and the null-on-both-reasons contract
      holds; `readCurrentRepoUrlResult` sets `degraded` correctly per branch **and preserves the
      WARN (tenant-mint) vs ERROR (query-error) mirror levels** (spy on `warnSilentFallback` vs
      `reportSilentFallback`).
- [ ] **AC5 — route 502, not 200 `[]`:** `test/workstream-issues-route.test.ts` — a degrade
      yields **HTTP 502** `{ error: "workstream_query_error" }` (was: 200 `{ issues: [] }`);
      the route does **not** double-`captureException` a `WorkstreamDegradedError`. Mock
      `resolveWorkstreamBoardMeta` as **resolving** so `Promise.all` rejects deterministically on
      the `getWorkstreamIssues` throw (not on a board-meta race).
- [ ] **AC6 — agent-tool loud:** `test/workstream-tools.test.ts` — a degrade makes
      `workstream_issues_list` return `isError: true` (was: `{ issues: [] }`).
- [ ] **AC7 — client scope:** the ONLY client edit is the FINDING-2 `firstLoadFailed` disable
      guard on the two New-Issue buttons; verify via `git diff --stat` the board diff is limited to
      that guard. RTL test (`test/components/workstream/…`) — a create attempt during a first-load
      degrade does **not** resurrect `<EmptyState>` (the New-Issue button is disabled while
      `error && !data`). Use the shared `SwrTestProvider` (`shouldRetryOnError:false`,
      `dedupingInterval:0`); drive the failure by swapping `global.fetch` to `{ ok: false }` —
      do NOT race the `mutate()` promise (harness-dependent timing; see Research Insights).
- [ ] **AC8:** `tsc --noEmit` clean; the project test runner (per `package.json scripts.test` /
      `vitest`, honoring the `test/**/*.test.ts(x)` include globs — a co-located component test is
      silently never run) green for the edited suites.

### Post-merge (operator)
- [ ] **AC9 — self-heal observable:** After deploy, confirm in Sentry that a workstream degrade
      appears as a queryable event (`feature:workstream op:no-installation` and the
      `feature:repo-scope` cold-start mirrors) rather than a silent empty read. `Automation:`
      Sentry MCP query (no SSH). Verdict rule: ≥0 events with the correct tags after the next
      cold start; the board shows the amber "showing the last loaded issues" banner, never a
      false EmptyState.

## Files to Edit
- `apps/web-platform/server/current-repo-url.ts` — add `readCurrentRepoUrlResult`; reimplement
  `getCurrentRepoUrl` as a thin wrapper (signature/behavior unchanged); **preserve the WARN
  (tenant-mint `warnSilentFallback`) vs ERROR (query-error `reportSilentFallback`) split**.
- `apps/web-platform/server/workstream/get-workstream-issues.ts` — throw `WorkstreamDegradedError`
  on P1 + P2; add the workstream-scoped mirror at the P2 throw site (`op: "repo-unresolved"`);
  keep Sentry mirrors; **switch the import from `getCurrentRepoUrl` to `readCurrentRepoUrlResult`**;
  update the header "Empty-vs-throw" doc block.
- `apps/web-platform/lib/workstream.ts` — add `export class WorkstreamDegradedError extends Error`
  (leaf module — client-safe, confirmed).
- `apps/web-platform/app/api/workstream/issues/route.ts` — skip re-capture for
  `WorkstreamDegradedError` (avoid double-count); still 502.
- `apps/web-platform/components/workstream/workstream-board.tsx` — FINDING-2 one-line guard:
  `firstLoadFailed = error != null && data == null`; `disabled={readOnly || firstLoadFailed}` on
  the toolbar `+ New Issue` button (`:528`) and the `EmptyState` button (`:642`).
- `apps/web-platform/test/server/workstream/get-workstream-issues.test.ts` — AC1/AC2/AC3
  (**switch the existing `vi.mock` from `getCurrentRepoUrl` to `readCurrentRepoUrlResult`** — the
  accessor now imports the richer variant).
- `apps/web-platform/test/current-repo-url.test.ts` — AC4.
- `apps/web-platform/test/workstream-issues-route.test.ts` — AC5.
- `apps/web-platform/test/workstream-tools.test.ts` — AC6.
- `apps/web-platform/test/components/workstream/workstream-board-*.test.tsx` (path per the
  `vitest.config.ts` `test/**/*.test.tsx` jsdom include glob) — AC7 (create-during-degrade).

## Files to Create
- Possibly one RTL test file under `apps/web-platform/test/components/workstream/` for AC7 if no
  suitable existing board test file exists. No production files created.

## Open Code-Review Overlap
None found — no open `code-review` issue references the edited files. (Confirm at `/work` time
with the two-stage `gh issue list --label code-review --json` + standalone `jq --arg` sweep over
the Files-to-Edit paths; the check requires network so it is deferred from plan-write.)

## Observability

```yaml
liveness_signal:
  what: "existing log.info 'workstream board read' (creatorAttributionCoverage) on every success"
  cadence: "per board GET / per agent workstream_issues_list call"
  alert_target: "none (cosmetic coverage log) — degrade alerting rides error_reporting below"
  configured_in: "server/workstream/get-workstream-issues.ts:146"
error_reporting:
  destination: "Sentry (via reportSilentFallback/warnSilentFallback at the degrade source) + pino stdout → container logs"
  fail_loud: "degrade now THROWS → HTTP 502 (route) / isError (agent tool); no longer a silent 200 []"
failure_modes:
  - mode: "P2 repoUrl null-from-transient-error (cold token cache / connection pool)"
    detection: "Sentry feature:workstream op:repo-unresolved (NEW, workstream-scoped, added at the P2 throw site so the board degrade is queryable under its own feature) PLUS the pre-existing feature:repo-scope op:read-current-repo-url(.tenant-mint) WARN mirror (ADR-059 level, shared)"
    alert_route: "existing workstream Sentry rules"
  - mode: "P1 installation unresolvable on connected repo (revoked grant / RPC blip)"
    detection: "Sentry feature:workstream op:no-installation"
    alert_route: "existing workstream Sentry rules"
  - mode: "GitHub LIST failure (unchanged — already throws → 502)"
    detection: "Sentry surface:workstream-issues (route captureException) for the HTTP caller. NOTE (pre-existing gap, obs G1, out of scope): the generic non-403 GitHub error path (github-api.ts:238-245) logs without reportSilentFallback, so the AGENT caller gets isError but no Sentry event for non-403 LIST failures — tracked as a follow-up (Deferral Tracking)."
    alert_route: "existing workstream Sentry rules"
logs:
  where: "Sentry events + container stdout (pino) — Better Stack ingests container logs"
  retention: "per existing Sentry/Better Stack retention (unchanged)"
discoverability_test:
  command: "Sentry issue search `feature:workstream op:no-installation` and `feature:repo-scope` after a cold start; board shows amber 'showing the last loaded issues' banner (no EmptyState). NO ssh."
  expected_output: "degrade surfaces as a queryable Sentry event + a 502 in route logs; prior issues remain on screen"
```

## Domain Review

**Domains relevant:** Product (Workstream board is a user-facing trust surface).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — this is a **behavioral** bug fix on an existing surface
that **adds no new user-facing pages, flows, or components**. UX deltas: (a) a transient degrade
now shows the **already-existing** amber "showing the last loaded issues" banner (or, on
first-ever load, the existing ErrorCard) instead of a false EmptyState; (b) a **one-line disable
guard** on the existing New-Issue buttons while the board failed to load with no data (FINDING 2)
— disabling an existing control under an error condition, not a new surface. No new component
files (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) are created (only a test
file) → no mechanical BLOCKING escalation. A strict honesty improvement using surfaces that
already ship.
**Agents invoked:** none (pipeline advisory auto-accept; deepen-plan + one-shot review provide
the substantive passes)
**Skipped specialists:** ux-design-lead (no new UI surface — reuses existing banner/ErrorCard),
copywriter (no new copy — existing banner strings unchanged)
**Pencil available:** N/A

#### Findings
No new user journey. The change makes an existing failure mode honest. `user-impact-reviewer`
will run at review time (threshold = single-user incident) to enumerate failure modes against
the diff (e.g. confirm honest-empty still renders EmptyState, confirm no consumer of
`getCurrentRepoUrl` regressed).

## GDPR / Compliance Gate (Phase 2.7)
**Assessment: no regulated-data surface touched; advisory-only, no findings.** The diff is
control-flow (throw vs. return `[]`) — it adds no new processing activity, no new
LLM/external-API data movement, no schema/migration/auth change. It reads only
`workspaces.repo_url` (a non-credential column already exposed to `authenticated`). The
`single-user incident` threshold triggers a gate *consideration* (trigger b), but there is no
data-movement axis for the gate to act on, so no `compliance-posture.md` write and no
`compliance/critical` issue. (Full `/soleur:gdpr-gate` may re-confirm at deepen-plan if desired.)

## Infrastructure (IaC) — Phase 2.8
Skipped: no new infrastructure (server/host/service/secret/vendor/DNS/cron). Pure code change
against already-provisioned surfaces.

## Hypotheses
Network-outage checklist (Phase 1.4): the report mentions "502" as the *intended* fix outcome,
not a diagnosed outage — the 502 is deliberately produced by the throw, not a firewall/SSH/DNS
symptom. No L3–L7 diagnostic order applies; this is an application-layer control-flow change.

## Risks & Mitigations
- **Permanent revoked-grant surfaces as a load error, not a calm empty state (user-impact
  FINDING 1, CONFIRMED).** On a genuinely revoked install with **no prior data**, the board shows
  `<ErrorCard>` whose only control is Retry — and SWR sets **no `errorRetryCount`**, so it retries
  **indefinitely** (bounded by exponential backoff) with `revalidateOnFocus`. This is strictly
  more honest than the old misleading EmptyState (the connected repo is NOT empty), and a warming
  backend self-heals. **Correction to the original scope-out:** the read-error state does NOT
  reach the write-surface reconnect banner (columns never render), so "reconnect guidance already
  lives on the write surface" is FALSE for this first-load path. **Disposition: deferred** — an
  in-surface reconnect affordance (wire `<ErrorCard action={{label:"Connect a repo", href:…}}>`
  for the degrade case; the `action` prop already exists on `components/ui/error-card.tsx`) is a
  separate read-path feature, out of scope for the transient-false-empty fix. File a tracking
  issue (see Deferral Tracking). The permanent-revoke case is not made data-worse by this PR (it
  was already broken/misleading); it moves from misleading-calm to honest-error.
- **`WorkstreamDegradedError` placement — resolved.** `lib/workstream.ts` is a declared leaf
  module ("no React, no `components/` import, node-unit-testable" header), so a bare `class extends
  Error` is client-safe. No further import-graph investigation needed.
- **`readCurrentRepoUrlResult` must set `degraded` correctly per branch.** The genuine-no-repo
  branch (`data` null / empty `repo_url`) MUST be `degraded:false` or honest-empty repos would
  start 502-ing. Covered by AC3. And it MUST keep the WARN-vs-ERROR mirror split (AC4) — unifying
  regresses the ADR-059 flood.
- **Route skip-recapture couples to an unenforced invariant (obs G3).** `if (!(e instanceof
  WorkstreamDegradedError)) captureException(...)` is Sentry-safe only because every
  `WorkstreamDegradedError` throw site (P1, P2) is preceded by a source mirror. Both throw sites
  now emit a `feature:workstream` mirror before throwing; AC1/AC2 pin the mirror-precedes-throw so
  a future degrade branch can't silently ship a 502 with zero Sentry coverage.

## Deferral Tracking
Two follow-ups surfaced by the deepen pass, each to be filed as a GitHub issue (`gh issue create`,
labels verified at `/work` time) with re-evaluation criteria:
1. **Board read-path reconnect affordance (user-impact FINDING 1).** Wire `<ErrorCard action>` (or
   a distinct read-only/reconnect surface) so a user whose GitHub-App grant is *permanently*
   revoked has an in-surface reconnect path instead of an infinite Retry loop. Re-evaluate if a
   `feature:workstream op:no-installation` Sentry event recurs for the same user across sessions
   (permanent, not transient).
2. **Mirror the generic non-403 GitHub LIST failure (obs G1).** Add a `reportSilentFallback` at
   `github-api.ts:238-245` so the AGENT caller (not just the HTTP route) gets a Sentry event on
   non-403 LIST failures. Small, isolated; out of scope for this control-flow fix.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, placeholder-only, or omits the threshold
  will fail `deepen-plan` Phase 4.6. This section is filled (threshold = single-user incident).
- `reportSilentFallback`/`warnSilentFallback` are named "silent" but here we **mirror-then-throw**
  (no longer silent). Keep them for the rich tag vocabulary (`pg_code`, per-tenant user
  identity); add a one-line comment at each degrade site noting the mirror precedes a throw so a
  future reader doesn't "simplify" the mirror away thinking the throw covers it — the throw is
  captured at the route boundary only for the HTTP caller; the agent-tool caller relies on the
  source mirror for Sentry coverage.
- Do NOT widen `getCurrentRepoUrl`'s signature or the two-reasons-for-null contract — 12
  consumers depend on it (`ws-handler.ts:1525` documents the reliance). The additive variant is
  the whole point.
