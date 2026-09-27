#!/usr/bin/env bash
# inngest-probe-row.sh — the ONE definition of "a dedicated-host inngest probe row" (#8846).
#
# A probe row is a journald row whose emitter (SYSLOG_IDENTIFIER) is the probe's own logger
# tag AND whose message BEGINS with the probe marker followed by a space. Both clauses are
# load-bearing:
#
#   - emitter: the inngest server's own event log is shipped under SYSLOG_IDENTIFIER=doppler on
#     the SAME host, and it quotes the marker whenever a GitHub issue/PR/comment about the probe
#     is webhooked in. A substring match read those rows as probe rows, so a healthy host
#     graded probe-unavailable and filed P1 pairs every hour (#8833/#8834 and siblings).
#   - anchor: a probe-emitter line that does not start with the marker is not a probe reading.
#
# Host isolation (host + host_name) is the CALLER's job — this predicate says nothing about which
# host a row came from.
#
# LOAD CONTRACT (every consumer; the census in inngest-probe-row.test.sh enforces the three
# marked [census] lines on every direct consumer, and fails CI on a reader that does not source
# this file at all). Load it EXACTLY like this, adapting only the failure arm:
#
#     unset INNGEST_PROBE_ROW_JQ INNGEST_PROBE_EMITTER INNGEST_PROBE_MARKER          [census]
#     _ipr_lib="${INNGEST_PROBE_ROW_LIB:-<path from THIS script's own location>}"   [census]
#     # shellcheck source=scripts/lib/inngest-probe-row.sh
#     if ! source "$_ipr_lib" || ! declare -F inngest_probe_row_selftest >/dev/null \
#        || ! inngest_probe_row_selftest; then                                       [census]
#       <selector_unavailable arm naming lib=$_ipr_lib>
#     fi
#
#   - `unset` BEFORE the source: the three names can arrive inherited (Doppler keys are exported
#     into $GITHUB_ENV by .github/actions/infra-credentials). A source that fails, or that loads a
#     file defining nothing (INNGEST_PROBE_ROW_LIB=/dev/null), must never leave an inherited —
#     possibly permissive — def in force.
#   - INNGEST_PROBE_ROW_LIB is the test-sandbox override (suites run a COPY of the consumer from a
#     temp dir). The default resolves from the consumer's own location (BASH_SOURCE /
#     $GITHUB_WORKSPACE), never from $PWD.
#   - The selftest after the source proves the loaded def compiles AND rejects the event-log
#     shapes; a lib that loads but defines nothing, or a permissive def, is selector_unavailable.
#   - Do NOT send the source's stderr to /dev/null: a missing file and a syntax error in this lib
#     must stay distinguishable in the log.
#   - Use "$INNGEST_PROBE_ROW_JQ" or "${INNGEST_PROBE_ROW_JQ:?}" (never a `:-` default) as the prefix of the jq program, then
#     `select(inngest_probe_row)` (or `select($row | inngest_probe_row)`) on the DECODED row
#     object, on one line with no jq `#` comment before the def name. Never redefine the def
#     locally (a later `def inngest_probe_row:` shadows this one).
#   - Capture jq's exit code before any `|| true`.
#   - Python consumers do the same bash-side load, then pass INNGEST_PROBE_EMITTER and
#     INNGEST_PROBE_MARKER to python through the environment and read
#     os.environ["INNGEST_PROBE_EMITTER"] / os.environ["INNGEST_PROBE_MARKER"].
#   - Name the marker as "$INNGEST_PROBE_MARKER" in --grep terms and messages after the source.
#
# FAILURE VOCABULARY (one pair, in every consumer). Each consumer keeps its own verdict CLASS
# (TRANSIENT exit 2, CANNOT ESTABLISH exit 3, exit 6, crash_reason=, unreadable, ...) but spells
# the reason with exactly these tokens:
#   - `selector_unavailable lib=<path>` — this file could not be sourced, defined nothing, or
#     failed inngest_probe_row_selftest. Nothing about the host was measured.
#   - `selector_failed jq_rc=<n>`       — jq exited non-zero while applying the def to rows.
# Never describe a lib-load failure as a row-decode failure ("jq did not decode the rows"): jq
# never ran.
#
# Sourceable under `set -u`; sets no shell options. Executed directly with --selftest it prints
# "inngest-probe-row selftest: ok" or exits 1 (the discoverability probe).

INNGEST_PROBE_EMITTER="inngest-server-probe"
INNGEST_PROBE_MARKER="SOLEUR_INNGEST_SERVER_PROBE"

# Built from the two variables above so each literal exists exactly once. `==` binds tighter than
# `and`, and `and` short-circuits, so a non-object row or a non-string message yields false rather
# than a jq error.
INNGEST_PROBE_ROW_JQ="def inngest_probe_row: type == \"object\" and .SYSLOG_IDENTIFIER == \"${INNGEST_PROBE_EMITTER}\" and ((.message | type) == \"string\") and (.message | startswith(\"${INNGEST_PROBE_MARKER} \"));"

# Compile the def (stderr visible) and grade one positive and three negative rows.
# Returns 0 only when every row grades as expected.
inngest_probe_row_selftest() {
  local out rc=0
  out="$(jq -cn "$INNGEST_PROBE_ROW_JQ"'
    [
      ({SYSLOG_IDENTIFIER: $e, message: ($m + " http_code=200 server_active=active")} | inngest_probe_row),
      ({SYSLOG_IDENTIFIER: "doppler", message: ("{\"caller\":\"api\",\"body\":\"" + $m + " http_code=200\"}")} | inngest_probe_row),
      ({SYSLOG_IDENTIFIER: "doppler", message: ($m + " http_code=200 server_active=active")} | inngest_probe_row),
      ({SYSLOG_IDENTIFIER: $e, message: ("note " + $m + " http_code=200")} | inngest_probe_row)
    ]' --arg e "$INNGEST_PROBE_EMITTER" --arg m "$INNGEST_PROBE_MARKER")" || rc=$?
  [[ "$rc" -eq 0 && "$out" == '[true,false,false,false]' ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--selftest" ]]; then
    if inngest_probe_row_selftest; then
      echo "inngest-probe-row selftest: ok"
      exit 0
    fi
    echo "inngest-probe-row selftest: FAILED" >&2
    exit 1
  fi
  echo "usage: bash $0 --selftest (or source it)" >&2
  exit 2
fi
