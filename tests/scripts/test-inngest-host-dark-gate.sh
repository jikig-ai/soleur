#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-host-dark-gate.sh — its one live entry point,
# `inngest_execute_registry_gate`, op=execute 2.0's positively-dark pre-flight (#8054), and the
# `_ihdg_*` probe-row helpers it shares. (The library's other entry point, `inngest_host_dark_gate`,
# "Guard 2" of the retired `inngest-volume-recut` apply_target, was deleted under #8316 together
# with the sections of this file that exercised it; `git show b6d745fe78:<this file>` recovers them.)
#
# TWO BATTERIES, AND THEY ARE NOT INTERCHANGEABLE:
#
#   1. THE DROP-ONE BATTERY (section 6.1) — one case per PREDICATE, E1..E14, each starting from a
#      fully-satisfying baseline and breaking EXACTLY ONE En. This is keyed on predicates, NOT on
#      verdict tokens, and the distinction is the trap it exists to close: several predicates share
#      a token (three map to `wrong_host`, two to `host_serving`, several to `unreadable`), so a
#      token-keyed battery needs only ~10 cases and SILENTLY UNDER-COVERS — dropping E7 and
#      dropping E9 both still emit `unreadable`, so it cannot tell that one of them was deleted.
#      A floor below asserts the distinct predicate cases that ran.
#
#   2. THE GUARD-MUTATION HARNESS (section 6.4) — mechanically runnable, not asserted. It patches a
#      PRISTINE COPY of the gate, neutering one predicate's check at a time, and asserts the verdict
#      CHANGES. Battery 1 mutates the INPUT and can pass against a guard with a dead check that
#      some other check happens to shadow; only this one proves each line is load-bearing. Every
#      row asserts the mutation LANDED (`cmp -s` against the pristine copy) before scoring anything
#      — `sed` exits 0 when it matches nothing, so without that floor a mutation aimed at a guard
#      that drifted emits a byte-identical copy and the row reports the check load-bearing for the
#      weakest possible reason.
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
# THE PROBE-ROW SELECTOR LIVES IN scripts/lib/inngest-probe-row.sh (#8846), and the gate resolves it
# relative to ITS OWN location. Every copy this suite runs from $TMP — the B10 mutants, the H2
# always-dark copies, the canary in section 7 — sits outside the repo, so without this override
# each copy would refuse `unreadable` on its missing selector and every mutation row would score a
# VACUOUS kill. EXPORTED, and assigned (not `:-`-defaulted) so a stray caller value cannot redirect
# it. The default-path resolution is asserted separately in section 7 with the override unset.
export INNGEST_PROBE_ROW_LIB="${REPO_ROOT}/scripts/lib/inngest-probe-row.sh"
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
HOSTV="soleur-inngest"
HOSTNAMEV="soleur-inngest-prd"
# data_mount_src is an AUDIT field since #8017, not the pin. It carries what findmnt actually
# reports on a real host -- a KERNEL device name -- because a synthesized by-id string here was
# exactly what let the unreachable comparison look tested (cq-assert-anchor-not-bare-token).
DEV="/dev/sdb"
DEVID="scsi-0HC_Volume_${VOLID}"       # the volume pin the retired gate's G14 compared (#8017); kept as a fixture field
DEVBASE="sdb"

# ── Fixture builders ──────────────────────────────────────────────────────────────
# bs_line <dt> <host> <host_name> <message> [SYSLOG_IDENTIFIER] [_BOOT_ID] — one
# betterstack-query.sh JSONEachRow row. `raw` is a JSON STRING containing a JSON document
# (double-encoded), exactly as ClickHouse stores it. The two trailing args are OPTIONAL and every
# pre-#8054 call site passes four: the identifier defaults to the probe's tag, and the journald
# envelope `_BOOT_ID` is emitted only when given (a probe row that carries none is the shape the
# pre-Vector-envelope fixtures already exercise, and the execute gate joins on the MESSAGE's
# `boot_id=`, never on the probe row's envelope).
bs_line() {
  local ident="${5:-inngest-server-probe}" bid="${6-}"
  jq -cn --arg dt "$1" --arg h "$2" --arg hn "$3" --arg m "$4" --arg id "$ident" --arg b "$bid" \
    '{dt:$dt, raw: (({host:$h, host_name:$hn, message:$m, SYSLOG_IDENTIFIER:$id}
                     + (if $b == "" then {} else {_BOOT_ID:$b} end)) | tojson)}'
}

# hb_line <dt> <host> <host_name> <_BOOT_ID> <flag> [reason] [SYSLOG_IDENTIFIER] — one
# `inngest-cutover-flip` heartbeat row as the WAREHOUSE holds it: `.message` is a PARSED OBJECT
# `{flag, reason, guard, exit_code, start_ts}` (measured 2026-09-11). The FSM logs a JSON string,
# Vector re-encodes it as a string (`vector.toml` ends every transform in `encode_json`), and it
# is Better Stack's ingest-side parse that yields the object the execute gate reads via
# `.message.flag`. `_BOOT_ID` is a REQUIRED
# positional, never derived from the probe row a fixture pairs it with: a default that copied the
# probe's boot would make the cross-stream join a tautology in every fixture.
hb_line() {
  [[ $# -ge 5 ]] || { printf 'FATAL: hb_line needs <dt> <host> <host_name> <_BOOT_ID> <flag>\n' >&2; exit 2; }
  local reason="${6:-noop-$5}" ident="${7:-inngest-cutover-flip}"
  jq -cn --arg dt "$1" --arg h "$2" --arg hn "$3" --arg b "$4" --arg f "$5" --arg r "$reason" --arg id "$ident" \
    '{dt:$dt, raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:$id, _BOOT_ID:$b,
                     message:{flag:$f, reason:$r, guard:"7761", exit_code:0, start_ts:1788430000}} | tojson)}'
}

# The probe's field list at probe_schema=7, in emit order (pinned against the real emitter by the
# emit/read contract arm near the bottom of this file).
# probe_schema=8 (#8017/#8015). The three new fields go at the TAIL, after data_bytes, so they
# sit downstream of the histogram's substr(out, 1, 400) cap and cannot displace an existing field.
PROBE_FIELDS=(http_code server_active vector_active redis_active uptime_s boot_id image_ref
              instance_id cli_version cutover_flag probe_schema host_role flush_latched
              redis_keys redis_expires redis_key_patterns data_mount_src data_bytes
              data_mount_base data_mount_devid registry_fns)
declare -A PD=(
  [http_code]=000 [server_active]=inactive [vector_active]=active [redis_active]=active
  # boot_id is HYPHENATED, as /proc/sys/kernel/random/boot_id renders it (measured live:
  # `402c0d5b-1cf3-495a-92e1-cf137732156f`); the journald envelope `_BOOT_ID` is the same value
  # with the hyphens stripped, and that strip is the cross-stream join key (#8054, E7/E13).
  [uptime_s]=98765 [boot_id]=b0000000-0000-4000-8000-000000000001 [image_ref]=ghcr.io/example@sha256:aaa
  [instance_id]=162809678 [cli_version]=v1.19.4 [cutover_flag]=rolled-back [probe_schema]=8
  [host_role]=dedicated [flush_latched]=false [redis_keys]=0
  # __NONE__ is the COHERENT partner of redis_keys=0 (the retired gate's G14). The execute gate never
  # reads it; a default of __UNREADABLE__ here would only make the fixture incoherent.
  [redis_key_patterns]=__NONE__
  # Coherent with redis_keys=0: an empty store has nothing carrying a TTL either.
  [redis_expires]=0
  [data_mount_src]="__DEV__" [data_bytes]=4096
  # #8017: the DEFAULT must be the PASSING identity, so every unrelated case exercises its own
  # predicate rather than collapsing on the retired gate's G14 -- the same reasoning the redis_key_patterns default
  # above records. registry_fns defaults non-zero for the same reason (a 0 is the diagnostic-boot
  # signature and would make unrelated rows fail #8015's discriminator instead of their own).
  [data_mount_base]="__DEVBASE__" [data_mount_devid]="__DEVID__" [registry_fns]=7
)
PD[data_mount_src]="$DEV"
PD[data_mount_base]="$DEVBASE"
PD[data_mount_devid]="$DEVID"

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
# P1b relative-operand rule (#7810): `: > "$f"` TRUNCATES whatever the caller names, and `$f` is a
# positional this function cannot see the root of. Every caller passes "$TMP/...", but that is a
# fact about the callers, not about this line — and a future caller passing a bare filename would
# silently truncate a file in the CWD, which for a suite run from the repo root is a tracked file.
_mk_rows_abs() {
  case "${1-}" in
    "")            printf 'FATAL: mk_rows target is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..)   printf 'FATAL: mk_rows target %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /*)            : ;;
    *)             printf 'FATAL: mk_rows target %s is RELATIVE; refusing to truncate it\n' "$1" >&2; exit 2 ;;
  esac
}
mk_rows() { local f="$1"; shift; _mk_rows_abs "$f"; : > "$f"; local l; for l in "$@"; do printf '%s\n' "$l" >> "$f"; done; }


# THE CLOCK IS PINNED FOR THE WHOLE SUITE, not just for E5's cases. Every fixture here is dated
# 2026-09-03 ~10:00 UTC, and E5 bounds the newest row's age against the real clock — so without
# this the suite passed this morning and would have started failing at 11:30 UTC and every day
# after, as a "flaky test" whose cause is a real predicate doing its job. `gate()` appends the
# caller's arguments AFTER the defaults and the parser takes the last assignment, so the E5 cases
# still override it.
#   1788430200 = 2026-09-03 10:10:00 UTC — ten minutes after the baseline row.
NOW=1788430200

# gate <rows> <heartbeat-file> [extra args…] — the fully-satisfying dispatch inputs, overridable.
#
# DISPATCHES ON `GATE_FN`, defaulting to the lib's one entry point. The harness stays parameterised
# so a mutated COPY of the gate (the guard-mutation harness) and a differently-sourced copy (the
# selector canary) run through the same argument list, and so a wrapper bug that stops dispatching
# on `GATE_FN` is caught by the ERG SELF-TEST rather than silently grading the wrong function.
_gate_default_args() {
  local rows="$1" second="$2"
  case "${GATE_FN:-inngest_execute_registry_gate}" in
    inngest_execute_registry_gate)
      printf '%s\n' --rows-file "$rows" --query-rc 0 \
        --hb-file "$second" --hb-rc 0 \
        --now-epoch "$NOW" ;;
    *) printf 'FATAL: GATE_FN=%s is not an entry point of the lib\n' "${GATE_FN}" >&2; exit 2 ;;
  esac
}
gate() {
  local rows="$1" second="$2"; shift 2
  local -a args=()
  # Herestring, not process substitution: `< <(…)` needs /dev/fd, which a bwrap sandbox without
  # `--proc /proc` (a nested user namespace, e.g. preflight Check 10 on the containerized path)
  # does not provide — measured: every case graded `unreadable` with `/dev/fd/63: No such file`.
  local _defaults; _defaults="$(_gate_default_args "$rows" "$second")"
  mapfile -t args <<< "$_defaults"
  "${GATE_FN:-inngest_execute_registry_gate}" "${args[@]}" "$@"
}

# expect <label> <want-token> <args to gate…>
_seen_tokens=""
expect() {
  local label="$1" want="$2"; shift 2
  local out rc=0 tok want_rc=1
  # TOKEN COVERAGE IS A RUNTIME FLOOR, NOT A GREP (AC4). Tokens are bare words to this wrapper, so a
  # grep over the suite measures MENTION, not assertion (measured: `grep -cF '"wrong_host"'` is 0
  # while `wrong_host` is asserted seven times). Record what was actually asserted.
  _seen_tokens="${_seen_tokens} ${want}"
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
  # COUNT DISTINCT PREDICATES, not calls. A floor over the call count is satisfied by twenty
  # `predicate E1 …` lines — the exact under-coverage the floor was written to make visible, one
  # level up. The set is what the floor now reads.
  case " ${_seen_predicates:-} " in *" $gn "*) : ;; *) _seen_predicates="${_seen_predicates:-} $gn" ;; esac
  expect "[$gn] $1" "$2" "${@:3}"
}

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
    for _f in boot_id probe_schema host_role server_active http_code cutover_flag registry_fns; do
      printf '%s\n' "$EMITTED" | grep -cx >/dev/null "$_f" || _missing="${_missing} ${_f}"
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
    for _f in boot_id probe_schema host_role server_active http_code cutover_flag registry_fns; do
      _ihdg_field "$_real_msg" "$_f" >/dev/null || _unresolved="${_unresolved} ${_f}"
    done
    if [[ -z "$_unresolved" ]]; then pass; else fail "B12: the gate's extractor did not resolve:${_unresolved} from a real-emitter-shaped line"; fi
    # The whole real-emitter-shaped line must clear the gate, or the contract is name-level only:
    # the emitter's field list, valued as the measured pre-arm row, is built here and asserted
    # `dark` further down (the heartbeat fixture it pairs with is built in section 6).
    _real_msg_erg="SOLEUR_INNGEST_SERVER_PROBE"
    while IFS= read -r _f; do
      [[ -n "$_f" ]] || continue
      case "$_f" in
        boot_id)       _real_msg_erg+=" boot_id=a1b2c3d4-0000-4000-8000-00000000cafe" ;;
        server_active) _real_msg_erg+=" server_active=activating" ;;
        cutover_flag)  _real_msg_erg+=" cutover_flag=aborted" ;;
        registry_fns)  _real_msg_erg+=" registry_fns=__UNREADABLE__" ;;
        redis_keys)    _real_msg_erg+=" redis_keys=16" ;;
        *)             _real_msg_erg+=" ${_f}=${PD[$_f]:-x}" ;;
      esac
    done <<< "$EMITTED"
    B12_ERG_MSG="$_real_msg_erg"
    # The EMITTER's schema literal and the LIB's constant are one number, cross-pinned here: a bump
    # that lands in inngest-bootstrap.sh alone would make the execute gate refuse `stale_schema` on every
    # dispatch until someone ran one — the #8054 fail-closed-and-unnoticed class.
    _emit_schema="$(grep -oE '^probe_schema=[0-9]+' "$BOOTSTRAP" | head -1 | cut -d= -f2)"
    _lib_schema="$(grep -oE '^_IHDG_EXPECTED_SCHEMA="[0-9]+"' "$GATE" | grep -oE '[0-9]+')"
    if [[ -n "$_emit_schema" && "$_emit_schema" == "$_lib_schema" ]]; then pass; else fail "B12: the emitter's probe_schema=${_emit_schema:-<none>} and the lib's _IHDG_EXPECTED_SCHEMA=${_lib_schema:-<none>} disagree"; fi
  fi
fi

# ══ Row 6/7/7b — RETIRED WITH THE inngest_volume_recut JOB (#8285) ═════════════════
# These rows graded the workflow's use of this lib: that apply-web-platform-infra.yml SOURCED it and
# CALLED the retired entry point under `if !`, that its dispatch-time inputs were bound from
# variables (not literals), that the two probe windows stayed `--since 90m`, and the operator-facing
# recovery prose of the recut dispatch. That job was converted into inngest_backstop_retire, which
# graded the live store through its own gate library and suite (both deleted by #8285 PR B with that
# job) and did not use this lib. The lib's remaining consumer is scripts/cutover-inngest.sh, whose
# wiring is pinned below (the cq-assert-anchor-not-bare-token form: the `source` keyword at the
# start of a line, comments stripped), and the workflow is pinned NOT to re-acquire an unreviewed
# copy of the call.
WF="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"
CUT_SH="${REPO_ROOT}/scripts/cutover-inngest.sh"
if grep -qE '^[[:space:]]*(source|\.)[[:space:]]+tests/scripts/lib/inngest-host-dark-gate\.sh' "$CUT_SH"; then pass; else fail "Row 6a: scripts/cutover-inngest.sh has no live SOURCE statement for inngest-host-dark-gate.sh (its remaining consumer)"; fi
_cut_calls="$(grep -vE '^[[:space:]]*#' "$CUT_SH" | grep -cE 'inngest_execute_registry_gate[[:space:]]+--rows-file' || true)"
if [[ "$_cut_calls" -ge 2 ]]; then pass; else fail "Row 6b: scripts/cutover-inngest.sh does not CALL inngest_execute_registry_gate from both arms (found ${_cut_calls}, want >=2)"; fi
if [ "$(grep -vE '^[[:space:]]*#' "$WF" | grep -cE '^[[:space:]]*(source|\.)[[:space:]]+[^#]*inngest-host-dark-gate\.sh')" -gt 0 ]; then
  fail "Row 6c: the workflow sources this lib again -- the recut dispatch it served was retired in #8285 and its entry point under #8316; re-add its wiring rows if that is intended"
else pass; fi

# ══ Row 9 — NO INVOCATION MAY FLOAT ON THE WALL CLOCK ═══════════════════════════
# E5 bounds the newest row's age against a clock, and every fixture in this file is dated
# 2026-09-03 ~10:00 UTC. So any invocation that does not pin `--now-epoch` passes in the morning
# and fails in the afternoon, with no edit in between — measured twice today, once on H2 and once
# on the mutation harness's MUTATED run, where the drift was worse than a flaky arm: the mutated
# verdict became `stale_row`, which differs from the expected token, so every B10 row reported the
# mutation load-bearing while measuring the clock.
#
# `gate()` pins it for the arms that go through it. This asserts the ones that do NOT: every
# direct `inngest_execute_registry_gate --rows-file` call must either pin the clock or be one of
# the two deliberate real-clock arms in Row 8 (section 6.6), which stamp their fixtures at
# `date -u` precisely to exercise the default branch.
# Scans real CALL SITES: a non-comment line that invokes the gate, joined with the next three
# lines so a backslash-continued invocation is judged whole (8, because `gate()` itself spans 7). An earlier cut of this check globbed
# the file for the call text and matched its own explanatory comment plus the truncated head of
# each continued call — `cq-assert-anchor-not-bare-token` again, in the arm written to prevent a
# different vacuity.
_unpinned=0
while IFS= read -r _n; do
  # Strip comments from the chunk BEFORE classifying. The nine-line window routinely runs into
  # the prose documenting the next arm, and both `--now-epoch` and the Row 8 fixture names appear
  # in that prose — so an unpinned call sitting above an explanation of pinning was read as pinned.
  _chunk="$(sed -n "${_n},$((_n + 8))p" "${BASH_SOURCE[0]}" \
            | grep -vE '^[[:space:]]*#' | sed 's/[[:space:]]#[[:space:]].*$//' | tr '\n' ' ')"
  case "$_chunk" in
    *'--now-epoch'*)                 : ;;
    *erg-now.json*|*erg-old.json*)   : ;;   # Row 8: deliberately the real clock
    *)  _unpinned=$((_unpinned + 1)); printf '    unpinned at line %s: %s\n' "$_n" "${_chunk:0:100}" >&2 ;;
  esac
# `GATE_FN=<name> mutate …` is a SELECTOR assignment, not an invocation — the call it selects goes
# through mutate(), which pins the clock on both runs.
done < <(grep -nE 'inngest_execute_registry_gate ' "${BASH_SOURCE[0]}" \
         | grep -v '^[0-9]*: *#' | grep -v 'grep -n' | grep -vE '^[0-9]*:[^#]*grep' | grep -v 'fail "Row 6b' | grep -v 'GATE_FN=inngest_' | cut -d: -f1)
if [[ "$_unpinned" -eq 0 ]]; then pass; else fail "Row 9: ${_unpinned} direct gate invocation(s) do not pin --now-epoch — they will pass or fail depending on the time of day"; fi

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
  # The control runs the SAME entry point and the SAME argument list as the mutated run below —
  # one list (`_gate_default_args`, then the row's env overrides, then the row's extra args, the
  # parser taking the last assignment), built once, so the two cannot drift apart (the earlier
  # shape built the mutated run's arguments by hand and pinned a different clock — the Row 9 story).
  local second="${SECOND:-$HB}"
  local -a margs=()
  local _mdefaults; _mdefaults="$(_gate_default_args "$rows" "$second")"
  mapfile -t margs <<< "$_mdefaults"
  margs+=(--now-epoch "${NOWV:-$NOW}" "$@")
  local base_rc=0 base_out base want_rc=1
  [[ "$tok" == "dark" ]] && want_rc=0
  base_out="$("${GATE_FN:-inngest_execute_registry_gate}" "${margs[@]}" 2>&1)" || base_rc=$?
  base="$(printf '%s\n' "$base_out" | tail -1)"
  if [[ "$base" != "$tok" || "$base_rc" -ne "$want_rc" ]]; then
    fail "B10[$gn]: the UNMUTATED gate did not return '$tok' rc=$want_rc for this fixture (got '$base' rc=$base_rc); the row does not exercise the check."
    return
  fi
  # THE MUTATED RUN MUST USE THE SAME CLOCK AS THE CONTROL. The control goes through `gate()`,
  # which pins `--now-epoch "$NOW"`; this call did not, so it ran against the REAL clock. With
  # every fixture dated 10:00 UTC that made the mutated run `stale_row` from mid-morning onward —
  # a verdict that differs from the expected token, which is exactly what this row treats as
  # "the mutation changed the verdict". Every B10 row was therefore passing on the clock rather
  # than on the neutered check, and would have kept doing so. `%q` so a value carrying a space or
  # a quote survives the `bash -c` boundary byte-for-byte.
  local q; q="$(printf '%q ' "${margs[@]}")"
  out="$(bash -c "set -uo pipefail; source '$mutated'; ${GATE_FN:-inngest_execute_registry_gate} $q" 2>&1)" || rc=$?
  got="$(printf '%s\n' "$out" | tail -1)"
  # A MUTANT THAT DID NOT RUN IS NOT A KILL. A `source` that fails to parse, a `return` with no
  # token, an unbound-variable abort (rc 127) all "change the verdict" while proving nothing about
  # the neutered line. Require the mutant to have produced a lib token with a lib rc — otherwise the
  # row is INCONCLUSIVE, which is a FAIL: the sed must be rewritten to weaken the check, not break it.
  case " ${_LIB_TOKENS:-} " in
    *" $got "*) : ;;
    *) fail "B10[$gn]: the MUTANT did not produce a lib token (got '${got:0:80}' rc=$rc) — it crashed or returned mute, so the row is inconclusive; rewrite the sed to WEAKEN the check" "$rc" "$out"; return ;;
  esac
  [[ "$rc" -eq 0 || "$rc" -eq 1 ]] || { fail "B10[$gn]: the MUTANT exited rc=$rc (not a lib rc) — inconclusive" "$rc" "$out"; return; }
  # TOKEN *OR* RC. `_ihdg_verdict` is the one place a token becomes an exit code for the gate; a mutation that leaves every token intact and returns 0 for all of them (matrix row 11)
  # changes no `tail -1` and was invisible to a token-only comparison. The kill CLASS is recorded:
  # `open` (the mutant graded `dark` — the check was the last thing between the fixture and a pass)
  # or `diag` (the mutant refused with a different token — the check chose the diagnosis). Rows
  # that claim to prove a fail-OPEN guard go through `mutate_open`, which requires `open`.
  if [[ "$got" != "$tok" || "$rc" -ne "$want_rc" ]]; then
    if [[ "$got" == "dark" && "$rc" -eq 0 ]]; then _kills_open=$((_kills_open + 1)); _last_kill=open; else _kills_diag=$((_kills_diag + 1)); _last_kill=diag; fi
    pass
  else
    _last_kill=none
    fail "B10[$gn]: neutering the check did NOT change the verdict (still '$tok' rc=$rc); the line may be dead code shadowed by another check." "$rc" "$out"
  fi
}
_kills_open=0; _kills_diag=0; _last_kill=none
_LIB_TOKENS="$(grep -v '^[[:space:]]*#' "$GATE" | grep -oE '_ihdg_verdict "[a-z0-9_]+"' | cut -d'"' -f2 | sort -u | tr '\n' ' ')"
# mutate_open — a mutate() row that must kill FAIL-OPEN: the mutant must grade `dark`. A row whose
# mutant lands on a SECOND refusal proves only that the check picks the diagnosis; it does not
# prove the check stands between its fixture and a pass (review found 14 of 50 execute-gate rows
# killing that way, several because `registry_fns` in the fixture let E12 shadow the line under test).
mutate_open() {
  local gn="$1"
  _last_kill=none
  mutate "$@"
  if [[ "$_last_kill" == "diag" ]]; then
    fail "B10[$gn]: the mutant refused with a DIFFERENT token instead of grading dark — the row proves a diagnosis choice, not a fail-open guard; give the fixture a shape no later predicate refuses"
  fi
}

# ══ 6. THE EXECUTE GATE — inngest_execute_registry_gate (#8054) ══════════════════
# `op=execute`'s 2.0 pre-flight required the dedicated host to ANSWER over GQL; P1-5 keeps it dark
# until `op=arm`, which runs AFTER execute — so 2.0 was unrunnable in the very sequence it guards.
# This entry point grades darkness POSITIVELY from the host's own probe row (E1–E12) and requires
# the flip FSM's heartbeat, on the SAME boot, to attest within `--hb-max-age` that the flag is
# outside the arm set (E13). The pass token is `dark`, the literal `expect()` maps to rc 0, so every
# wrapper above is reused unchanged — `GATE_FN` stays set to the one entry point for the section.
#
# Predicate ids are NAMESPACED (`ERG-E1` … `ERG-E14`): the retired gate's bare `[M1]`…`[M7]`,
# `H2`, `H3` ids are gone with it, but `_seen_predicates` is a word list and the namespace keeps a
# future collision from counting a stray case toward this gate's floor.
GATE_FN=inngest_execute_registry_gate

# Two boots, both synthesized. `EBOOT` is the CURRENT boot in every execute fixture; `OBOOT` is the
# previous one (the live window at plan time held both, so "a row from a previous boot" is a
# measured shape, not a hypothetical). The heartbeat join key is the HYPHEN-STRIPPED form.
EBOOT="a1b2c3d4-0000-4000-8000-00000000cafe"; EBID="${EBOOT//-/}"
OBOOT="906c015b-0000-4000-8000-00000000beef"; OBID="${OBOOT//-/}"

# emsg <override>… — the measured pre-arm row (2026-09-11): loopback refused, unit stuck in
# `activating` under the P1-5 refuse loop, flag `aborted`, registry unreadable BECAUSE the loopback
# refused. The store fields are populated because this gate must not read them — a row this gate
# would refuse on `redis_keys` is a row it read a field it has no business grading.
emsg() {
  msg "boot_id=$EBOOT" http_code=000 server_active=activating cutover_flag=aborted \
      registry_fns=__UNREADABLE__ redis_keys=16 redis_key_patterns='inngest:queue:1' "$@"
}
# erows <name> <dt> <message> [host] [host_name] [SYSLOG_IDENTIFIER] — a probe row carrying the
# CURRENT boot's envelope. The emitter defaults to the probe's own tag; #8846's forged rows pass
# `doppler`, the inngest server's event-log identifier on the same host.
erows() {
  mk_rows "$TMP/erg-$1.json" "$(bs_line "$2" "${4:-$HOSTV}" "${5:-$HOSTNAMEV}" "$3" "${6:-inngest-server-probe}" "$EBID")"
}
EROWS="$TMP/erg-rows.json"
mk_rows "$EROWS" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")"
# The heartbeat: one same-boot `aborted` row 60 s before NOW (the FSM emits ~1–2/min on a
# terminal flag — P0-1/P0-2 — so a 15-minute bound holds ~15–30 rows live).
HB="$TMP/erg-hb.json"
mk_rows "$HB" "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"

# ── The wrappers must discriminate for THIS entry point too ──────────────────────
# The wrapper self-tests prove `expect()` can fail; this one proves `gate()` dispatches on
# `GATE_FN` — a binding bug (`gate()` still calling a stale name) would make every execute arm
# below grade the WRONG function, and this is the arm that sees it: a plainly-serving row must
# FAIL a `dark` expectation through the dispatched path.
erows selftest '2026-09-03 10:00:00' "$(emsg http_code=200 server_active=active registry_fns=0)"
_st_p="$passes" _st_f="$fails"
expect "ERG SELF-TEST (expected to fail): a serving host is not dark" dark "$TMP/erg-selftest.json" "$HB" 2>/dev/null
_seen_tokens="${_seen_tokens% dark}"   # a must-FAIL probe asserted nothing: roll its token back out of the coverage set
if [[ "$fails" -eq $((_st_f + 1)) && "$passes" -eq "$_st_p" ]]; then
  passes="$_st_p"; fails="$_st_f"; pass
else
  passes="$_st_p"; fails="$_st_f"
  fail "INSTRUMENT: expect() did not fail on a must-fail execute-gate arm — gate() is not dispatching on GATE_FN"
fi
# A duplicated predicate id must not widen the distinct-predicate set — the floor counts SET
# members, and a battery that re-used one id thirteen times would otherwise clear it.
_d0=0; for _g in ${_seen_predicates:-}; do _d0=$((_d0 + 1)); done
_w_p="$passes" _w_f="$fails" _pc0="$predicate_cases"
predicate ERG-DUPTEST "dup-id probe 1 (expected to fail)" dark "$TMP/erg-selftest.json" "$HB" 2>/dev/null
_seen_tokens="${_seen_tokens% dark}"
predicate ERG-DUPTEST "dup-id probe 2 (expected to fail)" dark "$TMP/erg-selftest.json" "$HB" 2>/dev/null
_seen_tokens="${_seen_tokens% dark}"
_d1=0; for _g in ${_seen_predicates:-}; do _d1=$((_d1 + 1)); done
passes="$_w_p"; fails="$_w_f"; predicate_cases="$_pc0"
_seen_predicates="${_seen_predicates/ ERG-DUPTEST/}"
if [[ "$_d1" -eq $((_d0 + 1)) ]]; then pass; else fail "INSTRUMENT: predicate() counted a duplicated id twice (distinct ${_d0} -> ${_d1}); the drop-one floor is inflatable"; fi

# `expect()` and the duplicate-id probe above are proven. `predicate()` has its own failure mode: it
# increments `predicate_cases` and appends to `_seen_predicates` INSIDE ITSELF, so neutering its
# body to a bare `pass` keeps the drop-one floor printing "N distinct predicates covered" while every
# one of those assertions is decorative. A floor cannot see a wrapper that keeps counting; only
# driving the wrapper in the must-FAIL direction can. (Formerly section 0c; it moved here when the
# entry point it used to be driven through was retired, so it needs the execute fixtures above.)
_w_p="$passes" _w_f="$fails"
predicate SELFTEST "wrapper self-test (expected to fail)" dark "$TMP/erg-selftest.json" "$HB" 2>/dev/null
_w_ok=0; [[ "$fails" -eq $((_w_f + 1)) ]] && _w_ok=1
passes="$_w_p"; fails="$_w_f"
_seen_predicates="${_seen_predicates/ SELFTEST/}"; predicate_cases=$((predicate_cases - 1))
_seen_tokens="${_seen_tokens% dark}"
if [[ "$_w_ok" -eq 1 ]]; then pass; else fail "INSTRUMENT: predicate() did not fail on a must-fail arm — the entire drop-one battery is decorative"; fi

# ── BASELINE (must-PASS) ─────────────────────────────────────────────────────────
expect "[ERG] BASELINE: measured pre-arm row + fresh same-boot heartbeat => dark" dark "$EROWS" "$HB"

# ── The lib has never been called under errexit; the production caller runs `set -euo pipefail`
# An unguarded failing command inside the gate body dies BEFORE the verdict and leaves stdout
# EMPTY — fail-closed and mute, with no `::error::` and no remediation. Both directions, direct.
_rc=0; _out="$(bash -c "set -euo pipefail; source '$GATE'; inngest_execute_registry_gate --rows-file '$TMP/erg-selftest.json' --query-rc 0 --hb-file '$HB' --hb-rc 0 --now-epoch '$NOW'" 2>&1)" || _rc=$?
if [[ "$(printf '%s\n' "$_out" | tail -1)" == "host_serving" && "$_rc" -eq 1 ]]; then pass; else fail "[ERG-errexit] a refusal under 'set -euo pipefail' must still print its token (want host_serving rc 1)" "$_rc" "$_out"; fi
_rc=0; _out="$(bash -c "set -euo pipefail; source '$GATE'; inngest_execute_registry_gate --rows-file '$EROWS' --query-rc 0 --hb-file '$HB' --hb-rc 0 --now-epoch '$NOW'" 2>&1)" || _rc=$?
if [[ "$(printf '%s\n' "$_out" | tail -1)" == "dark" && "$_rc" -eq 0 ]]; then pass; else fail "[ERG-errexit] the pass path under 'set -euo pipefail' must print dark rc 0" "$_rc" "$_out"; fi
# …and the gate's stdout is EXACTLY one line. Every helper it calls is `$(…)`-captured; a helper
# whose stdout leaked would land a full probe row in the caller's `::error::` annotation.
_out="$(gate "$EROWS" "$HB" 2>/dev/null)"
if [[ "$(printf '%s\n' "$_out" | wc -l)" -eq 1 ]]; then pass; else fail "[ERG-stdout] the gate printed $(printf '%s\n' "$_out" | wc -l) lines; the verdict must be the whole of stdout" 0 "$_out"; fi

# ══ 6.1 THE DROP-ONE BATTERY — one case per PREDICATE, E1..E13 ═══════════════════

# E1 — the probe read did not answer. Evaluated FIRST: a 503 (rc 22 under --fail-with-body) is a
# broken READ, and refusing it as `silent` would tell the operator the host emits nothing.
predicate ERG-E1 "probe query rc 22 => unreadable (not silent)" unreadable "$EROWS" "$HB" --query-rc 22
predicate ERG-E1 "probe query rc non-numeric => unreadable" unreadable "$EROWS" "$HB" --query-rc x
# One case per remediation branch the CALLER partitions on (3 creds / 1 doppler / 2 reader / 99
# unclassified): the gate's token is the same for all — the rc travels beside it, not inside it.
for _rc in 3 1 2 99; do
  predicate ERG-E1 "probe query rc $_rc => unreadable (the caller branches on the rc, the gate does not)" unreadable "$EROWS" "$HB" --query-rc "$_rc"
done
predicate ERG-E1 "rows file absent => unreadable" unreadable "$TMP/does-not-exist.json" "$HB"

# E2 — bytes arrived, nothing decoded. Not silence: a gzipped or truncated response is a decode
# failure, and `silent`'s remedy (replace the host) is the wrong one for it.
printf 'not json{{{\n\x1f\x8b\x08garbage\n' > "$TMP/erg-garbage.json"
predicate ERG-E2 "bytes present but NOTHING decodes => unreadable (not silent)" unreadable "$TMP/erg-garbage.json" "$HB"

# E3 — zero rows, or rows only from the wrong host. Population before silence.
: > "$TMP/erg-empty.json"
predicate ERG-E3 "zero probe rows => silent" silent "$TMP/erg-empty.json" "$HB"
# THE REAL READER'S EMPTY RESULT IS ONE BLANK LINE, NOT ZERO BYTES. `_bs_query_rows` in
# scripts/cutover-inngest.sh renders with `printf '%s\n' "$rows"`, so "no rows" reaches the gate
# as a 1-byte file. Four review agents converged on the same defect: counted as a physical line
# it graded `unreadable` ("file an issue against the emitter") where the state is `silent` ("read
# the health run, replace the host"). Both fixtures below are the byte shape production emits.
printf '\n' > "$TMP/erg-blankline.json"
predicate ERG-E3 "the reader's EMPTY result (one blank line, the production byte shape) => silent, not unreadable" silent "$TMP/erg-blankline.json" "$HB"
predicate ERG-E13 "the reader's EMPTY heartbeat result (one blank line) => fsm_silent, not fsm_unreadable" fsm_silent "$EROWS" "$TMP/erg-blankline.json"
erows web '2026-09-03 10:00:00' "$(emsg host_role=web)" 'soleur-web-platform' 'soleur-web-prd'
predicate ERG-E3 "rows only from the WEB host => wrong_host (not silent)" wrong_host "$TMP/erg-web.json" "$HB"

# E4 — two rows at the newest `dt` that DISAGREE (matrix row 12). Tied-and-identical is fine.
mk_rows "$TMP/erg-tie.json" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg http_code=200 server_active=active registry_fns=9)" inngest-server-probe "$EBID")"
predicate ERG-E4 "[row 12] tied newest rows that disagree => unreadable" unreadable "$TMP/erg-tie.json" "$HB"
mk_rows "$TMP/erg-tie-same.json" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")"
expect "[ERG-E4] tied newest rows that AGREE (a duplicated delivery) => dark" dark "$TMP/erg-tie-same.json" "$HB"

# E5 — the newest row is OLD, or from the FUTURE (historically G3 of the retired recut gate).
#   row dt 10:00:00 = 1788429600; NOW + 3h = 1788440400; a future row: NOW pinned BEFORE the row.
mk_rows "$TMP/erg-hb-late.json" "$(hb_line '2026-09-03 12:59:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
predicate ERG-E5 "newest probe row 3h old => stale_row" stale_row "$EROWS" "$TMP/erg-hb-late.json" --now-epoch 1788440400
predicate ERG-E5 "newest probe row from the FUTURE => stale_row" stale_row "$EROWS" "$HB" --now-epoch 1788429000
expect "[ERG-E5] a 3h-old row is inside an explicitly widened bound => dark (bound is the gate's operand)" dark "$EROWS" "$TMP/erg-hb-late.json" --now-epoch 1788440400 --max-row-age 20000

# E6 — probe_schema is EXACTLY 8. `>=` would accept a future schema whose fields this gate has
# never seen (matrix row 6 mutates this to `-ge`).
erows e6 '2026-09-03 10:00:00' "$(emsg probe_schema=7)"
predicate ERG-E6 "probe_schema=7 => stale_schema" stale_schema "$TMP/erg-e6.json" "$HB"
erows e6b '2026-09-03 10:00:00' "$(emsg probe_schema=9)"
predicate ERG-E6 "probe_schema=9 (FUTURE) => stale_schema, never >=" stale_schema "$TMP/erg-e6b.json" "$HB"
erows e6c '2026-09-03 10:00:00' "$(emsg -probe_schema)"
predicate ERG-E6 "no probe_schema at all => stale_schema" stale_schema "$TMP/erg-e6c.json" "$HB"

# E7 — boot_id is a hyphenated UUID and strips to 32 hex. It is the JOIN KEY for E13, so a value
# that is present-but-degenerate (`unknown`, the emitter's read-failed sentinel; an all-hyphen
# string that strips to ""; the un-hyphenated form) must refuse HERE, before any jq sees `$bid`.
erows e7a '2026-09-03 10:00:00' "$(emsg -boot_id)"
predicate ERG-E7 "boot_id ABSENT => unreadable" unreadable "$TMP/erg-e7a.json" "$HB"
erows e7b '2026-09-03 10:00:00' "$(emsg boot_id=unknown)"
predicate ERG-E7 "boot_id=unknown (the emitter's read-failed sentinel) => unreadable" unreadable "$TMP/erg-e7b.json" "$HB"
erows e7c '2026-09-03 10:00:00' "$(emsg boot_id=------------------------------------)"
predicate ERG-E7 "[row 21] boot_id that strips to EMPTY => unreadable (never an empty join key)" unreadable "$TMP/erg-e7c.json" "$HB"
erows e7d '2026-09-03 10:00:00' "$(emsg "boot_id=$EBID")"
predicate ERG-E7 "boot_id already un-hyphenated (not the /proc shape) => unreadable" unreadable "$TMP/erg-e7d.json" "$HB"
erows e7e '2026-09-03 10:00:00' "$(emsg boot_id=)"
predicate ERG-E7 "boot_id= (present, empty) => unreadable" unreadable "$TMP/erg-e7e.json" "$HB"

# E8 — the row says it is the dedicated host (historically G7 of the retired recut gate).
erows e8 '2026-09-03 10:00:00' "$(emsg host_role=web registry_fns=n/a)"
predicate ERG-E8 "host_role=web => wrong_host" wrong_host "$TMP/erg-e8.json" "$HB"
erows e8b '2026-09-03 10:00:00' "$(emsg -host_role)"
predicate ERG-E8 "host_role ABSENT => wrong_host" wrong_host "$TMP/erg-e8b.json" "$HB"

# E9 — the loopback did NOT answer 200. A 200 here with the webhook refusing is a serving host
# behind a broken webhook path — refuse and say which one to check first.
erows e9 '2026-09-03 10:00:00' "$(emsg http_code=200 registry_fns=0)"
predicate ERG-E9 "http_code=200 => host_serving" host_serving "$TMP/erg-e9.json" "$HB"
erows e9b '2026-09-03 10:00:00' "$(emsg http_code=abc)"
predicate ERG-E9 "http_code non-numeric => unreadable" unreadable "$TMP/erg-e9b.json" "$HB"
erows e9c '2026-09-03 10:00:00' "$(emsg -http_code)"
predicate ERG-E9 "http_code ABSENT => unreadable (absence is not 'non-200')" unreadable "$TMP/erg-e9c.json" "$HB"

# E10 — systemd does not say `active`. NOT `== inactive`: the P1-5 refuse loop leaves the unit in
# `activating` (measured), and `failed` / `inactive` are equally dark. `unknown` is the emitter's
# read-failed sentinel and is a readability failure, not a claim about the unit.
erows e10 '2026-09-03 10:00:00' "$(emsg server_active=active)"
predicate ERG-E10 "server_active=active => host_serving" host_serving "$TMP/erg-e10.json" "$HB"
erows e10b '2026-09-03 10:00:00' "$(emsg server_active=unknown)"
predicate ERG-E10 "server_active=unknown => unreadable" unreadable "$TMP/erg-e10b.json" "$HB"
erows e10c '2026-09-03 10:00:00' "$(emsg server_active=)"
predicate ERG-E10 "server_active= (present, empty) => unreadable" unreadable "$TMP/erg-e10c.json" "$HB"
erows e10d '2026-09-03 10:00:00' "$(emsg -server_active)"
predicate ERG-E10 "server_active ABSENT => unreadable" unreadable "$TMP/erg-e10d.json" "$HB"

# E11 — the probe row's cutover_flag is a POSITIVE allowlist {aborted, rolled-back}. The arm set
# {armed, flipping, flushed, done} names its own remedy; EVERYTHING ELSE — `unknown`, `rollback`
# (in flight), empty, absent — is `flag_unreadable`. The G20 lesson: the empty string was once an
# accepting value in this lib, and matrix row 3 mutates this to the negative form to prove it is not.
for _f in armed flipping flushed "done"; do
  erows "e11-$_f" '2026-09-03 10:00:00' "$(emsg cutover_flag=$_f)"
  predicate ERG-E11 "cutover_flag=$_f => flag_armed" flag_armed "$TMP/erg-e11-$_f.json" "$HB"
done
for _f in unknown rollback bogus; do
  erows "e11-$_f" '2026-09-03 10:00:00' "$(emsg cutover_flag=$_f)"
  predicate ERG-E11 "cutover_flag=$_f => flag_unreadable (positive allowlist)" flag_unreadable "$TMP/erg-e11-$_f.json" "$HB"
done
erows e11-empty '2026-09-03 10:00:00' "$(emsg cutover_flag=)"
predicate ERG-E11 "cutover_flag= (present, empty) => flag_unreadable" flag_unreadable "$TMP/erg-e11-empty.json" "$HB"
erows e11-absent '2026-09-03 10:00:00' "$(emsg -cutover_flag)"
predicate ERG-E11 "cutover_flag ABSENT => flag_unreadable" flag_unreadable "$TMP/erg-e11-absent.json" "$HB"

# E12 — coherence: a loopback that refused cannot have yielded a registry count. A numeric
# `registry_fns` beside `http_code=000` means the emitter contradicts itself (#8015's field).
erows e12 '2026-09-03 10:00:00' "$(emsg registry_fns=3)"
predicate ERG-E12 "registry_fns=3 beside http_code=000 => unreadable (incoherent row)" unreadable "$TMP/erg-e12.json" "$HB"
erows e12b '2026-09-03 10:00:00' "$(emsg registry_fns=0)"
predicate ERG-E12 "registry_fns=0 beside http_code=000 => unreadable (0 is a measurement, not absence)" unreadable "$TMP/erg-e12b.json" "$HB"
erows e12c '2026-09-03 10:00:00' "$(emsg -registry_fns)"
predicate ERG-E12 "registry_fns ABSENT => unreadable" unreadable "$TMP/erg-e12c.json" "$HB"

# E13 — the heartbeat bridge. The probe row is hourly; the FSM heartbeat is ~1–2/min and carries
# the journald `_BOOT_ID`. Freshness comes from the heartbeat, identity from the boot join, and
# the flag from the NEWEST same-boot object row's `.message.flag` — graded in bash, never
# filtered in jq (matrix row 22: a value filter would skip a fresh `armed` for a stale `aborted`).
predicate ERG-E13 "heartbeat query rc 22 => fsm_unreadable" fsm_unreadable "$EROWS" "$HB" --hb-rc 22
predicate ERG-E13 "heartbeat query rc non-numeric => fsm_unreadable" fsm_unreadable "$EROWS" "$HB" --hb-rc x
predicate ERG-E13 "heartbeat file absent => fsm_unreadable" fsm_unreadable "$EROWS" "$TMP/does-not-exist.json"
predicate ERG-E13 "--hb-max-age non-numeric => fsm_unreadable (never coerced)" fsm_unreadable "$EROWS" "$HB" --hb-max-age 15m
predicate ERG-E13 "--hb-max-age empty => fsm_unreadable" fsm_unreadable "$EROWS" "$HB" --hb-max-age ""
predicate ERG-E13 "heartbeat bytes present but NOTHING decodes => fsm_unreadable" fsm_unreadable "$EROWS" "$TMP/erg-garbage.json"
predicate ERG-E13 "zero heartbeat rows => fsm_silent" fsm_silent "$EROWS" "$TMP/erg-empty.json"
mk_rows "$TMP/erg-hb-oldboot.json" "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$OBID" aborted)"
predicate ERG-E13 "[row 14] fresh heartbeat from a PREVIOUS boot only => fsm_silent" fsm_silent "$EROWS" "$TMP/erg-hb-oldboot.json"
mk_rows "$TMP/erg-hb-2h.json" "$(hb_line '2026-09-03 08:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
predicate ERG-E13 "[row 15] same-boot heartbeat 2h old => fsm_silent" fsm_silent "$EROWS" "$TMP/erg-hb-2h.json"
mk_rows "$TMP/erg-hb-future.json" "$(hb_line '2026-09-03 10:11:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
predicate ERG-E13 "same-boot heartbeat from the FUTURE => fsm_silent" fsm_silent "$EROWS" "$TMP/erg-hb-future.json"
mk_rows "$TMP/erg-hb-webhost.json" "$(hb_line '2026-09-03 10:09:00' 'soleur-web-platform' 'soleur-web-prd' "$EBID" aborted)"
predicate ERG-E13 "same-boot heartbeat from the WEB host => fsm_silent (identity conjunction)" fsm_silent "$EROWS" "$TMP/erg-hb-webhost.json"
mk_rows "$TMP/erg-hb-ident.json" "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted noop-aborted inngest-server-flip-guard)"
predicate ERG-E13 "same-boot row under another SYSLOG_IDENTIFIER => fsm_silent" fsm_silent "$EROWS" "$TMP/erg-hb-ident.json"
# `.message` a STRING on EVERY same-boot row: the FSM logs a JSON string, Vector re-encodes it as a
# string, and it is Better Stack's ingest-side parse that yields the object (measured 2026-09-11).
# Rows present + none parsed is a READ-PATH change, so it is `fsm_unreadable` — not `fsm_silent`,
# whose remedy (replace the host for a dead timer) would be wrong for a demonstrably live timer.
mk_rows "$TMP/erg-hb-string.json" "$(bs_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" '{"flag":"aborted","reason":"noop-aborted"}' inngest-cutover-flip "$EBID")"
predicate ERG-E13 "every same-boot heartbeat .message is a STRING (warehouse stopped parsing) => fsm_unreadable, not silent" fsm_unreadable "$EROWS" "$TMP/erg-hb-string.json"
# No `_BOOT_ID` on the heartbeat row at all (row 21's other half): never equal to a real key.
mk_rows "$TMP/erg-hb-nobid.json" "$(jq -cn --arg dt '2026-09-03 10:09:00' --arg h "$HOSTV" --arg hn "$HOSTNAMEV" \
  '{dt:$dt, raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:"inngest-cutover-flip", message:{flag:"aborted",reason:"noop-aborted"}} | tojson)}')"
predicate ERG-E13 "[row 21] heartbeat rows with NO _BOOT_ID => fsm_silent" fsm_silent "$EROWS" "$TMP/erg-hb-nobid.json"
mk_rows "$TMP/erg-hb-armed.json" "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" armed noop-armed)"
predicate ERG-E13 "fresh same-boot heartbeat flag=armed => flag_armed" flag_armed "$EROWS" "$TMP/erg-hb-armed.json"
mk_rows "$TMP/erg-hb-unknown.json" "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" unknown)"
predicate ERG-E13 "[row 16] fresh same-boot heartbeat flag=unknown => flag_unreadable" flag_unreadable "$EROWS" "$TMP/erg-hb-unknown.json"
mk_rows "$TMP/erg-hb-noflag.json" "$(jq -cn --arg dt '2026-09-03 10:09:00' --arg h "$HOSTV" --arg hn "$HOSTNAMEV" --arg b "$EBID" \
  '{dt:$dt, raw: ({host:$h, host_name:$hn, SYSLOG_IDENTIFIER:"inngest-cutover-flip", _BOOT_ID:$b, message:{reason:"noop-aborted"}} | tojson)}')"
predicate ERG-E13 "fresh same-boot heartbeat with NO .flag => flag_unreadable" flag_unreadable "$EROWS" "$TMP/erg-hb-noflag.json"
# Row 22 — the flag is graded on the NEWEST same-boot row, in bash, after selection. A jq value
# filter (`select(.message.flag == "aborted")`) would skip the fresh `armed` and pass on the stale
# `aborted`. Order in the file is deliberately NOT chronological.
mk_rows "$TMP/erg-hb-newarmed.json" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" armed noop-armed)" \
  "$(hb_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
predicate ERG-E13 "[row 22] NEWEST same-boot heartbeat armed (60s) beside an older aborted (600s) => flag_armed" flag_armed "$EROWS" "$TMP/erg-hb-newarmed.json"
# The NEWEST row under the tag is a STRING message (the FSM also logs plain lines, e.g. the seam
# refusal) beside an OLDER object row: the type filter must drop the string and grade the object,
# never refuse on the string and never let it shadow the fresh attestation.
mk_rows "$TMP/erg-hb-strnewest.json" \
  "$(hb_line '2026-09-03 10:08:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)" \
  "$(bs_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" 'SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED reason=noop' inngest-cutover-flip "$EBID")"
expect "[ERG-E13] a newer STRING row under the tag beside an older object row => dark (type filter, not value filter)" dark "$EROWS" "$TMP/erg-hb-strnewest.json"
# THE STALE-`armed` PROBE ROW. E11 grades the hourly probe row's flag BEFORE E13 grades the fresh
# heartbeat, so a probe row sampled mid-arm (`cutover_flag=armed`, 50 min old, loopback still
# refused) beside a fresh same-boot `aborted` heartbeat refuses `flag_armed` — a CONSERVATIVE
# refusal (the arm has in fact ended) that clears on the next hourly probe row. Pinned so the
# behaviour is visible and the caller's remedy can name the wait; the Guard Contract keeps E11 as a
# positive allowlist over the row that E9/E10 grade, and this is the price of grading it.
mk_rows "$TMP/erg-stale-armed.json" "$(bs_line '2026-09-03 09:20:00' "$HOSTV" "$HOSTNAMEV" "$(emsg cutover_flag=armed)" inngest-server-probe "$EBID")"
expect "[ERG-E11] stale (50 min) probe row cutover_flag=armed beside a fresh same-boot aborted heartbeat => flag_armed (conservative; clears on the next probe row)" flag_armed "$TMP/erg-stale-armed.json" "$HB"
# A same-boot row NEWER than the newest parsed heartbeat whose .message is a STRING beginning with
# `{` is a heartbeat the warehouse did not parse — grading the older parsed one would skip the
# freshest attestation. `fsm_unreadable`, never `dark`.
mk_rows "$TMP/erg-hb-newer-unparsed.json" \
  "$(hb_line '2026-09-03 10:08:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)" \
  "$(bs_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" '{"flag":"armed","reason":"noop-armed"}' inngest-cutover-flip "$EBID")"
predicate ERG-E13 "a NEWER same-boot JSON-shaped STRING row beside an older parsed row => fsm_unreadable (never grade past an unparsed heartbeat)" fsm_unreadable "$EROWS" "$TMP/erg-hb-newer-unparsed.json"

# E14 — THE PROBE ROW MUST POSTDATE THE NEWEST FSM TRANSITION. An arm that started the server and
# then aborted leaves a transition row (reason `verify-health`, not `noop-*`) AFTER the hourly probe
# row that said the port was closed; that row's darkness describes a state that no longer exists.
# The FSM's own text names the case: "a prod scheduler is STILL RUNNING on this host under a
# terminal flag". Refuse `stale_row` until a probe row from after the transition lands.
mk_rows "$TMP/erg-hb-transition-after.json" \
  "$(hb_line '2026-09-03 10:02:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted verify-health)" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
predicate ERG-E14 "an FSM transition (verify-health) 2 min AFTER the probe row => stale_row (the row predates the state change)" stale_row "$EROWS" "$TMP/erg-hb-transition-after.json"
mk_rows "$TMP/erg-hb-transition-before.json" \
  "$(hb_line '2026-09-03 09:50:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted verify-health)" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
expect "[ERG-E14] an FSM transition 10 min BEFORE the probe row => dark (the row postdates the state change)" dark "$EROWS" "$TMP/erg-hb-transition-before.json"
mk_rows "$TMP/erg-hb-transition-foreign.json" \
  "$(hb_line '2026-09-03 10:02:00' "$HOSTV" "$HOSTNAMEV" "$OBID" aborted verify-health)" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
expect "[ERG-E14] a transition on a FOREIGN boot after the probe row => dark (only same-boot transitions count)" dark "$EROWS" "$TMP/erg-hb-transition-foreign.json"
mk_rows "$TMP/erg-hb-transition-equal.json" \
  "$(hb_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted verify-health)" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
expect "[ERG-E14] a transition at EXACTLY the probe row's dt => dark (-le, the row is not older than the transition)" dark "$EROWS" "$TMP/erg-hb-transition-equal.json"
# Two heartbeat rows at the same newest dt that DISAGREE — a tie is not a winner here either.
mk_rows "$TMP/erg-hb-tie.json" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" armed noop-armed)" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
predicate ERG-E13 "tied newest heartbeat rows that disagree => fsm_unreadable" fsm_unreadable "$EROWS" "$TMP/erg-hb-tie.json"

# ══ 6.2 H-ROWS — the must-PASS shapes a refuse-everything gate cannot tell apart ═══
# H5 — non-canonical on FIVE axes: `failed` not `activating`; `rolled-back` not `aborted`; an
# image_ref the fixture has never used; a trailing field the gate never reads; heartbeat
# `rolled-back`/`noop-rolled-back`. The contract permits every one of these.
erows h5 '2026-09-03 10:07:00' "$(emsg server_active=failed cutover_flag=rolled-back image_ref=ghcr.io/other@sha256:fff) zz_unknown_trailing=1"
mk_rows "$TMP/erg-hb-h5.json" "$(hb_line '2026-09-03 10:09:30' "$HOSTV" "$HOSTNAMEV" "$EBID" rolled-back noop-rolled-back)"
expect "[ERG-H5] non-canonical dark row (failed/rolled-back/foreign image/extra field) + rolled-back heartbeat => dark" dark "$TMP/erg-h5.json" "$TMP/erg-hb-h5.json"
# H5b — history + mismatch + the stopped state. The heartbeat file holds an older same-boot `armed`
# IDLE row (reason `noop-armed` — an idle heartbeat, not a transition; the realistic post-abort trace
# carries a `verify-*` TRANSITION row instead, which E14 refuses until a fresher probe row lands —
# see the [ERG-E14] cases), then `aborted`, AND a foreign-boot `armed`; the probe row says
# `aborted` while the newest heartbeat says `rolled-back`; and `server_active=inactive` is the
# 5.4-day post-`stop_server` state. Pins that only the NEWEST same-boot heartbeat is graded and
# that the bridge is freshness, not corroboration of the probe's flag literal.
erows h5b '2026-09-03 10:00:00' "$(emsg server_active=inactive cutover_flag=aborted)"
mk_rows "$TMP/erg-hb-h5b.json" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" rolled-back noop-rolled-back)" \
  "$(hb_line '2026-09-03 10:02:00' "$HOSTV" "$HOSTNAMEV" "$EBID" armed noop-armed)" \
  "$(hb_line '2026-09-03 10:08:00' "$HOSTV" "$HOSTNAMEV" "$OBID" armed noop-armed)"
expect "[ERG-H5b] older same-boot armed + foreign-boot armed + newest same-boot rolled-back, probe says aborted, unit inactive => dark" dark "$TMP/erg-h5b.json" "$TMP/erg-hb-h5b.json"
# H5c — boundary EQUALITY on both ages: row_age == max_row_age and hb_age == hb_max_age.
#   NOW=1788430200 (10:10:00). Probe at 09:40:00 => 1800 s; heartbeat at 10:05:00 => 300 s.
erows h5c '2026-09-03 09:40:00' "$(emsg)"
mk_rows "$TMP/erg-hb-h5c.json" "$(hb_line '2026-09-03 10:05:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
expect "[ERG-H5c] row_age == max_row_age AND hb_age == hb_max_age => dark (-le, not -lt)" dark "$TMP/erg-h5c.json" "$TMP/erg-hb-h5c.json" --max-row-age 1800 --hb-max-age 300
expect "[ERG-H5c] one second past either bound refuses (row)" stale_row "$TMP/erg-h5c.json" "$TMP/erg-hb-h5c.json" --max-row-age 1799 --hb-max-age 300
expect "[ERG-H5c] one second past either bound refuses (heartbeat)" fsm_silent "$TMP/erg-h5c.json" "$TMP/erg-hb-h5c.json" --max-row-age 1800 --hb-max-age 299
# The measured live shape, verbatim in structure: probe rows from BOTH boots in the window (the
# previous boot's row is older), heartbeat rows ~1/min on the current boot.
mk_rows "$TMP/erg-h-live.json" \
  "$(bs_line '2026-09-03 07:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg "boot_id=$OBOOT" server_active=inactive)" inngest-server-probe "$OBID")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")"
mk_rows "$TMP/erg-hb-live.json" \
  "$(hb_line '2026-09-03 10:07:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)" \
  "$(hb_line '2026-09-03 10:08:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)" \
  "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
expect "[ERG-H-live] two boots in the probe window, three same-boot heartbeats => dark" dark "$TMP/erg-h-live.json" "$TMP/erg-hb-live.json"
# #8846 — the FORGED doppler row against the execute gate: the canonical pair ($EROWS + $HB), then a
# serving row whose message BEGINS with the marker but whose emitter is `doppler`, dated STRICTLY
# between the real row (10:00) and NOW (10:10). Not 10:00 itself: a tie on the newest `dt` trips
# `_ihdg_tied_newest` and refuses `unreadable`, which would be red for the wrong reason.
erows forged '2026-09-03 10:05:00' "$(emsg http_code=200 server_active=active registry_fns=9)" "$HOSTV" "$HOSTNAMEV" doppler
mk_rows "$TMP/erg-forged-pair.json" "$(cat "$EROWS")" "$(cat "$TMP/erg-forged.json")"
expect "[#8846-b] execute gate: a FORGED doppler serving row, newest, beside the real pre-arm row => dark (not a probe row)" \
  dark "$TMP/erg-forged-pair.json" "$HB"
# A malformed line must not swallow the valid rows after it, on EITHER stream.
mk_rows "$TMP/erg-hb-torn.json" 'not json{{{' "$(hb_line '2026-09-03 10:09:00' "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
expect "[ERG] a malformed heartbeat line does not swallow the valid row after it => dark" dark "$EROWS" "$TMP/erg-hb-torn.json"

# ── The emit-file side channel: validated values only, written only after their predicate ─────
_emit="$TMP/erg-emit.txt"
expect "[ERG-emit] --emit-file on the pass path => dark" dark "$EROWS" "$HB" --emit-file "$_emit"
if grep -qx "flag=aborted" "$_emit" && grep -qx "boot_id=$EBOOT" "$_emit" && grep -qx "row_age=600" "$_emit" && grep -qx "hb_age=60" "$_emit" && grep -qx "hb_flag=aborted" "$_emit"; then pass; else fail "[ERG-emit] the emit file must carry flag=/boot_id=/row_age=/hb_age=/hb_flag= for the pass path" 0 "$(cat "$_emit" 2>/dev/null)"; fi
expect "[ERG-emit] flag_unreadable writes the literal __UNREADABLE__, never the raw value" flag_unreadable "$TMP/erg-e11-bogus.json" "$HB" --emit-file "$_emit"
if grep -qx "flag=__UNREADABLE__" "$_emit" && ! grep -q "bogus" "$_emit"; then pass; else fail "[ERG-emit] a refused flag value must not reach the emit file" 0 "$(cat "$_emit" 2>/dev/null)"; fi
expect "[ERG-emit] a RELATIVE emit-file path refuses (P1b relative-operand rule)" unreadable "$EROWS" "$HB" --emit-file "erg-emit.txt"
[[ ! -e "erg-emit.txt" ]] && pass || { fail "[ERG-emit] the gate truncated a CWD-relative file"; rm -f erg-emit.txt; }

# ── Operands: the gate's own inputs degenerate ───────────────────────────────────
expect "[ERG-operand] an EMPTY expected-schema must refuse" stale_schema "$EROWS" "$HB" --expected-schema ""
expect "[ERG-operand] an EMPTY host identity must refuse" wrong_host "$EROWS" "$HB" --host ""
expect "[ERG-operand] an EMPTY host_name identity must refuse" wrong_host "$EROWS" "$HB" --host-name ""
expect "[ERG-operand] an unknown flag must refuse, never fall through" unreadable "$EROWS" "$HB" --not-a-real-flag 1
expect "[ERG-operand] a trailing flag with no value must refuse, not hang" unreadable "$EROWS" "$HB" --hb-max-age
expect "[ERG-operand] a non-numeric --max-row-age must refuse" unreadable "$EROWS" "$HB" --max-row-age 90m
expect "[ERG-operand] a non-numeric --now-epoch must refuse" unreadable "$EROWS" "$HB" --now-epoch now

# ── Row 13 / H2 — an always-dark execute gate is CAUGHT by the arms above ─────────
_always_dark_erg="$TMP/always-dark-erg.sh"
sed '/^inngest_execute_registry_gate() {$/,/^}$/ s|^  local rows_file="" query_rc="" hb_file="".*|  _ihdg_verdict "dark"; return $?|' "$GATE" > "$_always_dark_erg"
if cmp -s "$_always_dark_erg" "$GATE"; then
  fail "[ERG-H2] the always-dark mutation matched NOTHING; the gate's first line drifted"
else
  _rc=0; _out="$(bash -c "set -uo pipefail; source '$_always_dark_erg'; inngest_execute_registry_gate --rows-file '$TMP/erg-e9.json' --query-rc 0 --hb-file '$HB' --hb-rc 0 --now-epoch '$NOW'" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 0 && "$(printf '%s\n' "$_out" | tail -1)" == "dark" ]]; then
    pass   # detectable: the [ERG-E9] arm above asserts host_serving and would redden
  else
    fail "[ERG-H2] the always-dark copy did not produce a false 'dark'; the arms cannot be shown load-bearing" "$_rc" "$_out"
  fi
fi

# ══ 6.3 HELPER-LEVEL CONTRACTS — independent of the gate's own rows ═══════════════════
_rc=0; _ihdg_field "a=1 b=2" c >/dev/null || _rc=$?;            [[ "$_rc" -eq 1 ]] && pass || fail "[helper] _ihdg_field on an ABSENT field must rc 1"
_rc=0; _ihdg_field "a=1 a=2" a >/dev/null || _rc=$?;            [[ "$_rc" -eq 1 ]] && pass || fail "[helper] _ihdg_field on a DUPLICATED field must rc 1"
_rc=0; _ihdg_field $'a=1\nb=2' a >/dev/null || _rc=$?;          [[ "$_rc" -eq 1 ]] && pass || fail "[helper] _ihdg_field on a message carrying a NEWLINE must rc 1"
[[ "$(_ihdg_tied_newest "$TMP/erg-tie-same.json" "$HOSTV" "$HOSTNAMEV")" == "1" ]] && pass || fail "[helper] _ihdg_tied_newest must echo 1 on an identical duplicate"
[[ "$(_ihdg_tied_newest "$TMP/erg-tie.json" "$HOSTV" "$HOSTNAMEV")" == "0" ]] && pass || fail "[helper] _ihdg_tied_newest must echo 0 on a disagreement"
[[ "$(_ihdg_epoch_from_dt '2026-09-03 10:00:00')" == "1788429600" ]] && pass || fail "[helper] _ihdg_epoch_from_dt must render the E5 dt shape as UTC epoch"
[[ "$(_ihdg_epoch_from_dt '2026-09-03 10:00:00.123456')" == "1788429600" ]] && pass || fail "[helper] _ihdg_epoch_from_dt must accept the fractional-second shape"
_rc=0; _ihdg_epoch_from_dt 'yesterday' >/dev/null || _rc=$?;    [[ "$_rc" -eq 1 ]] && pass || fail "[helper] _ihdg_epoch_from_dt must refuse a shape date(1) would coerce"
_rc=0; _ihdg_epoch_from_dt '' >/dev/null || _rc=$?;             [[ "$_rc" -eq 1 ]] && pass || fail "[helper] _ihdg_epoch_from_dt must refuse the empty string"
_rc=0; _ihdg_epoch_from_dt 'now' >/dev/null || _rc=$?;          [[ "$_rc" -eq 1 ]] && pass || fail "[helper] _ihdg_epoch_from_dt must refuse 'now'"
_rc=0; _ihdg_epoch_from_dt '2026-09-11 10:00:00; touch x' >/dev/null || _rc=$?; [[ "$_rc" -eq 1 && ! -e x ]] && pass || { fail "[helper] _ihdg_epoch_from_dt must refuse a shape carrying a shell metacharacter"; rm -f x; }
# B12 for the execute gate: the real emitter's field list, valued as the measured pre-arm row.
if [[ -n "${B12_ERG_MSG:-}" ]]; then
  erows b12 '2026-09-03 10:00:00' "$B12_ERG_MSG"
  expect "[ERG-B12] a message built from the REAL emitter's field list, valued pre-arm => dark" dark "$TMP/erg-b12.json" "$HB"
else
  fail "[ERG-B12] the emitter-shaped message was not built (B12 above did not run)"
fi
# `_ihdg_graded_row` on the previous-boot row: the HELPER grades the row (it knows no "current"
# boot — that is E13's job), so it must PASS and hand back that row's own boot_id.
mk_rows "$TMP/erg-oldboot-row.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg "boot_id=$OBOOT")" inngest-server-probe "$OBID")"
_rc=0; _out="$(_ihdg_graded_row "$TMP/erg-oldboot-row.json" 0 "$HOSTV" "$HOSTNAMEV" 8 "$NOW" 5400)" || _rc=$?
if [[ "$_rc" -eq 0 && "$(printf '%s\n' "$_out" | wc -l)" -eq 2 && "$(printf '%s\n' "$_out" | head -1)" == "600" && "$(printf '%s\n' "$_out" | tail -1)" == *"boot_id=$OBOOT "* ]]; then pass; else fail "[helper] _ihdg_graded_row must return <age>\\n<message> rc 0 for a gradable previous-boot row" "$_rc" "$_out"; fi
_rc=0; _out="$(_ihdg_graded_row "$TMP/erg-empty.json" 0 "$HOSTV" "$HOSTNAMEV" 8 "$NOW" 5400)" || _rc=$?
[[ "$_rc" -eq 1 && "$_out" == "silent" ]] && pass || fail "[helper] _ihdg_graded_row must return the bare token rc 1 on refusal" "$_rc" "$_out"
# Policy cannot leak into a shared helper: no `_ihdg_*` function body other than `_ihdg_verdict`
# itself may call `_ihdg_verdict`. Awk over function bodies, comments stripped.
_leaks="$(awk '/^_(ihdg|erg)_[a-z_]+\(\) \{$/ { fn=$1; inb=1; next } inb && /^}$/ { inb=0; next } inb && fn!="_ihdg_verdict()" && !/^[[:space:]]*#/ && /_ihdg_verdict/ { print fn }' "$GATE")"
if [[ -z "$_leaks" ]]; then pass; else fail "[helper] these shared helpers call _ihdg_verdict (policy in a helper): $_leaks"; fi
# The selector is defined ONCE: every jq program that selects probe rows embeds `$_IHDG_SELECT`
# (itself built on `$_IHDG_IDENT`, which the heartbeat reader embeds), and the inline copy
# `_ihdg_row_count` carried (measured at plan time) is gone.
_sel_inline="$(grep -c 'select(\$d.host == \$h and \$d.host_name == \$hn)' "$GATE")"
[[ "$_sel_inline" -eq 1 ]] && pass || fail "[helper] the host conjunction appears ${_sel_inline}x in the lib; it must appear exactly once, inside _IHDG_IDENT"
# The expected schema is ONE constant: a bump that reaches the lib and not the emitter (or the
# reverse) would make the gate and the probe disagree about the same row forever.
[[ "$(grep -c '^_IHDG_EXPECTED_SCHEMA=' "$GATE")" -eq 1 && "$(grep -v '^[[:space:]]*#' "$GATE" | grep -c 'expected_schema="[0-9]')" -eq 0 ]] && pass || fail "[helper] the expected schema must be defined once as _IHDG_EXPECTED_SCHEMA and never as a per-entry-point literal"
# (The E11/E13 arm set's SET-EQUALITY to the P1-5 allowlist is asserted in the wiring suite, AC16,
# which derives both sides from source; a second copy of that derivation here would be the very
# copy-of-a-derivation class this PR removes. Mutation row ERG-M20 below drives the classifier.)

# ══ 6.4 THE GUARD-MUTATION HARNESS, EXECUTE-GATE ROWS ═════════════════════════════
# Two scoping rules, and they are the shared-helper contract. GATE-scoped rows patch inside
# `inngest_execute_registry_gate` only, so a predicate line the gate body and a helper happen to
# spell identically cannot match twice and fail the exactly-one-line guard. SHARED rows (the
# `_ihdg_*` helpers, `_IHDG_SELECT`, `_ihdg_verdict`) are UNSCOPED and go through `mutate_shared`:
# the helper line itself is the target, and the label records that the intent is a shared line,
# not a gate-body line. (Until #8316 each shared row ran against two entry points; the unscoped
# form is what let a helper tightening that reddened only one consumer be caught as a copy.)
_S='/^inngest_execute_registry_gate() {$/,/^}$/'
# mutate_shared <gn> <sed> <erg-rows> <erg-tok> [erg extra args…]
mutate_shared() {
  local gn="$1" expr="$2" erows_="$3" etok="$4"; shift 4
  GATE_FN=inngest_execute_registry_gate mutate "${gn}-erg" "$expr" "$erows_" "$etok" "$@"
}

# mutate()'s SELF-TEST. Neutering it to `pass; return 0` silenced every B10 row with the suite still
# green. Drive it with a mutation that cannot land (an anchor matching nothing): the harness must
# report the byte-identical-copy failure, not a silent pass. (Formerly in section 4, driven through
# the retired entry point; it needs `$EROWS`, so it lives here beside H7.)
_w_p="$passes" _w_f="$fails"
mutate SELFTEST 's|THIS-ANCHOR-MATCHES-NOTHING-XYZZY|:|' "$EROWS" dark 2>/dev/null
_w_ok=0; [[ "$fails" -eq $((_w_f + 1)) ]] && _w_ok=1
passes="$_w_p"; fails="$_w_f"
if [[ "$_w_ok" -eq 1 ]]; then pass; else fail "INSTRUMENT: mutate() did not fail on a mutation that cannot land — the whole B10 harness is decorative"; fi

# H7 — the KNOWN-NEGATIVE. The existing self-test proves mutate() fails on a patch that cannot
# land; nothing proved it can say "did NOT change" — a harness reporting "changed" for every
# patch is indistinguishable from a working one. A single-line patch on a COMMENT inside the gate
# lands, changes exactly one line, and must leave the verdict alone.
_w_p="$passes" _w_f="$fails"
mutate ERG-H7 "$_S s|^  # ── E12 — .*|  # ── E12 (comment mutated by the H7 known-negative) ──|" "$EROWS" dark 2>/dev/null
_w_ok=0; [[ "$fails" -eq $((_w_f + 1)) && "$passes" -eq "$_w_p" ]] && _w_ok=1
passes="$_w_p"; fails="$_w_f"
if [[ "$_w_ok" -eq 1 ]]; then pass; else fail "INSTRUMENT [H7]: mutate() did not report 'did NOT change the verdict' on a non-load-bearing line — it cannot distinguish a dead line from a live one"; fi

# Gate-scoped rows (matrix 1, 2, 4, 5, 14, 15).
# The E9/E8 fixtures below carry registry_fns=__UNREADABLE__ (emsg's default) ON PURPOSE: the
# drop-one cases for E9/E8 above use the emitter-realistic `registry_fns=0` / `n/a`, and against
# THOSE a neutered E9/E8 lands on E12's `unreadable` — a diagnosis kill that says nothing about
# whether E9/E8 alone stand between a serving host and `dark`. These do.
erows e9-open  '2026-09-03 10:00:00' "$(emsg http_code=200)"
erows e8-open  '2026-09-03 10:00:00' "$(emsg host_role=web)"
mutate_open ERG-M1  "$_S s|^  \[\[ \"\$http_code\" != \"200\" \]\].*|  :|"                 "$TMP/erg-e9-open.json"  host_serving
mutate_open ERG-M2  "$_S s|^  \[\[ \"\$server_active\" != \"active\" \]\].*|  :|"          "$TMP/erg-e10.json"      host_serving
mutate_open ERG-M4  "$_S s|^  \[\[ \"\$host_role\" == \"dedicated\" \]\].*|  :|"           "$TMP/erg-e8-open.json"  wrong_host
mutate_open ERG-M5  "$_S s|^  \[\[ \"\$registry_fns\" == \"__UNREADABLE__\" \]\].*|  :|"  "$TMP/erg-e12.json"      unreadable
mutate_open ERG-M14 's|select(\$d._BOOT_ID == \$b)|select(true)|'                            "$EROWS" fsm_silent --hb-file "$TMP/erg-hb-oldboot.json"
mutate_open ERG-M15 "$_S s|^  \[\[ \"\$hb_age\" -le \"\$hb_max_age\" \]\].*|  :|"          "$EROWS" fsm_silent --hb-file "$TMP/erg-hb-2h.json"
mutate_open ERG-M-E14 "$_S s|^    \[\[ \"\$hb_transition_epoch\" -le \"\$row_epoch\" \]\].*|    :|" "$EROWS" stale_row --hb-file "$TMP/erg-hb-transition-after.json"
# The flag classifier (matrix 3, 16, 20) — one definition serves E11 and E13, so one mutation
# reaches both; the two fixtures prove each consumer reads it.
mutate_open ERG-M3  "s|^    \*) printf 'unreadable' ;;|    *) printf 'preflip' ;;|"        "$TMP/erg-e11-unknown.json" flag_unreadable
mutate_open ERG-M16 "s|^    \*) printf 'unreadable' ;;|    *) printf 'preflip' ;;|"        "$EROWS" flag_unreadable --hb-file "$TMP/erg-hb-unknown.json"
mutate ERG-M20 "s|^    armed\|flipping\|flushed\|done) printf 'armed' ;;|    armed\|flipping\|done) printf 'armed' ;;|" "$TMP/erg-e11-flushed.json" flag_armed
# Shared rows (matrix 6, 7, 8, 9, 10, 11) — each is a helper line, scored through the execute gate.
mutate_shared ERG-M6  's|^  \[\[ "\$schema" == "\$expected_schema" \]\]|  [[ "$schema" -ge "$expected_schema" ]]|' "$TMP/erg-e6b.json" stale_schema
mutate_shared ERG-M7  's|^    _ihdg_refuse silent; return 1$|    :|'                    "$TMP/erg-empty.json" silent
mutate_shared ERG-M8  's|^  \[\[ "\$query_rc" -eq 0 \]\].*|  :|'                        "$EROWS" unreadable --query-rc 22
# Row 9: a FRESH foreign row beside a STALE dedicated row. With the host conjunction gone the
# foreign row supplies the recency bound (and is then graded — `wrong_host` from E8).
mk_rows "$TMP/erg-foreign-fresh.json" \
  "$(bs_line '2026-09-03 07:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")" \
  "$(bs_line '2026-09-03 10:00:00' 'soleur-web-platform' 'soleur-web-prd' "$(emsg host_role=web)" inngest-server-probe "$EBID")"
mutate_shared ERG-M9  's|select(\$d.host == \$h and \$d.host_name == \$hn)|select(true)|' "$TMP/erg-foreign-fresh.json" stale_row
mutate_shared ERG-M10 's|^  \[\[ "\$chosen_boot" =~ \^\[0-9a-f\]{8}-.*|  :|'           "$TMP/erg-e7b.json" unreadable
mutate_shared ERG-M11 's|^  \[\[ "\$1" == "dark" \]\]$|  true|'                          "$TMP/erg-e9.json" host_serving
# Row 12 — the tie check itself, neutered in the shared helper: a disagreeing tie must refuse.
mutate_shared ERG-M12 's|^  if \[\[ "\$(_ihdg_tied_newest "\$rows_file" "\$host" "\$host_name")" != "1" \]\]; then$|  if false; then|' "$TMP/erg-tie.json" unreadable
# …and in the OTHER file order, where the neutered tie check grades the dark half: `sort_by` is
# stable, so which row "wins" a tie is the caller's row order, and a fixture that only ever puts the
# serving row last kills on the safe side of that dependence (review, 2026-09-11).
mk_rows "$TMP/erg-tie-rev.json" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg http_code=200 server_active=active registry_fns=9)" inngest-server-probe "$EBID")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")"
GATE_FN=inngest_execute_registry_gate mutate_open ERG-M12-rev 's|^  if \[\[ "\$(_ihdg_tied_newest "\$rows_file" "\$host" "\$host_name")" != "1" \]\]; then$|  if false; then|' "$TMP/erg-tie-rev.json" unreadable
# EVERY OTHER LINE OF THE SHARED PRELUDE, scored through the execute gate: a helper line that no
# execute-gate row drives is a line the execute gate could stop depending on without this file
# noticing.
mutate_shared ERG-M-G4  's|^  \[\[ "\$schema" == "\$expected_schema" \]\].*|  :|'                    "$TMP/erg-e6.json" stale_schema
NOWV=1788440400 SECOND="$TMP/erg-hb-late.json" mutate_shared ERG-M-G3 's|^  \[\[ "\$row_age" -le "\$max_row_age" \]\].*|  :|' "$EROWS" stale_row --now-epoch 1788440400
unset NOWV SECOND
mutate_shared ERG-M-FUT 's|^  \[\[ "\$row_age" -ge 0 \]\].*|  :|'                                  "$EROWS" stale_row --now-epoch 1788429000
mutate_shared ERG-M-E2  's|^  \[\[ "\$raw_lines" -ge 1 \&\& "\$decoded_rows" -eq 0 \]\]$|  false|'            "$TMP/erg-garbage.json" unreadable
# `_ihdg_field`'s duplicate-name refusal (the field-injection lesson): a row carrying http_code twice.
mk_rows "$TMP/erg-dupfield.json"  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg) http_code=200" inngest-server-probe "$EBID")"
mutate_shared ERG-M-DUP 's|^  \[\[ "\$hits" -eq 1 \]\] \|\| return 1$|  :|'                          "$TMP/erg-dupfield.json" unreadable
# "The chosen row must BE the newest row": a newer row with no probe_schema beside an older one with it.
mk_rows "$TMP/erg-oldschema.json" \
  "$(bs_line '2026-09-03 09:50:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg -probe_schema)" inngest-server-probe "$EBID")"
mutate_shared ERG-M-NEW 's|^  if \[\[ "\$chosen_msg" != "\$newest_msg" \]\]; then$|  if false; then|' "$TMP/erg-oldschema.json" unreadable
# #8846 — the shared probe-row predicate, emptied in the ONE place the lib embeds it. The forged
# doppler row then becomes the newest "probe" row and the gate grades it as serving. A row that
# reddens only some readers is a second copy of the selector somewhere (see 6.5).
mutate_shared ERG-M-PROBE 's|^_IHDG_PROBE=.*|_IHDG_PROBE=""|' "$TMP/erg-forged-pair.json" dark

# ── 6.5 THE PER-READER SPLICE (#8846 review, test-design F1) ──────────────────────────────────
# ERG-M-PROBE empties the SHARED `_IHDG_PROBE`, so it proves one edit of the def reddens both
# consumers. It does NOT cover a per-function edit: each of the four readers splices
# `'"$_IHDG_SELECT"'` on its own line, and swapping ONE of them for `_IHDG_IDENT` (decode + host
# only, no probe-row predicate) left the whole suite green. On `_ihdg_newest_dt` that is a FAIL-OPEN
# on the destroy gate: a FRESH doppler event-log row supplies E5's recency while the graded message
# is a 3h-old real dark row — measured `dark`, rc 0, where the pristine gate says `stale_row`.
#
# The fixture: the real dark row at 10:00, a doppler row from the same host at 12:55, NOW 13:00
# (1788440400). Both doppler shapes: LIVE (the event log's JSON line, marker quoted mid-string —
# the #8833/#8834 shape) and FORGED (the message BEGINS with the marker). Behaviour first; then one
# mutation row per reader.
_evlog_live() { jq -cn --arg b "$1" '{caller:"api", msg:"webhook received", body:$b}'; }
mk_rows "$TMP/erg-stale-evlog-live.json" "$(cat "$EROWS")" \
  "$(bs_line '2026-09-03 12:55:00' "$HOSTV" "$HOSTNAMEV" "$(_evlog_live "$(emsg)")" doppler "$EBID")"
mk_rows "$TMP/erg-stale-evlog-forged.json" "$(cat "$EROWS")" \
  "$(bs_line '2026-09-03 12:55:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" doppler "$EBID")"
GATE_FN=inngest_execute_registry_gate expect "[#8846-G3] execute gate: STALE real row + FRESH doppler event-log row (LIVE shape) => stale_row, never dark" \
  stale_row "$TMP/erg-stale-evlog-live.json" "$TMP/erg-hb-late.json" --now-epoch 1788440400
GATE_FN=inngest_execute_registry_gate expect "[#8846-G3] execute gate: STALE real row + FRESH doppler row BEGINNING with the marker (FORGED) => stale_row, never dark" \
  stale_row "$TMP/erg-stale-evlog-forged.json" "$TMP/erg-hb-late.json" --now-epoch 1788440400
# A doppler row TIED with the real row on `dt` is not a tie: it is not a probe row. The pristine
# gate grades the real row; `_ihdg_tied_newest` without the predicate sees two distinct messages.
mk_rows "$TMP/erg-tie-evlog.json" "$(cat "$EROWS")" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg http_code=200 server_active=active registry_fns=9)" doppler "$EBID")"
GATE_FN=inngest_execute_registry_gate expect "[#8846-tie] execute gate: a doppler row sharing the real row's dt => dark (not a disagreeing tie)" \
  dark "$TMP/erg-tie-evlog.json" "$HB" --now-epoch "$NOW"

# The splice lives on exactly FOUR lines, one per reader — a fifth reader would carry no row below.
_splice_lines="$(grep -cxF "'\"\$_IHDG_SELECT\"'" "$GATE" || true)"
if [[ "$_splice_lines" == "4" ]]; then pass; else fail "[#8846-splice] expected the \$_IHDG_SELECT splice on exactly 4 lines (the four readers), found ${_splice_lines} — add a SPLICE row for the new reader"; fi
# _splice <reader> — a sed that swaps that ONE reader's `_IHDG_SELECT` splice for `_IHDG_IDENT`,
# range-scoped to the reader's body. mutate() asserts it changed exactly one line.
_splice() { printf '%s' "/^$1() {\$/,/^}\$/ s|^'\"\\\$_IHDG_SELECT\"'\$|'\"\\\$_IHDG_IDENT\"'|"; }
# _ihdg_newest_dt — the fail-OPEN one. Both shapes, and the kill must be `dark`.
NOWV=1788440400 GATE_FN=inngest_execute_registry_gate SECOND="$TMP/erg-hb-late.json" mutate_open SPLICE-NEWEST-live-erg   "$(_splice _ihdg_newest_dt)" "$TMP/erg-stale-evlog-live.json"   stale_row
NOWV=1788440400 GATE_FN=inngest_execute_registry_gate SECOND="$TMP/erg-hb-late.json" mutate_open SPLICE-NEWEST-forged-erg "$(_splice _ihdg_newest_dt)" "$TMP/erg-stale-evlog-forged.json" stale_row
# The other three fail CLOSED (the row/line-count cross-check or the tie refusal catches the extra
# row) — still a verdict change, and still a reader that stopped selecting probe rows.
mutate_shared SPLICE-ROWS  "$(_splice _ihdg_rows)"        "$TMP/erg-forged-pair.json" dark
mutate_shared SPLICE-COUNT "$(_splice _ihdg_row_count)"   "$TMP/erg-forged-pair.json" dark
mutate_shared SPLICE-TIE   "$(_splice _ihdg_tied_newest)" "$TMP/erg-tie-evlog.json"   dark

# THE SCOPING RULE IS ENFORCED, NOT DESCRIBED. Every single-consumer `mutate ERG-…` row must be
# function-scoped (`$_S`), except the ones whose line lives in a helper only the execute gate
# consumes (`_erg_flag_class`, `_erg_hb_newest`). Anything else unscoped is a shared-helper line
# and must say so by going through `mutate_shared` — a bare unscoped `mutate` row is a helper
# edit asserted without declaring it.
_unscoped="$(grep -E '^(GATE_FN=[a-z_]+ )?mutate(_open)? ERG-' "${BASH_SOURCE[0]}" | grep -v '"\$_S ' | grep -vE '^(GATE_FN=[a-z_]+ )?mutate(_open)? ERG-(M3|M16|M20|M14|M12-rev) ' || true)"
if [[ -z "$_unscoped" ]]; then pass; else fail "[harness] unscoped mutate rows on shared lines must go through mutate_shared:" 0 "$_unscoped"; fi

# ══ 6.6 Row 8 — the DEFAULT clock ═══════════════════════════════════════════════
# Every arm above pins `--now-epoch`, so the branch that reads the real clock (`date -u +%s`, the
# one production takes) is never executed. A row stamped at this moment must clear it. The probe
# row and its heartbeat are stamped from ONE `date` capture, and the heartbeat is a `noop-*` row,
# so E14 cannot fire and any `stale_row` below is E5's alone.
_row8_now="$(date -u '+%Y-%m-%d %H:%M:%S')"
erows now "$_row8_now" "$(emsg)"
mk_rows "$TMP/erg-hb-now.json" "$(hb_line "$_row8_now" "$HOSTV" "$HOSTNAMEV" "$EBID" aborted)"
_out="$(inngest_execute_registry_gate --rows-file "$TMP/erg-now.json" --query-rc 0 --hb-file "$TMP/erg-hb-now.json" --hb-rc 0 2>&1)" && _rc=0 || _rc=$?
if [[ "$(printf '%s\n' "$_out" | tail -1)" == "dark" && "${_rc:-1}" -eq 0 ]]; then pass; else fail "Row 8: a row stamped NOW does not clear under the real clock (got '$_out')"; fi
# ...and the same row two hours in the past must not.
erows old "$(date -u -d '2 hours ago' '+%Y-%m-%d %H:%M:%S')" "$(emsg)"
_out="$(inngest_execute_registry_gate --rows-file "$TMP/erg-old.json" --query-rc 0 --hb-file "$TMP/erg-hb-now.json" --hb-rc 0 2>&1)" && _rc=0 || _rc=$?
if [[ "$(printf '%s\n' "$_out" | tail -1)" == "stale_row" ]]; then pass; else fail "Row 8b: a 2h-old row cleared under the real clock (got '$_out')"; fi
# ...and the SAME default clock reached through the helper directly. `inngest_execute_registry_gate`
# always hands `_ihdg_graded_row` a resolved `now_epoch`, so the helper's own `date -u +%s` fallback is
# unreachable through the gate; an empty sixth operand is the only way to drive it. Without these two
# rows the fallback line is deletable at full green (the differential run measured it surviving).
_rc=0; _out="$(_ihdg_graded_row "$TMP/erg-now.json" 0 "$HOSTV" "$HOSTNAMEV" 8 "" 5400)" || _rc=$?
if [[ "$_rc" -eq 0 && "$(printf '%s\n' "$_out" | wc -l)" -eq 2 ]]; then pass; else fail "[helper] _ihdg_graded_row with an EMPTY now_epoch must grade a just-stamped row on the real clock" "$_rc" "$_out"; fi
_rc=0; _out="$(_ihdg_graded_row "$TMP/erg-old.json" 0 "$HOSTV" "$HOSTNAMEV" 8 "" 5400)" || _rc=$?
if [[ "$_rc" -eq 1 && "$_out" == "stale_row" ]]; then pass; else fail "[helper] _ihdg_graded_row with an EMPTY now_epoch must refuse a 2h-old row as stale_row on the real clock" "$_rc" "$_out"; fi
# The lib defines exactly ONE entry point. The workflow-test census keys on the `inngest_*_gate` name
# family, so a second entry point under another name would be invisible to it; this pins the count.
_entry_n="$(grep -cE '^inngest_[a-z0-9_]+\(\) *\{' "$GATE")"
[[ "$_entry_n" -eq 1 ]] && pass || fail "[helper] the lib defines ${_entry_n} inngest_* entry point(s); it must define exactly one (inngest_execute_registry_gate)"

# ── Ports: kills the retired battery held and this one did not ───────────────────
# The differential mutation run (#8316) found six shared-helper lines whose ONLY killing case lived
# in the retired entry point's rows. Each is re-expressed here against the execute gate's own
# pre-arm fixture (`emsg`), so the helper is still graded by something after the retired entry point is gone.
# [ERG-port] ids are not predicates: they do not count toward `_PRED_FLOOR`.
#
# A malformed PROBE line must not swallow the valid row after it (`-R` + `fromjson?` in
# `_ihdg_newest_dt` / `_ihdg_tied_newest`; the heartbeat-side twin is asserted above).
mk_rows "$TMP/erg-torn.json" 'not json{{{' \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")"
expect "[ERG-port] a malformed probe line does not swallow the valid row after it => dark" dark "$TMP/erg-torn.json" "$HB"
# `_ihdg_rows` sorts by dt and says so. Newest FIRST on disk: the newest row is still the newest.
mk_rows "$TMP/erg-reverse.json" \
  "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")" \
  "$(bs_line '2026-09-03 09:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg http_code=200 server_active=active registry_fns=0)" inngest-server-probe "$EBID")"
expect "[ERG-port] rows in REVERSE file order are still sorted by dt => dark" dark "$TMP/erg-reverse.json" "$HB"
# An unparseable `dt` is unreadable, never a stale or a fresh row.
mk_rows "$TMP/erg-baddt.json" "$(bs_line 'yesterday' "$HOSTV" "$HOSTNAMEV" "$(emsg)" inngest-server-probe "$EBID")"
expect "[ERG-port] an unparseable dt => unreadable" unreadable "$TMP/erg-baddt.json" "$HB"
# A single-encoded `raw` envelope (an object, not a JSON string) is an encoding change, not silence.
printf '%s\n' "{\"dt\":\"2026-09-03 10:00:00\",\"raw\":{\"host\":\"$HOSTV\",\"host_name\":\"$HOSTNAMEV\",\"message\":\"$(emsg)\",\"SYSLOG_IDENTIFIER\":\"inngest-server-probe\"}}" > "$TMP/erg-single-enc.json"
expect "[ERG-port] a single-encoded raw envelope refuses as unreadable" unreadable "$TMP/erg-single-enc.json" "$HB"
# The wrong-host census is a census of PROBE rows: a forged doppler row from the web host is not
# evidence that the identity filter is wrong, so a window holding nothing else is `silent`.
erows forged-web '2026-09-03 10:00:00' "$(emsg http_code=200 server_active=active registry_fns=9 host_role=web)" 'soleur-web-platform' 'soleur-web-prd' doppler
expect "[ERG-port] a FORGED doppler row from the WEB host only => silent (never wrong_host)" silent "$TMP/erg-forged-web.json" "$HB"
# A BARE `*`: under `toks=($msg)` it globs the CWD and injects `server_active=active`. The gate runs
# in the subshell and the verdict is asserted in the parent (a `( … ) && pass` form cannot fail).
mkdir -p "$TMP/globcwd" && : > "$TMP/globcwd/server_active=active"
[[ -e "$TMP/globcwd/server_active=active" ]] && pass || fail "[ERG-port] the glob row's precondition: the decoy file the bare * would expand to does not exist"
mk_rows "$TMP/erg-glob.json" "$(bs_line '2026-09-03 10:00:00' "$HOSTV" "$HOSTNAMEV" "$(emsg -server_active) *" inngest-server-probe "$EBID")"
_glob_out="$( cd "$TMP/globcwd" && inngest_execute_registry_gate --rows-file "$TMP/erg-glob.json" --query-rc 0 \
  --hb-file "$HB" --hb-rc 0 --now-epoch "$NOW" 2>&1 )" && _glob_rc=0 || _glob_rc=$?
if [[ "$(printf '%s\n' "$_glob_out" | tail -1)" == "unreadable" && "${_glob_rc:-0}" -ne 0 ]]; then pass; else fail "[ERG-port] an absent field is NOT supplied by globbing the CWD" "${_glob_rc:-0}" "$_glob_out"; fi

unset GATE_FN

# ══ 7. THE SELECTOR IS SOURCED, AND ITS ABSENCE IS A REFUSAL (#8846) ═════════════
# The probe-row predicate lives in scripts/lib/inngest-probe-row.sh. A gate that cannot load it
# cannot tell a probe row from a forged event-log row, so it has measured nothing: the entry point
# must refuse `unreadable` FIRST — before E1 and before any later predicate — with the lib path on
# STDERR and stdout the bare token only, because the production callers read the verdict with
# `$(…)` / `tail -1`.
#
# _sel_run <gate-file> <entry-point> <rows> <second> [extra args…] — run <entry-point> from a fresh
# `bash -c` that sources <gate-file>, so the lib is resolved at SOURCE time exactly as a caller
# resolves it. stdout -> `_sel_out`, rc -> `_sel_rc`, stderr -> $TMP/sel-err.txt. The caller's env
# (the INNGEST_PROBE_ROW_LIB under test) is inherited, so a per-call `VAR=… _sel_run` sets it.
_sel_run() {
  local gate_file="$1" fn="$2" rows="$3" second="$4"; shift 4
  local -a a=(); local d; d="$(GATE_FN="$fn" _gate_default_args "$rows" "$second")"
  mapfile -t a <<< "$d"
  local q; q="$(printf '%q ' "${a[@]}" "$@")"
  _sel_rc=0
  _sel_out="$(bash -c "set -uo pipefail; source '$gate_file'; $fn $q" 2>"$TMP/sel-err.txt")" || _sel_rc=$?
}
# _sel_refused <label> — the three-part refusal contract, asserted as ONE row per call.
_sel_refused() {
  local err; err="$(cat "$TMP/sel-err.txt" 2>/dev/null)"
  if [[ "$_sel_out" == "unreadable" && "$_sel_rc" -eq 1 ]] && grep -qF -- "$_SEL_PATH" <<<"$err"; then
    pass
  else
    fail "$1 (want stdout exactly 'unreadable', rc 1, and '$_SEL_PATH' named on stderr)" "$_sel_rc" "stdout=[${_sel_out}] stderr=[${err:0:300}]"
  fi
}
REPO_LIB_FOR_SEL="$REPO_ROOT/scripts/lib/inngest-probe-row.sh"
_SEL_PATH=/nonexistent/inngest-probe-row.sh
INNGEST_PROBE_ROW_LIB="$_SEL_PATH" _sel_run "$GATE" inngest_execute_registry_gate "$EROWS" "$HB" --now-epoch "$NOW"
_sel_refused "[#8846-lib] execute gate, selector lib MISSING, otherwise dark inputs => unreadable"
# ...and before E1: E1 would refuse `unreadable` on its own here, SILENTLY — only the stderr naming
# the lib proves the selector check ran first.
INNGEST_PROBE_ROW_LIB="$_SEL_PATH" _sel_run "$GATE" inngest_execute_registry_gate "$EROWS" "$HB" --query-rc 22 --now-epoch "$NOW"
_sel_refused "[#8846-lib] execute gate, selector lib MISSING and --query-rc 22 => unreadable WITH the lib named (checked before E1)"
# A file that SOURCES cleanly but defines no selector is the same missing selector.
_SEL_PATH=/dev/null
INNGEST_PROBE_ROW_LIB="$_SEL_PATH" _sel_run "$GATE" inngest_execute_registry_gate "$EROWS" "$HB" --now-epoch "$NOW"
_sel_refused "[#8846-lib] execute gate, selector lib sources but defines nothing (/dev/null) => unreadable"
# #8846 review P2-1 (reproduced as a FAIL-OPEN before the fix): an INHERITED permissive def plus a
# lib that assigns nothing. `.github/actions/infra-credentials` exports Doppler keys into
# $GITHUB_ENV, so the inherited value is a real channel; the load must unset it and prove the def.
INNGEST_PROBE_ROW_JQ='def inngest_probe_row: true;' INNGEST_PROBE_ROW_LIB="$_SEL_PATH" \
  _sel_run "$GATE" inngest_execute_registry_gate "$EROWS" "$HB" --now-epoch "$NOW"
_sel_refused "[#8846-lib] execute gate, INHERITED permissive INNGEST_PROBE_ROW_JQ + lib defining nothing => unreadable"
# A lib that LOADS and defines the selftest but whose def admits a doppler row fails its own
# selftest: the load is proven against the event-log shapes, not merely present.
_SEL_PATH="$TMP/permissive-probe-row.sh"
sed 's/^INNGEST_PROBE_ROW_JQ=.*/INNGEST_PROBE_ROW_JQ="def inngest_probe_row: true;"/' "$REPO_LIB_FOR_SEL" > "$_SEL_PATH"
if cmp -s "$REPO_LIB_FOR_SEL" "$_SEL_PATH"; then fail "[#8846-lib] permissive-lib fixture did not land (INNGEST_PROBE_ROW_JQ= line moved?)"; else pass; fi
INNGEST_PROBE_ROW_LIB="$_SEL_PATH" _sel_run "$GATE" inngest_execute_registry_gate "$EROWS" "$HB" --now-epoch "$NOW"
_sel_refused "[#8846-lib] execute gate, lib loads but its def is permissive (selftest fails) => unreadable"

# THE CANARY. Every B10 mutant and the H2 copy run from $TMP, outside the repo. If they could not
# load the selector they would all refuse `unreadable`, and every mutation row would score a kill
# that measured the missing lib instead of the neutered line. An UNMUTATED copy run the same way
# must return the control token.
cp "$GATE" "$TMP/canary-gate.sh" || { echo "FATAL: could not copy the gate for the canary" >&2; exit 2; }
_sel_run "$TMP/canary-gate.sh" inngest_execute_registry_gate "$EROWS" "$HB" --now-epoch "$NOW"
if [[ "$_sel_out" == "dark" && "$_sel_rc" -eq 0 ]]; then pass; else fail "[#8846-canary] an UNMUTATED copy of the gate under \$TMP (execute entry) did not return dark — the mutants cannot load the selector" "$_sel_rc" "$_sel_out $(cat "$TMP/sel-err.txt")"; fi
# ...and the canary DISCRIMINATES: the same copy with the override removed resolves the lib
# relative to $TMP, finds nothing, and refuses. Without this row the canary would also pass
# against a gate that never loads the selector at all.
_sel_out="$(env -u INNGEST_PROBE_ROW_LIB bash -c "set -uo pipefail; source '$TMP/canary-gate.sh'; inngest_execute_registry_gate $(printf '%q ' --rows-file "$EROWS" --query-rc 0 --hb-file "$HB" --hb-rc 0 --now-epoch "$NOW")" 2>/dev/null)" && _sel_rc=0 || _sel_rc=$?
if [[ "$_sel_out" == "unreadable" && "$_sel_rc" -eq 1 ]]; then pass; else fail "[#8846-canary] a copy under \$TMP with NO override still graded — the gate is not loading the selector from its own location" "$_sel_rc" "$_sel_out"; fi
# The DEFAULT path — resolved from the gate's own location, which is how the production caller
# (scripts/cutover-inngest.sh) loads it — must find the real lib.
_sel_out="$(env -u INNGEST_PROBE_ROW_LIB bash -c "set -uo pipefail; source '$GATE'; inngest_execute_registry_gate $(printf '%q ' --rows-file "$EROWS" --query-rc 0 --hb-file "$HB" --hb-rc 0 --now-epoch "$NOW")" 2>&1)" && _sel_rc=0 || _sel_rc=$?
if [[ "$_sel_out" == "dark" && "$_sel_rc" -eq 0 ]]; then pass; else fail "[#8846-lib] with no override the gate must resolve scripts/lib/inngest-probe-row.sh from its own location" "$_sel_rc" "$_sel_out"; fi

# ONE DEFINITION: the marker literal appears on NO executable line of the gate. The predicate
# carries it; a surviving inline copy is a second selector that the next tightening will miss —
# the exact drift the header's "DEFINED ONCE" section records twice already.
_marker_code="$(grep -vE '^[[:space:]]*#' "$GATE" | grep -cF 'SOLEUR_INNGEST_SERVER_PROBE' || true)"
if [[ "$_marker_code" -eq 0 ]]; then pass; else fail "[#8846-once] the probe marker appears on ${_marker_code} non-comment line(s) of the gate; select through inngest_probe_row instead"; fi

# ══ FLOORS ═══════════════════════════════════════════════════════════════════════
# THREE floors, and they measure different things. The predicate floor is the one the drop-one
# battery is about: a battery keyed on verdict TOKENS needs only ~10 cases because several
# predicates share a token, so a token-keyed battery silently under-covers and this floor is what
# makes that visible. EXACT (`-ne`), like the assertion floor below: a `-lt` floor tolerates a
# deleted predicate until the slack is used up, and the slack is attack budget. The comparison and
# both messages read the SAME literal, defined once here.
_PRED_FLOOR=14
_distinct=0; for _g in ${_seen_predicates:-}; do _distinct=$((_distinct + 1)); done
if [[ "$_distinct" -ne "$_PRED_FLOOR" ]]; then
  fails=$((fails + 1))
  printf '  FAIL DROP-ONE FLOOR: %s DISTINCT predicates covered (%s cases ran), floor is exactly %s. Covered:%s\n' \
    "$_distinct" "$predicate_cases" "$_PRED_FLOOR" "${_seen_predicates:-}" >&2
else
  printf '  ok   drop-one floor: exactly %s distinct predicates covered across %s cases (floor %s)\n' "$_distinct" "$predicate_cases" "$_PRED_FLOOR"
fi

# TOKEN COVERAGE. T = every token the lib can emit (from the lib, not from this file); with one
# entry point that is the execute gate's eleven. Every member must have been ASSERTED through
# expect(), and `dark` — the one arm a refuse-everything gate satisfies — an EXACT number of times.
# The must-FAIL self-tests above call `expect ... dark` too, and each rolls its token back out of
# `_seen_tokens`; before #8316 they did not, so the old `dark >= 2` floor was satisfied by the
# self-tests alone and could not see a deleted must-PASS case.
_DARK_FLOOR=18
_T="$(grep -v '^[[:space:]]*#' "$GATE" | grep -oE '_ihdg_verdict "[a-z0-9_]+"' | cut -d'"' -f2 | sort -u)"
_T_n=0; _T_hit=0; _T_miss=""
for _tok in $_T; do
  _T_n=$((_T_n + 1))
  case " ${_seen_tokens} " in *" ${_tok} "*) _T_hit=$((_T_hit + 1)) ;; *) _T_miss="${_T_miss} ${_tok}" ;; esac
done
_dark_n=0; for _tok in $_seen_tokens; do [[ "$_tok" == "dark" ]] && _dark_n=$((_dark_n + 1)); done
_T_EXPECT=11   # the execute gate's tokens; read by the test below and by its failure message
if [[ "$_T_n" -eq "$_T_EXPECT" && "$_T_hit" -eq "$_T_n" && "$_dark_n" -eq "$_DARK_FLOOR" ]]; then
  printf '  ok   token coverage: %s/%s tokens asserted (dark asserted exactly %sx)\n' "$_T_hit" "$_T_n" "$_dark_n"
else
  fails=$((fails + 1))
  printf '  FAIL TOKEN COVERAGE: %s/%s lib tokens asserted (want %s/%s), dark %sx (want exactly %s); never asserted:%s\n' "$_T_hit" "$_T_n" "$_T_EXPECT" "$_T_EXPECT" "$_dark_n" "$_DARK_FLOOR" "${_T_miss:- none}" >&2
fi

# The assertion floor is self-contained — bash builtins and this suite's own counters only. A floor
# that lives in a helper is silenced by the same move that silences the arms it guards. The literal
# is defined ONCE here and both sites read it.
#
# EXACT (`-ne`), NOT `-lt`. A `-lt` floor is satisfied by delete-one-add-one, and the slack it
# tolerates is attack budget: the one assertion of slack a sibling suite once carried absorbed
# exactly the row a mutation had proven load-bearing. A helper row that quietly stops running is
# the failure mode, and only an exact count sees it. The cost is a one-number bump on every
# legitimate addition — and the failure text below dictates the number, so the bump is mechanical.
#
# History, ending at this change: 309 with #8285 PR A (the recut job's wiring rows died, three rows
# pinned the surviving consumer); 180 with #8316, measured, then 184 at its review round (+1 glob-row precondition, +2 helper default-clock rows, +1 single-entry-point pin). The retired entry point's drop-one
# battery, plan-matrix rows, field-injection and review-found fail-open rows, H-rows, B13, the B10
# rows for G4-G20, the operand rows, every `-sib` half and the recut-gate selector rows died with it;
# the execute gate's own rows are unchanged, four section-7 rows were rebound to it rather than
# deleted, and the default-clock rows (Row 8/8b) were rebound to it as well. The base and branch
# assertion LABEL lists were diffed so the count cannot hide an accidental deletion. Six `[ERG-port]`
# rows (section 6.6) re-express kills that only the retired battery held (see the differential run).
_FLOOR=184
_ran=$((passes + fails))
if [[ "$_ran" -lt "$_FLOOR" ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is %s. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" "$_FLOOR" >&2
  printf 'inngest-host-dark-gate: %s passed, %s failed\n' "$passes" "$fails"
  exit 1
elif [[ "$_ran" -ne "$_FLOOR" ]]; then
  fails=$((fails + 1))
  printf '  FAIL STALE FLOOR: %s assertions ran, _FLOOR is %s — set _FLOOR=%s (the count is exact by design; an assertion was added without updating it).\n' "$_ran" "$_FLOOR" "$_ran" >&2
  printf 'inngest-host-dark-gate: %s passed, %s failed\n' "$passes" "$fails"
  exit 1
else
  printf '  ok   anti-vacuity floor: exactly %s assertions ran (floor %s)\n' "$_ran" "$_FLOOR"
fi

echo ""
echo "inngest-host-dark-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
