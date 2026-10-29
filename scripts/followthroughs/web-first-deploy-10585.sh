#!/usr/bin/env bash
# Standing follow-through watchdog for #10585 — a web-host replace/create
# verifies the replacement host's FIRST deploy, not just its boot.
#
# WHY THIS EXISTS. The `web_host_replace`/`web_host_create` dispatch jobs in
# apply-web-platform-infra.yml end at boot-trail verification: once
# fresh-host-boot-trail.sh confirms `fresh_boot_ready`, the host is declared
# provisioned and nothing afterward checks whether its first deploy ever
# completes. The #8743 fchmodat2 defect broke web-2's deploys on BOTH of its
# replacements (born 2026-09-25, re-replaced 2026-09-30) with no signal — a
# host that never deploys at all emits nothing any gate reads, and the
# release-time `Verify peer deploy completion` step (#10577) covers only hosts
# a release fans out to, inside that run's poll window. The residual arm is a
# CLOCK-BOUNDED obligation: every proven-fresh host still in var.web_hosts owes
# one Deploy-succeeded-class journald row within 2 days of its newest boot.
#
# SHAPE — STANDING, NOTIFY-ONLY, SELF-DERIVING. One permanently-open tracker,
# zero per-replace machinery: the probe derives the owed population from the
# dispatch history every sweep. It never exits 0 (the tracker must never
# close — CLOSED_LOOKBACK_DAYS=14 would retire the check ~14d after any
# closure; the 2026-10-15 dormancy trap) and never exits 1 (FAIL reads as
# "should not close", not this shape). POPULATION EXPIRY: an obligation whose
# newest proven boot is older than POPULATION_WINDOW_S (30 days — the -L cap of
# the dispatch-history read) leaves the population; the bound is deliberate and
# is reported (the NOT YET line names the owed count and the window), never
# silent.
#
# ALGORITHM:
#   Step 1 (population) — enumerate apply-web-platform-infra.yml
#     workflow_dispatch runs of the last 30d; for each completed run read its
#     web_host_replace/web_host_create jobs; for each such job parse the
#     EMITTED lines of the `Surface fresh-host Sentry breadcrumb trail` step
#     (awk -F'\t': field 2 = step name, field 3 = "<ts> <content>"; ANSI-prefixed
#     echoed `run:` source is excluded — the #9905 trap: echoed source carries
#     the UNEXPANDED `var.web_hosts["${WEB_HOST_KEY_RAW}"]`, only the emitted
#     line carries the resolved key). A host is owed only when the trail
#     emitted BOTH `web-host-(replace|create) <key> — fresh-host Sentry
#     pointer` AND `fresh-host boot reached fresh_boot_ready` — a `booted
#     DARK` trail contributes nothing (that failure is already loud; the job
#     reds), and a `complete_no_readiness` trail (booted; `cloud_init_complete`
#     seen but no `fresh_boot_ready`/`fresh_boot_not_ready_*` verdict emitted)
#     contributes nothing either — it never emits the ready anchor this arm
#     parses and the run already surfaces it as a warning. Job conclusion is
#     NOT the boot verdict (#6995). Per host key keep only the NEWEST proven
#     boot + timestamp + run URL — a re-replace supersedes the earlier
#     obligation (web-2 was replaced twice in 5 days).
#   Step 2 (roster) — a key is owed only while still declared in
#     var.web_hosts: grep apps/web-platform/infra/variables.tf for
#     `^[[:space:]]*"?<key>"?[[:space:]]*=[[:space:]]*{` — the same shape the
#     job's own membership check uses. A replaced-then-retired host owes
#     nothing.
#   Step 3 (verdict) — per owed host, one Better Stack query (hot remote() +
#     s3Cluster archive UNION; a real span needs both) scoped
#     `JSONExtractString(raw,'host_name') = 'soleur-<key>'` AND
#     `dt >= boot_ts`:
#       control_rows = ci-deploy/webhook sid rows (channel aliveness),
#       marker_rows  = Deploy-succeeded-class rows:
#         raw LIKE '%Deploy succeeded%' OR '%INNGEST_HEALTH_CHECK%' OR
#         '%BWRAP_USERNS_SYSCTL_%' OR '%PLUGIN_SEED_PROBE%' — each reachable
#         only past a completed seed+canary+swap (same set #8743's probe
#         grades). A marker must POSTDATE the boot it accounts for —
#         per-boot dt bound, not a bare count (the 2026-10-28 stale-evidence
#         learning).
#     marker >= 1                    -> accounted
#     marker = 0, now <  boot+2d     -> pending (still quiet)
#     marker = 0, now >= boot+2d     -> OVERDUE -> ACTION REQUIRED. The comment
#         names host key, boot ts, dispatch run URL and control_rows so the
#         reader sees "host dark" vs "host alive, deploy failing". control=0
#         past the deadline is still exit 5 — a fresh host emitting nothing to
#         the deploy-side channel IS the incident shape, not a clean zero.
#   Step 4 (verdict order) — every owed host is graded BEFORE a verdict is
#     chosen: a transport failure on one host records UNMEASURED and the loop
#     continues, so a sibling's unmeasurable state can never mask a real
#     overdue on another. Final precedence: any OVERDUE -> 5, else any
#     UNMEASURED -> 3, else NOT YET -> 2.
#
# RESIDUALS, stated: (1) `gh run view --job --log` reads the job's LATEST
#   attempt — a re-run's earlier trail is not visible; the newest attempt's
#   trail is what is graded, consistent with newest-boot-wins. (2) The verdict
#   UNION (hot remote() + s3Cluster archive) must answer inside
#   betterstack-query.sh's `curl --max-time 60` transport ceiling — a scan that
#   outruns it reads CANNOT ESTABLISH, never a quiet pass. (3) A
#   success-conclusion job whose trail step emitted zero parseable lines reads
#   CANNOT ESTABLISH: a broken parse channel is measurable, not a quiet pass.
#
# Exit semantics (sweep-followthroughs.sh rc->word map, notify-only subset):
#   5 = ACTION REQUIRED   an owed host's first deploy is overdue
#   2 = NOT YET           the standing quiet state — all accounted/pending,
#                         or nothing owed
#   3 = CANNOT ESTABLISH  credentials unset, gh/jq/awk/date/grep/sort missing
#                         or failing, bash < 4, variables.tf missing, the
#                         dispatch history hitting the -L cap (a possibly
#                         truncated 30d window), a success job with an
#                         unparseable trail, or the verdict-query transport
#                         failed — never a quiet 2 for an unmeasured host
#   78 = refused to run under xtrace with a live credential bound (#7797)
#   (0 and 1 are NEVER taken — asserted by the suite's property sweep.)
#
# Required env: GH_TOKEN (gh reads), BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}
#   — all four already bound in scheduled-followthrough-sweeper.yml `env:`.
#   Test seams: FT10585_QUERY_SH (query transport), FT10585_GH (gh binary
#   name), FT10585_REPO, FT10585_VARS_TF.
#
# Directive:
#   <!-- soleur:followthrough script=scripts/followthroughs/web-first-deploy-10585.sh earliest=<merge-timestamp-ISO8601Z> secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# RETIREMENT: the tracker is STANDING/notify-only by design — ending it is an
# operator act (close the issue AND remove the `follow-through` label, per
# followthrough-convention.md). When it ends, delete this file and its
# .test.sh, drop the `run_suite "scripts/web-first-deploy-10585"` line in
# scripts/test-all.sh, drop the regenerated row in scripts/suite-shard-legs.tsv
# (re-run `python3 scripts/regenerate-shard-manifest.py --incremental --write`),
# drop the duration-floor row in scripts/suite-durations.tsv, remove the
# directive from the standing tracker's body, and unwind the discoverability
# mentions: the `First-deploy verification` echo lines in BOTH the
# web_host_replace AND web_host_create Dispatch summaries
# (apply-web-platform-infra.yml), the lines in web-host-replace.md and
# web-host-birth.md §Verify the result, and the ADR-148 2026-10-29 addendum.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail

# Refuse to run under xtrace with a live credential set (#7797): tracing prints
# expanded commands, and the tokens ride them.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac
# never-0/never-1 backstop (followthrough-convention.md, post-#8296): under
# `set -u` an unguarded expansion aborts with status 1 — the sweeper's FAIL
# verb — and an early `exit 0` would close the standing tracker. This trap
# converts any unplanned 0/1 landing into CANNOT ESTABLISH so the invariant
# holds structurally rather than by review. It sits DIRECTLY after the xtrace
# refusal with nothing executable in between; the suite pins the ordering,
# exactly-one-trap, and no exec/kill.
# shellcheck disable=SC2154  # rc is assigned at trap-fire time inside the same string
trap 'rc=$?; case "$rc" in 0|1) printf "CANNOT ESTABLISH: unplanned exit path (rc=%s)\n" "$rc" >&2; exit 3;; esac' EXIT
export LC_ALL=C

REPO="${FT10585_REPO:-jikig-ai/soleur}"
WORKFLOW="apply-web-platform-infra.yml"
STEP="Surface fresh-host Sentry breadcrumb trail"
FIRST_DEPLOY_DEADLINE_S=172800   # 2 days — mirrors #8743's earliest=merge+2d convention
POPULATION_WINDOW_S=2592000      # 30 days of dispatch history
RUN_LIST_LIMIT=100               # gh run list page cap — a result of exactly this
                                 # size may be a truncated 30d window

for v in GH_TOKEN BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause).\n' "$v" >&2
    exit 3
  fi
done

GH="${FT10585_GH:-gh}"
for b in "$GH" jq awk date grep sort; do
  if ! command -v "$b" >/dev/null 2>&1; then
    printf 'CANNOT ESTABLISH: %s is not on PATH — cannot enumerate or grade.\n' "$b" >&2
    exit 3
  fi
done
if (( BASH_VERSINFO[0] < 4 )); then
  printf 'CANNOT ESTABLISH: bash >= 4 is required (the owed-boot map is an associative array); this is bash %s.\n' "${BASH_VERSION:-unknown}" >&2
  exit 3
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="${FT10585_QUERY_SH:-$SCRIPT_DIR/../betterstack-query.sh}"
if [ ! -f "$QUERY" ]; then
  printf 'CANNOT ESTABLISH: betterstack-query.sh not found at %s\n' "$QUERY" >&2
  exit 3
fi
VARS_TF="${FT10585_VARS_TF:-$SCRIPT_DIR/../../apps/web-platform/infra/variables.tf}"
if [ ! -f "$VARS_TF" ]; then
  printf 'CANNOT ESTABLISH: the var.web_hosts roster file is not at %s — the roster gate cannot run.\n' "$VARS_TF" >&2
  exit 3
fi

numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }
# Strip non-printable bytes from any API/log fragment echoed into a verdict
# line (the sweeper sanitize pattern) — a payload must not smuggle control
# bytes or markup into the tracker comment.
san() { printf '%s' "${1:-}" | LC_ALL=C tr -c '[:print:]\n\t' '?'; }
ts_to_epoch() { # <ISO-8601Z, fraction tolerated> -> epoch
  local t="$1"
  t="${t%Z}"; t="${t%%.*}"
  date -u -d "${t}Z" +%s 2>/dev/null
}
host_name_for() { # <key> -> journald host_name (web-1's live name is the legacy soleur-web-platform)
  if [[ "$1" == "web-1" ]]; then printf 'soleur-web-platform'; else printf 'soleur-%s' "$1"; fi
}

NOW_EPOCH="$(date -u +%s)"
if ! numeric "$NOW_EPOCH"; then
  printf 'CANNOT ESTABLISH: date -u +%%s did not return an epoch (got: %s).\n' "$(san "${NOW_EPOCH:0:60}")" >&2
  exit 3
fi
SINCE_ISO="$(date -u -d "@$((NOW_EPOCH - POPULATION_WINDOW_S))" '+%Y-%m-%dT%H:%M:%SZ')"

# ── Step 1: the owed population ─────────────────────────────────────────────
runs_json=$("$GH" run list --repo "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch \
  --created ">=${SINCE_ISO}" -L "$RUN_LIST_LIMIT" --json databaseId,createdAt,status,conclusion 2>/dev/null) || {
  printf 'CANNOT ESTABLISH: gh run list failed for %s (API/auth — GH_TOKEN is declared but the read did not complete).\n' "$WORKFLOW" >&2
  exit 3; }

ids=$(printf '%s' "$runs_json" | jq -r '.[] | select(.status == "completed") | .databaseId' 2>/dev/null) || {
  printf 'CANNOT ESTABLISH: unparseable gh run list JSON: %s\n' "$(san "${runs_json:0:200}")" >&2
  exit 3; }

# A result set of exactly the -L cap may be a TRUNCATED 30d window — an owed
# host could sit beyond the cap and drop silently. Per the never-quiet-on-
# unmeasured doctrine that is CANNOT ESTABLISH, not a smaller population.
n_runs=$(printf '%s' "$runs_json" | jq -r 'length' 2>/dev/null) || n_runs=""
if [[ "$n_runs" == "$RUN_LIST_LIMIT" ]]; then
  printf 'CANNOT ESTABLISH: gh run list returned exactly the -L %s cap for %s — the 30d population window may be truncated and an owed host silently dropped; refusing to grade a possibly-incomplete population.\n' "$RUN_LIST_LIMIT" "$WORKFLOW" >&2
  exit 3
fi

declare -A BOOT_EPOCH=() BOOT_ISO=() RUN_URL=()
for id in $ids; do
  if ! [[ "$id" =~ ^[0-9]+$ ]]; then
    printf 'CANNOT ESTABLISH: unexpected run id %s from gh run list.\n' "$(san "$id")" >&2
    exit 3
  fi
  # ONE REST call per run (the retired `gh run view --json jobs` fanned out to
  # ~3): the jobs list, filtered server-shape to "<job-id>\t<conclusion>".
  jobs_tsv=$("$GH" api "repos/${REPO}/actions/runs/${id}/jobs?per_page=100" \
    --jq '.jobs[] | select((.name == "web_host_replace" or .name == "web_host_create") and (.conclusion // "") != "" and (.conclusion // "") != "skipped") | "\(.id)\t\(.conclusion)"' \
    2>/dev/null) || {
    printf 'CANNOT ESTABLISH: cannot read the jobs of run %s.\n' "$id" >&2
    exit 3; }
  while IFS=$'\t' read -r jid jcon; do
    [[ -n "$jid" ]] || continue   # empty response = no qualifying job in this run
    if ! [[ "$jid" =~ ^[0-9]+$ ]]; then
      printf 'CANNOT ESTABLISH: unexpected job id %s in the jobs response of run %s.\n' "$(san "$jid")" "$id" >&2
      exit 3
    fi
    log=$("$GH" run view --repo "$REPO" --job "$jid" --log 2>/dev/null) || {
      printf 'CANNOT ESTABLISH: cannot read the log of job %s (run %s).\n' "$jid" "$id" >&2
      exit 3; }
    # The trail step's own output: field 2 is the step name, field 3 is
    # "<ts> <content>". Echoed `run:` source begins with an ANSI escape AFTER
    # the timestamp — drop it; only emitted lines carry a resolved host key.
    trail=$(awk -F'\t' -v step="$STEP" '
      index($2, step) == 1 {
        line = $3; sub(/^[^ ]+ /, "", line)
        if (substr(line, 1, 1) == sprintf("%c", 27)) next
        ts = $3; sub(/ .*/, "", ts)
        printf "%s\t%s\n", ts, line
      }' <<<"$log")
    # Tripwire: a SUCCESS-conclusion job always emits at least the pointer line
    # — zero parseable lines means the parse channel itself broke (log shape
    # drift), which is measurable CANNOT ESTABLISH, not a quiet population of 0.
    if [[ "$jcon" == "success" && -z "$trail" ]]; then
      printf 'CANNOT ESTABLISH: run %s job %s concluded success but the `%s` step emitted zero parseable lines — the log shape drifted; refusing to grade an unmeasured trail.\n' "$id" "$jid" "$STEP" >&2
      exit 3
    fi
    ready_ts=$(awk -F'\t' '$2 ~ /^fresh-host boot reached fresh_boot_ready/ { t=$1 } END { if (t != "") print t }' <<<"$trail")
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      [[ -n "$ready_ts" ]] || continue   # pointer without fresh_boot_ready = no proven boot
      epoch=$(ts_to_epoch "$ready_ts") || epoch=""
      if [[ -z "$epoch" ]]; then
        printf 'CANNOT ESTABLISH: the fresh_boot_ready line timestamp %s did not parse — the boot cannot be clocked.\n' "$(san "$ready_ts")" >&2
        exit 3
      fi
      url="https://github.com/${REPO}/actions/runs/${id}"
      if [[ -z "${BOOT_EPOCH[$key]:-}" || "$epoch" -gt "${BOOT_EPOCH[$key]}" ]]; then
        BOOT_EPOCH[$key]=$epoch; BOOT_ISO[$key]=$ready_ts; RUN_URL[$key]=$url
      fi
    done < <(awk -F'\t' '$2 ~ /^web-host-(replace|create) web-[0-9]+ — fresh-host Sentry pointer/ {
               k=$2; sub(/^web-host-(replace|create) /, "", k); sub(/ .*/, "", k); print k }' \
               <<<"$trail" | sort -u)
  done <<<"$jobs_tsv"
done

# ── Step 2: roster gate — a key is owed only while still in var.web_hosts ────
# "${!BOOT_EPOCH[@]}" is safe under `set -u` because `declare -A` marks the array
# set — the `${!arr[@]+"${!arr[@]}"}` alternate-expansion idiom MISPARSES on
# assoc arrays (it expands to nothing even when keys exist) and must not be used
# here.
declare -a OWED=()
for key in "${!BOOT_EPOCH[@]}"; do
  # Scoped to the `variable "web_hosts" { ... }` block — an unscoped grep would
  # also match a same-named key in a neighbouring variable declaration.
  if awk '/variable "web_hosts" \{/,/^\}/' "$VARS_TF" \
     | grep -qE "^[[:space:]]*\"?${key}\"?[[:space:]]*=[[:space:]]*\{"; then
    OWED+=("$key")
  fi
done
if (( ${#OWED[@]} > 0 )); then
  mapfile -t OWED < <(printf '%s\n' "${OWED[@]}" | sort)
fi

# ── Step 3: per-host verdict (Better Stack journald, hot+archive union) ──────
SRC="(SELECT dt, raw, JSONExtractString(raw,'SYSLOG_IDENTIFIER') AS sid FROM remote(\$BS_TABLE)
      UNION ALL SELECT dt, raw, JSONExtractString(raw,'SYSLOG_IDENTIFIER') AS sid FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)"
MARKER_PRED="raw LIKE '%Deploy succeeded%' OR raw LIKE '%INNGEST_HEALTH_CHECK%' OR raw LIKE '%BWRAP_USERNS_SYSCTL_%' OR raw LIKE '%PLUGIN_SEED_PROBE%'"

# run_one <sql> — prints the single result row, returns the sweep-contract code
# (callers `|| rc=$?`). A multi-line or unparseable body is NOT a zero count.
run_one() {
  local sql="$1" out rc
  out="$(bash "$QUERY" "$sql" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf 'CANNOT ESTABLISH: the verdict query could not run (rc=%s): %s\n' "$rc" "$(san "${out:0:200}")" >&2
    return 3
  fi
  if grep -qiE 'exception|DB::Err|Code: [0-9]+|syntax error' <<<"$out"; then
    printf 'CANNOT ESTABLISH: the query response carries an error alongside the count: %s\n' "$(san "${out:0:200}")" >&2
    return 3
  fi
  local nrows
  nrows=$(printf '%s\n' "$out" | jq -R -r 'fromjson? | select(type == "object") | .' | grep -c '{' || true)
  if [[ "$nrows" != "1" ]]; then
    printf 'CANNOT ESTABLISH: unparseable query result (%s row(s) decoded): %s\n' "$nrows" "$(san "${out:0:200}")" >&2
    return 3
  fi
  printf '%s' "$out"
}

declare -a OVERDUE=() PENDING=() ACCOUNTED=() UNMEASURED=()
for key in ${OWED[@]+"${OWED[@]}"}; do
  epoch=${BOOT_EPOCH[$key]}; iso=${BOOT_ISO[$key]}; url=${RUN_URL[$key]}
  host=$(host_name_for "$key")
  boot_sql=$(date -u -d "@$epoch" '+%Y-%m-%d %H:%M:%S')
  deadline=$((epoch + FIRST_DEPLOY_DEADLINE_S))
  # toDateTime64(..., 3, 'UTC') — the naive-literal convention: a bare
  # toDateTime('YYYY-MM-DD HH:MM:SS') parses in the SESSION TZ and silently
  # shifts the boot bound (the stale-evidence class; web2-plugin-seed-8743.sh
  # carries the same idiom). The `raw LIKE` prefilter is a scan-time cut;
  # JSONExtractString stays the authoritative host check.
  VERDICT_SQL="SELECT
  countIf(sid = 'ci-deploy' OR sid = 'webhook') AS control_rows,
  countIf(${MARKER_PRED}) AS marker_rows
FROM ${SRC}
WHERE dt >= toDateTime64('${boot_sql}', 3, 'UTC')
  AND raw LIKE '%${host}%'
  AND JSONExtractString(raw,'host_name') = '${host}'
FORMAT JSONEachRow"
  run_rc=0
  scan_out=$(run_one "$VERDICT_SQL") || run_rc=$?
  if [[ "$run_rc" -ne 0 ]]; then
    UNMEASURED+=("$key")   # grade the rest — a transport failure must not mask a real overdue
    continue
  fi
  IFS=$'\t' read -r control_rows marker_rows <<<"$(printf '%s\n' "$scan_out" | jq -R -r '
    fromjson? | select(type == "object" and has("control_rows"))
    | [.control_rows, .marker_rows] | map(tostring) | join("\t")')"
  row_ok=1
  for n in "${control_rows:-}" "${marker_rows:-}"; do
    if ! numeric "$n"; then row_ok=0; fi
  done
  if [[ "$row_ok" -ne 1 ]]; then
    printf 'CANNOT ESTABLISH: unparseable verdict row for %s: %s\n' "$host" "$(san "${scan_out:0:300}")" >&2
    UNMEASURED+=("$key")
    continue
  fi
  if [[ "$marker_rows" -ge 1 ]]; then
    ACCOUNTED+=("$key")
  elif (( NOW_EPOCH < deadline )); then
    PENDING+=("$key")
  else
    OVERDUE+=("${key}|${host}|${iso}|${url}|${control_rows}")
  fi
done

# Verdict precedence: any real OVERDUE outranks unmeasured siblings (exit 5
# over exit 3) — a transport failure on one host must never mask a proven
# overdue on another.
if (( ${#OVERDUE[@]} > 0 )); then
  for o in "${OVERDUE[@]}"; do
    IFS='|' read -r k h b u c <<<"$o"
    printf 'ACTION REQUIRED: %s (%s) was proven fresh-booted at %s and shows NO Deploy-succeeded-class journald row at/after its boot — the first deploy is overdue past the %ss deadline.\n' "$h" "$k" "$b" "$FIRST_DEPLOY_DEADLINE_S" >&2
    printf '  run: %s\n' "$u" >&2
    if [[ "$c" -gt 0 ]]; then
      printf '  control_rows=%s since the boot: the deploy-side channel is ALIVE — the host simply never completed a deploy.\n' "$c" >&2
    else
      printf '  control_rows=0 since the boot: the deploy-side channel itself is DARK for this host — that is the incident shape, not a clean zero.\n' >&2
    fi
  done
  printf 'A green boot is not a deployed host — see §Verify the result of BOTH knowledge-base/engineering/operations/runbooks/web-host-replace.md AND web-host-birth.md (this arm covers replaces and births alike), plus the #8743 postmortem.\n' >&2
  if (( ${#UNMEASURED[@]} > 0 )); then
    printf '  note: %s further owed host(s) (%s) failed to measure — they remain CANNOT ESTABLISH inside this ACTION REQUIRED.\n' "${#UNMEASURED[@]}" "${UNMEASURED[*]}" >&2
  fi
  exit 5
fi

if (( ${#UNMEASURED[@]} > 0 )); then
  printf 'CANNOT ESTABLISH: the verdict transport/parse failed for %s owed host(s) (%s) — no host was found overdue, but an unmeasured host is never a quiet pass.\n' "${#UNMEASURED[@]}" "${UNMEASURED[*]}" >&2
  exit 3
fi

printf 'NOT YET: owed=%s accounted=%s pending=%s — every proven-fresh web host still in var.web_hosts owes one Deploy-succeeded-class journald row within %ss of its newest boot; obligations older than %ss (the dispatch-history window) leave the population.\n' \
  "${#OWED[@]}" "${#ACCOUNTED[@]}" "${#PENDING[@]}" "$FIRST_DEPLOY_DEADLINE_S" "$POPULATION_WINDOW_S"
exit 2
