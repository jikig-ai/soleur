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
# Each check counts the lines matching one anchored pattern ("at least N"); a
# reformat that wraps a call across lines trips it, which is the intended noise.
app="$root/apps/web-platform/server"
cfg="$app/agent-runner-sandbox-config.ts"
consts="$app/agent-auth-env-vars.ts"
qopts="$app/agent-runner-query-options.ts"
legacy="$app/agent-runner.ts"
cc="$app/soleur-go-runner.ts"
if need_file "$cfg" && need_file "$consts" && need_file "$qopts" && need_file "$legacy" && need_file "$cc"; then
  check "credentials deny block built from the shared constant" \
    "$(grep -c -E '^ *envVars: AGENT_AUTH_ENV_VARS\.map\(' "$cfg" || true)" 1
  check "deny mode on the entries" \
    "$(grep -c -E '^ *mode: "deny" as const,' "$cfg" || true)" 1
  check "API key name defined in the shared constant" \
    "$(grep -c -E '^export const API_KEY_ENV_VAR = "ANTHROPIC_API_KEY"' "$consts" || true)" 1
  check "OAuth token name defined in the shared constant" \
    "$(grep -c -E '^export const OAUTH_ENV_VAR = "CLAUDE_CODE_OAUTH_TOKEN"' "$consts" || true)" 1
  check "production options builder takes the sandbox from buildAgentSandboxConfig" \
    "$(grep -c -E '^ *sandbox: buildAgentSandboxConfig\(' "$qopts" || true)" 1
  check "credentials directive used by the legacy prompt builder" \
    "$(grep -c -E 'CREDENTIALS_PROMPT_DIRECTIVE' "$legacy" || true)" 2
  check "credentials directive defined and used by the Concierge prompt builder" \
    "$(grep -c -E 'CREDENTIALS_PROMPT_DIRECTIVE' "$cc" || true)" 2
fi

if [ "$fail" -eq 0 ]; then
  echo "slice1-security: ok"
fi
exit "$fail"
