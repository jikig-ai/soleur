# shellcheck shell=bash
# Shared canonical projection for CI Required ruleset required_status_checks.
#
# Used by:
#   - scripts/audit-ruleset-bypass.sh (when extended for required_status_checks audit)
#   - scripts/update-ci-required-ruleset.sh (post-PUT verification fast-path)
#   - scripts/create-ci-required-ruleset.sh (canonical source for first apply)
#
# Why a projection BEFORE sort_by:
#   - `map({context, integration_id})` materializes only the two contractual
#     fields, dropping any GitHub-API-added metadata that might appear in
#     future responses (silent-drift defense).
#   - `sort_by(.context)` gives deterministic order — GitHub returns the
#     array in insertion order which is not contractual.
#
# Heterogeneous integration_id (15368 ×4, 57789 ×1) is INTENTIONALLY
# preserved per row. The CodeQL row is pinned to integration_id 57789
# (github-advanced-security app); a hand-edit that flattens this to a
# single constant would let `github-actions[bot]` (15368) silently spoof
# the CodeQL gate via a synthetic check-run. See #3545 audit-bot-codeql-
# coverage.sh for the runtime defense.
#
# Ref #3547.

# shellcheck disable=SC2034 # consumed by sourcing scripts via this variable
CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ='map({context, integration_id}) | sort_by(.context)'
