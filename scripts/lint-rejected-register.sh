#!/usr/bin/env bash
# lint-rejected-register.sh — the guard over the no-list: `knowledge-base/project/rejected/`,
# the rejected-concepts record.
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. Within one commit this script proves INTERNAL
# CONSISTENCY, NOT TRUTH. It compares an entry's CLAIM (`redundancy_check: not-implemented`)
# against the EVIDENCE THE SAME FILE CARRIES (`searched:`) — both inside one file. A confidently
# wrong entry that is internally consistent passes, and no amount of pre-commit cleverness changes
# that. The gap closes OUTSIDE the commit, because each `searched:` line is a command plus its
# result count and any reviewer or later session can re-run it and get a different number if the
# concept has since been built. A second assertion — that no number in `prior_requests` resolves to
# an issue closed as `completed` — needs the network and is deliberately NOT in this tier.
#
# THE CHECKS, in the order a reader meets them:
#
#   1. filename       an entry is `YYYY-MM-DD-<concept-slug>.md`. Mechanical, not advisory: a
#                     concept-similarity lookup over this directory would otherwise match
#                     `README.md` and manufacture the exact false rejection the no-list exists to
#                     prevent. `README.md` is excluded from the entry set; anything else that does
#                     not match the pattern is a violation, never a silent skip.
#   2. required keys  aliases, scope, why, public_note, instead, revisit_if, searched,
#                     redundancy_check — each present AND non-empty. `aliases` is required because
#                     matching is by CONCEPT, not by wording: "night theme" has to reach
#                     `dark-mode`, and without aliases that is aspiration rather than mechanism.
#                     The `why`/`public_note` split exists so an agent never quotes the blunt
#                     internal reason outward; an entry with `why` and no `public_note` leaves the
#                     only quotable text the one that must not be quoted.
#   3. forbidden keys implemented_at, requester, requested_by — rejected outright, anywhere in the
#                     file. `implemented_at` can only be true of a BUILT feature, and an
#                     already-implemented `wontfix` is a redundancy finding, not a rejection.
#                     The requester field is REMOVED FROM THE SCHEMA rather than enum-guarded:
#                     with zero external filers there is nobody to record, a forbidden-key check is
#                     strictly safer than a closed-vocabulary one at the same cost, and this
#                     repository is PUBLIC — entries carry roles, never identities.
#   4. the enum       `redundancy_check` is compared WHOLE-VALUE. `not-implemented` CONTAINS
#                     `implemented`; a substring comparison inverts this guard silently, which is
#                     `cq-assert-anchor-not-bare-token` in its sharpest form. An entry carrying a
#                     non-empty `superseded_by:` is on the REOPEN path — it is excluded from
#                     concept matching, so its claim is `superseded`, compared whole-value too.
#   5. slug vs scope  the filename's concept slug must appear in the entry's own `scope:`. To an
#                     external reader THE FILENAME IS THE CLAIM: `rejected/2026-09-20-browser-
#                     automation.md` reads as "Soleur does not do browser automation" no matter
#                     what the body says.
#   6. advisory-only  an entry may not name itself as grounds to close or label an issue. A
#                     prior-rejection hit is reported to a human and escalates; it never acts.
#                     `deferred-scope-out` in particular must never be applied on the basis of a
#                     record hit — see knowledge-base/project/rejected/README.md for the two
#                     automated hops that turn a false entry into a permanently-closed issue.
#
# ASSEMBLY IS THE GLOB, NEVER A MANIFEST. `--all` walks the directory. A name list would go stale
# the first time somebody added an entry without editing it.
#
# DISPATCH IS THREE, and this script is written for all three. There is no single write chokepoint:
# `git commit --no-verify` and a merge-resolution commit both reach the repository without the
# pre-commit hook. So: lefthook pre-commit on the glob with {staged_files}, a lefthook pre-push
# mirror with {push_files}, and a CI step running `--all` over the WHOLE glob rather than the
# staged set. Handed zero paths this script reports `0 files` and exits non-zero: "no paths,
# exit 0, nothing checked" is the vacuous arm.
#
# Path filtering is the DISPATCH's job (lefthook's `glob:`, or `--all`'s walk). This script checks
# the files it is handed, by basename rules, so it is testable outside the repository tree.
#
# Usage:
#   lint-rejected-register.sh <file> [<file> ...]
#   lint-rejected-register.sh --all [<dir>]      # default: <repo>/knowledge-base/project/rejected
#
# Exit codes:
#   0  every entry handed to it is clean, and at least one path was handed to it
#   1  at least one violation (each printed `<file>: [tag] <message>` on stderr)
#   2  a named path does not exist or is not readable
#   3  nothing was checked — zero paths, or a walk that found no entries. NOT success.
#
# Battery: plugins/soleur/test/lint-rejected-register.test.sh (16 mutation rows, 5 axes).

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || SELF_DIR="."
DEFAULT_DIR="$SELF_DIR/../knowledge-base/project/rejected"

# The schema, as two lists. Row 15 of the battery deletes `implemented_at` from the second one to
# prove the forbidden-key branch is what carries the check.
REQUIRED_KEYS=(aliases scope why public_note instead revisit_if searched redundancy_check)
FORBIDDEN_KEYS=(implemented_at requester requested_by)

# The advisory-only deny-list. An entry matching any of these is claiming an authority it does not
# have. Case-insensitive, and each pattern is a phrase an entry has no legitimate reason to carry.
AUTHORITY_PATTERNS=(
  'deferred-scope-out'
  'auto-?close'
  'automatically clos'
  '(sufficient|enough) (grounds|basis|reason)'
  'grounds to (close|label)'
  '(may|can|should) be closed'
  'close (the|this|any) issue'
)

violations=0
checked=0

report() { # <file> <tag> <message>
  printf '%s: [%s] %s\n' "$1" "$2" "$3" >&2
  violations=$((violations + 1))
}

# fm_value <file> <key> — the raw value of a top-level frontmatter key, including folded/literal
# block bodies and list items. Empty output means "absent, or present with nothing in it", and the
# caller cannot tell those apart on purpose: both are the same defect.
fm_value() {
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit; infm = 1; next }
    infm && $0 == "---" { exit }
    !infm { exit }
    {
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/) {
        k = $0; sub(/[[:space:]]*:.*$/, "", k)
        if (k == key) { cap = 1; v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); if (v != "") print v; next }
        cap = 0; next
      }
      if (cap && $0 ~ /[^[:space:]]/) print $0
    }
  ' "$1"
}

has_frontmatter() { [[ "$(head -n 1 "$1")" == "---" ]]; }

# Block scalar indicators are structure, not content: `>-` alone is an empty value.
strip_block_indicators() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*[|>][+-]\?[[:space:]]*$//' -e 's/^[[:space:]]*-[[:space:]]*//' \
    | tr -d ' \t\n'
}

check_entry() { # <path>
  local file="$1" base slug key val rc_val want_rc slug_re pat
  base="$(basename "$file")"

  if [[ ! -r "$file" ]]; then
    printf 'lint-rejected-register: path not readable: %s\n' "$file" >&2
    return 2
  fi

  # 1. filename
  if [[ ! "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
    report "$file" "bad-filename" "an entry is named YYYY-MM-DD-<concept-slug>.md; anything else is not an entry, and a lookup that matched it would manufacture a rejection nobody made"
    return 0
  fi
  slug="${base%.md}"
  slug="${slug#????-??-??-}"

  if ! has_frontmatter "$file"; then
    report "$file" "no-frontmatter" "an entry opens with a YAML frontmatter fence on line 1"
    return 0
  fi

  # 2. required keys, present AND non-empty
  for key in "${REQUIRED_KEYS[@]}"; do
    val="$(fm_value "$file" "$key")"
    if [[ -z "$(strip_block_indicators "$val")" ]]; then
      report "$file" "missing-key:$key" "required field is absent or empty"
    fi
  done

  # 3. forbidden keys, anywhere in the file
  for key in "${FORBIDDEN_KEYS[@]}"; do
    if grep -qE "^[[:space:]]*${key}[[:space:]]*:" "$file"; then
      case "$key" in
        implemented_at)
          report "$file" "forbidden-key:$key" "only a BUILT feature has one; an already-implemented wontfix is a redundancy finding whose record is the closing comment naming where it lives, not an entry here" ;;
        *)
          report "$file" "forbidden-key:$key" "the requester field is not in the schema: this repository is public and entries carry roles, never identities" ;;
      esac
    fi
  done

  # 4. the enum, WHOLE-VALUE
  rc_val="$(strip_block_indicators "$(fm_value "$file" redundancy_check)")"
  want_rc="not-implemented"
  if [[ -n "$(strip_block_indicators "$(fm_value "$file" superseded_by)")" ]]; then
    # The reopen path: a superseded entry is excluded from concept matching, so it no longer
    # asserts anything about whether the concept is built.
    want_rc="superseded"
  fi
  if [[ -n "$rc_val" ]] && [[ "$rc_val" != "$want_rc" ]]; then
    report "$file" "enum:redundancy_check" "must be exactly '$want_rc' (whole-value: 'not-implemented' CONTAINS 'implemented', so a substring comparison would accept the poisoned value); found '$rc_val'"
  fi

  # 5. the filename's slug must not outrun the entry's own scope
  slug_re="$(printf '%s' "$slug" | sed 's/-/[- ]/g')"
  if ! printf '%s' "$(fm_value "$file" scope)" | grep -qiE "$slug_re"; then
    report "$file" "slug-outruns-scope" "the filename's concept slug ('${slug//-/ }') does not appear in the entry's own scope:; to an external reader the filename is the claim"
  fi

  # 6. advisory-only
  for pat in "${AUTHORITY_PATTERNS[@]}"; do
    if grep -qiE "$pat" "$file"; then
      report "$file" "authority-claim" "an entry may never be the sole basis for closing or labelling an issue: a prior-rejection hit is reported to a human and escalates, it never acts (matched: $pat)"
      break
    fi
  done

  return 0
}

# --- dispatch -------------------------------------------------------------------------------------

paths=()
if [[ "${1:-}" == "--all" ]]; then
  dir="${2:-$DEFAULT_DIR}"
  if [[ ! -d "$dir" ]]; then
    printf 'lint-rejected-register: 0 files — %s is not a directory, so nothing was checked and the no-list is NOT certified\n' "$dir" >&2
    exit 3
  fi
  # The walk IS the assembly. Sorted for a stable report; `README.md` is the convention document,
  # not an entry.
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    paths+=("$f")
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
else
  if [[ $# -eq 0 ]]; then
    printf 'lint-rejected-register: 0 files handed to the lint — nothing was checked and the no-list is NOT certified\n' >&2
    exit 3
  fi
  for f in "$@"; do
    [[ "$(basename "$f")" == "README.md" ]] && continue
    paths+=("$f")
  done
fi

if [[ "${#paths[@]}" -eq 0 ]]; then
  if [[ "${1:-}" == "--all" ]]; then
    printf 'lint-rejected-register: 0 files — the walk of %s found no entries, so the no-list is NOT certified\n' "${2:-$DEFAULT_DIR}" >&2
    exit 3
  fi
  # Reached only when every handed path was README.md. That is a legitimate pre-commit shape (the
  # convention document changed and no entry did), and it is reported rather than swallowed. The
  # record itself is certified by the CI `--all` arm, which never sees a partial set.
  printf 'lint-rejected-register: 0 entries (only the convention document was in the handed set)\n'
  exit 0
fi

missing=0
for f in "${paths[@]}"; do
  if [[ ! -f "$f" ]]; then
    printf 'lint-rejected-register: file not found: %s\n' "$f" >&2
    missing=1
    continue
  fi
  check_entry "$f" || missing=1
  checked=$((checked + 1))
done

if [[ "$violations" -gt 0 ]]; then
  printf 'lint-rejected-register: %d violation(s) across %d file(s) checked\n' "$violations" "$checked" >&2
  exit 1
fi
if [[ "$missing" -eq 1 ]]; then
  exit 2
fi
printf 'lint-rejected-register: %d file(s) checked, clean\n' "$checked"
exit 0
