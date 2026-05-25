# Destroy-guard counter for apply-github-infra.yml. Path-specific to the
# only nested-block surface that has shipped destructively in this repo:
# `github_repository_ruleset.*.rules[].required_status_checks[].required_check[]`
# (PR #4395 shape; closes #3915). Sibling apply workflows are tracked as a
# follow-up — do NOT generalize this filter without re-running plan review.
#
# Input: `terraform show -json <plan>` document.
# Output: {resource_deletes: int, nested_deletes: int}. Caller sums to
#         destroy_count, then runs the [ack-destroy] gate.
#
# Design notes (from plan v2 — Kieran's plan-review iteration):
# - `$side` is a value-arg (jq 1.7+, safe on 1.8.x). NOT a filter-arg of
#   the `(before; after)` shape that re-evaluates on the inner string key
#   during recursion — that was the v1 P0-1 crash.
# - No recursion. v1's `walk()` shape returned 0 on equal-length parent
#   arrays (P0-2). Path-specific filter dissolves both bugs.
# - `select(.change.actions? | index("delete") | not)` excludes resources
#   the resource-level count already caught, so a hypothetical
#   ruleset-delete-with-nested-shrink can't double-count.
# - `select(. > 0)` drops additions and reorders; we only count shrinkage.

def required_check_count($side):
  ($side // {}) | [.rules[]?.required_status_checks[]?.required_check[]?] | length;

{
  resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
  nested_deletes:   ([.resource_changes[]?
                      | select(.type == "github_repository_ruleset")
                      | select(.change.actions? | index("delete") | not)
                      | (required_check_count(.change.before) - required_check_count(.change.after))
                      | select(. > 0)
                     ] | add // 0)
}
