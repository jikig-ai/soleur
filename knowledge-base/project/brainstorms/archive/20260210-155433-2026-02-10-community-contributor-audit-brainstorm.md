# Community & Contributor Audit Brainstorm

**Date:** 2026-02-10
**Status:** Ready for planning

## What We're Building

A comprehensive overhaul of all community-facing files and GitHub metadata to make the Soleur repository welcoming to contributors and discoverable by the broader Claude Code community.

## Why This Matters

The plugin has strong technical content (22 agents, 26 commands, 19 skills, active knowledge base, well-maintained CHANGELOG) but the community packaging has significant gaps. The README leads with unrealized vision instead of the shipped product, there are zero community infrastructure files (no CONTRIBUTING.md, issue templates, PR template, or Code of Conduct), the license has contradictions and missing fields, and the GitHub repo has an empty description with no topics.

## Key Decisions

### 1. README Structure: Product-first with collapsible vision

**Decision:** Restructure the README to lead with the Claude Code plugin (what it does, how to install, the workflow). Move the "Company-as-a-Service" vision content into a collapsible `<details>` section at the bottom.

**Rationale:** 45% of the current README discusses aspirational business strategy before showing what the repo actually contains. Contributors need to see the product in the first scroll.

**New README structure:**
1. Title + one-line description + badges (CI, version, license, Discord)
2. What is Soleur? (2-3 sentences about the plugin)
3. Quick Start (install command)
4. The Workflow (brainstorm -> plan -> work -> review -> compound)
5. Component overview (link to full docs)
6. Installation (registry + GitHub methods)
7. Contributing (summary + link to CONTRIBUTING.md)
8. Community (Discord link)
9. Credits
10. `<details>` The Soleur Vision (collapsed, contains current overview content)

**Fix stale counts:** Update "18 agents" and "17 skills" to match plugin README (22 agents, 19 skills).

### 2. License: Switch to Apache 2.0

**Decision:** Replace BSL-1.1 with Apache License 2.0.

**Actions:**
- Replace root `/LICENSE` with Apache 2.0 text
- Replace `/plugins/soleur/LICENSE` with Apache 2.0 text
- Update `plugin.json` license field from "BSL-1.1" to "Apache-2.0"
- Update `plugins/soleur/README.md` line 313 from "MIT" to "Apache-2.0"
- Fix copyright year from "2027" to "2025-present" (or similar)

**Rationale:** Apache 2.0 is permissive like MIT but adds patent protection. More contributor-friendly than BSL-1.1, which is not OSI-approved and actively discourages contributions. Resolves the BSL vs MIT contradiction.

### 3. CONTRIBUTING.md: Expose internal conventions to contributors

**Decision:** Create a comprehensive CONTRIBUTING.md that surfaces the development conventions currently hidden in AGENTS.md.

**Contents:**
- How to run the plugin locally (clone + `claude --plugin-dir`)
- How to file issues (link to templates)
- How to submit PRs (branch naming: `feat-<name>`, commit conventions)
- The versioning triad (plugin.json + CHANGELOG.md + README.md must update together)
- Skill compliance checklist (from AGENTS.md)
- Directory structure overview
- Testing expectations
- Code of Conduct reference

### 4. Code of Conduct: Contributor Covenant

**Decision:** Adopt the Contributor Covenant v2.1 as `CODE_OF_CONDUCT.md`.

**Rationale:** Industry standard, signals welcoming community, pairs with the Discord server.

### 5. GitHub Issue Templates: Bug + Feature + Skill Request

**Decision:** Create YAML-form issue templates:

- **Bug report** (`bug_report.yml`): Plugin version, Claude version, reproduction steps, expected/actual behavior, environment
- **Feature request** (`feature_request.yml`): Problem description, proposed solution, alternatives considered
- **New skill request** (`skill_request.yml`): Skill name, use case, example trigger phrases, references
- **config.yml**: Link to Discord for questions, disable blank issues

### 6. PR Template

**Decision:** Create `.github/PULL_REQUEST_TEMPLATE.md` with:

- Summary section
- Checklist: tests pass, version bumped, CHANGELOG updated, README counts verified
- Type of change (bug fix, new feature, breaking change)
- Related issue link

### 7. GitHub Repo Metadata

**Decision:** Update via `gh` CLI:

- **Description:** "Orchestration engine for Claude Code -- agents, workflows, and compounding knowledge"
- **Topics:** `claude-code`, `claude-code-plugin`, `ai-agents`, `developer-tools`, `orchestration`, `workflow`, `ai-powered`, `engineering`, `knowledge-base`
- **Homepage:** Set to the Discord invite or plugin docs if available

### 8. Badges

**Decision:** Add to README header:

- CI status badge (GitHub Actions)
- Version badge (from plugin.json: v1.11.0)
- License badge (Apache 2.0)
- Discord badge (invite link)

### 9. SECURITY.md

**Decision:** Create a basic security policy with:

- Supported versions
- How to report vulnerabilities (email or GitHub Security Advisories)
- Expected response time

### 10. GitHub Sponsors / FUNDING.yml

**Decision:** Create `.github/FUNDING.yml` with GitHub Sponsors profile.

### 11. CI Improvements (Optional, low priority)

**Observations for future work (not part of this brainstorm):**
- `deploy-docs.yml` points to an empty `plugins/soleur/docs/` directory
- CI runs `bun test` but there appear to be no test files
- Pre-commit hooks (lefthook) enforce Rust linting and markdownlint but CI doesn't replicate these checks
- `.gitignore` references Rust/Cargo artifacts with no Rust code present

These are noted but deferred -- they're about project health, not contributor attraction.

## Deliverables Summary

| File | Action |
|------|--------|
| `README.md` | Restructure: product-first, collapsible vision, fix counts, add badges |
| `CONTRIBUTING.md` | Create: expose conventions from AGENTS.md |
| `CODE_OF_CONDUCT.md` | Create: Contributor Covenant v2.1 |
| `LICENSE` | Replace: Apache 2.0 |
| `plugins/soleur/LICENSE` | Replace: Apache 2.0 |
| `SECURITY.md` | Create: vulnerability reporting process |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Create: structured bug report form |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Create: structured feature request form |
| `.github/ISSUE_TEMPLATE/skill_request.yml` | Create: new skill request form |
| `.github/ISSUE_TEMPLATE/config.yml` | Create: template chooser config |
| `.github/PULL_REQUEST_TEMPLATE.md` | Create: PR checklist |
| `.github/FUNDING.yml` | Create: GitHub Sponsors |
| `plugins/soleur/.claude-plugin/plugin.json` | Update: license field to Apache-2.0, keywords |
| `plugins/soleur/README.md` | Update: license line from MIT to Apache-2.0 |
| GitHub repo settings | Update: description, topics, homepage |

## Open Questions

- **GitHub Sponsors username:** Need the exact GitHub username or org for FUNDING.yml (likely `deruelle` or `jikig-ai`)
- **Security contact email:** What email should vulnerability reports go to?
- **Homepage URL:** Should repo homepage point to Discord, a docs site, or nothing for now?

## What This Brainstorm Does NOT Cover

- Building out the docs site (the empty `plugins/soleur/docs/` directory)
- Adding tests or fixing CI to run meaningful checks
- Cleaning up Rust-related artifacts from `.gitignore` and lefthook
- Creating "good first issue" labeled issues to attract contributors
- Writing a contributor onboarding guide or tutorial
