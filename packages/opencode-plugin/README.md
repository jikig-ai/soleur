# @soleur/opencode

Soleur AI organization plugin for OpenCode - a full AI organization across engineering, finance, marketing, legal, operations, product, sales, and support.

## Installation

### Quick Install (Recommended)

```bash
npx @soleur/opencode install
```

Or with bun:
```bash
bunx @soleur/opencode install
```

This will automatically configure OpenCode with all Soleur agents, skills, commands, and hooks.

### Manual Installation

1. Add the plugin to your `opencode.json`:
```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@soleur/opencode"]
}
```

2. Run the setup script to configure agents, skills, and commands:
```bash
npx @soleur/opencode install
```

## Features

- 80+ specialized AI agents across 8 departments
- 200+ skills for workflows like brainstorming, planning, implementation, review
- Integrated hooks for safety and compliance
- Seamless integration with OpenCode

## Usage

After installation, use `/go` in OpenCode to get started with the unified entry point.

## Documentation

See [soleur.ai](https://soleur.ai) for full documentation.

## License

BUSL-1.1
