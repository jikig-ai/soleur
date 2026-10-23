# Brainstorm: Bundle Soleur plugin into a marketplace plugin for OpenCode

## Problem
User asks: "is there anyway to bundle Soleur plugin into a marketplace plugin for opencode so the installation is easier for users?"

## Current State
- Soleur has OpenCode adapter at `plugins/soleur/opencode/` (plugin.ts, INSTRUCTIONS.md, opencode.json, agents/, commands/)
- Installation requires running `bun plugins/soleur/scripts/install-opencode-adapter.ts` which merges config into `~/.config/opencode/opencode.json`, copies agents/commands, resolves tokens
- For other platforms there are marketplace manifests (.claude-plugin/, .cursor-plugin/, .agents/plugins/)
- OpenCode v2 loads plugins from: local files in `.opencode/plugins/` or `~/.config/opencode/plugins/`, OR npm packages listed in `opencode.json` under `"plugin": [...]`

## Key Findings
- OpenCode doesn't have a centralized marketplace like Claude Code. Distribution is via npm packages added to config, or local files
- Example npm plugin: `opencode-helicone-session` - just exports default plugin module, users add `"plugin": ["opencode-helicone-session"]` to config
- Complex bundles like oh-my-opencode are published as npm packages with many files included
- Soleur's OpenCode integration needs: skills/agents/commands registered via opencode.json (skills/instructions arrays point to paths) and files in specific locations
- The current installer does token substitution (`__SOLEUR_PLUGIN_ROOT__` → actual path) because skills/instructions paths need absolute/resolved paths

## Options

### Option 1: Publish as npm package with auto-configuration
Create `@soleur/opencode` (or `soleur-opencode`) npm package containing:
- All Soleur OpenCode assets (plugin.ts, skills/, agents/, commands/, INSTRUCTIONS.md, full skills tree)
- Plugin module that can auto-configure on load? Or provide setup script
- But OpenCode plugin's setup() runs in context; can't easily modify user's opencode.json from within. Skills/agents/commands registration requires config entries.

Challenges:
- Skills/instructions paths in opencode.json need to point to where package is installed (node_modules location)
- Need to handle both global and project-level configs
- Token resolution is currently done by installer

### Option 2: Keep installer, improve UX with npx/one-liner
e.g. `npx @soleur/opencode-install` or `curl | bash` style. Easier to maintain, preserves existing logic.

### Option 3: Hybrid - npm package that bundles files + companion CLI
Package contains all files, and provides `soleur-opencode install` command that sets up config properly. Similar to oh-my-opencode pattern.

## Recommended Approach
Option 3 (hybrid) is cleanest:
1. Create an npm package `@soleur/opencode` that includes the full plugin distribution
2. Package includes: plugin module, all skills/, agents/, commands/, INSTRUCTIONS.md, scripts for setup
3. Add bin entry `soleur-opencode` that runs installer logic
4. Update docs: `npx @soleur/opencode@latest install` or `bunx @soleur/opencode install`
5. Keep backward compatible with current manual install

Also need to adapt the installer to work from node_modules location (resolve paths relative to package root).

## Next Steps
- Create package.json for the OpenCode distributable
- Structure files for npm publishing
- Adapt installer to work when installed via npm
- Test installation flow
