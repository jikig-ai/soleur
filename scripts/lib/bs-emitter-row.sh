#!/usr/bin/env bash
# bs-emitter-row.sh — the generalized journald emitter-selection jq def (#8875).
#
# A Better Stack `raw` column is a double-encoded journald record; selecting rows by message
# substring admits ANY emitter whose payload merely quotes the needle — doppler event-log rows
# quote issue/PR text verbatim (measured in #6475, the 2026-09-17 inngest-host-state.sh false
# "VERDICT NOT SERVING", and #8846). The emitter of a journald row is its SYSLOG_IDENTIFIER
# field; only a field-equality read on the DECODED row object discriminates it.
#
# This is the sibling of scripts/lib/inngest-probe-row.sh with the emitter (and marker)
# PARAMETERIZED instead of pinned to the probe constants — the probe lib keeps its own
# contract; this one is for every other emitter tag.
#
# Two exported jq programs:
#   BS_EMITTER_ROW_JQ        — `def bs_emitter_row($e):` true when the row is an object whose
#                              .SYSLOG_IDENTIFIER == $e.
#   BS_EMITTER_MARKER_ROW_JQ — `def bs_emitter_marker_row($e;$m):` bs_emitter_row($e) AND
#                              .message is a string BEGINNING with "$m " (marker + space: a
#                               row whose message starts "MARKERX" is not the marker). This
#                               variable INLINES the base def, so it compiles standalone.
#
# Host isolation (host + host_name) is the CALLER's job — these predicates say nothing about
# which host a row came from.
#
# LOAD CONTRACT (every consumer; the census in lint-betterstack-emitter-read.sh counts a
# non-comment source of this file — or a use of the exported names — as an emitter-selected
# reader). Load it EXACTLY like this, adapting only the failure arm:
#
#     unset BS_EMITTER_ROW_JQ BS_EMITTER_MARKER_ROW_JQ
#     _ber_lib="${BS_EMITTER_ROW_LIB:-<path from THIS script's own location>}"
#     # shellcheck source=scripts/lib/bs-emitter-row.sh
#     if ! source "$_ber_lib" || ! declare -F bs_emitter_row_selftest >/dev/null \
#        || ! bs_emitter_row_selftest; then
#       <selector_unavailable arm naming lib=$_ber_lib>
#     fi
#
#   - `unset` BEFORE the source: the names can arrive inherited (Doppler keys are exported
#     into $GITHUB_ENV by .github/actions/infra-credentials). A source that fails, or that
#     loads a file defining nothing (BS_EMITTER_ROW_LIB=/dev/null), must never leave an
#     inherited — possibly permissive — def in force.
#   - BS_EMITTER_ROW_LIB is the test-sandbox override (suites run a COPY of the consumer from
#     a temp dir). The default resolves from the consumer's own location (BASH_SOURCE /
#     $GITHUB_WORKSPACE), never from $PWD.
#   - The selftest after the source proves the loaded defs compile AND reject the wrong
#     shapes; a lib that loads but defines nothing, or a permissive def, is
#     selector_unavailable.
#   - Do NOT send the source's stderr to /dev/null: a missing file and a syntax error in this
#     lib must stay distinguishable in the log.
#   - Use "$BS_EMITTER_ROW_JQ" / "$BS_EMITTER_MARKER_ROW_JQ" (never a `:-` default) as the
#     prefix of the jq program, then `select(bs_emitter_row("<tag>"))` /
#     `select(bs_emitter_marker_row($e; $m))` on the DECODED row object — never redefine the
#     defs locally (a later `def bs_emitter_row:` shadows this one).
#   - Capture jq's exit code before any `|| true`.
#
# FAILURE VOCABULARY (one pair, in every consumer — identical tokens to inngest-probe-row.sh
# so failure-text greps work across both contracts). Each consumer keeps its own verdict
# CLASS (TRANSIENT exit 2, CANNOT ESTABLISH exit 3, ...) but spells the reason with exactly
# these tokens:
#   - `selector_unavailable lib=<path>` — this file could not be sourced, defined nothing, or
#     failed bs_emitter_row_selftest. Nothing about the host was measured.
#   - `selector_failed jq_rc=<n>`       — jq exited non-zero while applying the def to rows.
# Never describe a lib-load failure as a row-decode failure ("jq did not decode the rows"):
# jq never ran.
#
# Sourceable under `set -u`; sets no shell options. Executed directly with --selftest it
# prints "bs-emitter-row selftest: ok" or exits 1 (the discoverability probe).

# `==` binds tighter than `and`, and `and` short-circuits, so a non-object row or a
# non-string message yields false rather than a jq error.
BS_EMITTER_ROW_JQ='def bs_emitter_row($e): type == "object" and .SYSLOG_IDENTIFIER == $e;'

# The marker def embeds the base def so consumers may use this variable standalone
# (`jq "$BS_EMITTER_MARKER_ROW_JQ"` compiles on its own). Concatenating it after
# $BS_EMITTER_ROW_JQ is also safe: jq lets a later `def` shadow an earlier one, and the two
# base defs here are byte-identical.
BS_EMITTER_MARKER_ROW_JQ="${BS_EMITTER_ROW_JQ}"' def bs_emitter_marker_row($e;$m): bs_emitter_row($e) and ((.message | type) == "string") and (.message | startswith($m + " "));'

# Compile both defs (stderr stays visible) and grade positive/negative rows for each.
# Returns 0 only when every row grades as expected.
bs_emitter_row_selftest() {
  local out rc=0
  out="$(jq -cn "$BS_EMITTER_MARKER_ROW_JQ"'
    [
      ({SYSLOG_IDENTIFIER: $e, message: "anything"} | bs_emitter_row($e)),
      ({SYSLOG_IDENTIFIER: "other-emitter", message: "anything"} | bs_emitter_row($e)),
      ("a bare string" | bs_emitter_row($e)),
      ({SYSLOG_IDENTIFIER: $e, message: ($m + " field=value")} | bs_emitter_marker_row($e; $m)),
      ({SYSLOG_IDENTIFIER: "other-emitter", message: ($m + " field=value")} | bs_emitter_marker_row($e; $m)),
      ({SYSLOG_IDENTIFIER: $e, message: ("note " + $m + " field=value")} | bs_emitter_marker_row($e; $m)),
      ({SYSLOG_IDENTIFIER: $e, message: ($m + "X field=value")} | bs_emitter_marker_row($e; $m)),
      ({SYSLOG_IDENTIFIER: $e, message: 42} | bs_emitter_marker_row($e; $m))
    ]' --arg e 'probe-tag' --arg m 'SELFTEST_MARKER')" || rc=$?
  [[ "$rc" -eq 0 && "$out" == '[true,false,false,true,false,false,false,false]' ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--selftest" ]]; then
    if bs_emitter_row_selftest; then
      echo "bs-emitter-row selftest: ok"
      exit 0
    fi
    echo "bs-emitter-row selftest: FAILED" >&2
    exit 1
  fi
  echo "usage: bash $0 --selftest (or source it)" >&2
  exit 2
fi
