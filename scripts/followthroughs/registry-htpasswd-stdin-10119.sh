#!/usr/bin/env bash
# Follow-through verification for #10119 — the registry template's htpasswd password-on-stdin conversion.
#
# WHAT THIS ANSWERS. PR for #10119 changed `cloud-init-registry.yml` so the zot htpasswd file is built with
# `printf '%s' "$TOKEN" | htpasswd -Bin ...` (file born 0600) and the divergence probe verifies with
# `htpasswd -vi`. The registry host is cloud-init-only (ADR-096), so the running host is NOT changed by the
# merge itself: the merge fires registry-host-replace-dispatch.yml, which then replaces the host unattended.
# This probe reads the evidence that the REPLACED host runs the converted boot block: a dispatcher run that
# succeeded after the merge, AND SOLEUR_ZOT_DISK heartbeat rows newer than the merge, on a boot_id different
# from the pre-merge host's, whose `htpasswd_pull_matches` and `htpasswd_push_matches` are both `true` (the
# hashes the new boot block wrote verify against the CURRENT tokens) and whose `zot_image_digest` is real.
# A changed boot_id ALONE is not delivery evidence: the registry self-reboots (private-NIC guard), and an
# unreplaced old host reports matches=true from its OLD argv-built file under a fresh boot_id.
#
# PURE VERDICT EMITTER (followthrough-convention.md): no writes, no `gh issue close`, no comments; safe under
# the sweeper's dry_run and its closed-set re-runs.
#
# EXIT CONTRACT (sweep-followthroughs.sh maps the code to the heading an operator reads):
#   0 = PASS               delivered and measured good (see PASS below).
#   1 = FAIL               the replaced host reports a diverged or unverifiable htpasswd (`false`/`unknown`),
#                          or no real image digest, on every one of >= 3 rows of the new boot: the conversion
#                          shipped a host that cannot authenticate pulls.
#   2 = NOT YET            the PR is not merged, no row newer than the merge exists, the newest boot is still the
#                          pre-merge boot, no dispatcher run has succeeded since the merge, or a guard
#                          (credentials, query, decode) did not pass. Bounded: past 24h from the merge it becomes 3.
#   3 = CANNOT ESTABLISH   the pre-merge boot_id was never recorded in the PR body, no usable boot_id exists, or a
#                          NOT YET outlived 24h from the merge (`stale_*`).
#   5 = ACTION REQUIRED    the dispatcher posted a failure verdict on the PR after the merge (`kind=` below) and
#                          the probe has no PASS to outrank it.
#
# WHAT IT READS.
#   * `gh pr list --head <branch> --state merged` for the merge time, and `gh run list --workflow
#     registry-host-replace-dispatch.yml` for a run that SUCCEEDED after it (the sweeper job carries
#     `actions: read`, #8450; other probes read run data under it).
#   * The PR body's `Pre-merge boot_id: <uuid>` line (recorded by the pipeline before the PR was marked ready).
#     It must be a bare line: a bulleted, bolded or backticked uuid does not parse and exits 3.
#   * The PR's issue comments, for the dispatcher's `<!-- registry-delivery run=N kind=K -->` markers. A success
#     posts NO verdict comment, so the absence of one is not evidence. ANY failure-kind marker after the merge
#     escalates (exit 5) -- but only while the probe has no PASS: a refusal that a later re-fire resolved leaves
#     its comment behind forever, so measured success outranks it. The comment author is not filtered: a forged
#     marker can only ESCALATE to a human, never close the tracker (and a forged `kind=ok` cannot mask a real
#     failure marker, because every failure kind is considered, not just the last marker).
#   * scripts/betterstack-query.sh (SOLEUR_ZOT_DISK rows), through scripts/lib/zot-telemetry-parse.sh.
#
# TRUSTED REGION. Every field a verdict keys on is read from the text BEFORE the first ` zot_last_err=`
# (free text from a container log, attacker-influenceable on the private net). The two-hop `raw` envelope is
# decoded first (betterstack-query.sh documents it double-encoded) and only rows carrying the direct-POST
# producer envelope are used (rows merely QUOTING the marker are not evidence in either direction). The cut is
# done inline rather than through zot_trusted_region() because it must follow the double decode and the `dt`
# sort this probe needs; the discipline (cut at the FIRST occurrence) is the same.
#
# TIME. Better Stack's `dt` is `YYYY-MM-DD HH:MM:SS[.ffffff]` (space, no zone); gh's `mergedAt` is
# `YYYY-MM-DDTHH:MM:SSZ`. A raw string compare sorts every same-UTC-day row BEFORE the merge (space < `T`), so
# `dt` is normalised to the `T...Z` second-precision form before it is compared.
#
# PASS REQUIRES THREE GOOD ROWS on the new boot (not necessarily consecutive; a transient `unknown` among them is
# tolerated): Better Stack source 2457081 is shared and its ingest token is shared, so one producer-shaped row is
# cheap to forge; three good ticks on one fresh boot_id plus a successful dispatcher run is the adequate-authority
# bar the sibling registry probes use for "stop waiting". The residual (a holder of that token can still forge
# three rows in one second, and nothing enforces a minimum spacing) is the same one ADR-096 records; closing THIS
# tracker on it costs a hardening issue its auto-close, nothing more.
#
# WAITING IS BOUNDED. A NOT YET that outlives 24h from the merge becomes CANNOT ESTABLISH (exit 3, `stale_*`), so a
# replace that never lands without posting a verdict surfaces to a human instead of reading "waiting" forever.
#
# Secrets: GH_TOKEN, BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
#
# Tracker directive (goes in the #10119 issue body, at column 0; `earliest=` is the filing time because the
# merge time is unknown pre-merge, and this probe exits 2 until the PR is merged):
#   <!-- soleur:followthrough script=scripts/followthroughs/registry-htpasswd-stdin-10119.sh earliest=2026-10-14T00:00:00Z secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->

set -uo pipefail

# XTRACE REFUSAL (#7797). This probe binds BETTERSTACK_QUERY_PASSWORD and GH_TOKEN; tracing echoes a command
# AFTER expansion, so a credential would reach the transcript the moment it is used. Refuse to run traced.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
PARSE_LIB="$REPO_ROOT/scripts/lib/zot-telemetry-parse.sh"
BRANCH="feat-one-shot-10119-registry-htpasswd-stdin"
REPO="${GH_REPO:-jikig-ai/soleur}"
DISPATCH_WORKFLOW="registry-host-replace-dispatch.yml"
FAIL_KINDS='refused|dispatch-failed|apply-failed|unverified|cancelled|gate-failed|undetermined'
NEED_ROWS=3
STALE_AFTER_S=86400
KIND=""
MERGED_AT=""

# Leave a NOT YET (2) or CANNOT ESTABLISH (3) verdict. A dispatcher failure marker escalates to ACTION REQUIRED
# first; a 2 that has outlived STALE_AFTER_S from the merge becomes a 3. Only reached where the probe has no PASS.
leave() { # <code> <branch-label> <message...>
  local code="$1" label="$2"; shift 2
  if [[ -n "$KIND" ]]; then
    echo "ACTION REQUIRED [branch=dispatcher_verdict kind=$KIND]: the registry-host-replace dispatcher posted a '$KIND' verdict on the PR after the merge." >&2
    echo "           Read knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md § Reading a verdict for the next action." >&2
    exit 5
  fi
  if [[ "$code" == 2 && -n "$MERGED_AT" ]]; then
    local merged_s now_s
    merged_s="$(date -u -d "$MERGED_AT" +%s 2>/dev/null)" || merged_s=""
    now_s="$(date -u +%s)"
    if [[ "$merged_s" =~ ^[0-9]+$ ]] && (( now_s - merged_s > STALE_AFTER_S )); then
      echo "CANNOT ESTABLISH [branch=stale_$label]: still waiting more than 24h after the merge ($MERGED_AT); a human must look (was the replace fired, did it land?)." >&2
      exit 3
    fi
  fi
  case "$code" in 2) printf 'NOT YET [branch=%s]: %s\n' "$label" "$*" >&2 ;; *) printf 'CANNOT ESTABLISH [branch=%s]: %s\n' "$label" "$*" >&2 ;; esac
  exit "$code"
}

if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  echo "NOT YET [branch=creds_unset]: the Better Stack read credentials are not in this run's environment." >&2
  exit 2
fi

# ── the merge ──────────────────────────────────────────────────────────────────────────────────
PR_JSON="$(gh pr list --repo "$REPO" --head "$BRANCH" --state merged --json number,mergedAt,body --limit 1 2>/dev/null)" || {
  echo "NOT YET [branch=gh_pr_list_failed]: could not list the merged PR for $BRANCH." >&2; exit 2; }
PR_NUM="$(jq -r '.[0].number // empty' <<<"$PR_JSON" 2>/dev/null)"
MERGED_AT="$(jq -r '.[0].mergedAt // empty' <<<"$PR_JSON" 2>/dev/null)"
if [[ -z "$PR_NUM" || -z "$MERGED_AT" ]]; then
  MERGED_AT=""
  echo "NOT YET [branch=not_merged]: no merged PR for $BRANCH yet. The host replace has not been fired." >&2
  exit 2
fi
[[ "$PR_NUM" =~ ^[0-9]+$ ]] || { echo "NOT YET [branch=pr_number_unparseable]" >&2; exit 2; }

PRE_BOOT="$(jq -r '.[0].body // ""' <<<"$PR_JSON" | sed -n 's/^[[:space:]]*Pre-merge boot_id:[[:space:]]*\([0-9a-fA-F-]\{8,\}\)[[:space:]]*$/\1/p' | head -1)"
if [[ -z "$PRE_BOOT" ]]; then
  echo "CANNOT ESTABLISH [branch=no_pre_boot]: PR #$PR_NUM's body carries no 'Pre-merge boot_id: <uuid>' line, so a fresh-row check cannot" >&2
  echo "           tell the replaced host from the old one (the old host reports htpasswd matches=true every 5 minutes today)." >&2
  exit 3
fi

# ── dispatcher failure verdicts (escalate only while there is no PASS; see leave()) ───────────────
# EVERY failure-kind marker counts (not just the last marker), so a forged `kind=ok` posted after a genuine
# failure cannot mask it.
KIND="$(gh api --paginate --slurp "repos/$REPO/issues/$PR_NUM/comments?per_page=100" 2>/dev/null \
  | jq -r --arg after "$MERGED_AT" --arg kinds "^($FAIL_KINDS)\$" '[.[][] | select(.created_at >= $after) | .body | capture("<!-- registry-delivery run=[0-9]+ kind=(?<k>[a-z-]+)") | .k | select(test($kinds))] | last // ""' 2>/dev/null)" || KIND=""
[[ "$KIND" =~ ^($FAIL_KINDS)$ ]] || KIND=""

# ── the heartbeat rows ─────────────────────────────────────────────────────────────────────────
[[ -r "$PARSE_LIB" && -r "$QUERY" ]] || leave 2 tooling_missing "the query script or the parse library is unreadable."
# shellcheck source=../lib/zot-telemetry-parse.sh
. "$PARSE_LIB"

RAWOUT="$(bash "$QUERY" --since 24h --grep SOLEUR_ZOT_DISK --limit 500 2>/dev/null)" || leave 2 query_failed "betterstack-query.sh exited non-zero."
ENVELOPE="$(printf '%s\n' "$RAWOUT" | zot_envelope_anchor)"
if [[ -z "$ENVELOPE" ]]; then
  leave 2 no_producer_rows "no SOLEUR_ZOT_DISK row with the direct-POST producer envelope in the window (rows quoting the marker do not count)."
fi

# Decode both hops, carry a NORMALISED `dt`, keep only rows newer than the merge, and cut each row at its free-text tail.
TRUSTED="$(printf '%s\n' "$ENVELOPE" \
  | jq -r --arg after "$MERGED_AT" 'def nd: (. // "") | sub(" ";"T") | sub("\\.[0-9]+";"") | sub("(Z|[+-]00:?00)$";"") | . + "Z";
      select(.raw != null) | [(.dt | nd), (((.raw | fromjson?) // {}) | (.message // ""))] | select(.[0] > $after) | @tsv' 2>/dev/null \
  | sort | cut -f2- | grep -F 'SOLEUR_ZOT_DISK' | sed 's/ zot_last_err=.*//' || true)"
if [[ -z "$TRUSTED" ]]; then
  leave 2 no_row_after_merge "no decodable SOLEUR_ZOT_DISK row newer than the merge ($MERGED_AT)."
fi

NEW_BOOT="$(printf '%s\n' "$TRUSTED" | zot_newest_boot)"
if [[ -z "$NEW_BOOT" ]]; then
  leave 3 no_boot_id "rows newer than the merge exist but none carries a real boot_id (absent or the 'unknown' sentinel)."
fi
if [[ "$NEW_BOOT" == "$PRE_BOOT" ]]; then
  leave 2 still_pre_merge_boot "the newest boot_id is still the pre-merge host's. The replace has not landed (or was refused: see the dispatcher verdict)."
fi

SCOPED="$(printf '%s\n' "$TRUSTED" | zot_scope_to_boot "$NEW_BOOT")"
N_ROWS="$(printf '%s\n' "$SCOPED" | grep -c . || true)"
N_GOOD="$(printf '%s\n' "$SCOPED" | grep -F ' htpasswd_pull_matches=true' | grep -F ' htpasswd_push_matches=true' | grep -vE ' zot_image_digest=(unknown|none|-)( |$)' | grep -cE ' zot_image_digest=[0-9a-f]{12}' || true)"
N_BAD="$(printf '%s\n' "$SCOPED" | grep -cE ' htpasswd_(pull|push)_matches=(false|unknown)( |$)' || true)"

# FAIL needs a full window of evidence, all of it bad: one `unknown` row is a boot-time race or a Doppler hiccup,
# not proof the conversion broke the host. A window with no good row at all is either diverged/unverifiable
# htpasswd (N_BAD > 0) or true/true with no real digest (N_BAD == 0); both are a host that cannot serve pulls.
if (( N_GOOD == 0 )) && (( N_ROWS >= NEED_ROWS )); then
  if (( N_BAD > 0 )); then
    echo "FAIL [branch=htpasswd_not_matching]: the replaced host (new boot) reports a diverged or unverifiable htpasswd on $N_BAD of $N_ROWS row(s) and no good row." >&2
    echo "           The converted boot block built a file the divergence probe cannot verify against the current tokens. Revert the PR and re-fire the replace." >&2
  else
    echo "FAIL [branch=no_real_digest]: the replaced host (new boot) reports $N_ROWS row(s) with htpasswd matching but no real zot_image_digest on any." >&2
    echo "           zot is not serving the pinned image. Read the SOLEUR_ZOT_DISK zot_image_fetch fields, then revert or re-fire the replace." >&2
  fi
  exit 1
fi

if (( N_GOOD >= NEED_ROWS )); then
  # A boot_id change alone is not delivery: require a dispatcher run that SUCCEEDED after the merge.
  RUNS_OK="$(gh run list --repo "$REPO" --workflow "$DISPATCH_WORKFLOW" --limit 30 --json conclusion,createdAt 2>/dev/null \
    | jq -r --arg after "$MERGED_AT" '[.[] | select(.conclusion == "success" and .createdAt >= $after)] | length' 2>/dev/null)" || RUNS_OK=""
  if ! [[ "$RUNS_OK" =~ ^[0-9]+$ ]]; then
    leave 2 runs_query_failed "could not list $DISPATCH_WORKFLOW runs, so a new boot_id cannot be told from a reboot of the old host."
  fi
  if (( RUNS_OK == 0 )); then
    leave 2 no_successful_dispatch_run "$N_GOOD good row(s) on a new boot, but no $DISPATCH_WORKFLOW run has succeeded since the merge: this may be a reboot of the OLD host."
  fi
  echo "PASS [branch=delivered]: $N_GOOD of $N_ROWS row(s) on the new boot (a different host from the pre-merge one) report htpasswd_pull_matches=true, htpasswd_push_matches=true and a real zot_image_digest, and a $DISPATCH_WORKFLOW run succeeded after the merge."
  exit 0
fi
leave 2 awaiting_rows "the new boot has $N_GOOD good row(s) of $N_ROWS ($N_BAD bad; $NEED_ROWS good needed, one per 5-minute tick)."
