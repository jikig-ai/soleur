#!/usr/bin/env bash
# Tests for scripts/lib/git-data-boot-signal-poll.sh (#8178), and for the two workflow
# steps that call it.
#
# The git-data birth/replace boot poll is the only in-job evidence that the host booted,
# and before #8178 it had never read a row. This suite drives it hermetically — no
# network, no Doppler, no live table — and pins the SUT, not the harness:
#
#   * `doppler` is a PATH executable that RECORDS its argv, so the credential route
#     (`-p soleur -c prd_terraform --only-secrets …`) is asserted, not assumed.
#   * the reader shim records the SQL it was handed and the table the LIBRARY pinned. The
#     harness exports a WRONG table on purpose; only the library's own pin can win.
#   * the library runs in a child `bash -eo pipefail`, the shell a workflow step uses, and
#     never in a `||` context (which would switch errexit off and hide an abort).
#   * each workflow poll step's real `run:` body is extracted and executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/git-data-boot-signal-poll.sh"
WF="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
export TMPDIR="${TMPDIR:-/var/tmp}"
pass=0; fail=0
FAILURES=()

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $label"
  else fail=$((fail + 1)); FAILURES+=("$label"); echo "[FAIL] $label $detail" >&2; fi
}

# INSTRUMENT SELF-TEST (ADR-193): drive both reporter arms, require both counters to
# move, then unwind.
_report "instrument self-test (pass arm)" ok
_report "instrument self-test (fail arm)" bad "expected — unwound below"
if (( pass < 1 || fail < 1 )); then
  printf 'FAIL: instrument self-test did not move both counters\n' >&2; exit 1
fi
pass=0; fail=0; FAILURES=()

[[ -r "$LIB" ]] || { printf 'FAIL: library not readable at %s\n' "$LIB" >&2; exit 1; }
[[ -r "$WF" ]]  || { printf 'FAIL: workflow not readable at %s\n' "$WF" >&2; exit 1; }

SANDBOX="$(mktemp -d -t gdbootpoll.XXXXXXXX)"
trap 'rm -rf "$SANDBOX"' EXIT

# The doppler stand-in: records its argv, then runs whatever follows `--`.
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/doppler" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOPPLER_ARGV_LOG:?}"
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
shift || true
exec "$@"
STUB
chmod +x "$SANDBOX/bin/doppler"
# The timeout stand-in: records its argv, then runs the real timeout.
_real_timeout="$(command -v timeout)"
cat > "$SANDBOX/bin/timeout" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${TIMEOUT_ARGV_LOG:?}"
exec "$_real_timeout" "\$@"
STUB
chmod +x "$SANDBOX/bin/timeout"

# mkshim <name> <spec-file>
# The spec file holds one line per poll: "<rc>|<stdout>|<stderr>". The last line repeats
# for any poll beyond its length. The shim records the SQL ($1) and the table it received.
mkshim() {
  local name="$1" spec="$2"
  local d="$SANDBOX/$name"
  mkdir -p "$d"
  cp "$spec" "$d/spec"
  : > "$d/count"; : > "$d/doppler_argv"; : > "$d/timeout_argv"
  cat > "$d/reader.sh" <<'SHIM'
#!/usr/bin/env bash
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
n=$(( $(wc -l < "$d/count") + 1 )); echo "x" >> "$d/count"
total=$(wc -l < "$d/spec")
(( n > total )) && n=$total
line="$(sed -n "${n}p" "$d/spec")"
rc="${line%%|*}"; rest="${line#*|}"
sout="${rest%%|*}"; serr="${rest#*|}"
printf '%s\n' "BS_TABLE=${BS_TABLE:-<unset>} BS_TABLE_S3=${BS_TABLE_S3:-<unset>}" >> "$d/tables"
printf '%s\n' "DOPPLER_TOKEN=${DOPPLER_TOKEN:-<unset>} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-<unset>}" >> "$d/env"
printf '%s\n' "$1" >> "$d/sql"
[[ -n "$sout" ]] && printf '%b\n' "$sout"
[[ -n "$serr" ]] && printf '%b\n' "$serr" >&2
exit "$rc"
SHIM
  chmod +x "$d/reader.sh"
  printf '%s' "$d"
}

# in_step <shimdir> <script>  — runs <script> in the shell a workflow step uses, with the
# library sourced and the shim wired. Output -> $SANDBOX/out. Prints the child's exit code.
# The harness exports a WRONG table: the library must pin its own.
in_step() {
  local d="$1" script="$2" rc=0
  env PATH="$SANDBOX/bin:$PATH" DOPPLER_ARGV_LOG="$d/doppler_argv" TIMEOUT_ARGV_LOG="$d/timeout_argv" \
      AWS_SECRET_ACCESS_KEY=synthetic-r2-secret \
      BETTERSTACK_QUERY_SCRIPT="$d/reader.sh" BS_TABLE=wrong_table BS_TABLE_S3=wrong_table_s3 \
      DOPPLER_TOKEN="${STEP_DOPPLER_TOKEN-dp.st.synthetic}" LIB="$LIB" \
      bash --noprofile --norc -eo pipefail -c ". \"\$LIB\"; $script" > "$SANDBOX/out" 2>&1 || rc=$?
  printf '%s' "$rc"
}
# run_poll <shimdir> <max_polls> <anchor> — the poll loop alone, interval 0.
run_poll() { in_step "$1" "git_data_boot_poll $2 0 '$3'; echo POLL_RC=\$?"; }

spec() { local f="$SANDBOX/spec.$RANDOM$RANDOM"; printf '%s\n' "$@" > "$f"; printf '%s' "$f"; }
outq() { grep -qF -- "$1" "$SANDBOX/out"; }

have() { # $1=label $2=needle
  if outq "$2"; then _report "$1" ok; else _report "$1" bad "missing: $2 | got: $(tr '\n' ' ' < "$SANDBOX/out" | cut -c1-300)"; fi
}
havent() { # $1=label $2=needle-that-must-be-absent
  if outq "$2"; then _report "$1" bad "present but must not be: $2"; else _report "$1" ok; fi
}
rc_is() { # $1=label $2=want $3=got
  if [[ "$3" == "$2" ]]; then _report "$1" ok; else _report "$1" bad "rc=$3, want $2"; fi
}

# HELPER CANARIES. The reporter self-test proves _report works; these prove have(),
# havent() and rc_is() can each still say NO. Each is driven with an assertion that must
# fail, required to have recorded exactly one failure, then unwound.
printf 'canary-present\n' > "$SANDBOX/out"
for _canary in "have x __absent_needle__" "havent x canary-present" "rc_is x 0 1"; do
  _before=$fail
  # shellcheck disable=SC2086
  $_canary >/dev/null 2>&1
  if (( fail != _before + 1 )); then
    printf 'FAIL: helper canary "%s" did not record a failure — that helper cannot fail\n' "$_canary" >&2; exit 1
  fi
  fail=$((fail - 1)); unset 'FAILURES[-1]'
done

ANCHOR=1789398600
ROW='{"dt":"2026-09-14 15:27:24.816663","stage":"boot_complete","host":"soleur-git-data","luks_mounted":"yes","repo_root":"yes","hooks_path":"yes","provision":"yes","nft_metadata_drop":"yes","luks_reopen_unit":"yes","fence_on_mapper":"yes","erasure_probe":"yes","plaintext_empty":"yes","plaintext_volume":"present","served_repos":"0","plaintext_journal":"dirty"}'

# ── S1  rc=22 with no marker: unreadable, and the failure SAYS why ───────────
d=$(mkshim s1 "$(spec '22||curl: (22) The requested URL returned error: 403')")
run_poll "$d" 3 "$ANCHOR" >/dev/null
have    "S1a unmatched rc=22 -> verdict unreadable"       "VERDICT=unreadable"
have    "S1b names the 'other' classification"            "class=other"
have    "S1c prints the answered/total accounting"        "answered=0/3"
have    "S1d the reader's stderr REACHES the log"          "stderr: curl: (22) The requested URL returned error: 403"
have    "S1e body_bytes is the stdout length"              "body_bytes=0"
have    "S1f the rc is in the per-poll line"               "read FAILED rc=22"
have    "S1g the poll survives errexit and returns 0"      "POLL_RC=0"
havent  "S1h does NOT claim the host was silent"           "VERDICT=silent"

# ── S2  rc=22 auth body: classify, report length, NEVER the body ─────────────
AUTHBODY='Code: 516. DB::Exception: u_synthetic_9f3: Authentication failed'
d=$(mkshim s2 "$(spec "22|${AUTHBODY}|curl: (22) error")")
run_poll "$d" 2 "$ANCHOR" >/dev/null
have    "S2a auth body -> credentials-rejected"           "class=credentials-rejected"
have    "S2b reports the body's byte length"               "body_bytes=65"
havent  "S2c NEVER prints the username from the body"      "u_synthetic_9f3"
havent  "S2d NEVER prints the body text"                   "Authentication failed"

# ── S3  Answered-but-empty for every poll -> silent ──────────────────────────
d=$(mkshim s3 "$(spec '0||')")
run_poll "$d" 3 "$ANCHOR" >/dev/null
have    "S3a answered empty -> VERDICT=silent"            "VERDICT=silent"
have    "S3b accounting shows every read answered"        "answered=3/3"

# ── S4  Failures then an answered final read with a row -> received ──────────
d=$(mkshim s4 "$(spec '22||err' '22||err' "0|${ROW}|")")
run_poll "$d" 3 "$ANCHOR" >/dev/null
have    "S4a row on final read -> received"               "VERDICT=received"

# ── S4b THE LOOP STOPS on received (no 10-minute tail on a healthy boot) ──────
d=$(mkshim s4b "$(spec "0|${ROW}|")")
run_poll "$d" 3 "$ANCHOR" >/dev/null
n=$(wc -l < "$d/count")
rc_is "S4b one read, then stop"                           1 "$n"

# ── S4c exactly ONE row is exported, even if two come back ───────────────────
d=$(mkshim s4c "$(spec "0|${ROW}\n${ROW/luks_mounted\":\"yes/luks_mounted\":\"no}|")")
in_step "$d" "git_data_boot_poll 1 0 $ANCHOR >/dev/null; printf 'ROWLINES=%s\n' \"\$(printf '%s\n' \"\$GIT_DATA_BOOT_ROW\" | wc -l)\"" >/dev/null
have    "S4c GIT_DATA_BOOT_ROW is a single row"           "ROWLINES=1"

# ── S5  Answered empties then a FAILED final read -> unreadable, 2/3 answered ─
d=$(mkshim s5 "$(spec '0||' '0||' '22||err')")
run_poll "$d" 3 "$ANCHOR" >/dev/null
have    "S5a failed final read -> unreadable"             "VERDICT=unreadable"
have    "S5b accounting reports 2/3 answered"             "answered=2/3"

# ── S6  A reader error line carrying `boot_complete` never reads as received ──
# rc=22 case: the rc gate refuses it. rc=0 case: stdout is empty and the line is on
# STDERR, so only the stdout/stderr split keeps it out of the match.
d=$(mkshim s6 "$(spec "22||reader: bad query ... stage = 'boot_complete' ...")")
run_poll "$d" 2 "$ANCHOR" >/dev/null
havent  "S6a rc=22 + boot_complete on stderr is not received" "VERDICT=received"
d=$(mkshim s6b "$(spec "0||reader: note ... stage = 'boot_complete' ...")")
run_poll "$d" 2 "$ANCHOR" >/dev/null
havent  "S6b rc=0 + boot_complete on STDERR is not received"  "VERDICT=received"
have    "S6c it reads as silent (answered, empty stdout)"      "VERDICT=silent"

# ── S7  HTTP 200 carrying a mid-stream exception is NOT an answer ────────────
d=$(mkshim s7 "$(spec "0|${ROW}\nCode: 241. DB::Exception: Memory limit exceeded|")")
run_poll "$d" 2 "$ANCHOR" >/dev/null
havent  "S7a partial answer must NOT be received"         "VERDICT=received"
have    "S7b it is unreadable"                            "VERDICT=unreadable"

# ── S8  THE SQL the reader receives: anchor, host, stage, both arms, one row ──
d=$(mkshim s8 "$(spec '0||')")
run_poll "$d" 1 "$ANCHOR" >/dev/null
for frag in "WHERE dt > fromUnixTimestamp(${ANCHOR})" \
            "JSONExtractString(raw,'host_name') = 'soleur-git-data'" \
            "JSONExtractString(raw,'stage') = 'boot_complete'" \
            's3Cluster(primary, $BS_TABLE_S3)' \
            'remote($BS_TABLE)' \
            'ORDER BY dt DESC LIMIT 1'; do
  if grep -qF -- "$frag" "$d/sql"; then _report "S8 SQL carries: $frag" ok
  else _report "S8 SQL carries: $frag" bad "sql: $(tr '\n' ' ' < "$d/sql" | cut -c1-300)"; fi
done

# ── S9  A missing or malformed anchor fails CLOSED, before any read ──────────
for bad in "" "0" "abc" "178939860" "1789398600; DROP"; do
  d=$(mkshim "s9_$RANDOM" "$(spec "0|${ROW}|")")
  rc9=$(in_step "$d" "git_data_boot_poll 2 0 '$bad'")
  n=$(wc -l < "$d/count")
  if [[ "$rc9" == "2" && "$n" == "0" ]] && outq "VERDICT=refused-no-anchor"; then
    _report "S9 anchor '$bad' refused before any read" ok
  else _report "S9 anchor '$bad' refused before any read" bad "rc=$rc9 reads=$n"; fi
done

# ── S10 CLUSTER_DOESNT_EXIST names the reader's connection (#7867) ───────────
d=$(mkshim s10 "$(spec '22|Code: 701. DB::Exception: (CLUSTER_DOESNT_EXIST)|err')")
run_poll "$d" 2 "$ANCHOR" >/dev/null
have    "S10a CLUSTER_DOESNT_EXIST -> source-not-in-connection" "class=source-not-in-connection"

# ── S11 The wiring faults this change can itself introduce ───────────────────
d=$(mkshim s11a "$(spec '3||')")
run_poll "$d" 2 "$ANCHOR" >/dev/null
have    "S11a rc=3 -> credentials-absent"                 "class=credentials-absent"
d=$(mkshim s11b "$(spec '1||Doppler Error: unable to authenticate')")
run_poll "$d" 2 "$ANCHOR" >/dev/null
have    "S11b rc=1 -> reader-exit-1"                      "class=reader-exit-1"
d=$(mkshim s11c "$(spec '124||')")
run_poll "$d" 1 "$ANCHOR" >/dev/null
have    "S11c rc=124 (read timed out) -> transport"       "class=transport"

# ── S12 Scrub: quoted values and vendor hosts never reach the log; the rest does
d=$(mkshim s12 "$(spec "22|body|curl: could not resolve 'secret-value-xyz' at Ingest-99.BetterStackData.com")")
run_poll "$d" 2 "$ANCHOR" >/dev/null
havent  "S12a quoted value is scrubbed from stderr"       "secret-value-xyz"
havent  "S12b vendor hostname is scrubbed (any case)"     "BetterStackData.com"
have    "S12c the rest of the stderr line is retained"    "stderr: curl: could not resolve '<redacted>' at <host>"

# ── S13 The credential route and the table pin are the LIBRARY's ─────────────
d=$(mkshim s13 "$(spec '0||')")
run_poll "$d" 1 "$ANCHOR" >/dev/null
if grep -qF -- "run -p soleur -c prd_terraform --only-secrets BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD --no-exit-on-missing-only-secrets -- env -u DOPPLER_TOKEN -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY bash" "$d/doppler_argv"; then
  _report "S13a reads via doppler prd_terraform, only-secrets, missing keys reach the reader" ok
else _report "S13a reads via doppler prd_terraform, only-secrets, missing keys reach the reader" bad "argv: $(cat "$d/doppler_argv")"; fi
if grep -qE -- '^-k 5 45 doppler run ' "$d/timeout_argv"; then
  _report "S13c the 45 s cap wraps the WHOLE read, doppler included" ok
else _report "S13c the 45 s cap wraps the WHOLE read, doppler included" bad "timeout argv: $(cat "$d/timeout_argv")"; fi
if grep -qx 'DOPPLER_TOKEN=<unset> AWS_SECRET_ACCESS_KEY=<unset>' "$d/env"; then
  _report "S13d the reader does not inherit the Doppler token or the R2 key" ok
else _report "S13d the reader does not inherit the Doppler token or the R2 key" bad "env: $(cat "$d/env")"; fi
if grep -qx 'BS_TABLE=t520508_soleur_git_data_prd_logs BS_TABLE_S3=t520508_soleur_git_data_prd_s3' "$d/tables"; then
  _report "S13b the library's table pin beats an inherited value" ok
else _report "S13b the library's table pin beats an inherited value" bad "tables: $(cat "$d/tables")"; fi

# ── S14 The loop honours max_polls exactly ───────────────────────────────────
d=$(mkshim s14 "$(spec '22||err')")
run_poll "$d" 4 "$ANCHOR" >/dev/null
rc_is "S14a max_polls honoured exactly"                   4 "$(wc -l < "$d/count")"

# ── S15 decide() arms ────────────────────────────────────────────────────────
# shellcheck source=scripts/lib/git-data-boot-signal-poll.sh
. "$LIB"
rc_is "S15a decide(found,answered)=received"      received   "$(git_data_boot_poll_decide yes yes)"
rc_is "S15b decide(no-row,answered)=silent"       silent     "$(git_data_boot_poll_decide no yes)"
rc_is "S15c decide(no-row,unanswered)=unreadable" unreadable "$(git_data_boot_poll_decide no no)"
# S15d (#8211) every TERMINAL name is PROJECTED by the SQL the reader actually received (S8's
# capture). A name the invariant loop requires but the SELECT drops is absent from every real
# row, so a production boot would read as drift however healthy it was.
for _f in $GIT_DATA_BOOT_TERMINAL; do
  if grep -qE -- "JSONExtractString\\(raw,'${_f}'\\)[[:space:]]+AS ${_f}(,|$)" "$SANDBOX/s8/sql"; then _report "S15d SQL projects terminal ${_f}" ok
  else _report "S15d SQL projects terminal ${_f}" bad "sql: $(tr '\n' ' ' < "$SANDBOX/s8/sql" | cut -c1-300)"; fi
done

# ── S16 The poll leaves the caller's shell options alone ─────────────────────
d=$(mkshim s16 "$(spec '22||err' '0||')")
in_step "$d" "set +e; git_data_boot_poll 2 0 $ANCHOR >/dev/null; case \"\$-\" in *e*) echo ERREXIT=on ;; *) echo ERREXIT=off ;; esac" >/dev/null
have    "S16a errexit is still off after the poll"        "ERREXIT=off"

# ── S17 git_data_boot_verify: the whole step, both kinds ─────────────────────
# Called EXACTLY as the workflow calls it: `rc=0; git_data_boot_verify … || rc=$?`. That
# `||` switches errexit off inside the function, so every failure path must return non-zero
# on its own; a test that relied on errexit would pass for the wrong reason.
vcall() { printf 'rc=0; git_data_boot_verify %s || rc=$?; echo STEP_RC=$rc; exit $rc' "$1"; }
verify() { # <label> <kind> <apply> <spec…>  -> rc
  local label="$1" kind="$2" apply="$3"; shift 3
  local d; d=$(mkshim "v_$label" "$(spec "$@")")
  in_step "$d" "$(vcall "$kind 2 0 $ANCHOR $apply")"
}
rc_is "S17a received + all invariants -> 0" 0 "$(verify a birth success "0|${ROW}|")"
have  "S17b says the boot signal was received" "boot signal received"
rc_is "S17c replace received -> 0" 0 "$(verify c replace success "0|${ROW}|")"
rc_is "S17d luks_mounted=no -> 1" 1 "$(verify d replace success "0|${ROW/luks_mounted\":\"yes/luks_mounted\":\"no}|")"
have  "S17e names the unmet invariant" "luks_mounted=no"
havent "S17e2 and does not go on to report success" "boot signal received"
rc_is "S17f provision missing -> 1" 1 "$(verify f birth success "0|${ROW/,\"provision\":\"yes\"/}|")"
have  "S17g names the missing assertion" "WITHOUT a provision assertion"
havent "S17g2 and does not go on to report success" "boot signal received"
rc_is "S17h nft_metadata_drop=no -> 0 (warn, never fail)" 0 "$(verify h replace success "0|${ROW/nft_metadata_drop\":\"yes/nft_metadata_drop\":\"no}|")"
have  "S17i warns that the egress drop did not arm" "::warning::git-data booted with nft_metadata_drop=no"
rc_is "S17j nft_metadata_drop absent -> 0" 0 "$(verify j replace success "0|${ROW/,\"nft_metadata_drop\":\"yes\"/}|")"
have  "S17k warns that its state is UNKNOWN" "state is UNKNOWN"

# (#8210) luks_reopen_unit is TERMINAL, unlike nft_metadata_drop two arms up: a replace that
# delivers an unarmed boot-time LUKS reopen loses the store at the next reboot, and a replace is
# the only route by which that unit reaches the live host — so the poll must FAIL rather than
# warn. The `no` and the `absent` cases are both tested: the second is the reader-drift case,
# where a producer that stopped emitting the tag would otherwise read as healthy.
rc_is "S17h2 luks_reopen_unit=no -> 1 (TERMINAL, unlike nft_metadata_drop)" 1 "$(verify h2 replace success "0|${ROW/luks_reopen_unit\":\"yes/luks_reopen_unit\":\"no}|")"
have  "S17h3 names the unmet invariant" "luks_reopen_unit=no"
havent "S17h4 and does not go on to report success" "boot signal received"
rc_is "S17h5 luks_reopen_unit absent -> 1 (drift, not health)" 1 "$(verify h5 birth success "0|${ROW/,\"luks_reopen_unit\":\"yes\"/}|")"
have  "S17h6 names the missing assertion" "WITHOUT a luks_reopen_unit assertion"

# (#8211) THE THREE MEASURED BOOT CHECKS are TERMINAL too. For each: `no`, absent, and a third
# value must all refuse, and none may go on to report success. The third value is the case the
# plan's Sharp Edges name: the readers grep `"<field>":"yes"`, so only a presence-of-yes rule
# (not an absence-of-no rule) keeps an unexpected value from passing.
for _f in fence_on_mapper erasure_probe plaintext_empty; do
  rc_is "S20a ${_f}=no -> 1" 1 "$(verify "k1_$_f" replace success "0|${ROW/${_f}\":\"yes/${_f}\":\"no}|")"
  have  "S20b ${_f}=no names the unmet invariant" "${_f}=no"
  havent "S20c ${_f}=no does not report success" "boot signal received"
  rc_is "S20d ${_f} absent -> 1" 1 "$(verify "k4_$_f" birth success "0|${ROW/,\"${_f}\":\"yes\"/}|")"
  have  "S20e ${_f} absent names the missing assertion" "WITHOUT a ${_f} assertion"
  rc_is "S20f ${_f}=unknown -> 1 (only yes passes)" 1 "$(verify "k6_$_f" replace success "0|${ROW/${_f}\":\"yes/${_f}\":\"unknown}|")"
  havent "S20g ${_f}=unknown does not report success" "boot signal received"
done
# The informational fields never gate: served_repos and plaintext_volume are reported, and a
# boot_complete without them still passes on its terminal booleans.
rc_is "S20h informational fields absent -> 0" 0 "$(verify k8 replace success "0|${ROW/,\"plaintext_volume\":\"present\",\"served_repos\":\"0\",\"plaintext_journal\":\"dirty\"/}|")"
# (#5274) plaintext_journal is informational: a dirty journal is replayed into a throwaway COW, so
# neither value gates the poll — the terminal plaintext_empty does.
rc_is "S20i plaintext_journal=clean does not gate -> 0" 0 "$(verify k9 replace success "0|${ROW/\"plaintext_journal\":\"dirty\"/\"plaintext_journal\":\"clean\"}|")"

rc_is "S17l silent -> 1" 1 "$(verify l birth success '0||')"
have  "S17m silent routes to Sentry events after the anchor" "timestamped AFTER this run's boot-trail anchor"
have  "S17n silent uses a real emitted stage name" "stage:gitdata_runcmd_ok"
have  "S17o silent birth points at an existing runbook section" "runbook's 'If it fails' section"
havent "S17o2 and never names the non-existent ls-remote check" "ls-remote"
rc_is "S17p replace silent -> 1" 1 "$(verify p replace success '0||')"
have  "S17q replace silent forbids re-dispatch as a reading" "Do NOT re-dispatch the replace"
rc_is "S17r replace silent after a FAILED apply -> 1" 1 "$(verify r replace failure '0||')"
have  "S17s it does not assert the old host is gone" "whether the previous host was destroyed is NOT measured"
havent "S17t and never says the old host is gone" "The old host is gone"

rc_is "S17u unreadable, nothing answered -> 1" 1 "$(verify u replace success '22||err')"
have  "S17v says every read failed only when true" "Every read failed (answered=0/2)"
rc_is "S17w unreadable after an answered read -> 1" 1 "$(verify w replace success '0||' '22||err')"
have  "S17x names the FINAL read, with the count" "The FINAL read failed after 1/2 earlier reads answered"
havent "S17y and does not claim every read failed" "Every read failed"
have  "S17z carries the class into the annotation" "last class=other"
havent "S17za replace remediation never prescribes re-dispatch" "re-dispatch once"
have  "S17zz points at the anchored runbook query" "'After the birth' query (read-only) with this run's boot-trail anchor"

rc_is "S17zb refused anchor -> 1" 1 "$(d=$(mkshim vzb "$(spec '0||')"); in_step "$d" "$(vcall "birth 2 0 '' success")")"
have  "S17zc says the poll refused to run" "The boot poll refused to run (rc=2)"
rc_is "S17zd unknown kind -> 2" 2 "$(d=$(mkshim vzd "$(spec '0||')"); in_step "$d" "$(vcall "rebirth 2 0 $ANCHOR success")")"
rc_is "S17ze no DOPPLER_TOKEN -> 1" 1 "$(d=$(mkshim vze "$(spec '0||')"); STEP_DOPPLER_TOKEN="" in_step "$d" "$(vcall "replace 2 0 $ANCHOR success")")"
have  "S17zf names DOPPLER_TOKEN, and replace forbids re-dispatch" "do NOT re-dispatch the replace to get a reading"
n=$(wc -l < "$SANDBOX/vze/count")
rc_is "S17zg no read happens without DOPPLER_TOKEN" 0 "$n"
# The unexpected-verdict arm is reachable through the decide() seam: a vocabulary drift there
# must fail closed, never fall through to "received".
rc_is "S17zh an unknown verdict fails closed -> 1" 1 "$(d=$(mkshim vzh "$(spec "0|${ROW}|")"); in_step "$d" "git_data_boot_poll_decide() { echo bogus; }; $(vcall "birth 2 0 $ANCHOR success")")"
have  "S17zi names the unexpected verdict" "unexpected verdict 'bogus'"
havent "S17zj and does not report success" "boot signal received"

# ── S18 THE WORKFLOW: each job's poll step, extracted and EXECUTED ───────────
# Steps are cut out by NAME, comment lines dropped, so a check can only be satisfied by the
# step it is about, and never by prose.
extract_job() { # <job-id> -> job block
  awk -v j="  $1:" '$0==j{f=1; print; next} f && /^  [a-z_]+:$/{exit} f{print}' "$WF"
}
extract_step() { # <job-id> <step-name-prefix> [run] -> the step's lines (or its run body), no comments
  extract_job "$1" | python3 -c '
import sys
want, mode = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
lines = sys.stdin.read().split("\n"); i = 0
while i < len(lines) and not lines[i].startswith("      - name: " + want): i += 1
if i == len(lines): sys.exit(0)
blk = [lines[i]]; i += 1
while i < len(lines) and not lines[i].startswith("      - name: ") and not (lines[i] and not lines[i].startswith("      ")):
    blk.append(lines[i]); i += 1
if mode == "run":
    j = 0
    while j < len(blk) and blk[j].strip() != "run: |": j += 1
    print("\n".join(l[10:] for l in blk[j+1:] if l.startswith("          ") or l.strip() == ""))
else:
    print("\n".join(l.strip() for l in blk if not l.strip().startswith("#")))' "$2" "${3:-}"
}
mkdir -p "$SANDBOX/ws/scripts/lib"
cat > "$SANDBOX/ws/scripts/lib/git-data-boot-signal-poll.sh" <<'STUB'
git_data_boot_verify() { printf 'VERIFY_ARGS=%s|%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" "${6-<none>}"; return "${STUB_RC:-0}"; }
STUB
for job in git_data_host_create:birth git_data_host_replace:replace; do
  jid="${job%%:*}"; kind="${job#*:}"
  body="$(extract_step "$jid" "Poll for the git-data boot-completion signal" run)"
  if [[ -z "${body//[[:space:]]/}" ]]; then _report "S18 $jid poll run body extracted" bad "empty"; continue; fi
  for want_rc in 0 1; do
    rc=0
    env GITHUB_WORKSPACE="$SANDBOX/ws" STUB_RC="$want_rc" APPLY_OUTCOME=success BOOT_TRAIL_SINCE="$ANCHOR" \
      bash --noprofile --norc -e -c "$body" > "$SANDBOX/out" 2>&1 || rc=$?
    rc_is "S18 $jid step exits with the verify rc ($want_rc)" "$want_rc" "$rc"
  done
  if grep -qx "VERIFY_ARGS=$kind|20|30|$ANCHOR|success|<none>" "$SANDBOX/out"; then _report "S18 $jid calls verify as $kind, 20 x 30 s, anchored, nothing else" ok
  else _report "S18 $jid calls verify as $kind, 20 x 30 s, anchored, nothing else" bad "got: $(cat "$SANDBOX/out")"; fi
  rc=0
  env -u BOOT_TRAIL_SINCE GITHUB_WORKSPACE="$SANDBOX/ws" APPLY_OUTCOME=success \
    bash --noprofile --norc -e -c "$body" > "$SANDBOX/out" 2>&1 || rc=$?
  if grep -qx "VERIFY_ARGS=$kind|20|30||success|<none>" "$SANDBOX/out"; then _report "S18 $jid passes an UNSET anchor through as empty (no default)" ok
  else _report "S18 $jid passes an UNSET anchor through as empty (no default)" bad "got: $(cat "$SANDBOX/out")"; fi
done

# ── S19 THE WORKFLOW'S WIRING, per job, per STEP ─────────────────────────────
# chk <label> <step-text> <exact-line>: the line must be one of the step's own lines.
chk() {
  if grep -qxF -- "$3" <<<"$2"; then _report "$1" ok; else _report "$1" bad "missing line: $3"; fi
}
_before=$fail; chk "chk canary" "a line" "another line" >/dev/null 2>&1
if (( fail != _before + 1 )); then printf 'FAIL: chk canary did not record a failure\n' >&2; exit 1; fi
fail=$((fail - 1)); unset 'FAILURES[-1]'
for job in git_data_host_create git_data_host_replace; do
  anchor_run="$(extract_step "$job" "Stamp boot-trail run anchor" run)"
  n_epoch="$(grep -cE '^[[:space:]]*epoch=' <<<"$anchor_run" || true)"
  if grep -qx 'epoch=$(date -u +%s)' <<<"$anchor_run" && [[ "$n_epoch" == 1 ]]; then
    _report "S19 $job: anchor is the stamp, assigned once, no back-skew" ok
  else _report "S19 $job: anchor is the stamp, assigned once, no back-skew" bad "epoch lines=$n_epoch"; fi
  apply_step="$(extract_step "$job" "Terraform apply")"
  chk "S19 $job: apply step has id apply" "$apply_step" 'id: apply'
  poll_step="$(extract_step "$job" "Poll for the git-data boot-completion signal")"
  chk "S19 $job: poll step has id poll" "$poll_step" 'id: poll'
  chk "S19 $job: poll runs after success or failure only" "$poll_step" "if: \${{ !cancelled() && (steps.apply.outcome == 'success' || steps.apply.outcome == 'failure') }}"
  chk "S19 $job: poll receives the apply outcome" "$poll_step" 'APPLY_OUTCOME: ${{ steps.apply.outcome }}'
  chk "S19 $job: poll receives DOPPLER_TOKEN" "$poll_step" 'DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}'
  chk "S19 $job: poll receives the anchor" "$poll_step" 'BOOT_TRAIL_SINCE: ${{ steps.boot_anchor.outputs.epoch }}'
  if grep -qE '^(timeout-minutes|continue-on-error):' <<<"$poll_step"; then _report "S19 $job: poll step has no step timeout or continue-on-error" bad "found one"
  else _report "S19 $job: poll step has no step timeout or continue-on-error" ok; fi
  blk="$(extract_job "$job")"
  if grep -qF 'secrets.BETTERSTACK_QUERY' <<<"$blk"; then _report "S19 $job: binds no stale BETTERSTACK_QUERY secret" bad "found a binding"
  else _report "S19 $job: binds no stale BETTERSTACK_QUERY secret" ok; fi
  tmo="$(grep -m1 -E '^    timeout-minutes: [0-9]+$' <<<"$blk" | grep -oE '[0-9]+$' || true)"
  # 20 reads x (30 s sleep + 45 s read cap + 5 s kill grace) + 10 min for plan/apply
  # + 5 min for the steps that run BEFORE `Terraform plan`. That last term is the one an
  # earlier revision of this floor omitted: the create job runs eleven of them (checkout,
  # setup-terraform, the Doppler install, input validation, three interlocks that each reach
  # Doppler / the GitHub API / Better Stack, keygen, the secrets check, the R2 credential
  # extraction, terraform init), so a floor priced on plan+apply alone certifies a margin
  # that does not exist. Overrunning it cancels the job MID-POLL with no VERDICT line —
  # the "could not tell" state this suite's subject exists to remove.
  need=$(( (20 * (30 + 45 + 5) + 59) / 60 + 10 + 5 ))
  if [[ "$tmo" =~ ^[0-9]+$ ]] && (( tmo >= need )); then _report "S19 $job: timeout-minutes ($tmo) covers the poll ($need)" ok
  else _report "S19 $job: timeout-minutes covers the poll" bad "timeout-minutes='$tmo' need>=$need"; fi
  sum_step="$(extract_step "$job" "Dispatch summary")"
  chk "S19 $job: summary reads the apply outcome" "$sum_step" 'APPLY_OUTCOME: ${{ steps.apply.outcome }}'
  chk "S19 $job: summary reads the poll outcome" "$sum_step" 'POLL_OUTCOME: ${{ steps.poll.outcome }}'
  sum_run="$(extract_step "$job" "Dispatch summary" run)"
  for pair in "success:success:0" "success:failure:0" "success:skipped:1" "success:cancelled:1" \
              "success::1" ":success:1" "skipped:skipped:0" "failure:failure:0" "cancelled:skipped:0"; do
    IFS=: read -r ao po want <<<"$pair"
    rc=0
    env GITHUB_STEP_SUMMARY="$SANDBOX/summary" REASON=r JOB_STATUS=x RUN_URL=u APPLY_OUTCOME="$ao" POLL_OUTCOME="$po" \
      bash --noprofile --norc -e -c "$sum_run" > "$SANDBOX/out" 2>&1 || rc=$?
    rc_is "S19 $job: summary exits $want on apply='$ao' poll='$po'" "$want" "$rc"
  done
done

# ── S21 (#8211, Guard 2 row 4) THE TERMINAL SET IS DERIVED FROM THE PRODUCER ──────
# The required set is read from git-data-bootstrap.sh's own boot_complete emit arguments, never
# restated here: every `name=value` argument whose name is not informational. It must equal the
# poll's GIT_DATA_BOOT_TERMINAL (read by SOURCING the library, so the value checked is the value
# the job runs) AND the capture's _TERMINAL. Each terminal value must be a yes/no literal or a
# variable: any other literal is a third value, which the readers' `"<f>":"yes"` rule reads as
# drift on every boot. The mutation rows (S21e-h) run the same verdict against temp copies and
# must RED; they are read only when the real triple is green (S21b), so a real drift can never
# make them pass for the wrong reason.
G2_BOOT="$REPO_ROOT/apps/web-platform/infra/git-data-bootstrap.sh"
G2_CAP="$REPO_ROOT/scripts/followthroughs/git-data-rung2-evidence-capture.sh"
G2_INFORMATIONAL="plaintext_volume served_repos plaintext_journal nft_metadata_drop disk_pct inode_pct"
# g2_derive <bootstrap> — the terminal names, sorted, space-joined. rc 1 (printing BAD:) when a
# terminal argument carries a literal other than yes/no. Comment lines are stripped first and
# the window is anchored on the emit CALL, as git-data-emit.test.sh's AC30-parity does.
g2_derive() {
  local kv k v out="" bad=""
  while IFS= read -r kv; do
    [[ -n "$kv" ]] || continue
    k="${kv%%=*}"; v="${kv#*=}"
    case " $G2_INFORMATIONAL " in *" $k "*) continue ;; esac
    case "$v" in yes|no|\$*) out+="$k"$'\n' ;; *) bad+=" $kv" ;; esac
  done < <(grep -vE '^[[:space:]]*#' "$1" \
    | sed -n '/^[[:space:]]*"\$GIT_DATA_EMIT".*boot_complete/,/|| true$/p' \
    | grep -oE '"[a-z0-9_]+=[^"]*"' | tr -d '"')
  if [[ -n "$bad" ]]; then printf 'BAD:%s' "$bad"; return 1; fi
  printf '%s' "$out" | sort -u | tr '\n' ' '
}
# g2_poll_roster <poll-lib> — the runtime value, from a clean shell that sources the library.
g2_poll_roster() {
  bash --noprofile --norc -c '. "$1" >/dev/null 2>&1 || exit 1; printf "%s\n" $GIT_DATA_BOOT_TERMINAL' _ "$1" \
    | sort -u | tr '\n' ' '
}
# g2_cap_roster <capture> — exactly one `_TERMINAL="…"` declaration, or nothing.
g2_cap_roster() {
  [[ "$(grep -cE '^_TERMINAL="[a-z0-9_ ]+"$' "$1")" -eq 1 ]] || return 0
  grep -oE '^_TERMINAL="[a-z0-9_ ]+"$' "$1" | sed -E 's/^_TERMINAL="//; s/"$//' | tr ' ' '\n' | sort -u | tr '\n' ' '
}
# g2_verdict <bootstrap> <poll-lib> <capture> — prints GREEN or DRIFT(<why>); rc 0 iff GREEN.
g2_verdict() {
  local d p c
  d="$(g2_derive "$1")" || { printf 'DRIFT(producer %s)' "$d"; return 1; }
  p="$(g2_poll_roster "$2")"; c="$(g2_cap_roster "$3")"
  if [[ -z "$d" ]] || (( $(wc -w <<<"$d") < 4 )); then printf 'DRIFT(derived set implausibly small: %s)' "$d"; return 1; fi
  if [[ "$d" != "$p" ]]; then printf 'DRIFT(poll: %s| producer: %s)' "$p" "$d"; return 1; fi
  if [[ "$d" != "$c" ]]; then printf 'DRIFT(capture: %s| producer: %s)' "$c" "$d"; return 1; fi
  printf 'GREEN'
}
_g2_real="$(g2_derive "$G2_BOOT" || true)"
if [[ "$_g2_real" != BAD:* ]] && (( $(wc -w <<<"$_g2_real") >= 4 )); then _report "S21a derived a terminal set from the producer ($_g2_real)" ok
else _report "S21a derived a terminal set from the producer" bad "got: '${_g2_real}' — the extraction drifted or a terminal value is a third literal"; fi
_g2_v="$(g2_verdict "$G2_BOOT" "$LIB" "$G2_CAP" || true)"
if [[ "$_g2_v" == GREEN ]]; then _report "S21b producer == poll GIT_DATA_BOOT_TERMINAL == capture _TERMINAL" ok
else _report "S21b producer == poll GIT_DATA_BOOT_TERMINAL == capture _TERMINAL" bad "$_g2_v"; fi
# S21c: the contract's names are in the set the producer emits (C3), so a producer that stopped
# emitting a measured check cannot shrink all three rosters together and stay green.
_g2_miss=""
for _f in luks_mounted repo_root hooks_path provision luks_reopen_unit fence_on_mapper erasure_probe plaintext_empty; do
  [[ " $_g2_real " == *" $_f "* ]] || _g2_miss+=" $_f"
done
if [[ -z "$_g2_miss" ]]; then _report "S21c the producer emits every C3 terminal boolean" ok
else _report "S21c the producer emits every C3 terminal boolean" bad "missing:${_g2_miss}"; fi

G2_TMP="$SANDBOX/g2"; mkdir -p "$G2_TMP/lib"
cp "$REPO_ROOT"/scripts/lib/{git-data-boot-signal-poll,betterstack-absence,betterstack-read-classify,betterstack-sources}.sh "$G2_TMP/lib/"
# g2_mut <label> <landed-check> <bootstrap> <poll> <capture> — the mutation must LAND (its own
# check) and the verdict must RED. Unreadable while the real triple is not green.
g2_mut() {
  local label="$1" landed="$2" v
  if [[ "$_g2_v" != GREEN ]]; then _report "$label" bad "baseline S21b is not GREEN, so a RED here proves nothing"; return; fi
  if ! eval "$landed"; then _report "$label" bad "the mutation did not land"; return; fi
  v="$(g2_verdict "$3" "$4" "$5" || true)"
  if [[ "$v" == DRIFT* ]]; then _report "$label" ok; else _report "$label" bad "verdict: $v"; fi
}
# S21d: a NEW boolean emitted by the producer but added to neither reader.
sed -E 's/(^[[:space:]]*"\$GIT_DATA_EMIT".*boot_complete info "")/\1 "zz_new_check=${_zz}"/' "$G2_BOOT" > "$G2_TMP/boot-new.sh"
g2_mut "S21d MUTATION a new emitted boolean left out of both readers -> RED" \
  '[[ " $(g2_derive "$G2_TMP/boot-new.sh") " == *" zz_new_check "* ]]' "$G2_TMP/boot-new.sh" "$LIB" "$G2_CAP"
# S21e: the same new boolean, added to the capture but left out of the POLL's list.
sed -E 's/^(_TERMINAL="[a-z0-9_ ]+)"$/\1 zz_new_check"/' "$G2_CAP" > "$G2_TMP/cap-new.sh"
g2_mut "S21e MUTATION a new boolean in the capture but NOT in GIT_DATA_BOOT_TERMINAL -> RED" \
  'grep -qE "^_TERMINAL=.* zz_new_check\"$" "$G2_TMP/cap-new.sh"' "$G2_TMP/boot-new.sh" "$LIB" "$G2_TMP/cap-new.sh"
# S21f: the poll's list loses a name the producer still emits.
sed -E 's/^(GIT_DATA_BOOT_TERMINAL=".*) erasure_probe/\1/' "$LIB" > "$G2_TMP/lib/git-data-boot-signal-poll.sh"
g2_mut "S21f MUTATION erasure_probe dropped from GIT_DATA_BOOT_TERMINAL -> RED" \
  '! grep -qE "^GIT_DATA_BOOT_TERMINAL=.*erasure_probe" "$G2_TMP/lib/git-data-boot-signal-poll.sh"' \
  "$G2_BOOT" "$G2_TMP/lib/git-data-boot-signal-poll.sh" "$G2_CAP"
# S21g: the capture's required set loses a name the producer still emits.
sed -E 's/^(_TERMINAL=".*) fence_on_mapper/\1/' "$G2_CAP" > "$G2_TMP/cap-drop.sh"
g2_mut "S21g MUTATION fence_on_mapper dropped from the capture's _TERMINAL -> RED" \
  '! grep -qE "^_TERMINAL=.*fence_on_mapper" "$G2_TMP/cap-drop.sh"' "$G2_BOOT" "$LIB" "$G2_TMP/cap-drop.sh"
# S21h: a terminal boolean emitted as a third literal value.
sed -E 's/(^[[:space:]]*"\$GIT_DATA_EMIT".*boot_complete info "")/\1 "plaintext_empty=maybe"/' "$G2_BOOT" > "$G2_TMP/boot-third.sh"
g2_mut "S21h MUTATION a terminal emitted as a literal other than yes/no -> RED" \
  'grep -qF "plaintext_empty=maybe" "$G2_TMP/boot-third.sh"' "$G2_TMP/boot-third.sh" "$LIB" "$G2_CAP"

# ── Assertion count: EXACT, printf + exit, never through the helper it backstops ──
_total=$((pass + fail))
# RAISED 146 -> 184 (#8211), ITEMISED:
#     8  S15d one per GIT_DATA_BOOT_TERMINAL name: the SQL the reader received projects it
#    21  S20a-g fence_on_mapper / erasure_probe / plaintext_empty, each: `no` refuses and names
#        the unmet invariant and does not report success; absent refuses and names the missing
#        assertion; a third value refuses and does not report success (7 rows x 3 fields)
#     1  S20h the informational fields never gate
#     8  S21a-h Guard 2 row 4: the terminal set derived from the producer equals both readers'
#        rosters (3), and five mutations of that triple each RED
#   ----
#    38
# RAISED 184 -> 185 (#5274): S20i, plaintext_journal=clean does not gate the poll.
_EXACT=185
if (( _total != _EXACT )); then
  printf 'FAIL: assertion count: %d ran, expected exactly %d — coverage changed; update _EXACT deliberately\n' "$_total" "$_EXACT" >&2
  exit 1
fi
if (( ${#FAILURES[@]} != fail )); then
  printf 'FAIL: ledger drift: %d entries vs fail counter %d\n' "${#FAILURES[@]}" "$fail" >&2
  exit 1
fi
printf 'git-data-boot-signal-poll: %d passed, %d failed (%d assertions)\n' "$pass" "$fail" "$_total"
exit $(( fail > 0 ))
