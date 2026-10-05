#!/usr/bin/env bash
# admin-merge-ready.sh <PR> <head-sha> [--base BRANCH] [--wait [--timeout SEC]]
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
#   * The PR must be OPEN, its head must equal <head-sha>, and its base must equal --base
#     (default `main`), re-checked on every poll. Callers merge with --match-head-commit.
#   * Required set: `gh api repos/{owner}/{repo}/rules/branches/<base>` -- the UNION over every
#     `required_status_checks` rule (today two rulesets: CI Required + CLA Required), deduped.
#     An empty set is an ERROR, never "nothing required" -- that is the vacuous state. A rule
#     type this script does not evaluate (e.g. `workflows`, `code_scanning`, `pull_request`,
#     `required_deployments`) is also an ERROR: `--admin` bypasses it too, so ignoring it would
#     be a silent pass. `merge_queue` (adopted #9454) is a KNOWN type that adds NO required
#     context: it only re-runs the required set on a `merge_group` temp ref, so the required
#     contexts it gates are exactly the ones read above. `--admin` skips the queue the same way it
#     skips the required-status-checks rule (bypass_actors, mode pull_request; the adoption canary
#     verifies it), and the readiness decision below is unchanged. Every OTHER unlisted type
#     still errors.
#   * Every required entry must be pinned to an app (`integration_id`). An unpinned entry could
#     be satisfied by a legacy commit STATUS, which this script does not read; it is refused.
#   * Check runs: `commits/<sha>/check-runs?filter=all`, paginated, restricted to
#     `head_sha == <sha>`, matched by name AND `app.id == integration_id` (a run named like a
#     context but posted by a different app, e.g. a github-actions run named for a GHAS-bound
#     context, does not satisfy it).
#   * Latest run per context = max check-run `id`, compared numerically. NOT `started_at`: a
#     queued re-run has `started_at: null` and would sort as the OLDEST, letting a stale
#     success mask a pending re-run. This mirrors GitHub, which uses the latest run per name+app.
#   * Green = completed + success|skipped|neutral. GitHub docs, "About protected branches":
#     "Required status checks must have a `successful`, `skipped`, or `neutral` status before
#     collaborators can make changes to a protected branch." Do not "fix" skipped into a failure.
#   * EXCEPT a skipped/neutral required context is only as good as its check suite: GitHub marks a
#     job skipped when a `needs:` dependency failed and it lacks `if: always()`. If any other run
#     in the same check suite (latest per name+app) concluded non-green, the context is FAILED
#     (skipped-after-failure); if any is still running (a dependency being re-run), it is PENDING
#     (skipped-while-suite-running). `--admin` is the only check, so this is stricter than
#     GitHub on purpose: an unrelated failed job in the same workflow run also blocks.
#   * Untrusted CI: if the PR edits `.github/workflows/` or `.github/actions/` (current or
#     previous path of any file), its own runs could mint a genuine github-actions run under any
#     required name, so it cannot certify itself: UNTRUSTED-CI, not-ready. Such a PR has no
#     agent admin-merge path; the operator merges it by hand. The file list must be complete
#     (its length must equal the PR's `changedFiles`, and the API caps at 3000), else ERROR.
#   * Ready is decided POSITIVELY: every required context must be counted green. "No non-green
#     line was printed" is not readiness -- an empty or unparseable API body would satisfy it.
#
# KNOWN LIMITS (stated, not silent).
#   (a) A re-run started between this script's read and `gh pr merge` is not seen:
#       `--match-head-commit` pins the head, not the checks. settle-then-admin-merge.md's merge
#       block re-runs this script immediately before every merge attempt.
#   (b) A check run created through the API (POST /check-runs) by any workflow token holding
#       `checks: write` carries app 15368 and any name it likes -- including a workflow pushed to
#       a side branch by an actor with write access. GitHub's own server-side check has the same
#       weakness; UNTRUSTED-CI covers only workflows this PR itself edits.
#   (c) If two workflows ever emit a job with the same required name, the newer run wins, as it
#       does on GitHub. Probed 2026-09-22: no required name spans two check suites.
#   (d) Classic branch protection is not read; this repo has none (`branches/main/protection`
#       is 404) and its required checks live in rulesets (infra/github/*.tf).
#
# --green-sha <prior-sha> (was-green carryover).
#   For a PR that is BEHIND after a green head: the operator authorizes --admin, the branch is
#   updated (gh pr update-branch or equivalent), and the NEW head's checks have not settled.
#   The certification is carried from <prior-sha> to <sha> only when the move between them is
#   provably contentless:
#     * <sha> is a 2-parent commit with .commit.verification.verified == true. Only GitHub can
#       produce such a commit (update-branch / merge-upstream / web merge); a server-side merge
#       cannot smuggle authored edits -- it fails on conflict instead of producing one.
#     * parents[0] == <prior-sha>: the first parent is the head that was green.
#     * compare(parents[1]...<base>) is ahead|identical: the second parent is an ancestor-or-
#       equal of the base tip, so every byte the merge added came from <base>.
#   Any failure of those three is not-ready (reason=green-carryover-*), NOT an error: the
#   caller falls back to waiting for the new head's own checks. When the proof holds, the
#   required-check gate runs against <prior-sha>'s check runs (which still exist -- check runs
#   are keyed to the commit, not the branch) and the merge itself still uses
#   --match-head-commit <sha>. UNTRUSTED-CI still refuses first: a workflow-editing PR cannot
#   self-certify on ANY sha.
#
# --allow-local-merge (requires --green-sha; #9401).
#   A SECOND carryover arm for a head that is NOT GitHub-signed -- a hand-made
#   `git merge origin/<base>` push, which arrives unsigned (carryover-unverified under the
#   arm above). (The #9401 disjoint-delta skip needs NO carryover: it leaves the green head
#   untouched, so a plain invocation grades it directly; and a hook-produced sync merge can
#   never satisfy this arm -- its delta overlaps the PR's files by construction.) The
#   signature is replaced by
#   a mechanical proof that the merge added nothing but base-side docs content:
#     * still a 2-parent commit with parents[0] == <green-sha> -- a non-merge or a merge of a
#       different head is refused as carryover-not-merge / carryover-first-parent, flag or not;
#     * parents[1] is an ancestor-or-equal of <base> (same compare as the verified arm);
#     * compare(<green-sha>...<sha>)'s file list EQUALS
#       compare(<green-sha>...parents[1])'s as a set of (filename, status, previous_filename,
#       patch) tuples -- a merge that resolved a conflict or authored an edit diverges from
#       the base-side patch, a file it added beyond the base delta is smuggled, and a file it
#       DROPPED (a subset-only check would certify a merge that reverts base content -- e.g.
#       parents [G, tip] with G's tree) fails the equality;
#     * every such file sits on the docs surface (knowledge-base/, docs/,
#       plugins/soleur/skills/, or *.md) -- base-side CODE carried by an unsigned merge is not
#       certifiable by a gate that cannot replay it;
#     * none of them appear in the PR's own file list -- an overlap means merge-time
#       resolution touched content the PR owns.
#   Success grades <green-sha>'s contexts and reports reason=carryover-local-docs. Refusals
#   are not-ready (carryover-local-not-clean / -nondocs / -overlap), never errors; a truncated
#   (>=300-entry) or unparseable compare body is an error, like every other unreadable input.
#
# EXIT CODES (the contract every caller branches on).
#   0  ready      every required context present and green on this head -> merge with
#                 --match-head-commit <sha>
#   1  not-ready  something ABSENT/PENDING/FAILED (--wait: a FAILED is terminal), UNTRUSTED-CI,
#                 base mismatch, or --wait timeout (verdict=timeout) -> stop, never merge
#   2  error      usage
#   3  error      gh/jq missing, any API failure or unparseable body, empty required set,
#                 unpinned context, unsupported rule type, incomplete file list
#   4  stale      PR not OPEN, or head moved off <sha> -> re-read the SHA and restart
#   130           interrupted (signal); marker verdict=error
# Every path except --help prints the marker as its LAST stdout line:
#   SOLEUR_ADMIN_MERGE_READY verdict=<ready|not-ready|stale|timeout|error> pr=<N> sha=<sha>
#     base=<branch> reason=<token> required=<n> absent=<json> pending=<json> failed=<json>
# Name arrays are compact JSON because context names contain spaces, parentheses, '#' and ':'.
# PR-controlled strings (file paths) are never printed.
#
# --wait polls every ADMIN_MERGE_READY_POLL_SECONDS (default 60; test seam, must be ^[0-9]+$).
# The budget is counted in 60-second POLLS (ceil(timeout/60)), so a 0-second test poll gives the
# same poll count as production. Emits one WAIT line when the non-green set changes, a HEARTBEAT
# every 5 unchanged polls, and exactly one marker at the end. Host it in the Monitor tool.
set -uo pipefail

readonly MARKER="SOLEUR_ADMIN_MERGE_READY"

usage() {
  cat <<'EOF'
usage: admin-merge-ready.sh <PR> <head-sha> [--base BRANCH] [--wait [--timeout SEC]]
       admin-merge-ready.sh <PR> <head-sha> --green-sha <prior-sha> [--allow-local-merge] [--base BRANCH]
       admin-merge-ready.sh --help

Exits 0 only when every context required by the base branch's rulesets is PRESENT on
<head-sha> and its latest check run concluded success|skipped|neutral.
With --green-sha the gate runs against <prior-sha> instead: valid only when <head-sha>
is GitHub's own verified 2-parent merge of <prior-sha> and an ancestor-or-equal of the
base tip (was-green carryover; see the header). With --allow-local-merge an unsigned
local merge is also certified, but only when the delta it added over <prior-sha> is a
byte-identical replay of the base-side delta, docs-only, and disjoint from the PR's
own file list.

exit 0 ready | 1 not-ready|timeout | 2 usage error | 3 gh/jq/API/ruleset error | 4 stale (head moved / PR not open)

Last stdout line, on every path except --help:
  SOLEUR_ADMIN_MERGE_READY verdict=<ready|not-ready|stale|timeout|error> pr=<N> sha=<sha> base=<branch> reason=<token> required=<n> absent=<json-array> pending=<json-array> failed=<json-array>
EOF
}

PR_OUT="?"; SHA_OUT="?"; BASE="?"; REASON="none"
N_REQ=0; J_ABSENT="[]"; J_PENDING="[]"; J_FAILED="[]"

marker() {
  printf '%s verdict=%s pr=%s sha=%s base=%s reason=%s required=%s absent=%s pending=%s failed=%s\n' \
    "$MARKER" "$1" "$PR_OUT" "$SHA_OUT" "$BASE" "$REASON" "$N_REQ" "$J_ABSENT" "$J_PENDING" "$J_FAILED"
}

usage_error() {
  echo "admin-merge-ready: $1" >&2
  usage >&2
  REASON=usage
  marker error
  exit 2
}

# ── args ──────────────────────────────────────────────────────────────────────────────────────
if [[ "${1-}" == "--help" || "${1-}" == "-h" ]]; then usage; exit 0; fi
PR="${1-}"; SHA="${2-}"
[[ "$PR" =~ ^[0-9]+$ ]] || usage_error "PR must be a number"
PR_OUT="$PR"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || usage_error "head-sha must be a full 40-hex SHA"
SHA_OUT="$SHA"
shift 2
WAIT=0; TIMEOUT=3600; WANT_BASE="main"; GREEN_SHA=""; ALLOW_LOCAL=0
while (( $# > 0 )); do
  case "$1" in
    --wait) WAIT=1; shift ;;
    --timeout)
      if ! [[ "${2-}" =~ ^[0-9]+$ ]] || (( 10#$2 == 0 )); then usage_error "--timeout must be a positive integer"; fi
      TIMEOUT=$((10#$2)); shift 2 ;;
    --base)
      if ! [[ "${2-}" =~ ^[A-Za-z0-9._/-]+$ ]]; then usage_error "--base must be a branch name"; fi
      WANT_BASE="$2"; shift 2 ;;
    --green-sha)
      if ! [[ "${2-}" =~ ^[0-9a-f]{40}$ ]]; then usage_error "--green-sha must be a full 40-hex SHA"; fi
      GREEN_SHA="$2"; shift 2 ;;
    --allow-local-merge) ALLOW_LOCAL=1; shift ;;
    *) usage_error "unknown argument" ;;
  esac
done
[[ -z "$GREEN_SHA" || "$GREEN_SHA" != "$SHA" ]] \
  || usage_error "--green-sha equals <head-sha> -- plain invocation already covers it"
[[ "$ALLOW_LOCAL" != "1" || -n "$GREEN_SHA" ]] \
  || usage_error "--allow-local-merge requires --green-sha"
POLL_SECONDS="${ADMIN_MERGE_READY_POLL_SECONDS:-60}"
[[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || usage_error "ADMIN_MERGE_READY_POLL_SECONDS must be ^[0-9]+\$"

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not found on PATH" >&2; REASON="missing-tool"; marker error; exit 3; }
done

WORK="$(mktemp -d)" || { echo "ERROR: mktemp failed" >&2; REASON=mktemp; marker error; exit 3; }
trap 'rm -rf "$WORK"' EXIT
trap 'REASON=interrupted; marker error; exit 130' INT TERM HUP

# ── one readiness read ───────────────────────────────────────────────────────────────────────
# Sets LINES (newline-joined non-green lines), N_REQ, J_ABSENT/J_PENDING/J_FAILED, MSG, REASON.
# Returns 0 ready | 1 not-ready | 4 stale | 3 error.
fail3() { MSG="ERROR: $1"; REASON="$2"; return 3; }

check_once() {
  LINES=""; MSG=""; REASON="none"; N_REQ=0; J_ABSENT="[]"; J_PENDING="[]"; J_FAILED="[]"
  rm -f "$WORK"/*.json
  local state head changed enc

  gh pr view "$PR" --json state,headRefOid,baseRefName,changedFiles > "$WORK/pr.json" \
    || { fail3 "gh pr view $PR failed" api-error; return; }
  jq -e 'type == "object" and (.state|type) == "string" and (.headRefOid|type) == "string"
         and (.baseRefName|type) == "string" and (.changedFiles|type) == "number"' "$WORK/pr.json" >/dev/null 2>&1 \
    || { fail3 "unparseable gh pr view output" api-error; return; }
  state=$(jq -r '.state' "$WORK/pr.json")
  head=$(jq -r '.headRefOid' "$WORK/pr.json")
  changed=$(jq -r '.changedFiles' "$WORK/pr.json")
  BASE=$(jq -r '.baseRefName' "$WORK/pr.json")
  [[ "$BASE" =~ ^[A-Za-z0-9._/-]+$ ]] || { BASE="?"; fail3 "PR base branch unreadable" api-error; return; }
  if [[ "$state" != "OPEN" ]]; then MSG="NOT-OPEN: PR is not open"; REASON="not-open"; return 4; fi
  if [[ "$head" != "$SHA" ]]; then MSG="STALE: the PR head moved off $SHA"; REASON="head-moved"; return 4; fi
  if [[ "$BASE" != "$WANT_BASE" ]]; then
    MSG="BASE-MISMATCH: the PR targets $BASE, not $WANT_BASE"; REASON="base-mismatch"; return 1
  fi

  gh api --paginate --slurp "repos/{owner}/{repo}/pulls/$PR/files?per_page=100" > "$WORK/files.json" \
    || { fail3 "reading PR files failed" api-error; return; }
  local nfiles nci
  nfiles=$(jq -e 'if type == "array" and all(.[]; type == "array") then [.[][]] | length else error("shape") end' \
    "$WORK/files.json" 2>/dev/null) || { fail3 "unparseable PR file list" api-error; return; }
  if (( changed >= 3000 || nfiles != changed )); then
    fail3 "PR file list incomplete ($nfiles listed, $changed changed; the API caps at 3000)" incomplete-files; return
  fi
  nci=$(jq -r '[.[][] | [.filename, (.previous_filename // "")][]
               | select(test("^\\.github/(workflows|actions)/"))] | length' "$WORK/files.json") \
    || { fail3 "unparseable PR file list" api-error; return; }
  if (( nci > 0 )); then
    MSG="UNTRUSTED-CI: this PR edits $nci workflow-definition path(s) under .github/, so its own check runs cannot certify it"
    REASON="untrusted-ci"; return 1
  fi

  # --green-sha carryover: prove <sha> is GitHub's own contentless merge of the certified
  # <green-sha> and the base branch, then grade <green-sha>'s check runs. Verified merges are
  # server-side only (GitHub signs them; a server merge fails on conflict rather than
  # absorbing edits), so verified+2-parents+parents[0]==green+parents[1] an ancestor-or-equal
  # of <base> means the delta is exactly base content.
  CHECK_SHA="$SHA"
  if [[ -n "$GREEN_SHA" ]]; then
    gh api "repos/{owner}/{repo}/commits/$SHA" > "$WORK/head.json" \
      || { fail3 "reading head commit failed" api-error; return; }
    local carry p1 cstatus
    carry=$(jq -r --arg green "$GREEN_SHA" '
      (.commit.verification.verified // false) as $v
      | (.parents // []) as $p
      | if ($p | length) != 2 then "carryover-not-merge"
        elif $p[0].sha != $green then "carryover-first-parent"
        elif $v != true then "carryover-unverified"
        else "ok " + $p[1].sha end' "$WORK/head.json" 2>/dev/null) \
      || { fail3 "unparseable head commit" api-error; return; }
    # Only carryover-unverified is eligible for the local-merge arm: a head that
    # is not a merge, or whose first parent is not <green-sha>, is the wrong
    # SHAPE for carryover and refused the same with or without the flag.
    if [[ "$carry" == ok\ * ]]; then
      p1="${carry#ok }"
    elif [[ "$carry" == "carryover-unverified" && "$ALLOW_LOCAL" == "1" ]]; then
      p1=$(jq -r '.parents[1].sha // ""' "$WORK/head.json" 2>/dev/null) || p1=""
      [[ "$p1" =~ ^[0-9a-f]{40}$ ]] || { fail3 "unparseable head commit" api-error; return; }
    else
      MSG="GREEN-CARRYOVER refused: head $SHA is not a verified GitHub merge of $GREEN_SHA ($carry)"
      REASON="$carry"; return 1
    fi
    gh api "repos/{owner}/{repo}/compare/$p1...$BASE" > "$WORK/compare.json" \
      || { fail3 "compare of merged parent against $BASE failed" api-error; return; }
    cstatus=$(jq -r '.status // ""' "$WORK/compare.json" 2>/dev/null) \
      || { fail3 "unparseable compare response" api-error; return; }
    if [[ "$cstatus" != "ahead" && "$cstatus" != "identical" ]]; then
      MSG="GREEN-CARRYOVER refused: merged parent $p1 is not an ancestor-or-equal of $BASE (status=$cstatus)"
      REASON="carryover-not-base"; return 1
    fi
    if [[ "$carry" == ok\ * ]]; then
      CHECK_SHA="$GREEN_SHA"
      MSG="GREEN-CARRYOVER: head $SHA is a verified merge of $GREEN_SHA and $BASE@$p1; grading $GREEN_SHA's required contexts"
    else
      # --allow-local-merge arm (#9401): the signature is replaced by a diff
      # proof -- every file the merge added over <green-sha> must be a byte-
      # identical replay of the base-side delta, docs-only, and disjoint from
      # the PR's own file list.
      gh api "repos/{owner}/{repo}/compare/$GREEN_SHA...$SHA" > "$WORK/cmp_added.json" \
        || { fail3 "compare of the merge's added delta failed" api-error; return; }
      gh api "repos/{owner}/{repo}/compare/$GREEN_SHA...$p1" > "$WORK/cmp_base.json" \
        || { fail3 "compare of the merged base tip failed" api-error; return; }
      local lcl
      # One jq, one error path: clean-replay, docs-only and PR-disjointness are
      # a single predicate so a residual jq failure can never half-evaluate.
      lcl=$(jq -rn --slurpfile added "$WORK/cmp_added.json" --slurpfile base "$WORK/cmp_base.json" \
                  --slurpfile prf "$WORK/files.json" '
        # docs surface: sibling enumeration of the zero-conflict-surface
        # classifier in ship/references/settle-then-admin-merge.md — different
        # subject (merged delta vs the PR file list) but same surface; a move
        # of the docs roots must touch both. NO apostrophes in jq comments —
        # this program is single-quoted.
        def docs: .filename | test("^(knowledge-base/|docs/|plugins/soleur/skills/)") or test("\\.md$");
        ($added[0].files // null) as $af | ($base[0].files // null) as $bf
        | ([$prf[0][][] | .filename, (.previous_filename // empty)] | unique) as $pf
        | if $af == null or $bf == null then "error:unparseable"
          # The compare API truncates files[] at 300 entries (docs.github.com
          # REST compare commits) — at exactly 300 a complete list is
          # indistinguishable from a truncated one, so fail closed.
          elif ($af | length) >= 300 or ($bf | length) >= 300 then "error:incomplete"
          # Bijection, not subset: a merge whose tree DROPPED base-side content
          # (empty or partial $af) must not certify -- the admin merge would
          # revert main. The tuple includes previous_filename so a rename source
          # is bound, and every patch must be a real string.
          elif any($af[] + $bf[]; (.patch | type) != "string")
               or ([$af[] | [.filename, .status, (.previous_filename // ""), .patch]] | sort)
                  != ([$bf[] | [.filename, .status, (.previous_filename // ""), .patch]] | sort)
          then "not-clean"
          elif any($af[]; docs | not) then "nondocs"
          elif any($af[]; [.filename, (.previous_filename // empty)]
                          | .[] | . as $f | ($pf | index($f)) != null) then "overlap"
          else "ok" end' 2>/dev/null) || { fail3 "unparseable compare response" api-error; return; }
      if [[ "$lcl" == error:* ]]; then
        fail3 "merge-delta compare is unparseable or truncated (${lcl#error:})" incomplete-files; return
      fi
      if [[ "$lcl" != "ok" ]]; then
        MSG="GREEN-CARRYOVER refused: the local merge's added delta is not a clean docs-only replay of the base side, disjoint from the PR's files ($lcl)"
        REASON="carryover-local-$lcl"; return 1
      fi
      CHECK_SHA="$GREEN_SHA"
      REASON="carryover-local-docs"
      MSG="GREEN-CARRYOVER: head $SHA is a clean local merge of $GREEN_SHA and $BASE@$p1 (docs-only delta, disjoint from the PR's files; --allow-local-merge); grading $GREEN_SHA's required contexts"
    fi
  fi

  enc=$(jq -rn --arg b "$BASE" '$b|@uri')
  gh api --paginate --slurp "repos/{owner}/{repo}/rules/branches/$enc" > "$WORK/rules.json" \
    || { fail3 "reading the ruleset required set failed" api-error; return; }
  gh api --paginate --slurp "repos/{owner}/{repo}/commits/$CHECK_SHA/check-runs?per_page=100&filter=all" > "$WORK/runs.json" \
    || { fail3 "reading check runs failed" api-error; return; }
  jq -e 'type == "array" and all(.[]; type == "array")' "$WORK/rules.json" >/dev/null 2>&1 \
    || { fail3 "unparseable ruleset response" api-error; return; }
  jq -e 'type == "array" and all(.[]; type == "object" and (.check_runs|type) == "array")' "$WORK/runs.json" >/dev/null 2>&1 \
    || { fail3 "unparseable check-runs response" api-error; return; }

  local out
  out=$(jq -c --slurpfile rules "$WORK/rules.json" --arg sha "$CHECK_SHA" '
    ["deletion","non_fast_forward","creation","update","required_linear_history",
     "required_signatures","required_status_checks","merge_queue"] as $known
    | ($rules[0] | add // []) as $all
    | ([$all[] | .type | select(. as $t | $known | index($t) | not)] | unique) as $unknown
    | ([$all[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?]
       | reduce .[] as $e ([]; if any(.[]; .context == $e.context and .integration_id == $e.integration_id)
                               then . else . + [$e] end)) as $req
    | [.[] | .check_runs[] | select(.head_sha == $sha)] as $runs
    | if ($unknown | length) > 0 then {error: ("unsupported ruleset rule type(s) " + ($unknown | tojson)), reason: "unsupported-rule"}
      elif ($req | length) == 0 then {error: "required set unreadable or empty", reason: "empty-required"}
      elif any($req[]; .integration_id == null) then
        {error: ("unpinned required context(s) " + ([$req[] | select(.integration_id == null) | .context] | tojson) + " unsupported"), reason: "unpinned"}
      else
        # Latest run per (name, app, suite): the state of every job in a check suite.
        ( $runs | group_by([.name, .app.id, .check_suite.id]) | map(max_by(.id | tonumber)) ) as $latest
        | [ $req[] as $q
            | [ $runs[] | select(.name == $q.context and .app.id == $q.integration_id) ] as $c
            | if ($c | length) == 0 then {k: "ABSENT", n: $q.context}
              else ($c | max_by(.id | tonumber)) as $l
                | if $l.status == "completed" then
                    if $l.conclusion == "success" then {k: "GREEN", n: $q.context}
                    elif ($l.conclusion == "skipped" or $l.conclusion == "neutral") then
                      ( [ $latest[] | select(.check_suite.id != null and .check_suite.id == $l.check_suite.id
                                             and .id != $l.id) ] ) as $sib
                      | if $l.check_suite.id == null then {k: "FAILED", n: $q.context, d: ($l.conclusion + " without a check suite")}
                        elif any($sib[]; .status == "completed"
                                 and ((.conclusion // "") as $x | ["success","skipped","neutral"] | index($x) | not))
                        then {k: "FAILED", n: $q.context, d: ($l.conclusion + "-after-failure")}
                        elif any($sib[]; .status != "completed")
                        then {k: "PENDING", n: $q.context, d: ($l.conclusion + "-while-suite-running")}
                        else {k: "GREEN", n: $q.context} end
                    else {k: "FAILED", n: $q.context, d: ($l.conclusion // "null")} end
                  elif (["queued","in_progress","waiting","requested","pending"] | index($l.status)) then
                    {k: "PENDING", n: $q.context, d: $l.status}
                  else {k: "FAILED", n: $q.context, d: ("unknown status " + ($l.status | tostring))} end
              end ] as $v
        | { req: ($req | length),
            green:   [$v[] | select(.k == "GREEN")   | .n] | length,
            absent:  [$v[] | select(.k == "ABSENT")  | .n],
            pending: [$v[] | select(.k == "PENDING") | .n],
            failed:  [$v[] | select(.k == "FAILED")  | .n],
            lines:   [$v[] | select(.k != "GREEN")
                      | if .k == "ABSENT" then "ABSENT  \(.n)"
                        elif .k == "PENDING" then "PENDING \(.n) (\(.d))"
                        else "FAILED  \(.n) (\(.d))" end] }
      end' "$WORK/runs.json") || { fail3 "classifying check runs failed" api-error; return; }

  # Positive shape check on the classifier's own output before reading any field of it.
  jq -e 'type == "object" and ((has("error") and (.error|type) == "string")
         or ((.req|type) == "number" and (.green|type) == "number" and (.lines|type) == "array"))' \
    <<<"$out" >/dev/null 2>&1 || { fail3 "classifier produced no verdict" api-error; return; }
  if jq -e 'has("error")' <<<"$out" >/dev/null; then
    MSG="ERROR: $(jq -r '.error' <<<"$out")"; REASON=$(jq -r '.reason' <<<"$out"); return 3
  fi
  N_REQ=$(jq -r '.req' <<<"$out")
  J_ABSENT=$(jq -c '.absent' <<<"$out")
  J_PENDING=$(jq -c '.pending' <<<"$out")
  J_FAILED=$(jq -c '.failed' <<<"$out")
  LINES=$(jq -r '.lines[]' <<<"$out")
  if jq -e '.req > 0 and .green == .req and (.lines | length) == 0' <<<"$out" >/dev/null; then
    # A carryover arm that already named itself (carryover-local-docs) keeps its
    # reason; a plain or verified-carryover ready reads all-green as before.
    [[ "$REASON" == "none" ]] && REASON="all-green"
    return 0
  fi
  if [[ -z "$LINES" ]]; then fail3 "classifier counted $(jq -r '.green' <<<"$out") of $N_REQ green but named no culprit" api-error; return; fi
  REASON="not-green"; return 1
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
    4) finish 4 stale ;;
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
    4) finish 4 stale ;;
    1) ;;
    *) finish 3 error ;;
  esac
  # rc 1: a FAILED context, UNTRUSTED-CI or a base mismatch is terminal -- no point waiting.
  if [[ "$J_FAILED" != "[]" || "$REASON" != "not-green" ]]; then finish 1 not-ready; fi
  if [[ "$LINES" != "$prev" ]]; then
    printf 'WAIT poll=%d/%d absent=%s pending=%s\n' "$poll" "$MAX_POLLS" "$J_ABSENT" "$J_PENDING"
    prev="$LINES"
  elif (( poll % 5 == 0 )); then
    printf 'HEARTBEAT poll=%d/%d still waiting absent=%s pending=%s\n' \
      "$poll" "$MAX_POLLS" "$J_ABSENT" "$J_PENDING"
  fi
  (( poll < MAX_POLLS )) && sleep "$POLL_SECONDS"
done
MSG="TIMEOUT: $MAX_POLLS polls spent with required contexts still absent or pending"
REASON=timeout
finish 1 timeout
