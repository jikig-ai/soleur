---
title: "Tasks — bwrap probe self-report"
branch: feat-one-shot-8016-bwrap-probe-self-report
plan: knowledge-base/project/plans/2026-09-10-fix-bwrap-probe-self-report-plan.md
lane: single-domain
issue: 8016
---

# Tasks

Derived from `knowledge-base/project/plans/2026-09-10-fix-bwrap-probe-self-report-plan.md` after
plan review. Read the plan's `## Sharp Edges` before starting phase 2 — several tasks below are
one-line changes whose *wrong* form was measured this session and looks correct.

## Phase 0 — Preconditions

- [ ] 0.1 Re-read the NOTE block above the probe (anchor
      `# NOTE: a prior change (#4932) added --unshare-user --proc /proc here to`). The bwrap argv is
      not touched by anything below.
- [ ] 0.2 Confirm `_cred_err_tail` is top-level in `apps/web-platform/infra/ci-deploy.sh` and
      therefore in scope at the probe site.
- [ ] 0.3 Re-run the capture-form check:
      `bash -c 'set -euo pipefail; f(){ return 137; }; RC=0; V="$(f 2>&1)" || RC=$?; echo "rc=$RC len=${#V}"'`
      Expected `rc=137 len=0`. This is the line the whole PR turns on.
- [ ] 0.4 Measure `docker exec`'s exit-code stamping against the pinned host Docker version
      (`docker_ver=29.3.0` in the 2026-09-09 rows). Do **not** measure bwrap's codes — cite upstream.
- [ ] 0.5 Baseline `bash apps/web-platform/infra/ci-deploy.test.sh` → `216/216 passed, 0 failed`.
      A pre-existing red is a stop-and-report, not something to work around.
- [ ] 0.6 Run the live Better Stack query with **both** contamination byte-forms
      (`SYSLOG_IDENTIFIER":"ci-deploy` and `SYSLOG_IDENTIFIER\":\"ci-deploy\"`). Now, not
      post-merge — it is the only check that surfaces the JSON escaping before merge.

## Phase 1 — Tests first (RED)

- [ ] 1.1 Set `MOCK_LOGGER_CAPTURE_FILE` in the `assert_canary_sandbox_failed_state` scenario.
      The export goes **inside** the scenario's existing command-substitution subshell, path from
      the scenario's own `mktemp -d`. Hoisting it contaminates four later scenarios.
- [ ] 1.2 Select the rollback line by `grep -F 'DEPLOY_ROLLBACK: bwrap sandbox non-functional'`,
      assert the match count is exactly 1, then test fields on that line. **Do not copy
      `assert_ghcr_login_class`'s `head -1`** — it stops at the first match and makes the count
      assertion vacuous.
- [ ] 1.3 Parameterise the existing `bwrap-fail)` mock with `MOCK_BWRAP_FAIL_STDERR` and
      `MOCK_BWRAP_FAIL_RC`. Do not add new modes. `${VAR-default}` with **no colon** — an explicitly
      empty value must mean "silent", which `${VAR:-default}` would override.
- [ ] 1.4 Write the five scenarios: spoken, silent (`rc=137`, empty), purity (leak canary + CR +
      non-ASCII + `"` + `dp.st.` token), truncation (over-200, no redactable token), and
      pass-with-chatter (`rc=0` with stderr). All fixtures synthesized.
- [ ] 1.5 Write the Guard Contract assertions (plan `## Guard Contract`). They must fail against the
      current `ci-deploy.sh`.
- [ ] 1.6 Record the RED output.

## Phase 2 — Implementation (GREEN)

- [ ] 2.1 Replace the probe's condition with the errexit-safe, rc-preserving capture from the plan's
      Phase 2 block. `BWRAP_ERR="$(…)" || BWRAP_RC=$?` — not `if ! VAR=$(…)` (yields `rc=0`), not a
      bare assignment (aborts the script).
- [ ] 2.2 Add `PROBE_SECS` from `$SECONDS` around the capture.
- [ ] 2.3 Add the sanitizer call with its explicit rescue:
      `BWRAP_ERR_SAN="$(_cred_err_tail "$BWRAP_ERR")" || BWRAP_ERR_SAN="<sanitize_failed>"`.
- [ ] 2.4 Add the guarded re-emit **outside** the failure branch, carrying the sanitized value.
      An `if` block, not `[[ -n … ]] && printf …`.
- [ ] 2.5 Extend the `DEPLOY_ROLLBACK` logger line with `rc=`, `secs=`, `err_chars=` and, last and
      double-quoted, `err="…"`.
- [ ] 2.6 Add `blocking_probe_sentry_event`, modelled line-for-line on `sandbox_canary_sentry_event`,
      `op: "blocking-sandbox-probe"`, invoked with `|| true`.
- [ ] 2.7 Add the success-path twin `SANDBOX_PROBE_OK: rc=0 secs=$PROBE_SECS`, closed-vocabulary only.
- [ ] 2.8 Add one sentence to `_cred_err_tail`'s header recording the bwrap probe as its second
      producer **and** naming its 200-byte clamp. Do not change its body.
- [ ] 2.9 Verify untouched: the bwrap argv, `final_write_state 1 "canary_sandbox_failed"`,
      `run_faithful_sandbox_canary`. `rc` must not influence the rollback branch.
- [ ] 2.10 Run the suite to GREEN.

## Phase 3 — Mutation-prove the guard

- [ ] 3.1 Run mutation rows 1-6 and harness row H1; each must drive the suite RED. Restore after each.
- [ ] 3.2 Run harness rows H2, H3, H4; each must PASS.
- [ ] 3.3 Record the observed result per row for the PR body.

## Phase 4 — Correct #8016

- [ ] 4.1 Write the comment body to a temp file per the plan's `## Task 1` content requirements.
- [ ] 4.2 `gh issue comment 8016 --body-file <path>`. Do **not** edit the issue body.
- [ ] 4.3 Verify the body is unchanged against the SHA-256 recorded in the plan.

## Phase 5 — Filings

- [ ] 5.1 File the follow-through diagnosis tracker with the `follow-through` label and the
      `<!-- soleur:followthrough … -->` directive. Reference it from the PR body as `Ref #<N>`,
      never `Closes` — Phase 5.5's gate only sees `Ref|Tracks`.
- [ ] 5.2 Author `scripts/followthroughs/bwrap-probe-selfreport-<N>.sh`, modelled on
      `ci-deploy-sentry-post-fail-6475.sh`. Notify-only exits: 2 NOT YET, 5 ACTION REQUIRED,
      3 CANNOT ESTABLISH. Never 0, never 1.
- [ ] 5.3 Author the sibling `.test.sh` pinning the never-0/never-1 invariant.
- [ ] 5.4 File adjacent finding 1 (ghcr login classifier discards 70 bytes of stderr; relate to #6560).
- [ ] 5.5 File adjacent finding 2 (`IMAGE_VERIFY_FAIL result=cosign_absent mode=warn`).
- [ ] 5.6 File adjacent finding 3 (Vector allowlist contradicts its own documentation, two places).
- [ ] 5.7 File adjacent finding 4 (ADR-079 Deferral A orphaned; #5889 closed 2026-07-06 with a
      promote verdict that was never acted on; ADR-079 line 509 is factually wrong).
- [ ] 5.8 Add `<!-- gate-override: net-issue-flow -->` to the PR body with one justification line per
      filing. Net is +4.

## Phase 6 — Register bracket (contested)

- [ ] 6.1 Append one additive dated bracket to PA-8 §(g) of
      `knowledge-base/legal/article-30-register.md`. See `decision-challenges.md` §1 — one reviewer
      argued to cut this. Retained pending operator direction.

## Phase 7 — Ship

- [ ] 7.1 Put the three-way triage table (plan `## Closing`) in the PR body.
- [ ] 7.2 Expect `/ship` Phase 3.7 (dark-launch deploy gate) and Phase 5.5 (`deploy_pipeline_fix`
      auto-apply) to fire. Both are correct.
- [ ] 7.3 After merge, watch the first release against the triage table; the follow-through probe's
      window starts at the merge date and covers the same span.
