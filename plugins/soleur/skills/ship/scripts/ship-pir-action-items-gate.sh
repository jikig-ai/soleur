#!/usr/bin/env bash
# The /ship Phase 5.5 Incident-PIR SHAPE check: is a post-mortem's `## Action Items & Follow-ups`
# section in one of the two permitted forms?
#
#   (a) a table whose EVERY item row opens with a `#NNNN` Issue cell, and nothing else in the
#       section that reads as an action item (a bullet or numbered list beside the table is an
#       untracked item, not decoration), or
#   (b) a section with no item rows and no list items, carrying at column 0 the permitted no-item
#       sentence — plain, or with a single leading `_` or `*` marker (the two emphasised spellings
#       already shipped).
#
# This block lived inline in ship/SKILL.md until the #7941 plan; it was extracted for the reason
# #6813 extracted the gate's regexes and #7987 (PR #8011) its input: a check that exists only as
# prose in a skill file is executed by an agent reading it, and nothing tests it. The extraction
# is not a pure move — the acceptance set for (b) widened by the marker class, `--branch` checks
# EVERY PIR in the diff (the block checked only the first), list items beside a table now fail,
# fenced blocks and duplicate headings are handled, and "no PIR" and "git unavailable" got their
# own exit codes so the caller cannot mistake either for a pass.
#
# Usage:
#   ship-pir-action-items-gate.sh <path>     check one file
#   ship-pir-action-items-gate.sh --branch   check every PIR `git diff origin/main...HEAD` adds,
#                                            modifies or renames-to (read from the WORKING TREE —
#                                            commit the fix before re-running, the diff selects
#                                            committed paths)
#   ship-pir-action-items-gate.sh --corpus   check every tracked PIR (`git ls-files`), skipping
#                                            pre-template files that carry no section heading
#
# Exit codes:
#   0  every examined file passes (at least one `[PASS]` line on stdout)
#   1  at least one file fails (`[FAIL] <path>: <reason> — …` on stderr, one per file)
#   2  usage error, unreadable path, or git failed (`--branch`: `origin/main...HEAD` does not
#      resolve — a `master` repo, an unfetched or shallow clone with no merge base; `--corpus`:
#      `git ls-files` failed). In `--branch`/`--corpus` an unreadable file is exit 2 even when
#      other files failed — "could not measure" outranks "measured bad".
#   3  `--branch` found no PIR in the diff — a distinct code because the ship caller routes it to
#      its "No match" arm; discriminating that arm by scraping stdout is the unpinned-input class
#      #7987 removed
#
# Reasons (the first token after the colon on a `[FAIL]` line; the suite asserts them):
#   rows-without-issue   an item row does not open with `#NNNN`, or a list item sits in the
#                        section (with or without a table, with or without the sentence) — the
#                        fix is the same either way: file the issue and put the item in the table
#   no-sentence          no items at all and no permitted sentence at column 0 inside the section
#   no-heading           the file has no `## Action Items & Follow-ups` heading (outside fences)
#   duplicate-heading    more than one such heading — the section is ambiguous
#   not-a-regular-file   a symlink or non-file at the path — the gate grades committed bytes only
#
# `set -uo pipefail`, deliberately NOT `-e`: the row classifier's `grep -v` pipeline exits 1 on a
# table-free section (no match), and under `-e` that is a silent exit 1 with no verdict line —
# measured on the block's own pipelines. Sibling scripts in this directory use the same setting.
#
# Known limitation, stated rather than fixed: the sentence anchor is a PREFIX (see SENTENCE_RE);
# and `--corpus` skips a file with no heading as "pre-template", so a NEW PIR authored with a
# different heading is invisible to the corpus sweep — `--branch` (which the ship gate runs) does
# fail it with `no-heading`.

set -uo pipefail
export LC_ALL=C

SELECTOR='^knowledge-base/engineering/operations/post-mortems/.+-postmortem\.md$'
HEADING='## Action Items & Follow-ups'
# The permitted no-item sentence, anchored at column 0 with an OPTIONAL single `_` or `*` marker.
# The class is FROZEN: the template prescribes the plain form (so no new PIR is written with a
# marker) and the marker forms are the 21 PIRs shipped before that change. Do not widen it
# (`**` is a different shape, pinned red by a fixture) and do not narrow it to plain-only (that
# reds the 21 shipped files, which the skill cannot sweep in an operator's repository).
# PREFIX match, deliberately: four shipped PIRs append a resolution note after "fully resolved"
# (an issue list, a parenthetical), so end-anchoring would red them. The cost is that a suffix
# such as ", except the three items below" also passes — the gate checks the SHAPE the template
# prescribes, not the honesty of what follows it; that is what the Exit-0 arm's prose review is for.
SENTENCE_RE='^[_*]?No action items — incident fully resolved'
# A list item: bullet or numbered, optionally a task box. Inside the section these are action
# items that are not in the issue-backed table, whatever else the section holds.
ITEM_RE='^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]'

usage() {
  printf 'usage: %s <path> | --branch | --corpus\n' "$(basename "$0")" >&2
  exit 2
}

# section_lines <path> → the body of the FIRST `## Action Items & Follow-ups` section, with
# fenced code blocks removed (a fence toggles on any line starting with ``` or ~~~), ending at
# the next h1/h2 heading. Sub-headings (`### `) stay inside the section. Emits a first line
# `HEADINGS=<n>` counting real (unfenced, column-0) headings so the caller can classify 0 and >1.
section_lines() {
  awk -v h="$HEADING" '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    $0 == h { n++; if (n == 1) { f = 1 } else { f = 0 }; next }
    /^#{1,2} / { f = 0 }
    f { body = body $0 "\n" }
    END { printf "HEADINGS=%d\n%s", n, body }
  ' < "$1"
}

# check_one <path> → prints one verdict line; returns 0 (pass), 1 (fail), 2 (unreadable). Never exits.
check_one() {
  local f="$1" out n sec rows bad items
  if [[ ! -e "$f" && ! -L "$f" ]] || [[ -f "$f" && ! -r "$f" ]]; then
    printf 'PIR-ACTION-ITEMS: unreadable path %s\n' "$f" >&2
    return 2
  fi
  if [[ -L "$f" || ! -f "$f" ]]; then
    printf '[FAIL] %s: not-a-regular-file — the gate grades a committed regular file, not a link or a directory\n' "$f" >&2
    return 1
  fi
  out="$(section_lines "$f")"
  n="${out%%$'\n'*}"; n="${n#HEADINGS=}"
  sec="${out#*$'\n'}"
  if [[ "$n" -eq 0 ]]; then
    printf '[FAIL] %s: no-heading — no "%s" heading outside a fenced block; the section does not exist\n' "$f" "$HEADING" >&2
    return 1
  fi
  if [[ "$n" -gt 1 ]]; then
    printf '[FAIL] %s: duplicate-heading — %s "%s" headings; keep exactly one\n' "$f" "$n" "$HEADING" >&2
    return 1
  fi
  # Item rows = table rows minus the `| Issue |` header and the `|---|` divider.
  # `[[:space:]]`, not `\s`: ugrep and BusyBox grep disagree on the latter.
  rows="$(printf '%s\n' "$sec" | grep -E '^[[:space:]]*\|' \
          | grep -vE '^[[:space:]]*\|[[:space:]]*Issue[[:space:]]*\|' \
          | grep -vE '^[[:space:]]*\|[-:|[:space:]]+\|[[:space:]]*$' \
          | sed '/^[[:space:]]*$/d')"
  items="$(printf '%s\n' "$sec" | grep -E "$ITEM_RE")"
  # Shape (a): every item row MUST open with a `#NNNN` Issue cell (`#0` is not an issue). `#NNNN`
  # anywhere else in the row (an Action cell citing an issue) does not count — the Issue cell is
  # the tracked field. A list item anywhere in the section is an untracked item too.
  bad="$(printf '%s\n' "$rows" | sed '/^$/d' | grep -vE '^[[:space:]]*\|[[:space:]]*#[1-9][0-9]*[[:space:]]*\|')"
  if [[ -n "$bad" || -n "$items" ]]; then
    printf '[FAIL] %s: rows-without-issue — action items that do not open with a #NNNN Issue cell (file the issue, put the item in the table):\n' "$f" >&2
    printf '%s\n%s\n' "$bad" "$items" | sed '/^$/d; s/^/    /' >&2
    return 1
  fi
  if [[ -n "$rows" ]]; then
    printf '[PASS] %s\n' "$f"
    return 0
  fi
  # Shape (b): no items, so the permitted sentence is the ONLY valid form. Anchored at column 0
  # so the template's own instructional prose (a backticked copy mid-sentence) cannot satisfy it.
  if printf '%s\n' "$sec" | grep -qE "$SENTENCE_RE"; then
    printf '[PASS] %s\n' "$f"
    return 0
  fi
  printf '[FAIL] %s: no-sentence — no issue-backed table and no permitted no-item sentence at column 0 in "%s"\n' "$f" "$HEADING" >&2
  return 1
}

# select_paths <git args...> → NUL-delimited paths from git, filtered by SELECTOR, into `files`;
# sets `grc` to git's exit. NUL framing (never `--name-only` text) so a path git would C-quote
# (non-ASCII, tab, newline) still matches the anchored selector instead of vanishing.
files=()
LISTING_TMP=""
trap '[[ -n "$LISTING_TMP" ]] && rm -f "$LISTING_TMP"' EXIT
select_paths() {
  local p
  LISTING_TMP="$(mktemp -t pir-gate.XXXXXXXX)"
  git "$@" > "$LISTING_TMP"; grc=$?
  if [[ $grc -eq 0 ]]; then
    while IFS= read -r -d '' p; do
      [[ "$p" =~ $SELECTOR ]] && files+=("$p")
    done < "$LISTING_TMP"
  fi
}

[[ $# -eq 1 ]] || usage

case "$1" in
  --branch)
    # Run the diff ON ITS OWN, never inside a `|| true` pipeline: a git failure (128 when
    # origin/main does not resolve or has no merge base with HEAD — a `master` repo, an unfetched
    # or shallow clone) must surface as "unavailable", not as "no PIR". `--diff-filter=d` drops
    # only deletions; a rename is listed at its NEW path by `--name-only` whether or not rename
    # detection runs (measured: `--no-renames` is verdict-neutral, so it is not passed).
    # Three-dot, deliberately: two-dot would list main-owned changes as the branch's.
    select_paths diff -z --name-only --diff-filter=d origin/main...HEAD
    if [[ $grc -ne 0 ]]; then
      printf 'PIR-ACTION-ITEMS: unavailable — git diff origin/main...HEAD failed (rc=%s)\n' "$grc" >&2
      exit 2
    fi
    if [[ ${#files[@]} -eq 0 ]]; then
      printf 'PIR-ACTION-ITEMS: no PIR in diff\n'
      exit 3
    fi
    worst=0
    for f in "${files[@]}"; do
      check_one "$f"; rc=$?
      (( rc > worst )) && worst=$rc
    done
    exit "$worst"
    ;;
  --corpus)
    select_paths ls-files -z
    if [[ $grc -ne 0 ]]; then
      printf 'PIR-ACTION-ITEMS: unavailable — git ls-files failed (rc=%s)\n' "$grc" >&2
      exit 2
    fi
    selected=${#files[@]} examined=0 skipped=0 failed=0 worst=0
    for f in "${files[@]}"; do
      # `-r` first: `! grep -q` on an unreadable file (rc 2) would otherwise read as "no heading"
      # and SKIP it — an unreadable tracked PIR must reach check_one and its exit 2.
      if [[ -r "$f" ]] && ! grep -qE -- "^$HEADING" "$f"; then
        printf 'SKIP %s (no heading — pre-template)\n' "$f"
        skipped=$((skipped + 1))
        continue
      fi
      examined=$((examined + 1))
      check_one "$f"; rc=$?
      (( rc == 1 )) && failed=$((failed + 1))
      (( rc > worst )) && worst=$rc
    done
    printf 'PIR-ACTION-ITEMS: corpus selected=%s examined=%s skipped=%s failed=%s\n' \
      "$selected" "$examined" "$skipped" "$failed"
    exit "$worst"
    ;;
  --*) usage ;;
  *)
    check_one "$1"
    exit $?
    ;;
esac
