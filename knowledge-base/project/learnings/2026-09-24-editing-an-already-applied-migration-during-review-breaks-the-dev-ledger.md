---
title: "Editing an already-applied migration during review breaks the dev ledger"
category: database-issues
module: supabase-migrations
tags: [migrations, ci, review, dev-ledger-parity, tenant-integration, bash, set-e]
date: 2026-09-24
pr: 8650
issue: 8486
---

# Learning: Editing an already-applied migration during review breaks the dev ledger

## Problem

PR #8650 (feat-8486-human-presence-guard) added migration 140. During the review phase,
two review findings (a forward-ordering note, a corrected "mirrors 137" claim) were fixed
by editing that migration file's header **comments** — no DDL change. The next
`tenant-integration` CI run failed on "Assert unmerged migrations match the dev ledger":
dev Supabase had already applied migration 140 at blob `361b03b3…` (from an earlier CI
run on this same PR, before the review edit), and the tree now had a different blob
(`5ab90bf2…`). The guard's message named the exact fix: "a migration applied to dev is
as immutable as a merged one" — comments included, because the guard compares **byte
identity**, not semantic DDL equivalence.

Separately, a small helper added to `audit-flag-flip.sh` during the same review pass
broke 3 existing test assertions (rc=1 instead of the expected rc=4):

```bash
_audit_failed_marker() {
  printf 'SOLEUR_BOOTSTRAP_AUDIT_APPEND_FAILED reason=%s\n' "$1" >&2
  declare -F soleur_op_ledger_note >/dev/null 2>&1 && soleur_op_ledger_note audit_append_failed "$flag" "$1"
}
```

Called as a bare statement (`_audit_failed_marker no-ack`, not part of an `if`/`||`
chain) inside a function running under the caller's `set -e`, the `&&` compound's own
exit code (1, when `soleur_op_ledger_note` isn't yet defined) aborted the enclosing
function before it reached its own `return 4`.

## Solution

**Migration immutability:** restored the file to be byte-identical to the applied blob
(`git cat-file -p <applied-blob-sha> > <file>`, verified via `git hash-object`). Moved
the substantive corrections into ADR-249's residual-risks section instead — an ADR has
no such immutability constraint, and the migration's own header can stay frozen forever.

**The `set -e` trap:** any helper meant to be "fire-and-forget" bookkeeping around an
already-reported failure must end `return 0` unconditionally, and any `declare -F ... &&
...` compound inside it must not be the function's last executed statement — wrap it in
`if`/`fi` so the compound's own truthiness never becomes the function's implicit exit code.

## Key Insight

Two review-time defect classes recur on PRs that touch migrations mid-review:

1. **A migration file is immutable the moment CI applies it to ANY database** (dev or
   prd), not just once it merges to main — even a comments-only edit reproduces the
   exact "unmerged migration drifted from the dev ledger" failure this repo already
   guards against for merged migrations. Before editing a migration file during review,
   check whether `tenant-integration` has already run on this PR (it applies migrations
   to the shared dev project on any PR touching `supabase/migrations/`). If it has,
   route the fix to the nearest non-frozen artifact (an ADR, the plan, a follow-up
   migration for genuine DDL changes) instead of the migration file itself.
2. **A "fire-and-forget" bash helper added under an existing `set -e` caller is not
   fire-and-forget by default.** Any compound expression (`cmd1 && cmd2`) as a bare
   statement propagates ITS OWN exit code to errexit, which can abort the caller before
   a later `return <N>` runs — silently changing an intended exit code. Every helper
   whose job is side-effect bookkeeping (logging, metrics, best-effort writes) needs an
   explicit, unconditional `return 0`.

## Session Errors

1. **Added `_audit_failed_marker` as a bare `declare -F ... && ...` statement, breaking
   3 test assertions (rc=1 vs expected rc=4).**
   Recovery: wrapped in `if`/`fi` with an explicit `return 0`.
   Prevention: any new bash helper added to a file running under `set -euo pipefail`
   must end its own body with an unconditional `return 0` unless its exit code is
   deliberately meant to propagate; grep the file for `set -e`/`set -euo pipefail`
   before adding a helper, not after tests fail.
2. **Edited migration 140's header comments during review; CI had already applied that
   file to shared dev, breaking `tenant-integration`'s dev-ledger-parity guard.**
   Recovery: restored the file byte-identical to the applied blob (found via the
   guard's own error message, which names the applied blob SHA); moved the corrections
   to ADR-249.
   Prevention: before editing any file under `supabase/migrations/` mid-review on a PR
   where CI has already run, check whether `tenant-integration` succeeded (which means
   dev already applied it) before touching the file at all — route any post-apply
   correction to a non-frozen artifact.
3. **`dev-ledger-parity.test.sh`'s pinned `PIN_LATER` literal did not include the new
   migration's `.down.sql`, failing the local unit suite before the live CI guard
   caught the same class differently.**
   Recovery: added the new filename to the pinned literal (the test's own comment says
   "A change here must be a reviewed diff of these literals").
   Prevention: any PR adding a migration whose `.down.sql` recreates a function/policy
   (later-row-sensitive shape) should expect to update this pinned set; not a bug, but
   easy to miss without running the full local suite (`bash
   apps/web-platform/scripts/dev-ledger-parity.test.sh`) before pushing.
4. **First CONCUR gate (code-simplicity-reviewer) ruled "fix-inline, ~10-20 lines" on a
   scope-out candidate (a durable committed ledger for refused-write events) without
   discovering that the naive implementation would break an existing tested invariant
   (`operator-ack-guard.test.sh`'s "tree isolation" assertion) or that a sibling
   candidate (a repo-wide destructive-call census) actually touches ~104 unrelated
   files.**
   Recovery: attempted the implementation, discovered the conflicts empirically, and
   re-ran CONCUR with the measured facts attached; it reversed to CONCUR-to-scope-out
   on the first candidate and DISSENT-with-a-narrower-fix on the second.
   Prevention: for a CONCUR ruling that authorizes a NEW file-write mechanism or a
   repo-wide sweep, attempt a minimal implementation (or at least the relevant grep/
   census) BEFORE trusting the ruling — a cold CONCUR pass reasons from the finding's
   own framing, not from the codebase's existing invariants.

## Tags

category: database-issues, workflow-issues
module: supabase-migrations, review-pipeline
