# Learning: a "never raises" stderr helper must survive a missing stderr, and a content-free locator must name YOUR frame

## Problem

PR2 of #10331 added a guarded `_note(exc, site)` to four shipped Python scripts so that swallowed
exceptions leave a class-name-only breadcrumb. The guard was `except (OSError, ValueError)`, which
a closed `sys.stderr` raises, and three suites proved it. Review found three defects that the
author's own mutation spot-check could not reach:

1. `sys.stderr` is `None` when fd 2 is closed (`cmd 2>&-`), so `sys.stderr.write` raises
   `AttributeError`, which the guard did not catch. In resolve-debt the helper ran inside an
   `except OSError` cleanup block, so the `AttributeError` replaced the original exception; in
   founder-check it ran inside the rc-4 fail-closed arm, so the verdict line was never printed.
   The helper added to make a swallowed error visible turned two of them into crashes.
2. The fix for "the rc-4 detail is a bare class name, undiagnosable" used the innermost traceback
   frame. For the common internal errors that frame is a stdlib one (`_execute_child:2156`), which
   points an agent at an unrelated line of the script. The locator must pick the innermost frame
   whose `co_filename` is the script's own file (`__file__`), and format the line number with `%s`
   (`tb_lineno` can be `None`).
3. Tests that "prove no marker fires on non-JSON lines" used fixtures that never reached the handler;
   the census floor was `calls >= 1`, so deleting any single noted site survived.

## Solution

- Model the failure of the helper's OWN dependency: catch `AttributeError` too (a missing stderr),
  and in signal-context code also `RuntimeError`. Put a `none-stderr` case in every probe.
- Locator: innermost frame in the script's own file, falling back to the innermost frame; no
  imports (an AST-pinned import surface forbids `traceback`).
- Pin the SET of site labels per script in the probe (`argv[2]`), record the attempted flush text,
  and instrument the handler (count `json.loads` failures) to prove a fixture reaches it.
- Lines written on the teardown path after the kill go through a `_log_quiet` that cannot raise.

## Key Insight

A guard sized to the failures you imagined (a closed file object) is not the guard for the failure
the platform actually produces (`None`). When a helper's contract is "never raises", enumerate the
states of everything it touches, including the module global being absent, and give each a test
case. And a diagnostic that drops exception text for privacy must still carry a locator in a frame
the reader can open; "innermost" is not "yours".

## Session Errors

- **`gh issue create` denied: heredoc body in the same Bash call, then missing exit label** — Recovery: wrote the body with the Write tool, added `meta/machinery` / `User-Impact:` lines — Prevention: already in work skill ("never heredoc an issue body into the same Bash command as a hook-gated `gh issue create`").
- **Follow-up issue refused at 6 lines / 3 files; plan had deferred it** — Recovery: CTO re-ruled, fix folded inline — Prevention: plans that defer a `str(e)`-class fix should measure its size first; the filing gate is the backstop.
- **Baseline suites run on the live tree while editing it** — Recovery: killed, rebuilt from a detached pristine `git worktree add` — Prevention: take a baseline from a pristine detached worktree when you will edit during the run (work harness sharp edges).
- **Affected gate edited under while queued** — Recovery: killed it, re-ran suites individually — Prevention: already documented (queued counts as running).
- **check10 manifest inserted out of C-collation order** — Recovery: `LC_ALL=C sort -u` — Prevention: the gate's own message prescribes it.
- **`pgrep -f` and `git stash list` denied by hooks** — Recovery: `proc.sh list_runs`; none needed — Prevention: hook-enforced.
- **Moved a test and renamed its variable with a global `replace`** — Recovery: diffed to confirm only my lines changed — Prevention: scope renames to the hunk.

## Tags
category: logic-errors
module: plugins/soleur scripts (redaction proxy, founder-check, resolve-debt, scan-ancestor)
