#!/usr/bin/env bash
# dispatch-web-redeploy/source-run-gate.sh — decides whether git-data-pin-redeploy.yml
# should force a web release for a given apply-web-platform-infra.yml run (#7226, ADR-237 D6).
#
# The pin (GIT_DATA_SSH_HOST_KEY) changes ONLY when the git-data birth job
# (git_data_host_create) or replace job (git_data_host_replace) applies. So: proceed iff
# either of those jobs concluded `success` in the source run. Any other outcome — both
# skipped (an ordinary merge apply or another dispatch target), a failed or cancelled
# birth/replace — is a SKIP with a ::notice:: naming why; exit 0.
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
out="${GITHUB_OUTPUT:-/dev/null}"

rid="${SOURCE_RUN_ID:-}"
if [[ ! "$rid" =~ ^[0-9]+$ ]]; then
  echo "::error::source-run-gate: source run id '${rid}' is not numeric; cannot decide whether the pin rotated (fail closed)."
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
  { echo "proceed=true"; echo "source_job=${src}"; } >> "$out"
  exit 0
fi
echo "::notice::source-run-gate: no redeploy — in run ${rid} ${BIRTH_JOB}=${birth:-none} and ${REPLACE_JOB}=${replace:-none}; the host-key pin only rotates when one of them concludes success."
{ echo "proceed=false"; echo "source_job="; } >> "$out"
