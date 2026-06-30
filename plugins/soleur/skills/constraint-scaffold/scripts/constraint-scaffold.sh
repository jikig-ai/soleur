#!/usr/bin/env bash
# constraint-scaffold — deterministic generator for the Layer-1 client->server-secret
# import-boundary gate (ADR-071, Option D). Emits a dependency-cruiser config, a
# shared runner, and a CI workflow into the target Next.js app, and captures the
# known-violations baseline. v1 target = apps/web-platform (Next.js-only).
#
# Modes:
#   (default)            detect Next.js -> emit config + runner + workflow (refuse
#                        if any already exists; NO --force) -> capture baseline.
#   --refresh-baseline   clean-tree guard, then re-capture the baseline against the
#                        origin/main merge-base (so a same-PR violation is NOT
#                        grandfathered). Agent-only; never shown to the founder.
#
# Exit matrix (every non-zero is a hard, fail-closed stop):
#   0   success
#   64  usage error (unknown argument)
#   65  precondition failed (target is not a Next.js app)
#   66  refuse-if-exists (a non-baseline artifact already present; no --force)
#   67  dirty working tree (baseline capture requires a clean tree)
#   68  dependency-cruiser binary missing, or baseline capture failed
#   69  git/merge-base error during baseline capture
#   70  --refresh-baseline before generation (no .dependency-cruiser.cjs yet — run default mode first)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF_DIR="$(cd "$SCRIPT_DIR/../references" && pwd)"
# REPO_ROOT defaults to the skill's own repo. CONSTRAINT_SCAFFOLD_REPO_ROOT points
# the generator at a synthesized fixture repo (apps/web-platform-shaped) for the
# hermetic generator self-tests; in normal use it is unset. Templates (REF_DIR)
# always come from the real skill.
REPO_ROOT="${CONSTRAINT_SCAFFOLD_REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"

# v1: the one supported target.
TARGET_REL="apps/web-platform"
TARGET="$REPO_ROOT/$TARGET_REL"

CFG="$TARGET/.dependency-cruiser.cjs"
RUNNER="$TARGET/scripts/constraint-gates.sh"
WORKFLOW="$TARGET/.github/workflows/constraint-gates.yml"
BASELINE="$TARGET/.dependency-cruiser-known-violations.json"
DEPCRUISE="$TARGET/node_modules/.bin/depcruise"

log() { printf 'constraint-scaffold: %s\n' "$*" >&2; }
die() { log "$1"; exit "${2:-1}"; }

MODE="default"
case "${1:-}" in
  "") MODE="default" ;;
  --refresh-baseline) MODE="refresh" ;;
  *) die "unknown argument: $1 (expected none or --refresh-baseline)" 64 ;;
esac

# --- Precondition: target is a Next.js app -----------------------------------
detect_nextjs() {
  # next.config.* present AND an anchored "next": dependency key (the anchor
  # avoids matching "next-themes" etc.).
  compgen -G "$TARGET/next.config.*" >/dev/null 2>&1 || return 1
  grep -qE '"next"[[:space:]]*:' "$TARGET/package.json" 2>/dev/null || return 1
}
detect_nextjs || die "target $TARGET_REL is not a Next.js app (need next.config.* + anchored \"next\": in package.json)" 65

# --- Baseline capture (shared) -----------------------------------------------
# Captures the value-violations of the tree rooted at $1 into $BASELINE. Scans
# only the client dirs (app/components) that actually exist plus server/, so a
# single-client-dir app does not error on a missing dir.
capture_baseline() {
  local app_root="$1"
  [[ -x "$DEPCRUISE" ]] || die "dependency-cruiser not found at $DEPCRUISE — run 'bun install' in $TARGET_REL first" 68
  local scan_dirs=()
  local d
  for d in app components server; do
    [[ -d "$app_root/$d" ]] && scan_dirs+=("$d")
  done
  [[ "${#scan_dirs[@]}" -gt 0 ]] || die "no app/components/server dirs under $app_root — cannot capture baseline" 68
  local tmp
  tmp="$(mktemp)"
  if ! ( cd "$app_root" && "$DEPCRUISE" --config .dependency-cruiser.cjs --output-type baseline "${scan_dirs[@]}" ) > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die "baseline capture failed (dependency-cruiser config error?)" 68
  fi
  mv "$tmp" "$BASELINE"
  log "captured baseline: $(grep -c '"rule"' "$BASELINE" 2>/dev/null || echo 0) known violation(s) -> ${BASELINE#$REPO_ROOT/}"
}

# Capture the baseline against the origin/main merge-base in a detached worktree,
# so a violation introduced in the SAME PR (branch-added) is NOT grandfathered —
# only violations pre-existing on main land in the baseline. Used by BOTH modes:
# first adoption (default) must not grandfather a same-PR leak any more than a
# refresh does. Requires a clean tree (committed state == reviewable baseline).
capture_baseline_mergebase() {
  if ! { git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet; }; then
    die "working tree is dirty — commit or discard changes before capturing the baseline" 67
  fi
  MB="$(git -C "$REPO_ROOT" merge-base origin/main HEAD 2>/dev/null)" \
    || die "could not compute merge-base with origin/main (is origin/main fetched?)" 69
  log "capturing baseline against origin/main merge-base ${MB:0:12} (same-PR violations excluded)"

  WT="$(mktemp -d)"
  trap 'git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true; rm -rf "$WT"' EXIT
  git -C "$REPO_ROOT" worktree add --detach "$WT" "$MB" >/dev/null 2>&1 \
    || die "git worktree add at merge-base failed" 69

  WT_TARGET="$WT/$TARGET_REL"
  [[ -d "$WT_TARGET/app" || -d "$WT_TARGET/components" ]] \
    || die "merge-base tree has no $TARGET_REL/app|components — cannot capture baseline" 69
  # The merge-base may predate the gate: ensure the current config is present, and
  # reuse the installed node_modules (depcruise binary + resolver) via symlink.
  cp "$CFG" "$WT_TARGET/.dependency-cruiser.cjs"
  ln -s "$TARGET/node_modules" "$WT_TARGET/node_modules"
  capture_baseline "$WT_TARGET"

  # Clean up the worktree now (success path) so the caller can continue; clear the
  # trap so a later die does not double-remove an already-gone worktree.
  git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf "$WT"
  trap - EXIT
}

if [[ "$MODE" == "refresh" ]]; then
  [[ -f "$CFG" ]] || die "no .dependency-cruiser.cjs at $TARGET_REL — run the default mode first to generate the gate" 70
  capture_baseline_mergebase
  log "refresh complete — review the baseline diff before merging."
  exit 0
fi

# --- Default mode: emit artifacts (non-destructive) --------------------------
# Clean-tree guard FIRST — the baseline is captured against the origin/main
# merge-base (below), and we refuse to emit onto a dirty tree so the resulting
# baseline + artifact diff is reviewable and deterministic.
if ! { git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet; }; then
  die "working tree is dirty — commit or discard changes before generating the gate" 67
fi

for f in "$CFG" "$RUNNER" "$WORKFLOW"; do
  [[ -e "$f" ]] && die "refuse-if-exists: ${f#$REPO_ROOT/} already present (no --force; re-baseline via --refresh-baseline)" 66
done
[[ -e "$BASELINE" ]] && die "refuse-if-exists: ${BASELINE#$REPO_ROOT/} already present (re-baseline via --refresh-baseline)" 66

mkdir -p "$TARGET/scripts" "$TARGET/.github/workflows"

# .dependency-cruiser.cjs — emitted verbatim (the from-set is computed at
# require-time, never baked in).
cp "$REF_DIR/depcruise-config.template" "$CFG"

# Shared runner.
cp "$REF_DIR/shared-runner.template" "$RUNNER"
chmod +x "$RUNNER"

# CI workflow — substitute the target dir (path-check glob + working-directory +
# runner path). sed delimiter is '|' since the value contains no '|'.
sed "s|__TARGET_DIR__|$TARGET_REL|g" "$REF_DIR/constraint-gates-workflow.template" > "$WORKFLOW"

log "emitted: ${CFG#$REPO_ROOT/}, ${RUNNER#$REPO_ROOT/}, ${WORKFLOW#$REPO_ROOT/}"

# Capture the initial baseline against the origin/main merge-base — same path as
# --refresh-baseline, so a leak introduced in the SAME PR that scaffolds the gate
# is NOT grandfathered (only violations pre-existing on main are).
capture_baseline_mergebase

log "done. Verify green: (cd $TARGET_REL && bash scripts/constraint-gates.sh)"
exit 0
