---
title: "fix: enforce CI test gate to block PR approval"
type: fix
date: 2026-04-06
deepened: 2026-04-06
---

# fix: enforce CI test gate to block PR approval

## Enhancement Summary

**Deepened on:** 2026-04-06
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Defense-in-Depth, Test Scenarios)
**Research sources:** GitHub Rulesets API docs, GitHub Community discussions, gh CLI docs, institutional learnings

### Key Improvements

1. Corrected bypass_mode semantics: `"pull_request"` does NOT add UI friction -- it restricts direct pushes but still allows silent PR merge bypass
2. Added exact `gh api` PUT payload with all required fields for the ruleset update
3. Identified that `gh pr merge --auto` already waits for checks regardless of bypass -- the bypass only matters for direct merges
4. Added auto-merge compatibility edge case (known GitHub rulesets/auto-merge bug) with mitigation

### New Considerations Discovered

- Auto-merge (`--auto` flag) does not exercise bypass privileges -- it always waits for requirements. The real protection is already in place via the `/ship` workflow using `--auto`.
- Changing bypass_mode could theoretically interact with the known GitHub rulesets/auto-merge compatibility issue (Discussion #162623), but this repo already uses rulesets with auto-merge working, so risk is low.
- The `"pull_request"` mode prevents direct pushes to main that bypass the ruleset -- a secondary benefit beyond the PR merge path.

## Overview

Test failures were not blocking PRs from being merged because the CI Required ruleset
allows admin bypass (`bypass_mode: "always"`). Additionally, the historical gap between
local test execution (`bun test`) and CI test execution (`vitest run` via
`scripts/test-all.sh`) meant that 71 test failures visible locally were invisible to CI.
The execution gap was fixed in PR #1436; this plan addresses the remaining bypass gap.

## Problem Statement

Three compounding issues allowed PRs to merge with failing tests:

1. **Admin bypass on CI Required ruleset.** The ruleset (ID 14145388) has two
   `bypass_mode: "always"` actors: OrganizationAdmin and RepositoryRole 5 (Admin).
   Since the founder (`deruelle`) is an admin, every merge silently bypasses required
   checks. GitHub does not warn when bypassing -- it just merges.

2. **Local/CI test parity gap (fixed).** Before PR #1436, `/ship` Phase 4 ran
   `bun test` while CI ran `npx vitest run` via `scripts/test-all.sh`. DOM-dependent
   tests failed under bun (no happy-dom preload) but passed under vitest. This is now
   resolved -- both local and CI run `bash scripts/test-all.sh`.

3. **No enforcement at merge time.** The `/ship` skill treats pre-existing test failures
   as an advisory (create tracking issue, continue shipping). There is no hard gate
   that blocks the merge when CI checks fail -- it relies on GitHub's ruleset enforcement,
   which is bypassed per point 1.

### Research Insights

**How bypass_mode actually works (GitHub Rulesets API):**

- `"always"` -- Actor can bypass ALL ruleset rules, including direct pushes to
  protected branches. No audit trail for the bypass.
- `"pull_request"` -- Actor must go through a PR workflow. Can still merge PRs
  with failing checks, but a bypass badge appears in the PR timeline (post-merge
  audit, not a pre-merge confirmation). Direct pushes to main are blocked.
- `"exempt"` -- Rules are not run for the actor and no bypass audit entry is
  created. Functionally invisible bypass.

**How auto-merge interacts with bypass (critical finding):**

`gh pr merge --squash --auto` always waits for requirements to be met. It does
NOT exercise bypass privileges. This means the `/ship` workflow (which uses `--auto`)
is already protected -- auto-merge will not merge PRs with failing required checks
regardless of the caller's bypass mode. The bypass only matters when using direct
merge (no `--auto` flag) or `--admin` flag.

**Implication:** The actual gap is narrower than initially assessed. PRs merged via
`/ship` (which uses `--auto`) were not bypassing checks. The bypass only occurred
when the admin used direct merge (GitHub UI "Merge" button or `gh pr merge --squash`
without `--auto`).

## Root Cause Analysis

The CI Required ruleset was created via `scripts/create-ci-required-ruleset.sh`
with admin bypass enabled by default:

```json
"bypass_actors": [
  { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
  { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
]
```

This was a reasonable default for a solo founder (avoids lockout when CI is broken),
but it defeats the purpose of required checks for direct merges and allows direct
pushes to main that bypass all rules.

## Proposed Solution

### Phase 1: Tighten ruleset bypass mode and update script

Change `bypass_mode` from `"always"` to `"pull_request"` for both bypass actors on the
CI Required ruleset.

**What this changes:**

- Direct pushes to main are now blocked (must go through PR)
- Admin can still merge PRs with failing checks via UI or `gh pr merge --squash`
  (but the bypass is recorded in the PR timeline)
- Auto-merge (`--auto`) behavior is unchanged (already waits for checks)
- Bypass badge appears in PR timeline post-merge for audit trail

**What this does NOT change:**

- Auto-merge behavior (already correct)
- `/ship` workflow behavior (uses `--auto`, already waits for checks)
- Admin's ability to merge PRs with failing checks when needed (escape hatch)

**Implementation:**

Step 1: Update live ruleset via `gh api` PUT.

The PUT endpoint replaces array fields wholesale. Include the full bypass_actors
array with updated bypass_mode values, plus all other fields to preserve them:

```bash
payload=$(mktemp)
trap 'rm -f "$payload"' EXIT

cat > "$payload" << 'PAYLOAD_EOF'
{
  "name": "CI Required",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": 1,
      "actor_type": "OrganizationAdmin",
      "bypass_mode": "pull_request"
    },
    {
      "actor_id": 5,
      "actor_type": "RepositoryRole",
      "bypass_mode": "pull_request"
    }
  ]
}
PAYLOAD_EOF

gh api "repos/jikig-ai/soleur/rulesets/14145388" \
  -X PUT --input "$payload"
```

**Note on actor_id for OrganizationAdmin:** The current ruleset has `actor_id: null`
for OrganizationAdmin. The PUT payload must match this. If the API rejects `null`,
use `1` (the conventional placeholder for org-level actors). Verify the response
preserves both actors.

Step 2: Update `scripts/create-ci-required-ruleset.sh` to use `"pull_request"`
bypass mode for future re-creation:

```bash
# In the bypass_actors JSON block, change:
#   "bypass_mode": "always"
# to:
#   "bypass_mode": "pull_request"
# for both actors
```

**Files changed:**

- `scripts/create-ci-required-ruleset.sh`
- Live ruleset updated via `gh api` PUT

### Phase 2: Verification

1. Verify the live ruleset shows `bypass_mode: "pull_request"` for both actors:

   ```bash
   gh api repos/jikig-ai/soleur/rulesets/14145388 \
     --jq '.bypass_actors[] | "\(.actor_type) (id: \(.actor_id)) -> \(.bypass_mode)"'
   ```

   Expected output:

   ```text
   OrganizationAdmin (id: null) -> pull_request
   RepositoryRole (id: 5) -> pull_request
   ```

2. Run `bash scripts/lint-bot-synthetic-completeness.sh` to confirm no bot
   workflow regressions
3. Run `bash scripts/test-all.sh` to confirm all tests pass
4. Verify auto-merge still works by confirming this PR's own auto-merge
   queues and merges successfully after CI passes

## Defense-in-Depth Note

The `/ship` skill already handles CI failure in Phase 7: when auto-merge is
queued via `gh pr merge --squash --auto` and a required check fails, the PR
state becomes CLOSED (not MERGED), and Phase 7 investigates. With the
`bypass_mode` fix, direct merges (without `--auto`) are the only remaining
bypass vector, and those now leave an audit trail in the PR timeline.

The protection stack is now three layers deep:

1. **Ruleset enforcement** -- Required checks must pass for non-bypass merges
2. **Auto-merge behavior** -- `--auto` flag always waits for requirements
3. **Bypass audit trail** -- `"pull_request"` mode records bypass in PR timeline

### Research Insights: Known Edge Cases

**Auto-merge + rulesets compatibility (GitHub Discussion #162623):**

Some repos report auto-merge failing after migrating to rulesets. This is a
known GitHub bug where auto-merge does not trigger even when all checks pass.
The workaround is to create an empty classic branch protection rule alongside
the ruleset. This repo has auto-merge working (verified: PRs #1635-#1639 all
used auto-merge successfully), so this bug does not currently apply. However,
if auto-merge breaks after the bypass_mode change, the first diagnostic step
should be checking this known issue.

**Institutional learning: Checks API vs Status API (from GITHUB_TOKEN learning):**

The CI Required ruleset requires Check Runs (Checks API, integration_id 15368),
not commit statuses (Status API). Bot PRs created via GITHUB_TOKEN must post
synthetic Check Runs using `gh api repos/.../check-runs`, not
`gh api repos/.../statuses/...`. This is enforced by
`scripts/lint-bot-synthetic-completeness.sh`. The bypass_mode change does not
affect this mechanism.

**Institutional learning: Defer CI gating to gh pr checks:**

When checking CI status programmatically, use `gh pr checks <number> --required --fail-fast`
rather than custom jq filtering of `statusCheckRollup`. The `--required` flag
respects the repository's ruleset configuration.

## Acceptance Criteria

- [x] CI Required ruleset bypass_mode is `"pull_request"` for both actors
- [x] `scripts/create-ci-required-ruleset.sh` uses `"pull_request"` bypass mode
- [x] Ruleset verified via API after update
- [x] Bot synthetic completeness lint passes
- [ ] Auto-merge still works (verified on this PR's own merge)
- [x] Admin can still bypass when explicitly choosing to (escape hatch preserved)

## Test Scenarios

- Given a PR with failing `test` check, when auto-merge is queued via
  `gh pr merge --auto`, then GitHub blocks the merge (auto-merge waits for
  requirements -- this already works and is unchanged by this fix)
- Given a PR with passing checks, when auto-merge is queued, then the PR
  merges normally (no regression)
- Given `/ship` running on a branch where CI fails, when Phase 7 polls and
  finds state CLOSED, then the pipeline investigates the failure (existing flow)
- Given the updated ruleset, when verifying via API, then both bypass actors
  show `bypass_mode: "pull_request"`
- Given a direct push to main (not through PR), then the push is blocked
  (new protection from `"pull_request"` mode)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Remove all bypass actors | Solo founder lockout risk if CI breaks |
| Add a separate GitHub App for merging | Overengineered for a solo repo |
| Use branch protection rules instead of rulesets | Rulesets are the newer/recommended approach; already in use |
| Require PR reviews before merge | Solo founder -- no other reviewers available for blocking review |
| Add CI check gate to /ship Phase 6.5 | YAGNI -- existing Phase 7 already handles CI failure; auto-merge already waits for checks |
| Dedup test failure issues in /ship | Different concern (issue hygiene, not merge blocking) -- filed as separate issue |
| Use `bypass_mode: "exempt"` | No audit trail -- worse than `"always"` for accountability |

## Plan Review

Three reviewers (DHH, Kieran, Code Simplicity) agreed: the original 5-phase plan had
scope creep. Phases 3 (script update) merged into Phase 1. Phases 2 (/ship CI gate)
and 4 (issue dedup) dropped as YAGNI and scope creep respectively. Phase 5
(verification) simplified to API verification only.

Kieran flagged that `bypass_mode: "pull_request"` does NOT show a confirmation
prompt -- it merges silently but records the bypass in the PR timeline. Plan updated
to reflect this accurately.

## References

- CI Required ruleset: `gh api repos/jikig-ai/soleur/rulesets/14145388`
- [GitHub Rulesets API - Update a repository ruleset](https://docs.github.com/en/rest/repos/rules#update-a-repository-ruleset)
- [GitHub Rulesets - About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Auto-merge + rulesets known issue (Discussion #162623)](https://github.com/orgs/community/discussions/162623)
- [Bypass list behavior with status checks (Discussion #86534)](https://github.com/orgs/community/discussions/86534)
- [Auto-merge documentation](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)
- PR #1436: fixed test parity gap (`bun test` vs `vitest run`)
- PR #1415: added pre-existing test failure tracking gate to `/ship`
- Issue #1413: tracked 71 pre-existing test failures
- Issue #826: original CI Required check implementation
- `scripts/create-ci-required-ruleset.sh`: ruleset creation script
- `scripts/required-checks.txt`: canonical list of required check names
- `scripts/lint-bot-synthetic-completeness.sh`: bot PR synthetic check linter
- Institutional learning: `knowledge-base/project/learnings/integration-issues/github-token-pr-no-ci-trigger-ContentPublisher-20260326.md`
- Institutional learning: `knowledge-base/project/learnings/2026-03-05-defer-ci-gating-to-gh-pr-checks.md`
