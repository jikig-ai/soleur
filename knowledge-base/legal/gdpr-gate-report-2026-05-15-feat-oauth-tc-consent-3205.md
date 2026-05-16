**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

# gdpr-gate report — feat-oauth-tc-consent-3205

**Scope:** `git diff main...HEAD` against the canonical regulated-path regex
(`apps/web-platform/supabase/migrations/` + `app/api/` + `*.sql`).

**Matched regulated-path files (2):**

- `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql`
- `apps/web-platform/app/api/accept-terms/route.ts`

**Run timestamp:** 2026-05-15 (work Phase 2 exit, AC17).
**Plan:** `knowledge-base/project/plans/2026-05-15-feat-oauth-tc-consent-residual-audit-plan.md`.

---

## Summary

| `check_id` | Article | Status | Severity |
|---|---|---|---|
| `GDPR-Art-6` | Art. 6 lawful basis | Documented in PA 11 + migration prose; missing `-- LAWFUL_BASIS:` annotation convention | Suggestion |
| `GDPR-Art-5e` | Art. 5(1)(e) retention | `retention_until` column with 7-year default; sweep deferred (AC21) | Cleared |
| `GDPR-Art-17` | Art. 17 erasure | `ON DELETE RESTRICT` FK + `anonymise_tc_acceptances` RPC | Cleared |
| `GDPR-Chapter-V` | Art. 44-49 cross-border | No new non-EEA vendor; Supabase eu-west-1 only | Cleared |
| `GDPR-Art-9` | Art. 9 special-category | No Art. 9 column-name matches in `tc_acceptances` schema | Cleared |

**Critical findings:** 0.
**Important findings:** 0.
**Suggestion findings:** 1.

---

## `GDPR-Art-5e` — Retention envelope cleared

**Severity:** Cleared
**Article:** Art. 5(1)(e) storage limitation
**Location:** `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql:65-67`
**Pattern matched:** `retention_until timestamptz NOT NULL DEFAULT (now() + interval '7 years')`
**Why this matters:** Personal-data tables must declare a retention envelope or explicitly justify indefinite retention.
**What to do:** No action. Column ships with 7-year default + inline migration comment. Sweep mechanism deferred per plan AC21 (0 beta users + 7-year window means no row qualifies for deletion until 2033; deferred-tracking issue must be filed before merge per Phase 10).

## `GDPR-Art-17` — Erasure cascade cleared

**Severity:** Cleared
**Article:** Art. 17 right to erasure
**Location:** `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql:60` (FK) + `:206-237` (anonymise RPC)
**Pattern matched:** `user_id uuid REFERENCES public.users(id) ON DELETE RESTRICT` + `CREATE OR REPLACE FUNCTION public.anonymise_tc_acceptances`
**Why this matters:** Tables with user FKs need either `ON DELETE CASCADE` or a documented anonymisation pathway.
**What to do:** No action. The `ON DELETE RESTRICT` is intentional (preserves audit-trail row count); `anonymise_tc_acceptances(p_user_id)` UPDATEs `user_id = NULL` before the user is deleted, per the offboarding-runbook ordering documented in PA 11 of the Art. 30 register. Mirror of 043's tenant_deploy_audit pattern.

## `GDPR-Chapter-V` — Cross-border transfer cleared

**Severity:** Cleared
**Article:** Art. 44-49
**Location:** N/A — no new vendor.
**Pattern matched:** No new non-EEA env var, SDK, or processor.
**Why this matters:** New non-EEA vendors must be registered in `compliance-posture.md` Vendor DPAs.
**What to do:** No action. Data resides in Supabase `eu-west-1` (Ireland). Existing Supabase DPA covers PA 11; Art. 30 register updated to reflect this in the same PR.

## `GDPR-Art-9` — Special-category audit cleared

**Severity:** Cleared
**Article:** Art. 9 special categories
**Location:** `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql:55-71`
**Pattern matched:** Schema columns reviewed against the Art. 9 column-name list in `plugins/soleur/skills/gdpr-gate/references/fields.md`. Columns: `id (uuid)`, `user_id (uuid)`, `version (text)`, `document_sha (text)`, `accepted_at (timestamptz)`, `ip_hash (text NULL)`, `user_agent (text NULL)`, `retention_until (timestamptz)`, `created_at (timestamptz)`. None match Art. 9 categories (health, ethnicity, religion, political opinion, sexual orientation, trade union membership, genetic data, biometric data, criminal data).
**Why this matters:** Art. 9 columns require explicit lawful basis under Art. 9(2) + heightened safeguards.
**What to do:** No action. The `ip_hash` and `user_agent` columns are intentionally reserved-but-NULL for forward-compat per the LIA pending in #3855; landing as NULL means no Art. 9-adjacent processing in v1.

---

## `GDPR-Art-6` — Lawful basis annotation suggestion (NEW)

**Severity:** Suggestion
**Article:** Art. 6 lawful basis
**Location:** `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql:55-71`
**Pattern matched:** New schema column without inline `-- LAWFUL_BASIS: <basis>` annotation.
**Why this matters:** The convention is to annotate each personal-data column with its lawful basis inline so the migration is self-documenting; future audits don't need to cross-reference the Art. 30 register to know why a column exists.
**What to do:** Lawful basis IS documented — in the migration header comments (Art. 7(1) demonstrability, lines 5-7) and in the Art. 30 register PA 11 (Art. 6(1)(b) + Art. 7). The literal `-- LAWFUL_BASIS: art-6-1-b` convention is not yet adopted on prior migrations 001-040 either (per the "First-run on existing codebase" section of the gdpr-gate skill). Cosmetic; no blocker. Future PR can add the convention across the migrations folder in one sweep.

---

## Disposition

- **No `Critical` findings.** The operator-acknowledgment escalation flow (FR5) does NOT fire.
- **No `Important` findings.** No `compliance/improvement` issue required.
- **One `Suggestion` finding.** Captured here for the record; no Active Items row required.

The plan AC17 requirement ("`/soleur:gdpr-gate` invoked at /work Phase 2 exit; report committed at `knowledge-base/legal/gdpr-gate-report-2026-05-15-feat-oauth-tc-consent-3205.md`") is satisfied by this file.

---

## Cross-references

- **Art. 30 register update:** PA 11 — Consent Records (added in the same PR; see `knowledge-base/legal/article-30-register.md:183-199`).
- **Bump-policy rubric:** `knowledge-base/legal/tc-version-bump-policy.md` (added in the same PR; CLO sign-off captured at PR review per AC16).
- **Plan acceptance criteria:** AC1, AC2, AC4, AC5, AC6, AC7, AC8, AC9, AC10, AC11, AC12, AC13, AC14, AC15, AC16, AC17, AC18 — all satisfied pre-merge. AC22 (prd apply) and AC23 (post-merge spot-check) ship via `/soleur:ship` Phase 5 verification.
- **Deferred follow-on:** AC21 — `pg_cron` retention sweep tracking issue filed at Phase 10.2.
