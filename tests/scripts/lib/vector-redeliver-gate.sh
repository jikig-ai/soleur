# shellcheck shell=bash
# Sourced plan gate for the vector-redeliver scoped delivery arm
# (apply_target=vector-redeliver in .github/workflows/apply-web-platform-infra.yml).
#
# EXTRACTED + SOURCED (mirrors inngest-host-replace-gate.sh): both the workflow's
# vector_redeliver gate step AND tests/scripts/test-vector-redeliver-gate.sh source this
# file and call vector_redeliver_gate directly, so the CI decision logic is the SAME bytes
# the test exercises (no re-derived inline copy to drift).
#
# WHAT THIS ARM IS FOR. `vector.toml` is hashed into the triggers_replace of
# terraform_data.journald_persistent (server.tf), so a Vector config change reaches the
# running web-1 ONLY by replacing that resource. Before this arm the sole route was the
# merge-triggered push apply, which grades the WHOLE plan at once — so a delivery that is
# by itself routine could not land while unrelated pending drift sat in the same plan.
# This arm gives the delivery its own dispatch, scoped to that single address.
#
# ── ASSEMBLY (why grading the plan is sound) ────────────────────────────────────────
# The gate quantifies over `.resource_changes[]` of the `terraform show -json` document
# produced by THIS job's own plan step — the complete set of resources Terraform intends to
# act on, not a list of addresses anyone enumerated. The chokepoint is single and
# structural: the job runs exactly one `terraform plan -out=tfplan`, and exactly one
# `terraform apply tfplan` consuming THAT SAVED PLAN FILE; the gate reads the same artifact
# between them. Because the apply consumes the saved plan rather than re-planning, no
# resource can enter the apply that was absent from the graded document — the gate's scope
# and the apply's scope are the same object, not two lists kept in sync.
#
# This is why the gate reads the PLAN and not the `-target` flags: `-target` is transitive
# and is a request, not a bound. The real closure of
# `-target=terraform_data.journald_persistent` is ~9 addresses (both hcloud_server.web
# entries, hcloud_ssh_key.default, hcloud_placement_group.web_spread, the CF tunnel +
# random_id.tunnel_secret, doppler_service_token.web_probes, hcloud_volume.workspaces[*],
# tls_private_key.ci_ssh). Which addresses appear is a fact about current state and drifts;
# the assembly — one plan artifact, graded whole, feeding one apply — does not.
#
# ── WHY A BARE ["create"] IS ADMITTED ───────────────────────────────────────────────
# A gate written to "exactly one REPLACE" refuses a bare create of the same address — and a
# bare create is the shape the plan takes when the resource is absent from state (a run
# that died between the destroy and the create: job timeout, cancellation). Refusing it
# would brick the recovery arm at exactly the moment it is needed — the "a gate that always
# fails is an outage, not a tripwire" shape the ci_ssh gate's own header records.
#
# A bare create is not a widening of blast radius: creating this resource runs exactly the
# create-time provisioners that deliver vector.toml and reload the agents — the intended
# work of this arm, precisely. So the gate asserts exactly one DELIVERY —
# sorted(actions) == ["create","delete"] OR ["create"] — counted as one.
#
# ── WHY THE `depends_on` EDGE WAS NOT REMOVED ───────────────────────────────────────
# hcloud_server.web["web-1"] lands in the target closure through a transitive dependency
# edge, not through a widened allow-list. Cutting that edge to shrink the closure would
# decouple the provisioner from the host it provisions — the resource legitimately depends
# on the server existing. Grading the whole plan is the right response to a wide closure;
# severing a real dependency to make a gate's job easier is not.
#
# ── UN-INDEXED ADDRESS ASSUMPTION ───────────────────────────────────────────────────
# The allow-set matches `terraform_data.journald_persistent` by EXACT EQUALITY. If that
# resource is ever moved under `for_each`/`count`, its address becomes
# `terraform_data.journald_persistent["web-1"]` and exact equality stops matching — the
# entry counter reads 0 for a BROKEN ALLOW-SET, not for a satisfied desired state. That is
# why the no-op branch below is gated on `journald_entries`, and why its message says "no
# entry matched the allow-set" rather than "state already matches": the reassuring sentence
# must never be the one printed for the alarming condition.
#
# ── FOUR COUNTERS, AND WHY THE FOURTH IS NOT THE ONE THAT WAS CUT ───────────────────
# The design cut a `nested_removals` counter as UNIMPLEMENTABLE for a terraform_data
# resource (it has no nested blocks to remove; the allow-set subsumes the guarantee). That
# cut stands. `journald_entries` is a DIFFERENT counter, and it is load-bearing:
#
#   A lone ["delete"] or ["forget"] at the allowed address scores journald_delivered==0.
#   host_destroyed is TYPE-scoped to hcloud_server/hcloud_volume so it does not see a
#   terraform_data, and out-of-scope EXCLUDES the allowed address by construction — so
#   with three counters, the single most destructive shape this arm can emit would have
#   been indistinguishable from "already delivered" and returned NO-OP SUCCESS.
#
# Separating "how many entries exist at the address" from "how many of them are deliveries"
# makes absence (no-op, benign) and destruction (abort, alarming) distinct states.
#
# ── NEGATIVE ACTION FILTER ──────────────────────────────────────────────────────────
# out-of-scope treats everything EXCEPT ["no-op"] and ["read"] as a change, rather than
# filtering positively on create/update/delete/forget. A positive filter silently admits
# any action verb Terraform adds later (ephemeral open/close, a future verb) at a
# non-allowed address. That matters more here than at the sibling gate: with host_destroyed
# subsumed and the nested counter cut, out-of-scope is the only live address boundary.
# It also closes the measured empty-actions hole — `[]` is neither ["no-op"] nor ["read"],
# so a hidden destroy carrying "actions": [] is COUNTED rather than invisible.
#
# NO [ack-destroy] BYPASS: this arm is authorized by the menu-ack workflow_dispatch
# (hr-menu-option-ack-not-prod-write-auth), never a commit trailer. The `[ack-destroy]`
# path is structurally unavailable on dispatch anyway — the push guard reads
# github.event.head_commit.message, which is empty on workflow_dispatch.
#
# OUTCOMES (rc=0 for both success shapes; the caller distinguishes via VECTOR_REDELIVER_OUTCOME):
#   PASS   — oos==0 && host_destroyed==0 && journald_entries==1 && journald_delivered==1
#   NO-OP  — oos==0 && host_destroyed==0 && journald_entries==0   (already realised)
#   ABORT  — anything else (rc=1)
#
# Usage:  source tests/scripts/lib/vector-redeliver-gate.sh
#         vector_redeliver_gate <plan-json-file>   # 0=PASS or NO-OP, 1=ABORT
#         # then read $VECTOR_REDELIVER_OUTCOME  (pass|noop) to decide whether to apply

# THE FAIL-CLOSED PREAMBLE (#6997). A gate that authorises a production apply must never
# let "I could not check" read as "it is fine". These assertions refuse a plan document the
# gate cannot READ, cannot CLASSIFY, or whose counters did not evaluate — the shapes that
# otherwise score zero-of-everything and PASS.
#
# The `declare -F` guard makes the source idempotent: the workflow step may have sourced
# the preamble already, in either order.
# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _VRG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_VRG_DIR}/plan-gate-preamble.sh"
fi

vector_redeliver_gate() {
  local plan_json="$1"
  local counts oos hdel entries delivered

  # Caller-visible outcome. Reset on EVERY invocation: a stale `pass` from a previous call
  # in the same shell must never be read as this call's verdict.
  VECTOR_REDELIVER_OUTCOME="abort"

  # THE ASSERTS LIVE INSIDE THE FUNCTION, AS ITS FIRST STATEMENTS, because they consume
  # $plan_json — a FUNCTION PARAMETER that does not exist at file scope.
  #
  # `|| return 1` also catches a 127 undefined-function status, so a preamble that failed
  # to source aborts the gate rather than silently skipping the check.
  plan_gate_assert_readable     "vector_redeliver_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "vector_redeliver_gate" "$plan_json" || return 1

  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`, which
  # would false-match `terraform_data.journald_persistent_v2` and
  # `module.staging.terraform_data.journald_persistent`. Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" '
      def allow: [ "terraform_data.journald_persistent" ];
      # A change is anything that is NOT purely no-op/read. Negative by design — see header.
      def is_change: (.change.actions? // []) as $a
        | ($a != ["no-op"] and $a != ["read"]);
      $p[0] as $plan
      | {
          vector_out_of_scope_changes: (
            [ $plan.resource_changes[]?
              | select(is_change)
              | select(IN(.address; allow[]) | not) ]
            | length
          ),
          # TYPE-scoped, not address-prefix — an address match would collide with the
          # exact-equality rule. Volumes are named alongside servers because
          # hcloud_volume.workspaces[*] is sole-copy user data, sits in this arm''s target
          # closure, and is actively mutated by the LUKS arms.
          host_destroyed: (
            [ $plan.resource_changes[]?
              | select(.type? == "hcloud_server" or .type? == "hcloud_volume")
              | select((.change.actions? // []) | any(. == "delete" or . == "forget")) ]
            | length
          ),
          # EVERY entry at the allowed address, whatever its actions. Distinguishes
          # "address absent" (no-op, benign) from "address present but not a delivery"
          # (a lone delete/forget/update — alarming). See the four-counters note above.
          journald_entries: (
            [ $plan.resource_changes[]?
              | select(IN(.address; allow[])) ]
            | length
          ),
          journald_delivered: (
            [ $plan.resource_changes[]?
              | select(IN(.address; allow[]))
              | select(((.change.actions? // []) | sort) as $s
                       | $s == ["create","delete"] or $s == ["create"]) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "vector_redeliver_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.vector_out_of_scope_changes')
  hdel=$(echo "$counts" | jq -r '.host_destroyed')
  entries=$(echo "$counts" | jq -r '.journald_entries')
  delivered=$(echo "$counts" | jq -r '.journald_delivered')

  # Every counter is a non-negative integer BEFORE any arithmetic compares one.
  # A counter that did not evaluate is the empty string, and [[ "" -gt 0 ]] is FALSE under
  # bash coercion — so an uncomputed counter silently satisfies every threshold. The shared
  # helper names WHICH counter failed rather than reporting them all.
  plan_gate_assert_numeric "vector_redeliver_gate" \
    "vector_out_of_scope_changes=${oos}" "host_destroyed=${hdel}" \
    "journald_entries=${entries}" "journald_delivered=${delivered}" || return 1

  # The PASS-path counter line. Asserted by the suite and consumed as the liveness signal —
  # a gate that decides correctly but prints nothing is unobservable after the fact.
  echo "vector_out_of_scope_changes=${oos} host_destroyed=${hdel} journald_entries=${entries} journald_delivered=${delivered}"

  # Named, specific refusals FIRST, so an operator sees the alarming thing by name rather
  # than a generic "not the expected shape".
  if [[ "$hdel" -gt 0 ]]; then
    echo "vector_redeliver_gate: ABORT — this dispatch would DESTROY a server or volume (host_destroyed=${hdel}). web-1 and the workspaces volumes are in this arm's target closure; a delivery must never remove them."
    return 1
  fi
  if [[ "$oos" -gt 0 ]]; then
    echo "vector_redeliver_gate: ABORT — ${oos} change(s) outside the allow-set. This arm may only deliver terraform_data.journald_persistent; pending drift elsewhere in the closure must be cleared through the push apply, not through this arm."
    return 1
  fi
  if [[ "$entries" -eq 0 ]]; then
    # Deliberately NOT "state already matches": with an exact-equality allow-set, zero
    # entries is ALSO what a broken allow-set looks like (see the un-indexed-address note).
    echo "vector_redeliver_gate: NO-OP — no entry matched the allow-set, so there is nothing to redeliver. If a delivery was expected, verify terraform_data.journald_persistent is still un-indexed at that exact address."
    VECTOR_REDELIVER_OUTCOME="noop"
    return 0
  fi
  if [[ "$entries" -ne 1 || "$delivered" -ne 1 ]]; then
    echo "vector_redeliver_gate: ABORT — the allow-set address is present but this is not exactly one delivery (journald_entries=${entries} journald_delivered=${delivered}). A lone delete/forget, an update-in-place, or duplicate entries all land here; only [\"create\",\"delete\"] or [\"create\"] is a delivery."
    return 1
  fi
  echo "vector_redeliver_gate: PASS — exactly one delivery of terraform_data.journald_persistent, nothing else changed"
  VECTOR_REDELIVER_OUTCOME="pass"
  return 0
}
