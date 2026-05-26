**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

### `GDPR-Art-9` — special-category column added without explicit Art. 9(2) basis

**Severity:** Critical
**Article:** GDPR Art. 9 (special categories of personal data)
**Location:** apps/web-platform/supabase/migrations/053_add_health_profile.sql:5
**Pattern matched:** `medical_history TEXT` — column name match against the Art. 9 health-data list in `references/fields.md`
**Why this matters:** Art. 9 prohibits processing of special-category data unless one of ten Art. 9(2) bases applies (explicit consent, employment law, vital interests, public interest in public health, etc.). The column-name match is sufficient grounds for Critical because the gate cannot verify whether an Art. 9(2) basis is recorded — only that the column exists.
**What to do:** Operator-acknowledgment escalation flow:

─────────────────────────────────────────────────────────────────
CRITICAL FINDING — operator acknowledgment required
─────────────────────────────────────────────────────────────────

A `Critical` finding (`check_id: GDPR-Art-9`) requires an Active Items row in `knowledge-base/legal/compliance-posture.md`. The gate does NOT auto-write the row.

Run, in order:

  1. gh issue create --title "Art. 9 health-data column added (medical_history)" --label compliance/critical,domain/legal --body "<finding text>"
  2. Edit `knowledge-base/legal/compliance-posture.md` and append a row to the Active Items table.
  3. git add knowledge-base/legal/compliance-posture.md && git commit -m "compliance: register Art. 9 finding for #<issue>"
