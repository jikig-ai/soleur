#!/usr/bin/env bash
# Lint: on-main migration files are immutable (issue 8583 — the third leg
# of migration hygiene, after the unmerged-apply gate #4241 and the
# #4241 dev-ledger drift probe, made fail-loud per #7964).
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
#   bash lint-migration-immutability.sh --from-pr-diff [--repo <dir>]
#       CI mode. base = origin/${BASE_REF:-main}, head = HEAD, plus a
#       best-effort `git fetch` of the base ref (mirrors the pre-loop
#       fetch in run-migrations.sh). --repo lets CI run a copy of this
#       script extracted elsewhere (the workflow executes the BASE-ref
#       copy via `git show` so a PR cannot weaken the guard that judges
#       it) while operating on the checkout. On merge_group
#       github.base_ref is empty, so the default re-checks the queued
#       candidate against the newest origin/main — the
#       sibling-merged-in-flight arm.
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
Usage: lint-migration-immutability.sh --from-pr-diff [--repo <dir>]
       lint-migration-immutability.sh --base <ref> --head <ref> [--repo <dir>]

Fails when a PR mutates, deletes, or renames a supabase/migrations/*.sql
file that already exists on the base ref. New files (numbers beyond
max-on-base) are free to iterate; *.down.sql is exempt.

Exit codes:
  0  no on-main migration file was mutated (prints `migration-immutability: clean`)
  1  one or more on-main files differ (each named via ::error::)
  2  cannot measure (bad args, unresolvable ref, failed diff, wrong repo root)

Remediation: land the change as a new NNN_*.sql migration.
Break-glass: a file that is on main but was NEVER successfully applied
(apply failed → no ledger row → no drift) may still need an in-place fix;
that path is a deliberate, auditable admin/ruleset-bypass merge — see #8583.
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

need_value() {
  # A flag as the last arg leaves $#=1: `${2:-}` yields "" and `shift 2`
  # is a non-zero no-op that leaves $1 unchanged — the while loop would
  # re-match the same flag forever (an agent-facing hang, not an error).
  [[ $# -ge 2 ]] && return 0
  echo "lint-migration-immutability: $1 requires a value" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-pr-diff) FROM_PR_DIFF=1; shift ;;
    --base) need_value "$@"; BASE="$2"; shift 2 ;;
    --head) need_value "$@"; HEAD="$2"; shift 2 ;;
    --repo) need_value "$@"; REPO="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "lint-migration-immutability: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$FROM_PR_DIFF" == "1" ]]; then
  if [[ -n "$BASE" || -n "$HEAD" ]]; then
    echo "lint-migration-immutability: --from-pr-diff cannot be combined with --base/--head" >&2
    exit 2
  fi
  [[ -z "$REPO" ]] && REPO="$REPO_ROOT"
  base_ref="${BASE_REF:-main}"
  base_ref="${base_ref#refs/heads/}"
  BASE="origin/$base_ref"
  HEAD="HEAD"
else
  if [[ -z "$BASE" || -z "$HEAD" ]]; then
    echo "lint-migration-immutability: --base and --head are both required (or use --from-pr-diff)" >&2
    usage
    exit 2
  fi
  [[ -z "$REPO" ]] && REPO="$REPO_ROOT"
fi

# An explicit --repo may point at a fixture repo that IS a valid root on
# its own terms — assert the same migrations-dir identity there. The
# assertion precedes the fetch below deliberately: the fetch is a WRITE
# (updates refs/remotes/*, appends to the reflog, writes FETCH_HEAD) and
# must not land in a wrongly-resolved repository — sibling precedent at
# lint-migration-fk-preconditions.sh.
_assert_repo_root "$REPO" || exit 2

if [[ "$FROM_PR_DIFF" == "1" ]]; then
  # Best-effort refresh so a stale local origin/<base> cannot false-green
  # (CI always fetches fresh; this covers local runs). Failure is warned,
  # not silent — a stale base weakens the add-collides arm.
  git -C "$REPO" fetch --quiet --no-tags origin "$base_ref" 2>/dev/null \
    || echo "::warning::lint-migration-immutability: best-effort fetch of origin/$base_ref failed; comparing against possibly-stale ref"
fi

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
# -z: NUL-delimited output so paths containing spaces or non-ASCII bytes
# are not C-quoted (a quoted literal would not match an ls-tree pathspec
# and would silently classify as "new"). Kept in a temp file because a
# bash variable cannot hold NUL bytes.
if ! DIFF_FILE="$(mktemp)"; then
  echo "::error::lint-migration-immutability: mktemp failed; failing closed." >&2
  exit 2
fi
trap 'rm -f "$DIFF_FILE"' EXIT
if ! git -C "$REPO" diff --no-renames --name-only -z "$BASE...$HEAD" -- 'apps/web-platform/supabase/migrations/*.sql' > "$DIFF_FILE"; then
  echo "::error::lint-migration-immutability: git diff $BASE...$HEAD failed; failing closed." >&2
  exit 2
fi

touched=0
checked=0
skipped_new=0
exempt_down=0
violations=0

while IFS= read -r -d '' rel; do
  [[ -z "$rel" ]] && continue
  touched=$((touched + 1))

  case "$rel" in
    *.down.sql) exempt_down=$((exempt_down + 1)); continue ;;
  esac

  if ! base_ent=$(git -C "$REPO" ls-tree "$BASE" -- "$rel" </dev/null); then
    # rc != 0 is an oracle failure, not "absent" (absent is rc 0 + empty)
    # — degrading it to skipped-new would be a silent false-green.
    echo "::error::lint-migration-immutability: ls-tree failed for '$rel' at $BASE; failing closed." >&2
    exit 2
  fi
  if [[ -z "$base_ent" ]]; then
    # Not on the base ref — free to iterate regardless of number, but the
    # head entry must be a REGULAR blob: a symlink (120000) or gitlink
    # (160000) admitted here is a persistent unguarded mutation channel —
    # the runner follows the link at apply time while the ledgered blob
    # stays byte-identical (review: E6).
    if ! head_new=$(git -C "$REPO" ls-tree "$HEAD" -- "$rel" </dev/null); then
      echo "::error::lint-migration-immutability: ls-tree failed for '$rel' at $HEAD; failing closed." >&2
      exit 2
    fi
    new_mode=$(printf '%s\n' "$head_new" | awk '{print $1}')
    if [[ "$new_mode" != "100644" && "$new_mode" != "100755" ]]; then
      echo "::error::$rel: new migration path is not a regular file (mode ${new_mode:-absent}) — symlinks/gitlinks cannot be ledgered safely" >&2
      violations=$((violations + 1))
      continue
    fi
    skipped_new=$((skipped_new + 1))
    continue
  fi

  checked=$((checked + 1))
  if ! head_ent=$(git -C "$REPO" ls-tree "$HEAD" -- "$rel" </dev/null); then
    echo "::error::lint-migration-immutability: ls-tree failed for '$rel' at $HEAD; failing closed." >&2
    exit 2
  fi
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
done < "$DIFF_FILE"

if [[ "$violations" -gt 0 ]]; then
  echo "" >&2
  echo "::error::lint-migration-immutability: $violations on-main migration mutation(s) — see #8583" >&2
  echo "::error::  Reproduce locally: bash apps/web-platform/scripts/lint-migration-immutability.sh --base origin/main --head HEAD" >&2
  echo "migration-immutability: RED (touched=$touched on-main-checked=$checked new=$skipped_new down-exempt=$exempt_down violations=$violations)"
  exit 1
fi

if [[ "$touched" -gt 0 && "$checked" -eq 0 ]]; then
  # Audible degenerate case: the diff touched migration paths but nothing
  # was compared — every path is new or exempt. Legitimate for an
  # all-new-migrations PR, but it must be VISIBLE so a stubbed/broken
  # oracle cannot produce a clean-looking report indistinguishable from
  # a real check (mutation matrix row 6).
  echo "::notice::lint-migration-immutability: 0 on-main migration files checked — all $touched touched path(s) are new or exempt"
fi

echo "migration-immutability: clean (touched=$touched on-main-checked=$checked new=$skipped_new down-exempt=$exempt_down)"
exit 0
