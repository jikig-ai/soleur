---
title: "feat: scheduled quarterly rule-prune retirement-proposal PR"
date: 2026-05-04
issue: 3120
related_issues:
  - 3128
related_brainstorms:
  - knowledge-base/project/brainstorms/2026-05-04-harness-eval-stale-rules-brainstorm.md
related_specs:
  - knowledge-base/project/specs/feat-harness-eval-stale-rules/spec.md
related_prs:
  - 3123
type: feature
status: planned
requires_cpo_signoff: false
---

# feat: scheduled quarterly rule-prune retirement-proposal PR

## Overview

Add `--propose-retirement` flag to `scripts/rule-prune.sh` and a quarterly scheduled workflow `.github/workflows/scheduled-rule-prune.yml` that opens ONE PR per quarter appending zero-firing AGENTS.md rules to `scripts/retired-rule-ids.txt`. Closes the C2 loop from issue #3120.

D1 (corpus replay) is deferred to #3128 with an evidence gate (≥2 incidents). Out of scope here.

This is a 4-file delta on top of the shipped `rule-utility-scoring` infra (#2210):

- `scripts/rule-prune.sh` — extend with `--propose-retirement`.
- `.github/workflows/scheduled-rule-prune.yml` — new quarterly workflow.
- `scripts/rule-prune.test.sh` (new) OR extend `tests/commands/test-sync-rule-prune.sh` — coverage for the new flag.
- `knowledge-base/project/learnings/` — sharp-edge entry only if the first quarterly run surfaces a surprise (per `wg-every-session-error-must-produce-either` discoverability exit; not a pre-emptive write).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR1: script "writes a single PR" | The repo has a composite action `.github/actions/bot-pr-with-synthetic-checks` that already does PR creation + synthetic checks for `rule-metrics-aggregate.yml`. Reusing it is strictly simpler than re-implementing in `rule-prune.sh`. | Refactor script's role: `--propose-retirement` writes the file delta + a single-line PR-body summary; the workflow calls the composite action for git/PR work. Update spec FR1 wording at plan-finalize time. |
| FR2 cron `0 9 1 1,4,7,10 *` | The composite action appends `YYYY-MM-DD` to branch names (not `YYYY-Qn` as spec implied). | Branch becomes `ci/rule-prune-retire-2026-07-01` (not `chore/rule-prune-retire-2026-Q3`). Spec's branch-name shape was advisory; the date suffix from the action is fine. |
| FR1 skip already-retired by parsing `retired-rule-ids.txt` | The Python `load_retired_ids()` in `scripts/lint-rule-ids.py` is the canonical parser, but bash can do the parse with `awk` cleanly. No need to add a Python dep to `rule-prune.sh`. | Implement bash-side parse: `awk '/^[^#]/ { sub(/^[ \t]+/,""); sub(/[ \t]+$/,""); if ($0=="") next; split($0,a,"[ \t]*\\|[ \t]*"); gsub(/[ \t]+/,"",a[1]); if (a[1]!="") print a[1] }'` (leading + trailing whitespace stripped, empty lines after strip skipped, id field stripped of internal whitespace). |
| FR1 "skip `hr-*`" | `lint-rule-ids.py` already enforces hr-* immutability via `HR_RETIREMENT_ALLOWLIST`. Adding hr-X to `retired-rule-ids.txt` without also editing `HR_RETIREMENT_ALLOWLIST` AND removing hr-X from AGENTS.md fails the lint. | Confirms the spec's hard-no on hr-*. Automation only does the `retired-rule-ids.txt` append; the AGENTS.md + allowlist edits require human judgment. Skip `^hr-` regardless of allowlist state. |
| TR3 PR body via `gh pr create --body-file` | Composite action requires PR body to be **single-line** (action validates and rejects newlines). | PR body becomes a single summary line; per-rule rationale lives in the diff itself (each appended line carries `<id> | YYYY-MM-DD | PR #<N> | scheduled by rule-prune (<rule-text-prefix-30chars>)`). |
| Hook-/skill-enforced "Manual review required" section in PR body | Single-line body cap blocks this. | Inline the warning into the PR title for the rare case (`feat(rule-prune): propose retirement of 3 rules (1 hook-enforced — review carefully)`); reviewers see it before opening. Each appended line's breadcrumb still names hook/skill enforcement so the diff carries the detail. |

## Hypotheses

Not applicable — no SSH/network/connectivity symptom in this plan. Phase 1.4 trigger keywords did not match.

## Files to Edit

- `scripts/rule-prune.sh` — add `--propose-retirement` flag handler, retired-id parser, hr-* filter, file append, PR-body-summary writer.
- `tests/commands/test-sync-rule-prune.sh` OR `scripts/rule-prune.test.sh` — extend with `--propose-retirement` test cases. Decision deferred to TR2 below; lean toward extending `tests/commands/test-sync-rule-prune.sh` (existing fake-gh harness already in place).
- `scripts/retired-rule-ids.txt` — no edits in this PR, but the workflow's first run will append to it (verified by review, not by the PR that ships the workflow).
- `knowledge-base/project/specs/feat-harness-eval-stale-rules/spec.md` — fold in the FR1/TR3 reconciliation deltas after this plan is reviewed; spec stays canonical.

## Files to Create

- `.github/workflows/scheduled-rule-prune.yml` — quarterly cron workflow.

## Implementation Phases

### Phase 1: Script changes (1-2h)

1. Add CLI parsing for `--propose-retirement`. Define interaction with existing flags explicitly:
   - `--propose-retirement --dry-run`: HONORED. Skip the file append, still emit the stdout summary (so a developer can locally inspect what the workflow would produce). Document inline.
   - `--propose-retirement --weeks=N`: standard, N drives the cutoff.
   - Flag changes the post-candidate-discovery branch only — default per-rule-issue mode is unaffected when the flag is absent.

2. Add helper `_load_retired_ids()`:
   ```bash
   _load_retired_ids() {
     local file="${RULE_METRICS_ROOT:-$ROOT}/scripts/retired-rule-ids.txt"
     [[ -f "$file" ]] || return 0
     awk '/^[^#]/ {
       sub(/^[ \t]+/,""); sub(/[ \t]+$/,"")
       if ($0 == "") next
       split($0, a, "[ \t]*\\|[ \t]*")
       gsub(/[ \t]+/, "", a[1])
       if (a[1] != "") print a[1]
     }' "$file"
   }
   ```
   Strips leading/trailing whitespace AND internal whitespace in the id field; tolerates malformed rows missing the `|` delimiter (id-only field still extracted).

3. After candidate discovery, if `--propose-retirement` is set, branch into a new code path. **Write order is load-bearing — assemble the entire stdout summary AND validate every candidate BEFORE any file mutation.**
   - Build the already-retired set: `mapfile -t retired < <(_load_retired_ids); declare -A retired_set; for r in "${retired[@]}"; do retired_set["$r"]=1; done`.
   - Initialize an in-loop seen-set: `declare -A appended_set` to guard against duplicate-id within `rule-metrics.json` candidates.
   - **First pass — validate and decide, no writes:** for each candidate tuple `(id, section, first_seen, prefix)`:
     - Skip if `id` matches `^hr-` → log `[skip] hr-* retirement requires lint-rule-ids.py edit, not automated: $id` and continue.
     - Skip if `${retired_set[$id]:-}` is set → log `[skip] already retired: $id` and continue.
     - Skip if `${appended_set[$id]:-}` is set → log `[skip] duplicate candidate id (rule-metrics drift): $id` and continue.
     - Validate `id` against `_RULE_ID_RE`; on failure log a warning and continue.
     - Sanitize `prefix` by stripping CR/LF (`prefix="${prefix//[$'\n\r']/ }"`). If the sanitized prefix differs from the original, log a warning so AGENTS.md authors can fix the rule text.
     - Detect hook/skill enforcement: `is_he=0; if [[ "$prefix" == *"[hook-enforced"* || "$prefix" == *"[skill-enforced"* ]]; then is_he=1; fi`.
     - Push the formatted line into a `pending_lines` array (NOT to disk yet); update counters `appended` and `hook_enforced`.
     - Mark `appended_set[$id]=1`.
   - If 0 in `pending_lines`, log `No retirement candidates for >=${WEEKS}w.` and exit 0 (no stdout sentinels emitted; workflow's `no_candidates` branch fires).
   - **Second pass — atomic write:** if `--dry-run` is NOT set, append all lines from `pending_lines` to `$ROOT/scripts/retired-rule-ids.txt` in a single `printf '%s\n' "${pending_lines[@]}" >> "$file"`. Single redirect = atomic vs. mid-loop signal interruption.
   - Emit stdout sentinels (consumed by the workflow into `$GITHUB_OUTPUT`):
     ```
     ::rule-prune-pr-title::feat(rule-prune): propose retirement of N rules (M hook/skill-enforced)
     ::rule-prune-pr-body::Quarterly rule-prune retirement proposal: N rules with fire_count=0 over >=26 weeks. Per-rule rationale in the diff. M flagged hook-/skill-enforced — review them carefully. Spec: knowledge-base/project/specs/feat-harness-eval-stale-rules/spec.md.
     ```
   - Both lines `tr -d '\n\r'` defensively before emit (in case sanitization missed a path).

4. Counters tracked: only `appended` and `hook_enforced`. Skip cases log inline without tally — counts derivable from log scrub if needed.

5. Update top-of-file comment block to document `--propose-retirement`.

### Phase 2: Tests (1h)

Extend `tests/commands/test-sync-rule-prune.sh` with new cases. The propose-retirement codepath does NOT call gh, so no new fake is needed. **Each test isolates state via a per-T `RULE_METRICS_ROOT="$(mktemp -d)"` matching the existing fixture pattern in `scripts/rule-metrics-aggregate.test.sh`.**

- **T1:** `--propose-retirement` with no candidates → exit 0, stdout has `No retirement candidates`, no file changes, no sentinel lines emitted.
- **T2:** `--propose-retirement` with one non-hr candidate → `retired-rule-ids.txt` gains exactly one line in canonical format; both sentinel lines on stdout (`::rule-prune-pr-title::...`, `::rule-prune-pr-body::...`).
- **T3:** `--propose-retirement` with one `hr-*` candidate → no append; stdout has `[skip] hr-*` log; exit 0; no sentinels.
- **T4:** `--propose-retirement` with one already-retired id (id present in fixture `retired-rule-ids.txt`) → no append; stdout has `[skip] already retired` log; exit 0.
- **T5a:** `--propose-retirement` mixed (1 new non-hr, 1 hr-, 1 already-retired, 1 hook-enforced non-hr) → exactly 2 appends; appended lines have correct format; counts logged.
- **T5b:** Same fixture as T5a → assert title sentinel matches `feat(rule-prune): propose retirement of 2 rules (1 hook/skill-enforced)`.
- **T8:** Schema mismatch on `rule-metrics.json` (`schema: 99`) → exit 3 with existing schema-error message; `--propose-retirement` does not bypass the gate.
- **T9 (idempotency under re-run):** Run T2 once → captures appended id. Run again with the same fixture (so the appended line is now in `retired-rule-ids.txt`) → second run logs `[skip] already retired`, exits 0, no second append. Asserts file ends with same line count after second run.
- **T10 (duplicate-candidate guard):** Synthetic `rule-metrics.json` listing the same `wg-foo` twice (rare but possible under aggregator drift) → first hit appended, second hit logs `[skip] duplicate candidate id`, single-line append.
- **T11 (`--dry-run` honored):** `--propose-retirement --dry-run` with one candidate → no file write; stdout sentinels still emitted (so operator can preview).

Run with `bash tests/commands/test-sync-rule-prune.sh`. The existing runner is bash-native; do NOT add a new framework (per Sharp Edge: "verify the framework is actually installed").

**Tests dropped from the spec's original 8:** T6 (malformed `retired-rule-ids.txt`) and T7 (empty file). Rationale: `lint-rule-ids.py` is hook-enforced via lefthook on every commit; a malformed `retired-rule-ids.txt` would never reach a workflow run. The new awk parser tolerates malformed rows defensively in the `_load_retired_ids` helper itself, so the tolerance is still tested via T4 (any malformed line is just absent from the parsed set, which is the safe degradation).

### Phase 3: Workflow (30m)

Create `.github/workflows/scheduled-rule-prune.yml`:

```yaml
name: "Scheduled: Rule Prune Retirement Proposal"

on:
  schedule:
    - cron: '0 9 1 1,4,7,10 *'   # 09:00 UTC, 1st of Jan/Apr/Jul/Oct
  workflow_dispatch:

concurrency:
  group: scheduled-rule-prune
  cancel-in-progress: false

permissions:
  checks: write
  contents: write
  pull-requests: write

jobs:
  propose:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Checkout repository
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        # rule-metrics.json is committed; no need to run aggregator here.

      - name: Run rule-prune in propose-retirement mode
        id: prune
        run: |
          set -eo pipefail
          # Capture stdout so we can extract sentinels AND surface the log.
          out=$(bash scripts/rule-prune.sh --weeks=26 --propose-retirement)
          printf '%s\n' "$out"
          # Extract sentinels. If absent, no candidates were proposed.
          PR_TITLE=$(printf '%s\n' "$out" | sed -n 's/^::rule-prune-pr-title:://p' | head -n 1 | tr -d '\n\r')
          PR_BODY=$(printf '%s\n' "$out" | sed -n 's/^::rule-prune-pr-body:://p' | head -n 1 | tr -d '\n\r')
          if [[ -z "$PR_TITLE" || -z "$PR_BODY" ]]; then
            echo "no_candidates=true" >> "$GITHUB_OUTPUT"
            # Defensive: ensure no stray retired-rule-ids.txt mutation slipped through.
            if ! git diff --quiet -- scripts/retired-rule-ids.txt; then
              echo "::error::retired-rule-ids.txt was modified but no sentinels emitted — partial-failure recovery"
              exit 1
            fi
            exit 0
          fi
          echo "no_candidates=false" >> "$GITHUB_OUTPUT"
          {
            printf 'pr_title<<EOF\n%s\nEOF\n' "$PR_TITLE"
            printf 'pr_body<<EOF\n%s\nEOF\n' "$PR_BODY"
          } >> "$GITHUB_OUTPUT"

      - name: Open retirement-proposal PR
        if: steps.prune.outputs.no_candidates == 'false'
        uses: ./.github/actions/bot-pr-with-synthetic-checks
        with:
          add-paths: scripts/retired-rule-ids.txt
          branch-prefix: ci/rule-prune-retire-
          commit-message: "chore(rule-prune): propose retirement of stale rules"
          pr-title-prefix: ${{ steps.prune.outputs.pr_title }}
          pr-body: ${{ steps.prune.outputs.pr_body }}
          change-summary: "Stale-rule retirement proposal — appends to retired-rule-ids.txt only"
          gh-token: ${{ github.token }}

      - name: Email notification (failure)
        if: failure()
        uses: ./.github/actions/notify-ops-email
        with:
          subject: '[FAIL] Scheduled: Rule Prune Retirement Proposal failed'
          body: '<p><strong>Scheduled: Rule Prune Retirement Proposal</strong> failed.</p><p><a href="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}">View run</a></p>'
          resend-api-key: ${{ secrets.RESEND_API_KEY }}
```

### Phase 4: Post-merge verification (5m)

Per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies-a`:

1. `gh workflow run scheduled-rule-prune.yml` (manual trigger on `main` post-merge).
2. Poll: `gh run view <id> --json status,conclusion`.
3. Verify either: (a) clean exit with "No retirement candidates" log AND no PR opened (expected if no rules >=26w stale yet — 26 weeks ago is November 2025, before incidents.sh shipped), OR (b) one PR opened with the correct shape.

Likely outcome of first run: case (a) — `incidents.sh` shipped 2026-04-15 (#2210), so no rule has yet had 26 weeks of zero-firing data. The first eligible run is approximately Q4 2026 (October 1, 2026 cron). The workflow's correctness verification is done by `workflow_dispatch` post-merge, not by waiting for the natural cron.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `scripts/rule-prune.sh --propose-retirement` flag implemented per Phase 1.
- [ ] All Phase 2 test cases pass via `bash tests/commands/test-sync-rule-prune.sh`.
- [ ] `.github/workflows/scheduled-rule-prune.yml` validates via `gh workflow view scheduled-rule-prune.yml --yaml > /dev/null` (syntax check) — verified before opening PR.
- [ ] `scripts/lint-rule-ids.py` continues to pass (no edits to the linter; the propose-retirement automation respects existing `HR_RETIREMENT_ALLOWLIST` discipline by not appending hr-* at all).
- [ ] Spec `feat-harness-eval-stale-rules/spec.md` updated to reflect FR1/TR3 reconciliation (composite action, single-line PR body, branch shape).
- [ ] PR body has `Closes #3120` and `Refs #3128`.
- [ ] No edits to `AGENTS.md`, `retired-rule-ids.txt`, or `lint-rule-ids.py` in this PR — pure new-feature surface.

### Post-merge (operator)

- [ ] `gh workflow run scheduled-rule-prune.yml` triggered after merge.
- [ ] Run completes with `conclusion=success`.
- [ ] Either no PR opened (no candidates) OR one PR opened with single-line body, correct title, and only `scripts/retired-rule-ids.txt` modified.
- [ ] If a PR was opened, verify each appended line matches the canonical format and that no `hr-*` ids leaked through.
- [ ] Issue #3120 closed by merge (`Closes #3120` in PR body).
- [ ] Issue #3128 (D1 deferral) remains open with milestone `Post-MVP / Later`.

## Test Scenarios

(Mirrors Phase 2 — this is the contract spec-flow-analyzer reads. Each test isolates state via `RULE_METRICS_ROOT="$(mktemp -d)"`.)

| # | Scenario | Setup | Assert |
|---|---|---|---|
| T1 | No candidates | `rule-metrics.json` with all rules `fire_count > 0` | exit 0; no file edits; no sentinels emitted; stdout contains `No retirement candidates` |
| T2 | One non-hr candidate | rule `wg-foo`, `fire_count=0`, `first_seen` >26w ago | `retired-rule-ids.txt` gains 1 line in canonical format; both `::rule-prune-pr-title::` and `::rule-prune-pr-body::` sentinels on stdout |
| T3 | One hr-\* candidate | `hr-bar`, fire_count=0, first_seen >26w | no file edit; stdout has `[skip] hr-*` log; no sentinels |
| T4 | Already-retired id | `wg-baz` is in fixture `retired-rule-ids.txt`; matches >=26w predicate | no append; stdout has `[skip] already retired: wg-baz` |
| T5a | Mixed (counts) | 1 new non-hr, 1 hr-, 1 already-retired, 1 hook-enforced non-hr | exactly 2 appends in canonical format |
| T5b | Mixed (title format) | Same fixture as T5a | title sentinel = `feat(rule-prune): propose retirement of 2 rules (1 hook/skill-enforced)` |
| T8 | Schema mismatch | `rule-metrics.json` has `schema: 99` | exit 3 with existing schema-error; `--propose-retirement` does not bypass |
| T9 | Idempotency under re-run | T2 run once, then re-run with appended file as fixture | second run: `[skip] already retired`, exit 0, file line count unchanged |
| T10 | Duplicate candidate id | `rule-metrics.json` lists `wg-foo` twice (synthetic aggregator drift) | first hit appended, second logs `[skip] duplicate candidate id`, single append |
| T11 | `--dry-run` honored | `--propose-retirement --dry-run` with one candidate | no file write; sentinels still emitted (preview mode) |

T6 (malformed `retired-rule-ids.txt`) and T7 (empty file) dropped — the awk parser degrades safely (any malformed row is absent from the parsed set), and `lint-rule-ids.py` is hook-enforced upstream so production data cannot reach a malformed state.

## Domain Review

Carried forward from brainstorm `2026-05-04-harness-eval-stale-rules-brainstorm.md` per Phase 2.5 brainstorm carry-forward rule.

**Domains relevant:** Engineering (CTO — current task topic), Product (CPO), Marketing (CMO).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** Small, contained delta on shipped `rule-utility-scoring` infra. Architectural concern is keeping the new path consistent with `lint-rule-ids.py`'s `_RULE_ID_RE` and `HR_RETIREMENT_ALLOWLIST` semantics — addressed by NOT auto-appending hr-* regardless of allowlist state. Schema contract on `rule-metrics.json` already gated by `SCHEMA_VERSION`. No drift introduced.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** Smallest reviewable C2 delta. D1 deferred to #3128 with evidence gate. Recommended scope cut: ship Phase 1+2+3+4 only, no scope expansion to monthly tier. PR-as-tracking-artifact is correct; no separate tracking issue.

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward).
**Assessment:** Internal harness tooling. **Blog-eligible** post-ship — Fowler/Schmid/Liu thread audience overlaps Soleur's agent-tooling positioning. Trigger external content **after** the first eval-driven retirement merges (acceptance criterion). No README/docs change at ship; no pre-announcement.

### Product/UX Gate

**Tier:** none (no user-facing surface; CI workflow + bash script).

## User-Brand Impact

Carried forward from brainstorm — `USER_BRAND_CRITICAL=false`.

**If this lands broken, the user experiences:** No direct user impact. Failure mode is a non-running quarterly workflow (no PR opened, no rules retired) — silent no-op. Operator notices via `gh workflow list` or via the absence of quarterly retirement PRs. Email-on-failure is wired via the existing `notify-ops-email` action.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — workflow operates on `retired-rule-ids.txt` (committed harness file), not user data. No secrets accessed beyond `GITHUB_TOKEN`.

**Brand-survival threshold:** none. **Reason:** Internal harness tooling; no user-facing surface; no credential, payment, or data-isolation path.

## Open Code-Review Overlap

None. Queried 29 open `code-review`-labeled issues against `scripts/rule-prune.sh`, `tests/commands/test-sync-rule-prune.sh`, `scripts/retired-rule-ids.txt`, `scripts/rule-metrics-aggregate.sh`, and `.github/workflows/scheduled-rule-prune.yml` — zero overlapping references in issue bodies.

## Risks

1. **Composite action fails mid-flight, leaving file appended without a PR.** If `bot-pr-with-synthetic-checks` breaks after the script's append landed but before push/PR-create succeeded, the next quarterly run reads the unmerged appends from the dangling branch's parent commit on `main` — but `main` is unchanged because nothing pushed. The next run will re-discover the same candidates and re-append. The `git diff --quiet -- scripts/retired-rule-ids.txt` defensive check in workflow step `prune` (Phase 3) catches the case where the script appended but the workflow then exited the no-candidate branch (which would never happen with the new write-order, but is defended anyway). Operator cleans dangling branches via `git push origin --delete ci/rule-prune-retire-<date>`. Same failure mode applies to `rule-metrics-aggregate.yml` and has not surfaced in 3 weeks of operation.

2. **Single-line PR body limits reviewer context.** Reviewers must read the diff for per-rule rationale. Mitigated by (a) per-line breadcrumb in the appended lines, (b) hook-/skill-enforced count in the PR title, (c) the synthetic-check summary line.

3. **Back-to-back `workflow_dispatch` re-runs hit branch-already-exists.** First run creates `ci/rule-prune-retire-2026-07-01`. Second run on the same date with the original PR not yet merged: `git checkout -b` in the composite action will fail (branch already exists locally on the runner — but each run is a fresh runner, so locally fine; the conflict is on push: `git push -u origin "$BRANCH"` would either non-fast-forward-fail or silently force-push depending on action behavior). Acceptable: post-merge verification runs once; cron is quarterly. T9 covers the same-day re-run idempotency at the script level. Operator runs at most one `workflow_dispatch` per merge.

## Sharp Edges (carried into this plan)

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with `none` threshold + reason, per the Step 3 rule.
- The composite action `bot-pr-with-synthetic-checks` requires single-line PR bodies. Multi-line content fails action validation. This plan's body design respects that; future workflow callers must also check.
- Branch name suffix is `YYYY-MM-DD` (composite action), not `YYYY-Qn` (spec wording). Adjusted in the spec reconciliation table.
- **Cron drift / first eligible run lag.** `incidents.sh` shipped 2026-04-15; the 26-week threshold means no rule is retire-eligible until ~2026-10-15. The October 1, 2026 cron produces a no-op log; the first non-empty run is approximately January 1, 2027. `workflow_dispatch` post-merge is the only way to verify wiring before then.
- **Stdout sentinels are the workflow contract.** Any future change to the `::rule-prune-pr-title::` / `::rule-prune-pr-body::` prefix must update `.github/workflows/scheduled-rule-prune.yml` step `prune` in lockstep. Treat these as a versioned protocol between script and workflow — a comment block in both files names the other.

## Resume / handoff

Plan ready at `knowledge-base/project/plans/2026-05-04-feat-rule-prune-retirement-proposal-plan.md`. Spec at `knowledge-base/project/specs/feat-harness-eval-stale-rules/spec.md`. Branch `feat-harness-eval-stale-rules`, worktree `.worktrees/feat-harness-eval-stale-rules/`, draft PR #3123. Closes #3120, refs #3128.
