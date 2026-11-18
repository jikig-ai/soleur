# Tasks — feat-one-shot-oracle-bound-row

Plan: `knowledge-base/project/plans/2026-11-17-fix-oracle-review-required-bound-row-plan.md`
Issue: #12755 (standing tracker — referenced, never closed) | Epic: #11556

## Phase 1 — Seed the bound row

- [x] 1.1 Edit `scripts/required-check-wallclock-bounds.tsv`: insert
  `oracle-review-required<TAB>180<TAB>120<TAB>0.30` (literal tab bytes,
  exactly 4 columns) between the `vendor-pin-required` row (:58) and the
  `cla-check` row (:59) — position mirrors `scripts/required-checks.txt`
  ordering (:274 → :294 → :297).
- [x] 1.2 Same file: add a dated header seed note placed with the other
  dated notes (UMBRELLA RE-SEED precedent, :36):
  `# oracle-review-required seeded 2026-11-17: check went required via
  #12329 without a row; PR p90 139 s (n=30) / MQ p90 100 s (n=29) -> bounds
  180/120, margin 0.30`.
- [x] 1.3 Append a dated measured-history bullet to
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  under `## Measured history` (:287), in the style of the
  `2026-11-02 wallclock-p90 baseline (#11774 seed)` bullet (:371): seed
  values, n per surface, and why the row exists (`unbound` finding from
  the #12329 required-context add).

## Phase 2 — Commit-time verification (TSV-header-mandated)

- [x] 2.1 `bash scripts/watch-wallclock-p90-11774.sh --dry-run` — flagged
  set must not list `unbound: oracle-review-required`; the check's bound
  columns read 180/120 (not `—`); re-measured p90 ≤ seeded bound on both
  surfaces. If the API is unreachable, treat as blocked — never green.
- [x] 2.2 Conditional re-seed arm: if either surface's p90 drifted above
  its seed, re-seed that bound to the next-minute ceiling of the
  re-measured p90 and update the header note, the runbook bullet, and the
  plan's recorded numbers in the same commit (a loosen is legal only with
  the measurement recorded — TSV header rule).
- [x] 2.3 Parser spot-check:
  `awk -F'\t' '$1=="oracle-review-required"{print NF}'
  scripts/required-check-wallclock-bounds.tsv` prints `4`.
- [x] 2.4 Diff scope: `git diff --name-only origin/main...HEAD` ⊆ {the
  bounds TSV, this plan file, this spec dir, the runbook}.
- [ ] 2.5 PR body: reference #12755, #11556, #12329 contextually; NO
  `Closes`/`Fixes`/`Resolves` keyword against #12755 (standing tracker);
  include the `## Changelog` section the version-bump workflow reads.
