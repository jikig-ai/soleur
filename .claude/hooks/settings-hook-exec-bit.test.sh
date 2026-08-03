#!/usr/bin/env bash
# Guards that EVERY hook path named in .claude/settings.json is committed
# executable (100755) AND is executable on disk.
#
# Why this exists (#7166, from the #7151 review): a SessionStart hook shipped as
# mode 100644. `settings.json` invokes hook paths DIRECTLY (bare path, no
# interpreter), so the runtime's execve returned EACCES and the hook never ran
# once — while its own suite was 26/26 green, because the suite invoked it as
# `bash <hook>`, which ignores the mode bit entirely. Every green light, and the
# runtime never executed it.
#
# Guards the CLASS, not the instance. `scripts/followthrough-exec-bit.test.sh`
# does the same job for `scripts/followthroughs/*.sh`; its glob deliberately does
# NOT reach `.claude/hooks/`, and widening it would go RED on the .claude/hooks
# files that are legitimately 100644 (README.md, the two payload-shape .md docs,
# lib/*.sh sourced helpers, and several *.test.sh). So this is a sibling gate
# with a different derivation, not a widening of that one.
#
# DERIVATION, not enumeration: the path list is parsed out of settings.json at
# run time. A hand-maintained list would rot the moment a hook is added — and
# the file it failed to cover would be exactly the new, unproven one.
#
# ASSERTS BOTH MODES, deliberately:
#   * INDEX mode via `git ls-files -s` — the bug was COMMITTED as 100644, and a
#     worktree-only `chmod +x` that never reaches the index satisfies `test -x`
#     locally while still shipping a dead hook to every other checkout.
#   * ON-DISK via `test -x` — the index and the worktree diverge under
#     `core.fileMode=false`, on a `noexec` mount, or when a fix lands in the
#     index but not on disk. The runtime execve's the ON-DISK file, so an
#     index-only check would pass over a hook that cannot actually run here.
# Neither subsumes the other; both are required.
#
# CARDINALITY IS ASSERTED THREE WAYS, not by a loose floor. A floor ("at least
# 25") is the obvious mechanism and it is not sufficient: against 33 real paths,
# a jq filter that silently dropped an entire hook event (say all 5 PostToolUse
# entries) still clears 25 and the gate reports green over 5 unchecked hooks.
#   (a) the derived listing is non-empty;
#   (b) EVERY top-level key under `.hooks` contributes >= 1 path — so dropping a
#       whole event fails even though the total stays high;
#   (c) the derived command count equals the number of `type == "command"`
#       entries in the file — self-consistent, no magic number to maintain.
# (c) counts commands BEFORE de-duplication: three hooks are deliberately
# registered under two matchers each (guardrails.sh, kb-domain-allowlist-guard.sh,
# no-memory-write.sh), so the file holds 36 command entries over 33 distinct
# paths. Comparing the DEDUPED count against the entry count would be a
# permanently-red gate that the next person "fixes" by deleting the check.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 2

SETTINGS=".claude/settings.json"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

echo "settings-hook-exec-bit: every hook named in $SETTINGS must be committed 100755 and be executable on disk"

if ! command -v jq >/dev/null 2>&1; then
  # Fail, do not skip. Skipping on a missing tool is how a gate becomes
  # permanently inert on the one machine that needed it.
  fail "jq is not installed — cannot parse $SETTINGS, so this gate cannot run"
  echo "FAILED: $fails" >&2
  exit 1
fi

if [[ ! -f "$SETTINGS" ]]; then
  fail "$SETTINGS does not exist — the gate would pass vacuously"
  echo "FAILED: $fails" >&2
  exit 1
fi

# Every command string across every hook event, in file order, NOT de-duplicated.
# The `"$CLAUDE_PROJECT_DIR"/` prefix is stripped to yield a repo-relative path.
# Note the literal double quotes: settings.json stores `"$CLAUDE_PROJECT_DIR"/...`.
# shellcheck disable=SC2016  # the literal string "$CLAUDE_PROJECT_DIR" is the match target, not an expansion
all_commands=$(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$SETTINGS" 2>/dev/null \
  | sed 's|^"\$CLAUDE_PROJECT_DIR"/||')

# (a) Non-empty listing.
if [[ -z "$all_commands" ]]; then
  fail "no hook commands parsed out of $SETTINGS — the jq filter matched nothing, so every assertion below would be vacuous"
  echo "FAILED: $fails" >&2
  exit 1
fi

derived_count=$(printf '%s\n' "$all_commands" | grep -c .)

# (c) Self-consistency: the derivation must see every `type: command` entry.
entry_count=$(jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(.type == "command")] | length' "$SETTINGS" 2>/dev/null)
if [[ ! "$entry_count" =~ ^[0-9]+$ ]]; then
  fail "could not count 'type: command' entries in $SETTINGS (got: '$entry_count')"
elif [[ "$derived_count" -ne "$entry_count" ]]; then
  fail "derived $derived_count command(s) but $SETTINGS declares $entry_count 'type: command' entries — the jq filter is dropping entries, so some hooks are never checked"
else
  pass "derivation is self-consistent: $derived_count commands == $entry_count 'type: command' entries"
fi

# (b) Every hook event is REPRESENTED IN THE DERIVED LIST.
# Deliberately coupled to `all_commands` rather than re-querying the file: a
# check that independently re-reads settings.json per event would confirm the
# FILE has entries while saying nothing about whether the derivation above saw
# them — so a filter that silently drops all of PostToolUse would sail through
# it. Cross-checking the derived list makes this a genuinely second instrument
# from (c): (c) catches a drop of any size by count, (b) names the event that
# vanished.
events=$(jq -r '.hooks | keys[]' "$SETTINGS" 2>/dev/null)
if [[ -z "$events" ]]; then
  fail "no hook events found under .hooks in $SETTINGS"
else
  event_total=0
  while IFS= read -r ev; do
    [[ -z "$ev" ]] && continue
    event_total=$((event_total + 1))
    # shellcheck disable=SC2016
    first=$(jq --arg ev "$ev" -r '[.hooks[$ev][] | .hooks[] | .command][0] // ""' "$SETTINGS" 2>/dev/null \
      | sed 's|^"\$CLAUDE_PROJECT_DIR"/||')
    if [[ -z "$first" ]]; then
      fail "hook event '$ev' declares no commands in $SETTINGS"
      continue
    fi
    # grep against a here-string, never a pipe: `grep -q` on a pipe closes early
    # and the producer takes SIGPIPE, which under `pipefail` inverts the result.
    if ! grep -qxF -- "$first" <<< "$all_commands"; then
      fail "hook event '$ev' is absent from the derived list (expected '$first') — the derivation dropped an entire event, so its hooks are never mode-checked"
    fi
  done <<< "$events"
  (( event_total > 0 )) && pass "$event_total hook event(s) each represented in the derived list"
fi

# Distinct paths are what actually get mode-checked.
paths=$(printf '%s\n' "$all_commands" | sort -u | grep -c . || true)
checked=0
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  checked=$((checked + 1))

  # `git ls-files -s` emits: <mode> <sha> <stage>\t<path>
  entry=$(git ls-files -s -- "$p" 2>/dev/null)
  if [[ -z "$entry" ]]; then
    # Also catches a command carrying an interpreter or arguments: the derived
    # token then is not a tracked path, and production would exec something CI
    # never mode-checked.
    fail "$p is named in $SETTINGS but is NOT tracked by git — production would exec a file CI never sees (or the command carries args/an interpreter this gate cannot parse)"
    continue
  fi

  mode=${entry%% *}
  if [[ "$mode" != "100755" ]]; then
    fail "$p is committed mode $mode — settings.json execs it directly, so the runtime gets EACCES and the hook silently never runs (#7151)"
  fi

  if [[ ! -x "$p" ]]; then
    fail "$p is not executable on disk — the runtime execve's the on-disk file, so an index-only fix still cannot run here"
  fi
done <<< "$(printf '%s\n' "$all_commands" | sort -u)"

if [[ "$checked" -ne "$paths" ]]; then
  fail "checked $checked path(s) but derived $paths distinct path(s) — the check loop is skipping entries"
fi

if (( fails == 0 )); then
  pass "$checked distinct hook path(s) all tracked, committed 100755, and executable on disk"
  echo "PASSED"
  exit 0
fi

echo "FAILED: $fails" >&2
exit 1
