---
title: "feat: Add automated tests for plugin markdown components"
type: feat
date: 2026-02-12
issue: "#62"
version-bump: MINOR
deepened: 2026-02-12
---

# Add Automated Tests for Plugin Markdown Components

## Enhancement Summary

**Deepened on:** 2026-02-12
**Research agents used:** test-design-reviewer, code-simplicity-reviewer, codebase explorer, Context7 (Bun docs)

### Key Improvements
1. Simplified from 5 files to 2 files (components.test.ts + helpers.ts)
2. Removed YAGNI: root package.json, test tsconfig, heading hierarchy checks, reference file existence checks
3. Added granular assertion pattern: describe per file, test per field, custom error messages

## Overview

The plugin has 65 markdown components (22 agents, 8 commands, 35 skills) with zero automated tests. YAML frontmatter errors, broken markdown structure, and convention violations are only caught during manual use. This plan adds a `bun:test` suite that validates component structure and integrates with the pre-commit hook.

## Problem Statement

Broken frontmatter silently degrades agent/skill discovery with no error feedback. Missing required fields (`model`, `argument-hint`) go unnoticed. Convention violations (backtick references, wrong voice) accumulate. The telegram-bridge app has 84 tests, but plugin components have none.

## Proposed Solution

Create a test suite in `plugins/soleur/test/` using `bun:test` that validates all plugin markdown components. Fix known violations. Update the pre-commit hook to trigger tests on `.md` file changes under `plugins/soleur/`.

## Technical Approach

### Test Location & Infrastructure

- **Test directory:** `plugins/soleur/test/`
- **No root package.json needed.** Bun discovers `*.test.ts` files recursively. Lefthook runs `bun test plugins/soleur/test/` directly.
- **No test-specific tsconfig needed.** Bun's defaults handle ESNext + TypeScript out of the box.

### Test File Structure

```
plugins/soleur/test/
  components.test.ts    # All validation: frontmatter, structure, conventions
  helpers.ts            # File discovery, YAML parsing, shared utilities
```

Two files. One test file with logical `describe` blocks, one helper module. Bun supports `--test-name-pattern` filtering for debugging specific categories.

### Component Discovery (`helpers.ts`)

Glob patterns matching plugin loader behavior:

- **Agents:** `plugins/soleur/agents/**/*.md` (recursive -- loader recurses into subdirectories)
- **Commands:** `plugins/soleur/commands/soleur/*.md` (flat)
- **Skills:** `plugins/soleur/skills/*/SKILL.md` (one level only -- loader does NOT recurse skills)

Exclude: README.md, CHANGELOG.md, AGENTS.md, CLAUDE.md, LICENSE at plugin root.

```typescript
// helpers.ts
import { Glob } from "bun";

const PLUGIN_ROOT = "plugins/soleur";

export function discoverAgents(): string[] {
  return Array.from(new Glob(`${PLUGIN_ROOT}/agents/**/*.md`).scanSync("."))
    .filter(f => !f.endsWith("README.md"));
}

export function discoverCommands(): string[] {
  return Array.from(new Glob(`${PLUGIN_ROOT}/commands/soleur/*.md`).scanSync("."));
}

export function discoverSkills(): string[] {
  return Array.from(new Glob(`${PLUGIN_ROOT}/skills/*/SKILL.md`).scanSync("."));
}

export function parseFrontmatter(filePath: string): Record<string, unknown> {
  const content = Bun.file(filePath).text();
  // Parse YAML between --- delimiters
}
```

### Test Categories

All in `components.test.ts` with describe blocks:

**1. YAML Frontmatter Validation**

| Component | Required Fields | Allowed Values |
|-----------|----------------|----------------|
| Agent | `name`, `description`, `model` | model: `inherit`, `haiku`, `sonnet`, `opus` |
| Command | `name`, `description`, `argument-hint` | argument-hint: string (may be empty for commands that take no args) |
| Skill | `name`, `description` | -- |

**Granular assertion pattern** (from test design review -- improves failure messages):

```typescript
describe("Agent frontmatter", () => {
  const agents = discoverAgents();

  agents.forEach(agentPath => {
    describe(agentPath, () => {
      const fm = parseFrontmatter(agentPath);

      test("has name field", () => {
        expect(fm.name).toBeDefined();
      });

      test("has description field", () => {
        expect(fm.description).toBeDefined();
      });

      test("has valid model field", () => {
        expect(["inherit", "haiku", "sonnet", "opus"]).toContain(fm.model);
      });
    });
  });
});
```

This produces failures like: `Agent frontmatter > agents/research/foo.md > has valid model field` -- pinpointing exact file and field.

**2. Markdown Structure**

- Content exists after frontmatter (not empty body)

That's it. No heading hierarchy checks -- these are prompt instructions, not documentation. Heading jumps don't break agent execution.

**3. Convention Compliance**

- **Third-person voice:** Skill `description` fields must start with "This skill" (per constitution line 9)
- **Kebab-case filenames:** Agent `.md` filenames, command `.md` filenames, and skill directory names match `/^[a-z0-9]+(-[a-z0-9]+)*$/`
- **Backtick reference detection:** No inline backtick references matching `` `(references|assets|scripts)/[^`]+` `` in skill SKILL.md content. Simple regex -- no code block exclusion logic needed. The constitution bans backtick references unconditionally.
- **Agent example blocks:** Agent `description` fields contain at least one `<example>` block (per constitution line 13)

### Known Violations to Fix

These must be fixed in the same PR so tests pass on merge:

| Component | Violation | Fix |
|-----------|-----------|-----|
| `skills/agent-browser/SKILL.md` | Description doesn't start with "This skill" | Rewrite to "This skill should be used when automating browser interactions..." |
| `skills/rclone/SKILL.md` | Description doesn't start with "This skill" | Rewrite to "This skill should be used when uploading, syncing, or managing files..." |
| `commands/soleur/help.md` | Missing `argument-hint` | Add `argument-hint: ""` |
| `commands/soleur/one-shot.md` | Missing `argument-hint` | Add `argument-hint: "[feature description or issue reference]"` |
| Skills with backtick refs | Backtick paths instead of markdown links | Convert to `[filename](./references/filename)` format |

### Pre-commit Hook Update

Add to `lefthook.yml` after existing `bun-test` (priority 5):

```yaml
plugin-component-test:
  priority: 6
  glob: "plugins/soleur/**/*.md"
  run: bun test plugins/soleur/test/
```

Runs only when `.md` files under `plugins/soleur/` are staged. Sequential execution (existing `parallel: false` setting).

## Acceptance Criteria

- [ ] Test suite covers all plugin component types (agents, commands, skills)
- [ ] Tests run via `bun test plugins/soleur/test/`
- [ ] Pre-commit hook catches regressions when `.md` files under `plugins/soleur/` change
- [ ] All 65 existing components pass all tests
- [ ] Known violations fixed
- [ ] Test execution under 2 seconds

## Test Scenarios

- Given a new agent file without a `model` field, when `bun test` runs, then the test fails with `agents/path/file.md > has valid model field`
- Given a skill description starting with "Use when", when `bun test` runs, then the test fails identifying the third-person voice violation with file path
- Given a skill with `` `references/guide.md` `` in content, when `bun test` runs, then the backtick detection test fails with file path and matched pattern
- Given all components are valid, when `bun test` runs, then all tests pass in under 2 seconds
- Given a `.md` file under `plugins/soleur/` is staged, when committing, then lefthook triggers the plugin-component-test hook
- Given a malformed YAML frontmatter, when `bun test` runs, then the test fails with a clear parse error and file path

## Non-Goals

- Validating semantic content of prompts/instructions
- Testing that agents/skills work when invoked by Claude
- CI/CD pipeline integration (future work)
- Auto-fix capability for violations
- Reference link file existence checks (fails gracefully at runtime)
- Heading hierarchy validation (cosmetic, not functional)

## Dependencies & Risks

- **Violation fixes:** Changing skill descriptions changes the text Claude Code users see. Keep changes minimal and semantically equivalent.
- **False positives:** Third-person voice check ("This skill") is strict. If any skill legitimately needs a different pattern, add an explicit exception list in the test helpers.
- **Bun glob API:** Uses `Bun.Glob` for file discovery. Verify it handles the recursive agent directory structure correctly.

## Implementation Phases

### Phase 1: Test Infrastructure
1. Create `plugins/soleur/test/helpers.ts` -- file discovery (3 glob functions) + YAML frontmatter parser
2. Create `plugins/soleur/test/components.test.ts` -- all validation tests with granular describe/test blocks
3. Verify `bun test plugins/soleur/test/` discovers and runs tests

### Phase 2: Fix Violations
4. Fix skill descriptions (agent-browser, rclone, and any others discovered by tests)
5. Fix command frontmatter (help, one-shot argument-hint)
6. Fix backtick references in skills (dspy-ruby, compound-docs, skill-creator, others)
7. Run full test suite -- all 65 components must pass

### Phase 3: Hook Integration & Ship
8. Update `lefthook.yml` with plugin-component-test hook
9. Version bump (MINOR -- new test infrastructure)
10. Update plugin README with test section
11. Commit, push, PR referencing #62

## References

- Issue: #62
- Technical debt: `knowledge-base/learnings/technical-debt/2026-02-12-plugin-components-untested.md`
- Pre-commit gap: `knowledge-base/learnings/technical-debt/2026-02-12-precommit-hooks-missing-test-execution.md`
- Backtick violations: `knowledge-base/learnings/technical-debt/2026-02-12-backtick-references-in-skills.md`
- Plugin loader recursion: `knowledge-base/learnings/2026-02-12-plugin-loader-agent-vs-skill-recursion.md`
- Constitution testing section: `knowledge-base/overview/constitution.md:76-96`
- Existing test patterns: `apps/telegram-bridge/test/helpers.test.ts`
- Bun test runner: `https://bun.sh/docs/test`
