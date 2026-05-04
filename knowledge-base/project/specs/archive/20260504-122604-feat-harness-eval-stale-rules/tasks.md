# Tasks: feat-harness-eval-stale-rules

Derived from `knowledge-base/project/plans/2026-05-04-feat-rule-prune-retirement-proposal-plan.md` (post-review).
Closes #3120; refs #3128.

## Phase 1 — Script changes (`scripts/rule-prune.sh`)

1.1. Add `--propose-retirement` flag to CLI parsing. Define interaction explicitly: `--propose-retirement --dry-run` honored (no append, sentinels still emit); flag is no-op when default per-rule-issue mode is intended.
1.2. Add helper `_load_retired_ids()` with awk parser stripping leading + trailing whitespace and internal-whitespace in the id field; tolerates malformed rows by extracting only the id segment.
1.3. After candidate discovery, branch on `--propose-retirement`. Two-pass design:
   1.3.1. **First pass (no writes):** filter candidates against (a) `^hr-` prefix → log skip, (b) already-retired set → log skip, (c) duplicate-id-within-candidates seen-set → log skip, (d) `_RULE_ID_RE` validation → log warning. Sanitize `prefix` field for CR/LF; warn if mutated. Detect hook/skill enforcement. Push survivors into `pending_lines` array.
   1.3.2. **Second pass (single-redirect atomic write):** if `pending_lines` non-empty AND `--dry-run` not set, append all in one `printf >> file` call.
   1.3.3. Emit stdout sentinels `::rule-prune-pr-title::...` and `::rule-prune-pr-body::...` (each on its own line, both `tr -d '\n\r'`-stripped) when ≥1 candidate proposed; suppress sentinels when 0.
1.4. Track only two counters: `appended` and `hook_enforced`. Skip cases log inline without tally.
1.5. Update top-of-file comment block to document `--propose-retirement` and the `::rule-prune-pr-{title,body}::` sentinel contract.
1.6. Update `knowledge-base/project/specs/feat-harness-eval-stale-rules/spec.md` FR1 + TR3 to reflect the composite-action delegation, single-line PR body, branch-name shape, and stdout-sentinel contract.

## Phase 2 — Tests (`tests/commands/test-sync-rule-prune.sh`)

2.1. Extend the existing fake-gh harness file with new test cases. Each test isolates state via `RULE_METRICS_ROOT="$(mktemp -d)"` matching the existing fixture pattern.
2.2. Implement T1 (no candidates), T2 (one non-hr), T3 (one hr-*), T4 (already-retired), T5a (mixed counts), T5b (mixed title format), T8 (schema mismatch), T9 (re-run idempotency), T10 (duplicate candidate id), T11 (`--dry-run` honored).
2.3. Verify all tests pass with `bash tests/commands/test-sync-rule-prune.sh`.

## Phase 3 — Scheduled workflow (`.github/workflows/scheduled-rule-prune.yml`)

3.1. Create the workflow file: cron `0 9 1 1,4,7,10 *` + `workflow_dispatch`; concurrency group `scheduled-rule-prune` with `cancel-in-progress: false`; `timeout-minutes: 5`; permissions `checks: write, contents: write, pull-requests: write`.
3.2. Step `prune`: capture script stdout, `sed -n` extract sentinels, set `pr_title`/`pr_body` GitHub outputs (multiline-EOF), set `no_candidates` flag, defensive `git diff --quiet -- scripts/retired-rule-ids.txt` check on the no-candidates path.
3.3. Step `Open retirement-proposal PR`: gated on `steps.prune.outputs.no_candidates == 'false'`, calls `./.github/actions/bot-pr-with-synthetic-checks` with `add-paths: scripts/retired-rule-ids.txt`, branch-prefix `ci/rule-prune-retire-`, commit message, title prefix from output, body from output, `change-summary`, `gh-token: ${{ github.token }}`.
3.4. Step `Email notification (failure)`: gated on `if: failure()`, calls `./.github/actions/notify-ops-email`.
3.5. Validate workflow YAML pre-PR: `gh workflow view scheduled-rule-prune.yml --yaml > /dev/null` (post-push to validate against the API).

## Phase 4 — Post-merge verification

4.1. After merge: `gh workflow run scheduled-rule-prune.yml`.
4.2. Poll: `gh run view <id> --json status,conclusion` until completed.
4.3. Verify either (a) clean exit with `No retirement candidates` log AND no PR opened (expected — no rules >=26w stale yet) OR (b) one PR opened with single-line body, correct title, only `scripts/retired-rule-ids.txt` modified, no `hr-*` ids leaked.
4.4. Confirm #3120 closed by merge; #3128 (D1 deferral) remains open in milestone "Post-MVP / Later".

## Acceptance gate

All Phase 1-4 tasks completed; all Pre-merge and Post-merge acceptance criteria from the plan satisfied.
