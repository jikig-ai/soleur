#!/usr/bin/env bash
# (#12180) Did the inverted egress-gateway probe-silence alert hold, and did its canary fire?
#
# WHAT IT PROVES. The Better Stack Logs alert `soleur-egress-gw-probe-silent-prd` was changed to report the
# NUMBER OF ROSTER HOSTS THAT DID NOT EMIT (`higher_than 0`, `treat_as_zero`), and a throwaway canary alert
# `soleur-egress-gw-probe-silent-canary-prd` runs the same query against an identifier no host emits, so it
# must read 2 and open an incident. This script reads, in ORDER, so each verdict names ONE cause:
#
#   (1) the anchor incident (id 1047829421, the false positive this change must clear): open or resolved,
#       and when                                      (GET uptime.betterstack.com/api/v2/incidents/<id>)
#   (2) the incident list, newest first, walked until the page that carries the anchor — everything newer
#       than the anchor is then in hand, so a recurrence and a canary incident are both visible
#                                                      (GET uptime.betterstack.com/api/v2/incidents)
#   (3) the live alert listing: does the canary ALERT exist (separates "the evaluator never fired it" from
#       "the apply never created it")                  (GET telemetry.betterstack.com/api/v2/alerts)
#   (4) whether the canary resource is still DECLARED in the checkout's betterstack-logs-alerts.tf
#       (comment lines dropped first)
#   (5) only when the production incident is open or a newer one exists: per-host COUNTS of `egress-gw-probe`
#       rows over that incident's window (never row content) — the one field that separates an evaluator fault
#       (rows on both hosts) from an emitter or ingest fault (a host with none). Diagnostic only: a failed
#       read prints rows_in_window=unknown and cannot change the verdict.
#
# Incidents are matched on EXACT `.attributes.name` equality for both alerts. No startswith/test/contains: a
# canary cause that quotes the production alert name must never read as a production recurrence.
#
# VERDICT LINE (stdout, one per run, printed only by verdict()):
#   SOLEUR_EGRESS_GW_SILENT_SOAK verdict=<v> prod_incident=<open|resolved|unknown> resolved_age_s=<n>
#     newer_prod_incident=<0|1> canary=<fired|absent|unknown> canary_alert_live=<1|0|unknown>
#     canary_declared=<0|1> rows_in_window=<host:n,...|na|unknown>
#   One field per condition, so a caller can read any of them whatever the overall verdict (the postmerge step
#   reads `canary=` at apply completion + 25 minutes). A field that was not read yet when the run ended is
#   `unknown`; resolved_age_s is -1 when the production incident is open or unread; rows_in_window is `na`
#   when no rows read was needed.
#
# EXIT CONTRACT (sweep-followthroughs.sh):
#   0   PASS             verdict=pass            -> the sweeper CLOSES the tracker. Reachable only when the anchor
#                                                    was resolved >= 4 h ago, no newer production incident exists,
#                                                    a canary incident exists AND the canary is no longer declared.
#   2   NOT YET          verdict=not_yet         -> anchor still open (inside the horizon) or resolved < 4 h ago
#   3   CANNOT ESTABLISH verdict=unknown         -> any read failure, unparseable payload, truncated list, bad env
#   5   ACTION REQUIRED  verdict=action_required -> the sweeper comments. Any of: canary absent with the canary alert
#                                                    live (evaluator blind for this query shape -> heartbeat poller
#                                                    #12190, production alert stays armed); canary absent with the
#                                                    canary alert absent (the apply never created it: fix the apply);
#                                                    a production incident newer than the anchor (recurrence); the
#                                                    anchor still open past the horizon (poller or a pause); or all
#                                                    verification held but the canary is still declared (delete it).
#                                                    None of these wait for the 4 h window.
#   78  xtrace refusal (#7797)
#   exit 1 is NEVER used: to the sweeper 1 is FAIL, which can reopen a human-closed tracker. An EXIT trap remaps
#   a stray 1 (and any path that exits without a verdict) to verdict=unknown / 3.
#
# "EARLIEST" PROXY. The tracker's `earliest` (apply completion + 30 min) is not visible to a script that runs under
# `env -i`. "Open more than 4 h after earliest" is therefore approximated by the canary incident's started_at (the
# canary alert opens its incident one evaluation after the apply creates it): the anchor is STALE when it is still
# open and the canary incident is more than STALE_S = 4 h + 15 min old.
#
# HOST CHOICE (pre-step, 2026-11-05, read-only, one authenticated GET per host with BETTERSTACK_API_TOKEN_READONLY
# from Doppler soleur/prd_terraform; only HTTP status codes and key names were recorded): BOTH
# https://uptime.betterstack.com/api/v2/incidents and https://incidents.betterstack.com/api/v3/incidents answered
# HTTP 200 with the same shape (top-level data/pagination; the same attribute keys incl. name, cause, started_at,
# resolved_at, status; pagination first/last/next/prev; newest first; per_page honoured), and the anchor incident
# (a Logs-alert incident) is readable by id on both. This probe uses the v2 UPTIME host because two working repo
# scripts (send-failed-alert-probe-8097.sh, betterstack-incident-mirror.sh) already depend on it, so one vendor
# deprecation breaks all three together instead of this one silently.
#
# PUBLIC-COMMENT DISCIPLINE. The sweeper posts stdout+stderr verbatim into a public issue comment. Incident objects
# are projected to {id,name,started_at,resolved_at} before anything is printed; on an API failure only the HTTP
# status and the byte length are printed (never a body, never a credential); a refused pagination URL is reported by
# host only; a failed warehouse read prints its exit code and byte length only.
#
# Test seams (never set by the sweeper): EGRESS_GW_SILENT_BQ (betterstack-query.sh path), EGRESS_GW_SILENT_TF (the .tf),
# EGRESS_GW_SILENT_NOW_EPOCH (the clock), EGRESS_GW_SILENT_ANCHOR_ID, EGRESS_GW_SILENT_ROSTER (space-separated host
# names), EGRESS_GW_SILENT_PAGE_CAP. `curl` is PATH-shimmed by the harness.
# Observability layer: 6 (sweeper workflow run log + the tracker issue comment the sweeper posts).
# cq-test-fixtures-synthesized-only: no live response is captured into this file.
#
# RETIREMENT: when the canary is deleted (follow-up PR, as soon as a canary incident has been observed), touch every
#   site below in the same change; the count suites flip -1 here exactly as they flipped +1 when the canary landed.
#   (1) apps/web-platform/infra/betterstack-logs-alerts.tf: delete the local egress_gw_probe_silent_canary_sql and the
#       resources logtail_exploration.egress_gw_probe_silent_canary and logtail_exploration_alert.egress_gw_probe_silent_canary
#       (alert first); this probe's canary_declared turns 0 when the alert header is gone.
#   (2) .github/workflows/apply-web-platform-infra.yml: keep BOTH canary -target lines for exactly one apply (a bare
#       -target on an address with no configuration plans its DELETE), remove them in a later PR (the #11631 then #11672
#       sequence). The deletion plan shows 2 destroyed and needs a standalone [ack-destroy] line in the merge commit.
#   (3) tests/scripts/test-infra-privileged-tier-census.sh: add the two logtail addresses to INTENDED_DESTROYS for that
#       window, remove them with the targets; re-run apps/web-platform/infra/betterstack-alert-structure.test.sh rows 21-22
#       (they tolerate a bare -target only for a listed address; whether they accept a logtail_* row is unverified today).
#   (4) apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh: EXPECT_BLOCKS 19 -> 18 and re-derive MIN_PASSES.
#   (5) apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh: count == 19 -> 18 and its comment list.
#   (6) apps/web-platform/test/infra/egress-gw-alert.test.sh: delete the G2b canary block and its mutation rows; re-derive
#       PRESENCE_ROWS and MUT_ROWS at BOTH write sites each; fix the exact count of egress_gw_probe_silent* resources (4 -> 2).
#   (7) knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md: the canary section of the
#       soleur-egress-gw-probe-silent-prd heading; and ADR-218's canary note (the amendment records the end state).
#   After the sweeper PASS closes the tracker, closed_precheck never runs this again; the script stays as the reproduction.

set -uo pipefail

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797). `case "$-" in *x*)` tests whether tracing is ON
# rather than enumerating the eight ways to turn it on. Exit 78 is the one non-contract code the sweeper retries.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_API_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BQ="${EGRESS_GW_SILENT_BQ:-${REPO_ROOT}/scripts/betterstack-query.sh}"
TF="${EGRESS_GW_SILENT_TF:-${REPO_ROOT}/apps/web-platform/infra/betterstack-logs-alerts.tf}"
ANCHOR_ID="${EGRESS_GW_SILENT_ANCHOR_ID:-1047829421}"
ROSTER="${EGRESS_GW_SILENT_ROSTER:-soleur-web-platform soleur-web-2}"
PAGE_CAP="${EGRESS_GW_SILENT_PAGE_CAP:-50}"

PROD_NAME="soleur-egress-gw-probe-silent-prd"
CANARY_NAME="soleur-egress-gw-probe-silent-canary-prd"
CANARY_RESOURCE="egress_gw_probe_silent_canary"
EMITTER_TAG="egress-gw-probe"
SOAK_S=14400            # 4 h
STALE_S=15300           # 4 h + 15 min grace past the canary incident's start (the "earliest" proxy)
ROWS_LOOKBACK_S=1209600 # 14 d: cap on the rows_in_window read
ALERTS_HOST="telemetry.betterstack.com"
INCIDENTS_HOST="uptime.betterstack.com"

# ── State for the single verdict line ────────────────────────────────────────────────────────
V_PROD=unknown; V_AGE=-1; V_NEWER=unknown; V_CANARY=unknown; V_ALIVE=unknown; V_DECL=unknown; V_ROWS=na
VERDICT_DONE=0
WORK=""

# THE chokepoint: the only place a SOLEUR_EGRESS_GW_SILENT_SOAK line is printed and the only place the contract
# exit codes are chosen. <verdict> <exit>
verdict() {
  VERDICT_DONE=1
  printf 'SOLEUR_EGRESS_GW_SILENT_SOAK verdict=%s prod_incident=%s resolved_age_s=%s newer_prod_incident=%s canary=%s canary_alert_live=%s canary_declared=%s rows_in_window=%s\n' \
    "$1" "$V_PROD" "$V_AGE" "$V_NEWER" "$V_CANARY" "$V_ALIVE" "$V_DECL" "$V_ROWS"
  exit "$2"
}
transient() { printf 'TRANSIENT: %s\n' "$1" >&2; }
action() { printf 'ACTION REQUIRED: %s\n' "$1" >&2; }

# Any path that reaches here without a verdict (an unbound variable, a failed builtin) is unknown, never a bare
# status; a stray exit 1 is remapped, because to the sweeper 1 is FAIL.
_on_exit() {
  local rc=$?
  [[ -n "$WORK" ]] && rm -rf "$WORK" 2>/dev/null
  if [[ "$VERDICT_DONE" != 1 ]]; then
    VERDICT_DONE=1
    transient "the probe ended without a verdict (status ${rc})"
    printf 'SOLEUR_EGRESS_GW_SILENT_SOAK verdict=unknown prod_incident=%s resolved_age_s=%s newer_prod_incident=%s canary=%s canary_alert_live=%s canary_declared=%s rows_in_window=%s\n' \
      "$V_PROD" "$V_AGE" "$V_NEWER" "$V_CANARY" "$V_ALIVE" "$V_DECL" "$V_ROWS"
    exit 3
  fi
  [[ "$rc" -eq 1 ]] && exit 3
  return 0
}
trap _on_exit EXIT
trap 'exit 3' INT TERM HUP

unknown() { transient "$1"; verdict unknown 3; }

# ── Environment ──────────────────────────────────────────────────────────────────────────────
# NOT `: "${VAR:?msg}"` — that aborts with status 1, which the sweeper reads as FAIL.
[[ -n "${BETTERSTACK_API_TOKEN:-}" ]] || unknown "BETTERSTACK_API_TOKEN is not set in this environment; nothing is known"
# Token-shape guard: a newline would inject a curl config directive on the stdin channel http_get uses, and an empty
# one would send the request headerless. Never echoes it.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_bearer_ok "${BETTERSTACK_API_TOKEN}" || unknown "BETTERSTACK_API_TOKEN is unusable (unexpected shape); nothing is known"
[[ "$ANCHOR_ID" =~ ^[0-9]+$ ]] || unknown "anchor incident id is not numeric"
[[ "$PAGE_CAP" =~ ^[0-9]+$ && "$PAGE_CAP" -ge 1 ]] || unknown "page cap is not a positive integer"
NOW="${EGRESS_GW_SILENT_NOW_EPOCH:-$(date -u +%s)}"
[[ "$NOW" =~ ^[0-9]+$ ]] || unknown "the clock is not an epoch"
[[ -f "$TF" ]] || unknown "betterstack-logs-alerts.tf not found at ${TF}"
command -v jq >/dev/null 2>&1 || unknown "jq is not available"
WORK="$(mktemp -d -t egs-probe.XXXXXXXX)" || unknown "mktemp failed"

# ── HTTP ─────────────────────────────────────────────────────────────────────────────────────
# One GET with the bearer on curl's STDIN config channel (never argv: #7797). Returns 0 or non-zero with ONE reason
# line on stderr that carries the HTTP status and byte length only — never the body, never a credential.
http_get() { # <url> <outfile>
  local url="$1" body="$2" code rc=0 bytes
  : > "$body"
  # -g: no URL globbing; --max-redirs 0 for explicitness; --proto =https pins the scheme.
  code="$(curl --disable --noproxy '*' -g -sS -m 20 --proto '=https' --max-redirs 0 -o "$body" -w '%{http_code}' \
    -H 'Accept: application/json' --config - "$url" \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$BETTERSTACK_API_TOKEN"))" || rc=$?
  bytes="$(wc -c < "$body" 2>/dev/null || echo 0)"; bytes="${bytes//[[:space:]]/}"
  if [[ "$rc" -ne 0 ]]; then printf 'curl exited %s on GET %s (bytes=%s)\n' "$rc" "${url%%\?*}" "$bytes" >&2; return 1; fi
  case "$code" in 2*) ;; *) printf 'HTTP %s on GET %s (bytes=%s)\n' "$code" "${url%%\?*}" "$bytes" >&2; return 1 ;; esac
  return 0
}

# Paged GET of a `.data` list with an exact host pin on pagination.next (the token never leaves the host). Prints the
# concatenated `.data[]` objects as a JSON array. With a stop epoch the walk ends at the first page whose OLDEST
# started_at is <= it (the endpoint is newest-first, so everything after that page is older than the anchor).
paged_get() { # <host> <path> [stop-epoch]
  local host="$1" url="https://$1$2" stop="${3:-}" page=0 body="$WORK/page.json" oldest
  : > "$WORK/pages.ndjson"
  while [[ -n "$url" ]]; do
    page=$((page + 1))
    if [[ "$page" -gt "$PAGE_CAP" ]]; then printf 'pagination exceeded %s pages on %s\n' "$PAGE_CAP" "$host" >&2; return 1; fi
    case "$url" in
      "https://${host}/"*) ;;
      *) printf 'refusing off-host pagination.next (host=%s)\n' "$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://([^/?@]*@)?([^/?#]*).*#\2#')" >&2; return 1 ;;
    esac
    http_get "$url" "$body" || return 1
    if ! jq -e '.data | type == "array"' "$body" >/dev/null 2>&1; then
      printf 'no data array in GET %s (bytes=%s)\n' "${url%%\?*}" "$(wc -c < "$body" | tr -d '[:space:]')" >&2; return 1
    fi
    jq -c '.data[]' "$body" >> "$WORK/pages.ndjson"
    if [[ -n "$stop" ]]; then
      oldest="$(jq -r '[.data[] | .attributes.started_at // empty | (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch empty)] | min // empty' "$body" 2>/dev/null)"
      if [[ "$oldest" =~ ^[0-9]+$ ]] && [[ "$oldest" -le "$stop" ]]; then break; fi
    fi
    url="$(jq -r '.pagination.next // empty' "$body")"
  done
  jq -s '.' "$WORK/pages.ndjson"
}

# ── (1) The anchor incident ──────────────────────────────────────────────────────────────────
http_get "https://${INCIDENTS_HOST}/api/v2/incidents/${ANCHOR_ID}" "$WORK/single.json" 2>"$WORK/err" \
  || unknown "anchor incident read did not answer: $(tr '\n' ' ' < "$WORK/err")"
if ! anchor="$(jq -c '
  def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
  .data | select(type == "object")
  | {id: (.id|tostring), name: .attributes.name, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at}
  | . + {epoch: (.started_at | ep), resolved_epoch: (if .resolved_at == null then null else (.resolved_at | ep) end)}' "$WORK/single.json" 2>/dev/null)" \
  || [[ -z "$anchor" ]]; then
  unknown "anchor incident payload unparseable (bytes=$(wc -c < "$WORK/single.json" | tr -d '[:space:]'))"
fi
if [[ "$(printf '%s' "$anchor" | jq -r '.name')" != "$PROD_NAME" ]] || [[ "$(printf '%s' "$anchor" | jq -r '.id')" != "$ANCHOR_ID" ]]; then
  unknown "incident ${ANCHOR_ID} is not an incident of ${PROD_NAME}: the anchor cannot be trusted"
fi
A_EPOCH="$(printf '%s' "$anchor" | jq -r '.epoch')"
A_RES_EPOCH="$(printf '%s' "$anchor" | jq -r '.resolved_epoch // empty')"
[[ "$A_EPOCH" =~ ^[0-9]+$ ]] || unknown "anchor started_at is not a time"
if [[ -z "$A_RES_EPOCH" ]]; then
  V_PROD=open; V_AGE=-1
else
  [[ "$A_RES_EPOCH" =~ ^[0-9]+$ ]] || unknown "anchor resolved_at is not a time"
  V_PROD=resolved; V_AGE=$((NOW - A_RES_EPOCH))
fi

# ── (2) The incident list, walked back to the anchor ─────────────────────────────────────────
paged_get "$INCIDENTS_HOST" "/api/v2/incidents?per_page=50" "$A_EPOCH" > "$WORK/incidents.json" 2>"$WORK/err" \
  || unknown "incident list did not answer: $(tr '\n' ' ' < "$WORK/err")"
# PROJECTED, never raw: the raw objects carry acknowledged_by / resolved_by / screenshot URLs and this stdout lands in a
# public issue comment. An unparseable started_at is a transport fault (exit 3), never a verdict.
if ! projected="$(jq -c --arg p "$PROD_NAME" --arg c "$CANARY_NAME" '
  def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
  [.[] | {id: (.id|tostring), name: .attributes.name, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at,
          is_prod: (.attributes.name == $p), is_canary: (.attributes.name == $c)}
       | . + {epoch: ((.started_at // "1970-01-01T00:00:00Z") | (try ep catch null)),
              resolved_epoch: (if .resolved_at == null then null else (.resolved_at | (try ep catch null)) end)}]
  | if any(.[]; .epoch == null) then error("unparseable started_at") else . end' "$WORK/incidents.json" 2>/dev/null)"; then
  unknown "incident list unparseable (bytes=$(wc -c < "$WORK/incidents.json" | tr -d '[:space:]'))"
fi
# The anchor MUST be on the list we walked: its absence means the list is truncated, stale or a different view than the
# single read, and every conclusion drawn from it (no recurrence, no canary) would be drawn from nothing.
if [[ "$(printf '%s' "$projected" | jq --arg id "$ANCHOR_ID" '[.[] | select(.id == $id)] | length')" != "1" ]]; then
  unknown "the walked incident list does not carry the anchor ${ANCHOR_ID} exactly once: the list is truncated or inconsistent"
fi

# Exact-equality matches (is_prod / is_canary are `.attributes.name ==` booleans computed above; never a prefix,
# substring or cause match).
newer="$(printf '%s' "$projected" | jq -c --arg id "$ANCHOR_ID" --argjson a "$A_EPOCH" \
  '[.[] | select(.is_prod and .id != $id and .epoch > $a)] | sort_by(.epoch)')"
canary_inc="$(printf '%s' "$projected" | jq -c '[.[] | select(.is_canary)] | sort_by(.epoch)')"
if [[ "$(printf '%s' "$newer" | jq 'length')" -gt 0 ]]; then V_NEWER=1; else V_NEWER=0; fi
CANARY_EPOCH=""
if [[ "$(printf '%s' "$canary_inc" | jq 'length')" -gt 0 ]]; then
  V_CANARY=fired; CANARY_EPOCH="$(printf '%s' "$canary_inc" | jq -r '.[0].epoch')"
else
  V_CANARY=absent
fi

# ── (3) The live alert listing ───────────────────────────────────────────────────────────────
paged_get "$ALERTS_HOST" "/api/v2/alerts" > "$WORK/alerts.json" 2>"$WORK/err" \
  || unknown "alert listing did not answer: $(tr '\n' ' ' < "$WORK/err")"
if ! live="$(jq -r --arg n "$CANARY_NAME" '[.[] | select(.attributes.name == $n)] | length' "$WORK/alerts.json" 2>/dev/null)" || [[ ! "$live" =~ ^[0-9]+$ ]]; then
  unknown "alert listing unparseable (bytes=$(wc -c < "$WORK/alerts.json" | tr -d '[:space:]'))"
fi
if [[ "$live" -gt 0 ]]; then V_ALIVE=1; else V_ALIVE=0; fi

# ── (4) Is the canary still declared? (comment lines dropped first) ──────────────────────────
[[ -r "$TF" ]] || unknown "betterstack-logs-alerts.tf is not readable at ${TF}"
tf_stripped="$(grep -vE '^[[:space:]]*#' "$TF")"
if printf '%s\n' "$tf_stripped" | grep -qE "^[[:space:]]*resource[[:space:]]+\"logtail_exploration_alert\"[[:space:]]+\"${CANARY_RESOURCE}\"[[:space:]]*\{"; then
  V_DECL=1
else
  V_DECL=0
fi

# ── (5) rows_in_window (diagnostic only; a failure here never changes the verdict) ───────────
if [[ "$V_PROD" == open || "$V_NEWER" == 1 ]]; then
  V_ROWS=unknown
  if [[ "$V_NEWER" == 1 ]]; then
    win="$(printf '%s' "$newer" | jq -c '.[-1]')"
  else
    win="$(printf '%s' "$projected" | jq -c --arg id "$ANCHOR_ID" '[.[] | select(.id == $id)][0]')"
  fi
  w_start="$(printf '%s' "$win" | jq -r '.epoch')"
  w_end="$(printf '%s' "$win" | jq -r '.resolved_epoch // empty')"
  [[ "$w_end" =~ ^[0-9]+$ ]] || w_end="$NOW"
  if [[ "$w_start" =~ ^[0-9]+$ ]] && [[ -f "$BQ" ]] && [[ -n "${BETTERSTACK_QUERY_HOST:-}" && -n "${BETTERSTACK_QUERY_USERNAME:-}" && -n "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
    floor=$((NOW - ROWS_LOOKBACK_S)); [[ "$w_start" -lt "$floor" ]] && w_start="$floor"
    d_start="$(date -u -d "@${w_start}" '+%Y-%m-%d %H:%M:%S')"; d_end="$(date -u -d "@${w_end}" '+%Y-%m-%d %H:%M:%S')"
    WINDOW="dt >= '${d_start}' AND dt <= '${d_end}'"
    UNION="SELECT dt, raw FROM remote(\$BS_TABLE) WHERE ${WINDOW}
       UNION ALL
       SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND ${WINDOW}"
    sql="SELECT JSONExtractString(raw, 'host_name') AS host, count() AS n FROM (${UNION})
  WHERE JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = '${EMITTER_TAG}'
  GROUP BY host ORDER BY host FORMAT JSONEachRow"
    bq_rc=0
    bq_out="$(bash "$BQ" "$sql" 2>&1)" || bq_rc=$?
    answered=1
    if [[ "$bq_rc" -ne 0 ]]; then
      answered=0; transient "warehouse read did not answer (rc=${bq_rc}, bytes=${#bq_out}); rows_in_window is unknown"
    else
      # A ClickHouse mid-stream exception arrives as a BARE line on a 200 (#7855 P1-B): every non-empty line must be an object.
      while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == '{'* ]] || { answered=0; break; }
      done <<<"$bq_out"
      if [[ "$answered" == 1 ]] && ! printf '%s\n' "$bq_out" | jq -e -s 'all(type == "object")' >/dev/null 2>&1; then answered=0; fi
      [[ "$answered" == 0 ]] && transient "warehouse read returned a non-row answer (bytes=${#bq_out}); rows_in_window is unknown"
    fi
    if [[ "$answered" == 1 ]]; then
      if rows="$(printf '%s\n' "$bq_out" | jq -r -s --arg roster "$ROSTER" '
          ([.[] | {host: (.host // ""), n: ((.n // 0) | tostring)}]) as $r
          | ($roster | split(" ") | map(select(length > 0))) as $ro
          | (($ro + ($r | map(.host))) | unique | map(select(length > 0))) as $hosts
          | $hosts | map(. as $h | "\($h):\(([$r[] | select(.host == $h) | (.n | tonumber)] | add) // 0)") | join(",")' 2>/dev/null)" && [[ -n "$rows" ]]; then
        V_ROWS="$rows"
      fi
    fi
  fi
fi

# ── Verdict ──────────────────────────────────────────────────────────────────────────────────
proj_newer="$(printf '%s' "$newer" | jq -c '[.[] | {id, name, started_at, resolved_at}]')"
if [[ "$V_CANARY" == absent && "$V_ALIVE" == 1 ]]; then
  action "no canary incident exists although the canary alert ${CANARY_NAME} is live: the evaluator is blind for this query shape (an inference; the query itself is proven). Build the heartbeat poller (#12190) now, leave the production alert ARMED, and do not read a green production alert as healthy until the canary has fired. Anchor incident ${ANCHOR_ID}: ${V_PROD}."
  verdict action_required 5
fi
if [[ "$V_CANARY" == absent ]]; then
  action "no canary incident exists and ${CANARY_NAME} is not in the live alert listing: the apply never created it (alert-count cap refusal or a failed create). Check the merge run's Terraform apply step for logtail_exploration_alert.${CANARY_RESOURCE} and hotfix the apply; this is not an evaluator finding."
  verdict action_required 5
fi
if [[ "$V_NEWER" == 1 ]]; then
  action "a ${PROD_NAME} incident started after the anchor ${ANCHOR_ID} (recurrence; projected): ${proj_newer}. rows_in_window=${V_ROWS} separates an evaluator fault (rows on both hosts) from an emitter or ingest fault (a host with none). Response: the poller (#12190) or a pause, each needing the owner's per-command go-ahead for any Better Stack write; never a revert."
  verdict action_required 5
fi
if [[ "$V_PROD" == open ]]; then
  if [[ "$CANARY_EPOCH" =~ ^[0-9]+$ ]] && [[ $((NOW - CANARY_EPOCH)) -gt "$STALE_S" ]]; then
    action "anchor incident ${ANCHOR_ID} is still open more than ${STALE_S}s after the canary incident started (the earliest proxy): the inverted shape did not clear it. rows_in_window=${V_ROWS} (rows on both hosts means an empty-window read or a vendor that never auto-resolves; a host with none is real silence). Response: the poller (#12190) or a pause; close this tracker in favor of #12190 with its follow-through label removed; a manual resolve is a Better Stack write needing the owner's per-command go-ahead."
    verdict action_required 5
  fi
  transient "anchor incident ${ANCHOR_ID} is still open (inside the horizon); rows_in_window=${V_ROWS}"
  verdict not_yet 2
fi
if [[ "$V_AGE" -lt "$SOAK_S" ]]; then
  transient "anchor incident ${ANCHOR_ID} resolved ${V_AGE}s ago; the soak needs ${SOAK_S}s"
  verdict not_yet 2
fi
if [[ "$V_DECL" == 1 ]]; then
  action "all verification held (anchor resolved >= 4 h ago, no recurrence, canary incident seen) but the canary alert is still declared in betterstack-logs-alerts.tf: delete the canary (its incident, P1 mirror issue and email should not outlive their job). The RETIREMENT: header of this script lists every site to touch."
  verdict action_required 5
fi
verdict pass 0
