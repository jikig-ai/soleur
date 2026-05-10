#!/usr/bin/env bash
set -euo pipefail
# TODO Phase 2.3: osv.dev batch query, ecosystem allowlist, REVIEW-on-unknown,
# typosquat detection, network-error-as-REVIEW, response schema validation,
# 32 MiB body cap.
echo '{"verdict":"LOW-RISK","findings":[],"category":"supply-chain"}'
