#!/usr/bin/env bash
# Lint: enforce to_regclass preconditions on cross-file FK references in
# supabase/migrations/*.sql (Delta 2 of issue 4325 hardening bundle).
#
# Every new migration whose body has a `REFERENCES public.<table>` where
# the target is created in a DIFFERENT file MUST include a preceding
# `to_regclass('public.<table>')` precondition block, so a schema-vs-
# ledger split surfaces a self-describing error at the precondition
# line — not a cryptic FK parser trace three layers deep.
#
# Canonical precondition shape (from learning
# 2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md Part 2):
#
#   DO $$
#   BEGIN
#     IF to_regclass('public.<expected-relation>') IS NULL THEN
#       RAISE EXCEPTION USING
#         MESSAGE = 'Migration N precondition failed: …',
#         DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
#         HINT    = 'Recovery: knowledge-base/project/learnings/…';
#     END IF;
#   END $$;
#
# This lint checks PRESENCE of `to_regclass('public.<table>')` somewhere
# in the file for each cross-file FK target. It does NOT validate the
# RAISE EXCEPTION shape — that level of structural enforcement would
# require a SQL parser. The presence check is the load-bearing signal.
#
# Usage:
#   bash lint-migration-fk-preconditions.sh path/to/mig.sql [path/to/another.sql ...]
#   bash lint-migration-fk-preconditions.sh --from-pr-diff  # auto-scan PR diff
#
# Exit codes:
#   0  all checked files pass
#   1  one or more files have unguarded cross-file FK references
#   2  invocation error (bad args, missing files)
#
# Scope: best-effort regex against the codebase convention (uppercase
# DDL keywords, lowercase + public.-qualified relation names). Mirrors
# the regex in run-migrations.sh:282-287 + preflight-schema-vs-ledger.sh:68.
# Shapes outside that convention (lowercase `references`, schema-less
# `<name>`, quoted `"public"."Foo"`, dynamic `EXECUTE format(...)`)
# bypass this lint; the runtime probe + FK parser remain the last lines
# of defense.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"

# Resolve repo root so --from-pr-diff's git ls / git diff results (repo-
# relative paths) work regardless of caller CWD (`working-directory:
# apps/web-platform` in CI, or running from repo root locally).
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"

usage() {
  cat <<'USAGE'
Usage: lint-migration-fk-preconditions.sh <file> [<file> ...]
       lint-migration-fk-preconditions.sh --from-pr-diff

Validates that every cross-file `REFERENCES public.<table>` in each
listed migration file is preceded by a `to_regclass('public.<table>')`
precondition. Self-FK references (target created in same file) are
exempt.

Use --from-pr-diff to auto-scan migrations added/modified vs origin/main.
USAGE
}

# ---------- arg parsing ----------
if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

declare -a files=()
if [[ "$1" == "--from-pr-diff" ]]; then
  # Refresh origin/main best-effort (mirrors run-migrations.sh:124).
  git -C "$REPO_ROOT" fetch --quiet origin main 2>/dev/null || true
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # Skip down-sibling files — they're manual rollback; lint applies to
    # forward migrations only.
    case "$f" in
      *.down.sql) continue ;;
    esac
    # git diff returns repo-relative paths; absolutize against repo root
    # so subsequent `[[ -f ]]` works regardless of caller CWD.
    files+=("$REPO_ROOT/$f")
  done < <(git -C "$REPO_ROOT" diff origin/main...HEAD --name-only --diff-filter=AM -- 'apps/web-platform/supabase/migrations/*.sql' 2>/dev/null || true)
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "lint-migration-fk-preconditions: no migration changes in PR diff; nothing to check."
    exit 0
  fi
else
  for arg in "$@"; do
    case "$arg" in
      --help|-h) usage; exit 0 ;;
      *) files+=("$arg") ;;
    esac
  done
fi

# ---------- inventory cross-file CREATE TABLEs ----------
# Build the set of public.<table> names created across ALL migrations
# (not just the PR diff) so we can distinguish "FK target lives in
# another file" (must guard) from "FK target is a fresh table this
# diff introduces somewhere" (must guard via the OTHER file's CREATE).
declare -A all_creates=()
if [[ -d "$MIGRATIONS_DIR" ]]; then
  while IFS= read -r tbl; do
    [[ -z "$tbl" ]] && continue
    all_creates["$tbl"]=1
  done < <(grep -hoE 'CREATE TABLE (IF NOT EXISTS )?public\.[a-z_][a-z0-9_]*' "$MIGRATIONS_DIR"/*.sql 2>/dev/null \
           | awk '{print $NF}' | sort -u)
fi

# ---------- per-file check ----------
violations=0
for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "::error::lint-migration-fk-preconditions: file not found: $file" >&2
    exit 2
  fi

  filename=$(basename "$file")

  # Down siblings are operator-only rollback; skip.
  case "$filename" in
    *.down.sql) continue ;;
  esac

  # Extract REFERENCES public.<table> mentions.
  referenced=$(grep -oE 'REFERENCES public\.[a-z_][a-z0-9_]*' "$file" 2>/dev/null \
               | awk '{print $2}' | sort -u || true)

  # Extract same-file CREATE TABLE declarations (self-FK exclusion).
  same_file_creates=$(grep -oE 'CREATE TABLE (IF NOT EXISTS )?public\.[a-z_][a-z0-9_]*' "$file" 2>/dev/null \
                      | awk '{print $NF}' | sort -u || true)

  # Cross-file deps = referenced \ same_file_creates.
  cross_file_deps=$(comm -23 \
    <(printf '%s\n' "$referenced" | sed '/^$/d') \
    <(printf '%s\n' "$same_file_creates" | sed '/^$/d') 2>/dev/null || true)

  # For each cross-file target, check that `to_regclass('<target>')` is
  # mentioned somewhere in the file.
  while IFS= read -r tbl; do
    [[ -z "$tbl" ]] && continue
    if ! grep -qE "to_regclass\(\s*'$tbl'\s*\)" "$file"; then
      echo "::error::$filename: cross-file FK reference to '$tbl' without to_regclass precondition" >&2
      echo "::error::  Add a DO \$\$ … to_regclass('$tbl') IS NULL THEN RAISE EXCEPTION … END \$\$ block" >&2
      echo "::error::  See: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md" >&2
      violations=$((violations + 1))
    fi
  done <<<"$cross_file_deps"
done

if [[ "$violations" -gt 0 ]]; then
  echo "" >&2
  echo "::error::lint-migration-fk-preconditions: $violations unguarded cross-file FK reference(s)" >&2
  exit 1
fi

echo "lint-migration-fk-preconditions: ${#files[@]} file(s) checked, no violations."
exit 0
