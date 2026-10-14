# Follow-Through: Automated Tracking for External Dependencies

**Date:** 2026-04-03
**Status:** Decided
**Triggered by:** PR #1398 — Google OAuth brand verification had no tracking mechanism after session ended

## What We're Building

A "Follow-Through" pattern in the Soleur workflow that ensures external dependencies don't fall through the cracks after a PR merges. When `/ship` detects unchecked test plan items marked as external dependencies, it automatically creates tracking issues and a daily monitoring agent that checks status, comments updates, and escalates when SLAs are exceeded.

**Scope:** Composable foundation — detection + tracking + monitoring infrastructure with a plug-in predicate interface for automated verification. Ships with simple checks (HTTP 200, DNS lookup) and manual-confirm fallback. The architecture serves all Soleur users; additional predicates come when there's demand.

## Why This Approach

The problem is universal: every software project has external dependencies that outlive a session (DNS propagation, app store reviews, certificate issuance, brand verification, domain transfers). Current Soleur workflow ends at PR merge — anything that requires waiting days gets forgotten.

Three domain leaders (CPO, CMO, CTO) independently converged on "composable foundation" as the right scope:

- **Full automation** requires bespoke predicate logic per external service — 80% of complexity for 20% of value at N=1 users
- **Issue-only tracking** solves the forgetting problem but provides zero proactive monitoring
- **Composable foundation** gives the tracking and monitoring infrastructure that ALL Soleur users need, with a clean interface for plugging in automated verification as demand justifies it

## Key Decisions

| Decision | Choice | Alternatives Considered | Rationale |
|----------|--------|------------------------|-----------|
| Scope | Composable foundation | Full automation, minimal issue-only | Balances "build for users" with YAGNI. Architecture supports future predicates without requiring them now. |
| Detection method | Explicit marker syntax (⏳ emoji) | Keyword heuristic, interactive prompt | Zero ambiguity. Author marks external items intentionally. No false positives. |
| User-facing name | "Follow-Through" | "Deferred Verification", "Pending Verification", "Open Loop" | Implies agency and completion. Aligns with brand voice ("agents execute"). Not assistant language ("reminder", "todo"). |
| Notification | GitHub Issue comments + escalation after timeout | Issue comment only, issue + PR comment | Low noise daily. Escalation (reopen + label + @mention) guarantees visibility after SLA. |
| Architecture | Extend /ship Phase 7.5 + single daily cron | Standalone skill, per-item cron | "Compose, not orchestrate." One shared workflow handles all items. No cron proliferation. |
| Resolution | Agent auto-closes on verification | User confirms manually, agent suggests + user confirms | Fully autonomous for simple cases. Predicate interface returns pass/fail. Manual-confirm is the fallback when no predicate exists. |
| State store | GitHub Issues (body + comments) | Dedicated database, file-based | Already used everywhere. No new infrastructure. Labels as state machine. |
| GitHub label | `follow-through` | `deferred-verification`, `pending` | Matches the capability name. |

## Components

### 1. /ship Phase 7.5 — Follow-Through Detection

After PR merges and release workflows succeed, parse the PR body for unchecked test plan items with the ⏳ marker:

```markdown
- [ ] ⏳ Brand verification completes after homepage deploys (2-3 business days)
```

For each detected item, create a GitHub issue:

- **Title:** `follow-through: <item description>`
- **Label:** `follow-through`
- **Milestone:** from roadmap or "Post-MVP / Later"
- **Body:** What's being tracked, source PR, expected SLA, verification predicate (if known)

### 2. scheduled-follow-through.yml — Daily Monitor

A single GitHub Actions cron workflow running weekdays at 9am:

1. Scan all open issues with `follow-through` label
2. For each issue:
   - Parse SLA and creation date from issue body
   - If a predicate is defined, run it (DNS lookup, HTTP probe, etc.)
   - If predicate passes → auto-close with "Verified" comment
   - If within SLA → comment status update ("Day 3/5: still pending")
   - If SLA exceeded → add `needs-attention` label, @mention user

### 3. Predicate Interface (composable, extensible)

Each follow-through issue can include a verification block in its body:

```markdown
## Verification
- **Type:** dns-txt
- **Domain:** soleur.ai
- **Expected:** google-site-verification=abc123
- **SLA:** 5 business days
```

Supported predicate types at launch:

- `manual` — no automated check, user closes manually (default fallback)
- `http-200` — check URL returns HTTP 200
- `dns-txt` — check domain has expected TXT record
- `dns-a` — check domain resolves to expected IP

Future predicate types (deferred):

- `playwright` — browser-based verification (Google Cloud Console, app store dashboards)
- `api-status` — query vendor API for status
- `certificate` — verify TLS certificate issuance

### 4. Test Plan Marker Convention

PR authors mark external dependencies in test plans with the ⏳ emoji:

```markdown
## Test plan

- [x] Unit tests pass
- [x] Integration tests pass
- [ ] ⏳ Brand verification completes after homepage deploys (2-3 business days)
- [ ] ⏳ DNS propagation confirmed globally (24-48 hours)
```

## Open Questions

1. Should the daily cron also handle follow-through items created manually (not from /ship)? e.g., a user runs `/soleur:follow-through create` for an ad-hoc external dependency.
2. What's the maximum SLA before the cron stops checking? (Default 30 days, then auto-escalate and stop polling.)
3. Should predicate failures (DNS lookup timeout, HTTP error) count as "still pending" or trigger immediate escalation?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Valid workflow gap with existing infrastructure to compose. Recommended starting lightweight (Option A) to avoid premature generalization at N=1 users. Flagged scope creep risk if this touches the cloud platform (notifications, dashboard). Detection heuristic accuracy is the key design decision.

### Marketing (CMO)

**Summary:** "Deferred Verification" is internal jargon — needs user-facing name (resolved: "Follow-Through"). Frame as organizational memory, not reminders. Overpromise risk: messaging must distinguish "tracking and notification" from "resolution." Content opportunity: pillar article on "why AI agents forget after shipping" and "Built with Soleur" case study.

### Engineering (CTO)

**Summary:** Hard problem is completion predicates, not plumbing. GitHub Issues as state store avoids new infrastructure. Cost ceiling concern with polling agents — needs TTL/max-attempts. Recommended Option A with evolution to hybrid (Option C). Stateful polling is a new pattern for the currently stateless scheduled-agent system.
