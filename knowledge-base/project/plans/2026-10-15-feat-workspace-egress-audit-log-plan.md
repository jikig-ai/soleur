---
title: "feat: workspace-visible egress audit log (Scope Grants 'View egress audit log' affordance)"
date: 2026-10-15
slug: workspace-egress-audit-log
branch: feat-egress-audit-log-9545
issue: 9545
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Workspace owners can switch on open-web access for their agents on the Scope Grants "Agent web access" card, but they cannot see which hosts those agents contacted. The per-connection decisions are written by the dedicated egress gateway into a log that is shipped to the operator's log store, and nothing in the product reads it back. This plan builds the read path from those decisions to the workspace that produced them.

Per the binding CTO ruling the work splits in two (the CTO folded the legal-wording PR into the pipeline PR on plan review). This plan specifies the first in full and the second at design level only:

- **PR1: dark ingest pipeline.** A Vector rollup of the gateway log into 15-minute per-workspace buckets, a bearer-authenticated ingest route, a workspace-keyed table that no member can read yet, a 30-day retention sweep, a kill-switch flag defaulting off, plus the ADR, C4 edge and DPIA addendum. The public-document wording and register rows the CLO identified land in the same PR as its last commits, a clean seam that can be split back out if counsel review stalls: collection is off by default, so the wording gates enabling collection, not merging.
- **PR2: read route and settings card.** Member `SELECT` policy, `GET` route and the "View egress audit log" view. It is planned in its own pass once real volume has been measured from the existing Better Stack copy, because its shape depends on that number and because the destination view has no wireframe yet (the approved `.pen` shows only the link). PR2 is tracked on #9545 itself, so this plan files no new issue.

## Research Insights

**Premise validation (Phase 0.6).** Checked against `origin/main`: #9545 is OPEN (priority p2). The Phase A groundwork it waited on exists: `egress-gateway-squid.conf` (`logformat soleur_json`), `egress-auth-helper.sh` (workspace attribution via `%un`), ADR-278 (accepted 2026-10-05), the wireframe `knowledge-base/product/design/settings/agent-web-access.pen` (contains the "View egress audit log" link, not the destination view) and the Scope Grants page. Contradicted or corrected: the planned route `apps/web-platform/app/api/egress-audit/route.ts` does not exist (this is a build, not a fix); the issue says "per-session" but the log line carries no session id; the web-access grant is the column `workspaces.web_egress` (migration 158), not a `scope_grants` row; and the unverified claim that decision lines reach journald is now measured true (below).

**Measured fact (self-pulled, 2026-10-15).** Querying Better Stack for container `soleur-egress-gw` over 24 hours returned 100 rows (the query cap) with fields `bytes_out, client, decision, decision_reason, duration_ms, requested_host, resolved_ip, ts, workspace`. Decisions seen: `TCP_TUNNEL` 50, `TCP_DENIED` 49, `TCP_DENIED_ABORTED` 1. All traffic was the gateway's own probe (`github.com` tunnels and denied metadata-address probes) from a single workspace value, so **real customer volume is unmeasured** and the existing Better Stack copy is where it must be measured before PR2.

**Property List.**

- P1. A workspace's members can eventually see which hosts that workspace's agents contacted and whether each was allowed.
- P2. No workspace can see another workspace's records, including through the ingest path.
- P3. The operator-side raw log keeps its current role (forensics, 90 days) and gains no tenant-readable credential.
- P4. App-database write load from this feature is bounded and measured.
- P5. Stored records age out within a stated retention and can be switched off without a deploy.
- P6. Nothing is disclosed or claimed publicly ahead of the control that backs it.

**Cut List.**

| Mechanism | Property it would buy | Cut because |
|---|---|---|
| App reads Better Stack directly (fork A) | P1 | Needs a workspace-unscopable ClickHouse read credential on the app runtime; `cron-inngest-config-drift.ts` records that this credential is deliberately kept off the app. CTO ruled reject. |
| Per-event spool table (fork B) | P1 | Per-event inserts are the write shape that was 63% of production WAL once (PR #5736); retained raw rows serve no stated user need. CTO ruled reject. |
| Session id on each record | none asked | The log line has no session field; adding one is a gateway change with no requirement behind it. |
| Member `SELECT` policy in PR1 | P1 | A readable table is a viewer in fact and would trigger the DPIA t6 re-screen at PR1. CLO: ship RLS on with no member policy; the policy lands in PR2. |
| Per-row HMAC and replay window | authenticity | Same trust root as a bearer token (anything reading the app env holds the key), GREATEST already makes replays harmless, and the window defeats the disk buffer after an outage. CTO reversed his earlier ruling on plan review. |
| New Inngest prune function | P5 | Would add a Sentry cron monitor, which the two-PR rule forbids routing in the PR that creates it. `pg_cron` retention sweeps already exist (migrations 029, 038, 041). |
| Destination view and wireframe | P1 | Deferred to PR2 by the ruled split. |

**ADR corpus.** ADR-278 (the gateway), ADR-052 (container egress firewall) and ADR-286 (Vector journald source admission: sources are admitted by OR, so adding the rollup transform and sink must be checked against the admission test) bound this design.

**Learnings applied.** Reading Better Stack from the app is contradicted by the log-query runbook (three credentials, only the operator-held one reads content). Per-event inserts conflict with the WAL learning, so the rollup happens before the app. Workspace-attributed host data is personal data and earlier per-user histories were steered to aggregates. Tenant-side writes fail silently without an RPC (RLS plus column grant), so writes go through a `SECURITY DEFINER` function with no tenant `INSERT` policy. The viewer must filter by `workspace_id` with the same predicate as RLS (client/server mismatch learning). Committed `.pen` files must be committed before Pencil opens them (PR2).

## Research Reconciliation: Spec vs. Codebase

| Claim in the issue or brief | Reality | Plan response |
|---|---|---|
| Per-session CONNECT decision logs | Fields are workspace, host, decision, bytes, time; no session or user id | Records are per workspace and bucket. No session field is added. |
| Decision lines reach journald via stdout | Unverified in code (`access_log` writes a file in the container) | Measured working in Better Stack; add an ingest-side freshness signal so a future break is visible (see Observability). |
| Grant stored as a scope grant | Stored as `workspaces.web_egress` (migration 158, RPCs `get_workspace_web_egress`, `set_workspace_web_egress`) | Reuse `is_workspace_member` for the read predicate in PR2; no scope-grant coupling. |
| Route `app/api/egress-audit/route.ts` | Absent | PR2 creates the read route; PR1 creates only an internal ingest route. |
| Runbook says journald is at default size | `journald-soleur.conf` now sets a 1G cap | Correct the runbook sentence in PR1 docs edits. |

## Ruled Design (binding inputs)

**Ingestion (CTO fork 1: aggregated spool, rollup in Vector).**

- Vector reads `sources.egress_gw_journald` directly (not the PII-scrub chain) and applies a `reduce` keyed on `workspace`, `requested_host`, `decision` over 15-minute windows, emitting `count`, `sum(bytes_out)`, `first_seen`, `last_seen` per closed bucket.
- Stored fields: `workspace_id, bucket_start, requested_host, decision, source_host, request_count, bytes_out, first_seen, last_seen`. Not stored: `resolved_ip, client, duration_ms`, any user, session, path or IP value.
- Attribution hardening (plan review, architecture seat; verified by reading `egress-gateway-squid.conf` and `egress-auth-helper.sh`, not yet tested against Squid): `%un` logs the PRESENTED username even when authentication fails, and the helper only guards the allow path, so a bad-credential attempt naming another workspace id would produce a row attributed to that workspace. Add the HTTP status (`%>Hs`) to the logformat, drop failed-authentication (407) rows in VRL, JSON-safe the value, and require `workspace` to match a UUID pattern in VRL. The gateway's own probe username (`probe`) is not a workspace: it becomes a liveness heartbeat with no database write. A gateway test must prove it: a failed-authentication attempt naming a victim id yields a 407 row that VRL drops.
- Time bucketing: compute `bucket_start = floor(ts, 15 min)` in VRL and put it in the `reduce` group key. Vector windows are relative to the first event, so without this a restart re-emits the same real bucket under a shifted key.
- Cardinality: `requested_host` is agent-controlled and VRL is stateless per event, so VRL cannot count distinct hosts. Cap events per workspace per window upstream of the `reduce` with Vector's `throttle` transform keyed on `workspace` (threshold chosen from the Phase 0 volume measurement; excess events are discarded and counted), bound `requested_host` length in VRL, and fold any overflow into one `(other)` row in the RPC. The mechanism is chosen from a `vector test` prototype and a 100,000-unique-host flood test, not assumed, so memory (`MemoryMax=256M`) and WAL stay bounded.
- Rejection semantics: the RPC skips and counts rows for unknown or unattributable workspaces and never raises; the route returns 2xx for them. Raising would make the sink retry the same batch forever.
- Route order: runtime flag off returns 2xx first, then the secret check, then the body. A missing secret must not return 5xx (Vector retries forever).
- Route surface: the app container is published on `0.0.0.0:3000`, so the hop is not strictly loopback. The route requires a loopback `Host`, rejects forwarding headers, and gets an exact entry in `lib/routes.ts` `PUBLIC_PATHS` plus the csrf-coverage exemption (the `kb-drift-ingest` precedent). Without the `PUBLIC_PATHS` entry middleware redirects Vector to the login page before any gate runs.
- Delivery (CTO plan-review ruling, reversing the earlier per-row HMAC): Vector's native HTTP-sink bearer auth (`auth.strategy = "bearer"`) with a bounded disk buffer using `drop_newest` on overflow. The app compares the token in constant time and accepts a current and a previous token so the secret can rotate. Body cap, zod validation, a per-batch row cap and the workspace foreign key stay. The web Vector unit loads a single file (`--config /etc/vector/vector.toml`, `soleur-host-bootstrap.sh:926`), so there is no separate fragment: the sink reads its token through Vector's default-value interpolation `${EGRESS_AUDIT_INGEST_TOKEN:-}`, which does not stop startup where the variable is unset (strict `${VAR}` would). The secret exists only in Doppler `soleur/prd` (the web hosts); the inngest host uses a different Doppler project, never receives it, and runs no gateway, so the sink never fires there. The shared file already interpolates `${BETTERSTACK_LOGS_TOKEN}` (validated with dummy values at `server.tf:1445`). Support for the `:-` default in Vector 0.43.1 is verified by a Phase 3 test (`vector validate` with the variable unset and set) before the design is frozen. There is no replay window: `bucket_start` is validated instead (reject rows older than the 30-day retention or later than now plus one bucket plus skew), so a buffered backlog after an app outage is still accepted. The trust root is app-environment compromise (anything that can read the app env can forge rows); it goes in the ADR's does-not-defend list. Measured at work time: `/api/internal/*` is NOT blocked at the ingress and cannot be (other internal routes are deliberately public); ruled R2: no Cloudflare rule, the loopback-`Host` check, forwarding-header rejection and bearer token are the controls.
- Target: `http://127.0.0.1:3000/api/internal/egress-audit-ingest` (Vector and the app share the host; no firewall change, per the IaC read of ADR-052 and the inbound-only Hetzner firewall).
- Write path: route validates with zod, then calls one `SECURITY DEFINER` RPC that batch-upserts with `GREATEST` on conflict, key `(workspace_id, bucket_start, requested_host, decision, source_host)`. The workspace foreign key is a second check that rejects unknown workspaces.
- With the flag off the route returns 2xx and drops the batch, so the sink never retries into a full buffer.

**Counting semantics (resolves a tension between the CTO's `GREATEST` upsert and Vector's in-memory reduce state).** A Vector restart loses partial buckets, so a bucket can be emitted twice with different partial counts. `GREATEST` keeps the larger and makes retries idempotent, but undercounts across a restart. Per the CTO ruling `GREATEST` applies per column to `request_count`, `bytes_out` and `last_seen`, and `LEAST` to `first_seen`; `SUM` was rejected because journald cursor replay after a restart can re-count entries, and an audit log must never overstate. `source_host` stays in the key, taken from Vector's host field and validated against an allowlist, so two hosts' counts are kept apart and summed on read. The contract is therefore: **the set of hosts contacted and the decision are exact; counts and byte totals are best-effort lower bounds.** PR2's copy must say so, and an acceptance criterion pins it.

**Authorization (CTO fork 2).** Any workspace member may read, by `is_workspace_member(workspace_id, auth.uid())`, the same predicate in RLS and in the route, with the user-scoped client (not the service role). Confirm the predicate excludes pending and removed members. In PR1 the table has RLS enabled and **no** policy for members; only the RPC path writes, and nothing reads.

**Retention.** Engineering ceiling and recommended value: 30 days, hard-deleted daily on `last_seen`, plus `ON DELETE CASCADE` from the workspace. Mechanism: a `pg_cron` job defined in the migration calling a bounded batched-delete function (precedent: migrations 029, 038, 041). The legal number remains the CLO's call and gates both enabling collection and merging the PR1 legal commits.

## Implementation Phases (PR1)

### Phase 0: gates before code

1. Write the DPIA screening addendum (CLO): record that the rollup changes the facts of the 2026-10-05 memo (app-database persistence, a 30-day store, a table that will become member-readable), that WP248 "systematic monitoring of employees" is now partly engaged, and add trigger **t7**: retention above 30 days, or any user, session, IP or path field added. The full t6 re-screen (viewer lands) stays a PR2 merge gate.
2. Measure real daily CONNECT volume from the Better Stack copy (self-pull, 7-day window if retained) and record rows/day and the resulting rollup row estimate in this plan before the migration is written. This sizes the WAL estimate; the CTO's figure (about 80k rows/day at 1,000 workspaces) is the starting assumption, not the measurement.
3. Collection stays off for every external workspace until PR2 ships (ruled by the CTO agent, decision A below). PR1 ships dark; the only carve-out is a Jikigai-owned canary workspace via a per-org flag override, which still needs explicit operator authorization.
4. Measure before the acceptance criteria are frozen (the attribution and cardinality claims rest on reading, not on a test): on the pinned Squid image, whether `%un` logs the presented username on a failed login and whether `%>Hs` renders 407; with `vector test`, the `reduce` window and `throttle` behaviour including a 100,000-unique-host flood and its memory; and that Vector 0.43.1 accepts the default-value interpolation. The volume figures in this plan come from `betterstack-query.sh --since 24h --grep requested_host` (100 rows, the query cap: `TCP_TUNNEL` 50, `TCP_DENIED` 49, `TCP_DENIED_ABORTED` 1).

### Phase 1: migration (RED tests first)

`apps/web-platform/supabase/migrations/162_workspace_egress_audit_rollup.sql` (re-check the number at work time; 161 is the latest today) with `.down.sql`, `supabase/verify/162_*.sql`, and `test/supabase-migrations/162-*.test.ts`.

- Table `workspace_egress_audit_rollup` with the composite primary key above, `decision` stored as text and normalised in VRL (a CHECK would drift: Squid emits many `%Ss` values), `request_count`, `bytes_out` non-negative, `workspace_id` FK `ON DELETE CASCADE`.
- `ENABLE ROW LEVEL SECURITY`; `REVOKE INSERT, UPDATE, DELETE, SELECT` from `anon` and `authenticated` (migration 058 revokes only INSERT, UPDATE and DELETE; this migration also revokes SELECT because no member policy exists yet); no member policy in this migration.
- `ingest_egress_audit_rollup(rows jsonb)`: `SECURITY DEFINER`, `search_path` pinned including `pg_temp`, `GRANT EXECUTE` to `service_role` only with `REVOKE ... FROM PUBLIC`, bounded row count per call, skips and counts rows for unknown workspaces and for workspaces whose `web_egress` is false, joining `workspaces.web_egress` (never raises).
- `purge_egress_audit_rollup(retention interval)` batched delete (name follows `purge_workspace_member_actions`, migration 063), `REVOKE EXECUTE` from PUBLIC, anon and authenticated, scheduled with `pg_cron` daily inside a `DO` block catching `duplicate_object`; the `.down.sql` calls `cron.unschedule` and drops both functions; the verify SQL uses the `bad=1` row format of migration 158 for the grants, the table comment and the `cron.job` row.
- Register the new table in `test/rls-fuzz/targets.ts`: `workspaceTenancyTables` flags any RLS table with a `workspace_id` column until it is a target or an `EXCLUDED_ISOLATION` entry with a rationale. `rpc-cases.ts` covers only RPCs that `authenticated` can execute, and the ingest RPC is service-role only, so it is not registered there.
- Cross-tenant, cascade, sweep, idempotency and per-column `GREATEST` checks run in the live-database harness (`RLS_FUZZ_LOCAL`, real `SET ROLE` and JWT claims). `test/supabase-migrations/162-*.test.ts` holds offline SQL-text lints that cannot cross an auth boundary, so it carries only text assertions. Every negative read has a service-role positive control so an empty table cannot pass.

### Phase 2: ingest route and server module (RED tests first)

`app/api/internal/egress-audit-ingest/route.ts` (HTTP-method exports only) delegating to `server/egress-audit-ingest.ts`: body cap, bearer-token check (constant-time, current and previous token) and `bucket_start` bounds, zod schema, runtime-flag gate (Flagsmith `RUNTIME_FLAGS`, created with `soleur:flag-create`; fail-closed means dropping rows, because the deploy-time `ENV_FLAGS` mechanism cannot switch off without a deploy and so cannot satisfy P5), tenant-client-free service path calling the RPC, Sentry mirror on every failure path via the repo's silent-fallback helper. Follows the `kb-drift-ingest` internal-route pattern.

### Phase 3: Vector config (RED tests first)

`apps/web-platform/infra/vector.toml`: the `reduce` transform fed from `egress_gw_journald`, the VRL steps that compute `bucket_start`, filter (attribution hardening) and bound `requested_host` length, a `throttle` transform for the per-workspace event cap upstream of the `reduce`, and a new HTTP sink using native bearer auth with a bounded disk buffer. The sink reads its token through `${EGRESS_AUDIT_INGEST_TOKEN:-}` (default-empty, so the shared file still starts on the dedicated inngest host, where the sink never fires); there is no separate fragment because the unit loads one file. Add a `vector-egress-rollup` test file with fixtures, extend the admission-test model for the new sink, and keep `validate-vector-config.yml` green.

### Phase 4: secret and delivery

Terraform carrier for the bearer secret following `github-app.tf`: a `random_id` plus a `doppler_secret` in project `soleur`, config `prd`, masked, with no Terraform variable and no default (`hr-tf-variable-no-operator-mint-default`). The same `prd` secret reaches the app and Vector (Vector already runs under `doppler run --config prd`), so no unit or drop-in change is needed. The inngest host uses a different Doppler project and never receives it. Merge effect (state this as the first line of the PR body): merging triggers `apply-web-platform-infra.yml` (`paths: apps/web-platform/infra/**`), whose targets include `journald_persistent{,_web2}`, so Vector is redelivered to the web hosts and restarted (no serving downtime) independently of the app deploy and with no `depends_on` on the new secret. The ordering 'secret and route first' is therefore not enforceable, and the design makes it harmless: the sink's default-empty token and bounded retries mean that until the route and secret exist events are retried a bounded number of times and dropped, which loses nothing while the pipeline is dark. Delivery to running hosts uses the existing push apply for `terraform_data.journald_persistent` and `journald_persistent_web2` (`vector-redeliver` covers web-1 only; web-2 needs the push apply), which is a hash-triggered replace of those provisioners with a validate-and-restore gate: no host replace, no serving downtime, journald cursor-resumed so no log gap. This is the documented exception to `hr-prod-host-config-change-immutable-redeploy`: `vector.toml` is declared, hashed configuration with a validated reload.

### Phase 5: documentation carried by PR1

ADR (below), the C4 edge (below), the DPIA addendum from Phase 0, the runbook sentence correction, and the one-line ADR-281 correction: its Consequences bullet about the `image_cve_scan` monitor still says the forced-error acceptance "is not yet observed". Reword to: the workflow fired with an email action on 2026-10-15; mailbox receipt unobserved. This rides this PR rather than a standalone PR (CTO ruling).

### Phase 6: enablement (not part of the merge)

Turning the flag on in production is a separate, operator-authorized step and is not performed by this PR. Preconditions (CTO rulings A and B): no external-workspace enablement before PR2 has merged and the PR2 legal copy, the toggle copy and the owner notice are live; the owner notice has gone out at least 7 days earlier; the PR1 legal commits have merged and the DPIA addendum is filed. A Jikigai-owned canary workspace may be enabled earlier through a per-org flag override. A work-time check proves the per-org override works before this phase is relied on.

## Files to Create

- `apps/web-platform/supabase/migrations/162_workspace_egress_audit_rollup.sql`, `.down.sql`
- `apps/web-platform/supabase/verify/162_workspace_egress_audit_rollup.sql`
- `apps/web-platform/test/supabase-migrations/162-workspace-egress-audit-rollup.test.ts`
- `apps/web-platform/app/api/internal/egress-audit-ingest/route.ts`
- `apps/web-platform/server/egress-audit-ingest.ts`
- `apps/web-platform/test/egress-audit-ingest.test.ts`
- a live-database integration test beside the existing `RLS_FUZZ_LOCAL` cases (file name chosen at work time)
- `scripts/egress-audit-retention-check.sh` (freshness and retention probe; failure exits non-zero)
- `apps/web-platform/infra/vector-egress-rollup.test.sh` and fixtures under `apps/web-platform/infra/test-fixtures/`
- `knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md` (confirm next free ordinal at work time; the ship gate re-verifies)
- `knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md`

## Files to Edit

- `apps/web-platform/infra/vector.toml`
- `apps/web-platform/infra/egress-gateway-squid.conf` (add `%>Hs` to the logformat) and `apps/web-platform/infra/egress-gateway.test.sh` (failed-authentication attribution test); delivery path for the gateway config confirmed with the IaC architect at work time
- `apps/web-platform/lib/routes.ts` (`PUBLIC_PATHS` exact entry) and `apps/web-platform/lib/auth/csrf-coverage.test.ts`
- `apps/web-platform/test/rls-fuzz/targets.ts`
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (bump the `BASELINE_DECLARED_PROBES` ratchet from 66 to 67 with the required placement/truth/no-substitute comment, because this plan declares `credentials_required`; the test fails today at 67 declared against 66)
- Terraform for the bearer secret (extend the existing Doppler secrets file or add alongside `github-app.tf`)
- `apps/web-platform/lib/feature-flags/server.ts` (new runtime flag name, created through `soleur:flag-create`; the typed-`yes` creation step is handed to the operator) and `.env.example`
- `apps/web-platform/test/infra/vector-admission.test.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` if the edge must render)
- `knowledge-base/engineering/architecture/decisions/ADR-281-image-cve-scan-advisory-first-promoted-on-measured-fp-criterion.md` (one-line correction)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (stale journald sentence)
- `knowledge-base/legal/compliance-posture.md` (t6 addendum and t7 rows)

PR1 legal commits (the last commits of the same PR, a clean seam): `docs/legal/privacy-policy.md` (line near 197 and section 7), `docs/legal/acceptable-use-policy.md` (near 319), `docs/legal/data-protection-disclosure.md` (near 230), `docs/legal/gdpr-policy.md` (new entry), each mirrored under `plugins/soleur/docs/pages/legal/`, and `knowledge-base/legal/article-30-register.md` (PA-2, PA-8), `article-30-2-register.md`, `compliance-posture.md`.

## Open Code-Review Overlap

Re-run over the final file list. Four open `code-review` issues name a planned file and none concerns this work: #9705 (names `model.c4`; dead-probe heartbeat for an inngest alert), #3216 and #2197 (name `server.tf`; resolved-inline review notes and a billing refactor) and #8436 (names the GDPR policy; CCLA execution docs). Disposition for all four: **acknowledge** - different concerns, left open, no overlap in the edited regions.

## User-Brand Impact

- **If this lands broken, the user experiences:** a workspace owner who has enabled agent web access never sees the audit view populated, or sees counts that are lower than reality after a Vector restart; in PR1 nothing user-visible changes because the pipeline is dark.
- **If this leaks, the user's workflow is exposed via:** a record attributed to the wrong workspace (a forged or misrouted `workspace` value accepted by the ingest route, or an RLS gap in PR2) revealing which external hosts one workspace's agents contacted, which can disclose what a founder asked an agent to research.
- **Brand-survival threshold:** single-user incident

CPO sign-off is required at plan time before `soleur:work` begins (frontmatter `requires_cpo_signoff: true`); `soleur:engineering:review:user-impact-reviewer` runs at review time. Mitigations designed in: attribution comes from the gateway's token-bound `%un` (not client-supplied), the workspace FK rejects unknown ids, bearer-token auth with `bucket_start` bounds, a toggle join that drops rows for workspaces with web access off, no tenant write policy, RLS with no member policy until PR2, and a cross-tenant read test as an acceptance criterion.

Added at review (PR #10349): **account deletion fails closed** (a failing erase step aborts before the auth user is deleted, and is mirrored to Sentry with the user id), **resurrection** (a late buffered bucket re-creating erased history is closed by the orphan skip and the member-row lock), and **public legal wording** that states a control before it exists (the CLO-drafted text is qualified as drafted-not-live and lands last; it gates enabling, not merging).

## Observability

```yaml
liveness_signal:
  what: ingest freshness - the newest bucket_start in workspace_egress_audit_rollup is within 75 minutes whenever the gateway raw log (Better Stack) shows decisions for a canary workspace 35 to 60 minutes ago (a bucket lands about 31 minutes after its start, so the newest landed bucket is 31 to 46 minutes old in steady state); when the gateway log shows none the workspace set is idle and the probe passes, so the committed probe can tell idle from broken only by reading both sides (the app's info-level log lines are dropped by app_container_warn_filter, so a log marker cannot carry this signal); the gateway's own probe username provides a no-database-write heartbeat for the log path
  cadence: every 15-minute bucket flush
  alert_target: the freshness probe, read by the existing scheduled supabase watchdog or a follow-through; the gateway log path keeps its existing egress_gw_probe_silent alert
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf and apps/web-platform/infra/vector.toml
error_reporting:
  destination: Sentry via the repo's silent-fallback mirror for every ingest failure path (bad token, schema reject, bucket out of bounds, RPC error, body over cap); Vector sink errors have no Better Stack source today (see failure modes)
  fail_loud: true
  payload_rule: Sentry events carry reason codes and counts only, never `requested_host` or workspace values (host names can reveal user behaviour)
failure_modes:
  - mode: Vector restarts and loses partial buckets
    detection: counts undercount; set of hosts stays exact; documented as best-effort in the contract
    alert_route: none (accepted by design); AC pins the wording
  - mode: ingest route rejects everything (key drift between Vector and app)
    detection: freshness probe shows a stale max(bucket_start) while the gateway log is live; Sentry event per reject, debounced because the route is internet-reachable
    alert_route: freshness probe plus Sentry
  - mode: disk buffer fills (app down or flag mis-set)
    detection: no Better Stack source exists for Vector internal logs today (the vector_internal source reaches the console sink only), so detection is the freshness probe; the work phase adds a source only if it finds a cheap path, otherwise the gap is recorded in the ADR
    alert_route: freshness probe
  - mode: retention sweep stops running
    detection: a probe asserting no row with last_seen older than 35 days
    alert_route: the discoverability script below, run by the existing scheduled supabase watchdog or a follow-through
  - mode: gateway log stops reaching Better Stack (stdout path breaks)
    detection: egress_gw_probe_silent alert already exists
    alert_route: existing Better Stack policy
logs:
  where: Sentry (ingest failures) and Better Stack (the gateway raw log); the table itself is not a log
  retention: 90 days in Better Stack; 30 days for table rows
discoverability_test:
  command: bash scripts/egress-audit-retention-check.sh
  expected_output: "OK"
  credentials_required: "Supabase prd service-role read - no unauthenticated probe can read table freshness or the age of the oldest row"
```

The retention probe script is a committed repo-relative file created in Phase 1 (it reads through the Supabase REST path the preflight runbook already uses, prints `OK` only when the newest bucket is fresh and no row is older than 35 days, and exits non-zero otherwise; an unavailable read is a failure, never a pass). Its path is listed under Files to Create.

## Encryption Posture

```yaml
at_rest:
  - store: supabase.prd table workspace_egress_audit_rollup
    mechanism: provider-managed:Supabase platform disk encryption (named attestation recorded in the existing encryption-posture ledger for supabase.prd)
    evidence: knowledge-base ledger row for supabase.prd resolved by scripts/lint-encryption-posture.py
    defends_against: a seized or snapshotted database volume
    does_not_defend: a leaked service-role credential, an RLS bypass, or a SQL injection reading the table
    disclosed_as: not-publicly-claimed until the PR1 legal commits land
    live_verification: unavailable:no per-table attestation endpoint
in_transit:
  - connection: Vector -> app ingest route (same host; the app is published on 0.0.0.0:3000, so the route also requires a loopback Host and rejects forwarding headers)
    enforced_at: apps/web-platform/infra/vector.toml sink uri and server/egress-audit-ingest.ts
    tls: none on the same-host hop (plain HTTP to 127.0.0.1)
    cert_verification: off
    does_not_defend: any local process able to bind or sniff loopback on the host; authenticity rests on the bearer token, not transport
    disclosed_as: not-publicly-claimed
exception:
  justification: same-host hop where Vector and the app are co-resident; authenticity rests on the bearer token (rotation: current plus previous), not on transport; app-environment compromise can forge rows and is recorded in the ADR
  tracking_issue: "#9545"
  reevaluate_when: Vector or the ingest route moves to a different host or network namespace
  expires_on: 2027-01-13  # lint-encryption-posture.py fails repo-wide once this date passes; renew or remove before then
```

## Infrastructure (IaC)

### Terraform changes

Bearer secret as `random_id` plus `doppler_secret` (project `soleur`, config `prd`, masked), modelled on `github-app.tf`. No `variable`, no default. Provider versions unchanged.

### Apply path

Push apply of `terraform_data.journald_persistent` and `terraform_data.journald_persistent_web2` after merge (hash-triggered re-provision with validate and restore). Not a host replace; no serving downtime; Vector restarts with a 20 second settle window.

### Host fan-out

Gateway and Vector run on the web hosts only: `egress_gateway` and `egress_gateway_web2`. web-2 is a `twin` already covered by `journald_persistent_web2`. The inngest host receives the same `vector.toml` but runs no gateway, so the rollup transform is inert there; the sink's token is default-empty (`${EGRESS_AUDIT_INGEST_TOKEN:-}`) and the secret exists only in the web hosts' Doppler config, so the inngest host neither needs nor receives it.

### Distinctness / drift safeguards

`vector.toml` is not in the `deploy_pipeline_fix` trigger list, so no list edit is needed; no new pushed file is added, so `FILE_MAP`, `hooks.json.tmpl` and the ship-gate trigger list are untouched. A new `prd` secret needs no doppler-config-inventory change.

### Vendor-tier reality check

Better Stack free tier: 3 GB per month and 3-day retention applies to the free plan; the measured source shows 90-day retention in force, so the raw copy is not the constraint. The new sink adds no Better Stack volume.

## Architecture Decision (ADR/C4)

### ADR

Create `ADR-288` (ordinal provisional): "Aggregated egress audit spool via Vector to app ingest". Decision: roll up before the app, authenticate with a rotating bearer token, write through a single `SECURITY DEFINER` function, no member read until PR2, 30-day retention. Alternatives Considered table records the two rejected forks and the rejected member policy, each with the CTO and CLO reasoning above, plus per-row HMAC with a replay window (rejected by the CTO on plan review: same trust root, no added protection, and the window defeats the disk buffer). The does-not-defend list records that app-environment compromise can forge rows. Status "adopting" until PR2 ships. Carry the ADR-281 one-line correction in the same PR.

### C4 views

Read all three of `model.c4`, `views.c4` and `spec.c4` before editing. Already modelled: the Agent Egress Gateway container (`egressGw`, `model.c4:314`), the per-dispatch egress forwarder component (`model.c4:116`), and the Better Stack warehouse edges. Not modelled: the Vector-to-web-app ingest edge and the app database holding the rollup. In scope: add the edge (and a Vector element if none exists) with its `view ... include` line so it renders, and fix any description the change falsifies. `views.c4` carries a recorded layout gap for the egress path (`views.c4:5`); adding the edge changes layout, so regenerate with `bash scripts/regenerate-c4-model.sh` and run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

The ADR is authored now describing the target state with status "adopting"; it is not postponed.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO, deferred to PR2), Operations (infra)

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled fork 1 aggregated spool with rollup in Vector, fork 2 any member reads, a two-PR split, a 30-day engineering ceiling, and three constraints (measured WAL estimate with failure mirroring; write only through the RPC with no per-user columns; DPIA t6, retention number and privacy wording settled before PR1 merges). Infra review confirmed the delivery path, secret carrier and loopback reachability above.

### Legal

**Status:** reviewed
**Assessment:** CLO: the rollup is personal data (pseudonymous at best; directly identifying in a solo workspace). Jikigai is controller for solo workspaces and processor for team workspaces, and an independent controller of the 90-day raw log. DPIA t6 literally fires at the viewer (PR2) but PR1 changes the memo's facts, so an addendum precedes PR1 and PR1 ships with no member read. Retention 30 days under Art. 6(1)(f), cascade on workspace delete. Existing sentences in the privacy policy, acceptable-use policy and data-protection disclosure over-claim an audit log owners cannot see and need temporal qualifiers; the GDPR policy has no entry for the gateway at all. Draft wording is for counsel review and is carried by the PR1 legal commits.

### Product (CPO sign-off)

**Status:** SIGN-OFF WITH CONDITIONS for PR1 (PR2 gets its own sign-off). Conditions: (1) the PR1 legal commits merge before the collection flag is ever enabled in production; (2) the ingest drops and reports any unattributable workspace row (fail closed, never defaulted); (3) PR2 requires a new CPO and spec-flow pass, a wireframe, the DPIA t6 re-screen, a two-user cross-tenant test and plain best-effort count copy; (4) the operator decides on existing opted-in owners and the toggle's confirmation copy; (5) the measured rows/day figure is recorded. Also confirm `is_workspace_member` excludes pending and removed members, and state in PR2 copy that history is visible to current members.

### Product/UX Gate

**Tier:** advisory (deferred)
**Decision:** skipped for PR1: no user-facing file in its Files lists, so the mechanical UI-surface override does not fire. PR2 will run the BLOCKING pipeline (spec-flow, CPO, and a new wireframe for the destination view, since the approved `.pen` shows only the link).
**Agents invoked:** none for PR1
**Skipped specialists:** soleur:product:design:ux-design-lead (no UI surface in PR1; required at PR2 planning)
**Pencil available:** N/A (no UI surface in PR1)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A read path from per-session CONNECT decision logs to the workspace owner" [issue #9545] | Ruled Design (ingestion); Phases 1-4 | mapped (PR2 completes the read side) |
| 2 | "either (a) a spool/table the app reads ... or (b) a minimal settings UI view" [issue #9545] | Ruled Design; PR2 | mapped (a) in PR1, (b) in PR2 |
| 3 | "Needs: ingestion path (Better Stack query API or journald-side spool), authz scope, empty state, and the wireframe's link wired to a real destination." [issue #9545] | Ingestion and authorization rulings; empty state and link | mapped ingestion and authz; empty state and link descoped to PR2 - justification: they need the destination view and its wireframe |
| 4 | "the DPIA re-screen (memo knowledge-base/legal/ ... 2026-10-05-dpia-screening-agent-web-egress.md, trigger t6, 're-run before merge once the viewer lands') is a PLAN DELIVERABLE and merge gate" [brief] | Phase 0.1, PR2 merge gate | mapped |
| 5 | "the plan must settle two open design forks: authorization scope ... and ingestion path" [brief] | Ruled Design | mapped |
| 6 | "if a spool table is chosen include a write-frequency and WAL estimate" [brief] | Phase 0.2, Observability | mapped |
| 7 | "UI work needs a wireframe per wg-ui-feature-requires-pen-wireframe" [brief] | Product/UX Gate (PR2) | descoped to PR2 - justification: PR1 has no UI file |
| 8 | "Fold that one-line correction into this plan's first ADR or doc-touching PR" [brief] | Phase 5, Files to Edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Migration 162, RPC, table | "a spool/table the app reads" | asked |
| Ingest route and server module | "ingestion path (Better Stack query API or journald-side spool)" | asked |
| Vector rollup transform and sink | "ingestion path ... journald-side spool" | asked |
| Bearer secret Terraform carrier | — | inferred - justification: the ingest route must authenticate its caller or any local process could forge workspace data |
| Kill-switch flag | — | inferred - justification: CTO ruling requires a dark ship and a no-deploy off switch (P5) |
| pg_cron retention sweep | — | inferred - justification: CTO and CLO both bound retention; an unswept table breaches Art. 5(1)(e) |
| DPIA addendum and t7 trigger | "the DPIA re-screen ... is a PLAN DELIVERABLE" | asked |
| ADR-288 and C4 edge | — | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable` requires the record with the decision |
| Retention probe script | — | inferred - justification: the observability gate requires a no-SSH discoverability command |
| ADR-281 correction | "Fold that one-line correction into this plan's first ADR or doc-touching PR" | asked |

### Split Assessment

- Subsystems touched: 5 - `apps/web-platform`, `knowledge-base`, `docs`, `plugins/soleur`, `scripts` (docs and plugins only through the PR1 legal commits' mirrors)
- Planned files: about 38 (13 to create, 15 to edit, 10 legal documents and mirrors) | Estimated changed lines: about 900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: the tunables say split (5 roots, about 38 files); the CTO ruling on plan review overrides to two PRs: PR1 (dark pipeline plus the legal wording as its last commits, a clean seam that can be split back out if counsel review stalls) and PR2 (read route and card, planned after volume is measured)

## Acceptance Criteria

### PR1 (pipeline)

- [ ] In the live-database harness, a service-role write for workspace A succeeds (positive control) and a user-token read by a member of workspace B, and by a member of workspace A, is denied (PostgREST permission error, because SELECT is revoked in PR1); a table-empty pass is impossible.
- [ ] The ingest route rejects: a missing or wrong bearer token (the current and the previous token are both accepted), an out-of-bounds bucket, an oversize body, and a malformed row; unknown or unattributable workspaces are skipped and counted (never an error); each rejection is mirrored to Sentry, debounced.
- [ ] With the runtime flag injected off for every org in a batch (not read from the ambient environment) the route returns 2xx and writes nothing; a missing secret or a disabled flag never returns 5xx. The flag is evaluated per organisation after auth and parse (ruling R5 below replaces the earlier 'flag before the secret check' order).
- [ ] A failed-authentication attempt naming a victim workspace id produces a 407 gateway row that VRL drops; a non-UUID or `probe` username never reaches the database; the gateway test asserts both.
- [ ] `bucket_start` is computed from the event timestamp, a Vector restart does not shift bucket keys, and a flood of unique hosts is capped at 1,000 events per workspace per 900 s by `throttle` (R1); the RPC folds any host overflow into an `(other)` row; throttle discards are visible to an operator without SSH (a Vector internal-metrics path to a sink, or a Better Stack warning).
- [ ] CI proves the live-database cases executed: the `rls-authz-fuzz.yml` run asserts a non-zero executed count for the new cases, because the harness is wired through `describe.skipIf` and a skipped run exits 0.
- [ ] The preflight discoverability ratchet (`BASELINE_DECLARED_PROBES`) is bumped to the new count with the required comment and its test passes.
- [ ] Token rotation works: the previous token is still accepted during rotation, an unrelated token is rejected, and the comparison is constant-time.
- [ ] The RPC drops (and counts) rows for a workspace whose `web_egress` is false, and accepts them once it is true, tested in the live-database harness. The RPC checks the toggle's current state, not its state when the event happened, so buffered events from before a toggle-off are dropped (this errs toward minimization and is stated in the ADR); denied rows while the toggle is off are not stored (they remain in the 90-day raw log); toggle-off does not purge existing rows in this PR.
- [ ] A short DSAR runbook (export or delete by `workspace_id`, service role) is committed, so an Art. 15 or Art. 17 request has a product path before any external enablement.
- [ ] The new route has an exact `PUBLIC_PATHS` entry and passes the csrf-coverage test; the new table is a target (or an `EXCLUDED_ISOLATION` entry with rationale) in `test/rls-fuzz/targets.ts`.
- [ ] The RPC is executable by `service_role` only; `anon` and `authenticated` have no table privileges.
- [ ] The retention sweep deletes rows older than 30 days in bounded batches and is verified by a test that inserts an aged row (this table is not WORM-protected, so no trigger blocks the delete).
- [ ] `vector validate` passes; the new sink has a bounded disk buffer with `drop_newest`; the shared `vector.toml` carries no literal secret and reads the token only through `${EGRESS_AUDIT_INGEST_TOKEN:-}`, and `vector validate` passes with that variable unset (as on the inngest host) and set; the admission test and the new rollup test pass.
- [ ] (work-time gate, not a test) A measured rows/day figure from the real gateway log and the resulting WAL estimate are recorded in this plan before the migration is written.
- [ ] Counts are documented and tested as best-effort lower bounds; the set of hosts and decisions is exact.
- [ ] The new ADR (next free ordinal at the merge base), the C4 edge and the DPIA addendum (with trigger t7) are committed; `c4-count-parity` and the C4 render tests pass.
- [ ] ADR-281's stale sentence is corrected with "workflow fired with email action; receipt unobserved".
- [ ] (gdpr-gate `GDPR-Art-6`) The migration annotates the lawful basis on the table or each column with `-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f))`, matching the CLO's basis, and the DPIA addendum cites the same basis.
- [ ] (gdpr-gate `GDPR-Art-5e`) The table carries a `COMMENT ON TABLE` stating the 30-day retention and the sweep function name, and the verify SQL asserts the comment and the scheduled job exist.
- [ ] (gdpr-gate `GDPR-Art-17`, case 1) Rows disappear when the workspace row is deleted.
- [ ] (gdpr-gate `GDPR-Art-17`, case 2) Rows disappear on the account-erasure path for a solo workspace (where `workspace_id` equals the founder's id). Measured: the saga leaves the workspace row (migration 065), so the cascade does not cover it; ruling R3 adds saga step `5.15 erase-egress-audit-rollup` calling `erase_egress_audit_rollup(p_workspace uuid)` (service-role, idempotent, abort-on-failure) and a test in `test/account-delete.test.ts` that drives it; the DSAR export allowlist decision is recorded (rollup rows are not exported per user: no per-user data).
- [ ] (gdpr-gate testing layer) Test fixtures use synthesized workspace ids and hosts only (`cq-test-fixtures-synthesized-only`); no real workspace id or customer host appears in any fixture, including the Vector rollup fixtures.

### PR1 legal commits (last in the PR)

- [ ] Each public sentence the CLO flagged carries a temporal qualifier or the corrected fact, mirrored under `plugins/soleur/docs/pages/legal/`, with the retention number the CLO confirms.
- [ ] Article 30 register rows (PA-2, PA-8, processor-capacity) and the `compliance-posture.md` rows are added.

### PR2 (recorded here, planned later)

- [ ] DPIA t6 re-screen completed before merge; member `SELECT` policy and route share `is_workspace_member`; wireframe for the destination view committed first.
- [ ] (CTO rulings B and D) The owner notice (email to owners of workspaces with `web_egress=true`, plus a persistent in-app notice on the Agent web access card) is drafted by the CLO and goes out at least 7 days before external enablement; owners who switch on later see the confirmation copy at the toggle, which ships before enablement. Owners can opt out by switching the toggle off, which stops collection.
- [ ] (CTO ruling D) The toggle copy says that switching off stops new records, that existing records are deleted within 30 days, and that deleting the workspace deletes everything; it also says counts are best-effort lower bounds and that history is visible to current members. An explicit erasure request goes through the DSAR runbook. Exact wording is settled in PR2 planning with the CLO and CPO; if the CLO objects before PR2 merges, ruling D is reopened.

## Test Scenarios

- Given a valid row with the bearer token for workspace A, when the route is called with the flag on, then one bucket row exists and a second identical call leaves the row unchanged.
- Given two partial rows for one bucket (a Vector restart), then the stored count equals the larger.
- Given a row for a nonexistent workspace, then the RPC rejects it and no other row in the batch is lost.
- Given a row whose `bucket_start` is older than 30 days or later than now plus one bucket plus skew, then it is rejected; given a buffered row two hours old after an app outage, then it is accepted.
- Given a member of workspace B querying through PostgREST with a user token in PR1, then a permission error (SELECT is revoked); zero rows is the PR2 behaviour once the member policy exists.
- Given a failed-authentication gateway attempt naming a victim workspace id, then no rollup row is created for that workspace.
- Given the gateway's own probe username, then no database write occurs and the heartbeat is still emitted.
- Given the flag off and Vector sending, then the sink sees 2xx and the buffer does not grow.
- Given a row aged 31 days, when the sweep runs, then it is deleted; a 29-day row is kept.
- Given `vector.toml` with the new transform on the inngest host (no gateway), then Vector starts and the transform emits nothing.

## Plan-Review Revisions

Five-seat panel (simplicity, architecture, flow, convention, over-engineering critique) plus the CPO sign-off and one CTO consult on the contested items. Dispositions:

**Applied as mechanical** (one right answer): `PUBLIC_PATHS` and csrf-coverage entries; live-database harness for the isolation, cascade, sweep and `GREATEST` checks with service-role positive controls (the migrations directory holds offline lints); `targets.ts` registration instead of `rpc-cases.ts`; RPC skips and counts unknown workspaces and returns 2xx; attribution hardening for the forged-username case (`%>Hs`, drop 407, UUID pattern, `probe` as heartbeat); `bucket_start` in the reduce key; per-workspace host cap with an `(other)` bucket; flag check ordering and a runtime (Flagsmith) flag; observability moved from a log marker that the app's log filter drops to a database freshness probe, with `UNAVAILABLE` no longer a pass; migration details (`REVOKE ... FROM PUBLIC`, `down.sql` unschedule and drops, `DO`/`EXCEPTION` wrapper, `purge_` naming, no `CHECK` on `decision`, verify-SQL row format); ordinal-independent acceptance criteria; the Art. 17 criterion split into two cases; the loopback exception text and its lint expiry.

**Decided by the CTO on plan review** (reversing or confirming the earlier ruling): static bearer token via Vector's native sink auth replaces per-row HMAC (same trust root, no added protection); the replay window is dropped in favour of `bucket_start` bounds; `GREATEST` stays, per column, with `LEAST` for `first_seen`; `source_host` stays in the key; the legal-wording PR folds into PR1 as its last commits; collection is gated on the workspace toggle and toggle-off does not purge in PR1.

**Considered and not applied.** The over-engineering critique's proposals to delete the ADR and C4 work (the repo rule makes the decision record a deliverable of the plan that makes the decision), to drop the bounded disk buffer and the admission-test extension (the write-load property needs the buffer; the admission test is an existing convention), and to drop the account-erasure criterion (the foreign key does not cover the case where erasure anonymises the workspace row). The retention probe script is kept because the observability gate needs a no-SSH discoverability command, but it is now one script that also checks freshness. The runbook-sentence drive-by is kept because the stale line was found during research and costs one line.

**Resolved by sign-off.** The CPO conditions are recorded under Domain Review.

## Decisions Ruled by the CTO Agent

The operator delegated the four open decisions to the CTO (ruled by CTO agent, with the CLO and CPO inputs recorded above). The CLO retains drafting of any text; the CPO and CLO are consulted on PR2 wording.

- **A. Enabling before PR2.** Collection stays off for every external workspace until PR2 ships. Reason: collecting data no member can read, and that owners were never told about, leaves no product path for an Art. 15 request; Better Stack already holds the raw events for 90 days, so volume can be measured without app-database collection. Carve-out: a Jikigai-owned workspace only, as a canary, through a per-org flag override.
- **B. Owners who already have web access on.** A notice is required; a re-confirmation gate is not. The basis is Art. 6(1)(f), not consent, so collection under it needs no gate, but the owner must be told beforehand, and a forced re-confirmation would silently break working agents. The notice goes out at least 7 days before external enablement (that is the PR2 enablement, not PR1), by email to owners of workspaces with `web_egress=true` plus a persistent in-app notice, and owners can opt out by switching the toggle off.
- **C. Toggle off.** Switching it off stops collection and purges nothing in PR1. Denied attempts made while it is off are not stored in the app database (they stay in the 90-day raw log). The RPC checks the toggle's current state, so buffered events from before a toggle-off are dropped.
- **D. 'Off' does not mean 'forget'.** The log exists so owners can account for what agents did, and a purge-on-off would let one toggle erase evidence of other members' agent activity. Retention is already bounded to 30 days. PR2's toggle copy must satisfy the constraints in the PR2 acceptance criteria; exact wording is settled in PR2 planning.

**Still authorizations, not decisions (the operator's):** enabling the flag in production, creating the runtime flag (a typed-`yes` TTY step handed to the operator), and publishing any notice or legal text.

## Phase 0 Results (2026-10-15, work phase)

Measured at work time; these supersede the plan-time assumptions where they differ. Reproduction commands are in the commit that adds this section's tests.

- **0.1 DPIA addendum:** drafted by the CLO at `knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md` with t6/t7 rows in `compliance-posture.md`. Its section 8 lists inconsistencies in the existing public wording (processor vs own lawful basis; "withdraws consent" vs ruling D; "every outbound connection is recorded" over-claim; 30-day vs 90-day copies; PA-2/PA-8 "no new store"). They are inputs to the Phase 6 legal commits, not decisions.
- **0.2 Volume:** Better Stack `soleur-egress-gw`, 8 days: 3,434 decision rows (2026-10-12: 744, 10-13: 1,128, 10-14: 1,120), of which 3,425 are the gateway probe (`workspace=probe`) and 9 are unauthenticated (`workspace=-`). **Zero real-workspace rows.** The WAL estimate therefore stays the CTO's assumption (about 80k rows/day at 1,000 workspaces); real volume stays unmeasured and is a PR2 planning input once any workspace is enabled.
- **0.3 Erasure saga:** `account-delete.ts` plus migration 065 leave the workspace row in place on account erasure (`organizations.owner_user_id` becomes NULL; the orphan workspace remains). `ON DELETE CASCADE` therefore does not erase rollup rows on solo-account erasure. Ruled R3 below.
- **0.4 Delivery:** `squid.conf` is delivered by `terraform_data.egress_gateway{,_web2}` (hash over the conf, helper, deny file and bootstrap), auto-applied on merge, with a `docker restart` (seconds of gateway downtime; no image re-pin). Vector receives Doppler `soleur/prd` secrets via `doppler run`, so `${EGRESS_AUDIT_INGEST_TOKEN:-}` works. Corrections: add the new `random_id` and `doppler_secret` to the main plan/apply `-target` allow-lists in `apply-web-platform-infra.yml` (terraform-target-parity test); state the gateway restart in the PR's first line; the VRL must drop rows with no status field (mixed-version window).
- **0.5 Ingress:** no ingress block exists for `/api/internal/*`, and none is possible: `kb-drift-ingest`, `trigger-cron` and `schedule-reminder` are deliberately public. Ruled R2 below.
- **0.6 Measurements:** (a) Squid 6.13 on the pinned digest: `%un` logs the presented username on a failed login (victim id with a bogus token, and victim id with another workspace's valid token, both logged with `%>Hs` 407): the forged-attribution risk is real. An authenticated allow logs 200, an authenticated policy deny (metadata address) logs 403 attributed to the real workspace. (b) Vector 0.43.1: `${EGRESS_AUDIT_INGEST_TOKEN:-}` passes `vector validate` with the variable unset (default strict mode) and set. `vector validate --no-environment` does **not** compile VRL (a VRL compile error still printed Validated); only `vector test` does. (c) Flood, one workspace with 100,000 unique hosts: 426 MiB peak without a throttle (idle 56 MiB, about 3.7 KB per reduce group), 92 MiB with a cap of 2,000; ten workspaces flooding at once: 162 MiB at a cap of 1,000 and 270 MiB at 2,000.

### Rulings on the Phase 0 findings (ruled by CTO agent)

- **R1. Per-workspace cap = 1,000 events per 900 s** (`throttle`, keyed on the workspace), memory bounded by the cap alone; 2,000 is rejected because it breaches `MemoryMax=256M` at ten flooding workspaces. The contract wording becomes: the set of hosts is exact only while a workspace stays under 1,000 events per window; above it, discarded events can drop hosts. Throttle discards reach no sink today, so PR1 must add a path for them (acceptance criterion below). Revisit the number from real data after enabling.
- **R2. No Cloudflare rule.** The bearer token is the real control; the route also requires a loopback `Host` and rejects any forwarding header (Cloudflare adds `X-Forwarded-For` / `CF-Connecting-IP`, so a request that arrived through it is rejected), compares the token in constant time, returns a bare 401, and is inert when the flag is off.
- **R3. Erasure is a PR1 merge requirement.** New saga step `5.15 erase-egress-audit-rollup` in `account-delete.ts` after 5.14 and before step 6, calling a service-role RPC `erase_egress_audit_rollup(p_workspace uuid)` that hard-deletes by `workspace_id`; idempotent; a failure aborts like the other required steps. It runs for the solo workspace (workspace id equals user id). `ON DELETE CASCADE` stays but is not the erasure path. For team workspaces the workspace persists and rows stay under the 30-day retention (the rows hold no per-user data).
- **R4. `vector test` runs in `validate-vector-config.yml`**, after the "Admission-partition emulator tests" step, using the Vector binary already installed there; the fixture file `apps/web-platform/infra/vector-egress-rollup.test.toml` is added to the workflow's path filters; `vector validate` keeps `--no-environment`.
- **R5. Ingest route order, with the flag evaluated per organisation (ruled by CTO agent).** The canary in decision A needs a per-org override, which a route-level read with no org cannot see. Order: loopback `Host` and no forwarding header (401); no configured secret (2xx drop, never 5xx); wrong bearer (401); body cap, JSON and zod (4xx); per-row bucket bounds; one workspace-to-organisation query; the flag evaluated per distinct org with the identity `{ userId: null, role: "prd", orgId }` (the `Role` type has no `owner`, so the CTO's `role: owner` is read as the environment role); rows of orgs with the flag off are dropped and counted; then the RPC. The CTO's step 1 ("flag fully off for every identity: return 2xx") is subsumed: with every org off nothing is written and the answer is 2xx, and a global pre-check on the anonymous identity would drop the canary, so it is not implemented. The environment default stays OFF.

### Amendments at review of PR #10349 (R6, ruled by CTO agent)

- **R6-A. (amends R2)** `x-forwarded-*` are added by Next.js itself and are no longer rejected; the proxy markers are `cf-ray`, `cf-connecting-ip`, `forwarded`, `x-real-ip` and a multi-hop `x-forwarded-for`. A test pins the Next minor the rule was measured on (16.3.x) so an upgrade re-measures.
- **R6-B. (amends R1)** A second keyless throttle caps the total at 10,000 events per 900 s after the per-workspace one; its discards raise a `SOLEUR_EGRESS_AUDIT_THROTTLED_GLOBAL` marker. The per-key marker now reads `events_discarded_total` (the metric that carries the `key` tag in Vector 0.43.1).
- **R6-C.** The status filter is a positive allowlist `^(200|403|502|503|504)$`.
- **R6-D.** Ingest skips a workspace with no member row and erase deletes only such a workspace, both under a `FOR SHARE` lock on the member rows. An explicit erasure while the account stays open uses the new `erase_egress_audit_rollup_for_requester` (sole member only), not raw SQL. Deviation from the ruling, recorded: no audit row is written, because no audit table exists for this in PR1; the DSAR request record holds the returned count.
- **R6-E.** The ingest RPC catches only `data_exception` and `integrity_constraint_violation`; a system fault raises (route 503, Sentry, Vector retries 10 times). Table CHECKs close `decision`, the host charset, the bucket alignment and the `first_seen <= last_seen` window. Counted per row, never per batch.
- **R6-F.** The retention probe stays unscheduled in PR1; scheduling it is an unchecked precondition in `egress-audit-enable.md` and on #9545.
- **R6-G. (amends R5)** The route refuses to run in production while the global env mirror `FLAG_EGRESS_AUDIT_COLLECTION` is `1`, so a Flagsmith outage cannot open collection for every organisation.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails the deepen-plan gate; this one declares `single-user incident` and therefore needs CPO sign-off before work begins.
- The ordinal `ADR-288` and migration number `162` are provisional: sibling PRs claim them. Re-check at work time; the ship gate re-verifies.
- Strict `${NAME}` interpolation of the egress-ingest token in the shared `vector.toml` would break Vector startup on the inngest host; use only the default-value form `${EGRESS_AUDIT_INGEST_TOKEN:-}` (the file already interpolates `${BETTERSTACK_LOGS_TOKEN}`, validated with dummy values at `server.tf:1445`).
- Merging redelivers Vector to the web hosts immediately (the apply workflow triggers on `apps/web-platform/infra/**`); until the route is deployed the sink's bounded retries drop events, which loses nothing while the pipeline is dark. State this as the first line of the PR body.
- Do not add a member read path, a session id, an IP, a client address or any per-user field without reopening trigger t7.
- The route must return success when the flag is off; returning an error fills the disk buffer and then drops newer events.
