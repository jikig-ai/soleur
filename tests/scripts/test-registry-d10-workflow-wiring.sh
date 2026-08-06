#!/usr/bin/env bash
# Wiring gate: the D10 arms of `registry-luks-recut` must derive APP_DOMAIN_BASE from committed
# Terraform config, not from a Doppler secret that exists nowhere.
#
# ── THE DEFECT THIS PINS ────────────────────────────────────────────────────────────────────
# Both D10 arms read `doppler secrets get APP_DOMAIN_BASE -p soleur -c prd` with no fallback and
# failed closed on empty. That secret exists in NO config of the `soleur` project — measured
# 2026-08-06 across all 13. So the gate aborted at PREPARE before reaching its own destroy-guard,
# and the dispatch was unfireable during exactly the incident it exists to recover from.
#
# The unit suite (scripts/derive-app-domain-base.test.sh) proves the derivation is correct. It
# cannot prove the workflow USES it — that is this file's job, and the absence of such a gate is
# why the original bug survived: a `run:` body is not testable, so nothing ever executed it.
#
# ── WHY A SEPARATE FILE ─────────────────────────────────────────────────────────────────────
# NOT appended to tests/scripts/test-registry-pull-path-health.sh. The mutation battery sandboxes
# that suite into a tree with no `.github/` directory, so workflow-reading rows would go RED in
# the battery's own baseline and `harness_die` it (exit 2, no verdict) — converting a real safety
# net into a harness fault.
#
# ── HARNESS NOTES ───────────────────────────────────────────────────────────────────────────
# Comments are stripped before every assertion: a bare-token grep over a YAML body matches the
# explanatory prose describing the very construct under test, which is how a drift guard goes
# vacuously green. Assertions use herestrings rather than `producer | grep -q`, because under
# `pipefail` an early match makes the producer take SIGPIPE (141) and a NEGATIVE assertion then
# fails OPEN. A vacuity floor runs first — every content assertion below is meaningless if the
# extractor returned an empty body.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOW="${ROOT}/.github/workflows/apply-web-platform-infra.yml"
DERIVE="${ROOT}/scripts/derive-app-domain-base.sh"

passes=0
fails=0
_report() {
  if [[ "$2" == "ok" ]]; then passes=$((passes + 1)); printf '  ok   %s\n' "$1"
  else fails=$((fails + 1)); printf '  FAIL %s%s\n' "$1" "${3:+ — $3}"; fi
}

[[ -f "$WORKFLOW" ]] || { printf 'harness: workflow not found at %s\n' "$WORKFLOW" >&2; exit 2; }

# Extract a step body by its `- name:` line, up to the next `- name:` at the same indent,
# comments stripped.
_step_body() {
  awk -v want="$1" '
    index($0, "      - name: " want) == 1 { inb = 1; print; next }
    inb && /^      - name: / { inb = 0 }
    inb { print }
  ' "$WORKFLOW" | grep -vE '^[[:space:]]*#'
}

# Extract a whole job body (jobs sit at 2-space indent), comments stripped.
_job_body() {
  awk -v want="$1" '
    index($0, "  " want ":") == 1 { inb = 1; print; next }
    inb && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { inb = 0 }
    inb { print }
  ' "$WORKFLOW" | grep -vE '^[[:space:]]*#'
}

PREPARE_BODY="$(_step_body 'Derive restore inventory (D10 PREPARE)')"
VERDICT_BODY="$(_step_body 'Pre-destroy authorization gate (D10 VERDICT)')"

# ── W1: vacuity floor ───────────────────────────────────────────────────────────────────────
# Runs FIRST. If either extractor silently returned nothing (a renamed step, a changed indent),
# every assertion below would pass against an empty string and this gate would certify nothing.
w1_ok=1
[[ -n "$PREPARE_BODY" ]] || { _report "W1 PREPARE step body extracts non-empty" fail "extractor returned empty — step renamed or re-indented?"; w1_ok=0; }
[[ -n "$VERDICT_BODY" ]] || { _report "W1 VERDICT step body extracts non-empty" fail "extractor returned empty — step renamed or re-indented?"; w1_ok=0; }
if [[ "$w1_ok" -eq 1 ]]; then
  _report "W1 vacuity floor: both D10 step bodies extract non-empty" ok
else
  printf '\n=== %d passed, %d failed (vacuity floor failed — later rows are not meaningful) ===\n' "$passes" "$fails"
  exit 1
fi

# ── W2/W3/W5: shared properties, asserted as ONE loop over both bodies ──────────────────────
for arm in PREPARE VERDICT; do
  body="$PREPARE_BODY"
  [[ "$arm" == "VERDICT" ]] && body="$VERDICT_BODY"

  # W2 — calls the shared derivation exactly once.
  n=$(grep -cE 'scripts/derive-app-domain-base\.sh' <<<"$body")
  if [[ "$n" -eq 1 ]]; then
    _report "W2 ${arm} calls derive-app-domain-base.sh exactly once" ok
  else
    _report "W2 ${arm} calls derive-app-domain-base.sh exactly once" fail "found ${n}"
  fi

  # W3 — exports the value and retains a fail-closed abort on empty.
  if grep -qE '^[[:space:]]*export APP_DOMAIN_BASE[[:space:]]*$' <<<"$body"; then
    _report "W3 ${arm} exports APP_DOMAIN_BASE on its own line" ok
  else
    _report "W3 ${arm} exports APP_DOMAIN_BASE on its own line" fail "no bare 'export APP_DOMAIN_BASE' line"
  fi
  if grep -qE '\[\[ -z "\$APP_DOMAIN_BASE" \]\]|if \[\[ -z "\$APP_DOMAIN_BASE" \]\]' <<<"$body" \
     && grep -qE '^[[:space:]]*exit 1[[:space:]]*$' <<<"$body"; then
    _report "W3 ${arm} retains a fail-closed abort on an empty derivation" ok
  else
    _report "W3 ${arm} retains a fail-closed abort on an empty derivation" fail "missing -z guard or exit 1"
  fi

  # W5 — the bare-assignment form, and the errexit that makes it propagate.
  # `export X=$(cmd)` exits 0 even when cmd fails; that single character of difference is what
  # turns this fail-closed chain fail-open, so it is asserted as a NEGATIVE on the export form.
  if grep -qE 'export[[:space:]]+APP_DOMAIN_BASE=\$\(' <<<"$body"; then
    _report "W5 ${arm} uses the bare-assignment form (no export X=\$(...))" fail "found 'export APP_DOMAIN_BASE=\$(' — exit status is swallowed"
  else
    _report "W5 ${arm} uses the bare-assignment form (no export X=\$(...))" ok
  fi
  if grep -qE '^[[:space:]]*APP_DOMAIN_BASE=\$\(bash ' <<<"$body"; then
    _report "W5 ${arm} assigns from a bash invocation of the script" ok
  else
    _report "W5 ${arm} assigns from a bash invocation of the script" fail "no bare 'APP_DOMAIN_BASE=\$(bash ' assignment"
  fi
  if grep -qE '^[[:space:]]*set -euo pipefail[[:space:]]*$' <<<"$body"; then
    _report "W5 ${arm} body opens under set -euo pipefail" ok
  else
    _report "W5 ${arm} body opens under set -euo pipefail" fail "without errexit the assignment does not propagate the failure"
  fi
done

# ── W4: residual-zero across the RECUT CHAIN, workflow AND composite actions ────────────────
# Scoping this to the workflow alone would leave a hole the exact shape of the bug, because the
# recut's own restore leg runs inside a composite action.
#
# ALLOWLIST — deliberately enumerated and commented so each exclusion is visible rather than
# accidental. Both entries are OUT of the recut chain and deferred to D4:
#   * cf-tunnel-ssh-bridge/action.yml  — derives ssh.<base>; not invoked by this dispatch.
#   * "Resolve known-good image digest off-host" — the web-host birth/replace sites. Their
#     conversion was deliberately cut from this change (a host replace is a live possibility
#     during this incident), so a blanket residual-zero here would false-fail on work that was
#     scoped out on purpose.
declare -a ALLOWED_FILES=( "cf-tunnel-ssh-bridge/action.yml" )
declare -a ALLOWED_WORKFLOW_STEPS=( "Resolve known-good image digest off-host" )

# Enumerate every surviving dark read across the workflow + composite actions.
violations=""
scan_targets="$(find "${ROOT}/.github/actions" -name 'action.yml' 2>/dev/null; printf '%s\n' "$WORKFLOW")"
scanned=0
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  scanned=$((scanned + 1))
  skip=0
  for a in "${ALLOWED_FILES[@]}"; do
    [[ "$f" == *"$a" ]] && skip=1
  done
  [[ "$skip" -eq 1 ]] && continue

  # Comment-stripped, so prose describing the old read cannot register as a violation.
  hits="$(grep -vE '^[[:space:]]*#' "$f" | grep -nE 'doppler secrets get APP_DOMAIN_BASE' || true)"
  [[ -z "$hits" ]] && continue

  if [[ "$f" == "$WORKFLOW" ]]; then
    # Attribute each workflow hit to its owning step, and drop the allowlisted steps.
    unattributed="$(awk -v pat='doppler secrets get APP_DOMAIN_BASE' '
      /^      - name: / { step = substr($0, index($0, "- name: ") + 8) }
      $0 ~ /^[[:space:]]*#/ { next }
      index($0, pat) > 0 { print NR "\t" step }
    ' "$f")"
    while IFS=$'\t' read -r lineno step; do
      [[ -n "$lineno" ]] || continue
      allowed=0
      for s in "${ALLOWED_WORKFLOW_STEPS[@]}"; do
        [[ "$step" == *"$s"* ]] && allowed=1
      done
      [[ "$allowed" -eq 1 ]] && continue
      violations+="${f}:${lineno} (step: ${step})"$'\n'
    done <<<"$unattributed"
  else
    violations+="${f}: ${hits}"$'\n'
  fi
done <<<"$scan_targets"

if [[ "$scanned" -lt 2 ]]; then
  _report "W4 scan covered the workflow and composite actions" fail "only ${scanned} file(s) scanned — the find produced nothing"
else
  _report "W4 scan covered ${scanned} files (workflow + composite actions)" ok
fi

if [[ -z "$violations" ]]; then
  _report "W4 residual-zero: no un-allowlisted 'doppler secrets get APP_DOMAIN_BASE' in the recut chain" ok
else
  _report "W4 residual-zero" fail "surviving dark reads:"$'\n'"${violations}"
fi

# The allowlist must not rot into a permanent silent exemption: if a D4 conversion lands and the
# entry stops matching anything, this row goes RED so the exclusion is deleted rather than kept.
for a in "${ALLOWED_FILES[@]}"; do
  match="$(find "${ROOT}/.github/actions" -path "*${a}" 2>/dev/null | head -1)"
  if [[ -n "$match" ]] && grep -qE 'doppler secrets get APP_DOMAIN_BASE' "$match"; then
    _report "W4 allowlist entry '${a}' still describes a real deferred read" ok
  else
    _report "W4 allowlist entry '${a}' is stale" fail "no matching dark read — remove the exemption (D4 has landed)"
  fi
done
allow_step_live=0
for s in "${ALLOWED_WORKFLOW_STEPS[@]}"; do
  c=$(awk -v pat='doppler secrets get APP_DOMAIN_BASE' -v want="$s" '
    /^      - name: / { step = substr($0, index($0, "- name: ") + 8) }
    $0 ~ /^[[:space:]]*#/ { next }
    index($0, pat) > 0 && index(step, want) > 0 { n++ }
    END { print n + 0 }
  ' "$WORKFLOW")
  if [[ "$c" -gt 0 ]]; then
    allow_step_live=$((allow_step_live + 1))
    _report "W4 allowlisted step '${s}' still carries ${c} deferred read(s)" ok
  else
    _report "W4 allowlisted step '${s}' is stale" fail "no matching dark read — remove the exemption (D4 has landed)"
  fi
done

# ── W6: DOPPLER_TOKEN_PRD is gone from the D10 gate job ─────────────────────────────────────
# Scoped to the job, not the file: the token is legitimately used by registry_store_restore.
GATE_JOB="$(_job_body 'registry_pull_path_gate')"
if [[ -z "$GATE_JOB" ]]; then
  _report "W6 registry_pull_path_gate job body extracts non-empty" fail "extractor returned empty"
else
  _report "W6 registry_pull_path_gate job body extracts non-empty" ok
  if grep -qE 'DOPPLER_TOKEN_PRD' <<<"$GATE_JOB"; then
    _report "W6 DOPPLER_TOKEN_PRD absent from the D10 gate job" fail "still referenced — the credential the derivation removed"
  else
    _report "W6 DOPPLER_TOKEN_PRD absent from the D10 gate job" ok
  fi
fi

# ── W7: the referenced script exists and is executable ──────────────────────────────────────
# A wiring test pointing at a missing file must FAIL, not vacuously pass — every W2 row above
# would still be green if the script had never been committed.
if [[ -f "$DERIVE" ]]; then
  _report "W7 scripts/derive-app-domain-base.sh exists" ok
else
  _report "W7 scripts/derive-app-domain-base.sh exists" fail "the wired script is missing"
fi
if [[ -x "$DERIVE" ]]; then
  _report "W7 scripts/derive-app-domain-base.sh is executable" ok
else
  _report "W7 scripts/derive-app-domain-base.sh is executable" fail "not +x"
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
