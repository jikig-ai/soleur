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
# `cases` is incremented at the call site; rows that need a bash >= 5.2 behaviour print a counted
# SKIPPED line locally and FAIL under CI.

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
skip_or_fail() { # skip_or_fail <row id>: a counted skip locally, a failure under CI
  if [[ -n "${CI:-}" ]]; then
    cases=$((cases + 1)); fail "$1: needs bash >= 5.2 and CI runs ${BASH_VERSION}"
  else
    SKIPPED=$((SKIPPED + 1)); echo "  [skip] $1: needs bash >= 5.2 (running ${BASH_VERSION})"
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
derive_run() {
  ( cd "$1" && set -uo pipefail && _PRINT_AFFECTED=0 && _wt_missing_die() { :; } && eval "$(cat "$DERIVE_SRC")" && eval "$2" )
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
  skip_or_fail "R1"
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
  SKIPPED=$((SKIPPED + 1)); echo "  [skip] R3d: no UTF-8 locale available on this host"
else
  cases=$((cases + 1))
  _r3d="$(LC_ALL=$_r3d_loc derive_run "$FX" 'f() { local -a _vn=(A B) _vv=("\$B-$(head -c 4095 /dev/zero | tr "\0" z)" done); _affected_resolve_vars "$1"; }; f "é\$A"; case "$_RV" in *done*) echo RESOLVED ;; *\$B*) echo STOPPED ;; *) echo OTHER ;; esac' 2>&1)"
  if [[ "$_r3d" == "RESOLVED" ]]; then pass "R3d: the growth cap counts bytes under a UTF-8 caller locale ($_r3d_loc)"; else fail "R3d($_r3d_loc): '$_r3d'"; fi
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
_d3_forms=("deno test" "make test" "npm run test" "bun run test" "pnpm run test" "yarn run test" "bun test" "go test" "cargo test")
_d3_n=0
for _form in "${_d3_forms[@]}"; do
  _d3_n=$((_d3_n + 1))
  cases=$((cases + 1))
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
if (( _d3_n < 9 )); then fail "D3 floor: only $_d3_n forms driven"; cases=$((cases + 1)); fi
cases=$((cases + 1))
_ctl_argv="$(d3_edges cp test)"
if [[ " $_ctl_argv " == *" ^test/ "* ]]; then pass "D3 control: 'test' after a non-runner word still mints ^test/ (the skip is narrow)"; else fail "D3 control: argv got '${_ctl_argv:0:160}'"; fi
cases=$((cases + 1))
_ctl_pay="$(d3_edges "bash -c 'cd app && cp test'")"
if [[ " $_ctl_pay " == *" ^test/ "* ]]; then pass "D3 control: payload 'cp test' still mints ^test/"; else fail "D3 control: payload got '${_ctl_pay:0:160}'"; fi

# ---- verdict accounting -----------------------------------------------------------------------------
echo ""
if (( PASS + FAIL != cases )); then
  echo "[FATAL] verdict mismatch: PASS($PASS)+FAIL($FAIL) != cases($cases) — a row was skipped" >&2
  exit 2
fi
MIN_CASES=59
if (( cases + SKIPPED < MIN_CASES )); then
  echo "[FATAL] only $cases cases ran (+$SKIPPED skipped) — below the $MIN_CASES floor" >&2
  exit 2
fi
if (( SKIPPED > 0 )); then echo "SKIPPED rows=$SKIPPED (bash < 5.2)"; fi
echo "test-affected-derive: $PASS passed, $FAIL failed of $((PASS + FAIL)) (cases=$cases)"
(( FAIL == 0 )) || exit 1
exit 0
