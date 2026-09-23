#!/usr/bin/env bash
# render-c4-model.sh — Render the compiled LikeC4 model artifact from a repo's .c4 sources.
#
# Usage: bash <plugin>/scripts/render-c4-model.sh [--root DIR] [--out PATH] [--help]
#
# Compiles every LikeC4 DSL source (*.c4) under <root>/knowledge-base/engineering/
# architecture/diagrams/ into the layouted model.likec4.json that the web Knowledge
# Base viewer renders at runtime (the browser ships @likec4/diagram WITHOUT the
# compiler, so the JSON must be precompiled and committed).
#
# PLUGIN-OWNED (ADR-235 amendment, #8542 follow-up). It lived at the Soleur repo's
# scripts/regenerate-c4-model.sh, which a self-hosted install does not have, so the
# merge resolver could never regenerate in a customer repo. That path is now a thin
# wrapper for this repo's own callers; this file is the one renderer.
#
# --root DIR  The repository whose diagrams to render. Default: the git top level of
#             the current directory. The CODE comes from beside this script; only the
#             DATA comes from --root (ADR-179's code-root / data-root split).
# --out PATH  Write the validated, canonicalized model to PATH instead of the tracked
#             artifact. Used by plugins/soleur/test/c4-model-freshness.test.sh to render
#             to a temp path with identical logic, then byte-diff against the committed
#             artifact. Default: <root>/.../diagrams/model.likec4.json.
#
# Pinned to likec4@1.50.0 — MUST match apps/web-platform/Dockerfile +
# package.json @likec4/core/@likec4/diagram (guarded by c4-likec4-version-pin.test.ts).
# A CLI/client version skew silently desyncs the rendered diagram.
#
# Renders OFF-TREE to a temp path and validates structurally BEFORE publishing:
# `likec4 export json` exits 0 even on an unresolved-reference / empty model, so
# an exit-0 check is NOT proof of a good artifact — see learnings
# 2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md and
# apps/web-platform/server/c4-render.ts. Only a non-empty model is published,
# so a broken .c4 source can never clobber the good committed artifact.
#
# WRITES EXACTLY ONE FILE, the output path. The merge resolver commits whatever this
# changes, and asserts nothing else moved (resolve-regenerable-conflicts.sh, D4).
#
# Idempotent: rerunning against unchanged sources produces byte-identical output.

set -euo pipefail

LIKEC4_VERSION="1.50.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL_CLI="$SCRIPT_DIR/../lib/c4-canonical-cli.mjs"
ROOT=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    --root)
      [[ -n "${2:-}" ]] || { echo "ERROR: --root requires a DIR argument" >&2; exit 2; }
      ROOT="$2"
      shift 2
      ;;
    --out)
      [[ -n "${2:-}" ]] || { echo "ERROR: --out requires a PATH argument" >&2; exit 2; }
      OUT="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1 (try --help)" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "ERROR: not inside a git work tree and no --root given" >&2; exit 2; }
fi
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "ERROR: --root is not a directory" >&2; exit 2; }
DIAGRAMS_DIR="$ROOT/knowledge-base/engineering/architecture/diagrams"
[[ -n "$OUT" ]] || OUT="$DIAGRAMS_DIR/model.likec4.json"

if [[ ! -d "$DIAGRAMS_DIR" ]]; then
  echo "ERROR: diagrams directory not found at $DIAGRAMS_DIR" >&2
  exit 1
fi

# Guard: at least one DSL source. NOT "spec.c4 + model.c4 + views.c4": soleur:sync writes
# generated-components.c4, spec.c4 and views.c4 into a customer repo and never model.c4
# (that one belongs to soleur:architecture), so the all-three form refused every plainly
# synced repo. What makes a render trustworthy is the two gates below, not a file list.
shopt -s nullglob
_sources=("$DIAGRAMS_DIR"/*.c4)
shopt -u nullglob
if [[ "${#_sources[@]}" -eq 0 ]]; then
  echo "ERROR: no .c4 source in $DIAGRAMS_DIR" >&2
  exit 1
fi

[[ -f "$CANONICAL_CLI" ]] || { echo "ERROR: canonicalizer not found beside this script at $CANONICAL_CLI" >&2; exit 1; }

TMP="$(mktemp -d)"
PUBLISH_TMP=""
trap 'rm -rf "$TMP"; [[ -n "$PUBLISH_TMP" ]] && rm -f "$PUBLISH_TMP"' EXIT
RENDER_LOG="$TMP/render.log"

# Render off-tree with the pinned CLI, capturing all diagnostics. A non-zero
# exit is a hard failure; but likec4 ALSO exits 0 on broken sources, so the
# exit code alone is never sufficient (see the two checks below).
if ! ( cd "$DIAGRAMS_DIR" && npx -y --ignore-scripts "likec4@${LIKEC4_VERSION}" export json -o "$TMP/model.likec4.json" . ) >"$RENDER_LOG" 2>&1; then
  echo "ERROR: likec4 export exited non-zero — refusing to overwrite $OUT" >&2
  cat "$RENDER_LOG" >&2
  exit 1
fi

# exit-0 is NOT proof. likec4@1.50.0 has TWO source-fault modes that both exit 0:
#   (1) unresolved reference / missing spec.c4 -> an EMPTY-elements model
#       (the #4966 case; see apps/web-platform/server/c4-render.ts).
#   (2) a syntax error -> likec4 recovers by dropping the bad fragment, prints
#       `Invalid <file>` + `Line N:` (or `Could not resolve …`), and STILL emits
#       a non-empty (now-incomplete) model — so element-count alone misses it.
# Gate on BOTH a clean diagnostic stream AND a non-empty model. Element-count is
# the version-robust backstop; the diagnostic grep catches mode (2). On error we
# never publish, so a broken .c4 can never clobber the good committed artifact.
# Anchors keep the markers off the workspace-path line likec4 echoes (`workspace:
# /abs/path …`): `^Invalid ` and the indented `Line N:` form (`    Line 274:`)
# can't match a repo path, so a checkout dir containing those substrings can't
# false-FAIL. `Could not resolve` is a distinctive likec4 phrase.
DIAG_RE='^Invalid |Could not resolve|^[[:space:]]+Line [0-9]+:'
if grep -qE "$DIAG_RE" "$RENDER_LOG"; then
  echo "ERROR: likec4 reported a source validation error — refusing to overwrite $OUT" >&2
  grep -E "$DIAG_RE" "$RENDER_LOG" >&2
  echo "       Fix the .c4 source (run: cd $DIAGRAMS_DIR && npx -y likec4@${LIKEC4_VERSION} validate .)" >&2
  exit 1
fi
if ! jq -e '(.elements | length) > 0' "$TMP/model.likec4.json" >/dev/null 2>&1; then
  echo "ERROR: likec4 produced an empty/degenerate model — refusing to overwrite $OUT" >&2
  echo "       Fix the .c4 source (run: cd $DIAGRAMS_DIR && npx -y likec4@${LIKEC4_VERSION} validate .)" >&2
  exit 1
fi

# Canonicalize AFTER both gates (never instead of them): one JSON value per
# line with every view `hash` blanked, so git can merge two regenerations whose
# edits touch different values (ADR-235, #8542). Node serializes, never jq —
# jq reformats numbers. The web app (c4-render.ts) and the plugin
# (generate-c4-from-components.ts) emit these same bytes through the same
# module, so no writer reformats another's file.
if ! node "$CANONICAL_CLI" "$TMP/model.likec4.json" >"$TMP/canonical.json"; then
  echo "ERROR: could not canonicalize the rendered model — refusing to overwrite $OUT" >&2
  exit 1
fi

# Publish only on success, atomically: copy into the destination directory then
# rename. An intra-filesystem rename is atomic, so a crash mid-write can never
# leave a truncated model.likec4.json on the tracked path (a bare `cp` onto $OUT
# is not atomic). The temp lands beside $OUT (a dotfile, never a tracked .c4) so
# the rename stays on one filesystem; the EXIT trap reaps it if cp/mv aborts.
OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"
PUBLISH_TMP="$(mktemp "$OUT_DIR/.model.likec4.json.XXXXXX")"
cp "$TMP/canonical.json" "$PUBLISH_TMP"
mv -f "$PUBLISH_TMP" "$OUT"
PUBLISH_TMP=""  # renamed onto $OUT — nothing left for the trap to clean
echo "Regenerated $OUT ($(jq '.elements | length' "$OUT") elements, $(jq '.relations | length' "$OUT") relations, $(jq '.views | length' "$OUT") views)"
