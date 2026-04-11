# CI/CD Integration for Cloud Platform Agents

**Date:** 2026-04-10
**Issue:** #1062
**Status:** Brainstorm complete
**Branch:** cicd-integration

## What We're Building

Cloud platform agents need to interact with the founder's CI/CD pipeline — read CI status, trigger workflows, run tests, and open PRs. This closes the capability gap between the CLI plugin (full local toolchain access) and the cloud platform (currently no CI/CD access).

The feature decomposes into 4 sequential slices, each shipping as its own issue:

1. **GitHub App + proxy infrastructure** — shared foundation for all CI/CD capabilities
2. **Read CI status/logs** — first consumer, validates the infra works
3. **Trigger GitHub Actions workflows** — adds write actions through the proxy
4. **Open PRs** — highest-trust action, adds contents:write + pull_requests:write

## Why This Approach

### GitHub App over PAT or OAuth

A GitHub App provides per-repo permissions with short-lived installation tokens and automatic rotation. Unlike PATs (user-managed, often over-scoped) or OAuth (user-scoped to all repos), the App model gives the tightest permission boundary. The onboarding flow is clean: founder installs the Soleur app on their repo during setup.

### Server-side proxy over direct network access

The current sandbox is deny-all (`allowedDomains: []`). Rather than opening the network to github.com (which would allow exfiltration via gists, issue comments, or cross-repo access), all GitHub API calls route through a platform-side proxy. The proxy validates: target repo matches the workspace, endpoint is on the allowlist, request is within rate limits. The agent subprocess never touches github.com directly.

This pattern generalizes to all future service integrations (#1050) — each new service gets a proxy endpoint, not a domain allowlist entry.

### Tiered review gates enforced at proxy layer

| Tier | Actions | Enforcement |
|------|---------|-------------|
| Auto-approve | Read CI status, read logs, read workflow runs | Proxy passes through |
| Gate (founder confirms) | Trigger workflows, push to feature branches, open PRs | Proxy holds until founder approves in conversation |
| Block (never allowed) | Force-push, push to main/master, delete branches, close issues | Proxy rejects unconditionally |

Gates are enforced at the proxy layer, not by agent self-restraint. The agent cannot bypass them.

### Foundation-first sequencing

The GitHub App and proxy are shared infrastructure needed by all 4 slices. Building them first means each subsequent slice is incremental — just adding new proxy allowlist entries and review gate tiers. Each slice ships independently with its own security review.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth mechanism | GitHub App | Per-repo scope, short-lived tokens, automatic rotation, clean onboarding |
| Network policy | Server-side proxy | Agent never touches github.com; prevents exfiltration; generalizes to all services |
| Review gates | Tiered (auto/gate/block) | Proxy-enforced, not agent-decided; balances safety with usability |
| Scope | 4 issues, all P3 | Prerequisites resolved (#1060, #1044, #1076); full scope feasible |
| Build order | Foundation first, then sequential | Each slice builds on the last; clear gates between them |
| Decomposition | Break #1062 into 4 child issues | Each has distinct auth scope, security surface, and can ship independently |

## Open Questions

- **`gh` CLI vs raw API in agent sandbox?** Agent could use `gh` (needs binary in container + auth injection) or `curl` against the proxy. Proxy approach may make `curl` more natural since the endpoint is local.
- **CI log truncation** — GitHub Actions logs can be enormous. How much CI output should be fed back to agent context? May need summarization or tail-only.
- **"Run tests" = local or CI?** The issue says "via the workspace's test runner" which implies local execution (already possible if deps are installed). Triggering CI to run tests is covered by slice 3. Clarify in planning.
- **GPG signing** — If the founder's repo requires signed commits, pushes from the cloud platform will be rejected. Need a policy (Soleur GPG key? Skip requirement? Founder configures exemption?).
- **Rate limiting** — Multiple Soleur users triggering workflows through the same GitHub App could hit app-level rate limits. Need monitoring.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Feature requires solving 3 architecture decisions: GitHub auth mechanism, network sandbox policy, and review gate model. The CTO recommends GitHub App with server-side proxy. Complexity estimate: large (week+), partially driven by prerequisites that are now resolved. Two formal ADRs recommended: GitHub auth mechanism and network sandbox outbound access policy.

### Product (CPO)

**Summary:** The CPO flagged scope as deceptively large (4 capabilities, not 1 feature) and recommended read-only first to validate demand. With prerequisites resolved and the decision to decompose into 4 sequential issues, the risk is mitigated — each slice validates independently. Key UX questions: how founders grant repo access (GitHub App install flow), how CI results surface (inline vs. dedicated panel), and graduated trust levels for review gates.

## Capability Gaps

| Gap | Domain | What's Missing | Impact |
|-----|--------|---------------|--------|
| Domain leader stale data verification | Engineering | CTO, CFO, CRO, CCO, COO, CMO assess phases lack `gh issue view` verification instruction that CPO already has | Domain leaders operate on stale issue state, producing inaccurate assessments (observed in this brainstorm: CTO cited 3 closed issues as blockers) |
