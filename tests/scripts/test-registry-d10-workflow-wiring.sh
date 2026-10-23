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
        # THREE supplying forms, not two. `DOPPLER_TOKEN` as an env KEY and `--token` in argv
        # were the original two; a body-level `DOPPLER_TOKEN=...` assignment prefixed onto the
        # command is the third, and it is the SAFEST of them — `--token "$X"` puts the secret
        # in argv, readable from /proc by any other process on the runner for the life of the
        # call, whereas the assignment form keeps it in the environment. The row must not push
        # authors toward the argv form to satisfy it (#8252).
        #
        # Anchored on the ASSIGNMENT (`DOPPLER_TOKEN=`), never on the bare name: the defect this
        # row exists for is a step that DECLARES `DOPPLER_TOKEN_PRD` in env, references it
        # nowhere, and calls doppler bare. That step has the bare name in env and no `=` form in
        # the body, so it still fails here. A comment merely mentioning the variable also does
        # not satisfy it.
        supplies = (
            "DOPPLER_TOKEN" in env
            or "--token" in body
            or "DOPPLER_TOKEN=" in body
        )
        if not supplies:
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

# ── W9: the restore step turns every engine exit code into the same step exit status and a named annotation. ──
# The restore step maps the engine's exit code to one operator-facing `::error::` line. Exit 78
# (the engine refusing to run traced) had no arm and fell into the `*)` text that calls it "a
# defect worth filing", and arms 2 and 5 kept describing only the older meaning. Nothing pinned
# it: the gate suite's loop asserts only `rc != 0`, which the fallthrough also satisfies.
#
# W9 RUNS the step's real `run:` body (PyYAML extracts it, as W8 does) with `doppler`, `sleep` and
# the engine stubbed, once per code, and asserts what an operator and the runner would see: the
# step exits with the engine's code, the emitted annotation names that code (and is not the `*)`
# text for a documented one), 2/5 say `failed locally` and 78 says `traced invocation`, and the
# engine is called once (the retry bound, from the step's own `max=`, for exit 3). A text parse of
# the `case` was bypassed in two consecutive review rounds; running it cannot be, so none is kept.
# The stub ignores the engine's arguments: the engine suite and the rows above own those.
#
# The population is DERIVED (tests/scripts/lib/restore-engine-header.sh): the engine's header
# table must equal the codes its own `die N` / `exit N` sites emit. Exit 1 follows the rule in
# that lib: always exercised, never compared. The controls apply one mutation to the workflow text
# (or one stray `die 7` to the engine) and require the same check to refuse it.
# shellcheck source=tests/scripts/lib/restore-engine-header.sh
source "${ROOT}/tests/scripts/lib/restore-engine-header.sh"
RESTORE_ENGINE="${ROOT}/scripts/registry-restore-from-ghcr.sh"
RESTORE_ENGINE_TEXT="$(cat "$RESTORE_ENGINE" 2>/dev/null)"
RESTORE_WF_TEXT="$(cat "$WORKFLOW")"
RESTORE_STEP="Restore production's pinned image set from GHCR"
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
W9_TMP="$(mktemp -d)" || { printf 'harness: mktemp -d failed\n' >&2; exit 2; }
assert_fixture_dir "$W9_TMP"
trap 'rm -rf "$W9_TMP"' EXIT
W9_PY="$(cat <<'PYX'
import re, sys, yaml
mode, name, text = sys.argv[1], sys.argv[2], sys.stdin.read()
if mode == "extract":
    for j in (yaml.safe_load(text).get("jobs") or {}).values():
        for s in (j.get("steps") or []):
            if s.get("name") == name:
                sys.stdout.write(s.get("run") or ""); raise SystemExit(0)
    raise SystemExit(3)
a = text.index("      - name: " + name)
b = text.find("\n      - name: ", a + 1)
seg, rest = text[a:b], text[b:]
def once(old, new):
    global seg
    if seg.count(old) != 1: raise SystemExit("anchor %r found %d times" % (old, seg.count(old)))
    seg = seg.replace(old, new)
arm = re.search(r'\n( *78\) echo [^\n]*)', seg).group(1)
k = mode.split(":", 1)[1]
if k == "drop78": once("\n" + arm, "")
elif k == "dead": once("\n" + arm, ""); once('\n          case "$rc" in', '\n          if false; then echo "::error::restore FAILED exit 78 (TRACED INVOCATION)"; fi\n          case "$rc" in')
elif k == "nested": once(arm, '            9) case "$zz" in 78) echo "::error::restore FAILED exit 78 (TRACED INVOCATION)" ;; esac ;;')
elif k == "subject": once('case "$rc" in', 'case "$zz" in')
elif k == "clobber": once("\n            rc=$?\n", "\n            true; rc=$?\n")
elif k == "exit0": once('\n          exit "$rc"', "\n          exit 0")
elif k == "trap": once("\n          set +e\n", "\n          set +e\n          trap 'exit 0' EXIT\n")
elif k == "max0": once("\n          max=6\n", "\n          max=0\n")
elif k == "wrongscript": once("/scripts/registry-restore-from-ghcr.sh", "/scripts/registry-restore-from-ghcr.sh.gone")
else: raise SystemExit("unknown mutation " + k)
sys.stdout.write(text[:a] + seg + rest)
PYX
)"
w9_run() { # <run body> <engine exit code>: prints "RC=<step status> CALLS=<engine invocations>", then the step's output
  local d="$W9_TMP/run" out rc n
  assert_fixture_dir "$W9_TMP"
  rm -rf "$d"; mkdir -p "$d/bin" "$d/ws/scripts" "$d/tmp/pins"
  printf '%s\n' "$1" > "$d/step.sh"
  printf '#!/bin/sh\necho stub-value\n' > "$d/bin/doppler"
  printf '#!/bin/sh\nexit 0\n' > "$d/bin/sleep"
  cat > "$d/ws/scripts/registry-restore-from-ghcr.sh" <<'STUB'
#!/bin/sh
echo x >> "$W9_CALLS"
exit "$W9_RC"
STUB
  chmod +x "$d/bin/doppler" "$d/bin/sleep" "$d/ws/scripts/registry-restore-from-ghcr.sh"
  out="$(env -i PATH="$d/bin:/usr/bin:/bin" HOME="$d" GITHUB_WORKSPACE="$d/ws" RUNNER_TEMP="$d/tmp" GITHUB_ACTOR=a \
    GH_TOKEN_FOR_ENGINE=t DOPPLER_TOKEN=t W9_CALLS="$d/calls" W9_RC="$2" bash --noprofile --norc -eo pipefail "$d/step.sh" 2>&1)"; rc=$?
  n="$(wc -l < "$d/calls" 2>/dev/null)"
  printf 'RC=%s CALLS=%s\n%s\n' "$rc" "$((${n:-0}))" "$out"
}
w9_add() { w9_p="${w9_p}${w9_p:+$'\n'}$1"; }
w9_check() { # <workflow text> <engine text>: prints one problem per line; no output means the contract holds
  local wf="$1" eng="$2" body hdr emit maxv code res head out rc calls want line tested
  w9_p=""
  [[ -n "$eng" ]] || { echo "the restore engine is missing or empty at ${RESTORE_ENGINE}"; return; }
  hdr="$(restore_header_codes <<<"$eng" | grep -vx 1)"; emit="$(restore_emit_codes <<<"$eng" | grep -vx 1)"
  [[ "$hdr" == "$emit" ]] || w9_add "the engine header table (${hdr//$'\n'/ }) differs from the codes its die/exit sites emit (${emit//$'\n'/ }), both without 1"
  tested="$({ echo 1; restore_header_codes <<<"$eng"; } | sort -un)"
  [[ "$(grep -c . <<<"$tested")" -ge 7 ]] || w9_add "the engine header yielded fewer than 6 failure codes (header reshaped?)"
  body="$(python3 -c "$W9_PY" extract "$RESTORE_STEP" <<<"$wf")" || body=""
  [[ -n "$body" ]] || { w9_add "the restore step has no run: body (step renamed?)"; printf '%s' "$w9_p"; return; }
  maxv="$(sed -nE 's/^[[:space:]]*max=([0-9]+)[[:space:]]*$/\1/p' <<<"$body" | head -1)"
  [[ -n "$maxv" ]] || { w9_add "the restore step has no max= retry bound"; maxv=1; }
  for code in 0 $tested 137; do
    res="$(w9_run "$body" "$code")"; head="${res%%$'\n'*}"; out="${res#*$'\n'}"
    rc="${head#RC=}"; rc="${rc%% *}"; calls="${head##*CALLS=}"
    want=1; [[ "$code" == 3 ]] && want="$maxv"
    [[ "$rc" == "$code" ]] || w9_add "step exited ${rc}, want ${code} (engine exit ${code})"
    [[ "$calls" == "$want" ]] || w9_add "engine called ${calls} times for exit ${code}, want ${want}"
    line="$(grep -E '^::error::restore FAILED|^restore:' <<<"$out" | head -1)"
    if [[ "$code" == 0 ]]; then
      [[ "$line" == restore:* ]] || w9_add "exit 0 printed no success line"; continue
    fi
    [[ "$line" =~ exit\ ${code}([^0-9]|$) ]] || { w9_add "exit ${code} printed no annotation naming it (got: ${line:-nothing})"; continue; }
    if grep -qx "$code" <<<"$hdr" && grep -qiF 'unenumerated' <<<"$line"; then w9_add "exit ${code} fell to the *) arm"; fi
    case "$code" in
      2|5) grep -qiF 'failed locally' <<<"$line" || w9_add "the annotation for exit ${code} does not name the local login failure" ;;
      78)  grep -qiF 'traced invocation' <<<"$line" || w9_add "the annotation for exit 78 does not say traced invocation" ;;
    esac
  done
  printf '%s' "$w9_p"
}
w9_problems="$(w9_check "$RESTORE_WF_TEXT" "$RESTORE_ENGINE_TEXT")"
if [[ -z "$w9_problems" ]]; then
  _report "W9 the restore step maps every engine exit code to its step status and a named annotation" ok
else
  _report "W9 the restore step maps every engine exit code to its step status and a named annotation" fail "${w9_problems//$'\n'/; }"
fi

# W9 controls: each mutates the REAL workflow text (or adds one `die 7` to the engine), checks the
# mutation landed, and requires the same check to refuse it with a message naming the right thing.
for w9_c in "drop78|exit 78 fell" "dead|exit 78 fell" "nested|exit 78 fell" "subject|step exited" \
  "clobber|step exited 0" "exit0|step exited 0" "trap|step exited 0" "max0|engine called 0 times" "wrongscript|engine called 0 times"; do
  w9_mut="$(python3 -c "$W9_PY" "mutate:${w9_c%%|*}" "$RESTORE_STEP" <<<"$RESTORE_WF_TEXT")"
  if [[ -z "$w9_mut" || "$w9_mut" == "$RESTORE_WF_TEXT" ]]; then
    _report "W9 control ${w9_c%%|*}: the mutation landed" fail "the mutation did not change the workflow"; continue
  fi
  w9_out="$(w9_check "$w9_mut" "$RESTORE_ENGINE_TEXT")"
  if grep -qF -- "${w9_c#*|}" <<<"$w9_out"; then _report "W9 control ${w9_c%%|*}: refused" ok
  else _report "W9 control ${w9_c%%|*}: refused" fail "expected a refusal naming '${w9_c#*|}', got: ${w9_out:-<nothing>}"; fi
done
w9_out="$(w9_check "$RESTORE_WF_TEXT" "${RESTORE_ENGINE_TEXT}"$'\n''die 7 "a code the header does not list"')"
if grep -qF 'differs' <<<"$w9_out"; then _report "W9 control engine-die7: refused" ok
else _report "W9 control engine-die7: refused" fail "expected a refusal naming 'differs', got: ${w9_out:-<nothing>}"; fi

# ── Anti-vacuity assertion floor ────────────────────────────────────────────────────────────
# Measured: neutering `_report` to `return 0` reported "0 passed, 0 failed" and exit 0 — a
# suite asserting nothing is byte-indistinguishable from one that passed, because `fails` is a
# single unguarded integer. Pinned EXACTLY: a `>=` re-opens the hole on the next added row.
EXPECTED_ASSERTIONS=34
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_ASSERTIONS" ]]; then
  printf '  FAIL anti-vacuity: %d assertions passed, expected exactly %d — rows were added, removed, or silenced\n' \
    "$passes" "$EXPECTED_ASSERTIONS"
  fails=$((fails + 1))
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
