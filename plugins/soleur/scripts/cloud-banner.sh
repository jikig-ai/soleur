#!/usr/bin/env bash
# Emit the Soleur Cloud Mode capability banner for a detected non-local Devin
# session. Stateless — safe to invoke once per pipeline stage; the disclosure
# must be unmissable rather than deduplicated.
#
# Thin wrapper over the canonical classifier so callers never re-implement
# detection (see devin/INSTRUCTIONS.md §Cloud Mode). Prints nothing and exits 0
# on a `local` classification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/cloud-detect.sh" --banner
