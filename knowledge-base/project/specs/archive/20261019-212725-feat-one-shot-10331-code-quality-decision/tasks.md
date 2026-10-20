# Tasks: Code Quality keep-or-drop decision (slice 4 of #10331)

Plan: `knowledge-base/project/plans/2026-10-19-chore-code-quality-keep-or-drop-decision-plan.md`

## Phase 1: Snapshot and #10381 read (browser, read-only)

- 1.1 Open the Code Quality alert list for main; record total, per-rule counts and severities, scan commit
- 1.2 Record the `py/empty-except` count for the five files #10381 names; do not trigger a scan
- 1.3 Capture `default-setup` state (languages, suite, schedule) and the last three code-scanning PR runs; an empty or stale alert view means #10381 is "unverifiable", never "verified"
- 1.4 Append "Final snapshot before disable, 2026-10-19" to `knowledge-base/engineering/audits/2026-10-14-github-code-quality-baseline.md`

## Phase 2: Disable (browser, repository settings)

- 2.1 Turn Code Quality off in the repository settings (org-level configuration if the repo toggle is locked); note any AI-credits-only toggle seen, do not use it as a substitute
- 2.2 Reload the settings page to prove it reads off; check workflow 343194280 is no longer active; push a trivial commit and confirm a code-scanning "PR" run but no "Code Quality: PR" run for that head; `default-setup` equals the Phase 1 capture
- 2.3 Only after 2.2 passes, settle #10381 with the snapshot via `gh issue close` and a comment (no close keyword in prose); merge straight after (the setting is live before merge)

## Phase 3: Ledger row

- 3.1 Run `bash scripts/expenses-verify-by-check.sh` and note the counts (expect candidates 34, expired 22, anomalies 0)
- 3.2 Re-read the meter and add the retired GitHub Code Quality row (Amount = measured meter sum 2026-09-22 to disable day, 254.96 at plan time) next to the GitHub Team row; set `last_updated: 2026-10-19`; no marker, no pipe in Notes; include `Re-evaluation by 2026-11-14`
- 3.3 Re-run the checker; counts unchanged

## Phase 4: ADR-276 addendum

- 4.1 Append `## Amendment 2026-10-19 (S5 Code Quality decision, #9730; Ref #10331)` (append-only; `git diff` shows no removed lines)
- 4.2 Confirm `2026-11-14` appears in both the addendum and the ledger Notes

## Phase 5: Wrap-up

- 5.1 `gh issue comment 9730` pointer (decision, ledger row, amendment, re-evaluation date)
- 5.2 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh`
- 5.3 PR body: the standalone issue-closing line for #10331 exactly as the brief spells it, and the statement that the disable is a repository setting applied by the agent (no in-repo change, no operator step); do not touch `plugins/soleur/skills/work/SKILL.md`
