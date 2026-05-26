**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

### `GDPR-Art-5e` — missing retention metadata on new PII table

**Severity:** Important
**Article:** GDPR Art. 5(1)(e) (storage limitation)
**Location:** apps/web-platform/supabase/migrations/051_add_audit_log.sql:1-22
**Pattern matched:** `CREATE TABLE audit_log` with no retention column, no scheduled cleanup job reference
**Why this matters:** Art. 5(1)(e) requires that personal data is "kept for no longer than necessary". An audit log without a retention boundary or scheduled cleanup job is implicitly "forever" — that is not a retention policy.
**What to do:** Add a `retention_until TIMESTAMPTZ` column or document the cleanup-job path (e.g., `-- RETENTION: 24 months via cleanup-audit-log nightly job`). See `references/layers/data-lifecycle.md` DL-05.
