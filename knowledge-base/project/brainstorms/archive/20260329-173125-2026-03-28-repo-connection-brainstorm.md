# Project Repo Connection Brainstorm

**Date:** 2026-03-28
**Issue:** #1060
**Branch:** feat-repo-connection
**Participants:** Founder, CTO, CPO, CMO, CLO

## What We're Building

A feature that connects the founder's actual GitHub repository to their Soleur cloud workspace. Instead of agents operating in an empty shell, they work against the real codebase with full context -- code, specs, knowledge-base, and institutional memory.

For founders without a repo, Soleur auto-creates a GitHub repository with a scaffolded `knowledge-base/` structure, giving every founder a project repo from day one.

This is Phase 1, item 1.10 of the product roadmap.

## Why This Approach

The cloud platform's current empty-workspace model means agents operate in a vacuum -- no codebase context, no skills, no domain leaders, no institutional memory. Every other Phase 1 feature (multi-turn conversations, tag-and-route) delivers marginal value without a real codebase underneath.

Connecting the founder's actual repo is what transforms Soleur from "AI chat" to "AI team that knows your codebase." The CMO identified this as the single most important marketing event on the roadmap -- the feature that makes every positioning claim demonstrably true.

## Key Decisions

### 1. Full Bidirectional Sync (Read + Commit + Push)

Agents can read the full codebase, commit changes, and push back to GitHub. This is the complete value proposition from day one. Changes sync at session boundaries: pull on session start, push on session end.

**Trade-off:** More complex than read-only (CTO estimates 2-3 weeks vs 3-5 days), but delivers the real product experience. A read-only clone would break the current agent workflow that relies on committing artifacts.

### 2. GitHub App with Short-Lived Installation Tokens

A registered Soleur GitHub App handles authentication. Founders install it on their account/repo during onboarding. The app generates short-lived installation tokens (1hr expiry) for git operations.

**Why not PAT/deploy keys:** GitHub App tokens have the lowest blast radius (auto-expire, granular per-repo permissions, no long-lived secrets stored). PATs expose the founder's entire GitHub account. Deploy keys require manual setup per repo.

**Security architecture:** Installation tokens are generated server-side and injected via a git credential helper. They are never exposed to the agent sandbox. The existing three-tier sandbox model (bubblewrap + canUseTool + disallowedTools) remains intact. Git push/pull operations happen server-side, outside the agent sandbox.

### 3. GitHub Only for P1

GitHub has 90%+ market share among solo founders and startups. Supporting one platform well is better than three poorly. GitLab and Bitbucket deferred to a later phase.

### 4. Onboarding After API Key, Before Dashboard

The flow becomes: Signup -> Email -> T&C -> API key -> **Connect Repo** -> Dashboard. This maximizes the "aha moment" -- the first agent conversation already has full codebase context.

**Skip path:** The repo connection step is optional. Founders without a repo (or who want to try first) can skip and connect later from settings. However, the default path encourages connection.

### 5. Auto-Create Repo for Founders Without One

When a founder has no existing repo, Soleur auto-creates a GitHub repository via the GitHub App with a scaffolded `knowledge-base/` structure. Every founder gets a project repo from day one, even pre-code founders.

**Requires:** GitHub App `repo:create` scope. The auto-created repo includes `knowledge-base/` directories, a `CLAUDE.md`, and an initial commit.

### 6. Knowledge-Base in Repo Root

Agent-generated artifacts (brand guides, specs, legal docs) live in `knowledge-base/` at the repo root, committed to the founder's actual repository. Same pattern as Soleur's own repo.

**Why not .soleur/ or separate branch:** Artifacts should persist outside Soleur, be visible to the founder's team, and work with other tools. A hidden directory or separate branch creates friction and fragility.

### 7. Full Agent Write Access

Agents can modify any file in the repository, not just `knowledge-base/`. This is the core value proposition -- the AI team works on the founder's actual code. The existing sandbox security model (path containment to workspace) applies.

**Risk mitigation:** PR-based workflow in later phases. For P1, agents commit directly to the workspace clone. The founder reviews changes when they pull.

### 8. Shallow Clone (--depth 1)

Fast clone, minimal disk usage. Agents get current files but no git history. Most domain leaders (marketing, legal, product) don't need history. Engineering agents lose `git log`/`blame` but gain working codebase context.

**Trade-off:** Full clone would give agents history but consumes 2-10x more disk and takes minutes for large repos. Treeless clone requires network during agent sessions (sandbox blocks this). Shallow clone is the pragmatic P1 choice -- can deepen later if needed.

### 9. Pull on Session Start, Push on Session End

Sync happens at session boundaries. Before an agent session starts, the server pulls latest from GitHub. After the session ends, the server pushes agent commits. This is predictable, low-complexity, and avoids mid-session conflicts.

**Future consideration:** Webhook-based continuous sync can be added later for near-real-time collaboration.

## Open Questions

1. **Clone latency UX:** Large repos may take 30+ seconds even with `--depth 1`. What loading state do we show? "Setting up your AI organization..." messaging could reinforce value during the wait.

2. **Conflict resolution:** If the founder pushes to GitHub between sessions, the next pull may have conflicts with uncommitted agent changes. P1 approach: fail-safe -- if pull conflicts, skip pull and warn the founder. Proper merge/rebase in a later phase.

3. **Disk quotas:** The Hetzner volume is 20GB for all user workspaces. Need monitoring and a plan for when capacity is reached. Per-user quotas or volume expansion via Terraform.

4. **Plugin symlink conflict:** If the cloned repo already has a `plugins/` directory (e.g., dogfooding Soleur's own repo), the symlink creation needs to handle this gracefully. Platform-managed symlink takes precedence.

5. **Git identity:** Commits from agents are currently attributed to "Soleur <soleur@localhost>". Should they use the founder's identity? Per-workspace git config needed.

6. **GitHub App registration:** Need to register the app, configure OAuth callback URL, set up webhook endpoint. This is a prerequisite before any implementation.

7. **Legal document updates:** CLO identified that all existing legal documents (T&C, Privacy Policy, GDPR Policy, Data Protection Disclosure, AUP) need updates before this feature is exposed to external users. P0: DPA for source code processing. P1: T&C IP/credential/liability sections, Privacy Policy data categories, GDPR processing register.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** P1 with full bidirectional sync is 2-3 weeks of work. Major architectural decisions around credential isolation (git credential helper outside sandbox), network sandbox carve-out for server-side sync, and disk strategy. Recommends cloning outside the sandbox (in `provisionWorkspace`, not agent-initiated) and keeping the plugin symlink approach. Two architecture decisions to capture: git credential isolation model and workspace sync model.

### Product (CPO)

**Summary:** This is the product-defining feature -- without it, agents run against an empty shell with zero context. Flagged 5 critical product questions (all resolved in brainstorm). Identified roadmap inconsistencies: Phase 1 milestone still mentions Telegram (deferred), issue #1060 says item 1.11 (should be 1.10), issue includes private repo scope (contradicts P1 public-only). Recommended path A (brainstorm first, then spec) -- now complete.

### Marketing (CMO)

**Summary:** Single most important marketing event on the roadmap. Transforms every positioning claim from aspirational to demonstrable. The onboarding "connect your repo" moment is the conversion/retention event. Flagged "plugin" language contradiction (onboarding will expose `claude plugin install soleur` to users -- must resolve M1-M2 brand term compliance before external launch). Competitive differentiation is massive: no competitor offers an AI organization operating on the founder's actual project with full cross-domain context.

### Legal (CLO)

**Summary:** Fundamental shift in Soleur's data processing profile. Storing source code and git credentials triggers GDPR Article 28 (processor obligations), requires a Data Processing Agreement, and necessitates updates to all existing legal documents. Critical gaps: no IP ownership/license clause, no credential handling terms, no AI agent liability framework, no data deletion/portability terms. Recommended DPIA (Data Protection Impact Assessment) for AI agent processing of source code. Short-lived tokens (GitHub App) reduce credential breach blast radius significantly.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|------------|
| No GitHub OAuth / GitHub App integration | Engineering | Connecting repos requires OAuth consent flow or GitHub App installation. No existing code handles this. |
| No async workspace provisioning | Engineering | Clone operations are long-running. Current `provisionWorkspace` is synchronous. Needs a job queue or polling pattern. |
| Legal documents do not cover source code storage | Legal | All 7 legal documents need updates before external user exposure. DPA required for GDPR compliance. |
| "Plugin" language in onboarding | Marketing | Brand term contradiction becomes user-facing during the highest-stakes onboarding moment. |
