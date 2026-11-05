#!/usr/bin/env bash
# ci-oracle-lane.sh — the `oracle-selection` job's driver (#12156, ADR-276 amendment: DARK AND LOCKED).
#
# WHAT IT DECIDES. For a pull_request or merge_group run it answers one question: is EVERY changed path inside the
# oracle surface? When it is, the five heavy `test` legs (test-webplat, test-bun, test-scripts, test-scripts-heavy,
# web-platform-build) may skip while `shard-totality-mutations` skips on `oracle_only` and the `oracle-index-check`
# leg runs the oracle-validation manifest — an oracle-data diff changes no executable path, so the full battery
# proves nothing about it. It is a COST lever that may fail in ONE direction only: every unknown yields the full
# battery (oracle_only=false, active=false, skip_legs empty). It NEVER fails the step: it always exits 0 (an EXIT
# trap guarantees it), and the outputs are written as:
#   1. fail-closed defaults FIRST (oracle_only=false, active=false, skip_legs empty, head_sha empty, base_sha empty), then
#   2. ONE final printf block at the very end — to GITHUB_OUTPUT AND to stdout.
# A step killed anywhere between the two leaves exactly the defaults, so the gated jobs run.
#
# INPUTS ARE ENV ONLY (the workflow passes them through `env:`; nothing is interpolated into the script):
#   EVENT_NAME           github.event_name                          (pull_request | merge_group; anything else is full)
#   SWITCH               vars.CI_ORACLE_LANE                        (only the exact string `on` classifies; compared in bash)
#   PR_HEAD_SHA          github.event.pull_request.head.sha         (pull_request)
#   HEAD_REPO            github.event.pull_request.head.repo.full_name  (pull_request; a fork head is full)
#   MERGE_GROUP_HEAD_SHA github.event.merge_group.head_sha          (merge_group; the whole queued batch is diffed)
#   MERGE_GROUP_BASE_SHA github.event.merge_group.base_sha          (merge_group)
#   GH_REPO              github.repository                          (the fork comparison for pull_request)
#   GITHUB_SHA           the merge commit the pull_request checkout is at (runner-provided)
#   RUN_ATTEMPT          github.run_attempt                         (a re-run reuses the original payload: full)
#   GITHUB_OUTPUT        where the outputs go                       (unset: /dev/null)
#   GITHUB_STEP_SUMMARY  optional
#   RUNNER_TEMP          scratch root for the diff listing          (unset: $TMPDIR, then /tmp)
# CWD must be the repo checkout (actions/checkout, fetch-depth 0 — pull_request is at the MERGE ref).
#
# OUTPUTS (grammar pinned by scripts/ci-oracle-lane.test.sh):
#   oracle_only  ^(true|false)$       every changed path is inside the oracle surface AND, when
#                                     scripts/lib/test-affected-paths.sh changed, every changed hunk line lies inside
#                                     an `^AFFECTED_[A-Z0-9_]+_PATHS=(` … `^)` extent in BOTH the base and head images
#   active       ^(true|false)$       oracle_only AND the switch is exactly `on` AND the activation lock is absent —
#                                     NEVER true while `readonly ORACLE_LANE_LOCKED=1` stands (the lane is dark:
#                                     `would_skip` is annotated instead)
#   skip_legs    a comma list over    {test-webplat,test-bun,test-scripts,test-scripts-heavy,web-platform-build};
#                                     written ONLY when active
#   head_sha     ^([0-9a-f]{40})?$    pull_request: HEAD^2 of the merge ref; merge_group: MERGE_GROUP_HEAD_SHA
#   base_sha     ^([0-9a-f]{40})?$    pull_request: HEAD^1; merge_group: MERGE_GROUP_BASE_SHA
# The step also prints ONE `::notice title=ci-oracle-lane::SOLEUR_ORACLE_LANE ...` line (fixed tokens only: a path, a
# ref name, a SHA from the diff, the repository name or the raw switch value is NEVER echoed) and a short step summary.
# The notice carries, in this order: event, switch, locked, attempt, files, reason, oracle_only, would_skip, active.
# Reasons `signalled` (HUP/INT/TERM) and `lever_error` (an internal abort) are the two trap exits: both exit 0 with
# only the defaults. Reason `switch_off`: the variable held a non-`on` value (read the value class from `switch=`:
# `invalid` is any non-empty value but `on`, `unset` is empty).
#
# THE SURFACE (the lane's entire authority). A diff is oracle-only iff EVERY changed path is one of:
#   * scripts/ci-pr-affected-audit.accept.tsv
#   * scripts/ci-pr-affected-audit.baseline.tsv
#   * scripts/lib/test-affected-paths.sh — AND every changed hunk line lies inside an AFFECTED_*_PATHS array extent
#     computed in BOTH the base and head images (a NEW or DELETED whole array block still classifies: its lines are
#     inside the extent on the side that carries it; any hunk line outside extents — ALWAYS_ON_SUITES, _CLOSURE_LEAF_*,
#     AFFECTED_CONSUMED_EDGES, comments, functions — disqualifies the whole diff)
#   * a doc path — `knowledge-base/**/*.md` or a root-level `*.md`, the IDENTICAL grammar to ci-pr-selection.sh
#     is_doc_path (real oracle repairs carry pipeline planning artifacts; PR #12128's measured file list)
# THE EXCLUSION LIST (any one path ⇒ full battery, no lane): scripts/ci-pr-affected-replay.py, scripts/test-all.sh,
# plugins/soleur/scripts/lint-ratchet.py, .github/workflows/ci.yml, and any other scripts/lib/** path — the ratchet's
# own oracle machinery that is CODE. Load-bearing and pinned by the sentinel (Guard 1). The list is deliberately
# outcome-redundant with the surface (every member is already outside it) — it stays as defence in depth, so a future
# surface widening cannot silently adopt a machinery path.
# THE GUARDS, all of which must hold: pull_request — the merge-ref two-parent shape (HEAD^1 base, HEAD^2 == PR head,
# HEAD == GITHUB_SHA) and a same-repo head; merge_group — both payload SHAs are 40-hex and resolve to commits (the
# batch diff base_sha..head_sha is fail-closed correct: a code PR in the batch is not oracle-only). Both events —
# RUN_ATTEMPT == 1, ≤500 files, statuses M/A/D only, modes {000000,100644,100755}, every path byte printable ASCII,
# no `::` and no `,` in paths.
#
# Verdicts and annotations are literals only; every value that reaches an output is re-validated against its grammar
# at the final block. No tool beyond bash, git and coreutils (timeout unused; mktemp, wc, tr, rm) is used.
set -uo pipefail

readonly ORACLE_LANE_LOCKED=1  # ACTIVATION LOCK (#12156): the activation PR removes this line after the observation window

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
export GIT_OPTIONAL_LOCKS=0

OUT="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# The lane's own literals, committed here and pinned by the sentinel: a one-commit weakening must edit this file AND
# defeat scripts/ci-oracle-lane.test.sh.
readonly ORACLE_INDEX="scripts/lib/test-affected-paths.sh"
readonly ORACLE_SKIP_SET="test-webplat,test-bun,test-scripts,test-scripts-heavy,web-platform-build"

# ---- (1) fail-closed defaults, written FIRST and as ONE block ------------------------------------------------------
oracle_only=false
active=false
skip_legs=""
head_sha=""
base_sha=""
printf 'oracle_only=false\nactive=false\nskip_legs=\nhead_sha=\nbase_sha=\n' >> "$OUT"  # GUARD:O1-DEFAULTS

# State that only feeds the annotation. Every value is a literal, a number or a validated token.
sw="unset"
locked=false
attempt=0
files=0
reason=lever_error
would_skip=none
finished=0
sig=0
work=""

emit_notice() {
  printf '::notice title=ci-oracle-lane::SOLEUR_ORACLE_LANE event=%s switch=%s locked=%s attempt=%s files=%s reason=%s oracle_only=%s would_skip=%s active=%s\n' \
    "${EVENT_NAME:-unset}" "$sw" "$locked" "$attempt" "$files" "$reason" "$oracle_only" "$would_skip" "$active"
}

# An unexpected abort (an unbound variable, a signal) leaves only the defaults and still exits 0 (SIGKILL cannot be trapped;
# that case is the defaults by construction). A signal is `signalled`, any other abort is `lever_error`; one notice either way.
# shellcheck disable=SC2329  # invoked through the EXIT trap below
on_exit() {
  if [ "$finished" != 1 ]; then
    finished=1
    active=false
    oracle_only=false
    if [ "$sig" = 1 ]; then reason=signalled; else reason=lever_error; fi
    emit_notice
  fi
  # The scratch dir goes on EVERY exit path (normal, early return, abort, HUP/INT/TERM). SIGKILL cannot be trapped; RUNNER_TEMP
  # is per-job there.
  [ -z "$work" ] || rm -rf "$work"  # GUARD:O1-SCRATCH-CLEANUP
  exit 0
}
# shellcheck disable=SC2329  # invoked through the HUP/INT/TERM trap below
on_signal() {
  sig=1
  exit 0
}
trap on_exit EXIT  # GUARD:ALWAYS-EXIT-0
trap on_signal HUP INT TERM  # GUARD:ALWAYS-EXIT-0-SIGNAL

# ---- the switch and the lock (pure env, no I/O) ---------------------------------------------------------------------
[ -z "${SWITCH:-}" ] || sw=invalid
[ "${SWITCH:-}" = on ] && sw=on  # GUARD:O1-SWITCH-EXACT
[ "${ORACLE_LANE_LOCKED:-}" = 1 ] && locked=true  # GUARD:O1-LOCK-READ
case "${RUN_ATTEMPT:-}" in
  ''|*[!0-9]*) ;;
  *) [ "${#RUN_ATTEMPT}" -le 6 ] && attempt="$RUN_ATTEMPT" ;;
esac

# ---- the surface ----------------------------------------------------------------------------------------------------
# The doc allowlist: knowledge-base/**/*.md or a root-level *.md — IDENTICAL grammar to ci-pr-selection.sh is_doc_path
# (the file NAME must end in `.md`; `knowledge-base/?*.md` demands a non-empty remainder after the prefix; a root-level
# `.md` alone does not qualify; a root-level file has no `/` in it).
is_doc_path() {
  case "$1" in
    knowledge-base/?*.md) return 0 ;;
    */*) return 1 ;;
    ?*.md) return 0 ;;
  esac
  return 1
}

# The two literal ratchet data files.
is_oracle_data_path() {
  case "$1" in
    scripts/ci-pr-affected-audit.accept.tsv) return 0 ;;
    scripts/ci-pr-affected-audit.baseline.tsv) return 0 ;;
  esac
  return 1
}

# The exclusion list: the oracle machinery that is CODE. ORACLE_INDEX itself is consumed by the per-path loop BEFORE this
# predicate runs, so `scripts/lib/*` here means "any other scripts/lib/**".
is_excluded_path() {
  case "$1" in
    scripts/ci-pr-affected-replay.py) return 0 ;;
    scripts/test-all.sh) return 0 ;;
    plugins/soleur/scripts/lint-ratchet.py) return 0 ;;
    .github/workflows/ci.yml) return 0 ;;
    scripts/lib/*) return 0 ;;
  esac
  return 1
}

# ---- the AFFECTED_*_PATHS extent check ------------------------------------------------------------------------------
# `bitmap` / `bitmap_n` are the one shared scratch pair; each call overwrites them and callers copy out. A bitmap byte
# per image line: 1 = inside an `^AFFECTED_[A-Z0-9_]+_PATHS=(` … `^)` extent (opener and closer lines inclusive).
bitmap=""
bitmap_n=0
base_bitmap=""
head_bitmap=""

# $1 = image file (an EMPTY file is legal: the path is absent on that side of the diff, so no line is in-extent).
# Returns 1 when the extent walk cannot complete cleanly — a second opener inside an extent or an unclosed extent at
# EOF — because then no line-range claim can be proven and the diff fails closed.
bitmap_oracle_image() {  # GUARD:O1-EXTENT-PARSE
  bitmap=""
  bitmap_n=0
  local line in=0
  while IFS= read -r line || [ -n "$line" ]; do
    bitmap_n=$((bitmap_n + 1))
    if [[ "$line" =~ ^AFFECTED_[A-Z0-9_]+_PATHS=\( ]]; then
      [ "$in" = 0 ] || return 1
      in=1
    fi
    if [ "$in" = 1 ]; then bitmap+="1"; else bitmap+="0"; fi
    if [[ "$line" == \)* ]]; then
      in=0
    fi
  done < "$1"
  [ "$in" = 0 ] || return 1
  return 0
}

# Every `@@` hunk in a `git diff -U0` of ORACLE_INDEX: each changed old-side line must be inside a base extent and each
# changed new-side line inside a head extent. A pure-insertion hunk carries no old lines (a new array block is judged by
# the head extents); a pure-deletion hunk carries no new lines (a removed block is judged by the base extents).
check_hunks() {  # $1 = diff file   GUARD:O1-EXTENT-MISS
  local line os oc ns nc l
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '@@ -'*) ;; *) continue ;; esac
    [[ "$line" =~ ^@@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ @@ ]] || return 1
    os="${BASH_REMATCH[1]}"; oc="${BASH_REMATCH[3]:-1}"
    ns="${BASH_REMATCH[4]}"; nc="${BASH_REMATCH[6]:-1}"
    if [ "$oc" -gt 0 ]; then
      for (( l=os; l<os+oc; l++ )); do
        [ "${base_bitmap:l-1:1}" = "1" ] || return 1
      done
    fi
    if [ "$nc" -gt 0 ]; then
      for (( l=ns; l<ns+nc; l++ )); do
        [ "${head_bitmap:l-1:1}" = "1" ] || return 1
      done
    fi
  done < "$1"
  return 0
}

# ---- the work -------------------------------------------------------------------------------------------------------
run() {
  local parts p1 p2 h rl st p n nul size om nm
  local diff_base diff_head index_seen

  reason=not_lane_event
  case "${EVENT_NAME:-}" in
    pull_request|merge_group) ;;  # GUARD:O1-EVENTS
    *) return 0 ;;
  esac

  if [ "${EVENT_NAME:-}" = pull_request ]; then
    # (2a) the merge-ref shape: HEAD is GITHUB_SHA, has exactly two parents, and HEAD^2 is the PR head. All 40-hex.
    reason=bad_merge_shape
    [[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || return 0
    [[ "${PR_HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || return 0
    rl="$(git rev-list --parents -n 1 HEAD 2>/dev/null)" || return 0  # GUARD:O1-REVLIST
    read -r -a parts <<< "$rl"
    [ "${#parts[@]}" -eq 3 ] || return 0  # GUARD:O1-TWO-PARENTS
    h="${parts[0]}"; p1="${parts[1]}"; p2="${parts[2]}"
    [[ "$h" =~ ^[0-9a-f]{40}$ && "$p1" =~ ^[0-9a-f]{40}$ && "$p2" =~ ^[0-9a-f]{40}$ ]] || return 0
    [ "$h" = "$GITHUB_SHA" ] || return 0  # GUARD:O1-HEAD-IS-GITHUB-SHA
    [ "$p2" = "$PR_HEAD_SHA" ] || return 0  # GUARD:O1-PARENT2-IS-PR-HEAD
    head_sha="$p2"
    base_sha="$p1"
    diff_base="HEAD^1"
    diff_head="HEAD"

    # (3a) full on a fork head.
    reason=fork
    { [ -n "${HEAD_REPO:-}" ] && [ "${HEAD_REPO:-}" = "${GH_REPO:-}" ]; } || return 0  # GUARD:O1-FORK
  else
    # (2b) the merge_group shape: both payload SHAs are 40-hex and resolve to commits in this fetch-depth-0 checkout.
    # The batch diff base_sha..head_sha covers every queued entry, so a batch that contains a code PR fails closed.
    reason=bad_mg_shape
    [[ "${MERGE_GROUP_HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || return 0  # GUARD:O1-MG-SHA
    [[ "${MERGE_GROUP_BASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || return 0
    git rev-parse --verify --quiet "${MERGE_GROUP_HEAD_SHA}^{commit}" > /dev/null 2>&1 || return 0  # GUARD:O1-MG-RESOLVE
    git rev-parse --verify --quiet "${MERGE_GROUP_BASE_SHA}^{commit}" > /dev/null 2>&1 || return 0
    head_sha="$MERGE_GROUP_HEAD_SHA"
    base_sha="$MERGE_GROUP_BASE_SHA"
    diff_base="$MERGE_GROUP_BASE_SHA"
    diff_head="$MERGE_GROUP_HEAD_SHA"
  fi

  # (3b) full on a re-run.
  reason=rerun
  [ "${RUN_ATTEMPT:-}" = 1 ] || return 0  # GUARD:O1-RERUN

  # (3c) the switch: only the exact string `on` classifies at all. Anything else emits oracle_only=false with NO diff
  # work — the job itself only runs while the variable is non-empty, so `switch=invalid` is the telemetry for a mistyped
  # value. Deliberately before the diff: an off switch must never pay the classification cost.
  reason=switch_off
  [ "$sw" = on ] || return 0  # GUARD:O1-SWITCH-GATE

  # (4) the listing goes to a FILE: never argv, never env, never an annotation.
  reason=diff_error
  work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/oracle-lane.XXXXXX" 2>/dev/null)" || return 0
  git diff -z --raw --no-renames --no-abbrev --no-ext-diff --no-color "$diff_base" "$diff_head" -- > "$work/names.z" 2> "$work/diff.err" || return 0  # GUARD:O1-DIFF-RC
  size="$(wc -c < "$work/names.z")" || return 0
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  reason=empty_diff
  [ "$size" -gt 0 ] || return 0  # GUARD:O1-EMPTY-DIFF
  reason=malformed_diff
  nul="$(tr -cd '\0' < "$work/names.z" | wc -c)" || return 0
  [[ "$nul" =~ ^[0-9]+$ ]] || return 0
  [ $((nul % 2)) -eq 0 ] || return 0
  files=$((nul / 2))
  reason=too_many_files
  [ "$files" -le 500 ] || return 0  # GUARD:O1-MAX-FILES
  reason=malformed_diff
  [ "$files" -ge 1 ] || return 0

  # (5) the per-path surface check, one pass, no pipe — the single diff-listing chokepoint every changed path flows through.
  index_seen=0
  n=0
  while IFS= read -r -d '' meta; do
    IFS= read -r -d '' p || { reason=malformed_diff; return 0; }
    n=$((n + 1))
    [ -n "$p" ] || { reason=malformed_diff; return 0; }
    [[ "$meta" =~ ^:([0-7]{6})\ ([0-7]{6})\ ([0-9a-f]{40,64})\ ([0-9a-f]{40,64})\ ([A-Z][0-9]*)$ ]] || { reason=malformed_diff; return 0; }
    om="${BASH_REMATCH[1]}"; nm="${BASH_REMATCH[2]}"; st="${BASH_REMATCH[5]}"
    case "$st" in M|A|D) ;; *) reason=non_oracle_status; return 0 ;; esac  # GUARD:O1-STATUS
    case "$om" in 000000|100644|100755) ;; *) reason=non_oracle_mode; return 0 ;; esac  # GUARD:O1-MODE-OLD
    case "$nm" in 000000|100644|100755) ;; *) reason=non_oracle_mode; return 0 ;; esac  # GUARD:O1-MODE-NEW
    if [[ "$p" =~ [^\ -~] ]]; then reason=odd_path; return 0; fi  # GUARD:O1-CNTRL
    if [[ "$p" == *'::'* ]]; then reason=odd_path; return 0; fi  # GUARD:O1-COLONS
    if [[ "$p" == *,* ]]; then reason=odd_path; return 0; fi  # GUARD:O1-COMMA
    if [ "$p" = "$ORACLE_INDEX" ]; then index_seen=1; continue; fi  # GUARD:O1-INDEX-PATH
    if is_excluded_path "$p"; then reason=excluded; return 0; fi  # GUARD:O1-EXCLUDED
    if is_oracle_data_path "$p" || is_doc_path "$p"; then continue; fi  # GUARD:O1-SURFACE
    reason=outside_surface; return 0  # GUARD:O1-OUTSIDE
  done < "$work/names.z"
  [ "$n" -eq "$files" ] || { reason=malformed_diff; return 0; }

  # (6) the extent check for ORACLE_INDEX: `git diff -U0` hunk line ranges inside AFFECTED_*_PATHS extents in BOTH images.
  if [ "$index_seen" = 1 ]; then
    reason=diff_error
    git diff -U0 --no-renames --no-ext-diff --no-color "$diff_base" "$diff_head" -- "$ORACLE_INDEX" > "$work/index.diff" 2> "$work/index.err" || return 0  # GUARD:O1-INDEX-DIFF
    # An absent file on either side is an EMPTY image (add/delete whole blocks classify by the other side's extents).
    git show "$diff_base:$ORACLE_INDEX" > "$work/img-base" 2>/dev/null || : > "$work/img-base"
    git show "$diff_head:$ORACLE_INDEX" > "$work/img-head" 2>/dev/null || : > "$work/img-head"
    reason=extent_parse
    bitmap_oracle_image "$work/img-base" || return 0
    base_bitmap="$bitmap"
    bitmap_oracle_image "$work/img-head" || return 0
    head_bitmap="$bitmap"
    reason=extent_miss
    check_hunks "$work/index.diff" || return 0
  fi

  reason=oracle
  oracle_only=true
  would_skip="$ORACLE_SKIP_SET"
  return 0
}

run

# ---- (7) the arm: classified oracle-only AND the switch is exactly `on` AND the lock is absent -------------------------
# `sw = on` is redundant with the stage gate (reason=oracle already implies it) and is kept on purpose as the independent
# arming check — same defence-in-depth shape as the S4 driver's arm.
if [ "$oracle_only" = true ] && [ "$sw" = on ] && [ "$locked" = false ]; then  # GUARD:O1-ARM
  active=true
  skip_legs="$would_skip"  # GUARD:O1-SKIP-ONLY-WHEN-ACTIVE
fi

# Re-validate every value against its output grammar before it is written. A value that fails collapses to the defaults.
[[ "$oracle_only" =~ ^(true|false)$ ]] || oracle_only=false  # GUARD:O1-GRAMMAR-ONLY
[[ "$head_sha" =~ ^([0-9a-f]{40})?$ ]] || { head_sha=""; base_sha=""; }
[[ "$base_sha" =~ ^([0-9a-f]{40})?$ ]] || { head_sha=""; base_sha=""; }
if [ "$active" != true ] || [ "$oracle_only" != true ] || ! [[ "$skip_legs" =~ ^(test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build)(,(test-webplat|test-bun|test-scripts|test-scripts-heavy|web-platform-build))*$ ]]; then  # GUARD:O1-GRAMMAR-SKIP
  active=false
  skip_legs=""
fi

# ---- (8) ONE final block, to GITHUB_OUTPUT AND stdout ---------------------------------------------------------------
# A signal between this printf and `finished=1` would make the notice say active=false (signalled) while the file says
# true. Ignore the three signals across the writes (never restored: nothing after this point needs them).
trap '' HUP INT TERM  # GUARD:O1-SIGNAL-WINDOW
printf 'oracle_only=%s\nactive=%s\nskip_legs=%s\nhead_sha=%s\nbase_sha=%s\n' "$oracle_only" "$active" "$skip_legs" "$head_sha" "$base_sha" >> "$OUT"  # GUARD:O1-FINAL-BLOCK
printf 'oracle_only=%s\nactive=%s\nskip_legs=%s\nhead_sha=%s\nbase_sha=%s\n' "$oracle_only" "$active" "$skip_legs" "$head_sha" "$base_sha"  # GUARD:O1-STDOUT-BLOCK

# ---- (9) the annotation and the summary -----------------------------------------------------------------------------
finished=1
emit_notice
printf 'oracle-lane: switch=%s locked=%s reason=%s files=%s oracle_only=%s would_skip=%s active=%s\n' \
  "$sw" "$locked" "$reason" "$files" "$oracle_only" "$would_skip" "$active" >> "$SUMMARY"
exit 0  # on_exit removes the scratch dir
