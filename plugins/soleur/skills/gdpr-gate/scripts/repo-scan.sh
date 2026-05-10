#!/usr/bin/env bash
# gdpr-gate `--repo-scan` walker.
#
# Operator-initiated only — never auto-fires from /soleur:plan, /soleur:work,
# or lefthook. Resolves the canonical regulated-data regex and the path
# deny-list, then emits surviving candidate paths to stdout. The dispatching
# agent reads stdout, batches 25 files per Haiku call (ADR-026 TR3), and
# summarises findings inline.
#
# Defenses (named in the v2 plan §"User-Brand Impact"):
#   D1  Path deny-list before any read           (path-denylist.txt)
#   D2  git ls-files -c -o --exclude-standard    (no working-tree rename laundering)
#   D3  Path-allowlist env var, two-clause typo  (GDPR_GATE_REPO_SCAN_ALLOW_PATHS)
#       defense + CI-environment refusal         (CI + ALLOW_PATHS → exit 1)
#   D4  Inline-only output                       (no disk persistence here)
#   D5  Schema-only invariant                    (carried by the prompt template)
#
# Outputs:
#   stdout — surviving candidate paths, one per line
#   stderr — `# blocked: <path>` for denied paths, `# bypass: <path>` for
#            denied-but-allow-listed paths, plus error messages on exit 1

set -euo pipefail
LC_ALL=POSIX
export LC_ALL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
DENYLIST_FILE="$SCRIPT_DIR/path-denylist.txt"

# CI-environment refusal must trip BEFORE we touch git or read SKILL.md, so
# misconfigured CI runbooks fail loudly at the script boundary.
if [[ -n "${CI:-}" && -n "${GDPR_GATE_REPO_SCAN_ALLOW_PATHS:-}" ]]; then
  echo "gdpr-gate repo-scan: allow-list bypass refused in CI environment" >&2
  exit 1
fi

if [[ ! -f "$SKILL_MD" ]]; then
  echo "gdpr-gate repo-scan: SKILL.md not found at $SKILL_MD" >&2
  exit 1
fi

if [[ ! -f "$DENYLIST_FILE" ]]; then
  echo "gdpr-gate repo-scan: deny-list not found at $DENYLIST_FILE" >&2
  exit 1
fi

# Extract the canonical regex from SKILL.md §"Path globs (canonical)".
# Layout: a `## Path globs (canonical)` heading, prose, then a fenced ```
# block whose first non-blank line is the regex (starts with `^`).
canonical_regex="$(awk '
  /^## Path globs \(canonical\)/ { found = 1; next }
  found && /^```/ { in_block = !in_block; next }
  found && in_block && /^[[:space:]]*\^/ { print; exit }
' "$SKILL_MD")"

if [[ -z "$canonical_regex" ]]; then
  echo "gdpr-gate repo-scan: canonical regex not found in SKILL.md" >&2
  exit 1
fi

# Load deny-list patterns (skip blanks and `#` comments).
declare -a denylist_patterns=()
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line="${raw_line%$'\r'}"
  [[ -z "${line// /}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  denylist_patterns+=("$line")
done < "$DENYLIST_FILE"

if (( ${#denylist_patterns[@]} == 0 )); then
  echo "gdpr-gate repo-scan: deny-list is empty" >&2
  exit 1
fi

# Parse GDPR_GATE_REPO_SCAN_ALLOW_PATHS (D3 two-clause defense).
declare -a allow_paths=()
allow_paths_raw="${GDPR_GATE_REPO_SCAN_ALLOW_PATHS:-}"
if [[ -n "$allow_paths_raw" ]]; then
  IFS=':' read -ra allow_paths <<< "$allow_paths_raw"
  for ap in "${allow_paths[@]}"; do
    matched=0
    for dp in "${denylist_patterns[@]}"; do
      if [[ "$ap" =~ $dp ]]; then matched=1; break; fi
    done
    if (( matched == 0 )); then
      echo "gdpr-gate repo-scan: bypass references non-blocked path: $ap" >&2
      exit 1
    fi
    if ! git ls-files -c -o --exclude-standard --error-unmatch -- "$ap" >/dev/null 2>&1; then
      echo "gdpr-gate repo-scan: bypass references nonexistent path: $ap" >&2
      exit 1
    fi
  done
fi

is_allowed() {
  local path="$1"
  local ap
  for ap in "${allow_paths[@]+"${allow_paths[@]}"}"; do
    [[ "$path" == "$ap" ]] && return 0
  done
  return 1
}

# Walk: candidate paths after canonical-regex filter, then deny/allow check.
git ls-files -c -o --exclude-standard | grep -E "$canonical_regex" | while IFS= read -r path; do
  denied=0
  for dp in "${denylist_patterns[@]}"; do
    if [[ "$path" =~ $dp ]]; then
      denied=1
      break
    fi
  done
  if (( denied == 1 )); then
    if is_allowed "$path"; then
      echo "# bypass: $path" >&2
    else
      echo "# blocked: $path" >&2
    fi
    continue
  fi
  printf '%s\n' "$path"
done
