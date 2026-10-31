#!/usr/bin/env bash
# home-census-trigger.sh — run the counts-only production-HOME census through its secret-gated route (no SSH).
#
# Authorization: operator comment 6546444433 on #10455 (read-only, counts only, metadata only). Building and
# merging the mechanism does NOT run it. A real run needs, in this order: the CLO's C8 DISCHARGED comment from a
# pinned author (whose sha is also in the CLO record of the served build), a served build whose census paths equal
# the discharged commit, the reviewed trigger script, a mature container (C9), the two-run cap, and a write-ahead claim. See knowledge-base/engineering/operations/runbooks/home-census.md.
#
# Credential posture: INNGEST_MANUAL_TRIGGER_SECRET is read read-only from Doppler, passed to curl on its stdin
# config channel (never argv), never echoed, and the script refuses to run under shell tracing.
#
# STREAM CONTRACT: stdout is the data channel; every refusal and status message goes to stderr. A 2xx body is printed ONLY after it validates against the allowlist
# schema; any other body is never printed (a proxy 403 or 502 page carries a Ray ID and the caller's IP). Only the
# status class and the exit code are printed for those.
#
# Exit codes: 0 ok | 2 usage | 3 doppler/secret | 4 401/404 | 5 403 | 6 5xx | 7 timeout after scan (ambiguous: read
# Sentry and Better Stack first, never auto-retry) | 8 governance refusal | 9 build mismatch | 10 body failed the
# allowlist schema | 11 server refused (409/410/429/503; the closed error_class is printed when the body is the exact failure
# shape) | 12 preflight request did not complete (no scan runs in dry_run: safe to retry) | 78 xtrace refusal.
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
      GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_SSH_COMMAND GIT_ASKPASS BASH_ENV ENV
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
# One constant of pathspecs: a new census file cannot slip past a fixed list. The sink and gate files are bound too (CLO D7);
# infra/vector.toml and lib/routes.ts are not (neither can add a field to the object) and their diff is printed for the CLO.
SCRIPT_REL="apps/web-platform/scripts/home-census-trigger.sh"
CENSUS_PATHS=(':(glob)apps/web-platform/server/home-census*' 'apps/web-platform/app/api/internal/home-census' 'apps/web-platform/lib/internal-auth.ts' 'apps/web-platform/server/sentry-scrub.ts' 'apps/web-platform/sentry.server.config.ts' "$SCRIPT_REL")
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

die() { local code="$1"; shift; printf '%s\n' "$*" >&2; exit "$code"; }

# --- served build (no credential) ---
served_sha() {
  local h
  h="$(curl --disable --noproxy '*' --proto '=https' --max-redirs 0 --max-time 20 -sS "$HEALTH_URL" 2>/dev/null)" || return 1
  jq -er '.build_sha | select(type == "string" and test("^[0-9a-f]{40}$"))' <<<"$h" 2>/dev/null
}

# --- governance reads (real only). Comments counted ONLY from the pinned author allowlist, and only when the WHOLE body is
# exactly one governance line: a quote or a multi-line note that contains such a line is not a discharge or a claim. ---
trusted_comments() { # prints one body per line, from pinned authors only
  local ids assoc
  ids="$(printf '%s\n' $PINNED_AUTHOR_IDS | jq -R . | jq -sc .)"
  assoc="$(printf '%s\n' $PINNED_ASSOCIATIONS | jq -R . | jq -sc .)"
  gh api "repos/${REPO}/issues/${ISSUE}/comments" --paginate 2>/dev/null \
    | jq -r --argjson ids "$ids" --argjson assoc "$assoc" \
        '.[] | select(((.user.id|tostring) as $i | ($ids | index($i)) != null) and (.author_association as $a | ($assoc | index($a)) != null)) | .body
        | gsub("\r"; "") | select(test("^(home-census C8 DISCHARGED sha=[0-9a-f]{40} pr=[0-9]+|home-census run_id=[0-9]+ (claim|done))$"))'
}

RESP=""
trap 'rm -f "${RESP:-}"' EXIT

run_curl() { # body -> sets HTTP_CODE, RESP; token on stdin config only
  local body="$1" token="$2" rc=0
  [[ -z "$RESP" ]] || rm -f "$RESP"
  RESP="$(mktemp -t home-census-resp.XXXXXXXX)"
  HTTP_CODE="$(curl --disable --noproxy '*' --proto '=https' --max-redirs 0 --max-time 60 -sS -o "$RESP" -w '%{http_code}' \
    -X POST "$ROUTE_URL" -H 'content-type: application/json' -d "$body" --config - \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$token") 2>/dev/null)" || rc=$?
  return "$rc"
}

# The constant the server emits as `interpretation` (kept in step with INTERPRETATION in server/home-census.ts by the vitest parity test).
INTERPRETATION="counted in this container's writable layer at the run; not a statement about earlier containers, other hosts, or any time before or after the run"

# Allowlist schema for a 2xx body: exact key set, every value from its closed set, classes in the module's order.
# Anything that does not validate is never printed.
body_valid() {
  jq -e --arg interp "$INTERPRETATION" '
    def bucket: IN("0","1-4","5-19","20-99","100-999","1000+");
    def order: ["history_jsonl","debug","todos","tasks","history_dir","projects","sessions_json","sessions_key","shell_snapshots","account_state","backups","last_cleanup","statsig","file_history","other_under_claude"];
    ((keys | sort) == (["schema_version","ok","run_id","mode","data_source","build_sha","control","evidence","uptime_bucket","sunset_utc","truncated","truncation_reason","snapshot","mode_bits_semantics","interpretation","claude_config_dir_set","outer_wrap_cohorts","roots","roots_distinct","roots_note","activity_witness","trigger_class_nonzero","classes"] | sort))
    and .schema_version == 1 and .ok == true
    and (.run_id | type == "number" and . >= 1 and . <= 1000000000 and . == floor)
    and (.mode | IN("dry_run","real")) and (.data_source | IN("synthetic","container_home"))
    and (.build_sha | test("^([0-9a-f]{40}|dev)$")) and (.control | IN("passed","failed"))
    and (.evidence | IN("young","mature")) and (.uptime_bucket | IN("lt_1h","lt_24h","lt_7d","ge_7d"))
    and (.sunset_utc | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T00:00:00Z$"))
    and (.truncated | type == "boolean") and (.truncation_reason | IN("none","entry_cap","time_cap","load_shed","class_budget"))
    and .snapshot == "non_atomic" and .mode_bits_semantics == "file_mode_only_not_reachability" and .interpretation == $interp
    and (.claude_config_dir_set | type == "boolean") and .outer_wrap_cohorts == "unmeasured"
    and (.roots | type == "array" and length <= 3 and all(.[]; ((keys | sort) == ["label","root_listable","root_present"]) and (.label | IN("env_home","home_soleur","root")) and (.root_present | type == "boolean") and (.root_listable | type == "boolean")))
    and (.roots_distinct | type == "boolean") and (.roots_note | IN("none","env_home_rejected","homedir_unavailable"))
    and (.activity_witness | type == "boolean") and (.trigger_class_nonzero | IN("true","false","unknown","inconclusive"))
    and ((.classes | map(.class)) == order)
    and (.classes | all(.[]; ((keys | sort) == ["absent","class","class_result","errors","n_entries","n_mode_bits_group_r","n_mode_bits_other_r","n_symlink"])
        and ([.n_entries,.n_mode_bits_group_r,.n_mode_bits_other_r,.n_symlink,.errors] | all(bucket))
        and (.absent | type == "boolean") and (.class_result | IN("none_counted","counted","unknown","inconclusive"))))
  ' "$1" >/dev/null 2>&1
}

# error_class of a non-2xx body, printed ONLY when the body is exactly the closed failure shape (a proxy page is never echoed).
failure_class() {
  jq -er --arg interp "$INTERPRETATION" 'select(((keys | sort) == ["error_class","interpretation","ok","schema_version"]) and .schema_version == 1 and .ok == false and .interpretation == $interp
      and (.error_class | IN("unavailable","unauthorized","sunset","payload_too_large","invalid_json","invalid_body","invalid_mode","build_mismatch","young_container","busy","rate_limited","control_failed","internal"))) | .error_class' "$RESP" 2>/dev/null || true
}

status_exit() { # $1 = dry_run|real; maps a non-2xx answer to an exit code and a closed-set message
  local cls tag=""
  cls="$(failure_class)"
  [[ -z "$cls" ]] || tag=" error_class=${cls}"
  case "$HTTP_CODE" in
    401|404) die 4 "home-census-trigger: unauthorized or not found (status class 4xx)${tag}" ;;
    403) die 5 "home-census-trigger: forbidden (status class 4xx); the body is not printed" ;;
    5*)
      if [[ "$1" == "real" ]]; then
        die 6 "home-census-trigger: server error (status class 5xx${tag}). The scan may have run. Read Sentry and Better Stack first; do not retry."
      fi
      die 6 "home-census-trigger: server error (status class 5xx${tag}); no scan runs in dry_run, safe to retry" ;;
    *) die 11 "home-census-trigger: refused by the server (status ${HTTP_CODE})${tag}" ;;
  esac
}

TOKEN="$(doppler secrets get "$SECRET_NAME" -p soleur -c prd --plain 2>/dev/null)" || die 3 "home-census-trigger: could not read the secret from Doppler; nothing was sent"
_bearer_ok "$TOKEN" || die 3 "home-census-trigger: the secret is empty or has an unexpected shape; nothing was sent"

SERVED="$(served_sha)" || die 9 "home-census-trigger: /health did not report a 40-hex build_sha (a 'dev' build fails closed); nothing was sent"

if [[ "$MODE" == "dry_run" ]]; then
  BODY="$(build_body dry_run "$RUN_ID" "$SERVED" false)"
  rc=0; run_curl "$BODY" "$TOKEN" || rc=$?
  unset TOKEN
  [[ "$rc" -eq 0 ]] || die 12 "home-census-trigger: the preflight request did not complete (curl exit $rc); no scan runs in dry_run, safe to retry"
  if [[ "$HTTP_CODE" == 2* ]]; then
    body_valid "$RESP" || die 10 "home-census-trigger: the preflight body failed the allowlist schema; it is not printed"
    cat "$RESP"; echo; exit 0
  fi
  status_exit dry_run
fi

# ----------------------------- real -----------------------------
TRUSTED="$(trusted_comments)" || die 8 "home-census-trigger: could not read the tracker comments; nothing was sent"

# (1) C8: the DISCHARGED comment from a pinned author must name this sha and PR.
DIS_LINE="$(grep -E '^home-census C8 DISCHARGED sha=[0-9a-f]{40} pr=[0-9]+$' <<<"$TRUSTED" | tail -n 1 || true)"
[[ -n "$DIS_LINE" ]] || die 8 "home-census-trigger: no C8 DISCHARGED comment from a pinned author; nothing was sent"
[[ "$DIS_LINE" == "home-census C8 DISCHARGED sha=${DISCHARGED} pr=${PR}" ]] || die 8 "home-census-trigger: --discharged-sha/--pr do not match the C8 DISCHARGED comment; nothing was sent"
git rev-parse --show-toplevel >/dev/null 2>&1 || die 8 "home-census-trigger: not inside the repository"

# (2) Both commits must be available locally. The PR head is fetched into FETCH_HEAD only, to make the discharged
# commit available after a squash merge; no ancestry is inferred from it (the census-path diff below is the binding).
git cat-file -e "${SERVED}^{commit}" 2>/dev/null || git fetch --no-tags origin main >/dev/null 2>&1 || true
git cat-file -e "${DISCHARGED}^{commit}" 2>/dev/null || git fetch --no-tags origin "refs/pull/${PR}/head" >/dev/null 2>&1 || true
git cat-file -e "${SERVED}^{commit}" 2>/dev/null || die 9 "home-census-trigger: the served build is not available locally; nothing was sent"
git cat-file -e "${DISCHARGED}^{commit}" 2>/dev/null || die 8 "home-census-trigger: the discharged commit is not available locally; nothing was sent"

# (3) The CLO record of the SERVED build (not the working tree) carries this sha as a line of its own.
git show "${SERVED}:${CLO_RECORD}" 2>/dev/null | grep -qxF -- "DISCHARGED sha=${DISCHARGED}" || die 8 "home-census-trigger: the CLO record of the served build does not carry this sha; nothing was sent"

# (4) The served build's bound paths equal the discharged commit's, and the script that is running is the reviewed one.
git diff --quiet --no-ext-diff "$DISCHARGED" "$SERVED" -- "${CENSUS_PATHS[@]}" || die 9 "home-census-trigger: the bound paths of the served build differ from the discharged commit; nothing was sent"
git diff --quiet --no-ext-diff "$DISCHARGED" -- "$SCRIPT_REL" || die 8 "home-census-trigger: this trigger script differs from the discharged commit; nothing was sent"
[[ -z "$(git status --porcelain -- "$SCRIPT_REL" 2>/dev/null)" ]] || die 8 "home-census-trigger: this trigger script has uncommitted changes; nothing was sent"
# Not bound (neither can add a field to the object): shown so the CLO sees any new transform, enrichment, field or route prefix.
VSTAT="$(git diff --stat "$DISCHARGED" "$SERVED" -- apps/web-platform/infra/vector.toml apps/web-platform/lib/routes.ts 2>/dev/null || true)"
printf 'home-census-trigger: vector.toml and routes.ts diff, discharged commit to served build: %s\n' "${VSTAT:-none}" >&2

# (5) Preflight dry_run: mature container (C9) unless an explicit fallback.
PRE_BODY="$(build_body dry_run "$RUN_ID" "$SERVED" false)"
rc=0; run_curl "$PRE_BODY" "$TOKEN" || rc=$?
{ [[ "$rc" -eq 0 ]] && [[ "$HTTP_CODE" == 2* ]] && body_valid "$RESP"; } || die 8 "home-census-trigger: the preflight dry_run failed; nothing was sent"
EVIDENCE="$(jq -r '.evidence' "$RESP")"; UPB="$(jq -r '.uptime_bucket' "$RESP")"
if [[ "$C9_FALLBACK" -ne 1 ]]; then
  [[ "$EVIDENCE" == "mature" && ( "$UPB" == "lt_7d" || "$UPB" == "ge_7d" ) ]] || die 8 "home-census-trigger: the container is young; wait for 24 h of uptime and run the preflight again; nothing was sent"
fi

# (6) Two-run cap and monotonic run_id, from pinned-author claims only.
CLAIMS="$(grep -E '^home-census run_id=[0-9]+ claim$' <<<"$TRUSTED" || true)"
NCLAIMS=0; MAXID=0
if [[ -n "$CLAIMS" ]]; then
  NCLAIMS="$(wc -l <<<"$CLAIMS" | tr -d ' ')"
  MAXID="$(sed -E 's/^home-census run_id=([0-9]+) claim$/\1/' <<<"$CLAIMS" | sort -n | tail -n 1)"
fi
[[ "$NCLAIMS" -lt 2 ]] || die 8 "home-census-trigger: two claims already exist (the cap is two real runs); nothing was sent"
[[ "$RUN_ID" -gt "$MAXID" ]] || die 8 "home-census-trigger: --run-id must be above the last claim; nothing was sent"

# (7) Write-ahead claim BEFORE the request, then read it back: a claim that does not appear as a pinned-author comment
# means the posting account is not the pinned one (the cap would then be unenforced), and a count above two means a
# concurrent run. gh failure fails closed.
gh issue comment "$ISSUE" -R "$REPO" --body "home-census run_id=${RUN_ID} claim" >/dev/null 2>&1 || die 8 "home-census-trigger: could not post the claim comment; nothing was sent"
RECHECK="$(trusted_comments)" || die 8 "home-census-trigger: could not re-read the tracker comments after the claim; nothing was sent"
grep -qxF -- "home-census run_id=${RUN_ID} claim" <<<"$RECHECK" || die 8 "home-census-trigger: the claim is not visible as a pinned-author comment (wrong posting account?); nothing was sent"
[[ "$(grep -cE '^home-census run_id=[0-9]+ claim$' <<<"$RECHECK" || true)" -le 2 ]] || die 8 "home-census-trigger: more than two claims exist after posting (a concurrent run?); nothing was sent"

# (8) The request. expect_build_sha comes from /health; the response build is re-compared after the call.
ACCEPT=false; [[ "$C9_FALLBACK" -eq 1 ]] && ACCEPT=true
BODY="$(build_body real "$RUN_ID" "$SERVED" "$ACCEPT")"
rc=0; run_curl "$BODY" "$TOKEN" || rc=$?
unset TOKEN
if [[ "$rc" -ne 0 ]]; then
  die 7 "home-census-trigger: the request did not complete (curl exit $rc). The scan may have run. Read Sentry and Better Stack first; do not retry."
fi
mark_done() { gh issue comment "$ISSUE" -R "$REPO" --body "home-census run_id=${RUN_ID} done" >/dev/null 2>&1 || true; }
AFTER="$(served_sha || true)"
case "$HTTP_CODE" in
  2*)
    if body_valid "$RESP" && [[ "$AFTER" == "$SERVED" ]] && [[ "$(jq -r '.build_sha' "$RESP")" == "$SERVED" ]]; then
      mark_done; cat "$RESP"; echo; exit 0
    fi
    mark_done
    die 10 "home-census-trigger: the response failed the allowlist schema or the build changed during the call; the scan ran, so read Sentry and Better Stack; the body is not printed" ;;
  5*) status_exit real ;;
  *) mark_done; status_exit real ;;
esac
