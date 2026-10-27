#!/usr/bin/env bash
# Lint: enforce explicit api-role GRANTs on public-schema relations created by
# supabase/migrations/*.sql (ADR-303 — the SUBORDINATE static tier of the
# two-tier table-grant guard; the runtime rls-fuzz grant gate is authoritative).
#
# WHY: on 2026-10-30 hosted Supabase stopped auto-granting Data API access to
# new `public` tables (changelog 45329). Every migration merged after the flip
# that creates a relation without explicit GRANTs produces a table the Data
# API cannot see (42501) — on prd for anything created post-flip, and on every
# fresh environment (new project, preview branch, the rls-authz-fuzz stack)
# for anything in the corpus.
#
# THE CONTRACT: every file checked here that creates a public relation (table,
# view, materialized view — temp and partition-child excluded) must carry an
# in-file `GRANT ... TO (anon|authenticated|service_role)` naming it (the
# column-list form `GRANT SELECT (a,b) ON TABLE <rel> TO <role>` counts — it IS
# api exposure), or a `-- soleur:no-data-api: <rel> — <reason>` sentinel
# (`public.<rel>` accepted; reason REQUIRED — a reason-free exemption is an
# allowlist entry with no rationale). Tables with serial/identity columns —
# including `CREATE TABLE … (LIKE src INCLUDING ALL|IDENTITY)` copies —
# additionally need a sequence `GRANT USAGE` (post-flip sequences keep no
# USAGE default) or the sentinel; `create sequence` needs the same.
# `GRANT … ON ALL TABLES/SEQUENCES IN SCHEMA public` is NOT a satisfying form
# (blanket over-grant — flagged outright).
#
# DETECTION runs on noise-stripped SQL (comments, dollar-quoted bodies,
# single-quoted strings removed) via the JS engine in
# lib/lint-migration-api-grants.mjs — a line-scan would false-positive on a
# `create table` inside a comment and false-negative on a GRANT inside an
# EXECUTE string. The engine is a faithful port of the
# test/migration-lint/definer-grants.ts stripSqlNoise state machine
# (ADR-112 precedent), runnable under ambient `node` — required because this
# step in tenant-integration.yml executes BEFORE setup-node/npm ci.
#
# Usage:
#   bash lint-migration-api-grants.sh path/to/mig.sql [path/to/another.sql ...]
#   bash lint-migration-api-grants.sh --from-pr-diff  # auto-scan PR diff
#
# Exit codes:
#   0  all checked files pass
#   1  one or more files create an ungranted public relation
#   2  invocation error (bad args, missing files, no JS runtime)
#
# Scope: the PR-diff window only — the corpus is deliberately NOT asserted
# (pre-existing ungranted create-table files are covered by migration 174, not
# self-grants). A relation created via dynamic `EXECUTE format('create table
# %I', …)` inside a DO block is invisible to source-form detection — the
# live-catalog fuzz gate is the documented backstop (ADR-303).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/lib/lint-migration-api-grants.mjs"

# Resolve repo root so --from-pr-diff's git diff results (repo-relative paths)
# work regardless of caller CWD (working-directory: apps/web-platform in CI, or
# running from repo root locally). Mirrors lint-migration-fk-preconditions.sh.
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"
# Assert IDENTITY, not non-emptiness — a wrongly-resolved root makes the diff
# below match nothing and the lint exits 0 having examined none (silent false
# green); a missing migrations dir is the proof the root is wrong.
_assert_repo_root() {
  [[ -d "$1/apps/web-platform/supabase/migrations" ]] && return 0
  echo "lint-migration-api-grants: FATAL: repo root resolved to '$1', which does not" >&2
  echo "  contain apps/web-platform/supabase/migrations. Refusing to fetch or diff against it." >&2
  return 1
}
_assert_repo_root "$REPO_ROOT" || exit 2

usage() {
  cat <<'USAGE'
Usage: lint-migration-api-grants.sh <file> [<file> ...]
       lint-migration-api-grants.sh --from-pr-diff

Validates that every public relation a migration creates carries an in-file
api-role GRANT (or a soleur:no-data-api sentinel with a reason), and that
serial/identity tables carry a sequence GRANT USAGE.

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
  # Refresh origin/main (mirrors the fetch in run-migrations.sh's
  # unmerged-apply gate). NOT best-effort: a failed fetch leaves origin/main
  # stale or absent, and diffing against a missing ref exits nonzero — which
  # `|| true` used to swallow into "no files changed" → a silent false-green
  # over a PR that was never examined. Fail CLOSED (2) on either error.
  # (`cmd && rc=0 || rc=$?` — -e-safe and correct under this script's `set -u`
  # without -e, where a bare failing command would otherwise still be caught.)
  fetch_out="$(git -C "$REPO_ROOT" fetch --no-tags origin main 2>&1)" && fetch_rc=0 || fetch_rc=$?
  if [[ "$fetch_rc" -ne 0 ]]; then
    echo "::error::lint-migration-api-grants: 'git fetch origin main' failed (rc=${fetch_rc}) — the PR-diff window is not established. ${fetch_out}" >&2
    exit 2
  fi
  diff_out="$(git -C "$REPO_ROOT" diff origin/main...HEAD --name-only --diff-filter=AMR -- 'apps/web-platform/supabase/migrations/*.sql' 2>&1)" && diff_rc=0 || diff_rc=$?
  if [[ "$diff_rc" -ne 0 ]]; then
    echo "::error::lint-migration-api-grants: 'git diff origin/main...HEAD' failed (rc=${diff_rc}) — refusing to pass over an unexamined diff. ${diff_out}" >&2
    exit 2
  fi
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    # Skip down-sibling files — they're manual rollback; lint applies to
    # forward migrations only.
    case "$f" in
      *.down.sql) continue ;;
    esac
    # git diff returns repo-relative paths; absolutize against repo root
    # so subsequent [[ -f ]] works regardless of caller CWD. The diff filter
    # includes R (renamed+modified — for a rename git reports the NEW path,
    # which is the file we lint); a rename-only entry still passes the
    # [[ -f ]] check below, and a renamed migration must not escape the lint.
    files+=("$REPO_ROOT/$f")
  done <<<"$diff_out"
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "lint-migration-api-grants: no migration changes in PR diff; nothing to check."
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

# ---------- per-file pre-checks (existence + down-sibling skip) ----------
declare -a check=()
for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "::error::lint-migration-api-grants: file not found: $file" >&2
    exit 2
  fi
  case "$(basename "$file")" in
    *.down.sql) continue ;;  # operator-only rollback, never applied
  esac
  check+=("$file")
done

if [[ ${#check[@]} -eq 0 ]]; then
  echo "lint-migration-api-grants: 0 file(s) to check, no violations."
  exit 0
fi

# ---------- JS engine ----------
# The step runs before setup-node/npm ci in tenant-integration, so the engine
# must run on whatever runtime already exists: ambient `node` (present on GH
# runners), then `bun`, then a repo-installed tsx. Absent ALL of them we fail
# CLOSED (2) — never a silent pass over files we could not parse.
RUNNER=""
for cand in node bun "$SCRIPT_DIR/../node_modules/.bin/tsx" tsx; do
  command -v "$cand" >/dev/null 2>&1 && { RUNNER="$cand"; break; }
done
if [[ -z "$RUNNER" || ! -f "$ENGINE" ]]; then
  echo "::error::lint-migration-api-grants: cannot run the detection engine (missing JS runtime or $ENGINE). Failing closed." >&2
  exit 2
fi

"$RUNNER" "$ENGINE" "${check[@]}"
exit $?
