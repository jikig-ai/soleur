#!/usr/bin/env bash
# web2-luks-live-6931.test.sh — fixture harness for the #6931 soak-gated closure probe.
#
# The probe sources scripts/lib/web2-luks-rows.sh (the SAME query + parse the daily verify leg uses) and
# reads the marker through the Doppler API. A PATH-stubbed `curl` serves BOTH the Better Stack query (via
# the real scripts/betterstack-query.sh) and the Doppler GET, and REFUSES any request it was not taught
# (exit 64), so a probe that asks the wrong question cannot read the right fixture. Every sweeper exit code
# is driven and each verdict is pinned by BOTH its exit code and its leading word. Every row is synthesized.
#
# The probe's exit 0 closes the tracker, so the arms that matter are the ones that must NOT reach it: a
# young marker, a red row since the marker, a stale / non-LUKS latest row, an unanswered read.
#
# Registered explicitly in scripts/test-all.sh (scripts/followthroughs/*.test.sh is not in SUITE_GLOBS).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
PROBE="$DIR/web2-luks-live-6931.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }
# Instrument self-test: drive no() and ok() once each and require that EACH moved its own counter.
no "self-test (expected)" 2>/dev/null; ok "self-test (expected)" >/dev/null
if [ "$fail" -ne 1 ] || [ "$pass" -ne 1 ]; then
  printf 'FATAL: the verdict helpers do not count (fail=%s pass=%s)\n' "$fail" "$pass" >&2
  exit 1
fi
pass=0; fail=0

TOK=dp.st.fixture0marker
UA=11111111-2222-3333-4444-555555555555
BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/fx"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
# Routes on the destination. Refuses everything it was not taught.
url=""; data=""; user=""; cfg=""
while [ $# -gt 0 ]; do
  case "$1" in -d) data="$2"; shift 2 ;; -u) user="$2"; shift 2 ;; -K) cfg="$2"; shift 2 ;; -o) out="$2"; shift 2 ;; -w) wfmt="$2"; shift 2 ;; https://*) url="$1"; shift ;; *) shift ;; esac
done
case " $* " in *"$MARKER_TOKEN"*) echo "curl stub: the Doppler token appeared in argv" >&2; exit 64 ;; esac
case "$url" in
  "https://api.doppler.com/v3/configs/config/secret?project=soleur&config=prd_workspaces_luks_marker&name=WORKSPACES_LUKS_CUTOVER_AT")
    # the token must arrive on stdin as a curl config line, nowhere else
    [ "$cfg" = "-" ] || { echo "curl stub: the token must be read from stdin (-K -)" >&2; exit 64; }
    hdr="$(cat)"; [ "$hdr" = "header = \"Authorization: Bearer $MARKER_TOKEN\"" ] || { echo "curl stub: bad Authorization header" >&2; exit 64; }
    printf 'doppler\n' >> "$CALLS"
    [ -f "$FX/doppler.code" ] && code="$(cat "$FX/doppler.code")" || code=200
    [ -f "$FX/doppler.body" ] && cat "$FX/doppler.body" > "$out"
    printf '%s' "$code"; [ "$code" = 000 ] && exit 28; exit 0 ;;
  "https://fixture-connect.betterstackdata.com?"*)
    [ "$user" = fixture-user:fixture-pass ] || exit 64
    printf 'bs\n' >> "$CALLS"
    [ -f "$FX/bs.mode" ] && case "$(cat "$FX/bs.mode")" in 503) printf '{"error":"x"}'; exit 22 ;; timeout) exit 28 ;; esac
    case "$data" in *"'luks-monitor'"*) cat "$FX/probe" ;; *) echo "curl stub: REFUSED query" >&2; exit 64 ;; esac
    exit 0 ;;
esac
echo "curl stub: REFUSED $url" >&2; exit 64
STUB
chmod +x "$BIN/curl"

row() { jq -cn --arg age "$1" --arg m "$2" '{dt: "2026-10-01 04:41:00.000", age_s: $age, message: $m, host_name: "soleur-web-2", ident: "luks-monitor"}'; }
okmsg() { printf 'OK: /mnt/data is LUKS-backed (device_type=%s mount_source=/dev/mapper/workspaces escrow=%s header=readable boot_id=%s)' "${1:-crypto_LUKS}" "${2:-ok}" "$UA"; }
iso_ago() { date -u -d "$1 ago" +%Y-%m-%dT%H:%M:%SZ; }
D=86400

reset_fx() { rm -rf "$WORK/fx"; mkdir -p "$WORK/fx"; : > "$WORK/calls"; }
marker() { printf '{"name":"WORKSPACES_LUKS_CUTOVER_AT","value":{"raw":"%s","computed":"%s"},"success":true}' "$1" "$1" > "$WORK/fx/doppler.body"; }
probe() { cat > "$WORK/fx/probe"; }

# run <want-rc> <want-word> <label> [ENV=VAL ...]
run() {
  local want_rc="$1" want_word="$2" label="$3" out rc=0; shift 3
  out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" MARKER_TOKEN="$TOK" \
    BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user \
    BETTERSTACK_QUERY_PASSWORD=fixture-pass DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER="$TOK" "$@" \
    bash "${PROBE_UNDER_TEST:-$PROBE}" 2>&1)" || rc=$?
  LAST_OUT="$out"
  # The verdict word starts a line; the helper's own diagnostics (stderr, merged here) may precede it.
  if [ "$rc" = "$want_rc" ] && grep -q "^$want_word" <<<"$out"; then ok "$label → exit $want_rc ($want_word)"
  else no "$label: want exit $want_rc + '$want_word', got exit $rc: $(tr '\n' ' ' <<<"$out" | head -c 260)"; fi
  if grep -q "$TOK" <<<"$out"; then no "$label: the token reached the probe's output"; fi
}

# --- the PASS arm -----------------------------------------------------------------------------------------
reset_fx; marker "$(iso_ago '4 days')"
{ row 3600 "$(okmsg)"; row 3601 "[luks-monitor] $(okmsg)"; row $((2 * D)) "$(okmsg)"; } | probe
run 0 PASS "T1 marker 4d old, latest row fresh LUKS, no red row since"
grep -q 'age_s=3600' <<<"$LAST_OUT" && ok "T1 the PASS line names the latest row's age" || no "T1 PASS line lost the evidence: $LAST_OUT"
[ "$(grep -c '^doppler$' "$WORK/calls")" = 1 ] && [ "$(grep -c '^bs$' "$WORK/calls")" = 1 ] && ok "T1 exactly one Doppler GET and one Better Stack read" || no "T1 unexpected call count: $(tr '\n' ' ' < "$WORK/calls")"

# a FAIL row that is OLDER than the marker is history the marker already superseded
reset_fx; marker "$(iso_ago '4 days')"
{ row 3600 "$(okmsg)"; row $((6 * D)) "FAIL (device_not_luks): device_type=ext4 mount_source=/dev/sdb"; } | probe
run 0 PASS "T2 a FAIL row from BEFORE the marker does not count (the marker was written after it)"

# --- the arms that must NOT reach exit 0 ---------------------------------------------------------------------
reset_fx; marker "$(iso_ago '2 days')"; row 3600 "$(okmsg)" | probe
run 2 "NOT YET" "T3 marker only 2 days old: the soak is still running"
reset_fx; marker "$(iso_ago '71 hours')"; row 3600 "$(okmsg)" | probe
run 2 "NOT YET" "T4 marker 71h old: just short of the soak"
reset_fx; printf '{"messages":["Could not find requested secret"],"success":false}' > "$WORK/fx/doppler.body"; echo 404 > "$WORK/fx/doppler.code"; row 3600 "$(okmsg)" | probe
run 2 "NOT YET" "T5 marker absent (404): no first green yet, or a red row reset the soak"
[ ! -s "$WORK/calls" ] || ! grep -q '^bs$' "$WORK/calls" && ok "T5 an absent marker never queries Better Stack" || no "T5 queried Better Stack without a marker"

reset_fx; marker "$(iso_ago '4 days')"
{ row 3600 "$(okmsg)"; row $((1 * D)) "FAIL (device_not_luks): device_type=ext4 mount_source=/dev/sdb"; } | probe
run 1 FAIL "T6 a red row since the marker breaks the soak"
reset_fx; marker "$(iso_ago '4 days')"
{ row 3600 "$(okmsg)"; row $((1 * D)) "OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable boot_id=$UA escrow=ok)"; } | probe
run 1 FAIL "T7 a MALFORMED verdict row since the marker (duplicate key) is red too"
reset_fx; marker "$(iso_ago '4 days')"; row 3600 "$(okmsg ext4)" | probe
run 1 FAIL "T8 the latest probe row is not crypto_LUKS"
reset_fx; marker "$(iso_ago '4 days')"; row 3600 "$(okmsg crypto_LUKS missing)" | probe
run 1 FAIL "T9 the latest probe row has no off-host header copy (escrow=missing)"
reset_fx; marker "$(iso_ago '4 days')"; row 97200 "$(okmsg)" | probe
run 1 FAIL "T10 the latest probe row is 27h old: the probe is dark"
reset_fx; marker "$(iso_ago '4 days')"; : | probe
run 1 FAIL "T11 zero probe rows: an empty answer is evidence of nothing live, never a PASS"
reset_fx; marker "$(iso_ago '4 days')"; echo '<html>502</html>' | probe
run 1 FAIL "T12 an unparseable body is not a PASS"

# --- unanswered reads are NOT YET, never a verdict --------------------------------------------------------------
reset_fx; marker "$(iso_ago '4 days')"; row 3600 "$(okmsg)" | probe; echo 503 > "$WORK/fx/bs.mode"
run 2 "NOT YET" "T13 Better Stack 503: a read fault is not a verdict"
echo timeout > "$WORK/fx/bs.mode"
run 2 "NOT YET" "T14 Better Stack timeout"
reset_fx; marker "$(iso_ago '4 days')"; row 3600 "$(okmsg)" | probe; echo 500 > "$WORK/fx/doppler.code"
run 2 "NOT YET" "T15 Doppler API 500 reading the marker"
reset_fx; echo 000 > "$WORK/fx/doppler.code"; row 3600 "$(okmsg)" | probe
run 2 "NOT YET" "T16 Doppler API unreachable"
reset_fx; printf '{"value":{"raw":"not-a-date","computed":"not-a-date"}}' > "$WORK/fx/doppler.body"; row 3600 "$(okmsg)" | probe
run 2 "NOT YET" "T17 a hand-written non-ISO marker is not graded"
reset_fx; marker "$(date -u -d '2 days' +%Y-%m-%dT%H:%M:%SZ)"; row 3600 "$(okmsg)" | probe
run 2 "NOT YET" "T18 a FUTURE-dated marker is not graded"

# --- credentials -------------------------------------------------------------------------------------------------
reset_fx; marker "$(iso_ago '4 days')"; row 3600 "$(okmsg)" | probe
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER; do
  run 3 "CANNOT ESTABLISH" "T19 $v empty" "$v="
done
run 3 "CANNOT ESTABLISH" "T20 a token carrying shell metacharacters is refused" 'DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER=x$(id)'
[ ! -s "$WORK/calls" ] && ok "T19/T20 a credential fault makes no request at all" || no "T19/T20 made a request: $(tr '\n' ' ' < "$WORK/calls")"
out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" MARKER_TOKEN="$TOK" BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com \
  BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER="$TOK" bash -x "$PROBE" 2>&1)"; rc=$?
if [ "$rc" = 78 ] && ! grep -q "$TOK" <<<"$out"; then ok "T21 a traced run with live credentials is refused (rc 78) and the token is not echoed"; else no "T21 xtrace not refused (rc $rc)"; fi

# --- structural: the probe uses the SHARED helper, never its own copy of the query or the parse --------------
code="$(grep -vE '^[[:space:]]*#' "$PROBE")"
if grep -q 'source "\$_w2l_lib"' <<<"$code" && grep -q 'w2l_fetch_probe' <<<"$code" && grep -q 'w2l_probe_verdict' <<<"$code" \
   && ! grep -qE 'betterstack-query\.sh|remote\(|s3Cluster|SYSLOG_IDENTIFIER|JSONExtract' <<<"$code"; then
  ok "T22 the probe loads scripts/lib/web2-luks-rows.sh and carries no query or parse of its own"
else
  no "T22 the probe re-implements the Better Stack query or parse instead of using the shared helper"
fi
if ! grep -qE '(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|secrets (set|delete))' <<<"$code"; then ok "T23 the probe only READS the marker (no write verb)"; else no "T23 the probe carries a write verb against the marker"; fi

# --- mutation proofs: each mutant must turn at least one arm RED. A mutant that lands nothing is a failure. ----
# The mutant runs from a sandbox tree (the probe finds its helper relative to its own path), so the repo is
# never written to.
MUT="$WORK/mut"
mutant() { # <label> <old> <new>
  local label="$1" old="$2" new="$3"
  rm -rf "$MUT"; mkdir -p "$MUT/scripts/followthroughs" "$MUT/scripts/lib"
  cp "$ROOT/scripts/betterstack-query.sh" "$MUT/scripts/"
  cp "$ROOT/scripts/lib/web2-luks-rows.sh" "$ROOT/scripts/lib/betterstack-read-classify.sh" "$MUT/scripts/lib/"
  cp "$PROBE" "$MUT/scripts/followthroughs/probe.sh"
  if ! python3 - "$MUT/scripts/followthroughs/probe.sh" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  then no "mutation $label: the edit did not land exactly once (a mutant that lands nothing proves nothing)"; return; fi
  run_arms_quiet "$MUT/scripts/followthroughs/probe.sh"
  if [ "$MUTANT_RED" -gt 0 ]; then ok "mutation $label → RED ($MUTANT_RED arm(s) disagree with the shipped verdict)"; else no "mutation $label stayed GREEN: no arm can see this defect"; fi
}
# the arms that guard exit 0, replayed against a mutant copy; counts the ones that now disagree with the shipped verdict
run_arms_quiet() {
  MUTANT_RED=0
  local probe_file="$1" rc out
  arm() { # <want-rc> <setup-fn>
    reset_fx; "$2"
    rc=0
    out="$(env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORK" FX="$WORK/fx" CALLS="$WORK/calls" MARKER_TOKEN="$TOK" BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com \
      BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER="$TOK" bash "$probe_file" 2>&1)" || rc=$?
    [ "$rc" = "$1" ] || MUTANT_RED=$((MUTANT_RED + 1))
  }
  a_young() { marker "$(iso_ago '2 days')"; row 3600 "$(okmsg)" | probe; }
  a_red() { marker "$(iso_ago '4 days')"; { row 3600 "$(okmsg)"; row $((1 * D)) "FAIL (device_not_luks): x"; } | probe; }
  a_ext4() { marker "$(iso_ago '4 days')"; row 3600 "$(okmsg ext4)" | probe; }
  a_stale() { marker "$(iso_ago '4 days')"; row 97200 "$(okmsg)" | probe; }
  a_pass() { marker "$(iso_ago '4 days')"; row 3600 "$(okmsg)" | probe; }
  arm 2 a_young; arm 1 a_red; arm 1 a_ext4; arm 1 a_stale; arm 0 a_pass
}
# control: the UNMUTATED probe agrees with every arm (otherwise "RED" below would just mean the arms are wrong)
run_arms_quiet "$PROBE"
if [ "$MUTANT_RED" -eq 0 ]; then ok "mutation control: the shipped probe satisfies every replayed arm"; else no "mutation control: the shipped probe disagrees with $MUTANT_RED replayed arm(s)"; fi
mutant "soak shortened to 0 days (a young marker passes)" 'SOAK_DAYS=3' 'SOAK_DAYS=0'
mutant "the red-row scan is skipped" 'if (( reds > 0 )); then' 'if false; then'
mutant "the red-row window is zero (rows since the marker are not counted)" 'w2l_reds_since "$tmp/probe.jsonl" "$age_s"' 'w2l_reds_since "$tmp/probe.jsonl" 0'
mutant "the latest-row verdict is ignored" 'if [[ "$verdict" != GREEN* ]]; then' 'if false; then'

echo
echo "web2-luks-live-6931.test.sh: $pass passed, $fail failed"
# Non-degeneracy: the arms above must actually have run (35 green; floor 33 = same two-assertion slack as the sibling harnesses).
[ "$((pass + fail))" -ge 33 ] || { echo "FAIL: only $((pass + fail)) assertions ran (<33) — the harness did not execute fully" >&2; exit 1; }
[ "$fail" -eq 0 ]
