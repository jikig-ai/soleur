#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-host-shape-gate.sh (sourced by the inngest_host job in
# .github/workflows/apply-web-platform-infra.yml, #6894 — ADR-142 Guard 3).
#
# The gate grades every resource_changes entry against a per-address permitted-actions table over
# the job's 18 -target= addresses. Creates are PERMITTED, never REQUIRED.
#
# ONE CASE PER PREDICATE, AND ONE PER FORBIDDEN CELL of the permitted table. Every fixture starts
# from the REALISTIC base — all 18 addresses present as ["no-op"] (untargeted-but-present is the
# live shape) — and changes ONE thing, and every RED asserts the gate's `reason=<token>` rather than
# merely rc. Must-PASS rows are counted from the file (H2), so a gate stuck at "reject everything"
# cannot hide behind a RED-only battery.
#
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only). Deterministic; no network.
#
# Run: bash tests/scripts/test-inngest-host-shape-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DIR}/../.." && pwd)"
# shellcheck source=tests/scripts/lib/inngest-host-shape-gate.sh
source "${DIR}/lib/inngest-host-shape-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [[ -n "${2:-}" ]] && echo "      rc=$2" >&2; [[ -n "${3:-}" ]] && echo "      out=$3" >&2; return 0; }

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d -t inngest-host-shape-gate.XXXXXXXX)" || { printf '[FATAL] mktemp -d failed\n' >&2; exit 2; }
trap 'rm -rf "${TMP:?}"' EXIT

# ── INSTRUMENT SELF-TEST ──────────────────────────────────────────────────────────
# Both counters must move, reported via printf + exit, never through the helpers it backstops.
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — proves fail() records)" >/dev/null 2>&1
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  printf '[FATAL] instrument self-test did not move both counters (passes %s->%s, fails %s->%s)\n' \
    "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
passes=$_p0; fails=$_f0

GATE="${DIR}/lib/inngest-host-shape-gate.sh"
PREAMBLE="${DIR}/lib/plan-gate-preamble.sh"
WF="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"
# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${DIR}/lib/gate-suite-harness.sh"
assert_fixture_dir "$TMP"
# The harness sources MUTATED COPIES of the gate from $TMP, and the gate resolves the shared
# destroy-guard filter from its own directory — so the filter must sit beside those copies.
cp "${DIR}/lib/destroy-guard-filter-web-platform.jq" "${TMP:?}/" || { printf '[FATAL] could not stage the destroy-guard filter\n' >&2; exit 2; }

# ── The job's -target set, DERIVED from the workflow (never retyped) ──────────────
_job_body() {
  awk -v want="  $1:" '
    $0 == want { inb = 1; print; next }
    inb && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { inb = 0 }
    inb && /^[a-zA-Z]/ { inb = 0 }
    inb { print }
  ' "$WF" | grep -vE '^[[:space:]]*#'
}
JOB="$(_job_body inngest_host)"
TARGETS="$(grep -oE "\-target='[^']+'" <<<"$JOB" | sed -E "s/^-target='([^']+)'$/\1/" | sort)"
_n_targets="$(grep -c . <<<"$TARGETS" || true)"
if [[ "$_n_targets" != "18" ]]; then
  printf '[FATAL] expected the inngest_host job to carry 18 -target= addresses, derived %s — the extraction or the job drifted\n' "$_n_targets" >&2
  exit 2
fi

# ── Fixture builder ───────────────────────────────────────────────────────────────
# BASE: every -target address as ["no-op"] with a non-null `before` (it exists).
jq -Rn '[inputs | select(length > 0) | {address: ., change: {actions: ["no-op"], before: {id: "1"}, after: {}}}]
        | {format_version: "1.2", resource_changes: .}' <<<"$TARGETS" > "${TMP:?}/base.json"
PLAN="${TMP:?}/plan.json"
# build <spec…> — each spec is `addr=<actions-json>` (set/insert), `addr=ABSENT` (remove), or
# `+<entry-json>` (append a raw entry). Inserted addresses get `before: null` (a create shape).
build() {
  jq '
    reduce $ARGS.positional[] as $s (.;
      if ($s | startswith("+")) then .resource_changes += [($s[1:] | fromjson)]
      else ($s | index("=")) as $i | ($s[:$i]) as $a | ($s[$i + 1:]) as $v
        | if $v == "ABSENT" then .resource_changes |= map(select(.address != $a))
          elif any(.resource_changes[]; .address == $a) then .resource_changes |= map(if .address == $a then .change.actions = ($v | fromjson) else . end)
          else .resource_changes += [{address: $a, change: {actions: ($v | fromjson), before: null, after: {}}}]
          end
      end)' "${TMP:?}/base.json" --args "$@" > "${TMP:?}/plan.json"
}
# all_of <actions-json> — every -target address set to the same actions.
all_of() { local a spec=(); while IFS= read -r a; do spec+=("${a}=$1"); done <<<"$TARGETS"; build "${spec[@]}"; }

# check <name> <want_rc> <plan> <needle> [<needle>…] — every needle must appear.
check() {
  local name="$1" want_rc="$2" plan="$3"; shift 3
  local out rc=0 n missing=""
  out="$(inngest_host_shape_gate "$plan" 2>&1)" || rc=$?
  for n in "$@"; do [[ "$out" == *"$n"* ]] || missing+="${missing:+, }'$n'"; done
  if [[ "$rc" -eq "$want_rc" && -z "$missing" ]]; then pass; else fail "$name (want rc=$want_rc; missing: ${missing:-none})" "$rc" "$out"; fi
}
# red <reason> <spec…> — build the plan from the specs and require ABORT with that reason.
red() { local r="$1"; shift; build "$@"; check "RED ${r}: $*" 1 "$PLAN" "reason=${r} "; }

# ── WRAPPER SELF-TESTS ────────────────────────────────────────────────────────────
build
_st_p=$passes; _st_f=$fails
# A needle no gate state can emit, so this arm must fail against every gate.
check "SELF-TEST (expected to fail)" 1 "$PLAN" "reason=__selftest_unreachable__" 2>/dev/null
if [[ "$fails" -eq $((_st_f + 1)) && "$passes" -eq "$_st_p" ]]; then
  passes=$_st_p; fails=$_st_f; pass
else
  passes=$_st_p; fails=$_st_f
  printf '[FATAL] INSTRUMENT: check() did not fail on a must-fail arm — every assertion in this file is decorative\n' >&2
  exit 2
fi
_st_p=$passes; _st_f=$fails
red "__selftest_unreachable__" 2>/dev/null
if [[ "$fails" -eq $((_st_f + 1)) && "$passes" -eq "$_st_p" ]]; then
  passes=$_st_p; fails=$_st_f; pass
else
  passes=$_st_p; fails=$_st_f
  printf '[FATAL] INSTRUMENT: red() did not fail on a must-fail arm\n' >&2
  exit 2
fi
if ! gate_harness_selftest; then fails=$((fails + 1)); fi

# ── MUST-PASS ─────────────────────────────────────────────────────────────────────
build
check "PASS: all 18 addresses no-op (no create is ever required)" 0 "$PLAN" "inngest_host_shape_gate: PASS"
all_of '["create"]'
check "PASS: full from-scratch build (every address create, passphrase pair absent)" 0 "$PLAN" "inngest_host_shape_gate: PASS"
build 'doppler_secret.inngest_betterstack_logs_token=["update"]'
check "PASS: the only change is a doppler_secret update (rotation reaches Doppler by design)" 0 "$PLAN" "inngest_host_shape_gate: PASS"
build 'hcloud_volume.inngest_redis_luks=["create"]' 'hcloud_volume_attachment.inngest_redis_luks=["create"]'
check "PASS: the ADR-142 additive create (LUKS volume + attachment), rest no-op" 0 "$PLAN" "inngest_host_shape_gate: PASS"
build 'doppler_service_token.inngest=["update"]' 'doppler_project.inngest=["update"]' \
  '+{"address":"data.hcloud_image.ubuntu","change":{"actions":["read"]}}' \
  '+{"address":"hcloud_network.main","change":{"actions":["no-op"],"before":{"id":"9"},"after":{}}}'
check "PASS: Doppler updates + a data read + an untargeted dependency as no-op" 0 "$PLAN" "inngest_host_shape_gate: PASS"
mk_plan "$PLAN" "[]"
check "PASS: an EMPTY resource_changes array (nothing to apply; nothing is required)" 0 "$PLAN" "inngest_host_shape_gate: PASS"

# ── MUST-RED: every forbidden cell of the permitted table ─────────────────────────
S=hcloud_server.inngest
OV=hcloud_volume.inngest_redis
OA=hcloud_volume_attachment.inngest_redis
LV=hcloud_volume.inngest_redis_luks
LA=hcloud_volume_attachment.inngest_redis_luks
# server: no-op | create
red server_touched "$S=[\"update\"]"
red server_touched "$S=[\"delete\",\"create\"]"
red server_touched "$S=[\"create\",\"delete\"]"
red server_touched "$S=[\"delete\"]"
red server_touched "$S=[\"forget\"]"
# live volume: no-op | create IFF the server is a create
red old_volume_touched "$OV=[\"update\"]"
red old_volume_touched "$OV=[\"create\"]"
red old_volume_touched "$OV=[\"create\"]" "$S=[\"delete\",\"create\"]"
red old_volume_touched "$OV=[\"delete\"]"
red old_volume_touched "$OV=[\"forget\"]"
red old_volume_touched "$OV=[\"delete\",\"create\"]"
# live attachment: same rule
red old_attachment_touched "$OA=[\"update\"]"
red old_attachment_touched "$OA=[\"create\"]"
red old_attachment_touched "$OA=[\"create\"]" "$S=[\"update\"]"
red old_attachment_touched "$OA=[\"delete\"]"
red old_attachment_touched "$OA=[\"forget\"]"
red old_attachment_touched "$OA=[\"delete\",\"create\"]"
# ...and the conditional's PERMITTED direction: both created alongside a from-scratch server.
build "$S=[\"create\"]" "$OV=[\"create\"]" "$OA=[\"create\"]"
check "PASS: the live volume + attachment created ALONGSIDE a server create" 0 "$PLAN" "inngest_host_shape_gate: PASS"
# additive LUKS volume / attachment: no-op | create
red luks_volume_touched "$LV=[\"update\"]"
red luks_volume_touched "$LV=[\"delete\"]"
red luks_volume_touched "$LV=[\"forget\"]"
red luks_volume_touched "$LV=[\"delete\",\"create\"]"
red luks_attachment_touched "$LA=[\"update\"]"
red luks_attachment_touched "$LA=[\"delete\"]"
red luks_attachment_touched "$LA=[\"forget\"]"
# network: no-op | create
red network_touched 'hcloud_server_network.inngest=["update"]'
red network_touched 'hcloud_server_network.inngest=["delete"]'
red network_touched 'hcloud_server_network.inngest=["forget"]'
# firewall + its attachment: no-op | create (an update is an ingress change on a no-inbound host)
red firewall_touched 'hcloud_firewall.inngest=["update"]'
red firewall_touched 'hcloud_firewall_attachment.inngest=["update"]'
red firewall_touched 'hcloud_firewall.inngest=["delete"]'
red firewall_touched 'hcloud_firewall_attachment.inngest=["forget"]'
# generated secrets: no-op | create — a regeneration rotates the host's credentials
red generated_secret_touched 'random_id.inngest_signing_key_dedicated=["update"]'
red generated_secret_touched 'random_id.inngest_event_key_dedicated=["delete","create"]'
red generated_secret_touched 'random_password.inngest_redis_password_dedicated=["update"]'
red generated_secret_touched 'random_password.inngest_redis_password_dedicated=["forget"]'
# Doppler: no-op | create | update — never a delete or forget
red doppler_touched 'doppler_secret.inngest_signing_key_dedicated=["delete"]'
red doppler_touched 'doppler_project.inngest=["forget"]'
red doppler_touched 'doppler_service_token.inngest=["delete","create"]'
red doppler_touched 'doppler_environment.inngest_prd=["delete"]'
# The LUKS passphrase pair: ABSENT — any entry, a no-op included.
red luks_passphrase_in_graph '+{"address":"random_password.inngest_redis_luks","change":{"actions":["no-op"],"before":{"id":"1"},"after":{}}}'
red luks_passphrase_in_graph '+{"address":"doppler_secret.inngest_redis_luks_key","change":{"actions":["no-op"],"before":{"id":"1"},"after":{}}}'
red luks_passphrase_in_graph 'random_password.inngest_redis_luks=["create"]'

# ── MUST-RED: the global predicates, each on an input its own counter sees first ──
red forget_present '+{"address":"hcloud_volume.git_data","change":{"actions":["forget"],"before":{"id":"1"},"after":null}}'
red resource_deletes '+{"address":"hcloud_volume.git_data","change":{"actions":["delete"],"before":{"id":"1"},"after":null}}'
red nested_deletes '+{"address":"cloudflare_ruleset.waf","type":"cloudflare_ruleset","change":{"actions":["update"],"before":{"rules":[{},{}]},"after":{"rules":[{}]}}}'
red out_of_scope '+{"address":"hcloud_ssh_key.default","change":{"actions":["update"],"before":{"id":"1"},"after":{}}}'
red out_of_scope '+{"address":"hcloud_volume_attachment.git_data","change":{"actions":["create"],"before":null,"after":{}}}'

# ── SUBSTRING MEMBERSHIP: exact equality, never containment ───────────────────────
# `hcloud_volume.inngest_redis` is a prefix of `hcloud_volume.inngest_redis_luks`, which is a prefix
# of `…_luks_staging`. A prefix-sharing address must be OUT of scope — not filed under a class.
# (Under containment the additive-create PASS row above also reds: the LUKS create would land in
# the live volume's class.)
red out_of_scope '+{"address":"hcloud_volume.inngest_redis_luks_staging","change":{"actions":["create"],"before":null,"after":{}}}'
red out_of_scope '+{"address":"hcloud_server.inngest_canary","change":{"actions":["create"],"before":null,"after":{}}}'

# ── EMPTY-EVALUATING COUNTER must RED via plan_gate_assert_numeric ────────────────
# Built on an input where, with the counters uncomputed and the numeric assert gone, every
# threshold reads "" and the gate would PASS a state removal.
build '+{"address":"hcloud_volume.git_data","change":{"actions":["forget"],"before":{"id":"1"},"after":null}}'
_mut="${TMP:?}/mutated-numeric.sh"
awk -v n='select(.change.actions? | index("forget")) ] | length' '{ if (index($0, n)) print "            empty"; else print }' "$GATE" > "${TMP:?}/mutated-numeric.sh"
if cmp -s "$_mut" "$GATE"; then
  fail "EMPTY-COUNTER: the mutation matched NOTHING in the gate; the forget_present expression drifted"
else
  _rc=0; _out="$(bash -c "source '$PREAMBLE'; source '$_mut'; inngest_host_shape_gate '$PLAN'" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 1 && "$_out" == *"counter parse failed"* && "$_out" == *"forget_present=''"* ]]; then
    pass
  else
    fail "EMPTY-COUNTER: an empty-evaluating counter must ABORT naming it, not satisfy every threshold" "$_rc" "$_out"
  fi
fi

# ── PARTITION CLOSURE: an allow-set address with no permitted-actions rule ────────
# The gate as shipped is partitioned, so no PLAN can reach allow_unpartitioned — drive it through a
# copy of the gate with one address dropped from its class. That address would otherwise be
# admitted with NO per-address rule (any update/delete on it silently in scope).
build
awk -v n='a: ["hcloud_server_network.inngest"],' '{ if (index($0, n)) sub(/"hcloud_server_network\.inngest"/, ""); print }' "$GATE" > "${TMP:?}/mutated-partition.sh"
if cmp -s "${TMP:?}/mutated-partition.sh" "$GATE"; then
  fail "PARTITION: the class-drop mutation matched NOTHING in the gate; the class table drifted"
else
  _rc=0; _out="$(bash -c "source '$PREAMBLE'; source '${TMP:?}/mutated-partition.sh'; inngest_host_shape_gate '$PLAN'" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 1 && "$_out" == *"reason=allow_unpartitioned "* ]]; then pass; else fail "PARTITION: an allow-set address with no class must ABORT allow_unpartitioned on every plan" "$_rc" "$_out"; fi
fi

# ── Harness row (a): unreadable / unclassifiable plans RED ────────────────────────
check "Ha: missing plan JSON => fail-closed" 1 "${TMP:?}/does-not-exist.json" "ABORT"
check "Ha: a DIRECTORY as the plan path => fail-closed" 1 "${TMP:?}" "ABORT"
printf 'not json{{{' > "${TMP:?}/bad.json"
check "Ha: malformed JSON => fail-closed" 1 "${TMP:?}/bad.json" "unparseable"
printf '{"format_version":"1.2"}' > "${TMP:?}/nochanges.json"
check "Ha: no resource_changes key => fail-closed" 1 "${TMP:?}/nochanges.json" "no resource_changes array"
printf '{"format_version":"1.2","resource_changes":null}' > "${TMP:?}/nullchanges.json"
check "Ha: resource_changes null => fail-closed" 1 "${TMP:?}/nullchanges.json" "no resource_changes array"
build "+$(rc_empty_actions "$OV" 'hcloud_volume')"
cp "$PLAN" "${TMP:?}/pg-d5.json"
check "Ha (D5): an EMPTY actions array hiding a destroy of the live volume => unclassifiable ABORT" 1 "${TMP:?}/pg-d5.json" "inngest_host_shape_gate: ABORT — unclassifiable"
build "+$(rc_scalar_change "$OV" 'hcloud_volume')"
check "Ha (D6): a SCALAR .change => unclassifiable ABORT" 1 "$PLAN" "unclassifiable plan entry"
build "$OV=[[\"delete\"]]"
check "Ha: a NESTED actions array hiding a delete => unclassifiable ABORT" 1 "$PLAN" "unclassifiable plan entry"
# INVOKED, not merely sourced. At an allow-set address the per-address table is exhaustive, so an
# empty actions array there also fails its class (`[]` is not a permitted action list). OUTSIDE the
# allow-set it is invisible to every counter — `[] | any(...)` is false — so there the
# classifiability call is the SOLE guard: neutered, the plan must PASS.
build "+$(rc_empty_actions 'hcloud_volume.workspaces["web-1"]' 'hcloud_volume')"
cp "$PLAN" "${TMP:?}/pg-d5-oos.json"
check "Ha (D5): an EMPTY actions array OUTSIDE the allow-set => unclassifiable ABORT" 1 "${TMP:?}/pg-d5-oos.json" "unclassifiable plan entry"
gate_mutate_and_check "Ha: classifiability call is the sole guard on a hidden destroy outside the allow-set" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  inngest_host_shape_gate "${TMP:?}/pg-d5-oos.json"
# The readability call is LAYERED: neutered, the classifiability call still refuses.
gate_mutate_layered "Ha: readability call (invoked, not merely sourced)" \
  's/^  plan_gate_assert_readable .*/  :/' \
  "no resource_changes array" "unclassifiable plan entry" \
  inngest_host_shape_gate "${TMP:?}/nochanges.json"

# ── ALLOW-SET PARITY: the gate's allow-set IS the job's -target set ───────────────
# Guard 3's independent anchor. One diff could widen the gate and the workflow together; this row
# (and its twin in plugins/soleur/test/terraform-target-parity.test.ts) at least forces them to agree.
GATE_ALLOW="$(awk '/^      def allow: \[$/ { f = 1; next } f && /^      \];$/ { exit } f' "$GATE" | grep -oE '"[^"]+"' | tr -d '"' | sort)"
if [[ -n "$GATE_ALLOW" && "$GATE_ALLOW" == "$TARGETS" ]]; then
  pass
else
  fail "PARITY: the gate's def allow differs from the inngest_host job's -target set" "n/a" "$(diff <(printf '%s\n' "$GATE_ALLOW") <(printf '%s\n' "$TARGETS"))"
fi

# ── The dispatch job INVOKES the gate ─────────────────────────────────────────────
# Scoped to the inngest_host job (whole-line header match — inngest_host_replace shares the
# prefix), comment-stripped, anchored on the CALL FORM (cq-assert-anchor-not-bare-token).
_src_re='^          source "\$\{GITHUB_WORKSPACE\}/tests/scripts/lib/inngest-host-shape-gate\.sh"$'
_call_re='^          if ! inngest_host_shape_gate tfplan\.json; then$'
_n_src="$(grep -cE "$_src_re" <<<"$JOB" || true)"
_n_call="$(grep -cE "$_call_re" <<<"$JOB" || true)"
_n_call_wf="$(grep -vE '^[[:space:]]*#' "$WF" | grep -cE '^[[:space:]]*(if !?[[:space:]]*)?inngest_host_shape_gate[[:space:]]' || true)"
if [[ "$_n_src" == "1" ]]; then pass; else fail "WIRING: inngest_host must SOURCE the gate lib exactly once via the anchored source line (found ${_n_src})"; fi
if [[ "$_n_call" == "1" ]]; then pass; else fail "WIRING: inngest_host must CALL 'if ! inngest_host_shape_gate tfplan.json; then' exactly once (found ${_n_call})"; fi
if [[ "$_n_call_wf" == "1" ]]; then pass; else fail "WIRING: the gate call must be UNIQUE across the workflow (found ${_n_call_wf})"; fi
_ln() { grep -nE "$1" <<<"$JOB" | head -1 | cut -d: -f1; }
_l_json="$(_ln '^          terraform show -json tfplan > tfplan\.json$')"
_l_src="$(_ln "$_src_re")"
_l_call="$(_ln "$_call_re")"
_l_apply="$(_ln '^[[:space:]]*terraform apply -no-color -input=false tfplan$')"
if [[ -n "$_l_json" && -n "$_l_src" && -n "$_l_call" && -n "$_l_apply" ]] \
   && (( _l_json < _l_src && _l_src < _l_call && _l_call < _l_apply )); then
  pass
else
  fail "WIRING: order must be tfplan.json written < source < call < apply of the saved tfplan (json=${_l_json:-none} src=${_l_src:-none} call=${_l_call:-none} apply=${_l_apply:-none})"
fi
_abort_block="$(awk -v s="${_l_call:-0}" 'NR > s && /^          fi$/ { exit } NR > s { print }' <<<"$JOB")"
if grep -qxE '            exit 1' <<<"$_abort_block"; then pass; else fail "WIRING: the gate's ABORT branch does not 'exit 1'"; fi
if grep -qE '^[[:space:]]*continue-on-error:' <<<"$JOB"; then fail "WIRING: continue-on-error in inngest_host turns a gate ABORT green"; else pass; fi

# ── H2: must-PASS arms counted from the file ──────────────────────────────────────
_pass_arms="$(grep -cE '^check "PASS: [^"]*" 0 "\$PLAN" "inngest_host_shape_gate: PASS"' "${BASH_SOURCE[0]}" || true)"
if [[ "$_pass_arms" =~ ^[0-9]+$ ]] && [[ "$_pass_arms" -ge 7 ]]; then pass; else fail "H2: only ${_pass_arms} must-PASS arms found (floor 7)"; fi

# ── H1: anti-vacuity floor ────────────────────────────────────────────────────────
# Self-contained; reported via printf + exit, never through pass()/fail(). A floor, not equality.
_floor=79
_ran=$((passes + fails))
if [[ "$_ran" -lt "$_floor" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" "$_floor" >&2
  printf 'inngest-host-shape-gate: %s passed, %s failed\n' "$passes" "$fails"
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor %s)\n' "$_ran" "$_floor"

echo ""
echo "inngest-host-shape-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
