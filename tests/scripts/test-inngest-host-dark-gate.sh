#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-host-dark-gate.sh — Guard 2 of the inngest-volume-recut
# apply_target (#7695), the layer that checks the WORLD rather than an intent.
#
# THREE BATTERIES, AND THEY ARE NOT INTERCHANGEABLE:
#
#   1. THE DROP-ONE BATTERY (AC B11) — one case per PREDICATE, twenty of them, each starting from a
#      fully-satisfying baseline and breaking EXACTLY ONE Gn. This is keyed on predicates, NOT on
#      verdict tokens, and the distinction is the trap the AC exists to close: several predicates
#      share a token (three map to `wrong_host`, two to `host_serving`, four to `unreadable`), so a
#      token-keyed battery needs only ~10 cases and SILENTLY UNDER-COVERS — dropping G12 and
#      dropping G15 both still emit `unreadable`, so it cannot tell that one of them was deleted.
#      A floor below asserts twenty distinct predicate cases ran.
#
#   2. THE PLAN'S MUTATION MATRIX (rows 1-15) — input mutations derived from the DESIGN before the
#      guard existed. Several coincide with a drop-one case; they are asserted anyway and labelled
#      with their row number, so a dropped row is visible rather than merely absent.
#
#   3. THE GUARD-MUTATION HARNESS (AC B10) — mechanically runnable, not asserted. It patches a
#      PRISTINE COPY of the gate, neutering one predicate's check at a time, and asserts the verdict
#      CHANGES. Batteries 1 and 2 mutate the INPUT and can all pass against a guard with a dead
#      check that some other check happens to shadow; only this one proves each line is
#      load-bearing. Every row asserts the mutation LANDED (`cmp -s` against the pristine copy)
#      before scoring anything — `sed` exits 0 when it matches nothing, so without that floor a
#      mutation aimed at a guard that drifted emits a byte-identical copy and the row reports the
#      check load-bearing for the weakest possible reason.
#
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only). Deterministic; no network. The
# envelope shape mirrors betterstack-query.sh's JSONEachRow output, including the DOUBLE-ENCODED
# `raw` column — a fixture that skipped the double encoding would put the seam above the decode,
# and the decode is where #7674 measured 0/40 outer matches against 40/40 post-decode.
#
# Run: bash tests/scripts/test-inngest-host-dark-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${DIR}/lib/inngest-host-dark-gate.sh"
# shellcheck source=tests/scripts/lib/inngest-host-dark-gate.sh
source "$GATE"

passes=0
fails=0
predicate_cases=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [[ -n "${2:-}" ]] && echo "      rc=$2" >&2; [[ -n "${3:-}" ]] && echo "      out=$3" >&2; return 0; }

export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d -t inngest-host-dark-gate.XXXXXXXX)" || { echo "FATAL: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ── INSTRUMENT SELF-TEST ──────────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — proves fail() records)" >/dev/null 2>&1
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test did not move both counters (passes %s->%s, fails %s->%s)\n' \
    "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
passes=$_p0; fails=$_f0

VOLID="106261946"          # soleur-inngest-redis-store — the pinned physical volume
OTHERID="105149570"
HOSTV="soleur-inngest"
HOSTNAMEV="soleur-inngest-prd"
DEV="/dev/disk/by-id/scsi-0HC_Volume_${VOLID}"

# ── Fixture builders ──────────────────────────────────────────────────────────────
# bs_line <dt> <host> <host_name> <message> — one betterstack-query.sh JSONEachRow row. `raw` is a
# JSON STRING containing a JSON document (double-encoded), exactly as ClickHouse stores it.
bs_line() {
  jq -cn --arg dt "$1" --arg h "$2" --arg hn "$3" --arg m "$4" \
    '{dt:$dt, raw: ({host:$h, host_name:$hn, message:$m, SYSLOG_IDENTIFIER:"inngest-server-probe"} | tojson)}'
}

# The probe's field list at probe_schema=3, in emit order (pinned against the real emitter by the
# emit/read contract arm near the bottom of this file).
PROBE_FIELDS=(http_code server_active vector_active redis_active uptime_s boot_id image_ref
              instance_id cli_version cutover_flag probe_schema host_role flush_latched
              redis_keys data_mount_src data_bytes)
declare -A PD=(
  [http_code]=000 [server_active]=inactive [vector_active]=active [redis_active]=active
  [uptime_s]=98765 [boot_id]=b0000000000000000000000000000001 [image_ref]=ghcr.io/example@sha256:aaa
  [instance_id]=162809678 [cli_version]=v1.19.4 [cutover_flag]=rolled-back [probe_schema]=3
  [host_role]=dedicated [flush_latched]=false [redis_keys]=0
  [data_mount_src]="__DEV__" [data_bytes]=4096
)
PD[data_mount_src]="$DEV"

# msg <override>… — each override is `field=value`, or `-field` to DROP the field entirely.
# Dropping is a DIFFERENT mutation from setting a bad value, and the plan's rows 12/14/15 are
# specifically about absence: an absent http_code is trivially "non-200" and an absent boot_id
# compared against an absent boot_id is trivially equal.
msg() {
  local -A o=(); local a k v out f val
  for a in "$@"; do
    if [[ "$a" == -* ]]; then o["${a#-}"]="__DROP__"; else k="${a%%=*}"; v="${a#*=}"; o["$k"]="$v"; fi
  done
  out="SOLEUR_INNGEST_SERVER_PROBE"
  for f in "${PROBE_FIELDS[@]}"; do
    val="${o[$f]-${PD[$f]}}"
    [[ "$val" == "__DROP__" ]] && continue
    out+=" ${f}=${val}"
  done
  printf '%s' "$out"
}

# Baseline: one identity-correct, schema-3, dark, empty-store row.
mk_rows() { local f="$1"; shift; : > "$f"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$f"; done; }

ROWS="$TMP/rows.json"
FIN="$TMP/finished.json"
mk_rows "$ROWS" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg)")"
: > "$FIN"

# gate <rows> <finished> [extra args…] — the fully-satisfying dispatch-time inputs, overridable.
gate() {
  local rows="$1" fin="$2"; shift 2
  inngest_host_dark_gate \
    --rows-file "$rows" --query-rc 0 \
    --finished-file "$fin" --finished-rc 0 \
    --expected-volume-id "$VOLID" --live-attachment-id "$VOLID" \
    --followthrough-rc 0 --cutover-flag rolled-back --diagnostic-boot 0 \
    "$@"
}

# expect <label> <want-token> <args to gate…>
expect() {
  local label="$1" want="$2"; shift 2
  local out rc=0 tok want_rc=1
  [[ "$want" == "dark" ]] && want_rc=0
  out="$(gate "$@" 2>&1)" || rc=$?
  tok="$(printf '%s\n' "$out" | tail -1)"
  if [[ "$tok" == "$want" && "$rc" -eq "$want_rc" ]]; then
    pass
  else
    fail "$label (want token='$want' rc=$want_rc, got token='$tok')" "$rc" "$out"
  fi
}

# predicate <Gn> <label> <want-token> <args to gate…> — an expect() that also counts toward the
# drop-one battery's per-PREDICATE floor.
predicate() {
  local gn="$1"; shift
  predicate_cases=$((predicate_cases + 1))
  expect "[$gn] $1" "$2" "${@:3}"
}

# ══ BASELINE (must-PASS) ═════════════════════════════════════════════════════════
# The positive allowlist admits ONLY the literal `dark`. Without this arm every RED case below is
# satisfiable by a gate that refuses everything, and the twenty drop-one cases would prove nothing.
expect "BASELINE: fully satisfying row + dispatch inputs => dark" dark "$ROWS" "$FIN"

# ══ 1. THE DROP-ONE BATTERY — one case per PREDICATE ═════════════════════════════

# G1 — the read path did not answer. `unreadable`, and it is evaluated BEFORE G2 so a 503 is not
# reported as "the host emits nothing".
predicate G1 "probe query rc != 0 => unreadable (not silent)" unreadable "$ROWS" "$FIN" --query-rc 22

# G2 — zero rows from a correctly-identified host. Silence is not evidence of darkness.
: > "$TMP/rows-empty.json"
predicate G2 "zero probe rows => silent" silent "$TMP/rows-empty.json" "$FIN"

# G3 — the newest row is from a DIFFERENT boot than the schema-3 row the gate would read. This is
# the replaced-host shape: "dark" would be a fact about a machine that no longer exists.
mk_rows "$TMP/rows-g3.json" \
  "$(bs_line '2026-09-03 09:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg)")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg -probe_schema boot_id=b0000000000000000000000000000002)")"
predicate G3 "schema-3 row is from a stale boot => stale_row" stale_row "$TMP/rows-g3.json" "$FIN"

# G4 — EXACT equality on the schema, not `>=`.
mk_rows "$TMP/rows-g4.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg probe_schema=2)")"
predicate G4 "probe_schema=2 => stale_schema" stale_schema "$TMP/rows-g4.json" "$FIN"

# G5 — envelope `host` is the web host while `host_name` carries the dedicated literal. This is the
# R_SPOOF shape from scripts/inngest-dedicated-host-classify.sh's suite: #6616 is OPEN because a web
# host HAS been observed self-labelling with the sed-rendered `soleur-inngest-prd` literal, so
# `host` — Vector's auto-derived OS hostname — is the field a stale literal cannot forge.
mk_rows "$TMP/rows-g5.json" "$(bs_line '2026-09-03 10:00:00' 'soleur-web-platform' "$HOSTNAMEV" "$(msg)")"
predicate G5 "R_SPOOF: envelope host is the web host => wrong_host" wrong_host "$TMP/rows-g5.json" "$FIN"

# G6 — the mirror: `host` correct, `host_name` wrong. Either field alone is spoofable, which is why
# they are separate predicates rather than one conjunction case.
mk_rows "$TMP/rows-g6.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" 'soleur-web-prd' "$(msg)")"
predicate G6 "envelope host_name is not soleur-inngest-prd => wrong_host" wrong_host "$TMP/rows-g6.json" "$FIN"

# G7 — the row's own DOPPLER_PROJECT-derived role. §D1: the first implementation inferred this from
# "is /mnt/data a mountpoint", which is TRUE on the web host too, so a web row could have carried a
# store measurement into this gate's clearance condition.
mk_rows "$TMP/rows-g7.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg host_role=web)")"
predicate G7 "host_role=web => wrong_host" wrong_host "$TMP/rows-g7.json" "$FIN"

# G8 — systemd says the unit is running.
mk_rows "$TMP/rows-g8.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg server_active=active)")"
predicate G8 "server_active=active => host_serving" host_serving "$TMP/rows-g8.json" "$FIN"

# G9 — the loopback disagrees with systemd. This host has already been observed reporting a started
# unit that had failed to bind its port, so both signals are required.
mk_rows "$TMP/rows-g9.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg http_code=200)")"
predicate G9 "http_code=200 with server_active=inactive => host_serving" host_serving "$TMP/rows-g9.json" "$FIN"

# G10 — the host executed a function, whatever its own probe says.
mk_rows "$TMP/fin-g10.json" "$(bs_line '2026-09-03 10:05:00' "$HOSTV" "$HOSTNAMEV" 'function.finished id=abc status=Completed')"
predicate G10 "a function.finished row from this host => host_executing" host_executing "$ROWS" "$TMP/fin-g10.json"

# G11 — Redis is down, so its keyspace answer means nothing.
mk_rows "$TMP/rows-g11.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg redis_active=inactive)")"
predicate G11 "redis_active=inactive with redis_keys=0 => redis_down (never dark)" redis_down "$TMP/rows-g11.json" "$FIN"

# G12 — the count is the emitter's "I could not measure this" sentinel. SEPARATE FROM G13: merged,
# `[[ "__UNREADABLE__" -eq 0 ]]` is TRUE under bash arithmetic coercion and the sentinel becomes the
# clearing value.
mk_rows "$TMP/rows-g12.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg redis_keys=__UNREADABLE__)")"
predicate G12 "redis_keys=__UNREADABLE__ => unreadable (NOT coerced to 0)" unreadable "$TMP/rows-g12.json" "$FIN"

# G13 — the store is populated. Refused outright; route to ADR-142's preserve-and-copy.
mk_rows "$TMP/rows-g13.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg redis_keys=3)")"
predicate G13 "redis_keys=3 => store_populated" store_populated "$TMP/rows-g13.json" "$FIN"

# G14 — the measured store is NOT on the device being destroyed. Today's mount is `mount … || true`
# with `nofail`, so a failed mount leaves /mnt/data on the root disk and Redis reports empty WHILE
# THE VOLUME HOLDS A POPULATED AOF.
mk_rows "$TMP/rows-g14.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg data_mount_src=/dev/sda1)")"
predicate G14 "data_mount_src is the root disk => mount_mismatch" mount_mismatch "$TMP/rows-g14.json" "$FIN"
# A DIFFERENT physical volume's by-id path is the same defect one digit over.
mk_rows "$TMP/rows-g14b.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg "data_mount_src=/dev/disk/by-id/scsi-0HC_Volume_${OTHERID}")")"
expect "[G14b] data_mount_src pins a DIFFERENT volume => mount_mismatch" mount_mismatch "$TMP/rows-g14b.json" "$FIN"

# G15 — readability only, no ceiling. A size threshold here would be a made-up number; the honest
# guard is that the only surviving record of what is about to be destroyed was actually measured.
mk_rows "$TMP/rows-g15.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg data_bytes=__UNREADABLE__)")"
predicate G15 "data_bytes=__UNREADABLE__ => unreadable" unreadable "$TMP/rows-g15.json" "$FIN"
# …and a LARGE readable value must still PASS, or G15 is a ceiling in disguise. This is the arm that
# makes "readability only" a testable claim rather than a comment.
mk_rows "$TMP/rows-g15b.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg data_bytes=98765432100)")"
expect "[G15b] a LARGE readable data_bytes still => dark (readability only, no ceiling)" dark "$TMP/rows-g15b.json" "$FIN"

# G16 — readability only. `[ -f ]` cannot distinguish "no latch" from "cannot read the directory",
# so accepting `false` without this check would accept a positive claim about a store never read.
mk_rows "$TMP/rows-g16.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg flush_latched=__UNREADABLE__)")"
predicate G16 "flush_latched=__UNREADABLE__ => unreadable" unreadable "$TMP/rows-g16.json" "$FIN"
# BOTH polarities must PASS, or the readability check is a polarity check in disguise.
mk_rows "$TMP/rows-g16b.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg flush_latched=true)")"
expect "[G16b] flush_latched=true still => dark (neither polarity blocks)" dark "$TMP/rows-g16b.json" "$FIN"

# G17 — the LIVE Hetzner attachment disagrees with the operator's pin. Guard 1's ID-PIN reads a plan
# document; this one reads the world, and it is the world that gets destroyed.
predicate G17 "live attachment id != the pin => id_pin_mismatch" id_pin_mismatch "$ROWS" "$FIN" --live-attachment-id "$OTHERID"
expect "[G17b] an UNREADABLE live attachment id => id_pin_mismatch (fail-closed)" id_pin_mismatch "$ROWS" "$FIN" --live-attachment-id ""

# G18 — #7674 has not read PASS. Without it the recut is strictly counterproductive: the first arm
# would write a fresh latch, fail verify_or_abort, and land in terminal `aborted` with the store gone.
predicate G18 "followthrough 7674 is TRANSIENT => followthrough_7674" followthrough_7674 "$ROWS" "$FIN" --followthrough-rc 2

# G19 — the flag, RE-READ SYNCHRONOUSLY at dispatch. This is step (3) of the gate's monotonicity
# argument: without it, "the key count cannot increase between the row and the apply" is unproven.
predicate G19 "cutover flag = arm => flag_unsafe" flag_unsafe "$ROWS" "$FIN" --cutover-flag arm
expect "[G19b] cutover flag = aborted => dark (the other safe terminal state)" dark "$ROWS" "$FIN" --cutover-flag aborted

# G20 — diagnostic boot still set: #7228's defect reproduced one layer over, with the latch burned.
predicate G20 "INNGEST_DIAGNOSTIC_BOOT=1 => diagnostic_boot" diagnostic_boot "$ROWS" "$FIN" --diagnostic-boot 1
expect "[G20b] INNGEST_DIAGNOSTIC_BOOT unset => dark" dark "$ROWS" "$FIN" --diagnostic-boot ""

# ══ 2. THE PLAN'S MUTATION MATRIX — the rows not already covered above ═══════════
# Rows 1,2,3,4,5,7,9,11 coincide with G8,G9,G10,G1,G2,G13,G3,G11 and are asserted there. Row 6 is a
# workflow-dispatch row (below). Row 8 is the db-0-only reading (AC B13, below). The rest are
# ABSENCE mutations, which are a different class from a bad value and are asserted here.

# Row 12 — redis_keys absent from the row entirely. Absence must not parse to 0.
mk_rows "$TMP/rows-m12.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg -redis_keys)")"
expect "[Row 12] redis_keys ABSENT => unreadable (absence must not parse to 0)" unreadable "$TMP/rows-m12.json" "$FIN"

# Row 13 — a row from the pre-schema emitter. This is the EXPECTED verdict for every dispatch until
# the host is replaced: the running host's boot_id has been unchanged for weeks, so it emits no
# probe_schema at all. Intended, common, must abort, and must stay its own token — it is actionable
# ("replace the host first") where `unreadable` is not.
mk_rows "$TMP/rows-m13.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg -probe_schema)")"
expect "[Row 13] no probe_schema at all => stale_schema (the expected pre-replace verdict)" stale_schema "$TMP/rows-m13.json" "$FIN"

# Row 14 — http_code absent. Absence must not read as "non-200".
mk_rows "$TMP/rows-m14.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg -http_code)")"
expect "[Row 14] http_code ABSENT => unreadable (absence is not 'non-200')" unreadable "$TMP/rows-m14.json" "$FIN"

# Row 15 — boot_id absent from BOTH the chosen and the newest row. "" == "" must not satisfy the pin.
mk_rows "$TMP/rows-m15.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg -boot_id)")"
expect "[Row 15] boot_id ABSENT from both rows => unreadable ('' == '' is not a pin)" unreadable "$TMP/rows-m15.json" "$FIN"

# Row 10 — conditions satisfied on TWO DIFFERENT ROWS. The gate must read every field from ONE row,
# or it authorizes on a state that never simultaneously existed. Older row: dark host, populated
# store. Newer row: empty store, but the host is serving. Neither row alone clears; a gate that
# joined across rows would see `server_active=inactive` and `redis_keys=0` and call it dark.
mk_rows "$TMP/rows-m10.json" \
  "$(bs_line '2026-09-03 09:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg redis_keys=42)")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg server_active=active http_code=200)")"
expect "[Row 10] the two halves live on DIFFERENT rows => host_serving (never joined)" host_serving "$TMP/rows-m10.json" "$FIN"

# A malformed line must not lose the valid rows after it — the `-R` + `fromjson?` contract. Without
# it ONE truncated warehouse line aborts the whole jq invocation and every later row is dropped,
# which surfaces as `silent` on a window that in fact contained a clean reading.
mk_rows "$TMP/rows-torn.json" \
  'not json{{{' \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg)")"
expect "a malformed line does not swallow the valid rows after it => dark" dark "$TMP/rows-torn.json" "$FIN"

# The outer row must NOT be substring-matched: `raw` is double-encoded, so a gate greping the outer
# line for host_name would read zero rows FOREVER. A row whose OUTER json mentions the host but
# whose decoded payload is a different host must not count.
printf '%s\n' "$(jq -cn --arg m "$(msg)" '{dt:"2026-09-03 10:00:00", host_name:"soleur-inngest-prd", raw: ({host:"soleur-web-platform", host_name:"soleur-web-prd", message:$m}|tojson)}')" > "$TMP/rows-outer.json"
expect "outer-envelope host_name must not launder a foreign row => wrong_host" wrong_host "$TMP/rows-outer.json" "$FIN"

# Unreadable function.finished query: "the query failed" must not read as "zero rows, therefore none".
expect "function.finished query rc != 0 => unreadable (not 'no functions ran')" unreadable "$ROWS" "$FIN" --finished-rc 7

# ══ 3. H-ROWS ════════════════════════════════════════════════════════════════════

# H3 (must-PASS, non-canonical) — THE REAL PRODUCTION SHAPE. A busy fleet: function.finished rows
# are present in the window, but every one of them belongs to the web host. If this fails the gate is
# unusable exactly when it is needed, and the operator's only recourse is to bypass it.
mk_rows "$TMP/fin-h3.json" \
  "$(bs_line '2026-09-03 10:01:00' 'soleur-web-platform' 'soleur-web-prd' 'function.finished id=aaa status=Completed')" \
  "$(bs_line '2026-09-03 10:02:00' 'soleur-web-platform' 'soleur-web-prd' 'function.finished id=bbb status=Completed')"
expect "H3: busy fleet, dark inngest host => dark (function.finished all belong to web)" dark "$ROWS" "$TMP/fin-h3.json"

# H3b — and probe rows from BOTH hosts in the window: the dedicated host's row must be the one read.
mk_rows "$TMP/rows-h3b.json" \
  "$(bs_line '2026-09-03 09:59:00' 'soleur-web-platform' 'soleur-web-prd' "$(msg server_active=active http_code=200 host_role=web)")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg)")"
expect "H3b: a serving WEB row in the same window => dark (identity filter selects the right row)" dark "$TMP/rows-h3b.json" "$TMP/fin-h3.json"

# H2 — a decision function stuck at `dark` is caught ONLY by a must-FAIL pairing that asserts the
# TOKEN. Every RED arm above compares the token, not merely the rc, so an always-dark gate reddens
# all of them. Asserted explicitly so the dependency is legible.
_always_dark="$TMP/always-dark.sh"
sed 's|^  _ihdg_verdict "dark"$|  _ihdg_verdict "dark"|; s|_ihdg_verdict "store_populated"|_ihdg_verdict "dark"|' "$GATE" > "$_always_dark"
if cmp -s "$_always_dark" "$GATE"; then
  fail "H2: the always-dark mutation matched NOTHING; the verdict shape drifted"
else
  _rc=0; _out="$(bash -c "source '$_always_dark'; inngest_host_dark_gate --rows-file '$TMP/rows-g13.json' --query-rc 0 --finished-file '$FIN' --finished-rc 0 --expected-volume-id '$VOLID' --live-attachment-id '$VOLID' --followthrough-rc 0 --cutover-flag rolled-back --diagnostic-boot 0" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 0 && "$(printf '%s\n' "$_out" | tail -1)" == "dark" ]]; then
    pass   # the mutation is detectable: the G13 arm above asserts `store_populated` and would redden
  else
    fail "H2: neutering the store_populated verdict did not produce a false 'dark'; the arm cannot be shown load-bearing" "$_rc" "$_out"
  fi
fi

# ══ AC B13 — the db-0-only reading is absent from the gate by NAME ═══════════════
# `redis_keys` is summed from `INFO keyspace` across every database. The single-database size
# command reads db-0 only while `FLUSHALL` spans every db, so a store with keys in db-1 reads zero
# under it — a false `dark` authorizing a destroy. The historical `latch_dbsize` probe field carried
# exactly that asymmetry and sits one field name away.
if [[ "$(grep -c 'DBSIZE' "$GATE" || true)" == "0" ]]; then pass; else fail "B13: the gate mentions DBSIZE"; fi
if [[ "$(grep -c 'latch_dbsize' "$GATE" || true)" == "0" ]]; then pass; else fail "B13: the gate mentions latch_dbsize"; fi
# …and behaviourally: a row carrying BOTH a db-0-only reading of 0 and a true redis_keys of 5 must
# refuse. A gate that read the wrong field would call this dark.
mk_rows "$TMP/rows-b13.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(msg redis_keys=5) latch_dbsize=0")"
expect "B13: a db-0-only zero alongside redis_keys=5 => store_populated" store_populated "$TMP/rows-b13.json" "$FIN"

# ══ AC B12 — the EMIT/READ contract, against the REAL emitter ════════════════════
# Nothing else pins that the gate reads the field names the probe actually writes. A gate whose
# extractor names drifted from the emitter would report `unreadable` in production forever while
# every fixture above — built from the same drifted names — stayed green. The fixture seam sits
# above the emitter, so this arm reaches around it.
BOOTSTRAP="${REPO_ROOT}/apps/web-platform/infra/inngest-bootstrap.sh"
if [[ ! -f "$BOOTSTRAP" ]]; then
  fail "B12: inngest-bootstrap.sh not found at $BOOTSTRAP"
else
  EMIT_LINE="$(grep -F 'SOLEUR_INNGEST_SERVER_PROBE' "$BOOTSTRAP" | grep -F 'logger -t' | head -1)"
  if [[ -z "$EMIT_LINE" ]]; then
    fail "B12: could not locate the emitter's logger line in inngest-bootstrap.sh"
  else
    # Field names the REAL emitter writes, as `name=$var` pairs.
    EMITTED="$(printf '%s\n' "$EMIT_LINE" | grep -oE '[a-z_]+=\$[a-z_]+' | sed 's/=.*//' | sort -u)"
    _missing=""
    for _f in boot_id probe_schema host_role server_active http_code redis_active redis_keys data_mount_src data_bytes flush_latched; do
      printf '%s\n' "$EMITTED" | grep -qx "$_f" || _missing="${_missing} ${_f}"
    done
    if [[ -z "$_missing" ]]; then pass; else fail "B12: the gate consumes field(s) the emitter does not write:${_missing}"; fi
    # And every one of those names must resolve through the gate's OWN extractor on a message built
    # from the real emitter's field list — the parser, not just the name list.
    _real_msg="SOLEUR_INNGEST_SERVER_PROBE"
    while IFS= read -r _f; do
      [[ -n "$_f" ]] || continue
      _real_msg+=" ${_f}=${PD[$_f]:-x}"
    done <<< "$EMITTED"
    _unresolved=""
    for _f in boot_id probe_schema host_role server_active http_code redis_active redis_keys data_mount_src data_bytes flush_latched; do
      _ihdg_field "$_real_msg" "$_f" >/dev/null || _unresolved="${_unresolved} ${_f}"
    done
    if [[ -z "$_unresolved" ]]; then pass; else fail "B12: the gate's extractor did not resolve:${_unresolved} from a real-emitter-shaped line"; fi
    # The whole real-emitter-shaped line must clear the gate, or the contract is name-level only.
    mk_rows "$TMP/rows-b12.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$_real_msg")"
    expect "B12: a message built from the REAL emitter's field list => dark" dark "$TMP/rows-b12.json" "$FIN"
  fi
fi

# ══ Row 6 — the guard's own dispatch: SOURCED and CALLED by the workflow ═════════
# A guard that reports "0 checked" and exits 0 is vacuous, and nothing inside the gate function can
# see its own call site.
WF="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"
if grep -qF 'tests/scripts/lib/inngest-host-dark-gate.sh' "$WF"; then pass; else fail "Row 6a: the workflow does not SOURCE inngest-host-dark-gate.sh"; fi
if grep -qE '^[[:space:]]*if ! inngest_host_dark_gate ' "$WF"; then pass; else fail "Row 6b: the workflow does not CALL inngest_host_dark_gate under a non-suppressing 'if !'"; fi

# ══ 4. THE GUARD-MUTATION HARNESS (AC B10) ══════════════════════════════════════
# Mechanically runnable: each row patches a PRISTINE COPY of the gate, neutering ONE predicate's
# check, and asserts the verdict for that predicate's bad input CHANGES. Input batteries can all
# pass against a guard with a dead check that some later check happens to shadow; only this proves
# each line is load-bearing.
#
# THE PRISTINE COPY IS A `cp`, NOT `git checkout` — a battery that restores from HEAD reverts an
# UNCOMMITTED fix and then scores the DEFECT against itself, reporting SURVIVED while measuring a
# file that no longer contains the thing under test.
PRISTINE="$TMP/pristine-gate.sh"
cp "$GATE" "$PRISTINE" || { echo "FATAL: could not snapshot the gate" >&2; exit 2; }

# mutate <Gn> <sed-expr> <rows-file> <expected-unmutated-token> [extra gate args…]
mutate() {
  local gn="$1" expr="$2" rows="$3" tok="$4"; shift 4
  local mutated="$TMP/mut-${gn}.sh" out rc=0 got
  sed "$expr" "$PRISTINE" > "$mutated"
  if cmp -s "$mutated" "$PRISTINE"; then
    fail "B10[$gn]: the mutation matched NOTHING in the gate (byte-identical copy); the check drifted or was deleted. This row would have reported a vacuous pass."
    return
  fi
  # …AND IT MUST HAVE CHANGED EXACTLY ONE LINE. `cmp -s` only proves the file moved: a sed whose
  # pattern is broader than intended (a loose alternation, an under-anchored `.`) mangles several
  # lines at once, the verdict duly changes, and the row reports the target check load-bearing when
  # what it actually measured was collateral damage somewhere else in the gate.
  local _changed
  _changed="$(diff "$PRISTINE" "$mutated" | grep -c '^<' || true)"
  if [[ "$_changed" != "1" ]]; then
    fail "B10[$gn]: the mutation changed ${_changed} lines, expected exactly 1 — the sed pattern is broader than the check it names, so this row measures collateral damage rather than the target."
    return
  fi
  # Unmutated control FIRST: if the fixture does not drive this token today, the row proves nothing.
  local base; base="$(gate "$rows" "$FIN" "$@" 2>&1 | tail -1)"
  if [[ "$base" != "$tok" ]]; then
    fail "B10[$gn]: the UNMUTATED gate did not return '$tok' for this fixture (got '$base'); the row does not exercise the check."
    return
  fi
  out="$(bash -c "source '$mutated'; inngest_host_dark_gate --rows-file '$rows' --query-rc 0 --finished-file '${FIN2:-$FIN}' --finished-rc 0 --expected-volume-id '$VOLID' --live-attachment-id '${LIVEID:-$VOLID}' --followthrough-rc '${FTRC:-0}' --cutover-flag '${FLAGV:-rolled-back}' --diagnostic-boot '${DBOOT:-0}'" 2>&1)" || rc=$?
  got="$(printf '%s\n' "$out" | tail -1)"
  if [[ "$got" != "$tok" ]]; then
    pass
  else
    fail "B10[$gn]: neutering the check did NOT change the verdict (still '$tok'); the line may be dead code shadowed by another check." "$rc" "$out"
  fi
}

mutate G4  's|^  \[\[ "\$schema" == "\$expected_schema" \]\].*|  :|'                 "$TMP/rows-g4.json"  stale_schema
mutate G7  's|^  \[\[ "\$host_role" == "dedicated" \]\].*|  :|'                      "$TMP/rows-g7.json"  wrong_host
mutate G8  's|^  \[\[ "\$server_active" == "inactive" \]\].*|  :|'                   "$TMP/rows-g8.json"  host_serving
mutate G9  's|^  \[\[ "\$http_code" != "200" \]\].*|  :|'                            "$TMP/rows-g9.json"  host_serving
mutate G11 's|^  \[\[ "\$redis_active" == "active" \]\].*|  :|'                      "$TMP/rows-g11.json" redis_down
mutate G12 's|^  \[\[ "\$redis_keys" =~ \^\[0-9\]+\$ \]\].*|  :|'                    "$TMP/rows-g12.json" unreadable
mutate G13 's|^  \[\[ "\$redis_keys" -eq 0 \]\].*|  :|'                              "$TMP/rows-g13.json" store_populated
mutate G15 's|^  \[\[ "\$data_bytes" =~ \^\[0-9\]+\$ \]\].*|  :|'                    "$TMP/rows-g15.json" unreadable

# G14's check is a multi-line `if`; neuter its condition rather than a single `[[ … ]]` line.
mutate G14 's|^  if \[\[ "\$data_mount_src" != "\$expected_dev".*|  if false; then|' "$TMP/rows-g14.json" mount_mismatch

# G3's pin and G2's silence arm.
mutate G3  's|^  \[\[ "\$chosen_boot" == "\$newest_boot" \]\].*|  :|'                "$TMP/rows-g3.json"  stale_row
mutate G2  's|^    _ihdg_verdict "silent"; return \$?|    :|'                        "$TMP/rows-empty.json" silent

# The dispatch-time predicates: same contract, driven through the extra gate args.
LIVEID="$OTHERID" mutate G17 's|^  \[\[ "\$live_attachment_id" == "\$expected_volume_id" \]\].*|  :|' "$ROWS" id_pin_mismatch --live-attachment-id "$OTHERID"
FTRC=2            mutate G18 's|^  \[\[ "\$followthrough_rc" -eq 0 \]\].*|  :|'                        "$ROWS" followthrough_7674 --followthrough-rc 2
FLAGV=arm         mutate G19 's|^    rolled-back\|aborted) : ;;|    *) : ;;|'                          "$ROWS" flag_unsafe --cutover-flag arm
DBOOT=1           mutate G20 's|^    ..\|0) : ;;|    *) : ;;|'                                         "$ROWS" diagnostic_boot --diagnostic-boot 1
unset LIVEID FTRC FLAGV DBOOT

# ══ 5. THE GUARD'S OWN OPERANDS (the axis every other battery misses) ═══════════
# Batteries 1-4 all mutate the SUT or the input and confirm the guard REDS. None of them asks how
# the guard fails OPEN. This one degenerates an operand the guard itself INTERPOLATES — the kind of
# value that turns a containment test into a wildcard — and asserts the verdict is still a refusal.
#
# The shape being guarded against: `expected_dev="/dev/disk/by-id/scsi-0HC_Volume_${id}"` with an
# empty `$id` yields a PREFIX that no real device matches (safe), but the same construction one
# character different — a glob, a regex, a path prefix — degrades to "matches everything" and the
# guard accepts every input while looking exactly like a healthy run. A guard that accepts
# everything is indistinguishable from a healthy run, which is why this cannot be caught by
# reading the pass counts.
expect "OPERAND: an EMPTY volume-id pin must refuse, never build a matching device prefix" id_pin_mismatch "$ROWS" "$FIN" --expected-volume-id ""
expect "OPERAND: a non-numeric volume-id pin must refuse" id_pin_mismatch "$ROWS" "$FIN" --expected-volume-id "*"
expect "OPERAND: an EMPTY expected-schema must refuse, not match every schema" stale_schema "$ROWS" "$FIN" --expected-schema ""
expect "OPERAND: an EMPTY host identity must refuse, not match every host" wrong_host "$ROWS" "$FIN" --host ""
expect "OPERAND: an EMPTY host_name identity must refuse" wrong_host "$ROWS" "$FIN" --host-name ""
expect "OPERAND: a non-numeric query rc must refuse, not coerce to success" unreadable "$ROWS" "$FIN" --query-rc "x"
expect "OPERAND: a non-numeric followthrough rc must refuse" followthrough_7674 "$ROWS" "$FIN" --followthrough-rc ""
expect "OPERAND: an unknown flag must refuse, never fall through to a decision" unreadable "$ROWS" "$FIN" --not-a-real-flag 1

# ══ FLOORS ═══════════════════════════════════════════════════════════════════════
# TWO floors, and they measure different things. The predicate floor is the one AC B11 is about: a
# battery keyed on verdict TOKENS needs only ~10 cases because several predicates share a token, so
# a token-keyed battery silently under-covers and this floor is what makes that visible.
if [[ "$predicate_cases" -lt 20 ]]; then
  fails=$((fails + 1))
  printf '  FAIL DROP-ONE FLOOR: only %s per-PREDICATE cases ran, floor is 20 (G1..G20).\n' "$predicate_cases" >&2
else
  printf '  ok   drop-one floor: %s per-predicate cases ran (floor 20)\n' "$predicate_cases"
fi

# The assertion floor is self-contained — bash builtins and this suite's own counters only. A floor
# that lives in a helper is silenced by the same move that silences the arms it guards.
_ran=$((passes + fails))
if [[ "$_ran" -lt 55 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 63. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" >&2
  printf 'inngest-host-dark-gate: %s passed, %s failed\n' "$passes" "$fails"
  exit 1
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 63)\n' "$_ran"
fi

echo ""
echo "inngest-host-dark-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
