#!/usr/bin/awk -f
# Inserts a preflight job before the single existing job in a scheduled
# Claude workflow, and adds needs/if guards to the existing job.
# Idempotent: exits if a preflight job already exists.
#
# Usage: awk -f scripts/wire-anthropic-preflight.awk .github/workflows/<name>.yml > tmp && mv tmp <same>
# See .github/actions/anthropic-preflight/action.yml for the guarded action.

BEGIN {
  preflight = \
"  preflight:\n" \
"    runs-on: ubuntu-latest\n" \
"    timeout-minutes: 5\n" \
"    outputs:\n" \
"      ok: ${{ steps.check.outputs.ok }}\n" \
"    steps:\n" \
"      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1\n" \
"      - id: check\n" \
"        uses: ./.github/actions/anthropic-preflight\n" \
"        with:\n" \
"          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}\n" \
"\n"
  found_jobs = 0
  inserted = 0
  skip_next_blank = 0
}

# Abort if preflight already wired in.
/^  preflight:$/ { already = 1 }

{
  if (already) { print; next }

  if (!found_jobs && /^jobs:$/) {
    print
    found_jobs = 1
    next
  }

  # First job header after `jobs:` — inject preflight before it, then
  # add needs/if guards after it.
  if (found_jobs && !inserted && /^  [a-z][-a-z0-9]*:$/) {
    printf "%s", preflight
    print
    print "    needs: preflight"
    print "    if: needs.preflight.outputs.ok == 'true'"
    inserted = 1
    next
  }

  print
}

END {
  if (already) { exit 0 }
  if (!inserted) {
    print "ERROR: could not find job header to wire" > "/dev/stderr"
    exit 1
  }
}
