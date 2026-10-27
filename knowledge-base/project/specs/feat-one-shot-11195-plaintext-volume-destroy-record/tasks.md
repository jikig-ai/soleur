# Tasks: record PR after the plaintext git-data volume destroy (#11195)

Plan: knowledge-base/project/plans/2026-10-27-chore-git-data-plaintext-volume-destroy-record-plan.md

## Phase 0: Preconditions and read-only evidence

- [ ] 0.1 `git fetch origin main`; re-check `git log edade6cb3e..origin/main -- <file>` is empty for the six restore-by-checkout files (census test, parity test, grep-q-pipe-guard test, accept.tsv, suite-durations.tsv, suite-shard-legs.tsv); re-read `gh run view 40478209838 --json conclusion`, #11195, PR #11284
- [ ] 0.2 Run the guards to be touched on the unmodified tree and record baselines (census suite, parity test, `grep-q-pipe-guard.test.sh`, `lint-encryption-posture.py`, preflight G1)
- [ ] 0.3 Fresh read-only state read BEFORE the probe is deleted: `bash apps/web-platform/infra/git-data-plaintext-volume-state.sh` (read-only token); record UTC time and identifier-only output (skip with a note if no read credential)
- [ ] 0.4 Spawn `soleur:legal:clo` once (report-only, "do NOT use AskUserQuestion"): attest the equivalence, may the ledger row be retired, Art. 30 PA-36(f) marker wording, DPD 10.3(b) stays a CLO item; append the `Ruled by CLO agent` rows to `decision-challenges.md`; choose Branch A (attested) or B (not)

## Phase 1: Delete and reverse the counters (one commit)

- [ ] 1.1 Delete the workflow, the gate library, the gate suite and the probe
- [ ] 1.2 `git checkout edade6cb3e^ --` the census test (FLOOR 402 / MUTANT_FLOOR 154), parity test (TEST_FLOOR 297), grep-q-pipe-guard test (PJ_TRIPLES 291 + drains row), accept.tsv (3 rows), suite-durations.tsv, suite-shard-legs.tsv
- [ ] 1.3 Hand-revert `scripts/test-all.sh` (run_suite line + comment) and `scripts/lib/test-affected-paths.sh` (3 `AFFECTED_PLUGINS_SOLEUR_PATHS` entries + the `..._GIT_DATA_PLAINTEXT_DESTROY_GATE_PATHS` array and comment)
- [ ] 1.4 `preflight-discoverability-test.test.ts`: keep `BASELINE_DECLARED_PROBES = 85`, add one dated comment line (probe retired 2026-10-27, declaration is history)
- [ ] 1.5 Confirm each floor/triple count from a green run; grep for zero residual hits outside the allowed files

## Phase 2: Ledger

- [ ] 2.1 Branch A: remove the `hcloud_volume.git_data` store object; Branch B: keep it, rewrite evidence/live_verification to the read-back, `expires_on` unmoved
- [ ] 2.2 Rehearsal row: ruled `reevaluate_when` and dated justification parenthetical; `expires_on` 2026-12-31 unmoved
- [ ] 2.3 `python3 scripts/lint-encryption-posture.py` and `bash scripts/lint-encryption-posture.test.sh` green

## Phase 3: Records (Edit tool, unique anchors, compare `^## ` headings before/after)

- [ ] 3.1 ADR-239: append `## Amendment 2026-10-27 - read-back of the plaintext-volume destroy` (run URL, measured table, claim limit, status per CLO outcome, DPD dated item); earlier text byte-identical
- [ ] 3.2 Runbook `git-data-luks-cutover-5274.md`: keep heading, replace procedure subsections with a past-tense "As run" record, keep host-lost and retention paragraphs
- [ ] 3.3 `git-data.tf` (SOLEUR-DEBT marker past tense, comment block at the retired-volume stub), `git-data-luks.tf` comment, `test-git-data-wipe-wedge.sh` header line; banners and ADR-119 addendum untouched
- [ ] 3.4 `model.c4` gitDataStore description; hook regenerates `model.likec4.json`
- [ ] 3.5 `expenses.md` row: retired, marker dropped, RETIRED lead-in, PHANTOM sentence struck; run `expenses-verify-by-check.sh`
- [ ] 3.6 Art. 30 PA-36(f) marker only from CLO-returned wording; otherwise leave open

## Phase 4: Verification

- [ ] 4.1 Parity, preflight G1, census, grep-q-pipe-guard, wipe-wedge, replace/birth gates, root-key-arm, ledger lint, orphan-suite lint, guard-vacuity-floor, C4 tests + count parity, workflow lint, ci.yml ratchet step, kb-consumers test, affected-tests selection (heavy suites to CI, read back); plus the suites that read the rewritten runbook (`git-data-wipe-access`, `git-data-cutover-access`, `git-data-wipe-assert`, `lint-infra-no-human-steps` tests) and the shard-registry suites (`scripts-shard-totality`, `scripts-shard-manifest`, `regenerate-shard-manifest`, `test-infra-suite-registration*`); expenses check expects `expired=29 anomalies=0`

## Phase 5: PR and dated items

- [ ] 5.1 PR body with `Ref #11195 / #8211 / #6897 / #11194` (never Closes), rendered decision table, open items (DPD 2026-11-03 bound / 2026-11-11 outer limit; Art. 30 if no wording)
- [ ] 5.2 Post-merge watch: per-merge infra apply (empty plan), next drift run clean; PR link comment on #11195 and #6897
