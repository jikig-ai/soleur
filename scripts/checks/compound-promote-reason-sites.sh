#!/usr/bin/env bash
# Preflight Check 10 `discoverability_test` probe for #8427.
#
# Property: the SET of `reason` literals emitted by the `ok: false` returns
# inside `checkDiffPaths` is exactly the SET declared by `DiffPathVerdict`.
#
# WHY A ONE-TOKEN OUTPUT. Check 10's matcher is `tokens.some(...)` — ANY single
# surviving token satisfies a multi-token expectation — so an expectation listing
# the seven reasons would still PASS after six of them were reverted. One token,
# printed only on an exact match, is the only expectation shape a partial revert
# cannot satisfy.
#
# This is a cheap static mirror of the AST census in
# `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts`,
# which is the authority. The census runs a real TypeScript parse; this runs in a
# preflight budget measured in seconds and must not need node_modules.
set -uo pipefail
export LC_ALL=C

SRC="apps/web-platform/server/inngest/functions/cron-compound-promote.ts"

fail() { printf 'COMPOUND_PROMOTE_REASON_SITES_MISMATCH %s\n' "$1"; exit 1; }

[ -r "$SRC" ] || fail "unreadable=$SRC"

# --- declared side: the `reason:` member of the DiffPathVerdict union ---------
# Window from the type alias to its terminating `};`. Multi-line tolerant: the
# union is one member per line today, but nothing in this repo pins that (there
# is no formatter config), so the window is taken by range, not by line count.
declared="$(
  awk '
    /^export type DiffPathVerdict =/ { inblk = 1 }
    inblk { print }
    inblk && /^    \};$/ { exit }
  ' "$SRC" \
  | sed -n 's/.*|[[:space:]]*"\([a-z-]*\)".*/\1/p' \
  | sort -u
)"

# --- emitted side: every `reason: "…"` inside the checkDiffPaths body ---------
# The window ends at the function's closing brace at column 0.
emitted="$(
  awk '
    /^export async function checkDiffPaths\(/ { inblk = 1 }
    inblk { print }
    inblk && /^\}$/ { exit }
  ' "$SRC" \
  | grep -oE 'reason: "[a-z-]+"' \
  | sed 's/reason: "//; s/"$//' \
  | sort -u
)"

# A probe that finds nothing must FAIL, never print the OK token: an empty-vs-empty
# comparison is trivially equal, which is the vacuous pass this guard class exists
# to remove.
[ -n "$declared" ] || fail "declared-set-empty"
[ -n "$emitted" ]  || fail "emitted-set-empty"

if [ "$declared" != "$emitted" ]; then
  # Diagnostic on stderr so stdout carries the verdict token alone.
  printf 'declared:\n%s\nemitted:\n%s\n' "$declared" "$emitted" >&2
  fail "set-mismatch"
fi

printf 'COMPOUND_PROMOTE_REASON_SITES_OK\n'
