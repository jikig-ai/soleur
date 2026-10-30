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
# the engine stubbed, and asserts what an operator and the runner would see: for each code the step
# exits with the engine's code, the emitted annotation names that code (and is not the `*)` text for
# a documented one), 2/5 say `failed locally` and 78 says `traced invocation`, and the engine is
# called once (the step's own `max=` times for exit 3). Three more runs: a recovery (engine exits
# 3, 3, 0: the step ends 0 after 3 calls), a Doppler read failure (the step aborts 1 before any
# engine call) and the first engine call itself (its `--target` / `--tags-from` arguments, and that
# it was not started traced). A text parse of the workflow's `case` was bypassed in two consecutive review
# rounds; running it cannot be, so none is kept for the workflow. The engine's own behaviour belongs to its suite.
#
# Also pinned: the step's env is EXACTLY DOPPLER_TOKEN (secrets.DOPPLER_TOKEN_PRD) and
# GH_TOKEN_FOR_ENGINE (secrets.GITHUB_TOKEN), the job's `if` is exactly the normalized expression
# below, and the job carries exactly the keys it has today (so no `container`, `services`, `env`,
# `defaults`, `strategy`, `continue-on-error`, `concurrency` or `outputs` can appear unnoticed).
# The VALUES of environment / runs-on / permissions / timeout-minutes are not pinned here: they are
# the workflow's own to change, and a value pin would only mirror the workflow into this file.
# Exit 1 is always in the tested population (the header's non-zero codes UNION {1}): it is exercised and
# barred from the `*)` arm even if the header row for 1 were dropped, and its annotation must name the manifest.
#
# Also covered here (#10932 residuals 2 and 3): the Restore summary step (`w9_summary_check` runs its body for
# success, cancelled, failure and an empty outcome and pins its `if` and env); every `die` / `exit` word in the
# engine that is not a literal-code site, so a `die "$x"` is no longer invisible to the comparison below
# (`w9_computed_sites`); and the verdict swap (a nested run of this suite on a drop1 workflow must print exactly
# the FAIL line the drop1 control expects, and `w9_expect` has a canary). NOT covered: a die whose code arrives
# through `eval` or an indirect call (a command held in a variable), and the engine's own prose.
#
# The population is DERIVED (tests/scripts/lib/restore-engine-header.sh): the engine's header
# table must equal the codes its own `die N` / `exit N` sites emit. Exit 1 follows the rule in
# that lib: always exercised, never compared. The controls apply one mutation to the workflow text
# (or one stray `die` to the engine) and require the same check to refuse it.
# shellcheck source=tests/scripts/lib/restore-engine-header.sh
source "${ROOT}/tests/scripts/lib/restore-engine-header.sh"
RESTORE_ENGINE="${ROOT}/scripts/registry-restore-from-ghcr.sh"
RESTORE_ENGINE_TEXT="$(cat "$RESTORE_ENGINE" 2>/dev/null)"
RESTORE_WF_TEXT="$(cat "$WORKFLOW")"
RESTORE_STEP="Restore production's pinned image set from GHCR"
SUMMARY_STEP="Restore summary"
W9_ROW="W9 the restore step maps every engine exit code to its step status and a named annotation"
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
trap 'exit 143' TERM HUP INT
W9_PY="$(cat <<'PYX'
import re, sys, yaml
mode, name, text = sys.argv[1], sys.argv[2], sys.stdin.read()
other = sys.argv[3] if len(sys.argv) > 3 else ""
FORBID = ("if", "continue-on-error", "shell", "working-directory", "timeout-minutes")
if mode in ("sumextract", "sumkeys"):
    jobs = yaml.safe_load(text).get("jobs") or {}
    hits = [(jn, i, s) for jn, j in jobs.items() for i, s in enumerate(j.get("steps") or []) if s.get("name") == name]
    if not hits: raise SystemExit(3)
    if len(hits) != 1 or hits[0][0] != "registry_store_restore": raise SystemExit(4)
    if mode == "sumkeys":
        print("if=" + " ".join(str(hits[0][2].get("if", "")).split())); print("keys=" + " ".join(k for k in FORBID if k != "if" and k in hits[0][2]))
        raise SystemExit(0)
    names = [s.get("name") for s in jobs["registry_store_restore"]["steps"]]
    if other not in names or names.index(other) >= hits[0][1]: raise SystemExit(6)
    sys.stdout.write(hits[0][2].get("run") or ""); raise SystemExit(0)
if mode in ("extract", "keys"):
    hits = [(jn, s) for jn, j in (yaml.safe_load(text).get("jobs") or {}).items() for s in (j.get("steps") or []) if s.get("name") == name]
    if not hits: raise SystemExit(3)
    if len(hits) != 1 or hits[0][0] != "registry_store_restore": raise SystemExit(4)
    if mode == "keys": sys.stdout.write("\n".join(k for k in FORBID if k in hits[0][1]))
    else: sys.stdout.write(hits[0][1].get("run") or "")
    raise SystemExit(0)
if mode in ("env", "job"):
    jobs = yaml.safe_load(text).get("jobs") or {}
    j = jobs.get("registry_store_restore")
    if j is None: raise SystemExit(5)
    if mode == "job":
        n = j.get("needs"); n = [n] if isinstance(n, str) else list(n or [])
        jif = " ".join(str(j.get("if", "")).split())
        if jif.startswith("${{ ") and jif.endswith(" }}"): jif = jif[4:-3]
        print("needs=" + ",".join(n)); print("if=" + jif); print("keys=" + " ".join(sorted(j)))
        raise SystemExit(0)
    hits = [s for s in (j.get("steps") or []) if s.get("name") == name]
    if len(hits) != 1: raise SystemExit(3)
    for k, v in sorted((hits[0].get("env") or {}).items()): print("%s=%s" % (k, v))
    raise SystemExit(0)
if mode in ("mutate:jobif", "mutate:jobcoe", "mutate:jobctr", "mutate:ifor"):
    jh = "\n  registry_store_restore:\n"
    if text.count(jh) != 1: raise SystemExit("job header found %d times" % text.count(jh))
    a = text.index(jh) + len(jh)
    m = re.search(r"\n  [A-Za-z_][A-Za-z0-9_-]*:", text[a:])
    b = a + m.start() if m else len(text)
    job = text[a:b]
    if mode == "mutate:jobcoe": job = "    continue-on-error: true\n" + job
    elif mode == "mutate:jobctr": job = "    container: ubuntu:20.04\n" + job
    elif mode == "mutate:ifor":
        job, n = re.subn(r"(store_refill_needed == 'true')", r"\1 || always()", job)
        if n != 1: raise SystemExit("anchor store_refill_needed found %d times in the job" % n)
    else:
        job, n = re.subn(r"!cancelled\(\)\s*&&\s*", "", job)
        if n != 1: raise SystemExit("anchor !cancelled() && found %d times in the job" % n)
    sys.stdout.write(text[:a] + job + text[b:]); raise SystemExit(0)
head = "      - name: " + name
if text.count(head) != 1: raise SystemExit("step header found %d times" % text.count(head))
a = text.index(head)
b = text.find("\n      - name: ", a + 1)
seg, rest = text[a:b], text[b:]
def once(old, new):
    global seg
    if seg.count(old) != 1: raise SystemExit("anchor %r found %d times" % (old, seg.count(old)))
    seg = seg.replace(old, new)
if mode.startswith("mutate:sum"):
    # The summary step is the last step of its job, so the generic "next step header" bound would run into the next job.
    m = re.search(r"\n(?:      - name: |  [A-Za-z_][A-Za-z0-9_-]*:)", text[a + 1:])
    b = a + 1 + m.start() if m else len(text)
    seg, rest = text[a:b], text[b:]
    k = mode.split(":", 1)[1]
    if k == "sumifdrop": once("\n        if: always()", "")
    elif k == "sumenvlit": once("RESTORE_RESULT: ${{ job.status }}", "RESTORE_RESULT: success")
    elif k == "sumredirect": once('} >> "$GITHUB_STEP_SUMMARY"', "}")
    elif k in ("sumswap", "sumreword"):
        e1 = re.search(r"\n *success\)\n( *echo [^\n]*)", seg).group(1)
        e2 = re.search(r"\n *cancelled\)\n( *echo [^\n]*)", seg).group(1)
        e3 = re.search(r"\n *\*\)\n( *echo [^\n]*)", seg).group(1)
        if k == "sumswap": once(e1, "@@SWAP@@"); once(e3, e1); once("@@SWAP@@", e3)
        else: once(e1, '                echo "Done: the store is closed again."'); once(e2, '                echo "Restore cancelled; re-run the job."')
    elif k == "sumorder":
        t2 = text[:a] + text[b:]
        ri = "      - name: " + other
        if t2.count(ri) != 1: raise SystemExit("restore step header found %d times" % t2.count(ri))
        sys.stdout.write(t2[:t2.index(ri)] + seg.rstrip("\n") + "\n\n" + t2[t2.index(ri):]); raise SystemExit(0)
    else: raise SystemExit("unknown mutation " + k)
    sys.stdout.write(text[:a] + seg + rest); raise SystemExit(0)
arm = re.search(r'\n( *78\) echo [^\n]*)', seg).group(1)
k = mode.split(":", 1)[1]
if k == "drop78": once("\n" + arm, "")
elif k == "drop1": once("\n" + re.search(r'\n( *1\) echo [^\n]*)', seg).group(1), "")
elif k == "manifest":
    a1 = re.search(r'\n( *1\) echo [^\n]*)', seg).group(1)
    once(a1, re.sub("(?i)manifest", "pin set", a1))
elif k == "envextra": once("GH_TOKEN_FOR_ENGINE: ${{ secrets.GITHUB_TOKEN }}", "GH_TOKEN_FOR_ENGINE: ${{ secrets.GITHUB_TOKEN }}\n          SHELLOPTS: xtrace")
elif k == "envswap": once("DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_PRD }}", "DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}")
elif k == "dead": once("\n" + arm, ""); once('\n          case "$rc" in', '\n          if false; then echo "::error::restore FAILED exit 78 (TRACED INVOCATION)"; fi\n          case "$rc" in')
elif k == "nested": once(arm, '            9) case "$zz" in 78) echo "::error::restore FAILED exit 78 (TRACED INVOCATION)" ;; esac ;;')
elif k == "subject": once('case "$rc" in', 'case "${zz:-}" in')
elif k == "clobber": once("\n            rc=$?\n", "\n            true; rc=$?\n")
elif k == "sticky3": once("\n            rc=$?\n", "\n            rc=$(( rc == 3 ? 3 : $? ))\n")
elif k == "exit0": once('\n          exit "$rc"', "\n          exit 0")
elif k == "trap": once("\n          set +e\n", "\n          set +e\n          trap 'exit 0' EXIT\n")
elif k == "max0": once("\n          max=6\n", "\n          max=0\n")
elif k == "wrongscript": once("/scripts/registry-restore-from-ghcr.sh", "/scripts/registry-restore-from-ghcr.sh.gone")
elif k == "dopabort": once("\n            exit 1\n", "\n            exit 0\n")
elif k == "traced": once('bash "${GITHUB_WORKSPACE}/scripts/registry-restore-from-ghcr.sh"', 'bash -x "${GITHUB_WORKSPACE}/scripts/registry-restore-from-ghcr.sh"')
elif k == "args": once("--target 127.0.0.1:5000", "--target 127.0.0.1:5001")
elif k == "stepkeys": seg = seg.replace("\n", "\n        continue-on-error: true\n", 1)
else: raise SystemExit("unknown mutation " + k)
sys.stdout.write(text[:a] + seg + rest)
PYX
)"
w9_run() { # <run body> <engine exit codes, one per call> [dopfail]: prints RC=, CALLS=, FIRST= (the first engine call's "$- args"), then the step's output
  local d="$W9_TMP/run" out rc n=0 first="" cl=()
  assert_fixture_dir "$W9_TMP"
  rm -rf "$d"; mkdir -p "$d/bin" "$d/ws/scripts" "$d/tmp/pins"
  printf '%s\n' "$1" > "$d/step.sh"
  ln -s "$(command -v bash)" "$d/bin/bash"
  cat > "$d/bin/doppler" <<'STUB'
#!/bin/bash
[[ -z "${W9_DOPFAIL:-}" ]] || exit 1
echo stub-value
STUB
  printf '#!/bin/bash\nexit 0\n' > "$d/bin/sleep"
  cat > "$d/ws/scripts/registry-restore-from-ghcr.sh" <<'STUB'
#!/bin/bash
printf '%s %s\n' "$-" "$*" >> "$W9_CALLS"
mapfile -t l < "$W9_CALLS"
codes=($W9_SEQ)
i=$(( ${#l[@]} - 1 )); (( i < ${#codes[@]} )) || i=$(( ${#codes[@]} - 1 ))
exit "${codes[$i]}"
STUB
  chmod +x "$d/bin/doppler" "$d/bin/sleep" "$d/ws/scripts/registry-restore-from-ghcr.sh"
  out="$(cd "$d/ws" && timeout 120 env -i PATH="$d/bin" HOME="$d" GITHUB_WORKSPACE="$d/ws" RUNNER_TEMP="$d/tmp" GITHUB_ACTOR=a \
    GH_TOKEN_FOR_ENGINE=t DOPPLER_TOKEN=t W9_CALLS="$d/calls" W9_SEQ="$2" ${3:+W9_DOPFAIL=1} \
    "$d/bin/bash" --noprofile --norc -eo pipefail "$d/step.sh" 2>&1 </dev/null)"; rc=$?
  if [[ -f "$d/calls" ]]; then mapfile -t cl < "$d/calls"; n=${#cl[@]}; first="${cl[0]:-}"; fi
  printf 'RC=%s CALLS=%s\nFIRST=%s\n%s\n' "$rc" "$n" "$first" "$out"
}
w9_parse() { # <w9_run result>: sets w9_rc w9_calls w9_first w9_out
  local res="$1" rest="${1#*$'\n'}"
  w9_rc="${res%%$'\n'*}"; w9_calls="${w9_rc##*CALLS=}"; w9_rc="${w9_rc#RC=}"; w9_rc="${w9_rc%% *}"
  w9_first="${rest%%$'\n'*}"; w9_first="${w9_first#FIRST=}"
  w9_out="${rest#*$'\n'}"
}
w9_add() { w9_p="${w9_p}${w9_p:+$'\n'}$1"; }
# Verdicts are returned as DATA (`ok` / `fail`), never as an exit: the callers sit inside `$( )`, where an exit would only end the subshell.
w9_expect() { if grep -qF -- "$1" <<<"$2"; then echo ok; else echo fail; fi; } # <needle> <text>
w9_verdict() { if [[ -z "$1" ]]; then echo ok; else echo fail; fi; }           # <problems>: no problem is ok
w9_computed_sites() { # <engine text on stdin>: prints one offender per line (<line>:<token>, or a site-count problem); no output means every die/exit word is a literal-code site or one of the two allowed die() lines
  local txt dl=() cl=() close="" ln tok acc=0 re='^(die|exit) [0-9]+([[:space:];&|)]|$)'
  txt="$(sed -E 's/^[[:space:]]*#.*$//')" # whole-line comments are blanked, never deleted, so the reported line numbers are the engine file's
  mapfile -t dl < <(grep -nE '^die\(\) \{( #.*)?$' <<<"$txt" | cut -d: -f1)
  mapfile -t cl < <(grep -nE '^[[:space:]]*exit "\$code"$' <<<"$txt" | cut -d: -f1)
  [[ "${#dl[@]}" == 1 ]] || echo "allowed site count: the die() definition occurs ${#dl[@]} times, want exactly 1"
  [[ "${#cl[@]}" == 1 ]] || echo "allowed site count: the exit \"\$code\" line occurs ${#cl[@]} times, want exactly 1"
  if [[ "${#dl[@]}" == 1 && "${#cl[@]}" == 1 ]]; then
    close="$(awk -v s="${dl[0]}" 'NR > s && /^}/ { print NR; exit }' <<<"$txt")"
    if [[ -n "$close" && "${cl[0]}" -gt "${dl[0]}" && "${cl[0]}" -lt "$close" ]]; then
      txt="$(awk -v a="${dl[0]}" -v b="${cl[0]}" 'NR == a || NR == b { print ""; next } { print }' <<<"$txt")"
    else echo "allowed site count: the exit \"\$code\" line is not inside the die() body"; fi
  fi
  # Every remaining die/exit WORD is a token; only `die N` / `exit N` (one space, digits, a clean terminator) is accepted, because
  # that is the shape restore_emit_codes reads. A word census has no call-position anchor set to under-enumerate.
  while IFS=: read -r ln tok; do
    [[ -n "$ln" ]] || continue
    if [[ "$tok" =~ $re ]]; then acc=$((acc + 1)); else echo "${ln}:${tok%"${tok##*[![:space:]]}"}"; fi
  done < <(grep -noE '\b(die|exit)\b( [0-9]+\b)?.?' <<<"$txt")
  (( acc >= 1 )) || echo "census inspected zero sites — vacuous"
}
w9_summary_check() { # <workflow text>: prints one problem per line; no output means the Restore summary step holds its contract
  local wf="$1" body keys sif envm xrc v rc out f sd="$W9_TMP/sum" bashbin
  w9_p=""; bashbin="$(command -v bash)"
  body="$(timeout 30 python3 -I -c "$W9_PY" sumextract "$SUMMARY_STEP" "$RESTORE_STEP" <<<"$wf")"; xrc=$?
  case "$xrc" in
    0) ;;
    6) w9_add "summary step position: the ${SUMMARY_STEP} step must come after the restore step in registry_store_restore"; printf '%s' "$w9_p"; return ;;
    *) w9_add "summary step missing, duplicated or outside job registry_store_restore (extract rc ${xrc})"; printf '%s' "$w9_p"; return ;;
  esac
  [[ -n "$body" ]] || { w9_add "summary step has no run: body"; printf '%s' "$w9_p"; return; }
  keys="$(timeout 30 python3 -I -c "$W9_PY" sumkeys "$SUMMARY_STEP" "$RESTORE_STEP" <<<"$wf")" || keys=""
  sif="$(sed -n 's/^if=//p' <<<"$keys")"
  [[ "$sif" == "always()" ]] || w9_add "summary step if drifted: want exactly always() so it runs after a failure or a cancel (got: ${sif:-nothing})"
  [[ -z "$(sed -n 's/^keys=//p' <<<"$keys")" ]] || w9_add "summary step keys ($(sed -n 's/^keys=//p' <<<"$keys")) change how it runs and that this harness does not model"
  envm="$(timeout 30 python3 -I -c "$W9_PY" env "$SUMMARY_STEP" <<<"$wf")" || envm=""
  [[ "$envm" == 'RESTORE_RESULT=${{ job.status }}' ]] \
    || w9_add "summary step env drifted: want exactly RESTORE_RESULT from job.status and no other key (got: ${envm//$'\n'/ ; })"
  assert_fixture_dir "$W9_TMP"
  for v in success cancelled failure ""; do
    rm -rf "$sd"; mkdir -p "$sd"; : > "$sd/summary.md"
    out="$(cd "$sd" && timeout 30 env -i PATH=/nonexistent RESTORE_RESULT="$v" GITHUB_STEP_SUMMARY="$sd/summary.md" \
      "$bashbin" --noprofile --norc -eo pipefail -c "$body" 2>&1 </dev/null)"; rc=$?
    [[ "$rc" == 0 ]] || w9_add "summary run: the body exited ${rc} for RESTORE_RESULT='${v}'"
    [[ -z "$out" ]] || w9_add "summary stdout is not empty for RESTORE_RESULT='${v}' (got: ${out:0:80})"
    f="$(cat "$sd/summary.md")"
    [[ -n "$f" ]] || { w9_add "summary file is empty for RESTORE_RESULT='${v}'"; continue; }
    [[ "$(head -1 <<<"$f")" == "## registry store restore" ]] || w9_add "summary heading is not '## registry store restore' for RESTORE_RESULT='${v}'"
    case "$v" in
      success)   { grep -qF 'closed' <<<"$f" && ! grep -qiw 'failed' <<<"$f"; } || w9_add "summary outcome success must say closed and not failed" ;;
      cancelled) { grep -qF 'cancelled' <<<"$f" && ! grep -qF 'closed' <<<"$f"; } || w9_add "summary outcome cancelled must say cancelled and not closed" ;;
      *)         { grep -qiw 'failed' <<<"$f" && ! grep -qF 'closed' <<<"$f"; } || w9_add "summary outcome failed must say failed and not closed (RESTORE_RESULT='${v}')" ;;
    esac
  done
  printf '%s' "$w9_p"
}
w9_check() { # <workflow text> <engine text>: prints one problem per line; no output means the contract holds
  local wf="$1" eng="$2" envm jobm jif body hdr emit maxv code line want tested keys xrc sites
  w9_p=""
  [[ -n "$eng" ]] || { echo "the restore engine is missing or empty at ${RESTORE_ENGINE}"; return; }
  hdr="$(restore_header_codes <<<"$eng" | grep -vx 1)"; emit="$(restore_emit_codes <<<"$eng" | grep -vx 1)"
  [[ "$hdr" == "$emit" ]] || w9_add "the engine header table (${hdr//$'\n'/ }) differs from the codes its die/exit sites emit (${emit//$'\n'/ }), both without 1"
  sites="$(w9_computed_sites <<<"$eng")"
  [[ -z "$sites" ]] || w9_add "computed die/exit site (restore_emit_codes reads literal codes only, so the comparison above cannot see it): ${sites//$'\n'/ ; }"
  tested="$({ echo 1; restore_header_codes <<<"$eng"; } | sort -un)"
  [[ "$(grep -c . <<<"$tested")" -ge 7 ]] || w9_add "the engine header yielded fewer than 7 failure codes (header reshaped?)"
  body="$(timeout 30 python3 -I -c "$W9_PY" extract "$RESTORE_STEP" <<<"$wf")"; xrc=$?
  [[ "$xrc" == 0 ]] || { w9_add "the restore step is missing, duplicated or outside job registry_store_restore (extract rc ${xrc})"; printf '%s' "$w9_p"; return; }
  [[ -n "$body" ]] || { w9_add "the restore step has no run: body"; printf '%s' "$w9_p"; return; }
  keys="$(timeout 30 python3 -I -c "$W9_PY" keys "$RESTORE_STEP" <<<"$wf")"
  [[ -z "$keys" ]] || w9_add "the restore step has step keys (${keys//$'\n'/ }) that change how it runs and that this harness does not model"
  envm="$(timeout 30 python3 -I -c "$W9_PY" env "$RESTORE_STEP" <<<"$wf")" || envm=""
  [[ "$envm" == $'DOPPLER_TOKEN=${{ secrets.DOPPLER_TOKEN_PRD }}\nGH_TOKEN_FOR_ENGINE=${{ secrets.GITHUB_TOKEN }}' ]] \
    || w9_add "the restore step's credential env drifted: want exactly DOPPLER_TOKEN from secrets.DOPPLER_TOKEN_PRD and GH_TOKEN_FOR_ENGINE from secrets.GITHUB_TOKEN and no other key (got: ${envm//$'\n'/ ; })"
  jobm="$(timeout 30 python3 -I -c "$W9_PY" job "$RESTORE_STEP" <<<"$wf")" || jobm=""
  jif="$(sed -n 's/^if=//p' <<<"$jobm")"
  [[ "$jif" == "!cancelled() && needs.registry_luks_recut.outputs.store_refill_needed == 'true'" ]] \
    || w9_add "the job-level if of registry_store_restore drifted: want exactly !cancelled() && needs.registry_luks_recut.outputs.store_refill_needed == 'true' (got: ${jif:-nothing})"
  [[ "$(sed -n 's/^needs=//p' <<<"$jobm")" == registry_luks_recut && "$(sed -n 's/^keys=//p' <<<"$jobm")" == "environment if needs permissions runs-on steps timeout-minutes" ]] \
    || w9_add "the job-level keys of registry_store_restore drifted: want needs registry_luks_recut and exactly the keys environment if needs permissions runs-on steps timeout-minutes (got: ${jobm//$'\n'/ ; })"
  maxv="$(sed -nE 's/^[[:space:]]*max=([0-9]+)[[:space:]]*$/\1/p' <<<"$body" | head -1)"
  [[ -n "$maxv" ]] || { w9_add "the restore step has no max= retry bound"; maxv=1; }
  for code in 0 $tested 137; do
    w9_parse "$(w9_run "$body" "$code")"
    want=1; [[ "$code" == 3 ]] && want="$maxv"
    [[ "$w9_rc" == "$code" ]] || w9_add "step exited ${w9_rc}, want ${code} (engine exit ${code})"
    [[ "$w9_calls" == "$want" ]] || w9_add "engine called ${w9_calls} times for exit ${code}, want ${want}"
    if [[ "$code" == 0 && "$w9_calls" -ge 1 ]]; then
      [[ "${w9_first#* }" == "--target 127.0.0.1:5000 --tags-from ${W9_TMP}/run/tmp/pins/restore-pins.json" ]] \
        || w9_add "the engine's first call has the wrong arguments (got: ${w9_first#* })"
      [[ "${w9_first%% *}" != *x* ]] || w9_add "the engine was invoked traced (shell flags: ${w9_first%% *})"
    fi
    line="$(grep -E '^::error::restore FAILED|^restore:' <<<"$w9_out" | head -1)"
    if [[ "$code" == 0 ]]; then
      [[ "$line" == restore:* ]] || w9_add "exit 0 printed no success line"; continue
    fi
    [[ "$line" =~ exit\ ${code}([^0-9]|$) ]] || { w9_add "exit ${code} printed no annotation naming it (got: ${line:-nothing})"; continue; }
    if grep -qx "$code" <<<"$tested" && grep -qiF 'unenumerated' <<<"$line"; then w9_add "exit ${code} fell to the *) arm"; fi
    case "$code" in
      2|5) grep -qiF 'failed locally' <<<"$line" || w9_add "the annotation for exit ${code} does not name the local login failure" ;;
      1)   grep -qiF 'manifest' <<<"$line" || w9_add "the annotation for exit 1 does not name the manifest fault" ;;
      78)  grep -qiF 'traced invocation' <<<"$line" || w9_add "the annotation for exit 78 does not say traced invocation" ;;
    esac
  done
  w9_parse "$(w9_run "$body" "3 3 0")"
  [[ "$w9_rc" == 0 && "$w9_calls" == 3 ]] || w9_add "the recovered retry (engine exits 3 3 0) ended with step status ${w9_rc} after ${w9_calls} engine calls, want 0 after 3"
  grep -q '^restore:' <<<"$w9_out" || w9_add "the recovered retry printed no success line"
  grep -qF '::notice::restore attempt 1/' <<<"$w9_out" || w9_add "the recovered retry printed no retry notice"
  w9_parse "$(w9_run "$body" 0 dopfail)"
  [[ "$w9_rc" == 1 && "$w9_calls" == 0 ]] || w9_add "doppler failure: step exited ${w9_rc} after ${w9_calls} engine calls, want 1 after 0"
  grep -qF 'registry-store-restore ABORT' <<<"$w9_out" || w9_add "doppler failure: no 'registry-store-restore ABORT' annotation"
  printf '%s' "$w9_p"
}
w9_problems="$(w9_check "$RESTORE_WF_TEXT" "$RESTORE_ENGINE_TEXT")"
_report "$W9_ROW" "$(w9_verdict "$w9_problems")" "${w9_problems//$'\n'/; }"
# Nested proof run (the meta-control below runs this suite on a drop1-mutated tree): stop right after the W9 row, with a code that is
# never 0, so an exported W9_NESTED can neither recurse into the meta-control nor make a run go green.
if [[ "${W9_NESTED:-}" == 1 ]]; then
  printf '\n=== nested W9 proof: %d passed, %d failed ===\n' "$passes" "$fails"
  exit 64
fi

# W9 controls: each mutates the REAL workflow text (or adds one `die` to the engine), checks the
# mutation landed, and requires the same check to refuse it with a message naming the right thing.
for w9_c in "drop78|exit 78 fell" "dead|exit 78 fell" "nested|exit 78 fell" "subject|fell to the *) arm" \
  "clobber|step exited 0" "sticky3|recovered retry" "exit0|step exited 0" "trap|step exited 0" "max0|recovered retry" \
  "wrongscript|engine called 0 times" "dopabort|doppler failure" "traced|invoked traced" "args|wrong arguments" "stepkeys|step keys" \
  "drop1|exit 1 fell" "manifest|does not name the manifest fault" "envswap|credential env" "envextra|credential env drifted" \
  "jobif|job-level if" "ifor|job-level if" "jobcoe|job-level keys" "jobctr|job-level keys"; do
  w9_mut="$(timeout 30 python3 -I -c "$W9_PY" "mutate:${w9_c%%|*}" "$RESTORE_STEP" <<<"$RESTORE_WF_TEXT")"
  if [[ -z "$w9_mut" || "$w9_mut" == "$RESTORE_WF_TEXT" ]]; then
    _report "W9 control ${w9_c%%|*}: the mutation landed" fail "the mutation did not change the workflow"; continue
  fi
  w9_out="$(w9_check "$w9_mut" "$RESTORE_ENGINE_TEXT")"
  [[ "${w9_c%%|*}" == drop1 ]] && w9_drop1_mut="$w9_mut" && w9_drop1_out="$w9_out"
  _report "W9 control ${w9_c%%|*}: refused" "$(w9_expect "${w9_c#*|}" "$w9_out")" "expected a refusal naming '${w9_c#*|}', got: ${w9_out:-<nothing>}"
done
# One more code than the engine's header or its die/exit sites carry, so the control cannot go stale
# when the engine legitimately gains a code of its own.
w9_hi=$(( $({ restore_header_codes <<<"$RESTORE_ENGINE_TEXT"; restore_emit_codes <<<"$RESTORE_ENGINE_TEXT"; } | sort -n | tail -1) + 1 ))
w9_out="$(w9_check "$RESTORE_WF_TEXT" "${RESTORE_ENGINE_TEXT}"$'\n'"die ${w9_hi} \"a code the header does not list\"")"
_report "W9 control engine-extra-code: refused" "$(w9_expect differs "$w9_out")" "expected a refusal naming 'differs', got: ${w9_out:-<nothing>}"

# W9c controls (residual 3b): each appends ONE line to the real engine text and requires the census to name exactly it.
# The census on the unmutated text must be empty first, so the appended line is the only thing that can have produced the offender.
w9_cn=$(( $(wc -l <<<"$RESTORE_ENGINE_TEXT") + 1 ))
w9_cbase="$(w9_computed_sites <<<"$RESTORE_ENGINE_TEXT")"
for w9_cc in 'computed|die "$c" "x"|die' 'bare|exit|exit' 'twospace|die  7 "x"|die' 'partial|die 3$x "x"|die 3$'; do
  IFS='|' read -r w9_cname w9_cline w9_ctok <<<"$w9_cc"
  w9_cout="$(w9_computed_sites <<<"${RESTORE_ENGINE_TEXT}"$'\n'"${w9_cline}")"
  if [[ -z "$w9_cbase" && "$w9_cout" == "${w9_cn}:${w9_ctok}" ]]; then _report "W9c control ${w9_cname}: the census names the appended line" ok
  else _report "W9c control ${w9_cname}: the census names the appended line" fail "want exactly '${w9_cn}:${w9_ctok}' over an empty baseline; baseline: ${w9_cbase:-<empty>}; got: ${w9_cout:-<nothing>}"; fi
done
w9_cout="$(w9_computed_sites <<<"")"
if grep -qF 'inspected zero sites' <<<"$w9_cout"; then _report "W9c control zero-sites: an empty text is vacuous, not clean" ok
else _report "W9c control zero-sites: an empty text is vacuous, not clean" fail "got: ${w9_cout:-<nothing>}"; fi
w9_out="$(w9_check "$RESTORE_WF_TEXT" "${RESTORE_ENGINE_TEXT}"$'\n''die "$c" "x"')"
if grep -qF 'computed die/exit site' <<<"$w9_out"; then _report "W9c control wire-in: w9_check refuses a computed die" ok
else _report "W9c control wire-in: w9_check refuses a computed die" fail "got: ${w9_out:-<nothing>}"; fi
w9_cout="$(w9_computed_sites <<<"${RESTORE_ENGINE_TEXT}"$'\n''die 7 "x"'$'\n''# exit $x')"
if [[ -z "$w9_cbase" && -z "$w9_cout" ]]; then _report "W9c control must-pass: a literal die and a whole-line comment are accepted" ok
else _report "W9c control must-pass: a literal die and a whole-line comment are accepted" fail "baseline: ${w9_cbase:-<empty>}; got: ${w9_cout:-<nothing>}"; fi

# W9s: the Restore summary step (residual 3a). The controls mutate the REAL workflow text, check the mutation landed,
# and each requires a fragment only its own pin produces.
w9s_problems="$(w9_summary_check "$RESTORE_WF_TEXT")"
if [[ -z "$w9s_problems" ]]; then _report "W9s the Restore summary step runs always and prints the matching outcome block" ok
else _report "W9s the Restore summary step runs always and prints the matching outcome block" fail "${w9s_problems//$'\n'/; }"; fi
for w9_sc in "sumifdrop|summary step if" "sumenvlit|summary step env" "sumswap|summary outcome success" "sumredirect|summary stdout" "sumorder|summary step position"; do
  w9_mut="$(timeout 30 python3 -I -c "$W9_PY" "mutate:${w9_sc%%|*}" "$SUMMARY_STEP" "$RESTORE_STEP" <<<"$RESTORE_WF_TEXT")"
  if [[ -z "$w9_mut" || "$w9_mut" == "$RESTORE_WF_TEXT" ]]; then
    _report "W9s control ${w9_sc%%|*}: the mutation landed" fail "the mutation did not change the workflow"; continue
  fi
  w9_out="$(w9_summary_check "$w9_mut")"
  if grep -qF -- "${w9_sc#*|}" <<<"$w9_out"; then _report "W9s control ${w9_sc%%|*}: refused" ok
  else _report "W9s control ${w9_sc%%|*}: refused" fail "expected a refusal naming '${w9_sc#*|}', got: ${w9_out:-<nothing>}"; fi
done
w9_mut="$(timeout 30 python3 -I -c "$W9_PY" "mutate:sumreword" "$SUMMARY_STEP" "$RESTORE_STEP" <<<"$RESTORE_WF_TEXT")"
if [[ -z "$w9_mut" || "$w9_mut" == "$RESTORE_WF_TEXT" ]]; then
  _report "W9s control sumreword: the mutation landed" fail "the mutation did not change the workflow"
else
  w9_out="$(w9_summary_check "$w9_mut")"
  if [[ -z "$w9_out" ]]; then _report "W9s control sumreword: a reworded, still-correct step is accepted" ok
  else _report "W9s control sumreword: a reworded, still-correct step is accepted" fail "${w9_out//$'\n'/; }"; fi
fi

# W9v canary (residual 3c): the verdict function must map a missing needle to fail and a present one to ok.
if [[ "$(w9_expect needle 'a haystack without it')" == fail && "$(w9_expect needle 'a haystack with a needle in it')" == ok ]]; then
  _report "W9v canary: w9_expect maps a missing needle to fail and a present one to ok" ok
else _report "W9v canary: w9_expect maps a missing needle to fail and a present one to ok" fail "the verdict function does not discriminate"; fi

# W9v meta-control (residual 3c): run THIS suite, nested, on a tree whose workflow has the drop1 mutation. The real W9 row must
# print exactly the FAIL line the drop1 control above expects. A row swapped to `if true`, flipped, or hardcoded to ok prints no FAIL
# line there; a copy missing a file prints a different FAIL line (a fragment match would pass that, so the whole detail is compared).
w9_meta="$W9_TMP/meta"; w9_mp=""
assert_fixture_dir "$w9_meta"
rm -rf "$w9_meta"; mkdir -p "$w9_meta/tests/scripts/lib" "$w9_meta/scripts" "$w9_meta/.github/workflows"
for w9_f in "tests/scripts/lib/restore-engine-header.sh" "scripts/registry-restore-from-ghcr.sh" "scripts/derive-app-domain-base.sh"; do
  if [[ -f "${ROOT}/${w9_f}" ]]; then cp -p "${ROOT}/${w9_f}" "$w9_meta/${w9_f}"; else w9_mp+="the copy list names ${w9_f}, which does not exist; "; fi
done
cp "${BASH_SOURCE[0]}" "$w9_meta/tests/scripts/test-registry-d10-workflow-wiring.sh" || w9_mp+="the suite itself could not be copied; "
cp -R "${ROOT}/.github/actions" "$w9_meta/.github/actions" || w9_mp+=".github/actions could not be copied; "
printf '%s\n' "$w9_drop1_mut" > "$w9_meta/.github/workflows/apply-web-platform-infra.yml"
[[ -n "$w9_drop1_mut" && "$(cat "$w9_meta/.github/workflows/apply-web-platform-infra.yml")" != "$RESTORE_WF_TEXT" ]] || w9_mp+="the drop1 mutation did not land in the nested workflow; "
w9_nout="$(cd "$w9_meta" && W9_NESTED=1 timeout 120 bash "$w9_meta/tests/scripts/test-registry-d10-workflow-wiring.sh" 2>&1 </dev/null)"; w9_nrc=$?
[[ "$w9_nrc" == 64 ]] || w9_mp+="the nested run exited ${w9_nrc}, want 64; "
w9_nfails="$(grep -c '^  FAIL ' <<<"$w9_nout")"
[[ "$w9_nfails" == 1 ]] || w9_mp+="the nested run printed ${w9_nfails} FAIL lines, want exactly 1; "
[[ "$(grep '^  FAIL ' <<<"$w9_nout")" == "  FAIL ${W9_ROW} — ${w9_drop1_out//$'\n'/; }" ]] \
  || w9_mp+="the nested FAIL line is not the W9 row carrying the drop1 control's detail (got: $(grep '^  FAIL ' <<<"$w9_nout" | head -1 | cut -c1-200)); "
# Inline on purpose: reporting through w9_verdict would share the very function this control exists to catch (a verdict that is always ok).
if [[ -z "$w9_mp" ]]; then _report "W9v meta-control: a drop1 workflow makes the real W9 row print its FAIL line" ok
else _report "W9v meta-control: a drop1 workflow makes the real W9 row print its FAIL line" fail "$w9_mp"; fi

# ── Anti-vacuity assertion floor ────────────────────────────────────────────────────────────
# Measured: neutering `_report` to `return 0` reported "0 passed, 0 failed" and exit 0 — a
# suite asserting nothing is byte-indistinguishable from one that passed, because `fails` is a
# single unguarded integer. Pinned EXACTLY: a `>=` re-opens the hole on the next added row.
EXPECTED_ASSERTIONS=63
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_ASSERTIONS" ]]; then
  printf '  FAIL anti-vacuity: %d assertions passed, expected exactly %d — rows were added, removed, or silenced\n' \
    "$passes" "$EXPECTED_ASSERTIONS"
  fails=$((fails + 1))
fi

printf '\n=== %d passed, %d failed ===\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || exit 1
