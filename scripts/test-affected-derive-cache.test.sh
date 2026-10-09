#!/usr/bin/env bash
# test-affected-derive-cache.test.sh — the cross-run derive cache (#9812).
#
# PROPERTY. `scripts/lib/test-affected-derive-cache.sh` lets a local `--affected` walk serve a
# registration's `_affected_classify` result from a per-record cache under `.soleur/cache/
# affected-derive/v<schema>/`, keyed on schema + derive-code hash + label + argv and validated
# against the recorded read-file blob ids and probe outcomes. The contract has three legs:
#
#   1. byte-identical replay — a hit restores _AC_CLASS, the ordered _AC_EDGES, the _AC_ESET
#      shadow and _AC_SUITE_FILE exactly as a fresh derive would;
#   2. exact invalidation — a changed read file, a flipped probe outcome, an argv change, a
#      corrupt or wrong-schema record each re-derive that record ONLY;
#   3. advisory-only — no cache failure path can narrow the selection or exit nonzero;
#      `SOLEUR_AFFECTED_DERIVE_CACHE=0` is the kill switch.
#
# ASSEMBLY. The derive block is EXTRACTED from the runner by content anchor — column-0
# `_AC_CLASS=""` through the closing brace of `_affected_derive`, plus the `_affected_classify`
# body — and eval'd in a subshell whose cwd is a synthesized git-init'd fixture tree (the derive's
# probes resolve against cwd; `git hash-object` inside the fixture is the read-hasher). The cache
# lib is sourced verbatim. The floor asserts `declare -F _affected_classify_cached` after the
# eval+source: a missed anchor or an absent lib must not pass vacuously.
#
# AUTHORING (work/SKILL.md): never `producer | grep -q` under pipefail; capture rc on its own
# line; `cases` is incremented at the call site. Fixture git needs only
# `git init` + `hash-object` — no commits, no config.

# shellcheck disable=SC2016,SC2086 # fixture text and eval'd snippets are single-quoted on purpose (their $ must not expand here); form strings split into argv words on purpose
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
CACHELIB="$REPO_ROOT/scripts/lib/test-affected-derive-cache.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"
TESTROOT="$(mktemp -d -t affected-derive-cache.XXXXXXXX)" || exit 2

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TESTROOT"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT INT TERM HUP

PASS=0; FAIL=0; cases=0; SKIPPED=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

# Instrument self-test: both verdict helpers must move their counters.
_sp=$PASS; _sf=$FAIL
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
if (( PASS != _sp + 1 )) || (( FAIL != _sf + 1 )); then
  echo "[FATAL] instrument self-test failed" >&2; exit 1
fi
PASS=$_sp; FAIL=$_sf

# ---- extraction floor -------------------------------------------------------------------------------
# Same anchors as test-affected-derive.test.sh: the block opens on the column-0 `_AC_CLASS=""`
# declaration and ends at the first column-0 `}` after `_affected_derive() {`; the classifier body is
# appended separately. The probe/read RECORDING wrappers (_affected_probe, _affected_rec_read) live
# INSIDE that span, so the extraction carries them.
DERIVE_SRC="$TESTROOT/derive-block.sh"
awk '/^_AC_CLASS=""$/ && !s {s=1} s {print} s && /^_affected_derive\(\) \{/ {d=1} d && /^\}$/ {exit}' "$RUNNER" > "$DERIVE_SRC"
awk '/^_affected_classify\(\) \{/ {s=1} s {print} s && /^\}$/ {exit}' "$RUNNER" >> "$DERIVE_SRC"

# Run a snippet in a fixture tree: cache_run <fixture-dir> <snippet>. The subshell gets the derive
# block, the classifier and the cache lib; TEST_GROUP=all + _PRINT_AFFECTED=0 reproduce the walk's
# call context (the wrapper declines every other one).
cache_run() {
  ( cd "$1" && set -uo pipefail &&
    TEST_GROUP=all && _PRINT_AFFECTED=0 &&
    _wt_missing_die() { :; } &&
    eval "$(cat "$DERIVE_SRC")" &&
    source "$CACHELIB" &&
    eval "$2" )
}

cases=$((cases + 1))
_floor_out="$(cache_run "$TESTROOT" 'declare -F _affected_classify_cached >/dev/null && declare -F _affected_probe >/dev/null && declare -F _affected_rec_read >/dev/null && declare -F _adc_store >/dev/null && echo FOUND' 2>&1)"
if [[ "$_floor_out" == "FOUND" ]] && (( $(wc -c < "$DERIVE_SRC") > 4000 )); then
  pass "floor: derive block extracts by content anchor and the cache lib defines the wrapper ($(wc -c < "$DERIVE_SRC")B block)"
else
  fail "floor: extraction+source produced '${_floor_out}' (${#_floor_out}B), block $(wc -c < "$DERIVE_SRC") bytes"
fi

# ---- fixture tree ------------------------------------------------------------------------------------
# A git repo (hash-object needs one), the four code-hash marker files the lib hashes, and one suite
# with a two-file closure. `git init` output is silenced; no commit is needed — hash-object reads the
# worktree bytes.
FX="$TESTROOT/fx"
assert_fixture_dir "$FX"
mkdir -p "$FX/scripts/lib" "$FX/lib" "$FX/app"
git -C "$FX" init -q
for _cf in scripts/test-all.sh scripts/lib/test-affected-paths.sh scripts/lib/test-relevance-paths.sh scripts/lib/test-affected-derive-cache.sh; do
  printf 'marker v1\n' > "$FX/$_cf"
done
printf 'source "lib/helper.sh"\nbash lib/tool.sh\n' > "$FX/suite.test.sh"
printf 'source lib/dep.sh\n'                        > "$FX/lib/helper.sh"
: > "$FX/lib/dep.sh"
: > "$FX/lib/tool.sh"
: > "$FX/unrelated.txt"

# Emit a canonical record of the classify result + cache counters for a run.
_SNAP='printf "CLASS=%s\nEDGES=%s\nESET=%s\nSF=%s\nH=%s M=%s D=%s\n" \
  "${_AC_CLASS-}" "${_AC_EDGES[*]-}" "${_AC_ESET-}" "${_AC_SUITE_FILE-}" \
  "${_ADC_HITS-0}" "${_ADC_MISSES-0}" "${_ADC_DERIVED-0}"'

# T1 — byte-identical replay: a fresh-process classify on an unchanged tree hits the record written
# by the cold run and returns the identical class/edges/shadow/suite_file.
cases=$((cases + 1))
_a="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
_b="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
_a_state="$(printf '%s\n' "$_a" | grep -v '^[HMD]=')"; _b_state="$(printf '%s\n' "$_b" | grep -v '^[HMD]=')"
_b_ctr="$(printf '%s\n' "$_b" | grep '^H=')"
if [[ -n "$_a_state" && "$_a_state" == "$_b_state" && "$_b_ctr" == "H=1 M=0 D=0" ]]; then
  pass "T1: warm-process classify replays byte-identical state (hit, 0 misses, 0 re-derives)"
else
  fail "T1: cold=[${_a//$'\n'/|}] warm=[${_b//$'\n'/|}]"
fi

# T2 — in-closure edit re-derives only that record: edit a file the derive READ (lib/helper.sh),
# leaving argv and other records untouched.
cases=$((cases + 1))
printf 'source lib/dep.sh\nsource lib/tool2.sh\n' > "$FX/lib/helper.sh"
: > "$FX/lib/tool2.sh"
_c="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
if printf '%s' "$_c" | grep -q 'tool2' && printf '%s' "$_c" | grep -q '^H=0 M=0 D=1$'; then
  pass "T2: editing a recorded read re-derives the record (new edge visible, D=1)"
else
  fail "T2: warm=[${_c//$'\n'/|}]"
fi

# T3 — a file created at a recorded-MISS probe path invalidates the record.
cases=$((cases + 1))
: > "$FX/lib/suite.sh"   # a stem-candidate probe path (lib/ + suite stem) that missed at record time
_d="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
if printf '%s' "$_d" | grep -q 'suite\.sh' && printf '%s' "$_d" | grep -q '^H=0 M=0 D=1$'; then
  pass "T3: creating a file at a recorded-miss probe path re-derives (D=1)"
else
  fail "T3: warm=[${_d//$'\n'/|}]"
fi

# T4 — unrelated edit still hits: a file the derive never read or probed.
cases=$((cases + 1))
printf 'changed\n' >> "$FX/unrelated.txt"
_e="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
if printf '%s' "$_e" | grep -q '^H=1 M=0 D=0$'; then
  pass "T4: an edit to an unread/unprobed file serves the cache (H=1)"
else
  fail "T4: warm=[${_e//$'\n'/|}]"
fi

# Reference state for the degrade rows: the last-good derive is _d's (post-T3, i.e. lib/suite.sh
# exists and helper.sh pulls dep+tool2). Every fallback below must reproduce it byte-identically.
_gold_state="$(printf '%s\n' "$_d" | grep -v '^[HMD]=')"

# T5 — corrupt record falls back to a fresh derive with identical output, in two legs: (a) payload
# appended AFTER the `end` trailer — the post-trailer guard must reject it, and (b) a truncated
# record — the missing `end`/`sum` trailer must reject it. Each re-derives and re-stores a clean
# record for the next leg.
cases=$((cases + 1))
_recdir="$FX/.soleur/cache/affected-derive"
_corrupt_rc=0
_rfile="$(find "$_recdir" -name '*.rec' -type f -print -quit 2>/dev/null)" || _corrupt_rc=$?
if [[ -z "$_rfile" ]]; then _corrupt_rc=9; fi
if (( _corrupt_rc == 0 )); then
  printf 'edge\tCORTEX-MARKER-NEVER-A-REAL-EDGE\n' >> "$_rfile"   # leg a: post-trailer garbage
  _f1="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
  _f1_state="$(printf '%s\n' "$_f1" | grep -v '^[HMD]=')"
  _rfile="$(find "$_recdir" -name '*.rec' -type f -print -quit 2>/dev/null)"
  head -c 200 "$_rfile" > "$_rfile.trunc" && mv "$_rfile.trunc" "$_rfile"   # leg b: truncation
  _f2="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
  _f2_state="$(printf '%s\n' "$_f2" | grep -v '^[HMD]=')"
  if [[ "$_f1_state" == "$_gold_state" && "$_f2_state" == "$_gold_state" ]] \
    && printf '%s' "$_f1" | grep -q '^H=0 M=1 D=0$' \
    && printf '%s' "$_f2" | grep -q '^H=0 M=1 D=0$'; then
    pass "T5: post-trailer garbage and truncated records both miss and re-derive the identical state"
  else
    fail "T5: post-trailer=[${_f1//$'\n'/|}] truncated=[${_f2//$'\n'/|}]"
  fi
else
  fail "T5: no record file found under $_recdir to corrupt (find rc=$_corrupt_rc)"
fi

# T6 — wrong schema field falls back: a record claiming another schema refuses at parse.
cases=$((cases + 1))
_rfile2="$(find "$_recdir" -name '*.rec' -type f -print -quit 2>/dev/null)"
if [[ -n "$_rfile2" ]]; then
  # sed -i.bak + rm: the only prior in-place convention in scripts/ — works on BSD and GNU alike.
  sed -i.bak 's/^schema	.*/schema	vWRONG/' "$_rfile2" && rm -f "$_rfile2.bak"
  _g="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
  if printf '%s' "$_g" | grep -q '^H=0 M=1 D=0$'; then
    pass "T6: a wrong-schema record misses and re-derives"
  else
    fail "T6: warm=[${_g//$'\n'/|}]"
  fi
else
  fail "T6: no record file to corrupt"
fi

# T7 — kill switch: SOLEUR_AFFECTED_DERIVE_CACHE=0 derives fresh, writes nothing (the record count
# must not move — a switch that wrote would poison anyway).
cases=$((cases + 1))
_recs_before="$(find "$_recdir" -name '*.rec' -type f | wc -l | tr -d ' ')"
_h="$(cache_run "$FX" "SOLEUR_AFFECTED_DERIVE_CACHE=0; export SOLEUR_AFFECTED_DERIVE_CACHE; _affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
_recs_after="$(find "$_recdir" -name '*.rec' -type f | wc -l | tr -d ' ')"
_h_state="$(printf '%s\n' "$_h" | grep -v '^[HMD]=')"
if [[ "$_h_state" == "$_gold_state" && "$_recs_before" == "$_recs_after" ]] \
  && printf '%s' "$_h" | grep -q '^H=0 M=0 D=0$'; then
  pass "T7: kill switch derives fresh, serves identical state, touches no counter, writes no record"
else
  fail "T7: warm=[${_h//$'\n'/|}]"
fi

# T8 — argv change is a key change: same label, different argv misses and re-derives.
cases=$((cases + 1))
_i="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh --verbose; $_SNAP" 2>/dev/null)"
if printf '%s' "$_i" | grep -q '^H=0 M=1 D=0$'; then
  pass "T8: changed argv misses (key includes the verbatim argv)"
else
  fail "T8: warm=[${_i//$'\n'/|}]"
fi

# T9 — unreadable cache dir degrades to plain derive: identical state, no nonzero exit, at most one
# stderr note. chmod 000 on the cache root blocks traversal, so BOTH the record read and the store's
# mkdir/mv fail — the two failure legs in one row. (As root the chmod is a no-op and the row still
# verifies via the state/rc/notes assertions.)
cases=$((cases + 1))
chmod 000 "$_recdir" 2>/dev/null || true
_j="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>"$TESTROOT/t9.err")"
_j_rc=$?
_j_state="$(printf '%s\n' "$_j" | grep -v '^[HMD]=')"
_j_notes=$(wc -l < "$TESTROOT/t9.err" | tr -d ' ')
chmod 700 "$_recdir" 2>/dev/null || true
if [[ "$_j_state" == "$_gold_state" && $_j_rc -eq 0 && "$_j_notes" -le 1 ]]; then
  pass "T9: unwritable cache dir degrades (identical state, rc=0, ${_j_notes} stderr note(s))"
else
  fail "T9: rc=$_j_rc notes=$_j_notes state=[${_j//$'\n'/|}]"
fi

# T10 — input-site census: every filesystem input the extracted derive span can consult is either
# routed through `_affected_probe`/`_affected_rec_read`, inside the recorder's own body (`$_pp`), or
# the named `_wt_missing_die` liveness exemption — and every `_[a-z_]+` callee the span reaches is
# defined INSIDE the span (so the code hash covers it) or on the pinned boundary list. A site added
# later WITHOUT recording must fail here — the guard against silent invalidation weakening.
cases=$((cases + 1))
# Probe census: a site is a file-test predicate in [ / [[ / test syntax — in ANY position including
# after && / || / ! inside a compound test (`[[ -n "$p" && -e "$p" ]]` must be caught). The
# predicate class is the full file-test set plus -nt/-ot/-ef, not just e/f/d — a future -x or -s
# site is an unrecorded input the same way. `sed -e` flags and grep `-e` patterns never sit behind
# a test-opener token, so they stay unflagged.
_census_bad="$(grep -nE '(\[\[?|&&|\|\||!|(^|[^_[:alnum:]])test[[:space:]])[[:space:]]*(-[abcdefghkprstuwxGLNOS]|-nt|-ot|-ef)[[:space:]]' "$DERIVE_SRC" \
  | grep -vE '^[0-9]+:[[:space:]]*#|\$_pp|_wt_missing_die|_affected_(probe|rec_read)')"
# Read census: every file-content read must be the funnel read — "$_f" inside
# _affected_file_edges_uncached, recorded via _affected_rec_read at the _affected_file_edges entry.
# Outside the funnel flag mapfile/readarray/$(<f)/source/dot-source, cat and kin with a path
# operand, grep/sed/awk taking a $-variable operand, and `< FILE` redirect reads; inside the funnel
# a primitive on any variable OTHER than $_f reads unrecorded bytes. (Residual: exotic primitives
# — git show, backtick-cat, eval-indirection — are outside this window; the probe census plus the
# bench are the deeper net.)
_reads_bad="$(awk '
  /^[[:space:]]*#/ {next}
  /^_affected_file_edges_uncached\(\)/ {inf=1}
  inf && /^\}$/ {inf=0}
  !inf && (/mapfile|readarray|\$\([<]/ ||
           /(^|[^_[:alnum:]])(source|\.)[[:space:]]+["'"'"'$\/A-Za-z_.]/ ||
           /(^|[[:space:]])(cat|head|tail|wc|sort|uniq|cmp|diff|comm|perl|python|python3|jq|dd|iconv|xargs)[[:space:]]+["'"'"'$\/.A-Za-z_]/ ||
           /(grep|sed|awk)[[:space:]][^|;><]*\$\{?[A-Za-z_]/ ||
           /done[[:space:]]*<[^<(]|(^|[^_])read[[:space:]][^;|]*<[^<(]/) {print NR": "$0; next}
  inf && /(grep|sed|awk|cat|head|tail|wc|mapfile|readarray)[[:space:]][^|;><]*\$\{?[A-Za-z_]/ && !/\$_f/ {print NR": funnel-read-not-on-$_f: "$0}
' "$DERIVE_SRC")"
if [[ -n "$_reads_bad" ]]; then
  _census_bad="${_census_bad:+${_census_bad} || }read-sites: ${_reads_bad}"
fi
# Boundary census: the derive-family functions (_affected_*, _wt_*) defined OUTSIDE the extracted
# span must be exactly the pinned boundary set — a NEW out-of-span helper would escape both the
# code hash and every census above.
_defs_all="$(grep -oE '^_[a-z_]+\(' "$RUNNER" | tr -d '(' | sort -u)"
_defs_span="$(grep -oE '^_[a-z_]+\(' "$DERIVE_SRC" | tr -d '(' | sort -u)"
_affected_out="$(comm -23 <(printf '%s\n' "$_defs_all") <(printf '%s\n' "$_defs_span") | grep -E '^(_affected|_wt_)')"
if [[ "$_affected_out" != $'_affected_emit_receipt\n_wt_missing_die' ]]; then
  _census_bad="${_census_bad:+${_census_bad} || }out-of-span derive-family defs drifted: ${_affected_out//$'\n'/,}"
fi
# The lib's own span-extraction must not go silently partial — both awk legs must produce output
# on the real runner or the code hash quietly drops half the derive.
_s1="$(awk '/^_AC_CLASS=""$/ && !s {s=1} s {print} s && /^_affected_derive\(\) \{/ {d=1} d && /^\}$/ {exit}' "$RUNNER")"
_s2="$(awk '/^_affected_classify\(\) \{/ {s=1} s {print} s && /^\}$/ {exit}' "$RUNNER")"
if [[ ${#_s1} -lt 4096 || -z "$_s2" ]]; then
  _census_bad="${_census_bad:+${_census_bad} || }lib extraction anchors drifted (s1=${#_s1}B s2=${#_s2}B)"
fi
if [[ -z "$_census_bad" ]]; then
  _probe_calls=$(grep -c '_affected_probe [efd] ' "$DERIVE_SRC")
  if (( _probe_calls >= 7 )); then
    pass "T10: census — every probe/read/callee in the derive span is recorded, exempt, or boundary-pinned (${_probe_calls} recorded sites)"
  else
    fail "T10: census clean but only ${_probe_calls} recorded probe sites (<7 — instrumentation dropped?)"
  fi
else
  fail "T10: unrecorded input site(s) in the derive span: ${_census_bad//$'\n'/ || }"
fi

# T11 — the runner emits the AFFECTED_DERIVE_CACHE counters line at walk end (AC8's observability
# leg) and the walk's SUITE_COMMAND arm routes through the wrapper. Anchored on the call shapes, not
# bare names, so comments can't satisfy them.
cases=$((cases + 1))
if grep -qF 'AFFECTED_DERIVE_CACHE\tstate=%s\thits=%d' "$RUNNER" \
  && grep -qF '_affected_classify_cached "${_aff_fields[1]}"' "$RUNNER"; then
  pass "T11: runner emits AFFECTED_DERIVE_CACHE state=/hits=/misses=/derived= and routes the walk through the wrapper"
else
  fail "T11: runner lacks the emit line or the wrapper call site"
fi

# T12 — the runner actually sources the lib through $_ADC_LIB (the degrade-never-block arm): a
# missing/absent lib must leave plain classify reachable. Anchored on the source call.
cases=$((cases + 1))
if grep -qF 'source "$_ADC_LIB"' "$RUNNER"; then
  pass "T12: runner sources scripts/lib/test-affected-derive-cache.sh"
else
  fail "T12: runner never sources the cache lib"
fi

# T13 — memo-consumer invalidation (review P1): two registrations sharing one helper, classified in
# ONE process so the second consumes the first's _FE_FILES memo. The helper names a path that does
# not exist at extraction — the probe-miss must land in BOTH records, so creating the file later
# re-derives the memo-consumer too, not just the extractor. Without the _FE_PROBESETS slice the
# consumer's record would validate forever and serve an edge set missing the created file.
cases=$((cases + 1))
FX2="$TESTROOT/fx2"
assert_fixture_dir "$FX2"
mkdir -p "$FX2/scripts/lib" "$FX2/lib"
git -C "$FX2" init -q
for _cf in scripts/test-all.sh scripts/lib/test-affected-paths.sh scripts/lib/test-relevance-paths.sh scripts/lib/test-affected-derive-cache.sh; do
  printf 'marker v1\n' > "$FX2/$_cf"
done
printf 'source "lib/helper.sh"\n' > "$FX2/suite.test.sh"
printf 'source "lib/helper.sh"\n' > "$FX2/suite2.test.sh"
printf 'source lib/dep.sh\nsource lib/maybe.sh\n' > "$FX2/lib/helper.sh"
: > "$FX2/lib/dep.sh"   # dep.sh exists; maybe.sh deliberately does NOT
# Cold-run both registrations in one process — s2 consumes s1's helper.sh memo.
cache_run "$FX2" "_affected_classify_cached s1 bash suite.test.sh; _affected_classify_cached s2 bash suite2.test.sh" >/dev/null 2>&1
: > "$FX2/lib/maybe.sh"   # the recorded-miss probe path now exists
_k="$(cache_run "$FX2" "_affected_classify_cached s2 bash suite2.test.sh; $_SNAP" 2>/dev/null)"
if printf '%s' "$_k" | grep -q 'maybe' && printf '%s' "$_k" | grep -q '^H=0 M=0 D=1$'; then
  pass "T13: memo-consumer's record carries the extractor's probe slice (created file re-derives it)"
else
  fail "T13: memo-consumer warm=[${_k//$'\n'/|}]"
fi

# T14 — dispatch guards: the wrapper must bypass the cache (and write nothing) outside the
# all-group selection-walk context — TEST_GROUP≠all, and receipt mode (_PRINT_AFFECTED=1), whose
# edge set is deliberately partial and must never be minted into a record.
cases=$((cases + 1))
_recs_t14="$(find "$_recdir" -name '*.rec' -type f | wc -l | tr -d ' ')"
_t14a="$(cache_run "$FX" "TEST_GROUP=webplat; _affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
_t14b="$(cache_run "$FX" "_affected_emit_receipt() { :; }; _PRINT_AFFECTED=1; _affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
_recs_t14b="$(find "$_recdir" -name '*.rec' -type f | wc -l | tr -d ' ')"
if printf '%s' "$_t14a" | grep -q '^H=0 M=0 D=0$' \
  && printf '%s' "$_t14b" | grep -q '^H=0 M=0 D=0$' \
  && [[ "$_recs_t14" == "$_recs_t14b" ]]; then
  pass "T14: dispatch guards — TEST_GROUP/receipt contexts skip the cache and write nothing"
else
  fail "T14: group=[${_t14a//$'\n'/|}] receipt=[${_t14b//$'\n'/|}] recs $_recs_t14->$_recs_t14b"
fi

# T15 — cross-worktree refusal: a record minted in FX must never validate under FX2 even with
# identical code markers, label, and argv — the worktree field refuses it (AC6 leg).
cases=$((cases + 1))
# The record's FILENAME is its key — pick the canonical argv's record by computing the key in-fixture
# (a same-label record under different argv shares the label but lands at a different key).
_canon_key="$(cache_run "$FX" "_adc_init; _adc_key mysuite bash suite.test.sh" 2>/dev/null)"
_rec_src="$_recdir/v1/$_canon_key.rec"
_fx2dir="$FX2/.soleur/cache/affected-derive/v1"
if [[ -f "$_rec_src" && -d "$_fx2dir" ]]; then
  cp "$_rec_src" "$_fx2dir/"
  _m="$(cache_run "$FX2" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
  if printf '%s' "$_m" | grep -q '^H=0 M=1 D=0$'; then
    pass "T15: a record copied across worktrees misses (worktree field refuses foreign records)"
  else
    fail "T15: warm=[${_m//$'\n'/|}]"
  fi
else
  fail "T15: no FX record to copy or FX2 cache dir missing"
fi

# T16 — in-body corruption: flip a byte inside the class field (record still parses, all field
# checks pass) — the `sum` trailer must catch what structure checks cannot. Re-derives and heals.
cases=$((cases + 1))
_rfile3="$_recdir/v1/$_canon_key.rec"
if [[ -f "$_rfile3" ]]; then
  sed -i.bak 's/^class	.*/class	edge:forged-never-a-class/' "$_rfile3" && rm -f "$_rfile3.bak"
  _n="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
  _n_state="$(printf '%s\n' "$_n" | grep -v '^[HMD]=')"
  if [[ "$_n_state" == "$_gold_state" ]] && printf '%s' "$_n" | grep -q '^H=0 M=1 D=0$'; then
    pass "T16: a checksum-mismatched record misses and re-derives the identical state"
  else
    fail "T16: warm=[${_n//$'\n'/|}]"
  fi
else
  fail "T16: no record file to corrupt"
fi

# T17 — argv key collision shape: ('a|b','c') and ('a','b|c') join to the identical string under a
# delimiter scheme — length-prefixing keeps them distinct, and the record count discriminates.
cases=$((cases + 1))
_recs_t17="$(find "$_recdir" -name '*.rec' -type f | wc -l | tr -d ' ')"
cache_run "$FX" "_affected_classify_cached argvshape bash suite.test.sh 'a|b' 'c'" >/dev/null 2>&1
cache_run "$FX" "_affected_classify_cached argvshape bash suite.test.sh 'a' 'b|c'" >/dev/null 2>&1
_recs_t17b="$(find "$_recdir" -name '*.rec' -type f | wc -l | tr -d ' ')"
if (( _recs_t17b == _recs_t17 + 2 )); then
  pass "T17: ('a b') vs ('a','b') mint two distinct records (length-prefixed argv)"
else
  fail "T17: record count $_recs_t17 -> $_recs_t17b (expected +2)"
fi

# T18 — recorded-HIT probe flips to missing: remove a file the derive probed-and-read at record
# time. Both the probe outcome and the read hash drift — the record must re-derive, and the edge
# must leave the replayed set. (Last FX row: this mutates the fixture's gold state.)
cases=$((cases + 1))
rm -f "$FX/lib/tool.sh"
_o="$(cache_run "$FX" "_affected_classify_cached mysuite bash suite.test.sh; $_SNAP" 2>/dev/null)"
if printf '%s' "$_o" | grep -q '^H=0 M=0 D=1$' && ! printf '%s' "$_o" | grep -q 'tool\.sh'; then
  pass "T18: deleting a recorded-hit file re-derives (D=1, edge leaves the set)"
else
  fail "T18: warm=[${_o//$'\n'/|}]"
fi

echo
echo "test-affected-derive-cache: $((PASS))/${cases} rows passed, $FAIL failed, $SKIPPED skipped"
if (( FAIL > 0 || PASS < cases - SKIPPED )); then exit 1; fi
exit 0
