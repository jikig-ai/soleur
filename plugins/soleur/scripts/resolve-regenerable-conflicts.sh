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
# take the merged SOURCES and re-run the generator over them. The one such product is
# knowledge-base/engineering/architecture/diagrams/model.likec4.json, which the web-platform C4
# viewer fetches as a committed blob (apps/web-platform/app/api/kb/c4/project/route.ts).
#
# ── THE CONTRACT: TWO OUTCOMES ─────────────────────────────────────────────────────────────
#   exit 0       the merge completed and was COMMITTED. The caller may push.
#   exit non-0   nothing was touched. The tree is byte-identical to entry.
# Every exit prints one stdout line `SOLEUR_REGEN_ON_CONFLICT … rc=N` (rc=1 carries
# class=na|failed|interrupted and a reason slug) and, on refusal, one human line on stderr
# prefixed `[regen-on-conflict]` naming the next action.
#
# ── HOW: RENDER FROM GIT OBJECTS FIRST, TOUCH THE WORKTREE LAST (ADR-235 amendment 2026-09-23)
#   1. `git merge-tree` computes the merge without touching anything and yields the merged TREE.
#   2. The tracked, cleanly-merged LikeC4 sources are copied out of that tree's OBJECTS into a
#      private staging dir, and the renderer runs there. Nothing untracked, ignored, symlinked
#      or configured in the worktree can reach the render, and the renderer cannot write the
#      worktree. Every render failure, timeout or kill therefore happens with the tree untouched.
#   3. Only then: re-check nothing moved, `git merge --no-commit`, write the rendered bytes,
#      assert the index is exactly the merged tree plus those bytes, commit, and assert no commit
#      hook changed the result.
#
# NEVER PUSHES — callers own the push. NO LOCK — per-worktree index/HEAD/MERGE_HEAD serialise
# runs within a worktree; the HEAD and clean-tree re-checks make a lost race refuse.
set -uo pipefail

# The PLUGIN directory: this script's own, made absolute before any `cd` (ADR-179 A17).
_plugin_scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || _plugin_scripts_dir=""
readonly PLUGIN_SCRIPTS_DIR="$_plugin_scripts_dir"
# The REPO: the caller's, from the CWD — never BASH_SOURCE/../.., which is the plugin.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# The render budget, matching generate-c4-from-components.ts (a cold npx install measured 151s).
REGEN_TIMEOUT_S=600
BASE=""; BASE_SHA=""; HEAD_SHA=""; ARM=""; ROOT_SRC="-"
WORK=""; RENDER_PID=""; MERGING=0

# One line per exit for machines (stdout), one for humans (stderr).
_marker() { printf 'SOLEUR_REGEN_ON_CONFLICT rc=1 class=%s reason=%s\n' "$1" "$2"; }
# Strip control characters: the tail of a renderer log is attacker-influenced text.
_clean() { LC_ALL=C tr -d '\000-\011\013-\037\177' | tail -n 4 | tr '\n' '|' | sed 's/|$//; s/|/ | /g'; }

# na <slug> <message> — refuse before anything was touched.
na() { _marker na "$1"; echo "[regen-on-conflict] not applicable: $2" >&2; exit 1; }
# fail <slug> <message> — a regeneration problem, still before anything was touched.
fail() { _marker failed "$1"; echo "[regen-on-conflict] regen failed: $2" >&2; exit 1; }
# bail <slug> <message> — refuse AFTER the merge started: unwind, and VERIFY the unwind.
bail() {
  _marker failed "$1"
  local unwound="merge aborted, nothing committed"
  [[ -n "$REPO_ROOT" ]] && git -C "$REPO_ROOT" merge --abort 2>/dev/null
  if [[ -n "$REPO_ROOT" && -f "$(git -C "$REPO_ROOT" rev-parse --git-dir 2>/dev/null)/MERGE_HEAD" ]]; then
    unwound="could NOT unwind: a merge is still in progress — run: git merge --abort"
  fi
  echo "[regen-on-conflict] regen failed: $2 — $unwound" >&2
  exit 1
}

_cleanup() {
  [[ -n "$RENDER_PID" ]] && kill -TERM "$RENDER_PID" 2>/dev/null
  [[ -n "$WORK" && -d "$WORK" ]] && rm -rf -- "$WORK"
}
_on_signal() {
  if [[ "$MERGING" -eq 1 ]]; then
    bail interrupted "interrupted during the merge"
  fi
  _cleanup
  _marker interrupted signal
  echo "[regen-on-conflict] interrupted — nothing was touched; re-run when ready" >&2
  exit 1
}
trap _cleanup EXIT
trap _on_signal INT TERM HUP

[[ -n "$REPO_ROOT" ]] || na not-a-repo "not inside a git work tree — cd into the repository being merged and re-run"

# plugin_root -> sets PLUGIN_ROOT and ROOT_SRC (no subshell, so both survive), or returns 1 with
# the reason in PLUGIN_ROOT_WHY. The sibling wins; a bare ${CLAUDE_PLUGIN_ROOT}
# (no `:-`, ADR-179 A12) is read only when it is absent. The plugin.json check is a sanity
# check, not a boundary (ADR-179 A11, A17).
PLUGIN_ROOT=""; PLUGIN_ROOT_WHY=""
plugin_root() {
  local root=""
  if [[ -n "$PLUGIN_SCRIPTS_DIR" && -f "$PLUGIN_SCRIPTS_DIR/render-c4-model.sh" ]]; then
    root="$(cd "$PLUGIN_SCRIPTS_DIR/.." 2>/dev/null && pwd -P)" || root=""
    ROOT_SRC="sibling"
  elif [[ -n "${CLAUDE_PLUGIN_ROOT+set}" && "${CLAUDE_PLUGIN_ROOT}" == /* ]]; then
    root="$(cd "${CLAUDE_PLUGIN_ROOT}" 2>/dev/null && pwd -P)" || root=""
    ROOT_SRC="env"
    if [[ -z "$root" || ! -f "$root/scripts/render-c4-model.sh" ]]; then
      PLUGIN_ROOT_WHY="CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} has no scripts/render-c4-model.sh"
      return 1
    fi
  else
    PLUGIN_ROOT_WHY="no render-c4-model.sh beside this resolver and no absolute CLAUDE_PLUGIN_ROOT"
    return 1
  fi
  [[ -n "$root" ]] || { PLUGIN_ROOT_WHY="could not resolve the plugin root"; return 1; }
  if ! grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "$root/.claude-plugin/plugin.json" 2>/dev/null; then
    PLUGIN_ROOT_WHY="$root/.claude-plugin/plugin.json does not name soleur"
    return 1
  fi
  PLUGIN_ROOT="$root"
}

# ── THE RESOLVABLE SET ─────────────────────────────────────────────────────────────────────
# One hardcoded member, not a manifest (ADR-235: a manifest is a parse surface and invites
# re-tracking generated files). The test seam is ARGV-only (--test-resolvable <tsv>): an
# inherited env var reaching an unattended commit was a demonstrated command channel (#8384).
# Each argv-producing line carries an ARGV-SOURCE marker; the suite pins the set. An arm's argv
# is a PREFIX: the resolver appends `--root <staging> --out <file>`.
RESOLVABLE_PATHS=()
RESOLVABLE_ARGVS=()   # one TAB-joined argv prefix per path, index-aligned with the above
if [[ "${1:-}" == "--test-resolvable" ]]; then
  _tsv="${2:-}"
  [[ -f "$_tsv" ]] || na bad-args "--test-resolvable: '$_tsv' is not a file"
  while IFS=$'\t' read -r _p _rest; do
    [[ -n "$_p" ]] || continue
    RESOLVABLE_PATHS+=("$_p"); RESOLVABLE_ARGVS+=("$_rest")  # ARGV-SOURCE: test-seam
  done < "$_tsv"
  shift 2
  ARM="test-seam"
else
  RESOLVABLE_PATHS=("knowledge-base/engineering/architecture/diagrams/model.likec4.json")  # RESOLVABLE-SET: default
  ARM="plugin"
fi

BASE="${1:-}"
[[ -n "$BASE" ]] || na bad-args "no base ref given — re-run as: resolve-regenerable-conflicts.sh <base-ref> (e.g. origin/main)"
cd "$REPO_ROOT" || na not-a-repo "cannot enter repo root $REPO_ROOT"
BASE_SHA="$(git rev-parse --verify --quiet "$BASE^{commit}")" \
  || na bad-base "base ref '$BASE' does not resolve to a commit — git fetch it first"
HEAD_SHA="$(git rev-parse --verify --quiet HEAD)" || na no-head "HEAD does not resolve to a commit"

# _clean_or_why -> empty when the tree is clean for our purposes, else the reason.
# MERGE_HEAD first (its remedy differs). `-uall` so status.showUntrackedFiles=no cannot hide an
# untracked file; `--ignored` is NOT used — ignored files are invisible to the merge unless the
# merged tree adds the same path, which _collisions checks.
_clean_or_why() {
  [[ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]] || { printf 'a merge is already in progress — finish it or run git merge --abort'; return; }
  [[ -z "$(git status --porcelain --untracked-files=all)" ]] || printf 'working tree is not clean — commit or discard your changes'
}
_why="$(_clean_or_why)"; [[ -z "$_why" ]] || na dirty-tree "$_why, then re-run"

# ── CLASSIFY: merge-tree, NUL-framed ───────────────────────────────────────────────────────
WORK_PARENT="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/soleur"
if mkdir -p "$WORK_PARENT" 2>/dev/null && chmod 700 "$WORK_PARENT" 2>/dev/null && WORK="$(mktemp -d "$WORK_PARENT/regen.XXXXXX")"; then :
else fail no-staging "cannot create a private staging dir under $WORK_PARENT"; fi
chmod 700 "$WORK"

mt_rc=0
git merge-tree --write-tree -z --name-only "$BASE_SHA" "$HEAD_SHA" >"$WORK/mt" 2>"$WORK/mt.err" || mt_rc=$?
[[ "$mt_rc" -ne 0 ]] || na no-conflict "no conflict between HEAD and $BASE — nothing to resolve; merge it normally"
if [[ "$mt_rc" -ge 2 ]]; then
  grep -q 'unknown option\|usage: git merge-tree' "$WORK/mt.err" 2>/dev/null \
    && na old-git "git merge-tree --write-tree needs git >= 2.38 (you have $(git --version | cut -d' ' -f3)) — upgrade git, or resolve by hand"
  na merge-tree-failed "git merge-tree failed (rc=$mt_rc): $(_clean <"$WORK/mt.err")"
fi

# Records: <tree> NUL, conflicted paths NUL…, empty NUL, then messages as
# <N> NUL <N paths> NUL <type> NUL <text> NUL. Only a CONFLICT (contents) is resolvable: every
# other kind (modify/delete, rename/rename, add/add, distinct types) decides whether a file
# should EXIST, which regenerating cannot answer.
TREE=""; conflicted=(); content_ok=$'\x1f'
_state=tree; _n=0; _mpaths=()
while IFS= read -r -d '' rec; do
  case "$_state" in
    tree) TREE="$rec"; _state=paths ;;
    paths) if [[ -z "$rec" ]]; then _state=count; else conflicted+=("$rec"); fi ;;
    count)
      _n="$rec"; _mpaths=()
      [[ "$_n" =~ ^[0-9]+$ ]] || na merge-tree-format "unparseable merge-tree output"
      if [[ "$_n" -eq 0 ]]; then _state="type"; else _state="mpath"; fi ;;
    mpath) _mpaths+=("$rec"); [[ "${#_mpaths[@]}" -lt "$_n" ]] || _state="type" ;;
    type) _type="$rec"; _state=text ;;
    text)
      case "$_type" in
        "CONFLICT (contents)") for _mp in ${_mpaths[@]+"${_mpaths[@]}"}; do content_ok+="$_mp"$'\x1f'; done ;;
        CONFLICT*) na unresolvable-kind "$(printf '%s' "$rec" | _clean) — resolve this merge by hand" ;;
      esac
      _state=count ;;
  esac
done <"$WORK/mt"
[[ "$TREE" =~ ^[0-9a-f]{40,64}$ && "${#conflicted[@]}" -gt 0 ]] \
  || na merge-tree-format "merge-tree reported rc=$mt_rc but no conflicted path was parsed"

_argv_for() {  # <path> -> echoes the TAB-joined argv prefix, or returns 1
  local i
  for i in "${!RESOLVABLE_PATHS[@]}"; do
    [[ "${RESOLVABLE_PATHS[$i]}" == "$1" ]] && { printf '%s' "${RESOLVABLE_ARGVS[$i]:-}"; return 0; }
  done
  return 1
}
for p in "${conflicted[@]}"; do
  [[ "$content_ok" == *$'\x1f'"$p"$'\x1f'* ]] \
    || na unresolvable-kind "$p is not a plain content conflict — resolve this merge by hand"
  _argv_for "$p" >/dev/null || na not-regenerable "conflicted path is not regenerable: $p — resolve this merge by hand"
done

# The production arm is resolved only now that a regenerable conflict exists.
if [[ "$ARM" == "plugin" ]]; then
  plugin_root \
    || fail no-plugin-root "no usable Soleur plugin root ($PLUGIN_ROOT_WHY) — set CLAUDE_PLUGIN_ROOT to the installed plugin (the directory whose .claude-plugin/plugin.json names soleur) and re-run"
  RESOLVABLE_ARGVS=("$(printf 'bash\t%s' "$PLUGIN_ROOT/scripts/render-c4-model.sh")")  # ARGV-SOURCE: plugin
fi

# ── STAGE: tracked sources out of the merged tree's objects ────────────────────────────────
# Allowlist, not blocklist: only regular-file LikeC4 sources are copied. A symlink or gitlink
# anywhere under the directory, or a likec4 config (which likec4 would load, the js/ts forms as
# code), is REFUSED rather than skipped — rendering without it would not be the repo's model.
STAGE="$WORK/root"; OUT="$WORK/out"; mkdir -p "$STAGE" "$OUT"
_staged_dirs=$'\x1f'
for p in "${conflicted[@]}"; do
  _dir="$(dirname -- "$p")"
  [[ "$_staged_dirs" == *$'\x1f'"$_dir"$'\x1f'* ]] && continue
  _staged_dirs+="$_dir"$'\x1f'
  git ls-tree -r -z --full-tree "$TREE" -- "$_dir/" >"$WORK/ls" 2>/dev/null \
    || fail stage-failed "could not list $_dir in the merged tree"
  while IFS= read -r -d '' ent; do
    _meta="${ent%%$'\t'*}"; _path="${ent#*$'\t'}"
    _mode="${_meta%% *}"; _obj="${_meta##* }"
    case "/$_path/" in */../*|*/./*) na unsafe-path "refusing path $_path in the merged tree" ;; esac
    case "$_mode" in
      120000) na symlink-source "$_path is a symlink in the merged tree — the renderer would follow it outside the merge; replace it with a regular file" ;;
      160000) na gitlink-source "$_path is a submodule in the merged tree — its sources are not part of the merge" ;;
    esac
    case "${_path##*/}" in
      likec4.config.*|.likec4rc|.likec4.config.json)
        na likec4-config "$_path would configure the render (the .js/.ts forms run as code) — regenerate by hand" ;;
    esac
    [[ "$_mode" == 100644 || "$_mode" == 100755 ]] || continue
    case "$_path" in
      *.c4|*.likec4|*.like-c4)
        mkdir -p "$STAGE/$(dirname -- "$_path")"
        git cat-file blob "$_obj" >"$STAGE/$_path" || fail stage-failed "could not read $_path from the merged tree"
        chmod 600 "$STAGE/$_path" ;;
    esac
  done <"$WORK/ls"
done
for p in "${conflicted[@]}"; do
  _m="$(git ls-tree -z --full-tree "$TREE" -- "$p" | cut -d' ' -f1)"
  [[ "$_m" == 100644 || "$_m" == 100755 ]] || na not-a-file "$p is not a regular file in the merged tree — resolve this merge by hand"
done

# ── RENDER, in the background so a signal is handled at once ──────────────────────────────
_to=()
if command -v timeout >/dev/null 2>&1; then _to=(timeout -k 10 "$REGEN_TIMEOUT_S")
elif command -v gtimeout >/dev/null 2>&1; then _to=(gtimeout -k 10 "$REGEN_TIMEOUT_S"); fi
outs=()
for i in "${!conflicted[@]}"; do
  p="${conflicted[$i]}"
  IFS=$'\t' read -r -a _argv <<<"$(_argv_for "$p")"
  [[ "${#_argv[@]}" -gt 0 ]] || fail empty-command "empty regeneration command for $p"
  out="$OUT/$i"; outs+=("$out")
  echo "[regen-on-conflict] regenerating $p (runs likec4 through npx; a cold cache takes minutes)" >&2
  ${_to[@]+"${_to[@]}"} "${_argv[@]}" --root "$STAGE" --out "$out" >"$WORK/log.$i" 2>&1 &
  RENDER_PID=$!
  _rc=0; wait "$RENDER_PID" || _rc=$?
  RENDER_PID=""
  if [[ "$_rc" -ne 0 ]]; then
    _w="exited $_rc"; [[ "$_rc" -eq 124 && "${#_to[@]}" -gt 0 ]] && _w="timed out after ${REGEN_TIMEOUT_S}s"
    fail render-failed "the renderer $_w for $p: $(_clean <"$WORK/log.$i")"
  fi
  [[ -s "$out" ]] || fail no-output "the renderer did not produce $p"
  ! grep -qE '^(<{7}|={7}|>{7})( |$)' -- "$out" || fail markers "the rendered $p still contains conflict markers"
done

# ── APPLY: only now is the worktree touched ────────────────────────────────────────────────
[[ "$(git rev-parse --verify --quiet HEAD)" == "$HEAD_SHA" ]] \
  || na head-moved "HEAD moved during the render — nothing was touched; re-run"
_why="$(_clean_or_why)"; [[ -z "$_why" ]] || na dirty-tree "the worktree changed during the render ($_why) — nothing was touched; re-run"
# A path the merge ADDS that exists on disk (untracked or ignored) would be overwritten.
while IFS= read -r -d '' _a; do
  [[ -e "$_a" || -L "$_a" ]] && na would-overwrite "the merge adds $_a, which exists here untracked or ignored — move it aside and re-run"
done < <(git diff -z --name-only --diff-filter=A "$HEAD_SHA" "$TREE")

MERGING=1
merge_err="$(git merge --no-ff --no-commit -m "Merge $BASE (${BASE_SHA:0:12}); regenerated ${conflicted[*]}" "$BASE_SHA" 2>&1 >/dev/null)" || true
if [[ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]]; then
  bail merge-not-started "the merge did not start: $(printf '%s' "${merge_err:-no output}" | _clean)"
fi
for i in "${!conflicted[@]}"; do
  p="${conflicted[$i]}"
  [[ ! -L "$p" ]] || bail symlink-artifact "refusing to write through symlink $p"
  cp -- "${outs[$i]}" "$p" && git add -- "$p" || bail stage-failed "could not write $p"
  [[ "$(git rev-parse ":$p")" == "$(git hash-object --path="$p" -- "${outs[$i]}")" ]] \
    || bail staged-mismatch "the staged $p is not the rendered bytes"
done
[[ -z "$(git diff --name-only --diff-filter=U)" ]] || bail residual-conflict "conflicts remain after regeneration"
# The index must be exactly the merged tree plus the regenerated paths — nothing else.
_want="$(printf '%s\n' "${conflicted[@]}" | LC_ALL=C sort)"
_got="$(git diff --cached -z --name-only "$TREE" | tr '\0' '\n' | LC_ALL=C sort)"
[[ "$_got" == "$_want" ]] || bail index-mismatch "the index differs from the merged tree beyond the regenerated paths: $(printf '%s' "$_got" | _clean)"

_expect_tree="$(git write-tree)" || bail write-tree "could not write the index tree"
trap - INT TERM HUP   # a signal during `git commit` must not report "nothing committed"
commit_err="$(git commit --no-edit 2>&1 >/dev/null)" \
  || bail commit-failed "the merge commit failed: $(printf '%s' "$commit_err" | _clean)"
MERGING=0
if [[ "$(git rev-parse "HEAD^{tree}")" != "$_expect_tree" || "$(git rev-parse HEAD^1)" != "$HEAD_SHA" \
      || "$(git rev-parse HEAD^2 2>/dev/null)" != "$BASE_SHA" ]]; then
  git reset -q --keep "$HEAD_SHA" 2>/dev/null
  _marker failed commit-hook-changed-tree
  echo "[regen-on-conflict] regen failed: a commit hook changed the merge commit — it was undone; resolve by hand" >&2
  exit 1
fi

csv="$(IFS=,; printf '%s' "${conflicted[*]}")"
printf 'SOLEUR_REGEN_ON_CONFLICT paths=%s arm=%s root_src=%s rc=0\n' "$csv" "$ARM" "$ROOT_SRC"
