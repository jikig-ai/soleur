#!/usr/bin/env bash
#
# (#7025) Capture rung-2 boot evidence for a git-data REHEARSAL host.
#
# WHAT THIS DECIDES. Whether `apps/web-platform/infra/git-data-rung2-boot-evidence.env` gets
# written — the file whose presence releases git_data_rung2_rehearsal_gate, which is the
# binding mechanical hold on the birth of the host that will store every connected user's
# source code. It writes on PASS and on nothing else.
#
# THREE-STATE CONTRACT, inherited from git-data-birth-emitter-6982.sh and from the repo's
# documented convention (chardevice-wedge-nonrecurrence-5934.sh):
#   0 = PASS      — the rehearsal host completed its boot with every assertion positive.
#   1 = FAIL      — the host reported a fatal, or completed with an assertion false.
#   2 = TRANSIENT — nothing is known yet, or the instrument itself could not be trusted.
#
# THE HARD PART IS SILENCE, and it is worth stating before the code rather than after.
#
# A Better Stack query returning zero rows for a brand-new host is AMBIGUOUS. It is the same
# result whether the host booted dark, or the credentials are wrong, or the table name
# drifted, or the query has a typo in its WHERE clause. Reading that as "dark boot" grounds a
# rehearsal that may have been fine; reading it as "not yet" writes nothing and eventually
# times out, which is at least honest but tells the operator nothing about which it was.
# `hr-no-dashboard-eyeball-pull-data-yourself` forbids resolving this by looking at a
# dashboard, so it has to be resolved in the query set.
#
# THE ANCHOR RESOLVES IT, AND IT IS NOT THE ANCHOR THE PLAN SPECIFIED. The plan proposed
# anchoring on `stage:bootcmd_start` from this host, "which fires first, at cloud-init:33".
# MEASURED, that emit cannot reach Better Stack at all: it is a bare `curl` to Sentry inside
# `bootcmd`, which runs BEFORE `write_files`, so `/usr/local/bin/git-data-emit` does not exist
# yet and there is no Better Stack call in it. Worse, the emitter's Better Stack block is
# gated on `BETTERSTACK_LOGS_TOKEN` being in the environment.
#
# SUPERSEDED IN PART BY #7460: that token is now BAKED, so the gate is satisfied from
# `write_files` onward and EIGHT of the nine stages reach this source rather than one. The
# `bootcmd` beacon stays Sentry-only by construction — it fires before `write_files`, so the
# shared emitter does not exist yet, and no baked token changes that.
#
# The anchor's rationale is UNCHANGED and is why it was never keyed on this host: an anchor
# that is a strict prerequisite of the thing it is anchoring is not an anchor; it would have
# returned zero rows on a perfect rehearsal, forever, and the failure would have read as
# "dark boot". What DID change is the row-window bound — see FATAL_SQL below.
#
# So the anchor asks a different question: IS THIS SOURCE ANSWERING AT ALL? One query for any
# row from any host in the window. If the source is live and this host said nothing, the
# silence is about the host. If the source is dead, the silence is about the instrument and
# this script has no verdict to offer. That distinction is the entire point, and the arms in
# tests/scripts/test-git-data-rung2-evidence-capture.sh pin both directions.
#
# WHAT THIS DOES NOT CLAIM, stated because a gate believed to cover more than it does is worse
# than one whose scope is written down:
#   - It does not verify the SENTRY channel independently. NOTE, corrected 2026-08-03 (#7204):
#     the reason is NOT that search is unavailable — an earlier revision of this comment said
#     "Sentry has no search capability wired in this repo", and that is FALSE. Measured:
#     SENTRY_ISSUE_RO_TOKEN (Doppler soleur/prd, [event:read, org:read]) returns HTTP 200 on
#     /api/0/organizations/jikigai-eu/issues/?query=..., including a host_name: query. Only
#     scripts/sentry-issue.sh is id-shaped; the API is not. This route simply does not
#     implement the read — a scope decision, not a capability limit. It matters because #7116
#     (mis-reporting TRANSIENT for early-boot fatals it could read from Sentry directly) must
#     be planned against what is actually possible, and a false constraint in this header
#     would have planned it against a wall that does not exist
#     (hr-verify-repo-capability-claim-before-assert).
#
#     SUPERSEDED 2026-09-02 (#7481). This block used to end "#7116 owns that work; do not do
#     it here." #7116 is CLOSED — with the work REVERTED, which is why #7481 re-specifies it —
#     so an agent opening this file to implement the second channel was reading a prohibition
#     on its own task, citing an issue that no longer owns anything. The read is now
#     IMPLEMENTED here, via scripts/sentry-issue.sh --host-events, and the paragraph above
#     stands as the measurement that made it possible rather than as a reason not to.
#     The fatal channel is additionally proven at RUNG 1
#     by git-data-runcmd-rehearsal.test.sh, which shows the trap firing and emitting `fatal`;
#     rung 2's job is the real-host facts rung 1 structurally cannot reach — TLS egress from a
#     real Hetzner host, a real `doppler run`, and a real `cryptsetup luksOpen`.
#   - It does not verify the render VARS. The hash binds the template and the nine payloads,
#     never the templatefile arguments — which is why it writes RUNG2_VAR_DIVERGENCE and why
#     the gate refuses anything outside an identity-only allowlist.
#
# Usage (under doppler so the Better Stack credentials are injected):
#   doppler run -p soleur -c prd_terraform -- \
#     scripts/followthroughs/git-data-rung2-evidence-capture.sh \
#       --host-name soleur-git-data-rehearsal-<run-id> \
#       --evidence-url https://github.com/jikig-ai/soleur/actions/runs/<run-id> \
#       [--out <path>] [--cloud-init <path>] [--window '30 DAY'] [--verify-only]
set -uo pipefail

# A TERMINAL SENTINEL, PRINTED ON EVERY EXIT PATH. The workflow wraps this script in
# `doppler run`, which exits 1 on ITS OWN failures (measured: a bad token, and a bad
# project/config, both give rc=1) — the same code this script uses for FAIL. Without a
# sentinel the wrapper cannot tell "the rehearsal host reported a fatal" from "the capture
# script never ran a line", and it reported the former, sending the operator to diagnose a
# boot that was fine. The trap fires on the real exit code whatever path produced it.
trap 'printf "RUNG2_CAPTURE_VERDICT=%s\n" "$?"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Env override is the TEST SEAM, and the only one: the suite stubs the query transport rather
# than the decision function, so every arm exercises the real branching.
QUERY="${BETTERSTACK_QUERY_SH:-${REPO_ROOT}/scripts/betterstack-query.sh}"
GATE_LIB="${REPO_ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"

HOST_NAME=""
EVIDENCE_URL=""
CLOUD_INIT="${REPO_ROOT}/apps/web-platform/infra/cloud-init-git-data.yml"
OUT=""
WINDOW="30 DAY"
SENTRY_SINCE=""
VERIFY_ONLY=0
DIVERGENCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    # `shift 2 || shift` — a bare `shift 2` with only the flag left FAILS and leaves $#
    # unchanged, so the parse loop never terminates. Measured in the sibling reader this
    # session: the process hung until its caller's timeout killed it, which on this route
    # would burn the poll budget against a paid host with no verdict and no message.
    --host-name)    HOST_NAME="${2:-}"; shift 2 || shift ;;
    --evidence-url) EVIDENCE_URL="${2:-}"; shift 2 || shift ;;
    --since)        SENTRY_SINCE="${2:-}"; shift 2 || shift ;;
    --cloud-init)   CLOUD_INIT="${2:-}"; shift 2 || shift ;;
    --out)          OUT="${2:-}"; shift 2 || shift ;;
    --window)       WINDOW="${2:-}"; shift 2 || shift ;;
    --divergence)   DIVERGENCE="${2:?--divergence needs a value}"; shift 2 || shift ;;
    --verify-only)  VERIFY_ONLY=1; shift ;;
    --) shift ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

[[ -z "$OUT" ]] && OUT="$(dirname "$CLOUD_INIT")/git-data-rung2-boot-evidence.env"

if [[ -z "$HOST_NAME" ]]; then
  echo "usage: git-data-rung2-evidence-capture.sh --host-name soleur-git-data-rehearsal-<run-id> --evidence-url <url> [--out <path>]" >&2
  exit 64
fi

# THE HOST NAME IS INTERPOLATED INTO SQL, so it is validated rather than trusted. It reaches
# the WHERE clause of every query below; a name carrying a quote would either break the query
# or change which rows it selects, and "which rows" is the whole verdict.
#
# (#7227 item 4) AND IT IS CONSTRAINED TO REHEARSAL HOSTS. The charset rule alone says nothing
# about WHICH host: `soleur-git-data` — the production store holding every connected user's
# source code — satisfies `^[A-Za-z0-9._-]+$` perfectly. This script's caller projects the
# `detail` field of every matched row into a PUBLIC Actions log on a PUBLIC repo, so an
# unconstrained reader is one flag away from exporting production boot telemetry.
#
# STRICTLY NARROWER, never merely different: the trailing `[A-Za-z0-9._-]+` keeps the charset
# property (a prefix check written as a bare glob would accept
# `soleur-git-data-rehearsal-1" OR 1=1 --`), and the only production call site passes
# `${REHEARSAL_PREFIX}${GITHUB_RUN_ID}`, which still matches. The trailing HYPHEN in the
# prefix is load-bearing for the same reason it is in both orphan sweeps: `soleur-git-data`
# is a prefix of the rehearsal names, so omitting it re-admits production.
#
# NO OVERRIDE FLAG. Reading production boot telemetry is a different tool with a different
# output contract, not a flag on this one — an `--allow-production` escape hatch reopens the
# hole for exactly the caller most likely to be in a hurry. And the emitter's 180-byte bound
# is NOT a substitute: it bounds VOLUME, not CONTENT, and it is applied on the host at emit
# time. This script is a reader and inherits whatever shipped.
if [[ ! "$HOST_NAME" =~ ^soleur-git-data-rehearsal-[A-Za-z0-9._-]+$ ]]; then
  echo "refusing: --host-name must match ^soleur-git-data-rehearsal-[A-Za-z0-9._-]+$ — it is interpolated into the Better Stack SQL, AND this route projects matched rows into a public Actions log, so it may only read rehearsal hosts (never the production soleur-git-data). Got: ${HOST_NAME}" >&2
  exit 64
fi

# REFUSE A GATE-UNACCEPTABLE URL AT WRITE TIME. The gate requires an Actions run URL for this
# repository (#7025 R8). Discovering a typo at gate time means re-running a rehearsal that
# already cost a real host and ~8 minutes of wall clock — the expensive way to learn it.
if [[ ! "$EVIDENCE_URL" =~ ^https://github\.com/jikig-ai/soleur/actions/runs/[0-9]+ ]]; then
  echo "refusing: --evidence-url must be an Actions run URL for this repository (https://github.com/jikig-ai/soleur/actions/runs/<id>), because git_data_rung2_rehearsal_gate refuses anything else. Got: ${EVIDENCE_URL}" >&2
  exit 64
fi

# `--window` REACHES THE SAME `WHERE` CLAUSE, so it gets the same treatment as --host-name.
#
# Caught in review: --host-name was validated precisely BECAUSE it is interpolated into the
# Better Stack SQL, and then `WINDOW` was interpolated into `INTERVAL ${WINDOW}` in BOTH
# queries with no validation at all — the sibling parameter, same sink, missed. It is
# operator-supplied rather than attacker-controlled, so this is not a remote injection; but
# "which rows the query returns" IS the verdict this script produces, and a malformed or
# creative window silently changes what was measured while still reporting a verdict.
if [[ ! "$WINDOW" =~ ^[0-9]+[[:space:]]+(MINUTE|HOUR|DAY|WEEK|MONTH)$ ]]; then
  echo "refusing: --window must be '<n> MINUTE|HOUR|DAY|WEEK|MONTH' (it is interpolated into the Better Stack SQL). Got: ${WINDOW}" >&2
  exit 64
fi

# ── THE SECOND CHANNEL (#7481) ──────────────────────────────────────────────────────
#
# WHY IT EXISTS. It USED to be that everything before `doppler run` reached SENTRY ONLY, because
# the emitter's Better Stack block was gated on BETTERSTACK_LOGS_TOKEN and that token arrived
# only under `doppler run`. #7460 (ADR-198) bakes the token at 0600, so eight of the nine stages
# now reach Better Stack and only `bootcmd_start` is Sentry-only. The consult still earns its
# place: the bootcmd beacon, a token that failed to load, and any Better Stack ingest outage all
# leave Sentry as the only witness. A host that dies at luks_open — which is what the 2026-07-31
# rehearsal did — is no longer invisible to Better Stack, but every Better-Stack-silent condition
# report TRANSIENT for a failure Sentry could name. The workflow then retries rc=2 twenty
# times over ~16 minutes against a paid cpx22 before saying "do not simply re-dispatch".
#
# ONE HELPER, NOT SIX PLACEMENTS. The first design enumerated the call sites and got the list
# wrong twice — it named the two credential-preflight sites where its own justification named
# the two TRANSPORT-failure sites, which are a different pair. Enumerated member sets rot.
# Every no-verdict path funnels through transient(), so: one consult implementation; the
# mutation "revert one site to a bare `exit 2`" is caught by ONE arm grepping for a bare
# `exit 2` outside this helper with the derivation-fault site excluded by name and a floor on
# the count; and a seventh no-verdict path added next year is covered by construction.
# A TEST SEAM, and it is named so it reads as one. The arms in
# tests/scripts/test-git-data-rung2-evidence-capture.sh must drive the consult through every
# verdict it can produce — a fatal WITH a cause, a fatal with an EMPTY cause, clean, and each
# terminal refusal — and none of those are reachable against the live API from a suite that
# must run offline and hermetically. The override is deliberately NOT a general "point this
# anywhere" knob in production: nothing sets SOLEUR_SENTRY_READER outside the suite, and the
# default is the committed reader.
# GATED ON A TEST MARKER, not on the override alone. This script runs under
# `doppler run -c prd_terraform`, which exports EVERY name in that config (160 of them), so
# a bare `${SOLEUR_SENTRY_READER:-…}` is an arbitrary-command sink one config entry away —
# the same env-injection class this PR pinned PINNED_ORG/PINNED_PROJECT_ID against, which
# would have been reintroduced by the seam added to test the fix.
SENTRY_READER="${REPO_ROOT}/scripts/sentry-issue.sh"
if [[ -n "${SOLEUR_TEST_MODE:-}" && -n "${SOLEUR_SENTRY_READER:-}" ]]; then
  SENTRY_READER="$SOLEUR_SENTRY_READER"
fi

# Sentry's window, derived from the SAME --window this script already validates, so the two
# channels cannot disagree about what period a verdict covers. --since (ISO, passed by the
# workflow from the timestamp it recorded before applying) pins the read to THIS run instead,
# which is what actually closes #7481 defect 5: host_name embeds the run id, but a run id is
# STABLE across GitHub re-run ATTEMPTS, so an unpinned read lets attempt 2 of a fixed host
# report attempt 1's fatal. Without --since the residual is real and is stated, not hidden.
_sentry_window_args() {
  if [[ -n "$SENTRY_SINCE" ]]; then
    printf '%s\n' "--start" "$SENTRY_SINCE" "--end" "$(date -u +%Y-%m-%dT%H:%M:%S)"
    return 0
  fi
  # THE DEGRADE IS DELIBERATE AND MUST STAY VISIBLE. --since is optional because the workflow
  # passes "${RUNG2_SENTRY_SINCE:-}": on a path where the apply step did not run there is no
  # apply timestamp, and the caller MUST NOT die at an unset expansion — measured, requiring it
  # made every capture invocation exit 3 (WRAPPER FAILURE) and reddened 8 arms in
  # git-data-rung2-rehearsal.test.sh, i.e. the read never happened and the harness blamed the
  # doppler wrapper. Falling back to the --window period is correct but WIDER, so the consult
  # prints which shape it used rather than letting a run-pinned read and a 30-day read look
  # identical in the log.
  local n unit
  n="${WINDOW%% *}"; unit="${WINDOW##* }"
  case "$unit" in
    MINUTE) printf '%s\n' "--stats-period" "${n}m" ;;
    HOUR)   printf '%s\n' "--stats-period" "${n}h" ;;
    DAY)    printf '%s\n' "--stats-period" "${n}d" ;;
    WEEK)   printf '%s\n' "--stats-period" "${n}w" ;;
    # Sentry has no month unit; 30 days is the conservative (wider) reading.
    MONTH)  printf '%s\n' "--stats-period" "$(( n * 30 ))d" ;;
    *)      printf '%s\n' "--stats-period" "30d" ;;
  esac
}

# Prints the consult's verdict lines. Sets _SENTRY_VERDICT to FATAL | CLEAN | UNAVAILABLE.
_sentry_consult() {
  _SENTRY_VERDICT="UNAVAILABLE"
  # STRUCTURAL PREFLIGHTS FIRST, so an absent tool or token is a cheap named refusal rather
  # than a 401 discovered mid-poll or an rc=127 that reads most naturally as "not an array".
  if ! command -v jq >/dev/null 2>&1; then
    # MEASURED-BY: the `command -v jq` test on the line directly above. The message names a
    # cause, and that cause is the branch condition itself — but lint-diagnosis-claims cannot
    # see a basis that lives in the enclosing `if`, and its baseline ratchets DOWN only, so
    # the annotation is the sanctioned fix rather than a baseline bump (ADR-166).
    echo "  second channel: SKIPPED — jq is not installed, so a Sentry result could not be parsed."
    echo "  **Next:** install jq on the runner. Re-dispatching will not change this."
    return 0
  fi
  if [[ -z "${SENTRY_ISSUE_RO_TOKEN:-}" ]]; then
    echo "  second channel: SKIPPED — SENTRY_ISSUE_RO_TOKEN is unset, so the Sentry-only stages"
    echo "  (everything before \`doppler run\`) could not be read. This is NOT evidence the host"
    echo "  emitted nothing there."
    echo "  **Next:** add SENTRY_ISSUE_RO_TOKEN to the config this step runs under. Re-dispatching"
    echo "  will not change this."
    return 0
  fi
  if [[ ! -r "$SENTRY_READER" ]]; then
    echo "  second channel: SKIPPED — ${SENTRY_READER} not found."
    echo "  **Next:** this is a repo defect, not a host condition. Re-dispatching will not change it."
    return 0
  fi

  local _w=() _out _rc
  mapfile -t _w < <(_sentry_window_args)
  if [[ -n "$SENTRY_SINCE" ]]; then
    echo "  second channel: querying Sentry, window pinned to this run (since ${SENTRY_SINCE})."
  else
    echo "  second channel: querying Sentry over the --window period (${WINDOW}) — NOT pinned to"
    echo "  this run, because no --since was supplied. A re-run ATTEMPT of the same run id can"
    echo "  therefore surface an earlier attempt's fatal; weigh the timestamps below."
  fi
  # STDERR TO ITS OWN STREAM. Merging it into the parsed body meant any stderr byte on an
  # HTTP-200 read failed the shape guard below and degraded a genuine FATAL to UNAVAILABLE —
  # which, on the PASS path where UNAVAILABLE deliberately does not block, is a FAIL-OPEN on
  # the branch that writes gate-releasing evidence. This is the same "status into a separate
  # stream" discipline the reader itself applies, violated in its consumer.
  local _errf; _errf="$(mktemp -t rung2-sentry.XXXXXXXX.err)"
  _out="$(bash "$SENTRY_READER" --host-events "$HOST_NAME" "${_w[@]}" 2>"$_errf")"; _rc=$?
  local _err; _err="$(cat "$_errf" 2>/dev/null || echo '')"; rm -f "$_errf"

  case "$_rc" in
    0) : ;;
    77|78)
      # DETERMINISTIC AND TERMINAL. A 401/403 is repo/credential-side and identical on every
      # attempt; retrying it spends the whole poll budget to report the least actionable
      # verdict, against a paid host.
      echo "  second channel: UNAVAILABLE — Sentry refused the read (rc=${_rc}; 77=401 scope/membership, 78=403 wrong token)."
      printf '%s\n' "$_err" | head -3 | sed 's/^/    /'
      echo "  **Next:** fix SENTRY_ISSUE_RO_TOKEN's scope. This is DETERMINISTIC — re-dispatching"
      echo "  will reproduce it exactly and burn another paid host."
      return 0 ;;
    *)
      echo "  second channel: UNAVAILABLE — the Sentry read failed (rc=${_rc}). The read did NOT run;"
      echo "  this is NOT a 'the host emitted nothing to Sentry' result."
      printf '%s\n' "$_err" | head -3 | sed 's/^/    /'
      echo "  **Next:** read the lines above. If they name a transport fault, one re-dispatch is"
      echo "  reasonable; if they name a query or scope fault, it is not."
      return 0 ;;
  esac

  # SHAPE BEFORE COUNT (the reader validates it too; this is the consumer's own guard, because
  # `jq -e` on `null | length` returns 0 AND exits 0 — a count is never the first thing trusted).
  if ! printf '%s' "$_out" | jq -e 'type == "object" and ((.data | type) == "array")' >/dev/null 2>&1; then
    echo "  second channel: UNAVAILABLE — Sentry returned a body this route cannot parse."
    echo "  **Next:** treat as instrument failure, not as a host verdict."
    return 0
  fi

  local _n
  _n="$(printf '%s' "$_out" | jq -r '.data | length')"
  if [[ "$_n" -eq 0 ]]; then
    # ZERO ROWS IS TWO STATES, and only one of them is good news. "Sentry holds no fatal for
    # this host" and "this read reached nothing at all" are byte-identical here — a stale
    # PINNED_PROJECT_ID, a recreated project, a dark ingest, or an org the token lost
    # membership in ALL return HTTP 200 with an empty .data. On the PASS path that reads as
    # "cross-check passed" and releases the birth hold, so the zero is corroborated rather
    # than trusted. This is what --liveness is for; without this call it was dead code.
    #
    # The anchor EXCLUDES this host by design: its own unconditional level:info bootcmd
    # beacon would otherwise satisfy it, making it vacuous exactly when it matters.
    local _lw=() _lout _lrc _lerrf _lcount
    mapfile -t _lw < <(_sentry_window_args)
    _lerrf="$(mktemp -t rung2-live.XXXXXXXX.err)"
    _lout="$(bash "$SENTRY_READER" --liveness "$HOST_NAME" "${_lw[@]}" 2>"$_lerrf")"; _lrc=$?
    rm -f "$_lerrf"
    _lcount=""
    if [[ "$_lrc" -eq 0 ]]; then
      _lcount="$(printf '%s' "$_lout" | jq -r '.data[0]["count()"] // empty' 2>/dev/null || echo '')"
    fi
    if [[ -z "$_lcount" || ! "$_lcount" =~ ^[0-9]+$ || "$_lcount" -eq 0 ]]; then
      echo "  second channel: UNAVAILABLE — the fatal read returned zero rows AND the liveness"
      echo "  anchor could not confirm the source is answering (rc=${_lrc}, count=${_lcount:-none})."
      echo "  A zero-row read from a dark or misaddressed source is not a clean bill."
      echo "  **Next:** verify SENTRY_ISSUE_RO_TOKEN's org membership and that the pinned project"
      echo "  id still resolves. Re-dispatching will not change either."
      return 0
    fi
    _SENTRY_VERDICT="CLEAN"
    echo "  second channel: Sentry has NO level:fatal event for ${HOST_NAME} in this window,"
    echo "  and the source is answering (${_lcount} event(s) from other hosts)."
    return 0
  fi

  _SENTRY_VERDICT="FATAL"
  echo "  second channel: Sentry reports ${_n} level:fatal event(s) for ${HOST_NAME}:"
  # WHAT THE READER PRINTS, not only who reads. A verdict that names the stage and withholds
  # the cause is this route's ORIGINATING incident: on 2026-07-31 the artifact carried
  # `stage:luks_open level:fatal` and no `detail`, and the cause (`mount(2) ... ESRCH` from an
  # ext4 quota feature) had to be re-queried by hand. An EMPTY detail is reported AS empty —
  # "FAIL, cause unavailable" is honest; a cause-shaped blank is not.
  printf '%s' "$_out" | jq -r '.data[] |
      "    stage=\(.stage // "-") rc=\(.rc // "-") at \(.timestamp // "-")\n      detail: " +
      (if ((.detail // "") | tostring | ltrimstr("[") | rtrimstr("]") | gsub("\\s";"") | length) == 0
         then "(EMPTY — Sentry carries this fatal but no cause text. An empty JSON array counts as empty here too: that is the DETAIL=[] shape #7204 records.)"
         else (.detail | tostring) end)' 2>/dev/null | head -20
  return 0
}

# transient() — THE ONLY no-verdict exit in this script, and the point at which a
# Better-Stack-silent condition gets a second opinion before it is called "nothing is known".
transient() {
  printf '%s\n' "$@"
  echo
  _sentry_consult
  if [[ "$_SENTRY_VERDICT" == "FATAL" ]]; then
    echo
    echo "FAIL (Sentry-derived): ${HOST_NAME} reported a fatal that the Better Stack channel could"
    echo "not see. This is the failure class #7481 names — the boot died before \`doppler run\`, so"
    echo "the only channel carrying it is Sentry, and reporting TRANSIENT here would have sent the"
    echo "operator to re-dispatch a host that failed for a knowable reason."
    echo
    echo "NO EVIDENCE FILE WRITTEN."
    echo "**Next:** fix the cause named above, then re-run the rehearsal against the corrected"
    echo "template. Do NOT simply re-dispatch — each dispatch spends a paid cpx22."
    exit 1
  fi
  echo
  echo "TRANSIENT: no verdict. Both channels are silent or unavailable (see above), so this run"
  echo "declines to read silence as a dark boot."
  exit 2
}

# --since is OPTIONAL, but a malformed one is refused rather than silently widening the read:
# it is interpolated into the Sentry window, and which rows the query returns is the verdict.
if [[ -n "$SENTRY_SINCE" && ! "$SENTRY_SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
  echo "refusing: --since must be YYYY-MM-DDTHH:MM:SS (UTC, no zone suffix). Got: ${SENTRY_SINCE}" >&2
  exit 64
fi

# THE PREFLIGHT IS WHAT SEPARATES "I QUERIED AND SAW NOTHING" FROM "I NEVER QUERIED". Without
# it, a missing credential produces silence that is indistinguishable from a dark boot.
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    transient "TRANSIENT: ${v} is unset — cannot query Better Stack Logs, so this run has no verdict to offer (it is NOT evidence that the host booted dark). Re-run wrapped in: doppler run -p soleur -c prd_terraform -- ..."
  fi
done

[[ -x "$QUERY" || -r "$QUERY" ]] || transient "TRANSIENT: ${QUERY} not found"

# The archive arm is REQUIRED, not belt-and-braces: remote() alone is the ~40-minute hot
# window (measured 2026-07-15 for the #6982 probe), and a once-per-boot marker falls out of it
# immediately. Field isolation via Mode 1 raw SQL — a bare-substring --grep compiles to
# `raw LIKE '%…%'` and this source is shared with inngest webhook logs that quote issue bodies.
#
# Mode 1 takes the query as the FIRST POSITIONAL and accepts no convenience flags: `--since`
# belongs to Mode 2 and passing both makes the arg parser reject the SQL with exit 64. The
# #6982 probe's first draft did exactly that, which would have made it exit non-zero forever
# for a USAGE reason while reading as "still waiting". The window therefore lives INSIDE the SQL.
_bs_source="(SELECT dt, raw FROM remote(\$BS_TABLE)
             UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)"

# `__ANCHOR__` / `__HOSTROWS__` are inert SQL comments that name which question is being
# asked. They exist so the test suite's stub can answer BY QUERY SHAPE rather than by call
# ordinal — a counter-based stub bakes this script's current call ORDER into the fixture, and
# a stub that returns the right rows in the wrong order makes a broken script look correct.
#
# THE KEYWORD COMES FIRST, AHEAD OF THE COMMENT. betterstack-query.sh admits Mode 1 on
# `^[[:space:]]*(SELECT|WITH|SHOW)[[:space:]]`: `[[:space:]]*` eats the newline and indent and
# then requires the keyword, so a LEADING `/* … */` fails the match, the SQL falls through to
# the Mode 2 flag parser, and it exits 64 `unknown flag` on the FIRST query. That is rc!=0 ->
# this script exits 2 TRANSIENT -> the poll burns all 20 attempts -> RUNG2_BOOT_REHEARSAL=PASS
# is unreachable and the interlock can never be released by this route.
#
# The comment above already warned about this exit-64-for-a-USAGE-reason trap in its `--since`
# form, and this shape walked into it anyway — the tell that a prose warning is not a guard.
# Every arm of the test suite stubs betterstack-query.sh and dispatches on `__ANCHOR__`, the
# token INSIDE the comment that broke the real transport, so 28 green assertions certified a
# route that could not run. The admissibility arm in that suite runs the REAL script and is
# what actually holds this line in place.
ANCHOR_SQL="
  SELECT /* __ANCHOR__ source-liveness: is this log source answering AT ALL? */
         dt, JSONExtractString(raw,'host_name') AS host
  FROM ${_bs_source}
  WHERE dt > now() - INTERVAL ${WINDOW}
    AND JSONExtractString(raw,'host_name') != ''
    AND JSONExtractString(raw,'host_name') != '${HOST_NAME}'
  ORDER BY dt DESC LIMIT 5 FORMAT JSONEachRow"

# (#7204) `detail` AND `rc` ARE SELECTED HERE, and this is the single change that would have
# made #7204 self-diagnosing. The FAIL arm already printed matching rows — but the projection
# carried a VERDICT WITH NO CAUSE, so diagnosing "stage:luks_open, level:fatal" required
# hand-writing a new Better Stack query to discover the mount had returned ESRCH. The cause
# was in the row the whole time; the artifact just never asked for it.
#
# `rc` rides in $TAGS, which the emitter concatenates at TOP LEVEL of the JSON body, so
# JSONExtractString(raw,'rc') resolves — it is not nested under tags. Both columns are pinned
# by a mutation-armed assertion in git-data-rung2-rehearsal.test.sh; a column with no consumer
# would be dropped rather than added.
#
# KNOWN-EMPTY BY CONSTRUCTION, enumerated so a reader does not over-read them: the four
# assertion booleans below are emitted ONLY on a stage:boot_complete row. git-data-bootstrap.sh
# sets them there; the luks_err trap passes only rc=. On EVERY non-boot_complete row they are
# structurally empty, so "all four are blank" carries no information about how far the boot
# got — the `stage` tag is the only positional fact in a FAIL row. #7204's source brief made
# exactly that over-read.
# ONE SCOPE, BOTH QUERIES. The §5.0 argument -- "the fatal question must be unbounded by row
# chatter" -- only holds if the two queries cover the SAME period. Two copies of the window
# clause could drift apart silently and the verdict would then read a different period than the
# evidence claims.
#
# ATTEMPT-PINNED whenever --since is supplied. HOST_NAME embeds GITHUB_RUN_ID, which is STABLE
# across re-runs (#7481 defect 5), and WINDOW defaults to 30 DAY. So on attempt 2 of a run whose
# template was FIXED, an ORDER BY dt ASC scan surfaces attempt 1's fatal and the rehearsal FAILs
# forever. The old ORDER BY dt DESC LIMIT 50 hid that by accident; #7460 removed the accident
# without replacing the isolation. The Sentry consult was already bounded this way (see the
# --start/--end block below); this is the same bound on the Better Stack side.
if [[ -n "$SENTRY_SINCE" ]]; then
  _BS_WHEN="dt > parseDateTimeBestEffort('${SENTRY_SINCE}')"
else
  _BS_WHEN="dt > now() - INTERVAL ${WINDOW}"
fi
_BS_SCOPE="${_BS_WHEN}
    AND JSONExtractString(raw,'host_name') = '${HOST_NAME}'"

HOST_SQL="
  SELECT /* __HOSTROWS__ every stage this rehearsal host reported */
         dt,
         JSONExtractString(raw,'stage')         AS stage,
         JSONExtractString(raw,'level')         AS level,
         JSONExtractString(raw,'host_name')     AS host,
         JSONExtractString(raw,'detail')        AS detail,
         JSONExtractString(raw,'rc')            AS rc,
         JSONExtractString(raw,'luks_mounted')  AS luks_mounted,
         JSONExtractString(raw,'repo_root')     AS repo_root,
         JSONExtractString(raw,'hooks_path')    AS hooks_path,
         JSONExtractString(raw,'provision')     AS provision
  FROM ${_bs_source}
  WHERE ${_BS_SCOPE}
  ORDER BY dt DESC LIMIT 50 FORMAT JSONEachRow"

# THE FATAL ARM MUST NOT BE ROW-WINDOW-BOUNDED (#7460 §5.0).
#
# HOST_SQL keeps the NEWEST 50 rows. That was safe only while the channel split held and a
# healthy boot produced a single row. Now that eight stages emit — and the emitter fires far
# more often than once per stage (sshd warn, mount, gc-timer, the LUKS trap, per-stage
# `on_err`) — an EARLY fatal followed by enough later rows drops out of the window. The FAIL
# arm would then find nothing, fall through to the boot_complete check, and write PASS over an
# unread fatal.
#
# A verdict that depends on how chatty a healthy boot happens to be is not a verdict, so the
# fatal question gets its own query: same host, same window, filtered server-side to
# level='fatal', with a bound far above any plausible fatal count rather than above any
# plausible ROW count. `LIMIT 1000` is a runaway guard, not a window — a boot emitting 1000
# fatals has already answered the question this script asks.
FATAL_SQL="
  SELECT /* __FATALROWS__ every FATAL this rehearsal host reported, unbounded by row chatter */
         dt,
         JSONExtractString(raw,'stage')  AS stage,
         JSONExtractString(raw,'level')  AS level,
         JSONExtractString(raw,'host_name') AS host,
         JSONExtractString(raw,'detail') AS detail,
         JSONExtractString(raw,'rc')     AS rc
  FROM ${_bs_source}
  WHERE ${_BS_SCOPE}
    AND JSONExtractString(raw,'level') = 'fatal'
  ORDER BY dt ASC LIMIT 1000 FORMAT JSONEachRow"

# (#7772 item 1) PIN THE TABLE TO GIT-DATA'S OWN SOURCE. betterstack-query.sh defaults BS_TABLE
# to `t520508_soleur_inngest_vector_prd_3_logs` — the SHARED source (2457081) this host stopped
# shipping to. git-data now has its own source, 2734275 / table_name `soleur_git_data_prd`, and
# the naming convention the query script documents is `t<team>_<table_name>_logs`.
#
# WHY THIS IS NOT COSMETIC. Leaving the default in place does not error: the shared table exists
# and answers, it simply holds no rows from a host that no longer writes there. Every arm of this
# capture would then read an empty result and report a DARK BOOT — on a rehearsal that cost a real
# Hetzner host and in fact booted fine. A false FAIL is the expensive direction here, because the
# operator's next move is to re-dispatch (another paid host) rather than to doubt the query.
# Exported rather than passed as `--table` so the S3 sibling derives from it (BS_TABLE_S3 defaults
# to `${BS_TABLE%_logs}_s3`), keeping the hot and archive arms on the same source by construction.
#
# THE TABLE IS CREATED LAZILY, ON FIRST INGEST — measured 2026-09-03, minutes after the source was
# minted: `SELECT count() FROM remote(t520508_soleur_git_data_prd_logs)` answered HTTP 500
# `Code: 701 … CLUSTER_DOESNT_EXIST`, not an empty result set. The name is right (the API reports
# team_id=520508 and table_name=soleur_git_data_prd, and the incumbent derives identically); the
# table just does not exist until something writes to it.
#
# So on a rehearsal this arm has THREE outcomes, not two, and only two of them are about the host:
# rows (the boot emitted), an empty result (the table exists, so something has written to this
# source before, and THIS boot was dark), and CLUSTER_DOESNT_EXIST (nothing has EVER written to
# this source). The third reaches `_run_query` as a non-zero transport rc and is reported TRANSIENT
# — no verdict — which is the correct degradation: it is emphatically not a PASS, and it is not the
# false FAIL that would send the operator to re-dispatch another paid host. It does mean a fully
# dark first rehearsal burns its 16-minute poll before saying "no verdict" rather than "dark boot".
# Accepted rather than special-cased: distinguishing the two costs a vendor-error-string match, and
# a string match on a vendor 500 is exactly the kind of guard that rots silently.
export BS_TABLE="${BS_TABLE:-t520508_soleur_git_data_prd_logs}"

_run_query() {  # $1 = sql ; prints rows, returns the transport's rc
  bash "$QUERY" "$1" 2>&1
}

# ── ARTIFACT 1: the source-liveness anchor ────────────────────────────────────────
anchor_out="$(_run_query "$ANCHOR_SQL")"; anchor_rc=$?
if [[ "$anchor_rc" -ne 0 ]]; then
  transient "TRANSIENT: the Better Stack query transport exited ${anchor_rc} (unreachable or unauthorised). No verdict — this says nothing about the rehearsal host." \
            "$(printf '%s\n' "$anchor_out" | tail -5)"
fi
# DELIBERATELY EXCLUDES THIS HOST'S OWN ROWS (see the SQL). If the anchor could be satisfied
# by the rehearsal host, then "this host emitted nothing" would make the anchor dead too — and
# the two states the anchor exists to separate would collapse into one.
# HERESTRING, NOT A PIPE. Under `set -o pipefail`, `producer | grep -q PAT` returns
# NON-ZERO on a successful EARLY match once the body exceeds the 64 KiB pipe buffer: grep
# closes the pipe on first match, the producer takes SIGPIPE (141), and pipefail propagates
# it — so the match reads as a miss (#6649). A herestring has no pipe and no producer to
# kill. The bodies here are usually small, which is exactly what makes this the kind of bug
# that ships and then surfaces on the one run with a verbose `detail` field.
# ANCHORED ON THE FIELD, not the bare word. `_run_query` merges stderr, so any transport
# chatter containing the substring `host` (a hostname in a curl error, for one) satisfied a
# bare `grep -q 'host'` and reported the source LIVE. The rows are FORMAT JSONEachRow with the
# column aliased `host`, so the field shape is available and strictly tighter — and this is
# the one predicate the whole live-vs-silent distinction rests on.
#
# (#7772) THE FOREIGN-HOST ANCHOR DIED WITH THE SOURCE SPLIT, AND THE FALLBACK IS AN INGEST PROBE.
#
# This predicate asks "is the source answering AT ALL?" by requiring a row from some host OTHER
# than the rehearsal host. That worked only because source 2457081 was SHARED and its other
# tenants were chatty (measured 2026-09-03: soleur-web-platform ~1.99M rows, soleur-inngest-prd
# ~150k). git-data now ships to its OWN source 2734275, whose only possible writers are the prod
# host (never born) and rehearsal hosts -- which this predicate excludes BY DESIGN, and whose
# HOST_NAME embeds a per-run id so no two rehearsals share one.
#
# So on a single-tenant source the anchor is UNSATISFIABLE: a PERFECT first rehearsal creates the
# table, writes its rows, is excluded by the `!=` clause, reports ZERO foreign rows, and lands on
# TRANSIENT -- no evidence file, no verdict, and RUNG2_BOOT_REHEARSAL=PASS structurally
# unreachable. Each attempt costs a real Hetzner host and an environment approval. The failure is
# indistinguishable from a dark boot, which is the one distinction this whole arm exists to make.
#
# The question is unchanged; the instrument has to change. `betterstack-ingest-probe.sh` answers
# "is this source live?" directly at the WRITE endpoint, without writing a row (an empty batch),
# and discriminates 0 accepting / 4 refused (auth or quota) / 2 unreachable. That is strictly
# better than the foreign-host SELECT even on a shared source: it measures THIS source's
# liveness rather than inferring it from a neighbour's traffic.
#
# The foreign-host read is kept as a SUFFICIENT condition, not a necessary one -- if another host
# has written recently the source is obviously live, and that costs nothing to accept.
if ! grep -qE '"host":"[^"]+"' <<<"$anchor_out"; then
  _probe="${BETTERSTACK_INGEST_PROBE:-${REPO_ROOT}/scripts/betterstack-ingest-probe.sh}"
  if [[ ! -r "$_probe" ]]; then
    transient "TRANSIENT: no foreign-host rows, and the ingest probe is unreadable at ${_probe}," \
              "so this run cannot tell a live-but-silent source from a dead one. Not a verdict" \
              "about ${HOST_NAME}."
  fi
  _probe_rc=0
  BETTERSTACK_INGEST_URL="${GIT_DATA_BETTERSTACK_INGEST_URL:-https://s2734275.eu-central-1a.betterstackdata.com/}" \
  BETTERSTACK_LOGS_TOKEN="${GIT_DATA_BETTERSTACK_LOGS_TOKEN:-${BETTERSTACK_LOGS_TOKEN:-}}" \
    bash "$_probe" >/dev/null 2>&1 || _probe_rc=$?
  case "$_probe_rc" in
    0)
      # Source live, this host silent. That IS a statement about the host, so fall through to the
      # host read below and let it produce the verdict.
      printf 'anchor: no foreign-host rows; ingest probe says the source is ACCEPTING (single-tenant source, expected)\n' >&2
      ;;
    4)
      transient "TRANSIENT: no foreign-host rows, and the ingest probe reports the source REFUSING" \
                "writes (auth or quota). A refused sink cannot have recorded this boot, so silence" \
                "here is a statement about the INSTRUMENT, not about ${HOST_NAME}."
      ;;
    *)
      transient "TRANSIENT: no foreign-host rows, and the ingest probe could not reach the source" \
                "(rc=${_probe_rc}). A live source with a silent host and an unreachable source look" \
                "identical from this host's rows alone, so this run declines to read silence as a" \
                "dark boot."
      ;;
  esac
fi

# ── ARTIFACT 2: everything this host reported ─────────────────────────────────────
host_out="$(_run_query "$HOST_SQL")"; host_rc=$?
if [[ "$host_rc" -ne 0 ]]; then
  transient "TRANSIENT: the host-rows query exited ${host_rc} after the anchor succeeded. No verdict." \
            "$(printf '%s\n' "$host_out" | tail -5)"
fi

# ── ARTIFACT 2b: every FATAL this host reported, unbounded by row chatter ─────────
# Separate query, deliberately. See FATAL_SQL. A transport failure here is TRANSIENT for the
# same reason it is on the other two: an unanswered fatal query cannot be read as "no fatal",
# and reading it that way is precisely the silence-is-health defect this route exists to end.
fatal_out="$(_run_query "$FATAL_SQL")"; fatal_rc=$?
if [[ "$fatal_rc" -ne 0 ]]; then
  transient "TRANSIENT: the unbounded fatal query exited ${fatal_rc} after the anchor succeeded. No verdict —" \
            "an unanswered fatal query is NOT a clean bill." \
            "$(printf '%s\n' "$fatal_out" | tail -5)"
fi

# ── ARTIFACT 3: the FAIL arms ─────────────────────────────────────────────────────
#
# (#7025, R5) `level=fatal` IS THE REAL FAIL ARM, and the inherited `\bno\b` match is the
# second one rather than the first. git-data-bootstrap.sh emits boot_complete's four booleans
# as HARDCODED LITERALS — its own comment reads "The booleans are all `yes` by construction
# here; they are emitted because the CONSUMER asserts on them" — so a dark boot produces NO
# boot_complete at all and the `\bno\b` arm cannot fire against real telemetry. What a dark
# boot produces is a fatal at luks_open, bootstrap, doppler_run or sshd_config.
#
# The `\bno\b` arm is retained anyway: it costs nothing and it is exactly the arm that fires
# if those literals are ever replaced by real measurements.
# READS `fatal_out`, NOT `host_out` (#7460 §5.0). Grepping the windowed row set here is what
# made a chatty boot able to bury its own fatal; the predicate is kept identical so a mutation
# that points it back at `host_out` is a one-token, clearly-visible revert.
if grep -q '"level":"fatal"' <<<"$fatal_out"; then
  echo "FAIL: ${HOST_NAME} reported a FATAL. The rehearsal found the failure class this route exists to catch — a boot that would have looked green from the apply."
  grep '"level":"fatal"' <<<"$fatal_out" | head -10
  echo
  echo "NO EVIDENCE FILE WRITTEN. Fix the cause, then re-run the rehearsal against the corrected template."
  exit 1
fi

if ! grep -q 'boot_complete' <<<"$host_out"; then
  # THE EYEBALL INSTRUCTION IS GONE, NOT MOVED. This branch used to end by telling the reader
  # to go and inspect Sentry for this host_name before concluding anything — an instruction to
  # a human to go and look, which
  # hr-no-dashboard-eyeball-pull-data-yourself forbids and which nobody could act on from a
  # 7-day artifact anyway. transient() performs that consult itself and prints what it found.
  transient "TRANSIENT: the source is live (the anchor answered) but ${HOST_NAME} has not reported" \
            "stage:boot_complete within ${WINDOW}, and reported no fatal either. Either the boot is" \
            "still in progress, or it died before reaching a stage that can emit to Better Stack at" \
            "all. Since #7460 only \`stage:bootcmd_start\` is Sentry-only by construction; the other" \
            "eight stages post to Better Stack from a baked token, so silence here means the host" \
            "died before runcmd, the baked token did not load, or the ingest POST failed — check" \
            "Sentry for \`stage:betterstack_ingest\`, which reports exactly that."
fi

_bc_rows="$(grep 'boot_complete' <<<"$host_out" || true)"
if grep -qE '"(luks_mounted|repo_root|hooks_path|provision)":"no"' <<<"$_bc_rows"; then
  echo "FAIL: ${HOST_NAME} reported boot_complete with a FALSE assertion — it reached its final stage with an invariant unmet, which is the dark boot the interlock exists to catch."
  printf '%s\n' "$_bc_rows" | head -5
  echo
  echo "NO EVIDENCE FILE WRITTEN."
  exit 1
fi

# ── THE PASS PATH CONSULTS SENTRY TOO (#7481 §4.5b) ────────────────────────────────
#
# THE GAP THIS CLOSES IS THE WORST ONE IN THE ROUTE, and it is not a TRANSIENT-path gap.
# Every no-verdict branch above funnels through transient(), which consults Sentry. This
# branch does not reach transient() at all: Better Stack said boot_complete with no fatal and
# no false assertion, so without a cross-check the route WRITES gate-releasing evidence.
#
# A host can satisfy that and still have emitted a fatal. Everything before `doppler run`
# reaches Sentry ONLY, so a host that died at an early stage, was retried by cloud-init, and
# later reached boot_complete produces exactly this shape: a clean Better Stack record and a
# fatal only Sentry holds. The artifact would read RUNG2_BOOT_REHEARSAL=PASS — the file whose
# presence releases the binding mechanical hold on the birth of the host that will store every
# connected user's source code.
#
# PRECEDENCE IS EXPLICIT: a fatal on EITHER channel beats a clean read on the other. An
# UNAVAILABLE second channel does NOT block the PASS — it is reported and the Better Stack
# verdict stands, because refusing to pass on an unreadable second channel would make a Sentry
# scope problem cost a paid host for no safety gain. That asymmetry is deliberate and is the
# one place this route prefers the weaker guarantee; it is stated rather than left implicit.
echo "Cross-checking the second channel before writing evidence (a fatal on either channel beats a clean read on the other):"
_sentry_consult
if [[ "$_SENTRY_VERDICT" == "FATAL" ]]; then
  echo
  echo "FAIL (Sentry-derived, on an otherwise-PASSing Better Stack read): ${HOST_NAME} reached"
  echo "stage:boot_complete with no Better Stack fatal, but Sentry holds a level:fatal for this"
  echo "host in the same window. Since #7460 the early stages DO reach Better Stack, so a Sentry"
  echo "fatal with no Better Stack fatal means one of: the bootcmd beacon (Sentry-only by"
  echo "construction), a baked token that did not load, or an ingest POST that failed — the last"
  echo "two are themselves reported at \`stage:betterstack_ingest\`."
  echo
  echo "NO EVIDENCE FILE WRITTEN — deliberately. Writing PASS here would release the git-data"
  echo "birth hold on a boot that failed."
  echo "**Next:** fix the cause named above, then re-run the rehearsal."
  exit 1
fi

# ── PASS ──────────────────────────────────────────────────────────────────────────
#
# The hash comes from the SHARED helper, never hand-rolled here. That is the whole reason the
# helper was extracted: a second derivation agreeing with the gate's would be a property
# maintained by two people remembering to edit two files, and it has to hold across a file
# this script writes and the gate later reads.
# shellcheck source=/dev/null
source "$GATE_LIB"
# THE EXIT CODE STAYS 2; THE LABEL DOES NOT. The 0/1/2 verdict contract is consumed by the
# rehearsal workflow and no consumer greps this literal, so re-labelling is safe — and it is
# necessary, because a derivation fault is the one rc=2 arm that is NOT transient. It is a
# deterministic repo-side condition: the module's payload set or its render inputs are
# unresolvable, and the identical failure reproduces on every attempt. Calling it TRANSIENT
# told the reader to wait, and the workflow duly re-ran it ~20 times over ~10 minutes of a
# paid host before reporting "do not simply re-dispatch" (#7485).
#
# That retry loop is the workflow's, not this script's, and changing a paid-host dispatch's
# retry semantics is scoped out here (§Non-Goals) — so the honest move is to stop the message
# implying the wait is worth anything.
#
# REACHES THE STEP LOG AND THE capture-log ARTIFACT, NOT $GITHUB_STEP_SUMMARY: that workflow
# hardcodes its own rc=2 summary text, which this change does not edit.
if ! TEMPLATE_SHA="$(git_data_rung2_user_data_sha256 "$CLOUD_INIT")"; then
  echo "DERIVATION FAULT (deterministic, NOT transient): could not derive the user_data hash from ${CLOUD_INIT}, so there is nothing to bind evidence to. The render inputs or the module's payload set are unresolvable in THIS TREE — re-dispatching reproduces it identically, so do not wait for it to clear. The fail-closed diagnostic below names the offending file."
  printf '%s\n' "$TEMPLATE_SHA"
  exit 2
fi

# THE DIVERGENCE SET IS DECLARED BY THE CALLER, not echoed from the allowlist.
#
# This previously read `DIVERGENCE="${GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST// /,}"` — it wrote
# the gate's own allowlist back out, unconditionally, so the gate then checked
# allowlist ⊆ allowlist and R6 could only ever refuse a HAND-edited file. Caught in review.
# This script cannot know what diverged: it reads Better Stack, not terraform state.
#
# So the dispatcher declares it and this script refuses to invent one. `none` is the
# explicit no-divergence declaration; the gate refuses an absent or duplicated key.
if [[ -z "$DIVERGENCE" ]]; then
  echo "refusing: --divergence is required. It records which templatefile ARGUMENTS the rehearsal diverged from production on — the axis the evidence hash does NOT bind. Pass the identity-shaped set the rehearsal root actually diverges on, or 'none'. This script reads Better Stack, not terraform state, so it cannot derive it; echoing the gate's own allowlist back (which it used to do) makes the check allowlist-subset-of-allowlist and refuses nothing." >&2
  exit 64
fi

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  echo "PASS (--verify-only): ${HOST_NAME} reported stage:boot_complete with all four assertions positive, and no fatal. NO evidence file written."
  exit 0
fi

# Written with the QUERIES THAT PRODUCED IT. An evidence file asserting a result without the
# question behind it is unreproducible: the next reader cannot distinguish a real observation
# from a typo in a WHERE clause, and this file's whole job is to be checkable by someone who
# was not here.
{
  printf '# rung-2 boot rehearsal evidence — generated by scripts/followthroughs/git-data-rung2-evidence-capture.sh (#7025)\n'
  printf '#\n'
  printf '# READ THIS BEFORE MERGING IT. Merging this file RELEASES git_data_rung2_rehearsal_gate,\n'
  printf '# which is the binding mechanical hold on the birth of the host that stores every\n'
  printf '# connected user'"'"'s source code. It is deliberately NOT auto-committed by any workflow:\n'
  printf '# a route that writes its own gate-releasing evidence is self-approving.\n'
  printf '#\n'
  printf '# Rehearsal host : %s\n' "$HOST_NAME"
  printf '# Captured (UTC) : %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '#\n'
  printf '# WHAT THE HASH BINDS: the cloud-init template plus every file()-bound payload in\n'
  printf '# modules/git-data-userdata/main.tf. It does NOT bind the templatefile ARGUMENTS, so\n'
  printf '# the divergence set below is the declared, machine-checked scope of what differed\n'
  printf '# between this rehearsal and production. git_data_rung2_rehearsal_gate refuses any\n'
  printf '# entry outside its identity-only allowlist.\n'
  printf '#\n'
  printf '# ARTIFACT 1 — source-liveness anchor. Excludes this host BY DESIGN: an anchor a\n'
  printf '# silent host could satisfy would collapse "dark boot" and "broken instrument".\n'
  printf '# QUERY:%s\n' "$(printf '%s' "$ANCHOR_SQL" | tr '\n' ' ' | tr -s ' ')"
  printf '#\n'
  printf '# ARTIFACT 2 — every stage this host reported, and ARTIFACT 3 — the fatal/false-assertion\n'
  printf '# arms, both read from this one result set.\n'
  printf '# QUERY:%s\n' "$(printf '%s' "$HOST_SQL" | tr '\n' ' ' | tr -s ' ')"
  # The fatal arm is a SEPARATE query, so the evidence records both or it under-states what
  # was actually asked. An auditor reading only the windowed query would conclude the verdict
  # was window-bounded, which since #7460 it is not.
  printf '# QUERY_FATAL:%s\n' "$(printf '%s' "$FATAL_SQL" | tr '\n' ' ' | tr -s ' ')"
  printf '#\n'
  # THE SECOND CHANNEL'S VERDICT IS PART OF THE EVIDENCE, not just of the log.
  #
  # Without this line a PASS cross-checked CLEAN and a PASS whose cross-check was SKIPPED or
  # UNAVAILABLE are BYTE-IDENTICAL in the file that releases the birth hold — which is the
  # defect class this whole route exists to remove, one level up. It is worse than it sounds:
  # the capture-log artifact is uploaded only when `capture_rc != '0'`, so on a PASS the
  # `second channel:` line is discarded exactly where it is the sole record that the
  # cross-check ran at all. The human at the second gate merges THIS file, so the verdict
  # has to survive into it.
  #
  # Recorded, not enforced: an UNAVAILABLE second channel still passes (see the precedence
  # note above). This puts the degrade in front of the reviewer who is the actual control.
  printf '# ARTIFACT 4 — the Sentry cross-check, run before this file was written.\n'
  printf '# CLEAN = a fatal read returned zero rows AND the liveness anchor confirmed the\n'
  printf '# source is answering. UNAVAILABLE = the read did not happen or could not be\n'
  printf '# trusted; the PASS below rests on Better Stack alone.\n'
  printf '# QUERY: sentry-issue.sh --host-events %s %s\n' "$HOST_NAME" "$(_sentry_window_args | tr '\n' ' ')"
  printf 'RUNG2_SENTRY_CROSSCHECK=%s\n' "${_SENTRY_VERDICT:-NOT_RUN}"
  printf 'RUNG2_BOOT_REHEARSAL=PASS\n'
  printf 'RUNG2_EVIDENCE_URL=%s\n' "$EVIDENCE_URL"
  printf 'RUNG2_TEMPLATE_SHA256=%s\n' "$TEMPLATE_SHA"
  printf 'RUNG2_VAR_DIVERGENCE=%s\n' "$DIVERGENCE"
} > "$OUT"

# WORDED TO WHAT WAS ACTUALLY CHECKED. This said "with all four assertions positive",
# which overstates it: git-data-bootstrap.sh emits those four booleans as HARDCODED
# literals, so the `"…":"no"` arm can never fire against real telemetry. The real
# predicate is the one below. The overstatement mattered because it landed in the file a
# human reads at the second of the two intentional gates — the compensating control.
echo "PASS: ${HOST_NAME} reported stage:boot_complete and no level:fatal (Better Stack), with the Sentry cross-check reporting ${_SENTRY_VERDICT:-NOT_RUN}. NOTE: boot_complete's four booleans are hardcoded literals in git-data-bootstrap.sh, so this attests that the final stage was REACHED and that nothing reported a fatal — not that four invariants were independently measured."
echo "Evidence written to ${OUT} (user_data sha256 ${TEMPLATE_SHA})."
echo
echo "This file is NOT committed by this script and must NOT be committed by a workflow."
echo "Merging it is the second of the two intentional human gates on the git-data birth."
exit 0
