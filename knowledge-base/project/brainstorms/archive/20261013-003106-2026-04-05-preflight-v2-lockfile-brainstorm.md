# Preflight v2: Lockfile Consistency Check

**Date:** 2026-04-05
**Issue:** #1532
**Status:** Decided

## What We're Building

A diff-scoped lockfile consistency check for the preflight skill. When a PR modifies `package.json` or `bun.lock` but not `package-lock.json` (or vice versa), the preflight gate FAILs. This enforces the existing AGENTS.md rule that both lockfiles must be regenerated when dependencies change.

## Why This Approach

- **Real outage:** #1293 broke all Docker builds for hours because `bun.lock` was updated but `package-lock.json` was not. `npm ci` in Dockerfiles requires `package-lock.json` in sync.
- **Rule without enforcement:** AGENTS.md already documents this requirement but relies on agent memory — no automated gate catches it.
- **Minimal scope:** Domain leaders (CTO, CPO, CMO) converged on lockfile check as the only v2 item backed by a production incident. The other 3 items (agent spawning, Playwright CSP, severity tiers) are speculative hardening.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scope | Lockfile check only | Only item with real outage backing (#1293). Defer agent spawning, Playwright, severity tiers. |
| Detection method | Git diff-scoped | Diff `origin/main...HEAD` for lockfile/package.json changes. Mirrors v1's approach. |
| Check logic | If package.json or bun.lock changed but package-lock.json didn't (or vice versa), FAIL | Catches the exact #1293 scenario. |
| App scope | Only apps touched in the PR | No false positives on untouched apps. Consistent with v1's diff-based checks. |
| Result format | PASS/FAIL/SKIP (v1 system) | 4-tier severity deferred — premature for 3 checks + 1 assertion. |

## Non-Goals (Deferred to #1532)

- **Conditional agent spawning** — inline checks sufficient for v1/v2; agent budget at 2,552/2,500 words
- **Playwright console checks** — needs running dev server; v1 curl already hits prod headers
- **4-tier severity system** — premature for current check count
- **Full-repo lockfile scan** — diff-scoped avoids false positives on untouched apps

## Open Questions

None — scope is clear and implementation is straightforward (pure bash, git diff).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Lockfile check is LOW risk, pure bash. Agent description budget (2,552/2,500) is not impacted since no new agents are added. Recommended phasing: lockfile first, agent spawning later if justified by production misses.

### Product (CPO)

**Summary:** Lockfile check is the highest-leverage move — real outage backing, AGENTS.md rule without enforcement. Other v2 items are speculative hardening for a pre-beta tool with one user. Option B (lockfile only) wins.

### Marketing (CMO)

**Summary:** Ship silently. No announcement warranted for an internal quality gate enhancement. Optional technical blog on "self-assembling QA pipelines" if content calendar has a gap — not tied to this change.
