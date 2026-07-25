#!/usr/bin/env bash
# Sweep open `follow-through` issues, parse the soleur:followthrough
# directive in their bodies, and run the referenced verification script
# when the earliest-check timestamp has passed. Close the issue with a
# PASS comment on script exit 0; comment FAIL and leave open on exit 1;
# comment TRANSIENT and leave open on any other exit.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
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

# --- Closed-set (reopen path) bounds, #6698 ---------------------------------
# How far back to look for prematurely-closed follow-throughs. Bounded so the
# closed query stays cheap and the sweeper does not re-litigate ancient history.
CLOSED_LOOKBACK_DAYS="${CLOSED_LOOKBACK_DAYS:-14}"
# Validate before it reaches `date -d`, which accepts natural language ("next
# friday", "-1 year") and would silently produce a nonsense window.
if ! [[ "$CLOSED_LOOKBACK_DAYS" =~ ^[0-9]+$ ]] || (( CLOSED_LOOKBACK_DAYS < 1 )); then
  printf '::error::CLOSED_LOOKBACK_DAYS must be a positive integer (got %q)\n' "$CLOSED_LOOKBACK_DAYS" >&2
  exit 2
fi
# Its OWN limit. Deliberately NOT achieved by widening the open query to
# `--state all`: that shares one 50-item budget between the two sets, so a burst
# of closed issues would silently starve the open set the sweeper's primary job
# depends on.
CLOSED_LIMIT="${CLOSED_LIMIT:-30}"
# Stateless reopen bound — see closed_precheck. After this many sweeper reopens
# the issue needs a human, not another automated reopen.
REOPEN_MAX="${REOPEN_MAX:-3}"

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

# Marker embedded in every sweeper-authored reopen comment. Counting these
# bounds the reopen loop WITHOUT any persistent state — the script is stateless
# and runs its verification under `env -i`, so an in-process counter cannot
# survive between sweeps. GitHub's own comment history is the state.
readonly SWEEPER_REOPEN_MARKER="<!-- soleur:sweeper-reopen -->"
# The PASS block the sweeper writes when it closes an issue itself.
readonly SWEEPER_PASS_HEADING="### Sweeper run: PASS"

# Decide whether a CLOSED follow-through issue is a reopen candidate.
# Returns 0 to proceed, 1 to skip. Runs BEFORE the verification script so a
# skipped issue costs one cheap read instead of a full script execution.
closed_precheck() {
  local issue_num="$1"
  local comments_json rc=0
  # ‼️ stderr is captured SEPARATELY, not folded in with `2>&1`. gh writes
  # routine noise to stderr while exiting 0 (e.g. its own "A new release of gh
  # is available" notice); folding that into the JSON makes every jq below
  # parse-fail. Because run_one is invoked as `run_one … || fail` and this
  # function under `if !`, errexit is suppressed throughout — so an empty
  # `reopens` would satisfy `0 >= REOPEN_MAX` as false and PROCEED, defeating
  # both the cap and the PASS guard simultaneously in a function whose whole
  # contract is to fail closed.
  local err_file
  err_file=$(mktemp -t followthrough-gh-err.XXXXXXXX)
  comments_json=$(gh issue view "$issue_num" --repo "$REPO" --json comments 2>"$err_file") || rc=$?
  rm -f "$err_file"
  if (( rc != 0 )); then
    # FAIL-CLOSED. Without the comment history we can neither bound the reopen
    # loop nor tell our own PASS closure apart from someone else's — reopening
    # blind is how this becomes a daily flapping loop.
    fail "issue #$issue_num: could not read comments (rc=$rc) — skipping closed-set evaluation"
    return 1
  fi
  # Fail closed on unparseable JSON too — same reasoning as a non-zero exit.
  if ! printf '%s' "$comments_json" | jq -e '.comments' >/dev/null 2>&1; then
    fail "issue #$issue_num: comment payload is not parseable JSON — skipping closed-set evaluation"
    return 1
  fi

  # Do not re-litigate a closure the sweeper itself justified. This is
  # EVIDENCE-based, not ACTOR-based: it still catches a premature close by any
  # actor (operator, agent, a `Closes #N` in prose, or the sweeper on a
  # different day), while leaving the sweeper's own PASS alone. Without it,
  # every correctly-closed issue would be re-verified daily for the whole
  # recency window and reopened the moment its condition regressed — one
  # follow-through would silently become a permanent monitor.
  #
  # ‼️ Scan ALL comments, not just `.comments[-1]`. A positional check is
  # defeated by any single trailing comment from anyone — an operator note, the
  # triage bot, a linked-discussion reply — which silently re-arms daily
  # re-verification on exactly the issues humans have touched.
  local sweeper_passes
  sweeper_passes=$(printf '%s' "$comments_json" \
    | jq --arg h "$SWEEPER_PASS_HEADING" '[.comments[] | select(.body | startswith($h))] | length')
  if (( sweeper_passes > 0 )); then
    log "issue #$issue_num: carries the sweeper's own PASS block — not re-litigating"
    return 1
  fi

  local reopens
  reopens=$(printf '%s' "$comments_json" \
    | jq --arg m "$SWEEPER_REOPEN_MARKER" '[.comments[] | select(.body | contains($m))] | length')
  if (( reopens >= REOPEN_MAX )); then
    # ::error:: rather than a bare log: this is the give-up branch. Past the cap
    # the sweeper permanently abandons a still-failing verification, and a plain
    # stdout line in a green workflow run is read by nobody.
    printf '::error::sweeper reopen cap reached for issue #%s (%sx, cap=%s) — verification still fails and no further reopen will be attempted; needs a human\n' \
      "$issue_num" "$reopens" "$REOPEN_MAX"
    return 1
  fi
  return 0
}

run_one() {
  local issue_num="$1"
  local body="$2"
  # "open"  — the close path: PASS closes the issue.
  # "closed" — the reopen path: FAIL reopens it. A prematurely-closed
  #            follow-through is otherwise invisible to the sweeper forever,
  #            because it only ever listed `--state open`.
  local mode="${3:-open}"

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

  # Earliest gate — applies to BOTH sets.
  #
  # ‼️ THE CLOSED SET MUST NOT BYPASS THIS. An earlier draft of #6698 bypassed
  # it, reasoning that a closed follow-through already asserts "verified" so its
  # predicate should be evaluated immediately. That is wrong, because it
  # misreads what exit 1 means to a soak probe. The probes use exit 1 for "still
  # soaking", NOT for "closed prematurely" — e.g.
  # `scripts/followthroughs/workspaces-luks-soak-6604.sh` documents
  # `1 = FAIL (still soaking, ...)` and refuses a day-0 PASS "regardless of the
  # directive earliest=". So bypassing the gate makes every legitimately-closed
  # issue whose soak has not yet elapsed look prematurely closed, and the sweeper
  # reopens it — overriding the operator. Measured 2026-07-19: #6604
  # (earliest=07-25), #6416 (07-22) and #6462 (07-29) were all closed COMPLETED
  # with a future `earliest`, and a bypassing sweep would have reopened all three
  # that night.
  #
  # The bypass was also unnecessary. Its stated motivation was that #6657
  # (closed 07-18, earliest=07-25) would "leave the query window before its own
  # earliest elapsed" — true only for a recency window shorter than the ~7-day
  # gap. `CLOSED_LOOKBACK_DAYS` is 14, so #6657 stays a candidate until 08-01 and
  # is evaluated from 07-25 onward with the gate intact. Keeping the gate costs
  # the reopen path nothing and removes the whole override class.
  local earliest_epoch
  earliest_epoch=$(iso_to_epoch "${earliest:-}")
  if (( now_epoch < earliest_epoch )); then
    log "issue #$issue_num: earliest=$earliest not yet reached (now=$(date -u +%FT%TZ)) — skipping"
    return 0
  fi

  if [[ "$mode" == "closed" ]]; then
    if ! closed_precheck "$issue_num"; then
      return 0
    fi
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
  if [[ "$mode" == "closed" ]]; then
    # ‼️ INVERTED SEMANTICS. On the closed set the only actionable verdict is
    # FAIL: the issue asserts "verified" but its own predicate disagrees, so the
    # closure was premature.
    case "$rc" in
      1)
        verdict="FAIL"
        action="reopen"
        body_msg="### Sweeper reopen: verification FAILED ($(date -u +%FT%TZ))
$SWEEPER_REOPEN_MARKER
This issue was closed, but \`$script\` still exits 1 — the close criteria are **not** met. Reopening so it is not silently lost.

<details><summary>Output (last 4 KB)</summary>

\`\`\`
$trimmed_out
\`\`\`

</details>"
        ;;
      0)
        # FULL no-op — comment included. run_one's open path comments
        # UNCONDITIONALLY before deciding to close; reusing that here would post
        # a fresh "still recovered" comment on every correctly-closed issue,
        # every day, forever. The reopen cap bounds REOPENS, not comments, so
        # this needs its own guard.
        log "issue #$issue_num: closed and verification passes — no action, no comment"
        return 0
        ;;
      *)
        # TRANSIENT on a closed issue: no action AND no comment. A flaky probe
        # must not accrete daily noise on an issue that is already closed.
        log "issue #$issue_num: closed, verification TRANSIENT (exit $rc) — no action, no comment"
        return 0
        ;;
    esac

    if [[ "$DRY_RUN" == "1" ]]; then
      log "issue #$issue_num: DRY_RUN — would $action with verdict=$verdict"
      return 0
    fi

    printf '%s' "$body_msg" | gh issue comment "$issue_num" --repo "$REPO" --body-file -
    # A failed reopen is the ONLY failure surface for this path — surface it as
    # a workflow annotation rather than letting the caller's `|| fail` swallow
    # it into the log.
    if ! gh issue reopen "$issue_num" --repo "$REPO"; then
      printf '::error::sweeper failed to reopen issue #%s (verification exits 1 but the issue stays closed)\n' "$issue_num"
      return 1
    fi
    log "issue #$issue_num: verdict=$verdict action=$action"
    return 0
  fi

  case "$rc" in
    0)
      verdict="PASS"
      body_msg="$SWEEPER_PASS_HEADING ($(date -u +%FT%TZ))
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

  # --- Closed set: the reopen path (#6698) ----------------------------------
  # A follow-through can be closed while its condition is still unrecovered —
  # by the operator, an agent session, or a `Closes #N` that GitHub's keyword
  # parser matched in descriptive PR prose. Before this, the sweeper listed
  # `--state open` ONLY, so any such premature close was permanently invisible
  # and could never be reopened.
  #
  # Single pinned `--search` form: mixing `--search` with `--label`/`--state` is
  # gh-version-sensitive (gh folds them into search qualifiers), so all three
  # qualifiers live inside the search string.
  local closed_since
  closed_since=$(date -u -d "${CLOSED_LOOKBACK_DAYS} days ago" +%F 2>/dev/null || date -u +%F)
  local closed_json closed_rc=0
  closed_json=$(gh issue list --repo "$REPO" --state closed \
    --search "label:follow-through closed:>=${closed_since}" \
    --limit "$CLOSED_LIMIT" --json number,body,stateReason 2>&1) || closed_rc=$?
  if (( closed_rc != 0 )); then
    # ::error:: not a bare log: `fail` only prints to stderr, so a permanently
    # broken reopen path would leave the daily workflow green forever.
    printf '::error::closed-set query failed (rc=%s) — the follow-through reopen path did not run this sweep\n' "$closed_rc"
    fail "closed-set query failed (rc=$closed_rc) — skipping reopen path this sweep"
  else
    local closed_count
    closed_count=$(printf '%s' "$closed_json" | jq 'length')
    log "found $closed_count closed follow-through issue(s) since $closed_since"
    local j
    for j in $(seq 0 $((closed_count - 1))); do
      local cnum cbody creason
      cnum=$(printf '%s' "$closed_json" | jq -r ".[$j].number")
      cbody=$(printf '%s' "$closed_json" | jq -r ".[$j].body")
      creason=$(printf '%s' "$closed_json" | jq -r ".[$j].stateReason // \"\"")
      # NOT_PLANNED is a deliberate wontfix. Reopening it would override a human
      # decision, which is the opposite of what this path is for.
      # Only an explicit COMPLETED closure is a reopen candidate. NOT_PLANNED is
      # a deliberate wontfix, and a NULL reason (issues closed before GitHub
      # introduced close reasons, or via some API paths) is unknown provenance —
      # neither is evidence of a premature close, so both are left alone.
      if [[ "$creason" != "COMPLETED" ]]; then
        log "issue #$cnum: closed as ${creason:-<no-reason>} (not COMPLETED) — leaving closed"
        continue
      fi
      run_one "$cnum" "$cbody" closed || fail "issue #$cnum: closed-set run_one returned non-zero (continuing)"
    done
  fi

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
