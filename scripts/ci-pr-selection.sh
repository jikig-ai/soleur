#!/usr/bin/env bash
# ci-pr-selection.sh — the `pr-selection` job's driver (#9729, ADR-276 S4, PR B: DARK AND LOCKED).
#
# WHAT IT DECIDES. For a pull_request run it answers one question: may the three heavy gated legs
# (test-webplat, test-bun, test-scripts-heavy) be skipped because this diff cannot move them? It is a COST lever
# that may fail in ONE direction only: every unknown yields the full battery (empty `skip_legs`, `active=false`).
# It NEVER fails the step: it always exits 0 (an EXIT trap guarantees it), and the outputs are written as:
#   1. fail-closed defaults FIRST (head_sha empty, base_sha empty, active=false, skip_legs empty), then
#   2. ONE final printf block at the very end (head_sha, base_sha, active, skip_legs LAST).
# A step killed anywhere between the two leaves exactly the defaults, so the gated jobs run.
#
# INPUTS ARE ENV ONLY (the workflow passes them through `env:`; nothing is interpolated into the script):
#   EVENT_NAME      github.event_name                       (anything but `pull_request` is full)
#   SWITCH          vars.CI_PR_AFFECTED                      (only the exact string `on` runs stage 2 and can arm; compared in bash)
#   GITHUB_SHA      the merge commit the checkout is at
#   PR_HEAD_SHA     github.event.pull_request.head.sha
#   HEAD_REPO       github.event.pull_request.head.repo.full_name   (a fork head is full)
#   GH_REPO         github.repository
#   RUN_ATTEMPT     github.run_attempt                       (a re-run reuses the original payload: full)
#   GITHUB_OUTPUT   where the outputs go                     (unset: /dev/null)
#   GITHUB_STEP_SUMMARY  optional
#   RUNNER_TEMP     scratch root for the diff listing        (unset: $TMPDIR, then /tmp)
# PRODUCTION PARAMETER (the workflow sets it to 90):
#   PR_SELECTION_STAGE2_TIMEOUT  total stage-2 budget in seconds        (default 120; digits only, at most 6 of them, read as
#                                decimal so `08` is 8; anything else, and 0, falls back to the default; never `timeout 0`)
# TEST SEAM (a pure seam: the workflow never sets it):
#   PR_SELECTION_TEST_ALL        path of the test-all.sh to call        (default scripts/test-all.sh)
# CWD must be the repo checkout (actions/checkout, fetch-depth 0, of the pull_request MERGE ref).
#
# OUTPUTS (grammar pinned by scripts/ci-pr-selection.test.sh):
#   head_sha   ^([0-9a-f]{40})?$      HEAD^2 once the merge-ref shape is validated (an audit value; empty otherwise)
#   base_sha   ^([0-9a-f]{40})?$      HEAD^1, same rule
#   active     ^(true|false)$         true ONLY when the switch is exactly `on`, the activation lock is absent, the
#                                     diff is doc-only, the selector answered cleanly AND something would be skipped
#   skip_legs  ^([a-z-]+(,[a-z-]+)*)?$  subset of {test-webplat,test-bun,test-scripts-heavy}; written ONLY when active
# The step also prints ONE `::notice title=ci-pr-selection::SOLEUR_PR_SELECTION ...` line (counts and fixed tokens only:
# a path, a ref name, a SHA from the diff, the repository name or the raw switch value is NEVER echoed) and a short step
# summary. The notice carries, in this order: switch, locked, attempt, files, stage, reason, would_skip, sel_s, sel_censored,
# budget, active, groups. `sel_s` is the stage-2 wall time (0 whenever stage 2 did not run), a LOWER BOUND when `sel_censored=1` (budget or
# per-call timeout hit; a cold runner is expected to censor it). Reason `switch_off`: a doc-only diff that passed the paths cap, switch not `on`;
# a code diff keeps its stage-1 reason, so read the off switch from `switch=` (`invalid`: any non-empty value but `on`). `groups` is webplat:TOK,bun:TOK,scripts-heavy:TOK
# (`-` when stage 2 did not finish). Reason `affected_degraded` replaces `affected` when any group token is timeout|bad_rc|parse|missing_row|no_records|empty, so a degraded enumerate never
# reads as the benign `affected would_skip=none`. `affected_degraded` is TELEMETRY ONLY: healthy groups still arm when a sibling
# group is degraded (per-group evaluation), a decision to revisit before the lock is removed (ADR-276 S4 amendment). Reasons
# `signalled` (HUP/INT/TERM) and `lever_error` (an internal abort) are the two trap exits: both exit 0 with only the defaults.
#
# TWO STAGES (the cost shape, decision-challenges.md): STAGE 1 is a pure-bash positive allowlist over
# `git diff -z --raw --no-renames --no-abbrev HEAD^1 HEAD` (records `:oldmode newmode oldsha newsha STATUS` NUL `path` NUL).
# The diff LISTING is kept in a FILE under RUNNER_TEMP (never in an env var or an annotation); the comma `--paths=` list the
# selector receives is derived from it and IS argv (bounded: over 100000 bytes is full, which is also well under the kernel's
# 128 KiB single-argument limit). The allowlist grammar, ALL of which must hold for every changed path:
#   * status M, A or D (any other letter, a record that does not parse, or a NUL-parity/count mismatch is full);
#   * BOTH modes in {000000, 100644, 100755} (a symlink 120000, a gitlink 160000 or any other mode is `non_doc_mode`; a mode
#     flip 100644 -> 100755 on a doc file stays doc-class);
#   * the path is `knowledge-base/**/*.md` or a root-level `*.md`: the file NAME must end in `.md` (knowledge-base/x.sh, .ts,
#     .json, .c4, images, .pen, a root zz.mdx, zz.md.sh, knowledge-base-evil/zz.md or a bare file `knowledge-base` are non_doc);
#   * every byte of the path is printable ASCII 0x20-0x7e (this also rejects ASCII control characters, U+2028 and C1
#     controls as `odd_path`), the path has no `::` and no comma;
#   * the path is not on the TRIGGER LIST below.
# Nothing else runs in stage 1, so a code PR pays no pre-pass. STAGE 2 runs only for a doc-only diff AND only when the switch is exactly `on`:
#   env -u CI -u SOLEUR_TEST_FORCE_ALL -u GITHUB_OUTPUT ... bash test-all.sh --print-selection --paths=<list>
#   env -u CI -u SOLEUR_TEST_FORCE_ALL -u GITHUB_OUTPUT ... bash test-all.sh --enumerate-commands --paths=<list> <group>
# (the selector child also loses GITHUB_STEP_SUMMARY, GITHUB_ENV, GITHUB_PATH and GITHUB_STATE. That denies it the INHERITED
# variables only: a same-user child could still discover the path some other way. The real boundary is that stage 2 runs only
# for a doc-only diff with the switch on and the final output block is written LAST, after the child has exited, so nothing a child appended can
# outlive it: the last value per key wins.)
# A group joins the would-skip set only if its enumerate stream is non-empty, every runnable record is an
# AFFECTED_SELECTED row with sel=0 (and not always_on) or a SUITE_COMMAND_DECLINED record whose label is a known
# `--pr-gated` decline (ADR-262; every other decline is unreachable under CI, ADR-181, so the leg would still run),
# exactly one `AFFECTED_SUMMARY ... fallback=none` was seen and no AFFECTED_FALLBACK/UNRESOLVED line appeared. A diff
# under knowledge-base/engineering/architecture/diagrams/ never allows test-webplat to be skipped. Parse doubt, empty
# output, a timeout or a non-zero exit all mean no skip, with a fixed reason token.
#
# THE TRIGGER LIST (an edit to any selector input is a full run, so a PR cannot widen its own skips):
#   .github/workflows/ci.yml, scripts/ci-pr-selection.sh, scripts/lib/** (prefix), scripts/test-all.sh,
#   scripts/suite-shard-legs.tsv, scripts/suite-shard-legs-heavy.tsv (the heavy manifest),
#   scripts/test-affected-kb-consumers.baseline.txt.
# HONEST NOTE: today the list is outcome-redundant with the allowlist (every trigger path is already outside
# `knowledge-base/**/*.md` + root `*.md`, so it would be `non_doc` anyway). It is deliberate defense in depth (the operator-
# specified list stays) that becomes LOAD-BEARING the moment the allowlist is widened (PR C): scripts/ci-pr-selection.test.sh
# pins that with a combined behavioural mutant (a widened allowlist AND no trigger check reaches stage 2).
# scripts/ci-pr-selection.test.sh asserts that every file scripts/test-all.sh sources is under scripts/lib/ (covered by the
# prefix arm), so a new sourced location outside it reds the suite until this list learns it.
#
# Verdicts and annotations are literals only; every value that reaches an output is re-validated against its grammar
# at the final block. No tool beyond bash, git and coreutils (timeout, mktemp, wc, tr, env, rm) is used: the job
# installs nothing, and the suite runs this file with node, bun, python, jq, awk and sed off PATH.
set -uo pipefail

readonly PR_AFFECTED_LOCKED=1  # ACTIVATION LOCK (#9729): PR C removes this line in its last commit

export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
export GIT_OPTIONAL_LOCKS=0

OUT="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# ---- (1) fail-closed defaults, written FIRST and as ONE block ------------------------------------------------------
head_sha=""
base_sha=""
active=false
skip_legs=""
printf 'head_sha=\nbase_sha=\nactive=false\nskip_legs=\n' >> "$OUT"  # GUARD:G2-6-DEFAULTS

# State that only feeds the annotation. Every value is a literal, a number or a validated token.
sw="unset"
locked=false
attempt=0
files=0
stage=1
reason=lever_error
would_skip=none
sel_s=0
sel_censored=0
budget=120
groups=-
mode=full
finished=0
sig=0
work=""

emit_notice() {
  printf '::notice title=ci-pr-selection::SOLEUR_PR_SELECTION switch=%s locked=%s attempt=%s files=%s stage=%s reason=%s would_skip=%s sel_s=%s sel_censored=%s budget=%s active=%s groups=%s\n' \
    "$sw" "$locked" "$attempt" "$files" "$stage" "$reason" "$would_skip" "$sel_s" "$sel_censored" "$budget" "$active" "$groups"
}

# An unexpected abort (an unbound variable, a signal) leaves only the defaults and still exits 0 (SIGKILL cannot be trapped;
# that case is the defaults by construction). A signal is `signalled`, any other abort is `lever_error`; one notice either way.
# shellcheck disable=SC2329  # invoked through the EXIT trap below
on_exit() {
  if [ "$finished" != 1 ]; then
    finished=1
    active=false
    if [ "$sig" = 1 ]; then reason=signalled; else reason=lever_error; fi
    emit_notice
  fi
  # The scratch dir goes on EVERY exit path (normal, early return, abort, HUP/INT/TERM). SIGKILL cannot be trapped; RUNNER_TEMP
  # is per-job there.
  [ -z "$work" ] || rm -rf "$work"  # GUARD:G2-SCRATCH-CLEANUP
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
[ "${SWITCH:-}" = on ] && sw=on  # GUARD:G2-5-SWITCH-EXACT
[ "${PR_AFFECTED_LOCKED:-}" = 1 ] && locked=true  # GUARD:G2-13-LOCK-READ
case "${RUN_ATTEMPT:-}" in
  ''|*[!0-9]*) ;;
  *) [ "${#RUN_ATTEMPT}" -le 6 ] && attempt="$RUN_ATTEMPT" ;;
esac
# The stage-2 budget, sanitized once: digits only, at most 6 of them, read as DECIMAL (a leading zero is not octal), and at
# least 1 (a `timeout 0` would mean UNLIMITED, which must never happen). Anything else is the default.
budget="${PR_SELECTION_STAGE2_TIMEOUT:-120}"
case "$budget" in ''|*[!0-9]*) budget=120 ;; esac
[ "${#budget}" -le 6 ] || budget=120
budget=$((10#$budget))
[ "$budget" -ge 1 ] || budget=120

# ---- the trigger list -----------------------------------------------------------------------------------------------
is_trigger_path() {
  case "$1" in
    .github/workflows/ci.yml) return 0 ;;
    scripts/ci-pr-selection.sh) return 0 ;;
    scripts/test-all.sh) return 0 ;;
    scripts/suite-shard-legs.tsv) return 0 ;;
    scripts/suite-shard-legs-heavy.tsv) return 0 ;;
    scripts/test-affected-kb-consumers.baseline.txt) return 0 ;;
    scripts/lib/*) return 0 ;;
  esac
  return 1
}

# The positive allowlist: knowledge-base/**/*.md or a root-level *.md. The path must END in `.md` and have at least one
# character before that suffix: `knowledge-base/?*.md` demands a non-empty REMAINDER after the prefix, not a non-empty file stem,
# so a hidden file named `.md` in a subdirectory (`knowledge-base/a/.md`) IS accepted (the predicate is deliberate and
# unchanged); a root-level `.md` alone is not. A root-level file has no `/` in it.
is_doc_path() {
  case "$1" in
    knowledge-base/?*.md) return 0 ;;
    */*) return 1 ;;
    ?*.md) return 0 ;;
  esac
  return 1
}

# Labels of the registrations declined through `_diff_touches --pr-gated` in scripts/test-all.sh (ADR-262). Only these declines
# can happen on a pull_request CI run; any other SUITE_COMMAND_DECLINED record is a relevance decline that CI never takes
# (ADR-181), so a group holding one still runs. The suite derives this set from test-all.sh and pins it.
is_pr_gated_decline() {
  case "$1" in
    "scripts/lint-orphan-test-suites-mutations-a") return 0 ;;
    "scripts/lint-orphan-test-suites-mutations-b") return 0 ;;
    "scripts/cf-tunnel-liveness-gate-mutations") return 0 ;;
    "scripts/test-all-affected-a") return 0 ;;
    "scripts/test-all-affected-b") return 0 ;;
    "scripts/test-all-affected-c") return 0 ;;
    "scripts/test-all-affected-d") return 0 ;;
    "tests/scripts/registry-gate-mutation-battery") return 0 ;;
    "scripts/battery-tag-authorship-mutations") return 0 ;;
  esac
  return 1
}

# ---- stage 2 helpers ------------------------------------------------------------------------------------------------
# Selection rows, parsed once: parallel arrays searched linearly (a group names at most a handful of labels).
sel_labels=()
sel_vals=()
sel_classes=()
sel_summary_ok=0
sel_summary_bad=0
sel_fallback_seen=0

parse_selection() {  # $1 = file
  local line rest label sel cls tabs
  sel_labels=(); sel_vals=(); sel_classes=()
  sel_summary_ok=0; sel_summary_bad=0; sel_fallback_seen=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      AFFECTED_SELECTED$'\t'*)
        tabs="${line//[^$'\t']/}"
        [ "${#tabs}" -ge 3 ] || return 1  # GUARD:G2-10-TABS
        rest="${line#*$'\t'}"
        label="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        sel="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        cls="${rest%%$'\t'*}"
        [ -n "$label" ] || return 1
        case "$sel" in 0|1) ;; *) return 1 ;; esac
        [ -n "$cls" ] || return 1  # GUARD:G2-10-CLS
        sel_labels+=("$label"); sel_vals+=("$sel"); sel_classes+=("$cls")
        ;;
      AFFECTED_SUMMARY\ *)
        if [[ "$line" =~ ^AFFECTED_SUMMARY\ selected=[0-9]+\ of=[0-9]+\ always_on=[0-9]+\ edge=[0-9]+\ fallback=none$ ]]; then  # GUARD:G2-10-SUMMARY
          sel_summary_ok=$((sel_summary_ok + 1))
        else
          sel_summary_bad=1
        fi
        ;;
      AFFECTED_FALLBACK*|AFFECTED_UNRESOLVED*) sel_fallback_seen=1 ;;
    esac
  done < "$1"
  return 0
}

# Prints a fixed token: skip | no_records | selected | always_on | plain_decline | missing_row | parse
eval_group() {  # $1 = enumerate stream file
  local line rest label n=0 i found any_sel any_always
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      SUITE_COMMAND_DECLINED$'\t'*)
        rest="${line#*$'\t'}"
        label="${rest%%$'\t'*}"
        [ -n "$label" ] || { printf 'parse'; return 0; }
        is_pr_gated_decline "$label" || { printf 'plain_decline'; return 0; }  # GUARD:G2-11-PLAIN-DECLINE
        n=$((n + 1))
        ;;
      SUITE_COMMAND$'\t'*)
        rest="${line#*$'\t'}"
        label="${rest%%$'\t'*}"
        [ -n "$label" ] || { printf 'parse'; return 0; }
        found=0; any_sel=0; any_always=0
        for i in "${!sel_labels[@]}"; do
          [ "${sel_labels[$i]}" = "$label" ] || continue
          found=1
          [ "${sel_vals[$i]}" = 0 ] || any_sel=1
          [ "${sel_classes[$i]}" != always_on ] || any_always=1
        done
        [ "$found" = 1 ] || { printf 'missing_row'; return 0; }  # GUARD:G2-11-MISSING-ROW
        [ "$any_always" = 0 ] || { printf 'always_on'; return 0; }  # GUARD:G2-11-ALWAYS-ON
        [ "$any_sel" = 0 ] || { printf 'selected'; return 0; }  # GUARD:G2-11-SELECTED
        n=$((n + 1))
        ;;
      SUITE_COMMAND*|SUITE_REGISTRATION*) printf 'parse'; return 0 ;;
    esac
  done < "$1"
  [ "$n" -ge 1 ] || { printf 'no_records'; return 0; }  # GUARD:G2-11-NO-RECORDS
  printf 'skip'
}

# ---- the work -------------------------------------------------------------------------------------------------------
run() {
  local parts p1 p2 h rl st p n nul size paths t0 rem rc g leg tok list diagrams
  local test_all sel_file enum_file groups_summary groups_n degraded meta om nm

  reason=not_pr
  [ "${EVENT_NAME:-}" = pull_request ] || return 0  # GUARD:G2-NOT-PR

  # (2) the merge-ref shape: HEAD is GITHUB_SHA, has exactly two parents, and HEAD^2 is the PR head. All 40-hex.
  reason=bad_merge_shape
  [[ "${GITHUB_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || return 0
  [[ "${PR_HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || return 0
  rl="$(git rev-list --parents -n 1 HEAD 2>/dev/null)" || return 0  # GUARD:G2-1-REVLIST
  read -r -a parts <<< "$rl"
  [ "${#parts[@]}" -eq 3 ] || return 0  # GUARD:G2-1-TWO-PARENTS
  h="${parts[0]}"; p1="${parts[1]}"; p2="${parts[2]}"
  [[ "$h" =~ ^[0-9a-f]{40}$ && "$p1" =~ ^[0-9a-f]{40}$ && "$p2" =~ ^[0-9a-f]{40}$ ]] || return 0
  [ "$h" = "$GITHUB_SHA" ] || return 0  # GUARD:G2-1-HEAD-IS-GITHUB-SHA
  [ "$p2" = "$PR_HEAD_SHA" ] || return 0  # GUARD:G2-1-PARENT2-IS-PR-HEAD
  head_sha="$p2"
  base_sha="$p1"

  # (3) full on a fork head, a re-run, an empty diff and a diff over 500 files.
  reason=fork
  { [ -n "${HEAD_REPO:-}" ] && [ "${HEAD_REPO:-}" = "${GH_REPO:-}" ]; } || return 0  # GUARD:G2-FORK
  reason=rerun
  [ "${RUN_ATTEMPT:-}" = 1 ] || return 0  # GUARD:G2-7-RERUN

  # (4) the listing goes to a FILE: never argv, never env, never an annotation.
  reason=diff_error
  work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-selection.XXXXXX" 2>/dev/null)" || return 0
  git diff -z --raw --no-renames --no-abbrev --no-ext-diff --no-color HEAD^1 HEAD -- > "$work/names.z" 2> "$work/diff.err" || return 0  # GUARD:G2-1-DIFF-RC
  size="$(wc -c < "$work/names.z")" || return 0
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  reason=empty_diff
  [ "$size" -gt 0 ] || return 0  # GUARD:G2-15-EMPTY-DIFF
  reason=malformed_diff
  nul="$(tr -cd '\0' < "$work/names.z" | wc -c)" || return 0
  [[ "$nul" =~ ^[0-9]+$ ]] || return 0
  [ $((nul % 2)) -eq 0 ] || return 0
  files=$((nul / 2))
  reason=too_many_files
  [ "$files" -le 500 ] || return 0  # GUARD:G2-15-MAX-FILES
  reason=malformed_diff
  [ "$files" -ge 1 ] || return 0

  # (5) STAGE 1: the positive allowlist, one pass, no pipe.
  diagrams=0
  paths=""
  n=0
  while IFS= read -r -d '' meta; do
    IFS= read -r -d '' p || { reason=malformed_diff; return 0; }
    n=$((n + 1))
    [ -n "$p" ] || { reason=malformed_diff; return 0; }
    [[ "$meta" =~ ^:([0-7]{6})\ ([0-7]{6})\ ([0-9a-f]{40,64})\ ([0-9a-f]{40,64})\ ([A-Z][0-9]*)$ ]] || { reason=malformed_diff; return 0; }
    om="${BASH_REMATCH[1]}"; nm="${BASH_REMATCH[2]}"; st="${BASH_REMATCH[5]}"
    case "$st" in M|A|D) ;; *) reason=non_doc_status; return 0 ;; esac  # GUARD:G2-STATUS
    case "$om" in 000000|100644|100755) ;; *) reason=non_doc_mode; return 0 ;; esac  # GUARD:G2-MODE-OLD
    case "$nm" in 000000|100644|100755) ;; *) reason=non_doc_mode; return 0 ;; esac  # GUARD:G2-MODE-NEW
    if [[ "$p" =~ [^\ -~] ]]; then reason=odd_path; return 0; fi  # GUARD:G2-14-CNTRL
    if [[ "$p" == *'::'* ]]; then reason=odd_path; return 0; fi  # GUARD:G2-14-COLONS
    if [[ "$p" == *,* ]]; then reason=odd_path; return 0; fi  # GUARD:G2-14-COMMA
    if is_trigger_path "$p"; then reason=trigger; return 0; fi  # GUARD:G2-2-TRIGGER
    if ! is_doc_path "$p"; then reason=non_doc; return 0; fi  # GUARD:G2-15-ALLOWLIST
    case "$p" in knowledge-base/engineering/architecture/diagrams/*) diagrams=1 ;; esac  # GUARD:G2-15-DIAGRAMS-FLAG
    paths="${paths:+$paths,}$p"
  done < "$work/names.z"
  [ "$n" -eq "$files" ] || { reason=malformed_diff; return 0; }
  reason=paths_too_long
  [ "${#paths}" -le 100000 ] || return 0  # GUARD:G2-15-PATHS-CAP

  # (6) STAGE 2 runs only for a doc-only diff AND only when the switch is exactly `on` (the sw token above is the stage-2
  # decision point). Any other value stops here with ZERO selector calls; stage 1 and the notice already ran.
  reason=switch_off
  [ "$sw" = on ] || return 0  # GUARD:G2-16-SWITCH-GATE
  stage=2
  reason=selector_error
  test_all="${PR_SELECTION_TEST_ALL:-scripts/test-all.sh}"
  t0=$SECONDS
  sel_file="$work/selection.out"

  timeout -k 5 "$budget" env -u CI -u SOLEUR_TEST_FORCE_ALL -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY -u GITHUB_ENV -u GITHUB_PATH -u GITHUB_STATE bash "$test_all" --print-selection "--paths=$paths" < /dev/null > "$sel_file" 2> "$work/selection.err"  # GUARD:G2-9-CI-UNSET
  rc=$?
  sel_s=$((SECONDS - t0))
  # 124 is `timeout`'s own; 137 is the `-k` SIGKILL (and also an OOM kill, recorded here as a timeout: fail closed either way)
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then sel_censored=1; reason=selector_timeout; return 0; fi
  [ "$rc" -eq 0 ] || return 0
  parse_selection "$sel_file" || { reason=selector_unparsed; return 0; }
  if [ "$sel_fallback_seen" = 1 ]; then reason=selector_fallback; return 0; fi
  if [ "$sel_summary_bad" = 1 ]; then reason=selector_fallback; return 0; fi
  if [ "$sel_summary_ok" -ne 1 ]; then reason=selector_unparsed; return 0; fi  # GUARD:G2-10-SUMMARY-COUNT
  [ "${#sel_labels[@]}" -ge 1 ] || { reason=selector_unparsed; return 0; }  # GUARD:G2-10-ZERO-ROWS

  list=""
  groups_summary=""
  groups_n=""
  degraded=0
  for g in webplat bun scripts-heavy; do
    leg="test-$g"
    enum_file="$work/enum-$g.out"
    rem=$((budget - (SECONDS - t0)))
    if [ "$rem" -lt 1 ]; then tok=timeout  # GUARD:G2-9-REM
    else
      timeout -k 5 "$rem" env -u CI -u SOLEUR_TEST_FORCE_ALL -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY -u GITHUB_ENV -u GITHUB_PATH -u GITHUB_STATE bash "$test_all" --enumerate-commands "--paths=$paths" "$g" < /dev/null > "$enum_file" 2> "$work/enum-$g.err"  # GUARD:G2-9-CI-UNSET-ENUM
      rc=$?
      if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then tok=timeout
      elif [ "$rc" -ne 0 ]; then tok=bad_rc
      else tok="$(eval_group "$enum_file")"
      fi
    fi
    # An empty or unknown token (the evaluation subshell aborted) is `empty`: degraded, and the notice grammar stays intact.
    case "$tok" in skip|selected|always_on|plain_decline|timeout|bad_rc|parse|missing_row|no_records) ;; *) tok=empty ;; esac  # GUARD:G2-11-EMPTY-TOK
    if [ "$g" = webplat ] && [ "$diagrams" = 1 ] && [ "$tok" = skip ]; then tok=diagrams; fi  # GUARD:G2-15-DIAGRAMS
    case "$tok" in timeout) sel_censored=1; degraded=1 ;; bad_rc|parse|missing_row|no_records|empty) degraded=1 ;; esac
    groups_summary="${groups_summary:+$groups_summary }$leg=$tok"
    groups_n="${groups_n:+$groups_n,}$g:$tok"
    if [ "$tok" = skip ]; then list="${list:+$list,}$leg"; fi
  done
  sel_s=$((SECONDS - t0))
  mode=affected
  groups="$groups_n"
  if [ "$degraded" = 1 ]; then reason=affected_degraded; else reason=affected; fi
  [ -z "$list" ] || would_skip="$list"
  printf 'pr-selection: groups %s\n' "$groups_summary" >> "$SUMMARY"
  return 0
}

run

# ---- (7) the arm: switch exactly `on` AND the lock absent AND the selector answered cleanly -------------------------------
# The `sw = on` conjunct is REDUNDANT with the stage-2 gate (mode=affected already implies it) and is kept on purpose: it is the
# independent arming check, so a regression that deletes the stage-2 gate still cannot arm a skip for another switch value.
# Removing it ALONE is an equivalent mutant and no test isolates it (a masked-pair mutant was dropped: it was killed by its gate-bypass half).
# Treat it as defence in depth, not as a separately protected control.
if [ "$mode" = affected ] && [ "$would_skip" != none ] && [ "$sw" = on ] && [ "$locked" = false ]; then  # GUARD:G2-13-ARM
  active=true
  skip_legs="$would_skip"  # GUARD:G2-13-SKIP-ONLY-WHEN-ACTIVE
fi

# Re-validate every value against its output grammar before it is written. A value that fails collapses to the defaults.
[[ "$head_sha" =~ ^([0-9a-f]{40})?$ ]] || { head_sha=""; base_sha=""; }
[[ "$base_sha" =~ ^([0-9a-f]{40})?$ ]] || { head_sha=""; base_sha=""; }
if [ "$active" != true ] || ! [[ "$skip_legs" =~ ^(test-webplat|test-bun|test-scripts-heavy)(,(test-webplat|test-bun|test-scripts-heavy))*$ ]]; then
  active=false
  skip_legs=""
fi

# ---- (8) ONE final block, skip_legs LAST ----------------------------------------------------------------------------
# A signal between this printf and `finished=1` would make the notice say active=false (signalled) while the file says true.
# Ignore the three signals across the two statements (never restored: nothing after this point needs them).
trap '' HUP INT TERM  # GUARD:G2-12-SIGNAL-WINDOW
printf 'head_sha=%s\nbase_sha=%s\nactive=%s\nskip_legs=%s\n' "$head_sha" "$base_sha" "$active" "$skip_legs" >> "$OUT"  # GUARD:G2-12-FINAL-BLOCK

# ---- (9) the annotation and the summary -----------------------------------------------------------------------------
finished=1
emit_notice
printf 'pr-selection: switch=%s locked=%s reason=%s would_skip=%s active=%s sel_s=%s sel_censored=%s budget=%s groups=%s\n' \
  "$sw" "$locked" "$reason" "$would_skip" "$active" "$sel_s" "$sel_censored" "$budget" "$groups" >> "$SUMMARY"
exit 0  # on_exit removes the scratch dir
