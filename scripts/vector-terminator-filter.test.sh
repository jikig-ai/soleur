#!/usr/bin/env bash
# Structural + behavioural guard for the TLS terminator's journal filter in the shared vector.toml
# (transforms.inngest_terminator_filter). Two halves, plus mutation rows:
#
#   1. STRUCTURE (python3 tomllib over the real vector.toml): the filter reads exactly the raw journald
#      source, the PII chain reads the FILTER and not the raw source (and still reads every other source),
#      the condition is exactly three whole-line healthy-request drop patterns (each anchored at both ends),
#      scopes the drop to the terminator unit, is infallible (every field read falls back with `??`) and
#      names no kept class, the filter's region carries no unescaped dollar sign (Vector interpolates inside
#      comments; a doubled one is its escape), the stunnel config sets neither `debug` nor `output`, and the
#      fixture file carries the expected cases.
#   2. BEHAVIOUR: `vector test` of vector-terminator-filter.test.toml against the real file, when a Vector
#      0.43.x binary (or the pinned docker image) is reachable. The BLOCKING run is the
#      validate-vector-config.yml step (REQUIRE_VECTOR_TEST=1); here an absent binary is reported as SKIP,
#      never as a pass. `vector validate --no-environment` does NOT compile VRL, so this half is the only
#      proof the condition behaves.
#   3. MUTATION ROWS (Guard 2): each edits a COPY (never the real file) and re-runs the same functions over
#      it. The structure rows need no Vector; with one reachable, the second-drop and unanchor rows are
#      judged by `vector test` itself.
#
# No network. Fixtures are synthetic (loopback and the measured stunnel 5.72 lines).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This suite lives under scripts/ (a guard-vacuity-floor covered directory) but tests the infra config.
INFRA_DIR="$(cd "$SCRIPT_DIR/../apps/web-platform/infra" && pwd)"
VECTOR_TOML="$INFRA_DIR/vector.toml"
TESTS_TOML="$INFRA_DIR/vector-terminator-filter.test.toml"
CLOUD_INIT="$INFRA_DIR/cloud-init-inngest.yml"
VECTOR_IMAGE="${VECTOR_IMAGE:-timberio/vector:0.43.1-alpine}"

command -v python3 >/dev/null 2>&1 || { echo "SETUP FAILED: python3 absent" >&2; exit 2; }
python3 -c 'import tomllib' 2>/dev/null || { echo "SETUP FAILED: python3 tomllib absent (need >=3.11)" >&2; exit 2; }
[[ -f "$VECTOR_TOML" && -f "$TESTS_TOML" && -f "$CLOUD_INIT" ]] || { echo "SETUP FAILED: vector.toml, its test file or cloud-init-inngest.yml is missing" >&2; exit 2; }

PASS=0
FAIL=0
SKIP=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
check() { # check <description> <rc>
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}
check_test() { # check_test <description> <command...>: pass when the command exits 0
  local d="$1"
  shift
  if "$@"; then pass "$d"; else fail "$d"; fi
}

# Instrument self-test: drive pass/fail/check/check_test once each in both directions and require both counters
# to move, then unwind them. A rewritten helper must stop the suite, not make every row below vacuous.
selftest_p0=$PASS
selftest_f0=$FAIL
selftest_ok=1
check "selftest" 0 >/dev/null
[[ "$PASS" -eq $((selftest_p0 + 1)) && "$FAIL" -eq "$selftest_f0" ]] || selftest_ok=0
check "selftest" 1 >/dev/null
[[ "$PASS" -eq $((selftest_p0 + 1)) && "$FAIL" -eq $((selftest_f0 + 1)) ]] || selftest_ok=0
check_test "selftest" true >/dev/null
[[ "$PASS" -eq $((selftest_p0 + 2)) && "$FAIL" -eq $((selftest_f0 + 1)) ]] || selftest_ok=0
check_test "selftest" false >/dev/null
[[ "$PASS" -eq $((selftest_p0 + 2)) && "$FAIL" -eq $((selftest_f0 + 2)) ]] || selftest_ok=0
PASS=$selftest_p0
FAIL=$selftest_f0
if [[ "$selftest_ok" -ne 1 ]]; then
  printf '\n[FATAL] instrument self-test: check()/check_test() did not move the pass and fail counters, so every verdict below would be vacuous.\n' >&2
  exit 1
fi

VT_DIR="$(mktemp -d)" || { echo "SETUP FAILED: mktemp" >&2; exit 2; }
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
assert_fixture_dir "$VT_DIR"
cleanup_suite() {
  assert_fixture_dir "$VT_DIR"
  rm -rf "$VT_DIR"
}
trap cleanup_suite EXIT

# ---------- the structure checker: a function of (vector.toml, cloud-init-inngest.yml, tests.toml) ----------
STRUCT_SRC="$(cat <<'PY'
import re, sys, tomllib

vec_path, ci_path, tests_path = sys.argv[1], sys.argv[2], sys.argv[3]
vec_text = open(vec_path, encoding="utf-8").read()
c = tomllib.loads(vec_text)
t = c.get("transforms", {})

def row(name, ok):
    print(f"{name}\t{0 if ok else 1}")

filt = t.get("inngest_terminator_filter", {})
cond = filt.get("condition", "")
if not isinstance(cond, str):
    cond = ""
drop_in = t.get("pii_scrub_drop_userdata", {}).get("inputs", [])
OTHERS = ["system_journald", "app_container_warn_filter", "host_scripts_journald", "egress_gw_journald", "egress_audit_throttled_dedupe"]
# VRL comments never decide the condition, so every row below reads it comment-stripped.
cond = re.sub(r"(?m)#.*$", "", cond)
MATCHES = re.findall(r"match\(msg, r'([^']*)'\)", cond)
LITS = [r"Service \[inngest\] accepted connection from", r"s_connect: connected 127\.0\.0\.1:8288", r"Service \[inngest\] connected remote server from"]
KEPT = ["Connection closed", "Connection reset", "LOG3", "SSL_accept", "Configuration", "No more addresses", "s_connect: connect "]

row("filter is a filter transform over exactly the raw journald source", filt.get("type") == "filter" and filt.get("inputs") == ["inngest_journald"])
GRAPH = {**c.get("transforms", {}), **c.get("sinks", {})}
def consumers(node):
    return sorted(k for k, v in GRAPH.items() if node in (v.get("inputs") or []))
row("the raw terminator source is read by the filter only, and the filter only by pii_scrub_drop_userdata (no node can take rows before the filter or before the scrub)",
    consumers("inngest_journald") == ["inngest_terminator_filter"] and consumers("inngest_terminator_filter") == ["pii_scrub_drop_userdata"])
row("pii_scrub_drop_userdata reads the filter, not the raw terminator source, and still reads every other source",
    "inngest_terminator_filter" in drop_in and "inngest_journald" not in drop_in and all(o in drop_in for o in OTHERS))
row("filter condition extracted and non-trivial (>= 200 bytes; an empty extraction must fail the suite, never pass it)", len(cond) >= 200)
row("condition is exactly three match() drop patterns, one per healthy-request shape, and no contains()",
    len(MATCHES) == 3 and cond.count("match(") == 3 and "contains(" not in cond
    and all(sum(1 for m in MATCHES if l in m) == 1 for l in LITS))
row("every drop pattern is a WHOLE-line match: anchored at the start, an end anchor (the escaped dollar) and the LOG5 level",
    len(MATCHES) == 3 and all(m.startswith("^") and m.endswith("$$") and r"LOG5\[" in m for m in MATCHES))
row("condition scopes the drop to the terminator unit", "soleur-inngest-tls.service" in cond)
row("condition is infallible: both field reads fall back with ??, no fallible call",
    'string(._SYSTEMD_UNIT) ?? ""' in cond and 'string(.message) ?? ""' in cond and re.search(r"[A-Za-z_]!\(", cond) is None)
row("condition names no kept class (a second drop on Connection closed, LOG3 or SSL_accept is refused)", not any(k in cond for k in KEPT))

start = vec_text.find("# ---------------- inngest_terminator_filter")
end = vec_text.find("# ---------------- Transform 1/3", start) if start >= 0 else -1
region = vec_text[start:end] if start >= 0 and end > start else ""
row("filter region located and carries no unescaped dollar sign (Vector interpolates inside comments; a doubled one is its escape)",
    len(region) >= 200 and "$" not in region.replace("$$", ""))

ci = open(ci_path, encoding="utf-8").read().split("\n")
block = []
i = next((k for k, l in enumerate(ci) if l.strip() == "- path: /etc/soleur/inngest-tls.conf"), -1)
if i >= 0:
    j = next((k for k in range(i + 1, len(ci)) if ci[k].strip() == "content: |"), -1)
    if j >= 0:
        for l in ci[j + 1:]:
            if l.strip() and not l.startswith("      "):
                break
            block.append(l.strip())
row("stunnel config block located (an empty extraction fails)", any(l == "[inngest]" for l in block))
row("the unit the include list and the filter name is defined in cloud-init, and the stunnel service and upstream the drop patterns name exist there (a rename on either side silently stops the shipping or the drop)",
    any(l.strip() == "- path: /etc/systemd/system/soleur-inngest-tls.service" for l in ci)
    and any(l == "[inngest]" for l in block) and any(l == "connect = 127.0.0.1:8288" for l in block))
row("stunnel config sets no debug key (a higher level is the one way this journal carries more than peers, byte counts and errors)",
    not any(re.match(r"^debug\s*=", l, re.I) for l in block))
row("stunnel config sets no output key (a file would pull the logs out of the journal this change ships)",
    not any(re.match(r"^output\s*=", l, re.I) for l in block))

tests = tomllib.load(open(tests_path, "rb")).get("tests", [])
row("fixture file carries at least 21 tests", len(tests) >= 21)
row("fixture file carries exactly 4 drop cases (no_outputs_from: three shapes plus one variant) and every test inserts at the filter",
    sum(1 for x in tests if "no_outputs_from" in x) == 4
    and all(all(i.get("insert_at") == "inngest_terminator_filter" for i in x.get("inputs", [])) for x in tests)
    and len(tests) > 0)
PY
)"
structure_rows() { # <vector.toml> <cloud-init.yml> <tests.toml> -> "name<TAB>rc" lines
  python3 -c "$STRUCT_SRC" "$1" "$2" "$3"
}
row_failed() { # row_failed <rows-file> <name-substring>: succeeds when a row naming it carries rc 1
  # Two reads of FILES, never a pipe into grep -q: under pipefail an early match closes the pipe, the
  # producer takes SIGPIPE and the pipeline reports failure on a real hit.
  local sel="$1.sel"
  assert_fixture_dir "$sel"
  grep -F -- "$2" "$1" > "$sel" || true
  grep -qE $'\t1$' "$sel"
}

# ---------- the Vector runner: a function of (vector.toml, tests.toml, out) ----------
VT_PASSED=0
VT_FAILED=0
run_vector_test() { # <vector.toml> <tests.toml> <out> -> rc of vector test; 99 = no engine reachable
  local v="$1" t="$2" out="$3" stage
  assert_fixture_dir "$out"
  if [[ -n "${VECTOR_BIN:-}" ]] && command -v "$VECTOR_BIN" >/dev/null 2>&1; then
    BETTERSTACK_LOGS_TOKEN=dummy SENTRY_USERID_PEPPER=fixture-only "$VECTOR_BIN" test "$v" "$t" > "$out" 2>&1
    return $?
  elif command -v vector >/dev/null 2>&1 && grep -q ' 0\.43\.' <<<"$(vector --version 2>/dev/null)"; then
    BETTERSTACK_LOGS_TOKEN=dummy SENTRY_USERID_PEPPER=fixture-only vector test "$v" "$t" > "$out" 2>&1
    return $?
  elif command -v docker >/dev/null 2>&1 && docker image inspect "$VECTOR_IMAGE" >/dev/null 2>&1; then
    stage="$(mktemp -d "$VT_DIR/stage.XXXXXX")" || return 98
    assert_fixture_dir "$stage"
    cp "$v" "$stage/vector.toml" || return 98
    cp "$t" "$stage/filter.test.toml" || return 98
    docker run --rm -e BETTERSTACK_LOGS_TOKEN=dummy -e SENTRY_USERID_PEPPER=fixture-only \
      -v "$stage:/c:ro" "$VECTOR_IMAGE" test /c/vector.toml /c/filter.test.toml > "$out" 2>&1
    return $?
  fi
  return 99
}
count_results() { # count_results <out> -> sets VT_PASSED / VT_FAILED from the ANSI-stripped summary lines
  local clean="$1.clean"
  assert_fixture_dir "$clean"
  sed 's/\x1b\[[0-9;]*m//g' "$1" > "$clean"
  VT_PASSED="$(grep -cE '^test .* \.\.\. passed' "$clean" || true)"
  VT_FAILED="$(grep -cE '^test .* \.\.\. failed' "$clean" || true)"
}

echo "-- structure --"
STRUCT_ROWS="$VT_DIR/struct.tsv"
structure_rows "$VECTOR_TOML" "$CLOUD_INIT" "$TESTS_TOML" > "$STRUCT_ROWS" || { echo "SETUP FAILED: the structure pass crashed" >&2; exit 2; }
if [[ ! -s "$STRUCT_ROWS" ]]; then fail "structure pass produced no rows"; fi
while IFS=$'\t' read -r name rc; do
  [[ -n "$name" ]] || continue
  check "$name" "$rc"
done < "$STRUCT_ROWS"

echo "-- behaviour (vector test against the real vector.toml) --"
N_TESTS="$(grep -c '^\[\[tests\]\]' "$TESTS_TOML" || true)"
REAL_OUT="$VT_DIR/real.out"
run_vector_test "$VECTOR_TOML" "$TESTS_TOML" "$REAL_OUT"
VT_RC=$?
VECTOR_AVAILABLE=1
if [[ "$VT_RC" -eq 99 ]]; then
  VECTOR_AVAILABLE=0
  if [[ "${REQUIRE_VECTOR_TEST:-0}" == "1" ]]; then
    fail "REQUIRE_VECTOR_TEST=1 but no Vector binary or pinned docker image is reachable (a skip is not a pass here)"
  else
    SKIP=$((SKIP + 1))
    echo "  SKIP: no Vector 0.43.x binary or pinned docker image reachable (the validate-vector-config.yml step runs this blocking)"
  fi
else
  count_results "$REAL_OUT"
  check_test "vector test exits 0" test "$VT_RC" -eq 0
  check_test "vector test reports no failed test" test "$VT_FAILED" -eq 0
  check_test "vector test passed every test in the fixture file (not zero)" test "$VT_PASSED" -eq "$N_TESTS" -a "$VT_PASSED" -gt 0
fi

echo "-- Guard 2 mutation rows (each edits a COPY; a mutation that does not land is a failure, not a pass) --"
MUT_SRC="$(cat <<'PY'
import re, sys

mode, vec_in, tests_in, vec_out, tests_out = sys.argv[1:6]
vec = open(vec_in, encoding="utf-8").read()
tests = open(tests_in, encoding="utf-8").read()

def swap(text, old, new):
    if text.count(old) != 1:
        sys.stderr.write("mutation anchor not found exactly once (%d): %r\n" % (text.count(old), old))
        sys.exit(3)
    return text.replace(old, new, 1)

if mode == "unwire":
    vec = swap(vec, 'inputs = ["inngest_terminator_filter", "system_journald"', 'inputs = ["inngest_journald", "system_journald"')
elif mode == "second_drop":
    last = r"connected remote server from [0-9a-f.:]+$$')"
    vec = swap(vec, last, last + ' ||\n  contains(msg, "Connection closed: 0 byte(s)")')
elif mode == "bypass":
    vec = swap(vec, 'inputs = ["pii_scrub_string"]', 'inputs = ["pii_scrub_string", "inngest_journald"]')
elif mode == "unanchor":
    old = r'^(\d{4}\.\d\d\.\d\d \d\d:\d\d:\d\d )?LOG5\[[^\]]+\]: Service \[inngest\] accepted connection from [0-9a-f.:]+$$'
    vec = swap(vec, old, r'Service \[inngest\] accepted connection from')
elif mode == "empty_fixture":
    i = tests.find("[[tests]]")
    if i < 0:
        sys.stderr.write("no [[tests]] in the fixture file\n")
        sys.exit(3)
    tests = tests[:i]
elif mode == "rename_filter":
    vec = swap(vec, "[transforms.inngest_terminator_filter]", "[transforms.inngest_terminator_filterx]")
else:
    sys.stderr.write("unknown mutation mode %r\n" % mode)
    sys.exit(4)
open(vec_out, "w", encoding="utf-8").write(vec)
open(tests_out, "w", encoding="utf-8").write(tests)
PY
)"
mutate() { # mutate <mode> -> writes $VT_DIR/m-<mode>/{vector.toml,tests.toml}; rc 0 only when it landed
  local mode="$1" d="$VT_DIR/m-$1" mrc=0
  mkdir -p "$d" || return 2
  assert_fixture_dir "$d"
  python3 -c "$MUT_SRC" "$mode" "$VECTOR_TOML" "$TESTS_TOML" "$d/vector.toml" "$d/tests.toml" || mrc=$?
  if [[ "$mrc" -ne 0 ]]; then return "$mrc"; fi
  if cmp -s "$VECTOR_TOML" "$d/vector.toml" && cmp -s "$TESTS_TOML" "$d/tests.toml"; then return 5; fi
  return 0
}

# Mutation 1: the PII chain reads the raw source again (the filter is unwired). Structure rows only.
if mutate unwire; then
  structure_rows "$VT_DIR/m-unwire/vector.toml" "$CLOUD_INIT" "$VT_DIR/m-unwire/tests.toml" > "$VT_DIR/m-unwire/rows.tsv"
  check_test "mutation 1: an unwired filter (the PII chain reads the raw source) goes RED on the wiring row" \
    row_failed "$VT_DIR/m-unwire/rows.tsv" "pii_scrub_drop_userdata reads the filter"
else
  fail "mutation 1: could not be applied or did not land (anchor drifted, so this row measured nothing)"
fi

# Mutation 2: a SECOND drop pattern for the 0-byte Connection closed shape. Needs Vector (VRL compiles only there).
if mutate second_drop; then
  if [[ "$VECTOR_AVAILABLE" -eq 1 ]]; then
    run_vector_test "$VT_DIR/m-second_drop/vector.toml" "$VT_DIR/m-second_drop/tests.toml" "$VT_DIR/m-second_drop/out"
    M2_RC=$?
    count_results "$VT_DIR/m-second_drop/out"
    grep -E '^test .* \.\.\. failed' "$VT_DIR/m-second_drop/out.clean" > "$VT_DIR/m-second_drop/failed.txt" || true
    check_test "mutation 2: a second drop on Connection closed fails the 0-byte kept-class case" \
      bash -c 'test "$1" -ne 0 && grep -qF -- "0-byte Connection closed" "$2"' _ "$M2_RC" "$VT_DIR/m-second_drop/failed.txt"
  else
    structure_rows "$VT_DIR/m-second_drop/vector.toml" "$CLOUD_INIT" "$VT_DIR/m-second_drop/tests.toml" > "$VT_DIR/m-second_drop/rows.tsv"
    check_test "mutation 2: a second drop on Connection closed goes RED on the kept-class structure row (no Vector reachable)" \
      row_failed "$VT_DIR/m-second_drop/rows.tsv" "condition names no kept class"
  fi
else
  fail "mutation 2: could not be applied or did not land (anchor drifted, so this row measured nothing)"
fi

# Mutation 2b: one drop pattern loses its anchors (a substring drop). The kept decoys must catch it.
if mutate unanchor; then
  if [[ "$VECTOR_AVAILABLE" -eq 1 ]]; then
    run_vector_test "$VT_DIR/m-unanchor/vector.toml" "$VT_DIR/m-unanchor/tests.toml" "$VT_DIR/m-unanchor/out"
    M2B_RC=$?
    count_results "$VT_DIR/m-unanchor/out"
    grep -E '^test .* \.\.\. failed' "$VT_DIR/m-unanchor/out.clean" > "$VT_DIR/m-unanchor/failed.txt" || true
    check_test "mutation 2b: an unanchored drop pattern fails the whole-line decoy cases" \
      bash -c 'test "$1" -ne 0 && grep -qF -- "merely contains the accepted-connection text" "$2"' _ "$M2B_RC" "$VT_DIR/m-unanchor/failed.txt"
  else
    structure_rows "$VT_DIR/m-unanchor/vector.toml" "$CLOUD_INIT" "$VT_DIR/m-unanchor/tests.toml" > "$VT_DIR/m-unanchor/rows.tsv"
    check_test "mutation 2b: an unanchored drop pattern goes RED on the whole-line structure row (no Vector reachable)" \
      row_failed "$VT_DIR/m-unanchor/rows.tsv" "every drop pattern is a WHOLE-line match"
  fi
else
  fail "mutation 2b: could not be applied or did not land (anchor drifted, so this row measured nothing)"
fi

# Mutation 2c: a node takes the raw terminator rows around the filter and the scrub. Structure rows only.
if mutate bypass; then
  structure_rows "$VT_DIR/m-bypass/vector.toml" "$CLOUD_INIT" "$VT_DIR/m-bypass/tests.toml" > "$VT_DIR/m-bypass/rows.tsv"
  check_test "mutation 2c: a second reader of the raw terminator source goes RED on the consumer-set row" \
    row_failed "$VT_DIR/m-bypass/rows.tsv" "the raw terminator source is read by the filter only"
else
  fail "mutation 2c: could not be applied or did not land (anchor drifted, so this row measured nothing)"
fi

# Mutation 3 (the guard's own dispatch): a fixture file that yields zero test cases must fail the floor, never pass as 0 checked.
if mutate empty_fixture; then
  structure_rows "$VECTOR_TOML" "$CLOUD_INIT" "$VT_DIR/m-empty_fixture/tests.toml" > "$VT_DIR/m-empty_fixture/rows.tsv"
  check_test "mutation 3: a fixture file with zero test cases goes RED on the case-count floor" \
    row_failed "$VT_DIR/m-empty_fixture/rows.tsv" "fixture file carries at least 21 tests"
else
  fail "mutation 3: could not be applied or did not land (anchor drifted, so this row measured nothing)"
fi

# Harness row: an extractor that finds no filter condition (the transform is renamed) must fail the extraction floor.
if mutate rename_filter; then
  structure_rows "$VT_DIR/m-rename_filter/vector.toml" "$CLOUD_INIT" "$VT_DIR/m-rename_filter/tests.toml" > "$VT_DIR/m-rename_filter/rows.tsv"
  check_test "harness row: an empty condition extraction goes RED on the extraction floor" \
    row_failed "$VT_DIR/m-rename_filter/rows.tsv" "filter condition extracted and non-trivial"
else
  fail "harness row: could not be applied or did not land (anchor drifted, so this row measured nothing)"
fi

echo ""
echo "RESULT: $PASS passed, $FAIL failed, $SKIP skipped"
# The floor is the count THIS run must reach: the engine-backed run records three more verdicts (the
# vector test rows) than the engine-less one, so a single floor sized for the smaller run lets those three
# vanish from the larger one. Each arm carries its own literal bound, on its own if, exiting inside the block.
# Raise them with the suite, derived from a green run.
if [[ "$VECTOR_AVAILABLE" -eq 1 ]]; then
  if [[ $((PASS + FAIL)) -lt 25 ]]; then
    printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 25 with an engine.\n' "$((PASS + FAIL))" >&2
    exit 1
  fi
else
  if [[ $((PASS + FAIL)) -lt 22 ]]; then
    printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 22 without an engine.\n' "$((PASS + FAIL))" >&2
    exit 1
  fi
fi
[[ "$FAIL" -eq 0 ]] || exit 1
