# shellcheck shell=bash
# Shared canonical projection for CI Required ruleset required_status_checks.
#
# Used by:
#   - scripts/audit-ruleset-bypass.sh (when extended for required_status_checks audit)
#   - scripts/update-ci-required-ruleset.sh (post-PUT verification fast-path)
#   - scripts/create-ci-required-ruleset.sh (canonical source for first apply)
#   - scripts/verify-ruleset-required-checks.sh (the pre-apply by-value gate, #9362; both canonicals)
#
# Why a projection BEFORE sort_by:
#   - `map({context, integration_id})` materializes only the two contractual
#     fields, dropping any GitHub-API-added metadata that might appear in
#     future responses (silent-drift defense).
#   - `sort_by(.context)` gives deterministic order — GitHub returns the
#     array in insertion order which is not contractual.
#
# integration_id is preserved PER ROW, never collapsed to a constant: a hand-edit
# that flattens a differently-bound row would let `github-actions[bot]` (15368)
# silently spoof a gate bound to another app via a synthetic check-run.
# CodeQL is no longer a required context anywhere (#9454: the merge queue is
# adopted and CodeQL cannot report on `merge_group`, so CodeQL is ADVISORY — the
# canonical JSON is all-15368 today). The per-row rule is kept for the day a
# GHAS-bound row (CodeQL, 57789) is re-tightened (codeql-1537-revisit-watch.yml).
# See #3545 audit-bot-codeql-coverage.sh for the runtime defense.
#
# Ref #3547.

# shellcheck disable=SC2034 # consumed by sourcing scripts via this variable
CANONICALIZE_REQUIRED_STATUS_CHECKS_JQ='map({context, integration_id}) | sort_by(.context)'
