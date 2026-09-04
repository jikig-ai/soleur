#!/usr/bin/env bash
# vendor-pin-integrity.sh — pre-commit lefthook target (FR5, TR1).
#
# For each file argument: compute `git hash-object --no-filters` against the
# working-tree contents and compare to the blob-sha pinned in NOTICE
# frontmatter. Exit 1 on any mismatch (or on a staged file that is in neither
# NOTICE registry — silent local addition).
#
# NOTE the script iterates only over its ARGUMENTS and never walks the tree,
# so it cannot detect a reference file that is absent from both registries
# unless lefthook happens to stage it. The symmetric-difference property
# (disk(references/**) == lifted-files U soleur-authored) is bought by
# plugins/soleur/test/vendor-pin-integrity.test.sh, which does walk. That is
# the chokepoint; this script is not (#7710).
#
# `--no-filters` is load-bearing per TR1: skips gitattributes line-ending
# conversion that would otherwise diverge from upstream blob SHAs on
# Windows/CRLF setups.
#
# Modes:
#   default            local pin check (per-file hash vs NOTICE local-blob-sha)
#   --verify-upstream  call `gh api repos/$UPSTREAM/git/blobs/<sha>` for every
#                      NOTICE upstream-blob-sha and assert HTTP 200. Closes
#                      the NOTICE co-edit bypass (review #3521) — local
#                      hash + NOTICE-SHA match alone is tautological if the
#                      PR edits both. CI-time verification ensures each
#                      pinned upstream blob is a real, fetchable upstream
#                      object.
#
# Invoked from lefthook.yml (local mode) and
# `.github/workflows/vendor-pin-verify.yml` (--verify-upstream mode).
#
# NOTICE_FILE env var overrides the parser's default NOTICE path so tests can
# point at fixture frontmatter without mutating the live skill NOTICE.

set -euo pipefail

VERIFY_UPSTREAM=0
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-upstream) VERIFY_UPSTREAM=1; shift ;;
    --) shift; ARGS+=("$@"); break ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PARSER="$SCRIPT_DIR/notice-frontmatter.sh"
SKILL_PREFIX="plugins/soleur/skills/gdpr-gate"

if (( VERIFY_UPSTREAM )); then
  UPSTREAM=$(bash "$PARSER" field upstream 2>/dev/null || true)
  if [[ -z "$UPSTREAM" ]]; then
    echo "vendor-pin-integrity: NOTICE frontmatter missing 'upstream' field; cannot verify upstream blobs" >&2
    exit 1
  fi
  # NOTICE upstream field is `github.com/<owner>/<repo>`; strip the host.
  OWNER_REPO="${UPSTREAM#github.com/}"
  if [[ -z "$OWNER_REPO" || "$OWNER_REPO" == "$UPSTREAM" ]]; then
    echo "vendor-pin-integrity: NOTICE upstream field '$UPSTREAM' is not in github.com/<owner>/<repo> form" >&2
    exit 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "vendor-pin-integrity: --verify-upstream requires gh CLI" >&2
    exit 1
  fi
  fails=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    upstream_path="${line%%:*}"
    upstream_sha="${line##*:}"
    if ! gh api "repos/$OWNER_REPO/git/blobs/$upstream_sha" --silent 2>/dev/null; then
      echo "vendor-pin-integrity: upstream blob $upstream_sha (path $upstream_path) not fetchable from $OWNER_REPO — NOTICE may have been tampered with" >&2
      fails=$((fails + 1))
    fi
  done < <(bash "$PARSER" upstream-files)
  if (( fails > 0 )); then
    echo "vendor-pin-integrity: $fails upstream blob(s) failed verification" >&2
    exit 1
  fi
  echo "vendor-pin-integrity: all NOTICE upstream-blob-sha values verified against $OWNER_REPO"
  exit 0
fi

# Build expected map (rel_path → blob-sha) from NOTICE.
#
# TWO registries feed this map, with the same record shape and opposite
# provenance (#7710):
#   lifted-files    — upstream-derived, pinned against goSprinto MIT content.
#   soleur-authored — written from scratch for this plugin, no upstream.
# Both are tamper-checked identically; only the ORIGIN map below differs, and
# it exists so a mismatch names the list the file actually belongs to. Before
# #7710 only `lifted-files` was consulted, so every Soleur-authored reference
# file was rejected as a "silent local addition" and could not be committed
# without `--no-verify` — which blocked the documented v2->v3 lifecycle of
# `legal-consent.md`.
declare -A EXPECTED=()
declare -A ORIGIN=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  rel_path="${line%%:*}"
  sha="${line##*:}"
  EXPECTED["$SKILL_PREFIX/$rel_path"]="$sha"
  ORIGIN["$SKILL_PREFIX/$rel_path"]="lifted-files"
done < <(bash "$PARSER" lifted-files)

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  rel_path="${line%%:*}"
  sha="${line##*:}"
  # A path in BOTH registries is a provenance falsification, not a duplicate
  # pin: it would attest MIT provenance for Soleur's own writing. Refuse
  # rather than let one map silently win.
  if [[ -n "${EXPECTED["$SKILL_PREFIX/$rel_path"]:-}" ]]; then
    echo "vendor-pin-integrity: $SKILL_PREFIX/$rel_path appears in BOTH lifted-files and soleur-authored — provenance is ambiguous; a file is upstream-derived or Soleur-authored, never both." >&2
    exit 1
  fi
  EXPECTED["$SKILL_PREFIX/$rel_path"]="$sha"
  ORIGIN["$SKILL_PREFIX/$rel_path"]="soleur-authored"
done < <(bash "$PARSER" soleur-authored)

mismatches=0
for f in "$@"; do
  # Normalise to canonical repo-relative for registry lookup. `realpath -m`
  # resolves `..` segments without requiring the file to exist (covers the
  # synthetic-deletion case below).
  if [[ "$f" == /* ]]; then
    abs="$(realpath -m "$f" 2>/dev/null || echo "$f")"
    rel="${abs#"$REPO_ROOT"/}"
  else
    rel="$f"
  fi

  # NOTICE itself is in the lefthook glob (any byte change should re-run the
  # integrity gate) but is not a lifted-files registry entry. Skip the
  # registry check for it; its content is governed by the workflow's
  # NOTICE-bump step + reviewer eyes.
  if [[ "$rel" == "$SKILL_PREFIX/NOTICE" ]]; then
    continue
  fi

  expected="${EXPECTED[$rel]:-}"
  if [[ -z "$expected" ]]; then
    echo "vendor-pin-integrity: $rel is staged but appears in neither NOTICE lifted-files nor soleur-authored — silent local addition? Add it to lifted-files if it is vendored from upstream, or to soleur-authored if it is written for this plugin, or remove the file." >&2
    mismatches=$((mismatches + 1))
    continue
  fi

  if [[ ! -f "$REPO_ROOT/$rel" ]]; then
    echo "vendor-pin-integrity: $rel listed in NOTICE but missing from working tree" >&2
    mismatches=$((mismatches + 1))
    continue
  fi

  actual="$(git hash-object --no-filters "$REPO_ROOT/$rel")"
  if [[ "$actual" != "$expected" ]]; then
    # Name the list the file belongs to AND a mechanism that exists. The
    # previous text sent a blocked contributor to "the vendor-drift
    # workflow", deleted in #4483 — the only exit offered at the moment
    # their commit is refused, and a dead end.
    origin="${ORIGIN[$rel]:-lifted-files}"
    echo "vendor-pin-integrity: BLOB SHA mismatch on $rel (registry $origin: expected $expected, got $actual)." >&2
    if [[ "$origin" == "soleur-authored" ]]; then
      echo "  This file is Soleur-authored, so editing it is expected. Update its local-blob-sha in the soleur-authored block of $SKILL_PREFIX/NOTICE to: $actual" >&2
    else
      echo "  This file is vendored from upstream. Either revert the local edit, or — if this is a deliberate re-vendor — update its local-blob-sha in the lifted-files block of $SKILL_PREFIX/NOTICE to: $actual and record the upstream delta in the NOTICE table." >&2
    fi
    mismatches=$((mismatches + 1))
  fi
done

if (( mismatches > 0 )); then
  exit 1
fi

exit 0
