#!/usr/bin/env bash
# Meta-test: every CLI stub a hook test installs on PATH MUST inspect its own
# arguments.
#
# A stub that answers identically for any argv puts the fixture seam ABOVE the
# code under test: it cannot observe HOW the hook invokes the tool, so a
# malformed flag, a wrong subcommand, or a wrong positional argument all read as
# success. The test then reports green against a production path that has never
# executed.
#
# This guards the bug class fixed in #6775: pre-merge-auto-close-scan.sh built a
# `--repo` slug that kept the trailing `.git` on SSH remotes, so real `gh`
# answered with a GraphQL error and the PR body was never scanned. The stub in
# pre-merge-auto-close-scan.test.sh printed the body for ANY argv, so the arm was
# dark for 17 days while the suite reported 8/8 passed.
#
# Same shape and intent as hookeventname-coverage.test.sh, which made the
# "silently non-enforcing hook" class un-shippable after nine hooks shipped with
# it. This makes the "silently non-executing arm" class un-shippable.
#
# Scope: heredoc-written stubs for the CLIs hooks actually shell out to. The
# stub BODY is parsed, never the whole test file — a file-wide grep for `$1`
# false-positives on surrounding helper functions and would pass a blind stub.
#
# Known detector blind spots: a stub written via `printf`/`tee`/`install`, or to
# a variable path (`cat > "$STUB" <<…`). These are NOT silently tolerated — the
# pinned cardinality below turns any such miss into a loud failure, because a
# stub that drifts into an undetected shape drops the checked count. That pin is
# the general defense; the parser only has to be good enough to find the stubs
# that exist. Extending the parser is preferable to bumping the pin downward.
#
# Scope of the assertion: the stub body must REFERENCE argv. That is a
# necessary, not sufficient, condition for dispatching on it — a stub could log
# "$@" and still answer constantly. It is the cheap structural check; the
# semantic one belongs in the suite that owns the stub.

set -uo pipefail

HOOK_DIR="${STUB_ARGV_FIDELITY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SELF="$(basename "${BASH_SOURCE[0]}")"

# CLIs whose stubs must reference argv — the ones hooks in this directory
# actually shell out to. Widening this list is a one-line change.
STUB_CMDS="gh|jq|git"

# Expected number of stubs in the tree. Pinned, NOT a floor: a floor of 1 lets
# coverage silently collapse from N to 1 and still report PASS — a false-green
# guard against false greens. Bumping this is the intended edit when a stub is
# added; a DROP means the detector went blind and must be fixed, not lowered.
EXPECTED_STUBS="${STUB_ARGV_FIDELITY_EXPECTED:-4}"

fail=0
checked=0

# Emit one `<cmd>\t<line>\t<0|1>` record per heredoc-written stub in a test file.
# Tracks the heredoc delimiter so the body is bounded exactly, and reports
# whether that body references $1 / $@ / $* / ${1.
extract_stubs() {
  awk -v cmds="$STUB_CMDS" '
    !inbody {
      if ($0 ~ ("cat[[:space:]]*>[[:space:]]*\"?[^\"[:space:]]*/(" cmds ")\"?[[:space:]]*<<")) {
        name = $0; sub(/.*\//, "", name); sub(/".*/, "", name); sub(/[[:space:]].*/, "", name)
        # Strip LEADING whitespace before trimming at the first space. Without
        # it, `cat > "$B/gh" << '"'"'EOF'"'"'` (a space after `<<`, which is legal)
        # yields a delimiter of " EOF" -> the trailing-token sub deletes
        # everything -> delim becomes empty -> the close test never matches ->
        # the "body" runs to EOF and swallows every later stub. Measured: two
        # argv-blind stubs in one file reported PASS.
        delim = $0; sub(/.*<<-?/, "", delim); gsub(/['"'"'"]/, "", delim)
        sub(/^[[:space:]]+/, "", delim); sub(/[[:space:]].*/, "", delim)
        if (delim == "") next
        inbody = 1; argv = 0; start = NR
      }
      next
    }
    inbody {
      if ($0 ~ ("^[[:space:]]*" delim "[[:space:]]*$")) {
        printf "%s\t%d\t%d\n", name, start, argv
        inbody = 0
        next
      }
      # Comment lines are NOT evidence. A stub whose only mention of `$@` is a
      # docstring saying it inspects argv is precisely the blind stub this test
      # exists to reject — and a body-grep sees comments too
      # (`cq-assert-anchor-not-bare-token`). Skip them before matching.
      if ($0 ~ /^[[:space:]]*#/) next
      # `$1`, `${1`, `$@`, `$*` — including the `\$@` form used inside an
      # interpolating heredoc.
      if ($0 ~ /\$\{?[1@*]/) argv = 1
    }
    END { if (inbody) printf "%s\t%d\t%d\n", name, start, argv }
  ' "$1"
}

for t in "$HOOK_DIR"/*.test.sh; do
  [[ -f "$t" ]] || continue
  base="$(basename "$t")"
  [[ "$base" == "$SELF" ]] && continue
  while IFS=$'\t' read -r name line has_argv; do
    [[ -n "$name" ]] || continue
    checked=$((checked+1))
    if [[ "$has_argv" != "1" ]]; then
      echo "FAIL: $base:$line — the '$name' stub never references \$1/\$@/\$*."
      echo "      A stub that ignores argv cannot see how the hook invokes '$name',"
      echo "      so a malformed flag or wrong argument reads as success and the"
      echo "      test goes green against a path that never runs (#6775)."
      echo "      Dispatch on \"\$@\" — see the gh stub in pre-merge-auto-close-scan.test.sh."
      fail=1
    fi
  done < <(extract_stubs "$t")
done

# Cardinality pin. A sweep whose data source silently yields fewer members than
# it should still reports PASS on the ones it saw — the same false-green shape
# this test exists to catch. Pinning the count makes every detector blind spot
# loud instead of silent.
if [[ "$checked" -ne "$EXPECTED_STUBS" ]]; then
  echo "FAIL: inspected $checked CLI stub(s) under $HOOK_DIR, expected $EXPECTED_STUBS."
  if [[ "$checked" -lt "$EXPECTED_STUBS" ]]; then
    echo "      Coverage DROPPED. Either a stub was removed (lower the pin) or it"
    echo "      drifted into a shape the detector cannot see (fix the parser —"
    echo "      known blind spots: printf/tee/install writers, variable paths)."
    echo "      Do NOT lower the pin to make this pass without checking which."
  else
    echo "      A stub was added. Bump EXPECTED_STUBS to $checked."
  fi
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: all $checked hook-test CLI stub(s) reference argv."
fi

exit "$fail"
