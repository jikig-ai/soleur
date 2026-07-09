# ADR-102: Beta-CRM capture store — per-tenant Supabase, owner-private, agent-native, extraction-ready

- **Status:** adopting (Phase 1 migration + agent path + DSAR wiring ship; the capture skill and any UI surface are deferred follow-ups)
- **Date:** 2026-07-07
- **Deciders:** Operator; drafted via `/soleur:go` → brainstorm → plan → this ADR. Domain sign-offs carried forward from the brainstorm §Domain Assessments (CPO, CLO, CTO, CRO, COO, CFO).
- **Related:** ADR-066 (operator email-triage inbox — the owner-private-PII + Article-30 precedent), ADR-038/ADR-073 (workspace ownership model), mig 075 (`conversations` `visibility='private'` owner-only RLS template), mig 102 (`email_triage_items` WORM/RLS/anonymise template), #6165 (feature), #6166 (deferred standalone-product revisit), #6163 (Sourcing Options Canvas workflow). Validation: `knowledge-base/product/validation/2026-07-07-agent-operated-crm-validation.md`.

> **Ordinal.** Renumbered ADR-098 → **ADR-102** at `/work` start: sibling PR `feat-one-shot-5739-auth-wal-reduction-v2` landed `ADR-098-soleur-owns-auth-flow-state-retention.md` (plus ADR-099/100/101) between plan authoring and implementation, so 098–101 were taken; 102 was the next free ordinal against `origin/main`. The migration was likewise renumbered 123 → **126** (siblings landed 123/124/125). `/ship`'s ADR-Ordinal Collision Gate re-verifies against `origin/main` at merge and after every Phase-7 sync; on a further collision, sweep the feature artifact set (`grep -rn 'ADR-102' knowledge-base/project/{plans,specs}/feat-beta-conversation-capture/` + this file + the migration/code seed) in the same edit.

## Context

The operator is onboarding Soleur's first beta testers and has had many conversations carrying both **sales** signal (interest, objections, deal potential) and **product** signal (pain points, feature requests). There is no private, structured home for these conversations. The one embryonic precedent — `knowledge-base/support/community/user-conversations/2026-03-12-ex-colleague-bss-ai.md` — is an anonymized markdown record stored where neither `cro` nor `cpo` looks, with no PII boundary.

The capture holds **third-party PII shared under implied confidence** (names, employer, role, email, verbatim conversation content). Two forces make the storage boundary an architectural decision rather than a coding detail:

1. **Compliance blast radius.** Git-committed third-party PII is an Art. 17 erasure impossibility (git history is permanent) and is invisible to the commit secret-scanner (which is PII-blind). An RLS gap or a mis-scoped query exposes every prospect in a workspace — a trust rupture and a GDPR breach (Art. 33, 72h clock). Brand-survival threshold: **single-user incident**.
2. **Reusable capability, not a one-off.** This ships as a **per-tenant Soleur capability every future workspace inherits** — so the multi-tenancy + compliance scaffolding is part of the feature, and the code is a candidate to **extract later as its own agent-operated CRM product** (validation #6166: NOT-NOW as a standalone, build-as-module now, spin-out on explicit triggers). Clean module boundaries are therefore a first-class design goal.

The storage/engine decision was taken across the full four-way Sourcing Options Canvas (this case motivated workflow #6163). The alternatives record is §Alternatives Considered below.

## Decision

Build the capture store as **per-tenant Supabase Postgres tables inside the existing app DB**, owner-private, written and read by agents through an in-process MCP tool that calls `auth.uid()`-pinned SECURITY DEFINER RPCs, joined to the existing DSAR/erasure machinery, and organized behind a clean `crm` module seam for later extraction. No third-party PII is ever committed to git.

Concretely:

### 1. Storage boundary — extend the app DB, do not build/buy/self-host a CRM

Third-party PII lives in new per-tenant Supabase tables that inherit the existing RLS + DSAR + retention machinery. **Not** git markdown (permanent + secret-scan-blind), **not** an external SaaS CRM (new sub-processor, US-residency/CLOUD-Act, DPA + Art. 30), **not** a self-hosted OSS CRM (a whole second app to operate; AGPL productization trap for Twenty/Relaticle; app-layer scoping weaker than our Postgres RLS; a new erasure path outside our DSAR cascade). Extending the DB is ~2–3 tables + one RPC module, not "building a CRM."

### 2. Data model — three tables, mutable head + append-only history

| Table | Mutability | Key | Purpose |
|---|---|---|---|
| `beta_contacts` | **Mutable** | `user_id` (owner); `UNIQUE (id, user_id)` | The contact/opportunity head: `name, company, role, source, stage, next_action, next_action_date, last_contact, amount, currency, amount_basis, expected_close_date`. Current stage lives here. USD-normalization columns (`amount_normalized_usd/fx_rate/fx_rate_date`) are **deferred** (no FX source in the write path, no reporting consumer at 0 deals). |
| `interview_notes` | **Append-only** | composite FK `(contact_id, user_id)` → `beta_contacts(id, user_id)` | One dual-lens conversation note: dated free-text `body` + `lens[]` in `{sales, product}` (`cardinality(lens) >= 1`). The record IS the conversation; immutable once written. |
| `beta_contact_stage_transitions` | **Append-only** | composite FK `(contact_id, user_id)` → `beta_contacts(id, user_id)` | `from_stage, to_stage, entered_at` — the velocity source for `pipeline-analyst`. Written on every stage change (and on INSERT-at-non-default-stage); not reconstructable retroactively (FR3). |

The children carry a **composite FK** to `beta_contacts(id, user_id)` (not a bare `contact_id` FK): a child row can only ever carry its parent's owner, so a denormalized-`user_id` mis-stamp becomes a DB error, structurally closing a cross-tenant write/injection vector (review: security + data-integrity).

**One dual-lens record, not two logs** (a single conversation carries both facets; per-note `lens` tags; two logs = double-entry + drift, fatal for a solo founder). **Per-contact grain** with `company` as a denormalized text field (CRO's smallest schema); a nested companies table is deferred. **Tenant-generic** — no Soleur-specific stage names hardcoded; `stage` is a free enum constrained by a CHECK the tenant config owns.

### 3. Immutability by RLS-append-only, NOT a WORM no-mutate trigger

`interview_notes` and `beta_contact_stage_transitions` are append-only, but enforced by **RLS shape** (SELECT-owner-only policy; no UPDATE/DELETE policy; INSERT only through the RPC), **not** by a `BEFORE UPDATE/DELETE` no-mutate trigger like `email_triage_items`. Rationale: the beta-CRM carries **no statutory-retention class** — it is the operator's private discovery notebook, not tamper-evident legal evidence for a regulator. A no-mutate trigger would (a) block the `ON DELETE CASCADE` erasure path and reintroduce the Art. 17 cascade deadlock (learning `2026-05-25-art17-cascade-deadlock-and-worm-trigger-carveout.md`), and (b) buy tamper-evidence we do not need. Append-only-via-RPC-discipline (the RPC only INSERTs, never UPDATEs history) satisfies "not reconstructable retroactively." Because RLS shape (not a trigger) enforces this, a **migration-body guard test** asserts no `UPDATE`/`DELETE` statement targets the two history tables, so a future buggy RPC that mutates history trips CI.

### 4. Erasure = ON DELETE CASCADE (simpler than email_triage's RESTRICT + anonymise)

Because there is no statutory-retention obligation, Art. 17 erasure is a hard delete: `beta_contacts.user_id … REFERENCES public.users(id) ON DELETE CASCADE`, and the two child tables `ON DELETE CASCADE` from `beta_contacts`. Deleting the account deletes every row. This is deliberately **simpler** than `email_triage_items` (which uses `ON DELETE RESTRICT` + an `anonymise_*` RPC called before `auth.admin.deleteUser`) — that pattern exists only to retain anonymised statutory rows past account deletion, an obligation the beta-CRM does not have. No `anonymise_beta_*` RPC, no `account-delete.ts` cascade step needed for erasure. (A `data-integrity-guardian` deepen-plan pass must confirm the CASCADE chain does not collide with any WORM/RESTRICT ancestor and that the DSAR export still reads the rows before deletion.)

### 5. Agent read/write path — MCP tool → auth.uid()-pinned SECURITY DEFINER RPC

The make-or-break agent-native requirement. Today `cro`/`cpo` operate on git-KB files only; no MCP tool writes tenant DB rows. Add `server/crm/crm-tools.ts` (mirrors `server/inbox-tools.ts`): `userId` captured in the builder closure (never tool input), running on the tenant-scoped client (`getFreshTenantClient(userId)`) so RLS stays load-bearing.

- **Reads** (`crm_contact_list`, `crm_contact_get`, **`crm_note_list`**) query the tenant client directly (RLS owner-scoped), like `inbox_list`. (`crm_note_list` is required so a captured note is readable back — without it notes are write-only to the agent.)
- **Writes** (`crm_contact_upsert`, `crm_note_append`, `crm_contact_set_stage`) call `auth.uid()`-pinned SECURITY DEFINER RPCs (`SET search_path = public, pg_temp`), mirroring `set_email_triage_status`. Because SECURITY DEFINER **bypasses RLS**, each write RPC opens with a `auth.uid() IS NULL → 42501` guard then `SELECT … FOR UPDATE` + re-checks `user_id = auth.uid()` before mutating (no blind `ON CONFLICT DO UPDATE`; the `FOR UPDATE` also serializes concurrent stage changes). **No owner-INSERT/UPDATE RLS policy** — an owner-write policy beside the RPC is itself a bypass path (learning `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md`). `service_role` write is also REVOKEd (no service-role write pipeline exists). A separate **`crm_erase_contact` service_role-only RPC** is the auditable third-party (beta-tester) Art. 17 erasure path.
- Third-party conversation content surfaced to the agent is wrapped in an UNTRUSTED-content envelope (the `inbox-tools.ts` precedent). **Residual, explicitly accepted:** the `auth.uid()` pin closes the *cross-tenant* axis, but *within-tenant* prompt-injection (injected `body` driving the agent to overwrite a real contact's head fields) is NOT closed by the envelope — this is the first agent WRITE over untrusted content. At single-user scale the operator reviews agent actions in-session; a field-level old→new audit is a deferred hardening. A `<table>_jti_not_denied` RESTRICTIVE policy (068/076/077 shape) is added to all three tables so a revoked founder JWT is rejected at the PostgREST boundary.

### 6. Pipeline → Finance contract

A single canonical **stage→probability** map, versioned in one place (`server/crm/stage-probability.ts`), is also the **single source of the stage enum** — the migration `stage`/`to_stage` CHECK set is drift-guarded to equal `Object.keys(STAGE_PROBABILITY)` by a test (its real merge-time consumer; `pipeline-analyst` is a markdown agent that *references* it, not a TS importer). `amount` is stored **raw** with `currency` (ISO 4217); **USD normalization is deferred** (`amount_normalized_usd/fx_rate/fx_rate_date` land with a reporting consumer + an FX source — resolves the currency open question as raw-now/normalize-later). `amount` is nullable with an `amount_basis NOT NULL DEFAULT 'unknown'` discriminator in `{hypothetical_acv, committed, unknown}` so `pipeline-analyst` filters directional beta ACV from real committed pipeline (`'unknown'` excluded from committed pipeline). A `CHECK (amount IS NULL OR currency IS NOT NULL)` forbids an amount with no unit. Weighted-pipeline forecasting itself is deferred (CFO: theater at 0 deals) — the value now is capturing the fields + the contract. Schema ownership is CRO/pipeline-analyst.

### 7. Compliance floor ships with the feature

New **Article 30 Processing Activity PA-30** (next free; highest present = PA-29). Lawful basis **Art. 6(1)(f) legitimate interest + a dedicated LIA + a privacy-notice line** (matching the PA-27/PA-28 email precedent; resolves the consent open question — the gdpr-gate at plan Phase 2.7 is authoritative). **Retention: 24 months from `last_contact`** (aligns with the existing PA-PII 24-month envelope), swept by an in-migration `pg_cron` job (the `processed_resend_events` precedent). New tables registered in `DSAR_TABLE_ALLOWLIST` (the completeness lint forces it); export chain wired in `dsar-export.ts`. Because the legal cross-document gate fires on `dsar-export-allowlist.ts`, the four legal docs (`privacy-policy.md`, `gdpr-policy.md`, `data-protection-disclosure.md`, `compliance-posture.md`) are updated in the same PR.

**GDPR-gate fold-ins (Phase 2.7).** The beta tester is an **involuntary third-party data subject** (not the account owner): (a) **Art. 14** (not Art. 13) transparency — the LIA specifies the notice mechanism to the tester; (b) their access/erasure requests are fulfilled **manually via the service role** keyed on contact identity (distinct from the owner's `ON DELETE CASCADE`); (c) the `crm_*` agent-read path is a **Chapter V transfer** of third-party PII to Anthropic (US) for `cro`/`cpo` reasoning — recorded in PA-30 recipients under the existing Anthropic DPA; (d) **no special-category data solicited** (Art. 9) — free-text `body` is an incidental ingress, not a Critical column-name match.

### 8. Extraction seam — the `crm` module boundary

All CRM code lives behind a single seam: `server/crm/` (data access, the RPC wrappers, the stage-probability map, the MCP tools) + a self-contained migration `126_beta_crm.sql` + the `DSAR_TABLE_ALLOWLIST` adapter entries. No Soleur-specific stage names or fields are hardcoded; the stage enum + probability map are tenant-config-shaped. This keeps the capability a liftable unit if the #6166 spin-out triggers fire, without over-building a plugin abstraction now (YAGNI: the seam is a directory + a config map, not a package boundary).

### 9. De-identified insight layer stays in git

Aggregate/pseudonymised rollups (no identifiable person) are written to `knowledge-base/sales/` + `knowledge-base/product/` (both already sanctioned KB dirs), where `cro`/`cpo` already synthesize. Raw PII never leaves the DB.

## Alternatives Considered — Sourcing Options Canvas (#6163)

| Option | Privacy / residency | Productizes (multi-tenant) | Agent-native | Cost + ops | Licensing | Verdict |
|---|---|---|---|---|---|---|
| **Build — extend Supabase DB** (CHOSEN) | Best (EU-resident, no sub-processor, inherits DSAR/WORM) | Yes — rows, not servers | Native (shared auth/RLS + MCP tool) | Low (migration + one module) | None | **CHOSEN** |
| Buy — external SaaS (Attio / HubSpot Free) | New sub-processor; US-residency (Attio) / CLOUD Act (HubSpot EU) | No — a company account ≠ a tenant capability | Via API token | Recurring + DPA/Art. 30 | — | Rejected |
| OSS self-host (Twenty / Corteza / Relaticle) | Good (self-run) | Twenty single-tenant → sprawl; Corteza low-code toolkit | Twenty/Relaticle native MCP; Corteza DIY | A whole second app to operate (DB/auth/patch/backup) + a new erasure path outside DSAR | **AGPL productization trap** (Twenty/Relaticle, no commercial option); Corteza Apache-safe | Rejected (turnkey+multi-tenant+resale-safe quadrant is empty; Relaticle multi-tenancy is app-layer scoping, weaker than our RLS, and ships no DSAR/erasure) |
| Connect existing (BYO-CRM via native MCP) | Light (native MCP = no sub-processor) | Yes, for tenants who already run a CRM | Native | Deferrable per-CRM | — | **Deferred** (later phase) |

Secondary data-model / mechanism alternatives, decided within the CHOSEN option:

- **Two logs (a sales log + a product log)** — rejected: double-entry + drift. One dual-lens record with per-note `lens` tags.
- **WORM no-mutate trigger on the history tables** (email_triage shape) — rejected for MVP: reintroduces the Art. 17 CASCADE deadlock and buys tamper-evidence the non-statutory data does not need. Append-only-via-RLS instead. (Revisit if a statutory-retention class is ever added.)
- **RESTRICT FK + `anonymise_beta_*` RPC** (email_triage erasure shape) — rejected: no statutory rows to retain, so plain `ON DELETE CASCADE` is correct and simpler.
- **Per-company grain with nested contacts** — deferred: per-contact + denormalized `company` text is CRO's smallest schema; nested companies is a follow-up if `pipeline-analyst` aggregation demands it.
- **Fold stage history into a `stage_history jsonb` column on `beta_contacts`** (drop the third table) — rejected. A dedicated append-only table is what enables the **composite-FK owner guard** `(contact_id, user_id) → beta_contacts(id, user_id)` (a JSONB element can't be FK-guarded) and clean queryable velocity + a distinct DSAR Art-15 entry. On a single-user-incident surface the structural owner guard outweighs the one-table saving. (Simplicity review proposed the JSONB cut; the security + data-integrity guards decided it.)
- **`app/api/crm/*` route for the agent path** instead of an MCP tool — the MCP tool is the agent-native-parity precedent (`inbox-tools.ts`); a route is the UI-over-API surface for the deferred UI phase, not the agent path.

## Consequences

- The operator gets a private, agent-reachable capture home this week; `cro`/`cpo` read AND write records instead of them being dead documents; `pipeline-analyst`→`cfo` gain their first pipeline data layer.
- Every future tenant inherits the capability **and** its compliance obligations — the Article 30 entry + retention + DSAR wiring are the capability's floor, not an afterthought.
- The `crm` module seam keeps the code liftable for the #6166 spin-out without paying an abstraction tax now.
- **Accepted trade-off:** three new PII tables widen the DSAR/erasure surface and the legal-doc cross-document maintenance set. Mitigated by the completeness lint (forces allowlist registration) + the cross-document gate (forces the 4 legal docs) + an Art. 17 CASCADE integration test.
- **Accepted trade-off:** the agent write path is a new capability class (no prior agent-initiated DB write). Mitigated by RPC-only writes, `auth.uid()` pin, closure-captured `userId`, and the untrusted-content envelope.

## C4 impact

The container view gains a new data-store and a new external data subject (see the plan's `## Architecture Decision (ADR/C4)` § for the exact `model.c4` / `views.c4` edits):

- **New container (data store)** `crmStore = database "Beta-CRM Store" { technology "Supabase (beta_contacts, interview_notes, beta_contact_stage_transitions, mig 126)" }` inside `infra` (mirrors `operationalInbox`; `containers` view only).
- **New external actor** `betaContact = actor "Beta Tester / Prospect" { #external }` — the third-party data subject whose conversation PII the operator captures (mirrors `emailSender`; added to **both** `context` and `containers` views, as `emailSender` is).
- **New relationships:** `engine -> crmStore` (`crm_*` MCP tools read/write via RPC — agent-native parity, the true mirror of `engine -> operationalInbox`); `betaContact -> founder` (PII origin). **No `founder -> crmStore` edge** — no `founder -> <database>` edge exists in the model, and the MVP has no UI/API surface, so the only real `crmStore` access path is the agent; a `webapp -> crmStore` edge is added only when the deferred UI/API phase lands.
- Validated by `c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view include` on an undefined element fails there).

## UI phase (read-only) — amendment (#6172, mig 127)

The deferred UI/API phase referenced above has landed as a **read-only** surface at
`/dashboard/crm` (pipeline board + conversion funnel + contact-detail drawer). Editing
stays conversational via the agent (`crm_*` MCP tools) — no CRUD/drag-to-stage UI (the
visual surface's marginal value over the shipped agent capability is *scan/overview*, not
editing; a write UI would duplicate agent capability for an audience of one).

**Access path — same boundary, no new authz.** The browser cannot call in-process MCP
tools, so the UI gets its own thin `app/api/crm/*` **GET** routes that reuse the *exact*
owner-scoped RLS boundary: reads run on the authenticated **SSR cookie client**
(`createClient()` + `getUser()` — NOT the agent-impersonation `getFreshTenantClient`),
default-authed (no `PUBLIC_PATHS` entry). This realizes the reserved
`webapp -> crmStore` edge (now in `model.c4`).

**Owner-read accountability — atomic, fail-closed (mig 127).** An owner reading a
beta-tester's verbatim notes is a PII re-egress, so it is recorded. A new append-only,
owner-private `beta_contact_access_log` (same RLS posture as mig 126: SELECT-owner-only,
no INSERT/UPDATE/DELETE policy, table writes REVOKEd, RESTRICTIVE jti-deny; composite FK
`(contact_id, user_id) → beta_contacts(id, user_id) ON DELETE CASCADE` so it is swept by
the existing `crm_erase_contact`) plus the **atomic** `crm_get_contact_detail(p_contact_id)`
VOLATILE SECURITY DEFINER RPC: it inserts the audit row AND returns
`{contact, notes, transitions}` jsonb **in one transaction** — fail-closed (no audit row ⇒
no data). This makes "un-bypassable" an invariant (not a best-effort side-write), makes
SWR-revalidation duplicate log rows semantically correct (each = a real re-egress), and
neutralizes future prefetch phantom-reads. On RPC error the drawer renders a loud
ErrorCard + Retry (never silent, never data-without-audit).

**PII-safe errors (merge-blocking on the routes).** No route forwards raw Postgres
`error.message`/`details` to the HTTP body or Sentry — each returns a generic semantic
code and mirrors only `{ op, userId, code }`. Missing/erased/foreign ids return a
byte-identical `404` (no existence oracle), mirroring the RPC's uniform-42501 posture.

**Compliance deltas (no new legal basis).** Art. 15 (access) is served by the owner's own
read; Art. 17 (erasure) is unchanged — `crm_erase_contact` stays service-role-only and its CASCADE
now also sweeps the access log. No self-serve erase in v1.

**Art. 5(2) audit scope (deliberate, review-noted).** The access log covers the **UI drawer's**
note-body read (`crm_get_contact_detail`) only. The **agent** read path (`crm-tools.ts` reads
`interview_notes` bodies directly on the tenant client — arguably a larger re-egress, PII → the LLM)
is **NOT** logged; that gap predates this PR and is accepted for v1. So "Art. 5(2) is encoded" is
scoped to the visual surface, not claimed comprehensive. Extending the audit to the agent detail-read
path is a tracked post-v1 follow-up (touches the make-or-break agent path — R1-sensitive — so it gets
its own cycle, not folded into a read-only UI PR).

- **Realized relationship:** `webapp -> crmStore` — GET `/api/crm/*` RLS-owner-scoped read
  routes + the `crm_get_contact_detail` audit RPC. `crmStore` technology string updated to
  include `beta_contact_access_log` (mig 126 + 127). Still **no `founder -> crmStore`** edge
  (the founder reaches it through `webapp`).
