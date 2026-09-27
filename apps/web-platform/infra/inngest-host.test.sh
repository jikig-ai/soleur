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

# 1b. (#6178) The host-boot token MUST be read/write, NOT read-only. The cutover flip FSM
#     (inngest-cutover-flip.sh:flag_set) advances INNGEST_CUTOVER_FLIP on soleur-inngest/prd
#     via `doppler secrets set` under this token; a read-only token fails that write at the
#     FIRST transition (flag_set flipping), so the dedicated scheduler can never complete the
#     flip. Extract the access value from the token resource block specifically (not a bare
#     file-wide grep that a comment could satisfy), so a silent revert to "read" red-lines CI.
#     The awk SKIPS in-block comment lines and requires `access` at STATEMENT position
#     (^[[:space:]]*access) — a bare `access[[:space:]]*=` match plus no comment-skip is
#     defeated by an in-block decoy comment (`# access = "read/write"`) sitting above the real
#     read-only attribute (awk matches the comment first, prints read/write, exits green).
TOKEN_ACCESS="$(awk '
  /resource "doppler_service_token" "inngest"/ { inblk=1; next }
  inblk && /^[[:space:]]*#/ { next }
  inblk && /^[[:space:]]*access[[:space:]]*=/ { gsub(/[",]/,""); print $NF; exit }
  inblk && /^}/ { exit }
' "$HOST_TF")"
[[ "$TOKEN_ACCESS" == "read/write" ]] \
  && pass || fail "doppler_service_token.inngest access must be 'read/write' so the flip FSM can write INNGEST_CUTOVER_FLIP (got '${TOKEN_ACCESS:-<none>}'); a read-only token boot-fails the flip at its first transition (#6178)"
# Cross-check: the flip script's flag_set genuinely writes under the ambient (boot-token) env —
# if flag_set ever grows an explicit --token, this test's premise (boot token authorizes the
# write) must be re-derived rather than trusted. Scope to the WHOLE flag_set function body
# (awk between `flag_set() {` and the closing `}`), not a single line — the real write spans
# two physical lines (`doppler secrets set … \` then `  --project … --silent`), so a --token
# added on the continuation line would evade a line-scoped grep.
FLAG_SET_BODY="$(awk '/^flag_set\(\)[[:space:]]*\{/{i=1} i{print} i&&/^\}/{exit}' "${DIR}/inngest-cutover-flip.sh")"
printf '%s\n' "$FLAG_SET_BODY" | grep -cE 'doppler secrets set INNGEST_CUTOVER_FLIP' >/dev/null \
  && ! printf '%s\n' "$FLAG_SET_BODY" | grep -cE -- >/dev/null '--token' \
  && pass || fail "flip flag_set must write INNGEST_CUTOVER_FLIP under the ambient boot token (no explicit --token anywhere in the function body) — else the read/write requirement above is testing the wrong credential"

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
  && grep -qF ':/vector.toml /tmp/vector.toml' "$CLOUD_INIT" \
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
#    proves the token is a sibling of the INNGEST_ group, not inside it. Floor rose 4->5.
grep -qF 'HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)' "$CLOUD_INIT" \
  && grep -qF '"$n_inngest" -lt 5' "$CLOUD_INIT" \
  && pass || fail "isolation self-check admits BETTERSTACK_LOGS_TOKEN (top-level) and the floor is -lt 5"
# The old floor must be gone.
if grep -qF '"$n_inngest" -lt 4' "$CLOUD_INIT"; then
  fail "isolation floor must be -lt 5, not the old -lt 4"
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
GUARD_RE="$(grep -E "n_inngest=.*grep -Ec" "$CLOUD_INIT" | grep -oE "grep -Ec '[^']*'" | sed "s/grep -Ec '//; s/'$//")"
FLOOR="$(grep -oE '\[ "\$n_inngest" -lt [0-9]+ \]' "$CLOUD_INIT" | grep -oE '[0-9]+' | sed -n '1p')"
# Non-vacuity: a failed extraction must NOT silently pass every case below. An empty GUARD_RE
# makes `grep -Ec ""` match every line, which would fake a clean replay.
[[ -n "$GUARD_RE" ]] && pass || fail "could not extract the admit-regex from $CLOUD_INIT (the replay below would be vacuous)"
[[ "$FLOOR" == "5" ]] && pass || fail "could not extract the cardinality floor, or it is not 5 (got '${FLOOR:-<empty>}') — see the DEC-FLOOR note in cloud-init-inngest.yml before changing it"

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

# Dark boot (pre-arm) must PASS — the host has to bootstrap before any cutover.
[[ "$(isolation_decision "${DARK5[@]}")" == PASS ]] && pass || fail "dark 5-secret boot must PASS the isolation self-check"
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
[[ "$(isolation_decision "${DARK5[@]}" DOPPLER_PROJECT DOPPLER_CONFIG)" == PASS ]] && pass || fail "DOPPLER_* builtins must be stripped before counting"

# 9c. Pin the COMPARISON OPERATOR. The replay above re-derives the predicate, so it cannot see
#     an inversion in the file itself: flipping -ne to -eq makes an isolated host FATAL and a
#     LEAKY one boot clean, with every behavioral case above still green.
# shellcheck disable=SC2016  # literal $n_total/$n_inngest is intentional — matching the file's text
grep -qF '[ "$n_total" -ne "$n_inngest" ]' "$CLOUD_INIT" \
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
if grep -qE 'cosign[- ]verif' "$CLOUD_INIT" && ! grep -qE '^[[:space:]]*cosign verify[[:space:]]' "$CLOUD_INIT"; then
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
  if grep -qE "docker cp soleur-inngest-bootstrap-extract:/${asset//./\\.} /tmp/${asset//./\\.}" "$CLOUD_INIT"; then
    pass
  else
    fail "cloud-init-inngest.yml must 'docker cp soleur-inngest-bootstrap-extract:/${asset} /tmp/${asset}' — bootstrap's install-gate requires it at /tmp; without the cp DEDICATED_FLIP=0 and the flip timer never installs (#6178)"
  fi
done
# The staging outcome must self-report off-box (the silent absence hid the bug for a full
# cutover attempt): assert a flip-assets phone-home marker exists.
grep -qE 'inngest-boot-phone-home\.sh flip-assets-(staged|MISSING)' "$CLOUD_INIT" \
  && pass || fail "cloud-init-inngest.yml must phone-home the flip-assets staging outcome (flip-assets-staged / flip-assets-MISSING) so a future staging failure self-diagnoses off-box (#6178)"

# ANTI-VACUITY FLOOR. Reported by printf + exit, never through fail()/pass(), so neutering those
# cannot disarm it. The bound is the exact passing count; raise it with every added assertion.
INNGEST_HOST_MIN_ASSERTIONS=82
if [ "$((passes + fails))" -lt "$INNGEST_HOST_MIN_ASSERTIONS" ]; then
  printf 'FAIL: only %s assertions ran against a floor of %s — a section was skipped or the suite narrowed\n' "$((passes + fails))" "$INNGEST_HOST_MIN_ASSERTIONS" >&2
  exit 1
fi

echo ""
echo "=== inngest-host.test.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
