#!/usr/bin/env bash
# post-deploy-incident-soak.sh — GENERIC post-merge alert-channel soak for the
# follow-through sweeper (epic #10390, WS3; ADR-297). No issue number is baked
# in: one copy serves every enrollment, so no tracker's identity appears here.
#
# WHAT IT PROVES. In the window [deploy_ts, deploy_ts + SOAK_HOURS] BOTH watched
# alert surfaces stayed clean:
#   (1) ZERO new Better Stack incidents — /api/v2/incidents rows whose
#       started_at falls inside the window, resolved OR open (a page that fired
#       and auto-resolved inside the window is still a finding);
#   (2) ZERO new `ci/` GitHub issues — the whole watchdog filing family
#       (ci/inngest-*, ci/betterstack-incident, ci/zot-*, ci/prod-version-drift,
#       … — label PREFIX `ci/`, never one label) created inside the window.
#
# LIVENESS GATE (the convention's liveness-marker rule: never PASS a soak whose
# producer may have been silent). Before a PASS, the alert substrate must
# answer — GET /api/v2/heartbeats AND /api/v2/monitors must each return, and at
# least one member must be ARMED (status up|down), or "zero incidents" proves
# nothing. `paused`/`pending` members are TOLERATED: counted and logged, never a
# FAIL driver — but they cannot establish liveness on their own (the
# 2026-07-24 born-not-yet-armed learning: a for_each monitor is born `paused`,
# never ABSENT). A substrate where NOTHING is armed answers CANNOT ESTABLISH.
#
# EXIT CONTRACT (sweep-followthroughs.sh):
#   0   PASS              -> sweeper closes the tracker
#   1   FAIL              -> >=1 in-window incident or ci/ issue; sweeper
#                          comments, leaves open (the soak failed — a human
#                          judges whether the page was the deploy's own fault)
#   2   NOT YET           -> the soak window has not fully elapsed, or the
#                          deploy anchor is absent/unparseable
#   3   CANNOT ESTABLISH  -> any read failure, unparseable payload, a truncated
#                          result set, or zero armed heartbeat/monitor members
#   78  xtrace refusal (#7797)
#
# DEPLOY ANCHOR (the only input). The sweeper execs probes argv-free under
# `env -i`; the only per-tracker channel is earliest= -> SOLEUR_FT_EARLIEST.
# Convention for THIS script: earliest is the soak END — enroll with
# earliest=<deploy_ts+24h> so the first sweep runs only after the whole window
# elapsed; the probe derives deploy_ts = SOLEUR_FT_EARLIEST - SOAK_HOURS.
# Manual/debug runs pin the anchor directly — argv $1 or
# POST_DEPLOY_SOAK_DEPLOY_TS — but neither reaches the probe under the sweeper:
# only declared secrets= names bound in the workflow env are forwarded (#10552).
# The window is INCLUSIVE at both ends: an incident stamped at deploy_ts counts
# as post-deploy, one at the exact window end counts as in-window.
#
# Required env (declare via secrets=): GH_TOKEN — `gh issue list` is
#   unauthenticated under `env -i` without it, so the convention makes
#   secrets=GH_TOKEN MANDATORY for any gh-using probe even though this script
#   files nothing (read-only use of a write-capable token is what the clause
#   forwards; the soak itself never comments, closes or creates). And
#   BETTERSTACK_API_TOKEN — the account-wide uptime-API read, already bound in
#   scheduled-followthrough-sweeper.yml.
# Optional env: SOLEUR_FT_EARLIEST (sweeper-forwarded), POST_DEPLOY_SOAK_DEPLOY_TS,
#   POST_DEPLOY_SOAK_WINDOW_HOURS (default 24), POST_DEPLOY_SOAK_ISSUE_LIMIT
#   (default 200), GH_REPO (default jikig-ai/soleur). Test seams:
#   POST_DEPLOY_SOAK_NOW_EPOCH (fake clock); `curl` and `gh` are PATH-shimmed
#   by the harness.
#
# PUBLIC-COMMENT DISCIPLINE. The sweeper republishes this script's output
# verbatim into an issue comment: incidents are projected to
# {id,name,cause,started_at}, issues to {number,title,createdAt}; the bearer
# never rides argv; transport errors are token-scrubbed before echo.
#
# RETIREMENT: generic — keep as long as ANY live directive names it;
# `gh issue list --label follow-through` and grep the bodies for
# `post-deploy-incident-soak` before deleting (a closed-within-lookback
# tracker still runs it).
# Observability layer: 6 (sweeper workflow run log + the tracker issue comment
# the sweeper posts). cq-test-fixtures-synthesized-only: no live response is
# captured into this file or its suite.
#
# Directive example (a merge tracker, deploy at 2026-10-24T18:00:00Z):
#   <!-- soleur:followthrough
#     script=scripts/followthroughs/post-deploy-incident-soak.sh
#     earliest=2026-10-25T18:00:00Z
#     secrets=GH_TOKEN,BETTERSTACK_API_TOKEN
#   -->

set -uo pipefail

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797). The sweeper
# publishes stdout verbatim into a public issue comment.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_API_TOKEN:+x}${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C
# Same TLS-subversion prologue as betterstack-query.sh / the sibling probes:
# none of these can re-point a Bearer request or leak its keys when the
# sweeper's `env -i` is absent (a local `doppler run`).
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
export TMPDIR="${TMPDIR:-/var/tmp}"

GH_REPO="${GH_REPO:-jikig-ai/soleur}"
UPTIME_HOST="uptime.betterstack.com"
PAGE_CAP=50

emit() { printf 'SOLEUR_POST_DEPLOY_INCIDENT_SOAK verdict=%s detail="%s"\n' "$1" "${2//\"/}"; }
transient() { printf 'TRANSIENT: %s\n' "$1" >&2; }
notyet()   { printf 'NOT YET: %s\n'   "$1" >&2; }

# ISO-8601 -> epoch. GNU `date -d` first, BSD/macOS `date -j -f` fallback.
iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}
epoch_iso() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}
# Canonical ISO-8601 UTC ONLY — earliest= is issue-body data any member can
# edit, and GNU `date -d` accepts natural-language single tokens ("now",
# "@epoch") that would silently move the window (the actions-queue-tail-8450
# shape, review #8472).
canonical_iso() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; }

# ── Inputs ────────────────────────────────────────────────────────────────────
SOAK_HOURS="${POST_DEPLOY_SOAK_WINDOW_HOURS:-24}"
if [[ ! "$SOAK_HOURS" =~ ^[0-9]+$ ]] || [[ "$SOAK_HOURS" -eq 0 ]]; then
  notyet "POST_DEPLOY_SOAK_WINDOW_HOURS '${SOAK_HOURS}' is not a positive integer; nothing is known about the window."
  emit unknown "window-hours-invalid"
  exit 2
fi
SOAK_S=$(( SOAK_HOURS * 3600 ))

ISSUE_LIMIT="${POST_DEPLOY_SOAK_ISSUE_LIMIT:-200}"
if [[ ! "$ISSUE_LIMIT" =~ ^[0-9]+$ ]] || [[ "$ISSUE_LIMIT" -eq 0 ]]; then
  notyet "POST_DEPLOY_SOAK_ISSUE_LIMIT '${ISSUE_LIMIT}' is not a positive integer."
  emit unknown "issue-limit-invalid"
  exit 2
fi

DEPLOY_TS="${1:-${POST_DEPLOY_SOAK_DEPLOY_TS:-}}"
if [[ -z "$DEPLOY_TS" ]]; then
  # Sweeper path: earliest= is the soak END, so deploy_ts = earliest - SOAK_HOURS.
  earliest="${SOLEUR_FT_EARLIEST:-}"
  if [[ -z "$earliest" ]]; then
    notyet "no deploy anchor — argv \$1, POST_DEPLOY_SOAK_DEPLOY_TS and SOLEUR_FT_EARLIEST are all unset. Under the sweeper, enroll earliest=<deploy_ts+${SOAK_HOURS}h>."
    emit unknown "deploy-anchor-unset"
    exit 2
  fi
  if ! canonical_iso "$earliest"; then
    notyet "SOLEUR_FT_EARLIEST '${earliest}' is not canonical ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ) — issue-body data is not trusted at read."
    emit unknown "earliest-noncanonical"
    exit 2
  fi
  earliest_epoch="$(iso_epoch "$earliest" || true)"
  if [[ -z "${earliest_epoch:-}" ]]; then
    notyet "SOLEUR_FT_EARLIEST '${earliest}' is not a parseable ISO timestamp."
    emit unknown "earliest-unparseable"
    exit 2
  fi
  DEPLOY_EPOCH=$(( earliest_epoch - SOAK_S ))
  DEPLOY_TS="$(epoch_iso "$DEPLOY_EPOCH")"
else
  if ! canonical_iso "$DEPLOY_TS"; then
    notyet "deploy anchor '${DEPLOY_TS}' is not canonical ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ)."
    emit unknown "deploy-anchor-noncanonical"
    exit 2
  fi
  DEPLOY_EPOCH="$(iso_epoch "$DEPLOY_TS" || true)"
  if [[ -z "${DEPLOY_EPOCH:-}" ]]; then
    notyet "deploy anchor '${DEPLOY_TS}' is not a parseable ISO timestamp."
    emit unknown "deploy-anchor-unparseable"
    exit 2
  fi
fi

WINDOW_END_EPOCH=$(( DEPLOY_EPOCH + SOAK_S ))
WINDOW_END="$(epoch_iso "$WINDOW_END_EPOCH")"

NOW_EPOCH="${POST_DEPLOY_SOAK_NOW_EPOCH:-$(date -u +%s)}"
if [[ ! "$NOW_EPOCH" =~ ^[0-9]+$ ]]; then
  notyet "POST_DEPLOY_SOAK_NOW_EPOCH '${NOW_EPOCH}' is not an epoch integer."
  emit unknown "now-invalid"
  exit 2
fi
if (( NOW_EPOCH < WINDOW_END_EPOCH )); then
  notyet "soak window [${DEPLOY_TS} .. ${WINDOW_END}] has not fully elapsed (now=$(epoch_iso "$NOW_EPOCH")) — the sweeper's earliest= gate should already have deferred this; check the directive."
  emit not_yet "window-open deploy=${DEPLOY_TS} end=${WINDOW_END}"
  exit 2
fi

# ── Prereqs ───────────────────────────────────────────────────────────────────
# NOT `: "${VAR:?msg}"` — that aborts with status 1, which the sweeper reads as
# FAIL (the convention's varq ban).
if [[ -z "${GH_TOKEN:-}" ]]; then
  transient "GH_TOKEN is not set (declare secrets=GH_TOKEN in the directive); the ci/ issue half cannot run."
  emit unknown "GH_TOKEN-unset"
  exit 3
fi
if [[ -z "${BETTERSTACK_API_TOKEN:-}" ]]; then
  transient "BETTERSTACK_API_TOKEN is not set (declare it in the directive's secrets=); the incidents half cannot run."
  emit unknown "BETTERSTACK_API_TOKEN-unset"
  exit 3
fi
command -v gh   >/dev/null 2>&1 || { transient "gh not on PATH";  emit unknown "gh-absent";  exit 3; }
command -v jq   >/dev/null 2>&1 || { transient "jq not on PATH";  emit unknown "jq-absent";  exit 3; }
command -v curl >/dev/null 2>&1 || { transient "curl not on PATH"; emit unknown "curl-absent"; exit 3; }
# Token-shape guard: a newline in the token would inject a curl config directive
# on the stdin channel below, and an empty one would send the request
# headerless. Never echoes it.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
if ! _bearer_ok "$BETTERSTACK_API_TOKEN"; then
  transient "BETTERSTACK_API_TOKEN is unusable (unexpected shape); nothing is known about the substrate."
  emit unknown "BETTERSTACK_API_TOKEN-unusable"
  exit 3
fi

WORK="$(mktemp -d -t pdis.XXXXXXXX)" || { emit unknown "mktemp-failed"; exit 3; }
trap 'rm -rf "$WORK"' EXIT

redact() { # scrub the bearer from any text about to be printed
  local s="$1"
  s="${s//"$BETTERSTACK_API_TOKEN"/<redacted>}"
  s="${s//"$GH_TOKEN"/<redacted>}"
  printf '%s' "$s"
}

# ── Paged GET with an exact host pin on pagination.next (the token never leaves
# the host). Prints concatenated `.data[]` objects as one JSON array. Returns 0,
# or non-zero with a reason on stderr; every caller maps failure to exit 3. An
# optional stop epoch ends the walk once a page's OLDEST started_at predates it
# — the endpoints are newest-first, so everything past that page is irrelevant.
paged_get() { # <path> [stop-epoch]
  local url="https://${UPTIME_HOST}$1" stop="${2:-}" page=0 body="$WORK/page.json" code rc oldest
  : > "$WORK/pages.ndjson"
  while [[ -n "$url" ]]; do
    page=$((page + 1))
    if [[ "$page" -gt "$PAGE_CAP" ]]; then printf 'pagination exceeded %s pages on %s\n' "$PAGE_CAP" "$UPTIME_HOST" >&2; return 1; fi
    case "$url" in
      "https://${UPTIME_HOST}/"*) ;;
      *) printf 'refusing off-host pagination.next\n' >&2; return 1 ;;
    esac
    rc=0
    # -g: no URL globbing; --max-redirs 0 for explicitness. The bearer rides
    # curl's stdin config channel, never argv.
    code="$(curl --disable --noproxy '*' -g -sS -m 20 --proto '=https' --max-redirs 0 -o "$body" -w '%{http_code}' \
      -H 'Accept: application/json' --config - "$url" \
      < <(printf 'header = "Authorization: Bearer %s"\n' "$BETTERSTACK_API_TOKEN"))" || rc=$?
    if [[ "$rc" -ne 0 ]]; then printf 'curl exited %s on GET %s\n' "$rc" "${url%%\?*}" >&2; return 1; fi
    case "$code" in 2*) ;; *) printf 'HTTP %s on GET %s\n' "$code" "${url%%\?*}" >&2; return 1 ;; esac
    if ! jq -e '.data | type == "array"' "$body" >/dev/null 2>&1; then printf 'no data array in GET %s\n' "${url%%\?*}" >&2; return 1; fi
    jq -c '.data[]' "$body" >> "$WORK/pages.ndjson"
    if [[ -n "$stop" ]]; then
      oldest="$(jq -r '[.data[] | .attributes.started_at // empty | (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch empty)] | min // empty' "$body" 2>/dev/null)"
      if [[ "$oldest" =~ ^[0-9]+$ ]] && [[ "$oldest" -lt "$stop" ]]; then break; fi
    fi
    url="$(jq -r '.pagination.next // empty' "$body")"
  done
  jq -s '.' "$WORK/pages.ndjson"
}

# ── (1) Better Stack incidents started inside the window ─────────────────────
if ! incidents="$(paged_get "/api/v2/incidents?per_page=50" "$DEPLOY_EPOCH" 2>"$WORK/err")"; then
  transient "incidents read did not answer: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "incidents-read-failed"
  exit 3
fi
# PROJECTED, never raw: the raw objects carry acknowledged_by / resolved_by /
# screenshot URLs and this stdout lands in a public issue comment. A started_at
# the parser cannot read is a transport fault, never a verdict. Window bounds
# are INCLUSIVE ([deploy_ts, deploy_ts+SOAK_HOURS]).
if ! in_window="$(printf '%s' "$incidents" | jq -c --argjson s "$DEPLOY_EPOCH" --argjson e "$WINDOW_END_EPOCH" '
  [.[] | {id, name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at}
       | . + {epoch: ((.started_at // "1970-01-01T00:00:00Z") | (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch null))}]
  | if any(.[]; .epoch == null) then error("unparseable started_at") else . end
  | [.[] | select(.epoch >= $s and .epoch <= $e) | del(.epoch)]' 2>"$WORK/err")"; then
  transient "incident list unparseable: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "incidents-parse-failed"
  exit 3
fi
incident_n="$(printf '%s' "$in_window" | jq 'length')"

# ── (2) `ci/` GitHub issues created inside the window ────────────────────────
# The search qualifier bounds created >= deploy server-side; the window's upper
# bound and the `ci/` label-PREFIX filter are re-asserted client-side so a
# stubbed page cannot smuggle a row. --state all: an issue created AND closed
# inside the window (an auto-resolved filing) is still a finding.
if ! issues_raw="$(gh issue list --repo "$GH_REPO" --state all \
    --search "created:>=${DEPLOY_TS}" --limit "$ISSUE_LIMIT" \
    --json number,title,createdAt,labels 2>"$WORK/err")"; then
  transient "gh issue list failed (auth/network): $(redact "$(tr '\n' ' ' < "$WORK/err")")"
  emit unknown "issues-read-failed"
  exit 3
fi
returned_n="$(printf '%s' "$issues_raw" | jq 'length' 2>/dev/null || echo "")"
if [[ -z "$returned_n" ]]; then
  transient "gh issue list returned an unparseable payload."
  emit unknown "issues-parse-failed"
  exit 3
fi
if [[ "$returned_n" -eq "$ISSUE_LIMIT" ]]; then
  # A result set saturated at the limit is TRANSIENT, never a verdict — rows
  # past the cap could carry the ci/ filing being measured.
  transient "issue list saturated at --limit ${ISSUE_LIMIT} for created:>=${DEPLOY_TS}; the window cannot be judged on a truncated set. Raise POST_DEPLOY_SOAK_ISSUE_LIMIT or narrow the window."
  emit unknown "issues-truncated limit=${ISSUE_LIMIT}"
  exit 3
fi
ci_issues="$(printf '%s' "$issues_raw" | jq -c --arg d "$DEPLOY_TS" --arg e "$WINDOW_END" '
  [.[] | select(.createdAt >= $d and .createdAt <= $e
       and (((.labels // []) | map(.name) | map(select(startswith("ci/"))) | length) > 0))
     | {number, title, createdAt}]')"

# ── Verdict before the liveness gate: a finding is a finding (the filed
# incident itself proves the substrate paged — no liveness read needed). ──────
issue_n="$(printf '%s' "$ci_issues" | jq 'length')"
if [[ "$incident_n" -gt 0 || "$issue_n" -gt 0 ]]; then
  printf 'FAIL: %s Better Stack incident(s) and %s ci/ issue(s) in the soak window [%s .. %s]:\n' \
    "$incident_n" "$issue_n" "$DEPLOY_TS" "$WINDOW_END" >&2
  strip() { tr -d '\000-\037\177' | sed 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/\xe2\x80\x8b//g; s/\xef\xbb\xbf//g' | tr '\n' ' '; }
  printf '%s\n' "$in_window" | jq -r '.[] | "  incident #\(.id) \(.name) (cause=\(.cause // "n/a"), started \(.started_at))"' | strip | head -10 >&2
  printf '%s\n' "$ci_issues" | jq -r '.[] | "  issue #\(.number) \(.title) (opened \(.createdAt))"' | strip | head -10 >&2
  emit fail "incidents=${incident_n} ci_issues=${issue_n} deploy=${DEPLOY_TS} end=${WINDOW_END}"
  exit 1
fi

# ── (3) Liveness gate — zero findings only PASS on a proven-live substrate ────
armed=0
tolerated=0
other=0
for endpoint in heartbeats monitors; do
  if ! members="$(paged_get "/api/v2/${endpoint}?per_page=50" "" 2>"$WORK/err")"; then
    transient "${endpoint} read did not answer: $(redact "$(tr '\n' ' ' < "$WORK/err")")"
    emit unknown "${endpoint}-read-failed"
    exit 3
  fi
  counts="$(printf '%s' "$members" | jq -r '
    [.[] | (.attributes.status // "unknown")]
    | reduce .[] as $s ({armed:0, tolerated:0, other:0};
        if ($s == "up" or $s == "down") then .armed += 1
        elif ($s == "paused" or $s == "pending") then .tolerated += 1
        else .other += 1 end)
    | "\(.armed) \(.tolerated) \(.other)"' 2>/dev/null)"
  if [[ -z "$counts" ]]; then
    transient "${endpoint} list unparseable (no status fields)."
    emit unknown "${endpoint}-parse-failed"
    exit 3
  fi
  read -r a t o <<<"$counts"; other=$(( other + o ))
  armed=$(( armed + a ))
  tolerated=$(( tolerated + t ))
done
if [[ "$armed" -lt 1 ]]; then
  transient "no heartbeat or monitor member is ARMED (status up|down); ${tolerated} member(s) read paused/pending — born-but-not-yet-armed is not liveness evidence, so 'zero incidents' proves nothing (2026-07-24 learning)."
  emit unknown "substrate-unarmed tolerated=${tolerated} other=${other}"
  exit 3
fi

emit pass "incidents=0 ci_issues=0 deploy=${DEPLOY_TS} end=${WINDOW_END} armed=${armed} tolerated=${tolerated}"
echo "PASS: zero new Better Stack incidents and zero new ci/ issues in [${DEPLOY_TS} .. ${WINDOW_END}]; alert substrate armed=${armed} member(s) (${tolerated} paused/pending tolerated)."
exit 0
