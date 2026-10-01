#!/usr/bin/env bash
# Follow-through verification: #8562 — the dedicated inngest host provisions through the latched,
# retrying soleur-inngest-provision.service (ADR-257), and a host life that armed the unit reached
# bootstrap-done. Twin of inngest-private-nic-8539.sh (same host, same channel, same delivery path).
#
# WHY THIS EXISTS. #8562 is delivered DARK: merging re-renders hcloud_server.inngest's user_data,
# and that reaches the host only through an operator-dispatched `apply_target=inngest-host-replace`
# plus a human-approved `cutover-inngest.yml -f op=resume`. ADR-257 stays `adopting` until this
# probe reads PASS on the first host life born from the new template.
#
# ANCHOR: HOST LIFE, NOT NEWEST BOOT. A latched host that reboots emits no provision-attempt-start
# (the unit's ConditionPathExists skips it), and the phone-home carries no boot id, so a newest-boot
# grouping would read "not started" forever on a healthy host. Instead the probe takes the NEWEST
# `provision-unit-armed` row — emitted once per host life, from runcmd — and its `iid=` (the
# cloud-init instance-id). Old and new hosts share the hostname during a replace, so every other
# row is joined on that iid: a late bootstrap-done from a destroyed host can never read as the new
# host's.
#
# VERDICTS. Exactly ONE `verdict=…` line goes to STDOUT; every detail line goes to stderr. (The 8539
# twin prints its verdicts to stderr; preflight Check 10 matches stdout only.)
#   verdict=PASS                               exit 0  a bootstrap-done carries the armed row's iid
#   verdict=FAIL reason=degraded cause=…       exit 1  the only completions for that iid are
#                                                      bootstrap-done-DEGRADED (served SQLite-only,
#                                                      no latch): never a PASS
#   verdict=FAIL reason=never-started cause=…  exit 1  armed > 10 min ago, no provision-attempt-start
#                                                      for that iid
#   verdict=FAIL reason=no-bootstrap-done cause=…
#                                              exit 1  attempts for that iid, none reached
#                                                      bootstrap-done, first attempt > 2 h ago
#   Every FAIL carries cause=<per-iid counts> of isolation-check-FAILED, inngest_pull_fatal,
#   provision-fsm-busy and bootstrap-done-DEGRADED, so the verdict line alone names the next read.
#   verdict=TRANSIENT reason=not-delivered     exit 2  no provision-unit-armed row in the window:
#                                                      the new template has not reached a host yet
#   verdict=TRANSIENT reason=in-progress       exit 2  armed, and still inside the 10 min / 2 h
#                                                      bounds above — no verdict yet
#   verdict=TRANSIENT reason=probe-fault       exit 3  the question could not be asked: missing
#                                                      credentials, a failed query, or an armed row
#                                                      whose iid is absent, `unknown`, or the
#                                                      hostname (the fallback old and new hosts
#                                                      SHARE, so it cannot tell host lives apart).
#                                                      A DISTINCT token, so a bad credential can
#                                                      never match "not-delivered".
#
# KNOWN GAP: a host whose runcmd never reaches the arming items (an earlier item hangs, or
# cloud-init fails before runcmd) emits no provision-unit-armed row, and this probe reads it as
# TRANSIENT not-delivered — indistinguishable from "no replace has run yet". Only the host's
# earlier boot stages (runcmd-entered and the stage that stopped) show it.
#   exit 78                                            refused to run under xtrace with a live
#                                                      credential set (#7797)
#
# Output is COUNTS and the iid only. The sweeper posts stdout+stderr to a public issue, and the
# rows' detail= fields carry redacted log tails; no row detail is ever printed here.
#
# FIELD ISOLATION, not substring matching (same reasoning as inngest-zot-boot-7462.sh and the 8539
# twin): `--grep` is an unanchored LIKE over a source every host multiplexes into, so every
# judgement is made on the DECODED object's .marker / .host / .stage / .detail fields. `-R` plus
# `fromjson?` at both levels, so one malformed line drops only itself. The stage is compared as a
# WHOLE field: a stage value that is not a single token (e.g. "bootstrap-done 900000001") is
# dropped, and decoded rows are TAB-separated, so no value can shift into another column.
#
# THE `${VAR:?msg}` FORM IS BANNED HERE (scripts/lint-followthrough-varq-ban.sh): under the
# sweeper's shell it aborts with status 1, which this contract reads as FAIL.
#
# Required env (literal names; already wired into scheduled-followthrough-sweeper.yml, so no
# workflow edit): BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD.
# Credentials are never read here; they are consumed by scripts/betterstack-query.sh, which owns
# the only curl call (with its TLS-env and proxy confinement).
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${INNGEST_PROVISION_8562_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"

MARKER="SOLEUR_INNGEST_BOOT_STAGE"
# The Better Stack row's host field is the hostname (hcloud_server.inngest's name). Sentry's
# host_name tag carries the same value; web-1 reports as soleur-inngest-prd and never matches.
HOST="soleur-inngest"
WINDOW="${INNGEST_PROVISION_8562_WINDOW:-30d}"
LIMIT="${INNGEST_PROVISION_8562_LIMIT:-5000}"
START_BOUND_S=600    # armed -> first provision-attempt-start
DONE_BOUND_S=7200    # first attempt -> bootstrap-done

verdict() { printf 'verdict=%s\n' "$1"; }

probe_fault() {
  verdict "TRANSIENT reason=probe-fault"
  printf '  %s\n' "$@" >&2
  exit 3
}

now="${INNGEST_PROVISION_8562_NOW:-$(date -u +%s)}"
[[ "$now" =~ ^[0-9]+$ ]] || probe_fault "could not read the current time (got '${now}')."

missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then
  probe_fault "credentials unprovisioned — missing:${missing}." \
    "Nothing about the host was measured. Confirm the directive's secrets= clause lists all three."
fi

[[ -x "$QUERY" ]] || probe_fault "query helper not found or not executable at ${QUERY}."

# decode <rows> -> "<epoch>\t<stage>\t<iid|->" per matching row, oldest first.
# The inner .dt is the host's own ISO-8601 UTC stamp; the outer warehouse dt is the fallback.
decode() {
  printf '%s\n' "$1" | jq -R -r --arg m "$MARKER" --arg h "$HOST" '
    fromjson? | select(type == "object") | . as $o
    | (.raw? | fromjson?) | select(type == "object")
    | select(.marker == $m and .host == $h and (.stage | type) == "string")
    | select(.stage | test("^[A-Za-z0-9_.-]+$"))
    | ((.detail // "") | tostring) as $d
    | ([$d | capture("(^|\\s)iid=(?<iid>[A-Za-z0-9._-]+)") | .iid][0] // "-") as $iid
    | (((.dt // "") | tostring | fromdateiso8601?)
       // (($o.dt // "") | tostring | sub("\\.[0-9]+$"; "") | sub(" "; "T") | (. + "Z") | fromdateiso8601?)
       // empty) as $ts
    | "\($ts | floor)\t\(.stage)\t\($iid)"' 2>/dev/null | sort -n
}

# --- 1. the anchor: the newest provision-unit-armed row --------------------------------------------
armed_rows="$("$QUERY" --since "$WINDOW" --grep provision-unit-armed --limit "$LIMIT" 2>/dev/null)"
qrc=$?
[[ "$qrc" -eq 0 ]] || probe_fault "the Better Stack query for provision-unit-armed failed (rc=${qrc})." \
  "A revoked connection password and a network fault both land here; neither is a statement about the host."

armed="$(decode "$armed_rows" | awk -F'\t' '$2 == "provision-unit-armed"' | tail -n 1)"
if [[ -z "$armed" ]]; then
  verdict "TRANSIENT reason=not-delivered"
  {
    echo "  No provision-unit-armed row from host=${HOST} in the last ${WINDOW}."
    echo "  #8562's template reaches the host only at the next inngest-host-replace plus a"
    echo "  human-approved cutover-inngest.yml op=resume; until then this is the expected reading."
  } >&2
  exit 2
fi
armed_ts="$(printf '%s' "$armed" | awk -F'\t' '{print $1}')"
iid="$(printf '%s' "$armed" | awk -F'\t' '{print $3}')"
if [[ "$iid" == "-" || -z "$iid" ]]; then
  probe_fault "the newest provision-unit-armed row carries no iid= field, so no row can be joined to it." \
    "This is a contract drift in the runcmd arming item, not a host verdict."
fi
# The arming item falls back to the hostname, then to `unknown`, when the instance-id is
# unreadable. Both values are SHARED by every host life, so joining on them could PASS a new host
# on a destroyed host's bootstrap-done.
if [[ "$iid" == "unknown" || "$iid" == "$HOST" ]]; then
  probe_fault "the newest provision-unit-armed row carries iid=${iid}, a fallback every host life shares." \
    "It cannot tell this host life from the one it replaced, so no verdict is safe."
fi

# --- 2. the host life's attempts and completions ---------------------------------------------------
# `--grep bootstrap-done` also returns bootstrap-done-DEGRADED rows (substring LIKE); the exact
# stage comparison below tells them apart.
life_rows="$("$QUERY" --since "$WINDOW" --grep provision-attempt-start --grep bootstrap-done \
  --grep isolation-check-FAILED --grep inngest_pull_fatal --grep provision-fsm-busy --limit "$LIMIT" 2>/dev/null)"
qrc=$?
[[ "$qrc" -eq 0 ]] || probe_fault "the Better Stack query for the host life's stages failed (rc=${qrc})."

life="$(decode "$life_rows" | awk -F'\t' -v i="$iid" '$3 == i')"
count_stage() {
  local n
  n="$(printf '%s\n' "$life" | awk -F'\t' -v s="$1" '$2 == s' | grep -c . || true)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  printf '%s' "$n"
}
n_done="$(count_stage bootstrap-done)"
n_degraded="$(count_stage bootstrap-done-DEGRADED)"
n_attempt="$(count_stage provision-attempt-start)"
n_iso="$(count_stage isolation-check-FAILED)"
n_pull="$(count_stage inngest_pull_fatal)"
n_busy="$(count_stage provision-fsm-busy)"
first_attempt_ts="$(printf '%s\n' "$life" | awk -F'\t' '$2 == "provision-attempt-start" {print $1; exit}')"

cause="cause=isolation-check-FAILED:${n_iso},inngest_pull_fatal:${n_pull},provision-fsm-busy:${n_busy},bootstrap-done-DEGRADED:${n_degraded}"
summary="iid=${iid} attempts=${n_attempt} bootstrap_done=${n_done} armed_age_s=$((now - armed_ts))"

if [[ "$n_done" -gt 0 ]]; then
  verdict "PASS"
  {
    echo "  ${summary}"
    echo "  The host life that armed soleur-inngest-provision.service reached bootstrap-done."
    echo "  ADR-257 may flip adopting -> accepted."
  } >&2
  exit 0
fi

if [[ "$n_degraded" -gt 0 ]]; then
  verdict "FAIL reason=degraded ${cause}"
  {
    echo "  ${summary}"
    echo "  The bootstrap succeeded only DEGRADED (SQLite-only: Redis inactive or no durable ExecStart), so the unit"
    echo "  wrote no latch and retries only at the next boot. This is not the accepted state."
    echo "  Read the inngest-luks-* and post-boot-health stages for the same iid (runbook, Provision unit)."
  } >&2
  exit 1
fi

if [[ "$n_attempt" -eq 0 ]]; then
  if [[ $((now - armed_ts)) -gt "$START_BOUND_S" ]]; then
    verdict "FAIL reason=never-started ${cause}"
    {
      echo "  ${summary}"
      echo "  The unit was armed more than ${START_BOUND_S} s ago and no attempt ever started for this iid."
      echo "  Read the host's boot stages (inngest-server.md, Provision unit (#8562)); a replace re-arms it."
    } >&2
    exit 1
  fi
  verdict "TRANSIENT reason=in-progress"
  echo "  ${summary} — armed, first attempt not reported yet." >&2
  exit 2
fi

if [[ $((now - first_attempt_ts)) -gt "$DONE_BOUND_S" ]]; then
  verdict "FAIL reason=no-bootstrap-done ${cause}"
  {
    echo "  ${summary}"
    echo "  Attempts started more than ${DONE_BOUND_S} s ago and none reached bootstrap-done for this iid."
    echo "  Per the runbook this is a replace trigger; read inngest_pull_fatal / isolation-check-* /"
    echo "  provision-fsm-busy for the cause first."
  } >&2
  exit 1
fi

verdict "TRANSIENT reason=in-progress"
echo "  ${summary} — attempts running, inside the ${DONE_BOUND_S} s bound." >&2
exit 2
