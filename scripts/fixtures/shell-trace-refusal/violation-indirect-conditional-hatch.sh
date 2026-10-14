#!/usr/bin/env bash
# In scope via ${!name} alone: names no credential literally, so the hatch below
# has nothing real to test and is open by construction. Must be REJECTED.
set -uo pipefail
case "$-" in
  *x*)
    if [ -n "${SOME_VAR:+x}" ]; then
      printf '[FATAL] refusing\n' >&2
      exit 78
    fi
    ;;
esac
args=()
for name in $EXTERNALLY_SUPPLIED_NAMES; do
  args+=("$name=${!name}")
done
env "${args[@]}" /bin/true
