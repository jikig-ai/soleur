# Feature: Quarterly stale-rule retirement-proposal PR (C2-finish)

## Problem Statement

`scripts/rule-prune.sh` (shipped via #2210) surfaces AGENTS.md rules with `fire_count=0` as GitHub issues, but:

1. The script is never invoked on a schedule — the loop only closes when an operator runs `/soleur:sync rule-prune` manually.
2. The "propose retirement" automation step (commit ID to `scripts/retired-rule-ids.txt`) is missing — humans must hand-edit the file after reading each issue.

Per issue #3120 (scoped down to C2 after CPO assessment), close those two gaps with the smallest reviewable delta.

D1 (regression eval suite that replays new rules against historical `Closes #N` diffs to compute would-have-caught rates) is deferred to a separate issue, blocked on real evidence (≥2 incidents where a shipped rule provably failed). Goodhart and corpus-contamination problems make the metric speculative today. See brainstorm `2026-05-04-harness-eval-stale-rules-brainstorm.md` for the full deferral rationale.

## Goals

- Close the C2 loop: zero-hit rules surface as a reviewable artifact on a cadence, without operator action.
- The retirement step (appending to `retired-rule-ids.txt`) is automated; review remains human.
- Retiring `hr-*` rules stays hard-blocked (per `cq-rule-ids-are-immutable` and the hr-rule-retirement-guard, brainstorm 2026-04-24).
- One PR per quarter is the consolidated tracking artifact — no separate tracking issue.
- Existing 8-week manual `rule-prune.sh` path stays usable for ad-hoc inspection.

## Non-Goals

- D1 corpus-replay suite (deferred to a new issue, evidence-gated).
- 60-day "flag" tier with monthly tracking issue (Approach B). Reconsider after 1-2 quarters of retirement-PR data.
- Auto-merge or auto-close on the retirement PR. Human review required.
- Removing rule text from AGENTS.md in the same PR. Only `retired-rule-ids.txt` is appended; rule-body removal is a separate human PR.
- Slack/Discord notifications. The PR is the notification.
- Automation for `hr-*` rules. The script must explicitly NOT append `hr-*` ids to `retired-rule-ids.txt`; surface them in PR body as "blocked-from-automation: edit linter to retire."
- Running on schedule from a forked PR (no inputs from forks; cron-only or operator `workflow_dispatch`).

## Functional Requirements

### FR1: `--propose-retirement` flag on `rule-prune.sh`

When invoked with `--propose-retirement`:

- Compute candidates the same way as the existing flow: `fire_count=0` AND `first_seen >= cutoff` (cutoff from `--weeks`).
- Two-pass design (per plan + spec-flow review):
  1. **First pass (validate, no writes):** for each candidate, skip if `^hr-` (hr-* retirement requires `lint-rule-ids.py` edit, not automated), skip if already present in `scripts/retired-rule-ids.txt`, skip if duplicate-id within candidates set, validate against `_RULE_ID_RE`, sanitize CR/LF in `rule_text_prefix`. Push survivors to a `pending_lines` array; track `appended` and `hook_enforced` counters.
  2. **Second pass (atomic write):** if `pending_lines` non-empty AND `--dry-run` not set, append all lines to `scripts/retired-rule-ids.txt` in a single redirect (`printf >> file`).
- Each appended line uses canonical format: `<id> | YYYY-MM-DD | - | scheduled by rule-prune (first_seen=<ts>, fire_count=0, hook_enforced=<0|1>)`. The `-` placeholder for PR # is intentional — the actual PR number is in the breadcrumb's "scheduled by" trail and the PR title; backfilling would require a second commit on the proposal branch which adds churn for no review value.
- **Stdout sentinels** (consumed by the calling workflow into `$GITHUB_OUTPUT`):
  ```
  ::rule-prune-pr-title::feat(rule-prune): propose retirement of N rules (M hook/skill-enforced)
  ::rule-prune-pr-body::Quarterly rule-prune retirement proposal: N rules with fire_count=0 over >=W weeks. Per-rule rationale in the diff. M flagged hook-/skill-enforced — review them carefully. Spec: knowledge-base/project/specs/feat-harness-eval-stale-rules/spec.md.
  ```
  Both lines are `tr -d '\n\r'`-stripped before emission. Sentinels are emitted whenever `appended ≥ 1` (including under `--dry-run`, so an operator can preview what a real run would propose).
- The PR itself is opened by `.github/workflows/scheduled-rule-prune.yml` calling the existing `.github/actions/bot-pr-with-synthetic-checks` composite action with the sentinels as title/body inputs. The composite action handles git config, branch creation (suffix `YYYY-MM-DD`, e.g., `ci/rule-prune-retire-2026-07-01`), commit, push, PR creation, synthetic check runs, and auto-merge queueing.
- Idempotency at the script level: re-running on the same fixture skips already-appended ids via `_load_retired_ids` parse of the on-disk file (covered by test T9). Branch-exists collisions on back-to-back `workflow_dispatch` re-runs are handled by the composite action's existing logic; operators run at most one `workflow_dispatch` per merge.
- `--propose-retirement --dry-run` honored: no file write, sentinels still emitted (preview mode).

### FR2: Quarterly scheduled workflow

- File: `.github/workflows/scheduled-rule-prune.yml`.
- Cron: `0 9 1 1,4,7,10 *` (09:00 UTC, 1st of Jan/Apr/Jul/Oct).
- Trigger: `schedule` + `workflow_dispatch`.
- Job: checkout → `bash scripts/rule-prune.sh --weeks=26 --propose-retirement`.
- Permissions: `contents: write`, `pull-requests: write`, `issues: write`. (Issues kept for forward-compat if FR3 is added.)
- Concurrency group: `scheduled-rule-prune` (cancel-in-progress: false).
- Timeout: 5 minutes.
- Pattern reference: `.github/workflows/rule-metrics-aggregate.yml`.

### FR3: Existing 8-week manual path unchanged

- `/soleur:sync rule-prune` and `bash scripts/rule-prune.sh --weeks=8` continue to file per-rule issues with no behavior change.
- The `--propose-retirement` flag is opt-in only; it does NOT alter the default codepath.

## Technical Requirements

### TR1: Idempotency and re-run safety

- Skip ids already in `retired-rule-ids.txt` (parse uncommented lines, extract first column).
- Skip if branch `chore/rule-prune-retire-<YYYY-Qn>` exists OR an open PR with the canonical title exists.
- A failed mid-run partial commit must not leave an orphaned branch — the script should `git push` only after the append step succeeds. If push fails, branch stays local and is cleaned up on next run by detecting "branch exists locally but no remote" pattern. (Or simpler: refuse to start if local branch exists; error with cleanup instructions.)

### TR2: Drift guards

- The script already enforces `_RULE_ID_RE`. The new path MUST run candidates through the regex before any append.
- The new path MUST NOT bypass the `hr-*` block. Add an explicit `^hr-` skip with a clear log line per skipped id.
- A unit-style test fixture (extend existing `RULE_METRICS_ROOT`-driven tests) covers: (a) skip already-retired, (b) skip `hr-*`, (c) skip on existing branch, (d) PR body includes hook-enforced warning.

### TR3: PR creation under GitHub Actions

- Delegated entirely to `.github/actions/bot-pr-with-synthetic-checks` composite action — same pattern as `rule-metrics-aggregate.yml`. Workflow does NOT git-config or call `gh pr create` itself; it provides `pr-title-prefix`, `pr-body`, `add-paths`, `branch-prefix`, `commit-message`, `change-summary`, and `gh-token` to the action.
- The composite action requires `pr-body` to be **single-line** — multi-line content fails action validation. The script's sentinel emission is `tr -d '\n\r'`-stripped to honor this contract.
- Branch name suffix is `YYYY-MM-DD` (the composite action appends `$(date -u +%Y-%m-%d)` to `branch-prefix`). For the quarterly cron, this resolves to e.g. `ci/rule-prune-retire-2026-07-01`. The `YYYY-Qn` shape originally suggested in the brainstorm/spec is not used; the date is more granular and `bot-pr-with-synthetic-checks` does not parameterize the suffix shape.
- The first (and only) commit on the proposal branch is the `retired-rule-ids.txt` append; PR # is `-` placeholder in the breadcrumb (no second commit). The actual PR number is recoverable via `gh pr list --search "scheduled by rule-prune"` or via the breadcrumb's "scheduled by" trail.

### TR4: Empty-candidate handling

- If candidates list is empty after filtering, log `No retirement candidates for >=26w. Skipped.` and exit 0. Do not create branch, do not open PR.

### TR5: PR body format

- Sections: `## Summary`, `## Candidates`, `## Manual review required (hook-/skill-enforced and hr-\*)`, `## Verify`, `## Reviewer checklist`.
- Reviewer checklist must include the existing language from `rule-prune.sh`'s issue body: "Rules protecting rare but catastrophic failures (e.g., `hr-never-git-stash-in-worktrees`) may have zero hits and still be load-bearing."
- Append `Closes #3120` to body (after #3120 is retitled to C2-only scope).

### TR6: Documentation

- Add a `## Retirement automation` subsection to `knowledge-base/project/learnings/` only if a real-world surprise occurs during the first quarterly run. Per `wg-every-session-error-must-produce-either` discoverability exit, no preemptive learning file is required.
- Update `scripts/rule-prune.sh`'s top-of-file comment block to document `--propose-retirement`.

## Test Scenarios

1. **No candidates:** `--weeks=26 --propose-retirement` with all rules at `fire_count > 0` → log skip line, exit 0, no branch, no PR.
2. **One candidate, not yet retired:** → branch created, single line appended, PR opened with `Candidates` section listing the rule.
3. **Candidate already in `retired-rule-ids.txt`:** → skipped silently with debug log; if it was the only candidate, behavior matches scenario 1.
4. **`hr-*` candidate:** → NOT appended to `retired-rule-ids.txt`. Listed in `Manual review required` section with pointer to `lint-rule-ids.py`.
5. **Hook-enforced candidate (`[hook-enforced: ...]` annotation in `rule_text_prefix`):** → appended to `retired-rule-ids.txt` AND listed in `Manual review required` section so reviewer can affirm or remove that line before merging.
6. **Re-run on same quarter:** → branch exists, exit with `[skip] already proposed` log line, exit 0.
7. **Idempotency under empty `retired-rule-ids.txt` race:** → if file is missing entirely, treat as empty list (don't crash).
8. **Schema mismatch on `rule-metrics.json`:** → script already exits 3 with clear error per existing `SCHEMA_VERSION` gate. Test ensures `--propose-retirement` doesn't bypass that gate.

## Acceptance Criteria

- [ ] `scripts/rule-prune.sh --propose-retirement` flag implemented per FR1, with all 8 test scenarios covered.
- [ ] `.github/workflows/scheduled-rule-prune.yml` created and verified via `gh workflow run scheduled-rule-prune.yml` after merge (per `wg-after-merging-a-pr-that-adds-or-modifies`).
- [ ] First scheduled run (or a manual `workflow_dispatch` after merge) produces either a no-op log OR a PR matching the FR1 specification.
- [ ] `retired-rule-ids.txt` linter-test still passes after a synthetic run with a non-`hr-` test fixture.
- [ ] D1 deferral issue exists, milestoned to "Post-MVP / Later", with evidence-gate criteria documented.
- [ ] #3120 retitled (or closed-and-replaced) to reflect C2-only scope; D1 acceptance criterion (eval-replay number in PR body) struck.
- [ ] Brainstorm `2026-05-04-harness-eval-stale-rules-brainstorm.md` archived from open status to "shipped" once retirement PR pattern is verified.

## Open Questions for Plan-Time

1. PR # backfill strategy: second commit on the same branch vs. using `-` placeholder in `retired-rule-ids.txt`. Lean toward `-` placeholder + breadcrumb referencing PR title; saves a commit and keeps the diff minimal.
2. Branch-conflict handling: if the cron fires while a previous quarter's branch is unmerged, do we open a second PR for the new quarter, OR rebase the existing one? Lean toward "open a second PR" — quarters are independent intervals.
3. Bot identity for the commit: reuse `rule-metrics-aggregate.yml`'s identity verbatim or define a new one (`rule-prune-bot`). Lean reuse.
