---
title: Pre-merge sync is conditional on file-set overlap; green-SHA certification carries across a provably docs-only disjoint delta
status: active
date: 2026-10-02
related_adrs: [ADR-032, ADR-217]
issue: 9401
---

# ADR-265: Disjoint-delta pre-merge sync skip and local-merge green-SHA carryover (#9401)

## Context

`.claude/hooks/pre-merge-rebase.sh` unconditionally merged `origin/main` and pushed before
every `gh pr merge` issued from a PR's own checkout, so every advance of `main` invalidated
the green head SHA and restarted the ~25-minute required-check set. On PR #9339 `main` was
moving roughly hourly, so the branch never stayed green long enough to merge — a stale-green
livelock. The same unconditional `-R`/`--repo` refusal kept `gh pr merge -R <repo> <N>` (the
drain/one-shot spelling) permanently in the resolver's legacy state, grading the session's
HEAD rather than the PR's.

`admin-merge-ready.sh --green-sha` already carried a certified-green verdict to a new head,
but only when the new head was GitHub's own *signed* merge (`gh pr update-branch`). A
locally-produced `git merge origin/main` push — the natural shape once the hook stops
syncing — arrived unsigned and was refused as `carryover-unverified`, leaving no path that
both skips the rewrite and certifies the merge the operator did run.

## Decision

This is a merge-policy trust-boundary decision: the hook's sync is *conditional* and the
certification gate gains a second, unsigned-merge arm.

1. **The pre-merge sync runs only when the incoming delta overlaps the branch's file set.**
   After the existing merge-base/`origin/main` up-to-date check and before the `rebase-main`
   lock, the hook computes `files(merge_base..HEAD)` ∩ `files(merge_base..origin/main)`. An
   empty intersection skips the merge+push entirely — HEAD stays byte-identical — and reports
   `delta disjoint` in `additionalContext`. A non-admin merge then receives GitHub's own
   not-up-to-date refusal (the same posture an absent hook leaves); an `--admin` merge lands
   the certified head unmodified. **The failure direction is preserved:** any error computing
   either file set falls through to the sync, so pre-#9401 behaviour survives whenever the
   disjointness proof cannot run. The policy is deliberately NOT extended to
   `sync-pr-behind.sh` (that is #8683's scope).

2. **Same-repository repo pointers resolve the PR head.** `-R`/`--repo`/`GH_REPO`/`GH_HOST`
   operands — flag and env-assignment forms, on BOTH the quote-stripped and raw command — are
   normalised to (host, owner/repo) and compared against the session checkout's configured
   `remote.origin.url` (the raw config value, not `remote get-url`, which resolves
   `url.insteadOf` rewrites). Only when every operand proves same-repo are the flag tokens
   stripped and resolution proceeds; anything foreign, malformed, or unverifiable leaves the
   pre-existing denial arms unchanged. A local-path or unparseable origin proves nothing.

3. **`admin-merge-ready.sh --allow-local-merge`** (requires `--green-sha`) certifies an
   unsigned local merge when it is provably contentless for the PR: still a 2-parent head
   with `parents[0] == G` and `parents[1]` an ancestor-or-equal of the base, AND every file in
   `compare(G…SHA)` appears in `compare(G…parents[1])` with the same status and a
   byte-identical non-null patch, AND every such file is docs-surface
   (`knowledge-base/`, `docs/`, `plugins/soleur/skills/`, `*.md`), AND none appear in the PR's
   own file list. Success grades `G`'s check runs with `reason=carryover-local-docs`.
   Refusals are not-ready (`carryover-local-not-clean` / `-nondocs` / `-overlap`), never
   errors; a truncated (≥300-entry) or unparseable compare is an `error`, like every other
   unreadable input. PR-controlled filenames never appear in deny output.

## Consequences

- A green head SHA on a branch behind `main` is no longer invalidated when the incoming
  delta is disjoint — the #9339 stale-green livelock is closed for that class.
- Merge queue (#4856, gated on github/codeql-action#1537 for CodeQL `merge_group` support)
  remains the preferred long-term answer; this change is the disjoint-delta policy the issue
  names as the interim fix, and it stays sound if a queue lands later.
- The `-R`/`--repo` drain spelling now resolves the actual PR head — review evidence is tied
  to the PR being merged, never to the session's checkout.
- The `--allow-local-merge` arm is strictly narrower than the verified arm: it only admits
  merges whose added delta is provably replayed, docs-only, and disjoint. Anything else falls
  back to waiting for the new head's own suite. Note the disjoint-skip's own path needs no
  carryover — the skip leaves the green head untouched, so `admin-merge-ready.sh <N> <G>`
  grades it directly. The local arm is the rescue for a hand-made merge; a hook-produced sync
  merge is categorically uncertifiable by it (its delta overlaps the PR's files by
  construction → `carryover-local-overlap`).
- **Residual (semantic coupling):** file-set disjointness is a *syntactic* proxy — a
  main-side change can still break the PR without sharing a path (cross-file callers, a
  rename/delete pair, a type a second file must satisfy). The skip is file-level; a broken
  combination is caught by post-merge `main` CI. The docs-only bound on the unsigned arm is
  a risk-tolerance bound on exactly this gap, not an anti-injection bound (patch-identity is
  the anti-injection bound).
- Small contract note: the gate's ready marker keeps a carryover arm's own reason token
  (`carryover-local-docs`) rather than `all-green` — the `REASON == "none"` sentinel in
  `check_once`.
- Known residual: an env-assignment-prefixed merge (`GH_REPO=o/r gh pr merge`, no command
  separator) still does not match the top-level intercept pattern — a pre-existing detection
  gap, unchanged by this work.
