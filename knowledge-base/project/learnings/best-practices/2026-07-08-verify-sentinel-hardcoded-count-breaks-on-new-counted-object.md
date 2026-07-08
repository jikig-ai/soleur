---
title: "A migration that adds an object counted by a hardcoded verify/ sentinel must bump that sentinel's count in the SAME PR — it surfaces only in the post-merge live-prd verify-migrations job"
date: 2026-07-08
category: best-practices
tags: [migrations, verify-sentinel, rls, jti-deny, ci, post-merge, drift-guard]
issue: 6160
pr: 6229
component: apps/web-platform/supabase/verify
---

# Verify-sentinel hardcoded counts break on a new counted object

## Problem

PR #6160 (beta-CRM, migration 126) correctly added 3 new RESTRICTIVE
`*_jti_not_denied` RLS policies (068/076/077 shape) to its 3 tables. Every
pre-merge gate was green — offline migration shape test, `tsc`, the full
`vitest run` (976 files), preflight, a 9-agent review, `/soleur:gdpr-gate`. The
PR merged.

Then the **post-merge** `web-platform-release.yml` run failed: `migrate` ✓ (the
migration applied to prd), but **`verify-migrations` ✗** → **`deploy` skipped**.
The failing sentinel was `068_jti_deny_rls_predicate_and_revoke_rpc.sql /
jti_deny_policies_count_23`, which asserts:

```sql
SELECT 'jti_deny_policies_count_23',
       CASE WHEN count(*) = 23 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public'
   AND policyname LIKE '%_jti_not_denied'
   AND permissive = 'RESTRICTIVE';
```

23 was correct before #6160; adding 3 policies made the live count 26, so the
hardcoded `= 23` false-failed a correct database. Result: a **deploy freeze** —
prod kept running the prior code (no outage; the new tables are additive and
unused by old code) until a hotfix (#6229) bumped the sentinel 23 → 26.

## Root cause

The sentinel is an **exact-count drift guard** against the live prd DB. Its value
(catching an accidental policy drop) is exactly what makes it break on a
legitimate policy ADD: the count is coupled to the total number of jti-deny
tables across ALL migrations, so any migration that adds one must bump the count.
Nothing offline reproduces this — the sentinel lives in `supabase/verify/*.sql`
and runs ONLY in the `verify-migrations` release job against a real Postgres
with all migrations applied. The offline migration shape test asserts the *new*
policies exist; it has no visibility into a *global* count invariant owned by a
different migration's verify file.

## Key insight

**When a migration adds an object that a `supabase/verify/` sentinel counts by a
hardcoded total (RLS policies, grants, triggers, indexes, functions of a named
class), bump that sentinel's count in the SAME PR.** The plan even flagged the
jti-deny pattern ("inherit 068's shape") and filed a follow-up (#6176) to add it
to two more tables — but neither the plan nor any pre-merge gate connected
"adding a jti-deny policy" to "the 068 verify sentinel counts jti-deny policies."
Adding a counted object is a two-part change: the object + the count.

## Prevention

- **At plan/work time:** when adding an RLS policy / grant / trigger of a class
  that has a `verify/` sentinel, `grep -rn` that class name across
  `apps/web-platform/supabase/verify/*.sql`; if a `count(*) = N` sentinel exists
  for it, bump N in the same PR (and the sentinel name/comment if they embed N).
  Canonical grep for this class: `grep -rn 'jti_not_denied\|_count_[0-9]' apps/web-platform/supabase/verify/`.
- **At review time:** for any PR adding an RLS policy / grant, the review-spawn
  prompt should ask "does a `verify/` sentinel count objects of this class, and
  does its hardcoded total need bumping?"
- **Structural (deferred):** an exact-count sentinel is brittle by construction.
  A more robust form asserts *per-table presence* (every tenant table that should
  have the policy has it) rather than a global total — it does not break on a
  legitimate add. Bumping the count is the correct minimal maintenance; converting
  to presence-based is a larger, separate improvement.

## Session note

The count was verified deterministically before shipping the hotfix: the prior
sentinel passed at 23 (so live = 23), migration 126 adds exactly 3
`CREATE POLICY *_jti_not_denied` statements, and the `migrate` job succeeded →
live = 26. (A live `pg_policies` count would have confirmed it directly, but
`pg`/`psql` were absent from the fresh hotfix worktree; the arithmetic is
provable from the migration content + the prior passing sentinel + the
successful apply, which is not a dashboard-eyeball but a derivation.)
