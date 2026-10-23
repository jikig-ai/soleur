# Tasks — feat-one-shot-10921-corrupt-ancestry-flake

Plan: `knowledge-base/project/plans/2026-10-23-fix-g1b-corrupt-ancestry-fixture-flake-plan.md`
Issue: #10921 · closes #10921

Amended post plan-review (DHH + Kieran + code-simplicity + CTO-devex panel): stream pins,
charge convention, per-suite discriminators, selftest-capture contract, roster parity,
standing census, mint selftest driver. Deferred: two external `rm -f objects/` sites → #10956.

## Phase 1 — Setup + shared lib

- [x] 1.1 Write `plugins/soleur/test/lib/git-corrupt-graph.sh`: `dead_oid <repo>` (hash-object
  WITHOUT `-w`, BLOB type — `-t commit` on nonce bytes is fsck-refused on git 2.56, CTO ruling;
  constant nonce — absence, not uniqueness, is the property), `corrupt_walk_break <repo> <ref>`
  (forged commit, well-formed 40-hex parent = dead oid, `update-ref`), `corrupt_dead_tag <repo>
  <tag>` (forged tag object targeting a dead oid), `corrupt_skip <row> <cost> "<reason>"`
  (numeric `<cost>` validation per `arm_skip`; `SKIP (loud):` → stderr, `::warning::` → STDOUT —
  GH scans commands on stdout only; `%`/CR/LF sanitize). Header: #10921 + Arm-B reproduction +
  one-spelling rationale + forge-is-last-construction-step rule (repack traverses reflogs) +
  skip-producer registration contract. Every forge helper asserts non-empty `<repo>`
  (`assert_fixture_dir` precedent).
- [x] 1.2 `bash -n` + shellcheck per suite conventions; fixture-env adoption stays clean.

## Phase 2 — bump suite rewrite

- [x] 2.1 Source the lib in `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`.
- [x] 2.2 g1b.B7 (~L1593-1614): replace `main_commit c2/c3` + `rm -f` with `corrupt_walk_break`
  on `refs/heads/main` (keep `side_commit`/`seed_tag_at` — tag must still resolve).
- [x] 2.3 g1b.B7c (~L1627-1640): seed `vinngest-v1.1.37` BEFORE `corrupt_walk_break` (below-break
  objects unreachable afterwards), tag the forged tip; merged = exactly `{v1.1.38}` + stderr.
- [x] 2.4 g1b.B7a (~L1642-1661): `corrupt_dead_tag` — tag listed, `^{commit}` peel fails,
  merged = `v1.1.37` only. Peel precondition is CONSTRUCTION-INVARIANT (comment at site) — its
  own probe shape: tag listed ∧ peel fails ∧ merged == `{v1.1.37}` with clean stderr.
- [x] 2.5 g2b.I6 (~L2602-2614): `corrupt_walk_break` on `refs/remotes/origin/main` in `$H`
  (`merge-base` rc 128 + stderr verified — Kieran arm).
- [x] 2.6 Add `SKIPPED_ASSERTIONS=0` + `corrupt_skip` plumbing: per skip-eligible row —
  construction-invariant check (fail-only, ZERO counted) → walk-contract probe (contract =
  walk stderr NON-EMPTY, the SUT's acceptance — not `Could not read` text) → row. Tail:
  `TOTAL=$((PASS + FAIL + SKIPPED_ASSERTIONS))`, ceiling `<= <cap>`; `Results:` line appends
  `, $SKIPPED_ASSERTIONS skipped`. `st_run`/`st_moved` snapshot+restore `SKIPPED_ASSERTIONS`.
  Re-derive `MIN_ASSERTIONS` comment.
- [x] 2.7 Selftest rows: forced-skip → SKIP counted + warning, CAPTURED into file/var
  (`$LAST_OUT`/`STEP_OUT` pattern) — NO exercised `SKIP (loud):`/`::warning::` reaches suite
  streams (selftest-poisoning, Guard-1 row 8); readable dead-oid → FAIL not SKIP;
  charge-omission → floor fires; probe-forced-present → flagged.
- [x] 2.8 Standing census self-check row (fail-only, zero counted): grep `.github/scripts/test/`
  for under-`.git/objects` deletions across verbs (`rm`, `find -delete`, `unlink`, `rm -rf`) →
  zero hits. Roster-parity self-check: every `corrupt_skip` call-site name starts with a
  probe-registered prefix (rehearsal `_PROBE_NAMED`/`_SKIP_CALL_SITES` shape). Scope comment:
  census covers `.github/scripts/test/` only; external sites tracked in #10956.

## Phase 3 — mint suite

- [x] 3.1 Source the lib in `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`; rewrite
  fl.walk (~L1127-1138) to forged-tip construction (tag ON the forged tip — arm F verified).
- [x] 3.2 Same skip plumbing + tail arithmetic; re-derive `MIN_ASSERTIONS` comment; `Results:`
  line appends skipped count. Add a minimal st_run-shaped driver for the forced-skip path
  (bump parity — `mut_row` mutates the SUT, cannot exercise `corrupt_skip`).

## Phase 4 — cross-run observer

- [x] 4.1 `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`: second run-source for
  `pr-quality-guards.yml` runs sampled BY EVENT (`merge_group` required, `pull_request` for
  density — never `--branch main`/`conclusion==success`); markers `SKIP (loud): g1b.`/`g2b.`/
  `fl.`; per-SUITE discriminators (`=== test-<name>.sh ===` banners or `=== Guard 1b:`/`===
  Guard 3:` headers — verify at implement); per-SOURCE `observed >= 1` (zero-observed source →
  TRANSIENT, never pooled); per-source verdict strings (PASS/TRANSIENT/FAIL).
- [x] 4.2 `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh`: fed-log rows — marker
  present → hit; discriminator present + no markers → PASS; neither → TRANSIENT; pooled-vs-
  per-source observed row; roster parity (every enumerated prefix has ≥1 producer).
- [x] 4.3 Edit `.github/workflows/scheduled-rehearsal-skip-monitor.yml`: generalize/per-source
  alert title/body + remediation; one scope-comment header line (keep streak artifact name).

## Phase 5 — Verification

- [ ] 5.1 `bash .github/scripts/test/run-all.sh` → rc 0; g1b.B7/B7a/B7c, g2b.I6, fl.walk PASS.
- [x] 5.2 Packed arm: `SOLEUR_FIXTURE_PACKED=1` selftest arm repacks between seed+forge →
  identical outcomes (AC4).
- [x] 5.3 Forced-divergence: `CORRUPT_WALK_PROBE_FORCE=skip` → captured SKIP + `::warning::` +
  charged, suites exit 0 (AC5).
- [x] 5.4 Census self-check green; `git diff origin/main` touches no `.github/scripts/` file
  outside `test/` (AC10).
- [ ] 5.5 CI green on `Bash fixture tests for guard scripts`.

## Commit

- [ ] 6.1 `Closes #10921` in PR body (ship handles).
