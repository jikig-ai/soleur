#!/usr/bin/env bash
# Birth-time recovery check for the single-use web-2 volume rebirth (#9372, ADR-263 addendum, step S12): after the
# reborn host booted, is the escrowed LUKS header a plausible, self-consistent recovery artifact, and does the
# passphrase the host formatted with open that header? Read-only: nothing is written to Doppler, R2, Terraform
# state or the host. No SSH.
#
# EACH CHECK FAILS THE RUN (exit 1, a named ::error::); an UNREADABLE input is exit 3, never a pass:
#   (a) the web-class bucket holds EXACTLY ONE object named workspaces-luks-header-<uuid>.img (S3 ListObjectsV2:
#       zero is "no escrowed header", more than one, a stray key under the prefix or a truncated listing is ambiguous);
#   (b) that object is non-empty and starts with the LUKS magic (4c554b53babe);
#   (c) `cryptsetup luksUUID` of the downloaded image equals the <uuid> in its object name;
#   (d) the Doppler copy of the passphrase (prd_workspaces_luks_web / WORKSPACES_LUKS_KEY) and the Terraform-state copy
#       (random_password.workspaces_luks_web.result) are equal, compared as sha256 inside this one process;
#   (e) `cryptsetup open --test-passphrase` accepts that passphrase against the downloaded header image.
#
# WHAT THIS DOES NOT PROVE (say it, never imply it):
#   - that the passphrase opens the LIVE volume, or that the backup is the header of the live volume: the live volume's
#     LUKS UUID is not observable without host access (no SSH), so (c) compares the image with its own object name only;
#   - that either passphrase copy, or the escrowed header, SURVIVES LOSS: Doppler and Terraform state are one blast
#     radius, and agreement of two copies at one moment is not durability;
#   - that the Terraform-state bucket is versioned or durable (that is #7992);
#   - that a re-escrow exists once the host holds data (an open #9372 acceptance item), or that a restore works: no
#     restore is exercised, and a documented procedure is not a restore drill.
# The success line therefore says "consistency check; restore NOT exercised".
#
# SECRET HANDLING. The Terraform state also holds other secrets, so `terraform state pull` is only ever piped straight
# into ONE field-selecting jq program emitting this one value: nothing from the state is printed, tee'd or written to a
# file. Both passphrase copies live only in shell variables; they reach `cryptsetup` on STDIN (printf, a builtin: never
# argv, never a file) and are compared as sha256 digests. The R2 pair reaches curl as a `user = "kid:secret"` config
# line on stdin (`--config -`), never argv. Every secret value is ::add-mask::ed before use. Doppler is read with the
# single-secret form (never `doppler run` or a download: CWE-522), with DOPPLER_CONFIG_DIR pointed at an empty private
# directory so a planted ~/.doppler cannot steer the call.
#
# Tools (doppler, terraform, curl, cryptsetup, jq) are resolved from PATH; there is no other seam.
# Env: DOPPLER_TOKEN — a provider token that can read prd_workspaces_luks_web (the workflow binds TF_VAR_doppler_token_tf).
# Exit: 0 PASS, 1 a check failed, 3 an input could not be read, 78 refused to run under xtrace.
set -euo pipefail
case "$-" in
  *x*) if [ -n "${DOPPLER_TOKEN:+x}" ]; then printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2; exit 78; fi ;;
esac

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${_dir}/../apps/web-platform/infra"
D_PROJECT="soleur"
D_CONFIG="prd_workspaces_luks_web"
KEY_PREFIX="workspaces-luks-header-"
LUKS_MAGIC_HEX="4c554b53babe"
UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

# fail/unreadable escape %, CR and LF so no value can split the annotation or smuggle a workflow command into it.
_esc() { local m="$*"; m="${m//%/%25}"; m="${m//$'\r'/%0D}"; m="${m//$'\n'/%0A}"; printf '%s' "$m"; }
fail() { echo "::error::web2-rebirth-recovery-check: $(_esc "$*")"; exit 1; }
unreadable() { echo "::error::web2-rebirth-recovery-check: $(_esc "$*") (an unreadable input is not a pass)"; exit 3; }

[[ -n "${DOPPLER_TOKEN:-}" ]] || unreadable "DOPPLER_TOKEN is not set; nothing was read"

umask 077
W="$(mktemp -d)" || unreadable "mktemp failed"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/dopplercfg"
export DOPPLER_CONFIG_DIR="$W/dopplercfg"
export DOPPLER_ENABLE_VERSION_CHECK=false

_dget() { # <NAME> -> the secret on stdout; a failed or empty read is "unreadable", never a pass
  local v
  v="$(doppler secrets get "$1" --plain -p "$D_PROJECT" -c "$D_CONFIG" 2>/dev/null)" || unreadable "could not read ${1} from ${D_PROJECT}/${D_CONFIG}" >&2
  [[ -n "$v" ]] || unreadable "${1} is empty in ${D_PROJECT}/${D_CONFIG}" >&2
  printf '%s' "$v"
}

bucket="$(_dget WORKSPACES_HEADER_BUCKET)"
endpoint="$(_dget WORKSPACES_HEADER_R2_ENDPOINT)"
kid="$(_dget WORKSPACES_HEADER_R2_ACCESS_KEY_ID)"
secret="$(_dget WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY)"
pass_d="$(_dget WORKSPACES_LUKS_KEY)"
# Mask before any further use (the directive is consumed by the runner, never shown).
printf '::add-mask::%s\n' "$kid" "$secret" "$pass_d"

_shapes_ok() { # LC_ALL=C: a locale can widen the bracket ranges to non-ASCII letters
  local LC_ALL=C
  [[ "$bucket" =~ ^[a-z0-9][a-z0-9.-]*$ ]] && [[ "$endpoint" =~ ^https://[0-9a-f]{32}\.r2\.cloudflarestorage\.com$ ]] \
    && [[ "$kid" =~ ^[A-Za-z0-9]{16,128}$ ]] && [[ "$secret" =~ ^[A-Za-z0-9/+=_-]{16,256}$ ]]
}
_shapes_ok || fail "an R2 value read from Doppler has an unexpected shape (bucket, endpoint, key id or secret); nothing was sent"   # RC:SHAPE

_s3() { # <outfile> <url> -> prints the HTTP status; the pair rides stdin, never argv
  local code rc=0
  code="$(printf 'user = "%s:%s"\n' "$kid" "$secret" \
    | curl --disable --noproxy '*' --config - --aws-sigv4 'aws:amz:auto:s3' -sS --max-time 60 -o "$1" -w '%{http_code}' "$2")" || rc=$?
  [[ "$rc" -eq 0 ]] || code="000"
  printf '%s' "$code"
}

# (a) exactly one escrowed header.
code="$(_s3 "$W/list.xml" "${endpoint}/${bucket}?list-type=2&prefix=${KEY_PREFIX}")"
[[ "$code" == 200 ]] || unreadable "the bucket listing answered ${code}, not 200"
keys="$(grep -oE '<Key>[^<]*</Key>' "$W/list.xml" | sed -E 's#^<Key>(.*)</Key>$#\1#' || true)"
n_keys=0; [[ -z "$keys" ]] || n_keys="$(printf '%s\n' "$keys" | wc -l | tr -d ' ')"
n_match=0; [[ -z "$keys" ]] || n_match="$(printf '%s\n' "$keys" | grep -cE "^${KEY_PREFIX}${UUID_RE}\.img\$" || true)"
[[ "$n_keys" -ne 0 ]] || fail "no escrowed header: the bucket holds no object under ${KEY_PREFIX}"   # RC:ZERO
[[ "$n_keys" -eq 1 && "$n_match" -eq 1 ]] || fail "ambiguous escrow: ${n_keys} object(s) under ${KEY_PREFIX}, ${n_match} of the exact header shape; expected exactly one"   # RC:AMBIG
! grep -q '<IsTruncated>true</IsTruncated>' "$W/list.xml" || fail "ambiguous escrow: the listing is truncated"   # RC:TRUNC
key="$keys"
key_uuid="${key#"$KEY_PREFIX"}"; key_uuid="${key_uuid%.img}"
# Facts about the object for the dispatch summary (names, sizes and ids only; ListObjectsV2 carries no version id, and the
# bucket has no versioning until #7992, so none is claimed).
obj_size="$(grep -oE '<Size>[0-9]+</Size>' "$W/list.xml" | head -1 | sed -E 's#</?Size>##g' || true)"
obj_etag="$(grep -oE '<ETag>[^<]*</ETag>' "$W/list.xml" | head -1 | sed -E 's#</?ETag>##g; s#&quot;##g; s#"##g' || true)"

# (b) the object is a LUKS header image.
code="$(_s3 "$W/hdr.img" "${endpoint}/${bucket}/${key}")"
[[ "$code" == 200 ]] || unreadable "the header object answered ${code}, not 200"
[[ -s "$W/hdr.img" ]] || fail "the escrowed header object is empty"   # RC:SIZE
magic="$(head -c 6 "$W/hdr.img" | od -An -tx1 | tr -d ' \n')"
[[ "$magic" == "$LUKS_MAGIC_HEX" ]] || fail "the escrowed object does not start with the LUKS magic"   # RC:MAGIC

# (c) the image's own UUID is the one in its object name (NOT a claim about the live volume).
img_uuid="$(cryptsetup luksUUID "$W/hdr.img" 2>/dev/null)" || unreadable "cryptsetup could not read a UUID from the downloaded header"
[[ "${img_uuid,,}" == "${key_uuid,,}" ]] || fail "the header's own UUID differs from its object name's UUID"   # RC:UUID

# (d) the two passphrase copies agree. The state is read ONCE, straight into one field-selecting jq program.
STATE_JQ='[.resources[] | select(.mode == "managed" and .type == "random_password" and .name == "workspaces_luks_web") | .instances[0].attributes.result][0] // empty'
pass_t="$(cd "$INFRA_DIR" && terraform state pull 2>/dev/null | jq -er "$STATE_JQ" 2>/dev/null)" || unreadable "could not read the web-class passphrase from the Terraform state"   # RC:STATE-FAIL
[[ -n "$pass_t" ]] || unreadable "the web-class passphrase is empty in the Terraform state"   # RC:STATE-EMPTY
printf '::add-mask::%s\n' "$pass_t"
sha_d="$(printf '%s' "$pass_d" | sha256sum | cut -d' ' -f1)"
sha_t="$(printf '%s' "$pass_t" | sha256sum | cut -d' ' -f1)"
if [[ "$sha_d" == "$sha_t" ]]; then echo "passphrase copies agree: yes"; else echo "passphrase copies agree: no"; fi
[[ "$sha_d" == "$sha_t" ]] || fail "the Doppler and Terraform-state passphrase copies differ"   # RC:AGREE

# (e) the passphrase opens the escrowed header. The header image file stands in for the device, so cryptsetup reads
# its header and keyslots and opens nothing; the passphrase arrives on stdin (printf is a builtin, so it is not argv).
printf '%s' "$pass_d" | cryptsetup open --test-passphrase --key-file=- "$W/hdr.img" >/dev/null 2>&1 || fail "cryptsetup --test-passphrase did not accept the passphrase against the escrowed header (a wrong passphrase, an unreadable header image, or a cryptsetup or environment fault: this check cannot tell which)"   # RC:TESTPASS

echo "escrow object: key=${key} size_bytes=${obj_size:-unknown} etag=${obj_etag:-unknown} version_id=not-exposed(no-bucket-versioning,#7992)"
echo "escrow checks: single_object=yes luks_magic=yes header_uuid_matches_object_name=yes passphrase_copies_agree=yes test_passphrase_accepted=yes"

echo "web2-rebirth-recovery-check: PASS birth-time consistency check; restore NOT exercised; open until #7992 and a restore drill"
