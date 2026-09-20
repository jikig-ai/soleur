#!/usr/bin/env bash
# The mutation battery for scripts/lint-rejected-register.sh — the guard over the no-list
# (`knowledge-base/project/rejected/`, the rejected-concepts record).
#
# WRITTEN BEFORE THE GUARD, from the design. The matrix below is derived from the property, not
# from the implementation, so a row can be inadequate but cannot be tautological.
#
# THE PROPERTY UNDER TEST. No entry in the rejected-concepts record claims a concept is
# unimplemented while carrying evidence that it is; every entry carries the fields concept matching
# mechanically depends on (`aliases`, `scope`, the `why`/`public_note` split, `instead`); the
# filename's concept slug never claims more than the entry's own `scope`; no entry identifies a
# requester; and no entry arrogates the authority to close or label an issue.
#
# THE ANCHOR, STATED HONESTLY. Within one commit the guard proves INTERNAL CONSISTENCY, NOT TRUTH.
# It compares an entry's claim (`redundancy_check: not-implemented`) against the evidence the same
# file carries (`searched:`) — both inside one file, so a confidently wrong entry that is internally
# consistent passes. That gap closes OUTSIDE the commit, because each `searched` line is a command
# plus its result count and a reviewer can re-run it. The second assertion — no number in
# `prior_requests` resolves to an issue closed as `completed` — needs the network and is
# deliberately not in the pre-commit tier, so it is not in this battery either.
#
# THE MATRIX. 16 rows across 5 axes (SUT, fixture shape, fixture direction, dispatch, cardinality).
# Rows 1–11 and 13–16 must drive the guard RED; ROW 12 IS THE MUST-PASS ROW and is labelled as such
# at its definition. Each RED row asserts the guard's own rule tag, not merely a non-zero exit — a
# row that reddens for the wrong reason is a row that proves nothing.
#
#   #   axis               mutation                                          reddens because
#   1   fixture shape      redundancy_check: implemented                     the poisoning class
#   2   fixture shape      no redundancy_check key at all                    absence is not compliance
#   3   fixture shape      implemented_at: <path>                            only true of a built feature
#   4   fixture shape      searched: present but empty                       a claim with no evidence
#   5   fixture shape      requester: / requested_by: present at all         public-git personal data
#   6   fixture shape      aliases: empty                                   "night theme" never reaches dark-mode
#   7   fixture shape      no scope:                                         narrow request matches broad refusal
#   8   fixture shape      why: without public_note:                         the only quotable text is the unquotable one
#   9   fixture shape      no instead:                                       a mis-keyed mechanism refusal
#  10   fixture shape      filename slug absent from its own scope:          to a reader the FILENAME is the claim
#  11   fixture shape      entry names itself as grounds to close/label      the advisory-only clause, asserted
#  12   fixture direction  a VALID non-canonical entry                       MUST PASS — see P1
#  13   cardinality        two entries, first valid, second invalid          a check that stops at member 1
#  14   dispatch           invoked with zero path arguments                  "no paths, exit 0" is the vacuous arm
#  15   SUT                drop implemented_at from the forbidden-key set    proves row 3 is carried by the guard
#  16   SUT                enum comparison replaced by a substring match     `not-implemented` CONTAINS `implemented`
#
# THE HARNESS ROWS. A battery that cannot fail is worth nothing, so the instrument is tested too.
#
#  H1  reroute bad() to the PASS counter, against a sabotaged guard → the suite must still exit
#      non-zero. This proves DIRECTION, NOT PRESENCE: a misrouted bad() keeps `passes + fails`
#      conserved and leaves both floors green, so only the append-only verdict ledger can see it.
#      H1 carries its own presence control (the same child WITHOUT the misroute must also redden),
#      because "it reddened" is satisfied by a child that reddens for any reason at all.
#  H2  delete one matrix row invocation → the MIN_CASES floor must fire by name.
#  H3  weaken the success condition to `fail == 0` alone AND remove every row → `0 passed, 0 failed`
#      must not exit 0. The floor, not the verdict, is what catches an empty run.
#  P1  the must-PASS input of row 12 is a real dated concept entry and is NOT the canonical
#      README.md. A suite whose only must-PASS input is the convention document proves nothing about
#      the inputs the contract actually permits.
#
# THE FLOORS. Two, direct, in the ADR-193 shape: `printf >&2` + `exit 1`, never routed through this
# suite's own verdict helpers, because a floor enforced through the suspect cannot witness the
# suspect. Each floor's bound is DERIVED by a recipe over this file, written beside it — never
# hand-summed. MIN_CASES counts ROWS; MIN_AXES counts AXES. That distinction is ADR-193 Decision 2
# and must not collapse: eleven rows on one axis is eleven rows and one axis.
#
# Note on shape: these floors use the `[[ … ]] && { … }` form the plan prescribes rather than an
# `if` opener, so `scripts/guard-vacuity-floor.test.sh` — whose candidate pattern requires a
# conditional opener — does not enumerate them. They are mutation-tested HERE instead, by H2 and H3,
# which is local and stronger than enumeration; the trade is recorded rather than left implied.
#
# WHY THIS SOURCES lib/git-fixture-env.sh: BY CHOICE, NOT BY OBLIGATION. The fixture-env adoption
# gate's SHELL_ROOTS do not cover `plugins/soleur/test/*` — that root is explicitly out of its
# scope — so nothing forces this. It is sourced because sourcing ARMS THE GIT-LOCATION TRIPWIRE: if
# this suite is ever reached from a hook, git exports GIT_DIR/GIT_INDEX_FILE as absolute paths and a
# fixture's writes retarget the developer's live worktree. Aborting is the point; the builder is
# then called on the scratch root so every subprocess this suite spawns is hermetic.
#
# Fixtures are SYNTHESIZED (`cq-test-fixtures-synthesized-only`). No entry below describes a real
# request, a real person or a real refusal.
set -uo pipefail

# A direct invocation otherwise inherits a machine-global 4 GiB tmpfs shared with every sibling
# worktree, which makes this suite's verdicts a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { echo "FATAL: cannot resolve script dir" >&2; exit 2; }
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)" || REPO_ROOT=""

# The SUT, and the fixture-env library, are both overridable so the H-row children can be run from
# a scratch directory where neither sits at its usual relative offset. Defaults are the real paths.
LINT="${SOLEUR_RR_LINT:-$REPO_ROOT/scripts/lint-rejected-register.sh}"
FIXTURE_ENV="${SOLEUR_RR_FIXTURE_ENV:-$SCRIPT_DIR/lib/git-fixture-env.sh}"
# CHILD=1 suppresses the harness segment. Without it a self-copy re-runs H1–H3, each of which makes
# another self-copy, and the suite does not terminate.
CHILD="${SOLEUR_RR_CHILD:-0}"

[[ -f "$FIXTURE_ENV" ]] || { printf 'FATAL: missing %s\n' "$FIXTURE_ENV" >&2; exit 2; }
# shellcheck source=plugins/soleur/test/lib/git-fixture-env.sh
source "$FIXTURE_ENV" || { printf 'FATAL: could not source plugins/soleur/test/lib/git-fixture-env.sh\n' >&2; exit 2; }

# RED-BEFORE-GREEN is observable here: with no guard on disk this is the first thing that fires.
[[ -f "$LINT" ]] || { printf 'FATAL: the SUT does not exist: %s\n' "$LINT" >&2; exit 2; }

# mktemp -d, never a name derived from this script: parallel worktrees are this repository's
# documented workflow and a fixed name collides across sessions.
TMP_ROOT="$(mktemp -d)" || { printf 'FATAL: no scratch root\n' >&2; exit 2; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" ]] || { printf 'FATAL: bad scratch root: %s\n' "$TMP_ROOT" >&2; exit 2; }
readonly TMP_ROOT
trap 'rm -rf -- "$TMP_ROOT"' EXIT INT TERM

git_fixture_env "$TMP_ROOT" || { printf 'FATAL: could not build a hermetic fixture environment\n' >&2; exit 2; }

passes=0; fails=0; asserted=0
# Append-only, and it is what the accounting reconciles against. The counters are numbers a mutation
# can move; these lines are evidence it would have to delete instead. This is the ONLY observable
# that can see a verdict recorded in one bucket and counted in the other (H1).
VERDICT_LOG="$TMP_ROOT/verdicts.txt"; : > "$VERDICT_LOG"
# One line per executed row: "<case-id> <axis>". The floors and the identity check read this file,
# so they read an independent record rather than a counter the verdict helpers touch.
IDS_FILE="$TMP_ROOT/case-ids.txt"; : > "$IDS_FILE"

ok()  { printf '  PASS: %s\n' "$1"; printf 'PASS\n' >> "$VERDICT_LOG"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; printf 'FAIL\n' >> "$VERDICT_LOG"; fails=$((fails + 1)); }
# Incremented at the CALL SITE. A counter living inside the helper it polices cannot notice that
# helper being neutered, which is the whole point of the conservation check in the epilogue.
ck() { asserted=$((asserted + 1)); }

# emit_id <case-id> <axis> — the first statement of every row, so a row that dies during setup is
# absent from the emitted set and the identity check names it.
emit_id() { printf '%s %s\n' "$1" "$2" >> "$IDS_FILE"; }

# A harness that fails to SET UP must abort, never continue: case N running against case N-1's
# mutation reports a confident wrong verdict about the SUT.
must() { "$@" || { printf 'FATAL setup: %s\n' "$*" >&2; exit 2; } }
nonempty() { [[ -s "$1" ]] || { printf 'FATAL setup: empty or missing fixture: %s\n' "$1" >&2; exit 2; } }

# run_lint <args...> -> sets RC and OUT. `|| true` lives INSIDE the substitution: a deliberately
# non-zero command in `x="$(cmd)"` is a hazard worth closing even with `set -e` off here.
RC=0; OUT=""
run_lint() {
  OUT="$( "$BASH" "$@" 2>&1 || true )"
  # Re-run for the status only; capturing both in one pass would hide it behind `|| true`.
  "$BASH" "$@" >/dev/null 2>&1
  RC=$?
}

# --- the canonical VALID entry ------------------------------------------------------------------
# Synthesized. Its filename slug (`inbox-zero-autopilot`) appears inside its own `scope:`, which is
# the row-10 property in its satisfied direction.
VALID_BASENAME="2026-04-02-inbox-zero-autopilot.md"
write_valid_entry() { # <path>
  cat > "$1" <<'ENTRY'
---
aliases:
  - inbox zero autopilot
  - keep my inbox at zero for me
  - automatic mailbox triage
scope: >-
  inbox zero autopilot run as a standing background sweep over a connected mailbox, deciding
  without review what the founder sees, what is filed and what is answered.
why: >-
  A standing sweep decides on the founder's behalf and leaves no reviewable record of what it
  chose not to show them, which is the accountability the product is sold on.
public_note: >-
  Mailbox triage stays a reviewed step rather than a background sweep.
instead: >-
  A drafted reply held for approval, so the decision is the founder's and the typing is not.
revisit_if: >-
  A founder asks for the same sweep twice in one quarter and accepts a per-message audit trail.
redundancy_check: not-implemented
searched:
  - "git ls-files | grep -icE 'inbox[- ]zero' -> 0"
  - "git grep -ilE 'mailbox[- ]sweep' -- knowledge-base -> 0"
---

# Inbox zero autopilot

Synthesized fixture for the guard's battery. Nothing here records a real request or a real refusal.
ENTRY
  nonempty "$1"
}

REQUIRED_KEYS=(aliases scope why public_note instead revisit_if searched redundancy_check)

# new_dir <name> -> prints an absolute fixture directory
new_dir() {
  local d="$TMP_ROOT/$1"
  must mkdir -p "$d"
  printf '%s' "$d"
}

# assert_mutated <mutated> <pristine> <label> -> 0 if the mutation LANDED.
# A mutation that does not land reports the BASELINE, which is indistinguishable from a pass.
assert_mutated() {
  if cmp -s "$1" "$2"; then
    return 1
  fi
  return 0
}

# --- THE CONTROL. Unmutated, FIRST, and it must be GREEN. A red baseline voids every row below, so
# --- this ABORTS (exit 2) rather than counting a failure.
CTL_DIR="$(new_dir control)"
write_valid_entry "$CTL_DIR/$VALID_BASENAME"
PRISTINE="$TMP_ROOT/pristine.md"
must cp "$CTL_DIR/$VALID_BASENAME" "$PRISTINE"
run_lint "$LINT" "$CTL_DIR/$VALID_BASENAME"
if [[ "$RC" -ne 0 ]]; then
  printf 'FATAL: the UNMUTATED control is RED (rc=%s). Every row below would be meaningless.\n' "$RC" >&2
  printf '%s\n' "$OUT" >&2
  exit 2
fi
printf 'lint-rejected-register.test.sh\n'
printf '  control: the unmutated valid entry is accepted (rc=0)\n'

# --- axis: fixture shape ------------------------------------------------------------------------
# Every row here: write the pristine valid entry, mutate exactly one thing, PROVE the mutation
# landed, then require the guard to redden with its own rule tag.

red_row() { # <case-id> <expected-tag> <file-to-lint...> — the shared RED assertion
  local id="$1" tag="$2"; shift 2
  run_lint "$LINT" "$@"
  ck
  if [[ "$RC" -eq 1 && "$OUT" == *"$tag"* ]]; then
    ok "$id: guard reddened with $tag"
  else
    bad "$id: expected rc=1 and $tag; got rc=$RC, output: $OUT"
  fi
}

row01_enum_implemented() {
  emit_id row01-enum-implemented fixture-shape
  local d f; d="$(new_dir row01)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i 's/^redundancy_check: not-implemented$/redundancy_check: implemented/' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row01: mutation landed"; else bad "row01: mutation did NOT land — the guard would see the baseline"; return; fi
  red_row row01-enum-implemented '[enum:redundancy_check]' "$f"
}

row02_enum_missing() {
  emit_id row02-enum-missing fixture-shape
  local d f; d="$(new_dir row02)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i '/^redundancy_check:/d' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row02: mutation landed"; else bad "row02: mutation did NOT land"; return; fi
  red_row row02-enum-missing '[missing-key:redundancy_check]' "$f"
}

row03_implemented_at() {
  emit_id row03-implemented-at fixture-shape
  local d f; d="$(new_dir row03)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i 's|^redundancy_check: not-implemented$|implemented_at: apps/web-platform/lib/mailbox-sweep.ts\nredundancy_check: not-implemented|' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row03: mutation landed"; else bad "row03: mutation did NOT land"; return; fi
  red_row row03-implemented-at '[forbidden-key:implemented_at]' "$f"
}

row04_searched_empty() {
  emit_id row04-searched-empty fixture-shape
  local d f; d="$(new_dir row04)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  # Drop the two evidence lines; the key stays. A `not-implemented` claim with no evidence.
  must sed -i "/-> 0\"$/d" "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row04: mutation landed"; else bad "row04: mutation did NOT land"; return; fi
  red_row row04-searched-empty '[missing-key:searched]' "$f"
}

row05_requester_key() {
  emit_id row05-requester-key fixture-shape
  local d f; d="$(new_dir row05)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i 's|^redundancy_check: not-implemented$|requester: a founder on the design partner list\nrequested_by: the same founder\nredundancy_check: not-implemented|' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row05: mutation landed"; else bad "row05: mutation did NOT land"; return; fi
  run_lint "$LINT" "$f"
  ck
  if [[ "$RC" -eq 1 && "$OUT" == *'[forbidden-key:requester]'* && "$OUT" == *'[forbidden-key:requested_by]'* ]]; then
    ok "row05-requester-key: both forbidden requester spellings are named"
  else
    bad "row05-requester-key: expected rc=1 naming BOTH requester and requested_by; got rc=$RC, output: $OUT"
  fi
}

row06_aliases_empty() {
  emit_id row06-aliases-empty fixture-shape
  local d f; d="$(new_dir row06)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i '/^  - inbox zero autopilot$/d; /^  - keep my inbox at zero for me$/d; /^  - automatic mailbox triage$/d' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row06: mutation landed"; else bad "row06: mutation did NOT land"; return; fi
  red_row row06-aliases-empty '[missing-key:aliases]' "$f"
}

row07_scope_missing() {
  emit_id row07-scope-missing fixture-shape
  local d f; d="$(new_dir row07)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i '/^scope: >-$/,+2d' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row07: mutation landed"; else bad "row07: mutation did NOT land"; return; fi
  red_row row07-scope-missing '[missing-key:scope]' "$f"
}

row08_public_note_missing() {
  emit_id row08-public-note-missing fixture-shape
  local d f; d="$(new_dir row08)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i '/^public_note: >-$/,+1d' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row08: mutation landed"; else bad "row08: mutation did NOT land"; return; fi
  red_row row08-public-note-missing '[missing-key:public_note]' "$f"
}

row09_instead_missing() {
  emit_id row09-instead-missing fixture-shape
  local d f; d="$(new_dir row09)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i '/^instead: >-$/,+1d' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row09: mutation landed"; else bad "row09: mutation did NOT land"; return; fi
  red_row row09-instead-missing '[missing-key:instead]' "$f"
}

row10_filename_outruns_scope() {
  emit_id row10-filename-outruns-scope fixture-shape
  # The mutation is the RENAME, and the CONTENT IS UNTOUCHED — that is the whole point. To an
  # external reader the filename is the claim, so a broad filename over a narrow scope asserts a
  # refusal the body never made.
  local d f g; d="$(new_dir row10)"; f="${d:?}/$VALID_BASENAME"; g="${d:?}/2026-04-02-email-automation.md"
  write_valid_entry "$f"
  must mv "${f:?}" "${g:?}"
  ck
  if [[ ! -e "$f" && -e "$g" ]] && cmp -s "$g" "$PRISTINE"; then
    ok "row10: rename landed and the body is byte-identical to the pristine entry"
  else
    bad "row10: the rename did not land, or the body changed (which would confound the row)"
    return
  fi
  red_row row10-filename-outruns-scope '[slug-outruns-scope]' "$g"
}

row11_authority_claim() {
  emit_id row11-authority-claim fixture-shape
  local d f; d="$(new_dir row11)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  {
    printf '\n'
    printf 'This record is sufficient grounds to close any issue that asks for it: apply\n'
    printf '`deferred-scope-out` and move on without asking anybody.\n'
  } >> "${f:?}"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row11: mutation landed"; else bad "row11: mutation did NOT land"; return; fi
  red_row row11-authority-claim '[authority-claim]' "$f"
}

# --- axis: fixture direction ---------------------------------------------------------------------
# ROW 12 IS THE MUST-PASS ROW. A guard that rejects everything is exactly as useless as one that
# accepts everything, and this row is the only thing standing between the fifteen RED rows and that
# outcome. Its input is a real dated concept entry, NOT the canonical README.md — see P1.
row12_valid_entry_passes() {
  emit_id row12-valid-entry-passes fixture-direction
  local d f; d="$(new_dir row12)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  ck
  if cmp -s "$f" "$PRISTINE"; then ok "row12: the must-PASS input is the unmutated valid entry"; else bad "row12: the must-PASS input drifted from the pristine entry"; return; fi
  run_lint "$LINT" "$f"
  ck
  if [[ "$RC" -eq 0 ]]; then
    ok "row12-valid-entry-passes (MUST-PASS): a valid non-canonical entry is accepted"
  else
    bad "row12-valid-entry-passes (MUST-PASS): a valid entry was REJECTED (rc=$RC): $OUT"
  fi
}

# --- axis: cardinality ---------------------------------------------------------------------------
# Two entries, the FIRST valid and the SECOND invalid, reached by WALKING THE DIRECTORY (--all) and
# not from a manifest. The fixture also carries a README.md, so this row doubles as the proof that
# the convention document is excluded from the entry set (AC-4b): if README.md were treated as an
# entry, a concept-similarity lookup over this directory would match it and manufacture a false
# rejection.
row13_second_of_two_invalid() {
  emit_id row13-second-of-two-invalid cardinality
  local d first second; d="$(new_dir row13)"
  first="${d:?}/2026-04-01-inbox-zero-autopilot.md"
  second="${d:?}/2026-04-02-inbox-zero-autopilot.md"
  write_valid_entry "$first"
  write_valid_entry "$second"
  must sed -i 's/^redundancy_check: not-implemented$/redundancy_check: implemented/' "$second"
  printf '# The no-list\n\nSynthesized convention document; not an entry.\n' > "${d:?}/README.md"
  nonempty "${d:?}/README.md"
  ck
  if assert_mutated "$second" "$PRISTINE" && cmp -s "$first" "$PRISTINE"; then
    ok "row13: member 2 mutated, member 1 pristine"
  else
    bad "row13: fixture is not first-valid/second-invalid"
    return
  fi
  run_lint "$LINT" --all "$d"
  ck
  if [[ "$RC" -eq 1 && "$OUT" == *"$(basename "$second")"* && "$OUT" != *"README.md"* ]]; then
    ok "row13-second-of-two-invalid: the walk reaches member 2 and excludes README.md"
  else
    bad "row13-second-of-two-invalid: expected rc=1 naming member 2 and never README.md; got rc=$RC, output: $OUT"
  fi
}

# --- axis: dispatch -------------------------------------------------------------------------------
# `{staged_files}` can resolve to nothing. "no paths, exit 0, nothing checked" is the vacuous arm:
# the guard must say so and must not certify the record.
row14_zero_paths() {
  emit_id row14-zero-paths dispatch
  run_lint "$LINT"
  ck
  if [[ "$RC" -ne 0 && "$OUT" == *'0 files'* ]]; then
    ok "row14-zero-paths: reports '0 files' and refuses to certify (rc=$RC)"
  else
    bad "row14-zero-paths: expected non-zero plus '0 files'; got rc=$RC, output: $OUT"
  fi
}

# --- axis: SUT ------------------------------------------------------------------------------------
# These two rows mutate the GUARD, not a fixture, and prove the corresponding fixture row is carried
# by the guard rather than by fixture luck. The assertion is inverted: the mutant must ACCEPT the
# fixture its intact form rejects.
sut_mutant() { # <name> <sed-expr> -> prints the mutant path, or aborts if the mutation did not land
  local name="$1" expr="$2" m
  m="$TMP_ROOT/$name-lint.sh"
  must cp "$LINT" "$m"
  must sed -i "$expr" "$m"
  if cmp -s "$m" "$LINT"; then
    printf ''
    return 1
  fi
  printf '%s' "$m"
}

row15_sut_drop_implemented_at() {
  emit_id row15-sut-drop-implemented-at SUT
  local d f m; d="$(new_dir row15)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i 's|^redundancy_check: not-implemented$|implemented_at: apps/web-platform/lib/mailbox-sweep.ts\nredundancy_check: not-implemented|' "$f"
  m="$(sut_mutant row15 's/^FORBIDDEN_KEYS=(implemented_at /FORBIDDEN_KEYS=(/' || true)"
  ck
  if [[ -n "$m" && -f "$m" ]]; then ok "row15: SUT mutation landed (implemented_at left the forbidden-key set)"; else bad "row15: SUT mutation did NOT land — the guard's forbidden-key set is not in the expected shape"; return; fi
  run_lint "$m" "$f"
  ck
  if [[ "$RC" -eq 0 ]]; then
    ok "row15-sut-drop-implemented-at: the mutant ACCEPTS the implemented_at fixture, so row 3 is carried by the guard"
  else
    bad "row15-sut-drop-implemented-at: the mutant still rejected (rc=$RC) — row 3 passes on fixture luck, not on the branch under test"
  fi
}

row16_sut_substring_enum() {
  emit_id row16-sut-substring-enum SUT
  local d f m; d="$(new_dir row16)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i 's/^redundancy_check: not-implemented$/redundancy_check: implemented/' "$f"
  # `not-implemented` CONTAINS `implemented`: a substring comparison accepts the poisoned value.
  m="$(sut_mutant row16 's|"\$rc_val" != "\$want_rc"|"$rc_val" != *"implemented"*|' || true)"
  ck
  if [[ -n "$m" && -f "$m" ]]; then ok "row16: SUT mutation landed (whole-value compare -> substring compare)"; else bad "row16: SUT mutation did NOT land — the enum comparison is not in the expected shape"; return; fi
  run_lint "$m" "$f"
  ck
  if [[ "$RC" -eq 0 ]]; then
    ok "row16-sut-substring-enum: the substring mutant ACCEPTS redundancy_check: implemented, so the intact compare is whole-value"
  else
    bad "row16-sut-substring-enum: the substring mutant still rejected (rc=$RC) — the comparison under test is not the one doing the work"
  fi
}

# --- the harness segment --------------------------------------------------------------------------

SELF="${BASH_SOURCE[0]}"

# child_run <child-script> <lint-for-the-child> -> sets CRC and COUT
CRC=0; COUT=""
child_run() {
  COUT="$( SOLEUR_RR_CHILD=1 SOLEUR_RR_LINT="$2" SOLEUR_RR_FIXTURE_ENV="$FIXTURE_ENV" \
           "$BASH" "$1" 2>&1 || true )"
  SOLEUR_RR_CHILD=1 SOLEUR_RR_LINT="$2" SOLEUR_RR_FIXTURE_ENV="$FIXTURE_ENV" \
    "$BASH" "$1" >/dev/null 2>&1
  CRC=$?
}

h1_bad_misrouted_direction() {
  emit_id h1-bad-misrouted-direction harness
  # A guard that accepts everything, so the child's RED rows genuinely call bad().
  local stub="$TMP_ROOT/h1-stub-lint.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$stub"
  nonempty "$stub"

  # Presence control: the same child WITHOUT the misroute must redden. Without this arm "it
  # reddened" is satisfied by a child that reddens for any reason at all.
  local plain="$TMP_ROOT/h1-plain.sh"
  must cp "$SELF" "$plain"
  child_run "$plain" "$stub"
  ck
  if [[ "$CRC" -ne 0 ]]; then
    ok "h1 control: against a guard that accepts everything, an unmodified child reddens (rc=$CRC)"
  else
    bad "h1 control: an unmodified child exited 0 against a guard that accepts everything — every row is vacuous"
  fi

  # The misroute itself: bad() credits the PASS counter. Conservation still balances and both floors
  # stay green, so only the append-only ledger can see it.
  local mis="$TMP_ROOT/h1-misrouted.sh"
  must cp "$SELF" "$mis"
  # Addressed at the bad() definition line, and it changes ONE thing: which counter moves. Every
  # other byte of bad() survives, including the ledger append — which is exactly the mutation the
  # plan names, and exactly why the counters cannot see it.
  must sed -i '/^bad() {/s/fails=\$((fails + 1))/passes=$((passes + 1))/' "$mis"
  ck
  if [[ "$(grep -c '^bad() {.*passes=\$((passes + 1))' "$mis")" -eq 1 ]]; then
    ok "h1: the bad()-to-passes misroute landed in the child"
  else
    bad "h1: the misroute did NOT land — the child is a copy of this suite and proves nothing"
    return
  fi
  child_run "$mis" "$stub"
  ck
  if [[ "$CRC" -ne 0 && "$COUT" == *'accounting: ledger'* ]]; then
    ok "h1-bad-misrouted-direction: a bad() crediting passes still exits non-zero, caught by the ledger (rc=$CRC)"
  else
    bad "h1-bad-misrouted-direction: expected non-zero plus the ledger sentinel; got rc=$CRC. A discarded verdict is invisible: $COUT"
  fi
}

h2_case_dropped_floor() {
  emit_id h2-case-dropped-floor harness
  local child="$TMP_ROOT/h2-dropped.sh"
  must cp "$SELF" "$child"
  must sed -i '/^row07_scope_missing$/d' "$child"
  ck
  if ! cmp -s "$child" "$SELF"; then ok "h2: one row invocation was removed from the child"; else bad "h2: the row removal did NOT land"; return; fi
  child_run "$child" "$LINT"
  ck
  if [[ "$CRC" -ne 0 && "$COUT" == *'FATAL: battery shrank'* ]]; then
    ok "h2-case-dropped-floor: the MIN_CASES floor fires by name on a shrunken battery (rc=$CRC)"
  else
    bad "h2-case-dropped-floor: expected non-zero plus 'FATAL: battery shrank'; got rc=$CRC: $COUT"
  fi
}

h3_verdict_weakened_zero_cases() {
  emit_id h3-verdict-weakened-zero-cases harness
  local child="$TMP_ROOT/h3-weakened.sh"
  must cp "$SELF" "$child"
  # Two mutations, and both are needed to state the case: remove every row so the run is 0/0, and
  # weaken the success condition to `fail == 0` alone. `0 passed, 0 failed` must not exit 0.
  must sed -i '/^row[0-9][0-9]_[a-z0-9_]*$/d' "$child"
  must sed -i 's/^\[\[ "\$fails" -eq 0 \]\] && \[\[ "\$passes" -gt 0 \]\] || exit 1$/[[ "$fails" -eq 0 ]] || exit 1/' "$child"
  ck
  # Asserted on the child's LAST LINE, not by grepping the file for the old text: this function's
  # own source carries that text too, so a file-wide grep would read itself and never land.
  if [[ "$(grep -cE '^row[0-9][0-9]_[a-z0-9_]*$' "$child")" -eq 0 ]] \
     && [[ "$(tail -n 1 "$child")" == '[[ "$fails" -eq 0 ]] || exit 1' ]]; then
    ok "h3: the child runs no rows and its success condition is fail==0 alone"
  else
    bad "h3: one of the two mutations did NOT land — the child is not a 0/0 weakened-verdict suite"
    return
  fi
  child_run "$child" "$LINT"
  ck
  if [[ "$CRC" -ne 0 && "$COUT" == *'FATAL: battery shrank'* ]]; then
    ok "h3-verdict-weakened-zero-cases: 0 passed, 0 failed does NOT exit 0 — the floor catches it (rc=$CRC)"
  else
    bad "h3-verdict-weakened-zero-cases: expected non-zero plus the floor sentinel; got rc=$CRC: $COUT"
  fi
}

p1_must_pass_input_is_not_canonical() {
  emit_id p1-must-pass-input-not-canonical harness
  local d f k missing=""
  d="$(new_dir p1)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  ck
  if [[ "$VALID_BASENAME" != "README.md" ]] && [[ "$VALID_BASENAME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$ ]]; then
    ok "p1: the must-PASS input is a dated concept entry, not the canonical README.md"
  else
    bad "p1: the must-PASS input is $VALID_BASENAME — a suite whose only accepted input is the convention document proves nothing"
  fi
  for k in "${REQUIRED_KEYS[@]}"; do
    grep -qE "^${k}:" "$f" || missing="$missing $k"
  done
  ck
  if [[ -z "$missing" ]]; then
    ok "p1: the must-PASS input carries every required field (${#REQUIRED_KEYS[@]} of them)"
  else
    bad "p1: the must-PASS input is a stub — missing:$missing"
  fi
}

# --- invocations. One line per row; the floors' recipes read these lines. -------------------------
row01_enum_implemented
row02_enum_missing
row03_implemented_at
row04_searched_empty
row05_requester_key
row06_aliases_empty
row07_scope_missing
row08_public_note_missing
row09_instead_missing
row10_filename_outruns_scope
row11_authority_claim
row12_valid_entry_passes
row13_second_of_two_invalid
row14_zero_paths
row15_sut_drop_implemented_at
row16_sut_substring_enum

if [[ "$CHILD" != "1" ]]; then
  h1_bad_misrouted_direction
  h2_case_dropped_floor
  h3_verdict_weakened_zero_cases
  p1_must_pass_input_is_not_canonical
fi

# --- accounting, then the floors, then identity. All emitted DIRECTLY. ---------------------------
#
# Conservation runs FIRST (ADR-193 Decision 4): a neutered verdict helper trips it and a floor at
# once, and whichever runs first names the fault. "A verdict was discarded" is the true diagnosis;
# "the battery shrank" would be a false accusation.
_ledger_pass="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_ledger_fail="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
if [[ "${_ledger_pass:-0}" -ne "$passes" || "${_ledger_fail:-0}" -ne "$fails" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail) disagrees with the counters (%d pass / %d fail).\n' \
    "${_ledger_pass:-0}" "${_ledger_fail:-0}" "$passes" "$fails" >&2
  printf '  A verdict was recorded in one bucket and counted in the other. That is what a bad()\n' >&2
  printf '  crediting passes looks like, and the conserved sum below structurally cannot see it.\n' >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: passes+fails (%d) != asserted (%d).\n' "$((passes + fails))" "$asserted" >&2
  if [[ $((passes + fails)) -lt "$asserted" ]]; then
    printf '  An assertion was counted and its verdict was never recorded — a neutered ok()/bad().\n' >&2
  else
    printf '  A verdict was recorded with no counted case — a call site is missing its ck().\n' >&2
  fi
  exit 1
fi

cases="$(grep -cE '^row[0-9]+' "$IDS_FILE" || true)"
axes="$(awk '$1 ~ /^row/ { print $2 }' "$IDS_FILE" | sort -u | grep -c . || true)"
hcases="$(grep -cE '^(h[0-9]+|p[0-9]+)' "$IDS_FILE" || true)"

# MIN_CASES counts ROWS. Derived by recipe over this file's own invocation segment, never
# hand-summed:
#   grep -cE '^row[0-9][0-9]_[a-z0-9_]+$' plugins/soleur/test/lint-rejected-register.test.sh  -> 16
# (that is the invocation list above; the matrix table in the header names the same 16 rows.)
MIN_CASES=16
# MIN_AXES counts AXES, not rows — ADR-193 Decision 2, and the distinction must not collapse:
# eleven rows on one axis is eleven rows and one axis, and raising MIN_CASES must never be able to
# satisfy this one. Derived by recipe over the same segment:
#   grep -oE 'emit_id row[0-9a-z-]+ [A-Za-z-]+' plugins/soleur/test/lint-rejected-register.test.sh \
#     | awk '{print $3}' | sort -u | wc -l                                                    -> 5
# The five are SUT, fixture-shape, fixture-direction, dispatch, cardinality.
MIN_AXES=5

# Both floors APPEND TO THE LEDGER THE VERDICT READS before exiting. Without that their non-zero
# exit would be an accident of control flow and the printed verdict would contradict the exit code.
#
# THE STDERR DIAGNOSTIC IS EMITTED BEFORE THE LEDGER APPEND, and that order is load-bearing too.
# The append dereferences $VERDICT_LOG; the anti-vacuity ratchet's mutant slices the floor block out
# of the file, so that variable is UNBOUND there and `set -u` aborts on the append. With the append
# first, the FATAL line never reaches stderr, the ratchet sees only "unbound variable", and it scores
# the floor CONSTRUCTION instead of FIRES — a compliant floor misreported as unmeasurable. Emitting
# the diagnostic first also means a floor still says why it fired if the ledger write itself fails.
# WRITTEN AS `if` OPENERS ON PURPOSE, and the reason is not style. The plan prescribed the
# `[[ ... ]] && { ...; }` one-liner verbatim, and that shape is INVISIBLE to the repo-global
# anti-vacuity ratchet: `floor_lines_of()` in scripts/guard-vacuity-floor.test.sh matches
# `^[[:space:]]*(el)?if[[:space:]]+...`, so a floor with no conditional opener puts this suite
# outside that guard's population, its ratchet and its mutation loop. That file's own header names
# this as the one failure direction it cannot bound ("A NEW floor written in a shape the pattern
# never matched is bounded by NOTHING here"), which is exactly why it must not be relied on to
# catch it. Shipping a guard the guard-guard cannot see is the defect class ADR-193 exists to
# close, so the plan's intent (a DIRECT floor, never routed through the verdict helper) is honoured
# and its literal spelling is not. Second benefit, free: `set -e` does not fire on a failing
# non-final member of an AND-OR list, so the one-liner's control flow was subtler than it looked.
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'FATAL: battery shrank: %s < %s\n' "$cases" "$MIN_CASES" >&2
  printf 'FAIL\n' >> "$VERDICT_LOG"
  exit 1
fi
if [[ "$axes" -lt "$MIN_AXES" ]]; then
  printf 'FATAL: axes covered: %s < %s\n' "$axes" "$MIN_AXES" >&2
  printf 'FAIL\n' >> "$VERDICT_LOG"
  exit 1
fi

# Ordered LAST of the three floors deliberately: a deleted row drops both `cases` and
# `asserted`, and the cardinality message names the actual defect, so it must win. This floor
# is reached only when cardinality is intact and the machinery still went quiet.
# ANTI-VACUITY FLOOR OVER THE EXECUTED-ASSERTION COUNT (ADR-193 Decision 1).
#
# This is the floor the other two could not be. `cases` and `axes` below are read back from
# $IDS_FILE, which is written by emit_id at the top of each row — so they floor the battery's
# CARDINALITY, and that is a real property (a deleted row is caught). What they cannot see is the
# machinery going quiet: neuter ok()/bad()/ck() and $IDS_FILE is still written, so cases/axes read
# 16/5 and both floors stay green over a suite that asserted nothing.
#
# `asserted` is incremented at the CALL SITE, never inside a verdict helper, so it is the one
# quantity that collapses to 0 exactly when the machinery is neutered. Floored here, directly,
# reported with printf to stderr, and never routed through ok()/bad().
#
# scripts/guard-vacuity-floor.test.sh found this gap by derivation rather than by anyone noticing:
# its population rule is "an `if` with -lt/-le/-ge referencing an incremented counter", which
# cases/axes are not, so the only line it could classify as this suite's floor was the conservation
# check below — and under its neutering (every counter forced to 0) `0 -lt 0` is false, so the suite
# exited 0 and it reported NO_FIRE. The guard was right.
#
# THE VALUE IS THE MEASURED RUNTIME COUNT, NOT THE STATIC ONE, and the two differ on purpose:
#   grep -cE '^[[:space:]]*ck$' plugins/soleur/test/lint-rejected-register.test.sh   -> 31 call sites
#   the suite's own epilogue line, run                                              -> 40 executed
# The gap is nine: several ck call sites sit inside per-row loops, so the static recipe is a LOWER
# BOUND on executions and would leave nine assertions droppable without tripping anything. 40 is the
# tight bound. It ratchets the safe way round — adding rows pushes `asserted` up and never reds this.
MIN_ASSERTIONS=40
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: only %s assertion(s) executed, floor is %s. The battery ran but did not assert.\n' \
    "$asserted" "$MIN_ASSERTIONS" >&2
  printf 'FAIL\n' >> "$VERDICT_LOG"
  exit 1
fi

# MATRIX IDENTITY, not counts (a count is satisfied by N copies of one row). The emitted id set must
# EQUAL the declared set, in the `Object.keys(...).sort()` equality shape workflow-fidelity.test.ts
# uses.
MATRIX_IDS=(
  row01-enum-implemented
  row02-enum-missing
  row03-implemented-at
  row04-searched-empty
  row05-requester-key
  row06-aliases-empty
  row07-scope-missing
  row08-public-note-missing
  row09-instead-missing
  row10-filename-outruns-scope
  row11-authority-claim
  row12-valid-entry-passes
  row13-second-of-two-invalid
  row14-zero-paths
  row15-sut-drop-implemented-at
  row16-sut-substring-enum
)
HARNESS_IDS=(
  h1-bad-misrouted-direction
  h2-case-dropped-floor
  h3-verdict-weakened-zero-cases
  p1-must-pass-input-not-canonical
)
_declared="$(printf '%s\n' "${MATRIX_IDS[@]}" | LC_ALL=C sort)"
_emitted="$(awk '$1 ~ /^row/ { print $1 }' "$IDS_FILE" | LC_ALL=C sort -u)"
if [[ "$_declared" != "$_emitted" ]]; then
  printf '\nFATAL: matrix identity: the emitted case-id set does not equal the declared matrix.\n' >&2
  printf '  only declared: %s\n' "$(comm -23 <(printf '%s\n' "$_declared") <(printf '%s\n' "$_emitted") | tr '\n' ' ')" >&2
  printf '  only emitted:  %s\n' "$(comm -13 <(printf '%s\n' "$_declared") <(printf '%s\n' "$_emitted") | tr '\n' ' ')" >&2
  exit 1
fi
if [[ "$CHILD" != "1" ]]; then
  _hdeclared="$(printf '%s\n' "${HARNESS_IDS[@]}" | LC_ALL=C sort)"
  _hemitted="$(awk '$1 ~ /^(h|p)[0-9]/ { print $1 }' "$IDS_FILE" | LC_ALL=C sort -u)"
  if [[ "$_hdeclared" != "$_hemitted" ]]; then
    printf '\nFATAL: harness identity: the emitted harness-id set does not equal the declared set.\n' >&2
    printf '  declared: %s\n' "$(printf '%s ' "${HARNESS_IDS[@]}")" >&2
    printf '  emitted:  %s\n' "$(printf '%s ' "$_hemitted")" >&2
    exit 1
  fi
fi

printf '\nlint-rejected-register.test.sh: %d passed, %d failed, %d assertion(s) executed; %s mutation rows across %s axes, %s harness rows (floors %s/%s)\n' \
  "$passes" "$fails" "$asserted" "$cases" "$axes" "$hcases" "$MIN_CASES" "$MIN_AXES"
[[ "$fails" -eq 0 ]] && [[ "$passes" -gt 0 ]] || exit 1
