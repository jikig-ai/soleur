---
title: "fix: live-verify rail check FAILs on rail-listing lag — bounded observe + reload recovery + data-vs-render discriminator"
type: fix
date: 2026-10-06
slug: fix-live-verify-rail-budget
branch: fix-live-verify-rail-budget
issue: 9581
closes: 9581
lane: cross-domain
domain: engineering
brand_survival_threshold: none
---

# fix: live-verify rail check FAILs on rail-listing lag — bounded observe + reload recovery + data-vs-render discriminator

## Enhancement Summary

**Deepened on:** 2026-10-06
**Sections enhanced:** Proposed Solution, Technical Considerations,
Hypotheses, Guard Contract, Acceptance Criteria, References
**Research agents used:** inline equivalents (this harness exposes no
Task/Skill spawner — all fan-outs were executed as direct reads/greps/gh
probes by the planning process): repo-research (run.ts + rail data path
read end-to-end), learnings (rail-race cycle + vacuity learnings),
git-history (attribution probes), framework-docs (@playwright/test
installed `.d.ts` + migration 125 signature), review lenses
(correctness/simplicity/architecture/spec-flow self-review).

### Key Improvements

1. `page.reload` now carries an explicit `timeout: 30_000` — the
   installed `.d.ts` documents a default of `0` (no timeout), so an
   unpinned reload could outwait the total budget ceiling.
2. Failure diagnostics gained `reload_err` and the verdict taxonomy
   distinguishes thrown-reload (keep polling) from page-death
   (CANT-RUN) — a navigation-timeout throw does not close the page.
3. `rpc_row=no` OR `repoUrl === null` fails fast BEFORE the reload —
   scope-broken rows are a genuine regression, not lag, and must not
   burn the recovery draw.
4. Guard Contract matrix expanded to the required row roles
   (SUT/dispatch/second-member-ordering/suite-RED/must-PASS).

### New Considerations Discovered

- Playwright `page.reload` default timeout is `0` (no timeout) —
  verified in `node_modules/playwright-core/types/types.d.ts`.
- `list_conversations_enriched` signature confirmed against migration
  125: `(p_repo_url text, p_workspace_id uuid, p_archive text,
  p_status text, p_domain text, p_limit int)` — the probe spec is
  byte-consistent.
- `scripts/watch-live-verify-pass.sh` extracts only the
  `RESULT: <kind>` token, so enriched PASS/FAIL details cannot break
  the PASS watcher; no Sentry alert filters on the detail text (verified
  `apps/web-platform/infra/sentry/`).

## Overview

The post-deploy live-verify harness emits a blocking `RESULT: FAIL` when a
freshly persisted conversation does not appear in the Recent Conversations rail
inside a single 20s DOM wait with no retry and no reload. On prod, the row is
already committed before that wait begins, so any delivery-path lag longer than
20s — realtime pre-SUBSCRIBED miss, the rail's own ~9.6s bounded event-retry
exhausting against a slow commit/RPC, a slow `/api/workspace/active-repo`
settlement, or a transient `list_conversations_enriched` error — reads as a
release-blocking FAIL even though the persist/scope/render invariant the gate
exists to protect actually held. This plan replaces the single-shot wait with
a bounded observe-then-recover loop and a failure-path discriminator that
separates "data late / out of scope" from "render broken", keeping
`RESULT: FAIL` semantics honest and loud for the real regression class.

Tracking issue: #9581 (FAIL-class flake; distinct from the CANT-RUN timeout
trackers #8022, #7969, #7215, #5634, which are failures to run the harness at
all).

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). This is
a `fix-` branch with no brainstorm spec; lane was not carried forward.

## Problem Statement / Motivation

Observed failure (issue #9581): `web-platform-release` run 37426735876
(tag `web-v0.323.2`, merge sha `5b27b302c1`), job `live-verify`, step
"Run live-verify harness (report-only)":

```text
RESULT: FAIL — conversation cdda0872-f581-4383-b6da-7923de645d0a persisted but
did NOT appear in the rail within budget
```

The harness (`apps/web-platform/scripts/live-verify/run.ts`) is currently:

1. `pollFreshConversationId` polls PostgREST for the fresh row (30s budget)
   — succeeded; the conversation **was committed**.
2. `railRow.waitFor({ state: "visible", timeout: 20_000 })` (single shot,
   ~line 741) — no retry, no reload, no discriminator.
3. Any miss → `RESULT: FAIL` → emit step classifies `RESULT="FAIL"` → `BLOCK=1`
   → release run goes red → Sentry `level=error` event → operator email.

A single observed flake already consumed an operator page + a tracking issue.
The rail's data path has FOUR independent delivery arms (below); a transient
miss in all four within one 20s window is a prod-timing event, not a
regression — but the current shape cannot tell them apart.

## Research Insights

### Relevant file paths

- `apps/web-platform/scripts/live-verify/run.ts` — the harness. Assertion at
  ~:738-745 (`railRow.waitFor({ state: "visible", timeout: 20_000 })`, bare
  try/catch → `railOk`). Poll of record at ~:707-717
  (`pollFreshConversationId`, 30s). Verdict/emit at ~:747-755, :982-999.
  `awaitVisibleOrDiagnose` (:516-531) + `waitFailureState` (:398-500) are the
  established never-throws diagnostic seams this fix mirrors.
- `apps/web-platform/hooks/use-conversations.ts` — what the rail actually
  renders from. `useConversations` fetch = `supabase.rpc(
  "list_conversations_enriched", { p_repo_url, p_workspace_id, p_archive:
  "active", p_status: null, p_domain: null, p_limit: 15 })` (:359-369; rail
  `RAIL_LIMIT = 15`, `conversations-rail.tsx:15`). The fetch first awaits
  `activeRepoSettled.promise` (:321) — the shared SWR entry for
  `GET /api/workspace/active-repo`; a slow/failed settle stalls EVERY refetch.
- `apps/web-platform/components/chat/conversations-rail.tsx` — row markup is
  `<NavLink href={"/dashboard/chat/" + id}>` (:70-71) → `next/link` `<a>` —
  matches the `a[href$="/dashboard/chat/<id>"]` locator. Three mutually
  exclusive render branches — `conversations-rail-error` testid (:137),
  `conversations-rail-empty` (:152), or the rows map (:158) — give a free
  `rail_state` discriminator.
- `apps/web-platform/components/chat/chat-surface.tsx` — dispatches
  `CONVERSATION_CREATED_EVENT` with `detail.conversationId` when
  `realConversationId` resolves on a `"new"` conversation (~:495-510), and
  `CONVERSATION_ACTIVITY_EVENT` on derived turn boundaries (~:710-740).
- `apps/web-platform/app/api/workspace/active-repo/route.ts` — returns
  `{ workspaceId, repoUrl }`, the rail's exact scope inputs; reachable via
  `page.request.get` with the injected cookies (same identity the rail used).
- `.github/workflows/web-platform-release.yml` — emit step (:1965-2069)
  classifies on `case "${RESULT_LINE}"` patterns `"RESULT: PASS"*`,
  `"RESULT: FAIL"*` (→ `BLOCK=1`), `"RESULT: CANT-RUN"*` (→ `BLOCK=0`);
  enforce step (:2070-2089) is the sole blocking authority. No workflow edit
  needed if `RESULT:` line prefixes are preserved.
- `apps/web-platform/test/live-verify/` — 9 existing suites;
  `wait-failure-state.test.ts` establishes the fake-Page + never-throws
  convention; `no-bare-visibility-wait.test.ts` establishes the
  source-pin-the-wire convention (its `it(` floor lives in the pin file, a
  deliberate cross-file anti-vacuity split).

### What the rail renders from (the delivery arms)

For the fresh row to reach the DOM after commit, ONE of these must land:

1. **Realtime own-channel INSERT** — `command-center-own` channel,
   `user_id=eq.<uid>` filter → fill-only placeholder insert (:444-475), dropped
   by `shouldDropForScope` when scope unresolved. Pre-`SUBSCRIBED` deliveries
   are never replayed (supabase-js).
2. **SUBSCRIBED backfill** — one `fetchConversations()` on subscribe (:497).
3. **Scope-resolve backfill** — one quiet refetch on `workspaceId` null→id
   (:552-560).
4. **`CONVERSATION_CREATED_EVENT` bounded retry** — 6 attempts, backoff
   `[0,600,1000,1500,2500,4000]` ≈ 9.6s cumulative bound, keyed on
   `detail.conversationId` (:584-611).
5. **`CONVERSATION_ACTIVITY_EVENT` debounced refetch** — 500ms debounce on
   turn-boundary transitions (:619-635); fires repeatedly while the sent
   message's turn streams.

Arms 1-3 are one-shot; arms 4-5 repeat but are bounded/event-driven. The
20s window covers ~2× the largest designed bound (arm 4's 9.6s); the observed
flake is the all-arms-miss residual — plausible on prod when realtime connect,
active-repo settle, or the RPC is slow.

### Premise Validation (Phase 0.6)

- `gh issue view 9581` → OPEN, title matches the FAIL class; carries the exact
  observed RESULT line. Held.
- `gh pr view 5391 / 5436` → both MERGED (2026-06-16); they fixed the client
  class this FAIL was built to catch. Held.
- `gh issue view 8022 / 7969 / 7215 / 5634` → all OPEN, all CANT-RUN-class —
  confirmed distinct from this FAIL-with-harness-completed class. Held.
- `apps/web-platform/scripts/live-verify/run.ts` exists on `origin/main`;
  the single-shot `waitFor` at ~:741 and the persisted-before-assert control
  flow verified by direct read. Held.
- `.github/workflows/web-platform-release.yml` emit/enforce steps verified at
  :1965-2089 — the `RESULT: FAIL` → `BLOCK=1` mapping is as described. Held.
- ADR corpus grep for the mechanism (bounded retry / reload / poll in a
  verification harness): no ADR prescribes or rejects harness-side retry;
  ADR-064 covers the harness contract and is not contradicted — its FAIL
  semantics (rail regression = FAIL) are preserved by this plan.

### Property List (Phase 0.6b)

- P1: A persisted conversation that **never** reaches the rail DOM still
  produces `RESULT: FAIL` → `BLOCK=1` (unchanged, loud).
- P2: Delivery-path lag that self-heals within a bounded window no longer
  produces `RESULT: FAIL` (the flake).
- P3: A FAIL reports **why** — which rail render-branch was showing and
  whether the row was in the rail's own scoped data source — so "data late /
  scoped out" is distinguishable from "render broken" without a log dig.
- P4: Recovery is **measured**, not silent: the RESULT detail carries
  `via=` + `elapsed=` so the frequency of recovered runs is queryable in
  Sentry (the residual app-side delivery-gap signal is preserved, not
  masked).
- P5: The wire format the emit/enforce steps parse (`RESULT: PASS*` /
  `RESULT: FAIL*` / `RESULT: CANT-RUN*`) is unchanged — no YAML edit.
- P6: The new seam is unit-testable with the repo's existing fake-Page
  convention, and the wire (call site → seam → RESULT) is source-pinned —
  the #8092 "endpoints covered, wire not" class.

### Cut List (Phase 0.6b)

- Re-dispatch `CONVERSATION_CREATED_EVENT` from the harness via
  `page.evaluate` — buys P2 cheaply but is cooperative machinery the app's
  own listener must honor; a broken listener would silently fall through to
  reload-PASS and mask a real delivery-arm regression. Cut in favor of the
  passive reload, which exercises the mount-time fetch — a path no event
  wiring can fake.
- Extend `perf-probe.ts` to sample `list_conversations_enriched` RTT —
  buys prod latency numbers, but the RESULT-line `elapsed=` measurement
  (P4) produces them on every triggered run for free. Deferred as a
  non-goal; the probe exists (`scripts/live-verify/perf-probe.ts`, #8978)
  if a future latency question needs it.
- New RESULT kind (e.g. `RESULT: FLAKY-PASS`) — buys a fourth taxonomy slot
  but the emit/enforce steps would need a YAML edit and a new
  classification decision; `via=` inside the PASS detail carries the same
  information on the existing wire (P5). Cut.
- Multiple reloads — the reload exercises the mount-time fetch, which is
  deterministic given a committed in-scope row; a second reload repeats the
  same draw. One reload; absence after it is FAIL-worthy.

### Applicable institutional learnings

- `learnings/bug-fixes/2026-06-17-rail-realtime-race-needs-deterministic-signal-not-timing-tweaks.md`
  — the #5391→#5421→#5436 cycle: timing tweaks without a deterministic
  signal failed three times; verify against the deployed artifact. This
  plan is the harness-side completion of that lesson: the harness must
  observe like prod behaves, not like the happy path.
- `learnings/2026-06-17-message-free-verification-invariant-structurally-vacuous.md`
  — verification must exercise the real path; the reload arm exercises
  mount-time fetch, a real path.
- `learnings/2026-07-16-five-documented-traps-recurred-and-a-perturbing-instrument-is-not-evidence.md`
  — the reload arm is a perturbation, so the FAIL discriminator
  (rpc_row + rail_state) is what keeps it honest.
- `learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
  — a FAIL that cannot say WHY is the same check repeated: the
  `rail_state`/`rpc_row`/`active_repo` fields are the reporting layer
  this lesson prescribes, added at the failure path where they cost
  nothing on PASS.
- `wait-failure-state`/`no-bare-visibility-wait` conventions (PR #8092) —
  never-throws bounded diagnostics; source-pin the wire, anti-vacuity floor
  in a different file.

### Related issues / PRs

- #9581 (this work), #8022 / #7969 / #7215 / #5634 (CANT-RUN trackers —
  unaffected), #5391 / #5421 / #5436 / #5449 / #5451 (client rail-race fix
  chain), #9270 (CONVERSATION_ACTIVITY_EVENT arm), #4543 / ADR-044
  (workspace scoping), #8978 (perf-probe), #8092 (diagnostic seam pattern).

### CLAUDE.md conventions

- Client/server import boundary documented in
  `apps/web-platform/server/README.md` — untouched (harness is a script,
  not server code).

### Community/functional discovery

- Stack: TypeScript/Next.js — covered by built-in agents; no signature-file
  gaps (no dart/rust/elixir/go/swift/kotlin/php files). Community
  discovery: skipped per its own skip condition.
- Functional overlap: fix to a project-internal CI harness; no community
  artifact covers repo-specific deploy-gate semantics. Assessed inline —
  no install candidates.

## Research Reconciliation — Spec vs. Codebase

| Claim (task brief / #9581) | Reality on `origin/main` | Plan response |
|---|---|---|
| "single `railRow.waitFor` ~line 741, no retry or reload" | Confirmed — `run.ts:738-745`, bare try/catch → `railOk` | Replace with bounded observe+recover seam |
| "conversation confirmed persisted before the rail check" | Confirmed — `pollFreshConversationId` → `classifyDriveResult` → PROCEED precedes the assertion (:707-727) | The observe window starts post-commit; lag is the only way to lose |
| "emit/enforce steps key on `RESULT: FAIL` → BLOCK=1 (~lines 1762-1780)" | Confirmed — classifier case at :2005-2011, enforce at :2070-2089 | Preserve `RESULT:` prefixes; no YAML edit |
| "check `apps/web-platform/test/` for live-verify tests" | 9 suites under `test/live-verify/`; fake-Page + source-pin conventions established | Extend coverage in the same style |

## Hypotheses

(Phase 1.4 network-outage gate fired on `timeout` in the brief. Each layer
carries an artifact-based opt-out — this failure is a client-side DOM
timing race inside an app whose upstream network paths demonstrably worked
in the same run.)

1. **L3 firewall allow-list** — opted out. Artifact: the same run's
   `pollFreshConversationId` completed PostgREST round trips to
   `api.soleur.ai` and returned the committed row id; TCP/443 to Supabase
   and the app host was proven open in-run.
2. **L3 DNS / routing** — opted out. Artifact: the same run minted the
   session, loaded `/dashboard/chat/new`, and received `session_started`
   over WSS — all upstream of the failed assertion; resolution worked.
3. **L7 TLS / proxy** — opted out. Artifact: the run completed TLS to both
   `api.soleur.ai` (PostgREST) and the app origin (document load + WSS).
4. **L7 application** — opted out of *network* hypotheses; the app
   demonstrably served the page, accepted the WS session, persisted the
   row, and emitted `session_started`. The only failing hop was the
   final DOM render — inside the browser, after every network layer
   succeeded.

### Network-Outage Deep-Dive (deepen-plan §4.5 verification)

Layer-by-layer verdict against the checklist's required artifacts:

- **L3 firewall allow-list — verified-by-artifact:** the same run's
  PostgREST poll (`pollFreshConversationId`) returned the committed row
  from `api.soleur.ai` — TCP/443 to Supabase proven open in-run.
- **L3 DNS/routing — verified-by-artifact:** session mint, document load,
  and WS `session_started` all completed upstream of the failed wait.
- **L7 TLS/proxy — verified-by-artifact:** TLS to `api.soleur.ai` +
  the app origin and WSS both established in the same run.
- **L7 application — verified-by-artifact:** the app served the page,
  accepted the session, persisted the row; the only failing hop was the
  final DOM render — inside the browser, downstream of every network
  layer. No L3/L7 hypothesis survives; the residual hypotheses below are
  all inside the delivery/render path.

Flake-mechanism hypotheses (each names its recovery arm + discriminator):

- **H1 — realtime INSERT landed pre-SUBSCRIBED and all bounded retries
  exhausted.** Recovery: reload (mount-time fetch). Discriminator:
  `rpc_row=yes` on the failure path proves data was reachable.
- **H2 — `list_conversations_enriched` transient error / slow RPC during
  every refetch arm.** Recovery: reload re-runs the fetch once the
  transient clears. Discriminator: `rail_state=error` (the
  `conversations-rail-error` branch renders when the fetch rejects with no
  last-known rows).
- **H3 — `/api/workspace/active-repo` slow settlement.** Every refetch
  awaits `activeRepoSettled`; a >20s settle stalls all arms. Recovery:
  reload (fresh settle). Discriminator: `rail_state` (rail stuck in the
  loading branch — rows absent, error absent) + `active_repo=<resolved|
  unreadable>` from `page.request.get`.
- **H4 — row committed but out of the rail's scope** (repo_url /
  workspace_id mismatch — the #4543 shape). No recovery helps; this is a
  genuine FAIL. Discriminator: `rpc_row=no` after the observe window →
  FAIL fast without a wasted reload.
- **H5 — rail renders rows but never includes the id** (limit truncation,
  ordering, portal/collapse anomalies). `RAIL_LIMIT=15` makes truncation
  plausible only if the fresh row does not sort to the head — fresh rows
  carry `last_active=now()`, so this is the least likely arm; the
  `rail_state=rows:<n>` + `rpc_row=yes` discriminator still separates it.

## Proposed Solution

Replace the single-shot `railRow.waitFor` with an exported, unit-testable
seam — `assertRailRowVisible` — that observes, then recovers, then
discriminates:

```text
Phase A — OBSERVE (≈45s):
  poll railRow.isVisible() every ~1.5s.
  visible → verdict { kind:"appeared", via:"direct", elapsedMs, checks }.

Phase B — RECOVER (one reload, ≈45s more):
  probe rail scope ONCE first (each probe individually bounded at ~10s
    under the same FIELD_TIMEOUT_MS-race pattern waitFailureState uses —
    a diagnostic must never stall the verdict or outlive the total
    ceiling):
    {workspaceId, repoUrl} ← page.request.get(<prod>/api/workspace/active-repo)
    rpc_row ← supabase.rpc("list_conversations_enriched", { p_repo_url,
      p_workspace_id, p_archive:"active", p_status:null, p_domain:null,
      p_limit:15 }) membership check for convId
    → "yes" | "no" | "unreadable:<reason>"
  rpc_row === "no" OR resolved repoUrl === null → verdict { kind:"absent" }
    IMMEDIATELY (scope-broken / repo-less rail — a reload cannot help;
    H4 is a genuine FAIL, not lag).
  otherwise        → page.reload({ waitUntil:"domcontentloaded",
    timeout: 30_000 });   // d.ts: reload's default timeout is 0 = NO
    // timeout — an unpinned reload can hang past the total ceiling;
    // the bound is mandatory, not optional.
    keep polling isVisible() ~1.5s to the phase-B deadline.
    A thrown reload is NOT verdict material: capture `reload_err=<name>`
    into diagnostics and KEEP POLLING — a navigation-timeout throw does
    not close the page, so the post-reload window still applies. Only a
    target-closed / context-destroyed class (detected when isVisible()
    itself throws) maps to unverifiable.
    visible → { kind:"appeared", via:"reload", elapsedMs, checks }.
    deadline → { kind:"absent" } with diagnostics.

Failure diagnostics (never-throws, bounded like waitFailureState):
  rail_state = error | empty | rows:<n> | rail-absent | unreadable
  rpc_row    = yes | no | unreadable:<reason>
  active_repo = resolved | unreadable
  reload_err = <error.name> (only when the reload threw)

Verdict → Result mapping (pure function, exported):
  appeared          → PASS:  `fresh conversation persisted and appeared in
                       the rail (via=<direct|reload> elapsed=<N>s
                       checks=<n>)`
  absent            → FAIL:  `conversation <id> persisted but did NOT
                       appear in the rail within <total>s budget
                       (checks=<n> reloads=<m> rail_state=<…> rpc_row=<…>
                       active_repo=<…> [reload_err=<name> only when the
                       reload threw]) (the #5391/#5436 class, #9581)`
  page/reload dies  → CANT-RUN `rail-check:<waitFailureState diagnostic>`
                       (Target-closed / navigation-destroyed classes —
                       the page cannot reach a verdict; consistent with
                       awaitVisibleOrDiagnose's existing classification).
```

### Why this shape and not the alternatives

- **vs. a bigger constant (20s → Ns):** rejected — it cannot distinguish
  the all-arms-miss residual from a real regression, only delays the
  verdict. The `elapsed=` measurement lands in every RESULT line instead,
  so future budget questions are answered by Sentry query, not opinion.
- **vs. reload-retry only:** a bare reload would mask a broken delivery
  arm entirely (mount fetch always includes a committed in-scope row).
  The observe window gives the app's own arms ~4× their designed bound
  (~9.6s event retry + refetch latency) before reloading, and the
  `via=reload` PASS detail preserves the fact that they missed — the
  signal is downgraded to a measurement, not silenced.
- **vs. re-dispatching `CONVERSATION_CREATED_EVENT`:** cooperative — it
  only exercises the listener arm. A deleted/broken listener would route
  to reload-PASS and hide a real regression in the very mechanism
  #5391/#5436 built.
- **`rpc_row=no` fails fast:** a committed row absent from
  `list_conversations_enriched` under the rail's own scope params is a
  scope regression (#4543-class), not lag — it must not burn the reload
  or report as a generic timeout.

### Honest FAIL semantics (P1)

The gate still FAILs — and only FAILs — when the row genuinely cannot
reach the rail: out of scoped data (`rpc_row=no`), or absent from the DOM
after the app's own recovery bounds AND a fresh mount fetch. A row that
never appears still FAILs loudly: `BLOCK=1` unchanged.

## Technical Considerations

- **Playwright semantics:** poll `locator.isVisible()` (point-in-time,
  per-call) — NOT `waitFor`/`waitForSelector`, which would re-enter the
  `no-bare-visibility-wait` source-pin territory and can throw across
  navigation. Locators are lazy; the same `railRow` locator survives the
  reload.
- **`isVisible()` vs viewport:** both `waitFor(state:"visible")` and
  `isVisible()` accept off-viewport elements; no semantics change vs the
  old assertion.
- **New CANT-RUN subclass:** a page/browser death mid-check currently
  collapses into `railOk=false` → FAIL. The seam classifies
  target-closed/context-destroyed classes as `unverifiable` → CANT-RUN —
  consistent with `awaitVisibleOrDiagnose` and honest about what was
  verified (nothing). Deliberate classification change; documented for
  review.
- **`page.request` shares the injected cookie jar** — the active-repo
  probe reads exactly what the rail's SWR entry read.
- **RPC parity:** probe params mirror `RAIL_OPTIONS`
  (`{ archive:"active", status:null, domain:null, limit:15 }`) so
  `rpc_row` answers "is it in the list the rail fetched", not a
  different list.
- **Job budget:** worst case adds ~90s to a `timeout-minutes: 15` job;
  teardown ordering is unchanged (teardown still runs on FAIL).
- **Reload timeout (deepen finding):** Playwright's `page.reload`
  signature carries `timeout` defaulting to `0` — verified against
  `node_modules/playwright-core/types/types.d.ts` (`reload(options?:
  { timeout?: number; waitUntil?: … })`, doc: "Defaults to `0` - no
  timeout"). The seam MUST pass an explicit `timeout: 30_000` or a
  wedged navigation can outwait `RAIL_ASSERT_TOTAL_BUDGET_MS`; a thrown
  reload still routes to `reload_err` + keep-polling, never a verdict.
- **Precedent diff (deepen §4.4):** every pattern the seam prescribes
  has a same-file / same-suite precedent — never-throws bounded
  diagnostics (`waitFailureState`'s `safe()` race, run.ts:412-426),
  exported pure helpers for testability (`parseWsErrorFrame`,
  `classifyDriveResult`, `pollFreshConversationId`), the
  seam-call-site source pin (`no-bare-visibility-wait.test.ts`), the
  fake-Page fixture shape (`wait-failure-state.test.ts` `fakePage`).
  `page.request.get` + `supabase.rpc` on the rail's own data source is
  the one novel combination — no precedent; the probe is confined to
  the failure path so its blast radius is a diagnostic, not a verdict
  path.
- **Trigger gate:** `scripts/live-verify/run.ts` is not in
  `trigger-paths.txt` — the harness does not self-trigger on release.
  Same as every prior harness fix (#8092); no file added to the trigger
  list (harness-only diffs exercising themselves would make every
  release pay the ~10min Playwright install for a machinery change).
- **NFR:** no nfr-register impact — CI machinery only.
- **Encryption posture (deepen §4.10 evaluation):** introduces NO new
  persistent store and NO new cross-component connection — the
  `supabase.rpc` probe and `page.request.get` both ride pre-existing
  authenticated surfaces (the minted synthetic-user session and the
  injected browser context respectively). Section not required.

## User-Brand Impact

- **If this lands broken, the user experiences:** the release gate's own
  artifacts — a spurious `RESULT: FAIL` still reddens a release and
  emails the operator (if recovery over-triggers), or a real rail
  regression reports green (if the seam ever over-recovers). Both are
  caught by the suite + the `via=`/`rpc_row=` measurements, which is why
  they are plan-level requirements and not niceties.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing new — the RESULT line already flows through `redact()` and the
  new detail fields carry only UUIDs, counts, and fixed tokens (no
  tokens, no URLs beyond the already-allowlisted path forms).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is the
  operator's release-signal quality (Soleur's own machinery,
  `meta/machinery`), never an end user's data, session, or money — no
  end user can observe this change at all.

## Observability

```yaml
liveness_signal:
  what: RESULT line per triggered release run + Sentry event tagged gate=live-verify
  cadence: per web-platform release with triggering changes
  alert_target: operator email via Sentry alert on level=error; ::warning annotation for CANT-RUN
  configured_in: .github/workflows/web-platform-release.yml (emit step, "Emit result to Sentry + compute block signal")

error_reporting:
  destination: Sentry via POST to the public DSN store endpoint in the emit step
  fail_loud: RESULT: FAIL lines and job-level ::error annotations; BLOCK=1 reddens the release run

failure_modes:
  - mode: delivery arms miss transiently (the flake being fixed)
    detection: PASS detail carries via=reload — queryable in Sentry as a trend line, no longer a page
    alert_route: none (record-only); a rising via=reload trend is the app-side fix signal
  - mode: row persisted but out of rail scope (H4)
    detection: RESULT: FAIL with rpc_row=no in the detail
    alert_route: operator email via Sentry level=error + BLOCK=1
  - mode: row in scope but never renders (H1/H5 genuine)
    detection: RESULT: FAIL with rpc_row=yes and rail_state=<branch>
    alert_route: operator email via Sentry level=error + BLOCK=1
  - mode: page/browser dies mid-check
    detection: RESULT: CANT-RUN:rail-check:<diagnostic> + ::warning annotation
    alert_route: release annotation (non-blocking)

logs:
  where: GitHub Actions run log (live-verify step, tee /tmp/live-verify.out) + Sentry event message
  retention: Actions retention window; Sentry project retention

discoverability_test:
  command: rg -n "RESULT: PASS" .github/workflows/web-platform-release.yml
  expected_output: RESULT: PASS
```

## Guard Contract

### Guard 1 — rail-verdict honesty (row that never appears must FAIL; lag must not)

**Property.** After the conversation is confirmed persisted, a verdict of
FAIL is emitted iff the row is absent from the rail's scoped data source
OR absent from the rail DOM after the observe window plus one reload; a
row that reaches the DOM by any path yields PASS with its recovery path
recorded — never silently.

**Assembly.** The single chokepoint is the rail-verdict seam in
`driveAndVerify` (the ONLY place a rail PASS/FAIL is decided — the same
structural fact the current `railRow.waitFor` block holds today) and its
pure verdict→`Result` mapper; downstream chokepoints are `emitLine`/`emit`
(the only RESULT writers) and the workflow's `case "${RESULT_LINE}"`
classifier. The suite pins all four layers: seam behavior with a fake
Page, mapper output strings, RESULT-line shape, and the source-pin that
the call site routes through the seam (the #8092 endpoints-covered-
wire-not class).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | SUT — delete the reload arm (observe then straight to FAIL) | RED — the appears-only-after-reload scenario asserts PASS `via=reload` |
| 2 | SUT — revert the call site to bare `railRow.waitFor` (bypass the seam entirely) | RED — source-pin asserts the rail assertion routes through the exported seam and `railRow.waitFor(` is absent |
| 3 | SUT — `rpc_row=no` falls through to reload instead of FAIL-fast | RED — the scope-out scenario asserts FAIL **without** a reload call; this is the required ordering row: member 2 (the recovery draw) must not run when member 1 (the scope probe) has already decided — a check that runs both unconditionally cannot distinguish scope-broken from lag |
| 4 | SUT — map the unverifiable (page-dead) verdict to FAIL | RED — classification test asserts CANT-RUN |
| 5 | Guard's own dispatch — emit PASS without `via=` in the detail | RED — wire-shape test asserts the `via=` token in both PASS arms; an unmeasured recovery is the defect this guard exists over |
| 6 | Suite (harness) — drop the reload-call-count assertion from the appears-after-reload fixture | RED — a no-reload SUT then passes undetected; the suite must itself assert `reloadCalls === 1` (a guard reporting "0 recoveries exercised" and passing is vacuous) |
| 7 | must-PASS (non-canonical input, explicitly permitted variation) — fixture A: row appears on observe tick 3; fixture B: appears only on post-reload tick 2 | both must PASS the seam with correct `via=` — proves the guard accepts the recovery-path variation it is designed to tolerate, not just the canonical tick-1 case |
| 8 | Suite (harness) — `emit(FAIL)` / `emit(PASS)` output must match `/^RESULT: (FAIL|PASS) —/` | RED if wire prefixes drift — anchors the workflow classifier outside this diff |

**Anchor.** The workflow classifier (`.github/workflows/web-platform-release.yml`
emit step) is outside this diff but is the consumer the wire shape protects —
row 8 is what catches a weakening that only this side could introduce.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Read run.ts end-to-end around the rail assertion — understand what the rail renders from … and what latency is actually plausible on prod" | `## Research Insights` §What the rail renders from + `## Hypotheses` | mapped |
| 2 | "Fix the flake … poll the conversations API/source-of-truth endpoint for the row, THEN assert DOM visibility … or retry the rail check with a bounded reload/backoff loop" | `assertRailRowVisible` seam — Phase A observe + scope probe + single reload; run.ts edit | mapped |
| 3 | "widen the budget only if justified from measured prod timing" | `elapsed=`/`via=` measurement in every RESULT detail; ~45s+45s bounds justified as ~4× the app's own designed delivery bound, not a magic constant | mapped |
| 4 | "Check the result-taxonomy plumbing … keep the wire format the gate parses" | No new RESULT kind; `RESULT:` prefixes preserved; wire-shape test row | mapped |
| 5 | "Tests: extend whatever unit/fixture coverage exists for run.ts … synthesize fixtures only" | New `rail-assert-verdict` suite + pin extension in the established fake-Page style | mapped |
| 6 | "Gate impact: every flake FAIL emails the operator; keep the gate loud for real failures" | `rpc_row=no` FAIL-fast; absent-after-reload FAIL; `BLOCK=1` path untouched | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `assertRailRowVisible` observe+reload seam | "retry the rail check with a bounded reload/backoff loop" | asked |
| `rpc_row` scope probe + FAIL-fast | "poll the conversations API/source-of-truth endpoint for the row, THEN assert DOM visibility (distinguishes 'data late' from 'render broken')" | asked |
| `via=`/`elapsed=` RESULT measurement | "prefer measurement over a bigger magic constant" | asked |
| `rail_state`/`active_repo` diagnostics | "distinguishes 'data late' from 'render broken'" | asked |
| CANT-RUN on page-death mid-check | — | inferred — justification: a dead page cannot reach a verdict; FAIL would misreport an unverifiable run as a rail regression, which is the exact misclassification class this fix removes (consistent with `awaitVisibleOrDiagnose` precedent in the same file) |
| `no-bare-visibility-wait` pin extension + anti-vacuity floor | — | inferred — justification: the #8092 pin convention requires the wire itself to be source-pinned or the seam's tests cover endpoints it never wires (the documented endpoints-covered-wire-not class) |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 3 | Estimated changed lines: ~380
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `run.ts`'s rail assertion no longer relies on a single 20s
  `waitFor`; it polls `railRow.isVisible()` on a bounded interval across an
  observe window of ~45s and, absent, performs exactly one
  `page.reload({waitUntil:"domcontentloaded", timeout: 30_000})`
  followed by a second ~45s window. The two windows plus probe/reload time are enclosed in ONE
  named total ceiling constant (≈ `RAIL_ASSERT_TOTAL_BUDGET_MS ≈ 100s`)
  so the check can never out-wait its own budget — the 20s constant's
  original wall-clock-bounding role is preserved at the higher value
  (defense-relaxation accounting: it bounded FAIL-detection latency and
  job time; the new ceiling bounds the same threats at ~100s inside the
  15-min job budget).
- [ ] AC2: Before the reload, the harness probes
  `list_conversations_enriched` with the rail's own scope inputs
  (`{workspaceId, repoUrl}` from `page.request.get("…/api/workspace/
  active-repo")`); `rpc_row === "no"` returns a FAIL verdict immediately
  without reloading.
- [ ] AC3: A row that appears at any point yields `RESULT: PASS —` whose
  detail records `via=<direct|reload>` and `elapsed=<N>s`.
- [ ] AC4: A row that never appears still yields `RESULT: FAIL —` →
  `BLOCK=1` (wire format unchanged — `RESULT: PASS*`/`RESULT: FAIL*`/
  `RESULT: CANT-RUN*` prefixes all preserved; zero workflow-YAML edits).
- [ ] AC5: The FAIL detail carries `rail_state=<error|empty|rows:<n>|
  rail-absent|unreadable>`, `rpc_row=<yes|no|unreadable:<reason>>`,
  `checks=<n>`, `reloads=<m>` — all through `redact()`.
- [ ] AC6: Page/browser death inside the seam yields `RESULT: CANT-RUN`
  carrying the `waitFailureState` diagnostic, not a FAIL.
- [ ] AC7: New vitest coverage drives all six verdict paths with
  synthesized fake-Page/fake-supabase fixtures only; the source pin
  asserts the call site routes through the seam and no `railRow.waitFor(`
  returns.
- [ ] AC8: `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/live-verify/` green; `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` and `eslint` clean on the touched
  files. (NOT `bun test` — `apps/web-platform/bunfig.toml` carries
  `pathIgnorePatterns = ["**"]`, which silently blocks bun test
  discovery; and NOT `npm run -w` — the root package.json has no
  `workspaces` field.)
- [ ] AC9: Teardown ordering unchanged — `teardownConversation` still runs
  after the verdict regardless of outcome.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI-verification machinery change on
an existing deploy-gate script. Engineering was assessed and does not meet
its bar (no architectural decision, no new infrastructure; a bounded retry
inside an existing harness is normal implementation). All other domains'
assessment questions return no.

## Test Scenarios

- Given the row is already in the DOM on tick 1, when the seam runs, then
  it returns `{ kind:"appeared", via:"direct" }` and `page.reload` was
  never invoked.
- Given `isVisible()` is false for N ticks then true inside the observe
  window, when the seam runs, then `via="direct"` and no reload.
- Given `isVisible()` is false through the observe window and true only
  after `page.reload()` is called, when the seam runs, then
  `{ kind:"appeared", via:"reload" }` and the PASS detail contains
  `via=reload` and `elapsed=`.
- Given `isVisible()` stays false and the RPC membership probe returns no
  row, when the seam runs, then the verdict is `absent` → `RESULT: FAIL —`
  with `rpc_row=no` and `page.reload` was never called (fail-fast, H4).
- Given `isVisible()` stays false through both windows and `rpc_row=yes`,
  when the seam runs, then `RESULT: FAIL —` carries `rpc_row=yes` and
  `rail_state=<the fake's rendered branch>`.
- Given the RPC probe or `page.request` throws, when the seam runs, then
  `rpc_row=unreadable:<reason>` is embedded and the reload still runs —
  diagnostics never throw (waitFailureState invariant).
- Given `page.reload()` throws a navigation-timeout-class error but
  `isVisible()` keeps resolving, when the seam runs, then polling
  continues to the phase-B deadline and `reload_err=<name>` lands in the
  FAIL diagnostics — a thrown reload is not verdict material.
- Given `isVisible()` itself throws a target-closed / context-destroyed
  class error, when the seam runs, then the verdict maps to `CANT-RUN`
  carrying the waitFailureState diagnostic — never FAIL.
- Given the verdict mapper, when each verdict kind is mapped, then
  `emitLine` output matches `/^RESULT: (PASS —|FAIL —|CANT-RUN:)/` — the
  workflow classifier anchors.
- Given `conversations-rail-error` testid visible at FAIL time, when
  diagnostics collect, then `rail_state=error`; given the empty-state
  testid, `rail_state=empty`; given K other rail anchors, `rail_state=
  rows:K`.
- Source pins: `no-bare-visibility-wait.test.ts` extended to assert the
  rail-verdict call site routes through the seam and `railRow.waitFor(` is
  absent; the new suite's `it(` floor asserted from a different file (the
  established anti-vacuity split).

## Files to Edit

- `apps/web-platform/scripts/live-verify/run.ts` — replace the
  `railRow.waitFor` block (~:738-745) with the `assertRailRowVisible`
  seam; add the exported seam, the scope-membership probe, the
  `rail_state` collector, and the pure verdict→`Result` mapper; reuse
  `waitFailureState`/`FIELD_TIMEOUT_MS` conventions for the never-throws
  diagnostic path.
- `apps/web-platform/test/live-verify/no-bare-visibility-wait.test.ts` —
  extend the source pin: assert the rail-verdict call site routes through
  the exported seam and that no `railRow.waitFor(` returns (AC7's wire
  pin; the same file is the natural home because it already owns the
  bare-wait vocabulary).

## Files to Create

- `apps/web-platform/test/live-verify/rail-assert-verdict.test.ts` —
  fake-Page/fake-supabase coverage of all verdict paths (synthesized
  fixtures only, `cq-test-fixtures-synthesized-only`). The new suite's
  `it(` floor is asserted from `no-bare-visibility-wait.test.ts`, keeping
  the established cross-file anti-vacuity split.

## Implementation Phases

1. **Seam + mapper.** Extract `assertRailRowVisible`,
   `probeRailScopeRow`, `railRowState`, `railVerdictToResult` as exported
   units in `run.ts`; wire the call site; keep `RESULT:` emit shapes
   byte-compatible.
2. **Failing tests first.** Write `rail-assert-verdict.test.ts` against
   the exported seam (red), extend the pin, then implement to green.
   (Ordering is deliberate — `cq-write-failing-tests-before`.)
3. **Verify locally.** `vitest run test/live-verify/`, `tsc`, `eslint`.
   A live `--dry-run` is NOT required (the seam is unit-covered; a
   non-dry live run is exactly what the next triggering release
   exercises).

## Success Metrics

- The next `rpc_row=yes`-shaped prod lag produces `RESULT: PASS — …
  via=…` instead of a page; `via=reload` occurrences stay near zero and
  are queryable in Sentry (`message:"via=reload"`).
- Any genuine rail regression still produces `RESULT: FAIL` with
  discriminating `rail_state`/`rpc_row` fields — first-triage time drops
  because the FAIL line itself names the layer.

## Dependencies & Risks

- **Risk: over-recovery masks a broken delivery arm.** Mitigation: the
  observe window exceeds every designed arm bound ~4×; `via=reload` keeps
  the miss measurable; FAIL on `rpc_row=no` still catches scope breaks.
- **Risk: `list_conversations_enriched` signature drift.** The probe
  copies the rail's params; a signature change would degrade to
  `rpc_row=unreadable` (safe) and is caught by the suite's probe-shape
  test.
- **Risk: longer FAIL latency on genuine regressions** (~90s worst case
  added). Bounded by the 15-min job timeout; teardown ordering
  unchanged.
- **Pre-existing, out of scope:** `RAIL_LIMIT=15` truncation and the
  app's residual in-session delivery gap (an arm-miss with no later
  refetch leaves a real user's rail stale until next mount). If
  `via=reload` recurs, file that as its own app-side issue — the
  measurement this plan adds is exactly what would evidence it.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (87 issues)
searched for `apps/web-platform/scripts/live-verify/run.ts`,
`apps/web-platform/test/live-verify`, and
`apps/web-platform/hooks/use-conversations.ts`: zero body matches.

## References & Research

- Issue: #9581; run 37426735876 (`web-v0.323.2`, sha `5b27b302c1`)
- `apps/web-platform/scripts/live-verify/run.ts` (assertion ~:738-745;
  seams :398-531; poll :877-900; emit :982-999)
- `apps/web-platform/hooks/use-conversations.ts` (fetch :277-396; arms
  :408-635)
- `apps/web-platform/components/chat/conversations-rail.tsx` (:128-166;
  `RAIL_LIMIT` :15)
- `.github/workflows/web-platform-release.yml` (:1965-2089)
- ADR-064 `knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`
- Learnings (under `knowledge-base/project/learnings/`):
  `bug-fixes/2026-06-17-rail-realtime-race-needs-deterministic-signal-not-timing-tweaks.md`,
  `2026-06-17-message-free-verification-invariant-structurally-vacuous.md`,
  `2026-07-16-five-documented-traps-recurred-and-a-perturbing-instrument-is-not-evidence.md`
