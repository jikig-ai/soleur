---
title: "A pre-push scanner whose 'could not run' outcome the PR can induce must stop the push"
date: 2026-10-26
category: workflow-patterns
tags: [secret-scanning, gitleaks, pre-push, exit-code-taxonomy, fail-open, review-panel, ship]
---

# Learning: classify a scanner's outcomes by who can induce them

## Problem

P4a of #10924 added a local `gitleaks` range scan before `soleur:ship` pushes. The plan and three CTO rulings
settled on `0` clean, `1` findings (stop), `43` not-run (record and continue, because "CI is the load-bearing
gate"), and a scan that read the PR's own `.gitleaks.toml`. A 12-seat review then measured what that design allowed:

- CI's scan starts at the pull request, after the push, and a pushed SHA stays reachable through
  `refs/pull/N/head` even after a force-push. So "CI gates it" was a statement about the merge, not the publication.
- Exit 43 was reachable from the diff itself: a deleted or broken `.gitleaks.toml`, an orphan branch, a `-diff`
  attribute, a crashed or timed-out scan. Each one made the scan skip itself and told the caller to push.
- The scan could also say CLEAN while scanning less than the range: gitleaks exits 0 with `[]` and a partial commit
  count when git cannot read an object, a committed `-diff`/`binary` attribute or a NUL byte hides a patch, and a
  checked-out `.gitleaksignore` (the PR controls the work tree) allowlists the PR's own secret.

## Solution

- Split the outcomes by who can induce them. `43` is for what only the environment can cause (no gitleaks, no work
  tree, a shallow clone). `44` is a stop for everything the PR's content can cause (timeout, rc >= 2, empty report,
  count mismatch, `ERR`/`fatal:` in an rc-0 scan, orphan branch). The default arm of the verdict function is the stop.
- Read the BASE's committed config through `git show`, never the work tree's and never HEAD's, and point gitleaks at
  the git dir so it cannot read a checked-out ignore file. A base without a config is NOT_RUN, not a fallback.
- Pin what changes the patch stream: `GIT_ATTR_SOURCE` set to the empty tree, `--text`, global/system git config
  replaced. Do not replace `HOME`: it broke every version-manager shim for no gain.
- Make the PATH clean before anything external runs: find the repo root with builtins, drop relative, empty and
  in-repo absolute entries, then run git.
- Put the guidance in the script's own output (a continue verdict prints the HEAD it covers; a stop prints
  "automated agent: STOP"), because the pointer text in a SKILL.md does not survive compaction.

## Key Insight

For any gate that can end in "could not check", ask of each such outcome: can the thing being checked cause it? If
yes, that outcome must stop, whatever a later gate would catch. A ruling that rests on "another gate backstops this"
is a hypothesis about that gate's timing and coverage; measure both before accepting it. And a ruling is a
hypothesis about the implementation too: two of the three here (HEAD config fallback, replaced `HOME`) had measured
defects the first time they were run against a real fixture.

## Session Errors

1. **A review seat ran its fixtures in the live worktree.** It committed on the PR branch, moved `origin/main` and
   wrote a git identity after another seat overwrote the shared scratchpad helper it sourced; a 150 MB probe file
   was also left in the worktree. Recovery: verified `HEAD`, `origin/main`, status and `git config --local`, removed
   the file. **Prevention:** brief every seat with a seat-unique helper name, mktemp-only fixtures with their own
   identity, and "never create files in the worktree"; re-verify `git status` and `origin/main` after each panel.
2. **The settled rulings had measured defects when implemented.** The `43`-continue class, the PR's-own-config
   scan and the HOME replacement each failed on first measurement. **Prevention:** before implementing a ruling
   that says "fail open because X backstops it", run X's trigger and timing on a fixture; the CTO route accepts
   evidence and amends.
3. **My fixes introduced defects the next round found, twice.** The base-config read had a HEAD fallback; the PATH
   filter ran `dirname` and `git` before it existed. **Prevention:** a fix to a trust boundary gets its own
   reject-direction fixture in the same commit (the review skill's "fix commit is the least-audited surface").
4. **Suite authoring bugs.** A stale global (`$R`) sent a fixture commit to the wrong repo and a later
   `reset --hard` dropped another; a fake `touch` was absent from a constructed PATH; bash's command hash masked a
   PATH shim; a stub count drifted from the range. **Prevention:** set the fixture variable explicitly before each
   `addfile`, use shell builtins (`: >file`) in PATH-constructed shims, and put the shim where the FIRST external
   command resolves it.
5. **Hooks and the stop hook fired on commands and closing text.** `pgrep -f`, a variable-bearing `git commit`, a
   compound `git commit`, and a closing sentence that named a future action. All correct refusals; **Prevention:**
   `git -C <literal path> commit` as its own call, `pgrep` without `-f`, and a `Paused:` line when waiting.
6. **`fixture-dir-operand-assert` is red on this host** because `/home/jean/.git` exists (its "non-repository"
   control resolves up to it). Environmental, not caused by this diff.
7. **Planning-phase snags (forwarded from session-state).** A blocked scratch `rm -rf`, a blocked scratch
   `git commit` and early-returning background waits; none affected the plan. **Prevention:** none beyond the
   existing hooks (the refusals were correct); wait on a captured PID or an rc file, never a polled pattern.

