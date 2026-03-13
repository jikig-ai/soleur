---
title: Community & Contributor Audit
type: feat
date: 2026-02-10
updated: 2026-02-10
---

# Community & Contributor Audit

[Updated 2026-02-10] Revised after parallel review by DHH, simplicity, and quality reviewers. Scope reduced: cut SECURITY.md, FUNDING.yml, skill_request.yml. Simplified PR template. Reduced topics from 9 to 5. Added version bump phase, component count verification, and license compatibility check.

## Overview

Overhaul community-facing files and GitHub metadata to make the Soleur repository welcoming to contributors and discoverable by the Claude Code community. The plugin has strong technical content (22 agents, 26 commands, 19 skills) but the packaging has gaps: README leads with vision instead of product, zero community infrastructure files exist, license has contradictions, and GitHub repo metadata is empty.

## Problem Statement / Motivation

A potential contributor landing on the repo today sees 40+ lines of "Company-as-a-Service" philosophy before learning what the repo actually contains. There is no CONTRIBUTING.md, no issue templates, no PR template, and no Code of Conduct. The LICENSE file (BSL-1.1) has blank required fields and contradicts the plugin README (which says MIT). The GitHub repo has an empty description and zero topics. These gaps actively discourage contributions.

## Proposed Solution

Ship community infrastructure in one pass, organized into 5 phases. Phase 0 (pre-checks) and Phase 1 (license) run first. Phases 2-4 can run in parallel.

## Non-Goals

- Building the docs site (empty `plugins/soleur/docs/` directory)
- Adding automated tests or fixing CI to run meaningful checks
- Cleaning up Rust-related artifacts from `.gitignore` and lefthook
- Creating "good first issue" labeled issues
- Writing a contributor onboarding tutorial
- Social preview image / Open Graph branding
- DCO/CLA sign-off requirements
- SECURITY.md (add when project has meaningful security surface area)
- FUNDING.yml / GitHub Sponsors (add after external contributors are active)
- Dedicated skill request template (feature requests cover this)

## Acceptance Criteria

- [x] Credited projects' licenses verified compatible with Apache 2.0 (all MIT)
- [x] Component counts verified programmatically (22 agents, 26 commands, 19 skills)
- [x] LICENSE is Apache 2.0 in both root and `plugins/soleur/`
- [x] `plugin.json` license field says `Apache-2.0`, keywords expanded
- [x] `plugins/soleur/README.md` license line says Apache-2.0
- [x] Version bumped in plugin.json (1.12.0), CHANGELOG.md updated, plugin README counts verified
- [x] README leads with the Claude Code plugin, vision is in a collapsible section
- [x] Badges visible: version (1.12.0), license (Apache 2.0), Discord
- [x] Component counts in root README match verified counts (22/26/19)
- [x] CONTRIBUTING.md exists with development setup, PR process, versioning triad
- [x] CODE_OF_CONDUCT.md exists (Contributor Covenant v2.1)
- [x] Issue templates: bug_report.yml, feature_request.yml, config.yml
- [x] PR template exists with single testing checklist item
- [ ] GitHub repo description set (run after merge)
- [ ] GitHub repo topics set (run after merge)

## Implementation Phases

### Phase 0: Pre-Checks

Run before anything else. These are blocking.

**0a. License Compatibility Audit**

Check the licenses of all credited projects to verify Apache 2.0 compatibility:

```bash
# Check each credited project's license
gh api repos/EveryInc/compound-engineering-plugin --jq .license.spdx_id
gh api repos/Fission-AI/OpenSpec --jq .license.spdx_id
gh api repos/github/spec-kit --jq .license.spdx_id
```

If all are MIT or Apache-2.0, proceed. If any are GPL or AGPL, a NOTICE file is required -- stop and reassess.

**0b. Component Count Verification**

Verify the actual component counts before hardcoding them:

```bash
# Count agents (subdirectories under category dirs)
find plugins/soleur/agents -mindepth 2 -maxdepth 2 -type d | wc -l

# Count commands (markdown files)
find plugins/soleur/commands -name '*.md' | wc -l

# Count skills (directories with SKILL.md)
find plugins/soleur/skills -name 'SKILL.md' | wc -l
```

Expected: 22 agents, 26 commands, 19 skills. If counts differ, use the verified counts throughout.

**0c. Discord Link Verification**

Verify the Discord invite link is permanent and resolves:

```bash
curl -sI https://discord.gg/PYZbPBKMUY | head -5
```

### Phase 1: License Switch (Apache 2.0)

Do this first since it affects badges and other files.

**Files to create/modify:**

1. **`LICENSE`** (root) -- Replace BSL-1.1 with standard Apache License 2.0 text
   - Copyright line: `Copyright 2025 Jikigai`
   - Use the standard text from https://www.apache.org/licenses/LICENSE-2.0.txt

2. **`plugins/soleur/LICENSE`** -- Same Apache 2.0 text

3. **`plugins/soleur/.claude-plugin/plugin.json`** -- Update:
   - `"license": "Apache-2.0"` (was `"BSL-1.1"`)
   - Expand `"keywords"` to: `["soleur", "claude-code", "ai-agents", "developer-tools", "orchestration"]`

4. **`plugins/soleur/README.md`** line 313 -- Change `MIT` to `Apache-2.0`

### Phase 2: README Restructure

**File:** `README.md` (root)

New structure (content, not line references):

```markdown
# soleur

Orchestration engine for Claude Code -- agents, workflows, and compounding knowledge.

[![Version](https://img.shields.io/badge/version-{VERIFIED_VERSION}-blue)](https://github.com/jikig-ai/soleur/releases)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Discord](https://img.shields.io/badge/Discord-community-5865F2?logo=discord&logoColor=white)](https://discord.gg/PYZbPBKMUY)

## What is Soleur?

AI-powered development tools for Claude Code that get smarter with every use.
Soleur provides **{AGENT_COUNT} agents**, **{COMMAND_COUNT} commands**, and
**{SKILL_COUNT} skills** that compound your engineering knowledge over time --
every problem you solve makes the next one easier.

## Installation

**From the registry (recommended):**

    claude plugin install soleur

**From GitHub:**

    claude plugin install --url https://github.com/jikig-ai/soleur/tree/main/plugins/soleur

**For existing codebases:** Run `/soleur:sync` first to populate your
knowledge-base with conventions and patterns.

## The Workflow

    /soleur:brainstorm --> /soleur:plan --> /soleur:work --> /soleur:review --> /soleur:compound

| Command | Purpose |
| ------- | ------- |
| `/soleur:sync` | Analyze codebase and populate knowledge-base |
| `/soleur:brainstorm` | Explore ideas and make design decisions |
| `/soleur:plan` | Create structured implementation plans |
| `/soleur:work` | Execute plans with incremental commits |
| `/soleur:review` | Run comprehensive code review with specialized agents |
| `/soleur:compound` | Capture learnings for future work |

See **[full component reference](./plugins/soleur/README.md)** for all agents,
commands, and skills.

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get
started, file issues, and submit pull requests.

## Community

Join the conversation on [Discord](https://discord.gg/PYZbPBKMUY).

## Credits

This work builds on ideas and patterns from these excellent projects:

- [Compound Engineering Plugin](https://github.com/EveryInc/compound-engineering-plugin)
- [OpenSpec](https://github.com/Fission-AI/OpenSpec)
- [Spec-Kit](https://github.com/github/spec-kit)

## License

Apache-2.0. See [LICENSE](LICENSE) for details.

---

<details>
<summary>The Soleur Vision</summary>

{MOVE CURRENT README LINES 14-56 HERE VERBATIM}

</details>
```

**Key changes:**
- 3 badges (version, license, Discord) -- no CI badge since CI has no meaningful checks
- "What is Soleur?" replaces 40+ lines of vision -- 3 sentences
- Quick Start merged into Installation (single section, not two)
- Component counts use verified values from Phase 0b
- Vision content in collapsible `<details>` at bottom
- Table of Contents removed (README is short enough)
- Credits section stays visible (not collapsed)

### Phase 3: Community Infrastructure Files

**3a. `CONTRIBUTING.md`** (root)

Keep it short -- 3 main sections:

1. **Getting Started**
   - Clone repo, run `claude --plugin-dir ./plugins/soleur`
   - Test changes immediately without installation

2. **Submitting Changes**
   - Check existing issues first
   - Branch from `main`, use descriptive branch names
   - Write clear commit messages (`feat:`, `fix:`, `docs:` prefixes)
   - Open a PR referencing any related issues
   - For plugin changes: update version in `plugin.json`, add CHANGELOG entry, verify README counts match -- see [plugin development guide](plugins/soleur/AGENTS.md) for details

3. **Code of Conduct**
   - Link to CODE_OF_CONDUCT.md

**3b. `CODE_OF_CONDUCT.md`** (root)

- Contributor Covenant v2.1 verbatim text
- Enforcement contact: `jean.deruelle@jikigai.com`
- Scope: GitHub repository, Discord server, and community events

### Phase 4: GitHub Templates & Metadata

**4a. `.github/ISSUE_TEMPLATE/bug_report.yml`**

YAML form fields:
- **Description** (textarea, required) -- What happened?
- **Steps to reproduce** (textarea, required)
- **Expected behavior** (textarea, required)
- **Environment** (dropdowns/inputs):
  - Plugin version (e.g., 1.11.0)
  - Claude Code version
  - OS (Linux, macOS, Windows)
- **Command/skill/agent** (input, optional) -- Which component?
- **Logs** (textarea, optional) -- Error messages or console output

**4b. `.github/ISSUE_TEMPLATE/feature_request.yml`**

YAML form fields:
- **Problem** (textarea, required) -- What problem does this solve?
- **Proposed solution** (textarea, required)
- **Alternatives considered** (textarea, optional)
- **Additional context** (textarea, optional) -- Links, examples, component type (skill/agent/command)

**4c. `.github/ISSUE_TEMPLATE/config.yml`**

```yaml
blank_issues_enabled: true
contact_links:
  - name: Discord Community
    url: https://discord.gg/PYZbPBKMUY
    about: Ask questions, share ideas, and get help from the community
```

Blank issues enabled -- contributors may have questions or ideas that don't fit templates.

**4d. `.github/PULL_REQUEST_TEMPLATE.md`**

```markdown
## Summary

<!-- What does this PR do? -->

Closes #

## Type of Change

- [ ] Bug fix
- [ ] New feature (agent, command, or skill)
- [ ] Documentation update
- [ ] Breaking change

## Testing

- [ ] I have tested these changes locally
```

Simple. Versioning triad is documented in CONTRIBUTING.md and enforced during review, not via checkbox theater.

**4e. GitHub Repo Settings** (via `gh` CLI, run after merge)

```bash
gh repo edit jikig-ai/soleur \
  --description "Orchestration engine for Claude Code -- agents, workflows, and compounding knowledge" \
  --add-topic claude-code \
  --add-topic ai-agents \
  --add-topic developer-tools \
  --add-topic orchestration \
  --add-topic knowledge-base
```

5 topics. Focused, no redundancy.

### Phase 5: Version Bump

After all files are ready, bump the plugin version (this is a MINOR bump -- new community infrastructure).

1. Bump version in `plugins/soleur/.claude-plugin/plugin.json` (e.g., 1.11.0 -> 1.12.0)
2. Add CHANGELOG.md entry documenting all community infrastructure changes
3. Verify README component counts match Phase 0b results
4. Update version badge in root README to match new version

## Dependencies & Risks

**Dependencies:**
- Phase 0 (pre-checks) must complete before Phase 1
- Phase 1 (license) must complete before Phase 2 (README badges need correct license)
- Phase 5 (version bump) runs last
- Phases 2, 3, 4 are independent of each other

**Risks:**
- License change is legally significant -- mitigated by Phase 0a compatibility audit
- Changing repo description/topics is immediately visible to watchers -- run after merge
- If component counts differ from expected 22/26/19, all files referencing counts need updating

## Rollback Plan

All changes are file additions/modifications in a single branch. Revert the merge commit to roll back everything. GitHub repo metadata (description, topics) can be reverted via `gh repo edit`.

## Deliverables Summary

| File | Action |
|------|--------|
| `LICENSE` | Replace: Apache 2.0 |
| `plugins/soleur/LICENSE` | Replace: Apache 2.0 |
| `plugins/soleur/.claude-plugin/plugin.json` | Update: license, keywords, version |
| `plugins/soleur/README.md` | Update: license line to Apache-2.0 |
| `plugins/soleur/CHANGELOG.md` | Update: add entry for community infrastructure |
| `README.md` | Restructure: product-first, badges, collapsible vision |
| `CONTRIBUTING.md` | Create: 3-section contributor guide |
| `CODE_OF_CONDUCT.md` | Create: Contributor Covenant v2.1 |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Create: structured bug report form |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Create: structured feature request form |
| `.github/ISSUE_TEMPLATE/config.yml` | Create: template chooser config |
| `.github/PULL_REQUEST_TEMPLATE.md` | Create: simple PR template |
| GitHub repo settings | Update: description + 5 topics (after merge) |

**Total: 12 files + repo settings** (down from 15 files + repo settings)

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-10-community-contributor-audit-brainstorm.md`
- Current plugin docs: `plugins/soleur/README.md`
- Plugin dev guide: `plugins/soleur/AGENTS.md`
- Contributor Covenant v2.1: https://www.contributor-covenant.org/version/2/1/code_of_conduct/
- Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0.txt
- GitHub community standards: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions
