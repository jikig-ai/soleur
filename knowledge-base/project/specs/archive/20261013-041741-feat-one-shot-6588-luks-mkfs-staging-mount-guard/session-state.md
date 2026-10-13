# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-19-fix-workspaces-luks-mkfs-staging-mount-guard-plan.md
- Status: complete

### Errors
None. All gates passed; premise validation confirmed #6588 OPEN and every cited line/precedent verbatim. One self-correction during the pass: the required `hr-when-a-command-exits-non-zero-or-prints` citation was initially missing and was added.

### Decisions
- Root cause framed as a shape transplant across error-handling regimes. The git-data precedent's identical `mountpoint || mount` line is fail-*closed* because it runs under `set -euo pipefail`; the cutover copied the shape into a `set -uo pipefail` (no `-e`) script and dropped the `mkfs`. Deeper layer: every downstream gate (C1, `du`, `git fsck`, G3) is a pure function of two path strings — none anchors a path to a device, so no copy-gate could ever have caught this.
- The positive control must anchor `$MAPPER` to `$FRESH_DEV`, not just `$STAGING` to `$MAPPER`. `$MAPPER` is only a name; a stale mapper backed by a different container would otherwise pass every gate including the new one. Found independently by two correctness reviewers — the plan had reproduced the exact bug class it was written to fix.
- The stray-copy deletion was removed from scope. The dry-run carve-out was inverted — it would have placed an irreversible `rm -rf` of user source on the arm with zero human approval by construction. Replaced with a fail-closed `die` that blocks any cutover until remediated; deletion split to a follow-up PR that must name the AP-009 deviation.
- Loopback validation promoted to blocking Phase 1, escape hatch deleted. `losetup`/`cryptsetup` need no privileged container on `ubuntu-latest`, so infeasibility was never real.
- Six same-class sites folded in (`:670`, `:686`, `:693`, `:892`, `:899`, `rollback()` `:577` — all strictly-additive fail-closures). The `_same_dev` retrofit onto `:901`/`:911` was pulled: it would relax a currently-strict assert on the rollback-critical path on an unproven hypothesis, and the current code false-fails safely.
- Capacity gate moved in-scope: this PR is what first makes `ENOSPC` reachable, since the copy moves into a mapper strictly smaller than its source (LUKS2 offset ~16-32 MiB), and the delta rsync sits inside the freeze.

### Components Invoked
- `Skill: soleur:plan` -> `Skill: soleur:plan-review` -> `Skill: soleur:deepen-plan`
- Agents: `Explore` (learnings + precedent research), `soleur:engineering:cto`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `Explore` (verify-the-negative sweep), `best-practices-researcher`
- Gates: 4.4 precedent-diff, 4.55 downtime/cutover (fired, telemetry emitted), 4.6 user-brand impact, 4.7 observability, 4.8 PAT-shaped halt, 4.9 UI-wireframe (skipped — no UI surface)
