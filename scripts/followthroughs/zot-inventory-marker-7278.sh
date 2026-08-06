#!/usr/bin/env bash
# #7278 / ADR-171 — post-merge soak for the read-only zot disk-inventory lever.
#
# TRACKER: **#7339** (dedicated). NOT #7278 — that issue is closed by the shipping PR and the
# sweeper lists `--state open`, whose reopen path fires only on exit 1, so a correct exit-2 probe
# hosted there would be a permanent silent no-op. NOT #7247 either — a live P1 that will close
# when the incident does and take the tracker with it.
#
# WHAT IT CLOSES. ADR-171 ships at status `adopting`. Its flip condition is a REAL dispatch
# producing an OBSERVED `SOLEUR_ZOT_INVENTORY` line with `enumeration_complete=true`. That
# cannot happen before merge (the workflow does not exist on a runner until it lands), and the
# open sub-question it answers — H6, whether a GitHub runner's egress actually reaches
# `s2457081.eu-fsn-3.betterstackdata.com` against the region pin — was measured only from a
# workstation (POST -> 202, POST->queryable 17 s). A workstation 202 is not a runner 202.
#
# DISPATCH-GATED, NOT DATE-GATED. `earliest=` is a floor on when this probe first RUNS; it is
# never the condition. The condition is the observed marker. Set `earliest=` to the filing date
# per followthrough-convention.md (a far-future `earliest=` double-gates and only delays the
# answer).
#
# EXIT CONTRACT (scripts/sweep-followthroughs.sh) — DELIBERATELY THREE-WAY, AND 1 IS UNUSED:
#   0 = PASS       a marker line for this lever was observed AND enumeration_complete=true
#   2 = TRANSIENT  not yet dispatched, not yet observed, OR ANY auth/query/decode failure
#   1 = FAIL       *** NEVER EMITTED BY THIS PROBE ***
#
# WHY 1 IS NEVER EMITTED. `exit 1` in this contract means "this should NOT close" — a genuine
# regression. There is no regression shape here: the lever either has been dispatched and
# observed, or it has not been yet. "Not yet" is a not-yet, and a FAIL posts a comment on every
# sweep, forever, on a tracker whose condition is simply pending. Every failure path below is
# therefore an explicit `exit 2`.
#
# THE `${VAR:?msg}` FORM IS BANNED HERE (#6757), and the ban is mechanical, not stylistic:
# under the sweeper's non-interactive shell that word-expansion aborts with status **1**, which
# this contract reads as FAIL — so an unprovisioned secret would post a daily false-FAIL forever
# instead of retrying quietly. `scripts/lint-followthrough-varq-ban.sh` reddens CI on it. Use
# `if [[ -z "${VAR:-}" ]]; then ... exit 2; fi`, which is what every guard below does.
#
# ARCHIVE ARM ON, `--since 7d` — BOTH HALVES ARE LOAD-BEARING.
#   * The archive arm: `betterstack-query.sh` defaults to hot+archive and `--no-archive` opts
#     out to the ~40-minute hot window. The inventory workflow's OWN round-trip gate uses
#     `--no-archive --since 15m` because it is grading a seconds-old row and the S3 arm can only
#     contribute failure there. THIS probe is the opposite case: it grades a dispatch that may be
#     days old, which lives in the archive. Do not copy the workflow's flags here.
#   * `--since 7d`: the script's own default is `SINCE="1h"`. A 1-hour window could never observe
#     a dispatch from a previous day, so the probe would return TRANSIENT forever while the
#     evidence sat in the warehouse. 7d is set explicitly for that reason.
#
# THE DISCRIMINATOR, AND WHY IT IS NOT THE CONVENTIONAL ONE.
# The house rule for log-derived probes is to field-isolate on `SYSLOG_IDENTIFIER` parsed out of
# the JSON `raw` column, never a bare substring (#6475: a bare grep matches a CI job that merely
# PRINTED the marker name). That isolation is STRUCTURALLY UNAVAILABLE here: a direct CI POST to
# the Logs ingest endpoint never passes through journald or Vector, so the row carries no
# `SYSLOG_IDENTIFIER` at all. Requiring one would reject every genuine row.
#
# The substitute is a PREFIX ANCHOR plus a TYPE CONSTRAINT, applied to the DECODED `.message`:
#   (i)  the message must START WITH the literal `SOLEUR_ZOT_INVENTORY run_id=`, and
#   (ii) the run_id must be NUMERIC.
# The contamination this defends against is concrete: this plan, this ADR, the tracker body and
# the PR description all contain the string `SOLEUR_ZOT_INVENTORY` as prose, and GitHub webhook
# traffic is ingested into the same estate. A prose mention cannot satisfy a prefix-anchored
# match — the token never sits at offset 0 followed by ` run_id=` — and cannot supply a numeric
# GitHub run id. A bare `--grep SOLEUR_ZOT_INVENTORY` would match every one of them and
# auto-close this tracker on an echo of its own text.
#
# DECODE BEFORE MATCHING (BLOCKING, ADR-171 §2). `betterstack-query.sh` emits JSONEachRow whose
# `raw` column is itself a JSON *string* — i.e. double-encoded. A grep against the raw stream
# "silently returns nothing": a probe that can never PASS, which is indistinguishable from a
# probe that is correctly reporting a not-yet. Both jq hops below are required.
#
# ZERO ROWS IS AMBIGUOUS AND THE POSITIVE CONTROL SAYS WHICH KIND. `SOLEUR_ZOT_DISK` lands on the
# same source every 5 minutes, so any window measured in days holds hundreds of control rows. If
# the control is ALSO empty, the read path is dark and this probe has measured nothing at all —
# reported as `channel_dark`, never as "the marker is absent". Both are exit 2, so the control
# changes no verdict; it changes what the comment tells the next reader, which is the difference
# between "re-dispatch the lever" and "the query path is broken".
#
# Required env (LITERAL names — the sweeper runs probes under `env -i` with PATH + HOME + the
# directive-declared `secrets=` ONLY; all three are already wired into
# .github/workflows/scheduled-followthrough-sweeper.yml):
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
MARKER="SOLEUR_ZOT_INVENTORY"
CONTROL_MARKER="SOLEUR_ZOT_DISK"
WINDOW="${ZOT_INVENTORY_7278_WINDOW:-7d}"
LIMIT="${ZOT_INVENTORY_7278_LIMIT:-200}"

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is unset — cannot query the Logs warehouse. This is a provisioning" >&2
    echo "           gap in the sweeper env, not evidence about the lever." >&2
    exit 2
  fi
done

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY is missing or not executable." >&2
  exit 2
fi

# --- decode helper: JSONEachRow -> .raw (a JSON *string*) -> .message ------------------------
# Two hops, both with `fromjson?` so a non-JSON noise line is skipped rather than aborting the
# stream. `// empty` drops rows with no such field instead of emitting a literal "null".
decode_messages() {
  jq -R -r 'fromjson? | .raw // empty' 2>/dev/null \
    | jq -R -r 'fromjson? | .message // empty' 2>/dev/null
}

# --- the marker query ------------------------------------------------------------------------
# Archive arm ON (no --no-archive): a days-old dispatch lives in S3, not the hot window.
raw=$("$QUERY" --since "$WINDOW" --limit "$LIMIT" --grep "$MARKER" 2>/dev/null)
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "TRANSIENT: betterstack-query.sh exited $rc querying $MARKER over $WINDOW" >&2
  echo "           (network, credentials, or the archive arm). No claim is made about the" >&2
  echo "           lever — a failed query is not an absence." >&2
  exit 2
fi

decoded=$(printf '%s\n' "$raw" | decode_messages)

# PREFIX-ANCHORED, NUMERIC run_id. `grep -E '^...'` anchors at offset 0, which is what a prose
# mention of the marker in an issue body or PR description can never satisfy.
hits=$(printf '%s\n' "$decoded" | grep -E "^${MARKER} run_id=[0-9]+ " || true)
n_hits=$(printf '%s\n' "$hits" | grep -c . || true)
[[ "$n_hits" =~ ^[0-9]+$ ]] || n_hits=0

if [[ "$n_hits" -eq 0 ]]; then
  # --- positive control: is the READ PATH alive at all? --------------------------------------
  # Same source, same credentials, same window. SOLEUR_ZOT_DISK lands every 5 minutes.
  control_raw=$("$QUERY" --since "$WINDOW" --limit 5 --grep "$CONTROL_MARKER" 2>/dev/null) || control_raw=""
  n_control=$(printf '%s\n' "$control_raw" | decode_messages | grep -c . || true)
  [[ "$n_control" =~ ^[0-9]+$ ]] || n_control=0

  if [[ "$n_control" -eq 0 ]]; then
    echo "TRANSIENT: channel_dark — zero ${MARKER} rows AND zero ${CONTROL_MARKER} control rows" >&2
    echo "           in the last ${WINDOW}. ${CONTROL_MARKER} lands on this source every 5 min, so an" >&2
    echo "           empty control means the READ PATH is not answering. This probe has" >&2
    echo "           measured NOTHING about the lever — do not read it as 'the marker is" >&2
    echo "           absent'. Next: check the Better Stack query credentials and the archive" >&2
    echo "           arm before re-dispatching anything." >&2
    exit 2
  fi

  echo "TRANSIENT: marker_not_yet_observed — zero ${MARKER} rows in the last ${WINDOW}, but the" >&2
  echo "           read path IS alive (${n_control} ${CONTROL_MARKER} control row(s)), so this is a" >&2
  echo "           measured absence rather than a dark channel." >&2
  echo "           Next: dispatch the lever — 'gh workflow run registry-zot-inventory.yml'." >&2
  echo "           If a dispatch DID run and still nothing landed here, read that run's" >&2
  echo "           reason=ingest_rejected_http_<code>: that is where H6 (runner egress to the" >&2
  echo "           eu-fsn-3 ingest pin) is answered, and it is the evidence that would select" >&2
  echo "           the Sentry-mirror fallback." >&2
  exit 2
fi

# --- a marker exists; it PASSes only if the sweep was COMPLETE --------------------------------
# An incomplete sweep is not a partial success to be rounded up. `enumeration_complete=false`
# licenses NO conclusion at all (ADR-171): the delta it reports is indistinguishable from the
# finding, so closing this tracker on it would flip ADR-171 to `accepted` on a number nobody may
# read. Not-complete is a not-yet.
complete_hits=$(printf '%s\n' "$hits" | grep -F 'enumeration_complete=true' || true)
n_complete=$(printf '%s\n' "$complete_hits" | grep -c . || true)
[[ "$n_complete" =~ ^[0-9]+$ ]] || n_complete=0

if [[ "$n_complete" -eq 0 ]]; then
  echo "TRANSIENT: ${n_hits} ${MARKER} row(s) observed in the last ${WINDOW}, but NONE carries" >&2
  echo "           enumeration_complete=true. The round trip works — ingest, region pin and" >&2
  echo "           readback are all proven by these rows, so H6 is answered YES — but an" >&2
  echo "           incomplete sweep licenses no conclusion about delta_gb, and ADR-171's flip" >&2
  echo "           condition is a COMPLETE one." >&2
  echo "           Next: re-dispatch. Read manifest_errors / tag_list_errors / catalog_errors on" >&2
  echo "           the rows below — a crash-looping origin interrupting the sweep is the" >&2
  echo "           measured cause of the prototype's 12 manifest errors." >&2
  printf '%s\n' "$hits" | tail -3 | sed 's/^/        /' >&2
  exit 2
fi

echo "PASS: ${n_complete} of ${n_hits} ${MARKER} row(s) in the last ${WINDOW} carry"
echo "      enumeration_complete=true, prefix-anchored at offset 0 with a numeric run_id."
echo "      This is a READBACK, not the emitter's self-report: the row was read out of the"
echo "      warehouse through the ClickHouse path, which the emitter's exit code cannot fake."
echo "      It also answers H6 affirmatively — a GitHub runner's egress DOES reach the"
echo "      eu-fsn-3 ingest pin — so the Sentry-mirror fallback is not needed."
echo "      ADR-171 may now flip adopting -> accepted."
printf '%s\n' "$complete_hits" | tail -3 | sed 's/^/        /'
exit 0
