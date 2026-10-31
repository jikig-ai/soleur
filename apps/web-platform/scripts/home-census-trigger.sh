#!/usr/bin/env bash
# home-census-trigger.sh — run the counts-only production-HOME census through its secret-gated route (no SSH).
#
# Authorization: operator comment 6546444433 on #10455 (read-only, counts only, metadata only). Building and
# merging the mechanism does NOT run it. A real run needs, in this order: the CLO's C8 DISCHARGED comment from a
# pinned author, a served build whose census paths equal the discharged commit, a mature container (C9), the
# two-run cap, and a write-ahead claim comment. See knowledge-base/engineering/operations/runbooks/home-census.md.
#
# Credential posture: INNGEST_MANUAL_TRIGGER_SECRET is read read-only from Doppler, passed to curl on its stdin
# config channel (never argv), never echoed, and the script refuses to run under shell tracing.
#
# STREAM CONTRACT: stdout is the data channel. A 2xx body is printed ONLY after it validates against the allowlist
# schema; any other body is never printed (a proxy 403 or 502 page carries a Ray ID and the caller's IP). Only the
# status class and the exit code are printed for those.
#
# Exit codes: 0 ok | 2 usage | 3 doppler/secret | 4 401/404 | 5 403 | 6 5xx | 7 timeout after scan (ambiguous: read
# Sentry and Better Stack first, never auto-retry) | 8 governance refusal | 9 build mismatch | 10 body failed the
# allowlist schema | 11 server refused (409/410/429/503) | 78 xtrace refusal.
#
# RETIREMENT: delete with the route (#11714).
set -euo pipefail

case "$-" in
  *x*)
    printf 'HOME_CENSUS_TRIGGER_HALT reason=xtrace-credential-bound\n'
    printf 'home-census-trigger: refusing to run under xtrace — this script handles a live credential. Nothing was read or sent.\n'
    exit 78
    ;;
esac

# --disable and --noproxy close ~/.curlrc and the proxy vars; these close the env that subverts TLS itself and the
# env that redirects gh or git to another host or repository.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS \
      GH_REPO GH_HOST GIT_DIR GIT_EXTERNAL_DIFF GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
      GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_SSH_COMMAND GIT_ASKPASS
for v in $(compgen -e | grep -E '^GIT_CONFIG_(KEY|VALUE)_[0-9]+$' || true); do unset "$v"; done

ROUTE_URL="https://app.soleur.ai/api/internal/home-census"
HEALTH_URL="https://app.soleur.ai/health"
REPO="jikig-ai/soleur"
ISSUE="10455"
SECRET_NAME="INNGEST_MANUAL_TRIGGER_SECRET"
# Comments are trusted only from this pinned allowlist (match on user id AND association): a public issue can be
# commented on by anyone, so an unfiltered count could be forged into a permanent refusal or a false discharge.
PINNED_AUTHOR_IDS="54279"
PINNED_ASSOCIATIONS="OWNER MEMBER"
# One constant of pathspecs: a new census file cannot slip past a fixed list.
CENSUS_PATHS=(':(glob)apps/web-platform/server/home-census*' 'apps/web-platform/app/api/internal/home-census')
CLO_RECORD="knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md"

MODE=""; RUN_ID=""; DISCHARGED=""; PR=""; SELF_CHECK=0; C9_FALLBACK=0

usage() {
  cat <<'EOF'
Usage:
  home-census-trigger.sh --mode dry_run --run-id <N>
  home-census-trigger.sh --mode real --run-id <N> --discharged-sha <40-hex> --pr <PR> [--c9-fallback]
  home-census-trigger.sh --self-check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --run-id) RUN_ID="${2:-}"; shift 2 ;;
    --discharged-sha) DISCHARGED="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --c9-fallback) C9_FALLBACK=1; shift ;;
    --self-check) SELF_CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "home-census-trigger: unknown argument" >&2; usage >&2; exit 2 ;;
  esac
done

_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }

# The exact request body. Built with jq --arg and converted, never by string interpolation.
build_body() { # mode run_id expect_sha accept_young
  local m="$1" r="$2" s="$3" a="$4"
  if [[ "$m" == "real" ]]; then
    jq -nc --arg m "$m" --arg r "$r" --arg s "$s" --arg a "$a" \
      '{run_id: ($r|tonumber), mode: $m, expect_build_sha: $s} + (if $a == "true" then {accept_young: true} else {} end)'
  else
    jq -nc --arg m "$m" --arg r "$r" --arg s "$s" '{run_id: ($r|tonumber), mode: $m} + (if $s != "" then {expect_build_sha: $s} else {} end)'
  fi
}

if [[ "$SELF_CHECK" -eq 1 ]]; then
  # Offline: no network, no secret, no HOME read. Verifies the trigger, not the signal.
  b="$(build_body real 7 "$(printf 'a%.0s' {1..40})" false)"
  [[ "$(jq -r '.mode' <<<"$b")" == "real" && "$(jq -r '.run_id|type' <<<"$b")" == "number" ]] || { echo "self-check: body shape" >&2; exit 1; }
  jq -e 'has("accept_young")|not' <<<"$b" >/dev/null || { echo "self-check: accept_young must be absent by default" >&2; exit 1; }
  if _bearer_ok 'bad"token'; then echo "self-check: token-shape guard accepts a quote" >&2; exit 1; fi
  if _bearer_ok ''; then echo "self-check: token-shape guard accepts empty" >&2; exit 1; fi
  case "$-" in *x*) echo "self-check: xtrace" >&2; exit 1 ;; esac
  [[ "$ROUTE_URL" == https://* ]] || { echo "self-check: route url" >&2; exit 1; }
  printf 'HOME_CENSUS_TRIGGER_SELF_CHECK_OK\n'
  exit 0
fi

# --- argument validation (nothing below runs on an invalid argument) ---
case "$MODE" in dry_run|real) ;; *) echo "home-census-trigger: --mode must be dry_run or real" >&2; exit 2 ;; esac
[[ "$RUN_ID" =~ ^[1-9][0-9]{0,8}$ ]] || { echo "home-census-trigger: --run-id must match ^[1-9][0-9]{0,8}\$" >&2; exit 2; }
if [[ "$MODE" == "real" ]]; then
  [[ "$PR" =~ ^[0-9]+$ ]] || { echo "home-census-trigger: --pr must be a number" >&2; exit 2; }
  [[ "$DISCHARGED" =~ ^[0-9a-f]{40}$ ]] || { echo "home-census-trigger: --discharged-sha must be 40 lowercase hex" >&2; exit 2; }
fi

die() { local code="$1"; shift; printf '%s\n' "$*"; exit "$code"; }

# --- served build (no credential) ---
served_sha() {
  local h
  h="$(curl --disable --noproxy '*' --proto '=https' --max-redirs 0 --max-time 20 -sS "$HEALTH_URL" 2>/dev/null)" || return 1
  jq -er '.build_sha | select(type == "string" and test("^[0-9a-f]{40}$"))' <<<"$h" 2>/dev/null
}

# --- governance reads (real only). Comments counted ONLY from the pinned author allowlist. ---
trusted_comments() { # prints one body per line, from pinned authors only
  local ids assoc
  ids="$(printf '%s\n' $PINNED_AUTHOR_IDS | jq -R . | jq -sc .)"
  assoc="$(printf '%s\n' $PINNED_ASSOCIATIONS | jq -R . | jq -sc .)"
  gh api "repos/${REPO}/issues/${ISSUE}/comments" --paginate 2>/dev/null \
    | jq -r --argjson ids "$ids" --argjson assoc "$assoc" \
        '.[] | select(((.user.id|tostring) as $i | ($ids | index($i)) != null) and (.author_association as $a | ($assoc | index($a)) != null)) | .body' \
    | tr -d '\r'
}

run_curl() { # body -> sets HTTP_CODE, RESP; token on stdin config only
  local body="$1" token="$2" rc=0
  RESP="$(mktemp -t home-census-resp.XXXXXXXX)"
  HTTP_CODE="$(curl --disable --noproxy '*' --proto '=https' --max-redirs 0 --max-time 60 -sS -o "$RESP" -w '%{http_code}' \
    -X POST "$ROUTE_URL" -H 'content-type: application/json' -d "$body" --config - \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$token") 2>/dev/null)" || rc=$?
  return "$rc"
}

# Allowlist schema for a 2xx body. Anything else is never printed.
body_valid() {
  jq -e '
    def bucket: . as $b | ["0","1-4","5-19","20-99","100-999","1000+"] | index($b) != null;
    .schema_version == 1 and .ok == true and (.classes|length) == 15
    and (keys - ["schema_version","ok","run_id","mode","data_source","build_sha","control","evidence","uptime_bucket","sunset_utc","truncated","truncation_reason","snapshot","mode_bits_semantics","interpretation","claude_config_dir_set","outer_wrap_cohorts","roots","roots_distinct","roots_note","activity_witness","trigger_class_nonzero","classes"]) == []
    and (.classes | all(.[]; (keys|sort) == ["absent","class","class_result","errors","n_entries","n_mode_bits_group_r","n_mode_bits_other_r","n_symlink"] and (.n_entries|bucket) and (.errors|bucket)))
    and (.uptime_bucket | IN("lt_1h","lt_24h","lt_7d","ge_7d")) and (.evidence | IN("young","mature"))
  ' "$1" >/dev/null 2>&1
}

TOKEN="$(doppler secrets get "$SECRET_NAME" -p soleur -c prd --plain 2>/dev/null)" || die 3 "home-census-trigger: could not read the secret from Doppler; nothing was sent"
_bearer_ok "$TOKEN" || die 3 "home-census-trigger: the secret is empty or has an unexpected shape; nothing was sent"

SERVED="$(served_sha)" || die 9 "home-census-trigger: /health did not report a 40-hex build_sha (a 'dev' build fails closed); nothing was sent"

if [[ "$MODE" == "dry_run" ]]; then
  BODY="$(build_body dry_run "$RUN_ID" "$SERVED" false)"
  rc=0; run_curl "$BODY" "$TOKEN" || rc=$?
  unset TOKEN
  [[ "$rc" -eq 0 ]] || die 7 "home-census-trigger: preflight request failed (curl exit $rc)"
  if [[ "$HTTP_CODE" == 2* ]] && body_valid "$RESP"; then cat "$RESP"; echo; rm -f "$RESP"; exit 0; fi
  rm -f "$RESP"
  die 10 "home-census-trigger: preflight status class ${HTTP_CODE:0:1}xx; the body is not printed"
fi

# ----------------------------- real -----------------------------
TRUSTED="$(trusted_comments)" || die 8 "home-census-trigger: could not read the tracker comments; nothing was sent"

# (1) C8: the DISCHARGED comment from a pinned author must name this sha and PR.
DIS_LINE="$(grep -E '^home-census C8 DISCHARGED sha=[0-9a-f]{40} pr=[0-9]+$' <<<"$TRUSTED" | tail -n 1 || true)"
[[ -n "$DIS_LINE" ]] || die 8 "home-census-trigger: no C8 DISCHARGED comment from a pinned author; nothing was sent"
[[ "$DIS_LINE" == "home-census C8 DISCHARGED sha=${DISCHARGED} pr=${PR}" ]] || die 8 "home-census-trigger: --discharged-sha/--pr do not match the C8 DISCHARGED comment; nothing was sent"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die 8 "home-census-trigger: not inside the repository"
grep -qF -- "DISCHARGED sha=${DISCHARGED}" "${ROOT}/${CLO_RECORD}" 2>/dev/null || die 8 "home-census-trigger: the committed CLO record does not carry this sha; nothing was sent"

# (2) The discharged sha is a commit of that PR: an ancestor of (or equal to) the PR head, fetched into FETCH_HEAD only (no
# destination refspec). Ancestry and not equality, because the committed CLO record that carries the sha is itself a commit
# on top of the reviewed one; the census-path comparison in (3) is what proves nothing in the census changed after it.
git fetch --no-tags origin "refs/pull/${PR}/head" >/dev/null 2>&1 || die 8 "home-census-trigger: could not fetch the PR head; nothing was sent"
git rev-parse FETCH_HEAD >/dev/null 2>&1 || die 8 "home-census-trigger: the PR head is not available; nothing was sent"
git merge-base --is-ancestor "$DISCHARGED" FETCH_HEAD || die 8 "home-census-trigger: the discharged sha is not a commit of the PR; nothing was sent"

# (3) The served build's census paths equal the discharged commit's.
if ! git cat-file -e "${SERVED}^{commit}" 2>/dev/null; then
  git fetch --no-tags origin main >/dev/null 2>&1 || true
fi
git cat-file -e "${SERVED}^{commit}" 2>/dev/null || die 9 "home-census-trigger: the served build is not available locally; nothing was sent"
git diff --quiet --no-ext-diff "$DISCHARGED" "$SERVED" -- "${CENSUS_PATHS[@]}" || die 9 "home-census-trigger: the census paths of the served build differ from the discharged commit; nothing was sent"

# (4) Preflight dry_run: mature container (C9) unless an explicit fallback.
PRE_BODY="$(build_body dry_run "$RUN_ID" "$SERVED" false)"
rc=0; run_curl "$PRE_BODY" "$TOKEN" || rc=$?
[[ "$rc" -eq 0 ]] && [[ "$HTTP_CODE" == 2* ]] && body_valid "$RESP" || { rm -f "${RESP:-}"; die 8 "home-census-trigger: the preflight dry_run failed; nothing was sent"; }
EVIDENCE="$(jq -r '.evidence' "$RESP")"; UPB="$(jq -r '.uptime_bucket' "$RESP")"; rm -f "$RESP"
if [[ "$C9_FALLBACK" -ne 1 ]]; then
  [[ "$EVIDENCE" == "mature" && ( "$UPB" == "lt_7d" || "$UPB" == "ge_7d" ) ]] || die 8 "home-census-trigger: the container is young; wait for 24 h of uptime and run the preflight again; nothing was sent"
fi

# (5) Two-run cap and monotonic run_id, from pinned-author claims only.
CLAIMS="$(grep -E '^home-census run_id=[0-9]+ claim$' <<<"$TRUSTED" || true)"
NCLAIMS=0; MAXID=0
if [[ -n "$CLAIMS" ]]; then
  NCLAIMS="$(wc -l <<<"$CLAIMS" | tr -d ' ')"
  MAXID="$(sed -E 's/^home-census run_id=([0-9]+) claim$/\1/' <<<"$CLAIMS" | sort -n | tail -n 1)"
fi
[[ "$NCLAIMS" -lt 2 ]] || die 8 "home-census-trigger: two claims already exist (the cap is two real runs); nothing was sent"
[[ "$RUN_ID" -gt "$MAXID" ]] || die 8 "home-census-trigger: --run-id must be above the last claim; nothing was sent"

# (6) Write-ahead claim BEFORE the request. A failed run still consumes its claim; gh failure fails closed.
gh issue comment "$ISSUE" -R "$REPO" --body "home-census run_id=${RUN_ID} claim" >/dev/null 2>&1 || die 8 "home-census-trigger: could not post the claim comment; nothing was sent"

# (7) The request. expect_build_sha comes from /health; the response build is re-compared after the call.
ACCEPT=false; [[ "$C9_FALLBACK" -eq 1 ]] && ACCEPT=true
BODY="$(build_body real "$RUN_ID" "$SERVED" "$ACCEPT")"
rc=0; run_curl "$BODY" "$TOKEN" || rc=$?
unset TOKEN
if [[ "$rc" -ne 0 ]]; then
  rm -f "${RESP:-}"
  die 7 "home-census-trigger: the request did not complete (curl exit $rc). The scan may have run. Read Sentry and Better Stack first; do not retry."
fi
mark_done() { gh issue comment "$ISSUE" -R "$REPO" --body "home-census run_id=${RUN_ID} done" >/dev/null 2>&1 || true; }
AFTER="$(served_sha || true)"
case "$HTTP_CODE" in
  2*)
    if body_valid "$RESP" && [[ "$AFTER" == "$SERVED" ]] && [[ "$(jq -r '.build_sha' "$RESP")" == "$SERVED" ]]; then
      mark_done; cat "$RESP"; echo; rm -f "$RESP"; exit 0
    fi
    rm -f "$RESP"; mark_done
    die 10 "home-census-trigger: the response failed the allowlist schema or the build changed during the call; the body is not printed" ;;
  401|404) rm -f "$RESP"; mark_done; die 4 "home-census-trigger: unauthorized or not found (status class 4xx)" ;;
  403) rm -f "$RESP"; mark_done; die 5 "home-census-trigger: forbidden (status class 4xx); the body is not printed" ;;
  409|410|429|503) rm -f "$RESP"; mark_done; die 11 "home-census-trigger: refused by the server (status $HTTP_CODE); run the preflight command to see why" ;;
  5*) rm -f "$RESP"; die 6 "home-census-trigger: server error (status class 5xx). The scan may have run. Read Sentry and Better Stack first; do not retry." ;;
  *) rm -f "$RESP"; mark_done; die 11 "home-census-trigger: unexpected status class ${HTTP_CODE:0:1}xx; the body is not printed" ;;
esac
