#!/usr/bin/env bash
# gdpr-gate advisory pre-commit hook (lefthook).
#
# Always exits 0 — the hook is advisory, never blocking. Blocking enforcement
# lives in /soleur:ship Phase 5.5 (post-PR). This hook prints a one-line
# stderr breadcrumb when staged paths match the canonical regulated-data
# regex (single source of truth: SKILL.md §"Path globs (canonical)").
#
# Telemetry: emits, via .claude/hooks/lib/incidents.sh, an
# `hr-gdpr-gate-on-regulated-data-surfaces` event when a regulated-data path
# is touched, plus `gdpr-gate-staleness` and `gdpr-gate-cron-binding` events
# for the corpus-freshness signals. Telemetry survives even when the
# operator's terminal swallows stderr.
#
# This block previously documented a `gdpr-gate-touch` event. No such event
# has ever been emitted by this file (#7710). The name was corrected rather
# than the emit: `hr-gdpr-gate-on-regulated-data-surfaces` is the rule this
# gate enforces, and it is accepted by the incident allow-list via the
# closed-corpus arm of `_valid_rule` (it is a real `[id: ...]` in
# AGENTS.rules.md), not via the synthetic `gdpr-gate-*` prefix arm.
#
# Invoked from lefthook.yml:
#   gdpr-gate-advisory:
#     priority: 6
#     run: bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh {staged_files}

set -euo pipefail

# REPO_ROOT was REMOVED here (#7450 round-2 review). After `NOTICE_PARSER` moved to
# $BASH_SOURCE-relative resolution it had ZERO remaining expansions, leaving a bare
# `git rev-parse --show-toplevel` as the only statement in this file that could abort the
# run: it sits under `set -euo pipefail`, and this gate is documented at the top as
# "always exits 0 ... never blocking". It fails on a non-repo CWD, a broken .git worktree
# pointer, or a `safe.directory` ownership refusal — all routine on a fresh install or a
# container mount — and would have aborted the operator's `git commit` via lefthook.

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
# harness rather than by the tree under review.
#
# There is no `REPO_ROOT` in this file any more (see above). Two successive revisions of
# this comment were wrong about it, and both are recorded because the second was written
# to correct the first:
#   1. It first claimed every remaining `REPO_ROOT` use was a data-root read. FALSE —
#      `NOTICE_PARSER` below is EXECUTED (a code root by this ADR's classification) and was
#      resolved from it, with `GH_TOKEN` exported into the child. On the review path that
#      handed a GitHub token to a contributor-supplied script from inside the compliance
#      gate, in the very file edited to remove that vector.
#   2. The correction then claimed `REPO_ROOT` "stays for data-root reads". Also FALSE —
#      once `NOTICE_PARSER` moved to $BASH_SOURCE-relative there were no reads left at all,
#      so the assignment was dead code that could still abort the operator's commit.
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
# SIBLING of this script, so it needs no root at all: `$BASH_SOURCE`-relative is
# layout-invariant (ADR-178) and leaves NO operand for a checked-out tree to shadow —
# strictly better here than any root-anchored form, including CLAUDE_PROJECT_DIR.
# It was `"$REPO_ROOT/plugins/soleur/…"` (i.e. `git rev-parse --show-toplevel`) until
# #7450 review: EXECUTED below, three times, once with GH_TOKEN exported to the child.
NOTICE_PARSER="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/notice-frontmatter.sh"
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
  printf '⚠ gdpr-gate rules %s days stale (last verified %s) — output is advisory only and may miss recently-patched detection rules. Refresh: see "Corpus freshness" in this skill'"'"'s SKILL.md.\n' \
    "$days_stale" "$last_verified"
  emit_incident gdpr-gate-staleness warn "${days_stale}-days-stale" \
    2>/dev/null || true
fi
if (( days_stale > 90 )); then
  printf 'POSTURE_FAIL: gdpr-gate rules >90 days stale — compliance/critical posture row required. Operator chain: see "POSTURE_FAIL operator chain" in this skill'"'"'s SKILL.md.\n'
  emit_incident gdpr-gate-staleness deny "${days_stale}-days-stale-posture-fail" \
    2>/dev/null || true
fi

# Single source of truth — mirrors SKILL.md §"Path globs (canonical)".
CANONICAL_REGEX='^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)'

matched=()
examined=0
for f in "$@"; do
  examined=$((examined + 1))
  if [[ "$f" =~ $CANONICAL_REGEX ]]; then
    matched+=("$f")
  fi
done

# Scan-completion line (#7710). UNCONDITIONAL and AFTER the loop, reporting
# what the loop actually counted.
#
# Before this line existed, "the scan ran and matched nothing" and "the scan
# never ran" produced byte-identical output — nothing at all. On a corpus
# past the 90-day threshold the gate printed a staleness banner and a
# POSTURE_FAIL and no evidence that any path had been examined, so the
# refusal read as the whole output and a reader could not tell a healthy
# no-findings scan from a gate that never looked. That is the defect #7710
# reported, and it is why this line must NOT be gated on
# `${#matched[@]} > 0`: the zero-match case is precisely the state the
# property forbids being silent about.
#
# STDOUT, because agent runtimes commonly swallow stderr — the same reason
# the staleness banners are on stdout. The path-naming breadcrumb below stays
# on stderr.
#
# COUNTS ONLY, never path names: this line goes to a customer's terminal, and
# path structure is third-party-content-adjacent
# (hr-third-party-content-grep-on-undertaking; #7331 is the live scar). The
# stderr breadcrumb already names paths for the local operator.
#
# It carries neither `days stale` nor `POSTURE_FAIL`, so its presence is
# independent of the corpus's freshness state. That independence is the
# point: the evidence that a scan occurred must not be entangled with the
# age of the rules the scan used. It also keeps the existing negative
# assertions on those two strings able to witness a banner regression.
printf 'gdpr-gate: path scan complete — %d examined, %d matched\n' \
  "$examined" "${#matched[@]}"

if (( ${#matched[@]} > 0 )); then
  echo "gdpr-gate: regulated-data path touched (${matched[*]}); run /soleur:gdpr-gate" >&2
  emit_incident hr-gdpr-gate-on-regulated-data-surfaces applied \
    "regulated-data path touched: ${matched[0]}" 2>/dev/null || true

  # Operator-attested-mode banner — fires ONLY when (a) a regulated path is
  # being judged this commit AND (b) the cron binding is unavailable but
  # NOTICE last-verified is parseable.
  #
  # The #3541 relevance property is real, but this conditional is not what
  # delivers it, and the previous wording here was false (#7710). It claimed
  # that without the matched-path gate the banner "would fire on every
  # commit". It would not: lefthook invokes this script only when a staged
  # path matches the `gdpr-gate-advisory` glob, so on the pre-commit path
  # relevance is already bought by the glob and this conditional is a second,
  # narrower filter over an already-filtered set.
  #
  # What the conditional actually buys is relevance on the paths the glob does
  # NOT gate: direct invocation, the CI self-test, and `/soleur:gdpr-gate`,
  # where arbitrary arguments reach the script. That is a real property and
  # worth keeping — it is simply a different one from the claim it replaced.
  #
  # Banner literal is load-bearing: the self-test asserts it verbatim. See
  # review finding from user-impact-reviewer #3541.
  if [[ "$cron_days_stale" == "999" && "$notice_days_stale" != "999" ]]; then
    printf 'ℹ gdpr-gate: operator-attested mode (no GH_TOKEN available — cron-run timestamp unverified, falling back to NOTICE last-verified)\n'
    emit_incident gdpr-gate-cron-binding unavailable \
      "no-token-or-gh-cli" 2>/dev/null || true
  fi
fi

exit 0
