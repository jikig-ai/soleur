#!/usr/bin/env bash
#
# web-probes-token-rotation-verify.sh — read-only check that a Doppler service-token rotation
# actually happened (#8705). Lists the service tokens of one soleur config and prints ONE verdict
# line: the rotation is proven only by POSITIVE evidence (the retired token's slug is gone AND a
# replacement named with the expected prefix was created after the cut-off), never by an absence.
#
#   bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh \
#     [--config prd] [--retired-slug 01941a89] [--name-prefix web-probes-read-] \
#     [--not-before 2026-07-23T15:34:04Z]
#
# The defaults are the #8705 rotation: doppler_service_token.web_probes, whose retired token
# (slug 01941a89…) is held by retained web-1 snapshot image 411798619 (taken 2026-07-23T15:34:04Z).
# The next rotation of this token or a sibling passes new arguments; it does not need a new script.
# The slug is the identity check. A token's name is only a label: re-using a name mints a new key.
#
# Exit contract: 0 = rotated; 1 = the retired token is still listed, or no replacement exists;
# 2 = the listing could not be read or did not parse (inconclusive, never a verdict); 78 = refused
# to run under xtrace.
# Every verdict leaves through verdict() in the embedded Python below.
#
# Credential: the token-list endpoint needs a WORKPLACE token (a read service token gets HTTP 403
# there, measured 2026-09-24), so this reads DOPPLER_TOKEN_TF (dp.pt., Tier-B) from the
# environment, else soleur-infra-privileged/prd, else the pre-#8209-O10 fallback
# soleur/prd_terraform. The Authorization header travels to curl on a file descriptor (curl -K),
# never in argv, and the value is unset from this shell and its environment before any child that
# does not need it runs. Nothing here echoes a command line.
#
# Fixture seam (tests only): WEB_PROBES_TOKEN_LIST_JSON=<file> reads the listing from that file,
# fetches no credential, and appends " (fixture)" to the verdict line, so a stray variable is
# visible in a live run. Driven by apps/web-platform/infra/web-probes-token-rotation.test.sh.
#
# REMOVAL: this probe is meaningful only until image 411798619 is deleted (#8734). The plan's
# discoverability_test declaration that names it stays counted by the repo-wide probe ratchet.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

CONFIG="prd"
RETIRED_SLUG="01941a89"
NAME_PREFIX="web-probes-read-"
NOT_BEFORE="2026-07-23T15:34:04Z"

usage() {
  printf 'usage: %s [--config C] [--retired-slug S] [--name-prefix P] [--not-before YYYY-MM-DDTHH:MM:SSZ]\n' "${0##*/}" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) [[ $# -ge 2 ]] || usage; CONFIG="$2"; shift 2 ;;
    --retired-slug) [[ $# -ge 2 ]] || usage; RETIRED_SLUG="$2"; shift 2 ;;
    --name-prefix) [[ $# -ge 2 ]] || usage; NAME_PREFIX="$2"; shift 2 ;;
    --not-before) [[ $# -ge 2 ]] || usage; NOT_BEFORE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ "$CONFIG" =~ ^[a-z0-9_]+$ ]] || usage
[[ "$RETIRED_SLUG" =~ ^[A-Za-z0-9-]{4,}$ ]] || usage
[[ "$NAME_PREFIX" =~ ^[A-Za-z0-9._-]+$ ]] || usage
[[ "$NOT_BEFORE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]] || usage

BODY_FILE="$(mktemp -t wptr-verify.XXXXXXXX)" || { printf 'cannot create a scratch file\n' >&2; exit 2; }
trap 'rm -f "$BODY_FILE"' EXIT INT TERM HUP

MODE="live"
FETCH_RC=0
if [[ -n "${WEB_PROBES_TOKEN_LIST_JSON:-}" ]]; then
  MODE="fixture"
  cat -- "$WEB_PROBES_TOKEN_LIST_JSON" > "$BODY_FILE" 2>/dev/null || FETCH_RC=$?
else
  T="${DOPPLER_TOKEN_TF:-}"
  unset DOPPLER_TOKEN_TF
  if [[ -z "$T" ]]; then
    T="$(doppler secrets get DOPPLER_TOKEN_TF --project soleur-infra-privileged --config prd --plain --timeout 10s 2>/dev/null)" || T=""
  fi
  if [[ -z "$T" ]]; then
    T="$(doppler secrets get DOPPLER_TOKEN_TF --project soleur --config prd_terraform --plain --timeout 10s 2>/dev/null)" || T=""
  fi
  if [[ -z "$T" ]]; then
    FETCH_RC=90 # no credential resolved
  elif [[ ! "$T" =~ ^[A-Za-z0-9._-]+$ ]]; then
    FETCH_RC=91 # the value would not survive curl config quoting; refuse rather than inject
  else
    curl --disable --noproxy '*' -sS --fail --max-time 10 --proto '=https' \
      -K <(printf 'header = "Authorization: Bearer %s"\n' "$T") \
      -o "$BODY_FILE" \
      "https://api.doppler.com/v3/configs/config/tokens?project=soleur&config=${CONFIG}" 2>/dev/null || FETCH_RC=$?
  fi
  unset T
fi

python3 - "$BODY_FILE" "$FETCH_RC" "$MODE" "$RETIRED_SLUG" "$NAME_PREFIX" "$NOT_BEFORE" "$CONFIG" <<'PY'
import json
import re
import sys
from datetime import datetime

body_path, fetch_rc, mode, retired, prefix, not_before, config = sys.argv[1:8]
SAFE = re.compile(r"[^A-Za-z0-9._:+-]")
STAMP = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})")
VERDICTS = {
    "rotated": ("ROTATED", 0),
    "stale": ("STALE", 1),
    "missing": ("MISSING", 1),
    "unavailable": ("UNAVAILABLE", 2),
}


def clean(s):
    return SAFE.sub("?", str(s))[:80]


def stamp(s):
    """Parse an ISO-8601 instant; fractional seconds tolerated (any precision, truncated to µs)."""
    m = STAMP.fullmatch(s) if isinstance(s, str) else None
    if not m:
        raise ValueError(f"not an ISO-8601 instant: {clean(s)}")
    frac = (m.group(2) or "")[:7]
    zone = "+00:00" if m.group(3) == "Z" else m.group(3)
    return datetime.fromisoformat(m.group(1) + frac + zone)


def decide():
    if fetch_rc != "0":
        return "unavailable", f"could not read the token listing for soleur/{clean(config)} (fetch rc={clean(fetch_rc)}); inconclusive"
    try:
        with open(body_path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError):
        return "unavailable", "the token listing is empty or not JSON; inconclusive"
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
    listed = [t for t in tokens if t["slug"].startswith(retired)]
    if listed:
        return "stale", f"retired slug {clean(retired)} is still listed (name {clean(listed[0]['name'])}); the rotation has not happened"
    later = []
    for t in tokens:
        if t["name"].startswith(prefix):
            created = stamp(t["created_at"])
            if created > floor:
                later.append((created, t))
    if not later:
        return "missing", f"retired slug {clean(retired)} is gone but no {clean(prefix)}* token was created after {clean(not_before)}"
    _, newest = max(later, key=lambda pair: pair[0])
    return "rotated", f"retired slug {clean(retired)} absent; {clean(newest['name'])} created {clean(newest['created_at'])} > {clean(not_before)}"


def verdict(key, detail):
    """The single way out: print one line, then leave with the code the verdict maps to."""
    word, code = VERDICTS[key]
    print(f"{word}: {detail}{' (fixture)' if mode == 'fixture' else ''}")
    sys.exit(code)


try:
    key, detail = decide()
except Exception as e:  # noqa: BLE001 - any parse failure is inconclusive, never a verdict
    key, detail = "unavailable", f"verifier error ({type(e).__name__}: {clean(e)}); inconclusive"
verdict(key, detail)
PY
