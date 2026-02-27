---
title: "feat: Add pencil-setup skill for auto-detecting, installing, and registering Pencil MCP"
type: feat
date: 2026-02-27
---

# feat: Add pencil-setup skill for Pencil MCP auto-setup

[Updated 2026-02-27 — simplified after plan review: no script, inline SKILL.md only]

## Overview

Create a `pencil-setup` skill that auto-detects, installs, and registers the Pencil MCP server with Claude Code CLI. Replaces the manual "install from docs.pencil.dev" instruction in ux-design-lead with a one-command setup flow.

## Problem Statement / Motivation

Pencil MCP tools are required for visual design workflows (ux-design-lead agent, brainstorm visual handoffs) but have no automated setup path. The MCP server is a Go binary bundled inside the `highagency.pencildev` IDE extension — it can't be declared in `plugin.json` (HTTP-only). Users must manually install the extension, hope auto-registration triggers, and troubleshoot stale paths when extensions update.

**Confirmed issues from spike (2026-02-27):**
- Registration goes stale on extension updates (v0.6.25 registered, v0.6.26 installed)
- `claude mcp add` errors on duplicate names (exit 1) — need remove-then-add
- Default scope is `local` (project-level) — need `-s user` for global

## Proposed Solution

A single SKILL.md file with inline bash blocks. The LLM runs 5 sequential commands with conditional branching. No scripts/ directory. Follows the agent-browser and xcode-test patterns.

### Flow

```
1. Check if already registered → claude mcp list | grep pencil
2. Detect IDE → which cursor || which code
3. Find or install extension → glob for binary, install if missing
4. Register → claude mcp remove + claude mcp add -s user
5. Verify → claude mcp list | grep pencil
```

### Key Design Decisions

1. **Inline SKILL.md, no script** — This is a 5-command linear flow. The LLM handles sequential bash with branching all day. A script abstraction is unwarranted (review feedback: agent-browser and xcode-test use inline bash).
2. **`-s user` scope** — Registration at user level so Pencil works across all projects.
3. **Always remove-then-add** — `claude mcp add` errors on duplicates. Remove first (idempotent). This handles version drift, stale paths, and fresh installs identically — no separate drift detection needed.
4. **Glob for binary** — `ls mcp-server-*` finds the one platform binary. No `uname` mapping needed.
5. **Manual invocation first** — ux-design-lead prints "Run `/soleur:pencil-setup` first" rather than auto-invoking.
6. **No Windows in v1** — Bash-based skill. Add Windows when someone needs it.

## Technical Constraints (Empirically Verified)

| Constraint | Detail |
|-----------|--------|
| Binary always needs running IDE | `-app <ide>` flag required |
| `claude mcp add` not idempotent | Exit 1 on duplicate name, must remove first |
| Default scope is local | Must use `-s user` for global registration |
| `--app` accepts any string | `code`, `cursor`; connection attempt at runtime |
| Extension dir pattern | `~/.cursor/extensions/highagency.pencildev-*-universal/out/` |
| Multiple versions coexist | Glob finds latest via `sort -V | tail -1` |

## Acceptance Criteria

- [ ] **Already registered** — Given Pencil MCP is registered and binary path exists, skill prints "already configured" and exits
- [ ] **Fresh install** — Given no Pencil extension, skill installs via IDE CLI, registers binary with `claude mcp add -s user`, and verifies
- [ ] **No IDE** — Given no `cursor` or `code` on PATH, skill prints error with install links and stops
- [ ] **ux-design-lead updated** — Agent references `pencil-setup` skill instead of raw install URL
- [ ] **Version bump** — All version locations updated (MINOR)

## Test Scenarios

- Given no IDE installed → print "No supported IDE found" with download links
- Given Cursor + no Pencil extension → install extension, register MCP, verify
- Given Pencil already registered and path exists → print "already configured", exit

## Files to Create

### `plugins/soleur/skills/pencil-setup/SKILL.md`

~45 lines. YAML frontmatter + 4 inline bash steps (detect IDE, find/install extension, register MCP, verify). Error messages inline. Follows agent-browser pattern.

## Files to Modify

### `plugins/soleur/agents/product/design/ux-design-lead.md`

Replace prerequisite check (lines 9-11):
```
# Before:
"The Pencil extension is required for visual design. Install it from https://docs.pencil.dev/getting-started/installation"

# After:
"Pencil MCP is not configured. Run `/soleur:pencil-setup` to auto-install and register it."
```

### Version Bump Files (3.5.1 → 3.6.0, MINOR — new skill)

1. `plugins/soleur/.claude-plugin/plugin.json` — version
2. `plugins/soleur/CHANGELOG.md` — new `## [3.6.0]` entry
3. `plugins/soleur/README.md` — skill count 52→53, add pencil-setup to skills table
4. `plugins/soleur/.claude-plugin/marketplace.json` — version
5. Root `README.md` — version badge, skill count
6. `.github/ISSUE_TEMPLATE/bug_report.yml` — placeholder

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-27-pencil-setup-brainstorm.md`
- Spec: `knowledge-base/specs/feat-pencil-setup/spec.md`
- Pencil constraint learning: `knowledge-base/learnings/2026-02-14-pencil-mcp-local-binary-constraint.md`
- Similar skill: `plugins/soleur/skills/agent-browser/SKILL.md`
- Target agent: `plugins/soleur/agents/product/design/ux-design-lead.md:9-11`
- [Pencil Installation Docs](https://docs.pencil.dev/getting-started/installation)
