# gdpr-gate output: #12011 PR-B (migration 184), work-phase exit, 2026-11-04

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Scope: `git diff origin/main...HEAD` on branch `feat-feat-founder-approval-cards-pr-b`. Regulated-data paths matched: `apps/web-platform/supabase/migrations/184_legal_acceptance.sql`, `.down.sql`, `apps/web-platform/supabase/verify/184_legal_acceptance.sql`. Column names only were assessed; no row values exist (the tables are empty and dark).

### `GDPR-Art-6` — lawful basis annotation

**Severity:** Important (resolved in this PR)
**Article:** Art. 6(1)(f)
**Location:** `184_legal_acceptance.sql`, both `CREATE TABLE` statements
**Pattern matched:** new table without `-- LAWFUL_BASIS:`
**What was done:** both tables now carry `-- LAWFUL_BASIS: legitimate_interests (Art. 6(1)(f))` with the LIA and PA-40 cited. The LIA is drafted and not counsel-reviewed.

### `GDPR-Art-5e` — retention metadata

**Severity:** Important (open, disclosed)
**Article:** Art. 5(1)(e)
**Location:** `184_legal_acceptance.sql`
**What was done:** `-- RETENTION:` annotations added. `legal_acceptance`: proposed life of the instrument plus 5 years, cap 10, unconfirmed by counsel; no sweep is built and the guard refuses deletion, so the deletion path at the end of the period is an open follow-up (PA-40, counsel item 17). `legal_reauth_event`: rows older than 30 days are deleted when the next challenge is issued; not deleted on erasure.

### `GDPR-Art-17` — erasure

**Severity:** Important (decided, disclosed)
**Article:** Art. 17(3)(e)
**Location:** `legal_acceptance.founder_id`
**Pattern matched:** user-keyed table with no `ON DELETE` path
**Decision:** deliberate. `founder_id` is a plain uuid with no foreign key, the record is kept after erasure (CLO ruling 2026-11-03), and no `anonymise_*` RPC is added. The `GDPR-Art-17-caller` check does not apply (no `ON DELETE RESTRICT` FK and no `anonymise_*` RPC in the diff). The erasure reply wording is in `2026-11-founder-legal-acceptance-dsar-and-notice-note.md`.

### `GDPR-Chapter-V` — cross-border

**Severity:** none. No new vendor, SDK or environment variable in the diff. Supabase is the existing processor (PA-40 recipients).

### `GDPR-Art-9` — special category

**Severity:** none by column name. No column matches the Art. 9 list. `legal_acceptance.requested_edit` is free text and could contain special-category content by accident; it is capped at 1,000 characters and the UI will show a no-personal-data notice (PR-C) (text in the DSAR and notice note). Recorded as a counsel question (PA-40, item 17: whether the note stays at all).

### Other

DSAR: both tables are excluded from the self-serve export with a stated reason (`DSAR_TABLE_EXCLUSIONS`). No Critical finding; no `compliance-posture.md` escalation row is required beyond the PA-40 row already added.

gdpr-gate: path scan complete — 3 examined, 3 matched
