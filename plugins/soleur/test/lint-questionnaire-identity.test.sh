#!/usr/bin/env bash
# Behavioural battery for scripts/lint-questionnaire-identity.sh.
#
# THE MATRIX. 13 rows across 4 axes (fixture shape, fixture direction, dispatch, SUT). Every row
# drives the guard RED except the five MUST-PASS rows, each labelled at its definition — and those
# five are the load-bearing half here. A guard over a PUBLIC directory of third-party correspondence
# is trivially satisfiable by refusing everything, and refusing everything would make the documented
# worked example uncommittable and the skill unusable. So each false-positive control is paired with
# the true-positive it must not swallow.
#
#   #   axis               input                                             behaviour
#   1   fixture shape      a real-looking email address                      reaches a public repo forever
#   2   fixture shape      a +CC long-form telephone number                  the founder's mail client already has it
#   3   fixture shape      a parenthesised area code                         same class, second spelling
#   4   fixture shape      separator-joined digit groups                     same class, third spelling
#   5   fixture shape      "Kind regards" at line start                      the tell that a reply was pasted whole
#   6   fixture shape      "Sent from my" at line start                      same class, and the commonest one
#   7   fixture direction  the committed worked example, unmodified          MUST PASS — or the skill ships unusable
#   8   fixture direction  an @example.com address (RFC 2606)                MUST PASS — a synthesized fixture must stay writable
#   9   fixture direction  an @*.example address                             MUST PASS — same reserved space
#  10   fixture direction  ISO dates, issue numbers, a money figure          MUST PASS — none of these is a phone number
#  11   fixture direction  the offending shapes inside a fenced block        MUST PASS — a fence is quoted material
#  12   dispatch           invoked with zero path arguments                  "no paths, exit 0" is the vacuous arm
#  13   dispatch           staged poison + corrected worktree, and its inverse  the guard must certify the BLOB, not the tree
#
# THE FLOOR. One, direct, printf + exit 1, never routed through the verdict helpers (ADR-193): a floor
# enforced through the machinery it guards cannot witness that machinery being neutered.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LINT="${SOLEUR_QI_LINT:-${ROOT:?}/scripts/lint-questionnaire-identity.sh}"
EXAMPLE="${ROOT:?}/knowledge-base/project/questionnaires/2026-09-20-accountant-prepaid-hosting-contract.md"
[[ -f "$LINT" ]] || { printf 'FATAL: the SUT does not exist: %s\n' "$LINT" >&2; exit 2; }
[[ -f "$EXAMPLE" ]] || { printf 'FATAL: the worked example does not exist: %s\n' "$EXAMPLE" >&2; exit 2; }

# shellcheck source=plugins/soleur/test/lib/git-fixture-env.sh
source "${ROOT:?}/plugins/soleur/test/lib/git-fixture-env.sh" \
  || { printf 'FATAL: could not source plugins/soleur/test/lib/git-fixture-env.sh\n' >&2; exit 2; }

TMP_ROOT="$(mktemp -d)" || { printf 'FATAL: no scratch root\n' >&2; exit 2; }
: "${TMP_ROOT:?}"
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT INT TERM
# row13 runs `git init` inside TMP_ROOT. This sets a discovery ceiling there, pins identity and
# scrubs every inherited git-location variable, so a fixture commit cannot reach the real repository.
git_fixture_env "${TMP_ROOT:?}" || { printf 'FATAL: could not build a hermetic fixture environment\n' >&2; exit 2; }

passes=0; fails=0; asserted=0
VERDICT_LOG="${TMP_ROOT:?}/verdicts.txt"; : > "$VERDICT_LOG"
ok()  { printf '  PASS: %s\n' "$1"; printf 'PASS\n' >> "$VERDICT_LOG"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; printf 'FAIL\n' >> "$VERDICT_LOG"; fails=$((fails + 1)); }
ck()  { asserted=$((asserted + 1)); }

# A fixture is the COMMITTED example plus one appended line, so every row differs from the control by
# exactly the thing it is about. Synthesized throughout — no real address, firm or number
# (cq-test-fixtures-synthesized-only).
fixture() { # <name> <appended-text> -> prints the path
  local f="${TMP_ROOT:?}/$1.md"
  cp "$EXAMPLE" "$f" || { printf 'FATAL setup: could not seed %s\n' "$f" >&2; exit 2; }
  [[ -n "${2:-}" ]] && printf '\n%s\n' "$2" >> "$f"
  printf '%s' "$f"
}
run_lint() { OUT="$( "$BASH" "$LINT" "$@" 2>&1 || true )"; "$BASH" "$LINT" "$@" >/dev/null 2>&1; RC=$?; }

# --- THE CONTROL, first, and it ABORTS rather than counting a failure: a red baseline voids every row.
run_lint "$EXAMPLE"
if [[ "$RC" -ne 0 ]]; then
  printf 'FATAL: the UNMODIFIED worked example is RED (rc=%s). Every row below would be meaningless.\n%s\n' "$RC" "$OUT" >&2
  exit 2
fi
printf 'lint-questionnaire-identity.test.sh\n  control: the committed worked example is accepted (rc=0)\n'

red_row() { # <id> <tag> <appended-text>
  local id="$1" tag="$2" f; f="$(fixture "$id" "$3")"
  run_lint "$f"
  ck
  if [[ "$RC" -eq 1 && "$OUT" == *"$tag"* ]]; then ok "$id: reddened with $tag"
  else bad "$id: expected rc=1 and $tag; got rc=$RC: $OUT"; fi
}
green_row() { # <id> <why> <appended-text>
  local id="$1" why="$2" f; f="$(fixture "$id" "$3")"
  run_lint "$f"
  ck
  if [[ "$RC" -eq 0 ]]; then ok "$id (MUST-PASS): $why"
  else bad "$id (MUST-PASS): $why — but it was REJECTED (rc=$RC): $OUT"; fi
}

red_row row01-email          '[third-party-email]' 'Reply received from a.person@realfirm.co.uk about the treatment.'
red_row row02-phone-plus     '[third-party-phone]' 'They asked to be called on +44 20 7946 0958 before Friday.'
red_row row03-phone-parens   '[third-party-phone]' 'Switchboard (0207) 946 0958 reaches the practice.'
red_row row04-phone-groups   '[third-party-phone]' 'Direct line 0207 946 0958 during office hours.'
red_row row05-signoff        '[pasted-reply]'      'Kind regards'
red_row row06-sent-from      '[pasted-reply]'      'Sent from my phone'

green_row row07-worked-example  'the committed worked example stays committable' ''
green_row row08-rfc2606-com     'an @example.com address stays writable, so a synthesized fixture can exist' 'Write to someone@example.com if a reply is needed.'
green_row row09-rfc2606-sub     'an @<anything>.example address stays writable for the same reason' 'Or to someone@practice.example instead.'
green_row row10-dates-and-ids   'ISO dates, issue numbers and money figures are not telephone numbers' 'See issue 8289 dated 2026-09-20; the figure under discussion is 1 234 567.'
green_row row11-fenced          'the offending shapes inside a fenced block are quoted material, not content' '```
Kind regards
a.person@realfirm.co.uk
+44 20 7946 0958
```'

# row12 — the dispatch's vacuous arm. "Handed nothing, reported clean" is the shape that certifies an
# unexamined directory, so zero paths must REFUSE rather than pass.
ck
run_lint
if [[ "$RC" -eq 3 ]]; then ok "row12-zero-paths: handed no path the guard refuses (rc=3), never reports clean"
else bad "row12-zero-paths: expected rc=3; got rc=$RC: $OUT"; fi


# row13 — what the guard certifies must be what gets committed.
#
# Every row above is a plain file with no index at all, so none of them can see this: lefthook hands
# `{staged_files}` as PATHS and a filesystem read certifies the WORKING TREE. Stage a pasted
# signature block, correct the worktree copy, and the guard reported clean while the poisoned blob
# committed — no `--no-verify`, no `LEFTHOOK=0`. Both directions, because the fix must not trade this
# false negative for the `git add -p` false positive.
row13_staged_blob_is_certified() {
  local rec rel rc_staged out_staged rc_unstaged
  rec="${TMP_ROOT:?}/row13repo"
  rel="knowledge-base/project/questionnaires/2026-09-20-accountant-prepaid-hosting-contract.md"
  mkdir -p "$rec/$(dirname "$rel")" || { printf 'FATAL setup: mkdir\n' >&2; exit 2; }
  cp "$EXAMPLE" "$rec/$rel" || { printf 'FATAL setup: seed\n' >&2; exit 2; }
  git -C "$rec" init -q && git -C "$rec" add -A && git -C "$rec" commit -qm base \
    || { printf 'FATAL setup: could not build the git fixture\n' >&2; exit 2; }

  printf '\nKind regards\n' >> "$rec/$rel"
  git -C "$rec" add -A || { printf 'FATAL setup: add\n' >&2; exit 2; }
  sed -i '/^Kind regards$/d' "$rec/$rel" || { printf 'FATAL setup: sed\n' >&2; exit 2; }
  ck
  if grep -q '^Kind regards$' "$rec/$rel"; then
    bad "row13: setup — the worktree copy still carries the salutation, so this row would pass for the wrong reason"
    return
  fi
  ok "row13: setup — the salutation is in the INDEX only, absent from the worktree"

  out_staged="$( cd "$rec" && "$BASH" "$LINT" "$rel" 2>&1 || true )"
  ( cd "$rec" && "$BASH" "$LINT" "$rel" >/dev/null 2>&1 ); rc_staged=$?
  ck
  if [[ "$rc_staged" -eq 1 && "$out_staged" == *'[pasted-reply]'* ]]; then
    ok "row13-staged-blob-is-certified: the STAGED blob is what gets checked (rc=1)"
  else
    bad "row13-staged-blob-is-certified: staged poison with a clean worktree gave rc=$rc_staged — the guard certified the working tree, so a pasted reply commits unexamined: $out_staged"
  fi

  # `reset --hard`, not `checkout -- .`: the latter restores FROM THE INDEX, which still holds the
  # poison staged above, so it would hand it straight back and this arm would red for the wrong reason.
  git -C "$rec" reset -q --hard HEAD || { printf 'FATAL setup: reset\n' >&2; exit 2; }
  printf '\nKind regards\n' >> "$rec/$rel"
  ( cd "$rec" && "$BASH" "$LINT" "$rel" >/dev/null 2>&1 ); rc_unstaged=$?
  ck
  if [[ "$rc_unstaged" -eq 0 ]]; then
    ok "row13: an UNSTAGED violation does not block a commit that would not contain it (git add -p)"
  else
    bad "row13: an unstaged-only violation reddened (rc=$rc_unstaged) — the staged read traded a false negative for a false positive"
  fi
}
row13_staged_blob_is_certified

# --- accounting conservation, then the floor. Both direct.
_lp="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_lf="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
if [[ "${_lp:-0}" -ne "$passes" || "${_lf:-0}" -ne "$fails" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail) disagrees with the counters (%d / %d) — a verdict landed in one bucket and was counted in the other.\n' \
    "${_lp:-0}" "${_lf:-0}" "$passes" "$fails" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: passes+fails (%d) != asserted (%d).\n' "$((passes + fails))" "$asserted" >&2
  exit 1
fi
# Derived, and MEASURED rather than counted by hand: 6 red rows + 5 must-pass rows + 1 dispatch row at
# one assertion each, plus row13's three (its setup precondition, the staged direction, the unstaged
# direction). The first spelling said four and the floor fired at 15 < 16 — which is the floor doing
# exactly its job on its own author.
EXPECTED_ASSERTIONS=15
MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: %d assertion(s) executed, floor is %d. The battery ran but did not assert.\n' \
    "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\nlint-questionnaire-identity.test.sh: %d passed, %d failed, %d assertion(s) executed (floor %s)\n' \
  "$passes" "$fails" "$asserted" "$MIN_ASSERTIONS"
_lf_final="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
[[ "${_lf_final:-0}" -eq 0 && "$fails" -eq 0 && "$passes" -gt 0 ]] || exit 1
exit 0
