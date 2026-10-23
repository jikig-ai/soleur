---
name: feat-opencode-marketplace-plugin
status: completed
issue: 10723
lane: cross-domain
epic: 10591
created: 2026-10-20
last_reviewed: 2026-10-23
updated: 2026-10-23
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Spec: Bundle Soleur plugin into a marketplace plugin for OpenCode

## Problem Statement

"is there anyway to bundle Soleur plugin into a marketplace plugin for opencode so the installation is easier for users?"

The user is asking if we can make installation easier for OpenCode users by packaging as a marketplace plugin.

## Current State

- Soleur has OpenCode adapter at `plugins/soleur/opencode/` (INSTRUCTIONS.md, opencode.json, plugin.ts, agents/, commands/)
- Installation requires running `bun plugins/soleur/scripts/install-opencode-adapter.ts` which merges into `~/.config/opencode/opencode.json` and copies files
- For other platforms (Claude Code, Cursor, etc.) there are marketplace.json files in `.claude-plugin/`, `.cursor-plugin/`, `.agents/plugins/`

## Goal

Explore how to bundle Soleur as a marketplace plugin for OpenCode to simplify installation.

## Known Approaches

Need to understand OpenCode's plugin distribution model (v2). Key questions:
1. Does OpenCode have a marketplace/registry? If so, what format?
2. Can plugins be installed via `opencode install <plugin>` or similar?
3. What is the expected plugin package format for OpenCode?
4. How do other OpenCode plugins get distributed?

## Research Needed

- Understand OpenCode v2 plugin packaging/distribution
- Compare with existing platform marketplace manifests
- Identify what's needed to make it "one-click" installable

## Acceptance Criteria

- Document viable approaches for packaging Soleur for OpenCode marketplace
- Recommend best approach with implementation plan
- Consider backward compatibility and maintenance

## User-Brand Impact

**Artifact:** OpenCode plugin installation experience
**Vector:** Poor installation UX creates friction; failed installs could cause confusion
**Threshold:** single-user incident

## Current OpenCode Plugin Model

From OpenCode docs:
- Local plugins: files in `.opencode/plugins/` or `~/.config/opencode/plugins/` (auto-loaded)
- npm plugins: add package names to `opencode.json` under `"plugin": [...]` - npm packages installed automatically via Bun at startup
- Plugins export default with `id` and `setup()` function
- Soleur's OpenCode plugin: `plugins/soleur/opencode/plugin.ts` exports default with id "soleur"

## Analysis

OpenCode doesn't have a centralized marketplace like Claude Code's official marketplace. Instead:
1. Users install npm-distributed plugins by adding them to their config
2. Or they copy local plugin files

So "bundle into a marketplace plugin for opencode" likely means making it distributable as an npm package that users can add via config, rather than requiring the manual install-adapter script.

Current install flow for OpenCode (from go.md line 584 and INSTRUCTIONS): users run `bun "${CLAUDE_PLUGIN_ROOT}/scripts/install-opencode-adapter.ts"` to merge config, copy agents/commands, install plugin module with resolved paths.

This is more involved than just adding `"plugin": ["soleur-opencode"]` to config. The complexity comes from:
- Need to set up skills/agents/commands in the right locations
- Path resolution via token replacement
- Config merging

Options:
1. Publish as npm package `@soleur/opencode` (or `soleur-opencode`) that, when installed as a plugin, sets up everything. But how? The plugin's setup() runs, but skills/agents/commands registration works differently in OpenCode - they're registered via opencode.json config (skills/instructions arrays) and file locations.
2. Restructure so the npm package contains all necessary files and provides a post-install script or the plugin itself handles setup
3. Create a proper distributable that works with OpenCode's npm plugin mechanism

But looking at how OpenCode loads plugins - npm plugins are loaded from node_modules. The skills/instructions paths in opencode.json need to point to actual directories. Also agents/commands in OpenCode are discovered from specific locations? Let us look up how agents/commands are registered in OpenCode config.

From the INSTRUCTIONS.md we see: "Skills register from the canonical tree through the `skills` config key" - so opencode.json needs `"skills": ["/path/to/skills"]`. "Commands register from the config directory's `commands/`" and the installer copies them.

So for an npm package, the paths would be inside node_modules. That could work if structured properly.

## Recommendations

1. Create an npm package (e.g., `@soleur/opencode-plugin` or `soleur-opencode`) that bundles the full Soleur plugin for OpenCode
2. The package should include all necessary files (plugin.ts, skills/, agents/, commands/, INSTRUCTIONS.md)
3. Provide clear install instructions: add to opencode.json `"plugin": ["soleur-opencode"]` and also potentially run setup, or have the plugin auto-configure
4. Consider whether we need a companion setup script or if we can make it work purely as an npm plugin

But OpenCode's npm plugin loading - when you specify an npm package, does it just load the module? Or does it look for certain files? Let us look up the plugin loading more. From docs: "Specify npm packages in your config file. ... Both regular and scoped npm packages are supported. Browse available plugins in the ecosystem."

Also from the ecosystem, plugins like `opencode-helicone-session` export a default plugin. They don't necessarily set up skills/agents/commands - those might be for other plugin systems.

Soleur's OpenCode integration is more comprehensive than simple plugins - it includes a whole agent/skill framework. That might require a different distribution approach.

Another approach: maintain both - keep the current install-adapter for flexibility, and also publish an npm package variant. Make the npm package self-contained with its own copy of all assets and provide setup instructions.

But we need to understand the full picture. Let us look up how others distribute complex plugins. For example, oh-my-opencode has many components.

## Option 1: Publish as npm package (standard OpenCode plugin distribution)
Create a package like `@soleur/opencode` or `opencode-soleur` that:
- Exports the plugin module (like `plugins/soleur/opencode/plugin.ts` but adapted for npm)
- Includes all skills/agents/commands/INSTRUCTIONS.md
- Users add `"plugin": ["@soleur/opencode"]` to their config
- Need to handle setup of paths - skills/agents/commands registration

But OpenCode's npm plugin mechanism just loads the plugin module. Skills/agents/commands registration still needs to be configured in opencode.json (skills array, instructions array) or placed in expected directories. The plugin module itself can't modify opencode.json directly from what I see.

Also the plugin runs in the context of OpenCode - it can hook into events, add tools, etc. But for full framework integration like Soleur provides, the file layout and config registration matter.

## Option 2: Create an opencode plugin that also does setup
The npm plugin could have a postinstall script or provide a CLI command to run setup. Similar to how oh-my-opencode works with `npx oh-my-opencode install`. But oh-my-opencode has bin scripts and does installation.

Or the plugin could on first run detect if not configured and prompt/setup. But modifying user config files from a plugin might be possible? Let us look up how the plugin context works.

## Option 3: Create a marketplace entry
But OpenCode doesn't seem to have a centralized marketplace like Claude Code. The ecosystem page lists plugins but doesn't show a marketplace.json format or install command from marketplace. So "marketplace plugin" terminology might mean different things across tools.

For Claude Code: marketplace.json defines a marketplace of plugins. For OpenCode, the concept seems different - plugins are npm packages or local files.

Maybe the question is asking to make it easier to install as a marketplace-style plugin (like how Claude Code does it)? Or to follow marketplace patterns?

Or perhaps create `.opencode-plugin/` or similar structure? Let us look up more. Also look at how oh-my-opencode structures things - they have `.opencode/command`, `.opencode/skills` in the package files array. Also they might install them.

Also looking back at oh-my-opencode's files array: it includes `.opencode/command`, `.opencode/skills`, `packages/omo-codex/marketplace.json` etc. Maybe they copy files to user config during install?

Also looking up the bin scripts and postinstall.

Alternatively, maybe the request is to create an OpenCode marketplace entry/manifest so users can add it via a marketplace mechanism similar to how other platforms do it. Let us look up if OpenCode has any marketplace concept - checking recent docs or common patterns.

Another possibility is creating a `.opencode/marketplace.json` or similar, or using OpenCode's plugin registry if it exists.

Or maybe bundle it as a "plugin" in the OpenCode sense that can be added to a marketplace catalog. Let us look up the full ecosystem more - "opencode-workspace" says "Bundled multi-agent orchestration harness – 16 components, one install" - similar to what Soleur does. How is it installed?
