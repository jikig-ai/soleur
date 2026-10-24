#!/usr/bin/env bash
# (#10390 WS1) Better Stack incident mirror: read `GET /api/v2/incidents?resolved=false` with
# the read-only token and file/dedupe/auto-resolve `[ci/betterstack-incident]` GitHub issues —
# the channel that actually reached the operator on 2026-10-22, when the Inngest host replace
# fired heartbeat incidents whose only delivery was an unwatched email inbox.
#
# THE PROPERTY. Every open incident produces exactly one open issue keyed on the incident-id
# body marker `<!-- betterstack-incident id=<n> -->`; a resolved incident resolves only its own
# mirror-filed issue; a read failure always exits non-zero (never a silent green — a silent
# mirror is the defect class this file exists to close).
#
# PER RUN:
#   1. GET one page (?resolved=false&per_page=50), projected to {id,name,cause,started_at,url}.
#      Raw objects are NEVER printed: the token can read beat-capability ping URLs, so the
#      projection is the control (public-comment discipline, send-failed-alert-probe-8097.sh).
#   2. For each open incident: dedupe by BODY MARKER (never title — the #10918 class), comment
#      on a marker-matched open issue, else create with labels ci/betterstack-incident,
#      action-required, priority/p1-high. A human-filed same-TITLE issue with no marker is
#      untouched.
#   3. `pagination.next` non-null: annotated AND page 1 processed AND a degraded-class issue
#      filed — `[ci/betterstack-incident-mirror]` is a DISTINCT title from the incident class
#      so the two classes never collide in dedupe.
#   4. Resolve: close mirror-filed open issues whose incident-id the filing pass did not TOUCH
#      this run. THE ORDER IS LOAD-BEARING (Guard 1 row 3): resolve reads the touched-ledger
#      the filing pass writes; a resolve that ran first would see it empty and close live
#      issues. Any gh write failure aborts before resolve, so "untouched" means "absent from
#      the vendor's open list".
#
# EXIT CONTRACT. Exit 0 means exactly {mirrored, no_incidents} for every run that reached a
# verdict. The one other zero is --selftest (no network, no credentials). Every other outcome
# is non-zero: 3 a read could not be established (token, API, issues list, malformed JSON), 4 a
# gh write failed mid-run, 64 usage, 78 tracing refused. The EXIT trap rewrites any status
# outside that set — and a 0 no verdict produced — to 3.
#
# CREDENTIALS. BETTERSTACK_API_TOKEN_READONLY (GET only; can read ping URLs, so output is
# projected) reaches curl on stdin config (--config -), never argv, behind --disable
# --noproxy '*' and the TLS/DNS env scrub — parity with inngest-probe-heartbeat-feeder.sh and
# scripts/betterstack-query.sh. GH_TOKEN/GH_REPO drive the gh CLI (issues: write).
#
# Observability: the workflow's terminal sentry-heartbeat step checks in `ok` only on a
# deciding exit 0; a missed check-in is the dead-mirror page (ADR-248 dispatch table row).
# Harness: scripts/betterstack-incident-mirror.test.sh.
set -uo pipefail

# XTRACE REFUSAL (#7797). Tracing echoes a command after expansion, so under bash -x a
# credential reaches the transcript the moment it is bound. `case "$-"` tests whether tracing
# is ON rather than enumerating the ways to turn it on.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_API_TOKEN_READONLY:+x}${GH_TOKEN:+x}" ]; then
      printf 'betterstack-incident-mirror: verdict=xtrace_refused refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

marker() { # <verdict> [k=v ...]
  printf 'betterstack-incident-mirror: verdict=%s %s\n' "$1" "${2:-}"
}

# Set to 1 immediately before the two legitimate exits of status 0, and nowhere else.
DECIDED=0
WORK=""
cleanup_work() { if [[ -n "$WORK" && -d "$WORK" ]]; then rm -rf -- "$WORK"; fi; return 0; }
# NEVER an unexplained 0. Every status outside the contract, and a 0 that no verdict produced,
# is rewritten to 3. Each allowed status is spelled out as a literal so the harness's static
# allowlist can read every one. Installed directly after the xtrace refusal, before any other
# statement; the harness also forbids exec, kill and a second trap.
on_exit() {
  local rc=$?
  cleanup_work
  case "$rc" in
    0) if [ "$DECIDED" = 1 ]; then exit 0; fi ;;
    3) exit 3 ;;
    4) exit 4 ;;
    64) exit 64 ;;
    78) exit 78 ;;
  esac
  marker "trap_remapped" "rc=$rc"
  echo "CANNOT MIRROR: the mirror ended on a status outside its contract; nothing was decided. This says nothing about the incident list."
  exit 3
}
trap on_exit EXIT

export LC_ALL=C
# TLS/DNS environment that can substitute the trust store or the resolver for this file's own
# credentialed curl (parity with the feeder, #7873): --disable and --noproxy do not cover it.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
export TMPDIR="${TMPDIR:-/var/tmp}"

# Location-independent by construction: no lib sourcing, no git invocation, --repo on every gh.

# One page of 50 (12 heartbeats + monitors today). When the API reports a further page the
# mirror fails safe: annotate, process page 1, file the degraded class — never silently drop.
API_URL="https://uptime.betterstack.com/api/v2/incidents?resolved=false&per_page=50"
ISSUE_LABEL="ci/betterstack-incident"
TITLE_PREFIX="[ci/betterstack-incident]"
DEGRADED_TITLE="[ci/betterstack-incident-mirror] Incident list is paged — mirror read page 1 only"
DEGRADED_MARKER='betterstack-incident-mirror kind=paged'
TOKEN_RE='^[A-Za-z0-9._~+/=-]{20,}$'

if [[ "$#" -ne 0 ]]; then
  if [[ "$#" -eq 1 && "$1" == "--selftest" ]]; then
    # Hermetic: no network, no credentials — proves the projection jq compiles.
    jq -en '{data: [], pagination: {next: null}} | [.data[] | {id: (.id | tostring), name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at, url: .attributes.url}] | length == 0' >/dev/null \
      || { marker read_failed "reason=selftest_jq"; echo "CANNOT MIRROR: jq could not run the projection."; exit 3; }
    echo "betterstack-incident-mirror selftest: ok"
    DECIDED=1
    exit 0
  fi
  marker "usage" "argc=$#"
  echo "usage: betterstack-incident-mirror.sh takes no arguments except --selftest"
  exit 64
fi

fail_read() { # <reason> <human line>
  marker read_failed "reason=$1"
  echo "CANNOT MIRROR: $2"
  exit 3
}
fail_write() { # <reason> <human line>
  marker write_failed "reason=$1"
  echo "CANNOT MIRROR: $2"
  exit 4
}

TOK="${BETTERSTACK_API_TOKEN_READONLY:-}"
if [[ -z "$TOK" ]]; then
  fail_read token_unset "BETTERSTACK_API_TOKEN_READONLY is not set, so the incidents API cannot be read. The mirror is dark; this is the failure it exists to report."
fi
# No quote or newline can survive this shape, so none can add a curl directive. Never echoed.
if [[ ! "$TOK" =~ $TOKEN_RE ]]; then
  fail_read token_malformed "BETTERSTACK_API_TOKEN_READONLY does not have the shape of an API token."
fi
if [[ -z "${GH_REPO:-}" ]]; then
  fail_read gh_repo_unset "GH_REPO is not set; issues cannot be deduplicated or filed."
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
  fail_read gh_token_unset "GH_TOKEN is not set; the gh CLI is unauthenticated."
fi
command -v gh >/dev/null 2>&1 || fail_read gh_missing "the gh CLI is not on PATH."
command -v jq >/dev/null 2>&1 || fail_read jq_missing "jq is not on PATH."
command -v curl >/dev/null 2>&1 || fail_read curl_missing "curl is not on PATH."

WORK="$(mktemp -d "${TMPDIR}/betterstack-incident-mirror.XXXXXXXX")" \
  || fail_read mktemp "mktemp failed."

NOW="$(date -u '+%Y-%m-%d %H:%M UTC')"
RUN_URL="${RUN_URL:-n/a}"
# Every gh invocation rides the ONE chokepoint so --repo is never forgotten; calls under it
# carry the repo's issue-write scope (issues: write on github.token only).
ghw() { gh "$@" --repo "$GH_REPO"; }

# ── READ 1: the open-incident list (ONE page) ────────────────────────────────────────────
read_open_incidents() {
  local http crc=0
  http="$(printf 'header = "Authorization: Bearer %s"\n' "$TOK" \
    | curl --disable --noproxy '*' -g -sS -m 20 --proto '=https' --max-redirs 0 \
      -o "$WORK/api.json" -w '%{http_code}' -H 'Accept: application/json' --config - "$API_URL" \
      2>/dev/null)" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    fail_read "api_unreadable curl_rc=$crc" "the incidents API could not be read (curl status $crc). A dark mirror is the failure this file exists to report."
  fi
  case "$http" in
    2*) ;;
    *) fail_read "api_http http=$http" "the incidents API answered HTTP $http (a 401 means the read-only token is wrong or revoked)." ;;
  esac
  if ! jq -e '.data | type == "array"' "$WORK/api.json" >/dev/null 2>&1; then
    fail_read api_malformed "the incidents answer carried no data array."
  fi
  projected="$(jq -c '[.data[] | {id: (.id | tostring), name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at, url: .attributes.url}]' "$WORK/api.json" 2>/dev/null)" \
    || fail_read api_malformed "the incidents list could not be projected."
  OPEN_COUNT="$(printf '%s' "$projected" | jq 'length')"
  PAGED=0
  if [[ -n "$(jq -r '.pagination.next // empty' "$WORK/api.json")" ]]; then PAGED=1; fi
}

# ── READ 2: open issues on the label -> dedupe map (incident-id marker -> number) ───────
read_open_issues() {
  if ! ghw issue list --state open --label "$ISSUE_LABEL" --limit 200 --json number,title,body > "$WORK/issues.json" 2>/dev/null; then
    fail_read issues_unreadable "gh issue list failed; dedupe is impossible so nothing was filed or closed (a blind filing is worse than a loud miss)."
  fi
  if ! jq -e 'type == "array"' "$WORK/issues.json" >/dev/null 2>&1; then
    fail_read issues_malformed "gh issue list did not return a JSON array."
  fi
  jq -r '.[] | ((.body // "") | [scan("betterstack-incident id=[A-Za-z0-9_-]+")] | first // "") as $m
       | select($m != "") | "\($m | sub("betterstack-incident id=";""))\t\(.number)"' \
       "$WORK/issues.json" > "$WORK/issue_map" \
    || fail_read issues_malformed "the dedupe map could not be built."
  DEGRADED_NUM="$(jq -r --arg m "$DEGRADED_MARKER" '.[] | select((.body // "") | contains($m)) | .number' "$WORK/issues.json" | head -1)"
}

# ── FILING PASS: one issue per open incident, keyed on the body marker ─────────────────
sanitize() { printf '%s' "$1" | tr -d '\000-\037\177' | tr '\n' ' '; }

file_one() { # <projected incident object>
  local inc="$1" id name cause started url title num bodyf
  id="$(printf '%s' "$inc" | jq -r '.id')"
  name="$(printf '%s' "$inc" | jq -r '.name // "unnamed monitor"')"
  name="$(sanitize "$name" | head -c 120)"
  cause="$(printf '%s' "$inc" | jq -r '.cause // "n/a"')"
  cause="$(sanitize "$cause" | head -c 300)"
  started="$(printf '%s' "$inc" | jq -r '.started_at // "n/a"')"
  url="$(printf '%s' "$inc" | jq -r '.url // ""')"
  case "$url" in https://*) ;; *) url="n/a" ;; esac
  title="$TITLE_PREFIX $name"
  num="$(awk -F'\t' -v id="$id" '$1 == id {print $2}' "$WORK/issue_map" | head -1)"
  if [[ -n "$num" ]]; then
    ghw issue comment "$num" \
      --body "Still open at ${NOW} — incident \`${id}\` (\`${name}\`), cause \`${cause}\`. Run: ${RUN_URL}" >/dev/null \
      || fail_write "issue_comment id=$id" "the dedupe comment on issue #$num failed mid-run."
    commented=$((commented + 1))
  else
    local l
    for l in "$ISSUE_LABEL" action-required priority/p1-high; do
      gh label create "$l" --repo "$GH_REPO" --description "Better Stack incident mirror filing" --color B60205 2>/dev/null || true
    done
    bodyf="$WORK/body.$id.md"
    {
      printf '## Better Stack incident is open\n\n'
      printf -- '- **Monitor/heartbeat:** `%s`\n' "$name"
      printf -- '- **Incident id:** `%s`\n' "$id"
      printf -- '- **Cause:** `%s`\n' "$cause"
      printf -- '- **Started:** `%s`\n' "$started"
      printf -- '- **Vendor incident:** %s\n' "$url"
      printf -- '- **Detected:** %s\n' "$NOW"
      printf -- '- **Run log:** %s\n\n' "$RUN_URL"
      printf 'Filed by `scripts/betterstack-incident-mirror.sh` (scheduled-betterstack-incident-mirror.yml); it auto-resolves when the incident leaves the vendor open list. A same-titled issue filed by a human is a different issue — dedupe keys on the marker below, never the title (#10918).\n\n'
      printf '<!-- betterstack-incident id=%s -->\n' "$id"
    } > "$bodyf"
    ghw issue create --title "$title" \
      --label "$ISSUE_LABEL" --label action-required --label priority/p1-high \
      --body-file "$bodyf" >/dev/null \
      || fail_write "issue_create id=$id" "gh issue create failed for incident $id."
    created=$((created + 1))
  fi
  printf '%s\n' "$id" >> "$WORK/touched"
}

file_open_incidents() {
  local inc
  while IFS= read -r inc; do
    [[ -z "$inc" ]] && continue
    file_one "$inc"
  done <<<"$(printf '%s' "$projected" | jq -c '.[]')"
}

# ── PAGED: annotate, file the degraded class (distinct title), or auto-resolve it ──────
handle_paged() {
  degraded_action="none"
  local bodyf
  if [[ "$PAGED" == 1 ]]; then
    printf 'betterstack-incident-mirror: note=paged detail="pagination.next present; page 1 processed, later pages not read"\n'
    if [[ -n "$DEGRADED_NUM" ]]; then
      ghw issue comment "$DEGRADED_NUM" \
        --body "Incident list still paged at ${NOW}; the mirror reads page 1 only (per_page=50). Run: ${RUN_URL}" >/dev/null \
        || fail_write degraded_comment "the degraded-class comment failed."
      degraded_action="commented"
    else
      bodyf="$WORK/body.degraded.md"
      {
        printf '## Better Stack incident list is paged\n\nThe mirror read `pagination.next` on `GET /api/v2/incidents?resolved=false&per_page=50` at %s — open incidents exist beyond page 1 and are NOT mirrored. Fail-safe posture: annotate, process page 1, never silently drop. Raise the page size or follow `pagination.next`.\n\n- **Run log:** %s\n\n<!-- %s -->\n' "$NOW" "$RUN_URL" "$DEGRADED_MARKER"
      } > "$bodyf"
      ghw issue create --title "$DEGRADED_TITLE" \
        --label "$ISSUE_LABEL" --label action-required --label priority/p2-medium \
        --body-file "$bodyf" >/dev/null \
        || fail_write degraded_create "the degraded-class filing failed."
      degraded_action="created"
    fi
  elif [[ -n "$DEGRADED_NUM" ]]; then
    ghw issue close "$DEGRADED_NUM" \
      --comment "Incident list no longer paged at ${NOW} — page 1 covers the open set. Run: ${RUN_URL}" >/dev/null \
      || fail_write degraded_close "the degraded-class close failed."
    degraded_action="closed"
  fi
}

# ── RESOLVE PASS (must run AFTER the filing pass — the order is load-bearing) ──────────
resolve_stale_issues() {
  local iid inum
  while IFS=$'\t' read -r iid inum; do
    [[ -z "$iid" ]] && continue
    if grep -qxF "$iid" "$WORK/touched"; then continue; fi
    ghw issue close "$inum" \
      --comment "resolved upstream at ${NOW} — incident \`${iid}\` is no longer in Better Stack's open list. Run: ${RUN_URL}" >/dev/null \
      || fail_write "issue_close id=$iid" "the resolve close on issue #$inum failed."
    resolved=$((resolved + 1))
  done < "$WORK/issue_map"
}

emit_verdict() {
  if (( created + commented + resolved > 0 )) || [[ "$degraded_action" != "none" ]]; then
    marker mirrored "created=$created commented=$commented resolved=$resolved paged=$PAGED degraded=$degraded_action"
    echo "MIRRORED: created=$created commented=$commented resolved=$resolved paged=$PAGED degraded=$degraded_action"
  else
    marker no_incidents "open=$OPEN_COUNT paged=$PAGED"
    echo "MIRRORED: no open incidents and nothing to resolve."
  fi
  DECIDED=1
  exit 0
}

# ── MAIN ──────────────────────────────────────────────────────────────────────────────
projected="[]"; OPEN_COUNT=0; PAGED=0; DEGRADED_NUM=""
created=0; commented=0; resolved=0; degraded_action="none"
read_open_incidents
read_open_issues
: > "$WORK/touched"
file_open_incidents
handle_paged
resolve_stale_issues
emit_verdict
