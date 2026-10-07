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
