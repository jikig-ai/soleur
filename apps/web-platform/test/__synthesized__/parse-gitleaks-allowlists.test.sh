#!/usr/bin/env bash
# Test harness for apps/web-platform/scripts/parse-gitleaks-allowlists.mjs
#
# Pattern mirrors plugins/soleur/skills/incident/test/redact-sentinel.test.sh.
# Tests T1-T8 cover: missing file, malformed TOML, empty allowlist, top-level
# only, per-rule only, mixed dedupe, regex-meta-char-safe, v8.25+ shape detection.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PARSER="${REPO_ROOT}/apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"

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

assert_jq() {
  local label="$1" filter="$2" file="$3"
  if jq -e "${filter}" "${file}" >/dev/null 2>&1; then
    echo "PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (jq filter '${filter}' did not match)"
    cat "${file}" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -qE "${pattern}" "${file}"; then
    echo "PASS: ${label}"
    PASS=$((PASS + 1))
  else
    echo "FAIL: ${label} (pattern '${pattern}' not in ${file##*/})"
    cat "${file}" >&2
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# T1: missing file -> exit 2
# ---------------------------------------------------------------------------
node "${PARSER}" "${TMP_DIR}/does-not-exist.toml" >"${TMP_DIR}/t1.out" 2>&1
assert_exit "T1: missing file exits 2" 2 $?

# ---------------------------------------------------------------------------
# T2: malformed TOML (unbalanced brackets) -> exit 3
# ---------------------------------------------------------------------------
cat >"${TMP_DIR}/t2.toml" <<'EOF'
[allowlist]
paths = [
  '''broken-no-closing-bracket'''
EOF
node "${PARSER}" "${TMP_DIR}/t2.toml" >"${TMP_DIR}/t2.out" 2>&1
assert_exit "T2: malformed TOML exits 3" 3 $?

# ---------------------------------------------------------------------------
# T3: empty allowlist -> exit 0, output []
# ---------------------------------------------------------------------------
cat >"${TMP_DIR}/t3.toml" <<'EOF'
title = "no allowlist"
EOF
node "${PARSER}" "${TMP_DIR}/t3.toml" >"${TMP_DIR}/t3.out" 2>"${TMP_DIR}/t3.err"
assert_exit "T3: empty allowlist exits 0" 0 $?
assert_jq "T3: output is empty array" '. == []' "${TMP_DIR}/t3.out"

# ---------------------------------------------------------------------------
# T4: top-level [allowlist] only
# ---------------------------------------------------------------------------
cat >"${TMP_DIR}/t4.toml" <<'EOF'
title = "top-level only"

[allowlist]
description = "test"
paths = [
  '''top-level/path-one\.txt$''',
  '''top-level/path-two\.md$''',
]
EOF
node "${PARSER}" "${TMP_DIR}/t4.toml" >"${TMP_DIR}/t4.out" 2>&1
assert_exit "T4: top-level allowlist exits 0" 0 $?
assert_jq "T4: top-level paths emitted" '. == ["top-level/path-one\\.txt$", "top-level/path-two\\.md$"]' "${TMP_DIR}/t4.out"

# ---------------------------------------------------------------------------
# T5: per-rule [[rules.allowlists]] only, multiple rules
# ---------------------------------------------------------------------------
cat >"${TMP_DIR}/t5.toml" <<'EOF'
[[rules]]
id = "rule-a"
regex = '''aaa'''
keywords = ["a"]
  [[rules.allowlists]]
  paths = ['''rule-a/foo''', '''rule-a/bar''']

[[rules]]
id = "rule-b"
regex = '''bbb'''
keywords = ["b"]
  [[rules.allowlists]]
  paths = ['''rule-b/baz''']
EOF
node "${PARSER}" "${TMP_DIR}/t5.toml" >"${TMP_DIR}/t5.out" 2>&1
assert_exit "T5: per-rule allowlists exit 0" 0 $?
assert_jq "T5: per-rule paths deduped & emitted" '(. | length) == 3 and (any(. == "rule-a/foo")) and (any(. == "rule-b/baz"))' "${TMP_DIR}/t5.out"

# ---------------------------------------------------------------------------
# T6: mixed top-level + per-rule with overlap -> deduped union
# ---------------------------------------------------------------------------
cat >"${TMP_DIR}/t6.toml" <<'EOF'
[allowlist]
paths = ['''shared/path''', '''top-only/path''']

[[rules]]
id = "rule-c"
regex = '''ccc'''
keywords = ["c"]
  [[rules.allowlists]]
  paths = ['''shared/path''', '''per-rule-only/path''']
EOF
node "${PARSER}" "${TMP_DIR}/t6.toml" >"${TMP_DIR}/t6.out" 2>&1
assert_exit "T6: mixed exits 0" 0 $?
assert_jq "T6: deduped union has 3 entries" '(. | length) == 3' "${TMP_DIR}/t6.out"
assert_jq "T6: shared path appears once" '[.[] | select(. == "shared/path")] | length == 1' "${TMP_DIR}/t6.out"

# ---------------------------------------------------------------------------
# T7: regex meta-char safe — paths with \., (?:...), [...] verbatim
# ---------------------------------------------------------------------------
cat >"${TMP_DIR}/t7.toml" <<'EOF'
[allowlist]
paths = [
  '''apps/(?:infra|test)/.*\.test\.(?:sh|ts)$''',
  '''[A-Z]+/[a-z0-9_-]+\.snap$''',
]
EOF
node "${PARSER}" "${TMP_DIR}/t7.toml" >"${TMP_DIR}/t7.out" 2>&1
assert_exit "T7: regex-meta-safe exits 0" 0 $?
assert_jq "T7: parens/escape preserved verbatim" 'any(. == "apps/(?:infra|test)/.*\\.test\\.(?:sh|ts)$")' "${TMP_DIR}/t7.out"
assert_jq "T7: char class preserved verbatim" 'any(. == "[A-Z]+/[a-z0-9_-]+\\.snap$")' "${TMP_DIR}/t7.out"

# ---------------------------------------------------------------------------
# T8: v8.25+ shape ([[allowlists]] with targetRules) -> exit 4 + warning
#   The parser is locked to v8.24.2 syntax; encountering the new form must
#   block silently-incorrect parsing. Operator must update the parser
#   alongside the gitleaks bump.
# ---------------------------------------------------------------------------
cat >"${TMP_DIR}/t8.toml" <<'EOF'
title = "v8.25+ schema"

[[allowlists]]
description = "top-level allowlists with targetRules — v8.25+ only"
targetRules = ["rule-x"]
paths = ['''future/syntax/path''']
EOF
node "${PARSER}" "${TMP_DIR}/t8.toml" >"${TMP_DIR}/t8.out" 2>"${TMP_DIR}/t8.err"
assert_exit "T8: v8.25+ shape exits 4" 4 $?
assert_grep "T8: stderr warns about [[allowlists]] block" '\[\[allowlists\]\]' "${TMP_DIR}/t8.err"

# ---------------------------------------------------------------------------
# T9: real .gitleaks.toml — ≥14 unique paths (matches deepen-pass baseline)
# ---------------------------------------------------------------------------
node "${PARSER}" "${REPO_ROOT}/.gitleaks.toml" >"${TMP_DIR}/t9.out" 2>&1
assert_exit "T9: real .gitleaks.toml exits 0" 0 $?
assert_jq "T9: real .gitleaks.toml extracts >=14 unique paths" '(. | length) >= 14' "${TMP_DIR}/t9.out"

echo
echo "Total: ${PASS} pass, ${FAIL} fail"
[[ "${FAIL}" -eq 0 ]] || exit 1
