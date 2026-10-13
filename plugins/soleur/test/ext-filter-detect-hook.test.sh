#!/usr/bin/env bash
# ext-filter-detect-hook.test.sh — stub-PATH + settings fixtures for the SessionStart
# external-filter detector (#10230). The guard contract here is the marker's
# EPISTEMICS: a named posture requires identity corroboration, a bare PATH basename
# is unmeasured by construction, the proxy arm is always neutral (never a vendor
# name — a LiteLLM/corporate proxy is the user's own infra), and `tool=none` fires
# on clean detection so "hook dead" is distinguishable from "no filter".
#
# Auto-discovered by the `scripts` group glob in scripts/test-all.sh.

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$DIR/../../.." && pwd -P)"
SUT="$REPO_ROOT/plugins/soleur/hooks/ext-filter-detect.sh"
HOOKS_JSON="$REPO_ROOT/plugins/soleur/hooks/hooks.json"
DISPOSITIONS="$REPO_ROOT/.claude/hooks/devin-dispositions.tsv"

source "$DIR/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required by this suite" >&2; exit 2; }

SANDBOX="$(mktemp -d -t extfd.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

BIN="$SANDBOX/bin"; HOME_DIR="$SANDBOX/home"; CWD_DIR="$SANDBOX/cwd"
mkdir -p "$BIN" "$HOME_DIR/.claude" "$CWD_DIR/.claude" || exit 2

# Ambient env that rewrites scenario meaning is cleared; each arm re-adds what it needs.
unset ANTHROPIC_BASE_URL SOLEUR_DISABLE_EXT_FILTER_DETECT CODEX_THREAD_ID PLUGIN_ROOT

passes=0; fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; }
check() { [[ "$2" == *"$3"* ]] && pass "$1" || { fail "$1"; printf '       got: %s\n' "$2"; }; }
check_not() { [[ "$2" != *"$3"* ]] && pass "$1" || { fail "$1"; printf '       got: %s\n' "$2"; }; }

mk() { # <name> <version line> — a stub binary
  printf '#!/bin/sh\necho "%s"\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"
}
run() { # [--self-test] [ENV=val ...] -- runs the SUT with an empty stdin envelope
  local hook_arg=""
  case "${1:-}" in --*) hook_arg="$1"; shift ;; esac
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$HOME_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/soleur" "$@" \
    bash "$SUT" $hook_arg </dev/null 2>/dev/null
}

# --- marker semantics -------------------------------------------------------
OUT="$(run)"; check "clean detection emits tool=none" "$OUT" 'SOLEUR_EXT_FILTER tool=none'
check "tool=none carries the ref pointer" "$OUT" 'ref=soleur.ai/known-external-tools'

mk rtk 'rtk 0.12.3'
OUT="$(run)"; check "rtk PATH hit emits tool=rtk" "$OUT" 'tool=rtk'
check "bare PATH rtk floors at unmeasured" "$OUT" 'tool=rtk version=0.12.3 posture=unmeasured via=on-path'

printf '{"hooks":{"PreToolUse":[{"command":"rtk hook rewrite"}]}}' > "$HOME_DIR/.claude/settings.json"
OUT="$(run)"; check "settings-wired rtk gains settings-hook via" "$OUT" 'via=on-path,settings-hook'
check "settings path is tilde-collapsed, never an absolute home path" "$OUT" 'path=~/.claude/settings.json'
check "settings-wired rtk still unmeasured pre-evidence" "$OUT" 'posture=unmeasured'
check_not "settings-wired rtk never emits literal-clean pre-evidence" "$OUT" 'posture=literal-clean'

mk headroom 'headroom-ai 0.30.0'
printf '{"hooks":{"PreToolUse":[{"command":"headroom wrap"}]}}' > "$HOME_DIR/.claude/settings.local.json"
rm "$HOME_DIR/.claude/settings.json"
OUT="$(run)"; check "corroborated headroom at/below eval version" "$OUT" 'tool=headroom version=0.30.0 posture=measured-incompatible'
check "headroom measured_at carries the eval date" "$OUT" 'measured_at=2026-09-07'

mk headroom 'headroom-ai 0.99.0'
OUT="$(run)"; check "headroom newer than the eval floors at unmeasured" "$OUT" 'tool=headroom version=0.99.0 posture=unmeasured'

mk headroom 'not a filter at all'
rm "$HOME_DIR/.claude/settings.local.json"
OUT="$(run)"; check "unresolvable version floors at unmeasured" "$OUT" 'version=unknown posture=unmeasured'
check_not "a bare PATH basename hit never names a negative posture" "$OUT" 'posture=measured-incompatible'

rm -f "$BIN/rtk" "$BIN/headroom"
OUT="$(run ANTHROPIC_BASE_URL=http://localhost:4000)" \
  && check "generic local proxy emits the neutral arm" "$OUT" 'tool=proxy posture=unknown via=proxy-env'
check_not "proxy arm never emits a vendor name" "$OUT" 'tool=headroom'

# single-document stdout: co-detection joins markers inside ONE systemMessage object
mk rtk 'rtk 0.12.3'
OUT="$(run ANTHROPIC_BASE_URL=http://localhost:4000)"
[[ "$(printf '%s' "$OUT" | grep -c '"systemMessage"')" == 1 ]] \
  && pass "co-detection emits exactly one systemMessage object" \
  || fail "co-detection emits exactly one systemMessage object (got: $OUT)"
check "co-detection carries the proxy marker" "$OUT" 'SOLEUR_EXT_FILTER tool=proxy'
check "co-detection carries the rtk marker" "$OUT" 'SOLEUR_EXT_FILTER tool=rtk'

# project-level settings: corroborates, and path= is NEVER tilde-corrupted
printf '{"hooks":{"PreToolUse":[{"command":"rtk hook rewrite"}]}}' > "$CWD_DIR/.claude/settings.json"
printf '{"cwd":"%s"}' "$CWD_DIR" | env -i PATH="$BIN:/usr/bin:/bin" HOME="$HOME_DIR" \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT/plugins/soleur" bash "$SUT" 2>/dev/null > "$SANDBOX/cwd.out" || true
OUT="$(cat "$SANDBOX/cwd.out")"
check "project-level settings corroborates" "$OUT" 'via=on-path,settings-hook'
check "project path is emitted absolute, never tilde-corrupted" "$OUT" "path=$CWD_DIR/.claude/settings.json"
check_not "project path never tilde-corrupted" "$OUT" 'path=~proj'
rm -f "$CWD_DIR/.claude/settings.json" "$BIN/rtk"

OUT="$(run SOLEUR_DISABLE_EXT_FILTER_DETECT=1)"; check "kill switch emits nothing" "$OUT" ''

OUT="$(run --self-test)"; check "--self-test emits a marker" "$OUT" 'SOLEUR_EXT_FILTER'

# --- registration (the dispositions row + hooks.json shape are load-bearing) --
grp="$(jq -c '.hooks.SessionStart[] | select([.hooks[].command | contains("ext-filter-detect")] | any)' "$HOOKS_JSON")"
check "hooks.json registers ext-filter-detect on SessionStart" "$grp" 'ext-filter-detect'
check "the matcher covers startup|resume|clear|compact" "$grp" 'startup|resume|clear|compact'
check "the registration carries timeout 10" "$grp" '"timeout":10'
check "the command is a quoted bash invocation" "$grp" 'bash \"${CLAUDE_PLUGIN_ROOT}/hooks/ext-filter-detect.sh\"'
check "devin-dispositions.tsv carries a row" "$(cat "$DISPOSITIONS")" 'plugins/soleur/hooks/ext-filter-detect.sh'

MIN_VERDICTS=27
if (( passes + fails < MIN_VERDICTS )); then
  printf 'FATAL: verdict floor breached: %d < %d — the suite lost assertions.\n' "$((passes + fails))" "$MIN_VERDICTS" >&2
  fails=$((fails + 1))
fi
printf '\n=== %d verdicts, %d failed ===\n' "$((passes + fails))" "$fails"
(( fails == 0 ))
