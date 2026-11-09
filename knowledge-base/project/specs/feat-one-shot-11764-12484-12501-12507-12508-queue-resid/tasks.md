# Tasks — feat-one-shot-11764-12484-12501-12507-12508-queue-resid

Plan: `knowledge-base/project/plans/2026-11-09-fix-merge-queue-residual-batch-plan.md`
Issues: #11764, #12484, #12501, #12507, #12508 (one PR)

## 1. Setup

- [ ] 1.1 Re-fetch `origin/main`; re-check state of in-flight siblings PR #12495 (`merge-queue-stall-check.yml` + test) and PR #12498 (`apply-web-platform-infra.yml` + `deploy-policy-gate.sh`) — both were OPEN at plan time (2026-11-09); if either merged, rebase first and mirror any drifted reference shape.
- [ ] 1.2 Confirm the five issues are still OPEN and unclaimed (`gh issue view` + `collision-precheck.sh` per issue — PR #12510 is this pipeline's own draft, not a duplicate).

## 2. Phase 1 — #12484: three-dot port to ci-pr-selection.sh

- [ ] 2.1 In `scripts/ci-pr-selection.sh` `run()` pull_request arm: add `PR_BASE_REF` regex gate (`^[A-Za-z0-9][A-Za-z0-9._/-]*$` → `bad_base_ref`), unconditional `git fetch --no-tags --quiet origin "refs/heads/$PR_BASE_REF"` (→ `base_fetch`), `diff_base="$(git merge-base HEAD^2 FETCH_HEAD)"` (→ `no_merge_base`), `diff_head="$p2"`; replace the `HEAD^1 HEAD` diff args with `"$diff_base" "$diff_head"`; emit `base_sha` = the resolved merge-base. Place the fetch after the cheap env gates (not-PR/merge-shape/fork/re-run), before the diff — mirror `scripts/ci-oracle-lane.sh:314-331`.
- [ ] 2.2 Wire `PR_BASE_REF: ${{ github.event.pull_request.base.ref }}` into the pr-selection step env in `.github/workflows/ci.yml` (mirroring the oracle-selection arm at ~:487).
- [ ] 2.3 `scripts/ci-pr-selection.test.sh`: add stale-frozen-parent fixture (`HEAD^1` ≠ merge-base → PR-side-only file list), `bad_base_ref`/`base_fetch`/`no_merge_base` named-reason rows, and an up-to-date must-pass row.
- [ ] 2.4 `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md`: update the T5 drift-rule note to record the port landed (dated).

## 3. Phase 2 — #12501: any-commit reach in the two sibling apply workflows

- [ ] 3.1 `apply-github-infra.yml`: add `EVENT_MSGS_JSON: ${{ toJSON(github.event.commits.*.message) }}` beside `HEAD_MSG` in the kill_switch step (:88) and the plan step (:290); in each run body build `POLICY_MSGS` = `HEAD_MSG` + `jq -r 'join("\n")'` of `EVENT_MSGS_JSON` (with the `null`/empty guard) and point the anchored `[skip-github-apply]` / `[ack-destroy]` regexes at `POLICY_MSGS`. Keep regex literals byte-identical.
- [ ] 3.2 `apply-sentry-infra.yml`: same two sites (:161/:167 skip, :802+ ack-destroy).
- [ ] 3.3 Rewrite stale guidance: `apply-github-infra.yml:115` `if:`-conjunct comment; `apply-sentry-infra.yml` `:1190`, `:1302` (AC17 error text), `:1445-1446` ("only gesture that carries the original head_commit.message") — state that any commit in the push supplies the token, a re-run carries the original `commits` array, and `workflow_dispatch` still cannot (keep the 20-commit `event.commits` cap caveat per the issue).
- [ ] 3.4 Tests: below-tip-token fixtures in `tests/scripts/test-destroy-guard-counter.sh` (github-infra) and `test-destroy-guard-counter-sentry.sh` (sentry); update `test-apply-github-infra-mint-shape.sh:245-248` env snapshot; re-derive the `test-sentry-alert-adoption-guards.sh:140` count; confirm `test-destroy-guard-regex-parity.sh` stays green.

## 4. Phase 3 — #12507: promoted-head build-start aging

- [ ] 4.1 `merge-queue-stall-check.yml` run body: after the `stalled` jq and before filing, per entry with a valid 40-hex `headCommit.oid`, correlate its `merge_group` ci.yml run (reuse `fetch_runs`/`refre` machinery; `head_sha == oid` join) and re-age from `run.created_at`; file only when run-derived age > threshold OR no merge_group run exists. Keep `enqueuedAt`-only behavior for null/malformed oid. Add a comment block naming the promotion class (keep the edit inside the run body — expect rebase vs PR #12495's comment hunks).
- [ ] 4.2 `plugins/soleur/test/merge-queue-stall-check.test.sh`: rows for promoted-young-build (no file), promoted-old-build (file), old-head-no-run (file), null-oid (unchanged); assert the run-list lookup executes on every row (non-vacuity per suite convention).

## 5. Phase 4 — #12508: explicit enqueue after arming

- [ ] 5.1 `.github/scripts/bump-inngest-bootstrap-pin.sh`: after the successful `gh pr merge --auto --squash` arm (arm branch only — mirror_only/withheld unchanged), resolve the PR node id and `gh api graphql` `enqueuePullRequest` (no `jump`); on rejection `::warning` + continue.
- [ ] 5.2 `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`: rows — enqueue called with node id and no `jump`; enqueue failure → warn + exit 0; withheld-arm → no enqueue call.
- [ ] 5.3 ADR-270 dated addendum (2026-11-09): authored bot PRs enqueue explicitly; record the #12489 counter-instance (armed 13:30Z, `isInMergeQueue: false`, BLOCKED 5h20m+).

## 6. Phase 5 — #11764: producer routing + `.cs` reclaim

- [ ] 6.1 Census (uncommitted, results into PR body): `/tmp` top-level prefix histogram; `git grep -n mktemp` census across `.claude/hooks/`, `plugins/soleur/`, `scripts/`, `tests/`, `apps/` (exclude `knowledge-base/`); classify each site trapped / owned / needs-cleanup / external.
- [ ] 6.2 `plugins/soleur/test/test-helpers.sh`: in the no-outer-root arm, `export TMPDIR` at the `.soleur-owned` sandbox so descendant `mktemp` lands inside the owned dir (documented harness exception in `scratch-root.sh`).
- [ ] 6.3 Cleanup at census-confirmed repo-owned producers: `plugins/soleur/skills/skill-security-scan/scripts/{lib.sh,run-scan.sh}`, `plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh`, `scripts/followthroughs/git-data-rung2-evidence-capture.sh`, `tests/scripts/lib/git-data-birth-readiness-gate.sh`, `tests/scripts/test-git-data-birth-readiness-gate.sh`, and the non-test `.claude/hooks/` mktemp sites lacking cleanup — `trap`/`rm -f` per ADR-129 composition, or `soleur_scratch_session_begin` where the file is a harness.
- [ ] 6.4 `apps/web-platform/server/agent-env.ts`: `env.TMPDIR = opts.claudeTmpDir` beside the `CLAUDE_CODE_TMPDIR` injection; update `agent-runner-query-options.test.ts` and `cc-dispatcher-real-factory.test.ts` env-shape assertions.
- [ ] 6.5 `scripts/tmpfs-guard.sh`: owned-base age arm over `/tmp/.cs` (48h floor; reap aged entries + fully-stale tenant dirs; existing in-use map still applies); rows in `scripts/tmpfs-guard.test.sh` (aged reaped / fresh kept / non-`.cs` untouched).
- [ ] 6.6 ADR-250 dated addendum (2026-11-09): TMPDIR routing + owned-base age reaping; shared-`/tmp` heuristic reaping remains rejected.

## 7. Phase 6 — Verify

- [ ] 7.1 Suites: `scripts/ci-pr-selection.test.sh`, `tests/scripts/test-destroy-guard-{counter,counter-sentry,regex-parity,apply-github-infra-mint-shape}.sh`, `tests/scripts/test-sentry-alert-adoption-guards.sh`, `plugins/soleur/test/merge-queue-stall-check.test.sh`, `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`, `scripts/tmpfs-guard.test.sh`.
- [ ] 7.2 `apps/web-platform`: `./node_modules/.bin/vitest run` for `agent-runner-query-options` + `cc-dispatcher-real-factory`; `./node_modules/.bin/tsc --noEmit` (in-package, never `npm run -w`).
- [ ] 7.3 `actionlint` on the four edited workflows; `bash -n` on every edited `.sh`.
- [ ] 7.4 PR body: producer census histogram (AC14) + five `Closes #N` lines + blast-radius line (workflows edited are inert until their next matching push; pr-selection lever still dark).
