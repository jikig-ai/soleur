#!/usr/bin/env bash
# Follow-through verification for #10552 - the weekly `cron-compound-promote` run
# now hands the gates a SERVER-DERIVED diff, and the old terminal refusal
# `diff-underivable-apply` is gone.
#
# #10552: every cluster the promoter proposed was refused `diff-underivable-apply`
# because the model was asked to hand-write a unified diff over a file it was never
# shown. The fix has the model propose an insertion (anchor line + new lines) and the
# server derives the diff with git. This probe proves the fix on the only evidence
# that settles it: a run in production whose proposal REACHED the gates.
#
# PASS (stdout literal `PASS`, exit 0) needs POSITIVE evidence that a derived diff
# was consumed, from an ALLOWLIST:
#   - `clusters_opened >= 1` (a draft PR was opened), or
#   - a refusal that can occur only AFTER `checkDiffPaths` accepted the derived diff:
#     `diff-path-off-target`, `byte-budget-overflow`, `corpus-shrink-refused`,
#     `agents-core-hr-rule-edit-refused`, `not-committed-*`.
# The PASS set is NOT the complement of the failure set: a complement would pass
# `target-path-refused`, `skill-conflict-guard`, `diff-size-exceeded`,
# `branch-name-shape-failed`, `target-missing` and any forged unknown string, none of
# which touches the derived diff.
#
# Row classes (graded INSIDE jq on decoded, field-isolated rows):
#   P  proof        -> exit 0
#   F  defect       -> exit 1   any `diff-underivable-*`, `git-apply-check-failed`,
#                               `edit-derive-failed` (a SERVER bug, not a model one)
#   N  no proof     -> exit 2   model-side `edit-*`, `skill-conflict-guard`, quiet
#                               weeks, every status other than the above, and anything
#                               unrecognised
# Precedence over the post-floor runs: ANY class-P run -> PASS; otherwise the LATEST
# post-floor run decides (F -> FAIL, N -> NOT YET). A run holding both a proof and a
# class-F refusal is class P (it proves the path works) and the F reasons are printed
# to stderr as a NOTE.
#
# Exit semantics (sweep-followthroughs.sh's rc -> word map):
#   0 = PASS
#   1 = FAIL              (the derived diff is being refused by our own code)
#   2 = NOT YET           (no proof yet - still soaking)
#   3 = CANNOT ESTABLISH  (credential, floor, or positive control missing)
#   5 = ACTION REQUIRED   (still NOT YET 35 days after the floor: a permanent
#                          `edit-*` or skill-conflict streak must surface, not leave
#                          a silently open tracker)
#
# Fail-open shapes this probe is built to avoid (construction copied from
# compound-promote-outcome-8281.sh, which measured each in-repo):
#  1. ECHO. `--grep` is SQL `raw LIKE '%...%'`, and GitHub webhook payloads (PR and
#     issue bodies that quote reason names) land in the same source. We decode
#     structurally and field-isolate on `.fn` plus the boolean discriminator.
#  2. DARK CHANNEL. Zero decoded rows is evidence only if the pipeline is known live.
#     `SOLEUR_CLAUDE_COST` rides the same pino WARN -> Vector -> Better Stack path and
#     is the positive control; without control rows we refuse to grade (exit 3).
#  3. SLIDING WINDOW / STALE ROWS. The floor is the DEPLOY completion time of the fix
#     (`FT10552_DEPLOY_FLOOR`, required, never defaulted): old code keeps running until
#     the image deploys, so a fire in that gap writes `diff-underivable-apply` rows that
#     must not be graded. Rows dated before the floor are dropped inside jq, so
#     editing the floor earlier is the only way to grade them - and an unset or
#     unparsable floor is exit 3.
#
# Output hygiene: the sweeper posts this output as a GitHub comment, and the marker
# carries strings an attacker can influence indirectly. Only values matching the
# closed enum (or the `not-committed-*` / `diff-underivable-*` families, restricted to
# [a-z0-9-]) are printed; everything else is bucketed `unknown`.
#
# Directive on #10552 (set `earliest` to one day after the first `0 0 * * 0` fire that
# follows the deploy, and FT10552_DEPLOY_FLOOR to the deploy completion timestamp):
#   <!-- soleur:followthrough script=scripts/followthroughs/compound-promote-draft-edit-10552.sh earliest=<first-sunday-fire-after-deploy+1d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Tracing echoes commands after expansion, so a
# credential is printed the moment it is used. `${VAR:+x}` tests non-emptiness
# WITHOUT expanding the value. All three Better Stack vars are tested.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause).\n' "$v" >&2
    exit 3
  fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$REPO_ROOT" ]; then
  # Without this, a failed cd leaves QUERY_SH as "/scripts/betterstack-query.sh" and
  # the probe reports a credential-shaped TRANSIENT on every sweep forever.
  printf 'CANNOT ESTABLISH: could not resolve the repo root from %s\n' "${BASH_SOURCE[0]}" >&2
  exit 3
fi
QUERY_SH="$REPO_ROOT/scripts/betterstack-query.sh"

numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }

# The floor is REQUIRED and strictly shaped. `date -d` also accepts "yesterday" and
# "2 days ago", which would slide the window every run; only an absolute UTC ISO
# timestamp is accepted.
DEPLOY_FLOOR="${FT10552_DEPLOY_FLOOR:-}"
if [ -z "$DEPLOY_FLOOR" ]; then
  printf 'CANNOT ESTABLISH: FT10552_DEPLOY_FLOOR is not set (the deploy completion time of the fix, e.g. 2026-10-20T08:15:00Z). There is no default: a default would grade pre-fix rows.\n' >&2
  exit 3
fi
if ! [[ "$DEPLOY_FLOOR" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  printf 'CANNOT ESTABLISH: FT10552_DEPLOY_FLOOR is not an absolute UTC timestamp (YYYY-MM-DDTHH:MM:SSZ): %s\n' "${DEPLOY_FLOOR:0:40}" >&2
  exit 3
fi
floor_s="$(date -u -d "$DEPLOY_FLOOR" +%s 2>/dev/null || true)"
numeric "$floor_s" || {
  printf 'CANNOT ESTABLISH: FT10552_DEPLOY_FLOOR does not parse: %s\n' "${DEPLOY_FLOOR:0:40}" >&2; exit 3; }
LIMIT="${FT10552_LIMIT:-200}"
numeric "$LIMIT" || {
  printf 'CANNOT ESTABLISH: FT10552_LIMIT is not a number: %s\n' "${LIMIT:0:40}" >&2; exit 3; }

now_s="$(date -u +%s)"
# Fixed, deliberately not overridable by env: an env override is a way to defer the
# escalation forever.
ESCALATE_AFTER_DAYS=35

# NOT YET, or ACTION REQUIRED once the soak has outlived its budget.
not_yet() { # not_yet <message>
  local age_s=$((now_s - floor_s))
  if (( age_s >= ESCALATE_AFTER_DAYS * 86400 )); then
    printf 'ACTION REQUIRED: still NOT YET %s days after the deploy floor %s (budget %s). %s\n' \
      "$((age_s / 86400))" "$DEPLOY_FLOOR" "$ESCALATE_AFTER_DAYS" "$1" >&2
    exit 5
  fi
  printf 'NOT YET: %s\n' "$1" >&2
  exit 2
}

if [ ! -f "$QUERY_SH" ]; then
  not_yet "betterstack-query.sh not found at $QUERY_SH"
fi
if (( floor_s > now_s )); then
  not_yet "FT10552_DEPLOY_FLOOR $DEPLOY_FLOOR is in the future - the fix has not deployed yet."
fi

# Normalized floor in Better Stack's `dt` shape for a string comparison inside jq.
floor_dt="$(date -u -d "@$floor_s" '+%Y-%m-%d %H:%M:%S')"
# +2d of slack so a fire at the floor's edge is inside the window.
WINDOW="$(( (now_s - floor_s) / 86400 + 2 ))d"

# Scratch files (mktemp -t, so the redirect targets below are provably absolute).
# Both are written by jq / the query helper and read back; no verdict is ever taken
# from a pipeline's exit status.
QOUT="$(mktemp -t ft10552-rows.XXXXXXXX)"
GOUT="$(mktemp -t ft10552-graded.XXXXXXXX)"
SOUT="$(mktemp -t ft10552-sorted.XXXXXXXX)"
trap 'rm -f -- "$QOUT" "$GOUT" "$SOUT"' EXIT

# `run_query <label> <grep> <limit>` writes to $QOUT and is a plain statement, NOT
# inside `$(...)`: a `exit 3` in a command substitution exits the SUBSHELL, the caller
# gets an empty string, and "nothing was queried" is graded as a verdict (8281's case
# 7). stderr is CAPTURED, never discarded; rc 3 is forwarded as 3.
run_query() {
  local label="$1" pattern="$2" lim="$3" rc
  bash "$QUERY_SH" --since "$WINDOW" --grep "$pattern" --limit "$lim" > "$QOUT" 2>&1
  rc=$?
  if [ "$rc" -eq 3 ]; then
    printf 'CANNOT ESTABLISH: betterstack-query.sh could not query (%s): %s\n' "$label" "$(head -c 400 "$QOUT")" >&2
    exit 3
  fi
  if [ "$rc" -ne 0 ]; then
    not_yet "betterstack-query.sh exited $rc ($label): $(head -c 200 "$QOUT" | tr -c '[:alnum:] ._:/-' '?')"
  fi
}

# `-R` plus `fromjson?` at BOTH levels so a non-JSON line (merged stderr, a mid-stream
# ClickHouse exception) is skipped rather than aborting jq into a silent zero. The pino
# payload sits under `.message` of the decoded `raw`.
CONTROL_JQ='fromjson? | .raw? | fromjson? | .message?
            | select(type == "object" and .SOLEUR_CLAUDE_COST == true) | "row"'

# One line per VALID post-floor marker row, tab separated, every field already
# sanitized to a closed alphabet:
#   dt  trigger  status  class  reasons  has_f  opened
# `$m.fn == "cron-compound-promote"` and the boolean discriminator are checked on the
# decoded message, never on `raw`.
# shellcheck disable=SC2016  # a jq program: `$m`, `$floor` are jq variables, not shell expansions
GRADE_JQ='
def pset: ["diff-path-off-target","byte-budget-overflow","corpus-shrink-refused","agents-core-hr-rule-edit-refused"];
def fset: ["git-apply-check-failed","edit-derive-failed"];
def nset: ["edit-target-unreadable","edit-target-too-large","edit-invalid","edit-anchor-not-found",
           "edit-anchor-ambiguous","edit-target-duplicate","skill-conflict-guard","target-path-refused",
           "target-missing","branch-name-shape-failed","diff-size-exceeded"];
def sset: ["disabled","deduped","week-cap-reached","empty-corpus","anthropic-truncated",
           "no-qualifying-clusters","completed","error"];
def member($set): . as $x | any($set[]; . == $x);
def isP: type == "string" and (member(pset) or test("^not-committed-[a-z0-9-]{1,40}\\z"));
def isF: type == "string" and (startswith("diff-underivable-") or member(fset));
def shown: if type == "string" and (member(pset + fset + nset)
                                    or test("^(not-committed|diff-underivable)-[a-z0-9-]{1,40}\\z"))
           then . else "unknown" end;
fromjson? | select(type == "object")
| .dt as $dt0
| (.raw? | fromjson? | .message?) as $m
| select(($m | type) == "object" and $m.SOLEUR_COMPOUND_PROMOTE_OUTCOME == true and $m.fn == "cron-compound-promote")
| ($dt0 | if type == "string" then sub("T"; " ") else "" end) as $dt
| select($dt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"))
| ($dt[0:19]) as $d19
| select($d19 >= $floor)
| ($m.refusals | if type == "array" then . else [] end) as $rs
| (($m.clusters_opened // 0) | if type == "number" then . else 0 end) as $opened
| (if $opened >= 1 or ($rs | any(isP)) then "P"
   elif ($rs | any(isF)) then "F" else "N" end) as $cls
| [ $d19,
    ($m.trigger | if . == "cron" or . == "manual" then . else "unknown" end),
    ($m.status | if type == "string" and member(sset) then . else "unknown" end),
    $cls,
    ($rs | map(shown) | unique | if length == 0 then "-" else join(",") end),
    (if ($rs | any(isF)) then "1" else "0" end),
    ($opened | tostring) ]
| join("\t")
'

# --- positive control: prove the channel carries WARN markers at all ----------
run_query control SOLEUR_CLAUDE_COST 5
jq -R -r "$CONTROL_JQ" < "$QOUT" > "$GOUT"
rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'CANNOT ESTABLISH: jq failed decoding the positive-control rows (rc=%s).\n' "$rc" >&2
  exit 3
fi
ctl_n="$(grep -c . "$GOUT" || true)"
if ! numeric "$ctl_n" || [ "$ctl_n" -eq 0 ]; then
  printf 'CANNOT ESTABLISH: the positive control (SOLEUR_CLAUDE_COST decoded under .message within %s) returned 0 rows - the WARN->Vector->Better Stack channel is dark or its row shape changed. Refusing to grade an absence through a dead instrument.\n' "$WINDOW" >&2
  exit 3
fi

# --- the assertion: grade every post-floor marker -------------------------------
run_query outcome SOLEUR_COMPOUND_PROMOTE_OUTCOME "$LIMIT"
jq -R -r --arg floor "$floor_dt" "$GRADE_JQ" < "$QOUT" > "$GOUT"
rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'CANNOT ESTABLISH: jq failed grading the outcome rows (rc=%s).\n' "$rc" >&2
  exit 3
fi
# Oldest first; -s keeps the input order for equal timestamps.
sort -s -t "$(printf '\t')" -k1,1 "$GOUT" > "$SOUT"
rc=$?
if [ "$rc" -ne 0 ]; then
  printf 'CANNOT ESTABLISH: sort failed on the graded rows (rc=%s).\n' "$rc" >&2
  exit 3
fi

total_n="$(grep -c . "$SOUT" || true)"
p_n="$(awk -F '\t' '$4 == "P" { n++ } END { print n + 0 }' "$SOUT")"
recent="$(tail -n 8 "$SOUT" | awk -F '\t' '{ printf "  %s UTC trigger=%s status=%s class=%s opened=%s reasons=%s\n", $1, $2, $3, $4, $7, $5 }')"

if ! numeric "$total_n" || [ "$total_n" -eq 0 ]; then
  not_yet "0 valid SOLEUR_COMPOUND_PROMOTE_OUTCOME markers since the deploy floor $DEPLOY_FLOOR (control live: $ctl_n rows) - no run has been observed since the fix deployed."
fi

if numeric "$p_n" && [ "$p_n" -ge 1 ]; then
  proof="$(awk -F '\t' '$4 == "P" { l = $0 } END { print l }' "$SOUT")"
  IFS=$'\t' read -r p_dt p_trig p_status _ p_reasons p_hasf p_opened <<< "$proof"
  printf 'PASS\n'
  printf 'PASS evidence: %s run(s) of %s since %s proved a derived diff was consumed (control live: %s rows). Latest proof: %s UTC trigger=%s status=%s opened=%s reasons=%s\n%s\n' \
    "$p_n" "$total_n" "$DEPLOY_FLOOR" "$ctl_n" "$p_dt" "$p_trig" "$p_status" "$p_opened" "$p_reasons" "$recent" >&2
  if [ "$p_hasf" = "1" ]; then
    printf 'NOTE: that run also carried a class-F refusal (%s) - a server-side defect on a sibling cluster; see the runbook.\n' "$p_reasons" >&2
  fi
  exit 0
fi

last="$(tail -n 1 "$SOUT")"
IFS=$'\t' read -r l_dt l_trig l_status l_cls l_reasons _ l_opened <<< "$last"

if [ "$l_cls" = "F" ]; then
  printf 'FAIL: the latest run (%s UTC, trigger=%s, status=%s) was refused by our own code with a server-side reason: %s. A derived diff must not be underivable or rejected by git; this is a defect, not a model miss (control live: %s rows).\n%s\n' \
    "$l_dt" "$l_trig" "$l_status" "$l_reasons" "$ctl_n" "$recent" >&2
  exit 1
fi

not_yet "no run since $DEPLOY_FLOOR has proved a derived diff was consumed ($total_n run(s), control live: $ctl_n rows). Latest: $l_dt UTC trigger=$l_trig status=$l_status opened=$l_opened reasons=$l_reasons
$recent"
