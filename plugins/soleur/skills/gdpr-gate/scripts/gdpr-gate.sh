#!/usr/bin/env bash
# gdpr-gate advisory pre-commit hook (lefthook).
#
# Always exits 0 — the hook is advisory, never blocking. Blocking enforcement
# lives in /soleur:ship Phase 5.5 (post-PR). This hook prints a one-line
# stderr breadcrumb when staged paths match the canonical regulated-data
# regex (single source of truth: SKILL.md §"Path globs (canonical)").
#
# Telemetry: emits a `gdpr-gate-touch` event via .claude/hooks/lib/incidents.sh
# when a regulated-data path is touched. Telemetry survives even when the
# operator's terminal swallows stderr.
#
# Invoked from lefthook.yml:
#   gdpr-gate-advisory:
#     priority: 6
#     run: bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh {staged_files}

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

# shellcheck source=/dev/null
source "$REPO_ROOT/.claude/hooks/lib/incidents.sh"

# Single source of truth — mirrors SKILL.md §"Path globs (canonical)".
CANONICAL_REGEX='^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)'

matched=()
for f in "$@"; do
  if echo "$f" | grep -qE "$CANONICAL_REGEX"; then
    matched+=("$f")
  fi
done

if (( ${#matched[@]} > 0 )); then
  echo "gdpr-gate: regulated-data path touched (${matched[*]}); run /soleur:gdpr-gate" >&2
  emit_incident hr-gdpr-gate-on-regulated-data-surfaces applied \
    "regulated-data path touched: ${matched[0]}" 2>/dev/null || true
fi

exit 0
