# Test Design Review — PR #12127 (feat-one-shot-10861-pr5z-strict-zero)

Seat: `soleur:engineering:review:test-design-reviewer`
Worktree: `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10861-pr5z-strict-zero` @ `79db88e18b`
Target: `git diff origin/main...HEAD` — focus `plugins/soleur/test/ci-pr-affected-replay.test.sh` (+ `scripts/ci-pr-affected-replay.py`, `scripts/test-all.sh`, `scripts/ci-pr-affected-audit.{baseline,accept}.tsv`, `.gitattributes`, `ci.yml`, runbook).

## Evidence

- Focused suite run (report-only, no tree mutation): `bash plugins/soleur/test/ci-pr-affected-replay.test.sh --rows 458-461` → **715 passed, 0 failed, 715 assertions, 4 mutants**. `--rows` gates only `mutate`/`ow_mutate` sites; every `chk` row ran ungated, so the reworked rows were exercised live:
  - `ratchet state table: base absent / HEAD present is baseline-reintroduced …` PASS (`row_rt_reintroduced`)
  - `ratchet state table: a re-introduced baseline still prints each live pair as new-pair detail …` PASS (`row_rt_reintroduced_newpair`)
  - symlink, 150000-line cost, oracle, helper, floors, deleted/absent-both rows all PASS.
  - `mutant ratchet-adoption-refused is killed by row_rt_reintroduced` / `-reintroduced-tolerated` / `-live-gated` / `-content-weakened` — **4 of 4 killed**.
- Mutation instrument verified, not just read: `mutant_outcome()` (`:4282`, driven by `mutate()` `:4307`) copies the SUT to `$SANDBOX/mut-<name>.py`, asserts `old` occurs **exactly once**, requires the mutant to differ, `ast.parse`, import, and a green run of the named row on the PRISTINE SUT (cached `PRISTINE_OK`) before grading; `crashed`, `invalid`, `edit-failed`, `row-red-on-pristine` are never kills; duplicate (mutated-file,row) signatures are refused. All four `old` strings occur exactly once in `scripts/ci-pr-affected-replay.py` (verified by `grep -cF`; `:2058`, `:2075`). Harness control rows for each failure mode are present and green.
- The run confirms each new/changed assertion pins behavior a mutant defeats:
  - `! grep -q '^grown'` on the contentful arm (`row_rt_reintroduced`, `:2473`) is the ONLY discriminant for `ratchet-adoption-refused` (`:4889` widens the grown guard to fire base-absent; exit code and marker reason are identical under the mutant since reintroduced precedes grown in findings order — only the printed `grown\t…` line differs, and it lands on stdout where the `!grep` sees it) — killed, live.
  - The bl-empty arm (`rt_in good adopt 1 … --baseline scripts/bl-empty.tsv`) is the discriminant for `ratchet-reintroduced-content-weakened` (`head_text is not None` → truthy `head_text`; `""` skips the arm) — killed.
  - The `new`-empty adopt fixtures kill `ratchet-reintroduced-live-gated`; both arms kill `ratchet-reintroduced-tolerated`.
  - `row_rt_reintroduced_newpair` (`:2474`) pins BOTH the arm placement (marker = `findings[0]` = `baseline-reintroduced` only because the arm at `replay.py:2058` precedes the new-pair block at `:2061-2065`) and the `elif new:` co-firing.
- `DECLARED_TOTAL=599` = `^mutate ` 473 + `^ow_mutate ` 126 (counted); comment updated. `scripts/test-all.sh` arms `1-193` / `194-386` / `387-599` tile 1..599 contiguously; `scripts-shard-totality.test.sh` reads both dynamically (`_DECL_READ_RE`, `_rows_tile_check`) — no hardcoded `596` remains.
- Single deletion commit: `ab487915f1` is the only commit touching `scripts/ci-pr-affected-audit.baseline.tsv`; its `--stat` shows exactly the ruled coupling (git rm + `.gitattributes` line + 42 orphaned accept rows + replay.py arm + test rework + range bump). The drift-absorption commit `79db88e18b` adds only the `AFFECTED_PLUGINS_SOLEUR_TEST_CODEQL_TO_ISSUES_SWEEP_WIRING_TEST_SH_PATHS` edge (the suite exists on main, real read → declared edge, not an accept row — correct per the drain rubric).
- ci.yml step name `Ratchet the audit against the committed baseline` is byte-identical (0 `name:` lines in diff); only the job comment was edited — the observation-probe `STEP=` key is safe.
- PR body (`gh pr view 12127 --json body`): draft stub only, **no `## Test Pyramid` block** — checked; none required (no e2e-layer tests in the diff).

## Findings

- **P3** — `plugins/soleur/test/ci-pr-affected-replay.test.sh:2970`: chk label still reads *"a PR-tree helper that always reports adoption changes no verdict"*. The row body (`:2515`) and `rt_p_weak` (`:2285`) comments were retired to `baseline-reintroduced`, but this user-visible label was missed — under strict zero the weakened helper reports `baseline-reintroduced`. Cosmetic; the assertion itself is correct and green.
- **P3** — `plugins/soleur/test/ci-pr-affected-replay.test.sh:4889`, `:4895`: mutant names `ratchet-adoption-refused` and `ratchet-unresolved-base-is-an-adoption` retain the retired "adoption" vocabulary. Names are labels only (kill chains verified live), but the same retired-term sweep that fixed the comments should rename these for searchability. Related: `scripts/ci-pr-affected-replay.py:1869` docstring "never an adoption" is contrastive prose — borderline acceptable, but "never a silent base-absent" would be exact.
- **P3** — Co-firing coverage asymmetry: `row_rt_reintroduced_newpair` pins `new-pair` detail under the reintroduced marker, but `stale-line`/`baseline-dup`/`baseline-order` co-firing on a malformed re-add is asserted nowhere (the CTO ruling calls this co-firing "correct"; `row_rt_big_baseline`'s marker moved from `stale-line` to `baseline-reintroduced`, so the stale computation running under base-absent is now unpinned — a mutant gating `gone`/`dups`/`uniq!=sorted` on `base_text is not None` would survive). Impact is diagnostic-only (the verdict already refuses), but a `grep -q '^stale-line'` conjunct on `row_rt_big_baseline`, or a mutant `'    gone = [line for line in uniq if line not in live_set]' → '    gone = [line for line in uniq if line not in live_set] if base_text is not None else []'` proven by it, would close the pin for ~zero cost.
- **P3** — No battery mutant requires `row_rt_reintroduced_newpair` specifically (it does kill existing mutants — e.g. `ratchet-new-pair-first` flips the marker — so it is non-vacuous and verified, but a suppression mutant like `'    elif new:' → '    elif new and head_text is None:'` proven by this row would make the co-firing guarantee explicit). Optional.

No P1 or P2 findings. All settled rulings (rows 9–16) are implemented as decided — see Dissent below.

## Score Table

| Property | Score | Notes |
|----------|-------|-------|
| Understandable | 8/10 | chk labels are full-sentence verdict descriptions; row comments carry the why ("the `!grown` assertion keeps the reintroduced marker from masking a co-firing grown"). Two stale "adoption" labels (:2970, :4895) say one thing while the behavior is another — small dent. |
| Maintainable | 8/10 | Table-driven `rt_b_*`/`rt_p_*` fixture arms shared across rows; renamed rows updated at every reference incl. mutant proof-row args. Fixture composition (`rt_mk adopt rt_b_adopt rt_p_adopt`) makes the state-table mapping readable without the SUT. |
| Repeatable | 10/10 | Hermetic `git init` fixtures in `$RT`, stubbed selector/gh/`git`, no wall-clock equality — the one measured quantity (150000-line run) is BOUNDED (`< 25 s`), not pinned; correct per the bound-don't-pin rule. 715/715 green on my run. |
| Atomic | 9/10 | One state-table cell or one property per row; each row builds on independent fixture repos (`adopt`, `del`, `none`, `grow`). |
| Necessary | 9/10 | The two retired adopt rows were replaced, not duplicated — net +1 row for +1 verdict arm plus the co-firing guarantee. Every reworked assertion discriminates a real mutant (4/4 killed live). |
| Granular | 9/10 | Marker reason tokens + exact-line greps (`grep -qxF`) + `!grep` negative pins; a failure names the mutant and the row. |
| Fast | 8/10 | Suite is heavy (715 assertions, ~40 git fixtures, subprocess SUT runs) — the declared `*.test.sh` exception applies; runtime is owned by the committed `suite-durations` weights and the a/b/c shard split, not by per-test cost. My `--rows 458-461` run (full chk battery + 4 mutants) completed in ~4 min. |
| First (TDD) | 8/10 | Plan/CTO-ruling-driven; tests reworked in the same commit as the arm (coupling is mandated — the verdict, its rows and its mutants are one invariant). The mutation battery is the red-proof: every new arm lands with a proven killer row. |

**Test Quality Score: 8.6 / 10 (Grade: B — Good, borderline A)**

## Top 3 Recommendations

1. **Understandable** — `ci-pr-affected-replay.test.sh:2970`, `:4889`, `:4895`: finish the adoption-terminology sweep on the chk label and the two mutant names (and consider `replay.py:1869`). Expected +0.5 on Understandable; removes the last stale-state vocabulary a future reader could misread as a still-live arm.
2. **Necessary** — `row_rt_big_baseline` (`:2508-2512`): add a co-firing pin (e.g. `grep -q '^stale-line'` or a `baseline-dup` line grep) or a suppression mutant, so "content checks still run under base-absent" is pinned rather than incidental. Expected +0.3 Necessary; closes the asymmetry the `new-pair` co-firing row already covers.
3. **Granular** — `row_rt_reintroduced` (`:2473`): the two arms are `&&`-chained, so a failure does not name WHICH arm (contentful vs empty) regressed. Splitting the bl-empty arm into its own row (or into `row_rt_reintroduced_empty`) would pinpoint the discriminating fixture for `content-weakened`. Expected +0.2 Granular. Low priority — the mutant name already localizes.

## Patterns Observed

- **Positive:** the `mutate` instrument is self-verifying (pristine-row control, exact-once `old`, parse+import gates, crash≠kill, signature dedup) — a model mutation battery; `!grep` negative assertions used precisely where exit+marker under-discriminate; fixture arms compose (`rt_b_*`/`rt_p_*`) so the state table reads as a table; measured quantities are bounded not pinned.
- **Anti-pattern (mild):** retired-vocabulary residue in labels/names after a semantic rename — the sweep covered comments but not chk-label or mutant-name strings. Grep for the retired token on rename-commit is the cheap guard.
- **Mutation-battery audit note:** the three new mutants all perturb the SAME axis (the reintroduced arm's condition) — correctly, since that is the only new logic; the fourth (`adoption-refused`) perturbs the adjacent grown guard that the new arm now shadows. Per the battery-audit rule, N mutants on one axis count as one axis — here that is honest coverage of a 3-line arm, and the `!grown`/`bl-empty`/`newpair` assertions each have a dedicated killer.

### Pyramid

| File | Layer | Signals | Verdict | Confidence |
|------|-------|---------|---------|------------|
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` (modified) | unit | `*.test.sh` path signal; subprocess/git-fixture fan-out is the declared `*.test.sh` exception; suite not new — registered labels `ci-pr-affected-replay-{a,b,c}` in `scripts/test-all.sh` with committed weights | PASS | high |

No added test files, no layer changes, no e2e signals. The fan-out weight WARN applies to NEW `*.test.sh` only. PR body checked: no `## Test Pyramid` block — none required at this layer.

## Dissent Notes (settled rulings — report contradictions)

| Ruling | Implemented? | Evidence |
|---|---|---|
| token `baseline-reintroduced` | YES | `replay.py:2058-2060`; marker verified live |
| keep present/present machinery | YES | `replay.py:2066-2078` (stale/dup/order/grown intact); `row_rt_stale`/`row_rt_dup`/`row_rt_order`/`row_rt_grow_*` all present and green |
| arm BEFORE new-pair block | YES | `replay.py:2058` precedes `:2061/2064`; `row_rt_reintroduced_newpair` pins the marker order live |
| absent-grown assertion on the contentful reintroduced row | YES | `row_rt_reintroduced:2473` — and it is the proven discriminant for `ratchet-adoption-refused` (killed live) |
| single deletion commit | YES | `ab487915f1` only; exactly the ruled 6-file coupling |
| grown/stale/dup/order rows KEPT | YES | `:2390-2392`, `:2479-2482`, all green |

**Contradictions / residual:** none substantive. The "retired adoption wording" instruction was incompletely executed at `:2970` (chk label), `:4889`/`:4895` (mutant names) — all three are P3 cosmetic; no ruling semantics are violated. The co-firing ruling ("stale-line/dup/order may co-fire on a malformed re-add — correct") is implemented but only `new-pair` co-firing is assertion-pinned (P3 above).

## Summary

PR #12127 retires the ratchet's adoption arm and replaces it with an unconditional `baseline-reintroduced` verdict (`replay.py:2058`), deletes the now-empty committed baseline plus 42 orphaned accept rows in the ruled single commit `ab487915f1`, and reworks the state-table rows, chk labels and Guard-1-M7 mutants to match. The test design is strong: every new/changed assertion has a live kill in the suite's own self-verifying mutation battery (4/4 mutants killed in my `--rows 458-461` run, 715/715 assertions green), the `!grep '^grown'` and bl-empty arms are each the proven discriminant for a named mutant, DECLARED_TOTAL 599 and the `387-599` range are internally consistent and dynamically checked by the shard-totality suite, and all settled rulings landed as decided. The only findings are P3: three stale "adoption" strings the terminology sweep missed (`:2970`, `:4889`, `:4895`), an unpinned stale/dup/order co-firing path under base-absent, and the missing dedicated suppression mutant for `row_rt_reintroduced_newpair`. Score **8.6/10 (B)**, Pyramid **PASS** — approve from the test-design seat.
