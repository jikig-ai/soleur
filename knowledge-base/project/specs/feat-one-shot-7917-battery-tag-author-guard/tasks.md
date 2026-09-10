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
Phase order is load-bearing: **Phase 3 must not begin before Phase 2's RED transcript is committed.**
(Plan phases are numbered 0-4; these are numbered 1-6. Tasks phase N = plan phase N-1, and tasks
Phase 6 has no plan-phase counterpart — it is the quality-gate walk over ACs 22-33.)

## Phase 1 — Preconditions (no product edits)

- [x] 1.1 Re-run every measurement in the plan's `## Research Insights` against the branch tip; record drift.
- [x] 1.2 Record `--enumerate all` output as the pre-change baseline:
      `env -u TEST_GROUP -u SCRIPTS_SHARD SOLEUR_DISABLE_SESSION_STATE=1 bash scripts/test-all.sh --enumerate all`
- [x] 1.3 Record the current count of `_ENUMERATE` conjunct sites in `scripts/test-all.sh` (AC3a baseline).
- [ ] 1.4 Read `scripts/guard-vacuity-floor.test.sh`'s floor-shape detector; record the exact syntax form the new floor must take so the meta-guard can build a mutant for it.
- [x] 1.5 Run the `hr-write-boundary-sentinel-sweep-all-write-sites` sweep at **tag-authoring** scope (not fetch scope): `git fetch`, `git pull`, `git remote update`, `git tag` creations, `git update-ref refs/tags/…` — repo-wide, every spelling. (`git push … refs/tags/…` is OUT: it writes to the remote, never the local ref store.)
- [x] 1.6 Demonstrate closure membership for each AC31 witness candidate; substitute a demonstrated site where it cannot be shown. Do **not** widen the closure to make the AC pass.
- [x] 1.7 (Answered at plan time — no work.) `.claude/hooks/pre-merge-rebase-parity.test.sh` exists but asserts only the shared gate contract, so it would NOT catch a suppression added to one copy and not the other. This guard is what catches that: both copies are closure members. Close them as a pair in Phase 4.

## Phase 2 — RED window (constraint 2). No offender is fixed here.

- [x] 2.1 Add `--enumerate-commands <group>` to `scripts/test-all.sh`, parsed in the same pre-side-effect block as `--print-suite-globs`.
- [x] 2.1.1 It sets `_ENUMERATE=1` **as well as** its own mode flag, so every existing `_ENUMERATE` conjunct applies. (`grep -n '_ENUMERATE'` reports 9 lines; a naive `grep -c` over the conjunct patterns returns 8 because it counts a comment and misses the parse arm — assert the SET of non-comment lines, per AC3(a).)
- [x] 2.1.2 `_shard_enumerate_command_emit` emits tab-delimited argv; document the delimiter/escaping contract in the record's header.
- [x] 2.1.3 `skip_suite` emits `SUITE_COMMAND_DECLINED`, a distinct record type — its `$3` is a display string, not argv.
- [x] 2.2 Assert AC3(a) conjunct SET unchanged (non-comment `_ENUMERATE` lines, exactly one added), AC3(b) `_ENUMERATE=1` appears twice, AC3(c) bounded runtime and no nested `repo_boundary_classify` verdict.
- [x] 2.3 Write `scripts/battery-tag-authorship.test.sh`:
- [x] 2.3.1 Stage A — roots from `--enumerate-commands all`; hard ERROR on non-zero exit or zero records; resolver table incl. `bash -c`, `env … bash -c`, `bun test <dir>/`, nested runners; out-of-class ledger with a ceiling.
- [x] 2.3.2 Stage A — three source-coverage witnesses (glob / repo-root `scripts/*.test.sh` / `tests/scripts/`); `MIN_ROOTS` set **provisionally**, with the no-downward-ratchet rule and its three defined cases (absent on `origin/main` / unavailable-or-sandbox / both present).
- [x] 2.3.2b Re-measure the nested-runner parse floor rather than copying `MIN_INFRA_DERIVED=90`.
- [x] 2.3.3 Stage B — over-approximated closure to fixpoint; delegate nested runners via `( cd "$REPO_ROOT" && INFRA_ORPHAN_LIST=/dev/null bash "$INFRA_RUNNER" --list )` with a floor and the declared-vs-parsed cross-check.
- [x] 2.3.4 Stage C — occurrence pattern across the **verb** axis and the **spelling** axis; three verdicts only (`SUPPRESSED | EXEMPT | OFFENDER`); no `SCOPED`.
- [x] 2.3.5 Stage C — `SUPPRESSED` requires the positive-suppression match **and** the negative conjunct (no `--tags`, `-t`, `refs/tags/` operand, `tagOpt`).
- [x] 2.3.6 Stage C — read every site with `grep -n -B2`; `EXEMPT` requires the marker inside that window.
- [x] 2.3.7 Stage C.2 — exemption ledger as a bijection, site-granular keys, open-issue citations, ceiling.
- [x] 2.3.8 Stage D — `ck()` at call sites, conservation check, `BATTERY_TAG_MIN_ASSERTIONS` reported directly with **zero slack**, helper self-test before any case, `SELF_EXCLUSION` and `FIXTURE_EXCLUSION` as two size-asserted arrays.
- [x] 2.3.9 Every search site wrapped `{ grep … || true; }`.
- [x] 2.3.10 Header states every place the enumeration is an approximation (bun directory expansion; tracked-files-only closure).
- [x] 2.3.11 Build the `BATTERY_TAG_REPO_ROOT` / `BATTERY_TAG_RUNNER` seam **here**, in the guard, not in the battery — otherwise the guard that produces the RED transcript is a different program from the one Phase 3 grades.
- [x] 2.3.12 Wrap the `--enumerate-commands` call in `timeout 120` so a regression is a red suite, not a hung gate.
- [x] 2.4 Register the suite with an explicit `run_suite` under `want_scripts`, anchored on the invoked path.
- [x] 2.5 `git add` the new file — `guard-vacuity-floor.test.sh` sweeps `git ls-files`.
- [x] 2.6 Assert AC2: `--enumerate all` differs from the 1.2 baseline by exactly one added line naming the new suite.
- [x] 2.7 Run the guard with the ledger **empty**. Capture the verbatim transcript.
- [x] 2.8 Commit the transcript into the plan as `## Measurement (RED window)`; carry it into the PR body.
- [x] 2.9 Confirm the RED window is genuine: non-zero exit, or exit 0 with a non-zero `roots`/`occurrences` census. `roots=0` or `occurrences=0` fails this phase.

## Phase 3 — Mutation battery, written from the design

- [x] 3.1 Create `scripts/battery-tag-authorship-mutations.test.sh` and register it with a `run_suite` line under the same three placement constraints as the guard. A battery that runs in no gate is issue #7942's defect, one directory over.
- [x] 3.1b Exercise the seam with BOTH controls: offender planted + seam set → guard reds; same offender + seam **unset** → guard does not see it.
- [x] 3.1c Assert seam-equivalence: the guard run against a pristine copy through the seam produces a census byte-identical to the un-seamed live run. This is what makes fixture verdicts transferable to the repo.
- [x] 3.2 Control run first, in the same harness, required GREEN before any row verdict is read.
- [x] 3.3 Implement Guard-1 rows 1-25 against synthetic fixtures. Each RED row asserts the guard's own census line for the **specific planted site**, not a bare non-zero exit; each mutation is scoped to a line range and its placement asserted; byte-identical ⇒ UN-RUN, not pass. An UN-RUN row fails AC19 — re-author the fixture, never drop the row.
- [ ] 3.4 Implement Guard-2 rows 1-10.
- [x] 3.4b Set-compare the battery's printed row IDs against the row IDs in `## Guard Contract`, both ways, so a commented-out dispatch loop cannot report 0/0 as success.
- [x] 3.5b If the control run is RED, stop: the guard has changed since the AC16 transcript. Fix and re-capture the transcript rather than proceeding.
- [x] 3.5 Confirm every must-PASS row passes and none is the canonical fixture.
- [x] 3.6 Ratchet `BATTERY_TAG_MIN_ASSERTIONS` and `MIN_ROOTS` to measured values; record the no-downward-ratchet rule in the guard's header.

## Phase 4 — GREEN

- [x] 4.1 For each `OFFENDER` in the RED transcript, apply the cheapest correct closure — prefer suppression.
- [x] 4.2 Where an exemption is unavoidable, add the `repo-boundary-tag-exempt:` marker inside the `-B2` window **and** a ledger entry stating why suppression specifically breaks that site, citing an open tracking issue. "It is fixture-scoped" is not an accepted reason.
- [ ] 4.2b File those tracking issues (`wg-when-deferring-a-capability-create-a`). Never `#7917` — this PR closes it.
- [x] 4.2c `scripts/lib/repo-write-boundary.test.sh` needs an exemption marker for its deliberate `git tag probe-tag` creations. Comment lines ONLY: `MIN_ASSERTIONS=57` and every classifier arm stay untouched (AC10).
- [x] 4.5 If the census reports `offenders=0` on the first run, do not treat it as success by default. Under the reframed property every undeclared site is an offender, and the plan counts ten undeclared sites in `worktree-manager.sh` alone — so a zero is far more likely to mean the classifier under-matched than that the tree is clean. Reconcile against the Phase 1 sweep before accepting it.
- [x] 4.3 Resolve every `UNCLASSIFIED` registration into the resolver or the out-of-class ledger.
- [x] 4.4 Re-run: `offenders=0`, `unclassified=0`, non-zero census, ledger↔`EXEMPT` bijection holds.

## Phase 5 — Meta-guard and record

- [ ] 5.1 Re-measure `guard-vacuity-floor.test.sh`'s firing population; assert the new suite **by name** in its FIRES list and bump `MIN_FIRING_SUITES`.
- [x] 5.2 Add the new numbered section to ADR-207 as §5, inserted after `### 4. The collision guard…` and before `## Consequences` (reframed property; `EXEMPT` as accepted risk; ledger governance incl. "raising the ceiling is an ADR edit"). Pick ONE home for the ceiling value and assert the guard's copy equals it.
- [x] 5.3 Add the cell-6 exemption-ledger row citing `scripts/battery-tag-authorship.test.sh`. Do **not** transcribe a population figure. Leave the existing Consequences closing sentence intact.
- [x] 5.4 Verify AC29 with two independently range-scoped assertions, not a whole-file `grep -c`.

## Phase 6 — Quality gates

- [x] 6.1 `bash scripts/battery-tag-authorship.test.sh` → exit 0
- [ ] 6.2 `bash scripts/lint-orphan-test-suites.sh` → exit 0
- [ ] 6.3 `bash scripts/guard-vacuity-floor.test.sh` → exit 0, new suite named in FIRES
- [ ] 6.4 `python3 scripts/lint-guard-contract.py` → exit 0
- [ ] 6.5 `bash plugins/soleur/test/c4-count-parity.test.sh` → exit 0
- [ ] 6.6 `bash scripts/lib/repo-write-boundary.test.sh` → exit 0, unmodified by this PR
- [ ] 6.7 `bash scripts/test-all.sh scripts` → exit 0
- [ ] 6.8 `bash scripts/test-all.sh` → exit 0
- [ ] 6.9 `bash scripts/battery-tag-authorship-mutations.test.sh` → exit 0, every row executed, per-row output captured as the artifact.
- [ ] 6.10 `bash plugins/soleur/test/scripts-shard-totality.test.sh` → exit 0 (AC23b — the suite the registration can break from outside the diff).
- [ ] 6.11 AC1 set-compare: the ordered `SUITE_COMMAND` + `SUITE_COMMAND_DECLINED` label stream equals the `SUITE_REGISTRATION` label stream.
- [ ] 6.12 AC30 (`77`/`78` not hard-coded outside knowledge-base), AC31 live-witness half, AC32 closure-containment assertion.
- [ ] 6.13 Walk `## Acceptance Criteria` 1-33 and record each verification command's actual output.
