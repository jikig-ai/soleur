#!/usr/bin/env bash
# resolve-regenerable-conflicts.sh — complete a merge whose ONLY conflicts are on generated
# artifacts, by regenerating them from the merged sources.
#
# Usage: bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-regenerable-conflicts.sh" <base-ref>
#        (run from inside the repository being merged)
#
# WHY THIS EXISTS (#8377, ADR-235). A generated file that is COMMITTED conflicts with every
# other branch that regenerates it, and side-picking is always wrong: `--ours` and `--theirs`
# each produce an artifact that matches neither side's sources. The correct resolution is to
# take the merged SOURCES and re-run the generator over them.
#
# Most of this repo's generated files stopped being committed for exactly that reason. One did
# not: knowledge-base/engineering/architecture/diagrams/model.likec4.json is a PRODUCT, not a
# cache -- the web-platform C4 viewer (apps/web-platform/app/api/kb/c4/project/route.ts)
# fetches the committed blob from GitHub on the request path with no build step, so it has to
# exist as a committed blob. (An earlier draft cited c4-render.ts and "no likec4 compiler";
# c4-render.ts is the WRITER, and it proves a compiler exists in the runner image. The
# conclusion held; the reason did not.) This script is
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
# NO LOCK, and the reason is narrower than an earlier draft of this comment claimed. That
# draft said a second concurrent run "fails on git's own index.lock ... having touched
# nothing". Both halves were wrong (#8384 review): a LINKED WORKTREE keeps its index,
# index.lock, HEAD and MERGE_HEAD under .git/worktrees/<name>/, so index.lock is NOT shared
# between the 70+ worktrees of this repo; and when the merge did lose that race the regen had
# already run and written the tree -- only `git add` failed.
# What actually makes concurrent runs safe is per-worktree index/HEAD/MERGE_HEAD, an
# append-only object store, and per-ref locking. WITHIN one worktree the clean-tree and
# no-merge-in-progress preconditions serialize, and the MERGE_HEAD assertion below is what
# makes a lost race fail closed rather than commit a non-merge. Not covered by any of that:
# the shared npm/npx cache the regen command pulls through.
set -uo pipefail

# THE PLUGIN IS THIS SCRIPT'S; THE REPO IS THE CALLER'S. Two roots, two sources, never mixed.
#
# The PLUGIN directory comes from ${BASH_SOURCE[0]}, and it is made absolute HERE, before the
# `cd "$REPO_ROOT"` below: a relative BASH_SOURCE (`bash ../../x/resolve-….sh` from a
# subdirectory) resolved after that cd names a different directory -- possibly one inside the
# tree being merged. ADR-179 sanctions BASH_SOURCE for payload scripts ("their own BASH_SOURCE
# location (layout-invariant per ADR-178, and not CWD-derived)"); sync-pr-behind.sh already
# finds this resolver the same way. A sibling carries this script's own provenance, so it
# adds no trust edge that loading this script did not already add.
_plugin_scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || _plugin_scripts_dir=""
readonly PLUGIN_SCRIPTS_DIR="$_plugin_scripts_dir"
#
# The REPO is resolved from the CWD via `git rev-parse --show-toplevel`, never from
# ${BASH_SOURCE[0]}/../../.. -- this file ships inside the plugin, so on a self-hosted install
# its own path walks up to the PLUGIN root and not to the repository being merged. Getting it
# wrong does not fail loudly; it operates on the wrong tree. (That is the ban the BASH_SOURCE
# line above does NOT break: it locates CODE, and this line locates DATA.)
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# The render budget. A cold `npx -y likec4@…` install was measured at 151s, and a dense
# corpus renders slowly on its own (generate-c4-from-components.ts, RENDER_TIMEOUT_MS), so the
# same 600s. A timeout is reported with the arm's output tail, never swallowed.
REGEN_TIMEOUT_S=600

# BASE is assigned AFTER the --test-resolvable seam shifts its two argv slots (below);
# reading $1 here would capture the flag itself.
BASE=""

# na <reason> — refuse before anything has been touched.
na()   { echo "[regen-on-conflict] not applicable: $*" >&2; exit 1; }
# bail <reason> — refuse AFTER the merge started; unwind first.
bail() {
  # ASSERT THE OPERAND AT THE SITE. `git -C "" merge --abort` retargets the write at the
  # CALLER's repository, and $REPO_ROOT is command-substitution-derived. Every caller of
  # bail() today runs after the non-empty check below, so this is defence in depth rather
  # than a live bug — but "safe because of where it is called from" is not a property a
  # static reader (or the fixture-dir-operand guard) can confirm, and a future early call
  # would make it live. Asserting here costs one line.
  [[ -n "$REPO_ROOT" ]] || { echo "[regen-on-conflict] $* (no repo root; nothing unwound)" >&2; exit 1; }
  git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
  echo "[regen-on-conflict] $*" >&2
  exit 1
}

[[ -n "$REPO_ROOT" ]] || na "not inside a git work tree — cd into the repository being merged and re-run"

# ── THE PLUGIN ROOT THE ARM RUNS FROM ──────────────────────────────────────────────────────
# plugin_root -> echoes the absolute plugin root whose scripts/render-c4-model.sh the
# production arm runs, or returns 1 with the reason on stdout.
#
# ORDER IS THE CONTROL. The renderer beside THIS resolver wins; ${CLAUDE_PLUGIN_ROOT} is read
# only when that sibling is absent (a resolver copied out of its plugin, e.g. a snapshot).
# Bare form, no `:-` default: ADR-179 A12 records the `:-` class as unmigrated, not endorsed.
# `+set` tests for presence without supplying a value, so `set -u` cannot abort on it.
#
# The plugin.json name check below is DEFENCE-IN-DEPTH, NOT A BOUNDARY (ADR-179 A11). This
# repository's own plugins/soleur/.claude-plugin/plugin.json is tracked and names "soleur",
# so a shadowing copy inside a merged tree carries a GENUINE manifest and passes it byte for
# byte. What keeps a merged tree's copy from running is that neither source above is derived
# from the tree being merged. Where the resolver ITSELF was loaded out of the merged tree, its
# sibling IS that tree's copy and nothing in this script can change that -- the call site has
# to load it from the plugin root, which is why the pre-merge hooks do.
plugin_root() {
  local root="" src=""
  if [[ -n "$PLUGIN_SCRIPTS_DIR" && -f "$PLUGIN_SCRIPTS_DIR/render-c4-model.sh" ]]; then
    root="$(cd "$PLUGIN_SCRIPTS_DIR/.." 2>/dev/null && pwd -P)" || root=""
    src="the resolver's own plugin"
  elif [[ -n "${CLAUDE_PLUGIN_ROOT+set}" && -n "${CLAUDE_PLUGIN_ROOT}" ]]; then
    root="$(cd "${CLAUDE_PLUGIN_ROOT}" 2>/dev/null && pwd -P)" || root=""
    src="CLAUDE_PLUGIN_ROOT"
    if [[ -z "$root" || ! -f "$root/scripts/render-c4-model.sh" ]]; then
      printf '%s' "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} has no scripts/render-c4-model.sh"
      return 1
    fi
  else
    printf '%s' "no render-c4-model.sh beside this resolver ($PLUGIN_SCRIPTS_DIR) and CLAUDE_PLUGIN_ROOT is unset"
    return 1
  fi
  [[ -n "$root" ]] || { printf '%s' "could not resolve the plugin root from $src"; return 1; }
  if ! grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "$root/.claude-plugin/plugin.json" 2>/dev/null; then
    printf '%s' "$root/.claude-plugin/plugin.json (from $src) does not name soleur"
    return 1
  fi
  printf '%s' "$root"
}

# ── THE RESOLVABLE SET ─────────────────────────────────────────────────────────────────────
# One hardcoded path -> command pair. NOT a manifest file, deliberately: a manifest is a
# parse surface, and worse, it invites re-tracking generated files by making the list feel
# cheap to extend. Adding a second member is an edit HERE plus an ADR-235 amendment, so the
# cache-vs-product question gets asked each time.
#
# THE SEAM IS ARGV, NOT THE ENVIRONMENT, AND THE COMMAND IS AN ARGV VECTOR, NOT A STRING.
# Both halves are load-bearing and both were defects (#8384 review):
#
#   1. This ran `eval "$cmd"` on the command column. `eval` needs a shell for a value that is
#      a fixed argv -- so the default arm was eval'd too, for no benefit.
#   2. The seam was `RESOLVABLE_OVERRIDE`, an ordinary INHERITED environment variable, read
#      with no validation but `[[ -f ]]` and no test-mode gate. "TEST SEAM ONLY ... Nothing in
#      production sets it" is a statement about who DOES set it, not who CAN. All three
#      production call sites (sync-pr-behind.sh, pre-merge-rebase.sh, ship Phase 7) invoke
#      this script with a plain inherited environment, and pre-merge-rebase.sh does so from a
#      PreToolUse hook on `gh pr merge` with stdout and stderr discarded. Demonstrated: one
#      exported variable made this script run an arbitrary command, side-pick a conflicted
#      file to attacker-chosen content, COMMIT the merge and exit 0 -- whereupon the caller
#      pushes it.
#
# argv cannot be inherited. A caller who can set this script's argv can already run anything;
# a caller who merely exports a variable cannot. The flag is accepted only as argument 1.
#
# EVERY ARGV HAS A NAMED SOURCE. Each line that produces one carries a trailing ARGV-SOURCE
# marker, and resolve-regenerable-conflicts.test.sh pins the set of names. The production
# source is `plugin`: a renderer resolved by plugin_root(), never a path in the repo being
# merged -- which is what makes this work in a self-hosted repo that has no scripts/ of ours
# (#8542 follow-up; ADR-235 amendment). Its argv carries --root because the renderer's CODE
# comes from the plugin and only its DATA from the repository.
RESOLVABLE_PATHS=()
RESOLVABLE_ARGVS=()   # one TAB-joined argv vector per path, index-aligned with the above
ARM=""; ARM_ROOT="-"
if [[ "${1:-}" == "--test-resolvable" ]]; then
  _tsv="${2:-}"
  [[ -f "$_tsv" ]] || na "--test-resolvable: '$_tsv' is not a file"
  while IFS=$'\t' read -r _p _rest; do
    [[ -n "$_p" ]] || continue
    RESOLVABLE_PATHS+=("$_p"); RESOLVABLE_ARGVS+=("$_rest")  # ARGV-SOURCE: test-seam
  done < "$_tsv"
  shift 2
  ARM="test-seam"
else
  _root_or_why="$(plugin_root)" \
    || na "no Soleur plugin root: ${_root_or_why} — run the merge by hand: git merge <base>; bash <plugin-root>/scripts/render-c4-model.sh; git add knowledge-base/engineering/architecture/diagrams/model.likec4.json; git commit --no-edit"
  ARM="plugin"; ARM_ROOT="$_root_or_why"
  RESOLVABLE_PATHS=("knowledge-base/engineering/architecture/diagrams/model.likec4.json")  # RESOLVABLE-SET: default
  RESOLVABLE_ARGVS=("$(printf 'bash\t%s\t--root\t%s' "$ARM_ROOT/scripts/render-c4-model.sh" "$REPO_ROOT")")  # ARGV-SOURCE: plugin
fi

BASE="${1:-}"
[[ -n "$BASE" ]] || na "no base ref given — re-run as: resolve-regenerable-conflicts.sh <base-ref> (e.g. origin/main)"

cd "$REPO_ROOT" || na "cannot enter repo root $REPO_ROOT — check its permissions and re-run"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || na "not inside a git work tree"
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || na "base ref '$BASE' does not resolve to a commit — git fetch it first"

# is_resolvable <path> -> echoes the TAB-joined argv, or returns 1.
is_resolvable() {
  local want="$1" i
  for i in "${!RESOLVABLE_PATHS[@]}"; do
    if [[ "${RESOLVABLE_PATHS[$i]}" == "$want" ]]; then
      printf '%s' "${RESOLVABLE_ARGVS[$i]}"
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
[[ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]] || na "a merge is already in progress — finish it or run git merge --abort, then re-run"
[[ -z "$(git status --porcelain)" ]] || na "working tree is not clean — commit or discard your changes, then re-run"

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
  na "no conflict between HEAD and $BASE — nothing to resolve; merge it normally"
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
      na "unresolvable conflict kind: $line — resolve this merge by hand"
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
  c="$(is_resolvable "$p")" || na "conflicted path is not regenerable: $p — resolve this merge by hand"
  cmds+=("$c")
done

# ── NO UNTRACKED SOURCE MAY FEED THE REGEN (P5) ────────────────────────────────────────────
# likec4 compiles every .c4 under the directory it is pointed at, tracked or not. In a customer
# repo generated-components.c4 is written by soleur:sync and need not be committed, so without
# this the merge commit could carry a model rendered from a machine-local file the merge never
# saw -- a diagram nobody else can reproduce. `--others` WITHOUT --exclude-standard lists
# IGNORED files too, on purpose: an untracked non-ignored one already fails the clean-tree
# precondition above, so ignored ones are the only kind that reach here.
for p in "${conflicted[@]}"; do
  _src_dir="$(dirname -- "$p")"
  _untracked_src="$(git ls-files --others -- "$_src_dir" 2>/dev/null | grep -E '\.(c4|likec4)$' | head -1 || true)"
  [[ -z "$_untracked_src" ]] \
    || na "untracked source $_untracked_src would be compiled into the regenerated model but is not part of the merge — commit it or delete it, then re-run"
done

# ── APPLY ──────────────────────────────────────────────────────────────────────────────────
# --no-ff so the merge is always recorded as a merge; --no-commit so the regenerated artifact
# is part of the merge commit rather than a follow-up.
# THE MERGE MUST ACTUALLY HAVE STARTED. This was `|| true` with stderr discarded, and that
# is the one path where this script both writes and commits something it should not: if the
# merge fails for any reason OTHER than a content conflict -- a held index.lock, refusing to
# clobber an ignored working-tree file, merge.verifySignatures, ENOSPC -- there is no
# MERGE_HEAD and no conflict, so the regen ran, `git add` succeeded, `residual` came back
# empty, and `git commit --no-edit` created an ORDINARY NON-MERGE commit and exited 0. Every
# caller reads 0 as "merged, go push" (sync-pr-behind.sh then SKIPS the real merge). Measured
# in review: rc=1 with `M  gen.txt` still STAGED, against a header promising byte-identical.
merge_err="$(git merge --no-ff --no-commit "$BASE" 2>&1 >/dev/null)" || true
if [[ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]]; then
  git merge --abort 2>/dev/null || true
  _dirty="$(git status --porcelain)"
  if [[ -n "$_dirty" ]]; then
    echo "[regen-on-conflict] regen failed: the merge did not start AND the tree is not clean — resolve by hand: $(tr '\n' ' ' <<<"$_dirty")" >&2
  else
    echo "[regen-on-conflict] not applicable: the merge did not start: ${merge_err:-no output}" >&2
  fi
  exit 1
fi

# A regen is a 10-60s network operation (npx likec4) running while MERGE_HEAD is live. Without
# this, a SIGINT or a killed session leaves the worktree mid-merge carrying conflict markers --
# a third state the two-outcome contract does not admit.
trap 'git merge --abort 2>/dev/null || true' INT TERM HUP

for i in "${!conflicted[@]}"; do
  p="${conflicted[$i]}"
  # Re-check the symlink HERE, not only at entry: the merge just wrote the worktree, and a
  # symlink committed on the base side arrives as one.
  if [[ -L "$p" ]]; then
    bail "not applicable: refusing to write through symlink $p"
  fi
  # argv, never `eval` -- see THE RESOLVABLE SET above.
  IFS=$'\t' read -r -a _argv <<< "${cmds[$i]}"
  [[ "${#_argv[@]}" -gt 0 ]] || bail "regen failed: empty command for $p"
  # DELETE THE PATH BEFORE REGENERATING, so "the regen did not write this path" becomes "the
  # path does not exist" -- which the `-e` check below already catches. Without this the only
  # evidence that the command touched $p is the conflict-marker grep, and git writes NO markers
  # for a path it treats as BINARY: it marks the path UU and leaves OURS-content in place, so
  # the file reads clean and a no-op regen commits the ours-side artifact at rc=0. That is
  # side-picking dressed as a regeneration -- the exact outcome this script exists to prevent.
  # (Demonstrated in review against a `*.likec4.json binary` attribute. The root .gitattributes
  # re-added by #8542 sets ONLY `linguist-generated` on the artifact, and
  # plugins/soleur/test/c4-canonical.test.ts fails if a binary/-diff/-merge attribute joins it.)
  # Safe for the one production member: render-c4-model.sh reads the .c4 sources, never its
  # own output. A future incremental generator would need a different discriminator.
  rm -f -- "$p"
  # The output is CAPTURED, not discarded: the renderer's diagnostic is its only observability
  # surface, and `bail` used to be able to name only the argv. `timeout` is GNU coreutils and
  # absent from stock macOS, so its absence runs the arm unbounded rather than refusing.
  _to=()
  command -v timeout >/dev/null 2>&1 && _to=(timeout -k 10 "$REGEN_TIMEOUT_S")
  echo "[regen-on-conflict] regenerating $p with ${_argv[*]} (runs likec4 through npx; a cold cache takes minutes)" >&2
  _regen_rc=0
  _regen_out="$(${_to[@]+"${_to[@]}"} "${_argv[@]}" 2>&1)" || _regen_rc=$?
  if [[ "$_regen_rc" -ne 0 ]]; then
    _why="exited $_regen_rc"
    [[ "$_regen_rc" -eq 124 && "${#_to[@]}" -gt 0 ]] && _why="timed out after ${REGEN_TIMEOUT_S}s"
    bail "regen failed: '${_argv[*]}' $_why for $p: $(tail -n 4 <<<"$_regen_out" | tr '\n' '|' | sed 's/|$//; s/|/ | /g')"
  fi
  [[ -e "$p" ]] || bail "regen failed: '${_argv[*]}' did not produce $p"
  # THE REGENERATED FILE MUST NOT STILL CARRY MARKERS. `git add` on a conflicted path marks it
  # resolved with whatever bytes are in the worktree -- so a regen command that silently did
  # not touch THIS path would otherwise have its conflict markers staged and committed as the
  # artifact. The residual `--diff-filter=U` check below cannot see that: staging is exactly
  # what clears the U flag. Measured: without this, a two-path fixture whose command
  # regenerates only the first commits the second with `<<<<<<<` in it.
  if grep -qE '^(<{7}|={7}|>{7})( |$)' -- "$p" 2>/dev/null; then
    bail "regen failed: $p still contains conflict markers after '${_argv[*]}'"
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

# ── THE REGEN WROTE EXACTLY THE CONFLICTED PATHS (P3) ──────────────────────────────────────
# Everything the loop meant to write is STAGED by now, so anything still unstaged or untracked
# was written by a regen command beside its own artifact -- a cache, a temp file, a seed. The
# commit below would leave it behind (or, once staged by a later change, carry it into a merge
# commit), and the next run's clean-tree precondition would refuse. Arm-agnostic, so it holds
# for any future member of the resolvable set.
#
# The unwind has to be EXPLICIT: `git merge --abort` is `reset --merge`, which deliberately
# KEEPS unstaged changes and never touches untracked files. The tree was verified clean at
# entry, so every path listed here was written during this run and is ours to discard.
_stray_mod="$(git diff --name-only)"
_stray_new="$(git ls-files --others --exclude-standard)"
if [[ -n "$_stray_mod$_stray_new" ]]; then
  git merge --abort 2>/dev/null || true
  while IFS= read -r _f; do [[ -n "$_f" ]] && git checkout -q HEAD -- "$_f" 2>/dev/null; done <<<"$_stray_mod"
  while IFS= read -r _f; do [[ -n "$_f" ]] && rm -f -- "$_f"; done <<<"$_stray_new"
  echo "[regen-on-conflict] regen failed: the regen wrote outside the conflicted paths: $(printf '%s\n%s' "$_stray_mod" "$_stray_new" | tr '\n' ' ') — nothing was committed; report it against the renderer" >&2
  exit 1
fi

git commit --no-edit >/dev/null 2>&1 || bail "regen failed: merge commit failed"

csv="$(IFS=,; printf '%s' "${conflicted[*]}")"
printf 'SOLEUR_REGEN_ON_CONFLICT paths=%s arm=%s root=%s rc=0\n' "$csv" "$ARM" "$ARM_ROOT"
