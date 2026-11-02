# Plan: Bundle Soleur plugin into a marketplace plugin for OpenCode

## Problem Statement
User wants to bundle Soleur plugin into a marketplace plugin for OpenCode so installation is easier.

## Approach
Create an npm package (`@soleur/opencode`) that bundles the complete Soleur OpenCode plugin and provides a simple install command. This matches how other OpenCode plugins are distributed (npm packages added to config, or standalone installable packages like oh-my-opencode).

## Implementation

### Phase 1: Create npm package structure
- Create `packages/opencode-plugin/` directory with package.json
- Package will contain all OpenCode adapter files (plugin.ts, skills, agents, commands, hooks, lib)
- Include bin script for installation (`soleur-opencode install`)
- Copy necessary setup scripts (install-opencode-adapter, sync-opencode-adapter)

### Phase 2: Package setup
- Write package.json for `@soleur/opencode` with proper metadata
- Create CLI bin that wraps the installer
- Copy all required files from `plugins/soleur/opencode/` and related directories
- Create README with installation instructions

### Phase 3: Adapt installer for npm package context
- Installer needs to work when run from node_modules - paths resolve relative to package root
- Modify install script to accept package root as base

### Phase 4: Documentation
- Update docs to show `npx @soleur/opencode install` as recommended method
- Keep existing install method as alternative for development

## Deliverables
- `packages/opencode-plugin/` with complete distributable package
- npm-ready package that users can install via `npx @soleur/opencode install`
- Backward compatibility with existing installation method

## Acceptance Criteria
- Package can be built/published
- `npx @soleur/opencode install` works to set up config
- All skills, agents, commands properly installed
- No breaking changes to existing setup
