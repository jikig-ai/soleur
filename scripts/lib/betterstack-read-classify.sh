#!/usr/bin/env bash
# bs_read_classify — a classification of a failed betterstack-query.sh read (#8178).
#
# Two readers need an answer to "why did this read fail": the inngest cutover's
# `_bs_read_remedy` and the git-data birth/replace boot poll. The boot poll uses the
# whole token set. `_bs_read_remedy` calls it only for the rc=22 BODY partition and keeps
# its own rc arms, so the rc-level split still exists in two places; the body greps, which
# are the part that had already drifted once, exist here only.
#
# ONLY THE CLASSIFICATION IS SHARED, NOT THE PRINTER. The two callers legitimately want
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
#   source-not-in-connection  rc=22  body names CLUSTER_DOESNT_EXIST (#7867)
#   reader-refusal            rc 2/64/78   destination pin / usage / trace
#   transport                 rc 6/7/28/35 DNS / connect / timeout / TLS, and
#                             rc 124/137   the caller's `timeout` expired / killed it
#   other                     anything else
#
# `credentials-absent` and `reader-exit-1` are enumerated rather than folded into
# `other` deliberately: they are the two faults MOST likely to arise from this
# change's own edits, and `other` would make them indistinguishable from a vendor
# anomaly at exactly the moment someone is debugging the wiring.
#
# `source-not-in-connection` is new rather than inherited, and #8178's own history
# demands it. Better Stack answers HTTP 500 `CLUSTER_DOESNT_EXIST` when the SQL API
# CONNECTION does not cover the source. A connection does not cover sources created after
# it (#7867, resolved 2026-09-09), and that is exactly what failed #8178's poll: the
# repository secrets held the 2026-06-01 connection and the git-data source is from
# 2026-09-03. It is a READ-PATH fault, the reader's credential scope, and never a statement
# about the producer. (ADR-192 first read it as "the source has never stored a row"; its
# 2026-09-18 addendum retires that reading.) `--fail-with-body` reports it as the same
# rc=22 as a 401, so without the body grep the two were indistinguishable.

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
    6|7|28|35|124|137) printf '%s\n' 'transport';   return 0 ;;
    2|64|78)    printf '%s\n' 'reader-refusal';     return 0 ;;
    22)         : ;;  # fall through to the body greps below
    *)          printf '%s\n' 'other';              return 0 ;;
  esac

  # rc=22 only. Every grep is guarded so a MISSING rowsfile — the normal state when
  # the read died before writing one — cannot make this return non-zero.
  cls='other'
  grep -qiE 'Authentication failed|Code: 516|password is incorrect' "$rowsfile" 2>/dev/null && cls='credentials-rejected'
  grep -qi 'maintenance' "$rowsfile" 2>/dev/null && cls='source-under-maintenance'
  grep -qi 'CLUSTER_DOESNT_EXIST' "$rowsfile" 2>/dev/null && cls='source-not-in-connection'
  printf '%s\n' "$cls"
  return 0
}

# bs_read_scrub_err1 <errfile>
# The first stderr line of a failed read, safe for a PUBLIC run log: quoted values
# redacted, any `*.betterstackdata.com` host (matched case-insensitively, because curl
# echoes the host exactly as it was given) replaced by <host>, CR/LF removed, and capped
# at 200 characters. Prints `<none>` when there is nothing to print. Returns 0
# unconditionally, for the same reason bs_read_classify does.
bs_read_scrub_err1() {
  local errfile="${1:-}" line
  line="$(head -1 "$errfile" 2>/dev/null | tr -d '\r\n' \
    | sed -E "s/'[^']*'/'<redacted>'/g; s/[A-Za-z0-9.-]*betterstackdata\.com/<host>/gI" \
    | cut -c1-200 || true)"
  printf '%s\n' "${line:-<none>}"
  return 0
}
