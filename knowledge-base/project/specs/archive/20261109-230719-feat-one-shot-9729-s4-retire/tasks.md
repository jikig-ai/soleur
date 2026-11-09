# Tasks — feat-one-shot-9729-s4-retire

Derived from `knowledge-base/project/plans/2026-11-09-ci-s4-stage-retirement-plan.md` (post-authoring draft; regenerate if the plan changes at review/deepen).

## 1. Setup

- [x] 1.1 Re-read the plan's §Research Insights census; re-run the three `git grep` censuses on the fresh tree before editing (drift check).
- [x] 1.2 Confirm `git branch --show-current` == `feat-one-shot-9729-s4-retire` and the worktree is clean.

## 2. Phase 1 — Oracle sentinel re-scope (author + verify FIRST)

- [x] 2.1 Create `scripts/ci-oracle-surface.txt` with the 11-member list from plan Phase 1.1.
- [x] 2.2 Edit `scripts/ci-oracle-review.sh`: replace `ORACLE_REPLAY`/importlib extraction (`:59`, `:158-178`) with the base-txt → base-replay.py → HEAD-txt chain; update header contract (`:4-13`).
- [x] 2.3 Edit `scripts/ci-oracle-review.test.sh`: stub surface at `:98-105`, stub `git show` dispatch `:187`, add legacy-fallback arm.
- [x] 2.4 Edit `plugins/soleur/test/bot-synthetic-unreachability.test.sh`: re-source oracle list (`:33`), update required-set assertions (`:81-82`).
- [x] 2.5 Run `bash scripts/ci-oracle-review.test.sh` + `bash plugins/soleur/test/bot-synthetic-unreachability.test.sh` — green before any deletion.

## 3. Phase 2 — Remove `affected-index-ratchet` required context

- [x] 3.1 Delete the `affected-index-ratchet` job + comments in `.github/workflows/ci.yml` (`:22,:518-575`).
- [x] 3.2 Remove row + comment in `scripts/required-checks.txt` (`:240,:251`).
- [x] 3.3 Remove the context row in `scripts/ci-required-ruleset-canonical-required-status-checks.json` (`:43`).
- [x] 3.4 Remove the `required_check` block in `infra/github/ruleset-ci-required.tf` (`:200-206`).
- [x] 3.5 `tests/scripts/test-audit-ruleset-bypass.sh`: T-rsc-7 literal 12→11 + history line (`:701,:718-724`).
- [x] 3.6 `scripts/probe-merge-group-coverage.sh`: `MIN_CONTEXTS_DEFAULT` 14→13 + comment (`:69`).
- [x] 3.7 `plugins/soleur/test/required-checks-canonical-parity.test.sh:180`: `-ge 12`→`-ge 11`.
- [x] 3.8 admin-merge-ready fixtures: `rules-branches-main.json:53`, `check-runs.json:931-944`, `README.md:13`; `admin-merge-ready.test.sh` `:72,:337`.
- [x] 3.9 `scripts/pr-fanout-ledger.txt:57`: append the `-2` entry (count 22→20; verify with yaml.safe_load AFTER Phase 3 too).
- [x] 3.10 Verify `.github/actions/bot-pr-with-synthetic-checks/action.yml` derives its synthetic set from `required-checks.txt` (edit only if hardcoded).

## 4. Phase 3 — Remove the `pr-selection` lever

- [x] 4.1 `.github/workflows/ci.yml`: delete the `pr-selection` job (`:398-437`), prune `needs:` at `:1651,:1757,:2034,:2396`, remove the three PR-skip `if:` clauses (`:1652,:1758,:2035`), remove aggregator env `SKIP_LEGS/ACTIVE/HEAD_SHA_OK` (`:2433-2438`) and PR-AFFECTED-SKIP tolerance arms (`:2525,:2564-2568`), sweep comments.
- [x] 4.2 Delete `scripts/ci-pr-selection.sh` + `scripts/ci-pr-selection.test.sh`.
- [x] 4.3 Update pinned sets in `scripts/ci-push-dedupe.test.sh` (`:90-144,:225-230,:315-322`) and `scripts/ci-draft-light.test.sh` (`:85-110,:159-192,:353,:978-1102`).
- [x] 4.4 Update `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` pr-selection arms (`:585-637,:727,:852,:1045-1100`).
- [x] 4.5 Update `apps/web-platform/test/c4-likec4-version-pin.test.ts:259` `PR_AFFECTED_WEBPLAT_IF`.
- [x] 4.6 Re-anchor allowlist comments in `scripts/ci-e2e-classify.sh:23` + `scripts/ci-shard-totality-classify.sh:27`.

## 5. Phase 4 — Retire the evidence layer

- [x] 5.1 Delete `scripts/ci-pr-affected-replay.py`, `scripts/ci-pr-affected-preactivation.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`, `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`.
- [x] 5.2 `scripts/test-all.sh`: remove replay-arm + ci-pr-selection registrations (`:5651-5653,:7152`), start-first special-case (`:7554-7558`), mirror comments (`:2840,:3576`).
- [x] 5.3 `scripts/ci-oracle-lane.sh`: exclusion list (`:181`), memberless `is_oracle_data_path` (`:167-173`), comments (`:60-75`).
- [x] 5.4 `scripts/ci-oracle-lane-suites.txt` (`:31-34,:50-54`) + `scripts/ci-oracle-lane-legs.tsv` (`:13,:20,:26-27,:31`) — remove members, REBALANCE legs.
- [x] 5.5 `scripts/ci-oracle-lane.test.sh` — all pins listed in plan Phase 4.5, incl. O-DOCPARITY (`:1181-1185`): convert to a literal byte-pin of the `is_doc_path` body in `ci-oracle-lane.sh` (no surviving second copy — verified at deepen time).
- [x] 5.6 `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/test-affected-kb-consumers.baseline.txt` — remove retired rows.
- [x] 5.7 `scripts/lib/test-affected-paths.sh` — remove dead-suite edge arrays + dead-file edges + stale comments (minimal oracle-surface diff).
- [x] 5.8 `scripts/lib/test-suite-lanes.sh:135`, `scripts/lib/affected-glob.sh:31` — comments.
- [x] 5.9 Regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt`; update `scripts-shard-totality.test.sh:158`, `terraform-target-parity.test.ts:10563`, `ci-head-verdict.test.sh:1216`.
- [x] 5.10 `.claude/hooks/grep-q-pipe-guard.test.sh:2170` — substitute or drop the preactivation fixture row.
- [x] 5.11 `.github/workflows/code-quality-followups-watch.yml:81` — comment.
- [x] 5.12 Runbooks `ci-oracle-lane.md` (`:17,:74,:181`) + `ci-test-scripts-sharding.md` (`:31,:350-354,:518`).
- [x] 5.13 ADR-276 retirement amendment (dated `### Stage status` line, machinery list, dissent pair).

## 6. Phase 5 — Verification + merge prep

- [x] 6.1 Run the full verification battery in plan Phase 5 (all listed test files green).
- [x] 6.2 Residual-zero census greps — zero hits outside §Historical record.
- [x] 6.3 `python3 -c 'import yaml;print(len(yaml.safe_load(open(".github/workflows/ci.yml"))["jobs"]))'` == 20; ledger matches.
- [x] 6.4 Local `test-all.sh --affected` probe exits 0.
- [ ] 6.5 PR body: `Ref #N` only (no `Closes`/`Fixes`); oracle-review arm readiness (deruelle author or bound approval).
- [ ] 6.6 Merge via `gh pr merge --admin` when queue is shallow; NO `[skip-github-apply]` in the message.
- [ ] 6.7 Post-merge: watch `apply-github-infra.yml`; verify live ruleset = 11 CI names; `bypass_actors`/`conditions` unchanged; queue inspection; merge_group canary; census delta 12→11; record receipt as PR comment.
- [ ] 6.8 Close as *not planned*: #9729, #10414, #10415, #10949, #12151, #12154 (+ #12155, #12456 pending confirmation per decision-challenges.md).
