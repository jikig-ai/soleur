#!/usr/bin/env bash
# Local discoverability probe for the agent-security hardening epic (#9601, slice 1).
#
# Prints `slice1-security: ok` when every control merged so far is present in the
# tree, and `slice1-security: FAIL <what>` (exit 1) otherwise. It is a static
# invariant probe: it proves the controls are WIRED, not that they work; the
# behavioural proof is the suites named in the plan's Guard Contract.
#
# Compares with `grep -c` counts, never a negated grep: a pattern that fails to
# compile must not read as "nothing found, all good".
#
# Extended per PR: PR 1 (W1 credential deny) checks below; PR 2 adds the plugin
# guard registration, PR 3 the release scan step.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fail=0

need_file() { # need_file <path>
  if [ ! -f "$1" ]; then
    echo "slice1-security: FAIL missing file ${1#"$root"/}"
    fail=1
    return 1
  fi
}

check() { # check <label> <count> <minimum>
  case "$2" in
    '' | *[!0-9]*)
      echo "slice1-security: FAIL $1 (unreadable count '$2')"
      fail=1
      ;;
    *)
      if [ "$2" -lt "$3" ]; then
        echo "slice1-security: FAIL $1 (found $2, want at least $3)"
        fail=1
      fi
      ;;
  esac
}

# --- W1: sandbox denies the owner's Anthropic credential to sandboxed Bash ---
cfg="$root/apps/web-platform/server/agent-runner-sandbox-config.ts"
consts="$root/apps/web-platform/server/agent-auth-env-vars.ts"
if need_file "$cfg" && need_file "$consts"; then
  check "credentials deny block built from the shared constant" \
    "$(grep -c -e 'AGENT_AUTH_ENV_VARS.map' "$cfg" || true)" 1
  check "deny mode on every entry" \
    "$(grep -c -e 'mode: "deny" as const' "$cfg" || true)" 1
  check "both auth variables named in the shared constant" \
    "$(grep -c -e 'ANTHROPIC_API_KEY' -e 'CLAUDE_CODE_OAUTH_TOKEN' "$consts" || true)" 2
fi

if [ "$fail" -eq 0 ]; then
  echo "slice1-security: ok"
fi
exit "$fail"
