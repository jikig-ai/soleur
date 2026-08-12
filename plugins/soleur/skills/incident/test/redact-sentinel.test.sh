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
             github_token anthropic_key openai_key supabase_pat pem_private_key doppler_token slack_token \
             cloudflare_token; do
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

# ===========================================================================
# #6045 PR-B — item 1 (whitespace/newline reflow re-scan) + item 6 (Cloudflare token).
# All fixtures synthesized at runtime; invisibles/newlines via chr() (AC6).
# ===========================================================================

# Test 13 — reflow two-engine (item 1, AC1 shape): a stripe key split by a NEWLINE.
# (a) OLD raw-byte engine MISSES the split token (exit 0); (b) the new engine's base pass also
# cannot match across the kept newline — only _scan_reflow catches it after whitespace-rejoin.
# stripe_key is a pre-#5987 class the OLD engine already carries, so 13a isolates the SPLIT-evasion.
t13_file="${TMP_DIR}/t13.txt"
python3 -c "import sys; sys.stdout.write('key sk_live_0000ABCD'+chr(0x0a)+'1234000000000000 end'+chr(0x0a))" > "${t13_file}"
bash "${OLD_ENGINE}" "${t13_file}" >/dev/null 2>&1
assert_exit "Test 13a: OLD raw-byte engine MISSES newline-split stripe key" 0 $?
t13_out="${TMP_DIR}/t13.out"
bash "${SENTINEL}" "${t13_file}" >"${t13_out}" 2>&1
assert_exit "Test 13b: reflow catches newline-split stripe key" 1 $?
assert_grep "Test 13b: stripe_key via whitespace-rejoin" "matched pattern stripe_key" "${t13_out}"

# Test 13c — reflow with a SPACE split (distinct whitespace kind from 13b's newline). A doppler
# token split by an ASCII space (0x20 survives normalization). Must be caught.
t13c_file="${TMP_DIR}/t13c.txt"
python3 -c "import sys; sys.stdout.write('tok dp.st.ABCD1234 EFGH5678IJKLMNOP done'+chr(0x0a))" > "${t13c_file}"
bash "${SENTINEL}" "${t13c_file}" >/dev/null 2>&1
assert_exit "Test 13c: reflow catches space-split doppler token" 1 $?

# Test 13d — reflow NO-FALSE-POSITIVE on an INCLUDED prefix (spec-flow highest-value guard):
# an included distinctive prefix (dp.st.) followed by DESPACEABLE PROSE must NOT manufacture a
# match. Naive whitespace-strip would glue the prose into a 16+ run; the bounded-split guard
# (rejoin across few runs only; prose has a run every few chars) rejects it. Must exit 0.
t13d_file="${TMP_DIR}/t13d.txt"
python3 -c "import sys; sys.stdout.write('note dp.st. the quick brown fox ran far away today ok'+chr(0x0a))" > "${t13d_file}"
bash "${SENTINEL}" "${t13d_file}" >/dev/null 2>&1
assert_exit "Test 13d: reflow does NOT manufacture a match from prose after an included prefix" 0 $?

# Test 13e — negative baseline still clean after the reflow pass (no manufactured matches).
bash "${SENTINEL}" "${NEGATIVE_BASELINE}" >/dev/null 2>&1
assert_exit "Test 13e: reflow pass does not manufacture matches on the clean PIR" 0 $?

# Test 13f — Test-4b invariant (meta-redaction) holds on a REFLOW-caught finding (new emit path).
t13f_out="${TMP_DIR}/t13f.out"
bash "${SENTINEL}" "${t13_file}" >"${t13f_out}" 2>&1 || true
if grep -qE 'matched pattern stripe_key \(whitespace-rejoin\)' "${t13f_out}" && \
   ! grep -qE 'at offset [0-9]+: [^*]{5,}\*\*\*' "${t13f_out}"; then
  echo "PASS: Test 13f: reflow finding is tagged and meta-redacted (<=4-char reveal)"
  PASS=$((PASS + 1))
else
  echo "FAIL: Test 13f: reflow finding missing tag or leaked >4 prefix chars"
  cat "${t13f_out}"
  FAIL=$((FAIL + 1))
fi

# Test 14 — Cloudflare token (item 6): a 40-char [A-Za-z0-9_-] token containing BOTH an uppercase
# letter AND a digit trips cloudflare_token. Synthesized (no real token).
t14_file="${TMP_DIR}/t14.txt"
python3 -c "import sys; sys.stdout.write('CF_TOKEN v1.0 Ab3'+'x'*37+' end'+chr(0x0a))" > "${t14_file}"
t14_out="${TMP_DIR}/t14.out"
bash "${SENTINEL}" "${t14_file}" >"${t14_out}" 2>&1
assert_exit "Test 14: 40-char upper+digit token trips cloudflare_token" 1 $?
assert_grep "Test 14: cloudflare_token matched" "matched pattern cloudflare_token" "${t14_out}"

# Test 14b — anti-SHA NO-FALSE-POSITIVE: a 40-char lowercase-hex git SHA (digit, NO uppercase)
# must NOT trip. Incident PIRs cite commit SHAs constantly.
t14b_file="${TMP_DIR}/t14b.txt"
python3 -c "import sys; sys.stdout.write('commit '+'a1b2c3d4'*5+' shipped'+chr(0x0a))" > "${t14b_file}"
t14b_out="${TMP_DIR}/t14b.out"
bash "${SENTINEL}" "${t14b_file}" >"${t14b_out}" 2>&1
if grep -qE 'matched pattern cloudflare_token' "${t14b_out}"; then
  echo "FAIL: Test 14b: a 40-char git SHA falsely tripped cloudflare_token"
  FAIL=$((FAIL + 1))
else
  echo "PASS: Test 14b: 40-char lowercase-hex git SHA does NOT trip cloudflare_token (anti-SHA predicate)"
  PASS=$((PASS + 1))
fi

# Test 14c — anti-prose NO-FALSE-POSITIVE: a 40-char kebab-case identifier span (NO uppercase, NO
# digit) must NOT trip.
t14c_file="${TMP_DIR}/t14c.txt"
python3 -c "import sys; sys.stdout.write('rule cq-'+'-'.join(['abc']*9)+' xx'+chr(0x0a))" > "${t14c_file}"
t14c_out="${TMP_DIR}/t14c.out"
bash "${SENTINEL}" "${t14c_file}" >"${t14c_out}" 2>&1
if grep -qE 'matched pattern cloudflare_token' "${t14c_out}"; then
  echo "FAIL: Test 14c: a 40-char kebab span falsely tripped cloudflare_token"
  FAIL=$((FAIL + 1))
else
  echo "PASS: Test 14c: 40-char kebab prose does NOT trip cloudflare_token"
  PASS=$((PASS + 1))
fi

# Test 14d — negative baseline still clean with cloudflare_token added (cites SHAs).
bash "${SENTINEL}" "${NEGATIVE_BASELINE}" >/dev/null 2>&1
assert_exit "Test 14d: cloudflare_token class does not manufacture matches on the clean PIR" 0 $?

# ===========================================================================
# #6045 PR-C — item 2 (base64/hex/percent decode-and-rescan) + item 3 (headerless-PEM
# private-key DER discriminator). DER fixtures are SYNTHESIZED from the ASN.1 spec (no
# key material) so they exercise the discriminator branches directly.
# ===========================================================================

# DER shape helpers (Python): seq() wraps content in a SEQUENCE with correct short/long-form length.
_DER_PY='
import base64, sys
def seq(content):
    n = len(content)
    if n < 0x80: length = bytes([n])
    elif n < 0x100: length = bytes([0x81, n])
    else: length = bytes([0x82, n >> 8, n & 0xFF])
    return bytes([0x30]) + length + content
def b64(b): return base64.b64encode(b).decode()
# private-key-shaped, SHORT-form length (EC/Ed25519 size): SEQUENCE{ INTEGER 1, OCTET STRING(44) }
priv_short = seq(bytes([0x02,0x01,0x01]) + bytes([0x04,0x2C]) + b"\x00"*44)
# private-key-shaped, LONG-form length (RSA size): SEQUENCE{ INTEGER 0, OCTET STRING(300) }
priv_long  = seq(bytes([0x02,0x01,0x00]) + bytes([0x04,0x82,0x01,0x2C]) + b"\x00"*300)
# cert/SPKI/encrypted-PKCS#8 shape: SEQUENCE{ SEQUENCE(44) } — first inner is SEQUENCE, must REJECT
cert_like  = seq(seq(b"\x00"*44))
# PNG magic (0x89) — not a SEQUENCE, must REJECT
png        = bytes([0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A]) + b"\x00"*56
'

# Test 15 — item 3 private-key DER discriminator POSITIVES (short + long form).
t15a="${TMP_DIR}/t15a.txt"
python3 -c "${_DER_PY}
sys.stdout.write('k8s data: ' + b64(priv_short) + '\n')" > "${t15a}"
bash "${SENTINEL}" "${t15a}" >${TMP_DIR}/t15a.out 2>&1
assert_exit "Test 15a: short-form (EC/Ed25519-size) headerless private-key DER caught" 1 $?
assert_grep "Test 15a: pem_key_body" "matched pattern pem_key_body" ${TMP_DIR}/t15a.out

t15b="${TMP_DIR}/t15b.txt"
python3 -c "${_DER_PY}
sys.stdout.write('blob ' + b64(priv_long) + '\n')" > "${t15b}"
bash "${SENTINEL}" "${t15b}" >/dev/null 2>&1
assert_exit "Test 15b: long-form (RSA-size) headerless private-key DER caught" 1 $?

# Test 15c — item 3 with a 64-char-WRAPPED body (real PEM bodies are line-wrapped): block assembly
# must join consecutive base64 lines before decoding.
t15c="${TMP_DIR}/t15c.txt"
python3 -c "${_DER_PY}
b = b64(priv_long)
wrapped = '\n'.join(b[i:i+64] for i in range(0, len(b), 64))
sys.stdout.write('-- body --\n' + wrapped + '\n-- end --\n')" > "${t15c}"
bash "${SENTINEL}" "${t15c}" >/dev/null 2>&1
assert_exit "Test 15c: 64-char-wrapped headerless private-key body caught via block assembly" 1 $?

# Test 15d — item 3 NO-FALSE-POSITIVE: cert/SPKI/encrypted-PKCS#8 shape (inner SEQUENCE) must NOT
# trip pem_key_body — a public cert pasted into a legal draft is legitimate; flagging it fail-closes.
t15d="${TMP_DIR}/t15d.txt"
python3 -c "${_DER_PY}
sys.stdout.write('cert ' + b64(cert_like) + '\n')" > "${t15d}"
bash "${SENTINEL}" "${t15d}" >${TMP_DIR}/t15d.out 2>&1
if grep -qE 'matched pattern pem_key_body' ${TMP_DIR}/t15d.out; then
  echo "FAIL: Test 15d: a public-cert-shaped DER (inner SEQUENCE) falsely tripped pem_key_body"; FAIL=$((FAIL + 1))
else
  echo "PASS: Test 15d: cert/SPKI/encrypted-PKCS#8 shape does NOT trip pem_key_body (private-key discriminator)"; PASS=$((PASS + 1))
fi

# Test 15e — item 3 NO-FALSE-POSITIVE: a PNG image body (0x89 magic) must NOT trip pem_key_body.
t15e="${TMP_DIR}/t15e.txt"
python3 -c "${_DER_PY}
sys.stdout.write('img ' + b64(png) + '\n')" > "${t15e}"
bash "${SENTINEL}" "${t15e}" >${TMP_DIR}/t15e.out 2>&1
if grep -qE 'matched pattern pem_key_body' ${TMP_DIR}/t15e.out; then
  echo "FAIL: Test 15e: a PNG body falsely tripped pem_key_body"; FAIL=$((FAIL + 1))
else
  echo "PASS: Test 15e: PNG image body does NOT trip pem_key_body"; PASS=$((PASS + 1))
fi

# Test 16 — item 2 decode-and-rescan POSITIVES (base64, base64url, hex, percent) of a known secret.
_SECRET_PY='
import base64, urllib.parse, binascii, sys
# Split across concatenation so no contiguous sk_live_<24+> literal exists in source (GitHub push
# protection scans the raw file; cq-test-fixtures-synthesized-only). 38B body -> base64 is 52 chars
# (not 40 -> no cloudflare_token collision in the decode test).
s = b"sk_" + b"live_0000ABCD1234567890abcdefXYZ789"
b64s   = base64.b64encode(s).decode()
b64url = base64.urlsafe_b64encode(s).decode()
hexs   = s.hex()
pcts   = urllib.parse.quote(s.decode())
'
for enc in b64s b64url hexs pcts; do
  f="${TMP_DIR}/t16-${enc}.txt"
  python3 -c "${_SECRET_PY}
sys.stdout.write('payload: ' + ${enc} + ' trailer\n')" > "${f}"
  bash "${SENTINEL}" "${f}" >${TMP_DIR}/t16.out 2>&1
  assert_exit "Test 16.${enc}: encoded stripe key decoded and caught" 1 $?
  assert_grep "Test 16.${enc}: stripe_key via decode" "matched pattern stripe_key" ${TMP_DIR}/t16.out
done

# Test 16b — decode NO-FALSE-POSITIVE corpus: innocent encoded content must NOT manufacture a match.
#  (i) base64 of a PNG image; (ii) an SRI sha512- hash; (iii) a git SHA / sha256 hex; (iv) a base64
#  JWT-payload-shaped JSON containing an email (email is decode-skipped → must stay clean); (v) a
#  percent-encoded URL.
t16b="${TMP_DIR}/t16b.txt"
python3 -c "
import base64, sys
png = bytes([0x89,0x50,0x4E,0x47]) + bytes(range(60))
sri = 'sha512-' + base64.b64encode(bytes(range(64))).decode()
jwtjson = base64.urlsafe_b64encode(b'{\"sub\":\"1\",\"email\":\"a@b.com\"}').decode()
sys.stdout.write('image ' + base64.b64encode(png).decode() + '\n')
sys.stdout.write('integrity ' + sri + '\n')
sys.stdout.write('commit ' + 'ab'*20 + ' sha256 ' + 'cd'*32 + '\n')
sys.stdout.write('token ' + jwtjson + '\n')
sys.stdout.write('url https://x.example/a%2Fb%2Fc?q=1 done\n')
" > "${t16b}"
bash "${SENTINEL}" "${t16b}" >${TMP_DIR}/t16b.out 2>&1
if [[ $? -eq 0 ]]; then
  echo "PASS: Test 16b: innocent encoded content (image/SRI/SHA/JWT-JSON-email/percent-URL) does NOT manufacture a match"; PASS=$((PASS + 1))
else
  echo "FAIL: Test 16b: decode pass manufactured a false positive on innocent encoded content"; cat ${TMP_DIR}/t16b.out; FAIL=$((FAIL + 1))
fi

# Test 16c — malformed base64 candidate must NOT bubble to the exit-2 catch-all (per-candidate guard).
# A real secret alongside a malformed blob must still be caught (exit 1), not fail-closed to exit 2.
t16c="${TMP_DIR}/t16c.txt"
python3 -c "
import base64, sys
good = base64.b64encode(b'sk_' + b'live_0000ABCD1234567890abXY').decode()  # split literal: gitleaks stripe rule (cq-test-fixtures-synthesized-only)
sys.stdout.write('bad !!!====notbase64==== ' + good + ' end\n')
" > "${t16c}"
bash "${SENTINEL}" "${t16c}" >/dev/null 2>&1
assert_exit "Test 16c: malformed base64 candidate skipped per-candidate (real secret still caught, exit 1 not 2)" 1 $?

# Test 16d — Test-4b invariant on a DECODE-caught finding (new emit path).
bash "${SENTINEL}" "${TMP_DIR}/t16-b64s.txt" >${TMP_DIR}/t16d.out 2>&1 || true
if grep -qE 'matched pattern stripe_key \(decoded' ${TMP_DIR}/t16d.out && \
   ! grep -qE 'at offset [0-9]+: [^*]{5,}\*\*\*' ${TMP_DIR}/t16d.out; then
  echo "PASS: Test 16d: decode finding is tagged and meta-redacted (<=4-char reveal)"; PASS=$((PASS + 1))
else
  echo "FAIL: Test 16d: decode finding missing tag or leaked >4 prefix chars"; cat ${TMP_DIR}/t16d.out; FAIL=$((FAIL + 1))
fi

# Test 16e — behavioral fan-out bound: a base64-run-flooded input completes without hanging and
# exits cleanly (no manufactured matches); pins _MAX_ENCODED_CANDIDATES against a future cap removal.
t16e="${TMP_DIR}/t16e.txt"
python3 -c "import sys; sys.stdout.write((('QUJDREVGR0hJSktMTU5PUFFSU1Q ')*5000))" > "${t16e}"
timeout 30 bash "${SENTINEL}" "${t16e}" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 || $rc -eq 1 ]]; then
  echo "PASS: Test 16e: base64-flooded input completes within bound (rc=${rc}, not a timeout)"; PASS=$((PASS + 1))
else
  echo "FAIL: Test 16e: base64-flooded input did not complete (rc=${rc} — possible unbounded fan-out)"; FAIL=$((FAIL + 1))
fi

# Test 15f — item 3 with an INDENTED, 32-col-wrapped body (the real k8s Secret / Helm `data:` shape):
# block assembly must .strip() each line so indented base64 assembles. (#6045 review F2)
t15f="${TMP_DIR}/t15f.txt"
python3 -c "${_DER_PY}
b = b64(priv_long)
wrapped = '\n'.join('    ' + b[i:i+32] for i in range(0, len(b), 32))  # 4-space indent, 32-col
sys.stdout.write('data:\n  tls.key: |\n' + wrapped + '\n')" > "${t15f}"
bash "${SENTINEL}" "${t15f}" >/dev/null 2>&1
assert_exit "Test 15f: indented 32-col-wrapped k8s Secret private-key body caught via block assembly" 1 $?

# Test 16f — decode NO-FALSE-POSITIVE on a BINARY asset: a base64'd mostly-non-printable blob that
# carries an INCIDENTAL sk- run must NOT fail-close (the printable-text gate skips binary). (#6045 review F4)
t16f="${TMP_DIR}/t16f.txt"
python3 -c "
import base64, sys
# 200 high bytes (a font/wasm/image shape) with an incidental 'sk-...' run spliced in.
blob = bytes(range(0x80, 0x100)) * 2 + b'sk-A1b2C3d4E5f6G7h8I9j0' + bytes(range(0x80, 0x100))
sys.stdout.write('embedded asset: ' + base64.b64encode(blob).decode() + ' end\n')
" > "${t16f}"
bash "${SENTINEL}" "${t16f}" >${TMP_DIR}/t16f.out 2>&1
if [[ $? -eq 0 ]]; then
  echo "PASS: Test 16f: a base64 binary asset with an incidental sk- run does NOT fail-close (printable-text gate)"; PASS=$((PASS + 1))
else
  echo "FAIL: Test 16f: decode pass fail-closed a legitimate binary asset (over-redaction FP)"; cat ${TMP_DIR}/t16f.out; FAIL=$((FAIL + 1))
fi

# Test 17 — email-class ReDoS bound (#6045 security review P1): a large run of email-class chars with
# NO '@' must complete quickly (bounded quantifier → linear), not hang the fail-closed gate. 256 KiB of
# 'a' at the pre-fix O(n^2) rate timed out (>2 min); bounded it returns in well under the 20s ceiling.
t17="${TMP_DIR}/t17.txt"
python3 -c "import sys; sys.stdout.write('a'*262144)" > "${t17}"
timeout 20 bash "${SENTINEL}" "${t17}" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 || $rc -eq 1 ]]; then
  echo "PASS: Test 17: 256 KiB email-class flood completes within 20s (email quantifier bounded — no O(n^2) ReDoS)"; PASS=$((PASS + 1))
else
  echo "FAIL: Test 17: email-class flood did not complete (rc=${rc} — O(n^2) ReDoS regression)"; FAIL=$((FAIL + 1))
fi

# Test 18 — deployed-anchor coupling, RETARGETED and STRENGTHENED (#7450; was #6156 review P2).
#
# The original pinned the two redact-sentinel call sites byte-identical to each other, which is
# necessary and was never sufficient: two files can agree perfectly on an anchor that resolves
# into the reviewed party's tree. A naive `ANCHOR` swap would have preserved only that weak
# property and left the corpus unguarded, so this now asserts THREE things
# (`cq-assert-anchor-not-bare-token`).
INCIDENT_SKILL="${SKILL_DIR}/SKILL.md"
LINEAR_SKILL="${REPO_ROOT}/plugins/soleur/skills/linear-fetch/SKILL.md"

# 18a — coupling (preserved): the bare literal appears exactly 1x in each site.
ANCHOR='${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh'
lg_anchor=$(grep -Fc "${ANCHOR}" "${LEGAL_SKILL}" 2>/dev/null || true)
inc_anchor=$(grep -Fc "${ANCHOR}" "${INCIDENT_SKILL}" 2>/dev/null || true)
if [[ "${lg_anchor}" == "1" && "${inc_anchor}" == "1" ]]; then
  echo "PASS: Test 18a: bare deployed-anchor redact-sentinel literal is byte-identical (1×) in both legal-generate & incident SKILL.md"
  PASS=$((PASS + 1))
else
  echo "FAIL: Test 18a: deployed-anchor drift — expected the ADR-179 bare anchored redact-sentinel literal exactly once in each (legal-generate=${lg_anchor}, incident=${inc_anchor})"
  FAIL=$((FAIL + 1))
fi

# 18b — the ADR-179 decision-2 identity preflight is present at every secret-gate site.
# Anchored on the manifest name check, which a prose sentence cannot produce; a bare token like
# "preflight" or "CLAUDE_PLUGIN_ROOT" would be satisfied by a comment ABOUT the guard.
# `[[ -r ]]` does NOT satisfy this: ADR-179 §(a) measured a shape check passing while an
# attacker-chosen payload executed.
PREFLIGHT_NEEDLE='grep -q '"'"'"name"[[:space:]]*:[[:space:]]*"soleur"'"'"''
missing_preflight=""
unbound_halt=""

# STRENGTHENED, not cut (#7450 review). Guard 1 asserts the same property in
# TypeScript, but `scripts/test-all.sh` shards the two suites separately — Guard 1
# with the web-platform group, this file with the scripts group — so they do not
# always run together and neither is redundant with the other.
#
# Presence of the manifest check was never the property worth asserting: every gate
# carries a SECOND fail-closed check (`[[ -r "$SENTINEL" ]] || { …; exit 2; }`)
# immediately below, so "the file contains a preflight AND contains an exit 2" is
# satisfied with the preflight's own arm converted to a no-op. This now requires the
# halt to sit inside the preflight's OWN brace group, tracked by brace depth.
preflight_halts_in_own_arm() {
  awk '
    index($0, "\"${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json\"") && !started { started = 1 }
    started {
      stmt = stmt $0 "\n"
      n = gsub(/\{/, "{"); depth += n
      n = gsub(/\}/, "}"); depth -= n
      # Statement ends when braces balance and no continuation is pending.
      if (depth <= 0 && $0 !~ /\\[[:space:]]*$/) {
        print (stmt ~ /exit 2/) ? "BOUND" : "UNBOUND"
        exit
      }
    }
    END { if (!started) print "ABSENT" }
  ' "$1"
}

for gate_file in "${INCIDENT_SKILL}" "${LEGAL_SKILL}" "${LINEAR_SKILL}"; do
  n=$(grep -Fc "${PREFLIGHT_NEEDLE}" "${gate_file}" 2>/dev/null || true)
  if [[ "${n}" -lt 1 ]]; then
    missing_preflight="${missing_preflight} ${gate_file##*/skills/}"
    continue
  fi
  verdict="$(preflight_halts_in_own_arm "${gate_file}")"
  [[ "${verdict}" == "BOUND" ]] || unbound_halt="${unbound_halt} ${gate_file##*/skills/}(${verdict})"
done

if [[ -z "${missing_preflight}" && -z "${unbound_halt}" ]]; then
  echo "PASS: Test 18b: identity preflight present at all 3 secret-gate sites, and each HALTS IN ITS OWN ARM"
  PASS=$((PASS + 1))
else
  [[ -n "${missing_preflight}" ]] && echo "FAIL: Test 18b: identity preflight missing at:${missing_preflight} — the bare anchor is NOT safe by construction; the preflight is what carries it (ADR-179 decision 2)"
  [[ -n "${unbound_halt}" ]] && echo "FAIL: Test 18b: identity preflight present but its own arm does not exit 2 at:${unbound_halt} — a sibling halt elsewhere in the fence does not make THIS check fail-closed"
  FAIL=$((FAIL + 1))
fi

# 18c — corpus-wide negative. This single assertion mechanically closes ADR-179 §R5 and stops the
# rejected form reappearing ANYWHERE under the payload, which per-file counts structurally cannot
# do. The needle is built by concatenation so this file does not match its own assertion — the
# same reason the suite splits token-shaped fixtures.
#
# The split point sits INSIDE the rev-parse argument, not at the variable-name boundary. Splitting
# at the boundary leaves the shorter default-arm substring contiguous, and that shorter form is the
# needle this PR's own AC1 sweep greps for — so the file would report ITSELF as an unmigrated site
# while its own assertion passed. Do not restore the literal to this comment for readability: a
# body-grep cannot tell an explanation from an occurrence.
FORBIDDEN='${CLAUDE_PLUGIN_ROOT:-$(git rev-parse ''--show-toplevel)'
SEARCH_ROOT="${REPO_ROOT}/plugins/soleur/"

# ANTI-VACUITY FLOOR (#7450 review-finding A12). `grep -r` on a nonexistent root exits
# 2, `|| true` swallows it, `residual` is empty and the assertion reports a clean
# corpus — a PASS that means "the scan could not run", which is the one outcome a
# corpus-wide negative must never render as good. Two positive controls: the root must
# exist, and a literal KNOWN to be present must actually be found. If the apparatus is
# broken, the control fails loudly instead of the negative passing quietly.
control_hits=$(grep -rlF '${CLAUDE_PLUGIN_ROOT}' "${SEARCH_ROOT}" 2>/dev/null | grep -c . || true)
if [[ ! -d "${SEARCH_ROOT}" ]]; then
  echo "FAIL: Test 18c: search root ${SEARCH_ROOT} does not exist — the corpus-wide negative cannot be evaluated (a vacuous PASS is not a clean corpus)"
  FAIL=$((FAIL + 1))
elif [[ "${control_hits}" -lt 10 ]]; then
  echo "FAIL: Test 18c: positive control found only ${control_hits} files containing the bare anchor under ${SEARCH_ROOT} — expected >=10; the scan apparatus is broken, so its empty result proves nothing"
  FAIL=$((FAIL + 1))
else
  residual=$(grep -rlF "${FORBIDDEN}" "${SEARCH_ROOT}" 2>/dev/null || true)
  if [[ -z "${residual}" ]]; then
    echo "PASS: Test 18c: zero git-root-defaulted plugin-root anchors remain anywhere under plugins/soleur/ (control: ${control_hits} files scanned and matched)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: Test 18c: the rejected git-root-default form survives at:"
    echo "${residual}" | sed 's/^/         /'
    FAIL=$((FAIL + 1))
  fi
fi

# ---------------------------------------------------------------------------
# Test 19 — DECOY POSITIVE CONTROL for the untrusted-anchor vector (#7450, ADR-179).
#
# Test 18 above pins the two call sites to each OTHER. Nothing pinned either of them to a
# path the reviewed party cannot control — which is the actual defect: `review/SKILL.md`
# instructs `gh pr checkout`, so on the review path `$(git rev-parse --show-toplevel)` IS the
# contributor's tree, and the gate whose exit code decides whether secrets are emitted resolves
# its own scanner from there.
#
# The oracle is the anchor expression AS COMMITTED in incident/SKILL.md, extracted at runtime.
# It is deliberately NOT duplicated into this file: a guard whose expected value is a literal
# copied from the artifact it guards is a set-difference over one producer, and goes vacuous the
# moment someone edits both together
# (learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr...).
#
# 19a proves the decoy is a LIVE hazard rather than an inert file — the real sentinel flags the
# same fixture that the decoy waves through. A positive control that could not have passed
# proves nothing.
# ---------------------------------------------------------------------------
t19_tree="${TMP_DIR}/t19-contributor-tree"
mkdir -p "${t19_tree}/plugins/soleur/skills/incident/scripts" || {
  echo "FAIL: Test 19: could not build the contributor-tree sandbox — a harness that cannot SET UP must abort, not report a verdict about the SUT" >&2
  exit 2
}
git -C "${t19_tree}" init -q >/dev/null 2>&1
# Compare physical paths: mktemp may hand back a symlinked prefix while
# `git rev-parse --show-toplevel` always reports the resolved one, which would make the
# containment test below silently false-PASS.
t19_tree="$(cd "${t19_tree}" && pwd -P)"
t19_decoy="${t19_tree}/plugins/soleur/skills/incident/scripts/redact-sentinel.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${t19_decoy}"
chmod 0755 "${t19_decoy}"

# 19a — the decoy is a live hazard: it passes a file the real sentinel rejects.
t19_secret="${TMP_DIR}/t19-secret.md"
python3 -c "import sys; sys.stdout.write('anthropic_key: ' + 'sk-' + 'ant-api03-' + 'A'*32 + '\n')" > "${t19_secret}"
bash "${SENTINEL}" "${t19_secret}" >/dev/null 2>&1
t19_real_rc=$?
bash "${t19_decoy}" "${t19_secret}" >/dev/null 2>&1
t19_decoy_rc=$?
if [[ "${t19_real_rc}" -eq 1 && "${t19_decoy_rc}" -eq 0 ]]; then
  echo "PASS: Test 19a: decoy is a live hazard (real sentinel exit=1 on the fixture, decoy exit=0)"
  PASS=$((PASS + 1))
else
  echo "FAIL: Test 19a: decoy is not a valid positive control (real=${t19_real_rc} expected 1, decoy=${t19_decoy_rc} expected 0)"
  FAIL=$((FAIL + 1))
fi

# 19b — extract the anchor from the committed producer, and refuse to run vacuously.
#
# THREE hardenings over the original (#7450 review):
#
#   (1) BASH FENCES ONLY, and exactly one assignment per file. The old extractor was a
#       whole-file `sed … | head -1`, so an EARLIER ```text doc example carrying a
#       well-formed assignment became the oracle and silently retargeted 19b/19c away
#       from the live gate — oracle shadowing, measured. `head -1` is what made it
#       silent: a second match was not a conflict, it was simply discarded.
#   (2) (SENTINEL|SCRUBBER), not SENTINEL alone. The decoy control never reached
#       linear-fetch, which the PR body calls the highest residual risk, because its
#       variable is named SCRUBBER.
#   (3) Both gate files are driven, not just incident.
extract_gate_anchor() {
  awk '
    /^[[:space:]]*```bash[[:space:]]*$/ { infence = 1; next }
    /^[[:space:]]*```/                  { infence = 0; next }
    infence && /^[[:space:]]*(SENTINEL|SCRUBBER)="[^"]*"[[:space:]]*$/ {
      line = $0
      sub(/^[[:space:]]*(SENTINEL|SCRUBBER)="/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      print line
    }
  ' "$1"
}

for t19_gate in "${INCIDENT_SKILL}" "${LINEAR_SKILL}"; do
  t19_name="${t19_gate##*/skills/}"
  t19_anchors="$(extract_gate_anchor "${t19_gate}")"
  t19_n=$(printf '%s\n' "${t19_anchors}" | grep -c . || true)
  # DISTINCT values, not occurrences. The hazard this pins is a doc example or a second,
  # DIFFERING assignment shadowing the real anchor — so the property is "the file names
  # exactly one anchor value", not "it names it exactly once".
  #
  # Requiring a single occurrence was a proxy, and it was wrong in the fail-CLOSED direction:
  # `linear-fetch` must legitimately re-derive `SCRUBBER` in its Phase D fence, because each
  # fenced block is a separate Bash call and shell state does not persist across them. The
  # single-occurrence form rejected the correct code (and, before it was fixed, accepted the
  # bricked version that defined the variable in one fence and used it in another).
  # Two byte-identical assignments cannot shadow each other; two differing ones can, and
  # still fail here.
  t19_distinct=$(printf '%s\n' "${t19_anchors}" | grep . | sort -u | grep -c . || true)

  if [[ "${t19_n}" -lt 1 || "${t19_distinct}" -ne 1 ]]; then
    echo "FAIL: Test 19b[${t19_name}]: expected exactly ONE DISTINCT gate-anchor value in bash fences, found ${t19_distinct} distinct across ${t19_n} assignment(s) — a differing second assignment can shadow the real anchor, and an extractor that takes the first of several would not notice"
    FAIL=$((FAIL + 1))
    continue
  fi
  # The UNIQUE value — asserted to be the only distinct one above. Taking the raw multi-line
  # capture would leave `grep -F` treating the embedded newline as a pattern separator, so a
  # match on either line would satisfy it; that happens to work while the values are identical
  # and stops working the moment they are not, which is exactly the case being guarded.
  t19_expr="$(printf '%s\n' "${t19_anchors}" | grep . | sort -u)"

  if grep -Fq "${t19_expr}" "${t19_gate}"; then
    echo "PASS: Test 19b[${t19_name}]: anchor expression extracted from the committed SKILL.md"
    PASS=$((PASS + 1))
  else
    echo "FAIL: Test 19b[${t19_name}]: anchor extraction is vacuous — extracted text absent from the file"
    FAIL=$((FAIL + 1))
    continue
  fi

  # 19c — resolve the committed expression the way a reviewer's session would: plugin
  # root UNRESOLVED, CWD inside the checked-out contributor tree.
  #
  # (a) NEVER bash-expand this text. On the review path the SKILL.md is the CONTRIBUTOR's
  #     file, so the previous form — writing the expression into a script and running it
  #     — handed arbitrary command substitution from a hostile PR straight to bash inside
  #     the reviewer's own test run. The guard for the untrusted-anchor vector was itself
  #     an untrusted-input execution sink. Metacharacters are now a REFUSAL, not input.
  #
  # (b) RESOLVE BEFORE CONTAINMENT. The old `case` compared an UNRESOLVED string against
  #     an absolute `${t19_tree}/*` prefix, so a bare RELATIVE path never matched the
  #     prefix and therefore always "passed" — while resolving, by definition, against
  #     the caller's CWD, which is the contributor tree. The relative case is the
  #     failure, so it must be tested as one.
  case "${t19_expr}" in
    *'$('*|*'`'*|*';'*|*'|'*|*'&'*|*'>'*|*'<'*)
      echo "FAIL: Test 19c[${t19_name}]: anchor expression carries shell metacharacters (${t19_expr}) — refusing to expand contributor-controlled text"
      FAIL=$((FAIL + 1))
      continue ;;
    *'${CLAUDE_PLUGIN_ROOT:'*)
      echo "FAIL: Test 19c[${t19_name}]: anchor uses a :- / :? default (${t19_expr}) — ADR-179 rejects both; the default arm is the vector"
      FAIL=$((FAIL + 1))
      continue ;;
  esac

  # Pure textual substitution of the unresolved root — no shell evaluation.
  t19_resolved="${t19_expr//\$\{CLAUDE_PLUGIN_ROOT\}/}"
  case "${t19_resolved}" in
    /*) case "${t19_resolved}/" in
          "${t19_tree}"/*) t19_inside=1 ;;
          *)               t19_inside=0 ;;
        esac ;;
    # Relative: resolves against the caller's CWD, i.e. INTO the contributor tree.
    *)  t19_inside=1 ;;
  esac

  if [[ -n "${t19_resolved}" && "${t19_inside}" -eq 0 ]]; then
    echo "PASS: Test 19c[${t19_name}]: committed anchor resolves outside the contributor tree (${t19_resolved})"
    PASS=$((PASS + 1))
  else
    echo "FAIL: Test 19c[${t19_name}]: committed anchor resolves INTO the reviewed party's tree — a hostile PR's gate script would run as the gate (resolved=${t19_resolved:-<empty>}, tree=${t19_tree})"
    FAIL=$((FAIL + 1))
  fi
done

# ---------------------------------------------------------------------------
# Test 20 — CROSS-FILE anti-vacuity floor for the Guard 1 skills-axis block.
#
# Guard 1's own floor is closure-scoped to its `describe`, so DELETING THE WHOLE
# #7450 BLOCK was measured green at 9 tests: the floor died with the thing it
# counted. An in-file floor structurally cannot survive the deletion of its own
# file or block, so the floor that can must live somewhere else.
#
# Here specifically, and not in a sibling vitest file: `scripts/test-all.sh` shards
# these two suites differently (Guard 1 under the web-platform group, this one under
# the scripts group), so they do not always run together. A floor in the same shard
# would be reaped by the same skip that reaped the thing it guards.
# ---------------------------------------------------------------------------
T20_GUARD="${REPO_ROOT}/apps/web-platform/test/plugin-root-anchoring.test.ts"
T20_FLOOR=18

if [[ ! -f "${T20_GUARD}" ]]; then
  echo "FAIL: Test 20: Guard 1 is GONE (${T20_GUARD}) — the skills-axis anchoring assertions no longer exist"
  FAIL=$((FAIL + 1))
elif ! grep -Fq 'skills secret-gate subset (#7450)' "${T20_GUARD}"; then
  echo "FAIL: Test 20: Guard 1 no longer contains the #7450 skills secret-gate describe block — deleting it is exactly what its own in-file floor cannot detect"
  FAIL=$((FAIL + 1))
else
  t20_declared=$(sed -n 's/^[[:space:]]*expect(assertions)\.toBe(\([0-9]\+\));[[:space:]]*$/\1/p' "${T20_GUARD}" | tail -1)
  if [[ "${t20_declared}" != "${T20_FLOOR}" ]]; then
    echo "FAIL: Test 20: Guard 1's #7450 assertion floor is '${t20_declared:-<none>}', expected ${T20_FLOOR} — a floor lowered in the same commit that removes assertions is the failure mode this pins"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: Test 20: Guard 1's #7450 block is present and still declares ${T20_FLOOR} decided assertions (cross-file, cross-shard floor)"
    PASS=$((PASS + 1))
  fi
fi

# ---------------------------------------------------------------------------
# SHARED EXECUTABLE-LINE EXTRACTOR for Tests 21, 22 and 23.
#
# THE RECURRING DEFECT THIS CLOSES. Tests 22, 23 and 24 were written in the same two commits
# as Test 21 and asserted against the file's BYTES, not its executable content — so each was
# defeated by a COMMENT. Test 21 alone built an extractor, and its own comment argues at
# length why that scoping is load-bearing. Measured at round-2 review: deleting the real
# `[ -n "$PERSIST_SAFE" ]` arm and leaving a three-line comment quoting it kept BOTH Test 22
# and Test 23 green.
#
# So the extractor is shared rather than duplicated: a future assertion inherits the immunity
# instead of having to remember it.
#
# FENCE HANDLING, every arm added because a mutation walked through it:
#   V1  ```sh / ```shell / ```zsh — an agent executes those exactly as it executes ```bash.
#       This was the cheapest evasion of all: one word.
#   V2  ~~~ fences, which CommonMark treats identically to ```.
#   P2  a fence that is opened and never closed, and a stray ``` INSIDE a fence (a heredoc
#       emitting markdown) closing it early — so the close marker must match the opening
#       run length, and an unclosed fence is reported rather than silently swallowing the
#       rest of the file.
# Info strings (```bash title="x") and CRLF were already handled and are kept.
# ---------------------------------------------------------------------------
exec_lines() {
  awk '
    # opening fence: ``` or ~~~ (>=3), a shell-ish language, optional info string
    !infence && match($0, /^[[:space:]]*(`{3,}|~{3,})[[:space:]]*(bash|sh|shell|zsh)([[:space:]]|$)/) {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      run = 0; ch = substr(line, 1, 1)
      while (substr(line, run + 1, 1) == ch) run++
      infence = 1; fch = ch; frun = run; next
    }
    # a non-shell fence still OPENS a fence — otherwise its contents leak into the scan
    !infence && match($0, /^[[:space:]]*(`{3,}|~{3,})/) {
      line = $0; sub(/^[[:space:]]*/, "", line)
      run = 0; ch = substr(line, 1, 1)
      while (substr(line, run + 1, 1) == ch) run++
      infence = 2; fch = ch; frun = run; next
    }
    # closing fence: same char, at least the opening run length, nothing but the marker
    infence && match($0, /^[[:space:]]*(`{3,}|~{3,})[[:space:]]*\r?$/) {
      line = $0; sub(/^[[:space:]]*/, "", line)
      run = 0; ch = substr(line, 1, 1)
      while (substr(line, run + 1, 1) == ch) run++
      if (ch == fch && run >= frun) { infence = 0 }
      next
    }
    # SHELL COMMENTS INSIDE THE FENCE ARE NOT EXECUTABLE EITHER.
    # Fence-scoping alone is not enough and this was measured: with the fence scoping in
    # place, deleting the real `[ -n "$PERSIST_SAFE" ]` arm and leaving a comment quoting it
    # still passed Test 23, because the comment sits inside the ```bash fence. "Executable
    # content" has to mean executable, not merely fenced.
    infence == 1 && /^[[:space:]]*#/ { next }
    infence == 1 { print }
    END { if (infence) exit 3 }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Test 21 — B1: PIN THE ABSENCE of any git-root resolution at the three secret gates.
#
# Review finding §B1 prescribed adding, at each gate,
#   case "$(cd "${CLAUDE_PLUGIN_ROOT}" && pwd -P)/" in "$(git rev-parse --show-toplevel)/"*) halt;;
# That was measured and REJECTED (specs/.../b1-disposition.md): the loader substitutes the bare
# token at delivery, so the operand is a literal the adversary cannot reach — while the
# assertion breaks dogfooding on any plain clone (there the plugin root IS inside the working
# tree) and puts `git rev-parse --show-toplevel` back into the exact three files this PR
# removes it from.
#
# A disposition that is merely SATISFIED is not guarded, so this pins it. Deliberately broader
# than 18c, which is keyed to the `${CLAUDE_PLUGIN_ROOT:-...}` SYNTAX and so cannot see a bare
# `$(git rev-parse --show-toplevel)` — precisely the shape §B1 proposes.
# ---------------------------------------------------------------------------
t21_offenders=""
t21_unclosed=""
for gate_file in "${INCIDENT_SKILL}" "${LEGAL_SKILL}" "${LINEAR_SKILL}"; do
  if ! exec_lines "${gate_file}" >/dev/null 2>&1; then
    t21_unclosed="${t21_unclosed} ${gate_file##*/skills/}"
    continue
  fi
  n=$(exec_lines "${gate_file}" | grep -c 'git rev-parse' || true)
  [[ "${n}" -ne 0 ]] && t21_offenders="${t21_offenders} ${gate_file##*/skills/}(${n})"
done

# ANTI-VACUITY: PER-FILE required membership, never a total count.
#
# A `>= N` total fails OPEN on shrinkage — measured, the previous floor was `>= 3` against a
# real population of 15 (5 anchor lines per gate), so a one-character regression that blinded
# every INDENTED fence dropped `legal-generate` to 0 of its 5 while the other two still
# supplied 10, and B1's `case` planted in the blinded file stayed GREEN. That is finding A10
# reintroduced — and required-membership was the fix already applied to Test 24's floor in the
# same commit, and not carried across to its sibling.
t21_blind=""
for gate_file in "${INCIDENT_SKILL}" "${LEGAL_SKILL}" "${LINEAR_SKILL}"; do
  c=$(exec_lines "${gate_file}" 2>/dev/null | grep -c 'CLAUDE_PLUGIN_ROOT' || true)
  [[ "${c}" -ge 1 ]] || t21_blind="${t21_blind} ${gate_file##*/skills/}"
done

if [[ -n "${t21_unclosed}" ]]; then
  echo "FAIL: Test 21: unterminated bash fence in:${t21_unclosed} — the extractor cannot bound the executable region, so every verdict over this file would be unreliable"
  FAIL=$((FAIL + 1))
elif [[ -n "${t21_blind}" ]]; then
  echo "FAIL: Test 21: the fence extractor sees ZERO anchor lines in:${t21_blind} — it is blind to that gate's executable content, so a zero-offender verdict there is vacuous (per-file floor, not a total: a total lets one gate go dark while its siblings carry the count)"
  FAIL=$((FAIL + 1))
elif [[ -z "${t21_offenders}" ]]; then
  echo "PASS: Test 21: all 3 secret gates carry ZERO git-root resolution in executable positions, and the extractor sees every gate (the B1 invariant is pinned, not merely satisfied)"
  PASS=$((PASS + 1))
else
  echo "FAIL: Test 21: git-root resolution reappeared in an executable fence at:${t21_offenders} — see specs/feat-one-shot-7450-git-root-anchor-untrusted/b1-disposition.md. If this is a deliberate reversal, that document must be superseded FIRST; a gate that resolves the git root is the #7450 vector itself"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Test 22 — C10: every fail-closed halt on the anchor path emits a SOLEUR_* marker,
# ON STDOUT, FROM AN EXECUTABLE LINE.
#
# `go.md` and `sync.md` already emit one and `go.md` documents why: a refusal nobody can see
# in telemetry is indistinguishable from a run that never happened.
#
# THREE evasions this now closes, all measured green against the previous version:
#   W1  the marker present only in PROSE while the real echo was silenced — the whole point
#       of `exec_lines`.
#   W2  `exit 2; } >&2` — the redirect on the BRACE GROUP rather than the marker line, so a
#       substring test on the marker line alone sees nothing.
#   W5  `>&"2"` and `1>&2` spellings.
# And W3, the growth gap: the reason table is hardcoded, so a NEW fail-closed halt added with
# no marker passed silently. The cardinality check below closes that — the number of halts and
# the number of markers must agree per file.
# ---------------------------------------------------------------------------
t22_missing=""
t22_on_stderr=""
t22_uncovered=""
t22_specs="${INCIDENT_SKILL}:SOLEUR_INCIDENT_HALT:plugin-root-unverified,sentinel-unreadable,draft-alloc-failed,invalid-calendar-date,mttr-transposed,mttd-transposed
${LEGAL_SKILL}:SOLEUR_LEGAL_GENERATE_HALT:plugin-root-unverified,sentinel-unreadable,draft-alloc-failed
${LINEAR_SKILL}:SOLEUR_LINEAR_FETCH_HALT:plugin-root-unverified,scrubber-unreadable,scrubber-nonzero-exit,redaction-empty-output,redaction-ineffective"

while IFS= read -r t22_spec; do
  [[ -n "${t22_spec}" ]] || continue
  t22_file="${t22_spec%%:*}"
  t22_rest="${t22_spec#*:}"
  t22_prefix="${t22_rest%%:*}"
  t22_reasons="${t22_rest#*:}"
  t22_exec="$(exec_lines "${t22_file}" 2>/dev/null)"

  while IFS= read -r t22_reason; do
    [[ -n "${t22_reason}" ]] || continue
    # EXECUTABLE lines only, and the marker must be EMITTED (an `echo`/`printf` argument),
    # not merely mentioned.
    t22_line="$(printf '%s\n' "${t22_exec}" \
      | grep -E "(echo|printf)[^|]*${t22_prefix} reason=${t22_reason}" || true)"
    if [[ -z "${t22_line}" ]]; then
      t22_missing="${t22_missing} ${t22_file##*/skills/}:${t22_reason}"
    else
      # Inspect the MARKER'S OWN command segment, not the whole line. A single-line brace
      # group puts the marker echo and the human-guidance echo (`… >&2`) on one line, so a
      # line-wide test reports every correctly-written marker as stderr-bound — measured, it
      # flagged all three date halts the moment they were marked. Cut from the marker's echo
      # to the next `;`, which is where that command ends.
      t22_seg="$(printf '%s' "${t22_line}" \
        | sed -E "s/.*((echo|printf)[^;]*${t22_prefix} reason=${t22_reason}[^;]*).*/\\1/")"
      # ...AND the enclosing brace group. `{ echo "<marker>"; …; exit 2; } >&2` redirects the
      # WHOLE arm, including the marker, while leaving the marker's own segment clean — so a
      # per-command test alone reports it as compliant. Measured: that mutation landed and the
      # suite stayed green until this arm existed. Walk from the marker to the point where
      # brace depth returns to zero and inspect the closing line.
      t22_arm_redir="$(printf '%s\n' "${t22_exec}" | awk -v mark="${t22_prefix} reason=${t22_reason}" '
        index($0, mark) { armed = 1 }
        armed {
          n = gsub(/\{/, "{"); m = gsub(/\}/, "}")
          depth += n - m
          if (depth <= 0 && /\}/) {
            if ($0 ~ /\}[[:space:]]*[0-9]*>&[[:space:]]*"?2"?/) print "REDIR"
            armed = 0
          }
        }')"
      if printf '%s' "${t22_seg}" | grep -qE '>&[[:space:]]*"?2"?|[0-9]+>&' \
         || [[ -n "${t22_arm_redir}" ]]; then
        t22_on_stderr="${t22_on_stderr} ${t22_file##*/skills/}:${t22_reason}"
      fi
    fi
  done < <(printf '%s\n' "${t22_reasons}" | tr ',' '\n')

  # GROWTH FLOOR (W3): a new fail-closed halt must arrive with a marker. Count `exit 2`
  # dispatches and distinct markers in the executable region and require agreement.
  t22_exits=$(printf '%s\n' "${t22_exec}" | grep -c 'exit 2' || true)
  t22_marks=$(printf '%s\n' "${t22_exec}" | grep -oE "${t22_prefix} reason=[a-z-]+" | sort -u | grep -c . || true)
  if [[ "${t22_exits}" -gt "${t22_marks}" ]]; then
    t22_uncovered="${t22_uncovered} ${t22_file##*/skills/}(${t22_exits} halts vs ${t22_marks} markers)"
  fi
done < <(printf '%s\n' "${t22_specs}")

if [[ -z "${t22_missing}" && -z "${t22_on_stderr}" && -z "${t22_uncovered}" ]]; then
  echo "PASS: Test 22: all 11 fail-closed halts across the 3 gates emit a distinct SOLEUR_*_HALT reason= marker, on STDOUT, from an executable line — and each gate's halt count is covered by its marker count"
  PASS=$((PASS + 1))
else
  [[ -n "${t22_missing}" ]] && echo "FAIL: Test 22: fail-closed halt with no SOLEUR_* marker EMITTED from an executable line at:${t22_missing} — a marker that appears only in prose or a comment is documentation, and a halt nobody can see in telemetry is indistinguishable from a run that never happened"
  [[ -n "${t22_on_stderr}" ]] && echo "FAIL: Test 22: SOLEUR_* marker redirected to stderr at:${t22_on_stderr} — the human guidance belongs on stderr, but the MARKER is the machine-readable half and must go to stdout (check the brace group too: \`exit 2; } >&2\` redirects the whole arm)"
  [[ -n "${t22_uncovered}" ]] && echo "FAIL: Test 22: a gate has more fail-closed halts than distinct markers at:${t22_uncovered} — a new halt was added without one, and the reason table above cannot notice that on its own"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Test 23 — C12/AC5d: the linear-fetch non-empty check is ASSERTED, not merely present.
#
# AC5d claimed "asserted by a test, not by inspection" and no test asserted it: deleting
# `[ -n "$PERSIST_SAFE" ]` left the whole suite green.
#
# The first fix used `grep -A6` for the `exit 2`, and review defeated it two ways: a COMMENT
# quoting the old arm satisfied the presence half (X1b), and `[ -n … ] || true` next to an
# UNRELATED guard's `exit 2` satisfied the dispatch half (X2) — finding A2 reintroduced inside
# the assertion whose own comment cites A2. A window cannot tell whose `exit 2` it found.
#
# So this reuses `preflight_halts_in_own_arm`'s technique, which already exists in this file
# and solved exactly this: require the halt inside the check's OWN brace group, by brace depth.
# ---------------------------------------------------------------------------
t23_needle='[ -n "$PERSIST_SAFE" ]'
t23_exec="$(exec_lines "${LINEAR_SKILL}" 2>/dev/null)"
t23_n=$(printf '%s\n' "${t23_exec}" | grep -Fc "${t23_needle}" || true)
t23_bound=$(printf '%s\n' "${t23_exec}" | awk -v needle="${t23_needle}" '
  index($0, needle) { armed = 1 }
  armed {
    n = gsub(/\{/, "{"); m = gsub(/\}/, "}")
    depth += n - m
    if ($0 ~ /exit[[:space:]]+2/) { found = 1 }
    if (armed && depth <= 0 && /\}/) { armed = 0 }
  }
  END { print (found ? 1 : 0) }
')

if [[ "${t23_n}" -ge 1 && "${t23_bound}" -eq 1 ]]; then
  echo "PASS: Test 23: linear-fetch asserts non-empty redaction output on an executable line AND halts inside that check's OWN arm (AC5d is test-enforced)"
  PASS=$((PASS + 1))
else
  echo "FAIL: Test 23: the linear-fetch non-empty guard is missing from executable lines or does not halt in its own arm (present=${t23_n}, halts-in-own-arm=${t23_bound}) — empty scrubber output would be persisted as persist_safe_summary and the callers' absent-artifact contract, which is what stops them substituting the bearer-URL-bearing agent_context, would never fire"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Test 24 — STAKES-KEYED discovery, INVARIANT-keyed violation, NO allowlist.
# (CTO ruling item 2, rewritten at #7450 round-2 review.)
#
# WHY THIS IS NOT KEYED ON SYNTAX. Test 18c is keyed to one literal,
# `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse …)}`. That is what let finding B2 hide: `trigger-cron`
# invoked a script running `doppler secrets get … -c prd --plain` through the `./`-relative
# `:-` form, so 18c truthfully printed "zero … remain anywhere under plugins/soleur/" while a
# cheaper-to-exploit secret site sat one syntax away. A needle shaped like yesterday's bug
# cannot see tomorrow's.
#
# The first version of THIS test then made the same mistake one level up: it keyed the
# violation on `CLAUDE_PLUGIN_ROOT:-`, so it could not see the 16 credential scripts invoked
# through a BARE repo-relative path — strictly worse, because a bare path is CWD-relative
# unconditionally. So the assertion below is written as the INVARIANT:
#
#     no credential-ACQUIRING script is reachable through a path that resolves relative to CWD
#
# `:-`, bare `plugins/soleur/…` and `./plugins/soleur/…` are three instances of one class. A
# fourth spelling needs no new clause.
#
# WHY ACQUISITION, NOT ADJACENCY. The ruling says "reads a secret". Keying on credential-shaped
# NAMES instead enrols every redaction engine, because token names are their needles — measured:
# a name-keyed predicate matched `$SESSION_TOKENS` (LLM tokens), `$TRAILER_KEY` (a map key) and
# `${LINEAR_CDN_PATTERNS}` (via `_PAT`), inflating the population by 9 with scripts that acquire
# nothing. It also drags in `worktree-manager.sh`, which copies `.env*` files but acquires no
# named credential — and which #7453 owns.
#
# The boundary, as a DEFINITION rather than an allowlist (so a future member is excluded by
# reasoning, not by having been omitted from a list): a script that copies files which may
# contain secrets, on a machine that has already granted it execution, adds no marginal exposure
# beyond the generic arbitrary-code-execution that #7453 addresses for all ~105 deferred sites.
# A script whose purpose is to FETCH a named production credential and act with it is a direct
# exfiltration primitive when substituted.
# ---------------------------------------------------------------------------

# A credential token inside a COMMENT is a mention, not an acquisition. Without this a
# `# Never echo the API_KEY` line enrols a script that handles no credential, and the resulting
# CI failure asserts something untrue about it.
t24_strip_comments() {
  case "$1" in
    *.ts|*.mjs|*.cjs) sed -E 's,//.*,,' "$1" | grep -vE '^[[:space:]]*\*' ;;
    *)                grep -vE '^[[:space:]]*#' "$1" ;;
  esac
}

# Keyed on the ACT of obtaining or presenting a credential. `read -[a-z]*s` (not `read -s`)
# because the real sites write `read -rs`; that exact miss cost a false-clean during the ruling.
t24_acq_re='doppler secrets (get|download)|op read |vault kv get|gh auth token|read -[a-z]*s |Authorization: *Bearer|-H .Authorization|process\.env\.[A-Z_]*(TOKEN|_KEY|SECRET|PASSWORD)|env\("[A-Z_]*(TOKEN|_KEY|SECRET|PASSWORD)'

t24_acquirers=()
while IFS= read -r t24_f; do
  t24_strip_comments "${t24_f}" | grep -qE "${t24_acq_re}" \
    && t24_acquirers+=("${t24_f#"${REPO_ROOT}"/plugins/soleur/}")
done < <(find "${REPO_ROOT}/plugins/soleur" -path '*/scripts/*' -type f \
           \( -name '*.sh' -o -name '*.py' -o -name '*.ts' -o -name '*.mjs' -o -name '*.cjs' \) \
           ! -name '*.test.sh' 2>/dev/null | sort)

# ANTI-VACUITY: required MEMBERSHIP, never a count. A bare `>= N` floor fails OPEN on
# shrinkage — measured, an early draft used `>= 5` against a population of 21 and a mutation
# that gutted the predicate down to 9 members SURVIVED it. That is finding A10's shape.
# These three are pinned because each is a DISTINCT acquisition mechanism; a predicate that
# stops seeing any one of them has stopped doing its job whatever its total.
#   trigger.sh                — secrets-manager read (`doppler secrets get … -c prd --plain`)
#   discord-setup.sh          — ambient bot token (`DISCORD_BOT_TOKEN`)
#   provision-hetzner.sh      — silent interactive prompt (`read -rs`)
# `community-router.sh` is deliberately NOT pinned: under an acquisition predicate it correctly
# drops out, because its only credential mention is inside a routing-table string.
t24_required=(
  "skills/trigger-cron/scripts/trigger.sh"
  "skills/community/scripts/discord-setup.sh"
  "skills/provision-hetzner/scripts/provision-hetzner.sh"
)
t24_missing_required=""
for t24_req in "${t24_required[@]}"; do
  t24_found=0
  for t24_have in ${t24_acquirers[@]+"${t24_acquirers[@]}"}; do
    [[ "${t24_have}" == "${t24_req}" ]] && { t24_found=1; break; }
  done
  [[ "${t24_found}" -eq 1 ]] || t24_missing_required="${t24_missing_required} ${t24_req}"
done

if [[ -n "${t24_missing_required}" ]]; then
  echo "FAIL: Test 24: credential-acquisition discovery no longer sees:${t24_missing_required} — each is a DISTINCT acquisition mechanism (secrets-manager read / ambient bot token / silent prompt), so the predicate is broken and the zero-violation verdict below would be vacuous. Population is ${#t24_acquirers[@]}."
  FAIL=$((FAIL + 1))
else
  t24_violations=""
  for t24_rel in ${t24_acquirers[@]+"${t24_acquirers[@]}"}; do
    # Keyed on the PAYLOAD-RELATIVE PATH, never the basename: `flip.sh` is a suffix of
    # `audit-flag-flip.sh`, and a bare basename also collides with markdown link targets and
    # `# Usage:` lines. The full path is the script's unambiguous identity.
    t24_rel_re="$(printf '%s' "${t24_rel}" | sed 's/[.[\*^$]/\\&/g')"
    while IFS= read -r t24_hit; do
      [[ -n "${t24_hit}" ]] || continue
      t24_file="${t24_hit%%:*}"; t24_rest="${t24_hit#*:}"
      t24_lno="${t24_rest%%:*}"; t24_line="${t24_rest#*:}"

      # A script naming its OWN path (a usage header, a self-referential constant) is not a
      # call to itself.
      [[ "${t24_file}" == *"${t24_rel}" ]] && continue

      # A path inside a COMMENT is documentation, not an invocation — `audit-flag-flip.sh`
      # lists its four consumers in a comment block, which is a manifest, not a call.
      case "${t24_file}" in
        *.sh|*.py)        printf '%s' "${t24_line}" | grep -qE '^[[:space:]]*#' && continue ;;
        *.ts|*.mjs|*.cjs) printf '%s' "${t24_line}" | grep -qE '^[[:space:]]*(//|\*)' && continue ;;
      esac

      # EXECUTION context only. The invariant is about reachability FOR EXECUTION, so a path
      # merely read or written as CONTENT is a data root and correct as-is (the ruling's
      # classification table). Measured: `flag-delete/scripts/delete.sh` names `flip.sh` twice
      # to edit a map entry inside it — a source edit, not a call — and flagging that would
      # teach the next reader that data roots need anchoring, which inverts the rule.
      t24_is_exec=0
      # (1) an explicit verb, or a prose "Run <path>" instruction
      printf '%s' "${t24_line}" \
        | grep -qE "(^|[[:space:];&|(])(bash|sh|bun|node|python3|python|exec|source|\.)[[:space:]]+[^[:space:]]*${t24_rel_re}|[Rr]un[[:space:]]+[^[:space:]]*${t24_rel_re}" \
        && t24_is_exec=1
      # (2) a BARE quoted-path invocation — `"${CLAUDE_PLUGIN_ROOT}/…/trigger.sh" --list`
      # relies on the file's exec bit and carries no verb at all.
      printf '%s' "${t24_line}" | grep -qE "^[[:space:]]*\"?[^[:space:]]*${t24_rel_re}\"?[[:space:]]" \
        && t24_is_exec=1
      # (3) ASSIGN-THEN-INVOKE. `TRIGGER="…/trigger.sh"` then `bash "$TRIGGER"` on another
      # line is THE dominant shape in this corpus — it is why Guard 1 needs G2 at all ("the
      # anchor lives in an assignment, so an operand rule certifies the invocation while the
      # assignment points anywhere"). Requiring a verb on the same line missed every one of
      # them: measured, reverting trigger-cron's anchor to the `:-` form SURVIVED, because
      # all three of its sites are an assignment and two bare invocations.
      # The variable must actually be INVOKED somewhere in the file — otherwise this would
      # re-flag `flag-delete`'s `FLIP_SH`, which is only ever read as content (a data root).
      t24_var="$(printf '%s' "${t24_line}" | sed -nE "s/^[[:space:]]*(readonly[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*${t24_rel_re}.*/\\2/p")"
      if [[ -n "${t24_var}" ]] \
         && grep -qE "(^|[[:space:];&|(])(bash|sh|bun|node|python3|python|exec|source|\.)[[:space:]]+\"?\\\$\{?${t24_var}\}?\"?|^[[:space:]]*\"\\\$\{?${t24_var}\}?\"[[:space:]]" "${t24_file}"; then
        t24_is_exec=1
      fi
      [[ "${t24_is_exec}" -eq 1 ]] || continue

      # POSITIVE requirement — the invariant, not a list of bad spellings. TWO prefixes satisfy
      # it, and both must be accepted or the guard flags correct code (and gets weakened by
      # whoever hits that next):
      #   ${CLAUDE_PLUGIN_ROOT}/…      loader-substituted at delivery (ADR-179 decision 1)
      #   $SCRIPT_DIR / $BASH_SOURCE   layout-invariant per ADR-178, likewise not CWD-derived
      printf '%s' "${t24_line}" | grep -qE '\$\{CLAUDE_PLUGIN_ROOT\}/' && continue
      printf '%s' "${t24_line}" | grep -qE '\$\{?(SCRIPT_DIR|BASH_SOURCE)' && continue

      t24_violations="${t24_violations}
    ${t24_file#"${REPO_ROOT}"/}:${t24_lno}"
    done < <(grep -rn -F "${t24_rel}" "${REPO_ROOT}/plugins/soleur" \
               --include='*.md' --include='*.sh' --include='*.json' --include='*.ts' 2>/dev/null \
               | grep -v '/test/' | grep -v '\.test\.' || true)
  done

  if [[ -z "${t24_violations}" ]]; then
    echo "PASS: Test 24: none of the ${#t24_acquirers[@]} discovered credential-acquiring scripts is reachable through a CWD-relative path (stakes-keyed discovery, invariant-keyed violation, no allowlist)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: Test 24: a credential-ACQUIRING script is invoked through a path that resolves relative to CWD, so the session's own working directory decides which script runs:${t24_violations}"
    echo "       Fix: anchor the invocation on the bare quoted \${CLAUDE_PLUGIN_ROOT}, or resolve it \$BASH_SOURCE-relative if the target is a sibling in the payload."
    echo "       This assertion has NO allowlist by ruling — deferring to #7453 is for non-gate sites, not for sites that hand over a credential."
    FAIL=$((FAIL + 1))
  fi
fi


echo
echo "Total: ${PASS} pass, ${FAIL} fail"

# ---------------------------------------------------------------------------
# ANTI-VACUITY FLOOR ON THIS HARNESS'S OWN DISPATCH.
#
# `[[ "${FAIL}" -eq 0 ]]` alone is satisfied by a run that asserted NOTHING: delete every
# assertion between the setup block and here and the file exits 0 at `Total: 0 pass, 0 fail`,
# which `scripts/test-all.sh` reads as a passing suite. Measured — that is exactly what
# happened, in the file whose whole purpose is proving OTHER files are not deletable at green.
# Test 20 gives Guard 1 a cross-file floor and nothing reciprocated for Guard 2.
#
# This is not an invented convention: `scripts/lint-guard-contract.test.sh` already ships the
# identical `EXPECTED_MIN` floor, and it was not reused here.
#
# A FLOOR, deliberately, not `-eq`: the count is developer-incremented, so equality turns every
# added assertion into a spurious failure and the natural fix is to stop adding them. Derive the
# value from a green run and ratchet it UP when assertions are added — never down to make a
# failure go away, which is how a floor becomes the thing it was built to prevent.
# ---------------------------------------------------------------------------
EXPECTED_MIN=96
TOTAL_DISPATCHED=$(( PASS + FAIL ))
if [[ "${TOTAL_DISPATCHED}" -lt "${EXPECTED_MIN}" ]]; then
  echo "FAIL: harness dispatched only ${TOTAL_DISPATCHED} assertions (expected >= ${EXPECTED_MIN}) — a vacuous run. Assertions were removed or the dispatch was neutered; a suite that asserts nothing exits 0 and reads as PASS." >&2
  exit 1
fi

[[ "${FAIL}" -eq 0 ]]
