# Tasks — feat-one-shot-10921-corrupt-ancestry-flake

Plan: `knowledge-base/project/plans/2026-10-23-fix-g1b-corrupt-ancestry-fixture-flake-plan.md`
Issue: #10921 · closes #10921

## Phase 1 — Setup + shared lib

- [ ] 1.1 Write `plugins/soleur/test/lib/git-corrupt-graph.sh`: `dead_oid <repo>` (hash-object
  WITHOUT `-w`, BLOB type — `-t commit` on nonce bytes is fsck-refused on git 2.56, CTO ruling),
  `corrupt_walk_break <repo> <ref>` (forged commit, well-formed 40-hex parent = dead oid,
  `update-ref`), `corrupt_dead_tag <repo> <tag>` (forged tag object targeting
  a dead oid), `corrupt_skip <row> <reason>` (`SKIP (loud):` + `::warning::` with `%`/CR/LF
  sanitization + `SKIPPED_ASSERTIONS` charge). Header cites #10921 + the Arm-B reproduction.
- [ ] 1.2 `bash -n` + shellcheck per suite conventions; fixture-env adoption stays clean.

## Phase 2 — bump suite rewrite

- [ ] 2.1 Source the lib in `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`.
- [ ] 2.2 g1b.B7 (~L1593-1614): replace `main_commit c2/c3` + `rm -f` with `corrupt_walk_break`
  on `refs/heads/main` (keep `side_commit`/`seed_tag_at` — tag must still resolve).
- [ ] 2.3 g1b.B7c (~L1627-1640): seed `vinngest-v1.1.37` BEFORE `corrupt_walk_break` (below-break
  objects are unreachable afterwards — sequencing trap in plan §Technical Considerations), tag
  the forged tip; merged set must be exactly `{v1.1.38}` + stderr marker.
- [ ] 2.4 g1b.B7a (~L1642-1661): `corrupt_dead_tag` — tag listed, `^{commit}` peel fails,
  merged set = `v1.1.37` only.
- [ ] 2.5 g2b.I6 (~L2602-2614): `corrupt_walk_break` on `refs/remotes/origin/main` in `$H`.
- [ ] 2.6 Add `SKIPPED_ASSERTIONS=0` + `corrupt_skip` plumbing: per skip-eligible row —
  construction-invariant check → walk-contract probe (skip on absence) → row. Tail:
  `TOTAL=$((PASS + FAIL + SKIPPED_ASSERTIONS))`, ceiling `SKIPPED_ASSERTIONS <= <cap>` (cap =
  skip-eligible rows' declared assertion cost). Re-derive `MIN_ASSERTIONS` comment.
- [ ] 2.7 Selftest rows (st_run harness): forced-skip → SKIP counted + warning; readable dead-oid
  → FAIL not SKIP; charge-omission → floor fires; probe hard-coded present → selftest flags.

## Phase 3 — mint suite

- [ ] 3.1 Source the lib in `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`; rewrite
  fl.walk (~L1127-1138) to forged-tip construction (tag ON the forged tip — arm F verified).
- [ ] 3.2 Same skip plumbing + tail arithmetic; re-derive `MIN_ASSERTIONS` comment.

## Phase 4 — cross-run observer

- [ ] 4.1 `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`: second run-source for
  `pr-quality-guards.yml` runs; markers `SKIP (loud): g1b.`/`g2b.`/`fl.`; suite-scoped
  positive-control discriminator per source (per-source `observed` — never one shared counter).
- [ ] 4.2 `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh`: fed-log rows — marker
  present → hit; discriminator present + no markers → PASS; neither → TRANSIENT.
- [ ] 4.3 Edit `scheduled-rehearsal-skip-monitor.yml`: generalize or make per-source the alert
  title/body and remediation lines (currently rehearsal-specific) so g1b/g2b/fl markers file
  correctly labeled issues (CTO ruling; probe's second source samples by event — merge_group
  preferred, never `--branch main`/`conclusion==success` on `gh-readonly-queue/*` refs).

## Phase 5 — Verification

- [ ] 5.1 `bash .github/scripts/test/run-all.sh` → rc 0; g1b.B7/B7a/B7c, g2b.I6, fl.walk PASS.
- [ ] 5.2 Packed-store arm: inject `git repack -ad` into a fixture-setup copy → identical row
  outcomes (AC4).
- [ ] 5.3 Forced-divergence arm: probe sees no stderr marker → SKIP + `::warning::` + charged,
  suite exits 0 (AC5).
- [ ] 5.4 `grep -rn 'rm .*objects/' .github/scripts/test/` → zero hits in the two suites (AC1);
  `git diff origin/main` touches no `.github/scripts/` file outside `test/` (AC10).
- [ ] 5.5 CI green on `Bash fixture tests for guard scripts`.

## Commit

- [ ] 6.1 `Closes #10921` in PR body (ship handles).
