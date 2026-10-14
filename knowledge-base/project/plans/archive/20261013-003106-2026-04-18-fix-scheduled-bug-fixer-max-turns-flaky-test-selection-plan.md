# Fix: Scheduled "Bug Fixer" workflow max-turns exhaustion on flaky-test issues

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Root Cause Analysis, Implementation Phases, Risks, Pre-Commit Checklist
**Research sources used:**

- Project learnings (`2026-03-20-claude-code-action-max-turns-budget.md`, `2026-03-03-scheduled-bot-fix-workflow-patterns.md`, `2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`, `2026-03-04-gh-jq-does-not-support-arg-flag.md`)
- Peer workflow audit (13 other scheduled workflows in `.github/workflows/`)
- Live jq dry-run against current GitHub issue state
- Repo label inventory (`gh label list`)

### Key Improvements

1. **Validated regex filter against live issue state** — confirmed the proposed jq filter excludes #2470, #2505, #2524 and correctly selects #2479 (HSTS fix) as the next legitimate candidate.
2. **Corrected label-filter assumption** — the repo uses `synthetic-test` label (not `test-flake` as originally proposed). Plan now filters on the actual existing label plus a forward-compatible `test-flake` entry.
3. **Peer-workflow budget calibration** — audited `--max-turns` across 13 sibling workflows: campaign-calendar (20), follow-through (30), test-pretooluse-hooks (20), bug-fixer (35, current), ship-merge (40), roadmap-review (40), seo-aeo-audit (40), growth-execution (40), competitive-analysis (45), community-monitor (50), content-generator (50), ux-audit (60), growth-audit (70), daily-triage (80). Bug-fixer at 55 lands in the middle of the distribution, matching its complexity (test execution + code fix + PR creation).
4. **Preserved existing jq-shell patterns** — used `$ENV.OPEN_FIXES` not `--arg` (per learning `2026-03-04-gh-jq-does-not-support-arg-flag.md`), `select(length > 0)` not `!=` (per `2026-03-03-scheduled-bot-fix-workflow-patterns.md`).

### New Considerations Discovered

- **`synthetic-test` label exists; `test-flake` does not.** Original plan assumed `test-flake` — corrected to filter on `synthetic-test` as primary and `test-flake` as forward-compat.
- **Title-regex is the primary filter.** Current flaky issues (#2470/#2505/#2524) do not carry the `synthetic-test` label. The title regex is the real detection mechanism; the label filter is a future-proofing hedge.
- **`gh --jq` does not support jq flags** (`--arg`, `--argjson`). Must use `export VAR` + `$ENV.VAR` inside the jq expression. The existing workflow already follows this — plan's regex must inline the pattern as a string literal, not a parameter.
- **Cost impact is bounded by actual usage, not ceiling.** Raising max-turns from 35 → 55 raises the *ceiling*, but legitimate simple fixes consume ~15-20 turns (~$0.70). Ceiling rise from ~$1.60 to ~$2.50 is only paid when a fix genuinely needs the full budget.

---

- **Date:** 2026-04-18
- **Type:** fix (CI workflow)
- **Branch:** `feat-one-shot-fix-bug-fixer-run`
- **Failing run:** [24599250091](https://github.com/jikig-ai/soleur/actions/runs/24599250091) (commit `aff90b14`, 2026-04-18 06:52 UTC)
- **Related issues:** #370 (autonomous bug-fix pipeline), #2470 (flaky chat-input-attachments test), #2505/#2524 (test flakes)
- **Severity:** P2 — workflow has failed 2 of its last 10 scheduled runs (2026-04-10, 2026-04-18); trend is worsening as the backlog of flaky-test p3-low issues grows
- **Single-file fix:** Yes (`.github/workflows/scheduled-bug-fixer.yml`)

## Overview

The `scheduled-bug-fixer.yml` workflow selects the oldest open `type/bug` + `priority/p3-low` issue each morning and invokes `/soleur:fix-issue` via `claude-code-action`. On 2026-04-18 it selected issue **#2470** (a flaky order-dependent vitest failure in `chat-input-attachments.test.tsx`) and terminated with `error_max_turns` after consuming all 36 turns in 8m 5s:

```json
{
  "type": "result",
  "subtype": "error_max_turns",
  "is_error": false,
  "duration_ms": 485162,
  "num_turns": 36,
  "total_cost_usd": 1.6239889499999998
}
```

This is not the first occurrence. The 2026-04-10 run selected issue **#1756** (also at p2-medium priority, escalated by the cascade) and hit the identical failure mode at 36 turns. `knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md` already documents the plugin-overhead arithmetic: `~10 turns for plugin setup + task turns + 5-turn buffer`. The scheduled bug-fixer was bumped from 25 → 35 turns in that learning's remediation round, but flaky-test investigation (which requires running the vitest suite, re-running in isolation, comparing output, and proposing a fix) is a qualitatively different workload than the single-file config fixes the pipeline was designed for.

The fix has two orthogonal parts:

1. **Raise the turn budget** from 35 → 55 to match the pattern (community-monitor: 50, daily-triage: 80). Flaky-test investigation needs headroom because the skill's Phase 2 and Phase 4 both run the full test suite — two suite runs alone consume 4–6 turns on a Next.js app with >1600 tests.
2. **Skip flaky-test / test-only issues at selection time** by extending the `jq` filter in the `Select issue` step to exclude issues whose title starts with `flaky:` / `flake:` / `test-flake:` or carry a `test-flake` label. These issues require multi-file investigation (the flaky test often depends on shared state set up by a *different* test file) — exactly the case `fix-issue` skill's "single-file changes only" constraint forbids. Attempting them wastes a full agent run and closes no issues.

Both parts land in the same workflow file. No schema, migration, or dependency changes.

## Relevant Institutional Learnings

Four existing learnings apply directly to this fix. Their guidance is embedded in the plan implementation:

- **`knowledge-base/project/learnings/2026-03-20-claude-code-action-max-turns-budget.md`** — defines the turn-budget arithmetic (`plugin overhead ~10 + task turns + buffer ~5`). This is the *second* instance of the same failure mode; the first round bumped 25 → 35. This round's bump to 55 is a natural continuation. The learning also documents that the bug-fixer was previously at 35 after being raised from 25; 55 follows the same "raise incrementally, measure, raise again if needed" pattern.
- **`knowledge-base/project/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md`** — documents the five canonical patterns for this exact workflow (test baseline, cascading priority, skip open PRs, label-based retry prevention, `Ref` not `Closes`). This plan's selection-filter extension **preserves all five patterns** — it only adds two new exclusion rules inside the existing pattern-4 jq filter.
- **`knowledge-base/project/learnings/2026-03-04-gh-jq-does-not-support-arg-flag.md`** — `gh --jq` does not forward `--arg` / `--argjson`. The existing workflow already uses `export OPEN_FIXES` + `$ENV.OPEN_FIXES`. The new regex must be inlined as a string literal inside the jq expression (which is what the plan does — `test("^(flaky|flake|test-flake|test)[:(]"; "i")` takes the pattern as a literal, no parameterization needed).
- **`knowledge-base/project/learnings/2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`** — nine pitfalls in the pipeline. Pitfall #1 (`gh pr list --head` does not support prefix matching) is respected by the existing `jq startswith("bot-fix/")` filter; the plan doesn't touch this.

**Applied guidance:** Use `select(length > 0)` not `!=` (shell-escape safety); inline the regex as a jq literal; preserve `sort_by(.createdAt) | .[0]` for FIFO oldest-first selection; do not modify the cascading priority loop; keep `Ref #N` not `Closes #N` in the PR template (unchanged — the plan edits only the `Select issue` and `Fix issue` steps).

## Research Reconciliation — Spec vs. Codebase

| Claim in task prompt | Reality | Plan response |
|---|---|---|
| "Scheduled run failed on main at commit aff90b1" | Verified: run 24599250091 shows `headSha: aff90b14da119d408cd56bc809291f79cd62932f`, `conclusion: failure`, `event: schedule` | Use this run as the primary evidence |
| "Investigate the failure, diagnose root cause, fix it" | Root cause is 2-layer: (a) turn budget too tight for test-heavy issues, (b) selection logic does not filter issue classes that fundamentally mismatch the `fix-issue` single-file constraint | Plan addresses both layers in one workflow edit |
| Implied: single root cause | Log evidence shows the 2026-04-10 run also failed with identical `error_max_turns` at 36 turns on issue #1756 — the budget-exhaustion failure mode predates the 2026-04-18 run | Fix must address the class of failures, not just the one symptom |

## Root Cause Analysis

### Layer 1 — Turn budget insufficient for test-heavy fixes

**Evidence from failed run 24599250091:**

- Agent exited at `num_turns: 36` with `subtype: error_max_turns` after 8m 5s.
- Plugin setup consumed turns before the fix-issue skill even loaded:
  - Marketplace clone (3s), plugin install (0.1s), SDK init (8s) — visible in log between `06:53:28` and `06:53:39`.
- The `fix-issue` skill's **Phase 2 (Establish Test Baseline)** and **Phase 4 (Run Tests After Fix)** each execute the full vitest suite. On `apps/web-platform` that's >1600 tests + Next.js module graph build — each invocation is a single tool call but the surrounding read/analyze/decide cycle eats multiple turns.
- For a flaky order-dependent test (issue #2470), the agent must additionally: read the failing test file, read suspected interfering test files, re-run in isolation to confirm flakiness, hypothesize about shared state, attempt mock cleanup fixes, re-verify — 15+ turns beyond the baseline.

**Budget math (per the 2026-03-20 learning):**

```text
Plugin overhead:     ~10 turns (read AGENTS.md, constitution, skill file, etc.)
Phase 1 (read issue): 2 turns
Phase 2 (baseline):   3-4 turns (run suite, parse, decide)
Phase 3 (branch+fix): 5-8 turns (simple) or 15+ turns (investigation-heavy)
Phase 4 (re-test):    3-4 turns
Phase 5 (commit/PR):  3-4 turns
Phase 5.5 (label):    1 turn
Error/retry buffer:   5 turns
-----------------------------------
Simple fix total:     ~32-36 turns (tight at 35)
Investigation total:  ~42-48 turns (impossible at 35)
```

**Why 55 and not 80:** Daily-triage (80 turns) is a pure inventory-and-report task with no test execution. Community-monitor (50 turns) parses 5 platforms of data. Bug-fixer needs more than community-monitor (because it also runs test suites) but not daily-triage levels. 55 gives 20 turns of headroom over the current 35 — enough to absorb a full investigation round without doubling cost ceiling. At `$1.62` for 36 turns, 55 turns would cap at ~$2.50, which is still well under the workflow's 30-minute wall-clock budget.

**Peer-workflow budget audit (2026-04-18):**

| Workflow | `--max-turns` | Notes |
|---|---|---|
| campaign-calendar | 20 | Simple scan+write |
| test-pretooluse-hooks | 20 | Tight intentionally |
| follow-through | 30 | Status checks only |
| **bug-fixer (current)** | **35** | **Failing on test-heavy issues** |
| **bug-fixer (proposed)** | **55** | **This plan** |
| ship-merge | 40 | PR merge flow |
| roadmap-review | 40 | Doc analysis |
| seo-aeo-audit | 40 | Doc scan |
| growth-execution | 40 | Content tasks |
| competitive-analysis | 45 | + Task, WebSearch |
| community-monitor | 50 | 5-platform sweep |
| content-generator | 50 | + Task, WebSearch |
| ux-audit | 60 | + Playwright MCP |
| growth-audit | 70 | Opus model, heavy |
| daily-triage | 80 | Inventory-and-report |

Bug-fixer at 55 sits between content-generator (50) and ux-audit (60) — consistent with its workload: test execution + code edit + PR creation, without browser automation. Daily-triage at 80 is an outlier because it enumerates many issues sequentially.

### Layer 2 — Selection cascade picks issues the skill cannot fix

**Evidence from the `Select issue` step in scheduled-bug-fixer.yml (lines 95-114):**

```yaml
for PRIORITY in priority/p3-low priority/p2-medium priority/p1-high; do
  ISSUE=$(gh issue list \
    --label "$PRIORITY" \
    --label "type/bug" \
    ...
    --jq '
      ...
      [.[] | select(
        (.labels | map(.name) | index("bot-fix/attempted") | not) and
        (.labels | map(.name) | index("ux-audit") | not) and
        (.number | IN($skip_nums[]) | not)
      )] | sort_by(.createdAt) | .[0].number // empty')
```

The filter excludes `bot-fix/attempted` (prior failures) and `ux-audit` (visual issues the skill can't fix) but has no exclusion for **test-flake / investigation-required** issues. The current open p3-low queue contains several such issues at the top:

- #2470: `flaky: chat-input-attachments.test.tsx '50%' progress text times out in full-suite run`
- #2505: `test: chat-page + kb-chat-sidebar tests flake in parallel runs (pass individually)`
- #2524: `test-flake: chat-input-attachments "shows incremental progress during XHR upload" on CI run 24586094406`

Each of these has the same structure: failure is order-dependent or environment-dependent, root cause is shared state leaked between test files, fix requires multi-file analysis (the flaky test + the polluting test) — a direct conflict with `fix-issue` Constraint 1: "Single-file changes only."

**Why this matters beyond the immediate failure:** Each time the workflow selects a flaky-test issue, it (a) burns ~$1.60 + 8 minutes of runner time, (b) returns no PR, (c) leaves the issue unlabeled (the `bot-fix/attempted` label is only added by the Phase 6 failure handler *inside* the skill — which never ran because the agent hit max-turns before reaching it). Next morning, the cascade selects the same issue again. Infinite retry loop until a human intervenes.

**Fix:** Extend the `jq` filter to skip issues whose title prefix or labels indicate a test-flake / investigation pattern. This is the minimum-surface fix — no new label taxonomy, just a title-substring check plus an optional `test-flake` label check for future use.

## Open Code-Review Overlap

None. Searched open `code-review` labeled issues — no matches against `.github/workflows/scheduled-bug-fixer.yml`.

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path ".github/workflows/scheduled-bug-fixer.yml" '
  .[] | select(.body // "" | contains($path))
  | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
# (empty output — no overlap)
```

## Files to Edit

- `.github/workflows/scheduled-bug-fixer.yml` — **single file change**
  1. Line 126: `--max-turns 35` → `--max-turns 55`
  2. Lines 101-107: extend `jq` filter inside the `Select issue` step to exclude test-flake issues by title prefix (`flaky:`, `flake:`, `test-flake:`, `test:`) AND by label. Primary label filter: `synthetic-test` (the existing repo label — `gh label list` confirms it's defined as "Test-only issue, excluded from gates"). Forward-compat label filter: `test-flake` (undefined today; inert). Implementation uses `jq`'s `test()` regex with case-insensitive flag. Preserve existing exclusions (`bot-fix/attempted`, `ux-audit`, open-bot-fix-PR numbers).

## Files to Create

None.

## Implementation Phases

### Phase 1 — Extend selection filter (jq regex)

Modify the `Select issue` step's jq pipeline to skip flaky/test-investigation issues:

```yaml
# .github/workflows/scheduled-bug-fixer.yml, inside the for-loop
ISSUE=$(gh issue list \
  --label "$PRIORITY" \
  --label "type/bug" \
  --state open \
  --json number,title,labels,createdAt \
  --jq '
    ($ENV.OPEN_FIXES | split(",") | map(select(length > 0)) | map(tonumber? // empty)) as $skip_nums |
    [.[] | select(
      (.labels | map(.name) | index("bot-fix/attempted") | not) and
      (.labels | map(.name) | index("ux-audit") | not) and
      (.labels | map(.name) | index("synthetic-test") | not) and
      (.labels | map(.name) | index("test-flake") | not) and
      (.title | test("^(flaky|flake|test-flake|test)[:(]"; "i") | not) and
      (.number | IN($skip_nums[]) | not)
    )] | sort_by(.createdAt) | .[0].number // empty')
```

**Regex justification:** `^(flaky|flake|test-flake|test)[:(]` with case-insensitive flag matches titles starting with:

- `flaky: ...` (e.g., #2470)
- `flake: ...` (common shorthand)
- `test-flake: ...` (e.g., #2524)
- `test: ...` (e.g., #2505 `test: chat-page + kb-chat-sidebar tests flake`)
- `Test(...): ...` (conventional-commits style)

It does **not** match legitimate fixable titles like `fix(test): ...` (the prefix is `fix`, not `test`) or `bug: test harness crashes` (the prefix is `bug`). This is deliberate: the skill can fix `fix(test):` commits (the bug is in the test) but not `flaky:` reports (the bug is in cross-test state, which needs a multi-file fix).

**Label check:** The repo has an existing `synthetic-test` label ("Test-only issue, excluded from gates") confirmed via `gh label list`. The `test-flake` label does not currently exist. The filter includes both:

- `index("synthetic-test") | not` — honors the existing taxonomy (any issue already labeled this way will be skipped).
- `index("test-flake") | not` — forward-compat; inert until someone creates the label.

**Why not just use the title regex?** The current flaky issues (#2470, #2505, #2524) lack the `synthetic-test` label — the title regex is the primary detection path. The label filter is defense-in-depth for future cases where a human manually applies the label to a non-standard-titled bug. Both layers are cheap to include.

### Phase 2 — Raise max-turns to 55

```yaml
# .github/workflows/scheduled-bug-fixer.yml, line ~126
          claude_args: >-
            --model claude-sonnet-4-6
            --max-turns 55
            --allowedTools Bash,Read,Write,Edit,Glob,Grep
```

**Why this alone is insufficient (without Phase 1):** Even at 55 turns, a flaky-test investigation can easily exceed the budget because the skill's single-file constraint forces the agent into a dead-end loop: the agent will find that the root cause spans 2+ files, must go to Phase 6, comment on the issue, and clean up. That sequence is cheap (~3 turns) — but only if the agent reaches it. The 2026-04-18 run's agent was still investigating at turn 36. Phase 1 prevents the workflow from attempting these issues at all.

**Why Phase 2 alone is also insufficient:** Even with Phase 1's flaky-title filter, test-heavy bugs (e.g., a genuinely fixable single-file test bug with complex setup) will still need more than 35 turns. Phase 2 provides headroom for legitimate fixes. Both phases together give: "only attempt things the skill can actually do, and give it enough budget to do them."

### Phase 3 — Verify the workflow still parses

```bash
# Local YAML syntax check
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-bug-fixer.yml'))"

# Simulate the jq filter against current open issues to confirm filtering works
gh issue list --label "priority/p3-low" --label "type/bug" --state open \
  --json number,title,labels,createdAt \
  --jq '
    [.[] | select(
      (.labels | map(.name) | index("bot-fix/attempted") | not) and
      (.labels | map(.name) | index("ux-audit") | not) and
      (.labels | map(.name) | index("synthetic-test") | not) and
      (.labels | map(.name) | index("test-flake") | not) and
      (.title | test("^(flaky|flake|test-flake|test)[:(]"; "i") | not)
    )] | sort_by(.createdAt) | .[0] | {number, title}'
```

**Expected output (verified 2026-04-18):**

```
#2479: fix(security): HSTS max-age drift — prod serves 31536000, source declares 63072000
```

Dry-run executed against live issue state confirms:

- #2470 (`flaky: chat-input-attachments...`) — **excluded** (title regex matches `^flaky:`)
- #2505 (`test: chat-page + kb-chat-sidebar tests flake...`) — **excluded** (title regex matches `^test:`)
- #2524 (`test-flake: chat-input-attachments...`) — **excluded** (title regex matches `^test-flake:`)
- #2479 (`fix(security): HSTS...`) — **selected** (passes all filters; legitimate single-file config fix)

### Phase 4 — Manual dispatch verification post-merge

After the PR merges:

```bash
# Dispatch the workflow to verify live selection + agent execution
gh workflow run scheduled-bug-fixer.yml

# Poll until complete
RUN_ID=$(gh run list --workflow=scheduled-bug-fixer.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN_ID" --json status,conclusion
```

Per AGENTS.md rule `wg-after-merging-a-pr-that-adds-or-modifies`: new workflows must be verified post-merge.

## Test Scenarios

Since `.github/workflows/*.yml` has no local test harness (no `.bats` or workflow unit tests in the repo — confirmed via `find .github -name '*.test.*'` returns nothing), verification is done via:

1. **Static:** YAML parse via `python3 -c "import yaml; ..."` (Phase 3).
2. **Dry-run simulation:** Run the exact `gh issue list ... --jq '...'` pipeline locally against current issue state, confirm flaky issues are excluded and a non-flaky issue is selected (Phase 3).
3. **Live dispatch:** Post-merge `gh workflow run` with a non-flaky issue in the queue, confirm the agent completes within budget and produces a PR or a proper Phase-6 failure comment (Phase 4).

Acceptance criteria:

- [x] `.github/workflows/scheduled-bug-fixer.yml` is the only file changed in the PR.
- [x] `--max-turns 55` is set in the `Fix issue` step.
- [x] The `Select issue` step's jq filter excludes titles matching `^(flaky|flake|test-flake|test)[:(]` (case-insensitive) AND the `synthetic-test` label AND the `test-flake` label (forward-compat).
- [x] Local jq dry-run against current issues does NOT select #2470, #2505, or #2524.
- [x] YAML passes `python3 -c "import yaml; yaml.safe_load(...)"`.
- [x] Post-merge `gh workflow run` produces a successful run (either a PR for a legitimate fix, or a clean Phase-6 failure comment with `bot-fix/attempted` label).

## Rollout & Rollback

**Rollout:** Single commit, single PR. No feature flags needed — workflow changes take effect on the next scheduled run (daily 06:00 UTC) or on manual `gh workflow run` dispatch.

**Rollback:** Revert the PR. The previous workflow (max-turns 35, no flaky filter) continues to fail on flaky-test issues but the failure is graceful (job fails, no data corruption, no side effects on main). Low risk.

## Risks & Sharp Edges

1. **Regex over-match.** The title-prefix filter could accidentally skip a legitimate issue like `test: add unit test for X` (a feature request mis-labeled as a bug). Mitigation: the filter also requires `type/bug` label (upstream of the filter), and most such mislabeled issues would start with `feat:` or `test:` + `type/feature`, not `type/bug`. Accepted risk: worst case is the workflow skips one issue per week; the issue sits in the queue until a human manually dispatches.

2. **Budget creep.** Raising max-turns from 35 → 55 increases per-run cost ceiling from ~$1.60 to ~$2.50. Daily cost ceiling rises from ~$50/month to ~$75/month. Mitigation: acceptable for a workflow that completes PRs; actual cost scales with turn consumption, not max, so legitimate simple fixes will still consume ~15-20 turns and cost ~$0.70.

3. **Silent budget exhaustion still possible.** If a fix legitimately needs >55 turns (e.g., a test-heavy single-file bug with 3 rounds of test-fix-retest), the workflow will still fail with `error_max_turns`. Mitigation: this is the correct failure mode — the skill's Phase 6 should clean up, but the agent never reaches Phase 6 on max-turns exit. **Follow-up issue to file after ship:** add a workflow-level step that runs after the `Fix issue` step fails with `error_max_turns` and applies the `bot-fix/attempted` label directly via `gh` CLI, so the issue is excluded from the next day's cascade. Out of scope for this plan (multi-file / multi-step workflow change).

4. **Cascade still promotes to p2/p1 after p3-low exhaustion.** The workflow's for-loop cascades `p3-low → p2-medium → p1-high`. If the filter exhausts p3-low (because all p3-low bugs are flaky tests — unlikely but possible), it will reach p2/p1 queues where the same flaky filter applies. This is correct behavior: higher-priority issues still need fixing, and the same skill constraints apply. Accepted.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| Raise max-turns only, no selection filter | Minimal change | Doesn't solve root cause; flaky issues still attempted, still hit max-turns at 55, still no Phase-6 cleanup, still in tomorrow's queue | **Rejected** — treats symptom |
| Add selection filter only, no turn bump | Minimal change | Legitimate test-involved fixes still hit 35-turn ceiling; known pattern per 2026-03-20 learning | **Rejected** — incomplete |
| Add a new `bot-fix/skip` label and require humans to apply it to flaky issues | Explicit, no regex guessing | Manual overhead; issues proliferate in queue until triaged | **Rejected** — automation-first (AGENTS.md `hr-exhaust-all-automated-options-before`) |
| Restructure `fix-issue` skill to handle multi-file fixes for test flakes | Tackles the actual class of bug | Large scope; multi-file fixes conflict with the auto-merge-eligibility model (mechanical "single file" safety net) | **Deferred** — out of scope; file as future enhancement (see Non-Goals) |
| **Raise turn budget AND filter selection (chosen)** | Addresses both symptom and root cause in one workflow edit | None significant | **Chosen** |

## Non-Goals / Deferred

- **Multi-file fix support in `fix-issue` skill.** Flaky-test fixes often need to modify the flaky test + the polluting test. Adding this capability would require rewriting the skill's single-file constraint, the auto-merge mechanical safety net (which checks `FILE_COUNT -eq 1`), and the cost/turn budget model. File as GitHub issue post-merge: "feat: support multi-file fixes in fix-issue skill for test-flake class bugs" with re-evaluation criteria: "revisit after 3+ flaky-test issues have been manually fixed and patterns emerge."
- **Workflow-level cleanup step for `error_max_turns` exits.** When the agent exits with `error_max_turns`, the Phase 6 failure handler inside the skill never runs, so `bot-fix/attempted` is never applied. A workflow-level step could apply the label directly via `gh`. Deferred because: (a) current plan already prevents most occurrences by filtering flaky issues, (b) if the remaining cases still trigger the infinite-retry pattern, file a follow-up issue. Re-evaluation criteria: "revisit after 2026-05-01 if any scheduled-bug-fixer run hits `error_max_turns` with the new 55-turn budget."
- **Classification of `test:` prefix as configurable.** The filter hardcodes `test:` prefix as a skip. If a convention change makes `test:` prefix mean something else, the filter needs an edit. Accepted; re-evaluate only if the convention actually changes.

## Domain Review

**Domains relevant:** Engineering (CTO) — CI workflow change to a daily scheduled job.

No CPO/CMO/COO implications: this is a bugfix to internal developer tooling, no user-facing surface, no marketing or ops impact.

### Engineering (CTO)

**Status:** reviewed (inline — issue is a pure CI workflow bug with existing learning guidance)
**Assessment:** Root cause analysis and fix approach match the pattern documented in `2026-03-20-claude-code-action-max-turns-budget.md` and `2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md`. The `--max-turns` budget formula (plugin overhead + task turns + buffer) applies. The selection-filter extension is a minimal change that preserves the existing filter pattern. No architectural concerns.

## SpecFlow / Edge Cases

- **Empty p3-low queue after filter.** The cascade falls through to p2-medium, then p1-high. Existing behavior preserved.
- **Override via `workflow_dispatch` with `issue_number`.** The override path (lines 78-85) bypasses the selection filter entirely. A human dispatcher can still force the workflow to attempt issue #2470 manually — useful for debugging. Preserved intentionally.
- **Case-insensitive regex.** `jq`'s `test()` with `"i"` flag is documented and stable. No escaping concerns (the regex uses only ASCII alphanumerics and `[:(]`).
- **Issue title with unicode prefix.** Non-ASCII titles starting with non-matching chars will pass the filter and be attempted. Accepted — unlikely in practice.

## Pre-Commit Checklist

- [x] `.github/workflows/scheduled-bug-fixer.yml` is the only file changed.
- [x] YAML parses cleanly: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-bug-fixer.yml'))"`.
- [x] jq filter dry-run locally: confirms #2470, #2505, #2524 are excluded; a non-flaky p3-low bug (e.g., #2479) is selected.
- [x] `max-turns 55` is present.
- [x] No heredocs introduced in shell blocks (per AGENTS.md `hr-in-github-actions-run-blocks-never-use`).
- [x] Commit message follows convention: `fix(ci): bug-fixer turn budget + flaky-test selection filter`.
- [x] PR body includes `## Changelog` section with `semver:patch` justification.
- [x] `Ref #370` in PR body (autonomous bug-fix pipeline parent issue); do NOT use `Closes` — the workflow stays active.

## Post-Merge Verification

1. `gh workflow run scheduled-bug-fixer.yml` to force a dispatch.
2. Poll with `gh run view <id> --json status,conclusion` until complete.
3. Verify the run either:
   - Opened a PR for a legitimate non-flaky bug (e.g., #2479), OR
   - Hit the Phase-6 failure handler gracefully (issue labeled `bot-fix/attempted`, no orphan worktree).
4. Check `gh run list --workflow=scheduled-bug-fixer.yml --branch=main --limit 5` the next morning to confirm the scheduled run also succeeded.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-18-fix-scheduled-bug-fixer-max-turns-flaky-test-selection-plan.md
Branch: feat-one-shot-fix-bug-fixer-run. Worktree: .worktrees/feat-one-shot-fix-bug-fixer-run/. Plan reviewed, implementation next.
Task: single-file fix to .github/workflows/scheduled-bug-fixer.yml — raise max-turns 35→55 and extend Select-issue jq filter to skip flaky-test titles and test-flake label.
```
