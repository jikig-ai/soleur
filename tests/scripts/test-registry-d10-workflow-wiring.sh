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
# ── WHY EVERY ASSERTION IS ANCHORED, NOT COUNTED ────────────────────────────────────────────
# An earlier revision counted a bare path token. Review proved six mutations left it fully
# green, including two that re-admitted the original hazard class: pointing the arm at a
# DIFFERENT script while a comment mentioned the audited one, and replacing the fail-closed
# abort with a silent hardcoded fallback. Both are `cq-assert-anchor-not-bare-token`. Every row
# below now anchors on a call form or a block, never on a token that prose can produce.
#
# ── WHY A SEPARATE FILE ─────────────────────────────────────────────────────────────────────
# NOT appended to tests/scripts/test-registry-pull-path-health.sh. The mutation battery sandboxes
# that suite into a tree with no `.github/` directory, so workflow-reading rows would go RED in
# the battery's own baseline and `harness_die` it (exit 2, no verdict).
#
# Idiom follows its nearest neighbours (test-registry-pull-path-health.sh,
# test-registry-restore-from-ghcr.sh): `set -uo pipefail` + `export TMPDIR` + two-space `ok`/`FAIL`.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKFLOW="${ROOT}/.github/workflows/apply-web-platform-infra.yml"
DERIVE="${ROOT}/scripts/derive-app-domain-base.sh"
BRIDGE="${ROOT}/.github/actions/cf-tunnel-registry-bridge/action.yml"

passes=0
fails=0
_report() {
  if [[ "$2" == "ok" ]]; then passes=$((passes + 1)); printf '  ok   %s\n' "$1"
  else fails=$((fails + 1)); printf '  FAIL %s%s\n' "$1" "${3:+ — $3}"; fi
}

[[ -f "$WORKFLOW" ]] || { printf 'harness: workflow not found at %s\n' "$WORKFLOW" >&2; exit 2; }
[[ -f "$BRIDGE" ]]   || { printf 'harness: bridge action not found at %s\n' "$BRIDGE" >&2; exit 2; }

_strip() { grep -vE '^[[:space:]]*#'; }

_step_body() {
  awk -v want="$1" '
    index($0, "      - name: " want) == 1 { inb = 1; print; next }
    inb && /^      - name: / { inb = 0 }
    inb && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { inb = 0 }
    inb { print }
  ' "$WORKFLOW" | _strip
}

_job_body() {
  awk -v want="$1" '
    index($0, "  " want ":") == 1 { inb = 1; print; next }
    inb && /^  [a-zA-Z_][a-zA-Z0-9_-]*:/ { inb = 0 }
    inb { print }
  ' "$WORKFLOW" | _strip
}

PREPARE_BODY="$(_step_body 'Derive restore inventory (D10 PREPARE)')"
VERDICT_BODY="$(_step_body 'Pre-destroy authorization gate (D10 VERDICT)')"

# ── W1: vacuity floor ───────────────────────────────────────────────────────────────────────
w1_ok=1
[[ -n "$PREPARE_BODY" ]] || { _report "W1 PREPARE step body extracts non-empty" fail "extractor returned empty"; w1_ok=0; }
[[ -n "$VERDICT_BODY" ]] || { _report "W1 VERDICT step body extracts non-empty" fail "extractor returned empty"; w1_ok=0; }
if [[ "$w1_ok" -eq 1 ]]; then
  _report "W1 vacuity floor: both D10 step bodies extract non-empty" ok
else
  printf '\n=== %d passed, %d failed (vacuity floor failed) ===\n' "$passes" "$fails"
  exit 1
fi

# ── W2/W3/W5: shared properties, one loop over both bodies ──────────────────────────────────
for arm in PREPARE VERDICT; do
  body="$PREPARE_BODY"
  [[ "$arm" == "VERDICT" ]] && body="$VERDICT_BODY"

  # W2+W5 collapsed into ONE anchored row. Counting the path separately from the assignment
  # form let a substitution keep the count while changing behaviour three different ways
  # (different script + explanatory echo; dropped ${GITHUB_WORKSPACE} making it CWD-relative;
  # trailing comment naming the audited script). The anchor pins all of it at once, including
  # the ${GITHUB_WORKSPACE} prefix that DELIVERS the CWD-independence the unit suite proves.
  if grep -qE '^[[:space:]]*if ! APP_DOMAIN_BASE=\$\(DERIVE_CONTEXT=[A-Za-z0-9_-]+ bash "\$\{GITHUB_WORKSPACE\}/scripts/derive-app-domain-base\.sh"\); then$' <<<"$body"; then
    _report "W2 ${arm} invokes the shared derivation via the exact anchored call form" ok
  else
    _report "W2 ${arm} invokes the shared derivation via the exact anchored call form" fail "no anchored 'if ! APP_DOMAIN_BASE=\$(DERIVE_CONTEXT=… bash \"\${GITHUB_WORKSPACE}/scripts/derive-app-domain-base.sh\")' line"
  fi

  n=$(grep -cE 'scripts/derive-app-domain-base\.sh' <<<"$body")
  if [[ "$n" -eq 1 ]]; then
    _report "W2 ${arm} references the derivation exactly once" ok
  else
    _report "W2 ${arm} references the derivation exactly once" fail "found ${n}"
  fi

  if grep -qE '^[[:space:]]*export APP_DOMAIN_BASE[[:space:]]*$' <<<"$body"; then
    _report "W3 ${arm} exports APP_DOMAIN_BASE on its own line" ok
  else
    _report "W3 ${arm} exports APP_DOMAIN_BASE on its own line" fail "no bare 'export APP_DOMAIN_BASE' line"
  fi

  # W3 fail-closed, BLOCK-SCOPED. Two independent greps (one for the guard, one for any
  # `exit 1`) were satisfiable by an unrelated exit elsewhere in the step — measured: replacing
  # the abort with `APP_DOMAIN_BASE="soleur.ai"` + a ::warning:: and adding an unrelated
  # `exit 1` left the suite 21/0 while the gate authorized a destroy against a GUESSED host.
  # Extract the derivation-failure block and require the abort INSIDE it.
  abort_block="$(awk '
    /^[[:space:]]*if ! APP_DOMAIN_BASE=\$\(/ { inb = 1 }
    inb { print }
    inb && /^[[:space:]]*fi[[:space:]]*$/ { exit }
  ' <<<"$body")"
  if [[ -n "$abort_block" ]] \
     && grep -qE '::error::.*ABORT' <<<"$abort_block" \
     && grep -qE '^[[:space:]]*exit 1[[:space:]]*$' <<<"$abort_block"; then
    _report "W3 ${arm} aborts INSIDE the derivation-failure block (::error::…ABORT + exit 1)" ok
  else
    _report "W3 ${arm} aborts INSIDE the derivation-failure block" fail "block empty, or missing ::error::…ABORT / exit 1 within it"
  fi

  if grep -qE 'export[[:space:]]+APP_DOMAIN_BASE=\$\(' <<<"$body"; then
    _report "W5 ${arm} avoids the status-swallowing export form" fail "found 'export APP_DOMAIN_BASE=\$(' — exit status is swallowed"
  else
    _report "W5 ${arm} avoids the status-swallowing export form" ok
  fi

  if grep -qE '^[[:space:]]*set -euo pipefail[[:space:]]*$' <<<"$body"; then
    _report "W5 ${arm} body opens under set -euo pipefail" ok
  else
    _report "W5 ${arm} body opens under set -euo pipefail" fail "without errexit the assignment does not propagate the failure"
  fi
done

# ── W2b: the composite action is POSITIVELY pinned, not just forbidden a string ─────────────
# W4 below is a negative. Reverting the bridge to a hardcoded `APP_DOMAIN_BASE="soleur.ai"`
# satisfied every negative and left the suite green — the write-side hazard returns in a
# different costume. This row is the positive counterpart.
BRIDGE_BODY="$(_strip < "$BRIDGE")"
if grep -qE '^[[:space:]]*if ! APP_DOMAIN_BASE=\$\(DERIVE_CONTEXT=[A-Za-z0-9_-]+ bash "\$\{GITHUB_WORKSPACE\}/scripts/derive-app-domain-base\.sh"\); then$' <<<"$BRIDGE_BODY"; then
  _report "W2b cf-tunnel-registry-bridge invokes the shared derivation (anchored)" ok
else
  _report "W2b cf-tunnel-registry-bridge invokes the shared derivation (anchored)" fail "the recut's own refill leg does not call the derivation"
fi

# ── W4: residual-zero across the RECUT CHAIN, workflow AND composite actions ────────────────
# The pattern matches `doppler` co-occurring with the variable on one comment-stripped line,
# NOT a fixed command string. Measured: the fixed string was evaded by quoting the name, by a
# double space, and by `doppler secrets download … | jq -r .APP_DOMAIN_BASE`.
DARK_RE='doppler.*APP_DOMAIN_BASE'

# ALLOWLIST — enumerated and commented so each exclusion is visible rather than accidental.
# Both are OUT of the recut chain and deferred:
#   * cf-tunnel-ssh-bridge/action.yml  — derives ssh.<base>; not invoked by this dispatch.
#   * "Resolve known-good image digest off-host" — the web-host birth/replace sites, whose
#     conversion was deliberately cut (a host replace is live during this incident).
declare -a ALLOWED_FILES=( "cf-tunnel-ssh-bridge/action.yml" )
# name:expected-count. The count is PINNED, not merely non-zero: a PARTIAL conversion (one of
# the two sites) previously left the row green reporting "1 deferred read(s)".
declare -a ALLOWED_WORKFLOW_STEPS=( "Resolve known-good image digest off-host:2" )

violations=""
scan_targets="$(find "${ROOT}/.github/actions" -name 'action.y*ml' 2>/dev/null; printf '%s\n' "$WORKFLOW")"
scanned=0
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" ]] || continue
  scanned=$((scanned + 1))
  skip=0
  for a in "${ALLOWED_FILES[@]}"; do [[ "$f" == *"$a" ]] && skip=1; done
  [[ "$skip" -eq 1 ]] && continue

  hits="$(_strip < "$f" | grep -cE "$DARK_RE" || true)"
  [[ "$hits" -eq 0 ]] && continue

  if [[ "$f" == "$WORKFLOW" ]]; then
    unattributed="$(awk -v re="$DARK_RE" '
      /^      - name: / { step = substr($0, index($0, "- name: ") + 8) }
      $0 ~ /^[[:space:]]*#/ { next }
      $0 ~ re { print NR "\t" step }
    ' "$f")"
    while IFS=$'\t' read -r lineno step; do
      [[ -n "$lineno" ]] || continue
      allowed=0
      for s in "${ALLOWED_WORKFLOW_STEPS[@]}"; do
        [[ "$step" == *"${s%%:*}"* ]] && allowed=1
      done
      [[ "$allowed" -eq 1 ]] && continue
      violations+="${f}:${lineno} (step: ${step})"$'\n'
    done <<<"$unattributed"
  else
    violations+="${f} (${hits} dark read(s))"$'\n'
  fi
done <<<"$scan_targets"

if [[ "$scanned" -lt 2 ]]; then
  _report "W4 scan covered the workflow and composite actions" fail "only ${scanned} file(s) scanned"
else
  _report "W4 scan covered ${scanned} files (workflow + composite actions)" ok
fi

if [[ -z "$violations" ]]; then
  _report "W4 residual-zero: no un-allowlisted doppler+APP_DOMAIN_BASE read in the recut chain" ok
else
  _report "W4 residual-zero" fail "surviving dark reads:"$'\n'"${violations}"
fi

# Allowlist staleness — COMMENT-STRIPPED, like every other read path in this file. It was not,
# and a conversion that left the customary explanatory comment ("replaced the old `doppler
# secrets get APP_DOMAIN_BASE` dark read") kept the exemption alive forever off that prose.
for a in "${ALLOWED_FILES[@]}"; do
  match="$(find "${ROOT}/.github/actions" -path "*${a}" 2>/dev/null | head -1)"
  if [[ -n "$match" ]] && [[ "$(_strip < "$match" | grep -cE "$DARK_RE" || true)" -gt 0 ]]; then
    _report "W4 allowlist entry '${a}' still describes a real deferred read" ok
  else
    _report "W4 allowlist entry '${a}' is stale" fail "no matching dark read in CODE — remove the exemption (D4 has landed)"
  fi
done

for s in "${ALLOWED_WORKFLOW_STEPS[@]}"; do
  want="${s%%:*}"; expect="${s##*:}"
  c=$(awk -v re="$DARK_RE" -v want="$want" '
    /^      - name: / { step = substr($0, index($0, "- name: ") + 8) }
    $0 ~ /^[[:space:]]*#/ { next }
    $0 ~ re && index(step, want) > 0 { n++ }
    END { print n + 0 }
  ' "$WORKFLOW")
  if [[ "$c" -eq "$expect" ]]; then
    _report "W4 allowlisted step '${want}' carries exactly ${expect} deferred read(s)" ok
  else
    _report "W4 allowlisted step '${want}' count drifted" fail "expected ${expect}, found ${c} — a partial conversion landed; narrow or remove the exemption"
  fi
done

# ── W6: DOPPLER_TOKEN_PRD is gone from the D10 gate job ─────────────────────────────────────
GATE_JOB="$(_job_body 'registry_pull_path_gate')"
if [[ -z "$GATE_JOB" ]]; then
  _report "W6 registry_pull_path_gate job body extracts non-empty" fail "extractor returned empty"
else
  _report "W6 registry_pull_path_gate job body extracts non-empty" ok
  if grep -qE 'DOPPLER_TOKEN_PRD' <<<"$GATE_JOB"; then
    _report "W6 DOPPLER_TOKEN_PRD absent from the D10 gate job" fail "still referenced"
  else
    _report "W6 DOPPLER_TOKEN_PRD absent from the D10 gate job" ok
  fi
fi

# ── W7: the referenced script exists and is executable ──────────────────────────────────────
if [[ -f "$DERIVE" ]]; then _report "W7 scripts/derive-app-domain-base.sh exists" ok
else _report "W7 scripts/derive-app-domain-base.sh exists" fail "the wired script is missing"; fi
if [[ -x "$DERIVE" ]]; then _report "W7 scripts/derive-app-domain-base.sh is executable" ok
else _report "W7 scripts/derive-app-domain-base.sh is executable" fail "not +x"; fi

# ── W8: every step that shells out to `doppler` must actually give it a token. ──────────────
# The restore leg -- the job whose entire purpose is refilling the store AFTER the destroy --
# declared `DOPPLER_TOKEN_PRD` in its env, referenced it nowhere in its body, and called
# `doppler secrets get` bare. The CLI reads `DOPPLER_TOKEN` (or `--token`) and does not know the
# _PRD suffix, so it ran unauthenticated: "you must provide a token", empty sink credentials,
# engine abort exit 3, POST-DESTROY.
#
# It was latent behind the D10 gate for as long as A2 had never passed. Fixing A2 did not create
# it; it exposed it. This row is the mechanical version of that lesson, and it quantifies over
# EVERY step rather than the one that bit us.
# The variable is WORKFLOW, not WF. The first cut of this row used an undefined "$WF", so python
# opened "" , errored, the command substitution yielded EMPTY, and empty read as "no offenders" --
# the row reported ok with the bug fully reintroduced. That is the same empty-means-pass vacuity
# this row exists to catch, committed inside the row itself. Hence both guards below: the rc is
# checked, and an empty result is only trusted when python said it looked at something.
_dop_out=$(python3 - "$WORKFLOW" <<'PYX'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
bad, seen = [], 0
for jn, j in (d.get("jobs") or {}).items():
    if not isinstance(j, dict):
        continue
    for st in (j.get("steps") or []):
        body = str(st.get("run") or "")
        env = st.get("env") or {}
        if "doppler " not in body:
            continue
        seen += 1
        if "DOPPLER_TOKEN" not in env and "--token" not in body:
            bad.append(f"{jn}::{st.get('name')}")
# SEEN is printed so a zero-offender result can be distinguished from a scan that inspected
# nothing -- a non-vacuity control on the row's own population.
print(f"SEEN={seen}")
for b in bad:
    print(f"BAD={b}")
PYX
) || _dop_out="RC_FAIL"
_dop_seen=$(printf '%s\n' "$_dop_out" | sed -n 's/^SEEN=//p')
_dop_bad=$(printf '%s\n' "$_dop_out" | sed -n 's/^BAD=//p')
if [[ "$_dop_out" == "RC_FAIL" ]]; then
  _report "W8 every doppler-calling step supplies a token" fail "the scan itself failed; no verdict"
elif [[ -z "${_dop_seen:-}" || "${_dop_seen:-0}" -lt 1 ]]; then
  _report "W8 every doppler-calling step supplies a token" fail "the scan inspected ZERO doppler-calling steps — vacuous"
elif [[ -n "$_dop_bad" ]]; then
  _report "W8 every doppler-calling step supplies a token" fail "$_dop_bad"
else
  _report "W8 every doppler-calling step supplies a token (${_dop_seen} steps inspected)" ok
fi

# ── Anti-vacuity assertion floor ────────────────────────────────────────────────────────────
# Measured: neutering `_report` to `return 0` reported "0 passed, 0 failed" and exit 0 — a
# suite asserting nothing is byte-indistinguishable from one that passed, because `fails` is a
# single unguarded integer. Pinned EXACTLY: a `>=` re-opens the hole on the next added row.
EXPECTED_ASSERTIONS=23
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_ASSERTIONS" ]]; then
  printf '  FAIL anti-vacuity: %d assertions passed, expected exactly %d — rows were added, removed, or silenced\n' \
    "$passes" "$EXPECTED_ASSERTIONS"
  fails=$((fails + 1))
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
