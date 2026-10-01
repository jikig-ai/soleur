---
title: The fence probe read the config the bootstrap writes, not the path a push takes
date: 2026-09-21
category: security-issues
module: git-data-cutover
tags: [git-data, guard, probe, review, hooks, transport]
issue: 8101
pr: 8454
---

# Learning: a guard for a runtime behaviour must read what the runtime reads

## Problem

#8101 asked for the git-data cutover to copy `hooks/`, and for the wrappers to assert which device backs the store. Planning found two things. The copy body had already been deleted: the cutover is now a read-only proof, with the rebuild tracked in #8211. And the three wrappers are hash-bound: editing them voids the rung-2 evidence. So the PR added a read-only **fence probe** to the dry run and moved the rest to #8211.

The first version of the probe checked three things:
- the hooks directory and `pre-receive` have the ownership and mode the bootstrap sets;
- the system `core.hooksPath` names the directory;
- the directory is on the store device.

Every row and all 29 mutants were green. But the structural-enumeration review seat mapped the states in which a push runs no fence while the probe still says `ok`, and found the probe was measuring the wrong thing:

- **Pushes don't consult the system config.** The transport wrapper runs `git -c core.hooksPath=${HOOKS_DIR}`, so the command-line pin governs every push. The probe never read the wrapper. An old installed wrapper, or one pinning a different path, would pass.
- **Git runs the hook as the `git` user, not root.** Root's `[ -x ]` passes where `git` cannot traverse or execute. When `git` can't run the hook, git skips it and **accepts the push**. This was measured with mode 000 on the hooks directory: the push went through with rc 0.
- **`git config --system --get` does not follow `[include]`.** The probe read `/mnt/git-data/hooks` while the effective value was elsewhere.
- **The hooks directory's parent was never checked.** If `git` can write it, `git` can swap the whole directory after the probe has run.

## Solution

The probe now reads the push path:
- the installed wrapper must carry both pin lines (the hooks default and the `exec git -c …` line), derived from the serving path;
- `runuser -u git -- test -r/-x` checks the hook, preceded by `runuser -u git -- true || exit 16`, so a broken `runuser` is reported as an instrument failure, not a fence verdict;
- the parent must be root-owned with no group or other write bit;
- `pre-receive` must be on the store source as well as its directory;
- `git config` is read with `--includes` and with `GIT_CONFIG_*` cleared.

Arguments are validated before anything is printed, and a passed empty argument is refused rather than falling back to a default.

The tests changed too. `stat`, `git` and `runuser` shims mean the suite executes every branch past the non-root CI user's reach, instead of only matching the command against a transcribed byte string. The runtime arm installs the **real** wrapper and a real `git` user, then breaks each one. Final counts: 38 mutants, exact floor 267.

## Key Insight

For a guard over a runtime behaviour ("a push runs the fence"), name the process that performs the behaviour. Then read what **that process** reads, **as that process's user**, through **its** config resolution. Do not read the configuration file the setup script writes.

A setup script and a runtime can both "configure" the same thing through different channels: a config file versus a command-line override, or root versus the service user. Checking the setup's channel is a correct check of the wrong property, and every mutant of it stays in-window.

Only the structural-enumeration seat, which maps *every path to the sink*, could see this. The ten seats that tested the probe as written could not.

## Session Errors

1. **`gh issue create` was blocked for a missing `--milestone`, and the heredoc body in the same Bash call was lost with it.** Recovery: write the body with the Write tool, then run the create as its own call. **Prevention:** already documented in `work/SKILL.md`. Follow it; no new rule needed.
2. **`gh issue create` was blocked because the body named no user-visible consequence.** Recovery: added the `User-Impact:`, `Fix-Size:` and `Mandated-By:` lines. **Prevention:** hook-enforced already. Include the trailer the first time.
3. **The first #8211 append said the probe "landed in PR #8454" while that PR was still a draft.** Recovery: re-edited it to "lands in". **Prevention:** in any outward-facing text written before merge, write a claim about an unmerged PR in the future tense.
4. **The probe design measured the setup's channel, not the push path.** Recovery: the review-round rewrite above. **Prevention:** added a plan sharp edge (see below). Name the process performing the guarded behaviour, and read its channel as its user.
5. **A suite run name built from `"$*"` contained `/`, and `run_case` failed with FAIL SETUP.** Recovery: `tr -c 'A-Za-z0-9_.=-' _`. **Prevention:** sanitize any fixture-derived file name at the point it is built.
6. **Adding one remote check made mutant M13's `sed` anchor match two lines, and the AC2 expected timeline needed re-transcription.** Recovery: re-anchored and updated. **Prevention:** anchor each deletion mutant on text unique to its line. `mutate()`'s exact-diff-count check caught this, as it is meant to.
7. **`rm -rf "$d"` was blocked as a protected path**, because the hook cannot expand the variable. Recovery: removed literal paths. **Prevention:** give `rm -rf` literal scratch paths.
8. **The shared `/tmp/claude-1000` reached its per-user quota (5.0G, 4.8G of it other sessions' files), and every tool call returned an exit code with no output.** Recovery: deleted this session's own scratch directories and the review agent's sandbox, and wrote diagnostics to `/data`. **Prevention:** tell spawned review agents to delete their `/tmp` sandboxes when they finish. When output vanishes while exit codes still arrive, check `df /tmp` and `du /tmp/claude-1000` first.
9. **Docker was unreachable locally (the user is not in the `docker` group), so the runtime arm could only run in CI.** **Prevention:** the local suite report and the PR should both state that the runtime rows are covered only by CI, and CI should be watched before merge.
10. **The command-capture shim did not answer `ssh -W` on its first version.** Recovery: added a `-W` banner arm. **Prevention:** one-off.
11. **A combined read command exited 4 with no output while the quota was full.** **Prevention:** same as 8.

## Tags
category: security-issues
module: git-data-cutover
