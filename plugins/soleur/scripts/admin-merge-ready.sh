#!/usr/bin/env bash
# admin-merge-ready.sh <PR> <head-sha> [--wait [--timeout SEC]]
# admin-merge-ready.sh --help
#
# The ONLY permitted answer to "may this PR be admin-merged?" (#8500).
#
# WHY THIS EXISTS. An `--admin` merge bypasses the WHOLE `required_status_checks` ruleset
# rule (every required context, not just the up-to-date gate), so nothing server-side stops a
# red, pending or ABSENT merge. #8458 and #8439 were admin-merged that way. The obvious agent
# loop -- `gh pr checks --required` until nothing is pending -- lists only checks that EXIST: the
# aggregate `test` context is created only after every shard finishes, so it was absent (not
# pending) and the loop saw 25 of 26 required contexts green and merged. This script iterates
# the REQUIRED SET, never the present checks, so an uncreated required context reads ABSENT.
#
# HOW IT DECIDES.
#   * Required set: `gh api repos/{owner}/{repo}/rules/branches/<base>` -- the UNION over every
#     `required_status_checks` rule (today two rulesets: CI Required + CLA Required), deduped.
#     Classic branch protection is not consulted: this repo has none (`branches/main/protection`
#     is 404). An empty set is an ERROR, never "nothing required" -- that is the vacuous state.
#   * Every required entry must be pinned to an app (`integration_id`). An unpinned entry could
#     be satisfied by a legacy commit STATUS, which this script does not read; it is refused
#     (exit 3) so the gap fails loud rather than silently.
#   * Check runs: `commits/<sha>/check-runs?filter=all`, paginated, matched by name AND
#     `app.id == integration_id` (a CodeQL-named run from github-actions is not CodeQL).
#   * Latest run per context = max check-run `id`, compared numerically. NOT `started_at`: a
#     queued re-run has `started_at: null` and would sort as the OLDEST, letting a stale
#     success mask a pending re-run. This mirrors GitHub, which uses the latest run per name+app.
#   * Green = completed + success|skipped|neutral. GitHub docs, "About protected branches":
#     "Required status checks must have a `successful`, `skipped`, or `neutral` status before
#     collaborators can make changes to a protected branch." Do not "fix" skipped into a failure.
#   * EXCEPT skipped-after-failure: a job is `skipped` when a `needs:` dependency failed and it
#     lacks `if: always()`. A skipped/neutral required context whose check suite holds a failed
#     (latest-per-name) run is reported FAILED (skipped-after-failure). `--admin` is the only
#     check, so this is stricter than GitHub on purpose.
#   * Untrusted CI: if the PR edits `.github/workflows/` or `.github/actions/`, its own runs
#     could mint a genuine github-actions run under any required name, so it cannot certify
#     itself: UNTRUSTED-CI, not-ready.
#   * The PR must be OPEN and its head must equal <head-sha>, re-checked on every poll (P4);
#     callers then merge with `--match-head-commit <head-sha>`.
#
# KNOWN LIMITS (stated, not silent).
#   (a) A re-run started between this script's read and `gh pr merge` is not seen:
#       `--match-head-commit` pins the head, not the checks. Run the script and the merge back
#       to back with no sleep between (settle-then-admin-merge.md steps 4-5 do).
#   (b) An API-created check run (POST /check-runs) from an in-repo workflow holding
#       `checks: write` could carry any required name (`grep -rn 'checks: write' .github/workflows`).
#   (c) If two workflows ever emit a job with the same required name, the newer run wins, as it
#       does on GitHub. Probed 2026-09-22: no required name spans two check suites.
#
# EXIT CODES (the contract every caller branches on).
#   0  ready      every required context present and green on this head -> merge with
#                 --match-head-commit <sha>
#   1  not-ready  something ABSENT/PENDING/FAILED (--wait: a FAILED is terminal) or UNTRUSTED-CI
#   1  stale      PR not OPEN, or head moved off <sha> -> re-read the SHA and restart
#   1  timeout    --wait budget spent with contexts still ABSENT/PENDING -> never merge
#   2  error      usage
#   3  error      gh/jq missing, any API failure, empty required set, unpinned context
# Every path prints the marker as its LAST stdout line:
#   SOLEUR_ADMIN_MERGE_READY verdict=<ready|not-ready|stale|timeout|error> pr=<N> sha=<sha>
#     base=<branch> required=<n> absent=<json> pending=<json> failed=<json>
# Name arrays are compact JSON because context names contain spaces, parentheses, '#' and ':'.
#
# --wait polls every ADMIN_MERGE_READY_POLL_SECONDS (default 60; test seam, must be ^[0-9]+$).
# The budget is counted in POLLS (ceil(timeout/60)), so a 0-second test poll gives the same
# poll count as production. Emits one WAIT line when the non-green set changes, a HEARTBEAT
# every 5 unchanged polls, and exactly one marker at the end. Host it in the Monitor tool.
set -uo pipefail

readonly MARKER="SOLEUR_ADMIN_MERGE_READY"

usage() {
  cat <<'EOF'
usage: admin-merge-ready.sh <PR> <head-sha> [--wait [--timeout SEC]]
       admin-merge-ready.sh --help

Exits 0 only when every context required by the base branch's rulesets is PRESENT on
<head-sha> and its latest check run concluded success|skipped|neutral.

exit 0 ready | 1 not-ready|stale|timeout | 2 usage error | 3 gh/jq/API/ruleset error

Last stdout line, on every path:
  SOLEUR_ADMIN_MERGE_READY verdict=<ready|not-ready|stale|timeout|error> pr=<N> sha=<sha> base=<branch> required=<n> absent=<json-array> pending=<json-array> failed=<json-array>
EOF
}

PR_OUT="?"; SHA_OUT="?"; BASE="?"
N_REQ=0; J_ABSENT="[]"; J_PENDING="[]"; J_FAILED="[]"

marker() {
  printf '%s verdict=%s pr=%s sha=%s base=%s required=%s absent=%s pending=%s failed=%s\n' \
    "$MARKER" "$1" "$PR_OUT" "$SHA_OUT" "$BASE" "$N_REQ" "$J_ABSENT" "$J_PENDING" "$J_FAILED"
}

usage_error() {
  echo "admin-merge-ready: $1" >&2
  usage >&2
  marker error
  exit 2
}

# ── args ──────────────────────────────────────────────────────────────────────────────────────
if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then usage; exit 0; fi
PR="${1-}"; SHA="${2-}"
[[ "$PR" =~ ^[0-9]+$ ]] || usage_error "PR must be a number (got '${PR}')"
PR_OUT="$PR"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage_error "head-sha must be a full 40-hex SHA (got '${SHA}')"
SHA_OUT="$SHA"
shift 2
WAIT=0; TIMEOUT=3600
while (( $# > 0 )); do
  case "$1" in
    --wait) WAIT=1; shift ;;
    --timeout)
      if ! [[ "${2-}" =~ ^[0-9]+$ ]] || (( 10#$2 == 0 )); then usage_error "--timeout must be a positive integer"; fi
      TIMEOUT=$((10#$2)); shift 2 ;;
    *) usage_error "unknown argument '$1'" ;;
  esac
done
POLL_SECONDS="${ADMIN_MERGE_READY_POLL_SECONDS:-60}"
[[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || usage_error "ADMIN_MERGE_READY_POLL_SECONDS must be ^[0-9]+\$"

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not found on PATH" >&2; marker error; exit 3; }
done

WORK="$(mktemp -d)" || { echo "ERROR: mktemp failed" >&2; marker error; exit 3; }
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM HUP

# ── one readiness read ───────────────────────────────────────────────────────────────────────
# Sets LINES (newline-joined non-green lines), N_REQ, J_ABSENT/J_PENDING/J_FAILED, MSG.
# Returns 0 ready | 1 not-ready | 10 stale | 3 error.
check_once() {
  LINES=""; MSG=""; N_REQ=0; J_ABSENT="[]"; J_PENDING="[]"; J_FAILED="[]"
  rm -f "$WORK"/*.json
  local state head enc

  if ! gh pr view "$PR" --json state,headRefOid,baseRefName > "$WORK/pr.json"; then
    MSG="ERROR: gh pr view $PR failed"; return 3
  fi
  state=$(jq -r '.state // ""' "$WORK/pr.json") || { MSG="ERROR: unparseable gh pr view output"; return 3; }
  head=$(jq -r '.headRefOid // ""' "$WORK/pr.json")
  BASE=$(jq -r '.baseRefName // ""' "$WORK/pr.json")
  [[ -n "$BASE" && "$BASE" != *[[:space:]]* ]] || { BASE="?"; MSG="ERROR: PR base branch unreadable"; return 3; }
  if [[ "$state" != "OPEN" ]]; then MSG="NOT-OPEN: PR is $state"; return 10; fi
  if [[ "$head" != "$SHA" ]]; then MSG="STALE: head is $head, not $SHA"; return 10; fi

  if ! gh api --paginate --slurp "repos/{owner}/{repo}/pulls/$PR/files?per_page=100" > "$WORK/files.json"; then
    MSG="ERROR: reading PR files failed"; return 3
  fi
  local ci
  ci=$(jq -r '[.[][] | .filename | select(test("^\\.github/(workflows|actions)/"))] | join(" ")' "$WORK/files.json") \
    || { MSG="ERROR: unparseable PR files"; return 3; }
  if [[ -n "$ci" ]]; then
    MSG="UNTRUSTED-CI: this PR edits workflow definitions ($ci), so its own check runs cannot certify it"
    return 1
  fi

  enc=$(jq -rn --arg b "$BASE" '$b|@uri')
  if ! gh api --paginate --slurp "repos/{owner}/{repo}/rules/branches/$enc" > "$WORK/rules.json"; then
    MSG="ERROR: reading the ruleset required set failed"; return 3
  fi
  if ! gh api --paginate --slurp "repos/{owner}/{repo}/commits/$SHA/check-runs?per_page=100&filter=all" > "$WORK/runs.json"; then
    MSG="ERROR: reading check runs failed"; return 3
  fi

  local out
  out=$(jq -c --slurpfile rules "$WORK/rules.json" '
    ($rules[0] | add // []
      | [.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?]
      | reduce .[] as $e ([]; if any(.[]; .context == $e.context and .integration_id == $e.integration_id)
                              then . else . + [$e] end)) as $req
    | [.[] | .check_runs[]?] as $runs
    | if ($req | length) == 0 then {error: "ERROR: required set unreadable or empty"}
      elif any($req[]; .integration_id == null) then
        {error: ("ERROR: unpinned required context " + ([$req[] | select(.integration_id == null) | .context] | tojson) + " unsupported")}
      else
        # Latest run per (name, app, suite) that concluded non-green -> the suites a skipped
        # required context cannot be trusted in.
        ( $runs | group_by([.name, .app.id, .check_suite.id]) | map(max_by(.id | tonumber))
          | map(select(.status == "completed"
                       and ((.conclusion // "") as $c | ["success","skipped","neutral"] | index($c) | not)))
          | map(.check_suite.id) | map(select(. != null)) | unique ) as $badsuites
        | [ $req[] as $q
            | [ $runs[] | select(.name == $q.context and .app.id == $q.integration_id) ] as $c
            | if ($c | length) == 0 then {k: "ABSENT", n: $q.context}
              else ($c | max_by(.id | tonumber)) as $l
                | if $l.status == "completed" then
                    if $l.conclusion == "success" then {k: "GREEN", n: $q.context}
                    elif ($l.conclusion == "skipped" or $l.conclusion == "neutral") then
                      if ($l.check_suite.id != null and any($badsuites[]; . == $l.check_suite.id))
                      then {k: "FAILED", n: $q.context, d: "skipped-after-failure"}
                      else {k: "GREEN", n: $q.context} end
                    else {k: "FAILED", n: $q.context, d: ($l.conclusion // "null")} end
                  elif (["queued","in_progress","waiting","requested","pending"] | index($l.status)) then
                    {k: "PENDING", n: $q.context, d: $l.status}
                  else {k: "FAILED", n: $q.context, d: ("unknown status " + ($l.status | tostring))} end
              end ] as $v
        | { req: ($req | length),
            absent:  [$v[] | select(.k == "ABSENT")  | .n],
            pending: [$v[] | select(.k == "PENDING") | .n],
            failed:  [$v[] | select(.k == "FAILED")  | .n],
            lines:   [$v[] | select(.k != "GREEN")
                      | if .k == "ABSENT" then "ABSENT  \(.n)"
                        elif .k == "PENDING" then "PENDING \(.n) (\(.d))"
                        else "FAILED  \(.n) (\(.d))" end] }
      end' "$WORK/runs.json") || { MSG="ERROR: classifying check runs failed (unparseable API output)"; return 3; }

  local err
  err=$(jq -r '.error // ""' <<<"$out")
  if [[ -n "$err" ]]; then MSG="$err"; return 3; fi
  N_REQ=$(jq -r '.req' <<<"$out")
  J_ABSENT=$(jq -c '.absent' <<<"$out")
  J_PENDING=$(jq -c '.pending' <<<"$out")
  J_FAILED=$(jq -c '.failed' <<<"$out")
  LINES=$(jq -r '.lines[]' <<<"$out")
  [[ -z "$LINES" ]] && return 0
  return 1
}

finish() { # <rc> <verdict>
  if [[ -n "$MSG" ]]; then
    if [[ "$1" == 3 ]]; then printf '%s\n' "$MSG" >&2; else printf '%s\n' "$MSG"; fi
  fi
  [[ -n "$LINES" ]] && printf '%s\n' "$LINES"
  marker "$2"
  exit "$1"
}

# ── single check ─────────────────────────────────────────────────────────────────────────────
if (( WAIT == 0 )); then
  check_once; rc=$?
  case "$rc" in
    0) finish 0 ready ;;
    1) finish 1 not-ready ;;
    10) finish 1 stale ;;
    *) finish 3 error ;;
  esac
fi

# ── --wait ───────────────────────────────────────────────────────────────────────────────────
MAX_POLLS=$(( (TIMEOUT + 59) / 60 ))
prev=""
for (( poll = 1; poll <= MAX_POLLS; poll++ )); do
  check_once; rc=$?
  case "$rc" in
    0) finish 0 ready ;;
    10) finish 1 stale ;;
    3) finish 3 error ;;
  esac
  # rc 1: a FAILED context or UNTRUSTED-CI is terminal -- no point waiting.
  if [[ "$J_FAILED" != "[]" || "$MSG" == UNTRUSTED-CI* ]]; then finish 1 not-ready; fi
  if [[ "$LINES" != "$prev" ]]; then
    printf 'WAIT poll=%d/%d absent=%s pending=%s\n' "$poll" "$MAX_POLLS" "$J_ABSENT" "$J_PENDING"
    prev="$LINES"
  else
    (( poll % 5 == 0 )) && printf 'HEARTBEAT poll=%d/%d still waiting absent=%s pending=%s\n' \
      "$poll" "$MAX_POLLS" "$J_ABSENT" "$J_PENDING"
  fi
  (( poll < MAX_POLLS )) && sleep "$POLL_SECONDS"
done
MSG="TIMEOUT: $MAX_POLLS polls spent with required contexts still absent or pending"
finish 1 timeout
