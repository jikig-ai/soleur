#!/usr/bin/env bash
# dispatch-web-redeploy/source-run-gate.sh — decides whether git-data-pin-redeploy.yml
# should force a web release for a given apply-web-platform-infra.yml run (#7226, #8710,
# ADR-237 D2).
#
# In CI the pin (GIT_DATA_SSH_HOST_KEY) changes ONLY when the `terraform apply` of the git-data
# birth job (git_data_host_create) or replace job (git_data_host_replace) runs: that step
# (YAML `id: apply`) is the only CI writer of doppler_secret.git_data_ssh_host_key (parity test
# PT4 holds every other job of every workflow off that address). An operator-local
# `terraform apply` also writes it and fires no gate; ADR-237 D2 covers that path. A job
# conclusion is NOT evidence of an apply — a `plan_only=true` rehearsal of the replace ends
# `success` with the apply step `skipped` (#8710). So the gate reads the apply STEP of each job
# from the one jobs document `gh run view <id> --json jobs` returns. The API carries no step
# `id`, so the step is matched by its exact `name:` (the two *_APPLY constants below; parity
# test PT1 in plugins/soleur/test/terraform-target-parity.test.ts binds them to the workflow).
#
# Per job: N = the number of steps named exactly that job's apply constant (a missing or
# non-array `steps` counts N = 0), A = that step's conclusion when N == 1, passed through an
# allowlist (anything unknown prints as `unrecognized`). Rows are evaluated top to bottom,
# first match wins (the labels are row ids, not ranks):
#
#   row    job              steps / apply step                    result                        token
#   1      absent, skipped  -                                     quiet notice, job did not run verdict=not_run
#   1b     not success      steps is an empty array               quiet notice (environment     verdict=not_run
#                                                                 refusal, cancelled pending)
#   4      success          N != 1, or A not success/skipped      exit 1, fail closed           verdict=unidentified
#   2      success          A == success                          proceed: the pin rotated      verdict=rotated
#   3      any              A == skipped                          quiet notice, no apply ran    verdict=no_apply
#   5a     not success      A == success                          warning: the pin WAS          verdict=pin_published
#                                                                 published, no redeploy
#   5b     not success      anything else (N != 1, failure, ...)  warning: the pin MAY be       verdict=pin_maybe_published
#                                                                 published, no redeploy
#   (5a and 5b both set output pin_published=true, which emails ops: a red job that may have
#   published the pin is the state where the run ends green while erasures break.)
#
# Combination: any job in row 4 (or a duplicated git-data job) exits 1 before emitting outputs.
# Else any job in row 2 proceeds (birth wins a tie). Else any job in 5a/5b takes the warning
# arm (pin_published=true). Else the quiet notice arm. 5a/5b do not redeploy: the job is red,
# and the runbook's recovery for a red boot poll is a read first; the no-source_run_id dispatch
# redeploys when wanted. Every verdict line carries `in run <id>`, the per-job
# `<job>=<conclusion>` tokens and one `verdict=` token.
#
# This is a correctness gate, not an authorization gate: a branch dispatch controls job and step
# names, so NO name taken from the API is ever printed — only the constants, N, the allowlisted
# conclusions and the validated run id.
#
# FAIL CLOSED when the source run cannot be read: a non-numeric run id, `gh run view`
# failing, output that is not exactly one {jobs:[...]} document, or any jq evaluation failing
# exits 1. "Could not read" must never read as "nothing to do" — a missed redeploy leaves the
# app on a stale pin. Every jq read is a checked assignment in this shell, never a nested
# $(...) (whose failure errexit does not see).
#
# The jobs are read for SOURCE_RUN_ATTEMPT when it is a number (the attempt that fired this
# run), else for the latest attempt: a re-run in progress must not be graded for an earlier one.
#
# Env: SOURCE_RUN_ID (required), SOURCE_RUN_ATTEMPT (optional), GH_TOKEN / GH_REPO (consumed by gh),
#      GITHUB_OUTPUT (receives proceed=true|false, source_job=<name>, pin_published=true|false).
# Tested by tests/scripts/test-dispatch-web-redeploy.sh (rows G*, mutations GM).
set -euo pipefail

BIRTH_JOB="git_data_host_create"
REPLACE_JOB="git_data_host_replace"
# The `name:` of the `id: apply` step of each job in apply-web-platform-infra.yml, byte for byte
# (the replace name carries U+2014). Exact equality only (jq --arg), never a prefix or a regex.
BIRTH_APPLY="Terraform apply (git-data birth)"
REPLACE_APPLY="Terraform apply (git-data-host -replace) — both-volumes-preserved assert"
JOBS=("$BIRTH_JOB" "$REPLACE_JOB")
REDEPLOY_CMD="\`gh workflow run git-data-pin-redeploy.yml --ref main\`"
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
# The throwaway file is owned by this script, so this script's EXIT trap removes it.
out="${GITHUB_OUTPUT:-}"
if [[ -z "$out" ]]; then
  out="$(mktemp)"
  trap 'rm -f "$out"' EXIT
fi
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
att=()
[[ "${SOURCE_RUN_ATTEMPT:-}" =~ ^[1-9][0-9]*$ ]] && att=(--attempt "$SOURCE_RUN_ATTEMPT")
if ! doc="$(gh run view "$rid" "${att[@]}" --json jobs)"; then
  echo "::error::source-run-gate: could not read the jobs of run ${rid}; cannot decide whether the pin rotated (fail closed). Re-run this job."
  exit 1
fi
if ! jq -e -s 'length == 1 and (.[0].jobs | type) == "array"' >/dev/null 2>&1 <<<"$doc"; then
  echo "::error::source-run-gate: run ${rid} returned no readable jobs array (fail closed)."
  exit 1
fi

# allow VALUE -> VALUE when it is a known conclusion, else `unrecognized`. gh prints an
# in-progress conclusion as "" (a raw JSON null reads as `null`); both print as `null`.
allow() {
  case "$1" in
    "") printf 'null' ;;
    success|failure|cancelled|skipped|timed_out|neutral|action_required|stale|null) printf '%s' "$1" ;;
    *) printf 'unrecognized' ;;
  esac
}
_unreadable() {
  echo "::error::source-run-gate: could not evaluate the jobs of run ${rid}; cannot decide whether the pin rotated (fail closed)."
  exit 1
}
# _q VAR JOB APPLY FILTER -> VAR = FILTER over every job object named exactly JOB. A checked
# assignment in this shell: a jq failure exits 1 here instead of reading as an empty value.
_q() {
  local __r
  __r="$(jq -r --arg j "$2" --arg s "$3" ".jobs[] | objects | select(.name == \$j) | $4" <<<"$doc")" || _unreadable
  printf -v "$1" '%s' "$__r"
}
# _count VAR VALUE -> VAR = VALUE, which must be a plain number (else fail closed).
_count() { [[ "$2" =~ ^[0-9]+$ ]] || _unreadable; printf -v "$1" '%s' "$2"; }

declare -A V=() JC=() AL=()  # per job: verdict, allowlisted job conclusion, apply label
grade() {  # grade JOB APPLY_STEP_NAME -> V/JC/AL[JOB]
  local j="$1" s="$2" cnt st n raw a v jc
  cnt="$(jq --arg j "$j" '[.jobs[] | objects | select(.name == $j)] | length' <<<"$doc")" || _unreadable
  _count cnt "$cnt"
  if (( cnt == 0 )); then V[$j]=not_run; JC[$j]=absent; AL[$j]=none; return; fi
  if (( cnt > 1 )); then v=unidentified; V[$j]=$v; JC[$j]="duplicated_${cnt}"; AL[$j]=none; return; fi
  _q jc "$j" "$s" '.conclusion'
  JC[$j]="$(allow "$jc")"
  _q st "$j" "$s" 'if (.steps | type) == "array" then (.steps | length | tostring) else "none" end'
  # shellcheck disable=SC2016  # $s is the jq variable bound by _q's --arg, not a shell expansion
  _q n "$j" "$s" 'if (.steps | type) == "array" then [.steps[] | objects | select(.name == $s)] | length else 0 end'
  _count n "$n"
  # shellcheck disable=SC2016  # as above
  _q raw "$j" "$s" '[(.steps | if type == "array" then .[] else empty end) | objects | select(.name == $s)] | .[0].conclusion'
  a="$(allow "$raw")"
  if (( n == 0 )); then AL[$j]=not_found; elif (( n > 1 )); then AL[$j]="matched_${n}"; else AL[$j]="$a"; fi
  if [[ "${JC[$j]}" == absent || "${JC[$j]}" == skipped ]]; then v=not_run
  elif [[ "${JC[$j]}" != success && "$st" == 0 ]]; then v=not_run
  elif [[ "${JC[$j]}" == success ]]; then
    case "$n:$a" in 1:success) v=rotated ;; 1:skipped) v=no_apply ;; *) v=unidentified ;; esac
  else
    case "$n:$a" in 1:skipped) v=no_apply ;; 1:success) v=pin_published ;; *) v=pin_maybe_published ;; esac
  fi
  [[ "$v" == not_run ]] && AL[$j]=none
  V[$j]=$v
}
grade "$BIRTH_JOB" "$BIRTH_APPLY"
grade "$REPLACE_JOB" "$REPLACE_APPLY"
# Only the constants and allowlisted values below; never an API-supplied name.
tokens="${BIRTH_JOB}=${JC[$BIRTH_JOB]:-absent} ${BIRTH_JOB}.apply=${AL[$BIRTH_JOB]:-none} ${REPLACE_JOB}=${JC[$REPLACE_JOB]:-absent} ${REPLACE_JOB}.apply=${AL[$REPLACE_JOB]:-none}"

bad=""; src=""; pub=false; warn=false; skipped_apply=false
for j in "${JOBS[@]}"; do
  [[ "${V[$j]}" == unidentified ]] && bad="${bad:+$bad, }$j"
  [[ "${V[$j]}" == rotated && -z "$src" ]] && src="$j"
  [[ "${V[$j]}" == pin_published ]] && pub=true  # the pin WAS published (5a), not merely may be
  [[ "${V[$j]}" == pin_published || "${V[$j]}" == pin_maybe_published ]] && warn=true
  [[ "${V[$j]}" == no_apply ]] && skipped_apply=true
done

if [[ -n "$bad" ]]; then
  echo "::error::source-run-gate: in run ${rid} ${tokens}: ${bad} concluded success but its apply step could not be identified exactly once, or carries a conclusion impossible for a green job, or the job is duplicated; cannot decide whether the pin rotated (fail closed). verdict=unidentified. Fix: make BIRTH_APPLY / REPLACE_APPLY in .github/actions/dispatch-web-redeploy/source-run-gate.sh equal the name: of the id: apply step in apply-web-platform-infra.yml on main (or restore that step name). To decide whether the pin rotated: a matching line from \`gh run view ${rid} --log | grep -E 'fingerprint: SHA256:[A-Za-z0-9+/]{43}'\` proves it did (its absence proves nothing); when in doubt redeploy, which is idempotent: dispatch git-data-pin-redeploy.yml with NO source_run_id (${REDEPLOY_CMD})."
  exit 1
fi
if [[ -n "$src" ]]; then
  echo "::notice::source-run-gate: in run ${rid} ${tokens}: ${src} and its apply step concluded success; the pin rotated — redeploying. verdict=rotated"
  _emit "proceed=true" "source_job=${src}" "pin_published=false"
  exit 0
fi
if [[ "$warn" == true ]]; then
  if [[ "$pub" == true ]]; then
    if [[ "${V[$REPLACE_JOB]}" == pin_published ]]; then
      how="Start with a read, never a second replace: runbook git-data-luks-cutover-5274.md section \"If the fresh host fails a boot check after step 3\". To put the app on the new pin, dispatch git-data-pin-redeploy.yml with NO source_run_id (${REDEPLOY_CMD})"
    else
      how="A birth cannot be repeated: the only recovery is to dispatch git-data-pin-redeploy.yml with NO source_run_id (${REDEPLOY_CMD})"
    fi
    echo "::warning::source-run-gate: in run ${rid} ${tokens}: the apply step succeeded, so the new pin was published, but the job is red — the app was NOT redeployed and erasures fail host_key_mismatch until it is. verdict=pin_published. ${how}; passing source_run_id=${rid} would re-read this same red job and skip again."
    _summary "- ${tokens} in run ${rid}: verdict=pin_published — the pin was published but the app was not redeployed. ${how}."
  else
    echo "::warning::source-run-gate: in run ${rid} ${tokens}: the apply may have published the new pin before failing — pin may be published. verdict=pin_maybe_published. Dispatch git-data-pin-redeploy.yml with NO source_run_id (${REDEPLOY_CMD}) to redeploy unconditionally — passing source_run_id=${rid} would re-read this same non-success and skip again."
    _summary "- ${tokens} in run ${rid}: verdict=pin_maybe_published — pin may be published; dispatch git-data-pin-redeploy.yml with NO source_run_id (${REDEPLOY_CMD}) to redeploy unconditionally."
  fi
  _emit "proceed=false" "source_job=" "pin_published=${warn}"
  exit 0
fi
if [[ "$skipped_apply" == true ]]; then
  echo "::notice::source-run-gate: no redeploy — no apply ran in run ${rid} (a plan_only rehearsal, or the job stopped before apply), so the host-key pin is unchanged. ${tokens}. verdict=no_apply"
else
  echo "::notice::source-run-gate: no redeploy — in run ${rid} neither git-data job ran a step. ${tokens}; the host-key pin only rotates when a job's apply step succeeds. verdict=not_run"
fi
_emit "proceed=false" "source_job=" "pin_published=false"
