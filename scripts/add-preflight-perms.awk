#!/usr/bin/awk -f
# Adds `permissions: { contents: read }` to the preflight job in a workflow.
# Idempotent: no-op if the block is already present.

BEGIN { in_preflight = 0; inserted = 0; already = 0 }

/^  preflight:$/ { in_preflight = 1; print; next }

# Leaving the preflight job — stop tracking.
in_preflight && /^  [a-z][-a-z0-9]*:$/ { in_preflight = 0 }

# Already has a permissions block inside preflight — mark done.
in_preflight && /^    permissions:$/ { already = 1 }

# Insert after `timeout-minutes:` line (first occurrence inside preflight).
in_preflight && !inserted && !already && /^    timeout-minutes: 5$/ {
  print
  print "    permissions:"
  print "      contents: read"
  inserted = 1
  next
}

{ print }
