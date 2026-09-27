#!/usr/bin/env bash
# check-nav-channel-sweep.sh
#
# feat-ui-action-feedback (#8917) nav-channel sentinel — the route-pending bar
# is driven by exactly three channels (NavLink, usePendingRouter, popstate);
# a nav path that bypasses them dead-clicks: no bar on a slow nav is the
# failure mode this feature exists to remove. This script greps the
# greppable bypasses:
#
#   1. `import ... from "next/link"` outside components/ui/nav-link.tsx —
#      internal links must be NavLink (onNavigate fires the bar).
#   2. `router.push`/`router.replace`/`router.back`/`router.forward` in a
#      file importing `useRouter` — nav calls must go through
#      `usePendingRouter` (hooks/use-pending-router.ts wraps useRouter; it is
#      the one allowed useRouter importer with nav methods).
#   3. A literal internal `<a href="/…">` anchor — converts to NavLink.
#      Allowed: `/api/` downloads, `#fragment`, `mailto:`, absolute
#      `http(s):`, and non-literal `href={…}` (not statically checkable).
#
# Exits non-zero with a readable diff on violation.

set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"

SWEEP_PATHS="${NAV_SWEEP_PATHS:-components/*.tsx app/*.tsx hooks/*.ts hooks/*.tsx}"
read -r -a PATHSPEC <<< "$SWEEP_PATHS"

violations=0

# --- 1. raw next/link imports -------------------------------------------------
LINK_IMPORTS="$(git grep -lE 'from "next/link"' -- "${PATHSPEC[@]}" 2>/dev/null | grep -v '^components/ui/nav-link\.tsx$' || true)"
if [[ -n "$LINK_IMPORTS" ]]; then
  violations=$((violations + 1))
fi

# --- 2. useRouter files calling nav methods ------------------------------------
ROUTER_NAV=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ "$f" == "hooks/use-pending-router.ts" ]] && continue
  if grep -qE '\.(push|replace|back|forward)\(' "$f"; then
    ROUTER_NAV+="  $f"$'\n'
  fi
done < <(git grep -lE 'useRouter' -- "${PATHSPEC[@]}" 2>/dev/null || true)
if [[ -n "$ROUTER_NAV" ]]; then
  violations=$((violations + 1))
fi

# --- 3. literal internal anchors ------------------------------------------------
# <a href="/…"> where the target is not /api/ — the anchor does a full document
# reload and bypasses every pending channel.
RAW_ANCHORS="$(git grep -nE '<a[[:space:]][^>]*href="/' -- "${PATHSPEC[@]}" 2>/dev/null | grep -vE 'href="/api/' || true)"
if [[ -n "$RAW_ANCHORS" ]]; then
  violations=$((violations + 1))
fi

if (( violations > 0 )); then
  echo "FAIL: nav-channel sweep sentinel (#8917)" >&2
  if [[ -n "$LINK_IMPORTS" ]]; then
    echo "" >&2
    echo "Files importing next/link directly (use NavLink from components/ui/nav-link.tsx):" >&2
    printf '%s\n' "$LINK_IMPORTS" | sed 's/^/  /' >&2
  fi
  if [[ -n "$ROUTER_NAV" ]]; then
    echo "" >&2
    echo "Files calling router.push/replace/back/forward on a raw useRouter (use usePendingRouter):" >&2
    printf '%s' "$ROUTER_NAV" >&2
  fi
  if [[ -n "$RAW_ANCHORS" ]]; then
    echo "" >&2
    echo "Literal internal <a href=\"/…\"> anchors (convert to NavLink; /api/, #fragment, mailto:, external stay native):" >&2
    printf '%s\n' "$RAW_ANCHORS" >&2
  fi
  echo "" >&2
  echo "See components/ui/README.md §Nav-pending channels and the feat-ui-action-feedback plan." >&2
  exit 1
fi

echo "OK: nav-channel sweep sentinel (#8917) — no next/link imports, raw router nav calls, or literal internal anchors outside the channels."
exit 0
