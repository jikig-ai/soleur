#!/usr/bin/env bash
#
# (#9175) Capture provision-rehearsal evidence for a THROWAWAY inngest host.
#
# WHAT THIS DECIDES. Whether `inngest-provision-rehearsal-evidence.env` gets written — the
# artifact the operator attaches to #9175 proving the forced race rehearsed correctly:
# NIC-absent birth failed provisioning in the EXPECTED arm, the phase-B NIC attach healed it
# (bootstrap-done), and a post-reboot boot did NOT re-run provisioning (the latch held).
#
# THREE-STATE CONTRACT (same as git-data-rung2-evidence-capture.sh):
#   0 = PASS      — every assertion for the requested mode positive.
#   1 = FAIL      — a required marker is absent while the instrument is verifiably live.
#   2 = TRANSIENT — nothing is known yet, or the instrument itself could not be trusted.
#
# THE HARD PART IS SILENCE. A Better Stack query returning zero rows for a brand-new host is
# AMBIGUOUS — dark boot, wrong credentials, or instrument outage all look the same. The
# ANCHOR resolves it: one query for ANY row from this source in the window (not keyed on the
# rehearsal host — an anchor that is a strict prerequisite of the thing it anchors is not an
# anchor). If the source is live and this host said nothing, the silence is about the host
# (FAIL-adjacent verdicts); if the source is dead, TRANSIENT.
#
# WHAT THIS DOES NOT CLAIM: it reads the Better Stack channel only. Sentry cross-checks are
# out of scope for this rehearsal (the rung2 consult exists for that shape); the phone-home
# channel is the one the provision unit writes every marker to, so a dead Better Stack shows
# TRANSIENT rather than a wrong FAIL.
#
# Usage (under doppler so the Better Stack credentials are injected):
#   doppler run -p soleur -c prd_terraform -- \
#     scripts/followthroughs/inngest-provision-rehearsal-capture.sh \
#       --host-name soleur-inngest-rehearsal-<run-id> --mode phase-a \
#       --evidence-url https://github.com/jikig-ai/soleur/actions/runs/<run-id> \
#       [--out <path>] [--since <ISO>] [--window '2 HOUR'] [--min-attempts N]
set -uo pipefail

# REFUSE TO RUN UNDER xtrace WITH A LIVE CREDENTIAL BOUND (#7797 precedent). This script binds
# the warehouse read credential via the query transport; a traced run would log it.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_LOGS_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# A TERMINAL SENTINEL, PRINTED ON EVERY EXIT PATH. The workflow wraps this script in
# `doppler run`, which exits 1 on ITS OWN failures — the same code this script uses for
# FAIL. Without a sentinel the wrapper cannot tell "the rehearsal failed" from "the capture
# never ran a line".
trap 'printf "INNGEST_PROVISION_CAPTURE_VERDICT=%s\n" "$?"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Env override is the TEST SEAM, and the only one: the suite stubs the query transport rather
# than the decision function, so every arm exercises the real branching.
QUERY="${BETTERSTACK_QUERY_SH:-${REPO_ROOT}/scripts/betterstack-query.sh}"

HOST_NAME=""
EVIDENCE_URL=""
MODE=""
OUT=""
WINDOW="2 HOUR"
SINCE=""
REBOOT_SINCE=""
MIN_ATTEMPTS=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-name)     HOST_NAME="${2:-}"; shift 2 || shift ;;
    --evidence-url)  EVIDENCE_URL="${2:-}"; shift 2 || shift ;;
    --mode)          MODE="${2:-}"; shift 2 || shift ;;
    --out)           OUT="${2:-}"; shift 2 || shift ;;
    --window)        WINDOW="${2:-}"; shift 2 || shift ;;
    --since)         SINCE="${2:-}"; shift 2 || shift ;;
    # post-reboot only: the ISO timestamp recorded immediately BEFORE the reboot action —
    # the latch claim is "no provision rows after this boundary".
    --reboot-since)  REBOOT_SINCE="${2:-}"; shift 2 || shift ;;
    --min-attempts)  MIN_ATTEMPTS="${2:-}"; shift 2 || shift ;;
    --) shift ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

# assert_fixture_dir guards the evidence path before a writer roots at the caller's CWD.
# Byte-identical to the canonical definition in plugins/soleur/test/test-helpers.sh, whose
# equality fixture-dir-operand-assert asserts across every tracked copy; do not reword it.
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

case "$MODE" in
  phase-a|phase-b|post-reboot) ;;
  *) echo "usage: inngest-provision-rehearsal-capture.sh --host-name soleur-inngest-rehearsal-<run-id> --mode <phase-a|phase-b|post-reboot> --evidence-url <url> [--out <path>] [--since ISO] [--reboot-since ISO] [--window '<n> UNIT']" >&2; exit 64 ;;
esac
if [[ -z "$HOST_NAME" ]]; then
  echo "usage: --host-name is required" >&2; exit 64
fi
[[ -n "$OUT" ]] || OUT="${REPO_ROOT}/apps/web-platform/infra/inngest-provision-rehearsal-evidence.env"

# THE HOST NAME IS INTERPOLATED INTO SQL, so it is validated rather than trusted — AND it is
# constrained to rehearsal hosts. This script's caller may project matched rows into a public
# Actions log on a public repo, so an unconstrained reader is one flag away from exporting
# production boot telemetry. `soleur-inngest` (the PRODUCTION scheduler) satisfies a bare
# charset check perfectly; the trailing hyphen after `rehearsal-` is load-bearing for the
# same reason it is in the orphan sweep: `soleur-inngest` is a prefix of the rehearsal names.
# NO OVERRIDE FLAG — reading production boot telemetry is a different tool.
if [[ ! "$HOST_NAME" =~ ^soleur-inngest-rehearsal-[A-Za-z0-9._-]+$ ]]; then
  echo "refusing: --host-name must match ^soleur-inngest-rehearsal-[A-Za-z0-9._-]+$ — it is interpolated into the Better Stack SQL, AND this route may only read rehearsal hosts (never the production soleur-inngest). Got: ${HOST_NAME}" >&2
  exit 64
fi

# THE RUN COUPLING: --evidence-url must name the same run the host name encodes — the pair
# binds a measured rehearsal to the run whose log proves it (#8010 Guard-4 precedent).
if [[ ! "$EVIDENCE_URL" =~ ^https://github\.com/jikig-ai/soleur/actions/runs/[0-9]+ ]]; then
  echo "refusing: --evidence-url must be an Actions run URL for this repository (https://github.com/jikig-ai/soleur/actions/runs/<id>). Got: ${EVIDENCE_URL}" >&2
  exit 64
fi
_url_run_id="${EVIDENCE_URL#https://github.com/jikig-ai/soleur/actions/runs/}"
_url_run_id="${_url_run_id%%/*}"
_url_run_id="${_url_run_id%%\?*}"
_host_run_id="${HOST_NAME#soleur-inngest-rehearsal-}"
if [[ "$_host_run_id" != "$_url_run_id" ]]; then
  echo "refusing: --host-name and --evidence-url name DIFFERENT runs (host suffix '${_host_run_id}', url run id '${_url_run_id}')." >&2
  exit 64
fi

# --window and --since reach the WHERE clause, so they get the same treatment as --host-name.
if [[ ! "$WINDOW" =~ ^[0-9]+[[:space:]]+(MINUTE|HOUR|DAY|WEEK|MONTH)$ ]]; then
  echo "refusing: --window must be '<n> MINUTE|HOUR|DAY|WEEK|MONTH' (it is interpolated into the Better Stack SQL). Got: ${WINDOW}" >&2
  exit 64
fi
_ISO_TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$'
for _ts_flag in since reboot-since; do
  case "$_ts_flag" in
    since)        _ts_val="$SINCE" ;;
    reboot-since) _ts_val="$REBOOT_SINCE" ;;
  esac
  if [[ -n "$_ts_val" && ! "$_ts_val" =~ $_ISO_TS_RE ]]; then
    echo "refusing: --${_ts_flag} must be YYYY-MM-DDTHH:MM:SS (UTC, no zone suffix). Got: ${_ts_val}" >&2
    exit 64
  fi
done
if [[ "$MODE" == post-reboot && -z "$REBOOT_SINCE" ]]; then
  echo "refusing: --mode post-reboot requires --reboot-since (the timestamp recorded before the reboot action — without it 'no rows after the boundary' has no boundary)." >&2
  exit 64
fi
if ! [[ "$MIN_ATTEMPTS" =~ ^[0-9]+$ ]] || (( MIN_ATTEMPTS < 1 )); then
  echo "refusing: --min-attempts must be a positive integer. Got: ${MIN_ATTEMPTS}" >&2
  exit 64
fi

[[ -r "$QUERY" ]] || { echo "TRANSIENT: query transport ${QUERY} not found." >&2; exit 2; }

# ── Query helpers ────────────────────────────────────────────────────────────
# Mode-1 raw SQL against the source union (hot window + s3 archive). The host-name substring
# filter covers BOTH row shapes this host emits: phone-home JSON rows carry
# "host":"<hostname>" in the raw payload, and vector-shipped journald rows embed the
# hostname in the syslog header.
BS_SRC="(SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)"

# bs_query <sql> — runs the transport; rc on failure is propagated by callers.
bs_query() { bash "$QUERY" "$1"; }

# WHERE arm shared by every host-scoped query. SINCE pins to this run's window start when
# given (a re-run ATTEMPT reuses the run id, so an unpinned read could surface the previous
# attempt's rows); otherwise the --window bound applies.
host_where() {
  if [[ -n "$SINCE" ]]; then
    printf "dt > parseDateTime64BestEffort('%s') AND" "$SINCE"
  else
    printf "dt > now() - INTERVAL %s AND" "$WINDOW"
  fi
}

echo "capture: mode=${MODE} host=${HOST_NAME} window=${WINDOW}${SINCE:+ since=${SINCE}}"

# ── ANCHOR: is this source answering at all? ─────────────────────────────────
# NOT keyed on this host (see header). A zero-row answer means the instrument is dead, not
# the host — TRANSIENT, never FAIL.
ANCHOR_SQL="SELECT count() AS n FROM ${BS_SRC} WHERE $(host_where) raw != '' LIMIT 1"
ANCHOR_ROWS="$(bs_query "$ANCHOR_SQL" 2>/dev/null)" || {
  echo "TRANSIENT: the anchor query itself failed — the instrument cannot be trusted right now." >&2
  exit 2
}
ANCHOR_N="$(printf '%s' "$ANCHOR_ROWS" | jq -r 'try (.n | tonumber) catch 0' 2>/dev/null | head -1)"
if [[ ! "$ANCHOR_N" =~ ^[0-9]+$ ]] || (( ANCHOR_N == 0 )); then
  echo "TRANSIENT: zero rows from the source in the window — the instrument is silent, not the host." >&2
  exit 2
fi
echo "  anchor: source is answering (${ANCHOR_N} rows in window)"

# ── Host rows ────────────────────────────────────────────────────────────────
HOST_SQL="SELECT dt, raw FROM ${BS_SRC} WHERE $(host_where) position(raw, '${HOST_NAME}') > 0 ORDER BY dt LIMIT 2000"
HOST_ROWS="$(bs_query "$HOST_SQL" 2>/dev/null)" || {
  echo "TRANSIENT: the host-row query failed after a live anchor — transport fault." >&2
  exit 2
}

count_stage() { # <stage-substr> — count rows carrying this host's name AND the marker
  printf '%s\n' "$HOST_ROWS" | grep -cF -- "$1" 2>/dev/null || true
}

# IID DISCOVERY. Every provision marker carries iid=<cloud-init instance-id> in its detail;
# `provision-unit-armed` is emitted once per host life and is the first row guaranteed to
# carry it. An iid joined from this host's own armed row is how boot markers bind to THIS
# boot — host_name is stable across replaces, so iid is the discriminator.
IID="$(printf '%s\n' "$HOST_ROWS" | grep -oE 'iid=[A-Za-z0-9._-]+' | head -1 | sed 's/^iid=//')"
IID="${IID:-}"
if [[ -n "$IID" ]]; then
  echo "  iid resolved: ${IID}"
else
  echo "  iid: no iid= field found yet (no armed/attempt rows)"
fi

# VERDICT SEMANTICS, matched to the poll loop that calls this: FAIL is for a VIOLATION — a
# marker exists that the property forbids — which no further polling can heal. An ABSENT
# required marker is TRANSIENT, not FAIL: the marker may simply not have been emitted yet,
# and the workflow's own poll deadline is what converts "never arrived" into job failure.
# A capture that reported FAIL for "not yet" would burn a paid host on a timing accident.
violated=0   # a forbidden row exists -> FAIL
missing=""   # a required row is absent   -> TRANSIENT (poll again)
note() { printf '  %s\n' "$1"; }
ok()   { note "PASS: $1"; }
viol() { note "VIOLATION: $1"; violated=1; }
want() { note "WAIT: $1"; missing="${missing}$1; "; }

if [[ -z "$IID" && -z "$(printf '%s' "$HOST_ROWS" | tr -d '[:space:]')" ]]; then
  # Zero host rows with a live anchor is "dark so far", not "dark forever".
  echo "TRANSIENT (${MODE}): the source is answering but this host has emitted nothing yet — keep polling; the poll deadline owns the terminal verdict." >&2
  exit 2
fi

case "$MODE" in
  phase-a)
    # THE FORCED RACE'S EXPECTED-FAILURE FACE. Required, all for this host:
    #   provision-unit-armed            — the unit was armed on this boot
    #   >= MIN_ATTEMPTS provision-attempt-start — the retry loop actually retried
    #   >= 1 private_nic_timeout OR provision-nic-ABSENT — the NIC-absent failure was OBSERVED
    #   zero bootstrap-done             — nothing provisioned while the NIC was absent
    n_armed="$(count_stage provision-unit-armed)"
    n_start="$(count_stage provision-attempt-start)"
    n_nic_fail=$(( $(count_stage private_nic_timeout) + $(count_stage provision-nic-ABSENT) ))
    n_done="$(count_stage bootstrap-done)"
    (( n_done > 0 )) && viol "bootstrap-done emitted while the NIC was absent (n=${n_done}) — the provision path RAN WITHOUT the private net; this is the property under test, broken" || ok "no bootstrap-done while the NIC was absent"
    (( n_armed >= 1 ))           && ok "provision-unit-armed emitted for this host" || want "provision-unit-armed (n=${n_armed})"
    (( n_start >= MIN_ATTEMPTS )) && ok "provision-attempt-start count ${n_start} >= ${MIN_ATTEMPTS} (the retry loop retried NIC-less)" || want "provision-attempt-start count ${n_start} >= ${MIN_ATTEMPTS} (the retry loop retried NIC-less)"
    (( n_nic_fail >= 1 ))        && ok "NIC-absent failure observed (private_nic_timeout/provision-nic-ABSENT n=${n_nic_fail})" || want "NIC-absent failure observed (private_nic_timeout/provision-nic-ABSENT n=${n_nic_fail})"
    KEY=REHEARSAL_PHASE_A_OBSERVED
    ;;
  phase-b)
    # THE HEALED FACE: the phase-B attach converged and the FULL provision chain ran to
    # bootstrap-done for this iid — zot login, pull, isolation check, bootstrap all implied.
    # Failed attempts inside the window are EXPECTED (the unit retries), so exit rows are
    # reported, not required-zero — the success criterion is bootstrap-done itself.
    n_ok="$(count_stage private_nic_ok)"
    n_done="$(count_stage bootstrap-done)"
    n_exit="$(count_stage provision-attempt-exit-)"
    (( n_ok >= 1 ))   && ok "private_nic_ok emitted after the attach" || want "private_nic_ok emitted after the attach (n=${n_ok})"
    (( n_done >= 1 )) && ok "bootstrap-done emitted for this host" || want "bootstrap-done emitted for this host (n=${n_done})"
    note "info: ${n_exit} provision-attempt-exit-* row(s) in window (retries before convergence are expected)"
    KEY=REHEARSAL_PHASE_B_RECOVERY
    ;;
  post-reboot)
    # THE LATCH FACE: after the reboot boundary, the per-boot token-restage anchor MUST re-emit
    # (proving the boot ran and the scratch-Doppler channel works), and ZERO provision markers
    # may appear — the latch + OnBootSec re-entry refusal is the property under test.
    POST_ROWS="$(bs_query "SELECT dt, raw FROM ${BS_SRC} WHERE dt > parseDateTime64BestEffort('${REBOOT_SINCE}') AND position(raw, '${HOST_NAME}') > 0 ORDER BY dt LIMIT 2000" 2>/dev/null)" \
      || { echo "TRANSIENT: the post-reboot query failed after a live anchor." >&2; exit 2; }
    n_restage="$(printf '%s\n' "$POST_ROWS" | grep -cF 'SOLEUR_INNGEST_BS_TOKEN_RESTAGED' 2>/dev/null || true)"
    n_provision="$(printf '%s\n' "$POST_ROWS" | grep -cE 'provision-attempt-start|provision-attempt-exit|bootstrap-done|provision-unit-armed' 2>/dev/null || true)"
    (( n_provision > 0 )) && viol "${n_provision} provision marker(s) AFTER the reboot boundary — the latch did not hold (provision re-ran post-reboot)" || ok "zero provision markers after the reboot boundary — the latch held"
    (( n_restage >= 1 ))  && ok "token-restage anchor re-emitted post-reboot (proves this boot ran)" || want "token-restage anchor re-emitted post-reboot (n=${n_restage})"
    KEY=REHEARSAL_POST_REBOOT_LATCH
    ;;
esac

if (( violated )); then
  echo "FAIL (${MODE}): a forbidden marker exists — see the table above." >&2
  exit 1
fi
if [[ -n "$missing" ]]; then
  echo "TRANSIENT (${MODE}): still missing — ${missing}" >&2
  exit 2
fi

# ── Evidence write ───────────────────────────────────────────────────────────
assert_fixture_dir "$OUT"
mkdir -p "$(dirname "$OUT")"
{
  printf '# inngest provision forced-race rehearsal evidence — %s\n' "$MODE"
  printf '%s=PASS\n' "$KEY"
  printf 'REHEARSAL_HOST=%s\n' "$HOST_NAME"
  printf 'REHEARSAL_RUN_URL=%s\n' "$EVIDENCE_URL"
  [[ -n "$IID" ]] && printf 'REHEARSAL_IID=%s\n' "$IID"
  printf 'CAPTURED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$OUT"
echo "PASS (${MODE}): appended ${KEY}=PASS to ${OUT}"
exit 0
