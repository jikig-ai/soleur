# shellcheck shell=bash
# affected-glob.sh — `_affected_glob_split`, the single bash shape classifier for
# `glob:` declared-edge payloads (#10198; the helper extraction deferred from #9813
# to "the next grammar touch" — this issue is that touch).
#
# THE DOCTRINE. The `glob:<literal-head>/<glob-tail>` declared-entry kind (ADR-242
# decision 22) classifies a payload into exactly one of:
#
#   literal   — no metachar at all: the mint recurses it as a plain path entry
#               (a `glob:` spelling of a literal path, not a pattern).
#   dir       — well-formed, directory-anchored: a metachar-free head that is a
#               clean repo-relative prefix ending in `/`, and a tail that carries
#               `*` and never ends in `/`. Mints `^glob:<pattern>` (or degrades
#               to `^<head>/` when the head dir is absent on disk).
#   root      — well-formed, root-anchored (#10198): a metachar-free head with
#               no `/` at all (empty heads allowed), and a tail with `*` and no
#               `/`. Mints `^glob:<pattern>` with no `-d` probe — the repo root
#               is always present. Matches only DIR-LESS diff lines.
#   malformed — every other shape: degrades WIDER (the mint's `^glob:<verbatim>`
#               always-match edge, the hit arm's return-0, the covers() oracle's
#               always-cover) except at the census, where it is a static RED —
#               and at GLOBENT, where it stays `semantic` (the closed grammar).
#
# malformed-shape invariant — ONE doctrine, ONE classifier: the mint arms
# `_affected_add_edge`/`_affected_add_declared_edge` (#9441's -e-less declared
# twin) and the hit arm `_diff_edge_hit` in scripts/test-all.sh,
# the census arm in scripts/lint-orphan-test-suites.sh, and the covers() oracle
# in scripts/test-affected-kb-consumers.test.sh must classify a shape
# identically; GLOBENT (the registration-only classifier's awk regex) is a
# deliberate SUPERSET — admission can only widen, never narrow. The true site
# count is wider: scripts/ci-pr-affected-replay.py's edge_hit() is a Python
# MIRROR of the hit arm (bash-vs-python parity pinned by a differential row),
# and materialise() in scripts/lint-orphan-test-suites.test.sh splits payloads
# test-side. The four bash sites plus materialise() classify through THIS
# function; the Python and awk mirrors keep the same verdicts by inspection —
# a drift there is what the differential and k5/Rg fixtures exist to catch.
#
# INTERFACE. `_affected_glob_split <payload>` where <payload> is the text AFTER
# `glob:` (every call site strips the prefix first). Emits globals, never
# stdout (the _NP idiom — a command-substitution call would fork once per
# edge):
#
#   _AGS_CLASS  literal | dir | root | malformed
#   _AGS_WHY    the verdict's reason token:
#                 literal            — the class above (no metachar)
#                 dir                — the class above (well-formed)
#                 root               — the class above (well-formed)
#                 root-tail-slash    — a / in a root-anchored tail (unmatchable)
#                 charset            — a byte outside the grammar charset
#                                      [-A-Za-z0-9_./*-] (but not ? or [;
#                                      `:` is deliberately OUT — the verbatim-
#                                      mint degrade relies on ^glob:glob:<p>
#                                      classifying malformed on it)
#                 qbracket           — a ? or [ (outside the grammar)
#                 head-not-reporel   — head absolute / ./ ../ / holds // /./ /../
#                 head-mid-slash     — head is not /-terminated
#                 tail-trailing-slash— tail ends in / (no path can match it)
#                 tail-no-star       — tail carries no *
#   _AGS_HEAD   the leading metachar-free run (`${payload%%[*?[]*}`)
#   _AGS_TAIL   the rest of the payload ("" for literal) — internal to the
#               dispatch today; retained in the contract for the census's
#               reason-map and any future tail-aware consumer
#
# rc is ALWAYS 0: malformed is data, never a failure arm — callers run under
# `set -e`/`&&` chains and an rc-1 classifier would read as a crash, not a
# verdict. Bash 3.2-safe: case/[[ ]]/parameter expansion only.
_affected_glob_split() { # <payload> — classify the text AFTER `glob:`
  local _s="$1"
  _AGS_HEAD="${_s%%[*?[]*}"          # longest leading metachar-free run
  _AGS_TAIL=""
  _AGS_CLASS=""
  _AGS_WHY=""
  case "$_s" in
    *[\*?[]*) : ;;                  # a metachar is present — the glob grammar applies
    *) _AGS_CLASS=literal; _AGS_WHY=literal; return 0 ;;
  esac
  _AGS_TAIL="${_s#"$_AGS_HEAD"}"    # quoted pattern — a head can't glob inside #
  case "$_s" in
    *[?[]*) _AGS_CLASS=malformed; _AGS_WHY=qbracket; return 0 ;;
    *[!A-Za-z0-9_./*-]*) _AGS_CLASS=malformed; _AGS_WHY=charset; return 0 ;;
  esac
  case "$_AGS_HEAD" in
    /*|./*|../*|*"//"*|*"/./"*|*"/../"*)
      _AGS_CLASS=malformed; _AGS_WHY=head-not-reporel; return 0 ;;
    */)
      case "$_AGS_TAIL" in
        */) _AGS_CLASS=malformed; _AGS_WHY=tail-trailing-slash; return 0 ;;
        *\**) _AGS_CLASS=dir; _AGS_WHY=dir; return 0 ;;
        *) _AGS_CLASS=malformed; _AGS_WHY=tail-no-star; return 0 ;;
      esac
      ;;
    */*) _AGS_CLASS=malformed; _AGS_WHY=head-mid-slash; return 0 ;;
    *)
      # /-free head (empty included) — ROOT-ANCHORED (#10198): the pattern
      # matches only dir-less diff lines. A /-bearing tail can never match one.
      case "$_AGS_TAIL" in
        */*) _AGS_CLASS=malformed; _AGS_WHY=root-tail-slash; return 0 ;;
        *\**) _AGS_CLASS=root; _AGS_WHY=root; return 0 ;;
        *) _AGS_CLASS=malformed; _AGS_WHY=tail-no-star; return 0 ;;
      esac
      ;;
  esac
}
