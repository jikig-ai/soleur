#!/usr/bin/env bash
# check-deploy-script-parity.sh — is every web host running the repo's ci-deploy.sh? (#9151)
#
# The no-SSH parity read. Three arms, each independently strict:
#
#   (a) REPO   — sha256 of apps/web-platform/infra/ci-deploy.sh in this checkout.
#   (b) STATUS — web-1's live /hooks/deploy-status `.ci_deploy_sha256` field
#                (cat-deploy-state.sh computes it per request; the ONLY live
#                read available without SSH, since deploy.<base> is web-1-pinned).
#   (c) BS     — the NEWEST `DEPLOY_SCRIPT_SHA sha256=<hex>` Better Stack row per
#                expected host_name within --since. ci-deploy.sh emits the marker
#                once per invocation (journald → Vector Source 4 → Better Stack).
#                A stale newest row is DRIFT: the last deploy on that host ran
#                bytes that are not the repo's. A missing row proves nothing
#                either way — fail unless --allow-missing-bs.
#
# The expected host set is DERIVED from var.web_hosts in variables.tf and the
# host_name mapping in server.tf (`web-1` → `soleur-web-platform`, else
# `soleur-<key>`), so adding a web host widens the check automatically.
#
# Usage:
#   check-deploy-script-parity.sh [--self-test]
#       [--status-only | --bs-only]
#       [--since <dur for betterstack-query.sh, default 7d>]
#       [--limit <N, default 500>]
#       [--allow-missing-bs]
#       [--status-json-file <file> — read a captured /hooks/deploy-status body
#        instead of curling (test harness + offline forensics)]
#       [--bs-rows-file <file> — read JSONEachRow lines instead of querying
#        Better Stack (test harness)]
#
# Live arms need (web-1 status): WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID +
# CF_ACCESS_CLIENT_SECRET (or CI_SSH_ACCESS_TOKEN_ID/SECRET fallback),
# APP_DOMAIN_BASE (default soleur.ai); (BS): doppler CLI + prd_terraform creds.
#
# Exit: 0 parity; 1 drift/missing/transport failure (each named); 2 usage;
# 78 trace refusal with a live credential set (#7797).
set -uo pipefail

# (#7797) Refuse to run under shell tracing while a live credential is set: `set -x`
# would trace the token into whatever collects this script's output.
case "$-" in
  *x*)
    if [ -n "${CF_ACCESS_CLIENT_SECRET:+x}${CI_SSH_ACCESS_TOKEN_SECRET:+x}${HMAC_KEY:+x}${WEBHOOK_DEPLOY_SECRET:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELFTEST=0; STATUS_ARM=1; BS_ARM=1; SINCE="7d"; LIMIT=500; ALLOW_MISSING_BS=0
STATUS_JSON_FILE=""; BS_ROWS_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test) SELFTEST=1; shift ;;
    --status-only) BS_ARM=0; shift ;;
    --bs-only) STATUS_ARM=0; shift ;;
    --since) [[ $# -ge 2 ]] || { echo "--since needs a value" >&2; exit 2; }; SINCE="$2"; shift 2 ;;
    --limit) [[ $# -ge 2 ]] || { echo "--limit needs a value" >&2; exit 2; }; LIMIT="$2"; shift 2 ;;
    --allow-missing-bs) ALLOW_MISSING_BS=1; shift ;;
    --status-json-file) [[ $# -ge 2 ]] || { echo "--status-json-file needs a value" >&2; exit 2; }; STATUS_JSON_FILE="$2"; shift 2 ;;
    --bs-rows-file) [[ $# -ge 2 ]] || { echo "--bs-rows-file needs a value" >&2; exit 2; }; BS_ROWS_FILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,37p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Fail-closed arg validation: both-arm-off would print PARITY having verified
# nothing; a fixture path that cannot be read must FATAL, not skip its arm.
if [[ "$STATUS_ARM" -eq 0 && "$BS_ARM" -eq 0 ]]; then
  echo "FATAL: no arms enabled (--status-only and --bs-only are alternatives, not additions)" >&2; exit 2
fi
for f in "$STATUS_JSON_FILE" "$BS_ROWS_FILE"; do
  [[ -z "$f" || ( -r "$f" && -s "$f" ) ]] \
    || { echo "FATAL: fixture file missing or empty: $f" >&2; exit 2; }
done

# ── DERIVATIONS (shared by self-test and live) ───────────────────────────────────
# web_hosts keys from the var.web_hosts `default = { … }` block. Anchored on the
# per-host shape `"<key>" = {` inside the variable block, not a repo-wide pattern.
parse_host_keys() { # <variables.tf path> -> one key per line
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'variable "web_hosts" \{(.*?)\n\}', src, re.S)
assert m, "variable \"web_hosts\" block not found"
keys = re.findall(r'^\s*"([^"]+)"\s*=\s*\{', m.group(1), re.M)
assert keys, "no host keys parsed from var.web_hosts"
for k in keys: print(k)
PY
}

# server.tf's mapping: `each.key == "web-1" ? "soleur-web-platform" : "soleur-${each.key}"`.
# Assert the expression still has that exact shape before applying it — a changed
# mapping silently renames every host's telemetry, which this check cannot see.
assert_host_name_mapping_stable() { # <server.tf path>
  grep -qF 'each.key == "web-1" ? "soleur-web-platform" : "soleur-${each.key}"' "$1" \
    || { echo "DRIFT: server.tf's host_name ternary changed shape — re-derive the mapping here" >&2; return 1; }
}
host_name_for() { # <key>
  [[ "$1" == "web-1" ]] && printf 'soleur-web-platform\n' || printf 'soleur-%s\n' "$1"
}

sha_marker_of() { # stdin -> first sha256=<64hex> in a DEPLOY_SCRIPT_SHA message, or empty
  grep -oE 'DEPLOY_SCRIPT_SHA sha256=[0-9a-f]{64}' | head -1 | sed 's/.*sha256=//'
}

if [[ "$SELFTEST" -eq 1 ]]; then
  nfail=0
  keys="$(parse_host_keys "$ROOT/apps/web-platform/infra/variables.tf")" || nfail=1
  assert_host_name_mapping_stable "$ROOT/apps/web-platform/infra/server.tf" || nfail=1
  [[ "$(grep -c . <<<"$keys")" -ge 2 ]] || { echo "self-test: expected >= 2 web hosts, got: $keys" >&2; nfail=1; }
  map="$(while read -r k; do host_name_for "$k"; done <<<"$keys")"
  grep -qx 'soleur-web-platform' <<<"$map" && grep -qx 'soleur-web-2' <<<"$map" \
    || { echo "self-test: host_name mapping produced unexpected set: $map" >&2; nfail=1; }
  fixture_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  row="{\"dt\":\"2026-09-30 00:00:00.000\",\"raw\":\"{\\\"message\\\":\\\"DEPLOY_SCRIPT_SHA sha256=${fixture_sha}\\\",\\\"host_name\\\":\\\"soleur-web-2\\\"}\"}"
  [[ "$(printf '%s' "$row" | sha_marker_of)" == "$fixture_sha" ]] || { echo "self-test: marker extraction broke" >&2; nfail=1; }
  [[ $nfail -eq 0 ]] && echo "check-deploy-script-parity self-test: ok"
  exit $((nfail > 0))
fi

REPO_SHA="$(sha256sum "$ROOT/apps/web-platform/infra/ci-deploy.sh" | cut -d' ' -f1)"
echo "repo ci-deploy.sh sha256=$REPO_SHA"

# Capture THEN mapfile: a process-substitution producer's rc never reaches
# mapfile, so `mapfile … < <(failing) || …` is a dead guard and an empty array
# would silently sweep zero hosts behind a green PARITY.
host_keys_out="$(parse_host_keys "$ROOT/apps/web-platform/infra/variables.tf")" \
  || { echo "FATAL: could not derive the web host set from var.web_hosts" >&2; exit 1; }
mapfile -t HOST_KEYS <<<"$host_keys_out"
[[ ${#HOST_KEYS[@]} -ge 2 ]] \
  || { echo "FATAL: derived host set has ${#HOST_KEYS[@]} member(s), expected >= 2: $host_keys_out" >&2; exit 1; }
assert_host_name_mapping_stable "$ROOT/apps/web-platform/infra/server.tf" || exit 1

fail=0

# ── (b) web-1 deploy-status arm ─────────────────────────────────────────────────
if [[ "$STATUS_ARM" -eq 1 ]]; then
  if [[ -n "$STATUS_JSON_FILE" ]]; then
    body="$(<"$STATUS_JSON_FILE")"
  else
    BASE="${APP_DOMAIN_BASE:-soleur.ai}"
    # The request carries bearer credentials — pin the authority and close the
    # env channels that subvert egress/TLS (#7873/#7898 shape).
    [[ "$BASE" =~ ^[a-z0-9.-]+$ ]] \
      || { echo "FATAL: APP_DOMAIN_BASE is not a plain hostname ($BASE)" >&2; exit 2; }
    unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
    : "${WEBHOOK_DEPLOY_SECRET:?required for the web-1 status arm}"
    CF_ID="${CF_ACCESS_CLIENT_ID:-${CI_SSH_ACCESS_TOKEN_ID:-}}"
    CF_SEC="${CF_ACCESS_CLIENT_SECRET:-${CI_SSH_ACCESS_TOKEN_SECRET:-}}"
    : "${CF_ID:?CF Access client id required}" "${CF_SEC:?CF Access secret required}"
    # (#9597, S2) The three credentials ride curl's STDIN as `header = "..."` config lines (a process substitution,
    # never a pipe: `printf | curl --config -` dies with 141 under pipefail when curl does not read stdin), not its
    # argument list, which every local user reads from /proc/<pid>/cmdline. A config line is a quoted string, so each
    # VALUE is checked first: the Cloudflare Access pair against the cutover's `_bearer_ok` class, and the signature
    # must be exactly 64 lowercase hex (python3 missing or an empty key leaves HMAC empty, and an unsigned request
    # must never be sent). Every refusal is exit 2 (this script's usage-class refusal; exit 1 is DRIFT), sends no
    # request, and prints one value-free marker.
    _bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
    _refuse() { echo "check-deploy-script-parity: refusing to send credentials: $1 is unusable" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=check-deploy-script-parity reason=token_shape" >&2; exit 2; }
    _bearer_ok "$CF_ID" || _refuse "the Cloudflare Access client id"
    _bearer_ok "$CF_SEC" || _refuse "the Cloudflare Access client secret"
    HMAC="$(printf '' | HMAC_KEY="$WEBHOOK_DEPLOY_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())' 2>/dev/null)" || HMAC=""
    [[ "$HMAC" =~ ^[0-9a-f]{64}$ ]] || _refuse "the request signature (python3 missing or the webhook key empty)"
    STATUS_TMP="$(mktemp)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
    trap 'rm -f "$STATUS_TMP"' EXIT
    code="$(curl --disable --noproxy '*' --proto '=https' -s -o "$STATUS_TMP" -w '%{http_code}' --max-time 20 \
      "https://deploy.${BASE}/hooks/deploy-status" \
      --config - < <(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' "$HMAC" "$CF_ID" "$CF_SEC") 2>/dev/null || echo 000)"
    if [[ "$code" != "200" ]]; then
      echo "DRIFT(status): /hooks/deploy-status returned HTTP $code — web-1 parity cannot be read" >&2; fail=1
      body=""
    else
      body="$(<"$STATUS_TMP")"
    fi
    rm -f "$STATUS_TMP"
  fi
  if [[ -z "${body:-}" ]]; then
    # A 200 with an empty body is a transport anomaly, not parity — fail closed
    # rather than skip the arm.
    echo "DRIFT(status): /hooks/deploy-status returned an empty body — web-1 parity cannot be read" >&2; fail=1
  else
    live="$(printf '%s' "$body" | jq -r '.ci_deploy_sha256 // "ABSENT"')"
    hid="$(printf '%s' "$body" | jq -r '.host_id // "?"')"
    if [[ "$live" == "$REPO_SHA" ]]; then
      echo "PARITY(status): web-1 ($hid) serves ci-deploy.sh == repo ($REPO_SHA)"
    elif [[ "$live" == "ABSENT" ]]; then
      echo "DRIFT(status): web-1 ($hid) body lacks ci_deploy_sha256 — an old cat-deploy-state.sh is serving" >&2; fail=1
    else
      echo "DRIFT(status): web-1 ($hid) ci_deploy_sha256=$live != repo $REPO_SHA" >&2; fail=1
    fi
  fi
fi

# ── (c) Better Stack DEPLOY_SCRIPT_SHA arm ──────────────────────────────────────
if [[ "$BS_ARM" -eq 1 ]]; then
  if [[ -n "$BS_ROWS_FILE" ]]; then
    rows="$(<"$BS_ROWS_FILE")"
  else
    command -v doppler >/dev/null || { echo "FATAL: BS arm needs doppler (or --bs-rows-file)" >&2; exit 1; }
    rows="$(doppler run --preserve-env -p soleur -c prd_terraform -- bash "$ROOT/scripts/betterstack-query.sh" \
      --since "$SINCE" --grep DEPLOY_SCRIPT_SHA --limit "$LIMIT" 2>/dev/null)" \
      || { echo "FATAL: betterstack-query.sh failed under doppler" >&2; exit 1; }
  fi
  # Newest sha per host_name: decode .raw (double-JSON), sort by dt desc, first per host.
  newest="$(printf '%s\n' "$rows" | jq -Rr '
    fromjson? // empty
    | {dt: (.dt // ""), raw: (try (.raw | fromjson?) catch {})}
    | select(.raw | type == "object")
    | {dt: .dt, ident: (.raw.SYSLOG_IDENTIFIER // ""), host: (.raw.host_name // ""), sha: (try ((.raw.message // "") | capture("DEPLOY_SCRIPT_SHA sha256=(?<s>[0-9a-f]{64})") | .s) catch "")}
    # Field-isolate on the emitter, never the message alone (#6475): a CI job that
    # merely PRINTED "DEPLOY_SCRIPT_SHA" would otherwise count as a deploy row.
    | select(.ident == "ci-deploy" and .host != "" and .sha != "")
    | [.dt, .host, .sha] | @tsv' 2>/dev/null | sort -r | awk -F '\t' '!seen[$2]++ {print $2 "\t" $3}')"
  for key in "${HOST_KEYS[@]}"; do
    hname="$(host_name_for "$key")"
    sha="$(awk -F '\t' -v h="$hname" '$1 == h {print $2; exit}' <<<"$newest")"
    if [[ -z "$sha" ]]; then
      if [[ "$ALLOW_MISSING_BS" -eq 1 ]]; then
        echo "WARN(bs): no DEPLOY_SCRIPT_SHA row for $hname in --since $SINCE (cannot prove; allowed)"
      else
        echo "DRIFT(bs): no DEPLOY_SCRIPT_SHA row for $hname in --since $SINCE — its last deploy predates the marker or the window" >&2; fail=1
      fi
    elif [[ "$sha" == "$REPO_SHA" ]]; then
      echo "PARITY(bs): $hname last deployed ci-deploy.sh == repo"
    else
      echo "DRIFT(bs): $hname last deployed sha=$sha != repo $REPO_SHA" >&2; fail=1
    fi
  done
fi

if [[ "$fail" -eq 0 ]]; then echo "check-deploy-script-parity: PARITY"; else echo "check-deploy-script-parity: DRIFT" >&2; fi
exit $fail
