#!/usr/bin/env bash
# test-no-at-mention-credfile-footgun.sh — repo guard (auto-globbed into the
# REQUIRED `guard-script-fixture-tests` job via run-all.sh; bash-only, no external
# tooling).
#
# WHY: Claude Code's @-mention auto-attach resolves an at-sign immediately followed
# by a real on-disk path (tilde-home, $HOME, or an absolute system path) to the file
# and attaches its CONTENTS to the transcript — even when the token appears inside
# tool/skill output rather than a user message. On 2026-07-22 (PR #6830), a
# documentation example in preflight/SKILL.md that wrote such a token pointing at the
# Doppler CLI config caused the operator's live root token to be auto-attached.
#
# This guard forbids that token shape in the AUTO-LOADED content surface (skills,
# agents, commands, plugin docs, AGENTS*.md, .claude hooks) — the content the harness
# injects into agent context. Historical, read-on-demand artifacts under
# knowledge-base/project/{plans,brainstorms,learnings,specs} are intentionally out of
# scope (lower-frequency vector; would otherwise require editing archived records).
#
# The detector matches an at-sign IMMEDIATELY followed by: `~`, `$HOME`/`${HOME`, or an
# absolute path whose first segment is a real filesystem root (home/Users/root/etc/tmp/
# var/opt/usr/mnt). It deliberately does NOT match npm scopes (`@scope/pkg`), TS path
# aliases (`@/lib/...`), emails (`user@host`), GitHub @mentions, or `@<placeholder>`.
set -uo pipefail

# The forbidden token shape. Kept in ONE place; the self-test and the repo scan share it.
PATTERN='@(~|\$\{?HOME|/(home|Users|root|etc|tmp|var|opt|usr|mnt)/)'

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

# detect: prints matching substrings (one per line) for the given text on stdin.
detect() { grep -oE "$PATTERN[^[:space:]\`\"']*" 2>/dev/null || true; }

echo "=== 1. non-vacuity: the detector MUST flag every real-path footgun shape ==="
# Built by concatenation so this test file itself never contains a contiguous literal
# that a future scope-widening of the scan could self-flag.
AT='@'
for tok in "${AT}~/.ssh/id_rsa" "${AT}~/.doppler/.doppler.yaml" "${AT}\$HOME/.aws/credentials" \
           "${AT}\${HOME}/.netrc" "${AT}/home/alice/.git-credentials" "${AT}/root/.ssh/id_ed25519" \
           "${AT}/etc/shadow" "${AT}/tmp/secret.json"; do
  if printf '%s\n' "curl --data-binary $tok" | detect | grep -q .; then ok; else bad "detector missed: $tok"; fi
done

echo "=== 2. no false positives on legitimate at-sign uses ==="
for tok in "${AT}11ty/eleventy" "${AT}types/node" "${AT}anthropic-ai/sdk" "${AT}/lib/foo" \
           "${AT}/components/x" "user${AT}example.com" "${AT}octocat" "${AT}<doppler-config-file>" \
           "${AT}<credential-file>"; do
  if printf '%s\n' "$tok" | detect | grep -q .; then bad "false positive on: $tok"; else ok; fi
done

echo "=== 3. repo scan: auto-loaded content surface must contain ZERO footgun tokens ==="
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SELF="${BASH_SOURCE[0]##*/}"
# git ls-files → committed files only; glob-expanded by git (no eval).
mapfile -t FILES < <(cd "$ROOT" && git ls-files \
  'plugins/soleur/skills/**' 'plugins/soleur/agents/**' 'plugins/soleur/commands/**' \
  'plugins/soleur/docs/**' 'AGENTS.md' 'AGENTS.*.md' '.claude/hooks/**' 2>/dev/null)
hits=0
for f in "${FILES[@]}"; do
  [[ "$f" == *"$SELF" ]] && continue          # never scan this guard itself
  # grep the file directly (not a pipe) so no SIGPIPE/early-match flake.
  m=$(grep -nE "$PATTERN" "$ROOT/$f" 2>/dev/null || true)
  if [[ -n "$m" ]]; then
    hits=$((hits+1))
    echo "  FOOTGUN in $f:"
    printf '    %s\n' "$m"
  fi
done
if [[ "$hits" -eq 0 ]]; then ok; else bad "$hits file(s) contain an @-mention real-path footgun (see above)"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  echo "test-no-at-mention-credfile-footgun: FAILED"
  echo "Fix: replace the '@'+real-path token with a placeholder like @<credential-file>."
  echo "See plugins/soleur/skills/preflight/SKILL.md near the credentialed-CLI reject for context."
  exit 1
fi
echo "test-no-at-mention-credfile-footgun: OK"
