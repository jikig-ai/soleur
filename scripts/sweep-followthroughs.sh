#!/usr/bin/env bash
# Sweep open `follow-through` issues, parse the soleur:followthrough
# directive in their bodies, and run the referenced verification script
# when the earliest-check timestamp has passed. Close the issue with a
# PASS comment on script exit 0; comment FAIL and leave open on exit 1;
# comment TRANSIENT and leave open on any other exit.
#
# Convention: knowledge-base/engineering/ops/runbooks/followthrough-convention.md
#
# Required env:
#   GH_TOKEN  — GitHub token with issues:write
#
# Optional env:
#   GH_REPO   — repo (defaults to current)
#   DRY_RUN   — set to 1 to skip close/comment, only print actions
#
# All other env vars listed in the directive's `secrets=` clause are
# expected to be present in the calling environment (the workflow YAML
# is responsible for selectively exposing them).

set -euo pipefail

REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
DRY_RUN="${DRY_RUN:-0}"
SCRIPTS_ROOT="scripts/followthroughs"

now_epoch=$(date -u +%s)

log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# Parse a single directive from an issue body. Stdin = body text.
# Writes lines: `KEY VALUE` for script/earliest/secrets, or nothing if no
# directive is present. Multiple directives in one body → only the first
# is honored (log a warning).
parse_directive() {
  awk '
    /<!-- *soleur:followthrough/, /-->/ {
      gsub(/^<!-- *soleur:followthrough/, "")
      gsub(/-->/, "")
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
        if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
        if ($i ~ /^secrets=/)  { sub(/^secrets=/, "", $i);  print "secrets "  $i }
      }
    }
  '
}

iso_to_epoch() {
  # GNU date; portable enough for ubuntu-latest runner. Empty stdin → 0.
  local iso="$1"
  [[ -z "$iso" ]] && { echo 0; return; }
  date -u -d "$iso" +%s 2>/dev/null || echo 0
}

run_one() {
  local issue_num="$1"
  local body="$2"

  local script earliest secrets
  while read -r key val; do
    case "$key" in
      script)   script="$val" ;;
      earliest) earliest="$val" ;;
      secrets)  secrets="$val" ;;
    esac
  done < <(printf '%s' "$body" | parse_directive)

  if [[ -z "${script:-}" ]]; then
    log "issue #$issue_num: no directive — skipping"
    return 0
  fi

  log "issue #$issue_num: directive found (script=$script earliest=${earliest:-now} secrets=${secrets:-none})"

  # Path safety: script MUST live under scripts/followthroughs/. Reject
  # anything else so a tampered issue body can't point at /etc/passwd.
  case "$script" in
    "$SCRIPTS_ROOT"/*) : ok ;;
    *)
      fail "issue #$issue_num: script path '$script' not under $SCRIPTS_ROOT/ — refusing to run"
      return 2
      ;;
  esac

  if [[ ! -f "$script" ]]; then
    fail "issue #$issue_num: script '$script' missing in repo HEAD — leaving issue open"
    return 0
  fi
  if [[ ! -x "$script" ]]; then
    fail "issue #$issue_num: script '$script' not executable — leaving issue open"
    return 0
  fi

  # Earliest gate
  local earliest_epoch
  earliest_epoch=$(iso_to_epoch "${earliest:-}")
  if (( now_epoch < earliest_epoch )); then
    log "issue #$issue_num: earliest=$earliest not yet reached (now=$(date -u +%FT%TZ)) — skipping"
    return 0
  fi

  # Build the env allowlist. Default = nothing. Only vars named in
  # `secrets=` are passed through to the script.
  local -a env_args=("env" "-i" "PATH=$PATH" "HOME=$HOME")
  if [[ -n "${secrets:-}" ]]; then
    IFS=',' read -r -a secret_names <<<"$secrets"
    for name in "${secret_names[@]}"; do
      name="${name// /}"
      [[ -z "$name" ]] && continue
      # Only pass through if the var is set in our environment.
      if [[ -n "${!name+x}" ]]; then
        env_args+=("$name=${!name}")
      else
        fail "issue #$issue_num: required secret '$name' not set in workflow env — leaving issue open"
        return 0
      fi
    done
  fi

  log "issue #$issue_num: running $script"
  local rc=0
  local out
  out=$("${env_args[@]}" "$script" 2>&1) || rc=$?
  log "issue #$issue_num: $script exit=$rc"

  local trimmed_out
  trimmed_out=$(printf '%s' "$out" | tail -c 4000)

  local verdict body_msg action
  case "$rc" in
    0)
      verdict="PASS"
      body_msg="### Sweeper run: PASS ($(date -u +%FT%TZ))
Script: \`$script\` exited 0. Auto-closing per follow-through convention.

<details><summary>Output (last 4 KB)</summary>

\`\`\`
$trimmed_out
\`\`\`

</details>"
      action="close"
      ;;
    1)
      verdict="FAIL"
      body_msg="### Sweeper run: FAIL ($(date -u +%FT%TZ))
Script: \`$script\` exited 1. Leaving issue open; the close criteria are not met.

<details><summary>Output (last 4 KB)</summary>

\`\`\`
$trimmed_out
\`\`\`

</details>"
      action="comment"
      ;;
    *)
      verdict="TRANSIENT"
      body_msg="### Sweeper run: TRANSIENT (exit $rc, $(date -u +%FT%TZ))
Script: \`$script\` exited $rc. Treating as transient; leaving issue open for next sweep.

<details><summary>Output (last 4 KB)</summary>

\`\`\`
$trimmed_out
\`\`\`

</details>"
      action="comment"
      ;;
  esac

  if [[ "$DRY_RUN" == "1" ]]; then
    log "issue #$issue_num: DRY_RUN — would $action with verdict=$verdict"
    return 0
  fi

  printf '%s' "$body_msg" | gh issue comment "$issue_num" --repo "$REPO" --body-file -
  if [[ "$action" == "close" ]]; then
    gh issue close "$issue_num" --repo "$REPO"
  fi

  log "issue #$issue_num: verdict=$verdict action=$action"
}

main() {
  log "sweep start (repo=$REPO dry_run=$DRY_RUN)"

  local issues_json
  issues_json=$(gh issue list --repo "$REPO" --label follow-through --state open --limit 50 --json number,body)
  local count
  count=$(printf '%s' "$issues_json" | jq 'length')
  log "found $count open follow-through issues"

  local i
  for i in $(seq 0 $((count - 1))); do
    local num body
    num=$(printf '%s' "$issues_json" | jq -r ".[$i].number")
    body=$(printf '%s' "$issues_json" | jq -r ".[$i].body")
    run_one "$num" "$body" || fail "issue #$num: run_one returned non-zero (continuing)"
  done

  log "sweep done"
}

main "$@"
