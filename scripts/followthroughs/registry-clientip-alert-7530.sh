#!/usr/bin/env bash
# Follow-through verification for #7530 — the standing alert for a non-RFC1918 registry clientIP.
#
# WHAT THIS ANSWERS. PR #10320 adds `soleur-registry-clientip-not-rfc1918-prd` to
# apps/web-platform/infra/betterstack-logs-alerts.tf: a Better Stack Logs alert that alerts by email (free
# tier, no escalation policy) when the registry plane ships a `clientIP` outside 10/8, 172.16/12 and 192.168/16 (the CLO's 2026-08 ruling lets
# the log shipper keep `clientIP` unredacted ONLY while every observable value is private). The alert is
# applied by the merge's push apply and `treat_as_zero` means a predicate that silently stopped matching
# reads as healthy forever, so "the resource exists" proves nothing. This probe is a pure verdict
# emitter that proves the PREDICATE, as committed, behaves on the live engine and on the live stream.
# It reads, grades, prints counts and tokens, and exits. It never writes (no `gh issue close`, no
# comment, no dispatch, no rerun), so it is safe under the sweeper's `dry_run`.
#
# THE GATES, in order (exit 2 until all hold, exit 3 when something is provably wrong or unreadable):
#   1. PR 10320 is merged.
#   2. A PUSH-event run of apply-web-platform-infra.yml for the merge SHA or a descendant concluded
#      `success`. The workflow has a single pending slot, so the merge SHA's own run may be displaced
#      (cancelled): a descendant's successful run counts. A failed apply with nothing running is exit 3
#      naming what clears it (a push-event apply that succeeds; a workflow_dispatch re-fire is NOT counted),
#      never an endless 2.
#   3. The newest SOLEUR_ZOT_DISK boot began AFTER the merge (the registry host was replaced) and has
#      at least 30 minutes of rows (a window to grade), and its newest row is not older than 30 minutes.
#   4. The alert's SQL is extracted from betterstack-logs-alerts.tf (the local
#      `registry_clientip_not_rfc1918_sql`; precedent: luks-monitor-host-timer-8706.sh). Absent while the
#      checkout does not yet contain the merge: exit 2; absent after: exit 3.
# Then four engine reads, all through scripts/betterstack-query.sh in raw-SQL mode over the hot window
# plus the archive, from the newest post-merge boot's first row to now:
#   (a) the 16-LITERAL CLASSIFICATION TABLE through the extracted lambda, with synthetic literals only
#       (engine semantics: 10/8, 172.16/12, 192.168/16 and IPv4-mapped private values quiet; public,
#       loopback, link-local, CGNAT and IPv6 values flagged). A wrong classification is a measured
#       contradiction of the alert's design: exit 1, counts only.
#   (b) the predicate AS WRITTEN over the window: the committed conjuncts verbatim, nothing added or
#       removed. Must be 0 against a positive population. Above 0: exit 1, counts only.
#   (c) the PRIVATE-FLAGGED CONTROL: the same predicate with its private-range exclusion flipped to an
#       inclusion. Must be above 0, which proves the engine path that flags a row is alive; a zero here
#       makes (b)'s zero uninterpretable: exit 3.
#   (d) the POPULATION: rows under the two producer anchors that carry a clientIP at all. Empty: exit 3.
#
# NEVER AN ADDRESS. The sweeper posts this output verbatim into a PUBLIC issue, and what is being
# measured is whether a client address reached the sink. Output is counts, verdict tokens and truncated
# boot ids only: no row text, no clientIP value (not even the synthetic table literals), no timestamps.
#
# CREDENTIAL POSTURE. GH_TOKEN (read-only gh calls: pr view, run list) and BETTERSTACK_QUERY_HOST /
# _USERNAME / _PASSWORD (the ClickHouse HTTP connection, read through scripts/betterstack-query.sh) are
# read from the environment by NAME only. No value is printed, echoed or placed on a command line; the
# query tool's stdout and stderr are captured and never passed through (a tool that dies mid-auth can
# print a header carrying the credential); the probe refuses to run under xtrace while any credential is
# set (exit 78, #7797).
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh maps the code to the heading an operator reads):
#   0 = PASS               gates held; table correct; as-written count 0 over a positive population;
#                          control above 0. The tracker may close.
#   1 = FAIL               ONLY a measured contradiction: the predicate as written counts a non-private
#                          clientIP over the window, or the extracted predicate misclassifies the table.
#                          Counts only. On a closed tracker exit 1 reopens it, so nothing else is 1.
#   2 = NOT YET            PR not merged, push apply not concluded, replace not landed, too little data,
#                          or the checkout predates the merge.
#   3 = CANNOT ESTABLISH   anything unreadable or unprovable: a failed read or query, a missing
#                          credential, an unorderable SHA, a failed apply, a silent producer, an empty
#                          channel or population, a dead control, an unextractable predicate.
#   78                     refused to run traced with a credential set.
#
# WHAT A PASS DOES AND DOES NOT PROVE (documented limits):
#   * "The newest boot began AFTER the merge" (gate 3) is satisfied by a plain REBOOT of the old registry
#     host as well as by a replace. The gate proves a host is reporting a fresh boot, not which template
#     built it.
#   * PASS grades the predicate as COMMITTED in the checkout (the extracted local) over the new window; it
#     does not read the alert text deployed in Better Stack. That the deployed alert equals the committed
#     one is the push apply's job (gate 2), not this probe's.
#   * COUPLING: the extraction below uses the HARD-CODED local name registry_clientip_not_rfc1918_sql
#     (LOCAL in the python block). It must equal the local the logtail_exploration's sql_query references
#     in betterstack-logs-alerts.tf; the suite's local_parity row enforces that, so a rename in the .tf
#     has to update LOCAL here in the same change.
#   * The measured population is the SHIPPER arm only: the disk arm (SOLEUR_ZOT_DISK) has no live positive
#     control: 0 SOLEUR_ZOT_DISK rows with a clientIP at the time of writing, so a PASS does not evidence that arm.
#   * PR_NUMBER=10320 is hard-coded: if the PR is closed and replaced by another number this probe stays at
#     exit 2 (n_pr_unmerged) forever; re-point PR_NUMBER (and the suite's gh row) or retire it.
#   * PRE_MERGE_LOOKBACK_SECS=7200: the boot read starts 2 hours before the merge. If the old host was silent
#     for longer than that before the merge there is no producer row to read and the probe sits at exit 3
#     (c_channel_dark) until a new boot reports.
#   * APPLY_WF is restated here with no parity check against the workflow YAML: a rename makes the run
#     listing unreadable or empty, so the probe cannot reach PASS (exit 3 or 2).
#
# RETIREMENT: once #7530 is closed, delete this script, its suite (registry-clientip-alert-7530.test.sh),
# its run_suite line in scripts/test-all.sh, its entries in scripts/lib/test-affected-paths.sh and
# scripts/lint-betterstack-emitter-read.sh, its two rows in scripts/suite-shard-legs.tsv and
# scripts/suite-durations.tsv, and delete the directive on #7530.
# BASELINE_DECLARED_PROBES in plugins/soleur/test/preflight-discoverability-test.test.ts is UNCHANGED by this retirement.
# It counts the PLANS (archive included) that declare credentials_required; the one plan whose discoverability_test
# names this probe keeps its declaration, so the constant falls only if that plan file is deleted or its declaration removed.
# Also reconcile the two rename guards: apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh
# (its H3 rename row points at local_parity in this probe's suite) loses its partner with this suite.
# The sweeper keeps re-running a closed tracker's probe for a while; every non-contradiction path here is
# 0, 2 or 3, so it cannot reopen the tracker by accident.
#
# Tracker directive (unfenced, column 0, in the #7530 body; the comma-separated list is required, a
# space-separated list forwards only the first name):
#   <!-- soleur:followthrough script=scripts/followthroughs/registry-clientip-alert-7530.sh earliest=2026-10-14T00:00:00Z secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

set -uo pipefail

# XTRACE REFUSAL (#7797). Tracing echoes a command after expansion, so a credential reaches the
# transcript the moment it is bound. Refuse to run traced while any credential is present.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

export LC_ALL=C

REPO="jikig-ai/soleur"
PR_NUMBER=10320
APPLY_WF="apply-web-platform-infra.yml"
TF_REL="apps/web-platform/infra/betterstack-logs-alerts.tf"
EXPECTED_HOST="soleur-registry"
MARKER="SOLEUR_ZOT_DISK"
# At least 30 minutes of rows from the newest post-merge boot before the window is graded.
MIN_SPAN_SECS=1800
# A newest row older than this is a silent producer (six missed */5 ticks), not a current window.
SILENT_SECS=1800
# The boot read starts this far before the merge so a pre-merge boot is visible as pre-merge.
PRE_MERGE_LOOKBACK_SECS=7200
# The classification table has exactly this many literals.
TABLE_ROWS=16
# A canonical non-negative integer: no leading zero (bash arithmetic reads 08/09 as an octal ERROR and 007 as
# octal 7) and at most 12 digits (no 64-bit overflow). Every integer read from a query answer or a date goes through it.
INT_RE='^(0|[1-9][0-9]{0,11})$'
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
# --limit IS NOT OPTIONAL: betterstack-query.sh defaults to 100 rows, silently short.
WINDOW_LIMIT=5000

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Test seams, inert under the sweeper's rebuilt environment (nothing but PATH and the forwarded names).
ROOT="${REG7530_REPO:-$SCRIPT_ROOT}"
BQ="${REG7530_BQ:-$SCRIPT_ROOT/scripts/betterstack-query.sh}"
TF="${REG7530_TF:-$ROOT/$TF_REL}"

say() { # <verdict-line> [prose line ...] -> stdout (the sweeper captures it into the comment)
  printf 'registry-clientip[#7530]: %s\n' "$1"
  shift
  local l
  for l in "$@"; do printf '  %s\n' "$l"; done
}

for need in gh jq git python3; do
  if ! command -v "$need" >/dev/null 2>&1; then
    say "verdict=c_deps_missing tool=$need" "CANNOT ESTABLISH: $need is not installed on this runner."
    exit 3
  fi
done
if [[ -z "${GH_TOKEN:-}" ]]; then
  say "verdict=c_token_unset" "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must list GH_TOKEN in secrets=)."
  exit 3
fi

# ── 1. the PR ─────────────────────────────────────────────────────────────────────────────────
rc=0
PR_JSON="$(gh pr view "$PR_NUMBER" -R "$REPO" --json state,mergeCommit,mergedAt 2>/dev/null)" || rc=$?
PR_STATE=""
if [[ "$rc" -eq 0 ]]; then
  PR_STATE="$(jq -r '.state // ""' <<<"$PR_JSON" 2>/dev/null)" || PR_STATE=""
fi
if [[ "$rc" -ne 0 || -z "$PR_STATE" ]]; then
  say "verdict=c_pr_read_failed rc=$rc" "CANNOT ESTABLISH: the PR $PR_NUMBER state could not be read."
  exit 3
fi
if [[ "$PR_STATE" != "MERGED" ]]; then
  say "verdict=n_pr_unmerged state=$PR_STATE" "NOT YET: PR $PR_NUMBER is not merged."
  exit 2
fi
MERGE_SHA="$(jq -r '.mergeCommit.oid // ""' <<<"$PR_JSON" 2>/dev/null)" || MERGE_SHA=""
if ! [[ "$MERGE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  say "verdict=c_pr_sha_unreadable" "CANNOT ESTABLISH: PR $PR_NUMBER is merged but its merge commit SHA is unreadable."
  exit 3
fi
MERGED_AT="$(jq -r '.mergedAt // ""' <<<"$PR_JSON" 2>/dev/null)" || MERGED_AT=""
MERGE_EPOCH=""
if [[ "$MERGED_AT" =~ $ISO_RE ]]; then
  MERGE_EPOCH="$(date -u -d "$MERGED_AT" +%s 2>/dev/null)" || MERGE_EPOCH=""
fi
if ! [[ "$MERGE_EPOCH" =~ $INT_RE ]]; then
  say "verdict=c_merge_time_unreadable" "CANNOT ESTABLISH: PR $PR_NUMBER is merged but its merge time is unreadable."
  exit 3
fi
if ! git -C "$ROOT" cat-file -e "${MERGE_SHA}^{commit}" 2>/dev/null; then
  say "verdict=c_history_unreadable which=merge" "CANNOT ESTABLISH: the merge commit is not in this checkout (a shallow clone cannot order runs)."
  exit 3
fi

# Canonical copy (byte-identical to plugins/soleur/test/test-helpers.sh; asserted by fixture-dir-operand-assert.test.sh).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

descends() {
  assert_fixture_dir "$ROOT"
  git -C "$ROOT" merge-base --is-ancestor "$MERGE_SHA" "$1" 2>/dev/null
}

# ── 2. the push apply ─────────────────────────────────────────────────────────────────────────
rc=0
RUNS_JSON="$(gh run list -R "$REPO" --workflow "$APPLY_WF" --event push --limit 100 \
  --json databaseId,headSha,conclusion,status,createdAt,event 2>/dev/null)" || rc=$?
RUNS_TSV=""
if [[ "$rc" -eq 0 ]]; then
  RUNS_TSV="$(jq -r 'if type == "array" then [.[] | select(.event == "push")] | sort_by(.createdAt) | .[] | [.databaseId, .headSha, (.conclusion // ""), (.status // "")] | @tsv else error("not an array") end' <<<"$RUNS_JSON" 2>/dev/null)" || rc=$?
fi
if [[ "$rc" -ne 0 ]]; then
  say "verdict=c_runs_read_failed rc=$rc" "CANNOT ESTABLISH: the $APPLY_WF run listing could not be read."
  exit 3
fi

APPLY_OK=0; N_INPROG=0; N_FAILED=0; N_UNORDERABLE=0
while IFS=$'\t' read -r rid rsha rconc rstat; do
  [[ -n "$rid" ]] || continue
  [[ "$rsha" =~ ^[0-9a-f]{40}$ ]] || continue
  if ! git -C "$ROOT" cat-file -e "${rsha}^{commit}" 2>/dev/null; then
    N_UNORDERABLE=$((N_UNORDERABLE + 1))
    continue
  fi
  descends "$rsha" || continue
  if [[ "$rstat" != "completed" ]]; then
    N_INPROG=$((N_INPROG + 1))
    continue
  fi
  if [[ "$rconc" == "success" ]]; then
    APPLY_OK=1
    break
  fi
  N_FAILED=$((N_FAILED + 1))
done <<<"$RUNS_TSV"

if (( APPLY_OK == 0 )); then
  if (( N_INPROG > 0 )); then
    say "verdict=n_apply_pending in_progress=$N_INPROG" "NOT YET: the push apply for the merge is still running."
    exit 2
  fi
  if (( N_UNORDERABLE > 0 )); then
    say "verdict=c_history_unreadable which=runs unorderable=$N_UNORDERABLE" "CANNOT ESTABLISH: $N_UNORDERABLE apply run(s) carry a SHA absent from this checkout, so they cannot be ordered against the merge."
    exit 3
  fi
  if (( N_FAILED > 0 )); then
    say "verdict=c_apply_failed failed=$N_FAILED" "CANNOT ESTABLISH: the push apply for the merge concluded without success and nothing is running, so the alert may not exist." \
      "What clears this verdict: a push-event run of apply-web-platform-infra.yml for the merge commit or a descendant that concludes success (this probe lists --event push runs only)." \
      "Transient failure: gh run rerun <failed push run id> --failed (re-executes the same push-event run, which then counts)." \
      "Config defect: merge a fix that touches apps/web-platform/infra/ to main; its push apply descends from the merge commit and counts once it succeeds." \
      "Re-fire: gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun  (NOT counted: a workflow_dispatch run applies the current main but is not a push-event run, so this verdict stays c_apply_failed until a push-event apply succeeds)."
    exit 3
  fi
  say "verdict=n_apply_pending" "NOT YET: no push-event $APPLY_WF run for the merge SHA or a descendant has been recorded."
  exit 2
fi

# ── 3. the post-merge boot ────────────────────────────────────────────────────────────────────
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    say "verdict=c_bs_creds_unset secret=$v" "CANNOT ESTABLISH: $v is not set (the tracker directive must list it in secrets=)."
    exit 3
  fi
done
if [[ ! -x "$BQ" ]]; then
  say "verdict=c_query_missing" "CANNOT ESTABLISH: scripts/betterstack-query.sh is missing or not executable."
  exit 3
fi

# decode_rows: stdin = betterstack-query.sh JSONEachRow. Prints `dt<TAB>message` for rows whose DECODED
# message STARTS with the marker (offset 0), sorted by dt. A row quoting the marker later, a journald
# envelope or a non-object raw does not survive.
decode_rows() {
  jq -r --arg pfx "$MARKER " '
    select(type == "object" and ((.raw | type) == "string"))
    | ((.raw | fromjson?) // null) as $o
    | select(($o | type) == "object")
    | ($o.message // "") as $m
    | select(($m | type) == "string" and ($m | startswith($pfx)))
    | [((.dt // "") | tostring | sub("T"; " ") | sub("Z$"; "") | sub("\\.[0-9]+$"; "")), $m] | @tsv' 2>/dev/null | sort
}

# parse_rows: stdin = decode_rows output. Prints `dt<TAB>boot_id` for host=$EXPECTED_HOST rows, read from
# the TRUSTED HEAD only (before the first ` zot_last_err=`); `unknown` (the /proc-unreadable default) is
# excluded by the hex character class.
parse_rows() {
  awk -F'\t' -v host="$EXPECTED_HOST" '
    {
      dt = $1; m = $2
      i = index(m, " zot_last_err=")
      head = (i > 0) ? substr(m, 1, i - 1) : m
      if (head !~ ("(^| )host=" host "($| )")) next
      if (!match(head, / boot_id=[0-9a-fA-F-]+/)) next
      b = substr(head, RSTART + 9, RLENGTH - 9)
      printf "%s\t%s\n", dt, b
    }'
}

BOOT_SINCE="$(date -u -d "@$(( MERGE_EPOCH - PRE_MERGE_LOOKBACK_SECS ))" '+%Y-%m-%dT%H:%M:%SZ')"
rc=0
BOOT_RAW="$("$BQ" --since "$BOOT_SINCE" --grep "$MARKER" --limit "$WINDOW_LIMIT" 2>/dev/null)" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  say "verdict=c_boot_read_failed rc=$rc" "CANNOT ESTABLISH: the $MARKER read failed. Its output is deliberately NOT reproduced here (the credential is bound in that process and this text is public)."
  exit 3
fi
BOOT_ROWS="$(printf '%s\n' "$BOOT_RAW" | decode_rows | parse_rows)"
if [[ -z "$BOOT_ROWS" ]]; then
  say "verdict=c_channel_dark" "CANNOT ESTABLISH: no producer row from host=$EXPECTED_HOST since before the merge; absence of rows is not evidence about the alert."
  exit 3
fi

NEWEST_BOOT="$(printf '%s\n' "$BOOT_ROWS" | tail -n 1 | cut -f2)"
FIRST_DT=""; LAST_DT=""; N_BOOT_ROWS=0
while IFS=$'\t' read -r dt boot; do
  [[ "$boot" == "$NEWEST_BOOT" ]] || continue
  [[ -n "$FIRST_DT" ]] || FIRST_DT="$dt"
  LAST_DT="$dt"
  N_BOOT_ROWS=$((N_BOOT_ROWS + 1))
done <<<"$BOOT_ROWS"

MERGE_STR="$(date -u -d "@$MERGE_EPOCH" '+%Y-%m-%d %H:%M:%S')"
if ! [[ "$MERGE_STR" < "$FIRST_DT" ]]; then
  say "verdict=n_no_post_merge_boot boot=${NEWEST_BOOT:0:8}" "NOT YET: the newest registry boot began before the merge, so the replaced host has not reported."
  exit 2
fi

FIRST_EPOCH="$(date -u -d "$FIRST_DT UTC" +%s 2>/dev/null)" || FIRST_EPOCH=""
LAST_EPOCH="$(date -u -d "$LAST_DT UTC" +%s 2>/dev/null)" || LAST_EPOCH=""
if ! [[ "$FIRST_EPOCH" =~ $INT_RE && "$LAST_EPOCH" =~ $INT_RE ]]; then
  say "verdict=c_boot_time_unparsable" "CANNOT ESTABLISH: the post-merge boot's row times do not parse."
  exit 3
fi
NOW_EPOCH="$(date -u +%s)"
if (( NOW_EPOCH - LAST_EPOCH > SILENT_SECS )); then
  say "verdict=c_producer_silent boot=${NEWEST_BOOT:0:8} last_row_age_min=$(( (NOW_EPOCH - LAST_EPOCH) / 60 ))" \
    "CANNOT ESTABLISH: the post-merge boot's newest row is more than 30 minutes old; the host stopped reporting, so a window ending now describes nothing."
  exit 3
fi
SPAN_SECS=$(( LAST_EPOCH - FIRST_EPOCH ))
if (( SPAN_SECS < MIN_SPAN_SECS )); then
  say "verdict=n_boot_too_young boot=${NEWEST_BOOT:0:8} span_min=$(( SPAN_SECS / 60 )) rows=$N_BOOT_ROWS" \
    "NOT YET: the post-merge boot has $(( SPAN_SECS / 60 )) minute(s) of rows; at least 30 are needed to grade a window."
  exit 2
fi
START_ISO="$(date -u -d "@$FIRST_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')"

# ── 4. the alert SQL, extracted and transformed (python3, isolated) ───────────────────────────
# Builds four queries from the COMMITTED local. Nothing here edits a conjunct: the as-written query is
# the committed tail verbatim; the control differs from it by ONE flipped NOT; the population is the
# producer anchors plus "carries a clientIP"; the table query swaps the message for a synthetic literal.
PY_OUT="$(python3 -I - "$TF" "$START_ISO" <<'PY'
import json, re, sys

path, start = sys.argv[1], sys.argv[2]
LOCAL = "registry_clientip_not_rfc1918_sql"
NOT_PRIVATE = "AND NOT match(n, '^(10[.]"
POS_PRIVATE = "AND match(n, '^(10[.]"
MSG_REF = "JSONExtractString(raw, 'message')"
# The 16-literal classification table (RFC 5737 / 3849 documentation addresses and private ranges;
# 1 = the predicate must flag it). Synthetic only. Never printed by the probe.
TABLE = [
    ("10.0.1.10:54321", 0), ("172.16.0.1:1", 0), ("172.31.255.255:9", 0), ("192.168.1.1:80", 0),
    ("::ffff:10.0.0.5", 0), ("default", 0),
    ("198.51.100.7:443", 1), ("127.0.0.1:5000", 1), ("172.15.0.1:1", 1), ("172.32.0.1:9", 1),
    ("192.169.0.1:80", 1), ("169.254.169.254:80", 1), ("100.64.0.1:80", 1), ("[2001:db8::1]:80", 1),
    ("2001:db8::1", 1), ("::ffff:198.51.100.7", 1),
]


def out(d):
    print(json.dumps(d))
    sys.exit(0)


def balanced(s, k):
    """Index just past the ')' matching the '(' at s[k]; quoted strings are skipped. -1 if unbalanced."""
    depth, inq = 0, False
    while k < len(s):
        c = s[k]
        if inq:
            if c == "\\":
                k += 2
                continue
            if c == "'":
                inq = False
        else:
            if c == "'":
                inq = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return k + 1
        k += 1
    return -1


if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", start):
    out({"err": "shape"})
try:
    with open(path, encoding="utf-8") as fh:
        tf = fh.read()
except OSError:
    out({"err": "local_absent"})
m = re.search(r"^[ \t]*" + LOCAL + r"[ \t]*=[ \t]*<<-?SQL[ \t]*\n(.*?)\n[ \t]*SQL[ \t]*$", tf, re.M | re.S)
if not m:
    out({"err": "local_absent"})
sql = " ".join(m.group(1).split())
head = "WHERE time BETWEEN {{start_time}} AND {{end_time}} "
i = sql.find(head)
j = sql.rfind(" GROUP BY time")
if i < 0 or j < i + len(head):
    out({"err": "shape"})
tail = sql[i + len(head):j]
if not tail.startswith("AND (startsWith("):
    out({"err": "shape"})
a0 = tail.index("(")
a1 = balanced(tail, a0)
e0 = tail.find("arrayExists(")
if a1 < 0 or e0 < 0:
    out({"err": "shape"})
e1 = balanced(tail, e0 + len("arrayExists"))
if e1 < 0:
    out({"err": "shape"})
anchors = tail[a0:a1]
aexpr = tail[e0:e1]
if aexpr.count(MSG_REF) != 1 or tail.count(NOT_PRIVATE) != 1:
    out({"err": "shape"})
ctl_tail = tail.replace(NOT_PRIVATE, POS_PRIVATE)

S = "parseDateTime64BestEffort('" + start + "', 3, 'UTC')"
src = ("(SELECT dt, raw FROM remote($BS_TABLE) WHERE dt >= " + S
       + " UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1 AND dt >= " + S + ")")
base = " FROM " + src + " WHERE dt >= " + S + " "
out({
    "err": "",
    "as_written_sql": "SELECT count() AS n_as_written" + base + tail + " FORMAT JSONEachRow",
    "control_sql": "SELECT count() AS n_control" + base + ctl_tail + " FORMAT JSONEachRow",
    "population_sql": ("SELECT count() AS n_population" + base + "AND " + anchors
                       + " AND match(" + MSG_REF + ", 'clientIP[:=]') FORMAT JSONEachRow"),
    "table_sql": ("SELECT lit, " + aexpr.replace(MSG_REF, "concat('clientIP:', lit)")
                  + " AS flagged FROM (SELECT arrayJoin([" + ", ".join("'" + t[0] + "'" for t in TABLE)
                  + "]) AS lit) FORMAT JSONEachRow"),
    "expected": {t[0]: t[1] for t in TABLE},
})
PY
)" || PY_OUT=""
PY_ERR="$(jq -r '.err // "shape"' <<<"$PY_OUT" 2>/dev/null)" || PY_ERR="shape"
if [[ "$PY_ERR" != "" ]]; then
  if [[ "$PY_ERR" == "local_absent" ]]; then
    ANC_RC=0
    assert_fixture_dir "$ROOT"
    git -C "$ROOT" merge-base --is-ancestor "$MERGE_SHA" HEAD 2>/dev/null || ANC_RC=$?
    if [[ "$ANC_RC" -eq 1 ]]; then
      say "verdict=n_sql_not_on_main" "NOT YET: the alert local is absent and this checkout does not contain the merge commit yet."
      exit 2
    fi
    say "verdict=c_sql_local_absent" "CANNOT ESTABLISH: the local registry_clientip_not_rfc1918_sql is absent from $TF_REL after the merge reached this checkout."
    exit 3
  fi
  say "verdict=c_sql_shape" "CANNOT ESTABLISH: the alert SQL no longer has the shape this probe transforms (time frame, producer anchors, arrayExists lambda, private-range exclusion)."
  exit 3
fi
TABLE_SQL="$(jq -r '.table_sql' <<<"$PY_OUT")"
POP_SQL="$(jq -r '.population_sql' <<<"$PY_OUT")"
ASW_SQL="$(jq -r '.as_written_sql' <<<"$PY_OUT")"
CTL_SQL="$(jq -r '.control_sql' <<<"$PY_OUT")"
EXPECTED_JSON="$(jq -c '.expected' <<<"$PY_OUT")"

# ── 5. the engine reads ───────────────────────────────────────────────────────────────────────
Q_OUT=""
run_q() { # <kind> <sql> -> Q_OUT; exit 3 on a failed query
  local kind="$1" sql="$2" qrc=0
  Q_OUT="$("$BQ" "$sql" 2>/dev/null)" || qrc=$?
  if [[ "$qrc" -ne 0 ]]; then
    say "verdict=c_query_failed which=$kind rc=$qrc" "CANNOT ESTABLISH: the $kind query failed. Its output is deliberately NOT reproduced here."
    exit 3
  fi
}
COUNT=""
read_count() { # <kind> <alias> -> COUNT; exit 3 on anything but a non-negative integer
  local kind="$1" key="$2"
  COUNT="$(printf '%s\n' "$Q_OUT" | jq -r --arg k "$key" 'select(type == "object") | .[$k] // empty | tostring' 2>/dev/null | head -n 1)"
  if ! [[ "$COUNT" =~ $INT_RE ]]; then
    say "verdict=c_query_failed which=$kind" "CANNOT ESTABLISH: the $kind query returned no usable count (an empty or malformed answer is never a zero)."
    exit 3
  fi
}

run_q table "$TABLE_SQL"
TABLE_STATS="$(printf '%s\n' "$Q_OUT" | jq -s -c --argjson exp "$EXPECTED_JSON" '
  [.[] | select(type == "object" and has("lit") and has("flagged"))] as $rows
  | { n: ($rows | length),
      unknown: ([$rows[] | select($exp[(.lit | tostring)] == null)] | length),
      dup: ((($rows | map(.lit) | unique | length)) != ($rows | length)),
      mismatches: ([$rows[] | select($exp[(.lit | tostring)] != null and ((.flagged | tonumber) != $exp[(.lit | tostring)]))] | length) }' 2>/dev/null)" || TABLE_STATS=""
T_N="$(jq -r '.n // ""' <<<"$TABLE_STATS" 2>/dev/null)" || T_N=""
T_UNKNOWN="$(jq -r '.unknown // ""' <<<"$TABLE_STATS" 2>/dev/null)" || T_UNKNOWN=""
T_DUP="$(jq -r '.dup' <<<"$TABLE_STATS" 2>/dev/null)" || T_DUP=""
T_MISMATCH="$(jq -r '.mismatches // ""' <<<"$TABLE_STATS" 2>/dev/null)" || T_MISMATCH=""
if ! [[ "$T_N" == "$TABLE_ROWS" && "$T_UNKNOWN" == "0" && "$T_DUP" == "false" && "$T_MISMATCH" =~ $INT_RE ]]; then
  say "verdict=c_table_unreadable rows=${T_N:-0}" "CANNOT ESTABLISH: the classification answer is not exactly $TABLE_ROWS distinct known literals, so the table cannot be graded."
  exit 3
fi

run_q population "$POP_SQL"; read_count population n_population; POPULATION="$COUNT"
run_q as_written "$ASW_SQL"; read_count as_written n_as_written; AS_WRITTEN="$COUNT"
run_q control "$CTL_SQL";    read_count control n_control;       CONTROL="$COUNT"

# ── 6. the verdict ────────────────────────────────────────────────────────────────────────────
if (( AS_WRITTEN > 0 )); then
  say "verdict=f_non_rfc1918 as_written=$AS_WRITTEN population=$POPULATION control=$CONTROL boot=${NEWEST_BOOT:0:8} span_min=$(( SPAN_SECS / 60 ))" \
    "FAIL: the predicate as written counts $AS_WRITTEN row(s) with a non-RFC1918 clientIP over the post-merge window." \
    "No value is shown here (this comment is public). Follow the runbook registry-clientip-rfc1918-7530.md: fix the ingress cause first, count the exposure, never paste an address."
  exit 1
fi
if (( T_MISMATCH > 0 )); then
  say "verdict=f_table_mismatch table_mismatches=$T_MISMATCH rows=$TABLE_ROWS" \
    "FAIL: the extracted predicate misclassifies $T_MISMATCH of $TABLE_ROWS synthetic literals on the live engine, so the alert does not do what it claims." \
    "The literals are withheld from this public comment; see the table in the comment above the local in $TF_REL."
  exit 1
fi
if (( POPULATION == 0 )); then
  say "verdict=c_population_empty as_written=$AS_WRITTEN" "CANNOT ESTABLISH: no row under the producer anchors carries a clientIP in the window, so a zero count proves nothing."
  exit 3
fi
if (( CONTROL == 0 )); then
  say "verdict=c_control_dead population=$POPULATION as_written=$AS_WRITTEN" "CANNOT ESTABLISH: the private-flagged control counts nothing over a positive population, so the as-written zero cannot be told from a dead predicate."
  exit 3
fi
say "verdict=p_pass population=$POPULATION as_written=$AS_WRITTEN control=$CONTROL table_mismatches=0 boot=${NEWEST_BOOT:0:8} span_min=$(( SPAN_SECS / 60 ))" \
  "PASS: the push apply succeeded; the classification table matches on all $TABLE_ROWS synthetic literals; the predicate as written counts 0 non-private clientIP rows" \
  "over $(( SPAN_SECS / 60 )) minute(s) of the post-merge boot ($POPULATION clientIP-bearing rows); the private-flagged control counts $CONTROL." \
  "register PA-8 (c)/(g) brackets, counsel-review-7440 addendum + frontmatter clientip_monitoring_pointer, ADR-211 and ADR-218 delivery-state lines say NOT in force / not treated as an enforced invariant until this PASS: re-date them per knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md section 'After the first graded PASS'"
exit 0
