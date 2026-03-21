# Continuous Community Agent Brainstorm

**Date:** 2026-03-10
**Issue:** #145
**Branch:** feat-continuous-community-agent
**Status:** Decided

## What We're Building

A scheduled GitHub Actions workflow that runs the community agent daily to monitor Discord activity and X/Twitter metrics, generate a unified digest, and queue drafted replies as GitHub Issues for human batch review. No autonomous posting — the human remains the final approval gate.

### Scope

**In scope:**

- Daily scheduled workflow (`cron` + `workflow_dispatch`) using `claude-code-action`
- Discord monitoring: message volume, active members, notable conversations
- X/Twitter metrics: profile stats (followers, tweets) via Free tier API
- Combined digest generation committed to `knowledge-base/community/`
- Draft reply queue as a GitHub Issue per run
- Safety constraints: timeout, max-turns, concurrency group

**Out of scope (deferred):**

- Autonomous reply posting (no human approval bypass)
- X mention fetching (Free tier returns 403; deferred until paid API tier)
- Playwright web fallback for X scraping (fragile in CI)
- GitHub discussions monitoring
- Cross-platform content suggestions

## Why This Approach

### The Problem

The community agent requires manual invocation via `/soleur:community`. Digests go stale (last digest: 2026-02-19, 19 days old). Mentions may go unnoticed for days. There is no systematic community monitoring cadence.

### Why Scheduled Monitoring + Draft Queue

Three domain leaders (CMO, CCO, CTO) independently converged on the same conclusion:

1. **The system is explicitly designed against autonomous posting.** Headless engage skips all mentions. The brand guide names the human reviewer as the enforcement mechanism (line 169). Removing the human gate requires an automated content filter or confidence-scoring system that does not exist.

2. **Risk-reward ratio at current scale.** Near-zero followers, zero external users, PIVOT/validation mode. Autonomous engagement on a near-empty account risks looking performative. At 2 mentions/week, manual review is trivially easy.

3. **The scheduling infrastructure already exists.** Four GitHub Actions workflows use `claude-code-action` with cron triggers. Following this pattern is straightforward and proven.

### Why Defer X Mention Fetching

- X Free tier returns 403 on `GET /2/users/:id/mentions`
- Playwright in CI requires session cookie management and X actively blocks automated browsers
- X profile metrics (followers, tweet count) work on Free tier and provide health signal without mention data
- When paid tier ($100/mo) is budgeted, mention fetching can be added as a one-line change

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Autonomy: monitoring + draft queue, no autonomous posting** | Brand guide relies on human reviewer. No automated guardrail enforcement exists. All three domain leaders recommended this. |
| 2 | **Trigger: GitHub Actions cron + workflow_dispatch** | Consistent with 4 existing scheduled workflows. Not local cron. |
| 3 | **Cadence: daily** | Near-zero mention volume. Daily is sufficient and cost-effective (~30 runs/month). |
| 4 | **Platforms: Discord + X metrics** | Discord has free, reliable API. X metrics work on Free tier. X mentions deferred. |
| 5 | **Draft queue: GitHub Issue per run** | Consistent with how scheduled-bug-fixer reports. Easy to review and act on. |
| 6 | **Digest scope: mentions + metrics + activity summary** | Comprehensive enough to be useful, not so detailed it's noisy. |
| 7 | **Architecture: single claude-code-action workflow** | One workflow file. Agent handles fetching, drafting, and reporting. Simplest approach. |
| 8 | **X mentions: deferred until paid API tier** | Free tier blocks mention endpoint. Playwright fallback too fragile for CI. |

## Domain Leader Assessments

### CMO Assessment

- **Critical concern:** Brand voice drift without human review. The brand voice is specific (declarative, no hedging, no pleasantries) and guardrails require nuanced judgment ("skip rage-bait," "review full account history").
- **"Bot account" perception risk:** Continuous posting at mechanical intervals is identity-destructive for a "one founder, full conviction" brand.
- **Recommendation:** Split into scheduled monitoring (low risk, build now) vs autonomous posting (high risk, defer). Start with automated digest generation as a proving ground.

### CCO Assessment

- **Current engage is intentionally a no-op in headless mode.** This was a deliberate design decision, not a bug.
- **Missing support infrastructure:** No incident response runbook, no escalation guide, no `knowledge-base/support/` directory.
- **Shadow mode recommendation:** Before any autonomous posting, run in shadow mode (draft-and-log-without-posting) for 2-4 weeks to validate draft quality.
- **Prerequisite list:** Automated guardrail enforcement, circuit breaker/kill switch, support runbooks — all needed before autonomous posting.

### CTO Assessment

- **Architecture tension:** Human-in-the-loop vs autonomy. The entire engagement pipeline was designed with the human as the final gate.
- **State persistence gap:** `since-id` tracking is local file only. CI needs GitHub repository variables (`gh variable set`) or committed state files.
- **Cost runaway risk:** Paid X API has no documented spending ceiling. Needs hard caps: max N replies per run, monthly tweet counter.
- **Recommendation:** Option 2 (autonomous draft + deferred human review) solves the friction problem without introducing autonomous posting risk.

## Institutional Learnings Applied

16 documented learnings inform this design:

- **Guardrails must match observable data** — policy rules the agent can't verify from its data pipeline will be silently ignored
- **Discord webhook sanitization** — always set `allowed_mentions: {parse: []}` to prevent @everyone pings
- **Scheduled bot workflow patterns** — baseline verification, cascading priority, label-based dedup, skip issues with open PRs, use `Ref #N`
- **claude-code-action token revocation** — file persistence must happen inside the agent prompt, not a subsequent step
- **X API pay-per-use billing** — detect HTTP 402 specifically; web UI works regardless of credit balance
- **Shell API wrapper hardening** — 5 defense layers: input validation, curl stderr suppression, JSON validation, float retry, jq fallback
- **Depth-limited retries** — max 3 retry depth on all API calls to prevent stack overflow under rate limiting

## Open Questions

1. **State persistence for since-id in CI:** GitHub repository variable (`gh variable set`) vs committed state file vs Actions artifact. CTO recommends repo variable as cleanest.
2. **X API secrets provisioning:** `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` need to be added as GitHub Actions secrets when X mention fetching is enabled.
3. **Digest posting destination:** Should the daily digest also post to Discord (via webhook) or just commit to the repo?
4. **Failure notification:** Should failed runs notify via Discord webhook (like other workflows) or just create a labeled issue?

## Capability Gaps

| Gap | Domain | What Is Missing | Why Needed |
|-----|--------|-----------------|------------|
| Automated guardrail enforcement | Engineering | No content filter or confidence scorer; brand guide relies on human reviewer | Required before any future autonomous posting phase |
| CI-persistent state mechanism | Engineering | No pattern for persisting small state values across scheduled workflow runs | since-id tracking must survive between runs |
| Monitoring and alerting | Operations | No cost tracking for X API credits | Continuous agent needs spending observability |
| Support runbooks | Support | `knowledge-base/support/` does not exist | Incident response, escalation procedures undocumented |
| Shadow mode capability | Engineering | No "draft-and-log-without-posting" mode | Needed to validate autonomous draft quality before going live |
