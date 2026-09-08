#!/usr/bin/env bash
# (#7873) Every declaration of a Better Stack ingest host agrees with the others
# that name the SAME source.
#
# THE POPULATION IS DERIVED, NEVER LISTED. The first version of this suite carried
# a hand-written six-file array and an `EXPECTED_SITES=6` guard. Both were wrong:
# a repo-wide grep finds TWELVE declaring files, and the six named modelled ONE of
# the fleet's TWO sources without saying so. A hand-maintained population is the
# stale snapshot that is the same defect one level up (AP-023) -- and a parity
# guard whose population is smaller than the real one is worse than none, because
# it reports agreement it never checked.
#
# THE FLEET HAS TWO SOURCES, DELIBERATELY. `s2457081.eu-fsn-3` is the shared
# control/inngest source; `s2734275.eu-central-1a` is the git-data source
# (apps/web-platform/infra/git-data.tf declares it on purpose). So the property is
# NOT "one host repo-wide" -- it is "every declaration naming source N agrees on
# N's full host". A single-host assertion would have failed on a correct tree.
#
# This asserts PARITY, not a pin: it does not care WHICH host a source uses, only
# that one answer is given everywhere. A legitimate migration stays a single edit.
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || { printf '[FATAL] cannot cd to repo root\n' >&2; exit 2; }

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

# Positive control (ADR-193): drive both helpers once and refuse to continue
# unless both counters move. Reported with printf + exit, never through the
# helpers it backstops.
_p=$PASS; _f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS - _p)) -ne 1 ] || [ $((FAIL - _f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2
  exit 1
fi
PASS=$_p; FAIL=$_f

HOST_RE='s[0-9]+\.[a-z0-9-]+\.betterstackdata\.com'

# Production declarations only. Excluding tests/fixtures/knowledge-base is not a
# convenience: those legitimately carry synthetic and historical hosts, and a
# suite that failed on its own fixtures could not be written.
# `--untracked` because `git grep` is INDEX-scoped by default: a declaring file
# the developer just wrote is invisible until staged, so a local or pre-commit
# run would certify parity over a population that excludes the new file.
mapfile -t FILES < <(git grep -l --untracked -E "$HOST_RE" -- . \
  ':!knowledge-base' ':!tests' ':!*.test.sh' ':!scripts/fixtures' | sort)

# A derived population can be empty for reasons that have nothing to do with the
# property (a broken regex, a git failure, a bad CWD) -- and empty would otherwise
# report a clean sweep. The floor is ABSOLUTE and ratchets upward.
MIN_FILES=12
if [ "${#FILES[@]}" -lt "$MIN_FILES" ]; then
  printf '[FATAL] derived only %s declaring file(s), floor is %s -- refusing to certify parity over a population this small (broken grep? wrong CWD?)\n' \
    "${#FILES[@]}" "$MIN_FILES" >&2
  exit 1
fi
pass "derived ${#FILES[@]} declaring file(s) from the tree (floor ${MIN_FILES})"

# Partition every declaration by SOURCE ID, then require each partition to agree.
declare -A SEEN_HOSTS=()
declare -A SEEN_WHERE=()
for f in "${FILES[@]}"; do
  hosts="$(grep -vE '^[[:space:]]*#' "$f" | grep -ohE "$HOST_RE" | sort -u || true)"
  if [ -z "$hosts" ]; then
    # Every host in this file sits in a comment. Not a drift signal on its own.
    continue
  fi
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    sid="${h%%.*}"
    SEEN_HOSTS["$sid"]="${SEEN_HOSTS[$sid]:-}${h}
"
    SEEN_WHERE["$sid"]="${SEEN_WHERE[$sid]:-}${f} "
  done <<< "$hosts"
done

if [ "${#SEEN_HOSTS[@]}" -eq 0 ]; then
  fail "no source partitions were built from ${#FILES[@]} file(s) -- the extraction is broken"
fi

# PARTITIONING ALONE IS VACUOUS ON A RENAME, and that is not hypothetical -- it
# survived this suite's own mutation battery. Renaming one file's `s2457081` to
# `s9999999` creates a NEW partition holding exactly one declaration, which is
# internally consistent by construction: 1-of-1 is indistinguishable from
# all-of-1. So the partition check must be paired with (a) a closed set of known
# source ids and (b) an absolute floor per source. Both ratchet upward.
KNOWN_SIDS="s2457081 s2734275"
# Ratcheted to the MEASURED population. At 6/3/10 the floors carried a unit of
# slack, so re-pointing one file from s2457081 to s2734275 -- a silent misroute,
# and verbatim the case the floor's own message names -- left both partitions
# above their floors and the suite green.
declare -A SID_FLOOR=( [s2457081]=7 [s2734275]=3 )

for sid in $(printf '%s\n' "${!SEEN_HOSTS[@]}" | sort); do
  distinct="$(printf '%s' "${SEEN_HOSTS[$sid]}" | sort -u | grep -c . || true)"
  n_decl="$(printf '%s' "${SEEN_HOSTS[$sid]}" | grep -c . || true)"
  if [ "$distinct" -eq 1 ]; then
    pass "source ${sid}: ${n_decl} declaration(s) agree on $(printf '%s' "${SEEN_HOSTS[$sid]}" | sort -u | head -1)"
  else
    fail "source ${sid} is split across ${distinct} hosts: $(printf '%s' "${SEEN_HOSTS[$sid]}" | sort -u | tr '\n' ' ')-- in: ${SEEN_WHERE[$sid]}"
  fi

  case " $KNOWN_SIDS " in
    *" $sid "*) : ;;
    *) fail "unknown ingest source ${sid} appeared in: ${SEEN_WHERE[$sid]}-- a source id was renamed, or a third source was added without updating KNOWN_SIDS" ;;
  esac

  floor="${SID_FLOOR[$sid]:-0}"
  if [ "$n_decl" -lt "$floor" ]; then
    fail "source ${sid} has ${n_decl} declaration(s), floor is ${floor} -- a declaration was removed or re-pointed at another source"
  fi
done

# Every KNOWN source must still be declared somewhere. A source that vanishes
# entirely would otherwise pass: the loop above only walks what it found.
for sid in $KNOWN_SIDS; do
  if [ -z "${SEEN_HOSTS[$sid]:-}" ]; then
    fail "known ingest source ${sid} has NO declaration anywhere in the tree"
  fi
done

# scripts/lib/betterstack-sources.sh is the canonical declaration and builds its
# hosts by INTERPOLATION (`s${BS_CONTROL_SOURCE_ID}.…`), so the literal grep above
# is structurally unable to see it. Changing a source id there would split the
# fleet with every assertion above still green. Bind the ids to the partitions.
LIB="scripts/lib/betterstack-sources.sh"
if [ ! -f "$LIB" ]; then
  fail "canonical source declaration $LIB is missing"
else
  for v in BS_CONTROL_SOURCE_ID BS_GIT_DATA_SOURCE_ID; do
    id="$(grep -E "^${v}=" "$LIB" | head -1 | sed -E 's/^[^=]+="?([0-9]+)"?.*/\1/')"
    if [ -z "$id" ]; then
      fail "$LIB does not declare $v as a bare numeric id"
    elif [ -n "${SEEN_HOSTS[s${id}]:-}" ]; then
      pass "$v=$id is the source the tree's literal declarations name (s${id})"
    else
      fail "$LIB declares $v=$id but NO literal declaration in the tree names s${id} -- the canonical id and the fleet have diverged"
    fi
  done
fi

# ANTI-VACUITY FLOOR. MIN_FILES above bounds the POPULATION; this bounds the
# VERDICTS. Emitted with printf + exit directly -- never through the helpers it
# backstops, which the same edit could disarm.
MIN_ASSERTIONS=5
_total=$((PASS + FAIL))
if [ "$_total" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] betterstack-ingest-parity ran only %s assertion(s), floor is %s -- a skipped loop reports clean\n' \
    "$_total" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf 'betterstack-ingest-parity: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
