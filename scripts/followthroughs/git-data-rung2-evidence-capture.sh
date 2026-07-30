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
# gated on `BETTERSTACK_LOGS_TOKEN` being in the environment, which happens only under
# `doppler run` — so on a SUCCESSFUL boot the only row this source ever receives from a
# git-data host is `boot_complete` itself. An anchor that is a strict prerequisite of the
# thing it is anchoring is not an anchor; it would have returned zero rows on a perfect
# rehearsal, forever, and the failure would have read as "dark boot".
#
# So the anchor asks a different question: IS THIS SOURCE ANSWERING AT ALL? One query for any
# row from any host in the window. If the source is live and this host said nothing, the
# silence is about the host. If the source is dead, the silence is about the instrument and
# this script has no verdict to offer. That distinction is the entire point, and the arms in
# tests/scripts/test-git-data-rung2-evidence-capture.sh pin both directions.
#
# WHAT THIS DOES NOT CLAIM, stated because a gate believed to cover more than it does is worse
# than one whose scope is written down:
#   - It does not verify the SENTRY channel independently. Sentry has no search capability
#     wired in this repo (scripts/sentry-issue.sh needs an issue id, and the `event:read`
#     scope lives in a token this route does not carry). The fatal channel is proven at RUNG 1
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
VERIFY_ONLY=0
DIVERGENCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-name)    HOST_NAME="${2:-}"; shift 2 ;;
    --evidence-url) EVIDENCE_URL="${2:-}"; shift 2 ;;
    --cloud-init)   CLOUD_INIT="${2:-}"; shift 2 ;;
    --out)          OUT="${2:-}"; shift 2 ;;
    --window)       WINDOW="${2:-}"; shift 2 ;;
    --divergence)   DIVERGENCE="${2:?--divergence needs a value}"; shift 2 ;;
    --verify-only)  VERIFY_ONLY=1; shift ;;
    --) shift ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

[[ -z "$OUT" ]] && OUT="$(dirname "$CLOUD_INIT")/git-data-rung2-boot-evidence.env"

if [[ -z "$HOST_NAME" ]]; then
  echo "usage: git-data-rung2-evidence-capture.sh --host-name <name> --evidence-url <url> [--out <path>]" >&2
  exit 64
fi

# THE HOST NAME IS INTERPOLATED INTO SQL, so it is validated rather than trusted. It reaches
# the WHERE clause of every query below; a name carrying a quote would either break the query
# or change which rows it selects, and "which rows" is the whole verdict.
if [[ ! "$HOST_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "refusing: --host-name must match ^[A-Za-z0-9._-]+$ (it is interpolated into the Better Stack SQL). Got: ${HOST_NAME}" >&2
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

# THE PREFLIGHT IS WHAT SEPARATES "I QUERIED AND SAW NOTHING" FROM "I NEVER QUERIED". Without
# it, a missing credential produces silence that is indistinguishable from a dark boot.
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: ${v} is unset — cannot query Better Stack Logs, so this run has no verdict to offer (it is NOT evidence that the host booted dark). Re-run wrapped in: doppler run -p soleur -c prd_terraform -- ..."
    exit 2
  fi
done
[[ -x "$QUERY" || -r "$QUERY" ]] || { echo "TRANSIENT: ${QUERY} not found"; exit 2; }

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

HOST_SQL="
  SELECT /* __HOSTROWS__ every stage this rehearsal host reported */
         dt,
         JSONExtractString(raw,'stage')         AS stage,
         JSONExtractString(raw,'level')         AS level,
         JSONExtractString(raw,'host_name')     AS host,
         JSONExtractString(raw,'luks_mounted')  AS luks_mounted,
         JSONExtractString(raw,'repo_root')     AS repo_root,
         JSONExtractString(raw,'hooks_path')    AS hooks_path,
         JSONExtractString(raw,'provision')     AS provision
  FROM ${_bs_source}
  WHERE dt > now() - INTERVAL ${WINDOW}
    AND JSONExtractString(raw,'host_name') = '${HOST_NAME}'
  ORDER BY dt DESC LIMIT 50 FORMAT JSONEachRow"

_run_query() {  # $1 = sql ; prints rows, returns the transport's rc
  bash "$QUERY" "$1" 2>&1
}

# ── ARTIFACT 1: the source-liveness anchor ────────────────────────────────────────
anchor_out="$(_run_query "$ANCHOR_SQL")"; anchor_rc=$?
if [[ "$anchor_rc" -ne 0 ]]; then
  echo "TRANSIENT: the Better Stack query transport exited ${anchor_rc} (unreachable or unauthorised). No verdict — this says nothing about the rehearsal host."
  printf '%s\n' "$anchor_out" | tail -5
  exit 2
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
if ! grep -qE '"host":"[^"]+"' <<<"$anchor_out"; then
  echo "TRANSIENT: the source-liveness anchor returned ZERO rows from ANY other host in the last ${WINDOW}."
  echo "That is a statement about the INSTRUMENT, not about ${HOST_NAME}: a live source with a"
  echo "silent host and a dead source look identical from this host's rows alone, so this run"
  echo "declines to read silence as a dark boot. Check the Better Stack source and credentials."
  exit 2
fi

# ── ARTIFACT 2: everything this host reported ─────────────────────────────────────
host_out="$(_run_query "$HOST_SQL")"; host_rc=$?
if [[ "$host_rc" -ne 0 ]]; then
  echo "TRANSIENT: the host-rows query exited ${host_rc} after the anchor succeeded. No verdict."
  printf '%s\n' "$host_out" | tail -5
  exit 2
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
if grep -q '"level":"fatal"' <<<"$host_out"; then
  echo "FAIL: ${HOST_NAME} reported a FATAL. The rehearsal found the failure class this route exists to catch — a boot that would have looked green from the apply."
  grep '"level":"fatal"' <<<"$host_out" | head -10
  echo
  echo "NO EVIDENCE FILE WRITTEN. Fix the cause, then re-run the rehearsal against the corrected template."
  exit 1
fi

if ! grep -q 'boot_complete' <<<"$host_out"; then
  echo "TRANSIENT: the source is live (the anchor answered) but ${HOST_NAME} has not reported"
  echo "stage:boot_complete within ${WINDOW}, and reported no fatal either. Either the boot is"
  echo "still in progress, or it died before reaching a stage that can emit to Better Stack at"
  echo "all — everything before \`doppler run\` reaches SENTRY ONLY, because the emitter's"
  echo "Better Stack block is gated on BETTERSTACK_LOGS_TOKEN being in the environment."
  echo "Check Sentry for this host_name before concluding anything."
  exit 2
fi

_bc_rows="$(grep 'boot_complete' <<<"$host_out" || true)"
if grep -qE '"(luks_mounted|repo_root|hooks_path|provision)":"no"' <<<"$_bc_rows"; then
  echo "FAIL: ${HOST_NAME} reported boot_complete with a FALSE assertion — it reached its final stage with an invariant unmet, which is the dark boot the interlock exists to catch."
  printf '%s\n' "$_bc_rows" | head -5
  echo
  echo "NO EVIDENCE FILE WRITTEN."
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
if ! TEMPLATE_SHA="$(git_data_rung2_user_data_sha256 "$CLOUD_INIT")"; then
  echo "TRANSIENT: could not derive the user_data hash, so there is nothing to bind evidence to."
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
  printf '#\n'
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
echo "PASS: ${HOST_NAME} reported stage:boot_complete and no level:fatal. NOTE: boot_complete's four booleans are hardcoded literals in git-data-bootstrap.sh, so this attests that the final stage was REACHED and that nothing reported a fatal — not that four invariants were independently measured."
echo "Evidence written to ${OUT} (user_data sha256 ${TEMPLATE_SHA})."
echo
echo "This file is NOT committed by this script and must NOT be committed by a workflow."
echo "Merging it is the second of the two intentional human gates on the git-data birth."
exit 0
