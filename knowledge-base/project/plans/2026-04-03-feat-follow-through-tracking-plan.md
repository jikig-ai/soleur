---
title: "feat: Follow-Through — automated external dependency tracking in /ship"
type: feat
date: 2026-04-03
---

# Follow-Through: Automated External Dependency Tracking

## Overview

Extend the `/ship` skill with a Phase 7.5 that detects unchecked test plan items marked with ⏳ in PR bodies after merge, creates tracking GitHub Issues with structured verification metadata, and adds a daily cron workflow that monitors resolution — auto-closing on success or escalating after SLA timeout.

**Issue:** [#1433](https://github.com/jikig-ai/soleur/issues/1433)
**Brainstorm:** [2026-04-03-follow-through-brainstorm.md](../brainstorms/2026-04-03-follow-through-brainstorm.md)
**Spec:** [spec.md](../specs/feat-follow-through/spec.md)

## Problem Statement

When `/ship` produces a PR with unchecked test plan items that depend on external processes (Google brand verification, DNS propagation, certificate issuance), there is no mechanism to track resolution after the session ends. The session ends, the verification never happens, and silent failures accumulate. PR #1398 (Google OAuth brand verification) triggered this — no tracking mechanism existed after the session closed.

## Proposed Solution

Three components compose to solve this:

1. **`/ship` Phase 7.5** — Post-merge detection of ⏳-marked items, automatic issue creation
2. **`scheduled-follow-through.yml`** — Daily cron workflow that monitors open follow-through issues
3. **Verification block format** — Fenced YAML code block in issue body for automated verification (http-200, dns-txt, dns-a, manual)

## Technical Approach

### Component 1: /ship Phase 7.5 — Follow-Through Detection

**File:** `plugins/soleur/skills/ship/SKILL.md`

**Placement:** Inside Phase 7's "If merged" block, as a new **Step 3.5** after Step 3 (post-merge workflow validation) and before Step 4 (worktree cleanup). This is NOT a top-level phase peer — it is a numbered item within the existing merge-confirmation sequence. At this point:

- PR is confirmed MERGED
- Release workflows have been verified
- PR body is still accessible via `gh pr view`
- Worktree cleanup hasn't happened yet

**Detection logic:**

Step 1 — Read the PR body. Use the PR number from Phase 6:

```text
gh pr view <PR_NUMBER> --json body --jq .body
```

Step 2 — Scan for unchecked items with ⏳ marker. Match lines matching this pattern:

```text
- [ ] ⏳ <description>
```

Regex: `^- \[ \] ⏳ (.+)$` (multiline). Each match group captures the item description.

Step 3 — Ensure the `follow-through` and `needs-attention` labels exist:

```text
gh label create "follow-through" --description "External dependency awaiting verification" --color "C5DEF5" 2>/dev/null || true
gh label create "needs-attention" --description "SLA exceeded, requires human action" --color "D93F0B" 2>/dev/null || true
```

Step 4 — For each detected item, create a GitHub issue. All issues are created with `manual` type and `5 business days` SLA by default. Users can edit the issue body after creation to configure automated predicates (http-200, dns-txt, dns-a). Read `knowledge-base/product/roadmap.md` to determine the milestone (or default to "Post-MVP / Later"):

```text
gh issue create --title "follow-through: <item description>" --label "follow-through" --milestone "<milestone>" --body "<structured body>"
```

**Issue body template:**

````markdown
## Follow-Through Item

<item description>

**Source PR:** #<PR_NUMBER>
**Created by:** /ship Phase 7.5
**Created:** <YYYY-MM-DD>

## Verification

```yaml
type: manual
sla_business_days: 5
```

To enable automated verification, edit the YAML block above. Supported types:

- `http-200` — add `url: https://example.com`
- `dns-txt` — add `domain: example.com` and `expected: verification-string`
- `dns-a` — add `domain: example.com` and `expected: 1.2.3.4`

## Status

Awaiting verification. The daily follow-through monitor will check this issue.
````

Step 5 — Report: "Created N follow-through issue(s): #X, #Y, #Z"

**If no ⏳-marked items found:** Skip silently, proceed to cleanup (Step 4).

### Component 2: scheduled-follow-through.yml — Daily Monitor

**File:** `.github/workflows/scheduled-follow-through.yml`

Follow the existing scheduled workflow pattern from `scheduled-daily-triage.yml`:

- SHA-pinned actions (resolve at plan time via `gh api`)
- `concurrency: group: schedule-follow-through, cancel-in-progress: false`
- `permissions: contents: read, issues: write, id-token: write`
- `timeout-minutes: 15` (lightweight — just issue scanning and predicate checks)
- Cron: `0 9 * * 1-5` (9am UTC weekdays)
- `workflow_dispatch: {}` for manual testing

**Agent configuration:**

- `claude_args: --model claude-sonnet-4-6 --max-turns 30 --allowedTools Bash,Read,Glob,Grep`

**Agent prompt structure:**

The claude-code-action agent receives a prompt to:

1. List open issues with `follow-through` label: `gh issue list --label follow-through --state open --json number,title,body,createdAt,author --jq '.'`
2. For each issue:
   a. Extract the fenced YAML code block from the issue body (regex: `` ```yaml\n...\n``` ``)
   b. Calculate **business days** elapsed since creation (skip Saturdays and Sundays — count only Mon-Fri)
   c. Based on predicate type from the YAML block:
      - `manual`: Skip automated check, only track SLA
      - `http-200`: Run `curl -s -o /dev/null -w "%{http_code}" <url>` and check for 200
      - `dns-txt`: Run `dig +short TXT <domain>` and check for expected value
      - `dns-a`: Run `dig +short A <domain>` and check for expected IP
   d. **Comment only on state transitions** (not daily):
      - **Predicate passes** → Close issue with comment: "Verified: [predicate result]. Auto-closing."
      - **SLA exceeded (first time)** → Add `needs-attention` label, @-mention the issue author, comment: "SLA exceeded ([N] business days). @[author] — manual intervention required."
      - **Max polling exceeded (30 business days)** → Add `needs-attention` label, @-mention the issue author, comment: "Maximum polling period reached (30 business days). Stopping automated monitoring. @[author] — manual intervention required." Close the issue.
      - **Within SLA, no state change** → No comment. Silent.
3. Output a summary table of all checked issues and their status.

**Sharp edges for agent prompt:**

- Never modify issue body (only comments and labels)
- Never create new issues
- Never close issues unless predicate passes or 30-day max exceeded
- If `gh` commands fail, skip the issue and continue
- If `dig` or `curl` are unavailable, fall back to status comment: "Predicate check unavailable in this environment"

### Component 3: Verification Block Format

No separate implementation needed — this is the fenced YAML code block in the issue body parsed by the daily monitor agent. The monitor extracts the ````yaml ...```` block and reads the fields:

| Type | Fields | Check Command | Pass Condition |
|------|--------|---------------|----------------|
| `manual` | (none) | N/A | User closes manually |
| `http-200` | url | `curl -s -o /dev/null -w "%{http_code}" <url>` | HTTP 200 |
| `dns-txt` | domain, expected | `dig +short TXT <domain>` | Contains expected value |
| `dns-a` | domain, expected | `dig +short A <domain>` | Contains expected IP |

All issues are created as `manual` type by default. Users edit the YAML block in the issue body to configure automated predicates when applicable. This avoids a custom parsing syntax in test plan items and plays to the monitor agent's strength — it can read YAML reliably from a fenced code block.

## Acceptance Criteria

- [ ] PR with ⏳-marked unchecked items triggers follow-through issue creation at ship time (with fenced YAML verification block, `follow-through` label, and milestone)
- [ ] Predicate auto-closes issue when check passes (http-200 returns 200, dns-txt/dns-a record matches expected value)
- [ ] Manual predicate leaves issue open for user to close
- [ ] SLA escalation adds `needs-attention` label and @-mentions the issue author
- [ ] 30-day max polling closes issue with escalation comment and @-mention
- [ ] No follow-through issues created for unchecked items without ⏳ marker
- [ ] No follow-through issues created for checked items (`- [x] ⏳`)
- [ ] Monitor comments only on state transitions (predicate pass, SLA breach, max polling) — no daily "still pending" noise

## Test Scenarios

### Detection Tests

- Given a PR body with `- [ ] ⏳ Brand verification completes (2-3 business days)`, when Phase 7.5 runs, then issue is created with type `manual`, SLA `5 business days`, and fenced YAML verification block
- Given a PR body with `- [x] ⏳ Already done`, when Phase 7.5 runs, then no issue is created (item is checked)
- Given a PR body with `- [X] ⏳ Already done`, when Phase 7.5 runs, then no issue is created (uppercase X also means checked)
- Given a PR body with `- [ ] Regular unchecked item` (no ⏳), when Phase 7.5 runs, then no issue is created
- Given a PR body with zero ⏳ items, when Phase 7.5 runs, then Phase 7.5 is skipped silently

### Monitor Tests

- Given an open follow-through issue with `http-200` predicate (user edited YAML block) and URL returning 200, when daily monitor runs, then issue is auto-closed with "Verified" comment
- Given an open follow-through issue with `manual` type within SLA, when daily monitor runs, then no comment is added (silent — no state change)
- Given an open follow-through issue past SLA, when daily monitor runs, then `needs-attention` label is added, author is @-mentioned, and escalation comment posted
- Given an open follow-through issue at 30 business days, when daily monitor runs, then issue is closed with "Maximum polling period reached" comment and @-mention

### Integration Verification

- **Workflow YAML valid:** `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/scheduled-follow-through.yml'))"`
- **Manual workflow trigger:** `gh workflow run scheduled-follow-through.yml` after merge, poll until complete
- **Label creation:** `gh label list --search "follow-through" --json name --jq '.[0].name'` expects `follow-through`

## Domain Review

**Domains relevant:** Product, Marketing, Engineering (carried forward from brainstorm)

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Hard problem is predicates, not plumbing. GitHub Issues as state store avoids new infrastructure. Cost ceiling concern with polling agents — needs TTL/max-attempts (addressed: 30-day max). Stateful polling is a new pattern for the currently stateless scheduled-agent system.

### Marketing (CMO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** "Follow-Through" name validated (implies agency, not reminders). Content opportunity: pillar article on "why AI agents forget after shipping." Messaging must distinguish tracking from resolution.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Valid workflow gap. Composable foundation scope correct. Scope creep risk if this touches cloud platform (it doesn't — purely GitHub Issues). Detection accuracy ensured by explicit ⏳ marker (no heuristics).

### Product/UX Gate

**Tier:** none — orchestration/infrastructure change, no user-facing pages or UI components.

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| ⏳ emoji not rendering in some environments | Use the literal UTF-8 character, not an image. GitHub renders it correctly in issues and PRs. |
| Predicate checks failing in CI environment | Agent prompt includes fallback: "If dig/curl unavailable, comment status instead of failing" |
| Agent billing from daily cron runs | `timeout-minutes: 15` cap. Cost scales linearly with open issue count: ~3-5 turns per issue (fetch + parse + check + maybe comment). At 10 open issues, expect ~$0.15-0.25/run at sonnet pricing. 30-day max polling is the safety valve. |
| Verification YAML block drift | Fenced code block (`` ```yaml ``) is more reliably extractable than markdown section headers. The monitor uses regex to extract the block, then parses YAML — not LLM heuristic parsing. |

## Alternative Approaches Considered

| Approach | Rejected Because |
|----------|-----------------|
| Standalone `/follow-through` skill | Fragmented workflow — composing into /ship ensures every PR gets scanned |
| Per-item cron workflows | Cron proliferation — one workflow per tracked item would be unmanageable |
| Database state store (Supabase) | Unnecessary infrastructure — GitHub Issues already serve as state store everywhere |
| Keyword heuristic detection | False positives — explicit ⏳ marker gives zero ambiguity |
| Interactive prompt during /ship | Blocks headless mode — explicit marker syntax works in both interactive and headless |

## Implementation Phases

### Phase 1: /ship Phase 7.5 — Detection & Issue Creation

**Files to modify:**

- `plugins/soleur/skills/ship/SKILL.md` — Add Phase 7.5 section

**Tasks:**

1. Add Step 3.5 inside Phase 7's "If merged" block, after Step 3 (post-merge workflow validation), before Step 4 (cleanup)
2. Write detection logic: read PR body, regex match `- [ ] ⏳` and `- [X] ⏳` patterns (both case variants for checked)
3. Write label creation step (follow-through, needs-attention)
4. Write issue creation step with fenced YAML verification block template (all issues default to `manual` type)

### Phase 2: Daily Monitor Workflow

**Files to create:**

- `.github/workflows/scheduled-follow-through.yml`

**Tasks:**

1. Resolve action SHAs for `actions/checkout@v4` and `anthropics/claude-code-action@v1`
2. Generate workflow YAML following `scheduled-daily-triage.yml` pattern
3. Configure `claude_args` with `--allowedTools Bash,Read,Glob,Grep` (sandboxing)
4. Write agent prompt with: fenced YAML block extraction, business-day calculation (skip weekends), predicate execution, state-transition-only commenting, SLA escalation with @-mention, and 30 business day max
5. Add security comment header
6. Validate YAML syntax

### Phase 3: Testing & Validation

**Tasks:**

1. Validate YAML syntax with Python yaml.safe_load
2. After merge, trigger manual workflow run with `gh workflow run`
3. Create a test follow-through issue with `http-200` predicate pointing to a known URL
4. Verify the daily monitor agent processes it correctly

## References

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-04-03-follow-through-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/feat-follow-through/spec.md`
- **Ship skill:** `plugins/soleur/skills/ship/SKILL.md` (Phase 7)
- **Workflow template:** `.github/workflows/scheduled-daily-triage.yml` (cron pattern)
- **Schedule skill:** `plugins/soleur/skills/schedule/SKILL.md` (SHA resolution, template)
- **Trigger issue:** [#1433](https://github.com/jikig-ai/soleur/issues/1433)
- **Source PR:** [#1398](https://github.com/jikig-ai/soleur/pull/1398) (Google OAuth brand verification)
