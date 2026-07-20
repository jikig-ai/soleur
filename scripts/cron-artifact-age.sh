#!/usr/bin/env bash
# cron-artifact-age.sh — the cron-liveness cohort's artifact-age detector (#6737).
#
# WHY THIS EXISTS (ADR-126 follow-up). ADR-126 closed a single cron's blind spot:
# `cron-community-monitor` posted GREEN for six days while committing no digest,
# because its check-in colour was gated on "a labelled issue landed" rather than
# on the artifact the operator actually reads. `resolveOutputAwareOk` is shared,
# so every producer whose deliverable is a COMMITTED FILE inherits that blind
# spot. #6737 audits the cohort; this script is the audit's one durable artifact.
#
# THE DESIGN CONSTRAINT — the reporter must not be the subject. Every
# handler-local remedy (reading safeCommitAndPr's return value, adding a
# `livenessOk` flag, emitting more markers) is authored by, and runs inside, the
# very handler under suspicion. That is precisely why the handler-local monitors
# missed the gap: a wedged, throwing, or never-scheduled handler reports nothing,
# and "nothing" is indistinguishable from "healthy" on every operator-reachable
# surface. This script measures from OUTSIDE the handler entirely — it reads
# committed git history on the default branch and asks a question no handler can
# answer about itself: did your artifact actually land?
#
# WHAT IT CATCHES THAT RETURN-VALUE READS STRUCTURALLY CANNOT:
#   * A THROW out of safe-commit-pr. A throw produces no return value at all, so
#     there is nothing for a handler to consume.
#   * A `no-changes` STREAK. One `no-changes` is healthy for a change-conditional
#     producer; 110 consecutive ones is an outage. They are identical per-run.
#   * PR OPENED BUT NEVER MERGED (observed: seo-aeo PR #5026, state CLOSED, head
#     `ci/seo-aeo-audit-2026-06-08-113158`). The commit happened — on a branch
#     that never landed. Only a DEFAULT-BRANCH check sees this.
#   * cron-roadmap-review, the 9th producer, which is outside MIGRATED_PROMPT and
#     outside every handler-local remedy. This script enumerates PRODUCERS, not
#     handler shapes, so it covers 9/9.
#
# WHY SELF-AUTHORSHIP AND NOT PATH mtime. Age is measured from the cron's OWN
# commit-message anchor, not from "last commit touching the artifact path".
# Humans edit these same paths constantly; a path-mtime probe would report
# `plugins/soleur/docs/` as 3 days fresh while cron-seo-aeo-audit has not landed
# anything in 55 days. Human edits MASK cron darkness, which is the same
# masking-by-a-healthy-neighbour error the cohort audit records as
# propagation-vs-blindness. The artifact-frontmatter cross-check is a SEPARATE,
# genuinely independent producer and lives in the audit doc, not here.
#
# No SSH, no credentials, no dashboard. Reads git history only.
#
# Usage:
#   bash scripts/cron-artifact-age.sh --all      # 9 rows, cadence + PASS/STALE
#   bash scripts/cron-artifact-age.sh --help
#
# Exit: 0 if every producer is PASS; 1 if any producer is STALE.
set -euo pipefail

# --------------------------------------------------------------------------
# Thresholds are derived from each cron's OWN schedule, never from a flat
# constant. A flat window is the cadence-blindness error the audit records: a
# 12-day observation window contains ZERO fires of a monthly cron, so "no
# artifact in 12 days" is not evidence about `cron-competitive-analysis`
# (`0 9 1 * *`) and must never be read as such.
#
# Class A (deterministic) producers write on every run, so two missed intervals
# is already conclusive. Class B (change-conditional) producers may legitimately
# produce no diff on a run, so they are granted ONE additional interval before a
# verdict — that is the entire mechanical difference between the classes.
# --------------------------------------------------------------------------
readonly CLASS_A_INTERVALS=2
readonly CLASS_B_INTERVALS=3

# Absolute ceiling. Without it a long-cadence Class B producer buys an
# indefensible amount of silence purely from arithmetic: monthly x 3 intervals
# is 94 days, so a producer three full months dark would still read PASS. No
# committed-file producer is healthy after a quarter of silence at ANY cadence.
readonly MAX_THRESHOLD_DAYS=75

# Producer table: name|cron_expr|interval_days|class|anchor_regex
#
# `anchor_regex` is the cron's own `commitMessage:` literal, taken from its
# handler (content anchor, not a line number). Verified present in each handler:
#   cron-seo-aeo-audit.ts            commitMessage: "fix(seo): weekly SEO/AEO audit fixes"
#   cron-content-generator.ts        commitMessage: "feat(content): auto-generate article"
#   cron-growth-execution.ts         commitMessage: "fix(growth): biweekly keyword optimization"
#   cron-campaign-calendar.ts        commitMessage: "ci: update campaign calendar and content-strategy review"
#   cron-growth-audit.ts             commitMessage: "docs: weekly growth audit"
#   cron-community-monitor.ts        commitMessage: "docs: daily community digest"
#   cron-competitive-analysis.ts     commitMessage: "docs: update competitive intelligence report"
#   cron-architecture-diagram-sync.ts commitMessage: "docs(arch): weekly architecture diagram sync"
# cron-roadmap-review.ts has NO `commitMessage:` constant — it is a hook-guarded
# Tier-1 self-commit, which is exactly why it is invisible to every
# MIGRATED_PROMPT-shaped remedy. Its anchor is derived from its landed history.
cron_producer_rows() {
  cat <<'ROWS'
cron-seo-aeo-audit|0 11 * * 1|7|B|^fix\(seo\): weekly SEO/AEO audit fixes
cron-content-generator|0 10 * * 2,4|4|A|^feat\(content\): auto-generate article
cron-growth-execution|0 10 1,15 * *|15|B|^fix\(growth\): biweekly keyword optimization
cron-campaign-calendar|0 16 * * 1|7|A|^ci: update campaign calendar and content-strategy review
cron-growth-audit|0 7 * * 1|7|A|^docs: weekly growth audit
cron-community-monitor|0 8 * * *|1|A|^docs: daily community digest
cron-competitive-analysis|0 9 1 * *|31|B|^docs: update competitive intelligence report
cron-architecture-diagram-sync|0 2 * * 0|7|B|^docs\(arch\): weekly architecture diagram sync
cron-roadmap-review|0 9 * * 1|7|B|^(chore|fix)\(roadmap\): (weekly|CPO)
ROWS
}

# threshold_days <interval_days> <class> -> integer
threshold_days() {
  local interval="$1" klass="$2" intervals t
  case "$klass" in
    A) intervals=$CLASS_A_INTERVALS ;;
    B) intervals=$CLASS_B_INTERVALS ;;
    *) echo "threshold_days: unknown class '$klass'" >&2; return 2 ;;
  esac
  # +1 grace day absorbs schedule jitter and the commit-vs-merge lag.
  t=$((interval * intervals + 1))
  if ((t > MAX_THRESHOLD_DAYS)); then t=$MAX_THRESHOLD_DAYS; fi
  printf '%s' "$t"
}

# last_artifact_epoch <repo_dir> <ref> <anchor_regex> -> epoch seconds, or empty
# if the producer has NEVER landed an artifact on that ref.
last_artifact_epoch() {
  local repo="$1" ref="$2" anchor="$3" out
  out="$(git -C "$repo" log "$ref" -1 --format='%at' --extended-regexp \
    --grep="$anchor" 2>/dev/null || true)"
  printf '%s' "$out"
}

# age_days <repo_dir> <ref> <anchor_regex> <now_epoch> -> integer days, or NEVER
age_days() {
  local repo="$1" ref="$2" anchor="$3" now="$4" epoch
  epoch="$(last_artifact_epoch "$repo" "$ref" "$anchor")"
  if [[ -z "$epoch" ]]; then printf 'NEVER'; return 0; fi
  printf '%s' $(( (now - epoch) / 86400 ))
}

# classify_age <age_days_or_NEVER> <threshold_days> -> PASS|STALE
#
# NEVER is STALE by construction. A producer that has not once landed its
# artifact is the most severe form of the defect, not an absence of evidence —
# treating "no observation" as PASS is the exact fail-open that ADR-126 forbids.
classify_age() {
  local age="$1" threshold="$2"
  if [[ "$age" == "NEVER" ]]; then printf 'STALE'; return 0; fi
  if ((age > threshold)); then printf 'STALE'; else printf 'PASS'; fi
}

report_all() {
  local repo="${REPO_DIR:-.}" ref="${DEFAULT_REF:-origin/main}" now
  now="${NOW_EPOCH:-$(date +%s)}"
  local any_stale=0 name cron_expr interval klass anchor t age verdict

  printf '%-32s %-14s %-5s %-7s %-9s %s\n' \
    PRODUCER CADENCE CLASS AGE THRESHOLD VERDICT
  printf '%s\n' "--------------------------------------------------------------------------------------"

  while IFS='|' read -r name cron_expr interval klass anchor; do
    [[ -n "$name" ]] || continue
    t="$(threshold_days "$interval" "$klass")"
    age="$(age_days "$repo" "$ref" "$anchor" "$now")"
    verdict="$(classify_age "$age" "$t")"
    [[ "$verdict" == "STALE" ]] && any_stale=1
    printf '%-32s %-14s %-5s %-7s %-9s %s\n' \
      "$name" "$cron_expr" "$klass" "$age" "${t}d" "$verdict"
  done < <(cron_producer_rows)

  printf '%s\n' "--------------------------------------------------------------------------------------"
  if ((any_stale)); then
    printf 'RESULT: at least one producer is STALE (ref=%s)\n' "$ref"
    return 1
  fi
  printf 'RESULT: all producers within threshold (ref=%s)\n' "$ref"
  return 0
}

usage() {
  cat <<'USAGE'
cron-artifact-age.sh — artifact-age detector for the cron-liveness cohort (#6737)

  --all     Report all 9 committed-file cron producers: cadence, class, age in
            days since the producer last landed its artifact on the default
            branch, the schedule-derived threshold, and a PASS/STALE verdict.
  --help    This message.

Environment overrides (used by the test harness):
  REPO_DIR     git repo to inspect (default: .)
  DEFAULT_REF  ref treated as the default branch (default: origin/main)
  NOW_EPOCH    "now" in epoch seconds (default: date +%s)

Exit 0 if every producer is PASS, 1 if any is STALE.
USAGE
}

# Sourced by cron-artifact-age.test.sh for unit-level access to the pure
# functions above; only executes when run directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:---help}" in
    --all) report_all ;;
    --help | -h) usage ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
fi
