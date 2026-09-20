#!/usr/bin/env bash
# ensure-kb-index.sh — regenerate the knowledge-base index if, and only if, it is stale.
#
# Usage: bash scripts/ensure-kb-index.sh [--help] [--soft]
#
# Flags:
#   --soft   Never fail the caller. Every error becomes a `WARN:` line and the
#            exit status is 0. Used by the `prepare` lifecycle script and by the
#            SessionStart hooks, where a malformed knowledge-base/ must not break
#            `bun install` or refuse to start a session.
#
# WHY THIS SCRIPT EXISTS (#8377, ADR-230). knowledge-base/INDEX.md, kb-tags.txt and
# kb-categories.txt are CACHES: pure functions of the tree, so ADR-230 untracks them and
# regenerates them on demand instead of committing them. That removed a whole defect class —
# a file that is never committed can never conflict, and these three conflicted on almost
# every advance of main (42 of 71 first-parent commits in the 7 days before the change) —
# but it moves the freshness obligation to READ TIME. Every reader calls this first.
#
# THE PROBE IS A CONTENT FINGERPRINT, NOT AN MTIME COMPARISON, and that is the one design
# decision here worth defending. An mtime probe cannot see a timestamp-preserving edit — a
# `cp -p`, an `rsync -a`, or a `git checkout` of an older blob leaves eligible content changed
# and the file OLDER than the stamp. The failure is silent and lands exactly on the reader:
# it greps an index that does not list what is on disk and reports "no prior art". So the
# probe hashes `git ls-files -s` (blob ids for tracked content) concatenated with
# `git status --porcelain -uall` (paths for modified and untracked files), both scoped to
# knowledge-base/. It costs ~60 ms against a ~3 s regeneration.
#
# THE RESIDUE, STATED HONESTLY: an edit to a GITIGNORED file under knowledge-base/ (a local
# private/ note) is invisible to both halves of the fingerprint. No Property requires it, and
# the next tracked change picks it up. An earlier draft paired this with a `find -newer` mtime
# probe to cover it; that is two mechanisms for one property, and the mtime half could not
# cover the row above, so it was cut.
#
# PORTABILITY. No `sha1sum`, `date +%N`, `stat -c`, `readlink -f` or `timeout` appears here:
# none of them is on a stock macOS host. `git hash-object` does the hashing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KB_DIR="${KB_DIR:-$REPO_ROOT/knowledge-base}"
KB_DIR="${KB_DIR%/}"
GENERATOR="$SCRIPT_DIR/generate-kb-index.sh"
STAMP="$KB_DIR/.kb-index.stamp"
TARGETS=(INDEX.md kb-tags.txt kb-categories.txt)

SOFT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      sed -n '2,/^$/s/^# //p' "$0"
      exit 0
      ;;
    --soft) SOFT=1; shift ;;
    *)
      echo "ERROR: unknown argument '$1' (see --help)" >&2
      exit 2
      ;;
  esac
done

# die <exit-code> <message> — the single exit path for every failure.
#
# Under --soft this downgrades to WARN and exits 0, which is what makes the script safe to
# put in `prepare` and SessionStart. The DISTINCTION IS KEPT IN THE TEXT, not only in the
# status: a caller that swallowed the code can still see which happened in its log.
die() {
  local code="$1"; shift
  if [[ "$SOFT" == 1 ]]; then
    echo "WARN: $*" >&2
    exit 0
  fi
  echo "ERROR: $*" >&2
  exit "$code"
}

# Nothing to index. Not an error: this script runs from `prepare` in checkouts that may not
# carry a knowledge-base/ at all (a customer repo, a partial clone, a docs-only worktree).
[[ -d "$KB_DIR" ]] || exit 0

# ── SYMLINK REFUSAL, BEFORE ANYTHING IS READ OR WRITTEN ────────────────────────────────────
# `mv -f` onto a symlink REPLACES the link, but the generator's own `--out` write and any
# future in-place write would follow it. A planted link at one of these paths is an
# arbitrary-file-write primitive, so refuse the whole run rather than skipping one target:
# a partial regeneration is a worse outcome than none, because it reads as success.
for _t in "${TARGETS[@]}" ".kb-index.stamp"; do
  if [[ -L "$KB_DIR/$_t" ]]; then
    die 3 "refusing to write through symlink $KB_DIR/$_t"
  fi
done

# ── FRESHNESS ──────────────────────────────────────────────────────────────────────────────
# Two independent reasons to regenerate, checked in this order because absence is cheaper and
# is NOT implied by staleness: a fingerprint can match while kb-tags.txt has been deleted.
REASON=""
for _t in "${TARGETS[@]}" ".kb-index.stamp"; do
  if [[ ! -f "$KB_DIR/$_t" ]]; then
    REASON="absent"
    break
  fi
done

# fingerprint — blob ids for tracked content plus paths for modified/untracked files.
#
# THE GENERATED PATHS ARE EXCLUDED EXPLICITLY, and that exclusion is load-bearing rather
# than tidiness. The four outputs live INSIDE knowledge-base/, so without it every
# regeneration changes the very quantity the next run compares against: the artifacts land
# as untracked files, `git status -uall` lists them, the fingerprint moves, and the script
# regenerates on EVERY call forever. `.gitignore` happens to hide them in this repo, which
# is exactly what makes the bug dangerous — the probe would be correct here and wrong in any
# checkout whose ignore rules differ, and the failure mode is a silent 3 s tax on every read.
# Excluding them here makes the probe a function of the SOURCES alone.
#
# EMPTY OUTSIDE A CHECKOUT, deliberately. Both git commands fail there, and an empty
# fingerprint hashes to a stable value, so the script regenerates on its first call (the
# stamp is absent) and then no-ops. That is the correct behaviour for an exported tarball:
# generate once, then stop paying for it.
fingerprint() {
  {
    git -C "$KB_DIR" ls-files -s -- . \
      ':(exclude)INDEX.md' ':(exclude)kb-tags.txt' ':(exclude)kb-categories.txt' \
      ':(exclude).kb-index.stamp' 2>/dev/null
    git -C "$KB_DIR" status --porcelain --untracked-files=all -- . \
      ':(exclude)INDEX.md' ':(exclude)kb-tags.txt' ':(exclude)kb-categories.txt' \
      ':(exclude).kb-index.stamp' 2>/dev/null
  } | git hash-object --stdin 2>/dev/null
}

# COMPUTED ONCE, BEFORE the decision, and reused as the stamp value. Recomputing it after
# generation would record the tree as it stands at the END of a ~3 s run, so a file written
# mid-generation would be stamped as already-indexed and never picked up. Stamping the
# pre-generation state can only cause a redundant regeneration next call, which is the safe
# direction to be wrong in.
FP="$(fingerprint)"

if [[ -z "$REASON" ]]; then
  _was="$(cat "$STAMP" 2>/dev/null)"
  if [[ "$FP" != "$_was" ]]; then
    REASON="stale"
  fi
fi

# FRESH. Print NOTHING — silence is the contract every caller reads as "the index is good".
[[ -n "$REASON" ]] || exit 0

# ── REGENERATE ─────────────────────────────────────────────────────────────────────────────
[[ -x "$GENERATOR" || -f "$GENERATOR" ]] || die 1 "generator not found at $GENERATOR"

# `_ms_now` is bash-5's microsecond clock where available and degrades to whole seconds on
# bash 3.2 (stock macOS). Reporting a coarse number is honest; `date +%N` is not portable and
# a fabricated sub-second figure would be worse than a rounded one.
_ms_now() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local t="${EPOCHREALTIME/,/.}"
    printf '%s%s' "${t%.*}" "$(printf '%.3s' "${t#*.}")"
  else
    printf '%s000' "$SECONDS"
  fi
}
_t0="$(_ms_now)"

TMP="$(mktemp -d)" || die 1 "could not create a scratch directory"
# EVERY path out of this script from here on removes the scratch dir, including the `die`
# paths and a SIGINT mid-generation.
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

# Generate OFF TO THE SIDE. The tracked-artifact-truncation class this avoids is real and
# documented in generate-kb-index.sh: a bare `> "$INDEX_FILE"` destroys the existing index
# before the renderer runs, so an OOM-killed xargs child leaves 8 bytes on disk.
_gen_rc=0
KB_DIR="$KB_DIR" bash "$GENERATOR" --out "$TMP" >/dev/null 2>&1 || _gen_rc=$?
if [[ "$_gen_rc" -ne 0 ]]; then
  die 1 "generate-kb-index.sh failed (rc=$_gen_rc)"
fi

for _t in "${TARGETS[@]}"; do
  [[ -f "$TMP/$_t" ]] || die 1 "generate-kb-index.sh produced no $_t"
done

# PUBLISH. Per-file atomic via `mv -f` within one filesystem; the three are NOT swapped as a
# set. Accepted deliberately (ADR-230): two sessions regenerating in one worktree can leave a
# reader INDEX.md from generation A beside kb-tags.txt from generation B. Both derive from
# near-identical trees and are consumed independently — rows versus facet validation — and
# the next read regenerates. A lock to close that costs more than the race does.
for _t in "${TARGETS[@]}"; do
  mv -f "$TMP/$_t" "$KB_DIR/$_t" || die 1 "could not publish $_t"
done

# STAMP LAST, and only after every target landed. An interrupted run therefore leaves the
# stamp stale or absent, which makes the NEXT call regenerate — the safe direction. Writing
# it first would record freshness the artifacts do not have.
#
# Staged in $TMP, not beside the stamp: a `$STAMP.tmp.$$` would itself be an untracked file
# under knowledge-base/ while the fingerprint runs, and its name carries the pid, so it would
# poison the very value being recorded with something that differs on every invocation.
printf '%s\n' "$FP" > "$TMP/stamp" || die 1 "could not stage the stamp"
mv -f "$TMP/stamp" "$STAMP" || die 1 "could not publish the stamp"

_t1="$(_ms_now)"
printf 'SOLEUR_KB_INDEX_REGEN reason=%s ms=%s\n' "$REASON" "$((_t1 - _t0))"
