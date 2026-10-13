---
feature: lint-bot-statuses-required-promotion
issue: 6882
pr: 6883
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-23-feat-promote-credential-path-guard-required-check-plan.md
date: 2026-07-23
---

# Tasks: promote the credential-path guard to a blocking required check (#6882)

Phase order is load-bearing — the earner (Phase 2) MUST precede the contract (Phase 3).
Do not reorder.

## Phase 0 — Preconditions (verification only, no edits)

- [x] 0.1 Full-scan green: run `python3 scripts/lint-credential-path-literals.py`, then read `$?` on
      its own line → `0`. Do NOT pipe through `head`/`tail` before reading `$?` (a pipeline returns
      the last command's status and reports a false `0`).
- [x] 0.2 Confirm counts: `grep -vE '^\s*#|^\s*$' scripts/required-checks.txt | wc -l` → 21
- [x] 0.3 Confirm `jq 'length' scripts/ci-required-ruleset-canonical-required-status-checks.json` → 20
      and `jq '[.[]|select(.integration_id==15368)]|length' …` → 19
- [x] 0.4 Confirm `grep -c 'required_check {' infra/github/ruleset-ci-required.tf` → 20
- [x] 0.5 Confirm `create-ci-required-ruleset.sh`, `update-ci-required-ruleset.sh`, and
      `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts` read the canonical
      JSON and hardcode no set (no edit expected)
- [x] 0.6 Baseline `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` → 30 passed, 0 failed
- [x] 0.7 Baseline `bash scripts/lint-bot-synthetic-completeness.sh` → exit 0

## Phase 1 — RED: failing test first

- [x] 1.1 Add **Test 8** to `plugins/soleur/test/required-checks-canonical-parity.test.sh` asserting
      `.github/workflows/../actions/bot-pr-with-synthetic-checks/action.yml` invokes
      `lint-credential-path-literals.py` in its preflight. Follow the Test-4 style (grep the action
      body, fail loud, name ADR-139 in the failure message).
- [x] 1.2 Run the suite — Test 8 MUST FAIL (the preflight does not exist yet). Record the failure.

## Phase 2 — Earn the bot green (composite action)

- [x] 2.1 In `.github/actions/bot-pr-with-synthetic-checks/action.yml`, add a Phase-4
      "Secret-safety ceiling" step immediately after the `lint-fixture-content` reproduction:
      `python3 scripts/lint-credential-path-literals.py "${PATHS[@]}"` (shell: bash). Non-zero exit
      must abort before branch push / PR creation / synthetic posting, matching the gitleaks arm.
- [x] 2.2 Extend the `ALLOWED_PATHS` comment block: note that `credential-path-guard` is
      EARNED (not fabricated) via 2.1, and that its `SCAN_DIRS` DOES intersect `ALLOWED_PATHS`
      (`weakness-digest.md`) — which is why the `rule-body-lint` / `sentry-destroy-required`
      unreachability argument was not reused.
- [x] 2.3 Syntax-check the embedded shell only: `bash -c '<extracted run snippet>'`.
      Do NOT run `actionlint` on a composite action definition (spurious schema errors).
- [x] 2.4 Re-run the parity suite — Test 8 now PASSES (GREEN).

## Phase 3 — Extract the job (ci.yml)

- [x] 3.1 Add always-run job `credential-path-guard` to `.github/workflows/ci.yml`: checkout (pinned
      SHA, matching sibling jobs) + `python3 scripts/lint-credential-path-literals.py` (full scan,
      no `--changed`/`--base`).
- [x] 3.2 Verify the new job has NO `if:` gating on `github.event_name` — it must report on
      `pull_request` AND `merge_group` or the queue entry stalls pending forever.
- [x] 3.3 Verify the new job does NOT set `fetch-depth: 0` — full-scan needs no merge base.
- [x] 3.4 Remove the `Lint resolvable credential-file paths in docs (changed vs base)` step from
      `lint-bot-statuses`. LEAVE its `fetch-depth: 0` (lint-infra-no-human-steps still needs it).
- [x] 3.5 Add a comment above the new job marking it REQUIRED, and one above the remaining
      `lint-bot-statuses` steps restating they remain ADVISORY (mirror the existing #6734/ADR-129 note).

## Phase 4 — Register the contract (SSOT fan-out — all four in one commit)

- [x] 4.1 `scripts/required-checks.txt`: add `credential-path-guard` to the CI Required section with a
      comment stating the green is EARNED by the Phase-2 preflight, explicitly contrasting with the
      FABRICATED-NOT-EARNED entries above it and naming the `ALLOWED_PATHS ∩ SCAN_DIRS ≠ ∅` reason.
- [x] 4.2 `scripts/ci-required-ruleset-canonical-required-status-checks.json`: append
      `{"context": "credential-path-guard", "integration_id": 15368}`.
- [x] 4.3 `infra/github/ruleset-ci-required.tf`: add the matching `required_check` block.
- [x] 4.4 Same file: update the header comment `the 19 \`context\` strings` → `20`, and add a dated
      note recording this addition (mirror the existing #6049 / #6103 header notes).
- [x] 4.5 Confirm all four edits are staged together — the parity test enforces set equality
      file-vs-file, so partial staging goes red.

## Phase 5 — Tests

- [x] 5.1 `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` → ALL TESTS PASSED
- [x] 5.2 Prove Test 8 has teeth: temporarily delete the preflight line, re-run (MUST fail), restore.
- [x] 5.3 `bash scripts/lint-bot-synthetic-completeness.sh` → exit 0 AND its
      `Required synthetic checks:` line contains `credential-path-guard` (this is AC3)
- [x] 5.4 `bash scripts/lint-bot-synthetic-statuses.sh` → green (sibling gate, unchanged)
- [x] 5.5 Prove the preflight catches: write a temp `.md` containing a home-relative Doppler config
      path, run the linter positionally against it → exit 1. Delete the temp file.
- [x] 5.6 Full-scan still green: `python3 scripts/lint-credential-path-literals.py` → exit 0

## Phase 6 — Records

- [x] 6.1 Create the ADR via `/soleur:architecture` — "Earned-green preflight required for
      reachable-surface content gates". Provisional ordinal ADR-139 (highest existing is ADR-138).
      Record: the `ALLOWED_PATHS ∩ SCAN_DIRS = ∅` test, re-derived per gate never inherited; the
      tripwire-axis finding (generator output format is the second mutable input and no tripwire
      watches it); alternatives (integration_id = deadlock; shrink ALLOWED_PATHS = breaks
      weakness-miner). Amends — does not reverse — ADR-092 and the ADR-031 2026-07-17 amendment.
- [x] 6.2 If the ordinal is taken at ship time, renumber AND sweep this file, the plan, and every AC
      naming the ordinal in the SAME edit.
- [x] 6.3 Append the Art. 32(1)(d) entry to `knowledge-base/legal/compliance-posture.md` (incident
      class + advisory→blocking upgrade as evidence of testing/evaluating a technical measure).
- [x] 6.4 Confirm `knowledge-base/legal/article-30-register.md` is UNCHANGED
      (`git diff --stat` on it → empty).

## Phase 7 — Verification

- [ ] 7.1 Confirm TR7: full-scan wall-clock on the hosted runner is acceptable (check the job duration
      on the PR's first CI run).
- [ ] 7.2 Confirm `credential-path-guard` appears in the PR check list.
- [x] 7.3 Walk every AC (AC1–AC12) in the plan and record pass/fail with the command output.
- [ ] 7.4 PR body uses `Closes #6882` (not in the title).
- [ ] 7.5 Note R3 in the PR body: open PRs predating this merge will block on the new context until
      rebased — expected transitional cost of adding any required check.
