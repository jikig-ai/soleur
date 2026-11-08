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

PASSES=0 FAILS=0 CHECKS=0
pass() { PASSES=$((PASSES + 1)); printf '[ok] %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); printf '[FAIL] %s\n' "$1"; }
check() { CHECKS=$((CHECKS + 1)); if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

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

# Controls for the helpers that OWN a verdict (a positive control on pass()/fail() cannot see these): each must be able to say
# NO. They report with printf+exit directly, never through the helpers under test, and are not counted as assertions.
_c_ok="$(check "ctl-ok" 0)"; _c_bad="$(check "ctl-bad" 1)"
if [ "$_c_ok" != "[ok] ctl-ok" ] || [ "$_c_bad" != "[FAIL] ctl-bad" ]; then printf 'FATAL: check() cannot tell pass from fail\n' >&2; exit 1; fi
if absent "xAy" "A" || ! absent "xBy" "A" || clean "[id=$K22]" || clean "[id=$K43]" || ! clean "plain text"; then printf 'FATAL: absent()/clean() control failed\n' >&2; exit 1; fi
if ! contains "abc" "b" || contains "abc" "z"; then printf 'FATAL: contains() control failed\n' >&2; exit 1; fi
_c_two="$(check "ctl-two" 2)"; _c_pb="$(pass x >/dev/null; printf %s "$PASSES")"; _c_fb="$(fail x >/dev/null; printf %s "$FAILS")"
if [ "$_c_two" != "[FAIL] ctl-two" ] || [ "$_c_pb" != "$((PASSES + 1))" ] || [ "$_c_fb" != "$((FAILS + 1))" ]; then printf 'FATAL: pass()/fail()/check(2) control failed\n' >&2; exit 1; fi


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
  local label="$1" raw out fails_before="$FAILS"
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
  # ONE verdict per shape. A consumer must grep `^\[ok\] <label>: verdict` (anchored at the line start AND on the verdict
  # text): a bare `^\[ok\] .*<label>` is satisfied by any [ok] row of the shape (the old lib still prints six per label), and
  # `destroyed` is a suffix of `deposed-will-be-destroyed`.
  [ "$FAILS" = "$fails_before" ]; check "$label: verdict - every row of this shape passed" "$?"
}

shape_row tainted-must-be-replaced   'random_id.k is tainted, so must be replaced' pair
shape_row replaced-as-requested      'random_id.k will be replaced, as requested' pair
shape_row destroyed                  'random_id.k will be destroyed' null
shape_row created                    'random_id.k will be created' plus
shape_row deposed-will-be-destroyed  'random_id.k (deposed object abc12345) will be destroyed' null
shape_row drift-has-changed          'random_id.k has changed' pair
shape_row module-tainted             'module.m.random_password.k is tainted, so must be replaced' pair
shape_row indexed-for-each           'random_id.k["a b"] is tainted, so must be replaced' pair
shape_row indexed-count              'random_id.k[0] has changed' pair
shape_row module-for-each-deposed    'module.m["x y"].random_id.k (deposed object abc12345) will be destroyed' null

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

# --- every member of both literal sets is its own window: type x attribute table (all 5 types, all 8 attributes) ----------
# A value of 50+ chars (a real 32-byte key renders 43 b64 chars / 64 hex chars), distinct per attribute, so dropping ANY one
# alternation member (e.g. `result|base64|b64`, `string|uuid|bytes`) reddens exactly its rows. The raw block is proven live first.
for t in id password string uuid bytes; do
  for a in id b64_std b64_url hex dec result base64 b64; do
    vo="SynthOld_${a}_$(printf '0%.0s' {1..50})"; vn="SynthNew_${a}_$(printf '1%.0s' {1..50})"
    raw="$(printf '  # random_%s.m will be updated in-place\n  ~ resource "random_%s" "m" {\n      ~ %-10s = "%s" -> "%s"\n        byte_length = 16\n    }\n\n  # hcloud_volume.v will be updated in-place\n  ~ resource "hcloud_volume" "v" {\n        id        = "12345"\n    }\n' "$t" "$t" "$a" "$vo" "$vn")"
    out="$(tf_redact_random_ids <<<"$raw")"
    contains "$raw" "$vo" && contains "$raw" "$vn"; check "member-$t-$a: raw block carries both values (live positive control)" "$?"
    absent "$out" "$vo" && absent "$out" "$vn"; check "member-$t-$a: old and new value redacted" "$?"
    contains "$out" '        id        = "12345"' && contains "$out" 'byte_length = 16'; check "member-$t-$a: block ends at its closer, non-secret attribute kept" "$?"
  done
done

# --- the closer is the RESOURCE closer: a nested block closing at another indent must not end the range early ------------
NEST="  # random_id.k will be updated in-place
  ~ resource \"random_id\" \"k\" {
      ~ keepers     = {
          ~ \"rot\" = \"a\" -> \"b\"
        }
      ~ hex         = \"$OLD_HEX\" -> \"$NEW_HEX\"
      ~ id          = \"$K22\" -> \"$N22\"
    }
  # hcloud_volume.v will be updated in-place
  ~ resource \"hcloud_volume\" \"v\" {
        id        = \"12345\"
    }"
NOUT="$(tf_redact_random_ids <<<"$NEST")"
leaks "$NEST" && contains "$NEST" "$OLD_HEX"; check "nested block: detector flags the raw block (live positive control)" "$?"
absent "$NOUT" "$OLD_HEX" && absent "$NOUT" "$NEW_HEX" && clean "$NOUT"; check "nested block: secrets AFTER a nested closer are still redacted" "$?"
contains "$NOUT" '"rot" = "a" -> "b"'; check "nested block: a non-secret keepers entry is kept" "$?"
contains "$NOUT" '        id        = "12345"'; check "nested block: the next resource's id line is NOT redacted" "$?"

# --- header edge shapes ----------------------------------------------------------------------------------------------
# `terraform show` / `state show` print `# random_id.k:` (bare address, colon) with a column-0 resource body and closer.
SHOWIN="# random_id.k:
resource \"random_id\" \"k\" {
    b64_std     = \"$K22\"
    hex         = \"$OLD_HEX\"
    id          = \"$K22\"
}
# hcloud_volume.v:
resource \"hcloud_volume\" \"v\" {
    id          = \"12345\"
}"
SHOWOUT="$(tf_redact_random_ids <<<"$SHOWIN")"
leaks "$SHOWIN"; check "show-shape: detector flags the raw block (live positive control)" "$?"
clean "$SHOWOUT" && absent "$SHOWOUT" "$OLD_HEX"; check "show-shape: bare '# random_id.k:' block is redacted" "$?"
contains "$SHOWOUT" '    id          = "12345"'; check "show-shape: the next resource's id line is NOT redacted" "$?"
SHOWNEST="# random_string.s:
resource \"random_string\" \"s\" {
    id          = \"$K22\"
    keepers     = {
        \"rot\" = \"a\"
    }
    result      = \"SynthShowResult_$(printf '2%.0s' {1..40})\"
}
# hcloud_volume.v:
resource \"hcloud_volume\" \"v\" {
    id          = \"12345\"
}"
SNOUT="$(tf_redact_random_ids <<<"$SHOWNEST")"
contains "$SHOWNEST" 'SynthShowResult_' && contains "$SHOWNEST" "$K22"; check "show-shape nested map: raw block carries the values (live positive control)" "$?"
absent "$SNOUT" 'SynthShowResult_' && absent "$SNOUT" "$K22"; check "show-shape nested map: id AND result AFTER a 4-space keepers closer are redacted (column-0 closer only)" "$?"
contains "$SNOUT" '"rot" = "a"' && contains "$SNOUT" '    id          = "12345"'; check "show-shape nested map: keepers entry and the next resource's id are kept" "$?"
# Real `terraform show` suffixes: `(tainted)`, `(deposed object ..)`, trailing whitespace and a CR (CRLF log).
n=0
for hdr in "# random_id.k: (tainted)" "# random_id.k: (deposed object abc12345)" "# random_id.k: " "# random_id.k:$(printf '\r')" "# random_id.k: (tainted) $(printf '\r')"; do
  n=$((n + 1))
  SH2="$hdr
resource \"random_id\" \"k\" {
    hex         = \"$OLD_HEX\"
    id          = \"$K22\"
}
# hcloud_volume.v:
resource \"hcloud_volume\" \"v\" {
    id          = \"12345\"
}"
  SH2OUT="$(tf_redact_random_ids <<<"$SH2")"
  contains "$SH2" "$OLD_HEX" && contains "$SH2" "$K22"; check "show-suffix-$n: raw block carries the values (live positive control)" "$?"
  absent "$SH2OUT" "$OLD_HEX" && absent "$SH2OUT" "$K22" && contains "$SH2OUT" '    id          = "12345"'; check "show-suffix-$n: block redacted, the next resource's id kept" "$?"
done

BARE="$(printf '  # random_id.k\n  ~ resource "random_id" "k" {\n      ~ hex = "%s" -> "%s"\n    }\n' "$OLD_HEX" "$NEW_HEX" | tf_redact_random_ids)"
absent "$BARE" "$OLD_HEX" && absent "$BARE" "$NEW_HEX"; check "bare-address header (nothing after the address) is redacted" "$?"

# The block-start is word-boundary-led: a non-random address that merely CONTAINS `random_id.` opens nothing.
LB="  # hcloud_server.my_random_id.x will be replaced
  -/+ resource \"hcloud_server\" \"web\" {
      ~ id          = \"12345\" -> \"67890\"
    }"
[ "$(tf_redact_random_ids <<<"$LB")" = "$LB" ]; check "left boundary: '# ..my_random_id.x ...' does not open a block (byte-identical)" "$?"

# A Destroying/Refreshing LINE naming the address (no leading `# `) opens no plan block: the per-line rule redacts its [id=] and the
# next resource's id attribute stays readable. The deposed-object line has a SPACE after the address, i.e. the one non-comment
# shape the address part of the start regex alone would accept.
RF="random_id.k (deposed object abc12345): Destroying... [id=$K22]
  # hcloud_server.web will be updated in-place
  ~ resource \"hcloud_server\" \"web\" {
      ~ id          = \"12345\" -> \"67890\"
    }"
RFOUT="$(tf_redact_random_ids <<<"$RF")"
absent "$RFOUT" "$K22" && contains "$RFOUT" '~ id          = "12345" -> "67890"'; check "comment anchor: a non-comment line naming the address opens no block (next id readable)" "$?"

# The show-shape start is anchored `:$`: a comment that merely has text after `addr:` is no show header (byte-identical).
NS="# random_id.k: this is prose, not a show header
resource \"hcloud_volume\" \"v\" {
    id          = \"12345\"
}"
[ "$(tf_redact_random_ids <<<"$NS")" = "$NS" ]; check "show start is anchored: '# addr: prose' opens no block (byte-identical)" "$?"

# Real replace shape: the new side is `(known after apply)`, unquoted.
KA="$(printf '  # random_id.k is tainted, so must be replaced\n-/+ resource "random_id" "k" {\n      ~ b64_std     = "%s" -> (known after apply)\n    }\n' "$K22" | tf_redact_random_ids)"
absent "$KA" "$K22" && contains "$KA" '"<redacted>" -> (known after apply)'; check "replace shape: old value redacted, '(known after apply)' kept" "$?"

# Two values on ONE line: every substitution is global.
TWO="random_id.a: replaced [id=$K22] by random_id.b [id=$K43]
random_id.a  id = \"$K22\" -> id = \"$N22\""
TWOOUT="$(tf_redact_random_ids <<<"$TWO")"
absent "$TWOOUT" "$K22" && absent "$TWOOUT" "$K43" && absent "$TWOOUT" "$N22"; check "two values on one line: both [id=] and both id = \"\" occurrences redacted" "$?"

# Fail-safe direction of an unterminated block (documented in the lib header): a LATER id attribute line is over-redacted.
UNTERM2="$UNTERM
  ~ resource \"hcloud_server\" \"web\" {
      ~ id          = \"12345\" -> \"67890\""
UT2OUT="$(tf_redact_random_ids <<<"$UNTERM2")"
contains "$UT2OUT" '~ id          = "<redacted>" -> "<redacted>"'; check "stuck-state unterminated block: a later id attribute line is over-redacted (fail-safe direction, documented)" "$?"

# --- the counted relay hello-signing key (#12289, A-0 of #12363): random_bytes.proxy_hello_hmac[0] -----------------
# random_bytes.hex is Sensitive, so the real plan prints `(sensitive value)`; the second block is the defence-in-depth
# case (a provider that printed the hex in clear), which must still be blanked at a COUNTED address. HEX64 is synthesized.
HEX64="${HEX32}${HEX32}"
HMAC_SENS='  # random_bytes.proxy_hello_hmac[0] will be created
  + resource "random_bytes" "proxy_hello_hmac" {
      + base64 = (sensitive value)
      + hex    = (sensitive value)
      + length = 32
    }'
HMAC_CLEAR="  # random_bytes.proxy_hello_hmac[0] will be created
  + resource \"random_bytes\" \"proxy_hello_hmac\" {
      + hex    = \"$HEX64\"
      + length = 32
    }"
HMAC_SENS_OUT="$(tf_redact_random_ids <<<"$HMAC_SENS")"
HMAC_CLEAR_OUT="$(tf_redact_random_ids <<<"$HMAC_CLEAR")"
[ "$(tf_redact_random_ids <<<"$HMAC_CLEAR")" != "$HMAC_CLEAR" ] && contains "$HMAC_CLEAR" "$HEX64"; check "positive control: the clear-hex counted block is changed by the filter and the raw block carries the 64-hex token" "$?"
absent "$HMAC_CLEAR_OUT" "$HEX64" && contains "$HMAC_CLEAR_OUT" 'hex    = "<redacted>"'; check "counted random_bytes[0] block: a clear 64-hex value is blanked and the attribute line keeps its shape" "$?"
[ "$HMAC_SENS_OUT" = "$HMAC_SENS" ]; check "counted random_bytes[0] block: the (sensitive value) form passes through byte-identical (nothing to lose, nothing over-redacted)" "$?"
[ "$(nlines "$HMAC_CLEAR_OUT")" = "$(nlines "$HMAC_CLEAR")" ] && contains "$HMAC_CLEAR_OUT" 'random_bytes.proxy_hello_hmac[0] will be created'; check "counted random_bytes[0] block: address and line count preserved" "$?"

printf '\n%s passed, %s failed\n' "$PASSES" "$FAILS"
# Gate. Conservation first, WITHOUT routing through pass()/fail() (neutering either must not disarm it): every check()
# lands in exactly one bucket. MIN_ASSERTIONS is a FLOOR (never -eq), raised deliberately with the suite.
MIN_ASSERTIONS=331
if [ "$((PASSES + FAILS))" -ne "$CHECKS" ]; then printf 'FATAL: assertion conservation broken: passes+fails=%s checks=%s\n' "$((PASSES + FAILS))" "$CHECKS" >&2; exit 1; fi
if [ "$CHECKS" -lt "$MIN_ASSERTIONS" ]; then printf 'FATAL: only %s assertions ran, floor is %s\n' "$CHECKS" "$MIN_ASSERTIONS" >&2; exit 1; fi
[ "$FAILS" -eq 0 ] || exit 1
