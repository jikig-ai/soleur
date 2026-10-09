# shellcheck shell=bash
# Sourced gates for apply_target=inngest-backstop-retire (.github/workflows/apply-web-platform-infra.yml, #8285).
#
# A REWRITE, not a conversion, of the retired inngest-volume-recut-gate.sh. That gate demanded
# delete AND create and a born-RAW volume; this one never permits a create of the retired volume
# and never permits a replace. Reused from it: the fail-closed preamble, the named-live pattern and
# the id-pin counters.
#
# FIVE FUNCTIONS, each the SAME bytes tests/scripts/test-inngest-backstop-retire-gate.sh grades:
#
#   inngest_backstop_retire_gate <plan.json> <phase> <expected_id> <mode>        (Guard 2)
#       phase = detach | wipe | teardown | destroy   (anything else ABORTS: reason=phase_unknown)
#       mode  = targeted | untargeted                (anything else ABORTS: reason=mode_unknown)
#   inngest_backstop_live_store_gate --cutover-flag .. --active-id .. --luks-volume-file ..      (plan 2.0)
#       --probe-file .. --now .. --inflight-runs .. --server-id ..
#   inngest_backstop_destroy_precondition --erasure .. --wipe-run-id .. ...                      (Guard 4)
#   inngest_backstop_wipe_evidence_gate --rows-file .. --nonce .. ...        (the evidence funnel; the wipe
#       phase's poll and Guard 4 both call it)
#   inngest_backstop_wipe_nonce_rows --rows-file .. --nonce ..               (prints the message of every
#       wipe-marker row bearing the nonce; the poll uses it to short-circuit on a refusal)
#
# THE PLAN-SHAPE QUANTIFIER. Every element of .resource_changes[] is graded; an address nobody
# enumerated still aborts (the gate never works from a list of "addresses known today"). Per phase
# the AUTHORIZED categories and how many of each (the table is `rng` in the jq program):
#   detach    exactly 1 delete of hcloud_volume_attachment.inngest_redis
#   wipe      exactly 1 create each of hcloud_server.inngest_backstop_wipe and its attachment (step A)
#   teardown  0..1 delete each of those two (ANY subset: a half-failed step A must still tear down)
#   destroy   exactly 1 delete of hcloud_volume.inngest_redis
# An UNTARGETED plan (the read-only plan of the whole root: the D1 proof) additionally tolerates the
# orphan volume delete in every phase before destroy and REQUIRES hcloud_server.inngest and the LUKS
# volume/attachment to be present as exactly one no-op each (absence from a plan proves nothing).
# It grades ONLY the four retire addresses against the phase's set; an entry for any OTHER resource
# is unrelated drift and is ignored (it is neither out_of_scope nor unauthorized_delete) unless it
# carries the live volume id or the host (below) or uses a verb outside the closed vocabulary. The
# targeted plan, which is what gets applied, is graded exactly. No [ack-destroy] bypass exists.
#
# NEVER-ACTED-ON SET. Independently of the table above: any positive action (create/update/delete/
# forget) on hcloud_server.inngest, on the LUKS volume or attachment, on the LUKS key pair, on the
# web-1 volume/attachment/server, or on ANY entry whose before/after carries the live volume id
# 106903269 as a whole scalar value (compared as a string) is refused. That last clause is what makes a
# mistargeted id a plan-JSON fact rather than an address assumption; an id embedded INSIDE a longer
# string (a URL, a label) is not matched.
#
# CLOSED VERB VOCABULARY (this gate only). An entry whose actions contain a verb outside
# {no-op, read, create, update, delete, forget} aborts as reason=unknown_verb: the positive-action
# filter is a deny-list of four verbs, so a verb a future Terraform adds would otherwise read as inert.
#
# ID PIN. $expected_id is required in EVERY phase (id_pin_absent), must equal the retired volume id
# 106261946 (pin_not_retired), and every authorized entry's physical id is read from the plan JSON
# (.change.before.id / .before.volume_id / .after.volume_id), never from a comment, compared as a
# STRING, and a null/absent/unknown id is its own counter (id_unverifiable).
#
# Counters use the 4-verb POSITIVE-ACTION filter; it excludes no-op AND read. The ABORT line carries
# `reason=<token>` naming the FIRST failing counter in a fixed order (most specific first).

# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _IBRG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_IBRG_DIR}/plan-gate-preamble.sh"
fi

_IBRG_RETIRED_ID="106261946"
_IBRG_LIVE_ID="106903269"

inngest_backstop_retire_gate() {
  local plan_json="${1:-}"
  local phase="${2:-}"
  local expected_id="${3:-}"
  local mode="${4:-}"
  local counts lvt ist nlt uvb ipa pnr idm idu sab lpa ud oos sex smi reason

  # An unrecognized phase or mode must abort, never default to a permissive set.
  case "$phase" in
    detach|wipe|teardown|destroy) ;;
    *) echo "inngest_backstop_retire_gate: ABORT reason=phase_unknown — phase '${phase}' is not one of detach|wipe|teardown|destroy"; return 1 ;;
  esac
  case "$mode" in
    targeted|untargeted) ;;
    *) echo "inngest_backstop_retire_gate: ABORT reason=mode_unknown — mode '${mode}' is not targeted|untargeted"; return 1 ;;
  esac

  plan_gate_assert_readable     "inngest_backstop_retire_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "inngest_backstop_retire_gate" "$plan_json" || return 1

  if ! counts=$(jq -n --slurpfile p "$plan_json" --arg expected "$expected_id" --arg phase "$phase" --arg mode "$mode" \
      --arg retired "$_IBRG_RETIRED_ID" --arg livev "$_IBRG_LIVE_ID" '
      def nrm: .address | sub("\\[[0-9]+\\]$"; "");
      def acts: .change.actions;
      def pos: (acts | any(. == "create" or . == "update" or . == "delete" or . == "forget"));
      def hasdel: (acts | any(. == "delete" or . == "forget"));
      def only($a): (acts == $a);
      def scal($v): if ($v | type) == "string" or ($v | type) == "number" then ($v | tostring) else null end;
      def bid:  scal(try .change.before.id catch null);
      def bvol: scal(try .change.before.volume_id catch null);
      def avol: scal(try .change.after.volume_id catch null);
      def avol_unknown: ((try .change.after_unknown.volume_id catch null) == true);
      def is_wsrv: (.address == "hcloud_server.inngest_backstop_wipe" or .address == "hcloud_server.inngest_backstop_wipe[0]");
      def is_watt: (.address == "hcloud_volume_attachment.inngest_backstop_wipe" or .address == "hcloud_volume_attachment.inngest_backstop_wipe[0]");
      def cat:
        if   .address == "hcloud_volume_attachment.inngest_redis" and only(["delete"]) then "att_del"
        elif .address == "hcloud_volume.inngest_redis"            and only(["delete"]) then "vol_del"
        elif is_wsrv and only(["create"]) then "wsrv_create"
        elif is_watt and only(["create"]) then "watt_create"
        elif is_wsrv and only(["delete"]) then "wsrv_del"
        elif is_watt and only(["delete"]) then "watt_del"
        else null end;
      # The orphan volume delete is tolerated before the destroy phase only in the UNTARGETED plan.
      def orphan_hi: (if $mode == "untargeted" then 1 else 0 end);
      def rng:
        { detach:   {att_del: [1,1], vol_del: [0, orphan_hi], wsrv_create: [0,0], watt_create: [0,0], wsrv_del: [0,0], watt_del: [0,0]},
          wipe:     {att_del: [0,0], vol_del: [0, orphan_hi],
                     wsrv_create: (if $mode == "targeted" then [1,1] else [0,0] end),
                     watt_create: (if $mode == "targeted" then [1,1] else [0,0] end), wsrv_del: [0,0], watt_del: [0,0]},
          teardown: {att_del: [0,0], vol_del: [0, orphan_hi], wsrv_create: [0,0], watt_create: [0,0], wsrv_del: [0,1], watt_del: [0,1]},
          destroy:  {att_del: [0,0], vol_del: [1,1], wsrv_create: [0,0], watt_create: [0,0], wsrv_del: [0,0], watt_del: [0,0]}
        }[$phase];
      # whole-scalar match: an id embedded inside a longer string (a URL, a label) is not matched
      def refs_live: ([(.change.before // empty), (.change.after // empty) | .. | scalars | tostring] | any(. == $livev));
      def vocab: ["no-op", "read", "create", "update", "delete", "forget"];
      # an UNTARGETED plan grades only the four retire addresses; every other entry is unrelated drift
      def rel: (nrm | IN("hcloud_volume_attachment.inngest_redis", "hcloud_volume.inngest_redis",
                         "hcloud_server.inngest_backstop_wipe", "hcloud_volume_attachment.inngest_backstop_wipe"));
      def graded: ($mode == "targeted") or rel;
      def live_addr: ["hcloud_volume.inngest_redis_luks", "hcloud_volume_attachment.inngest_redis_luks"];
      def named_live: ["random_password.inngest_redis_luks", "doppler_secret.inngest_redis_luks_key",
                       "hcloud_volume.workspaces[\"web-1\"]", "hcloud_volume_attachment.workspaces[\"web-1\"]", "hcloud_server.web[\"web-1\"]"];
      # the physical id an authorized entry is graded on (null = the plan cannot name it)
      def phys:
        (cat) as $c
        | if   $c == "vol_del"                           then bid
          elif $c == "att_del" or $c == "watt_del"       then bvol
          elif $c == "watt_create"                       then (if avol_unknown then null else avol end)
          else "n/a" end;
      $p[0] as $plan
      | ($plan.resource_changes // []) as $rc
      | rng as $r
      | [ $rc[] | select(pos) ] as $posl
      | {
          live_volume_touched: ([ $posl[] | select((nrm | IN(live_addr[])) or refs_live) ] | length),
          inngest_server_touched: ([ $posl[] | select(nrm == "hcloud_server.inngest") ] | length),
          named_live_touched: ([ $posl[] | select($mode == "targeted") | select(nrm | IN(named_live[])) ] | length),
          unknown_verb: ([ $rc[] | select(acts | any(. as $v | (vocab | index($v)) == null)) ] | length),
          id_pin_absent: (if $expected == "" then 1 else 0 end),
          pin_not_retired: (if $expected != "" and $expected != $retired then 1 else 0 end),
          id_mismatch: (if $expected == "" then 0 else
              [ $posl[] | select(cat != null) | phys | select(. != null and . != "n/a" and . != $expected) ] | length end),
          id_unverifiable: ([ $posl[] | select(cat != null) | phys | select(. == null) ] | length),
          inngest_server_absent: (if $mode == "untargeted" then
              (if ([ $rc[] | select(.address == "hcloud_server.inngest") | select(only(["no-op"])) ] | length) == 1 then 0 else 1 end)
              else 0 end),
          luks_pair_absent: (if $mode == "untargeted" then
              ([ "hcloud_volume.inngest_redis_luks", "hcloud_volume_attachment.inngest_redis_luks" ]
                | map(. as $a | select(([ $rc[] | select(.address == $a) | select(only(["no-op"])) ] | length) != 1)) | length)
              else 0 end),
          unauthorized_delete: ([ $posl[] | select(graded) | select(hasdel) | select((cat == null) or ($r[cat][1] == 0)) ] | length),
          out_of_scope:        ([ $posl[] | select(graded) | select(hasdel | not) | select((cat == null) or ($r[cat][1] == 0)) ] | length),
          shape_extra:   ([ $r | to_entries[] | select(.value[1] >= 1) | .key as $k | select(([ $posl[] | select(cat == $k) ] | length) > .value[1]) ] | length),
          shape_missing: ([ $r | to_entries[] | select(.value[0] >= 1) | .key as $k | select(([ $posl[] | select(cat == $k) ] | length) < .value[0]) ] | length)
        }
    ' 2>/dev/null); then
    echo "inngest_backstop_retire_gate: ABORT reason=jq_failed — jq evaluation failed on ${plan_json}"
    return 1
  fi
  lvt=$(echo "$counts" | jq -r '.live_volume_touched')
  ist=$(echo "$counts" | jq -r '.inngest_server_touched')
  nlt=$(echo "$counts" | jq -r '.named_live_touched')
  uvb=$(echo "$counts" | jq -r '.unknown_verb')
  ipa=$(echo "$counts" | jq -r '.id_pin_absent')
  pnr=$(echo "$counts" | jq -r '.pin_not_retired')
  idm=$(echo "$counts" | jq -r '.id_mismatch')
  idu=$(echo "$counts" | jq -r '.id_unverifiable')
  sab=$(echo "$counts" | jq -r '.inngest_server_absent')
  lpa=$(echo "$counts" | jq -r '.luks_pair_absent')
  ud=$(echo "$counts"  | jq -r '.unauthorized_delete')
  oos=$(echo "$counts" | jq -r '.out_of_scope')
  sex=$(echo "$counts" | jq -r '.shape_extra')
  smi=$(echo "$counts" | jq -r '.shape_missing')

  # Every counter is a non-negative integer BEFORE any arithmetic compares one.
  plan_gate_assert_numeric "inngest_backstop_retire_gate" \
    "live_volume_touched=${lvt}" "inngest_server_touched=${ist}" "named_live_touched=${nlt}" "unknown_verb=${uvb}" "id_pin_absent=${ipa}" \
    "pin_not_retired=${pnr}" "id_mismatch=${idm}" "id_unverifiable=${idu}" "inngest_server_absent=${sab}" \
    "luks_pair_absent=${lpa}" "unauthorized_delete=${ud}" "out_of_scope=${oos}" "shape_extra=${sex}" "shape_missing=${smi}" || return 1

  echo "phase=${phase} mode=${mode} live_volume_touched=${lvt} inngest_server_touched=${ist} named_live_touched=${nlt} unknown_verb=${uvb} id_pin_absent=${ipa} pin_not_retired=${pnr} id_mismatch=${idm} id_unverifiable=${idu} inngest_server_absent=${sab} luks_pair_absent=${lpa} unauthorized_delete=${ud} out_of_scope=${oos} shape_extra=${sex} shape_missing=${smi}"

  if [[ "$lvt" -eq 0 && "$ist" -eq 0 && "$nlt" -eq 0 && "$uvb" -eq 0 && "$ipa" -eq 0 && "$pnr" -eq 0 && "$idm" -eq 0 && "$idu" -eq 0 \
     && "$sab" -eq 0 && "$lpa" -eq 0 && "$ud" -eq 0 && "$oos" -eq 0 && "$sex" -eq 0 && "$smi" -eq 0 ]]; then
    echo "inngest_backstop_retire_gate: PASS — ${phase}/${mode} plan is exactly the authorized set against volume ${expected_id} (hcloud_server.inngest, the LUKS pair and the web-1 set untouched; no reference to the live volume ${_IBRG_LIVE_ID}; no out-of-scope action)"
    return 0
  fi
  reason=unknown
  if   [[ "$lvt" -ne 0 ]]; then reason=live_volume_touched
  elif [[ "$ist" -ne 0 ]]; then reason=inngest_server_touched
  elif [[ "$nlt" -ne 0 ]]; then reason=named_live_touched
  elif [[ "$uvb" -ne 0 ]]; then reason=unknown_verb
  elif [[ "$ipa" -ne 0 ]]; then reason=id_pin_absent
  elif [[ "$pnr" -ne 0 ]]; then reason=pin_not_retired
  elif [[ "$idm" -ne 0 ]]; then reason=id_mismatch
  elif [[ "$idu" -ne 0 ]]; then reason=id_unverifiable
  elif [[ "$sab" -ne 0 ]]; then reason=inngest_server_absent
  elif [[ "$lpa" -ne 0 ]]; then reason=luks_pair_absent
  elif [[ "$ud"  -ne 0 ]]; then reason=unauthorized_delete
  elif [[ "$oos" -ne 0 ]]; then reason=out_of_scope
  elif [[ "$sex" -ne 0 ]]; then reason=shape_extra
  elif [[ "$smi" -ne 0 ]]; then reason=shape_missing
  fi
  echo "inngest_backstop_retire_gate: ABORT reason=${reason} — plan is NOT the exact ${phase}/${mode} set for volume ${expected_id} (the pin is required, must be the retired id and must match the plan's physical id; the host, the LUKS pair, web-1 and anything referencing ${_IBRG_LIVE_ID} must show no action; an untargeted plan must carry the host and LUKS pair as present no-ops; any other create/update/delete/forget aborts)"
  return 1
}

# ── inngest_backstop_live_store_gate ────────────────────────────────────────────────
# Plan 2.0: the SAME single chokepoint in front of phases detach | wipe | destroy (NOT teardown: a leaked
# wipe host must always be cleanable, whatever state the live store is in). Pure decision over values the
# workflow step READ (the I/O stays in the workflow): every input is adversarial, so an empty,
# null, degraded or malformed value fails closed.
#   --cutover-flag     INNGEST_LUKS_CUTOVER from Doppler soleur-inngest/prd  (must be exactly `done`)
#   --active-id        INNGEST_LUKS_ACTIVE_VOLUME_ID                         (must be 106903269)
#   --luks-volume-file body of GET /v1/volumes/106903269
#   --server-id        id of the live inngest server (GET /v1/servers?name=soleur-inngest)
#   --probe-file       TSV `dt<TAB>message` of the dedicated-host probe rows (selected by the
#                      workflow with the shared predicate scripts/lib/inngest-probe-row.sh)
#   --now              epoch seconds      --inflight-runs  count of OTHER apply runs in flight
inngest_backstop_live_store_gate() {
  local flag="" active="" luks="" probe="" now="" inflight="" server="" a
  while [[ $# -gt 0 ]]; do
    a="$1"
    case "$a" in
      --cutover-flag) flag="${2-}" ;; --active-id) active="${2-}" ;; --luks-volume-file) luks="${2-}" ;;
      --probe-file) probe="${2-}" ;; --now) now="${2-}" ;; --inflight-runs) inflight="${2-}" ;; --server-id) server="${2-}" ;;
      *) echo "inngest_backstop_live_store_gate: ABORT reason=usage — unknown option ${a}"; return 1 ;;
    esac
    shift 2 2>/dev/null || shift $#
  done
  local _g="inngest_backstop_live_store_gate"
  [[ "$flag" == "done" ]] || { echo "${_g}: ABORT reason=flag_not_done — INNGEST_LUKS_CUTOVER must read exactly 'done' (rollback/armed/copying/unreadable all refuse)"; return 1; }
  [[ "$active" == "$_IBRG_LIVE_ID" ]] || { echo "${_g}: ABORT reason=active_id_mismatch — INNGEST_LUKS_ACTIVE_VOLUME_ID must be ${_IBRG_LIVE_ID}"; return 1; }
  if [[ -z "$luks" || ! -f "$luks" ]] || ! jq -e '(.volume | type) == "object" and (.volume | has("id")) and (.volume | has("server"))' "$luks" >/dev/null 2>&1; then
    echo "${_g}: ABORT reason=luks_volume_unreadable — the Hetzner body for the LUKS volume is missing, unparseable or lacks volume.id/volume.server (a degraded 200 is not evidence)"; return 1
  fi
  if [[ "$(jq -r '.volume.id | tostring' "$luks")" != "$_IBRG_LIVE_ID" ]]; then
    echo "${_g}: ABORT reason=luks_identity_mismatch — the volume Hetzner answered is not ${_IBRG_LIVE_ID}"; return 1
  fi
  local srv
  srv="$(jq -r '.volume.server | if (type == "number" or type == "string") then tostring else "" end' "$luks")"
  if [[ ! "$server" =~ ^[0-9]+$ || "$srv" != "$server" ]]; then
    echo "${_g}: ABORT reason=luks_not_attached — volume ${_IBRG_LIVE_ID} is not attached to the live server (server id '${server}', attached to '${srv:-none}')"; return 1
  fi
  # Probe: every non-empty line must be `dt<TAB>message`; the NEWEST decides.
  if [[ -z "$now" || ! "$now" =~ ^[0-9]+$ ]]; then echo "${_g}: ABORT reason=probe_unusable — no clock"; return 1; fi
  if [[ -z "$probe" || ! -f "$probe" ]]; then echo "${_g}: ABORT reason=probe_unusable — probe file missing"; return 1; fi
  local line dt msg newest_dt="" newest_msg="" n=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    if [[ "$line" != *$'\t'* ]]; then echo "${_g}: ABORT reason=probe_unusable — a probe line is not dt<TAB>message"; return 1; fi
    dt="${line%%$'\t'*}"; msg="${line#*$'\t'}"; dt="${dt/T/ }"
    if [[ ! "$dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then echo "${_g}: ABORT reason=probe_unusable — a probe row has no readable timestamp"; return 1; fi
    dt="${dt:0:19}"; n=$((n + 1))
    if [[ -z "$newest_dt" || ! "$dt" < "$newest_dt" ]]; then newest_dt="$dt"; newest_msg="$msg"; fi
  done < "$probe"
  if [[ "$n" -lt 1 ]]; then echo "${_g}: ABORT reason=probe_unusable — no probe rows (a silent producer is not a healthy store)"; return 1; fi
  local ep age
  ep="$(date -u -d "$newest_dt" +%s 2>/dev/null)" || ep=""
  if [[ ! "$ep" =~ ^[0-9]+$ ]]; then echo "${_g}: ABORT reason=probe_unusable — unparseable probe timestamp"; return 1; fi
  age=$((now - ep))
  if (( age < -300 )); then echo "${_g}: ABORT reason=probe_future — the newest probe row is dated in the future"; return 1; fi
  if (( age > 10800 )); then echo "${_g}: ABORT reason=probe_stale — the newest dedicated probe row is ${age}s old (limit 10800s)"; return 1; fi
  local tok devid="" ra="" tokens
  read -r -a tokens <<<"$newest_msg"
  for tok in "${tokens[@]}"; do
    [[ -z "$devid" && "$tok" == data_mount_devid=* ]] && devid="${tok#data_mount_devid=}"
    [[ -z "$ra" && "$tok" == redis_active=* ]] && ra="${tok#redis_active=}"
  done
  [[ "$devid" == "scsi-0HC_Volume_${_IBRG_LIVE_ID}" ]] || { echo "${_g}: ABORT reason=probe_devid_mismatch — the newest probe row's data_mount_devid is '${devid:-absent}', not scsi-0HC_Volume_${_IBRG_LIVE_ID}"; return 1; }
  [[ "$ra" == "active" ]] || { echo "${_g}: ABORT reason=probe_redis_down — redis_active='${ra:-absent}' on the newest probe row"; return 1; }
  [[ "$inflight" =~ ^[0-9]+$ && "$inflight" -eq 0 ]] || { echo "${_g}: ABORT reason=inflight_apply — another apply run is in flight or unreadable ('${inflight}')"; return 1; }
  echo "${_g}: PASS — flag done, pointer and probe on ${_IBRG_LIVE_ID}, volume attached to server ${server}, probe ${age}s old with redis active, no other apply in flight"
  return 0
}

# ── inngest_backstop_destroy_precondition ───────────────────────────────────────────
# Guard 4: evidence-before-destroy. The single chokepoint; the workflow runs it BEFORE any plan.
#   --erasure ''|wipe|provider-only   --wipe-run-id N
#   --clo-attestation-ref URL   --clo-comment-file F      (provider-only: the comment fetched by id)
#   --rows-file F (Better Stack JSONEachRow, `raw` double-encoded)   --volume-file F (GET /v1/volumes/106261946)
#   --actions-file F (GET /v1/volumes/106261946/actions)  --live-server-id ID
#   --after-epoch E (floor: the wipe run's start)   --now EPOCH
# Hetzner's `size` is in GiB; the row's size_bytes is compared to size*1073741824.
#
# TRUST. The wipe row is SELF-ATTESTED: the shared Better Stack ingest token lets a holder post any row,
# so the funnel's nonce/emitter checks make STALE or REPLAYED rows fail, they do not make a forged row
# impossible. The wipe path therefore ALSO requires Hetzner's own action history (a different party): an
# attach_volume by a server that is not the live one, finished at or after the wipe run's start, and a
# later detach_volume. The provider-only path (D4) needs a CLO attestation comment on #8285 from a
# repository OWNER|MEMBER|COLLABORATOR that names the volume; it evidences NO overwrite.
inngest_backstop_destroy_precondition() {
  local erasure="" run="" clo="" clofile="" rows="" vol="" acts="" livesrv="" after="" now="" a
  while [[ $# -gt 0 ]]; do
    a="$1"
    case "$a" in
      --erasure) erasure="${2-}" ;; --wipe-run-id) run="${2-}" ;; --clo-attestation-ref) clo="${2-}" ;; --clo-comment-file) clofile="${2-}" ;;
      --rows-file) rows="${2-}" ;; --volume-file) vol="${2-}" ;; --actions-file) acts="${2-}" ;; --live-server-id) livesrv="${2-}" ;;
      --after-epoch) after="${2-}" ;; --now) now="${2-}" ;;
      *) echo "inngest_backstop_destroy_precondition: ABORT reason=usage — unknown option ${a}"; return 1 ;;
    esac
    shift 2 2>/dev/null || shift $#
  done
  local _g="inngest_backstop_destroy_precondition" path cid
  case "$erasure" in
    ""|wipe) path=wipe ;;
    provider-only) path=provider ;;
    *) echo "${_g}: ABORT reason=erasure_unknown — erasure '${erasure}' is neither empty/wipe nor provider-only"; return 1 ;;
  esac
  if [[ "$path" == provider ]]; then
    [[ -z "$run" ]] || { echo "${_g}: ABORT reason=ambiguous_inputs — erasure=provider-only must not carry a wipe_run_id"; return 1; }
    if [[ ! "$clo" =~ ^https://github\.com/jikig-ai/soleur/issues/8285#issuecomment-([0-9]+)$ ]]; then
      echo "${_g}: ABORT reason=clo_ref_invalid — erasure=provider-only needs clo_attestation_ref to be exactly https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<id>"; return 1
    fi
    cid="${BASH_REMATCH[1]}"
    if [[ -z "$clofile" || ! -f "$clofile" ]] || ! jq -e --arg id "$cid" '(.id | tostring) == $id and (.issue_url | type == "string" and endswith("/issues/8285")) and (.author_association | type == "string") and (.body | type == "string")' "$clofile" >/dev/null 2>&1; then
      echo "${_g}: ABORT reason=clo_comment_unreadable — the GitHub API did not return comment ${cid} on #8285 (missing, not JSON, another comment or another issue)"; return 1
    fi
    jq -e '.author_association | IN("OWNER", "MEMBER", "COLLABORATOR")' "$clofile" >/dev/null 2>&1 \
      || { echo "${_g}: ABORT reason=clo_author_not_privileged — the attestation comment's author_association is not OWNER|MEMBER|COLLABORATOR"; return 1; }
    jq -e --arg v "$_IBRG_RETIRED_ID" '.body | test("(^|[^0-9])" + $v + "([^0-9]|$)")' "$clofile" >/dev/null 2>&1 \
      || { echo "${_g}: ABORT reason=clo_body_missing_volume — the attestation comment does not name volume ${_IBRG_RETIRED_ID}"; return 1; }
  else
    [[ -z "$clo" ]] || { echo "${_g}: ABORT reason=ambiguous_inputs — clo_attestation_ref requires erasure=provider-only"; return 1; }
    [[ "$run" =~ ^[0-9]+$ ]] || { echo "${_g}: ABORT reason=run_id_invalid — wipe_run_id must be the numeric id of the wipe dispatch"; return 1; }
  fi
  # The Hetzner-side re-check -- outside the wipe script's own diff.
  if [[ -z "$vol" || ! -f "$vol" ]] || ! jq -e '(.volume | type) == "object" and (.volume | has("server")) and (.volume.size | type) == "number" and (.volume.size > 0) and (.volume.size == (.volume.size | floor))' "$vol" >/dev/null 2>&1; then
    echo "${_g}: ABORT reason=volume_unreadable — the Hetzner body for volume ${_IBRG_RETIRED_ID} is missing, degraded or lacks server/size"; return 1
  fi
  [[ "$(jq -r '.volume.id | tostring' "$vol")" == "$_IBRG_RETIRED_ID" ]] || { echo "${_g}: ABORT reason=volume_identity_mismatch — Hetzner answered a volume other than ${_IBRG_RETIRED_ID}"; return 1; }
  if [[ "$(jq -r '.volume.server | type' "$vol")" != "null" ]]; then
    echo "${_g}: ABORT reason=still_attached — volume ${_IBRG_RETIRED_ID} still has an attachment (no live attachment may exist)"; return 1
  fi
  if [[ "$path" == provider ]]; then
    echo "${_g}: PASS — D4 provider-only erasure: volume detached; CLO attestation comment ${cid} is from a privileged author and names the volume (NO overwrite is evidenced; the record must say provider delete only)"
    return 0
  fi
  local size_bytes ev hres
  size_bytes=$(( $(jq -r '.volume.size' "$vol") * 1073741824 ))
  if ! ev="$(inngest_backstop_wipe_evidence_gate --rows-file "$rows" --nonce "$run" --volume-id "$_IBRG_RETIRED_ID" \
        --size-bytes "$size_bytes" --after-epoch "$after" --now "$now")"; then
    echo "$ev"; return 1
  fi
  # Corroboration by a party the ingest token does not reach: Hetzner's own action history for the volume.
  if [[ ! "$livesrv" =~ ^[0-9]+$ ]]; then echo "${_g}: ABORT reason=live_server_unreadable — the live inngest server id is unreadable ('${livesrv}')"; return 1; fi
  if [[ -z "$acts" || ! -f "$acts" ]] || ! jq -e '(.actions | type) == "array"' "$acts" >/dev/null 2>&1; then
    echo "${_g}: ABORT reason=actions_unreadable — the Hetzner action history for volume ${_IBRG_RETIRED_ID} is missing or has no actions array"; return 1
  fi
  hres="$(jq -r --argjson after "$after" --arg live "$livesrv" '
      def ep: (try ((tostring | .[:19]) | strptime("%Y-%m-%dT%H:%M:%S") | mktime) catch null);
      def srv: [(.resources // [])[] | select(.type == "server") | .id | select(. != null) | tostring];
      [ .actions[] | select(.status == "success") | {c: .command, f: (.finished | ep), s: srv} | select(.f != null) ] as $ok
      | [ $ok[] | select(.c == "attach_volume" and .f >= $after and (.s | any(. != $live))) ] as $att
      | if ($att | length) == 0 then "no_wipe_attach"
        elif ([ $ok[] | select(.c == "detach_volume" and .f >= ($att | map(.f) | min)) ] | length) == 0 then "no_wipe_detach"
        else "ok" end' "$acts" 2>/dev/null)" || hres=""
  case "$hres" in
    ok) ;;
    no_wipe_attach) echo "${_g}: ABORT reason=no_wipe_attach — Hetzner records no successful attach_volume of ${_IBRG_RETIRED_ID} to a server other than ${livesrv} since the wipe run started (a wipe row without it is unsupported)"; return 1 ;;
    no_wipe_detach) echo "${_g}: ABORT reason=no_wipe_detach — Hetzner records an attach but no successful detach_volume after it"; return 1 ;;
    *) echo "${_g}: ABORT reason=actions_unreadable — the Hetzner action history could not be evaluated"; return 1 ;;
  esac
  echo "${_g}: PASS — ${ev#*PASS — }; Hetzner records the wipe host's attach and a later detach; volume detached"
  return 0
}

# ── inngest_backstop_wipe_evidence_gate ─────────────────────────────────────────────
# The evidence funnel, shared by the wipe phase's bounded poll (volume still attached to the wipe
# host) and the destroy precondition (volume detached). Sequential filters over the Better Stack rows,
# so every criterion has its OWN reason: marker (anchored at the message start, a row that merely
# QUOTES the marker is not evidence) -> emitter (the host and shipper the wipe host's payload carries)
# -> nonce == the wipe dispatch's run id -> result=wiped readback=zero sig_after=none -> volume_id and
# size_bytes == Hetzner's -> timestamp not before the floor and not in the future. ANY row surviving
# every filter counts: a later `refused` row does not hide it, and neither does a `prior=blank` re-entry
# row (a re-run that found the device already blank is itself a `wiped` row and qualifies as evidence).
# Key=value tokens are FIRST-wins. The emitter and nonce checks make STALE or REPLAYED rows fail; the row
# is still SELF-ATTESTED (a holder of the shared ingest token could forge one), which is why the destroy
# precondition also requires Hetzner's action history. Guest-side logical erasure, not physical.
#   --rows-file F --nonce N --volume-id ID --size-bytes B --after-epoch E --now EPOCH
_IBRG_WIPE_HOST="soleur-inngest-backstop-wipe"
_IBRG_WIPE_SHIPPER="inngest-backstop-wipe"
# shellcheck disable=SC2016  # jq program text, not shell
_IBRG_WIPE_JQ_DEFS='
  def toks: split(" ") | map(select(contains("="))) | reduce .[] as $t ({}; ($t | index("=")) as $i | ($t[:$i]) as $k | if has($k) then . else .[$k] = $t[$i+1:] end);
  def epoch: (try ((.dt | tostring | sub("T"; " ") | .[:19]) | strptime("%Y-%m-%d %H:%M:%S") | mktime) catch null);
  def objs: [ split("\n")[] | select(length > 0) | (fromjson? // empty) | select(type == "object") ];
  def wrow: . as $o
    | (if (.raw | type) == "string" then (.raw | fromjson? // {}) else {} end) as $r
    | ((try ($r.message) catch null) // (try $o.message catch null)) as $m
    | select(($m | type) == "string" and ($m | startswith("SOLEUR_INNGEST_BACKSTOP_WIPE ")))
    | {e: ($o | epoch), f: ($m | toks), m: $m, h: (try $r.host catch null), sh: (try $r.shipper catch null)};
'
inngest_backstop_wipe_evidence_gate() {
  local rows="" run="" vid="" size_bytes="" after="" now="" a
  while [[ $# -gt 0 ]]; do
    a="$1"
    case "$a" in
      --rows-file) rows="${2-}" ;; --nonce) run="${2-}" ;; --volume-id) vid="${2-}" ;; --size-bytes) size_bytes="${2-}" ;;
      --after-epoch) after="${2-}" ;; --now) now="${2-}" ;;
      *) echo "inngest_backstop_wipe_evidence_gate: ABORT reason=usage — unknown option ${a}"; return 1 ;;
    esac
    shift 2 2>/dev/null || shift $#
  done
  local _g="inngest_backstop_wipe_evidence_gate"
  [[ "$run" =~ ^[0-9]+$ ]] || { echo "${_g}: ABORT reason=run_id_invalid — nonce must be the numeric id of the wipe dispatch"; return 1; }
  [[ "$vid" == "$_IBRG_RETIRED_ID" && "$size_bytes" =~ ^[1-9][0-9]*$ ]] || { echo "${_g}: ABORT reason=volume_mismatch — volume id/size to match are unreadable or not the retired volume"; return 1; }
  [[ "$after" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] || { echo "${_g}: ABORT reason=evidence_stale — the time floor or the clock is unreadable"; return 1; }
  if [[ -z "$rows" || ! -f "$rows" ]]; then echo "${_g}: ABORT reason=rows_unreadable — the evidence rows were not read"; return 1; fi
  local stages
  if ! stages="$(jq -R -s -r --arg run "$run" --arg vid "$_IBRG_RETIRED_ID" --arg sz "$size_bytes" --argjson after "$after" --argjson now "$now" \
      --arg eh "$_IBRG_WIPE_HOST" --arg es "$_IBRG_WIPE_SHIPPER" "${_IBRG_WIPE_JQ_DEFS}"'
      objs as $objs
      | ($objs | length) as $decoded
      | [ $objs[] | wrow ] as $s0
      | ($s0 | map(select(.h == $eh and .sh == $es))) as $se
      | ($se | map(select(.f.nonce == $run))) as $s1
      | ($s1 | map(select(.f.result == "wiped" and .f.readback == "zero" and .f.sig_after == "none"))) as $s2
      | ($s2 | map(select(.f.volume_id == $vid and .f.size_bytes == $sz))) as $s3
      | ($s3 | map(select(.e != null and .e >= $after and .e <= ($now + 300)))) as $s4
      | "\($decoded) \($s0 | length) \($se | length) \($s1 | length) \($s2 | length) \($s3 | length) \($s4 | length)"
    ' "$rows" 2>/dev/null)"; then
    echo "${_g}: ABORT reason=rows_unreadable — the evidence rows could not be decoded"; return 1
  fi
  local d s0 se s1 s2 s3 s4
  read -r d s0 se s1 s2 s3 s4 <<<"$stages"
  if [[ ! "${d}${s0}${se}${s1}${s2}${s3}${s4}" =~ ^[0-9]+$ ]]; then echo "${_g}: ABORT reason=rows_unreadable — the evidence funnel did not evaluate"; return 1; fi
  if [[ "$d" -eq 0 && -s "$rows" ]]; then echo "${_g}: ABORT reason=rows_unreadable — the evidence file has content but nothing decodes as a row"; return 1; fi
  if   [[ "$s0" -eq 0 ]]; then echo "${_g}: ABORT reason=evidence_absent — no SOLEUR_INNGEST_BACKSTOP_WIPE row ($d decoded line(s))"; return 1
  elif [[ "$se" -eq 0 ]]; then echo "${_g}: ABORT reason=emitter_mismatch — $s0 wipe row(s), none posted by host ${_IBRG_WIPE_HOST} / shipper ${_IBRG_WIPE_SHIPPER}"; return 1
  elif [[ "$s1" -eq 0 ]]; then echo "${_g}: ABORT reason=nonce_mismatch — $se wipe row(s) from the wipe host, none carrying nonce=${run}"; return 1
  elif [[ "$s2" -eq 0 ]]; then echo "${_g}: ABORT reason=not_wiped — no row for nonce ${run} says result=wiped readback=zero sig_after=none"; return 1
  elif [[ "$s3" -eq 0 ]]; then echo "${_g}: ABORT reason=volume_mismatch — no wiped row matches volume_id=${_IBRG_RETIRED_ID} and size_bytes=${size_bytes} (Hetzner)"; return 1
  elif [[ "$s4" -eq 0 ]]; then echo "${_g}: ABORT reason=evidence_stale — the wiped row is older than the wipe run's start or dated in the future"; return 1
  fi
  echo "${_g}: PASS — wiped row bound to nonce ${run}: readback=zero sig_after=none volume_id=${vid} size_bytes=${size_bytes}, after the floor"
  return 0
}

# ── inngest_backstop_wipe_nonce_rows ────────────────────────────────────────────────
# The poll's diagnostic read: prints the `message` of every wipe-marker row bearing --nonce, one per
# line, and nothing else, so a `result=refused reason=<guard>` row can end the poll at once and a timeout
# can name what the host DID say. It is not evidence (no emitter/result/size check): only the verdict
# above is.
#   --rows-file F --nonce N
inngest_backstop_wipe_nonce_rows() {
  local rows="" run="" a
  while [[ $# -gt 0 ]]; do
    a="$1"
    case "$a" in
      --rows-file) rows="${2-}" ;; --nonce) run="${2-}" ;;
      *) echo "inngest_backstop_wipe_nonce_rows: ABORT reason=usage — unknown option ${a}"; return 1 ;;
    esac
    shift 2 2>/dev/null || shift $#
  done
  [[ "$run" =~ ^[0-9]+$ ]] || { echo "inngest_backstop_wipe_nonce_rows: ABORT reason=run_id_invalid — nonce must be numeric"; return 1; }
  if [[ -z "$rows" || ! -f "$rows" ]]; then echo "inngest_backstop_wipe_nonce_rows: ABORT reason=rows_unreadable — the rows were not read"; return 1; fi
  jq -R -s -r --arg run "$run" "${_IBRG_WIPE_JQ_DEFS}"'objs[] | wrow | select(.f.nonce == $run) | .m' "$rows" 2>/dev/null \
    || { echo "inngest_backstop_wipe_nonce_rows: ABORT reason=rows_unreadable — the rows could not be decoded"; return 1; }
}
