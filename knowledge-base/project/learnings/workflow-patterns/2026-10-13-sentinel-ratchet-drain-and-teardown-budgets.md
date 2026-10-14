---
date: 2026-10-13
area: workflow-patterns
issue: 10096
pr: 10238
---

# Draining a sentinel ratchet: teardown timeouts must be sized to the helper, not the old call

## What happened

PR #10238 migrated 15 `test/server/**` suites from raw/best-effort
`admin.deleteUser` teardown to the canonical `tearDownTenantUser` helper and
drained `KNOWN_LEGACY_CARRIERS` to empty in the same commit (the sentinel's
stale-entry contract requires it). Review surfaced two classes of follow-up.

## Session errors (each with Prevention)

1. **`gh pr create` on a fresh branch fails** with "No commits between main and
   <branch>" — the worktree-manager creates the branch at origin/main; a draft
   PR needs a first commit.
   **Prevention:** commit the spec-dir scaffold (or plan stub) before
   `gh pr create --draft`; the pipeline expects a pushed commit anyway.

2. **`pipeline-tally.sh gate/incr` errors `missing-file` on a fresh worktree**
   — the tally ledger is per-worktree.
   **Prevention:** run `pipeline-tally.sh init` at worktree creation before the
   first gate call.

3. **`fix-round-seats.sh` arg-shape miss (second occurrence)** — it lives at
   `skills/review/scripts/fix-round-seats.sh` (not plugin `scripts/`) and takes
   `--files <newline-or-comma list>` + `--finding-seats <seat,...>`, no
   positional args.
   **Prevention:** `head -40` the script for Usage before invoking; pipe the
   diff list via stdin (`--files -`).

4. **Timeout enumeration missed `scope-grants/lifecycle`** — the CTO amendment
   named "≥2-user afterAlls", but a 1-user afterAll running ~26 sequential
   round-trips under the default 20s hookTimeout is the same risk. Review
   (three seats) caught it.
   **Prevention:** apply amendment *intent* (helper ≈24 RTs/user vs the
   enclosing budget), not the literal enumeration — audit EVERY site that
   gains a helper call, not just the named ones. Also: 8 pre-existing 30s
   afterAlls were sized for 2 bare deleteUser calls (2 RTs), not ~48 — a
   workload change invalidates a budget even when the budget text already
   exists.

## Design notes

- Loop-abandonment (first teardown throw skips remaining users) is a
  convention-wide property of all ~20 adopters — fixed-shape filed as #10249
  (plural helper), not per-file divergence.
- The sentinel's post-drain state is still load-bearing: empty
  KNOWN_LEGACY_CARRIERS + 6-key EXPECTED_CALL_COUNTS keeps the offender and
  count-pin tests enforcing.
