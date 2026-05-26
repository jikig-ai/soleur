**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

### `GDPR-Art-6` — missing lawful basis annotation on new column

**Severity:** Important
**Article:** GDPR Art. 6
**Location:** apps/web-platform/supabase/migrations/050_add_email_to_profiles.sql:14-16
**Pattern matched:** `email TEXT NOT NULL` without `-- LAWFUL_BASIS: <basis>` annotation
**Why this matters:** Every processing activity on personal data requires one of six lawful bases (Art. 6(1) a–f). Without an annotated basis at design time, the privacy policy and DSAR runbook cannot reliably enumerate the lawful basis on demand.
**What to do:** Add `-- LAWFUL_BASIS: contract` (or `consent` / `legitimate_interest` / etc.) above the column definition. See `plugins/soleur/skills/gdpr-gate/references/non-negotiables.md` §Art. 6.
