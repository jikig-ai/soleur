#!/usr/bin/env bash
# Follow-through verification for epic #10390 defect 3 — the inngest host's
# config-refresh tick (OnUnitActiveSec=60s; a sustained identical failure re-emits
# once per 300s window) emitted SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature
# with cosign's stderr swallowed (>/dev/null 2>&1), so the honest reject was
# undebuggable. The fix captures bounded stderr on-host and rides a classified
# detail= token on the row.
#
# WHAT IT VERIFIES, as a conjunction — all VERIFY_FAIL predicates below are
# reason=signature-scoped (a non-signature VERIFY_FAIL is a different defect
# class and never blocks PASS):
#   (a) POSITIVE CONTROL — soleur-inngest still ships SOLEUR_INFRA_PULL_* rows
#       since SOLEUR_FT_EARLIEST (inngest-config-refresh journald → Vector
#       Source 4). Zero = dark channel, never a clean zero.
#   (b) NEW-CODE MARKER — a reason=signature VERIFY_FAIL row carrying detail=
#       can only be emitted by the fixed refresh script; undetailed signature
#       rows post-earliest mean the old binary is still running past the
#       replace window → FAIL.
#   (c) ABSENCE — zero reason=signature VERIFY_FAIL rows since earliest is the
#       soak verdict (AC7). Signature rows that persist WITH detail= mean the
#       channel is alive and rejecting — that is NOT YET (the captured detail
#       names the residual cause for the follow-up fix), never a pass.
#
# Exit semantics (sweep-followthroughs.sh rc→word map):
#   0 = PASS               control >=1 AND zero reason=signature VERIFY_FAIL
#                          rows since earliest
#   1 = FAIL               >=1 reason=signature VERIFY_FAIL row WITHOUT detail=
#                          since earliest
#   2 = NOT YET            signature rows persist (all carry detail=), earliest
#                          in the future, or a transient query error
#   3 = CANNOT ESTABLISH   credentials unset, earliest unset/malformed,
#                          betterstack-query.sh or jq absent, transport rc=3, or
#                          the positive control reads 0 (channel dark / host moved)
#   78 = refused under xtrace with a live credential bound (#7797)
#
# Required env: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} (declared in the
#   directive secrets= clause; already wired in scheduled-followthrough-sweeper.yml),
#   SOLEUR_FT_EARLIEST (the sweeper forwards the directive's earliest=).
#   Test seam: FT10390_QUERY_SH.
#
# ENROLLMENT (an unlabeled directive is invisible to the sweeper):
#   1. gh issue edit 10390 --add-label follow-through
#   2. Post the directive below as a comment at column 0 (outside any fence),
#      substituting earliest=<host-replace timestamp + 24h as an ISO instant> —
#      a literal `<replace+1d>` exits CANNOT ESTABLISH forever.
#
# Directive:
#   <!-- soleur:followthrough script=scripts/followthroughs/inngest-verify-clean-10390.sh earliest=<replace+1d as ISO instant> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
#
# RETIREMENT: when the soak closes, delete this file and remove the directive
# from the tracker comment.
#
# cq-test-fixtures-synthesized-only: no live response is captured into this file.

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac
export LC_ALL=C

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause).\n' "$v" >&2
    exit 3
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="${FT10390_QUERY_SH:-$SCRIPT_DIR/../betterstack-query.sh}"
if [ ! -f "$QUERY" ]; then
  printf 'CANNOT ESTABLISH: betterstack-query.sh not found at %s — instrument absent.\n' "$QUERY" >&2
  exit 3
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'CANNOT ESTABLISH: jq not on PATH — cannot decode the JSONEachRow result.\n' >&2
  exit 3
fi

numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }

# ── EVIDENCE GATE ────────────────────────────────────────────────────────────
EARLIEST_SHAPE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
EARLIEST="${SOLEUR_FT_EARLIEST:-}"
if [[ -z "$EARLIEST" ]]; then
  printf 'CANNOT ESTABLISH: SOLEUR_FT_EARLIEST is unset — no evidence gate. The\n' >&2
  printf '                  directive must carry earliest=<ISO instant after the host replace>.\n' >&2
  exit 3
fi
if ! [[ "$EARLIEST" =~ $EARLIEST_SHAPE ]]; then
  printf 'CANNOT ESTABLISH: SOLEUR_FT_EARLIEST %s is not an ISO instant; refusing to grade.\n' "$EARLIEST" >&2
  exit 3
fi
EARLIEST_EPOCH="$(date -u -d "$EARLIEST" +%s 2>/dev/null)" || EARLIEST_EPOCH=""
if [[ -z "$EARLIEST_EPOCH" ]]; then
  printf 'CANNOT ESTABLISH: SOLEUR_FT_EARLIEST %s does not parse as a date; refusing to grade.\n' "$EARLIEST" >&2
  exit 3
fi
NOW_EPOCH="$(date -u +%s)"
if (( EARLIEST_EPOCH > NOW_EPOCH )); then
  printf 'NOT YET: SOLEUR_FT_EARLIEST (%s) is in the future — no post-replace evidence can exist yet.\n' "$EARLIEST" >&2
  exit 2
fi
SINCE_SQL="$(date -u -d "@$EARLIEST_EPOCH" '+%Y-%m-%d %H:%M:%S')"

SRC="(SELECT dt, raw FROM remote(\$BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)"

# Host scoping mirrors the drift comparator's dual extraction: _HOSTNAME for
# journald rows, host for the phone-home POST path.
HOST_PRED="(JSONExtractString(raw,'_HOSTNAME') = 'soleur-inngest' OR JSONExtractString(raw,'host') = 'soleur-inngest')"
VF="raw LIKE '%SOLEUR_INFRA_PULL_VERIFY_FAIL%'"

run_one() { # $1 = SQL; prints result rows or exits with the query rc
  local out rc
  out="$(bash "$QUERY" "$1" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 3 ]]; then
    printf 'CANNOT ESTABLISH: the transport reports nothing was queried.\n' >&2
    exit 3
  fi
  if [[ "$rc" -ne 0 ]]; then
    printf 'NOT YET: Better Stack query failed (rc=%s): %s\n' "$rc" "${out:0:200}" >&2
    exit 2
  fi
  printf '%s' "$out"
}

SCAN_SQL="SELECT
  countIf(${HOST_PRED} AND raw LIKE '%SOLEUR_INFRA_PULL_%') AS control_rows,
  countIf(${HOST_PRED} AND ${VF}) AS vf_rows,
  countIf(${HOST_PRED} AND ${VF} AND raw LIKE '%detail=%') AS vf_detailed,
  countIf(${HOST_PRED} AND ${VF} AND raw LIKE '%reason=signature%') AS sig_rows,
  countIf(${HOST_PRED} AND ${VF} AND raw LIKE '%reason=signature%' AND raw LIKE '%detail=%') AS sig_detailed
FROM ${SRC}
WHERE dt >= toDateTime('${SINCE_SQL}')
FORMAT JSONEachRow"

# run_one runs inside a command substitution — its `exit N` exits the SUBSHELL,
# not this script, so the verdict rc must be captured and re-raised here.
SCAN_RC=0
SCAN_OUT="$(run_one "$SCAN_SQL")" || SCAN_RC=$?
case "$SCAN_RC" in
  0) ;;
  3) exit 3 ;;
  *) exit 2 ;;
esac
read -r control_rows vf_rows vf_detailed sig_rows sig_detailed <<<"$(printf '%s\n' "$SCAN_OUT" \
  | jq -R -r 'fromjson? | select(type == "object")
  | [.control_rows, .vf_rows, .vf_detailed, .sig_rows, .sig_detailed] | map(tostring) | join("\t")')"

for n in "${control_rows:-}" "${vf_rows:-}" "${vf_detailed:-}" "${sig_rows:-}" "${sig_detailed:-}"; do
  if ! numeric "$n"; then
    printf 'NOT YET: unparseable scan result: %s\n' "${SCAN_OUT:0:300}" >&2
    exit 2
  fi
done

verdict() { # $1 outcome, $2 exit
  echo "SOLEUR_INNGEST_VERIFY_SOAK outcome=$1 control_rows=${control_rows} vf_rows=${vf_rows} vf_detailed=${vf_detailed} sig_rows=${sig_rows} sig_detailed=${sig_detailed} since=${EARLIEST}"
  exit "$2"
}

if [[ "$control_rows" -eq 0 ]]; then
  printf 'CANNOT ESTABLISH: zero SOLEUR_INFRA_PULL_* rows for soleur-inngest since %s — the channel is dark (or the hostname moved); absence would be vacuous.\n' "$EARLIEST" >&2
  verdict cannot_establish 3
fi

# Only the reason=signature arm carries detail= — an undetailed row on any OTHER
# reason (pull, sha, install, …) is legal in both old and new code and must not
# read as "old binary still running". The FAIL discriminator is signature-scoped.
# A numerically-inconsistent payload must not drive sig_undetailed negative
# (negative silently skips FAIL) — clamp, never sign-extend.
sig_undetailed=$(( sig_rows - sig_detailed ))
(( sig_undetailed < 0 )) && sig_undetailed=0
if [[ "$sig_undetailed" -gt 0 ]]; then
  printf 'FAIL: %s reason=signature VERIFY_FAIL row(s) without detail= since %s — the pre-fix refresh script is still running past the replace window.\n' "$sig_undetailed" "$EARLIEST" >&2
  verdict fail 1
fi

# The soak verdict (AC7) is signature-scoped; a transient reason=pull row is
# context, not a soak blocker — otherwise one zot hiccup pins the tracker open.
if [[ "$sig_rows" -gt 0 ]]; then
  printf 'NOT YET: %s reason=signature VERIFY_FAIL row(s) since %s (all carry detail= — the token names the residual cause; the root-cause fix is the follow-up). Other-reason VERIFY_FAIL rows in window: %s.\n' "$sig_rows" "$EARLIEST" "$(( vf_rows - sig_rows ))" >&2
  verdict not_yet 2
fi

printf 'PASS: zero reason=signature VERIFY_FAIL rows for soleur-inngest since %s over a live channel (other-reason rows: %s).\n' "$EARLIEST" "$vf_rows"
verdict pass 0
