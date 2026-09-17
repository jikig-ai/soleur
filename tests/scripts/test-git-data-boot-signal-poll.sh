#!/usr/bin/env bash
# Tests for scripts/lib/git-data-boot-signal-poll.sh (#8178).
#
# The git-data birth/replace boot poll is the ONLY in-job verification that the host
# actually booted, and it had never read a row: 20/20 rc=22 on both real dispatches,
# with the cause unrecoverable from the run log because stderr went to /dev/null.
# This suite drives the poll hermetically — no network, no doppler, no live table —
# through a reader shim resolved via BETTERSTACK_QUERY_SCRIPT.
#
# TWO SHIMS ARE REQUIRED, NOT ONE. `doppler` is not installed on a workstation or in
# the hermetic environment, so shimming only the reader would change the argument of a
# command that never runs and every row would grade rc=127 -> `other`. `doppler` is
# stubbed as a shell function, exactly as the cutover driver does.
#
# THE SHIM READS BS_TABLE / BS_TABLE_S3 FROM THE ENVIRONMENT. betterstack-query.sh
# substitutes those tokens internally, so the SQL a shim receives is byte-identical for
# the pinned and the default table — a SQL-matching stub could not otherwise see which
# source was selected, and the table pin is load-bearing (#7772).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/git-data-boot-signal-poll.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"
pass=0; fail=0
FAILURES=()

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $label"
  else fail=$((fail + 1)); FAILURES+=("$label"); echo "[FAIL] $label $detail" >&2; fi
}

# INSTRUMENT SELF-TEST (ADR-193): drive both reporter arms, require both counters to
# move, then unwind. A suite whose reporter is stuck on the pass branch reports a clean
# run having asserted nothing.
_report "instrument self-test (pass arm)" ok
_report "instrument self-test (fail arm)" bad "expected — unwound below"
if (( pass < 1 || fail < 1 )); then
  printf 'FAIL: instrument self-test did not move both counters\n' >&2; exit 1
fi
pass=0; fail=0; FAILURES=()

[[ -r "$LIB" ]] || { printf 'FAIL: library not readable at %s\n' "$LIB" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
for fn in git_data_boot_read git_data_boot_answered git_data_boot_poll git_data_boot_poll_decide; do
  declare -F "$fn" >/dev/null || { printf 'FAIL: %s not defined after sourcing\n' "$fn" >&2; exit 1; }
done

SANDBOX="$(mktemp -d -t gdbootpoll.XXXXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

# mkshim <name> <spec-file>
# The spec file holds one line per poll: "<rc>|<stdout>|<stderr>". The last line
# repeats for any poll beyond its length, so a 1-line spec is a constant reader.
mkshim() {
  # SPLIT DELIBERATELY: `local` expands every argument BEFORE the builtin runs, so
  # `local name="$1" d="$SANDBOX/$name"` expands $name while it is still unbound and
  # dies under `set -u`. The later assignment must be its own statement.
  local name="$1" spec="$2"
  local d="$SANDBOX/$name"
  mkdir -p "$d"
  cp "$spec" "$d/spec"
  : > "$d/count"
  cat > "$d/reader.sh" <<'SHIM'
#!/usr/bin/env bash
# Hermetic betterstack-query.sh stand-in. Answers per the spec line for this poll.
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
n=$(( $(wc -l < "$d/count") + 1 )); echo "x" >> "$d/count"
total=$(wc -l < "$d/spec")
(( n > total )) && n=$total
line="$(sed -n "${n}p" "$d/spec")"
rc="${line%%|*}"; rest="${line#*|}"
sout="${rest%%|*}"; serr="${rest#*|}"
# Record the table the caller pinned: betterstack-query.sh substitutes BS_TABLE
# internally, so the SQL alone cannot reveal it.
printf '%s\n' "BS_TABLE=${BS_TABLE:-<unset>} BS_TABLE_S3=${BS_TABLE_S3:-<unset>}" >> "$d/tables"
printf '%s\n' "$*" >> "$d/argv"
[[ -n "$sout" ]] && printf '%b\n' "$sout"
[[ -n "$serr" ]] && printf '%b\n' "$serr" >&2
exit "$rc"
SHIM
  chmod +x "$d/reader.sh"
  printf '%s' "$d"
}

# run_poll <shimdir> <max_polls> <interval_s> <anchor>  -> writes combined output to $SANDBOX/out
run_poll() {
  local d="$1" mx="$2" iv="$3" anchor="$4" rc=0
  (
    export BETTERSTACK_QUERY_SCRIPT="$d/reader.sh"
    export BS_TABLE="t520508_soleur_git_data_prd_logs"
    export BS_TABLE_S3="t520508_soleur_git_data_prd_s3"
    export RUNNER_TEMP="$d"
    # doppler is not installed here; the real step runs the reader THROUGH it.
    doppler() { while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done; shift || true; "$@"; }
    export -f doppler
    # shellcheck source=/dev/null
    . "$LIB"
    git_data_boot_poll "$mx" "$iv" "$anchor"
  ) > "$SANDBOX/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}

spec() { local f="$SANDBOX/spec.$RANDOM"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }
outq() { grep -qF "$1" "$SANDBOX/out"; }

have() { # $1=label $2=needle
  if outq "$2"; then _report "$1" ok; else _report "$1" bad "missing: $2 | got: $(tr '\n' ' ' < "$SANDBOX/out" | cut -c1-240)"; fi
}
havent() { # $1=label $2=needle-that-must-be-absent
  if outq "$2"; then _report "$1" bad "present but must not be: $2"; else _report "$1" ok; fi
}

# The anchor is an EPOCH, matching the SQL's fromUnixTimestamp(). The row below is
# 17 minutes after it; OLDROW is four days before.
ANCHOR=1789398600
ROW='{"dt":"2026-09-14 15:27:24.816663","stage":"boot_complete","host":"soleur-git-data"}'
OLDROW='{"dt":"2026-09-10 01:00:00.000000","stage":"boot_complete","host":"soleur-git-data"}'

# ── S1  The arm #8178 is actually about: rc=22, body matching no marker ──────
d=$(mkshim s1 "$(spec '22||curl: (22) The requested URL returned error: 403')")
run_poll "$d" 3 0 "$ANCHOR" >/dev/null
have    "S1a unmatched rc=22 -> verdict unreadable"      "VERDICT=unreadable"
have    "S1b names the 'other' classification"           "class=other"
have    "S1c prints the answered/total accounting"       "answered=0/3"
havent  "S1d does NOT claim the host was silent"         "VERDICT=silent"

# ── S2  rc=22 auth body: classify, report length, NEVER the body ─────────────
AUTHBODY='Code: 516. DB::Exception: u_synthetic_9f3: Authentication failed'
d=$(mkshim s2 "$(spec "22|${AUTHBODY}|curl: (22) error")")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
have    "S2a auth body -> credentials-rejected"          "class=credentials-rejected"
have    "S2b reports the body's byte length"             "body_bytes="
havent  "S2c NEVER prints the username from the body"    "u_synthetic_9f3"
havent  "S2d NEVER prints the body text"                 "Authentication failed"

# ── S3  Answered-but-empty for every poll -> silent (host, not read, at fault)
d=$(mkshim s3 "$(spec '0||')")
run_poll "$d" 3 0 "$ANCHOR" >/dev/null
have    "S3a answered empty -> VERDICT=silent"           "VERDICT=silent"
have    "S3b accounting shows every read answered"       "answered=3/3"
havent  "S3c does NOT route to credential remediation"   "credentials-rejected"

# ── S4  Failures then an answered final read with a row -> received ──────────
d=$(mkshim s4 "$(spec '22||err' '22||err' "0|${ROW}|")")
run_poll "$d" 3 0 "$ANCHOR" >/dev/null
have    "S4a row after anchor on final read -> received" "VERDICT=received"

# ── S5  Answered empties then a FAILED final read -> unreadable ──────────────
# The verdict is anchored on the FINAL read: each read queries the whole window, so
# demanding N clean reads would let one late 5xx abort an otherwise-verified birth.
d=$(mkshim s5 "$(spec '0||' '0||' '22||err')")
run_poll "$d" 3 0 "$ANCHOR" >/dev/null
have    "S5a failed final read -> unreadable"            "VERDICT=unreadable"
have    "S5b accounting reports 2/3 answered"            "answered=2/3"

# ── S6  THE MATCH-BUFFER DEFECT, asserted directly ───────────────────────────
# betterstack-query.sh echoes the failing query back on its error path, and that query
# CONTAINS the literal `boot_complete`. If stderr reaches the match buffer, poll 1
# reports the boot signal as received over a host that never booted. stdout is empty,
# stderr carries the echoed query, rc=22.
d=$(mkshim s6 "$(spec "22||betterstack-query.sh: query failed: SELECT ... stage = 'boot_complete' ...")")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
havent  "S6a stderr echo must NOT be read as received"   "VERDICT=received"
have    "S6b it is an unreadable read, not a host verdict" "VERDICT=unreadable"

# ── S6b THE SAME DEFECT ON THE rc=0 PATH, which is the harder half ───────────
# S6 uses rc=22, so the rc gate alone blocks it and the fixture cannot tell whether the
# stdout/stderr SPLIT is doing any work. This one answers rc=0 with EMPTY stdout and a
# stderr line containing the literal `boot_complete`: if the two streams were merged,
# the match buffer would hold that line on a read the rc gate considers good. It must
# still not be `received` — here the SHAPE gate is what refuses it, because the line
# does not start `{"dt":`. Both gates are independently sufficient, and this fixture is
# what makes that claim measurable instead of asserted.
d=$(mkshim s6b "$(spec "0||betterstack-query.sh: query failed: ... stage = 'boot_complete' ...")")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
havent  "S6c rc=0 + boot_complete on STDERR is not received" "VERDICT=received"

# ── S7  HTTP 200 carrying a mid-stream exception is NOT an answer ────────────
d=$(mkshim s7 "$(spec "0|${ROW}\nCode: 241. DB::Exception: Memory limit exceeded|")")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
havent  "S7a partial answer must NOT be received"        "VERDICT=received"

# ── S8  A row dated BEFORE the anchor is a previous generation, not this boot ─
d=$(mkshim s8 "$(spec "0|${OLDROW}|")")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
havent  "S8a pre-anchor row must NOT be received"        "VERDICT=received"
have    "S8b it reads as silent (answered, no qualifying row)" "VERDICT=silent"

# ── S9  An empty anchor fails CLOSED ─────────────────────────────────────────
rc9=$(run_poll "$(mkshim s9 "$(spec "0|${ROW}|")")" 2 0 "")
if [[ "$rc9" != "0" ]]; then _report "S9a empty BOOT_TRAIL_SINCE fails closed" ok
else _report "S9a empty BOOT_TRAIL_SINCE fails closed" bad "returned 0 — an unanchored query can match a destroyed host's row"; fi
havent  "S9b and does not report received"               "VERDICT=received"

# ── S10 ADR-192: CLUSTER_DOESNT_EXIST names the PRODUCER, not the credential ─
d=$(mkshim s10 "$(spec '22|Code: 170. DB::Exception: CLUSTER_DOESNT_EXIST|err')")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
have    "S10a CLUSTER_DOESNT_EXIST -> table-missing"     "class=table-missing"
havent  "S10b must NOT blame the credentials"            "class=credentials-rejected"

# ── S11 The two wiring faults this change can itself introduce ───────────────
d=$(mkshim s11a "$(spec '3||')")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
have    "S11a rc=3 -> credentials-absent"                "class=credentials-absent"
d=$(mkshim s11b "$(spec '1||Doppler Error: unable to authenticate')")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
have    "S11b rc=1 -> reader-exit-1 (names DOPPLER_TOKEN)" "class=reader-exit-1"

# ── S12 NFR2 scrub: quoted values and vendor hostnames never reach the log ───
d=$(mkshim s12 "$(spec "22|body|curl: could not resolve 'secret-value-xyz' at ingest-99.betterstackdata.com")")
run_poll "$d" 2 0 "$ANCHOR" >/dev/null
havent  "S12a quoted value is scrubbed from stderr"      "secret-value-xyz"
havent  "S12b vendor hostname is scrubbed"               "betterstackdata.com"

# ── S13 The table pin actually reaches the reader (#7772) ────────────────────
d=$(mkshim s13 "$(spec '0||')")
run_poll "$d" 1 0 "$ANCHOR" >/dev/null
if grep -q 'BS_TABLE=t520508_soleur_git_data_prd_logs' "$d/tables" 2>/dev/null; then
  _report "S13a the pinned table reaches the reader" ok
else _report "S13a the pinned table reaches the reader" bad "tables file: $(cat "$d/tables" 2>/dev/null)"; fi

# ── S14 The loop honours max_polls (budget is real, not decorative) ──────────
d=$(mkshim s14 "$(spec '22||err')")
run_poll "$d" 4 0 "$ANCHOR" >/dev/null
n14=$(wc -l < "$d/count")
if [[ "$n14" == "4" ]]; then _report "S14a max_polls honoured exactly" ok
else _report "S14a max_polls honoured exactly" bad "made $n14 reads, expected 4"; fi

# ── S15 decide() is a pure function drivable into every arm ──────────────────
[[ "$(git_data_boot_poll_decide yes yes)" == "received"   ]] && _report "S15a decide(found,answered)=received" ok   || _report "S15a decide received" bad
[[ "$(git_data_boot_poll_decide no  yes)" == "silent"     ]] && _report "S15b decide(no-row,answered)=silent" ok     || _report "S15b decide silent" bad
[[ "$(git_data_boot_poll_decide no  no )" == "unreadable" ]] && _report "S15c decide(no-row,unanswered)=unreadable" ok || _report "S15c decide unreadable" bad

# ── Assertion floor: printf + exit, never through the helper it backstops ────
_total=$((pass + fail))
_FLOOR=29
if (( _total < _FLOOR )); then
  printf 'FAIL: assertion floor: %d ran, floor %d — the harness lost coverage rather than passing it\n' "$_total" "$_FLOOR" >&2
  exit 1
fi
if (( ${#FAILURES[@]} != fail )); then
  printf 'FAIL: ledger drift: %d entries vs fail counter %d\n' "${#FAILURES[@]}" "$fail" >&2
  exit 1
fi
printf 'git-data-boot-signal-poll: %d passed, %d failed (%d assertions)\n' "$pass" "$fail" "$_total"
exit $(( fail > 0 ))
