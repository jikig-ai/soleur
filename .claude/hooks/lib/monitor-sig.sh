#!/usr/bin/env bash
# Shared target-signature extraction for the two monitor-lifetime hooks:
# monitor-arm-recorder.sh (PostToolUse, writes the ledger) and
# monitor-supersede-guard.sh (PreToolUse, reads it and reports).
#
# One file rather than two copies because a signature the writer and the reader
# compute DIFFERENTLY never matches, and "never matches" is byte-for-byte
# indistinguishable from "no prior monitor" — a silently dead gate.
#
# The scheme is deliberately narrow and its MISSES are documented rather than
# denied. Measured 2026-09-03, these shapes produce NO signature and are
# therefore invisible: `gh pr checks` with no number (branch-resolved),
# `gh run watch <run-id>`, `gh api repos/o/r/pulls/<n>`, a flag before the
# number (`gh pr checks --repo o/r 7753`), and any absolute path outside
# /tmp and /var/tmp. Do not describe this scheme as collision-free.

# monitor_sig <payload-json> -> echoes a signature, or nothing.
monitor_sig() {
  local input="$1" cmd wsurl n w b p sig=""
  # ADR-156 / AP-020: hook stdin is model-controlled. A non-string field must
  # collapse to "" rather than render across lines into the extractors below.
  cmd=$(printf '%s' "$input" | jq -r 'if ((.tool_input.command? // null) | type) == "string" then .tool_input.command else "" end' 2>/dev/null) || cmd=""
  wsurl=$(printf '%s' "$input" | jq -r 'if ((.tool_input.ws?.url? // null) | type) == "string" then .tool_input.ws.url else "" end' 2>/dev/null) || wsurl=""

  if [ -n "$wsurl" ]; then
    # Drop the query string. It carries signed tokens in practice, and host+path
    # is what identifies the stream — so redaction and collision semantics agree.
    sig="ws:${wsurl%%\?*}"
  else
    n=$(printf '%s' "$cmd" | grep -oE 'gh (pr|issue) [a-z-]+ [0-9]+' | grep -oE '[0-9]+$' | head -1)
    if [ -n "$n" ]; then
      sig="pr:$n"
    else
      w=$(printf '%s' "$cmd" | grep -oE '(--workflow|-w)[= ][A-Za-z0-9._-]+' | head -1 | sed 's/.*[= ]//')
      if [ -n "$w" ]; then
        # Scope by branch when one is named. `--branch main` and `--branch feat-x`
        # on one workflow are different targets; unscoped they collided (measured).
        b=$(printf '%s' "$cmd" | grep -oE '\-\-branch[= ][A-Za-z0-9._/-]+' | head -1 | sed 's/.*[= ]//')
        sig="workflow:$w${b:+@$b}"
      else
        p=$(printf '%s' "$cmd" | grep -oE '/(var/tmp|tmp)/[A-Za-z0-9._/-]+' | head -1)
        [ -n "$p" ] && sig="path:$p"
      fi
    fi
  fi
  # Cap. The signature is the only unbounded field in a ledger record, and a
  # record over 4096 bytes stops being one write() — concurrent appends then
  # splice, and a spliced-but-parseable fragment can disarm the read entirely.
  printf '%s' "${sig:0:512}"
}
