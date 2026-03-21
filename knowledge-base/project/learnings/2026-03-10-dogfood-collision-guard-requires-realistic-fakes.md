# Learning: Evolus/pencil collision guard requires realistic fake binaries for testing

## Problem

When dogfooding the pencil-setup three-tier detection (#499), a naive fake `pencil` binary (simple `echo` script that outputs "Evolus Pencil 3.0" and exits 0 on all inputs) passed the collision guard unexpectedly. The `detect_pencil_cli()` function's second check (`pencil mcp-server --help`) succeeded because the fake binary exits 0 regardless of arguments.

## Solution

Create realistic fake binaries that reject unknown subcommands:

```bash
#!/bin/bash
case "$1" in
  --version) echo "Evolus Pencil 3.0" ;;
  *)         echo "Unknown command: $1" >&2; exit 1 ;;
esac
```

With this realistic fake, the collision guard works correctly: `--version` doesn't match "pencil.dev" or "pencil v" patterns, and `mcp-server --help` exits 1, so both checks fail and the collision warning is printed.

## Key Insight

When testing CLI tool detection that relies on subcommand probing (e.g., `tool subcommand --help`), naive fakes that exit 0 on all inputs bypass the detection logic. Always model the failure modes of the real tool being impersonated. A real evolus/pencil would error on `mcp-server` because that subcommand doesn't exist in their product.

## Tags

category: testing
module: pencil-setup
