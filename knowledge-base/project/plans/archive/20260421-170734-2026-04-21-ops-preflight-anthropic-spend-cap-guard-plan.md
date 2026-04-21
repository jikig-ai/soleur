# ops: add pre-flight Anthropic spend-cap guard to Claude-using workflows

**Issue:** #2715
**Type:** chore / ops
**Priority:** p2-medium
**Branch:** `feat-one-shot-2715-preflight-spend-cap-guard`
**Milestone:** Post-MVP / Later

## Enhancement Summary

**Deepened on:** 2026-04-21
**Sections enhanced:** 6 (Non-Goals, Research Insights, Implementation Phases, Files to Edit, Risks, Acceptance Criteria)
**Research sources used:** Anthropic Admin API docs, Anthropic Messages API docs, GitHub Actions expressions docs, `gh api repos/anthropics/claude-code-action/releases`, repo grep of `if: failure()` step-level conditionals.

### Key Improvements

1. **Verified skipped-job → failure-notification semantics live.** `if: failure()` is a **step-level** conditional inside the claude-action job in 11 of the 15 scheduled workflows. When the job-level guard `if: needs.preflight.outputs.ok == 'true'` evaluates false, the whole job is skipped — the `if: failure()` step never runs. This is exactly the desired "no email on cap day" behavior. No extra wiring needed.
2. **Resolved action-pin cross-check live.** `v1.0.102` was released 2026-04-20 (one day after `v1.0.101`, which the repo pins). Pin-freshness rule (`cq-claude-code-action-pin-freshness`) says ≤ 3 weeks; we are within the window. `v1` floating tag resolves to SHA `5d29e76984c4bd1246cd84381ae25b1452e9047b` (different from `v1.0.101`'s `ab8b1e6471c519c585ba17e8ecaccc9d83043541`), confirming `scheduled-roadmap-review.yml`'s `@v1` is a separate pin requiring a separate PR to reconcile.
3. **Pinned model ID to the dated form.** Switched from `claude-haiku-4-5` (alias, survives model-rotation) to `claude-haiku-4-5-20251001` (the exact ID cited in issue #2715 body). Aliases may or may not exist for every minor bump; the dated ID is the API-guaranteed form. Tradeoff documented in Research Insights.
4. **Added actionlint caveat for composite actions.** `actionlint` validates the workflow references but does NOT deeply lint composite action `action.yml` files for shell errors — the embedded bash block is the real risk surface. Added explicit `shellcheck` task to the Phase 1 exit checks.
5. **Sharp-edge guard: duplicate-edit bug propagation.** Added AGENTS.md `cq-workflow-pattern-duplication-bug-propagation` reference to Risks and to the implementation discipline.
6. **Explicit test for the cap-exhausted branch.** Added a `workflow_dispatch`-driven test via a temporary test workflow that injects a known-bad key, rather than waiting for natural cap exhaustion. See T2 in Test Scenarios.

### New Considerations Discovered

- **The `setup-node` and `actions/checkout` steps in the existing workflows add 10-30s each.** The preflight job does NOT need either — it's a pure `curl`. Save overhead by not adding `uses: actions/checkout@...` to the preflight job unless strictly needed. (Sketch in Phase 1 had checkout; removed in deepened version — the composite action runs inline shell without repo files.)
- **`concurrency: group` + `cancel-in-progress: false`** — when the preflight passes and the next run queues, the claude job queues behind. No change to existing concurrency behavior.
- **5-minute `timeout-minutes` cap on the preflight job** bounds the failure mode if Anthropic hangs during a global incident. 5 minutes is generous (typical response <2s); it just prevents the job from consuming the caller's full budget (`scheduled-bug-fixer.yml` has `timeout-minutes: 150`).
- **The `permissions:` block can stay unchanged.** The preflight job inherits workflow-level `permissions:`; it only needs network egress (no GH token read/write). Confirmed by inspection — `permissions: contents: read` is strictly more permission than needed, but no downside.
- **Model pricing quote accuracy.** Haiku 4.5 published pricing is `$1.00 / Mtok` input / `$5.00 / Mtok` output as of 2026-04 (Anthropic pricing page); 1 token input = $0.000001. Updated from the earlier $0.80/Mtok estimate. 450 pings/month ≈ $0.00045 — still negligible.

## Overview

When the Anthropic Console **monthly usage-limit cap** exhausts, every scheduled Claude-using workflow fails mid-step with `API Error 400: You have reached your specified API usage limits`. On 2026-04-20/21 this produced 8 failed runs, 8 <ops@jikigai.com> failure emails, ~80 min wasted runner time, and silent backlog until an operator noticed.

This plan adds a composite action `.github/actions/anthropic-preflight/` that each Claude-using workflow calls **before** the `anthropics/claude-code-action` step. The preflight sends a 1-token `claude-haiku-4-5` ping; on cap-exhausted it surfaces a clear outcome the caller can branch on and exit early with `success` (no email spam, no wasted runner minutes). Unexpected non-200 responses fail fast with full body so operators see what broke.

## Goals

- A single shared composite action any workflow can call before Claude steps.
- Cap exhaustion → workflow exits `success` (skipped), zero failure emails.
- Unexpected non-200 → workflow fails fast with clear diagnostic (existing failure path still fires if the cap drains mid-run).
- Wired into **all 15** workflows that currently use `anthropics/claude-code-action@*` (enumerated below).
- O(1) API call, <10s per workflow, negligible token cost.

## Non-Goals

- **Not** switching to the Admin API `cost_report` endpoint. Verified 2026-04-21 via [platform.claude.com/docs/en/api/admin-api/usage-cost/get-cost-report](https://platform.claude.com/docs/en/api/admin-api/usage-cost/get-cost-report): the endpoint returns *historical* cost buckets, not remaining quota. Computing `remaining = cap - cumulative` requires (a) an Admin API key (separate secret, broader scope), (b) knowing the configured cap out-of-band, and (c) a second query. The 1-token probe is strictly simpler and has identical detection semantics. Open question resolved against the probe.
- **Not** adding a daily "today saved N runs" summary email in this PR. Split into follow-up issue (see Deferrals).
- **Not** modifying `claude-code-review.yml` (PR-event-triggered, not scheduled) — it's included in the 15-workflow wiring because cap-exhaustion still kills operator review work, but the "not scheduled" distinction only affects notification policy.
- **Not** fixing the stale `@v1` floating pin in `scheduled-roadmap-review.yml`. That's a separate concern tracked elsewhere.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2715) | Codebase reality (verified 2026-04-21) | Plan response |
| --- | --- | --- |
| "8+ scheduled workflows" | **15** workflows use `anthropics/claude-code-action@*` today (see list in Phase 2) | Wire all 15, not just the 8 that failed on 2026-04-20. The 7 unaffected today were simply off-schedule — same class of failure. |
| Notify via `notify-ops-email` composite | Action exists at `.github/actions/notify-ops-email/action.yml` and is used by 17 workflows | No change — preflight just prevents the email from firing on cap-exhausted. |
| Preflight response shape | Anthropic returns `400` with body containing `"specified API usage limits"` phrase | Grep the phrase verbatim (issue's proposed pattern confirmed). |
| Admin API has direct quota endpoint | **No.** `/v1/organizations/cost_report` returns historical buckets only. No "remaining quota" endpoint. | Proceed with 1-token probe; document rationale in composite action header. |
| All 15 workflows pinned to `v1.0.101` | 14 pinned to `ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101`; **`scheduled-roadmap-review.yml` uses floating `@v1`** | Out of scope here — flag in `## Open Code-Review Overlap`. |

## Hypotheses

N/A — not an SSH/network-outage symptom (issue trigger list: SSH, kex, firewall, handshake, 5xx — none apply; this is a vendor-API quota issue with a known 400 error body).

## Research Insights

### Composite action pattern (verified against `.github/actions/notify-ops-email/action.yml`)

- `runs.using: 'composite'` with `shell: bash` per step.
- Inputs declared with `required: true` + `description`. Secrets passed from caller (`resend-api-key: ${{ secrets.RESEND_API_KEY }}` pattern) — the same shape works for `anthropic-api-key`.
- Outputs declared at top level (`outputs.ok.value: ${{ steps.check.outputs.ok }}`) and consumed by the caller via `needs.<job>.outputs.<name>`.
- `HTTP_CODE` separation pattern (`curl -s -o <file> -w '%{http_code}'`) used in notify-ops-email is the cleanest way to split body from status in bash — adopted here for the probe.

### The 1-token probe (from issue, verified against Anthropic API semantics)

```bash
curl -sS -w '\n%{http_code}' https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"."}]}'
```

- **Model ID:** `claude-haiku-4-5-20251001` — the exact dated form cited in issue #2715's body. Aliases (`claude-haiku-4-5`) may or may not be provisioned; the dated ID is API-guaranteed. If Anthropic retires this snapshot before we refresh (typical retention: 6+ months), the preflight will 404 → `exit 1` via the `else` branch → ops sees a clear error. Accept: bumping the dated ID is a 1-line, low-risk change.
- **Cost:** Haiku 4.5 is $1.00/Mtok input and $5.00/Mtok output (Anthropic pricing 2026-04). 1 input token ≈ $0.000001; `max_tokens: 1` bounds output cost. 15 workflows × 1 run/day = 15 pings/day × 30 = 450 pings/month = ~$0.00045/month. Negligible.
- **Latency:** single round-trip to `api.anthropic.com`, <2s typical; add a 5-minute job `timeout-minutes:` as a hard ceiling for global-incident hangs.
- **Cap-exhausted signal:** HTTP 400 with body containing `specified API usage limits`. Grep-matchable. Verbatim error body from issue #2715: `"You have reached your specified API usage limits"`.

### AGENTS.md constraints

- `cq-claude-code-action-pin-freshness` — the action pin `ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101` is current (≤3 weeks); **do not** bump it in this PR. If the pin needs refreshing, do it in a separate PR so the preflight rollout stays atomic.
- `hr-in-github-actions-run-blocks-never-use` — do NOT use column-0 heredoc terminators. The existing `notify-ops-email` pattern uses `$(jq -n ...)` inline and `| head -n -1` for body extraction; preserve that style.
- `cq-ci-steps-polling-json-endpoints-under` — the preflight parses a response body, but it's a **single** request (no retry loop), so `jq -e` guard isn't strictly required. However, we ARE calling `jq` to construct the request payload for robustness (issue's `-d '...'` literal form is fine for the ASCII content `"."`, but the AGENTS.md preference for JSON safety suggests `jq -n` is cleaner).
- `hr-github-actions-workflow-notifications` — if we add any notification (we're not, in this PR), it must go through `notify-ops-email`, not Discord webhooks.
- `wg-after-merging-a-pr-that-adds-or-modifies` — after merge, the plan MUST trigger `gh workflow run` on one scheduled workflow (`scheduled-daily-triage.yml` is the cheapest) and verify the preflight step succeeds and the claude step runs unchanged.

### Related learnings

- `knowledge-base/project/learnings/2026-03-14-curl-response-header-capture-pattern.md` — confirms the `-w '%{http_code}'` separator pattern is a documented convention in this repo.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` (27 open issues). For each planned file path:

- `.github/actions/anthropic-preflight/action.yml` → None (new file)
- `.github/workflows/scheduled-ux-audit.yml` → None
- `.github/workflows/scheduled-community-monitor.yml` → None
- `.github/workflows/scheduled-bug-fixer.yml` → None
- Generic `anthropics/claude-code-action` / `ANTHROPIC_API_KEY` / scheduled-workflow matches → None

**Result:** None. Two adjacent issues (noted during research but NOT returned by `--label code-review`):

- `scheduled-roadmap-review.yml` uses the floating `@v1` pin instead of a SHA — **Acknowledge.** Live SHA lookup (2026-04-21) via `gh api repos/anthropics/claude-code-action/git/refs/tags/v1`:

  ```text
  v1 → 5d29e76984c4bd1246cd84381ae25b1452e9047b
  v1.0.101 → ab8b1e6471c519c585ba17e8ecaccc9d83043541
  v1.0.102 → <published 2026-04-20, 1 day after 1.0.101; within freshness window>
  ```

  The `@v1` SHA differs from the repo's other pin, so `scheduled-roadmap-review.yml` floats to whatever `v1` resolves to at run time. Separate PR / issue will reconcile. Not in scope here.

## Stakeholders

- **Ops (CTO/COO):** receives failure emails; benefits most — zero false-alarm emails on cap days.
- **Plugin maintainers:** each time a new scheduled workflow is added, must remember to wire in the preflight. Mitigated by adding a line to `knowledge-base/engineering/` docs (and optionally a rule-audit check, deferred).
- **Anthropic billing:** +450 haiku pings/month across the org. Negligible.

## Detail Level: MORE

Not MINIMAL (multi-file, workflow wiring requires careful duplication and verification across 15 files) and not A LOT (no new skill, no new domain leaders, no new testing framework — it's a composite action and a sed-able edit across 15 YAMLs).

## Implementation Phases

### Phase 1 — Composite action scaffold

**Files to create:**

- `.github/actions/anthropic-preflight/action.yml`

**Contract:**

- **Inputs:** `anthropic-api-key` (required, secret).
- **Outputs:** `ok` — string `"true"` | `"false"`. `"false"` means cap exhausted. (Do not use `"skipped"` — GitHub outputs are strings; keep the set binary for caller branching.)
- **Behavior:**
  - `200` → `ok=true`.
  - `400` with body containing `specified API usage limits` → `ok=false`, emit `::warning::` with the Anthropic-supplied message for observability.
  - Anything else (4xx other, 5xx, non-JSON, curl exit != 0) → `exit 1` with `::error::` including HTTP code + first 500 chars of body. The Claude step won't run (blocked by `needs` + `if`), and the workflow's existing `notify-ops-email` failure hook still fires — which is correct for "something unexpected is broken."
- **No retry.** A single probe is sufficient; transient network blips that recover within seconds would not change the cap state. The caller's existing behavior (no preflight retry today) is preserved.

**Sketch** (final form belongs in the action.yml; heredoc-safe bash, no column-0 terminators):

```yaml
name: 'Anthropic Preflight'
description: 'Probe the Anthropic API with a 1-token request before an expensive claude-code-action step. Sets ok=false if the monthly spend cap is exhausted, exits non-zero on unexpected failures.'

inputs:
  anthropic-api-key:
    description: 'Anthropic API key (from secrets.ANTHROPIC_API_KEY)'
    required: true

outputs:
  ok:
    description: 'true if the API is usable; false if the monthly cap is exhausted. Step fails (exit 1) for unexpected errors.'
    value: ${{ steps.check.outputs.ok }}

runs:
  using: 'composite'
  steps:
    - id: check
      shell: bash
      env:
        ANTHROPIC_API_KEY: ${{ inputs.anthropic-api-key }}
      run: |
        set -uo pipefail
        BODY_FILE="${RUNNER_TEMP}/anthropic-preflight-body.txt"
        # CI-only mock path: exercises the cap-exhausted grep deterministically.
        # Never set in production workflows.
        if [[ -n "${ANTHROPIC_PREFLIGHT_MOCK_RESPONSE:-}" ]]; then
          printf '%s' "$ANTHROPIC_PREFLIGHT_MOCK_RESPONSE" > "$BODY_FILE"
          HTTP_CODE="${ANTHROPIC_PREFLIGHT_MOCK_HTTP_CODE:-400}"
        else
          if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
            echo "::error::ANTHROPIC_API_KEY not set"
            exit 1
          fi
          PAYLOAD=$(jq -nc '{model:"claude-haiku-4-5-20251001",max_tokens:1,messages:[{role:"user",content:"."}]}')
          HTTP_CODE=$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
            https://api.anthropic.com/v1/messages \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -H "content-type: application/json" \
            -d "$PAYLOAD" || echo "000")
        fi
        BODY=$(head -c 500 "$BODY_FILE" 2>/dev/null || echo "")
        # Verbatim error body from Anthropic API on cap-exhausted —
        # source: issue #2715 (2026-04-21), string "specified API usage limits"
        if [[ "$HTTP_CODE" == "200" ]]; then
          echo "ok=true" >> "$GITHUB_OUTPUT"
          echo "Anthropic preflight: OK"
        elif [[ "$HTTP_CODE" == "400" ]] && grep -q "specified API usage limits" "$BODY_FILE"; then
          echo "ok=false" >> "$GITHUB_OUTPUT"
          echo "::warning::Anthropic spend cap exhausted — skipping Claude steps. Body: $BODY"
        else
          echo "::error::Unexpected Anthropic preflight response (HTTP $HTTP_CODE). Body: $BODY"
          exit 1
        fi
```

**Verification tasks (Phase 1 exit):**

1. `yamllint .github/actions/anthropic-preflight/action.yml`.
2. `actionlint .github/actions/anthropic-preflight/action.yml` (note: actionlint's coverage of composite-action shell bodies is weaker than for workflows — supplement with step 3).
3. `shellcheck -s bash <(awk '/run: \|/,/^[^ ]/' .github/actions/anthropic-preflight/action.yml | tail -n +2)` — extract the bash block and lint directly. Catches `unbound variable`, exit-code swallowing, and quoting bugs that `actionlint` doesn't flag in composite-action `run:` bodies.
4. Smoke test — add a temporary `.github/workflows/test-anthropic-preflight.yml` with `workflow_dispatch`, trigger via `gh workflow run test-anthropic-preflight.yml`, poll until complete, verify `ok=true`. Delete the file before PR merge. Alternative: trigger via the first migrated workflow in Phase 2 with `workflow_dispatch`.

### Phase 2 — Wire into all 15 workflows

**Files to edit** (enumerated via `grep -l anthropics/claude-code-action .github/workflows/`):

1. `.github/workflows/scheduled-daily-triage.yml`
2. `.github/workflows/scheduled-seo-aeo-audit.yml`
3. `.github/workflows/scheduled-growth-audit.yml`
4. `.github/workflows/scheduled-growth-execution.yml`
5. `.github/workflows/scheduled-campaign-calendar.yml`
6. `.github/workflows/scheduled-community-monitor.yml`
7. `.github/workflows/scheduled-competitive-analysis.yml`
8. `.github/workflows/scheduled-content-generator.yml`
9. `.github/workflows/scheduled-follow-through.yml`
10. `.github/workflows/scheduled-bug-fixer.yml`
11. `.github/workflows/scheduled-ship-merge.yml`
12. `.github/workflows/scheduled-ux-audit.yml`
13. `.github/workflows/scheduled-roadmap-review.yml`
14. `.github/workflows/test-pretooluse-hooks.yml`
15. `.github/workflows/claude-code-review.yml`

**Wiring pattern (two shapes):**

**Shape A — workflows with a single claude job (14 of 15):** Split into two jobs, `preflight` → `<existing-job-name>`. The existing job keeps its steps but gains `needs: preflight` and `if: needs.preflight.outputs.ok == 'true'`.

```yaml
jobs:
  preflight:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      ok: ${{ steps.check.outputs.ok }}
    steps:
      # NOTE: checkout IS required because `uses: ./.github/actions/anthropic-preflight`
      # is a repo-local composite action — GitHub needs the repo on disk to resolve it.
      # Confirmed by GitHub docs on local-composite-action resolution.
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      - id: check
        uses: ./.github/actions/anthropic-preflight
        with:
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}

  <existing-job-name>:
    needs: preflight
    if: needs.preflight.outputs.ok == 'true'
    # ... existing content unchanged ...
```

**Skipped-job + `if: failure()` semantics (verified live):**

11 of the 15 workflows have a step `if: failure()` inside the claude-job (e.g., `scheduled-seo-aeo-audit.yml:93`, `scheduled-ux-audit.yml:191,211`) that invokes `./.github/actions/notify-ops-email`. When the job-level `if: needs.preflight.outputs.ok == 'true'` evaluates false, the **entire job is skipped**. Per GitHub docs ([Evaluate expressions → Status check functions](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/evaluate-expressions-in-workflows-and-actions#status-check-functions)): `failure()` returns true only when a previous step of the same job fails. A **skipped job never executes any steps**, so `if: failure()` inside it never runs → no email. Per [using-conditions-to-control-job-execution](https://docs.github.com/en/actions/using-jobs/using-conditions-to-control-job-execution): "A job that is skipped will report its status as 'Success'." → workflow conclusion is `success`, not `failure`. This is exactly what we want. No extra wiring needed on the 11 failure-notification workflows.

**Shape B — `scheduled-bug-fixer.yml` and `scheduled-ship-merge.yml`:** These already have a `select` gate (`if: steps.select.outputs.issue`). The `preflight` job is still a separate first job; the existing `select` gate stays in place as a second condition. If either the preflight fails OR there's nothing to select, the claude step is skipped — this is correct.

**`notify-ops-email` failure hooks stay as-is.** The failure step runs only on job failure. On `ok=false`, the claude job is **skipped** (not failed) — `if: failure()` does not fire on skip. Verified via [GitHub docs on status check functions](https://docs.github.com/en/actions/learn-github-actions/expressions#status-check-functions): `failure()` returns true only when a previous step failed; skipped jobs do not count.

**Edge case — `concurrency` groups:** All 15 workflows have `concurrency:` groups. Splitting one job into two does NOT change the group (the group applies at workflow level). No action needed.

**Edge case — `permissions`:** The `preflight` job only needs network access (no GH token). The existing top-level `permissions:` block already covers the second job. No change.

**Edge case — `workflow_dispatch` inputs:** Several workflows accept inputs (e.g., `scheduled-bug-fixer.yml`). These are accessible in both jobs via `github.event.inputs.*`. No change.

**Edge case — `claude-code-review.yml` (PR-triggered):** This workflow is triggered by `pull_request` events, not `schedule`. Cap-exhaustion during a PR still fails the check — same class. Apply the same wiring; the PR-check status will show "skipped" instead of "failed" on a cap day, which is the correct behavior (reviewer will see the skip and retry after quota reset, instead of a red cross they'd retry anyway).

**Verification tasks (Phase 2 exit):**

1. For each edited workflow, `actionlint .github/workflows/<file>.yml` clean.
2. `yamllint .github/workflows/<file>.yml` clean.
3. Confirm the claude step's `uses:` pin is unchanged (`cq-claude-code-action-pin-freshness` — don't bump unrelated pins).
4. After merge: `gh workflow run scheduled-daily-triage.yml` manually and poll with `gh run view <id> --json status,conclusion` until it completes. Expect: preflight job → success, daily-triage job → success (or existing-behavior).

### Phase 3 — Post-merge verification

Per `wg-after-merging-a-pr-that-adds-or-modifies`, a new workflow or composite action MUST be manually triggered to confirm it works end-to-end — syntax validity is not sufficient.

**Tasks:**

1. Merge PR to main.
2. Run `gh workflow run scheduled-daily-triage.yml` (cheapest; ~1min cost).
3. Poll `gh run list --workflow=scheduled-daily-triage.yml --limit 1 --json status,conclusion,databaseId` until `status=completed`.
4. Verify: preflight step logs `Anthropic preflight: OK`, daily-triage job ran to completion.
5. Optional — simulate cap-exhausted: temporarily set `ANTHROPIC_API_KEY` to an empty value via workflow input OR wait for natural cap-exhaustion (not worth blocking on). The `ok=false` path is covered by the unit-test-style inline grep; the workflow conclusion on `ok=false` is `success` (skipped job), which is testable by substituting a known-bad key in a throwaway test-only workflow if desired.

## Files to Create

- `.github/actions/anthropic-preflight/action.yml`

## Files to Edit

- `.github/workflows/scheduled-daily-triage.yml`
- `.github/workflows/scheduled-seo-aeo-audit.yml`
- `.github/workflows/scheduled-growth-audit.yml`
- `.github/workflows/scheduled-growth-execution.yml`
- `.github/workflows/scheduled-campaign-calendar.yml`
- `.github/workflows/scheduled-community-monitor.yml`
- `.github/workflows/scheduled-competitive-analysis.yml`
- `.github/workflows/scheduled-content-generator.yml`
- `.github/workflows/scheduled-follow-through.yml`
- `.github/workflows/scheduled-bug-fixer.yml`
- `.github/workflows/scheduled-ship-merge.yml`
- `.github/workflows/scheduled-ux-audit.yml`
- `.github/workflows/scheduled-roadmap-review.yml`
- `.github/workflows/test-pretooluse-hooks.yml`
- `.github/workflows/claude-code-review.yml`

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
| --- | --- | --- | --- |
| 1-token haiku probe (chosen) | Simple, O(1), negligible cost, direct detection | Consumes 1 token/probe (~$0 total) | **Chosen** |
| Admin API `cost_report` + compare to known cap | Zero-token | Requires Admin API key secret; cap is not exposed via API (must be known out-of-band); two queries; more moving parts | Rejected — complexity > 1 token/month cost |
| Sentry / ops-dashboard alert on first failure | No code change in workflows | Doesn't prevent the 8 emails; operator sees cap only after N failures | Rejected — doesn't solve the problem |
| Single reusable workflow vs. composite action | Slightly more self-contained | Reusable workflows can't be called as a step (only a job); forcing two jobs adds scheduling latency and runner provisioning cost | Composite action is the correct primitive (per `.github/actions/notify-ops-email` precedent) |
| Skip preflight if last N runs succeeded (cache) | Saves tokens | Adds state, cache key design, cache-stale window. 1 token/day is not worth optimizing. | Rejected — YAGNI |

**Deferred for follow-up** (see Deferrals below):

- Daily "today we skipped N Claude runs due to cap" digest email.
- A rule-audit check that flags any new workflow using `anthropics/claude-code-action` without `uses: ./.github/actions/anthropic-preflight` earlier in the same file.
- Migrating `scheduled-roadmap-review.yml` from `@v1` floating to pinned SHA.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.github/actions/anthropic-preflight/action.yml` created, uses composite runs, declares `anthropic-api-key` input and `ok` output.
- [ ] Composite action includes the `ANTHROPIC_PREFLIGHT_MOCK_RESPONSE` / `ANTHROPIC_PREFLIGHT_MOCK_HTTP_CODE` env-var short-circuit for CI-only deterministic testing of the cap-exhausted grep branch (documented inline as "CI-only mock path").
- [ ] Exactly 15 workflows updated with a `preflight` job + `needs: preflight` + `if: needs.preflight.outputs.ok == 'true'` guard on the existing claude job.
- [ ] `actionlint` passes on all 16 changed files.
- [ ] `yamllint` passes on all 16 changed files.
- [ ] `shellcheck` passes on the extracted bash body of the composite action.
- [ ] No changes to `anthropics/claude-code-action` SHA pins in any touched workflow (pin `ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101` preserved; the newer `v1.0.102` published 2026-04-20 will ride a separate `cq-claude-code-action-pin-freshness` sweep).
- [ ] No `hr-in-github-actions-run-blocks-never-use` violations (no column-0 heredoc terminators; payload built with `jq -nc`).
- [ ] `AGENTS.md`, `constitution.md`, and `plugins/soleur/AGENTS.md` unchanged.
- [ ] Cap-branch smoke test: temporary `.github/workflows/test-anthropic-preflight.yml` triggered once with `ANTHROPIC_PREFLIGHT_MOCK_RESPONSE` set, asserts `ok=false`; file deleted before merge.

### Post-merge (operator)

- [ ] `gh workflow run scheduled-daily-triage.yml` triggered and polled to completion (`status=completed`, `conclusion=success`); preflight step visible in logs with `Anthropic preflight: OK`.
- [ ] At least one other scheduled workflow has completed naturally on its next scheduled tick (cross-check the rollout didn't regress the majority path). Verify via `gh run list --workflow=<each>.yml --limit 1`.
- [ ] No failure emails to <ops@jikigai.com> caused by the rollout itself in the 24h post-merge window.

## Test Scenarios

**T1 — OK path (preflight returns 200):**

- Trigger `scheduled-daily-triage.yml` via `workflow_dispatch`.
- Expected: preflight step logs `Anthropic preflight: OK`, outputs `ok=true`; triage job runs.

**T2 — Cap-exhausted path (preflight returns 400 with cap message):**

- Cannot be deterministically triggered on-demand via the real cap. **Chosen approach: CI-only response-body mock env var.** Add a `[[ -n "${ANTHROPIC_PREFLIGHT_MOCK_RESPONSE:-}" ]]` branch at the top of the shell block: if set, use the env var value as the response body and `HTTP_CODE=400`, skip curl. Then the test workflow passes `ANTHROPIC_PREFLIGHT_MOCK_RESPONSE='{"type":"error","error":{"type":"invalid_request_error","message":"You have reached your specified API usage limits"}}'` and asserts `ok=false`. This keeps production code paths minimal (one `if [[ -n ...` guard) while deterministically exercising the grep. Alternative rejected: injecting an invalid key returns HTTP 401, which exercises T3 (unexpected → fail fast), NOT the cap branch — it wouldn't test the grep.
- Record the grep string verbatim in a code comment: `# Verbatim error body from Anthropic API on cap-exhausted — source: issue #2715 (2026-04-21), string "specified API usage limits"`.

**T3 — Unexpected error (preflight returns non-200 non-cap):**

- Covered by the `else` branch — `::error::` + `exit 1`. Verified by static inspection of the action.yml.

**T4 — Missing secret:**

- Preflight exits 1 with `::error::ANTHROPIC_API_KEY not set`. Covered by the guard at top of the shell block.

**T5 — Syntax / wiring regression:**

- `actionlint` + `yamllint` across all 16 files (pre-commit).

## CI Verification

**Commands to run locally before pushing:**

```bash
# Lint the composite action and workflow changes
actionlint .github/actions/anthropic-preflight/action.yml
actionlint .github/workflows/scheduled-*.yml .github/workflows/claude-code-review.yml .github/workflows/test-pretooluse-hooks.yml

# Smoke the probe logic against the real API (optional — costs 1 haiku token ≈ $0)
PAYLOAD=$(jq -nc '{model:"claude-haiku-4-5",max_tokens:1,messages:[{role:"user",content:"."}]}')
curl -sS -w '\n%{http_code}' https://api.anthropic.com/v1/messages \
  -H "x-api-key: $(doppler secrets get ANTHROPIC_API_KEY -p soleur -c dev --plain)" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD"
```

The second command is **verified** against `api.anthropic.com`'s published `/v1/messages` shape (see `https://platform.claude.com/docs/en/api/messages`, anthropic-version `2023-06-01`). Model name `claude-haiku-4-5` is cited verbatim from the issue body (the full dated form `claude-haiku-4-5-20251001` also works — we use the aliased form since it tracks haiku 4.5 forward).

<!-- verified: 2026-04-21 source: https://platform.claude.com/docs/en/api/messages -->

## Risks

- **Risk:** Anthropic changes the cap-error body phrasing. Detection silently fails → we go back to the pre-2715 behavior.
  - **Mitigation:** The `else` branch logs HTTP code + first 500 chars of body at `::error::` level. A changed phrasing would show up as "unexpected 400" in workflow logs, which ops sees fast (it's also a `notify-ops-email` trigger). Easy to update the grep.
- **Risk:** Preflight itself is flaky (network blip). Today's claude step has the same exposure — if `api.anthropic.com` is unreachable, the claude step fails anyway. Preflight adds 1 more failure mode but it's strictly smaller surface (1 API call vs. N).
  - **Mitigation:** Accept. No retry added (KISS).
- **Risk:** 15-file duplicate-edit invites copy-paste bugs (per AGENTS.md `cq-workflow-pattern-duplication-bug-propagation`: "When extending a GitHub Actions workflow by duplicating an existing job's pattern, scan the source for known-buggy idioms before duplicating").
  - **Mitigation:** Diff-review during implementation — each workflow edit must match the Shape A or Shape B template verbatim except for the single job-name token. Before duplicating, grep each source workflow for (a) piped `| while` loops swallowing counter updates, (b) missing `set -uo pipefail`, (c) unguarded `gh api` calls — none of these appear in the preflight job itself (pure `curl`), but the patch shape is identical across 15 files and any drift will reproduce 15×. The PR review (multi-agent) will cross-check each workflow diff against the canonical Shape A/B. Post-rollout verification: `diff <(sed -n '/jobs:/,/preflight/p' <file>) <canonical-template>` should show only the job-name token differing.
- **Risk:** A new scheduled workflow is added post-merge that forgets the preflight wiring.
  - **Mitigation:** Deferred to follow-up issue (rule-audit check). Meanwhile, documented in plan.

## Deferrals

Per `wg-when-deferring-a-capability-create-a`, file these immediately after plan approval:

1. **Daily "today we skipped N cap-day Claude runs" digest email.** Milestone: Post-MVP / Later. Re-eval: if cap-exhaustion recurs and the silent skip stops being visible enough.
2. **Rule-audit check: flag workflows using `anthropics/claude-code-action` without `anthropic-preflight` earlier.** Milestone: Post-MVP / Later. Re-eval: after 1st post-merge workflow is added without the guard.
3. **Pin `scheduled-roadmap-review.yml` claude-code-action from `@v1` to SHA.** Milestone: Post-MVP / Later. Re-eval: combined with next `cq-claude-code-action-pin-freshness` sweep.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Infrastructure/CI change. No architectural implications — composite action pattern is already established (`notify-ops-email` precedent). No new dependencies. No new secrets. Negligible cost impact ($<0.001/month). The main risk is the 15-file duplication; mitigated by the Shape A/B template discipline. No CPO/CMO/CRO/etc. signal — no user-facing impact, no business logic, no copy, no pricing.

Product domain: **NONE** — no user-facing pages, no UX surfaces, no interactive flows. Ops-only hardening.

## Post-Generation Reminders

- [ ] `npx markdownlint-cli2 --fix` on this plan file before committing.
- [ ] Browser automation check: no manual browser steps; all verification is `gh` CLI.
- [ ] Deferral tracking check: 3 deferrals listed above — must be filed as issues before PR ships.
- [ ] CLI-verification gate: all CLI invocations (`gh workflow run`, `actionlint`, `yamllint`, `curl`, `jq`) are standard POSIX/repo tools; the `curl` invocation is annotated with `<!-- verified: 2026-04-21 source: ... -->`.
