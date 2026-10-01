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
# IT READS THE STAGED BLOB, NOT THE WORKING TREE, for any path git has an index entry for — see
# `staged_view` below. What remains uncovered is narrower and is not a staging question: a bare
# personal name is not a decidable property of text, so the editorial rule in the record's own README
# (record the substance, attribute to a ROLE) is the control for that and this guard is the floor
# under it.
# SO THIS IS A FLOOR, NOT A SOLUTION, and the distinction is the honest part. It catches the shapes
# that are mechanically recognisable — an email address, a long-form telephone number, a
# signature-block salutation. It cannot catch a bare personal name, which is the most likely leak and
# is not a decidable property of text. The remedy for that stays editorial: the README instructs
# recording the substance and attributing to a ROLE, and this gate stops the cases a regex can own.
set -uo pipefail

DEFAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/knowledge-base/project/questionnaires"

violations=0
checked=0

# --- CERTIFY THE STAGED BLOB, NOT THE WORKING TREE ------------------------------------------------
#
# lefthook hands `{staged_files}` as PATHS, and every read here opens the file on disk. Measured:
# append a forbidden key, `git add`, delete the line from the worktree copy, and this guard exits 0
# while the poisoned blob commits — with no `--no-verify` and no `LEFTHOOK=0`, so it is a bypass the
# DISPATCH note above does not list.
#
# THE INVERSE IS ALSO A DEFECT, and it is the one a worktree read causes rather than misses: under
# `git add -p` an UNSTAGED violation blocks a commit that does not contain it. The staged blob is by
# definition the commit`s content, so reading it removes a false negative AND a false positive. An
# earlier disposition here claimed the opposite trade and deferred the fix on that basis; the claim
# was inverted and the CONCUR gate refused the deferral.
#
# NO MODE FLAG AND NO DISPATCH CHANGE, because the case is DETECTABLE rather than declared:
# `git ls-files --error-unmatch` fails for an untracked path (a `--all` walk of an unstaged fixture,
# or a brand-new entry), and those fall back to the path as handed. For pre-push and CI the index
# matches what is being pushed on a clean tree, so the substitution is byte-identical there; on a
# dirty tree the index is still the closer proxy for committed content than the worktree is.
#
# The mirror preserves the FULL RELATIVE PATH so that every derivation downstream is unaffected —
# `basename` still yields the dated slug and `dirname`s parent still yields the record directory,
# which the filename, slug-in-scope, root-README and superseded_by checks all depend on.
# THE MIRROR DIRECTORY IS CREATED IN THE PARENT SHELL, EAGERLY, AND THAT IS NOT A STYLE CHOICE.
# `staged_view` is called from `paths+=("$(staged_view "$f")")`, i.e. inside a command substitution —
# a SUBSHELL. A first version created the directory lazily inside it, which put two bugs in one line:
# the assignment never reached the parent (so `unmirror` was a no-op and diagnostics printed the
# mirror path an operator cannot act on), and the cleanup `trap ... EXIT` fired at SUBSHELL exit,
# deleting the mirror between writing it and reading it. Measured: the leaked path appeared in the
# first diagnostic line. State that must outlive a command substitution is set before it.
# The trap is registered UNCONDITIONALLY and immediately after the allocation, never behind a
# `[[ -n … ]] &&` guard. `scripts/lint-trap-tempfile-ownership.py` rule (c) reads it that way for a
# reason that is not stylistic: a conditional trap statement is one the linter cannot see owns the
# allocation, and more importantly a script that dies between `mktemp -d` and a deferred registration
# leaks the directory. The emptiness check belongs in the trap BODY, where it costs nothing.
STAGED_MIRROR=""
trap '[[ -n "${STAGED_MIRROR:-}" ]] && rm -rf -- "${STAGED_MIRROR:?}"' EXIT INT TERM
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  STAGED_MIRROR="$(mktemp -d)" || STAGED_MIRROR=""
fi
# staged_view <path> -> prints a path whose CONTENT is what would be committed.
staged_view() {
  local p="$1" rel m out
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf "%s" "$p"; return 0; }
  git ls-files --error-unmatch -- "$p" >/dev/null 2>&1 || { printf "%s" "$p"; return 0; }
  rel="$(git ls-files --full-name -- "$p" 2>/dev/null | head -n 1)"
  [[ -n "$rel" ]] || { printf "%s" "$p"; return 0; }
  [[ -n "$STAGED_MIRROR" ]] || { printf "%s" "$p"; return 0; }
  out="$STAGED_MIRROR/$rel"
  mkdir -p "$(dirname "$out")" 2>/dev/null || { printf "%s" "$p"; return 0; }
  # A path staged as a DELETION has no blob; nothing to certify, so hand back the original and let
  # the existence checks speak.
  git show ":$rel" > "$out" 2>/dev/null || { printf "%s" "$p"; return 0; }
  printf "%s" "$out"
}
# Report paths as the caller spelled them: a mirror path in a diagnostic is an internal detail that
# the operator cannot act on.
unmirror() { local p="$1"; [[ -n "$STAGED_MIRROR" ]] && printf "%s" "${p#"$STAGED_MIRROR"/}" || printf "%s" "$p"; }
report() { printf '%s: [%s] %s\n' "$(unmirror "$1")" "$2" "$3" >&2; violations=$((violations + 1)); }

# Each pattern is a shape a questionnaire has no legitimate reason to carry. The recipient's ROLE is
# what the frontmatter records; none of these is a role.
#
# The email pattern deliberately excludes this repository's own operator addresses and the
# `*.example` / `example.com` reserved domains (RFC 2606), because a synthesized fixture must remain
# writable — `cq-test-fixtures-synthesized-only` requires fixtures to be synthetic, and a guard that
# refuses synthetic addresses makes the documented example unwritable.
check_file() { # <path>
  local f="$1" body hits
  [[ -r "$f" ]] || { printf 'lint-questionnaire-identity: path not readable: %s\n' "$(unmirror "$f")" >&2; return 2; }
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
    paths+=("$(staged_view "$f")")
  done < <(find "$dir" \( -type f -o -type l \) -print | LC_ALL=C sort)
else
  if [[ $# -eq 0 ]]; then
    printf 'lint-questionnaire-identity: 0 files handed to the lint — nothing was checked and the questionnaires are NOT certified\n' >&2
    exit 3
  fi
  for f in "$@"; do
    [[ "$(basename "$f")" == "README.md" ]] && continue
    paths+=("$(staged_view "$f")")
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
  [[ -e "$f" || -L "$f" ]] || { printf 'lint-questionnaire-identity: file not found: %s\n' "$(unmirror "$f")" >&2; exit 2; }
  check_file "$f" || exit 2
done

if [[ "$violations" -gt 0 ]]; then
  printf 'lint-questionnaire-identity: %d violation(s) across %d file(s) checked\n' "$violations" "$checked" >&2
  exit 1
fi
printf 'lint-questionnaire-identity: %d file(s) checked, clean\n' "$checked"
exit 0
