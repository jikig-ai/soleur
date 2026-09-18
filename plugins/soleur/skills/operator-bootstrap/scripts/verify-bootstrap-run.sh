#!/usr/bin/env bash
# verify-bootstrap-run.sh — read a generated script's run ledger.
#
# ONE mode: `--ledger <path> --last`. It prints the last run's stage ledger and
# exits non-zero when that run is incomplete, naming the stage index to resume
# from.
#
# There is deliberately NO `--self-test`. An earlier draft had one; it duplicated
# plugins/soleur/test/operator-script.test.sh (which already asserts the same
# contract in CI, with mutation matrices behind it) and its "N/N invariants OK"
# pinned a hard-coded count inside an expected-output string — the frozen-list
# defect the guards forbid elsewhere.
#
# COMPLETENESS IS DECIDED BY COMPARING A COMPLETED SET AGAINST A DECLARED TOTAL,
# not by looking for a settle record after the last begin record. The latter is
# undecidable from the artifact: the missing line would have been written by the
# process that was killed, so its absence is indistinguishable from never-ran,
# deleted-by-the-founder, and a different slug directory.
#
# <!-- Inspired by mattpocock/skills/skills/engineering/wizard/ (MIT, Copyright (c) 2026 Matt Pocock). -->
#
# Exit codes: 0 complete · 1 usage error · 2 ledger unreadable/empty
#             65 the last run is INCOMPLETE (stages are missing)
set -euo pipefail

LEDGER=""
WANT_LAST=false

usage() {
  cat >&2 <<'USAGE'
Usage: verify-bootstrap-run.sh --ledger <path> --last

  --ledger <path>   The run ledger written by a generated bootstrap script
                    (provisioning/<slug>/bootstrap-runs.jsonl, or
                     .soleur/bootstrap-runs.jsonl when there is no slug).
  --last            Report on the most recent run. Required; it is the only mode.
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; [[ -n "$LEDGER" ]] || usage; shift 2 ;;
    --last)   WANT_LAST=true; shift ;;
    --help|-h) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$LEDGER" ]] || usage
$WANT_LAST || usage

if [[ ! -r "$LEDGER" ]]; then
  echo "SOLEUR_BOOTSTRAP_LEDGER_UNREADABLE path=${LEDGER}" >&2
  exit 2
fi

# The last run_id present in the file. Field extraction is a plain sed rather
# than jq: a generated script runs on the founder's machine and must not acquire
# a dependency to be inspectable.
last_run="$(sed -n 's/.*"run_id":"\([^"]*\)".*/\1/p' "$LEDGER" | tail -1)"
if [[ -z "$last_run" ]]; then
  echo "SOLEUR_BOOTSTRAP_LEDGER_EMPTY path=${LEDGER}" >&2
  exit 2
fi

run_lines="$(grep -F "\"run_id\":\"${last_run}\"" "$LEDGER" || true)"

total="$(sed -n 's/.*"total_stages":\([0-9]*\).*/\1/p' <<<"$run_lines" | tail -1)"
[[ -n "$total" ]] || total=0

echo "run_id:       ${last_run}"
echo "declared:     ${total} stage(s)"
echo ""
printf '%-6s %-10s %s\n' "STAGE" "OUTCOME" "NAME"

completed=""
idx=1
while [[ "$idx" -le "$total" ]]; do
  settle="$(grep -F '"phase":"settle"' <<<"$run_lines" | grep -F "\"stage_index\":${idx}," || true)"
  name="$(sed -n 's/.*"stage_name":"\([^"]*\)".*/\1/p' <<<"$settle" | tail -1)"
  outcome="$(sed -n 's/.*"outcome":"\([^"]*\)".*/\1/p' <<<"$settle" | tail -1)"
  if [[ -n "$settle" && "$outcome" == "ok" ]]; then
    completed="${completed} ${idx}"
    printf '%-6s %-10s %s\n' "$idx" "ok" "$name"
  elif [[ -n "$settle" ]]; then
    printf '%-6s %-10s %s\n' "$idx" "${outcome:-?}" "$name"
  else
    begun="$(grep -F '"phase":"begin"' <<<"$run_lines" | grep -F "\"stage_index\":${idx}," || true)"
    bname="$(sed -n 's/.*"stage_name":"\([^"]*\)".*/\1/p' <<<"$begun" | tail -1)"
    printf '%-6s %-10s %s\n' "$idx" "MISSING" "${bname:-<never began>}"
  fi
  idx=$((idx + 1))
done

n_done="$(wc -w <<<"$completed" | tr -d ' ')"
echo ""
echo "completed:    ${n_done}/${total}"

if [[ "$total" -gt 0 && "$n_done" -eq "$total" ]]; then
  echo "SOLEUR_BOOTSTRAP_RUN_COMPLETE run_id=${last_run}"
  exit 0
fi

# Resume from the first stage that is not in the completed set — not from the
# highest index seen, which would skip a gap in the middle.
resume=1
idx=1
while [[ "$idx" -le "$total" ]]; do
  if ! grep -qw "$idx" <<<"$completed"; then
    resume="$idx"
    break
  fi
  idx=$((idx + 1))
done

echo "SOLEUR_BOOTSTRAP_RUN_INCOMPLETE run_id=${last_run} resume_stage=${resume}"
echo "Resume with:  SOLEUR_BOOTSTRAP_START_STAGE=${resume} bash <the bootstrap script>" >&2
exit 65
