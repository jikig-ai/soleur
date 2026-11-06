#!/usr/bin/env bash
# Fixture suite for scripts/followthroughs/inngest-bs-token-restage-7596.sh, the #7596
# measured-close probe: exit 0 PASS only on CURRENT-GENERATION evidence — a post-floor
# (MIN_DT) journald `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` row whose _BOOT_ID positively
# matches the newest inngest-server-probe row's boot id, or a post-floor BOOT_STAGE
# `bs-token-restaged`/`bs-token-restage-enabled` marker scoped to the newest generation.
# Every other state is exit 2 TRANSIENT with a named reason (pre_replace | leg_unit |
# boot_id_unresolvable | restage_not_ok | query_failed | credentials_unprovisioned |
# selector_failed | query_tool_missing). FAIL is deliberately unreachable.
#
# No network: the probe is COPIED into a temp tree `$TREE/scripts/followthroughs/` whose
# sibling `$TREE/scripts/betterstack-query.sh` is a stub, because the probe resolves its
# reader as `$SCRIPT_DIR/../betterstack-query.sh` and has no environment seam. The probe
# makes THREE reads per run, all mode-2 flag form; the stub keys on the --grep value:
#   * `--grep SOLEUR_INNGEST_BS_TOKEN_RESTAGE`  -> the journald leg rows    ($STUB_JROWS)
#   * `--grep inngest-server-probe`             -> the boot-anchor rows     ($STUB_PROWS)
#   * `--grep SOLEUR_INNGEST_BOOT_STAGE`        -> the curl-ingest leg rows ($STUB_BROWS)
# Any other argv is REFUSED with exit 64. Per-leg failure knobs: STUB_JRC/PRC/BRC.
# Registered EXPLICITLY in scripts/test-all.sh (scripts/followthroughs/*.test.sh is not in
# SUITE_GLOBS).
#
# INSTRUMENT SELF-TEST + MUTATION BATTERY + STUBBED-PROBE GUARD — same conventions as
# inngest-luks-keeper-dark-11265.test.sh: helpers proven on known-true/known-false inputs
# (rc 4 abort), mutants at `# [mut:NAME]` tag lines re-run the suite on themselves
# (FT_INNER=1) and are credited only when the inner run exits 1 printing its own named
# FAIL fragment, and SAW_PASS must end at 1 or a probe that can never reach a verdict
# passes vacuously.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${FT_REPO:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SUT="${FT_SUT:-$SCRIPT_DIR/inngest-bs-token-restage-7596.sh}"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT:?}"' EXIT

PASS=0; FAIL=0; LEDGER="$ROOT/ledger"; : > "$LEDGER"
ok()    { PASS=$((PASS + 1)); printf 'ok\t%s\n' "$1" >> "$LEDGER"; echo "  PASS: $1"; }
bad()   { FAIL=$((FAIL + 1)); printf 'bad\t%s\n' "$1" >> "$LEDGER"; echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3] present" ;; *) ok "$1" ;; esac; }

instrument_selftest() {
  local p0=$PASS f0=$FAIL n0 p1 f1 p2 f2
  n0="$(wc -l < "$LEDGER")"
  { check st 1 2; has st abc z; hasnt st abc b; } >/dev/null
  p1=$((PASS - p0)); f1=$((FAIL - f0))
  { check st 1 1; has st abc b; hasnt st abc z; } >/dev/null
  p2=$((PASS - p0 - p1)); f2=$((FAIL - f0 - f1))
  PASS=$p0; FAIL=$f0
  head -n "$n0" "$LEDGER" > "$LEDGER.t" && mv "$LEDGER.t" "$LEDGER"
  if [ "$p1/$f1/$p2/$f2" != "0/3/3/0" ]; then
    echo "INSTRUMENT SELF-TEST FAILED: check/has/hasnt cannot tell true from false"
    exit 4
  fi
}
instrument_selftest

CAN_STR="CANARY-9f2c4a"
B1="aaaa1111-2222-3333-4444-555555555555"   # the CURRENT generation's boot id
B0="bbbb0000-1111-2222-3333-444444444444"   # the previous generation's boot id
PRE="2026-10-29 08:00:00"                    # before the MIN_DT floor (2026-10-30)
POST="2026-10-31 08:00:00"                   # after it
POST2="2026-10-31 10:00:00"

# Row builders — the REAL stored shapes, raw = a JSON string holding a JSON document.
jrow() {  # <dt> <boot-id|-> <message>
  jq -nc --arg dt "$1" --arg b "$2" --arg m "$3" \
    '{dt:$dt, raw:({SYSLOG_IDENTIFIER:"inngest-bs-token-restage", host:"soleur-inngest", host_name:"soleur-inngest-prd", _BOOT_ID:$b, message:$m}|tojson)}'
}
jrow_noboot() {  # <dt> <message> — a journald row whose _BOOT_ID never shipped
  jq -nc --arg dt "$1" --arg m "$2" \
    '{dt:$dt, raw:({SYSLOG_IDENTIFIER:"inngest-bs-token-restage", host:"soleur-inngest", host_name:"soleur-inngest-prd", message:$m}|tojson)}'
}
prow() {  # <dt> <boot-id|-> — the generation anchor
  jq -nc --arg dt "$1" --arg b "$2" \
    '{dt:$dt, raw:({SYSLOG_IDENTIFIER:"inngest-server-probe", host:"soleur-inngest", host_name:"soleur-inngest-prd", _BOOT_ID:$b, message:"SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active"}|tojson)}'
}
prow_noboot() {  # <dt> — a server-probe row whose _BOOT_ID never shipped
  jq -nc --arg dt "$1" \
    '{dt:$dt, raw:({SYSLOG_IDENTIFIER:"inngest-server-probe", host:"soleur-inngest", host_name:"soleur-inngest-prd", message:"SOLEUR_INNGEST_SERVER_PROBE http_code=200"}|tojson)}'
}
srow() {  # <dt> <stage> — a BOOT_STAGE marker on the direct-curl ingest leg
  jq -nc --arg dt "$1" --arg s "$2" \
    '{dt:$dt, raw:({marker:"SOLEUR_INNGEST_BOOT_STAGE", stage:$s, detail:"ok=1 boot-trace channel re-armed", host:"soleur-inngest", message:("SOLEUR_INNGEST_BOOT_STAGE stage="+$s+" ok=1 boot-trace channel re-armed"), shipper:"cloud-init-phone-home"}|tojson)}'
}
OKMSG="SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1 path=/run/inngest-bs-logs-token #7228"
FAILMSG="SOLEUR_INNGEST_BS_TOKEN_RESTAGE_FAILED reason=doppler-read rc=1 #7228"

# The temp tree: probe under scripts/followthroughs/, stub reader at scripts/betterstack-query.sh.
TREE="$ROOT/tree"; mkdir -p "$TREE/scripts/followthroughs"
PROBE="$TREE/scripts/followthroughs/inngest-bs-token-restage-7596.sh"
cp "$SUT" "$PROBE"
QUERY_STUB="$TREE/scripts/betterstack-query.sh"
cat > "$QUERY_STUB" <<'STUB'
#!/usr/bin/env bash
# Three-arm reader stub keyed on the --grep value; any other argv is REFUSED (exit 64)
# so a probe that invented a fourth read or dropped a flag gets a refusal, not rows.
set -u
printf '%s\n' "$*" > "$STUB_ARGS"
for f in " --since " " --grep " " --limit "; do
  case " $* " in *"$f"*) : ;; *) echo "REFUSED argv-missing-flag:$f" >> "$STUB_CALLS"; exit 64 ;; esac
done
case " $* " in
  *" --grep SOLEUR_INNGEST_BS_TOKEN_RESTAGE "*)
    echo J >> "$STUB_CALLS"; cat "$STUB_JROWS" 2>/dev/null
    if [ "${STUB_JRC:-0}" != 0 ]; then echo "auth failure for user secret-user at host secret-host $STUB_CANARY" >&2; exit "$STUB_JRC"; fi ;;
  *" --grep inngest-server-probe "*)
    echo P >> "$STUB_CALLS"; cat "$STUB_PROWS" 2>/dev/null
    if [ "${STUB_PRC:-0}" != 0 ]; then echo "auth failure for user secret-user at host secret-host $STUB_CANARY" >&2; exit "$STUB_PRC"; fi ;;
  *" --grep SOLEUR_INNGEST_BOOT_STAGE "*)
    echo B >> "$STUB_CALLS"; cat "$STUB_BROWS" 2>/dev/null
    if [ "${STUB_BRC:-0}" != 0 ]; then echo "auth failure for user secret-user at host secret-host $STUB_CANARY" >&2; exit "$STUB_BRC"; fi ;;
  *) echo "REFUSED unexpected-grep" >> "$STUB_CALLS"; exit 64 ;;
esac
STUB
chmod +x "$QUERY_STUB"
EVIL="$ROOT/evil.sh"; printf '#!/usr/bin/env bash\necho EVIL >> "%s"\n' "$ROOT/evil-called" > "$EVIL"; chmod +x "$EVIL"

RCS="$ROOT/rcs"; : > "$RCS"
OUT=""; RC=0; SAW_PASS=0
run() {  # knobs: QH QU QP XBASH STUB_JRC STUB_PRC STUB_BRC ; rows come from $ROOT/{j,p,b}rows
  RC=0
  rm -f "$ROOT/args" "$ROOT/calls" "$ROOT/evil-called"; : > "$ROOT/calls"
  OUT="$(env -i PATH="$PATH" HOME="$ROOT" TMPDIR="$ROOT" STUB_ARGS="$ROOT/args" STUB_CALLS="$ROOT/calls" \
    STUB_JROWS="$ROOT/jrows" STUB_PROWS="$ROOT/prows" STUB_BROWS="$ROOT/brows" \
    STUB_JRC="${STUB_JRC:-0}" STUB_PRC="${STUB_PRC:-0}" STUB_BRC="${STUB_BRC:-0}" STUB_CANARY="$CAN_STR" \
    RESTAGE_QUERY_BIN="$EVIL" \
    BETTERSTACK_QUERY_HOST="${QH-h}" BETTERSTACK_QUERY_USERNAME="${QU-u}" BETTERSTACK_QUERY_PASSWORD="${QP-p}" \
    bash ${XBASH:+"$XBASH"} "$PROBE" 2>&1 </dev/null)" || RC=$?
  echo "$RC" >> "$RCS"
  [ "$RC" = 0 ] && SAW_PASS=1
  return 0
}
calls()  { grep -c . "$ROOT/calls" 2>/dev/null || true; }
jcalls() { grep -c '^J$' "$ROOT/calls" 2>/dev/null || true; }
pcalls() { grep -c '^P$' "$ROOT/calls" 2>/dev/null || true; }
bcalls() { grep -c '^B$' "$ROOT/calls" 2>/dev/null || true; }
reset_knobs() { unset QH QU QP XBASH STUB_JRC STUB_PRC STUB_BRC; }
empty_all() { : > "$ROOT/jrows"; : > "$ROOT/prows"; : > "$ROOT/brows"; }
run_battery() { [ -z "${FT_INNER:-}" ] && [ "${1:-}" != "--no-battery" ]; }

reset_knobs
echo "=== inngest-bs-token-restage-7596.sh tests ==="

# 1. credentials: missing in any position is TRANSIENT with no reader call
for v in QH QU QP; do
  empty_all; jrow "$POST" "$B1" "$OKMSG" > "$ROOT/jrows"; eval "$v=''"; run
  check "empty $v: exit 2" 2 "$RC"; has "empty $v: credentials_unprovisioned" "$OUT" "credentials_unprovisioned"
  check "empty $v: reader never called" 0 "$(calls)"; reset_knobs
done

# 2. xtrace refusal: 78 before any read when a credential is in scope
empty_all; XBASH="-x" run; reset_knobs
check "xtrace with credentials: exit 78" 78 "$RC"; check "xtrace: reader never called" 0 "$(calls)"
QP="" XBASH="-x" run; reset_knobs
check "xtrace with no credentials: exit 2 (the refusal exists to protect the credential)" 2 "$RC"

# 3. read failure on ANY leg is TRANSIENT query_failed; credential-shaped stderr is withheld
empty_all; STUB_JRC=7 run; reset_knobs
check "journald read exits 7: exit 2" 2 "$RC"; has "journald read failure: query_failed" "$OUT" "query_failed"
hasnt "read failure: user withheld" "$OUT" "secret-user"; hasnt "read failure: host withheld" "$OUT" "secret-host"
hasnt "read failure: canary withheld" "$OUT" "$CAN_STR"
empty_all; STUB_PRC=3 run; reset_knobs
check "server-probe read exits 3: exit 2" 2 "$RC"; has "probe read failure: query_failed" "$OUT" "query_failed"
empty_all; STUB_BRC=5 run; reset_knobs
check "boot-stage read exits 5: exit 2" 2 "$RC"; has "boot-stage read failure: query_failed" "$OUT" "query_failed"
empty_all; mv "$QUERY_STUB" "$QUERY_STUB.off"; run; mv "$QUERY_STUB.off" "$QUERY_STUB"; reset_knobs
check "reader script missing: exit 2" 2 "$RC"

# 4. the probe issues exactly three reads (journald leg, boot anchor, curl-ingest leg)
empty_all; run
check "three reads per run" "1/1/1" "$(jcalls)/$(pcalls)/$(bcalls)"

# 5. pre_replace: nothing post-floor of ANY kind — the channel_dark-family state
empty_all; run
check "zero rows anywhere: exit 2" 2 "$RC"; has "zero rows: pre_replace" "$OUT" "pre_replace"
empty_all
{ jrow "$PRE" "$B0" "$OKMSG"; } > "$ROOT/jrows"
{ prow "$PRE" "$B0"; } > "$ROOT/prows"
{ srow "$PRE" bs-token-restaged; } > "$ROOT/brows"
run
check "everything predates the floor: exit 2" 2 "$RC"; has "pre-floor only: pre_replace" "$OUT" "pre_replace"

# 6. floor exclusion (Guard 2 row 4): a pre-MIN_DT ok=1 row must NEVER exit 0
empty_all
{ jrow "$PRE" "$B0" "$OKMSG"; } > "$ROOT/jrows"
{ prow "$POST" "$B1"; prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "pre-floor ok=1 row beside a live current generation: exit 2, never 0" 2 "$RC"
has "floor exclusion: the verdict names the leg" "$OUT" "leg_unit"
# the dt-shape gate precedes the lexical floor: a non-ISO dt can sort past the
# cut and must never count as post-floor evidence on either evidence leg
empty_all
{ jrow "not-a-timestamp" "$B1" "$OKMSG"; } > "$ROOT/jrows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "a garbage-dt ok=1 row: exit 2, never post-floor" 2 "$RC"
hasnt "garbage-dt journald row: never a PASS" "$OUT" "PASS:"
empty_all
{ srow "not-a-timestamp" bs-token-restage-enabled; } > "$ROOT/brows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "a garbage-dt enabled marker: exit 2, never gen-qualified" 2 "$RC"
hasnt "garbage-dt stage row: never a PASS" "$OUT" "PASS:"

# 7. boot_id_unresolvable (Guard 2 row 7): post-floor evidence exists but the
#    generation anchor cannot be read — never a degraded MIN_DT-only PASS
empty_all; jrow "$POST" "$B1" "$OKMSG" > "$ROOT/jrows"; run
check "post-floor ok=1 + absent server-probe read: exit 2" 2 "$RC"
has "unresolvable anchor: boot_id_unresolvable" "$OUT" "boot_id_unresolvable"
empty_all; jrow "$POST" "$B1" "$OKMSG" > "$ROOT/jrows"; prow_noboot "$POST" > "$ROOT/prows"; run
check "post-floor ok=1 + probe rows lacking _BOOT_ID: exit 2" 2 "$RC"
has "probe rows without _BOOT_ID: boot_id_unresolvable" "$OUT" "boot_id_unresolvable"
empty_all; srow "$POST" bs-token-restaged > "$ROOT/brows"; run
check "post-floor BOOT_STAGE marker + absent server-probe read: exit 2" 2 "$RC"
has "unverifiable marker generation: boot_id_unresolvable" "$OUT" "boot_id_unresolvable"
empty_all; jrow_noboot "$POST" "$OKMSG" > "$ROOT/jrows"; prow "$POST" "$B1" > "$ROOT/prows"; run
check "post-floor restage row missing its own _BOOT_ID: exit 2" 2 "$RC"
has "row boot id unresolvable: boot_id_unresolvable" "$OUT" "boot_id_unresolvable"
# the anchor is the newest row CARRYING a boot id: a newest dash row must not
# strand the probe while an earlier row already named the generation
empty_all
{ jrow "$POST" "$B1" "$OKMSG"; } > "$ROOT/jrows"
{ prow "$POST" "$B1"; prow_noboot "$POST2"; } > "$ROOT/prows"
run
check "newest probe row lacks _BOOT_ID but an earlier row carries it: exit 0" 0 "$RC"
has "anchor skips the dash row: pass_arm=journald" "$OUT" "pass_arm=journald"
# a forged non-charset boot id degrades to unresolvable and NEVER echoes into
# output (the sweeper posts probe output verbatim into issue comments)
empty_all
{ jrow "$POST" "$B1" "$OKMSG"; } > "$ROOT/jrows"
{ prow "$POST2" 'aa11<script>@everyone'; } > "$ROOT/prows"
run
check "a forged non-charset boot id: exit 2 (anchor unresolvable)" 2 "$RC"
has "forged boot id: boot_id_unresolvable" "$OUT" "boot_id_unresolvable"
hasnt "forged boot id never echoes into output" "$OUT" "<script>"

# 8. PASS arm-1: post-floor journald ok=1 with a matching current-generation _BOOT_ID
empty_all
{ jrow "$POST" "$B1" "$OKMSG"; } > "$ROOT/jrows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "post-floor journald ok=1 row + matching boot: exit 0" 0 "$RC"
has "arm-1 PASS names its arm" "$OUT" "pass_arm=journald"; has "arm-1 PASS: journald leg reported" "$OUT" "journald_rows=present"

# 9. PASS arm-2: a same-generation bs-token-restage-enabled marker (the
#    replace-bound first-boot runcmd — DELIVERY proof), journald leg dark.
#    The restaged marker alongside it is boot evidence only; a reboot-
#    generation restaged WITHOUT an enabled marker must NEVER close.
empty_all
{ srow "$POST" bs-token-restage-enabled; srow "$POST" bs-token-restaged; } > "$ROOT/brows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "post-floor BOOT_STAGE enabled+restaged markers, journald absent: exit 0" 0 "$RC"
has "arm-2 PASS names its arm" "$OUT" "pass_arm=boot_stage"; has "arm-2 PASS: journald leg dark inside the close" "$OUT" "journald_rows=absent"
empty_all
{ srow "$POST" bs-token-restage-enabled; } > "$ROOT/brows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "the enabled marker alone satisfies arm-2: exit 0" 0 "$RC"; has "enabled-marker PASS arm" "$OUT" "pass_arm=boot_stage"
empty_all
{ srow "$POST" bs-token-restaged; } > "$ROOT/brows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "post-floor restaged WITHOUT enabled (a plain reboot): exit 2, never 0" 2 "$RC"
has "reboot-only generation: delivery_unproven" "$OUT" "delivery_unproven"
hasnt "reboot-only generation: never a PASS" "$OUT" "pass_arm="

# 10. arm preference: journald wins when both legs carry current-generation evidence
empty_all
{ jrow "$POST" "$B1" "$OKMSG"; } > "$ROOT/jrows"
{ srow "$POST" bs-token-restage-enabled; } > "$ROOT/brows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "both arms qualifying: exit 0" 0 "$RC"
has "both legs present: journald preferred" "$OUT" "pass_arm=journald"; has "both legs present: journald_rows=present" "$OUT" "journald_rows=present"

# 11. leg_unit: post-floor activity proves the host lives but zero restage-unit evidence
empty_all; { prow "$POST" "$B1"; prow "$POST2" "$B1"; } > "$ROOT/prows"; run
check "post-floor probe rows only: exit 2" 2 "$RC"; has "alive-but-no-restage: leg_unit" "$OUT" "leg_unit"
empty_all
{ jrow "$POST" "$B0" "$OKMSG"; } > "$ROOT/jrows"          # post-floor but OLD generation
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "post-floor restage row from the old boot only: exit 2" 2 "$RC"
has "old-generation restage evidence: leg_unit" "$OUT" "leg_unit"
empty_all
{ srow "$POST" bootstrap-done; } > "$ROOT/brows"          # non-restage BOOT_STAGE traffic
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "post-floor non-restage markers only: exit 2" 2 "$RC"; has "non-restage markers: leg_unit" "$OUT" "leg_unit"

# 12. the stale-generation-in-window trap: an OLD-boot marker inside the window
empty_all
{ srow "2026-10-30 08:00:00" bs-token-restaged; } > "$ROOT/brows"   # old boot's marker, post-floor
{ prow "2026-10-30 12:00:00" "$B0"; prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "old-generation marker newer than MIN_DT but before the current boot: exit 2" 2 "$RC"
has "stale-generation marker: leg_unit, never PASS" "$OUT" "leg_unit"

# 13. restage_not_ok: the unit ran on the current boot and did not report ok=1
empty_all
{ jrow "$POST" "$B1" "$FAILMSG"; } > "$ROOT/jrows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "current-generation RESTAGE_FAILED row: exit 2" 2 "$RC"; has "unit ran and failed: restage_not_ok" "$OUT" "restage_not_ok"
empty_all
{ srow "$POST" bs-token-restage-enable-FAILED; } > "$ROOT/brows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "current-generation enable-FAILED marker: exit 2" 2 "$RC"; has "enable-FAILED marker: restage_not_ok" "$OUT" "restage_not_ok"
# the ok=1 test is boundary-anchored: ok=15 must not read as a qualifying row
empty_all
{ jrow "$POST" "$B1" "SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=15 path=/run/inngest-bs-logs-token"; } > "$ROOT/jrows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "an ok=15 message is not ok=1: exit 2" 2 "$RC"; has "ok=15: restage_not_ok" "$OUT" "restage_not_ok"

# 14. isolation holds: wrong-host / wrong-host_name / wrong-ident rows never count
empty_all
{ jq -nc --arg dt "$POST" '{dt:$dt, raw:({SYSLOG_IDENTIFIER:"inngest-bs-token-restage", host:"web-1", host_name:"soleur-web-platform", _BOOT_ID:"x", message:"SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1"}|tojson)}'; } > "$ROOT/jrows"
{ prow "$POST2" "$B1"; } > "$ROOT/prows"
run
check "a web-1 restage row: exit 2, never counted" 2 "$RC"

# 15. the MIN_DT floor is baked and dated at filing (suite-asserted constant)
mindt="$(grep -oE "^MIN_DT='?[0-9-]+'?" "$SUT" | head -n1)"
check "the probe bakes MIN_DT=2026-10-30 (the filing/enrollment floor)" "MIN_DT='2026-10-30'" "$mindt"

# 16. the reader has no env seam (the credential the probe carries rides this channel)
empty_all; jrow "$POST" "$B1" "$OKMSG" > "$ROOT/jrows"; prow "$POST2" "$B1" > "$ROOT/prows"; run
check "an exported RESTAGE_QUERY_BIN is ignored: the evil script never ran" "" "$(cat "$ROOT/evil-called" 2>/dev/null)"
leftover="$(grep -n 'RESTAGE_QUERY_BIN' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "the probe source has no RESTAGE_QUERY_BIN seam" "" "$leftover"
check "the reader path is fixed to \$SCRIPT_DIR/../betterstack-query.sh" 1 "$(grep -cE '^QUERY="\$SCRIPT_DIR/\.\./betterstack-query\.sh"' "$SUT")"

# 17. exit vocabulary, header contract and public-leak hygiene of the source
badrc="$(grep -vxE '0|2|78' "$RCS" | sort -u | tr '\n' ' ')"
check "every observed exit status is in {0,2,78} (FAIL unreachable)" "" "$badrc"
exits="$(grep -vE '^[[:space:]]*#' "$SUT" | grep -oE '(^|[^A-Za-z_])exit [0-9]+' 2>/dev/null | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')"
check "the source names only exit 0, 2 and 78" "0 2 78 " "$exits"
qform="$(grep -nE '\$\{[A-Za-z_0-9]+:\?' "$SUT" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
check "no \${VAR:?} form on an executable line" "" "$qform"
dir_lines="$(grep -E '^#[[:space:]]+<!-- soleur:followthrough ' "$SUT" || true)"
check "the header carries exactly one single-line follow-through directive" 1 "$(printf '%s\n' "$dir_lines" | grep -c .)"
has "the directive names this script and its secrets clause" "$dir_lines" "script=scripts/followthroughs/inngest-bs-token-restage-7596.sh"
has "the header names its tracker" "$(sed -n '1,140p' "$SUT")" "TRACKER: #7596"
has "the header carries a RETIREMENT census" "$(sed -n '1,140p' "$SUT")" "RETIREMENT:"
has "the RETIREMENT census names this suite" "$(sed -n '1,140p' "$SUT")" "inngest-bs-token-restage-7596.test.sh"
has "the RETIREMENT census names the runbook section" "$(sed -n '1,140p' "$SUT")" "inngest-server.md"

# 18. STUBBED-PROBE GUARD: a probe that can never reach a verdict must red this suite
check "the probe reached PASS in at least one fixture run (a neutered probe reds here)" 1 "$SAW_PASS"

FIX_N="$(wc -l < "$LEDGER")"
if run_battery "${1:-}"; then
  echo "=== mutation battery ==="
  export FT_REPO="$REPO"
  MUT="$ROOT/mut"; mkdir -p "$MUT"
  mutate_run() { # <name> <tag-or-unique-text> <replacement line> <expected FAIL fragment>
    local name="$1" tag="$2" rep="$3" frag="$4" f="$MUT/$1.sh" o="$MUT/$1.out" rc=0
    if ! grep -qF -- "$tag" "$SUT"; then bad "mutation $name: tag $tag exists in the probe (instrument)"; return; fi
    REP="$rep" TAG="$tag" awk 'index($0, ENVIRON["TAG"]) { print ENVIRON["REP"]; next } { print }' "$SUT" > "$f"
    if cmp -s "$SUT" "$f"; then bad "mutation $name: the mutation did not land (instrument)"; return; fi
    if ! bash -n "$f" 2>/dev/null; then bad "mutation $name: the mutant does not parse (instrument)"; return; fi
    FT_INNER=1 FT_SUT="$f" bash "$SELF" > "$o" 2>&1 || rc=$?
    if [ "$rc" = 0 ]; then bad "mutation $name: SURVIVED (rc=0)"
    elif [ "$rc" != 1 ]; then bad "mutation $name: unresolved instrument rc=$rc"
    elif grep -qF -- "FAIL: $frag" "$o"; then ok "mutation $name: caught by its own FAIL line [$frag]"
    else bad "mutation $name: rc=1 but no FAIL line [$frag] (killed by something else)"; fi
  }
  mutate_sub() { # <name> <unique text> <from> <to> <expected FAIL fragment>
    local line new
    line="$(grep -F -- "$2" "$SUT" || true)"
    if [ -z "$line" ] || [ "$(printf '%s\n' "$line" | wc -l)" != 1 ]; then bad "mutation $1: the text [$2] matches exactly one line (instrument)"; return; fi
    new="${line/"$3"/"$4"}"
    if [ "$new" = "$line" ]; then bad "mutation $1: [$3] is present in the line (instrument)"; return; fi
    mutate_run "$1" "$2" "$new" "$5"
  }
  ctl=0; FT_INNER=1 FT_SUT="$SUT" bash "$SELF" >/dev/null 2>&1 || ctl=$?
  check "battery control: the pristine probe passes the inner suite (rc 0)" 0 "$ctl"
  mutate_run m1-xtrace-refusal-dropped '[mut:xtrace]' '  *zzz*)' 'xtrace with credentials: exit 78'
  mutate_run m2-cred-check-skipped    '[mut:cred]'    'if false; then' 'empty QH: credentials_unprovisioned'
  mutate_sub m3-floor-removed         '[mut:floor]'   '2026-10-30' '2026-11-02' 'post-floor journald ok=1 row + matching boot: exit 0'
  mutate_sub m4-boot-match-inverted   '[mut:boot]'    '== "$CUR_BOOT"' '!= "$CUR_BOOT"' 'post-floor journald ok=1 row + matching boot: exit 0'
  mutate_sub m5-gen-check-inverted    '[mut:gen]'     '< "$dt"' '> "$dt"' 'stale-generation marker: leg_unit, never PASS'
  mutate_sub m6-arm2-stages-shrunk    '[mut:arm]'     'bs-token-restage-enabled' 'bs-token-never' 'the enabled marker alone satisfies arm-2: exit 0'
  mutate_sub m7-host-isolation-drift  '[mut:host]'    'soleur-inngest' 'soleur-inngest-DRIFT' 'post-floor journald ok=1 row + matching boot: exit 0'
  mutate_sub m8-env-seam-reintroduced '[mut:query-path]' 'QUERY="$SCRIPT_DIR/../betterstack-query.sh"' 'QUERY="${RESTAGE_QUERY_BIN:-$SCRIPT_DIR/../betterstack-query.sh}"' 'an exported RESTAGE_QUERY_BIN is ignored: the evil script never ran'
  mutate_sub m9-tol-zeroed            '[mut:tol]'     'GEN_TOL_S=7200' 'GEN_TOL_S=0' 'post-floor BOOT_STAGE enabled+restaged markers, journald absent: exit 0'
  mutate_sub m10-dtshape-dropped      '[mut:dtshape]' ']] || return 1' ']] || true' 'a garbage-dt ok=1 row: exit 2, never post-floor'
  mutate_sub m11-restaged-qualifies   '[mut:arm2]'    'bs-token-restage-enabled' 'bs-token-restaged' 'post-floor restaged WITHOUT enabled (a plain reboot): exit 2, never 0'
  mutate_sub m12-bootgate-dropped     '[mut:bootgate]' '|| CUR_BOOT=""' '|| true' 'forged boot id never echoes into output'
fi

MIN_FIXTURE=70; MIN_BATTERY=13
LEDGER_N="$(wc -l < "$LEDGER")"
echo; echo "=== inngest-bs-token-restage-7596.sh: $PASS passed, $FAIL failed ($LEDGER_N recorded) ==="
if [ "$LEDGER_N" -ne $((PASS + FAIL)) ]; then printf 'LEDGER MISMATCH\n'; exit 1; fi
if [ -z "${FT_INNER:-}" ]; then
  if [ "$FIX_N" -lt "$MIN_FIXTURE" ]; then printf 'FLOOR: only %s fixture assertions ran, expected at least %s\n' "$FIX_N" "$MIN_FIXTURE"; exit 1; fi
  if run_battery "${1:-}" && [ $((LEDGER_N - FIX_N)) -lt "$MIN_BATTERY" ]; then printf 'FLOOR: only %s battery assertions ran, expected at least %s\n' "$((LEDGER_N - FIX_N))" "$MIN_BATTERY"; exit 1; fi
fi
[ "$FAIL" -eq 0 ]
