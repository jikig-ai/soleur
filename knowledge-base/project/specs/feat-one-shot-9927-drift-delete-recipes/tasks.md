# Tasks: fix drift workflow DELETE recipes (#9927 item 8c)

Plan: knowledge-base/project/plans/2026-10-15-fix-drift-workflow-remove-delete-recipes-plan.md
Ref #9927 only (no closing keyword).

## Phase 1: RED first

- 1.1 Add `all_run_bodies <wf>` helper (python + yaml.safe_load, all steps, path-parameterised) to plugins/soleur/test/token-drift-workflow-causes.test.sh
- 1.2 Add Check 1: step-scoped Hetzner write-verb check (comment-stripped bodies mentioning api.hetzner.cloud or HCLOUD_TOKEN)
- 1.3 Add Check 2: whole-workflow Doppler `configs|environments|projects delete` check
- 1.4 Add Check 3: positive anti-vacuity row (exactly 2 filers, read-only label_selector loops, distinct labels, steps-examined floor)
- 1.5 Add Check 4: sandbox mutation row (control GREEN; injected -X DELETE RED; injected doppler configs delete RED; comment-only and non-Hetzner `gh api -X POST` must-PASS)
- 1.6 Raise the anti-vacuity floor (guard, FATAL message, comment) to the realized PASS+FAIL (currently 61, expected 65)
- 1.7 Run suite against the unchanged workflow; confirm Checks 1 and 2 RED; keep output for the PR body

## Phase 2: GREEN workflow edit

- 2.1 Rung-2 filer: replace survivors prose, mark fence READ-ONLY, delete the three DELETE-related echo lines, reword the Doppler paragraph (CTO text)
- 2.2 Inngest filer: replace second Remedy paragraph, add READ-ONLY comment, delete the two DELETE echo lines, reword the Doppler environment paragraph (CTO text)
- 2.3 `bash -n` each extracted filer body; YAML parses; no `-X` left in the file

## Phase 3: Sweep hits

- 3.1 ADR-282 residual bullet erratum (status stays accepted)
- 3.2 inngest-provision-rehearsal.md line ~167 reword
- 3.3 Confirm archived plans, git-data-rung2-rehearsal.md ~406, census tests untouched

## Phase 4: Verify (targeted suites only)

- 4.1 token-drift-workflow-causes, terraform-drift-step-order, terraform-drift-sentry-leg, heartbeat-reconcile-issue-step
- 4.2 git-data-rung2-rehearsal.test.sh, inngest-provision-rehearsal.test.sh
- 4.3 bun test plugins/soleur/test/terraform-target-parity.test.ts
- 4.4 python3 scripts/lint-guard-contract.py

## Phase 5: Ship

- 5.1 PR body/title/commits: Ref #9927, no closing keyword; trailers per instructions
- 5.2 Note UNTRUSTED-CI (workflow diff, no agent --admin fallback)
- 5.3 Optional follow-up note under #9927: HCLOUD_TOKEN_READONLY in the fence
