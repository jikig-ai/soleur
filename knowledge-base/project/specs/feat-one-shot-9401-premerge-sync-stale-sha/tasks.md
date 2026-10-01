# Tasks — chore(merge): stop the pre-merge sync from invalidating a green SHA

Plan: `knowledge-base/project/plans/2026-10-01-chore-premerge-sync-stale-sha-plan.md`
Issue: #9401 (closes)

## Phase 1 — Hook disjoint-delta skip (tests RED first)

- [ ] 1.1 Add fixture cases to `.claude/hooks/pre-merge-rebase.test.sh`:
      T-disjoint (origin/main advances on files outside the PR diff → exit 0,
      `delta disjoint` in additionalContext, `git rev-parse HEAD` unchanged, no
      push), T-overlap (shared file → merge+push runs), T-failopen (induced
      diff failure → sync runs).
- [ ] 1.2 Implement the disjoint check in `.claude/hooks/pre-merge-rebase.sh`
      between the `MERGE_BASE == REMOTE_MAIN` early exit and
      `acquire_lock rebase-main`: `PR_FILES`/`INCOMING` via
      `git diff --name-only`, sorted-set intersection; empty intersection →
      emit `additionalContext` containing `delta disjoint` + counts, `exit 0`.
      Any computation failure falls through to the existing sync.
- [ ] 1.3 Update the hook header comment documenting the disjoint policy and
      its failure direction (toward sync).

## Phase 2 — Same-repo `-R`/`--repo`/`GH_REPO`/`GH_HOST` resolution

- [ ] 2.1 Add fixture cases: `-R` scoped to the same repository resolves the PR
      head (state P: evidence range is the PR head, sync skipped from a foreign
      checkout); `-R` foreign-repo keeps state-L behavior; `--repo=` and
      attached `-Rowner/repo` spellings covered. Origins in fixtures are local
      paths — set a URL-shaped `origin` via `git remote set-url` (offline-safe)
      and use the existing `gh` stub.
- [ ] 2.2 Implement operand extraction + normalization in the
      `MERGE_TARGET_WHY` chain (https/ssh/git@ URL forms, `.git` suffix,
      case-fold); strip flag+operand from `_scan_args`/`_merge_args` output
      before the bare-number checks; `$SCAN`/`$CMD` parses must agree after
      stripping.
- [ ] 2.3 Keep non-GitHub/unresolvable origin ⇒ refused (state L), matching
      today.

## Phase 3 — `admin-merge-ready.sh` local-merge carryover arm

- [ ] 3.1 Add cases to `plugins/soleur/scripts/admin-merge-ready.test.sh`:
      local merge of G + docs-only disjoint delta + `--allow-local-merge` →
      ready, `reason=carryover-local-docs`; code delta → not-ready; smuggled
      file (absent from base delta) → not-ready; same-path-different-patch →
      not-ready; wrong first parent / non-merge head → not-ready; flag absent
      → unchanged `carryover-unverified`.
- [ ] 3.2 Implement the arm in `check_once`'s `GREEN_SHA` block after the
      verified-merge check fails: parents `[G, B]`, `compare(B...base)`
      ahead|identical, per-file `patch` equality between `compare(G...H)` and
      `compare(merge_base(G,B)...B)`, docs-only classifier + disjoint from the
      PR file list; paginate/fail-closed on incomplete compare results.
- [ ] 3.3 Update script header + `usage()`; check
      `plugins/soleur/test/admin-merge-ready-wiring.test.sh` for flag/usage
      pins and update if needed.

## Phase 4 — Docs + ADR

- [ ] 4.1 Update `plugins/soleur/skills/ship/references/settle-then-admin-merge.md`
      (detached-worktree bullet now scoped to overlapping deltas; `--green-sha`
      section gains the local-merge arm).
- [ ] 4.2 Update `plugins/soleur/skills/ship/SKILL.md` was-green carryover
      sentence — net ≤ ~300 bytes (274000 ceiling, 335 headroom).
- [ ] 4.3 Update `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 mirror sentence.
- [ ] 4.4 Annotate `knowledge-base/project/constitution.md`'s
      `[hook-enforced: pre-merge-rebase.sh]` line with the disjoint-delta
      exception.
- [ ] 4.5 Author ADR-264 (provisional ordinal — enumerate across `origin/*`
      refs at start; ship's `adr-ordinals` gate re-verifies) via
      `soleur:architecture`: green-SHA carryover over provably docs-only
      disjoint delta + conditional pre-merge sync.

## Phase 5 — Sweep + ship hygiene

- [ ] 5.1 `grep -rn 'delta disjoint\|allow-local-merge' plugins/ .claude/ docs/`
      for consistent token spelling.
- [ ] 5.2 Verify unchanged suites still pass:
      `.claude/hooks/pre-merge-rebase-parity.test.sh`,
      `.claude/hooks/pre-merge-rebase-headless.test.sh`,
      `.claude/hooks/incident-sandbox-coverage.test.sh`,
      `test/pre-merge-rebase.test.ts`,
      `.claude/hooks/ship-unpushed-commits-gate.test.sh` (T11 ordering).
- [ ] 5.3 AC checklist against the plan; `git diff` review of the hook for
      `set -eo pipefail` `|| true` hygiene on no-match greps.
