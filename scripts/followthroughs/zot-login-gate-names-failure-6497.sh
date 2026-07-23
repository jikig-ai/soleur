#!/usr/bin/env bash
# Follow-through verification for #6497 (post-deploy confirmation of PR #6528).
#
# PR #6528 does not repair the login failure — it buys the datum. Its close
# criterion (AC13) is therefore a POST-DEPLOY SOAK, not a merge-time assertion:
# the gate must self-report on the next real deploy.
#
# THE INVARIANT (AC13): every docker-login outcome the gate emits must fall into
# exactly ONE of three named states. `unclassified` with no hatch fields is the
# dead-end this PR exists to drain, and is the only genuine FAIL.
#
#   (a) success           — `ZOT_GATE: active …` / `PRELUDE: … ok`
#                           NO class= and NO rc= (the gate had no failure to name)
#   (b) no login attempted — a bounded, named non-login state:
#                           zot  → `reason=probe_unreachable` / `reason=creds_absent`
#                           ghcr → `PRELUDE: … skipping …` (carries NO reason= field:
#                                  reason= is emitted only by zot_gate_degraded_event,
#                                  which is zot-only — GHCR is journald-only by decision)
#   (c) login failed      — carries rc= AND class= AND stderr_chars= AND stdout_chars=
#                           On class=unclassified, tok= must be populated. `kw=` may be
#                           EMPTY and that is CORRECT — kw is empty exactly on the novel
#                           shape the hatch exists to capture; an empty kw IS the H-D
#                           datum ("matched no known keyword"). Do NOT assert kw non-empty.
#
# Only (c) is the invariant under test. (a) and (b) are "the gate had no login outcome
# to name", which is itself a bounded, named state.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (every failed-login line carries the hatch; sweeper closes #6497)
#   1 = FAIL       (≥1 failed-login line lacks rc=/class=/*_chars= — the dead-end persists)
#   * = TRANSIENT  (Better Stack unreachable/auth failure, or NO login lines in the window
#                   — absence of data is NOT proof of success; retry next sweep)
#
# Required env: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}
#   (wired in scheduled-followthrough-sweeper.yml; mirrors Doppler soleur/prd_terraform)
#
# WHY the window is 90m and not 60m: at 6-12 deploys/day the mean inter-deploy gap is
# 2-4h, so a 60m window legitimately returns zero rows and would be misread as failure.
# 90m matches the AC13 probe verbatim. Zero rows is TRANSIENT here, never PASS — a
# no-data window is the silent-success trap this whole PR is about.

set -uo pipefail

if [[ -z "${BETTERSTACK_QUERY_HOST:-}" ]]; then echo "TRANSIENT: BETTERSTACK_QUERY_HOST not set" >&2; exit 2; fi
if [[ -z "${BETTERSTACK_QUERY_USERNAME:-}" ]]; then echo "TRANSIENT: BETTERSTACK_QUERY_USERNAME not set" >&2; exit 2; fi
if [[ -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then echo "TRANSIENT: BETTERSTACK_QUERY_PASSWORD not set" >&2; exit 2; fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '.')"
QUERY="${REPO_ROOT}/scripts/betterstack-query.sh"

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: ${QUERY} not found or not executable" >&2
  exit 2
fi

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT INT TERM

# --since 90m parses the script's own ^([0-9]+)([hmd])$ regex; --grep is repeatable and
# OR-combined, so this sees BOTH the ZOT_GATE and the PRELUDE halves. (The plan's first
# draft used a bare `--since 60`, which fails that regex and silently degrades to
# WHERE dt >= '60' — the probe did not run at all. Verified parsing before shipping.)
if ! bash "$QUERY" --since 90m --grep ZOT_GATE --grep PRELUDE > "$OUT" 2>&1; then
  echo "TRANSIENT: betterstack-query.sh failed:" >&2
  tail -5 "$OUT" >&2
  exit 2
fi

# Only FAILED-login lines carry the AC13 (c) obligation. Success lines and named
# non-login states are states (a)/(b) and are excluded by construction.
FAILED_LINES="$(grep -E 'ZOT_GATE: docker login .* FAILED|PRELUDE: docker login .* FAILED' "$OUT" || true)"

# Any login lines at all? Absence of data proves nothing (no deploy in the window).
ANY_LINES="$(grep -cE 'ZOT_GATE|PRELUDE' "$OUT" || true)"
if [[ "${ANY_LINES:-0}" -eq 0 ]]; then
  echo "TRANSIENT: no ZOT_GATE/PRELUDE lines in the last 90m — no deploy in the window." >&2
  echo "           Absence of data is not proof the gate self-reports. Retrying next sweep." >&2
  exit 2
fi

# #6565 errno round — REPORTING ONLY, and it must run on BOTH PASS paths.
#
# WHY A FUNCTION AND NOT AN ECHO AT THE END: this probe is SINGLE-SHOT (it PASSes, comments, the
# sweeper auto-resolves the tracker, it never runs again) and it has TWO exit-0 paths — the
# zero-FAILED branch below, and the all-lines-carry-the-hatch path at the bottom. The errno round's
# deliverable was originally reported only on the second. If the first sweep after `earliest` landed
# on an all-success 90m window, the probe would PASS through the FIRST path, close, and the round's
# entire deliverable would be foreclosed PERMANENTLY — a later resumed failure never read by anyone.
# Both paths report; neither asserts. Reporting-only by construction: no `exit`, no assignment the
# verdict reads, both fields closed-vocabulary/integers (`ci-deploy.sh` › `_login_kw`,`_login_hatch`).
#
# On the zero-FAILED path the fields are EMPTY, and that is itself the datum the plan's verdict rule
# calls "premise (A) FALSIFIED" — the continuous cred-store failure stopped on its own, which is a
# MAJOR finding and the one branch most likely to be misread as ordinary success.
_report_errno_round() {
  # $1 = the lines to read (may be empty), $2 = a one-line context label.
  local _kw _ec
  _kw="$(printf '%s\n' "${1:-}" | grep -oE 'kw=[a-z,]*' | sort -u | tr '\n' ' ')"
  _ec="$(printf '%s\n' "${1:-}" | grep -oE 'errno_chars=[0-9]+' | sort -u | tr '\n' ' ')"
  echo "Observed kw (the errno round's deliverable — record on #6565; ${2}). An EMPTY kw value is" \
       "itself the datum: the errno matched none of the probed literals:" "${_kw:-<none>}"
  echo "Observed errno_chars (bounds the errno set in ONE round; 22 == 'cannot allocate memory'," \
       "and is INVARIANT under docker's uint32 temp suffix, unlike stderr_chars — record on #6565):" \
       "${_ec:-<none>}"
  # *** READ THIS BEFORE INTERPRETING AN EMPTY errno_chars — the two empties are NOT the same. ***
  # `errno_chars` is a #6565 field. The code that emits it lands on web-1 and then SITS: the
  # redeploy step is seccomp-conditional, so a `ci-deploy.sh`-only merge does not itself deploy
  # (plan AC8). Until an independent release runs, the gate still emits the PRE-#6565 line shape —
  # which has no `errno_chars` AT ALL and probes ten literals, not sixteen.
  # So: `errno_chars=<none>` while FAILED lines EXIST means "the deployed code predates the errno
  # round; the datum does not exist yet" — NOT "the errno has no length" and NOT "the round ran and
  # found nothing". Conflating those reads a not-yet-deployed instrument as a negative result, which
  # is the single most likely way this round gets misfiled as finished.
  if [[ -n "${1:-}" && -z "$_ec" ]]; then
    echo "  ^^ errno_chars ABSENT on lines that DO exist ⇒ web-1 is still running PRE-#6565 code." \
         "The errno round has NOT reported yet. Do not read this as a negative result; re-read after" \
         "the next independent web-platform release (this probe is single-shot, so record on #6565 now)."
  fi
}

if [[ -z "$FAILED_LINES" ]]; then
  # Login lines exist and none of them FAILED → every outcome is state (a)/(b).
  # The gate had no failure to name. AC13 holds.
  echo "PASS: ${ANY_LINES} login line(s) in the last 90m, zero FAILED — every outcome is a" \
       "named success / non-login state (AC13 states (a)/(b))."
  echo "MAJOR — read this before treating the PASS as routine: zero FAILED means the CONTINUOUS" \
       "cred-store failure measured on both registries 2026-07-15 has STOPPED ON ITS OWN. That is" \
       "the plan's 'premise (A) FALSIFIED' branch, not ordinary success: the errno question is now" \
       "unanswerable from telemetry and the diagnosis must be re-opened, not considered settled."
  _report_errno_round "" "zero FAILED lines in the window, so there is no kw to observe"
  exit 0
fi

# Each FAILED line MUST carry the full hatch. A line missing any field is the
# class=unclassified http=none dead-end this PR exists to drain.
BAD=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  miss=""
  printf '%s' "$line" | grep -q 'rc='            || miss="${miss}rc "
  printf '%s' "$line" | grep -q 'class='         || miss="${miss}class "
  printf '%s' "$line" | grep -q 'stderr_chars='  || miss="${miss}stderr_chars "
  printf '%s' "$line" | grep -q 'stdout_chars='  || miss="${miss}stdout_chars "
  # tok= must populate on unclassified. kw= is deliberately NOT asserted (see header).
  if printf '%s' "$line" | grep -q 'class=unclassified'; then
    printf '%s' "$line" | grep -qE 'tok=[A-Za-z]' || miss="${miss}tok(on-unclassified) "
  fi
  [[ -n "$miss" ]] && BAD="${BAD}
  missing[ ${miss}]: ${line}"
done <<< "$FAILED_LINES"

if [[ -n "$BAD" ]]; then
  echo "FAIL: a failed-login line does not name its own failure — AC13 state (c) unmet." >&2
  echo "      The gate is still dead-ending. Do NOT close #6497.${BAD}" >&2
  exit 1
fi

N="$(printf '%s\n' "$FAILED_LINES" | grep -c . || true)"
echo "PASS: all ${N} failed-login line(s) carry rc + class + stderr_chars + stdout_chars" \
     "(and tok on unclassified). The gate names its own failure — AC13 state (c) holds."
echo "Observed classes: $(printf '%s\n' "$FAILED_LINES" | grep -oE 'class=[a-z_]+' | sort -u | tr '\n' ' ')"
echo "Observed docker_ver (first read of the unpinned host version — record on #6565):" \
     "$(printf '%s\n' "$FAILED_LINES" | grep -oE 'docker_ver=[0-9.a-z]+' | sort -u | tr '\n' ' ')"
# #6565 errno round — REPORTING ONLY, and load-bearing precisely because of that.
#
# WHY THIS LINE EXISTS: this probe is SINGLE-SHOT. It PASSes on the already-measured datum,
# comments, the sweeper auto-resolves issue 6497, and it NEVER RUNS AGAIN. It is also the ONLY
# automated reader of these lines. So without this echo the errno round's entire deliverable —
# the one field the round was built to buy — has no automated reader, ever. One line, the same
# shape as the docker_ver line directly above, which is already a datum-reporting channel.
#
# It CANNOT flip the verdict: it sits after the last `exit 1`, asserts nothing, and both fields
# are closed-vocabulary/integers by construction (`ci-deploy.sh` › `_login_kw`, `_login_hatch`).
# `kw=` may legitimately be EMPTY — that IS the H-D datum ("matched no known keyword"), so this
# reports it and does not assert it (see this file's header: "Do NOT assert kw non-empty").
echo "Observed kw (the errno round's deliverable — record on #6565; EMPTY kw is itself the datum," \
     "meaning the errno matched none of the probed literals):" \
     "$(printf '%s\n' "$FAILED_LINES" | grep -oE 'kw=[a-z,]*' | sort -u | tr '\n' ' ')"
echo "Observed errno_chars (bounds the errno set in ONE round; 22 == 'cannot allocate memory'," \
     "and is INVARIANT under docker's uint32 temp suffix, unlike stderr_chars — record on #6565):" \
     "$(printf '%s\n' "$FAILED_LINES" | grep -oE 'errno_chars=[0-9]+' | sort -u | tr '\n' ' ')"
exit 0
