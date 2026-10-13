# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-01-fix-stale-git-lock-sweep-worktree-plan.md
- Status: complete

### Errors
None. Notable: mid-drafting the plan file briefly showed on-disk edits the subagent had not authored (a "Lock-file set (revised per CTO)" heading), suggesting a transient concurrent writer/harness re-entry. It converged with intent; final committed file is coherent; git status showed only the plan + tasks files.

### Decisions
- Single chokepoint: new `sweep_stale_git_locks()` helper called once from `ensure_bare_config()` (before its first `git config` write at :144). All create paths + `cleanup_merged_worktrees:888` already route through `ensure_bare_config`, so one call covers both session-start self-heal and pre-create paths.
- Age-guard via mtime comparison (default 60s), mirroring the clock-skew-guarded age check at :989-999; future-dated locks treated as fresh — the brake against clobbering a live sub-second config writer.
- Scope to common `git_dir` config locks (`config.lock`, `config.worktree.lock`) as load-bearing; `index.lock`/`HEAD.lock` as defense-in-depth. Per-worktree lock dirs out of scope. bwrap/seccomp/SDK layer untouched (owned by feat-harden-agent-sandbox-5875).
- `set -e` hardening (arithmetic in `if`, guarded `rm`/`stat`) is the real implementation risk — folded into snippet + tasks.
- Root cause verified empirically (reproduced EEXIST wedge; "File exists", exit 255), disproving the bind-mount theory. Brand-survival threshold: single-user incident; requires_cpo_signoff: true.

### Components Invoked
- soleur:plan, soleur:engineering:cto, soleur:deepen-plan
