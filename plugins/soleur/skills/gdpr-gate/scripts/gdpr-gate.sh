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

# Source telemetry helper if present. Downstream installs of the Soleur plugin
# may not ship .claude/hooks/lib/incidents.sh — preserve the always-exit-0
# advisory contract by no-op'ing emit_incident in that case rather than
# letting `set -e` abort before the breadcrumb.
INCIDENTS_LIB="$REPO_ROOT/.claude/hooks/lib/incidents.sh"
if [[ -f "$INCIDENTS_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$INCIDENTS_LIB"
else
  emit_incident() { :; }
fi

# Runtime staleness check (FR6 / TR2 / TR6).
#
# The gdpr-gate skill is partially driven by detection rules lifted from
# upstream gosprinto/compliance-skills (see plugins/soleur/skills/gdpr-gate/NOTICE).
# When the cron-driven re-vendor pipeline silently breaks (workflow disabled,
# GH outage, PR queued), the lifted rules go stale and the gate's
# "no findings" output becomes a false-clean signal on regulated PRs.
# The runtime banner is the load-bearing user-protection layer in that case.
#
# Banner emits to STDOUT (not stderr) — agent runtimes commonly swallow stderr.
# Gate exits 0 in all paths (advisory contract preserved).
# Subshell-exec (not source) so parser failure / deletion / future date all
# resolve to days_stale=999 → banner fires → gate stays advisory.
NOTICE_PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
days_stale=$(bash "$NOTICE_PARSER" days-stale 2>/dev/null || echo 999)
last_verified=$(bash "$NOTICE_PARSER" field last-verified 2>/dev/null || echo "unknown")
[[ -n "$last_verified" ]] || last_verified="unknown"
if (( days_stale > 30 )); then
  printf '⚠ gdpr-gate rules %s days stale (last verified %s) — output is advisory only and may miss recently-patched detection rules. Refresh: see knowledge-base/engineering/policies/content-vendoring.md\n' \
    "$days_stale" "$last_verified"
  emit_incident gdpr-gate-staleness warn "${days_stale}-days-stale" \
    2>/dev/null || true
fi
if (( days_stale > 90 )); then
  printf 'POSTURE_FAIL: gdpr-gate rules >90 days stale — compliance/critical posture row required. Operator chain: knowledge-base/engineering/policies/content-vendoring.md#posture-fail-operator-chain\n'
  emit_incident gdpr-gate-staleness deny "${days_stale}-days-stale-posture-fail" \
    2>/dev/null || true
fi

# Single source of truth — mirrors SKILL.md §"Path globs (canonical)".
CANONICAL_REGEX='^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)'

matched=()
for f in "$@"; do
  if [[ "$f" =~ $CANONICAL_REGEX ]]; then
    matched+=("$f")
  fi
done

if (( ${#matched[@]} > 0 )); then
  echo "gdpr-gate: regulated-data path touched (${matched[*]}); run /soleur:gdpr-gate" >&2
  emit_incident hr-gdpr-gate-on-regulated-data-surfaces applied \
    "regulated-data path touched: ${matched[0]}" 2>/dev/null || true
fi

exit 0
