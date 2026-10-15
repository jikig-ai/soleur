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
workspace. The status moves to `accepted` when PR2 (member read policy, read route, card) has merged and the owner notice has been
out for at least 7 days. The ordinal was verified free against `origin/main` (highest ADR-287) and is re-verified at ship.

## Context

A workspace owner can switch on open-web access for the workspace's agents, but cannot see which hosts those agents contacted.
The egress gateway (ADR-278) already writes one JSON decision line per CONNECT to journald, and Vector ships it to Better Stack
for 90 days of operator-side forensics. Nothing in the product reads it back. Measured on 2026-10-15 (plan Phase 0): in 8 days the
gateway log held 3,434 rows, 3,425 from its own synthetic probe and 9 unauthenticated, so real customer volume is unmeasured.

## Decision

1. **Roll up before the app, not in it.** Vector reads `sources.egress_gw_journald` directly and reduces the decision log into
   15-minute buckets per workspace, host, decision and source host. Per-event inserts are the write shape that was 63% of production
   WAL once (PR #5736), and retained raw rows serve no stated user need. Stored: `workspace_id, bucket_start, requested_host,
   decision, source_host, request_count, bytes_out, first_seen, last_seen`. Not stored: resolved IP, client address, duration, any
   user, session or path value (DPIA trigger t7).
2. **Authenticated same-host ingest.** Vector posts closed buckets to `POST /api/internal/egress-audit-ingest` with a bearer token.
   The route requires a loopback `Host`, rejects any forwarding header (Cloudflare adds `X-Forwarded-For` and `CF-Connecting-IP`),
   compares the token in constant time against the current and the previous token (rotation), caps the body, validates with zod
   and bounds `bucket_start` per row. No ingress block exists or is possible for `/api/internal/*` (other internal routes are
   public by design), so these checks and the token are the controls. Ruled by the CTO agent.
3. **One write path.** The route calls `ingest_egress_audit_rollup` (service-role only). It skips and counts unknown, toggle-off
   and malformed rows and never raises on row content, because an error would make the sink retry the same batch forever. It
   merges per column with `GREATEST` (`LEAST` for `first_seen`), never `SUM`: a journald cursor replay after a Vector restart can
   re-count entries and an audit log must not overstate. Distinct host rows per workspace and bucket are capped at 500; the
   overflow folds into one `(other)` row.
4. **The flag is evaluated per organisation, after authentication.** `egress-audit-collection` (Flagsmith runtime flag) defaults
   OFF. A Jikigai-owned canary organisation is enabled by a per-org override; external organisations stay off until PR2 ships
   (CTO ruling A). A missing secret or a disabled flag answers 2xx and drops the batch, never 5xx, so the sink's disk buffer does
   not fill. A failed flag evaluation is "off".
5. **Attribution is hardened at the gateway and again in Vector.** Squid's `%un` logs the presented username even when
   authentication fails (measured on 6.13), so a bad-credential attempt naming another workspace id would otherwise be attributed
   to that workspace. The log format gains the HTTP status as its last field (a host that injects JSON keys cannot override it);
   Vector drops rows with no status or status 407, requires the workspace to be a UUID (the gateway probe username and the
   unauthenticated `-` drop out and write nothing), allowlists host characters and normalises the decision to
   `allowed | denied | other`.
6. **Memory is bounded by a cap, not by hope.** `reduce` holds about 3.7 KB per key. A `throttle` caps 1,000 events per workspace
   per 15 minutes upstream of it. Measured: one workspace with 100,000 unique hosts peaks at 426 MiB uncapped; ten workspaces
   flooding at once peak at 162 MiB with this cap and 270 MiB at 2,000 (the unit's `MemoryMax` is 256M). Discards are exported as
   Vector's per-key discard counter and turned into one `SOLEUR_EGRESS_AUDIT_THROTTLED` marker line per change in Better Stack.
7. **Retention and erasure.** 30 days, hard-deleted daily by a `pg_cron` job on `last_seen`, plus `ON DELETE CASCADE` from the
   workspace. The cascade does not fire on account erasure (the saga keeps the orphan workspace row, migration 065), so account
   deletion calls `erase_egress_audit_rollup` as a required step (5.15) before deleting the auth user.
8. **Nothing is readable in PR1.** The table has RLS enabled, no policy and every privilege revoked from `anon` and
   `authenticated`. The member `SELECT` policy lands in PR2, with the DPIA t6 re-screen as its merge gate.
9. **Counts are best-effort lower bounds; the host set is exact only below the cap.** A restart loses partial buckets and the cap
   discards events above 1,000 per workspace per window. Any later user-facing copy must say so.

## Delivery

The bearer token is a `random_id` plus a `doppler_secret` in `soleur/prd` (`apps/web-platform/infra/egress-audit.tf`), read by the
app and by Vector at process start (Vector already runs under `doppler run --config prd`). The shared `vector.toml` reads it only
as the default-value form, because the same file is rendered onto the dedicated inngest host, which has no gateway and no copy of the
secret; Vector interpolates inside comments too, so the strict form must not appear anywhere in the file (a structural test pins
this). Merging triggers `apply-web-platform-infra.yml`: the secret is created in the main stage, then the SSH stage redelivers
`squid.conf` to the gateways (a container restart: seconds of agent-egress downtime) and `vector.toml` to the web hosts
(`journald_persistent{,_web2}`, a restart with journald cursor resume, no log gap). Until the route is deployed the sink's bounded
retries drop events, which loses nothing while the pipeline is dark.

## Does not defend

- **App-environment compromise.** Anything that can read the app environment, or the Doppler `prd` config, holds the ingest token and
  can forge rows for any workspace that has collection enabled. The token authenticates a same-host hop; it is not an attestation.
- **A local process that can bind or sniff loopback on the web host.** The hop is plain HTTP to `127.0.0.1` (encryption-posture
  exception, expires 2027-01-13).
- **Overstatement of completeness.** Counts and the host set are lower bounds (decision 9). This is not a complete forensic record;
  the 90-day Better Stack copy remains the operator-side record.
- **Detection of a full disk buffer.** Vector's internal logs reach no sink today. A stalled pipeline is detected by the freshness
  probe (`scripts/egress-audit-retention-check.sh`), not by a Vector-side alert.
- **A flooding workspace's later hosts.** Above the cap, discarded events can drop hosts; the marker line says it happened.
- **Buffered events from before a toggle-off.** The toggle is read at ingest time, so they are dropped (errs toward minimization).
  Existing rows are not purged on toggle-off (CTO ruling C, D); they age out within 30 days or on an erasure request.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| App reads Better Stack directly | Needs a workspace-unscopable ClickHouse read credential on the app runtime; the log-query runbook and `cron-inngest-config-drift.ts` keep that credential off the app deliberately. |
| Per-event spool table | Per-event inserts were 63% of production WAL once (PR #5736); retained raw rows serve no stated need. |
| Per-row HMAC with a replay window | Same trust root as a bearer token (anything that reads the app environment holds the key), `GREATEST` already makes replays harmless, and a replay window defeats the disk buffer after an app outage. Reversed by the CTO on plan review. |
| Member `SELECT` policy in PR1 | A readable table is a viewer in fact and triggers the DPIA t6 re-screen at PR1. Ships in PR2. |
| New Inngest prune function | Adds a Sentry cron monitor, which the two-PR monitor rule forbids routing in the PR that creates it; `pg_cron` retention sweeps already exist. |
| Global flag read at the top of the route | Cannot see a per-org override, so the canary would be dropped or every external organisation enabled. Replaced by per-org evaluation after authentication. |
| Cloudflare rule blocking the ingest path | A Terraform change for little gain: the other internal routes must stay public and the token is the real control. |
| `reroute_dropped` on the throttle | Not available in Vector 0.43.1 (rejected at config load); the per-key discard counter is used instead. |

## Consequences

- A new `workspace_egress_audit_rollup` table, three service-role functions and one daily `pg_cron` job; a new internal route with an
  exact `PUBLIC_PATHS` entry; one runtime flag; one Doppler secret.
- Vector gains a rollup pipeline in the shared file. `vector validate --no-environment` does not compile VRL, so the new
  `validate-vector-config.yml` step runs `vector test` against the real file (17 tests, mutation-checked).
- Enabling collection in production is an operator action and is not part of this PR: PR2 must have shipped, the toggle copy and the
  owner notice must be live, and the notice must have been out for at least 7 days (CTO rulings A and B). The CLO-reviewed public
  wording lands as the last commits of the PR1 branch and gates enabling, not merging.
- The forced-error acceptance of ADR-281's `image_cve_scan` monitor is corrected in the same PR (the workflow fired with an email
  action; mailbox receipt was unobserved).
