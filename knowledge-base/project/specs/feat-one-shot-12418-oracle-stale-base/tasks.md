# Tasks — feat-one-shot-12418-oracle-stale-base

Derived from `knowledge-base/project/plans/2026-11-09-fix-oracle-stale-base-s3-probe-retirement-plan.md`.

## 1. Oracle fix (issue #12418)

- [ ] 1.1 `.github/workflows/ci.yml` `oracle-selection` step: add `PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}` and `PR_BASE_REF: ${{ github.event.pull_request.base.ref }}` to the `env:` block with an anchored comment; leave the `base="HEAD^1"` driver-source line untouched
- [ ] 1.2 `scripts/ci-oracle-lane.sh` (2a) arm: resolve the live base (payload `PR_BASE_SHA` verified resolvable → else `git fetch --no-tags --quiet origin "$PR_BASE_REF"` → `FETCH_HEAD`), set `diff_base=$(git merge-base HEAD^2 "$resolved")`; every failure arm emits fail-closed defaults with a named `reason=`; `base_sha` emits the merge-base
- [ ] 1.3 Update the driver header grammar comment (line ~41) and the runbook `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` manual-replay recipe to the merge-base derivation
- [ ] 1.4 `scripts/ci-oracle-lane.test.sh`: `drive()` env for `PR_BASE_*`, a merge-carrying-branch fixture (stale `HEAD^1`, branch merged newer main carrying oracle-surface paths), linear-branch regression row, fetch-failure and empty-merge-base fail-closed rows
- [ ] 1.5 Append a dated amendment note to ADR-276 recording the #12418 diff-base correction

## 2. Retirement (trackers #9728 + S3-EXIT-CENSUS)

- [ ] 2.1 `git rm scripts/followthroughs/ci-draft-light-soak-9728.{sh,test.sh} scripts/ci-draft-push-census.{sh,test.sh}`
- [ ] 2.2 `scripts/test-all.sh`: delete the two `run_suite` blocks (comment + line); the `scripts/ci-draft-light` block stays
- [ ] 2.3 `.github/CODEOWNERS`: delete the four rows
- [ ] 2.4 `scripts/ci-pr-affected-audit.accept.tsv`: prune the stale row at 1806 per the audit's stale report
- [ ] 2.5 `.claude/hooks/grep-q-pipe-guard.test.sh`: delete the exemption row at 2205
- [ ] 2.6 Reword basenames out of `scripts/sweep-followthroughs.sh:61`, `scripts/sweep-followthroughs.test.sh:1656,1735`, `.github/workflows/scheduled-followthrough-sweeper.yml:68`, and `fixture-relative-assert.baseline.txt:~147` (issue-number tombstone `#9728`)

## 3. Regenerations

- [ ] 3.1 `python3 scripts/regenerate-shard-manifest.py --incremental --write` — verify the diff removes exactly the two label rows per TSV
- [ ] 3.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` — verify the three rows drop

## 4. Verification

- [ ] 4.1 `bash scripts/ci-oracle-lane.test.sh` — green end-to-end including new merge-base rows
- [ ] 4.2 `bash scripts/lint-orphan-test-suites.sh`, `bash scripts/sweep-followthroughs.test.sh`, `bash plugins/soleur/test/fixture-relative-assert.test.sh`, `bash .claude/hooks/grep-q-pipe-guard.test.sh` — all green
- [ ] 4.3 Affected-index ratchet/audit reports no `stale` rows; `bash plugins/soleur/test/scripts-shard-totality.test.sh` green
- [ ] 4.4 `rg -n 'ci-draft-light-soak-9728|ci-draft-push-census' scripts/ .github/ .claude/ plugins/` → zero hits
- [ ] 4.5 `git diff` review of the regenerated TSVs — exactly the two label rows removed, no unrelated rebalance
