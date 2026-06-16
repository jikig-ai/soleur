# Learning: a branch-switch in the user's workspace clone must `-f` against the auto-commit allowlist's dirty non-KB tree

## Problem

`syncPush`'s new protected-branch fallback (#5426, `apps/web-platform/server/session-sync.ts`
`runProtectedFallback`) accretes the KB tree onto a `soleur/kb-sync` side branch by switching
branches in the user's workspace clone: `git checkout -B soleur/kb-sync origin/<side|default>`.

The workspace clone is NOT clean at push time. `syncPush`'s auto-commit step stages and commits
ONLY paths matching `ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//]` (the #2905 allowlist), and
deliberately leaves every other tracked file dirty so non-KB agent-session edits never land in PRs
the loop didn't author. A plain `git checkout -B <branch> <start-point>` ABORTS
("Your local changes to the following files would be overwritten by checkout") whenever a dirty
tracked non-KB file differs in the start-point's tree. For a multi-session protected-repo user whose
default branch had upstream non-KB churn since the side branch was created, that abort recurs every
session — the fallback silently strands and the user's KB is never delivered (fails safe: no data
loss, but no delivery either).

Multi-agent review caught it: `data-integrity-guardian` (P2, "silently blocks delivery") +
`user-impact-reviewer` (P3, "fails safe, no KB loss"). The unit tests with mocked git could not —
the mock treats every checkout as succeeding.

## Solution

Force the branch switch: `git checkout -f -B soleur/kb-sync <start-point>`. The `-f` discards only
local MODIFICATIONS to tracked files (untracked files are carried across untouched). Those discarded
edits are exactly the never-synced non-KB working-tree changes — never committed by `syncPush`, never
pushed, AND already discarded by the fallback's own success-path `reset --hard origin/<default>`. So
`-f` loses nothing the successful fallback wouldn't drop anyway; it only removes the abort that
stranded the unsuccessful one.

## Key Insight

When code switches branches inside the **user's workspace clone** (not a clean CI checkout), reason
about `ALLOWED_AUTOCOMMIT_PATHS` first: the clone always carries dirty non-allowlisted tracked files
by design. Any `checkout`/`checkout -B` against a start-point whose tree differs on those files
aborts. The safe force is justified only because the success path already resets `--hard` — i.e. the
discard is consistent with the path's existing end-state, not a new data-loss surface. Confirm that
equivalence before reaching for `-f`.

Companion observability pattern from the same review: when one Sentry op is pinned by an
issue-alert op-contract test but two distinct failure sub-modes route to it (here:
`kb-sync.protected-fallback-failed` for both "fallback ran and failed" and the `persistent_other`
"never attempted" branch), do NOT split the op (that breaks the contract test). Discriminate via
`extra.reason` instead — Sentry keeps one alert, the payload disambiguates.

## Tags
category: best-practices
module: session-sync
related: [[2026-06-16-realtime-event-guard-must-equal-fetch-query-scope]]
