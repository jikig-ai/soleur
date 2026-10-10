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

# row <decision> <ruleSuffix|-> <repo> -> one stub row in the stored shape
row() {
  local rule="-"
  [ "$2" != "-" ] && rule="hosted-destroy-ask:$2"
  jq -nc --arg d "$1" --arg r "$rule" --arg repo "$3" --arg role "${4:-owner}" \
    '{dt:"2026-10-11 10:00:00.000000", raw:({message:({level:40,msg:"x",sec:true,decision:$d,ruleId:$r,repo:$repo,approverRole:$role}),source_kind:"app_container"}|tojson)}'
}
rows_of() { local n="$1"; shift; local i; for ((i = 0; i < n; i++)); do row "$@"; done; }

QUERY_STUB="$ROOT/query.sh"
cat > "$QUERY_STUB" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGS"
if [ -n "${STUB_RC:-}" ] && [ "$STUB_RC" != 0 ]; then echo "auth failure for user secret-user at host secret-host" >&2; exit "$STUB_RC"; fi
cat "$STUB_ROWS"
STUB
chmod +x "$QUERY_STUB"

run() { # run <window> <rowsfile> [extra env assignments...]
  local win="$1" rows="$2"; shift 2
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
check "zero rows: NOT YET (exit 2)" 2 "$RC"; has "zero rows says it is expected at low volume" "$OUT" "low volume"
has "the window and the marker reach the query script" "$(cat "$ROOT/args")" "--since 24h --grep destroy-ask"

# --- stored-shape drift: rows mention the marker, none decodes
printf '%s\n' '{"dt":"2026-10-11 10:00:00","raw":"{\"message\":\"some issue body quoting destroy-ask\"}"}' > "$ROOT/drift"
out_rc 24h "$ROOT/drift"; check "mentions but no decode: exit 3" 3 "$RC"; has "...named SHAPE_DRIFT" "$OUT" "SHAPE_DRIFT"

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

# --- exit vocabulary and xtrace
for f in r1 r2 r3 s1 s3 drift empty; do
  w=24h; case "$f" in s*) w=7d ;; esac
  out_rc "$w" "$ROOT/$f"
  case "$RC" in 2|3|5) ok "exit vocabulary: $f -> $RC" ;; *) bad "exit vocabulary: $f -> $RC (never 0 or 1)" ;; esac; CHECKED=$((CHECKED + 1))
done
OUT="$(STUB_ROWS="$ROOT/r1" STUB_ARGS="$ROOT/args" DESTROY_ASK_QUERY_SCRIPT="$QUERY_STUB" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p bash -x "$SUT" --window 24h 2>&1)"; RC=$?
check "xtrace with a live credential: refuses (78)" 78 "$RC"

# Anti-vacuity floor: a literal directly above its `if`, reported by printf + exit, never through the helpers.
MIN_CHECKS=49
if [ "$CHECKED" -lt "$MIN_CHECKS" ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, floor %s\n' "$CHECKED" "$MIN_CHECKS" >&2
  exit 1
fi
if [ $((PASS + FAIL)) -ne "$CHECKED" ]; then printf 'HALT: pass+fail (%s) != checks (%s)\n' "$((PASS + FAIL))" "$CHECKED"; exit 1; fi
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
