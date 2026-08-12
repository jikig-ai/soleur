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
#
# CODE ROOT, not a data root (#7450; ADR-179's classification). This path gets
# SOURCED, so it executes in THIS shell — and it must therefore never be derived
# from `git rev-parse --show-toplevel`, which on the review path resolves to the
# contributor's checked-out tree. `review/SKILL.md` instructs `gh pr checkout`,
# and this script is itself a compliance gate, so a same-named file in a hostile
# PR would run with the gate's authority. CLAUDE_PROJECT_DIR is supplied by the
# harness rather than by the tree under review. `REPO_ROOT` above stays as-is:
# its other uses are DATA-root reads of the workspace being audited, which is
# exactly what they should measure.
# Resolution, in trust order, and NEVER from `git rev-parse --show-toplevel`:
#   1. CLAUDE_PROJECT_DIR — supplied by the harness, not by the tree under review.
#      Measured 2026-08-12: unset in a plain Claude Code session and in git hooks,
#      so it cannot be the ONLY arm without silently retiring this telemetry.
#   2. This script's OWN location. Layout-invariant per ADR-178, and crucially NOT
#      CWD-derived: a `gh pr checkout` cannot redirect it, because by the time this
#      line runs the anchor decision has already been made — if a hostile script
#      were executing, sourcing its sibling lib adds nothing. On a plugin INSTALL
#      the walk lands somewhere with no such lib, so it no-ops, which is correct.
# The `-f` test is the safety net for both arms: a wrong root simply no-ops.
_incidents_root="${CLAUDE_PROJECT_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../../.." 2>/dev/null && pwd -P)}"
INCIDENTS_LIB="${_incidents_root:+${_incidents_root}/.claude/hooks/lib/incidents.sh}"
if [[ -n "$INCIDENTS_LIB" && -f "$INCIDENTS_LIB" ]]; then
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
# the content-vendor-drift cron's run timestamp is not. Taking the MIN ensures
# a fresh-looking last-verified cannot suppress a stale-cron banner.
# NOTICE_FILE and GH_TOKEN propagate explicitly — Bash subshell-exec does NOT
# inherit them otherwise. Operator-attested-mode banner fires only when the
# cron binding is unavailable AND last-verified is parseable — when both are
# 999 the existing 30d/90d banners cover the case.
#
# ⚠️ THE CRON HALF OF THIS BINDING IS INERT TODAY (#7255). `cron_days_stale`
# resolves to 999 on EVERY call: the probe queries
# `scheduled-content-vendor-drift.yml`, and that workflow no longer exists —
# the job moved to an Inngest cron with no GitHub Actions run to list. So the
# MIN below is always MIN(notice, 999) == notice, and the anti-backdating
# property this comment describes is NOT currently in force. The direction is
# fail-safe (the operator-attested-mode banner fires rather than a false
# freshness claim), which is exactly why it went unnoticed. Not fixed here —
# an Inngest-aware liveness source is a different change in a different
# subsystem. The comment is corrected rather than left asserting a defense
# that is not running.
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
