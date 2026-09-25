#!/usr/bin/env bash
#
# web-probes-token-rotation-verify.sh — read-only check that a Doppler service-token rotation
# actually happened — the generic verifier for a Doppler service-token rotation, used by
# doppler_service_token.web_probes (#8705) and doppler_service_token.ghcr_minter (#8737). Lists the service tokens of one soleur config and prints ONE verdict
# line: the rotation is proven only by POSITIVE evidence (the retired token is gone AND a
# replacement named with the expected prefix was created after the cut-off), never by an absence.
#
#   bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh \
#     [--config prd] [--retired-slug 01941a89] [--retired-name web-probes-read] \
#     [--name-prefix web-probes-read-] [--not-before 2026-07-23T15:34:04Z]
#
# The defaults are the #8705 rotation: doppler_service_token.web_probes, whose retired token
# (slug 01941a89…, name web-probes-read) is very likely held by retained web-1 snapshot image
# 411798619 (taken 2026-07-23T15:34:04Z). The slug is the identity check; a token still carrying
# the retired NAME also counts as not rotated. The next rotation passes new arguments.
#
# SCOPE: the verdict is about DOPPLER only (the retired key can no longer read soleur/<config>).
# It says nothing about whether each host received the new key: pair it with a green post-bridge
# SSH stage in the merge's apply run and with the probe heartbeats.
#
# Exit contract: 0 = rotated; 1 = the retired token is still listed, or no replacement exists;
# 2 = the listing could not be read or did not parse (inconclusive, never a verdict);
# 64 = usage error; 78 = refused to run under xtrace.
# Every verdict leaves through verdict() in the embedded Python below.
#
# Credential: the token-list endpoint needs a WORKPLACE token (a read service token gets HTTP 403
# there, measured 2026-09-24), so this reads DOPPLER_TOKEN_TF (dp.pt., Tier-B) from the
# environment, else soleur-infra-privileged/prd, else the pre-#8209-O10 fallback
# soleur/prd_terraform; the verdict line names which source answered. RESIDUAL: until #8209 O11,
# soleur/prd_terraform is writable by DOPPLER_TOKEN_WRITE (ADR-241 D6), so a value planted there
# could point this read at another workplace's listing. A src=soleur/prd_terraform verdict is only
# as trustworthy as that config. The Authorization header
# travels to curl on a file descriptor (curl -K), never in argv, and the value never enters any
# child's environment. Nothing here echoes a command line.
#
# Tests drive this through a stubbed `curl` on PATH (web-probes-token-rotation.test.sh); there is
# deliberately no environment-selectable fixture seam.
#
# REMOVAL: retire when no `.tf` ROTATION note references it (grep `rotation-verify.sh` in *.tf).
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
# allexport would export T below into curl's environment; switch it off before any assignment.
set +a
export LC_ALL=C
# `--disable` closes ~/.curlrc and `--noproxy '*'` the proxy vars; neither touches the env that
# subverts TLS itself (SSLKEYLOGFILE, CA substitution) or name resolution. Same line as
# scripts/betterstack-query.sh (#7873).
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

CONFIG="prd"
RETIRED_SLUG="01941a89"
RETIRED_NAME="web-probes-read"
NAME_PREFIX="web-probes-read-"
NOT_BEFORE="2026-07-23T15:34:04Z"

usage() {
  printf 'usage: %s [--config C] [--retired-slug S] [--retired-name N] [--name-prefix P] [--not-before YYYY-MM-DDTHH:MM:SSZ]\n' "${0##*/}" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || usage; CONFIG="$2"; shift 2 ;;
    --retired-slug) [[ $# -ge 2 ]] || usage; RETIRED_SLUG="$2"; shift 2 ;;
    --retired-name) [[ $# -ge 2 ]] || usage; RETIRED_NAME="$2"; shift 2 ;;
    --name-prefix) [[ $# -ge 2 ]] || usage; NAME_PREFIX="$2"; shift 2 ;;
    --not-before) [[ $# -ge 2 ]] || usage; NOT_BEFORE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$CONFIG" =~ ^[a-z0-9_]+$ ]] || usage
[[ "$RETIRED_SLUG" =~ ^[A-Za-z0-9-]{4,}$ ]] || usage
[[ "$RETIRED_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || usage
[[ "$NAME_PREFIX" =~ ^[A-Za-z0-9._-]+$ ]] || usage
[[ "$NOT_BEFORE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]] || usage

BODY_FILE="$(mktemp -t wptr-verify.XXXXXXXX)" || { printf 'cannot create a scratch file\n' >&2; exit 2; }
trap 'rm -f "$BODY_FILE"' EXIT INT TERM HUP

FETCH_RC=0
HTTP="000"
SRC="none"
unset T
declare +x T
T="${DOPPLER_TOKEN_TF:-}"
unset DOPPLER_TOKEN_TF
[[ -n "$T" ]] && SRC="env"
if [[ -z "$T" ]]; then
  T="$(doppler secrets get DOPPLER_TOKEN_TF --project soleur-infra-privileged --config prd --plain --timeout 10s 2>/dev/null)" || T=""
  [[ -n "$T" ]] && SRC="soleur-infra-privileged/prd"
fi
if [[ -z "$T" ]]; then
  T="$(doppler secrets get DOPPLER_TOKEN_TF --project soleur --config prd_terraform --plain --timeout 10s 2>/dev/null)" || T=""
  [[ -n "$T" ]] && SRC="soleur/prd_terraform"
fi
if [[ -z "$T" ]]; then
  FETCH_RC=90 # no credential resolved
elif [[ ! "$T" =~ ^[A-Za-z0-9._-]+$ ]]; then
  FETCH_RC=91 # the value would not survive curl config quoting; refuse rather than inject
else
  HTTP="$(curl --disable --noproxy '*' -sS --fail --max-time 10 --proto '=https' \
    -K <(printf 'header = "Authorization: Bearer %s"\n' "$T") \
    -o "$BODY_FILE" -w '%{http_code}' \
    "https://api.doppler.com/v3/configs/config/tokens?project=soleur&config=${CONFIG}" 2>/dev/null)" || FETCH_RC=$?
fi
unset T

python3 - "$BODY_FILE" "$FETCH_RC" "$HTTP" "$SRC" "$RETIRED_SLUG" "$RETIRED_NAME" "$NAME_PREFIX" "$NOT_BEFORE" "$CONFIG" <<'PY'
import json
import re
import sys
from datetime import datetime

body_path, fetch_rc, http, src, retired, retired_name, prefix, not_before, config = sys.argv[1:10]
SAFE = re.compile(r"[^A-Za-z0-9._:+/-]")
STAMP = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})")
FETCH_REASONS = {"90": "no DOPPLER_TOKEN_TF resolved (env, soleur-infra-privileged/prd, soleur/prd_terraform)",
                 "91": "DOPPLER_TOKEN_TF has characters outside the service-token alphabet"}
VERDICTS = {
    "rotated": ("ROTATED", 0),
    "stale": ("STALE", 1),
    "missing": ("MISSING", 1),
    "unavailable": ("UNAVAILABLE", 2),
}


def clean(s):
    return SAFE.sub("?", str(s))[:80]


def stamp(s):
    """Parse an ISO-8601 instant; fractional seconds of any precision, normalised to 6 digits so
    datetime.fromisoformat accepts it on Python < 3.11 too."""
    m = STAMP.fullmatch(s) if isinstance(s, str) else None
    if not m:
        raise ValueError(f"not an ISO-8601 instant: {clean(s)}")
    frac = "." + (m.group(2) or ".")[1:7].ljust(6, "0")
    zone = "+00:00" if m.group(3) == "Z" else m.group(3)
    return datetime.fromisoformat(m.group(1) + frac + zone)


def unique_keys(pairs):
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate JSON key")
    return dict(pairs)


def decide():
    if fetch_rc != "0":
        why = FETCH_REASONS.get(fetch_rc, f"fetch rc={clean(fetch_rc)} http={clean(http)}")
        return "unavailable", f"could not read the token listing ({why}); inconclusive"
    try:
        with open(body_path, encoding="utf-8") as fh:
            doc = json.load(fh, object_pairs_hook=unique_keys)
    except (OSError, ValueError):
        return "unavailable", "the token listing is empty, not JSON, or has duplicate keys; inconclusive"
    if not isinstance(doc, dict):
        return "unavailable", "the token listing is not a JSON object; inconclusive"
    if "page" in doc:
        return "unavailable", "the token listing is paged and this probe reads one page; inconclusive"
    tokens = doc.get("tokens")
    if not isinstance(tokens, list) or not tokens:
        return "unavailable", "the token listing has no non-empty tokens array; inconclusive"
    for t in tokens:
        if not (isinstance(t, dict) and all(isinstance(t.get(k), str) and t.get(k) for k in ("slug", "name", "created_at"))):
            return "unavailable", "a listed token lacks slug, name or created_at (schema drift); inconclusive"
    floor = stamp(not_before)
    want = retired.strip().lower()
    listed = [t for t in tokens if t["slug"].strip().lower().startswith(want) or t["name"].strip() == retired_name]
    if listed:
        return "stale", f"retired token ({clean(retired)} / {clean(retired_name)}) is still listed as {clean(listed[0]['name'])}; the rotation has not happened"
    later = []
    for t in tokens:
        if t["name"].startswith(prefix):
            created = stamp(t["created_at"])
            if created > floor:
                later.append((created, t))
    if not later:
        return "missing", f"retired token is gone but no {clean(prefix)}* token was created after {clean(not_before)}"
    _, newest = max(later, key=lambda pair: pair[0])
    return "rotated", f"retired slug {clean(retired)} absent; {clean(newest['name'])} created {clean(newest['created_at'])} > {clean(not_before)}"


def verdict(key, detail):
    """The single way out: print one line, then leave with the code the verdict maps to."""
    word, code = VERDICTS[key]
    print(f"{word}: soleur/{clean(config)} (src={clean(src)}): {detail}")
    sys.exit(code)


try:
    key, detail = decide()
except Exception as e:  # noqa: BLE001 - any parse failure is inconclusive, never a verdict
    key, detail = "unavailable", f"verifier error ({type(e).__name__}: {clean(e)}); inconclusive"
verdict(key, detail)
PY
