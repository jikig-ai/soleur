#!/usr/bin/env bash
# Lint: direct `.from("conversations").update(...)` calls outside the typed
# wrapper module are forbidden in `apps/web-platform/server/`.
#
# Use `updateConversationFor()` from `@/server/conversation-writer` so the
# R8 composite-key invariant (`.eq("id", id).eq("user_id", userId)`) is
# enforced in one place. If a site genuinely needs direct access (bulk
# status sweep without per-user dimension; stronger composite key than the
# wrapper provides), add a `// allow-direct-conversation-update: <reason>`
# comment within the 3 lines preceding the `.from("conversations")` call.
#
# Refs: #2954 (introduced the R8 pattern), #2956 (generalized via wrapper).
set -euo pipefail

SERVER_DIR="apps/web-platform/server"
WRAPPER="$SERVER_DIR/conversation-writer.ts"

if [[ ! -d "$SERVER_DIR" ]]; then
  echo "FAIL: $SERVER_DIR not found (run from repo root)" >&2
  exit 2
fi

if [[ ! -f "$WRAPPER" ]]; then
  echo "FAIL: $WRAPPER not found — wrapper module is the source of truth" >&2
  exit 2
fi

# Find candidate files with any `from("conversations")` token. ripgrep
# with -l emits filenames only.
candidates=$(rg -l 'from\("conversations"\)' "$SERVER_DIR" \
  --glob '!conversation-writer.ts' \
  --glob '!*.test.ts' || true)

if [[ -z "$candidates" ]]; then
  echo "OK: no direct conversation updates outside the wrapper."
  exit 0
fi

# Per-file awk: load every line into an array, then scan for
# `.from("conversations")` lines whose chain (within the next 5 lines)
# includes `.update(`. For each unallowlisted offender, print
# `file:line:source` and exit non-zero.
#
# Multi-line tolerance: the chain split across lines (`.from(...)\n
# .update(...)`) is the bug class this script exists to prevent —
# scanning forward 5 lines from `from("conversations")` for `.update(`
# catches every shape used in the codebase (single-line, 2-line,
# 4-line broken chains).
#
# Allowlist: any of the 3 lines immediately preceding the
# `from("conversations")` line containing `allow-direct-conversation-update:`
# accepts the block.
fail=0
out=""
for file in $candidates; do
  result=$(awk '
    BEGIN { fail = 0 }
    { lines[NR] = $0 }
    END {
      for (n = 1; n <= NR; n++) {
        if (lines[n] !~ /from\("conversations"\)/) continue

        # Look ahead up to 5 lines for `.update(` to confirm this is a
        # write, not a read (`.select(...)`) or insert (`.insert(...)`).
        found_update = 0
        upper = n + 5
        if (upper > NR) upper = NR
        for (m = n; m <= upper; m++) {
          if (lines[m] ~ /\.update\(/) { found_update = 1; break }
          if (lines[m] ~ /\.(select|insert|delete|upsert)\(/) break
        }
        if (!found_update) continue

        # Look back up to 3 lines for the allowlist marker.
        allowed = 0
        lower = n - 3
        if (lower < 1) lower = 1
        for (m = lower; m < n; m++) {
          if (lines[m] ~ /allow-direct-conversation-update:/) {
            allowed = 1
            break
          }
        }
        if (allowed) continue

        printf "%s:%d:%s\n", FILENAME, n, lines[n]
        fail = 1
      }
      exit fail
    }
  ' "$file") || {
    fail=1
    out+="$result"$'\n'
  }
done

if (( fail )); then
  echo "FAIL: direct .from(\"conversations\").update(...) outside conversation-writer.ts:"
  echo ""
  printf '%s' "$out"
  echo ""
  echo "Use updateConversationFor() from @/server/conversation-writer."
  echo "If this site genuinely needs direct access (bulk sweep, stronger"
  echo "composite key than the wrapper provides), add"
  echo "  // allow-direct-conversation-update: <reason>"
  echo "within the 3 lines preceding the .from(\"conversations\") call."
  exit 1
fi

echo "OK: no direct conversation updates outside the wrapper."
exit 0
