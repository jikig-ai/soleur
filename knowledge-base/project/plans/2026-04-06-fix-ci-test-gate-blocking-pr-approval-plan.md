---
title: "fix: enforce CI test gate to block PR approval"
type: fix
date: 2026-04-06
---

# fix: enforce CI test gate to block PR approval

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
but it defeats the purpose of required checks for normal development flow.

## Proposed Solution

### Phase 1: Tighten ruleset bypass mode and update script

Change `bypass_mode` from `"always"` to `"pull_request"` for both bypass actors on the
CI Required ruleset. With `"pull_request"` mode, admins can still bypass when merging
PRs, but the bypass is recorded in the PR timeline with a visible badge. This preserves
the escape hatch while making bypass deliberate and auditable.

**Note:** The `"pull_request"` bypass mode does NOT show a confirmation prompt before
merge. It still merges silently, but the bypass appears in the PR timeline post-merge.
The value is auditability, not friction.

**Stronger alternative considered:** Remove bypass actors entirely. Rejected because a
solo founder with no other admin would be permanently locked out if CI breaks (e.g.,
GitHub Actions outage, external dependency failure). The `"pull_request"` mode is the
right balance -- bypass is possible but recorded.

**Implementation:**

1. Update live CI Required ruleset (ID 14145388) via `gh api` PUT: change
   `bypass_mode` from `"always"` to `"pull_request"` for both actors
2. Update `scripts/create-ci-required-ruleset.sh` to use `"pull_request"` bypass
   mode with an explanatory comment about the tradeoff

**Files changed:**

- `scripts/create-ci-required-ruleset.sh`
- Live ruleset updated via `gh api` PUT

### Phase 2: Verification

1. Verify the live ruleset shows `bypass_mode: "pull_request"` for both actors
   via `gh api repos/jikig-ai/soleur/rulesets/14145388`
2. Run `bash scripts/lint-bot-synthetic-completeness.sh` to confirm no bot
   workflow regressions
3. Run `bash scripts/test-all.sh` to confirm all tests pass

## Defense-in-Depth Note

The `/ship` skill already handles CI failure in Phase 7: when auto-merge is
queued via `gh pr merge --squash --auto` and a required check fails, the PR
state becomes CLOSED (not MERGED), and Phase 7 investigates. With the
`bypass_mode` fix, `gh pr merge --auto` will correctly respect required checks
instead of silently bypassing them. No additional `/ship` changes are needed --
the existing Phase 7 flow is sufficient.

## Acceptance Criteria

- [ ] CI Required ruleset bypass_mode is `"pull_request"` for both actors
- [ ] `scripts/create-ci-required-ruleset.sh` uses `"pull_request"` bypass mode
- [ ] Ruleset verified via API after update
- [ ] Bot synthetic completeness lint passes
- [ ] Admin can still bypass when explicitly choosing to (escape hatch preserved)

## Test Scenarios

- Given a PR with failing `test` check, when auto-merge is queued via
  `gh pr merge --auto`, then GitHub blocks the merge (ruleset enforcement)
- Given a PR with passing checks, when auto-merge is queued, then the PR
  merges normally (no regression)
- Given `/ship` running on a branch where CI fails, when Phase 7 polls and
  finds state CLOSED, then the pipeline investigates the failure (existing flow)

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
| Add CI check gate to /ship Phase 6.5 | YAGNI -- existing Phase 7 already handles CI failure; bypass_mode fix closes the gap |
| Dedup test failure issues in /ship | Different concern (issue hygiene, not merge blocking) -- filed as separate issue |

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
- Bypass mode docs: [GitHub Rulesets API](https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset)
- PR #1436: fixed test parity gap (`bun test` vs `vitest run`)
- PR #1415: added pre-existing test failure tracking gate to `/ship`
- Issue #1413: tracked 71 pre-existing test failures
- Issue #826: original CI Required check implementation
- `scripts/create-ci-required-ruleset.sh`: ruleset creation script
- `scripts/required-checks.txt`: canonical list of required check names
- `scripts/lint-bot-synthetic-completeness.sh`: bot PR synthetic check linter
