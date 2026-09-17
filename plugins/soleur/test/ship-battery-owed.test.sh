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
# shellcheck source=./test-helpers.sh
source "$HERE/test-helpers.sh"

GATE="$HERE/../skills/ship/scripts/battery-owed.sh"
[[ -r "$GATE" ]] || { printf 'FATAL: gate not readable at %s\n' "$GATE" >&2; exit 1; }

OWED=0
SKIPPABLE=42
UNDECIDABLE=2

# ONE owning trap, registered before the first allocation (ADR-129, rule (c)).
# Each fixture root is appended as it is created, so a failed assertion, a
# `set -u` abort or a signal between two allocations still removes every root
# already made — a trailing `rm -rf` at the end of the file only runs on the
# happy path, which is precisely the path that does not leak.
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
  local dir="$1" required="$2" checks="$3" green_sha="${4:-}" statuses="${5:-[]}" rules_rc="${6:-0}"
  mkdir -p "$dir"
  printf '%s' "$required"  > "$dir/required.json"
  printf '%s' "$checks"    > "$dir/checks.json"
  printf '%s' "$statuses"  > "$dir/statuses.json"
  printf '%s' "$green_sha" > "$dir/green_sha"
  printf '%s' "$rules_rc"  > "$dir/rules_rc"
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
  if printf '%s\n' "$GATE_RE_LINE" | grep -qF "$_p"; then
    assert_eq "ok" "ok" "T11 gate matches test-all.sh infra prefix '$_p'"
  else
    assert_eq "MISSING" "ok" "T11 gate does NOT match test-all.sh infra prefix '$_p' — predicate drift"
  fi
done <<< "$AUTHORITY_PREFIXES"

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
GATE_SHARDS="$(printf '%s\n' "$GATE_PREMISE" | grep -oE '(test-webplat|test-bun|test-scripts|web-platform-build)' | sort -u)"
AGG_LIST="$(awk '/^  test:/{f=1} f&&/^    needs:/{print; exit}' "$CI_YML" \
  | sed -E 's/^[[:space:]]*needs:[[:space:]]*\[//; s/\][[:space:]]*$//' | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep .)"
_gate_n="$(printf '%s\n' "$GATE_SHARDS" | grep -c .)"
if [[ "$_gate_n" -ge 4 ]]; then
  assert_eq "ok" "ok" "T13 the gate's premise names $_gate_n shard(s) (>=4)"
else
  assert_eq "derived $_gate_n" "ok" "T13 premise extraction found $_gate_n shards — rows below vacuous"
fi
while IFS= read -r _shard; do
  [[ -z "$_shard" ]] && continue
  if printf '%s\n' "$AGG_LIST" | grep -qx "$_shard"; then
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

# The floor counts the instrument self-test's two rows plus every row above.
# Set EQUAL to the current count, not below it: slack is budget for a silently
# deleted row.
print_results 44
