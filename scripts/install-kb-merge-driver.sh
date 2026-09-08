#!/usr/bin/env bash
# install-kb-merge-driver.sh — register the knowledge-base index merge driver (#7935).
#
# Idempotent, silent when already correct, and BEST-EFFORT BY DESIGN: it must
# never block a session start or a dependency install. Every failure path exits
# 0 with a diagnostic on stderr.
#
# THE STORED VALUE IS A RELATIVE COMMAND, NOT AN ABSOLUTE PATH. Measured: git
# invokes a merge driver with CWD at the working-tree root even when `git merge`
# runs from a subdirectory, so `bash scripts/merge-kb-index.sh %O %A %B %P` is
# correct in every worktree with nothing baked in. This matters here more than
# it would elsewhere: the repository is bare with linked worktrees, so
# `--show-toplevel` returns the CALLING worktree's root, and baking that into
# the shared config would pin the driver to a feature worktree that gets deleted
# after merge -- producing a flurry of mystery conflicts across unrelated
# worktrees. `--git-common-dir` is no better: the bare repo's parent holds no
# scripts/ directory.
#
# PORCELAIN CALLS ONLY, NEVER A FILE EDIT. This script mutates .git/config
# exclusively through `git config <key> <value>`. Stated as a constraint rather
# than left implicit, because that same shared config holds `core.hooksPath` --
# and a bug that clobbered THAT key would silently disarm every lefthook gate
# across every worktree at once, which is a far worse outcome than the
# unregistered merge driver this script exists to prevent. Plain `git config`
# also serialises through .git/config.lock and never hand-serialises INI, which
# is the property the repo's TypeScript sibling `atomicGitConfig` exists to buy.
#
# IT MUST NOT ARM THE WORKTREE-CONFIG WEDGE. The key written is a plain
# top-level `merge.kb-index.driver`. This script never touches
# `config.worktree` and never sets `extensions.worktreeConfig` (ADR-173 keeps
# that unset deliberately; its stated re-evaluation trigger is a new setter
# appearing anywhere in the toolchain).

set -uo pipefail

KEY="merge.kb-index.driver"
VALUE='bash scripts/merge-kb-index.sh %O %A %B %P'
NAME_KEY="merge.kb-index.name"
NAME_VALUE='knowledge-base index: three-way merge over generated rows'

# OUTPUT CHANNEL (load-bearing). `systemMessage` on STDOUT is the operator-visible
# channel for an exit-0 hook; plain stderr is DISCARDED there
# (`.claude/hooks/README.md`), and this script runs from SessionStart and always
# exits 0. An earlier revision reported registration failures only on stderr —
# the one sink this repo has already recorded as non-functional, in the sibling
# `.claude/hooks/supabase-loopback-warn.sh`, whose header documents exactly this
# defect. stderr is kept as a second sink for the interactive `npm install` case.
note() {
  printf 'install-kb-merge-driver: %s\n' "$1" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg m "install-kb-merge-driver: $1" '{systemMessage:$m}' 2>/dev/null || true
  fi
}

# Not a git repository (a tarball export, a docs-only checkout) is not an error.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  note "not inside a git repository; nothing to register"
  exit 0
fi

set_key() {
  local key="$1" want="$2" current count
  # `--get` returns the LAST value of a multi-valued key, and git resolves
  # merge.<name>.driver to that same last value — so a config carrying two
  # entries reports "already correct" while a different one may be live, and a
  # plain `git config <key> <value>` ERRORS on a multivar rather than replacing
  # it. Both directions leave the key unconverged with the script exiting 0.
  # Count first, then always write with --replace-all.
  count="$(git config --get-all "$key" 2>/dev/null | wc -l | tr -d ' ')"
  current="$(git config --get "$key" 2>/dev/null || true)"
  if [[ "$count" == "1" && "$current" == "$want" ]]; then
    return 0
  fi
  if [[ "${count:-0}" -gt 1 ]]; then
    note "$key held $count values; collapsing to one (a multivar makes the live driver ambiguous)"
  fi
  if git config --replace-all "$key" "$want" 2>/dev/null; then
    return 0
  fi
  # A concurrent writer holds .git/config.lock. Parallel agent sessions across
  # many worktrees can fire SessionStart simultaneously, so this is a realistic
  # shape rather than a hypothetical one. Retry once, then give up quietly --
  # whichever session wins writes the same value.
  sleep 1
  if git config --replace-all "$key" "$want" 2>/dev/null; then
    return 0
  fi
  return 1
}

rc=0
set_key "$KEY" "$VALUE" || rc=1
set_key "$NAME_KEY" "$NAME_VALUE" || rc=1

if [[ "$rc" -ne 0 ]]; then
  # Do NOT name a cause this run did not measure. The previous text asserted
  # config.lock contention on every failure, which sent a reader down a lock
  # path for a multivar or a permissions problem.
  note "could not write $KEY; the driver is NOT registered in this checkout (causes: .git/config.lock held, a read-only config, or a value this script could not replace)"
  note "re-run: bash scripts/install-kb-merge-driver.sh"
fi

# Always 0: a registration failure must never block a session start or an
# `npm install`. CI's `generate-kb-index.sh --check` is what makes an
# unregistered driver loud, because git itself gives no signal at all when
# .gitattributes names a driver that is not registered -- it silently falls back
# to the default text merge.
exit 0
