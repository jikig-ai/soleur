#!/usr/bin/env bash
# tenant-integration-gate-verdict.sh — fail-closed verdict for the
# `tenant-integration-required` aggregator gate job (#5585).
#
# Usage: tenant-integration-gate-verdict.sh <detect_changes_result> <tenant_integration_result>
#   where each arg is a GitHub Actions `needs.<job>.result`
#   (success | failure | cancelled | skipped | "").
#
# Exit 0 (gate SUCCESS) iff BOTH:
#   - detect-changes succeeded (the path-detection that decides whether to
#     run the heavy suite actually ran), AND
#   - the heavy tenant-integration job is `success` (relevant PR, suite green)
#     OR `skipped` (unrelated PR — detect-changes emitted tenant=false).
# Exit 1 (gate FAILURE) for everything else. This is an ALLOW-LIST: any
# unenumerated state — detect-changes failure/cancelled/skipped/empty
# (the DROP-1 fail-open class), suite failure/cancelled/empty, or a future
# GitHub-added result string — fails closed.
#
# Lives in a script (not inline in the workflow) so the five-branch verdict
# is unit-tested by tests/scripts/test-tenant-integration-gate-verdict.sh.
set -uo pipefail

detect="${1:-}"
suite="${2:-}"

if [[ "$detect" == "success" && ( "$suite" == "success" || "$suite" == "skipped" ) ]]; then
  echo "tenant-integration gate: PASS (detect-changes=$detect, tenant-integration=$suite)"
  exit 0
fi

echo "::error::tenant-integration gate FAILED closed (detect-changes=${detect:-<empty>}, tenant-integration=${suite:-<empty>}). The required check passes only when detect-changes succeeds AND the suite is success or skipped." >&2
exit 1
