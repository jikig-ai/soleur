#!/usr/bin/env bash
# Fixture suite for run-report-exit-first-contact-8076.sh.
#
# The probe's first draft read the pino fields at the TOP level of the decoded
# `raw`; live Better Stack rows nest them under `.message`, so AC18b could
# never FAIL and the probe would have closed #8076 through a real deny (#8074
# review). Every row here is the LIVE shape (double-encoded raw, payload under
# `.message`), and each guard has a must-FAIL / must-NOT-PASS fixture, so a
# decoder that reads the wrong level reds on this file, not on the tracker.
#
# Stubs: `gh` (PATH-shimmed, answers from $FIX files) and the Better Stack query
# script ($FT8076_QUERY, answers from $FIX/bs-<marker>.jsonl). No network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/run-report-exit-first-contact-8076.sh"
[[ -x "$PROBE" ]] || { printf 'FATAL: probe not executable at %s\n' "$PROBE" >&2; exit 2; }

PASS=0; FAIL=0; ASSERTED=0
pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1" >&2; }

# --- ADR-193 instrument self-test: both counters must move, reported directly ---
_p0=$PASS; _f0=$FAIL
pass "instrument"; fail "instrument"
if [[ $PASS -ne $((_p0 + 1)) || $FAIL -ne $((_f0 + 1)) ]]; then
  printf 'INSTRUMENT: pass()/fail() did not move their counters\n' >&2; exit 1
fi
PASS=$_p0; FAIL=$_f0

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
STUBS="$FIX/bin"; mkdir -p "$STUBS"

# gh stub: search/issues by label → $FIX/search-<label>.json; the closed
# community search → $FIX/search-closed.json; issue view 8027 → $FIX/state-8027.
cat > "$STUBS/gh" <<'GH'
#!/usr/bin/env bash
FIX="${FT8076_FIX:?}"
case "$1 $2" in
  "api search/issues"*)
    q="$2"
    if [[ "$q" == *"is:closed"* ]]; then f="$FIX/search-closed.json"
    elif [[ "$q" == *"scheduled-architecture-diagram-sync"* ]]; then f="$FIX/search-arch.json"
    elif [[ "$q" == *"scheduled-roadmap-review"* ]]; then f="$FIX/search-roadmap.json"
    else echo "stub: unknown query $q" >&2; exit 1; fi
    [[ -f "$f" ]] || { echo "stub: no fixture $f" >&2; exit 1; }
    # honour the probe's --jq by delegating to jq on the fixture
    shift 2; [[ "$1" == "--jq" ]] || { echo "stub: expected --jq" >&2; exit 1; }
    jq -c "$2" "$f" ;;
  "issue view")
    cat "$FIX/state-8027" ;;
  *) echo "stub: unhandled gh $*" >&2; exit 1 ;;
esac
GH
chmod +x "$STUBS/gh"

# Better Stack query stub: answers with $FIX/bs-<marker>.jsonl (empty if absent).
QSTUB="$FIX/betterstack-query.sh"
cat > "$QSTUB" <<'Q'
#!/usr/bin/env bash
FIX="${FT8076_FIX:?}"
marker=""
while [[ $# -gt 0 ]]; do case "$1" in --grep) marker="$2"; shift 2 ;; *) shift ;; esac; done
[[ -n "${BS_FAIL:-}" ]] && { echo "curl: (22) The requested URL returned error: 401" >&2; exit 22; }
f="$FIX/bs-$marker.jsonl"
[[ -f "$f" ]] && cat "$f"
exit 0
Q
chmod +x "$QSTUB"

# --- fixture builders ---------------------------------------------------------
# A LIVE-shaped Better Stack row: `raw` is a JSON STRING whose decoded value
# carries the pino line under `message`.
bs_row() { # $1 = message object JSON
  jq -cn --arg raw "$(jq -cn --argjson m "$1" '{message: $m, source_kind: "app"}')" '{dt: "2026-09-14T10:00:00Z", raw: $raw}'
}
cost_row() { bs_row '{"SOLEUR_CLAUDE_COST":true,"component":"claude-cost","source":"cron:cron-roadmap-review"}'; }
deny_row() { bs_row "{\"SOLEUR_CRON_FILING_DENY\":true,\"component\":\"cron-filing-deny\",\"fn\":\"$1\",\"count\":1,\"commands\":[\"gh issue create\"]}"; }
# The pre-fix shape: fields at the TOP level of the decoded raw — the probe
# must NOT read these (a top-level reader is exactly the vacuity being pinned).
top_level_deny_row() { jq -cn --arg raw "{\"SOLEUR_CRON_FILING_DENY\":true,\"component\":\"cron-filing-deny\",\"fn\":\"$1\"}" '{dt: "x", raw: $raw}'; }

issue() { # number, labels csv, body
  jq -cn --argjson n "$1" --arg labels "$2" --arg body "$3" '{number: $n, body: $body, labels: ($labels | split(",") | map(select(length > 0) | {name: .}))}'
}
search_file() { # file, issues...
  local f="$1"; shift
  printf '%s\n' "$@" | jq -cs '{items: .}' > "$f"
}

healthy() {
  search_file "$FIX/search-arch.json" "$(issue 9001 scheduled-architecture-diagram-sync 'ok')"
  search_file "$FIX/search-roadmap.json" "$(issue 9002 scheduled-roadmap-review 'ok')"
  search_file "$FIX/search-closed.json" "$(issue 7030 scheduled-community-monitor '## Community Monitor — 2026-08-01')" "$(issue 7051 scheduled-community-monitor 'digest')"
  printf 'OPEN\n' > "$FIX/state-8027"
  { cost_row; cost_row; } > "$FIX/bs-SOLEUR_CLAUDE_COST.jsonl"
  : > "$FIX/bs-SOLEUR_CRON_FILING_DENY.jsonl"
}

run_probe() { # sets RC and OUT in the caller's shell (no subshell capture of the verdict)
  OUT="$(cd "$HERE/../.." && env -i PATH="$STUBS:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" \
    FT8076_FIX="$FIX" FT8076_QUERY="$QSTUB" FT8076_DENY_LIMIT="${DENY_LIMIT:-200}" \
    GH_TOKEN="${GH_TOKEN_OVERRIDE-t}" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    ${BS_FAIL:+BS_FAIL=1} bash "$PROBE" 2>&1)"
  RC=$?
}
expect_rc() { # name, expected rc, actual rc, must-contain
  ASSERTED=$((ASSERTED + 1))
  if [[ "$3" == "$2" ]] && grep -qF -- "$4" <<<"$OUT"; then pass "$1 (rc=$3)"; else fail "$1: rc=$3 expected $2; output: $(printf '%s' "$OUT" | tail -3 | tr '\n' '|')"; fi
}

# --- T1 healthy: PASS ------------------------------------------------------------
healthy; run_probe; rc=$RC; expect_rc "T1 healthy first contact → PASS" 0 "$rc" "PASS: first live contact clean"

# --- T2 a deny row for a first-contact cron, NESTED under .message → FAIL ---------
healthy; { cost_row; deny_row cron-roadmap-review; deny_row cron-content-generator; } > "$FIX/bs-SOLEUR_CRON_FILING_DENY.jsonl"
run_probe; rc=$RC; expect_rc "T2 nested deny row for cron-roadmap-review → FAIL" 1 "$rc" "1 SOLEUR_CRON_FILING_DENY row(s) for the first-contact crons"

# --- T2′ garbage lines around the deny row must not turn it into a PASS ----------
healthy; { echo "WARNING: some stderr merged in"; deny_row cron-architecture-diagram-sync; echo "not json"; } > "$FIX/bs-SOLEUR_CRON_FILING_DENY.jsonl"
run_probe; rc=$RC; expect_rc "T2a non-JSON lines in the deny stream do not mask a deny" 1 "$rc" "1 SOLEUR_CRON_FILING_DENY row(s)"

# --- T2″ a deny for an UNRELATED cron is not a first-contact failure --------------
healthy; deny_row cron-content-generator > "$FIX/bs-SOLEUR_CRON_FILING_DENY.jsonl"
run_probe; rc=$RC; expect_rc "T2b deny for another cron → still PASS" 0 "$rc" "0 SOLEUR_CRON_FILING_DENY rows for the first-contact crons"

# --- T3 control dark (no claude-cost rows under .message) → FAIL, never PASS ------
healthy; : > "$FIX/bs-SOLEUR_CLAUDE_COST.jsonl"
run_probe; rc=$RC; expect_rc "T3 dark control → FAIL" 1 "$rc" "positive control"
# ... and a control whose rows carry the fields at the TOP level (the pre-fix
# shape) is ALSO dark: the decoder reads .message, nothing else.
healthy; top_level_deny_row x | sed 's/SOLEUR_CRON_FILING_DENY/SOLEUR_CLAUDE_COST/; s/cron-filing-deny/claude-cost/' > "$FIX/bs-SOLEUR_CLAUDE_COST.jsonl"
run_probe; rc=$RC; expect_rc "T3a top-level-shaped control rows read as dark" 1 "$rc" "positive control"

# --- T4 deny page at LIMIT → NOT YET (2), not a clean zero -----------------------
healthy; { deny_row cron-a; deny_row cron-b; deny_row cron-c; } > "$FIX/bs-SOLEUR_CRON_FILING_DENY.jsonl"
DENY_LIMIT=3 run_probe; rc=$RC; expect_rc "T4 deny page hit LIMIT → NOT YET" 2 "$rc" "hit its LIMIT"

# --- T5 missing GH_TOKEN → CANNOT ESTABLISH (3), not NOT YET ---------------------
healthy; GH_TOKEN_OVERRIDE='' run_probe; rc=$RC; expect_rc "T5 missing GH_TOKEN → CANNOT ESTABLISH" 3 "$rc" "GH_TOKEN is not injected"

# --- T6 a FAILED-bodied digest closed with the marker → FAIL ---------------------
healthy; search_file "$FIX/search-closed.json" "$(issue 7030 scheduled-community-monitor 'digest')" "$(issue 8027 scheduled-community-monitor 'Automated FAILED self-report from `cron-community-monitor`.')"
run_probe; rc=$RC; expect_rc "T6 marker-closed FAILED digest → FAIL" 1 "$rc" "FAILED-bodied"

# --- T7 #8027 closed → FAIL -----------------------------------------------------
healthy; printf 'CLOSED\n' > "$FIX/state-8027"
run_probe; rc=$RC; expect_rc "T7 #8027 closed → FAIL" 1 "$rc" "#8027 (FAILED self-report) is CLOSED"

# --- T8 no marker-closed digest at all → FAIL (the arm never fired) --------------
healthy; search_file "$FIX/search-closed.json"
run_probe; rc=$RC; expect_rc "T8 zero marker-closed digests → FAIL" 1 "$rc" "never attributed a close"

# --- T9 arch cron not fired yet → NOT YET --------------------------------------
healthy; search_file "$FIX/search-arch.json"
run_probe; rc=$RC; expect_rc "T9 no post-merge arch issue → NOT YET" 2 "$rc" "has not fired post-merge"

# --- T10 relabelled meta/machinery → FAIL --------------------------------------
healthy; search_file "$FIX/search-roadmap.json" "$(issue 9002 scheduled-roadmap-review,meta/machinery 'x')"
run_probe; rc=$RC; expect_rc "T10 relabelled run-report → FAIL" 1 "$rc" "carry meta/machinery"

# --- T11 Better Stack query fails → FAIL (never an absence) ---------------------
healthy; BS_FAIL=1 run_probe; rc=$RC; expect_rc "T11 query error → FAIL" 1 "$rc" "did not answer"

# --- T12 garbage search result → NOT YET ---------------------------------------
healthy; printf 'not json at all\n' > "$FIX/search-arch.json"
run_probe; rc=$RC; expect_rc "T12 unparseable search result → NOT YET" 2 "$rc" "NOT YET"

printf '\nrun-report-exit-first-contact-8076.test.sh: %d passed, %d failed (%d asserted)\n' "$PASS" "$FAIL" "$ASSERTED"
MIN_ASSERTIONS=14
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FLOOR: only %s assertions ran, expected at least %s\n' "$ASSERTED" "$MIN_ASSERTIONS" >&2; exit 1
fi
[[ "$PASS" -eq "$ASSERTED" && "$FAIL" -eq 0 ]] || exit 1
exit 0
