---
title: "fix: orphan sweeps read the read-only Hetzner token only, and a red sweep reaches a person"
date: 2026-10-23
slug: orphan-sweeps-read-only-token-and-failure-email
branch: feat-one-shot-orphan-sweep-readonly-token
issue: 10664
lane: single-domain
type: fix
---

# fix: orphan sweeps read the read-only Hetzner token only, and a red sweep reaches a person

## Overview

Two jobs in `.github/workflows/scheduled-terraform-drift.yml` (`rung2-rehearsal-orphan-sweep`, `inngest-rehearsal-orphan-sweep`) list Hetzner objects with GET calls only. Today each binds the `infra-privileged` environment and runs the `infra-credentials` loader, then reads `HCLOUD_TOKEN` from the loader's export. In the Tier-B arm that name is the read/write token, so a job that only reads holds a credential able to delete. When the loader falls back (missing environment secret) the token is empty, the sweep fails red, and nothing files an issue or sends an email.

This change moves both jobs to the shape `sole-copy-protection-check` already uses on `main`: no `environment:`, no loader, a pinned Doppler CLI install, one bounded read of `HCLOUD_TOKEN_READONLY` from `soleur/prd_terraform` with the `DOPPLER_TOKEN` repository secret, no fallback to the read/write name, and a main-only job guard. Each job also gets a failure email through `notify-ops-email`, so a red sweep is a message and not only a run annotation. Code only: no Hetzner or Doppler write, no apply, no ruleset change. Tracked under #10664 (checklist item "Orphan-sweep steps keep the loader-exported token and have no notification path"); epic #9927 stays open. Ref #9927, Ref #10112.

## Research Insights

**Premise validation (2026-10-23).** #10664 is OPEN; its sibling site-C work is in draft PR #10891 on a live branch and shares no file with this change (checked: PR #10891 and #10935 file lists contain neither the drift workflow nor the token-drift suite). The CTO ruling of 2026-10-20 on PR #10652 (finding F3) deferred exactly this conversion as "a separate least-privilege change" needing "its own step-level tests". The runbook Group 3 table already lists the rung-2 sweep as "Tier after: A -> HCLOUD_TOKEN_READONLY". Cited file and symbol paths exist on `main` (workflow lines 2463 and 2887 for the two jobs; `scripts/lib/bearer-curl.sh`; `.github/actions/notify-ops-email`).

**Safety of the conversion (the "caller table shows it safe" condition).**
- Both sweeps issue only GETs against `api.hetzner.cloud` (`servers`, `volumes`, `ssh_keys`, `firewalls` by label selector, plus a servers name-prefix GET). The rung-2 sweep also runs `doppler configs list` with the Tier-A `DOPPLER_TOKEN` it already binds in its own step env. No write is executed or printed (the DELETE recipe went in #9927 item 8c).
- The Hetzner "Read" permission covers every GET listed above.
- The same secret and the same read pattern run today: `sole-copy-protection-check` finished `success` in run 39816136720 (2026-10-22, main), and that job's gate is red on any non-clean verdict, so its token read worked. Measured via `gh api .../actions/runs/39816136720/jobs`, conclusion field only.
- Project identity of the token: `sole-copy-protection-check` pins the Inngest store volume by name and Hetzner id twice a day and files or emails on `volume-not-found`, so a read-only token pointing at another project is already a paged condition. The sweeps rely on that single check and do not duplicate the pin. Residual stated plainly: a read/write token stored under the read-only name is undetectable by these readers (the O5 write-probe, last recorded 2026-09-29, is the control).

**Property List.**
1. Neither orphan-sweep job holds a credential able to write to Hetzner.
2. A sweep that cannot produce a verdict (secret read failed, API unreachable, filer failed) reaches a person without relying on someone opening the run.
3. A third `*-orphan-sweep` job added later cannot silently re-introduce the loader or the read/write name.
4. The runbook's caller table and notification-gap paragraph state the new shape.

**Cut List.** (a) A project-identity canary inside the sweeps: cut, property already bought by the sole-copy check's volume-id pin (dependency recorded above). (b) Sharing the Doppler install between jobs: cut, tracked as #10431. (c) A Sentry check-in for these jobs: cut, tracked as #10430. (d) Converting `curl` to `bc_curl` in the Inngest sweep: cut, no property bought; the shape check `bc_ok_var` is added by sourcing the library, the request lines are unchanged.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| Runbook Group 3 row for `rung2-rehearsal-orphan-sweep` says `environment:` "(none)" and credential `HCLOUD_TOKEN` | The job binds `infra-privileged` and uses the loader today | The row becomes true after this change; update credential to `HCLOUD_TOKEN_READONLY` and add the missing Inngest sweep row |
| Workflow comment at the sole-copy job (about line 1869): the two sweeps read the loader's token, "NOT provably read-only" | True today, false after this change | Rewrite the comment in the same edit |
| Runbook: "Every one of the 32 jobs that call the loader" | Two of those jobs leave the loader | Re-measure the count from census row G1j after the edit and update the dated note |
| Runbook: sweeps "have no notification path" | Becomes false | Replace with the new email path |

## Open Code-Review Overlap

None (queried the open `code-review` issues for the four planned files: no match).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Orphan-sweep steps in scheduled-terraform-drift.yml read the loader token, and there's no notify-ops-email on failure" [brief] | Phase 1 (token read) and Phase 2 (failure email) | mapped |
| 2 | "convert them to a read-only-token-only read (only once the loader contract and caller table show that is safe; verify, and if it is not provably safe, narrow the change and record why)" [brief] | Research Insights safety section; Phase 1 | mapped |
| 3 | "add a notify-ops-email step on failure so a red sweep reaches a person" [brief] | Phase 2 | mapped |
| 4 | "Code only" [brief] | Whole plan (no apply, no secret write, no dispatch) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/scheduled-terraform-drift.yml` edits | "Orphan-sweep steps in scheduled-terraform-drift.yml" | asked |
| `plugins/soleur/test/token-drift-workflow-causes.test.sh` rows | "convert them to a read-only-token-only read" (a guard the drift suite pins, per the CTO ruling that required "its own step-level tests") | asked |
| Runbook `infra-credential-tiers-8209.md` rows and paragraph | — | inferred — justification: the runbook's caller table and "no notification path" paragraph would state the old shape, and the census-adjacent docs are read by the next operator; stale rows are how this gap stayed unnoticed |
| Main-only `if:` guard on both jobs | — | inferred — justification: the dropped `infra-privileged` environment carried the `main`-only deployment policy; without a replacement a branch dispatch would read the token and file issues |
| Workflow comment rewrite near the sole-copy job | — | inferred — justification: the comment asserts the sweeps hold a non-read-only token, which this change makes false |

### Split Assessment

- Subsystems touched: 3 (workflow, plugin test suite, runbook docs)
- Planned files: 3 | Estimated changed lines: about 330
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; the sweeps are operator-facing drift detection. A broken conversion makes a sweep fail red; with the new email that is a message to ops, and a leaked Hetzner rehearsal host (a paying box) would go unreported until the run is read.

**If this leaks, the user's data / workflow / money is exposed via:** the read-only Hetzner token printed in a run log. Mitigated by per-line `::add-mask::` before first use, the shape check before any request, and no echo of API bodies. No user data is read by these jobs.

**Brand-survival threshold:** none

threshold: none, reason: the diff touches a CI workflow that reads a Read-permission infrastructure token and no user-facing surface, user data or user credentials.

## Implementation Phases

### Phase 1 — convert both sweep jobs to the Tier-A read

In `.github/workflows/scheduled-terraform-drift.yml`, for `rung2-rehearsal-orphan-sweep` and `inngest-rehearsal-orphan-sweep`:

1. Remove `environment: infra-privileged`; add `if: github.ref == 'refs/heads/main'` (hygiene, same words as the sole-copy job).
2. Replace the `infra-credentials` step with the pinned Doppler CLI install step (same release and sha256 as the sole-copy job and the loader; `timeout-minutes: 3`). Add `persist-credentials: false` and `timeout-minutes: 2` to the checkout.
3. In each sweep step, replace `TOKEN="${HCLOUD_TOKEN:-}"` and the single `::add-mask::` with: source `scripts/lib/bearer-curl.sh`; `timeout -k 5 60 doppler secrets get HCLOUD_TOKEN_READONLY --plain --project soleur --config prd_terraform` with the rc captured; rc 124 or 137 ends red with a named slug that says this is not a missing credential; mask each output line; empty value ends red; `bc_ok_var TOKEN` failure calls `bc_refuse scheduled-terraform-drift TOKEN` and ends red. Every one of those ends `exit 1`, never a clean verdict. No fallback to any other name.
4. The Inngest sweep binds `DOPPLER_TOKEN` in its step env and unsets it after the read; the rung-2 sweep keeps `DOPPLER_TOKEN` because its scratch-config probe still runs `doppler configs list`.
5. Add `timeout-minutes` to the two sweep steps (each Hetzner request keeps its existing `-f`; the rung-2 path keeps `bc_curl`'s own bounds; the Inngest path adds `--max-time 30` to its three curl calls).
6. Rewrite the stale comment block above the sole-copy job ("THE TOKEN, AND WHY THE LOADER IS NOT USED") to say the two sweeps now read the same token the same way.

### Phase 2 — failure email on both jobs

1. Rung-2 job: give the existing scratch-config email step `id: notify_channel`. Append `Email notification (rung-2 sweep — the job failed)` with `if: failure() && steps.notify_channel.outcome != 'success'`, `continue-on-error: true`, `timeout-minutes: 2`, `uses: ./.github/actions/notify-ops-email`, `resend-api-key: ${{ secrets.RESEND_API_KEY }}`. The de-duplication leg keeps one message per failed run.
2. Inngest job: append `Email notification (inngest rehearsal sweep — the job failed)` with `if: failure()`, same bounds.
3. Bodies carry run URL and step outcomes only (sweep, filer, Doppler install): no resource names, no API body, no token. Subject prefix `[INFRA DRIFT]`.

### Phase 3 — guard rows in the drift suite (written BEFORE Phase 1 edits, see Guard Contract)

Add rows R7 and R8 to `plugins/soleur/test/token-drift-workflow-causes.test.sh` with their mutation-runner verdicts, and raise the anti-vacuity floor from 172 to the realized `PASS + FAIL`, updating the comment history line and the guard literal to the same number.

### Phase 4 — docs

`knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: update the `rung2-rehearsal-orphan-sweep` row; add an `inngest-rehearsal-orphan-sweep` row; replace the "no notification path" sentence with the email path and the shared read dependency; re-measure and update the loader-job count in the dated note (run `tests/scripts/test-infra-privileged-tier-census.sh` and read the G1j bracket).

## Files to Edit

- `.github/workflows/scheduled-terraform-drift.yml`
- `plugins/soleur/test/token-drift-workflow-causes.test.sh`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-orphan-sweep-readonly-token/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-orphan-sweep-readonly-token/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-orphan-sweep-readonly-token/session-state.md`

## Guard Contract

### Guard 1 — orphan sweeps hold no read/write Hetzner credential

**Property.** No job in `scheduled-terraform-drift.yml` whose id ends in `-orphan-sweep` calls the `infra-credentials` loader, declares an `environment:`, reads a Tier-B secret name, or reads the bare `HCLOUD_TOKEN` (from the environment or from Doppler); each reads `HCLOUD_TOKEN_READONLY` from `prd_terraform` with a rc-checked, bounded call.

**Assembly.** The population is derived from the parsed workflow (every job id with the `-orphan-sweep` suffix), never a hard-coded pair; the chokepoints the property quantifies over are: job-level `environment:`, any step `uses:` of the loader, any `run:` or `env:` text naming `HCLOUD_TOKEN` as a whole word (not the `_READONLY` suffix), `DOPPLER_TOKEN_INFRA_PRIVILEGED`, and `doppler secrets get` with any name other than `HCLOUD_TOKEN_READONLY`. A floor of at least 2 jobs in the population keeps a rename from emptying it. The printed pasteable blocks in the filers are covered by existing rows R6a-c.

**Mutation matrix.**

| # | Edit (must drive R7 RED) | Targets |
|---|--------------------------|---------|
| 1 | Re-add the `infra-credentials` loader step to the Inngest sweep | loader chokepoint |
| 2 | Re-add `environment: infra-privileged` to the rung-2 sweep | environment chokepoint |
| 3 | Change one sweep's read to `doppler secrets get HCLOUD_TOKEN` (bare name) | name chokepoint, whole-word test |
| 4 | Add a THIRD job `rehearsal-x-orphan-sweep` with the loader after the two compliant ones | second member after a compliant first; population is derived |
| 5 | Rename both jobs so none ends in `-orphan-sweep` | the guard's own dispatch (population 0 must be RED, not "0 checked, green") |
| 6 | Re-introduce `TOKEN="${HCLOUD_TOKEN:-}"` in one sweep step | env-read chokepoint |
| 7 | Remove the `|| doppler_rc=$?` capture so a failed read aborts unnamed | rc-checked read |

**Harness rows.** (H1) Replace the guard's population selector with `jobs[:1]` in the mutation copy of the suite: the suite must go RED on the second member (a check that stops at the first member is the class). (H2) A must-PASS non-canonical input: a sweep job whose read spells `--config prd_terraform --project soleur` in swapped order and masks with a different loop variable name, which the contract permits, must stay GREEN. The existing late-dispatch re-validation covers a neutered `pass()`/`fail()`.

**Anchor.** No stored value is compared; the guard reads the same file it judges. The independent anchor for "the token is really read-only" is the O5 write-probe (owner action, last recorded 2026-09-29, not re-run here); stated as a residual in the PR body.

### Guard 2 — every sweep job emails on failure

**Property.** Each `-orphan-sweep` job has a step using `./.github/actions/notify-ops-email` whose `if:` contains `failure()`, is `continue-on-error: true`, and is bounded by `timeout-minutes`; the rung-2 job's email is de-duplicated against its existing email step.

**Assembly.** Same derived population; chokepoints: step `uses:`, `if:` text, `continue-on-error`, `timeout-minutes` on that step.

**Mutation matrix.**

| # | Edit (must drive R8 RED) | Targets |
|---|--------------------------|---------|
| 1 | Delete the email step from the Inngest sweep | presence |
| 2 | Change a sweep email's `if:` to `success()` | polarity |
| 3 | Change a sweep email's `if:` to `always()` (mails every run) | spam polarity |
| 4 | Remove `continue-on-error` from the email step | must-not-fail-the-job |
| 5 | Add a third `-orphan-sweep` job without an email step | second member after compliant first |

**Harness rows.** (H3) The rung-2 email with the de-duplication leg spelled differently (`steps.notify_channel.outcome == 'skipped'` plus `'failure'` legs) must stay GREEN (must-PASS non-canonical). (H4) A mutation copy where the email step's `uses:` points at a different action must be RED.

**Anchor.** None stored; consistency of the file against itself is the property.

## Observability

```yaml
liveness_signal:
  what: the twice-daily dispatched drift run completes with both sweep jobs green (a clean sweep) or red plus an email
  cadence: twice daily (Inngest-dispatched, ADR-033)
  alert_target: ops@jikigai.com via notify-ops-email; GitHub issue under the infra-drift label for orphans
  configured_in: .github/workflows/scheduled-terraform-drift.yml (the two new email steps)
error_reporting:
  destination: email (Resend) and the run's named ::error:: annotation
  fail_loud: true
failure_modes:
  - mode: secret read times out, is empty, or fails the shape check
    detection: named ::error:: slug, job red
    alert_route: failure email
  - mode: Hetzner API unreachable or listing paginated beyond page 1
    detection: existing fail-closed ::error::, job red
    alert_route: failure email
  - mode: issue filer cannot create or comment
    detection: filer step failure makes the job red
    alert_route: failure email
  - mode: the email channel itself fails
    detection: continue-on-error step; its failure is visible in the run only
    alert_route: none (stated residual; tracked with #10430, the missing Sentry check-in)
logs:
  where: GitHub Actions run log
  retention: repository default (90 days)
discoverability_test:
  command: grep -cE 'name: Email notification \(.*sweep — the job failed\)' .github/workflows/scheduled-terraform-drift.yml
  expected_output: "2"
```

## Acceptance Criteria

- [ ] Neither sweep job contains `environment:`, the loader `uses:` line, `HCLOUD_TOKEN` as a whole word, or `DOPPLER_TOKEN_INFRA_PRIVILEGED`: `python3` parse of the workflow and the suite's R7 row print PASS.
- [ ] Both sweep steps read `HCLOUD_TOKEN_READONLY` with `timeout -k 5 60`, rc captured, per-line mask, empty and shape refusals exit 1: R7 PASS and the suite's named-slug assertions.
- [ ] Both jobs carry the main-only `if:` and a bounded checkout, Doppler install and sweep step.
- [ ] Each job has one `notify-ops-email` step gated on `failure()` with `continue-on-error: true` and `timeout-minutes`: R8 PASS; the rung-2 job sends at most one email per failed run.
- [ ] `bash plugins/soleur/test/token-drift-workflow-causes.test.sh` exits 0 with the raised floor equal to the realized `PASS + FAIL` (comment and guard literal agree), and every mutation row in both matrices reports RED.
- [ ] `bash plugins/soleur/test/terraform-drift-step-order.test.sh`, `bash plugins/soleur/test/sole-copy-drift-check.test.sh`, `bash plugins/soleur/test/terraform-drift-sentry-leg.test.sh`, `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh`, `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh` exit 0 (G1j shows a loader-job count two lower than before).
- [ ] The runbook rows, the count note and the notification paragraph state the new shape; the comment above the sole-copy job no longer says the sweeps hold a non-read-only token.
- [ ] `actionlint` (or the repo's workflow lint) is clean on the edited file.
- [ ] PR body states what was measured (run 39816136720 job conclusions on 2026-10-22; census G1j count before and after; suite results) and what was not (no live run of the converted jobs before merge; the O5 write-probe not re-run; no dispatch). Uses `Ref #10664`-free wording per the brief: `Ref #9927` and `Ref #10112` only, no closing keyword anywhere.

## Test Scenarios

1. Parse and lint: edited workflow parses, jobs list unchanged, step ids unique.
2. Mutation runner: each row in both matrices applied to a temp copy, suite goes RED, original goes GREEN.
3. Census: G1j count before vs after the edit.
4. Post-merge (read-only, by the pipeline's postmerge step): `gh workflow run` is NOT used here; the next dispatched run's two sweep jobs conclude `success` (read their conclusions with `gh api .../jobs`). Recorded as a dated follow-through in the PR body, not as a gate.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Sharp Edges

- `HCLOUD_TOKEN` is a prefix of `HCLOUD_TOKEN_READONLY`: every test and grep for the bare name must be word-bounded.
- `failure()` is also true when an upstream install step fails; that is intended.
- The rung-2 job still needs `DOPPLER_TOKEN` after the token read (scratch-config probe); do not unset it there.
- A job skipped by the main-only `if:` sends nothing; a branch dispatch of the workflow is expected to skip both sweeps.
- The floor in the drift suite must be edited in the comment history and the guard literal together.
