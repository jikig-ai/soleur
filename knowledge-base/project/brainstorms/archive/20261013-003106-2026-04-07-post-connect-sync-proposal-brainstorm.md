# Post-Connect Sync Proposal & Project Status Report

**Date:** 2026-04-07
**Status:** Decided
**Branch:** feat-post-connect-sync-proposal
**PR:** #1771

## What We're Building

After a user connects a project in the web platform UI (connect-repo flow), the system should:

1. **Fast scan** the cloned repo during provisioning to produce a project health snapshot
2. **Auto-trigger** a headless agent sync to populate the Knowledge Base
3. **Display** the health snapshot on a revamped Ready state and a persistent KB overview page
4. **Notify** the user in the Command Center when the deep agent analysis completes

Currently, after repo clone, the "Setting Up" animation shows fake progress steps ("Scanning project structure", "Analyzing conventions") that are purely cosmetic. The user lands on an empty KB with "Nothing Here Yet." This feature makes those steps real and gives users immediate value.

## Why This Approach

The hybrid approach (fast scan + async agent sync) balances speed with depth:

- **Fast scan** (server-side, ~2-5s): Deterministic file-presence checks. No AI tokens. Produces an immediate health snapshot the user can see in the Ready state.
- **Deep agent sync** (async, headless): Runs `/soleur:sync` non-interactively with auto-accept for high-confidence findings. Populates constitution, architecture docs, component docs. Appears in Command Center as an "Executing" conversation with Realtime status updates.
- **KB overview page** (`/dashboard/kb/overview`): Persistent home for the health snapshot + recommendations. Updated when deep analysis completes. Replaces "Nothing Here Yet" as the KB landing experience.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Trigger timing | During provisioning pipeline | "Setting Up" steps become real operations. No separate triggers to manage. |
| Fast scan location | Server-side in `server/workspace.ts` | Part of `provisionWorkspaceWithRepo`. No API roundtrip needed. |
| Health snapshot storage | JSON column on user record | Small payload (~1KB). Avoids separate table. Can be refreshed by re-scanning. |
| Deep sync mode | Auto-accept headless | No user interaction required. User reviews results in KB viewer afterward. |
| Deep sync trigger | Auto-triggered after provisioning | Zero friction. User sees it running in Command Center. |
| Status report display | Ready state (revamped) + KB overview page | Ready state gives immediate feedback. KB overview persists for revisits. |
| Notification channel | Command Center (Supabase Realtime) | Conversation status updates from "Executing" to "Completed". Already built. |

## Fast Scan: What to Detect

The server-side scanner checks file patterns to build a `ProjectHealthSnapshot`:

### Project Structure

- **Package manager**: `package.json`, `Gemfile`, `requirements.txt`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `pom.xml`
- **Language/framework**: Inferred from package files and file extensions
- **Monorepo signals**: `packages/`, `apps/`, `workspaces` in package.json, `lerna.json`, `turbo.json`, `nx.json`

### Quality Signals

- **Tests**: `**/*.test.*`, `**/*.spec.*`, `test/`, `tests/`, `__tests__/`, `spec/`
- **CI/CD**: `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/`
- **Linting**: `.eslintrc*`, `.prettierrc*`, `biome.json`, `.rubocop.yml`, `.golangci.yml`
- **Type safety**: `tsconfig.json`, type annotation patterns
- **Docker**: `Dockerfile`, `docker-compose.yml`, `compose.yml`

### Documentation

- **README**: `README.md`, `README.rst`
- **Docs directory**: `docs/`, `documentation/`
- **API docs**: `openapi.yaml`, `swagger.json`
- **CLAUDE.md**: Project instructions for Claude Code

### KB State

- **Knowledge base directory**: `knowledge-base/` presence
- **Constitution**: `knowledge-base/project/constitution.md`
- **Components**: `knowledge-base/project/components/`
- **Learnings**: `knowledge-base/project/learnings/`

## Status Report: Recommendations Engine

Based on detected vs. missing signals, generate actionable recommendations:

| Signal Missing | Recommendation |
|----------------|----------------|
| No tests found | "Add tests to improve code confidence. Your project uses [framework] -- consider [test framework]." |
| No CI config | "Set up CI/CD to automate testing. GitHub Actions workflows can run on every push." |
| No linting config | "Add a linter to enforce consistent code style across your team." |
| No README | "Create a README.md to document your project's purpose and setup." |
| No CLAUDE.md | "Add a CLAUDE.md to give AI assistants context about your project conventions." |
| No KB | "The Knowledge Base will be populated by the deep analysis running now." |
| KB exists but incomplete | "Your Knowledge Base has [X/Y] sections populated. Deep analysis will fill in the gaps." |

## UX Flow

### Connect Repo: Setting Up State

The existing animated steps map to real operations:

1. "Copying project files" -> Git clone (existing)
2. "Scanning project structure" -> Fast scan (NEW)
3. "Detecting knowledge base" -> KB detection within fast scan (NEW)
4. "Analyzing conventions and patterns" -> Agent sync triggered (NEW)
5. "Preparing AI team" -> Health snapshot stored (NEW)

### Connect Repo: Ready State (Revamped)

Replace the bare success screen with a project health card:

- **Project name and repo link**
- **Health snapshot summary**: Detected signals (green checkmarks), missing signals (amber suggestions)
- **Top 3 recommendations**: Most impactful actionable items
- **Deep analysis status**: "Running..." with link to Command Center, or "Complete" with link to KB
- **CTA**: "Go to Dashboard" / "View Knowledge Base"

### KB Overview Page (`/dashboard/kb/overview`)

New persistent page at the root of the KB section:

- **Project health score**: Visual summary (not a numeric score -- categorized as "Well-documented", "Getting started", "Needs attention")
- **Signal inventory**: Expandable sections showing what was detected
- **Recommendations**: Full list with priority ordering
- **KB completeness**: Which KB sections are populated vs. empty
- **Last analyzed**: Timestamp + "Re-analyze" button
- **Deep analysis status**: If running, show progress

## Open Questions

- What is the token budget for auto-triggered agent sync? Should there be a limit per project?
- Should the health snapshot auto-refresh periodically (e.g., on git push via webhook)?
- Should the KB overview page be the default KB landing or accessed via a tab/nav item?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** This belongs in Phase 3 (Make it Sticky). T3 ("Make the Moat Visible") requires founders to see KB value -- a post-connect sync that immediately populates KB artifacts is the fastest path. Risk to P4 validation is high if absent: the 2026-03-03 onboarding audit rated "no post-install guidance" as P0. If beta founders connect repos and get silence, the 2-week unassisted usage metric (P4 item 4.4) will fail. Roadmap needs a Phase 3 line item (e.g., 3.16).

### Marketing

**Summary:** This is the single highest-leverage marketing moment -- it turns the abstract promise ("AI that already knows your business") into a concrete first-session experience. Product strategy TR5 already prescribes this exact sequence (install -> sync -> one domain task -> result). The status report output is inherently shareable for build-in-public content. Copy quality for the sync proposal and status report is critical -- these are the first branded words a new user reads after connecting. Risk: sync output quality varies by project size; must be useful even for small/simple repos.

### Support

**Summary:** Eliminates the "blank slate" problem -- the single largest source of "I installed it, now what?" confusion. Needs support runbooks before shipping: sync failure triage guide, onboarding friction playbook, and sync FAQ. Scope boundary between `/soleur:sync` and `/soleur:bootstrap` must be clarified to avoid "which one do I use?" questions. Resume community digest generation (stale since Mar 24) to detect onboarding confusion signals.
