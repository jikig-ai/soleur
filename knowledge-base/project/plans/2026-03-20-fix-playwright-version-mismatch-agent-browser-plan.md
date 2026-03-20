---
title: "fix: resolve Playwright version mismatch between agent-browser and Playwright MCP"
type: fix
date: 2026-03-20
semver: patch
---

# fix: resolve Playwright version mismatch between agent-browser and Playwright MCP

## Overview

The globally installed `agent-browser@0.5.0` depends on `playwright-core@1.57.0`, which expects Chromium revision 1200. The Playwright MCP plugin (`@playwright/mcp@latest`) installs Chromium revision 1208 (from Playwright 1.58.2). Since only revision 1208 exists at `~/.cache/ms-playwright/chromium-1208/`, agent-browser fails with "Version mismatch between agent-browser (expects 1200) and installed Playwright (1208)."

## Problem Statement

Two independent systems share the `~/.cache/ms-playwright/` browser cache but depend on different Playwright versions:

1. **agent-browser@0.5.0** -- depends on `playwright-core@^1.57.0` (resolved to 1.57.0), expects Chromium revision **1200** at `~/.cache/ms-playwright/chromium-1200/`
2. **Playwright MCP plugin** (`playwright@claude-plugins-official`) -- runs `npx @playwright/mcp@latest` which depends on `playwright@1.59.0-alpha`, but the system `npx playwright install` installed Chromium revision **1208** (Playwright 1.58.2)

The revision 1200 directory does not exist. Only `chromium-1208` and `chromium_headless_shell-1208` are present. When agent-browser launches, `playwright-core@1.57.0` looks for `chromium-1200/` and fails.

### Root Cause Chain

1. `npx playwright install` (run globally) installed revision 1208 browsers (matching system Playwright 1.58.2)
2. `agent-browser@0.5.0`'s bundled `playwright-core@1.57.0` has `browsers.json` specifying revision 1200
3. Playwright's browser lookup is exact-match on revision number -- no forward compatibility
4. Result: agent-browser cannot find a usable Chromium binary

## Proposed Solution

### Option A: Update agent-browser to latest (Recommended)

Update from `agent-browser@0.5.0` to `agent-browser@0.21.4` (latest). The new version:
- Has **zero npm dependencies** (50.6 MB self-contained bundle vs 3.7 MB + playwright-core)
- Bundles its own browser binary, eliminating shared-cache conflicts entirely
- Published by Vercel 3 hours ago, actively maintained

```bash
npm install -g agent-browser@0.21.4
```

**Advantages:**
- Eliminates the version coupling permanently -- no future Playwright MCP upgrades will break agent-browser
- The bundled browser means `agent-browser install` is no longer needed
- Maintained version (0.5.0 is 80 versions behind)

**Risks:**
- API changes between 0.5.0 and 0.21.4 may break existing SKILL.md command examples
- The 50.6 MB package size is ~14x larger (acceptable for a global CLI)

### Option B: Install matching Chromium revision (Quick fix)

Run agent-browser's own install command to download revision 1200:

```bash
npx playwright-core@1.57.0 install chromium
```

This would create `~/.cache/ms-playwright/chromium-1200/` alongside the existing `chromium-1208/`.

**Advantages:**
- Minimal change, no version upgrade needed
- Both revisions coexist in the cache

**Risks:**
- Fragile -- next Playwright MCP update may change revision again, re-triggering the mismatch
- Wastes ~300 MB disk for duplicate Chromium installations
- Does not address the underlying coupling between two independent tools sharing a cache

### Option C: Symlink hack (Not recommended)

Symlink `chromium-1200` to `chromium-1208`. Not recommended because Playwright checks the binary version at launch and will reject a binary that doesn't match its expected revision.

## Decision: Option A

Option A is the correct fix. It eliminates the root cause (shared browser cache coupling) rather than working around it. The SKILL.md files need updating if the CLI API has changed, but that's a one-time cost.

## Technical Considerations

### Agent-browser CLI API compatibility

Need to verify the following commands still work in 0.21.4:
- `agent-browser open <url>`
- `agent-browser snapshot -i`
- `agent-browser click @e1`
- `agent-browser fill @e1 "text"`
- `agent-browser screenshot <file>`
- `agent-browser --headed` flag
- `agent-browser --session` flag
- `agent-browser install` (may no longer be needed)

### Files referencing agent-browser

These files contain agent-browser commands or version references that may need updating:

1. `plugins/soleur/skills/agent-browser/SKILL.md` -- Main skill documentation
2. `plugins/soleur/skills/test-browser/SKILL.md` -- E2E testing skill using agent-browser
3. `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- Dependency check script
4. `plugins/soleur/skills/feature-video/SKILL.md` -- Feature video skill
5. `plugins/soleur/agents/operations/ops-provisioner.md` -- Browser automation agent
6. `plugins/soleur/agents/operations/ops-research.md` -- Research agent with browser
7. `plugins/soleur/skills/review/references/review-e2e-testing.md` -- Review testing reference

### Playwright MCP is unaffected

The Playwright MCP plugin (`mcp__plugin_playwright_playwright__*` tools) runs via `npx @playwright/mcp@latest` and manages its own browser installation (the `mcp-chrome-*` directory in the cache). This fix only addresses the `agent-browser` CLI tool. No changes to Playwright MCP configuration are needed.

### Existing learning applies

`knowledge-base/project/learnings/2026-03-19-npm-global-install-version-pinning.md` documents the principle that global npm installs should be version-pinned. The fix should pin to a specific version (`agent-browser@0.21.4`), not use `@latest`.

## Acceptance Criteria

- [ ] `agent-browser` updated to 0.21.4 (or latest stable) globally
- [ ] `agent-browser open https://example.com` succeeds without version mismatch error
- [ ] `agent-browser snapshot -i` returns element refs
- [ ] `agent-browser screenshot test.png` captures a screenshot
- [ ] SKILL.md files updated if any CLI API changes are detected
- [ ] Playwright MCP tools (`browser_navigate`, `browser_snapshot`) continue to work independently
- [ ] Old Chromium revision 1200 directory does not need to exist
- [ ] `check_deps.sh` updated if the install command changed

## Test Scenarios

- Given agent-browser@0.21.4 is installed globally, when running `agent-browser open https://example.com`, then it opens the page without a version mismatch error
- Given agent-browser@0.21.4 is installed globally, when running `agent-browser snapshot -i`, then it returns element refs in the expected format
- Given Playwright MCP tools are configured, when running `browser_navigate` via MCP, then it works independently of agent-browser's version
- Given agent-browser@0.21.4 has no playwright-core dependency, when Playwright is upgraded globally, then agent-browser is not affected
- Given the test-browser skill is invoked, when agent-browser CLI commands are run, then they use the syntax compatible with 0.21.4

## Non-goals

- Modifying Playwright MCP plugin configuration
- Downgrading the system Playwright version
- Pinning `@playwright/mcp` to a specific version (it manages its own browser)
- Changing the browser interaction hierarchy (Playwright MCP > agent-browser > manual) established in the existing plan

## MVP

### Phase 1: Update agent-browser

```bash
npm install -g agent-browser@0.21.4
```

### Phase 2: Verify CLI API compatibility

```bash
agent-browser open https://example.com
agent-browser snapshot -i
agent-browser screenshot test.png
agent-browser close
rm -f test.png
```

### Phase 3: Update documentation (if API changed)

If any commands changed between 0.5.0 and 0.21.4, update:

- `plugins/soleur/skills/agent-browser/SKILL.md`
- `plugins/soleur/skills/test-browser/SKILL.md`
- `plugins/soleur/skills/feature-video/scripts/check_deps.sh`

### Phase 4: Create learning

Document the version mismatch pattern in a new learning:

```text
knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md
```

Key insight: When two tools share `~/.cache/ms-playwright/`, their Playwright versions must be compatible or one must bundle its own browser. Self-contained packages (like agent-browser@0.21.4) eliminate this coupling.

## References

- `plugins/soleur/skills/agent-browser/SKILL.md` -- agent-browser skill documentation
- `plugins/soleur/skills/test-browser/SKILL.md` -- E2E testing skill
- `knowledge-base/project/plans/2026-03-10-fix-default-playwright-mcp-browser-interactions-plan.md` -- Related plan establishing Playwright MCP as default
- `knowledge-base/project/learnings/2026-03-19-npm-global-install-version-pinning.md` -- npm version pinning principle
- `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md` -- Playwright MCP path resolution gotcha
- [agent-browser npm](https://www.npmjs.com/package/agent-browser) -- Package registry
- [Playwright browser versioning](https://playwright.dev/docs/browsers) -- How Playwright manages browser revisions
