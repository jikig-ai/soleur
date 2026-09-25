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
# until this file existed the day-7 reading was an `op=verify` dispatch somebody had to remember.
# The 07-07 extraction plan prescribed a PASS/FAIL follow-through for exactly this wait and it was
# never built; this is that follow-through in the notify-only vocabulary the close decision
# requires. Design record: the ADR-100 addendum dated 2026-09-19 and the plan
# knowledge-base/project/plans/2026-09-19-feat-inngest-soak-6178-followthrough-enrollment-plan.md.
#
# WHAT IT MEASURES. Over the pinned 52-cron population and the open-topped window from SOAK_FROM,
# every (functionID, 1200 s startedAt-bucket) group holding more than one distinct run is a
# finding. Five such groups, from four attributed events, are EXPLAINED: the 2026-09-17T12:40–13:00Z
# catch-up after the 76-minute no-scheduler window (two groups; PR #8252, `op=resume` run
# 35223389582), the 09-19 manual retry, the 09-22 catch-up and the 09-24 manual trigger
# (attributions on #6178 comments 5738682595 and 5829980093). Each is pinned as the exact RUN-ID SET
# the host reported, joined to `routine_runs.run_id` (the ULID the run-log middleware writes), so
# the functionID→name mapping is proven rather than inferred from counts: a group is explained only
# if its members are exactly those ids. The minter at 5 (or 3) in 1491374, a third function in a
# pinned bucket, or the same counts with different run ids, are all UNEXPLAINED. Each explained
# bucket prints one `explained_why: bucket=<b>` line carrying its own attribution.
#
# ANCHOR PROVENANCE (ADR-146; runbook inngest-server.md §"Scan window + trust anchor"). SOAK_FROM
# is an `override`-class anchor: bucket_floor(2026-09-15T13:23:00Z) − 2×1200 s, where 13:23:00Z
# is the 09-15 `op=verify` pass (run 34974655656), itself `anchor_source=floor(override)` and
# `VERIFIED (QUALIFIED)`. The day-7 reading inherits both qualifications; it is a SOAK reading over
# the post-verify window, not a re-proof of the coexistence region.
#
# SCOPE (op=verify P2-a). The on-host probe reads ONLY the dedicated host's (10.0.1.40) run index —
# it is NOT a web-host double-fire detector; web-1's quiesced shape (scripts/inngest-host-state.sh)
# is the second evidence held before flipping. Accepted residuals: (P2-c) two runs of one tick
# started more than 20 minutes apart land in different buckets and read clean; a MANUAL trigger of
# a cron (`cron/<id>.manual-trigger`) within 1200 s of its scheduled tick reads as a group — the
# host's projection carries neither `queuedAt` nor the trigger source, so attribution against
# `routine_runs.trigger_source` is the operator's step, never this probe's. An attributed
# manual-trigger group is then recorded as a pin in EXPLAINED, as two already are.
#
# HOW IT READS. The deploy webhook forwards only `from` and `function_ids` to the on-host probe
# (apps/web-platform/infra/hooks.json.tmpl), so the window is open-topped and the ONLY cost lever
# is the POPULATION: the 52 ids are dealt round-robin into 5 slices of ≤ 11 from a density-sorted
# file (inngest-soak-6178.function-ids.txt — the sort IS the balancing lever) so no slice
# approaches the host's 18-page / 1800-run feasibility gate (90 s ÷ 5 s/page × 100). A registry
# GET first requires every population id to still be registered; a registry that GREW is reported
# as UNMEASURED ids and QUALIFIES the verdict rather than blocking it.
#
# CREDENTIAL POSTURE. Three secrets, forwarded by the sweeper from the directive's `secrets=`
# clause under `env -i`: WEBHOOK_DEPLOY_SECRET (HMAC over the empty GET body), CF_ACCESS_CLIENT_ID
# and CF_ACCESS_CLIENT_SECRET (the Cloudflare Access pair). None is ever printed; the probe emits
# ids, buckets, counts and slice numbers only (AC-NOBODY). Every host-supplied field is
# shape-validated BEFORE it is printed; the only host-authored text that reaches stdout is the
# bounded, charset-filtered excerpt of a FATAL/error body (`excerpt`, ≤120 bytes, no quotes or
# control bytes), because the sweeper republishes stdout+stderr verbatim on a public issue.
#
# Two mechanisms have no precedent in the probe corpus, declared here so a reader does not look for
# one: the rc-FILTERING EXIT trap (11 probes trap EXIT for cleanup only; this one rewrites every rc
# outside {2,3,5,78} to 3, because a `set -u` abort is rc 1 = the sweeper's FAIL/reopen verb), and
# the `remedy=` output key (siblings use prose tails).
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh) — NEVER 0, NEVER 1:
#   2  = NOT YET            a complete, non-vacuous reading taken before SOAK_END.
#   3  = CANNOT ESTABLISH   credentials unset, population/registry/slice unreadable, vacuous,
#                           incomplete, thin, eroded, a failing jq, past the horizon, or ANY
#                           unmapped exit.
#   5  = ACTION REQUIRED    at/after SOAK_END: "SOAK CLEAN … flip, re-read, release, close" or
#                           "SOAK NOT CLEAN … investigate". Both name the operator verbs.
#   78 = refused to run under xtrace with a live credential (#7797); TRANSIENT to the sweeper.
#   0 and 1 are structurally unreachable: no literal `exit 0`/`exit 1` exists in this file, every
#   jq/curl/date whose output feeds a decision has its rc captured, and the EXIT trap rewrites
#   any other status to 3. A bash PARSE error exits 2 without running the trap, so the file also
#   re-parses itself with `bash -n` before doing anything else.
#
# ── WHY `-uo` AND NOT `-euo` ─────────────────────────────────────────────────
# 66 of the 68 probes here use `set -uo pipefail`, including both of the ones
# this file is modelled on, and the reason is specific rather than stylistic.
# Under `-e` any unguarded non-zero command aborts with bash's own status, which
# for most failures is **1** — and 1 is the sweeper's FAIL verb AND its reopen
# trigger on a closed issue. So `-e` hands this file a path to the one exit code
# its contract says it must never take, reachable by adding any future unguarded
# command. Without `-e`, a failure surfaces only as a code this file chose.
# Every failure path below is explicitly `||`-guarded, and the companion suite
# asserts `rc` is never 0 or 1 across the whole fixture family rather than
# leaving that invariant as prose.
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

# A syntax error later in this file would exit 2 (= NOT YET) with bash's own error text and no
# trap. bash parses incrementally, so a whole-file `-n` from here catches it first.
if ! bash -n "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
  printf 'CANNOT ESTABLISH: reason=probe_unparseable remedy=the probe file does not parse; fix the syntax (bash -n scripts/followthroughs/inngest-soak-6178.sh)\n' >&2
  exit 3
fi

set -uo pipefail

# ONE EXIT trap: cleanup + the rc filter. Bash keeps a SINGLE EXIT trap — a later
# `trap 'rm -rf "$WORK"' EXIT` would silently REPLACE this filter and a `set -u` abort would then
# exit 1 (= FAIL, a reopen in closed mode). EXIT-only on purpose: an INT/TERM arm would rewrite a
# signal kill to 3. WORK is assigned ONCE, from a bare `mktemp -d`, so the `rm -rf` operand is
# provably absolute (the P1b ratchet, plugins/soleur/test/fixture-relative-assert.test.sh); a
# failed mktemp leaves it empty and the `-n` guard makes the cleanup a no-op.
WORK="$(mktemp -d 2>/dev/null)"
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

cannot_establish() { # cannot_establish <reason-and-fields> <remedy>
  printf 'CANNOT ESTABLISH: reason=%s remedy=%s\n' "$1" "$2" >&2
  exit 3
}
[[ -n "$WORK" && -d "$WORK" ]] || cannot_establish "scratch_unavailable" "mktemp -d failed on the runner (TMPDIR full or unwritable)"

# ── constants ────────────────────────────────────────────────────────────────────────────────
SOAK_FROM=2026-09-15T12:40:00Z      # bucket_floor(09-15 verify pass 13:23:00Z) − 2×PERIOD
SOAK_END=2026-09-22T13:23:00Z       # the 09-15 verify pass instant + 7 days
SOAK_STALE=2026-10-06T00:00:00Z     # past this, refuse before any GET: the reading is no longer takeable and the verbs are overdue
PERIOD=1200
SLICE_MAX=11
POPULATION_SIZE=52
RUN_FLOOR=800                       # half the day-3.6 count (826); a hole that lost > half the window
PROBE_BUDGET_S=420                  # wall-clock cap for the slice loop: the sweeper's job is 15 min for ALL probes
# The explained groups, pinned as exact run-id SETS (host `.id` == `routine_runs.run_id`, read
# 2026-09-19 from prd: the four `cron-ghcr-token-minter` rows and the two `cron-anthropic-credit-probe`
# rows started 12:53:07–12:53:30Z). The (functionID, bucket, count) triple must match AND the
# member ids must equal the set — bucket 1491374 is historical and immutable, so any other member
# set in it is a new finding.
# Only the two 09-17 pins omit `why` (they print EXPLAINED_WHY); every other pin must carry its own.
EXPLAINED='[
  {"functionID":"9a26ac57-a722-5c59-9f36-115675eecbad","bucket":1491540,"count":2,
   "ids":["01M2XM4813N3QE97TEZZVW9TT7","01M2XMEM8TZEDVAMRTZSCPWVVZ"],
   "why":"2026-09-19 20:01Z+20:06Z: two manual triggers (trigger_source=manual), an operator retry of a failed run"},
  {"functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","bucket":1491719,"count":3,
   "ids":["01M341XPCWG79VZZPDJQ9W64KG","01M341XQ4SX2KGWVF5J0XQ9PTG","01M341XQNXQDFJSNW1C5PDP4TH"],
   "why":"2026-09-22 catch-up: 07:00/07:20/07:40 ticks missed with no scheduler, each fired once at resume 35698687536"},
  {"functionID":"209d5706-72bd-561c-88dc-92d7e23c1849","bucket":1491858,"count":2,
   "ids":["01M38ZZP4PKKDB2QJ3HB77JTEY","01M390P0W5ZT51H3VDD1M2CTYJ"],
   "why":"2026-09-24 06:00Z scheduled tick plus a manual trigger at 06:12:11Z (trigger_source=manual)"},
  {"functionID":"26e6836b-97ad-503f-8b08-490d8a2f4ce8","bucket":1491374,"count":4,
   "ids":["01M2QPSG3066F4DRDEBX5FCJSC","01M2QPSGN9WFA6ERRYCJP8ACNY","01M2QPSH0C5MWWGVM45D73QFGF","01M2QPSHH0TRCGYC9DBAHHCA1J"]},
  {"functionID":"2e625d3c-0207-569f-b10b-567bc685ad5e","bucket":1491374,"count":2,
   "ids":["01M2QPSG3C1H3HG443K6JG9Q0V","01M2QPSGKXBTKVDD358S1GRQ76"]}
]'
EXPLAINED_WHY='2026-09-17T12:40–13:00Z catch-up after the 76-minute no-scheduler window (PR #8252, op=resume run 35223389582): cron-ghcr-token-minter (`*/20`) ×4 and cron-anthropic-credit-probe (`47 * * * *`) ×2 = exactly the ticks each missed, each fired once on resume — one scheduler draining its backlog, not two schedulers; run ids joined to routine_runs on #6178 comment 5738682595'
SNAPSHOTS='398857857, 406654994, 407991378, 411798619'
HOOK_BASE=https://deploy.soleur.ai/hooks
UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$'
INT_RE='^[0-9]{1,12}$'              # bounded: bash arithmetic wraps at 64 bits, so an unbounded digit run is not an integer
BETTERSTACK_HINT='doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 24h --grep SOLEUR_INNGEST_PREFLIGHT --limit 20'
SLICE_REMEDY='retry next sweep; hmac_mismatch = WEBHOOK_DEPLOY_SECRET rotated (the repo secret the sweeper forwards, not the Doppler copy); cf_access = the CF-Access pair; probe_fatal names the host'"'"'s own reason and the slice to re-sort, and more than a week after day 7 it is the expected page-budget horizon, not a broken probe (this reading stays takeable for roughly one to two weeks after day 7; after that the heaviest slice outgrows the host'"'"'s page budget and the probe reports CANNOT ESTABLISH until #6178 is closed); bad_run_shape = the host probe'"'"'s projection changed — compare its emitted shape against op=verify 2.6'
SCOPE_LINE='SCOPE: this reading is the dedicated host'"'"'s (10.0.1.40) run index only — it is NOT a web-host double-fire detector (op=verify P2-a); before flipping, hold web-1'"'"'s quiesced shape too: doppler run -p soleur -c prd_terraform -- bash scripts/inngest-host-state.sh'
PROVENANCE='window anchored on the 09-15 verify pass (run 34974655656, itself a QUALIFIED verdict: override anchor, population scoped to these 52 crons — ADR-146); this is a soak reading over the startedAt proxy, not a complete exactly-once proof: two runs of one tick started more than 20 minutes apart land in different buckets and read clean (P2-c), and a manual trigger within 1200 s of a scheduled tick reads as a group'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POP_FILE="${INNGEST_SOAK_POPULATION_FILE:-$REPO_ROOT/scripts/followthroughs/inngest-soak-6178.function-ids.txt}"

# jqv <var> <site> <jq args...> — every jq whose output feeds a decision goes through here, and it
# is called DIRECTLY (never inside `$(…)`): a `cannot_establish` from inside a command substitution
# exits only the SUBSHELL, and under `-uo pipefail` WITHOUT `-e` the assignment then continues with
# an empty value (measured while building this file: a `startedAt` fromdateiso8601 could not parse
# fell through to a clean NOT YET). jq's stderr is captured, never republished: it embeds the
# offending VALUE in its message.
jqv() {
  local __var="$1" site="$2"; shift 2
  local out rc
  out="$(jq "$@" 2>"$WORK/jq.err")"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    cannot_establish "jq_failed rc=${rc} site=${site}" "a host-supplied field did not parse at this site; nothing was decided. Re-run next sweep; if it repeats, compare the host probe's emitted shape against op=verify 2.6 (scripts/cutover-inngest.sh)"
  fi
  printf -v "$__var" '%s' "$out"
}

# ── seams (unreachable from a tracker body: the sweeper runs probes under env -i) ────────────
NOW_EPOCH="${INNGEST_SOAK_NOW_EPOCH:-}"
if [[ -n "$NOW_EPOCH" ]]; then
  [[ "$NOW_EPOCH" =~ $INT_RE ]] || cannot_establish "bad_now_override" "INNGEST_SOAK_NOW_EPOCH must be epoch seconds (digits only); it is a test seam and must be unset under the sweeper"
else
  NOW_EPOCH="$(date -u +%s)"; rc=$?
  [[ "$rc" -eq 0 && "$NOW_EPOCH" =~ $INT_RE ]] || cannot_establish "clock_unreadable rc=${rc}" "date -u +%s failed on the runner"
fi
SOAK_FROM_EPOCH="$(date -u -d "$SOAK_FROM" +%s)"; rc=$?
[[ "$rc" -eq 0 && "$SOAK_FROM_EPOCH" =~ $INT_RE ]] || cannot_establish "clock_unreadable rc=${rc} site=soak_from" "GNU date could not parse SOAK_FROM"
SOAK_END_EPOCH="$(date -u -d "$SOAK_END" +%s)"; rc=$?
[[ "$rc" -eq 0 && "$SOAK_END_EPOCH" =~ $INT_RE ]] || cannot_establish "clock_unreadable rc=${rc} site=soak_end" "GNU date could not parse SOAK_END"
SOAK_STALE_EPOCH="$(date -u -d "$SOAK_STALE" +%s)"; rc=$?
[[ "$rc" -eq 0 && "$SOAK_STALE_EPOCH" =~ $INT_RE ]] || cannot_establish "clock_unreadable rc=${rc} site=soak_stale" "GNU date could not parse SOAK_STALE"
if [[ "$NOW_EPOCH" -ge "$SOAK_STALE_EPOCH" ]]; then
  cannot_establish "horizon_passed stale_since=${SOAK_STALE}" "the day-7 reading is no longer takeable (the heaviest slice has outgrown the host's page budget) and #6178 is still open; if the ADR-100 flip and the snapshot release are done, close #6178 — nothing here is dispatched past this date, so this line repeats daily until then"
fi

# ── credentials: absent is CANNOT ESTABLISH (3, never 2 — NOT YET is reserved for a reading) ──
missing=""
[[ -z "${WEBHOOK_DEPLOY_SECRET:-}" ]] && missing="${missing} WEBHOOK_DEPLOY_SECRET"
[[ -z "${CF_ACCESS_CLIENT_ID:-}" ]] && missing="${missing} CF_ACCESS_CLIENT_ID"
[[ -z "${CF_ACCESS_CLIENT_SECRET:-}" ]] && missing="${missing} CF_ACCESS_CLIENT_SECRET"
if [[ -n "$missing" ]]; then
  cannot_establish "credentials_unprovisioned missing:${missing}" "nothing about the host was measured. Confirm the directive's secrets= clause lists all three and that the sweeper workflow env sets them"
fi

# ── population: exactly POPULATION_SIZE strict-UUID lines, file order preserved ──────────────
[[ -r "$POP_FILE" ]] || cannot_establish "population_malformed cause=unreadable" "the population file is missing or unreadable at ${POP_FILE#"$REPO_ROOT"/}"
pop_lines="$(grep -vE '^[[:space:]]*(#|$)' "$POP_FILE" || true)"
pop_n="$(printf '%s\n' "$pop_lines" | grep -c . || true)"
pop_ok="$(printf '%s\n' "$pop_lines" | LC_ALL=C grep -cE "$UUID_RE" || true)"
pop_u="$(printf '%s\n' "$pop_lines" | LC_ALL=C grep -E "$UUID_RE" | LC_ALL=C sort -u | grep -c . || true)"
if [[ "$pop_n" -ne "$POPULATION_SIZE" || "$pop_ok" -ne "$POPULATION_SIZE" || "$pop_u" -ne "$POPULATION_SIZE" ]]; then
  cannot_establish "population_malformed lines=${pop_n} uuid=${pop_ok} unique=${pop_u} want=${POPULATION_SIZE}" "the committed population file must hold exactly ${POPULATION_SIZE} distinct UUID lines; regenerate from the run logs named in its header"
fi
printf '%s\n' "$pop_lines" > "$WORK/population.txt"
LC_ALL=C sort -u "$WORK/population.txt" > "$WORK/population.sorted"

# ── one request shape (canary-promotion-5875.sh: HMAC over the empty GET body) ───────────────
SIG="$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" | sed 's/.*= //')"
# hook_get <url> <body-file> → sets HTTP_CODE and CURL_RC (globals — called DIRECTLY, never via
# `$(…)`, which would run it in a subshell and discard both). The body file is created first so a
# transport failure leaves an EMPTY file, never a missing one (a missing file makes every later
# `< "$body"` print bash's own redirect error onto the public comment). No `|| echo 000`: curl
# already prints 000 via -w on a transport failure, so an append would yield 000000.
# --max-time 105 > the host's own bound (DEADLINE 90 s + PAGE_MIN); --connect-timeout bounds a
# stalled edge. The sweeper runs every probe sequentially under one 15-minute job with no per-probe
# ceiling, so this probe also enforces PROBE_BUDGET_S.
HTTP_CODE=""; CURL_RC=0
hook_get() {
  : > "$2"
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
  if grep -qE 'inngest-(doublefire|registry)-probe: FATAL' "$f" 2>/dev/null; then printf 'probe-fatal'
  elif grep -qF 'Error occurred while evaluating hook rules.' "$f" 2>/dev/null; then printf 'hook-rule-mismatch'
  elif grep -qiE '<!DOCTYPE|<html' "$f" 2>/dev/null; then printf 'cf-access-html'
  else printf 'other'; fi
}
# excerpt <file> <class> → what the public comment may carry about a body: the host probe's own
# reason tokens for a FATAL, a fixed sentence for HTML, and otherwise at most 120 bytes from an
# allowlisted charset — never a raw byte. A body whose RUN SHAPE failed validation is withheld
# entirely (its offending value is what the shape check exists to keep off the comment).
excerpt() {
  case "$2" in
    probe-fatal) LC_ALL=C grep -oE 'reason=[a-z_]+( pages_scanned=[0-9]+)?|errors=\[[^]]{0,80}\]' "$1" 2>/dev/null | head -1 | LC_ALL=C tr -cd 'A-Za-z0-9_=:.,/ []{}"-' ;;
    cf-access-html) printf '(html page withheld)' ;;
    withheld) printf '(json body withheld: run shape)' ;;
    *) LC_ALL=C tr -cd 'A-Za-z0-9_=:.,/ {}"-' < "$1" 2>/dev/null | cut -c1-120 ;;
  esac
}

# ── registry gate: every population id must still be registered; growth is reported, not refused ─
hook_get "$HOOK_BASE/inngest-registry-probe" "$WORK/registry.body"; code="$HTTP_CODE"
if [[ "$CURL_RC" -ne 0 || "$code" != "200" ]]; then
  bc="$(classify_body "$WORK/registry.body")"
  cannot_establish "registry_unreadable curl_rc=${CURL_RC} http=${code} body_class=${bc} body_len=$(wc -c < "$WORK/registry.body" | tr -d ' ') body=$(excerpt "$WORK/registry.body" "$bc")" "retry next sweep; hook-rule-mismatch = WEBHOOK_DEPLOY_SECRET rotated (the repo secret the sweeper forwards); cf-access-html = the CF-Access pair rotated"
fi
if ! jq -e '(.function_count | type) == "number" and (.function_ids | type) == "array" and all(.function_ids[]; type == "string")' "$WORK/registry.body" >/dev/null 2>&1; then
  cannot_establish "registry_unreadable curl_rc=0 http=200 body_class=$(classify_body "$WORK/registry.body") cause=bad_shape" "the registry probe's projection changed; compare against apps/web-platform/infra/inngest-registry-probe.sh"
fi
jqv reg_count registry_count -r '.function_count' "$WORK/registry.body"
[[ "$reg_count" =~ $INT_RE ]] || cannot_establish "registry_unreadable cause=bad_count" "function_count is not an integer"
jqv reg_ids_raw registry_ids -r '.function_ids[]' "$WORK/registry.body"
printf '%s\n' "$reg_ids_raw" | LC_ALL=C grep -E "$UUID_RE" | LC_ALL=C sort -u > "$WORK/registry.ids"
reg_missing_list="$(LC_ALL=C comm -23 "$WORK/population.sorted" "$WORK/registry.ids")"; rc=$?
[[ "$rc" -eq 0 ]] || cannot_establish "registry_unreadable cause=comm_failed rc=${rc}" "the population/registry set difference could not be computed on the runner"
reg_missing="$(printf '%s\n' "$reg_missing_list" | grep -c . || true)"
if [[ "$reg_missing" -ne 0 ]]; then
  cannot_establish "registry_drift missing_from_registry=${reg_missing} function_count=${reg_count}" "a pinned cron is no longer registered, so the pinned population no longer covers the registry — do not flip; re-derive the cron population (gh workflow run cutover-inngest.yml -f op=registry-probe is read-only) and re-measure"
fi
reg_total="$(grep -c . "$WORK/registry.ids" || true)"
# Ids registered that are NOT in the population: 18 event-driven functions on 09-15. Anything above
# that is a function registered since — UNMEASURED by this reading, so the verdict is qualified.
UNMEASURED_N=$(( reg_total > POPULATION_SIZE + 18 ? reg_total - POPULATION_SIZE - 18 : 0 ))
UNMEASURED_LINE=""
if [[ "$UNMEASURED_N" -gt 0 ]]; then
  UNMEASURED_LINE="registry: ${UNMEASURED_N} function(s) registered after 09-15 (function_count=${reg_count}) are UNMEASURED by this reading — attribute their triggers (cron or event) before flipping; a new cron needs the population file re-derived"
fi

# ── slices: round-robin over the density-sorted file, ≤ SLICE_MAX ids each ───────────────────
N_SLICES=$(( (POPULATION_SIZE + SLICE_MAX - 1) / SLICE_MAX ))
: > "$WORK/spool.json"
slice_line=""
sum_deduped=0
kk=0; code=""; bc=""; blen=0; body=""
unreadable() { # unreadable <cause> — reads the current slice's globals
  local cause="$1" shown_bc="$bc"
  [[ "$cause" == "bad_run_shape" ]] && shown_bc="withheld"
  cannot_establish "slice_unreadable slice=${kk}/${N_SLICES} curl_rc=${CURL_RC} http=${code} cause=${cause} body_class=${bc} body_len=${blen} body=$(excerpt "$body" "$shown_bc")" "$SLICE_REMEDY"
}
for (( k = 0; k < N_SLICES; k++ )); do
  kk=$((k + 1))
  csv="$(awk -v n="$N_SLICES" -v k="$k" '(NR-1)%n==k' "$WORK/population.txt" | paste -sd, -)"
  body="$WORK/slice-$kk.body"
  if (( SECONDS > PROBE_BUDGET_S )); then
    cannot_establish "slice_budget_exhausted slice=${kk}/${N_SLICES} elapsed_s=${SECONDS} budget_s=${PROBE_BUDGET_S}" "the earlier slices consumed the probe's wall-clock budget (a stalled edge or a slow host); retry next sweep — the sweeper job caps ALL probes at 15 minutes"
  fi
  hook_get "$HOOK_BASE/inngest-doublefire-probe?from=${SOAK_FROM}&function_ids=${csv}" "$body"; code="$HTTP_CODE"
  bc="$(classify_body "$body")"
  blen="$(wc -c < "$body" | tr -d ' ')"
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
    'all(.runs[]; (.id | type) == "string" and (.id | test("^[0-9A-Z]{26}$")) and (.functionID | type) == "string" and (.functionID | test($u)) and ((.startedAt == null) or ((.startedAt | type) == "string" and (.startedAt | test($t)))))' \
    "$body" >/dev/null 2>&1 || unreadable bad_run_shape
  jqv tc "total_count_${kk}" -r '.total_count' "$body"
  # The host emits the enum string "unknown" when page-1 totalCount did not parse; a bash
  # arithmetic test would read that as 0, so this is a regex, never `-gt`.
  [[ "$tc" =~ $INT_RE ]] || cannot_establish "total_count_unknown slice=${kk}/${N_SLICES}" "re-run next sweep; if it repeats: ${BETTERSTACK_HINT/PREFLIGHT/PREFLIGHT_GATE}"
  jqv nruns "runs_${kk}" '.runs | length' "$body"
  if [[ "$tc" -eq 0 || "$nruns" -eq 0 ]]; then
    cannot_establish "slice_vacuous slice=${kk}/${N_SLICES} total_count=${tc} runs=${nruns}" "gh workflow run cutover-inngest.yml -f op=registry-probe (read-only) and compare its ids against scripts/followthroughs/inngest-soak-6178.function-ids.txt"
  fi
  jqv deduped "deduped_${kk}" '.runs | unique_by(.id) | length' "$body"
  if [[ "$deduped" -lt "$tc" ]]; then
    cannot_establish "slice_incomplete slice=${kk}/${N_SLICES} deduped=${deduped} total_count=${tc}" "re-run next sweep; if it repeats the host's pagination is truncating: ${BETTERSTACK_HINT}"
  fi
  # Every run's functionID must be one this slice asked for: a host answering for a function it was
  # not asked about is a projection change, and it is also what makes the dealer observable.
  jqv foreign "foreign_${kk}" --arg csv "$csv" '($csv | split(",")) as $want | [.runs[].functionID | select(. as $f | $want | index($f) | not)] | length' "$body"
  [[ "$foreign" == "0" ]] || cannot_establish "slice_unreadable slice=${kk}/${N_SLICES} cause=foreign_function_id foreign=${foreign}" "the host returned runs for a function this slice did not request; compare the hook's function_ids forwarding (apps/web-platform/infra/hooks.json.tmpl) against op=verify 2.6"
  # Spool the .runs ARRAY (never the response object: `jq -s add` over objects keeps only the
  # last slice — the false-clean shape the review caught).
  jqv spool_arr "spool_${kk}" -c '.runs | unique_by(.id)' "$body"
  printf '%s\n' "$spool_arr" >> "$WORK/spool.json"
  sum_deduped=$(( sum_deduped + deduped ))
  slice_line="${slice_line}${slice_line:+ }s${kk}=${tc}"
done

# ── union → dedupe → floors → buckets ────────────────────────────────────────────────────────
jqv runs_all union -s -c '[.[][]] | unique_by(.id)' "$WORK/spool.json"
printf '%s\n' "$runs_all" > "$WORK/runs.json"
jqv runs_n runs_n 'length' "$WORK/runs.json"
# The function sets are disjoint across slices, so the union must be exactly the sum of the
# per-slice deduped counts; a shortfall is a run id shared by two DIFFERENT runs.
if [[ "$runs_n" -ne "$sum_deduped" ]]; then
  cannot_establish "union_mismatch union=${runs_n} sum_of_slices=${sum_deduped}" "two slices returned the same run id for different runs; the host's run-id uniqueness (trace_runs.run_id) is broken — do not flip; read the preflight markers: ${BETTERSTACK_HINT}"
fi
jqv null_started null_started '[.[] | select(.startedAt == null)] | length' "$WORK/runs.json"
if [[ "$runs_n" -lt "$RUN_FLOOR" ]]; then
  cannot_establish "population_thin runs=${runs_n} floor=${RUN_FLOOR}" "re-run next sweep; if it repeats, the host's run index has a mid-window hole — read the SOLEUR_INNGEST_PREFLIGHT markers: ${BETTERSTACK_HINT}"
fi
# A run with no startedAt cannot be bucketed; a few are a queue snapshot, many are a projection
# regression that would hide a double-fire behind an unbucketed row.
if (( null_started * 20 > runs_n )); then
  cannot_establish "index_eroded cause=null_started null_started=${null_started} runs=${runs_n}" "more than 5% of runs carry no startedAt; the host's projection changed — do not flip; compare against op=verify 2.6"
fi
jqv min_started min_started -r '[.[] | select(.startedAt != null) | .startedAt] | min // ""' "$WORK/runs.json"
[[ "$min_started" =~ $ISO_RE ]] || cannot_establish "index_eroded min_started=none" "no run carries a startedAt; the host's run index is unreadable for this window: ${BETTERSTACK_HINT}"
min_whole="${min_started%%.*}"; min_whole="${min_whole%Z}Z"
min_epoch="$(date -u -d "$min_whole" +%s)"; rc=$?
[[ "$rc" -eq 0 && "$min_epoch" =~ $INT_RE ]] || cannot_establish "date_failed rc=${rc} site=min_started" "the earliest startedAt did not parse as ISO-8601"
if [[ "$min_epoch" -lt "$SOAK_FROM_EPOCH" ]]; then
  cannot_establish "window_underrun min_started=${min_started} window_head=${SOAK_FROM}" "the host returned a run that started before the requested from=; the hook is no longer forwarding the lower bound — do not flip; compare apps/web-platform/infra/hooks.json.tmpl against op=verify 2.6"
fi
if [[ "$min_epoch" -gt $((SOAK_FROM_EPOCH + 2 * PERIOD)) ]]; then
  cannot_establish "index_eroded min_started=${min_started} window_head=${SOAK_FROM}" "the host's run index no longer reaches the window's head; any 09-15/16 double-fire would be gone too — do not flip; read the preflight markers: ${BETTERSTACK_HINT}"
fi
# The op=verify 2.6 bucketing (scripts/cutover-inngest.sh), modulo the input shape (`.[]` here,
# `.runs[]` there): null startedAt excluded (counted above), fractional seconds stripped,
# floor(startedAt / PERIOD). Dedupe is by run id ONLY — 2.6's (functionID, startedAt) fallback is
# dropped because the shape gate above refuses a run without a string id, and that fallback can
# shift counts against an exact pin. Each group also carries its sorted member ids.
jqv groups groups -c --argjson period "$PERIOD" \
  '[ .[] | select(.startedAt != null) | { fn: .functionID, id: .id, bucket: ((.startedAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) / $period | floor) } ] | group_by([.fn, .bucket]) | map(select(length > 1)) | map({ functionID: .[0].fn, bucket: .[0].bucket, count: length, ids: (map(.id) | sort) })' \
  "$WORK/runs.json"
# Exact split: explained iff (functionID, bucket, count) equals a pin AND the member ids equal its set.
jqv split split -c --argjson ex "$EXPLAINED" \
  '[ .[] | . as $g
     | ([ $ex[] | select(.functionID == $g.functionID and .bucket == $g.bucket and .count == $g.count and ((.ids | sort) == $g.ids)) ] | first) as $pin
     | . + { explained: ($pin != null), why: ($pin.why // "") } ]' <<<"$groups"
jqv explained_n explained_n '[.[] | select(.explained)] | length' <<<"$split"
jqv unexplained_n unexplained_n '[.[] | select(.explained | not)] | length' <<<"$split"

# bucket_window <bucket> → sets BUCKET_WINDOW="<iso>–<iso>" (a global — called directly, see jqv);
# the bucket is validated as a bounded integer before any arithmetic.
BUCKET_WINDOW=""
bucket_window() {
  [[ "$1" =~ $INT_RE ]] || cannot_establish "shape_failed site=bucket" "a computed bucket index was not an integer"
  local a b
  a="$(date -u -d "@$(( $1 * PERIOD ))" +%Y-%m-%dT%H:%M:%SZ)" || cannot_establish "date_failed rc=$? site=bucket" "GNU date could not render a bucket"
  b="$(date -u -d "@$(( ($1 + 1) * PERIOD ))" +%Y-%m-%dT%H:%M:%SZ)" || cannot_establish "date_failed rc=$? site=bucket" "GNU date could not render a bucket"
  BUCKET_WINDOW="${a}–${b}"
}
# print_groups <tsv-rows> <label>: one line per group, every field re-validated before printing.
print_groups() {
  local rows="$1" label="$2" fn b c
  while IFS=$'\t' read -r fn b c; do
    [[ -n "$fn" ]] || continue
    [[ "$fn" =~ $UUID_RE && "$c" =~ $INT_RE ]] || cannot_establish "shape_failed site=group" "a group carried a non-UUID functionID or a non-integer count"
    bucket_window "$b"
    printf '%s: functionID=%s bucket=%s (%s) count=%s\n' "$label" "$fn" "$b" "$BUCKET_WINDOW" "$c"
  done <<<"$rows"
}

now_iso="$(date -u -d "@${NOW_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)" || cannot_establish "clock_unreadable site=now_iso" "GNU date could not render NOW"
days_elapsed="$(awk -v n="$NOW_EPOCH" -v f="$SOAK_FROM_EPOCH" 'BEGIN { printf "%.1f", (n - f) / 86400 }')"

# ── the reading block precedes every verdict ─────────────────────────────────────────────────
printf 'reading: window=%s..%s slices=%s/%s runs=%s null_started=%s explained=%s UNEXPLAINED=%s unmeasured_fns=%s days_elapsed=%s (%s)\n' \
  "$SOAK_FROM" "$now_iso" "$N_SLICES" "$N_SLICES" "$runs_n" "$null_started" "$explained_n" "$unexplained_n" "$UNMEASURED_N" "$days_elapsed" "$slice_line"
[[ -n "$UNMEASURED_LINE" ]] && printf '%s\n' "$UNMEASURED_LINE"
jqv expl_rows expl_rows -r '.[] | select(.explained) | [.functionID, .bucket, .count] | @tsv' <<<"$split"
jqv unexpl_rows unexpl_rows -r '.[] | select(.explained | not) | [.functionID, .bucket, .count] | @tsv' <<<"$split"
print_groups "$expl_rows" "explained"
# One attribution line per explained bucket; a pin with no `why` (only the 09-17 pins) falls back to
# EXPLAINED_WHY in jq, so no TSV field is empty. unique_by(.bucket) collapses the two 09-17 groups,
# which is correct only while every pin in one bucket shares one `why` (true: only 1491374 holds two).
jqv why_rows why_rows -r --arg w "$EXPLAINED_WHY" \
  '[.[] | select(.explained) | {bucket, why: (if .why == "" then $w else .why end)}] | unique_by(.bucket) | .[] | [.bucket, .why] | @tsv' <<<"$split"
while IFS=$'\t' read -r b w; do
  [[ -n "$b" ]] || continue
  [[ "$b" =~ $INT_RE ]] || cannot_establish "shape_failed site=why_bucket" "an explained bucket index was not an integer"
  printf 'explained_why: bucket=%s %s\n' "$b" "$w"
done <<<"$why_rows"
print_groups "$unexpl_rows" "UNEXPLAINED"

if [[ "$NOW_EPOCH" -lt "$SOAK_END_EPOCH" ]]; then
  printf 'NOT YET: interim reading at day %s of 7 — the soak ends %s. %s.\n' "$days_elapsed" "$SOAK_END" "$PROVENANCE"
  if [[ "$unexplained_n" -gt 0 ]]; then
    printf 'NOT YET: %s UNEXPLAINED group(s) already present — investigate now, do not wait for day 7; the day-7 verdict will read SOAK NOT CLEAN unless each is attributed.\n' "$unexplained_n"
  fi
  exit 2
fi

# ── at/after SOAK_END: ACTION REQUIRED, either arm ───────────────────────────────────────────
printf 'ACTION REQUIRED: the soak window closed %s (day %s). %s.\n' "$SOAK_END" "$days_elapsed" "$PROVENANCE"
QUAL=""
[[ "$UNMEASURED_N" -gt 0 ]] && QUAL=" (QUALIFIED: ${UNMEASURED_N} unmeasured function(s) — see the registry line)"
if [[ "$unexplained_n" -eq 0 ]]; then
  printf 'operator verbs, in this order — the irreversible one goes after a fresh reading, not before:\n'
  printf '  (1) dispatch the ADR-100 `adopting → accepted` flip PR (knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md) — reversible;\n'
  printf '  (2) wait for the NEXT sweep'"'"'s comment to read SOAK CLEAN again — a fresh reading between the reversible and the irreversible verb is what protects the snapshots, not the order of the last two;\n'
  printf '  (3) release the four inngest-cutover-pre-* hcloud images (%s) — DELETE /v1/images/<id>, destructive, operator-acked;\n' "$SNAPSHOTS"
  printf '  (4) close #6178 LAST — a notify-only probe never exits 1, so a group found after the close is dropped by the sweeper'"'"'s closed-set path; closing last keeps this probe reporting until the verbs are done. It then repeats this comment daily until the close.\n'
  printf '%s\n' "$SCOPE_LINE"
  printf 'ACTION REQUIRED: SOAK CLEAN outside the explained bucket%s — %s distinct runs, %s explained group(s), 0 UNEXPLAINED; dispatch the ADR-100 `adopting → accepted` flip PR, re-read, release the four `inngest-cutover-pre-*` hcloud images (%s), close #6178\n' "$QUAL" "$runs_n" "$explained_n" "$SNAPSHOTS"
  exit 5
fi
printf 'operator verbs: attribute each UNEXPLAINED group above against routine_runs (read-only GET /rest/v1/routine_runs?select=routine_id,run_id,trigger_source,started_at on prd, started_at inside the bucket window; routine_runs under-records the host index by ~2%%, so a member with no row is attributed by its neighbours) before any flip; a group whose members are one scheduled tick fired twice by two schedulers means the soak FAILED and the rollback path in the runbook applies, not the flip; a manual trigger (trigger_source=manual) beside a scheduled tick is a false group — record it here and re-read.\n'
printf '%s\n' "$SCOPE_LINE"
printf 'ACTION REQUIRED: SOAK NOT CLEAN%s — %s UNEXPLAINED group(s) outside the explained bucket; investigate the listed groups before flipping\n' "$QUAL" "$unexplained_n"
exit 5
