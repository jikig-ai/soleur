# Session State — feat-one-shot-9763-local-test-speed

## Position
- Second sequential PR (per /go kickoff): #9762 shipped (PR #9766, squash 23aa2aaf86, release v3.329.0, issue closed). This worktree branched from `origin/main` @ 23aa2aaf86.
- Plan written: `knowledge-base/project/plans/2026-10-09-chore-local-test-speed-plan.md` — owner-authorized mechanism: split `ALWAYS_ON_SUITES` at 10 s committed-weight cap (126 cheap ≈198 s stay; 29 heavy ≈1100 s → `CI_HEAVY_SUITES`), ship Phase 4 `--affected` becomes the fast tier by construction, deterministic budget lint, P2-caching rejected.
- Next: `soleur:work` on this plan.

### Errors
- (carry-forward) ship battery for #9762 hit 6 environmental failures — all confirmed non-diff: repo had been converted to shallow (`--unshallow` fixed), transient archive.ubuntu.com outage (tracked #9394), contention timeouts. Isolated re-runs all green.
- (carry-forward) `lint-skill-body-budget` — work/SKILL.md at ~9 B headroom under 362 KB ceiling; any SKILL.md edit must be byte-frugal.

### Decisions
- Split axis = 10 s committed weight (only threshold leaving edge-headroom inside 300 s target).
- `CI_HEAVY_SUITES` runs locally only via own-file / consumed-edge arms; CI legs untouched.
- P2 caching rejected (staleness class vs ~2 min saving).
- Budget enforced by deterministic lint (Σ ≤ 300 s, per-suite ≤ 10 s), not a wall-clock gate.

### Components Invoked
- Skills: soleur:plan (inline passes — no Task/Workflow spawn on this harness)
- Commands: gh issue view/comment, git worktree add, suite-durations.tsv arithmetic
