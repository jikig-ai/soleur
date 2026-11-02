# shellcheck shell=bash
# Shared by every launch-check lib. Sourced; never executed.

# lc_abort <reason> <exit-code> [detail]: one machine-readable marker on stdout (the customer's tool
# result is the only sink; there is no Soleur-side telemetry by design), then exit.
lc_abort() {
  printf 'SOLEUR_LAUNCH_CHECK_ABORT reason=%s%s\n' "$1" "${3:+ $3}"
  [ -n "${3:-}" ] && printf 'launch-check: %s (%s)\n' "$1" "$3" >&2 || printf 'launch-check: %s\n' "$1" >&2
  exit "${2:-2}"
}

# lc_scrub: one line, no tabs, no pipes that would split a markdown table cell.
lc_scrub() { printf '%s' "$1" | tr '\t\n\r' '   '; }
