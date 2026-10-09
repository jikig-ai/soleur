#!/usr/bin/env bash
# (#9175) Discoverability probe for the inngest-provision rehearsal route — answers "did the
# rehearsal route run, and did it conclude?" from the PUBLIC GitHub runs API (no credentials;
# the repo is public). Prints `last_run_conclusion=<success|failure|null>` for the newest
# dispatch of inngest-provision-rehearsal.yml, `null` before its first run.
#
# Deliberately thin: the evidence-bearing instrument is the capture script (Better Stack);
# this probe exists so "is there a rehearsal result?" is discoverable without GitHub auth.
set -uo pipefail

WF="inngest-provision-rehearsal.yml"
out="$(curl --disable --noproxy '*' --connect-timeout 5 -m 20 -sS -f \
  "https://api.github.com/repos/jikig-ai/soleur/actions/workflows/${WF}/runs?per_page=1" 2>/dev/null)" \
  || { echo "last_run_conclusion=unreachable"; exit 2; }
con="$(printf '%s' "$out" | jq -r '.workflow_runs[0].conclusion // "null"' 2>/dev/null)"
[[ -n "$con" ]] || con="null"
echo "last_run_conclusion=${con}"
exit 0
