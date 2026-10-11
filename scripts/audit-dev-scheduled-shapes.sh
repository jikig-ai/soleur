#!/usr/bin/env bash
# audit-dev-scheduled-shapes.sh — one-time credential-shape audit of soleur/dev_scheduled.
#
# #9972 was the first dev-config credential-shape failure in a week (bump-cloud-init-pin's
# token-shape regex refused GitHub's new installation-token shape); #9995 was the second
# (a parseable-but-unregistered GITHUB_APP_PRIVATE_KEY). This audit walks the WHOLE
# dev_scheduled census (`doppler secrets --only-names`, never a value listing), fetches
# each value into a variable, and checks it against the shape class its name declares —
# printing one name->verdict line per entry and a summary. VALUES ARE NEVER PRINTED.
#
# Shape classes (first match wins; a name no class claims is UNCLASSIFIED — reported,
# never read as ok):
#   *PRIVATE_KEY* / *PEM*      pem     — openssl pkey -check parses (literal `\n`
#                                       escapes expanded first, as getPrivateKey does)
#                                       OR the value is a bare key blob in the token
#                                       alphabet (VAPID-style base64url EC keys are
#                                       stored un-PEM'd — a *PRIVATE_KEY name does not
#                                       promise PEM wrapping)
#   *_URL                      url     — ^<scheme>:// (any scheme, not only https)
#   *_INSTALLATION_ID          numeric — ^[0-9]+$ ; GITHUB_APP_ID likewise
#   *_B64                      b64     — ^[A-Za-z0-9+/=]+$
#   *TOKEN* *SECRET* *_PAT     token   — RFC 6750 b64token alphabet [A-Za-z0-9._~+/=-]
#    *PASSWORD* *_KEY                  — a PROPERTY guard, NOT a vendor-format prefix
#                                       (the #9972 lesson: guarding `ghp_`-shape is what
#                                       refused GitHub's next shape)
#   every name                 floor   — non-empty and no byte outside [\n\x20-\x7E]
#                                       (a CR or control byte in a stored secret is a
#                                       transport defect whatever its class)
#
# Exit 0 = every checked name conforms; 1 = at least one FAIL; 3 = the census itself
# could not be read or was empty/unrecognised — "0 checked" never exits 0.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${DOPPLER_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

umask 077
PROJ=soleur; CFG=dev_scheduled

die() { printf 'audit-dev-scheduled-shapes: %s\n' "$1" >&2; exit "${2:-1}"; }

[[ -n "${DOPPLER_TOKEN:-}" ]] \
  || die "DOPPLER_TOKEN is not set; run with a dev-scoped token (never falls back to an ambient login)" 3
command -v doppler >/dev/null 2>&1 || die "doppler CLI not on PATH" 3
command -v jq >/dev/null 2>&1 || die "jq not on PATH" 3
command -v openssl >/dev/null 2>&1 || die "openssl not on PATH (pem class)" 3

names_json="$(doppler secrets --only-names --json -p "$PROJ" -c "$CFG" 2>/dev/null)" \
  || die "doppler secrets --only-names -p $PROJ -c $CFG failed (rc=$?) — census unreadable" 3

# A JSON object whose keys are all-uppercase secret names is the census; anything else
# (envelope {"names": [...]}, an error string, empty object) fails closed — the same
# all-uppercase-key proof assert-dev-doppler-scope.sh uses for its absence check.
jq -e 'type == "object" and (keys | all(test("^[A-Z0-9_]+$")))' >/dev/null 2>&1 <<<"$names_json" \
  || die "census did not return a JSON object of UPPERCASE names — refusing to read it as a listing" 3
n_names="$(jq -r 'keys | length' <<<"$names_json")"
[[ "$n_names" -gt 0 ]] || die "census returned zero names — '0 checked' is never a pass" 3

class_of() {
  case "$1" in
    *PRIVATE_KEY*|*PEM*) echo pem ;;
    *_URL) echo url ;;
    *_INSTALLATION_ID|GITHUB_APP_ID) echo numeric ;;
    *_B64) echo b64 ;;
    *TOKEN*|*SECRET*|*_PAT|*PASSWORD*|*_KEY) echo token ;;
    *) echo unclassified ;;
  esac
}

# tmpfs first (XDG_RUNTIME_DIR) — a killed audit must not leave a PEM on disk.
PEMD="$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/var/tmp}}/audit-pem.XXXXXXXX")" || die "mktemp failed" 3
trap 'rm -rf "${PEMD:-}"' EXIT

pem_ok() {  # value on stdin; expands literal \n then openssl -check. No output.
  local f="$PEMD/v.pem"
  awk '{gsub(/\\n/, "\n"); printf "%s\n", $0}' > "$f"
  openssl pkey -check -in "$f" -noout >/dev/null 2>&1 \
    || openssl rsa -check -in "$f" -noout >/dev/null 2>&1
}

checked=0 ok=0 failed=0 unclassified=0
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  checked=$((checked + 1))
  cls="$(class_of "$name")"
  # $() strips trailing newlines from the value — acceptable normalization: the
  # floor's job is catching transport corruption (CR/control bytes), and a stored
  # trailing newline is the commonest harmless storage accident bc_ok trims anyway.
  val="$(doppler secrets get "$name" --plain -p "$PROJ" -c "$CFG" 2>/dev/null)"
  grc=$?
  verdict=""
  if [[ "$grc" -ne 0 ]]; then
    verdict="FAIL-fetch"
  elif [[ -z "$val" ]]; then
    verdict="FAIL-floor-empty"
  elif [[ "$(printf '%s' "$val" | LC_ALL=C tr -d '\012\040-\176' | wc -c)" -gt 0 ]]; then
    verdict="FAIL-floor-control"
  else
    case "$cls" in
      pem)      printf '%s' "$val" | pem_ok && verdict=ok || { [[ "$val" =~ ^[A-Za-z0-9._~+/=-]+$ ]] && verdict=ok || verdict="FAIL-pem"; } ;;
      url)      [[ "$val" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]] && verdict=ok || verdict="FAIL-url" ;;
      numeric)  [[ "$val" =~ ^[0-9]+$ ]] && verdict=ok || verdict="FAIL-numeric" ;;
      b64)      [[ "$val" =~ ^[A-Za-z0-9+/=]+$ ]] && verdict=ok || verdict="FAIL-b64" ;;
      token)    [[ "$val" =~ ^[A-Za-z0-9._~+/=-]+$ ]] && verdict=ok || verdict="FAIL-token" ;;
      *)        verdict="UNCLASSIFIED" ;;
    esac
  fi
  case "$verdict" in
    ok) ok=$((ok + 1)) ;;
    UNCLASSIFIED) unclassified=$((unclassified + 1)) ;;
    *) failed=$((failed + 1)) ;;
  esac
  printf 'name=%s class=%s verdict=%s\n' "$name" "$cls" "$verdict"
done < <(jq -r 'keys[]' <<<"$names_json")

printf 'AUDIT_SUMMARY checked=%d ok=%d fail=%d unclassified=%d\n' "$checked" "$ok" "$failed" "$unclassified"
[[ "$failed" -eq 0 ]]
