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
#   (3) the live alert listing: does the canary ALERT exist and is it unpaused (separates "the evaluator never
#       fired it" from "the apply never created it" and from "someone paused it"), and is the PRODUCTION alert
#       still present, unpaused and in the inverted shape (`higher_than 0`) — a PASS must never rest on an alert
#       that was deleted, paused or reverted            (GET telemetry.betterstack.com/api/v2/alerts)
#   (4) whether the canary resource is still DECLARED in the checkout's betterstack-logs-alerts.tf
#       (comment lines dropped first)
#   (5) per-host COUNTS of `egress-gw-probe` rows over the TRAILING 15 MINUTES (the alert's own query window;
#       never row content, host names outside [A-Za-z0-9._-]{1,63} are folded into `other`). Diagnostic while a
#       production incident is open or a recurrence exists (a failed read prints rows_in_window=unknown and cannot
#       change that verdict), and VERDICT-BEARING on the pass path: an unreadable read is exit 3 and a roster host
#       with no rows is exit 5, so a green production alert over a silent host can never close the tracker.
#
# THE FLOOR AND THE SOAK CLOCK (#12189). The recurrence floor is the PINNED apply time, APPLY_FLOOR_EPOCH below. A
# production incident counts as a recurrence when it started at or after FLOOR - SLACK_S (300 s; the canary incident
# started 64 s BEFORE its alert was created, so the apply's own window needs slack) and is not the anchor. Earlier
# incidents are the OLD alert shape flapping before the apply (incident 1048111600 started 07:45Z, resolved_at
# 12:10Z, before the apply at 12:16Z) and never count. ONE soak clock replaces the three age gates the first version
# had: quiet_since = max(FLOOR, the latest resolved_at of any listed exact-name production incident), and the pass
# needs NOW - quiet_since >= SOAK_S (4 h). An exact-name production incident that started before the floor and is
# still open blocks a pass (exit 2 until QUIET_STALE_S past quiet_since, then exit 5). A recurrence is permanent by design: one
# production incident at or after the floor minus slack returns exit 5 at every sweep, resolved or not, until a human closes the
# tracker by hand or deliberately re-pins (the poller #12190 is the response, not an off switch); nobody should replace the floor with a moving one. A manual resolve of a still-open
# PRE-floor incident restarts the soak instead of blocking it: accepted residual (CTO ruling 2026-11-06; the resolver is
# presumed owner-class, which is unverified, and a still-misfiring alert shows up again inside the 4 h window, as a new incident (a recurrence) or as the old one reopened
# (an open pre-floor incident), and either way blocks the pass).
#
# THE PIN IS A STORED VALUE. It is the canary alert's `created_at` (2026-11-06T12:16:03.768Z) from apply run
# 42216140017, which ran 12:14:26Z to 12:17:27Z, so the production alert's shape change landed somewhere inside that
# run and the pin may be later than the true change by up to about 1.6 minutes (the slack covers it) and earlier than it by up to
# about 83 s (an old-shape incident opening in that gap would read as a recurrence: a false exit 5, cleared by a hand close or a re-pin). It is a literal
# because the exit-0 read happens AFTER the canary alert is deleted, when no alert exists to read. A reshape of the
# production alert's evaluated query, `on_missing_data` or `query_period` that keeps `higher_than 0` is invisible to the
# shape check, so a follow-up commit measured from that apply run (the reshape PR itself cannot know the apply time) must
# re-pin APPLY_FLOOR_EPOCH by hand (a code-level detector that
# hashes the alert block beside the pin is documented in ADR-218 as a follow-up, not built). The live canary incident's
# `started_at` and the canary alert's `created_at` (while it exists) bound the pin from above at run time: a listed
# canary started or created earlier than FLOOR - SLACK_S is exit 3 (the pin sits later than the canary by more than the slack: move
# the pin back, or delete and re-create the canary; a re-created canary is later than the pin and passes). That exit 3 is raised
# AFTER the production-alert and recurrence findings (CTO ruling), so it never masks those two; it does precede the open-incident, soak and
# canary branches. While the canary still exists a forward re-pin (pin hours after the canary) trips it at every sweep, so a forward
# re-pin before the canary is retired also needs the canary re-created. Alert
# `updated_at` is vendor churn (it bumps about every five minutes with no apply) and is never read.
#
# BLIND SPOT. The incident walk stops at the page that carries the anchor, so a production incident OLDER than the
# anchor's page is invisible to it (older ones on the anchor's own page of 50 are read), whether it is still open or resolves
# after the floor. The vendor status filter that would
# close the gap is unverified, so the walk is unchanged.
#
# Incidents are matched on EXACT `.attributes.name` equality for both alerts. No startswith/test/contains: a
# canary cause that quotes the production alert name must never read as a production recurrence.
#
# VERDICT LINE (stdout, one per run; formatted only by emit_line(), printed by verdict() and, on the two no-verdict paths, by the
# mktemp-failure branch and the EXIT trap, which call emit_line directly):
#   SOLEUR_EGRESS_GW_SILENT_SOAK verdict=<v> prod_incident=<open|resolved|unknown> resolved_age_s=<n>
#     newer_prod_incident=<0|1> canary=<fired|absent|unknown> canary_alert_live=<1|0|unknown>
#     canary_declared=<0|1> prod_alert=<ok|absent|paused|shape|unknown> anchor_resolved_by=<none|actor|unknown>
#     rows_in_window=<host:n,...|na|unknown> quiet_age_s=<n|-1> pre_floor_open_prod_incident=<0|1|unknown>
#   One field per condition, so a caller can read any of them whatever the overall verdict. The first ten fields keep
#   their names and order; the last two were appended by #12189. `prod_incident`, `resolved_age_s` and
#   `anchor_resolved_by` describe the ANCHOR and are informational: `anchor_resolved_by` says only whether the anchor
#   has an ACTOR (a user or API token) in resolved_by or null (that a null means the alert recovered is inferred, not measured),
#   the identity is never printed, and no
#   verdict depends on it (OBSERVED 2026-11-06: resolved_by is "API" on 1047829421 and null on
#   1048111600, resolved_at 12:10Z). `newer_prod_incident` means a production incident other than the anchor started at or after
#   FLOOR - SLACK_S. `quiet_age_s` is NOW - quiet_since (-1 until read). `pre_floor_open_prod_incident` is 1 when an
#   exact-name production incident is open and is not counted as a recurrence. A field that was not read yet when the
#   run ended is `unknown`; resolved_age_s is -1 when the anchor is open or unread; rows_in_window is `na` when no
#   rows read was needed or reached.
#
# EXIT CONTRACT (sweep-followthroughs.sh):
#   0   PASS             verdict=pass            -> the sweeper CLOSES the tracker. Reachable only when: the production
#                                                    alert is live, unpaused and `higher_than 0`; no production incident
#                                                    started at or after FLOOR - SLACK_S (other than the anchor) and none
#                                                    is open; at least SOAK_S have passed since quiet_since; a canary
#                                                    incident exists; EVERY roster host has rows in the trailing 15
#                                                    minutes; and the canary is neither declared nor live. Exit 0 also needs
#                                                    the vendor to keep listing the canary incident after its alert is deleted
#                                                    (unverified); if it does not, the retired exit 5 below applies.
#   2   NOT YET          verdict=not_yet         -> an exact-name production incident is open (inside QUIET_STALE_S), or
#                                                    the soak has not run its 4 h, or the canary alert is too young
#   3   CANNOT ESTABLISH verdict=unknown         -> any read failure, unparseable payload, truncated list, bad env, a
#                                                    floor or canary cross-check that disagrees, or rows unreadable on
#                                                    the pass path
#   5   ACTION REQUIRED  verdict=action_required -> the sweeper comments. Any of: production alert deleted, paused or
#                                                    reverted; a production incident at or after the floor minus slack (recurrence);
#                                                    canary absent with the canary alert live (evaluator blind for this
#                                                    query shape -> heartbeat poller #12190, production alert stays armed),
#                                                    paused, or never created, or retired with its incident unreadable;
#                                                    an open production incident past QUIET_STALE_S; a roster host with
#                                                    no rows; or all verification held but the canary is still declared or
#                                                    live (delete it). The production-alert, recurrence and canary-state findings do not wait for the 4 h window; the roster-host
#                                                    and delete-the-canary findings are reached only after it, and the
#                                                    open-incident one only past QUIET_STALE_S.
#   78  xtrace refusal (#7797)
#   exit 1 is NEVER used: to the sweeper 1 is FAIL, which can reopen a human-closed tracker. An EXIT trap remaps
#   a stray 1 (and any path that exits without a verdict) to verdict=unknown / 3.
#
# WHAT THE PRODUCTION-ALERT CHECK DOES NOT READ. It reads present-once, `paused` (must be a boolean), operator and value.
# on_missing_data, query_period, the channels and the exploration SQL are pinned by the Terraform guards
# (egress-gw-alert.test.sh) and the apply, not here: their live attribute names are unverified, and a guessed name
# would turn a healthy alert into a permanent `shape` finding. That is why the pin above exists.
#
# "EARLIEST". The sweeper forwards the tracker's `earliest` as SOLEUR_FT_EARLIEST. This probe does NOT read it: it is an
# operator date later than the apply, so using it as a floor would hide post-apply incidents, and the old open-anchor
# staleness test that used it is replaced by the quiet_since clock above.
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
# host only; a failed warehouse read prints its exit code and byte length only. Every field added by #12189 is a
# number or a fixed token.
#
# Test seams (never set by the sweeper): EGRESS_GW_SILENT_BQ (betterstack-query.sh path), EGRESS_GW_SILENT_TF (the .tf),
# EGRESS_GW_SILENT_NOW_EPOCH (the clock), EGRESS_GW_SILENT_FLOOR_EPOCH (the pinned floor), EGRESS_GW_SILENT_ANCHOR_ID,
# EGRESS_GW_SILENT_ROSTER (space-separated host names), EGRESS_GW_SILENT_PAGE_CAP. `curl` is PATH-shimmed by the harness.
# Observability layer: 6 (sweeper workflow run log + the tracker issue comment the sweeper posts).
# cq-test-fixtures-synthesized-only: no live response is captured into this file.
#
# RETIREMENT: when the canary is deleted (follow-up PR, once this probe's exit 5 asks for the deletion), touch every
#   site below in the same change; the count suites flip -1 here exactly as they flipped +1 when the canary landed.
#   (1) apps/web-platform/infra/betterstack-logs-alerts.tf: delete the local egress_gw_probe_silent_canary_sql and the
#       resources logtail_exploration.egress_gw_probe_silent_canary and logtail_exploration_alert.egress_gw_probe_silent_canary
#       (alert first); this probe's canary_declared turns 0 when the alert header is gone.
#   (2) .github/workflows/apply-web-platform-infra.yml: keep BOTH canary -target lines for exactly one apply (a bare
#       -target on an address with no configuration plans its DELETE), remove them in a later PR (the #11653 then #11785
#       sequence). The deletion plan shows 2 destroyed and needs a standalone [ack-destroy] line in the merge commit.
#   (3) tests/scripts/test-infra-privileged-tier-census.sh: add the two logtail addresses to INTENDED_DESTROYS for that
#       window, remove them with the targets. VERIFIED 2026-11-05 in a scratch worktree: without the entries the structure
#       suite's apply-parity row rejects the bare logtail targets; with them it and the census pass.
#   (3b) apps/web-platform/infra/betterstack-alert-structure.test.sh: CENSUS_FLOOR_ALERTS and CENSUS_FLOOR_EXPLORATIONS 19 -> 18.
#   (4) apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh: EXPECT_BLOCKS 19 -> 18 and re-derive MIN_PASSES.
#   (5) apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh: count == 19 -> 18 and its comment list.
#   (6) apps/web-platform/test/infra/egress-gw-alert.test.sh: delete the G2b canary block and its mutation rows; re-derive
#       PRESENCE_ROWS and MUT_ROWS at BOTH write sites each; fix the exact count of egress_gw_probe_silent* resources (4 -> 2).
#   (7) every document that describes the canary: knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md
#       (the canary sections of the soleur-egress-gw-probe-silent-prd heading, including "Two limits"),
#       knowledge-base/engineering/operations/runbooks/betterstack-log-query.md (the egress bullet),
#       .github/workflows/infra-validation.yml (the comment above the egress step), the header and alert comments of
#       apps/web-platform/infra/betterstack-logs-alerts.tf, and ADR-218's canary note and its 2026-11-06 amendment (the
#       amendment records the end state). Grep the repo for `silent_canary` and `probe-silent-canary` before merging the deletion.
#   (8) This probe's own transport copies http_get / paged_get / _bearer_ok are the third inline copy of the bearer
#       GET (see send-failed-alert-probe-8097.sh and scripts/lib/bearer-curl.sh): extract them in this change.
#   (9) APPLY_FLOOR_EPOCH below: it has no outside anchor once the canary incident disappears. When the canary pair is
#       deleted, leave the pin as it is (it is the recurrence floor for the lifetime of this tracker), and re-pin it by hand in
#       a follow-up commit measured from the apply run of any change that reshapes the production alert's evaluated query,
#       `on_missing_data` or `query_period` (the reshape PR itself cannot know the apply time).
#   (10) The canary's mirror issue (#12242) closes itself when its incident leaves the open list: confirm that after the apply and
#       do NOT close it by hand (expected: a hand close files a fresh P1 at the next 15-minute run while the incident is still open;
#       the mirror dedupes on OPEN issues only). If the vendor keeps the incident open
#       after its alert is deleted, say so on tracker #12189.
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
# PIN (see "THE PIN IS A STORED VALUE" above): 2026-11-06T12:16:03Z, apply run 42216140017, canary alert created_at 12:16:03.768Z.
# Re-pin by hand in a follow-up commit measured from the apply run of any change to the production alert's evaluated query,
# on_missing_data or query_period.
APPLY_FLOOR_EPOCH=1793967363
FLOOR="${EGRESS_GW_SILENT_FLOOR_EPOCH:-$APPLY_FLOOR_EPOCH}"
ROSTER_RAW="${EGRESS_GW_SILENT_ROSTER:-soleur-web-platform soleur-web-2}"
# Operator env, but it is printed in the public verdict: keep only well-formed, de-duplicated host names. An entry outside the
# host-name shape is NOT silently dropped (a shrunken roster would then read as a complete one): it marks the roster bad, and the
# rows read on the pass path is then unknown. Globbing is off so a stray `*` cannot expand against the working directory.
ROSTER=""; ROSTER_BAD=0
set -f
for h in $ROSTER_RAW; do
  if [[ "$h" =~ ^[A-Za-z0-9._-]{1,63}$ ]]; then ROSTER+="${h}"$'\n'; else ROSTER_BAD=1; fi
done
set +f
ROSTER="$(printf '%s' "$ROSTER" | sort -u | tr '\n' ' ')"
ROSTER="${ROSTER% }"
PAGE_CAP="${EGRESS_GW_SILENT_PAGE_CAP:-50}"

PROD_NAME="soleur-egress-gw-probe-silent-prd"
CANARY_NAME="soleur-egress-gw-probe-silent-canary-prd"
CANARY_RESOURCE="egress_gw_probe_silent_canary"
EMITTER_TAG="egress-gw-probe"
SOAK_S=14400            # 4 h
QUIET_STALE_S=15300     # 4 h + 15 min grace: an open pre-floor production incident older than this past quiet_since is a finding
SLACK_S=300             # subtracted from the floor in the four lower-bound comparisons (FLOOR_LO), never from the soak clock
ROWS_WINDOW_S=900       # rows_in_window reads the trailing 15 min: the alert's own query window
CANARY_MIN_AGE_S=1200   # a canary alert younger than this has not had one evaluation cycle: not_yet, not blind
ALERTS_HOST="telemetry.betterstack.com"
INCIDENTS_HOST="uptime.betterstack.com"

# ── State for the single verdict line ────────────────────────────────────────────────────────
V_PROD=unknown; V_AGE=-1; V_NEWER=unknown; V_CANARY=unknown; V_ALIVE=unknown; V_DECL=unknown; V_ROWS=na
V_PALERT=unknown; V_RBY=unknown; V_QUIET=-1; V_PREOPEN=unknown
ROWS_OK=unknown
XCHECK_MSG=""          # a canary/pin cross-check that disagrees: raised as `unknown` after the production findings
VERDICT_DONE=0
# The ONE place the verdict line is formatted: the mktemp-failure path, verdict() and the EXIT trap all call it.
emit_line() { # <verdict>
  printf 'SOLEUR_EGRESS_GW_SILENT_SOAK verdict=%s prod_incident=%s resolved_age_s=%s newer_prod_incident=%s canary=%s canary_alert_live=%s canary_declared=%s prod_alert=%s anchor_resolved_by=%s rows_in_window=%s quiet_age_s=%s pre_floor_open_prod_incident=%s\n' \
    "$1" "$V_PROD" "$V_AGE" "$V_NEWER" "$V_CANARY" "$V_ALIVE" "$V_DECL" "$V_PALERT" "$V_RBY" "$V_ROWS" "$V_QUIET" "$V_PREOPEN"
}
# WORK is bound once, here, before any trap or helper that reads it. A failed mktemp is a verdict, never a bare status.
WORK="$(mktemp -d -t egs-probe.XXXXXXXX)" || {
  printf 'TRANSIENT: mktemp failed\n' >&2
  emit_line unknown
  exit 3
}

# THE chokepoint: the only place the contract exit codes are chosen (the line itself is formatted by emit_line, which the
# mktemp-failure path and the EXIT trap also call). <verdict> <exit>
verdict() {
  local word="$1" code="$2"
  # The pairing is part of the contract: exit 0 is reserved for `pass` and `pass` is exit 0 only. A call site that edits one
  # half (an `action_required 0`) would CLOSE the tracker over a finding, so the pairing is refused rather than trusted.
  if [[ "$word" == pass && "$code" != 0 ]] || [[ "$word" != pass && "$code" == 0 ]]; then
    transient "internal: verdict ${word} paired with exit ${code}; refused"
    word=unknown; code=3
  fi
  VERDICT_DONE=1
  emit_line "$word"
  exit "$code"
}
transient() { printf 'TRANSIENT: %s\n' "$1" >&2; }
action() { printf 'ACTION REQUIRED: %s\n' "$1" >&2; }

# Any path that reaches here without a verdict (an unbound variable, a failed builtin) is unknown, never a bare
# status; a stray exit 1 is remapped, because to the sweeper 1 is FAIL.
_on_exit() {
  local rc=$?
  rm -rf "$WORK" 2>/dev/null
  if [[ "$VERDICT_DONE" != 1 ]]; then
    VERDICT_DONE=1
    transient "the probe ended without a verdict (status ${rc})"
    emit_line unknown
    exit 3
  fi
  # Defensive: unreachable while verdict() is never given 1 (a stray exit 1 BEFORE a verdict takes the branch above).
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
[[ "$NOW" =~ ^[0-9]{1,12}$ ]] || unknown "the clock is not a plausible epoch"
NOW=$((10#$NOW))
# The floor is canonicalised (a leading zero would be octal in $(( )) and breaks --argjson) and digit-capped.
[[ "$FLOOR" =~ ^[0-9]{1,12}$ ]] || unknown "the apply floor is not an epoch"
FLOOR=$((10#$FLOOR))
[[ "$FLOOR" -le "$NOW" ]] || unknown "the apply floor lies after the clock: the pin or the clock is wrong"
FLOOR_LO=$((FLOOR - SLACK_S))
[[ -f "$TF" ]] || unknown "betterstack-logs-alerts.tf not found at ${TF}"
command -v jq >/dev/null 2>&1 || unknown "jq is not available"

# ── HTTP ─────────────────────────────────────────────────────────────────────────────────────
# One GET with the bearer on curl's STDIN config channel (never argv: #7797). Returns 0 or non-zero with ONE reason
# line on stderr that carries the HTTP status and byte length only — never the body, never a credential.
http_get() { # <url> <outfile>
  local url="$1" body="$2" code rc=0 bytes
  : > "$WORK/${body##*/}"
  # -g: no URL globbing; --max-redirs 0 for explicitness; --proto =https pins the scheme.
  code="$(curl --disable --noproxy '*' -g -sS -m 20 --proto '=https' --max-redirs 0 -o "$body" -w '%{http_code}' \
    -H 'Accept: application/json' --config - "$url" \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$BETTERSTACK_API_TOKEN") 2>/dev/null)" || rc=$?
  bytes="$(wc -c < "$body" 2>/dev/null || echo 0)"; bytes="${bytes//[[:space:]]/}"
  # The error lines name the HOST only: a pagination.next path is vendor-controlled text that this stdout publishes.
  local h="${url#https://}"; h="${h%%/*}"
  if [[ "$rc" -ne 0 ]]; then printf 'curl exited %s on GET https://%s (bytes=%s)\n' "$rc" "$h" "$bytes" >&2; return 1; fi
  case "$code" in 2*) ;; *) printf 'HTTP %s on GET https://%s (bytes=%s)\n' "$code" "$h" "$bytes" >&2; return 1 ;; esac
  return 0
}

# Paged GET of a `.data` list with an exact host pin on pagination.next (the token never leaves the host). Prints the
# concatenated `.data[]` objects as a JSON array. With a stop epoch the walk ends at the first page whose OLDEST
# started_at is <= it (the endpoint is newest-first, so everything after that page is older than the anchor).
paged_get() { # <host> <path> [stop-epoch]
  local host="$1" url="https://$1$2" stop="${3:-}" page=0 body="$WORK/page.json" oldest bad_host
  : > "$WORK/pages.ndjson"
  while [[ -n "$url" ]]; do
    page=$((page + 1))
    if [[ "$page" -gt "$PAGE_CAP" ]]; then printf 'pagination exceeded %s pages on %s\n' "$PAGE_CAP" "$host" >&2; return 1; fi
    case "$url" in
      "https://${host}/"*) ;;
      *)
        bad_host="$(printf '%s' "$url" | sed -E 's#^[a-zA-Z]+://([^/?@]*@)?([^/?\#]*).*#\2#')"
        [[ "$bad_host" =~ ^[a-z0-9.-]{1,253}$ ]] || bad_host='<redacted>'
        printf 'refusing off-host pagination.next (host=%s)\n' "$bad_host" >&2; return 1 ;;
    esac
    http_get "$url" "$body" || return 1
    if ! jq -e '.data | type == "array"' "$body" >/dev/null 2>&1; then
      printf 'no data array in GET https://%s (bytes=%s)\n' "$host" "$(wc -c < "$body" | tr -d '[:space:]')" >&2; return 1
    fi
    jq -c '.data[]' "$body" >> "$WORK/pages.ndjson"
    if [[ -n "$stop" ]]; then
      oldest="$(jq -r '[.data[] | .attributes.started_at // empty | (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch empty)] | min // empty' "$body" 2>/dev/null)"
      if [[ "$oldest" =~ ^[0-9]+$ ]] && [[ "$oldest" -le "$stop" ]]; then break; fi
    fi
    # A malformed `pagination` (a string, an array) must not read as "end of list": that would truncate the walk silently.
    url="$(jq -r 'if (.pagination | type) == "object" then (if (.pagination.next | type) == "string" then .pagination.next elif .pagination.next == null then empty else error("next") end) elif .pagination == null then empty else error("pagination") end' "$body" 2>/dev/null)" \
      || { printf 'unreadable pagination in GET https://%s (bytes=%s)\n' "$host" "$(wc -c < "$body" | tr -d '[:space:]')" >&2; return 1; }
  done
  jq -s '.' "$WORK/pages.ndjson"
}

# ── (1) The anchor incident ──────────────────────────────────────────────────────────────────
http_get "https://${INCIDENTS_HOST}/api/v2/incidents/${ANCHOR_ID}" "$WORK/single.json" 2>"$WORK/err" \
  || unknown "anchor incident read did not answer: $(tr '\n' ' ' < "$WORK/err")"
if ! anchor="$(jq -c '
  def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
  .data | select(type == "object")
  | {id: (.id|tostring), name: .attributes.name, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at,
     by_actor: (if (.attributes | has("resolved_by")) then (.attributes.resolved_by != null) else null end)}
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
[[ "$A_EPOCH" -le "$FLOOR" ]] || unknown "the apply floor lies before the anchor's start: the pin or the anchor is wrong"
if [[ -z "$A_RES_EPOCH" ]]; then
  V_PROD=open; V_AGE=-1
else
  [[ "$A_RES_EPOCH" =~ ^[0-9]+$ ]] || unknown "anchor resolved_at is not a time"
  V_PROD=resolved; V_AGE=$((NOW - A_RES_EPOCH))
  # Whether an ACTOR resolved it (never who). INFORMATIONAL ONLY: no verdict depends on it. OBSERVED 2026-11-06:
  # `resolved_by` is "API" on this anchor (resolved through the API) and null on incident 1048111600 (resolved_at 12:10Z; the null reading is inferred, not measured).
  # A response without the key is `unknown`.
  case "$(printf '%s' "$anchor" | jq -r '.by_actor')" in
    true) V_RBY=actor ;;
    false) V_RBY=none ;;
    *) V_RBY=unknown ;;
  esac
fi

# ── (2) The incident list, walked back to the anchor ─────────────────────────────────────────
paged_get "$INCIDENTS_HOST" "/api/v2/incidents?per_page=50" "$A_EPOCH" > "$WORK/incidents.json" 2>"$WORK/err" \
  || unknown "incident list did not answer: $(tr '\n' ' ' < "$WORK/err")"
# PROJECTED, never raw: the raw objects carry acknowledged_by / resolved_by / screenshot URLs and this stdout lands in a
# public issue comment. An unparseable started_at is a transport fault (exit 3), never a verdict; so is an unparseable
# resolved_at on a production incident (it must never be read as "still open").
if ! projected="$(jq -c --arg p "$PROD_NAME" --arg c "$CANARY_NAME" '
  def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
  [.[] | {id: (.id|tostring), name: .attributes.name, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at,
          is_prod: (.attributes.name == $p), is_canary: (.attributes.name == $c)}
       | . + {epoch: (.started_at | (try ep catch null)),
              resolved_epoch: (if .resolved_at == null then null else (.resolved_at | (try ep catch null)) end)}]
  | if any(.[]; .epoch == null or (([.id | match("\\A[0-9]+\\z")] | length) == 0) or (.is_prod and .resolved_at != null and .resolved_epoch == null))
    then error("unparseable started_at, id or resolved_at") else . end' "$WORK/incidents.json" 2>/dev/null)"; then
  unknown "incident list unparseable (bytes=$(wc -c < "$WORK/incidents.json" | tr -d '[:space:]'))"
fi
# The anchor MUST be on the list we walked: its absence means the list is truncated, stale or a different view than the
# single read, and every conclusion drawn from it (no recurrence, no canary) would be drawn from nothing.
if [[ "$(printf '%s' "$projected" | jq --arg id "$ANCHOR_ID" '[.[] | select(.id == $id)] | length')" != "1" ]]; then
  unknown "the walked incident list does not carry the anchor ${ANCHOR_ID} exactly once: the list is truncated or inconsistent"
fi
# ...and the listed anchor must AGREE with the single read on name and start: two views of one incident that disagree
# are an inconsistent API answer, not a basis for a verdict.
if [[ "$(printf '%s' "$projected" | jq -r --arg id "$ANCHOR_ID" --arg n "$PROD_NAME" --argjson a "$A_EPOCH" \
      '[.[] | select(.id == $id and .name == $n and .epoch == $a)] | length')" != "1" ]]; then
  unknown "the listed anchor ${ANCHOR_ID} disagrees with the single read on name or start time: inconsistent API answer"
fi
# ...and on whether it is resolved: the verdict ladder reads the open set from the list and the anchor's state from the single
# read, so a disagreement would feed it an inconsistent anchor.
list_open="$(printf '%s' "$projected" | jq -r --arg id "$ANCHOR_ID" '[.[] | select(.id == $id)][0] | (.resolved_epoch == null)' 2>/dev/null)"
single_open=false; [[ -z "$A_RES_EPOCH" ]] && single_open=true
[[ "$list_open" == true || "$list_open" == false ]] || unknown "the listed anchor's resolved state is unreadable"
[[ "$list_open" == "$single_open" ]] || unknown "the listed anchor ${ANCHOR_ID} disagrees with the single read on whether it is resolved: inconsistent API answer"

# Exact-equality matches (is_prod / is_canary are `.attributes.name ==` booleans computed above; never a prefix,
# substring or cause match). Every count and epoch below is shape-checked: a jq failure inside `$( )` reads as an empty
# string, and an empty count must never read as zero.
newer="$(printf '%s' "$projected" | jq -c --arg id "$ANCHOR_ID" --argjson lo "$FLOOR_LO" \
  '[.[] | select(.is_prod and .id != $id and .epoch >= $lo)] | sort_by(.epoch)' 2>/dev/null)"
n_newer="$(printf '%s' "$newer" | jq 'length' 2>/dev/null)"
[[ "$n_newer" =~ ^[0-9]+$ ]] || unknown "the recurrence set is unreadable"
canary_inc="$(printf '%s' "$projected" | jq -c '[.[] | select(.is_canary)] | sort_by(.epoch)' 2>/dev/null)"
n_canary_inc="$(printf '%s' "$canary_inc" | jq 'length' 2>/dev/null)"
[[ "$n_canary_inc" =~ ^[0-9]+$ ]] || unknown "the canary incident set is unreadable"
if [[ "$n_newer" -gt 0 ]]; then V_NEWER=1; else V_NEWER=0; fi
CANARY_EPOCH=""
if [[ "$n_canary_inc" -gt 0 ]]; then
  V_CANARY=fired; CANARY_EPOCH="$(printf '%s' "$canary_inc" | jq -r '.[0].epoch' 2>/dev/null)"
  [[ "$CANARY_EPOCH" =~ ^[0-9]+$ ]] || unknown "the canary incident's start is not a time"
  # The canary incident bounds the pin from above: a canary that started earlier than the floor minus slack means the pin sits
  # later than the canary by more than the slack. Recorded here and raised as `unknown` after the production findings.
  [[ "$CANARY_EPOCH" -ge "$FLOOR_LO" ]] || XCHECK_MSG="a listed canary incident started earlier than the apply floor minus slack: the pin sits later than the canary by more than the slack; move APPLY_FLOOR_EPOCH back, or delete and re-create the canary"
else
  V_CANARY=absent
fi
# The open pre-floor set: exact-name production incidents with no resolve that are not counted as a recurrence (the anchor
# included, whatever its start). The soak origin (quiet_since): the later of the floor and the latest resolve of any listed production incident.
PRE_OPEN="$(printf '%s' "$projected" | jq -r --arg id "$ANCHOR_ID" --argjson lo "$FLOOR_LO" \
  '[.[] | select(.is_prod and .resolved_epoch == null and (.id == $id or .epoch < $lo))] | length' 2>/dev/null)"
[[ "$PRE_OPEN" =~ ^[0-9]+$ ]] || unknown "the open pre-floor incident set is unreadable"
if [[ "$PRE_OPEN" -gt 0 ]]; then V_PREOPEN=1; else V_PREOPEN=0; fi
QUIET_SINCE="$(printf '%s' "$projected" | jq -r --argjson fl "$FLOOR" \
  '([.[] | select(.is_prod and .resolved_epoch != null) | .resolved_epoch] + [$fl]) | max' 2>/dev/null)"
[[ "$QUIET_SINCE" =~ ^[0-9]+$ ]] || unknown "the soak origin (quiet_since) is unreadable"
[[ "$QUIET_SINCE" -le "$NOW" ]] || unknown "a production incident is recorded as resolved after the clock: the clock or the list is wrong"
V_QUIET=$((NOW - QUIET_SINCE))

# ── (3) The live alert listing ───────────────────────────────────────────────────────────────
paged_get "$ALERTS_HOST" "/api/v2/alerts" > "$WORK/alerts.json" 2>"$WORK/err" \
  || unknown "alert listing did not answer: $(tr '\n' ' ' < "$WORK/err")"
if ! alerts_proj="$(jq -c --arg p "$PROD_NAME" --arg c "$CANARY_NAME" '
  def ep: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
  def pick($n): [.[] | select(.attributes.name == $n)
        | {paused: (.attributes.paused), operator: .attributes.operator, value: .attributes.value,
           created_epoch: (.attributes.created_at | (try ep catch null))}];
  {prod: pick($p), canary: pick($c)}' "$WORK/alerts.json" 2>/dev/null)"; then
  unknown "alert listing unparseable (bytes=$(wc -c < "$WORK/alerts.json" | tr -d '[:space:]'))"
fi
live="$(printf '%s' "$alerts_proj" | jq -r '.canary | length')"
[[ "$live" =~ ^[0-9]+$ ]] || unknown "alert listing unparseable (canary count)"
[[ "$live" -le 1 ]] || unknown "alert listing carries ${CANARY_NAME} more than once: inconsistent API answer"
if [[ "$live" -gt 0 ]]; then V_ALIVE=1; else V_ALIVE=0; fi
# `paused` must be a BOOLEAN on every alert we read: a missing, null or renamed key would otherwise read as "not paused".
if [[ "$(printf '%s' "$alerts_proj" | jq -r '[.prod[], .canary[] | .paused | type == "boolean"] | all')" != true ]]; then
  unknown "alert listing carries no boolean paused flag for ${PROD_NAME} or the canary: the schema is not what this probe reads"
fi
CANARY_PAUSED="$(printf '%s' "$alerts_proj" | jq -r '[.canary[] | .paused] | any')"
CANARY_CREATED="$(printf '%s' "$alerts_proj" | jq -r '[.canary[] | .created_epoch | select(. != null)] | min // empty')"
if [[ "$live" -gt 0 ]]; then
  # A listed canary alert must carry a parseable creation time at or after the floor minus slack: otherwise the pin is
  # later than the canary, or the canary is not the one the pin was measured on.
  if ! [[ "$CANARY_CREATED" =~ ^[0-9]+$ ]]; then
    XCHECK_MSG="the listed canary alert carries no parseable created_at: the pin cannot be cross-checked"
  elif [[ "$CANARY_CREATED" -lt "$FLOOR_LO" ]]; then
    XCHECK_MSG="the listed canary alert was created earlier than the apply floor minus slack: the pin sits later than the canary by more than the slack; move APPLY_FLOOR_EPOCH back, or delete and re-create the canary"
  fi
fi
# The production alert must be in the listing exactly once, unpaused and in the inverted shape. A listing that does
# not carry it is not evidence of a healthy alert: deleted, or an incomplete answer; either needs a human.
case "$(printf '%s' "$alerts_proj" | jq -r '.prod | length')" in
  1)
    if [[ "$(printf '%s' "$alerts_proj" | jq -r '.prod[0].paused')" == true ]]; then V_PALERT=paused
    elif [[ "$(printf '%s' "$alerts_proj" | jq -r '.prod[0] | (.operator == "higher_than" and .value == 0)')" != true ]]; then V_PALERT=shape
    else V_PALERT=ok; fi ;;
  0) V_PALERT=absent ;;
  *) unknown "alert listing carries ${PROD_NAME} more than once: inconsistent API answer" ;;
esac

# ── (4) Is the canary still declared? (comment lines dropped first) ──────────────────────────
[[ -r "$TF" ]] || unknown "betterstack-logs-alerts.tf is not readable at ${TF}"
tf_stripped="$(grep -vE '^[[:space:]]*(#|//)' "$TF")"
# The file must be the one that declares the PRODUCTION alert: an empty or unrelated file would otherwise read as "canary retired".
grep -qE '^[[:space:]]*resource[[:space:]]+"logtail_exploration_alert"[[:space:]]+"egress_gw_probe_silent"[[:space:]]*\{' <<<"$tf_stripped" \
  || unknown "betterstack-logs-alerts.tf does not declare the production alert resource: the canary declaration cannot be read from it"
V_DECL=0
# Any of the three pieces keeps the canary declared: a half-deleted canary (alert gone, exploration or SQL local left)
# must not read as retired. A block comment reads as declared: a safe deadlock, not a false pass.
for decl in "resource[[:space:]]+\"logtail_exploration_alert\"[[:space:]]+\"${CANARY_RESOURCE}\"[[:space:]]*\{" \
            "resource[[:space:]]+\"logtail_exploration\"[[:space:]]+\"${CANARY_RESOURCE}\"[[:space:]]*\{" \
            "${CANARY_RESOURCE}_sql[[:space:]]*="; do
  if grep -qE "^[[:space:]]*${decl}" <<<"$tf_stripped"; then V_DECL=1; break; fi
done

# ── (5) rows_in_window ───────────────────────────────────────────────────────────────────────
# The trailing 15 minutes (the alert's own query window), NOT the incident's whole life: rows from before a host died
# would otherwise read as both hosts emitting now. A FUNCTION called in the main shell (never inside `$( )`, where an
# exit would only leave the subshell); it sets V_ROWS and ROWS_OK (1 only when every roster host has n > 0, computed in
# the same jq that builds the field, and never for an empty roster).
read_rows() {
  V_ROWS=unknown; ROWS_OK=unknown
  local w_start d_start d_end WINDOW UNION sql bq_rc bq_out answered line rows ok_tok field
  w_start=$((NOW - ROWS_WINDOW_S))
  if [[ -z "$ROSTER" || "$ROSTER_BAD" == 1 ]]; then
    transient "rows_in_window skipped: the roster is empty or carries an entry outside the host-name shape, so no host set can be proven emitting; rows_in_window is unknown"
    return 0
  fi
  if [[ -f "$BQ" ]] && [[ -n "${BETTERSTACK_QUERY_HOST:-}" && -n "${BETTERSTACK_QUERY_USERNAME:-}" && -n "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
    d_start="$(date -u -d "@${w_start}" '+%Y-%m-%d %H:%M:%S')"; d_end="$(date -u -d "@${NOW}" '+%Y-%m-%d %H:%M:%S')"
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
      # Host names come from log rows, so they are untrusted text that this stdout publishes: anything outside a plain
      # hostname shape is folded into `other` and the list is capped.
      # \A...\z, never ^...$: Oniguruma's $ matches before a trailing newline, which would split the verdict line.
      # Roster hosts come first, at most 10 other hosts follow, and everything else is folded into `other`.
      if rows="$(printf '%s\n' "$bq_out" | jq -r -s --arg roster "$ROSTER" '
          ($roster | split(" ") | map(select(length > 0)) | sort) as $ro
          | ([.[] | {host: ((.host // "") | if ([match("\\A[A-Za-z0-9._-]{1,63}\\z")] | length) > 0 then . else "other" end), n: ((.n // 0) | tonumber | if . < 0 then 0 else . end)}]) as $r0
          | ([$r0[].host] | unique | map(select(. != "other" and (. as $h | $ro | any(. == $h) | not)))) as $extra
          | ($extra[:10]) as $keep
          | ($r0 | map(.host as $h | if $h != "other" and ($ro | any(. == $h) | not) and ($keep | any(. == $h) | not) then .host = "other" else . end)) as $r
          | ($ro + $keep + (if any($r[]; .host == "other") then ["other"] else [] end)) as $hosts
          | ($ro | length > 0 and all(.[]; . as $h | (([$r[] | select(.host == $h) | .n] | add) // 0) > 0)) as $ok
          | ($hosts | map(. as $h | "\($h):\(([$r[] | select(.host == $h) | .n] | add) // 0)") | join(",")) as $f
          | "\($ok) \($f)"' 2>/dev/null)" && [[ -n "$rows" ]]; then
        ok_tok="${rows%% *}"; field="${rows#* }"
        if [[ ( "$ok_tok" == true || "$ok_tok" == false ) && -n "$field" && "$field" != "$rows" ]]; then
          V_ROWS="$field"
          if [[ "$ok_tok" == true ]]; then ROWS_OK=1; else ROWS_OK=0; fi
        fi
      fi
    fi
  else
    transient "rows_in_window skipped: warehouse credentials (BETTERSTACK_QUERY_*) or ${BQ##*/} not available; rows_in_window is unknown"
  fi
}
# Diagnostic read: only when something needs the host picture (an open pre-floor incident or a recurrence).
if [[ "$PRE_OPEN" -gt 0 || "$V_NEWER" == 1 ]]; then read_rows; fi

# ── Verdict ──────────────────────────────────────────────────────────────────────────────────
# Built from VALIDATED values (a numeric id and canonical timestamps re-rendered from the parsed epochs), never from the
# raw vendor strings: fromdateiso8601 accepts trailing text, and this stdout is a public comment.
proj_newer="$(printf '%s' "$newer" | jq -c '[.[] | {id, name, started_at: (.epoch | todate), resolved_at: (if .resolved_epoch == null then null else (.resolved_epoch | todate) end)}]')"
# The production alert's own state comes first: every other conclusion assumes it is the thing being soaked.
case "$V_PALERT" in
  absent)
    action "${PROD_NAME} is not in the live alert listing: it was deleted or the listing is incomplete. Without it nothing pages on a silent host; restore it (apply) before reading anything else here."
    verdict action_required 5 ;;
  paused)
    action "${PROD_NAME} is PAUSED in the live listing: the page is off. A pause is a Better Stack write that needs the owner's per-command go-ahead; do not leave it paused while the evaluator question is open."
    verdict action_required 5 ;;
  shape)
    action "${PROD_NAME} is live but is not 'higher_than 0' (operator/value differ): the inverted shape is not what is running (the apply has not landed, or it was reverted). A revert restores the shape that misfired."
    verdict action_required 5 ;;
esac
if [[ "$V_NEWER" == 1 ]]; then
  action "a ${PROD_NAME} incident started at or after the apply floor minus ${SLACK_S} s (recurrence; projected): ${proj_newer}. rows_in_window=${V_ROWS} (the trailing 15 minutes) separates an evaluator fault (rows on both hosts now) from an emitter or ingest fault (a host with none). Response: the poller (#12190); any Better Stack write needs the owner's per-command go-ahead; never a revert."
  verdict action_required 5
fi
# A canary/pin disagreement qualifies only the canary evidence, so it is raised after the findings about production above.
[[ -z "$XCHECK_MSG" ]] || unknown "$XCHECK_MSG"
if [[ "$V_CANARY" == absent && "$V_ALIVE" == 1 ]]; then
  if [[ "$CANARY_PAUSED" == true ]]; then
    action "the canary alert ${CANARY_NAME} is live but PAUSED, so no canary incident can exist. This is not an evaluator finding: unpause it (a Better Stack write needing the owner's per-command go-ahead) or let the apply re-arm it."
    verdict action_required 5
  fi
  if [[ "$CANARY_CREATED" =~ ^[0-9]+$ ]] && [[ $((NOW - CANARY_CREATED)) -lt "$CANARY_MIN_AGE_S" ]]; then
    transient "the canary alert was created $((NOW - CANARY_CREATED))s ago; it needs ${CANARY_MIN_AGE_S}s for one evaluation cycle before its absence means anything"
    verdict not_yet 2
  fi
  action "no canary incident exists although the canary alert ${CANARY_NAME} is live: the evaluator is blind for this query shape (an inference; the query itself is proven). Build the heartbeat poller (#12190) now, leave the production alert ARMED, and do not read a green production alert as healthy until the canary has fired. Anchor incident ${ANCHOR_ID}: ${V_PROD}."
  verdict action_required 5
fi
if [[ "$V_CANARY" == absent && "$V_DECL" == 1 ]]; then
  action "no canary incident exists and ${CANARY_NAME} is not in the live alert listing but is still declared: it was DELETED or NEVER CREATED (the apply has not run yet, an alert-count cap refusal or a failed create; or the vendor drops the incident with its alert). Check the merge run's Terraform apply step for logtail_exploration_alert.${CANARY_RESOURCE}; this is not an evaluator finding."
  verdict action_required 5
fi
if [[ "$V_CANARY" == absent ]]; then
  action "the canary is retired (its alert is gone from the live listing and from the declaration) and no canary incident is listed any more, so canary=fired cannot be re-read here. If an earlier sweep comment on this tracker already read canary=fired, close the tracker by hand citing that comment and remove its follow-through label so the sweeper stops scanning it. Do not build the heartbeat poller on this evidence: whether the vendor keeps a canary incident after its alert is deleted is unverified."
  verdict action_required 5
fi
if [[ "$PRE_OPEN" -gt 0 ]]; then
  if [[ "$V_QUIET" -gt "$QUIET_STALE_S" ]]; then
    action "an open ${PROD_NAME} incident that started before the apply is still open ${V_QUIET}s after quiet_since (more than 4 h + 15 min): the inverted shape did not clear it. rows_in_window=${V_ROWS} (the trailing 15 minutes; rows on both hosts means an empty-window read or a vendor that never auto-resolves; a host with none is real silence). Response: the poller (#12190); close this tracker in favor of #12190 with its follow-through label removed; a manual resolve is a Better Stack write needing the owner's per-command go-ahead."
    verdict action_required 5
  fi
  transient "an open ${PROD_NAME} incident that started before the apply is still open (inside the horizon): quiet_since is ${V_QUIET}s ago; rows_in_window=${V_ROWS}"
  verdict not_yet 2
fi
if [[ "$V_QUIET" -lt "$SOAK_S" ]]; then
  transient "no ${PROD_NAME} incident since the apply or the latest resolve ${V_QUIET}s ago; the soak needs ${SOAK_S}s"
  verdict not_yet 2
fi
# The pass path proves BOTH roster hosts are emitting now: a green production alert over a silent host is exactly the
# evaluator fault the canary cannot rule out. Unreadable is unknown (3); a roster host with no rows is a finding (5).
# (Both diagnostic triggers exit above, so this is the only read on the pass path.)
read_rows
if [[ "$ROWS_OK" == unknown ]]; then
  unknown "the pass path needs rows from the trailing 15 minutes on every roster host and the read did not establish them (rows_in_window=${V_ROWS})"
fi
if [[ "$ROWS_OK" != 1 ]]; then
  action "a roster host has no rows in the trailing 15 minutes although the production alert is green and the soak held: rows_in_window=${V_ROWS}. A host that emits nothing is the silence this alert exists to catch; the tracker stays open until every roster host emits. Response: the poller (#12190); any Better Stack write needs the owner's per-command go-ahead."
  verdict action_required 5
fi
if [[ "$V_DECL" == 1 || "$V_ALIVE" == 1 ]]; then
  action "all verification held (no ${PROD_NAME} incident at or after the apply for >= 4 h, rows on every roster host, canary incident seen) but the canary is still declared in betterstack-logs-alerts.tf or still live in the alert listing: delete the canary (its incident, P1 mirror issue and email should not outlive their job; the deletion needs the owner's per-command go-ahead and the standalone [ack-destroy] line). The RETIREMENT: header of this script lists every site to touch."
  verdict action_required 5
fi
# Defense in depth: the ladder above tests the BAD value of each member, so assert the conjunction of the GOOD values here, where a
# state the ladder did not model (an unset member, a new enum value) lands on unknown instead of on the pass.
if [[ "$V_PALERT" != ok || "$V_NEWER" != 0 || "$V_CANARY" != fired || "$V_ALIVE" != 0 || "$V_DECL" != 0 ||
      "$PRE_OPEN" != 0 || "$ROWS_OK" != 1 || "$V_QUIET" -lt "$SOAK_S" || -n "$XCHECK_MSG" || "$ROSTER_BAD" != 0 ]]; then
  unknown "the pass preconditions were not all established (internal inconsistency); no pass is granted"
fi
verdict pass 0
