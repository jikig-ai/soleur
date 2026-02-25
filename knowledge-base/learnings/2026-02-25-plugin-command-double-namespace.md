# Learning: Plugin command double-namespace and headless auto-load timing

## Problem

Commands in the Soleur Claude Code plugin appeared with double namespaces (`soleur:soleur:go` instead of `soleur:go`). Additionally, the plugin failed to auto-load on first session in headless/web environments, only succeeding on session 2+ via container caching.

## Root Cause

**Double namespace:** The plugin loader uses subdirectory names under `commands/` as part of the command namespace. Commands were at `commands/soleur/go.md`, so the resolved path `soleur/go` was prefixed with the plugin name `soleur:`, producing `soleur:soleur:go`. The official plugin spec expects commands flat in `commands/` (e.g., `commands/go.md`).

**First-session headless failure:** `extraKnownMarketplaces` + `enabledPlugins` requires the trust dialog to trigger auto-installation. In headless mode (Claude Code on the web), the trust dialog is skipped. SessionStart hooks run AFTER the plugin registry is built, so `claude plugin install` in the hook is too late for the current session.

## Solution

1. Moved `commands/soleur/*.md` to `commands/*.md` (flat structure)
2. Updated frontmatter `name` fields to remove `soleur:` prefix (plugin namespace auto-adds it)
3. Updated all internal path references (AGENTS.md, helpers.ts, stats.js, compound-capture, sync, help)
4. Documented timing behavior in SessionStart hook comments

## Three Failed Attempts

1. **Commit #307** (marketplace manifest): Marketplace registered but plugin not auto-installed
2. **Commit #308** (SessionStart hook): Plugin installed but too late -- registry already built
3. **Commit #309** (marketplace + enabledPlugins): Required trust dialog, skipped in headless mode

## Session Errors

- `Unknown skill: soleur:go` due to double-namespacing as `soleur:soleur:go`
- Plugin auto-load silently failed in headless mode (no error, just missing skills)
- Three prior commits each addressed a symptom without resolving the root cause

## Key Insight

Plugin commands must be flat in `commands/` -- subdirectories become part of the namespace. For headless environments, there is currently no way to auto-load plugins on first session. `--plugin-dir` has no settings.json equivalent (feature request filed). Container caching enables session 2+.

## Tags

category: plugin-system
module: soleur-plugin
