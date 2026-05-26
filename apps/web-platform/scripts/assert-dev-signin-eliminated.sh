#!/usr/bin/env bash
# assert-dev-signin-eliminated.sh — post-`next build` tripwire for R3.
#
# Greps the production build output for forbidden source-level identifiers
# tied to the dev-only sign-in panel (R3 / feat-dev-signin-bypass). Exits
# non-zero with the offending file path on any hit. Wired into the
# existing prd-build pipeline (Dockerfile builder stage) so a Docker
# build of the prd image fails when dev-only symbols leak into shared
# CLIENT code.
#
# Scope decision (deviates from the plan's literal task-2.6 scope of
# `.next/server/**`; aligns with the plan's "Honest framing" paragraph):
#
#   App Router compiles `app/api/auth/dev-signin/route.ts` and the panel
#   server component into `.next/server/**` UNCONDITIONALLY — webpack
#   tree-shaking does not eliminate route modules even when their bodies
#   are dead-branch-pruned by SWC/Terser. The honest threat model is a
#   future refactor leaking dev-only paths into SHARED CLIENT code. The
#   load-bearing defenses against the server-side residual are the
#   request-time NODE_ENV literal + the Doppler-prd-absence preflight.
#
#   Therefore this gate scans:
#     - `.next/static/**`                      (client chunks + maps)
#     - `.next/server/server-reference-manifest.js`  (RSC client-callable manifest)
#   and intentionally does NOT scan `.next/server/**` broadly.
#
# Forbidden token list (any hit fails):
#   - `dev-1@example.com`, `dev-2@example.com`, `dev-3@example.com`
#   - `DEV_SIGNIN`, `DEV_USER_`
#   - `dev-sign-in-panel`, `isDevSignInEnabled`, `"dev-signin"`
#
# `"dev-signin"` is the quoted form (the FLAG_VARS key in source). The bare
# `dev-signin` string would false-positive against build-time-embedded file
# paths in worktrees whose directory name contains the feature branch (e.g.,
# `.worktrees/feat-dev-signin-bypass/...` baked into pdfjs-dist's
# `createRequire(file:///...)` call). The quoted form is the actual leak
# signal — it only appears when the FLAG_VARS dictionary itself ends up in
# a client chunk.
#
# Usage (from apps/web-platform):
#   bash scripts/assert-dev-signin-eliminated.sh
#
# Optional env var to force-fail on a specific path (debugging the gate):
#   ASSERT_DEV_SIGNIN_DEBUG=1
set -uo pipefail

cd "$(dirname "$0")/.."

NEXT_DIR=".next"
if [[ ! -d "$NEXT_DIR" ]]; then
  echo "::error::$NEXT_DIR not found — run \`npm run build\` first."
  exit 2
fi

# `printf '%s\n' ... | grep -F` is the cheapest way to OR the literals.
TOKENS=(
  "dev-1@example.com"
  "dev-2@example.com"
  "dev-3@example.com"
  "DEV_SIGNIN"
  "DEV_USER_"
  "dev-sign-in-panel"
  "isDevSignInEnabled"
  '"dev-signin"'
)

# Build a `-e <token>` argv for fixed-string grep. Each token is matched
# literally (no regex) — `dev-signin` is a substring of `dev-sign-in-panel`
# but each is on the list independently for clarity.
GREP_ARGS=()
for t in "${TOKENS[@]}"; do
  GREP_ARGS+=("-e" "$t")
done

hits=0
hit_files=()

scan() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  # `-r` recurses; `-l` prints filenames only; `-I` ignores binary files;
  # `-F` literal match; `--include` keeps the scan to text-likely files.
  while IFS= read -r file; do
    hits=$((hits + 1))
    hit_files+=("$file")
  done < <(grep -rlIF "${GREP_ARGS[@]}" \
    --include='*.js' --include='*.mjs' --include='*.cjs' \
    --include='*.css' --include='*.html' --include='*.json' \
    --include='*.map' \
    "$path" 2>/dev/null || true)
}

scan "$NEXT_DIR/static"
scan "$NEXT_DIR/server/server-reference-manifest.js"

if [[ "$hits" -gt 0 ]]; then
  echo "::error::dev-signin token(s) leaked into prd build output:"
  for f in "${hit_files[@]}"; do
    echo "::error::  $f"
  done
  echo "::error::Forbidden tokens: ${TOKENS[*]}"
  echo "::error::This means a future refactor pulled a dev-only module"
  echo "::error::into shared client code. Trace the import chain."
  exit 1
fi

echo "::notice::No dev-signin tokens detected in prd client bundles or RSC manifest."
exit 0
