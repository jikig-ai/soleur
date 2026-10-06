#!/usr/bin/env bash
# Test suite for tests/scripts/lib/web-host-rebirth-gate.sh (#9372, ADR-263 addendum).
#
# The gate grades the two plans of the single-use web-2 volume rebirth: `pre` (before anything is
# touched) and `post` (after the empty volume was deleted and forgotten). It is the sibling of
# web-host-birth-gate.sh (create-only) and web-host-replace-gate.sh (volume survives) and borrows
# neither allow-set. The property that protects production is the REJECT set, so nearly every row
# below is a refusal, and the mutation battery at the end proves each load-bearing arm by removing
# it from a COPY of the gate and requiring the battery to go red.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): tests/scripts/fixtures/web-host-rebirth/{pre,post}.json.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/web-host-rebirth-gate.sh"
PREAMBLE="${ROOT}/tests/scripts/lib/plan-gate-preamble.sh"
FIX="${ROOT}/tests/scripts/fixtures/web-host-rebirth"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SID=1001
VID=106466179
KEY="web-2"

# battery <gate-file> — runs every assertion against the given gate file and prints one line per FAILED
# assertion name ("FAILED <name>"); prints "RAN <n>" last. Used on the real gate (must print no FAILED)
# and on mutated copies (must print at least one FAILED).
battery() {
  local gate="$1" n=0 out rc
  # shellcheck disable=SC1090
  source "$PREAMBLE"
  # shellcheck disable=SC1090
  source "$gate"

  # mut <fixture> <jq-expr> -> path of a mutated copy
  mut() { local f="$TMP/m.$RANDOM.$RANDOM.json"; jq "$2" "$FIX/$1.json" > "$f"; printf '%s' "$f"; }

  # expect <name> <want-rc> <want-substring|-> <mode> <plan> [key] [sid] [vid]
  expect() {
    local name="$1" want="$2" sub="$3" mode="$4" plan="$5" key="${6-$KEY}" sid="${7-$SID}" vid="${8-$VID}"
    n=$((n + 1))
    out="$(web_host_rebirth_gate "$mode" "$plan" "$key" "$sid" "$vid" 2>&1)"; rc=$?
    if [[ "$rc" -ne "$want" ]]; then printf 'FAILED %s (rc=%s want=%s) %s\n' "$name" "$rc" "$want" "${out:0:200}"; return; fi
    if [[ "$sub" != "-" && "$out" != *"$sub"* ]]; then printf 'FAILED %s (rc ok, output lacks %q) %s\n' "$name" "$sub" "${out:0:200}"; fi
  }

  local P="$FIX/pre.json" Q="$FIX/post.json" f

  # ---- must PASS
  expect "pass: canonical pre"  0 "PASS" pre  "$P"
  expect "pass: canonical post" 0 "PASS" post "$Q"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-2\"]" or .address=="hcloud_server_network.web[\"web-2\"]") | .change) |= (.actions=["create"] | .before=null)')"
  expect "pass: post with the server already absent from state (create alone)" 0 "PASS" post "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before={"id":"777","name":"soleur-web-platform-data-web-2","size":20,"labels":{"app":"soleur-web-platform"}} | .after=.before)')"
  expect "pass: post-heal with the raw volume already created" 0 "PASS" post-heal "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_volume_attachment.workspaces[\"web-2\"]") | .change) |= (.actions=["create"] | .before=null)')"
  expect "pass: pre after a completed detach (attachment create alone)" 0 "PASS" pre "$f"

  # ---- web-1 and argument refusals
  expect "refuse: web-1 by name (first statement)" 1 "REFUSES" pre "$P" "web-1"
  expect "refuse: web-1 by name with a nonexistent plan (refusal precedes everything)" 1 "REFUSES" post "$TMP/none.json" "web-1"
  expect "refuse: missing host key" 1 "no host key" pre "$P" ""
  expect "refuse: unknown mode" 1 "mode" bogus "$P"
  expect "refuse: non-numeric server id" 1 "server id" pre "$P" "$KEY" "abc"
  expect "refuse: non-numeric volume id" 1 "volume id" pre "$P" "$KEY" "$SID" "12x"
  expect "refuse: missing plan file" 1 "not found" pre "$TMP/none.json"
  f="$(mut pre '.resource_changes=null')"
  expect "refuse: resource_changes null" 1 "ABORT" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-1\"]") | .change.actions) = []')"
  expect "refuse: an actions:[] entry (web-1 server, undecidable)" 1 "ABORT" pre "$f"

  # ---- the volume can never be deleted, forgotten or replaced
  for m in pre post; do
    for a in '["delete"]' '["forget"]' '["delete","create"]'; do
      f="$(mut $m '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions='"$a"' | .before={"id":"106466179","name":"soleur-web-platform-data-web-2","size":20,"labels":{"app":"soleur-web-platform"}})')"
      expect "refuse: $m plan with the volume $a" 1 "volume" "$m" "$f"
    done
  done

  # ---- the volume must be born raw, once, and be the right volume
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.after) += {"format":"ext4"}')"
  expect "refuse: post volume born ext4" 1 "format" post "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.after_unknown) += {"format":true}')"
  expect "refuse: post volume format unknown" 1 "format" post "$f"
  f="$(mut post '.resource_changes += [.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]")]')"
  expect "refuse: post with two volume entries" 1 "entries" post "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.after.size) = 40')"
  expect "refuse: post volume size changed" 1 "size" post "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.after.labels) = {"app":"other"}')"
  expect "refuse: post volume labels changed" 1 "labels" post "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.after.name) = "soleur-web-platform-data"')"
  expect "refuse: post volume carries web-1's name" 1 "name" post "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.actions) = ["update"]')"
  expect "refuse: pre plan with the volume not a no-op" 1 "volume" pre "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before=.after)')"
  expect "refuse: post plan with the volume a no-op (plain post, not post-heal)" 1 "volume" post "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before={"id":"106466179","name":"soleur-web-platform-data-web-2","size":20,"labels":{"app":"soleur-web-platform"}} | .after=.before)')"
  expect "refuse: post-heal where the surviving volume IS the pinned one" 1 "pinned" post-heal "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before={"id":"777","format":"ext4","name":"soleur-web-platform-data-web-2","size":20,"labels":{"app":"soleur-web-platform"}} | .after=.before)')"
  expect "refuse: post-heal where the surviving volume is ext4" 1 "format" post-heal "$f"

  # ---- every destroy is pinned to a physical id
  expect "refuse: server id pin differs from the plan" 1 "pin" pre "$P" "$KEY" 4242
  expect "refuse: volume id pin differs from the plan" 1 "pin" pre "$P" "$KEY" "$SID" 4242
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-2\"]") | .change.before.name) = "soleur-web-1"')"
  expect "refuse: server destroy whose before.name is not soleur-web-2" 1 "pin" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_server_network.web[\"web-2\"]") | .change.before.server_id) = 9')"
  expect "refuse: NIC destroy for another server" 1 "pin" pre "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_server_network.web[\"web-2\"]") | .change.before.server_id) = 9')"
  expect "refuse: NIC destroy for another server (post)" 1 "pin" post "$f"

  # ---- scope: nothing else may change
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-1\"]") | .change.actions) = ["update"]')"
  expect "refuse: web-1 server update (reboot class)" 1 "reboot" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-1\"]") | .change.actions) = ["delete","create"]')"
  expect "refuse: web-1 server replace" 1 "out-of-scope" pre "$f"
  f="$(mut post '.resource_changes += [{"address":"cloudflare_record.app","type":"cloudflare_record","change":{"actions":["update"],"before":{},"after":{},"after_unknown":{}}}]')"
  expect "refuse: an extra address changes" 1 "out-of-scope" post "$f"
  for a in create update delete; do
    f="$(mut post '(.resource_changes[] | select(.address=="random_password.workspaces_luks_web") | .change.actions) = ["'"$a"'"]')"
    expect "refuse: passphrase-pair address with $a" 1 "out-of-scope" post "$f"
  done
  f="$(mut post '(.resource_changes[] | select(.address=="doppler_secret.workspaces_luks_web_key") | .change.actions) = ["update"]')"
  expect "refuse: web-class key secret updated" 1 "out-of-scope" post "$f"
  f="$(mut post '.resource_changes += [{"address":"cloudflare_record.app","type":"cloudflare_record","change":{"actions":["forget"],"before":{},"after":null,"after_unknown":{}}}]')"
  expect "refuse: forget at a non-volume address" 1 "forget" post "$f"
  f="$(mut post '.resource_changes += [.resource_changes[] | select(.address=="hcloud_server.web[\"web-2\"]") | .address="hcloud_server.web[\"web-3\"]"]')"
  expect "refuse: a second server create" 1 "server" post "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_firewall_attachment.web") | .change.actions) = ["delete"]')"
  expect "refuse: firewall attachment deleted" 1 "firewall" pre "$f"

  # ---- requirements, not only prohibitions
  for a in 'hcloud_server_network.web["web-2"]' 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_firewall_attachment.web' 'hcloud_server.web["web-2"]'; do
    f="$(mut post 'del(.resource_changes[] | select(.address=="'"${a//\"/\\\"}"'"))')"
    expect "refuse: required member missing ($a)" 1 "missing" post "$f"
  done


  # ---- the allow-list is exact: a narrower action set than the contract is a violation too (a delete ALONE is not a replace)
  for addr in 'hcloud_server.web[\"web-2\"]' 'hcloud_server_network.web[\"web-2\"]' 'hcloud_volume_attachment.workspaces[\"web-2\"]'; do
    f="$(mut pre '(.resource_changes[] | select(.address=="'"$addr"'") | .change.actions) = ["delete"]')"
    expect "refuse: pre plan with a delete ALONE at $addr" 1 "unexpected action" pre "$f"
  done
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume_attachment.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before={"volume_id":106466179,"server_id":1001} | .after=.before)')"
  expect "refuse: post plan with the attachment a no-op (it must be created after the volume was recreated)" 1 "unexpected action" post "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["create"] | .before=null)')"
  expect "refuse: pre plan that CREATES the volume (the old one must be a no-op in pre)" 1 "unexpected action" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_firewall_attachment.web") | .change.actions) = ["no-op"]')"
  expect "refuse: firewall attachment a no-op (the replaced server must re-attach)" 1 "unexpected action" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_firewall_attachment.web") | .change.actions) = ["delete","create"]')"
  expect "refuse: firewall attachment replaced (it may only update)" 1 "unexpected action" pre "$f"

  # ---- every pin is independent: only ONE field wrong, everything else correct
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-2\"]") | .change.before.id) = "9999"')"
  expect "refuse: ONLY the server before.id differs (NIC and attachment still match)" 1 "pin: server destroy" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_volume_attachment.workspaces[\"web-2\"]") | .change.before.volume_id) = 4242')"
  expect "refuse: ONLY the attachment before.volume_id differs" 1 "pin: attachment destroy" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_volume_attachment.workspaces[\"web-2\"]") | .change.before.server_id) = 4242')"
  expect "refuse: ONLY the attachment before.server_id differs" 1 "pin: attachment destroy" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.before.id) = "4242"')"
  expect "refuse: ONLY the live volume's before.id differs from the pinned volume (pre)" 1 "pin: the live volume" pre "$f"

  # ---- cardinality
  f="$(mut post '.resource_changes += [.resource_changes[] | select(.address=="hcloud_volume_attachment.workspaces[\"web-2\"]")]')"
  expect "refuse: two attachment entries (exactly one is required)" 1 "entries=2" post "$f"
  f="$(mut post '.resource_changes += [.resource_changes[] | select(.address=="hcloud_server_network.web[\"web-2\"]")]')"
  expect "refuse: two NIC entries" 1 "entries=2" post "$f"

  # ---- post-heal: the surviving volume is checked for name, size and labels like a freshly planned one
  hv='{"id":"777","name":"soleur-web-platform-data-web-2","size":20,"labels":{"app":"soleur-web-platform"}}'
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before='"$hv"' | .after=.before | .before.name="soleur-web-platform-data")')"
  expect "refuse: post-heal surviving volume carries web-1's name" 1 "name" post-heal "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before='"$hv"' | .after=.before | .before.size=40)')"
  expect "refuse: post-heal surviving volume has the wrong size" 1 "size" post-heal "$f"
  f="$(mut post '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["no-op"] | .before='"$hv"' | .after=.before | .before.labels={"app":"x"})')"
  expect "refuse: post-heal surviving volume has the wrong labels" 1 "labels" post-heal "$f"

  # ---- jq errors inside an arm fail CLOSED (a malformed entry is a violation, never a silent pass)
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-2\"]") | .change.before) = "not-an-object"')"
  expect "refuse: a server entry whose before is a string (pin arm cannot evaluate it)" 1 "jq-error: pin-server" pre "$f"
  f="$(mut pre '(.resource_changes[] | select(.address=="hcloud_volume_attachment.workspaces[\"web-2\"]") | .change.before) = "not-an-object"')"
  expect "refuse: an attachment entry whose before is a string (pin arm cannot evaluate it)" 1 "jq-error: pin-volume" pre "$f"


  # ---- resume mode: a re-dispatch after the rebirth ran may only ADD what a partly failed apply left missing
  local R="$FIX/resume.json"
  expect "pass: canonical resume plan (everything already applied; all no-ops)" 0 "PASS" resume "$R" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_server_network.web[\"web-2\"]") | .change) |= (.actions=["create"] | .before=null)')"
  expect "pass: resume plan that creates a missing private NIC" 0 "PASS" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_volume_attachment.workspaces[\"web-2\"]") | .change) |= (.actions=["create"] | .before=null)')"
  expect "pass: resume plan that re-creates a missing volume attachment" 0 "PASS" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_firewall_attachment.web") | .change.actions) = ["update"]')"
  expect "pass: resume plan that updates the firewall attachment" 0 "PASS" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-2\"]") | .change.actions) = ["delete","create"]')"
  expect "refuse: a resume plan that REPLACES the server" 1 "unexpected action" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_server.web[\"web-2\"]") | .change.actions) = ["update"]')"
  expect "refuse: a resume plan that updates the server (reboot class)" 1 "reboot" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change) |= (.actions=["create"] | .before=null | .after={"name":"soleur-web-platform-data-web-2","size":20,"labels":{"app":"soleur-web-platform"}})')"
  expect "refuse: a resume plan that CREATES a volume (a second raw volume)" 1 "unexpected action" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.actions) = ["delete"]')"
  expect "refuse: a resume plan that deletes the volume" 1 "unexpected action" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.before.id) = "106466179"')"
  expect "refuse: a resume plan whose surviving volume IS the pinned plaintext one" 1 "pinned" resume "$f" "$KEY" 2002 "$VID"
  f="$(mut resume '(.resource_changes[] | select(.address=="hcloud_volume.workspaces[\"web-2\"]") | .change.before.format) = "ext4"')"
  expect "refuse: a resume plan whose surviving volume is formatted ext4" 1 "format" resume "$f" "$KEY" 2002 "$VID"
  expect "refuse: a resume plan for a server id that is not the plan's" 1 "pin: server" resume "$R" "$KEY" 4242 "$VID"
  expect "refuse: the ordinary post fixture graded as resume (it replaces the server and creates the volume)" 1 "unexpected action" resume "$Q" "$KEY" 2002 "$VID"
  expect "refuse: web-1 by name in resume mode" 1 "REFUSES" resume "$R" "web-1" 2002 "$VID"

  printf 'RAN %s\n' "$n"
}

passes=0; fails=0
report="$(battery "$GATE" 2>&1)"
while IFS= read -r line; do
  case "$line" in
    FAILED*) fails=$((fails + 1)); printf '  FAIL %s\n' "${line#FAILED }" ;;
    RAN*)    ran="${line#RAN }" ;;
    *)       printf '       %s\n' "$line" ;;
  esac
done <<<"$report"
ran="${ran:-0}"
passes=$((ran - fails))
printf '\nreal gate: %s assertions, %s passed, %s failed\n' "$ran" "$passes" "$fails"

# ---- harness rows: the suite cannot go quiet
FLOOR=80
if [[ ! -f "$GATE" ]]; then echo "  FAIL gate file missing: $GATE"; fails=$((fails + 1)); fi
if [[ "$ran" -lt "$FLOOR" ]]; then echo "  FAIL assertion floor: ran ${ran} < ${FLOOR} (a deleted or skipped row must not pass)"; fails=$((fails + 1)); fi
if [[ ! -s "$FIX/pre.json" || ! -s "$FIX/post.json" ]]; then echo "  FAIL canonical fixtures missing"; fails=$((fails + 1)); fi

# ---- the first executable statement of the gate function is the by-name web-1 refusal
first_stmt="$(awk '/^web_host_rebirth_gate\(\)/{f=1;next} f&&/^[[:space:]]*(local |#|$)/{next} f{print;exit}' "$GATE" 2>/dev/null)"
if [[ "$first_stmt" != *'_WEB_HOST_REBIRTH_LUKS_PINNED_KEY'* ]]; then
  echo "  FAIL the by-name web-1 refusal is not the gate's first executable statement (got: ${first_stmt})"; fails=$((fails + 1))
else echo "  ok   the by-name web-1 refusal is first"; fi

# ---- the pinned key and the replace gate's key stay in lockstep, and the volume size follows variables.tf
want_key="$(sed -nE 's/^_WEB_HOST_REPLACE_LUKS_PINNED_KEY="([^"]+)".*/\1/p' "${ROOT}/tests/scripts/lib/web-host-replace-gate.sh" | head -1)"
have_key="$(sed -nE 's/^_WEB_HOST_REBIRTH_LUKS_PINNED_KEY="([^"]+)".*/\1/p' "$GATE" | head -1)"
if [[ -z "$want_key" || "$want_key" != "$have_key" ]]; then echo "  FAIL pinned key drift (replace gate '${want_key}', rebirth gate '${have_key}')"; fails=$((fails + 1)); else echo "  ok   pinned key matches the replace gate"; fi
tf_size="$(awk '/^variable "volume_size"/{f=1} f&&/default/{gsub(/[^0-9]/,"",$3); print $3; exit}' "${ROOT}/apps/web-platform/infra/variables.tf")"
gate_size="$(sed -nE 's/^_WEB_HOST_REBIRTH_VOLUME_SIZE=([0-9]+).*/\1/p' "$GATE" | head -1)"
if [[ -z "$tf_size" || "$tf_size" != "$gate_size" ]]; then echo "  FAIL volume size drift (variables.tf '${tf_size}', gate '${gate_size}')"; fails=$((fails + 1)); else echo "  ok   volume size matches variables.tf"; fi

# ---- the raw-volume verdict stays the same predicate set as the birth gate's (parity row; the birth gate cannot be sourced for it)
parity_ok=1
for frag in '($c.after | type) != "object"' '$c.after_unknown == null' '(.format // false) != false' '($c.after | has("format")) and ($c.after.format != null)'; do
  grep -qF -- "$frag" "${ROOT}/tests/scripts/lib/web-host-birth-gate.sh" || { echo "  FAIL birth gate lost the predicate: $frag"; parity_ok=0; }
  grep -qF -- "$frag" "$GATE" || { echo "  FAIL rebirth gate lacks the birth gate's predicate: $frag"; parity_ok=0; }
done
if [[ "$parity_ok" -eq 1 ]]; then echo "  ok   raw-volume predicates match the birth gate"; else fails=$((fails + 1)); fi

# ---- measured against the destroy-guard filter (the contract the apply path also runs): the canonical plans must read as
# a server+NIC replace with NO volume destroy, no passphrase rotation, no undecidable entry, and no reboot update.
JQF="${ROOT}/tests/scripts/lib/destroy-guard-filter-web-platform.jq"
for m in pre post; do
  c="$(jq -c -f "$JQF" < "$FIX/$m.json" 2>/dev/null)"
  for kv in '"web2_volume_destroyed":0' '"luks_passphrase_rotations":0' '"undecidable_entries":0' '"reboot_updates":0' '"host_creates":1'; do
    if [[ "$c" != *"$kv"* ]]; then echo "  FAIL destroy-guard reading of the ${m} fixture lacks ${kv}: ${c}"; fails=$((fails + 1)); fi
  done
done
echo "  ok   destroy-guard readings measured on both fixtures"

# ---- mutation battery: remove each load-bearing arm from a COPY; the battery must go red
mutate() { # <name> <sed-script>
  local name="$1" script="$2" copy="$TMP/gate.mut.sh" after
  cp "$GATE" "$copy"
  sed -i -E "$script" "$copy"
  if cmp -s "$GATE" "$copy"; then echo "  FAIL mutation '${name}' did not change the gate (the anchor drifted)"; fails=$((fails + 1)); return; fi
  after="$(battery "$copy" 2>&1 | grep -c '^FAILED')"
  if [[ "$after" -gt 0 ]]; then echo "  ok   mutation killed: ${name} (${after} assertions went red)"
  else echo "  FAIL mutation SURVIVED: ${name}"; fails=$((fails + 1)); fi
}
mutate "web-1 refusal removed"            's/^(\s*)if \[\[ "\$host_key" == "\$_WEB_HOST_REBIRTH_LUKS_PINNED_KEY" \]\]; then/\1if false; then/'
mutate "classifiability check removed"    's/^(\s*)plan_gate_assert_classifiable .*/\1:/'
mutate "server-id pin removed"            's/^(\s*)[^#]*(# GATE:PIN-SERVER)$/\1: \2/'
mutate "volume-id pin removed"            's/^(\s*)[^#]*(# GATE:PIN-VOLUME)$/\1: \2/'
mutate "allow-set check removed"          's/^(\s*)[^#]*(# GATE:ALLOW-SET)$/\1: \2/'
mutate "raw-volume check removed"         's/^(\s*)[^#]*(# GATE:RAW-VOLUME)$/\1: \2/'
mutate "requirement arms removed"         's/^(\s*)[^#]*(# GATE:REQUIRED)$/\1: \2/'
mutate "pin-server jq failure no longer fails closed"  's/\{ echo "jq-error: pin-server"; return 0; \}/{ return 0; }/'
mutate "pin-volume jq failure no longer fails closed"  's/\{ echo "jq-error: pin-volume"; return 0; \}/{ return 0; }/'
mutate "reboot counter removed"           's/^(\s*)[^#]*(# GATE:REBOOT)$/\1: \2/'

echo
if [[ "$fails" -gt 0 ]]; then echo "web-host-rebirth-gate: ${fails} FAILED"; exit 1; fi
echo "web-host-rebirth-gate: all assertions and mutations passed"
