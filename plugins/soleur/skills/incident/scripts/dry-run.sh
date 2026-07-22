#!/usr/bin/env bash
# Dry-run harness for /soleur:incident (#2725, plan Step 4 / AC8-AC13).
#
# Reads a synthetic incident fixture (JSON) and emits the skill's Phase 0-8
# output stream to stdout. Never writes to runbooks/. Never invokes
# compound-capture (emits a marker line instead).
#
# Designed so plan ACs are greppable against the captured output:
#   out=$(mktemp -t pir-dry-run.XXXXXXXX.txt)
#   bash scripts/dry-run.sh test/fixtures/dry-run-incident.json > "$out"; echo "OUT=$out"
#
# Synthetic-only — fixtures must contain no real production credentials
# (`cq-test-fixtures-synthesized-only`).
set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: dry-run.sh <fixture.json>" >&2
  exit 2
fi

FIXTURE="$1"

if [[ ! -r "${FIXTURE}" ]]; then
  echo "dry-run: fixture not readable: ${FIXTURE}" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../../.." && pwd)"

SENTINEL="${SKILL_DIR}/scripts/redact-sentinel.sh"
TEMPLATE="${SKILL_DIR}/templates/pir.md"

# --- Parse fixture ---
title=$(jq -r '.title' "${FIXTURE}")
detected_at=$(jq -r '.detected_at' "${FIXTURE}")
symptom=$(jq -r '.symptom' "${FIXTURE}")
suspected_change=$(jq -r '.suspected_change' "${FIXTURE}")
affected_count=$(jq -r '.affected_user_count' "${FIXTURE}")
threshold_in=$(jq -r '.brand_survival_threshold' "${FIXTURE}")
risk=$(jq -r '.art_33.risk_to_subjects' "${FIXTURE}")
categories=$(jq -r '.art_33.data_categories_breached | join(",")' "${FIXTURE}")
triggers_csv=$(jq -r '.triggers | join(",")' "${FIXTURE}")
status_in=$(jq -r '.status' "${FIXTURE}")

# New operator-supplied fields (merged-template shape). Defaults mirror SKILL.md Phase 0.
recovery_at=$(jq -r '.recovery_at // ""' "${FIXTURE}")
monitoring_detected_at=$(jq -r '.monitoring_detected_at // ""' "${FIXTURE}")
detection_method=$(jq -r '.detection_method // "manual"' "${FIXTURE}")
triggered_by=$(jq -r '.triggered_by // "system"' "${FIXTURE}")
incident_overview=$(jq -r '.incident_overview // "TBD"' "${FIXTURE}")
resolution=$(jq -r '.resolution // "TBD"' "${FIXTURE}")
participants=$(jq -r '.participants // "Operator (single founder)"' "${FIXTURE}")
version_triggered=$(jq -r '.version_triggered // "TBD"' "${FIXTURE}")
version_restored=$(jq -r '.version_restored // "N/A — not yet restored"' "${FIXTURE}")
services_impacted=$(jq -r '.services_impacted // "TBD"' "${FIXTURE}")
revenue_impact=$(jq -r '.revenue_impact // "Unknown / N/A"' "${FIXTURE}")
team_impact=$(jq -r '.team_impact // "Unknown / N/A"' "${FIXTURE}")

# --- LLM-trust boundary validation (FR7) ---
if ! [[ "${detected_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "dry-run: detected_at fails ISO-8601 regex: ${detected_at}" >&2
  exit 2
fi
# recovery_at / monitoring_detected_at are OPTIONAL but, when present, MUST match the
# same regex before any duration arithmetic (FR7 — never trust an LLM-emitted duration).
ISO_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if [[ -n "${recovery_at}" ]] && ! [[ "${recovery_at}" =~ ${ISO_RE} ]]; then
  echo "dry-run: recovery_at fails ISO-8601 regex: ${recovery_at}" >&2
  exit 2
fi
if [[ -n "${monitoring_detected_at}" ]] && ! [[ "${monitoring_detected_at}" =~ ${ISO_RE} ]]; then
  echo "dry-run: monitoring_detected_at fails ISO-8601 regex: ${monitoring_detected_at}" >&2
  exit 2
fi

# --- MTTR / MTTD local computation (FR7 — never an LLM-emitted duration) ---
# The ISO regex above gates FORMAT but not calendar validity (it accepts month 13,
# day 40, hour 25), so `date -u -d` can still reject a regex-passing value. Capture
# the epoch with explicit failure handling (mirrors the Art. 33 deadline guard below)
# and fail loud rather than emitting a garbage/empty duration with a green exit.
iso_to_epoch() {
  local ts="$1" epoch
  if ! epoch=$(date -u -d "${ts}" +%s 2>/dev/null); then
    echo "dry-run: timestamp not a valid calendar date: ${ts}" >&2
    exit 2
  fi
  printf '%s' "${epoch}"
}
fmt_duration() {  # signed-safe: only ever called with a non-negative second count
  printf '%dh%dm' $(( $1 / 3600 )) $(( ($1 % 3600) / 60 ))
}
if [[ -n "${recovery_at}" ]]; then
  mttr_secs=$(( $(iso_to_epoch "${recovery_at}") - $(iso_to_epoch "${detected_at}") ))
  if (( mttr_secs < 0 )); then
    echo "dry-run: recovery_at (${recovery_at}) precedes detected_at (${detected_at}) — transposed timestamps" >&2
    exit 2
  fi
  MTTR=$(fmt_duration "${mttr_secs}")
else
  MTTR="TBD (status not resolved)"
fi
if [[ "${detection_method}" == "monitoring" && -n "${monitoring_detected_at}" ]]; then
  mttd_secs=$(( $(iso_to_epoch "${monitoring_detected_at}") - $(iso_to_epoch "${detected_at}") ))
  if (( mttd_secs < 0 )); then
    echo "dry-run: monitoring_detected_at (${monitoring_detected_at}) precedes detected_at (${detected_at}) — transposed timestamps" >&2
    exit 2
  fi
  MTTD=$(fmt_duration "${mttd_secs}")
else
  MTTD="Unknown (external/manual report)"
fi

# Local slug computation (never accept slug from LLM).
slug=$(printf '%s\n' "${title}" | awk '{ gsub(/[^a-zA-Z0-9]+/, "-"); print tolower($0) }' | sed 's/^-//;s/-$//')

# --- First-pass redaction sentinel on ALL operator-supplied fields (FR7) ---
# MUST run BEFORE any echo to the transcript (Phase 0/3 below echo several of these
# fields). Covers every operator-controlled free-text/identifier field that later
# reaches the draft OR is echoed to stdout — including triggers_csv (echoed in
# Phase 3) and the version_* fields. The Phase 6 scan-on-draft is the second pass.
early_input_check=$(mktemp)
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
  "${title}" "${symptom}" "${suspected_change}" \
  "${incident_overview}" "${participants}" "${resolution}" \
  "${services_impacted}" "${revenue_impact}" "${team_impact}" \
  "${version_triggered}" "${version_restored}" \
  "${detection_method}" "${triggered_by}" > "${early_input_check}"
printf '%s\n' "${triggers_csv//,/$'\n'}" >> "${early_input_check}"
if ! bash "${SENTINEL}" "${early_input_check}" >/dev/null 2>&1; then
  echo "sentinel: FAIL on operator-supplied input fields (first pass, pre-echo)" >&2
  bash "${SENTINEL}" "${early_input_check}" >&2 2>&1 || true
  rm -f "${early_input_check}"
  echo "[dry-run] BLOCKING — redact operator-supplied input before re-running." >&2
  exit 1
fi
rm -f "${early_input_check}"

# --- Phase 0 ---
echo "=== Phase 0: facts captured ==="
echo "  title:               ${title}"
echo "  detected_at:         ${detected_at}"
echo "  symptom:             ${symptom}"
echo "  suspected_change:    ${suspected_change}"
echo "  affected_user_count: ${affected_count}"
echo "  slug (local-computed): ${slug}"
echo

# --- Phase 1: classification with decision criteria INLINE before confirm (AC9) ---
echo "=== Phase 1: brand_survival_threshold classification ==="
echo "Decision criteria (rendered inline BEFORE confirm — AC9):"
echo "  criterion 1 (none):              no user-facing artifact, no credential surface, no billing path"
echo "  criterion 2 (single-user incident): one real user impacted OR sensitive-data surface at risk"
echo "  criterion 3 (aggregate pattern): repeated or systemic impact across users / tenants"
echo
echo "brand_survival_threshold (advisory): ${threshold_in}"
echo "  reason: affected_user_count=${affected_count}, risk_to_subjects=${risk}, data_categories_breached=[${categories}]"
echo "  [dry-run] operator confirms advisory (no override)"
echo

# --- Phase 2: Art. 33/34 gate with parity blocking (AC12) ---
echo "=== Phase 2: GDPR Art. 33 / 34 gate ==="
art_33="false"
art_34="false"
if [[ -n "${categories}" && "${risk}" != "none" ]]; then
  art_33="true"
fi
if [[ "${risk}" == "high" ]]; then
  art_34="true"
fi

# Compute Art. 33 deadline (detected_at + 72h)
art_33_deadline=""
if [[ "${art_33}" == "true" ]]; then
  art_33_deadline=$(date -u -d "${detected_at} +72 hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "TBD")
fi

echo "  art_33_triggered: ${art_33}"
echo "  art_34_triggered: ${art_34}"
echo "  art_33_deadline:  ${art_33_deadline}"
if [[ "${art_33}" == "true" ]]; then
  echo
  echo "Art. 33 triggered. CNIL notification deadline: ${art_33_deadline}."
  echo "Confirm notification path acknowledged (type ACK-ART33 to proceed)."
  echo "  [dry-run] ACK-ART33 confirmed"
fi
if [[ "${art_34}" == "true" ]]; then
  echo
  echo "Art. 34 triggered (risk_to_subjects=high). Direct subject notification \"without undue delay\" — no fixed numeric deadline."
  echo "Confirm subject-notification path acknowledged (type ACK-ART34 to proceed)."
  echo "  [dry-run] ACK-ART34 confirmed"
fi
echo

# --- Phase 3: runbook routing (dry-run prints would-be matches) ---
echo "=== Phase 3: runbook routing ==="
runbook_dir="${REPO_ROOT}/knowledge-base/engineering/operations/runbooks"
if [[ -d "${runbook_dir}" ]]; then
  echo "  [dry-run] selected triggers (from fixture): ${triggers_csv}"
else
  echo "  no runbook directory at ${runbook_dir} — proceed ad-hoc"
fi
echo

# --- Phase 4: PIR scaffold via sed-substitute ---
echo "=== Phase 4: PIR scaffold ==="

# Render triggers as YAML list items
triggers_yaml=""
IFS=',' read -ra trig_arr <<< "${triggers_csv}"
for t in "${trig_arr[@]}"; do
  [[ -z "${t}" ]] && continue
  triggers_yaml+="  - ${t}"$'\n'
done
# Strip trailing newline
triggers_yaml="${triggers_yaml%$'\n'}"

# Secret-leak preamble (TR2): triggers contain api_key_leaked / credentials_exposed / token_exposed / secret_in_logs?
secret_leak_preamble=""
case ",${triggers_csv}," in
  *,api_key_leaked,*|*,credentials_exposed,*|*,token_exposed,*|*,secret_in_logs,*)
    secret_leak_preamble=$(cat <<'EOF'
## Step 0: REVOKE FIRST

Before any forensic work, revoke the leaked credential at the issuer:
- Stripe: dashboard → API keys → roll
- Supabase: dashboard → API → reset
- Doppler: rotate via `doppler secrets rotate`
- GitHub: Settings → Tokens → revoke
- Anthropic / OpenAI / Vercel / Cloudflare: equivalent dashboard rotation

Per learning 2026-02-10-api-key-leaked-in-git-history-cleanup.md.
EOF
)
    ;;
esac

draft_file=$(mktemp)
sentinel_out=$(mktemp)
trap 'rm -f "${draft_file}" "${sentinel_out}"' EXIT

# Numeric extraction for incident_pr (FR7 validation). Prefer an explicit `#NNNN`
# token over any leading numeric fragment so prose like "see #3721 (replaces #2725)"
# resolves to 3721, not e.g. a date fragment. Falls back to first numeric only when
# no `#NNNN` is found (covers "PR 3704 broke X" shape).
incident_pr=$(printf '%s\n' "${suspected_change}" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
if [[ -z "${incident_pr}" ]]; then
  incident_pr=$(printf '%s\n' "${suspected_change}" | grep -oE '[0-9]+' | head -1)
fi
incident_pr="${incident_pr:-0}"

today=$(date -u +%Y-%m-%d)

# Build the draft. Use a here-doc instead of sed so we do not have to escape
# every special character in the variables.
{
  cat <<EOF
---
title: "${title}"
date: ${today}
incident_pr: ${incident_pr}
incident_window: "${detected_at} → ${recovery_at:-TBD}"
recovery_at: "${recovery_at:-TBD}"
suspected_change: "${suspected_change}"
brand_survival_threshold: ${threshold_in}
status: open
triggers:
${triggers_yaml}
art_33_triggered: ${art_33}
art_34_triggered: ${art_34}
art_33_deadline: "${art_33_deadline}"
---

## Actor key

- agent
- agent-with-ack
- human

${secret_leak_preamble}

# Incident Overview

${incident_overview}

## Status

open — one of resolved / unresolved but ended / ongoing. Mirrors the status: frontmatter.

## Symptom

${symptom}

## Incident Timeline

- Start time (detected): ${detected_at}
- End time (recovered): ${recovery_at:-TBD}
- Duration (MTTR): ${MTTR}

| Actor | Time (UTC) | Action |
|---|---|---|
| human | ${detected_at} | Incident detected. |

## Participants and Systems Involved

${participants}

## Detection (+ MTTD)

- How detected: ${detection_method} — monitoring system vs. external/manual report.
- MTTD (mean time to detect): ${MTTD}

## Triggered by

${triggered_by} — one of user / system / market movement / provider.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Resolution

${resolution}

## Recovery verification

TBD.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

TBD

## Versions of Components

- Version(s) that triggered the outage: ${version_triggered}
- Version(s) that restored the service: ${version_restored}

## Impact details

### Services Impacted

${services_impacted}

### Customer Impact (by role)

- Prospect: TBD
- Authenticated app user: TBD
- Legal-document signer: TBD
- Admin via Access: TBD
- Billing customer: TBD
- OAuth installation owner: TBD

### Revenue Impact

${revenue_impact}

### Team Impact

${team_impact}

## Lessons Learned

### Where we got lucky

TBD

### What went well

TBD

### What went wrong

TBD

## Action Items & Follow-ups

Each row MUST cite a filed GitHub issue (#NNNN). If none, replace the table with:
_No action items — incident fully resolved in the source PR with no residual work._

| Issue | Action | Status |
|---|---|---|
| #TBD | TBD | open |
EOF
} > "${draft_file}"

echo "  draft scaffolded to tmp file (not yet emitted inline)"
echo "  template source: ${TEMPLATE}"
echo

# --- Phase 5: deferred public summary ---
echo "=== Phase 5: public summary ==="
echo "Public-safe PIR summary deferred to #3732 (opens after first real customer-impact incident)."
echo

# --- Phase 6: sentinel BEFORE Phase 7 inline-emit (AC10 ordering) ---
echo "=== Phase 6: redaction sentinel (pre-inline-emit) ==="
# The first-pass scan on operator-supplied input ran pre-echo near the top of the
# script (before Phase 0/3 echoed any field). This Phase 6 pass scans the fully
# scaffolded draft — the second, on-draft sentinel pass.
if bash "${SENTINEL}" "${draft_file}" >"${sentinel_out}" 2>&1; then
  echo "sentinel: pass"
else
  rc=$?
  echo "sentinel: FAIL on draft (exit ${rc})"
  cat "${sentinel_out}"
  echo "[dry-run] BLOCKING — operator would iterate. Halting dry-run."
  exit 1
fi
echo

# --- Phase 7: commit gate (literal COMMIT-PIR token only) ---
echo "=== Phase 7: operator review + commit ==="
echo "<draft begins>"
cat "${draft_file}"
echo "<draft ends>"
echo
echo "To commit, type exactly: COMMIT-PIR"
echo "Anything else (yes, y, ok, approved, looks good) is REJECTED."
echo "  [dry-run] commit-token examples:"
echo "    input 'yes'        → REJECTED. Type exactly: COMMIT-PIR"
echo "    input 'y'          → REJECTED. Type exactly: COMMIT-PIR"
echo "    input 'ok'         → REJECTED. Type exactly: COMMIT-PIR"
echo "    input 'approved'   → REJECTED. Type exactly: COMMIT-PIR"
echo "    input 'COMMIT-PIR' → would write knowledge-base/engineering/operations/post-mortems/${slug}-postmortem.md"
echo

# --- Phase 8: status: resolved gate + compound-capture handoff (AC13) ---
echo "=== Phase 8: compound-capture handoff ==="
if [[ "${status_in}" != "resolved" ]]; then
  echo "Phase 8 requires PIR status: resolved. Current: ${status_in}."
  echo "[dry-run] exits non-zero here in real flow; continuing dry-run to satisfy capture-all-phases mode."
else
  echo "PIR status: resolved — emitting closed-PIR body inline (compound-capture transcript-scrape will pick it up)"
  echo "<closed-pir begins>"
  cat "${draft_file}"
  echo "<closed-pir ends>"
  echo
  echo "Invoking: skill: soleur:compound-capture --headless"
fi

exit 0
