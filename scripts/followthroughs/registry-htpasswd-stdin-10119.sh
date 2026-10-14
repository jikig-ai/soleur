#!/usr/bin/env bash
# Follow-through verification for #10119 — the registry template's htpasswd password-on-stdin conversion.
#
# WHAT THIS ANSWERS. PR for #10119 changed `cloud-init-registry.yml` so the zot htpasswd file is built with
# `printf '%s' "$TOKEN" | htpasswd -Bin ...` (file born 0600) and the divergence probe verifies with
# `htpasswd -vi`. The registry host is cloud-init-only (ADR-096), so merging applies NOTHING by itself: the
# merge fires registry-host-replace-dispatch.yml, which replaces the host unattended. This probe reads the
# only evidence that the REPLACED host runs the converted boot block: a SOLEUR_ZOT_DISK heartbeat row, newer
# than the merge, on a boot_id different from the pre-merge host's, whose `htpasswd_pull_matches` and
# `htpasswd_push_matches` are both `true` (the hashes the new boot block wrote verify against the CURRENT
# tokens) and whose `zot_image_digest` is a real digest.
#
# PURE VERDICT EMITTER (followthrough-convention.md): no writes, no `gh issue close`, no comments; safe under
# the sweeper's dry_run and its closed-set re-runs.
#
# EXIT CONTRACT (sweep-followthroughs.sh maps the code to the heading an operator reads):
#   0 = PASS               delivered and measured good (see PASS below).
#   1 = FAIL               the replaced host reports a diverged or unverifiable htpasswd (`false`/`unknown`),
#                          or no real image digest: the conversion shipped a host that cannot authenticate pulls.
#   2 = NOT YET            the PR is not merged, no row newer than the merge exists, the newest boot is still the
#                          pre-merge boot, or a guard (credentials, query, decode) did not pass.
#   3 = CANNOT ESTABLISH   the pre-merge boot_id was never recorded in the PR body, or no usable boot_id exists.
#   5 = ACTION REQUIRED    the dispatcher posted a failure verdict on the PR after the merge (`kind=` below).
#
# WHAT IT READS.
#   * `gh pr list --head <branch> --state merged` for the merge time (Actions runs are NOT queried: the
#     sweeper's token is `contents: read` + `issues: write` and an Actions-runs read 403s under it).
#   * The PR body's `Pre-merge boot_id: <uuid>` line (recorded by the pipeline before the PR was marked ready).
#   * The PR's issue comments, for the dispatcher's `<!-- registry-delivery run=N kind=K -->` markers. A success
#     posts NO verdict comment, so the absence of one is not evidence; a failure kind escalates (exit 5). The
#     comment author is not filtered: a forged marker can only ESCALATE to a human, never close the tracker.
#   * scripts/betterstack-query.sh (SOLEUR_ZOT_DISK rows), through scripts/lib/zot-telemetry-parse.sh.
#
# TRUSTED REGION. Every field a verdict keys on is read from the text BEFORE the first ` zot_last_err=`
# (free text from a container log, attacker-influenceable on the private net). The two-hop `raw` envelope is
# decoded first (betterstack-query.sh documents it double-encoded) and only rows carrying the direct-POST
# producer envelope are used (rows merely QUOTING the marker are not evidence in either direction).
#
# PASS REQUIRES THREE ROWS on the new boot, all good: Better Stack source 2457081 is shared and its ingest
# token is shared, so one producer-shaped row is cheap to forge; three consecutive ticks on one fresh boot_id
# is the same adequate-authority bar the sibling registry probes use for "stop waiting". The residual (a holder
# of that token can still forge three) is the same one ADR-096 records; closing THIS tracker on it costs a
# hardening issue its auto-close, nothing more.
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
FAIL_KINDS='refused|dispatch-failed|apply-failed|unverified|cancelled|gate-failed|undetermined'
NEED_ROWS=3

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

# ── dispatcher failure verdicts (escalate only) ────────────────────────────────────────────────
KIND="$(gh api --paginate --slurp "repos/$REPO/issues/$PR_NUM/comments?per_page=100" 2>/dev/null \
  | jq -r --arg after "$MERGED_AT" '[.[][] | select(.created_at >= $after) | .body | capture("<!-- registry-delivery run=[0-9]+ kind=(?<k>[a-z-]+)") | .k] | last // ""' 2>/dev/null)" || KIND=""
if [[ "$KIND" =~ ^($FAIL_KINDS)$ ]]; then
  echo "ACTION REQUIRED [branch=dispatcher_verdict kind=$KIND]: the registry-host-replace dispatcher posted a '$KIND' verdict on PR #$PR_NUM after the merge." >&2
  echo "           Read knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md § Reading a verdict for the next action." >&2
  exit 5
fi

# ── the heartbeat rows ─────────────────────────────────────────────────────────────────────────
[[ -r "$PARSE_LIB" && -r "$QUERY" ]] || { echo "NOT YET [branch=tooling_missing]: the query script or the parse library is unreadable." >&2; exit 2; }
# shellcheck source=../lib/zot-telemetry-parse.sh
. "$PARSE_LIB"

RAWOUT="$(bash "$QUERY" --since 24h --grep SOLEUR_ZOT_DISK --limit 500 2>/dev/null)" || {
  echo "NOT YET [branch=query_failed]: betterstack-query.sh exited non-zero." >&2; exit 2; }
ENVELOPE="$(printf '%s\n' "$RAWOUT" | zot_envelope_anchor)"
if [[ -z "$ENVELOPE" ]]; then
  echo "NOT YET [branch=no_producer_rows]: no SOLEUR_ZOT_DISK row with the direct-POST producer envelope in the window (rows quoting the marker do not count)." >&2
  exit 2
fi

# Decode both hops, carry `dt`, keep only rows newer than the merge, and cut each row at its free-text tail.
TRUSTED="$(printf '%s\n' "$ENVELOPE" \
  | jq -r --arg after "$MERGED_AT" 'select(.raw != null) | [(.dt // ""), (((.raw | fromjson?) // {}) | (.message // ""))] | select(.[0] > $after) | @tsv' 2>/dev/null \
  | sort | cut -f2- | grep -F 'SOLEUR_ZOT_DISK' | sed 's/ zot_last_err=.*//' || true)"
if [[ -z "$TRUSTED" ]]; then
  echo "NOT YET [branch=no_row_after_merge]: no decodable SOLEUR_ZOT_DISK row newer than the merge ($MERGED_AT)." >&2
  exit 2
fi

NEW_BOOT="$(printf '%s\n' "$TRUSTED" | zot_newest_boot)"
if [[ -z "$NEW_BOOT" ]]; then
  echo "CANNOT ESTABLISH [branch=no_boot_id]: rows newer than the merge exist but none carries a real boot_id (absent or the 'unknown' sentinel)." >&2
  exit 3
fi
if [[ "$NEW_BOOT" == "$PRE_BOOT" ]]; then
  echo "NOT YET [branch=still_pre_merge_boot]: the newest boot_id is still the pre-merge host's. The replace has not landed (or was refused: see the dispatcher verdict)." >&2
  exit 2
fi

SCOPED="$(printf '%s\n' "$TRUSTED" | zot_scope_to_boot "$NEW_BOOT")"
N_ROWS="$(printf '%s\n' "$SCOPED" | grep -c . || true)"
N_GOOD="$(printf '%s\n' "$SCOPED" | grep -F ' htpasswd_pull_matches=true' | grep -F ' htpasswd_push_matches=true' | grep -vE ' zot_image_digest=(unknown|none|-)( |$)' | grep -cE ' zot_image_digest=[0-9a-f]{12}' || true)"
N_BAD="$(printf '%s\n' "$SCOPED" | grep -cE ' htpasswd_(pull|push)_matches=(false|unknown)( |$)' || true)"
if (( N_BAD > 0 )) && (( N_GOOD == 0 )); then
  echo "FAIL [branch=htpasswd_not_matching]: the replaced host (new boot) reports a diverged or unverifiable htpasswd on $N_BAD of $N_ROWS row(s) and no good row." >&2
  echo "           The converted boot block built a file the divergence probe cannot verify against the current tokens. Revert the PR and re-fire the replace." >&2
  exit 1
fi
if (( N_GOOD >= NEED_ROWS )); then
  echo "PASS [branch=delivered]: $N_GOOD of $N_ROWS row(s) on the new boot (a different host from the pre-merge one) report htpasswd_pull_matches=true, htpasswd_push_matches=true and a real zot_image_digest."
  exit 0
fi
echo "NOT YET [branch=awaiting_rows]: the new boot has $N_GOOD good row(s) of $N_ROWS ($NEED_ROWS needed, one per 5-minute tick)." >&2
exit 2
