#!/usr/bin/env bash
# #7761 — the seam-gate + injection-bound reached the dedicated inngest host, and the host rests in
# its POST-CUTOVER steady state (`done`, re-earned by the FSM on THIS machine) afterwards.
#
# TRACKER: **#7761**. It stays OPEN until this reads PASS; scripts/sweep-followthroughs.sh closes
# it on exit 0 and lists `--state open`, so a PR changing this probe carries `Ref #7761`, never a
# closing keyword.
# RUN IT: doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh
# RETIREMENT: when #7761 closes, delete this probe, its .test.sh, the `.after` sidecar, the #7761
# PROBE PARITY block in apps/web-platform/infra/cutover-inngest-workflow.test.sh, and this path's
# entry in .github/workflows/infra-validation.yml `pull_request.paths`.
#
# WHY A COMMITTED PROBE. Delivery is tag -> image build -> digest bump -> HOST REPLACE of the
# fleet's sole scheduler (the digest is ForceNew in user_data; ADR-100 addendum 2026-08-25 /
# #7674). A production destroy-and-recreate whose verification cannot be re-run is unauditable.
#
# THE ANSWER KEY (rewritten 2026-09-24, after the cutover completed). INLINE, never env-supplied:
# this authorizes closing a P1 security issue, and an environment-supplied answer key is the very
# class of untrusted input #7761 is about. cutover-inngest.yml op=resume wrote `flushed` and the host
# FSM's `flushed)` arm completed it to `done` on 2026-09-23; the flush latch on /mnt/data is
# monotonic and G3.7 refuses op=arm once a FLUSHALL is on record, so `done` is the ONLY passable
# state — and only when the FSM re-earned it here:
#   P1 delivery    every post-boundary noop-done row carries guard=7761 (only the post-#7761 script
#                  stamps it), and they all come from ONE machine M.
#   P2 liveness    >= 2 DISTINCT stamped noop-done heartbeats on M after its op=resume row, the
#                  newest within the last HEARTBEAT_MAX_AGE_S (the 30s timer is cycling NOW).
#   P3 no refusal  zero SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED rows under the tag since the boundary.
#   P4 provenance  M has a post-boundary, guard-stamped `flushed-resume-no-reflush` row. A replaced
#                  host emits noop-done under an INHERITED done until op=resume runs; that never counts.
#   P5 no drift    since the boundary, no flip-FSM row other than that resume shape.
# Ownership binds to journald `_MACHINE_ID`, not the hostname: the done-owner marker lives on the
# root disk (a replace destroys it) while the hostname survives a replace. A PASS is only as
# trustworthy as the log source's shared ingest token — anyone holding it can write any field.
#
# DRIFT IS A POSITIVE OBSERVATION, NOT THE PRESENCE OF A FLAG. emit_state writes the POST-run flag,
# so a transition into flipping/flushed exists in the warehouse only as its outcome REASON. ONE
# sparse OR-query over the whole since-boundary interval (by warehouse `dt`) — DRIFT_GREPS: every
# emitter reason except the noop-done heartbeat, plus flag:flipping/flushed as defence in depth —
# returns only the resume row on a healthy host (measured 2026-09-24: exactly 1 row). A resting
# rolled-back/aborted after the cutover is a dark scheduler, so it is drift, not a pass. A reason
# the emitter gains and DRIFT_GREPS lacks is invisible here: the #7761 parity block in
# apps/web-platform/infra/cutover-inngest-workflow.test.sh is the guard for that, not the runtime.
#
# THE WAREHOUSE SHAPE. The flip FSM's `message` is a parsed JSON OBJECT inside `raw` (2,743 of 2,743
# rows in a 30h sample, 2026-09-24), and DRIFT_GREPS' quoted terms match only that shape: in a
# STRING-shaped message the quotes are escaped and nothing matches. So mine() marks a row decoded
# from a string (or a `{`-string that no longer parses — logger truncates at 1 KiB), and any such
# flip row in LIVE refuses the PASS (`message_shape_unsupported`): the drift half would be blind.
#
# THE BOUNDARY. FLIP_ROLLOUT_AFTER, else the committed `.after` sidecar (a regular one-line file;
# the sweeper runs probes under `env -i`, so the sidecar is its only channel), else DERIVED from
# telemetry. A SUPPLIED boundary may yield PASS/FAIL/TRANSIENT; a DERIVED one PASS/TRANSIENT only
# (#7695, verdict_fail()) — and in practice never PASS, because the owning machine's flip rows
# always predate the first hourly probe row the derivation reads. Machine M must emit NO flip row
# at or before the boundary (queried by its _MACHINE_ID over 30 days), so moving the sidecar can
# re-certify only a NEW machine; it cannot erase drift on the current one.
#
# VERDICT TABLE (reason= : meaning -> action). Exit 0 = PASS, 1 = FAIL, 2 = TRANSIENT (the sweeper's
# NOT YET), 3 = CANNOT ESTABLISH (a config error, or a read-path failure against a supplied boundary
# more than 7 days old). Every remediation is an Actions dispatch, a sidecar edit, or a Better Stack
# read (scripts/betterstack-query.sh --since <boundary> --grep inngest-cutover-flip); none needs SSH.
#   flush_path_transition_after_replace  : a flush-path row since the boundary -> Redis suspect; do not re-dispatch
#   drift_after_replace                  : any other FSM row since the boundary -> read the rows; human review
#   stale_image                          : a post-boundary heartbeat lacks guard=7761 -> the replace kept the old
#                                          image; compare the cloud-init-inngest.yml digest pins with the build
#   multiple_machines_since_boundary     : >1 _MACHINE_ID emitted since the boundary -> the host was replaced
#                                          after it: move the sidecar to that replace's completion time (exit 3)
#   done_not_resumed                     : done not re-earned on this machine yet -> `gh workflow run
#                                          cutover-inngest.yml -f op=resume` (waits for inngest-cutover approval)
#   done_not_resumed_past_deadline       : the same, past the deadline under a supplied boundary -> as above
#   insufficient_post_replace_markers    : < 2 heartbeats after the resume -> re-run shortly
#   insufficient_post_replace_markers_past_deadline : the same, long after the resume -> the timer is not cycling
#   heartbeat_stale                      : M's newest heartbeat is older than HEARTBEAT_MAX_AGE_S -> the timer stopped
#   channel_dark                         : no flip-tag rows from this host -> re-run; the host may be booting
#   channel_dark_past_deadline           : the same past the deadline -> the unit is not running (read its tag rows)
#   cutover_armed                        : an `armed` row (uncapped) -> establish who armed it
#   seam_refused                         : a seam refusal on the live host -> rename the colliding Doppler secret
#   doppler_flag_not_done                : Doppler's INNGEST_CUTOVER_FLIP is not `done` -> explain before any apply
#   boundary_inside_owning_machine_lifetime : M emitted before the boundary -> restore the sidecar to the replace
#                                          that created M; drift on M needs human review, not a sidecar edit (exit 3)
#   message_shape_unsupported            : string-shaped flip rows -> the drift query cannot see them (exit 3)
#   machine_id_absent                    : heartbeats carry no _MACHINE_ID -> the shipper changed (exit 3)
#   drift_query_truncated / refusals_query_truncated / boundary_check_truncated : a full page with no finding
#   drift_query_failed / refusals_query_failed / query_failed / row_decode_failed : read path -> re-run
#   boundary_check_query_failed          : read path of the boundary check -> re-run
#     (the read-path and truncation rows above exit 2, and 3 once a supplied boundary is > 7 days old)
#   drift_limit_invalid / limit_invalid  : a malformed FLIP_ROLLOUT_* numeric seam -> unset it (exit 3)
#   sidecar_is_symlink / sidecar_oversize : the `.after` sidecar is not a one-line regular file (exit 3)
#   boundary_unparseable                 : the boundary is not a real ISO-8601 UTC instant (exit 3)
#   credentials_unprovisioned / jq_unavailable : the environment cannot read -> BETTERSTACK_QUERY_* from
#                                          Doppler soleur/prd_terraform; install jq
#   derived_boundary_stale_supply_authoritative_boundary : a derived boundary cannot FAIL -> commit one
#   pin_unreadable / probe_channel_dark / boundary_underivable : the derivation had nothing to read
#   (exit 78: refused to run under xtrace with a live credential set — #7797)
set -uo pipefail

# #7797: this probe binds BETTERSTACK_QUERY_PASSWORD, and `-x` would print it. Refuse to run
# traced while the credential is actually set — the conditional form, because tracing a run with
# no credential provisioned is a legitimate way to debug the TRANSIENT arm.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="${FLIP_ROLLOUT_QUERY_BIN:-$REPO_ROOT/scripts/betterstack-query.sh}"
# The committed boundary: 2026-09-23T19:36:32Z = apply run 35910239344, job inngest_host_replace,
# completedAt (the old machine's last row 19:35:23Z, the new machine's first start_ts 19:37:57Z,
# its op=resume 19:42:45Z). LIFECYCLE: it belongs to #7761 and retires with this probe. If the host
# is replaced while #7761 is still open, the sidecar must MOVE to that replace's completion time.
AFTER_FILE="${FLIP_ROLLOUT_AFTER_FILE:-$REPO_ROOT/scripts/followthroughs/inngest-cutover-flip-rollout-7761.after}"
# Seamed like QUERY so the Doppler arm is drivable by the suite.
DOPPLER_BIN="${FLIP_ROLLOUT_DOPPLER_BIN:-doppler}"

# The syslog TAG, not a marker substring: emit_state rows are bare JSON whose identity lives in the
# tag, and SYSLOG_IDENTIFIER is present in `raw`.
TAG="${FLIP_ROLLOUT_TAG:-inngest-cutover-flip}"
REFUSAL_MARKER="SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED"
# Two identity fields, both required (#6616 — `host_name` telemetry has been observed lying).
FLIP_HOST="${FLIP_ROLLOUT_HOST:-soleur-inngest}"
FLIP_HOST_NAME="${FLIP_ROLLOUT_HOST_NAME:-soleur-inngest-prd}"
# LIVE is deliberately NARROW (~274 rows/h under the tag): it only has to hold the newest
# heartbeats. Everything that must span the whole since-boundary interval is its own sparse query.
WINDOW="${FLIP_ROLLOUT_WINDOW:-2h}"
LIMIT="${FLIP_ROLLOUT_LIMIT:-500}"
# The drift page. Healthy = 1 row; 5000 leaves ~1.7 days of headroom even under a 2,880-row/day
# flood, and past that a finding is already a FAIL. A test seam, not an answer-key member: shrinking
# it can only yield TRANSIENT, growing it only makes the page more complete.
DRIFT_LIMIT="${FLIP_ROLLOUT_DRIFT_LIMIT:-5000}"
BOUNDARY_CHECK_LIMIT=5000
DOPPLER_PROJECT_NAME="${FLIP_ROLLOUT_DOPPLER_PROJECT:-soleur-inngest}"
DOPPLER_CONFIG_NAME="${FLIP_ROLLOUT_DOPPLER_CONFIG:-prd}"
# How long after the boundary a silent host stops being "not yet" and becomes a failure. A test
# seam: it can move FAIL<->TRANSIENT, never manufacture a PASS.
STALE_AFTER_S="${FLIP_ROLLOUT_STALE_AFTER_S:-3600}"
# The newest heartbeat on the owning machine must be at most this old (30s cadence; generous slack).
HEARTBEAT_MAX_AGE_S=600
# A read-path non-verdict against a supplied boundary older than this is CANNOT ESTABLISH (exit 3),
# not NOT YET forever.
NON_VERDICT_MAX_AGE_S=604800

# --- THE ANSWER KEY (inline; see the header) --------------------------------------------------
POST_CUTOVER_FLAG="done"
DONE_ENTRY_REASON="flushed-resume-no-reflush"
EXPECTED_GUARD="7761"
MIN_MARKERS=2
FLUSH_PATH_REASONS='["flip-complete","flushall-failed","dbsize-nonzero"]'
FLUSH_PATH_FLAGS='["flipping","flushed"]'
# Quoted terms (`'"reason":"<r>'`) match because `message` is an object inside raw. No term carries
# `_`, which ClickHouse LIKE reads as a wildcard. One term per line: the parity loop reads this block.
DRIFT_GREPS=(
  '"reason":"dbsize-nonzero'
  '"reason":"flip-complete'
  '"reason":"flushall-failed'
  '"reason":"flushed-resume-no-reflush'
  '"reason":"latch-unrecordable'
  '"reason":"refuse-rearm-after-done'
  '"reason":"rolled-back'
  '"reason":"unexpected-exit'
  '"reason":"verify-health'
  '"reason":"verify-owner-unrecordable'
  '"reason":"verify-registry-empty'
  '"reason":"verify-registry-unreadable'
  '"reason":"verify-unknown'
  '"reason":"noop-unset'
  '"reason":"noop-rolled-back'
  '"reason":"noop-aborted'
  '"flag":"flipping"'
  '"flag":"flushed"'
)
# Every reason literal the emitter can write, for DISPLAY only: a finding prints its reason only
# when it is one of these (noop-unset / unexpected-exit(from=…) embed the raw flag value, and this
# output lands in a PUBLIC issue comment that the runner's secret masker never sees).
KNOWN_REASONS='["dbsize-nonzero","flip-complete","flushall-failed","flushed-resume-no-reflush",
  "latch-unrecordable","refuse-rearm-after-done","rolled-back","verify-health",
  "verify-owner-unrecordable","verify-registry-empty","verify-registry-unreadable","verify-unknown",
  "noop-done","noop-unset","noop-rolled-back","noop-aborted"]'

# --- the boundary -----------------------------------------------------------------------------
AFTER="${FLIP_ROLLOUT_AFTER:-}"
# #7695 4.0 — PROVENANCE. A SUPPLIED boundary is an assertion by a human or an apply that the
# replace happened at T, so silence after T really is a bricked scheduler and the FAIL arms below
# apply verbatim. A DERIVED boundary is an INFERENCE and is capped at PASS-or-TRANSIENT by
# verdict_fail(). The two rules govern disjoint provenances; neither overrides the other.
BOUNDARY_PROVENANCE=supplied
if [[ -z "$AFTER" ]]; then
  # The sidecar's contents reach a PUBLIC issue comment through every message below, so it is read
  # as a one-line regular file or not at all: a symlink to /proc/self/environ would otherwise
  # publish BETTERSTACK_QUERY_PASSWORD through boundary_unparseable.
  if [[ -L "$AFTER_FILE" ]]; then
    echo "CANNOT_ESTABLISH: reason=sidecar_is_symlink — ${AFTER_FILE##*/} is a symlink; it must be a regular" >&2
    echo "           one-line file holding the replace time. Its target was not read." >&2
    exit 3
  fi
  if [[ -f "$AFTER_FILE" && -r "$AFTER_FILE" ]]; then
    _sidecar="$(head -c 65 "$AFTER_FILE" 2>/dev/null || true)"
    if [[ "${#_sidecar}" -gt 64 ]]; then
      echo "CANNOT_ESTABLISH: reason=sidecar_oversize — ${AFTER_FILE##*/} holds more than 64 bytes; it must be" >&2
      echo "           exactly one ISO-8601 UTC timestamp. Its contents were not printed." >&2
      exit 3
    fi
    AFTER="$(printf '%s' "$_sidecar" | tr -d '[:space:]')"
  fi
fi
if [[ -z "$AFTER" ]]; then
  # #7695 4.1 — DO NOT exit here: the derivation runs after the credential/jq preflights below.
  BOUNDARY_PROVENANCE=derived
fi
if [[ "$BOUNDARY_PROVENANCE" == "supplied" ]] && ! [[ "$AFTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  # The LENGTH only, never the value (see the sidecar note above).
  echo "CANNOT_ESTABLISH: reason=boundary_unparseable length=${#AFTER} — expected ISO-8601 UTC" >&2
  echo "           (YYYY-MM-DDTHH:MM:SSZ). A boundary that cannot be parsed must not be" >&2
  echo "           silently widened to 'any time', which would let pre-replace markers pass." >&2
  exit 3
fi

# --- the flag, CORROBORATED from Doppler when a credential happens to be present ---------------
# Not a hard requirement: the sweeper provisions no Doppler token, so in CI this arm is inert and
# the flag is read from the rows themselves. When a credential IS present it fails fast: any value
# other than the post-cutover `done` — `rolled-back` and `aborted` included — blocks a PASS.
doppler_flag=""
if command -v "$DOPPLER_BIN" >/dev/null 2>&1; then
  # A FAILED read is no read: stdout from a failing doppler must never be taken as the flag.
  if _dout="$("$DOPPLER_BIN" secrets get INNGEST_CUTOVER_FLIP \
                -p "$DOPPLER_PROJECT_NAME" -c "$DOPPLER_CONFIG_NAME" --plain 2>/dev/null)"; then
    doppler_flag="$(printf '%s' "$_dout" | tr -d '[:space:]')"
  fi
fi
# #7695 P3: print the value only when it is a known FSM enum member. This string is echoed into a
# PUBLIC GitHub issue comment, which the runner's secret masker never sees.
_flag_for_display() {
  case "${1:-}" in
    rolled-back|rollback|aborted|armed|flipping|flushed|done|unset) printf '%s' "$1" ;;
    *) printf '<non-enum value, %s chars>' "${#1}" ;;
  esac
}
if [[ -n "$doppler_flag" && "$doppler_flag" != "$POST_CUTOVER_FLAG" ]]; then
  echo "FAIL: reason=doppler_flag_not_done — INNGEST_CUTOVER_FLIP in ${DOPPLER_PROJECT_NAME}/${DOPPLER_CONFIG_NAME} reads" >&2
  echo "      '$(_flag_for_display "$doppler_flag")', expected '${POST_CUTOVER_FLAG}'. The cutover completed, so the" >&2
  echo "      scheduler's steady state is done; any other value means a rollback, an abort, or an armed" >&2
  echo "      cutover. Do NOT re-dispatch the apply until this is explained — the armed path ends in FLUSHALL." >&2
  exit 1
fi

# --- credentials and tooling for the marker read ----------------------------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then
  echo "TRANSIENT: reason=credentials_unprovisioned — missing:${missing}." >&2
  echo "           The liveness half was never asked. That is NOT a PASS: a correct flag on a host" >&2
  echo "           that stopped polling is the twelve-day false-'done' shape ADR-100 records (#7228)." >&2
  exit 2
fi
# jq is load-bearing for every selector below. Unpreflighted, a missing jq empties the row set and
# the probe blames the HOST for a local tooling fault.
if ! command -v jq >/dev/null 2>&1; then
  echo "TRANSIENT: reason=jq_unavailable — the decode path is unusable, so nothing was measured." >&2
  exit 2
fi
# The limits interpolate into SQL and into bash arithmetic. A leading zero is refused: `08` is not
# a bash integer, so `-ge` would error and silently skip the page-full check.
if ! [[ "$DRIFT_LIMIT" =~ ^[1-9][0-9]{0,5}$ ]]; then
  echo "CANNOT_ESTABLISH: reason=drift_limit_invalid — FLIP_ROLLOUT_DRIFT_LIMIT must match ^[1-9][0-9]{0,5}\$." >&2
  exit 3
fi
if ! [[ "$LIMIT" =~ ^[1-9][0-9]{0,5}$ && "$STALE_AFTER_S" =~ ^[1-9][0-9]{0,6}$ ]]; then
  # STALE_AFTER_S reaches `[[ -gt ]]`, which evaluates its operands as arithmetic.
  echo "CANNOT_ESTABLISH: reason=limit_invalid — FLIP_ROLLOUT_LIMIT / FLIP_ROLLOUT_STALE_AFTER_S must be plain integers." >&2
  exit 3
fi

# mine <since> <limit> <tag|""> [--until <until>] <term>... — ONE query, OR over the terms, then
# decode and field-isolate on the DECODED row. Emits one compact line per row: an emit_state
# message becomes its JSON object plus `_mid` (journald _MACHINE_ID); any other message (a refusal
# marker, a Doppler stderr line) passes through as a JSON string. `tag` non-empty additionally
# requires SYSLOG_IDENTIFIER == tag — the LUKS cutover FSM on this SAME host emits the same noop-*
# reasons under its own tag.
#
# THE MESSAGE SHAPE. In the warehouse the flip FSM's `message` is a parsed JSON OBJECT inside raw
# (measured 2026-09-24: 2,743 of 2,743 rows). The pre-2026-09-24 `.message? // empty` under `jq -r`
# pretty-printed each object over several lines, the caller's `fromjson?` then failed on every
# one, and every live row was dropped. The legacy STRING shape is still decoded (`fromjson`), carries
# `_mid`, and is MARKED `_str` — a `{`-string that no longer parses becomes `_undecodable` — because
# the drift query's quoted terms cannot see that shape, so the caller refuses a PASS on it.
#
# THE PAGE-FULL SENTINEL. A trailing `__PAGE_FULL__` line when the RAW page (before the host
# filter, so foreign rows count) reached the limit: an absence conclusion drawn from a full
# newest-first page is invalid, because the oldest rows are the ones it dropped. Callers strip it
# before any emptiness check.
mine() {
  local since="$1" limit="$2" tag="$3"; shift 3
  local until_args=() grep_args=() t rows qrc n out jrc
  if [[ "${1:-}" == "--until" ]]; then until_args=(--until "$2"); shift 2; fi
  for t in "$@"; do grep_args+=(--grep "$t"); done
  rows="$("$QUERY" --since "$since" "${until_args[@]}" "${grep_args[@]}" --limit "$limit" 2>/dev/null)"; qrc=$?
  if [[ "$qrc" -ne 0 ]]; then printf '__QUERY_FAILED__%s' "$qrc"; return 0; fi
  n="$(grep -c . <<<"$rows" || true)"
  # `-R` plus `fromjson?` is load-bearing: without `-R`, ONE malformed line aborts the whole jq
  # invocation and every valid row after it is lost.
  out="$(printf '%s\n' "$rows" \
    | jq -R -c --arg h "$FLIP_HOST" --arg hn "$FLIP_HOST_NAME" --arg tag "$tag" '
        fromjson? | .raw? | fromjson?
        | select(type == "object")
        | select(.host == $h and .host_name == $hn)
        | select($tag == "" or .SYSLOG_IDENTIFIER == $tag)
        | (._MACHINE_ID // "") as $mid
        | .message
        | if type == "object" then . + {_mid: $mid}
          elif type == "string" then
            ((try fromjson catch null) as $d
             | if ($d | type) == "object" then $d + {_mid: $mid, _str: true}
               elif startswith("{") then {_mid: $mid, _undecodable: true}
               else . end)
          else empty end' 2>/dev/null)"; jrc=$?
  if [[ "$jrc" -ne 0 ]]; then printf '__DECODE_FAILED__%s' "$jrc"; return 0; fi
  [[ -n "$out" ]] && printf '%s\n' "$out"
  if [[ "${n:-0}" -ge "$limit" ]]; then printf '__PAGE_FULL__\n'; fi
  return 0
}
_strip_sentinel() { grep -vx '__PAGE_FULL__' <<<"$1" || true; }
_page_full() { grep -qx '__PAGE_FULL__' <<<"$1"; }

# Shared jq for decoding the stripped rows, and for DISPLAYING a row in a public comment.
JQ_LIB='
def iso: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
def rows: [inputs | fromjson? | select(type == "object")];
def flagdisp: if . == null or . == "" then "<empty>"
  elif type == "string" and (. as $f | ["rolled-back","aborted","armed","flipping","flushed","done","unset"] | index($f) != null) then .
  else "<non-enum value, \(tostring | length) chars>" end;
def reasondisp($known): if type != "string" then "<non-enum reason>"
  elif (. as $r | $known | index($r) != null) then .
  elif test("^unexpected-exit\\(from=.*\\)$") then "unexpected-exit(from=\(capture("^unexpected-exit\\(from=(?<x>.*)\\)$").x | flagdisp))"
  else "<non-enum reason, \(length) chars>" end;
def tsdisp: if iso or . == "unknown" then . else "<non-date, \(tostring | length) chars>" end;
def middisp: if type == "string" and test("^[0-9a-zA-Z]{8}") then .[0:8] else "<none>" end;
def line($known): "flag=\(.flag | flagdisp) reason=\(.reason | reasondisp($known)) at=\(.start_ts | tsdisp) mid=\(._mid | middisp)";
'

# --- #7695 4.0: the ONE place a boundary-dependent FAIL may be emitted ------------------------
#
# A DERIVED boundary may produce PASS or TRANSIENT and NEVER FAIL: an inferred boundary can
# misattribute a PRE-replace event as post-replace, and a re-pin to a digest some host already
# reported derives a boundary on the very machine the rollout replaced. Every BOUNDARY-DEPENDENT
# FAIL routes through here. Three arms deliberately do not, because none consults the boundary:
# the Doppler flag (its CURRENT value), `cutover_armed` (never a resting state), and `seam_refused`
# (the #7761 condition itself, occurring now).
#
# The FAIL line is printed FIRST and LAST: the sweeper keeps only the tail of the output, so a long
# evidence list would otherwise push the verdict out of the comment.
verdict_fail() {
  local reason="$1"; shift
  if [[ "${BOUNDARY_PROVENANCE:-supplied}" == "derived" ]]; then
    echo "TRANSIENT: reason=derived_boundary_stale_supply_authoritative_boundary" >&2
    echo "           would_be=${reason%% *} (the derived arm would have reported ${reason})" >&2
    echo "           The boundary was INFERRED from the earliest probe row carrying the pinned" >&2
    echo "           digest -- nobody asserted a replace time. An inference is not entitled to" >&2
    echo "           declare a regression, so this is capped at TRANSIENT. To re-arm the FAIL arm," >&2
    echo "           commit the replace's completion time (ISO-8601 UTC) to ${AFTER_FILE##*/}." >&2
    # Capping the VERDICT is the point; dropping the evidence is not.
    [[ "$#" -gt 0 ]] && printf '%s\n' "$@" >&2
    exit 2
  fi
  echo "FAIL: reason=${reason}" >&2
  if [[ "$#" -gt 0 ]]; then
    printf '%s\n' "$@" >&2
    echo "FAIL: reason=${reason}" >&2
  fi
  exit 1
}

# A read-path non-verdict: nothing was measured. Exit 2 (NOT YET) — but against a SUPPLIED boundary
# more than 7 days old, exit 3 (CANNOT ESTABLISH): a stuck read path is then something to fix, and
# rendering it NOT YET every day forever is the state this probe exists to end. A derived boundary
# keeps exit 2: an inferred boundary's age proves nothing.
non_verdict() {
  local reason="$1"; shift
  local code=2
  if [[ "$BOUNDARY_PROVENANCE" == "supplied" && "${boundary_age:-0}" -gt "$NON_VERDICT_MAX_AGE_S" ]]; then code=3; fi
  if [[ "$code" == "3" ]]; then echo "CANNOT_ESTABLISH: reason=${reason}" >&2; else echo "TRANSIENT: reason=${reason}" >&2; fi
  [[ "$#" -gt 0 ]] && printf '%s\n' "$@" >&2
  if [[ "$code" == "3" ]]; then
    echo "           The supplied boundary is ${boundary_age}s old (> ${NON_VERDICT_MAX_AGE_S}s)." >&2
    echo "           A read-path non-verdict this long after the boundary is not 'not yet': fix the read path." >&2
  fi
  exit "$code"
}

# --- #7695 4.1-4.6: derive the boundary when none was supplied --------------------------------
if [[ "$BOUNDARY_PROVENANCE" == "derived" ]]; then
  # 4.6: "first" is a SLICE. mine_dt()'s --limit returns the NEWEST N rows before re-sorting, so
  # past roughly DERIVE_LIMIT probe rows the earliest row FOUND is not the earliest that exists.
  # The residual is bounded in the safe direction: a slice can only push the derived boundary
  # LATER, which delays a PASS, and under verdict_fail()'s cap it can never manufacture a
  # condemnation.
  # #7695 P1/P2 — the host probe fires HOURLY, so the derivation needs a wide window: 24h, its own
  # default since 2026-09-24 (it used to inherit the retired drift window's).
  DERIVE_WINDOW="${FLIP_ROLLOUT_DERIVE_WINDOW:-24h}"
  DERIVE_LIMIT="${FLIP_ROLLOUT_DERIVE_LIMIT:-5000}"
  # betterstack-query.sh interpolates LIMIT into SQL uninterpolated. Shape-check it here rather
  # than extending that unvalidated-env-var class by one more member.
  case "$DERIVE_LIMIT" in ''|*[!0-9]*) DERIVE_LIMIT=5000 ;; esac
  PIN_FILE="${FLIP_ROLLOUT_PIN_FILE:-$REPO_ROOT/apps/web-platform/infra/cloud-init-inngest.yml}"
  # 4.2: match on the DIGEST ONLY. The live host reports the ZOT ref
  # (10.0.1.30:5000/jikig-ai/...@sha256:...) because cloud-init reassigns IREF="$ZIREF" on a
  # successful zot pull and writes THAT to /etc/default/soleur-inngest-image, which the probe
  # reads -- while the pin literal here is the GHCR ref. A whole-ref comparison therefore never
  # matches and the derivation would be a permanent silent no-op: the exact class this work
  # exists to retire. Guard B asserts both legs carry the identical digest, which is what makes
  # digest-only matching sound.
  PINNED_DIGEST="$(grep -oE 'soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' "$PIN_FILE" 2>/dev/null \
                   | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)"
  if [[ ! "$PINNED_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "TRANSIENT: reason=pin_unreadable file=${PIN_FILE} — the pinned digest could not be read," >&2
    echo "           so no boundary can be derived and NOTHING was measured. This is not a verdict" >&2
    echo "           about the host." >&2
    exit 2
  fi
  # 4.4: the probe row carries no time INSIDE the message -- the
  # emitter writes a flat key=value string, so the timestamp exists only as the row's outer `dt`
  # column. A sibling selector is required: bind the outer row, then emit "dt <TAB> message".
  # 4.5: inherit the SAME two-field host filter (#6616 -- host_name can lie, so both are checked).
  # This matters more after this PR than before it: the co-located web host execs the same
  # bootstrap image and emits the same marker, and this PR bumps all four pin sites to ONE digest,
  # so a colocated web host would emit rows carrying the pinned digest. Dormant today
  # (web_colocate_inngest defaults false), latent tomorrow.
  mine_dt() {
    local window="$1" term="$2" rows qrc out jrc
    rows="$("$QUERY" --since "$window" --grep "$term" --limit "$DERIVE_LIMIT" 2>/dev/null)"; qrc=$?
    if [[ "$qrc" -ne 0 ]]; then printf '__QUERY_FAILED__%s' "$qrc"; return 0; fi
    # `(fromjson?) as $row`, PARENTHESISED. `fromjson? as $row` is a SYNTAX ERROR in jq 1.7.x --
    # the grammar did not accept a postfix `?` immediately before `as` until 1.8 -- and GitHub's
    # runners ship 1.7. Reproduced locally against a downloaded jq-1.7.1: the whole filter fails to
    # COMPILE, `2>/dev/null` ate the error, the pipeline yielded nothing, and the caller reported
    # `probe_channel_dark` -- "the host emitted no rows at all". So on every jq<1.8 host the entire
    # derived-boundary arm was a permanent silent no-op that ACCUSED THE HOST, which is precisely
    # the class this probe's header exists to retire. Sibling mine() spells the same thing with a
    # PIPE (`fromjson? | .raw?`), which is why only the derivation broke.
    # A compile error is not a data condition. Route a jq failure to its own marker so it can never
    # again be read as silence from the host.
    out="$(printf '%s\n' "$rows" \
      | jq -R -r --arg h "$FLIP_HOST" --arg hn "$FLIP_HOST_NAME" \
           '(fromjson?) as $row
            | ($row.raw? | fromjson?) as $m
            | select($m != null)
            | select($m.host == $h and $m.host_name == $hn)
            | "\($row.dt)\t\($m.message // "")"' 2>/dev/null)"; jrc=$?
    if [[ "$jrc" -ne 0 ]]; then printf '__DECODE_FAILED__%s' "$jrc"; return 0; fi
    printf '%s' "$out"
  }
  DERIVE_ROWS="$(mine_dt "$DERIVE_WINDOW" "SOLEUR_INNGEST_SERVER_PROBE")"
  case "$DERIVE_ROWS" in
    __QUERY_FAILED__*)
      echo "TRANSIENT: reason=query_failed rc=${DERIVE_ROWS#__QUERY_FAILED__} — the read path did" >&2
      echo "           not answer, so no boundary could be derived. Nothing was measured." >&2
      exit 2 ;;
    __DECODE_FAILED__*)
      echo "TRANSIENT: reason=row_decode_failed rc=${DERIVE_ROWS#__DECODE_FAILED__} jq=$(jq --version 2>/dev/null || echo unknown)" >&2
      echo "           — jq did not decode the rows, so NOTHING was measured about the host. This is" >&2
      echo "           a defect in this probe or its environment, NOT a statement about the rollout;" >&2
      echo "           reporting it as a dark channel would accuse the host of the probe's own fault." >&2
      exit 2 ;;
  esac
  # Field-isolate image_ref from the decoded message rather than substring-matching the row
  # (#6475): a row that merely QUOTED the digest anywhere else must not count as a delivery.
  DERIVED_RAW="$(printf '%s\n' "$DERIVE_ROWS" \
    | awk -F'\t' -v d="$PINNED_DIGEST" '
        NF >= 2 {
          ref = ""
          n = split($2, kv, /[[:space:]]+/)
          for (i = 1; i <= n; i++) if (kv[i] ~ /^image_ref=/) { ref = substr(kv[i], 11) }
          if (ref != "" && index(ref, d) > 0) print $1
        }' \
    | sort | head -1 || true)"
  if [[ -z "$DERIVED_RAW" ]]; then
    # #7695 P2: "no row carries the pinned digest" and "no probe rows at all" are different states
    # and only one of them is about the rollout. mine_dt already holds the discriminator, and the
    # observed digest is the one-line answer to "why" -- so report it rather than making the
    # operator re-derive it.
    _observed="$(printf '%s\n' "$DERIVE_ROWS" \
      | awk -F'\t' 'NF >= 2 { n = split($2, kv, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (kv[i] ~ /^image_ref=/) print substr(kv[i], 11) }' \
      | grep -oE 'sha256:[0-9a-f]{64}' | sort -u | head -3 | tr '\n' ' ' || true)"
    if [[ -z "$(printf '%s' "$DERIVE_ROWS" | tr -d '[:space:]')" ]]; then
      echo "TRANSIENT: reason=probe_channel_dark window=${DERIVE_WINDOW} — the host emitted NO" >&2
      echo "           SOLEUR_INNGEST_SERVER_PROBE row at all, so the probe channel itself is the" >&2
      echo "           unknown here, not the rollout. NOTHING was measured about either." >&2
      exit 2
    fi
    echo "TRANSIENT: reason=boundary_underivable digest=${PINNED_DIGEST} observed=${_observed:-none}" >&2
    echo "           window=${DERIVE_WINDOW} — no probe" >&2
    echo "           row in the window reports an image_ref carrying the pinned digest, so the" >&2
    echo "           replace has not been observed yet. NOTHING about the rollout was measured;" >&2
    echo "           this is not 'the rollout failed'. Expected before the host replace runs." >&2
    exit 2
  fi
  # 4.3: NORMALISE, then run the EXISTING validator over the result -- never instead of it.
  # betterstack-query.sh returns ClickHouse `dt` values that are space-separated with no T and no
  # Z, so handing one straight to the validator exits boundary_unparseable: a permanent no-op
  # wearing a different reason string. Bypassing the validator would let a malformed boundary
  # widen the window to "any time", which is the failure the validator exists to prevent.
  AFTER="$(date -u -d "$DERIVED_RAW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  if ! [[ "$AFTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo "TRANSIENT: reason=boundary_unparseable length=${#DERIVED_RAW} (derived) — the row's dt" >&2
    echo "           could not be normalised to ISO-8601 UTC, so nothing was measured." >&2
    exit 2
  fi
  echo "note: boundary DERIVED from telemetry = ${AFTER} (earliest probe row carrying ${PINNED_DIGEST});" >&2
  echo "      verdicts are capped at PASS-or-TRANSIENT for this provenance." >&2
fi

# --- how old is the boundary? -----------------------------------------------------------------
# Decides whether silence is "not yet" or "never", and whether a read-path non-verdict has aged
# into CANNOT ESTABLISH. Computed before the first query so every arm can consult it.
now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
after_epoch="$(date -u -d "$AFTER" +%s 2>/dev/null || echo 0)"
# A value can match the ISO shape and still not be an instant (2026-02-30T00:00:00Z). An epoch of 0
# would silently zero boundary_age and disarm every deadline arm, so refuse it here.
if ! [[ "$after_epoch" =~ ^[1-9][0-9]*$ ]]; then
  echo "CANNOT_ESTABLISH: reason=boundary_unparseable length=${#AFTER} — the boundary matches the ISO shape but is" >&2
  echo "           not a real UTC instant, so no deadline can be computed." >&2
  exit 3
fi
boundary_age=0
if [[ "$now_epoch" -gt 0 ]]; then boundary_age=$(( now_epoch - after_epoch )); fi
stale_note="the boundary is ${boundary_age}s old; a silent host stops being 'not yet' after ${STALE_AFTER_S}s"

# _read_or_stop <raw> <query-failed-token> <label> — route a mine() failure sentinel to its
# non-verdict. Every query result passes through here, so a failed read can never be read as silence.
_read_or_stop() {
  case "$1" in
    __QUERY_FAILED__*)
      non_verdict "$2 rc=${1#__QUERY_FAILED__} — the $3 read did not answer; nothing was measured." ;;
    __DECODE_FAILED__*)
      non_verdict "row_decode_failed rc=${1#__DECODE_FAILED__} jq=$(jq --version 2>/dev/null || echo unknown) — the $3 rows" \
        "           were not decoded; nothing was measured. A probe defect, not a statement about the host." ;;
  esac
}
# _num <value> <label> — a jq-derived count that is not a number means jq failed; never read it as 0.
_num() {
  [[ "$1" =~ ^[0-9]+$ ]] || non_verdict "row_decode_failed — the $2 count could not be computed; nothing was measured."
}
# _cap_rows <n> — print at most 20 lines of stdin, then "(+N more)". The sweeper keeps only the last
# 4000 bytes of output, so an uncapped list would push the verdict line out of the comment.
_cap_rows() {
  local total="$1"
  head -n 20
  if [[ "$total" -gt 20 ]]; then echo "      (+$(( total - 20 )) more)"; fi
}

# --- LIVE: the newest flip-tag rows from this host --------------------------------------------
LIVE_RAW="$(mine "$WINDOW" "$LIMIT" "$TAG" "$TAG")"
_read_or_stop "$LIVE_RAW" query_failed LIVE
# Strip the page-full sentinel BEFORE the emptiness check: a page full of FOREIGN rows is a dark
# channel for this host, not a non-empty one.
LIVE="$(_strip_sentinel "$LIVE_RAW")"

# `armed` — kept as defence in depth (the current emitter never writes it into a row's flag), and
# UNCAPPED: `armed` is never a resting state, so it is an alarm whatever the boundary's provenance.
armed_n="$(printf '%s\n' "$LIVE" | jq -R -n -r "$JQ_LIB"'[rows[] | select(.flag == "armed")] | length' 2>/dev/null)"
_num "$armed_n" armed
if [[ "$armed_n" -gt 0 ]]; then
  echo "FAIL: reason=cutover_armed — ${armed_n} 'armed' FSM row(s) are present on the LIVE host." >&2
  printf '%s\n' "$LIVE" | jq -R -n -r --argjson known "$KNOWN_REASONS" "$JQ_LIB"'rows[] | select(.flag == "armed") | "      " + line($known)' 2>/dev/null \
    | _cap_rows "$armed_n" >&2
  echo "      A cutover is QUEUED: the next 30s poll stops inngest-server and runs FLUSHALL against" >&2
  echo "      the Redis AOF holding user job payloads. Establish who armed it before anything else." >&2
  echo "FAIL: reason=cutover_armed" >&2
  exit 1
fi

if [[ -z "$LIVE" ]]; then
  if [[ "$boundary_age" -gt "$STALE_AFTER_S" ]]; then
    verdict_fail "channel_dark_past_deadline host=${FLIP_HOST}/${FLIP_HOST_NAME} — zero rows" \
      "      in the newest ${LIMIT} rows / ${WINDOW}, and ${stale_note}." \
      "      At a 30-second cadence this is not a host that has yet to boot; it is a host that is not" \
      "      running the unit. Read the host's own tag rows for a mount-namespace setup failure:" \
      "      scripts/betterstack-query.sh --since ${AFTER} --grep inngest-cutover-flip"
  fi
  echo "TRANSIENT: reason=channel_dark host=${FLIP_HOST}/${FLIP_HOST_NAME} — zero rows in the newest ${LIMIT} rows / ${WINDOW}." >&2
  echo "           The host is not reporting, so its FSM state is UNKNOWN — not 'healthy'. If the" >&2
  echo "           apply has just run, the host may still be booting (${stale_note})." >&2
  exit 2
fi

# The drift half can only see OBJECT-shaped rows (see the header), so a string-shaped flip row in
# LIVE means the since-boundary drift query may be blind. That is not a PASS.
shape_n="$(printf '%s\n' "$LIVE" | jq -R -n -r "$JQ_LIB"'[rows[] | select(._str == true or ._undecodable == true)] | length' 2>/dev/null)"
_num "$shape_n" message-shape
if [[ "$shape_n" -gt 0 ]]; then
  echo "CANNOT_ESTABLISH: reason=message_shape_unsupported count=${shape_n} — flip-tag rows arrived with a STRING" >&2
  echo "           message (or one that no longer parses). DRIFT_GREPS matches only the object shape, so a" >&2
  echo "           drift row in that shape would be invisible. Nothing about drift was established." >&2
  exit 3
fi

# --- P5: drift — ONE sparse query over the WHOLE since-boundary interval ----------------------
DRIFT_RAW="$(mine "$AFTER" "$DRIFT_LIMIT" "$TAG" "${DRIFT_GREPS[@]}")"
_read_or_stop "$DRIFT_RAW" drift_query_failed drift
DRIFT_FULL=0
_page_full "$DRIFT_RAW" && DRIFT_FULL=1
DRIFT="$(_strip_sentinel "$DRIFT_RAW")"
# ONE jq call. The query is bounded by warehouse `dt` (since the boundary), so EVERY returned row is
# considered — including a run whose start_ts predates the boundary but which emitted after it: a
# row the query placed after the boundary is never dropped. The single EXEMPT shape is the op=resume
# row (reason + flag only); guard, machine and time are OWNERSHIP questions, answered below — but its
# machine still counts toward multiple_machines_since_boundary. Every other row is a finding, classed
# flush-path when its reason, its flag, or an `unexpected-exit(from=flipping|flushed)` says so.
ANALYSIS="$(printf '%s\n' "$DRIFT" | jq -R -n -c \
  --arg after "$AFTER" --arg entry "$DONE_ENTRY_REASON" --arg steady "$POST_CUTOVER_FLAG" \
  --arg guard "$EXPECTED_GUARD" --argjson fr "$FLUSH_PATH_REASONS" --argjson ff "$FLUSH_PATH_FLAGS" \
  --argjson known "$KNOWN_REASONS" "$JQ_LIB"'
  rows as $considered
  | ($considered | map(select((.reason == $entry and .flag == $steady) | not))) as $findings
  | { owners: [ $considered[]
                | select(.reason == $entry and .flag == $steady and (.start_ts | iso)
                         and .start_ts > $after and .guard == $guard)
                | {ts: .start_ts, mid: (._mid // "")} ],
      mids: ([ $considered[] | ._mid // "" | select(. != "") ] | unique),
      findings: ($findings | length),
      flush: ([ $findings[]
                | select((.reason as $r | $fr | index($r) != null)
                         or (.flag as $f | $ff | index($f) != null)
                         or ((.reason | type) == "string"
                             and (.reason | test("^unexpected-exit\\(from=(flipping|flushed)\\)$")))) ]
              | length),
      lines: [ $findings[] | line($known) ] }' 2>/dev/null)"
[[ -n "$ANALYSIS" ]] || non_verdict "row_decode_failed — the drift rows could not be analysed; nothing was measured."
read -r n_findings n_flush <<<"$(jq -r '"\(.findings) \(.flush)"' <<<"$ANALYSIS" 2>/dev/null)"
_num "${n_findings:-}" drift-finding
_num "${n_flush:-}" flush-path
if [[ "$n_findings" -gt 0 ]]; then
  mapfile -t _fl < <(jq -r '.lines[] | "      " + .' <<<"$ANALYSIS" | _cap_rows "$n_findings")
  if [[ "$n_flush" -gt 0 ]]; then
    verdict_fail "flush_path_transition_after_replace — the latch guarantee is broken (${n_findings} row(s) since ${AFTER})." \
      "${_fl[@]}" \
      "      A flush-path transition ran after the cutover. Treat the Redis contents as suspect and do" \
      "      not re-dispatch anything until it is explained."
  fi
  verdict_fail "drift_after_replace — the flip FSM left its post-cutover steady state (${n_findings} row(s) since ${AFTER})." \
    "${_fl[@]}" \
    "      The only FSM rows expected after the boundary are the op=resume row and the noop-done" \
    "      heartbeat. Establish what moved it before re-dispatching anything. Drift on THIS machine" \
    "      needs human review — moving the sidecar cannot clear it."
fi

# --- P3: seam refusals since the boundary -----------------------------------------------------
# The refusal is a raw `logger -t inngest-cutover-flip` line, so it is tag-isolated like everything
# else, and only a message that STARTS with the marker counts (a row merely quoting it does not).
# Boundary-independent in meaning (the #7761 condition occurring), so it is not capped.
REFUSALS_RAW="$(mine "$AFTER" "$DRIFT_LIMIT" "$TAG" "$REFUSAL_MARKER")"
_read_or_stop "$REFUSALS_RAW" refusals_query_failed seam-refusal
refusal_count="$(_strip_sentinel "$REFUSALS_RAW" | jq -R -n -r --arg mk "$REFUSAL_MARKER" \
  '[inputs | fromjson? | select(type == "string" and startswith($mk + " "))] | length' 2>/dev/null)"
_num "$refusal_count" seam-refusal
if [[ "$refusal_count" -gt 0 ]]; then
  echo "FAIL: reason=seam_refused count=${refusal_count} — the gate refused a fixture seam on the LIVE host." >&2
  echo "      A name in the ${DOPPLER_PROJECT_NAME}/${DOPPLER_CONFIG_NAME} Doppler config collided with a fixture" >&2
  echo "      seam name: the #7761 condition itself, occurring. The gate held, so nothing was executed —" >&2
  echo "      but rename the offending secret before it collides with a name the gate does not cover." >&2
  echo "FAIL: reason=seam_refused" >&2
  exit 1
fi

# --- truncation: only now may an ABSENCE be concluded ------------------------------------------
# Findings are positive observations and stand on a truncated page. "No drift", "no owning resume"
# and "no refusal" are absences, and a newest-first page drops the OLDEST rows first.
if [[ "$DRIFT_FULL" == "1" ]]; then
  non_verdict "drift_query_truncated limit=${DRIFT_LIMIT} — the since-boundary drift page is full, so" \
    "           neither 'no drift' nor 'no owning resume' can be concluded from it."
fi
if _page_full "$REFUSALS_RAW"; then
  non_verdict "refusals_query_truncated limit=${DRIFT_LIMIT} — the since-boundary refusal page is full, so" \
    "           'no seam refusal' cannot be concluded from it."
fi

# --- P1: delivery — every post-boundary heartbeat is stamped, and from ONE machine --------------
read -r post_stamped post_oldrev MACHINE <<<"$(printf '%s\n' "$LIVE" | jq -R -n -r \
  --arg after "$AFTER" --arg guard "$EXPECTED_GUARD" "$JQ_LIB"'
  [ rows[] | select(.reason == "noop-done" and .flag == "done" and (.start_ts | iso) and .start_ts > $after) ] as $p
  | ($p | map(select(.guard == $guard))) as $s
  | "\($s | length) \($p | map(select((.guard // "") != $guard)) | length) \(
      ($s | sort_by(.start_ts) | last | ._mid // "") | if . == "" then "-" else . end)"' 2>/dev/null)"
_num "${post_stamped:-}" stamped-heartbeat
_num "${post_oldrev:-}" unstamped-heartbeat
[[ "${MACHINE:-}" =~ ^[0-9a-zA-Z]+$ ]] || MACHINE="-"

# ANY unstamped post-boundary heartbeat is a stale image, even beside stamped ones: an old-image
# emitter under the same identity is exactly what the stamp exists to expose, and the absence of
# unstamped rows is the one thing a forger cannot remove from a genuinely stale host.
if [[ "$post_oldrev" -gt 0 ]]; then
  verdict_fail "stale_image — ${post_oldrev} post-boundary noop-done marker(s) carry no guard=${EXPECTED_GUARD} stamp." \
    "      A PRE-#7761 script is polling on this host identity. The replace did not deliver the fix:" \
    "      check that BOTH image digest pins in cloud-init-inngest.yml moved to the digest the build" \
    "      produced (build-inngest-bootstrap-image.yml run log). The seam exposure is still live."
fi

_insufficient() { # _insufficient <count> <since-what> <since-epoch>
  if [[ $(( now_epoch - $3 )) -gt "$STALE_AFTER_S" ]]; then
    verdict_fail "insufficient_post_replace_markers_past_deadline count=$1" \
      "      want>=${MIN_MARKERS} distinct stamped noop-done after $2, more than ${STALE_AFTER_S}s ago." \
      "      The host has not been observed POLLING since then. At a 30-second cadence that is not 'not yet'."
  fi
  echo "TRANSIENT: reason=insufficient_post_replace_markers count=$1" >&2
  echo "           want>=${MIN_MARKERS} distinct stamped noop-done after $2 (newest ${LIMIT} rows / ${WINDOW})." >&2
  echo "           At a 30-second cadence this resolves within minutes." >&2
  exit 2
}
if [[ "$post_stamped" -eq 0 ]]; then
  _insufficient 0 "the boundary ${AFTER}" "$after_epoch"
fi
if [[ "$MACHINE" == "-" ]]; then
  echo "CANNOT_ESTABLISH: reason=machine_id_absent count=${post_stamped} — stamped heartbeats carry no _MACHINE_ID," >&2
  echo "           so ownership cannot be bound to a machine. The shipper's journald fields changed." >&2
  exit 3
fi
# ONE machine since the boundary: heartbeats (LIVE) and every drift-query row (resume rows included).
n_mids="$( { printf '%s\n' "$LIVE" | jq -R -n -r --arg after "$AFTER" "$JQ_LIB"'
             rows[] | select(.reason == "noop-done" and (.start_ts | iso) and .start_ts > $after) | ._mid // empty'
           jq -r '.mids[]' <<<"$ANALYSIS"; } 2>/dev/null | grep -v '^$' | sort -u | grep -c . || true)"
_num "$n_mids" machine
if [[ "$n_mids" -gt 1 ]]; then
  echo "CANNOT_ESTABLISH: reason=multiple_machines_since_boundary count=${n_mids} — more than one _MACHINE_ID emitted" >&2
  echo "           flip rows after ${AFTER}. The host was replaced after the boundary (or a second emitter" >&2
  echo "           shares its identity): move the sidecar to the latest replace's inngest_host_replace completedAt." >&2
  exit 3
fi

# --- the boundary must PRECEDE the owning machine's first row ---------------------------------
# Otherwise moving the sidecar forward past a drift event would erase it — a false PASS on a P1
# tracker. A real replace time always precedes the new machine's first row (2026-09-23: replace
# 19:36:32, first row 19:37:57), so ANY row from machine M at or before the boundary means the
# boundary sits inside M's lifetime. Queried by M's own _MACHINE_ID over 30 days (sparse, and
# independent of how long M was silent), bounded by `dt` <= the boundary.
check_since="$(date -u -d "@$(( after_epoch - 30 * 86400 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
BC_RAW="$(mine "$check_since" "$BOUNDARY_CHECK_LIMIT" "$TAG" --until "$AFTER" "\"_MACHINE_ID\":\"${MACHINE}\"")"
_read_or_stop "$BC_RAW" boundary_check_query_failed boundary-check
inside="$(_strip_sentinel "$BC_RAW" | jq -R -n -r --arg m "$MACHINE" "$JQ_LIB"'[rows[] | select(._mid == $m)] | length' 2>/dev/null)"
_num "$inside" boundary-check
if [[ "$inside" -gt 0 ]]; then
  echo "CANNOT_ESTABLISH: reason=boundary_inside_owning_machine_lifetime — machine ${MACHINE:0:8} emitted ${inside} row(s)" >&2
  echo "           at or before the boundary ${AFTER}, so the boundary is after this machine booted." >&2
  echo "           The sidecar must hold the completion time of the replace that created this machine; moving it" >&2
  echo "           later can re-certify only a NEW machine. Drift on this machine needs human review." >&2
  exit 3
fi
if _page_full "$BC_RAW"; then
  non_verdict "boundary_check_truncated — the boundary check filled a ${BOUNDARY_CHECK_LIMIT}-row page."
fi

# --- P4: done provenance — the FSM re-earned done on THIS machine after the boundary -----------
OWNED_SINCE="$(jq -r --arg m "$MACHINE" '[.owners[] | select(.mid == $m) | .ts] | sort | first // ""' <<<"$ANALYSIS" 2>/dev/null)"
if [[ -n "$OWNED_SINCE" && ! "$OWNED_SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  non_verdict "row_decode_failed — the owning resume's timestamp did not parse; nothing was measured."
fi
if [[ -z "$OWNED_SINCE" ]]; then
  _dnr=(
    "      Machine ${MACHINE:0:8} emits guard-stamped noop-done after the boundary ${AFTER}, but has no"
    "      post-boundary, guard-stamped '${DONE_ENTRY_REASON}' row: its done is INHERITED, not re-earned."
    "      Run \`gh workflow run cutover-inngest.yml -f op=resume\` (it waits for approval on the"
    "      inngest-cutover environment). If the host was replaced after ${AFTER}, the sidecar must move to"
    "      that apply run's inngest_host_replace completedAt."
  )
  if [[ "$boundary_age" -gt "$STALE_AFTER_S" ]]; then
    verdict_fail "done_not_resumed_past_deadline — no op=resume on machine ${MACHINE:0:8} since ${AFTER}." "${_dnr[@]}"
  fi
  echo "TRANSIENT: reason=done_not_resumed — no op=resume on machine ${MACHINE:0:8} since ${AFTER} (${stale_note})." >&2
  printf '%s\n' "${_dnr[@]}" >&2
  exit 2
fi

# --- P2: liveness AFTER the owning resume, and NOW ---------------------------------------------
# DISTINCT start_ts: one heartbeat delivered twice is one heartbeat.
read -r post_ok newest_hb <<<"$(printf '%s\n' "$LIVE" | jq -R -n -r \
  --arg m "$MACHINE" --arg since "$OWNED_SINCE" --arg guard "$EXPECTED_GUARD" "$JQ_LIB"'
  [ rows[] | select(.reason == "noop-done" and .flag == "done" and .guard == $guard and ._mid == $m
                    and (.start_ts | iso) and .start_ts > $since) | .start_ts ] | unique
  | "\(length) \(last // "-")"' 2>/dev/null)"
_num "${post_ok:-}" liveness
owned_epoch="$(date -u -d "$OWNED_SINCE" +%s 2>/dev/null || echo "$after_epoch")"
if [[ "$post_ok" -lt "$MIN_MARKERS" ]]; then
  _insufficient "$post_ok" "the op=resume at ${OWNED_SINCE}" "$owned_epoch"
fi
newest_epoch="$(date -u -d "${newest_hb:-}" +%s 2>/dev/null || echo 0)"
if [[ $(( now_epoch - newest_epoch )) -gt "$HEARTBEAT_MAX_AGE_S" ]]; then
  echo "TRANSIENT: reason=heartbeat_stale newest=${newest_hb:-none} — machine ${MACHINE:0:8}'s newest heartbeat is more" >&2
  echo "           than ${HEARTBEAT_MAX_AGE_S}s old, so the 30s timer is not observed cycling NOW." >&2
  exit 2
fi

corroboration="doppler read skipped (no credential in this environment)"
[[ -n "$doppler_flag" ]] && corroboration="doppler corroborates: ${doppler_flag}"
# Disclose any seam that shaped this run. Under the sweeper's `env -i` it is always `default`.
seams=""
for _v in $(compgen -v FLIP_ROLLOUT_ || true); do
  [[ -n "${!_v:-}" ]] && seams="${seams:+${seams},}${_v}"
done
echo "PASS: #7761 delivered — ${post_ok} guard=${EXPECTED_GUARD} noop-done heartbeats on machine ${MACHINE:0:8} owned since ${OWNED_SINCE}"
echo "      (op=resume after the boundary ${AFTER}); no drift and no seam refusal since the boundary; ${corroboration}"
echo "      seams=${seams:+overridden:}${seams:-default}"
exit 0
