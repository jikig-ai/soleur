#!/usr/bin/env bash
# sentry-destroy-gate-verdict.sh — fail-closed verdict for the
# `sentry-destroy-required` aggregator gate job (#6589).
#
# Usage: sentry-destroy-gate-verdict.sh <detect_changes_result> <plan_pr_result>
#   where each arg is a GitHub Actions `needs.<job>.result`
#   (success | failure | cancelled | skipped | "").
#
# Exit 0 (gate SUCCESS) iff BOTH:
#   - detect-changes succeeded (the path detection that decides whether to run
#     the full-root plan actually ran), AND
#   - plan_pr is `success` (the PR touches infra/sentry/** and either destroys
#     nothing or carries a pre-staged [ack-destroy]) OR `skipped` (the PR does
#     not touch the Sentry surface, or this is a merge_group candidate whose
#     authoritative plan already ran pre-queue).
# Exit 1 (gate FAILURE) for everything else. This is an ALLOW-LIST: any
# unenumerated state — detect-changes failure/cancelled/skipped/empty, plan_pr
# failure/cancelled/empty, or a future GitHub-added result string — fails closed.
#
# WHY AN ALLOW-LIST AND NOT `!= 'failure'`. A deny-list greens on `cancelled`
# and on the empty string. The empty string is what a `needs` job reports when
# it never ran because an EARLIER job in its chain failed — so a deny-list would
# hand a green to exactly the case where the gate learned nothing. This gate's
# entire purpose is to refuse a destroy nobody acknowledged; a gate that greens
# when it did not run is worse than no gate, because it launders "unknown" into
# "approved".
#
# Lives in a script (not inline in the workflow) so the verdict's branches are
# unit-tested by tests/scripts/test-sentry-destroy-gate-verdict.sh. Mirrors
# scripts/tenant-integration-gate-verdict.sh (#5585) exactly.
set -uo pipefail

detect="${1:-}"
plan="${2:-}"

if [[ "$detect" == "success" && ( "$plan" == "success" || "$plan" == "skipped" ) ]]; then
  echo "sentry-destroy gate: PASS (detect-changes=$detect, plan_pr=$plan)"
  exit 0
fi

echo "::error::sentry-destroy gate FAILED closed (detect-changes=${detect:-<empty>}, plan_pr=${plan:-<empty>}). The required check passes only when detect-changes succeeds AND the full-root plan job is success or skipped. A destroy that nobody acknowledged must never reach main: see #6074, where a removed monitor block silently left the live monitor billing." >&2
exit 1
