# Learning: A count-only drift-sentinel hotfix leaves the per-member presence assertions incomplete

## Problem

Issue #6233 reported `verify-migrations` red on `main` at
`068_jti_deny_rls_predicate_and_revoke_rpc.sql/jti_deny_policies_count_23` — an
aggregate count sentinel asserting exactly 23 RESTRICTIVE `*_jti_not_denied`
policies. A sibling migration (126, beta-CRM) had added 3 more policies, so the
count drifted to 26 and the sentinel failed, gating `deploy`.

PR #6229 (`a4d8208e8`) fixed the RED by bumping the count sentinel `23 → 26`
(and renaming `count_23 → count_26`) — the minimum to unblock deploys. But
#6229 used `Refs #6160`, never `Closes #6233`, so the issue stayed open, and the
count bump left the guard's **other half** incomplete: the file's count sentinel
now asserted `26` while only **21** per-table `*_jti_not_denied_policy_present`
presence assertions existed. The 5 policies added after the mig-068 base array —
`workspace_activity` (076), `kb_files` (077), and `beta_contacts` /
`interview_notes` / `beta_contact_stage_transitions` (126) — had **no** per-table
check, and the file header falsely claimed "each of the 26 tables has its own
policy."

## Solution

Add the 5 missing per-table presence assertions (mirroring the existing 21
verbatim, table name substituted), spliced mid-`UNION ALL`-chain before the
terminal `;`-ended anon-REVOKE block, and correct the header comment so the
**named set (26) equals the aggregate count (26)**. Verify-SQL only; no runtime,
schema, or DDL change. Verified read-only against live dev before commit: the
full query returned 35 checks, 0 failing, 26 per-table checks passing.

## Key Insight

An **aggregate count sentinel** (`..._count_N`) and its **per-member presence
assertions** are two halves of the same drift guard, and they answer different
questions: the count catches "a member was dropped/added" only in aggregate; the
per-member checks catch "the count is right but the *set* is wrong" (one dropped
+ one unrelated added → count still passes, identity is wrong). A hotfix that
bumps only the count to clear CI is a **legitimate but partial** fix — it
restores green without restoring the guard's identity half. When you bump a
count-N sentinel, either complete the per-member assertions in the same PR, or
file/track the residual so the count-vs-identity gap does not silently persist.

Corollary (already worked as designed here): a `#N` whose **literal** defect was
already resolved by a sibling hotfix is not a no-op close — scope the work to the
residual completeness gap the hotfix left behind (plan Phase 0.6 premise
validation caught the stale premise and re-scoped correctly).

## Session Errors

None detected. Clean run — planning, work, review (4 agents, 0 findings), and
QA (skipped: prose scenarios, behavior already live-verified) all passed first
try.

## Tags
category: best-practices
module: apps/web-platform/supabase/verify
related: "#6233, #6229, #5280 (all-members drift guard must rebase before ship)"
