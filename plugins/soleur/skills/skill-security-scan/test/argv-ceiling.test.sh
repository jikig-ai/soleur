#!/usr/bin/env bash
# Argv-ceiling regression for skill-security-scan (#6736).
#
# WHAT THIS GUARDS. Two sites used to bind an unbounded payload as ONE argv argument:
#   - scripts/lib.sh   emit_result()  `--argjson f "$findings_json"`   (per category)
#   - scripts/run-scan.sh             `--argjson fs "$findings_summary"` (all five)
# The kernel caps a SINGLE argv argument at MAX_ARG_STRLEN = 131,072 B -- bisected on this
# host: 131,071 B passes, 131,072 B fails E2BIG. That is NOT `getconf ARG_MAX` (2,097,152 B
# here); a payload at 6% of ARG_MAX still dies. Both now use stdin / `--rawfile`, which is
# file-or-pipe I/O and has no per-argument limit.
#
# WHY THIS IS THE UNBOUNDED ONE. apply_yaml_rules caps each snippet at 200 chars, so it
# LOOKS bounded -- but nothing caps the FINDING COUNT: one grep hit per matching line, over
# a SKILL.md of any length. At ~265 B/finding the ceiling lands near 490 findings, and this
# repo already ships a 220,523 B SKILL.md.
#
# THE FAILURE WAS SILENT, which is why the behavioural assertions below check CONTENT and
# not just the exit code. run-scan.sh invokes each category as
# `bash check-*.sh … || echo '{"…check-failed…"}'`, so an E2BIG inside a category script is
# swallowed into a "category script error" placeholder: the scan exits 0 and reports a
# REVIEW verdict with ZERO real findings instead of the hundreds it actually found. An
# exit-code-only test passes straight through that.
#
# FIXTURE ADEQUACY. The fixture is SYNTHESIZED (cq-test-fixtures-synthesized-only) -- it is
# generated here, never copied from a real skill. It is also PRODUCTION-SHAPED: each line is
# long enough to fill the 200-char snippet window, because BYTES PER FINDING is the
# load-bearing parameter, not finding count. Short matching lines would yield ~70 B findings,
# so even thousands of them would stay under the ceiling and PASS ON UNMODIFIED CODE.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
CHECK_FS="$SCRIPTS/check-filesystem-boundary.sh"
RUN_SCAN="$SCRIPTS/run-scan.sh"

# Named at every use, never bare.
MAX_ARG_STRLEN=131072

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
[[ -f "$CHECK_FS" ]] || { echo "ERROR: not found: $CHECK_FS" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SKILL_SECURITY_SCAN_OFFLINE=1

echo "TEST: skill-security-scan argv ceiling (#6736)"

# --- Synthesized, production-shaped fixture ---------------------------------------------
# Each line trips filesystem-boundary's `path-traversal-absolute` rule (a quote followed by
# /etc/) and is padded past 200 chars so the captured snippet fills its cap. Nothing here is
# copied from a real SKILL.md.
FIXTURE="$WORK/synth.skill.md"
ROWS=900
{
  printf '# Synthesized fixture skill\n\n'
  for i in $(seq 1 "$ROWS"); do
    printf 'Line %04d config path "/etc/synthesized-fixture-%04d/a-deliberately-long-configuration-path-segment-that-fills-the-two-hundred-character-snippet-window-so-that-bytes-per-finding-not-finding-count-is-what-drives-this-fixture-over-the-ceiling"\n' "$i" "$i"
  done
} > "$FIXTURE"

# --- Generator cardinality --------------------------------------------------------------
gen_rows="$(grep -c '^Line [0-9]' "$FIXTURE")"
if [[ "$gen_rows" -eq "$ROWS" ]]; then
  pass "fixture generator emitted $gen_rows matching lines (want $ROWS)"
else
  fail "fixture generator emitted $gen_rows lines (want $ROWS) -- asserts below would be vacuous"
fi

# --- Category level: emit_result must survive a >ceiling findings array ------------------
cat_out="$(bash "$CHECK_FS" < "$FIXTURE" 2>"$WORK/cat_err.txt")"
cat_rc=$?
if [[ "$cat_rc" -eq 0 ]]; then
  pass "check-filesystem-boundary exits 0 on a >ceiling finding set"
else
  fail "check-filesystem-boundary exit=$cat_rc -- stderr: $(head -c 200 "$WORK/cat_err.txt")"
fi

# FIXTURE ADEQUACY, asserted IN-SUITE so this cannot silently degrade to vacuous as the
# rule pack, the snippet cap, or jq's encoding changes.
findings_bytes="$(printf '%s' "$cat_out" | jq -c '.findings' | wc -c)"
if [[ "$findings_bytes" -gt "$MAX_ARG_STRLEN" ]]; then
  pass "findings payload is ${findings_bytes} B > MAX_ARG_STRLEN (${MAX_ARG_STRLEN})"
else
  fail "findings payload is only ${findings_bytes} B -- below MAX_ARG_STRLEN (${MAX_ARG_STRLEN}), this test proves nothing"
fi

# Count asserted RELATIONALLY against the source line count, not a literal pin.
findings_n="$(printf '%s' "$cat_out" | jq '.findings | length')"
if [[ "$findings_n" -eq "$gen_rows" ]]; then
  pass "findings|length=$findings_n == $gen_rows source lines (no truncation)"
else
  fail "findings|length=$findings_n != $gen_rows source lines (undercount / truncation)"
fi

# The findings must really carry their rule_id and snippet -- not empty shells.
real_findings="$(printf '%s' "$cat_out" | jq '[.findings[] | select(.rule_id == "path-traversal-absolute" and (.snippet | length) > 100)] | length')"
if [[ "$real_findings" -eq "$gen_rows" ]]; then
  pass "all $real_findings findings carry rule_id + a full snippet at >ceiling size"
else
  fail "only $real_findings of $gen_rows findings carry rule_id + full snippet"
fi

# --- Aggregator level: run-scan must not degrade to the check-failed placeholder ---------
scan_out="$(bash "$RUN_SCAN" "$FIXTURE" 2>"$WORK/scan_err.txt")"
scan_rc=$?
if [[ "$scan_rc" -eq 0 ]]; then
  pass "run-scan.sh exits 0 on a >ceiling finding set"
else
  fail "run-scan.sh exit=$scan_rc -- stderr: $(head -c 200 "$WORK/scan_err.txt")"
fi

# THE ANTI-SILENT-DEGRADATION ASSERTION. Pre-fix, the E2BIG inside check-filesystem-boundary
# is swallowed by run-scan's `|| echo '{"…check-failed…"}'` fallback, so the run still exits
# 0 -- but the filesystem-boundary row is replaced by an "unknown" category carrying a single
# `check-failed` finding. Asserting on the REAL row is what makes that visible.
#
# `grep -c` on a herestring, never `producer | grep -q`: under `set -o pipefail` an early
# match closes the pipe, the producer takes SIGPIPE (141), and the pipeline reports failure
# even though grep MATCHED.
fs_row="$(grep -cE '^\| filesystem-boundary \| (REVIEW|HIGH-RISK) \| [0-9]+ \|' <<<"$scan_out")"
if [[ "$fs_row" -ge 1 ]]; then
  pass "filesystem-boundary reported as a real category row"
else
  fail "no real filesystem-boundary row -- the category silently degraded to check-failed"
fi

reported_n="$(sed -nE 's/^\| filesystem-boundary \| [A-Z-]+ \| ([0-9]+) \|.*/\1/p' <<<"$scan_out" | head -1)"
if [[ "${reported_n:-0}" -eq "$gen_rows" ]]; then
  pass "run-scan reports all $reported_n findings (== $gen_rows source lines)"
else
  fail "run-scan reports ${reported_n:-<none>} findings but fixture had $gen_rows -- silent loss"
fi

checkfailed="$(grep -c 'check-failed' <<<"$scan_out")"
if [[ "$checkfailed" -eq 0 ]]; then
  pass "no check-failed placeholder in the report"
else
  fail "report contains $checkfailed check-failed placeholder(s) -- a category died and was swallowed"
fi

if grep -qiE 'argument list too long' "$WORK/cat_err.txt" "$WORK/scan_err.txt"; then
  fail "an E2BIG diagnostic reached stderr -- argv ceiling was hit"
else
  pass "no 'Argument list too long' diagnostic on stderr"
fi

# --- Structural: neither site may rebind an unbounded payload onto argv ------------------
# Anchored on syntax a COMMENT cannot produce. Both files now carry prose mentioning
# `--argjson`, so a bare-token grep would false-pass on this fix's own documentation
# (cq-assert-anchor-not-bare-token). `-cE` with a leading `^[^#]*` restricts to code lines.
lib_argjson="$(grep -cE '^[^#]*--argjson[[:space:]]+f[[:space:]]+"\$findings_json"' "$SCRIPTS/lib.sh")"
if [[ "$lib_argjson" -eq 0 ]]; then
  pass "lib.sh does not bind \$findings_json via --argjson"
else
  fail "lib.sh rebinds \$findings_json via --argjson on $lib_argjson code line(s)"
fi

scan_argjson="$(grep -cE '^[^#]*--argjson[[:space:]]+(fs|b)[[:space:]]+"\$(findings_summary|body_redacted)"' "$RUN_SCAN")"
if [[ "$scan_argjson" -eq 0 ]]; then
  pass "run-scan.sh does not bind the summary/body via --argjson"
else
  fail "run-scan.sh rebinds an unbounded payload via --argjson on $scan_argjson code line(s)"
fi

# Positive form: the --rawfile binding must actually be present. `--rawfile\s+\w+` is
# syntax a comment cannot produce in the code position asserted here.
if grep -qE '^[^#]*--rawfile[[:space:]]+fs[[:space:]]+"\$summary_file"' "$RUN_SCAN"; then
  pass "run-scan.sh binds the summary with --rawfile"
else
  fail "run-scan.sh no longer binds the summary with --rawfile"
fi

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
