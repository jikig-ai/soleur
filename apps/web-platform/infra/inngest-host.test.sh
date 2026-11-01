#!/usr/bin/env bash
#
# Drift guard for the dedicated Inngest singleton host (#6178, ADR-100). Asserts the
# load-bearing security/correctness invariants of inngest-host.tf + cloud-init-inngest.yml:
#   - FRESH signing/event keys (AC-KEYROTATE) — NOT reused from the co-located inngest.tf.
#   - Secrets on a SEPARATE Doppler PROJECT `soleur-inngest` (AC3), not a `prd` branch config.
#   - hcloud_firewall.inngest is deny-all-public (zero inbound); nftables (not the cloud
#     firewall) scopes :8288/:8289 to web-host IPs only, dropping git-data/.20 + registry/.30.
#   - Guard 1 (#8754): the server is BORN with that firewall (firewall_ids), and no attachment
#     binds it anywhere in the root.
#   - NO lifecycle.ignore_changes=[user_data] (maintenance-window force-replace, ADR-100).
#   - arm64 inngest-CLI SHA override (the amd64 image-env SHA would fail the arm64 verify).
#   - Vector WIRED on this arm64 host (arm64 build + isolated-project token, #6197).
#
# Run: bash apps/web-platform/infra/inngest-host.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_TF="${DIR}/inngest-host.tf"
CLOUD_INIT="${DIR}/cloud-init-inngest.yml"
INNGEST_TF="${DIR}/inngest.tf"
VECTOR_TF="${DIR}/vector.tf"
BOOTSTRAP="${DIR}/inngest-bootstrap.sh"
VARIABLES_TF="${DIR}/variables.tf"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

for f in "$HOST_TF" "$CLOUD_INIT" "$INNGEST_TF" "$VECTOR_TF" "$BOOTSTRAP" "$VARIABLES_TF"; do
  [ -f "$f" ] || { echo "FAIL: required file not found: $f" >&2; exit 1; }
done

# 1. FRESH keys (AC-KEYROTATE) — the dedicated resources exist AND are distinct from the
#    co-located inngest.tf keys. A reuse would sign the new boundary with the old key (SEC-H3).
grep -qE 'resource "random_id" "inngest_signing_key_dedicated"' "$HOST_TF" \
  && grep -qE 'resource "random_id" "inngest_event_key_dedicated"' "$HOST_TF" \
  && grep -qE 'resource "random_password" "inngest_redis_password_dedicated"' "$HOST_TF" \
  && pass || fail "fresh dedicated signing/event/redis key resources present"
# The dedicated signing secret must reference the DEDICATED key, never the co-located _prd one.
# Strip COMMENT lines first — the header comments reference the co-located key BY NAME as the
# thing NOT reused (a bare grep would false-match that prose).
if grep -qE 'random_id\.inngest_signing_key_dedicated\.hex' "$HOST_TF" \
   && ! grep -vE '^[[:space:]]*#' "$HOST_TF" | grep -cE 'random_id\.inngest_(signing|event)_key_prd' >/dev/null; then
  pass
else
  fail "dedicated secrets reference the dedicated keys, not the co-located _prd keys"
fi

# 1b. (#6178, split by ADR-282 addendum 2026-10-30 #9927 item 4) The credential is SPLIT.
#     - doppler_service_token.inngest (the BOOT token; both on-host copies) is access = "read".
#     - doppler_service_token.inngest_flip (the FLIP token) is access = "read/write", named
#       "inngest-flip", and is read only by inngest-cutover-flip.service through the cloud-init
#       drop-in (inngest-flip-token.test.sh proves the resolution; this block proves the grant).
#     The cutover flip FSM (inngest-cutover-flip.sh:flag_set) advances INNGEST_CUTOVER_FLIP on
#     soleur-inngest/prd via `doppler secrets set`; that write must run under a read/write token,
#     and every OTHER consumer must hold a read-only one.
#     Extract each value from its OWN resource block (block-scoped awk, exits at `^}`), skipping
#     in-block comment lines and requiring the attribute at STATEMENT position, so an in-block
#     decoy comment (`# access = "read/write"`) above the real attribute cannot satisfy it and
#     the first block's attributes cannot leak into the second. The resource anchor includes the
#     closing quote: `"inngest"` is a prefix of nothing here, and `"inngest_flip"` never matches it.
tok_attr() { # $1 resource label  $2 attribute
  awk -v lbl="$1" -v attr="$2" '
    index($0, "resource \"doppler_service_token\" \"" lbl "\" {") == 1 { inblk=1; next }
    inblk && /^[[:space:]]*#/ { next }
    inblk && $0 ~ "^[[:space:]]*" attr "[[:space:]]*=" { gsub(/[",]/,""); print $NF; exit }
    inblk && /^}/ { exit }
  ' "$HOST_TF"
}
BOOT_ACCESS="$(tok_attr inngest access)"
[[ "$BOOT_ACCESS" == "read" ]] \
  && pass || fail "doppler_service_token.inngest (the boot token) access must be 'read' (got '${BOOT_ACCESS:-<none>}'): a leak of the boot token must not be able to overwrite the LUKS passphrase pair (ADR-282 addendum, #9927 item 4)"
FLIP_ACCESS="$(tok_attr inngest_flip access)"
[[ "$FLIP_ACCESS" == "read/write" ]] \
  && pass || fail "doppler_service_token.inngest_flip access must be 'read/write' so the flip FSM can write INNGEST_CUTOVER_FLIP (got '${FLIP_ACCESS:-<none>}')"
FLIP_NAME="$(tok_attr inngest_flip name)"
[[ "$FLIP_NAME" == "inngest-flip" ]] \
  && pass || fail "doppler_service_token.inngest_flip name must be 'inngest-flip' (got '${FLIP_NAME:-<none>}')"
# The flip token lives on the same isolated project and config as the boot token, never elsewhere.
[[ "$(tok_attr inngest_flip project)" == "$(tok_attr inngest project)" && -n "$(tok_attr inngest_flip project)" ]] \
  && [[ "$(tok_attr inngest_flip config)" == "$(tok_attr inngest config)" && -n "$(tok_attr inngest_flip config)" ]] \
  && pass || fail "doppler_service_token.inngest_flip must name the same project and config as doppler_service_token.inngest"
# The templatefile map hands the flip key to the template as its own variable.
grep -vE '^[[:space:]]*#' "$HOST_TF" | grep -qE 'doppler_flip_token[[:space:]]*=[[:space:]]*doppler_service_token\.inngest_flip\.key' \
  && pass || fail "the templatefile map must pass doppler_flip_token = doppler_service_token.inngest_flip.key"
# Cross-check: the flip script's flag_set genuinely writes under the AMBIENT env (the flip unit's
# drop-in makes the ambient DOPPLER_TOKEN the flip token; inngest-flip-token.test.sh section R
# proves which token that is). If flag_set ever grows an explicit --token, the premise must be
# re-derived rather than trusted. Scope to the WHOLE flag_set function body (awk between
# `flag_set() {` and the closing `}`), not a single line — the real write spans two physical
# lines (`doppler secrets set ... \` then `  --project ... --silent`), so a --token added on the
# continuation line would evade a line-scoped grep.
FLAG_SET_BODY="$(awk '/^flag_set\(\)[[:space:]]*\{/{i=1} i{print} i&&/^\}/{exit}' "${DIR}/inngest-cutover-flip.sh")"
printf '%s\n' "$FLAG_SET_BODY" | grep -cE 'doppler secrets set INNGEST_CUTOVER_FLIP' >/dev/null \
  && ! printf '%s\n' "$FLAG_SET_BODY" | grep -cE -- >/dev/null '--token' \
  && pass || fail "flip flag_set must write INNGEST_CUTOVER_FLIP under the ambient token (no explicit --token anywhere in the function body) — the ambient token is whichever the flip unit's EnvironmentFile order yields (inngest-flip-token.test.sh section R), so an explicit --token would make that proof test the wrong credential"

# 2. Separate Doppler PROJECT (AC3), not a prd branch config.
grep -qE 'resource "doppler_project" "inngest"' "$HOST_TF" \
  && grep -qE 'name[[:space:]]*=[[:space:]]*"soleur-inngest"' "$HOST_TF" \
  && pass || fail "separate soleur-inngest Doppler project declared"
# Every dedicated doppler_secret targets that project (never a `config = "prd_inngest"` branch).
if grep -qE 'config[[:space:]]*=[[:space:]]*"prd_inngest"' "$HOST_TF"; then
  fail "dedicated secrets must NOT use a prd_inngest branch config (non-isolating, #6122)"
else
  pass
fi

# 3. Deny-all-public firewall (zero inbound rules) — intra-subnet is open by membership;
#    signature-verify is the /api/inngest boundary; nftables scopes the control API.
if awk '/resource "hcloud_firewall" "inngest"/{f=1} f&&/^}/{f=0} f' "$HOST_TF" | grep -cE 'rule[[:space:]]*\{|direction[[:space:]]*=[[:space:]]*"in"' >/dev/null; then
  fail "hcloud_firewall.inngest must have ZERO inbound rules (deny-all-public)"
else
  pass
fi

# 3b. GUARD 1 (#8754, ADR-100 2026-09-25 addendum) — the inngest server is BORN with the deny-all
#     firewall. `firewall_ids` is sent inside ServerCreate, so the firewall is on the host before
#     first boot, on every birth and every -replace. `firewall_ids` is Optional+Computed: deleting
#     the line plans NOTHING and detaches nothing, so no plan-level check sees the regression. This
#     guard is what does. Property, over every *.tf of the root after HCL comment stripping:
#       (a) exactly ONE `resource "hcloud_server" "inngest"` header, and its block sets
#           firewall_ids to EXACTLY [hcloud_firewall.inngest.id] (any layout), with neither
#           ignore_remote_firewall_ids nor an ignore_changes that covers firewall_ids;
#       (b) hcloud_firewall.inngest stays deny-all: exactly one header, no `rule` (static or
#           dynamic, either direction — an outbound rule would dark-boot the host) and no apply_to;
#       (c) NOTHING else binds either end: no hcloud_firewall_attachment references
#           hcloud_firewall.inngest or hcloud_server.inngest, none is named "inngest", no other
#           firewall references hcloud_server.inngest, no locals block references
#           hcloud_firewall.inngest, and no `data "hcloud_firewall(s)"` exists;
#       (d) no override / JSON config file touches hcloud_server or hcloud_firewall (terraform
#           merges those behind the .tf text this guard reads);
#       (e) exactly one `removed { from = hcloud_firewall_attachment.inngest … }`, forgetting
#           (destroy = false), in any file and in either attribute order.
#     Runs over a DIRECTORY so the synthesized fixtures below exercise the same code as the real root.
export TMPDIR="${TMPDIR:-/var/tmp}"
_G1_TMP="$(mktemp -d -t inngest-host-guard1.XXXXXXXX)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${_G1_TMP:?}"' EXIT
# HCL comment stripper: `#` and `//` to end of line, `/* … */` across lines, all only OUTSIDE a
# "string" (so `"https://x/*"` survives). Heredoc bodies pass through verbatim, so a decoy block
# inside one is still counted by (a). String state resets per line. POSIX awk only (mawk on CI).
_g1_strip() {
  awk '
    hd != "" { print; if ($0 ~ ("^[[:space:]]*" hd "[[:space:]]*$")) hd = ""; next }
    {
      out = ""; s = $0; instr = 0
      while (s != "") {
        if (inblk) { p = index(s, "*/"); if (!p) { s = ""; break }; s = substr(s, p + 2); inblk = 0; continue }
        if (instr) {
          if (match(s, /^([^"\\]|\\.)*"/)) { out = out substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1); instr = 0; continue }
          out = out s; s = ""; break
        }
        if (match(s, /"|#|\/\/|\/\*/)) {
          tok = substr(s, RSTART, RLENGTH); out = out substr(s, 1, RSTART - 1); s = substr(s, RSTART + RLENGTH)
          if (tok == "\"") { out = out tok; instr = 1 } else if (tok == "/*") { inblk = 1 } else { s = "" }
          continue
        }
        out = out s; s = ""
      }
      print out
      if (!inblk && match(out, /<<-?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) {
        hd = substr(out, RSTART, RLENGTH); sub(/^<<-?/, "", hd); sub(/[[:space:]]+$/, "", hd)
      }
    }' "$@"
}
# _g1_blocks <header-ERE> <file>... — one line per top-level block whose header matches, as
# "<file>\t<block flattened to one line>". A block ends at the first column-0 `}`, or on its
# header line when that line's braces balance (a one-line block).
_g1_blocks() {
  local re="$1"; shift
  awk -v re="$re" '
    FNR == 1 { f = 0 }
    !f && $0 ~ re {
      name = FILENAME; sub(/.*\//, "", name)
      o = gsub(/\{/, "{"); c = gsub(/\}/, "}")
      if (o > 0 && o == c) { print name "\t" $0; next }
      f = 1; buf = ""
    }
    f { buf = buf " " $0 }
    f && /^}/ { print name "\t" buf; f = 0 }
  ' "$@"
}
# Header EREs: labels quoted or bare; _g1_hdr anchors column 0 (terraform fmt), _g1_any any indent.
_g1_hdr() { printf '^%s[[:space:]]+"?%s"?[[:space:]]+"?%s"?[[:space:]]*[{]' "$1" "$2" "$3"; }
_g1_any() { printf '^[[:space:]]*%s[[:space:]]+"?%s"?[[:space:]]+"?%s"?([[:space:]]|[{]|$)' "$1" "$2" "$3"; }
_G1_B='([^A-Za-z0-9_-]|$)' # reference boundary: hcloud_server.inngest, never hcloud_server.inngest_x
# guard1_violations <dir> <host-tf-basename> — prints one line per violation, nothing when compliant.
guard1_violations() {
  local dir="$1" hostb="$2" sdir tf f n n_tf=0 srv fw lists norm blk name n_rm=0 n_rm_ok=0
  for tf in "$dir"/*.tf; do [[ -f "$tf" ]] && n_tf=$((n_tf + 1)); done
  if [[ "$n_tf" -eq 0 ]]; then
    echo "no *.tf files under ${dir} (every scan below would be vacuous)"
    return 0
  fi
  sdir="$(mktemp -d "${_G1_TMP}/strip.XXXXXXXX")" || { echo "mktemp failed (fail closed)"; return 0; }
  for tf in "$dir"/*.tf; do [[ -f "$tf" ]] && _g1_strip "$tf" > "$sdir/$(basename "$tf")"; done
  touch "$sdir/$hostb"
  # (d) override / JSON configuration merged behind the .tf text.
  for f in "$dir"/override.tf "$dir"/*_override.tf "$dir"/*.tf.json; do
    [[ -f "$f" ]] && grep -qE 'hcloud_(server|firewall)' "$f" \
      && echo "$(basename "$f"): an override/JSON config file mentions hcloud_server/hcloud_firewall — terraform merges it over the blocks this guard reads"
  done
  # (a) the server.
  n="$(cat "$sdir"/*.tf | grep -cE "$(_g1_any resource hcloud_server inngest)")"
  [[ "$n" == "1" ]] || echo "resource \"hcloud_server\" \"inngest\" occurs ${n} times across the root (must be exactly 1; a second copy can shadow the real block)"
  srv="$(_g1_blocks "$(_g1_hdr resource hcloud_server inngest)" "$sdir/$hostb" | cut -f2-)"
  if [[ -z "$srv" ]]; then
    echo "server block not found: no 'resource \"hcloud_server\" \"inngest\"' in ${hostb} (never a vacuous pass)"
  else
    lists="$(grep -oE '(^|[^A-Za-z0-9_])firewall_ids[[:space:]]*=[[:space:]]*\[[^]]*\]' <<<"$srv" || true)"
    if [[ -z "$lists" ]]; then
      echo "hcloud_server.inngest sets no firewall_ids — the host would boot with no Hetzner firewall"
    elif [[ "$(grep -c . <<<"$lists")" != "1" ]]; then
      echo "hcloud_server.inngest sets firewall_ids more than once"
    else
      norm="$(tr -d '[:space:]' <<<"$lists" | sed -e 's/^[^f]*//' -e 's/,]$/]/')"
      [[ "$norm" == "firewall_ids=[hcloud_firewall.inngest.id]" ]] \
        || echo "hcloud_server.inngest firewall_ids must be exactly [hcloud_firewall.inngest.id] (got '${norm}')"
    fi
    grep -qE "(^|[^A-Za-z0-9_])ignore_remote_firewall_ids${_G1_B}" <<<"$srv" \
      && echo "hcloud_server.inngest sets ignore_remote_firewall_ids — a detach made outside terraform would never be re-planned"
    grep -qE 'ignore_changes[[:space:]]*=[[:space:]]*(all([^A-Za-z0-9_]|$)|\[[^]]*firewall_ids)' <<<"$srv" \
      && echo "hcloud_server.inngest lifecycle.ignore_changes covers firewall_ids — a drifted binding would never be re-planned"
  fi
  # (b) the firewall.
  n="$(cat "$sdir"/*.tf | grep -cE "$(_g1_any resource hcloud_firewall inngest)")"
  [[ "$n" == "1" || "$n" == "0" ]] || echo "resource \"hcloud_firewall\" \"inngest\" occurs ${n} times across the root (must be exactly 1)"
  fw="$(_g1_blocks "$(_g1_hdr resource hcloud_firewall inngest)" "$sdir/$hostb" | cut -f2-)"
  if [[ -z "$fw" ]]; then
    echo "firewall block not found: no 'resource \"hcloud_firewall\" \"inngest\"' in ${hostb}"
  else
    grep -qE '(^|[^A-Za-z0-9_])apply_to([^A-Za-z0-9_]|$)' <<<"$fw" \
      && echo "hcloud_firewall.inngest carries an apply_to block — a second binding channel for the firewall"
    grep -qE '(^|[^A-Za-z0-9_])rule"?[[:space:]]*[{]' <<<"$fw" \
      && echo "hcloud_firewall.inngest has a rule block (static or dynamic) — it must stay a zero-rule deny-all"
  fi
  # (c) every other binding channel, in every file.
  while IFS=$'\t' read -r f blk; do
    name="$(sed -E 's/^[[:space:]]*resource[[:space:]]+"?hcloud_firewall_attachment"?[[:space:]]+"?([A-Za-z0-9_-]+).*/\1/' <<<"$blk")"
    [[ "$name" == "inngest" ]] && echo "${f}: resource \"hcloud_firewall_attachment\" \"inngest\" is declared — it was replaced by a removed{} forget for #8754"
    grep -qE "hcloud_firewall\\.inngest${_G1_B}" <<<"$blk" \
      && echo "${f}: hcloud_firewall_attachment.${name} binds hcloud_firewall.inngest — the binding must live on hcloud_server.inngest.firewall_ids"
    grep -qE "hcloud_server\\.inngest${_G1_B}" <<<"$blk" \
      && echo "${f}: hcloud_firewall_attachment.${name} binds hcloud_server.inngest — its firewall set is exactly firewall_ids"
  done < <(_g1_blocks "$(_g1_hdr resource hcloud_firewall_attachment '[A-Za-z0-9_-]+')" "$sdir"/*.tf)
  while IFS=$'\t' read -r f blk; do
    name="$(sed -E 's/^[[:space:]]*resource[[:space:]]+"?hcloud_firewall"?[[:space:]]+"?([A-Za-z0-9_-]+).*/\1/' <<<"$blk")"
    grep -qE "hcloud_server\\.inngest${_G1_B}" <<<"$blk" \
      && echo "${f}: hcloud_firewall.${name} references hcloud_server.inngest — an apply_to binding onto the inngest server"
  done < <(_g1_blocks "$(_g1_hdr resource hcloud_firewall '[A-Za-z0-9_-]+')" "$sdir"/*.tf)
  while IFS=$'\t' read -r f blk; do
    grep -qE "hcloud_firewall\\.inngest${_G1_B}" <<<"$blk" \
      && echo "${f}: a locals block references hcloud_firewall.inngest — an indirection an attachment could bind through"
  done < <(_g1_blocks '^locals[[:space:]]*[{]' "$sdir"/*.tf)
  grep -lE "$(_g1_any data 'hcloud_firewalls?' '[A-Za-z0-9_-]+')" "$sdir"/*.tf 2>/dev/null | while IFS= read -r f; do
    echo "$(basename "$f"): declares a data \"hcloud_firewall\" source — an indirection an attachment could bind the inngest firewall through"
  done
  # (e) the forget.
  while IFS=$'\t' read -r f blk; do
    grep -qE "from[[:space:]]*=[[:space:]]*hcloud_firewall_attachment\\.inngest${_G1_B}" <<<"$blk" || continue
    n_rm=$((n_rm + 1))
    grep -qE 'lifecycle[[:space:]]*[{][[:space:]]*destroy[[:space:]]*=[[:space:]]*false[[:space:]]*[}]' <<<"$blk" && n_rm_ok=$((n_rm_ok + 1))
  done < <(_g1_blocks '^removed[[:space:]]*[{]' "$sdir"/*.tf)
  [[ "$n_rm" -eq 1 && "$n_rm_ok" -eq 1 ]] \
    || echo "need exactly one 'removed { from = hcloud_firewall_attachment.inngest  lifecycle { destroy = false } }' in the root (found ${n_rm}, ${n_rm_ok} forgetting) — dropping the resource without it plans a DESTROY (a detach), not a forget"
  return 0
}
_G1_OUT="$(guard1_violations "$DIR" "$(basename "$HOST_TF")")"
if [[ -z "$_G1_OUT" ]]; then
  pass
else
  while IFS= read -r _l; do fail "GUARD 1 (#8754): ${_l}"; done <<<"$_G1_OUT"
fi

# 3c. GUARD 1 harness + mutation rows over SYNTHESIZED fixture roots (cq-test-fixtures-synthesized-
#     only). Each fixture is a two-file root: inngest-host.tf + other.tf. H/P-rows must PASS, M/A/C-
#     rows must RED; together they prove the extractor is neither keyed on one layout nor vacuous.
_G1_FW='resource "hcloud_firewall" "inngest" {
  name = "soleur-inngest"
}'
_G1_REMOVED='removed {
  from = hcloud_firewall_attachment.inngest

  lifecycle {
    destroy = false
  }
}'
_G1_OTHER='resource "hcloud_firewall_attachment" "git_data" {
  firewall_id = hcloud_firewall.git_data.id
  server_ids  = [hcloud_server.git_data.id]
}'
# g1_fixture <name> <server-body> [<extra-host-tf>] [<other-tf>] — writes a fixture root, echoes its dir.
g1_fixture() {
  local d="${_G1_TMP}/$1"
  mkdir -p "$d"
  printf 'resource "hcloud_server" "inngest" {\n  name = "soleur-inngest-server"\n%s\n  labels = {\n    app = "x"\n  }\n}\n\n%s\n\n%s\n%s\n' \
    "$2" "$_G1_FW" "$_G1_REMOVED" "${3:-}" > "$d/inngest-host.tf"
  printf '%s\n' "${4:-$_G1_OTHER}" > "$d/other.tf"
  echo "$d"
}
_g1_n_red=0
_g1_n_pass=0
g1_row() { # g1_row <PASS|RED> <label> <dir> [<needle>]
  local out
  out="$(guard1_violations "$3" inngest-host.tf)"
  if [[ "$1" == PASS ]]; then
    _g1_n_pass=$((_g1_n_pass + 1))
    [[ -z "$out" ]] && pass || fail "GUARD 1 $2 must PASS, got: ${out}"
  else
    _g1_n_red=$((_g1_n_red + 1))
    [[ -n "$out" && "$out" == *"${4:-}"* ]] && pass || fail "GUARD 1 $2 must RED naming '${4:-<any>}', got: '${out}'"
  fi
}
g1_row PASS "canonical" "$(g1_fixture canon '  firewall_ids = [hcloud_firewall.inngest.id]')"
g1_row PASS "H1 extra whitespace + trailing comment" "$(g1_fixture h1 '  firewall_ids   =   [ hcloud_firewall.inngest.id ]   # deny-all')"
g1_row PASS "H2 multi-line list with a trailing comma" "$(g1_fixture h2 $'  firewall_ids = [\n    hcloud_firewall.inngest.id,\n  ]')"
g1_row RED "M1 firewall_ids line missing" "$(g1_fixture m1 '  image = "ubuntu-24.04"')" "sets no firewall_ids"
g1_row RED "M1b firewall_ids only in a comment" "$(g1_fixture m1b '  # firewall_ids = [hcloud_firewall.inngest.id]')" "sets no firewall_ids"
g1_row RED "M2 firewall_ids points at another firewall" "$(g1_fixture m2 '  firewall_ids = [hcloud_firewall.registry.id]')" "must be exactly"
g1_row RED "M3 the attachment resource re-added" "$(g1_fixture m3 '  firewall_ids = [hcloud_firewall.inngest.id]' $'resource "hcloud_firewall_attachment" "inngest" {\n  firewall_id = hcloud_firewall.inngest.id\n  server_ids  = [hcloud_server.inngest.id]\n}')" '"inngest" is declared'
g1_row RED "M4 a second firewall after a compliant first" "$(g1_fixture m4 '  firewall_ids = [hcloud_firewall.inngest.id, hcloud_firewall.web.id]')" "must be exactly"
_g1_m5="$(g1_fixture m5 '  firewall_ids = [hcloud_firewall.inngest.id]')"
sed -i 's/resource "hcloud_server" "inngest"/resource "hcloud_server" "inngest_renamed"/' "$_g1_m5/inngest-host.tf"
g1_row RED "M5 server block renamed (no vacuous pass)" "$_g1_m5" "server block not found"
g1_row RED "M6 an attachment under another name binding the inngest firewall" "$(g1_fixture m6 '  firewall_ids = [hcloud_firewall.inngest.id]' '' $'resource "hcloud_firewall_attachment" "sneaky" {\n  firewall_id = hcloud_firewall.inngest.id\n  server_ids  = [hcloud_server.inngest.id]\n}')" "hcloud_firewall_attachment.sneaky binds"
_g1_m7="$(g1_fixture m7 '  firewall_ids = [hcloud_firewall.inngest.id]')"
sed -i 's/^  name = "soleur-inngest"$/&\n  apply_to {\n    server = hcloud_server.inngest.id\n  }/' "$_g1_m7/inngest-host.tf"
g1_row RED "M7 an apply_to block on hcloud_firewall.inngest" "$_g1_m7" "apply_to"
_g1_m8="$(g1_fixture m8 '  firewall_ids = [hcloud_firewall.inngest.id]')"
sed -i 's/destroy = false/destroy = true/' "$_g1_m8/inngest-host.tf"
g1_row RED "M8 the removed block destroys instead of forgetting" "$_g1_m8" "removed"
# --- Review rows (PR #8831). Each RED row closes one bypass the M-rows above did not reach. ---
_G1_OK='  firewall_ids = [hcloud_firewall.inngest.id]'
g1_row RED "M1c firewall_ids only in a // comment" "$(g1_fixture m1c '  // firewall_ids = [hcloud_firewall.inngest.id]')" "sets no firewall_ids"
g1_row RED "M1d firewall_ids only in a multi-line /* */ comment" "$(g1_fixture m1d $'  /*\n  firewall_ids = [hcloud_firewall.inngest.id]\n  */')" "sets no firewall_ids"
g1_row PASS "H3 comment tokens inside strings are not comments" "$(g1_fixture h3 $'  description = "cache /api/* via https://x #y"\n  firewall_ids = [hcloud_firewall.inngest.id]')"
# M9: a compliant decoy header inside a locals heredoc, ABOVE the real block, which lost its line.
_g1_m9="$(g1_fixture m9 '  image = "ubuntu-24.04"')"
# The opener is printed via %s: a literal heredoc token here reads as an unclosed heredoc to
# scripts/guard-vacuity-floor.test.sh, which would then hide this suite's floor.
{ printf 'locals {\n  decoy = %s\nresource "hcloud_server" "inngest" {\n  firewall_ids = [hcloud_firewall.inngest.id]\n}\nEOT\n}\n\n' '<''<-EOT'; cat "${_G1_TMP}/m9/inngest-host.tf"; } > "${_G1_TMP}/m9/x" && mv "${_G1_TMP}/m9/x" "${_G1_TMP}/m9/inngest-host.tf"
g1_row RED "M9 a heredoc decoy header above the real block" "$_g1_m9" "occurs 2 times"
g1_row RED "M10 a later sibling server carries firewall_ids, inngest does not" "$(g1_fixture m10 '  image = "ubuntu-24.04"' $'resource "hcloud_server" "other" {\n  firewall_ids = [hcloud_firewall.inngest.id]\n}')" "sets no firewall_ids"
_g1_m11="$(g1_fixture m11 "$_G1_OK")"
printf '{"resource":{"hcloud_server":{"inngest":{"firewall_ids":[]}}}}\n' > "${_G1_TMP}/m11/inngest_override.tf.json"
g1_row RED "M11 a JSON override file rewrites the server" "$_g1_m11" "override"
_g1_m11b="$(g1_fixture m11b "$_G1_OK")"
printf 'resource "hcloud_firewall" "inngest" {\n  apply_to {\n    label_selector = "app=x"\n  }\n}\n' > "${_G1_TMP}/m11b/fw_override.tf"
g1_row RED "M11b an _override.tf merges an apply_to into the firewall" "$_g1_m11b" "override"
g1_row RED "M12 ignore_remote_firewall_ids on the server" "$(g1_fixture m12 $'  firewall_ids = [hcloud_firewall.inngest.id]\n  ignore_remote_firewall_ids = true')" "ignore_remote_firewall_ids"
g1_row RED "M13 firewall_ids in lifecycle.ignore_changes" "$(g1_fixture m13 $'  firewall_ids = [hcloud_firewall.inngest.id]\n  lifecycle {\n    ignore_changes = [\n      ssh_keys,\n      firewall_ids,\n    ]\n  }')" "ignore_changes"
_g1_m14="$(g1_fixture m14 "$_G1_OK")"
sed -i 's/^  name = "soleur-inngest"$/&\n  rule {\n    direction       = "out"\n    protocol        = "tcp"\n    port            = "443"\n    destination_ips = ["10.0.0.1\/32"]\n  }/' "$_g1_m14/inngest-host.tf"
g1_row RED "M14 a rule block on hcloud_firewall.inngest (an outbound rule dark-boots the host)" "$_g1_m14" "rule block"
_g1_m14b="$(g1_fixture m14b "$_G1_OK")"
sed -i 's/^  name = "soleur-inngest"$/&\n  dynamic "rule" {\n    for_each = []\n    content {\n      direction = "in"\n    }\n  }/' "$_g1_m14b/inngest-host.tf"
g1_row RED "M14b a dynamic \"rule\" block on hcloud_firewall.inngest" "$_g1_m14b" "rule block"
g1_row RED "A3 an attachment binds ANOTHER firewall to hcloud_server.inngest" "$(g1_fixture a3 "$_G1_OK" '' $'resource "hcloud_firewall_attachment" "web" {\n  firewall_id = hcloud_firewall.web.id\n  server_ids  = [hcloud_server.inngest.id]\n}')" "hcloud_firewall_attachment.web binds hcloud_server.inngest"
g1_row RED "A4 apply_to on ANOTHER firewall targets hcloud_server.inngest" "$(g1_fixture a4 "$_G1_OK" '' $'resource "hcloud_firewall" "web" {\n  name = "w"\n  apply_to {\n    server = hcloud_server.inngest.id\n  }\n}')" "hcloud_firewall.web references hcloud_server.inngest"
g1_row RED "A5 a local indirects the inngest firewall into an attachment" "$(g1_fixture a5 "$_G1_OK" '' $'locals {\n  fw = hcloud_firewall.inngest.id\n}\n\nresource "hcloud_firewall_attachment" "sneaky" {\n  firewall_id = local.fw\n  server_ids  = [hcloud_server.git_data.id]\n}')" "locals block references hcloud_firewall.inngest"
g1_row RED "A6 a data source re-reads the inngest firewall" "$(g1_fixture a6 "$_G1_OK" '' $'data "hcloud_firewall" "x" {\n  name = "soleur-inngest"\n}')" 'data "hcloud_firewall"'
_g1_c4="$(g1_fixture c4 "$_G1_OK")"
sed -i 's/resource "hcloud_firewall" "inngest"/resource "hcloud_firewall" "inngest_renamed"/' "$_g1_c4/inngest-host.tf"
g1_row RED "C4 firewall block renamed (no vacuous pass)" "$_g1_c4" "firewall block not found"
mkdir -p "${_G1_TMP}/c5"
g1_row RED "C5 an empty root (no vacuous pass)" "${_G1_TMP}/c5" "no *.tf files"
_g1_p1="$(g1_fixture p1 "$_G1_OK")"
sed -i -e '/^removed {$/,/^}$/d' "$_g1_p1/inngest-host.tf"
printf 'removed {\n  lifecycle {\n    destroy = false\n  }\n  from = hcloud_firewall_attachment.inngest\n}\n' >> "${_G1_TMP}/p1/inngest-host.tf"
g1_row PASS "P1 removed block with lifecycle before from" "$_g1_p1"
_g1_p2="$(g1_fixture p2 "$_G1_OK")"
sed -i -e '/^removed {$/,/^}$/d' "$_g1_p2/inngest-host.tf"
printf '%s\n' "$_G1_REMOVED" > "${_G1_TMP}/p2/forgets.tf"
g1_row PASS "P2 removed block in a different .tf of the same root" "$_g1_p2"
# Row accounting: every `g1_row PASS|RED` call line in this file (comment-stripped) ran exactly once.
# A row skipped by an early return, a conditional or a broken fixture would otherwise vanish quietly.
_g1_calls_red="$(sed 's/#.*//' "${BASH_SOURCE[0]}" | grep -cE '^[[:space:]]*g1_row[[:space:]]+RED[[:space:]]')"
_g1_calls_pass="$(sed 's/#.*//' "${BASH_SOURCE[0]}" | grep -cE '^[[:space:]]*g1_row[[:space:]]+PASS[[:space:]]')"
[[ "$_g1_n_red" -eq "$_g1_calls_red" && "$_g1_n_pass" -eq "$_g1_calls_pass" && "$_g1_calls_red" -ge 20 ]] \
  && pass || fail "GUARD 1 row accounting: ran ${_g1_n_red} RED / ${_g1_n_pass} PASS rows, the file declares ${_g1_calls_red} RED / ${_g1_calls_pass} PASS"

# 4. NO lifecycle.ignore_changes=[user_data]. Strip COMMENT lines first — the block carries a
#    "Deliberately NO ...ignore_changes=[user_data]" prose comment a bare grep would false-match.
if grep -vE '^[[:space:]]*#' "$HOST_TF" | grep -cE 'ignore_changes[[:space:]]*=[[:space:]]*\[[^]]*user_data' >/dev/null; then
  fail "hcloud_server.inngest must NOT set ignore_changes=[user_data] (ADR-100 force-replace)"
else
  pass
fi

# 5. Dual-arch inngest-CLI SHA (#6178): BOTH the amd64 (inngest.tf) and arm64 checksums are
#    declared; the arch is DERIVED from the server type (local.inngest_arch); and the cloud-init
#    OVERRIDES the image-env SHA with the ARCH-MATCHED value before running the bootstrap.
grep -qE 'inngest_cli_sha256[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$INNGEST_TF" \
  && grep -qE 'inngest_cli_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$INNGEST_TF" \
  && grep -qF 'startswith(var.inngest_server_type, "cax") ? "arm64" : "amd64"' "$HOST_TF" \
  && grep -qF 'local.inngest_arch == "arm64" ? local.inngest_cli_sha256_arm64 : local.inngest_cli_sha256' "$HOST_TF" \
  && grep -qF 'INNGEST_CLI_SHA256="${inngest_cli_sha256}"' "$CLOUD_INIT" \
  && grep -qF 'INNGEST_CLI_ARCH=${inngest_cli_arch}' "$CLOUD_INIT" \
  && pass || fail "dual-arch inngest-CLI SHA: amd64+arm64 locals + derived arch + arch-matched cloud-init override"

# 6. nftables scopes :8288/:8289 to web-host IPs only, rendered from the TF constant
#    local.web_host_private_ips (host.tf) into the nft saddr set via ${web_host_private_ips}.
grep -qF 'ip saddr { ${web_host_private_ips} } accept' "$CLOUD_INIT" \
  && pass || fail "nftables saddr set is rendered from local.web_host_private_ips"

# 6b. DRIFT GUARD (#6608), mirroring cutover-inngest-workflow.test.sh's var.web_hosts parity:
#     the allowlist local's IP set MUST byte-match the canonical var.web_hosts private_ip set
#     (variables.tf `default` map). This closes the "no edge to var.web_hosts" gap the issue
#     names — the literal was hardcoded and drifted when web-2 (10.0.1.11) was retired
#     2026-07-17 (#6538). Deriving the canonical set (not a second hardcoded literal) means a
#     future roster change to var.web_hosts red-lines this test until the allowlist follows.
#     `sed 's/#.*//'` strips comments BEFORE matching so a retired IP eulogized in prose
#     (variables.tf documents `# web-2 (fsn1, 10.0.1.11) RETIRED ...`) can neither be picked up
#     as a canonical member (a false-FAIL demanding the allowlist re-add .11) nor stand in for a
#     renamed/absent live local (a vacuous PASS). The CANON derivation assumes the only quoted
#     `private_ip = "10.0.1.X"` assignments in variables.tf are var.web_hosts entries (true today;
#     mirrors cutover-inngest-workflow.test.sh).
ALLOWLIST_SET=$(sed 's/#.*//' "$HOST_TF" \
  | grep -oE 'web_host_private_ips[[:space:]]*=[[:space:]]*"[0-9.,]+"' \
  | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd,)
CANON_WEB_HOSTS=$(sed 's/#.*//' "$VARIABLES_TF" \
  | grep -oE 'private_ip[[:space:]]*=[[:space:]]*"10\.0\.1\.[0-9]+"' \
  | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd,)
if [[ -n "$ALLOWLIST_SET" && -n "$CANON_WEB_HOSTS" && "$ALLOWLIST_SET" == "$CANON_WEB_HOSTS" ]]; then
  pass
else
  fail "web_host_private_ips ('$ALLOWLIST_SET') must equal var.web_hosts private_ip set ('$CANON_WEB_HOSTS') — roster drift (#6608)"
fi

# 6c. The web-host allowlist local must NOT contain git-data(.20)/registry(.30) (complementary
#     to the parity guard: neither peer host may ever enter the :8288/:8289 allowlist).
HOST_TF_NOCOMMENT=$(sed 's/#.*//' "$HOST_TF")
if printf '%s\n' "$HOST_TF_NOCOMMENT" | grep -cE 'web_host_private_ips[[:space:]]*=' >/dev/null && printf '%s\n' "$HOST_TF_NOCOMMENT" | grep -E 'web_host_private_ips[[:space:]]*=' | grep -cE '10\.0\.1\.(20|30)' >/dev/null; then
  fail "web_host_private_ips must NOT include git-data(.20)/registry(.30)"
else
  pass
fi

# 7. Vector WIRED, dual-arch (#6197): BOTH the amd64 (vector.tf) and arm64 SHA locals are
#    declared; the cloud-init OVERRIDES VECTOR_CLI_SHA256 with the ARCH-MATCHED value, passes
#    VECTOR_CLI_ARCH derived from the type, and stages /tmp/vector.toml so the bootstrap writes
#    the vector.service unit.
grep -qE 'vector_sha256[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$VECTOR_TF" \
  && grep -qE 'vector_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$VECTOR_TF" \
  && grep -qF 'VECTOR_CLI_SHA256=${vector_sha256}' "$CLOUD_INIT" \
  && grep -qF 'VECTOR_CLI_ARCH=${inngest_cli_arch}' "$CLOUD_INIT" \
  && grep -qE '^[[:space:]]*STAGED="[^"]*(^|[" ])vector\.toml([" ]|$)' "$CLOUD_INIT" \
  && grep -qF 'for _f in $STAGED; do docker cp "$cid:/$_f" "/tmp/$_f" 2>/dev/null || true; done' "$CLOUD_INIT" \
  && pass || fail "Vector wired dual-arch — amd64+arm64 SHA locals + arch-matched cloud-init override + VECTOR_CLI_ARCH derived + /tmp/vector.toml staged"
# The DEFERRED empty VECTOR_CLI_* form must be GONE (would skip the install).
if grep -qE 'VECTOR_CLI_VERSION=""|"VECTOR_CLI_VERSION="' "$CLOUD_INIT"; then
  fail "Vector must no longer be deferred (empty VECTOR_CLI_* form is gone)"
else
  pass
fi
# The templatefile must pass the arch-conditional Vector SHA + the Doppler-CLI arch/checksum
# into the cloud-init render (dual-arch).
grep -qF 'local.inngest_arch == "arm64" ? local.vector_sha256_arm64 : local.vector_sha256' "$HOST_TF" \
  && grep -qF 'doppler_arch' "$HOST_TF" \
  && grep -qF 'doppler_sha256' "$HOST_TF" \
  && grep -qF 'doppler_$${DOPPLER_VERSION}_linux_${doppler_arch}.tar.gz' "$CLOUD_INIT" \
  && pass || fail "inngest-host.tf passes arch-conditional Vector SHA + doppler_arch/sha; cloud-init uses \${doppler_arch}"

# 7a. #9175: the templatefile passes the Doppler config name EXPLICITLY — prod resolves "prd"
#     at the call site (never a template default, which would hide the prod resolution), and the
#     rehearsal root supplies its scratch config through the same variable.
grep -qF 'inngest_doppler_config = "prd"' "$HOST_TF" \
  && pass || fail "inngest-host.tf must pass inngest_doppler_config = \"prd\" explicitly (#9175)"
# The template consumes it at every boot-path --config site (rendered literally) — prove the
# variable is actually threaded, not just declared.
grep -qF '${inngest_doppler_config}' "$CLOUD_INIT" \
  && pass || fail "cloud-init-inngest.yml must consume \${inngest_doppler_config} at the --config sites (#9175)"

# 8. inngest-bootstrap.sh arch-parameterizes the Vector install (#6197): VECTOR_CLI_ARCH
#    defaults amd64 (web host preserved) + an arm64->aarch64 triple map applied to BOTH the
#    download URL AND the extract path. No residual UNCONDITIONAL x86_64 literal in either.
grep -qE 'VECTOR_CLI_ARCH="\$\{VECTOR_CLI_ARCH:-amd64\}"' "$BOOTSTRAP" \
  && grep -qF 'aarch64-unknown-linux-musl' "$BOOTSTRAP" \
  && grep -qF '${vec_triple}.tar.gz' "$BOOTSTRAP" \
  && grep -qF 'vector-${vec_triple}/bin/vector' "$BOOTSTRAP" \
  && pass || fail "inngest-bootstrap.sh arch-parameterizes Vector (VECTOR_CLI_ARCH + aarch64 triple for URL + extract)"
# The URL/extract must NOT still hardcode vector-x86_64-unknown-linux-musl.
if grep -qF 'vector-x86_64-unknown-linux-musl' "$BOOTSTRAP"; then
  fail "inngest-bootstrap.sh must not hardcode vector-x86_64-unknown-linux-musl (URL/extract derive from \${vec_triple})"
else
  pass
fi

# 9. Boot isolation self-check admits BETTERSTACK_LOGS_TOKEN as a TOP-LEVEL alternation
#    member (#6197). A NESTED member would match INNGEST_BETTERSTACK_LOGS_TOKEN and fail to
#    match a bare BETTERSTACK_LOGS_TOKEN → boot-brick. The HEARTBEAT_URL)|BETTERSTACK anchor
#    proves the token is a sibling of the INNGEST_ group, not inside it. Floor rose 4->5,
#    then 5->6 (#10390 defect 3 — INNGEST_CONFIG_DIGEST materializes in that arc's
#    promotion apply; the bump and the doppler_secret write ride the same merge->promote
#    window, per the ordering gate in cloud-init-inngest.yml).
#    SOURCE LOCATION (#8562): the check moved out of runcmd into the provision script
#    (/usr/local/bin/soleur-inngest-provision, a write_files entry), so §9-§9c read THAT entry's
#    body, not the whole file — a copy of the regex anywhere else cannot satisfy them.
ISO_SRC="${_G1_TMP}/provision-script.sh"
awk '/^  - path: \/usr\/local\/bin\/soleur-inngest-provision$/{f=1;next} f&&/^  - path: /{f=0} f&&/^[^[:space:]]/{f=0} f' "$CLOUD_INIT" > "$ISO_SRC"
grep -qF 'HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)' "$ISO_SRC" \
  && grep -qF '"$n_inngest" -lt 6' "$ISO_SRC" \
  && pass || fail "isolation self-check admits BETTERSTACK_LOGS_TOKEN (top-level) and the floor is -lt 6"
# The old floor must be gone.
if grep -qF '"$n_inngest" -lt 5' "$ISO_SRC"; then
  fail "isolation floor must be -lt 6, not the old -lt 5"
else
  pass
fi

# 9b. (#6178) BEHAVIORAL replay of the boot isolation self-check.
#     A source-text `grep -qF '<fragment>'` is NOT sufficient here: it certifies that a
#     substring exists SOMEWHERE in a ~500-line YAML, so it stays green while the live regex
#     is mutated into a no-op (grep -Ec -> grep -c), widened to admit everything
#     (^( -> ^(.*|), or reverted outright with the fragment surviving in a COMMENT. Measured:
#     5 of 8 such mutations passed the old fragment guard, including bug #6178 itself.
#     Instead, extract the guard's OWN bytes and replay its predicate over synthesized name
#     sets, so the assertions are about the decision the host actually makes.
#     Mirrors registry-boot-guard.test.sh's extract-and-replay idiom (the sibling host).
GUARD_RE="$(grep -E "n_inngest=.*grep -Ec" "$ISO_SRC" | grep -oE "grep -Ec '[^']*'" | sed "s/grep -Ec '//; s/'$//")"
FLOOR="$(grep -oE '\[ "\$n_inngest" -lt [0-9]+ \]' "$ISO_SRC" | grep -oE '[0-9]+' | sed -n '1p')"
# Non-vacuity: a failed extraction must NOT silently pass every case below. An empty GUARD_RE
# makes `grep -Ec ""` match every line, which would fake a clean replay.
[[ -n "$GUARD_RE" ]] && pass || fail "could not extract the admit-regex from the provision script in $CLOUD_INIT (the replay below would be vacuous)"
[[ "$FLOOR" == "6" ]] && pass || fail "could not extract the cardinality floor, or it is not 6 (got '${FLOOR:-<empty>}') — see the DEC-FLOOR note in cloud-init-inngest.yml before changing it"

# Replays the file's exact predicate: strip DOPPLER_ builtins, then FATAL unless the visible
# non-DOPPLER set is a SUBSET of the allowlist (n_total == n_inngest) AND meets the floor.
isolation_decision() {
  local names n_total n_ing
  names="$(printf '%s\n' "$@" | grep -v '^DOPPLER_' || true)"
  n_total="$(printf '%s\n' "$names" | grep -c . || true)"
  n_ing="$(printf '%s\n' "$names" | grep -Ec "$GUARD_RE" || true)"
  if [ "$n_total" -ne "$n_ing" ] || [ "$n_ing" -lt "$FLOOR" ]; then echo FATAL; return 1; fi
  echo PASS; return 0
}

DARK5=(INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI BETTERSTACK_LOGS_TOKEN)
LIVE7=("${DARK5[@]}" INNGEST_CUTOVER_FLIP INNGEST_HEARTBEAT_URL)

# Dark boot must PASS — the host has to bootstrap. Under floor 6 the minimal bootable set is
# the dark five + INNGEST_CONFIG_DIGEST, which this arc's promotion apply materializes (#10390
# defect 3 — the bump and the doppler_secret write ride the same merge->promote window).
DARK6=("${DARK5[@]}" INNGEST_CONFIG_DIGEST)
[[ "$(isolation_decision "${DARK6[@]}")" == PASS ]] && pass || fail "dark 6-secret boot (incl. INNGEST_CONFIG_DIGEST) must PASS the isolation self-check"
# And a 5-name read post-materialization means the digest was deleted — FATAL, a loud brick,
# never a silent under-floor boot.
[[ "$(isolation_decision "${DARK5[@]}")" == FATAL ]] && pass || fail "a 5-name set without INNGEST_CONFIG_DIGEST must FATAL under floor 6 — a deleted digest bricks loudly"
# THE #6178 REGRESSION, behaviorally: op=arm adds CUTOVER_FLIP + HEARTBEAT_URL. Before the fix
# this FATALed (n_total=7 vs n_inngest=6), bricking every provision while the flip was armed.
[[ "$(isolation_decision "${LIVE7[@]}")" == PASS ]] && pass || fail "armed 7-secret set must PASS — op=arm writes INNGEST_CUTOVER_FLIP; rejecting it boot-bricks the dedicated host (#6178)"
# The QUEUED repeat: inngest-config-digest.tf declares an 8th name into the same project.
[[ "$(isolation_decision "${LIVE7[@]}" INNGEST_CONFIG_DIGEST)" == PASS ]] && pass || fail "8-secret set incl. INNGEST_CONFIG_DIGEST must PASS — inngest-config-digest.tf applies it at this cutover and requires the admitting regex to land atomically"
# (#7695) INNGEST_REDIS_LUKS_KEY: inngest-redis-luks.tf declares a 9th name into this project,
# and #7695 puts the passphrase pair in the PER-MERGE `-target=` allowlist — so unlike the digest
# above, this secret lands at MERGE rather than at a dispatch. From that apply onward an unadmitted
# name makes n_total != n_inngest → FATAL on every re-provision, with no Vector to report it. This
# is the third instance of the #6178 class in one regex; the behavioural case is what stops a
# fourth, because a source-fragment grep stays green while the live regex is mutated.
[[ "$(isolation_decision "${LIVE7[@]}" INNGEST_CONFIG_DIGEST INNGEST_REDIS_LUKS_KEY)" == PASS ]] && pass || fail "9-secret set incl. INNGEST_REDIS_LUKS_KEY must PASS — inngest-redis-luks.tf mints it into soleur-inngest/prd at MERGE (per-merge -target), so an unadmitted name boot-bricks the host on its next re-provision (#7695, the #6178 class)"
# Nesting holds for it too: the member is INNGEST_REDIS_LUKS_KEY, not a bare REDIS_LUKS_KEY.
[[ "$(isolation_decision "${DARK5[@]}" REDIS_LUKS_KEY)" == FATAL ]] && pass || fail "a BARE REDIS_LUKS_KEY (no INNGEST_ prefix) must FATAL — the member is nested inside the INNGEST_ group"
# (#6894, ADR-142 additive blue-green) TWO more names, the fourth and fifth instances of this class.
# INNGEST_LUKS_CUTOVER is the cutover's trigger and INNGEST_LUKS_ACTIVE_VOLUME_ID is the pointer the
# boot resolver reads to decide which volume is /mnt/data; op=luks-cutover writes both into THIS
# project. From that write onward an unadmitted name is n_total != n_inngest → FATAL on the next
# re-provision — and a re-provision is the ONLY delivery path to this host, so the cutover would
# brick the very replace that has to follow it. Admitting them ahead of the write is a no-op for
# the subset test (an absent name is excluded from both counters), which is why it lands now.
[[ "$(isolation_decision "${LIVE7[@]}" INNGEST_CONFIG_DIGEST INNGEST_REDIS_LUKS_KEY INNGEST_LUKS_CUTOVER INNGEST_LUKS_ACTIVE_VOLUME_ID)" == PASS ]] && pass || fail "11-secret set incl. INNGEST_LUKS_CUTOVER + INNGEST_LUKS_ACTIVE_VOLUME_ID must PASS — op=luks-cutover writes both into soleur-inngest/prd, so an unadmitted name boot-bricks the host on the replace that must follow the cutover (#6894, the #6178 class)"
# Each alone, so neither member rides on the other's admission.
[[ "$(isolation_decision "${DARK5[@]}" INNGEST_LUKS_CUTOVER)" == PASS ]] && pass || fail "INNGEST_LUKS_CUTOVER alone on a dark set must PASS (the trigger may be written before the pointer)"
[[ "$(isolation_decision "${DARK5[@]}" INNGEST_LUKS_ACTIVE_VOLUME_ID)" == PASS ]] && pass || fail "INNGEST_LUKS_ACTIVE_VOLUME_ID alone on a dark set must PASS (the pointer outlives the trigger after rollback)"
# Nesting holds for both: a bare LUKS_CUTOVER / LUKS_ACTIVE_VOLUME_ID is foreign.
[[ "$(isolation_decision "${DARK5[@]}" LUKS_CUTOVER)" == FATAL ]] && pass || fail "a BARE LUKS_CUTOVER (no INNGEST_ prefix) must FATAL — the member is nested inside the INNGEST_ group"
[[ "$(isolation_decision "${DARK5[@]}" LUKS_ACTIVE_VOLUME_ID)" == FATAL ]] && pass || fail "a BARE LUKS_ACTIVE_VOLUME_ID (no INNGEST_ prefix) must FATAL — the member is nested inside the INNGEST_ group"
# Exact-name admission, not a prefix: a lookalike must not ride in on the new alternation.
[[ "$(isolation_decision "${DARK5[@]}" INNGEST_LUKS_CUTOVER_EXTRA)" == FATAL ]] && pass || fail "INNGEST_LUKS_CUTOVER_EXTRA must FATAL — the alternation is anchored, a suffixed lookalike is foreign"
# Isolation still holds: an over-scoped token leaking ONE foreign name must fail closed.
[[ "$(isolation_decision "${LIVE7[@]}" SUPABASE_SERVICE_ROLE_KEY)" == FATAL ]] && pass || fail "a foreign secret must FATAL — this is the over-scoped-credential defense the self-check exists for"
# Floor still bites (catches the degenerate empty-read case where n_total==n_inngest==0).
[[ "$(isolation_decision INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI)" == FATAL ]] && pass || fail "a 4-name set must FATAL on the floor"
# NESTING, behaviorally: CUTOVER_FLIP must be admitted only as INNGEST_CUTOVER_FLIP.
[[ "$(isolation_decision INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI CUTOVER_FLIP)" == FATAL ]] && pass || fail "a BARE CUTOVER_FLIP (no INNGEST_ prefix) must FATAL — the member must be nested inside the INNGEST_ group"
# TOP-LEVEL anchor (#6197), behaviorally: BETTERSTACK_LOGS_TOKEN is a sibling of the group,
# so the INNGEST_-prefixed spelling must NOT be admitted.
[[ "$(isolation_decision INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI INNGEST_BETTERSTACK_LOGS_TOKEN)" == FATAL ]] && pass || fail "INNGEST_BETTERSTACK_LOGS_TOKEN must FATAL — BETTERSTACK_LOGS_TOKEN is a TOP-LEVEL member, not nested (#6197)"
# DOPPLER_* builtins are stripped before counting.
[[ "$(isolation_decision "${DARK6[@]}" DOPPLER_PROJECT DOPPLER_CONFIG)" == PASS ]] && pass || fail "DOPPLER_* builtins must be stripped before counting"

# 9c. Pin the COMPARISON OPERATOR. The replay above re-derives the predicate, so it cannot see
#     an inversion in the file itself: flipping -ne to -eq makes an isolated host FATAL and a
#     LEAKY one boot clean, with every behavioral case above still green.
# shellcheck disable=SC2016  # literal $n_total/$n_inngest is intentional — matching the file's text
grep -qF '[ "$n_total" -ne "$n_inngest" ]' "$ISO_SRC" \
  && pass || fail "the isolation self-check must compare with -ne (an -eq inversion admits an over-scoped credential and rejects an isolated one)"

# 10. (#6536, AC6) The dark-host heartbeat prose must NOT re-assert the false "curl no-ops"
#     claim. `curl -fsS --max-time 10 ""` exits 2 ("blank argument where content is
#     expected" — measured), it does NOT no-op. That false comment is what authorized the
#     bug: it described a no-op the code never implemented, so the dark host's oneshot
#     failed every 60s for 3 days (3,724 fires) while the comment said this was fine. The
#     no-op is now implemented EXPLICITLY, as the @@DARK_ARM@@ render in inngest-bootstrap.sh.
#     Absence-grep is safe here: the corrected prose states the measured rc=2 behaviour and
#     has no reason to restate the phrase.
if grep -qi 'curl no-ops' "$HOST_TF"; then
  fail "inngest-host.tf must not claim the dark host's heartbeat curl no-ops (it exits 2 — #6536)"
else
  pass
fi
# The corrected prose must actually name the measured behaviour + its owner, so this is a
# record-correction rather than a silent deletion of the claim.
grep -qE 'exits? 2' "$HOST_TF" \
  && grep -qF '#6536' "$HOST_TF" \
  && grep -qF 'inngest-bootstrap.sh' "$HOST_TF" \
  && pass || fail "inngest-host.tf must state the measured rc=2 truth, cite #6536, and name where the skip is implemented"

# 11. (plan CF-2) The bootstrap pull must be VERIFIED-BY-CONSTRUCTION, and the file must not
#     claim a verification it does not perform. Same shape as item 10 above, one file over:
#     `grep -n cosign cloud-init-inngest.yml` returned exactly ONE hit and it was a comment
#     asserting the cold-boot pull was cosign-verified. It never was. The real path is
#     IREF -> docker pull -> docker create/cp -> `bash inngest-bootstrap.sh` AS ROOT, with no
#     signature check anywhere; build-inngest-bootstrap-image.yml says outright that this
#     image is not signed. The claim survived long enough that the PLAN for this change
#     inherited it from the comment and restated it as an acceptance criterion — which is the
#     whole reason a false comment is treated here as a defect and not as untidiness.
#
#     Two assertions, because either alone is defeatable:
#       (a) no cosign VERIFICATION may be claimed unless one is actually executed. Stated as
#           an implication rather than a flat absence, so the day someone ships a real
#           `cosign verify` the guard permits the prose that describes it.
#       (b) the pull is digest-pinned. This is the substantive control the false comment stood
#           in for: `@sha256:` names immutable bytes, so a mutable tag cannot be re-pointed at
#           a different root-executed payload between the build and a host replace.
#     #6780 update: a REAL cosign verification now exists on this host — the config-refresh
#     consumer runs `verify-blob` inside the pinned cosign image (`"$COSIGN_IMAGE"
#     verify-blob --trusted-root …` in the baked refresh script). The guard's semantic is
#     unchanged — no verification may be CLAIMED unless one is executed — but the permitted
#     execution forms now include the image-wrapped verify-blob, so the prose and the
#     mechanism stay one edit apart rather than re-creating the false-comment defect class.
if grep -qE 'cosign[- ]verif' "$CLOUD_INIT" \
  && ! grep -qE '^[[:space:]]*cosign verify[[:space:]]' "$CLOUD_INIT" \
  && ! grep -qE 'COSIGN[A-Z_]*}?"?[[:space:]]+verify-blob[[:space:]]' "$CLOUD_INIT"; then
  fail "cloud-init-inngest.yml claims a cosign verification but executes none (CF-2 — the claim was false for months)"
else
  pass
fi
# Record-correction, not silent deletion (mirrors item 10's second leg): the corrected prose
# must name the absence, cite its issue, and name what replaced it.
grep -qE 'NO SIGNATURE VERIFICATION ON THIS PATH' "$CLOUD_INIT" \
  && grep -qF 'CF-2' "$CLOUD_INIT" \
  && grep -qE 'DIGEST PIN' "$CLOUD_INIT" \
  && pass || fail "cloud-init-inngest.yml must state that no signature verification exists, cite CF-2, and name the digest pin that replaces it"
# Anchored on the ASSIGNMENT construct, not a bare `@sha256:` token — the comments above it
# discuss the digest pin in prose, and a token grep would pass on that prose alone with the
# assignment still on a mutable tag. The tag is retained ahead of the digest deliberately: it
# keeps the `soleur-inngest-bootstrap:vX.Y.Z` pin-drift guard in
# cloud-init-inngest-bootstrap.test.sh armed, and docker resolves by the digest regardless.
grep -qE '^[[:space:]]*IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$' "$CLOUD_INIT" \
  && pass || fail "IREF must be digest-pinned (repo:vX.Y.Z@sha256:<64-hex>) — CF-2: a mutable tag gates a root-executed payload on nothing but GHCR TLS"

# 12. (#6780, ADR-135 2026-10-13 amendment) The config-refresh consumer bake — structural pins.
#     The behavioral/fixture coverage lives in inngest-config-refresh.test.sh (the rendered
#     payload's own suite); here we pin the TEMPLATE-level shape this file is answerable for:
#       a) the four consumer write_files entries exist exactly once with the right modes and
#          root ownership (the script and units are root-owned; the version seed is 0644);
#       b) the two heavy payloads are templatefile-driven file() embeds, NOT inline copies —
#          `${indent(6, <var>)}` under `content: |`, so the repo file stays the single source
#          (an inlined installer/root would silently diverge);
#       c) the runcmd arms the timer AFTER the /etc/default/inngest-server write (the unit's
#          ConditionPathExists is that file — enabling early would fire a permanently-skipping
#          timer boot);
#       d) the consumer's engine paths are NOT reachable through the refresh-set allowlist
#          (HARD-1 — a signed bundle must not be able to replace the verifier itself).
for _p in /usr/local/bin/infra-config-install \
          /usr/local/bin/inngest-config-refresh.sh \
          /etc/systemd/system/inngest-config-refresh.service \
          /etc/systemd/system/inngest-config-refresh.timer \
          /etc/soleur/cosign-trusted-root.json \
          /var/lib/inngest-config/applied.version; do
  [ "$(grep -cF "  - path: $_p" "$CLOUD_INIT")" -eq 1 ] \
    && pass || fail "#6780: exactly one write_files entry for $_p"
done
grep -qF '${indent(6, infra_config_install_text)}' < <(grep -A3 -F '  - path: /usr/local/bin/infra-config-install' "$CLOUD_INIT") \
  && pass || fail "#6780: infra-config-install must embed via \${indent(6, infra_config_install_text)} (single-source, D12)"
grep -qF '${indent(6, cosign_trusted_root_text)}' < <(grep -A3 -F '  - path: /etc/soleur/cosign-trusted-root.json' "$CLOUD_INIT") \
  && pass || fail "#6780: cosign-trusted-root.json must embed via \${indent(6, cosign_trusted_root_text)} (single-source, D12)"
_cr_arm="$(grep -n 'enable --now inngest-config-refresh.timer' "$CLOUD_INIT" | head -1 | cut -d: -f1)"
_cr_env="$(grep -n '> /etc/default/inngest-server' "$CLOUD_INIT" | head -1 | cut -d: -f1)"
{ [ -n "$_cr_arm" ] && [ -n "$_cr_env" ] && [ "$_cr_arm" -gt "$_cr_env" ]; } \
  && pass || fail "#6780: the refresh timer must be armed AFTER /etc/default/inngest-server is written"
for _eng in 'inngest-config-refresh' 'infra-config-install' 'cosign-trusted-root' 'applied.version'; do
  ! grep -q "$_eng" < <(grep -vE '^[[:space:]]*#' "$DIR/inngest-config-refresh-set.txt") \
    && pass || fail "#6780 HARD-1: engine path $_eng appears in inngest-config-refresh-set.txt"
done

# --- (#6178) Flip-asset staging PARITY: cloud-init must docker-cp every flip asset that
#     inngest-bootstrap.sh installs from /tmp. The bug this guards: the OCI image baked the
#     flip trio in (Dockerfile COPY) and bootstrap gated its install on `-f /tmp/inngest-
#     cutover-flip.*`, but cloud-init NEVER docker-cp'd image:/ -> /tmp, so DEDICATED_FLIP
#     stayed 0 and the inngest-cutover-flip.timer never installed on any dedicated host — the
#     flip FSM could not run. Derive the required set from the CONSUMER (bootstrap's install
#     lines), so adding a new flip asset to bootstrap without staging it in cloud-init red-lines.
#     The four hard-required files are those in bootstrap's install-gate condition (:664).
# DERIVE the required set from bootstrap's OWN install-gate condition (the `-f /tmp/...` tests
# whose failure keeps DEDICATED_FLIP=0), NOT a hardcoded list — so a NEW required asset added
# to bootstrap's gate without a matching cloud-init cp red-lines (the new-asset-drift case a
# static allowlist misses). The gate block runs from `DEDICATED_FLIP=0` to its `then`.
# Anchor on the INNER flip-gate `if [[ -f /tmp/inngest-cutover-flip.sh ...` (NOT the outer
# DOPPLER_PROJECT `if`, whose `then` would end the capture before the -f tests).
# The ONE staging list (#8562 review), read from its single assignment in the provision script.
STAGED_LIST="$(sed -n 's/^[[:space:]]*STAGED="\([^"]*\)"$/\1/p' "$CLOUD_INIT")"
[ "$(grep -cE '^[[:space:]]*STAGED="' "$CLOUD_INIT")" = 1 ] && [ -n "$STAGED_LIST" ] \
  && pass || fail "cloud-init-inngest.yml must assign the STAGED asset list exactly once (#8562)"
GATE_BLOCK="$(awk '/if \[\[ -f \/tmp\/inngest-cutover-flip\.sh/{i=1} i{print} i&&/then$/{exit}' "$BOOTSTRAP")"
mapfile -t FLIP_REQUIRED < <(printf '%s\n' "$GATE_BLOCK" | grep -oE '/tmp/inngest-[a-z-]+\.[a-z]+' | sed 's#^/tmp/##' | sort -u)
[[ "${#FLIP_REQUIRED[@]}" -ge 4 ]] \
  && pass || fail "could not derive the flip install-gate asset set from inngest-bootstrap.sh (got ${#FLIP_REQUIRED[@]}; expected >=4) — the parity check below would be vacuous"
for asset in "${FLIP_REQUIRED[@]}"; do
  # cloud-init must docker-cp it from the PINNED extract container to that exact /tmp path.
  # The container name (soleur-inngest-bootstrap-extract) is pinned deliberately: a typo in the
  # SOURCE container (`docker cp WRONGNAME:/asset ...`) fails at runtime, is swallowed by
  # `2>/dev/null || true`, and silently skips staging — the exact silent-skip class this fix
  # exists to prevent. A `[^ ]*:/asset` match would pass on the typo'd container.
  # #8562: the container is addressed by the ID `docker create` returned (`$cid`), not by its
  # fixed name, so a SIGKILLed attempt's leftover container can never be the source; and (review)
  # every staged asset is copied by ONE loop over ONE list, $STAGED, which also drives the
  # per-attempt stale-file rm — so the asset must be a WORD of that list (a substring would let
  # `inngest-cutover-flip.shx` satisfy it), and the loop line below must copy from "$cid".
  if [[ " $STAGED_LIST " == *" ${asset} "* ]]; then
    pass
  else
    fail "cloud-init-inngest.yml's STAGED list must name ${asset} — the provision script docker-cps every STAGED asset to /tmp; bootstrap's install-gate requires it there; without it DEDICATED_FLIP=0 and the flip timer never installs (#6178)"
  fi
done
grep -qF 'for _f in $STAGED; do docker cp "$cid:/$_f" "/tmp/$_f" 2>/dev/null || true; done' "$CLOUD_INIT" \
  && pass || fail "cloud-init-inngest.yml must copy every STAGED asset with the one loop 'for _f in \$STAGED; do docker cp \"\$cid:/\$_f\" \"/tmp/\$_f\" …' (#8562)"
# ...and $cid is the ID of the pinned extract container, bound exactly once.
[ "$(grep -cE '^[[:space:]]*cid="\$\(docker create --name soleur-inngest-bootstrap-extract "\$IREF"\)"$' "$CLOUD_INIT")" = 1 ] \
  && pass || fail "cloud-init-inngest.yml must bind cid=\"\$(docker create --name soleur-inngest-bootstrap-extract \"\$IREF\")\" exactly once — every docker cp source is that ID (#8562)"
# The staging outcome must self-report off-box (the silent absence hid the bug for a full
# cutover attempt): assert a flip-assets phone-home marker exists.
grep -qE 'inngest-boot-phone-home\.sh flip-assets-(staged|MISSING)' "$CLOUD_INIT" \
  && pass || fail "cloud-init-inngest.yml must phone-home the flip-assets staging outcome (flip-assets-staged / flip-assets-MISSING) so a future staging failure self-diagnoses off-box (#6178)"

# 6. D1 GUARD (#8285, #9786). The retired plaintext backstop volume is no longer declared, and the
#    cloud-init `inngest_volume_id` input is gone: the template no longer reads it, so nothing in the
#    root may assign it again. Property: "the retired volume is not declared, and the retired id cannot
#    come back as a template input". (Before #9786 this guard also held `user_data` byte-identical across
#    the backstop's removal by pinning the id as a literal; #9786 deliberately changes user_data once, in a
#    parked PR, and removes the pin.) Scans over
#    comment-stripped *.tf (a comment naming a resource must not satisfy or trip them):
#      v1 neither retired address is declared; v2 zero `inngest_volume_id =` assignments in any file
#      of the root; v4 no live reference to hcloud_volume.inngest_redis (the `_luks` sibling is a
#      different resource and is allowed). The rehearsal root's *.tf and the budget script are
#      scanned for v2 as well (the template has three renderers); v1/v4 stay root-only.
d1_violations() { # d1_violations <dir>
  local dir="$1" f stripped extra_scan n
  # Comment lines and `description = "..."` lines are prose, not references (a variable description may
  # name the retired address to explain what it pins); a depends_on, attribute access or resource header
  # is what v1/v4 are after.
  # The scan covers the root's *.tf, the rehearsal root's *.tf (the second renderer of this template) and the
  # budget script (the third); the last two are absent from the fixtures and skipped there. The key is
  # matched QUOTED or bare, at line start or inline, and with `=` or `:` (JSON-style) so a spelling change
  # cannot walk past it.
  stripped="$(for f in "$dir"/*.tf; do [ -f "$f" ] && grep -vE '^[[:space:]]*(#|//|description[[:space:]]*=)' "$f"; done)"
  extra_scan="$(for f in "$dir"/inngest-provision-rehearsal/*.tf "$dir"/inngest-userdata-budget.sh; do [ -f "$f" ] && grep -vE '^[[:space:]]*(#|//|description[[:space:]]*=)' "$f"; done)"
  [[ -n "$stripped" ]] || { echo "no .tf content scanned (fail closed)"; return 0; }
  grep -qE '^[[:space:]]*resource[[:space:]]+"hcloud_volume(_attachment)?"[[:space:]]+"inngest_redis"' <<<"$stripped" \
    && echo "v1: hcloud_volume(_attachment).inngest_redis is declared again"
  n="$(grep -cE '(^|[^[:alnum:]_])["'"'"']?inngest_volume_id["'"'"']?[[:space:]]*[=:]' <<<"${stripped}"$'\n'"${extra_scan}")"
  [[ "$n" == 0 ]] || echo "v2: expected zero inngest_volume_id assignments, found ${n}"
  grep -qE 'hcloud_volume\.inngest_redis([^_[:alnum:]]|$)' <<<"$stripped" \
    && echo "v4: a live reference to hcloud_volume.inngest_redis remains"
  return 0
}
d1_fixture() { # d1_fixture <name> <extra tf> [second-file tf] — a compliant host file plus extras
  local d="${_G1_TMP}/d1-$1"
  mkdir -p "$d" || return 1
  printf 'resource "hcloud_server" "inngest" {\n  user_data = templatefile("x", {\n    inngest_luks_volume_id = hcloud_volume.inngest_redis_luks.id\n  })\n}\n%s\n' "${2:-}" > "$d/inngest-host.tf"
  if [[ -n "${3:-}" ]]; then printf '%s\n' "$3" > "$d/extra.tf"; fi
  if [[ -n "${4:-}" ]]; then mkdir -p "$d/inngest-provision-rehearsal" && printf '%s\n' "$4" > "$d/inngest-provision-rehearsal/rehearsal.tf"; fi
  echo "$d"
}
_D1_OUT="$(d1_violations "$DIR")"
if [[ -z "$_D1_OUT" ]]; then
  pass
else
  while IFS= read -r _l; do fail "D1 guard (#9786): ${_l}"; done <<<"$_D1_OUT"
fi
d1_row() { # d1_row <PASS|RED> <label> <dir> [<needle>]
  local out
  out="$(d1_violations "$3")"
  if [[ "$1" == PASS ]]; then
    [[ -z "$out" ]] && pass || fail "D1 $2 must PASS, got: ${out}"
  else
    [[ -n "$out" && "$out" == *"${4:-}"* ]] && pass || fail "D1 $2 must RED naming '${4:-<any>}', got: '${out}'"
  fi
}
d1_row PASS "canonical: no input, a comment may name the retired volume" "$(d1_fixture ok '# hcloud_volume.inngest_redis is only named in this comment')"
d1_row PASS "D1-H1 a variable description may name the retired address" "$(d1_fixture h1 $'variable "x" {\n  description = "pins hcloud_volume.inngest_redis (retired)"\n}')"
d1_row RED "D1-M5b a depends_on reference is not a description" "$(d1_fixture m5b $'resource "terraform_data" "y" {\n  depends_on = [hcloud_volume.inngest_redis]\n}')" "v4:"
d1_row RED "D1-M1 the volume is re-declared" "$(d1_fixture m1 $'resource "hcloud_volume" "inngest_redis" {\n  size = 10\n}')" "v1:"
d1_row RED "D1-M1b the attachment is re-declared" "$(d1_fixture m1b $'resource "hcloud_volume_attachment" "inngest_redis" {\n  volume_id = 1\n}')" "v1:"
d1_row RED "D1-M2 the input is reintroduced at the volume resource" "$(d1_fixture m2 $'locals {\n  b = templatefile("y", {\n    inngest_volume_id = hcloud_volume.inngest_redis.id\n  })\n}')" "v2:"
d1_row RED "D1-M2b the input is reintroduced at the LUKS volume" "$(d1_fixture m2b $'locals {\n  b = templatefile("y", {\n    inngest_volume_id = hcloud_volume.inngest_redis_luks.id\n  })\n}')" "v2:"
d1_row RED "D1-M3 the input is reintroduced as the retired literal in a SECOND file" "$(d1_fixture m3 '' $'locals {\n  b = templatefile("y", {\n    inngest_volume_id = "106261946"\n  })\n}')" "found 1"
d1_row RED "D1-M5 a live reference hides in another expression" "$(d1_fixture m5 $'output "x" {\n  value = hcloud_volume.inngest_redis.id\n}')" "v4:"
d1_row RED "D1-M6 two reintroduced assignments are both counted" "$(d1_fixture m6 $'locals {\n  b = templatefile("y", {\n    inngest_volume_id = "1"\n  })\n}' $'locals {\n  c = templatefile("z", {\n    inngest_volume_id = "2"\n  })\n}')" "found 2"
d1_row RED "D1-M7 an empty root scans nothing" "$(mkdir -p "${_G1_TMP}/d1-empty" && echo "${_G1_TMP}/d1-empty")" "fail closed"
d1_row RED "D1-M8 the input is reintroduced with a QUOTED key" "$(d1_fixture m8 '' $'locals {\n  b = templatefile("y", {\n    "inngest_volume_id" = "1"\n  })\n}')" "found 1"
d1_row RED "D1-M9 the input is reintroduced INLINE in a one-line map" "$(d1_fixture m9 $'locals {\n  b = templatefile("y", { inngest_volume_id = "1" })\n}')" "found 1"
d1_row RED "D1-M10 the input is reintroduced in the REHEARSAL root (the template's second renderer)" "$(d1_fixture m10 '' '' $'locals {\n  b = templatefile("y", {\n    inngest_volume_id = "1"\n  })\n}')" "found 1"
# D1-V VALUE PINS. D1 proves the retired key stays gone; it said nothing about what the surviving key is
# BOUND to, so `inngest_luks_volume_id = "106261946"` (the retired id) or any other literal would have passed
# every suite while pointing the resolver at a destroyed device. Pin each renderer's binding to its own
# declared LUKS volume, comment-stripped and whole-line.
_pin_prod="$(grep -vE '^[[:space:]]*#' "$DIR/inngest-host.tf" | grep -cxE '[[:space:]]*inngest_luks_volume_id[[:space:]]*=[[:space:]]*hcloud_volume\.inngest_redis_luks\.id')"
[[ "$_pin_prod" == 1 ]] && pass || fail "D1-V1 inngest-host.tf must bind inngest_luks_volume_id to hcloud_volume.inngest_redis_luks.id exactly once (found ${_pin_prod})"
_pin_reh="$(grep -vE '^[[:space:]]*#' "$DIR/inngest-provision-rehearsal/rehearsal.tf" | grep -cxE '[[:space:]]*inngest_luks_volume_id[[:space:]]*=[[:space:]]*hcloud_volume\.rehearsal_inngest_luks\.id')"
[[ "$_pin_reh" == 1 ]] && pass || fail "D1-V2 rehearsal.tf must bind inngest_luks_volume_id to hcloud_volume.rehearsal_inngest_luks.id exactly once (found ${_pin_reh})"

# D1-H2 HARNESS ROW: the RED rows must be able to fail the suite. With d1_violations neutered to
# `return 0` the same RED row must register a failure; if it registers a pass the RED rows above
# prove nothing. Driven in a subshell so the neutered function and its counters never leak.
_D1_NEUTERED="$( d1_violations() { return 0; }; fails=0; fail() { fails=$((fails + 1)); }; pass() { :; }
  d1_row RED "D1-H2 neutered scan" "$(d1_fixture h2 $'locals {\n  b = templatefile("y", {\n    inngest_volume_id = "1"\n  })\n}')" "v2:"
  printf '%s' "$fails" )"
[[ "$_D1_NEUTERED" == 1 ]] && pass || fail "D1-H2 a neutered d1_violations did not fail the RED row (fails=${_D1_NEUTERED}) — the RED rows are vacuous"

# 12. (#10136) TLS terminator for the :8288 link: stunnel4 on ${inngest_private_ip}:8443 forwarding to
#     127.0.0.1:8288, a counted legacy listener, a 5-minute `tls-health` emitter, and the two new
#     boot-isolation names. Template rationale lives in inngest-tls.tf and the runbook; this block
#     pins the SHAPE (static) and the BEHAVIOUR of the two host scripts (extracted, path-rewritten,
#     run against stubs).
tls_entry() { # <write_files path> -> the entry's content block, de-indented, template tokens resolved
  awk -v p="  - path: $1" '
    $0 == p { f = 1; next }
    f && /^  - path: / { exit }
    f && /^    content: \|/ { c = 1; next }
    f && c && /^    (owner|permissions):/ { exit }
    f && c { sub(/^      /, ""); print }
  ' "$CLOUD_INIT" | sed -e 's/\${inngest_private_ip}/10.0.1.40/g' -e 's/\$\${/${/g'
}
ln_of() { grep -nxF -- "$1" "$CLOUD_INIT" | head -n 1 | cut -d: -f1; }

# 12a. nft: named counters, counting rules BEFORE their accepts, the 8443 accept/drop pair, and the
#      pre-existing 8288/8289 accept + drop lines BYTE-IDENTICAL (other suites and the #10405 chain
#      fingerprint read them).
NFT_IND="          "
L_ACC="$(ln_of "${NFT_IND}tcp dport { 8288, 8289 } ip saddr { \${web_host_private_ips} } accept")"
L_DROP="$(ln_of "${NFT_IND}tcp dport { 8288, 8289 } drop")"
L_LEG="$(ln_of "${NFT_IND}tcp dport 8288 ip saddr { \${web_host_private_ips} } counter name \"legacy_8288\"")"
L_TC="$(ln_of "${NFT_IND}tcp dport 8443 ip saddr { \${web_host_private_ips} } counter name \"tls_8443\"")"
L_TA="$(ln_of "${NFT_IND}tcp dport 8443 ip saddr { \${web_host_private_ips} } accept")"
L_TD="$(ln_of "${NFT_IND}tcp dport 8443 drop")"
L_C1="$(ln_of "        counter legacy_8288 { }")"
L_C2="$(ln_of "        counter tls_8443 { }")"
L_TBL="$(ln_of "      table inet soleur_inngest {")"
L_CHN="$(ln_of "        chain input {")"
[[ -n "$L_ACC" && -n "$L_DROP" ]] && pass || fail "the existing 8288/8289 accept and drop lines must stay byte-identical (accept='${L_ACC:-}' drop='${L_DROP:-}')"
[[ -n "$L_LEG" && -n "$L_ACC" && "$L_LEG" -lt "$L_ACC" ]] && pass || fail "the verdict-less legacy_8288 counting rule must sit BEFORE the 8288 accept (first match wins)"
[[ -n "$L_TC" && -n "$L_TA" && -n "$L_TD" && "$L_TC" -lt "$L_TA" && "$L_TA" -lt "$L_TD" ]] && pass || fail "8443 order must be: tls_8443 counting rule, source-scoped accept, then drop"
[[ -n "$L_ACC" && -n "$L_DROP" && -n "$L_TA" && "$L_ACC" -lt "$L_DROP" && "$L_DROP" -lt "$L_TC" ]] && pass || fail "the 8443 block must follow the unchanged 8288/8289 accept+drop pair"
[[ -n "$L_C1" && -n "$L_C2" && -n "$L_TBL" && -n "$L_CHN" && "$L_TBL" -lt "$L_C1" && "$L_C1" -lt "$L_CHN" && "$L_TBL" -lt "$L_C2" && "$L_C2" -lt "$L_CHN" ]] && pass || fail "both named counter objects must be declared inside table inet soleur_inngest before the chain"
# The rendered chain text must not carry inline packet counts (an inline counter would change the
# chain listing on every read and break any fingerprint over it): rules use named counters only.
if sed -n "${L_CHN:-1},\$p" "$CLOUD_INIT" | grep -E '^ +tcp dport' | grep -E 'counter( packets| [^n])' >/dev/null; then
  fail "no inline 'counter' (anonymous) in the chain; named counter objects only"
else
  pass
fi

TLS_T="$(mktemp -d)"
NFT_BODY="$(awk '/nft -f - <<.NFTEOF.$/ { f = 1; next } /^      NFTEOF$/ { f = 0 } f { sub(/^      /, ""); print }' "$CLOUD_INIT" | sed 's/\${web_host_private_ips}/10.0.1.10,10.0.1.11/')"
printf '%s\n' "$NFT_BODY" > "$TLS_T/nft.conf"
if command -v nft >/dev/null 2>&1 && unshare -rn true 2>/dev/null; then
  if unshare -rn nft -c -f "$TLS_T/nft.conf" 2>"$TLS_T/nft.err"; then pass; else fail "nft -c -f rejects the extracted ruleset: $(head -c 300 "$TLS_T/nft.err")"; fi
else
  echo "SKIP: nft -c syntax check needs nft and unprivileged user namespaces"
fi

# 12b. Isolation: INNGEST_TLS_KEY / INNGEST_TLS_CERT are admitted (Terraform mints both into
#      soleur-inngest/prd at merge; an unadmitted name boot-bricks the next re-provision), the floor
#      is now 6 (#10390 defect 3 — INNGEST_CONFIG_DIGEST materialized), and neither a bare nor a
#      suffixed look-alike is.
[[ "$(isolation_decision "${DARK5[@]}" INNGEST_TLS_KEY INNGEST_TLS_CERT)" == PASS ]] && pass || fail "DARK5 + INNGEST_TLS_KEY + INNGEST_TLS_CERT must PASS — the TLS key and cert are minted into soleur-inngest/prd (#10136)"
[[ "$(isolation_decision "${LIVE7[@]}" INNGEST_CONFIG_DIGEST INNGEST_REDIS_LUKS_KEY INNGEST_LUKS_CUTOVER INNGEST_LUKS_ACTIVE_VOLUME_ID INNGEST_TLS_KEY INNGEST_TLS_CERT)" == PASS ]] && pass || fail "the full 13-name set incl. the TLS pair must PASS"
[[ "$(isolation_decision "${DARK5[@]}" INNGEST_TLS_KEY)" == PASS ]] && pass || fail "INNGEST_TLS_KEY alone must PASS (the pair is written by one apply but each name stands alone)"
[[ "$(isolation_decision "${DARK5[@]}" TLS_KEY)" == FATAL ]] && pass || fail "a BARE TLS_KEY (no INNGEST_ prefix) must FATAL — the member is nested inside the INNGEST_ group"
[[ "$(isolation_decision "${DARK5[@]}" TLS_CERT)" == FATAL ]] && pass || fail "a BARE TLS_CERT (no INNGEST_ prefix) must FATAL — the member is nested inside the INNGEST_ group"
[[ "$(isolation_decision "${DARK5[@]}" INNGEST_TLS_KEY_EXTRA)" == FATAL ]] && pass || fail "INNGEST_TLS_KEY_EXTRA must FATAL — the alternation is anchored, a suffixed look-alike is foreign"
[[ "$(isolation_decision "${DARK5[@]}" INNGEST_TLS_CERT_OLD)" == FATAL ]] && pass || fail "INNGEST_TLS_CERT_OLD must FATAL — a suffixed look-alike is foreign"

# 12c. Static shape of the new write_files entries and the runcmd arm.
TLS_CONF="$(tls_entry /etc/soleur/inngest-tls.conf)"
TLS_UNIT="$(tls_entry /etc/systemd/system/soleur-inngest-tls.service)"
TLS_FETCH="$(tls_entry /usr/local/bin/soleur-inngest-tls)"   # one script: `fetch` mode (ExecStartPre) and the default health mode
TLS_HEALTH="$TLS_FETCH"
TLS_HUNIT="$(tls_entry /etc/systemd/system/soleur-inngest-tls-health.service)"
TLS_HTIMER="$(tls_entry /etc/systemd/system/soleur-inngest-tls-health.timer)"
grep -qE '^  - stunnel4( |$)' "$CLOUD_INIT" && pass || fail "stunnel4 must be in packages:"
[[ -n "$TLS_CONF" && -n "$TLS_UNIT" && -n "$TLS_FETCH" && -n "$TLS_HUNIT" && -n "$TLS_HTIMER" ]] && pass || fail "all five TLS write_files entries must exist (conf, unit, script, health unit, health timer)"
grep -qE '^  - path: /etc/stunnel/' "$CLOUD_INIT" && fail "the stunnel conf must live OUTSIDE /etc/stunnel/ so no packaged unit can glob it" || pass
for _k in 'foreground = yes' 'setuid = stunnel4' 'setgid = stunnel4' 'sslVersionMin = TLSv1.2' 'ciphers = ECDHE+AESGCM:ECDHE+CHACHA20' 'options = NO_TICKET' 'renegotiation = no' 'accept = 10.0.1.40:8443' 'connect = 127.0.0.1:8288' 'cert = /run/soleur-inngest-tls/cert.pem' 'key = /run/soleur-inngest-tls/key.pem'; do
  grep -qxF "$_k" <<<"$TLS_CONF" && pass || fail "stunnel conf must carry exactly: $_k"
done
grep -qE '^(chroot|verify|CAfile|sslVersion) ' <<<"$TLS_CONF" && fail "stunnel conf must not set chroot or client-verify keys" || pass
grep -qE '^EnvironmentFile' <<<"$TLS_UNIT" && fail "the TLS unit must carry NO EnvironmentFile= (the Doppler token must not reach the network-facing process)" || pass
grep -qxF 'ExecStartPre=+/usr/local/bin/soleur-inngest-tls fetch' <<<"$TLS_UNIT" && pass || fail "the key/cert fetch must run as ExecStartPre=+ (root) from the baked script"
grep -qxF 'ExecStart=/usr/bin/stunnel4 /etc/soleur/inngest-tls.conf' <<<"$TLS_UNIT" && pass || fail "ExecStart must run stunnel4 on the out-of-/etc/stunnel conf"
grep -qxF 'Requires=inngest-nftables.service' <<<"$TLS_UNIT" && grep -qE '^After=.*inngest-nftables\.service' <<<"$TLS_UNIT" && pass || fail "the listener must Require and order After inngest-nftables.service (never runs without its drop rule)"
grep -qxF 'Restart=on-failure' <<<"$TLS_UNIT" && grep -qxF 'StartLimitIntervalSec=0' <<<"$TLS_UNIT" && pass || fail "the unit must retry forever (Restart=on-failure + StartLimitIntervalSec=0): a Doppler disruption at boot must not leave it failed"
for _h in NoNewPrivileges=yes ProtectSystem=strict ProtectHome=yes PrivateTmp=yes PrivateDevices=yes MemoryDenyWriteExecute=yes 'SystemCallFilter=@system-service' RuntimeDirectoryPreserve=restart; do
  grep -qxF "$_h" <<<"$TLS_UNIT" && pass || fail "the TLS unit must be hardened: $_h"
done
# stunnel drops privileges with setuid/setgid, so the bounding set must keep exactly those two capabilities.
grep -qxF 'CapabilityBoundingSet=CAP_SETUID CAP_SETGID' <<<"$TLS_UNIT" && pass || fail "CapabilityBoundingSet must be exactly CAP_SETUID CAP_SETGID (an empty set breaks the setuid drop)"
# inngest-server must never depend on the terminator.
if grep -nE '^ *(Requires|Wants|BindsTo|PartOf|Requisite)=.*soleur-inngest-tls\.service' "$CLOUD_INIT" >/dev/null; then fail "nothing may Require/Want/Bind soleur-inngest-tls.service (a terminator fault must not stop the scheduler)"; else pass; fi
grep -q 'inngest-server' <<<"$TLS_UNIT" && fail "the TLS unit must not reference inngest-server" || pass
grep -qE '^ *umask 0077$' <<<"$TLS_FETCH" && pass || fail "the fetch script must set umask 0077 before writing the key"
grep -qE -- '(--token|set -x|bash -x|sh -x|echo .*\$\(doppler)' <<<"$TLS_FETCH" && fail "the fetch script must never put the token on argv, trace, or echo a secret" || pass
grep -qF 'openssl pkey' <<<"$TLS_FETCH" && grep -qE 'openssl x509 .*-pubkey' <<<"$TLS_FETCH" && pass || fail "the fetch script must prove the key matches the cert (public keys compared) before publishing"
grep -qF 'chown root:stunnel4' <<<"$TLS_FETCH" && grep -qF 'chmod 0640' <<<"$TLS_FETCH" && pass || fail "the key must be 0640 root:stunnel4 (a 0600 root key breaks a SIGHUP reload after the setuid drop)"
grep -qF '/etc/default/inngest-doppler' <<<"$TLS_FETCH" && pass || fail "the fetch script must source the Doppler token file itself (the unit has no EnvironmentFile=)"
# Multi-line emit_refusal definer + a call carrying the crit marker: the alert drift guard
# (betterstack-send-failed-alert.test.sh) recognises exactly this shape.
grep -qxF 'emit_refusal() {' <<<"$TLS_HEALTH" && grep -qxF '  logger -p user.crit -t inngest-tls-health "$1"' <<<"$TLS_HEALTH" && pass || fail "the health script must define a MULTI-LINE emit_refusal() logging at user.crit with tag inngest-tls-health"
[[ "$(grep -c 'emit_refusal "SOLEUR_INNGEST_TLS_REFUSED reason=' <<<"$TLS_HEALTH")" == 1 ]] && grep -qE 'r=listener_down' <<<"$TLS_HEALTH" && grep -qE 'r="\$r cert_expiring"' <<<"$TLS_HEALTH" && pass || fail "both refusal reasons (listener_down, cert_expiring) must feed ONE emit_refusal call carrying the marker (a second call line adds a second census case to the alert drift guard)"
grep -qE 'inngest-boot-phone-home\.sh tls-health ' <<<"$TLS_HEALTH" && pass || fail "the periodic row must ship through inngest-boot-phone-home.sh with stage tls-health"
grep -q . < <(grep -E 'logger' <<<"$TLS_HEALTH" | grep -vF 'logger -p user.crit -t inngest-tls-health "$1"') && fail "the health script must have no logger call outside emit_refusal" || pass
grep -qxF 'OnUnitActiveSec=5min' <<<"$TLS_HTIMER" && grep -qE '^After=.*inngest-bs-token-restage\.service' <<<"$TLS_HUNIT" && grep -qxF 'ExecStart=/usr/local/bin/soleur-inngest-tls' <<<"$TLS_HUNIT" && pass || fail "the health timer fires every 5 minutes and its unit runs after inngest-bs-token-restage.service"
# runcmd: arm the listener and the timer, each failing loudly to the boot phone-home.
grep -nE '^ +systemctl enable --now \$u' "$CLOUD_INIT" >/dev/null && grep -qF 'for u in soleur-inngest-tls.service soleur-inngest-tls-health.timer; do' "$CLOUD_INIT" && grep -qE 'inngest-boot-phone-home\.sh tls-enable-FAILED' "$CLOUD_INIT" && pass || fail "runcmd must enable --now the TLS unit and the health timer and report a failure to the boot phone-home (tls-enable-FAILED)"
L_NIC="$(grep -nF 'soleur-inngest-nic-wait ${inngest_private_ip}' "$CLOUD_INIT" | tail -n 1 | cut -d: -f1)"
L_TLSRUN="$(grep -nF 'for u in soleur-inngest-tls.service' "$CLOUD_INIT" | head -n 1 | cut -d: -f1)"
[[ -n "$L_NIC" && -n "$L_TLSRUN" && "$L_NIC" -lt "$L_TLSRUN" ]] && pass || fail "the listener is armed AFTER the private-NIC wait (it binds the private address)"

# 12d. BEHAVIOUR of the fetch script: extracted, paths rewritten into a sandbox, doppler/chown/chgrp
#      stubbed. Fixture material is generated here and thrown away (never a real cert or key).
if command -v openssl >/dev/null 2>&1 && [[ -n "$TLS_FETCH" ]]; then
  tls_fx() { # <dir> <days>
    openssl ecparam -name prime256v1 -genkey -noout -out "$1/key" 2>/dev/null
    openssl req -new -x509 -key "$1/key" -subj /CN=fixture -days "$2" -addext "subjectAltName=IP:10.0.1.40" -out "$1/cert" 2>/dev/null
  }
  tls_sandbox() { # <name> -> $W with stubs and an env file
    W="$TLS_T/$1"; mkdir -p "$W/bin" "$W/fx" "$W/run"
    cat > "$W/bin/doppler" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$W/doppler.argv"
[ -f "$W/fx/$3" ] || exit 1
cat "$W/fx/$3"
STUB
    for _c in chown chgrp; do printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >> "$W/own.log"\n' "$_c" > "$W/bin/$_c"; done
    chmod +x "$W/bin/"*
    printf 'HOME=/root\nDOPPLER_TOKEN=dp.st.prd.FIXTURETOKEN0123456789abcdef\nDOPPLER_CONFIG=prd\n' > "$W/doppler.env"
    printf '%s\n' "$TLS_FETCH" | sed -e "s|/run/soleur-inngest-tls|$W/run/soleur-inngest-tls|g" -e "s|/etc/default/inngest-doppler|$W/doppler.env|g" > "$W/fetch.sh"
    mkdir -p "$W/run/soleur-inngest-tls"
  }
  tls_fetch_run() { ( cd "$W" && PATH="$W/bin:$PATH" W="$W" bash "$W/fetch.sh" fetch >"$W/out" 2>"$W/err"; echo $? ); }
  tls_fx "$TLS_T" 3650
  openssl ecparam -name prime256v1 -genkey -noout -out "$TLS_T/otherkey" 2>/dev/null
  D() { echo "$W/run/soleur-inngest-tls"; }

  tls_sandbox ok; cp "$TLS_T/key" "$W/fx/INNGEST_TLS_KEY"; cp "$TLS_T/cert" "$W/fx/INNGEST_TLS_CERT"
  rc="$(tls_fetch_run)"
  [[ "$rc" == 0 && -s "$(D)/key.pem" && -s "$(D)/cert.pem" ]] && pass || fail "fetch happy path must publish key.pem and cert.pem (rc=$rc)"
  [[ "$(stat -c %a "$(D)/key.pem" 2>/dev/null)" == 640 && "$(stat -c %a "$(D)/cert.pem" 2>/dev/null)" == 644 ]] && pass || fail "published modes must be key 0640, cert 0644"
  [[ "$(stat -c %a "$(D)")" == 750 ]] && grep -qxF "chgrp stunnel4 $(D)" "$W/own.log" && grep -q "^chown root:stunnel4 .*/key.pem\$" "$W/own.log" && pass || fail "the runtime dir must be 0750 group stunnel4 and the key group stunnel4 (own.log: $(tr '\n' '|' < "$W/own.log"))"
  [[ "$(cat "$W/run/soleur-inngest-tls.rc" 2>/dev/null)" == 0 ]] && pass || fail "fetch must record rc 0 for the health emitter"
  [[ "$(ls -A "$(D)" | sort | tr '\n' ' ')" == "cert.pem key.pem " ]] && pass || fail "no temp directory may be left behind (found: $(ls -A "$(D)" | tr '\n' ' '))"
  # No secret on argv, stdout or stderr.
  if grep -qF 'FIXTURETOKEN' "$W/doppler.argv" || grep -qE 'PRIVATE KEY|FIXTURETOKEN' "$W/out" "$W/err"; then fail "the Doppler token / key must never appear on argv, stdout or stderr"; else pass; fi
  [[ "$(grep -c . "$W/doppler.argv")" == 2 ]] && grep -qE '^secrets get INNGEST_TLS_KEY --project soleur-inngest ' "$W/doppler.argv" && pass || fail "fetch must call doppler secrets get exactly twice against soleur-inngest (argv: $(tr '\n' '|' < "$W/doppler.argv"))"

  tls_sandbox mismatch; cp "$TLS_T/otherkey" "$W/fx/INNGEST_TLS_KEY"; cp "$TLS_T/cert" "$W/fx/INNGEST_TLS_CERT"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 && ! -e "$(D)/key.pem" && ! -e "$(D)/cert.pem" && "$(cat "$W/run/soleur-inngest-tls.rc")" != 0 ]] && pass || fail "a key that does not match the cert must fail closed and publish nothing (rc=$rc)"

  tls_sandbox nokey; cp "$TLS_T/cert" "$W/fx/INNGEST_TLS_CERT"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 && ! -e "$(D)/key.pem" ]] && pass || fail "a missing/failed key read must fail closed (rc=$rc)"

  tls_sandbox emptycert; cp "$TLS_T/key" "$W/fx/INNGEST_TLS_KEY"; : > "$W/fx/INNGEST_TLS_CERT"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 && ! -e "$(D)/key.pem" ]] && pass || fail "an empty cert must fail closed (rc=$rc)"

  tls_sandbox garbage; printf 'not a key\n' > "$W/fx/INNGEST_TLS_KEY"; cp "$TLS_T/cert" "$W/fx/INNGEST_TLS_CERT"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 && ! -e "$(D)/key.pem" ]] && pass || fail "an unparseable key must fail closed (rc=$rc)"

  tls_sandbox noenv; cp "$TLS_T/key" "$W/fx/INNGEST_TLS_KEY"; cp "$TLS_T/cert" "$W/fx/INNGEST_TLS_CERT"; rm -f "$W/doppler.env"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 && ! -e "$(D)/key.pem" ]] && pass || fail "a missing Doppler token file must fail closed (rc=$rc)"

  # R3 (P3): a failed re-fetch must not abort the unit start while the preserved RuntimeDirectory already
  # holds a matching, unexpired pair (RuntimeDirectoryPreserve=restart). The rc file still records the cause.
  tls_stale() { # <name> <key> <cert>: Doppler unreachable (no fixtures), pair already published
    tls_sandbox "$1"; cp "$2" "$(D)/key.pem"; cp "$3" "$(D)/cert.pem"
  }
  tls_stale stale "$TLS_T/key" "$TLS_T/cert"
  rc="$(tls_fetch_run)"
  [[ "$rc" == 0 && "$(cat "$W/run/soleur-inngest-tls.rc")" == 93 ]] && cmp -s "$TLS_T/key" "$(D)/key.pem" && cmp -s "$TLS_T/cert" "$(D)/cert.pem" && pass || fail "a failed re-fetch with a valid pair already in place must exit 0, keep the pair and record rc 93 (rc=$rc, rcfile=$(cat "$W/run/soleur-inngest-tls.rc" 2>/dev/null))"
  tls_stale stalemis "$TLS_T/otherkey" "$TLS_T/cert"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 ]] && pass || fail "a failed re-fetch with a MISMATCHED pair in place must still fail the start (rc=$rc)"
  openssl req -new -x509 -key "$TLS_T/key" -subj /CN=fixture -days 1 -addext "subjectAltName=IP:10.0.1.40" -out "$TLS_T/cert1d" 2>/dev/null
  tls_stale staleexp "$TLS_T/key" "$TLS_T/cert1d"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 ]] && pass || fail "a failed re-fetch with a pair that expires within a day must still fail the start (rc=$rc)"
  tls_stale stalehalf "$TLS_T/key" "$TLS_T/cert"; rm -f "$(D)/cert.pem"
  rc="$(tls_fetch_run)"
  [[ "$rc" != 0 ]] && pass || fail "a failed re-fetch with only half a pair in place must still fail the start (rc=$rc)"

  # 12e. BEHAVIOUR of the health emitter: stubs for systemctl, ss, nft, logger, the phone-home
  #      emitter and `openssl s_client`; every other openssl call is real.
  tls_hsandbox() { # <name> <cert> <listening 1|0>
    W="$TLS_T/$1"; mkdir -p "$W/bin" "$W/run/soleur-inngest-tls"
    cp "$2" "$W/run/soleur-inngest-tls/cert.pem"; printf '0\n' > "$W/run/soleur-inngest-tls.rc"
    cat > "$W/bin/systemctl" <<'STUB'
#!/bin/sh
case "$*" in
  is-active*) echo active ;;
  *NRestarts*) echo 2 ;;
esac
STUB
    if [ "$3" = 1 ]; then
      printf '#!/bin/sh\necho "LISTEN 0 128 10.0.1.40:8443 0.0.0.0:*"\n' > "$W/bin/ss"
    else
      printf '#!/bin/sh\nexit 0\n' > "$W/bin/ss"
    fi
    cat > "$W/bin/nft" <<'STUB'
#!/bin/sh
case "$*" in
  *"counter inet soleur_inngest legacy_8288"*) printf 'table inet soleur_inngest {\n\tcounter legacy_8288 {\n\t\tpackets 6 bytes 338\n\t}\n}\n' ;;
  *"counter inet soleur_inngest tls_8443"*) printf 'table inet soleur_inngest {\n\tcounter tls_8443 {\n\t\tpackets 9 bytes 1200\n\t}\n}\n' ;;
  *"chain inet soleur_inngest input"*) cat "$W/chain.txt" ;;
esac
STUB
    printf 'table inet soleur_inngest {\n\tchain input {\n\t\ttype filter hook input priority -10; policy accept;\n\t\tiif "lo" accept\n\t\ttcp dport 8288 ip saddr { 10.0.1.10 } counter name "legacy_8288"\n\t\ttcp dport { 8288, 8289 } ip saddr { 10.0.1.10 } accept\n\t\ttcp dport { 8288, 8289 } drop\n\t\ttcp dport 8443 ip saddr { 10.0.1.10 } counter name "tls_8443"\n\t\ttcp dport 8443 ip saddr { 10.0.1.10 } accept\n\t\ttcp dport 8443 drop\n\t}\n}\n' > "$W/chain.txt"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$W/logger.log"\n' > "$W/bin/logger"
    printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$1" "$2" >> "$W/phone.log"\n' > "$W/phone.sh"
    cat > "$W/bin/openssl" <<'STUB'
#!/bin/sh
if [ "$1" = s_client ]; then
  [ -t 0 ] || timeout 2 cat >/dev/null
  [ -f "$W/served.pem" ] && cat "$W/served.pem"
  exit 0
fi
exec /usr/bin/openssl "$@"
STUB
    if [ "$3" = 1 ]; then cp "$2" "$W/served.pem"; fi
    chmod +x "$W/bin/"* "$W/phone.sh"
    printf '%s\n' "$TLS_HEALTH" | sed -e "s|/run/soleur-inngest-tls|$W/run/soleur-inngest-tls|g" -e "s|/usr/local/bin/inngest-boot-phone-home.sh|$W/phone.sh|g" > "$W/health.sh"
  }
  tls_health_run() { ( cd "$W" && PATH="$W/bin:$PATH" W="$W" bash "$W/health.sh" >"$W/out" 2>"$W/err"; echo $? ); }
  # A cert 30 days from expiry (the 90-day alert threshold).
  openssl ecparam -name prime256v1 -genkey -noout -out "$TLS_T/key30" 2>/dev/null
  openssl req -new -x509 -key "$TLS_T/key30" -subj /CN=fixture -days 30 -addext "subjectAltName=IP:10.0.1.40" -out "$TLS_T/cert30" 2>/dev/null

  tls_hsandbox hok "$TLS_T/cert" 1
  rc="$(tls_health_run)"
  HROW="$(cat "$W/phone.log" 2>/dev/null)"
  HRE='^tls-health\|unit=active nrestarts=2 fetch_rc=0 bind=10\.0\.1\.40:8443 listener=1 served_sha256=[0-9a-f]{64} cert_sha256=[0-9a-f]{64} notafter_days=[0-9]+ legacy_8288_packets=6 tls_8443_packets=9 nft8443_sha256=[0-9a-f]{64} nft_rules=[0-9]+ boot_id=[0-9a-f]{8}$'
  [[ "$rc" == 0 ]] && grep -qE "$HRE" <<<"$HROW" && pass || fail "healthy emit must be exactly one tls-health row with the planned field list in order (rc=$rc row='$HROW')"
  _s="$(printf '%s' "$HROW" | sed -n 's/.*served_sha256=\([0-9a-f]*\).*/\1/p')"; _c="$(printf '%s' "$HROW" | sed -n 's/.* cert_sha256=\([0-9a-f]*\).*/\1/p')"
  _real="$(openssl x509 -in "$TLS_T/cert" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d : | tr 'A-F' 'a-f')"
  [[ -n "$_s" && "$_s" == "$_c" && "$_c" == "$_real" ]] && pass || fail "served_sha256 and cert_sha256 must both equal the lowercase colon-free SHA-256 of the DER cert (served=$_s cert=$_c real=$_real)"
  # R3 (S5): the handshake-failure counter was removed (no consumer; a client that rejects the CA leaves no stunnel error line).
  ! grep -qE 'hs_fail|journalctl|SSL_accept' <<<"$TLS_HEALTH" && pass || fail "the tls-health script must not carry the removed hs_fail_15m field or its journald scan"
  [[ ! -s "$W/logger.log" ]] && pass || fail "a healthy host must not emit the crit refusal marker (logger: $(cat "$W/logger.log"))"
  [[ "$(printf '%s\n' "$HROW" | grep -c .)" == 1 ]] && pass || fail "exactly one phone-home row per run"
  # The phone-home redaction pass must preserve the labelled sha256 fields and the 8-char boot_id.
  _sedexpr="$(tls_entry /usr/local/bin/inngest-boot-phone-home.sh | grep -E "^detail=.*sed -E" | sed -E "s/.*sed -E '([^']*)'.*/\1/")"
  _detail="${HROW#tls-health|}"
  if [[ -n "$_sedexpr" ]] && [[ "$(printf '%s' "$_detail" | sed -E "$_sedexpr")" == "$_detail" ]]; then pass; else fail "the phone-home redaction must leave the tls-health detail intact (labelled sha256 fields, 8-char boot_id)"; fi

  tls_hsandbox hdown "$TLS_T/cert" 0
  rc="$(tls_health_run)"; HROW="$(cat "$W/phone.log" 2>/dev/null)"
  grep -q 'listener=0 served_sha256= ' <<<"$HROW" && pass || fail "a down listener must report listener=0 and an empty served_sha256 (row='$HROW')"
  grep -qE '^-p user\.crit -t inngest-tls-health SOLEUR_INNGEST_TLS_REFUSED reason=listener_down unit=active fetch_rc=0 nrestarts=2 notafter_days=[0-9]+$' "$W/logger.log" 2>/dev/null && pass || fail "listener=0 must emit the crit SOLEUR_INNGEST_TLS_REFUSED reason=listener_down marker (logger: $(cat "$W/logger.log" 2>/dev/null))"

  tls_hsandbox hexp "$TLS_T/cert30" 1
  rc="$(tls_health_run)"; HROW="$(cat "$W/phone.log" 2>/dev/null)"
  grep -qE '^-p user\.crit -t inngest-tls-health SOLEUR_INNGEST_TLS_REFUSED reason=cert_expiring unit=active fetch_rc=0 nrestarts=2 notafter_days=(29|30)$' "$W/logger.log" 2>/dev/null && pass || fail "notafter_days < 90 must emit the crit cert_expiring marker (logger: $(cat "$W/logger.log" 2>/dev/null))"
  grep -qE 'listener=1 .*notafter_days=(29|30) ' <<<"$HROW" && pass || fail "an expiring cert still reports listener=1 with its day count (row='$HROW')"

  tls_hsandbox hboth "$TLS_T/cert30" 0
  rc="$(tls_health_run)"
  [[ "$(grep -c 'SOLEUR_INNGEST_TLS_REFUSED reason=listener_down,cert_expiring ' "$W/logger.log" 2>/dev/null)" == 1 && "$(grep -c . "$W/logger.log")" == 1 ]] && pass || fail "listener=0 AND an expiring cert must emit ONE marker naming both reasons (logger: $(cat "$W/logger.log" 2>/dev/null))"
else
  fail "openssl and the extracted TLS write_files entries are required for the behavioural rows (found openssl=$(command -v openssl || echo none), fetch bytes=${#TLS_FETCH})"
fi
rm -rf "$TLS_T"

# 10. (#10540) The key-rotation route re-propagates BOTH copies from the dedicated random_id, so the
#     dedicated pair must stay rotatable by a plain `-replace` of the random_id: no lifecycle block on the
#     dedicated random_ids or doppler_secrets (an `ignore_changes=[value]` here would swallow the in-place
#     update phase 1 relies on), and the app (soleur/prd) copies in inngest.tf must derive from them.
_tf_block() { # FILE TYPE NAME -> resource block with comment lines removed
  awk -v t="$2" -v n="$3" '
    $0 ~ "^resource \"" t "\" \"" n "\" \\{" { inb=1 }
    inb && /^[[:space:]]*#/ { next }
    inb { print }
    inb && /^}/ { exit }
  ' "$1"
}
for _n in inngest_signing_key_dedicated inngest_event_key_dedicated; do
  _b="$(_tf_block "$HOST_TF" doppler_secret "$_n")"
  if [ -n "$_b" ] && ! grep -q 'lifecycle' <<<"$_b"; then pass; else fail "doppler_secret.${_n} must exist and carry NO lifecycle block (#10540: phase 1 updates it in place)"; fi
  _b="$(_tf_block "$HOST_TF" random_id "$_n")"
  if [ -n "$_b" ] && ! grep -q 'lifecycle' <<<"$_b"; then pass; else fail "random_id.${_n} must exist and carry NO lifecycle block (#10540: -replace must regenerate it)"; fi
done
_app_sign="$(_tf_block "$INNGEST_TF" doppler_secret inngest_signing_key_prd)"
_app_evt="$(_tf_block "$INNGEST_TF" doppler_secret inngest_event_key_prd)"
if grep -q 'value[[:space:]]*=.*random_id\.inngest_signing_key_dedicated\.hex' <<<"$_app_sign" \
   && grep -q 'value[[:space:]]*=[[:space:]]*random_id\.inngest_event_key_dedicated\.hex' <<<"$_app_evt"; then
  pass
else
  fail "app soleur/prd INNGEST_SIGNING_KEY/INNGEST_EVENT_KEY must derive from the dedicated random_id hex (#10540)"
fi
if grep -q 'ignore_changes[[:space:]]*=[[:space:]]*\[value\]' <<<"$_app_sign" \
   && grep -q 'ignore_changes[[:space:]]*=[[:space:]]*\[value\]' <<<"$_app_evt"; then
  pass
else
  fail "app key copies must keep ignore_changes=[value] so a per-merge plan shows no diff (#10540)"
fi
# Harness row: the extractor discriminates (an absent resource yields an empty block, which the loop above FAILS).
if [ -z "$(_tf_block "$HOST_TF" doppler_secret inngest_no_such_secret)" ]; then pass; else fail "block extractor returned text for a resource that does not exist"; fi

# ANTI-VACUITY FLOOR. Reported by printf + exit, never through fail()/pass(), so neutering those
# cannot disarm it. The bound is the exact passing count; raise it with every added assertion.
# 99 -> 100 (#9786): measured 101 before the D1 rewrite (the old floor carried 2 of slack). The rewrite drops the
# pin-drift, pin-as-reference and pin-missing rows (-3), adds a second-file reintroduction row (+1) and the
# neutered-scan harness row (+1): 101 - 3 + 1 + 1 = 100, exact.
# 100 -> 105 (#9786 review fix round): D1-M8 quoted key, D1-M9 inline map, D1-M10 rehearsal-root reintroduction
# (+3), and the D1-V1/V2 value pins on the surviving key (+2). Exact.
# 105 -> 183 (#10136): the TLS block (nft order/pins, isolation rows, write_files shape, fetch and health
# behaviour) adds 78 unconditional assertions (197 passing measured locally, which includes the one
# `nft -c` row that only runs where nft and unprivileged user namespaces exist).
# 183 -> 184 (#10390 defect 3, floor 5->6): the dark-boot replay splits into a DARK6 PASS row and a
# 5-name FATAL row (+1 net new) and the DOPPLER_* strip row rides DARK6 (+0) — 203 passing measured
# locally with the conditional nft row.
# 184 -> 191 (#10540, +7): the dedicated pair carries no lifecycle (4 rows), the app copies derive from the dedicated hex (1)
# and keep ignore_changes (1), plus the extractor harness row (1). The pre-existing slack is unchanged.
# 191 -> 213 (flip-token split review round, K8): the floor had drifted 23 BELOW the suite (214 passing measured; the
# old 191 let 23 assertions vanish unnoticed). It is now the UNCONDITIONAL count: 214 passing includes the one `nft -c`
# row that only runs where nft and unprivileged user namespaces exist, so 213 holds on a runner without them. Still a
# floor (never `-eq`): raise it in the same edit that adds an assertion.
INNGEST_HOST_MIN_ASSERTIONS=213
if [ "$((passes + fails))" -lt "$INNGEST_HOST_MIN_ASSERTIONS" ]; then
  printf 'FAIL: only %s assertions ran against a floor of %s — a section was skipped or the suite narrowed\n' "$((passes + fails))" "$INNGEST_HOST_MIN_ASSERTIONS" >&2
  exit 1
fi

echo ""
echo "=== inngest-host.test.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
