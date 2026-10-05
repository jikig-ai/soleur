# Tasks — fix preflight Check 10's suite-integrity ANSI summary parser

Branch: `feat-one-shot-7466-check10-ansi-summary-parser`
Plan: `knowledge-base/project/plans/2026-09-08-fix-check10-ansi-summary-parser-plan.md`
Closes: #7466
Lane: `cross-domain` (no spec.md; TR2 fail-closed)

Work target: `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`

> Every mutation in Phase 4 runs against a **copy** in `$TMPDIR`, never the tracked file
> (`hr-never-git-stash-in-worktrees`). Every floor value is read off a green run, never copied
> from the plan.

## Phase 1 — Baseline and preconditions

- [x] 1.1 Record the green terminal line with colour scrubbed:
      `env -u FORCE_COLOR -u CLICOLOR_FORCE bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh`
      (expected today: `=== 13 passed, 0 failed (13 checks) ===`, exit 0).
- [x] 1.2 Record the coloured run: `FORCE_COLOR=1 bash <file>` (expected today:
      `11 passed, 1 failed (12 checks)` + `[FATAL] SUT floor`, exit 1). Keep both outputs for
      the PR body.
- [x] 1.3 Capture bun's real coloured bytes for **both** shapes and paste them verbatim from
      `cat -v` into the fixture comments, with the bun version:
      (a) a non-zero run, (b) an all-`.skip` run. Plan facts F1/F2 depend on these.
- [x] 1.4 Precondition gate: confirm on the pinned bun that `pass` and `fail` print
      unconditionally and that `skip` / `todo` / `expect() calls` are omitted when zero. D-3's
      predicate and D-4's normalisation both rest on that split.
- [x] 1.5 Baseline the corpus guard: `bash scripts/guard-vacuity-floor.test.sh`
      (expected `Total: 23 passed, 0 failed`, exit 0).
- [x] 1.6 Note the two shape constraints before editing: `MIN_CHECKS=` must stay on the line
      immediately above its `if`, and `if [[ $((PASS + FAIL)) -ne "$cases" ]]` must keep its
      byte shape.

## Phase 2 — Scaffold (refactor, no behaviour change)

- [x] 2.1 Add `ESC` and `strip_ansi` as a **pass-through** (`cat`), taking a path.
- [x] 2.2 Add `parse_bun_summary <path>` echoing `"pass fail skip todo expect"` with `-` for
      an unread field, reading its input **exactly once** into a local, with today's
      defective greps (no strip, `n_expect` still unanchored).
- [x] 2.3 Add `summary_measured <pass> <fail>` with today's fail-open semantics (ignores
      `fail`).
- [x] 2.4 Rewire the live consumption block through the new functions. Gate stays green at the
      current `MIN_CHECKS`; confirm with 1.1.

## Phase 3 — RED (failing checks before the fix)

- [x] 3.1 Add the `declare -F strip_ansi parse_bun_summary summary_measured` symbol guard
      above the self-test section, so a missing function cannot read as a wrong answer.
- [x] 3.2 Add `--- 0. Parser self-test ---` with `assert_parse` / `assert_measured` wrappers
      that increment `cases` unconditionally before their pass/fail branch.
- [x] 3.3 Add parser fixtures and checks: S1 (plain, non-green `122 3 1 2 514`),
      S2a (coloured non-zero), S2b (coloured all-skip, `0 0 2 - -`), S3 (colon-SGR + `\0337`
      + `\033(B`), S4 (decoy with a mid-log `999 expect() calls`, expects `- - - - -`).
- [x] 3.4 Add predicate checks V1 (`- -` false), V2 (`122 -` false), V3 (`- 0` false),
      V4 (`122 0` true).
- [x] 3.5 Add N1 (live run: `n_skip`/`n_todo`/`n_expect` are integers at the comparison) and
      N2 (instrument self-test: a deliberately wrong expectation moves `FAIL` by exactly 1).
- [x] 3.6 Run and record the RED/GREEN split. Expected against the scaffold: S2a, S2b, S3, S4,
      V2 and N1 RED; S1, V1, V3, V4 and N2 GREEN. A mixed result is the requirement — publish
      the table in the PR body.

## Phase 4 — GREEN (the fix)

- [x] 4.1 `strip_ansi` becomes real: `LC_ALL=C tr '\r' '\n' < "$1" | LC_ALL=C sed -e
      "s|${ESC}\[[0-?]*[ -/]*[@-~]||g" -e "s|${ESC}[ -/]*[0-~]||g"`. Comment the `|`
      delimiter, the `LC_ALL=C`, and the OSC / stale-text-before-`\e[1G` limits.
- [x] 4.2 Anchor `n_expect`'s first stage at `^[[:space:]]*`; verify every second stage stays
      **unanchored** (an anchored `^[0-9]+` returns empty and reddens a healthy tree).
- [x] 4.3 `summary_measured` requires `pass` and `fail` to match `^[0-9]+$`. `expect` is
      deliberately not an input — bun omits it when zero.
- [x] 4.4 Rewrite the consumption block: one `read -r` binding, verdict bound before anything
      else, `-`→0 normalisation for `skip`/`todo`/`expect` as the first statements of the
      measured branch, all three arms failing closed in the `else`.
- [x] 4.5 Delete all five `: "${n_*:=0}"` defaults.
- [x] 4.6 Give each SUT floor its own `if ! [[ … =~ ^[0-9]+$ ]]` arm ahead of the `-lt`
      comparison, so the predicate travels with the comparison.
- [x] 4.7 Make the "could not parse" row unconditional (add the `else` recording a `pass`),
      and rewrite the now-false comment above it.
- [x] 4.8 Add the ADR-193 Decision #4 note explaining why the new FATAL exits before the
      accounting-conservation check.

## Phase 5 — Ratchet and mutation proof

- [x] 5.1 Re-run green; read `MIN_CHECKS` **off the run** and ratchet with no slack. Keep the
      assignment adjacent to its `if`.
- [x] 5.2 Run M1–M14 and H1–H5 against copies in `$TMPDIR`; record every observed verdict.
      M1 must leave S1 and S4 GREEN — that half is the differential proof.
- [x] 5.3 Verify AC13–AC17 (producer greps, defaults removed, GNU escape unused, empty stderr,
      the M1 end-to-end unmeasured output).
- [x] 5.4 `bash scripts/guard-vacuity-floor.test.sh` green, plus the M13 adjacency mutation.
- [x] 5.5 `python3 scripts/lint-trap-tempfile-ownership.py <file>` clean.

## Phase 6 — Follow-through and ship

- [x] 6.1 Filed as #7942 — RESCOPED after the CONCUR gate. The parse at
      `git-fixture-env.mutation.sh:193` is not the defect: its stage one is unanchored, so
      colour does not break it, and the file is executed by nothing (`test-all.sh` globs
      `*.test.sh`, which the `.mutation.sh` spelling excludes). Fixing the grep alone would
      arm #7466's exact defect there and launder a dead harness as maintained. The issue
      covers BOTH unregistered batteries (`hook-git-env-coverage.mutation.sh` too), cites
      this repo's own ruling at `.github/workflows/infra-validation.yml:699-701`, and carries
      the `strip_ansi`-into-`test-helpers.sh` extraction as step 3 rather than step 1.
- [ ] 6.2 Compound: amend the three existing learnings that prescribe the GNU-only, SGR-only
      strip with the two facts measured here (`\x1b` is a GNU sed extension; an SGR-only strip
      is defeated by a non-SGR CSI).
- [ ] 6.3 PR body carries `Closes #7466`, the Phase 3 RED/GREEN table, and every mutation
      verdict.

## Phase 7 — Review round (2026-09-08, nine agents)

- [x] 7.1 P1 (security): the parse trusted every byte of `$LOG`. Two measured forgeries —
      a pre-block `console.log(" 999999 expect() calls")` clearing MIN_ASSERTIONS on 132
      assertion-free tests, and a post-terminator append via the fd 1 every spawned child
      inherits. Bounded the parse to bun's own summary block.
- [x] 7.2 P1 (security): `^[0-9]+$` admits `08`, which bash reads as octal and which then
      made every comparison return false — all three floors bypassed. `10#` at the producer
      plus a length cap (2^63 wrapped negative through the same regex).
- [x] 7.3 P1 (observability): skip/todo/expect absence was an INFERENCE. Added the
      `pass+fail+skip+todo == ran` reconciliation off bun's unconditional `Ran N` line.
- [x] 7.4 P1 (test-design): a MISROUTED `fail()` conserved the sum and shipped exit 0.
      Added the append-only `VERDICTS` transcript and a routing check that reads it.
- [x] 7.5 P1 (test-design): `assert_measured` had no instrument probe; stubbing it plus
      restoring the predicate fail-open shipped #7466 itself at 25/25. Added N3.
- [x] 7.6 P1 (architecture): the counter set was restated at five hand-maintained sites.
      Derived from one `COUNTERS` list.
- [x] 7.7 P2: check dispatch made path-invariant (29 both branches), so an unparsed summary
      no longer trips the anti-vacuity floor and blames the harness.
- [x] 7.8 P2: `$LOG` retained on the skip/todo arm and both floors; T1 asserts the strip at
      text level; `FORCE_COLOR=1` on the live run so CI exercises the strip.
- [x] 7.9 P2: MIN_TESTS/MIN_ASSERTIONS ratcheted 131->132 / 537->539 per this file's own rule.
- [x] 7.10 P2: falsified prose corrected — the sentinel's `read`-collapse justification, the
      plan's out-of-branch structural claim, "13 of the 25" (measured: 13 of 29), the
      `discoverability_test` anchor, and mutation-verdicts' claim that
      `guard-vacuity-floor.test.sh` covers the verdict helpers (it does not).
- [x] 7.11 P2: #7942 amended — third consumer, the ADR-193 incompatibility of
      `test-helpers.sh`, an over-reached universal, and the divergent `strip_ansi`.
- [ ] 7.12 DEFERRED: a fixture-identity manifest (row name + fixture digest), so a fixture
      cannot be swapped with its name and slot intact. T1 closes the escape-bearing case;
      the general mechanism is larger than this PR.
