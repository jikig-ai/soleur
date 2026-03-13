---
title: "feat: External agent discovery via registry integration"
type: feat
date: 2026-02-12
updated: 2026-02-18
---

# External Agent Discovery via Registry Integration

## Overview

Add gap-triggered community agent/skill discovery to the `/plan` command. When `/plan` detects that the current project uses a stack not covered by built-in agents, it queries external registries for matching community artifacts, presents suggestions from trusted sources, and installs approved ones.

[Updated 2026-02-18] Research spike complete. Viable unauthenticated APIs found. This plan replaces the research-spike scope with an implementation plan. Plan reviewed by DHH, Simplicity, and Architecture reviewers -- targeted fixes applied.

## Problem Statement

The Soleur plugin ships with agents covering Rails, security, architecture, and other domains. Projects using uncovered stacks (Flutter, Rust, Elixir, etc.) get no stack-specific assistance. Users have no way to discover that community-maintained agents exist for their stack.

## Plan Review Outcomes

### Round 1 [2026-02-12]

Three reviewers unanimously challenged the original multi-phase plan. Decision: research spike only.

### Round 2 [2026-02-18]

Three reviewers challenged the implementation plan:
- **DHH:** Cut to signpost only (log message, no registry queries). 80% scope cut.
- **Simplicity:** Keep agent approach but cut to 1 registry, agents-only, binary trust. 40% cut.
- **Architecture:** Agent approach is sound. Move from Phase 0.1 to Phase 1.5. Fix gap detection, test frontmatter loader, use curl instead of WebFetch for JSON.

**Decision:** Keep current scope. Apply targeted fixes from Architecture reviewer. User chose to proceed with full plan over signpost-only or minimal approaches.

**Fixes applied:**
1. Moved discovery from Phase 0.1 to Phase 1.5 (after idea refinement and local research)
2. Added Phase 0 loader test for extra frontmatter fields
3. Added `stack` frontmatter field for reliable gap re-detection
4. Added prompt injection to risk table
5. Specified gap check algorithm (frontmatter `stack` field, not filename heuristic)
6. Documented agent/skill directory asymmetry as intentional
7. Use Bash `curl` for JSON API queries instead of WebFetch

## Proposed Solution

Insert a discovery step at Phase 1.5 in the `/plan` command, after idea refinement and local research:

```
/plan "add push notifications"
  Phase 0:   Load context (existing)
  Phase 0.5: Idea refinement (existing)
  Phase 1:   Local research (existing)
  Phase 1.5: Discovery check (NEW)
    -> Detect: Flutter project (pubspec.yaml + *.dart)
    -> Check: No agents with stack: flutter in frontmatter
    -> Query: registries via curl (JSON APIs)
    -> Filter: Anthropic + verified publishers only
    -> Present: "Found 2 Flutter agents. Install? [approve/skip/skip all]"
    -> Install approved -> agents/community/flutter-review.md
  Phase 1.5b: External research (existing, continues normally)
```

**Why Phase 1.5 and not Phase 0.1:** At Phase 0.1, the feature description hasn't been refined yet. In a Rails + Flutter monorepo, you don't know which stack the feature touches until after idea refinement. At Phase 1.5, the idea is clear and local research has identified the relevant stack.

**Trade-off acknowledged:** Agents installed at Phase 1.5 do not participate in the current `/plan` run. They benefit subsequent commands (`/review`, `/work`, future `/plan` runs). This is acceptable -- the plan's primary value is the plan document, not the agents assisting in planning.

## Technical Approach

### Stack Detection

File-signature heuristics, same pattern as `/review` conditional agents:

| Files Present | Detected Stack |
|---------------|---------------|
| `pubspec.yaml` + `*.dart` | Flutter/Dart |
| `Cargo.toml` + `*.rs` | Rust |
| `mix.exs` + `*.ex` | Elixir |
| `go.mod` + `*.go` | Go |
| `Package.swift` + `*.swift` | Swift/iOS |
| `build.gradle` + `*.kt` | Kotlin/Android |
| `composer.json` + `*.php` | PHP/Laravel |

Stacks already covered by built-in agents (Rails, TypeScript, general security/architecture) are excluded from gap detection.

### Gap Check Algorithm

The gap check uses the `stack` frontmatter field, not filename heuristics:

1. Detect project stack from file signatures (table above)
2. For each detected stack, search all agent files: `grep -rl "stack: <stack>" agents/`
3. If any agent file has a matching `stack:` field, the stack is covered -- skip discovery
4. If no match, the stack is a gap -- trigger discovery

This means:
- Built-in agents that cover specific stacks should have `stack: rails`, `stack: typescript` etc. in their frontmatter (a prerequisite task)
- Community agents installed by discovery include `stack: flutter` in their frontmatter
- Re-running `/plan` after installing a Flutter agent correctly detects coverage

### Registry Integration

Three unauthenticated registries, queried in parallel via Bash `curl` (JSON APIs, not HTML):

| Registry | Endpoint | Scale | Timeout |
|----------|----------|-------|---------|
| api.claude-plugins.dev | `curl -s "https://api.claude-plugins.dev/api/skills/search?q={stack}&limit=10"` | 3,915 skills | 5s |
| claudepluginhub.com | `curl -s "https://www.claudepluginhub.com/api/plugins?q={stack}"` | 12,171 plugins | 5s |
| Anthropic repos | `curl -s "https://raw.githubusercontent.com/anthropics/.../marketplace.json"` | ~70 artifacts | 5s |

**Why curl instead of WebFetch:** WebFetch converts HTML to markdown and processes through an AI model. These are JSON APIs returning structured data. `curl` via Bash returns raw JSON that the agent can parse directly. This is the same pattern used by `infra-security` for Cloudflare API calls.

Partial failures: surface results from registries that responded. All fail: skip discovery silently. 401/403 responses treated as permanent failures (registry added auth), not transient.

### Trust Model

| Tier | Source | Surfaced |
|------|--------|----------|
| 1: Anthropic | `anthropics/skills`, `anthropics/claude-plugins-official` | Always |
| 2: Verified | Registry `verified: true` or `stars >= 10` flag | Always |
| 3: Community | Unverified, low stars | Never (manual install only) |

Hardcoded in the discovery agent for v1. Configurable allowlist deferred.

**"Verified" definition:** This uses the registry's own verification metadata. We do not run our own verification. The registry operators determine what "verified" means. This is a pragmatic choice -- we trust registry operators as much as we trust npm or RubyGems for their verified badge.

### Installation

- **Agents:** `plugins/soleur/agents/community/<name>.md` -- auto-discovered (agents recurse)
- **Skills:** `plugins/soleur/skills/community-<name>/SKILL.md` -- flat naming required (Claude Code loader doesn't recurse skills)
- **Install location:** Current working directory (respects worktree if active)

**Directory asymmetry (intentional):** Agents use a subdirectory (`agents/community/`) because the loader recurses. Skills use a prefix (`skills/community-<name>/`) because the loader only discovers `skills/*/SKILL.md`. This asymmetry is a deliberate workaround for the Claude Code runtime limitation, not an oversight. Both conventions enable easy cleanup: `rm -rf agents/community/` or `rm -rf skills/community-*/`.

**Why `agents/community/` and not domain directories:** The Architecture reviewer suggested placing community agents in domain directories (e.g., `agents/engineering/review/community--flutter-review.md`). We chose a separate `community/` directory because: (a) it enables easy bulk cleanup, (b) the discovered name (`soleur:community:flutter-review`) clearly signals provenance to the user, (c) community agents may not fit neatly into existing domain categories.

Validation before writing to disk:
1. YAML frontmatter parses successfully
2. Required fields present (`name`, `description`)
3. File size under 100KB
4. No path traversal in field values

Provenance frontmatter added to every installed artifact:
```yaml
---
name: flutter-review
description: "Flutter-specific code review agent"
model: inherit
stack: flutter
source: "anthropics/skills"
registry: "api.claude-plugins.dev"
installed: "2026-02-18"
verified: true
---
```

**Note:** The `stack`, `source`, `registry`, `installed`, and `verified` fields are non-standard. A Phase 0 loader test (task 1.0) verifies the loader ignores unknown frontmatter fields before implementation proceeds.

### Approval Flow

Present up to 5 suggestions. For each:
```
[1/3] flutter-review (anthropics/skills, verified)
  Flutter-specific code review patterns for Dart and Widget trees.
  Install? [approve / skip / skip all]
```

"Skip all" ends discovery immediately and proceeds to planning.

### Rollback

If a community agent causes issues:
1. Delete the file: `rm agents/community/<name>.md` or `rm -rf skills/community-<name>/`
2. The agent/skill disappears from the next session
3. No plugin reload or restart needed (files are read per-session)

To list all community-installed artifacts: `ls agents/community/ skills/community-*/SKILL.md 2>/dev/null`

## Implementation Phases

### Phase 1: Discovery Agent + /plan Integration (this PR)

**Tasks:**

**1.0 Phase 0 Loader Test (prerequisite)**
- Create a test agent with extra frontmatter fields (`stack`, `source`, `registry`, `installed`, `verified`)
- Verify the plugin loader discovers it correctly
- If loader rejects extra fields: move provenance to markdown comment blocks
- Delete the test agent after verification

**1.1 Add `stack` field to existing conditional agents**
- Add `stack: rails` to `dhh-rails-reviewer.md` and `kieran-rails-reviewer.md`
- This enables the gap check algorithm to know Rails is covered

**1.2 Create discovery agent**
- Create `plugins/soleur/agents/engineering/discovery/agent-finder.md`
- YAML frontmatter: name, description, model (inherit)
- Example block with context/user/assistant/commentary (per constitution)
- Instructions for: stack gap detection, registry queries (curl), JSON parsing, trust filtering, deduplication, approval flow, installation with validation, graceful degradation

**1.3 Create community directory**
- Create `plugins/soleur/agents/community/.gitkeep`

**1.4 Integrate discovery into /plan**
- Add Phase 1.5 "Discovery Check" between local research and external research
- Stack detection via file-signature heuristics
- Gap checking via `stack:` frontmatter field
- Conditional spawn of agent-finder
- Graceful fallthrough if no gap or discovery fails

**1.5 Version bump and docs**
- Bump version in `plugins/soleur/plugin.json` (MINOR -- new agent + new behavior)
- Add CHANGELOG.md entry
- Update README.md (agent count, mention community discovery)

**1.6 Review and ship**
- Run code review on unstaged changes
- Run `/soleur:compound` to capture learnings
- Stage all artifacts
- Commit, push, create PR referencing #55

**Files changed:**
- `plugins/soleur/agents/engineering/discovery/agent-finder.md` (new)
- `plugins/soleur/agents/community/.gitkeep` (new)
- `plugins/soleur/agents/engineering/review/dhh-rails-reviewer.md` (add `stack` field)
- `plugins/soleur/agents/engineering/review/kieran-rails-reviewer.md` (add `stack` field)
- `plugins/soleur/commands/soleur/plan.md` (add Phase 1.5)
- `plugins/soleur/plugin.json` (version bump)
- `plugins/soleur/CHANGELOG.md` (entry)
- `plugins/soleur/README.md` (agent count update)

### Phase 2: Polish (future, on demand)

- Per-project caching (store results in `.soleur/discovery-cache.json`)
- Configurable trust allowlist in settings
- Conflict detection: warn when community agent overlaps new built-in
- "Don't ask again" per stack per project
- Suggestion grouping for multi-stack projects

### Phase 3: Advanced (future, only if requested)

- User-configured SkillsMP MCP for semantic search
- Static bundled index for offline/fast discovery
- Community agent update checking
- Automated frontmatter quality scoring

## Acceptance Criteria

- [ ] `/plan` on a Flutter project (no built-in Flutter agents) triggers discovery at Phase 1.5
- [ ] `/plan` on a Rails project (built-in Rails agents with `stack: rails`) does NOT trigger discovery
- [ ] Only Anthropic + verified publisher artifacts are suggested
- [ ] User can approve, skip, or skip-all suggestions
- [ ] Approved agents install to `agents/community/` with provenance frontmatter including `stack` field
- [ ] Approved skills install to `skills/community-<name>/` with provenance frontmatter
- [ ] Network failures do not block planning
- [ ] Malformed registry responses treated as empty (no crash)
- [ ] Invalid YAML frontmatter in downloaded artifact rejects installation
- [ ] Installed community agents work in subsequent commands
- [ ] Re-running `/plan` after community install does not re-trigger discovery for the same stack

## Test Scenarios

- Given a Flutter project with no Flutter agents, when running `/plan`, then discovery suggests Flutter agents from trusted registries
- Given a Rails project with built-in Rails agents (frontmatter `stack: rails`), when running `/plan`, then discovery does not trigger
- Given all registries unreachable, when running `/plan` on a Flutter project, then a warning is shown and planning continues
- Given Flutter agents previously installed in `agents/community/` with `stack: flutter`, when running `/plan` again, then discovery does not trigger
- Given registry returns malformed JSON, when querying, then that registry is treated as empty
- Given downloaded agent has invalid YAML, when attempting install, then installation is rejected with message
- Given user selects "skip all", when presented with 3 suggestions, then all are skipped and planning continues immediately
- Given a Rails + Flutter monorepo and the feature only touches Rails code, when running `/plan`, then discovery may trigger for Flutter (false positive accepted -- Phase 1.5 placement reduces but does not eliminate this)

## Non-Goals

- Auto-installing without user consent
- Auto-updating installed community agents
- Configurable allowlist (v2)
- Per-project caching (v2)
- Discovery during commands other than `/plan` (v2)
- SkillsMP MCP integration (v2, requires user API key)
- Static bundled index (v2)
- "Don't ask again" mechanism (v2)
- Sandboxing community agent capabilities
- Content-level prompt injection scanning (accepted risk -- mitigated by source-gating + human approval)

## Dependencies and Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Registry APIs change or go offline | Discovery fails | Graceful degradation: skip and continue |
| Low-quality artifacts suggested | User installs bad agent | Frontmatter validation + verified-only filter |
| Supply chain: compromised publisher | Malicious system prompt | Source-gating + human approval + easy removal |
| Prompt injection in community agent body | Agent manipulates Claude behavior | Source-gating (Anthropic + verified only) + human reads content before approving + easy removal (delete file) |
| Registry adds authentication | Registry becomes unusable | Detect 401/403 as permanent failure, skip that registry |
| Extra frontmatter fields rejected by loader | Community agents invisible | Phase 0 loader test (task 1.0) catches this before implementation |
| False positive gap detection on monorepos | Unnecessary discovery prompts | Accepted for v1. Phase 1.5 placement reduces frequency. "Skip all" minimizes friction |

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-12-external-agent-discovery-brainstorm.md`
- Spec: `knowledge-base/specs/feat-external-agent-discovery/spec.md`
- Registry research: `knowledge-base/specs/feat-external-agent-discovery/registry-research.md`
- Conditional agents pattern: `plugins/soleur/commands/soleur/review.md:81-138`
- Constitution: `knowledge-base/overview/constitution.md`
- Issue: #55
- MCP audit: #116, PR #125
- Plugin loader learning: `knowledge-base/learnings/2026-02-12-plugin-loader-agent-vs-skill-recursion.md`
- MCP bundling learning: `knowledge-base/learnings/integration-issues/2026-02-18-authenticated-mcp-servers-cannot-bundle-in-plugin-json.md`
