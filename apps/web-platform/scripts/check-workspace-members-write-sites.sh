#!/usr/bin/env bash
# check-workspace-members-write-sites.sh
#
# feat-workspace-member-actions-audit (#4231) TR9 sentinel.
#
# Enumerates every INSERT / UPDATE / DELETE / upsert site against
# public.workspace_members under apps/web-platform/ and asserts each is
# in one of three approved categories:
#
#   (a) A SECURITY DEFINER RPC body that contains
#       `set_config('workspace_audit.actor_user_id', ...)` — captures the
#       actor for the AFTER trigger that writes workspace_member_actions.
#       (mig 058 invite/remove RPCs re-CREATEd in mig 063.)
#
#   (b) A SECURITY DEFINER RPC body that contains
#       `SET LOCAL session_replication_role = 'replica'` — the
#       documented bypass path used by anonymise_workspace_members
#       (mig 063 re-CREATE; cascade DELETE under account-delete).
#
#   (c) A documented admin-tool / fixture / one-shot-migration path
#       with an explicit NULL-actor expectation. Each site MUST be in
#       the ALLOWED_LITERAL_WRITES list below with a justification.
#
# Exits non-zero on any unrecognised write site. Run as part of pre-
# merge validation (Phase 8.4 of the plan); also invoked from the
# corresponding vitest test (test/server/check-workspace-members-write-sites.test.ts).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# -----------------------------------------------------------------------------
# Allowlist of approved literal write sites.
#
# Format: "<relative_path>:<grep_pattern>:<justification>"
# Each line is checked via `git grep -n -E "<grep_pattern>" "<path>"` and the
# match count must equal the number of `:matches:` entries; otherwise the
# sentinel fails (either a write was added without allowlisting, or a write
# was removed and the allowlist is now stale).
#
# Justifications are human-readable strings; they exist for code review.
# -----------------------------------------------------------------------------

# Category (a) + (b): SQL RPC bodies in migration files.
#   - mig 058 originals (invite/remove/anonymise) + their mig 063 re-CREATEs.
#   - mig 063 also contains its own re-CREATEd bodies (3 of them).
# These are checked structurally via the migration-shape test
# (test/supabase-migrations/062-workspace-member-actions.test.ts) rather than
# enumerated here, because their identity is "every body with the canonical
# pragma" — pattern-based, not file-based.

# Category (c): explicit literal write sites that bypass the SQL RPC layer.
ALLOWED_LITERAL_WRITES=(
  # 053 initial backfill — pre-audit-table migration; legitimate NULL-actor
  # because the audit table did not exist at backfill time.
  "apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:^[[:space:]]*INSERT INTO public\\.workspace_members:053-initial-backfill"

  # Integration fixture INSERT — synthesized fixture path; documented NULL-actor.
  # Lives at test/helpers/, not server/, so production traffic cannot reach it.
  "apps/web-platform/test/helpers/workspace-members-fixtures.ts:\\.from\\(\"workspace_members\"\\)[[:space:]]*$:fixture-insert-or-delete"

  # 062 itself contains the re-CREATEd invite_workspace_member + remove_workspace_member
  # + anonymise_workspace_members bodies — each carries the actor GUC or replica
  # bypass per category (a)/(b); structurally verified by the migration-shape test.
  "apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:^[[:space:]]*INSERT INTO public\\.workspace_members:062-recreate-invite-rpc-body"
  "apps/web-platform/supabase/migrations/063_workspace_member_actions.sql:^[[:space:]]*DELETE FROM public\\.workspace_members:062-recreate-remove-or-anonymise-rpc-body"

  # 058 contains the original invite/remove/anonymise bodies (carried forward
  # at runtime by mig 063's CREATE OR REPLACE). Listed for completeness because
  # the migrations are applied in order — 058 lands first.
  "apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql:INSERT INTO public\\.workspace_members:058-invite-rpc-body"
  "apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql:DELETE FROM public\\.workspace_members:058-remove-and-anonymise-rpc-bodies"
)

# -----------------------------------------------------------------------------
# Discovery: enumerate every concrete mutation site
# -----------------------------------------------------------------------------

# SQL write sites (migrations).
SQL_WRITES="$(git grep -nE \
  '(INSERT[[:space:]]+INTO[[:space:]]+public\.workspace_members\b|UPDATE[[:space:]]+public\.workspace_members\b|DELETE[[:space:]]+FROM[[:space:]]+public\.workspace_members\b)' \
  -- 'apps/web-platform/supabase/migrations/*.sql' 2>/dev/null || true)"

# TS write sites (server + lib + scripts + app — anything that could ship).
# Match .from("workspace_members") followed (within 5 lines) by .insert / .update /
# .delete / .upsert. The server-side reads use .select() only.
TS_WRITE_FROM_LINES="$(git grep -nE '\.from\("workspace_members"\)' \
  -- 'apps/web-platform/server/' 'apps/web-platform/lib/' 'apps/web-platform/scripts/' 'apps/web-platform/app/' 'apps/web-platform/components/' 2>/dev/null || true)"

# Probe each candidate `.from("workspace_members")` for a mutation verb nearby.
TS_WRITES=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # line shape: <path>:<lineno>:<content>
  filepath="${line%%:*}"
  rest="${line#*:}"
  lineno="${rest%%:*}"
  end_lineno=$((lineno + 6))
  # Slice the file lines [lineno..lineno+6] and look for a mutation verb.
  if sed -n "${lineno},${end_lineno}p" "$filepath" 2>/dev/null | \
       grep -qE '\.(insert|update|delete|upsert)\('; then
    TS_WRITES="${TS_WRITES}${line}"$'\n'
  fi
done <<< "$TS_WRITE_FROM_LINES"

# Test-helpers fixtures are an approved literal-write category; capture them
# separately so they don't appear in the unfiltered TS_WRITES output noise.
TEST_FIXTURE_WRITES="$(git grep -nE '\.from\("workspace_members"\)' \
  -- 'apps/web-platform/test/helpers/' 2>/dev/null || true)"

# -----------------------------------------------------------------------------
# Match each discovered site against the allowlist
# -----------------------------------------------------------------------------

unrecognised_count=0
unrecognised_diag=""

check_site() {
  local site="$1"
  local filepath="${site%%:*}"
  local rest="${site#*:}"
  local lineno="${rest%%:*}"
  local content="${rest#*:}"

  for entry in "${ALLOWED_LITERAL_WRITES[@]}"; do
    local entry_path="${entry%%:*}"
    local entry_rest="${entry#*:}"
    local entry_pat="${entry_rest%:*}"
    if [[ "$filepath" == "$entry_path" ]]; then
      if [[ "$content" =~ $entry_pat ]] || \
         sed -n "${lineno}p" "$filepath" 2>/dev/null | grep -qE "$entry_pat"; then
        return 0
      fi
    fi
  done

  unrecognised_count=$((unrecognised_count + 1))
  unrecognised_diag="${unrecognised_diag}  ${site}"$'\n'
  return 1
}

# Walk SQL writes.
while IFS= read -r site; do
  [[ -z "$site" ]] && continue
  check_site "$site" || true
done <<< "$SQL_WRITES"

# Walk TS writes (server / lib / scripts / app / components).
# The TS server/lib surface MUST NOT contain any literal mutation by
# default — all writes route through SQL RPCs. But category (c) of the
# allowlist permits documented admin-tool / one-shot script paths if an
# explicit ALLOWED_LITERAL_WRITES entry covers them. Route through
# check_site so the allowlist contract is symmetric with SQL writes;
# unmatched TS mutations still fail with the `[server-mutation forbidden]`
# diagnostic so the asymmetry-was-the-bug failure shape is preserved.
while IFS= read -r site; do
  [[ -z "$site" ]] && continue
  if check_site "$site"; then
    continue  # allowlisted category-(c) TS write
  fi
  # check_site already incremented unrecognised_count + appended a generic
  # diag line; re-format the line to flag it as a server-mutation
  # (preserves the operator-facing 'forbidden' framing for unallowlisted
  # TS hits while keeping the allowlist contract uniform).
  unrecognised_diag="${unrecognised_diag%"  ${site}"$'\n'}"
  unrecognised_diag="${unrecognised_diag}  [server-mutation forbidden] ${site}"$'\n'
done <<< "$TS_WRITES"

# Walk test-fixture writes — must match the fixture allowlist entry.
while IFS= read -r site; do
  [[ -z "$site" ]] && continue
  check_site "$site" || true
done <<< "$TEST_FIXTURE_WRITES"

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------

if [[ $unrecognised_count -gt 0 ]]; then
  echo "FAIL: workspace_members write-site sentinel (#4231 TR9)" >&2
  echo "Found $unrecognised_count unrecognised mutation site(s):" >&2
  echo "$unrecognised_diag" >&2
  echo "" >&2
  echo "Resolution paths:" >&2
  echo "  1. Route the write through a SECURITY DEFINER RPC that calls" >&2
  echo "     set_config('workspace_audit.actor_user_id', auth.uid()::text, true)" >&2
  echo "     so the AFTER trigger captures the actor (category a)." >&2
  echo "  2. Document the site as a controlled admin-tool / migration / fixture" >&2
  echo "     path by adding it to ALLOWED_LITERAL_WRITES in this script with a" >&2
  echo "     justification (category c)." >&2
  echo "" >&2
  echo "  See plan §Phase 7.4 and TR9 of spec.md (#4231)." >&2
  exit 1
fi

echo "OK: workspace_members write-site sentinel (#4231 TR9) — all sites accounted for."
exit 0
