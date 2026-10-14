# Tasks — feat-one-shot-10099-heredoc-here-string-false-positive

Plan: `knowledge-base/project/plans/2026-10-13-fix-10099-heredoc-here-string-plan.md`
Issue: #10099 (closes) · umbrella: #8689 (stays open) · follow-up: filed in §4

Measured plan-time baseline (this branch, full suite run 2026-10-13):
`repo-wide floor-bearing 360`, covered 313, deferred 47, unclassified 0,
fires 298, nofire 0, construct 15; deferred 31/0/16; `23 passed, 0 failed`.

## 0. RED first (`cq-write-failing-tests-before`)

- [ ] 0.1 Add the ARM 8c block to `scripts/guard-vacuity-floor.test.sh` between
  ARM 8b (~line 1433) and ARM 9 (~line 1435): synthesize a `$SUITE_TMP` fixture
  (`printf '%s\n'` rows, ARM 7/8/8b style) containing — counter increments
  (`cases=$((cases + 1))` ×2), a `<<< 'literal'` here-string (and a `<<<lit`
  variant line), a real `cat <<'HD'` heredoc whose body holds a floor-shaped
  decoy `if [[ "$cases" -lt 99 ]]`, and the real floor `if [[ "$cases" -lt 2 ]]`.
- [ ] 0.2 Assertion (a): `floor_lines_of` on the fixture returns exactly one
  candidate and it is the real floor line — pass()/fail() row.
- [ ] 0.3 Assertion (b): the decoy `if [[ "$cases" -lt 99 ]]` line number is
  absent from `floor_lines_of` output — pass()/fail() row.
- [ ] 0.4 Run `bash scripts/guard-vacuity-floor.test.sh`; capture the FAIL on
  the new row (expected: `floor_lines_of` returns 0 candidates — the phantom
  span swallows the floor) while the existing 23 stay green. Attach the
  capture to the PR (AC4).

## 1. Detector fix (`scripts/guard-vacuity-floor.test.sh`)

- [ ] 1.1 Inside `heredoc_lines_of`'s `match()` block (~line 130), before the
  `tag` extraction, add the preceding-`<` rejection (ruling D1/D2 — amend to
  the `(^|[^<])` regex form or the rescan loop ONLY if the CTO ruling says so):
  `if (RSTART > 1 && substr($0, RSTART-1, 1) == "<") next`
- [ ] 1.2 Extend the function's comment block (~lines 123-126) with the
  measured history: the `<<<` second-`<` class + the #10051 measurement, the
  `<<<<<<<`-marker instance (`resolve-regenerable-conflicts.test.sh:123`), and
  the residual classes deferred under #8689 (quoted-needle `<<`, comment-line
  openers, `a<<b` arithmetic, `<<<`+real-opener same-line).
- [ ] 1.3 Re-run the suite — ARM 8c must go GREEN and the ledger must print
  `floor-bearing 362`, `covered 315`, `fires 300`, `construct 15`,
  `deferred 47`, `unclassified 0` **only after §2 lands** (before §2,
  `construct` reads 16 and ARM 2 reds — expected intermediate state, not a
  surprise).

## 2. Companion edit (`plugins/soleur/test/deploy-arm.test.sh`) — REQUIRED

- [ ] 2.1 Move `MIN_CASES=79` (line ~697) to the line directly above
  `if [[ "$cases" -lt "$MIN_CASES" ]]` (line ~703) — adjacent-literal binding
  so `build_mutant`'s backward slice carries it. No other reference to
  `MIN_CASES` exists between :697 and :704 (grep-verified); the move is
  semantics-free.
- [ ] 2.2 `bash plugins/soleur/test/deploy-arm.test.sh` exits 0 unchanged
  (its floor reads the same value; only the binding position moved). (AC3)

## 3. Optional ratchet capture (D5 — only if ruled)

- [ ] 3.1 If the CTO ruling keeps it: `MIN_FIRING_SUITES` 52 → 54 with the
  comment changelog annotation `+2 (#10099): resolve-regenerable-conflicts,
  deploy-arm (derivation widening — here-string openers no longer phantom)`.

## 4. Follow-up + closeout

- [ ] 4.1 File ONE follow-up issue under #8689, labels `domain/engineering`,
  `type/bug`, `meta/machinery`, carrying the measured residuals verbatim:
  (a) comment-line `<<TAG` openers + the `doppler-injection-bound.test.sh`
  deferred-ledger interaction (48>47 ⇒ promote-or-harden decision, measured
  FIRES but helper-internal counters — the promotion-bar question);
  (b) the quoted-needle `<<` class with `lint-shell-capture-exit.test.sh:832`'s
  live derivation miss named (subject de-tokenization `<[<]` idiom + its
  `${CAPTURE_LINT_MIN_ASSERTIONS:-133}` non-adjacent bound needs repair too);
  (c) `a<<b` arithmetic-adjacency. (AC6)
- [ ] 4.2 Comment on #8689: the `<<<` leg is closed by this PR; residual
  classes are carried in the new issue.
- [ ] 4.3 Optional touch-up only: note the detector fix in
  `lint-shell-trace-credential-refusal.test.sh`'s :2986-2989 workaround comment
  (do NOT revert the variable-bound probes — D8).
- [ ] 4.4 PR body: first line answers "does merging this mutate production?"
  (`no — test machinery only`); `Closes #10099`; `## Changelog` section
  (semver:patch — bug fix in test machinery).

## 5. Verification gates

- [ ] 5.1 `bash scripts/guard-vacuity-floor.test.sh` → exit 0,
  `Total: 25 passed, 0 failed`, ledger 362/315/47/0/300/0/15, deferred
  31/0/16. (AC2)
- [ ] 5.2 `git diff --name-only origin/main...HEAD` shows only
  `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/
  deploy-arm.test.sh`, `knowledge-base/project/**`. (AC5)
- [ ] 5.3 `python3 scripts/lint-guard-contract.py` exits 0.
- [ ] 5.4 Probe sanity: `git grep -l 'RSTART-1' -- scripts/` prints
  `scripts/guard-vacuity-floor.test.sh`.
