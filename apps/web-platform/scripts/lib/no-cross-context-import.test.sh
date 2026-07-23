#!/usr/bin/env bash
# Guard: no apps/web-platform PRODUCTION source file may import a module that
# resolves OUTSIDE apps/web-platform/ (the Next.js Docker build context copies
# only apps/web-platform/ + the vendored plugin, NOT repo-root scripts/ or any
# sibling app). Such a cross-context import COMPILES under a local `next build`
# (the full repo is present) but FAILS the containerized build with
# "Module not found: ../../../…" — a silent trap that ships green through PR CI
# (which builds locally) and only reddens the web-platform-release Docker build,
# blocking prod deploy.
#
# Why: #6852 imported stripFrontmatter from repo-root scripts/lib/frontmatter-strip/
# strip.ts into cron-compound-promote.ts; local `next build` + tsc were green,
# but release run 29994907565 step 19 failed and the deploy was blocked. Fixed in
# #6875 by inlining. This guard makes the whole class fail at the touched-file /
# scripts-shard test instead of at post-merge release.
#
# Auto-discovered by scripts/test-all.sh's `apps/web-platform/scripts/lib/*.test.sh`
# glob (scripts shard). Test files, e2e, and the test/ tree are excluded — they
# are NOT in the Docker build and legitimately reference repo-root scripts/ under
# vitest (which has the full repo).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
APP="$ROOT/apps/web-platform"
fail=0
checked=0

# Collect relative imports (from/require/dynamic-import) in production TS/TSX.
# `git grep` is fast and respects the tree; scope excludes tests + e2e + the
# test/ helpers tree. Pathspecs are relative to $ROOT.
while IFS= read -r hit; do
  file="${hit%%:*}"
  rest="${hit#*:}"
  # Extract the quoted specifier from a `from '…'` / `import('…')` / `require('…')`.
  spec="$(printf '%s' "$rest" | grep -oE "['\"](\.\.?/)[^'\"]*['\"]" | head -1 | sed -E "s/^['\"]//; s/['\"]$//")"
  [[ -z "$spec" ]] && continue
  checked=$((checked+1))
  resolved="$(realpath -m "$(dirname "$ROOT/$file")/$spec")"
  case "$resolved" in
    "$APP"/*) : ;;  # resolves within web-platform — in the Docker build context
    *)
      echo "FAIL: $file imports '$spec'"
      echo "        → resolves to $resolved (OUTSIDE apps/web-platform/ — absent from the Docker build context)"
      fail=1
      ;;
  esac
done < <(git -C "$ROOT" grep -nE "(from|import|require)\s*\(?\s*['\"]\.\.?/" -- \
           'apps/web-platform/**/*.ts' 'apps/web-platform/**/*.tsx' \
           ':!apps/web-platform/**/*.test.ts' ':!apps/web-platform/**/*.test.tsx' \
           ':!apps/web-platform/**/*.spec.ts' ':!apps/web-platform/**/*.spec.tsx' \
           ':!apps/web-platform/test/**' ':!apps/web-platform/e2e/**' 2>/dev/null)

if [[ "$checked" -eq 0 ]]; then
  echo "FAIL: no relative imports scanned — the git grep produced zero candidates, which is not credible for apps/web-platform; the pathspec/glob likely broke."
  exit 1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "OK: $checked relative import(s) scanned; none escape apps/web-platform/ (Docker build context intact)."
fi
exit "$fail"
