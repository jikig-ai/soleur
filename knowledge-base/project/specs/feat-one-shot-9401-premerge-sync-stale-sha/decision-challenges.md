# Decision Challenges — feat-one-shot-9401-premerge-sync-stale-sha

Recorded by `soleur:plan` (headless pipeline; no operator gate). Ship renders
these into the PR body / `action-required` issues.

1. **Scope choice: disjoint-delta policy over merge queue.** The issue's stated
   preference ("prefer GitHub merge queue") is not implementable today — the
   queue was adopted in #5780 and reverted 2026-06-30 because a blocking
   required `CodeQL` check and `merge_group` builds are mutually exclusive
   (`codeql-action#1537`, still OPEN 2026-10-01). The plan ships the issue's
   fallback arm instead of its preferred arm. This is a deviation from the
   issue's stated direction the operator should see: if CodeQL is ever made
   advisory, the merge-queue path becomes available again and this policy may
   be redundant.
2. **New opt-in flag rather than widening `--green-sha` silently.** The
   local-merge carryover arm is gated behind `--allow-local-merge` so existing
   callers keep the verified-merge-only contract. An alternative reading of the
   issue would extend `--green-sha` unconditionally; the flag trades one extra
   token at call sites for a non-widening of the existing guarantee.
3. **Disjoint-skip applies to all invocations, not only `--admin`/`--match-head-commit`.**
   A plain `gh pr merge` on a stale branch is refused by GitHub either way
   (checks pending on the synced head today; BEHIND after the skip), so gating
   the skip on flag presence would buy nothing. Taste-adjacent: if the operator
   prefers the skip only fire when a SHA is pinned, that narrows the win to the
   admin path.
