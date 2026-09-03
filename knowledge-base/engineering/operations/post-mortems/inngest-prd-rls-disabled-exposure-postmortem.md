---
title: "soleur-inngest-prd public tables RLS-disabled + anon-reachable (CRITICAL exposure)"
date: 2026-06-29
incident_pr: 5687
incident_window: "≈2026-06-17 (Inngest project provisioned, public tables created without RLS) → 2026-06-29T (lockdown applied)"
recovery_at: "2026-06-29 (advisor rls_disabled_in_public 14 → 0)"
suspected_change: "Supabase auto-grants anon/authenticated full DML on tables created by `postgres`; Inngest's self-hosted schema was created on the project WITHOUT RLS ever being enabled, so PostgREST served every public table to the anon role."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - provider-default-grant (Supabase default privileges auto-GRANT anon/authenticated on postgres-owned tables)
  - missing-control (RLS never enabled on the Inngest backing project's public schema)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — CLO determination: no notifiable personal-data breach (reachability-only; anon/service_role keys never published or committed; access-log dimension INCONCLUSIVE but not positive-evidence-of-access)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The dedicated EU Inngest backing Supabase project `soleur-inngest-prd` (ref `pigsfuxruiopinouvjwy`) had Row-Level Security **disabled** on all 14 public tables, and the `anon` + `authenticated` roles held **full DML** while PostgREST served the public schema. Every Inngest event payload and tenant identifier (`events.event_data`, `event_user`, `account_id`, `workspace_id`, `worker_ip`, `function_runs`, `history`, …) was readable — and writable/deletable — by anyone holding the project's anon key, via the anonymous REST endpoint. Supabase's automated security advisor flagged it (`rls_disabled_in_public`, lint 0013) and emailed the operator a CRITICAL alert, which was routed into `/soleur:go`.

## Status

resolved

## Symptom

Supabase CRITICAL advisor email: "Table publicly accessible. Anyone with your project URL can read, edit, and delete all data in this table because Row-Level Security is not enabled. `rls_disabled_in_public`. Project soleur-inngest-prd." Live verification confirmed the finding was real: `anon` held SELECT/INSERT/UPDATE/DELETE on all 14 public tables and PostgREST exposed the public schema (anon REST reachable; pg_graphql disabled).

## Incident Timeline

- **Start time (detected):** 2026-06-29 (operator forwarded the Supabase CRITICAL email)
- **End time (recovered):** 2026-06-29 (lockdown SQL applied; advisor 14 → 0)
- **Duration (MTTR):** ~hours (same session: detect → verify → GDPR escalation gate → apply → verify)

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-29 | Supabase advisor CRITICAL email received and forwarded into `/soleur:go`. |
| agent | 2026-06-29 | Live-verified the finding REAL: anon+authenticated full DML on 14 public tables; PostgREST serves public schema; pg_graphql disabled. |
| agent | 2026-06-29 | GATE G-ESCALATE run: anon/service_role keys never published or committed (clean tree + full git-history pickaxe); retained edge logs showed zero anon traffic in-window; retention (~1–2d) < exposure window (~12d) → access-log dimension INCONCLUSIVE-but-low-risk. |
| agent | 2026-06-29 | Applied idempotent lockdown SQL as the `postgres` owner via the Management API (ENABLE RLS not FORCE + REVOKE ALL on tables/sequences + ALTER DEFAULT PRIVILEGES REVOKE). |
| agent | 2026-06-29 | Verified: advisor 14 → 0; pg_default_acl anon/auth rows 3 → 0; owner read intact (3603 events); anon read → permission denied (42501); PostgREST anon REST → HTTP 401. |
| agent | 2026-06-29 | Built durable apply + daily self-heal workflow (`apply-inngest-rls.yml`) with an authoritative catalog gate; ADR-030 invariant I8 + C4 refresh. |

## Participants and Systems Involved

Systems: Supabase project `soleur-inngest-prd` (Postgres + PostgREST + Supabase Management API), Inngest (connects as the `postgres` owner over the Supavisor session pooler), GitHub Actions (durable apply + self-heal). Participants: operator (detection/forwarding), Claude Code agent (verification, remediation, durability, this PIR).

## Detection (+ MTTD)

- **How detected:** External monitoring — Supabase's own automated security advisor (`rls_disabled_in_public`), delivered by email. NOT detected by Soleur-side monitoring (we had no check asserting RLS-enabled on the Inngest project).
- **MTTD (mean time to detect):** Advisor first dated 2026-06-22; operator-actioned 2026-06-29 (~7 days advisor→action). True exposure start (project provisioning, ≈2026-06-17) → detection was longer; the Inngest project was never covered by an RLS-posture check.

## Triggered by

provider — Supabase's default-privilege behavior (auto-GRANT anon/authenticated on every `postgres`-owned table) combined with a missing control (RLS never enabled on this project's public schema). No code change in this repo caused it; the project was provisioned out-of-band (the Inngest backing DB is intentionally not a Terraform resource).

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| RLS was never enabled on the Inngest project's public schema, and Supabase default-grants left anon/authenticated with full DML | advisor `rls_disabled_in_public` on all 14 tables; live `has_table_privilege('anon', …)` true; pg_default_acl anon/auth rows present | none | CONFIRMED |

## Resolution

Applied an idempotent SQL lockdown as the `postgres` table owner via the Supabase Management API: `ENABLE ROW LEVEL SECURITY` (NOT `FORCE`, so the owner — Inngest — keeps full access via owner-bypass) with zero policies on all public tables; `REVOKE ALL … FROM anon, authenticated` on every table + sequence (+ matviews, defensively); and `ALTER DEFAULT PRIVILEGES FOR ROLE postgres … REVOKE` on TABLES/SEQUENCES/FUNCTIONS to stop recurrence on future Inngest-version tables. A fail-closed Inngest-sentinel preflight refuses to run against any non-Inngest project. Durable re-apply + daily self-heal ships as `apply-inngest-rls.yml` with an authoritative catalog gate (asserts RLS-on + postgres-owned + neither anon nor authenticated holds SELECT/INSERT/UPDATE/DELETE/TRUNCATE).

## Recovery verification

Live, against production `soleur-inngest-prd` on 2026-06-29: Supabase advisor `rls_disabled_in_public` **14 → 0**; `pg_default_acl` anon/auth rows **3 → 0**; broadened authoritative catalog gate **violations = 0**; owner liveness intact (`set local role postgres; select count(*) from public.events` → 3603, later 3742); anon path denied (`set local role anon` → SQLSTATE 42501); PostgREST anon REST → HTTP 401; pg_graphql confirmed disabled (no second front door).

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was the data anon-reachable?** PostgREST served the public schema and the `anon` role held SELECT/DML on every public table.
2. **Why did anon hold those grants?** Supabase default privileges auto-GRANT `anon`/`authenticated` full DML on every table created by the `postgres` role, and nothing revoked them.
3. **Why did RLS not stop it?** RLS was never enabled on this project's public schema — RLS is opt-in per table, and the Inngest schema was created without it.
4. **Why was RLS never enabled?** The Inngest backing DB is provisioned out-of-band (intentionally not a Terraform resource, mirroring the `INNGEST_POSTGRES_URI` treatment); the out-of-band path had no RLS-posture step and no check asserting one.
5. **Why was the gap not caught for ~12 days?** No Soleur-side monitoring asserted RLS-enabled / anon-no-grant on the Inngest project — detection relied entirely on Supabase's advisor email. (Now closed: `apply-inngest-rls.yml`'s daily authoritative catalog gate fails loud on any regression.)

## Versions of Components

- **Version(s) that triggered the outage:** n/a — provisioning-state misconfiguration, not a deployed code version. The Inngest schema (goose-migrated) created tables without RLS since project provisioning.
- **Version(s) that restored the service:** `apps/web-platform/infra/inngest-rls/0001_enable_rls_lockdown.sql` applied 2026-06-29; durability via `apply-inngest-rls.yml` (merge-trigger + daily schedule).

## Impact details

### Services Impacted

No availability impact — Inngest connects as the `postgres` owner and was never affected (owner-bypass preserves access under non-forced RLS; verified). The impact was **confidentiality/integrity exposure surface**, not an outage: durable run-state was theoretically readable/writable/deletable by an anon-key holder for the exposure window.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface.

- Prospect: none (no prospect data in the Inngest backing DB).
- Authenticated app user: **potential** confidentiality exposure — Inngest event payloads carry tenant ids / account/workspace identifiers and worker IPs; an anon-key holder could in principle have read them. No evidence of actual access (zero anon traffic in retained logs; keys never published). No data loss occurred.
- Legal-document signer: none (no legal-doc data in this DB).
- Admin via Access: none.
- Billing customer: none (no billing/payment data in this DB).
- OAuth installation owner: indirect only — installation-related ids could appear in event payloads; same potential-but-unevidenced exposure as authenticated users.

### Revenue Impact

None. No outage, no churn event, no refund.

### Team Impact

One focused remediation session (detect → verify → GDPR gate → apply → durability → docs). No on-call escalation.

## Lessons Learned

### Where we got lucky

The anon and service_role keys were **never published or committed** — that precondition, not log evidence, is what let the CLO reach "no notifiable breach." Had a key leaked during the ~12-day window, the short log retention would have left us unable to prove or disprove access (the access-log dimension was already INCONCLUSIVE for that reason). We were also lucky the connection role is the table owner, so the non-forced-RLS lockdown was non-breaking.

### What went well

The GATE G-ESCALATE discipline (key-exposure check + retention horizon + access-log analysis) produced an honest, defensible determination instead of a hand-wave. The remediation was non-breaking by construction (owner-bypass reasoning, verified live before and after). The fix was made durable (self-heal workflow) rather than a one-shot manual apply.

### What went wrong

An out-of-band-provisioned production database carried personal-data-bearing tables with RLS disabled and anon-full-DML for ~12 days, undetected by any Soleur-side control. Detection depended entirely on the provider's advisor email. The verification gap nearly shipped, too: the first self-heal gate asserted only `anon SELECT`, missing the brand-fatal `TRUNCATE`/`DELETE` vector (RLS does not gate TRUNCATE) — caught by convergent multi-agent review and fixed in-PR.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur. The core recurrence vector (RLS re-disabled or a new Inngest-version table re-exposed) is **fully closed in the source PR**: `ALTER DEFAULT PRIVILEGES … REVOKE` stops new-table auto-grants, and `apply-inngest-rls.yml`'s daily authoritative catalog gate re-locks + fails loud on any regression. The one residual is investigability, not recurrence:

| Issue | Action | Status |
|---|---|---|
| #5697 | Raise `soleur-inngest-prd` log retention (or ship logs to a durable sink) so a future exposure window can be analyzed end-to-end — turns a future INCONCLUSIVE access-log determination into a conclusive one. | open |

<!-- ADDENDUM-2026-08-26 START -->

## Addendum — 2026-08-26 (annotation only; nothing above is corrected)

Everything above is a true record of the 2026-06-29 incident and response. This note is
appended rather than merged in, because the figures it qualifies were accurate when written.

**The "~1–2 days" retention figure appears twice** — in the timeline row for the GATE
G-ESCALATE run, and in "Where we got lucky". Both are left as recorded: they are what was
measured on 2026-06-29. Re-measured on 2026-08-26, the aggregate retained span on this project
is materially longer.

**That longer span does not make the access-log dimension conclusive, and #5697 stays open.**
The determination's evidentiary claim rests on `edge_logs`, which produced **zero rows across
the entire 30-day live period** — it is uninstrumented on this project, so its zero is an
instrumentation gap, not evidence of no traffic. Retaining more of a signal that is never
emitted recovers nothing. The INCONCLUSIVE treatment is reinforced, not overturned.

#5697 asks to raise retention **or** ship logs to a durable sink. Revocable vendor-side
retrievability satisfies neither limb, and the durable-sink limb is untouched, so the item
remains open and the "residual is investigability" framing above still holds.

**Tooling migration.** The Management API log endpoint used for the access-log analysis is
deprecated, with removal announced for 2026-09-23, and replaced by a unified log stream taking
ClickHouse SQL. Access-log queries now go through `scripts/supabase-logs-query.sh`, which
returns a coverage verdict with every result — so the specific trap this incident's
investigation had to reason around by hand (a zero that means "not retained" or "not
instrumented" rather than "no traffic") is now answered by the tool.

**The GATE G-ESCALATE discipline praised in "What went well" now has a durable home.** It
existed only as a blockquote in the source plan; it is now
`knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md`, with
`triggers:` frontmatter so the incident skill can route to it by symptom. Tool runbook:
`knowledge-base/engineering/operations/runbooks/supabase-log-query.md`.

**Measurement source.** `knowledge-base/engineering/operations/references/supabase-management-api-log-contract.md`
(§Confirmed from the plan, finding E). Cite it rather than restating its figures.

**Sibling records carrying the same addendum:**

- `knowledge-base/project/specs/feat-one-shot-inngest-prd-rls-enable/gate-g-escalate-evidence.md`
- `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`

<!-- ADDENDUM-2026-08-26 END -->

<!-- MARKER-2026-09-03 START -->

> **Pointer — 2026-09-03 (#7717).** A second annotation-only addendum was added to the
> canonical determination at
> `knowledge-base/legal/audits/2026-06-29-inngest-prd-rls-reachability-gdpr-determination.md`
> ("Addendum — 2026-09-03"). In short: the 2026-08-26 correction addressed `edge_logs`
> only; `auth_logs` is instrumented and its zero retains weak evidentiary value; and
> `postgrest_logs` — the instrumented source that records REST traffic on this project —
> was never queried and that window is now unrecoverable. **The verdict is unaffected.**
> This is a pointer, not a third copy: read the addendum at the canonical record.

<!-- MARKER-2026-09-03 END -->
