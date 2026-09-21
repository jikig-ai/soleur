#!/usr/bin/env bash
# dispatch-web-redeploy/source-run-gate.sh — decides whether git-data-pin-redeploy.yml
# should force a web release for a given apply-web-platform-infra.yml run (#7226, ADR-237 D6).
#
# The pin (GIT_DATA_SSH_HOST_KEY) changes ONLY when the git-data birth job
# (git_data_host_create) or replace job (git_data_host_replace) applies. So: proceed iff
# either of those jobs concluded `success` in the source run. Both skipped/absent (an
# ordinary merge apply or another dispatch target) is a SKIP with a ::notice::; exit 0.
# A birth/replace that concluded anything else (failure, cancelled, ...) is also a SKIP,
# but LOUD: the apply may have published the new pin before a later step failed, so it
# emits a ::warning:: and a summary line naming the manual recovery (a dispatch with NO
# source_run_id — the same id would re-read the same non-success); exit 0.
#
# FAIL CLOSED when the source run cannot be read: a non-numeric run id, `gh run view`
# failing, or output that is not a {jobs:[...]} document exits 1. "Could not read" must
# never read as "nothing to do" — a missed redeploy leaves the app on a stale pin.
#
# Env: SOURCE_RUN_ID (required), GH_TOKEN / GH_REPO (consumed by gh),
#      GITHUB_OUTPUT (receives proceed=true|false and source_job=<name>).
# Tested by tests/scripts/test-dispatch-web-redeploy.sh (rows G*).
set -euo pipefail

BIRTH_JOB="git_data_host_create"
REPLACE_JOB="git_data_host_replace"
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
# Outside Actions (a local run) the outputs go to a throwaway file, never a relative path.
out="${GITHUB_OUTPUT:-$(mktemp)}"
_emit() {
  assert_fixture_dir "$out"
  printf '%s\n' "$@" >> "$out"
}
_summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY" || true; }

rid="${SOURCE_RUN_ID:-}"
if [[ ! "$rid" =~ ^[0-9]+$ ]]; then
  # The unvalidated value is never echoed (it would land inside a workflow command).
  echo "::error::source-run-gate: the source run id is not a plain number; cannot decide whether the pin rotated (fail closed)."
  exit 1
fi
if ! doc="$(gh run view "$rid" --json jobs)"; then
  echo "::error::source-run-gate: could not read the jobs of run ${rid}; cannot decide whether the pin rotated (fail closed). Re-run this job."
  exit 1
fi
if ! jq -e '(.jobs | type) == "array"' >/dev/null 2>&1 <<<"$doc"; then
  echo "::error::source-run-gate: run ${rid} returned no readable jobs array (fail closed)."
  exit 1
fi
concl() { jq -r --arg n "$1" '[.jobs[] | select(.name == $n) | .conclusion // ""] | if length == 1 then .[0] else "absent" end' <<<"$doc"; }
birth="$(concl "$BIRTH_JOB")"; replace="$(concl "$REPLACE_JOB")"

if [[ "$birth" == success || "$replace" == success ]]; then
  src="$REPLACE_JOB"; [[ "$birth" == success ]] && src="$BIRTH_JOB"
  echo "source-run-gate: ${src} concluded success in run ${rid}; the pin rotated — redeploying."
  _emit "proceed=true" "source_job=${src}"
  exit 0
fi
for c in "$birth" "$replace"; do
  case "$c" in
    skipped|absent|"") ;;
    *)
      echo "::warning::source-run-gate: in run ${rid} ${BIRTH_JOB}=${birth:-none} and ${REPLACE_JOB}=${replace:-none}. The apply may have published the new pin before failing — pin may be published; dispatch git-data-pin-redeploy.yml with NO source_run_id (\`gh workflow run git-data-pin-redeploy.yml --ref main\`) to redeploy unconditionally — passing source_run_id=${rid} would re-read this same non-success and skip again."
      _summary "- ${BIRTH_JOB}=${birth:-none}, ${REPLACE_JOB}=${replace:-none} in run ${rid}: pin may be published; dispatch git-data-pin-redeploy.yml with NO source_run_id (\`gh workflow run git-data-pin-redeploy.yml --ref main\`) to redeploy unconditionally."
      _emit "proceed=false" "source_job="
      exit 0
      ;;
  esac
done
echo "::notice::source-run-gate: no redeploy — in run ${rid} ${BIRTH_JOB}=${birth:-none} and ${REPLACE_JOB}=${replace:-none}; the host-key pin only rotates when one of them concludes success."
_emit "proceed=false" "source_job="
