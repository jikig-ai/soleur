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
assert_eq "$(run_gate "$WORK" "$STUB")" "$SKIPPABLE" \
  "T1 clean tree + all required green on THIS sha + no infra paths -> SKIPPABLE"

# =============================================================================
# T2 — dirty tree. "CI is green" then describes a different tree.
# =============================================================================
printf 'uncommitted\n' > "$WORK/dirty.txt"
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
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
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
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
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T4 a required context passed then was RE-RUN red -> OWED (newest attempt wins)"

# The inverse, so the row above cannot pass by the gate simply ignoring order.
RERUN_GREEN='[{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T09:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$TWO_REQUIRED" "$RERUN_GREEN" "$(head_sha_of "$WORK")"
assert_eq "$(run_gate "$WORK" "$STUB")" "$SKIPPABLE" \
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
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T4c newest attempt is red and listed FIRST (production order) -> OWED (time, not array position)"

# =============================================================================
# T4d — APP IDENTITY. A pinned context is satisfiable only by its own app.
#
# All 26 required contexts on this repo pin integration_id 15368. Matching on name
# alone made the gate strictly MORE permissive than the ruleset it calls
# authoritative: any installed app with `checks: write` could satisfy a required
# context by naming a check-run after it.
# =============================================================================
FOREIGN_APP='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":99999}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$FOREIGN_APP" "$(head_sha_of "$WORK")"
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T4d a green check-run from a FOREIGN app cannot satisfy a pinned required context -> OWED"

OWN_APP='[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]'
make_stub "$STUB" "$PINNED_REQUIRED" "$OWN_APP" "$(head_sha_of "$WORK")"
assert_eq "$(run_gate "$WORK" "$STUB")" "$SKIPPABLE" \
  "T4e the SAME pinned context satisfied by its own app -> SKIPPABLE (both directions)"

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
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
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
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T5 diff touches apps/web-platform/infra/** -> OWED even with every required check green"

in_fixture "$WORK" bash -c 'git rm -r --quiet --cached apps/web-platform >/dev/null 2>&1; rm -rf apps; mkdir -p .github/workflows && printf "x\n" > .github/workflows/apply-web-platform-infra.yml && git add -A && git commit --quiet -m "infra workflow change"'
make_stub "$STUB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK")"
assert_eq "$(run_gate "$WORK" "$STUB")" "$OWED" \
  "T5b diff touches ONLY .github/workflows/apply-web-platform-infra.yml -> OWED (the second prefix test-all.sh matches)"

# =============================================================================
# T5c — the infra condition SELF-RETIRES once #6480 lands.
# =============================================================================
make_stub "$STUB" '[{"context":"test","integration_id":null},{"context":"adr-ordinals","integration_id":null},{"context":"infra-validate-required","integration_id":null}]' \
  '[{"name":"test","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"infra-validate-required","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]' \
  "$(head_sha_of "$WORK")"
assert_eq "$(run_gate "$WORK" "$STUB")" "$SKIPPABLE" \
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
assert_eq "$(run_gate "$WORKB" "$STUBB")" "$OWED" \
  "T5d branch is BEHIND origin/main -> OWED (CI verified merge(HEAD,base), not this tree)"

# And the inverse, so the row cannot pass by the gate simply always refusing.
in_fixture "$WORKB" bash -c 'git merge --quiet origin/main --no-edit'
make_stub "$STUBB" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORKB")"
assert_eq "$(run_gate "$WORKB" "$STUBB")" "$SKIPPABLE" \
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
assert_eq "$(run_gate "$WORKB" "$STUBB")" "$OWED" \
  "T5f a file renamed OUT of apps/web-platform/infra/ -> OWED (the old path must still count)"

# =============================================================================
# T6 — a required context ABSENT. The non-vacuity row.
# =============================================================================
new_fixture_root ROOT2
WORK2="$(build_fixture "$ROOT2")"
STUB2="$ROOT2/stub"
make_stub "$STUB2" '[{"context":"test","integration_id":null},{"context":"adr-ordinals","integration_id":null},{"context":"never-ran","integration_id":null}]' "$GREEN_CHECKS" "$(head_sha_of "$WORK2")"
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$OWED" \
  "T6 a required context is ABSENT (nothing failing) -> OWED, not a vacuous skip"

# =============================================================================
# T7 — present but not green.
# =============================================================================
make_stub "$STUB2" "$TWO_REQUIRED" \
  '[{"name":"test","status":"completed","conclusion":"failure","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]' \
  "$(head_sha_of "$WORK2")"
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$OWED" "T7 a required context concluded failure -> OWED"

make_stub "$STUB2" "$TWO_REQUIRED" \
  '[{"name":"test","status":"in_progress","conclusion":null,"started_at":"2026-01-01T00:00:00Z","app":{"id":15368}},{"name":"adr-ordinals","status":"completed","conclusion":"success","started_at":"2026-01-01T00:00:00Z","app":{"id":15368}}]' \
  "$(head_sha_of "$WORK2")"
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$OWED" \
  "T7b a required context still in_progress -> OWED (not-yet-green is not green)"

# =============================================================================
# T8 — the ruleset cannot be read. UNDECIDABLE, never a skip.
# =============================================================================
make_stub "$STUB2" "$TWO_REQUIRED" "$GREEN_CHECKS" "$(head_sha_of "$WORK2")" "[]" 1
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$UNDECIDABLE" \
  "T8 ruleset unreadable -> UNDECIDABLE (caller treats as OWED), never SKIPPABLE"

# =============================================================================
# T9 — an EMPTY required set. Refusing a trivially-satisfied skip.
# =============================================================================
make_stub "$STUB2" '[]' "$GREEN_CHECKS" "$(head_sha_of "$WORK2")"
assert_eq "$(run_gate "$WORK2" "$STUB2")" "$UNDECIDABLE" \
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
  *rules/branches/main*) sleep 120 ;;
esac
exit 0
HANGSTUB
chmod +x "$STUB3/gh"
_t0=$(date +%s)
_rc="$(run_gate "$WORK3" "$STUB3")"
_elapsed=$(( $(date +%s) - _t0 ))
assert_eq "$_rc" "$UNDECIDABLE" "T10 a hanging gh endpoint -> UNDECIDABLE, not a hang"
if (( _elapsed < 40 )); then
  assert_eq "bounded" "bounded" "T10b the hang returned in ${_elapsed}s (bounded well under the 120s stub sleep)"
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
AUTHORITY_PREFIXES="$(grep -A 3 "_diff_names" "$REPO_ROOT/scripts/test-all.sh" \
  | grep -oE "'(apps/web-platform/infra/|\.github/workflows/apply-web-platform-infra\.yml)'" \
  | tr -d "'" | sort -u)"
# The gate's own predicate, with regex escaping removed so a plain literal
# comparison is meaningful (the gate stores it as an ERE, `\.github/...`).
GATE_RE_LINE="$(grep -F 'INFRA_RE=' "$REPO_ROOT/plugins/soleur/skills/ship/scripts/battery-owed.sh" | tr -d '\\')"

# Non-vacuity: the authority extraction must find BOTH prefixes, or this row
# silently proves nothing about a predicate it never read.
_auth_n="$(printf '%s\n' "$AUTHORITY_PREFIXES" | grep -c .)"
assert_eq "$_auth_n" "2" "T11 authority extraction found both test-all.sh infra prefixes (else this row is vacuous)"

while IFS= read -r _p; do
  [[ -z "$_p" ]] && continue
  if printf '%s\n' "$GATE_RE_LINE" | grep -qF "$_p"; then
    assert_eq "matched" "matched" "T11 gate matches test-all.sh infra prefix '$_p'"
  else
    assert_eq "MISSING" "matched" "T11 gate does NOT match test-all.sh infra prefix '$_p' — predicate drift"
  fi
done <<< "$AUTHORITY_PREFIXES"

# The floor counts the instrument self-test's two rows plus every row above.
# Set EQUAL to the current count, not below it: slack is budget for a silently
# deleted row.
print_results 26
