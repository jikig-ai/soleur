# Learning: a verify sentinel pins a posture — a posture-changing PR must re-derive the whole sentinel corpus, not just add its own

## Problem

Migration 178 (PR #11253) narrowed api-role table grants that migration 174's
snapshot had materialized. The branch shipped a new `supabase/verify/178_*.sql`
asserting the NEW posture — but `verify/174_*.sql` still asserted the OLD one.
`run-verify.sh` runs EVERY file under `supabase/verify/` on every deploy, and
`deploy` needs `verify-migrations` green in `web-platform-release.yml`, so the
first post-178 deploy would have red 15 stale rows and blocked every later
deploy. Found in QA, not in review: the review panel checked the new file's
internal consistency; nobody asked what the diff did to the *other* sentinels.

Same blind spot, second instance, same PR: `verify/178` itself probed only the
enumerated universe (each named verb/relation/role), never the complement.
Column-level `attacl` grants survive `REVOKE ALL ON TABLE`, so a stray column
grant outside the census would have passed the sentinel silently (the rls-fuzz
`aclexplode` sweep was the only backstop).

## Solution

- Deleted the 15 superseded rows in `verify/174` with a SUPERSEDED comment
  naming 178 and pointing at verify/178 as the new-posture assertion (precedent:
  verify files are edited post-creation — they are live sentinels, not immutable
  migrations). 150/150 rows bad=0 on the rehearsal stack afterward.
- Added `no_uncovered_col_grants_narrowed` to verify/178: one catalog sweep
  (`pg_attribute` × roles × verbs) asserting no api-role column privilege exists
  beyond the census that a held table-level verb does not already cover —
  mirroring the fuzz gate's registered-or-covered rule. Positive control:
  planted `GRANT UPDATE(tc_accepted_at)` / `GRANT SELECT(filename) ON
  _schema_migrations` both fire `bad=1`, revoke returns 0.

## Key Insight

Any diff that changes a state a sentinel asserts must ship BOTH the new
assertion AND the retirement (or re-scoping) of the old one — and the
sentinel's own complement must be probed, or the guard only sees what its
author remembered to enumerate. Litmus for future grant/policy/flag diffs:
`grep -rln '<relation-or-mechanism>' supabase/verify/` and read every hit for
"does this row still state truth after my change?" — the check that would have
caught this in review is one grep, not a new suite.

## Session Errors

- **Misread a diff row and nearly reported a false finding.** Read
  `revoked_authenticated_flag_flip_audit` as missing `('SELECT')` in the verify
  VALUES list; the actual file had it. Recovery: re-grepped the on-disk file
  before filing. Prevention: verify a finding against the file, never against a
  remembered diff line — one `grep` before writing it down.
- **`cd ..` one level short broke a `git add` pathspec.** Combined `cd
  apps/web-platform && … && cd .. && git add apps/web-platform/…` landed in
  `apps/` and refused `apps/apps/…`. Recovery: absolute path. Prevention: use
  absolute paths or `git -C <wt>` for staging.
- **First `run-verify.sh` exited 1.** Investigated — the reds were pre-existing
  stack-state noise (162 fixtures) plus the real 174 staleness that became the
  P1 fix. Prevention: none — the rule "investigate every non-zero" caught it.
- **No subagent spawn surface this session.** Review panel ran as 15 lenses
  executed inline, disclosed as `Reviewed-Coverage: sequential-fallback`.
  Prevention: none — the honest-mode mechanism worked; recorded for the record.
- **verify/174 staleness surfaced in QA, not review.** Recurring class — a
  future grant/policy change can re-introduce it. Prevention: the litmus grep
  above; candidate rule — a migration that revokes or narrows must sweep
  `supabase/verify/*.sql` for rows asserting the old posture in the same PR.

## Tags

category: workflow-patterns
module: supabase-verify-sentinels
issue: 11193
pr: 11253
