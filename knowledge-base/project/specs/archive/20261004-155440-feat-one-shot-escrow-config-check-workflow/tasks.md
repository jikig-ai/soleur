# Tasks: unattended read-only web-host escrow readiness diagnostic workflow

Plan: `knowledge-base/project/plans/2026-10-04-chore-web-host-escrow-readiness-diagnostic-workflow-plan.md`
Issue refs: #9377, #9461 (Ref only, never Closes). Do NOT dispatch the workflow in any phase.

## Phase 1 - Setup / failing test first

- 1.1 Create `plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh` (a required check via the scripts-group glob; the infra-directory alternative is advisory) (instrument self-test, YAML-parsed structural rows, behavioural rows that execute the extracted step body against the REAL preflight and checker behind a Doppler stub).
  - 1.1.1 Structural rows: triggers, effective permissions, one job, environment, loader `with:` keys, checkout flags, no write verbs, no persisting sinks, no expansion of the token variable.
  - 1.1.2 Behavioural rows: rc 0 with `live-ok`, rc 0 with empty output (must not pass), 1, 2, 3, 78 (inject `SHELLOPTS=xtrace`), an unlisted code; token and canary containment; Doppler-stderr credential-shape containment; injection and cap rows.
  - 1.1.3 Wording pins (doc-grep): runbook step 0 and the PASS text carry "not sufficient"; runbooks carry the re-run-at-birth and current-main-head sentences and drop the stale snippet.
  - 1.1.4 Dispatch rows: workflow missing / renamed reds as `workflow-missing`; declared case count pinned exactly.
- 1.2 Run it and confirm it is RED before the workflow exists.

## Phase 2 - Core implementation

- 2.1 Create `.github/workflows/web-host-escrow-diagnose.yml` as pinned in the plan, plus the as-built additions recorded in the plan's "As-built deltas" ceiling note (dispatch only, `contents: read`, one job on `infra-privileged`, checkout with `persist-credentials: false`, loader with ONLY `doppler-token-infra-privileged`, one check step).
- 2.2 Make the shape test green.

## Phase 3 - Wire the gates

- 3.1 Confirm the suite is picked up by the `plugins/soleur/test/*.test.sh` glob and `bash scripts/lint-orphan-test-suites.sh` is green. No `infra-validation.yml`, CODEOWNERS or C4 edit. (As built, the review round added the shard-manifest rows and an affected-gate `AFFECTED_` array.)
- 3.3 Run: tier census, terraform-target-parity, workflow-file-size, web-host-escrow-preflight-census, c4-count-parity, loader test, preflight and checker suites, `scripts/lint-workflows.sh`, the four `lint-workflow-*.py` gates. No assertion edits.
- 3.4 `git diff origin/main` over the untouched-by-design files is empty (web-1 refusal lib, preflight, loader); the checker differs by header comment lines only.

## Phase 4 - Docs and ADR

- 4.1 Rewrite step 0 of `web-host-birth.md` and `web-host-replace.md` (dispatch, watch, decode table incl. loader verdicts, branch-ref refusal, necessary-not-sufficient, valid-at-run-time, token note); repoint the birth break-glass source to `soleur-infra-privileged/prd` with its precondition.
- 4.2 ADR-241 D2 dated note via `soleur:architecture` (true-strength residual, D11 reconciliation, #9461 link). No status change.

## Phase 5 - Tracking and hand-off

- 5.1 Comment on #9461 (diagnostic path only; birth/replace unchanged) and on #9377.
- 5.2 NOT TAKEN (decision-challenges.md): no deferral issue is filed; the deferral and its trigger are recorded in the ADR-241 note and the plan's Deferred table.
- 5.3 `python3 scripts/lint-guard-contract.py` on the plan; markdownlint on plan and tasks.
- 5.4 PR body: `Ref #9377`, `Ref #9461`, necessary-not-sufficient sentence, residual, "workflow NOT dispatched". Run `soleur:engineering:review:user-impact-reviewer` at review.

## Post-merge (automated, next step; not part of this PR's work)

- 6.1 An agent dispatches `gh workflow run web-host-escrow-diagnose.yml --ref main`, arms `gh run watch`, records the verdict on #9377.
