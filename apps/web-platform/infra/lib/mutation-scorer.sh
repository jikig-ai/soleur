# shellcheck shell=bash
# mutation-scorer.sh — the one row-verdict scorer for web-platform infra mutation batteries (#8855).
#
# Scope: web-platform infra mutation batteries only. Every consumer must also be listed in
# FILES_8855 in .claude/hooks/grep-q-pipe-guard.test.sh, which pins that no named file scores a
# row through a pipe.
#
# mutation_scorer_failed_on <log> <fail-line-ERE> <needle> [<needle>...]
#   return 0  iff EVERY needle is a substring of some line of <log> matching <fail-line-ERE>
#   return 1  otherwise (including "the log has no failure lines at all": grep rc 1)
#   exit 2    harness abort: no needle, an empty needle, or grep rc >= 2
#             (unreadable log / ERE that does not compile)
#
# Capture once, then match in bash — NO PIPE. A reader that stops at its first match leaves the
# producer writing into a closed pipe; under load the producer takes SIGPIPE, pipefail reports
# the pipeline failed, and a row that WAS killed on its named assertion scores MISROUTED (#8664).
# An empty needle is refused because a substring test on "" matches anything, which would score
# any failure at all as KILLED. Needles are matched quoted, so glob metacharacters and
# option-shaped strings (`--branch`) are literal.
#
# Call it in the battery's own shell. Inside $( … ), ( … ) or a pipeline stage, exit 2 leaves only
# that subshell; the caller must then treat rc 2 as an abort itself (zot-pull's `|| die` does).
# Sourced only. Sets no shell options and no file-scope variables; defines no `die`, because some
# consumers define their own and some define none.

_mutation_scorer_abort() {
  printf 'HARNESS ABORT: mutation_scorer: %s\n' "$*" >&2
  exit 2
}

mutation_scorer_failed_on() {
  (( $# >= 3 )) || _mutation_scorer_abort "usage: mutation_scorer_failed_on <log> <fail-line-ERE> <needle>... (got $# args)"
  local log="$1" ere="$2" needle fails rc=0
  shift 2
  for needle in "$@"; do
    [[ -n "$needle" ]] || _mutation_scorer_abort "empty needle for $log"
  done
  # `|| rc=$?`, not `; rc=$?`: a sourced lib cannot know whether its caller runs under errexit.
  fails="$(grep -E -- "$ere" "$log")" || rc=$?
  (( rc <= 1 )) || _mutation_scorer_abort "could not read $log or compile '$ere' (grep rc=$rc)"
  for needle in "$@"; do
    [[ "$fails" == *"$needle"* ]] || return 1
  done
  return 0
}
