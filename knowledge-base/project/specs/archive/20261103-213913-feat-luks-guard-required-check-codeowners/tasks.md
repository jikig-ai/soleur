# Tasks: feat-luks-guard-required-check-codeowners

Plan: knowledge-base/project/plans/2026-11-03-feat-luks-guard-required-check-plan.md. Ref #9927 (never Closes).

## Phase 1 — Registration (pin first)

- [x] 1.1 Write the failing G2f pin (Phase 2) before the registration
- [x] 1.2 Add the `run_suite "apps/web-platform/infra/inngest-luks-sole-copy" bash ...` line in the `want_scripts` region of `scripts/test-all.sh` that holds the census registration
- [x] 1.3 Add the `DOUBLE_COVERED_ACK` entry in `scripts/lint-orphan-test-suites.sh` (reason cites #9927)
- [ ] 1.4 Run `python3 scripts/regenerate-shard-manifest.py --incremental --write`; commit any TSV row
- [x] 1.5 Run `scripts/lint-orphan-test-suites.sh`; add a declared affected-paths edge if it reds UNCLASSIFIED
- [x] 1.6 Update the "five ... SIXTH" comment above `DOUBLE_COVERED_ACK`

## Phase 2 — Deregistration pin (test-bun leg)

- [x] 2.1 Add G2f to `plugins/soleur/test/terraform-target-parity.test.ts`: one label occurrence, exact command after comment strip, inside its own column-0 `want_scripts` region, no enclosing indented `if`, `|| true` suffix RED, target file exists, fail closed on zero matches
- [x] 2.2 Bump `TEST_FLOOR` and its ledger comment
- [x] 2.3 Amend the G2e SUNSET comment (G2e may stay as the independent anchor)
- [x] 2.4 Confirm Guard 1 is in `guard-vacuity-floor.test.sh` PROMOTED_FILES; add if absent (already present: no edit needed)

## Phase 3 — Records

- [x] 3.1 CODEOWNERS rows (5 files) with a "routing text, not enforcement" header comment
- [x] 3.2 ADR-282 addendum: measured before/after, plain residual-risk paragraph (CPO), link #9927 item 1b, "regression-checked" wording, dated Superseded markers on the advisory sentences
- [x] 3.3 Update Guard 1's header ADVISORY sentence
- [x] 3.4 Amend Article 30 register TOM (13) and `compliance-posture.md` (dated Superseded markers, conditional wording, leave #8528 text alone)

## Phase 4 — Verify

- [ ] 4.1 Push; read the `test-scripts` leg from the Actions API: label present, wall time recorded, H1d/H1e rows pass (PyYAML)
- [ ] 4.2 AC1 on a throwaway branch: mutated subject turns `test-scripts` and `test` red
- [ ] 4.3 Run mutations M1-M6 and the harness rows locally; record "6 of 6 red" in the PR body
- [ ] 4.4 `c4-count-parity.test.sh` green; `git diff origin/main -- infra/github` empty

## Phase 5 — Ship housekeeping

- [ ] 5.1 Open code-review overlap query on the final file lists
- [ ] 5.2 PR body: `Ref #9927`; legal amendments listed; G2e sunset and off-project copy not in scope
- [x] 5.3 Record the G2e-sunset follow-up as a checklist comment on #9927 (owner and criterion per the plan; no new issue)
