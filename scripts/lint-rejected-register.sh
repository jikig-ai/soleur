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
# DISPATCH IS THREE, and this script is written for all three: lefthook pre-commit on the glob with
# {staged_files}, a lefthook pre-push mirror with {push_files}, and a CI step running `--all` over
# the WHOLE glob rather than the staged set. Handed zero paths this script reports `0 files` and
# exits non-zero: "no paths, exit 0, nothing checked" is the vacuous arm.
#
# NONE OF THE THREE IS BLOCKING, AND THE READER MUST NOT INFER THAT THEY ARE. The two lefthook arms
# are bypassed by `--no-verify`, by `LEFTHOOK=0`, by any clone without lefthook installed, and by
# every server-side commit (a web-UI edit, a `gh api` content write, a squash-merge). The CI `--all`
# arm — the one written to cover exactly those — runs inside the `lint-bot-statuses` job, which
# declares itself ADVISORY at `.github/workflows/ci.yml` and is absent from
# `scripts/required-checks.txt`, so a PR merges with it RED. Verified:
# `grep -c lint-bot-statuses scripts/required-checks.txt` -> 0.
#
# Promoting it is deliberately NOT done here. `required-checks.txt` carries an auto-fabrication guard
# (#6049): adding a content-scoped gate name fabricates a green for bot PRs, and the canonical list
# is pinned by `required-checks-canonical-parity.test.sh` against a Terraform-managed ruleset, so the
# promotion is a separate change with its own review. Tracked as its own issue; until it lands, this
# guard is an ADVISORY one at every dispatch, and the record's correctness rests on review.
#
# One rationale that was wrong and is corrected rather than deleted, because it is load-bearing for
# anyone reasoning about coverage: earlier revisions of this comment (and of the two lefthook
# entries) said a "merge-resolution commit" reaches the repository without the pre-commit hook.
# It does not — lefthook keys `merge` on MERGE_HEAD, this entry carries no `skip: merge`, so a
# merge-resolution commit, an amended merge commit and a `cherry-pick --continue` all DO run the
# guard (measured, lefthook 2.1.6; see the note at lefthook.yml). The genuinely uncovered merge is
# the CLEAN one, which auto-commits, and the server-side one, which runs no hook at all.
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

# is_record_root_readme <path> <record-root> — the convention document, and ONLY at the root.
#
# Compared on the CANONICAL directory, never on the path string. The first version of this exemption
# was a string equality against `$DEFAULT_DIR/README.md`, and `DEFAULT_DIR` is an ABSOLUTE path
# derived from the script's own location (`$SELF_DIR/../knowledge-base/project/rejected`) while
# lefthook hands `{staged_files}`/`{push_files}` as REPOSITORY-RELATIVE paths. The two spellings never
# matched, so the record's own README was linted as an entry and the pre-push hook refused the push —
# caught by the hook rather than by the battery, because every battery row builds its fixtures from an
# absolute `$TMP_ROOT` and so only ever exercised the spelling that worked.
#
# `cd … && pwd -P` resolves `.`, `..`, a relative prefix and a symlinked root alike, and it keeps the
# exemption root-scoped: `<root>/archive/README.md` canonicalises to a different directory and stays a
# subject, which is the hole this exemption had to stop being.
is_record_root_readme() {
  local f="$1" root="$2" fd rd
  [[ "$(basename "$f")" == "README.md" ]] || return 1
  fd="$(cd "$(dirname "$f")" 2>/dev/null && pwd -P)" || return 1
  rd="$(cd "$root" 2>/dev/null && pwd -P)" || return 1
  [[ "$fd" == "$rd" ]]
}

# Block scalar indicators are structure, not content: `>-` alone is an empty value.
strip_block_indicators() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*[|>][+-]\?[[:space:]]*$//' -e 's/^[[:space:]]*-[[:space:]]*//' \
    | tr -d ' \t\n'
}

# YAML quoting is presentation, not value. `redundancy_check: "not-implemented"` and
# `redundancy_check: not-implemented` are the SAME value, and the whole-value enum compare below
# rejected the quoted spelling — so the one entry most likely to be written by a careful author was
# the one the guard refused. Strips one matched layer of surrounding single or double quotes, which
# is all YAML permits on a plain scalar.
unquote_scalar() {
  local v="$1"
  [[ "$v" =~ ^\"(.*)\"$ ]] && v="${BASH_REMATCH[1]}"
  [[ "$v" =~ ^\'(.*)\'$ ]] && v="${BASH_REMATCH[1]}"
  printf '%s' "$v"
}

# Normalise prose for an EQUALITY comparison between two fields: case, punctuation and whitespace
# all folded away, because `public_note` duplicating `why` is a content defect and not a formatting
# one, and the two will never be byte-identical.
normalise_prose() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

check_entry() { # <path>
  local file="$1" base slug key val rc_val want_rc slug_re pat
  base="$(basename "$file")"

  if [[ ! -r "$file" ]]; then
    printf 'lint-rejected-register: path not readable: %s\n' "$file" >&2
    return 2
  fi

  # 1. filename. A non-conforming name is reported and the schema checks are skipped (they would be
  # noise on a file that is not an entry) — but checks 3 and 6 still run, because the PII check and
  # the authority-claim check are exactly the ones that matter most on an irregular file, and an
  # early `return 0` here meant the files most likely to be irregular were the only ones never
  # inspected for a `requester:` or a self-granted authority.
  local name_ok=1
  if [[ ! "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$ ]]; then
    report "$file" "bad-filename" "an entry is named YYYY-MM-DD-<concept-slug>.md; anything else is not an entry, and a lookup that matched it would manufacture a rejection nobody made"
    name_ok=0
  fi
  if [[ -L "$file" ]]; then
    report "$file" "symlink-entry" "an entry is a regular file: a symlink puts the bytes the record certifies outside the record, where neither this guard's walk nor a reviewer's diff sees them"
    name_ok=0
  fi
  if [[ "$name_ok" -eq 0 ]]; then
    check_forbidden_keys "$file"
    check_authority_claim "$file"
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
  check_forbidden_keys "$file"

  # 4. the enum, WHOLE-VALUE
  rc_val="$(unquote_scalar "$(strip_block_indicators "$(fm_value "$file" redundancy_check)")")"
  want_rc="not-implemented"
  if [[ -n "$(unquote_scalar "$(strip_block_indicators "$(fm_value "$file" superseded_by)")")" ]]; then
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
  check_authority_claim "$file"

  # 7. `searched` records EVIDENCE, not intentions. The contract in the record's README is a list of
  # commands each followed by what it returned (`-> N`), because the field exists to make the
  # redundancy search auditable — the same discipline as
  # `hr-no-dashboard-eyeball-pull-data-yourself`. Presence was checked; shape was not, so
  # `searched: - looked around` satisfied the guard completely.
  local searched_items=0 searched_bad=0 line
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    searched_items=$((searched_items + 1))
    printf '%s' "$line" | grep -q -- '->' || searched_bad=$((searched_bad + 1))
  done <<< "$(fm_value "$file" searched)"
  if [[ "$searched_items" -gt 0 && "$searched_bad" -gt 0 ]]; then
    report "$file" "searched-no-result" "$searched_bad of $searched_items searched: item(s) record a command with no result: each line is '<command> -> <what it returned>', because an unauditable search is the claim this field exists to replace"
  fi

  # 8. `public_note` is what an agent quotes OUTWARD; `why` is the reasoning for a reader who already
  # has the context. If they are the same text the split has collapsed, and the blunt version is what
  # gets pasted at the person whose request was refused.
  local pn wy
  pn="$(normalise_prose "$(fm_value "$file" public_note)")"
  wy="$(normalise_prose "$(fm_value "$file" why)")"
  if [[ -n "$pn" && "$pn" == "$wy" ]]; then
    report "$file" "public_note-equals-why" "public_note duplicates why: the split exists because one is addressed to a reader who has the context and the other to one who does not, and an agent quotes public_note"
  fi

  # 9. `superseded_by` is the reopen path, and a dangling one is worse than none: the entry is
  # excluded from concept matching (so it stops answering "was this refused?") while pointing at
  # nothing that answers it instead.
  local sup sup_base
  sup="$(unquote_scalar "$(strip_block_indicators "$(fm_value "$file" superseded_by)")")"
  if [[ -n "$sup" ]]; then
    sup_base="$(basename "$sup")"
    if [[ ! -e "$(dirname "$file")/$sup_base" ]]; then
      report "$file" "dangling-superseded_by" "superseded_by names '$sup', which is not a file in this record: a superseded entry is skipped by the concept lookup, so a dangling pointer silently removes the refusal from the record instead of redirecting it"
    fi
  fi

  return 0
}

# The two checks that run on EVERY file handed in, conforming name or not.
check_forbidden_keys() { # <path>
  local file="$1" key
  for key in "${FORBIDDEN_KEYS[@]}"; do
    # Spelling is not the contract; the KEY is. `requester:`, `"requester":`, `Requester:` and an
    # inline-flow `{requester: x}` are the same field, and an anchored lower-case-only pattern
    # accepted three of the four. This repository is public: the check has to be about the field.
    if grep -qiE "(^|[[:space:]{,])[\"']?${key}[\"']?[[:space:]]*:" "$file"; then
      case "$key" in
        implemented_at)
          report "$file" "forbidden-key:$key" "only a BUILT feature has one; an already-implemented wontfix is a redundancy finding whose record is the closing comment naming where it lives, not an entry here" ;;
        *)
          report "$file" "forbidden-key:$key" "the requester field is not in the schema: this repository is public and entries carry roles, never identities" ;;
      esac
    fi
  done
}

check_authority_claim() { # <path>
  local file="$1" pat
  for pat in "${AUTHORITY_PATTERNS[@]}"; do
    if grep -qiE "$pat" "$file"; then
      report "$file" "authority-claim" "an entry may never be the sole basis for closing or labelling an issue: a prior-rejection hit is reported to a human and escalates, it never acts (matched: $pat)"
      break
    fi
  done
}

# --- dispatch -------------------------------------------------------------------------------------

paths=()
if [[ "${1:-}" == "--all" ]]; then
  dir="${2:-$DEFAULT_DIR}"
  if [[ ! -d "$dir" ]]; then
    printf 'lint-rejected-register: 0 files — %s is not a directory, so nothing was checked and the no-list is NOT certified\n' "$dir" >&2
    exit 3
  fi
  # THE WALK IS THE ASSEMBLY, AND ITS SHAPE IS THE WHOLE PROPERTY. The checks are stated over "no
  # file in the rejected-concepts record", so every predicate narrowing this walk carves an exact,
  # enumerable hole in that claim — and a file in the hole is a member of the record for every
  # CONSUMER (`generate-kb-index.sh` walks it recursively with no depth bound, so a subdirectory entry
  # is indexed into knowledge-base/INDEX.md and is discoverable by `soleur:kb-search` and by any
  # agent's own grep) while being a non-member for the guard.
  #
  # Measured on the earlier `-maxdepth 1 -type f -name '*.md'` form: a record holding one clean entry
  # plus three poisoned ones — a symlink, a subdirectory entry, and a `.MD` — reported
  # `1 file(s) checked, clean` and exited 0, while a `requester:` naming a real person, an inverted
  # enum and a self-granted authority to apply `deferred-scope-out` sat inside the record it had just
  # certified. Handed those same files explicitly the guard reddened correctly on every one: the
  # checks were sound and the assembly was the defect.
  #
  # So this walk is DELIBERATELY over-inclusive: recursive, symlinks included, every extension. A
  # file that is not an entry gets reported as one rather than skipped, because in this directory
  # "not an entry" is itself the finding. Only the record's OWN root README.md is exempt — a
  # README.md in a subdirectory is not the convention document, and the earlier basename-only skip
  # made `rejected/archive/README.md` a hole large enough to park an entry in.
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    is_record_root_readme "$f" "$dir" && continue
    paths+=("$f")
  done < <(find "$dir" \( -type f -o -type l \) -print | LC_ALL=C sort)
else
  if [[ $# -eq 0 ]]; then
    printf 'lint-rejected-register: 0 files handed to the lint — nothing was checked and the no-list is NOT certified\n' >&2
    exit 3
  fi
  for f in "$@"; do
    # Root-only, via the SAME predicate the walk uses: `<record>/archive/README.md` is not the
    # convention document, and skipping it on basename alone returned rc=0 for a file with arbitrary
    # contents. Shared rather than re-derived, because the two arms receive different path spellings
    # and a second copy is where that difference goes unnoticed.
    is_record_root_readme "$f" "$DEFAULT_DIR" && continue
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
  # whole-record pass is the CI `--all` arm, which never sees a partial set — but that arm is
  # advisory (see the DISPATCH note in the header), so this is a gap narrowed, not closed.
  printf 'lint-rejected-register: 0 entries (only the convention document was in the handed set)\n'
  exit 0
fi

missing=0
for f in "${paths[@]}"; do
  # `-e`, not `-f`: a symlink IS a member of the record and must reach check_entry, which reports it
  # as `symlink-entry`. Under `-f` a broken symlink also read as "file not found", which is an
  # infrastructure complaint rather than the finding it actually is.
  if [[ ! -e "$f" && ! -L "$f" ]]; then
    printf 'lint-rejected-register: file not found: %s\n' "$f" >&2
    missing=1
    continue
  fi
  check_entry "$f" || missing=1
  checked=$((checked + 1))
done

# CROSS-ENTRY UNIQUENESS. Every check above is per-file and therefore structurally blind to this:
# the entry key is the concept PLUS its aliases, so two entries claiming one alias make a lookup
# non-deterministic — it returns whichever the walk reached first, and the two may disagree about
# whether the concept is refused. Only a pass that has seen every entry can see it, so it runs here,
# and only when the walk was whole (`--all`); on a staged subset the absence of a collision is not
# evidence of uniqueness, and reporting it as such would be the vacuous arm.
if [[ "${1:-}" == "--all" && "${#paths[@]}" -gt 1 ]]; then
  dupes="$(
    for f in "${paths[@]}"; do
      [[ -f "$f" ]] || continue
      b="$(basename "$f")"
      [[ "$b" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]] || continue
      # The slug is itself an alias for this purpose — a lookup matches on either.
      sl="${b%.md}"; printf '%s\t%s\n' "$(normalise_prose "${sl#????-??-??-}")" "$f"
      while IFS= read -r a; do
        a="$(normalise_prose "$a")"
        [[ -n "$a" ]] && printf '%s\t%s\n' "$a" "$f"
      done <<< "$(fm_value "$f" aliases)"
    done | LC_ALL=C sort | awk -F'\t' '
      { if ($1 == prev_k && $2 != prev_f) print $1 "\t" prev_f "\t" $2; prev_k = $1; prev_f = $2 }'
  )"
  if [[ -n "$dupes" ]]; then
    while IFS=$'\t' read -r k f1 f2; do
      [[ -n "$k" ]] || continue
      report "$f2" "duplicate-alias" "the concept key '$k' is also claimed by $f1: the entry key is the concept plus its aliases, so two claimants make the lookup return whichever the walk reached first — merge them, or supersede one"
    done <<< "$dupes"
  fi
fi

if [[ "$violations" -gt 0 ]]; then
  printf 'lint-rejected-register: %d violation(s) across %d file(s) checked\n' "$violations" "$checked" >&2
  exit 1
fi
if [[ "$missing" -eq 1 ]]; then
  exit 2
fi
printf 'lint-rejected-register: %d file(s) checked, clean\n' "$checked"
exit 0
