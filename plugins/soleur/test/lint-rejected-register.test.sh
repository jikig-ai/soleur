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
# THE MATRIX. 29 rows across 7 axes (SUT, fixture shape, fixture direction, dispatch, cardinality,
# value shape, assembly). Every row must drive the guard RED except the four MUST-PASS rows — 12, 17,
# 23 and 28 — each labelled as such at its definition. Each RED row asserts the guard's own rule tag,
# not merely a non-zero exit: a row that reddens for the wrong reason is a row that proves nothing,
# and each MUST-PASS row exists because its RED partner would otherwise be satisfied by a guard that
# simply refuses more.
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
#  17   fixture direction  redundancy_check: "not-implemented" (quoted)      MUST PASS — quoting is presentation
#  18   value shape        "requester": (quoted key)                         the FIELD is forbidden, not a spelling
#  19   value shape        Requester: (capitalised key)                      same field, same reason
#  20   value shape        searched: present, no `->` result                 an intention is not an audit trail
#  21   value shape        public_note: byte-equal to why:                   the outward text becomes the blunt one
#  22   value shape        superseded_by: names no existing entry            drops the refusal instead of redirecting
#  23   fixture direction  superseded_by: names a real entry                 MUST PASS — or row 22 proves nothing
#  24   assembly           a poisoned entry in a SUBDIRECTORY                indexed by kb-search, invisible to the walk
#  25   assembly           a poisoned entry named `.MD`                      and it is still checked for PII once reached
#  26   assembly           an entry that is a SYMLINK                        certified bytes living outside the record
#  27   assembly           a poisoned `archive/README.md`                    a basename skip is not a document identity
#  28   assembly           the record's OWN README.md                        MUST PASS — row 27's fix must not over-reach
#  29   assembly           two entries claiming one alias                    per-file checks are blind to this by construction
#  30   dispatch           the root README under a RELATIVE path spelling     MUST PASS — the spelling the hooks actually pass
#  31   dispatch           staged poison + corrected worktree, and its inverse  the guard must certify the BLOB, not the tree
#
# Rows 18–23 exist because the structural enumeration of this guard found the same defect eight
# times: the required-key loop proves a key is PRESENT and non-empty, and most of the fields have a
# contract that presence does not express. Rows 24–29 exist because the checks were never the defect
# — THE WALK WAS. Measured on the pre-fix `--all`: one clean entry plus three poisoned members
# (subdirectory, symlink, `.MD`) reported `1 file(s) checked, clean` and exited 0, while handing the
# guard those same files explicitly reddened on every one.
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
# THE FLOORS. Three, direct, in the ADR-193 shape: `printf >&2` + `exit 1`, never routed through this
# suite's own verdict helpers, because a floor enforced through the suspect cannot witness the
# suspect. THREE floors, each bound DERIVED by a recipe over this file, written beside it — never
# hand-summed. MIN_CASES counts ROWS; MIN_AXES counts AXES; MIN_ASSERTIONS counts EXECUTIONS. The
# first distinction is ADR-193 Decision 2 and must not collapse: eleven rows on one axis is eleven
# rows and one axis. The third exists because the first two are read from the emitted-ids file and
# are therefore satisfied by CARDINALITY — a battery whose every assertion had been neutered still
# emitted sixteen ids and cleared both, measured.
#
# Note on shape: these floors are written with `if` openers, not the `[[ … ]] && { … }` form the plan
# prescribes. The plan is authoritative for the floors' INTENT and not for their syntax, and the
# syntax is load-bearing here: `floor_lines_of()` in `scripts/guard-vacuity-floor.test.sh` matches
# only a conditional opener, so in the `&&` form this suite sat OUTSIDE the repo's own anti-vacuity
# population entirely — three healthy floors that no meta-ratchet could see. An earlier revision of
# this comment claimed that exclusion was a deliberate trade covered by H2 and H3; it was neither
# deliberate nor covered, and it is recorded here because the claim is exactly the kind a later
# reader would trust. The floors are now enumerated by that guard AND mutation-tested here.
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
  #
  # The second sed strips BOTH pass-guards, because the verdict is reconciled against two independent
  # records — the append-only ledger and the mutable counters — and weakening only one leaves the
  # other still requiring a pass. That is deliberate: a future rewrite of the verdict breaks this row
  # loudly instead of silently reducing what it proves.
  must sed -i '/^row[0-9][0-9]_[a-z0-9_]*$/d' "$child"
  must sed -i 's/\[\[ "${_final_pass:-0}" -gt 0 \]\] && //; s/&& \[\[ "\$passes" -gt 0 \]\] //' "$child"
  ck
  # Asserted on the child's LAST LINE, not by grepping the file for the old text: this function's
  # own source carries that text too, so a file-wide grep would read itself and never land.
  if [[ "$(grep -cE '^row[0-9][0-9]_[a-z0-9_]*$' "$child")" -eq 0 ]] \
     && [[ "$(tail -n 1 "$child")" == '  && [[ "$fails" -eq 0 ]] || exit 1' ]] \
     && [[ "$(grep -c -- '-gt 0' "$child")" -lt "$(grep -c -- '-gt 0' "$SELF")" ]]; then
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

# --- axis: VALUE SHAPE (the required-key loop checks PRESENCE; the contract is the VALUE) ---------
# Every row above this point drives a check that existed. These drive checks added because the
# structural enumeration of the guard found the same gap eight times: `fm_value` proves a key is
# present and non-empty, and eight of the required fields have a CONTRACT that presence does not
# express. A field satisfied by any non-empty string is a field the schema documents and the guard
# does not enforce.

row17_quoted_enum_accepted() {
  emit_id row17-quoted-enum-accepted fixture-direction
  local d f; d="$(new_dir row17)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  # YAML quoting is presentation. This spelling is the SAME value and was REJECTED, so the entry a
  # careful author writes was the one the guard refused. MUST-PASS in the quoted direction.
  must sed -i 's/^redundancy_check: not-implemented$/redundancy_check: "not-implemented"/' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row17: mutation landed"; else bad "row17: mutation did NOT land"; return; fi
  run_lint "$LINT" "$f"
  ck
  if [[ "$RC" -eq 0 ]]; then
    ok "row17-quoted-enum-accepted (MUST-PASS): a quoted enum scalar is the same value and is accepted"
  else
    bad "row17-quoted-enum-accepted (MUST-PASS): the quoted spelling was REJECTED (rc=$RC): $OUT"
  fi
}

row18_requester_quoted_key() {
  emit_id row18-requester-quoted-key value-shape
  local d f; d="$(new_dir row18)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  # `"requester":` is the same FIELD. An anchored lower-case-only pattern accepted it, so the PII
  # check was about a spelling rather than about the schema.
  must sed -i 's|^redundancy_check: not-implemented$|"requester": a-role-that-should-not-be-here\nredundancy_check: not-implemented|' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row18: mutation landed"; else bad "row18: mutation did NOT land"; return; fi
  red_row row18-requester-quoted-key '[forbidden-key:requester]' "$f"
}

row19_requester_capitalised_key() {
  emit_id row19-requester-capitalised-key value-shape
  local d f; d="$(new_dir row19)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  must sed -i 's|^redundancy_check: not-implemented$|Requester: a-role-that-should-not-be-here\nredundancy_check: not-implemented|' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row19: mutation landed"; else bad "row19: mutation did NOT land"; return; fi
  red_row row19-requester-capitalised-key '[forbidden-key:requester]' "$f"
}

row20_searched_no_result() {
  emit_id row20-searched-no-result value-shape
  local d f; d="$(new_dir row20)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  # The key is present and non-empty, so row04's emptiness check is satisfied. What is missing is the
  # RESULT — and `searched` exists to make the redundancy search auditable, which an intention is not.
  must sed -i 's|^  - "git.*-> 0"$|  - "had a look around the codebase"|' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row20: mutation landed"; else bad "row20: mutation did NOT land"; return; fi
  red_row row20-searched-no-result '[searched-no-result]' "$f"
}

row21_public_note_equals_why() {
  emit_id row21-public-note-equals-why value-shape
  local d f; d="$(new_dir row21)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  # Both keys present, both non-empty, and the split has collapsed — so the blunt internal reasoning
  # is what an agent now quotes at the person whose request was refused.
  must python3 - "$f" <<'PYX'
import re, sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read()
m = re.search(r'^why: >-\n((?:  .*\n)+)', t, re.M)
assert m, 'why: block not found in the canonical entry'
body = m.group(1)
t = re.sub(r'^public_note: >-\n(?:  .*\n)+', 'public_note: >-\n' + body, t, count=1, flags=re.M)
open(p, 'w', encoding='utf-8').write(t)
PYX
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row21: mutation landed"; else bad "row21: mutation did NOT land"; return; fi
  red_row row21-public-note-equals-why '[public_note-equals-why]' "$f"
}

row22_dangling_superseded_by() {
  emit_id row22-dangling-superseded-by value-shape
  local d f; d="$(new_dir row22)"; f="${d:?}/$VALID_BASENAME"
  write_valid_entry "$f"
  # A superseded entry is EXCLUDED from concept matching, so a dangling pointer does not redirect the
  # refusal — it removes it from the record while looking like a redirection.
  must sed -i 's|^redundancy_check: not-implemented$|redundancy_check: superseded\nsuperseded_by: 2027-01-01-no-such-entry.md|' "$f"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row22: mutation landed"; else bad "row22: mutation did NOT land"; return; fi
  red_row row22-dangling-superseded-by '[dangling-superseded_by]' "$f"
}

row23_superseded_by_resolves() {
  emit_id row23-superseded-by-resolves fixture-direction
  local d f g; d="$(new_dir row23)"; f="${d:?}/$VALID_BASENAME"
  g="${d:?}/2026-04-03-inbox-zero-successor.md"
  write_valid_entry "$f"
  write_valid_entry "$g"
  must sed -i 's|^redundancy_check: not-implemented$|redundancy_check: superseded\nsuperseded_by: 2026-04-03-inbox-zero-successor.md|' "$f"
  # The successor needs its own slug inside its own scope (the row-10 property) and its own aliases,
  # or it reds for reasons that have nothing to do with what this row asserts.
  # BOTH spellings. The slug check lowers `-` to `[- ]`, so `scope:` satisfies it with the SPACED
  # form, and a hyphens-only rewrite left the successor reddening on `slug-outruns-scope` — which
  # would have made row22 pass for a reason unrelated to the pointer being dangling.
  must sed -i 's|inbox-zero-autopilot|inbox-zero-successor|g; s|inbox zero autopilot|inbox zero successor|g' "$g"
  ck
  if assert_mutated "$f" "$PRISTINE"; then ok "row23: mutation landed"; else bad "row23: mutation did NOT land"; return; fi
  run_lint "$LINT" "$f" "$g"
  ck
  if [[ "$RC" -eq 0 ]]; then
    ok "row23-superseded-by-resolves (MUST-PASS): a superseded_by naming a real entry is accepted"
  else
    bad "row23-superseded-by-resolves (MUST-PASS): a resolvable superseded_by was REJECTED (rc=$RC): $OUT — row22 would then pass for the wrong reason"
  fi
}

# --- axis: ASSEMBLY (which files are MEMBERS of the record at all) --------------------------------
# The checks above are sound and were never the defect. THE WALK WAS. Every predicate that narrowed
# `--all`'s `find` carved an exact hole in the property "no file in the record violates this", and a
# file in the hole was a member for every CONSUMER — `generate-kb-index.sh` walks the record
# recursively with no depth bound, so it reaches subdirectories the guard could not — while being a
# non-member for the guard. Measured on the pre-fix walk: one clean entry plus three poisoned members
# reported `1 file(s) checked, clean`, rc=0.
#
# These five rows are the holes, each driven through `--all` because that is the only dispatch whose
# assembly is the guard's own.

row24_assembly_subdirectory() {
  emit_id row24-assembly-subdirectory assembly
  local d rec; d="$(new_dir row24)"; rec="${d:?}/rejected"
  must mkdir -p "${rec:?}/archive"
  write_valid_entry "${rec:?}/$VALID_BASENAME"
  write_valid_entry "${rec:?}/archive/$VALID_BASENAME"
  must sed -i 's|^redundancy_check: not-implemented$|requester: a-role-that-should-not-be-here\nredundancy_check: not-implemented|' "${rec:?}/archive/$VALID_BASENAME"
  red_row row24-assembly-subdirectory '[forbidden-key:requester]' --all "${rec:?}"
}

row25_assembly_uppercase_extension() {
  emit_id row25-assembly-uppercase-extension assembly
  local d rec; d="$(new_dir row25)"; rec="${d:?}/rejected"
  must mkdir -p "${rec:?}"
  write_valid_entry "${rec:?}/$VALID_BASENAME"
  write_valid_entry "${rec:?}/2026-04-02-inbox-zero-autopilot.MD"
  must sed -i 's|^redundancy_check: not-implemented$|requester: a-role-that-should-not-be-here\nredundancy_check: not-implemented|' "${rec:?}/2026-04-02-inbox-zero-autopilot.MD"
  # Two properties in one dispatch: the member is REACHED (bad-filename), and reaching it is not the
  # end of it — the PII check still runs, which an early `return 0` on a bad filename prevented.
  red_row row25-assembly-uppercase-extension '[forbidden-key:requester]' --all "${rec:?}"
}

row26_assembly_symlink() {
  emit_id row26-assembly-symlink assembly
  local d rec out; d="$(new_dir row26)"; rec="${d:?}/rejected"; out="${d:?}/outside.md"
  must mkdir -p "${rec:?}"
  write_valid_entry "${rec:?}/$VALID_BASENAME"
  write_valid_entry "${out:?}"
  must ln -s "${out:?}" "${rec:?}/2026-04-02-inbox-zero-symlinked.md"
  red_row row26-assembly-symlink '[symlink-entry]' --all "${rec:?}"
}

row27_assembly_subdirectory_readme() {
  emit_id row27-assembly-subdirectory-readme assembly
  local d rec; d="$(new_dir row27)"; rec="${d:?}/rejected"
  must mkdir -p "${rec:?}/archive"
  write_valid_entry "${rec:?}/$VALID_BASENAME"
  # A README.md in a SUBDIRECTORY is not the convention document. Skipping on basename alone made
  # this path return rc=0 with arbitrary contents — the largest of the four holes, because it is the
  # one an author could reach without doing anything unusual.
  write_valid_entry "${rec:?}/archive/README.md"
  must sed -i 's|^redundancy_check: not-implemented$|requested_by: a-role-that-should-not-be-here\nredundancy_check: not-implemented|' "${rec:?}/archive/README.md"
  red_row row27-assembly-subdirectory-readme '[forbidden-key:requested_by]' --all "${rec:?}"
}

row28_assembly_root_readme_exempt() {
  emit_id row28-assembly-root-readme-exempt assembly
  local d rec; d="$(new_dir row28)"; rec="${d:?}/rejected"
  must mkdir -p "${rec:?}"
  write_valid_entry "${rec:?}/$VALID_BASENAME"
  # The OTHER direction of row27, and it is why that fix is root-scoped rather than a deletion: the
  # record's own README is the convention document and must stay exempt. Without this row, "report
  # every README" would satisfy row27 and break the record.
  printf '# The no-list\n\nConvention document, not an entry. No frontmatter, no schema.\n' > "${rec:?}/README.md"
  run_lint "$LINT" --all "${rec:?}"
  ck
  if [[ "$RC" -eq 0 ]]; then
    ok "row28-assembly-root-readme-exempt (MUST-PASS): the record's own README.md is still the convention document"
  else
    bad "row28-assembly-root-readme-exempt (MUST-PASS): the root README was linted as an entry (rc=$RC): $OUT — row27's fix over-reached"
  fi
}

row29_cross_entry_duplicate_alias() {
  emit_id row29-cross-entry-duplicate-alias assembly
  local d rec; d="$(new_dir row29)"; rec="${d:?}/rejected"
  must mkdir -p "${rec:?}"
  write_valid_entry "${rec:?}/$VALID_BASENAME"
  # A second entry claiming the same alias. Every OTHER check in this guard is per-file and therefore
  # structurally blind to this: the lookup key is the concept plus its aliases, so two claimants make
  # the answer depend on which the walk reached first, and the two may disagree about the refusal.
  write_valid_entry "${rec:?}/2026-04-04-inbox-zero-duplicate.md"
  must sed -i 's|inbox-zero-autopilot|inbox-zero-duplicate|g' "${rec:?}/2026-04-04-inbox-zero-duplicate.md"
  red_row row29-cross-entry-duplicate-alias '[duplicate-alias]' --all "${rec:?}"
}

row30_dispatch_relative_paths() {
  emit_id row30-dispatch-relative-paths dispatch
  # THE PATH SPELLING IS PART OF THE DISPATCH. Every other row builds its fixtures under an absolute
  # $TMP_ROOT, so the suite only ever exercised the spelling that happened to work — and the root-README
  # exemption was first written as a string equality against `$DEFAULT_DIR/README.md`, which is
  # ABSOLUTE (derived from the script's own location), while lefthook hands `{staged_files}` and
  # `{push_files}` as REPOSITORY-RELATIVE paths. The two spellings never matched: the record's own
  # convention document was linted as an entry and the PRE-PUSH HOOK REFUSED THE PUSH. Measured, and
  # caught by the hook rather than by this battery, which is the gap this row closes.
  #
  # This row therefore drives the REAL dispatch: cwd at the repository root, repo-relative paths into
  # the repository's own record, read-only. It cannot use a $TMP_ROOT fixture, because the exemption is
  # deliberately scoped to the record root that `DEFAULT_DIR` names — a README somewhere else is not
  # this repository's convention document, and rows 27 and 28 already pin that boundary.
  local entry
  entry="$( cd "$REPO_ROOT" && ls knowledge-base/project/rejected/2*-*.md 2>/dev/null | head -n 1 )"
  ck
  if [[ -n "$entry" ]]; then
    ok "row30: the repository's record has an entry to drive the real dispatch against ($entry)"
  else
    bad "row30: no dated entry found under knowledge-base/project/rejected/ — this row cannot exercise the hook's invocation, so it is reporting on nothing"
    return
  fi
  ck
  local rc_rel
  ( cd "$REPO_ROOT" && "$BASH" "$LINT" knowledge-base/project/rejected/README.md "$entry" >/dev/null 2>&1 )
  rc_rel=$?
  if [[ "$rc_rel" -eq 0 ]]; then
    ok "row30-dispatch-relative-paths (MUST-PASS): the hook's own spelling — repo-relative paths — exempts the root README"
  else
    bad "row30-dispatch-relative-paths (MUST-PASS): repo-relative paths rc=$rc_rel. The exemption is comparing path STRINGS, so it holds for the absolute spelling the fixtures use and fails for the one lefthook actually passes — this is the pre-push refusal, reproduced."
  fi
  # The absolute spelling of the same two files must agree. Two spellings of one path disagreeing is
  # the defect itself, so the row asserts agreement rather than each in isolation.
  ck
  local rc_abs
  ( cd "$REPO_ROOT" && "$BASH" "$LINT" "$REPO_ROOT/knowledge-base/project/rejected/README.md" "$REPO_ROOT/$entry" >/dev/null 2>&1 )
  rc_abs=$?
  if [[ "$rc_abs" -eq "$rc_rel" ]]; then
    ok "row30: the absolute and relative spellings of the same paths agree (both rc=$rc_abs)"
  else
    bad "row30: the same two files gave rc=$rc_rel relative and rc=$rc_abs absolute — the guard's verdict depends on how its caller spells the path"
  fi
}

row31_staged_blob_is_certified() {
  emit_id row31-staged-blob-is-certified dispatch
  # WHAT THE GUARD CERTIFIES MUST BE WHAT GETS COMMITTED. lefthook hands `{staged_files}` as PATHS,
  # and a filesystem read certifies the WORKING TREE — so stage a poisoned entry, correct the worktree
  # copy, and the guard reported clean while the poisoned blob committed, with no `--no-verify` and no
  # `LEFTHOOK=0`. That is a bypass the script's own DISPATCH enumeration did not list, and no other row
  # here can see it: every other fixture is a plain file under $TMP_ROOT with no index at all.
  #
  # Both directions, because the fix has two failure modes and they point opposite ways. Reading the
  # staged blob closes the false NEGATIVE above; it must not introduce a false POSITIVE, and the case
  # that would is `git add -p` — an UNSTAGED violation must not block a commit that does not contain it.
  local d rec; d="$(new_dir row31)"; rec="${d:?}/repo"
  must mkdir -p "${rec:?}/knowledge-base/project/rejected"
  local rel="knowledge-base/project/rejected/$VALID_BASENAME"
  write_valid_entry "${rec:?}/$rel"
  # The fixture env is already hermetic (git_fixture_env at the top of this file sets a ceiling at
  # $TMP_ROOT and pins identity), so `git init` here cannot reach the developer's repository.
  must git -C "${rec:?}" init -q
  must git -C "${rec:?}" add -A
  must git -C "${rec:?}" commit -qm base

  # (a) staged poison + corrected worktree -> the guard must read the BLOB and redden.
  must sed -i 's|^redundancy_check: not-implemented$|requester: a-role-that-should-not-be-here\nredundancy_check: not-implemented|' "${rec:?}/$rel"
  must git -C "${rec:?}" add -A
  must sed -i '/^requester: a-role-that-should-not-be-here$/d' "${rec:?}/$rel"
  ck
  if grep -q '^requester:' "${rec:?}/$rel"; then
    bad "row31: setup — the worktree copy still carries requester:, so this row would pass for the wrong reason"
    return
  else
    ok "row31: setup — the poison is in the INDEX only, absent from the worktree"
  fi
  local rc_staged out_staged
  out_staged="$( cd "${rec:?}" && "$BASH" "$LINT" "$rel" 2>&1 || true )"
  ( cd "${rec:?}" && "$BASH" "$LINT" "$rel" >/dev/null 2>&1 ); rc_staged=$?
  ck
  if [[ "$rc_staged" -eq 1 && "$out_staged" == *'[forbidden-key:requester]'* ]]; then
    ok "row31-staged-blob-is-certified: the STAGED blob is what gets checked (rc=1)"
  else
    bad "row31-staged-blob-is-certified: staged poison with a clean worktree gave rc=$rc_staged — the guard certified the working tree, so the poisoned blob commits with no --no-verify: $out_staged"
  fi
  # The diagnostic must name the path as HANDED. A mirror path under $TMPDIR is an internal detail the
  # operator cannot act on, and leaking it is what a lazily-created mirror did.
  ck
  if [[ "$out_staged" != *"$TMPDIR"* ]] || [[ "$out_staged" == *"$rel"* ]]; then
    ok "row31: the diagnostic names the path as handed, not an internal mirror path"
  else
    bad "row31: the diagnostic leaked an internal mirror path: $out_staged"
  fi

  # (b) the inverse. Unstaged violation only -> must NOT block.
  #
  # `git checkout -- .` is WRONG here and was the first spelling: it restores the worktree from the
  # INDEX, and phase (a) deliberately left the poison staged — so it handed the poison straight back
  # and this arm reddened for a reason that had nothing to do with the property. Reset BOTH, from HEAD.
  must git -C "${rec:?}" reset -q --hard HEAD
  must sed -i 's|^redundancy_check: not-implemented$|requester: a-role-that-should-not-be-here\nredundancy_check: not-implemented|' "${rec:?}/$rel"
  local rc_unstaged
  ( cd "${rec:?}" && "$BASH" "$LINT" "$rel" >/dev/null 2>&1 ); rc_unstaged=$?
  ck
  if [[ "$rc_unstaged" -eq 0 ]]; then
    ok "row31: an UNSTAGED violation does not block a commit that would not contain it (git add -p)"
  else
    bad "row31: an unstaged-only violation reddened (rc=$rc_unstaged) — the staged read traded a false negative for a false positive"
  fi
}

row12_valid_entry_passes
row13_second_of_two_invalid
row14_zero_paths
row15_sut_drop_implemented_at
row16_sut_substring_enum
row17_quoted_enum_accepted
row18_requester_quoted_key
row19_requester_capitalised_key
row20_searched_no_result
row21_public_note_equals_why
row22_dangling_superseded_by
row23_superseded_by_resolves
row24_assembly_subdirectory
row25_assembly_uppercase_extension
row26_assembly_symlink
row27_assembly_subdirectory_readme
row28_assembly_root_readme_exempt
row29_cross_entry_duplicate_alias
row30_dispatch_relative_paths
row31_staged_blob_is_certified

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
MIN_CASES=31
# MIN_AXES counts AXES, not rows — ADR-193 Decision 2, and the distinction must not collapse:
# eleven rows on one axis is eleven rows and one axis, and raising MIN_CASES must never be able to
# satisfy this one. Derived by recipe over the same segment:
#   grep -oE 'emit_id row[0-9a-z-]+ [A-Za-z-]+' plugins/soleur/test/lint-rejected-register.test.sh \
#     | awk '{print $3}' | sort -u | wc -l                                                    -> 7
# The seven are SUT, fixture-shape, fixture-direction, dispatch, cardinality, value-shape, assembly.
MIN_AXES=7

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
# THE VALUE IS THE MEASURED RUNTIME COUNT, NOT THE STATIC ONE, and the two differ on purpose. An
# earlier revision of this comment explained the gap as "several ck call sites sit inside per-row
# loops". That is FALSE and was measured so: ZERO ck sites sit inside a loop (p1's only `for` has its
# ck after `done`). The entire gap is `red_row`'s single ck, executed once per caller. The number was
# right and the stated mechanism was wrong, which is worse than a wrong number — anyone re-deriving
# it looks for loops that do not exist. Recipe, corrected:
#   static ck call sites                                    grep -cE '^[[:space:]]*ck$' <this file>
#   plus one per red_row caller                             grep -cE '^  red_row ' <this file>
#   = the executed count, which the epilogue line prints
#
# AND IT IS MODE-DEPENDENT. `SOLEUR_RR_CHILD=1` skips the four harness rows, so a child executes
# strictly fewer assertions than a parent. A single parent-mode literal therefore FIRED on every
# intact child — which silently voided h1's presence control, whose only assertion is `CRC -ne 0`:
# the rc=1 it observed was this floor misfiring on the mode mismatch, not the child's rows catching
# the accept-everything stub. It would have passed with every row in the child hollowed out. Two
# bounds, so each mode is floored at its own tight count and an intact child can be GREEN.
# Measured, both modes, on this tree:
#   bash <this file>                    -> 67 executed   (31 matrix rows + 4 harness rows)
#   SOLEUR_RR_CHILD=1 bash <this file>  -> 58 executed   (31 matrix rows alone)
# The harness contribution is the difference, 9, and is asserted separately so that adding a harness
# row cannot be absorbed by slack in the matrix bound or vice versa.
MIN_ASSERTIONS_MATRIX=58
MIN_ASSERTIONS_HARNESS=9
EXPECTED_ASSERTIONS="$MIN_ASSERTIONS_MATRIX"
[[ "$CHILD" == "1" ]] || EXPECTED_ASSERTIONS=$((MIN_ASSERTIONS_MATRIX + MIN_ASSERTIONS_HARNESS))
# THE SHAPE OF THE NEXT TWO LINES IS LOAD-BEARING, and the reason is mechanical rather than stylistic.
# `scripts/guard-vacuity-floor.test.sh` mutation-tests this floor by slicing the block below into a
# standalone script, widening BACKWARD only over contiguous simple assignments. The mode selection
# above is not one, so an `if/else/fi` writing `MIN_ASSERTIONS` left it UNBOUND in the mutant, which
# aborted under `set -u` before the floor ran: the guard then scored this floor CONSTRUCTION, the
# suite lost its only FIRES floor, and the whole suite was reported as having a floor "enforced
# THROUGH the machinery it guards". Measured — the mode-aware fix reintroduced exactly that.
#
# So the threshold is bound by ONE simple assignment adjacent to the floor, with a fallback that
# applies only inside the mutant (in a real run EXPECTED_ASSERTIONS is always set). `1` cannot rot as
# rows are added, and any positive value discriminates because the mutant zeroes `asserted` to 0.
MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}
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
  row17-quoted-enum-accepted
  row18-requester-quoted-key
  row19-requester-capitalised-key
  row20-searched-no-result
  row21-public-note-equals-why
  row22-dangling-superseded-by
  row23-superseded-by-resolves
  row24-assembly-subdirectory
  row25-assembly-uppercase-extension
  row26-assembly-symlink
  row27-assembly-subdirectory-readme
  row28-assembly-root-readme-exempt
  row29-cross-entry-duplicate-alias
  row30-dispatch-relative-paths
  row31-staged-blob-is-certified
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
# THE VERDICT READS THE APPEND-ONLY LEDGER, not the counters. `$fails` is a mutable number: any line
# inserted between the conservation check above and this point can zero it, and the exit code would
# then contradict the FAIL lines already printed. The ledger can only be appended to, so it is the
# authority — the same precedent as fixture-relative-assert.test.sh's own verdict. The counters are
# kept in the condition as well: they are reconciled against the ledger above, so requiring both to
# agree costs nothing and means a mutation has to defeat two independent records.
_final_fail="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
_final_pass="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
[[ "${_final_fail:-1}" -eq 0 ]] && [[ "${_final_pass:-0}" -gt 0 ]] \
  && [[ "$fails" -eq 0 ]] && [[ "$passes" -gt 0 ]] || exit 1
