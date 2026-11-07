#!/usr/bin/env bash
# shellcheck disable=SC2154  # T18's R18*/W18*/S18* names are assigned by new_fixture_root via printf -v
# Suite for plugins/soleur/skills/ship/scripts/battery-owed.sh (#8247).
#
# This gate decides whether a ~35-minute run happens, so it will be under
# standing pressure to be read generously. Both directions are pinned here, and
# every refusal has its own row: a gate with only must-skip rows passes when it
# is made unconditionally permissive, which is the one mutation that matters.
#
# Fixtures are SYNTHESIZED, never captured (cq-test-fixtures-synthesized-only):
# a throwaway bare repo plus a `gh` stub serving hand-written payloads.
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ONE owning trap, registered before the first allocation (ADR-129, rule (c)).
# Each fixture root is appended as it is created, so a failed assertion, a
# `set -u` abort or a signal between two allocations still removes every root
# already made — a trailing `rm -rf` at the end of the file only runs on the
# happy path, which is precisely the path that does not leak.
#
# Installed BEFORE the helper is sourced: test-helpers.sh composes its
# incident-sandbox cleanup over an existing EXIT trap, whereas a trap installed
# afterwards replaces it and leaks the sandbox on every direct run (#8659).
FIXTURE_ROOTS=()
cleanup_fixture_roots() {
  local d
  for d in "${FIXTURE_ROOTS[@]:-}"; do
    [[ -n "$d" && "$d" == /* && -d "$d" ]] && rm -rf "$d"
  done
  # Explicit success: a trap whose last command returns non-zero can set the
  # shell's exit status, turning "ALL TESTS PASSED" into a non-zero rc.
  return 0
}
trap cleanup_fixture_roots EXIT INT TERM

# shellcheck source=./test-helpers.sh
source "$HERE/test-helpers.sh"

GATE="$HERE/../skills/ship/scripts/battery-owed.sh"
[[ -r "$GATE" ]] || { printf 'FATAL: gate not readable at %s\n' "$GATE" >&2; exit 1; }

OWED=0
SKIPPABLE=42
UNDECIDABLE=2

# Allocate a fixture root and register it for cleanup in one step, so a new
# fixture cannot be added without being owned.
#
# ASSIGNS INTO A CALLER-NAMED VARIABLE; it does NOT print the path for `$(...)`.
# An earlier revision did, and command substitution forks a SUBSHELL — so
# `FIXTURE_ROOTS+=("$d")` ran in the child and the parent's array stayed EMPTY.
# The trap then iterated nothing and removed nothing, i.e. the owning-trap fix
# was inert while looking correct, which is the exact leak the lint flagged.
# Measured: the parent saw 0 registered roots.
new_fixture_root_var() { printf ''; }
new_fixture_root() {
  local __out_var="$1" __d
  __d="$(mktemp -d -t battery-owed-XXXXXX)" || return 1
  FIXTURE_ROOTS+=("$__d")
  printf -v "$__out_var" '%s' "$__d"
}

# --- instrument self-test ----------------------------------------------------
# Drive both dispatch helpers once each before any real row, and refuse to
# continue unless both counters moved. Without this, an edit that neuters
# assert_eq turns the whole suite into a silent pass.
_p0="$PASS"; _f0="$FAIL"
assert_eq "instrument" "instrument" "instrument self-test: the PASS arm records"
assert_eq "a" "b" "instrument self-test: the FAIL arm records (EXPECTED — subtracted below)"
if (( PASS <= _p0 || FAIL <= _f0 )); then
  printf 'FATAL: instrument self-test did not move both counters (PASS %s->%s, FAIL %s->%s).\n' \
    "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 1
fi
FAIL=$(( FAIL - 1 ))   # subtract the deliberate failure

# --- fixture builder ---------------------------------------------------------
# Builds: a bare "origin" with a main branch, a clone on a feature branch whose
# upstream is current. Returns the clone path on stdout.
# `git_fixture_env` EXPORTS into the calling shell and prints nothing; it is
# called directly, never in a command substitution. Each fixture-mutating block
# runs in its own subshell so those exports cannot leak into the gate run.
build_fixture() {
  local root="$1"
  local origin="$root/origin.git" work="$root/work"
  (
    git_fixture_env "$root" || exit 1
    git init --quiet --bare "$origin"
    git clone --quiet "$origin" "$work"
  ) >/dev/null 2>&1 || return 1
  (
    cd "$work" || exit 1
    git_fixture_env "$work" || exit 1
    mkdir -p plugins/soleur
    printf 'seed\n' > README.md
    git add -A
    git commit --quiet -m "seed"
    git branch -M main
    git push --quiet -u origin main
    git checkout --quiet -b feat-fixture
    printf 'change\n' > plugins/soleur/thing.md
    git add -A
    git commit --quiet -m "feature change"
    git push --quiet -u origin feat-fixture
  ) >/dev/null 2>&1 || return 1
  printf '%s\n' "$work"
}

# Run git mutations inside an already-built fixture.
in_fixture() {
  local work="$1"; shift
  ( cd "$work" || exit 1
    git_fixture_env "$work" || exit 1
    "$@" ) >/dev/null 2>&1
}

# --- gh stub -----------------------------------------------------------------
# APPLIES THE REAL `--jq` FILTER over a real API envelope. An earlier revision
# ran `jq -c '.[]'` and ignored the filter entirely, handing the gate rows with
# `started_at` intact — a shape the production projection never produces, because
# it did not select that field. The rows then happened to be ordered newest-last
# in the fixtures, so the re-run rows passed by pinning ARRAY POSITION while the
# real gate was sorting on an all-empty key and picking the OLDEST attempt. The
# seam sat above the exact thing under test.
#
# $1 stub dir, $2 required-contexts JSON, $3 check_runs JSON, $4 the sha that
# JSON is served FOR, $5 statuses JSON, $6 ruleset exit code.
make_stub() {
  local dir="$1" required="$2" checks="$3" green_sha="${4:-}" statuses="${5:-[]}" rules_rc="${6:-0}" checks_rc="${7:-0}"
  mkdir -p "$dir"
  printf '%s' "$required"  > "$dir/required.json"
  printf '%s' "$checks"    > "$dir/checks.json"
  printf '%s' "$statuses"  > "$dir/statuses.json"
  printf '%s' "$green_sha" > "$dir/green_sha"
  printf '%s' "$rules_rc"  > "$dir/rules_rc"
  printf '%s' "$checks_rc" > "$dir/checks_rc"
  cat > "$dir/gh" <<'STUB'
#!/usr/bin/env bash
DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
joined="$*"
# Recover the --jq filter the caller passed, so the fixture goes through the SAME
# projection production uses.
filter=""
prev=""
for a in "$@"; do
  [[ "$prev" == "--jq" ]] && filter="$a"
  prev="$a"
done
case "$joined" in
  *rules/branches/main*)
    rc="$(cat "$DIR/rules_rc")"
    [[ "$rc" != "0" ]] && exit "$rc"
    # Build the RAW ruleset envelope the API returns, so the gate's own filter
    # does the projection. The fixture stays a readable context list.
    jq -c '[{type:"required_status_checks",parameters:{required_status_checks:.}}]' < "$DIR/required.json" \
      | jq -c "${filter:-.}"
    exit 0 ;;
  *check-runs*)
    crc="$(cat "$DIR/checks_rc" 2>/dev/null || echo 0)"
    [[ "$crc" != "0" ]] && exit "$crc"
    want="$(cat "$DIR/green_sha")"
    if [[ -n "$want" && "$joined" == *"$want"* ]]; then
      # Real envelope: the API returns {"check_runs": [...]}.
      jq -c '{check_runs: .}' < "$DIR/checks.json" | jq -c "${filter:-.}"
    fi
    exit 0 ;;
  *statuses*)
    jq -c "${filter:-.}" < "$DIR/statuses.json"; exit 0 ;;
esac
echo "gh stub: unhandled '$joined'" >&2
exit 1
STUB
  chmod +x "$dir/gh"
}

# The fixture repo's HEAD moves as rows commit, so resolve it per call.
head_sha_of() { ( cd "$1" && git_fixture_env "$1" >/dev/null 2>&1; git rev-parse HEAD ); }

run_gate() {
  local work="$1" stub="$2"
  ( cd "$work" || exit 9
    git_fixture_env "$work" || exit 9
    PATH="$stub:$PATH" bash "$GATE" >/dev/null 2>&1 )
  printf '%s' "$?"
}

# run_gate discards stdout, so an OWED row proves "not 42" and nothing more --
# it cannot tell condition 1 from condition 2 from an accidental early exit, and
# three of this suite's refusal rows are mutually indistinguishable to it. This
# returns the VERDICT LINE so a row can assert WHICH condition fired.
# MUST NOT PROPAGATE THE GATE'S EXIT CODE. test-helpers.sh sets errexit, so a
# command substitution whose function returns non-zero aborts the whole suite --
# and this gate returns non-zero on every path but SKIPPABLE. That is why
# run_gate above ends on `printf` rather than on the subshell: the trailing
# success is load-bearing, not style. Measured: without the explicit `return 0`
# this helper killed the run mid-file at the first UNDECIDABLE row, printing no
# error and no results block, which reads exactly like a hang.
run_gate_out() {
  local work="$1" stub="$2" out
  out="$( ( cd "$work" || exit 9
            git_fixture_env "$work" >/dev/null 2>&1 || exit 9
            PATH="$stub:$PATH" bash "$GATE" 2>&1 ) || true )"
  printf '%s' "$out"
  return 0
}

# Substring match on the verdict line, reported through the shared counters.
assert_reason() {
  local work="$1" stub="$2" needle="$3" label="$4" out
  out="$(run_gate_out "$work" "$stub")"
  if printf '%s' "$out" | grep -cF >/dev/null "$needle"; then
    assert_eq "ok" "ok" "$label"
  else
    assert_eq "$out" "reason containing: $needle" "$label"
  fi
}

GREEN_CHECKS='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
# The ruleset shape: {context, integration_id}. integration_id null = unpinned.
TWO_REQUIRED='[{"context":"test","integration_id":null},{"context":"adr-ordinals","integration_id":null}]'
PINNED_REQUIRED='[{"context":"test","integration_id":15368}]'

# =============================================================================
# T1 — the must-SKIP direction. All conditions hold.
# =============================================================================
new_fixture_root ROOT
WORK="$(build_fixture "$ROOT")"
STUB="$ROOT/stub"; make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK")"
assert_eq "$SKIPPABLE" "$(run_gate "$WORK" "$STUB")" \
  "T1 clean tree + all required green on THIS sha + no infra paths -> SKIPPABLE"

# =============================================================================
# T2 — dirty tree. "CI is green" then describes a different tree.
# =============================================================================
printf 'uncommitted\n' > "$WORK/dirty.txt"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T2 dirty working tree -> OWED (CI verified a different tree)"
rm -f "$WORK/dirty.txt"

# =============================================================================
# T3 — THE SHA PROPERTY. Green for the PARENT commit, not for HEAD.
#
# This is the sharpest property in the design and an earlier revision pinned it
# with NOTHING: the stub served the same fixture for any sha, so pointing the
# gate at `main` or a literal left every row passing. It is also what makes a
# separate "is it pushed?" condition unnecessary — an unpushed commit simply has
# no check-runs for its sha.
# =============================================================================
PARENT_SHA="$( cd "$WORK" && git_fixture_env "$WORK" >/dev/null 2>&1; git rev-parse HEAD~1 )"
make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$PARENT_SHA"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T3 required checks green on the PARENT sha only -> OWED (green must be green on THIS sha)"
make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK")"

# =============================================================================
# T4 — a RE-RUN that went red. Newest attempt fails, an older one passed.
#
# GitHub keeps every attempt and a re-run ADDS a row: measured on this repo, one
# merge commit carried 121 check-runs across 63 distinct names. An
# `any(...succeeded)` test reads `ok` for a context a human would call red.
# =============================================================================
RERUN_RED='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T09:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$TWO_REQUIRED" "$RERUN_RED" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T4 a required context passed then was RE-RUN red -> OWED (newest attempt wins)"

# The inverse, so the row above cannot pass by the gate simply ignoring order.
RERUN_GREEN='[{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T09:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$TWO_REQUIRED" "$RERUN_GREEN" "$(head_sha_of "$WORK")"
assert_eq "$SKIPPABLE" "$(run_gate "$WORK" "$STUB")" \
  "T4b a required context failed then was RE-RUN green -> SKIPPABLE (newest attempt wins, both directions)"
make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK")"

# =============================================================================
# T4c — NEWEST-BY-TIME, NOT BY ARRAY POSITION.
#
# GitHub returns rows newest-FIRST (measured on a57cdb772: cla-evidence descends
# 11:30 -> 03:00). So a row set whose newest element is FIRST is the production
# order, and a gate that fell back to array position would pick the oldest. T4/T4b
# alone cannot see this: their fixtures happen to put the newest last, so they
# pin position and time simultaneously. This row separates them.
# =============================================================================
NEWEST_FIRST_RED='[{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T09:00:00Z","app":{"id":15368}},{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$TWO_REQUIRED" "$NEWEST_FIRST_RED" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T4c newest attempt is red and listed FIRST (production order) -> OWED (time, not array position)"

# T4c2/T4c3 — ORDERING MUST NOT DECIDE when the sort key is absent.
#
# `sort_by(.started_at // "")` maps a null/missing key to "", which sorts BEFORE
# every ISO timestamp, so `last` returns an OLDER completed row and an in-flight
# attempt becomes invisible. Measured before the fix: one completed+success row
# plus one in_progress row with `started_at: null` evaluated to "ok" -> SKIPPABLE.
# That is the same newest-wins inversion this file already fixed once, arriving
# through the sort KEY rather than the sort. Both rows below are order-independent
# by construction: T4c2 refuses on the attempt's STATUS, T4c3 on the fact that
# "newest" is undecidable across two rows when a key is missing.
NULL_START_INFLIGHT='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"test","status":"in_progress","conclusion":null,"started_at":null,"app":{"id":15368}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$NULL_START_INFLIGHT" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T4c2 an in-flight attempt with a NULL started_at cannot be hidden by an older green row -> OWED"

NULL_START_BOTH_GREEN='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"test","status":"completed","conclusion":"failure","started_at":null,"app":{"id":15368}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$NULL_START_BOTH_GREEN" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T4c3 two completed attempts where one has NO started_at -> OWED (newest is undecidable)"

# =============================================================================
# T4d — APP IDENTITY. A pinned context is satisfiable only by its own app.
#
# Matching on name alone made the gate strictly MORE permissive than the ruleset
# it calls authoritative: any installed app with `checks: write` could satisfy a
# required context by naming a check-run after it.
#
# The app id is NOT uniform across the required set, so T4g/T4h below pin the
# per-context read that T4d/T4e cannot. Measured 2026-09-17 against the live
# ruleset: 26 contexts, 25 pinned to 15368 (GitHub Actions), `CodeQL` pinned to
# 57789 (github-advanced-security) — a split scripts/required-checks.txt has
# recorded since #6050. An earlier revision of this comment said all 26 were
# 15368, and every fixture in this file used 15368 or null, so replacing the
# gate's `$r.integration_id` with the literal 15368 left the suite fully GREEN.
# (Historical measurement. Since #9454 — merge queue adopted, CodeQL advisory — the live
# set is uniformly 15368; the `CodeQL`/57789 rows below are a SYNTHETIC stand-in for any
# context bound to a different app, which a CodeQL re-tighten would make real again.)
# =============================================================================
FOREIGN_APP='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":99999}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$FOREIGN_APP" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T4d a green check-run from a FOREIGN app cannot satisfy a pinned required context -> OWED"

OWN_APP='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$OWN_APP" "$(head_sha_of "$WORK")"
assert_eq "$SKIPPABLE" "$(run_gate "$WORK" "$STUB")" \
  "T4e the SAME pinned context satisfied by its own app -> SKIPPABLE (both directions)"

# T4g/T4h — the app id is read PER CONTEXT, never as a shared constant.
#
# Two required contexts pinned to DIFFERENT apps, mirroring the live ruleset's
# 15368/57789 split. Every other fixture here uses one id, so none of them can
# tell `$r.integration_id` from a hardcoded 15368; these two can. Mutating the
# gate's `select($r.integration_id == null or .app_id == $r.integration_id)` to
# compare against a literal 15368 turns T4g SKIPPABLE -> OWED (the 57789 context
# reads ABSENT). T4h is the other direction: an app id that is correct for ONE
# required context does not satisfy a DIFFERENT one.
SPLIT_REQUIRED='[{"context":"test","integration_id":15368},{"context":"CodeQL","integration_id":57789}]'
SPLIT_MATCHED='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"CodeQL","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":57789}}]'
make_stub "$STUB" "$SPLIT_REQUIRED" "$SPLIT_MATCHED" "$(head_sha_of "$WORK")"
assert_eq "$SKIPPABLE" "$(run_gate "$WORK" "$STUB")" \
  "T4g two required contexts pinned to DIFFERENT apps, each satisfied by its own -> SKIPPABLE"

SPLIT_CROSSED='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"CodeQL","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$SPLIT_REQUIRED" "$SPLIT_CROSSED" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T4h a green CodeQL check-run from 15368 cannot satisfy a context pinned to 57789 -> OWED"

# =============================================================================
# T4f — a legacy commit STATUS must not outrank a check-run.
#
# Statuses carry a real created_at while check-runs carried an empty sort key in
# an earlier revision, so "" < any ISO made every status win regardless of age. A
# status needs only the `repo:status` scope — the weakest GitHub token there is.
# =============================================================================
STALE_STATUS='[{"context":"test","state":"success","created_at":"2020-01-01T00:00:00Z"}]'
RED_CHECK='[{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$RED_CHECK" "$(head_sha_of "$WORK")" "$STALE_STATUS"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T4f a six-year-old green commit STATUS cannot override a red check-run on a pinned context -> OWED"

# =============================================================================
# T5 — the infra surface. BOTH prefixes test-all.sh matches.
#
# No required check runs those suites (#6480), so the battery is their only
# BLOCKING gate. An earlier revision matched one prefix and drifted on its first
# write; T5b is the spelling it missed.
# =============================================================================
in_fixture "$WORK" bash -c 'mkdir -p apps/web-platform/infra && printf "x\n" > apps/web-platform/infra/deploy.sh && git add -A && git commit --quiet -m "infra change"'
make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T5 diff touches apps/web-platform/infra/** -> OWED even with every required check green"

in_fixture "$WORK" bash -c 'git rm -r --quiet --cached apps/web-platform >/dev/null 2>&1; rm -rf apps; mkdir -p .github/workflows && printf "x\n" > .github/workflows/apply-web-platform-infra.yml && git add -A && git commit --quiet -m "infra workflow change"'
make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T5b diff touches ONLY .github/workflows/apply-web-platform-infra.yml -> OWED (the second prefix test-all.sh matches)"

# =============================================================================
# T5c — the infra condition SELF-RETIRES once #6480 lands.
# =============================================================================
make_stub "$STUB" '[{"context":"test","integration_id":null},{"context":"adr-ordinals","integration_id":null},{"context":"infra-validate-required","integration_id":null}]' \
  '[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"infra-validate-required","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]' \
  "$(head_sha_of "$WORK")"
assert_eq "$SKIPPABLE" "$(run_gate "$WORK" "$STUB")" \
  "T5c infra diff + infra-validate-required IS required and green -> SKIPPABLE (condition self-retires)"

# =============================================================================
# T5d — THE BRANCH MUST BE UP TO DATE WITH origin/main.
#
# ci.yml has no push trigger for feature branches, so the `test` check-run on a
# branch head comes from a pull_request run against refs/pull/N/merge — CI
# verified merge(HEAD, base), not HEAD. The two trees are the same only when
# origin/main is already an ancestor of HEAD. Without this the gate's headline
# claim is false whenever main has advanced, which `strict: false` makes ordinary.
# =============================================================================
ROOTB="$(new_fixture_root_var)"; new_fixture_root ROOTB
WORKB="$(build_fixture "$ROOTB")"
STUBB="$ROOTB/stub"
# Advance origin/main past the branch point, leaving the branch BEHIND.
in_fixture "$WORKB" bash -c 'git checkout --quiet main && printf "newer\n" > on-main.md && git add -A && git commit --quiet -m "main advances" && git push --quiet origin main && git checkout --quiet feat-fixture'
make_stub "$STUBB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKB")"
assert_eq "$OWED" "$(run_gate "$WORKB" "$STUBB")" \
  "T5d branch is BEHIND origin/main -> OWED (CI verified merge(HEAD,base), not this tree)"

# And the inverse, so the row cannot pass by the gate simply always refusing.
in_fixture "$WORKB" bash -c 'git merge --quiet origin/main --no-edit'
make_stub "$STUBB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKB")"
assert_eq "$SKIPPABLE" "$(run_gate "$WORKB" "$STUBB")" \
  "T5e after merging origin/main in -> SKIPPABLE (up to date, so the merge ref IS this tree)"

# =============================================================================
# T5f — a file RENAMED OUT of the infra surface still counts as an infra diff.
#
# `--name-only` prints only the new path, so the gate would miss it while
# test-all.sh's predicate catches it. Measured: --name-only gave `moved.tf`;
# --name-status -M gave `R100 apps/web-platform/infra/a.tf moved.tf`.
# =============================================================================
in_fixture "$WORKB" bash -c 'mkdir -p apps/web-platform/infra && printf "x\n" > apps/web-platform/infra/a.tf && git add -A && git commit --quiet -m "add infra file" && git push --quiet origin feat-fixture && git checkout --quiet main && git merge --quiet feat-fixture --no-edit && git push --quiet origin main && git checkout --quiet feat-fixture'
in_fixture "$WORKB" bash -c 'git mv apps/web-platform/infra/a.tf moved.tf && git commit --quiet -m "rename out of the infra surface"'
make_stub "$STUBB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKB")"
assert_eq "$OWED" "$(run_gate "$WORKB" "$STUBB")" \
  "T5f a file renamed OUT of apps/web-platform/infra/ -> OWED (the old path must still count)"

# =============================================================================
# T5g/T5h — the MIRROR of T5f, which T5f structurally could not reach.
#
# A rename emits both paths on ONE tab-joined line and INFRA_RE is `^`-anchored,
# so testing the joined line tests the OLD path only. T5f renames OUT, putting
# the infra path in column 1 where the anchor matches -- so T5f passed while the
# gate was blind to every rename IN. Measured on a probe repo before the fix:
# `R100  src/x.tf  apps/web-platform/infra/x.tf` did NOT match, i.e. a .tf file
# renamed into the Terraform module directory returned SKIPPABLE. Terraform loads
# every *.tf in that directory, so it is a real infra change with no content diff,
# on the one shard no required check covers. T5h is the same bug at the workflow
# literal, whose `$` anchor fails when the literal sits in column 1.
# Both die if `tr '\t' '\n'` is removed from the CHANGED pipeline.
# =============================================================================
in_fixture "$WORKB" bash -c 'git checkout --quiet -- . && printf "y\n" > outside.tf && git add -A && git commit --quiet -m "add a tf file outside infra" && git push --quiet origin feat-fixture && git checkout --quiet main && git merge --quiet feat-fixture --no-edit && git push --quiet origin main && git checkout --quiet feat-fixture'
in_fixture "$WORKB" bash -c 'mkdir -p apps/web-platform/infra && git mv outside.tf apps/web-platform/infra/outside.tf && git commit --quiet -m "rename INTO the infra surface"'
make_stub "$STUBB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKB")"
assert_eq "$OWED" "$(run_gate "$WORKB" "$STUBB")" \
  "T5g a file renamed INTO apps/web-platform/infra/ -> OWED (the NEW path must also count)"

in_fixture "$WORKB" bash -c 'git checkout --quiet -- . && mkdir -p .github/workflows && printf "on: push\n" > .github/workflows/apply-web-platform-infra.yml && git add -A && git commit --quiet -m "add the apply workflow" && git push --quiet origin feat-fixture && git checkout --quiet main && git merge --quiet feat-fixture --no-edit && git push --quiet origin main && git checkout --quiet feat-fixture'
in_fixture "$WORKB" bash -c 'git mv .github/workflows/apply-web-platform-infra.yml docs-old-apply.yml && git commit --quiet -m "rename the apply workflow out"'
make_stub "$STUBB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKB")"
assert_eq "$OWED" "$(run_gate "$WORKB" "$STUBB")" \
  "T5h the apply-web-platform-infra workflow renamed OUT -> OWED (the \$-anchored literal in column 1)"

# =============================================================================
# T2b/T2c — the OTHER TWO dirty shapes. T2 only ever instantiated an UNTRACKED
# file, so `git status --porcelain` could have been swapped for
# `git ls-files --others` and stayed green — leaving the gate's self-declared
# sharpest condition pinned by one of the three shapes it must catch.
# =============================================================================
in_fixture "$WORK" bash -c 'printf "modified\n" >> README.md'
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T2b a MODIFIED TRACKED file -> OWED (not just untracked)"
in_fixture "$WORK" bash -c 'git checkout --quiet -- README.md'

in_fixture "$WORK" bash -c 'printf "staged\n" > staged.md && git add staged.md'
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T2c a STAGED change -> OWED (the third dirty shape)"
in_fixture "$WORK" bash -c 'git rm -q --cached staged.md && rm -f staged.md'

# =============================================================================
# T6b — conclusions outside success/failure. GitHub's branch protection treats
# `neutral` and `skipped` as passing; this gate does NOT, which is the SAFE
# direction (more OWED). Pinned so the choice is deliberate rather than accidental,
# and so a future "just accept neutral" edit has to argue with a row.
# =============================================================================
NEUTRAL_CHECK='[{"name":"test","status":"completed","conclusion":"neutral","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$NEUTRAL_CHECK" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T6b conclusion=neutral -> OWED (this gate requires success; GitHub would pass it)"
SKIPPED_CHECK='[{"name":"test","status":"completed","conclusion":"skipped","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$SKIPPED_CHECK" "$(head_sha_of "$WORK")"
assert_eq "$OWED" "$(run_gate "$WORK" "$STUB")" \
  "T6c conclusion=skipped -> OWED (same deliberate strictness)"

# =============================================================================
# T12 — the 15s bound is asserted in SOURCE, not only behaviourally.
# T10b's window admits anything under 40s, so widening `timeout 15` to `timeout 35`
# was free. Pin the literal the way T11 pins INFRA_RE.
# =============================================================================
GATE_SRC="$(git rev-parse --show-toplevel)/plugins/soleur/skills/ship/scripts/battery-owed.sh"
if grep -qE '^\s*REQUIRED_JSON="\$\(timeout 15 gh api' "$GATE_SRC"; then
  assert_eq "ok" "ok" "T12 the ruleset call is bounded at the documented 15s"
else
  assert_eq "bound changed" "ok" "T12 the ruleset call's timeout literal is not 15 — behaviour row T10b would not notice"
fi

# =============================================================================
# T6 — a required context ABSENT. The non-vacuity row.
# =============================================================================
new_fixture_root ROOT2
WORK2="$(build_fixture "$ROOT2")"
STUB2="$ROOT2/stub"
make_stub "$STUB2" '[{"context":"test","integration_id":null},{"context":"adr-ordinals","integration_id":null},{"context":"never-ran","integration_id":null}]' "$GREEN_CHECKS" "$(head_sha_of "$WORK2")"
assert_eq "$OWED" "$(run_gate "$WORK2" "$STUB2")" \
  "T6 a required context is ABSENT (nothing failing) -> OWED, not a vacuous skip"

# =============================================================================
# T7 — present but not green.
# =============================================================================
make_stub "$STUB2" "$TWO_REQUIRED" \
  '[{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]' \
  "$(head_sha_of "$WORK2")"
assert_eq "$OWED" "$(run_gate "$WORK2" "$STUB2")" "T7 a required context concluded failure -> OWED"

make_stub "$STUB2" "$TWO_REQUIRED" \
  '[{"name":"test","status":"in_progress","conclusion":null,"started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]' \
  "$(head_sha_of "$WORK2")"
assert_eq "$OWED" "$(run_gate "$WORK2" "$STUB2")" \
  "T7b a required context still in_progress -> OWED (not-yet-green is not green)"

# =============================================================================
# T8 — the ruleset cannot be read. UNDECIDABLE, never a skip.
# =============================================================================
make_stub "$STUB2" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK2")" "[]" 1
assert_eq "$UNDECIDABLE" "$(run_gate "$WORK2" "$STUB2")" \
  "T8 ruleset unreadable -> UNDECIDABLE (caller treats as OWED), never SKIPPABLE"

# =============================================================================
# T9 — an EMPTY required set. Refusing a trivially-satisfied skip.
# =============================================================================
make_stub "$STUB2" '[]' "$GREEN_CHECKS" "$(head_sha_of "$WORK2")"
assert_eq "$UNDECIDABLE" "$(run_gate "$WORK2" "$STUB2")" \
  "T9 zero required contexts -> UNDECIDABLE, never a trivially-satisfied skip"

# =============================================================================
# T10 — A HANGING ENDPOINT MUST NOT HANG THE GATE.
#
# `gh` imposes no timeout of its own (measured: a blackholed host was still
# running at 25 s). A gate that runs before a 35-minute battery owes "never
# throws AND always returns"; try/catch bounds exceptions, not time. Fixture the
# HANG, not only the rejection.
# =============================================================================
new_fixture_root ROOT3
WORK3="$(build_fixture "$ROOT3")"
STUB3="$ROOT3/stub"
make_stub "$STUB3" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK3")"
# Replace the stub's ruleset arm with one that hangs well past the gate's bound.
cat > "$STUB3/gh" <<'HANGSTUB'
#!/usr/bin/env bash
case "$*" in
  *rules/branches/main*) exec sleep 60 ;;
esac
exit 0
HANGSTUB
chmod +x "$STUB3/gh"
_t0=$(date +%s)
_rc="$(run_gate "$WORK3" "$STUB3")"
_elapsed=$(( $(date +%s) - _t0 ))
assert_eq "$UNDECIDABLE" "$_rc" "T10 a hanging gh endpoint -> UNDECIDABLE, not a hang"
if (( _elapsed < 40 )); then
  assert_eq "bounded" "bounded" "T10b the hang returned in ${_elapsed}s (bounded well under the 60s stub sleep)"
else
  assert_eq "took ${_elapsed}s" "bounded" "T10b the gate did NOT bound the hanging call"
fi

# =============================================================================
# T11 — parity with test-all.sh's own infra predicate.
#
# The gate re-derives which paths make the infra runner relevant. test-all.sh is
# the authority; this row fails if it grows a prefix the gate does not match, so
# the drift is caught at the source rather than by a future incident.
# =============================================================================
REPO_ROOT="$(git rev-parse --show-toplevel)"
# The authority: the two literals test-all.sh's _infra_in_diff block greps for.
# DERIVE the set with an OPEN pattern. An earlier revision extracted with a
# fixed two-literal alternation naming the very prefixes it expected, so a third
# prefix added to test-all.sh was invisible and `_auth_n` was 2 BY CONSTRUCTION —
# the row's own comment ("fails if test-all.sh grows a third") was false, and that
# is the single thing this row exists to do. Verified: injecting a third
# `grep -qF '...'` into the authority left every T11 row green.
#
# The shape, not the content: every operand of a `grep -qF '<prefix>'` inside the
# _infra_in_diff block.
AUTHORITY_PREFIXES="$(awk '/^_infra_in_diff=0$/,/^fi$/' "$REPO_ROOT/scripts/test-all.sh" \
  | grep -oE "grep -qF '[^']+'" | sed -E "s/^grep -qF '//; s/'$//" | sort -u)"
GATE_RE_LINE="$(grep -F 'INFRA_RE=' "$REPO_ROOT/plugins/soleur/skills/ship/scripts/battery-owed.sh" | tr -d '\\')"

# Non-vacuity: the extraction must find AT LEAST the two we know of. A `>=` floor,
# not `== 2`: the whole point is that the authority may grow.
_auth_n="$(printf '%s\n' "$AUTHORITY_PREFIXES" | grep -c .)"
if [[ "$_auth_n" -ge 2 ]]; then
  assert_eq "ok" "ok" "T11 authority extraction derived $_auth_n infra prefix(es) from test-all.sh (>=2)"
else
  assert_eq "derived $_auth_n" "ok" "T11 authority extraction found $_auth_n prefixes — the extractor is broken, so every row below is vacuous"
fi

while IFS= read -r _p; do
  [[ -z "$_p" ]] && continue
  if printf '%s\n' "$GATE_RE_LINE" | grep -cF >/dev/null "$_p"; then
    assert_eq "ok" "ok" "T11 gate matches test-all.sh infra prefix '$_p'"
  else
    assert_eq "MISSING" "ok" "T11 gate does NOT match test-all.sh infra prefix '$_p' — predicate drift"
  fi
done <<< "$AUTHORITY_PREFIXES"

# =============================================================================
# T14 — WHICH condition fired, not merely "not 42".
#
# run_gate discards stdout, so every refusal row above asserts the same thing:
# the exit code is not 42. Three of this suite's conditions are therefore
# mutually indistinguishable to it -- a gate that refused unconditionally from
# line 1, or one whose conditions all collapsed onto the first, would keep every
# one of those rows green. These rows read the verdict line instead.
# =============================================================================
ROOTC="$(new_fixture_root_var)"; new_fixture_root ROOTC
WORKC="$(build_fixture "$ROOTC")"
STUBC="$ROOTC/stub"
make_stub "$STUBC" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKC")"

in_fixture "$WORKC" bash -c 'printf "dirty\n" > untracked-file.txt'
assert_reason "$WORKC" "$STUBC" "working tree is dirty" \
  "T14a a dirty tree refuses FOR THE DIRTY REASON (not merely non-42)"
in_fixture "$WORKC" bash -c 'rm -f untracked-file.txt'

in_fixture "$WORKC" bash -c 'git checkout --quiet main && printf "n\n" > adv.md && git add -A && git commit --quiet -m "main advances" && git push --quiet origin main && git checkout --quiet feat-fixture'
make_stub "$STUBC" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKC")"
assert_reason "$WORKC" "$STUBC" "not an ancestor of HEAD" \
  "T14b a BEHIND branch refuses FOR THE ANCESTOR REASON, distinguishing it from T14a"
in_fixture "$WORKC" bash -c 'git merge --quiet origin/main --no-edit'

in_fixture "$WORKC" bash -c 'mkdir -p apps/web-platform/infra && printf "x\n" > apps/web-platform/infra/z.tf && git add -A && git commit --quiet -m "infra"'
make_stub "$STUBC" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKC")"
assert_reason "$WORKC" "$STUBC" "infra surface" \
  "T14c an infra diff refuses FOR THE INFRA REASON, distinguishing it from T14a/T14b"

# =============================================================================
# T15 — the check-runs endpoint can FAIL, and the statuses branch has no
# positive row.
#
# make_stub could fixture a rules-endpoint rc but the check-runs arm always
# exited 0, so the gate's `(( rc == 0 )) || undecidable` on that call was
# unreachable from here. And the whole lazy-statuses path -- fetch, merge, second
# eval -- was only ever entered by T4f, where app identity discards the status
# BEFORE ordering is consulted, so no row had ever seen the merge succeed.
# =============================================================================
ROOTD="$(new_fixture_root_var)"; new_fixture_root ROOTD
WORKD="$(build_fixture "$ROOTD")"
STUBD="$ROOTD/stub"

make_stub "$STUBD" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKD")" "[]" 0 1
assert_eq "$UNDECIDABLE" "$(run_gate "$WORKD" "$STUBD")" \
  "T15a the check-runs endpoint failing -> UNDECIDABLE (never a skip)"
assert_reason "$WORKD" "$STUBD" "could not read check-runs" \
  "T15b and it names the check-runs read as the cause"

# An UNPINNED required context with NO check-run, satisfied only by a legacy
# commit status. This is the merge path: check-runs leave it ABSENT, the statuses
# fetch fires, the two surfaces are combined, and the second eval must clear it.
ONE_UNPINNED='[{"context":"legacy-ctx","integration_id":null}]'
GREEN_STATUS='[{"context":"legacy-ctx","state":"success","created_at":"2026-01-01T00:00:00Z"}]'
make_stub "$STUBD" "$ONE_UNPINNED" "[]" "$(head_sha_of "$WORKD")" "$GREEN_STATUS"
assert_eq "$SKIPPABLE" "$(run_gate "$WORKD" "$STUBD")" \
  "T15c an UNPINNED context satisfied only by a green legacy STATUS -> SKIPPABLE (the merge path works)"

# The ordering property T4f was meant to pin, on an UNPINNED context so the
# status is not discarded by app identity first. T4f uses PINNED_REQUIRED, so its
# status row (app_id null) is filtered out before `sort_by` is ever consulted --
# invert the sort to `first` and T4f stays green.
OLD_GREEN_STATUS='[{"context":"legacy-ctx","state":"success","created_at":"2020-01-01T00:00:00Z"}]'
NEW_RED_CHECK='[{"name":"legacy-ctx","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUBD" "$ONE_UNPINNED" "$NEW_RED_CHECK" "$(head_sha_of "$WORKD")" "$OLD_GREEN_STATUS"
assert_eq "$OWED" "$(run_gate "$WORKD" "$STUBD")" \
  "T15d a 2020 green STATUS cannot outrank a 2026 red check-run on an UNPINNED context -> OWED"

# =============================================================================
# T13 — parity with the premise the WHOLE gate rests on.
#
# The gate's containment argument is that CI's required `test` context covers
# every test-all.sh group except infra. T11 pins the infra half. Nothing pinned
# this half: if ci.yml's `test` aggregator drops a shard from its `needs:` list,
# the gate keeps skipping a suite CI no longer runs, and its verdict line is
# unchanged. Measured while adding this row: `test` is `needs: [test-webplat,
# test-bun, test-scripts, web-platform-build]` with `if: always()`, and its
# aggregation loop sets fail=1 on ANY non-success result -- so a SKIPPED shard
# reds the context rather than passing it. That is what makes the premise true
# today, and it is exactly what could change without anyone editing this gate.
#
# DERIVE both sides. The aggregator's needs: list comes out of ci.yml; the
# expected set comes out of the gate's own premise comment. Neither is retyped
# here, so a shard added to one and not the other reds this row.
# =============================================================================
CI_YML="$REPO_ROOT/.github/workflows/ci.yml"
AGG_NEEDS="$(awk '/^  test:/{f=1} f&&/^    needs:/{print; exit}' "$CI_YML" \
  | sed -E 's/^[[:space:]]*needs:[[:space:]]*\[//; s/\][[:space:]]*$//' | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -c .)"
if [[ "$AGG_NEEDS" -ge 4 ]]; then
  assert_eq "ok" "ok" "T13 extracted $AGG_NEEDS shard(s) from ci.yml's test aggregator (>=4)"
else
  assert_eq "derived $AGG_NEEDS" "ok" "T13 extraction found $AGG_NEEDS shards — extractor broken, rows below vacuous"
fi

# DIRECTION MATTERS, and the first draft of this row had it backwards. Iterating
# ci.yml's shards and asserting the gate NAMES each one does not catch the drift
# that hurts: CI dropping a shard from the aggregator while the gate keeps
# skipping on its behalf. Iterate the GATE's named shards and require ci.yml to
# still aggregate each -- that is the direction in which silence becomes a wrong
# SKIP.
GATE_PREMISE="$(grep -F 'test-webplat + test-bun + test-scripts' "$REPO_ROOT/plugins/soleur/skills/ship/scripts/battery-owed.sh")"
# LONGEST-FIRST: `test-scripts` is a strict prefix of `test-scripts-heavy`, so an
# alternation naming the shorter first silently collapses the heavy job into the
# light one and the T13 loop below never checks it.
GATE_SHARDS="$(printf '%s\n' "$GATE_PREMISE" | grep -oE '(test-webplat|test-bun|test-scripts-heavy|test-scripts|web-platform-build)' | sort -u)"
AGG_LIST="$(awk '/^  test:/{f=1} f&&/^    needs:/{print; exit}' "$CI_YML" \
  | sed -E 's/^[[:space:]]*needs:[[:space:]]*\[//; s/\][[:space:]]*$//' | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep .)"
_gate_n="$(printf '%s\n' "$GATE_SHARDS" | grep -c .)"
if [[ "$_gate_n" -ge 5 ]]; then
  assert_eq "ok" "ok" "T13 the gate's premise names $_gate_n shard(s) (>=5)"
else
  assert_eq "derived $_gate_n" "ok" "T13 premise extraction found $_gate_n shards — rows below vacuous"
fi
while IFS= read -r _shard; do
  [[ -z "$_shard" ]] && continue
  if printf '%s\n' "$AGG_LIST" | grep -cx >/dev/null "$_shard"; then
    assert_eq "ok" "ok" "T13 ci.yml's test aggregator still covers '$_shard'"
  else
    assert_eq "MISSING" "ok" "T13 the gate skips on behalf of '$_shard' but ci.yml no longer aggregates it — premise drift"
  fi
done <<< "$GATE_SHARDS"

# The aggregator must not treat a non-success shard as a pass. Executed, not read:
# a `skipped` shard flowing through as green is the shape that would let the gate
# skip a suite CI never ran.
AGG_BODY_NONSUCCESS="$(awk '/^  test:/{f=1} f&&/^  [a-z]/&&!/^  test:/{exit} f' "$CI_YML" \
  | grep -cE '^[[:space:]]*if \[\[ "\$result" == "success" \]\]; then')"
if [[ "$AGG_BODY_NONSUCCESS" -ge 1 ]]; then
  assert_eq "ok" "ok" "T13 ci.yml's aggregator continues ONLY on success, so a skipped shard reds the context"
else
  assert_eq "MISSING" "ok" "T13 ci.yml's aggregator no longer gates on == success — the gate's premise may be false"
fi

# =============================================================================
# T16 — the CONSUMER contract in ship/SKILL.md Phase 4 (#8322).
#
# battery-owed.sh returns a verdict; the SKILL decides which battery runs on
# it. Since #8322 the OWED arm runs `--affected`, not the full battery, and the
# only spelling that buys `--full` is the operator's `/ship --full` — which
# must outrank even a SKIPPABLE verdict. These rows pin the dispatch block
# itself, not the script (the script is mode-agnostic by design).
# =============================================================================
SKILL_MD="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"

# The fenced dispatch block: the FULL_BATTERY branch through the closing `fi`.
DISPATCH="$(awk '/FULL_BATTERY:-}.*==.*true/{f=1} f{print} f&&/^fi$/{exit}' "$SKILL_MD")"
if [[ -n "$DISPATCH" ]]; then
  assert_eq "ok" "ok" "T16a ship/SKILL.md carries a FULL_BATTERY-gated dispatch block"
else
  assert_eq "MISSING" "ok" "T16a no FULL_BATTERY dispatch block found — extraction broken or dispatch deleted"
fi

# /ship --full runs the FULL battery unconditionally — before battery-owed.sh
# is even consulted, so a SKIPPABLE verdict cannot demote an explicit ask.
# Since #9307 the command is the plugin gate `affected-tests.sh --full`, which
# delegates `--full` to a capability-positive runner — the mode flag is the pin.
if printf '%s\n' "$DISPATCH" | grep -c >/dev/null 'affected-tests\.sh" --full\|affected-tests\.sh --full' \
   && ! printf '%s\n' "$DISPATCH" | grep -c >/dev/null 'battery-owed\.sh.*--full'; then
  assert_eq "ok" "ok" "T16b the FULL_BATTERY arm runs affected-tests.sh --full unconditionally"
else
  assert_eq "MISSING" "ok" "T16b the FULL_BATTERY arm does not run --full — operator opt-in demoted"
fi

# The OWED arm runs the AFFECTED gate — the plugin gate's bare spelling, which
# delegates `--affected` to a capability-positive runner (#9307). Extract the
# else-branch: the lines between the battery-owed verdict check and the
# closing fi.
OWED_ARM="$(printf '%s\n' "$DISPATCH" | awk '/battery-owed\.sh/{f=1} f{print}')"
if printf '%s\n' "$OWED_ARM" | grep -c >/dev/null 'affected-tests\.sh' \
   && ! printf '%s\n' "$OWED_ARM" | grep -c >/dev/null 'affected-tests\.sh" --full\|affected-tests\.sh --full\|test-all\.sh --full'; then
  assert_eq "ok" "ok" "T16c the OWED arm runs the affected gate, never --full"
else
  assert_eq "MISSING" "ok" "T16c the OWED arm does not run the affected gate — default gate demoted"
fi

# 42 is still the ONLY skip. The dispatch must keep `rc -eq 42` as the skip
# branch and run on every other status.
if printf '%s\n' "$DISPATCH" | grep -c >/dev/null 'rc" -eq 42\|rc -eq 42'; then
  assert_eq "ok" "ok" "T16d rc=42 remains the only skip branch — not-42 still runs"
else
  assert_eq "MISSING" "ok" "T16d the 42-only-skip branch vanished — every failure would now run OR skip wrongly"
fi

# =============================================================================
# T17 — ADR-276 S3 (#9728): a draft-era red `test` on a READY head.
#
# With CI_DRAFT_LIGHT on, a draft's `test` concludes red BY DESIGN ("draft: full battery owed at ready"). Option R is what
# keeps this gate correct without a code change: the newest `test` row per name must be completed+success, so a draft's red
# row is NOT-GREEN and the gate returns OWED. These rows PIN that (no edit to battery-owed.sh) and are each paired with a
# mutation of a COPY of the gate that must turn them RED, so the rows are shown able to fail:
#   T17a  draft red test, the ready run never started          -> OWED
#   T17b  draft red test, then the ready run's row CANCELLED    -> OWED
#   T17c  draft red test, then a ready-run row still running    -> OWED
#   T17d  control: draft red test, then the ready run's row GREEN -> SKIPPABLE (newest wins; the pin is not reject-everything)
# =============================================================================
DRAFT_RED='{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}'
READY_CANCELLED='{"name":"test","status":"completed","conclusion":"cancelled","started_at":"2026-01-01T01:00:00Z","app":{"id":15368}}'
READY_RUNNING='{"name":"test","status":"in_progress","conclusion":null,"started_at":"2026-01-01T01:00:00Z","app":{"id":15368}}'
READY_GREEN='{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T01:00:00Z","app":{"id":15368}}'
new_fixture_root R17
W17="$(build_fixture "$R17")"
S17="$R17/stub"
t17() { # <label> <expected-rc> <checks-json>
  make_stub "$S17" "$PINNED_REQUIRED" "$3" "$(head_sha_of "$W17")"
  assert_eq "$2" "$(run_gate "$W17" "$S17")" "$1"
}
t17 "T17a draft-era red test, ready run never started -> OWED" "$OWED" "[$DRAFT_RED]"
t17 "T17b draft-era red test then a CANCELLED ready row -> OWED" "$OWED" "[$DRAFT_RED,$READY_CANCELLED]"
t17 "T17c draft-era red test then a ready row still running -> OWED" "$OWED" "[$DRAFT_RED,$READY_RUNNING]"
t17 "T17d draft-era red test then a GREEN ready row -> SKIPPABLE (newest row wins)" "$SKIPPABLE" "[$DRAFT_RED,$READY_GREEN]"
# Mutants of a COPY (the real gate is never touched): each lets a draft-era row read as verified, so the matching row must go RED.
mut17() { # <id> <python-old> <python-new> <row-label> <expected-rc-of-the-real-gate> <checks-json>
  local m="$R17/mut-$1.sh" got
  cp "$GATE" "$m"
  # <7>/<8> (optional) is a SECOND edit: T17c is guarded twice (the in-flight refusal AND the final success test), so one site
  # alone cannot redden it.
  if ! OLD="$2" NEW="$3" OLD2="${7:-}" NEW2="${8:-}" python3 -c '
import os, sys
p = sys.argv[1]; s = open(p).read()
for o, n in ((os.environ["OLD"], os.environ["NEW"]), (os.environ["OLD2"], os.environ["NEW2"])):
    if not o: continue
    if s.count(o) != 1: sys.exit(1)
    s = s.replace(o, n)
open(p, "w").write(s)' "$m"; then
    assert_eq "landed" "mutation did not land" "T17 $1 mutation lands exactly once"; return 0
  fi
  make_stub "$S17" "$PINNED_REQUIRED" "$6" "$(head_sha_of "$W17")"
  local saved="$GATE"; GATE="$m"; got="$(run_gate "$W17" "$S17")"; GATE="$saved"
  if [[ "$got" != "$5" ]]; then assert_eq "red" "red" "T17 $1: $4 goes RED against the mutant (rc $got, the real gate gives $5)"
  else assert_eq "red" "still-green:$got" "T17 $1: $4 goes RED against the mutant"; fi
}
mut17 M17a 'if .conclusion == "success" then "ok" else "NOT-GREEN" end' 'if .conclusion != null then "ok" else "NOT-GREEN" end' "T17a (draft red test)" "$OWED" "[$DRAFT_RED]"
mut17 M17b 'if .conclusion == "success" then "ok" else "NOT-GREEN" end' 'if (.conclusion == "success" or .conclusion == "cancelled") then "ok" else "NOT-GREEN" end' "T17b (cancelled ready row)" "$OWED" "[$DRAFT_RED,$READY_CANCELLED]"
mut17 M17c 'elif ($rows | any(.status != "completed")) then "NOT-GREEN"' 'elif false then "NOT-GREEN"' "T17c (ready row still running)" "$OWED" "[$DRAFT_RED,$READY_RUNNING]" \
  'if .conclusion == "success" then "ok" else "NOT-GREEN" end' 'if .conclusion != "failure" then "ok" else "NOT-GREEN" end'

# =============================================================================
# T18 — the operator's `ci-is-the-gate` token (the brief said "rely on CI", ship ran the local battery anyway).
#
# A `- ci-is-the-gate: <words>` bullet under `## Operator Constraints` in THIS branch's session-state.md makes the gate
# return 42 without CI evidence: conditions 1 (dirty tree), 2 (behind main) and 4 (CI state) do not apply to it. It never
# overrides the infra surface (committed, staged or untracked) or an unresolved diff. T18a-c isolate ONE outranked condition
# each and carry a same-fixture no-token CONTROL (the branch is renamed so the token is invisible while tree and HEAD are
# unchanged), T18d is the incident shape, T18e-i the infra refusals (rename, staged, quoted paths, tag, merge, git-failure shims), T18j-n the reject side, T18o the printed words, T18p the
# writer/reader parity.
# =============================================================================
TOK18='## Operator Constraints\n- constraint: Rely on CI required test check\n- ci-is-the-gate: Rely on CI required test check\n'
REF18="$HERE/../skills/one-shot/references/operator-constraints.md"

# Writes (and optionally commits) the branch's session-state.md. The operands are relative to the fixture root.
ss18_write() { # <work> <printf-%b body> [commit] [spec-dir-name]
  local w="$1" body="$2" commit="${3:-}" d="${4:-feat-fixture}"
  in_fixture "$w" bash -c 'mkdir -p "knowledge-base/project/specs/$2" && printf "%b" "$1" > "knowledge-base/project/specs/$2/session-state.md"' _ "$body" "$d" || true
  if [[ -n "$commit" ]]; then in_fixture "$w" bash -c 'git add -A && git commit --quiet -m session-state' || true; fi
  return 0
}

# A needle that must NOT appear. Always paired with a positive needle at the call site, so an empty crash output cannot satisfy it.
assert_not_reason() { # <work> <stub> <needle> <label>
  local out
  out="$(run_gate_out "$1" "$2")"
  if printf '%s' "$out" | grep -cF >/dev/null "$3"; then
    assert_eq "absent" "present: $3" "$4"
  else
    assert_eq "ok" "ok" "$4"
  fi
}

# The reject side: OWED, fell through to condition 4, and no token verdict.
reject18() { # <label> <work> <stub>
  assert_eq "$OWED" "$(run_gate "$2" "$3")" "$1: OWED"
  assert_reason "$2" "$3" "required context(s) not present" "$1: falls through to condition 4"
  assert_not_reason "$2" "$3" "operator ci-is-the-gate" "$1: no token verdict"
}

# The no-token control: the branch is renamed, so the token file is not this branch's. Same tree, same HEAD.
ctl18() { # <work> <stub> <expected-rc> <reason-needle> <label>
  in_fixture "$1" git branch -m feat-fixture feat-other || true
  assert_eq "$3" "$(run_gate "$1" "$2")" "$5: no-token control rc"
  assert_reason "$1" "$2" "$4" "$5: no-token control reason"
  in_fixture "$1" git branch -m feat-other feat-fixture || true
}

# run_gate from a subdirectory of the fixture (the arm must not depend on the cwd).
run_gate_sub() { # <work> <stub> <subdir>
  ( cd "$1/$3" || exit 9
    git_fixture_env "$1" || exit 9
    PATH="$2:$PATH" bash "$GATE" >/dev/null 2>&1 )
  printf '%s' "$?"
}

# --- T18a: token outranks condition 4 (ruleset unreadable) -------------------
new_fixture_root R18a; W18a="$(build_fixture "$R18a")"; S18a="$R18a/stub"
ss18_write "$W18a" "$TOK18" commit
make_stub "$S18a" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$W18a")" "[]" 1
assert_eq "$SKIPPABLE" "$(run_gate "$W18a" "$S18a")" "T18a token + ruleset unreadable -> SKIPPABLE (the token outranks condition 4)"
ctl18 "$W18a" "$S18a" 2 "could not read the branch ruleset" "T18a"

# --- T18b: token outranks condition 2 (behind origin/main) -------------------
new_fixture_root R18b; W18b="$(build_fixture "$R18b")"; S18b="$R18b/stub"
in_fixture "$W18b" bash -c 'git checkout --quiet main && printf "newer\n" > on-main.md && git add -A && git commit --quiet -m "main advances" && git push --quiet origin main && git checkout --quiet feat-fixture' || true
ss18_write "$W18b" "$TOK18" commit
make_stub "$S18b" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$W18b")"
assert_eq "$SKIPPABLE" "$(run_gate "$W18b" "$S18b")" "T18b token + branch BEHIND origin/main -> SKIPPABLE (the token outranks condition 2)"
ctl18 "$W18b" "$S18b" "$OWED" "not an ancestor of HEAD" "T18b"

# --- T18c: token outranks condition 1 (UNTRACKED session-state.md) -----------
new_fixture_root R18c; W18c="$(build_fixture "$R18c")"; S18c="$R18c/stub"
ss18_write "$W18c" "$TOK18"
make_stub "$S18c" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$W18c")"
assert_eq "$SKIPPABLE" "$(run_gate "$W18c" "$S18c")" "T18c token in an UNTRACKED file (dirty tree) -> SKIPPABLE (the token outranks condition 1)"
ctl18 "$W18c" "$S18c" "$OWED" "working tree is dirty" "T18c"

# --- T18d: the incident shape, every outranked condition at once -------------
# Untracked token as the LAST of three bullets, branch behind, required contexts ABSENT, ruleset readable.
new_fixture_root R18d; W18d="$(build_fixture "$R18d")"; S18d="$R18d/stub"
in_fixture "$W18d" bash -c 'git checkout --quiet main && printf "newer\n" > on-main.md && git add -A && git commit --quiet -m "main advances" && git push --quiet origin main && git checkout --quiet feat-fixture' || true
ss18_write "$W18d" '## Operator Constraints\n- constraint: one\n- constraint: two\n- ci-is-the-gate: Rely on CI required test check\n'
make_stub "$S18d" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$SKIPPABLE" "$(run_gate "$W18d" "$S18d")" "T18d dirty + behind + no CI evidence + token last of three -> SKIPPABLE (incident shape)"
assert_reason "$W18d" "$S18d" "local battery NOT executed per operator constraint" "T18d the verdict tells the PR author what to record"

# --- T18e-i: the infra surface is never skipped (contexts ABSENT: "arm gone" falls to a different reason) ---
INFRA_REASON='operator ci-is-the-gate set, but the diff touches the infra surface'
new_fixture_root R18e; W18e="$(build_fixture "$R18e")"; S18e="$R18e/stub"
in_fixture "$W18e" bash -c 'mkdir -p apps/web-platform/infra && printf x > apps/web-platform/infra/deploy.sh && git add -A && git commit --quiet -m infra' || true
ss18_write "$W18e" "$TOK18" commit
make_stub "$S18e" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18e" "$S18e")" "T18e token + committed apps/web-platform/infra path -> OWED"
assert_reason "$W18e" "$S18e" "$INFRA_REASON" "T18e the infra refusal names itself"

new_fixture_root R18f; W18f="$(build_fixture "$R18f")"; S18f="$R18f/stub"
in_fixture "$W18f" bash -c 'mkdir -p .github/workflows && printf x > .github/workflows/apply-web-platform-infra.yml && git add -A && git commit --quiet -m wf' || true
ss18_write "$W18f" "$TOK18" commit
make_stub "$S18f" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18f" "$S18f")" "T18f token + ONLY the apply-web-platform-infra.yml workflow in the diff -> OWED (second alternative)"
assert_reason "$W18f" "$S18f" "$INFRA_REASON" "T18f the infra refusal names itself"

new_fixture_root R18g; W18g="$(build_fixture "$R18g")"; S18g="$R18g/stub"
ss18_write "$W18g" "$TOK18" commit
in_fixture "$W18g" bash -c 'mkdir -p apps/web-platform/infra sub && printf x > apps/web-platform/infra/new.tf' || true
make_stub "$S18g" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18g" "$S18g")" "T18g token + an UNTRACKED infra file (clean committed diff), from the repo root -> OWED"
assert_reason "$W18g" "$S18g" "$INFRA_REASON" "T18g (root) the infra refusal names itself"
assert_eq "$OWED" "$(run_gate_sub "$W18g" "$S18g" sub)" "T18g the same untracked infra file seen from a SUBDIRECTORY -> OWED (repo-wide, not cwd-relative)"
# An unstaged edit of a TRACKED infra file that is already on main (so it is not in the committed diff).
new_fixture_root R18g2; W18g2="$(build_fixture "$R18g2")"; S18g2="$R18g2/stub"
in_fixture "$W18g2" bash -c 'git checkout --quiet main && mkdir -p apps/web-platform/infra && printf a > apps/web-platform/infra/t.tf && git add -A && git commit --quiet -m i && git push --quiet origin main && git checkout --quiet feat-fixture && git merge --quiet origin/main --no-edit' || true
ss18_write "$W18g2" "$TOK18" commit
in_fixture "$W18g2" bash -c 'printf b > apps/web-platform/infra/t.tf' || true
make_stub "$S18g2" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18g2" "$S18g2")" "T18g an UNSTAGED edit of a tracked infra file -> OWED"
assert_reason "$W18g2" "$S18g2" "$INFRA_REASON" "T18g (unstaged) the infra refusal names itself"

# A rename OUT of the infra surface (the old path must be listed): committed, then staged. The file lives on main so it is not in
# the branch's own diff before the move.
mk18_tf() { # <work> : puts apps/web-platform/infra/t.tf on main and merges it into the feature branch
  in_fixture "$1" bash -c 'git checkout --quiet main && mkdir -p apps/web-platform/infra && printf a > apps/web-platform/infra/t.tf && git add -A && git commit --quiet -m i && git push --quiet origin main && git checkout --quiet feat-fixture && git merge --quiet origin/main --no-edit' || true
}
new_fixture_root R18h; W18h="$(build_fixture "$R18h")"; S18h="$R18h/stub"
mk18_tf "$W18h"
in_fixture "$W18h" bash -c 'git mv apps/web-platform/infra/t.tf moved.tf && git commit --quiet -m moved' || true
ss18_write "$W18h" "$TOK18" commit
make_stub "$S18h" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18h" "$S18h")" "T18h token + a COMMITTED rename out of the infra surface -> OWED"
assert_reason "$W18h" "$S18h" "$INFRA_REASON" "T18h (committed) the infra refusal names itself"
new_fixture_root R18h2; W18h2="$(build_fixture "$R18h2")"; S18h2="$R18h2/stub"
mk18_tf "$W18h2"
ss18_write "$W18h2" "$TOK18" commit
in_fixture "$W18h2" bash -c 'git mv apps/web-platform/infra/t.tf moved.tf' || true
make_stub "$S18h2" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18h2" "$S18h2")" "T18h token + a STAGED rename out of the infra surface -> OWED"
assert_reason "$W18h2" "$S18h2" "$INFRA_REASON" "T18h (staged) the infra refusal names itself"

# A path staged then deleted from disk shows only in the --cached listing.
new_fixture_root R18ad; W18ad="$(build_fixture "$R18ad")"; S18ad="$R18ad/stub"
ss18_write "$W18ad" "$TOK18" commit
in_fixture "$W18ad" bash -c 'mkdir -p apps/web-platform/infra && printf x > apps/web-platform/infra/ad.tf && git add apps/web-platform/infra/ad.tf && rm apps/web-platform/infra/ad.tf' || true
make_stub "$S18ad" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18ad" "$S18ad")" "T18h token + an infra path staged then deleted from disk -> OWED"
assert_reason "$W18ad" "$S18ad" "$INFRA_REASON" "T18h (staged+deleted) the infra refusal names itself"

# Paths git C-quotes (a non-ASCII byte) must still match the ^-anchored pattern, in EACH of the -z sources.
new_fixture_root R18i; W18i="$(build_fixture "$R18i")"; S18i="$R18i/stub"
in_fixture "$W18i" bash -c 'mkdir -p apps/web-platform/infra && printf x > "apps/web-platform/infra/$(printf "\303\251").tf" && git add -A && git commit --quiet -m q1' || true
ss18_write "$W18i" "$TOK18" commit
make_stub "$S18i" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18i" "$S18i")" "T18i token + a committed infra path with a non-ASCII byte (git C-quotes it) -> OWED"
assert_reason "$W18i" "$S18i" "$INFRA_REASON" "T18i (committed) the infra refusal names itself"
new_fixture_root R18i2; W18i2="$(build_fixture "$R18i2")"; S18i2="$R18i2/stub"
in_fixture "$W18i2" bash -c 'mkdir -p apps/web-platform/infra && printf x > "apps/web-platform/infra/$(printf "\303\251").tf" && git add -A && git commit --quiet -m q2 && git push --quiet origin feat-fixture' || true
in_fixture "$W18i2" bash -c 'git checkout --quiet main && git merge --quiet --ff-only feat-fixture && git push --quiet origin main && git checkout --quiet feat-fixture' || true
ss18_write "$W18i2" "$TOK18" commit
in_fixture "$W18i2" bash -c 'printf y > "apps/web-platform/infra/$(printf "\303\251").tf"' || true
make_stub "$S18i2" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18i2" "$S18i2")" "T18i token + an UNSTAGED edit of a tracked non-ASCII infra path -> OWED"
assert_reason "$W18i2" "$S18i2" "$INFRA_REASON" "T18i (unstaged) the infra refusal names itself"
new_fixture_root R18i3; W18i3="$(build_fixture "$R18i3")"; S18i3="$R18i3/stub"
ss18_write "$W18i3" "$TOK18" commit
in_fixture "$W18i3" bash -c 'mkdir -p apps/web-platform/infra && printf a > apps/web-platform/infra/a.txt && printf x > "apps/web-platform/infra/$(printf "\303\251").tf" && printf z > zzz.txt && printf z > 0first.txt' || true
make_stub "$S18i3" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18i3" "$S18i3")" "T18i token + UNTRACKED non-ASCII infra path among other untracked files -> OWED"
assert_reason "$W18i3" "$S18i3" "$INFRA_REASON" "T18i (untracked) the infra refusal names itself"

# A tag named like the base ref must not shadow refs/remotes/origin/main (it would empty the committed diff).
new_fixture_root R18t; W18t="$(build_fixture "$R18t")"; S18t="$R18t/stub"
in_fixture "$W18t" bash -c 'mkdir -p apps/web-platform/infra && printf x > apps/web-platform/infra/deploy.sh && git add -A && git commit --quiet -m infra' || true
ss18_write "$W18t" "$TOK18" commit
in_fixture "$W18t" bash -c 'git tag origin/main HEAD' || true
make_stub "$S18t" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18t" "$S18t")" "T18i a tag named origin/main does not hide a committed infra change -> OWED"
assert_reason "$W18t" "$S18t" "$INFRA_REASON" "T18i (tag) the infra refusal names itself"

# A merge in progress with unmerged paths is refused even with a token.
new_fixture_root R18m; W18m="$(build_fixture "$R18m")"; S18m="$R18m/stub"
in_fixture "$W18m" bash -c 'git checkout --quiet main && mkdir -p plugins/soleur && printf other > plugins/soleur/thing.md && git add -A && git commit --quiet -m conflict && git push --quiet origin main && git checkout --quiet feat-fixture && git merge origin/main --no-edit' || true
ss18_write "$W18m" "$TOK18"
make_stub "$S18m" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18m" "$S18m")" "T18i token + a merge in progress with unmerged paths -> OWED"
assert_reason "$W18m" "$S18m" "a merge is in progress or paths are unmerged" "T18i (merge) the refusal names itself"

# Each of the four git sources fails closed: a git shim that fails on that source's argv -> UNDECIDABLE.
REAL_GIT18="$(command -v git)"
shim18() { # <label> <argv-pattern>
  new_fixture_root SHIMROOT18
  local w s
  w="$(build_fixture "$SHIMROOT18")"; s="$SHIMROOT18/stub"
  ss18_write "$w" "$TOK18" commit
  make_stub "$s" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
  ( cd "$s" && printf '#!/usr/bin/env bash\ncase "$*" in *"%s"*) exit 1 ;; esac\nexec %s "$@"\n' "$2" "$REAL_GIT18" > git && chmod +x git )
  assert_eq "$UNDECIDABLE" "$(run_gate "$w" "$s")" "$1: a failing git source -> UNDECIDABLE (never SKIPPABLE)"
  assert_reason "$w" "$s" "working-tree scope check failed" "$1: the failure names itself"
}
shim18 "T18i source 1 (committed diff)" "--name-only refs/remotes/origin/main...HEAD --"
shim18 "T18i source 2 (working tree)" "--name-only HEAD --"
shim18 "T18i source 3 (untracked)" "ls-files -z"
shim18 "T18i source 4 (staged)" "--cached HEAD --"

# --- T18j-n: the reject side (clean tree, in sync, contexts ABSENT: the fall-through is condition 4) ---
new_fixture_root R18r; W18r="$(build_fixture "$R18r")"; S18r="$R18r/stub"
make_stub "$S18r" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
ss18_write "$W18r" '## Plan Phase\n- ci-is-the-gate: x\n' commit
reject18 "T18j token under the wrong section" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- constraint: a\n### Errors\n- ci-is-the-gate: x\n' commit
reject18 "T18j token under a sub-heading after the section" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- ci-is-the-gate:\n' commit
reject18 "T18k token with no words" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- ci-is-the-gate: \0001 \n' commit
reject18 "T18k token with only a control character and a space (the emptiness test, not the awk anchor)" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- ci-is-the-gate: \0303\0251\n' commit
reject18 "T18k token with only non-ASCII" "$W18r" "$S18r"
ss18_write "$W18r" "$TOK18" commit some-other-branch
in_fixture "$W18r" bash -c 'git rm --quiet -r knowledge-base/project/specs/feat-fixture && git commit --quiet -m drop' || true
reject18 "T18l token only in another branch's session-state.md" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- constraint: ci-is-the-gate: x\n' commit
reject18 "T18m a constraint line that merely contains the token words" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- constraint: a\n\n- ci-is-the-gate: x\n' commit
reject18 "T18m token appended after a blank line" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- constraint: a\nnote\n- ci-is-the-gate: x\n' commit
reject18 "T18m token after a non-bullet line" "$W18r" "$S18r"

ss18_write "$W18r" '```markdown\n## Operator Constraints\n\n- ci-is-the-gate: quoted\n```\n' commit
reject18 "T18m a section inside a code fence" "$W18r" "$S18r"
ss18_write "$W18r" '<!--\n## Operator Constraints\n- ci-is-the-gate: hidden\n-->\n' commit
reject18 "T18m a section inside an HTML comment" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- constraint: a\n\n## Operator Constraints\n- ci-is-the-gate: x\n' commit
reject18 "T18n two sections of the same name void the token" "$W18r" "$S18r"
in_fixture "$W18r" bash -c 'mkdir -p knowledge-base/project/specs/real && printf "## Operator Constraints\n\n- ci-is-the-gate: via link\n" > knowledge-base/project/specs/real/session-state.md && rm -f knowledge-base/project/specs/feat-fixture/session-state.md && ln -s ../real/session-state.md knowledge-base/project/specs/feat-fixture/session-state.md && git add -A && git commit --quiet -m link' || true
reject18 "T18m a symlinked session-state.md" "$W18r" "$S18r"
in_fixture "$W18r" bash -c 'git rm -q -r knowledge-base/project/specs/feat-fixture knowledge-base/project/specs/real && git commit --quiet -m unlink' || true
for body18 in \
  '## Operator Constraints Extra\n\n- ci-is-the-gate: x\n' \
  '### Operator Constraints\n\n- ci-is-the-gate: x\n' \
  '## Operator Constraints\n- ci-is-the-gate:x\n' \
  '## Operator Constraints\n- CI-IS-THE-GATE: x\n' \
  '## Operator Constraints\n- ci-is-the-gate-not: x\n' \
  '~~~\n## Operator Constraints\n- ci-is-the-gate: x\n~~~\n' \
  '````\n```\n## Operator Constraints\n- ci-is-the-gate: x\n```\n````\n' \
  '   ```\n## Operator Constraints\n- ci-is-the-gate: x\n   ```\n' \
  '> ```\n## Operator Constraints\n- ci-is-the-gate: x\n> ```\n' \
  '<!-- x --> <!--\n## Operator Constraints\n- ci-is-the-gate: x\n-->\n' \
  '## Operator Constraints\n- constraint: no <!-- markers\n- ci-is-the-gate: x\n'
do
  ss18_write "$W18r" "$body18" commit
  reject18 "T18m look-alike or quoted section (${body18:0:34})" "$W18r" "$S18r"
done

# --- T18x: the arm stays LIVE in the real repo shape, and each remaining guard has its own row ---------------------
# (a) a tracked, UNCHANGED infra file inherited from main plus a gitignored infra cache must not force OWED (liveness);
new_fixture_root R18x; W18x="$(build_fixture "$R18x")"; S18x="$R18x/stub"
mk18_tf "$W18x"
in_fixture "$W18x" bash -c 'printf "apps/web-platform/infra/.terraform/\n" > .gitignore && git add -A && git commit --quiet -m ignore' || true
ss18_write "$W18x" "$TOK18" commit
in_fixture "$W18x" bash -c 'mkdir -p apps/web-platform/infra/.terraform && printf x > apps/web-platform/infra/.terraform/cache' || true
make_stub "$S18x" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$SKIPPABLE" "$(run_gate "$W18x" "$S18x")" "T18x token + a tracked unchanged infra file + an ignored infra cache -> SKIPPABLE (the arm stays live)"
assert_eq "$SKIPPABLE" "$(run_gate_sub "$W18x" "$S18x" plugins)" "T18x the same verdict from a SUBDIRECTORY (token path is repo-root based)"
# (b) the newline joins between the path sources: a path glued to its neighbour would miss the ^ anchor;
new_fixture_root R18j; W18j="$(build_fixture "$R18j")"; S18j="$R18j/stub"
ss18_write "$W18j" "$TOK18" commit
in_fixture "$W18j" bash -c 'printf q >> README.md && mkdir -p apps/web-platform/infra && printf x > apps/web-platform/infra/a.tf' || true
make_stub "$S18j" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18j" "$S18j")" "T18x a modified tracked file followed by an untracked infra file (w2|w3 join) -> OWED"
new_fixture_root R18k; W18k="$(build_fixture "$R18k")"; S18k="$R18k/stub"
ss18_write "$W18k" "$TOK18" commit
in_fixture "$W18k" bash -c 'printf z > zzz.txt && mkdir -p apps/web-platform/infra && printf x > apps/web-platform/infra/ad2.tf && git add apps/web-platform/infra/ad2.tf && rm apps/web-platform/infra/ad2.tf' || true
make_stub "$S18k" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18k" "$S18k")" "T18x an untracked file followed by a staged-then-deleted infra path (w3|w4 join) -> OWED"
# (c) an empty branch diff whose HEAD is not an ancestor of origin/main stays UNDECIDABLE even with a token;
new_fixture_root R18g3; W18g3="$(build_fixture "$R18g3")"; S18g3="$R18g3/stub"
in_fixture "$W18g3" bash -c 'git rm -q plugins/soleur/thing.md && git commit --quiet -m undo && git checkout --quiet main && mkdir -p plugins/soleur && printf n > plugins/soleur/other.md && git add -A && git commit --quiet -m adv && git push --quiet origin main && git checkout --quiet feat-fixture' || true
ss18_write "$W18g3" "$TOK18"
make_stub "$S18g3" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$UNDECIDABLE" "$(run_gate "$W18g3" "$S18g3")" "T18x token + an empty branch diff whose HEAD is not an ancestor of origin/main -> UNDECIDABLE"
assert_reason "$W18g3" "$S18g3" "operator ci-is-the-gate set but the branch diff is empty" "T18x the undecidable names the token"
# (d) each half of the merge refusal alone: MERGE_HEAD without unmerged paths, unmerged paths without MERGE_HEAD;
new_fixture_root R18ma; W18ma="$(build_fixture "$R18ma")"; S18ma="$R18ma/stub"
in_fixture "$W18ma" bash -c 'git checkout --quiet main && printf n > on-main.md && git add -A && git commit --quiet -m adv && git push --quiet origin main && git checkout --quiet feat-fixture && git merge --no-commit --no-ff origin/main' || true
ss18_write "$W18ma" "$TOK18"
make_stub "$S18ma" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18ma" "$S18ma")" "T18x MERGE_HEAD alone (clean --no-commit merge) -> OWED"
assert_reason "$W18ma" "$S18ma" "a merge is in progress or paths are unmerged" "T18x (MERGE_HEAD alone) the refusal names itself"
new_fixture_root R18mb; W18mb="$(build_fixture "$R18mb")"; S18mb="$R18mb/stub"
in_fixture "$W18mb" bash -c 'git checkout --quiet main && mkdir -p plugins/soleur && printf other > plugins/soleur/thing.md && git add -A && git commit --quiet -m adv && git push --quiet origin main && git checkout --quiet feat-fixture && git cherry-pick origin/main' || true
ss18_write "$W18mb" "$TOK18"
make_stub "$S18mb" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18mb" "$S18mb")" "T18x unmerged paths alone (cherry-pick conflict, no MERGE_HEAD) -> OWED"
assert_reason "$W18mb" "$S18mb" "a merge is in progress or paths are unmerged" "T18x (unmerged alone) the refusal names itself"
# (e) a grep that prints 0 / fails must not read as 'no infra match';
shimgrep18() { # <label> <script-body>
  new_fixture_root SHIMGROOT18
  local w s
  w="$(build_fixture "$SHIMGROOT18")"; s="$SHIMGROOT18/stub"
  ss18_write "$w" "$TOK18" commit
  make_stub "$s" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
  ( cd "$s" && printf '#!/usr/bin/env bash\n%s\n' "$2" > grep && chmod +x grep )
  assert_eq "$UNDECIDABLE" "$(run_gate "$w" "$s")" "$1 -> UNDECIDABLE (never SKIPPABLE)"
  assert_reason "$w" "$s" "infra scope check did not run" "$1: the failure names itself"
}
shimgrep18 "T18x a grep that prints 0 and exits 1" 'echo 0; exit 1'
shimgrep18 "T18x a grep that exits 2 with no output" 'exit 2'
shim18 "T18x the unmerged-path probe fails" "ls-files -u"
# (f) a symlinked PARENT directory reads no token; a slash branch reads its nested path; first-wins; allowed characters survive.
new_fixture_root R18sd; W18sd="$(build_fixture "$R18sd")"; S18sd="$R18sd/stub"
make_stub "$S18sd" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
in_fixture "$W18sd" bash -c 'mkdir -p ../outside-specs/feat-fixture && printf "## Operator Constraints\n\n- ci-is-the-gate: via parent link\n" > ../outside-specs/feat-fixture/session-state.md && mkdir -p knowledge-base/project && ln -s ../../../outside-specs knowledge-base/project/specs && git add -A && git commit --quiet -m parentlink' || true
reject18 "T18x a symlinked parent directory" "$W18sd" "$S18sd"
new_fixture_root R18sl; W18sl="$(build_fixture "$R18sl")"; S18sl="$R18sl/stub"
in_fixture "$W18sl" git branch -m feat-fixture feat/slash || true
ss18_write "$W18sl" "$TOK18" commit "feat/slash"
make_stub "$S18sl" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$W18sl")"
assert_eq "$SKIPPABLE" "$(run_gate "$W18sl" "$S18sl")" "T18x a branch name holding / reads specs/<a>/<b>/session-state.md -> SKIPPABLE"
new_fixture_root R18fw; W18fw="$(build_fixture "$R18fw")"; S18fw="$R18fw/stub"
ss18_write "$W18fw" '## Operator Constraints\n- ci-is-the-gate: first, v1.2 ok 3-4 days\n- ci-is-the-gate: second\n' commit
make_stub "$S18fw" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$SKIPPABLE" "$(run_gate "$W18fw" "$S18fw")" "T18x two token lines in one section -> SKIPPABLE"
assert_reason "$W18fw" "$S18fw" "first, v1.2 ok 3-4 days" "T18x the first line wins and its allowed characters survive"
assert_not_reason "$W18fw" "$S18fw" "second" "T18x the second token line is not printed"

# (g) the allow-list drops shell metacharacters, and an inherited git-location variable cannot redirect the reads.
new_fixture_root R18al; W18al="$(build_fixture "$R18al")"; S18al="$R18al/stub"
ss18_write "$W18al" '## Operator Constraints\n- ci-is-the-gate: alpha;beta\n' commit
make_stub "$S18al" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_reason "$W18al" "$S18al" "alphabeta" "T18x a semicolon in the words is dropped, its neighbours kept"
assert_not_reason "$W18al" "$S18al" "alpha;beta" "T18x the semicolon is not printed"
new_fixture_root R18gv; W18gv="$(build_fixture "$R18gv")"; S18gv="$R18gv/stub"
ss18_write "$W18gv" "$TOK18" commit
make_stub "$S18gv" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$SKIPPABLE" "$( ( cd "$W18gv" || exit 9
    git_fixture_env "$W18gv" >/dev/null 2>&1 || exit 9
    GIT_DIR="$R18gv/no-such-gitdir" GIT_INDEX_FILE="$R18gv/no-such-index" PATH="$S18gv:$PATH" bash "$GATE" >/dev/null 2>&1
    printf '%s' "$?" ) )" "T18x an inherited GIT_DIR / GIT_INDEX_FILE cannot redirect the gate's reads -> SKIPPABLE"

# (h) verification-pass gaps: an in-repo symlinked directory, a corrupt MERGE_HEAD, a gitlink hidden by ignore=all.
new_fixture_root R18ld; W18ld="$(build_fixture "$R18ld")"; S18ld="$R18ld/stub"
make_stub "$S18ld" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
in_fixture "$W18ld" bash -c 'mkdir -p knowledge-base/project/specs-real/feat-fixture knowledge-base/project/specs && printf "## Operator Constraints\n\n- ci-is-the-gate: via in-repo link\n" > knowledge-base/project/specs-real/feat-fixture/session-state.md && ln -s ../specs-real/feat-fixture knowledge-base/project/specs/feat-fixture && git add -A && git commit --quiet -m inrepolink' || true
reject18 "T18x an in-repo symlinked spec directory" "$W18ld" "$S18ld"
new_fixture_root R18mh; W18mh="$(build_fixture "$R18mh")"; S18mh="$R18mh/stub"
ss18_write "$W18mh" "$TOK18" commit
make_stub "$S18mh" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$SKIPPABLE" "$(run_gate "$W18mh" "$S18mh")" "T18x (control) a clean tree with the token -> SKIPPABLE"
in_fixture "$W18mh" bash -c 'echo garbage > "$(git rev-parse --absolute-git-dir)/MERGE_HEAD"' || true
assert_eq "$OWED" "$(run_gate "$W18mh" "$S18mh")" "T18x a corrupt MERGE_HEAD file -> OWED"
assert_reason "$W18mh" "$S18mh" "a merge is in progress or paths are unmerged" "T18x (corrupt MERGE_HEAD) the refusal names itself"
new_fixture_root R18sm; W18sm="$(build_fixture "$R18sm")"; S18sm="$R18sm/stub"
ss18_write "$W18sm" "$TOK18"
make_stub "$S18sm" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
in_fixture "$W18sm" bash -c 'git init --quiet ../subsrc && git -C ../subsrc -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m s && mkdir -p apps/web-platform/infra && git -c protocol.file.allow=always submodule add --quiet ../subsrc apps/web-platform/infra/sub && git config -f .gitmodules submodule.apps/web-platform/infra/sub.ignore all && git add -A && git commit --quiet -m gitlink' || true
assert_eq "$OWED" "$(run_gate "$W18sm" "$S18sm")" "T18x a gitlink under the infra surface hidden by ignore=all -> OWED"
assert_reason "$W18sm" "$S18sm" "the diff touches the infra surface" "T18x (hidden gitlink) the refusal names the infra surface"

# --- T18o: the words are printed as untrusted ASCII, cut at 200 bytes --------
new_fixture_root R18o; W18o="$(build_fixture "$R18o")"; S18o="$R18o/stub"
make_stub "$S18o" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
PFX18='a$(touch SENTINEL18)b`touch SENTINEL18`c"d'
PAD18="$(printf 'y%.0s' $(seq 1 $(( 196 - ${#PFX18} ))))"
ss18_write "$W18o" "## Operator Constraints\\n- ci-is-the-gate: ${PFX18}\\0001${PAD18}QRSZ\\n" commit
assert_eq "$SKIPPABLE" "$(run_gate "$W18o" "$S18o")" "T18o a long token with markup and a control character -> SKIPPABLE"
OUT18o="$(run_gate_out "$W18o" "$S18o")"
if printf '%s' "$OUT18o" | grep -cF >/dev/null 'QRS' && ! printf '%s' "$OUT18o" | grep -cF >/dev/null 'QRSZ'; then
  assert_eq "ok" "ok" "T18o the 200-byte cut keeps bytes 198-200 and drops byte 201"
else
  assert_eq "$OUT18o" "QRS present, QRSZ absent" "T18o the 200-byte cut keeps bytes 198-200 and drops byte 201"
fi
WORDS18o="$(printf '%s' "$OUT18o" | sed -n 's/.*session-state.md: \(.*\)): local battery.*/\1/p')"
if [[ -n "$WORDS18o" ]] && ! grep -qE "[^A-Za-z0-9 ,.-]" <<<"$WORDS18o"; then
  assert_eq "ok" "ok" "T18o only [A-Za-z0-9 ,.-] survive in the printed words"
else
  assert_eq "$WORDS18o" "only [A-Za-z0-9 ,.-]" "T18o only [A-Za-z0-9 ,.-] survive in the printed words"
fi
assert_reason "$W18o" "$S18o" "untrusted text from session-state.md" "T18o the words are labelled untrusted"
assert_reason "$W18d" "$S18d" "this script read no CI state" "T18d the verdict claims no CI state it did not read"

# --- T18p: writer/reader parity ----------------------------------------------
# The strings one-shot is told to write (the reference's fenced example) must be the strings the gate reads.
parity_rc() { # <reference-path> <work> <stub> : writes the reference's WHOLE fenced example verbatim
  local ref="$1" w="$2" st="$3" body
  [[ -r "$ref" ]] || { printf 'NOREF'; return 0; }
  body="$(awk '/^```/{f=!f; next} f' "$ref")"
  [[ -n "$body" ]] || { printf 'EMPTY'; return 0; }
  ss18_write "$w" "${body}\n" commit
  run_gate "$w" "$st"
}
new_fixture_root R18p; W18p="$(build_fixture "$R18p")"; S18p="$R18p/stub"
make_stub "$S18p" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "ok" "$([[ -r "$REF18" ]] && echo ok || echo unreadable)" "T18p the reference file is readable"
assert_eq "$SKIPPABLE" "$(parity_rc "$REF18" "$W18p" "$S18p")" "T18p the reference's own example section is read by the gate as a token -> SKIPPABLE"
( cd "$R18p" && sed 's/^## Operator Constraints$/## Op Constraints/' "$REF18" > ref-renamed.md )
assert_eq "$OWED" "$(parity_rc "$R18p/ref-renamed.md" "$W18p" "$S18p")" "T18p a reference whose heading is renamed does NOT parse as a token -> OWED (the row can fail)"

# =============================================================================
# T19 — `--token-only` and its consumers (#12247). Work Phase 2 and review's lead gate reach the reader through
# plugins/soleur/scripts/gate-or-skip.sh; the Grok pre-push gate calls it inline. Only exit 42 skips, only a bare
# invocation consults the token, and ship Phase 4 (T16) keeps calling the reader with no argument. T18 already pins the
# shared token arm, so these rows pin only what the flag, the wrapper and the call sites add.
# =============================================================================
GOS="$HERE/../scripts/gate-or-skip.sh"
GROKS="$HERE/../scripts/grok-pre-push-gate.sh"
WORK_SKILL="$HERE/../skills/work/SKILL.md"
REVIEW_SKILL="$HERE/../skills/review/SKILL.md"
TOKFLAG='--token-only'

# gate run with arguments; rc only / output. Both end on a success so the suite's errexit cannot kill a refusal row.
run_gate_args() { # <work> <stub> [args...]
  local work="$1" stub="$2"; shift 2
  ( cd "$work" || exit 9
    git_fixture_env "$work" || exit 9
    PATH="$stub:$PATH" bash "$GATE" "$@" >/dev/null 2>&1 )
  printf '%s' "$?"
  return 0
}
run_gate_args_out() { # <work> <stub> [args...]
  local work="$1" stub="$2" out; shift 2
  out="$( ( cd "$work" || exit 9
            git_fixture_env "$work" >/dev/null 2>&1 || exit 9
            PATH="$stub:$PATH" bash "$GATE" "$@" 2>&1 ) || true )"
  printf '%s' "$out"
  return 0
}
reason_args() { # <work> <stub> <needle> <label> [args...]
  local w="$1" s="$2" n="$3" l="$4" out; shift 4
  out="$(run_gate_args_out "$w" "$s" "$@")"
  if grep -qF -- "$n" <<<"$out"; then assert_eq "ok" "ok" "$l"; else assert_eq "$out" "reason containing: $n" "$l"; fi
  return 0
}
assert_has() { # <haystack> <needle> <label>
  if grep -qF -- "$2" <<<"$1"; then assert_eq "ok" "ok" "$3"; else assert_eq "missing: $2" "present" "$3"; fi
  return 0
}
assert_lacks() { # <haystack> <needle> <label>
  if grep -qF -- "$2" <<<"$1"; then assert_eq "present: $2" "absent" "$3"; else assert_eq "ok" "ok" "$3"; fi
  return 0
}
# A gh shim that LOGS its argv and then runs the stub, so "no CI state was read" is observable (the bare control proves the shim fires).
shim19() { # <shim-dir> <real-stub-dir>
  assert_fixture_dir "$1"
  mkdir -p "$1"
  : > "$1/calls.log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/calls.log"\nexec "%s/gh" "$@"\n' "$1" "$2" > "$1/gh"
  chmod +x "$1/gh"
  return 0
}

# --- T19a: no token -> OWED without reading CI state -------------------------
new_fixture_root R19a; W19a="$(build_fixture "$R19a")"; S19a="$R19a/stub"; H19a="$R19a/shim"
make_stub "$S19a" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$W19a")"
shim19 "$H19a" "$S19a"
assert_eq "$SKIPPABLE" "$(run_gate "$W19a" "$H19a")" "T19a (control) the bare run on a green-CI tree with no token -> SKIPPABLE"
assert_eq "nonempty" "$([[ -s "$H19a/calls.log" ]] && echo nonempty || echo empty)" "T19a (control) the bare run reads CI state, so the call log is non-empty and the shim fires"
assert_fixture_dir "$H19a"
: > "$H19a/calls.log"
assert_eq "$OWED" "$(run_gate_args "$W19a" "$H19a" "$TOKFLAG")" "T19a --token-only with no token on the same tree -> OWED"
reason_args "$W19a" "$H19a" "no operator ci-is-the-gate token" "T19a the reason names the missing token" "$TOKFLAG"
assert_eq "empty" "$([[ -s "$H19a/calls.log" ]] && echo nonempty || echo empty)" "T19a --token-only with no token read no CI state (empty gh call log)"

# --- T19b: token -> the existing token arm, nothing else ---------------------
new_fixture_root R19b; W19b="$(build_fixture "$R19b")"; S19b="$R19b/stub"
in_fixture "$W19b" bash -c 'git checkout --quiet main && printf "newer\n" > on-main.md && git add -A && git commit --quiet -m "main advances" && git push --quiet origin main && git checkout --quiet feat-fixture' || true
ss18_write "$W19b" '## Operator Constraints\n- constraint: one\n- constraint: two\n- ci-is-the-gate: Rely on CI required test check\n'
in_fixture "$W19b" git merge-base --is-ancestor refs/remotes/origin/main HEAD && B19="in-sync" || B19="behind"
assert_eq "behind" "$B19" "T19b (precondition) the fixture really is behind origin/main"
make_stub "$S19b" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$SKIPPABLE" "$(run_gate_args "$W19b" "$S19b" "$TOKFLAG")" "T19b --token-only + token + dirty + behind main + no CI evidence -> SKIPPABLE (incident shape)"
reason_args "$W19b" "$S19b" "local battery NOT executed per operator constraint" "T19b the verdict tells the author what to record" "$TOKFLAG"
new_fixture_root R19b2; W19b2="$(build_fixture "$R19b2")"; S19b2="$R19b2/stub"
ss18_write "$W19b2" "$TOK18" commit
make_stub "$S19b2" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$W19b2")"
assert_eq "$SKIPPABLE" "$(run_gate_args "$W19b2" "$S19b2" "$TOKFLAG")" "T19b --token-only + token + green CI -> SKIPPABLE"
reason_args "$W19b2" "$S19b2" "operator declared CI the gate" "T19b on green CI the reason is the operator token, not the CI-evidence verdict" "$TOKFLAG"
assert_lacks "$(run_gate_args_out "$W19b2" "$S19b2" "$TOKFLAG")" "required contexts present and green" "T19b the CI-evidence verdict never appears under --token-only"

# --- T19c: the infra surface still wins --------------------------------------
new_fixture_root R19c; W19c="$(build_fixture "$R19c")"; S19c="$R19c/stub"
in_fixture "$W19c" bash -c 'mkdir -p apps/web-platform/infra && printf x > apps/web-platform/infra/deploy.sh && git add -A && git commit --quiet -m infra' || true
ss18_write "$W19c" "$TOK18" commit
make_stub "$S19c" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate_args "$W19c" "$S19c" "$TOKFLAG")" "T19c --token-only + token + infra path -> OWED"
reason_args "$W19c" "$S19c" "$INFRA_REASON" "T19c the infra refusal names itself" "$TOKFLAG"

# --- T19d: the argument parser is closed -------------------------------------
assert_eq "$SKIPPABLE" "$(run_gate "$W19b2" "$S19b2")" "T19d (control) the bare run with a token -> SKIPPABLE"
assert_eq "$SKIPPABLE" "$(run_gate_args "$W19b2" "$S19b2" --token-only)" "T19d (control) a lone --token-only with a token -> SKIPPABLE"
assert_eq "$UNDECIDABLE" "$(run_gate_args "$W19b2" "$S19b2" --bogus)" "T19d an unknown flag -> UNDECIDABLE even with a token"
reason_args "$W19b2" "$S19b2" "unknown argument" "T19d the unknown flag names itself" --bogus
assert_eq "$UNDECIDABLE" "$(run_gate_args "$W19b2" "$S19b2" --token-only extra)" "T19d a second argument -> UNDECIDABLE"
reason_args "$W19b2" "$S19b2" "unknown argument" "T19d the second argument names itself" --token-only extra
assert_eq "$UNDECIDABLE" "$(run_gate_args "$W19b2" "$S19b2" "")" "T19d an empty-string argument -> UNDECIDABLE"
assert_lacks "$(run_gate_args_out "$W19b2" "$S19b2" --bogus-VALUE-19)" "bogus-VALUE-19" "T19d the rejected argument is not echoed"

# A plain repository with no knowledge-base and no origin/main: the short-circuit precedes the origin/main check.
new_fixture_root R19e
( cd "$R19e" && git_fixture_env "$R19e" && git init --quiet plain && cd plain && printf x > f && git add -A && git commit --quiet -m s ) >/dev/null 2>&1 || true
reason_args "$R19e/plain" "$S19a" "is not an ancestor of HEAD" "T19e (control) the bare run in a plain repo reaches the origin/main condition"
assert_eq "$OWED" "$(run_gate_args "$R19e/plain" "$S19a" "$TOKFLAG")" "T19e --token-only in a plain repo without origin/main -> OWED"
reason_args "$R19e/plain" "$S19a" "no operator ci-is-the-gate token" "T19e --token-only answers before any origin/main check" "$TOKFLAG"

# CONTROL: assert_has / assert_lacks / reason_args each OWN their verdict, so the dispatch floor and the assert_eq self-test above
# cannot see one of them being neutered. Drive each in the pass AND the fail direction; the three deliberate FAILs are unwound.
_p19=$PASS; _f19=$FAIL
assert_has "abc" "b" "T19 control: assert_has accepts a present needle"
assert_lacks "abc" "z" "T19 control: assert_lacks accepts an absent needle"
reason_args "$R19e/plain" "$S19a" "no operator ci-is-the-gate token" "T19 control: reason_args accepts a present reason" "$TOKFLAG"
_p19b=$PASS; _f19b=$FAIL
assert_has "abc" "zzz" "T19 control: assert_has rejects an absent needle (EXPECTED FAIL, subtracted)"
assert_lacks "abc" "abc" "T19 control: assert_lacks rejects a present needle (EXPECTED FAIL, subtracted)"
reason_args "$R19e/plain" "$S19a" "this reason does not exist" "T19 control: reason_args rejects a missing reason (EXPECTED FAIL, subtracted)" "$TOKFLAG"
if (( _p19b - _p19 != 3 || FAIL - _f19b != 3 || _f19b != _f19 )); then
  printf 'FATAL: T19 helper controls did not move the counters as expected (pass %s->%s, fail %s->%s->%s).\n' "$_p19" "$_p19b" "$_f19" "$_f19b" "$FAIL" >&2
  exit 1
fi
FAIL=$(( FAIL - 3 ))

# --- T19f: the wrapper, against a FAKE plugin tree ---------------------------
# Stub reader (prints SKIPPABLE-shaped text whatever it exits) and stub gate log their argv; the wrapper resolves its siblings
# from its own directory, so the fake tree is the only thing it can see.
mk_gos_tree() { # <root> <reader-rc|MISSING> <gate-rc>
  local r="$1" rrc="$2" grc="$3"
  assert_fixture_dir "$r"
  mkdir -p "$r/plugins/soleur/scripts" "$r/plugins/soleur/skills/ship/scripts"
  cp "$GOS" "$r/plugins/soleur/scripts/gate-or-skip.sh" 2>/dev/null || true
  : > "$r/reader.args"; : > "$r/gate.args"
  if [[ "$rrc" != MISSING ]]; then
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/reader.args"\nprintf "battery-owed: SKIPPABLE - stub verdict (no trailing newline)"\nexit %s\n' "$r" "$rrc" > "$r/plugins/soleur/skills/ship/scripts/battery-owed.sh"
  fi
  printf '#!/usr/bin/env bash\nprintf "RUN\\n" >> "%s/gate.args"\nfor a in "$@"; do printf "<%%s>\\n" "$a" >> "%s/gate.args"; done\nexit %s\n' "$r" "$r" "$grc" > "$r/plugins/soleur/scripts/affected-tests.sh"
  return 0
}
run_gos() { # <root> [args...] -> GOS_RC, GOS_OUT
  local r="$1"; shift
  GOS_RC=0
  GOS_OUT="$(bash "$r/plugins/soleur/scripts/gate-or-skip.sh" "$@" 2>&1)" || GOS_RC=$?
  return 0
}
gate_calls() { grep -c '^RUN$' "$1/gate.args" 2>/dev/null || true; return 0; }
gate_argv() { grep -v '^RUN$' "$1/gate.args" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true; return 0; }

new_fixture_root G42; mk_gos_tree "$G42" 42 0; run_gos "$G42"
assert_eq "0" "$GOS_RC" "T19f reader 42 on a bare invocation -> the wrapper exits 0"
assert_has "$GOS_OUT" "SKIPPED (NOT run, NOT passed)" "T19f the skip says it was NOT run and NOT passed"
assert_has "$GOS_OUT" "AFFECTED_GATE_SKIPPED reason=operator-ci-is-the-gate" "T19f the skip prints its machine line"
assert_has "$GOS_OUT" "battery-owed: SKIPPABLE - stub verdict" "T19f the reader's own verdict line is printed"
assert_eq "0" "$(gate_calls "$G42")" "T19f reader 42 -> the gate is NOT invoked"
assert_eq "--token-only" "$(cat "$G42/reader.args")" "T19f the reader saw exactly --token-only"
G42_STDOUT="$(bash "$G42/plugins/soleur/scripts/gate-or-skip.sh" 2>/dev/null || true)"
assert_has "$G42_STDOUT" "SKIPPED (NOT run, NOT passed)" "T19f the SKIPPED wording is on STDOUT (a lead capturing only stdout still sees it)"
assert_has "$G42_STDOUT" "AFFECTED_GATE_SKIPPED reason=operator-ci-is-the-gate" "T19f the machine line is on STDOUT"

for rrc in 0 1 2 41 43 137; do
  new_fixture_root GR; mk_gos_tree "$GR" "$rrc" 0; run_gos "$GR"
  assert_eq "1" "$(gate_calls "$GR")" "T19f reader $rrc -> the gate runs once"
  assert_eq "" "$(gate_argv "$GR")" "T19f reader $rrc -> the gate gets no arguments"
  assert_eq "0" "$GOS_RC" "T19f reader $rrc -> the gate's rc 0 is returned"
done
new_fixture_root GM; mk_gos_tree "$GM" MISSING 0; run_gos "$GM"
assert_eq "1" "$(gate_calls "$GM")" "T19f a missing reader -> the gate runs"
for grc in 6 1; do
  new_fixture_root GP; mk_gos_tree "$GP" 0 "$grc"; run_gos "$GP"
  assert_eq "$grc" "$GOS_RC" "T19f the gate's rc $grc passes through unchanged"
done

# Any argument bypasses the token: the reader (configured to say 42) is not consulted and the gate gets the arguments verbatim.
new_fixture_root GA; mk_gos_tree "$GA" 42 0; run_gos "$GA" --full
assert_eq "<--full>" "$(gate_argv "$GA")" "T19f --full reaches the gate verbatim"
assert_eq "" "$(cat "$GA/reader.args")" "T19f --full does not consult the reader"
new_fixture_root GB; mk_gos_tree "$GB" 42 0; run_gos "$GB" --base "a b" --explain
assert_eq "<--base> <a b> <--explain>" "$(gate_argv "$GB")" "T19f a preview with a spaced argument reaches the gate as the same argv (no word splitting)"
assert_eq "" "$(cat "$GB/reader.args")" "T19f a preview does not consult the reader"
new_fixture_root GE; mk_gos_tree "$GE" 42 0; run_gos "$GE" ""
assert_eq "1" "$(gate_calls "$GE")" "T19f an empty-string argument runs the gate"
assert_eq "<>" "$(gate_argv "$GE")" "T19f the empty-string argument reaches the gate as one empty argument"
assert_eq "" "$(cat "$GE/reader.args")" "T19f an empty-string argument does not consult the reader"

# A decoy CLAUDE_PLUGIN_ROOT whose reader says 42 must not skip (siblings resolve from the wrapper's own directory).
new_fixture_root GD1; mk_gos_tree "$GD1" 0 0
new_fixture_root GD2; mk_gos_tree "$GD2" 42 0
GOS_RC=0; GOS_OUT="$(CLAUDE_PLUGIN_ROOT="$GD2/plugins/soleur" bash "$GD1/plugins/soleur/scripts/gate-or-skip.sh" 2>&1)" || GOS_RC=$?
assert_eq "1" "$(gate_calls "$GD1")" "T19f a decoy CLAUDE_PLUGIN_ROOT does not skip: the gate runs"
assert_eq "" "$(cat "$GD2/reader.args")" "T19f the decoy tree's reader is never consulted"

# Live repo: the sibling reader the wrapper resolves exists and answers the flag.
GOS_DIR="$(cd -P "$(dirname "$GOS")" 2>/dev/null && pwd -P)"
LIVE_READER="$GOS_DIR/../skills/ship/scripts/battery-owed.sh"
assert_eq "readable" "$([[ -r "$LIVE_READER" ]] && echo readable || echo unreadable)" "T19f the reader beside the wrapper is readable"
assert_eq "$UNDECIDABLE" "$( ( bash "$LIVE_READER" --token-only --bogus >/dev/null 2>&1 ); printf '%s' "$?" )" "T19f the live reader answers --token-only --bogus with UNDECIDABLE"

# Flag parity: the string the wrapper passes and the string the Grok block passes are the string the reader accepts.
flag_of() { # <file> <invocation-var>
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -F -- "\"\$$2\"" | grep -oE -- '--[a-z][a-z-]*' | head -n1
}
FLAG_W="$(flag_of "$GOS" READER || true)"
FLAG_G="$(flag_of "$GROKS" BATTERY_OWED || true)"
new_fixture_root R19p; W19p="$(build_fixture "$R19p")"; S19p="$R19p/stub"
make_stub "$S19p" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
for pair in "wrapper:$FLAG_W" "grok:$FLAG_G"; do
  nm="${pair%%:*}"; fl="${pair#*:}"
  assert_eq "nonempty" "$([[ -n "$fl" ]] && echo nonempty || echo empty)" "T19f the $nm flag string was extracted"
  if [[ -n "$fl" ]]; then
    reason_args "$W19p" "$S19p" "no operator ci-is-the-gate token" "T19f the real reader accepts the $nm flag ($fl)" "$fl"
  else
    assert_eq "extracted" "empty" "T19f the real reader accepts the $nm flag (nothing to run)"
  fi
done
reason_args "$W19p" "$S19p" "unknown argument" "T19f (control) the same fixture rejects --bogus" --bogus

# --- T19g: the Grok gate's two sentinel blocks -------------------------------
block_of() { awk -v s="# $2:start" -v e="# $2:end" '$0 == s {f=1; next} $0 == e {f=0} f' "$1" 2>/dev/null; }
G19_DISPATCH="$(block_of "$GROKS" grok-token-dispatch)"
G19_BANNER="$(block_of "$GROKS" grok-token-banner)"
assert_eq "nonempty" "$([[ -n "$G19_DISPATCH" ]] && echo nonempty || echo empty)" "T19g the dispatch block was extracted"
assert_eq "nonempty" "$([[ -n "$G19_BANNER" ]] && echo nonempty || echo empty)" "T19g the banner block was extracted"
run_grok19() { # <reader-rc> -> G19_RC G19_OUT G19_CALLS G19_RARGS
  local rrc="$1" gd
  new_fixture_root gd
  assert_fixture_dir "$gd"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/reader.args"\n[ "$*" = "--token-only" ] || exit 64\nexit %s\n' "$gd" "$rrc" > "$gd/reader.sh"
  : > "$gd/calls.log"
  {
    printf 'set -euo pipefail\nBATTERY_OWED=%q\nGATE=/nonexistent/gate.sh\n' "$gd/reader.sh"
    printf 'run_step() { printf "%%s\\n" "$1" >> %q; }\n' "$gd/calls.log"
    printf '%s\n' "$G19_DISPATCH"
    printf 'echo "FSB=${FIDELITY_SKIP_BUDGET:-unset}"\n'
    printf 'echo TRAILING-STEP\n'
    printf '%s\n' "$G19_BANNER"
  } > "$gd/harness.sh"
  G19_RC=0
  G19_OUT="$(bash "$gd/harness.sh" 2>&1)" || G19_RC=$?
  G19_CALLS="$(cat "$gd/calls.log")"
  G19_RARGS="$(cat "$gd/reader.args" 2>/dev/null || true)"
  return 0
}
run_grok19 42
assert_eq "0" "$G19_RC" "T19g reader 42 -> the block runs to the end with exit 0"
assert_eq "" "$G19_CALLS" "T19g reader 42 -> run_step is never called"
assert_eq "--token-only" "$G19_RARGS" "T19g the reader saw exactly --token-only"
assert_has "$G19_OUT" "PASS WITH SKIPPED GATE" "T19g a skip ends in the distinct banner"
assert_lacks "$G19_OUT" "safe to git push" "T19g a skip never prints the plain PASS banner"
assert_has "$G19_OUT" "TRAILING-STEP" "T19g the later steps still run after a skip"
assert_has "$G19_OUT" "[note] affected-tests gate SKIPPED (NOT run, NOT passed)" "T19g the skip note is printed"
assert_has "$G19_OUT" "FSB=0" "T19g a waived affected step makes grok-fidelity RUN its rule-budget lint (nothing else ran test-all)"
for rrc in 0 1 2 41 43 137; do
  run_grok19 "$rrc"
  assert_eq "0" "$G19_RC" "T19g reader $rrc -> the block runs to the end with exit 0 (no errexit abort)"
  assert_eq "affected-tests gate" "$G19_CALLS" "T19g reader $rrc -> run_step runs the affected-tests gate once"
  assert_has "$G19_OUT" "safe to git push" "T19g reader $rrc -> the plain PASS banner"
  assert_lacks "$G19_OUT" "PASS WITH SKIPPED GATE" "T19g reader $rrc -> no skip banner"
  assert_has "$G19_OUT" "FSB=1" "T19g reader $rrc -> grok-fidelity may skip its rule-budget lint (the affected gate ran test-all)"
done
GROK_CODE="$(grep -v '^[[:space:]]*#' "$GROKS" 2>/dev/null || true)"
assert_eq "1" "$(grep -cF -- '"$BATTERY_OWED"' <<<"$GROK_CODE" || true)" "T19g the Grok script invokes the reader exactly once"
assert_eq "1" "$(grep -cF -- "$TOKFLAG" <<<"$GROK_CODE" || true)" "T19g the Grok script carries the flag exactly once"
assert_eq "1" "$(grep -cF -- 'run_step "affected-tests gate" bash "$GATE"' <<<"$GROK_CODE" || true)" "T19g the bare affected-tests gate line is kept, exactly once (a second unconditional call would defeat the waiver)"
assert_has "$(grep -E '^GATE=' "$GROKS" || true)" "affected-tests.sh" "T19g GATE= still names affected-tests.sh"

# The script's REAL sibling-path assignment (the harness above supplies its own): it resolves, is sibling-relative, answers the flag.
BO_LINE="$(grep -E '^BATTERY_OWED=' "$GROKS" || true)"
BO_PATH="$(bash -c 'line=${2//\$\{BASH_SOURCE\[0\]\}/$1}; eval "$line"; printf %s "$BATTERY_OWED"' _ "$GROKS" "$BO_LINE" 2>/dev/null || true)"
assert_eq "readable" "$([[ -n "$BO_PATH" && -r "$BO_PATH" ]] && echo readable || echo unreadable)" "T19g the Grok script's real BATTERY_OWED path resolves to a readable reader"
assert_lacks "$BO_LINE" "CLAUDE_PLUGIN_ROOT" "T19g the Grok reader path is sibling-relative, never env-directed"
assert_eq "$UNDECIDABLE" "$( ( bash "$BO_PATH" --token-only --bogus >/dev/null 2>&1 ); printf '%s' "$?" )" "T19g the resolved Grok reader answers --token-only --bogus with UNDECIDABLE"
# The waiver's footprint: every non-comment reference to AFFECTED_GATE_WAIVED sits inside the two sentinel blocks.
WAIVED_ALL="$(grep -v '^[[:space:]]*#' "$GROKS" | grep -c 'AFFECTED_GATE_WAIVED' || true)"
WAIVED_IN="$( { printf '%s\n' "$G19_DISPATCH"; printf '%s\n' "$G19_BANNER"; } | grep -v '^[[:space:]]*#' | grep -c 'AFFECTED_GATE_WAIVED' || true)"
assert_eq "$WAIVED_IN" "$WAIVED_ALL" "T19g no reference to the waiver flag exists outside the two sentinel blocks (a widened waiver would add one)"
assert_eq "ok" "$([[ "$WAIVED_IN" -ge 3 ]] && echo ok || echo "only $WAIVED_IN")" "T19g the waiver flag is initialised, set and read inside the blocks"

GROK_EXPORT_LINE="$(grep -E '^export GROK_FIDELITY_SKIP_BUDGET=' "$GROKS" || true)"
assert_eq 'export GROK_FIDELITY_SKIP_BUDGET="$FIDELITY_SKIP_BUDGET"' "$GROK_EXPORT_LINE" "T19g the fidelity-budget export is derived from the waiver-aware variable (a literal 1 would hide the rule-budget lint on a waived push)"

# The waiver's other names: _tok_rc must not exist outside the blocks, and FIDELITY_SKIP_BUDGET exactly once (the export line).
for nm in _tok_rc FIDELITY_SKIP_BUDGET; do
  OUT_N="$(grep -v '^[[:space:]]*#' "$GROKS" | grep -c "$nm" || true)"
  IN_N="$( { printf '%s\n' "$G19_DISPATCH"; printf '%s\n' "$G19_BANNER"; } | grep -v '^[[:space:]]*#' | grep -c "$nm" || true)"
  WANT_OUT=0; [[ "$nm" == FIDELITY_SKIP_BUDGET ]] && WANT_OUT=1
  assert_eq "$WANT_OUT" "$(( OUT_N - IN_N ))" "T19g $nm is referenced outside the sentinel blocks exactly $WANT_OUT time(s)"
done
# Executable: the REAL script from the dispatch block through the export line, stubs for the reader and run_step.
run_grok_export() { # <reader-rc>
  local rrc="$1" gd
  new_fixture_root gd
  assert_fixture_dir "$gd"
  printf '#!/usr/bin/env bash\nexit %s\n' "$rrc" > "$gd/reader.sh"
  {
    printf 'set -euo pipefail\ncd %q\nBATTERY_OWED=%q\nGATE=/nonexistent/gate.sh\nSKIP_BUILD=1\nrun_step() { :; }\nstep() { :; }\nnpm() { echo NPM-CALLED >&2; exit 99; }\n' "$gd" "$gd/reader.sh"
    awk '/^# grok-token-dispatch:start$/ {f=1} f {print} /^export GROK_FIDELITY_SKIP_BUDGET=/ {exit}' "$GROKS"
    printf 'echo "EXPORTED=${GROK_FIDELITY_SKIP_BUDGET:-unset}"\n'
  } > "$gd/harness.sh"
  GX_OUT="$(env -u GROK_FIDELITY_SKIP_BUDGET -u FIDELITY_SKIP_BUDGET bash "$gd/harness.sh" 2>&1)" || GX_OUT="rc!=0: $GX_OUT"
  return 0
}
run_grok_export 42
assert_has "$GX_OUT" "EXPORTED=0" "T19g the REAL script exports 0 after a waive (the value grok-fidelity sees, with anything between the block and the export included)"
for rrc in 0 2 43; do
  run_grok_export "$rrc"
  assert_has "$GX_OUT" "EXPORTED=1" "T19g the REAL script exports 1 when the affected step runs (reader $rrc)"
done
FIDELITY_GATE="$HERE/../scripts/grok-fidelity-gate.sh"
assert_has "$(grep -F 'GROK_FIDELITY_SKIP_BUDGET' "$FIDELITY_GATE" || true)" '!= "1"' "T19g grok-fidelity skips its rule-budget lint ONLY on the literal 1, so 0 runs it"
GATE_LINE="$(grep -E '^GATE=' "$GROKS" || true)"
GATE_PATH="$(bash -c 'line=${2//\$\{BASH_SOURCE\[0\]\}/$1}; eval "$line"; printf %s "$GATE"' _ "$GROKS" "$GATE_LINE" 2>/dev/null || true)"
assert_eq "readable" "$([[ -n "$GATE_PATH" && -r "$GATE_PATH" ]] && echo readable || echo unreadable)" "T19g the Grok script's real GATE path resolves to a readable affected-tests.sh"

# --- T19h: the call sites ----------------------------------------------------
FENCE19="$(awk '/Affected-Test Exit Gate/ {h=1} h && /^ *```bash/ {o=1; next} o && /^ *```/ {exit} o' "$WORK_SKILL" 2>/dev/null || true)"
FENCE19_CODE="$(grep -v '^[[:space:]]*#' <<<"$FENCE19" || true)"
FENCE19_SENT="$(awk '/Affected-Test Exit Gate/ {h=1} h' "$WORK_SKILL" 2>/dev/null | head -n 20 || true)"
assert_eq "nonempty" "$([[ -n "$FENCE19" ]] && echo nonempty || echo empty)" "T19h work step 9's fence was extracted"
assert_has "$FENCE19_CODE" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh"' "T19h work step 9 runs the wrapper"
FENCE19_CMDS="$(grep -v '^[[:space:]]*#' <<<"$FENCE19" | sed 's/^[[:space:]]*//; /^$/d' || true)"
assert_eq 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh"' "$FENCE19_CMDS" "T19h work step 9's fence holds EXACTLY the wrapper command (no echo prefix, no || true, no extra line)"
assert_lacks "$FENCE19_CODE" "affected-tests.sh" "T19h work step 9's command lines no longer name affected-tests.sh"
assert_has "$FENCE19" "affected-tests.sh" "T19h the fence keeps the affected-tests.sh literal in a comment (fullsuite-merge-gate pin)"
WORK_LEAD="$(awk -v RS= '/The lead runs the gate/' "$WORK_SKILL" 2>/dev/null || true)"
REVIEW_LEAD="$(awk -v RS= '/The lead runs the gate/' "$REVIEW_SKILL" 2>/dev/null || true)"
assert_eq "nonempty" "$([[ -n "$WORK_LEAD" ]] && echo nonempty || echo empty)" "T19h work's fan-out lead paragraph was extracted"
assert_eq "nonempty" "$([[ -n "$REVIEW_LEAD" ]] && echo nonempty || echo empty)" "T19h review's lead paragraph was extracted"
assert_has "$WORK_LEAD" '${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh' "T19h work's fan-out lead gate uses the wrapper"
assert_has "$REVIEW_LEAD" '${CLAUDE_PLUGIN_ROOT}/scripts/gate-or-skip.sh' "T19h review's lead gate uses the wrapper"
assert_has "$WORK_LEAD" 'AFFECTED_GATE_SKIPPED' "T19h work's fan-out lead names the unique skip token"
assert_has "$REVIEW_LEAD" 'AFFECTED_GATE_SKIPPED' "T19h review's lead gate names the unique skip token"
assert_has "$FENCE19_SENT" 'AFFECTED_GATE_SKIPPED' "T19h work step 9 names the unique skip token"
assert_has "$FENCE19_SENT" 'was NOT run' "T19h work step 9 says the gate was NOT run (not just that the token exists)"
# The gates that must stay token-blind: a fix loop and the commit hook run tests, and the executables never read the token.
for f in "$HERE/../skills/test-fix-loop/SKILL.md" "$HERE/../../../lefthook.yml"; do
  assert_eq "readable" "$([[ -s "$f" ]] && echo readable || echo unreadable)" "T19h negative: $(basename "$f") is readable"
  assert_eq "0" "$(grep -cE 'gate-or-skip|--token-only|ci-is-the-gate' "$f" 2>/dev/null || true)" "T19h negative: $(basename "$f") does not reference the wrapper, the flag or the token"
done
LIBS19="$(ls "$HERE"/../scripts/lib/affected-tests/*.sh 2>/dev/null || true)"
for f in "$HERE/../scripts/affected-tests.sh" "$HERE/../skills/ship/scripts/battery-refusal-wait.sh" "$HERE/../../../scripts/test-all.sh" "$HERE/../../../scripts/hooks/pre-push" $LIBS19; do
  assert_eq "readable" "$([[ -s "$f" ]] && echo readable || echo unreadable)" "T19h negative: $(basename "$f") is readable"
  assert_eq "0" "$(grep -cE 'gate-or-skip|--token-only|ci-is-the-gate' "$f" 2>/dev/null || true)" "T19h negative: $(basename "$f") never reads the token"
done
CALLERS19="$(cd "$HERE/../../.." && grep -rlE 'gate-or-skip|--token-only' plugins/soleur/skills plugins/soleur/scripts .github/workflows 2>/dev/null | sort | tr '\n' ' ' || true)"
WANT_CALLERS19="plugins/soleur/scripts/gate-or-skip.sh plugins/soleur/scripts/grok-pre-push-gate.sh plugins/soleur/skills/one-shot/references/operator-constraints.md plugins/soleur/skills/review/SKILL.md plugins/soleur/skills/ship/references/affected-gate-contract.md plugins/soleur/skills/ship/scripts/battery-owed.sh plugins/soleur/skills/work/SKILL.md "
assert_eq "$WANT_CALLERS19" "$CALLERS19" "T19h the set of files naming the wrapper or the flag is CLOSED (a new caller must be added here on purpose)"
OC_ITEM4="$(grep -E '^4\. ' "$REF18" 2>/dev/null || true)"
assert_has "$OC_ITEM4" "--token-only" "T19h the writer reference's item 4 names the --token-only readers"
assert_has "$OC_ITEM4" "gate-or-skip.sh" "T19h the writer reference's item 4 names the wrapper"

# The floor counts the instrument self-test's two rows plus every row above.
# Set EQUAL to the current count, not below it: slack is budget for a silently
# deleted row.
print_results 391
