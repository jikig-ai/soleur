#!/usr/bin/env bash
# Persist the rehearsal skip monitor's consecutive-TRANSIENT streak in a workflow artifact.
#
# WHY NOT THE ACTIONS CACHE. The streak used to round-trip through actions/cache. The release
# pipeline's BuildKit gha export writes about 1.2 GB per release and keeps the repository over its
# 10 GB cache cap, and GitHub evicts least-recently-accessed first, so a 192-byte entry read once a
# day was always the loser and the round-trip assertion was red most days. An artifact has an
# explicit retention and is outside the cache quota. See ADR-296.
#
# Subcommands (the workflow wires them in this order: fetch, probe, seal, assert, upload):
#   fetch  find the newest eligible prior artifact, validate it, write its value to $STREAK_FILE
#          and emit `matched=true|false` to $GITHUB_OUTPUT. An UNREADABLE store (listing failed,
#          not JSON) always exits 1: it is not "no prior state". With BOOTSTRAP=true a corrupt
#          NEWEST artifact is discarded (the documented reseed path); without it, it exits 1.
#   seal   after the probe: make $STREAK_FILE an explicit number. A real verdict clears the file,
#          so absence becomes 0 -- but a TRANSIENT verdict must have left a value >= 1, otherwise
#          the probe's silent write was lost and sealing 0 would reset the streak.
#   assert exit 1 unless fetch matched a prior streak or this is an explicit BOOTSTRAP run.
#
# Selection is fail-closed. Artifacts are repository-scoped, not ref-scoped, and a fork
# pull_request run is listed under this repository with a fork-controlled head_branch, so the
# head repository must equal this repository, the run must be on STREAK_BRANCH, the size is
# bounded, the archive must hold exactly one member named `streak`, and the value must be 1-6
# digits. The log never carries the raw artifact value: a line starting `::stop-commands::` or
# `::error::` would be interpreted by the runner.
#
# Required env (fetch): GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_ID GITHUB_RUN_ID
# STREAK_ARTIFACT_NAME STREAK_BRANCH STREAK_FILE GITHUB_OUTPUT. Optional: BOOTSTRAP GITHUB_REF_NAME
# GITHUB_ACTOR.

set -uo pipefail

# XTRACE CREDENTIAL REFUSAL (#7797). `set -x` echoes every expanded command, including the `gh`
# calls that carry GH_TOKEN, into a log that lands in a public Actions run.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

die() { printf '::error::%s\n' "$1"; exit 1; }

# A value is only ever a decimal counter. Validated with a bash regex (not grep -E, which
# passes "1\nabc" line by line) and forced to base 10 (a leading zero is octal in $(( ))).
valid_number() { [[ "${1-}" =~ ^[0-9]{1,6}$ ]]; }

cmd_fetch() {
  : "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_REPOSITORY_ID:?}" "${GITHUB_RUN_ID:?}"
  : "${STREAK_ARTIFACT_NAME:?}" "${STREAK_BRANCH:?}" "${STREAK_FILE:?}" "${GITHUB_OUTPUT:?}"
  local bootstrap=false
  [ "${BOOTSTRAP:-}" = "true" ] && bootstrap=true
  [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "GITHUB_REPOSITORY has an unexpected shape"
  [[ "$STREAK_ARTIFACT_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "STREAK_ARTIFACT_NAME has an unexpected shape"
  [[ "$GITHUB_REPOSITORY_ID" =~ ^[0-9]+$ ]] || die "GITHUB_REPOSITORY_ID is not numeric"
  [[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ ]] || die "GITHUB_RUN_ID is not numeric"

  mkdir -p "$(dirname "$STREAK_FILE")" || die "could not create the state directory"
  local tmp; tmp=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/streak-fetch.XXXXXXXX") || die "could not create a scratch directory"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local actor="${GITHUB_ACTOR:-unknown}"
  [[ "$actor" =~ ^[A-Za-z0-9-]{1,39}$ ]] || actor=unknown
  if [ "$bootstrap" = true ]; then
    printf '::notice::bootstrap by %s: a missing or corrupt prior streak is permitted for this run only\n' "$actor"
  fi
  if [ "${GITHUB_REF_NAME:-$STREAK_BRANCH}" != "$STREAK_BRANCH" ]; then
    printf '::notice::ref %s is not %s: state is read from %s and is NOT written back by this run\n' \
      "${GITHUB_REF_NAME//[^A-Za-z0-9._\/-]/?}" "$STREAK_BRANCH" "$STREAK_BRANCH"
  fi

  # 1. List. The exact-name filter only: the repo-wide listing is not used. A failed or malformed
  #    listing is an unreadable store, never "no prior artifact", under either BOOTSTRAP value.
  local list_rc=0
  gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/artifacts?name=${STREAK_ARTIFACT_NAME}&per_page=100" \
    > "$tmp/list.raw" 2> "$tmp/list.err" || list_rc=$?
  [ "$list_rc" -eq 0 ] || die "artifact listing failed (gh exited ${list_rc}); the streak store is unreadable, which is not the same as empty"
  [ -s "$tmp/list.raw" ] || die "artifact listing returned an empty body; the streak store is unreadable"
  jq -s '[.[].artifacts[]]' "$tmp/list.raw" > "$tmp/list.json" 2> "$tmp/jq.err" \
    || die "artifact listing was not JSON with an artifacts array; the streak store is unreadable"
  jq -e 'type == "array"' "$tmp/list.json" > /dev/null 2>&1 \
    || die "artifact listing did not reduce to an array; the streak store is unreadable"

  # 2. Select, fail-closed: unexpired, small, from STREAK_BRANCH, from THIS repository (not a fork),
  #    from a run strictly before this one (excludes this run's own earlier attempt, and makes a
  #    re-run of an older run read its predecessor), newest by workflow_run.id.
  local art_id
  art_id=$(jq -r --arg branch "$STREAK_BRANCH" --argjson repo "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" '
      [ .[] | select(
            (.expired == false)
        and ((.size_in_bytes // 1000000000) <= 4096)
        and ((.workflow_run.head_branch // "") == $branch)
        and ((.workflow_run.repository_id // -1) == $repo)
        and ((.workflow_run.head_repository_id // 0) == $repo)
        and ((.workflow_run.id | type) == "number")
        and ((.workflow_run.id // 0) < $run)
        and ((.id | type) == "number")
      ) ] | sort_by(.workflow_run.id) | last | .id // empty' "$tmp/list.json" 2> /dev/null) \
    || die "artifact selection failed"
  if [ -z "$art_id" ]; then
    printf '::notice::no eligible prior streak artifact\n'
    printf 'matched=false\n' >> "$GITHUB_OUTPUT"
    return 0
  fi
  [[ "$art_id" =~ ^[0-9]+$ ]] || die "selected artifact id is not numeric"

  # 3. Download and validate. Anything wrong with the NEWEST eligible artifact is fatal, except
  #    under BOOTSTRAP, where it is discarded so a poisoned artifact can never wedge the monitor.
  discard() { # $1 = reason (fixed text only, never artifact content)
    if [ "$bootstrap" = true ]; then
      printf '::warning::discarding the newest streak artifact (%s); bootstrap run\n' "$1"
      printf 'matched=false\n' >> "$GITHUB_OUTPUT"
      return 0
    fi
    die "the newest streak artifact is unusable (${1}); dispatch with bootstrap=true to reseed"
  }
  local dl_rc=0
  timeout 60 gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts/${art_id}/zip" \
    > "$tmp/a.zip" 2> "$tmp/dl.err" || dl_rc=$?
  [ "$dl_rc" -eq 0 ] || { discard "download failed, exit ${dl_rc}"; return $?; }
  unzip -Z1 "$tmp/a.zip" > "$tmp/members" 2> /dev/null || { discard "not a readable archive"; return $?; }
  printf 'streak\n' > "$tmp/members.want"
  cmp -s "$tmp/members" "$tmp/members.want" || { discard "archive members are not exactly one file named streak"; return $?; }
  unzip -p "$tmp/a.zip" streak > "$tmp/val.raw" 2> /dev/null || { discard "member unreadable"; return $?; }
  local v
  v=$(head -c 32 "$tmp/val.raw")
  if ! valid_number "$v"; then
    printf '::notice::malformed streak value (length %s, shape %s)\n' "${#v}" \
      "$(printf '%s' "$v" | LC_ALL=C tr -c '[:alnum:]' '?' | head -c 16)"
    discard "malformed value"
    return $?
  fi

  printf '%s' "$((10#$v))" > "$STREAK_FILE" || die "could not write the state file"
  printf 'streak artifact %s restored from a prior run\n' "$art_id"
  printf 'matched=true\n' >> "$GITHUB_OUTPUT"
}

cmd_seal() {
  : "${STREAK_FILE:?}"
  local verdict="${VERDICT:-}"
  mkdir -p "$(dirname "$STREAK_FILE")" || die "could not create the state directory"
  local v=""
  [ -f "$STREAK_FILE" ] && v=$(tr -d '\n' < "$STREAK_FILE")
  case "$verdict" in
    pass|fail|broken)
      # A real verdict clears the probe's file; absence is a 0, not a lost write.
      if [ -z "$v" ]; then v=0; fi
      valid_number "$v" || die "the state file holds a non-numeric value after a '${verdict}' verdict"
      ;;
    transient)
      # The probe MUST have written an incremented value; its write is `2>/dev/null || true`, so
      # a lost increment would otherwise be sealed as 0 and silently reset the streak.
      valid_number "$v" || die "verdict transient but the state file is missing, empty or non-numeric: the probe's increment was lost"
      [ "$((10#$v))" -ge 1 ] || die "verdict transient but the state file holds 0: the probe's increment was lost"
      ;;
    *) die "unknown or empty verdict; refusing to seal" ;;
  esac
  printf '%s' "$((10#$v))" > "$STREAK_FILE" || die "could not write the sealed state file"
  printf 'streak sealed at %s (verdict %s)\n' "$((10#$v))" "$verdict"
}

cmd_assert() {
  : "${STREAK_FILE:?}"
  local matched="${MATCHED:-}" bootstrap="${BOOTSTRAP:-}"
  local v=""
  [ -f "$STREAK_FILE" ] && v=$(tr -d '\n' < "$STREAK_FILE")
  valid_number "$v" || die "the sealed streak state is missing or non-numeric"
  if [ "$matched" != "true" ] && [ "$bootstrap" != "true" ]; then
    die "the streak store returned no prior generation. The consecutive-TRANSIENT escalation cannot fire, so a permanently broken probe is indistinguishable from a healthy quiet window. Dispatch with bootstrap=true to reseed."
  fi
  printf 'streak state: restored=%s value=%s\n' "${matched:-false}" "$((10#$v))"
}

case "${1-}" in
  fetch)  cmd_fetch ;;
  seal)   cmd_seal ;;
  assert) cmd_assert ;;
  *) printf 'usage: %s fetch|seal|assert\n' "$0" >&2; exit 2 ;;
esac
