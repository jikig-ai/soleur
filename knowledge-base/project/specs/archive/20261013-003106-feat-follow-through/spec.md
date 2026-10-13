# Spec: Follow-Through — Automated External Dependency Tracking

**Issue:** [#1433](https://github.com/jikig-ai/soleur/issues/1433)
**Branch:** deferred-verification
**Brainstorm:** [2026-04-03-follow-through-brainstorm.md](../../brainstorms/2026-04-03-follow-through-brainstorm.md)

## Problem Statement

When `/ship` produces a PR with unchecked test plan items that depend on external processes (Google brand verification, DNS propagation, app store reviews, certificate issuance), there is no mechanism to track resolution after the session ends. Users must manually remember to check back, leading to forgotten verifications and silent failures.

## Goals

1. Ensure no external dependency is forgotten after a PR merges
2. Provide proactive monitoring with status updates and escalation
3. Auto-resolve when automated verification is possible
4. Design a composable foundation that serves all Soleur users

## Non-Goals

- Cloud platform UI integration (dashboard widgets, push notifications) — deferred to P3
- Playwright-based browser verification predicates — deferred until demand justifies complexity
- Vendor-specific API integrations (Google Cloud, AWS, Apple) — deferred
- Per-item cron workflows — single shared workflow handles all items

## Functional Requirements

- **FR1:** `/ship` Phase 7 Step 3.5 parses PR body for unchecked test plan items marked with ⏳ emoji
- **FR2:** For each detected item, creates a GitHub issue with `follow-through` label, structured body (description, source PR, SLA, predicate type)
- **FR3:** A daily cron workflow (`scheduled-follow-through.yml`) scans all open `follow-through` issues
- **FR4:** For issues with a predicate defined, the agent runs the check and auto-closes if verification passes
- **FR5:** For issues within SLA with no state change, the agent takes no action (silent monitoring — comments only on state transitions)
- **FR6:** For issues exceeding SLA, the agent adds `needs-attention` label and @mentions the user
- **FR7:** Supported predicate types at launch: `manual`, `http-200`, `dns-txt`, `dns-a`

## Technical Requirements

- **TR1:** Detection uses explicit ⏳ marker syntax — no keyword heuristics
- **TR2:** GitHub Issues serve as the state store (body for config, comments for history)
- **TR3:** Single shared cron workflow (no per-item workflow proliferation)
- **TR4:** Cron workflow uses `claude-code-action` with `--allowedTools` for sandbox compatibility
- **TR5:** Maximum polling duration: 30 days, then auto-escalate and stop
- **TR6:** Predicate interface is structured YAML in issue body (type, parameters, SLA)
- **TR7:** `follow-through` label created automatically if it doesn't exist

## Acceptance Criteria

- [ ] PR with ⏳-marked unchecked items triggers follow-through issue creation at ship time
- [ ] Daily cron workflow runs, comments on open follow-through issues
- [ ] SLA escalation works: issue gets `needs-attention` label + @mention after timeout
- [ ] `dns-txt` predicate auto-closes issue when record is found
- [ ] `http-200` predicate auto-closes issue when URL returns 200
- [ ] Manual predicate leaves issue open for user to close
- [ ] No follow-through issues created for unchecked items without ⏳ marker
