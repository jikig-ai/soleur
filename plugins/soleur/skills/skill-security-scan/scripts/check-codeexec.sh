#!/usr/bin/env bash
set -euo pipefail
# TODO Phase 2.1: semgrep --config code-exec.yaml + targeted regex for
# obfuscation signatures. Stdin = SKILL.md, stdout = JSON, exit 0 always.
echo '{"verdict":"LOW-RISK","findings":[],"category":"code-execution"}'
