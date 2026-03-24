# Learning: defaultMode lives inside permissions, not at top level

## Problem

When adding `defaultMode: "auto"` to `.claude/settings.json`, placing it at the top level causes a schema validation error: `Unrecognized field: defaultMode`. The Claude Code settings schema is strict about field placement.

## Solution

`defaultMode` is nested inside the `permissions` object, not at the root:

```json
{
  "permissions": {
    "defaultMode": "auto",
    "allow": [...]
  }
}
```

The schema shows `defaultMode` as a property of `permissions` with enum values: `acceptEdits`, `bypassPermissions`, `default`, `dontAsk`, `plan`, `auto`.

## Key Insight

Claude Code's settings schema groups permission-related fields (allow, deny, ask, defaultMode, disableBypassPermissionsMode, disableAutoMode, additionalDirectories) under the `permissions` key. The `autoMode` classifier config (environment, allow, soft_deny) is a separate top-level key. Don't confuse the two: `permissions.defaultMode` sets which mode is active, while `autoMode` configures the classifier's behavior when auto mode is active.

## Session Errors

1. **Placed defaultMode at top level instead of under permissions** — Recovery: Schema validator caught the error and showed the full schema. Read the schema to find the correct location. — Prevention: Always check field nesting in the Claude Code schema before editing settings.json. The `effortLevel` learning (2026-02-24) documents a similar pattern where a setting was placed at the wrong level.

2. **404 on docs URL** — `https://code.claude.com/docs/en/auto-mode` returned 404 after redirect from `docs.anthropic.com`. — Recovery: Fetched `/en/permissions` instead, which contained comprehensive auto mode documentation including the full `autoMode` configuration reference. — Prevention: When a specific docs page 404s, try the parent topic page (permissions, settings, etc.) which often contains the information in a combined reference.

## Tags

category: build-errors
module: claude-code-settings
