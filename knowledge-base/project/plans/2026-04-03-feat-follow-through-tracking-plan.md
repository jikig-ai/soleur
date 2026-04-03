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
3. **Predicate interface** — Structured YAML in issue body for automated verification (http-200, dns-txt, dns-a, manual)

## Technical Approach

### Component 1: /ship Phase 7.5 — Follow-Through Detection

**File:** `plugins/soleur/skills/ship/SKILL.md`

**Placement:** After Phase 7 Step 3 (post-merge workflow validation), before Step 4 (cleanup). At this point:

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

Step 3 — For each detected item, extract structured metadata if present. Items may include parenthetical hints:

```text
- [ ] ⏳ Brand verification completes (2-3 business days)
- [ ] ⏳ DNS propagation confirmed globally (24-48 hours, dns-a: 1.2.3.4)
```

Parse optional predicate hints from the description. Default to `manual` type and `5 business days` SLA if not specified.

Step 4 — Ensure the `follow-through` and `needs-attention` labels exist:

```text
gh label create "follow-through" --description "External dependency awaiting verification" --color "C5DEF5" 2>/dev/null || true
gh label create "needs-attention" --description "SLA exceeded, requires human action" --color "D93F0B" 2>/dev/null || true
```

Step 5 — For each detected item, create a GitHub issue. Read `knowledge-base/product/roadmap.md` to determine the milestone (or default to "Post-MVP / Later"):

```text
gh issue create --title "follow-through: <item description>" --label "follow-through" --milestone "<milestone>" --body "<structured body>"
```

**Issue body template:**

```markdown
## Follow-Through Item

<item description>

**Source PR:** #<PR_NUMBER>
**Created by:** /ship Phase 7.5
**Created:** <YYYY-MM-DD>

## Verification

- **Type:** <manual|http-200|dns-txt|dns-a>
- **SLA:** <N business days>
<type-specific fields, e.g.:>
- **URL:** <url for http-200>
- **Domain:** <domain for dns-txt/dns-a>
- **Expected:** <expected value>

## Status

Awaiting verification. The daily follow-through monitor will check this issue.
```

Step 6 — Report: "Created N follow-through issue(s): #X, #Y, #Z"

**If no ⏳-marked items found:** Skip silently, proceed to Step 4 (cleanup).

### Component 2: scheduled-follow-through.yml — Daily Monitor

**File:** `.github/workflows/scheduled-follow-through.yml`

Follow the existing scheduled workflow pattern from `scheduled-daily-triage.yml`:

- SHA-pinned actions (resolve at plan time via `gh api`)
- `concurrency: group: schedule-follow-through, cancel-in-progress: false`
- `permissions: contents: read, issues: write, id-token: write`
- `timeout-minutes: 15` (lightweight — just issue scanning and predicate checks)
- Cron: `0 9 * * 1-5` (9am UTC weekdays)
- `workflow_dispatch: {}` for manual testing

**Agent prompt structure:**

The claude-code-action agent receives a prompt to:

1. List open issues with `follow-through` label: `gh issue list --label follow-through --state open --json number,title,body,createdAt --jq '.'`
2. For each issue:
   a. Parse the `## Verification` block from the issue body
   b. Calculate days elapsed since creation
   c. Based on predicate type:
      - `manual`: Skip automated check, only track SLA
      - `http-200`: Run `curl -s -o /dev/null -w "%{http_code}" <URL>` and check for 200
      - `dns-txt`: Run `dig +short TXT <domain>` and check for expected value
      - `dns-a`: Run `dig +short A <domain>` and check for expected IP
   d. Based on result:
      - **Predicate passes** → Close issue with comment: "Verified: <predicate result>. Auto-closing."
      - **Within SLA** → Comment: "Day N/M: still pending. <predicate result if checked>"
      - **SLA exceeded** → Add `needs-attention` label, comment: "SLA exceeded (N days). Escalating."
      - **Max polling exceeded (30 days)** → Add `needs-attention` label, comment: "Maximum polling period reached (30 days). Stopping automated monitoring. Manual intervention required." Close the issue.
3. Output a summary table of all checked issues and their status.

**Sharp edges for agent prompt:**

- Never modify issue body (only comments and labels)
- Never create new issues
- Never close issues unless predicate passes or 30-day max exceeded
- If `gh` commands fail, skip the issue and continue
- If `dig` or `curl` are unavailable, fall back to status comment: "Predicate check unavailable in this environment"

### Component 3: Predicate Interface

No separate implementation needed — this is the structured YAML format in the issue body parsed by the daily monitor agent. The format is:

| Type | Fields | Check Command | Pass Condition |
|------|--------|---------------|----------------|
| `manual` | (none) | N/A | User closes manually |
| `http-200` | URL | `curl -s -o /dev/null -w "%{http_code}" <URL>` | HTTP 200 |
| `dns-txt` | Domain, Expected | `dig +short TXT <domain>` | Contains expected value |
| `dns-a` | Domain, Expected | `dig +short A <domain>` | Contains expected IP |

### Inline Predicate Hint Syntax

Authors can embed predicate hints directly in ⏳-marked test plan items:

```markdown
- [ ] ⏳ Homepage returns 200 (http-200: https://soleur.ai, 3 days)
- [ ] ⏳ DNS TXT record propagated (dns-txt: soleur.ai, google-site-verification=abc, 5 days)
- [ ] ⏳ Server IP resolves (dns-a: api.soleur.ai, 1.2.3.4, 2 days)
- [ ] ⏳ Brand verification completes (7 days)  ← defaults to manual
```

Phase 7.5 parses these hints to populate the issue body's Verification block. If no hint is provided, the predicate type defaults to `manual` and SLA to `5 business days`.

## Acceptance Criteria

- [ ] PR with ⏳-marked unchecked items triggers follow-through issue creation at ship time
- [ ] Issues have structured body with Verification block (type, SLA, parameters)
- [ ] `follow-through` and `needs-attention` labels are created automatically
- [ ] Daily cron workflow runs weekdays at 9am UTC
- [ ] Agent comments status updates on open follow-through issues
- [ ] `dns-txt` predicate auto-closes issue when record is found
- [ ] `http-200` predicate auto-closes issue when URL returns 200
- [ ] Manual predicate leaves issue open for user to close
- [ ] SLA escalation adds `needs-attention` label and comments
- [ ] 30-day max polling closes issue with escalation
- [ ] No follow-through issues created for unchecked items without ⏳ marker
- [ ] Workflow follows existing patterns (SHA-pinned actions, concurrency group, security comment)

## Test Scenarios

### Detection Tests

- Given a PR body with `- [ ] ⏳ DNS propagation confirmed (dns-a: api.soleur.ai, 1.2.3.4, 2 days)`, when /ship Phase 7.5 runs, then a follow-through issue is created with type `dns-a`, domain `api.soleur.ai`, expected `1.2.3.4`, SLA `2 days`
- Given a PR body with `- [ ] ⏳ Brand verification completes (7 days)`, when Phase 7.5 runs, then issue is created with type `manual`, SLA `7 days`
- Given a PR body with `- [ ] ⏳ Something pending`, when Phase 7.5 runs, then issue is created with type `manual`, SLA `5 business days` (defaults)
- Given a PR body with `- [x] ⏳ Already done`, when Phase 7.5 runs, then no issue is created (item is checked)
- Given a PR body with `- [ ] Regular unchecked item` (no ⏳), when Phase 7.5 runs, then no issue is created
- Given a PR body with zero ⏳ items, when Phase 7.5 runs, then Phase 7.5 is skipped silently

### Monitor Tests

- Given an open follow-through issue with `http-200` predicate and URL returning 200, when daily monitor runs, then issue is auto-closed with "Verified" comment
- Given an open follow-through issue with `dns-a` predicate and domain not resolving, when daily monitor runs within SLA, then status comment is added
- Given an open follow-through issue past SLA, when daily monitor runs, then `needs-attention` label is added and escalation comment posted
- Given an open follow-through issue at 30 days, when daily monitor runs, then issue is closed with "Maximum polling period reached" comment

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
| Agent billing from daily cron runs | `timeout-minutes: 15` cap. Expected 10-30 turns per run (list + parse + check). ~$0.10-0.30/day at sonnet pricing. |
| Issue body parsing fragility | Structured YAML format with clear section headers. Agent parses with explicit delimiter matching, not heuristic. |
| Duplicate issue creation on re-runs | Phase 7.5 only runs once during ship (after merge confirmation). If ship is re-invoked, the PR is already MERGED and the phase would detect existing issues before creating duplicates. Add a guard: check for existing open issues with `follow-through` label referencing the same PR number. |

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

1. Add Phase 7.5 section after existing Phase 7 Step 3 (post-merge workflow validation), before Step 4 (cleanup)
2. Write detection logic: read PR body, regex match ⏳-marked unchecked items
3. Write inline hint parser: extract predicate type, parameters, SLA from parenthetical hints
4. Write label creation step (follow-through, needs-attention)
5. Write issue creation step with structured body template
6. Add duplicate detection guard (check existing issues for same PR)

### Phase 2: Daily Monitor Workflow

**Files to create:**

- `.github/workflows/scheduled-follow-through.yml`

**Tasks:**

1. Resolve action SHAs for `actions/checkout@v4` and `anthropics/claude-code-action@v1`
2. Generate workflow YAML following `scheduled-daily-triage.yml` pattern
3. Write agent prompt with predicate execution, status commenting, SLA escalation, and 30-day max
4. Add security comment header
5. Validate YAML syntax

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
- **Label state machine:** `.github/workflows/scheduled-ship-merge.yml` (ship/failed pattern)
- **Schedule skill:** `plugins/soleur/skills/schedule/SKILL.md` (SHA resolution, template)
- **Trigger issue:** [#1433](https://github.com/jikig-ai/soleur/issues/1433)
- **Source PR:** [#1398](https://github.com/jikig-ai/soleur/pull/1398) (Google OAuth brand verification)
