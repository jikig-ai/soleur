#!/usr/bin/env bash
# Test harness for plugins/soleur/skills/incident/scripts/redact-sentinel.sh
#
# Pattern mirrors plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh:
# - set -uo pipefail (NOT -e — single test failure must not abort the suite)
# - PASS/FAIL counter
# - trap-based cleanup
#
# Tests 1-4 are the ORIGINAL contract (redact-sentinel #2725 FR3).
# Tests 5-12 are the redaction-hardening suite (#5987): NFKC + zero-width strip
# before matching, ReDoS-safe fail-closed input cap, fail-closed on no-python3,
# ERE->re golden parity, and the legal-generate gate.
#
# All confusable / oversize / invalid-byte inputs are generated AT RUNTIME via
# `python3 -c` with chr(0xXXXX) — NEVER committed as literal invisibles
# (`cq-regex-unicode-separators-escape-only`; AC6 enforces this). All tokens are
# synthesized from format specs (`cq-test-fixtures-synthesized-only`).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../../.." && pwd)"

SENTINEL="${SKILL_DIR}/scripts/redact-sentinel.sh"
POSITIVE_CORPUS="${SCRIPT_DIR}/fixtures/positive-corpus.md"
NEGATIVE_BASELINE="${REPO_ROOT}/knowledge-base/engineering/operations/post-mortems/dashboard-error-postmortem.md"
LEGAL_SKILL="${REPO_ROOT}/plugins/soleur/skills/legal-generate/SKILL.md"

PASS=0
FAIL=0
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "PASS: ${label} (exit=${actual})"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (expected exit=${expected}, got ${actual})"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE "${pattern}" "${file}"; then
    echo "PASS: ${label} (pattern matched in ${file##*/})"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (pattern '${pattern}' not found in ${file##*/})"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test 1 — negative-baseline (clean hand-redacted PIR exits 0)
# ---------------------------------------------------------------------------
out="${TMP_DIR}/test1.out"
bash "${SENTINEL}" "${NEGATIVE_BASELINE}" >"${out}" 2>&1
assert_exit "Test 1: negative-baseline exits 0 on hand-redacted PIR" 0 $?

# ---------------------------------------------------------------------------
# Test 2 — positive-corpus: every regex class triggers >=1
# ---------------------------------------------------------------------------
out="${TMP_DIR}/test2.out"
bash "${SENTINEL}" "${POSITIVE_CORPUS}" >"${out}" 2>&1
rc=$?
assert_exit "Test 2: positive-corpus exits non-zero" 1 "${rc}"

for class in JWT email UUID stripe_key stripe_whsec stripe_acct stripe_cust_pi_seti_sub_in IPv4 env_var \
             github_token anthropic_key openai_key supabase_pat pem_private_key doppler_token slack_token; do
  assert_grep "Test 2.${class}: pattern '${class}' present" "matched pattern ${class}" "${out}"
done

# ---------------------------------------------------------------------------
# Test 3 — invalid arg -> exit 2
# ---------------------------------------------------------------------------
out="${TMP_DIR}/test3.out"
bash "${SENTINEL}" /nonexistent/path/to/file.md >"${out}" 2>&1
assert_exit "Test 3: nonexistent file exits 2" 2 $?

bash "${SENTINEL}" >"${out}" 2>&1
assert_exit "Test 3: missing arg exits 2" 2 $?

# ---------------------------------------------------------------------------
# Test 4 — output format (TIGHTENED, #5987): capped reveal, never a full token.
# Was `.{8}\*\*\*.{8}` (leaked ~50% of a fixed-prefix key). Now <=4 + *** + <=4.
# ---------------------------------------------------------------------------
out="${TMP_DIR}/test4.out"
bash "${SENTINEL}" "${POSITIVE_CORPUS}" >"${out}" 2>&1 || true
assert_grep "Test 4: capped output format 'at offset N: <=4-prefix***<=4-suffix matched pattern X'" \
  'at offset [0-9]+: .{0,4}\*\*\*(.{0,4})? matched pattern [A-Za-z_]+' "${out}"

# Test 4b — NO full-token reveal: no finding line may reveal >4 prefix chars.
if grep -qE 'at offset [0-9]+: [^*]{5,}\*\*\*' "${out}"; then
  echo "FAIL: Test 4b: a finding revealed >4 prefix chars (entropy leak regression)"
  FAIL=$((FAIL + 1))
else
  echo "PASS: Test 4b: no finding reveals >4 prefix chars (meta-redaction tightened)"
  PASS=$((PASS + 1))
fi

# ===========================================================================
# #5987 — redaction hardening suite (Tests 5-12)
# ===========================================================================

# ---------------------------------------------------------------------------
# Test 5 — compatibility-confusable + invisible-splitter evasion (AC1).
# A JWT split by ZWSP (U+200B), soft-hyphen (U+00AD), and line-sep (U+2028),
# plus a fullwidth Stripe key. (a) OLD raw-byte engine MISSES; (b) new engine CATCHES.
# Invisibles built via chr(0xXXXX) so no literal invisibles land in this file.
# ---------------------------------------------------------------------------
t5_file="${TMP_DIR}/t5.txt"
python3 -c "
import sys
def fw(s):  # ASCII printable -> fullwidth (NFKC folds back)
    return ''.join(chr(ord(c)+0xFEE0) if 0x21<=ord(c)<=0x7e else c for c in s)
jwt = 'eyJ'+'A'*12+chr(0x200b)+'.'+'B'*10+chr(0x00ad)+'BB'+'.'+'C'*10+chr(0x2028)+'CC'
stripe = fw('sk_live_0000000000000000')
sys.stdout.write(jwt+'\n'+stripe+'\n')
" > "${t5_file}"

# (a) OLD bash engine MISSES the evasive tokens. Baseline is a FROZEN copy of the pre-#5987
# grep scanner committed at fixtures/legacy-bash-scanner.sh — NOT `git show main:redact-sentinel.sh`,
# which becomes the new shim post-merge (references redact-engine.py absent from a temp dir -> exit 2,
# a merge-time time-bomb that would turn main red for the next contributor). The frozen copy is a
# self-contained pure-bash scanner and is stable across merges.
OLD_ENGINE="${SCRIPT_DIR}/fixtures/legacy-bash-scanner.sh"
bash "${OLD_ENGINE}" "${t5_file}" >/dev/null 2>&1
assert_exit "Test 5a: OLD raw-byte engine MISSES confusable/invisible-split tokens" 0 $?

# (b) new engine catches after strip + NFKC
t5_out="${TMP_DIR}/t5.out"
bash "${SENTINEL}" "${t5_file}" >"${t5_out}" 2>&1
assert_exit "Test 5b: engine catches confusable/invisible-split tokens" 1 $?
assert_grep "Test 5b.JWT: JWT class tripped after strip" "matched pattern JWT" "${t5_out}"
assert_grep "Test 5b.stripe: fullwidth Stripe key tripped after NFKC" "matched pattern stripe_key" "${t5_out}"

# Test 5c — category-based STRIP: invisible/control/format families NFKC leaves intact must all be
# stripped, not just a hand-picked list. One secret per invisible class; each must be CAUGHT (exit 1).
# NUL(Cc), DEL(Cc), variation-selector U+FE0F(Mn), Tags-block U+E0020(Cf), combining grapheme joiner
# U+034F(Mn). Splice is placed mid-token so a raw-byte matcher would miss it.
for probe in "NUL:0x00" "DEL:0x7f" "VS16:0xfe0f" "TAGSPACE:0xe0020" "CGJ:0x34f"; do
  name="${probe%%:*}"; cp="${probe##*:}"
  f="${TMP_DIR}/t5c-${name}.txt"
  python3 -c "import sys; sys.stdout.write('sk_live_0000'+chr(${cp})+'000000000000\n')" > "${f}"
  bash "${SENTINEL}" "${f}" >/dev/null 2>&1
  assert_exit "Test 5c.${name}: invisible-splice (${cp}) stripped by category, secret caught" 1 $?
done

# Test 5d — second-strip necessity (U+FFA0 halfwidth Hangul filler): NFKC folds U+FFA0 -> U+1160,
# a strippable char NOT present in the raw input. Only the post-NFKC second strip catches it. This
# pins the double-strip so a future "simplification" removing it fails loudly.
t5d_file="${TMP_DIR}/t5d.txt"
python3 -c "import sys; sys.stdout.write('sk_live_0000'+chr(0xFFA0)+'000000000000\n')" > "${t5d_file}"
bash "${SENTINEL}" "${t5d_file}" >/dev/null 2>&1
assert_exit "Test 5d: U+FFA0->U+1160 NFKC fold caught by the second strip" 1 $?

# ---------------------------------------------------------------------------
# Test 6 — oversize -> synthetic HIGH (AC2). Cap lowered via env for speed.
# ---------------------------------------------------------------------------
t6_file="${TMP_DIR}/t6.txt"
head -c 2048 /dev/zero | tr '\0' 'a' > "${t6_file}"   # 2048 bytes of 'a', no secret
t6_out="${TMP_DIR}/t6.out"
REDACT_MAX_INPUT_BYTES=1024 bash "${SENTINEL}" "${t6_file}" >"${t6_out}" 2>&1
assert_exit "Test 6: raw-oversize input exits 1 (synthetic HIGH)" 1 $?
assert_grep "Test 6: synthetic-HIGH marker present" "SYNTHETIC HIGH" "${t6_out}"
if grep -qE 'matched pattern' "${t6_out}"; then
  echo "FAIL: Test 6: per-class matching ran on oversize input (should short-circuit)"
  FAIL=$((FAIL + 1))
else
  echo "PASS: Test 6: no per-class matching on oversize input (fail-fast)"
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# Test 6b — expansion bomb (AC2): raw < cap but NFKC-expanded > cap.
# U+FDFA NFKC-expands to 18 codepoints. Built via chr(0xFDFA).
# ---------------------------------------------------------------------------
t6b_file="${TMP_DIR}/t6b.txt"
python3 -c "import sys; sys.stdout.write(chr(0xFDFA)*40)" > "${t6b_file}"  # raw ~120 bytes
t6b_raw=$(wc -c < "${t6b_file}")
t6b_out="${TMP_DIR}/t6b.out"
REDACT_MAX_INPUT_BYTES=200 bash "${SENTINEL}" "${t6b_file}" >"${t6b_out}" 2>&1
t6b_rc=$?
echo "  (Test 6b: raw=${t6b_raw} bytes < cap=200; NFKC-expanded > cap)"
assert_exit "Test 6b: NFKC-expansion-oversize exits 1 (post-NFKC re-check)" 1 "${t6b_rc}"
assert_grep "Test 6b: synthetic-HIGH marker present" "SYNTHETIC HIGH" "${t6b_out}"

# ---------------------------------------------------------------------------
# Test 7 — invalid-UTF-8 splice (AC1b): a secret with an invalid byte spliced in
# (-> U+FFFD) is caught after the strip.
# ---------------------------------------------------------------------------
t7_file="${TMP_DIR}/t7.txt"
python3 -c "
import sys
sys.stdout.buffer.write(b'sk_live_0000' + b'\x80' + b'0000000000000000\n')
" > "${t7_file}"
t7_out="${TMP_DIR}/t7.out"
bash "${SENTINEL}" "${t7_file}" >"${t7_out}" 2>&1
assert_exit "Test 7: invalid-UTF-8-spliced secret caught after strip" 1 $?
assert_grep "Test 7: stripe_key tripped post-strip" "matched pattern stripe_key" "${t7_out}"

# ---------------------------------------------------------------------------
# Test 8 — no false positives: clean baselines still exit 0 after normalization.
# ---------------------------------------------------------------------------
bash "${SENTINEL}" "${NEGATIVE_BASELINE}" >/dev/null 2>&1
assert_exit "Test 8a: normalization does not manufacture matches on clean PIR" 0 $?
t8_file="${TMP_DIR}/t8.txt"
python3 -c "import sys; sys.stdout.write('Privet clean prose ' + chr(0x043f)+chr(0x0440)+' no secrets.\n')" > "${t8_file}"
bash "${SENTINEL}" "${t8_file}" >/dev/null 2>&1
assert_exit "Test 8b: Cyrillic prose without secrets exits 0 (fold != fabricate)" 0 $?

# ---------------------------------------------------------------------------
# Test 9 — golden ERE<->re parity (AC3): every class the OLD bash engine catches
# on the corpus, the NEW engine also catches (no class narrowed by the port).
# New additive classes (doppler/slack) are a superset and do not break parity.
# ---------------------------------------------------------------------------
old_hits="${TMP_DIR}/old_hits.txt"
new_hits="${TMP_DIR}/new_hits.txt"
# LC_ALL=C on BOTH sort and comm: comm requires byte-collation order; a locale sort (en_US) collates
# case-insensitively so comm sees "unsorted input" and its diff is undefined — the parity guard would
# run blind. Byte-sort both streams and byte-compare.
bash "${OLD_ENGINE}" "${POSITIVE_CORPUS}" 2>/dev/null | grep -oE 'matched pattern [A-Za-z_]+' | LC_ALL=C sort -u > "${old_hits}"
bash "${SENTINEL}"   "${POSITIVE_CORPUS}" 2>/dev/null | grep -oE 'matched pattern [A-Za-z_]+' | LC_ALL=C sort -u > "${new_hits}"
missing=$(LC_ALL=C comm -23 "${old_hits}" "${new_hits}")
if [[ -z "${missing}" ]]; then
  echo "PASS: Test 9: golden parity — new engine catches every class the old engine did"
  PASS=$((PASS + 1))
else
  echo "FAIL: Test 9: new engine NARROWED these classes vs old: ${missing//$'\n'/, }"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Test 10 — fail-closed on no-python3 (AC4): shim exits 2 (not 0, not 1) with
# python3 shadowed off PATH. `dirname` symlinked so the shim can still resolve DIR.
# ---------------------------------------------------------------------------
nopy="${TMP_DIR}/nopy"
mkdir -p "${nopy}"
ln -s "$(command -v dirname)" "${nopy}/dirname"
BASH_BIN="$(command -v bash)"   # absolute path — parent must NOT PATH-search under the stripped PATH
t10_file="${TMP_DIR}/t10.txt"
printf 'sk_test_0000000000000000\n' > "${t10_file}"
PATH="${nopy}" "${BASH_BIN}" "${SENTINEL}" "${t10_file}" >/dev/null 2>&1
assert_exit "Test 10: no-python3 fails closed with exit 2" 2 $?

# ---------------------------------------------------------------------------
# Test 11 — legal-generate gate (AC5): a synthesized secret in a legal draft
# mktemp makes the sentinel exit non-zero; and the SKILL.md wires the gate
# BEFORE the inline presentation step.
# ---------------------------------------------------------------------------
t11_file="${TMP_DIR}/legal-draft.md"
printf '# Privacy Policy (DRAFT)\n\nContact: STRIPE_SECRET_KEY=sk_live_0000000000000000\n' > "${t11_file}"
bash "${SENTINEL}" "${t11_file}" >/dev/null 2>&1
assert_exit "Test 11a: legal draft with secret trips the sentinel (non-zero)" 1 $?
assert_grep "Test 11b: legal-generate SKILL.md wires redact-sentinel.sh" \
  'redact-sentinel\.sh' "${LEGAL_SKILL}"
# The gate block must appear BEFORE the presentation step. Anchor on the stable structural heading
# `## Phase 3` (where the Accept/Edit/Reject presentation lives) rather than brittle label prose —
# a reworded decision-gate label must not silently empty the check.
gate_line=$(grep -nE 'redact-sentinel\.sh' "${LEGAL_SKILL}" 2>/dev/null | head -1 | cut -d: -f1)
present_line=$(grep -nE '^## Phase 3' "${LEGAL_SKILL}" 2>/dev/null | head -1 | cut -d: -f1)
if [[ -n "${gate_line}" && -n "${present_line}" && "${gate_line}" -lt "${present_line}" ]]; then
  echo "PASS: Test 11c: redaction gate precedes inline presentation (Phase 3) in legal-generate SKILL.md"
  PASS=$((PASS + 1))
else
  echo "FAIL: Test 11c: redaction gate must precede Phase 3 presentation (gate=${gate_line:-none}, phase3=${present_line:-none})"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Test 12 — cross-script homoglyph honesty (AC1): a CONFUSABLE_MAP-covered prefix
# (Cyrillic s U+0455) is caught; an UNMAPPED lookalike (Cyrillic t U+0442) is a
# version-controlled KNOWN GAP (current behavior = exit 0, not claimed covered).
# ---------------------------------------------------------------------------
t12_cov="${TMP_DIR}/t12-covered.txt"
python3 -c "import sys; sys.stdout.write(chr(0x0455)+'k-ant-' + 'A'*32 + '\n')" > "${t12_cov}"  # Cyrillic s -> s
bash "${SENTINEL}" "${t12_cov}" >/dev/null 2>&1
assert_exit "Test 12a: CONFUSABLE_MAP-covered homoglyph prefix is caught (exit 1)" 1 $?

t12_gap="${TMP_DIR}/t12-gap.txt"
python3 -c "import sys; sys.stdout.write('sk-an'+chr(0x0442)+'-' + 'A'*32 + '\n')" > "${t12_gap}"  # Cyrillic t -> UNMAPPED
bash "${SENTINEL}" "${t12_gap}" >/dev/null 2>&1
assert_exit "Test 12b: UNMAPPED homoglyph is a version-controlled known gap (exit 0)" 0 $?

# ---------------------------------------------------------------------------
# AC6 — no literal invisibles committed anywhere in the two touched skills.
# ---------------------------------------------------------------------------
if grep -rlP '[\x{200b}\x{200c}\x{200d}\x{2060}\x{feff}\x{202a}-\x{202e}\x{2028}\x{2029}\x{00ad}\x{fffd}]' \
     "${REPO_ROOT}/plugins/soleur/skills/incident" \
     "${REPO_ROOT}/plugins/soleur/skills/legal-generate" 2>/dev/null | grep -q .; then
  echo "FAIL: AC6: literal invisibles committed (must be chr()/escapes only)"
  grep -rlP '[\x{200b}\x{200c}\x{200d}\x{2060}\x{feff}\x{202a}-\x{202e}\x{2028}\x{2029}\x{00ad}\x{fffd}]' \
     "${REPO_ROOT}/plugins/soleur/skills/incident" \
     "${REPO_ROOT}/plugins/soleur/skills/legal-generate" 2>/dev/null
  FAIL=$((FAIL + 1))
else
  echo "PASS: AC6: no literal invisibles committed in incident/legal-generate skills"
  PASS=$((PASS + 1))
fi

echo
echo "Total: ${PASS} pass, ${FAIL} fail"
[[ "${FAIL}" -eq 0 ]]
