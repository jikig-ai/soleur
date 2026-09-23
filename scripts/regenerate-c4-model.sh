#!/usr/bin/env bash
# regenerate-c4-model.sh — this repo's entry point for rendering model.likec4.json.
#
# Usage: bash scripts/regenerate-c4-model.sh [--out PATH] [--help]
#
# A WRAPPER, not a second renderer. The renderer moved into the plugin as
# plugins/soleur/scripts/render-c4-model.sh so a self-hosted install has one (ADR-235
# amendment). This path stays because lefthook's c4-model-regenerate hook, the docs and
# operator muscle memory call it. It is NOT an arm of the merge resolver: the resolver
# runs the renderer beside itself and never reads this file.
#
# The root is this file's own repository, as before the move — not the caller's CWD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
exec bash "$REPO_ROOT/plugins/soleur/scripts/render-c4-model.sh" --root "$REPO_ROOT" "$@"
