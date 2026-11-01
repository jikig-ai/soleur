# Tasks — chore: demote 8 always-on fast-tier labels to edge-selection (#11648)

Derived from `knowledge-base/project/plans/2026-11-01-chore-fast-tier-always-on-demotion-plan.md` (post-review). Demotion set (issue #11648): `scripts/test-all-group-affected`, `tests/scripts/lint-ratchet`, `plugins/soleur/test/check-deps-adapter-drift.test.sh`, `plugins/soleur/test/token-drift-workflow-causes.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/lint-encryption-posture`, `plugins/soleur/test/gitleaks-merge-commit.test.sh`, `scripts/lint-gh-argv-arg-live`.

## Phase 0: Evidence capture and pin arithmetic

- [ ] 0.1 Download the newest green `merge_group` `suite-timings-scripts-*` artifacts (`gh run download <id> -p 'suite-timings-scripts-*' -D <dir>`) and run `python3 scripts/regenerate-shard-manifest.py --drift-report --timings-dir <dirs…>`; fall back to the runbook's recorded 2026-10-31 medians if artifacts are stale.
- [ ] 0.2 Write `knowledge-base/project/specs/feat-one-shot-11648-fast-tier-demotion/receipts/medians-11648.txt` — per-label median, committed weight, verdict (demote / measurement-artifact).
- [ ] 0.3 Lock the demotion set; compute resulting always-on count (122 − N) and floor (count − 5).

## Phase 1: Index demotion

- [ ] 1.1 `scripts/lib/test-affected-paths.sh` — remove the 8 labels from `ALWAYS_ON_SUITES`.
- [ ] 1.2 Extend `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` with root-anchored `glob:*.<ext>` edges for each PJ_EXTS extension (sh bash yml yaml tf tftpl template service tmpl).
- [ ] 1.3 Add `AFFECTED_SCRIPTS_TEST_ALL_GROUP_AFFECTED_PATHS` — `scripts/test-all.sh`, `scripts/lib/{test-affected-paths,test-relevance-paths,affected-glob,test-affected-derive-cache,repo-write-boundary}.sh`, self, index.
- [ ] 1.4 Add `AFFECTED_TESTS_SCRIPTS_LINT_RATCHET_PATHS` — `plugins/soleur/scripts/lint-ratchet.py`, `plugins/soleur/scripts/ruff-requirements.txt`, `tests/scripts/fixtures/lint-ratchet/`, `tests/scripts/_git_fixture_env.py`, `ruff.toml`, `apps/web-platform/eslint.test-dirs.config.mjs`, self, index.
- [ ] 1.5 Add `AFFECTED_PLUGINS_SOLEUR_TEST_CHECK_DEPS_ADAPTER_DRIFT_TEST_SH_PATHS` — `plugins/soleur/skills/pencil-setup/scripts/`, `plugins/soleur/test/test-helpers.sh`, self, index.
- [ ] 1.6 Add `AFFECTED_PLUGINS_SOLEUR_TEST_TOKEN_DRIFT_WORKFLOW_CAUSES_TEST_SH_PATHS` — `.github/workflows/scheduled-terraform-drift.yml`, `scripts/check-cloudflare-token-drift.sh`, `apps/web-platform/infra/doppler-config-inventory.txt`, `apps/web-platform/infra/token-drift-read-tokens.tf`, `knowledge-base/engineering/operations/runbooks/`, `plugins/soleur/test/test-helpers.sh`, self, index.
- [ ] 1.7 Add `AFFECTED_SCRIPTS_LINT_ENCRYPTION_POSTURE_PATHS` — `scripts/lint-encryption-posture.py`, `scripts/encryption-posture-ledger.json`, `scripts/encryption-posture-ledger.schema.json`, `apps/web-platform/infra/`, `apps/cla-evidence/infra/`, `infra/`, `plugins/soleur/skills/plan/references/plan-issue-templates.md`, self, index.
- [ ] 1.8 Add `AFFECTED_PLUGINS_SOLEUR_TEST_GITLEAKS_MERGE_COMMIT_TEST_SH_PATHS` — `.github/workflows/secret-scan.yml`, `.gitleaks.toml`, `plugins/soleur/test/lib/gitleaks-probe.sh`, `plugins/soleur/test/test-helpers.sh`, self, index.
- [ ] 1.9 Add `AFFECTED_SCRIPTS_LINT_GH_ARGV_ARG_LIVE_PATHS` — `glob:*.sh`, `.github/workflows/`, `scripts/lint-gh-argv-arg.py`, index.
- [ ] 1.10 Rewrite the `#9763 withdrawn-to-edge-selection` comment to name the resulting demoted set (AC3); move `grep-q-pipe-guard`'s re-promotion note out of the member list.
- [ ] 1.11 Delete the 8 rows in `scripts/always-on-justifications.tsv`; verify `bash scripts/always-on-ledger.test.sh` green.

## Phase 2: Pin re-ratchet

- [ ] 2.1 `scripts/test-all.sh:4164` — `_MIN_ALWAYS_ON_DECLARED` 117 → resulting-count−5; append re-pin ledger comment (`#11648: -8 always-on — re-pinned at N-5`).
- [ ] 2.2 `scripts/test-all-affected.test.sh:2941-2947` — f1 literal pin 117 → same value; update the `122-count` narrative strings.
- [ ] 2.3 Verify `bash scripts/test-all-fast-tier-budget.test.sh` and `bash scripts/test-all-affected.test.sh` green.

## Phase 3: Ratchet reconciliation loop

- [ ] 3.1 `python3 -I scripts/ci-pr-affected-replay.py ratchet` — resolve every `new-pair` on the demoted suites via edge widening or anchor-keyed accept rows in `scripts/ci-pr-affected-audit.accept.tsv`; never grow `scripts/ci-pr-affected-audit.baseline.tsv`.
- [ ] 3.2 `bash scripts/test-affected-kb-consumers.test.sh` — real kb reads get covering edges; citation-only refs recorded via `--write-baseline` with `false-positive:` classifications.
- [ ] 3.3 `bash scripts/lint-orphan-test-suites.sh` green; `--print-selection` spot-check each label resolves `edge:declared`/`edge:consumed` (never `unclassified`).

## Phase 4: Verification battery + docs

- [ ] 4.1 Run the guard battery: fast-tier-budget, always-on-ledger, lint-orphan, kb-consumers, test-all-affected, test-all-group-affected, test-all-weight-drift, corpus-weight-budget, ci-pr-affected ratchet.
- [ ] 4.2 AC1 re-priced-fixture check: drive `check_tier` against a durations copy with the 8 rows at real medians — must stay green.
- [ ] 4.3 AC6 spot checks: `--print-selection --paths=<subject>` selects each demoted suite; `--paths=<unrelated>` declines where honest edges permit.
- [ ] 4.4 Confirm the 8 labels still registered (shard manifest + durations rows untouched, no hand-edits).
- [ ] 4.5 Record AC evidence under `receipts/`; verify all 8 ACs.
