# Decision Challenges — feat-one-shot-worktree-config-lock-wedge

Persisted headless per plan-review routing (ADR-084). `/ship` Phase 6 renders these into the PR body + files an `action-required` issue for operator visibility.

## User-Challenge: fix-layer diverged from the coordinator's mid-task direction (evidence-driven)

**Stated direction (task brief + coordinator course-correction):** fix the wedge in `_config_lock_wedged`/`atomic_git_config` (brief), or in the **sweep** / by making **`git worktree add`** resilient against a bind-mounted-regular EBUSY lock (coordinator).

**What the evidence showed (Better Stack telemetry + local RC=255 repro + Dockerfile/workspace source + 5-agent panel):**
- The lock is a **chardevice** (`rdev=1:3`), not a bind-mounted regular file — the coordinator's/brief's "regular file / EBUSY-on-rm" premise does not match production.
- `git worktree add` **SUCCEEDS** on the non-bare workspace; the sweep never `rm`s a chardevice. Neither is the failing path.
- The real failure is `ensure_worktree_identity`'s raw `git config --local` write trying to overwrite the host-seeded **owner** identity with the image's `github-actions[bot]` **global** identity (`Dockerfile:212` vs `workspace.ts:246`) → EEXIST on the masked lock.
- Naively routing that write (my own v1 "Layer A") would "succeed" at **misattributing the user's commits to `github-actions[bot]`** — worse than the loud wedge.

**Decision:** the primary fix is **"stop clobbering the host-seeded owner identity"**, not a sweep/`git worktree add`/lock-routing change. This is a divergence from the operator's stated direction, made on decisive evidence, and is surfaced here rather than silently applied.

**Operator action (optional):** if you specifically want the sweep/lock-layer hardened regardless, see deferred issue #6186 (detector unification). The host-side Layer-B option (remove/replace the `Dockerfile:212` bot global, or set the sandbox `--global` to the workspace owner at provision) is flagged as a deepen-plan/architecture decision and may spawn its own issue.

## Deferred (tracked)

- **#6186** — unify `_config_lock_wedged` with the sweep node-classification (latent bind-mounted-regular / EBUSY-on-rm case; not the current production signature).
