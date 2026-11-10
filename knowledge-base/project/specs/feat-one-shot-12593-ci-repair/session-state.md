# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-11-10-fix-ci-main-red-baseline-literals-apt-repair-plan.md
- Status: complete (plan + deepen-plan run inline — no spawn tool in this harness; sequential-fallback disclosed in the plan's Enhancement Summary)

### Errors

None — all four deterministic defects reproduced live before planning; every fix mechanism verified against the suites' own documented regen paths.

### Decisions

- Full #12593 scope despite open sibling PR #12560 covering items 3+4 (it is red on legs items 1+2 cause — an interlock, not a collision; recorded in decision-challenges.md).
- Item 6 (rung-2 boot evidence) descoped: gate is non-required and the artifact is deliberately non-auto-committed.
- dpkg repair inside the existing per-attempt `timeout`, gated `try > 1`; header accepted-limit note updated; regression row with a `dpkg` stub.
- `contexts=12 producers=11` at test line 641 is a synthetic control input — audited, unchanged.

### Components Invoked

soleur:plan (inline), soleur:deepen-plan (inline gates pass), pipeline-tally, worktree-manager, cloud-detect

## Operator Constraints

- constraint: Verify each baseline regen produces ONLY the expected delta (the missing rows/sites named above) — a regen that rewrites unrelated content needs explanation in the PR.
- constraint: Baseline/test files may be oracle surface or ratchet-pinned — if the oracle gate or a ratchet rejects, follow that check's own documented escape (accept rows, etc.), never weaken the guard.
- constraint: Watch for the apt flake in your own CI run (FIXTURE_APT_CAUSE / dpkg was interrupted signatures are environmental — retry the leg via gh run rerun --failed rather than treating as your diff).
- constraint: Verify the true live values before editing — do not guess.
- constraint: PR body Closes #12593 is intentional.

no ci-is-the-gate token written (asked for local verification runs — brief requires executing the suites and verifying deltas)
