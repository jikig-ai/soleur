---
feature: lint-bot-statuses-required-promotion
issue: 6882
pr: 6883
branch: feat-lint-bot-statuses-required-promotion
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-23-lint-bot-statuses-required-promotion-brainstorm.md
status: draft
date: 2026-07-23
---

# Spec: promote the credential-path guard to a blocking required check

## Problem Statement

`scripts/lint-credential-path-literals.py` is the regression guard for a realized credential-leak
class: a tracked doc containing a home-relative resolvable path to a real credential file causes
Claude Code's harness to auto-attach that file into model context, which previously read a live
`dp.ct.*` Doppler token into session transcripts.

The guard runs today inside the `lint-bot-statuses` ci.yml job, but that job is absent from
`scripts/required-checks.txt` and from the CI Required ruleset. A PR can therefore merge with it
red. The guard is advisory, and an advisory gate on a previously-realized leak vector is no gate.

Promotion is not mechanical. `scripts/required-checks.txt` is the SSOT from which
`.github/actions/bot-pr-with-synthetic-checks` derives `CHECK_NAMES` and posts an **unconditional
green** synthetic check-run for every listed name. Naively listing a content-scoped gate fabricates
a pass on exactly the PRs the gate cannot inspect.

## Goals

- G1. Make the credential-path guard genuinely blocking on human PRs.
- G2. Ensure the bot-PR synthetic green for that guard is **earned**, not fabricated.
- G3. Do not change the enforcement level of any other check in the `lint-bot-statuses` bundle.
- G4. Leave the required-check drift chain (SSOT ↔ canonical JSON ↔ Terraform ↔ parity test)
  internally consistent at every commit that lands on `main`.

## Non-Goals

- NG1. Promoting `lint-trap-tempfile-ownership.py`. ADR-129 declares it advisory-by-design and
  names promotion a separate deliberate follow-up; #6752 tracks three open sites.
- NG2. Promoting `lint-orphan-test-suites.sh`. It carries a live carve-out (#6751).
- NG3. Promoting `lint-infra-no-human-steps.py`. It has 475 full-scan violations and can only
  run in changed-files mode; its promotion is a separate decision with its own drain prerequisite.
- NG4. Draining the 475 `lint-infra-no-human-steps` violations.
- NG5. Changing `ALLOWED_PATHS` in the bot composite action.
- NG6. Any change to the CLA Required ruleset.

## Functional Requirements

- **FR1.** Extract the credential-path step out of `lint-bot-statuses` into a new always-run
  `ci.yml` job named `credential-path-guard`. It must not gate on `github.event_name`, so it
  reports on `pull_request` **and** `merge_group` (a required context that does not report on
  `merge_group` stalls the queue entry forever).
- **FR2.** The new job invokes the linter in **full-scan** mode
  (`python3 scripts/lint-credential-path-literals.py`, no `--changed`/`--base`). Verified green on
  this branch: `OK: no resolvable credential-file path literals in 7450 scanned file(s)`, exit 0.
- **FR3.** `lint-bot-statuses` retains its remaining six steps unchanged and remains advisory
  (absent from the SSOT and the ruleset).
- **FR4.** Add a Phase-4 "Secret-safety ceiling" step to
  `.github/actions/bot-pr-with-synthetic-checks/action.yml` that runs the credential linter over
  the staged paths before the PR is opened, and fails loud on a non-zero exit — no branch pushed,
  no PR, no synthetics. Mirror the existing earned-green `gitleaks` / `lint-fixture-content` steps.
  The linter accepts explicit positional paths, so this takes the form
  `python3 scripts/lint-credential-path-literals.py "${PATHS[@]}"`.
- **FR5.** Register `credential-path-guard` as a required context in all three SSOT artifacts:
  `scripts/required-checks.txt` (CI Required section), the canonical JSON
  (`{"context": "credential-path-guard", "integration_id": 15368}`), and a `required_check` block
  in `infra/github/ruleset-ci-required.tf`.
- **FR6.** The comment accompanying the new SSOT entry must state that the green is **EARNED**
  (by FR4), explicitly distinguishing it from the FABRICATED-NOT-EARNED entries (`rule-body-lint`,
  `sentry-destroy-required`) whose soundness rests on `ALLOWED_PATHS` unreachability.
- **FR7.** Update the stale header comment in `infra/github/ruleset-ci-required.tf` recording the
  required-context count.

## Technical Requirements

- **TR1.** All FR5 artifacts land in **one PR**.
  `plugins/soleur/test/required-checks-canonical-parity.test.sh` Test 1 asserts set equality
  file-vs-file between the SSOT's CI subset and the canonical JSON's `integration_id == 15368`
  contexts (⊆ and ⊇), so updating any one alone goes red immediately. There is no safe staging.
- **TR2.** FR4 must not merge after FR5. If the name enters the SSOT first, every bot PR in that
  window ships a fabricated green over the guarded surface.
- **TR3.** The job `name:` is public ABI in three files (ADR-032 Sharp Edge 1). A later rename
  silently un-requires the check with no CI signal, so any rename must carry a paired Terraform
  and canonical-JSON edit in the same PR.
- **TR4.** The Terraform apply happens on merge via `apply-github-infra.yml`; the ruleset must not
  require the context before the job exists on `main`, or every PR blocks on a context nobody posts.
- **TR5.** No edit needed to `scripts/create-ci-required-ruleset.sh`,
  `scripts/update-ci-required-ruleset.sh`, or
  `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts` — all three read the
  canonical JSON at runtime rather than hardcoding the set. Re-confirm during implementation.
- **TR6.** Current counts to preserve consistency against: `required-checks.txt` 21 names
  (19 CI + 2 CLA); canonical JSON 20 contexts (19 × 15368 + `CodeQL` × 57789); Terraform 20
  `required_check` blocks. Promotion takes these to 22 / 21 / 21.
- **TR7.** Confirm full-scan wall-clock on the hosted runner is acceptable before marking ready.

## Acceptance Criteria

Mapped to the three checkboxes on #6882.

- **AC1** (issue item 1 — the decision). Resolved: reproduce the scan in the composite action's
  preflight (FR4). The `integration_id` alternative is rejected — Actions always report as 15368,
  so requiring another producer deadlocks bot PRs rather than excluding them from synthesis.
  Recorded with rationale in the brainstorm and in the ADR (AC5).
- **AC2** (issue item 2 — the promotion). `credential-path-guard` present in all three SSOT
  artifacts; the parity test passes; a PR that introduces a hard-fail credential path cannot merge.
- **AC3** (issue item 3 — the bot-PR audit). Both callers of the composite action
  (`.github/workflows/weakness-miner.yml`, `.github/workflows/rule-metrics-aggregate.yml`) verified
  to route through it, so FR4 covers both. Verified that no workflow hand-rolls a synthetic
  check-run POST — the only other `check-runs` reference (`web-platform-release.yml`) is a read.
- **AC4.** `lint-bot-statuses` remains advisory; #6752 and #6751 do not become merge blockers.
- **AC5.** An ADR records the general rule: a content-scoped gate may rely on the
  fabricated-but-unreachable argument **only** where `ALLOWED_PATHS ∩ SCAN_DIRS = ∅`, and that
  intersection must be re-derived — not inherited — for each new gate. Note explicitly that
  reachability can also change via a *generator output-format* change, which the existing
  `ALLOWED_PATHS` tripwires do not watch.
- **AC6.** A `knowledge-base/legal/compliance-posture.md` ledger entry records the incident and the
  advisory→blocking upgrade as Art. 32(1)(d) evidence (testing and evaluating the effectiveness of
  a technical measure). No Article 30 amendment required.

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Name lands in SSOT before the preflight exists → fabricated greens in the window | TR2: single PR, preflight first in review order |
| R2 | Ruleset requires a context the job does not yet post → all PRs block | TR4: job ships in the same PR; apply runs on merge |
| R3 | Full-scan surfaces a violation introduced between now and merge | Full scan verified green today; re-run in CI on every push |
| R4 | Future job rename silently un-requires the gate | TR3; ADR-032 contract restated in the ADR |
| R5 | Later change to `weakness-miner.sh` output makes the surface materially reachable | FR4 makes the green earned regardless of generator format — this risk is retired, not tracked |

## Out of Scope / Follow-ups

- Draining the 475 `lint-infra-no-human-steps` full-scan violations, which is the prerequisite for
  ever promoting that guard in full-scan mode.
- Promoting the remaining `lint-bot-statuses` steps (tracked by ADR-129 / #6752 / #6751).
