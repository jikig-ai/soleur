---
title: Egress audit records are rolled up in Vector, posted to an authenticated app route and stored per workspace, dark until a member can read them
status: adopting
date: 2026-10-15
supersedes: none
issue: 9545
related: [9534, 9601, 10018]
related_adrs: [ADR-278, ADR-286, ADR-052, ADR-281, ADR-038, ADR-043]
tags: [egress, audit-log, vector, privacy, rls, retention, gdpr]
brand_survival_threshold: single-user incident
---

# ADR-288: Egress audit records are rolled up in Vector, posted to an authenticated app route and stored per workspace, dark until a member can read them

## Status

**Adopting.** PR1 (this decision) ships the pipeline dark: nothing reads the table and collection is off for every external
workspace. The status moves to `accepted` when PR2 (member read path and card; see the amendment below, which replaced the read
policy and route with a member RPC) has merged and the owner notice has been out for at least 7 days. The ordinal was verified free against `origin/main` (highest ADR-287) and is re-verified at ship.

## Context

A workspace owner can switch on open-web access for the workspace's agents, but cannot see which hosts those agents contacted.
The egress gateway (ADR-278) already writes one JSON decision line per CONNECT to journald, and Vector ships it to Better Stack
for 90 days of operator-side forensics. Nothing in the product reads it back. Measured on 2026-10-15 (plan Phase 0): in 8 days the
gateway log held 3,434 rows, 3,425 from its own synthetic probe and 9 unauthenticated, so real customer volume is unmeasured.

## Decision

1. **Roll up before the app, not in it.** Vector reads `sources.egress_gw_journald` directly and reduces the decision log into
   15-minute buckets per workspace, host, decision and source host. A per-event insert is the write shape that was 63% of production
   WAL once (PR #5736's single dedup INSERT), and retained raw rows serve no stated user need. Stored: `workspace_id, bucket_start, requested_host,
   decision, source_host, request_count, bytes_out, first_seen, last_seen`. Not stored: resolved IP, client address, duration, any
   user, session or path value (DPIA trigger t7).
2. **Authenticated same-host ingest.** Vector posts closed buckets to `POST /api/internal/egress-audit-ingest` with a bearer token.
   The route requires a loopback `Host`, rejects a request that carries a proxy marker (`CF-Ray`, `CF-Connecting-IP`,
   `Forwarded`, `X-Real-IP`, or an `X-Forwarded-For` chain of more than one hop),
   compares the token in constant time against the current and the previous token (rotation), caps the body, validates with zod
   and bounds `bucket_start` per row; a malformed row is dropped and counted, never a reason to fail its neighbours. The body cap
   is counted in bytes while streaming. No ingress block exists or is possible for `/api/internal/*` (other internal routes are
   public by design), so these checks and the token are the controls. Ruled by the CTO agent.
   **Amendment (R6, review of PR #10349).** The ruling's premise that Vector's request carries no forwarding header is false for
   `X-Forwarded-*`: Next.js adds `x-forwarded-for`, `-host`, `-proto` and `-port` to every request it serves (measured on 16.3.8), so
   rejecting them returned 401 to every legitimate batch. Those four are no longer a proxy signal; the Cloudflare headers
   (added to every proxied request), `Forwarded`, `X-Real-IP` and a multi-hop chain are, and the loopback `Host` plus the bearer
   remain the controls.
3. **One write path.** The route calls `ingest_egress_audit_rollup` (service-role only). It skips and counts unknown, orphaned
   (no member row left), toggle-off and malformed rows and never raises on row CONTENT (it catches only `data_exception` and
   `integrity_constraint_violation`), because an error would make the sink retry the same batch forever; a system fault (lock,
   I/O, permission, schema drift) does raise, so the route answers 5xx, mirrors it and Vector retries. The table's CHECKs close
   `decision` to `allowed | denied | other`, restrict the host to its character set and require an aligned bucket and an ordered
   `first_seen <= last_seen` inside it. A replay that changes nothing does not rewrite the tuple. It
   merges per column with `GREATEST` (`LEAST` for `first_seen`), never `SUM`: a journald cursor replay after a Vector restart can
   re-count entries and an audit log must not overstate. Distinct host rows per workspace and bucket are capped at 500; the
   overflow folds into one `(other)` row.
4. **The flag is evaluated per organisation, after authentication.** `egress-audit-collection` (Flagsmith runtime flag) defaults
   OFF. A Jikigai-owned canary organisation is enabled by a per-org override; external organisations stay off until PR2 ships
   (CTO ruling A). A missing secret or a disabled flag answers 2xx and drops the batch, never 5xx, so the sink's disk buffer does
   not fill. A failed flag evaluation is "off" and is mirrored. `getRuntimeFlag` itself never throws on a Flagsmith outage: it falls
   back to the GLOBAL, role-blind env mirror `FLAG_EGRESS_AUDIT_COLLECTION`. That is the one way a Flagsmith outage could open
   collection for every organisation, so the route refuses to run (2xx, batch dropped, mirrored as `env-fallback-on`) when
   `NODE_ENV=production` and that variable is `1`: collection is on only where Flagsmith positively says so (CTO ruling R6-G).
5. **Attribution is hardened at the gateway and again in Vector.** Squid's `%un` logs the presented username even when
   authentication fails (measured on 6.13), so a bad-credential attempt naming another workspace id would otherwise be attributed
   to that workspace. The log format gains the HTTP status as its last field (a host that injects JSON keys cannot override it);
   Vector keeps only rows whose status is on a positive allowlist (200, 403, 502, 503, 504; so 407, an aborted connection's 000 and
   an older gateway's missing status all fail closed), requires the workspace to be a UUID (the gateway probe username and the
   unauthenticated `-` drop out and write nothing), allowlists host characters and normalises the decision to
   `allowed | denied | other`.
6. **Memory is bounded by a cap, not by hope.** `reduce` holds about 3.7 KB per key. A `throttle` caps 1,000 events per workspace
   per 15 minutes upstream of it, and a second keyless `throttle` bounds the TOTAL (the per-workspace cap alone does not bound memory:
   19 workspaces at the cap exceed the unit limit). A Vector throttle is a leaky bucket, not a fixed window (measured on 0.43.1: it
   admits `threshold` at once and refills `threshold` per window, so up to twice the threshold can be alive at once), so the global
   threshold is 5,000 per 900 s, bounding the reduce keys at about 10,000: the ten-workspace case measured below. The cap is shared with
   workspaces whose flag is off, because the app gates after Vector; a busy non-enabled tenant can use the canary's budget, which the
   `SOLEUR_EGRESS_AUDIT_THROTTLED_GLOBAL` marker makes visible. The per-workspace cap has the same shape (up to about 2,000 events in a
   window), which the global cap bounds in aggregate. Measured: one workspace with 100,000 unique hosts peaks at 426 MiB uncapped; ten workspaces
   flooding at once peak at 162 MiB with this cap and 270 MiB at 2,000 (the unit's `MemoryMax` is 256M). Discards are exported as
   Vector's per-key discard counter and turned into one `SOLEUR_EGRESS_AUDIT_THROTTLED` marker line per change in Better Stack.
7. **Retention and erasure.** 30 days, hard-deleted daily by a `pg_cron` job on `last_seen`, plus `ON DELETE CASCADE` from the
   workspace. The cascade does not fire on account erasure (the saga keeps the orphan workspace row, migration 065), so account
   deletion calls `erase_egress_audit_rollup` as a required step (5.15) before deleting the auth user. The step runs after the
   member rows are removed and the RPC erases only a workspace with no member left, so it cannot over-erase a team workspace; the
   ingest RPC skips such an orphan, so a late buffered bucket cannot re-create erased history. Both decisions are taken under a
   `FOR SHARE` lock on the member rows, so the saga's member delete waits for an in-flight ingest and the erase that follows removes
   what it wrote (CTO ruling R6-D). An explicit data-subject request made while the account stays open goes through
   `erase_egress_audit_rollup_for_requester(workspace, requester)`, which deletes only when the requester is the sole member and refuses
   while web access is on for the workspace (buckets already in Vector's reduce or buffer would re-create the history; the runbook
   says to switch web access off and wait 20 minutes). Ingest and the saga can deadlock on the member-row locks (40P01); ingest
   processes rows in workspace order and either side retries, which is rare and only reachable once collection is on. Ingest counts
   an orphaned workspace as `skipped_orphan`, separately from `skipped_unknown`.
8. **Nothing is readable in PR1.** The table has RLS enabled, no policy and every privilege revoked from `anon` and
   `authenticated`. *(Superseded 2026-10-26 by the PR2 amendment below: no member `SELECT` policy lands; members read through one RPC.)*
9. **Counts are best-effort lower bounds; the host set is exact only below the cap.** A restart loses partial buckets and the cap
   discards events above 1,000 per workspace per window. Any later user-facing copy must say so.

## Write volume

Estimated at 430-540 bytes of WAL per row. At 80,000 rows a day that is about 40 MB a day of record WAL; the worst case with a
full-page image on every write (the primary key leads with the random workspace uuid, so inserts scatter across the index) is about
640 MB a day; the daily purge adds about 7.5 MB a day. These are estimates: after the canary has run, read
`pg_stat_statements.wal_bytes` for `ingest_egress_audit_rollup` and replace them with the measurement.

## Delivery

The bearer token is a `random_id` plus a `doppler_secret` in `soleur/prd` (`apps/web-platform/infra/egress-audit.tf`), read by the
app and by Vector at process start (Vector already runs under `doppler run --config prd`). The shared `vector.toml` reads it only
as the default-value form, because the same file is rendered onto the dedicated inngest host, which has no gateway and no copy of the
secret; Vector interpolates inside comments too, so the strict form must not appear anywhere in the file (a structural test pins
this). Merging triggers `apply-web-platform-infra.yml`: the secret is created in the main stage, then the SSH stage redelivers
`squid.conf` to the gateways (a container restart: seconds of agent-egress downtime) and `vector.toml` to the web hosts
(`journald_persistent{,_web2}`, a restart with journald cursor resume, no log gap). Until the route is deployed the sink's bounded
retries drop events, which loses nothing while the pipeline is dark.

**Ordering.** The app container reads `EGRESS_AUDIT_INGEST_TOKEN` at start (`ci-deploy.sh` passes secrets when the container is
created), so the container must be restarted after the Doppler secret exists; until then the route answers 202 with the batch
dropped (`secret-unset`). **Rollback.** Revert the app change before running `162_workspace_egress_audit_rollup.down.sql`: the
account-delete saga calls `erase_egress_audit_rollup`, and a missing function aborts every account deletion at step 5.15.

## Does not defend

- **App-environment compromise.** Anything that can read the app environment, or the Doppler `prd` config, holds the ingest token and
  can forge rows for any workspace that has collection enabled. The token authenticates a same-host hop; it is not an attestation.
- **A local process that can bind or sniff loopback on the web host.** The hop is plain HTTP to `127.0.0.1` (encryption-posture
  exception, expires 2027-01-13).
- **Overstatement of completeness.** Counts and the host set are lower bounds (decision 9). This is not a complete forensic record;
  the 90-day Better Stack copy remains the operator-side record.
- **Detection of a full disk buffer.** Vector's internal logs reach no sink today. A stalled pipeline would be detected by the
  freshness probe (`scripts/egress-audit-retention-check.sh`), not by a Vector-side alert. **The probe is not scheduled anywhere
  yet**, so in PR1 it is a manual check; scheduling it (with `EGRESS_AUDIT_EXPECT_COLLECTION=1` and the canary workspace list) is a
  precondition of enabling collection for any workspace, listed unchecked in the enable runbook
  (`knowledge-base/engineering/operations/runbooks/egress-audit-enable.md`) and tracked on #9545.
- **A flooding workspace's later hosts.** Above the cap, discarded events can drop hosts; the marker line says it happened.
- **Buffered events from before a toggle-off.** The toggle is read at ingest time, so they are dropped (errs toward minimization).
  Existing rows are not purged on toggle-off (CTO ruling C, D); they age out within 30 days or on an erasure request.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| App reads Better Stack directly | Needs a workspace-unscopable ClickHouse read credential on the app runtime; the log-query runbook and `cron-inngest-config-drift.ts` keep that credential off the app deliberately. |
| Per-event spool table | Per-event inserts were 63% of production WAL once (PR #5736); retained raw rows serve no stated need. |
| Per-row HMAC with a replay window | Same trust root as a bearer token (anything that reads the app environment holds the key), `GREATEST` already makes replays harmless, and a replay window defeats the disk buffer after an app outage. Reversed by the CTO on plan review. |
| Member `SELECT` policy in PR1 | A readable table is a viewer in fact and triggers the DPIA t6 re-screen at PR1. *Not shipped in PR2 either: replaced by the member RPC (amendment 2026-10-26).* |
| New Inngest prune function | Adds a Sentry cron monitor, which the two-PR monitor rule forbids routing in the PR that creates it; `pg_cron` retention sweeps already exist. |
| Global flag read at the top of the route | Cannot see a per-org override, so the canary would be dropped or every external organisation enabled. Replaced by per-org evaluation after authentication. |
| Cloudflare rule blocking the ingest path | A Terraform change for little gain: the other internal routes must stay public and the token is the real control. |
| `reroute_dropped` on the throttle | Not available in Vector 0.43.1 (rejected at config load); the per-key discard counter is used instead. |

## Consequences

- A new `workspace_egress_audit_rollup` table, four service-role functions and one daily `pg_cron` job; a new internal route with an
  exact `PUBLIC_PATHS` entry; one runtime flag; one Doppler secret.
- Vector gains a rollup pipeline in the shared file. `vector validate --no-environment` does not compile VRL, so the new
  `validate-vector-config.yml` step runs `vector test` against the real file (23 tests, mutation-checked).
- Enabling collection in production is an operator action and is not part of this PR: PR2 must have shipped, the toggle copy and the
  owner notice must be live, and the notice must have been out for at least 7 days (CTO rulings A and B). The CLO-reviewed public
  wording lands as the last commits of the PR1 branch and gates enabling, not merging.
- The forced-error acceptance of ADR-281's `image_cve_scan` monitor is corrected in the same PR (the workflow fired with an email
  action; mailbox receipt was unobserved).

## Amendment 2026-10-26 (#9545 PR2): the member read path is an RPC, not a policy

*Its "ONE function" and "Fixed 30-day window" statements are superseded in part by the 2026-11-03 amendment below.*

**Decision.** Members read the rollup through ONE `SECURITY DEFINER` function, `get_egress_audit_summary(p_workspace_id, p_limit,
p_decision)` (migration 177). There is **no member `SELECT` policy and no table grant**: a direct `.from(table).select()` stays a
permission error, so the table is still an excluded, zero-policy target in the RLS fuzz harness. This corrects the PR1 text above
that said a policy "lands in PR2" (migration 162 is immutable on `main`; its header and table comment are left as written).

- **Authorization is the function's.** First statement: `auth.uid() IS NULL OR NOT is_workspace_member(p_workspace_id, auth.uid())`
  raises SQLSTATE `42501` with a constant message that differs from the engine's grant-denial text. Pending invitees and removed
  members are not members. Every aggregate carries `workspace_id = p_workspace_id`: a definer bypasses RLS, so that predicate is the
  tenant boundary once the gate passes. `EXECUTE` is revoked from PUBLIC, `anon`, `authenticated` and `service_role`, then granted to
  `authenticated` only.
- **Deliberately not gated on the collection flag or on `web_egress`.** The data exists only where collection is on, and history must
  stay readable after the toggle is switched off (ruling D: switching off stops new records and deletes nothing). The flag decides
  only which empty state the view shows and whether the enable dialog may say hosts are recorded; the three readers share
  `server/egress-audit-collection.ts`.
- **No HTTP route.** A server-rendered page calls the RPC through the caller's cookie client (CTO ruling 2026-10-26, reversing the
  earlier thin-route decision: nothing consumes a route). The workspace id comes only from the fail-loud `readWorkspaceIdFromDb`.
- **No `statement_timeout` clause.** A function-level setting does not re-arm the already-running outer statement (proved on
  Postgres 17); the bound is the role timeout, `p_limit` at most 500, the primary-key range scan and the caller's abort signal.
- **Shape.** Fixed 30-day window on `last_seen` (the daily purge keys on it), bounded above by `now()`. Overflow (`'(other)'`) is a
  separate typed field summed across buckets and source hosts, never a host row; `source_host` is never exposed. `p_limit = 0`
  returns only the last-request probe (the card hint).
- **Verified against the repo.** The `decision` column has a `CHECK IN ('allowed','denied','other')`; `other` is shown as a third
  visible state, never folded into Blocked. Overflow counts merge with `GREATEST` at ingest, so they are very loose lower bounds and
  the view always says "at least".

### Read-path rulings (review round, 2026-10-26)

- **Second gate statement.** After the membership check the function refuses a revoked-but-unexpired JWT of a current member
  (`is_jti_denied_from_jwt()`, mirroring migration 127): SQLSTATE `42501`, message `'egress audit: token denied'`. A definer bypasses
  the RESTRICTIVE jti policies, so the denylist has to be restated in the body.
- **Cost shape.** The page query is a top-N rewrite (`ORDER BY last_seen DESC LIMIT p_limit + 1` over real-host groups), the function
  pins `SET plan_cache_mode = force_custom_plan` (after five executions in one session plpgsql would flip to a generic plan), and sums
  are clamped to 9007199254740991 (JS `MAX_SAFE_INTEGER`). `p_limit` stays clamped to 0..500; it is not the cost driver.
- **Loader.** `forbidden` only when the 42501 message starts with the constant prefix `egress audit:` and a space; any other 42501 (an engine "permission denied for
  function", a lost EXECUTE grant) is a paged `rpc_error` with `pg_code=42501`. A Flagsmith outage maps to `collection: "unknown"`
  through `readRuntimeFlagDetailed` / `readEgressAuditCollectionState`; ingest stays boolean. The op registry gains
  `hint_workspace_read` and `web_access_read` (unpaged) and every mirror carries a sanitised `pg_code` tag. Bounds: page pointer
  2000 ms, collection and web-access reads 1500 ms each after the RPC; card pointer 600 ms, org 800 ms, hint 800 ms, overall 1200 ms.
  Independent reads are not started before the RPC (rejected: they would run before the caller is authorised). Only the Scope Grants
  page guards against a workspace mismatch (it forces the card's collection state to `unknown`); the destination page resolves the
  workspace once, so it has no second read to compare.
- **Agent prompt.** `WEB_EGRESS_PROMPT_ADDENDUM` no longer claims "every decision is logged with workspace attribution"; it says
  requests may be recorded best-effort and points to the audit view.
- **Page caching.** The page response carries `Cache-Control: no-store`.

### Accepted residuals (read path)

1. **Adversarial worst case.** About 1.44M (host, decision) groups for one workspace took 5.4-6.3 s on the local database after the rewrite (an earlier note here said about 3.5 s; the AC3a measurement in the plan supersedes it),
   leaving only about 1.7-2.6 s of headroom against the 8 s role timeout. A slower production host can push this case over the timeout and turn
   the accepted fail-closed outcome into routine `rpc_timeout` pages. Accepted as
   a documented limit: collection is off for external organisations (gated by #11237) and the failure mode is fail-closed
   (`unavailable`, never a wrong answer). A per-workspace distinct-host cap and fold policy at ingest (PR1 scope, a new migration
   because 162 is immutable) and a limiter for member-callable aggregation RPCs are **#11237 enablement blockers**.
2. **Writer-side evasion.** A prompt-injected agent can push a host out of the view by contacting more than 200 decoy hosts more
   recently, or more than 500 in one bucket (folded into the nameless `(other)` row at ingest). This is a transparency log for
   members, **not** a forensic or exfiltration-detection control; the overflow count is the residual signal. Ordering and filters were
   rejected as mitigations because the attacker controls denied decoys too.
3. **Direct member RPC loops.** A member can call the RPC in a loop from their own client; it is bounded only by the
   `authenticated` role's 8 s `statement_timeout` and per-workspace scope. The `p_limit` clamp stays 500 because it is not the cost driver.
4. **Router Cache window.** The 30 s Router Cache (`staleTimes.dynamic`, ADR-067) lets a just-removed member's already-open session
   re-display a payload fetched earlier.
5. **Agent-readable surface parity gap.** The RPC is callable by any authenticated member client but no agent/MCP tool exists. A
   follow-up issue (#11258) tracks it.
   *Superseded in part by the 2026-11-04 amendment below: the parity gap is now a recorded deferral with a pinned absence and re-evaluation triggers, not an open-ended gap; #11258 stays open.*

The status stays **Adopting**: it moves to `accepted` after PR2 has merged and the owner notice has been out for at least 7 days (an
enablement step; the flag flip is tracked in #11237, not part of PR2).

## Amendment 2026-11-03 (#11238): the member read gains a window, in a second function

**Decision.** Members read the rollup through TWO `SECURITY DEFINER` functions with one contract:

- `get_egress_audit_summary(p_workspace_id, p_limit, p_decision)` (migration 177): fixed 30-day window, unchanged. It stays for the
  Scope Grants card hint (`p_limit = 0`) and for the previous app image while a deploy is in flight.
- `get_egress_audit_window_summary(p_workspace_id, p_limit, p_decision, p_window)` (migration 183): `p_window` is one of `24h`, `7d`,
  `30d`, with no argument defaults. The destination page always calls this one, including for the default 30 days, with no fallback
  to the 177 function on error.

This supersedes the 2026-10-26 amendment's "ONE `SECURITY DEFINER` function" and "Fixed 30-day window" wording. Everything else in that
amendment holds for both functions: membership check first, jti denylist second, then argument validation; the
`workspace_id = p_workspace_id` predicate on every read; `EXECUTE` for `authenticated` only; no member `SELECT` policy and no table grant.

- **Window.** Derived after the two authz checks and the `p_decision` check, through a `CASE` map to a literal interval (never cast from
  caller text, no `ELSE`), so `NULL` and any unknown value raise SQLSTATE `22023` with a message that starts with the `egress audit:` prefix (the constant `RPC_DENIAL_PREFIX`, which ends in one space).
  Bounded above by `now()`; the `last_seen` predicate decides inclusion. The 15-minute `bucket_start` slack stays a scan aid, so a
  bucket that began before the window start but whose `last_seen` falls inside it is counted whole: the view says "about the last N".
- **Retention is unchanged.** A shorter window is a narrower read of the same stored rows; the purge still keys on `last_seen` at 30 days.
- **Why a distinct name and not a 4-argument overload.** The runtime RLS fuzz coverage gates assert that no authenticated-executable
  definer function is overloaded (both gates key on the `proname(args)` composite; AC7 is the anon-reachability gate, AC8 the authenticated-reachability and overload gate); ADR-112's
  static allowlist tier accepts an overload name collision as a residual and does not assert it. A distinct name avoids rewriting a
  security-gate harness and any named-argument ambiguity in PostgREST.
- **Why the body is duplicated and the 177 function is not turned into a wrapper.** Migration 177 is immutable and the previous image
  calls it. Drift between the two bodies is capped by a text-parity guard in the default suite
  (`test/supabase-migrations/183-egress-audit-window-summary.test.ts`, which names the only permitted differences) and a live parity
  check in the gated RLS fuzz suite.
- **Retirement path.** The card's "requests in the last 24 hours" count is a later PR on #11238. That PR must either move the card to the
  183 function or add a separate count-only function. Retiring the 177 function is TWO steps, never one change: migrations run before
  the app image, so a migration that drops it while the previous image's card still calls it would fault the card hint for the whole
  rollout. First ship an image whose card no longer calls 177; only a later migration (a new `DROP FUNCTION`, never an edit of 177)
  drops it, together with the 177-function rows of `supabase/verify/177_egress_audit_summary_rpc.sql` (its two `egress_rollup_*` table rows
  stay: they assert the rollup tables, not the function), the runbook's 177 lost-grant query, the 183 text-parity test and the loader test
  that pins the card probe's argument object (and AC8's expectations). It must NOT add a third copy of the body: if
  a third reader is ever needed, extract the shared aggregation into a non-granted `STABLE` helper first. A default-suite test in
  `test/supabase-migrations/183-egress-audit-window-summary.test.ts` pins, as a text heuristic over the migration files (it cannot see a
  grant made outside migrations), the set of member-readable readers of the rollup table to exactly migrations 177 and 183, so a third reader fails there until this paragraph is revisited. This paragraph is the record; no
  separate issue.
- **Skew.** Migration 183 is applied before the app image that calls it. Until PostgREST reloads its schema cache a page load can fault
  with `PGRST202` (a paged `rpc_error`); the card keeps working because it uses the 177 function.

The status stays **Adopting**.

## Amendment 2026-11-04 (#11258): the agent-readable surface stays deferred, and its absence is pinned

**Decision.** Ruled by the CTO agent on 2026-11-04. No agent-exposed surface over the egress audit summary is built now, and no
migration, grant, route or tool changes. Per repository source, no agent tool file names either function, the loader or the rollup
table, and read-only platform tools have not been promoted to the router, so neither of the first two re-evaluation triggers below
has occurred; the third is flag state, which git cannot show and which was not re-measured for this amendment (collection stays
operator-held). Reach by capability is a separate matter from naming: see "What the pin does not see". This amendment supersedes
accepted residual 5 in part (marked in place): the gap is now a recorded deferral with a pinned absence and triggers. The other
residuals are unchanged.

- **Deliberate exception to AP-004 (agent-user parity).** A member reads the workspace aggregate in Scope Grants. An agent reads
  nothing and is told to point the member to that page (`WEB_EGRESS_PROMPT_ADDENDUM`), so the capability it lacks is the
  cross-session aggregate and the retention state. The exception is re-reviewed on the earliest trigger below; parity is restored
  when the constraints below are met.
- **State on 2026-11-04.** Per migrations 177 and 183, `EXECUTE` on the two member-read functions is granted to `authenticated` and
  revoked from `anon` and `service_role`; the grant state is re-asserted at every deploy by `supabase/verify/177_egress_audit_summary_rpc.sql`
  and `supabase/verify/183_egress_audit_window_summary.sql`. On this date a scan of non-test source under `apps/web-platform` found
  the two function names in three files only (`server/egress-audit-read.ts`, the only caller; `lib/egress-audit/summary.ts` and
  `server/dsar-export-allowlist.ts`, both comments), the loader imported only by the two server-rendered Scope Grants pages, and
  the rollup table named only in the erasure saga, the ingest and the DSAR allowlist comment. It found no egress-audit reference in
  any file that builds, registers or classifies an agent tool, in any tier-map key, or in the router's base tool list. The router
  registers the narrate and summarize tools, behind a flag the C4 editing tool, and for a CRM new-lead chat the `crm_*` tools;
  `readCcMcpAllowlist` throws on a denylisted or approval-required short name and otherwise returns `{}` in its current phase
  (#3722). The leader-surface runner assembles its platform tools inline from the `server/**/*-tool(s).ts` builders; none of them
  names egress audit data.
- **What the pin does not see.** `apps/web-platform/test/egress-audit-agent-surface-absence.test.ts` runs in the `unit` project
  on any diff that touches `apps/web-platform`; a diff confined to `plugins/`, `scripts/` or `.github/` never runs it, and
  activating per-suite test selection must declare the scanned tree as an input of the suite or mark it always-run. It scans every
  JavaScript and TypeScript source file (`.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.mts`, `.cts`) in the app tree except
  dependencies, build output and reports, tests, browser tests, static assets, docs, SQL and CI config, for the two function names,
  the loader import, the rollup table name, and any egress-audit mention in a file that is a tool builder by filename or that
  registers tools or imports the Agent SDK (a mention check, not a reachability check). It refuses symlinks and fails if production
  code imports a test-named module or a module in an excluded directory (test-named files themselves are not scanned). Two runtime
  assertions cover the tier-map keys and the router's base list (narrate and summarize only). It does not see: a name assembled at
  runtime; a read through a client obtained from a helper (`getFreshTenantClient`, `mintFounderJwt`, `createServiceClient`) in a
  file that spells none of the names, including a tool builder that already holds a service-role client; the per-dispatch C4 and
  CRM tool names and the leader runner's inline tool list (held by the text scan only); non-JavaScript files in the app tree and
  code outside it, including the retention probe script; a plugin-supplied MCP server, plugin skills and agents, or plugin code
  executed in-process by a server-side cron job; an environment-supplied `CC_MCP_ALLOWLIST` value; a database-side change; a
  deployed configuration; and an operator-run agent holding database credentials. The compensating control for a new
  service-role importer is `apps/web-platform/scripts/service-role-allowlist-gate.sh` with the CODEOWNERS pin on
  `apps/web-platform/.service-role-allowlist`; it checks the identifiers `createServiceClient` and `getServiceClient` per file in
  tracked `server/` and `lib/` `.ts` files, so `app/` routes, hooks, scripts, clients built directly from a key, and a new table
  read in a file already on the allowlist are outside it. The pin is designed to fail first for the spellings it scans; it is not
  a proof that no surface exists.
- **Threat model for a future surface.** An agent acting for a member would hold that member's authority, which both functions
  scope to the whole workspace rather than to the calling session. Every current member already sees that aggregate in the view;
  what changes is that an agent would exercise the read without the member's per-read intent, and could read hosts contacted by
  other sessions (the rollup carries no member or session field, so nothing is attributed). Destination hosts are chosen by the
  requesting agent or by any page it fetched and are retained for about 30 days, so a returned host string is a persistent
  second-order injection channel across sessions; migration 162's charset check removes spaces and markup but is a floor, not a
  mitigation. A compromised agent could also use repeated reads as an allow/deny oracle for gateway policy by host, to probe what
  the log retains (residual 2), or to tune a decoy flood against the overflow signal. The log remains a transparency log for
  members, not a forensic or exfiltration-detection control, and this amendment does not change that.
- **Constraints any future agent surface must meet.**
  - Member user-JWT client only. `service_role` cannot execute the functions but holds full privilege on the rollup table
    (migration 174) and bypasses membership scoping, so there is also no direct table read by any client. A new service-role
    importer in `server/` or `lib/` needs a `.service-role-allowlist` line and CODEOWNERS approval; that gate's scope is stated above.
  - Calls only the existing functions: no generic SQL tool, no call-any-RPC tool, no new grant. The workspace id is bound by
    closure from the server-resolved current workspace and is never a tool argument.
  - Read-only and aggregate-only: no `source_host`, no per-request rows, only the windows the function already accepts, a small
    fixed row and byte cap. Hosts reach the model either not at all or as fenced, length-capped, grammar-checked data; the overflow
    signal is withheld from the agent or coarsened.
  - Output carries no time finer than the date and no persisted relative age (extending DPIA addendum C7, which assumes a view that
    persists nothing), or the surface returns counts only.
    Tool results enter the conversation transcript, which retention and erasure of the rollup do not reach, so persistence of any
    returned value beyond the 30-day horizon (C2, 12.6) is a question for the legal review, not a given.
  - Scope: the rollup has no session or member key, so per-session filtering is impossible. Cross-session visibility through an
    agent is not resolved by any constraint here. The surface must reach exactly the reader set of the view (current members of the
    workspace, equally: DPIA addendum C5); any narrower set, or any consent mechanism, is decided in legal review.
  - Rate-limited. Any record of the agent's own reads must not add a member or session field to the rollup or the function output
    (t7). A record keyed to a member or session, including one visible only to that member, is a per-member or per-session "who"
    view: a full DPIA, not a re-screen, and it contradicts the C6 copy "no member or session is recorded" unless that copy changes
    (DPIA addendum 12.5, 12.6). Its retention, erasure and DSAR treatment are specified in the same PR.
  - Tiered `gated` explicitly in the same PR, with an approval classification (ADR-305, ADR-309). This departs from the
    auto-approved read-only RPC tools because the record is something an injected agent could use for evasion; a review card does not
    address output-borne injection, so the output constraints above still apply.
  - Legal and security review before it merges, including the DPIA addendum 12.6 re-screen (t6, t7) with C1 to C7 re-confirmed; the
    wording of any changed member disclosure (C6) is prepared and reviewed by the CLO and signed off by the human operator at
    flag-on, with the pre-flip publication-order check (DPIA addendum 13.4). The absence test,
    its expected sets and this amendment are updated in the same PR.
- **Re-evaluation triggers (first to occur).** The CTO ruling holder re-evaluates, with the CLO for any DPIA re-screen point, and the
  human operator signs off any resulting amendment; the output is a dated amendment here or a closed #11258. No automated prompt
  exists for triggers 2 and 3: the #3722 promotion and the operator-held flag flip are the moments to re-read this amendment.
  (1) A change adds an agent tool or MCP server entry in repository source that names either function, the loader or the rollup
  table (a naming trigger; the absence test is designed to fail first and points here). A populated `CC_MCP_ALLOWLIST` outcome is
  not seen by the test and is held by trigger 2. (2) Read-only platform tools are promoted to the Concierge router (#3722); the test
  does not detect this, review does. (3) The first external-organization enablement of egress audit collection, which stays
  operator-held; moving the rollup table into the DSAR allowlist is a second member read path and a DPIA 12.6 re-screen point.
  Until one occurs, #11258 stays open and no agent-readable surface is built.
- **Expected sets.** They live in the test (`EXPECTED_NAME_FILES`, `EXPECTED_TABLE_FILES`, `EXPECTED_LOADER_IMPORTERS`,
  `EXPECTED_EXCLUDED_DIR_IMPORTERS`), each entry with its reason, so this record cannot drift from them. The DSAR allowlist entry
  is a comment and may legitimately disappear when the table moves into the allowlist; edit the set in that PR.
- **Alternatives considered.** Building the surface now: rejected, no consumer exists and collection is off for external
  organisations (flag state not re-measured here). A prose-only record with no pin: rejected, member user-JWT clients and an
  allowlisted service-role client already exist in the platform tool files.

The status stays **Adopting**.
