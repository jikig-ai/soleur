#!/usr/bin/env bash
# Dry-run harness for /soleur:incident (#2725, plan Step 4 / AC8-AC13).
#
# Reads a synthetic incident fixture (JSON) and emits the skill's Phase 0-8
# output stream to stdout. Never writes to runbooks/. Never invokes
# compound-capture (emits a marker line instead).
#
# Designed so plan ACs are greppable against the captured output:
#   bash scripts/dry-run.sh test/fixtures/dry-run-incident.json > /tmp/pir-dry-run.txt
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

# --- LLM-trust boundary validation (FR7) ---
if ! [[ "${detected_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "dry-run: detected_at fails ISO-8601 regex: ${detected_at}" >&2
  exit 2
fi

# Local slug computation (never accept slug from LLM).
slug=$(printf '%s\n' "${title}" | awk '{ gsub(/[^a-zA-Z0-9]+/, "-"); print tolower($0) }' | sed 's/^-//;s/-$//')

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
runbook_dir="${REPO_ROOT}/knowledge-base/engineering/ops/runbooks"
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
incident_window: "${detected_at} → TBD"
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

## Symptom

${symptom}

## Root-cause hypothesis

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | ${detected_at} | Incident detected. |

## Recovery verification

TBD.

## Follow-ups

- [ ] TBD

## Who was affected (by role)

- Prospect: TBD
- Authenticated app user: TBD
- Legal-document signer: TBD
- Admin via Access: TBD
- Billing customer: TBD
- OAuth installation owner: TBD
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
# Also sentinel-scan the operator-supplied input fields BEFORE the draft is
# scaffolded — covers the user-impact-reviewer finding that operator-pasted
# log fragments in symptom/suspected_change would otherwise reach the Phase 4
# draft via sed-substitution without an earlier scan in dry-run/headless mode.
input_check=$(mktemp)
printf '%s\n%s\n%s\n' "${symptom}" "${suspected_change}" "${title}" > "${input_check}"
if ! bash "${SENTINEL}" "${input_check}" >"${sentinel_out}" 2>&1; then
  echo "sentinel: FAIL on operator-supplied fields (symptom/suspected_change/title)"
  cat "${sentinel_out}"
  rm -f "${input_check}"
  echo "[dry-run] BLOCKING — redact operator-supplied input before re-running."
  exit 1
fi
rm -f "${input_check}"

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
echo "    input 'COMMIT-PIR' → would write knowledge-base/engineering/ops/runbooks/${slug}-postmortem.md"
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
