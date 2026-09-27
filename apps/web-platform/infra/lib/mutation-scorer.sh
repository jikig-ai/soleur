# shellcheck shell=bash
# mutation-scorer.sh — the shared row-verdict scorer for web-platform infra mutation batteries (#8855).
#
# TEST HARNESS ONLY. Nothing delivers this file to a host; it lives under the infra root so that
# infra-validation.yml re-runs its consumers when it changes.
#
# Consumers: every file that sources this lib must be pinned in .claude/hooks/grep-q-pipe-guard.test.sh
# (FILES_8855, or FILES_8664 for the zot-pull battery). The guard derives the set of sourcing files and
# fails on any it does not pin, so a new consumer cannot join unpinned. mutation-scorer-consumers.test.sh
# runs every sourcing battery with MUTATION_SCORER_PROBE set and requires each to reach this function.
#
# mutation_scorer_failed_on <log> <fail-line-ERE> <needle> [<needle>...]
#   return 0  iff EVERY needle is a substring of some line of <log> matching <fail-line-ERE>
#   return 1  otherwise (including "the log has no failure lines at all": grep rc 1)
#   exit 2    harness abort: an empty fail-line ERE, no needle, an empty needle, a needle containing a newline (it could
#             match across two lines), or grep rc >= 2 (unreadable log / ERE that does not compile)
#
# Capture once, then match in bash — NO PIPE. A reader that stops at its first match leaves the
# producer writing into a closed pipe; under load the producer takes SIGPIPE, pipefail reports
# the pipeline failed, and a row that WAS killed on its named assertion scores MISROUTED (#8664).
# An empty needle is refused because a substring test on "" matches anything, which would score
# any failure at all as KILLED. Needles are matched quoted, so glob metacharacters and
# option-shaped strings (`--branch`) are literal. `grep -a` keeps a stray NUL byte in a guard log
# from turning the capture into "Binary file matches" and a present needle into a miss.
#
# Call it in the battery's own shell. Inside $( … ), ( … ) or a pipeline stage, exit 2 leaves only
# that subshell; the caller must then treat rc 2 as an abort itself (zot-pull's G4 row does it
# with `$( … ) || die`).
# Sourced only. Sets no shell options and no file-scope variables; defines no `die`, because some
# consumers define their own and some define none.

_mutation_scorer_abort() {
  printf 'HARNESS ABORT: mutation_scorer: %s\n' "$*" >&2
  exit 2
}

mutation_scorer_failed_on() {
  # Wire probe for mutation-scorer-consumers.test.sh: prove a battery REACHES this call. It can
  # only turn a run red (exit 86), never green, so an inherited value fails closed.
  if [[ -n "${MUTATION_SCORER_PROBE:-}" ]]; then
    printf 'MUTATION_SCORER_PROBE_REACHED %s\n' "$(caller 0)" >&2
    exit 86
  fi
  (( $# >= 3 )) || _mutation_scorer_abort "usage: mutation_scorer_failed_on <log> <fail-line-ERE> <needle>... (got $# args)"
  local log="$1" ere="$2" needle fails rc=0
  shift 2
  # An empty ERE selects EVERY line, silently widening "on a failure line" to "anywhere in the log".
  [[ -n "$ere" ]] || _mutation_scorer_abort "empty fail-line ERE for $log"
  for needle in "$@"; do
    [[ -n "$needle" ]] || _mutation_scorer_abort "empty needle for $log"
    [[ "$needle" != *$'\n'* ]] || _mutation_scorer_abort "needle for $log contains a newline"
  done
  # `|| rc=$?`, not `; rc=$?`: a sourced lib cannot know whether its caller runs under errexit.
  fails="$(grep -a -E -- "$ere" "$log")" || rc=$?
  (( rc <= 1 )) || _mutation_scorer_abort "could not read $log or compile '$ere' (grep rc=$rc)"
  for needle in "$@"; do
    [[ "$fails" == *"$needle"* ]] || return 1
  done
  return 0
}
