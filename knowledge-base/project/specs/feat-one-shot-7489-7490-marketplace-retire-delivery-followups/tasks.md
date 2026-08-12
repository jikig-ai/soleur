---
title: "Tasks — legacy-marketplace decision and post-delivery follow-ups"
date: 2026-08-12
branch: feat-one-shot-7489-7490-marketplace-retire-delivery-followups
plan: knowledge-base/project/plans/2026-08-12-chore-legacy-marketplace-decision-and-delivery-followups-plan.md
lane: cross-domain
closes: [7489, 7490]
---

# Tasks

Derived from the plan after review. Phase ordering is load-bearing: the probe precedes any arm
execution (or its pre-state evidence is destroyed by the thing it evidences), Phase 2 precedes Phase 3
(Phase 3 presents Phase 2's verdicts and withdraws falsified arms), and the canary's integration shape
is settled before its script is written.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm the plan's live-state readings still hold before acting on them: the legacy install's
  `projectPath`, both registration sites, and the `pluginUsage` split. Plan-time facts about a live
  machine are stale by definition; abort and re-plan if they have drifted.
- [ ] 0.2 Re-run the timeout instrument control (`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=1`) on the CLI
  version under test and record the version.
- [ ] 0.3 Confirm `scripts/marketplace-drift-check.test.sh` passes on `origin/main` so any later failure
  is attributable to this change.

## Phase 1 — Legacy-resolver probe and pre-state reading

- [ ] 1.1 Write `scripts/plugin-legacy-resolver-probe.sh` against Guard 2's Assembly: settings
  precedence chain (not a frozen site list), two-stage predicate (`source.repo` at registration sites,
  then an alias join for `installed_plugins.json` and `enabledPlugins`), unresolvable alias reported as
  explicit unknown, site **list** with per-site resolved path and read status, `--json` mode.
- [ ] 1.2 Write `scripts/plugin-legacy-resolver-probe.test.sh` with all five Guard 2 mutation rows as
  named cases against synthesized `HOME` fixtures. Fixtures are synthesized, never copied.
- [ ] 1.3 Register both suites in `scripts/test-all.sh` with explicit `run_suite` lines.
- [ ] 1.4 Run the probe on this machine; commit the dated pre-state reading into
  `knowledge-base/project/specs/<branch>/measurements.md` with home paths and unrelated repository
  names redacted.

## Phase 2 — Environment family and destructive paths, measured

Each arm uses a scratch `HOME` and the tiny-timeout falsification instrument. Record command, CLI
version and verdict for every arm; a verdict is `measured` with a result or `unverified` with a
statement of what would verify it.

- [ ] 2.1 Control — confirm the instrument fires.
- [ ] 2.2 Claim (a): does a settings-file `env` block reach the plugin git path?
- [ ] 2.3 Claim (b): does it reach the background refresh? Backdated `lastUpdated` fixture. May land
  unverified with a statement of what would verify it; do not infer from claim (a).
- [ ] 2.4 `autoUpdate: false` — suppression, and which of the two declaration sites is authoritative.
- [ ] 2.5 `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` — does it prevent the `.bak` move on a forced
  pull failure, and can it be made persistent by whatever mechanism 2.2 established?
- [ ] 2.6 The `--sparse` re-clone hazard on an existing checkout. This is the `single-user incident`
  finding; if it cannot be reproduced, record it as unverified rather than dropping it.
- [ ] 2.7 `marketplace remove` symmetry — does removal clean both declaration sites?
- [ ] 2.8 Record the four remaining siblings from the bundle in `measurements.md`, behaviour marked
  unmeasured. They do not enter the runbook.
- [ ] 2.9 Append every reading to `measurements.md`.

## Phase 3 — The decision, recorded

- [ ] 3.1 Detect attachment (`HEADLESS_MODE`, no TTY, plan-file-path argument, one-shot context) and
  record the branch taken.
- [ ] 3.2 Compose the question with Phase 2's verdicts attached; withdraw any arm whose mechanism Phase 2
  falsified rather than offering a choice known to be inert.
- [ ] 3.3 Attached: ask once, execute the answer, record it. Arm A runs the four commands with
  `--scope project` from the install's own `projectPath`, then the orphan-cache reclaim behind the
  runbook's print-then-delete guard. Arm B writes `autoUpdate: false` to the authoritative site and
  ships the failure-mode variable if 2.5 found a persistent mechanism. Arm C writes nothing.
- [ ] 3.4 Headless: execute nothing; append the question and verdicts to
  `knowledge-base/project/specs/<branch>/decision-challenges.md`.
- [ ] 3.5 Re-run the probe and commit the post-state reading under every arm and under the headless
  branch.

## Phase 4 — Delivery canary

- [ ] 4.1 Write `scripts/plugin-delivery-canary.sh`: pinned CLI, scratch `HOME`,
  `CLAUDE_CODE_PLUGIN_PREFER_HTTPS`, then three independently observable conjuncts — completeness (set
  comparison of the delivered listing against what `main` serves, with a cardinality assertion),
  integrity (per-file digest against the reference pinned at the **delivered commit**), freshness
  (delivered commit against `main` HEAD). No metadata field participates in any verdict.
- [ ] 4.2 Determine the inherent delta between the delivered listing and the source listing once, and
  encode it as named justified exclusions rather than a tolerance.
- [ ] 4.3 Add `--self-test` (no network, no credentials) and the `compared=<N>` / `expected=<M>`
  anti-vacuity floor.
- [ ] 4.4 Add the `canary` job to `.github/workflows/scheduled-marketplace-drift.yml`:
  `permissions: contents: read`, its own `timeout-minutes`, `actions/checkout` scoped to this job only,
  findings out via sanitized job outputs.
- [ ] 4.5 Wire the verdict into the alarm — the filing step's condition and the heartbeat's status
  expression must both consider the canary job, keeping the `outcome == 'success'` conjunct that
  `scripts/marketplace-drift-check.test.sh` asserts.
- [ ] 4.6 Branch the issue title and remediation by finding class (AP-021).
- [ ] 4.7 Update the workflow header rationale for the new execution surface.
- [ ] 4.8 Extend `scripts/marketplace-drift-check.test.sh` for the new job; write
  `scripts/plugin-delivery-canary.test.sh` with all eight Guard 1 rows plus the static wiring
  assertion; register it in `scripts/test-all.sh`.

## Phase 5 — Upstream reports

- [ ] 5.1 Duplicate search using the List API plus client-side `jq` (not `--search`).
- [ ] 5.2 Compose four report bodies in `knowledge-base/project/specs/<branch>/upstream-reports.md`.
- [ ] 5.3 Scrub all four exposure categories (`/home/...` and `~` forms, unrelated repository names and
  layout, install timestamps, machine identifiers), then read back as a discrete step.
- [ ] 5.4 Route per the plan's table. On contradiction: prefer a comment on the existing issue over a
  new one, and record the contradiction and substitution.
- [ ] 5.5 Sending is operator-gated. Headless: commit the bodies, send nothing, let the follow-through
  carry the send.

## Phase 6 — Records

- [ ] 6.1 ADR-182 amendment: Context correction (pull-first), Decision 5 disposition, rejected
  retire-the-entry alternative.
- [ ] 6.2 ADR-182 Decision 6: the second control, its alternatives, its accepted risk, its #7493
  relationship.
- [ ] 6.3 `model.c4` — all three sole/only-control occurrences; preserve the five count-anchored literals
  in the `github -> sentry` edge. Regenerate and commit `model.likec4.json`; run both C4 suites.
- [ ] 6.4 Runbook Symptom 2 — the `--sparse` fresh-add versus existing-checkout distinction, plus the
  failure-mode variable as standing mitigation.
- [ ] 6.5 Runbook Symptom 1 — state that `claude plugin list --json` is a projection of
  `installed_plugins.json`; add a cross-check that does not depend on it.
- [ ] 6.6 Runbook persistence section — replace with Phase 2's labelled verdicts; add a row per canary
  finding token. If claim (a) measured false, the sanctioned replacement is that no persistent mechanism
  was found and migration is the answer.
- [ ] 6.7 Both READMEs — the same `--sparse` distinction; verify nothing states or implies a clone per
  refresh.
- [ ] 6.8 `scripts/followthroughs/plugin-delivery-canary-7490.sh` plus the tracker directive and
  `follow-through` label, `earliest` just after merge.

## Phase 7 — Acceptance

- [ ] 7.1 Walk all 28 pre-merge acceptance criteria, recording the command and its output for each.
- [ ] 7.2 `bash scripts/test-all.sh` — green, or every failure confirmed pre-existing on `origin/main`.
- [ ] 7.3 `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-infra-no-human-steps.py
  --changed --base origin/main`, `bash scripts/lint-workflows.sh`, `bash
  scripts/lint-diagnosis-claims.sh`, `bash scripts/check-adr-ordinals.sh`.
