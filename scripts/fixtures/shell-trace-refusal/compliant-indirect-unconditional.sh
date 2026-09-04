#!/usr/bin/env bash
# Same unbounded indirection, refused UNCONDITIONALLY. Must PASS. This is the
# positive control: without it, a rule that rejected every indirect file would
# score identically to one that discriminates.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac
args=()
for name in $EXTERNALLY_SUPPLIED_NAMES; do
  args+=("$name=${!name}")
done
env "${args[@]}" /bin/true
