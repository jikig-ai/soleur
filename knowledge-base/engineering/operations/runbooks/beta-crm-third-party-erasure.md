---
title: Beta-CRM third-party (beta-tester / prospect) Art. 17 erasure
type: runbook
date: 2026-07-07
issue: 6165
adr: knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
lia: knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md
article-30: knowledge-base/legal/article-30-register.md (PA-30)
---

# Runbook — Beta-CRM third-party Art. 17 erasure request

**When to use.** A beta tester / prospect (a **third-party** data subject, NOT
the account owner) recorded in the owner-private beta-CRM exercises their GDPR
Article 17 right to erasure — e.g. an email to `legal@jikigai.com` asking to be
removed. This is the operative third-party erasure mechanism disclosed in **PA-30**,
the **LIA §Art. 17 path**, Privacy Policy §4.7, and Data Protection Disclosure
§5.3(c). (The account **owner's** own whole-store erasure is separate and fully
automatic: `ON DELETE CASCADE` from `public.users` on account deletion — no
runbook needed.)

**Distinction from the owner path.** The third party has no account and cannot
self-serve. The erasure is keyed on **contact identity**, runs under the
`service_role`-only SECURITY DEFINER RPC `crm_erase_contact(p_contact_id)`
(migration 126), and CASCADEs the contact's `interview_notes` +
`beta_contact_stage_transitions`. There is no owner-scoped path because the RPC
must reach across the owner boundary to erase a subject the owner controls.

## Preconditions

- Verify the requester's identity and that they are the subject of the records
  (Art. 12(6) — request further info if reasonable doubt).
- Confirm no Art. 17(3) exemption applies (there is **no statutory-retention
  class** on this data — ADR-102 §4 — so a hard delete is correct; no
  anonymise-and-retain).

## Steps (no SSH; Supabase MCP or Doppler `DATABASE_URL_POOLER`)

The beta-CRM store is owner-private (owner-only RLS), so the operator must run
these as **service-role / admin** — the RLS-scoped app path cannot see another
owner's rows. Use the Supabase MCP `execute_sql` tool (or `psql` via the Doppler
`DATABASE_URL_POOLER` for the target env), against the **correct env's** project
(`hr-dev-prd-distinct-supabase-projects`).

1. **Locate the contact_id.** Search by the identifying detail the subject gave
   (name / company / email-in-notes). Owner-scope is intentionally NOT applied —
   this is the cross-owner admin path:

   ```sql
   SELECT id, user_id, name, company, role, last_contact
   FROM public.beta_contacts
   WHERE name ILIKE '%<name>%' OR company ILIKE '%<company>%';
   -- If the identifier only appears in a note body:
   SELECT contact_id FROM public.interview_notes WHERE body ILIKE '%<detail>%';
   ```

   Confirm you have the right row(s). A subject may span more than one
   `contact_id` (recorded by different owners) — erase each.

2. **Erase.** Call the service-role RPC for each matched `contact_id`:

   ```sql
   SELECT public.crm_erase_contact('<contact_id>'::uuid);  -- returns 1 on delete, 0 if already gone
   ```

3. **Verify (pull the data yourself — `hr-no-dashboard-eyeball-pull-data-yourself`).**

   ```sql
   SELECT count(*) FROM public.beta_contacts WHERE id = '<contact_id>';                 -- 0
   SELECT count(*) FROM public.interview_notes WHERE contact_id = '<contact_id>';        -- 0 (CASCADE)
   SELECT count(*) FROM public.beta_contact_stage_transitions WHERE contact_id = '<contact_id>'; -- 0 (CASCADE)
   ```

4. **Respond to the subject** within one month (Art. 12(3)) confirming erasure,
   and **note the fact** of the erasure request + completion date (not the
   subject's data) in the compliance log.

## Notes

- `crm_erase_contact` is `GRANT EXECUTE ... TO service_role` only; it is NOT
  callable by `authenticated` and is NOT an agent tool (the agent runs on the
  RLS-scoped tenant client and must never reach across owners).
- At single-operator v1 the operator IS the admin; when non-Soleur tenants
  onboard, the cross-owner search in step 1 must be scoped to the requesting
  subject's records only, and this runbook re-reviewed with the CLO.
