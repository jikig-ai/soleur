---
title: "A fix that hardens a COMPUTATION must sweep every CONSUMER of the computed value — especially consumers positioned before the computation"
date: 2026-06-08
category: bug-fixes
module: apps/web-platform/server/cc-dispatcher.ts
tags: [github-app, installation-token, ordering-bug, multi-consumer, self-heal, concierge]
related_prs: [5041, 5031, 4946]
---

# Learning: harden-the-computation ≠ fix-the-bug — sweep every consumer

## Problem

The hosted Concierge reported TWO errors when a founder asked it to fix an issue:
"GitHub API Forbidden (403)" + "No Git Repository in Workspace". PR #5031 had
just shipped to "harden the Concierge gh-403 installation self-heal" — yet the
user still hit both errors.

Both errors were ONE cascade. `realSdkQueryFactory` (cc-dispatcher.ts) resolves a
stored GitHub App `installationId` (often a cross-account/personal install holding
only `issues: read` on the org repo), then has THREE consumers of "the right
installation": the workspace clone (`ensureWorkspaceRepoCloned`), the GH_TOKEN
mint, and the C4 write tool. #5031 added an installation **self-heal** that
computes `effectiveInstallationId` (the entitled repo-owner install) — but the
clone ran ~64 lines BEFORE that computation and consumed the raw stored id. So:
stored wrong install → `git clone` 403 → fail-soft → workspace left `.git`-less
(`realGraftRepoClone` moves `.git` LAST as a success sentinel) → `worktree-manager.sh`
finds no repo → "No Git Repository in Workspace".

#5031 hardened the COMPUTATION of `effectiveInstallationId`. The mint and the C4
tool consumed it. The clone — the precondition for ALL git work — was the one
consumer still on the stored id, and it was positioned first.

## Solution

Pure in-function reordering, no new logic: hoist the owner/repo parse + the
self-heal block ABOVE `ensureWorkspaceRepoCloned`, and pass `effectiveInstallationId`
(not the stored `installationId`) into the clone. In every non-promotion branch
`effectiveInstallationId === installationId`, so the clone uses exactly the stored
install it used before whenever the entitlement gate (#4946) does not promote —
the fix never widens access (the fail-closed proof, AC2).

## Key Insight

**When a fix "hardens"/"fixes" a COMPUTED value, the work is not done until you
`git grep` every CONSUMER of that value and confirm each reads the post-computation
version — paying special attention to consumers positioned EARLIER in the function
than the computation.** A computation can be perfectly correct and still be
bypassed by a consumer that runs before it. The symptom (#5031's `gh issue create`
403) named the consumer the author was looking at (the mint); the actual
brand-survival consumer (the clone) was silent because its failure surfaced two
layers downstream as an unrelated-looking error.

This is the same family as the review-skill defect catalogue entries
"Multi-step saga fix that addresses only the reported failing step" and
"Credential/PII redaction fix that scrubs only the NEW path and misses the
pre-existing sink" — a fix applied at one site while a sibling consumer of the
same value/contract is left on the old behavior. The mechanical gate: enumerate
consumers (`git grep <computed-var>` + `git grep <the function the value feeds>`),
not just the site the symptom names.

## Session Errors

1. **Relative `cd apps/web-platform` failed in the worktree pipeline** — the Bash
   tool's CWD was already the app dir, so the relative `cd` errored "No such file
   or directory". Recovery: drop the `cd` (or use an absolute path).
   **Prevention:** in worktree pipelines always chain `cd <worktree-abs-path> && <cmd>`
   in one Bash call; never assume the relative CWD (already a documented work-skill rule).

2. **`mock.calls[0][0]` failed `tsc --noEmit`** (TS2532 "possibly undefined" +
   TS2493 "tuple of length 0 has no element at index 0") when asserting a
   cross-mock lockstep on a spy declared `vi.fn(async () => undefined)` — the
   zero-param implementation types `.mock.calls` as a zero-length tuple.
   Recovery: replaced the index-access cross-reference with
   `expect(spy).toHaveBeenCalledWith(expect.objectContaining({ field }))` per
   branch (which pins each consumer to the same constant, giving the same lockstep
   guarantee without the fragile typing).
   **Prevention:** assert mock call-args via `toHaveBeenCalledWith(objectContaining(...))`,
   not `mock.calls[i][j]` index access — index access on an inferred-signature spy
   trips strict tsc. If you must index, type the spy explicitly (`vi.fn<...>()`).
