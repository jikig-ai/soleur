# shellcheck shell=bash
# Shared canonical projection for CI Required ruleset bypass_actors arrays.
#
# Used by scripts/audit-ruleset-bypass.sh (daily drift detection) and
# scripts/update-ci-required-ruleset.sh (post-PUT verification fast-path).
# Both consumers MUST canonicalize through this exact jq filter so a
# round-tripped null-vs-missing-key API response (GitHub's contract is
# unpinned on which form they emit) does not surface as a false drift.
#
# Why a projection BEFORE sort_by:
#   - GitHub may return `{"actor_type": "OrganizationAdmin", "bypass_mode":
#     "pull_request"}` (no actor_id key) OR
#     `{"actor_type": "OrganizationAdmin", "actor_id": null, "bypass_mode":
#     "pull_request"}` for the same logical state.
#   - `map({actor_type, actor_id, bypass_mode})` materializes missing
#     keys as `null`; both shapes collapse to identical canonical form.
#   - `sort_by(.actor_type, (.actor_id // "null" | tostring), .bypass_mode)`
#     yields a deterministic order regardless of API response sequencing.
#
# Number-vs-string actor_id (e.g., hand-edit accidentally quoting "5") is
# intentionally preserved as drift — that IS a real edit signal.
#
# Ref #3544.

# shellcheck disable=SC2034 # consumed by sourcing scripts via this variable
CANONICALIZE_BYPASS_ACTORS_JQ='map({actor_type, actor_id, bypass_mode}) | sort_by(.actor_type, (.actor_id // "null" | tostring), .bypass_mode)'
