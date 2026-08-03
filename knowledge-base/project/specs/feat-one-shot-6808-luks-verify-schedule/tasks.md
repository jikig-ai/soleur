---
feature: feat-one-shot-6808-luks-verify-schedule
plan: knowledge-base/project/plans/2026-08-03-feat-luks-verify-scheduled-with-alarm-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
pr: 7196
refs: [6808, 6588, 6604, 6807, 6812, 7138, 3958]
---

# Tasks — schedule `workspaces-luks-verify` daily, with its failure-surfacing path

Derived from the finalized plan. Phase order is load-bearing: 1.0 unblocks CI for everything after
it, and the classification contract must exist before anything consumes it.

## Phase 0 — Preconditions (verify, do not assume)

- [ ] 0.1 Confirm `git branch --show-current` == `feat-one-shot-6808-luks-verify-schedule`
- [ ] 0.2 Re-run the plan's §Premise Validation live checks; any divergence halts and re-scopes
- [ ] 0.3 Read ADR-033's 2026-06-02 scope note in full; confirm the anti-circularity corollary is
      genuinely absent before drafting the addendum. No new ordinal, so no collision sweep
- [ ] 0.4 *(resolved at deepen-plan — no edit needed.)* `sentry-monitor-iac-parity.test.ts`
      enumerates every `.yml`/`.yaml` in `.github/workflows/` and greps for `monitor-slug:`; no
      `scheduled-*` prefix filter. It auto-discovers this workflow — and FAILS if a `monitor-slug:`
      is declared with no matching `sentry_cron_monitor`, so the two must land together
- [ ] 0.5 Baseline the four grep-anchored constraints so drift is detectable: AC7 (API-prefixed
      health literal → expect 0), AC10 (the extracted `307|…` set), `luks-monitor.test.sh` case (y)
      verdict-grep pattern, `workspaces-luks-header.test.sh` H15b/H20
- [ ] 0.6 `bash apps/web-platform/infra/run-registered-suites.sh --list` and run the workspaces-luks
      suites green **before** any edit, so a later failure is attributable
- [ ] 0.7 Re-measure the live Sentry PAYG figure (for Phase 3.5) — do not trust the written one

## Phase 1 — Unblock CI, then RED

- [ ] 1.0 **Do this first.** Add `- ".github/workflows/workspaces-luks-verify.yml"` to
      `.github/workflows/infra-validation.yml`'s `paths:`. Until this lands, every guard in this PR
      is unreachable on the PRs that would break it
- [ ] 1.0b Register `workspaces-luks-verify-workflow.test.sh` in `infra-validation.yml`, adjacent to
      the existing `workspaces-luks-cutover-workflow.test.sh` registration
- [ ] 1.1 Create `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`, mirroring
      `workspaces-luks-cutover-workflow.test.sh` (PyYAML parse → TSV verdicts → `bash -n` on extracted
      `run:` bodies → execute with stubs → positive controls), borrowing the PATH-stub technique from
      `git-data-rung2-rehearsal.test.sh` arm 13 where `bash -e` fidelity matters
  - [ ] 1.1a Parse the workflow as YAML (never grep for structure); extract every `run:` body and
        `bash -n` each. Empty extraction is a hard fail, never a skip
  - [ ] 1.1b Execute the `id: reassert` body under `bash -e` with `ssh`/`curl`/`tar`/`doppler`
        stubbed, over the fixture set: `pass` (positive control); rc 1 → `drift`;
        rc 3 `workspace_count_shortfall` → `readiness`; rc 3 `readyz_not_ready` → `readiness`;
        rc 3 empty reason → `readiness`; rc 3 `workspace_count_baseline_missing` → `unavailable`;
        rc 3 `readyz_gate_regression` → `unavailable`; rc 255 → `unavailable`; rc 127 → `unavailable`;
        **rc 1 `mapper_path_override_refused` → `unavailable`** (reason-first, not rc-first);
        rc 1 `doppler_unreachable` → `unavailable`; verdict line absent → `unavailable`;
        health 307 (STRUCTURAL) → `readiness`; health 521 after budget (RETRYABLE) → `unavailable`
  - [ ] 1.1c Seed-refusal fixtures: `GITHUB_EVENT_NAME=schedule` + non-empty seed → non-zero exit,
        class `unavailable`, **and the ssh stub records no `WORKSPACES_COUNT=` append**;
        `GITHUB_EVENT_NAME=schedule` + empty seed → seed branch not entered
  - [ ] 1.1d Non-vacuity guard: assert the fixture set produced **all four** classes
  - [ ] 1.1e **Evaluated truth table** over the alarm `if:` — `steps.reassert.outcome ∈ {success,
        failure, skipped, cancelled}` × `outcome_class ∈ {pass, drift, readiness, unavailable, ''}`;
        the alarm fires on every cell except `(success, pass)`. NOT a substring grep
  - [ ] 1.1f YAML-shape assertions (the three that encode a lesson): `id: reassert` present; the
        alarm `if:` names `always()` + `github.event_name == 'schedule'`/`alarm_selftest` +
        the `steps.reassert.outcome` conjunct; the workflow cron == the `cron-monitors.tf` crontab
  - [ ] 1.1g Execute the alarm body with a stubbed `gh` recording argv: one fixture per class asserts
        a create-or-comment happened; `gh label create … || true` is idempotent; dedupe queries before
        creating; empty class routes to `unavailable`; a `drift` body carries `first_observed_at` +
        the counsel trigger-(3) pointer; a repeat with an unchanged `reason` adds no comment;
        ops-email fires for `drift`/`readiness` and not `unavailable`
  - [ ] 1.1h **`paths:` drift assertion** — every file this suite greps appears in
        `infra-validation.yml`'s `paths:`
  - [ ] 1.1i Assertion floor set to the suite's actual count (not an aspirational 40); the
        all-four-classes guard in 1.1d is the primary anti-vacuity check
- [ ] 1.2 Run it. It MUST fail — a test that passes before the change tests nothing

## Phase 2 — GREEN: the workflow

- [ ] 2.1 Add the `schedule:` trigger (`41 4 * * *`) with a header comment carrying the ADR-033
      carve-out citation, the anti-circularity corollary, the cadence justification, the `always()`
      rationale and the #6808 sunset note. Leave `workflow_dispatch:` and `seed_workspace_count`
      byte-identical
- [ ] 2.2 `permissions:` → `contents: read` + `issues: write`
- [ ] 2.3 Add `id: reassert` to the Re-assert step
- [ ] 2.4 Implement the **inline** classifier — **reason-first, then rc** — and call `emit_class`
      immediately before **every** `exit` (see the plan's exit-site → class map), including the early
      `WEB_HOST_SSH` guard. Hoist the `sed` reason extraction above the rc branching. Change no
      existing `::error::` string and no existing exit code
- [ ] 2.5 Add the scheduled-seed refusal guard before any seed handling
- [ ] 2.6 Set `health_class=structural` **inside the existing `307|…` case-arm body** (an addition,
      not a re-spelling) so the classifier can split STRUCTURAL from RETRYABLE without re-listing
      codes (which AC10 forbids)
- [ ] 2.7 Add `emit_class pass` before the final PASSED echo
- [ ] 2.8 Add the `alarm_selftest` dispatch-only boolean input (`default: false`) and extend the
      alarm gate to `github.event_name == 'schedule' || inputs.alarm_selftest`
- [ ] 2.9 Add the alarm step **after** the bridge-teardown steps (SSH key shredded before `gh` runs):
      literal `if:` from the plan; `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` in `env:`; `case`-based
      class routing to three **titles** under one `ci/luks-verify` label; idempotent
      `gh label create … || true`; dedupe by label + exact title via a standalone `jq --arg`;
      comment only when `reason` changes; `workspace_count_shortfall` → `priority/p0-critical`
- [ ] 2.10 *(no green-close step — a green run files nothing and closes nothing)*
- [ ] 2.11 Add the `notify-ops-email` step for `drift` and `readiness` only; record its outcome in
      the issue body; add `RESEND_API_KEY` to the `Verify required secrets present` guard
- [ ] 2.12 Add the Sentry check-in step last: `always()`, `continue-on-error: true`, the literal
      producer-status-first `status:` expression from the plan
- [ ] 2.13 Re-run Phase 1's suite until green
- [ ] 2.14 Re-run `workspaces-luks-freeze.test.sh`, `luks-monitor.test.sh` and
      `workspaces-luks-header.test.sh` — AC7, AC10, case (y) and H15b/H20 must all still pass
- [ ] 2.15 `bash scripts/lint-workflows.sh` exits 0

## Phase 3 — Sentry monitor + vendor expense

- [ ] 3.1 Add `resource "sentry_cron_monitor" "workspaces_luks_verify"` to
      `apps/web-platform/infra/sentry/cron-monitors.tf` (`name = "workspaces-luks-verify"`,
      `crontab = "41 4 * * *"`, `checkin_margin_minutes = 420`, `failure_issue_threshold = 2`, `max_runtime_minutes = 20`),
      with a comment giving the three absence modes it covers, why BOTH the margin and the threshold
      depart from convention (cite #4189 — they only work as a pair), and the #3958
      silent-deactivation residual
- [ ] 3.2 `bash apps/web-platform/infra/run-registered-suites.sh --list` shows the new suite
- [ ] 3.3 Run `sentry-monitor-iac-parity.test.ts` — auto-discovers the new slug, fails if the TF resource is absent (no edit to the test)
- [ ] 3.4 Run the sentry-root plan; confirm **zero destroys / zero replaces**
- [ ] 3.5 Update the `knowledge-base/operations/expenses.md` Sentry Team row (+1 cron-monitor seat,
      +$0.78/mo) using the Phase 0.7 live figure — `wg-record-recurring-vendor-expense-before-ready`

## Phase 4 — Documentation truth-maintenance

- [ ] 4.1 ADR-033 anti-circularity addendum (no new ordinal)
- [ ] 4.2 `model.c4` `github -> sentry` edge — **remove** the hand-maintained counts; add
      `workspaces-luks-verify` to the named GHA-`schedule:`-fired list; run the C4 validation tests
- [ ] 4.3 Article 30 register PA-1(g)(17) + PA-2(g)(21) — record the daily scheduled verification,
      name the durable evidence query, replace run `30130277489` with `30749271370`
- [ ] 4.4 Counsel audit: annotate the `claim_decay_trigger` frontmatter field; correct §A3.4
      recommendation 2 to state the schedule does **not** retire the heartbeat requirement.
      Disposition unchanged
- [ ] 4.5 Runbook `workspaces-luks-cutover-6604.md` §5 — extend the existing verdict table with an
      `outcome_class` column; note the check is now daily-automatic; give
      `workspace_count_shortfall` a terminal action that names a recipient and a recovery source;
      add an escalation row for a sustained bridge outage
- [ ] 4.6 File the cf-tunnel-ssh-bridge host-key TOFU tracking issue (NOT #5914 — different surface);
      link it from the plan's Encryption Posture exception row and the workflow header
- [ ] 4.7 *(no follow-through enrolment — no soak-gated close criterion is declared)*

## Phase 5 — Verification

- [ ] 5.1 `bash apps/web-platform/infra/run-registered-suites.sh` — full infra suite
- [ ] 5.2 `bash scripts/test-all.sh`
- [ ] 5.3 Walk every Acceptance Criterion, running its literal command
- [ ] 5.4 Verify every `knowledge-base/` citation in the plan resolves
- [ ] 5.5 PR body uses `Ref #6808`, never `Closes`; includes the one-line note that this converts 8
      lifetime operator-initiated root SSH sessions into ~365/yr unattended ones

## Post-merge (`/soleur:postmerge`, automated)

- [ ] P.1 `gh workflow run workspaces-luks-verify.yml -f alarm_selftest=true`; confirm the
      `[ci/luks-verify] SELF-TEST — ignore` issue is filed; close it. This is the only execution of
      the alarm path against real GHA expression evaluation before a genuine failure
- [ ] P.2 After the next 04:41 UTC: `gh run list --workflow=workspaces-luks-verify.yml
      --event=schedule --limit 3` shows `conclusion=success`, and the Sentry monitor shows a check-in
