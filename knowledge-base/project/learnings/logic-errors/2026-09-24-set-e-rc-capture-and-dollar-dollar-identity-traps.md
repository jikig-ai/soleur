---
module: System
date: 2026-09-24
problem_type: logic_error
component: tooling
symptoms:
  - "Purge script exited silently after printing only its scan header (set -e killed the process before the report)"
  - "Child bash -c process reported $$ equal to the parent pid, so an ownership guard passed when it should have refused"
  - "tc_tree_has_mount flagged every non-empty directory as containing a nested mount (%d is find depth, not device)"
  - "Every registered worktree vetoed as nested-git because the probe matched the candidate's own .git pointer"
  - "MIN_ASSERTIONS anti-vacuity floors set above the actual green count failed fully-passing suites"
root_cause: logic_error
resolution_type: code_fix
severity: high
issue: "#7004"
pr: 8738
tags: [bash, set-e, errexit, dollar-dollar, proc, scratch-reclamation, review-fix, footgun]
---

# set -e + plain-call rc capture, and $$ is not process identity under exec wrappers

## Problem

The review-fix tail of PR #8738 (`feat-tmp-scratch-reclamation`) kept dying
silently or misbehaving in ways that had nothing to do with the reclamation
logic itself. Three distinct bash footguns, all in the same session, all
recurring:

1. **`set -e` kills `fn "$x"; rc=$?` rc-capture.** A function called plainly
   that returns nonzero aborts the script *before* `$?` can be read. Three
   call sites in `tmp-classify.sh`/`soleur-tmp-purge.sh` needed
   `if fn; then rc=0; else rc=$?; fi`.
2. **`(( n > 0 )) && echo ...` at a function tail aborts under `set -e` when
   the count is 0** — the `&&` list returns 1, and since it's the last
   statement the function returns 1, killing the caller.
3. **`$$` is NOT process identity under exec-harness wrappers.** In the
   Devin exec environment (and any command-substitution/subshell wrapper),
   `$$` and `$BASHPID` report the *top-level session shell's* pid for every
   spawned child — a real `bash -c` child sees `$$` equal to its parent's
   pid, so a `[[ "$pid" == "$$" ]]` ownership guard passes for a process that
   is not the owner.

## Environment

- Module: `scripts/soleur-tmp-purge.sh`, `plugins/soleur/scripts/lib/tmp-classify.sh`,
  `scripts/lib/scratch-root.sh`, `tests/scripts/test-scratch-session.sh`
- Affected Component: ownership-keyed scratch reclamation (Reaper 3, session
  sweep, operator purge)
- Date: 2026-09-24

## Symptoms

- `test-tmp-purge.sh` exited rc=1 with output truncated after the first
  `=== test-tmp-purge ===` header — the suite's `set -e` killed it inside a
  `$(...)` capture that ran `fn; rc=$?`.
- `test-scratch-session.sh` reported `child cleanup deleted parent root`
  even though the implementation checked `SOLEUR_SCRATCH_OWNER_PID == $$`.
- `tc_tree_has_mount` retained *every* non-empty candidate (the false-positive
  nested-mount case) — 8 regression arms red at once.
- A marker-bearing worktree was quarantine-moved instead of taking the
  registry arm — the sweep's ordering ran marker before the `.git` file check.

## What Didn't Work

**Attempted Solution 1:** `$$`-based owner check
`if [[ "${SOLEUR_SCRATCH_OWNER_PID:-}" != "$$" ]]; then return 0; fi`
in `_soleur_scratch_cleanup`.

- **Why it failed:** `$$` in the child reported the *parent's* pid under the
  exec harness (confirmed by comparing `$$` to `readlink /proc/self` —
  `/proc/self` showed a new pid while `$$` stayed the session shell's). The
  ownership check read as "same process" for a different process.

**Attempted Solution 2:** `BASHPID` as a more-correct pid source.

- **Why it failed:** `BASHPID` collapsed identically under the wrapper — both
  `$$` and `$BASHPID` were bound to the session shell.

## Session Errors

1. **`set -e` + plain-call rc capture** — three sites (`tc_marker_owner_pid`,
   `tc_owner_pid_verify`, `tc_reap_decide` callers) needed `if` wrapping.
   **Recovery:** wrapped every rc-capture call site.
   **Prevention:** under `set -e`, NEVER write `fn "$x"; rc=$?`. The rc of a
   plain call is unreachable — it aborts first. Always `if fn; then rc=0;
   else rc=$?; fi` or `fn && rc=0 || rc=$?`.

2. **`(( ... )) &&` at function tail** — `run_scan`'s last statement was
   `(( skipped_odd > 0 )) && echo ...`; with zero skips it returns 1 and
   `set -e` kills before the report.
   **Recovery:** `if (( ... )); then echo ...; fi`.
   **Prevention:** a bare `&&`-list at function tail is a silent `return 1`
   under `set -e`. Use `if` blocks for trailing conditional output.

3. **`find -printf %d` is DEPTH, not device** — the mount probe flagged
   every non-empty dir.
   **Recovery:** `%D` is the device field.
   **Prevention:** when a `find -printf` field is load-bearing for a safety
   decision, check the manpage letter-case — `%d` (depth) vs `%D` (device)
   vs `%i` (inode) are all different and the letters look interchangeable.

4. **Nested `.git` probe matched the candidate's own `.git`** — `-mindepth 1`
   vetoed every registered worktree because the dir's own `.git` pointer
   file counted as a nested ref.
   **Recovery:** `-mindepth 2` (a worktree's own `.git` is at depth 1;
   nested worktrees live at depth ≥2).
   **Prevention:** when checking for *nested* refs, explicitly exclude the
   candidate's own top-level `.git` — it's the pointer, not a nested tree.

5. **`tc_tree_has_*` helpers missing `-d` guards** — regular files reported
   as mounted/git-bearing because `find FILE -mindepth 1` is empty and the
   `ls -A` fallback prints the filename.
   **Recovery:** `[[ -d "$1" ]] || return 1` at the top of both helpers.
   **Prevention:** any `tc_tree_*` helper that reasons about *contents* must
   guard on `-d` first — a regular file is not a tree.

6. **MIN_ASSERTIONS floors overshot actual green counts** — set 45/52 vs
   actual 42/47 → the anti-vacuity gate failed a fully-passing suite.
   **Recovery:** lowered floors to 38/44 (below the real count with headroom
   for conditional-arm skips).
   **Prevention:** set `MIN_ASSERTIONS` below the observed count, not at it —
   conditional arms (disk-base block, optional seams) legitimately reduce
   the count on some hosts.

7. **`begin` base normalization overreach** — flattening every `/tmp/...`
   explicit arg to `/tmp` broke test isolation and could escape a session
   root handed via TMPDIR.
   **Recovery:** normalize only the *implicit* base (unset arg → TMPDIR);
   an explicit arg is the caller's contract.
   **Prevention:** normalization is a default-path convenience — an explicit
   argument means the caller already chose.

8. **Long diagnostic detour on the `$$` collapse** — the inherited-cleanup
   arm failed nondeterministically in `bash -c` one-liners because my own
   test probes pre-expanded `$$` in single-quoted heredocs, producing
   contradictory readings before I switched to script files and `/proc/self`
   for ground truth.
   **Recovery:** wrote `$$`/`$BASHPID`/`readlink /proc/self` into a script
   file — only `/proc/self` reported the real child pid.
   **Prevention:** when a test arm's inner process must report its own
   identity, never rely on `$$` inside nested quoting — write a script file
   or read `/proc/self`. Quoting collapse is indistinguishable from a real
   pid bug until you isolate it.

## Solution

The ownership guard in `_soleur_scratch_cleanup` switched from pid-comparison
to **non-exported variable presence**:

```bash
# Before (broken under exec wrappers):
if [[ "${SOLEUR_SCRATCH_OWNER_PID:-}" != "$$" ]]; then return 0; fi

# After (kernel-safe):
# _SOLEUR_SCRATCH_FD is `declare -g`, deliberately NOT exported — only the
# process that ran begin() holds it. The exported SOLEUR_SCRATCH_* vars make
# the session visible to children; this non-exported holder-fd variable is
# what makes the DELETE path owner-only.
[[ -n "${_SOLEUR_SCRATCH_FD:-}" ]] || return 0
```

`begin()` opens a holder fd on the root via `exec {_SOLEUR_SCRATCH_FD}< "$root"`.
The fd is inherited by children (the liveness mechanism — an open fd in a
child marks the tree live), but the *variable* is not, so a child cannot know
the fd number and cannot pass the check. The pid check is redundant once the
fd-var check is in place, and the fd-var check is immune to `$$` collapse.

## Why This Works

1. **`set -e` semantics:** a function called plainly is a simple command;
   a nonzero return fires errexit. `if`/`while`/`until`/`!`/`&&`/`||` context
   disables errexit inside the function *and* gives the caller the rc.
2. **`$$` vs `/proc/self`:** `$$` is a shell variable bound at shell startup;
   under command-substitution wrappers it can reflect the *invoking* shell's
   pid rather than the real process's. `/proc/self` is kernel truth. The
   fd-var approach sidesteps pid comparison entirely.
3. **`-mindepth 2`:** the candidate's own `.git` is at depth 1 relative to
   `find "$dir"`; nested refs live at depth ≥2. Same for `%D` vs `%d` —
   one letter, wrong field, every dir flagged.

## Prevention

- Under `set -euo pipefail`, audit every `fn ...` followed by `rc=$?` — the
  rc is unreachable. The lint `scripts/lint-shell-capture-exit.py` covers
  `x=$(cmd)`; the `fn; rc=$?` shape is the same defect in a different costume
  and is not yet linted.
- Any process-identity check that must distinguish parent from child should
  use non-exported shell state (a variable or a held fd) or `/proc/self`,
  never `$$`.
- Any `find` field used in a safety decision should be verified against the
  manpage — `%d`, `%D`, `%i` are all different and visually confusable.
- `MIN_ASSERTIONS` floors belong *below* the observed green count with
  headroom for conditional arms.

## Related Issues

- [[2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint]]
  — the `x=$(cmd)` costume of the same `set -e` defect; this PR's `fn; rc=$?`
  shape is the sibling the lint doesn't cover yet.
- [[2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch]]
  — same session-shape: a safety check that dies on the input it exists to
  detect.
