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
# Extended per PR: PR 1 (W1 credential deny) checks below; PR 2 (W2) adds the plugin
# destructive-command guard (registration plus a three-envelope functional probe);
# PR 3 the release scan step.
#
# SLICE1_PLUGIN_ROOT (default <repo>/plugins/soleur) is a test seam: the suite
# points it at a COPY of the plugin tree so a broken guard can be driven without
# editing the live hook. The observability gate runs this script under a 15 s cap.
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

# --- W2: the plugin destructive-command guard is registered and decides -------
# Registration: some PreToolUse entry that runs the guard has a matcher that reads
# "Bash". Function: the hook, run from a temp HOME and cwd with GIT_* stripped by
# prefix and the kill switch unset, answers ask / deny / nothing for three canned
# envelopes. Needs jq and perl and says so by name rather than passing without them.
plugin="${SLICE1_PLUGIN_ROOT:-$root/plugins/soleur}"
hooks_json="$plugin/hooks/hooks.json"
guard="$plugin/hooks/destructive-command-guard.sh"
if need_file "$hooks_json" && need_file "$guard"; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "slice1-security: FAIL guard check needs jq on PATH"
    fail=1
  elif ! command -v perl >/dev/null 2>&1; then
    echo "slice1-security: FAIL guard check needs perl on PATH"
    fail=1
  else
    matchers="$(jq -r '.hooks.PreToolUse[]? | select(any(.hooks[]?; (.command // "") | contains("hooks/destructive-command-guard.sh"))) | .matcher // ""' "$hooks_json" 2>/dev/null || true)"
    bash_hits=0
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      n="$(printf '%s' Bash | grep -c -E -- "$m" || true)"
      case "$n" in '' | *[!0-9]*) n=0 ;; esac
      bash_hits=$((bash_hits + n))
    done <<EOF
$matchers
EOF
    check "guard registered under a PreToolUse matcher that reads Bash" "$bash_hits" 1

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    guard_says() { # guard_says <command> -> the permissionDecision, or empty when the hook is silent
      env_json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"},\"cwd\":\"$tmp\"}"
      out="$(
        for v in $(compgen -e); do
          case "$v" in GIT_*) unset "$v" ;; esac
        done
        unset SOLEUR_DISABLE_DESTRUCTIVE_GUARD
        cd "$tmp" && printf '%s' "$env_json" | HOME="$tmp" bash "$guard" 2>/dev/null
      )" || out=""
      printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true
    }
    d1="$(guard_says 'terraform destroy')"
    d2="$(guard_says 'rm -rf ~')"
    d3="$(guard_says 'ls')"
    [ "$d1" = ask ] || { echo "slice1-security: FAIL guard probe 'terraform destroy' answered '$d1', want ask"; fail=1; }
    [ "$d2" = deny ] || { echo "slice1-security: FAIL guard probe 'rm -rf ~' answered '$d2', want deny"; fail=1; }
    [ -z "$d3" ] || { echo "slice1-security: FAIL guard probe 'ls' answered '$d3', want silence"; fail=1; }
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "slice1-security: ok"
fi
exit "$fail"
