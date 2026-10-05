# shellcheck shell=bash
# Sourced plan-SHAPE gate for the inngest-host dispatch
# (apply_target=inngest-host in .github/workflows/apply-web-platform-infra.yml, #6894 / ADR-142).
#
# EXTRACTED + SOURCED (mirrors inngest-volume-recut-gate.sh / inngest-host-replace-gate.sh): both
# the workflow's inngest_host plan step AND tests/scripts/test-inngest-host-shape-gate.sh source
# this file and call inngest_host_shape_gate directly, so the CI decision logic is the SAME bytes
# the test exercises.
#
# WHAT THIS IS — a SHAPE gate, not a first-create gate. The inngest-host dispatch has several
# legitimate uses: a from-scratch build of the dedicated host, the ADR-142 additive create of the
# LUKS volume + attachment, a Doppler rotation, and a no-op re-run. So NO create is ever REQUIRED
# (an all-no-op plan passes, and so does an empty resource_changes array — nothing would be
# applied). What the gate refuses is every action outside the per-address permitted table below.
#
# ALLOW-SET = EXACTLY the inngest_host job's `-target=` addresses (derived from the workflow,
# not retyped; the battery and terraform-target-parity.test.ts both RED if the two drift apart).
# Every allow-set address belongs to EXACTLY ONE class; `allow_unpartitioned` aborts the gate if an
# address is in the allow-set with no class (it would be unconstrained) or in a class but not the
# allow-set.
#
# PER-ADDRESS PERMITTED ACTIONS (anything else at the address → the class's reason token):
#   hcloud_server.inngest                       no-op | create            → server_touched
#       (update covers the in-place server_type change, which reboots the sole scheduler; a
#        replace is the separately-gated inngest-host-replace dispatch)
#   hcloud_volume.inngest_redis                 no-op | create IFF the server is a create
#                                                                         → old_volume_touched
#   hcloud_volume_attachment.inngest_redis      no-op | create IFF the server is a create
#                                                                         → old_attachment_touched
#   hcloud_volume.inngest_redis_luks            no-op | create            → luks_volume_touched
#   hcloud_volume_attachment.inngest_redis_luks no-op | create            → luks_attachment_touched
#   hcloud_server_network.inngest               no-op | create            → network_touched
#   hcloud_firewall.inngest                     no-op | create            → firewall_touched
#       (an update is an ingress change on a host that takes no inbound traffic). The binding is
#       hcloud_server.inngest.firewall_ids (#8754); the old attachment's forget reds forget_present.
#   random_id.inngest_{signing,event}_key_dedicated, random_password.inngest_redis_password_dedicated
#                                               no-op | create            → generated_secret_touched
#   doppler_project.inngest, doppler_environment.inngest_prd, doppler_secret.*_dedicated,
#   doppler_secret.inngest_betterstack_logs_token, doppler_service_token.inngest
#                                               no-op | create | update   → doppler_touched
#       (rotations reach Doppler by design — inngest-host.tf's "TF owns these three values")
#
# "create IFF the server is a create": the live plaintext AOF volume and its attachment may only be
# born alongside a from-scratch host. A create of either while the server already exists means the
# volume left state — creating a fresh EMPTY volume at the address the host mounts as /mnt/data.
#
# GLOBAL:
#   luks_passphrase_in_graph — random_password.inngest_redis_luks / doppler_secret.inngest_redis_luks_key
#       must be ABSENT from resource_changes. ANY entry, a no-op included. They are per-merge
#       -targeted (the `apply` job) and nothing in this job's target set depends on them, so their
#       presence means the target set or the dependency graph changed under this gate.
#   forget_present   — any `forget` anywhere (a `removed{}`/`state rm` manifests as forget).
#   resource_deletes, nested_deletes — read from tests/scripts/lib/destroy-guard-filter-web-platform.jq,
#       the SAME filter the job's inline destroy-guard uses, so there is one definition of each.
#   out_of_scope     — any create/update/delete/forget at an address outside the allow-set.
#
# MEMBERSHIP IS EXACT EQUALITY, AND IT LIVES IN ONE PLACE (`is_addr`). `hcloud_volume.inngest_redis`
# is a PREFIX of `hcloud_volume.inngest_redis_luks`; containment would file the additive volume's
# create under the live volume's class. Every class and set lookup routes through `is_addr`.
#
# The positive-action filter excludes BOTH `no-op` AND `read`.
#
# NO [ack-destroy] BYPASS on this path.
#
# Usage:  source tests/scripts/lib/inngest-host-shape-gate.sh
#         inngest_host_shape_gate <plan-json-file>   # 0=PASS, 1=ABORT
#
# The ABORT line carries `reason=<token>` naming the FIRST failing counter in a fixed order.

# The shared destroy-guard filter is resolved from THIS file's directory at source time.
_IHSG_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_IHSG_FILTER="${_IHSG_LIBDIR}/destroy-guard-filter-web-platform.jq"

# THE FAIL-CLOSED PREAMBLE (#6997). Idempotent source.
# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  source "${_IHSG_LIBDIR}/plan-gate-preamble.sh"
fi

inngest_host_shape_gate() {
  local plan_json="$1"
  local counts dg rd nd reason t
  local -A c=()
  # Every counter, in REASON ORDER (most specific first; the catch-alls last).
  local -a order=(allow_unpartitioned luks_passphrase_in_graph old_volume_touched old_attachment_touched
    server_touched luks_volume_touched luks_attachment_touched firewall_touched network_touched
    generated_secret_touched doppler_touched forget_present resource_deletes nested_deletes out_of_scope)

  plan_gate_assert_readable     "inngest_host_shape_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "inngest_host_shape_gate" "$plan_json" || return 1

  if ! counts=$(jq -n --slurpfile p "$plan_json" '
      def allow: [
        "hcloud_server.inngest",
        "hcloud_volume.inngest_redis",
        "hcloud_volume_attachment.inngest_redis",
        "hcloud_volume.inngest_redis_luks",
        "hcloud_volume_attachment.inngest_redis_luks",
        "hcloud_server_network.inngest",
        "hcloud_firewall.inngest",
        "random_id.inngest_signing_key_dedicated",
        "random_id.inngest_event_key_dedicated",
        "random_password.inngest_redis_password_dedicated",
        "doppler_project.inngest",
        "doppler_environment.inngest_prd",
        "doppler_secret.inngest_signing_key_dedicated",
        "doppler_secret.inngest_event_key_dedicated",
        "doppler_secret.inngest_redis_password_dedicated",
        "doppler_secret.inngest_betterstack_logs_token",
        "doppler_service_token.inngest"
      ];
      def classes: [
        {r: "server_touched",           a: ["hcloud_server.inngest"],                       ok: [["no-op"], ["create"]],           with_server_create: false},
        {r: "old_volume_touched",       a: ["hcloud_volume.inngest_redis"],                 ok: [["no-op"]],                       with_server_create: true},
        {r: "old_attachment_touched",   a: ["hcloud_volume_attachment.inngest_redis"],      ok: [["no-op"]],                       with_server_create: true},
        {r: "luks_volume_touched",      a: ["hcloud_volume.inngest_redis_luks"],            ok: [["no-op"], ["create"]],           with_server_create: false},
        {r: "luks_attachment_touched",  a: ["hcloud_volume_attachment.inngest_redis_luks"], ok: [["no-op"], ["create"]],           with_server_create: false},
        {r: "network_touched",          a: ["hcloud_server_network.inngest"],               ok: [["no-op"], ["create"]],           with_server_create: false},
        {r: "firewall_touched",         a: ["hcloud_firewall.inngest"],                     ok: [["no-op"], ["create"]],           with_server_create: false},
        {r: "generated_secret_touched", a: ["random_id.inngest_signing_key_dedicated", "random_id.inngest_event_key_dedicated",
                                            "random_password.inngest_redis_password_dedicated"],
                                                                                            ok: [["no-op"], ["create"]],           with_server_create: false},
        {r: "doppler_touched",          a: ["doppler_project.inngest", "doppler_environment.inngest_prd",
                                            "doppler_secret.inngest_signing_key_dedicated", "doppler_secret.inngest_event_key_dedicated",
                                            "doppler_secret.inngest_redis_password_dedicated", "doppler_secret.inngest_betterstack_logs_token",
                                            "doppler_service_token.inngest"],
                                                                                            ok: [["no-op"], ["create"], ["update"]], with_server_create: false}
      ];
      def passphrase: ["random_password.inngest_redis_luks", "doppler_secret.inngest_redis_luks_key"];
      # THE ONE MEMBERSHIP PRIMITIVE. Exact string equality — see the header.
      def is_addr($a): (.address == $a);
      def in_set(s): (. as $e | any(s[]; . as $a | $e | is_addr($a)));
      def positive: (.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"));
      $p[0] as $plan
      | ([ $plan.resource_changes[]? | select(is_addr("hcloud_server.inngest")) | select(.change.actions == ["create"]) ] | length > 0) as $srv_create
      | (reduce classes[] as $c ({};
          .[$c.r] = ([ $plan.resource_changes[]?
                       | select(in_set($c.a))
                       | .change.actions as $acts
                       | select((any($c.ok[]; . == $acts) or ($c.with_server_create and $srv_create and $acts == ["create"])) | not) ]
                     | length)))
      + {
          allow_unpartitioned: (
            # Each allow-set address must sit in EXACTLY one class, and every class address must
            # be in the allow-set — otherwise an address is admitted with no per-address rule.
            ([ allow[] as $a | select(([ classes[] | select(any(.a[]; . == $a)) ] | length) != 1) ] | length)
            + ([ classes[].a[] as $x | select(({address: $x} | in_set(allow)) | not) ] | length)
          ),
          luks_passphrase_in_graph: (
            [ $plan.resource_changes[]? | select(in_set(passphrase)) ] | length
          ),
          forget_present: (
            [ $plan.resource_changes[]? | select(.change.actions? | index("forget")) ] | length
          ),
          out_of_scope: (
            [ $plan.resource_changes[]? | select(positive) | select(in_set(allow) | not) ] | length
          )
        }
    ' 2>/dev/null); then
    echo "inngest_host_shape_gate: ABORT reason=jq_failed — jq evaluation failed on ${plan_json}"
    return 1
  fi
  # resource_deletes / nested_deletes: the job's own destroy-guard filter, one definition.
  if ! dg=$(jq -f "$_IHSG_FILTER" "$plan_json" 2>/dev/null); then
    echo "inngest_host_shape_gate: ABORT reason=jq_failed — the destroy-guard filter (${_IHSG_FILTER}) failed on ${plan_json}"
    return 1
  fi
  rd=$(echo "$dg" | jq -r '.resource_deletes')
  nd=$(echo "$dg" | jq -r '.nested_deletes')

  for t in "${order[@]}"; do
    case "$t" in
      resource_deletes) c[$t]="$rd" ;;
      nested_deletes)   c[$t]="$nd" ;;
      *)                c[$t]=$(echo "$counts" | jq -r --arg k "$t" '.[$k]') ;;
    esac
  done

  # Every counter is a non-negative integer BEFORE any arithmetic compares one. A counter that did
  # not evaluate is "" (or "null" for a missing key), and [[ "" -eq 0 ]] is TRUE under bash
  # coercion — so an uncomputed counter would silently satisfy every threshold.
  local -a pairs=()
  for t in "${order[@]}"; do pairs+=("${t}=${c[$t]}"); done
  plan_gate_assert_numeric "inngest_host_shape_gate" "${pairs[@]}" || return 1

  echo "${pairs[*]}"

  reason=""
  for t in "${order[@]}"; do
    if [[ "${c[$t]}" -ne 0 ]]; then reason="$t"; break; fi
  done
  if [[ -z "$reason" ]]; then
    echo "inngest_host_shape_gate: PASS — every action is in the inngest-host permitted table (no touch on the live AOF volume/attachment or an existing server, no firewall/network/generated-secret update, the LUKS passphrase pair absent, no delete/forget, nothing out of scope)"
    return 0
  fi
  echo "inngest_host_shape_gate: ABORT reason=${reason} — plan is NOT an inngest-host shape (see the permitted table in tests/scripts/lib/inngest-host-shape-gate.sh: the live AOF volume/attachment may only be created alongside a from-scratch server; the server may only be created; firewall/network/generated secrets only created; Doppler never deleted; the LUKS passphrase pair must be absent; no delete, forget, nested-block removal or out-of-scope action)"
  return 1
}
