#!/usr/bin/env bash
# Every decision variable below is assigned by jqv() via printf -v, which shellcheck cannot see
# through (SC2154 fires on each read); the helper is the point, so the warning is disabled file-wide.
# shellcheck disable=SC2154
# #6178 — the ADR-100 Phase-4 exactly-once soak, read by a machine on the day it becomes readable.
#
# TRACKER: **#6178**. NOTIFY-ONLY. This probe never closes the tracker and never reopens it: the
# close authorises the ADR-100 `adopting → accepted` flip and the release of four rollback
# snapshots, which are operator verbs. The sweeper renders this probe's exit codes as words in
# the comment heading (scripts/sweep-followthroughs.sh, `run_one`'s rc→word map) and closes on
# NONE of them.
#
# WHY. The dedicated-host cutover completed 2026-09-15 (ADR-100 addendum 2026-09-15). Its soak —
# seven days of exactly-once cron scheduling on the dedicated host — is what flips the ADR, and
# until this file existed the day-7 reading was an `op=verify` dispatch somebody had to remember,
# with two repo variables set and deleted by hand. The 07-07 extraction plan prescribed a
# follow-through for exactly this wait (`inngest-double-fire-6178.sh`, PASS/FAIL) and it was never
# built. This is that follow-through, in the notify-only vocabulary the close decision requires.
#
# WHAT IT MEASURES. Over the pinned 52-cron population and the open-topped window from SOAK_FROM,
# every (functionID, 1200 s startedAt-bucket) group holding more than one distinct run is a
# finding. Exactly two such groups are EXPLAINED — the 2026-09-17T12:40–13:00Z catch-up after the
# 76-minute no-scheduler window (PR #8252; `op=resume` run 35223389582): cron-ghcr-token-minter
# (`*/20`) ×4 and cron-anthropic-credit-probe (`47 * * * *`) ×2 = exactly the ticks each missed,
# each fired once on resume — one scheduler draining its backlog, not two schedulers (routine_runs
# attribution on #6178 comment 5738682595). They are pinned as EXACT (functionID, bucket, count)
# triples: bucket 1491374 is historical and immutable, so the minter at 5 (or 3) is UNEXPLAINED.
#
# ANCHOR PROVENANCE (ADR-146, runbook inngest-server.md §"Scan window + trust anchor"). SOAK_FROM
# is an `override`-class anchor: bucket_floor(2026-09-15T13:23:00Z) − 2×1200 s, where 13:23:00Z
# is the 09-15 `op=verify` pass (run 34974655656). That pass was ITSELF QUALIFIED — its log reads
# `anchor_source=floor(override)` and `2.6 exactly-once VERIFIED (QUALIFIED) — … population scoped
# to function_ids=[…]`. The day-7 reading inherits both qualifications (an operator-typed anchor
# and a 52-cron population) and is a SOAK reading over the post-verify window, not a re-proof of
# the coexistence region.
#
# SCOPE (op=verify P2-a). The on-host probe reads ONLY the dedicated host's (10.0.1.40) run index.
# It is NOT a web-host double-fire detector; web-1's quiesced shape is the second evidence the
# operator holds before flipping (scripts/inngest-host-state.sh). Accepted residual (P2-c): two
# runs of one tick started more than 20 minutes apart land in different buckets and read clean —
# the host's projection carries no `queuedAt`.
#
# HOW IT READS. The deploy webhook forwards only `from` and `function_ids` to the on-host probe
# (apps/web-platform/infra/hooks.json.tmpl), so the window is open-topped and the ONLY cost
# lever is the POPULATION: the 52 ids are dealt round-robin into 5 slices of ≤ 11 from a
# density-sorted file (inngest-soak-6178.function-ids.txt — the sort IS the balancing lever) so
# no slice approaches the host's 18-page / 1800-run feasibility gate (90 s ÷ 5 s/page × 100). A registry GET first pins the registry at
# REGISTRY_COUNT and requires population ⊆ registry, so a cron registered after 09-15 refuses
# (registry_drift) rather than reading clean.
#
# CREDENTIAL POSTURE. Three secrets, forwarded by the sweeper from the directive's `secrets=`
# clause under `env -i`: WEBHOOK_DEPLOY_SECRET (HMAC over the empty GET body), CF_ACCESS_CLIENT_ID
# and CF_ACCESS_CLIENT_SECRET (the Cloudflare Access pair). The same three serve
# canary-promotion-5875.sh. None is ever printed; the probe emits ids, buckets, counts and slice
# numbers only (AC-NOBODY), and every host-supplied field is shape-validated BEFORE it is printed,
# because the sweeper republishes stdout+stderr verbatim on a public issue.
#
# THREE MECHANISMS ARE NOVEL IN THE PROBE CORPUS, declared here so a reader does not look for
# precedent: (1) the rc-FILTERING EXIT trap — 14 probes trap EXIT for cleanup only and
# git-data-rung2-evidence-capture.sh reads `$?` without rewriting it; this one rewrites every rc
# outside {2,3,5,78} to 3, because a `set -u` abort (rc 1) would be the sweeper's FAIL/reopen
# verb; (2) the `jqv` helper with a `site=` token — per-site rc capture is precedented by
# 7922's `|| cannot_establish` and 8097's `if ! x=$(…)`; the helper is not; (3) the `remedy=`
# output key — siblings use prose tails.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh) — NEVER 0, NEVER 1:
#   2  = NOT YET            a complete, non-vacuous reading taken before SOAK_END.
#   3  = CANNOT ESTABLISH   credentials unset, population/registry/slice unreadable, vacuous,
#                           incomplete, thin, eroded, a failing jq, or ANY unmapped exit.
#   5  = ACTION REQUIRED    at/after SOAK_END: "SOAK CLEAN … flip, release, close" or
#                           "SOAK NOT CLEAN … investigate". Both name the operator verbs.
#   78 = refused to run under xtrace with a live credential (#7797); TRANSIENT to the sweeper.
#   0 and 1 are structurally unreachable: no literal `exit 0`/`exit 1` exists in this file, every
#   jq/curl/date whose output feeds a decision has its rc captured, and the EXIT trap rewrites
#   any other status to 3. A notify-only probe that exits 1 would REOPEN the tracker in the
#   sweeper's closed-set path; one that exits 0 would CLOSE it.
#
# WHY -uo AND NOT -euo. An errexit abort exits 1, which this contract reads as FAIL — the one
# status that reopens. Failures are routed explicitly instead, and the trap backstops the rest.
#
# THE `${VAR:?msg}` FORM IS BANNED HERE (scripts/lint-followthrough-varq-ban.sh rule 1): under the
# sweeper's non-interactive shell that word-expansion aborts with status 1. Required env is named
# literally below.
#
# RETIREMENT: delete this file, inngest-soak-6178.test.sh, inngest-soak-6178.function-ids.txt and
# the `run_suite "scripts/inngest-soak-6178"` line in scripts/test-all.sh no earlier than #6178's
# close + 14 days (the sweeper's closed-set lookback), or accept a daily `missing in repo HEAD`
# stderr line until then. The ADR-100 addendum stays — it is history.

# #7797: refuse to run under xtrace while a live credential is bound. `$-` is tested FIRST and the
# bindings ONLY with `${VAR:+x}` (expands to a literal `x`): a `-n "$VAR"` test would itself print
# the value under `-x` before the refusal fires.
case "$-" in
  *x*)
    if [ -n "${WEBHOOK_DEPLOY_SECRET:+x}" ] || [ -n "${CF_ACCESS_CLIENT_ID:+x}" ] || [ -n "${CF_ACCESS_CLIENT_SECRET:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

set -uo pipefail

# ONE EXIT trap: cleanup + the rc filter. Bash keeps a SINGLE EXIT trap — a later
# `trap 'rm -rf "$WORK"' EXIT` would silently REPLACE this filter and a `set -u` abort would then
# exit 1 (= FAIL, a reopen in closed mode). EXIT-only on purpose: an INT/TERM arm would rewrite a
# signal kill to 3. WORK is assigned ONCE, from a bare `mktemp -d`, so the `rm -rf` operand is
# provably absolute (the P1b ratchet, plugins/soleur/test/fixture-relative-assert.test.sh); a
# failed mktemp leaves it empty and the `-n` guard makes the cleanup a no-op.
WORK="$(mktemp -d)"
on_exit() {
  local rc=$?
  [[ -n "$WORK" ]] && rm -rf "$WORK"
  case "$rc" in
    2|3|5|78) exit "$rc" ;;
    *)
      printf 'CANNOT ESTABLISH: reason=unmapped_exit rc=%s remedy=an unbound variable or a stray non-zero status reached the trap; nothing was decided. Re-run next sweep; if it repeats, read the probe with `bash -n` and the sweeper log.\n' "$rc" >&2
      exit 3 ;;
  esac
}
trap on_exit EXIT

# ── constants ────────────────────────────────────────────────────────────────────────────────
SOAK_FROM=2026-09-15T12:40:00Z      # bucket_floor(09-15 verify pass 13:23:00Z) − 2×PERIOD
SOAK_END=2026-09-22T13:23:00Z       # soak start + 7 days
PERIOD=1200
SLICE_MAX=11
POPULATION_SIZE=52
REGISTRY_COUNT=70
RUN_FLOOR=800                       # half the day-3.6 count (826); a hole that lost > half the window
PROBE_BUDGET_S=420                  # wall-clock cap for the slice loop: the sweeper's job is 15 min for ALL probes
EXPLAINED='[{"functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","bucket":1491374,"count":4},{"functionID":"2e625d3c-0207-569f-b10b-567bc685ad5e","bucket":1491374,"count":2}]'
EXPLAINED_WHY='2026-09-17T12:40–13:00Z catch-up after the 76-minute no-scheduler window (PR #8252, op=resume run 35223389582): cron-ghcr-token-minter (`*/20`) ×4 and cron-anthropic-credit-probe (`47 * * * *`) ×2 = exactly the ticks each missed, each fired once on resume — one scheduler draining its backlog, not two schedulers; recorded on #6178 comment 5738682595'
SNAPSHOTS='398857857, 406654994, 407991378, 411798619'
HOOK_BASE=https://deploy.soleur.ai/hooks
UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$'
BETTERSTACK_HINT='doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_INNGEST_PREFLIGHT --limit 20'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POP_FILE="${INNGEST_SOAK_POPULATION_FILE:-$REPO_ROOT/scripts/followthroughs/inngest-soak-6178.function-ids.txt}"

cannot_establish() { # cannot_establish <reason-and-fields> <remedy>
  printf 'CANNOT ESTABLISH: reason=%s remedy=%s\n' "$1" "$2" >&2
  exit 3
}
# jqv <var> <site> <jq args...> — every jq whose output feeds a decision goes through here, and
# it is called DIRECTLY (never inside `$(…)`): a `cannot_establish` from inside a command
# substitution exits only the SUBSHELL, and under `-uo pipefail` WITHOUT `-e` the assignment
# then continues with an empty value — a `startedAt` fromdateiso8601 cannot parse would fall
# through to a clean verdict (measured while building this file: rc 2 with the jq error on
# stderr). The result lands in the named variable via printf -v.
jqv() {
  local __var="$1" site="$2"; shift 2
  local out rc
  out="$(jq "$@")"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    cannot_establish "jq_failed rc=${rc} site=${site}" "a host-supplied field did not parse at this site; nothing was decided. Re-run next sweep; if it repeats, compare the host probe's emitted shape against op=verify 2.6 (scripts/cutover-inngest.sh)"
  fi
  printf -v "$__var" '%s' "$out"
}

# ── seams (unreachable from a tracker body: the sweeper runs probes under env -i) ────────────
NOW_EPOCH="${INNGEST_SOAK_NOW_EPOCH:-}"
if [[ -n "$NOW_EPOCH" ]]; then
  [[ "$NOW_EPOCH" =~ ^[0-9]+$ ]] || cannot_establish "bad_now_override" "INNGEST_SOAK_NOW_EPOCH must be epoch seconds (digits only); it is a test seam and must be unset under the sweeper"
else
  NOW_EPOCH="$(date -u +%s)"; rc=$?
  [[ "$rc" -eq 0 && "$NOW_EPOCH" =~ ^[0-9]+$ ]] || cannot_establish "clock_unreadable rc=${rc}" "date -u +%s failed on the runner"
fi
SOAK_FROM_EPOCH="$(date -u -d "$SOAK_FROM" +%s)"; rc=$?
[[ "$rc" -eq 0 && "$SOAK_FROM_EPOCH" =~ ^[0-9]+$ ]] || cannot_establish "clock_unreadable rc=${rc} site=soak_from" "GNU date could not parse SOAK_FROM"
SOAK_END_EPOCH="$(date -u -d "$SOAK_END" +%s)"; rc=$?
[[ "$rc" -eq 0 && "$SOAK_END_EPOCH" =~ ^[0-9]+$ ]] || cannot_establish "clock_unreadable rc=${rc} site=soak_end" "GNU date could not parse SOAK_END"

# ── credentials: absent is CANNOT ESTABLISH (3, never 2 — NOT YET is reserved for a reading) ──
missing=""
[[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]] && missing="${missing} WEBHOOK_DEPLOY_SECRET"
[[ -z "${CF_ACCESS_CLIENT_ID:-}" ]] && missing="${missing} CF_ACCESS_CLIENT_ID"
[[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]] && missing="${missing} CF_ACCESS_CLIENT_SECRET"
if [[ -n "$missing" ]]; then
  cannot_establish "credentials_unprovisioned missing:${missing}" "nothing about the host was measured. Confirm the directive's secrets= clause lists all three and that the sweeper workflow env sets them (the same three serve #5875)"
fi

# ── population: exactly POPULATION_SIZE strict-UUID lines, file order preserved ──────────────
[[ -r "$POP_FILE" ]] || cannot_establish "population_malformed cause=unreadable" "the population file is missing or unreadable at ${POP_FILE#"$REPO_ROOT"/}"
pop_lines="$(grep -vE '^[[:space:]]*(#|$)' "$POP_FILE" || true)"
pop_n="$(printf '%s\n' "$pop_lines" | grep -c . || true)"
pop_ok="$(printf '%s\n' "$pop_lines" | LC_ALL=C grep -cE "$UUID_RE" || true)"
pop_u="$(printf '%s\n' "$pop_lines" | LC_ALL=C grep -E "$UUID_RE" | sort -u | grep -c . || true)"
if [[ "$pop_n" -ne "$POPULATION_SIZE" || "$pop_ok" -ne "$POPULATION_SIZE" || "$pop_u" -ne "$POPULATION_SIZE" ]]; then
  cannot_establish "population_malformed lines=${pop_n} uuid=${pop_ok} unique=${pop_u} want=${POPULATION_SIZE}" "the committed population file must hold exactly ${POPULATION_SIZE} distinct UUID lines; regenerate from the run logs named in its header"
fi

[[ -n "$WORK" && -d "$WORK" ]] || cannot_establish "scratch_unavailable" "mktemp -d failed on the runner (TMPDIR full or unwritable)"
printf '%s\n' "$pop_lines" > "$WORK/population.txt"

# ── one request shape (canary-promotion-5875.sh: HMAC over the empty GET body) ───────────────
SIG="$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')"
# hook_get <url> <body-file> → sets HTTP_CODE and CURL_RC (globals — called DIRECTLY, never via
# `$(…)`, which would run it in a subshell and discard both). No `|| echo 000`: curl already
# prints 000 via -w on a transport failure, so an append would yield 000000.
HTTP_CODE=""; CURL_RC=0
hook_get() {
  # --max-time 105 > the host's own bound (DEADLINE 90 s + PAGE_MIN); --connect-timeout bounds a
  # stalled edge. The sweeper runs every probe sequentially under one 15-minute job with no per-probe
  # ceiling, so this probe also enforces PROBE_BUDGET_S below.
  HTTP_CODE="$(curl --disable --noproxy '*' --proto '=https' -sS --connect-timeout 10 --max-time 105 -o "$2" -w '%{http_code}' -X GET \
    -H "X-Signature-256: sha256=$SIG" \
    -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
    -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
    "$1" 2>/dev/null)"
  CURL_RC=$?
}
# classify_body <file> → body_class token. Never prints the body.
classify_body() {
  local f="$1"
  if grep -qF 'inngest-doublefire-probe: FATAL' "$f" 2>/dev/null; then printf 'probe-fatal'
  elif grep -qF 'Error occurred while evaluating hook rules.' "$f" 2>/dev/null; then printf 'hook-rule-mismatch'
  elif grep -qiE '<!DOCTYPE|<html' "$f" 2>/dev/null; then printf 'cf-access-html'
  elif jq -e . "$f" >/dev/null 2>&1; then printf 'json'
  else printf 'other'; fi
}
# excerpt <file> <class> → a printable, angle-bracket-free excerpt safe for a public comment.
excerpt() {
  case "$2" in
    probe-fatal) LC_ALL=C grep -oE 'reason=[a-z_]+( pages_scanned=[0-9]+)?' "$1" | head -1 ;;
    cf-access-html) printf '(html page withheld)' ;;
    *) LC_ALL=C tr -cd '[:print:]' < "$1" | tr -d '<>' | cut -c1-200 ;;
  esac
}

# ── registry-drift gate: the population must still be the registry's cron set ────────────────
hook_get "$HOOK_BASE/inngest-registry-probe" "$WORK/registry.body"; code="$HTTP_CODE"
if [[ "$CURL_RC" -ne 0 || "$code" != "200" ]]; then
  bc="$(classify_body "$WORK/registry.body")"
  cannot_establish "registry_unreadable curl_rc=${CURL_RC} http=${code} body_class=${bc} body_len=$(wc -c < "$WORK/registry.body" | tr -d ' ') body=$(excerpt "$WORK/registry.body" "$bc")" "retry next sweep; hook-rule-mismatch = WEBHOOK_DEPLOY_SECRET rotated (shared with #5875); cf-access-html = the CF-Access pair rotated"
fi
if ! jq -e '(.function_count | type) == "number" and (.function_ids | type) == "array" and all(.function_ids[]; type == "string")' "$WORK/registry.body" >/dev/null 2>&1; then
  cannot_establish "registry_unreadable curl_rc=0 http=200 body_class=$(classify_body "$WORK/registry.body") cause=bad_shape" "the registry probe's projection changed; compare against apps/web-platform/infra/inngest-registry-probe.sh"
fi
jqv reg_count registry_count -r '.function_count' "$WORK/registry.body"
[[ "$reg_count" =~ ^[0-9]+$ ]] || cannot_establish "registry_unreadable cause=bad_count" "function_count is not an integer"
jqv reg_ids_raw registry_ids -r '.function_ids[]' "$WORK/registry.body"
printf '%s\n' "$reg_ids_raw" | LC_ALL=C grep -E "$UUID_RE" | sort -u > "$WORK/registry.ids"
reg_missing="$(LC_ALL=C comm -23 <(sort -u "$WORK/population.txt") "$WORK/registry.ids" | grep -c . || true)"
if [[ "$reg_count" -ne "$REGISTRY_COUNT" || "$reg_missing" -ne 0 ]]; then
  cannot_establish "registry_drift function_count=${reg_count} want=${REGISTRY_COUNT} missing_from_registry=${reg_missing}" "a function was registered or removed since 09-15; the pinned population no longer covers the registry — do not flip; re-derive the cron population (gh workflow run cutover-inngest.yml -f op=registry-probe is read-only) and re-measure"
fi

# ── slices: round-robin over the density-sorted file, ≤ SLICE_MAX ids each ───────────────────
N_SLICES=$(( (POPULATION_SIZE + SLICE_MAX - 1) / SLICE_MAX ))
: > "$WORK/spool.json"
slice_line=""
for (( k = 0; k < N_SLICES; k++ )); do
  kk=$((k + 1))
  csv="$(awk -v n="$N_SLICES" -v k="$k" '(NR-1)%n==k' "$WORK/population.txt" | paste -sd, -)"
  body="$WORK/slice-$kk.body"
  if (( SECONDS > PROBE_BUDGET_S )); then
    cannot_establish "slice_budget_exhausted slice=${kk}/${N_SLICES} elapsed_s=${SECONDS} budget_s=${PROBE_BUDGET_S}" "the earlier slices consumed the probe's wall-clock budget (a stalled edge or a slow host); retry next sweep — the sweeper job caps ALL probes at 15 minutes"
  fi
  hook_get "$HOOK_BASE/inngest-doublefire-probe?from=${SOAK_FROM}&function_ids=${csv}" "$body"; code="$HTTP_CODE"
  bc="$(classify_body "$body")"
  blen="$(wc -c < "$body" 2>/dev/null | tr -d ' ' || echo 0)"
  unreadable() { # unreadable <cause>
    cannot_establish "slice_unreadable slice=${kk}/${N_SLICES} curl_rc=${CURL_RC} http=${code} cause=$1 body_class=${bc} body_len=${blen} body=$(excerpt "$body" "$bc")" "retry next sweep; hmac_mismatch = WEBHOOK_DEPLOY_SECRET rotated (shared with #5875); cf_access = the CF-Access pair; probe_fatal names the host's own reason and the slice to re-sort, and more than a week after day 7 it is the expected page-budget horizon, not a broken probe (this reading stays takeable for roughly one to two weeks after day 7; after that the heaviest slice outgrows the host's page budget and the probe reports CANNOT ESTABLISH until #6178 is closed); bad_run_shape = the host probe's projection changed — compare its emitted shape against op=verify 2.6"
  }
  # The FATAL check precedes any status/jq branch: a future 200-with-FATAL must not read clean.
  [[ "$bc" == "probe-fatal" ]] && unreadable probe_fatal
  [[ "$CURL_RC" -ne 0 ]] && unreadable transport
  if [[ "$code" != "200" ]]; then
    case "$bc" in
      hook-rule-mismatch) unreadable hmac_mismatch ;;
      cf-access-html) unreadable cf_access ;;
      *) unreadable other ;;
    esac
  fi
  jq -e '(.runs | type) == "array"' "$body" >/dev/null 2>&1 || unreadable bad_run_shape
  # Every host-supplied field is shape-validated BEFORE anything from this body is printed.
  jq -e --arg u "$UUID_RE" --arg t "$ISO_RE" \
    'all(.runs[]; (.id | type) == "string" and (.functionID | type) == "string" and (.functionID | test($u)) and ((.startedAt == null) or ((.startedAt | type) == "string" and (.startedAt | test($t)))))' \
    "$body" >/dev/null 2>&1 || unreadable bad_run_shape
  jqv tc "total_count_${kk}" -r '.total_count' "$body"
  # The host emits the enum string "unknown" when page-1 totalCount did not parse; a bash
  # arithmetic test would read that as 0, so this is a regex, never `-gt`.
  [[ "$tc" =~ ^[0-9]+$ ]] || cannot_establish "total_count_unknown slice=${kk}/${N_SLICES}" "re-run next sweep; if it repeats: ${BETTERSTACK_HINT/PREFLIGHT/PREFLIGHT_GATE}"
  jqv nruns "runs_${kk}" '.runs | length' "$body"
  if [[ "$tc" -eq 0 || "$nruns" -eq 0 ]]; then
    cannot_establish "slice_vacuous slice=${kk}/${N_SLICES} total_count=${tc} runs=${nruns}" "gh workflow run cutover-inngest.yml -f op=registry-probe (read-only) and compare its ids against scripts/followthroughs/inngest-soak-6178.function-ids.txt"
  fi
  jqv deduped "deduped_${kk}" '.runs | unique_by(.id) | length' "$body"
  if [[ "$deduped" -lt "$tc" ]]; then
    cannot_establish "slice_incomplete slice=${kk}/${N_SLICES} deduped=${deduped} total_count=${tc}" "re-run next sweep; if it repeats the host's pagination is truncating: ${BETTERSTACK_HINT}"
  fi
  # Spool the .runs ARRAY (never the response object: `jq -s add` over objects keeps only the
  # last slice — the false-clean shape the review caught).
  jqv spool_arr "spool_${kk}" -c '.runs' "$body"
  printf '%s\n' "$spool_arr" >> "$WORK/spool.json"
  slice_line="${slice_line}${slice_line:+ }s${kk}=${tc}"
done

# ── union → dedupe → floors → buckets ────────────────────────────────────────────────────────
jqv runs_all union -s -c '[.[][]] | unique_by(.id)' "$WORK/spool.json"
printf '%s\n' "$runs_all" > "$WORK/runs.json"
jqv runs_n runs_n 'length' "$WORK/runs.json"
jqv active_fns active_fns '[.[].functionID] | unique | length' "$WORK/runs.json"
jqv null_started null_started '[.[] | select(.startedAt == null)] | length' "$WORK/runs.json"
if [[ "$runs_n" -lt "$RUN_FLOOR" ]]; then
  cannot_establish "population_thin runs=${runs_n} floor=${RUN_FLOOR}" "re-run next sweep; if it repeats, the host's run index has a mid-window hole — read the SOLEUR_INNGEST_PREFLIGHT markers: ${BETTERSTACK_HINT}"
fi
jqv min_started min_started -r '[.[] | select(.startedAt != null) | .startedAt] | min // ""' "$WORK/runs.json"
[[ "$min_started" =~ $ISO_RE ]] || cannot_establish "index_eroded min_started=none" "no run carries a startedAt; the host's run index is unreadable for this window: ${BETTERSTACK_HINT}"
min_whole="${min_started%%.*}"; min_whole="${min_whole%Z}Z"
min_epoch="$(date -u -d "$min_whole" +%s)"; rc=$?
[[ "$rc" -eq 0 && "$min_epoch" =~ ^[0-9]+$ ]] || cannot_establish "jq_failed rc=${rc} site=min_started_date" "the earliest startedAt did not parse as ISO-8601"
if [[ "$min_epoch" -gt $((SOAK_FROM_EPOCH + 2 * PERIOD)) ]]; then
  cannot_establish "index_eroded min_started=${min_started} window_head=${SOAK_FROM}" "the host's run index no longer reaches the window's head; any 09-15/16 double-fire would be gone too — do not flip; read the preflight markers: ${BETTERSTACK_HINT}"
fi
# Byte-for-byte the op=verify 2.6 bucketing (scripts/cutover-inngest.sh): null startedAt excluded
# (counted above), fractional seconds stripped, floor(startedAt / PERIOD).
jqv groups groups -c --argjson period "$PERIOD" \
  '[ .[] | select(.startedAt != null) | { fn: .functionID, bucket: ((.startedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) / $period | floor) } ] | group_by([.fn, .bucket]) | map(select(length > 1)) | map({ functionID: .[0].fn, bucket: .[0].bucket, count: length })' \
  "$WORK/runs.json"
# Exact-triple split: explained iff (functionID, bucket, count) EQUALS a pinned triple.
jqv split split -c --argjson ex "$EXPLAINED" \
  '[ .[] | . as $g | . + { explained: any($ex[]; .functionID == $g.functionID and .bucket == $g.bucket and .count == $g.count) } ]' <<<"$groups"
jqv explained_n explained_n '[.[] | select(.explained)] | length' <<<"$split"
jqv unexplained_n unexplained_n '[.[] | select(.explained | not)] | length' <<<"$split"

# bucket_window <bucket> → sets BW="<iso>–<iso>" (a global — called directly, see jqv); the
# bucket is validated as digits before any arithmetic.
BW=""
bucket_window() {
  [[ "$1" =~ ^[0-9]+$ ]] || cannot_establish "jq_failed rc=0 site=bucket_shape" "a computed bucket index was not an integer"
  local a b
  a="$(date -u -d "@$(( $1 * PERIOD ))" +%Y-%m-%dT%H:%M:%SZ)" || cannot_establish "jq_failed rc=$? site=bucket_date" "GNU date could not render a bucket"
  b="$(date -u -d "@$(( ($1 + 1) * PERIOD ))" +%Y-%m-%dT%H:%M:%SZ)" || cannot_establish "jq_failed rc=$? site=bucket_date" "GNU date could not render a bucket"
  BW="${a}–${b}"
}

now_iso="$(date -u -d "@${NOW_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)" || cannot_establish "clock_unreadable site=now_iso" "GNU date could not render NOW"
days_elapsed="$(awk -v n="$NOW_EPOCH" -v f="$SOAK_FROM_EPOCH" 'BEGIN { printf "%.1f", (n - f) / 86400 }')"

# ── the reading block precedes every verdict ─────────────────────────────────────────────────
printf 'reading: window=%s..%s slices=%s/%s runs=%s active_fns=%s null_started=%s explained=%s UNEXPLAINED=%s days_elapsed=%s (%s)\n' \
  "$SOAK_FROM" "$now_iso" "$N_SLICES" "$N_SLICES" "$runs_n" "$active_fns" "$null_started" "$explained_n" "$unexplained_n" "$days_elapsed" "$slice_line"
# One jq per class renders the rows as TSV; the shape check runs per row before anything is printed.
jqv expl_rows expl_rows -r '.[] | select(.explained) | [.functionID, .bucket, .count] | @tsv' <<<"$split"
jqv unexpl_rows unexpl_rows -r '.[] | select(.explained | not) | [.functionID, .bucket, .count] | @tsv' <<<"$split"
while IFS=$'\t' read -r fn b c; do
  [[ -n "$fn" ]] || continue
  [[ "$fn" =~ $UUID_RE && "$c" =~ ^[0-9]+$ ]] || cannot_establish "jq_failed rc=0 site=group_shape" "a group carried a non-UUID functionID or a non-integer count"
  bucket_window "$b"
  printf 'explained: functionID=%s bucket=%s (%s) count=%s — %s\n' "$fn" "$b" "$BW" "$c" "$EXPLAINED_WHY"
done <<<"$expl_rows"
while IFS=$'\t' read -r fn b c; do
  [[ -n "$fn" ]] || continue
  [[ "$fn" =~ $UUID_RE && "$c" =~ ^[0-9]+$ ]] || cannot_establish "jq_failed rc=0 site=group_shape" "a group carried a non-UUID functionID or a non-integer count"
  bucket_window "$b"
  printf 'UNEXPLAINED: functionID=%s bucket=%s (%s) count=%s\n' "$fn" "$b" "$BW" "$c"
done <<<"$unexpl_rows"

PROVENANCE="window anchored on the 09-15 verify pass (run 34974655656, itself a QUALIFIED verdict: override anchor, population scoped to these 52 crons — ADR-146); this is a soak reading over the startedAt proxy, not a complete exactly-once proof: two runs of one tick started more than 20 minutes apart land in different buckets and read clean (P2-c)"

if [[ "$NOW_EPOCH" -lt "$SOAK_END_EPOCH" ]]; then
  printf 'NOT YET: interim reading at day %s of 7 — the soak ends %s. %s.\n' "$days_elapsed" "$SOAK_END" "$PROVENANCE"
  if [[ "$unexplained_n" -gt 0 ]]; then
    printf 'NOT YET: %s UNEXPLAINED group(s) already present — investigate now, do not wait for day 7; the day-7 verdict will read SOAK NOT CLEAN unless each is attributed.\n' "$unexplained_n"
  fi
  exit 2
fi

# ── at/after SOAK_END: ACTION REQUIRED, either arm ───────────────────────────────────────────
printf 'ACTION REQUIRED: the soak window closed %s (day %s). %s.\n' "$SOAK_END" "$days_elapsed" "$PROVENANCE"
printf 'horizon: this reading stays takeable for roughly one to two weeks after day 7; after that the heaviest slice outgrows the host'"'"'s page budget and the probe reports CANNOT ESTABLISH until #6178 is closed — that is expected, not a broken probe.\n'
if [[ "$unexplained_n" -eq 0 ]]; then
  printf 'operator verbs, in this order: (1) dispatch the ADR-100 `adopting → accepted` flip PR (knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md, status: adopting → accepted); (2) release the four inngest-cutover-pre-* hcloud images (%s) — DELETE /v1/images/<id>, destructive, operator-acked; (3) close #6178 LAST — a notify-only probe never exits 1, so a group found after the close is dropped by the closed-set path; closing last keeps this probe reporting until the destructive verbs are done.\n' "$SNAPSHOTS"
  printf 'SCOPE: this reading is the dedicated host'"'"'s (10.0.1.40) run index only — it is NOT a web-host double-fire detector (op=verify P2-a); before flipping, hold web-1'"'"'s quiesced shape too: doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh\n'
  printf 'ACTION REQUIRED: SOAK CLEAN outside the explained bucket — %s distinct runs, %s explained group(s), 0 UNEXPLAINED; dispatch the ADR-100 `adopting → accepted` flip PR, release the four `inngest-cutover-pre-*` hcloud images (%s), close #6178\n' "$runs_n" "$explained_n" "$SNAPSHOTS"
  exit 5
fi
printf 'operator verbs: attribute each UNEXPLAINED group above against routine_runs (read-only GET /rest/v1/routine_runs on prd, started_at inside the bucket window) before any flip; a group that is a second scheduler firing the same tick means the soak FAILED and the rollback path in the runbook applies, not the flip.\n'
printf 'SCOPE: this reading is the dedicated host'"'"'s (10.0.1.40) run index only — it is NOT a web-host double-fire detector (op=verify P2-a); before flipping, hold web-1'"'"'s quiesced shape too: doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh\n'
printf 'ACTION REQUIRED: SOAK NOT CLEAN — %s UNEXPLAINED group(s) outside the explained bucket; investigate the listed groups before flipping\n' "$unexplained_n"
exit 5
