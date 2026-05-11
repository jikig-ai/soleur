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
#
# Trust-binding (#3535): invoke parser twice and compute MIN in the caller
# frame. NOTICE last-verified is operator-controlled (a PR can backdate it);
# scheduled-content-vendor-drift workflow run timestamp is not. Taking the
# MIN ensures a fresh-looking last-verified cannot suppress a stale-cron
# banner. NOTICE_FILE and GH_TOKEN propagate explicitly — Bash subshell-exec
# does NOT inherit them otherwise. Operator-attested-mode banner fires only
# when the cron binding is unavailable AND last-verified is parseable — when
# both are 999 the existing 30d/90d banners cover the case.
NOTICE_PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
notice_days_stale=$(NOTICE_FILE="${NOTICE_FILE:-}" \
  bash "$NOTICE_PARSER" days-stale 2>/dev/null || echo 999)
cron_days_stale=$(NOTICE_FILE="${NOTICE_FILE:-}" \
  GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}" \
  bash "$NOTICE_PARSER" cron-run-stale 2>/dev/null || echo 999)

# MIN-of-both compute (caller frame — Bash env exports drop across the
# subshell-exec boundary, so the comparison must live here).
if [[ "$cron_days_stale" != "999" && "$notice_days_stale" != "999" ]]; then
  if (( cron_days_stale < notice_days_stale )); then
    days_stale="$cron_days_stale"
    emit_incident gdpr-gate-cron-binding min-wins \
      "cron=${cron_days_stale} notice=${notice_days_stale}" \
      2>/dev/null || true
  else
    days_stale="$notice_days_stale"
    emit_incident gdpr-gate-cron-binding applied \
      "cron=${cron_days_stale} notice=${notice_days_stale}" \
      2>/dev/null || true
  fi
elif [[ "$cron_days_stale" != "999" ]]; then
  days_stale="$cron_days_stale"
  emit_incident gdpr-gate-cron-binding applied \
    "cron-only=${cron_days_stale}" 2>/dev/null || true
else
  days_stale="$notice_days_stale"
fi

last_verified=$(NOTICE_FILE="${NOTICE_FILE:-}" \
  bash "$NOTICE_PARSER" field last-verified 2>/dev/null || echo "unknown")
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

  # Operator-attested-mode banner — fires ONLY when (a) a regulated path is
  # being judged this commit AND (b) the cron binding is unavailable but
  # NOTICE last-verified is parseable. Gating on matched paths prevents
  # banner-fatigue (otherwise the banner would fire on every commit in a
  # subagent shell without GH_TOKEN, training operators to ignore the
  # signal). Banner literal is load-bearing: the self-test asserts it
  # verbatim. See review finding from user-impact-reviewer #3541.
  if [[ "$cron_days_stale" == "999" && "$notice_days_stale" != "999" ]]; then
    printf 'ℹ gdpr-gate: operator-attested mode (no GH_TOKEN available — cron-run timestamp unverified, falling back to NOTICE last-verified)\n'
    emit_incident gdpr-gate-cron-binding unavailable \
      "no-token-or-gh-cli" 2>/dev/null || true
  fi
fi

exit 0
