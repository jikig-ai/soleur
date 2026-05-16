**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

### `GDPR-Art-17` — FK to users without ON DELETE CASCADE or anonymisation migration

**Severity:** Important
**Article:** GDPR Art. 17 (right to erasure)
**Location:** apps/web-platform/supabase/migrations/052_add_user_preferences.sql:8-12
**Pattern matched:** `user_id UUID REFERENCES auth.users(id)` without `ON DELETE CASCADE` clause and no companion anonymisation migration
**Why this matters:** When a user exercises Art. 17 erasure, every FK row pointing back to the user record must either cascade-delete or anonymise. A bare FK orphans PII rows in this table when the parent is deleted, leaving regulator-shaped exposure.
**What to do:** Either (a) add `ON DELETE CASCADE`, or (b) create an `anonymise_user_preferences(user_id UUID)` function called from the user-deletion path. See `references/layers/data-lifecycle.md` DL-02.
