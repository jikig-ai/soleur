#!/usr/bin/env bash
# #7761 — the seam-gate + injection-bound reached the dedicated inngest host, and the host is
# still in its safe terminal state afterwards.
#
# TRACKER: **#7761**. It stays OPEN until this reads PASS. scripts/sweep-followthroughs.sh lists
# `--state open`, so hosting a probe on a CLOSED issue is a permanent silent no-op — which is why
# the PR that ships this carries `Ref #7761` and NOT `Closes #7761`.
#
# WHY THIS PROBE IS A COMMITTED DELIVERABLE RATHER THAN AN IN-SESSION CHECK. Merging this fix
# changes NOTHING on the live host. Every on-host asset here is baked into the OCI bootstrap image
# and pulled by a digest literal in `user_data`, which is ForceNew on `hcloud_server.inngest` with
# no `ignore_changes` (ADR-100 addendum 2026-08-25 / #7674). So delivery is a tag -> image build ->
# digest bump -> HOST REPLACE of the fleet's sole scheduler. A production destroy-and-recreate
# whose verification cannot be re-run is an unauditable change, so the verification ships with it.
#
# WHAT IT VERIFIES — POSITIVELY, NEVER BY ABSENCE ALONE.
#
#   1. The NEW script is actually on the host. Every other observable here — the flag value, the
#      noop markers, the absence of flush transitions — is emitted BYTE-IDENTICALLY by the pre-fix
#      script, so without this the probe would report "delivered" for a replace that silently kept
#      the old image (a digest that never moved, a flip-asset copy that fell through its `|| true`
#      guard). emit_state stamps `guard:<GUARD_REV>`; only the post-#7761 script emits it.
#
#   2. At least two `noop-rolled-back` markers carry timestamps AFTER the replace. Two, not one:
#      one marker proves the host booted and emitted once; two proves the 30-second timer is
#      actually CYCLING, which is the property that makes the flag a live control channel rather
#      than a value nobody is reading. A host with no inbound SSH has no other channel.
#
#   3. No flag drift after the replace. This is what "the flush latch is intact" means in an
#      observable form: the latch file lives on /mnt/data and this repo has no SSH path to read it
#      (hr-no-ssh-fallback-in-runbooks), and in the `rolled-back` terminal state the FSM never
#      consults it. What the latch EXISTS to guarantee is observable — that nothing moved off the
#      terminal state. ANY other post-boundary flag fails, not just the three flush-path ones:
#      `armed` is the state whose NEXT poll stops the server and runs the FLUSHALL, so accepting it
#      would report all-clear on the last quiet moment before the destructive arm.
#
#   4. No seam refusal. A `SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED` marker on the live host means a
#      name in the soleur-inngest/prd Doppler config collided with a fixture seam — the #7761
#      condition itself, occurring. Queried separately because it is a raw string, not emit_state
#      JSON, so the JSON selector below discards it by construction.
#
# WHY THE MARKER GREP IS THE TAG AND NOT A `SOLEUR_` STRING. An earlier revision grepped
# `SOLEUR_INNGEST_CUTOVER`, which compiles to `raw LIKE '%SOLEUR_INNGEST_CUTOVER%'`. emit_state's
# rows are BARE JSON — the identity lives in the syslog tag, not the payload — so that grep matched
# only the four exceptional-path markers, all of which `fromjson?` then discarded. The probe could
# never return PASS and its flush assertion could never return FAIL: a permanent silent no-op, the
# exact failure its own header claims to retire. `SYSLOG_IDENTIFIER` IS present in `raw` (proved by
# betterstack-query.sh's `--raw-only` mode having to exclude it), so the tag is the correct grep.
#
# THE BOUNDARY IS REQUIRED, AND ITS ABSENCE IS NOT A PASS. "After the replace" cannot be evaluated
# without knowing when the replace happened, and a window reaching back past it would be satisfied
# by the OLD host's markers — the probe would certify the rollout using evidence produced by the
# machine the rollout replaced. Read from FLIP_ROLLOUT_AFTER, else the committed `.after` sidecar,
# else DERIVED from telemetry (see the provenance split below).
# A boundary that is OLD with still no markers is a FAIL, not a TRANSIENT: at a 30-second cadence
# "not yet" expires in minutes, and leaving it TRANSIENT forever makes a permanently bricked
# scheduler indistinguishable from a rollout nobody has run.
#
# THAT FAIL ARM IS SCOPED TO A *SUPPLIED* BOUNDARY (#7695). It rests on the boundary being an
# ASSERTION -- a human or an apply said "the replace happened at T" -- so silence after T really is
# a bricked scheduler. Since #7695 the boundary can instead be DERIVED from telemetry (the earliest
# probe row whose image_ref carries the pinned digest) when neither source supplies one, because
# the `.after` sidecar never existed and nothing writes it, so this probe returned
# `boundary_unknown` on every sweep and measured nothing for the life of the issue.
#
# A derived boundary is an INFERENCE, and it can be wrong in the one direction that manufactures a
# false condemnation: any re-pin to a digest some host already reported -- a rollback re-pin above
# all -- derives a boundary in the PAST, on the machine the rollout was meant to replace. So:
#
#   SUPPLIED boundary -> PASS / FAIL / TRANSIENT, exactly as above. Nothing changes.
#   DERIVED  boundary -> PASS or TRANSIENT only, NEVER FAIL (enforced by verdict_fail()).
#
# The two rules govern disjoint provenances, so neither overrides the other. The anti-brick signal
# is ROUTED, not lost: where the derived arm would have failed it exits 2 with
# `derived_boundary_stale_supply_authoritative_boundary`, which names the missing authority and
# says how to re-arm the FAIL arm, rather than blaming the host on the strength of an inference.
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh):
#   0 = PASS       new script on host, >=2 post-boundary rolled-back markers, no drift, no refusal.
#   1 = FAIL       a real regression: flag moved, a flush ran, a seam was refused, or the host has
#                  been silent well past the boundary. The boundary-dependent arms of this are
#                  reachable ONLY under a SUPPLIED boundary (see the provenance split above). THREE
#                  boundary-independent arms fail under either provenance, because none consults the
#                  boundary: `cutover_armed`, `seam_refused`, and the Doppler flag mismatch.
#                  NOTE the Doppler one is INERT in scheduled-followthrough-sweeper.yml, which
#                  provisions no Doppler token and installs no Doppler CLI -- so in the only
#                  environment that runs this on a schedule the surviving pair is `cutover_armed`
#                  (telemetry) and `seam_refused`. That is why `cutover_armed` must stay uncapped:
#                  it is the FLUSHALL alarm on the one channel CI actually has.
#   2 = TRANSIENT  not delivered yet, boundary unknown, credentials unprovisioned, or any
#                  query/decode failure. Nothing was measured; this is never an all-clear.
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
AFTER_FILE="${FLIP_ROLLOUT_AFTER_FILE:-$REPO_ROOT/scripts/followthroughs/inngest-cutover-flip-rollout-7761.after}"
# Seamed like QUERY so the Doppler arm is drivable by the suite. Without this the corroboration
# branch is unreachable by design and its FAIL arm has no coverage.
DOPPLER_BIN="${FLIP_ROLLOUT_DOPPLER_BIN:-doppler}"

# The syslog TAG, not a marker substring. See the header.
TAG="${FLIP_ROLLOUT_TAG:-inngest-cutover-flip}"
REFUSAL_MARKER="SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED"
# Two identity fields, both required (#6616 — `host_name` telemetry has been observed lying: a web
# host self-labelled with the sed-rendered dedicated-host literal). `host` is Vector's auto-derived
# OS hostname, which a stale literal cannot forge. A PASS here closes #7761, so a row matching only
# `host_name` would close the tracker on evidence from the wrong machine.
FLIP_HOST="${FLIP_ROLLOUT_HOST:-soleur-inngest}"
FLIP_HOST_NAME="${FLIP_ROLLOUT_HOST_NAME:-soleur-inngest-prd}"
# The liveness window is deliberately NARROW. The tag emits ~2,880 rows/day at a 30s cadence, so a
# 24h window against any sane row limit takes the NEWEST N rows and silently examines a slice —
# reporting a slice as the window is the failure cutover-inngest.sh documents for this same tag.
# Two markers at 30s needs minutes, not hours.
WINDOW="${FLIP_ROLLOUT_WINDOW:-2h}"
LIMIT="${FLIP_ROLLOUT_LIMIT:-500}"
# The drift and refusal queries run over a WIDER window with their own narrow greps, so their row
# counts are tiny and the limit is not binding on them.
DRIFT_WINDOW="${FLIP_ROLLOUT_DRIFT_WINDOW:-24h}"
DOPPLER_PROJECT_NAME="${FLIP_ROLLOUT_DOPPLER_PROJECT:-soleur-inngest}"
DOPPLER_CONFIG_NAME="${FLIP_ROLLOUT_DOPPLER_CONFIG:-prd}"
# The expected terminal flag and the marker threshold are INLINE, not env-overridable. An earlier
# revision exposed them as FLIP_ROLLOUT_EXPECTED_FLAG / _MIN_MARKERS, which is an environment-
# supplied answer key on a probe that authorizes closing a security issue — in a PR whose entire
# thesis is that environment-supplied values are untrusted.
EXPECTED_FLAG="rolled-back"
# #7695 P0 — THE LIVE FLAG IS `aborted`, NOT `rolled-back`, AND BOTH ARE TERMINAL NO-OPS.
# Measured 2026-09-07: `doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd` returns
# `aborted`, and the live rows are {"reason":"noop-aborted","flag":"aborted"} every 30s. Matching
# only `rolled-back` made post_ok 0 forever AND made the drift selector match EVERY row -- so this
# probe still could not PASS, having swapped `boundary_unknown` for `flag_drift`: the same
# permanent silent no-op wearing a different reason string, which is the exact class this file's
# header exists to retire. ADR-199's clearance predicate already accepts both.
#
# INLINE, not env-overridable, for the same reason EXPECTED_FLAG is: this is the answer key on a
# probe that authorizes closing a type/security issue.
#
# `armed`, `flipping`, `flushed` and `done` are deliberately NOT here -- they are the condemnations.
TERMINAL_SAFE_FLAGS='["rolled-back","aborted"]'
MIN_MARKERS=2
# The guard revision the post-#7761 script stamps into every emit_state row.
EXPECTED_GUARD="${FLIP_ROLLOUT_EXPECTED_GUARD:-7761}"
# How long after the boundary a silent host stops being "not yet" and becomes a failure.
STALE_AFTER_S="${FLIP_ROLLOUT_STALE_AFTER_S:-3600}"

# --- the boundary -----------------------------------------------------------------------------
AFTER="${FLIP_ROLLOUT_AFTER:-}"
# #7695 4.0 — PROVENANCE. A SUPPLIED boundary is an assertion by a human or an apply that the
# replace happened at T, so silence after T really is a bricked scheduler and the FAIL arms below
# apply verbatim. A DERIVED boundary is an INFERENCE and is capped at PASS-or-TRANSIENT by
# verdict_fail(). The two rules govern disjoint provenances; neither overrides the other.
BOUNDARY_PROVENANCE=supplied
if [[ -z "$AFTER" && -r "$AFTER_FILE" ]]; then
  AFTER="$(tr -d '[:space:]' < "$AFTER_FILE" 2>/dev/null || true)"
fi
if [[ -z "$AFTER" ]]; then
  # #7695 4.1 — DO NOT exit here. This block is pure env/file I/O and sits AHEAD of everything the
  # derivation needs (the BETTERSTACK_QUERY_* check, the jq check, mine()). Record that the
  # boundary must be derived and continue; the derivation runs after those preflights, which also
  # yields the better reason for free -- absent credentials exit `credentials_unprovisioned`,
  # which is more accurate than a boundary complaint.
  BOUNDARY_PROVENANCE=derived
fi
if [[ "$BOUNDARY_PROVENANCE" == "supplied" ]] && ! [[ "$AFTER" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "TRANSIENT: reason=boundary_unparseable value='${AFTER}' — expected ISO-8601 UTC" >&2
  echo "           (YYYY-MM-DDTHH:MM:SSZ). A boundary that cannot be parsed must not be" >&2
  echo "           silently widened to 'any time', which would let pre-replace markers pass." >&2
  exit 2
fi

# --- 1. the flag, CORROBORATED from Doppler when a credential happens to be present ------------
#
# NOT a hard requirement, and that is a deliberate correction. The sweeper
# (scheduled-followthrough-sweeper.yml) exposes BETTERSTACK_QUERY_* and several other secrets but
# NO Doppler token, so a probe that REQUIRED a Doppler read would return `flag_unreadable` on every
# sweep for the life of the issue — a permanent silent no-op, precisely the failure mode the
# sibling #7674 probe was written to retire. The flag is available on the channel the sweeper DOES
# have: emit_state stamps it into every marker. That reading is the primary source below; a Doppler
# read, when a credential is present, is strictly better evidence for one narrow case — the flag
# changed in Doppler but not yet observed by the host — so it FAILS FAST when available.
doppler_flag=""
if command -v "$DOPPLER_BIN" >/dev/null 2>&1; then
  doppler_flag="$("$DOPPLER_BIN" secrets get INNGEST_CUTOVER_FLIP \
                    -p "$DOPPLER_PROJECT_NAME" -c "$DOPPLER_CONFIG_NAME" --plain 2>/dev/null || true)"
  doppler_flag="$(printf '%s' "$doppler_flag" | tr -d '[:space:]')"
fi
# #7695: membership in the terminal-safe SET, not equality with one member -- `aborted` is the
# live value and is as terminal as `rolled-back`.
_flag_is_terminal_safe() {
  [[ -n "${1:-}" ]] || return 1
  printf '%s' "$TERMINAL_SAFE_FLAGS" | jq -e --arg f "$1" 'index($f) != null' >/dev/null 2>&1
}
# #7695 P3: print the value only when it is a known FSM enum member. This string is echoed into a
# PUBLIC GitHub issue comment by sweep-followthroughs.sh, whose own comment records that issue
# bodies do NOT pass the runner's secret masker -- so an unconstrained print publishes whatever
# the secret happens to hold.
_flag_for_display() {
  case "${1:-}" in
    rolled-back|aborted|armed|flipping|flushed|done|"") printf '%s' "${1:-<empty>}" ;;
    *) printf '<non-enum value, %s chars>' "${#1}" ;;
  esac
}
if [[ -n "$doppler_flag" ]] && ! _flag_is_terminal_safe "$doppler_flag"; then
  echo "FAIL: the FSM flag in ${DOPPLER_PROJECT_NAME}/${DOPPLER_CONFIG_NAME} reads" >&2
  echo "      '$(_flag_for_display "$doppler_flag")', expected one of ${TERMINAL_SAFE_FLAGS}." >&2
  echo "      The host was braked and serving nothing before this rollout; a flag that has moved" >&2
  echo "      means either someone armed a cutover or the replace resumed a transient. Do NOT" >&2
  echo "      re-dispatch the apply until this is explained — the armed path ends in FLUSHALL." >&2
  exit 1
fi

# --- credentials for the marker read ----------------------------------------------------------
missing=""
[[ -z "${BETTERSTACK_QUERY_HOST:-}" ]] && missing="${missing} BETTERSTACK_QUERY_HOST"
[[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]] && missing="${missing} BETTERSTACK_QUERY_USERNAME"
[[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && missing="${missing} BETTERSTACK_QUERY_PASSWORD"
if [[ -n "$missing" ]]; then
  echo "TRANSIENT: reason=credentials_unprovisioned — missing:${missing}." >&2
  echo "           The flag read above passed, but the liveness half was never asked. That is" >&2
  echo "           NOT a PASS: a correct flag on a host that stopped polling is exactly the" >&2
  echo "           twelve-day false-'done' shape ADR-100 records (#7228)." >&2
  exit 2
fi
# jq is load-bearing for every selector below. Unpreflighted, a missing jq empties the row set and
# the probe blames the HOST ("not reporting") for a local tooling fault.
if ! command -v jq >/dev/null 2>&1; then
  echo "TRANSIENT: reason=jq_unavailable — the decode path is unusable, so nothing was measured." >&2
  exit 2
fi

# mine <window> <grep-term> — decode, then field-isolate on the DECODED object. `-R` plus
# `fromjson?` at BOTH levels is load-bearing rather than defensive habit: without `-R`, ONE
# malformed line aborts the whole jq invocation and every valid row after it is lost — which would
# surface as "the host emits nothing" on a window that in fact contained a clean PASS.
mine() {
  local window="$1" term="$2" rows qrc
  rows="$("$QUERY" --since "$window" --grep "$term" --limit "$LIMIT" 2>/dev/null)"; qrc=$?
  if [[ "$qrc" -ne 0 ]]; then printf '__QUERY_FAILED__%s' "$qrc"; return 0; fi
  printf '%s\n' "$rows" \
    | jq -R -r --arg h "$FLIP_HOST" --arg hn "$FLIP_HOST_NAME" \
         'fromjson? | .raw? | fromjson?
          | select(.host == $h and .host_name == $hn)
          | .message? // empty' 2>/dev/null
}


# --- #7695 4.0: the ONE place a FAIL may be emitted -------------------------------------------
#
# THE RULE, AND WHY IT IS STRUCTURAL RATHER THAN REMEMBERED. A DERIVED boundary may produce
# PASS or TRANSIENT and NEVER FAIL. Every BOUNDARY-DEPENDENT FAIL routes through this helper, so
# a later edit that adds a bare `exit 1` to one of those arms is a visible deviation rather than
# a silent restoration of the hazard below.
#
# TWO FAIL ARMS DELIBERATELY DO NOT ROUTE THROUGH IT, AND MUST NOT. The cap exists because an
# INFERRED boundary can misattribute a PRE-replace event as post-replace. An arm that never
# consults the boundary cannot make that error, and capping it would suppress a true present-tense
# alarm for no gain:
#   * the Doppler FSM-flag mismatch — reads the flag's CURRENT value, no $AFTER anywhere. A flag
#     that has moved means someone armed a cutover, and the armed path ends in FLUSHALL.
#   * `cutover_armed` — matches `flag == "armed"` over DRIFT_WINDOW with NO $AFTER filter. `armed`
#     is never a resting state, so it is an alarm regardless of when the replace happened.
#   * `seam_refused` — counts refusal markers over DRIFT_WINDOW, not relative to $AFTER. It is the
#     #7761 condition itself occurring, on the live host, right now.
# Both are boundary-independent by inspection; if a future edit makes either consult $AFTER, it
# must move under this helper in the same edit.
#
# THE HAZARD. The derivation reads the pin. Any re-pin to a digest some host ALREADY reported --
# a rollback re-pin above all -- derives a boundary in the PAST, on the very machine the rollout
# was meant to replace. `boundary_age > STALE_AFTER_S` would then convert ordinary silence into
# `FAIL reason=stale_image`, whose text tells the operator "the replace kept the old image ...
# the seam exposure is still live" FOR A REPLACE THAT NEVER HAPPENED -- a false accusation, on a
# type/security tracker. This script's own header warns against certifying a rollout with
# evidence from the machine it replaced; an unbounded derivation reintroduces that inverted.
#
# THE ANTI-BRICK SIGNAL IS ROUTED, NOT LOST. Where the derived arm would have failed it exits 2
# naming the MISSING AUTHORITY rather than blaming the host, and says how to re-arm the
# authoritative FAIL arm. A bricked scheduler stays distinguishable -- via a reason that demands
# the authoritative input, not via a condemnation built on an inference.
verdict_fail() {
  local reason="$1"; shift
  if [[ "${BOUNDARY_PROVENANCE:-supplied}" == "derived" ]]; then
    echo "TRANSIENT: reason=derived_boundary_stale_supply_authoritative_boundary" >&2
    echo "           (the derived arm would have reported ${reason})" >&2
    echo "           The boundary was INFERRED from the earliest probe row carrying the pinned" >&2
    echo "           digest -- nobody asserted a replace time. An inference is not entitled to" >&2
    echo "           declare a regression, so this is capped at TRANSIENT." >&2
    echo "           To re-arm the authoritative FAIL arm, set FLIP_ROLLOUT_AFTER to the apply's" >&2
    echo "           completion time (ISO-8601 UTC) or write it to ${AFTER_FILE}." >&2
    # #7695 P3 (review): print the detail lines here too. Capping the VERDICT is the point; dropping
    # the evidence is not -- without this the operator loses the flag/reason/timestamp rows and keeps
    # only the reason token, which is a paging-detail regression introduced by the cap itself.
    [[ "$#" -gt 0 ]] && printf '%s\n' "$@" >&2
    exit 2
  fi
  echo "FAIL: reason=${reason}" >&2
  printf '%s\n' "$@" >&2
  exit 1
}

# --- #7695 4.1-4.6: derive the boundary when none was supplied --------------------------------
if [[ "$BOUNDARY_PROVENANCE" == "derived" ]]; then
  # 4.6: "first" is a SLICE. mine()'s --limit returns the NEWEST N rows before re-sorting, so past
  # roughly 500 probe rows the earliest row FOUND is not the earliest that exists. Raise the limit
  # for this query specifically -- and note the residual is bounded in the safe direction: a slice
  # can only push the derived boundary LATER, which delays a PASS. Under verdict_fail()'s cap it
  # can never manufacture a condemnation. THAT CLAIM IS ONE-SIDED AND THE OTHER SIDE MATTERS: the
  # same later boundary also SHRINKS the drift arm's window (it filters `.start_ts > $after`), so a
  # slice can manufacture a false ACQUITTAL on the safety half. That is why the derivation runs over
  # DRIFT_WINDOW below -- the two horizons then agree by construction and both directions are
  # bounded.
  # #7695 P1/P2 — DERIVE OVER THE *DRIFT* HORIZON, NOT THE LIVENESS ONE. WINDOW (2h) is sized for
  # the flip tag's 30s cadence; the host probe fires HOURLY, so a 2h derivation has a margin of one
  # sample AND -- worse -- pins AFTER to the window edge, silently collapsing the drift arm's
  # documented 24h horizon to 2h and discarding 22h of safety evidence before printing "no flag
  # drift". Default to DRIFT_WINDOW so the two agree by construction.
  DERIVE_WINDOW="${FLIP_ROLLOUT_DERIVE_WINDOW:-$DRIFT_WINDOW}"
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
  # 4.4: mine() emits .message only, and the probe row carries no time INSIDE the message -- the
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
    echo "TRANSIENT: reason=boundary_unparseable value='${DERIVED_RAW}' (derived) — the row's dt" >&2
    echo "           could not be normalised to ISO-8601 UTC, so nothing was measured." >&2
    exit 2
  fi
  echo "note: boundary DERIVED from telemetry = ${AFTER} (earliest probe row carrying ${PINNED_DIGEST});" >&2
  echo "      verdicts are capped at PASS-or-TRANSIENT for this provenance." >&2
fi

LIVE="$(mine "$WINDOW" "$TAG")"
case "$LIVE" in
  __QUERY_FAILED__*)
    echo "TRANSIENT: reason=query_failed rc=${LIVE#__QUERY_FAILED__} — the ClickHouse read path did not answer." >&2
    echo "           Nothing about the host's liveness was measured. Observed 2026-09-03: this" >&2
    echo "           source answers 503 'under maintenance', which is a read-path outage and says" >&2
    echo "           nothing about the host." >&2
    exit 2 ;;
esac

# --- how stale is the boundary? ---------------------------------------------------------------
# Used only to decide whether silence is "not yet" or "never". Computed before the marker counts
# so both the empty and the insufficient arms can consult it.
now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
after_epoch="$(date -u -d "$AFTER" +%s 2>/dev/null || echo 0)"
boundary_age=0
if [[ "$now_epoch" -gt 0 && "$after_epoch" -gt 0 ]]; then boundary_age=$(( now_epoch - after_epoch )); fi
stale_note="the boundary is ${boundary_age}s old; a silent host stops being 'not yet' after ${STALE_AFTER_S}s"

if [[ -z "$LIVE" ]]; then
  if [[ "$boundary_age" -gt "$STALE_AFTER_S" ]]; then
    verdict_fail "channel_dark_past_deadline host=${FLIP_HOST}/${FLIP_HOST_NAME} — zero rows" \
      "      in ${WINDOW}, and ${stale_note}." \
      "      At a 30-second cadence this is not a host that has yet to boot; it is a host that" \
      "      is not running the unit. Check for a mount-namespace setup failure from the" \
      "      ReadWritePaths/StateDirectory directives, which kills the unit on every fire and" \
      "      emits nothing at all."
  fi
  echo "TRANSIENT: reason=channel_dark host=${FLIP_HOST}/${FLIP_HOST_NAME} window=${WINDOW} — zero rows." >&2
  echo "           The host is not reporting, so its FSM state is UNKNOWN — not 'healthy'. If the" >&2
  echo "           apply has just run, the host may still be booting (${stale_note})." >&2
  exit 2
fi

# --- 2. liveness, and 1. the delivery discriminator -------------------------------------------
# `.start_ts` is compared as a STRING, so a row whose stamp is not a date must be excluded rather
# than sorted: inngest-cutover-flip.sh falls back to the literal `unknown` when `date` fails, and
# "unknown" > "2026-…" lexicographically — so a broken-clock row, INCLUDING one from the replaced
# host, would otherwise count as post-boundary evidence toward the PASS.
post_ok="$(printf '%s\n' "$LIVE" \
  | jq -R -r --arg after "$AFTER" --argjson safe "$TERMINAL_SAFE_FLAGS" --arg guard "$EXPECTED_GUARD" \
       'fromjson?
        | select(.start_ts | type == "string" and test("^[0-9]{4}-"))
        | select(.start_ts > $after)
        | select(.flag as $f | $safe | index($f) != null)
        | select(.reason == ("noop-" + .flag) and .guard == $guard)
        | .start_ts' 2>/dev/null | grep -c . || true)"
case "$post_ok" in ''|*[!0-9]*) post_ok=0 ;; esac

# Post-boundary rows that are well-formed but carry the WRONG guard rev (or none) — i.e. the
# pre-#7761 script is still running. Distinguished from "no rows" so the operator is told the
# replace kept the old image rather than that the host is silent.
post_oldrev="$(printf '%s\n' "$LIVE" \
  | jq -R -r --arg after "$AFTER" --arg guard "$EXPECTED_GUARD" \
       'fromjson?
        | select(.start_ts | type == "string" and test("^[0-9]{4}-"))
        | select(.start_ts > $after)
        | select((.guard // "") != $guard)
        | .start_ts' 2>/dev/null | grep -c . || true)"
case "$post_oldrev" in ''|*[!0-9]*) post_oldrev=0 ;; esac

if [[ "$post_oldrev" -gt 0 && "$post_ok" -eq 0 ]]; then
  verdict_fail "stale_image — ${post_oldrev} post-boundary marker(s) carry no guard=${EXPECTED_GUARD} stamp." \
    "      The host is alive and polling, but it is running the PRE-#7761 script. The replace" \
    "      did not deliver the fix: check that BOTH image digest pins in cloud-init-inngest.yml" \
    "      moved to the digest the Phase 8 build produced, and that the flip-asset copy in the" \
    "      bootstrap did not fall through its || true guard. The seam exposure is still live."
fi

# --- 3. flag drift, over the WIDE window with its own narrow grep ------------------------------
# ANY post-boundary flag other than the expected terminal one fails. Enumerating only the three
# flush-path states would let `armed` through — the state whose next poll runs the FLUSHALL.
DRIFT_ROWS="$(mine "$DRIFT_WINDOW" "$TAG")"
case "$DRIFT_ROWS" in
  __QUERY_FAILED__*)
    echo "TRANSIENT: reason=drift_query_failed rc=${DRIFT_ROWS#__QUERY_FAILED__} — the safety half was not measured." >&2
    exit 2 ;;
esac
# #7695 P1 — `armed` IS BOUNDARY-INDEPENDENT AND MUST NOT BE CAPPED.
#
# The derived-boundary cap exists because an INFERRED boundary can misattribute a PRE-replace event
# as post-replace. That reasoning holds for the ABSENCE arms (silence read as "the replace kept the
# old image"). It does NOT hold for `armed`: that is a positively-observed row, and `armed` is never
# a resting state -- it is transient by design, and its next 30s poll stops the server and runs the
# FLUSHALL. So an `armed` row anywhere in DRIFT_WINDOW is an alarm irrespective of when the replace
# happened, which makes it exempt by this file's OWN criterion rather than by carve-out.
#
# WHY THIS MATTERS OPERATIONALLY. scheduled-followthrough-sweeper.yml provisions no Doppler token
# and installs no Doppler CLI, so the uncapped Doppler arm above is inert on every real sweep. If
# `armed` stayed capped, the FLUSHALL alarm would be reachable ONLY on a channel that does not
# exist in CI, while the telemetry channel that always exists reported TRANSIENT.
armed_rows="$(printf '%s\n' "$DRIFT_ROWS" \
  | jq -R -r 'fromjson?
        | select(.flag == "armed")
        | "flag=\(.flag) reason=\(.reason) at=\(.start_ts)"' 2>/dev/null)"
if [[ -n "$armed_rows" ]]; then
  echo "FAIL: reason=cutover_armed — an 'armed' FSM row is present on the LIVE host." >&2
  printf '%s\n' "$armed_rows" | sed 's/^/      /' >&2
  echo "      A cutover is QUEUED: the next 30s poll stops inngest-server and runs FLUSHALL against" >&2
  echo "      the Redis AOF holding user job payloads. Establish who armed it before anything else." >&2
  echo "      This arm is deliberately NOT subject to the derived-boundary cap: 'armed' is never a" >&2
  echo "      resting state, so it is an alarm regardless of when the replace happened." >&2
  exit 1
fi

drift="$(printf '%s\n' "$DRIFT_ROWS" \
  | jq -R -r --arg after "$AFTER" --argjson safe "$TERMINAL_SAFE_FLAGS" \
       'fromjson?
        | select(.start_ts | type == "string" and test("^[0-9]{4}-"))
        | select(.start_ts > $after)
        | select(.flag as $f | $safe | index($f) == null)
        | "flag=\(.flag) reason=\(.reason) at=\(.start_ts)"' 2>/dev/null)"
if [[ -n "$drift" ]]; then
  drift_detail="$(printf '%s\n' "$drift" | sed 's/^/      /')"
  # Herestring, NOT a pipe. This file sets `pipefail`, under which `producer | grep -q` takes
  # SIGPIPE (141) when the match is early enough that the producer is still writing -- failing
  # the pipeline EVEN THOUGH grep matched, and presenting as an unreproducible flake.
  if grep -qE 'flag=(flipping|flushed|done)' <<<"$drift"; then
    verdict_fail "flush_path_transition_after_replace — the latch guarantee is broken." \
      "$drift_detail" \
      "      The host was braked; nothing should have moved off a terminal-safe flag. Treat the" \
      "      Redis contents as suspect and do not re-dispatch."
  else
    verdict_fail "flag_drift_after_replace — the FSM flag moved off the terminal-safe set." \
      "$drift_detail" \
      "      ('armed' is handled above by its own uncapped arm, so this is a non-armed drift.)" \
      "      Establish what moved the flag before re-dispatching anything."
  fi
fi

# --- 4. seam refusals -------------------------------------------------------------------------
# Queried separately: the refusal marker is a RAW string, not emit_state JSON, so every selector
# above discards it by construction. Without this the single most interesting thing this PR can
# emit has no reader at all.
REFUSALS="$(mine "$DRIFT_WINDOW" "$REFUSAL_MARKER")"
case "$REFUSALS" in
  __QUERY_FAILED__*) REFUSALS="" ;;  # already reported by the drift arm; do not double-fail
esac
refusal_count="$(printf '%s\n' "$REFUSALS" | grep -cF "$REFUSAL_MARKER" || true)"
case "$refusal_count" in ''|*[!0-9]*) refusal_count=0 ;; esac
if [[ "$refusal_count" -gt 0 ]]; then
  echo "FAIL: reason=seam_refused count=${refusal_count} — the gate refused a fixture seam on the LIVE host." >&2
  echo "      That means a name in the ${DOPPLER_PROJECT_NAME}/${DOPPLER_CONFIG_NAME} Doppler config" >&2
  echo "      collided with a fixture seam name: the #7761 condition itself, occurring. The gate" >&2
  echo "      held, so nothing was executed — but rename the offending secret before it collides" >&2
  echo "      with a name the gate does not cover." >&2
  exit 1
fi

if [[ "$post_ok" -ge "$MIN_MARKERS" ]]; then
  corroboration="doppler read skipped (no credential in this environment)"
  [[ -n "$doppler_flag" ]] && corroboration="doppler corroborates: ${doppler_flag}"
  echo "PASS: #7761 delivered. ${post_ok} '${EXPECTED_FLAG}' marker(s) after ${AFTER} carrying"
  echo "      guard=${EXPECTED_GUARD} (so the NEW script is on the host, not merely a host that"
  echo "      booted after the timestamp); >= ${MIN_MARKERS}, so the 30s timer is cycling rather"
  echo "      than having booted once; no flag drift; no seam refusal; ${corroboration}."
  exit 0
fi

if [[ "$boundary_age" -gt "$STALE_AFTER_S" ]]; then
  verdict_fail "insufficient_post_replace_markers_past_deadline count=${post_ok}" \
    "      want>=${MIN_MARKERS} after ${AFTER}, and ${stale_note}." \
    "      The flag is correct and nothing flushed, but the host has not been observed POLLING" \
    "      since the replace. At a 30-second cadence that is not 'not yet'."
fi
echo "TRANSIENT: reason=insufficient_post_replace_markers count=${post_ok}" >&2
echo "           want>=${MIN_MARKERS} after ${AFTER} (window ${WINDOW}); ${stale_note}." >&2
echo "           The flag is correct and nothing flushed, but the host has not yet been observed" >&2
echo "           POLLING since the replace. At a 30-second cadence this resolves within minutes." >&2
exit 2
