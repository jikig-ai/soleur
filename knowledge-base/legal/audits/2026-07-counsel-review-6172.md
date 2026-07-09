---
title: "Counsel review audit — #6172 (beta-CRM read-accountability log: migration 127 `beta_contact_access_log`, GDPR Art. 5(2))"
type: counsel-review
date: 2026-07-09
issue: 6172
pr: 6239
adr: knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
lia: knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md
parent_audit: knowledge-base/legal/audits/2026-07-counsel-review-6165.md
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-07-09
signed_off_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; external counsel re-review reserved for the inherited PA-30 triggers below"
brand_survival_threshold: single-user incident
re_evaluation_triggers: "Inherits the #6165 / PA-30 frontmatter triggers verbatim (first arms-length / non-Soleur tenant becomes a store owner; any tester-visible surface or agent-user parity for the third-party subject; any special-category (Art. 9) field, or the free-text `body` routinely carrying Art. 9 data; any outbound-send authority to CRM contacts; retention-horizon change or non-owner workspace-shared visibility mode; agent write-path de-gating; an EEA-out transfer not covered by the disclosed DPF/SCCs; a regulated-industry contact). PLUS access-log-specific triggers: the access log gains a note-body / content column or any third-party-content field (today it is metadata-only: contactId + timestamp) OR the log is surfaced to Anthropic or any other recipient (today it never leaves the DB and is not part of the crm-tools agent-read path) OR an independent retention clock or a manual purge path is added for the log (today it has no clock — erased only WITH the contact via CASCADE) OR the log gains an owner-write RLS policy or a client-role INSERT/UPDATE/DELETE grant (today INSERT is RPC-only, and there is no UPDATE/DELETE anywhere)."
---

# Counsel review audit — #6172 (beta-CRM read-accountability log, migration 127)

> **STATUS: DISCHARGED — reviewed and attested by the `clo` agent on 2026-07-09.**
> The `clo` agent (Soleur legal domain leader) is the reviewing authority for the
> v1 Soleur-as-tenant-zero posture — this is an agent-native company; legal review
> is a CLO-agent function, not a task for the non-lawyer operator. The operator
> retains an optional veto; **external** counsel re-review is reserved for the
> frontmatter re-evaluation triggers. The agent cross-checked every
> implementation-detail claim in the four amended legal artifacts against the
> actual migration `127_beta_crm_access_log.sql` (the table DDL, the four-column
> shape, the RLS/REVOKE/jti-deny matrix, the atomic fail-closed
> `crm_get_contact_detail` RPC body, the composite-FK `ON DELETE CASCADE`) and
> against `server/dsar-export-allowlist.ts` (the article-`15` access-only tag) —
> and **discharges the gate with no blocking condition**. One non-blocking
> observation is recorded below.

This audit is the load-bearing evidence for the ship-time Counsel-Review
CLO-Attestation gate on **PR #6239** (issue **#6172**, `feat-beta-crm-ui`,
ADR-102 UI phase). The PR ships the read-only in-Soleur beta-CRM board/funnel/drawer
surface. Its regulated-data grain is **migration 127**, which adds exactly **one
table** (`beta_contact_access_log`) and **one RPC** (`crm_get_contact_detail`) that
together make the operator's *read* of a contact's detail accountable under GDPR
**Article 5(2)**. This is a strict, minimal **extension** of the migration-126
beta-CRM already discharged in the parent audit
(`knowledge-base/legal/audits/2026-07-counsel-review-6165.md`, PA-30). The legal
grain is **narrow**: **no new processing activity, no new lawful basis, no new data
subject, no new recipient / sub-processor / Chapter V transfer.** There are **no
`[DRAFT — pending CLO/counsel review]` markers** to clear in this PR.

## What migration 127 actually is (cross-checked against the SQL body)

- **Table `public.beta_contact_access_log`** — columns `id uuid PK` / `user_id
  uuid` (the owner) / `contact_id uuid` / `accessed_at timestamptz DEFAULT now()`
  **only**. No note-body column, no third-party-content column. It is an
  **append-only, owner-private read-accountability log**: it records WHICH contact
  the operator opened and WHEN (drawer-open granularity). *Confirmed lines 70–90.*
- **Written atomically inside `crm_get_contact_detail(p_contact_id)`** — one
  `VOLATILE SECURITY DEFINER` function that INSERTs the audit row and RETURNs the
  `{contact, notes, transitions}` jsonb in the **same transaction**, fail-closed:
  the INSERT precedes the return, so if it raises the whole txn rolls back and **no
  PII is returned without an audit row**. *Confirmed lines 131–211 (INSERT at
  184–185 before RETURN at 205).* Called by the **SSR cookie client** (the read-only
  detail drawer), so this is a UI read on the operator's behalf — distinct from the
  migration-126 agent read/write path, and **not** an Anthropic egress.
- **RLS posture** — `ENABLE ROW LEVEL SECURITY`; SELECT-owner-only
  (`user_id = auth.uid()`); **no INSERT/UPDATE/DELETE policy** (an owner-write policy
  beside the RPC would be a bypass — learning 2026-05-21); table-level
  INSERT/UPDATE/DELETE **REVOKEd from PUBLIC, anon, authenticated AND service_role**
  (the RPC writes as function owner); RESTRICTIVE `beta_contact_access_log_jti_not_denied`
  policy; and the RPC body **re-asserts** `is_jti_denied_from_jwt()` so a
  revoked-but-unexpired founder JWT cannot read via the SECURITY DEFINER path.
  *Confirmed lines 96–114, 159–162.*
- **Erasure (Art. 17)** — the composite FK `(contact_id, user_id) REFERENCES
  beta_contacts (id, user_id) ON DELETE CASCADE` means the log rows are removed
  **with the contact**. The existing mig-126 `crm_erase_contact` (DELETE FROM
  beta_contacts) CASCADEs here, and whole-store account-deletion CASCADE reaches it
  too. **No independent retention clock.** *Confirmed lines 79–81, 38–42, 64–69.*
- **DSAR (Art. 15)** — registered in `server/dsar-export-allowlist.ts` as
  `beta_contact_access_log: { ownerField: "user_id", article: "15" }` — **access-only**
  (controller-generated read metadata; NOT Art. 20-portable, which is correct — the
  owner did not "provide" it). *Confirmed allowlist line 346.*

## Per-artifact verdict

| Artifact | Claim(s) cross-checked against code | Verdict |
|---|---|---|
| `docs/legal/privacy-policy.md` §4.7 (Read-accountability log clause) | Metadata-only (`contact_id` + `accessed_at`, never note content); Art. 5(2); written atomically with the read (no detail without the audit row); owner-private; in the Art. 15 export; erased with the contact | **CONFIRMED** — accurate to the migration. The clause frames the write as the "read-only detail drawer" open, matching the SSR-client call site (not the agent path). |
| `docs/legal/gdpr-policy.md` §3.13 (new Read-accountability-log bullet + "content tables" tweak) | Fourth owner-only append-only table; migration 127 / #6172; metadata only; atomic fail-closed `crm_get_contact_detail`; same owner-only RLS + RESTRICTIVE jti-deny; INSERT only via RPC (no owner-write policy); Art. 15 access-only, not Art. 20; composite-FK CASCADE via `crm_erase_contact` + whole-store; no new lawful basis / data subject | **CONFIRMED** — every identifier and behavioural claim matches the SQL. "three owner-only tables" → "three owner-only **content** tables" disambiguates the count so the log is not mis-read as a fourth content table. |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` §3.13 (Eleventy mirror — same bullet + tweak) | Mirror of the canonical §3.13 addition | **CONFIRMED** — mirrored in lockstep; heading sequence unchanged (bullet, not a heading), so `legal-doc-consistency.test.ts` stays green. |
| `docs/legal/data-protection-disclosure.md` §2.3(ad) + §5.3(a) + §5.3(c) | §2.3(ad): "three tables" → "four tables" + the (4) `beta_contact_access_log` enumeration entry (four-column shape, Art. 5(2), atomic RPC, INSERT-only-via-RPC, never a note body) + erasure clause now lists access-log rows in the `crm_erase_contact` CASCADE; §5.3(a): access-log added as Article-15 controller-generated read-accountability metadata; §5.3(c): whole-store + third-party erasure clauses list the access-log rows | **CONFIRMED** — the most detailed prose; every column name, the RPC name, the CASCADE behaviour, and the article tag check out against the migration and the allowlist. |
| `knowledge-base/legal/compliance-posture.md` (2026-07-09 changelog entry + `last_updated`) | Migration 127 extends mig-126; one table + one RPC; metadata-only Art. 5(2); NO new PA / lawful basis / data subject / recipient / Chapter V transfer; DSAR article `15` access-only; Art. 17 via composite-FK CASCADE (no independent clock); docs-in-lockstep list; SHA repin; TC_VERSION not required; DISCHARGED | **CONFIRMED** — accurate summary; `last_updated` bumped to 2026-07-09; `LEGAL_DOC_SHAS` repinned for the three edited `docs/legal/*.md`. |

## Resolution axes

1. **Lawful basis — RESOLVED / inherited, no new basis.** The log's per-column
   `LAWFUL_BASIS` annotation (migration lines 64–69) is `legitimate-interest
   (Art. 6(1)(f)) + Art. 5(2) accountability`, pointing at the same PA-30 LIA
   (`2026-07-07-beta-crm-lia.md`). The Art. 5(2) accountability principle is the
   *reason the log exists* (an owner reading a beta-tester's detail is a PII
   re-egress the controller records); it does not create a new processing purpose.
   No new LIA is required — indeed the log is a **safeguard** that strengthens the
   existing balancing (it makes owner reads auditable).
2. **No new data subject — RESOLVED.** The log holds `contact_id` (a reference to
   an already-registered `beta_contacts` row) + the owner's `user_id` + a timestamp.
   It introduces no new category of person and no new content about the existing
   third-party subjects — only metadata about the operator's own access events.
3. **No new recipient / Chapter V transfer — RESOLVED.** `crm_get_contact_detail`
   returns to the SSR cookie client (the drawer UI); the access-log row itself is
   never surfaced to Anthropic or any other recipient and holds no content. The
   mig-126 Anthropic Chapter V analysis is unchanged and correctly **not** re-opened.
4. **Art. 15 access-only — RESOLVED / matches the allowlist.** `article: "15"`
   (not `15+20`) is correct: the log is controller-generated read metadata, not
   owner-provided data, so Art. 20 portability does not attach. The prose in all
   three canonical docs states "access-only / not Art. 20-portable" verbatim to that
   posture; `dsar-allowlist-completeness.test.ts` fail-closes CI on allowlist drift.
5. **Art. 17 via CASCADE — RESOLVED / no orphan risk.** The composite-FK
   `ON DELETE CASCADE` guarantees the log cannot outlive its contact; there is no
   independent retention clock and no separate erasure path to maintain. Both the
   per-contact `crm_erase_contact` and whole-store account-deletion CASCADE sweep it.
6. **Append-only / write-boundary — RESOLVED / structurally sound.** No owner-write
   RLS policy; table-level INSERT/UPDATE/DELETE REVOKEd from every client role incl.
   `service_role`; INSERT only via the function-owner RPC; no UPDATE/DELETE anywhere.
   Immutability is by RLS shape, matching the mig-126 history tables.

## Non-blocking observation

- **A. Eleventy mirror drift on privacy-policy and DPD is pre-existing (carried
  from #6165), not introduced here.** The canonical `docs/legal/privacy-policy.md`
  §4.7 and `docs/legal/data-protection-disclosure.md` §2.3(ad) carry the full
  beta-CRM prose (now extended with the access-log clause); their Eleventy mirrors
  (`plugins/soleur/docs/pages/legal/{privacy-policy,data-protection-disclosure}.md`)
  **do not contain the beta-CRM prose at all** — that gap predates this PR (the
  #6165 changelog scoped the mirror sync to the gdpr §3.13 heading). Body-equivalence
  is enforced by `check-tc-document-sha.sh` **only for `terms-and-conditions`**
  (the eight non-T&C docs are explicitly deferred per the script header and
  `BODY_EQUIVALENCE_DOCS`), and `legal-doc-consistency.test.ts` checks only
  heading-sequence + named sentinels — neither of which this PR changes. So there is
  **no new published-site disclosure gap and no failing gate**; the gdpr-policy
  mirror (which does have §3.13) was updated in lockstep. The privacy-policy/DPD
  mirror backfill remains the same carried-forward one-off remediation item already
  tracked from #6165 — out of scope for this PR. Named here for the record.

## Overall disposition

**DISCHARGED — proceed to ship.** Migration 127 is a minimal, safeguard-only
extension of the already-discharged migration-126 beta-CRM: an append-only,
owner-private, metadata-only Art. 5(2) read-accountability log with fail-closed
atomic writes, owner-only RLS + jti-deny, Art. 15 access-only DSAR inclusion, and
Art. 17 erasure by composite-FK CASCADE. The four amended legal artifacts state the
implementation accurately across every axis (lawful basis inherited, no new data
subject, no new recipient/transfer, Art. 15 access-only, Art. 17 via CASCADE,
append-only write boundary); **no prose misstates the code**, and no required
disclosure is missing. The single observation is non-blocking and requires no in-PR
prose correction to ship. All output remains **draft material requiring professional
legal review**; this attestation is the v1 internal CLO-agent sign-off, with the
operator's optional veto retained and external counsel re-review reserved for the
inherited PA-30 frontmatter triggers.
