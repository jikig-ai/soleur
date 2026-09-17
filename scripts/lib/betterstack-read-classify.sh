#!/usr/bin/env bash
# bs_read_classify — the ONE partition of betterstack-query.sh's rc space (#8178).
#
# Two readers need the same answer to "why did this read fail": the inngest cutover's
# `_bs_read_remedy` and the git-data birth/replace boot poll. Before this file each
# re-derived the partition inline, so the two could drift — and the poll's version
# was the one that had never run, which is how a starved read spent two dispatches
# being diagnosed by hand.
#
# ONLY THE PARTITION IS SHARED, NOT THE PRINTER. The two callers legitimately want
# different forward actions: the cutover's rc=22 arms end "Re-dispatch later", which
# on the birth path is an IMPOSSIBLE remedy — the birth gate refuses a zero-create
# plan for as long as a host exists. So `_bs_read_remedy` keeps its own arms and its
# own name; it calls this for the classification and nothing else.
#
# CONTRACT
#   bs_read_classify <rc> <rowsfile>
#     stdout : exactly one token, one line, from the set below
#     return : 0 UNCONDITIONALLY
#
# The unconditional 0 is load-bearing and is asserted directly by the suite (T14-T16).
# Every caller runs under `set -e`; the natural shape for the last arm here is
# `grep -q … && printf`, which returns non-zero whenever the grep misses — i.e. on
# the COMMON path — and would abort the caller mid-classification. Written as an
# explicit `printf` plus `return 0` so no arm can leak a status.
#
# TOKENS (eight classes, not five)
#   credentials-absent        rc=3   the three query variables were not injected
#   reader-exit-1             rc=1   `doppler run` or the reader exited 1 — names
#                                    DOPPLER_TOKEN, NOT the Better Stack credentials
#   credentials-rejected      rc=22  body names an auth failure
#   source-under-maintenance  rc=22  body names maintenance
#   table-missing             rc=22  body names CLUSTER_DOESNT_EXIST (ADR-192)
#   reader-refusal            rc 2/64/78   destination pin / usage / trace
#   transport                 rc 6/7/28/35 DNS / connect / timeout / TLS
#   other                     anything else
#
# `credentials-absent` and `reader-exit-1` are enumerated rather than folded into
# `other` deliberately: they are the two faults MOST likely to arise from this
# change's own edits, and `other` would make them indistinguishable from a vendor
# anomaly at exactly the moment someone is debugging the wiring.
#
# `table-missing` is new rather than inherited, and #8178's own history demands it.
# ADR-192 records that a Better Stack source which has never STORED a row answers
# HTTP 500 `CLUSTER_DOESNT_EXIST`, and `curl --fail-with-body` reports that as the
# same rc=22 as a 401 — while meaning the opposite: the PRODUCER is at fault, not the
# reader. Conflating them is why the failing run log could not tell "nobody wrote"
# from "we were refused".

# PRECEDENCE IS SEQUENTIAL ASSIGNMENT, PRESERVED EXACTLY FROM THE ORIGINAL.
# The arms below are assignments, not if/elif, so a body carrying BOTH an auth marker
# and a maintenance marker ends as `source-under-maintenance`. That is the behaviour
# `_bs_read_remedy` has shipped, no existing fixture discriminated it, and an
# if/elif rewrite would invert it silently — so the order is pinned here and the
# suite asserts it (T13) rather than trusting the reading.
bs_read_classify() {
  local rc="${1:-}" rowsfile="${2:-}" cls

  case "$rc" in
    3)          printf '%s\n' 'credentials-absent'; return 0 ;;
    1)          printf '%s\n' 'reader-exit-1';      return 0 ;;
    6|7|28|35)  printf '%s\n' 'transport';          return 0 ;;
    2|64|78)    printf '%s\n' 'reader-refusal';     return 0 ;;
    22)         : ;;  # fall through to the body greps below
    *)          printf '%s\n' 'other';              return 0 ;;
  esac

  # rc=22 only. Every grep is guarded so a MISSING rowsfile — the normal state when
  # the read died before writing one — cannot make this return non-zero.
  cls='other'
  grep -qiE 'Authentication failed|Code: 516|password is incorrect' "$rowsfile" 2>/dev/null && cls='credentials-rejected'
  grep -qi 'maintenance' "$rowsfile" 2>/dev/null && cls='source-under-maintenance'
  grep -qi 'CLUSTER_DOESNT_EXIST' "$rowsfile" 2>/dev/null && cls='table-missing'
  printf '%s\n' "$cls"
  return 0
}
