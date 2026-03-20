# Feature Request: `pluginDirs` setting in settings.json (equivalent of `--plugin-dir`)

**Repository:** https://github.com/anthropics/claude-code

## Problem

The `--plugin-dir` CLI flag allows loading plugins from local directories for the current session. However, there is no `settings.json` equivalent. This creates a gap for teams and projects that need automatic plugin loading without the marketplace install flow.

The specific use case: a repository that IS a plugin (or contains a plugin) cannot reliably auto-load its own plugin in headless/remote environments (Claude Code on the web). The current workarounds all have timing issues:

1. **`extraKnownMarketplaces` + `enabledPlugins`**: Requires the trust dialog to trigger auto-installation. In headless mode, the trust dialog is skipped, so plugins are never auto-installed.
2. **SessionStart hook with `claude plugin install`**: The hook runs AFTER the plugin registry is built, so the installed plugin isn't available until the next session.
3. **Container caching**: Works for session 2+ but breaks during active development when the container cache is invalidated by code changes.

## Proposed Solution

Add a `pluginDirs` key to `settings.json` that loads plugins from local directories at startup, before the skill registry is built:

```json
{
  "pluginDirs": [
    "./plugins/soleur"
  ]
}
```

This would behave identically to `--plugin-dir` but be configured declaratively in the project settings, making it work across all environments (interactive, headless, web).

### Scoping

The setting should work at all scopes:
- **Project scope** (`.claude/settings.json`): Load plugins for all collaborators
- **Local scope** (`.claude/settings.local.json`): Load plugins for the current user only
- **User scope** (`~/.claude/settings.json`): Load plugins across all projects

### Security

Since `--plugin-dir` already exists as a CLI flag, the security model is established. The settings.json version would follow the same trust model as `extraKnownMarketplaces` — the user trusts the project directory when they clone and open it.

## Alternatives Considered

- **`extraKnownMarketplaces` with directory source**: Already exists but doesn't auto-install in headless mode
- **SessionStart hooks**: Run too late in the lifecycle
- **Pre-populating `~/.claude/plugins/installed_plugins.json`**: Fragile, depends on internal cache structure
- **Environment variable `CLAUDE_PLUGIN_DIRS`**: Would also solve the problem but less discoverable than a settings key

## Environment

- Claude Code version: 2.1.56
- Affected mode: Claude Code on the web (headless/remote)
- Also useful for: CI/CD, GitHub Actions, any headless deployment
