#!/usr/bin/env bash
# Exit-code harness for post-deploy-incident-soak.sh (generic post-merge
# alert-channel soak; epic #10390 WS3, ADR-297).
#
# The probe's exit code IS its authorization artifact: sweep-followthroughs.sh
# closes the tracker on 0, comments FAIL on 1, and retries on anything else.
# Cardinal sins: a vacuous 0 on a window the read never measured; a 0 where the
# alert substrate could not have paged (zero armed members); and a 1
# manufactured from a read failure (TRANSIENT is the contract for an
# unmeasured window — the sweeper retries, it does not alarm).
#
# The SUT runs under `env -i` exactly as the sweeper runs it, with PATH-shimmed
# `curl` (dispatches on the URL: incidents vs heartbeats vs monitors, per-page
# files, records argv + the stdin-config bearer, can fail with a chosen rc or a
# chosen HTTP status) and `gh` (records argv, serves the issues fixture or
# fails). The window is pinned to fixed timestamps + a fake NOW clock, so every
# case is deterministic. Fixtures are synthesized
# (cq-test-fixtures-synthesized-only) and reproduce the uptime-API list shape
# ({data:[{id,attributes:{...}}],pagination:{next}}) and `gh issue list`'s
# [{number,title,createdAt,labels:[{name}]}].

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/post-deploy-incident-soak.sh"
fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

# Instrument self-test (ADR-193): both counters must move before any verdict is
# trusted.
_p0=$total; pass "instrument: pass() moves the counter" >/dev/null; _f0=$fails
fail "instrument: fail() moves the counter" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move their counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

WORK="$(mktemp -d -t pdis-test.XXXXXXXX)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
mkdir -p "$WORK/bin"
CALLS="$WORK/calls.log"

# ── Fixed window: deploy 2026-10-24T12:00:00Z, 24h soak -> end 25T12:00Z ─────
DEPLOY="2026-10-24T12:00:00Z"
DEPLOY_EPOCH="$(date -u -d "$DEPLOY" +%s)"
END_EPOCH=$(( DEPLOY_EPOCH + 86400 ))
NOW_EPOCH=$(( END_EPOCH + 60 ))   # first sweep 60s after the window closed
IN_WINDOW="2026-10-24T18:30:00.000Z"   # inside [deploy, deploy+24h]
AT_DEPLOY="$DEPLOY"                    # inclusive lower bound
AT_END="2026-10-25T12:00:00.000Z"      # inclusive upper bound
PRE_DEPLOY="2026-10-24T11:59:00.000Z"  # before the window
POST_WINDOW="2026-10-25T12:01:00.000Z" # after the window

incident_row() { # <id> <name> <cause> <started_at>
  printf '{"id":"%s","type":"incident","attributes":{"name":"%s","cause":"%s","started_at":"%s","resolved_at":null,"acknowledged_by":"SECRETISH_PERSON","screenshot_url":"https://x/SECRETISH_SHOT"}}' \
    "$1" "$2" "$3" "$4"
}
incidents_json() { # rows as $@; next-url as $INCIDENTS_NEXT (optional)
  local next="${INCIDENTS_NEXT:-null}" rows="" r
  [[ "$next" != null ]] && next="\"$next\""
  for r in "$@"; do rows+="${rows:+,}$r"; done
  printf '{"data":[%s],"pagination":{"next":%s}}' "$rows" "$next"
}
hb_json() { # statuses as $@
  local rows="" s
  for s in "$@"; do rows+="${rows:+,}{\"id\":\"hb-${s}\",\"attributes\":{\"name\":\"hb-${s}\",\"status\":\"${s}\"}}"; done
  printf '{"data":[%s],"pagination":{"next":null}}' "$rows"
}
mon_json() { # statuses as $@
  local rows="" s
  for s in "$@"; do rows+="${rows:+,}{\"id\":\"mon-${s}\",\"attributes\":{\"name\":\"mon-${s}\",\"status\":\"${s}\"}}"; done
  printf '{"data":[%s],"pagination":{"next":null}}' "$rows"
}
issue_row() { # <number> <title> <createdAt> <labels-csv>
  local labels="" l
  IFS=',' read -r -a ls <<<"${4:-}"
  for l in "${ls[@]}"; do [[ -n "$l" ]] && labels+="${labels:+,}{\"name\":\"$l\"}"; done
  printf '{"number":%s,"title":"%s","createdAt":"%s","labels":[%s]}' "$1" "$2" "$3" "$labels"
}
issues_json() { local rows="" r; for r in "$@"; do rows+="${rows:+,}$r"; done; printf '[%s]' "$rows"; }

# ── curl stub: dispatches on URL (+page), honours -o and -w, records argv,
#    reads the stdin-config bearer, fails on demand ─────────────────────────
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
cfg="$(dirname "$0")/.."
printf 'curl %s\n' "$*" >> "$cfg/calls.log"
out=""; url=""; want_code=0
args=("$@")
for a in "${args[@]}"; do [[ "$a" == "-" ]] && { cat >> "$cfg/stdin.log"; break; }; done
for (( i = 0; i < ${#args[@]}; i++ )); do
  case "${args[$i]}" in
    -o) out="${args[$((i+1))]}"; i=$((i+1)) ;;
    -w) want_code=1; i=$((i+1)) ;;
    -m|-H|--max-redirs|--proto|--noproxy) i=$((i+1)) ;;
    https://*) url="${args[$i]}" ;;
  esac
done
page="$(printf '%s' "$url" | sed -nE 's/.*[?&]page=([0-9]+).*/\1/p')"
kind=""
case "$url" in
  https://uptime.betterstack.com/api/v2/incidents*)  kind=incidents ;;
  https://uptime.betterstack.com/api/v2/heartbeats*) kind=heartbeats ;;
  https://uptime.betterstack.com/api/v2/monitors*)   kind=monitors ;;
  *) printf 'stub: unexpected url %s\n' "$url" >&2; printf 'OFFHOST %s\n' "$url" >> "$cfg/calls.log"; exit 99 ;;
esac
rc_file="$cfg/curl_${kind}.rc"; [[ -f "$rc_file" ]] && { rc="$(<"$rc_file")"; [[ "$rc" != "0" ]] && exit "$rc"; }
if [[ -n "$page" && -f "$cfg/${kind}.p${page}.json" ]]; then body="$cfg/${kind}.p${page}.json"; else body="$cfg/${kind}.json"; fi
[[ -f "$body" ]] || { printf 'stub: missing fixture %s\n' "$body" >&2; exit 98; }
code="$(cat "$cfg/${kind}.code" 2>/dev/null || echo 200)"
[[ -n "$out" ]] && cp "$body" "$out"
[[ "$want_code" == 1 ]] && printf '%s' "$code"
exit 0
STUB
chmod 0755 "$WORK/bin/curl"

# ── gh stub: records argv, serves issues.json, fails on demand ───────────────
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
cfg="$(dirname "$0")/.."
printf 'gh %s\n' "$*" >> "$cfg/calls.log"
rc_file="$cfg/gh.rc"; [[ -f "$rc_file" ]] && { rc="$(<"$rc_file")"; [[ "$rc" != "0" ]] && { echo "gh: simulated failure" >&2; exit "$rc"; }; }
case " $* " in
  *" issue list "*) cat "$cfg/issues.json" ;;
  *) printf 'stub: unexpected gh argv %s\n' "$*" >&2; exit 64 ;;
esac
STUB
chmod 0755 "$WORK/bin/gh"

# run_case <desc> <expected-rc> [env assignments...] -- SUT argv via $SUT_ARGV
run_case() {
  local desc="$1" expected="$2"; shift 2
  local rc=0 out
  out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
    GH_TOKEN=faketoken123 BETTERSTACK_API_TOKEN=fakeapitoken456 \
    "$@" bash "$SUT" ${SUT_ARGV:-} 2>&1)"; rc=$?
  if [[ "$rc" -eq "$expected" ]]; then pass "$desc"; else fail "$desc (expected rc=$expected, got rc=$rc; out: $(printf '%s' "$out" | tail -4 | tr '\n' '|'))"; fi
  unset SUT_ARGV
}

# ── Fixtures for the base case: clean window, armed substrate ───────────────
BASE_HB='{"data":[{"id":"hb-1","attributes":{"name":"soleur-inngest-server-prd","status":"up"}},{"id":"hb-2","attributes":{"name":"soleur-git-data-host-prd","status":"paused"}}],"pagination":{"next":null}}'
BASE_MON='{"data":[{"id":"mon-1","attributes":{"name":"soleur app database readiness","status":"up"}}],"pagination":{"next":null}}'
EMPTY_INCIDENTS='{"data":[],"pagination":{"next":null}}'
EMPTY_ISSUES='[]'

write_base() { # <incidents> <issues> [hb] [mon]
  printf '%s' "${1:-$EMPTY_INCIDENTS}" > "$WORK/incidents.json"
  printf '%s' "${2:-$EMPTY_ISSUES}" > "$WORK/issues.json"
  printf '%s' "${3:-$BASE_HB}" > "$WORK/heartbeats.json"
  printf '%s' "${4:-$BASE_MON}" > "$WORK/monitors.json"
  : > "$CALLS"; : > "$WORK/stdin.log"
  rm -f "$WORK"/curl_*.rc "$WORK"/*.code "$WORK/gh.rc" "$WORK"/incidents.p*.json
}
ENV="POST_DEPLOY_SOAK_DEPLOY_TS=$DEPLOY POST_DEPLOY_SOAK_NOW_EPOCH=$NOW_EPOCH"

# 1. Clean window, armed substrate (one member paused -> tolerated) -> PASS 0
write_base
run_case "clean window + armed substrate (paused member tolerated) -> PASS" 0 $ENV

# The PASS line should name the counts and the liveness arm.
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=t BETTERSTACK_API_TOKEN=t \
  $ENV bash "$SUT" 2>&1)"
if printf '%s' "$out" | grep -q "PASS: zero new Better Stack incidents and zero new ci/ issues"; then
  pass "PASS line names both zero counts"
else
  fail "PASS line names both zero counts (out: $(printf '%s' "$out" | tail -2))"
fi

# 2. Incident in window -> FAIL 1
write_base "$(incidents_json "$(incident_row 77 "soleur-inngest-consumer-prd" "Heartbeat missed" "$IN_WINDOW")")"
run_case "incident inside window -> FAIL" 1 $ENV

# 3. Incident before deploy AND after window end -> PASS (window pinned)
write_base "$(incidents_json \
  "$(incident_row 71 "pre-deploy incident" "x" "$PRE_DEPLOY")" \
  "$(incident_row 78 "post-window incident" "x" "$POST_WINDOW")")"
run_case "incidents only outside [deploy, deploy+24h] -> PASS" 0 $ENV

# 4. Inclusive bounds: incident at exactly deploy_ts -> FAIL; at exactly end -> FAIL
write_base "$(incidents_json "$(incident_row 79 "at-deploy" "x" "$AT_DEPLOY")")"
run_case "incident stamped exactly at deploy_ts -> FAIL (inclusive)" 1 $ENV
write_base "$(incidents_json "$(incident_row 80 "at-end" "x" "$AT_END")")"
run_case "incident stamped exactly at window end -> FAIL (inclusive)" 1 $ENV

# 5. ci/ issue in window -> FAIL 1
write_base "$EMPTY_INCIDENTS" \
  "$(issues_json "$(issue_row 111 "ci/inngest-down fired" "$IN_WINDOW" "ci/inngest-down,action-required")")"
run_case "ci/ issue inside window -> FAIL" 1 $ENV

# 6. Issue in window WITHOUT a ci/ label -> PASS
write_base "$EMPTY_INCIDENTS" \
  "$(issues_json "$(issue_row 112 "a plain question" "$IN_WINDOW" "type/question")")"
run_case "non-ci/ issue inside window -> PASS" 0 $ENV

# 7. ci/ issue created after window end -> PASS (upper bound client-side)
write_base "$EMPTY_INCIDENTS" \
  "$(issues_json "$(issue_row 113 "late filing" "$POST_WINDOW" "ci/zot-restart-loop")")"
run_case "ci/ issue after window end -> PASS" 0 $ENV

# 8. curl transport failure on incidents -> CANNOT ESTABLISH 3
write_base
echo 7 > "$WORK/curl_incidents.rc"
run_case "incidents read: curl rc=7 -> CANNOT ESTABLISH" 3 $ENV

# 9. HTTP 500 on incidents -> 3
write_base
echo 500 > "$WORK/incidents.code"
run_case "incidents read: HTTP 500 -> CANNOT ESTABLISH" 3 $ENV

# 10. gh failure -> 3
write_base
echo 4 > "$WORK/gh.rc"
run_case "gh issue list failure -> CANNOT ESTABLISH" 3 $ENV

# 11. heartbeats read failure on the liveness gate -> 3
write_base
echo 28 > "$WORK/curl_heartbeats.rc"
run_case "liveness read failure -> CANNOT ESTABLISH" 3 $ENV

# 12. All members paused/pending -> 3 (nothing armed: zero findings prove nothing)
write_base "$EMPTY_INCIDENTS" "$EMPTY_ISSUES" \
  "$(hb_json paused pending)" "$(mon_json paused)"
run_case "all members paused/pending -> CANNOT ESTABLISH (tolerated, not armed)" 3 $ENV

# 13. paused member + one armed member -> PASS (tolerated)
write_base "$EMPTY_INCIDENTS" "$EMPTY_ISSUES" \
  "$(hb_json pending up)" "$(mon_json paused)"
run_case "pending heartbeat tolerated alongside an armed member -> PASS" 0 $ENV

# 14. Unparseable started_at -> 3
write_base "$(incidents_json "$(incident_row 90 "bad-ts" "x" "not-a-timestamp")")"
run_case "unparseable started_at -> CANNOT ESTABLISH" 3 $ENV

# 15. Issue list saturated at --limit -> 3 (truncated set cannot be judged)
write_base "$EMPTY_INCIDENTS" \
  "$(issues_json "$(issue_row 201 a "$IN_WINDOW" type/chore)" "$(issue_row 202 b "$IN_WINDOW" type/chore)")"
run_case "issue list at the limit -> CANNOT ESTABLISH" 3 \
  $ENV POST_DEPLOY_SOAK_ISSUE_LIMIT=2

# 16. argv $1 deploy anchor (local/manual run) -> FAIL on in-window incident
write_base "$(incidents_json "$(incident_row 77 "soleur-inngest-server-prd" "x" "$IN_WINDOW")")"
SUT_ARGV="$DEPLOY"
run_case "argv deploy anchor -> FAIL on in-window incident" 1 \
  POST_DEPLOY_SOAK_NOW_EPOCH="$NOW_EPOCH"

# 17. SOLEUR_FT_EARLIEST derivation: earliest = deploy+24h is the soak END
write_base "$(incidents_json "$(incident_row 77 "earliest-derived window" "x" "$IN_WINDOW")")"
run_case "SOLEUR_FT_EARLIEST-derived window -> FAIL on in-window incident" 1 \
  POST_DEPLOY_SOAK_NOW_EPOCH="$NOW_EPOCH" SOLEUR_FT_EARLIEST="2026-10-25T12:00:00Z"

# 18. Window not yet elapsed -> NOT YET 2
EARLY_NOW=$(( DEPLOY_EPOCH + 3600 ))
write_base
run_case "fake now inside the window -> NOT YET" 2 \
  POST_DEPLOY_SOAK_DEPLOY_TS="$DEPLOY" POST_DEPLOY_SOAK_NOW_EPOCH="$EARLY_NOW"

# 19. No anchor at all -> NOT YET 2
write_base
run_case "no deploy anchor -> NOT YET" 2 POST_DEPLOY_SOAK_NOW_EPOCH="$NOW_EPOCH"

# 20. Non-canonical anchor (natural language — `date -d` would accept it) -> 2
write_base
run_case "non-canonical deploy anchor -> NOT YET" 2 \
  POST_DEPLOY_SOAK_DEPLOY_TS="yesterday" POST_DEPLOY_SOAK_NOW_EPOCH="$NOW_EPOCH"

# 21. Non-canonical earliest under the sweeper path -> 2 (issue-body data untrusted)
write_base
run_case "non-canonical SOLEUR_FT_EARLIEST -> NOT YET" 2 \
  POST_DEPLOY_SOAK_NOW_EPOCH="$NOW_EPOCH" SOLEUR_FT_EARLIEST="2026-10-25 12:00:00"

# 22. Missing GH_TOKEN -> 3 (env-allowlist failure, not a finding)
write_base
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  BETTERSTACK_API_TOKEN=t $ENV bash "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 3 ]]; then pass "missing GH_TOKEN -> CANNOT ESTABLISH"; else fail "missing GH_TOKEN -> CANNOT ESTABLISH (rc=$rc)"; fi

# 23. Missing BETTERSTACK_API_TOKEN -> 3
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  GH_TOKEN=t $ENV bash "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 3 ]]; then pass "missing BETTERSTACK_API_TOKEN -> CANNOT ESTABLISH"; else fail "missing BETTERSTACK_API_TOKEN -> CANNOT ESTABLISH (rc=$rc)"; fi

# 24. xtrace refusal -> 78 with creds set
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" \
  GH_TOKEN=t BETTERSTACK_API_TOKEN=t $ENV bash -x "$SUT" 2>&1)"; rc=$?
if [[ "$rc" -eq 78 ]]; then pass "xtrace with creds -> refusal 78"; else fail "xtrace with creds -> refusal 78 (rc=$rc)"; fi

# 25. Query-shape pins: the gh call carries the server-side created:>= bound and
#     the curl calls hit incidents + heartbeats + monitors on the pinned host.
write_base
env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=t BETTERSTACK_API_TOKEN=t \
  $ENV bash "$SUT" >/dev/null 2>&1
if grep -q "gh issue list .*created:>=${DEPLOY}" "$CALLS"; then
  pass "gh call carries created:>= deploy bound"
else
  fail "gh call carries created:>= deploy bound (calls: $(cat "$CALLS"))"
fi
for ep in incidents heartbeats monitors; do
  if grep -q "https://uptime.betterstack.com/api/v2/${ep}" "$CALLS"; then
    pass "curl reached /api/v2/${ep} on the pinned host"
  else
    fail "curl reached /api/v2/${ep} on the pinned host"
  fi
done
if grep -q 'header = "Authorization: Bearer ' "$WORK/stdin.log"; then
  pass "bearer rides the stdin config channel (never argv)"
else
  fail "bearer rides the stdin config channel (stdin.log: $(cat "$WORK/stdin.log"))"
fi
if grep -q 'Authorization' "$CALLS"; then
  fail "bearer must never reach argv"
else
  pass "bearer never reaches argv"
fi

# 26. pagination.next honoured: the in-window incident sits on page 2 -> FAIL
write_base
INCIDENTS_NEXT="https://uptime.betterstack.com/api/v2/incidents?per_page=50&page=2" \
  incidents_json "$(incident_row 60 "old-page-1" "x" "$POST_WINDOW")" > "$WORK/incidents.json"
incidents_json "$(incident_row 77 "page-2 finding" "x" "$IN_WINDOW")" > "$WORK/incidents.p2.json"
run_case "in-window incident on page 2 -> FAIL" 1 $ENV

# 27. Off-host pagination.next -> 3 (never follows the token off-host)
write_base
INCIDENTS_NEXT="https://evil.example.com/api/v2/incidents?page=2" \
  incidents_json "$(incident_row 60 "old-page-1" "x" "$POST_WINDOW")" > "$WORK/incidents.json"
run_case "off-host pagination.next -> CANNOT ESTABLISH" 3 $ENV

# 28. Env-override anchor: POST_DEPLOY_SOAK_DEPLOY_TS behaves like argv.
write_base "$(incidents_json "$(incident_row 77 "env-anchored" "x" "$IN_WINDOW")")"
run_case "POST_DEPLOY_SOAK_DEPLOY_TS anchor -> FAIL on in-window incident" 1 \
  $ENV

# 29. A 1h soak: earliest = deploy+1h derives a 1h window; an incident 2h past
#     deploy is out of it.
SHORT_EPOCH=$(( DEPLOY_EPOCH + 3600 ))
write_base "$(incidents_json "$(incident_row 77 "2h-later" "x" "2026-10-24T14:00:00.000Z")")"
run_case "POST_DEPLOY_SOAK_WINDOW_HOURS=1 narrows the derived window -> PASS" 0 \
  POST_DEPLOY_SOAK_WINDOW_HOURS=1 SOLEUR_FT_EARLIEST="2026-10-24T13:00:00Z" \
  POST_DEPLOY_SOAK_NOW_EPOCH=$(( SHORT_EPOCH + 60 ))

printf '\n%d assertions, %d failure(s)\n' "$total" "$fails"
[[ "$fails" -eq 0 ]]
