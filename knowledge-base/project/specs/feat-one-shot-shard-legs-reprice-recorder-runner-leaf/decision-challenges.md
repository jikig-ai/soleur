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
