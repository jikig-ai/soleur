#!/usr/bin/env bash
# Persist the rehearsal skip monitor's consecutive-TRANSIENT streak in a workflow artifact
# (the Actions cache was evicted daily; see ADR-296 for the measured cause and the alternatives).
#
# Subcommands (the workflow wires them in this order: fetch, probe, seal, assert, upload):
#   fetch  find the newest eligible prior artifact, validate it, write its value to $STREAK_FILE,
#          emit `matched=true|false` and `prior=<n>` to $GITHUB_OUTPUT. An UNREADABLE store (the
#          listing or the download failed) always exits 1: it is not "no prior state". With
#          BOOTSTRAP=true a corrupt NEWEST artifact is discarded (the documented reseed path).
#   seal   after the probe: make $STREAK_FILE an explicit number, verdict-aware. The probe's own
#          write is `2>/dev/null || true`, so a TRANSIENT verdict must have moved the streak to
#          exactly RESTORED+1 (the value fetch restored); anything else means the increment was lost.
#   assert exit 1 unless fetch matched a prior streak or this is an explicit BOOTSTRAP run. A red assert
#          on an empty store still lets the upload publish this run's value, so the next run self-heals.
#
# Selection is fail-closed. Artifacts are repository-scoped, not ref-scoped, and a fork
# pull_request run is listed under this repository with a fork-controlled head_branch, so the head
# repository must equal this repository, the run must be on STREAK_BRANCH, the size is bounded, the
# archive must hold exactly one member named `streak`, the member is read through a bounded pipe
# (the 4096-byte limit is on the COMPRESSED archive), and the value must be 1-6 digits. The log
# never carries artifact content: a line starting `::stop-commands::` or `::error::` would be
# interpreted by the runner.
#
# Required env (fetch): GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_ID GITHUB_RUN_ID
# STREAK_ARTIFACT_NAME STREAK_BRANCH STREAK_FILE GITHUB_OUTPUT. Optional: BOOTSTRAP GITHUB_ACTOR
# STREAK_LIST_TIMEOUT (seconds, 1 or more, default 120). seal: STREAK_FILE VERDICT RESTORED (the `prior`
# output of fetch). assert: STREAK_FILE
# MATCHED BOOTSTRAP.

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

# The repo-wide path guard (byte-identical to every tracked copy; see the fixture-relative ratchet): it
# refuses an empty, relative, `..`-bearing or synthetic-fs operand before anything is written to it.
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

# A value is only ever a decimal counter. Validated with a bash regex (not grep -E, which
# passes "1\nabc" line by line) and forced to base 10 (a leading zero is octal in $(( ))).
valid_number() { [[ "${1-}" =~ ^[0-9]{1,6}$ ]]; }

# Contents of the state file with no trailing newline; tr is NOT used so "1\n2" cannot collapse to 12.
read_state() { if [ -f "$STREAK_FILE" ]; then cat "$STREAK_FILE"; fi; }

cmd_fetch() {
  : "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_REPOSITORY_ID:?}" "${GITHUB_RUN_ID:?}"
  : "${STREAK_ARTIFACT_NAME:?}" "${STREAK_BRANCH:?}" "${STREAK_FILE:?}" "${GITHUB_OUTPUT:?}"
  local bootstrap=false
  [ "${BOOTSTRAP:-}" = "true" ] && bootstrap=true
  [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "GITHUB_REPOSITORY has an unexpected shape"
  [[ "$STREAK_ARTIFACT_NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "STREAK_ARTIFACT_NAME has an unexpected shape"
  # A non-numeric id handed to jq --argjson would compare below every artifact id.
  [[ "$GITHUB_REPOSITORY_ID" =~ ^[0-9]+$ ]] || die "GITHUB_REPOSITORY_ID is not numeric"
  [[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ ]] || die "GITHUB_RUN_ID is not numeric"
  assert_fixture_dir "$STREAK_FILE"
  local list_timeout="${STREAK_LIST_TIMEOUT:-120}"
  # `timeout 0` means no limit, which would recreate the hang this bound exists to close.
  [[ "$list_timeout" =~ ^[1-9][0-9]{0,3}$ ]] || die "STREAK_LIST_TIMEOUT must be 1 to 9999 seconds"

  mkdir -p "$(dirname "$STREAK_FILE")" || die "could not create the state directory"
  local tmp; tmp=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/streak-fetch.XXXXXXXX") || die "could not create a scratch directory"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  assert_fixture_dir "$tmp"

  local actor="${GITHUB_ACTOR:-unknown}"
  [[ "$actor" =~ ^[A-Za-z0-9-]{1,39}$ ]] || actor=unknown
  if [ "$bootstrap" = true ]; then
    printf '::notice::bootstrap by %s: a missing or corrupt prior streak is permitted for this run only\n' "$actor"
  fi

  # 1. List. The exact-name filter only; the repo-wide listing is not used. A failed, hung or
  #    malformed listing is an unreadable store, never "no prior artifact", under either BOOTSTRAP value.
  local list_rc=0
  timeout "$list_timeout" gh api --paginate "repos/${GITHUB_REPOSITORY}/actions/artifacts?name=${STREAK_ARTIFACT_NAME}&per_page=100" \
    > "$tmp/list.raw" 2> /dev/null || list_rc=$?
  [ "$list_rc" -ne 124 ] || die "artifact listing timed out after ${list_timeout}s; the streak store is unreadable"
  [ "$list_rc" -eq 0 ] || die "artifact listing failed (gh exited ${list_rc}); the streak store is unreadable, which is not the same as empty"
  [ -s "$tmp/list.raw" ] || die "artifact listing returned an empty body; the streak store is unreadable"
  jq -s '[.[].artifacts[]]' "$tmp/list.raw" > "$tmp/list.json" 2> /dev/null \
    || die "artifact listing was not JSON with an artifacts array; the streak store is unreadable"

  # 2. Select, fail-closed: unexpired, small (a missing size reads as huge), from STREAK_BRANCH, from
  #    THIS repository (not a fork), from a run strictly before this one (excludes this run's own
  #    earlier attempt; makes a re-run of an older run read its predecessor), newest by run id.
  local art_id
  art_id=$(jq -r --arg branch "$STREAK_BRANCH" --argjson repo "$GITHUB_REPOSITORY_ID" --argjson run "$GITHUB_RUN_ID" '
      [ .[] | select(
            (.expired == false)
        and ((.size_in_bytes // 1000000000) <= 4096)
        and (.workflow_run.head_branch == $branch)
        and (.workflow_run.repository_id == $repo)
        and (.workflow_run.head_repository_id == $repo)
        and ((.workflow_run.id | type) == "number")
        and (.workflow_run.id < $run)
      ) ] | sort_by([.workflow_run.id, .id]) | last | .id // empty' "$tmp/list.json" 2> /dev/null) \
    || die "artifact selection failed"
  if [ -z "$art_id" ]; then
    printf '::notice::no eligible prior streak artifact\n'
    printf 'matched=false\nprior=0\n' >> "$GITHUB_OUTPUT"
    return 0
  fi
  [[ "$art_id" =~ ^[0-9]+$ ]] || die "selected artifact id is not numeric"

  # 3. Download and validate. A failed DOWNLOAD is an unreadable store and always fatal. Anything
  #    wrong with the CONTENT of the newest eligible artifact is fatal too, except under BOOTSTRAP,
  #    where it is discarded so a poisoned artifact can never wedge the monitor.
  local dl_rc=0
  timeout 60 gh api "repos/${GITHUB_REPOSITORY}/actions/artifacts/${art_id}/zip" \
    > "$tmp/a.zip" 2> /dev/null || dl_rc=$?
  [ "$dl_rc" -eq 0 ] || die "artifact download failed (exit ${dl_rc}); the streak store is unreadable"

  discard() { # $1 = reason (fixed text only, never artifact content)
    if [ "$bootstrap" = true ]; then
      printf '::warning::discarding the newest streak artifact (%s); bootstrap run\n' "$1"
      printf 'matched=false\nprior=0\n' >> "$GITHUB_OUTPUT"
      return 0
    fi
    die "the newest streak artifact is unusable (${1}); dispatch with bootstrap=true to reseed"
  }
  # Repeated on purpose: the repo's fixture-relative ratchet ends a guard's window at the nested
  # function definition above, so the redirects below need their own guard.
  assert_fixture_dir "$tmp"
  unzip -Z1 "$tmp/a.zip" > "$tmp/members" 2> /dev/null || { discard "not a readable archive"; return; }
  printf 'streak\n' > "$tmp/members.want"
  cmp -s "$tmp/members" "$tmp/members.want" || { discard "archive members are not exactly one file named streak"; return; }
  # Bounded read: the size limit above is on the COMPRESSED archive, so cap what is decompressed. unzip
  # dies of SIGPIPE (141) once head has its 8 bytes; that is the expected early stop, not an error.
  local rcs
  timeout 10 unzip -p "$tmp/a.zip" streak < /dev/null 2> /dev/null | head -c 8 > "$tmp/val.raw"
  rcs=("${PIPESTATUS[@]}")
  { [ "${rcs[0]}" -eq 0 ] || [ "${rcs[0]}" -eq 141 ]; } && [ "${rcs[1]}" -eq 0 ] || { discard "member unreadable"; return; }
  # Digits plus newlines only (no NUL, space or letter) and at most 7 bytes: 6 digits and the one trailing
  # newline a writer may add; the value check below then requires digits only once the newlines are stripped.
  local raw_bytes stray v
  raw_bytes=$(wc -c < "$tmp/val.raw")
  stray=$(tr -d '0-9\n' < "$tmp/val.raw" | wc -c)
  v=$(cat "$tmp/val.raw")
  if [ "$raw_bytes" -gt 7 ] || [ "$stray" -ne 0 ] || ! valid_number "$v"; then
    printf '::notice::malformed streak value (%s bytes read)\n' "$raw_bytes"
    discard "malformed value"
    return
  fi

  assert_fixture_dir "$STREAK_FILE"
  printf '%s' "$((10#$v))" > "$STREAK_FILE" || die "could not write the state file"
  printf 'streak artifact %s restored from a prior run\n' "$art_id"
  printf 'matched=true\nprior=%s\n' "$((10#$v))" >> "$GITHUB_OUTPUT"
}

cmd_seal() {
  : "${STREAK_FILE:?}"
  assert_fixture_dir "$STREAK_FILE"
  local verdict="${VERDICT:-}" restored="${RESTORED:-0}"
  # An empty RESTORED means fetch produced no output (it failed); the upload is skipped then anyway.
  [ -n "$restored" ] || restored=0
  valid_number "$restored" || die "RESTORED is not a number"
  restored=$((10#$restored))
  mkdir -p "$(dirname "$STREAK_FILE")" || die "could not create the state directory"
  local v; v=$(read_state)
  if [ -n "$v" ]; then
    valid_number "$v" || die "the state file holds a non-numeric value after a '${verdict}' verdict"
    v=$((10#$v))
  fi
  case "$verdict" in
    pass)
      # The probe cleared the file on a real PASS; force 0 so a failed `rm` cannot leave the old streak.
      v=0 ;;
    fail)
      # The probe clears the file on a real FAIL; force 0 so a failed `rm` cannot leave a stale streak
      # that makes the next TRANSIENT escalate early. The escalation exits rc 3 and seals as `broken`,
      # so a `fail` verdict never legitimately carries a surviving streak.
      v=0 ;;
    broken)
      # rc 3 (the escalation) leaves the streak that tripped it, written by the probe's own
      # `_transient`; any other broken exit never reached that write, so the value fetch restored is
      # kept. A broken probe is not evidence of a clean window.
      [ -n "$v" ] || v=$restored ;;
    transient)
      # The probe's `_transient` writes exactly RESTORED+1. Its write is `2>/dev/null || true`, so any
      # other value means the increment was lost and sealing it would silently stall the streak.
      [ -n "$v" ] || die "verdict transient but the state file is missing or empty: the probe's increment was lost"
      [ "$v" -eq $((restored + 1)) ] || die "verdict transient but the streak is ${v}, expected $((restored + 1)): the probe's increment was lost"
      ;;
    *) die "unknown or empty verdict; refusing to seal" ;;
  esac
  printf '%s' "$v" > "$STREAK_FILE" || die "could not write the sealed state file"
  printf 'streak sealed at %s (verdict %s)\n' "$v" "$verdict"
}

cmd_assert() {
  : "${STREAK_FILE:?}"
  local matched="${MATCHED:-}" bootstrap="${BOOTSTRAP:-}"
  local v; v=$(read_state)
  valid_number "$v" || die "the sealed streak state is missing or non-numeric"
  if [ "$matched" != "true" ] && [ "$bootstrap" != "true" ]; then
    if [ -z "$matched" ]; then
      die "the fetch step produced no result (it failed or was skipped); see that step. An unreadable store is not fixed by bootstrap=true."
    fi
    die "the streak store returned no prior generation. The consecutive-TRANSIENT escalation cannot fire, so a permanently broken probe is indistinguishable from a healthy quiet window. This run still publishes its own value, so the next run restores it; dispatch with bootstrap=true to make a run like this one green."
  fi
  printf 'streak state: restored=%s value=%s\n' "${matched:-false}" "$((10#$v))"
}

case "${1-}" in
  fetch)  cmd_fetch ;;
  seal)   cmd_seal ;;
  assert) cmd_assert ;;
  *) printf 'usage: %s fetch|seal|assert\n' "$0" >&2; exit 2 ;;
esac
