# Migration Checklist — 140_flag_flip_audit_approval_method

## prd apply — pending

Migration 140 has been applied to the shared **dev** Supabase project by
`tenant-integration` CI (per-PR automatic dev apply). It has **not** been
applied to **prd** as of this checklist's writing — prd apply is the
`migrate` job in `.github/workflows/web-platform-release.yml`, which fires
automatically on push to `main` and is sequenced strictly before the `deploy`
job (`deploy` job's `needs: [resolve-target, migrate, verify-migrations,
verify-doppler-secrets]`).

**Safety before prd-apply (verified during review, PR #8650):** the new
`approval_method` column is nullable with no default (no table rewrite), and
`audit-flag-flip.sh`'s `audit_flag_flip_rpc` always sends the new
`p_approval_method` key. Against a prd database that has not yet applied
migration 140, PostgREST cannot match the new 8-arg function signature and
returns a non-2xx response; the caller's HTTP-code check then fails closed
(rc 4, caller aborts before any Flagsmith/Supabase mutation —
append-before-flip is preserved). The practical consequence of merging before
the automatic prd-apply completes is availability (flag flips against prd
blocked for the few minutes between merge and the `migrate` job completing),
never corruption. See migration 140's own header and ADR-249's
"Forward ordering for migration 140" bullet for the full analysis.

No operator action is required — the standard merge-triggered release
pipeline applies this migration automatically, ahead of `deploy`. This
checklist exists only to give preflight Check 1 (DB Migration Status) a
documented signal so it does not FAIL on the expected pre-merge state
(migration correctly absent from prd until the release pipeline runs).

Re-verified post-merge via CI's `verify-migrations` job (runs
`apps/web-platform/scripts/run-verify.sh`, which includes
`apps/web-platform/supabase/verify/140_flag_flip_audit_approval_method.sql`).
