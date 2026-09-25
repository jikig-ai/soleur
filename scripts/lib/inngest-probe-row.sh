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
# Contract for consumers (every reader of SOLEUR_INNGEST_SERVER_PROBE rows sources this file —
# the census in inngest-probe-row.test.sh fails CI on a reader that does not):
#   - Resolve the path as "${INNGEST_PROBE_ROW_LIB:-<repo-relative path>}" (the override exists for
#     test sandboxes that run a COPY of the consumer from a temp dir).
#   - Guard the source with `|| <selector-unavailable arm>` — never read a failed source as silence.
#   - Use "$INNGEST_PROBE_ROW_JQ" (no `:-` default) and prefix it to the jq program; then
#     `select(inngest_probe_row)` on the DECODED row object.
#   - Capture jq's exit code before any `|| true`.
#   - Python consumers read os.environ["INNGEST_PROBE_EMITTER"] / ["INNGEST_PROBE_MARKER"].
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
