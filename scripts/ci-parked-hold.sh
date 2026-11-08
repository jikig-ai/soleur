#!/usr/bin/env bash
# parked-hold: the server-side evaluator behind the `parked-hold` member step of the `secret-guards`
# required umbrella (.github/workflows/secret-scan.yml; #12396, ADR-032 amendment 2026-11-08).
#
# Fails the check while the PR carries the `parked` label ("Reviewed draft held until an approved
# window; do not merge or arm auto-merge"), and fails CLOSED when the label state cannot be read.
# It binds auto-merge, the merge queue and every identity that is subject to the required checks. It
# does NOT bind a bypass actor running `gh pr merge --admin`, and any identity with triage access
# can remove the label (which re-runs this check green): both are stated residuals in the ADR.
#
# Inputs (ALL from the step's env:, never interpolated into the run: block):
#   EVENT_NAME    github.event_name. pull_request and merge_group are evaluated; any other event is a
#                 deliberate no-op (the step condition already skips them; this is defence in depth so
#                 the script can never fail main's push/schedule scans, where there is no PR).
#   PR_NUMBER     github.event.pull_request.number (pull_request events)
#   MG_HEAD_REF   github.event.merge_group.head_ref (merge_group events). The PR number is parsed
#                 from the queue ref with the `mg_arm` regex of scripts/ci-oracle-review.sh.
#   REPO          github.repository
#   GH_TOKEN      github.token (pull-requests read is enough; the umbrella job already holds write)
#   PARKED_HOLD_RETRY_SLEEP  seconds between the two attempts (default 2; the self-test sets 0)
#
# Reads the labels LIVE from the API, never from the event payload: a re-run reuses the original
# payload, so a label added or removed since would be invisible, and `rename-guard` / `allowlist-diff`
# (which do read the payload) are exactly the weakness this avoids.
#
# merge_group semantics (re-read from `mg_arm` in scripts/ci-oracle-review.sh, which is parity-pinned
# to scripts/merge-queue-cla-verify.sh): those arms enumerate every queue entry at or below the
# candidate's position because the candidate commit is cumulative. This check deliberately does NOT
# enumerate. With merge_method SQUASH each queue position runs its OWN merge_group build, and each
# build's `secret-guards` evaluates the PR named by its own head_ref; a lower entry is judged by its
# own build. Residual: a label added to an entry AFTER its build ran is not seen (dequeue per
# knowledge-base/engineering/operations/runbooks/merge-queue-dequeue.md).
#
# Output: one fixed annotation per failure. Label text, response bodies and the ref are never echoed.
# Exit: 0 not parked (or no PR on this event); 1 parked or unreadable; 78 refused under set -x with a
# live credential (#7797).
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] parked-hold: refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

fail() { # fail <fixed message>
  printf '::error::parked-hold: %s\n' "$1"
  exit 1 # GUARD:fail-closed
}

case "${EVENT_NAME:-}" in
  pull_request | merge_group) ;;
  *)
    echo "parked-hold: no pull request on this event; nothing to evaluate"
    exit 0
    ;;
esac

[[ "${REPO:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "REPO is not owner/name"

if [ "$EVENT_NAME" = "pull_request" ]; then
  [[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]] || fail "PR_NUMBER is not a number"
  pr="$PR_NUMBER"
else
  [[ "${MG_HEAD_REF:-}" =~ ^refs/heads/gh-readonly-queue/main/pr-([0-9]+)-[0-9a-f]{40}$ ]] \
    || fail "merge_group head ref does not match the queue ref pattern"
  pr="${BASH_REMATCH[1]}"
fi
pr=$((10#$pr)) # normalise leading zeros so the numeric compare below is exact

sleep_s="${PARKED_HOLD_RETRY_SLEEP:-2}"
[[ "$sleep_s" =~ ^[0-9]+$ ]] || sleep_s=2

# ONE bounded retry (2 attempts) so a single transient API 5xx does not block the queue.
attempt=0
fetched=0
code=""
payload=""
errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT
while [ "$attempt" -lt 2 ]; do
  attempt=$((attempt + 1))
  if payload="$(gh api "repos/${REPO}/pulls/${pr}" 2>"$errfile")"; then
    fetched=1
    break
  fi
  code="$(grep -oE 'HTTP [0-9]{3}' "$errfile" | head -n1 | cut -d' ' -f2)"
  [ "$attempt" -lt 2 ] && sleep "$sleep_s"
done
[ "$fetched" -eq 1 ] || fail "label state unreadable (HTTP ${code:-unknown})"

# A wrong or partial body must never pass as "not parked".
jq -e --argjson pr "$pr" '(.number == $pr) and (.labels | type == "array")' <<<"$payload" >/dev/null 2>&1 \
  || fail "label state unreadable (unexpected response body)"

jq -e '[.labels[] | ((.name // "") | tostring | ascii_downcase)] | any(. == "parked")' <<<"$payload" >/dev/null 2>&1
case "$?" in
  0)
    printf '::error::PR #%s carries parked. Remove the label (maintainers) or keep the PR a draft\n' "$pr"
    exit 1
    ;;
  1)
    printf 'parked-hold: PR #%s does not carry parked\n' "$pr"
    exit 0
    ;;
  *) fail "label state unreadable (label list could not be evaluated)" ;;
esac
