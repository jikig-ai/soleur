# Tasks: fix scheduled-oauth-probe notify checkout

Plan: `knowledge-base/project/plans/2026-05-04-fix-scheduled-oauth-probe-notify-checkout-plan.md`
Issue: #3118
Branch: `feat-one-shot-3118-oauth-probe-notify-fix`

## Phase 1: Inventory

- [ ] 1.1 Run `grep -rln "uses: \./\.github/actions/notify-ops-email" .github/workflows/ | sort` and confirm output matches the 22-workflow expectation.
- [ ] 1.2 Run `grep -L "actions/checkout" $(grep -rln "uses: \./\.github/actions/notify-ops-email" .github/workflows/)` and confirm output is exactly two files: `scheduled-oauth-probe.yml` and `scheduled-cloud-task-heartbeat.yml`. If a third file appears, expand the fix scope to it in this same PR (do not defer).
- [ ] 1.3 Confirm the canonical SHA pin via `grep -h 'actions/checkout@' .github/workflows/scheduled-terraform-drift.yml`. Expected: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`.

## Phase 2: Edit scheduled-oauth-probe.yml

- [ ] 2.1 Read `.github/workflows/scheduled-oauth-probe.yml` (Edit tool requires it).
- [ ] 2.2 Insert a new step as the first step of `jobs.probe.steps` (above the existing `- id: probe` at line 32):
    - Name: `Checkout (for local composite action)`
    - Uses: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
    - With: `sparse-checkout: |\n  .github/actions` and `sparse-checkout-cone-mode: false`
- [ ] 2.3 Confirm no other lines change (probe shell, cron, subject/body, masked secret usage all preserved).

## Phase 3: Edit scheduled-cloud-task-heartbeat.yml

- [ ] 3.1 Read `.github/workflows/scheduled-cloud-task-heartbeat.yml` to identify which job consumes `notify-ops-email` at line 180.
- [ ] 3.2 Insert the same checkout step as the first step of that job.
- [ ] 3.3 Confirm no other lines change.

## Phase 4: Local validation

- [ ] 4.1 `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-oauth-probe.yml'))"` returns 0.
- [ ] 4.2 `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-cloud-task-heartbeat.yml'))"` returns 0.
- [ ] 4.3 Acceptance grep (tightened to match the `uses:` line, not a stray comment):
    ```bash
    for f in .github/workflows/scheduled-oauth-probe.yml .github/workflows/scheduled-cloud-task-heartbeat.yml; do
      grep -qE '^\s*-?\s*uses:\s*actions/checkout@' "$f" \
        || { echo "MISSING checkout in $f"; exit 1; }
    done
    ```
- [ ] 4.4 Pin-drift check: `grep -h 'actions/checkout@' .github/workflows/*.yml | sort -u` shows a single pinned SHA (no v3 / no unpinned tags introduced).

## Phase 5: PR + post-merge verification

- [ ] 5.1 Open PR with body containing `Closes #3118` and `Ref #2997`.
- [ ] 5.2 After merge, run `gh workflow run scheduled-oauth-probe.yml --ref main`.
- [ ] 5.3 Poll `gh run list --workflow=scheduled-oauth-probe.yml --limit 1 --json databaseId,status,conclusion` until `status=completed`.
- [ ] 5.4 Inspect the log: `Email notification (failure)` step MUST NOT show `Can't find 'action.yml'` error. If probe was green, the step was skipped (its `if:` guard is false) — re-dispatch is not required for verification because the local-action resolution happens at job-prepare time, not at step-run time. If probe was red, the email step MUST now succeed.
- [ ] 5.5 If probe ran green, verify auto-close fired: `gh issue view 3118 --json state` returns `CLOSED`.
- [ ] 5.6 Run `gh workflow run scheduled-cloud-task-heartbeat.yml --ref main` (or trigger the workflow's natural condition) and confirm the notify path is no longer susceptible to the `Can't find 'action.yml'` failure.

## Out of scope (do not touch in this PR)

- The probe shell script (untouched per user instruction).
- Cron cadence (`*/15 * * * *`) — GitHub Actions deprioritization is a separate concern.
- The transient 07:25 UTC `network_error` itself — probe is green from local; if it recurs post-merge, file a new ticket.
