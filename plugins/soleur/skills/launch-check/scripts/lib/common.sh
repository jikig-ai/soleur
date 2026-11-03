# shellcheck shell=bash
# Shared by every launch-check lib. Sourced; never executed.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

# lc_abort <reason> <exit-code> [detail]: one machine-readable marker on stdout (the customer's tool
# result is the only sink; there is no Soleur-side telemetry by design), then exit.
lc_abort() {
  printf 'SOLEUR_LAUNCH_CHECK_ABORT reason=%s%s\n' "$1" "${3:+ $3}"
  [ -n "${3:-}" ] && printf 'launch-check: %s (%s)\n' "$1" "$3" >&2 || printf 'launch-check: %s\n' "$1" >&2
  exit "${2:-2}"
}

# lc_scrub: one line, no tabs or carriage returns (markdown-table pipes are escaped by the renderer).
lc_scrub() { printf '%s' "$1" | tr '\t\n\r' '   '; }

# lc_seam <VAR> <default>: the value of an environment override, honoured ONLY when LAUNCH_CHECK_TEST=1.
# A production run never lets an inherited variable (a repo-controlled shell profile, direnv, an `env` block
# in project settings) swap out the scanner, the redaction sentinel or the guard manifest.
lc_seam() { local v="${!1:-}"; if [ "${LAUNCH_CHECK_TEST:-}" = 1 ] && [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi; }

# lc_is_headless: an unattended run (CI set, or LAUNCH_CHECK_HEADLESS=1). Used by the render guard and by the issue
# writer's own write wrapper, so the refusal does not depend on the caller having checked.
lc_is_headless() { [ -n "${CI:-}" ] || [ "${LAUNCH_CHECK_HEADLESS:-}" = 1 ]; }
