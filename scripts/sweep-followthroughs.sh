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
# directive is present. Multiple directives in one body → only the FIRST
# is honored; the parser emits a synthetic `__sweeper_meta__
# multi_directive_count <N>` line so the bash caller can log a warning.
# The `__sweeper_meta__` key shape is a private contract with run_one;
# future directive fields MUST NOT use that name.
#
# Fenced markdown code blocks (lines starting with three backticks, the
# canonical GitHub-flavored markdown form) are skipped wholesale. This
# closes the residual where a directive copy-pasted into a ```html``` fence
# at column 1 would otherwise satisfy the anchored start-range regex.
parse_directive() {
  awk '
    BEGIN { in_dir = 0; seen = 0; closing = 0; fence = 0 }
    /^```/ { fence = !fence; next }
    fence { next }
    /^<!-- *soleur:followthrough/ {
      seen++
      if (seen == 1) in_dir = 1
    }
    # End-of-directive check MUST run BEFORE the in_dir body block, because
    # the body block gsub(/-->/, "") strips the closing marker from $0 in
    # place, which would prevent /-->/ from matching on the same line. Set
    # a flag here, apply it in a post-body block.
    /-->/ && in_dir {
      closing = 1
    }
    in_dir {
      gsub(/^<!-- *soleur:followthrough/, "")
      gsub(/-->/, "")
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
        if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
        if ($i ~ /^secrets=/)  { sub(/^secrets=/, "", $i);  print "secrets "  $i }
      }
    }
    closing { in_dir = 0; closing = 0 }
    END { if (seen > 1) print "__sweeper_meta__ multi_directive_count " seen }
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
    # First-wins, not last-wins: a directive line containing multiple
    # `script=`/`earliest=`/`secrets=` tokens (e.g.,
    # `<!-- soleur:followthrough script=a.sh script=b.sh -->`) emits one
    # KEY VALUE line per matching field in the awk for-loop. Without the
    # `-z` guard the bash loop would take the LAST value, which is the
    # same multi-directive bypass that Gap 2 closed across directives.
    case "$key" in
      script)   [[ -z "${script:-}" ]]   && script="$val" ;;
      earliest) [[ -z "${earliest:-}" ]] && earliest="$val" ;;
      secrets)  [[ -z "${secrets:-}" ]]  && secrets="$val" ;;
      __sweeper_meta__)
        # val shape: "<meta_kind> <args>". Decode whitespace-tolerantly via
        # `read` so a future parser-side reformat does not silently break
        # the consumer; fallthrough log fires for unknown meta_kind so an
        # additive parser change cannot quietly no-op here.
        local meta_kind meta_args
        read -r meta_kind meta_args <<<"$val"
        case "$meta_kind" in
          multi_directive_count)
            log "issue #$issue_num: multi-directive body: $meta_args directives found, honoring first only"
            ;;
          *)
            log "issue #$issue_num: unknown __sweeper_meta__ kind '$meta_kind' (val='$val') — ignoring"
            ;;
        esac
        ;;
    esac
  done < <(printf '%s' "$body" | parse_directive)

  if [[ -z "${script:-}" ]]; then
    log "issue #$issue_num: no directive — skipping"
    # Visibility: aggregate no-directive issues into the end-of-sweep
    # summary. Without this, an issue filed without a directive (per the
    # 2026-05-21 incident where #4244/#4245/#4246 all shipped directive-less)
    # silently never gets evaluated. The summary surfaces the gap so the
    # operator can either backfill the directive or close the issue as
    # wontfix. Path: $NO_DIRECTIVE_FILE if set by main(), else no-op.
    if [[ -n "${NO_DIRECTIVE_FILE:-}" ]]; then
      printf '%s\n' "$issue_num" >> "$NO_DIRECTIVE_FILE"
    fi
    return 0
  fi

  log "issue #$issue_num: directive found (script=$script earliest=${earliest:-now} secrets=${secrets:-none})"

  # Path safety: script MUST canonicalize to a path under
  # scripts/followthroughs/. Use realpath rather than a bare prefix-match —
  # a path that traverses out of the allowlist root via `..` would satisfy
  # a naïve case-glob but is rejected after canonicalization. `-m` accepts
  # non-existent paths (the on-disk check below handles missing scripts
  # with a clearer error). `|| true` guards against realpath failures on
  # exotic input: empty $canon fails the case-glob → REJECT.
  #
  # Symlinks are rejected BEFORE canonicalization: realpath follows
  # symlinks, so an attacker-controlled symlink under scripts/followthroughs/
  # would canonicalize to its target outside the allowlist and get rejected
  # (good) but more importantly, a symlink TARGETING another committed
  # script in the repo (e.g. a privileged terraform-apply wrapper) would
  # have its existence/executability checks pass against the symlink. The
  # cheapest defense is to refuse symlinks under the allowlist root.
  if [[ -L "$script" ]]; then
    fail "issue #$issue_num: script path '$script' is a symlink — refusing to run"
    return 2
  fi
  local canon
  canon=$(realpath -m --relative-to="$PWD" "$script" 2>/dev/null || true)
  # Reject embedded newlines in the canonical path: `realpath -m` happily
  # round-trips a path containing \n, and the case-glob's prefix match
  # would still accept the canonical-form's first line. Defense-in-depth
  # on top of the case-glob.
  if [[ "$canon" == *$'\n'* ]]; then
    fail "issue #$issue_num: script path '$script' contains embedded newline — refusing to run"
    return 2
  fi
  case "$canon" in
    "$SCRIPTS_ROOT"/*) script="$canon" ;;
    *)
      fail "issue #$issue_num: script path '$script' escapes $SCRIPTS_ROOT/ — refusing to run"
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
  #
  # PATH is pinned to the FHS default rather than forwarded from the
  # parent environment: forwarding the workflow runner's PATH (which may
  # be augmented with tool-cache or actions-runner-prefix dirs) defeats
  # the purpose of `env -i`. The verification scripts under
  # scripts/followthroughs/ should not depend on caller-side PATH state.
  local -a env_args=("env" "-i" "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "HOME=$HOME")
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

  # Tmpfile collects issue numbers that lack the soleur:followthrough
  # directive. End-of-sweep summary surfaces them (closes #4244/#4245/#4246
  # class — issues filed without a directive that the sweeper silently
  # never evaluates).
  NO_DIRECTIVE_FILE=$(mktemp -t followthrough-no-directive.XXXXXXXX.txt)
  export NO_DIRECTIVE_FILE
  trap 'rm -f "$NO_DIRECTIVE_FILE"' EXIT

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

  # No-directive summary. If any issues lacked the directive, emit a
  # structured warning section that bubbles to the workflow summary.
  local no_dir_count=0
  if [[ -s "$NO_DIRECTIVE_FILE" ]]; then
    no_dir_count=$(wc -l < "$NO_DIRECTIVE_FILE" | tr -d '[:space:]')
  fi
  if [[ "$no_dir_count" -gt 0 ]]; then
    log "WARN: $no_dir_count open follow-through issue(s) have no soleur:followthrough directive:"
    while IFS= read -r issue_num; do
      log "  - #$issue_num — needs directive or close as wontfix"
    done < "$NO_DIRECTIVE_FILE"
    # Emit to GITHUB_STEP_SUMMARY if running in CI so it appears in the
    # workflow run page without forcing the operator to scroll the log.
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      {
        printf '### ⚠️ Follow-through issues missing directive (%d)\n\n' "$no_dir_count"
        printf 'These issues carry the `follow-through` label but no `<!-- soleur:followthrough ... -->` block. The sweeper cannot evaluate them — they will rot open until manually addressed.\n\n'
        while IFS= read -r issue_num; do
          printf -- '- [#%s](https://github.com/%s/issues/%s)\n' "$issue_num" "$REPO" "$issue_num"
        done < "$NO_DIRECTIVE_FILE"
        printf '\nResolve each by either (a) adding the directive (see `plugins/soleur/skills/ship/SKILL.md` §Phase 7 Step 3.5.A-F), or (b) closing as wontfix with rationale.\n'
      } >> "$GITHUB_STEP_SUMMARY"
    fi
  fi

  log "sweep done (no_directive=$no_dir_count)"
}

# Allow tests to source this script without running main().
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
