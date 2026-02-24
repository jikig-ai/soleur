# Learning: effortLevel is Not a Valid settings.json Field

## Problem

When trying to add `"effortLevel": "high"` as a top-level key in `.claude/settings.json`, the Claude Code settings validator rejected it with "Unrecognized field: effortLevel". The framework-docs-researcher agent had incorrectly reported that `effortLevel` works as a direct settings.json field.

## Solution

Use the `env` key to set the environment variable instead:

```json
{
  "env": {
    "CLAUDE_CODE_EFFORT_LEVEL": "high"
  }
}
```

The `env` key in settings.json sets environment variables for Claude Code sessions. `CLAUDE_CODE_EFFORT_LEVEL` is the correct environment variable name, accepting values: `low`, `medium`, `high` (default).

Other valid methods to control effort:
- `/model` command mid-session (effort slider with left/right arrows)
- `CLAUDE_CODE_EFFORT_LEVEL` env var before starting Claude

## Key Insight

The `.claude/settings.json` schema is strict -- it only accepts fields defined in the JSON Schema. `effortLevel` is not a recognized field despite being a valid Claude Code concept. Always verify settings fields against the actual schema validation, not against agent research claims. The `env` key is the correct escape hatch for environment-variable-based configuration.

## Session Errors

1. Settings.json schema validation failure on `effortLevel` field -- fixed by using `env.CLAUDE_CODE_EFFORT_LEVEL`

## Tags

category: configuration-fixes
module: claude-code-settings
