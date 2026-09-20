#!/usr/bin/env bash
# Third-party identity guard for knowledge-base/project/questionnaires/.
#
# WHY THIS EXISTS. That directory is the one surface in this repository designed to ingest ANOTHER
# PERSON'S WORDS — an accountant's, a lawyer's, a notary's — and the repository is PUBLIC with
# permanent history. The sibling rejected-concepts record removed `requester`/`requested_by` from its
# schema outright on exactly that ground: entries carry roles, never identities. A questionnaire that
# pastes an inbound reply restores the identity the sibling record refuses to hold, one directory over.
#
# THE SKILL'S OWN DEFENCES DO NOT REACH A HAND EDIT, which is why this exists as a commit-time gate
# rather than a step. `soleur:questionnaire-generate` assembles its `## Context` from a three-field
# allowlist and previews before writing, and `redact-sentinel.sh` backstops it — but that sentinel is
# SECRET-scoped, and this skill's own rationale records why a secret scan cannot hold this line: an
# accountant's name and direct line pass a secrets gate clean. And the `## Answers` section is filled
# in by hand, after the skill has finished, by a founder pasting an email. No step covers that.
#
#
# IT READS THE WORKING TREE, NOT THE STAGED BLOB, AND THAT IS A REAL HOLE — stated here because the
# word this guard prints is "clean". lefthook hands `{staged_files}` as PATHS; every read below
# (`head`, `awk`, `grep`) opens the file on disk. So: stage a poisoned entry, correct the worktree
# copy, commit. The guard reports clean and the poisoned blob lands, with no `--no-verify` and no
# `LEFTHOOK=0` — a bypass the DISPATCH enumeration above does not list. Measured on both this guard
# and its questionnaire sibling. Partial staging gives the inverse: a false positive on content that
# is not being committed.
#
# NOT FIXED HERE, deliberately. Reading `git show :<path>` instead is not a drop-in — it is correct
# for the pre-commit arm and wrong for the other two (`--all` and `{push_files}` have no index entry
# to read), and "check the staged blob" trades this false negative for the partial-stage false
# positive rather than closing the class. The honest answer is to check BOTH, per arm, which is a
# change to every content lint in this repository rather than to this one; the convention is
# repo-wide. Carried as a review finding with this disclosure as its disposition.
# SO THIS IS A FLOOR, NOT A SOLUTION, and the distinction is the honest part. It catches the shapes
# that are mechanically recognisable — an email address, a long-form telephone number, a
# signature-block salutation. It cannot catch a bare personal name, which is the most likely leak and
# is not a decidable property of text. The remedy for that stays editorial: the README instructs
# recording the substance and attributing to a ROLE, and this gate stops the cases a regex can own.
set -uo pipefail

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-base/project/questionnaires"

violations=0
checked=0
report() { printf '%s: [%s] %s\n' "$1" "$2" "$3" >&2; violations=$((violations + 1)); }

# Each pattern is a shape a questionnaire has no legitimate reason to carry. The recipient's ROLE is
# what the frontmatter records; none of these is a role.
#
# The email pattern deliberately excludes this repository's own operator addresses and the
# `*.example` / `example.com` reserved domains (RFC 2606), because a synthesized fixture must remain
# writable — `cq-test-fixtures-synthesized-only` requires fixtures to be synthetic, and a guard that
# refuses synthetic addresses makes the documented example unwritable.
check_file() { # <path>
  local f="$1" body hits
  [[ -r "$f" ]] || { printf 'lint-questionnaire-identity: path not readable: %s\n' "$f" >&2; return 2; }
  checked=$((checked + 1))

  # Strip fenced code blocks: a fence is quoted material, and the template itself shows shapes.
  body="$(awk '/^```/{f=!f; next} !f{print}' "$f")"

  hits="$(printf '%s' "$body" | grep -oiE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
    | grep -viE '@(example|example\.(com|org|net)|[A-Za-z0-9.-]+\.example)$' \
    | grep -viE '@(soleur\.ai|jikigai\.com|anthropic\.com|users\.noreply\.github\.com)$' || true)"
  if [[ -n "$hits" ]]; then
    report "$f" "third-party-email" "an email address reaches a PUBLIC repository with permanent history: $(printf '%s' "$hits" | head -n 1). Record the substance and attribute to the recipient's ROLE ('the accountant'), never to a person — the same rule that removed requester from the rejected-concepts schema"
  fi

  # A telephone number in long form. Bounded so an ISO date, an issue number and a money figure do not
  # match: requires a leading +, or a parenthesised area code, or 3+ separator-joined groups.
  if printf '%s' "$body" | grep -qE '(\+[0-9][0-9 ().-]{8,}[0-9])|(\([0-9]{2,4}\)[0-9 .-]{6,})|([0-9]{3,4}[ .-][0-9]{3,4}[ .-][0-9]{3,4})'; then
    report "$f" "third-party-phone" "a telephone number reaches a PUBLIC repository. The founder already has the recipient's contact details in their own mail client; this file does not need them"
  fi

  # A signature-block salutation is the tell that a reply was pasted rather than transcribed.
  if printf '%s' "$body" | grep -qiE '^[[:space:]]*(kind regards|best regards|yours (sincerely|faithfully)|sent from my)'; then
    report "$f" "pasted-reply" "a signature-block salutation means an inbound message was pasted whole. Transcribe each answer under its question and drop the greeting, the sign-off and the signature block — see knowledge-base/project/questionnaires/README.md"
  fi
  return 0
}

paths=()
if [[ "${1:-}" == "--all" ]]; then
  dir="${2:-$DEFAULT_DIR}"
  if [[ ! -d "$dir" ]]; then
    printf 'lint-questionnaire-identity: 0 files — %s is not a directory, so nothing was checked and the questionnaires are NOT certified\n' "$dir" >&2
    exit 3
  fi
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$(basename "$f")" == "README.md" ]] && continue
    paths+=("$f")
  done < <(find "$dir" \( -type f -o -type l \) -print | LC_ALL=C sort)
else
  if [[ $# -eq 0 ]]; then
    printf 'lint-questionnaire-identity: 0 files handed to the lint — nothing was checked and the questionnaires are NOT certified\n' >&2
    exit 3
  fi
  for f in "$@"; do
    [[ "$(basename "$f")" == "README.md" ]] && continue
    paths+=("$f")
  done
fi

if [[ "${#paths[@]}" -eq 0 ]]; then
  if [[ "${1:-}" == "--all" ]]; then
    printf 'lint-questionnaire-identity: 0 files — the walk of %s found no questionnaire, so nothing is certified\n' "${2:-$DEFAULT_DIR}" >&2
    exit 3
  fi
  printf 'lint-questionnaire-identity: 0 questionnaires (only the convention document was in the handed set)\n'
  exit 0
fi

for f in "${paths[@]}"; do
  [[ -e "$f" || -L "$f" ]] || { printf 'lint-questionnaire-identity: file not found: %s\n' "$f" >&2; exit 2; }
  check_file "$f" || exit 2
done

if [[ "$violations" -gt 0 ]]; then
  printf 'lint-questionnaire-identity: %d violation(s) across %d file(s) checked\n' "$violations" "$checked" >&2
  exit 1
fi
printf 'lint-questionnaire-identity: %d file(s) checked, clean\n' "$checked"
exit 0
