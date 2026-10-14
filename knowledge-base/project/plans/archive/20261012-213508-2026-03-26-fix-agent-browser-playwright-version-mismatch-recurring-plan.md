---
title: "fix: permanently resolve recurring Playwright version mismatch in agent-browser"
type: fix
date: 2026-03-26
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-26
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, MVP, Acceptance Criteria, Test Scenarios)
**Research sources:** npm registry (agent-browser@0.22.3 latest), comprehensive grep of all install references, 4 institutional learnings, PATH behavior analysis

### Key Improvements

1. **Version bump**: agent-browser@0.22.3 is now the latest (0.21.4 is 5 versions behind). Updated all pinned references. Same Rust native architecture, zero npm dependencies.
2. **Missed file discovered**: `plugins/soleur/README.md:312` also uses `npm install -g agent-browser@0.22.3` without `--prefix ~/.local` -- added to files-to-modify list.
3. **Version guard robustness**: Added edge case handling for when `--version` returns unexpected output (empty or non-numeric). Verified output format: `agent-browser X.Y.Z`.
4. **Comprehensive install reference audit**: Found 5 files (not 3) containing `npm install -g agent-browser` without `--prefix ~/.local`. All enumerated in files-to-modify.

### New Considerations Discovered

- agent-browser@0.22.3 released since the original March 20 plan. Same architecture (Rust native, Chrome for Testing, zero deps). Pinning to 0.22.3 gets latest bug fixes.
- `plugins/soleur/README.md` has a Browser Automation section (line 312) that was missed by both previous plans. Must also be updated with `--prefix ~/.local`.
- The `postinstall` script (`node scripts/postinstall.js`) is still present in 0.22.3 -- runs during `npm install -g` and may handle initial setup. Does not replace `agent-browser install` but may print helpful messages.

# fix: permanently resolve recurring Playwright version mismatch in agent-browser

## Overview

The agent-browser Playwright version mismatch (expects revision 1200, installed 1208) keeps recurring despite a previous fix (plan `2026-03-20-fix-playwright-version-mismatch-agent-browser-plan.md`). The previous plan correctly identified the solution (upgrade to agent-browser@0.22.3 which uses Chrome for Testing instead of Playwright) and the upgrade was applied to `~/.local/bin`. However, the system-level binary at `/usr/bin/agent-browser` (version 0.5.0, owned by root) shadows the local install because PATH resolution in non-interactive shells puts `/usr/bin` before `~/.local/bin`.

## Problem Statement

### What is happening

```
$ which agent-browser
/usr/bin/agent-browser          # <-- 0.5.0, depends on playwright-core@1.57.0 (revision 1200)

$ ~/.local/bin/agent-browser --version
agent-browser 0.21.4            # <-- Correct version, installed but shadowed

$ ls ~/.cache/ms-playwright/
chromium-1208/                  # <-- Only revision 1208 exists (from Playwright MCP)
```

agent-browser@0.5.0 at `/usr/bin` looks for `chromium-1200/` in `~/.cache/ms-playwright/`, finds only `chromium-1208/`, and fails with a version mismatch error.

### Why the previous fix didn't stick

The March 20 plan correctly:

1. Installed agent-browser@0.22.3 to `~/.local` via `npm install --prefix ~/.local -g agent-browser@0.22.3`
2. Documented the PATH ordering issue in a learning (`2026-03-20-npm-global-install-without-sudo.md`)
3. Updated SKILL.md documentation for the new CLI API

But it did NOT:

1. Remove or disable the system binary at `/usr/bin/agent-browser` (requires sudo)
2. Add a runtime resolution mechanism that bypasses PATH ordering
3. Update `check_deps.sh` or skill scripts to resolve the correct binary deterministically

The result: every new shell session, including the non-interactive Bash tool, resolves `/usr/bin/agent-browser` (0.5.0) instead of `~/.local/bin/agent-browser` (0.22.3). The "fix" is invisible.

### Root Cause Chain

1. agent-browser@0.5.0 was installed system-wide (`npm install -g` with sudo, January 15) -- lives at `/usr/lib/node_modules/agent-browser/` with symlink at `/usr/bin/agent-browser`
2. The user cannot run `sudo npm uninstall -g agent-browser` (AGENTS.md: "The Bash tool runs in a non-interactive shell without sudo access")
3. agent-browser@0.22.3 was installed to `~/.local` via `npm install --prefix ~/.local -g agent-browser@0.22.3`
4. PATH in non-interactive shells: `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:...:/home/jean/.local/bin`
5. `/usr/bin` appears before `~/.local/bin` in PATH, so `which agent-browser` resolves to the old 0.5.0 binary
6. `.bashrc` line 166 prepends `~/.local/bin` to PATH, but this only applies after `.bashrc` is fully sourced -- the base PATH from `/etc/environment` or login shell already has `/usr/bin` first
7. Non-interactive shells (Bash tool) may not source `.bashrc` at all, or source it after system paths are already set

## Proposed Solution

### Three-pronged approach

**Prong 1: Manual step -- remove the system binary (requires sudo, one-time)**

The user must run ONE command with sudo to remove the stale system package:

```bash
sudo npm uninstall -g agent-browser
```

This removes `/usr/bin/agent-browser` and `/usr/lib/node_modules/agent-browser/`. After this, `which agent-browser` resolves to `~/.local/bin/agent-browser` (0.22.3).

**Prong 2: Add a version guard to `check_deps.sh` and skill entry points**

Even after removing the system binary, future installs could recreate it. Add a version check that catches mismatches early:

```bash
# Version guard: agent-browser must be 0.21.x+ (Chrome for Testing, no Playwright dependency)
AB_VERSION=$(agent-browser --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
if [[ -n "$AB_VERSION" ]]; then
  AB_MAJOR=$(echo "$AB_VERSION" | cut -d. -f1)
  AB_MINOR=$(echo "$AB_VERSION" | cut -d. -f2)
  if [[ "$AB_MAJOR" -eq 0 && "$AB_MINOR" -lt 21 ]]; then
    echo "  [ERROR] agent-browser $AB_VERSION is too old (uses Playwright, causes version mismatch)"
    echo "  Required: >= 0.21.1 (uses Chrome for Testing)"
    echo "  Fix: sudo npm uninstall -g agent-browser && npm install --prefix ~/.local -g agent-browser@0.22.3 && agent-browser install"
    exit 1
  fi
fi
```

**Prong 3: Update SKILL.md install instructions to use `--prefix ~/.local`**

All install references should use `npm install --prefix ~/.local -g agent-browser@0.22.3` instead of `npm install -g agent-browser@0.22.3`, since the latter requires sudo on systems where the npm prefix is `/usr`.

Additionally, add a "Troubleshooting" section to the agent-browser SKILL.md that documents the PATH shadowing issue and how to resolve it.

## Technical Considerations

### Why not just fix PATH?

Adding `~/.local/bin` to the front of PATH in `.bashrc` (already done at line 166) should work for interactive shells. But:

- Non-interactive shells (Bash tool) may not source `.bashrc`
- The `.profile` adds `~/.local/bin:$PATH` at line 27, but `.bash_profile` may override this
- PATH construction is spread across `.profile`, `.bash_profile`, `.bashrc`, and system files -- fragile to maintain

The most reliable fix is to remove the stale system binary entirely (Prong 1), with the version guard (Prong 2) as defense-in-depth.

### Files to modify

1. **`plugins/soleur/skills/agent-browser/SKILL.md`** -- Update install instructions to use `--prefix ~/.local`, bump version to 0.22.3, add troubleshooting section
2. **`plugins/soleur/skills/feature-video/scripts/check_deps.sh`** -- Add version guard for agent-browser >= 0.21.1, update install message to use `--prefix ~/.local` and 0.22.3
3. **`plugins/soleur/skills/test-browser/SKILL.md`** -- Update install instructions to use `--prefix ~/.local` and 0.22.3
4. **`plugins/soleur/README.md`** (line 312) -- Update Browser Automation section install instruction to use `--prefix ~/.local` and 0.22.3
5. **`knowledge-base/project/learnings/2026-03-20-npm-global-install-without-sudo.md`** -- Update with the full PATH shadowing resolution pattern

### Research Insights

**Version discovery (npm registry, 2026-03-26):**

- agent-browser@0.22.3 is the latest version (0.21.4 is 5 releases behind)
- 0.22.3 has zero npm dependencies (same Rust native architecture as 0.21.1+)
- Still uses Chrome for Testing, `agent-browser install` still required
- `postinstall` script (`node scripts/postinstall.js`) still present -- runs during `npm install -g`
- Package size: ~51 MB (consistent with 0.21.4)

**Install reference audit (comprehensive grep):**

Five files contain `npm install -g agent-browser` without `--prefix ~/.local`:

| File | Line | Current |
|------|------|---------|
| `plugins/soleur/skills/agent-browser/SKILL.md` | 14, 20 | `npm install -g agent-browser@0.21.4` |
| `plugins/soleur/skills/test-browser/SKILL.md` | 47, 60 | `npm install -g agent-browser@0.21.4` |
| `plugins/soleur/skills/feature-video/scripts/check_deps.sh` | 218 | `npm install -g agent-browser@0.21.4` |
| `plugins/soleur/README.md` | 312 | `npm install -g agent-browser@0.21.4` |
| Previous plans (knowledge-base/) | multiple | Various references (informational only, no fix needed) |

All four non-plan files must be updated. The previous March 20 plan missed README.md entirely.

**Version guard robustness:**

The version guard script uses `agent-browser --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'`. Verified output format: `agent-browser 0.21.4` -- the grep correctly extracts `0.21.4`. If the output format ever changes (unlikely for a Rust CLI), the guard falls through silently (no false rejection).

### What does NOT need changing

- **Playwright MCP configuration** -- completely independent, unaffected
- **ops-provisioner.md / ops-research.md** -- these use Playwright MCP as default, agent-browser is a fallback
- **constitution.md** -- browser hierarchy rules are already correct
- **CLI API compatibility** -- all core commands are unchanged between 0.21.4 and 0.22.3; `--session` to `--session-name` rename was already applied in the March 20 plan

### Existing learnings that apply

1. `2026-03-20-playwright-shared-cache-version-coupling.md` -- Documents the shared cache problem; agent-browser@0.22.3 eliminates it
2. `2026-03-20-npm-global-install-without-sudo.md` -- Documents `--prefix ~/.local` workaround; needs update about PATH shadowing
3. `2026-03-19-npm-global-install-version-pinning.md` -- Pin to specific version, not `@latest`
4. `2026-02-13-agent-prompt-sharp-edges-only.md` -- Troubleshooting section should document sharp edges only

## Acceptance Criteria

- [ ] System binary at `/usr/bin/agent-browser` removed (manual step: `sudo npm uninstall -g agent-browser`)
- [ ] `which agent-browser` resolves to `~/.local/bin/agent-browser` (version 0.22.3)
- [ ] `agent-browser open https://example.com` succeeds without version mismatch error
- [ ] `agent-browser snapshot -i` returns element refs in `@e1` format
- [x] `check_deps.sh` includes version guard rejecting agent-browser < 0.21.1
- [x] agent-browser SKILL.md install instructions use `npm install --prefix ~/.local -g agent-browser@0.22.3`
- [x] agent-browser SKILL.md includes troubleshooting section for PATH shadowing
- [x] test-browser SKILL.md install instructions use `npm install --prefix ~/.local -g agent-browser@0.22.3`
- [x] README.md Browser Automation section uses `npm install --prefix ~/.local -g agent-browser@0.22.3`
- [x] npm-global-install-without-sudo learning updated with PATH shadowing resolution
- [ ] Playwright MCP tools continue working independently

## Test Scenarios

- Given the system binary at `/usr/bin/agent-browser` is removed, when running `which agent-browser`, then it resolves to `~/.local/bin/agent-browser`
- Given agent-browser@0.22.3 is at `~/.local/bin`, when running `agent-browser --version`, then it returns `agent-browser 0.22.3`
- Given agent-browser@0.22.3 is correctly resolved, when running `agent-browser open https://example.com`, then it opens without a Playwright version mismatch error
- Given `check_deps.sh` has the version guard, when agent-browser@0.5.0 is in PATH, then the script exits with an error message explaining the version requirement
- Given `check_deps.sh` has the version guard, when agent-browser@0.22.3 is in PATH, then the script reports `[ok] agent-browser`
- Given Playwright MCP is configured, when running `browser_navigate` via MCP, then it works independently of agent-browser
- Given a fresh shell session (non-interactive), when running `agent-browser --version`, then it returns 0.22.3 (not 0.5.0)

## Non-goals

- Changing the browser interaction hierarchy (Playwright MCP > agent-browser > manual)
- Modifying Playwright MCP plugin configuration
- Pinning the Playwright MCP version
- Installing a different version of agent-browser (0.22.3 is current and correct)
- Fixing PATH ordering in `.bashrc` / `.profile` (fragile; removing the stale binary is more reliable)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling fix for a developer dependency.

## MVP

### Phase 1: Remove stale system binary (manual -- requires sudo)

The user must run this once:

```bash
sudo npm uninstall -g agent-browser
# Verify:
which agent-browser  # Should now resolve to ~/.local/bin/agent-browser
agent-browser --version  # Should show 0.22.3
```

If `~/.local/bin/agent-browser` does not exist or is not 0.22.3:

```bash
npm install --prefix ~/.local -g agent-browser@0.22.3
agent-browser install  # Downloads Chrome for Testing
```

### Phase 2: Add version guard to check_deps.sh

Update `plugins/soleur/skills/feature-video/scripts/check_deps.sh` agent-browser check (currently lines 214-223):

```bash
# Hard dependency -- cannot record without this
if command -v agent-browser >/dev/null 2>&1; then
  # Version guard: must be 0.21.x+ (Chrome for Testing, no Playwright dep)
  AB_VERSION=$(agent-browser --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ -n "$AB_VERSION" ]]; then
    AB_MAJOR=$(echo "$AB_VERSION" | cut -d. -f1)
    AB_MINOR=$(echo "$AB_VERSION" | cut -d. -f2)
    if [[ "$AB_MAJOR" -eq 0 && "$AB_MINOR" -lt 21 ]]; then
      echo "  [ERROR] agent-browser $AB_VERSION is too old (pre-0.21 uses Playwright, causes version mismatch)"
      echo "    Required: >= 0.21.1 (uses Chrome for Testing, no shared Playwright cache)"
      echo "    Fix: sudo npm uninstall -g agent-browser && npm install --prefix ~/.local -g agent-browser@0.22.3 && agent-browser install"
      exit 1
    fi
  fi
  echo "  [ok] agent-browser ($AB_VERSION)"
else
  echo "  [MISSING] agent-browser (required)"
  echo "    Install: npm install --prefix ~/.local -g agent-browser@0.22.3 && agent-browser install"
  echo "    On Linux: agent-browser install --with-deps (if system deps missing)"
  echo
  echo "Cannot proceed without agent-browser."
  exit 1
fi
```

### Phase 3: Update SKILL.md install instructions

**agent-browser SKILL.md** -- update install section and add troubleshooting:

````markdown
### Install if needed

```bash
npm install --prefix ~/.local -g agent-browser@0.22.3
agent-browser install  # Downloads Chrome for Testing (~300MB)
# On Linux if system deps missing:
# agent-browser install --with-deps
```

### Troubleshooting: version mismatch

If you see "Version mismatch between agent-browser (expects 1200) and installed Playwright (1208)":

1. Check which binary is running: `which agent-browser && agent-browser --version`
2. If it resolves to `/usr/bin/agent-browser` (version 0.5.0), a stale system install is shadowing the correct version
3. Fix: `sudo npm uninstall -g agent-browser` to remove the system binary
4. Verify: `which agent-browser` should now resolve to `~/.local/bin/agent-browser` (0.22.3)
````

**test-browser SKILL.md** -- update install section:

````markdown
**Install if needed:**

```bash
npm install --prefix ~/.local -g agent-browser@0.22.3
agent-browser install  # Downloads Chrome for Testing (~300MB)
```
````

Also update the auto-install fallback in the verification step:

````markdown
```bash
command -v agent-browser >/dev/null 2>&1 && echo "Ready" || (echo "Installing..." && npm install --prefix ~/.local -g agent-browser@0.22.3 && agent-browser install)
```
````

**README.md** -- update Browser Automation section:

````markdown
```bash
npm install --prefix ~/.local -g agent-browser@0.22.3
agent-browser install  # Downloads Chrome for Testing
```
````

### Phase 4: Update learning

Update `knowledge-base/project/learnings/2026-03-20-npm-global-install-without-sudo.md` to add the PATH shadowing resolution:

Add to Key Insight section:

```markdown
5. Even after installing to `~/.local`, the old system binary may shadow the new one in non-interactive shells where PATH puts `/usr/bin` first
6. The most reliable fix is to remove the stale system binary with `sudo npm uninstall -g <package>`, then verify with `which <tool>`
7. Add version guards in dependency check scripts as defense-in-depth -- catch the wrong binary at runtime rather than relying on PATH ordering
```

### Phase 5: Verification

```bash
# Verify system binary is gone
which agent-browser  # Should be ~/.local/bin/agent-browser
agent-browser --version  # Should be 0.22.3

# Verify no version mismatch
agent-browser open https://example.com
agent-browser snapshot -i
agent-browser close

# Verify Playwright MCP still works independently
# (use browser_navigate MCP tool)

# Verify check_deps.sh catches old versions
# (mock test -- temporarily alias agent-browser to echo "0.5.0")
```

## References

- `knowledge-base/project/plans/2026-03-20-fix-playwright-version-mismatch-agent-browser-plan.md` -- Previous plan (correct diagnosis, incomplete fix)
- `knowledge-base/project/learnings/2026-03-20-npm-global-install-without-sudo.md` -- `--prefix ~/.local` workaround
- `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md` -- Shared cache coupling problem
- `plugins/soleur/skills/agent-browser/SKILL.md` -- Agent-browser skill documentation
- `plugins/soleur/skills/test-browser/SKILL.md` -- Test-browser skill documentation
- `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- Dependency check script
- `plugins/soleur/README.md` -- Browser Automation section install instruction
