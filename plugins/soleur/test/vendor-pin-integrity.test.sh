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

# --- TS4: AC5b parity — lefthook glob matches every NOTICE lifted-files[].path ---
# The glob uses pattern entries (`references/*.md`, `references/layers/*.md`)
# rather than per-file literals so that any new file added under references/
# triggers the integrity script — which then rejects it via the "staged but
# not in NOTICE" branch. The parity check therefore verifies that each NOTICE
# rel_path matches one of the pattern entries, not that it appears as a
# literal string.
echo "TS4: AC5b — lefthook glob matches every NOTICE lifted-files[].path"
assert_file_exists "$LEFTHOOK" "lefthook.yml exists"

# Verify the stanza exists at all.
if grep -qE '^[[:space:]]+vendor-pin-integrity:' "$LEFTHOOK"; then
  echo "  PASS: lefthook.yml has vendor-pin-integrity stanza"
  PASS=$((PASS + 1))
else
  echo "  FAIL: lefthook.yml is missing the vendor-pin-integrity stanza"
  FAIL=$((FAIL + 1))
fi

# Parity check: every NOTICE-listed path matches the lefthook glob patterns.
# The integrity script reads its registry from NOTICE at runtime, so as long
# as the glob covers the NOTICE paths and NOTICE itself, divergence is impossible.
MISSING_GLOBS=()
while IFS= read -r line; do
  rel_path="${line%%:*}"
  # Match the current pattern set: `references/*.md` or `references/layers/*.md`.
  if [[ ! "$rel_path" =~ ^references/[^/]+\.md$ ]] && \
     [[ ! "$rel_path" =~ ^references/layers/[^/]+\.md$ ]]; then
    MISSING_GLOBS+=("$rel_path")
  fi
done < <(bash "$PARSER" lifted-files)

if (( ${#MISSING_GLOBS[@]} == 0 )); then
  echo "  PASS: every NOTICE lifted-files[].path is matched by the lefthook glob"
  PASS=$((PASS + 1))
else
  echo "  FAIL: lefthook glob does not match: ${MISSING_GLOBS[*]}"
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

# ---------------------------------------------------------------------------
# Guard 1 — the vendored-pin registry (#7710)
#
# Property: every file under the gate's `references/**` carries a pin
# appropriate to its provenance — upstream-derived files in `lifted-files`,
# Soleur-authored files in `soleur-authored` — and no file appears in the
# wrong list or in neither.
#
# The chokepoint is THIS WALK, not vendor-pin-integrity.sh: the script
# iterates only over its arguments and never reads the tree, so the
# symmetric-difference property is bought here and lefthook/CI do not reach
# it through the script.
# ---------------------------------------------------------------------------

# Build a fixture NOTICE from a lifted-files block and a soleur-authored block.
# Kept as a helper so each mutation case differs only in the registry content.
make_notice() {
  # $1 = destination path, $2 = lifted-files body, $3 = soleur-authored body
  cat > "$1" <<NOTICE_EOF
---
upstream: github.com/goSprinto/compliance-skills
pinned-commit: 7b58d68461cb1fc033a063e34cc9de63d0b4144b
last-verified: 2026-05-10
registry: knowledge-base/engineering/policies/content-vendoring.md
lifted-files:
$2
soleur-authored:
$3
---

# NOTICE (test fixture)
NOTICE_EOF
}

# --- TS6: reverse parity — every references/** file is in exactly one list ---
# Mutation 1 in the Guard Contract: a file listed in NEITHER registry must go
# RED. This is the direction nothing asserted before #7710, and it is why
# three files sat unpinned for 117 days.
echo "TS6: disk(references/**) == lifted-files U soleur-authored (symmetric difference empty)"

DISK_FILES=()
while IFS= read -r f; do
  DISK_FILES+=("${f#"$SKILL_DIR"/}")
done < <(find "$SKILL_DIR/references" -type f -name '*.md' | sort)

REGISTRY_FILES=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  REGISTRY_FILES+=("${line%%:*}")
done < <(bash "$PARSER" lifted-files; bash "$PARSER" soleur-authored)

# Own dispatch (mutation 5): `0 checked, 0 failed` must not read as success.
# A walk that yields nothing is a broken harness, not a clean registry.
if (( ${#DISK_FILES[@]} < 8 )); then
  echo "  FAIL: disk walk yielded ${#DISK_FILES[@]} files under references/ (expected >= 8) — harness defect, not a clean registry"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: disk walk yielded ${#DISK_FILES[@]} files under references/"
  PASS=$((PASS + 1))
fi

if (( ${#REGISTRY_FILES[@]} < 8 )); then
  echo "  FAIL: registry union yielded ${#REGISTRY_FILES[@]} entries (expected >= 8) — parser or NOTICE defect"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: registry union yielded ${#REGISTRY_FILES[@]} entries"
  PASS=$((PASS + 1))
fi

UNPINNED=()
for d in "${DISK_FILES[@]}"; do
  found=0
  for r in "${REGISTRY_FILES[@]}"; do
    [[ "$d" == "$r" ]] && { found=1; break; }
  done
  (( found )) || UNPINNED+=("$d")
done
assert_eq "" "${UNPINNED[*]:-}" "no references/ file is absent from both registries"

ORPHANED=()
for r in "${REGISTRY_FILES[@]}"; do
  found=0
  for d in "${DISK_FILES[@]}"; do
    [[ "$d" == "$r" ]] && { found=1; break; }
  done
  (( found )) || ORPHANED+=("$r")
done
assert_eq "" "${ORPHANED[*]:-}" "no registry entry names a file absent from disk"
echo ""

# --- TS7: no file appears in BOTH registries (provenance falsification) ---
# Mutation 2: moving a Soleur-authored file into lifted-files attests
# goSprinto MIT provenance for Soleur's own writing. It must be REJECTED,
# not merely un-required.
echo "TS7: no file appears in both lifted-files and soleur-authored"
BOTH=()
while IFS= read -r lifted; do
  [[ -z "$lifted" ]] && continue
  lp="${lifted%%:*}"
  while IFS= read -r auth; do
    [[ -z "$auth" ]] && continue
    ap="${auth%%:*}"
    [[ "$lp" == "$ap" ]] && BOTH+=("$lp")
  done < <(bash "$PARSER" soleur-authored)
done < <(bash "$PARSER" lifted-files)
assert_eq "" "${BOTH[*]:-}" "lifted-files and soleur-authored are disjoint"
echo ""

# --- TS8: Soleur-authored files are integrity-checked, not rejected ---
# AC4 first half. Before #7710 these three exited 1 as "silent local
# addition", which is why the documented v2->v3 lifecycle of
# legal-consent.md could not be committed without --no-verify.
echo "TS8: Soleur-authored reference files pass the integrity check"
AUTHORED_PATHS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  AUTHORED_PATHS+=("$SKILL_DIR/${line%%:*}")
done < <(bash "$PARSER" soleur-authored)

if (( ${#AUTHORED_PATHS[@]} == 0 )); then
  echo "  FAIL: soleur-authored list is empty — nothing was checked"
  FAIL=$((FAIL + 1))
else
  set +e
  ( cd "$REPO_ROOT" && bash "$INTEGRITY" "${AUTHORED_PATHS[@]}" >/dev/null 2>&1 )
  RC=$?
  set -e
  assert_eq "0" "$RC" "exit 0 for ${#AUTHORED_PATHS[@]} Soleur-authored files with matching SHAs"
fi
echo ""

# --- TS9: mismatched Soleur-authored SHA is rejected, and named as such ---
# AC4 second half. The message must name the Soleur-authored list rather
# than "silent local addition" — a contributor who edits legal-consent.md
# is following a documented lifecycle, not smuggling in a vendored file.
echo "TS9: mismatched soleur-authored SHA -> exit 1, message names the right list"
TMP_TS9="$(mktemp -d -t vpi-ts9.XXXXXXXX)"
assert_fixture_dir "$TMP_TS9"
trap 'rm -rf "$TMP_TS9"' EXIT

make_notice "$TMP_TS9/NOTICE" \
"  - path: references/fields.md
    upstream-path: pii-detector/patterns/fields.md
    upstream-blob-sha: c1bb748fe00a53b283efe66ec937fa39437d2efc
    local-blob-sha: $(git hash-object --no-filters "$SKILL_DIR/references/fields.md")
    status: active-eu-extended" \
"  - path: references/non-negotiables.md
    local-blob-sha: 0000000000000000000000000000000000000000
    status: soleur-authored"

set +e
STDERR=$( cd "$REPO_ROOT" && NOTICE_FILE="$TMP_TS9/NOTICE" bash "$INTEGRITY" \
  "$SKILL_DIR/references/non-negotiables.md" 2>&1 >/dev/null )
RC=$?
set -e
assert_eq "1" "$RC" "exit 1 on soleur-authored blob-sha mismatch"
assert_contains "$STDERR" "non-negotiables.md" "stderr names the mismatched file"
assert_contains "$STDERR" "soleur-authored" "stderr names the soleur-authored list"
echo ""

# --- TS10: second member — the walk must not stop at the first compliant file
# Mutation 4: file A compliant, file B not, A ordered first.
echo "TS10: a compliant first argument does not mask a non-compliant second"
set +e
STDERR=$( cd "$REPO_ROOT" && NOTICE_FILE="$TMP_TS9/NOTICE" bash "$INTEGRITY" \
  "$SKILL_DIR/references/fields.md" "$SKILL_DIR/references/non-negotiables.md" 2>&1 >/dev/null )
RC=$?
set -e
assert_eq "1" "$RC" "exit 1 when only the SECOND argument mismatches"
assert_contains "$STDERR" "non-negotiables.md" "stderr names the second (failing) file"
echo ""

# --- TS11: entry order is not significant (must-PASS non-canonical input) ---
# Harness row (ii). Reordering ENTRIES is permitted; reordering KEYS within
# an entry is not, since _emit_files hard-codes `- path:` as each record's
# first key. Quoted scalars are deliberately NOT used as the variant here —
# notice-frontmatter.sh strips whitespace but not quotes, so a quoted SHA
# would emit the quotes and the fix would loosen an injection guard.
echo "TS11: reordering registry ENTRIES does not change the verdict"
make_notice "$TMP_TS9/NOTICE-reordered" \
"  - path: references/leakage-vectors.md
    upstream-path: pii-detector/rules/leakage-vectors.md
    upstream-blob-sha: 15a46e529e789930149f4b9bce875bfe5c53e478
    local-blob-sha: $(git hash-object --no-filters "$SKILL_DIR/references/leakage-vectors.md")
    status: active-verbatim
  - path: references/fields.md
    upstream-path: pii-detector/patterns/fields.md
    upstream-blob-sha: c1bb748fe00a53b283efe66ec937fa39437d2efc
    local-blob-sha: $(git hash-object --no-filters "$SKILL_DIR/references/fields.md")
    status: active-eu-extended" \
"  - path: references/legal-consent.md
    local-blob-sha: $(git hash-object --no-filters "$SKILL_DIR/references/legal-consent.md")
    status: soleur-authored
  - path: references/non-negotiables.md
    local-blob-sha: $(git hash-object --no-filters "$SKILL_DIR/references/non-negotiables.md")
    status: soleur-authored"

set +e
( cd "$REPO_ROOT" && NOTICE_FILE="$TMP_TS9/NOTICE-reordered" bash "$INTEGRITY" \
  "$SKILL_DIR/references/fields.md" \
  "$SKILL_DIR/references/leakage-vectors.md" \
  "$SKILL_DIR/references/non-negotiables.md" \
  "$SKILL_DIR/references/legal-consent.md" >/dev/null 2>&1 )
RC=$?
set -e
assert_eq "0" "$RC" "exit 0 with entries in non-canonical order"
echo ""

# --- TS12: the mismatch message names a mechanism that exists (AC18) ---
# It told a blocked contributor to "run the vendor-drift workflow", which has
# not existed since #4483. It is the only exit they get at the moment their
# commit is refused.
echo "TS12: mismatch guidance does not name the deleted vendor-drift workflow"
if grep -q 'vendor-drift workflow' "$INTEGRITY"; then
  echo "  FAIL: mismatch message still points at the workflow deleted in #4483"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: mismatch message does not name the deleted workflow"
  PASS=$((PASS + 1))
fi
echo ""

# --- TS13: lefthook glob reaches every registry path, legacy/ included ---
# The pre-#7710 parity check (TS4) walked lifted-files only and matched two
# single-level patterns. Adding references/legacy/** to a registry without
# adding it to the glob would leave that file ungated while appearing pinned.
echo "TS13: lefthook glob covers every registry path including references/legacy/"
UNGLOBBED=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  rel_path="${line%%:*}"
  if [[ ! "$rel_path" =~ ^references/[^/]+\.md$ ]] && \
     [[ ! "$rel_path" =~ ^references/layers/[^/]+\.md$ ]] && \
     [[ ! "$rel_path" =~ ^references/legacy/[^/]+\.md$ ]]; then
    UNGLOBBED+=("$rel_path")
  fi
done < <(bash "$PARSER" lifted-files; bash "$PARSER" soleur-authored)
assert_eq "" "${UNGLOBBED[*]:-}" "every registry path matches a lefthook glob pattern"

for pat in \
  "plugins/soleur/skills/gdpr-gate/references/*.md" \
  "plugins/soleur/skills/gdpr-gate/references/layers/*.md" \
  "plugins/soleur/skills/gdpr-gate/references/legacy/*.md"; do
  if grep -qF -- "\"$pat\"" "$LEFTHOOK"; then
    echo "  PASS: lefthook declares glob $pat"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: lefthook is missing glob $pat"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

print_results
