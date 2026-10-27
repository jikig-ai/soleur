# Learning: a tracked-file guard must read each probe's exit status, and a fix can break the state the guard was not written for

## Problem

The `/soleur:go` session-start gate restored `.mcp.json` from `main` unconditionally, so an uncommitted edit to the tracked file was replaced (#9622). The fix added a guard that keeps a tracked, dirty, symlinked or index-pinned file and prints `SOLEUR_SESSION_START_SKIPPED reason=mcp-json-dirty`.

Two defects shipped inside the guard itself and passed a 219-assertion suite, a self-run 13-mutation battery and shellcheck:

1. The first predicate asked "is it tracked?" with `git ls-files --error-unmatch`, and treated every non-zero status as "not tracked". That command exits 1 for an untracked path and 128 for a fatal error such as an unreadable index. With a corrupt index the guard fell through to the restore while `git show main:.mcp.json` (which reads only the object store) still worked, so the edit was overwritten.
2. The fix for a subdirectory-cwd finding changed `git show main:.mcp.json` to the cwd-relative `main:./.mcp.json`. A bare repo refuses that spelling, so the documented bare-root refresh (`wg-at-session-start-after-cleanup-merged`) silently stopped writing.

## Solution

- One probe, `git ls-files -v -- .mcp.json`, whose exit status is read: rc != 0 keeps the file (`cause=probe-failed rc=N`), empty output is untracked, tag `H` goes on to `git diff --quiet HEAD` (rc 1 = differs, rc > 1 = probe failed), any other tag is `index-flag`. A symlink is kept first and never compared.
- `rm -f` of the temp name before the redirect, so a pre-planted symlink is not written through.
- The `./` spelling only inside a work tree (`git rev-parse --is-inside-work-tree`); a bare repo keeps the root-relative form and treats nothing as tracked.
- The marker names its measured cause (`cause=symlink|index-flag|differs-from-head|probe-failed`), like the sibling markers' `verdict=`, `source=` and `rc=` fields. The `reason=` token is unchanged so substring consumers still match.
- Rows R12k to R12r cover assume-unchanged, the stale-HEAD incident shape, an unreadable index, the temp symlink, a subdirectory run, a main-equal symlink, a bare repo and a tracked `sub/.mcp.json`; R3c and R6 now assert the file's bytes on the two arms that deliberately skip the restore.

## Key Insight

Every git probe in a guard has at least three outcomes, and the guard must name which one it measured. `ls-files --error-unmatch`: 0 tracked, 1 untracked, 128 error. `git diff --quiet`: 0 clean, 1 differs, above 1 could not tell. Folding the third into the second makes the guard fail open on exactly the input where failing closed matters, and the unreadable-index fixture is one no author builds unless a reviewer names it.

A fix is also a change of state space: switching a path spelling to be cwd-relative moved the bare-root case from "works" to "refused", and no row covered the bare root. When a guard fix changes how a path is resolved, enumerate the git states (bare root, linked worktree, subdirectory, detached HEAD, unborn HEAD, no `main`) before and after, in throwaway repos.

Mutations that survived and why: dropping the bare-repo `elif` changes nothing on git 2.55 because `ls-files` in a bare repo returns rc 0 with no output; it stays as insurance for versions that refuse. Root-anchoring the tracked probe or the symlink test only differs when `main` also carries a nested `.mcp.json`, in which case the `main:./` read already protects the root file.

## Session Errors

1. **The first guard folded a probe error into "untracked" (security seat, P2).** Recovery: single `ls-files -v` probe with rc read. **Prevention:** for any guard over git state, list each probe's exit statuses before writing the predicate and fixture the error one (an unreadable index is `printf junk > .git/index`).
2. **My cwd-relative fix broke the bare-root refresh (architecture seat).** Recovery: `./` only inside a work tree, row R12q. **Prevention:** after changing how a guard resolves a path, re-run the git-state table (bare root, linked worktree, subdirectory) for the changed predicate in throwaway repos.
3. **A scripted test edit aborted on a mis-cased anchor and the next suite run showed the previous green.** Recovery: `git status --short` showed only `go.md` modified; re-ran with the right anchors. **Prevention:** after any scripted edit, confirm the target file appears in `git status` before reading a suite result (already documented in `work/SKILL.md`).
4. **Assertion-floor miscount (240 vs 239).** Recovery: the floor failed loudly and was corrected. **Prevention:** replace-in-place edits add no assertions; count only new `want_*` calls, or run the suite and copy the executed total.
5. **`gh issue create` refused by the filing hook (no user-visible consequence named).** Recovery: `Mandated-By: wg-when-an-audit-identifies-pre-existing` on its own line. **Prevention:** a filing that tracks a pre-existing defect found in review carries that mandate line from the start.
6. **Two stop-hook blocks for closing text that named an unperformed action while waiting on background seats.** Recovery: explicit `<stop>BLOCKED: ...</stop>` reasons. **Prevention:** when ending a turn only to wait for a notification, say so with the stop tag rather than narrating the next step.
7. **A throwaway-repo command ended with `cd /`, resetting the persistent cwd to the primary checkout.** Recovery: re-entered the worktree on the next call. **Prevention:** run scratch-repo work in a subshell `( cd "$d" && ... )`.
8. **`tasks.md` said R12h is RED before the fix; it passes before the fix.** Recovery: corrected in the outcome section. **Prevention:** derive "RED before the fix" claims from the measured RED run, not from the row's intent.
9. **Plan phase (forwarded): a scripted edit dropped a closing code fence, and a probe's `expected_output` carried a space.** Recovery: both fixed before the plan commit. **Prevention:** re-run the plan lints after any scripted multi-edit.

## Tags

category: logic-errors
module: plugins/soleur/commands/go.md, plugins/soleur/test/go-session-gates.test.sh

## Addendum — 2026-10-11 PR #9051 maintenance

The session-start gate completed asynchronously. Its final restore reads local
`main`, which lagged this feature branch's MCP profile configuration. The branch
was clean before the gate; afterward its generated `.mcp.json` diff replaced
profile-slot wiring with old shared-profile wiring. Reversed only that generated
diff and verified byte identity with HEAD. No browser was launched.

Session errors and prevention:

1. Broad source reads exceeded output budgets. Re-read the relevant sections
   in bounded chunks; truncation provides no complete-file evidence.
2. A previous `/tmp` gate helper and the installed CI-only reference were absent.
   Extracted the current canonical gates and read the reference from this
   worktree. Temporary helpers and installed references require existence probes.
3. An incoming Vitest wrapper was read from the pre-merge tree, where it did
   not exist. Read it with `git show <pinned-main>:<path>` before merging.
4. Sandbox lock writes and a GitHub network read failed. Retried the necessary
   operations through escalation; the successful cleanup still reported the
   temporary sweep's independent lock contention, which remains a skipped sweep.
5. Reversed the gate's generated MCP diff before its asynchronous execution
   finished; the final restore wrote it again. Awaited the gate's completion,
   reversed the generated diff again and verified the branch bytes. Future
   repairs of a gate's output must follow its completion, never a partial log.
6. A saved-description comparison looked in the feature worktree after its
   writer had omitted `workdir`. Used a fresh authoritative PR-description read
   in the feature worktree; every scratch writer and reader must share an
   explicit absolute working directory.
7. A repeated sentence placed the new verdict before an older dated section.
   The post-edit tail check caught it; moved it to the end using unique adjacent
   context. Append-only records require an end-of-file placement check.

These were visible failures or local execution mistakes; no new cross-cutting
rule or runtime qualification claim follows from this maintenance.

## Addendum — 2026-10-11 remaining acceptance preparation

The continuation repeated oversized combined reads and guessed absent source
filenames. Discovery with `rg --files` and bounded rereads corrected the scope;
no missing file or truncated output was treated as implementation evidence.
The tally was initialized after the first two read-only audit agents launched;
their seats were recorded before the third launch. Initialize and gate before
each spawn, including audit-only preparation.

Fresh scratch-runner generation initially used JavaScript replacement-string
metasyntax against a Python regex containing dollar/apostrophe characters. Syntax
checks caught the malformed copy before execution. Replacement callbacks and
direct line parsing produced the valid fresh artifact. Its first read-only
preview then refused a legitimate systemd filename containing `@`; bounded source
inspection corrected the admission grammar and preview passed. The old consumed
runner and authorization marker were preserved; no build or startup followed.

Local C.9 passed in the verified PID namespace without a code change. A green
isolated result narrows the observation; it cannot establish the earlier CI
failure's cause or close its tracker. Retain that distinction in handoffs.
