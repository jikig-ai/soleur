#!/usr/bin/env bash
# Runner for the scheduled real-SDK ask probe — #10111 Part 1 / ADR-284 amendment.
#
# Wraps apps/web-platform/scripts/dev-probe-destroy-ask.ts for .github/workflows/scheduled-real-sdk-ask-probe.yml so the parts that decide
# whether the lane is guarded (exit-code mapping, rerun policy, issue dedupe) are testable offline instead of rotting in workflow YAML.
# Offline suite: real-sdk-ask-probe.test.sh (stub probe, stub gh that exits 64 on unexpected argv, tiny real git repos).
#
# Subcommands (run from the repository root):
#   should-run   Push events only; every other event prints run=true. Compares the push with the last COMPLETED, NON-CANCELLED run of
#                this workflow on main (a run evicted from the concurrency queue is recorded as cancelled and must not hide an SDK change):
#                any changed file in the push allowlist other than the two package files -> run=true; only the package files changed ->
#                run=true unless the resolved @anthropic-ai/claude-agent-sdk and @anthropic-ai/claude-code versions are equal in both
#                lockfiles. Fails TOWARD running on any uncertainty. Writes run=true|false to $GITHUB_OUTPUT.
#                Env: GITHUB_EVENT_NAME, GITHUB_SHA, PUSH_BEFORE_SHA (github.event.before), GITHUB_REPOSITORY, GH_TOKEN, WORKFLOW_FILE
#                (default scheduled-real-sdk-ask-probe.yml; needs `actions: read`).
#   run          Runs $PROBE_CMD (default: bun run apps/web-platform/scripts/dev-probe-destroy-ask.ts) with NODE_ENV=test, redacts the
#                output into $PROBE_OUT_FILE (the artifact), classifies it in ONE place (classify), reruns the whole probe at most once on the
#                REMAINING share of the single $4 cap, writes the job summary ($GITHUB_STEP_SUMMARY) and outputs outcome, reason, cost,
#                provenance to $GITHUB_OUTPUT. Exits 0 only for outcome=pass.
#   file-issue   Filer job only (never the PR self-test): maps the probe job's outputs to at most one open issue per class (exact-title
#                match). Env: PROBE_OUTCOME, PROBE_REASON, PROBE_COST, PROBE_PROVENANCE, PROBE_JOB_RESULT (needs.probe.result),
#                GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_SERVER_URL, GH_TOKEN.
#
# Outcomes: pass | fail | blind (could not measure) | skipped (explicit, set by the workflow, never by this script).
# A pass is a measurement of the HOST-side SDK boundary only; no output here may describe it as production verification.
#
# xtrace refusal first: tracing echoes expanded values, and this script runs with a live API key and a GitHub token (#7797).

set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${ANTHROPIC_API_KEY:+x}${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

RUN_BUDGET_USD=4   # mirrors RUN_BUDGET_USD in scripts/lib/probe-budget.ts (the offline suite asserts equality)
MIN_CASES=8        # mirrors MIN_DEFAULT_CASES in dev-probe-destroy-ask.ts (the offline suite asserts equality)
MIN_RERUN_BUDGET_USD=0.50
LABEL="ci/real-sdk-ask-probe"
TITLE_REGRESSION="[ci/real-sdk-ask-probe] real-SDK ask probe regression"
TITLE_BLIND="[ci/real-sdk-ask-probe] real-SDK ask probe blind"
ADR_PATH="knowledge-base/engineering/architecture/decisions/ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md"
POSTMORTEM_PATH="knowledge-base/engineering/operations/post-mortems/2026-10-11-hosted-bash-ask-bypassed-by-sdk-auto-allow-postmortem.md"
SDK_PACKAGES=("@anthropic-ai/claude-agent-sdk" "@anthropic-ai/claude-code")
LOCKFILE="apps/web-platform/package-lock.json"
# Every user-visible string (job summary, issue bodies) carries this: the scope of what a result means.
HOST_ONLY_RESIDUAL="host-only residual: this probe runs on a CI host with host bwrap, not in the hosted container whose sandbox is the variable behind #10054; the in-process Sentry capture proves emission only; production arrival not observed."

emit() { # key value -> $GITHUB_OUTPUT (stdout when unset)
  printf '%s=%s\n' "$1" "$2" >>"${GITHUB_OUTPUT:-/dev/stdout}"
}

# --- value normalisers: nothing from probe output crosses a job boundary or lands in an issue body unless it passes one of these --------
norm_reason() {
  case "$1" in
    *$'\n'*|*$'\r'*) printf 'contract-drift' ;;
    pass|probe-fail|budget-exceeded|no-anthropic-key|model-did-not-attempt-bash|sandbox-not-engaged|grant-not-live|grant-control-not-established|case-count-below-floor|cant-run|diagnostic|crash|contract-drift|no-outcome) printf '%s' "$1" ;;
    *) printf 'contract-drift' ;;
  esac
}
norm_cost() {
  case "$1" in *$'\n'*|*$'\r'*) printf 'unknown'; return 0 ;; esac
  if [[ "$1" =~ ^[0-9]{1,6}(\.[0-9]{1,6})?$ ]]; then printf '%s' "$1"; else printf 'unknown'; fi
}
norm_prov() {
  case "$1" in *$'\n'*|*$'\r'*) printf 'unknown'; return 0 ;; esac
  if [[ "$1" =~ ^sdk=[A-Za-z0-9._+-]+\ cli=[A-Za-z0-9._+-]+$ ]]; then printf '%s' "$1"; else printf 'unknown'; fi
}

redact() {
  sed -E 's/sk-ant-[A-Za-z0-9_-]+/<redacted>/g; s/sk-[A-Za-z0-9_-]{20,}/<redacted>/g; s/gh[pousr]_[A-Za-z0-9]{20,}/<redacted>/g; s/github_pat_[A-Za-z0-9_]{20,}/<redacted>/g'
}

# =================================================================================================================================
# should-run
# =================================================================================================================================
in_run_allowlist() { # file triggers a run on its own (the package files are handled separately)
  case "$1" in
    apps/web-platform/server/agent-runner-sandbox-config.ts|apps/web-platform/server/sandbox-hook.ts|apps/web-platform/server/agent-runner-query-options.ts|apps/web-platform/server/permission-callback.ts|apps/web-platform/server/destroy-ask-classifier.ts|apps/web-platform/server/destroy-ask-lane.ts|apps/web-platform/server/agent-env.ts) return 0 ;;
    apps/web-platform/scripts/dev-probe-destroy-ask.ts|apps/web-platform/scripts/real-sdk-ask-probe.sh|apps/web-platform/scripts/lib/probe-budget.ts) return 0 ;;
    plugins/soleur/hooks/*) return 0 ;;
    .github/workflows/scheduled-real-sdk-ask-probe.yml) return 0 ;;
  esac
  return 1
}

lock_version() { # lockfile-content package -> version or empty
  jq -r --arg k "node_modules/$2" '.packages[$k].version // ""' <<<"$1" 2>/dev/null || printf ''
}

cmd_should_run() {
  local event="${GITHUB_EVENT_NAME:-}" sha="${GITHUB_SHA:-}" before="${PUSH_BEFORE_SHA:-}"
  local repo="${GITHUB_REPOSITORY:-}" wf="${WORKFLOW_FILE:-scheduled-real-sdk-ask-probe.yml}"
  local baseline runs files f pkg_changed=0 base_lock head_lock bv hv p

  if [ "$event" != "push" ]; then
    emit run true
    echo "real-sdk-ask-probe: event '${event:-unset}' always runs"
    return 0
  fi
  if [ -z "$sha" ] || [ -z "$before" ] || [[ "$before" =~ ^0+$ ]]; then
    emit run true
    echo "::notice::real-sdk-ask-probe: no usable before/head SHA, running"
    return 0
  fi
  if ! runs="$(gh api "repos/${repo}/actions/workflows/${wf}/runs?branch=main&status=completed&per_page=30" 2>/dev/null)"; then
    emit run true
    echo "::notice::real-sdk-ask-probe: could not list previous runs, running"
    return 0
  fi
  baseline="$(jq -r --arg sha "$sha" '[.workflow_runs[]? | select(.conclusion != null and .conclusion != "cancelled" and .head_sha != $sha)][0].head_sha // empty' <<<"$runs" 2>/dev/null || printf '')"
  if ! [[ "$baseline" =~ ^[0-9a-f]{40}$ ]]; then
    emit run true
    echo "::notice::real-sdk-ask-probe: no completed non-cancelled baseline run, running"
    return 0
  fi
  if ! git fetch --no-tags --depth=1 origin "$baseline" >/dev/null 2>&1; then
    emit run true
    echo "::notice::real-sdk-ask-probe: baseline ${baseline:0:12} could not be fetched, running"
    return 0
  fi
  if ! files="$(git diff --name-only "$baseline" "$sha" 2>/dev/null)"; then
    emit run true
    echo "::notice::real-sdk-ask-probe: could not diff ${baseline:0:12}..${sha:0:12}, running"
    return 0
  fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if in_run_allowlist "$f"; then
      emit run true
      echo "::notice::real-sdk-ask-probe: ${f} changed since the last completed run (${baseline:0:12}), running"
      return 0
    fi
    case "$f" in apps/web-platform/package.json|"$LOCKFILE") pkg_changed=1 ;; esac
  done <<<"$files"
  if [ "$pkg_changed" -eq 0 ]; then
    # A push-filtered workflow should always see an allowlisted file; a net-empty diff is unexpected, so fail toward running.
    emit run true
    echo "::notice::real-sdk-ask-probe: no allowlisted file in ${baseline:0:12}..${sha:0:12}, running"
    return 0
  fi
  if ! base_lock="$(git show "${baseline}:${LOCKFILE}" 2>/dev/null)" || ! head_lock="$(git show "${sha}:${LOCKFILE}" 2>/dev/null)"; then
    emit run true
    echo "::notice::real-sdk-ask-probe: a lockfile could not be read, running"
    return 0
  fi
  for p in "${SDK_PACKAGES[@]}"; do
    bv="$(lock_version "$base_lock" "$p")"
    hv="$(lock_version "$head_lock" "$p")"
    if [ -z "$bv" ] || [ -z "$hv" ] || [ "$bv" != "$hv" ]; then
      emit run true
      echo "::notice::real-sdk-ask-probe: ${p} ${bv:-?} -> ${hv:-?}, running"
      return 0
    fi
  done
  emit run false
  echo "::notice::real-sdk-ask-probe: only package files changed and neither SDK version moved since ${baseline:0:12}, skipping the paid probe"
  return 0
}

# =================================================================================================================================
# run
# =================================================================================================================================

# classify <exit-code> <redacted-output-file>
# The ONE place that computes the outcome. Sets C_OUTCOME (pass|fail|blind), C_REASON (norm_reason enum), C_RETRY (yes|no), C_COST, C_PROV.
# `pass` needs exit 0 AND `RESULT: PASS` AND cases-run >= MIN_CASES AND >= MIN_CASES case lines AND remote refs unchanged.
classify() {
  local rc="$1" f="$2" result_line rest token cases_run case_lines refs_ok r
  C_OUTCOME=blind; C_REASON=crash; C_RETRY=no
  C_COST="$(norm_cost "$(sed -n 's/^TOTAL costUsd=\(.*\)$/\1/p' "$f" | tail -1)")"
  C_PROV="$(norm_prov "$(sed -n 's/^PROVENANCE \(sdk=[^ ]* cli=[^ ]*\)\( .*\)\{0,1\}$/\1/p' "$f" | head -1)")"
  result_line="$(awk '/^RESULT: /{l=$0} END{print l}' "$f")"
  rest="${result_line#RESULT: }"
  token="${rest%% *}"
  cases_run="$(sed -n 's/.*cases-run=\([0-9][0-9]*\).*/\1/p' <<<"$result_line" | tail -1)"
  [[ "$cases_run" =~ ^[0-9]+$ ]] || cases_run=0
  case_lines="$(awk '/^PROBE [^ ]+ .*verdict=/{n++} END{print n+0}' "$f")"
  refs_ok="$(awk '/^PROBE remote-refs-unchanged=/{l=$0} END{print (l ~ /^PROBE remote-refs-unchanged=true( |$)/) ? 1 : 0}' "$f")"
  case "$token" in
    "")
      C_REASON=crash
      ;;
    PASS)
      if [ "$rc" -eq 0 ] && [ "$cases_run" -ge "$MIN_CASES" ] && [ "$case_lines" -ge "$MIN_CASES" ] && [ "$refs_ok" -eq 1 ]; then
        C_OUTCOME=pass; C_REASON=pass
      else
        C_REASON=contract-drift
      fi
      ;;
    FAIL)
      if [ "$rc" -eq 1 ]; then C_OUTCOME=fail; C_REASON=probe-fail; else C_REASON=contract-drift; fi
      ;;
    CANT-RUN:*)
      if [ "$rc" -ne 3 ]; then
        C_REASON=contract-drift
      else
        r="${token#CANT-RUN:}"
        case "$r" in
          budget-exceeded|no-anthropic-key) C_REASON="$r"; C_RETRY=no ;;
          model-did-not-attempt-bash|sandbox-not-engaged|grant-not-live|grant-control-not-established|case-count-below-floor) C_REASON="$r"; C_RETRY=yes ;;
          *) C_REASON=cant-run; C_RETRY=yes ;;
        esac
      fi
      ;;
    DIAGNOSTIC)
      C_REASON=diagnostic
      ;;
    *)
      C_REASON=contract-drift
      ;;
  esac
  C_REASON="$(norm_reason "$C_REASON")"
}

# run_probe_pass <n> [budget] -> redacted output in $WORK/red.<n>, exit code in P_RC
run_probe_pass() {
  local n="$1" budget="${2:-}" raw="$WORK/raw.$1"
  local -a cmd
  read -r -a cmd <<<"$PROBE_CMD"
  if [ -n "$budget" ]; then
    PROBE_RUN_BUDGET_USD="$budget" NODE_ENV=test "${cmd[@]}" </dev/null >"$raw" 2>&1
    P_RC=$?
  else
    env -u PROBE_RUN_BUDGET_USD NODE_ENV=test "${cmd[@]}" </dev/null >"$raw" 2>&1
    P_RC=$?
  fi
  redact <"$raw" >"$WORK/red.$n"
  rm -f "$raw"
}

write_summary() { # outcome reason cost provenance attempts
  {
    printf '## Real-SDK ask probe: %s\n\n' "$1"
    printf -- '- outcome: %s (%s)\n' "$1" "$2"
    printf -- '- measured cost (SDK estimate, not a bill): $%s of the $%s per-run cap\n' "$3" "$RUN_BUDGET_USD"
    printf -- '- SDK/CLI: %s\n' "$4"
    printf -- '- attempts: %s\n' "$5"
    printf -- '- scope: %s\n' "$HOST_ONLY_RESIDUAL"
    case "$1" in
      pass) printf -- '- meaning: the real-SDK probe passed against the repo-head SDK, CLI and option builder on a CI host; it does not discharge ADR-284 Flip criteria 1 or 5 without a build_sha match.\n' ;;
      fail) printf -- '- meaning: REGRESSION — the hook-then-canUseTool precedence is not holding on this build. A p1 issue is filed by the filer job.\n' ;;
      *) printf -- '- meaning: the probe could not measure (never a pass). A p2 issue is filed by the filer job.\n' ;;
    esac
    printf '\n```\n'
    cat "$6"
    printf '```\n'
  } >>"${GITHUB_STEP_SUMMARY:-/dev/stdout}"
}

cmd_run() {
  PROBE_CMD="${PROBE_CMD:-bun run apps/web-platform/scripts/dev-probe-destroy-ask.ts}"
  local out_file="${PROBE_OUT_FILE:-${RUNNER_TEMP:-.}/real-sdk-ask-probe.out}"
  local spent1 remaining attempts=1 cost2 total_cost outcome reason prov cost
  WORK="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
  trap 'rm -rf "$WORK"' EXIT

  run_probe_pass 1
  classify "$P_RC" "$WORK/red.1"
  : >"$out_file"
  { printf '=== pass 1 (exit %s) ===\n' "$P_RC"; cat "$WORK/red.1"; } >>"$out_file"
  cat "$WORK/red.1"
  outcome="$C_OUTCOME"; reason="$C_REASON"; cost="$C_COST"; prov="$C_PROV"
  cp "$WORK/red.1" "$WORK/final"

  if [ "$outcome" = "blind" ] && [ "$C_RETRY" = "yes" ]; then
    # One whole-probe rerun, on what is LEFT of the single run cap, so both passes together stay inside it.
    spent1="$cost"; [ "$spent1" = "unknown" ] && spent1=0
    remaining="$(awk -v cap="$RUN_BUDGET_USD" -v spent="$spent1" 'BEGIN{r=cap-spent; if(r<0)r=0; printf "%.2f", r}')"
    if awk -v cap="$RUN_BUDGET_USD" -v spent="$spent1" -v min="$MIN_RERUN_BUDGET_USD" 'BEGIN{exit !((cap-spent) >= min - 1e-9)}'; then
      echo "real-sdk-ask-probe: pass 1 was CANT-RUN:${reason}; rerunning once with \$${remaining} of the \$${RUN_BUDGET_USD} cap left"
      attempts=2
      run_probe_pass 2 "$remaining"
      classify "$P_RC" "$WORK/red.2"
      { printf '=== pass 2 (exit %s, budget %s) ===\n' "$P_RC" "$remaining"; cat "$WORK/red.2"; } >>"$out_file"
      cat "$WORK/red.2"
      cp "$WORK/red.2" "$WORK/final"
      outcome="$C_OUTCOME"; reason="$C_REASON"; prov="$C_PROV"
      cost2="$C_COST"
      if [ "$cost" = "unknown" ] || [ "$cost2" = "unknown" ]; then
        total_cost=unknown
      else
        total_cost="$(awk -v a="$cost" -v b="$cost2" 'BEGIN{printf "%.4f", a+b}')"
      fi
      cost="$total_cost"
    else
      echo "real-sdk-ask-probe: pass 1 was CANT-RUN:${reason}; only \$${remaining} of the cap is left (< \$${MIN_RERUN_BUDGET_USD}), not rerunning"
    fi
  fi

  write_summary "$outcome" "$reason" "$cost" "$prov" "$attempts" "$WORK/final"
  emit outcome "$outcome"
  emit reason "$reason"
  emit cost "$cost"
  emit provenance "$prov"
  if [ "$outcome" = "pass" ]; then
    echo "real-sdk-ask-probe: pass (cost \$${cost}). ${HOST_ONLY_RESIDUAL}"
    return 0
  fi
  echo "::error::real-sdk-ask-probe: outcome=${outcome} reason=${reason}. ${HOST_ONLY_RESIDUAL}"
  return 1
}

# =================================================================================================================================
# file-issue
# =================================================================================================================================
build_body() { # outfile class(regression|blind) mode(new|again|passed) outcome reason cost prov run_url
  local out="$1" class="$2" mode="$3" outcome="$4" reason="$5" cost="$6" prov="$7" url="$8"
  local base="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/blob/main"
  {
    case "$mode" in
      passed) printf '%s\n\n' "A later run of the real-SDK ask probe subsequently passed. This issue stays OPEN: a green run never closes a regression issue (the lane may be flaky or a path outside the filter may still be inert); a human reviews and closes it." ;;
      again)  printf '%s\n\n' "Another occurrence of this probe outcome." ;;
      *)
        if [ "$class" = "regression" ]; then
          printf '%s\n\n' "The scheduled real-SDK ask probe reported FAIL: with the repo-head SDK, bundled CLI and option builder, a destroy-family Bash command did not get the Approve/Reject card on the hook-then-canUseTool path (the #10054 class). Treat as a regression of the hosted must-ask lane until proven otherwise."
        else
          printf '%s\n\n' "The scheduled real-SDK ask probe could NOT measure the lane (CANT-RUN, a diagnostic result, a crash with no RESULT line, a budget stop, or a setup failure). A blind probe is never a pass; this issue closes itself on the next PASS."
        fi
        ;;
    esac
    printf -- '- outcome: %s\n- reason: %s\n- measured cost (SDK estimate, not a bill): $%s\n- SDK/CLI: %s\n- run: %s\n\n' "$outcome" "$reason" "$cost" "$prov" "$url"
    printf '%s\n\n' "Scope: ${HOST_ONLY_RESIDUAL}"
    printf -- '- ADR-284 (see the "C9 result" paragraphs): %s/%s\n- Post-mortem: %s/%s\n' "$base" "$ADR_PATH" "$base" "$POSTMORTEM_PATH"
  } >"$out"
}

cmd_file_issue() {
  local repo="${GITHUB_REPOSITORY:-}" event="${GITHUB_EVENT_NAME:-}" outcome="${PROBE_OUTCOME:-}" reason cost prov job="${PROBE_JOB_RESULT:-}"
  local url issues_json class title prio num n rc=0 body

  if [ "$event" = "pull_request" ]; then
    echo "real-sdk-ask-probe: the PR self-test never files issues"
    return 0
  fi
  if [ -z "$outcome" ]; then
    case "$job" in
      failure|cancelled) outcome=blind; reason=no-outcome; cost=unknown ;;
      *)
        echo "::error::real-sdk-ask-probe: file-issue got an empty outcome and the probe job result is '${job:-unset}'; refusing to guess" >&2
        return 2
        ;;
    esac
  else
    reason="$(norm_reason "${PROBE_REASON:-}")"
    cost="$(norm_cost "${PROBE_COST:-}")"
  fi
  prov="$(norm_prov "${PROBE_PROVENANCE:-}")"
  case "$outcome" in
    skipped) echo "real-sdk-ask-probe: skipped is never a pass and files nothing"; return 0 ;;
    pass|fail|blind) : ;;
    *) echo "::error::real-sdk-ask-probe: unknown outcome, refusing to file" >&2; return 2 ;;
  esac

  url="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID:-0}"
  [[ "$url" =~ ^https://[A-Za-z0-9._/-]+$ ]] || url=unknown

  if ! issues_json="$(gh issue list --repo "$repo" --state open --label "$LABEL" --limit 200 --json number,title 2>/dev/null)"; then
    echo "::error::real-sdk-ask-probe: could not list open issues; filing nothing" >&2
    return 1
  fi
  open_numbers() { # title -> open issue numbers with EXACTLY this title, oldest first (never a fuzzy match)
    jq -r --arg t "$1" '[.[] | select(.title == $t)] | sort_by(.number) | .[].number' <<<"$issues_json"
  }
  local reg_nums blind_nums
  if ! reg_nums="$(open_numbers "$TITLE_REGRESSION")" || ! blind_nums="$(open_numbers "$TITLE_BLIND")"; then
    echo "::error::real-sdk-ask-probe: the issue list was not parseable; filing nothing" >&2
    return 1
  fi
  body="$(mktemp -t soleur-run.$$.XXXXXXXX)"

  case "$outcome" in
    pass)
      for num in $blind_nums; do
        build_body "$body" blind passed "$outcome" "$reason" "$cost" "$prov" "$url"
        gh issue comment "$num" --repo "$repo" --body-file "$body" >/dev/null || rc=1
        gh issue close "$num" --repo "$repo" --reason completed >/dev/null || rc=1
      done
      for num in $reg_nums; do
        build_body "$body" regression passed "$outcome" "$reason" "$cost" "$prov" "$url"
        gh issue comment "$num" --repo "$repo" --body-file "$body" >/dev/null || rc=1
      done
      ;;
    fail|blind)
      if [ "$outcome" = "fail" ]; then
        class=regression; title="$TITLE_REGRESSION"; prio="priority/p1-high"; n="$(printf '%s' "$reg_nums" | head -1)"
      else
        class=blind; title="$TITLE_BLIND"; prio="priority/p2-medium"; n="$(printf '%s' "$blind_nums" | head -1)"
      fi
      if [ -n "$n" ]; then
        build_body "$body" "$class" again "$outcome" "$reason" "$cost" "$prov" "$url"
        gh issue comment "$n" --repo "$repo" --body-file "$body" >/dev/null || rc=1
      else
        build_body "$body" "$class" new "$outcome" "$reason" "$cost" "$prov" "$url"
        # Idempotent: an existing label makes this fail, which is fine.
        gh label create "$LABEL" --repo "$repo" --color D93F0B --description "Scheduled real-SDK ask probe findings (ADR-284)" >/dev/null 2>&1 || true
        gh issue create --repo "$repo" --title "$title" --body-file "$body" \
          --label type/security --label domain/engineering --label "$prio" --label "$LABEL" >/dev/null || rc=1
      fi
      ;;
  esac
  rm -f "$body"
  return "$rc"
}

# =================================================================================================================================
case "${1:-}" in
  should-run) cmd_should_run ;;
  run) cmd_run ;;
  file-issue) cmd_file_issue ;;
  *) echo "usage: $0 {should-run|run|file-issue}" >&2; exit 2 ;;
esac
