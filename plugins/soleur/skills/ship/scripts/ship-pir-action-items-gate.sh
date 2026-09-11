#!/usr/bin/env bash
# The /ship Phase 5.5 Incident-PIR SHAPE check: is a post-mortem's `## Action Items & Follow-ups`
# section in one of the two permitted forms?
#
#   (a) a table whose EVERY item row opens with a `#NNNN` Issue cell, or
#   (b) a table-free section carrying, at column 0, the permitted no-item sentence — plain, or
#       with a single leading `_` or `*` marker (the two emphasised spellings already shipped).
#
# This block lived inline in ship/SKILL.md until the #7941 plan; it was extracted for the reason
# #6813 extracted the gate's regexes and #7987 (PR #8011) its input: a check that exists only as
# prose in a skill file is executed by an agent reading it, and nothing tests it. The extraction
# is not a pure move — the acceptance set for (b) widened by the marker class, `--branch` checks
# EVERY PIR in the diff (the block checked only the first), and "no PIR" and "git unavailable"
# got their own exit codes so the caller cannot mistake either for a pass.
#
# Usage:
#   ship-pir-action-items-gate.sh <path>     check one file
#   ship-pir-action-items-gate.sh --branch   check every PIR `git diff origin/main...HEAD` adds,
#                                            modifies or renames-to
#   ship-pir-action-items-gate.sh --corpus   check every tracked PIR (`git ls-files`), skipping
#                                            pre-template files that carry no section heading
#
# Exit codes:
#   0  every examined file passes (at least one `[PASS]` line on stdout)
#   1  at least one file fails (`[FAIL] <path>: <reason> — …` on stderr, one per file)
#   2  usage error, unreadable path, or `git diff origin/main...HEAD` failed (`--branch`)
#   3  `--branch` found no PIR in the diff — a distinct code because the ship caller routes it to
#      its "No match" arm; discriminating that arm by scraping stdout is the unpinned-input class
#      #7987 removed
#
# Reasons (the first token after the colon on a `[FAIL]` line; the suite asserts them):
#   rows-without-issue   shape (a) with at least one item row not opening with `#NNNN`
#   no-sentence          no item rows and no permitted sentence at column 0 inside the section
#   no-heading           the file has no `## Action Items & Follow-ups` heading at all
#
# `set -uo pipefail`, deliberately NOT `-e`: the row classifier's `grep -v` pipeline exits 1 on a
# table-free section (no match), and under `-e` that is a silent exit 1 with no verdict line —
# measured on the block's own pipelines. Sibling scripts in this directory use the same setting.
#
# Known limitation, stated rather than fixed: the section extraction (heading to the next `## `)
# is not fence-aware, so a fenced block INSIDE the section that contains a `## ` line ends the
# section early. Fail-closed; zero such files in the corpus when this was written.

set -uo pipefail
export LC_ALL=C

SELECTOR='^knowledge-base/engineering/operations/post-mortems/.+-postmortem\.md$'
HEADING='## Action Items & Follow-ups'
# The permitted no-item sentence, anchored at column 0 with an OPTIONAL single `_` or `*` marker.
# The class is FROZEN: the template prescribes the plain form (so no new PIR is written with a
# marker) and the marker forms are the 21 PIRs shipped before that change. Do not widen it
# (`**` is a different shape, pinned red by a fixture) and do not narrow it to plain-only (that
# reds the 21 shipped files, which the skill cannot sweep in an operator's repository).
SENTENCE_RE='^[_*]?No action items — incident fully resolved'

usage() {
  printf 'usage: %s <path> | --branch | --corpus\n' "$(basename "$0")" >&2
  exit 2
}

# check_one <path> → prints one verdict line; returns 0 (pass) or 1 (fail). Never exits.
check_one() {
  local f="$1" sec rows bad n
  if [[ ! -r "$f" ]]; then
    printf 'PIR-ACTION-ITEMS: unreadable path %s\n' "$f" >&2
    return 2
  fi
  if ! grep -qE -- "^$HEADING" "$f"; then
    printf '[FAIL] %s: no-heading — no "%s" heading; the section does not exist\n' "$f" "$HEADING" >&2
    return 1
  fi
  sec="$(awk -v h="$HEADING" 'index($0, h)==1 {f=1; next} /^## /{f=0} f' "$f")"
  # Item rows = table rows minus the `| Issue |` header and the `|---|` divider.
  # `[[:space:]]`, not `\s`: ugrep and BusyBox grep disagree on the latter.
  rows="$(printf '%s\n' "$sec" | grep -E '^[[:space:]]*\|' \
          | grep -vE '^[[:space:]]*\|[[:space:]]*Issue[[:space:]]*\|' \
          | grep -vE '^[[:space:]]*\|[-:|[:space:]]+\|[[:space:]]*$' \
          | sed '/^[[:space:]]*$/d')"
  if [[ -n "$rows" ]]; then
    # Shape (a): every item row MUST open with a `#NNNN` Issue cell. `#NNNN` anywhere else in the
    # row (an Action cell citing an issue) does not count — the Issue cell is the tracked field.
    bad="$(printf '%s\n' "$rows" | grep -vE '^[[:space:]]*\|[[:space:]]*#[0-9]+[[:space:]]*\|')"
    if [[ -n "$bad" ]]; then
      n="$(printf '%s\n' "$bad" | grep -c .)"
      printf '[FAIL] %s: rows-without-issue — %s action-item row(s) do not open with a #NNNN Issue cell:\n' "$f" "$n" >&2
      printf '%s\n' "$bad" | sed 's/^/    /' >&2
      return 1
    fi
    printf '[PASS] %s\n' "$f"
    return 0
  fi
  # Shape (b): no item rows, so the permitted sentence is the ONLY valid form. Anchored at column
  # 0 so the template's own instructional prose (a backticked copy mid-sentence) cannot satisfy it.
  if printf '%s\n' "$sec" | grep -qE "$SENTENCE_RE"; then
    printf '[PASS] %s\n' "$f"
    return 0
  fi
  printf '[FAIL] %s: no-sentence — no issue-backed table and no permitted no-item sentence at column 0 in "%s"\n' "$f" "$HEADING" >&2
  return 1
}

# check_many <path>... → runs check_one over each; exit 1 if any failed, 2 if any unreadable, else 0.
check_many() {
  local f rc worst=0
  for f in "$@"; do
    check_one "$f"; rc=$?
    (( rc > worst )) && worst=$rc
  done
  return "$worst"
}

[[ $# -eq 1 ]] || usage

case "$1" in
  --branch)
    # Run the diff ON ITS OWN, never inside a `|| true` pipeline: a git failure (128 when
    # origin/main does not resolve — a `master` repo, an unfetched clone) must surface as
    # "unavailable", not as "no PIR". `--no-renames` reports a renamed PIR as A at its new path
    # (checked) plus D at the old one; `--diff-filter=d` drops only the deletions.
    listing="$(git diff --name-only --no-renames --diff-filter=d origin/main...HEAD)"; grc=$?
    if [[ $grc -ne 0 ]]; then
      printf 'PIR-ACTION-ITEMS: unavailable — git diff origin/main...HEAD failed (rc=%s)\n' "$grc" >&2
      exit 2
    fi
    mapfile -t files < <(printf '%s\n' "$listing" | grep -E "$SELECTOR")
    if [[ ${#files[@]} -eq 0 ]]; then
      printf 'PIR-ACTION-ITEMS: no PIR in diff\n'
      exit 3
    fi
    check_many "${files[@]}"
    exit $?
    ;;
  --corpus)
    listing="$(git ls-files)"; grc=$?
    if [[ $grc -ne 0 ]]; then
      printf 'PIR-ACTION-ITEMS: unavailable — git ls-files failed (rc=%s)\n' "$grc" >&2
      exit 2
    fi
    mapfile -t files < <(printf '%s\n' "$listing" | grep -E "$SELECTOR")
    selected=${#files[@]} examined=0 skipped=0 failed=0
    for f in "${files[@]}"; do
      if ! grep -qE -- "^$HEADING" "$f"; then
        printf 'SKIP %s (no heading — pre-template)\n' "$f"
        skipped=$((skipped + 1))
        continue
      fi
      examined=$((examined + 1))
      check_one "$f" || failed=$((failed + 1))
    done
    printf 'PIR-ACTION-ITEMS: corpus selected=%s examined=%s skipped=%s failed=%s\n' \
      "$selected" "$examined" "$skipped" "$failed"
    [[ $failed -eq 0 ]]
    exit $?
    ;;
  --*) usage ;;
  *)
    check_one "$1"
    exit $?
    ;;
esac
