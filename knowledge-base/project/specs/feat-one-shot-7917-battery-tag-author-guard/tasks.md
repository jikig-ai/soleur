---
feature: battery tag-authorship guard
branch: feat-one-shot-7917-battery-tag-author-guard
issue: 7917
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-09-feat-battery-tag-author-guard-plan.md
date: 2026-09-09
---

# Tasks — battery tag-authorship guard (#7917)

Derived from `knowledge-base/project/plans/2026-09-09-feat-battery-tag-author-guard-plan.md`.
Phase order is load-bearing: **Phase 2 must not begin before Phase 1's RED transcript is committed.**

## Phase 1 — Preconditions (no product edits)

- [ ] 1.1 Re-run every measurement in the plan's `## Research Insights` against the branch tip; record drift.
- [ ] 1.2 Record `--enumerate all` output as the pre-change baseline:
      `env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash scripts/test-all.sh --enumerate all`
- [ ] 1.3 Record the current count of `_ENUMERATE` conjunct sites in `scripts/test-all.sh` (AC3a baseline).
- [ ] 1.4 Read `scripts/guard-vacuity-floor.test.sh`'s floor-shape detector; record the exact syntax form the new floor must take so the meta-guard can build a mutant for it.
- [ ] 1.5 Run the `hr-write-boundary-sentinel-sweep-all-write-sites` sweep at **tag-authoring** scope (not fetch scope): `git fetch`, `git pull`, `git remote update`, `git tag` creations, `git update-ref refs/tags/…`, `git push` with a `refs/tags` refspec — repo-wide, every spelling.
- [ ] 1.6 Demonstrate closure membership for each AC31 witness candidate; substitute a demonstrated site where it cannot be shown. Do **not** widen the closure to make the AC pass.
- [ ] 1.7 Check whether `.claude/hooks/pre-merge-rebase.sh` and `.openhands/hooks/pre-merge-rebase.sh` are held in parity by an existing assertion.

## Phase 2 — RED window (constraint 2). No offender is fixed here.

- [ ] 2.1 Add `--enumerate-commands <group>` to `scripts/test-all.sh`, parsed in the same pre-side-effect block as `--print-suite-globs`.
- [ ] 2.1.1 It sets `_ENUMERATE=1` **as well as** its own mode flag, so all nine `_ENUMERATE` conjuncts apply.
- [ ] 2.1.2 `_shard_enumerate_command_emit` emits tab-delimited argv; document the delimiter/escaping contract in the record's header.
- [ ] 2.1.3 `skip_suite` emits `SUITE_COMMAND_DECLINED`, a distinct record type — its `$3` is a display string, not argv.
- [ ] 2.2 Assert AC3(a) conjunct count unchanged, AC3(b) `_ENUMERATE=1` appears twice, AC3(c) bounded runtime and no nested `repo_boundary_classify` verdict.
- [ ] 2.3 Write `scripts/battery-tag-authorship.test.sh`:
- [ ] 2.3.1 Stage A — roots from `--enumerate-commands all`; hard ERROR on non-zero exit or zero records; resolver table incl. `bash -c`, `env … bash -c`, `bun test <dir>/`, nested runners; out-of-class ledger with a ceiling.
- [ ] 2.3.2 Stage A — three source-coverage witnesses (glob / repo-root `scripts/*.test.sh` / `tests/scripts/`); `MIN_ROOTS` with a no-downward-ratchet rule.
- [ ] 2.3.3 Stage B — over-approximated closure to fixpoint; delegate nested runners via `( cd "$REPO_ROOT" && INFRA_ORPHAN_LIST=/dev/null bash "$INFRA_RUNNER" --list )` with a floor and the declared-vs-parsed cross-check.
- [ ] 2.3.4 Stage C — occurrence pattern across the **verb** axis and the **spelling** axis; three verdicts only (`SUPPRESSED | EXEMPT | OFFENDER`); no `SCOPED`.
- [ ] 2.3.5 Stage C — `SUPPRESSED` requires the positive-suppression match **and** the negative conjunct (no `--tags`, `-t`, `refs/tags/` operand, `tagOpt`).
- [ ] 2.3.6 Stage C — read every site with `grep -n -B2`; `EXEMPT` requires the marker inside that window.
- [ ] 2.3.7 Stage C.2 — exemption ledger as a bijection, site-granular keys, open-issue citations, ceiling.
- [ ] 2.3.8 Stage D — `ck()` at call sites, conservation check, `BATTERY_TAG_MIN_ASSERTIONS` reported directly, helper self-test before any case, `SELF_EXCLUSION` and `FIXTURE_EXCLUSION` as two size-asserted arrays.
- [ ] 2.3.9 Every search site wrapped `{ grep … || true; }`.
- [ ] 2.3.10 Header states every place the enumeration is an approximation (bun directory expansion; tracked-files-only closure).
- [ ] 2.4 Register the suite with an explicit `run_suite` under `want_scripts`, anchored on the invoked path.
- [ ] 2.5 `git add` the new file — `guard-vacuity-floor.test.sh` sweeps `git ls-files`.
- [ ] 2.6 Assert AC2: `--enumerate all` differs from the 1.2 baseline by exactly one added line naming the new suite.
- [ ] 2.7 Run the guard with the ledger **empty**. Capture the verbatim transcript.
- [ ] 2.8 Commit the transcript into the plan as `## Measurement (RED window)`; carry it into the PR body.
- [ ] 2.9 Confirm the RED window is genuine: non-zero exit, or exit 0 with a non-zero `roots`/`occurrences` census. `roots=0` or `occurrences=0` fails this phase.

## Phase 3 — Mutation battery, written from the design

- [ ] 3.1 Build the `BATTERY_TAG_REPO_ROOT` / `BATTERY_TAG_RUNNER` injection seam; exercise it with the control run.
- [ ] 3.2 Control run first, in the same harness, required GREEN before any row verdict is read.
- [ ] 3.3 Implement Guard-1 rows 1-17 against synthetic fixtures; assert each RED row's mutation **landed** against a pristine copy (byte-identical ⇒ UN-RUN, not pass).
- [ ] 3.4 Implement Guard-2 rows 1-8.
- [ ] 3.5 Confirm every must-PASS row passes and none is the canonical fixture.
- [ ] 3.6 Ratchet `BATTERY_TAG_MIN_ASSERTIONS` and `MIN_ROOTS` to measured values; record the no-downward-ratchet rule in the guard's header.

## Phase 4 — GREEN

- [ ] 4.1 For each `OFFENDER` in the RED transcript, apply the cheapest correct closure — prefer suppression.
- [ ] 4.2 Where an exemption is unavoidable, add the `repo-boundary-tag-exempt:` marker inside the `-B2` window **and** a ledger entry stating why suppression specifically breaks that site, citing an open tracking issue. "It is fixture-scoped" is not an accepted reason.
- [ ] 4.3 Resolve every `UNCLASSIFIED` registration into the resolver or the out-of-class ledger.
- [ ] 4.4 Re-run: `offenders=0`, `unclassified=0`, non-zero census, ledger↔`EXEMPT` bijection holds.

## Phase 5 — Meta-guard and record

- [ ] 5.1 Re-measure `guard-vacuity-floor.test.sh`'s firing population; assert the new suite **by name** in its FIRES list and bump `MIN_FIRING_SUITES`.
- [ ] 5.2 Add the new numbered section to ADR-207 (reframed property; `EXEMPT` as accepted risk; ledger governance incl. "raising the ceiling is an ADR edit").
- [ ] 5.3 Add the cell-6 exemption-ledger row citing `scripts/battery-tag-authorship.test.sh`. Do **not** transcribe a population figure. Leave the existing Consequences closing sentence intact.
- [ ] 5.4 Verify AC29 with two independently range-scoped assertions, not a whole-file `grep -c`.

## Phase 6 — Quality gates

- [ ] 6.1 `bash scripts/battery-tag-authorship.test.sh` → exit 0
- [ ] 6.2 `bash scripts/lint-orphan-test-suites.sh` → exit 0
- [ ] 6.3 `bash scripts/guard-vacuity-floor.test.sh` → exit 0, new suite named in FIRES
- [ ] 6.4 `python3 scripts/lint-guard-contract.py` → exit 0
- [ ] 6.5 `bash plugins/soleur/test/c4-count-parity.test.sh` → exit 0
- [ ] 6.6 `bash scripts/lib/repo-write-boundary.test.sh` → exit 0, unmodified by this PR
- [ ] 6.7 `bash scripts/test-all.sh scripts` → exit 0
- [ ] 6.8 `bash scripts/test-all.sh` → exit 0
- [ ] 6.9 Walk `## Acceptance Criteria` 1-33 and record each verification command's actual output.
