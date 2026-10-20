# Learning: context-reviewed-gate.sh resolves cwd to the bare root on worktree commits

## Problem

During a `soleur:one-shot` run on `feat-one-shot-schedule-test-weight-tweet`
(2026-10-19), `.claude/hooks/context-reviewed-gate.sh` falsely denied two
`git commit` attempts inside `.worktrees/feat-one-shot-schedule-test-weight-tweet`.

The hook's `resolve_command_cwd` resolved the working directory to the **bare
repo root** rather than the worktree when `git commit` was issued without an
explicit `cd <worktree> &&` prefix in the command text. The bare root's stale
index happened to carry a sibling session's in-flight `last_reviewed` staged
deletions, so the gate evaluated the commit against the wrong index and denied
it — a commit on an unrelated branch blocked by changes it never made.

## Root cause

Same shape as the `.cwd`-less envelope class already recorded for
`guardrails.sh` block-commit-on-main (the reason worktree commits need
`git -C <path>` or an embedded `cd`): hook processes cannot see the agent's
logical cwd and fall back to a repo-level resolution that lands on the bare
root. `context-reviewed-gate.sh` inherits that blind spot for its index probe.

## Workaround that unblocked the run

Embed `cd <worktree-abs-path> && git commit ...` in the command text so
`resolve_command_cwd` resolves the worktree explicitly — equivalent in effect
to the `git -C <worktree>` guidance for the block-commit-on-main gate.

## Candidate fix

Extend `resolve_command_cwd` (or this hook's index probe) to prefer the
git-common-dir-aware worktree resolution the other gates now use, or track
with the `.cwd` envelope gap (#8254 umbrella). Filed here as a learning; a
hidden-constraint AGENTS.md rule is NOT warranted — the hook emits a clear
deny message, so the discoverability exit applies.
