---
title: "fix: resolve Playwright version mismatch between agent-browser and Playwright MCP"
type: fix
date: 2026-03-20
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, MVP, Acceptance Criteria, Test Scenarios)
**Research sources:** agent-browser GitHub README (0.21.4), npm registry metadata, 4 institutional learnings, CLI command audit

### Key Improvements

1. Corrected critical misunderstanding: agent-browser@0.21.4 is a **Rust native CLI** using Chrome for Testing, not a Node.js wrapper around Playwright. It still requires `agent-browser install` but downloads Chrome for Testing (not Playwright's Chromium), eliminating the shared-cache problem entirely.
2. Identified concrete API changes: `--session` renamed to `--session-name`, new `batch` command, `--annotate` screenshot flag, new `diff`, `network`, `clipboard` commands. Core commands (`open`, `snapshot -i`, `click @ref`, `fill @ref`, `screenshot`) are unchanged.
3. The `check_deps.sh` install instruction is still correct (`npm install -g agent-browser && agent-browser install`) -- `agent-browser install` is still required but now downloads Chrome for Testing instead of Playwright's Chromium.
4. Added `postinstall` script awareness -- npm install triggers `scripts/postinstall.js` which may handle some setup automatically.

### New Considerations Discovered

- agent-browser@0.21.0 still had `playwright-core@^1.57.0` as a dependency. The bundling happened in 0.21.1+. The switch to Rust native CLI with Chrome for Testing was a significant architecture change.
- The `--session` flag from 0.5.0 is now `--session-name` in 0.21.4. SKILL.md files referencing `--session` need updating.
- agent-browser now has a config file system (`.agent-browser.json`) and environment variable overrides for all flags.
- Linux may need `agent-browser install --with-deps` for system dependencies.

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

Update from `agent-browser@0.5.0` to `agent-browser@0.21.4` (latest). The new version is a **fundamentally different architecture**:

- **Rust native CLI** (not Node.js) -- fast startup, no Node.js runtime needed for the daemon
- Uses **Chrome for Testing** (Google's official automation channel) instead of Playwright's Chromium
- Has **zero npm dependencies** (50.6 MB self-contained bundle including Rust binary)
- Browser downloaded via `agent-browser install` to its own directory, **not** `~/.cache/ms-playwright/`
- Still requires `agent-browser install` but downloads from Chrome for Testing, not Playwright

```bash
npm install -g agent-browser@0.21.4
agent-browser install  # Downloads Chrome for Testing (not Playwright's Chromium)
```

### Research Insights

**Architecture migration timeline (from npm registry):**
- `agent-browser@0.5.0` (installed) -- Node.js, depends on `playwright-core@^1.57.0`, 3.7 MB
- `agent-browser@0.21.0` -- Still depends on `playwright-core@^1.57.0` (last version with Playwright dep)
- `agent-browser@0.21.1` -- Zero dependencies, 50 MB (Rust binary bundled, Chrome for Testing)
- `agent-browser@0.21.4` -- Latest, same architecture as 0.21.1

**CLI API compatibility audit (from GitHub README):**

| Command | 0.5.0 | 0.21.4 | Status |
|---------|-------|--------|--------|
| `open <url>` | Yes | Yes | Unchanged |
| `snapshot -i` | Yes | Yes | Unchanged |
| `snapshot -i --json` | Yes | Yes | Unchanged |
| `snapshot -c` (compact) | Yes | Yes | Unchanged |
| `click @e1` | Yes | Yes | Unchanged |
| `fill @e1 "text"` | Yes | Yes | Unchanged |
| `type @e1 "text"` | Yes | Yes | Unchanged |
| `screenshot [path]` | Yes | Yes | Unchanged (new `--annotate` flag added) |
| `screenshot --full` | Yes | Yes | Unchanged |
| `--headed` | Yes | Yes | Unchanged |
| `--session` | Yes | **Renamed** to `--session-name` | Breaking |
| `session list` | Yes | **Changed** to `state list` | Breaking |
| `install` | Yes | Yes | Still required (Chrome for Testing, not Playwright) |
| `close` | Yes | Yes | Unchanged (aliases: `quit`, `exit`) |
| `find role` | Yes | Yes | Added `--name` filter |
| `batch` | No | Yes | New command |
| `diff` | No | Yes | New command |
| `network` | No | Yes | New command |
| `clipboard` | No | Yes | New command |
| `upgrade` | No | Yes | New command |

**Key breaking change:** `--session` is now `--session-name`. The agent-browser SKILL.md section on "Sessions (Parallel Browsers)" needs updating.

**Advantages:**
- Eliminates the Playwright version coupling permanently -- agent-browser now uses Chrome for Testing, a completely separate browser from Playwright's Chromium
- No shared cache directory (`~/.cache/ms-playwright/`) -- the two tools are fully independent
- Maintained version (0.5.0 is 80 versions behind)
- Faster startup (Rust native daemon model vs Node.js per-command)

**Risks:**
- The `--session` to `--session-name` rename will break SKILL.md documentation (low risk -- easy to update)
- 50.6 MB package size is ~14x larger (acceptable for a global CLI)
- `agent-browser install` now downloads Chrome for Testing (~300 MB) which needs disk space in addition to any existing Playwright browsers
- The `postinstall` script (`scripts/postinstall.js`) runs automatically during `npm install -g` and may handle some setup

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

Option A is the correct fix. It eliminates the root cause (shared browser cache coupling) by moving agent-browser to an entirely different browser backend (Chrome for Testing vs Playwright's Chromium). The SKILL.md changes are minimal -- only the `--session` to `--session-name` rename is a breaking change; all core commands are identical.

## Technical Considerations

### Agent-browser CLI API compatibility

Verified from the 0.21.4 README -- all core commands used in SKILL.md files are unchanged:

- `agent-browser open <url>` -- unchanged
- `agent-browser snapshot -i` -- unchanged
- `agent-browser snapshot -i --json` -- unchanged
- `agent-browser click @e1` -- unchanged
- `agent-browser fill @e1 "text"` -- unchanged
- `agent-browser screenshot <file>` -- unchanged (new `--annotate` option added)
- `agent-browser --headed` -- unchanged
- `agent-browser --session` -- **renamed to `--session-name`** (breaking)
- `agent-browser install` -- still required (downloads Chrome for Testing, not Playwright's Chromium)

### Research Insights: Linux system dependencies

On Linux, `agent-browser install --with-deps` installs required system libraries. The current install instruction (`npm install -g agent-browser && agent-browser install`) may need updating to use `--with-deps` on Debian/Ubuntu. The `check_deps.sh` script should be updated accordingly.

### Files referencing agent-browser

These files contain agent-browser commands or version references that may need updating:

1. `plugins/soleur/skills/agent-browser/SKILL.md` -- Main skill documentation
   - **Update needed:** `--session` examples to `--session-name`
   - **Update needed:** "vs Playwright MCP" table -- agent-browser no longer uses Playwright
   - **Update needed:** Install instructions -- add note about Chrome for Testing
2. `plugins/soleur/skills/test-browser/SKILL.md` -- E2E testing skill using agent-browser
   - **No changes needed** -- uses `open`, `snapshot -i`, `click`, `fill`, `screenshot` (all unchanged)
3. `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- Dependency check script
   - **Minimal change:** Install instruction is the same (`npm install -g agent-browser && agent-browser install`)
   - **Consider:** Adding `--with-deps` for Linux
4. `plugins/soleur/skills/feature-video/SKILL.md` -- Feature video skill
   - **Check if** it references `--session` (if so, update to `--session-name`)
5. `plugins/soleur/agents/operations/ops-provisioner.md` -- Browser automation agent
   - **No agent-browser changes needed** -- this agent was already updated to prefer Playwright MCP per the existing plan
6. `plugins/soleur/agents/operations/ops-research.md` -- Research agent with browser
   - **No agent-browser changes needed** -- same as ops-provisioner
7. `plugins/soleur/skills/review/references/review-e2e-testing.md` -- Review testing reference
   - **No changes needed** -- references `/test-browser` skill, not agent-browser directly

### Playwright MCP is unaffected

The Playwright MCP plugin (`mcp__plugin_playwright_playwright__*` tools) runs via `npx @playwright/mcp@latest` and manages its own browser installation (the `mcp-chrome-*` directory in the cache). After this fix, agent-browser and Playwright MCP use completely different browser backends:
- **agent-browser@0.21.4** -- Chrome for Testing (its own download directory)
- **Playwright MCP** -- Chromium from `~/.cache/ms-playwright/chromium-1208/` or its own `mcp-chrome-*` profile

The two tools are now fully decoupled.

### Existing learnings that apply

1. **`2026-03-19-npm-global-install-version-pinning.md`** -- Pin to a specific version (`agent-browser@0.21.4`), not `@latest`. The npm registry guarantees published versions are immutable.
2. **`2026-02-17-playwright-screenshots-land-in-main-repo.md`** -- Playwright MCP path resolution from repo root. Unaffected by this fix, but relevant context: agent-browser screenshots resolve from CWD (different behavior from Playwright MCP).
3. **`2026-03-13-browser-tasks-require-playwright-not-manual-labels.md`** -- Playwright MCP is the default for browser tasks. Agent-browser is a fallback. This fix ensures the fallback works.
4. **`2026-02-13-agent-prompt-sharp-edges-only.md`** -- SKILL.md updates should document sharp edges only (the `--session` to `--session-name` rename), not re-document all commands the model already knows.

### Research Insight: postinstall script

agent-browser@0.21.4 has a `postinstall` script (`scripts/postinstall.js`) that runs automatically during `npm install -g`. This may print setup instructions or attempt to download Chrome for Testing automatically. If it does, `agent-browser install` may be partially redundant. Verify during implementation.

## Acceptance Criteria

- [ ] `agent-browser` updated to 0.21.4 globally via `npm install -g agent-browser@0.21.4`
- [ ] `agent-browser install` run successfully (downloads Chrome for Testing)
- [ ] `agent-browser open https://example.com` succeeds without version mismatch error
- [ ] `agent-browser snapshot -i` returns element refs in the `@e1` format
- [ ] `agent-browser screenshot test.png` captures a screenshot
- [ ] agent-browser SKILL.md updated: `--session` examples changed to `--session-name`
- [ ] agent-browser SKILL.md updated: "vs Playwright MCP" table reflects Chrome for Testing backend
- [ ] Playwright MCP tools (`browser_navigate`, `browser_snapshot`) continue to work independently
- [ ] Old Chromium revision 1200 directory does not need to exist
- [ ] `check_deps.sh` verified -- install instruction (`npm install -g agent-browser && agent-browser install`) is still correct
- [ ] Linux `--with-deps` flag documented in check_deps.sh or SKILL.md

## Test Scenarios

- Given agent-browser@0.21.4 is installed globally, when running `agent-browser open https://example.com`, then it opens the page without a version mismatch error
- Given agent-browser@0.21.4 is installed globally, when running `agent-browser snapshot -i`, then it returns element refs in `@e1` format
- Given agent-browser@0.21.4 uses Chrome for Testing, when checking `~/.cache/ms-playwright/`, then no new directories are created by agent-browser (it uses its own download path)
- Given Playwright MCP tools are configured, when running `browser_navigate` via MCP, then it works independently of agent-browser's version
- Given agent-browser@0.21.4 has no playwright-core dependency, when Playwright is upgraded globally, then agent-browser is not affected
- Given the test-browser skill is invoked, when agent-browser CLI commands are run, then `open`, `snapshot -i`, `click @ref`, `fill @ref`, `screenshot` all work identically to 0.5.0
- Given the agent-browser SKILL.md `--session` examples, when checking post-update, then they use `--session-name` instead
- Given `agent-browser install` is run on Linux, when system dependencies are missing, then `--with-deps` flag is available to install them

## Non-goals

- Modifying Playwright MCP plugin configuration
- Downgrading the system Playwright version
- Pinning `@playwright/mcp` to a specific version (it manages its own browser)
- Changing the browser interaction hierarchy (Playwright MCP > agent-browser > manual) established in the existing plan
- Cleaning up old `~/.cache/ms-playwright/chromium-*` directories (they may still be needed by Playwright MCP)

## MVP

### Phase 1: Update agent-browser

```bash
npm install -g agent-browser@0.21.4
agent-browser install  # Downloads Chrome for Testing (~300MB first time)
# On Linux if system deps missing:
# agent-browser install --with-deps
```

### Phase 2: Verify CLI API compatibility

```bash
agent-browser open https://example.com
agent-browser snapshot -i
agent-browser screenshot test.png
agent-browser close
rm -f test.png
```

### Phase 3: Update SKILL.md documentation

**agent-browser SKILL.md changes:**

1. Update "Sessions (Parallel Browsers)" section -- change `--session` to `--session-name`:

```markdown
### Sessions (Parallel Browsers)

```bash
# Run multiple independent browser sessions
agent-browser --session-name browser1 open https://site1.com
agent-browser --session-name browser2 open https://site2.com

# List saved states
agent-browser state list
```
```

2. Update "vs Playwright MCP" table -- agent-browser now uses Chrome for Testing (Rust native):

```markdown
## vs Playwright MCP

| Feature | agent-browser (CLI) | Playwright MCP |
|---------|---------------------|----------------|
| Interface | Bash commands | MCP tools |
| Selection | Refs (@e1) | Refs (e1) |
| Output | Text/JSON | Tool responses |
| Parallel | Session names | Tabs |
| Browser | Chrome for Testing | Chromium |
| Runtime | Rust native | Node.js |
| Best for | Quick automation | Tool integration |
```

3. Update install note -- Chrome for Testing, not "Downloads Chromium":

```markdown
### Install if needed

```bash
npm install -g agent-browser@0.21.4
agent-browser install  # Downloads Chrome for Testing (~300MB)
```
```

**check_deps.sh:** Install instruction `npm install -g agent-browser && agent-browser install` is still correct. Consider adding `--with-deps` note for Linux.

### Phase 4: Create learning

Document the version mismatch pattern in:

```text
knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md
```

Key insights:
1. When two tools share `~/.cache/ms-playwright/`, their Playwright versions must be compatible or one must bundle its own browser
2. Self-contained packages (like agent-browser@0.21.1+) that use Chrome for Testing instead of Playwright eliminate this coupling entirely
3. Playwright's browser lookup is exact-match on revision number -- no forward compatibility between revisions
4. Pin global npm installs to specific versions per learning `2026-03-19-npm-global-install-version-pinning.md`

## References

- `plugins/soleur/skills/agent-browser/SKILL.md` -- agent-browser skill documentation
- `plugins/soleur/skills/test-browser/SKILL.md` -- E2E testing skill
- `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- Dependency check script
- `knowledge-base/project/plans/2026-03-10-fix-default-playwright-mcp-browser-interactions-plan.md` -- Related plan establishing Playwright MCP as default
- `knowledge-base/project/learnings/2026-03-19-npm-global-install-version-pinning.md` -- npm version pinning principle
- `knowledge-base/project/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md` -- Playwright MCP path resolution gotcha
- `knowledge-base/project/learnings/2026-03-13-browser-tasks-require-playwright-not-manual-labels.md` -- Playwright MCP is default, agent-browser is fallback
- `knowledge-base/project/learnings/2026-02-13-agent-prompt-sharp-edges-only.md` -- SKILL.md sharp edges only
- [agent-browser GitHub](https://github.com/vercel-labs/agent-browser) -- Source repository and README
- [Chrome for Testing](https://developer.chrome.com/blog/chrome-for-testing/) -- Google's official automation browser channel
