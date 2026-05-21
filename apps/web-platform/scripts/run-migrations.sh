#!/usr/bin/env bash
set -euo pipefail

# Automated migration runner for Supabase/PostgreSQL.
# Applies unapplied SQL files from the migrations directory,
# tracking state in a _schema_migrations table.
#
# Usage: doppler run -c prd -- bash run-migrations.sh
# Requires: DATABASE_URL or DATABASE_URL_POOLER environment variable.
#   Prefers DATABASE_URL_POOLER (IPv4 pooler) for CI where IPv6 is unavailable.
# Rollback: See apps/web-platform/docs/migration-rollback.md

# Argument parsing.
# Placed before any side-effects (psql/DATABASE_URL checks) so --help works
# on a fresh checkout without env or psql installed.
# Long-options only, with the `=` form (e.g. `--bootstrap=skip`).
# `--bootstrap skip` (separate token) is not supported and falls through to
# the unknown-arg branch below — keep this constraint in mind when adding
# future flags.
bootstrap_mode="auto"  # auto = legacy bootstrap fires when table empty
for arg in "$@"; do
  case "$arg" in
    --bootstrap=skip) bootstrap_mode="skip" ;;
    --bootstrap=auto) bootstrap_mode="auto" ;;
    --help|-h)
      cat <<'USAGE'
Usage: run-migrations.sh [--bootstrap=skip|auto]

Applies SQL files from supabase/migrations/ in filename order, tracking state
in public._schema_migrations.

Options:
  --bootstrap=auto   (default) On an empty tracking table, seed sentinel rows
                     for migrations 001-010 (assumed pre-applied on legacy prd).
                     Required for the prd CI migrate job.
  --bootstrap=skip   Disable the bootstrap seed. Use this on first-time
                     provisioning of a fresh Supabase project where 001-010
                     have NOT been applied. All migrations apply in order.
                     Equivalent: BOOTSTRAP_MIGRATIONS=0 bash run-migrations.sh.
  --help, -h         Print this message and exit.

Environment:
  DATABASE_URL_POOLER     Preferred (IPv4 pooler) for CI.
  DATABASE_URL            Fallback (direct connection, IPv6).
  BOOTSTRAP_MIGRATIONS=0  Same effect as --bootstrap=skip. When set, this
                          OVERRIDES the flag — `BOOTSTRAP_MIGRATIONS=0` plus
                          `--bootstrap=auto` still results in skip mode.
USAGE
      exit 0 ;;
    *)
      echo "::error::Unknown argument: $arg"
      echo "Run with --help for usage."
      exit 2 ;;
  esac
done

# Env-var override: BOOTSTRAP_MIGRATIONS=0 forces skip mode regardless of flag.
# Set when CI/cron callers cannot easily change argv.
if [[ "${BOOTSTRAP_MIGRATIONS:-1}" == "0" ]]; then
  bootstrap_mode="skip"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"

command -v psql >/dev/null 2>&1 || { echo "::error::psql not found on PATH"; exit 1; }

# Prefer DATABASE_URL_POOLER (IPv4 pooler) for CI environments where IPv6 is unavailable.
# Falls back to DATABASE_URL (direct connection) for environments with IPv6 support.
DATABASE_URL="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"

if [[ -z "$DATABASE_URL" ]]; then
  echo "::error::Neither DATABASE_URL_POOLER nor DATABASE_URL is set. Ensure Doppler injects them."
  exit 1
fi

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "::error::Migrations directory not found: $MIGRATIONS_DIR"
  exit 1
fi

run_sql() {
  psql "$DATABASE_URL" --no-psqlrc --set ON_ERROR_STOP=1 -tAq -c "$1"
}

# Create tracking table if it does not exist
run_sql "CREATE TABLE IF NOT EXISTS public._schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);"

echo "Migration tracking table ready."

# Bootstrap: if the tracking table is empty, seed all known pre-existing migrations.
# These were applied manually to production before this runner existed.
# This list is frozen — new migrations are tracked automatically by the runner.
row_count=$(run_sql "SELECT count(*) FROM public._schema_migrations;")
if [[ "$row_count" -eq 0 ]]; then
  if [[ "$bootstrap_mode" == "skip" ]]; then
    echo "Empty tracking table detected — skipping bootstrap (--bootstrap=skip)."
    echo "All migrations will apply in filename order."
  else
    echo "Empty tracking table detected — bootstrapping known migrations..."
    run_sql "INSERT INTO public._schema_migrations (filename) VALUES
      ('001_initial_schema.sql'),
      ('002_add_byok_and_stripe_columns.sql'),
      ('003_fix_encrypted_key_column_type.sql'),
      ('004_add_not_null_iv_auth_tag.sql'),
      ('005_add_tc_accepted_at.sql'),
      ('006_restrict_tc_accepted_at_update.sql'),
      ('007_remediate_fabricated_tc_accepted_at.sql'),
      ('007_remove_tc_accepted_metadata_trust.sql'),
      ('008_add_tc_accepted_version.sql'),
      ('009_byok_hkdf_per_user_keys.sql'),
      ('010_tag_and_route.sql')
    ON CONFLICT (filename) DO NOTHING;"
    echo "Bootstrapped pre-existing migrations."
  fi
fi

# Refresh origin/main once so the unmerged-apply gate below (issue #4241)
# reads a current `git ls-tree`. Tolerate offline; emit a visible warning so
# a stale ref does not silently route every file through the ack-bypass path.
if ! git fetch --quiet origin main 2>/tmp/run-migrations-fetch.err; then
  echo "::warning::git fetch origin main failed (see /tmp/run-migrations-fetch.err); unmerged-apply gate may produce false positives."
fi

# Same-integer-prefix collision check (#4241 follow-up). The convention is
# "one forward migration per integer prefix"; the runner is filename-keyed,
# so two distinct `NNN_*.sql` files coexist as separate `_schema_migrations`
# rows and apply in alphabetical order — order set by accident, not
# convention. Severity is `::warning::` (not `::error::`) because main today
# already carries one pre-existing collision (053_append_kb_sync_row_rpc.sql
# from PR-H #4066 vs 053_template_authorizations.sql from PR-I #4213) that
# the runner has been tolerating since both merged; failing here would block
# every dev/prd apply until the collision is renumbered, which is its own
# follow-up. The warning surfaces the convention violation at every apply so
# the next reviewer who notices it can schedule the renumber.
collision_check=$(find "$MIGRATIONS_DIR" -maxdepth 1 -name '*.sql' -not -name '*.down.sql' -printf '%f\n' \
  | awk -F'_' '{print $1}' \
  | sort \
  | uniq -d)
if [[ -n "$collision_check" ]]; then
  echo "::warning::Migration filename prefix collision detected. Convention is one forward migration per integer prefix; renumber-on-rebase before adding a new collider."
  while IFS= read -r prefix; do
    [[ -z "$prefix" ]] && continue
    echo "::warning::  prefix '$prefix' is shared by:"
    find "$MIGRATIONS_DIR" -maxdepth 1 -name "${prefix}_*.sql" -not -name '*.down.sql' -printf '::warning::    - %f\n'
  done <<<"$collision_check"
fi

# Apply unapplied migrations in sorted order
applied=0
skipped=0

for migration_file in "$MIGRATIONS_DIR"/*.sql; do
  filename="$(basename "$migration_file")"

  # Skip down-migration artifacts. These are manual-rollback files (e.g.,
  # `053_template_authorizations.down.sql`) — they live alongside the
  # forward migration for paired-edit visibility but MUST NOT be applied
  # during forward runs. Bash glob expansion sorts `.down.sql` BEFORE
  # `.sql` (`.d` < `.s` lexically), so without this skip, a down file
  # whose first statement targets an as-yet-uncreated relation (e.g.,
  # `DROP TRIGGER ... ON public.<table>`) fails before the corresponding
  # `.sql` runs. **Why:** PR-I (#4213) — mig 053 down file led with
  # `DROP TRIGGER ... ON public.template_authorizations`; the dev apply
  # job failed with "relation does not exist" because `.down.sql` was
  # applied first. Mig 051's down file did not trip the same gate
  # because its first statement is `CREATE OR REPLACE FUNCTION
  # grant_action_class(...)` which is no-op-friendly against the prior
  # mig-048 grant function. Filter at the glob level so the runner is
  # independent of down-file shape.
  case "$filename" in
    *.down.sql) continue ;;
  esac

  # Filename shape whitelist — defense in depth for the SQL literal interpolations
  # below and the `git ls-tree` path interpolation in the unmerged-apply gate.
  # The *.sql glob does NOT exclude quotes, newlines, backslashes, or path-
  # traversal sequences in filenames; an attacker with repo-write would otherwise
  # have a small SQL-injection surface against the dev-only `_schema_migrations`
  # table via crafted migration filenames.
  case "$filename" in
    *[!a-zA-Z0-9._-]*)
      echo "::error::Migration filename contains unsupported characters: $filename"
      exit 1 ;;
  esac

  # Unmerged-apply gate (#4241). Block apply of migration filenames that are
  # not on origin/main unless the operator explicitly acks with
  # ALLOW_UNMERGED_DEV_APPLY=1. Closes the dev-vs-main drift class that broke
  # `Tenant integration (dev-Supabase)` on 2026-05-21 when migrations 053-057
  # from an unmerged branch were applied to dev. `git ls-tree origin/main`
  # reads the local fetch (refreshed once before the loop above). The opt-in
  # env var is a local-iteration valve: dev is unshared and synthetic-only per
  # hr-dev-prd-distinct-supabase-projects, so the ack here prevents leave-behind
  # drift rather than authorising a destructive prd write (distinct from the
  # prd-only ack class governed by hr-menu-option-ack-not-prod-write-auth).
  if [[ -z "$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename" 2>/dev/null)" ]]; then
    if [[ "${ALLOW_UNMERGED_DEV_APPLY:-0}" != "1" ]]; then
      echo "::error::Migration $filename is NOT on origin/main. Applying unmerged migrations to dev creates dev-vs-main drift (precedent: #4241). To override locally, re-run with ALLOW_UNMERGED_DEV_APPLY=1 and revert the dev schema before pushing — see knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md."
      exit 1
    fi
    echo "::warning::$filename is not on origin/main; proceeding under ALLOW_UNMERGED_DEV_APPLY=1."

    # Cross-branch collision warning (#4225 follow-up). The file just passed
    # the unmerged-apply gate under ALLOW_UNMERGED_DEV_APPLY=1 — surface
    # whether origin/main already carries DIFFERENT file(s) at the same
    # numeric prefix. That class fires when a sibling PR landed a same-
    # numbered migration to main WHILE this branch was in flight (the
    # actual #4225 → #4251 failure mode: branch's 054_workspace_member_
    # attestations was in flight when main landed 054_schema_migrations_
    # content_sha). The local same-prefix warning earlier in the script
    # only fires AFTER rebase; this inline surface catches the gap when
    # the operator applies BEFORE rebasing (direct-pg fallback, manual
    # psql, anything that bypasses this script's discipline).
    #
    # Severity is ::warning:: (not ::error::) to match the pre-loop
    # same-prefix tolerance — the 053-class triple-add (PR-H + PR-I +
    # this branch) is by-design and would otherwise block every CI run
    # for any future PR adding a sibling-prefix migration. The warning
    # is the load-bearing signal: operator who sees it in their CI log
    # has the chance to renumber before merge. See learning
    # 2026-05-21-postgrest-schema-cache-and-stale-plan-quoted-apply-state.md
    # §3 "Parallel-branch migration coordination" for the rename +
    # `public._schema_migrations` reconcile recovery pattern.
    file_prefix=$(printf '%s' "$filename" | awk -F'_' '{print $1}')
    if [[ "$file_prefix" =~ ^[0-9]{3}$ ]]; then
      main_with_prefix=$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/" 2>/dev/null \
        | awk '{print $NF}' \
        | xargs -I{} basename {} \
        | grep -E "^${file_prefix}_[^.]+\.sql$" \
        | grep -v '\.down\.sql$' \
        | grep -v "^${filename}$" || true)
      if [[ -n "$main_with_prefix" ]]; then
        echo "::warning::Cross-branch migration filename collision: branch '${filename}' shares prefix ${file_prefix} with origin/main file(s). Renumber the branch's collider to the next free prefix before merge (typical pattern: 054→058, 055→059, …) to avoid the tracking-table reconcile recovery class."
        # printf '%s\n' (NOT '%s') so the final coexists-with line is newline-
        # terminated — without the trailing newline, the next iteration's
        # ::warning::… line glues onto the same line and a regex looking for
        # `<prior-file>.*is not on origin/main` matches across the boundary
        # (broke run-migrations-unmerged-gate.test.ts positive-control case).
        printf '%s\n' "$main_with_prefix" | sed 's/^/::warning::  coexists-with: /'
      fi
    fi
  fi

  # Filenames are from a controlled glob (*.sql) AND have passed the shape
  # whitelist above — safe for direct interpolation.
  already_applied=$(run_sql "SELECT count(*) FROM public._schema_migrations WHERE filename = '$filename';")
  if [[ "$already_applied" -gt 0 ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  echo "Applying: $filename"
  # Compute the git blob SHA-1 of the file body so the drift probe can detect
  # same-filename content drift (mig 054 adds the content_sha column to
  # _schema_migrations). Same hash space as `git ls-tree origin/main`'s third
  # column. Mig 054 is itself the first row to carry content_sha; pre-054 rows
  # stay NULL by design (no apply-time history to retroactively populate).
  content_sha=$(git hash-object "$migration_file" 2>/dev/null || echo "")
  if [[ -z "$content_sha" ]]; then
    # Fall back to sha1sum on systems without git available (no git is a
    # broken state for this runner, but the script should still complete the
    # apply — drift probe just won't have content_sha to compare).
    content_sha=$(sha1sum "$migration_file" 2>/dev/null | awk '{print $1}' || echo "")
  fi
  # Apply migration and record it in a single atomic transaction. The INSERT
  # row carries content_sha when known; NULL otherwise (column is nullable).
  if ! {
    cat "$migration_file"
    if [[ -n "$content_sha" ]]; then
      printf "\nINSERT INTO public._schema_migrations (filename, content_sha) VALUES ('%s', '%s');\n" "$filename" "$content_sha"
    else
      printf "\nINSERT INTO public._schema_migrations (filename) VALUES ('%s');\n" "$filename"
    fi
  } | psql "$DATABASE_URL" --no-psqlrc --single-transaction --set ON_ERROR_STOP=1; then
    echo "::error::Migration failed: $filename"
    exit 1
  fi
  echo "  Applied successfully."
  applied=$((applied + 1))
done

echo "Migration run complete: $applied applied, $skipped skipped."
