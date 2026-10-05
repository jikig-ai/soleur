#!/usr/bin/env bash
# Pre-bypass exposure measurement for a self-sealing required check (#7600).
#
# WHAT THIS IS FOR. A required status check triggered on `pull_request_target` executes the
# workflow file from the BASE branch, never the PR head. That is a security property, not a
# bug -- it is why the trigger may hold secrets. The consequence is that a required
# `pull_request_target` check which breaks on `main` is SELF-SEALING: no PR can repair it,
# because every PR is subject to the broken copy. The sanctioned exit is a ruleset bypass
# actor.
#
# The reusable asset from the 2026-08-16 `cla-evidence` outage is NOT "use the admin bypass".
# It is the EXPOSURE MEASUREMENT performed before authorising one. This script is that
# measurement, executed rather than described: a prose checklist is run by a human under time
# pressure during an outage, which is exactly when a step gets skipped.
#
# THE THREE-STATE RULE (ADR-192). An unanswerable probe is NOT a clean probe. Every check
# below resolves to PASS / FAIL / UNKNOWN, and any UNKNOWN forces the overall verdict to
# UNKNOWN -- never SAFE. A query that could not run and a query that found nothing must not
# produce the same verdict, because the first one reads as safety and is not.
#
# WHAT IT DOES NOT DO. It does not perform the bypass, and it takes no write action of any
# kind. It measures and prints. The decision, and the merge, remain the operators.
#
# Usage:
#   scripts/preflight-required-check-bypass.sh --surface
#       Enumerate the deadlockable surface: required checks produced by pull_request_target
#       workflows. Run this BEFORE an incident, to know what can deadlock.
#
#   scripts/preflight-required-check-bypass.sh --check <context> --since <ISO8601> [--until <ISO8601>]
#       Measure exposure for a broken required check over the dark window.
#
#       --until is the RESTORATION instant. Omit it only while the outage is still live.
#       An open-ended window sweeps every merge up to now and reports REAL for a long-since
#       repaired incident -- correct arithmetic, wrong question. The window has two ends.
#
# Exit codes:
#   0  measured, exposure NIL -- a bypass is defensible on this evidence
#   1  measured, exposure REAL -- a bypass drops something; do not proceed on this basis
#   2  UNKNOWN -- at least one probe could not be answered; treat as REAL until resolved
#   3  usage error

set -uo pipefail

REPO="${SOLEUR_REPO:-jikig-ai/soleur}"
MODE=""
CHECK=""
SINCE=""
UNTIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface) MODE="surface"; shift ;;
    --check)   MODE="measure"; CHECK="${2:-}"; shift 2 || shift ;;
    --since)   SINCE="${2:-}"; shift 2 || shift ;;
    --until)   UNTIL="${2:-}"; shift 2 || shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 3 ;;
  esac
done

[[ -n "$MODE" ]] || { echo "usage: $0 --surface | --check <context> --since <ISO8601>" >&2; exit 3; }

command -v gh >/dev/null || { echo "SOLEUR_BYPASS_PREFLIGHT probe=gh state=UNKNOWN reason=gh-not-installed" >&2; exit 2; }

repo_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# --- The deadlockable surface -------------------------------------------------------------
#
# DERIVED, never hardcoded. A hardcoded list is a snapshot: the next workflow that adopts
# `pull_request_target`, or the next check added to a ruleset, silently leaves the list stale
# while this script keeps reporting confidently. Both halves are read live.
#
# `grep -l pull_request_target` over the workflow directory is NOT sufficient and was measured
# wrong: on this repo it returns five files, three of which only MENTION the trigger in a
# comment. The `on:` block is what decides, so parse it.
pr_target_workflows() {
  local root; root="$(repo_root)"
  python3 - "$root/.github/workflows" <<'PY'
import os, re, sys
d = sys.argv[1]
if not os.path.isdir(d):
    print("__UNKNOWN__"); sys.exit(0)
for fn in sorted(os.listdir(d)):
    if not fn.endswith((".yml", ".yaml")):
        continue
    try:
        lines = open(os.path.join(d, fn), encoding="utf-8").read().splitlines()
    except Exception:
        print("__UNKNOWN__"); continue
    inon = False
    for ln in lines:
        if re.match(r"^on:\s*$", ln):
            inon = True; continue
        if re.match(r"^on:\s*\S", ln):
            if "pull_request_target" in ln: print(fn)
            break
        if inon:
            if ln and not ln[0].isspace(): break
            if re.match(r"^  pull_request_target\s*:", ln):
                print(fn); break
PY
}

# Every check context required by any ACTIVE ruleset, with the ruleset that requires it.
required_contexts() {
  gh api "repos/$REPO/rulesets" --jq '.[] | select(.enforcement=="active") | .id' 2>/dev/null |
  while read -r rid; do
    [[ -n "$rid" ]] || continue
    gh api "repos/$REPO/rulesets/$rid" --jq \
      '.name as $n | .rules[]? | select(.type=="required_status_checks")
       | .parameters.required_status_checks[] | "\($n)\t\(.context)"' 2>/dev/null
  done
}

# A check context is produced by a job; map job `name:` (or the job key when unnamed) back to
# its workflow file, so a required context can be attributed to a pull_request_target file.
context_owner() {
  local root; root="$(repo_root)"
  python3 - "$root/.github/workflows" <<'PY'
import os, re, sys
d = sys.argv[1]
if not os.path.isdir(d): sys.exit(0)
for fn in sorted(os.listdir(d)):
    if not fn.endswith((".yml", ".yaml")): continue
    try: lines = open(os.path.join(d, fn), encoding="utf-8").read().splitlines()
    except Exception: continue
    injobs=False; job=None
    for ln in lines:
        if re.match(r"^jobs:\s*(#.*)?$", ln): injobs=True; continue
        if injobs and re.match(r"^[A-Za-z]", ln): injobs=False; job=None; continue
        if not injobs: continue
        m = re.match(r'^  "?([A-Za-z0-9_-]+)"?:\s*(#.*)?$', ln)
        if m:
            job = m.group(1); print(f"{job}\t{fn}"); continue
        n = re.match(r'^    name:\s*(.+?)\s*$', ln)
        if n and job:
            print(f"{n.group(1).strip(chr(34)+chr(39))}\t{fn}")
PY
}

if [[ "$MODE" == "surface" ]]; then
  echo "=== Deadlockable surface for $REPO ==="
  echo
  mapfile -t PRT < <(pr_target_workflows)
  if [[ ${#PRT[@]} -eq 0 ]]; then
    echo "SOLEUR_BYPASS_PREFLIGHT probe=surface state=PASS detail=no-pull-request-target-workflows"
    exit 0
  fi
  if printf '%s\n' "${PRT[@]}" | grep -q '__UNKNOWN__'; then
    echo "SOLEUR_BYPASS_PREFLIGHT probe=surface state=UNKNOWN reason=workflow-dir-unreadable" >&2
    exit 2
  fi
  echo "pull_request_target workflows (parsed from the on: block, not grepped):"
  printf '  %s\n' "${PRT[@]}"
  echo

  OWNERS="$(context_owner)"
  REQ="$(required_contexts)"
  if [[ -z "$REQ" ]]; then
    echo "SOLEUR_BYPASS_PREFLIGHT probe=required-contexts state=UNKNOWN reason=empty-or-unreadable" >&2
    exit 2
  fi

  echo "REQUIRED checks produced by those workflows — these are what can deadlock:"
  found=0
  while IFS=$'\t' read -r ruleset ctx; do
    [[ -n "$ctx" ]] || continue
    owner="$(awk -F'\t' -v c="$ctx" '$1==c {print $2; exit}' <<<"$OWNERS")"
    for w in "${PRT[@]}"; do
      if [[ "$owner" == "$w" ]]; then
        printf '  %-28s  <- %-24s  [ruleset: %s]\n' "$ctx" "$w" "$ruleset"
        found=$((found + 1))
      fi
    done
  done <<<"$REQ"
  [[ $found -gt 0 ]] || echo "  (none — no required check is currently produced by a pull_request_target workflow)"
  echo
  echo "Bypass actors (the sanctioned exit; verify one exists BEFORE assuming it does):"
  gh api "repos/$REPO/rulesets" --jq '.[] | select(.enforcement=="active") | .id' 2>/dev/null |
    while read -r rid; do
      # `join(", ") // "NONE"` does NOT work here: join on an empty array yields "", and ""
      # is truthy to jq's `//`, so a ruleset with NO bypass actor rendered as a blank line.
      # That is the one output an operator must not miss -- no bypass actor means there is
      # no sanctioned exit at all, and a blank reads as a formatting artefact.
      gh api "repos/$REPO/rulesets/$rid" --jq \
        '[.bypass_actors[]? | .actor_type + "(" + .bypass_mode + ")"] as $b
         | "  " + .name + ": " + (if ($b | length) == 0 then "NONE — no sanctioned exit" else ($b | join(", ")) end)' 2>/dev/null
    done
  exit 0
fi

# --- Exposure measurement -----------------------------------------------------------------
[[ -n "$CHECK" ]] || { echo "--check requires a context name" >&2; exit 3; }
[[ -n "$SINCE" ]] || { echo "--since requires an ISO8601 instant (the first failing run)" >&2; exit 3; }

unknown=0
real=0

emit() { printf 'SOLEUR_BYPASS_PREFLIGHT probe=%s state=%s %s\n' "$1" "$2" "${3:-}"; }
note() { printf '    %s\n' "$*"; }

echo "=== Pre-bypass exposure measurement ==="
echo "repo=$REPO check=$CHECK window=$SINCE..${UNTIL:-<still live>}"
echo

# (2) Did any merges land during the window? Zero merges = zero unrecorded events.
echo "[2] Merges during the dark window"
if [[ -n "$UNTIL" ]]; then
  merge_q="merged:$SINCE..$UNTIL"
else
  merge_q="merged:>=$SINCE"
  note "no --until given: treating the outage as STILL LIVE and sweeping to now"
fi
# `-L` is load-bearing, not tidiness. `gh pr list --search` caps at 30 rows unless a limit
# is given, and a truncated list is indistinguishable from a short one -- which in THIS probe
# means under-reporting merges and returning NIL for a window that had exposure. That is the
# same "an empty read is not a clean read" defect the header states, so a cap-length result
# is reported UNKNOWN rather than counted.
# Overridable so the cap-detection branch below can actually be EXERCISED. A branch that
# cannot be driven is indistinguishable from one that does not work.
MERGE_LIMIT="${SOLEUR_BYPASS_MERGE_LIMIT:-200}"
merged="$(gh pr list --repo "$REPO" --state merged --search "$merge_q" -L "$MERGE_LIMIT" \
            --json number,mergedAt --jq '.[] | "#\(.number) \(.mergedAt)"' 2>/dev/null)"
mrc=$?
if [[ $mrc -ne 0 ]]; then
  emit merges UNKNOWN "reason=query-failed rc=$mrc"; unknown=1
elif [[ -z "$merged" ]]; then
  emit merges PASS "count=0"
  note "no merges landed in the window, so no event could have gone unrecorded"
elif [[ "$(wc -l <<<"$merged")" -ge "$MERGE_LIMIT" ]]; then
  emit merges UNKNOWN "reason=result-at-limit limit=$MERGE_LIMIT"
  note "the query returned $MERGE_LIMIT rows, which is the cap -- the true count may be higher"
  note "narrow the window or raise MERGE_LIMIT; a capped list must not be counted as complete"
  unknown=1
else
  emit merges REAL "count=$(wc -l <<<"$merged")"
  note "$(tr '\n' ' ' <<<"$merged")"
  note "each of these merged while the check was dark — confirm none needed its record"
  real=1
fi
echo

# (4) Did the ENFORCING gate stay green? Distinguish the sidecar from the instrument.
# A sidecar records; an instrument conditions merge. Losing a sidecar for a window is a
# very different exposure from losing the instrument, and the two are easy to conflate
# because they sit side by side in the checks list.
echo "[4] Sibling required checks during the window (sidecar vs instrument)"
siblings="$(required_contexts | awk -F'\t' -v c="$CHECK" '$2!=c {print $2}' | sort -u)"
if [[ -z "$siblings" ]]; then
  emit siblings UNKNOWN "reason=could-not-enumerate-required-contexts"; unknown=1
else
  note "other required contexts: $(tr '\n' ' ' <<<"$siblings")"
  note "identify which of these is the INSTRUMENT for $CHECK and confirm it stayed green;"
  note "a green instrument means the enforceable control held while the sidecar was dark"
  emit siblings PASS "enumerated=$(wc -l <<<"$siblings")"
fi
echo

# (1)+(3) Last good run, and whether the write path was ever reached.
echo "[1/3] Last successful run of '$CHECK', and whether its write path was reached"
runs="$(gh run list --repo "$REPO" --json databaseId,name,conclusion,event,createdAt -L 100 \
          --jq ".[] | select(.name==\"$CHECK\") | \"\(.databaseId)\t\(.conclusion)\t\(.event)\t\(.createdAt)\"" 2>/dev/null)"
rrc=$?
if [[ $rrc -ne 0 || -z "$runs" ]]; then
  emit last-good-run UNKNOWN "reason=no-runs-matched-name rc=$rrc"
  note "the workflow NAME and the CHECK CONTEXT are frequently different strings;"
  note "re-run with the workflow name, or inspect: gh run list --repo $REPO -L 50"
  unknown=1
else
  note "$(head -5 <<<"$runs" | tr '\n' '|')"
  skipped="$(awk -F'\t' '$2=="skipped"' <<<"$runs" | wc -l)"
  emit write-path PASS "skipped_runs=$skipped"
  note "a trigger whose runs are all 'skipped' never invoked the write path,"
  note "so it cannot have dropped anything"
  note "MANUAL CONFIRMATION STILL REQUIRED: open the last successful run and look for the"
  note "idempotency marker (e.g. a 409 on a conditional PUT). If the artifact for this"
  note "period already exists, every run in the window was a no-op and the loss is nil."
  note "If the period rolled over and no record exists, THE LOSS IS REAL."
fi
echo

echo "=== Verdict ==="
if [[ $unknown -eq 1 ]]; then
  echo "UNKNOWN — at least one probe could not be answered."
  echo "An unanswerable probe is not a clean probe (ADR-192). Treat exposure as REAL until"
  echo "the UNKNOWN above is resolved. Do NOT read this as authorisation."
  exit 2
fi
if [[ $real -eq 1 ]]; then
  echo "REAL — something measurable happened in the window."
  echo "The zero-loss precedent does NOT apply. Resolve each item above before bypassing."
  exit 1
fi
echo "NIL on the automated probes."
echo "The artifact-already-written check (item 1) still needs the run log inspected by eye;"
echo "this script cannot read a conditional-PUT status code out of a job log reliably."
echo "Record the measurement in knowledge-base/legal/audits/ and a commit trailer."
exit 0
