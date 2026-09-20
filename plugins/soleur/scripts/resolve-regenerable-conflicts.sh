#!/usr/bin/env bash
# resolve-regenerable-conflicts.sh — complete a merge whose ONLY conflicts are on generated
# artifacts, by regenerating them from the merged sources.
#
# Usage: bash plugins/soleur/scripts/resolve-regenerable-conflicts.sh <base-ref>
#
# WHY THIS EXISTS (#8377, ADR-230). A generated file that is COMMITTED conflicts with every
# other branch that regenerates it, and side-picking is always wrong: `--ours` and `--theirs`
# each produce an artifact that matches neither side's sources. The correct resolution is to
# take the merged SOURCES and re-run the generator over them.
#
# Most of this repo's generated files stopped being committed for exactly that reason. One did
# not: knowledge-base/engineering/architecture/diagrams/model.likec4.json is a PRODUCT, not a
# cache -- the web-platform C4 viewer reads it out of synced repos that ship no likec4
# compiler (apps/web-platform/server/c4-render.ts), so it has to exist as bytes. This script is
# what keeps that one file from costing what the caches used to.
#
# ── THE CONTRACT: TWO OUTCOMES, AND THE DIAGNOSIS IS IN THE TEXT ───────────────────────────
#   exit 0       the merge completed and was COMMITTED. The caller may push.
#   exit non-0   nothing was touched. The tree is byte-identical to entry and the caller
#                falls back to its existing behaviour.
#
# There is deliberately no third status. An earlier draft split "not applicable" from "regen
# failed" into exit 1 and exit 2; no call site branched on the difference, so the split bought
# nothing and invited a caller to treat one of them as success. The distinction lives in
# stderr, prefixed `not applicable:` or `regen failed:`, where a human reads it.
#
# NEVER PUSHES. Callers own the push and its rejection handling -- sync-pr-behind.sh has exit
# 7 for a rejected push, ship Phase 7 re-polls and re-syncs. A push from here would race them.
#
# NO LOCK. The clean-tree/no-merge-in-progress precondition below IS the serialization: a
# second concurrent run in the same worktree fails it, or fails on git's own index.lock, and
# exits non-zero having touched nothing. That is fail-closed. A dedicated lock beside the
# caller's own (pre-merge-rebase.sh already holds `rebase-main`) would add a failure mode
# without removing one.
set -uo pipefail

# THE REPO IS THE CALLER'S, NOT THIS SCRIPT'S. Resolved from the CWD via
# `git rev-parse --show-toplevel`, never from ${BASH_SOURCE[0]}/../../.. -- this file ships
# inside the plugin, so on a self-hosted install its own path walks up to the PLUGIN root and
# not to the repository being merged. The regen commands below are relative paths run from
# this root, so getting it wrong does not fail loudly; it operates on the wrong tree.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

BASE="${1:-}"

# na <reason> — refuse before anything has been touched.
na()   { echo "[regen-on-conflict] not applicable: $*" >&2; exit 1; }
# bail <reason> — refuse AFTER the merge started; unwind first.
bail() {
  git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
  echo "[regen-on-conflict] $*" >&2
  exit 1
}

[[ -n "$BASE" ]] || na "no base ref given (usage: resolve-regenerable-conflicts.sh <base-ref>)"
[[ -n "$REPO_ROOT" ]] || na "not inside a git work tree (run from the repository being merged)"

cd "$REPO_ROOT" || na "cannot enter repo root $REPO_ROOT"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || na "not inside a git work tree"
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || na "base ref '$BASE' does not resolve to a commit"

# ── THE RESOLVABLE SET ─────────────────────────────────────────────────────────────────────
# One hardcoded path -> command pair. NOT a manifest file, deliberately: a manifest is a
# parse surface, and worse, it invites re-tracking generated files by making the list feel
# cheap to extend. Adding a second member is an edit HERE plus an ADR-230 amendment, so the
# cache-vs-product question gets asked each time.
#
# RESOLVABLE_OVERRIDE is a TEST SEAM ONLY (a TSV of `path<TAB>command`), used by this script's
# suite to drive the two-path and empty-set rows. Nothing in production sets it.
RESOLVABLE_PATHS=()
RESOLVABLE_CMDS=()
if [[ -n "${RESOLVABLE_OVERRIDE:-}" ]]; then
  [[ -f "$RESOLVABLE_OVERRIDE" ]] || na "RESOLVABLE_OVERRIDE=$RESOLVABLE_OVERRIDE is not a file"
  while IFS=$'\t' read -r _p _c; do
    [[ -n "$_p" ]] || continue
    RESOLVABLE_PATHS+=("$_p"); RESOLVABLE_CMDS+=("$_c")
  done < "$RESOLVABLE_OVERRIDE"
else
  RESOLVABLE_PATHS=("knowledge-base/engineering/architecture/diagrams/model.likec4.json")
  RESOLVABLE_CMDS=("bash scripts/regenerate-c4-model.sh")
fi

# is_resolvable <path> -> echoes the command, or returns 1.
is_resolvable() {
  local want="$1" i
  for i in "${!RESOLVABLE_PATHS[@]}"; do
    if [[ "${RESOLVABLE_PATHS[$i]}" == "$want" ]]; then
      printf '%s' "${RESOLVABLE_CMDS[$i]}"
      return 0
    fi
  done
  return 1
}

# ── PRECONDITIONS ──────────────────────────────────────────────────────────────────────────
# A dirty tree is refused rather than merged around: `git merge` would sweep the operator's
# uncommitted work into a commit this script writes unattended.
# ORDER MATTERS. MERGE_HEAD is checked FIRST because a conflicted merge also leaves a dirty
# tree, so the clean-tree check would otherwise answer every in-progress merge with "working
# tree is not clean" -- true, but it routes the operator to the wrong remedy (the fix is
# `git merge --abort`, not staging or discarding files).
[[ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]] || na "a merge is already in progress"
[[ -z "$(git status --porcelain)" ]] || na "working tree is not clean"

# ── CLASSIFY THE CONFLICT BEFORE TOUCHING THE TREE ─────────────────────────────────────────
# merge-tree computes the merge WITHOUT mutating the worktree, so everything above this point
# is reversible by construction. Three meanings, and the script reads all three here while
# reporting only two to its caller:
#   rc 0     clean merge -- nothing for this script to resolve
#   rc 1     conflicts -- parse them
#   rc >= 2  git itself failed -- never guess
mt_out=""; mt_rc=0
mt_out="$(git merge-tree --write-tree "$BASE" HEAD 2>&1)" || mt_rc=$?

if [[ "$mt_rc" -eq 0 ]]; then
  # A run that resolved NOTHING must not return 0: the caller reads 0 as "merged, go push".
  na "no conflict between HEAD and $BASE — nothing to resolve"
fi
if [[ "$mt_rc" -ge 2 ]]; then
  na "git merge-tree failed (rc=$mt_rc): $mt_out"
fi

# Only `CONFLICT (content):` is resolvable. Every other kind -- modify/delete, rename/rename,
# add/add -- encodes a decision about whether a file should EXIST, which regenerating cannot
# answer. Refusing them is not conservatism; a regen would silently pick "exists".
conflicted=()
while IFS= read -r line; do
  [[ "$line" == CONFLICT\ * ]] || continue
  case "$line" in
    "CONFLICT (content): Merge conflict in "*)
      # Path is everything after the prefix, so paths containing spaces survive intact.
      conflicted+=("${line#CONFLICT (content): Merge conflict in }")
      ;;
    *)
      na "unresolvable conflict kind: $line"
      ;;
  esac
done <<< "$mt_out"

# NO FIXTURE REACHES THIS, deliberately. It fires only if merge-tree exits 1 while emitting no
# parseable CONFLICT line -- i.e. if git changes that output format. Its mutation SURVIVES the
# suite and that is the correct result, recorded rather than left for someone to rediscover:
# the alternative to this line is exiting 0 on an unparsed conflict, which commits a merge the
# script never inspected.
[[ "${#conflicted[@]}" -gt 0 ]] || na "merge-tree reported rc=$mt_rc but no CONFLICT lines were parsed"

cmds=()
for p in "${conflicted[@]}"; do
  c="$(is_resolvable "$p")" || na "conflicted path is not regenerable: $p"
  cmds+=("$c")
done

# ── APPLY ──────────────────────────────────────────────────────────────────────────────────
# --no-ff so the merge is always recorded as a merge; --no-commit so the regenerated artifact
# is part of the merge commit rather than a follow-up.
git merge --no-ff --no-commit "$BASE" >/dev/null 2>&1 || true   # expected to conflict

for i in "${!conflicted[@]}"; do
  p="${conflicted[$i]}"
  # Re-check the symlink HERE, not only at entry: the merge just wrote the worktree, and a
  # symlink committed on the base side arrives as one.
  if [[ -L "$p" ]]; then
    bail "not applicable: refusing to write through symlink $p"
  fi
  if ! eval "${cmds[$i]}" >/dev/null 2>&1; then
    bail "regen failed: '${cmds[$i]}' exited non-zero for $p"
  fi
  [[ -e "$p" ]] || bail "regen failed: '${cmds[$i]}' did not produce $p"
  # THE REGENERATED FILE MUST NOT STILL CARRY MARKERS. `git add` on a conflicted path marks it
  # resolved with whatever bytes are in the worktree -- so a regen command that silently did
  # not touch THIS path would otherwise have its conflict markers staged and committed as the
  # artifact. The residual `--diff-filter=U` check below cannot see that: staging is exactly
  # what clears the U flag. Measured: without this, a two-path fixture whose command
  # regenerates only the first commits the second with `<<<<<<<` in it.
  if grep -qE '^(<{7}|={7}|>{7})( |$)' -- "$p" 2>/dev/null; then
    bail "regen failed: $p still contains conflict markers after '${cmds[$i]}'"
  fi
  git add -- "$p" || bail "regen failed: could not stage $p"
done

# The regen commands were run for the paths merge-tree named. If ANY conflict survives, the
# set we acted on was not the set that exists -- do not commit a partial resolution.
# ALSO NOT REACHED BY ANY FIXTURE, and kept for a different reason than the marker check
# above. That one catches "the regen did not touch this path"; this one catches "git merge
# conflicted on a path merge-tree never named" -- a divergence between the two commands. No
# fixture can produce it without a git bug, so its mutation survives the suite by design.
residual="$(git diff --name-only --diff-filter=U)"
[[ -z "$residual" ]] || bail "not applicable: conflicts remain after regeneration: $(tr '\n' ' ' <<< "$residual")"

git commit --no-edit >/dev/null 2>&1 || bail "regen failed: merge commit failed"

csv="$(IFS=,; printf '%s' "${conflicted[*]}")"
printf 'SOLEUR_REGEN_ON_CONFLICT paths=%s rc=0\n' "$csv"
