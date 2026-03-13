# Brainstorm: Domain-First Directory Restructure

**Date:** 2026-02-12
**Status:** Decided
**Issue:** [#53](https://github.com/jikig-ai/soleur/issues/53)

## What We're Building

A domain-first directory restructure of the Soleur plugin (`plugins/soleur/`) that reorganizes agents, commands, and skills by business domain, mapped to the 5 core functions of an early-stage startup: **engineering**, **product** (design + brand + research), **growth** (marketing + sales + analytics), **operations** (finance + legal + HR), and **support** (customer success + onboarding + retention). A `shared/` tier holds cross-domain components. This is a MAJOR version bump (2.0.0) reflecting a clean break from the current function-first agent organization and flat skill/command layout.

## Why This Approach

The current structure was built organically for engineering workflows. As Soleur expands to cover all startup functions, the flat skill layout (19 skills in one directory) and function-only agent categorization (review/, research/, design/, workflow/) won't scale. A domain-first structure mapped to startup functions makes it immediately clear which components serve which business function, while the `shared/` tier honestly represents that the core workflow (brainstorm, plan, work, review, ship) is domain-agnostic.

### Domain Model [Updated 2026-02-12]

Domains are modeled after the 5 collapsed functions of an early-stage startup:

| Domain | Covers | Examples |
|--------|--------|----------|
| **shared** | Core workflow, cross-domain tools | brainstorm, plan, work, review, git-worktree |
| **engineering** | Code, CI/CD, testing, architecture, DevOps | code review agents, Rails skills, test runners |
| **product** | Design, branding, user research, specs, prototyping | UX research, brand identity, design systems |
| **growth** | Marketing, sales, content, SEO, analytics | content agents, SEO tools, outreach automation |
| **operations** | Finance, legal, HR, admin, compliance | invoicing, contract review, expense tracking |
| **support** | Customer success, onboarding, retention | support ticket agents, feedback collection |

### Approaches Considered

**Approach 1: Pure Domain-First (Rejected)**
Everything under a domain directory, no shared tier. Rejected because core workflow commands (brainstorm, plan, work) and cross-cutting agents (learnings-researcher, repo-research-analyst) genuinely serve all domains. Forcing them under `engineering/` would be misleading.

**Approach 2: Domain-First with Shared Tier (Selected)**
`shared/` directory for cross-domain components, domain directories for domain-specific ones. Accurately models reality. Additional decision cost ("is this shared or domain-specific?") is worth the accuracy.

**Approach 3: Core at Root (Rejected)**
Keep `soleur/` core at command root, domain dirs only for additions. Rejected for inconsistency -- agents would be domain-first but commands would have a special tier.

## Key Decisions

1. **Single plugin, namespaced by domain** -- No separate plugins per domain. Everything stays in `plugins/soleur/` but organized under domain subdirectories.

2. **Domain-first with shared tier** -- The target structure:
   ```
   agents/
     shared/           # Cross-domain agents
       research/        # learnings-researcher, repo-research-analyst, etc.
       workflow/        # pr-comment-resolver, spec-flow-analyzer
     engineering/       # Code, CI/CD, testing, architecture
       review/          # code-quality-analyst, security-sentinel, etc.
       design/          # ddd-architect
     product/           # Design, branding, user research, prototyping
     growth/            # Marketing, sales, content, SEO, analytics
     operations/        # Finance, legal, HR, admin, compliance
     support/           # Customer success, onboarding, retention

   commands/
     shared/           # Cross-domain commands
       soleur/          # brainstorm, plan, work, review, sync, compound
       *.md             # changelog, triage, lfg, etc.
     engineering/       # Engineering-specific commands
     product/
     growth/
     operations/
     support/

   skills/
     shared/           # Cross-domain skills
       brainstorming/
       git-worktree/
       spec-templates/
       compound-docs/
       file-todos/
       rclone/
     engineering/       # Engineering-specific skills
       dhh-rails-style/
       atdd-developer/
       andrew-kane-gem-writer/
       frontend-design/
       ...
     product/
     growth/
     operations/
     support/
   ```

3. **Full restructure, MAJOR version bump** -- Move all existing engineering components into their proper domain directories in one shot. Version becomes 2.0.0.

4. **Keep function subcategories within domains** -- Agents within a domain retain subcategories (review/, research/, design/, workflow/) for internal organization.

5. **Target domains** -- Mapped to 5 collapsed startup functions: engineering, product (design+brand+research), growth (marketing+sales+analytics), operations (finance+legal+HR), support (CS+onboarding+retention). New domains can be added later by creating a new subdirectory.

## Classification Guide

### Shared Components (cross-domain)
- **Agents:** learnings-researcher, repo-research-analyst, best-practices-researcher, framework-docs-researcher, git-history-analyzer, pr-comment-resolver, spec-flow-analyzer
- **Commands:** brainstorm, plan, work, review, sync, compound, changelog, triage, lfg, ship, help, deepen-plan, plan-review
- **Skills:** brainstorming, git-worktree, spec-templates, compound-docs, file-todos, rclone, agent-browser, skill-creator, create-agent-skills, user-story-writer, gemini-imagegen, every-style-editor

### Engineering Components
- **Agents:** All review/* agents (code-quality-analyst, security-sentinel, performance-oracle, etc.), ddd-architect, architecture-strategist, legacy-code-expert
- **Commands:** resolve_parallel, resolve_pr_parallel, resolve_todo_parallel, test-browser, agent-native-audit, deploy-docs, release-docs, xcode-test, reproduce-bug
- **Skills:** dhh-rails-style, atdd-developer, andrew-kane-gem-writer, frontend-design, dspy-ruby, agent-native-architecture

### Product Components
- Empty initially. Will house design, branding, user research, and prototyping tools.

### Growth Components
- Empty initially. Will house marketing, sales, content, SEO, and analytics tools.

### Operations Components
- Empty initially. Will house finance, legal, HR, admin, and compliance tools.

### Support Components
- Empty initially. Will house customer success, onboarding, and retention tools.

## Open Questions

1. **Agent naming in multi-domain context** -- Should agent names be prefixed with their domain (e.g., `engineering:code-quality-analyst`) or keep current names since the directory already provides context?
2. **README tables** -- The README currently has one flat table per component type. Should it be reorganized by domain, or keep flat tables with a "Domain" column?
3. **Some components are borderline** -- e.g., `every-style-editor` could be marketing or shared. The classification guide above is a starting proposal that should be validated during implementation.

## Success Criteria

- All existing components are reachable at their new paths
- No broken references between commands and agents
- plugin.json updated to 2.0.0
- CHANGELOG and README reflect new structure
- `grep -r` audit confirms no stale path references
- New domain directories can be added by creating subdirectories (no config changes needed)
