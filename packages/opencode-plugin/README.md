# @soleur/opencode

Soleur AI organization plugin for [OpenCode](https://opencode.ai) — 67 specialized AI agents, 4 commands, and 103 workflow skills across engineering, finance, legal, marketing, operations, product, sales, and support.

## Installation

Requires [Bun](https://bun.sh) (`bun` on `PATH`).

```bash
npx @soleur/opencode install
```

Or with Bun directly:

```bash
bunx @soleur/opencode install
```

This vendors the Soleur payload into `~/.config/opencode/soleur/` and installs the OpenCode commands, agent stubs, hook module, and `opencode.json` entries into `~/.config/opencode/` (preserving your existing `opencode.json` keys). Because the payload is copied into `~/.config/opencode/soleur/`, the installation remains intact even after `npx` / `bunx` prunes its cache.

### Options

```bash
npx @soleur/opencode install --target /path/to/.opencode   # install into a custom config directory
npx @soleur/opencode install --check                       # verify the installation without writing
npx @soleur/opencode install --force                       # backup and replace an unparseable opencode.json
```

## Usage

Start a new OpenCode session and run:

- `/go <what you want to do>` — unified entry point that routes to the right workflow skill
- `/sync` — analyze your codebase and populate the knowledge base
- `/help` — list all available Soleur commands, agents, and skills

Skills are loaded with the `skill` tool by bare id (`plan`, `work`, `review`, `one-shot`, etc.).

## Documentation

Full documentation and OpenCode capability notes: [soleur.ai/getting-started](https://soleur.ai/getting-started/) and [OpenCode instructions](https://github.com/jikig-ai/soleur/blob/main/plugins/soleur/opencode/INSTRUCTIONS.md).

## License

BUSL-1.1
