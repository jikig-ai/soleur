#!/usr/bin/env bash
#
# Drift-guards for the WEB-HOST-CLASS header-escrow resources (#9377, ADR-263 R4 narrowing):
# workspaces-luks-header-web.tf — the second R2 bucket and the three secrets that land in
# prd_workspaces_luks_web.
#
# WHY A SEPARATE SUITE. A new file escapes BOTH existing guards: workspaces-luks.test.sh A11 is
# file-scoped to workspaces-luks.tf, and workspaces-luks-header.test.sh pins workspaces-luks-header.tf
# (exactly 2 masked doppler_secrets, name literal soleur-workspaces-luks-header). So this suite
# REPLICATES their two load-bearing properties for the new file — exact per-file cardinality and
# `config = "prd"` nowhere — and adds the one that is new here: nothing in this file may write to
# web-1's own config (`prd_workspaces_luks`), because the whole point of the split is that a
# web-class token cannot read web-1's escrow pair.
#
# Every assertion is MUTATION-TESTED: the predicate is re-run against a deliberately broken copy and
# MUST flip to failing, and a row is only graded when the predicate is GREEN on the real file first
# (positive control). Anchoring is on the syntactic construct inside a brace-depth-extracted resource
# block of comment-stripped code, never a bare token (cq-assert-anchor-not-bare-token).
#
# Run: bash apps/web-platform/infra/workspaces-luks-header-web.test.sh
# Presence under apps/web-platform/infra/ IS registration (run-registered-suites.sh, ADR-252).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# HEADER_WEB_TF is a test seam so the RED state (file absent) can be demonstrated without editing the tree.
TF="${HEADER_WEB_TF:-$DIR/workspaces-luks-header-web.tf}"
HEADER_TF="$DIR/workspaces-luks-header.tf"

[ -f "$TF" ] || { echo "FAIL: workspaces-luks-header-web.tf not found at $TF" >&2; exit 1; }
[ -f "$HEADER_TF" ] || { echo "FAIL: workspaces-luks-header.tf not found at $HEADER_TF" >&2; exit 1; }

WLHW_SCR="$(mktemp -d "${TMPDIR:-/var/tmp}/wlhw.XXXXXXXX")"
trap 'rm -rf "${WLHW_SCR:?}"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

strip_comments() {
  sed -E -e 's~/\*.*\*/~~g' -e 's~^[[:space:]]*(#|//).*$~~' "$1"
}

# Brace-depth extraction (an `awk /^}/` range truncates at the first column-0 `}` of a nested block).
block_of() {
  local file="$1" type="$2" name="$3"
  strip_comments "$file" | awk -v t="$type" -v n="$name" '
    $0 ~ "^resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1 }
    inb {
      print
      d += gsub(/\{/, "{")
      d -= gsub(/\}/, "}")
      if (d <= 0 && NR > 1 && /\}/) { inb = 0 }
    }
  '
}

attr() {
  printf '%s\n' "$1" | sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*\$/\\1/p" | head -1
}

# The three secrets: <resource name> <secret NAME> <value reference>
SECRETS=(
  'workspaces_luks_web_key|WORKSPACES_LUKS_KEY|random_password.workspaces_luks.result'
  'workspaces_luks_web_header_bucket|WORKSPACES_HEADER_BUCKET|cloudflare_r2_bucket.workspaces_luks_header_web.name'
  'workspaces_luks_web_header_r2_endpoint|WORKSPACES_HEADER_R2_ENDPOINT|local.r2_s3_endpoint'
)

# --- Predicates: each takes a file, echoes 1 (holds) / 0 (does not hold) -------------------------

# W1 — the bucket: cloudflare.r2 alias, the web-class name, WEUR hint, prevent_destroy, and DISTINCT from
# both the web-1 header bucket and the tfstate bucket (which holds the passphrase in plaintext state).
p_bucket_shape() {
  local b; b="$(block_of "$1" cloudflare_r2_bucket workspaces_luks_header_web)"
  [ -n "$b" ] || { echo 0; return; }
  [ "$(attr "$b" provider)" = 'cloudflare.r2' ] || { echo 0; return; }
  [ "$(attr "$b" account_id)" = 'var.cf_account_id' ] || { echo 0; return; }
  [ "$(attr "$b" name)" = '"soleur-workspaces-luks-header-web"' ] || { echo 0; return; }
  [ "$(attr "$b" location)" = '"WEUR"' ] || { echo 0; return; }
  [ "$(attr "$b" prevent_destroy)" = 'true' ] || { echo 0; return; }
  if grep -Eq '"soleur-terraform-state"|"soleur-workspaces-luks-header"' <<<"$b"; then echo 0; return; fi
  echo 1
}

# W2 — each of the three secrets: right NAME, right value REFERENCE, masked, project soleur, and its config is a
# REFERENCE to doppler_config.workspaces_luks_web (an edge, so the config exists before the secret; the #6197
# edge). A string literal config would also pass terraform validate, so the argument FORM is asserted.
p_secret_shape() {
  local f="$1" row rname sname sval b
  for row in "${SECRETS[@]}"; do
    IFS='|' read -r rname sname sval <<<"$row"
    b="$(block_of "$f" doppler_secret "$rname")"
    [ -n "$b" ] || { echo 0; return; }
    [ "$(attr "$b" project)" = '"soleur"' ] || { echo 0; return; }
    [ "$(attr "$b" config)" = 'doppler_config.workspaces_luks_web.name' ] || { echo 0; return; }
    [ "$(attr "$b" name)" = "\"$sname\"" ] || { echo 0; return; }
    [ "$(attr "$b" value)" = "$sval" ] || { echo 0; return; }
    [ "$(attr "$b" visibility)" = '"masked"' ] || { echo 0; return; }
  done
  echo 1
}

# W3 — ADDITION-BLINDNESS BACKSTOP for this file (the A11 / header-test shape): exactly one bucket + three
# doppler_secrets and nothing else. No random_password (the passphrase is NEVER re-minted here: the key
# secret is an in-graph REFERENCE to random_password.workspaces_luks, so a rotation cannot drift), no
# service token (tokens live in workspaces-luks-fresh-boot.tf with their own pins), no variable, no `var.`
# reference (hr-tf-variable-no-operator-mint-default), no output/module/data/locals that could launder a value.
p_no_laundering_resource() {
  local f="$1" code
  code="$(strip_comments "$f")"
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource ')" = "4" ] || { echo 0; return; }
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource "cloudflare_r2_bucket"')" = "1" ] || { echo 0; return; }
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource "doppler_secret"')" = "3" ] || { echo 0; return; }
  if grep -Eq '^variable ' <<<"$code"; then echo 0; return; fi
  if grep -Eq '^(output|module|data|locals|provider|terraform|import|moved|removed)[[:space:]{"]' <<<"$code"; then echo 0; return; fi
  if grep -Eq '(^|[^A-Za-z0-9_.])var\.[a-z_]' <<<"$(grep -vE '^[[:space:]]*account_id[[:space:]]*=[[:space:]]*var\.cf_account_id[[:space:]]*$' <<<"$code")"; then echo 0; return; fi
  echo 1
}

# W4 — NO secret in this file lands in shared `prd` or in web-1's own `prd_workspaces_luks`. Either would defeat
# the split: the first hands the pair to every prd consumer, the second puts web-2's passphrase read back on the
# config web-1's token reads. End-anchored so `prd_workspaces_luks_web` (the intended config) is not a false match.
p_no_foreign_config() {
  local code; code="$(strip_comments "$1")"
  if grep -Eq '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd(_workspaces_luks)?"[[:space:]]*$' <<<"$code"; then echo 0; return; fi
  if grep -Eq '"prd_workspaces_luks"' <<<"$code"; then echo 0; return; fi
  # and every config attribute that exists is the reference form
  [ "$(printf '%s\n' "$code" | grep -Ec '^[[:space:]]*config[[:space:]]*=')" = "3" ] || { echo 0; return; }
  [ "$(printf '%s\n' "$code" | grep -Ec '^[[:space:]]*config[[:space:]]*=[[:space:]]*doppler_config\.workspaces_luks_web\.name[[:space:]]*$')" = "3" ] || { echo 0; return; }
  echo 1
}

# W5 — every doppler_secret is masked (count of masked == count of secrets, so a fourth unmasked secret and a
# dropped `masked` line both flip it).
p_all_masked() {
  local code; code="$(strip_comments "$1")"
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource "doppler_secret"')" = "3" ] || { echo 0; return; }
  [ "$(printf '%s\n' "$code" | grep -Ec '^[[:space:]]*visibility[[:space:]]*=[[:space:]]*"masked"[[:space:]]*$')" = "3" ] || { echo 0; return; }
  echo 1
}

# W6 — the web-class bucket and the web-1 bucket are DIFFERENT resources with DIFFERENT names (a copy-paste of the
# web-1 name would make both hosts' escrow collide in one bucket and put the isolation back to nothing).
p_bucket_distinct_from_web1() {
  local w h wn hn
  w="$(block_of "$1" cloudflare_r2_bucket workspaces_luks_header_web)"
  h="$(block_of "$HEADER_TF" cloudflare_r2_bucket workspaces_luks_header)"
  [ -n "$w" ] && [ -n "$h" ] || { echo 0; return; }
  wn="$(attr "$w" name)"; hn="$(attr "$h" name)"
  [ -n "$wn" ] && [ "$wn" != "$hn" ] || { echo 0; return; }
  echo 1
}

# --- Harness ------------------------------------------------------------------------------------

assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}

assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  [ "$($fn "$file")" = "1" ] || { fail "$name: positive control — the predicate is not green on the real file, so this row proves nothing"; return; }
  tmp="$(mktemp "$WLHW_SCR/mut.XXXXXX")"
  sed -E "$sed_expr" "$file" > "$tmp"
  if cmp -s "$file" "$tmp"; then
    fail "$name: the mutation did not change the file (a mutation that lands nothing proves nothing)"
    rm -f "$tmp"; return
  fi
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION did not flip the check to failing"; fi
  rm -f "$tmp"
}

assert_mutation_append() {
  local name="$1" fn="$2" file="$3" line="$4" tmp got
  [ "$($fn "$file")" = "1" ] || { fail "$name: positive control — the predicate is not green on the real file, so this row proves nothing"; return; }
  tmp="$(mktemp "$WLHW_SCR/mut.XXXXXX")"
  cp "$file" "$tmp"
  printf '%s\n' "$line" >> "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION (appended violating line) did not flip the check to failing"; fi
  rm -f "$tmp"
}

assert_holds "W1 bucket is soleur-workspaces-luks-header-web on cloudflare.r2, WEUR, prevent_destroy, distinct from tfstate/web-1" p_bucket_shape "$TF"
assert_mutation "W1 (name collides with the web-1 bucket)" p_bucket_shape "$TF" 's/"soleur-workspaces-luks-header-web"/"soleur-workspaces-luks-header"/'
assert_mutation "W1 (name is the tfstate bucket)" p_bucket_shape "$TF" 's/"soleur-workspaces-luks-header-web"/"soleur-terraform-state"/'
assert_mutation "W1 (prevent_destroy dropped to false)" p_bucket_shape "$TF" 's/prevent_destroy([[:space:]]*)=([[:space:]]*)true/prevent_destroy\1=\2false/'
assert_mutation "W1 (default cloudflare provider instead of the r2 alias)" p_bucket_shape "$TF" 's/provider([[:space:]]*)=([[:space:]]*)cloudflare\.r2/provider\1=\2cloudflare/'
assert_mutation "W1 (location hint dropped)" p_bucket_shape "$TF" 's/location([[:space:]]*)=([[:space:]]*)"WEUR"/location\1=\2"ENAM"/'

assert_holds "W2 the three secrets carry the right NAME, value reference, masked, config = reference" p_secret_shape "$TF"
assert_mutation "W2 (key secret re-pointed to a literal)" p_secret_shape "$TF" 's/value([[:space:]]*)=([[:space:]]*)random_password\.workspaces_luks\.result/value\1=\2"hunter2"/'
assert_mutation "W2 (key secret name changed)" p_secret_shape "$TF" 's/"WORKSPACES_LUKS_KEY"/"WORKSPACES_LUKS_KEY_X"/'
assert_mutation "W2 (bucket secret value is a literal, not the bucket reference)" p_secret_shape "$TF" 's/value([[:space:]]*)=([[:space:]]*)cloudflare_r2_bucket\.workspaces_luks_header_web\.name/value\1=\2"soleur-terraform-state"/'
assert_mutation "W2 (bucket secret points at the WEB-1 bucket)" p_secret_shape "$TF" 's/value([[:space:]]*)=([[:space:]]*)cloudflare_r2_bucket\.workspaces_luks_header_web\.name/value\1=\2cloudflare_r2_bucket.workspaces_luks_header.name/'
assert_mutation "W2 (endpoint secret value changed)" p_secret_shape "$TF" 's/value([[:space:]]*)=([[:space:]]*)local\.r2_s3_endpoint/value\1=\2"https:\/\/example.test"/'
assert_mutation "W2 (config becomes a string literal)" p_secret_shape "$TF" '/"workspaces_luks_web_key"/,/^}/ s/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_web\.name/config\1=\2"prd_workspaces_luks_web"/'
assert_mutation "W2 (project changed)" p_secret_shape "$TF" '/"workspaces_luks_web_header_bucket"/,/^}/ s/project([[:space:]]*)=([[:space:]]*)"soleur"/project\1=\2"other"/'

assert_holds "W3 exactly one bucket + three doppler_secrets, no password/token/variable/var./output" p_no_laundering_resource "$TF"
assert_mutation_append "W3 attack-1 (a fourth secret written to shared prd)" p_no_laundering_resource "$TF" \
  'resource "doppler_secret" "leak" { config = "prd" }'
assert_mutation_append "W3 attack-2 (a decoy random_password re-minting the passphrase)" p_no_laundering_resource "$TF" \
  'resource "random_password" "decoy" { length = 8 }'
assert_mutation_append "W3 attack-3 (a service token declared here, outside its own pins)" p_no_laundering_resource "$TF" \
  'resource "doppler_service_token" "admin_leak" { access = "admin" }'
assert_mutation_append "W3 attack-4 (an operator-supplied variable)" p_no_laundering_resource "$TF" \
  'variable "web_escrow_key" {}'
assert_mutation_append "W3 attack-5 (an output re-exposing the passphrase)" p_no_laundering_resource "$TF" \
  'output "leak" { value = random_password.workspaces_luks.result }'
assert_mutation "W3 attack-6 (a var. reference smuggled into a value)" p_no_laundering_resource "$TF" \
  's/value([[:space:]]*)=([[:space:]]*)local\.r2_s3_endpoint/value\1=\2var.endpoint/'

assert_holds "W4 no secret lands in shared prd or in web-1's prd_workspaces_luks; all three configs are the reference form" p_no_foreign_config "$TF"
assert_mutation "W4 (key secret moved to shared prd)" p_no_foreign_config "$TF" '/"workspaces_luks_web_key"/,/^}/ s/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_web\.name/config\1=\2"prd"/'
assert_mutation "W4 (key secret moved back to web-1's config — the split undone)" p_no_foreign_config "$TF" '/"workspaces_luks_web_key"/,/^}/ s/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_web\.name/config\1=\2"prd_workspaces_luks"/'
assert_mutation "W4 (endpoint secret moved to the marker config)" p_no_foreign_config "$TF" '/"workspaces_luks_web_header_r2_endpoint"/,/^}/ s/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_web\.name/config\1=\2doppler_config.workspaces_luks_marker.name/'

assert_holds "W5 every doppler_secret is masked" p_all_masked "$TF"
assert_mutation "W5 (one secret unmasked)" p_all_masked "$TF" '/"workspaces_luks_web_header_bucket"/,/^}/ s/visibility([[:space:]]*)=([[:space:]]*)"masked"/visibility\1=\2"unmasked"/'
assert_mutation "W5 (visibility line dropped from one secret)" p_all_masked "$TF" '/"workspaces_luks_web_key"/,/^}/ {/visibility/d}'

assert_holds "W6 the web-class bucket name differs from the web-1 bucket name" p_bucket_distinct_from_web1 "$TF"
assert_mutation "W6 (names collide)" p_bucket_distinct_from_web1 "$TF" 's/"soleur-workspaces-luks-header-web"/"soleur-workspaces-luks-header"/'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---------------------------
# W1 1+5, W2 1+7, W3 1+6, W4 1+3, W5 1+2, W6 1+1 = 6 + 8 + 7 + 4 + 3 + 2 = 30.
total=$((passes + fails))
if [ "$total" -lt 30 ]; then
  echo "FAIL: ran only ${total} assertions (<30) — suite did not execute fully" >&2
  exit 1
fi

echo "workspaces-luks-header-web: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
