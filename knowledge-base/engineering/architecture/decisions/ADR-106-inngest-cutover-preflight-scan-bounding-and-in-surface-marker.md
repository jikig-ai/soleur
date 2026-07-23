---
title: Inngest cutover pre-flight scans — bound duration + abandon-safety + in-surface marker (amends ADR-105)
status: adopting
date: 2026-07-09
amends: ADR-105
supersedes: none
issue: 6258
related: [6178, 6230, 6218, 5503, 5509, 5523]
related_adrs: [ADR-105, ADR-100]
brand_survival_threshold: single-user incident
---

# ADR-106: Inngest cutover pre-flight scans — bound duration + abandon-safety + in-surface marker (amends ADR-105)

## Context

The Inngest dedicated-host cutover (#6178) is gated by two read-only pre-flight ops in
`.github/workflows/cutover-inngest.yml` — `op=inventory` (the #5509 before/after baseline) and
`op=verify` (the #6178 registry + double-fire check). Both drive paginated GraphQL scans against the
self-hosted `inngest start` server's Postgres-backed GQL API through the host webhook (adnanh/webhook
v2.8.2): `inngest-inventory.sh` (`eventsV2` over a 365-day window with `includeInternalEvents:true`),
`inngest-doublefire-probe.sh` (`runs` over a 365-day / all-function history), and the single-shot
`inngest-registry-probe.sh` (`functions { id }`).

After ADR-105 bounded the connection *footprint* (per-pool cap + idle drain, deployed prod ~14:14 UTC
2026-07-09), the pre-flight hooks still **hung past their outer curl budget and returned `HTTP 000`
(empty body)** — verified with two fresh `op=inventory` runs after a clean restart with the capped
build. ADR-105 explicitly did **not** bound scan *duration/cost* (`ADR-105` §Consequences); the
`HTTP 000` hang is a distinct failure mode from the `EMAXCONNSESSION` (500) two-writer topology.

Three coupled defects on the pre-flight path (all confirmed in code):

1. **Unbounded scan.** Each paginated hook loops a GraphQL cursor (`while :;`) to exhaustion with
   **no page ceiling and no wall-clock budget**. N pages × up to a per-page `--max-time` exceeds the
   outer curl budget (inventory 30s, verify = registry-probe 30s + doublefire 60s).
2. **No server-side kill + orphaned scan ratchets the pool.** adnanh/webhook v2.8.2 has **no
   `command-timeout`**; when the outer curl times out (→ `HTTP 000`) the hook keeps scanning
   server-side, orphaned, still holding its inngest→Postgres connections. Combined with the ADR-105
   §Precondition two-writer idle plateau, those pinned connections push the shared 30-slot pool to
   `EMAXCONNSESSION` — the next run returns `HTTP 500`, a restart clears it, the cycle repeats.
3. **The surface is observability-dark on the failure path.** The only telemetry
   (`logger -t inngest-inventory`) fired **only** at the end of the success path; a hang never reached
   it (the reported "0 hits over 40m"). The occurrence was undiagnosable off-box
   (`hr-observability-as-plan-quality-gate`).

The mechanism of the pool ratchet is the loop **continuing to issue per-page queries after the client
has abandoned the request** (the outer curl timed out) — not connections being "pinned" by the webhook.
Halting that loop is what releases the load.

Brand-survival threshold: `single-user incident` — the load-bearing guard is the **inventory
completeness invariant**: the bounded/cost-reduced scan MUST NOT drop any armed `reminder.scheduled`
or distinct event name the current unbounded scan captures. A narrowed window that dropped a far-future
armed reminder would make the cutover before/after diff go false-clean and silently lose a scheduled
reminder — an irreversible per-user brand hit.

## Decision

The cutover pre-flight hooks MUST bound scan **duration/cost** (in addition to ADR-105's connection
**footprint** cap), MUST be **abandon-safe**, and MUST emit an **in-surface marker** on start/timeout.

1. **Wall-clock deadline (sum-bounded).** Each paginated scan captures a monotonic start (`date +%s`
   delta — precedent `ci-deploy.sh:1524-1535`; the repo never uses `SECONDS`) at run entry, before any
   network call, and enforces an env-seam deadline `PREFLIGHT_DEADLINE_S` (default inventory 22s,
   doublefire 50s). The real invariant is the **sum bound** `in_script_deadline + per_page ≤ outer_curl`,
   NOT the ordering `per_page ≤ deadline < outer`: each page's curl is clamped to the **remaining
   budget** (`--max-time = DEADLINE_S − elapsed`, floored ≥1) so no in-flight page can overshoot the
   outer curl (30s inventory / 60s verify). `--connect-timeout` bounds a TCP-connect stall on every
   per-page curl, including the single-shot registry-probe.
2. **Page ceiling.** An env-overridable `MAX_PAGES` guard, gated as "about to fetch page > MAX_PAGES
   **while `hasNextPage=true`**" (a corpus that exactly fits breaks clean, never false-aborts).
3. **Abandon-safety via ONE shared loud-abort helper.** The deadline exit, the ceiling exit, and the
   existing empty-`endCursor` / malformed-GraphQL guards ALL route through one helper that emits a
   `SOLEUR_INNGEST_PREFLIGHT_TIMEOUT` marker then `exit 1` — **never `break`** (a `break` falls through
   to the emit and produces a truncated well-formed HTTP-200 body = the #6218 false-clean class). The
   non-zero exit maps to a webhook non-200 (`hooks.json.tmpl` `include-command-output-in-response-on-error`),
   so the workflow's `CODE!=200` cause-branch surfaces the real timeout cause. `exit 1` fires the EXIT
   trap → the `mktemp` spool is cleaned; halting the loop releases the inngest→Postgres connections.
4. **Cost reduction — completeness BY CONSTRUCTION.** The window is **never narrowed** (the `from`
   filter bounds `receivedAt`, not fire-time, so narrowing silently drops far-future armed reminders).
   - **armed_reminders** is enumerated by a DEDICATED `eventNames:["reminder.scheduled"]` full-window
     query (small, page-ceiling-immune; precedent `inngest-enumerate-reminders.sh:82`).
   - **event_names** keeps the all-events distinct scan; the ONLY cost lever is raising `PAGE_SIZE`
     (lossless round-trip cut). If the corpus does not fit even at the raised size it aborts LOUD.
   - **doublefire** is bounded by a `functionIDs` filter + the page ceiling, NOT a narrowed time
     window: the probe window MUST stay ⊇ the operator cutover window (`FROM ≤ cutover_instant −
     2×max_cron_period`) — a narrower window feeds false "missed ticks" into the enumeration
     (`cutover-inngest.yml:704-743`) → operator re-fire → **double-fire**, the exact harm the cutover
     prevents. This is a SEPARATE invariant from the inventory "superset" one.
5. **In-surface marker (journald-only).** `SOLEUR_INNGEST_PREFLIGHT_{START,DONE,TIMEOUT}` via
   `logger -t "$LOG_TAG"` only (the hook's stdout IS the pure-JSON webhook body, #5503 — a stdout
   marker would corrupt the parse). START is the literal first line, before any network call, so an
   absence-of-START unambiguously means transport/host-down. TIMEOUT carries a curl-exit class
   (`pages_timed_out`, `last_curl_exit`) so `{deadline_hit, pages_scanned, pages_timed_out,
   last_curl_exit}` splits slow-scan vs pool-pressure-stall (curl exit 28, the `HTTP 000` shape) vs
   host-unreachable (no START) in one event. The three tags (`inngest-inventory`,
   `inngest-doublefire-probe`, `inngest-registry-probe`) are already in Vector's `host_scripts_journald`
   allowlist (`vector.toml:134`/`:144`/`:145`) — no allowlist edit. Purity (#5503): enum/count/id only;
   a raw GraphQL `errors[].message` is mapped to an enum (`reason=gql_error`), never emitted verbatim —
   the purity test is the SOLE guard (Vector does not scrub `postgres://<user>:<pass>@<host>/db`).
6. **Bounded transport retry (tightly scoped).** The op=inventory curl and the op=verify **transport**
   curls (registry-probe, doublefire) are wrapped in a 2-attempt retry (~5s gap, fail-closed): now that
   attempt-1 is abandon-safe it releases connections, so a transient two-writer 500 clears on attempt-2.
   It wraps ONLY the transport failure — NOT the `registry_empty` precondition verdict, NOT the
   op=execute DI-C3 gate (`:565`), NOT the health probe (`:83`, which has its own retry).
7. **NOT chosen: a `/usr/bin/timeout` hooks.json wrapper.** See Alternatives.

## Considered Options

- **(chosen) In-script `date +%s`-delta deadline + page ceiling + abandon-safe loud-abort + journald
  marker + bounded transport retry.** Fixes the `HTTP 000` hang and breaks the orphan-scan ratchet
  without touching the pool topology or executing the cutover. The in-script deadline is sufficient and
  abandon-safe because it halts the loop that *drives* the PG load.
- **`/usr/bin/timeout` hard-kill wrapper in `hooks.json.tmpl`.** Rejected — the adnanh/webhook static-arg
  form is unverified (zero repo precedent); it only guards non-loop hangs (already `--max-time`-bounded),
  its SIGTERM can fire mid-`logger` (losing the marker) or bypass the EXIT trap (leaking the `mktemp`
  spool), and it widens blast radius (`inngest-inventory` is also the `scheduled-inngest-health.yml`
  probe endpoint). `hooks.json.tmpl` is NOT edited.
- **Convert the hooks to async (202 + fork + poll `/hooks/*-status`).** Rejected as primary — it
  re-architects the synchronous `op=inventory`/`op=verify` response contract, a large blast radius for a
  pre-flight fix. Reconsider only if the `event_names` all-events scan cannot fit the budget even at the
  raised `PAGE_SIZE`.
- **Narrow the eventsV2 window to cut cost.** Rejected — the `from` filter bounds `receivedAt`, not
  fire-time, so it silently drops far-future armed reminders (the single-user-incident vector). The cost
  lever is a raised `PAGE_SIZE` + a dedicated reminder query, never a window narrow.
- **Only raise the outer curl `--max-time`.** Rejected — a longer client budget still hangs on an
  unbounded scan and still orphans the server-side scan (worsens the ratchet). Bounding must be
  server-side.

## Consequences

- The three host-script edits ride the existing no-SSH infra-config auto-apply
  (`apply-deploy-pipeline-fix.yml`, `paths:` already list all three). No new host script → no
  TRIGGER_FILES / parity edit (`ship-deploy-pipeline-fix-gate.test.ts` stays green). No unit restart,
  no tag release, no cutover execution.
- **Blast radius is NOT preflight-only.** `inngest-inventory.sh` is also consumed by
  `scheduled-inngest-health.yml:90` (the 15-min durability probe), the op=execute DI-C3 gate
  (`cutover-inngest.yml:565`), and op=rollback (`:807`). The completeness invariant + abandon-safety
  protect those consumers (bounded scan → 200 or LOUD fail, never a truncated false-clean); the health
  probe converts a former silent hang into a clean 200.
- The pre-flight path is now observable off-box: a recurrence self-reports the START/TIMEOUT marker to
  Better Stack (Vector journald pipe, source 2457081) with the discriminator fields.
- `status: adopting` flips to `accepted` after the post-apply `op=inventory` re-run returns HTTP 200
  with a well-formed body and the `SOLEUR_INNGEST_PREFLIGHT_START` marker is queryable in Better Stack.
  A green `op=verify` **JOB** is a post-#6178 concern (see below), NOT a gate on this ADR.

## Relationship to ADR-105 (`amends`, not `supersedes`)

ADR-105 and ADR-106 are **both deployed and orthogonal** — ADR-105 bounds the connection *footprint*
(per-pool cap + idle drain), ADR-106 bounds the scan *duration/cost* + adds abandon-safety and the
marker. `supersedes` would be wrong: the ADR-105 pool cap stays in force. This ADR does NOT re-derive
the two-writer scoping — that is fully recorded in **ADR-105 §"Precondition — exactly ONE prod-pool
writer"** (`ADR-105:109-143`): the residual `HTTP 500` is the topological contention of two co-located
writers on one 30-slot pool, deferred to #6178 (durable single-writer collapse) and gated by the manual
#6230 web-2 quiesce. ADR-106 breaks the *tooling-induced* contribution to that contention (the
orphan-scan ratchet); it does not, and does not claim to, make two writers fit.

## Per-op definition of done (re-scoped)

`op=verify`'s FIRST step is the registry-probe precondition, which hard-requires `registry_empty ==
false` on the dark dedicated host `10.0.1.40` (`cutover-inngest.yml:628-631`). Pre-cutover that host is
empty, so the op=verify **JOB** legitimately exits non-zero there (a verdict, not a transport hang) and
the doublefire sub-probe is never reached. So a green op=verify job **cannot** go green without running
the cutover (forbidden here). The DoD is therefore per-op: **op=inventory returns HTTP 200** (the #6258
verify-close signal) + the op=verify sub-probe transports are bounded/observable (no 000/500), proven by
unit tests; a green op=verify JOB is post-#6178.

## Diagram

**No C4 impact.** A scan-bounding + timeout + log-marker change adds/removes no element, edge, or
`#external` boundary. The `inngest` container, its `inngestPostgres` dedicated-project DB (Supavisor
session pooler `:5432`), and the GitHub-Actions cutover workflow are already modeled (`model.c4`,
`views.c4`, `spec.c4`) — mirrors ADR-105's "No C4 impact" reasoning. `c4-code-syntax.test.ts` +
`c4-render.test.ts` run unchanged.
