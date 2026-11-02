#!/usr/bin/env bash
# Battery for tests/scripts/lib/tf-redact-random-ids.sh (#11294): the filter that keeps a
# random_id's base64url key bytes out of the PUBLIC `terraform plan/apply` log and the public drift issue.
# Every fixture is SYNTHESIZED (no real key material): K22/K43 are made-up tokens of the two lengths a
# 16-byte / 32-byte random_id renders at. The detector (leaks) is proven live on raw input first, so a green
# run cannot be a detector that matches nothing. Retention rows are shaped like the over-redaction risk.
# shellcheck disable=SC2016
set -uo pipefail

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/scripts/lib/tf-redact-random-ids.sh
source "$SUITE_DIR/lib/tf-redact-random-ids.sh"

PASSES=0 FAILS=0
pass() { PASSES=$((PASSES + 1)); printf '[ok] %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); printf '[FAIL] %s\n' "$1"; }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

K22='Synth-Fixture_0000000a'
K43="${K22}${K22}"; K43="${K43:0:43}"
HEX32='00112233445566778899aabbccddeeff'
[ "${#K22}" -eq 22 ] && [ "${#K43}" -eq 43 ] || { printf 'FAIL SETUP: token lengths %s/%s\n' "${#K22}" "${#K43}" >&2; exit 2; }

# A quoted or [id=]-bracketed 22- or 43-char base64url token (resource names are never exactly 22/43 long here).
leaks() { grep -qE "(\[id=|\")[A-Za-z0-9_-]{22}(\]|\")|(\[id=|\")[A-Za-z0-9_-]{43}(\]|\")" <<<"$1"; }
contains() { grep -qF -- "$2" <<<"$1"; }
absent() { ! grep -qF -- "$2" <<<"$1"; }
clean() { ! leaks "$1"; }
nlines() { printf '%s\n' "$1" | wc -l; }

# --- Refreshing / Creation / Modification / Destruction / Read lines -------------------------------------
LINES="random_id.inngest_signing_key_dedicated: Refreshing state... [id=$K22]
random_id.inngest_event_key_dedicated: Refreshing state... [id=$K43]
module.m.random_password.x: Creation complete after 0s [id=$K43]
random_id.inngest_signing_key_dedicated: Modifying... [id=$K22]
random_string.s: Destroying... [id=$K22]
random_uuid.u: Refreshing state... [id=$K22]
random_bytes.b: Refreshing state... [id=$K43]
random_id.r: Read complete after 0s [id=$K22]"

# instrument control: the detector fires on the raw (unredacted) input, so the green rows below are not vacuous
leaks "$LINES"; check "positive control: detector flags the raw random_* lines" "$?"
OUT="$(tf_redact_random_ids <<<"$LINES")"
[ "$OUT" != "$LINES" ]; check "positive control: helper changed a known-positive input" "$?"
clean "$OUT"; check "no 22- or 43-char token survives on any random_* line" "$?"
[ "$(nlines "$OUT")" = "$(nlines "$LINES")" ]; check "line count preserved" "$?"
for addr in random_id.inngest_signing_key_dedicated random_id.inngest_event_key_dedicated module.m.random_password.x random_string.s random_uuid.u random_bytes.b random_id.r; do
  contains "$OUT" "$addr"; check "address kept: $addr" "$?"
done
contains "$OUT" 'Refreshing state... [id=<redacted>]'; check "Refreshing line keeps its shape with the value blanked" "$?"
contains "$OUT" 'Creation complete after 0s [id=<redacted>]'; check "Creation complete line keeps its shape" "$?"

# --- plan diff blocks (modify/destroy print b64_*/hex/dec un-redacted: random_id attributes are not sensitive) --
BLOCK="  # random_id.inngest_signing_key_dedicated will be destroyed
  - resource \"random_id\" \"inngest_signing_key_dedicated\" {
      - b64_std     = \"$K22\" -> null
      - b64_url     = \"$K22\" -> null
      - byte_length = 16 -> null
      - dec         = \"123456789012345678901234567890123456789\" -> null
      - hex         = \"$HEX32\" -> null
      - id          = \"$K22\" -> null
      - keepers     = {
          - \"rotation\" = \"2026-10\"
        } -> null
    }

  # hcloud_volume.inngest_redis_luks will be updated in-place
  ~ resource \"hcloud_volume\" \"inngest_redis_luks\" {
        id        = \"12345\"
        name      = \"inngest-redis-luks\"
    }
Plan: 0 to add, 1 to change, 1 to destroy."
BOUT="$(tf_redact_random_ids <<<"$BLOCK")"
clean "$BOUT"; check "plan block: no key token survives (b64_std/b64_url/id)" "$?"
absent "$BOUT" "$HEX32"; check "plan block: hex value redacted" "$?"
absent "$BOUT" '123456789012345678901234567890123456789'; check "plan block: dec value redacted" "$?"
contains "$BOUT" '# random_id.inngest_signing_key_dedicated will be destroyed'; check "plan block: header address kept" "$?"
contains "$BOUT" 'byte_length = 16 -> null'; check "plan block: non-secret attribute kept" "$?"
contains "$BOUT" '"rotation" = "2026-10"'; check "plan block: keepers entry kept" "$?"
[ "$(nlines "$BOUT")" = "$(nlines "$BLOCK")" ]; check "plan block: line count preserved" "$?"
contains "$BOUT" '        id        = "12345"'; check "retention: the next resource's id line is NOT redacted (block ends at its closing brace)" "$?"
contains "$BOUT" 'Plan: 0 to add, 1 to change, 1 to destroy.'; check "retention: Plan summary kept" "$?"

# --- retention fixtures (shaped like the over-redaction risk) -------------------------------------------------
KEEP="hcloud_volume.inngest_redis_luks: Refreshing state... [id=12345]
hcloud_server.inngest: Refreshing state... [id=98765432]
doppler_secret.inngest_signing_key_dedicated: Refreshing state... [id=soleur/prd/INNGEST_SIGNING_KEY]
ghcr.io/jikig-ai/soleur@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  inngest connect --gateway 10.0.1.5:8289 --signing-key-fallback registry.internal:5000
Initializing the backend...
Plan: 1 to add, 0 to change, 0 to destroy."
KOUT="$(tf_redact_random_ids <<<"$KEEP")"
[ "$KOUT" = "$KEEP" ]; check "retention: hetzner [id=12345], sha256 digest, host:port and non-random lines are byte-identical" "$?"

# --- exit status: the filter never masks the producer's status; callers read PIPESTATUS[0] ---------------
{ printf 'random_id.x: Refreshing state... [id=%s]\n' "$K22"; exit 3; } | tf_redact_random_ids >/dev/null 2>&1
st=("${PIPESTATUS[@]}")
[ "${st[0]}" = "3" ]; check "producer exit status 3 is readable via PIPESTATUS[0] through the filter" "$?"
[ "${st[1]}" = "0" ]; check "filter itself exits 0" "$?"
tf_redact_random_ids </dev/null >/dev/null; check "empty input exits 0" "$?"
EMPTY="$(printf '' | tf_redact_random_ids)"; [ -z "$EMPTY" ]; check "empty input yields empty output" "$?"
NOLF="$(printf 'random_id.x: Refreshing state... [id=%s]' "$K22" | tf_redact_random_ids; printf x)"
[ "$NOLF" = 'random_id.x: Refreshing state... [id=<redacted>]x' ]; check "a missing trailing newline is not invented" "$?"

# --- ANSI colour (#11294 follow-up): a step without -no-color prints `ESC[0mESC[1mrandom_id.X: ... [id=<key>]ESC[0m` ------
# The first real apply run leaked ONE line this way: the bold sequence ends in `m`, an alphanumeric, so the address was not
# preceded by a non-word character and the address anchor never matched. The filter must see the line the way a human does.
ESC=$'\033'
ANSI="${ESC}[0m${ESC}[1mrandom_id.tunnel_secret: Refreshing state... [id=$K43]${ESC}[0m
${ESC}[0m${ESC}[1mrandom_password.zot_pull: Refreshing state... [id=none]${ESC}[0m
${ESC}[0m${ESC}[1mhcloud_volume.v: Refreshing state... [id=12345]${ESC}[0m
${ESC}[0m${ESC}[1mrandom_id.inngest_signing_key_dedicated: Creation complete after 0s [id=$K43]${ESC}[0m"
leaks "$ANSI"; check "ansi positive control: the detector flags the raw coloured lines" "$?"
AOUT="$(tf_redact_random_ids <<<"$ANSI")"
clean "$AOUT"; check "ansi: no 22- or 43-char token survives on a coloured random_* line" "$?"
contains "$AOUT" 'random_id.tunnel_secret: Refreshing state... [id=<redacted>]'; check "ansi: the coloured Refreshing line is redacted and keeps its address" "$?"
contains "$AOUT" 'random_id.inngest_signing_key_dedicated: Creation complete after 0s [id=<redacted>]'; check "ansi: the coloured Creation complete line is redacted" "$?"
contains "$AOUT" 'hcloud_volume.v: Refreshing state... [id=12345]'; check "ansi: a coloured non-random line keeps its text" "$?"
[ "$(nlines "$AOUT")" = "$(nlines "$ANSI")" ]; check "ansi: line count preserved" "$?"
ABLOCK="${ESC}[1m  # random_id.k${ESC}[0m will be destroyed
${ESC}[0m  ${ESC}[31m-${ESC}[0m resource \"random_id\" \"k\" {
      ${ESC}[31m-${ESC}[0m hex         = \"$HEX32\" -> null
      ${ESC}[31m-${ESC}[0m id          = \"$K22\" -> null
    }
  ${ESC}[1m# hcloud_volume.v${ESC}[0m will be updated in-place
        id        = \"12345\""
ABOUT="$(tf_redact_random_ids <<<"$ABLOCK")"
absent "$ABOUT" "$HEX32"; check "ansi plan block: the hex value is redacted" "$?"
clean "$ABOUT"; check "ansi plan block: no key token survives" "$?"
contains "$ABOUT" '        id        = "12345"'; check "ansi plan block: the next resource's id line is NOT redacted" "$?"
NOCSI="$(printf 'plain %s text, no escapes\n' "[ok]" | tf_redact_random_ids)"; [ "$NOCSI" = 'plain [ok] text, no escapes' ]; check "ansi: a line with brackets but no escape sequence is byte-identical" "$?"

# --- every header shape that prints a random_* block (#11294 PR-F) ---------------------------------------------------
# The block-start used to need `will be|must be` right after the address, so `is tainted, so must be replaced`,
# `(deposed object ...) will be destroyed` and the `has changed` drift blocks printed old AND new key bytes in the clear.
# Each row has a STABLE LABEL: the key-rotate workflow's guard job greps this suite's output for these labels before it
# dispatches anything, so renaming one is a contract change. Values are synthesized, built by concatenation.
N22="${K22%a}b"
OLD_HEX="${HEX32}"
NEW_HEX="ffeeddccbbaa99887766554433221100"
OLD_DEC="123456789012345678901234567890123456789"
NEW_DEC="987654321098765432109876543210987654321"
[ "${#N22}" -eq 22 ] && [ "$N22" != "$K22" ] || { printf 'FAIL SETUP: N22\n' >&2; exit 2; }

# mkblock <header-without-leading-comment-marker> <mode>   mode: pair (old -> new) | null (old -> null) | plus (new only)
mkblock() {
  local hdr="$1" mode="$2" a
  printf '  # %s\n' "$hdr"
  printf '  ~ resource "random_id" "k" {\n'
  for a in b64_std b64_url id; do
    case "$mode" in
      pair) printf '      ~ %-10s = "%s" -> "%s"\n' "$a" "$K22" "$N22" ;;
      null) printf '      - %-10s = "%s" -> null\n' "$a" "$K22" ;;
      plus) printf '      + %-10s = "%s"\n' "$a" "$N22" ;;
    esac
  done
  case "$mode" in
    pair) printf '      ~ hex         = "%s" -> "%s"\n      ~ dec         = "%s" -> "%s"\n' "$OLD_HEX" "$NEW_HEX" "$OLD_DEC" "$NEW_DEC" ;;
    null) printf '      - hex         = "%s" -> null\n      - dec         = "%s" -> null\n' "$OLD_HEX" "$OLD_DEC" ;;
    plus) printf '      + hex         = "%s"\n      + dec         = "%s"\n' "$NEW_HEX" "$NEW_DEC" ;;
  esac
  printf '        byte_length = 16\n    }\n\n'
  printf '  # hcloud_volume.v will be updated in-place\n  ~ resource "hcloud_volume" "v" {\n        id        = "12345"\n    }\nPlan: 1 to add, 1 to change, 1 to destroy.\n'
}

# shape_row <LABEL> <header> <mode>
shape_row() {
  local label="$1" raw out
  raw="$(mkblock "$2" "$3")"
  leaks "$raw" && contains "$raw" "$([ "$3" = plus ] && printf %s "$NEW_HEX" || printf %s "$OLD_HEX")"; check "$label: detector flags the raw block (live positive control)" "$?"
  out="$(tf_redact_random_ids <<<"$raw")"
  clean "$out"; check "$label: no 22- or 43-char key token survives (b64_std/b64_url/id)" "$?"
  if [ "$3" = plus ]; then
    absent "$out" "$NEW_HEX"; check "$label: hex redacted" "$?"
    absent "$out" "$NEW_DEC"; check "$label: dec redacted" "$?"
  else
    absent "$out" "$OLD_HEX"; check "$label: hex redacted on the left of ->" "$?"
    absent "$out" "$OLD_DEC"; check "$label: dec redacted on the left of ->" "$?"
    absent "$out" "$K22"; check "$label: old b64/id value redacted on the left of ->" "$?"
  fi
  if [ "$3" = pair ]; then
    absent "$out" "$NEW_HEX"; check "$label: hex redacted on the right of ->" "$?"
    absent "$out" "$NEW_DEC"; check "$label: dec redacted on the right of ->" "$?"
    absent "$out" "$N22"; check "$label: new b64/id value redacted on the right of ->" "$?"
  fi
  contains "$out" "# $2"; check "$label: header text and address kept" "$?"
  contains "$out" 'byte_length = 16'; check "$label: non-secret attribute kept" "$?"
  contains "$out" '        id        = "12345"'; check "$label: the next resource's id line is NOT redacted (block ends at its closer)" "$?"
  contains "$out" 'Plan: 1 to add, 1 to change, 1 to destroy.'; check "$label: Plan summary kept" "$?"
  [ "$(nlines "$out")" = "$(nlines "$raw")" ]; check "$label: line count preserved" "$?"
}

shape_row tainted-must-be-replaced   'random_id.k is tainted, so must be replaced' pair
shape_row replaced-as-requested      'random_id.k will be replaced, as requested' pair
shape_row destroyed                  'random_id.k will be destroyed' null
shape_row created                    'random_id.k will be created' plus
shape_row deposed-will-be-destroyed  'random_id.k (deposed object abc12345) will be destroyed' null
shape_row drift-has-changed          'random_id.k has changed' pair
shape_row module-tainted             'module.m.random_password.k is tainted, so must be replaced' pair

# --- regression: widening the block-start must not reach other resources or change the shape of the log ------------------
HZ="hcloud_server.web: Refreshing state... [id=12345]
  # hcloud_server.web is tainted, so must be replaced
  -/+ resource \"hcloud_server\" \"web\" {
      ~ id          = \"12345\" -> (known after apply)
        name        = \"web\"
    }
  # hcloud_server.web has changed
  ~ resource \"hcloud_server\" \"web\" {
      ~ id          = \"12345\" -> \"67890\"
    }
  # hcloud_volume.v (deposed object abc12345) will be destroyed
  - resource \"hcloud_volume\" \"v\" {
      - id          = \"12345\" -> null
    }"
HZOUT="$(tf_redact_random_ids <<<"$HZ")"
[ "$HZOUT" = "$HZ" ]; check "regression: tainted, drift and deposed blocks of a NON-random resource (hetzner [id=12345]) are byte-identical" "$?"

# --- stuck states: the widened block-start applies to every Terraform job, so a malformed log must stay a log ---------------
UNTERM="  # random_id.k is tainted, so must be replaced
  -/+ resource \"random_id\" \"k\" {
      ~ id          = \"$K22\" -> \"$N22\"
      ~ hex         = \"$OLD_HEX\" -> \"$NEW_HEX\"
Error: Invalid provider configuration
  with provider[\"registry.terraform.io/hetznercloud/hcloud\"],
The diagnostic text after an unterminated block stays readable."
UTOUT="$(tf_redact_random_ids <<<"$UNTERM")"; rc=$?
[ "$rc" = "0" ]; check "stuck-state unterminated block: filter exits 0" "$?"
clean "$UTOUT"; check "stuck-state unterminated block: key tokens inside it are still redacted" "$?"
absent "$UTOUT" "$OLD_HEX"; check "stuck-state unterminated block: hex still redacted" "$?"
contains "$UTOUT" 'Error: Invalid provider configuration'; check "stuck-state unterminated block: the later Error line is readable" "$?"
contains "$UTOUT" 'The diagnostic text after an unterminated block stays readable.'; check "stuck-state unterminated block: the later prose line is readable" "$?"
[ "$(nlines "$UTOUT")" = "$(nlines "$UNTERM")" ]; check "stuck-state unterminated block: line count preserved" "$?"

EOIN="  # random_id.k (deposed object abc12345) will be destroyed
  - resource \"random_id\" \"k\" {
      - hex         = \"$OLD_HEX\" -> null
      - id          = \"$K22\" -> null"
EOUT="$(printf '%s' "$EOIN" | tf_redact_random_ids; printf x)"
case "$EOUT" in *x) EOUT="${EOUT%x}" ;; esac
clean "$EOUT"; check "stuck-state end-of-input mid-block: key token redacted" "$?"
absent "$EOUT" "$OLD_HEX"; check "stuck-state end-of-input mid-block: hex redacted" "$?"
[ "$(nlines "$EOUT")" = "$(nlines "$EOIN")" ]; check "stuck-state end-of-input mid-block: no trailing newline invented, line count kept" "$?"

LATER="$(mkblock 'random_id.k is tainted, so must be replaced' pair)
Error: Unsupported argument
  on main.tf line 7, in resource \"hcloud_volume\" \"v\":
 This line mentions random_id.k and stays readable."
LOUT="$(tf_redact_random_ids <<<"$LATER")"
clean "$LOUT"; check "stuck-state later diagnostic: block redacted" "$?"
contains "$LOUT" 'Error: Unsupported argument'; check "stuck-state later diagnostic: Error line readable" "$?"
contains "$LOUT" '  on main.tf line 7, in resource "hcloud_volume" "v":'; check "stuck-state later diagnostic: location line readable" "$?"
contains "$LOUT" ' This line mentions random_id.k and stays readable.'; check "stuck-state later diagnostic: prose naming a random_* address readable" "$?"
[ "$(nlines "$LOUT")" = "$(nlines "$LATER")" ]; check "stuck-state later diagnostic: line count preserved" "$?"

printf '\n%s passed, %s failed\n' "$PASSES" "$FAILS"
[ "$FAILS" -eq 0 ] && [ "$PASSES" -ge 25 ] || exit 1
