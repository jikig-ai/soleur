#!/usr/bin/env bash

# Tests for plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh.
# Run: bash plugins/soleur/test/vendor-pin-integrity.test.sh
#
# The integrity script is invoked by the `vendor-pin-integrity` lefthook stanza.
# Per file argument: compute `git hash-object --no-filters` and compare against
# the blob-sha pinned in NOTICE frontmatter. Exit 1 on mismatch with a stderr
# message naming the file. Exit 0 if every file matches.
#
# AC5b parity: lefthook.yml `vendor-pin-integrity` glob list ⊇ NOTICE
# `lifted-files[].path` (entries are full repo-relative paths). Catches the
# class of bug where a 6th lifted file is added to NOTICE without updating
# lefthook (silent local-edit detection bypass).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$SCRIPT_DIR/../../.."
INTEGRITY="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh"
PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
SKILL_DIR="$REPO_ROOT/plugins/soleur/skills/gdpr-gate"
LEFTHOOK="$REPO_ROOT/lefthook.yml"

echo "=== vendor-pin-integrity tests ==="
echo ""

assert_file_exists "$INTEGRITY" "vendor-pin-integrity.sh exists"

# --- TS1: happy path — every lifted file's actual SHA matches NOTICE ---
# Run the integrity script over all 5 NOTICE-tracked file paths; expect exit 0.
echo "TS1: live NOTICE + live lifted files → exit 0 (no drift)"
LIFTED_PATHS=()
while IFS= read -r line; do
  # NOTICE paths are repo-relative under plugins/soleur/skills/gdpr-gate/.
  rel_path="${line%%:*}"
  LIFTED_PATHS+=("$SKILL_DIR/$rel_path")
done < <(bash "$PARSER" lifted-files)

set +e
( cd "$REPO_ROOT" && bash "$INTEGRITY" "${LIFTED_PATHS[@]}" >/dev/null 2>&1 )
RC=$?
set -e
assert_eq "0" "$RC" "exit 0 when all lifted files match NOTICE blob SHAs"
echo ""

# --- TS2: SHA-mismatch fixture (mocked NOTICE) → exit 1 ---
# Build a fixture NOTICE with deliberately-wrong blob-sha for fields.md, then
# point the integrity script at it via NOTICE_FILE override. Expect exit 1
# and a stderr line naming the mismatched file.
echo "TS2: NOTICE-with-wrong-SHA → exit 1 + mismatch message on stderr"
TMP_NOTICE="$(mktemp)"
cat > "$TMP_NOTICE" <<'EOF'
---
upstream: github.com/goSprinto/compliance-skills
pinned-commit: 7b58d68461cb1fc033a063e34cc9de63d0b4144b
last-verified: 2026-05-10
registry: knowledge-base/engineering/policies/content-vendoring.md
lifted-files:
  - path: references/fields.md
    upstream-path: pii-detector/patterns/fields.md
    upstream-blob-sha: c1bb748fe00a53b283efe66ec937fa39437d2efc
    local-blob-sha: 0000000000000000000000000000000000000000
    status: active-eu-extended
---

# NOTICE (test fixture)
EOF

set +e
STDERR=$( ( cd "$REPO_ROOT" && NOTICE_FILE="$TMP_NOTICE" \
  bash "$INTEGRITY" "$SKILL_DIR/references/fields.md" ) 2>&1 1>/dev/null )
RC=$?
set -e
assert_eq "1" "$RC" "exit 1 on NOTICE/actual blob-sha mismatch"
assert_contains "$STDERR" "fields.md" "stderr names the mismatched file"
assert_contains "$STDERR" "mismatch" "stderr identifies it as a mismatch"
rm -f "$TMP_NOTICE"
echo ""

# --- TS3: file not in NOTICE registry — flagged as silent-addition ---
# A staged file that lefthook glob matches but NOTICE doesn't track means
# someone added a 6th lifted file without updating NOTICE. Must exit non-zero.
echo "TS3: file present on disk but absent from NOTICE → exit non-zero"
TMP_FILE="$(mktemp -p "$SKILL_DIR" --suffix=.md unrecognised-XXXX)"
trap 'rm -f "$TMP_FILE"' EXIT
echo "fake lifted content" > "$TMP_FILE"
set +e
STDERR=$( ( cd "$REPO_ROOT" && bash "$INTEGRITY" "$TMP_FILE" ) 2>&1 1>/dev/null )
RC=$?
set -e
if (( RC != 0 )); then
  echo "  PASS: exit non-zero ($RC) on file not in NOTICE registry"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected non-zero exit when file is absent from NOTICE"
  FAIL=$((FAIL + 1))
fi
rm -f "$TMP_FILE"
trap - EXIT
echo ""

# --- TS4: AC5b parity — lefthook glob ⊇ NOTICE lifted-files[].path ---
# Each NOTICE lifted-files path (relative under skills/gdpr-gate) must appear
# as a path-array glob entry in lefthook.yml's vendor-pin-integrity stanza.
# Surface form: `        - "plugins/soleur/skills/gdpr-gate/<rel>"`.
echo "TS4: AC5b — lefthook glob ⊇ NOTICE lifted-files[].path"
assert_file_exists "$LEFTHOOK" "lefthook.yml exists"
LEFTHOOK_CONTENT=$(cat "$LEFTHOOK")

# Verify the stanza exists at all.
if grep -qE '^[[:space:]]+vendor-pin-integrity:' "$LEFTHOOK"; then
  echo "  PASS: lefthook.yml has vendor-pin-integrity stanza"
  PASS=$((PASS + 1))
else
  echo "  FAIL: lefthook.yml is missing the vendor-pin-integrity stanza"
  FAIL=$((FAIL + 1))
fi

# Parity check: every NOTICE-listed path is present as a glob entry.
MISSING_GLOBS=()
while IFS= read -r line; do
  rel_path="${line%%:*}"
  full="plugins/soleur/skills/gdpr-gate/$rel_path"
  if ! grep -qF "\"$full\"" "$LEFTHOOK"; then
    MISSING_GLOBS+=("$full")
  fi
done < <(bash "$PARSER" lifted-files)

if (( ${#MISSING_GLOBS[@]} == 0 )); then
  echo "  PASS: every NOTICE lifted-files[].path appears in lefthook glob"
  PASS=$((PASS + 1))
else
  echo "  FAIL: lefthook glob missing entries: ${MISSING_GLOBS[*]}"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- TS5: --no-filters discipline — script must call git hash-object
# --no-filters (TR1; line-ending normalisation otherwise diverges from
# upstream blob SHAs).
echo "TS5: script uses 'git hash-object --no-filters' (TR1)"
if grep -q 'git hash-object --no-filters' "$INTEGRITY"; then
  echo "  PASS: --no-filters flag present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: missing --no-filters; line-ending normalisation will skew SHAs"
  FAIL=$((FAIL + 1))
fi
echo ""

print_results
