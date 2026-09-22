#!/usr/bin/env bash
# Lint: on-main migration files are immutable (issue 8583 — the third leg
# of migration hygiene, after the unmerged-apply gate #4241 and the
# dev-ledger drift probe #7964).
#
# Once a file under apps/web-platform/supabase/migrations/ is merged to
# main it is, for all practical purposes, applied: tenant-integration
# applies main's migrations to dev on every push and the ledger records
# content_sha. An in-place edit is then silently skipped by the runner
# (already_applied short-circuit) while the ledger drifts red post-merge
# — the exact #8507/138_agent_engine_runs.sql incident. Behavior changes
# ship as a new NNN_*.sql, never as an edit to a merged file.
#
# Check: enumerate the PR diff's migration paths and compare each
# path's mode+blob sha between the base ref tip and HEAD via
# `git ls-tree`. Three deliberate properties:
#
#   * `--no-renames` is load-bearing — with default rename detection
#     `git diff --name-only` emits only the rename DESTINATION, so a
#     `git mv` on an on-main migration would evade enumeration entirely
#     (verified live in a fixture repo: R100 collapses to D + A).
#   * Comparison is ls-tree IDENTITY (mode + blob), not diff status —
#     an `A`-status path that already exists on main with different
#     content (the add-collides race: main gained the same numbered file
#     after the branch diverged) still fails.
#   * `*.down.sql` is exempt — run-migrations.sh never applies down files
#     (glob skip ~line 256) and the ledger never tracks them, so their
#     mutation cannot drift anything.
#
# Numbering beyond max-on-main is free to iterate: a path absent from
# the base ref's tree is skipped as "new", whatever its number.
#
# Usage:
#   bash lint-migration-immutability.sh --from-pr-diff
#       CI mode. base = origin/${BASE_REF:-main}, head = HEAD, plus a
#       best-effort `git fetch --quiet origin main` (mirrors
#       run-migrations.sh:124). On merge_group github.base_ref is empty,
#       so the default re-checks the queued candidate against the newest
#       origin/main — the sibling-merged-in-flight arm.
#   bash lint-migration-immutability.sh --base <ref> --head <ref> [--repo <dir>]
#       Explicit refs for tests and local runs. No fetch is attempted.
#
# Exit codes:
#   0  no on-main migration file was mutated (prints `migration-immutability: clean`)
#   1  one or more on-main files differ (each named via ::error::)
#   2  cannot measure (bad args, unresolvable ref, failed diff, wrong repo root)
#
# Summary line always prints the counted shape — touched / on-main-checked /
# new / exempt — so a degenerate enumeration (diff touched migrations yet
# zero files checked, e.g. a stubbed oracle) is audible in the log rather
# than indistinguishable from a real clean pass.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"
# Same identity assertion as lint-migration-fk-preconditions.sh: a wrong
# root is reachable (missing git, dubious-ownership fallback to pwd) and
# would let the diff below match nothing and exit 0 having examined none.
_assert_repo_root() {
  [[ -d "$1/apps/web-platform/supabase/migrations" ]] && return 0
  echo "lint-migration-immutability: FATAL: repo root resolved to '$1', which does not" >&2
  echo "  contain apps/web-platform/supabase/migrations. Refusing to diff against it." >&2
  return 1
}

usage() {
  cat <<'USAGE'
Usage: lint-migration-immutability.sh --from-pr-diff
       lint-migration-immutability.sh --base <ref> --head <ref> [--repo <dir>]

Fails when a PR mutates, deletes, or renames a supabase/migrations/*.sql
file that already exists on the base ref. New files (numbers beyond
max-on-base) are free to iterate; *.down.sql is exempt.

Remediation: land the change as a new NNN_*.sql migration.
USAGE
}

BASE=""
HEAD=""
REPO=""
FROM_PR_DIFF=0

# ---------- arg parsing (order-agnostic flags) ----------
if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-pr-diff) FROM_PR_DIFF=1; shift ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --head) HEAD="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "lint-migration-immutability: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$FROM_PR_DIFF" == "1" ]]; then
  REPO="$REPO_ROOT"
  BASE="origin/${BASE_REF:-main}"
  HEAD="HEAD"
  # Best-effort refresh so a stale local origin/main cannot false-green
  # (CI always fetches fresh; this covers local runs).
  git -C "$REPO" fetch --quiet --no-tags origin main 2>/dev/null || true
else
  if [[ -z "$BASE" || -z "$HEAD" ]]; then
    echo "lint-migration-immutability: --base and --head are both required (or use --from-pr-diff)" >&2
    usage
    exit 2
  fi
  [[ -z "$REPO" ]] && REPO="$REPO_ROOT"
fi

# An explicit --repo may point at a fixture repo that IS a valid root on
# its own terms — assert the same migrations-dir identity there.
_assert_repo_root "$REPO" || exit 2

# ---------- resolve refs (fail closed) ----------
if ! git -C "$REPO" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
  echo "::error::lint-migration-immutability: cannot resolve base ref '$BASE'" >&2
  exit 2
fi
if ! git -C "$REPO" rev-parse --verify --quiet "$HEAD^{commit}" >/dev/null; then
  echo "::error::lint-migration-immutability: cannot resolve head ref '$HEAD'" >&2
  exit 2
fi

# ---------- enumerate the diff ----------
# --no-renames: see header — rename detection would hide the source path.
if ! CHANGED=$(git -C "$REPO" diff --no-renames --name-only "$BASE...$HEAD" -- 'apps/web-platform/supabase/migrations/*.sql' 2>/dev/null); then
  echo "::error::lint-migration-immutability: git diff $BASE...$HEAD failed; failing closed." >&2
  exit 2
fi

touched=0
checked=0
skipped_new=0
exempt_down=0
violations=0

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  touched=$((touched + 1))

  case "$rel" in
    *.down.sql) exempt_down=$((exempt_down + 1)); continue ;;
  esac

  base_ent=$(git -C "$REPO" ls-tree "$BASE" -- "$rel" 2>/dev/null || true)
  if [[ -z "$base_ent" ]]; then
    # Not on the base ref — free to iterate regardless of number.
    skipped_new=$((skipped_new + 1))
    continue
  fi

  checked=$((checked + 1))
  head_ent=$(git -C "$REPO" ls-tree "$HEAD" -- "$rel" 2>/dev/null || true)
  # ls-tree line: "<mode> <type> <sha>\t<path>". Compare mode+sha (the
  # first two whitespace fields and the sha) — dropping the path column
  # keeps the comparison identity-shaped on both sides.
  base_id=$(printf '%s\n' "$base_ent" | awk '{print $1, $3}')
  head_id=$(printf '%s\n' "$head_ent" | awk '{print $1, $3}')

  if [[ -z "$head_ent" ]]; then
    echo "::error::$rel: on-main migration file deleted or renamed away — on-main migration files are immutable; land the change as a new NNN_*.sql (#8583)" >&2
    violations=$((violations + 1))
  elif [[ "$base_id" != "$head_id" ]]; then
    echo "::error::$rel: on-main migration file mutated (mode/blob differs vs $BASE) — on-main migration files are immutable; land the change as a new NNN_*.sql (#8583)" >&2
    violations=$((violations + 1))
  fi
done <<<"$CHANGED"

if [[ "$violations" -gt 0 ]]; then
  echo "" >&2
  echo "::error::lint-migration-immutability: $violations on-main migration mutation(s) — see #8583" >&2
  echo "migration-immutability: RED (touched=$touched on-main-checked=$checked new=$skipped_new down-exempt=$exempt_down violations=$violations)"
  exit 1
fi

if [[ "$touched" -gt 0 && "$checked" -eq 0 ]]; then
  # Audible degenerate case: the diff touched migration paths but nothing
  # was compared — every path is new or exempt. Legitimate for an
  # all-new-migrations PR, but it must be VISIBLE so a stubbed/broken
  # oracle cannot produce a clean-looking report indistinguishable from
  # a real check (mutation matrix row 6).
  echo "::notice::migration-immutability: 0 on-main migration files checked — all $touched touched path(s) are new or exempt"
fi

echo "migration-immutability: clean (touched=$touched on-main-checked=$checked new=$skipped_new down-exempt=$exempt_down)"
exit 0
