#!/usr/bin/env bash
# vendor-pin-integrity.sh — pre-commit lefthook target (FR5, TR1).
#
# For each file argument: compute `git hash-object --no-filters` against the
# working-tree contents and compare to the blob-sha pinned in NOTICE
# frontmatter. Exit 1 on any mismatch (or on a staged file that is not in
# the NOTICE registry — silent local addition).
#
# `--no-filters` is load-bearing per TR1: skips gitattributes line-ending
# conversion that would otherwise diverge from upstream blob SHAs on
# Windows/CRLF setups.
#
# Invoked from lefthook.yml:
#   vendor-pin-integrity:
#     priority: 6
#     glob:
#       - "plugins/soleur/skills/gdpr-gate/references/fields.md"
#       - ...
#     run: bash plugins/soleur/skills/gdpr-gate/scripts/vendor-pin-integrity.sh {staged_files}
#
# NOTICE_FILE env var overrides the parser's default NOTICE path so tests can
# point at fixture frontmatter without mutating the live skill NOTICE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PARSER="$SCRIPT_DIR/notice-frontmatter.sh"
SKILL_PREFIX="plugins/soleur/skills/gdpr-gate"

# Build expected map (rel_path → blob-sha) from NOTICE.
declare -A EXPECTED=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  rel_path="${line%%:*}"
  sha="${line##*:}"
  EXPECTED["$SKILL_PREFIX/$rel_path"]="$sha"
done < <(bash "$PARSER" lifted-files)

mismatches=0
for f in "$@"; do
  # Normalise to canonical repo-relative for registry lookup. `realpath -m`
  # resolves `..` segments without requiring the file to exist (covers the
  # synthetic-deletion case below).
  if [[ "$f" == /* ]]; then
    abs="$(realpath -m "$f" 2>/dev/null || echo "$f")"
    rel="${abs#"$REPO_ROOT"/}"
  else
    rel="$f"
  fi

  # NOTICE itself is in the lefthook glob (any byte change should re-run the
  # integrity gate) but is not a lifted-files registry entry. Skip the
  # registry check for it; its content is governed by the workflow's
  # NOTICE-bump step + reviewer eyes.
  if [[ "$rel" == "$SKILL_PREFIX/NOTICE" ]]; then
    continue
  fi

  expected="${EXPECTED[$rel]:-}"
  if [[ -z "$expected" ]]; then
    echo "vendor-pin-integrity: $rel is staged but not in NOTICE lifted-files — silent local addition? Update NOTICE registry or remove the file." >&2
    mismatches=$((mismatches + 1))
    continue
  fi

  if [[ ! -f "$REPO_ROOT/$rel" ]]; then
    echo "vendor-pin-integrity: $rel listed in NOTICE but missing from working tree" >&2
    mismatches=$((mismatches + 1))
    continue
  fi

  actual="$(git hash-object --no-filters "$REPO_ROOT/$rel")"
  if [[ "$actual" != "$expected" ]]; then
    echo "vendor-pin-integrity: BLOB SHA mismatch on $rel (expected $expected, got $actual). Either revert the local edit or run the vendor-drift workflow to bump NOTICE." >&2
    mismatches=$((mismatches + 1))
  fi
done

if (( mismatches > 0 )); then
  exit 1
fi

exit 0
