---
type: ops-hardening
classification: ci-cron-workflow
issue: 3544
parent: 3542
origin: 2719
requires_cpo_signoff: true
brand_survival_threshold: single-user-incident
---

# Periodic Audit of CI Required Ruleset `bypass_actors` (R15 follow-up D1)

## Overview

Add a daily scheduled GitHub Actions workflow that compares the live `bypass_actors`
of the `CI Required` ruleset (#14145388) on `jikig-ai/soleur` against a
canonical, in-repo expected set. On any drift (additions, removals, mode
changes, scope-broadening edits), the workflow files a `compliance/critical`
GitHub issue routed to ops + CPO and emails ops via `notify-ops-email`.

This closes the audit gap noted in #3542 R15 mitigation: the destructive
`scripts/update-ci-required-ruleset.sh` PUT copies `bypass_actors` verbatim
from the live snapshot, so an admin who broadens bypass between two PUTs
leaves no repo-side trace -- GitHub's audit log is the only surface. A
hourly/daily compare-and-alert closes that gap with a single-day worst-case
detection window.

## User-Brand Impact

**If this lands broken, the user experiences:** No direct user impact (operator-facing
audit). However, "broken" here = false negatives: drift goes undetected, an
attacker-broadened `bypass_actors` lets a malicious PR ship without the
`skill-security-scan PR gate` ever running, and a single skill-install
incident becomes the brand-ending event #2719 was filed to prevent.

**If this leaks, the user's data/workflow is exposed via:** A widened
`bypass_actors` entry allows admin-merge bypassing R15 (the
`skill-security-scan PR gate` required check). One malicious skill merge
under bypass = installable-skill code-execution on any operator who pulls.
The bypass surface IS the threat surface for the EU `single-user incident`
threshold from #2719/#3542.

**Brand-survival threshold:** single-user incident (carried forward from the
parent R15 brainstorm/plan; verified via #3543's frontmatter and
`compliance-posture.md` `#2719` row).

## Research Reconciliation -- Spec vs. Codebase

| Spec / Issue claim | Reality | Plan response |
|---|---|---|
| "daily cron" (issue #3544 Goal) | No frequency floor stated; #3543 plan §592 implies admin edits are vanishingly rare in solo-operator setup; aggregate-pattern detection ≠ single-incident | Adopt 1/day at 06:00 UTC. Mirrors `scheduled-github-app-drift-guard.yml` cadence philosophy (hourly there because auth-broken is single-incident; ours is aggregate but with single-incident downstream) -- daily is the right floor; document re-evaluation in scope-out criteria |
| "post a `compliance/critical` issue if … drifts" (issue) | `compliance/critical` label exists (`B60205`, `gh label list` verified); used by gdpr-gate + vendor-pin-drift workflows | Use the existing label; do NOT create new |
| "canonical config" location unspecified | `scripts/create-ci-required-ruleset.sh:80-95` already contains the canonical 2-entry list (`OrganizationAdmin` + `RepositoryRole id=5`, both `pull_request` mode); live state matches verbatim | Source-of-truth = a new `scripts/ci-required-ruleset-canonical-bypass-actors.json` file checked in; both `create-ci-required-ruleset.sh` and the new audit workflow read from it. Avoids duplicating the array in YAML + bash |
| #3543 R15 noted bypass_actors "verbatim from live" | Confirmed: `update-ci-required-ruleset.sh:120` copies `before` array unchanged into the PUT payload | This audit is the missing trust-loop closer -- the update script's "copy verbatim" is intentional and stays as-is; the audit is what verifies the live state IS the canonical state at periodic intervals |
| `OrganizationAdmin` `actor_id: null` (canonical) | Live API returns `actor_id: null` for `OrganizationAdmin` (verified via `gh api .../rulesets/14145388 --jq '.bypass_actors'`) | Canonical JSON file uses `actor_id: null` for the org-admin row; comparison must handle JSON null vs missing key |

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open` against
the planned files (`scripts/update-ci-required-ruleset.sh`,
`scripts/required-checks.txt`, `knowledge-base/legal/compliance-posture.md`).

## Hypotheses

N/A -- no network/connectivity symptom in scope.

## Functional Overlap

No existing scheduled workflow audits ruleset `bypass_actors`. The closest
sibling is `.github/workflows/scheduled-github-app-drift-guard.yml` (audits
GitHub App identity drift, not ruleset drift); pattern is reused
mechanically but the audit target is distinct. The `lint-bot-statuses.yml`
workflow audits bot-PR synthetic-check coverage, not ruleset bypass
authorities. No overlap; greenfield.

## Files to Create

1. `.github/workflows/scheduled-ruleset-bypass-audit.yml` -- daily cron
   workflow. Fetches live ruleset, diffs against canonical, files or
   updates a `compliance/critical` tracking issue on drift, auto-closes
   stale tracking issues when drift recovers. Mirrors structure of
   `scheduled-github-app-drift-guard.yml` (3-output failure routing,
   strip_log_injection, runbook-linked body, notify-ops-email step,
   issue-create-or-comment pattern, green auto-close).

2. `scripts/ci-required-ruleset-canonical-bypass-actors.json` -- source-of-truth
   JSON array. Two entries verbatim from the live ruleset:
   `OrganizationAdmin / null / pull_request` and `RepositoryRole / 5 /
   pull_request`. Committed; never edited without an accompanying
   `compliance-posture.md` row.

3. `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md` -- operator
   runbook for the three failure routes: `ci/auth-broken` (drift detected --
   investigate audit log, restore canonical via update-ci-required-ruleset.sh
   PUT-cycle, log to compliance-posture.md), `ci/guard-broken` (audit itself
   malfunctioned -- API rate-limit, JSON parse, token absence), and the
   green-recovery procedure.

4. `knowledge-base/project/learnings/best-practices/2026-05-11-ruleset-bypass-audit-canonical-vs-live-comparison.md`
   -- a short learning on JSON-array-set-equality semantics when comparing
   GitHub Ruleset `bypass_actors` (order-insensitive, key-canonical) and the
   `null`-actor_id vs missing-key trap. Date deferred to write time per
   sharp-edge convention.

## Files to Edit

1. `scripts/create-ci-required-ruleset.sh` -- replace the inline
   `bypass_actors` literal with a `jq` injection from
   `scripts/ci-required-ruleset-canonical-bypass-actors.json` so the
   creation script and audit workflow share a single source of truth.
   Preserves R10 (Sharp Edge: "JSON payload via heredoc into a file, then
   `--input "$payload"`") and keeps the script idempotent.

2. `scripts/update-ci-required-ruleset.sh` -- add a post-PUT verification
   step that asserts the round-tripped `bypass_actors` exactly matches the
   canonical JSON, not just the pre-mutation snapshot. This is the audit's
   "fast path" -- if R15 mitigation re-PUTs ever happen, the verification
   fires the same diff logic the cron audit uses, blocking the apply on
   drift instead of waiting up to 24h.

3. `knowledge-base/legal/compliance-posture.md` -- amend the `#2719` row to
   note "Daily audit (#3544) compares live bypass_actors to
   `scripts/ci-required-ruleset-canonical-bypass-actors.json`; drift
   auto-files `compliance/critical` issue." `last_updated:` bumps to
   2026-05-11.

4. `scripts/required-checks.txt` -- add a comment block noting that the
   `bypass_actors` for the CI Required ruleset are canonicalized in
   `scripts/ci-required-ruleset-canonical-bypass-actors.json` (operator
   discoverability -- one file for required checks, an adjacent file for
   bypass authorities).

## Implementation Phases

### Phase 0 -- Preflight (no writes)

0.1 Verify label `compliance/critical` exists on `jikig-ai/soleur`:
    `gh label list --limit 200 | grep -E '^compliance/critical\b'`. Already
    verified at plan time; re-verify at /work entry.

0.2 Verify label `ci/auth-broken` and `ci/guard-broken` exist (defensively
    created by `scheduled-github-app-drift-guard.yml`). Already verified.

0.3 Capture live `bypass_actors` JSON to disk for canonical-JSON authorship:
    `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.bypass_actors' > /tmp/live-bypass.json`.

0.4 Capture live ruleset full state (id, target, enforcement, conditions,
    rules) for diff-vs-canonical verification at smoke time:
    `gh api repos/jikig-ai/soleur/rulesets/14145388 > /tmp/live-ruleset.json`.

### Phase 1 -- Canonical JSON + script refactor (contract-changing edits FIRST)

Per Sharp Edge #2026-05-10-plan-phase-order: contract-changing edits ship
**before** the consumer (the audit workflow).

1.1 Create `scripts/ci-required-ruleset-canonical-bypass-actors.json` with
    the 2-entry array. Verbatim from live (verified `actor_id: null` vs
    missing-key semantics: GitHub returns explicit `null` for
    `OrganizationAdmin`, so the canonical file MUST use `null`, not omit).

1.2 Refactor `scripts/create-ci-required-ruleset.sh` to inject
    `bypass_actors` from the JSON file via `jq --slurpfile`. The full
    payload is still built via heredoc-then-`--input` (R10 Sharp Edge).
    Test: `bash scripts/create-ci-required-ruleset.sh` against a fake
    ruleset name (or `--dry-run` if available; otherwise dry-test the
    payload assembly with `--print-payload` flag added in this phase).

1.3 Extend `scripts/update-ci-required-ruleset.sh` post-PUT verification to
    diff the round-tripped `bypass_actors` against the canonical JSON
    file (existing logic only diffs against the pre-mutation snapshot).
    On mismatch -> exit 2 (rollback-required), matching existing exit-code
    semantics.

### Phase 2 -- The audit workflow (consumer)

2.1 Create `.github/workflows/scheduled-ruleset-bypass-audit.yml` with this
    structure (mirrors `scheduled-github-app-drift-guard.yml`):

    - **Name:** `Scheduled: Ruleset Bypass Audit`
    - **Trigger:** `schedule: - cron: '0 6 * * *'` (06:00 UTC daily, off-peak
      relative to other crons; `workflow_dispatch:` for manual runs).
    - **Concurrency:** `group: scheduled-ruleset-bypass-audit`,
      `cancel-in-progress: false`.
    - **Permissions:** `contents: read, issues: write`.
    - **Repo guard:** `if: github.repository == 'jikig-ai/soleur'`.
    - **Timeout:** `timeout-minutes: 5`.

    Step 1 -- Checkout (sparse for `scripts/` + `.github/actions/notify-ops-email`).

    Step 2 -- Defensively create `compliance/critical`, `ci/auth-broken`,
    `ci/guard-broken` labels (defensive mirror of drift-guard yaml:65-76).

    Step 3 (id: `check`) -- Audit script body. NOT `set -e` (collect failure
    modes -> outputs, per drift-guard's 3-output model). Capture
    step output via `exec > >(tee -a "$RUNNER_TEMP/step-output.log") 2>&1`
    for the leak tripwire (see Step 4).

    - Fetch live ruleset:
      `curl -s --max-time 15 -H 'Authorization: Bearer $GH_TOKEN' -H 'Accept: application/vnd.github+json' https://api.github.com/repos/jikig-ai/soleur/rulesets/14145388 -o $LIVE_FILE -w '%{http_code}'`
      (use curl over `gh api` for `--max-time` -- aligns with Sharp Edge
      "pin a timeout on dig/curl in CI"; `gh api` lacks `--max-time`).
    - Failure modes (each routes via `record_failure`):
      - `github_api_network` (curl error) -> `ci/guard-broken`
      - `github_api_http != 200` -> `ci/guard-broken`
      - `github_api_invalid_json` -> `ci/guard-broken`
      - `live_missing_bypass_actors` (jq returns null) -> `ci/guard-broken`
      - `canonical_file_missing` -> `ci/guard-broken`
      - `bypass_actors_drift` -> `ci/auth-broken` (the load-bearing detection)

    - **Drift detection (the heart of the audit):**

      ```bash
      # jq array-of-objects set equality.
      # Sort by (actor_type, actor_id, bypass_mode) for stable comparison.
      # Use --slurpfile so jq sees a single array; --argjson would re-parse.
      live_sorted=$(jq -c 'sort_by(.actor_type, (.actor_id // "null" | tostring), .bypass_mode)' "$LIVE_BYPASS_FILE")
      canonical_sorted=$(jq -c 'sort_by(.actor_type, (.actor_id // "null" | tostring), .bypass_mode)' "$CANONICAL_FILE")
      if [[ "$live_sorted" != "$canonical_sorted" ]]; then
        record_failure "bypass_actors_drift" \
          "live=${live_sorted}; canonical=${canonical_sorted}" \
          "ci/auth-broken"
      fi
      ```

    - Sanitize `failure_mode`, `failure_detail`, `failure_label` via the
      drift-guard's `strip_log_injection` helper (CRLF + U+0085 + U+2028 +
      U+2029 stripped via `tr` + `sed`). Echo `key=value` to
      `$GITHUB_OUTPUT` only after sanitation -- Sharp Edge
      `cq-regex-unicode-separators-escape-only` plus the
      log-injection-into-annotations bullet in the plan SKILL Sharp Edges.

    Step 4 (id: `tripwire`) -- Lightweight leak tripwire. Audit doesn't mint
    JWTs, so the only credential surface is `$GH_TOKEN`. Tripwire is just:
    `grep -v '^::' "$RUNNER_TEMP/step-output.log" | grep -E 'gh[opsu]_[A-Za-z0-9]{36}|ghp_[A-Za-z0-9]{36}|github_pat_'` -- if a token shape appears in step output (which would only happen via an `echo "$GH_TOKEN"` misuse), file a `security/leak-suspected` issue. Lightweight but not zero (defense-in-depth).

    Step 5 -- File or comment on tracking issue (failure):

    - Title routing by `failure_label`:
      - `ci/auth-broken` -> `[compliance/critical] CI Required ruleset bypass_actors drift detected`
      - `ci/guard-broken` -> `[ci/guard-broken] Ruleset bypass audit malfunctioned`
    - Labels: `compliance/critical` (for `ci/auth-broken` only),
      `ci/auth-broken` OR `ci/guard-broken`, `priority/p1-high`,
      `domain/legal` (for `ci/auth-broken` -- routes to CLO triage).
    - Body: failure_mode, failure_detail, run URL, link to runbook,
      reference to #2719 and #3542.
    - **De-dupe:** search existing open issues with the same label +
      `in:title "bypass audit"` and comment rather than file again
      (mirror drift-guard yaml:401-411).

    Step 6 -- `notify-ops-email` action (with `continue-on-error: true`):
    subject mirrors failure_mode; body includes failure_label and run URL.

    Step 7 -- Auto-close stale tracking issue when audit green:
    `if: steps.check.outputs.failure_mode == ''` -- close any open
    `[compliance/critical]` OR `[ci/guard-broken]` audit tracking issue
    with a "audit green at $NOW" comment.

2.2 Lint the new YAML:
    - `yamllint .github/workflows/scheduled-ruleset-bypass-audit.yml`
    - `actionlint -no-color .github/workflows/scheduled-ruleset-bypass-audit.yml`
    - Embedded shell smoke: `bash -c "$(yq '.jobs.audit.steps[2].run' .github/workflows/scheduled-ruleset-bypass-audit.yml)" --dry-run` is infeasible because the script depends on `$GH_TOKEN`, `$RUNNER_TEMP`, `$LIVE_FILE`. Instead: shellcheck the inline `run:` block via `actionlint`'s shellcheck integration (default-on); verify by running `actionlint -shellcheck=` with verbose output. Per Sharp Edge #2026-05-11-multi-word-required-check: NEVER `bash -n` on the YAML.

2.3 Run the workflow once via `gh workflow run scheduled-ruleset-bypass-audit.yml --ref feat-one-shot-3544-bypass-actors-audit`. **EXPECT FAILURE** at this step -- the workflow file must exist on the default branch for `workflow_dispatch` to dispatch (per Sharp Edge `2026-04-21-workflow-dispatch-requires-default-branch.md`). Pre-merge verification = `actionlint` + shellcheck + local-shell-extraction unit test (Phase 3.3). Post-merge verification = `gh workflow run` against main (Phase 5).

### Phase 3 -- Unit tests for the drift detection logic

3.1 Add `scripts/test/audit-bypass-drift.test.sh` (or `.bats` if existing
    test convention uses bats). Convention check: `find apps/ scripts/
    plugins/ -name '*.test.sh' -o -name '*.bats' 2>/dev/null | head` ->
    detect convention before authoring. Likely `.test.sh` (project
    convention; per Sharp Edge "never prescribe a new test framework
    without an Add dependency task").

3.2 Test cases (deterministic; no live API):

    - **T1 -- identity:** live equals canonical -> exit 0, no failure_mode.
    - **T2 -- added entry:** live has an extra `RepositoryRole id=4`
      (Maintain) -> drift detected, label `ci/auth-broken`.
    - **T3 -- removed entry:** live missing OrganizationAdmin -> drift
      detected, label `ci/auth-broken` (drift in either direction).
    - **T4 -- mode change:** live has OrganizationAdmin `bypass_mode:
      always` instead of `pull_request` -> drift detected (THE most
      brand-damaging case: silent broadening from PR-gated to always).
    - **T5 -- order-insensitive:** live has the same 2 entries in
      reverse order -> NO drift (jq `sort_by` is canonical).
    - **T6 -- `actor_id: null` vs missing key:** live has
      `{"actor_type": "OrganizationAdmin", "bypass_mode": "pull_request"}`
      (no `actor_id` key at all) -> NO drift (jq `(.actor_id // "null"
      | tostring)` collapses both to `"null"`). This is the trap from
      the Research Reconciliation table.
    - **T7 -- canonical file missing/malformed:** -> failure_mode
      `canonical_file_missing` or `canonical_file_invalid_json`,
      label `ci/guard-broken`.
    - **T8 -- live API HTTP 5xx:** mocked curl returns 503 -> failure_mode
      `github_api_http`, label `ci/guard-broken`.
    - **T9 -- log-injection sanitation:** failure_detail containing CRLF
      and U+2028 -> emitted `key=value` has none of those bytes.

3.3 The test extracts the drift-detection bash block from the YAML via
    `yq '.jobs.audit.steps[2].run' workflow.yml > /tmp/audit-step.sh`
    and sources it inside a test harness that mocks `curl`/`gh`. This is
    NOT `bash -n` (which would crash on the YAML header); it's
    `bash -c "$(extract-step.sh) ..."` with fixtures. Per Sharp Edge
    "embedded shell in YAML: extract, then `bash -c`".

3.4 Wire `scripts/test/audit-bypass-drift.test.sh` into `scripts/test-all.sh`
    (verify via `bash scripts/test-all.sh` runs it).

### Phase 4 -- Runbook + compliance-posture wiring

4.1 Author `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`:

    - **Pre-mutation gates:** verify drift is real (re-fetch live and diff
      by hand), check audit log for the editing actor and timestamp.
    - **Triage paths:**
      - **Drift = legitimate (e.g., onboarding a new RepositoryRole admin
        on purpose):** edit `scripts/ci-required-ruleset-canonical-bypass-actors.json`
        in a PR, get CPO sign-off via `requires_cpo_signoff: true`
        frontmatter, append a row to `compliance-posture.md` `#2719`.
      - **Drift = unauthorized broadening:** rotate admin credentials
        (org owner action), restore canonical via `update-ci-required-ruleset.sh`
        PUT (uses canonical JSON, not live, post-Phase-1 refactor),
        file post-mortem under `knowledge-base/project/learnings/security-issues/`,
        update `compliance-posture.md` Active Items.
      - **Drift = guard malfunction:** check API rate limit, token scope,
        re-run via `workflow_dispatch`; if persistent, open
        `ci/guard-broken` post-mortem.
    - **Green-recovery procedure:** the audit auto-closes the tracking
      issue on next green run; operators must NOT manually close
      drift-fired issues without verifying the next audit pass.

4.2 Amend `knowledge-base/legal/compliance-posture.md`:
    - `last_updated: 2026-05-11`.
    - HTML comment row noting `<!-- 2026-05-11: R15 follow-up D1 -- daily
      bypass_actors audit landed via #<this-PR> -->`.
    - `#2719` row gets a trailing sentence: "Daily audit
      (`.github/workflows/scheduled-ruleset-bypass-audit.yml`, #3544)
      compares live `bypass_actors` to
      `scripts/ci-required-ruleset-canonical-bypass-actors.json`; any
      drift auto-files a `compliance/critical` issue routed to CLO."

4.3 Amend `scripts/required-checks.txt` -- one comment-block addition
    pointing readers to the canonical JSON. Three lines max.

### Phase 5 -- Post-merge verification (operator-run, per `hr-menu-option-ack-not-prod-write-auth`)

Post-merge ACs (no auto-execution; operator drives):

5.1 Verify workflow file is on `main` (per Sharp Edge: `workflow_dispatch`
    requires default-branch presence):
    ```bash
    gh api repos/jikig-ai/soleur/contents/.github/workflows/scheduled-ruleset-bypass-audit.yml?ref=main \
      --jq '.path'
    ```
    Must return the path string.

5.2 Run the workflow once manually:
    ```bash
    gh workflow run scheduled-ruleset-bypass-audit.yml
    ```
    Then poll:
    ```bash
    until gh run list --workflow=scheduled-ruleset-bypass-audit.yml \
      --limit=1 --json conclusion,status \
      --jq '.[0] | select(.status=="completed") | .conclusion' \
      | grep -q success; do sleep 20; done
    ```
    Expect: `conclusion: success`, audit-green path, no tracking issue
    filed.

5.3 Smoke-test the failure path. Temporarily edit
    `scripts/ci-required-ruleset-canonical-bypass-actors.json` on a
    short-lived branch to a known-different value (e.g., remove the
    `RepositoryRole` entry), open a tiny PR, re-run the workflow via
    `gh workflow run --ref <smoke-branch>`. Expect: `failure_mode =
    bypass_actors_drift`, `label = ci/auth-broken`, one
    `[compliance/critical] CI Required ruleset bypass_actors drift
    detected` issue filed. Verify body contains the live vs canonical
    diff. Then close the smoke PR without merging, close the smoke
    issue, document in the runbook.

5.4 Update `compliance-posture.md`:
    - Move D1 from "deferred" to "landed" in the `#2719` row:
      `R15 follow-up D1 landed via #<this-PR> on 2026-05-11`.

5.5 Close #3544: `gh issue close 3544 --comment "Landed via #<this-PR>.
    Smoke transcript: <link to smoke-PR-run>."`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `.github/workflows/scheduled-ruleset-bypass-audit.yml` exists,
      passes `yamllint`, passes `actionlint` (with shellcheck integration).
- [ ] **AC2** `scripts/ci-required-ruleset-canonical-bypass-actors.json`
      exists, is valid JSON (`jq -e . < file > /dev/null`), and equals
      live state at time of merge (`jq -s 'sort_by(...) == sort_by(...)'
      comparison against `gh api .../rulesets/14145388 --jq '.bypass_actors'`).
- [ ] **AC3** `scripts/create-ci-required-ruleset.sh` builds an identical
      payload (modulo `bypass_actors` source) compared to the pre-refactor
      version. Verify via `diff <(bash scripts/create-ci-required-ruleset.sh
      --print-payload) <(git show HEAD~1:scripts/create-ci-required-ruleset.sh
      | bash --print-payload)`.
- [ ] **AC4** `scripts/update-ci-required-ruleset.sh` post-PUT verification
      now references the canonical JSON file (grep for the path string
      returns ≥1 hit).
- [ ] **AC5** `scripts/test/audit-bypass-drift.test.sh` exists and all 9
      test cases (T1-T9) pass.
- [ ] **AC6** `bash scripts/test-all.sh` exits 0 and includes the new
      audit-bypass-drift test in its output.
- [ ] **AC7** `knowledge-base/engineering/ops/runbooks/ruleset-bypass-drift.md`
      exists and lists the three triage paths.
- [ ] **AC8** `knowledge-base/legal/compliance-posture.md` has
      `last_updated: 2026-05-11` and the `#2719` row mentions the daily
      audit.
- [ ] **AC9** `scripts/required-checks.txt` has a comment pointing to the
      canonical JSON file.
- [ ] **AC10** PR body uses `Ref #3544`, `Ref #3542`, `Ref #2719` -- NOT
      `Closes` (per `ops-remediation` extension of `wg-use-closes-n-in-pr-body-not-title-to`;
      the actual closure is post-merge after Phase 5.3 smoke).
- [ ] **AC11** PR body declares brand-survival threshold `single-user
      incident` (carry-forward from parent R15) and references CPO sign-off
      from #3543.
- [ ] **AC12** No new top-level dependencies added (no Sharp Edge violation
      for "no new dependencies" claim).
- [ ] **AC13** `actor_id: null` vs missing-key trap is exercised by T6 in
      the test suite (per Research Reconciliation table).

### Post-merge (operator)

- [ ] **AC14** Phase 5.1 verifies workflow on default branch.
- [ ] **AC15** Phase 5.2 manual `workflow_dispatch` run on main succeeds
      with audit-green.
- [ ] **AC16** Phase 5.3 smoke-PR drives a known drift; one
      `[compliance/critical]` issue filed; closed via Phase 5.3 cleanup.
- [ ] **AC17** Phase 5.4 `compliance-posture.md` `#2719` row updated to
      "landed via #<this-PR>".
- [ ] **AC18** Phase 5.5 issue #3544 closed with smoke-transcript link.
- [ ] **AC19** Next-day cron (2026-05-12 06:00 UTC) fires and exits green
      -- verify next session via `gh run list --workflow=scheduled-ruleset-bypass-audit.yml --limit=2`.

## Test Scenarios

### Scenario 1: Audit green path (no drift)

**Given:** Live `bypass_actors` matches canonical JSON exactly.
**When:** Workflow fires at 06:00 UTC.
**Then:**
1. `check` step completes with `failure_mode=""`.
2. `tripwire` step completes with no leak shape found.
3. No issue is filed.
4. Any open `[compliance/critical] CI Required ruleset bypass_actors drift`
   issue (carryover from a prior drift) is auto-closed with the
   audit-green comment.
5. `notify-ops-email` is NOT triggered.

### Scenario 2: Drift detected (mode broadening)

**Given:** An admin edits `OrganizationAdmin.bypass_mode` from
`pull_request` to `always` directly via the GitHub UI.
**When:** Workflow fires.
**Then:**
1. `check` step sets `failure_mode=bypass_actors_drift`, `failure_label=ci/auth-broken`.
2. `failure_detail` contains a redacted-of-CRLF rendering of the diff.
3. A new issue is filed titled `[compliance/critical] CI Required ruleset
   bypass_actors drift detected`.
4. Issue is labeled `compliance/critical`, `ci/auth-broken`,
   `priority/p1-high`, `domain/legal`.
5. Issue body links to the run, the runbook, and references #2719, #3542,
   #3544.
6. `notify-ops-email` sends with subject containing `bypass_actors_drift`.

### Scenario 3: Drift detected (entry added)

**Given:** A new `Integration` bypass_actor for a recently-installed app
appears in the live ruleset.
**When:** Workflow fires.
**Then:** Same as Scenario 2; the failure_detail names the added entry's
`actor_type` + `actor_id`.

### Scenario 4: Audit malfunction (network)

**Given:** `api.github.com` returns HTTP 503 to the curl request.
**When:** Workflow fires.
**Then:**
1. `check` sets `failure_mode=github_api_http`, `failure_label=ci/guard-broken`.
2. Issue filed (or commented if open) with label `ci/guard-broken`,
   `priority/p1-high`. NO `compliance/critical` label (this is guard
   failure, not authority drift).
3. `notify-ops-email` sends.

### Scenario 5: Audit recovery

**Given:** A prior drift opened a `[compliance/critical]` issue; admin has
since restored the canonical state.
**When:** Workflow fires green.
**Then:** The open issue is auto-closed with the audit-green comment
referencing the run.

### Scenario 6: De-dupe on repeated drift

**Given:** Drift detected on day N; issue #X filed. Drift persists into
day N+1.
**When:** Workflow fires on day N+1.
**Then:** No new issue; a comment is added to #X noting the second
detection at the new timestamp.

## Risks

1. **GitHub API rate-limit at 06:00 UTC.** Mitigation: workflow uses
   `${{ secrets.GITHUB_TOKEN }}` (5000 req/hr), only 1 API call per run,
   timeout 5min. Not a real risk at daily cadence.

2. **`actor_id: null` vs missing-key.** Already covered by Research
   Reconciliation, test T6, and the jq `(.actor_id // "null" | tostring)`
   coalescing pattern. Plan-time canonical JSON authorship MUST use
   `null` (verified from live state).

3. **Canonical JSON drift from authorized changes (e.g., onboarding a
   second admin).** Mitigation: the canonical JSON is in-repo, edits go
   through PR review with `requires_cpo_signoff: true` on the editing
   PR (per parent R15 frontmatter inheritance). Authorized changes
   become a co-incident with `compliance-posture.md` row update;
   re-running the audit closes the old tracking issue.

4. **False positive at `gh run list` polling in Phase 5.2.** Mitigation:
   `--limit=1` + `--jq` filter for `status=completed`, polling loop
   with sleep.

5. **Log injection via the `failure_detail` JSON diff.** Mitigation:
   `strip_log_injection` mirror of drift-guard yaml:266-273 -- strips
   CR/LF/FF/VT/DEL + U+0085 + U+2028 + U+2029 via tr+sed before
   echoing to `$GITHUB_OUTPUT`. Per Sharp Edge `cq-regex-unicode-separators-escape-only`.

6. **Re-fetching from `api.github.com` instead of `gh api`.** Mitigation:
   curl gives us `--max-time 15` (Sharp Edge: pin a timeout); `gh api`
   does not. The trade-off (manual JSON-error handling) is small.

7. **Workflow disabled by GHA after 60 days inactivity if never fires.**
   Mitigation: daily cron -> never idle. (Same defense the
   `scheduled-disk-io-7d-recheck.yml` `--once`-style workflows lack and
   manage via self-disable.)

## Sharp Edges

A plan whose `## User-Brand Impact` section is empty, contains only TBD,
or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)

Per Sharp Edge #2026-05-11-multi-word-required-check: do NOT prescribe
`bash -n .github/workflows/scheduled-ruleset-bypass-audit.yml` as an AC.
Use `yamllint` + `actionlint -shellcheck=` for the YAML; use
`bash -c "$(yq '.jobs.audit.steps[2].run' ...)" ...` for the embedded
shell snippet (extracted-then-run).

Per `2026-04-21-workflow-dispatch-requires-default-branch.md`: pre-merge
verification of the workflow itself is impossible via `gh workflow run
--ref feat-branch` -- the workflow file must be on the default branch
first. Mitigation: unit tests on the extracted shell snippet (Phase 3)
substitute for end-to-end execution; Phase 5.2 + 5.3 are the post-merge
smoke that closes the loop.

Per `wg-use-closes-n-in-pr-body-not-title-to` `ops-remediation` extension:
PR body uses `Ref #3544`, NOT `Closes #3544`. Issue closure happens
post-merge after Phase 5.3 smoke succeeds.

Per Sharp Edge "verify-third-party-action-behavior-claims-against-codebase-precedent":
`notify-ops-email` composite action exists at
`.github/actions/notify-ops-email/action.yml` -- verified at plan time.

Per `cq-pg-security-definer-search-path-pin-pg-temp`: N/A (no Postgres
in scope).

Per `hr-when-a-plan-specifies-relative-paths-e-g`: file glob check --
the canonical JSON file is a single new file (not a glob); the workflow
file is a single new file; the runbook is a single new file. All
absolute paths verified to exist or be greenfield.

When editing `scripts/create-ci-required-ruleset.sh` to source from a
JSON file, R10 Sharp Edge ("heredoc payload then `--input`") still
applies -- the JSON file is read via `jq --slurpfile`, then the assembled
payload is written to a tempfile and `--input "$payload"` is used.

## Alternative Approaches Considered

| Approach | Pro | Con | Decision |
|---|---|---|---|
| Hourly cron (mirror drift-guard) | 1h worst-case detection | 24x more cron-job consumption; admin edits are vanishingly rare for solo operator | Defer to daily; re-evaluate when a 2nd admin operator onboards (issue's re-eval criterion) |
| Audit ALL rulesets, not just CI Required | Catches CLA Required + future rulesets | Wider blast radius; CLA Required doesn't gate R15 (single-user-incident threshold) | Scoped to CI Required only; file scope-out for CLA expansion if R15 ever expands |
| Compare via `gh api ... | diff` instead of jq sort | Simpler shell | Sensitive to key order returned by GitHub (not contractual); fragile | Use `jq sort_by` (deterministic) |
| Store canonical as YAML inside the workflow | One file | Duplicates source-of-truth from `create-ci-required-ruleset.sh`; drift between the two becomes its own audit problem | JSON file shared by both is the single source of truth |
| File a `domain/legal` issue (not `compliance/critical`) | Simpler routing | `domain/legal` is a triage label, not a severity; the issue body's explicit `compliance/critical` ask is load-bearing | Use `compliance/critical` per issue body; also apply `domain/legal` for CLO routing |
| Audit `bypass_actors` AND `required_status_checks` AND `conditions` in one workflow | More coverage | Conflates "trust authority broadened" (this audit's job) with "required checks weakened" (separate threat); the latter is a different blast-radius surface | Scope to bypass_actors; file a follow-up for required_status_checks audit if a separate incident motivates it |

## Domain Review

**Domains relevant:** Engineering (CTO -- CI/security workflow), Legal/Compliance (CLO -- `compliance/critical` issue routing), Product (CPO -- `single-user incident` threshold carry-forward from R15).

### Engineering (CTO)

**Status:** carry-forward from #3542 / #3524
**Assessment:** This is a small follow-up audit workflow on top of the R15
mitigation that already shipped. The pattern (3-output failure routing,
strip_log_injection, runbook-linked tracking issue, notify-ops-email)
is well-established in `scheduled-github-app-drift-guard.yml`. No new
architectural surface; reuse of existing labels and composite actions.

### Legal/Compliance (CLO)

**Status:** carry-forward from #3542 / #3543 (#2719 R15 mitigation)
**Assessment:** The brand-survival threshold inherits from #2719: a
broadened bypass_actor allows a malicious skill-install PR to merge
without the `skill-security-scan PR gate`, which is the single-user
incident vector. This audit closes the audit-log-only blind spot in the
R15 mitigation (#3543's `update-ci-required-ruleset.sh` copies
bypass_actors verbatim from live; this workflow asserts live ==
canonical at daily cadence). The `compliance/critical` label routes to
CPO + CLO triage. Inherits #2719's EU jurisdiction posture.

### Product/UX Gate

**Tier:** NONE
**Decision:** auto-accepted (no user-facing surface; this is an internal CI cron workflow)
**Agents invoked:** none
**Skipped specialists:** none (no Product domain in scope beyond brand-survival threshold carry-forward, which is a CLO matter)
**Pencil available:** N/A

## GDPR Gate

**Decision:** SKIPPED (no regulated-data surface). The audit fetches a
GitHub Ruleset definition (organizational config metadata, not PII); the
issue body it files contains no PII (failure_mode, failure_detail,
timestamps, run URL). Per canonical regex in `gdpr-gate/SKILL.md`: no
schemas, no migrations, no auth flows, no API routes.

## Telemetry & Observability

- Each workflow run emits one of three outcomes via `$GITHUB_OUTPUT`:
  `failure_mode=""` (green), `failure_mode=bypass_actors_drift` (drift),
  `failure_mode=<other>` (guard malfunction).
- A tracking issue per drift route serves as the on-disk durable state.
- `notify-ops-email` carries the operator-facing alert.
- No Sentry integration (this is CI infrastructure, not application code;
  Sentry-mirror rule `cq-silent-fallback-must-mirror-to-sentry` applies
  to app code paths only).

## Rollout Plan

1. PR opens with all Phase 1-4 artifacts.
2. CI green; merge to main.
3. Operator runs Phase 5.1 + 5.2 + 5.3 (smoke) + 5.4 + 5.5 in order.
4. The daily cron self-runs from 2026-05-12 onward; Phase 5 AC19 verifies.

## Rollback Plan

If the workflow misfires (false positive flood):
1. Disable: `gh workflow disable scheduled-ruleset-bypass-audit.yml`.
2. Investigate via the runbook's "audit malfunction" path.
3. File a fix PR; re-enable post-merge.

The canonical JSON file is harmless if the workflow is disabled (no
consumer of `scripts/ci-required-ruleset-canonical-bypass-actors.json`
other than the audit and the post-PUT verification in
`update-ci-required-ruleset.sh`).

## References

- #3544 (this issue)
- #3542 (parent R15 mitigation deferral D1)
- #3543 (R15 mitigation PR -- shipped 2026-05-11)
- #2719 (origin: skill-install advisory gate, single-user incident threshold)
- #3524 (parent skill PR)
- `scripts/create-ci-required-ruleset.sh` (canonical bypass_actors source)
- `scripts/update-ci-required-ruleset.sh` (R15 mutation script)
- `.github/workflows/scheduled-github-app-drift-guard.yml` (pattern template)
- `knowledge-base/engineering/ops/runbooks/skill-security-scan-required-check.md` (parent runbook)
- `knowledge-base/legal/compliance-posture.md` (`#2719` row -- post-merge update)
- Learning: `2026-03-19-github-ruleset-stale-bypass-actors.md`
- Learning: `2026-04-03-github-ruleset-put-replaces-entire-payload.md`
