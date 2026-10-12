#!/usr/bin/env bash
# Fixture tests for scripts/followthroughs/hosted-destroy-ask-window-9776.sh (a NOTIFY-ONLY probe: it exits 2
# not-yet, 3 cannot-establish or 5 action-required, never 0 or 1). The query script is a stub that RECORDS its
# argv and prints JSONEachRow rows in the stored shape (`raw` is a JSON STRING whose `.message` is the pino object).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/hosted-destroy-ask-window-9776.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

PASS=0; FAIL=0; CHECKED=0
ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }
check() { CHECKED=$((CHECKED + 1)); if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
has()   { CHECKED=$((CHECKED + 1)); case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3]" ;; esac; }
hasnt() { CHECKED=$((CHECKED + 1)); case "$2" in *"$3"*) bad "$1" "unexpected [$3] present" ;; *) ok "$1" ;; esac; }

# row <decision> <ruleSuffix|-> <repo> [role] -> one stub row in the stored shape. CONTAINER_NAME is a TOP-LEVEL field of the
# decoded `raw` (measured on live app-container rows 2026-10-12); ROW_CONTAINER overrides it for the rows that must be excluded.
row() {
  local rule="-"
  [ "$2" != "-" ] && rule="hosted-destroy-ask:$2"
  jq -nc --arg d "$1" --arg r "$rule" --arg repo "$3" --arg role "${4:-owner}" --arg c "${ROW_CONTAINER:-soleur-web-platform}" \
    '{dt:"2026-10-11 10:00:00.000000", raw:({message:({level:40,msg:"x",sec:true,decision:$d,ruleId:$r,repo:$repo,approverRole:$role}),CONTAINER_NAME:$c,source_kind:"app_container"}|tojson)}'
}
rows_of() { local n="$1"; shift; local i; for ((i = 0; i < n; i++)); do row "$@"; done; }
# inngest_rows <n>: the measured 2026-10-12 contamination shape, synthesized (no real payload text): the Inngest host's
# journald copies of webhook payloads that QUOTE the marker. No CONTAINER_NAME; `message` is a string, not a pino object.
inngest_rows() {
  local i; for ((i = 0; i < $1; i++)); do
    jq -nc '{dt:"2026-10-12 09:00:00.000000", raw:({SYSLOG_IDENTIFIER:"doppler",host_name:"soleur-inngest-prd",source_kind:"journald",message:"synthetic webhook event payload quoting destroy-ask"}|tojson)}'
  done
}

QUERY_STUB="$ROOT/query.sh"
cat > "$QUERY_STUB" <<'STUB'
#!/usr/bin/env bash
# Dispatches on the FIRST argument, like the real script: `SELECT ...` is the raw-SQL liveness read, anything else the
# convenience-flag ask read. Every call appends its argv to STUB_ARGS (truncated by run()).
printf '%s\n' "$*" >> "$STUB_ARGS"
case "$1" in
  SELECT*)
    if [ -n "${STUB_LIVE_RC:-}" ] && [ "$STUB_LIVE_RC" != 0 ]; then echo "auth failure for user secret-user at host secret-host" >&2; exit "$STUB_LIVE_RC"; fi
    case "${STUB_LIVE-1000}" in
      garbage) echo "<html>not a count</html>" ;;
      *) printf '{"n":%s}\n' "${STUB_LIVE-1000}" ;;
    esac
    exit 0 ;;
esac
if [ -n "${STUB_RC:-}" ] && [ "$STUB_RC" != 0 ]; then echo "auth failure for user secret-user at host secret-host" >&2; exit "$STUB_RC"; fi
cat "$STUB_ROWS"
STUB
chmod +x "$QUERY_STUB"

run() { # run <window> <rowsfile> [extra env assignments...]
  local win="$1" rows="$2"; shift 2
  : > "$ROOT/args"
  env STUB_ROWS="$rows" STUB_ARGS="$ROOT/args" DESTROY_ASK_QUERY_SCRIPT="$QUERY_STUB" \
    BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p "$@" \
    bash "$SUT" ${win:+--window "$win"} 2>&1
}
out_rc() { OUT="$(run "$@")"; RC=$?; }

# --- argument and environment handling
OUT="$(bash "$SUT" 2>&1)"; check "no --window: exit 3" 3 $?
OUT="$(bash "$SUT" --window 30d 2>&1)"; check "bad window: exit 3" 3 $?
OUT="$(bash "$SUT" --bogus 2>&1)"; check "unknown argument: exit 3" 3 $?
: > "$ROOT/empty"
OUT="$(DESTROY_ASK_QUERY_SCRIPT="$QUERY_STUB" STUB_ROWS="$ROOT/empty" STUB_ARGS="$ROOT/args" BETTERSTACK_QUERY_HOST= BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p bash "$SUT" --window 24h 2>&1)"; RC=$?
check "missing credential: exit 3" 3 "$RC"; has "missing credential names the variable" "$OUT" "BETTERSTACK_QUERY_HOST"
out_rc 24h "$ROOT/empty" STUB_RC=7
check "query failure: exit 3" 3 "$RC"; hasnt "query failure never echoes the stub's credential text" "$OUT" "secret-user"; hasnt "nor its host" "$OUT" "secret-host"
out_rc 24h "$ROOT/empty"
check "zero rows, channel live: NOT YET (exit 2)" 2 "$RC"; has "zero rows says it is expected at low volume" "$OUT" "low volume"
has "24h zero asks prints the string the tail checks (T1)" "$OUT" "NOT YET: no 24h revert threshold tripped."
has "zero asks states it plainly" "$OUT" "0 natural asks"
has "the window and the marker reach the query script" "$(cat "$ROOT/args")" "--since 24h --grep destroy-ask"

# --- stored-shape drift: rows mention the marker, none decodes
printf '%s\n' '{"dt":"2026-10-11 10:00:00","raw":"{\"message\":\"synthetic text quoting destroy-ask\",\"CONTAINER_NAME\":\"soleur-web-platform\"}"}' > "$ROOT/drift"
out_rc 24h "$ROOT/drift"; check "an APP-CONTAINER row mentions the marker, none decodes: exit 3 (M7: isolation did not blind the arm it protects)" 3 "$RC"; has "...named SHAPE_DRIFT" "$OUT" "SHAPE_DRIFT"

# --- 24h window
{ rows_of 3 destroy-ask git-force-default alice/app; } > "$ROOT/r1"
out_rc 24h "$ROOT/r1"; check "24h, 3 ordinary asks: NOT YET" 2 "$RC"; has "counts line" "$OUT" "asks=3"
{ rows_of 3 destroy-ask git-force-default alice/app; row destroy-ask classifier-error alice/app; } > "$ROOT/r2"
out_rc 24h "$ROOT/r2"; check "24h, a classifier-error ask: ACTION REQUIRED" 5 "$RC"; has "...names revert-or-fix" "$OUT" "REVERT_OR_FIX:classifier_error(1)"
{ rows_of 25 destroy-ask git-force-implicit bob/x; rows_of 5 destroy-ask terraform-destroy bob/x; } > "$ROOT/r3"
out_rc 24h "$ROOT/r3"; check "24h, one repo, 30 asks, one rule 83 percent: storm proxy trips" 5 "$RC"; has "...names the proxy, not the ruled metric" "$OUT" "REVERT_PROXY"
{ rows_of 10 destroy-ask git-force-implicit bob/x; } > "$ROOT/r4"
out_rc 24h "$ROOT/r4"; check "24h, one rule 100 percent but only 10 asks (below the floor): no trip" 2 "$RC"
{ rows_of 12 destroy-ask git-force-implicit a/a; rows_of 12 destroy-ask git-force-default b/b; rows_of 12 destroy-ask terraform-destroy c/c; } > "$ROOT/r5"
out_rc 24h "$ROOT/r5"; check "24h, 36 asks spread over three repos and rules: no trip" 2 "$RC"
hasnt "output never names a repo" "$OUT" "a/a"

# --- 7d window
{ rows_of 10 destroy-ask git-force-default alice/app; rows_of 4 destroy-ask-approved git-force-default alice/app; row destroy-ask-rejected git-force-default alice/app; row destroy-ask-expired git-force-default alice/app; } > "$ROOT/s1"
out_rc 7d "$ROOT/s1"; check "7d clean: ACTION REQUIRED (record the numbers)" 5 "$RC"; has "...says record" "$OUT" "Record these numbers"; hasnt "...and trips nothing" "$OUT" "TRIPPED:"
has "outcome counts" "$OUT" "approved=4 rejected=1 expired=1"
{ rows_of 9 destroy-ask git-force-default alice/app; row destroy-ask git-push-unknown-default alice/app; } > "$ROOT/s2"
out_rc 7d "$ROOT/s2"; check "7d, unknown-default exactly 10 percent: not above the line" 5 "$RC"; hasnt "...so no TUNE" "$OUT" "TUNE:"
{ rows_of 8 destroy-ask git-force-default alice/app; rows_of 2 destroy-ask git-push-unknown-default alice/app; } > "$ROOT/s3"
out_rc 7d "$ROOT/s3"; check "7d, unknown-default 20 percent: TUNE" 5 "$RC"; has "...names it" "$OUT" "TUNE:unknown_default(2/10)"
{ rows_of 7 destroy-ask git-force-default alice/app; rows_of 2 destroy-ask fail-closed-keyword alice/app; row destroy-ask raw-scan alice/app; } > "$ROOT/s4"
out_rc 7d "$ROOT/s4"; check "7d, keyword plus raw 30 percent: TUNE" 5 "$RC"; has "...names it" "$OUT" "TUNE:keyword_plus_raw(3/10)"
out_rc 7d "$ROOT/s4"; has "the same rows are NOT a 24h revert" "$(run 24h "$ROOT/s4")" "NOT YET"

# --- a result that cannot be trusted is CANNOT ESTABLISH, never a quiet window
printf '%s\n' '{"error":"unauthorized"}' > "$ROOT/errbody"
out_rc 24h "$ROOT/errbody"; check "an error body with exit 0 is not a quiet window: exit 3" 3 "$RC"
row destroy-ask git-force-default r/r > "$ROOT/one"; yes "$(cat "$ROOT/one")" | head -5000 > "$ROOT/full"
out_rc 24h "$ROOT/full"; check "a result at the 5000-row limit is truncated: exit 3" 3 "$RC"; has "...says truncated" "$OUT" "truncated"
{ rows_of 3 destroy-ask-approved git-force-default alice/app; } > "$ROOT/o1"
out_rc 24h "$ROOT/o1"; check "outcome lines with no ask lines: exit 3" 3 "$RC"
{ rows_of 1 destroy-ask git-force-default alice/app; rows_of 2 destroy-ask-approved git-force-default alice/app; } > "$ROOT/o2"
out_rc 24h "$ROOT/o2"; check "more outcomes than asks: exit 3" 3 "$RC"

# --- every repo is evaluated, not only the busiest
{ rows_of 21 destroy-ask git-force-implicit a/a; rows_of 40 destroy-ask git-force-default b/b; rows_of 40 destroy-ask terraform-destroy b/b; rows_of 30 destroy-ask git-force-implicit b/b; } > "$ROOT/m1"
out_rc 24h "$ROOT/m1"; check "24h, the busiest repo is spread but a smaller qualifying repo is all one rule: trips" 5 "$RC"
{ rows_of 12 destroy-ask git-force-default alice/app; rows_of 2 destroy-ask-approved git-force-default alice/app member; row destroy-ask-approved git-force-default alice/app owner; } > "$ROOT/m2"
out_rc 24h "$ROOT/m2"; has "member approvals are reported" "$OUT" "member_approvals=2"; has "implicit-force share is reported" "$OUT" "implicit_force=0"

# --- enrolment wrappers fix the window and delegate (the directive cannot carry arguments)
for w in 24h 7d; do
  WOUT="$(STUB_ROWS="$ROOT/r1" STUB_ARGS="$ROOT/wargs-$w" DESTROY_ASK_QUERY_SCRIPT="$QUERY_STUB" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p bash "$SCRIPT_DIR/hosted-destroy-ask-window-9776-$w.sh" 2>&1)"; WRC=$?
  case "$w:$WRC" in 24h:2|7d:5) ok "wrapper $w: exit $WRC (the same verdict as --window $w)" ;; *) bad "wrapper $w: unexpected exit $WRC" ;; esac; CHECKED=$((CHECKED + 1))
  has "wrapper $w queries the $w window" "$(cat "$ROOT/wargs-$w")" "--since $w"
done

# --- Guard 2: isolation (the measured 2026-10-12 contamination) and liveness (a quiet window must be proven quiet, not dark)
# H0 (first measured shape): 34 Inngest-host rows quote the marker, no app-container row does, no lane row exists.
inngest_rows 34 > "$ROOT/h0"
out_rc 24h "$ROOT/h0"; check "H0: 34 non-app rows quoting the marker are NOT a shape drift (24h: exit 2)" 2 "$RC"; has "H0: the first line names the window" "$OUT" "hosted destroy-ask window 24h"
hasnt "H0: never reports SHAPE_DRIFT on another service's rows" "$OUT" "SHAPE_DRIFT"
out_rc 7d "$ROOT/h0"; check "M6: the same contamination at 7d: ACTION REQUIRED (exit 5), not CANNOT ESTABLISH" 5 "$RC"
# M1/M2: dark channel (zero app-container pino rows in the same window) with zero asks is CANNOT ESTABLISH in both windows
out_rc 24h "$ROOT/empty" STUB_LIVE=0; check "M1: zero asks + dark channel (24h): exit 3, not 2" 3 "$RC"; has "M1: says why" "$OUT" "liveness"
out_rc 7d "$ROOT/empty" STUB_LIVE=0; check "M2: zero asks + dark channel (7d): exit 3, not 5" 3 "$RC"
# M3/M4: live channel, zero asks
out_rc 7d "$ROOT/empty"; check "M3: live channel, zero asks, 7d: exit 5" 5 "$RC"
has "M3: the n=0 statement" "$OUT" "0 natural asks"; has "M3: says the soak did not exercise the lane" "$OUT" "did not exercise the lane"
has "M3: points at the flip checklist" "$OUT" "Flip checklist"; has "M3: still the probe's first-line shape" "$OUT" "hosted destroy-ask window 7d"
out_rc 24h "$ROOT/empty"; check "M4: live channel, zero asks, 24h: exit 2" 2 "$RC"
# M8: truncation is judged on the RAW line count, so contamination cannot hide it
{ inngest_rows 4995; rows_of 5 destroy-ask git-force-default alice/app; } > "$ROOT/m8"
out_rc 24h "$ROOT/m8"; check "M8: 5000 raw rows (almost all non-app): truncated, exit 3" 3 "$RC"; has "M8: says truncated" "$OUT" "truncated"
# M9 / H2: only the app container counts, and the match is exact
{ ROW_CONTAINER=soleur-web-platform-canary rows_of 3 destroy-ask git-force-default alice/app; } > "$ROOT/m9"
out_rc 24h "$ROOT/m9"; check "M9: canary-container ask rows are not asks (exit 2, zero asks)" 2 "$RC"; has "M9: asks=0 (anchored: top_repo_asks=0 would also contain asks=0)" "$OUT" "window 24h: asks=0 "
{ ROW_CONTAINER=Soleur-Web-Platform rows_of 2 destroy-ask git-force-default zed/zed; rows_of 2 destroy-ask git-force-default carol/other; } > "$ROOT/h2"
out_rc 24h "$ROOT/h2"; check "H2: a repo the canonical fixture never uses, and a different-case container name" 2 "$RC"
has "H2: only the exact-case app container counts (2 asks, not 4)" "$OUT" "window 24h: asks=2 "
{ inngest_rows 34; rows_of 3 destroy-ask git-force-default alice/app; } > "$ROOT/mix"
out_rc 24h "$ROOT/mix"; has "contamination beside real lane rows: only the lane rows count" "$OUT" "window 24h: asks=3 "
hasnt "...and the contamination does not trip anything" "$OUT" "SHAPE_DRIFT"
# the liveness read: raw SQL through the same query script, both Better Stack arms, same window, app container, pino level >= 40
out_rc 24h "$ROOT/empty"; LARGS="$(cat "$ROOT/args")"
has "liveness read is the raw-SQL call" "$LARGS" "SELECT"; has "liveness read includes the hot arm" "$LARGS" 'remote($BS_TABLE)'
has "liveness read includes the ARCHIVE arm" "$LARGS" 's3Cluster(primary, $BS_TABLE_S3)'; has "liveness read uses the same 24h window" "$LARGS" "INTERVAL 24 HOUR"
has "liveness read is scoped to the app container" "$LARGS" "soleur-web-platform"; has "liveness read requires pino level 40 or above" "$LARGS" ">= 40"
out_rc 7d "$ROOT/empty"; has "7d liveness read uses the 7d window" "$(cat "$ROOT/args")" "INTERVAL 7 DAY"
# a liveness read that fails or cannot be parsed never reads as a quiet window
out_rc 24h "$ROOT/empty" STUB_LIVE_RC=7; check "liveness query failure: exit 3" 3 "$RC"; hasnt "...never echoes the stub's credential text" "$OUT" "secret-user"
out_rc 24h "$ROOT/empty" STUB_LIVE=garbage; check "liveness result that is not a count: exit 3" 3 "$RC"
# liveness is not consulted when asks exist (the channel is evidently live) and never changes a trip
out_rc 24h "$ROOT/r2" STUB_LIVE=0; check "asks present: a classifier-error ask still trips with a zero liveness stub" 5 "$RC"

# --- exit vocabulary and xtrace
for f in r1 r2 r3 s1 s3 drift empty; do
  w=24h; case "$f" in s*) w=7d ;; esac
  out_rc "$w" "$ROOT/$f"
  case "$RC" in 2|3|5) ok "exit vocabulary: $f -> $RC" ;; *) bad "exit vocabulary: $f -> $RC (never 0 or 1)" ;; esac; CHECKED=$((CHECKED + 1))
done
OUT="$(STUB_ROWS="$ROOT/r1" STUB_ARGS="$ROOT/args" DESTROY_ASK_QUERY_SCRIPT="$QUERY_STUB" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p bash -x "$SUT" --window 24h 2>&1)"; RC=$?
check "xtrace with a live credential: refuses (78)" 78 "$RC"

# Anti-vacuity floor: a literal directly above its `if`, reported by printf + exit, never through the helpers.
MIN_CHECKS=87
if [ "$CHECKED" -lt "$MIN_CHECKS" ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, floor %s\n' "$CHECKED" "$MIN_CHECKS" >&2
  exit 1
fi
if [ $((PASS + FAIL)) -ne "$CHECKED" ]; then printf 'HALT: pass+fail (%s) != checks (%s)\n' "$((PASS + FAIL))" "$CHECKED"; exit 1; fi
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
