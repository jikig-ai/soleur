---
title: "Planning-subagent fabrication under file-read failure + output-corruption false 'untracked tree' conclusion"
date: 2026-05-29
category: workflow-patterns
tags: [one-shot, planning-subagent, bare-repo, tool-output-corruption, observability, sentry]
related_pr: 4597
related_sentry: "Sentry event github-c8bb0ef6 (2026-05-29, web-platform)"
---

# Planning-subagent fabrication + output-corruption false "untracked" conclusion

Context: `/soleur:go` → `/soleur:one-shot` on a production Sentry error
("no workspace matched (installation_id, repo)" in the Inngest function
`workspace-reconcile-on-push`). The fix itself was a one-symbol severity swap, but
the run hit two distinct failure classes worth recording.

## 1. A planning subagent that reports "file-read failure, recovered" cannot be trusted on specifics

The plan subagent's Session Summary said it hit filesystem read failures, wrote its
first draft against a **non-existent file tree**, then "recovered against the real
source." Its delivered plan still asserted, with confidence and line numbers, things
that did not match the real file:

- "the handler does not throw; it already calls `reportSilentFallback` + returns" — but
  an intermediate draft also claimed it *did* throw, and quoted a 97-line file that
  threw at line 60 with a `NonRetriableError` import. The **real** file is 259 lines,
  never throws, and has no `NonRetriableError` import.
- "`warnSilentFallback` is already imported and used in this file" — it was **not**
  imported (only `reportSilentFallback` was).
- wrong path (`server/lib/observability.ts` vs real `server/observability.ts`), wrong
  `retries` (claimed 1 then 3; real is 1), a fabricated "deadletter drain" site.

**Lesson:** the work skill's "plan-quoted numbers are preconditions to verify, not
facts" applies doubly when the planning subagent self-reports read failures. At
work-start, `Read` the real target file and re-derive line numbers / control flow
BEFORE editing. The plan is authoritative for **intent** (downgrade an expected no-op
out of the error budget), never for code specifics. The real bug was exactly one thing:
the no-match skip was mirrored via `reportSilentFallback` (`level: "error"`) instead of
the existing `warnSilentFallback` sibling (`level: "warning"`).

## 2. Under tool-output corruption, one `ls`/grep is not enough to conclude a tree is untracked

This session had severe, intermittent tool-output corruption (duplicated blocks,
swallowed sections, stale echoes interleaving across calls). On the strength of a
single wrong-path `ls` plus corrupted/duplicated output, I twice reached a
**catastrophically wrong** conclusion: that `apps/web-platform/` was gitignored /
untracked and belonged to a separate repository — and I even narrated a non-existent
user reply. It does not: `apps/web-platform/` is tracked in `jikig-ai/soleur`
(`git ls-files -- apps/web-platform/` → 1482 files; `git check-ignore` → not ignored;
`git rev-parse --show-toplevel` from inside it → the soleur worktree).

**Lesson:** before concluding a directory is untracked / a separate repo, require
**multiple mutually-corroborating git signals to agree**: `git ls-files -- <path>`
(count > 0 ⇒ tracked), `git check-ignore <path>`, `git status --short`, and
`git rev-parse --show-toplevel` from inside it. A lone `ls`/grep — especially under
output instability — is not evidence. And never act on a "user reply" that wasn't
actually received; re-read the transcript rather than filling the gap.

## The fix (for reference)

`apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`: swap the
no-workspace-match `reportSilentFallback(...)` → `warnSilentFallback(...)` (warning
level), and add a warning-level mirror to the schema-version deadletter drain (was a
silent `return`). Genuine-failure paths (resolve-workspaces DB error, per-workspace
sync failure, workspace-dir-missing) stay on `reportSilentFallback` (error level).
Tests assert the no-match + schema-gate paths call `warnSilentFallback` and NOT
`reportSilentFallback`; sync/dir-missing keep asserting error-level. See PR #4597.
