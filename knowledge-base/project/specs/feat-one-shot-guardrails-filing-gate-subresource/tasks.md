# Tasks: fix guardrails filing gate on issue sub-resources

Plan: `knowledge-base/project/plans/2026-09-27-fix-guardrails-filing-gate-issue-subresource-plan.md`

## Phase 1: Setup

- [ ] 1.1 Re-read `.claude/hooks/guardrails.sh` around the CLASS 4 comment and trigger, the
      `--body-file|-F)` case in the body-corpus reader, and the `names no user-visible consequence`
      refusal string. Confirm the plan's anchors still hold on the current base.
- [ ] 1.2 Copy the whole `.claude/hooks/` directory (with `lib/`) into the scratchpad as the
      main-hook baseline for the RED check and the differential corpus.

## Phase 2: RED

- [ ] 2.1 Append the 32 rows from the plan's `<details>` block to `.claude/hooks/guardrails.test.sh`,
      directly after the `gh api POST to another endpoint is untouched` row.
- [ ] 2.2 Bump `MIN_ASSERTIONS` from 127 to 159, and extend the running-sum comment with
      `+ 32 CLASS 4 endpoint-scope rows = 159`.
- [ ] 2.3 Run the suite against main's hook in the scratch copy. Expect exactly 21 `FAIL:` lines, all
      of them new rows.

## Phase 3: GREEN (`.claude/hooks/guardrails.sh`, four hunks)

- [ ] 3.1 Replace the CLASS 4 trigger with the `_api_first_words` helper and the one-source,
      one-endpoint-regex, one-signal-regex trigger (plan §1). Copy it exactly.
- [ ] 3.2 Rewrite the CLASS 4 comment block (plan §4), without the literal `_gh_api_issue=`.
- [ ] 3.3 Make `-F` a body file only when `_gh_create == 1` (plan §2).
- [ ] 3.4 Append the api-form exit-1 and `--input` sentence to the refusal string (plan §3).

## Phase 4: Verification

- [ ] 4.1 `bash -n .claude/hooks/guardrails.sh`, then `bash .claude/hooks/guardrails.test.sh`. Expect
      `Total: 159  Pass: 159  Fail: 0`.
- [ ] 4.2 `python3 scripts/lint-shell-capture-exit.py .claude/hooks/guardrails.sh`. Expect 0 new
      findings.
- [ ] 4.3 `grep -cE '^[^#]*_gh_api_issue=' .claude/hooks/guardrails.sh`. Expect `2`.
- [ ] 4.4 Run the differential corpus (plan Test Scenarios step 2) against the scratch main copy and
      the patched hook, both invoked in place. Expect no collection shape allowed under a POST
      spelling, no `-X GET` denied, and deny → allow flips only on sub-resource paths and
      `issues.json`.
- [ ] 4.5 `git diff --name-only origin/main...HEAD -- .claude/ apps/`. Expect exactly the two hook
      files.
