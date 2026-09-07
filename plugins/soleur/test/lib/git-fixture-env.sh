#!/usr/bin/env bash
# The shell fixture git environment: the tripwire, and the builder, over ONE list.
#
# Shell sibling of plugins/soleur/test/lib/git-fixture-env.ts and tests/scripts/_git_fixture_env.py.
# Before this file existed the tripwire was inlined in test-helpers.sh and there was no shell
# builder at all, so every shell suite that created a fixture spelled the environment itself --
# #7849 counted four spellings of one idea, each free to drift. This file is the chokepoint: source
# it, and a suite gets both halves from one array.
#
# Sourcing this file ARMS THE TRIPWIRE as a side effect, exactly as sourcing test-helpers.sh did.
# That is deliberate: the guard has to fire before a suite can create anything, and a guard a caller
# must remember to invoke is a guard that will be forgotten.
#
# See #7833 (the process boundary this stands behind) and #7849 (this adoption).

# --- Guard 3 (#7833): fail-loud git-location tripwire ------------------------------------------
# A suite sourcing this file must not be running under an inherited git-location environment. In a
# linked worktree git exports GIT_DIR/GIT_INDEX_FILE to every hook as ABSOLUTE paths, and they
# override both a subprocess's working directory and `git -C` -- so a fixture's `git init`
# initialises nothing and its commits land on the developer's live branch.
#
# This ABORTS rather than unsetting. Scrubbing here would hide a broken entry point: the next suite
# that does not source this file would still be exposed, and the operator would never learn which
# runner invocation lacked the scrub. SOLEUR_GIT_TRIPWIRE_ALLOW=1 is the deliberate escape for a
# suite whose subject IS the inherited environment.

# The variables that redirect WHERE git reads and writes, or that make `git init` copy executable
# content into the fixture. ONE definition, read by BOTH the tripwire below and the builder further
# down -- that single-sourcing is the whole point of this file.
#
# Kept in lockstep with GIT_LOCATION_VARS in plugins/soleur/test/lib/git-fixture-env.ts and with
# GIT_LOCATION_VARS in tests/scripts/_git_fixture_env.py. That lockstep is ENFORCED, not asserted
# in prose: plugins/soleur/test/git-env-list-parity.test.sh derives all three and compares them.
readonly GIT_LOCATION_VARS=(
  GIT_DIR
  GIT_WORK_TREE
  GIT_INDEX_FILE
  GIT_COMMON_DIR
  GIT_OBJECT_DIRECTORY
  GIT_ALTERNATE_OBJECT_DIRECTORIES
  GIT_NAMESPACE
  GIT_TEMPLATE_DIR
  GIT_EXEC_PATH
)

# Name the SUITE in the announcement, not this library and not test-helpers.sh.
#
# The inlined version read `${BASH_SOURCE[1]}`, which was correct when the loop lived in
# test-helpers.sh sourced directly by a suite. Here the depth varies: a suite may source this file
# directly (frame 1) or reach it through test-helpers.sh (frame 2). A fixed index would name the
# wrong file in one of those two cases, and the whole value of the message is telling the operator
# WHICH entry point lacked the scrub. Walk instead, and skip our own infrastructure.
_soleur_git_reporting_frame() {
  local i
  for ((i = 1; i < ${#BASH_SOURCE[@]}; i++)); do
    case "${BASH_SOURCE[i]}" in
      */git-fixture-env.sh|*/test-helpers.sh) continue ;;
      "") continue ;;
      *) printf '%s' "${BASH_SOURCE[i]}"; return ;;
    esac
  done
  printf 'this suite'
}

if [[ "${SOLEUR_GIT_TRIPWIRE_ALLOW:-0}" == "1" ]]; then
  # Announce when the escape is taken. A switch that disarms a write-boundary guard with no trace
  # is the shape this guard exists to prevent, so a green run must still show it.
  printf '[git-tripwire] DISARMED by SOLEUR_GIT_TRIPWIRE_ALLOW=1 in %s\n' \
    "$(_soleur_git_reporting_frame)" >&2
else
  _soleur_git_leaked=""
  for _v in "${GIT_LOCATION_VARS[@]}"; do
    if [[ -n "${!_v:-}" ]]; then
      _soleur_git_leaked="${_soleur_git_leaked}  ${_v}=${!_v}"$'\n'
    fi
  done
  if [[ -n "$_soleur_git_leaked" ]]; then
    printf '\nFATAL: %s started with an inherited git-location environment:\n\n%s\n' \
      "$(_soleur_git_reporting_frame)" "$_soleur_git_leaked" >&2
    printf 'Fix the ENTRY POINT, by prefixing it with:\n\n  unset%s && <runner>\n\n' \
      "$(printf '%s' "$_soleur_git_leaked" | sed 's/=.*$//' | tr '\n' ' ' | sed 's/^/ /;s/  */ /g;s/ $//')" >&2
    exit 97
  fi
  unset _soleur_git_leaked _v
fi

# --- the builder --------------------------------------------------------------------------------
#
# git_fixture_env <fixture-dir>
#
# Exports, into the CALLING shell, the environment a fixture that WRITES needs. Mirrors
# gitFixtureEnv() in the TS sibling: a prefix sweep as the base, then the three things the sweep
# alone does not give -- an identity, a discovery ceiling, and config hermeticity.
#
# EXCLUSION BY PREFIX, NEVER BY NAME LIST. GIT_LOCATION_VARS above is for the TRIPWIRE and the
# entry-point scrub, which need concrete words to name and to unset. It is NOT the sweep: a name
# list as the sweep is what shipped four omissions in the TS sibling before review caught them.
#
# Returns non-zero WITHOUT EXPORTING ANYTHING if the ceiling would be unenforceable. A partial
# environment is the silent degradation this file exists to prevent -- it reads as protection.
git_fixture_env() {
  local fixture_dir="${1:-}"
  if [[ -z "$fixture_dir" ]]; then
    printf 'git_fixture_env: refusing to build an environment with no fixture directory.\n' >&2
    printf '  There is deliberately no default: a default of $TMPDIR yields a ceiling of "/",\n' >&2
    printf '  which git ignores, so the caller would silently lose the ceiling.\n' >&2
    return 2
  fi

  # Resolve the FIXTURE, then take its parent -- not the other way round. Resolving the LEXICAL
  # parent yields a ceiling naming a symlink parent while git getcwd reports the physical path, and
  # discovery escapes.
  # Refuse a non-absolute fixture directory outright rather than resolving it against $PWD.
  # Resolving would make the "ceiling is not absolute" arm below UNREACHABLE -- a guard that cannot
  # fire -- and it would silently bind the fixture to whatever directory the caller happened to be
  # in, which for a suite that changes directory is not the fixture it meant.
  local abs physical ceiling
  if [[ "$fixture_dir" != /* ]]; then
    printf 'git_fixture_env: fixture directory %s is not absolute.\n' "$fixture_dir" >&2
    printf '  Pass an absolute path (mktemp -d gives one); a relative path would be resolved\n' >&2
    printf '  against the current directory, which is not necessarily the fixture.\n' >&2
    return 2
  fi
  abs="$fixture_dir"
  if [[ -d "$abs" ]]; then
    physical="$(cd -P "$abs" 2>/dev/null && pwd -P)" || physical=""
  else
    physical="$abs"
  fi
  if [[ -z "$physical" ]]; then
    printf 'git_fixture_env: cannot resolve fixture directory %s\n' "$fixture_dir" >&2
    return 2
  fi
  ceiling="$(dirname "$physical")"

  # GIT_CEILING_DIRECTORIES is ":"-separated and git IGNORES every non-absolute entry, so a colon
  # anywhere splits it into fragments that are all discarded. "/" is ignored for the same reason.
  # Validate BEFORE the first export, so a refusal leaves the caller exactly as it was.
  case "$ceiling" in
    /) printf 'git_fixture_env: ceiling for %s computed as "/" -- git ignores it.\n' "$fixture_dir" >&2
       printf '  Pass a fixture at least two levels below "/".\n' >&2
       return 2 ;;
    /*) : ;;
    *) printf 'git_fixture_env: ceiling %s for %s is not absolute -- git ignores it.\n' \
         "$ceiling" "$fixture_dir" >&2
       return 2 ;;
  esac
  if [[ "$ceiling" == *:* ]]; then
    printf 'git_fixture_env: ceiling %s for %s contains ":" -- git splits it into fragments\n' \
      "$ceiling" "$fixture_dir" >&2
    printf '  that are all discarded, leaving the ceiling unenforceable.\n' >&2
    return 2
  fi

  # Validation passed. Only now may anything be exported.
  #
  # The sweep, by prefix. `${!GIT_@}` expands to the NAMES of every set variable beginning GIT_,
  # so this reaches members no list knows about -- including GIT_SSH, which a GIT_SSH_COMMAND name
  # rule structurally cannot match because the prefix is longer than the name.
  local _v
  for _v in ${!GIT_@}; do
    # Skip our own array. `${!GIT_@}` matches every SHELL variable with the prefix, not just the
    # environment, so it names GIT_LOCATION_VARS -- which is readonly, making `unset` emit
    # "cannot unset: readonly variable" to stderr on EVERY call. That is not cosmetic: converted
    # suites capture stderr, so it would corrupt exactly the diagnostics read when one fails.
    # Skipped by name rather than silenced with 2>/dev/null, so a genuinely unsettable inherited
    # GIT_ variable still reports.
    [[ "$_v" == "GIT_LOCATION_VARS" ]] && continue
    unset "$_v"
  done
  # Execution vectors git consults whose names carry NO GIT_ prefix, so the sweep cannot see them.
  # SSH_ASKPASS is the documented fallback when GIT_ASKPASS and core.askPass are unset: an
  # inherited value names a program git will run.
  unset SSH_ASKPASS

  export GIT_CEILING_DIRECTORIES="$ceiling"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL=/dev/null
  # GIT_CONFIG_GLOBAL replaces the config files but NOT the sibling XDG git files: attributes and
  # ignore are located independently of config content, so a developer `* text=auto` still rewrites
  # fixture bytes. Point XDG at the fixture, which holds no git/ subdirectory.
  export GIT_ATTR_NOSYSTEM=1
  export XDG_CONFIG_HOME="$physical/.soleur-fixture-xdg"
  export GIT_TERMINAL_PROMPT=0

  # Synthesized identity (`cq-test-fixtures-synthesized-only`). Required: the sweep removes
  # GIT_AUTHOR_*/GIT_COMMITTER_* and GIT_CONFIG_GLOBAL=/dev/null removes the developer own, so
  # without these the fixture first commit fails "Author identity unknown".
  export GIT_AUTHOR_NAME="Soleur Fixture"
  export GIT_AUTHOR_EMAIL="fixture@example.com"
  export GIT_COMMITTER_NAME="Soleur Fixture"
  export GIT_COMMITTER_EMAIL="fixture@example.com"

  # Signing, as a CONFIG OVERRIDE rather than a global replacement (deepen-plan D-1, measured).
  # GIT_CONFIG_GLOBAL=/dev/null and GIT_CONFIG_NOSYSTEM=1 do not reach a REPO-LOCAL
  # commit.gpgsign=true: the fixture then fails "gpg failed to sign the data". GIT_CONFIG_COUNT
  # entries are applied as command-line -c overrides, which outrank repo-local config, so this
  # covers the case the TS sibling handled only inside gitFixture() -- and every suite converted
  # under #7849 calls the BUILDER without that wrapper.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=commit.gpgsign
  export GIT_CONFIG_VALUE_0=false

  return 0
}
