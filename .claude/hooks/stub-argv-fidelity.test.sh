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

set -uo pipefail

HOOK_DIR="${STUB_ARGV_FIDELITY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SELF="$(basename "${BASH_SOURCE[0]}")"

# CLIs whose stubs must dispatch on argv. Widening this list is a one-line
# change; every stub in the tree already complies.
STUB_CMDS="gh|jq|git|doppler|curl"

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
        delim = $0; sub(/.*<<-?/, "", delim); gsub(/['"'"'"]/, "", delim); sub(/[[:space:]].*/, "", delim)
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

# Minimum-cardinality guard. A sweep whose data source silently yields nothing
# exits 0 with ZERO coverage and reads as a pass — the same false-green shape
# this test exists to catch, so it must not be reachable here.
if [[ "$checked" -lt 1 ]]; then
  echo "FAIL: no CLI stubs found under $HOOK_DIR — the detector matched nothing."
  echo "      Either the heredoc pattern drifted or the directory is wrong;"
  echo "      a sweep that inspects zero stubs is not a passing sweep."
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: all $checked hook-test CLI stub(s) dispatch on argv."
fi

exit "$fail"
