---
title: "content: repo connection feature launch content brief"
type: feat
date: 2026-03-29
issue: "#1273"
pr_reference: "#1257"
---

# Content: Repo Connection Feature Launch

## Overview

Create three content pieces for the GitHub repo connection feature shipped in PR #1257: a product update blog post, a technical deep-dive blog post, and social distribution content across all active channels. This is the content remediation identified by the CMO pre-ship content gate -- the feature is live, content needs to follow within one week.

## Problem Statement / Motivation

PR #1257 shipped the single most important feature on the Soleur roadmap (per CMO assessment in brainstorm #1060): connecting a founder's actual GitHub repository to their AI organization. This transforms Soleur from "AI chat against an empty workspace" to "AI team that operates on your real codebase." The feature is live but has zero content amplification -- no announcement, no technical narrative, no social distribution.

The content strategy identifies two relevant gaps:

- **Gap 4 (Engineering-in-Context Value Proposition)**: The repo connection feature IS the engineering-in-context value proposition made real. Content should connect to this gap.
- **Gap 1 (Cross-Domain Compounding Narrative)**: Repo connection enables compounding -- agents now read the actual knowledge-base, brand guide, specs, and learnings from the founder's repo. Content should reinforce this narrative.

## Proposed Solution

Three content pieces, each using existing skills:

### Content Piece 1: Product Update Post

- **Title**: "Your AI Team Now Works From Your Actual Codebase"
- **Audience**: General register (non-technical founders) + technical register (developers)
- **Pillar**: Product Updates / Feature Launches
- **Skill**: `soleur:content-writer`
- **Output path**: `plugins/soleur/docs/blog/2026-03-29-your-ai-team-works-from-your-actual-codebase.md`
- **Key angles**:
  - The "aha moment" -- connecting your repo means every agent conversation starts with real context
  - Onboarding flow designed for founders who may not be technical
  - Auto-create repo option for pre-code founders
  - Best-effort sync: agents pull latest on session start, push changes on session end
  - Brand voice: general register for the narrative, technical register for implementation details
- **Data points to include**:
  - GitHub App with installation token caching (not OAuth, not PAT)
  - Shallow clone + best-effort sync (never blocks sessions)
  - Skip path available (repo connection is optional)
  - Knowledge-base scaffolding for new repos
- **Outline** (pass as `--outline` to content-writer):
  - The problem: AI agents operating against empty workspaces lose the context that makes them useful
  - What changed: connect your GitHub repo during onboarding, agents operate on your actual codebase
  - How it works: install the Soleur GitHub App, select or create a repo, workspace is provisioned with your code
  - The compounding effect: agents read your knowledge-base, brand guide, specs, and learnings -- context carries forward
  - For founders without a repo: auto-create option scaffolds a knowledge-base from day one
  - What happens behind the scenes: best-effort sync (pull on session start, push on session end), never blocks your work
  - Internal links: reference "Why Most Agentic Engineering Tools Plateau" for compound knowledge context
- **Keywords**: "AI team codebase", "GitHub AI agent", "AI development workflow", "agentic engineering codebase"

### Content Piece 2: Technical Blog Post

- **Title**: "Credential Helper Isolation: Secure Git Auth in Sandboxed Environments"
- **Audience**: Technical register (developers, security engineers)
- **Pillar**: Technical Deep Dives
- **Skill**: `soleur:content-writer`
- **Output path**: `plugins/soleur/docs/blog/2026-03-29-credential-helper-isolation-sandboxed-environments.md`
- **Key angles**:
  - The engineering problem: how do you give a sandboxed AI agent git push/pull access without exposing long-lived credentials?
  - The credential helper pattern: write a temp shell script to `/tmp` with a randomized UUID filename, point `GIT_ASKPASS` at it, clean up in `finally`
  - Why GitHub App installation tokens (not PAT, not deploy keys): 1hr auto-expiry, per-repo scoping, no long-lived secrets
  - Security hardening: randomized paths prevent symlink attacks, UUID validation on userId prevents path traversal
  - Best-effort sync philosophy: failed sync is recoverable, blocked session is not
  - Code examples from `workspace.ts`, `github-app.ts`, `session-sync.ts`
- **Data points to include**:
  - RS256 JWT signing with Node `crypto` (no external JWT library)
  - Installation token caching with 5-minute safety margin before expiry
  - `randomCredentialPath()` using `crypto.randomUUID()`
  - Shallow clone (`--depth 1`) trade-offs
  - Rebase conflict handling: `git rebase --abort` and continue
- **Outline** (pass as `--outline` to content-writer):
  - The engineering problem: sandboxed AI agents need git push/pull but must not hold long-lived credentials
  - Why not PAT or deploy keys: blast radius, expiry, scope comparison
  - The credential helper pattern: write a temp shell script, point GIT_ASKPASS, clean up in finally
  - Security hardening: randomized UUID paths prevent symlink attacks, userId validation prevents path traversal
  - GitHub App JWT flow: RS256 signing with Node crypto, installation token caching with 5-minute safety margin
  - Best-effort sync philosophy: failed sync is recoverable, blocked session is not
  - Code walkthrough: workspace.ts, github-app.ts, session-sync.ts with annotated excerpts
  - Internal links: reference the product update post for the user-facing narrative
- **Keywords**: "git credential helper", "sandboxed git auth", "GitHub App authentication", "credential isolation pattern"
- **Publish timing**: Schedule 5-7 days after the product update post (staggered for maximum impact)

### Content Piece 3: Social Distribution

- **Skill**: `soleur:social-distribute` (run on the product update post)
- **Output path**: `knowledge-base/marketing/distribution-content/2026-03-29-repo-connection-launch.md`
- **Primary channels** (prioritize review): Discord, X/Twitter, LinkedIn Personal, LinkedIn Company
- **Secondary channels** (generated but lower priority): Bluesky, IndieHackers, Reddit, Hacker News
- **Key message**: Your AI team now operates on your actual codebase -- not a blank workspace. Connect your GitHub repo during onboarding, and every agent conversation starts with real context.
- **Tone**: Confident, concrete (product announcement register from brand guide)

## Implementation Phases

### Phase 1: Product Update Blog Post

- [x] Run `soleur:content-writer` with the product update topic, outline, and keywords
- [x] Verify brand voice compliance (general + technical registers)
- [x] Verify Eleventy frontmatter and JSON-LD structured data
- [x] Verify all claims are factually grounded in the PR #1257 implementation

Files:

- `plugins/soleur/docs/blog/2026-03-29-your-ai-team-works-from-your-actual-codebase.md`

### Phase 2: Technical Blog Post

- [x] Run `soleur:content-writer` with the credential helper topic, outline, and keywords
- [x] Verify code examples match actual implementation in `workspace.ts`, `github-app.ts`, `session-sync.ts`
- [x] Verify technical register voice
- [x] Verify security claims are accurate (randomized paths, UUID validation, token expiry)

Files:

- `plugins/soleur/docs/blog/2026-03-29-credential-helper-isolation-sandboxed-environments.md`

### Phase 3: Social Distribution and Content Strategy Updates

- [x] Run `soleur:social-distribute` on the product update blog post
- [x] Verify platform-specific formatting (character limits, thread structure)
- [x] Verify brand voice consistency across primary channel variants (Discord, X, LinkedIn)
- [x] Verify links point to the correct blog post URL
- [x] Update `knowledge-base/marketing/content-strategy.md` Gap 4 to reference the new content
- [x] Update `knowledge-base/marketing/campaign-calendar.md` with the new content entries

Files:

- `knowledge-base/marketing/distribution-content/2026-03-29-repo-connection-launch.md`
- `knowledge-base/marketing/content-strategy.md`
- `knowledge-base/marketing/campaign-calendar.md`

## Acceptance Criteria

- [x] Product update blog post exists at the specified path with valid Eleventy frontmatter
- [x] Technical blog post exists at the specified path with valid Eleventy frontmatter
- [x] Social distribution content file exists with variants for all specified channels
- [x] All content uses the correct brand voice register (general for product update narrative, technical for deep-dive)
- [x] All factual claims are traceable to PR #1257 implementation code
- [x] Content strategy document updated to reflect the new content
- [x] Campaign calendar updated with publish dates

## Test Scenarios

- Given the product update blog post, when built with Eleventy, then it renders without errors and includes JSON-LD structured data
- Given the technical blog post, when code examples are compared to source files, then every code snippet matches the actual implementation
- Given the social distribution file, when parsed by `content-publisher.sh`, then each channel variant has the correct YAML frontmatter and respects platform character limits
- Given the content strategy document, when Gap 4 is reviewed, then it references the new content with a completion annotation

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed (self-referential -- this IS the marketing task)
**Assessment:** The content pieces directly address CMO pre-ship gate recommendations from PR #1257. The product update post targets Gap 4 (Engineering-in-Context Value Proposition) in the content strategy. The technical blog adds to the Technical Deep Dives pillar. Social distribution follows the established pattern from previous launches (PWA milestone, legal document generation). No new marketing concerns -- execution of an already-assessed content opportunity.

## References

- Issue: [#1273](https://github.com/jikig-ai/soleur/issues/1273)
- Shipped PR: [#1257](https://github.com/jikig-ai/soleur/pull/1257)
- Brainstorm: `knowledge-base/project/brainstorms/archive/20260329-173125-2026-03-28-repo-connection-brainstorm.md`
- Onboarding copy: `knowledge-base/marketing/copy/connect-repo-onboarding.md`
- Implementation learning: `knowledge-base/project/learnings/2026-03-29-repo-connection-implementation.md`
- Content strategy: `knowledge-base/marketing/content-strategy.md` (Gaps 1 and 4)
- Brand guide: `knowledge-base/marketing/brand-guide.md`
- Technical files:
  - `apps/web-platform/server/workspace.ts` -- credential helper pattern
  - `apps/web-platform/server/github-app.ts` -- JWT signing, token caching
  - `apps/web-platform/server/session-sync.ts` -- best-effort sync
  - `apps/web-platform/app/(auth)/connect-repo/page.tsx` -- 9-state onboarding flow
