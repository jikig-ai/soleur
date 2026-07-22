# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md
- Status: complete

### Errors
One recoverable block: the `iac-plan-write-guard.sh` PreToolUse hook rejected the first plan write on the phrase "operator-driven" in an AC. Resolved by adding the `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` marker (Phase 2.8 genuinely reviewed — no infra surface is introduced) and rewording the AC. No other errors.

### Decisions
- Rejected the source-fsck hoist the brief proposed. Git repos self-heal (`gc`/`repack`/`prune`/reflog expiry), so a pre-freeze baseline goes stale in the dangerous direction and can mask a genuine copy loss, letting Phase 5 wipe the plaintext original. Both sides run concurrently inside the freeze instead — `max(4.5,4.5) ≈ 5 min` on independent devices. A pre-freeze advisory probe survives separately (evidence, never the comparand) and runs in both arms.
- The differential must not become a no-op. Leading hypothesis (UNKNOWN — the deciding datum was discarded) is `fatal: detected dubious ownership`: cutover runs as root, container repos are uid 1001, so fsck exits 128 before reading an object. A naive rc-only differential would classify all 8 `preexisting` and go permanently green. Hence a separate aborting `probe_failed` class plus per-repo absolute `safe.directory`.
- Measured semantics changed the classifier: rc is a bitmask (corruption is rc 3, not 1); rc 0 does not mean clean (broken alternates, junk objects); a missing object is rc 2 with empty stderr (report on stdout). Set comparison is unconditional; the classifier is total with a fail-closed default.
- A linked worktree fsck'd at a copied path reads the original filesystem (measured: it follows its absolute `gitdir:` pointer back across the mount). Same for absolute `objects/info/alternates` — which is what hypothesis H2 actually looks like. Both detected and counted rather than silently mismeasured.
- Scope cuts from the simplicity review: dropped the `dst_only` classification (the `du` assert and G3 manifest already own it), collapsed per-workspace `skipped` rows into summary counters, cut 13 ACs to 9.

### Components Invoked
- `Skill: soleur:plan`
- `Skill: soleur:deepen-plan`
- `Agent: Explore` (empirical `git fsck` semantics, git 2.53.0)
- `Agent: soleur:engineering:review:architecture-strategist`
- `Agent: soleur:engineering:review:code-simplicity-reviewer`
- `Agent: soleur:product:spec-flow-analyzer`
- `gh issue list` (code-review overlap check — none), `gh issue view 6733` (open, P1)

## Cutover Context
- Triggering run: 29725194755 (2026-07-20, dry_run=false) — safe-aborted at the fsck gate, DP-6 auto-rollback, prod healthy.
- #6733 stays OPEN. Closed only by a completed cutover, never by this merge. PR uses `Ref`, not `Closes`.
