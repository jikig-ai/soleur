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

Per the binding CTO ruling the work splits in three. This plan specifies the first two in full and the third at design level only:

- **PR1a: dark ingest pipeline.** A Vector rollup of the gateway log into 15-minute per-workspace buckets, an HMAC-authenticated ingest route, a workspace-keyed table that no member can read yet, a 30-day retention sweep, a kill-switch flag defaulting off, plus the ADR, C4 edge and DPIA addendum.
- **PR1b: legal wording and registers.** The public-document sentences and register rows the CLO identified, landing before the collection flag is ever turned on.
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
| Member `SELECT` policy in PR1a | P1 | A readable table is a viewer in fact and would trigger the DPIA t6 re-screen at PR1. CLO: ship RLS on with no member policy; the policy lands in PR2. |
| New Inngest prune function | P5 | Would add a Sentry cron monitor, which the two-PR rule forbids routing in the PR that creates it. `pg_cron` retention sweeps already exist (migrations 029, 038, 041). |
| Destination view and wireframe | P1 | Deferred to PR2 by the ruled split. |

**Learnings applied.** Reading Better Stack from the app is contradicted by the log-query runbook (three credentials, only the operator-held one reads content). Per-event inserts conflict with the WAL learning, so the rollup happens before the app. Workspace-attributed host data is personal data and earlier per-user histories were steered to aggregates. Tenant-side writes fail silently without an RPC (RLS plus column grant), so writes go through a `SECURITY DEFINER` function with no tenant `INSERT` policy. The viewer must filter by `workspace_id` with the same predicate as RLS (client/server mismatch learning). Committed `.pen` files must be committed before Pencil opens them (PR2).

## Research Reconciliation: Spec vs. Codebase

| Claim in the issue or brief | Reality | Plan response |
|---|---|---|
| Per-session CONNECT decision logs | Fields are workspace, host, decision, bytes, time; no session or user id | Records are per workspace and bucket. No session field is added. |
| Decision lines reach journald via stdout | Unverified in code (`access_log` writes a file in the container) | Measured working in Better Stack; add an ingest-side freshness signal so a future break is visible (see Observability). |
| Grant stored as a scope grant | Stored as `workspaces.web_egress` (migration 158, RPCs `get_workspace_web_egress`, `set_workspace_web_egress`) | Reuse `is_workspace_member` for the read predicate in PR2; no scope-grant coupling. |
| Route `app/api/egress-audit/route.ts` | Absent | PR2 creates the read route; PR1a creates only an internal ingest route. |
| Runbook says journald is at default size | `journald-soleur.conf` now sets a 1G cap | Correct the runbook sentence in PR1a docs edits. |

## Ruled Design (binding inputs)

**Ingestion (CTO fork 1: aggregated spool, rollup in Vector).**

- Vector reads `sources.egress_gw_journald` directly (not the PII-scrub chain) and applies a `reduce` keyed on `workspace`, `requested_host`, `decision` over 15-minute windows, emitting `count`, `sum(bytes_out)`, `first_seen`, `last_seen` per closed bucket.
- Stored fields: `workspace_id, bucket_start, requested_host, decision, source_host, request_count, bytes_out, first_seen, last_seen`. Not stored: `resolved_ip, client, duration_ms`, any user, session, path or IP value.
- Delivery: Vector's HTTP sink cannot sign a whole batch, so each rollup event carries its own HMAC computed in VRL (`hmac()` is already used in `vector.toml`); the app verifies per row, with a timestamp and replay window and a request-body cap. The sink uses a bounded disk buffer with `drop_newest` on overflow.
- Target: `http://127.0.0.1:3000/api/internal/egress-audit-ingest` (Vector and the app share the host; no firewall change, per the IaC read of ADR-052 and the inbound-only Hetzner firewall).
- Write path: route validates with zod, then calls one `SECURITY DEFINER` RPC that batch-upserts with `GREATEST` on conflict, key `(workspace_id, bucket_start, requested_host, decision, source_host)`. The workspace foreign key is a second check that rejects unknown workspaces.
- With the flag off the route returns 2xx and drops the batch, so the sink never retries into a full buffer.

**Counting semantics (resolves a tension between the CTO's `GREATEST` upsert and Vector's in-memory reduce state).** A Vector restart loses partial buckets, so a bucket can be emitted twice with different partial counts. `GREATEST` keeps the larger and makes retries idempotent, but undercounts across a restart. The contract is therefore: **the set of hosts contacted and the decision are exact; counts and byte totals are best-effort lower bounds.** PR2's copy must say so, and an acceptance criterion pins it.

**Authorization (CTO fork 2).** Any workspace member may read, by `is_workspace_member(workspace_id, auth.uid())`, the same predicate in RLS and in the route, with the user-scoped client (not the service role). Confirm the predicate excludes pending and removed members. In PR1a the table has RLS enabled and **no** policy for members; only the RPC path writes, and nothing reads.

**Retention.** Engineering ceiling and recommended value: 30 days, hard-deleted daily on `last_seen`, plus `ON DELETE CASCADE` from the workspace. Mechanism: a `pg_cron` job defined in the migration calling a bounded batched-delete function (precedent: migrations 029, 038, 041). The legal number remains the CLO's call and is a merge gate for PR1b.

## Implementation Phases (PR1a)

### Phase 0: gates before code

1. Write the DPIA screening addendum (CLO): record that the rollup changes the facts of the 2026-10-05 memo (app-database persistence, a 30-day store, a table that will become member-readable), that WP248 "systematic monitoring of employees" is now partly engaged, and add trigger **t7**: retention above 30 days, or any user, session, IP or path field added. The full t6 re-screen (viewer lands) stays a PR2 merge gate.
2. Measure real daily CONNECT volume from the Better Stack copy (self-pull, 7-day window if retained) and record rows/day and the resulting rollup row estimate in this plan before the migration is written. This sizes the WAL estimate; the CTO's figure (about 80k rows/day at 1,000 workspaces) is the starting assumption, not the measurement.
3. Decide, via the surfaced operator decisions below, whether PR1a may be enabled before PR2 exists. PR1a ships dark regardless.

### Phase 1: migration (RED tests first)

`apps/web-platform/supabase/migrations/162_workspace_egress_audit_rollup.sql` (re-check the number at work time; 161 is the latest today) with `.down.sql`, `supabase/verify/162_*.sql`, and `test/supabase-migrations/162-*.test.ts`.

- Table `workspace_egress_audit_rollup` with the composite primary key above, `decision` constrained to the known Squid values, `request_count`, `bytes_out` non-negative, `workspace_id` FK `ON DELETE CASCADE`.
- `ENABLE ROW LEVEL SECURITY`; `REVOKE INSERT, UPDATE, DELETE, SELECT` from `anon` and `authenticated` (as in migration 058); no member policy in this migration.
- `ingest_egress_audit_rollup(rows jsonb)`: `SECURITY DEFINER`, `search_path` pinned including `pg_temp`, `GRANT EXECUTE` to `service_role` only, bounded row count per call, rejects unknown workspaces.
- `prune_egress_audit_rollup(retention interval)` batched delete, scheduled with `pg_cron` daily.
- Register both RPCs in `test/rls-fuzz/rpc-cases.ts`.

### Phase 2: ingest route and server module (RED tests first)

`app/api/internal/egress-audit-ingest/route.ts` (HTTP-method exports only) delegating to `server/egress-audit-ingest.ts`: body cap, per-row HMAC verification with constant-time compare and a replay window, zod schema, flag gate (`getFlag`), tenant-client-free service path calling the RPC, Sentry mirror on every failure path via the repo's silent-fallback helper. Follows the `kb-drift-ingest` internal-route pattern.

### Phase 3: Vector config (RED tests first)

`apps/web-platform/infra/vector.toml`: the `reduce` transform fed from `egress_gw_journald`, a VRL step that signs each row with `get_env_var()` (never `${...}` interpolation, because the file is shared with the dedicated inngest host that lacks the secret), and a new HTTP sink with a bounded disk buffer. Add a `vector-egress-rollup` test file with fixtures, extend the admission-test model for the new sink, and keep `validate-vector-config.yml` green.

### Phase 4: secret and delivery

Terraform carrier for the HMAC key following `github-app.tf`: a `random_id` plus a `doppler_secret` in project `soleur`, config `prd`, masked, with no Terraform variable and no default (`hr-tf-variable-no-operator-mint-default`). The same `prd` secret reaches the app and Vector (Vector already runs under `doppler run --config prd`), so no unit or drop-in change is needed. The secret must exist before Vector is redelivered. Delivery to running hosts uses the existing push apply for `terraform_data.journald_persistent` and `journald_persistent_web2` (`vector-redeliver` covers web-1 only; web-2 needs the push apply), which is a hash-triggered replace of those provisioners with a validate-and-restore gate: no host replace, no serving downtime, journald cursor-resumed so no log gap. This is the documented exception to `hr-prod-host-config-change-immutable-redeploy`: `vector.toml` is declared, hashed configuration with a validated reload.

### Phase 5: documentation carried by PR1a

ADR (below), the C4 edge (below), the DPIA addendum from Phase 0, the runbook sentence correction, and the one-line ADR-281 correction: its Consequences bullet about the `image_cve_scan` monitor still says the forced-error acceptance "is not yet observed". Reword to: the workflow fired with an email action on 2026-10-15; mailbox receipt unobserved. This rides this PR rather than a standalone PR (CTO ruling).

### Phase 6: enablement (not part of the merge)

Turning the flag on in production is a separate, operator-authorized step after PR1b has merged and the DPIA addendum is filed. It is not performed by this PR.

## Files to Create

- `apps/web-platform/supabase/migrations/162_workspace_egress_audit_rollup.sql`, `.down.sql`
- `apps/web-platform/supabase/verify/162_workspace_egress_audit_rollup.sql`
- `apps/web-platform/test/supabase-migrations/162-workspace-egress-audit-rollup.test.ts`
- `apps/web-platform/app/api/internal/egress-audit-ingest/route.ts`
- `apps/web-platform/server/egress-audit-ingest.ts`
- `apps/web-platform/test/egress-audit-ingest.test.ts`
- `apps/web-platform/infra/vector-egress-rollup.test.sh` and fixtures under `apps/web-platform/infra/test-fixtures/`
- `knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md` (confirm next free ordinal at work time; the ship gate re-verifies)
- `knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md`

## Files to Edit

- `apps/web-platform/infra/vector.toml`
- Terraform for the HMAC secret (extend the existing Doppler secrets file or add alongside `github-app.tf`)
- `apps/web-platform/lib/feature-flags/server.ts` (new env flag name) and `.env.example`
- `apps/web-platform/test/rls-fuzz/rpc-cases.ts`
- `apps/web-platform/test/infra/vector-admission.test.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and `views.c4` if the edge must render)
- `knowledge-base/engineering/architecture/decisions/ADR-281-image-cve-scan-advisory-first-promoted-on-measured-fp-criterion.md` (one-line correction)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (stale journald sentence)
- `knowledge-base/legal/compliance-posture.md` (t6 addendum and t7 rows)

PR1b edits (separate PR): `docs/legal/privacy-policy.md` (line near 197 and section 7), `docs/legal/acceptable-use-policy.md` (near 319), `docs/legal/data-protection-disclosure.md` (near 230), `docs/legal/gdpr-policy.md` (new entry), each mirrored under `plugins/soleur/docs/pages/legal/`, and `knowledge-base/legal/article-30-register.md` (PA-2, PA-8), `article-30-2-register.md`, `compliance-posture.md`.

## Open Code-Review Overlap

None. Five planned or likely-touched files (`vector.toml`, `egress-gateway-squid.conf`, the Scope Grants page, the web-egress toggle, `workspace-action-audit`) were checked against all open `code-review` issues; no body names any of them.

## User-Brand Impact

- **If this lands broken, the user experiences:** a workspace owner who has enabled agent web access never sees the audit view populated, or sees counts that are lower than reality after a Vector restart; in PR1a nothing user-visible changes because the pipeline is dark.
- **If this leaks, the user's workflow is exposed via:** a record attributed to the wrong workspace (a forged or misrouted `workspace` value accepted by the ingest route, or an RLS gap in PR2) revealing which external hosts one workspace's agents contacted, which can disclose what a founder asked an agent to research.
- **Brand-survival threshold:** single-user incident

CPO sign-off is required at plan time before `soleur:work` begins (frontmatter `requires_cpo_signoff: true`); `soleur:engineering:review:user-impact-reviewer` runs at review time. Mitigations designed in: attribution comes from the gateway's token-bound `%un` (not client-supplied), the workspace FK rejects unknown ids, per-row HMAC with a replay window, no tenant write policy, RLS with no member policy until PR2, and a cross-tenant read test as an acceptance criterion.

## Observability

```yaml
liveness_signal:
  what: ingest freshness - the newest bucket_start per sink host is within 40 minutes while the flag is on and workspaces have web access enabled; emitted as a structured SOLEUR_EGRESS_AUDIT_INGEST marker per accepted batch (batch size, rows, newest bucket) and a Vector sink heartbeat in Better Stack
  cadence: every 15-minute bucket flush
  alert_target: Better Stack log alert on marker absence while the flag is on (mirrors the egress_gw_probe_silent pattern in betterstack-logs-alerts.tf), routed to the existing on-call heartbeat policy
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf and apps/web-platform/infra/vector.toml
error_reporting:
  destination: Sentry via the repo's silent-fallback mirror for every ingest failure path (HMAC reject, schema reject, RPC error, body over cap); Vector sink errors reach Better Stack through the existing vector-internal-logs source
  fail_loud: true
failure_modes:
  - mode: Vector restarts and loses partial buckets
    detection: counts undercount; set of hosts stays exact; documented as best-effort in the contract
    alert_route: none (accepted by design); AC pins the wording
  - mode: ingest route rejects everything (key drift between Vector and app)
    detection: SOLEUR_EGRESS_AUDIT_INGEST marker absent while Vector shows sink 401s; Sentry event per reject
    alert_route: Better Stack marker-absence alert plus Sentry
  - mode: disk buffer fills (app down or flag mis-set)
    detection: Vector internal metric buffer_discarded_events and a log line on drop_newest
    alert_route: Better Stack alert on the Vector internal-logs source
  - mode: retention sweep stops running
    detection: a probe asserting no row with last_seen older than 35 days
    alert_route: the discoverability script below, run by the existing scheduled supabase watchdog or a follow-through
  - mode: gateway log stops reaching Better Stack (stdout path breaks)
    detection: egress_gw_probe_silent alert already exists
    alert_route: existing Better Stack policy
logs:
  where: Better Stack (ingest markers, Vector internal logs) and Sentry (failures); the table itself is not a log
  retention: 90 days in Better Stack; 30 days for table rows
discoverability_test:
  command: bash scripts/egress-audit-retention-check.sh
  expected_output: "OK or UNAVAILABLE"
```

The retention probe script is a committed repo-relative file created in Phase 1 (it reads through the supabase REST path the preflight runbook already uses and prints `OK`, or `UNAVAILABLE` when credentials are absent, never a pass on a failed read). Its path is listed under Files to Create at work time. The liveness marker is emitted from stdout so a blind sandbox is not involved.

## Encryption Posture

```yaml
at_rest:
  - store: supabase.prd table workspace_egress_audit_rollup
    mechanism: provider-managed:Supabase platform disk encryption (named attestation recorded in the existing encryption-posture ledger for supabase.prd)
    evidence: knowledge-base ledger row for supabase.prd resolved by scripts/lint-encryption-posture.py
    defends_against: a seized or snapshotted database volume
    does_not_defend: a leaked service-role credential, an RLS bypass, or a SQL injection reading the table
    disclosed_as: not-publicly-claimed until PR1b wording lands
    live_verification: unavailable:no per-table attestation endpoint
in_transit:
  - connection: Vector -> app ingest route (loopback, same host)
    enforced_at: apps/web-platform/infra/vector.toml sink uri and server/egress-audit-ingest.ts
    tls: none on the loopback hop (plain HTTP to 127.0.0.1)
    cert_verification: off
    does_not_defend: any local process able to bind or sniff loopback on the host; integrity rests on the per-row HMAC, not transport
    disclosed_as: not-publicly-claimed
exception:
  justification: loopback-only hop on a single host where Vector and the app are co-resident; per-row HMAC provides authenticity and replay protection
  tracking_issue: "#9545"
  reevaluate_when: Vector or the ingest route moves to a different host or network namespace
  expires_on: 2027-01-13
```

## Infrastructure (IaC)

### Terraform changes

HMAC key as `random_id` plus `doppler_secret` (project `soleur`, config `prd`, masked), modelled on `github-app.tf`. No `variable`, no default. Provider versions unchanged.

### Apply path

Push apply of `terraform_data.journald_persistent` and `terraform_data.journald_persistent_web2` after merge (hash-triggered re-provision with validate and restore). Not a host replace; no serving downtime; Vector restarts with a 20 second settle window.

### Host fan-out

Gateway and Vector run on the web hosts only: `egress_gateway` and `egress_gateway_web2`. web-2 is a `twin` already covered by `journald_persistent_web2`. The inngest host receives the same `vector.toml` but runs no gateway, so the new transform is inert there (hence `get_env_var()`).

### Distinctness / drift safeguards

`vector.toml` is not in the `deploy_pipeline_fix` trigger list, so no list edit is needed; no new pushed file is added, so `FILE_MAP`, `hooks.json.tmpl` and the ship-gate trigger list are untouched. A new `prd` secret needs no doppler-config-inventory change.

### Vendor-tier reality check

Better Stack free tier: 3 GB per month and 3-day retention applies to the free plan; the measured source shows 90-day retention in force, so the raw copy is not the constraint. The new sink adds no Better Stack volume.

## Architecture Decision (ADR/C4)

### ADR

Create `ADR-288` (ordinal provisional): "Aggregated egress audit spool via Vector to app ingest". Decision: roll up before the app, sign per row, write through a single `SECURITY DEFINER` function, no member read until PR2, 30-day retention. Alternatives Considered table records the two rejected forks and the rejected member policy in PR1a, each with the CTO and CLO reasoning above. Status "adopting" until PR2 ships. Carry the ADR-281 one-line correction in the same PR.

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
**Assessment:** CLO: the rollup is personal data (pseudonymous at best; directly identifying in a solo workspace). Jikigai is controller for solo workspaces and processor for team workspaces, and an independent controller of the 90-day raw log. DPIA t6 literally fires at the viewer (PR2) but PR1 changes the memo's facts, so an addendum precedes PR1 and PR1 ships with no member read. Retention 30 days under Art. 6(1)(f), cascade on workspace delete. Existing sentences in the privacy policy, acceptable-use policy and data-protection disclosure over-claim an audit log owners cannot see and need temporal qualifiers; the GDPR policy has no entry for the gateway at all. Draft wording is for counsel review and is carried by PR1b.

### Product/UX Gate

**Tier:** advisory (deferred)
**Decision:** skipped for PR1a: no user-facing file in its Files lists, so the mechanical UI-surface override does not fire. PR2 will run the BLOCKING pipeline (spec-flow, CPO, and a new wireframe for the destination view, since the approved `.pen` shows only the link).
**Agents invoked:** none for PR1a
**Skipped specialists:** soleur:product:design:ux-design-lead (no UI surface in PR1a; required at PR2 planning)
**Pencil available:** N/A (no UI surface in PR1a)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A read path from per-session CONNECT decision logs to the workspace owner" [issue #9545] | Ruled Design (ingestion); Phases 1-4 | mapped (PR2 completes the read side) |
| 2 | "either (a) a spool/table the app reads ... or (b) a minimal settings UI view" [issue #9545] | Ruled Design; PR2 | mapped (a) in PR1a, (b) in PR2 |
| 3 | "Needs: ingestion path (Better Stack query API or journald-side spool), authz scope, empty state, and the wireframe's link wired to a real destination." [issue #9545] | Ingestion and authorization rulings; empty state and link | mapped ingestion and authz; empty state and link descoped to PR2 - justification: they need the destination view and its wireframe |
| 4 | "the DPIA re-screen (memo knowledge-base/legal/ ... 2026-10-05-dpia-screening-agent-web-egress.md, trigger t6, 're-run before merge once the viewer lands') is a PLAN DELIVERABLE and merge gate" [brief] | Phase 0.1, PR2 merge gate | mapped |
| 5 | "the plan must settle two open design forks: authorization scope ... and ingestion path" [brief] | Ruled Design | mapped |
| 6 | "if a spool table is chosen include a write-frequency and WAL estimate" [brief] | Phase 0.2, Observability | mapped |
| 7 | "UI work needs a wireframe per wg-ui-feature-requires-pen-wireframe" [brief] | Product/UX Gate (PR2) | descoped to PR2 - justification: PR1a has no UI file |
| 8 | "Fold that one-line correction into this plan's first ADR or doc-touching PR" [brief] | Phase 5, Files to Edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Migration 162, RPC, table | "a spool/table the app reads" | asked |
| Ingest route and server module | "ingestion path (Better Stack query API or journald-side spool)" | asked |
| Vector rollup transform and sink | "ingestion path ... journald-side spool" | asked |
| HMAC secret Terraform carrier | — | inferred - justification: the ingest route must authenticate its caller or any local process could forge workspace data |
| Kill-switch flag | — | inferred - justification: CTO ruling requires a dark ship and a no-deploy off switch (P5) |
| pg_cron retention sweep | — | inferred - justification: CTO and CLO both bound retention; an unswept table breaches Art. 5(1)(e) |
| DPIA addendum and t7 trigger | "the DPIA re-screen ... is a PLAN DELIVERABLE" | asked |
| ADR-288 and C4 edge | — | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable` requires the record with the decision |
| Retention probe script | — | inferred - justification: the observability gate requires a no-SSH discoverability command |
| ADR-281 correction | "Fold that one-line correction into this plan's first ADR or doc-touching PR" | asked |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform`, `knowledge-base`, `docs`, `plugins/soleur` (the last two only through PR1b's legal mirrors)
- Planned files: about 20 | Estimated changed lines: about 750
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split - PR1a (dark pipeline: `apps/web-platform`, ADR, C4, DPIA addendum, ADR-281 line), PR1b (public legal wording and registers, landing before the flag is enabled), PR2 (read route and card, planned after volume is measured)

## Acceptance Criteria

### PR1a

- [ ] A cross-tenant test proves a record written for workspace A is unreadable by a member of workspace B and by a member of workspace A (no member policy exists).
- [ ] The ingest route rejects: a missing or bad HMAC, a replayed timestamp, an unknown workspace, an oversize body, and a malformed row; each rejection is mirrored to Sentry.
- [ ] With the flag off the route returns 2xx and writes nothing.
- [ ] The RPC is executable by `service_role` only; `anon` and `authenticated` have no table privileges.
- [ ] The retention sweep deletes rows older than 30 days in bounded batches and is verified by a test that inserts an aged row (this table is not WORM-protected, so no trigger blocks the delete).
- [ ] `vector validate` passes; the new sink has a bounded disk buffer with `drop_newest`; the signing step uses `get_env_var()`; the admission test and the new rollup test pass.
- [ ] A measured rows/day figure from the real gateway log and the resulting WAL estimate are recorded in this plan before the migration is written.
- [ ] Counts are documented and tested as best-effort lower bounds; the set of hosts and decisions is exact.
- [ ] ADR-288, the C4 edge and the DPIA addendum (with trigger t7) are committed; `c4-count-parity` and the C4 render tests pass.
- [ ] ADR-281's stale sentence is corrected with "workflow fired with email action; receipt unobserved".

### PR1b

- [ ] Each public sentence the CLO flagged carries a temporal qualifier or the corrected fact, mirrored under `plugins/soleur/docs/pages/legal/`, with the retention number the CLO confirms.
- [ ] Article 30 register rows (PA-2, PA-8, processor-capacity) and the `compliance-posture.md` rows are added.

### PR2 (recorded here, planned later)

- [ ] DPIA t6 re-screen completed before merge; member `SELECT` policy and route share `is_workspace_member`; wireframe for the destination view committed first.

## Test Scenarios

- Given a valid signed row for workspace A, when the route is called with the flag on, then one bucket row exists and a second identical call leaves the row unchanged.
- Given two partial rows for one bucket (a Vector restart), then the stored count equals the larger.
- Given a row for a nonexistent workspace, then the RPC rejects it and no other row in the batch is lost.
- Given a signed row older than the replay window, then it is rejected.
- Given a member of workspace B querying through PostgREST with a user token, then zero rows and no error that reveals existence.
- Given the flag off and Vector sending, then the sink sees 2xx and the buffer does not grow.
- Given a row aged 31 days, when the sweep runs, then it is deleted; a 29-day row is kept.
- Given `vector.toml` with the new transform on the inngest host (no gateway), then Vector starts and the transform emits nothing.

## Operator Decisions (surfaced, not decided)

- Whether collection may be enabled in production before PR2 exists. If yes, public disclosure is due at enablement and PR1b must merge first; if no, the flag stays off until PR2.
- Whether owners who already have web access switched on receive an Art. 13(3)-style notice or a re-confirmation that a member-visible record will exist.
- Publishing or declining any user notice, and the toggle's confirmation copy at PR2.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails the deepen-plan gate; this one declares `single-user incident` and therefore needs CPO sign-off before work begins.
- The ordinal `ADR-288` and migration number `162` are provisional: sibling PRs claim them. Re-check at work time; the ship gate re-verifies.
- `get_env_var()` is mandatory in `vector.toml`; any `${NAME}` interpolation breaks Vector startup on the inngest host.
- The HMAC secret must exist in `soleur/prd` before Vector is redelivered, or every row is signed with an empty key and rejected.
- Do not add a member read path, a session id, an IP, a client address or any per-user field without reopening trigger t7.
- The route must return success when the flag is off; returning an error fills the disk buffer and then drops newer events.
