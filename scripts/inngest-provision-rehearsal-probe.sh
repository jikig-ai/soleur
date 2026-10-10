#!/usr/bin/env bash
# (#9175) Discoverability probe for the inngest-provision rehearsal route — answers "did the
# rehearsal route run, and did it conclude?" from the PUBLIC GitHub runs API (no credentials;
# the repo is public). Prints, for the newest dispatch of inngest-provision-rehearsal.yml:
#
#   last_run_id=<digits|none>          — the run whose artifact carries the evidence
#   last_run_url=<url|none>
#   last_run_status=<queued|in_progress|completed|none>
#   last_run_conclusion=<success|failure|cancelled|timed_out|action_required|
#                        startup_failure|skipped|stale|neutral|null>
#
# `null`/none = never ran (or still running: check status). `unreachable` (exit 2) = the API
# or the JSON shape failed — a tooling fault, never conflated with "no run".
#
# Deliberately thin: the evidence-bearing instrument is the capture script (Better Stack);
# this probe exists so "is there a rehearsal result?" is discoverable without GitHub auth.
set -uo pipefail

WF="inngest-provision-rehearsal.yml"
command -v jq >/dev/null 2>&1 || { echo "last_run_conclusion=unreachable (jq missing)"; exit 2; }
out="$(curl --disable --noproxy '*' --connect-timeout 5 -m 20 -sS -f \
  "https://api.github.com/repos/jikig-ai/soleur/actions/workflows/${WF}/runs?per_page=1" 2>/dev/null)" \
  || { echo "last_run_conclusion=unreachable"; exit 2; }
parsed="$(printf '%s' "$out" | jq -r '
  .workflow_runs[0] // empty
  | [.id, .html_url, .status, (.conclusion // "null")] | @tsv' 2>/dev/null)" \
  || { echo "last_run_conclusion=unreachable (unparseable API payload)"; exit 2; }
if [[ -z "$parsed" ]]; then
  echo "last_run_id=none"; echo "last_run_url=none"
  echo "last_run_status=none"; echo "last_run_conclusion=null"
  exit 0
fi
IFS=$'\t' read -r rid url status con <<<"$parsed"
echo "last_run_id=${rid}"
echo "last_run_url=${url}"
echo "last_run_status=${status}"
echo "last_run_conclusion=${con}"
exit 0
