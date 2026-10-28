# shellcheck shell=bash
# Sourced plan gate for the git-data wipe wedge (tests/scripts/test-git-data-wipe-wedge.sh).
#
# Usage: git_data_wedge_gate <plan.json>   # 0=PASS, 1=REFUSE
#
# Refuses iff a `terraform show -json` plan would RE-WEDGE the retired plaintext
# store — the post-delete and detached-not-deleted shapes the destroy workflow
# (git-data-plaintext-volume-destroy.yml, ADR-239 Option B) exists to remove:
#
#   hcloud_volume.git_data             any entry whose actions contain "create"
#                                      (a wiped store being born empty again)
#   hcloud_volume_attachment.git_data  any entry whose actions are EXACTLY
#                                      ["create"] (reattaching a detached-but-
#                                      retained volume to a live host; a full
#                                      delete+create inside a scoped replace is
#                                      admissible drift, not the wedge)
#
# Every other entry — including a properly-scoped hcloud_server.git_data
# delete+create — is out of scope for this gate and PASSES: the wedge is the
# plaintext volume coming back, not the host being replaced.
#
# Callers MUST check the return code (`if ! git_data_wedge_gate …; then …`).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plan-gate-preamble.sh"

git_data_wedge_gate() {
  local plan_json="$1"

  plan_gate_assert_readable     "git_data_wedge_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "git_data_wedge_gate" "$plan_json" || return 1

  local counts
  if ! counts="$(jq -n --slurpfile p "$plan_json" '
    ($p[0].resource_changes // []) as $rcs |
    {
      vol_create: ([$rcs[] | select(.address == "hcloud_volume.git_data")
                    | select(.change.actions | index("create") != null)] | length),
      att_create: ([$rcs[] | select(.address == "hcloud_volume_attachment.git_data")
                    | select(.change.actions == ["create"])] | length)
    }' 2>/dev/null)"; then
    echo "git_data_wedge_gate: ABORT — counter computation failed (jq error). Fail-closed: an uncomputed counter is not a zero."
    return 1
  fi

  local vol_create att_create
  vol_create="$(jq -r '.vol_create' <<<"$counts")"
  att_create="$(jq -r '.att_create' <<<"$counts")"
  plan_gate_assert_numeric "git_data_wedge_gate" "vol_create=${vol_create}" "att_create=${att_create}" || return 1

  if [[ "$vol_create" -gt 0 || "$att_create" -gt 0 ]]; then
    echo "git_data_wedge_gate: REFUSE — plan re-creates the retired plaintext store (vol_create=${vol_create} att_create=${att_create}); the git-data wipe wedge must stay closed."
    return 1
  fi

  echo "git_data_wedge_gate: PASS — no plaintext-store re-create in plan."
  return 0
}
