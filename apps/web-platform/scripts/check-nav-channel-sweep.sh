#!/usr/bin/env bash
# check-nav-channel-sweep.sh
#
# feat-ui-action-feedback (#8917) nav-channel sentinel — the route-pending bar
# is driven by exactly three channels (NavLink, usePendingRouter, popstate);
# a nav path that bypasses them dead-clicks: no bar on a slow nav is the
# failure mode this feature exists to remove. This script greps the
# greppable bypasses:
#
#   1. `import ... from "next/link"` (either quote style) outside
#      components/ui/nav-link.tsx — internal links must be NavLink
#      (onNavigate fires the bar).
#   2. Nav method calls on a raw `useRouter` handle — bound names
#      (`const r = useRouter(); r.push(`), destructured methods
#      (`const { push } = useRouter()`), and direct (`useRouter().push(`).
#      Nav calls must go through `usePendingRouter`
#      (hooks/use-pending-router.ts is the one allowed useRouter importer
#      with nav methods). `refresh()` stays raw-legal — it is not a nav.
#   3. A literal internal `<a href="/…">` anchor — tag-sliced (multi-line
#      aware), any quote style including `href={"/…"}`. Converts to NavLink.
#      Allowed: `/api/` downloads, `#fragment`, `mailto:`, absolute
#      `http(s):`, and tags marked data-nav-exempt="reason" for an
#      INTENTIONAL hard reload (e.g. sign-out boundary, error-recovery
#      reload — document the reason on the tag).
#
# Exits non-zero with a readable diff on violation.

set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"

SWEEP_PATHS="${NAV_SWEEP_PATHS:-components/*.tsx app/*.tsx hooks/*.ts hooks/*.tsx lib/*.ts lib/*.tsx}"
read -r -a PATHSPEC <<< "$SWEEP_PATHS"

violations=0

# --- 1. raw next/link imports -------------------------------------------------
LINK_IMPORTS="$(git grep -lE "from ['\"]next/link['\"]" -- "${PATHSPEC[@]}" 2>/dev/null | grep -v '^components/ui/nav-link\.tsx$' || true)"
if [[ -n "$LINK_IMPORTS" ]]; then
  violations=$((violations + 1))
fi

# --- 2. useRouter files calling nav methods ------------------------------------
# Per file: (a) direct `useRouter().<m>(`, (b) destructured
# `const { push } = useRouter()`, (c) `<bound>.<m>(` for whatever identifier
# the file binds useRouter() to — receiver-anchored so `arr.push(` /
# `str.replace(` on non-router receivers do NOT false-positive.
ROUTER_NAV=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ "$f" == "hooks/use-pending-router.ts" ]] && continue
  hit=""
  if grep -qE 'useRouter\(\)\.(push|replace|back|forward)\(' "$f"; then
    hit="direct call"
  elif grep -qE '\{[^}]*\b(push|replace|back|forward)\b[^}]*\}\s*=\s*useRouter\(' "$f"; then
    hit="destructured nav method"
  else
    # receiver-anchored: every identifier bound via `X = useRouter()`
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      if grep -qE "\\b${name}\\.(push|replace|back|forward)\\(" "$f"; then
        hit="${name}.push/replace/back/forward"
        break
      fi
    done < <(grep -oE '[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*useRouter\(' "$f" | sed -E 's/[[:space:]]*=[[:space:]]*useRouter\(//')
  fi
  [[ -n "$hit" ]] && ROUTER_NAV+="  $f ($hit)"$'\n'
done < <(git grep -lE 'useRouter' -- "${PATHSPEC[@]}" 2>/dev/null || true)
if [[ -n "$ROUTER_NAV" ]]; then
  violations=$((violations + 1))
fi

# --- 3. literal internal anchors ------------------------------------------------
# Tag-sliced, not line-grepped: a multi-line `<a\n  href="/x">` bypasses a
# line regex. Any literal-quote form ("/x", '/x', {"/x"}). /api/, #, mailto:,
# http(s):, and data-nav-exempt tags are allowed.
RAW_ANCHORS="$(
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    perl -0777 -ne '
      while (/<a\s[^>]*?>/gs) {
        my $tag = $&;
        next if $tag =~ /data-nav-exempt/;
        next unless $tag =~ /href=\{?\s*["'"'"'`][^\x27"`]*\//;
        # literal "/" immediately after the opening quote of href
        next unless $tag =~ /href=\{?\s*["'"'"'`]\//;
        next if $tag =~ /href=\{?\s*["'"'"'`]\/api\//;
        print "$ARGV: $tag\n";
      }
    ' "$f"
  done < <(git grep -lF '<a' -- "${PATHSPEC[@]}" 2>/dev/null || true)
)"
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
    echo "Files calling router push/replace/back/forward on a raw useRouter (use usePendingRouter):" >&2
    printf '%s' "$ROUTER_NAV" >&2
  fi
  if [[ -n "$RAW_ANCHORS" ]]; then
    echo "" >&2
    echo "Literal internal <a href=\"/…\"> anchors (convert to NavLink; /api/, #fragment, mailto:, external stay native; intentional hard reloads carry data-nav-exempt=\"reason\"):" >&2
    printf '%s\n' "$RAW_ANCHORS" >&2
  fi
  echo "" >&2
  echo "See components/ui/README.md §Nav-pending channels and the feat-ui-action-feedback plan." >&2
  exit 1
fi

echo "OK: nav-channel sweep sentinel (#8917) — no next/link imports, raw router nav calls, or literal internal anchors outside the channels."
exit 0
