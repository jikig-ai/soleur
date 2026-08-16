#!/usr/bin/env bash
# Close the Dependabot PRs superseded by the consolidated bump in #7084 (ADR-191).
#
# Idempotent and resumable: already-closed PRs are skipped, each close is recorded so a
# partial failure can be re-run without double-commenting, and a PR whose target this
# branch did NOT deliver is escalated rather than closed.
#
# The re-verification is the point. Dependabot rebases open PRs, so between the time this
# list was drawn up and the time it runs, a new advisory can have moved one of these PRs
# to a HIGHER target than we delivered. Closing that one as "superseded" would silently
# drop a real security bump — the exact outcome this whole change exists to prevent. So
# each PR's CURRENT target is read immediately before its close, and `delivered >= target`
# is asserted per package.
#
# Usage:
#   bash scripts/close-superseded-dependabot-prs.sh --dry-run    # default
#   bash scripts/close-superseded-dependabot-prs.sh --apply
set -euo pipefail

SUPERSEDING_PR="${SUPERSEDING_PR:-7566}"
# `.git` is a FILE in a worktree, not a directory, so a literal `.git/...` path fails
# with "Not a directory". Resolve the real git dir instead.
STATE_DIR="${STATE_DIR:-$(git rev-parse --git-dir)/dependabot-sweep}"
MODE="dry-run"
[[ "${1:-}" == "--apply" ]] && MODE="apply"

# The queue, as measured 2026-08-16. PR 7571 is NOT in the plan's list of nine — it opened
# after the plan was written and is subsumed by the same @hono/node-server bump as 7503.
PRS=(7237 7238 7239 7245 7292 7294 7367 7368 7503 7571)

mkdir -p "$STATE_DIR"

# Resolved version of <pkg> in <lockfile>, or "" when absent.
resolved() { # $1=lockfile $2=pkg
  [[ -f "$1" ]] || {
    printf ''
    return 0
  }
  python3 -c '
import json,sys,re
lock,pkg=sys.argv[1],sys.argv[2]
try: pkgs=json.load(open(lock))["packages"]
except Exception: print(""); raise SystemExit
vs=[v.get("version") for k,v in pkgs.items() if k.endswith("node_modules/"+pkg) and v.get("version")]
def key(s): return tuple(int(x) for x in re.findall(r"\d+", s)[:3])
print(min(vs, key=key) if vs else "")
' "$1" "$2"
}

vge() { # $1 >= $2 ?
  python3 -c '
import sys,re
def k(s): return tuple(int(x) for x in re.findall(r"\d+", s)[:3])
sys.exit(0 if k(sys.argv[1]) >= k(sys.argv[2]) else 1)
' "$1" "$2"
}

lockfile_for() { # map a PR title directory to its lockfile
  case "$1" in
    */apps/web-platform | *apps/web-platform*) echo "apps/web-platform/package-lock.json" ;;
    *pencil-setup*) echo "plugins/soleur/skills/pencil-setup/scripts/package-lock.json" ;;
    *) echo "package-lock.json" ;;
  esac
}

closed=0
skipped=0
escalated=0

for pr in "${PRS[@]}"; do
  marker="$STATE_DIR/$pr.closed"
  if [[ -f "$marker" ]]; then
    echo "  #$pr already handled by a previous run — skipping (no double comment)"
    skipped=$((skipped + 1))
    continue
  fi

  meta=$(gh pr view "$pr" --json state,title 2>/dev/null || echo '')
  if [[ -z "$meta" ]]; then
    echo "::warning::#$pr could not be read; leaving it alone"
    continue
  fi
  state=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
  title=$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])')

  if [[ "$state" != "OPEN" ]]; then
    # Dependabot self-closes a rebased PR once the delivered version satisfies it, with NO
    # comment naming a superseding PR. That is the SUCCESS path, not a missing step.
    echo "  #$pr already $state (Dependabot self-closed after the bump landed) — nothing to do"
    : > "$marker"
    skipped=$((skipped + 1))
    continue
  fi

  # "bump <pkg> from <a> to <b> in /<dir>"
  pkg=$(sed -E 's/.*bump ([^ ]+) from .*/\1/' <<< "$title")
  target=$(sed -E 's/.* to ([^ ]+).*/\1/' <<< "$title")
  lock=$(lockfile_for "$title")
  have=$(resolved "$lock" "$pkg")

  if [[ -z "$have" ]]; then
    echo "::error::#$pr — $pkg not resolvable in $lock; NOT closing, escalating"
    escalated=$((escalated + 1))
    continue
  fi

  if ! vge "$have" "$target"; then
    echo "::error::#$pr — this branch delivered $pkg@$have but the PR now targets $target."
    echo "::error::Dependabot has rebased it to a HIGHER version than we shipped. Closing it as superseded would drop a real security bump. NOT closing."
    escalated=$((escalated + 1))
    continue
  fi

  echo "  #$pr  $pkg  target=$target delivered=$have  → superseded"
  if [[ "$MODE" == "apply" ]]; then
    gh pr close "$pr" --comment "Superseded by #${SUPERSEDING_PR}, which resolves \`${pkg}\` to \`${have}\` (>= this PR's ${target}) as part of the consolidated Dependabot drain for #7084.

That PR also fixes the reason this one could not merge on its own: \`apps/web-platform\` carried two lockfiles, Dependabot only ever updated one of them, and the other made \`bun install --frozen-lockfile\` fail the required checks. npm is now the single lockfile of record (ADR-191)."
    : > "$marker"
    closed=$((closed + 1))
  else
    closed=$((closed + 1))
  fi
done

echo
echo "sweep (${MODE}): ${closed} superseded, ${skipped} already handled, ${escalated} escalated"
if [[ $escalated -gt 0 ]]; then
  echo "::error::${escalated} PR(s) were NOT closed because the delivered version does not cover their current target."
  exit 1
fi
