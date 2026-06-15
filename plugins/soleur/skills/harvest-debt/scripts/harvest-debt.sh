#!/usr/bin/env bash
# harvest-debt.sh — surface inline SOLEUR-DEBT deferral markers as a ledger.
#
# Greps tracked SOURCE for `SOLEUR-DEBT:` markers, groups hits by file, splits
# each on the first `;` into ceiling + upgrade-trigger, and flags any marker
# with no trigger as `no-trigger` (the rot-prone case). Read-only: it writes
# nothing and closes nothing — promotion into the ledger is /soleur:compound,
# closure is /soleur:resolve-debt.
#
# Scope: CODE comments only. `*.md` prose (the convention doc, plans, specs,
# SKILL bodies) is excluded by design so the marker DEFINITION never self-reports
# as debt — a path denylist, not a semantic check (see SKILL.md "Scope").
#
# Usage: harvest-debt.sh [--help]   (run from the repo root)
# Exit: 0 = clean (markers reported or none found); 2 = usage error.
set -euo pipefail

readonly MARKER="SOLEUR-DEBT:"

usage() {
  cat <<'EOF'
harvest-debt.sh — list inline SOLEUR-DEBT deferral markers, grouped by file.

Usage:
  harvest-debt.sh           Harvest markers from the current git repo.
  harvest-debt.sh --help    Show this help.

A marker reads `// SOLEUR-DEBT: <ceiling>; <upgrade trigger>`. Markers with no
`;`-delimited trigger are flagged `no-trigger`. Read-only — promote worth-tracking
markers with /soleur:compound, close them with /soleur:resolve-debt.
EOF
}

main() {
  case "${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
    "") ;;
    *)
      echo "harvest-debt: unknown argument '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "harvest-debt: not inside a git work tree" >&2
    exit 2
  fi

  # Anchor at the repo root so the exclude pathspecs (which are repo-root-relative)
  # match regardless of the caller's subdirectory — enforces the "run from root"
  # contract instead of merely documenting it.
  cd "$(git rev-parse --show-toplevel)" || exit 2

  # git grep already skips untracked paths (node_modules, .git). Exclude prose
  # (*.md), this skill's own dir (its marker literals are definitions), and build
  # output. git grep exits 1 on no match under pipefail — tolerate with `|| true`.
  local hits
  hits="$(
    git grep -nI -F -e "$MARKER" -- \
      ':(exclude)*.md' \
      ':(exclude)plugins/soleur/skills/harvest-debt' \
      ':(exclude)*.min.*' \
      ':(exclude,glob)**/node_modules/**' \
      ':(exclude,glob)**/_site/**' \
      ':(exclude,glob)**/dist/**' \
      2>/dev/null || true
  )"

  if [[ -z "$hits" ]]; then
    echo "No SOLEUR-DEBT markers found."
    exit 0
  fi

  printf '%s\n' "$hits" | awk -v marker="$MARKER" '
    BEGIN { total = 0; untriggered = 0; prev = "" }
    {
      # git grep -n emits "<file>:<lineno>:<content>". Anchor on the ":<digits>:"
      # boundary (lineno is always numeric) so a colon WITHIN the path does not
      # mis-peel file/lineno. Skip any line lacking that boundary.
      if (!match($0, /:[0-9]+:/)) next
      file = substr($0, 1, RSTART - 1)
      rest = substr($0, RSTART + 1)
      j = index(rest, ":"); lineno = substr(rest, 1, j - 1); content = substr(rest, j + 1)

      m = index(content, marker)
      after = substr(content, m + length(marker))
      gsub(/^[ \t]+/, "", after); gsub(/[ \t]+$/, "", after)

      s = index(after, ";")
      if (s > 0) { ceiling = substr(after, 1, s - 1); trigger = substr(after, s + 1) }
      else { ceiling = after; trigger = "" }
      gsub(/[ \t]+$/, "", ceiling)
      gsub(/^[ \t]+/, "", trigger); gsub(/[ \t]+$/, "", trigger)

      if (file != prev) { printf "\n## %s\n", file; prev = file }
      if (trigger == "") {
        printf "- L%s — ceiling: %s — **no-trigger**\n", lineno, ceiling
        untriggered++
      } else {
        printf "- L%s — ceiling: %s — trigger: %s\n", lineno, ceiling, trigger
      }
      total++
    }
    END {
      printf "\n%d marker%s, %d with no trigger.\n", total, (total == 1 ? "" : "s"), untriggered
    }
  '
}

main "$@"
