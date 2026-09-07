#!/usr/bin/env bash
# Shared test helpers for bash test suites.
# Source this file at the top of each .test.sh file.

set -euo pipefail

# --- Guard 3 (#7833): fail-loud git-location tripwire ------------------------------------------
# The tripwire and the fixture-env builder now live in ONE file over ONE list (#7849). Sourcing it
# arms the tripwire exactly as the inlined loop did, and additionally gives every suite that sources
# these helpers a `git_fixture_env <dir>` builder -- which is the point: a suite that creates a
# fixture no longer has to spell the environment itself.
#
# Resolved relative to THIS file, never the caller's working directory: test-helpers.sh is sourced
# from suites that have already changed directory into a fixture.
# shellcheck source=./lib/git-fixture-env.sh
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/git-fixture-env.sh"

# --- Incident-telemetry sandbox (#7853) --------------------------------------------------------
# The shell arm of the same chokepoint. A suite sourcing these helpers can spawn a hook or a gate
# script, and those emit through `.claude/hooks/lib/incidents.sh`, which resolves its sink by
# walking up to the REAL repository unless INCIDENTS_REPO_ROOT says otherwise. Three suites were
# measured writing fabricated rows into the operator ledger that way.
#
# Non-destructive: a root already chosen -- by the suite, by test-incident-sandbox.sh, or by an
# outer runner -- wins. Absent one, a scratch root is created here so a DIRECTLY invoked suite is
# covered, which is the spelling all three measured leaks occurred under.
# Validate an INHERITED root too, not only one we mint. `[ -z ]` alone lets a NON-ABSOLUTE value
# through, and `_incidents_repo_root()` returns any non-empty value verbatim -- so
# `INCIDENTS_REPO_ROOT=.` resolves against the HOOK's cwd, i.e. the operator's real ledger for any
# hook spawned at the checkout root, while every static check for the variable's name reports it
# set. The TS and Python siblings both require an absolute path; these shell arms did not.
case "${INCIDENTS_REPO_ROOT:-}" in
  /?*) : ;;
  "")  _soleur_sb="$(mktemp -d -t soleur-inc-XXXXXX 2>&1)" || {
         printf "FATAL: could not create an incident-telemetry sandbox: %s\n" "${_soleur_sb}" >&2
         printf "  Refusing to run: an unset INCIDENTS_REPO_ROOT points test telemetry at the\n" >&2
         printf "  operator real .claude/.rule-incidents.jsonl.\n" >&2
         exit 1
       }
       case "${_soleur_sb:-}" in
         /?*) : ;;
         *)   printf "FATAL: mktemp produced a non-absolute sandbox path: %s\n" \
                "${_soleur_sb:-<empty>}" >&2; exit 1 ;;
       esac
       # FAIL LOUD, not `|| true`: emit_incident drops a row WITHOUT a sentinel when its parent dir
       # is missing, so on a full tmpfs every emit is silently discarded.
       mkdir -p "$_soleur_sb/.claude" || {
         printf "FATAL: could not create %s/.claude\n" "$_soleur_sb" >&2; exit 1
       }
       export INCIDENTS_REPO_ROOT="$_soleur_sb"
       export SOLEUR_TEST_INCIDENT_ROOT="$_soleur_sb"
       # Own it (ADR-129 rule (c)), COMPOSED with any EXIT trap already installed.
       _soleur_prior=$(trap -p EXIT | sed -E "s/^trap -- '(.*)' EXIT$/\1/")
       if [ -n "$_soleur_prior" ]; then
         # shellcheck disable=SC2064
         trap "$_soleur_prior; rm -rf '$_soleur_sb'" EXIT
       else
         # shellcheck disable=SC2064
         trap "rm -rf '$_soleur_sb'" EXIT
       fi
       unset _soleur_prior _soleur_sb ;;
  *)   printf "FATAL: inherited INCIDENTS_REPO_ROOT is not absolute: %s\n" \
         "$INCIDENTS_REPO_ROOT" >&2
       printf "  A relative root resolves against each hook's cwd.\n" >&2
       exit 1 ;;
esac

PASS=0
FAIL=0
SKIPPED=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected to contain: '$needle'"
    echo "    actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="$2"

  if [[ -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local path="$1"
  local msg="$2"

  if [[ ! -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file still exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

make_gh_stub() {
  # Creates a `gh` stub at "$stub_dir/gh" that handles `gh run list ...`.
  # The first arg is the stub directory (prepend to PATH); the second is the
  # literal stdout for `gh run list`. Subcommands other than `run list` exit 1.
  local stub_dir="$1" output="$2"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2" == "run list" ]]; then
  printf '%s\n' "$output"
  exit 0
fi
echo "gh stub: unhandled subcommand '\$@'" >&2
exit 1
EOF
  chmod +x "$stub_dir/gh"
}

make_gh_stub_sleep() {
  # gh stub that sleeps to exercise the parser's timeout wrapper.
  local stub_dir="$1" seconds="$2"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2" == "run list" ]]; then
  sleep $seconds
  printf '2026-02-01T00:00:00Z\n'
  exit 0
fi
exit 1
EOF
  chmod +x "$stub_dir/gh"
}

make_gh_api_stub() {
  # Creates a `gh` stub at "$stub_dir/gh" that handles `gh api <url>` and
  # `gh auth status`. Unlike make_gh_stub (which only knows `gh run list`),
  # this dispatches on the API path and serves fixtures from "$fixture_dir".
  #
  # Per-endpoint fixture files, keyed by URL substring
  # (graphql | issue_comments | stargazers | issues | pulls | commits | repo):
  #   <key>.json    stdout payload            (optional)
  #   <key>.stderr  stderr emitted alongside  (optional)
  #   <key>.exit    exit code, default 0      (optional)
  #
  # The three modes the collector suite needs fall out of those three files:
  #   (a) large valid payload  -> big <key>.json
  #   (b) stdout + stderr noise -> <key>.json plus <key>.stderr
  #   (c) exit 0 with an error body -> <key>.json = {"message":"Not Found"}
  #
  # A request with no fixture at all fails loudly rather than returning empty,
  # so a mis-keyed URL surfaces as a test error instead of a vacuous pass.
  local stub_dir="$1" fixture_dir="$2"
  mkdir -p "$stub_dir" "$fixture_dir"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'FIXTURES=%q\n' "$fixture_dir"
    cat <<'STUB'
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi

if [[ "${1:-}" != "api" ]]; then
  echo "gh api stub: unhandled subcommand '$*'" >&2
  exit 1
fi

# First non-flag argument after `api` is the endpoint.
shift
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|-f|-F|-q|--jq|--template|--method|-X) shift 2 || true; continue ;;
    --paginate|--slurp|--include|-i)         shift; continue ;;
    -*)                                      shift; continue ;;
    *)                                       url="$1"; break ;;
  esac
done

# Most specific first: an issues URL also matches the bare repos/ prefix.
key=""
case "$url" in
  graphql)            key="graphql" ;;
  */issues/comments*) key="issue_comments" ;;
  */stargazers*)      key="stargazers" ;;
  */issues*)          key="issues" ;;
  */pulls*)           key="pulls" ;;
  */commits*)         key="commits" ;;
  repos/*)            key="repo" ;;
esac

if [[ -z "$key" ]]; then
  echo "gh api stub: no fixture key for URL '$url'" >&2
  exit 1
fi

body="$FIXTURES/$key.json"
errf="$FIXTURES/$key.stderr"
codef="$FIXTURES/$key.exit"

if [[ ! -f "$body" && ! -f "$errf" && ! -f "$codef" ]]; then
  echo "gh api stub: no fixture for key '$key' (url '$url')" >&2
  exit 1
fi

if [[ -f "$errf" ]]; then cat "$errf" >&2; fi
if [[ -f "$body" ]]; then cat "$body"; fi

if [[ -f "$codef" ]]; then exit "$(cat "$codef")"; fi
exit 0
STUB
  } > "$stub_dir/gh"
  chmod +x "$stub_dir/gh"
}

# print_results [expected_assertion_count]
#
# The optional argument is an ANTI-VACUITY FLOOR, and it is the only thing that
# distinguishes "every assertion passed" from "no assertion ran". Measured on
# this suite during #7408 review: neutering `assert_eq` to `return 0` produced
#
#     Passed: 0 / Failed: 0 / ALL TESTS PASSED   (exit 0)
#
# because the green branch was keyed on `FAIL -eq 0` and nothing on `PASS > 0`.
# Deleting six of nine arms wholesale was likewise exit 0. CI reads the exit
# code, so both are indistinguishable from a clean run.
#
# A FLOOR, not equality: the count is developer-incremented, so `-eq` would turn
# every legitimately-added assertion into a spurious failure and train people to
# edit the number without reading it. Derive the floor from a green run.
#
# Optional by design — ~21 sibling bash suites call this with no argument and
# must keep working. Suites that pass a floor opt into the stronger guarantee.
print_results() {
  local expected="${1:-}"
  echo "=== Results ==="
  echo "Passed: $PASS"
  echo "Failed: $FAIL"
  if (( SKIPPED > 0 )); then
    echo "Skipped: $SKIPPED"
  fi
  echo ""

  if [[ -n "$expected" ]]; then
    local ran=$(( PASS + FAIL + SKIPPED ))
    if [[ "$ran" -lt "$expected" ]]; then
      echo "ANTI-VACUITY FLOOR TRIPPED: $ran assertion(s) ran, expected at least $expected."
      echo "Assertions were skipped or the dispatch helpers were neutered — this is NOT a pass."
      exit 1
    fi
  fi

  if [[ $FAIL -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
  elif (( SKIPPED > 0 )); then
    # Honest summary: not "ALL TESTS PASSED" when timing invariants weren't
    # actually enforced. Reviewer P2 — closes silent-green-on-skipped-tests
    # footgun on PRs that conditionally gate timing tests behind CI=true.
    echo "ALL EXECUTED TESTS PASSED ($SKIPPED skipped)"
    exit 0
  else
    echo "ALL TESTS PASSED"
    exit 0
  fi
}

# Refuse before writing, rather than let an empty operand retarget a git write at whatever
# repository the caller happens to be standing in. `git -C ""` does NOT error — it silently
# operates on the current directory, which under TEST_GROUP=scripts is the developer's live
# worktree, whose `.git/config` is the SHARED file every worktree on the machine inherits.
#
# Rejects, beyond empty: bare `/` AND its aliases `//` and `/.` (a `/*` arm accepts all three, and
# `rm -rf "/"/*` is the worst outcome in this corpus — a one-character bypass of a stated
# rejection); any path containing `..`, which can resolve back inside the real repo; and
# /proc, /sys, /dev, because `/proc/self/cwd` is absolute, passes every other arm, and resolves
# to precisely "whatever repository the caller happens to be standing in".
#
# Still no `realpath`: it breaks on a symlinked /tmp, which this corpus uses. So a symlink to
# $HOME is ACCEPTED — stated here rather than left implied, because the arms above make this
# look like a containment check and it is not.
#
# The body below is the CANONICAL copy, asserted byte-for-byte against every other copy by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
