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

printf '\n%s passed, %s failed\n' "$PASSES" "$FAILS"
[ "$FAILS" -eq 0 ] && [ "$PASSES" -ge 25 ] || exit 1
