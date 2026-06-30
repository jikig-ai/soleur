# Learning: a 1:1 mirror of a DB-concurrency precedent silently breaks a NEW role's fencing-token contract

category: best-practices
module: apps/web-platform/supabase, multi-host-workspaces, review
date: 2026-06-30
pr: feat-5274-phase2-git-data-lease-fencing (epic #5274 Phase 2, PR A)

## Problem

PR A landed a per-`(workspace_id, worktree_id)` write-lease (`worktree_write_lease`,
migration 116) by **mirroring the canonical `acquire_conversation_slot` precedent
(migration 029) 1:1** — same RLS-only posture, same fenced-upsert, same
advisory-xact-lock, same `release_*` that **DELETEs the slot row**. tsc passed, the
8 integration ACs passed live on DEV, and 4 of 9 review agents (security,
data-integrity, migration-expert, performance) returned APPROVE/PASS.

But `architecture-strategist` (corroborated by `data-integrity-guardian`'s
forward-looking note) flagged a **HIGH**: `lease_generation` is ALSO a **Kleppmann
fencing token** the host presents to the git-data pre-receive fence, which
ADR-068 §3 fixes as `reject gen < max` (a globally-monotonic-max compare). The
slot precedent's DELETE-on-release **resets `lease_generation` to the column
default `1`** on the next acquire. Phase-3 failure path: HOST_B takes over
(`gen=2`, git-data `max=2`) → HOST_B gracefully releases (row deleted) → next
acquire `gen=1 < max=2` → **the fence rejects every push = workspace write
outage** (the exact "commit silently fails to persist" brand-critical incident the
lease exists to prevent). The integration test AC2(d) even *asserted* the
reset-to-1 as correct — freezing the inverted invariant in a green test.

## Root cause

The precedent served a DIFFERENT role. `acquire_conversation_slot` is ONLY a
concurrency slot (mutual exclusion) — for which reset-on-release is harmless. The
new table reuses the same `lease_generation` column for a SECOND role: a fencing
token presented to a resource server. A fencing token's one non-negotiable
property is **per-resource monotonicity that survives lock release**. DELETE
destroys exactly that. The 1:1 mirror copied the lifecycle that was correct for
role (i) and silently wrong for role (ii). This is the precise seam where
"mirror the precedent" breaks down: **the precedent's invariants are guaranteed
only for the role it was built for.**

## Solution

CTO ruling (routed via the work skill's architectural-fork rule — a data-model
decision with material trade-offs and a USER_BRAND_CRITICAL failure mode is the
CTO's call, not the operator's, not resolved unilaterally): **tombstone-on-release**.
`release_worktree_lease` becomes an `UPDATE ... SET heartbeat_at = '-infinity'`
(retaining the row + its `lease_generation`) instead of a DELETE, so the next
acquire takes over *immediately* via the existing expiry disjunct while the token
keeps climbing. The git-data fence stays the unmodified dumb `reject gen < max`;
the FK `ON DELETE CASCADE` is untouched (Art.17 erasure intact — the tombstone is
non-personal operational state). AC2(d) inverted to assert gen climbs 1→2→3 and
never resets. Rejected: a per-resource sequence/side-counter (breaks the
single-atomic-statement acquire) and a fence-side `(epoch, gen)` scheme (wrong
Kleppmann layer — the crash path never releases, so the fence can't rely on
release-time clearing).

## Key Insight

**When you reuse a DB-concurrency precedent for a NEW role that adds a contract
the precedent never had (a fencing token, an audit-WORM row, a portability
export), enumerate the new contract's invariants and check each against the
precedent's lifecycle — do not assume a passing 1:1 mirror is correct.** The
monotonic-token responsibility belongs at the *lock service* (the lease), never
the *resource server* (keep the fence a dumb compare). A green test that asserts
the inverted invariant (`AC2(d) gen===1`) is worse than no test — it freezes the
bug as "correct." This is caught by `architecture-strategist` ONLY when the
review-spawn prompt names the downstream contract (ADR-068 §3) explicitly; the
mechanical mirror passes every other lens.

## Secondary insights

- **`pg_get_function_arguments` includes a `RETURNS TABLE` function's OUT columns**,
  so a verify-sentinel that pins named-arg parity via exact-string equality
  false-fails on a table-returning RPC (acquire's `host_id`, `lease_generation`
  OUT cols). Use `proargnames @> ARRAY['p_workspace_id', ...]` (array-contains)
  to pin only the INPUT arg names — it ignores OUT params. A supabase-js `.rpc()`
  routes by ARG NAME, and the typed-signature `has_function_privilege` checks do
  NOT catch an arg-name drift; the `proargnames` check is the CI-enforced guard
  (the opt-in integration test is the only other parity check and isn't wired
  into CI).
- **A new migration table with a user-transitive FK (e.g. `workspace_id`) trips
  `dsar-allowlist-completeness.test.ts` the moment it lands** — it must be
  classified in `DSAR_TABLE_ALLOWLIST` or `DSAR_TABLE_EXCLUSIONS`
  (`dsar-export-allowlist.ts`), and touching that file mandates the 4-doc
  legal-doc cross-document lockstep (privacy-policy + gdpr-policy +
  data-protection-disclosure + compliance-posture, + SHA repins + Eleventy
  mirrors) via `legal-doc-cross-document-gate.yml`. Plans that add ANY new
  user-FK table should pre-budget this lockstep as a deliverable, not discover it
  at the full-suite exit gate. The minimal honest treatment for an operational
  no-personal-data table is a DSAR **exclusion** + a `**Last Updated:**`
  changelog note in each legal doc (no new disclosure section — there is no
  personal-data processing to disclose).

## Session Errors

1. **Worktree deps under-hydrated** — `npm install` required before tsc/vitest. Recovery: ran it first per the resume. Prevention: one-off (resume already flagged it); the worktree-manager should hydrate on create.
2. **Migration number collision (115)** — origin/main landed `115_prune_cron_job_run_details` during the rebase, colliding with `115_worktree_write_lease`. Recovery: renumbered 115→116 + reconciled the dev ledger. Prevention: already covered by the pre-apply collision check (PR #4225 class) — re-run `git ls-tree origin/main` AFTER every rebase, not just at first apply.
3. **DSAR completeness gate failure** — the new table tripped `dsar-allowlist-completeness.test.ts`, forcing the legal-doc lockstep. Recovery: added the exclusion + 4-doc lockstep + SHA repins + mirrors. Prevention: anticipate at plan time for any new user-FK table (route bullet added).
4. **Fork hit session limit mid-task** — the legal-lockstep fork returned with no persistent edits. Recovery: did the lockstep manually (inspected `git status` to confirm the fork wrote nothing — never trust a session-limited fork's "done"). Prevention: one-off (external limit); verify a delegated agent's file output via `git status` before continuing.
5. **`pg` not installed** — Recovery: bun-installed in `/tmp` per the Supabase fallback chain. Prevention: one-off env; the fallback chain covers it.
6. **`bun add` to an empty dir produced no node_modules** — Recovery: created an explicit `package.json` first. Prevention: one-off bun quirk.
7. **CWD resets between Bash calls (bare-repo worktree)** — a sed batch failed on a relative `cd apps/web-platform`. Recovery: absolute paths. Prevention: already documented; always use worktree-absolute paths in compound/multi-call bash.
8. **Round-trip script wrong filename** (`116` vs actual `115`) → MODULE_NOT_FOUND. Recovery: `ls` the scratchpad, used the real name. Prevention: one-off naming slip.
9. **proargnames verify check initially wrong** (`pg_get_function_arguments` includes OUT cols) — Recovery: switched to `proargnames @>` before running. Prevention: captured as a secondary insight above.
10. **`check-tc-document-sha.sh` run from wrong CWD** (repo-root-relative globs) → 0-docs error. Recovery: re-ran from the worktree root. Prevention: the script is repo-root-relative; run repo-root-relative scripts from the worktree root, not the app dir.
11. **`package-lock.json` drift from `npm install`** (npm normalized `dev:true` on optional deps). Recovery: `git checkout -- package-lock.json`. Prevention: after a hydration-only `npm install`, restore the lockfile unless a dependency actually changed.
12. **Plan-vs-code architecture gap (gen monotonicity)** — the plan's 1:1-mirror-of-029 prescription was structurally incompatible with ADR-068 §3. Recovery: caught at review (architecture-strategist HIGH), routed to the CTO agent, fixed via tombstone-on-release. Prevention: the headline insight above — check a reused precedent's invariants against the new role's contract.
