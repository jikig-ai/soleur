#!/usr/bin/env bash
# test-affected-derive.test.sh — the affected pre-pass derive and the selection-identity bench (#9307).
#
# PROPERTY. The source/import closure derive in scripts/test-all.sh (`_affected_derive` and the helpers
# it calls) is bounded and deterministic: a captured variable value resolves literally whatever the
# bash version, a pathological value cannot multiply a token, and edge-set membership agrees with the
# edge array. scripts/affected-prepass-bench.sh is the acceptance contract for any change to that code,
# so its compare logic is exercised here against fake runners and synthesized streams.
#
# ASSEMBLY. The derive block is EXTRACTED from the runner by content anchor — from the column-0
# `_AC_CLASS=""` declaration through the closing brace of `_affected_derive` — and eval'd in a
# subshell whose cwd is a synthesized fixture tree (the derive's `-e` tests resolve against cwd). The
# floor asserts `declare -F _affected_derive` after the eval: a missed anchor must not pass vacuously.
#
# AUTHORING (work/SKILL.md): never `producer | grep -q` under pipefail; capture rc on its own line;
# `cases` is incremented at the call site; a row whose host requirement is missing (bash >= 5.2, a UTF-8
# locale) prints a counted SKIPPED line locally and FAILS under CI (skip_or_fail). Several rows below build
# argv or snippets by word splitting on purpose (a form string becomes argv words); those lines carry a
# disable comment that says why.

# shellcheck disable=SC2016,SC2086 # fixture text and eval'd snippets are single-quoted on purpose (their $ must not expand here); form strings split into argv words on purpose
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
BENCH="$REPO_ROOT/scripts/affected-prepass-bench.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"
TESTROOT="$(mktemp -d -t affected-derive.XXXXXXXX)" || exit 2

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

# bash >= 5.2 has `patsub_replacement`; rows that depend on it cannot be driven on an older bash.
_bash_52=0
if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 2) )); then _bash_52=1; fi
skip_or_fail() { # skip_or_fail <row id> <what the row needs>: a counted skip locally, a FAILURE under CI (CI must not skip silently)
  if [[ -n "${CI:-}" ]]; then
    cases=$((cases + 1)); fail "$1: needs $2 and CI lacks it (bash ${BASH_VERSION})"
  else
    SKIPPED=$((SKIPPED + 1)); echo "  [skip] $1: needs $2 (running bash ${BASH_VERSION})"
  fi
}

# ---- extraction floor -------------------------------------------------------------------------------
# Column-0 `_AC_CLASS=""` is the FIRST occurrence (a second, indented one sits inside _affected_classify);
# the block ends at the first column-0 `}` after `_affected_derive() {`.
DERIVE_SRC="$TESTROOT/derive-block.sh"
awk '/^_AC_CLASS=""$/ && !s {s=1} s {print} s && /^_affected_derive\(\) \{/ {d=1} d && /^\}$/ {exit}' "$RUNNER" > "$DERIVE_SRC"
# `_affected_classify` is the other function that assigns the edge array; R4b drives its entry reset.
awk '/^_affected_classify\(\) \{/ {s=1} s {print} s && /^\}$/ {exit}' "$RUNNER" >> "$DERIVE_SRC"

# Run a snippet against the extracted block in a fixture tree: derive_run <fixture-dir> <snippet>.
derive_run() { # DERIVE_BLOCK overrides the extracted block (the mutant rows run a block with one guard removed)
  ( cd "$1" && set -uo pipefail && _PRINT_AFFECTED=0 && _wt_missing_die() { :; } && eval "$(cat "${DERIVE_BLOCK:-$DERIVE_SRC}")" && eval "$2" )
}

cases=$((cases + 1))
_floor_out="$(derive_run "$TESTROOT" 'declare -F _affected_derive >/dev/null && declare -F _affected_file_edges >/dev/null && declare -F _affected_resolve_vars >/dev/null && echo FOUND' 2>&1)"
if [[ "$_floor_out" == "FOUND" ]] && (( $(wc -c < "$DERIVE_SRC") > 4000 )); then
  pass "floor: the derive block extracts by content anchor and defines the derive functions ($(wc -c < "$DERIVE_SRC") bytes)"
else
  fail "floor: extraction produced '${_floor_out}' (${#_floor_out}B), block $(wc -c < "$DERIVE_SRC") bytes"
fi

# ---- fixture tree for the derive rows ---------------------------------------------------------------
FX="$TESTROOT/fx"
mkdir -p "$FX/lib" "$FX/lib/a&b" "$FX/a"
: > "$FX/lib/helper.sh"
: > "$FX/lib/a&b/x.sh"
: > "$FX/a/b"
: > "$FX/a/bc"
: > "$FX/nl"$'\n'"y"
assert_fixture_dir "$FX"

# R1 (A1): a captured variable value containing `&` resolves LITERALLY, cold and warm. With
# patsub_replacement on (bash >= 5.2) `&` in the replacement of `${v//pat/repl}` expands to the matched text,
# so `lib/a&b/x.sh` resolved to `lib/a$Pb/x.sh` and the edge was lost; the derive block switches the option off
# before its first call. Driven twice on one file: the second call replays the per-file memo, so a first call
# that resolved wrongly would be replayed wrongly too.
if (( _bash_52 == 1 )); then
  cases=$((cases + 1))
  printf 'P="lib/a&b/x.sh"\nbash "$P"\n' > "$FX/amp.sh"
  _r1="$(derive_run "$FX" '_affected_reset_edges; _affected_file_edges amp.sh; cold="${_AC_EDGES[*]-}"; _affected_reset_edges; _affected_file_edges amp.sh; printf "%s|%s" "$cold" "${_AC_EDGES[*]-}"' 2>&1)"
  if [[ "$_r1" == "^lib/a&b/x.sh|^lib/a&b/x.sh" ]]; then
    pass "R1: a captured value containing & resolves literally on the cold and the warm call"
  else
    fail "R1: got '${_r1:0:200}'"
  fi
else
  skip_or_fail "R1" "bash >= 5.2"
fi

# R3b (must-PASS): a long line with no self-reference still resolves to the exact expected edge (pass 2 resolves
# a WHOLE grep line, not a token).
cases=$((cases + 1))
_pad="$(head -c 5000 /dev/zero | tr '\0' 'a')"
printf 'LONG="lib/helper.sh"\nbash "$LONG" # %s\n' "$_pad" > "$FX/long.sh"
_r3b="$(derive_run "$FX" '_affected_reset_edges; _affected_file_edges long.sh; printf "%s" "${_AC_EDGES[*]-}"' 2>&1)"
if [[ "$_r3b" == "^lib/helper.sh" ]]; then
  pass "R3b: a 5000-byte line with no self-reference resolves to exactly ^lib/helper.sh"
else
  fail "R3b: edges='${_r3b:0:200}'"
fi

# R2/R3/R3c (A2): variable resolution is growth-bounded. `_affected_resolve_vars` re-loops so a value that carries
# another $VAR also resolves, capped at 12 passes; a self- or mutually-referential value tripled the string every
# pass (3^12 ~ 531k times), which is cost, not information. The bound is on GROWTH (input length + 4096 bytes), not on
# absolute length, because a legitimate line over 4096 bytes must still resolve (R3b). Driven through the function
# directly: `_vn`/`_vv` are the caller's dynamically-scoped variable map.
resolve_len() { # resolve_len <names (space)> <val-A> <val-B> <input> -> "<length>|<head 12 chars>"
  RV_NAMES="$1" RV_A="$2" RV_B="$3" RV_IN="$4" derive_run "$FX" 'f() { local -a _vn=($RV_NAMES) _vv=("$RV_A" "$RV_B"); _affected_resolve_vars "$RV_IN"; }; f; printf "%s|%s" "${#_RV}" "${_RV:0:12}"' 2>&1
}
cases=$((cases + 1))
_r2="$(resolve_len "A B" 'x$A$A$A' unused 'head/$A')"
if [[ "${_r2%%|*}" =~ ^[0-9]+$ ]] && (( ${_r2%%|*} < 30000 )) && [[ "${_r2#*|}" == head/x* ]]; then
  pass "R2: a self-referential value stops growing (length ${_r2%%|*} < 30000, head before the first expansion kept)"
else
  fail "R2: length/head '${_r2:0:80}'"
fi
cases=$((cases + 1))
_r3="$(resolve_len "A B" '$B$B$B' '$A$A$A' 'h/$A')"
if [[ "${_r3%%|*}" =~ ^[0-9]+$ ]] && (( ${_r3%%|*} < 30000 )) && [[ "${_r3#*|}" == h/* ]]; then
  pass "R3: a mutually referential pair stops growing (length ${_r3%%|*} < 30000)"
else
  fail "R3: length/head '${_r3:0:80}'"
fi
# Boundary: growth of exactly 4096 resolves the second variable, 4097 leaves it. Input `h/$A` is 5 bytes; value A is
# `$B-` plus padding (the `-` ends the variable name), so the first pass grows the string by len(A)-2.
boundary() { # boundary <padding length> -> RESOLVED | STOPPED | OTHER
  RVPAD="$(head -c "$1" /dev/zero | tr '\0' 'z')" derive_run "$FX" 'f() { local -a _vn=(A B) _vv=("\$B-$RVPAD" done); _affected_resolve_vars "$1"; }; f "h/\$A"; case "$_RV" in *done*) echo RESOLVED ;; *\$B*) echo STOPPED ;; *) echo OTHER ;; esac' 2>&1
}
cases=$((cases + 1))
_r3c1="$(boundary 4095)"   # len(A)=4098 -> growth 4096
if [[ "$_r3c1" == "RESOLVED" ]]; then pass "R3c: growth of exactly 4096 still resolves the second variable"; else fail "R3c(4096): '$_r3c1'"; fi
cases=$((cases + 1))
_r3c2="$(boundary 4096)"   # len(A)=4099 -> growth 4097
if [[ "$_r3c2" == "STOPPED" ]]; then pass "R3c: growth of 4097 stops before the second variable"; else fail "R3c(4097): '$_r3c2'"; fi
# R3d: the cap is BYTES whatever the caller's locale. `local LC_ALL=C _cap=$(( ${#1} + ... ))` expands `${#1}` before
# the assignment takes effect, so under a UTF-8 caller a multibyte input was measured in characters against a
# byte-counted loop test (cap 4099 for "é$A" where 4100 is right). Input `é$A` is 4 bytes; growth of exactly 4096
# bytes must still resolve the second variable.
_r3d_loc=""
for _l in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if [[ "$(LC_ALL=$_l bash -c 'printf %s "${#1}"' _ 'é' 2>/dev/null)" == "1" ]]; then _r3d_loc="$_l"; break; fi
done
if [[ -z "$_r3d_loc" ]]; then
  skip_or_fail "R3d" "a UTF-8 locale (C.UTF-8, en_US.UTF-8)"
else
  cases=$((cases + 1))
  _r3d="$(LC_ALL=$_r3d_loc derive_run "$FX" 'f() { local -a _vn=(A B) _vv=("\$B-$(head -c 4095 /dev/zero | tr "\0" z)" done); _affected_resolve_vars "$1"; }; f "é\$A"; case "$_RV" in *done*) echo RESOLVED ;; *\$B*) echo STOPPED ;; *) echo OTHER ;; esac' 2>&1)"
  if [[ "$_r3d" == "RESOLVED" ]]; then pass "R3d: the growth cap counts bytes under a UTF-8 caller locale ($_r3d_loc)"; else fail "R3d($_r3d_loc): '$_r3d'"; fi
fi

# R3e: resolution is a CHAIN. V1 -> V2 -> V3 resolves through three passes (each pass resolves one level, so a value that carries
# another $VAR also resolves). The 12-pass cap is a boundary the growth rows above cannot see: a 12-variable chain resolves
# completely, a 13-variable chain stops with its last reference left in place (`$V13`), which then dies at the caller's `-e` filter.
chain() { # chain <n>: V1='$V2' ... V<n>='done'; resolves '$V1' and prints the result
  # shellcheck disable=SC2016 # the snippet is eval'd by derive_run; its $ expansions must NOT expand here
  CH_N="$1" derive_run "$FX" 'f() { local -a _vn=() _vv=(); local _i; for (( _i=1; _i<CH_N; _i++ )); do _vn+=("V$_i"); _vv+=("\$V$(( _i + 1 ))"); done; _vn+=("V$CH_N"); _vv+=(done); _affected_resolve_vars "\$V1"; }; f; printf "%s" "$_RV"' 2>&1
}
cases=$((cases + 1))
_r3e3="$(chain 3)"; _r3e12="$(chain 12)"; _r3e13="$(chain 13)"
# shellcheck disable=SC2016 # the expected value is the literal text $V13
if [[ "$_r3e3" == "done" && "$_r3e12" == "done" && "$_r3e13" == '$V13' ]]; then
  pass "R3e: a 3-variable chain resolves in three passes; a 12-variable chain resolves; a 13-variable chain stops at the 12-pass cap with \$V13 left"
else
  fail "R3e: chain(3)='${_r3e3}' chain(12)='${_r3e12}' (want done) chain(13)='${_r3e13}' (want \$V13)"
fi

# R4 (A3a): the edge-membership set `_AC_ESET` agrees with the `_AC_EDGES` array at every site that assigns
# the array, and membership is an EXACT-entry test. The array is the ordered store `--print-selection` prints;
# the set only answers "already present?" in O(length) instead of a per-edge array scan. Sites: the derive
# entry, the classify entry, `_affected_resolve_edges` (which fills the array without add_edge) and an external
# `_affected_reset_edges`. Prefix collision: `^a/bc` present must not make `^a/b` look present. A name carrying
# a newline would forge two set entries, so it must not mint.
AGREE='chk() { local a s; a="$(printf "%s\n" ${_AC_EDGES[@]+"${_AC_EDGES[@]}"} | sed "/^$/d" | sort)"; s="$(printf "%s" "${_AC_ESET-}" | sed "/^$/d" | sort)"; if [[ "$a" == "$s" ]]; then echo "AGREE:$a"; else echo "DISAGREE a=[$a] s=[$s]"; fi; }'
cases=$((cases + 1))
_r4a="$(derive_run "$FX" "$AGREE"'; _AC_EDGES=(^stale); _AC_ESET=$'"'"'\n^stale\n'"'"'; _affected_derive lbl lib/helper.sh; chk' 2>&1)"
if [[ "$_r4a" == "AGREE:^lib/helper.sh" ]]; then pass "R4a: derive entry resets both stores; the set equals the array"; else fail "R4a: ${_r4a:0:200}"; fi
cases=$((cases + 1))
_r4b="$(derive_run "$FX" "$AGREE"'; _AC_EDGES=(^stale); _AC_ESET=$'"'"'\n^stale\n'"'"'; TEST_GROUP=group; _affected_classify lbl lib/helper.sh; chk' 2>&1)"
if [[ "$_r4b" == "AGREE:" ]]; then pass "R4b: classify entry resets both stores; both are empty"; else fail "R4b: ${_r4b:0:200}"; fi
cases=$((cases + 1))
_r4c="$(derive_run "$FX" "$AGREE"'; _AC_EDGES=(^stale); _AC_ESET=$'"'"'\n^stale\n'"'"'; ARR=(^a/bc ^lib/helper.sh); _affected_resolve_edges ARR; chk; _affected_add_edge a/b; chk' 2>&1)"
if [[ "$_r4c" == "AGREE:^a/bc"$'\n'"^lib/helper.sh"$'\n'"AGREE:^a/b"$'\n'"^a/bc"$'\n'"^lib/helper.sh" ]]; then
  pass "R4c: resolve_edges rebuilds the set from the loaded members, and ^a/b mints beside ^a/bc (no prefix collision)"
else
  fail "R4c: ${_r4c:0:300}"
fi
cases=$((cases + 1))
_r4d="$(derive_run "$FX" "$AGREE"'; _affected_add_edge a/b; _affected_add_edge a/bc; _affected_reset_edges; chk; _affected_add_edge a/b; chk' 2>&1)"
if [[ "$_r4d" == "AGREE:"$'\n'"AGREE:^a/b" ]]; then pass "R4d: an external _affected_reset_edges empties both stores and a re-add mints again"; else fail "R4d: ${_r4d:0:300}"; fi
cases=$((cases + 1))
_r4e="$(derive_run "$FX" "$AGREE"'; _affected_reset_edges; _affected_add_edge "$(printf "nl\ny")"; _affected_add_edge a/b; chk' 2>&1)"
if [[ "$_r4e" == "AGREE:^a/b" ]]; then pass "R4e: a name carrying a newline does not mint (it would forge two set entries)"; else fail "R4e: ${_r4e:0:300}"; fi

cases=$((cases + 1))
_r4f="$(derive_run "$FX" "$AGREE"'; _affected_reset_edges; _affected_add_edge lib/helper.sh; _affected_add_edge lib/helper.sh; chk' 2>&1)"
if [[ "$_r4f" == "AGREE:^lib/helper.sh" ]]; then pass "R4f: the same edge offered twice is minted once (the membership test is what dedups)"; else fail "R4f: ${_r4f:0:300}"; fi
# `..` is a suffix of nothing and `.` is a suffix of `..`: a membership string bracketed on the right only treats `.` as present.
cases=$((cases + 1))
_r4g="$(derive_run "$FX" "$AGREE"'; _affected_reset_edges; _affected_add_edge ..; _affected_add_edge .; chk' 2>&1)"
if [[ "$_r4g" == "AGREE:."$'\n'".." ]]; then pass "R4g: '.' mints beside '..' (the membership string is bracketed on BOTH sides)"; else fail "R4g: ${_r4g:0:300}"; fi
# The eval operand is validated: a non-identifier name returns without evaluating it and without touching the edges.
cases=$((cases + 1))
_r4h="$(derive_run "$FX" "$AGREE"'; _AC_EDGES=(^keep); _AC_ESET=$'"'"'\n^keep\n'"'"'; _affected_resolve_edges "FOO; touch $PWD/sentinel-injected"; if [[ -e sentinel-injected ]]; then echo INJECTED; else echo NOSENT; fi; chk' 2>&1)"
if [[ "$_r4h" == "NOSENT"$'\n'"AGREE:^keep" ]]; then pass "R4h: a non-identifier array name is refused before eval (nothing runs, edges untouched)"; else fail "R4h: ${_r4h:0:300}"; fi
# Tripwire: only three places may assign the array (init, reset, the eval in resolve_edges); a fourth is a site R4a-d do not cover.
cases=$((cases + 1))
_r4i="$(grep -vE '^[[:space:]]*#' "$DERIVE_SRC" | grep -c '_AC_EDGES=(' || true)"
if [[ "$_r4i" == "3" ]]; then pass "R4i: exactly three sites assign _AC_EDGES (init, reset, resolve_edges)"; else fail "R4i: $_r4i assignment sites in the derive block"; fi

# ---- the bench: compare logic and dispatch ----------------------------------------------------------
# A stream is N AFFECTED_SELECTED rows (label, bit, class, edges) and a summary whose of= is N.
mk_stream() { # mk_stream <out> <n> [extra-label]
  local out="$1" n="$2" extra="${3-}" i total="$2"
  assert_fixture_dir "$out"
  : > "$out"
  for (( i=1; i<=n; i++ )); do
    printf 'AFFECTED_SELECTED\tsuite/%03d\t1\tedge:derived\t^lib/e%03d.sh|^lib/f%03d.sh\n' "$i" "$i" "$i" >> "$out"
  done
  if [[ -n "$extra" ]]; then
    printf 'AFFECTED_SELECTED\t%s\t1\talways_on\t\n' "$extra" >> "$out"
    total=$((n + 1))
    printf 'AFFECTED_SUMMARY selected=%d of=%d always_on=1 edge=%d fallback=none\n' "$total" "$total" "$n" >> "$out"
  else
    printf 'AFFECTED_SUMMARY selected=%d of=%d always_on=0 edge=%d fallback=none\n' "$n" "$n" "$n" >> "$out"
  fi
}
mk_enum() { # mk_enum <out> <n> [extra-label]: the --enumerate-commands label list for a stream of n rows
  local out="$1" n="$2" extra="${3-}" i
  assert_fixture_dir "$out"
  : > "$out"
  for (( i=1; i<=n; i++ )); do printf 'SUITE_COMMAND\tsuite/%03d\tbash\tx.sh\n' "$i" >> "$out"; done
  [[ -z "$extra" ]] || printf 'SUITE_COMMAND\t%s\tbash\ty.sh\n' "$extra" >> "$out"
}
mk_runner() { # mk_runner <path> <selection> <enum> [pre-command]
  cat > "$1" <<EOF
#!/usr/bin/env bash
${4-}
case "\$*" in
  *--enumerate-commands*) cat "$3" ;;
  *--print-selection*) cat "$2" ;;
esac
EOF
}
bench() { ( cd "$REPO_ROOT" && bash "$BENCH" "$@" ) 2>&1; }

B="$TESTROOT/bench"; mkdir -p "$B"; assert_fixture_dir "$B"
mk_stream "$B/sel.base" 534
mk_enum "$B/enum.base" 534

# Compare-only rows: identical, then one defect class per row.
cases=$((cases + 1))
_o="$(bench --compare-only "$B/sel.base" "$B/sel.base")"; _rc=$?
if [[ "$_rc" == "0" && "$_o" == IDENTICAL:* ]]; then pass "R7a: --compare-only of a stream with itself is identical (rc 0)"; else fail "R7a: rc=$_rc $_o"; fi

cases=$((cases + 1))
python3 - "$B/sel.base" "$B/sel.onebyte" <<'PY'
import sys
lines = open(sys.argv[1], "rb").read().split(b"\n")
# the LAST of the 534 rows: change one byte in its edge list
i = max(k for k, l in enumerate(lines) if l.startswith(b"AFFECTED_SELECTED"))
lines[i] = lines[i][:-1] + b"X"
open(sys.argv[2], "wb").write(b"\n".join(lines))
PY
_o="$(bench --compare-only "$B/sel.base" "$B/sel.onebyte")"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"differ byte-for-byte"* ]]; then pass "R7b: a one-byte difference in the last of 534 rows is caught (rc 1)"; else fail "R7b: rc=$_rc $_o"; fi

cases=$((cases + 1))
python3 - "$B/sel.base" "$B/sel.reordered" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
i = next(k for k, l in enumerate(lines) if l.startswith("AFFECTED_SELECTED"))
f = lines[i].split("\t")
f[4] = "|".join(reversed(f[4].split("|")))
lines[i] = "\t".join(f)
open(sys.argv[2], "w").write("\n".join(lines))
PY
_o="$(bench --compare-only "$B/sel.base" "$B/sel.reordered")"; _rc=$?
if [[ "$_rc" == "1" ]]; then pass "R7c: edges reordered inside a row are a difference (rc 1)"; else fail "R7c: rc=$_rc $_o"; fi

cases=$((cases + 1))
: > "$B/sel.empty"
_o="$(bench --compare-only "$B/sel.empty" "$B/sel.empty")"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"zero rows"* ]]; then pass "R7d: two empty streams do not read as identical (rc 1)"; else fail "R7d: rc=$_rc $_o"; fi

cases=$((cases + 1))
grep -v '^AFFECTED_SUMMARY' "$B/sel.base" > "$B/sel.crash"
_o="$(bench --compare-only "$B/sel.base" "$B/sel.crash")"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"no AFFECTED_SUMMARY"* ]]; then pass "R7e: a head stream cut off before its summary is a difference (rc 1)"; else fail "R7e: rc=$_rc $_o"; fi

cases=$((cases + 1))
sed 's/^\(AFFECTED_SUMMARY .* of=\)534/\1533/' "$B/sel.base" > "$B/sel.badof"
_o="$(bench --compare-only "$B/sel.base" "$B/sel.badof")"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"of=533"* ]]; then pass "R7f: a summary of= that disagrees with the row count is a difference (rc 1)"; else fail "R7f: rc=$_rc $_o"; fi

# An added registration is legitimate only when declared: rc 0 with --added, rc 1 without.
cases=$((cases + 1))
mk_stream "$B/sel.plus" 534 suite/new
_o1="$(bench --compare-only "$B/sel.base" "$B/sel.plus" --added suite/new)"; _rc1=$?
_o2="$(bench --compare-only "$B/sel.base" "$B/sel.plus")"; _rc2=$?
if [[ "$_rc1" == "0" && "$_rc2" == "1" ]]; then pass "R7g: an added suite row passes only when declared (rc 0 declared, rc 1 undeclared)"; else fail "R7g: declared rc=$_rc1 ($_o1); undeclared rc=$_rc2 ($_o2)"; fi

# An edge that exists only because the change ADDED a file (the runner's text now names the new suite file, so
# every suite whose closure reaches the runner gains it) is allowed only when declared with --added-edges.
cases=$((cases + 1))
python3 - "$B/sel.base" "$B/sel.addedge" <<'PY2'
import sys
lines = open(sys.argv[1]).read().split("\n")
i = next(k for k, l in enumerate(lines) if l.startswith("AFFECTED_SELECTED"))
f = lines[i].split("\t"); f[4] = f[4] + "|^scripts/newfile.sh"; lines[i] = "\t".join(f)
open(sys.argv[2], "w").write("\n".join(lines))
PY2
_o1="$(bench --compare-only "$B/sel.base" "$B/sel.addedge" --added-edges scripts/newfile.sh)"; _rc1=$?
_o2="$(bench --compare-only "$B/sel.base" "$B/sel.addedge")"; _rc2=$?
_o3="$(bench --compare-only "$B/sel.base" "$B/sel.addedge" --added-edges scripts/other.sh)"; _rc3=$?
if [[ "$_rc1" == "0" && "$_rc2" == "1" && "$_rc3" == "1" ]]; then pass "R7p: an added-file edge passes only when that exact path is declared (rc 0 declared; rc 1 undeclared or a different path)"; else fail "R7p: declared=$_rc1 undeclared=$_rc2 other=$_rc3 ($_o1 / $_o2)"; fi

# A dropped base row, with a plausible summary, is still caught.
cases=$((cases + 1))
python3 - "$B/sel.base" "$B/sel.dropped" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
i = next(k for k, l in enumerate(lines) if l.startswith("AFFECTED_SELECTED"))
del lines[i]
lines = [l.replace("of=534", "of=533").replace("selected=534", "selected=533").replace("edge=534", "edge=533") for l in lines]
open(sys.argv[2], "w").write("\n".join(lines))
PY
_o="$(bench --compare-only "$B/sel.base" "$B/sel.dropped")"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"drops 1 base row"* ]]; then pass "R7h: a dropped base row is caught even when the summary is rewritten to match (rc 1)"; else fail "R7h: rc=$_rc $_o"; fi

# Dispatch rows: the full path (worktree-free, via --base-runner/--head-runner) with fake runners.
mk_runner "$B/run.base" "$B/sel.base" "$B/enum.base"
cp "$B/run.base" "$B/run.same"

cases=$((cases + 1))
_o="$(bench --base-runner "$B/run.base" --head-runner "$B/run.same" --probe README.md --runs 1)"; _rc=$?
# The runner path is part of the side identity, so two different paths with the same bytes are a comparison;
# the same PATH twice is the exit-3 row below.
if [[ "$_rc" == "0" && "$_o" == *"IDENTICAL: 534"* ]]; then
  pass "R7i: a pristine fake runner pair is identical through the full dispatch path (rc 0)"
else
  fail "R7i: rc=$_rc ${_o:0:400}"
fi

cases=$((cases + 1))
python3 - "$B/sel.base" "$B/sel.edgedrop" <<'PY'
import sys
lines = open(sys.argv[1]).read().split("\n")
i = next(k for k, l in enumerate(lines) if l.startswith("AFFECTED_SELECTED"))
f = lines[i].split("\t"); f[4] = f[4].split("|")[0]; lines[i] = "\t".join(f)
open(sys.argv[2], "w").write("\n".join(lines))
PY
mk_runner "$B/run.edgedrop" "$B/sel.edgedrop" "$B/enum.base"
_o="$(bench --base-runner "$B/run.base" --head-runner "$B/run.edgedrop" --probe README.md --runs 1)"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"DIFFERS"* ]]; then pass "R7j: a pair with one edge dropped is a difference through the full path (rc 1)"; else fail "R7j: rc=$_rc ${_o:0:300}"; fi

cases=$((cases + 1))
_o="$(bench --base-runner "$B/run.base" --head-runner "$B/run.base" --probe README.md --runs 1)"; _rc=$?
if [[ "$_rc" == "3" ]]; then pass "R7k: the same runner path on both sides exits 3 (nothing to compare)"; else fail "R7k: rc=$_rc ${_o:0:200}"; fi

cases=$((cases + 1))
mk_stream "$B/sel.plus2" 534 suite/new
mk_enum "$B/enum.plus2" 534 suite/new
mk_runner "$B/run.plus" "$B/sel.plus2" "$B/enum.plus2"
_o="$(bench --base-runner "$B/run.base" --head-runner "$B/run.plus" --probe README.md --runs 1)"; _rc=$?
if [[ "$_rc" == "0" && "$_o" == *"1 added row"* ]]; then pass "R7l: a pair differing by exactly one added registration is identical, the label derived from the enumerations (rc 0)"; else fail "R7l: rc=$_rc ${_o:0:400}"; fi

cases=$((cases + 1))
mk_runner "$B/run.stderr" "$B/sel.base" "$B/enum.base" 'echo "noise on stderr only" >&2'
_o="$(bench --base-runner "$B/run.base" --head-runner "$B/run.stderr" --probe README.md --runs 1)"; _rc=$?
if [[ "$_rc" == "0" ]]; then pass "R7m: a difference in stderr alone is not a selection difference (rc 0)"; else fail "R7m: rc=$_rc ${_o:0:300}"; fi

cases=$((cases + 1))
mk_runner "$B/run.ci" "$B/sel.base" "$B/enum.base" '[[ -z "${CI:-}${SOLEUR_TEST_FORCE_ALL:-}" ]] || { echo "AFFECTED_SELECTED	poisoned	1	always_on	"; exit 0; }'
_o="$( cd "$REPO_ROOT" && CI=1 SOLEUR_TEST_FORCE_ALL=1 bash "$BENCH" --base-runner "$B/run.base" --head-runner "$B/run.ci" --probe README.md --runs 1 2>&1 )"; _rc=$?
if [[ "$_rc" == "0" ]]; then pass "R7n: the child runs without CI or SOLEUR_TEST_FORCE_ALL even when the bench shell has them (rc 0)"; else fail "R7n: rc=$_rc ${_o:0:300}"; fi

cases=$((cases + 1))
mk_runner "$B/run.crash" "$B/sel.base" "$B/enum.base" 'case "$*" in *--print-selection*) exit 7 ;; esac'
_o="$(bench --base-runner "$B/run.base" --head-runner "$B/run.crash" --probe README.md --runs 1)"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"exited rc=7"* ]]; then pass "R7o: a side that exits non-zero is a failure, not an agreement (rc 1)"; else fail "R7o: rc=$_rc ${_o:0:300}"; fi

# ---- the comparator, quantified over position, column and order (a one-row sample cannot tell a full compare from a partial one)
mutate() { # mutate <kind> <row index> <in> <out>
  python3 - "$@" <<'PY2'
import sys
kind, idx, src, dst = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
lines = open(src).read().split("\n")
rows = [k for k, l in enumerate(lines) if l.startswith("AFFECTED_SELECTED")]
k = rows[idx]
f = lines[k].split("\t")
if kind == "edge": f[4] = f[4] + "x"
elif kind == "class": f[3] = "always_on"
elif kind == "bit": f[2] = "0"
elif kind == "swap":
    lines[k], lines[rows[idx + 1]] = lines[rows[idx + 1]], lines[k]
    open(dst, "w").write("\n".join(lines)); sys.exit(0)
lines[k] = "\t".join(f)
open(dst, "w").write("\n".join(lines))
PY2
}
cases=$((cases + 1))
_miss=""
for _pos in 0 266 532; do
  for _kind in edge class bit swap; do
    mutate "$_kind" "$_pos" "$B/sel.base" "$B/sel.mut"
    bench --compare-only "$B/sel.base" "$B/sel.mut" >/dev/null; _rc=$?
    [[ "$_rc" == "1" ]] || _miss+=" ${_kind}@${_pos}(rc=$_rc)"
  done
done
if [[ -z "$_miss" ]]; then pass "R7q: an edge, class, bit or order change in the first, a middle or the last row is a difference (12 of 12 rc 1)"; else fail "R7q: undetected:$_miss"; fi

cases=$((cases + 1))
sed 's/^\(AFFECTED_SUMMARY .*\)edge=534/\1edge=533/' "$B/sel.base" > "$B/sel.badsum"
_o="$(bench --compare-only "$B/sel.base" "$B/sel.badsum")"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"head summary"* ]]; then pass "R7r: a summary that disagrees with its own intact rows is a difference (rc 1)"; else fail "R7r: rc=$_rc $_o"; fi

cases=$((cases + 1))
sed 's/fallback=none/fallback=index-missing/' "$B/sel.base" > "$B/sel.degraded"
_o="$(bench --compare-only "$B/sel.base" "$B/sel.degraded")"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"degraded run"* ]]; then pass "R7s: a degraded head run (fallback != none) is a difference (rc 1)"; else fail "R7s: rc=$_rc $_o"; fi

cases=$((cases + 1))
_o="$(bench --compare-only "$B/sel.base" "$B/sel.plus" --added suite/other)"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"head adds labels"* ]]; then pass "R7t: a declared label that is not the one the head added is a difference (rc 1)"; else fail "R7t: rc=$_rc $_o"; fi

# Dispatch: a head runner that answers differently on its second call (determinism), and a base whose summary
# disagrees with its own enumeration.
cases=$((cases + 1))
cat > "$B/run.flaky" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *--enumerate-commands*) cat "$B/enum.base" ;;
  *--print-selection*)
    n=\$(cat "$B/flaky.count" 2>/dev/null || echo 0); echo \$((n + 1)) > "$B/flaky.count"
    if (( n == 0 )); then cat "$B/sel.base"; else cat "$B/sel.edgedrop"; fi ;;
esac
EOF
rm -f "$B/flaky.count"
_o="$(bench --base-runner "$B/run.base" --head-runner "$B/run.flaky" --probe README.md --runs 2)"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"non-deterministic"* ]]; then pass "R7u: a head run that differs from its own first run is a difference (rc 1)"; else fail "R7u: rc=$_rc ${_o:0:300}"; fi

cases=$((cases + 1))
python3 - "$B/enum.base" "$B/enum.short" <<'PY2'
import sys
lines = open(sys.argv[1]).read().split("\n")
open(sys.argv[2], "w").write("\n".join(lines[1:]))
PY2
mk_runner "$B/run.shortenum" "$B/sel.base" "$B/enum.short"
_o="$(bench --base-runner "$B/run.shortenum" --head-runner "$B/run.base" --probe README.md --runs 1)"; _rc=$?
if [[ "$_rc" == "1" && "$_o" == *"base summary of=534 but"* ]]; then pass "R7v: a base whose summary of= disagrees with its enumeration is a difference (rc 1)"; else fail "R7v: rc=$_rc ${_o:0:300}"; fi

# ---- D3: runner SUBCOMMANDS are not operands (#9307, ADR-242 decision 17) ----------------------------------
# The word `test` after a runner word resolves to the repo-root test/ directory and mints an edge that
# selects every suite carrying it for any diff under test/. Each form below is driven as a registration argv
# AND as a `bash -c` payload (the payload loop has its own word walk). The control rows prove the skip is
# narrow: `test` after a word that is NOT a runner still mints, so a skip that swallowed every `test` fails.
FX3="$TESTROOT/fx-d3"
mkdir -p "$FX3/test" "$FX3/app"
: > "$FX3/test/x.ts"
assert_fixture_dir "$FX3"
d3_edges() { # d3_edges <derive argv...> -> the edge array, space-joined
  D3_ARGV="$*" derive_run "$FX3" 'eval "set -- $D3_ARGV"; _affected_derive lbl "$@"; printf "%s" "${_AC_EDGES[*]-}"' 2>&1
}
# The forms are READ from the runner's own case labels in `_affected_runner_subcmd`, so a label added there is driven here
# with no edit to this file. `run test` stands for npm|bun|pnpm|yarn run test (its previous word is `run`), so it is driven
# through those four wrappers. The expected count of driven forms comes from a SECOND parse of the same case line (its `|`
# separators counted, not its quoted strings matched), never from the loop under test.
_d3_body="$(awk '/^_affected_runner_subcmd\(\)/ {s=1} s {print} s && /^\}/ {exit}' "$RUNNER")"
_d3_labels="$(printf '%s\n' "$_d3_body" | grep -o '"[a-z]* [a-z]*"' | tr -d '"')"
_d3_alts="$(printf '%s\n' "$_d3_body" | awk '/^[[:space:]]*"[a-z]+ [a-z]+"\|/ {n += gsub(/\|/, "|") + 1} END {print n + 0}')"
_d3_forms=(); _d3_nrun=0
while IFS= read -r _lbl; do
  [[ -n "$_lbl" ]] || continue
  case "$_lbl" in
    "run "*) _d3_nrun=$((_d3_nrun + 1)); for _w in npm bun pnpm yarn; do _d3_forms+=("$_w $_lbl"); done ;;
    *) _d3_forms+=("$_lbl") ;;
  esac
done <<< "$_d3_labels"
_d3_n=0
for _form in "${_d3_forms[@]}"; do
  _d3_n=$((_d3_n + 1))
  cases=$((cases + 1))
  # shellcheck disable=SC2086 # the form string is argv words by design: it must split
  _argv_out="$(d3_edges $_form app)"
  if [[ " $_argv_out " != *" ^test/ "* ]]; then
    pass "D3[$_form]: argv form mints no ^test/ edge"
  else
    fail "D3[$_form]: argv form minted ^test/ — '${_argv_out:0:160}'"
  fi
  cases=$((cases + 1))
  _pay_out="$(d3_edges "bash -c 'cd app && $_form'")"
  if [[ " $_pay_out " == *" ^app/ "* && " $_pay_out " != *" ^test/ "* ]]; then
    pass "D3[$_form]: -c payload form mints the cd target (^app/) and no ^test/ edge"
  else
    fail "D3[$_form]: -c payload edges '${_pay_out:0:160}' (want ^app/ and no ^test/)"
  fi
done
cases=$((cases + 1))
if (( _d3_alts >= 1 && _d3_nrun >= 1 && _d3_n == _d3_alts + 3 * _d3_nrun )); then
  pass "D3 floor: every case alternative of _affected_runner_subcmd is driven ($_d3_n forms = $_d3_alts alternatives + 3 extra wrappers for each of $_d3_nrun run-test label)"
else
  fail "D3 floor: drove $_d3_n forms; the case line has $_d3_alts alternatives of which $_d3_nrun are run-test (want alternatives + 3 per run-test label)"
fi
cases=$((cases + 1))
_ctl_argv="$(d3_edges cp test)"
if [[ " $_ctl_argv " == *" ^test/ "* ]]; then pass "D3 control: 'test' after a non-runner word still mints ^test/ (the skip is narrow)"; else fail "D3 control: argv got '${_ctl_argv:0:160}'"; fi
cases=$((cases + 1))
_ctl_pay="$(d3_edges "bash -c 'cd app && cp test'")"
if [[ " $_ctl_pay " == *" ^test/ "* ]]; then pass "D3 control: payload 'cp test' still mints ^test/"; else fail "D3 control: payload got '${_ctl_pay:0:160}'"; fi

# ---- A5: the runner and its index are closure LEAVES for text mentions (#9307, ADR-242 decision 18) -------
# A leaf file keeps its real `source`/import edges (pass 1) and loses the edges its text merely NAMES (pass 2
# invocation tokens, pass 3 `$VAR/path` tokens): the runner names ~475 files in its own text and every
# suite that reaches it inherited all of them. The leaf set is ONE array (CLOSURE_LEAF_FILES) so the rule
# has one site; a derive row pins that the two literals the `runner-changed` fallback greps equal it. The
# `$(dirname "${BASH_SOURCE[0]}")` resolve of a whole line is NOT part of the leaf rule: every file gets it
# (rows A5-dirname below), so the lib a hook sources through `_X="$(dirname ...)/lib/x.sh"; source "$_X"` is an edge
# whether or not the hook is a leaf.
FX5="$TESTROOT/fx-leaf"
mkdir -p "$FX5/lib" "$FX5/app"
: > "$FX5/lib/helper.sh"; : > "$FX5/lib/other.sh"; : > "$FX5/lib/third.sh"; : > "$FX5/lib/viavar.sh"; : > "$FX5/lib/viadir.sh"
# shellcheck disable=SC2016 # the fixture text carries literal $ expansions that must NOT expand here
printf 'D="lib"\nV="lib/viavar.sh"\nW="$(dirname "${BASH_SOURCE[0]}")/../lib/viadir.sh"\nsource lib/helper.sh\nsource "$V"\nsource "$W"\nbash lib/other.sh\necho "$D/third.sh"\n' > "$FX5/app/leaf.sh"
cp "$FX5/app/leaf.sh" "$FX5/app/notleaf.sh"
# near-miss names: a leaf match is the EXACT path (after one leading ./), not a suffix or a prefix of it
mkdir -p "$FX5/xapp"
cp "$FX5/app/leaf.sh" "$FX5/xapp/leaf.sh"
cp "$FX5/app/leaf.sh" "$FX5/app/leaf.sh.bak"
# the hook shape from the repo (.claude/hooks/agent-token-tee.sh): the lib path sits in a variable whose value carries a space
# shellcheck disable=SC2016 # literal $ expansions in fixture text
printf '_inc="$(dirname "${BASH_SOURCE[0]}")/../lib/viadir.sh"\nif [[ -f "$_inc" ]]; then\n  source "$_inc" 2>/dev/null || true\nfi\n_rot="$(dirname "$0")/../lib/helper.sh"\nsource "$_rot"\nbash lib/other.sh\n' > "$FX5/app/hook.sh"
# shellcheck disable=SC2016 # literal $ expansions in fixture text
printf 'W0="$(dirname "$0")/../lib/viadir.sh"\nsource "$W0"\nbash lib/other.sh\n' > "$FX5/app/leaf0.sh"
printf 'bash app/leaf.sh\n' > "$FX5/suite.sh"
assert_fixture_dir "$FX5"
leaf_edges() { # leaf_edges <leaf array body> <snippet tail> -> sorted edges, space-joined
  LEAF_BODY="$1" TAIL="$2" derive_run "$FX5" 'eval "CLOSURE_LEAF_FILES=($LEAF_BODY)"; _affected_reset_edges; eval "$TAIL"; printf "%s" "$(printf "%s\n" ${_AC_EDGES[@]+"${_AC_EDGES[@]}"} | LC_ALL=C sort | tr "\n" " ")"' 2>&1
}
cases=$((cases + 1))
_a1="$(leaf_edges '' '_affected_file_edges app/leaf.sh')"
if [[ "$_a1" == "^lib/helper.sh ^lib/other.sh ^lib/third.sh ^lib/viadir.sh ^lib/viavar.sh " ]]; then
  pass "A5 control: with no leaf set the file's source, invocation, \$VAR/path and dirname-variable edges are all minted (the fixture exercises passes 1 to 3)"
else
  fail "A5 control: edges '${_a1:0:160}' (want ^lib/helper.sh ^lib/other.sh ^lib/third.sh ^lib/viadir.sh ^lib/viavar.sh)"
fi
cases=$((cases + 1))
_a2="$(leaf_edges 'app/leaf.sh' '_affected_file_edges app/leaf.sh')"
if [[ "$_a2" == "^lib/helper.sh ^lib/viadir.sh ^lib/viavar.sh " ]]; then
  pass "A5: a leaf file keeps its real source edges (literal and through a variable) and loses the invocation and \$VAR/path edges it merely names"
else
  fail "A5: leaf edges '${_a2:0:160}' (want exactly ^lib/helper.sh ^lib/viadir.sh ^lib/viavar.sh)"
fi
cases=$((cases + 1))
_a3="$(leaf_edges 'app/leaf.sh' '_affected_file_edges ./app/leaf.sh')"
if [[ "$_a3" == "^lib/helper.sh ^lib/viadir.sh ^lib/viavar.sh " ]]; then
  pass "A5: the ./-rooted spelling of a leaf matches the leaf set (the leading ./ is stripped before comparing)"
else
  fail "A5: ./leaf.sh edges '${_a3:0:160}' (want exactly ^lib/helper.sh ^lib/viadir.sh ^lib/viavar.sh)"
fi
cases=$((cases + 1))
_a4="$(leaf_edges 'app/leaf.sh' '_affected_file_edges app/notleaf.sh')"
if [[ "$_a4" == "^lib/helper.sh ^lib/other.sh ^lib/third.sh ^lib/viadir.sh ^lib/viavar.sh " ]]; then
  pass "A5: the rule is per file; a non-leaf with identical text keeps every edge, the dirname-variable lib included"
else
  fail "A5: non-leaf edges '${_a4:0:160}' (want ^lib/helper.sh ^lib/other.sh ^lib/third.sh ^lib/viadir.sh ^lib/viavar.sh)"
fi
# Near-miss names are NOT leaves: the leaf test is an exact path comparison, so neither a longer directory name nor a
# longer file name may inherit the narrowing (a substring or suffix match would narrow files nobody declared).
cases=$((cases + 1))
_a4b="$(leaf_edges 'app/leaf.sh' '_affected_file_edges xapp/leaf.sh')"
_a4c="$(leaf_edges 'app/leaf.sh' '_affected_file_edges app/leaf.sh.bak')"
_a4_all="^lib/helper.sh ^lib/other.sh ^lib/third.sh ^lib/viadir.sh ^lib/viavar.sh "
if [[ "$_a4b" == "$_a4_all" && "$_a4c" == "$_a4_all" ]]; then
  pass "A5: xapp/leaf.sh and app/leaf.sh.bak are not leaves (a leaf is an exact path, not a suffix or prefix match)"
else
  fail "A5 near-miss: xapp/leaf.sh='${_a4b:0:120}' app/leaf.sh.bak='${_a4c:0:120}' (want every edge: ${_a4_all})"
fi
# A5-dirname: the whole-line `$(dirname ...)` resolve applies to EVERY file. `_inc="$(dirname "${BASH_SOURCE[0]}")/../lib/x.sh"`
# keeps a space in its value, so a split cut it in two and `source "$_inc"` never became an edge; 11 tracked hooks use the idiom
# (.claude/hooks/agent-token-tee.sh, pre-merge-rebase.sh, memory-backstop.sh, ...). Gating the resolve on the leaf set fixed two
# files and pinned the rest as losing it.
cases=$((cases + 1))
_a4d="$(leaf_edges '' '_affected_file_edges app/hook.sh')"
if [[ "$_a4d" == "^lib/helper.sh ^lib/other.sh ^lib/viadir.sh " ]]; then
  pass "A5-dirname: a NON-leaf hook keeps the lib it sources through a dirname variable (\$(dirname \"\${BASH_SOURCE[0]}\") and \$(dirname \"\$0\"))"
else
  fail "A5-dirname: non-leaf hook edges '${_a4d:0:160}' (want ^lib/helper.sh ^lib/other.sh ^lib/viadir.sh)"
fi
cases=$((cases + 1))
_a4e="$(leaf_edges 'app/leaf0.sh' '_affected_file_edges app/leaf0.sh')"
_a4f="$(leaf_edges '' '_affected_file_edges app/leaf0.sh')"
if [[ "$_a4e" == "^lib/viadir.sh " && "$_a4f" == "^lib/other.sh ^lib/viadir.sh " ]]; then
  pass "A5-dirname: the \$0 spelling resolves for a leaf (keeps only the sourced lib) and for a non-leaf (keeps both edges)"
else
  fail "A5-dirname \$0: leaf='${_a4e:0:120}' (want ^lib/viadir.sh) non-leaf='${_a4f:0:120}' (want ^lib/other.sh ^lib/viadir.sh)"
fi
cases=$((cases + 1))
_a5="$(leaf_edges 'app/leaf.sh' '_affected_derive lbl suite.sh')"
if [[ " $_a5" == *" ^app/leaf.sh "* && " $_a5" == *" ^lib/helper.sh "* && " $_a5" == *" ^lib/viavar.sh "* && " $_a5" == *" ^lib/viadir.sh "* && " $_a5" != *" ^lib/other.sh "* && " $_a5" != *" ^lib/third.sh "* ]]; then
  pass "A5: a suite reaching a leaf keeps the leaf itself and its real source closure, and none of the leaf's named files"
else
  fail "A5: closure edges '${_a5:0:200}'"
fi
cases=$((cases + 1))
_leaf_lib="$(cd "$REPO_ROOT" && bash -c 'source scripts/lib/test-affected-paths.sh 2>/dev/null; printf "%s\n" ${CLOSURE_LEAF_FILES[@]+"${CLOSURE_LEAF_FILES[@]}"}' | LC_ALL=C sort | tr '\n' ' ')"
if [[ "$_leaf_lib" == "scripts/lib/test-affected-paths.sh scripts/test-all.sh " ]]; then
  pass "A5: CLOSURE_LEAF_FILES lists exactly the runner and its index (not the relevance lib)"
else
  fail "A5: CLOSURE_LEAF_FILES is '${_leaf_lib}'"
fi
cases=$((cases + 1))
# The runner-changed fallback names the same two files by literal; they are coupled by name only, so the
# equality is pinned here. Extract the literals from the `_aff_runner_in_diff` block by content anchor.
_fb_lits="$(awk '/_aff_runner_in_diff=0/ {s=1} s && /grep -qF/ {print} s && /_aff_runner_in_diff=1/ {exit}' "$RUNNER" | grep -oE "grep -qF '[^']+'" | sed -E "s/grep -qF '([^']+)'/\1/" | LC_ALL=C sort | tr '\n' ' ')"
if [[ "$_fb_lits" == "$_leaf_lib" && -n "$_fb_lits" ]]; then
  pass "A5: the two literals the runner-changed fallback greps equal CLOSURE_LEAF_FILES"
else
  fail "A5: fallback literals '${_fb_lits}' vs leaf set '${_leaf_lib}'"
fi

# The bench walker RESTATES three runner constants (it is a second implementation, so it cannot import them). Each pair is
# read from its own text and pinned equal: a drift would make the oracle certify a closure the runner does not walk.
cases=$((cases + 1))
_pd_bench="$(sed -n 's/^MAXDEPTH = \([0-9][0-9]*\)$/\1/p' "$BENCH")"
_pd_run_n="$(grep -cE '_depth < [0-9]+' "$RUNNER")"
_pd_run="$(grep -oE '_depth < [0-9]+' "$RUNNER" | head -1 | sed 's/_depth < //')"
if [[ "$_pd_bench" =~ ^[0-9]+$ && "$_pd_run_n" == "1" && "$_pd_bench" == "$_pd_run" ]]; then
  pass "A5 parity: the bench walker's MAXDEPTH ($_pd_bench) equals the runner's closure depth bound (_depth < $_pd_run)"
else
  fail "A5 parity: bench MAXDEPTH='${_pd_bench}' runner '_depth < N' sites=${_pd_run_n} value='${_pd_run}'"
fi
cases=$((cases + 1))
_pw_run="$(sed -n "s/^.*_inv_words='\([^']*\)'.*/\1/p" "$RUNNER" | tr '\n' '@')"
_pw_bench="$(sed -nE "s/^.*words = r'([^']*)' if leaf else r'([^']*)'.*/\2@\1@/p" "$BENCH")"
if [[ -n "$_pw_run" && "$_pw_run" == "$_pw_bench" ]]; then
  pass "A5 parity: the bench walker's invocation words (full and leaf) equal the runner's _inv_words ($_pw_run)"
else
  fail "A5 parity: runner _inv_words='${_pw_run}' bench words='${_pw_bench}'"
fi

# ---- D1: `$(cd "<dir>[/..]" && pwd)` resolves to its cd TARGET (#9307, ADR-242 decision 18) --------------------
# The greedy `$(cd*pwd)` replacement collapsed the whole substitution to the file's own directory, so a
# `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"` file looked for `$REPO_ROOT/lib/x.sh` one
# or two levels below the repo root and dropped the edge. Each row drives one idiom through the file-edge walk.
FX6="$TESTROOT/fx-d1"
mkdir -p "$FX6/lib" "$FX6/app/deep" "$FX6/other"
: > "$FX6/lib/real.sh"; : > "$FX6/app/helper.sh"; : > "$FX6/other/y.sh"
printf 'REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"\nbash "$REPO_ROOT/lib/real.sh"\n' > "$FX6/app/deep/t1.sh"
printf 'REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\nbash "$REPO_ROOT/lib/real.sh"\n' > "$FX6/app/t2.sh"
printf 'APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"\nbash "$APP/helper.sh"\n' > "$FX6/app/deep/t3.sh"
printf 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nbash "$HERE/../helper.sh"\n' > "$FX6/app/deep/t4.sh"
printf 'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\nROOT="$(cd "$ROOT/.." && pwd)"\nbash "$ROOT/lib/real.sh"\n' > "$FX6/app/deep/t5.sh"
# one line, `;`-joined: the whole line is one token, so `$R` expands to a value that runs to the end of the line
printf 'R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; bash "$R/other/y.sh"\n' > "$FX6/app/deep/t6.sh"
# the unquoted assignment captures only `$(cd`: no spelling of it resolves, before or after D1
printf 'R=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)\nbash "$R/other/y.sh"\n' > "$FX6/app/deep/t7.sh"
# a variable rebuilt from a variable: `$REPO_ROOT/..` is the parent of the repo root, which is OUTSIDE the repo
printf 'P="$(cd "$REPO_ROOT/.." && pwd)"\nbash "$P/lib/real.sh"\n' > "$FX6/app/deep/t8.sh"
assert_fixture_dir "$FX6"
d1_edges() { derive_run "$FX6" "_affected_reset_edges; _affected_file_edges $1; printf '%s' \"\$(printf '%s\\n' \${_AC_EDGES[@]+\"\${_AC_EDGES[@]}\"} | LC_ALL=C sort | tr '\\n' ' ')\"" 2>&1; }
cases=$((cases + 1))
_d1a="$(d1_edges app/deep/t1.sh)"
if [[ "$_d1a" == "^lib/real.sh " ]]; then pass "D1: cd \"<dir>/../..\" && pwd resolves two levels up, so \$REPO_ROOT/lib/real.sh is an edge"; else fail "D1 two-level: edges '${_d1a:0:160}'"; fi
cases=$((cases + 1))
_d1b="$(d1_edges app/t2.sh)"
if [[ "$_d1b" == "^lib/real.sh " ]]; then pass "D1: cd \"<dir>/..\" && pwd resolves one level up"; else fail "D1 one-level: edges '${_d1b:0:160}'"; fi
cases=$((cases + 1))
_d1c="$(d1_edges app/deep/t3.sh)"
# The whole-line dirname resolve (rows A5-dirname) splits `$(cd "app/deep/.." && pwd -P)` into words, and the word `"app/deep/.."` is
# itself a path that exists: the cd TARGET directory (^app/) is a coarse extra edge. It only widens; the row pins the precise edge.
if [[ " $_d1c " == *" ^app/helper.sh "* && " $_d1c " != *" ^app/deep/helper.sh "* ]]; then pass "D1: the pwd -P spelling resolves to the cd target too (^app/helper.sh, not app/deep/helper.sh)"; else fail "D1 pwd -P: edges '${_d1c:0:160}' (want ^app/helper.sh, never ^app/deep/helper.sh)"; fi
cases=$((cases + 1))
_d1d="$(d1_edges app/deep/t4.sh)"
if [[ " $_d1d " == *" ^app/helper.sh "* ]]; then pass "D1 control: a cd with no /.. still resolves to the file's own directory (^app/helper.sh via app/deep/../helper.sh)"; else fail "D1 control: edges '${_d1d:0:160}' (want ^app/helper.sh)"; fi

# A variable rebuilt from a variable is not resolvable here: it must NOT be normalised to a wrong path. `cd "$REPO_ROOT/.." && pwd`
# is the PARENT of the repo root (outside the repo), and normpath would collapse `$REPO_ROOT/..` to `.`, which names the repo
# root: `bash "$P/lib/real.sh"` would then mint ^lib/real.sh, a file the suite does not run. The `*'$'*` guard keeps such a
# token on the greedy fallback. The row is built so that its result DIFFERS with and without the guard: the same block with
# the guard removed (count asserted) must mint the wrong edge, otherwise the row would pass with its guard deleted.
cases=$((cases + 1))
_d1h="$(d1_edges app/deep/t8.sh)"
_g_old="    if [[ \"\$_cdt\" != *'\$'* ]]; then"
_g_n="$(grep -cF -- "$_g_old" "$DERIVE_SRC")"
_blk="$(cat "$DERIVE_SRC")"
printf '%s\n' "${_blk/"$_g_old"/    if true; then}" > "$TESTROOT/derive-noguard.sh"
_g_mut="$(DERIVE_BLOCK="$TESTROOT/derive-noguard.sh" d1_edges app/deep/t8.sh)"
if [[ "$_g_n" == "1" ]] && ! cmp -s "$DERIVE_SRC" "$TESTROOT/derive-noguard.sh" \
   && [[ " $_d1h " != *" ^lib/real.sh "* && " $_g_mut " == *" ^lib/real.sh "* ]]; then
  pass "D1: a cd target built from a variable is not normalised (no ^lib/real.sh); the same row WITHOUT the \$-guard mints it (guard landed once, result differs)"
else
  fail "D1 guard: guard sites=$_g_n guarded='${_d1h:0:100}' (want no ^lib/real.sh) unguarded='${_g_mut:0:100}' (want ^lib/real.sh)"
fi

# D1 may only WIDEN. `R="$(cd ... && pwd)"; bash "$R/other/y.sh"` on ONE line carries the whole line as a single token, so `$R`
# expands to a value that ends in the rest of the line; before D1 the greedy collapse gave that token the file's own directory
# (^app/deep/), and D1's normalisation resolved it to the repo root (rejected), dropping the edge. A token D1 left without an
# edge is re-run as it was before D1.
cases=$((cases + 1))
_d1f="$(d1_edges app/deep/t6.sh)"
if [[ "$_d1f" == "^app/deep/ " ]]; then pass "D1: the ;-joined one-line shape keeps the file's own directory edge (D1 did not narrow it)"; else fail "D1 ;-joined: edges '${_d1f:0:160}' (want ^app/deep/)"; fi
# The unquoted `R=$(cd ... && pwd)` assignment is a LIMIT, identical before and after D1 (the variable map captures `$(cd` only):
# pinned so a change in either direction is noticed, not because it is right. Nothing is lost relative to the runner before D1.
cases=$((cases + 1))
_d1g="$(d1_edges app/deep/t7.sh)"
if [[ -z "${_d1g// /}" ]]; then pass "D1 limit: the unquoted R=\$(cd ...) assignment resolves to no edge, as it did before D1"; else fail "D1 unquoted: edges '${_d1g:0:160}' (before D1 this shape had none; a new edge is a widening to review)"; fi

# ---- A5 bench: the declared-delta (--leaf-files) compare, driven on synthesized streams --------------------
# The bench's walker is its OWN code (grep-shaped regexes over suite text, never the runner), so the rows
# build a small tree whose leaf file (runner.sh) sources one real file and merely NAMES three more, and
# hand-written base/head streams. Every RED row asserts rc and a message substring.
LF="$TESTROOT/leafbench"
mkdir -p "$LF/root/lib" "$LF/root/named"
: > "$LF/root/lib/real.sh"; : > "$LF/root/named/b.sh"; : > "$LF/root/named/c.sh"; : > "$LF/root/named/helper.sh"
printf 'source named/helper.sh\n' > "$LF/root/named/a.test.sh"
printf 'source lib/real.sh\nbash named/a.test.sh\nbash named/b.sh\n' > "$LF/root/runner.sh"
printf 'bash named/c.sh\n' > "$LF/root/idx.sh"
printf 'bash ./runner.sh\n' > "$LF/root/suite1.sh"
printf 'bash ./runner.sh\n' > "$LF/root/suite3.sh"
printf 'bash ./idx.sh\n' > "$LF/root/suite4.sh"
printf 'echo plain\n' > "$LF/root/suite2.sh"
assert_fixture_dir "$LF"
printf 'SUITE_COMMAND\tS1\tbash\tsuite1.sh\nSUITE_COMMAND\tS2\tbash\tsuite2.sh\nSUITE_COMMAND\tS3\tbash\tsuite3.sh\nSUITE_COMMAND\tS4\tbash\tsuite4.sh\n' > "$LF/cmds.tsv"
mkstream() { # mkstream <out> <S1 edges> <S2 edges> <S3 edges> <S4 edges>  (each '|'-joined)
  local out="$1"; shift
  assert_fixture_dir "$out"
  { printf 'AFFECTED_SELECTED\tS1\t1\tedge:derived\t%s\n' "$1"
    printf 'AFFECTED_SELECTED\tS2\t1\tedge:derived\t%s\n' "$2"
    printf 'AFFECTED_SELECTED\tS3\t1\tedge:derived\t%s\n' "$3"
    printf 'AFFECTED_SELECTED\tS4\t1\tedge:derived\t%s\n' "$4"
    printf 'AFFECTED_SUMMARY selected=4 of=4 always_on=0 edge=4 fallback=none\n'
  } > "$out"
}
S1_BASE='^suite1.sh|^runner.sh|^lib/real.sh|^named/a.test.sh|^named/helper.sh|^named/b.sh'
S1_HEAD='^suite1.sh|^runner.sh|^lib/real.sh'
S3_BASE='^suite3.sh|^runner.sh|^lib/real.sh|^named/a.test.sh|^named/helper.sh|^named/b.sh'
S3_HEAD='^suite3.sh|^runner.sh|^lib/real.sh'
S4_BASE='^suite4.sh|^idx.sh|^named/c.sh'
S4_HEAD='^suite4.sh|^idx.sh'
S2='^suite2.sh'
leafcmp() { # leafcmp <leaf list> <base> <head> [extra bench args...] -> prints verdict, rc in LEAF_RC
  local _ll="$1" _lb="$2" _lh="$3"; shift 3
  LEAF_OUT="$(bash "$BENCH" --compare-only "$_lb" "$_lh" --leaf-files "$_ll" --cmds "$LF/cmds.tsv" --root "$LF/root" "$@" 2>&1)"; LEAF_RC=$?
}
mkstream "$LF/base.tsv" "$S1_BASE" "$S2" "$S3_BASE" "$S4_BASE"

cases=$((cases + 1))
mkstream "$LF/h-ok.tsv" "$S1_HEAD" "$S2" "$S3_HEAD" "$S4_HEAD"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-ok.tsv"
if [[ "$LEAF_RC" == "0" && "$LEAF_OUT" == *"EXPLAINED (0 unexplained, 0 kept, ceilings 0/0): 4 rows compared, 3 reach a leaf file, 3 lost edges"* ]]; then
  pass "A5 bench: removing exactly the leaf-named edges is explained (rc 0; 3 of 4 rows reach a leaf; the index leaf explains S4)"
else
  fail "A5 bench: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
mkstream "$LF/h-real.tsv" '^suite1.sh|^runner.sh' "$S2" "$S3_HEAD" "$S4_HEAD"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-real.tsv"
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"lost the REAL source edge lib/real.sh"* ]]; then
  pass "A5 bench: dropping a real source edge of a leaf file is refused (retained-edge check)"
else
  fail "A5 bench real-edge: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
mkstream "$LF/h-unexpl.tsv" "$S1_HEAD" "$S2" '^runner.sh|^lib/real.sh' "$S4_HEAD"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-unexpl.tsv"
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"row S3: removed set != walker's expected set"* && "$LEAF_OUT" != *"row S1: removed set"* ]]; then
  pass "A5 bench: an unexplained removal in a later row is refused after a compliant first row (every row is checked)"
else
  fail "A5 bench unexplained: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
mkstream "$LF/h-add.tsv" "$S1_HEAD|^named/c.sh" "$S2" "$S3_HEAD" "$S4_HEAD"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-add.tsv"
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"row S1: head ADDS edges"* ]]; then
  pass "A5 bench: a head edge the base lacked is refused (the head may only lose edges)"
else
  fail "A5 bench add: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/base.tsv"
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"population floor: no row lost an edge"* ]]; then
  pass "A5 bench: head equal to base (a neutralised leaf rule) is refused by the population floor (no row lost an edge)"
else
  fail "A5 bench neutralised: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
mkstream "$LF/h-class.tsv" "$S1_HEAD" "$S2" "$S3_HEAD" "$S4_HEAD"
sed -i 's/^\(AFFECTED_SELECTED\tS2\t1\t\)edge:derived/\1always_on/' "$LF/h-class.tsv"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-class.tsv"
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"row S2: label/class differ"* ]]; then
  pass "A5 bench: a class change on any row is refused"
else
  fail "A5 bench class: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
: > "$LF/empty.tsv"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/empty.tsv"
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"empty stream"* ]]; then
  pass "A5 bench: an empty head stream is refused"
else
  fail "A5 bench empty: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
mkstream "$LF/h-nothing.tsv" "$S1_BASE" "$S2" "$S3_BASE" "$S4_BASE"
leafcmp nonexistent-leaf.sh "$LF/base.tsv" "$LF/h-nothing.tsv"
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"population floor: no row lost an edge"* ]]; then
  pass "A5 bench: a leaf set no row reaches fails the population floor (0 compared cannot pass)"
else
  fail "A5 bench floor: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

cases=$((cases + 1))
LEAF_OUT="$(bash "$BENCH" --compare-only "$LF/base.tsv" "$LF/h-ok.tsv" --leaf-files runner.sh --cmds "$LF/cmds.tsv" --root "$LF/root" --added S9 2>&1)"; LEAF_RC=$?
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"exclusive"* ]]; then
  pass "A5 bench: --leaf-files is exclusive with --added (the two contracts are not mixed)"
else
  fail "A5 bench exclusive: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi

# ---- A5 bench: per-row invariants, the two ceilings, the blind-walker floor and the usage errors ----------------
mkrows() { # mkrows <out> <label#bit#class#edges>...: the rows and the AFFECTED_SUMMARY the runner would print for them
  local out="$1"; shift
  assert_fixture_dir "$out"
  : > "$out"
  local spec label bit cls edges sel=0 ao=0 ed=0 n=0
  for spec in "$@"; do
    IFS='#' read -r label bit cls edges <<< "$spec"
    printf 'AFFECTED_SELECTED\t%s\t%s\t%s\t%s\n' "$label" "$bit" "$cls" "$edges" >> "$out"
    n=$((n + 1))
    if [[ "$bit" == "1" ]]; then
      sel=$((sel + 1))
      case "$cls" in always_on) ao=$((ao + 1)) ;; edge:*) ed=$((ed + 1)) ;; esac
    fi
  done
  printf 'AFFECTED_SUMMARY selected=%d of=%d always_on=%d edge=%d fallback=none\n' "$sel" "$n" "$ao" "$ed" >> "$out"
}
D='edge:derived'
# (a) a row that reaches a leaf and loses NOTHING while the walker expects removals is a hard failure no ceiling can excuse
cases=$((cases + 1))
mkrows "$LF/h-a.tsv" "S1#1#$D#$S1_BASE" "S2#1#$D#$S2" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-a.tsv" --max-unexplained 99 --max-kept 99
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"row S1: reaches a leaf file and lost NOTHING"* ]]; then
  pass "A5 bench (a): a row that reaches a leaf and lost nothing fails with both ceilings at 99 (the rule did not apply to it)"
else
  fail "A5 bench (a): rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi
# (b) a row that reaches no leaf but loses edges is a hard failure, whatever the ceilings
cases=$((cases + 1))
mkrows "$LF/base-b.tsv" "S1#1#$D#$S1_BASE" "S2#1#$D#^suite2.sh|^named/b.sh|^named/c.sh" "S3#1#$D#$S3_BASE" "S4#1#$D#$S4_BASE"
mkrows "$LF/h-b.tsv" "S1#1#$D#$S1_HEAD" "S2#1#$D#$S2" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"
leafcmp runner.sh,idx.sh "$LF/base-b.tsv" "$LF/h-b.tsv" --max-unexplained 99 --max-kept 99
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"row S2: lost 2 edge(s)"* && "$LEAF_OUT" == *"reach no leaf file with outbound edges"* ]]; then
  pass "A5 bench (b): a row that does not reach a leaf but loses edges fails with both ceilings at 99"
else
  fail "A5 bench (b): rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi
# (f) "reaches a leaf" counts only leaves that have outbound edges: lib/real.sh names nothing, so a row that merely carries it
# does not reach a leaf, cannot lose anything, and is not counted. Listing it as a leaf changes neither the count nor the verdict.
cases=$((cases + 1))
mkrows "$LF/base-f.tsv" "S1#1#$D#$S1_BASE" "S2#1#$D#^suite2.sh|^lib/real.sh" "S3#1#$D#$S3_BASE" "S4#1#$D#$S4_BASE"
mkrows "$LF/h-f.tsv" "S1#1#$D#$S1_HEAD" "S2#1#$D#^suite2.sh|^lib/real.sh" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"
leafcmp runner.sh,idx.sh,lib/real.sh "$LF/base-f.tsv" "$LF/h-f.tsv"; _f_rc=$LEAF_RC; _f_out="$LEAF_OUT"
mkrows "$LF/h-f2.tsv" "S1#1#$D#$S1_HEAD" "S2#1#$D#^suite2.sh" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"
leafcmp runner.sh,idx.sh,lib/real.sh "$LF/base-f.tsv" "$LF/h-f2.tsv"
if [[ "$_f_rc" == "0" && "$_f_out" == *"4 rows compared, 3 reach a leaf file, 3 lost edges"* && "$LEAF_RC" == "1" && "$LEAF_OUT" == *"row S2: lost 1 edge(s)"* ]]; then
  pass "A5 bench (f): a leaf with no outbound edge (lib/real.sh) does not count as reached (3, not 4) and a row carrying only it may lose nothing"
else
  fail "A5 bench (f): control rc=$_f_rc ${_f_out:0:200} | loss rc=$LEAF_RC ${LEAF_OUT:0:200}"
fi
# (c) the selected bit may narrow 1 -> 0 only with a removed edge that matches a --probe path
mkrows "$LF/h-c.tsv" "S1#0#$D#$S1_HEAD" "S2#1#$D#$S2" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"
cases=$((cases + 1))
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-c.tsv" --probe named/b.sh
if [[ "$LEAF_RC" == "0" && "$LEAF_OUT" == *"EXPLAINED (0 unexplained, 0 kept"* ]]; then
  pass "A5 bench (c): a 1 -> 0 narrowing is accepted when the removed edge ^named/b.sh matches the probe path (summary adjusted by the flip)"
else
  fail "A5 bench (c) matching probe: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi
cases=$((cases + 1))
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-c.tsv"; _c_none_rc=$LEAF_RC; _c_none_out="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-c.tsv" --probe other/z.sh
if [[ "$_c_none_rc" == "1" && "$_c_none_out" == *"row S1: selected bit changed 1 -> 0 without a removed probe-matching edge"* \
   && "$LEAF_RC" == "1" && "$LEAF_OUT" == *"selected bit changed 1 -> 0"* ]]; then
  pass "A5 bench (c): the same 1 -> 0 narrowing is refused with no probe and with a probe that matches none of the removed edges"
else
  fail "A5 bench (c) refused: no-probe rc=$_c_none_rc ${_c_none_out:0:160} | other-probe rc=$LEAF_RC ${LEAF_OUT:0:160}"
fi
# (d) a blind walker is a failure: no SUITE_COMMAND records at all, or a compared label without one
cases=$((cases + 1))
: > "$LF/cmds-empty.tsv"
LEAF_OUT="$(bash "$BENCH" --compare-only "$LF/base.tsv" "$LF/h-ok.tsv" --leaf-files runner.sh,idx.sh --cmds "$LF/cmds-empty.tsv" --root "$LF/root" --max-unexplained 99 --max-kept 99 2>&1)"; LEAF_RC=$?
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"holds no SUITE_COMMAND record"* ]]; then
  pass "A5 bench (d): a --cmds stream with no SUITE_COMMAND record is refused even with both ceilings at 99"
else
  fail "A5 bench (d) empty cmds: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi
cases=$((cases + 1))
grep -v $'^SUITE_COMMAND\tS3\t' "$LF/cmds.tsv" > "$LF/cmds-nos3.tsv"
LEAF_OUT="$(bash "$BENCH" --compare-only "$LF/base.tsv" "$LF/h-ok.tsv" --leaf-files runner.sh,idx.sh --cmds "$LF/cmds-nos3.tsv" --root "$LF/root" --max-unexplained 99 --max-kept 99 2>&1)"; LEAF_RC=$?
if [[ "$LEAF_RC" == "1" && "$LEAF_OUT" == *"row S3: no SUITE_COMMAND record"* ]]; then
  pass "A5 bench (d): a compared label with no SUITE_COMMAND record is refused (the walker would have no roots for it)"
else
  fail "A5 bench (d) missing label: rc=$LEAF_RC ${LEAF_OUT:0:300}"
fi
# (e) two ceilings, one per direction, each driven at N (pass) and N-1 (fail), and neither excuses the other
mkrows "$LF/h-e1.tsv" "S1#1#$D#^runner.sh|^lib/real.sh" "S2#1#$D#$S2" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"   # S1 also loses its own ^suite1.sh: 1 unexplained
mkrows "$LF/h-e2.tsv" "S1#1#$D#$S1_HEAD|^named/b.sh" "S2#1#$D#$S2" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"       # S1 keeps ^named/b.sh, which is only named by the leaf: 1 kept
cases=$((cases + 1))
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e1.tsv" --max-unexplained 1; _e1_pass_rc=$LEAF_RC; _e1_pass_out="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e1.tsv" --max-unexplained 0; _e1_fail_rc=$LEAF_RC; _e1_fail_out="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e1.tsv" --max-unexplained 0 --max-kept 99; _e1_other_rc=$LEAF_RC
if [[ "$_e1_pass_rc" == "0" && "$_e1_pass_out" == *"EXPLAINED (1 unexplained, 0 kept, ceilings 1/0)"* \
   && "$_e1_fail_rc" == "1" && "$_e1_fail_out" == *"(1 unexplained removals"*"ceiling --max-unexplained 0)"* && "$_e1_other_rc" == "1" ]]; then
  pass "A5 bench (e): --max-unexplained N passes a row with N unexplained removals, N-1 fails it, and --max-kept does not excuse it"
else
  fail "A5 bench (e) unexplained: N rc=$_e1_pass_rc ${_e1_pass_out:0:160} | N-1 rc=$_e1_fail_rc ${_e1_fail_out:0:160} | other-ceiling rc=$_e1_other_rc"
fi
cases=$((cases + 1))
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e2.tsv" --max-kept 1; _e2_pass_rc=$LEAF_RC; _e2_pass_out="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e2.tsv" --max-kept 0; _e2_fail_rc=$LEAF_RC; _e2_fail_out="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e2.tsv" --max-kept 0 --max-unexplained 99; _e2_other_rc=$LEAF_RC
if [[ "$_e2_pass_rc" == "0" && "$_e2_pass_out" == *"EXPLAINED (0 unexplained, 1 kept, ceilings 0/1)"* \
   && "$_e2_fail_rc" == "1" && "$_e2_fail_out" == *"head KEPT 1 edge(s)"*"ceiling --max-kept 0"* && "$_e2_other_rc" == "1" ]]; then
  pass "A5 bench (e): --max-kept N passes a row that kept N expected-removed edges, N-1 fails it, and --max-unexplained does not excuse it"
else
  fail "A5 bench (e) kept: N rc=$_e2_pass_rc ${_e2_pass_out:0:160} | N-1 rc=$_e2_fail_rc ${_e2_fail_out:0:160} | other-ceiling rc=$_e2_other_rc"
fi
# (g) the printed category: each direction names why the walker did not expect it. h-e1 drops the suite's own file, which the
# walker's head closure still reaches; base-g carries an edge the walker never derives (^lib/ghost.sh) and the head drops it.
cases=$((cases + 1))
mkrows "$LF/base-g.tsv" "S1#1#$D#$S1_BASE|^lib/ghost.sh" "S2#1#$D#$S2" "S3#1#$D#$S3_BASE" "S4#1#$D#$S4_BASE"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e1.tsv" --max-unexplained 1; _g1="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base-g.tsv" "$LF/h-ok.tsv" --max-unexplained 1; _g3="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-e2.tsv" --max-kept 1; _g2="$LEAF_OUT"
if [[ "$_g1" == *"by category: removed: the walker's head closure still reaches it=1"* \
   && "$_g3" == *"by category: removed: not in the walker's base closure=1"* \
   && "$_g2" == *"by category: kept: head route the walker lacks=1"* ]]; then
  pass "A5 bench (g): unexplained and kept edges are printed by category (head closure still reaches it; outside the walker's base closure; kept edge the walker's head closure lacks)"
else
  fail "A5 bench (g): head-reaches='${_g1:0:260}' not-in-base='${_g3:0:260}' kept='${_g2:0:260}'"
fi

# fidelity: the walker prints how many edge-classified rows of each stream it reproduces EXACTLY; a base row carrying an edge the
# walker never derives (^lib/ghost.sh) counts against the base side only
cases=$((cases + 1))
leafcmp runner.sh,idx.sh "$LF/base.tsv" "$LF/h-ok.tsv"; _fid_ok="$LEAF_OUT"
leafcmp runner.sh,idx.sh "$LF/base-g.tsv" "$LF/h-ok.tsv" --max-unexplained 1; _fid_g="$LEAF_OUT"
if [[ "$_fid_ok" == *"walker fidelity: it reproduced 4 of 4 base rows and 4 of 4 head rows exactly"* \
   && "$_fid_g" == *"walker fidelity: it reproduced 3 of 4 base rows and 4 of 4 head rows exactly"* ]]; then
  pass "A5 bench: the walker's fidelity is printed per side (4 of 4 on a clean pair; 3 of 4 base rows when one carries an edge the walker never derives)"
else
  fail "A5 bench fidelity: clean='${_fid_ok:0:200}' ghost='${_fid_g:0:200}'"
fi

# Full dispatch path: fake runners through --base-runner/--head-runner. The walker root is passed (--root) because the runners
# run from the repository root; --cmds is NOT passed, so the suite commands come from the head runner's own --enumerate-commands.
mkrows "$LF/sel.head-ok" "S1#1#$D#$S1_HEAD" "S2#1#$D#$S2" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"
cp "$LF/cmds.tsv" "$LF/enum.leaf"
mk_runner "$LF/run.leaf-base" "$LF/base.tsv" "$LF/enum.leaf"
mk_runner "$LF/run.leaf-head" "$LF/sel.head-ok" "$LF/enum.leaf"
leafbench() { LB_OUT="$( cd "$REPO_ROOT" && bash "$BENCH" "$@" 2>&1 )"; LB_RC=$?; }
cases=$((cases + 1))
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-head" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root"
if [[ "$LB_RC" == "0" && "$LB_OUT" == *"EXPLAINED (0 unexplained, 0 kept, ceilings 0/0): 4 rows compared"* && "$LB_OUT" == *"selection narrowed only as declared"* ]]; then
  pass "A5 bench dispatch: --leaf-files through --base-runner/--head-runner is explained and says 'narrowed only as declared' with 0 unexplained and 0 kept"
else
  fail "A5 bench dispatch: rc=$LB_RC ${LB_OUT:0:400}"
fi
# (g) the plain-language line never claims "only as declared" when a removal was tolerated
cases=$((cases + 1))
mk_runner "$LF/run.leaf-e1" "$LF/h-e1.tsv" "$LF/enum.leaf"
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-e1" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root" --max-unexplained 1
if [[ "$LB_RC" == "0" && "$LB_OUT" == *"narrowed, with 1 unexplained removal(s) and 0 kept edge(s) within the ceilings"* && "$LB_OUT" != *"narrowed only as declared"* ]]; then
  pass "A5 bench dispatch (g): with one tolerated unexplained removal the verdict line carries the numbers and never says 'narrowed only as declared'"
else
  fail "A5 bench dispatch (g): rc=$LB_RC ${LB_OUT:0:400}"
fi
# declared-edge protection: a label that DECLARES an edge keeps it in the head (the runner re-adds declarations), so the head
# keeping ^named/b.sh is not a "kept" edge for it. The fixture root carries a lib declaring AFFECTED_S1_PATHS=(named/b.sh); the
# control root has none, so the same head stream keeps an edge the walker expects removed.
cases=$((cases + 1))
mkdir -p "$LF/rootd/scripts/lib"
cp -r "$LF/root/." "$LF/rootd/"
printf 'AFFECTED_S1_PATHS=(\n  "named/b.sh"\n)\n' > "$LF/rootd/scripts/lib/test-affected-paths.sh"
mkrows "$LF/sel.head-decl" "S1#1#$D#$S1_HEAD|^named/b.sh" "S2#1#$D#$S2" "S3#1#$D#$S3_HEAD" "S4#1#$D#$S4_HEAD"
mk_runner "$LF/run.leaf-decl" "$LF/sel.head-decl" "$LF/enum.leaf"
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-decl" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/rootd"; _d_rc=$LB_RC; _d_out="$LB_OUT"
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-decl" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root"
if [[ "$_d_rc" == "0" && "$_d_out" == *"EXPLAINED (0 unexplained, 0 kept"* && "$LB_RC" == "1" && "$LB_OUT" == *"head KEPT 1 edge(s)"* ]]; then
  pass "A5 bench dispatch: a declared edge is protected (kept is 0 with the declaration, 1 without it)"
else
  fail "A5 bench dispatch declared: with-decl rc=$_d_rc ${_d_out:0:160} | without rc=$LB_RC ${LB_OUT:0:160}"
fi
# AFFECTED_CONSUMED_EDGES (`label|ARRAY`, the array owned by EITHER lib) declares edges just as a per-label array does: the runner
# re-adds them, so the head keeping ^named/b.sh is not "kept" for a label that consumes an array holding it.
cases=$((cases + 1))
mkdir -p "$LF/rootc/scripts/lib"
cp -r "$LF/root/." "$LF/rootc/"
printf 'AFFECTED_CONSUMED_EDGES=(\n  "S1|S1_CONSUMED"\n)\n' > "$LF/rootc/scripts/lib/test-affected-paths.sh"
printf 'S1_CONSUMED=(\n  "named/b.sh"\n)\n' > "$LF/rootc/scripts/lib/test-relevance-paths.sh"
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-decl" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/rootc"
if [[ "$LB_RC" == "0" && "$LB_OUT" == *"EXPLAINED (0 unexplained, 0 kept"* ]]; then
  pass "A5 bench dispatch: an edge consumed through AFFECTED_CONSUMED_EDGES (array in the relevance lib) is protected like a declared one"
else
  fail "A5 bench dispatch consumed: rc=$LB_RC ${LB_OUT:0:300}"
fi
# a partially neutralised rule: it applied to S1 and S4 and not to S3, which reaches the runner and lost nothing
cases=$((cases + 1))
mkrows "$LF/sel.head-part" "S1#1#$D#$S1_HEAD" "S2#1#$D#$S2" "S3#1#$D#$S3_BASE" "S4#1#$D#$S4_HEAD"
mk_runner "$LF/run.leaf-part" "$LF/sel.head-part" "$LF/enum.leaf"
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-part" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root" --max-unexplained 99 --max-kept 99
if [[ "$LB_RC" == "1" && "$LB_OUT" == *"row S3: reaches a leaf file and lost NOTHING"* ]]; then
  pass "A5 bench dispatch: a rule that applied to some rows and not S3 fails through the full path even with both ceilings at 99"
else
  fail "A5 bench dispatch partial: rc=$LB_RC ${LB_OUT:0:400}"
fi
# the selected bit through the full path (the probe names an edge the head removed)
cases=$((cases + 1))
mk_runner "$LF/run.leaf-flip" "$LF/h-c.tsv" "$LF/enum.leaf"
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-flip" --probe named/b.sh --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root"; _fl_rc=$LB_RC
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-flip" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root"
if [[ "$_fl_rc" == "0" && "$LB_RC" == "1" && "$LB_OUT" == *"selected bit changed 1 -> 0"* ]]; then
  pass "A5 bench dispatch: a selected-bit narrowing passes the full path with a matching --probe and fails with one that matches none"
else
  fail "A5 bench dispatch bit: matching rc=$_fl_rc | other rc=$LB_RC ${LB_OUT:0:300}"
fi
# the blind-walker floor on the full path: a head runner whose --enumerate-commands lists nothing, or exits non-zero, is a failure;
# an operator-passed --cmds is used as given (the loop used to overwrite it with the enumeration).
: > "$LF/enum.none"
mk_runner "$LF/run.leaf-noenum" "$LF/sel.head-ok" "$LF/enum.none"
cases=$((cases + 1))
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-noenum" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root" --max-unexplained 99 --max-kept 99
if [[ "$LB_RC" == "1" && "$LB_OUT" == *"cannot enumerate the head's suite commands (rc=0, 0 SUITE_COMMAND record(s))"* ]]; then
  pass "A5 bench dispatch (d): a head runner that enumerates no suite command is a failure, not an empty walker that passes under the ceilings"
else
  fail "A5 bench dispatch blind: rc=$LB_RC ${LB_OUT:0:400}"
fi
cases=$((cases + 1))
mk_runner "$LF/run.leaf-enumfail" "$LF/sel.head-ok" "$LF/enum.leaf" 'case "$*" in *--enumerate-commands*) echo "enumeration broke" >&2; exit 7 ;; esac'
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-enumfail" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root"
if [[ "$LB_RC" == "1" && "$LB_OUT" == *"cannot enumerate the head's suite commands (rc=7"*"enumeration broke"* ]]; then
  pass "A5 bench dispatch (d): a head runner whose --enumerate-commands exits non-zero fails with its rc and stderr in the message"
else
  fail "A5 bench dispatch enumfail: rc=$LB_RC ${LB_OUT:0:400}"
fi
cases=$((cases + 1))
leafbench --base-runner "$LF/run.leaf-base" --head-runner "$LF/run.leaf-noenum" --probe README.md --runs 1 --leaf-files runner.sh,idx.sh --root "$LF/root" --cmds "$LF/cmds.tsv"
if [[ "$LB_RC" == "0" && "$LB_OUT" == *"EXPLAINED (0 unexplained, 0 kept"* ]]; then
  pass "A5 bench dispatch (h): an operator-passed --cmds is used as given (a head runner that enumerates nothing is not consulted)"
else
  fail "A5 bench dispatch --cmds: rc=$LB_RC ${LB_OUT:0:400}"
fi
# (h) these options mean nothing outside leaf mode: accepted and ignored they would read as a check that ran
cases=$((cases + 1))
_u_bad=""
for _opt in "--cmds $LF/cmds.tsv" "--root $LF/root" "--max-kept 1" "--max-unexplained 1"; do
  # shellcheck disable=SC2086 # the option string is argv words by design
  _u_out="$(bash "$BENCH" --compare-only "$LF/base.tsv" "$LF/base.tsv" $_opt 2>&1)"; _u_rc=$?
  [[ "$_u_rc" == "2" && "$_u_out" == *"need --leaf-files"* ]] || _u_bad+=" [${_opt%% *} rc=$_u_rc]"
done
if [[ -z "$_u_bad" ]]; then
  pass "A5 bench (h): --cmds, --root, --max-kept and --max-unexplained without --leaf-files are usage errors (rc 2)"
else
  fail "A5 bench (h): not refused:$_u_bad"
fi

# ---- verdict accounting -----------------------------------------------------------------------------
echo ""
if (( PASS + FAIL != cases )); then
  echo "[FATAL] verdict mismatch: PASS($PASS)+FAIL($FAIL) != cases($cases) — a row was skipped" >&2
  exit 2
fi
MIN_CASES=116
if (( cases + SKIPPED < MIN_CASES )); then
  echo "[FATAL] only $cases cases ran (+$SKIPPED skipped) — below the $MIN_CASES floor" >&2
  exit 2
fi
if (( SKIPPED > 0 )); then echo "SKIPPED rows=$SKIPPED (a row's host requirement was not met; CI fails instead)"; fi
echo "test-affected-derive: $PASS passed, $FAIL failed of $((PASS + FAIL)) (cases=$cases)"
(( FAIL == 0 )) || exit 1
exit 0
