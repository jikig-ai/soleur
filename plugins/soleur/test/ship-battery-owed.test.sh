#!/usr/bin/env bash
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
# unchanged), T18d is the incident shape, T18e-i the infra refusals, T18j-n the reject side, T18o the printed words, T18p the
# writer/reader parity, T18q-s three committed mutants of a COPY of the gate.
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

# A rename INTO the infra surface, uncommitted: both the old and the new path must be listed.
new_fixture_root R18h; W18h="$(build_fixture "$R18h")"; S18h="$R18h/stub"
in_fixture "$W18h" bash -c 'printf y > outside.tf && git add -A && git commit --quiet -m outside' || true
ss18_write "$W18h" "$TOK18" commit
in_fixture "$W18h" bash -c 'mkdir -p apps/web-platform/infra && git mv outside.tf apps/web-platform/infra/outside.tf' || true
RN18="$( cd "$W18h" && git_fixture_env "$W18h" >/dev/null 2>&1; git diff --name-status -M HEAD | cut -c1 | head -1 )"
assert_eq "R" "$RN18" "T18h setup: the uncommitted move is a rename in git's own listing"
make_stub "$S18h" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18h" "$S18h")" "T18h token + a rename INTO the infra surface (uncommitted) -> OWED"
assert_reason "$W18h" "$S18h" "$INFRA_REASON" "T18h the infra refusal names itself"

# Paths git C-quotes (a non-ASCII byte, a tab) must still match the ^-anchored pattern.
new_fixture_root R18i; W18i="$(build_fixture "$R18i")"; S18i="$R18i/stub"
in_fixture "$W18i" bash -c 'mkdir -p apps/web-platform/infra && printf x > "apps/web-platform/infra/$(printf "\303\251").tf" && git add -A && git commit --quiet -m q1' || true
ss18_write "$W18i" "$TOK18" commit
make_stub "$S18i" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18i" "$S18i")" "T18i token + a committed infra path with a non-ASCII byte (git C-quotes it) -> OWED"
assert_reason "$W18i" "$S18i" "$INFRA_REASON" "T18i (non-ASCII) the infra refusal names itself"
new_fixture_root R18i2; W18i2="$(build_fixture "$R18i2")"; S18i2="$R18i2/stub"
in_fixture "$W18i2" bash -c 'mkdir -p apps/web-platform/infra && printf x > "apps/web-platform/infra/a$(printf "\t")b.tf" && git add -A && git commit --quiet -m q2' || true
ss18_write "$W18i2" "$TOK18" commit
make_stub "$S18i2" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "$OWED" "$(run_gate "$W18i2" "$S18i2")" "T18i token + a committed infra path with a TAB in its name -> OWED"
assert_reason "$W18i2" "$S18i2" "$INFRA_REASON" "T18i (tab) the infra refusal names itself"

# --- T18j-n: the reject side (clean tree, in sync, contexts ABSENT: the fall-through is condition 4) ---
new_fixture_root R18r; W18r="$(build_fixture "$R18r")"; S18r="$R18r/stub"
make_stub "$S18r" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
ss18_write "$W18r" '## Plan Phase\n- ci-is-the-gate: x\n' commit
reject18 "T18j token under the wrong section" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- constraint: a\n### Errors\n- ci-is-the-gate: x\n' commit
reject18 "T18j token under a sub-heading after the section" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- ci-is-the-gate:\n' commit
reject18 "T18k token with no words" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- ci-is-the-gate:  \n' commit
reject18 "T18k token with two spaces only" "$W18r" "$S18r"
ss18_write "$W18r" '## Operator Constraints\n- ci-is-the-gate: \0001\n' commit
reject18 "T18k token with only a control character" "$W18r" "$S18r"
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

# Two sections of the same name: the first token line in ANY of them wins (the writer keeps one).
new_fixture_root R18n; W18n="$(build_fixture "$R18n")"; S18n="$R18n/stub"
make_stub "$S18n" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
ss18_write "$W18n" '## Operator Constraints\n- constraint: a\n\n## Operator Constraints\n- ci-is-the-gate: x\n' commit
assert_eq "$SKIPPABLE" "$(run_gate "$W18n" "$S18n")" "T18n a token only in a SECOND section of the same name -> SKIPPABLE (documented behaviour)"

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
if printf '%s' "$OUT18o" | LC_ALL=C grep -cP >/dev/null '[\x00-\x08\x0e-\x1f"`$]'; then
  assert_eq "absent" "control, quote, backtick or dollar present" "T18o the printed words carry no control character, quote, backtick or dollar"
else
  assert_eq "ok" "ok" "T18o the printed words carry no control character, quote, backtick or dollar"
fi
if [[ -e "$W18o/SENTINEL18" ]]; then
  assert_eq "absent" "SENTINEL18 created" "T18o a command substitution inside the words is never evaluated"
else
  assert_eq "ok" "ok" "T18o a command substitution inside the words is never evaluated"
fi
assert_reason "$W18o" "$S18o" "untrusted text from session-state.md" "T18o the words are labelled untrusted"

# --- T18p: writer/reader parity ----------------------------------------------
# The strings one-shot is told to write (the reference's fenced example) must be the strings the gate reads.
parity_rc() { # <reference-path> <work> <stub>
  local ref="$1" w="$2" st="$3" heading tok
  [[ -r "$ref" ]] || { printf 'NOREF'; return 0; }
  heading="$(awk '/^```/{f=!f; next} f && /^## / {print; exit}' "$ref")"
  tok="$(awk '/^```/{f=!f; next} f && /^- ci-is-the-gate:/ {print; exit}' "$ref")"
  [[ -n "$heading" && -n "$tok" ]] || { printf 'EMPTY'; return 0; }
  ss18_write "$w" "${heading}\\n${tok}\\n" commit
  run_gate "$w" "$st"
}
new_fixture_root R18p; W18p="$(build_fixture "$R18p")"; S18p="$R18p/stub"
make_stub "$S18p" "$TWO_REQUIRED" "$GREEN_CHECKS" ""
assert_eq "ok" "$([[ -r "$REF18" ]] && echo ok || echo unreadable)" "T18p the reference file is readable"
assert_eq "$SKIPPABLE" "$(parity_rc "$REF18" "$W18p" "$S18p")" "T18p the reference's own example section is read by the gate as a token -> SKIPPABLE"
( cd "$R18p" && sed 's/^## Operator Constraints$/## Op Constraints/' "$REF18" > ref-renamed.md )
assert_eq "$OWED" "$(parity_rc "$R18p/ref-renamed.md" "$W18p" "$S18p")" "T18p a reference whose heading is renamed does NOT parse as a token -> OWED (the row can fail)"

# --- T18q-s: committed mutants of a COPY of the gate --------------------------
mut18() { # <id> <old> <new> <work> <stub> <expected-rc> <reason-needle> <label>
  local m="$R18p/mut-$1.sh" got out saved="$GATE"
  ( cd "$R18p" && cp "$GATE" "mut-$1.sh" )
  if ! OLD="$2" NEW="$3" python3 -c '
import os, sys
p = sys.argv[1]; s = open(p).read(); o = os.environ["OLD"]
if s.count(o) != 1: sys.exit(1)
open(p, "w").write(s.replace(o, os.environ["NEW"]))' "$m" || ! bash -n "$m"; then
    assert_eq "landed" "mutation did not land" "T18 $1 mutation lands exactly once and parses"; return 0
  fi
  GATE="$m"; got="$(run_gate "$4" "$5")"; out="$(run_gate_out "$4" "$5")"; GATE="$saved"
  assert_eq "$6" "$got" "T18 $1: $8 (mutant rc)"
  if printf '%s' "$out" | grep -cF >/dev/null "$7"; then assert_eq "ok" "ok" "T18 $1: $8 (mutant reason)"; else assert_eq "$out" "reason containing: $7" "T18 $1: $8 (mutant reason)"; fi
}
# Pristine-copy control: a plain copy of the gate behaves like the real one (so the mutants below are graded against a working baseline).
( cd "$R18p" && cp "$GATE" pristine.sh ); saved18="$GATE"; GATE="$R18p/pristine.sh"
assert_eq "$SKIPPABLE" "$(run_gate "$W18d" "$S18d")" "T18 control: an unmutated copy of the gate still returns 42 on the incident shape"
GATE="$saved18"
mut18 M18q 'if [[ -n "$OPERATOR_CI_WORDS" ]]; then' 'if false; then' "$W18d" "$S18d" "$OWED" "required context(s) not present" "arm disabled: the incident shape falls through to condition 4"
mut18 M18r 'grep -qE "$INFRA_RE" <<<"$_all"; _g=$?' 'true; _g=1' "$W18e" "$S18e" "$SKIPPABLE" "operator ci-is-the-gate" "arm without its infra grep: an infra diff is skipped"
mut18 M18s '[[ -z "$OPERATOR_CI_WORDS" ]] && ! git merge-base --is-ancestor refs/remotes/origin/main HEAD' '! git merge-base --is-ancestor refs/remotes/origin/main HEAD' "$W18b" "$S18b" "$OWED" "not an ancestor of HEAD" "condition 2 without its stand-down: a behind branch is refused"

# The floor counts the instrument self-test's two rows plus every row above.
# Set EQUAL to the current count, not below it: slack is budget for a silently
# deleted row.
print_results 136
