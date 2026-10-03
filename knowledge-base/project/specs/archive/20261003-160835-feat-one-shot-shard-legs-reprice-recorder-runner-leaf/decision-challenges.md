# Decision challenges — feat-one-shot-shard-legs-reprice-recorder-runner-leaf

Persisted by the headless planning run for `ship` to render into the PR body. The operator's stated direction is the default; each entry below is a place where the plan departs from, or interprets, that direction.

## 2026-10-02 — Single PR despite a split recommendation (User-Challenge)

- **Operator direction:** implement PR-B, PR-C and the shard-leg regeneration (D5) in this one-shot.
- **Plan's Split Assessment:** over the thresholds (about 1,600 changed lines; the PR-A review split on the same seam because selection-changing work in a diff that touches `scripts/test-all.sh` degrades the local gate to the full run).
- **Plan's choice:** proceed as one PR with three commit-isolated, revertable phases (recorder and PR-B; PR-C; D5 last). Cut order if scope pressure appears: D4, then Phase C narrowing, then A5.
- **To reverse:** stop after Phase 1 (PR-B) and open PR-C from a branch cut off main after PR-B merges; D5 then runs as the last step of PR-C or on its own.

## 2026-10-02 — Interpretation of PR-B and PR-C (Taste)

The four plans named in the brief do not define PR-B or PR-C. The plan uses the definitions in the last two comments of issue 9307 and the archived PR-A plan (B1 recorder, B2 `scripts/domain-model-drift`, B3 audit round 2, D2 ratchet breadth, D3 subcommand forms, D4 deleted declared subject; A5 runner leaf, D1 `REPO_ROOT` idiom, Phase C heavy batteries; D5 shard regeneration). D2-D4 are included because the issue defines PR-B that way, although the brief's headline names only the recorder and the demotions.

## 2026-10-02 — D4 is kept but marked cut-first (Taste)

D4's property (a deleted declared subject still selects its suite) is partly covered today because the census linter reports the dangling declaration in the same run. It is kept because the issue lists it under PR-B, and ordered last so it can be dropped without touching the rest.

## 2026-10-02 — Phase C scope shrank (Taste)

ADR-262 already withdrew `scripts/test-all-affected` and both `lint-orphan-test-suites-mutations` halves from the always-on set, so the issue's four Phase C candidates are down to one plausible narrowing (`scripts/test-all-infra-coverage-notice`) among six remaining heavy batteries (561 s of 1,147 s always-on suite time). The plan audits all six, defaults every one to keep, and does not build perturbation or corpus-check tooling.

## 2026-10-02 — Plan-review panel recommendations the plan did not adopt (User-Challenge / Taste)

- **Split into separate PRs (DHH, CTO; simplicity implicit):** PR-B, PR-C and D5 as three PRs. Not adopted: the brief asks for all three in one run. Mitigation adopted instead: Phase 2 is gated on Phase 1 being green on CI with its fingerprint recorded, and Phase 3 is the first piece to peel into its own data-refresh PR.
- **Cut D4 entirely (DHH, simplicity; CTO says cut first):** not adopted unconditionally because the issue defines D4 as part of PR-B; it is conditional, last in Phase 1, and dropping it requires one deferral issue.
- **Cut D1 (simplicity):** adopted in a conditional form — D1 is implemented only if a Phase 0.4 census (independent of the runner) finds a suite that misses a named edge, because the issue's "23 README edges" premise did not reproduce.
- **Shrink the recorder (DHH, simplicity, CTO):** adopted (mechanical): no `--propose-cover`, no `--markdown`, no newline or symlink checks, no static scan over observed scripts; verdict core retained.
- **Move D5 to its own PR (DHH, CTO):** not adopted by default (the brief asks for it); see the first bullet.

## 2026-10-02 — Deepen-pass: D5 placement (Taste)

The architecture review recommends making D5 a post-merge data PR from runs that contain the merge commit, because the ratchet (the suite D5 exists to re-weight) is measured here at its post-PR-A walk cost and A5 then lowers it, and because this PR shares generated files with PR 9409. The plan keeps D5 as the last commit (the brief asks for it) with the lag stated and the procedure replayable, so peeling it into its own PR is a cut-and-paste.

## 2026-10-03 — D4 dropped, with one deferral issue (Taste)

D4 (a declared edge to a deleted subject still selects its suite) was cut as the plan's own cut order allows: it was the one selection-widening change in a PR whose acceptance rests on certifying a narrowing, it needs a five-part set across the runner, the declarations lib, the census linter, two suites and a mutation, and no declared subject is missing today. It is tracked in #9441 with re-evaluation criteria; ADR-242 decision 17 says so. To reverse: land the five-part set from #9441.

## 2026-10-03 — The leaf oracle is bounded, not exact (Taste)

**Superseded in review (2026-10-03):** the walker was rebuilt as a second implementation of the derive's text rules and now reproduces every edge-classified row (408/408); both ceilings default to 0. The reasoning below is the first write-up and is kept as history.

The plan specified that the bench's independent walker computes the expected head set and that head equals base minus that set. Measured on the real streams, an independent text walker over-approximates the derive: 2,161 removals over 24 rows are not explained by it (up to 189 per row) and the head kept 24 edges it expected removed. Equality would force the walker to become the derive, which is no longer independent. The oracle therefore keeps the exact checks (no added edge, no class change, no unexplained selected-bit change, every real source edge of a leaf kept with a population floor that FAILS when the walker resolves none) and applies an explicit `--max-unexplained` ceiling (default 0, run at 200, always printed) to the rest, with the recorder's check mode as the behavioural cover. The first version of the floor was vacuous on an empty list and hid the loss of the runner's variable-sourced libs until it was made to fail. To reverse: tighten `--max-unexplained` as the walker is improved.

## 2026-10-03 — Sandbox rows for the two diff scopes were not added (Taste)

The plan asked for a branch-scope row (a diff containing a leaf still reports `runner-changed`) and a staged-scope row (a diff containing only a leaf selects every label that carried `^scripts/test-all.sh`) in `scripts/test-all-affected.test.sh`. Branch scope is already pinned by that suite's row k and the fallback literals are pinned equal to `CLOSURE_LEAF_FILES` by a derive row; the staged-scope property is that the leaf FILE stays an edge of every closure reaching it, which a derive row asserts directly. A sandbox row would need a label that reaches the runner, and the parity rule forbids adding a label to the sandbox keep-list. To reverse: add the label with a recomputed parity fingerprint.

## 2026-10-03 — Suites with no recorder evidence: hedged to always-on, not guessed (Taste)

`scripts/orphan-process-reaper` lost 715 of 725 derived edges to the leaf rule and the recorder could not produce a recording for it under `env -i` without network (57 of 145 assertions fail). It moves to `ALWAYS_ON_SUITES` (8.7 s) instead of relying on the oracle's unexplained-removal allowance. `scripts/lint-rule-ids-live` and `scripts/check-tom4-rls-posture` (Round 2) stay demoted on Round 1 evidence with no Round 2 evidence either way, and the audit says so. To reverse: give the recorder the environment those suites need and re-audit.

## Review amendments (11-seat panel, 2026-10-03)

- **`_MIN_ALWAYS_ON_DECLARED` raised 116 -> 140 (the plan said "never raised").** The plan's rule meant the floor stayed 23 below the count after this PR re-promoted
  suites, so 23 entries could be deleted from `ALWAYS_ON_SUITES` with no `below-floor` refusal. The floor is now count minus 5 and row `f1` pins the literal AND
  `count - floor <= 5`, so the next re-promotion has to move both. The plan's reason for never raising it (a rebase that drops the count below the floor refuses
  every local run) is the cost accepted.
- **An `unreliable` suite that is already demoted goes BACK to always-on (the plan said "leave as is").** The plan's rule left the unsafe direction in place; and the
  two Round 2 `unreliable` rows turned out to be an artifact of the recorder's contamination probe (fixed), so re-recording decided them: both `uncovered`, both re-promoted.
- **Hedge by cost.** Re-checked rows with no usable evidence are hedged to always-on only when that costs under about 7 s (six suites); `test-affected-kb-consumers` (77 s),
  `orphan-process-reaper-mutations` (134 s) and `audit-suite-reads` (95 s) stay on their edges with the gap stated, because hedging them adds 306 s (+24%) to always-on time.
- **The `$(dirname ...)/` line-level resolve covers non-leaf files too, in the slash form only.** The first review fix applied it to every file and measured 241 rows
  gaining 326 edges (29 to 39 selected-bit flips); the slash form measured 58 rows, 86 edges and 0 to 11 flips with the same real source gains.
- **Recorder flags removed:** `--reps` (fixed at 2) and `--allow-unresolved-probes` (the rule is unconditional); no test or recorded run used either.
- **Declared wontfix (polish):** extracting `cmd_record`/`_v_group` into smaller functions, and moving the bench walker out of its heredoc into a module. Both are refactors with no
  failing scenario; the suites around them are mutation-proven as they stand.
