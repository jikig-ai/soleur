---
title: Dual-write mirror must fail CLOSED on the credential-clear (disconnect) path during a read-cutover soak
date: 2026-05-28
category: security-issues
module: apps/web-platform/server/workspace-repo-mirror.ts
issue: 4558
pr: 4559
adr: ADR-044
tags: [dual-write, read-cutover, credential, fail-closed, soak-migration, multi-agent-review]
---

# Dual-write mirror must fail closed on the credential-clear path

## Problem

ADR-044 relocates repo-connection state (`repo_url`, `github_installation_id` [a
GitHub App token grant], …) from `users` to `workspaces`. During the soak, the
WRITE path dual-writes (`users` authoritative + a best-effort mirror to
`workspaces`) while the READ path already reads `workspaces` ONLY
(`getCurrentRepoUrl` / `resolveInstallationId`).

The mirror (`mirrorRepoColsToSoloWorkspace`) was uniformly best-effort: on error
it reported to Sentry and returned without throwing, rationalized as "the `users`
write stays authoritative until decommission." That reasoning is correct for the
read path's *absence* direction but wrong for the credential-clear direction:

- **Connect** + mirror fails → read path shows "not connected" (safe-fail; the
  next connect/sync re-mirrors).
- **Disconnect** + mirror fails → `workspaces` retains the live
  `github_installation_id` + `repo_url`. The read path is workspaces-only, so the
  user "disconnected" but the agent can still resolve the stale credential and
  act under the supposedly-revoked GitHub grant. The agent-runner revalidation
  guard `if (repoUrl && installationId === null)` structurally CANNOT catch it —
  both values stay non-null.

## Solution

Make the mirror **asymmetric**: best-effort by default (connect), fail-closed on
the credential-clear path. Added an opt-in `{ throwOnError: true }` to
`mirrorRepoColsToSoloWorkspace`; the disconnect route passes it and returns 500
on failure so the (idempotent) disconnect is retried rather than reporting a
disconnect that left the credential readable. Connect paths keep the default
best-effort behavior.

Defense-in-depth: extended the ADR-044 pre-decommission drift gate (P.3 / AC15)
to also check `github_installation_id IS DISTINCT FROM`, not just `repo_url` —
the credential is the security-relevant divergence and the durable backstop if a
mirror silently fails before the fix lands everywhere.

## Key Insight

When a migration moves the READ path to a new table ahead of decommissioning the
old one, the "old table stays authoritative" framing is only half true: for any
column the read path already sources from the new table, the mirror to the new
table is **load-bearing, not best-effort** — at least in the *clearing*
direction. Audit every dual-write site by asking "if this mirror silently fails,
does the read path fail OPEN (shows stale presence) or CLOSED (shows stale
absence)?" Fail-open on a credential is a single-user-incident vector.

A second-order insight: the asymmetry is per-direction, not per-site. The same
helper is safe best-effort on connect and unsafe best-effort on disconnect, so
the fix is an opt-in flag at the call site, not a blanket throw.

## How it was caught

Two orthogonal multi-agent reviewers concurred independently:
`data-integrity-guardian` (rated P2 "dual-write divergence window") and
`user-impact-reviewer` (FINDING 1, highest, under the single-user-incident
threshold). Neither the unit suite nor `tsc` could surface it — the read path and
write path each looked internally consistent. This is another data point for
"multi-agent review catches bugs tests miss," specifically the
feature-wiring/composition class where module A (best-effort mirror) and module B
(workspaces-only read) are each correct in isolation but compose into a
credential-retention bug.

A parallel finding from the same review (`security-sentinel` +
`code-quality-analyst` concurring): legal Art-30 register prose had drifted from
the implementing migration — it quoted the literal column-level
`REVOKE SELECT (github_installation_id)` that migration 079 explicitly documents
as a no-op, and mislabeled migration 081 (the Art-17 erasure cascade) as a "TS
read-cutover." Reinforces the "legal-disclosure-prose must be grep-validated
against the actual migration" defect class for docs-that-describe-code PRs.

## Session Errors

1. **`set -uo pipefail` tripped `ZSH_VERSION: unbound variable`** in the
   `/soleur:review` classification predicate block (the harness shell snapshot
   references `ZSH_VERSION` unset). Exit 127; the predicate computation aborted
   mid-run. **Recovery:** re-ran the enumeration without `set -u`. **Prevention:**
   the review skill's classification block should use `set -uo pipefail` only
   after guarding harness-exported unset vars, or drop `-u`.
2. **frontend-anti-slop NUL-grep returned 0 files** (`git diff --name-only -z |
   grep -zE '…$'`) although 4 UI files matched the equivalent plain grep — the
   `$` anchor under `grep -z` did not match the intended paths. **Recovery:** ran
   `tier1-scan.ts` with explicit `--paths`. **Prevention:** note the `-z`/`$`
   anchor quirk in the review anti-slop hook snippet.
3. **`git add` path doubling** — CWD was `apps/web-platform` (left over from a
   vitest run) so `git add apps/web-platform/<path>` resolved to
   `apps/web-platform/apps/web-platform/<path>` (not found). **Recovery:** `cd`
   to the worktree root before staging. **Prevention:** already covered by the
   work skill's "Bash CWD does not persist" note — stage with worktree-root cd
   or repo-relative paths from a known CWD.
4. **Background vitest EXIT=127** — the CWD reverted to the worktree root after a
   `cd <root> && git commit` call, so `./node_modules/.bin/vitest` was not on the
   path. **Recovery:** re-ran as `cd apps/web-platform && ./node_modules/.bin/vitest`.
   **Prevention:** always chain `cd <abs-path> && <cmd>` in a single Bash call for
   worktree test runs (work skill already documents this).
