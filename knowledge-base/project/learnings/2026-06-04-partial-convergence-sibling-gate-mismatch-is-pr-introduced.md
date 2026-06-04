# Learning: partial source-convergence leaves a pr-introduced sibling-gate mismatch

## Problem

PR #4921 converged the leader agent's `workspacePath` from the legacy
`users.workspace_path` column to the ACTIVE workspace (`resolveActiveWorkspacePath`,
ADR-044) — mirroring #4910's Concierge half. The change moved ONE read (the path)
to the new source but left a SIBLING gate on the legacy source: `syncPull`/`syncPush`
in `agent-runner.ts` were still gated on the caller's solo `users.repo_status`.

The plan framed `repo_status` as "still legacy, tracked separately (out of scope)".
That framing was wrong. **Five orthogonal review agents** (data-integrity,
architecture, code-quality, user-impact, agent-native) independently flagged it: for
an invited member whose solo `repo_status` is null/`not_connected` but whose ACTIVE
(shared) workspace IS connected, the gate evaluated false → the leader's edits were
never pulled from / pushed to the shared remote. A silent write-loss window on shared
content — the exact #4543 divergence the path convergence fixes, re-created one branch
away.

## Insight

When a PR re-sources read A (path) to a new source of truth but leaves sibling gate B
(repo_status, an installation flag, a status enum) reading the OLD source, the
path/gate **grain mismatch is pr-introduced**, NOT a pre-existing scope-out — even
though gate B's code is untouched. Before the PR both reads were solo-keyed and
consistent (the skip was harmless); the PR creates the divergent state where they
disagree. Per `rf-review-finding-default-fix-inline`'s pr-introduced rule, this MUST
be fixed inline, not deferred.

Mechanical test: did this PR move read A to a source that read B does not also read?
If yes, B is now mis-keyed relative to A and the PR owns the fix.

## Fix

Don't re-derive gate B on the new source (extra query, more coupling). Prefer to
**drop the redundant outer gate** when the gated operation already self-guards on the
correct grain. `syncPull`/`syncPush` already check `hasRemote(workspacePath)` +
`resolveInstallationId(userId)` (active-workspace installation) + (push)
`hasLocalCommits` — so the outer `repo_status === "ready"` filter was redundant AND
mis-keyed. Removing it lets the operation's own guards (keyed on the converged path)
decide, and removes the dual-grain read entirely.

## Reusable rule

A "documented out-of-scope, tracked separately" note in a plan does not make a
finding pre-existing. If the diff is the surface that introduces the divergence
between two related reads, it is pr-introduced — fix it in the same PR or reduce the
PR's scope. Multi-agent review reliably surfaces this when the spawn prompt names the
two reads and asks "do they resolve from the same source post-diff?".
