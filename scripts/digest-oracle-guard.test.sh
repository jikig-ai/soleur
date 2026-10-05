#!/usr/bin/env bash
# Regression harness for the rendered-credential digest oracle (#7140 / #7103 R4).
#
# WHAT WENT WRONG, AND WHY A SHAPE CHECK COULD NOT SEE IT.
#
# `var.doppler_token` is `sensitive = true`, and sensitivity propagates through the local and
# through base64encode(), so `terraform console` prints the literal string `(sensitive value)`.
# That string fed to `base64 -d` fails; the failure was swallowed by `2>/dev/null`; the empty
# result reached `sha256sum`; and sha256("") is
# e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 — a perfectly well-formed
# 64-hex string. The old `[[ =~ ^[0-9a-f]{64}$ ]]` check passed, the step announced "tier-2 byte
# compare ACTIVE", and it armed the gate with a digest that can never match ANY real file. The
# gate then reported content_mismatch and blamed the delivery. Its first real execution
# (run 30708795115) failed a delivery that was byte-correct.
#
# A shape check cannot distinguish "hashed the payload" from "hashed nothing". This harness
# exists so that property is asserted rather than reasoned about.
#
# HOW IT RUNS. The step's `run:` script is EXTRACTED FROM THE WORKFLOW rather than copied here.
# A copy would agree with itself while disagreeing with the workflow — a guard that passes
# precisely when it is wrong. It is then executed under `env -i` with stubbed `doppler` and
# `terraform`, so the arms below are pure functions of what those tools return.
#
# Registered in scripts/test-all.sh, which runs inside the required `test` context (verified
# against the live ruleset). That gating is deliberate: the harness needs no tooling the `test`
# job does not already have (python3 + PyYAML), and putting a regression guard in a runner
# nobody is blocked by would reproduce, in this very PR, the defect R5 exists to fix.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="$REPO_ROOT/.github/workflows/apply-deploy-pipeline-fix.yml"
STEP_ID="rendered_digest"
EMPTY_SHA="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
ENV_KEY="INFRA_CONFIG_RENDERED_SHA__ETC_DEFAULT_SOLEUR_DOPPLER_TOKEN"

pass=0; fail=0; asserts=0
# `asserts` is incremented at the CALL SITE, never inside ok()/bad(). That placement is the
# whole substance of the accounting-conservation check at the bottom of this file: a counter
# that moves inside both verdict helpers moves WITH the verdict, so stubbing bad() to a no-op
# drops the row and its count together and `pass+fail == asserts` still holds. Measured on this
# shape before the fix: a neutered bad() printed "conservation GREEN — defect hidden", rc 0.
#
# Never increment inside `$( )` — a subshell discards it.
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }
# One assertion is about to be decided; eq() always resolves to exactly one verdict.
eq()  { asserts=$((asserts + 1)); if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi }

TMP="$(mktemp -d)" || { echo "SETUP FAILED: mktemp"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

[[ -f "$WF" ]] || { echo "SETUP FAILED: workflow not found at $WF"; exit 2; }
command -v python3 >/dev/null || { echo "SETUP FAILED: python3 absent"; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "SETUP FAILED: PyYAML absent (the required 'test' job has it; see 0.4)"; exit 2; }

echo "=== digest-oracle-guard (#7140 / #7103 R4) ==="

# --- Extract the step body from the workflow -----------------------------------------------
SCRIPT="$TMP/step.sh"
python3 - "$WF" "$STEP_ID" "$SCRIPT" <<'PY' || { echo "SETUP FAILED: could not extract the step"; exit 2; }
import sys, yaml
wf, step_id, out = sys.argv[1], sys.argv[2], sys.argv[3]
doc = yaml.safe_load(open(wf))
found = []
for job in (doc.get("jobs") or {}).values():
    for step in (job.get("steps") or []):
        if step.get("id") == step_id:
            found.append(step)
if len(found) != 1:
    sys.stderr.write("expected exactly 1 step with id=%s, found %d\n" % (step_id, len(found)))
    sys.exit(1)
run = found[0].get("run")
if not run:
    sys.stderr.write("step has no run: block\n"); sys.exit(1)
open(out, "w").write(run)
PY

# --- FIXTURE PRECONDITION SELF-CHECK (5.6) --------------------------------------------------
# If a refactor renames the step or drops the id, the extraction above still "succeeds" against
# nothing and every arm below passes vacuously. These make that a loud FIXTURE error rather than
# a phantom green.
asserts=$((asserts + 1))
if [[ -s "$SCRIPT" ]]; then ok "extracted a non-empty step body for id=$STEP_ID"; else bad "extracted step body is EMPTY — every arm below would be vacuous"; fi
for token in 'base64 -d' 'sha256sum' "$ENV_KEY"; do
  asserts=$((asserts + 1))
  if grep -qF -- "$token" "$SCRIPT"; then
    ok "extracted body still contains '$token' (fixture is the real oracle)"
  else
    bad "extracted body lacks '$token' — the harness is not testing the digest oracle any more"
  fi
done

# --- No-interpolation assertion (5.5) -------------------------------------------------------
# The body must not carry ${{ }} expressions. This harness runs it as plain bash, so an
# interpolation would be a literal string here and a DIFFERENT program in CI — the harness would
# be testing something the workflow never executes. It is also the workflow-injection surface.
asserts=$((asserts + 1))
# shellcheck disable=SC2016
if grep -q '\${{' "$SCRIPT"; then
  bad "step body contains a \${{ }} expression — it would evaluate differently in CI than under this harness"
else
  ok "step body contains no \${{ }} interpolation (harness runs the same program CI does)"
fi

# --- pull_request_target refusal (5.3) ------------------------------------------------------
# This workflow holds prd Doppler credentials. pull_request_target runs with the BASE repo's
# secrets against a HEAD-controlled checkout, so it would hand those credentials to any fork PR.
asserts=$((asserts + 1))
if python3 -c "
import sys, yaml
d = yaml.safe_load(open('$WF'))
on = d.get(True) or d.get('on') or {}
on = on if isinstance(on, dict) else {k: None for k in ([on] if isinstance(on, str) else on)}
sys.exit(0 if 'pull_request_target' in on else 1)
" 2>/dev/null; then
  bad "workflow triggers on pull_request_target while holding prd credentials"
else
  ok "workflow does not trigger on pull_request_target"
fi

# --- The runner: execute the step hermetically ----------------------------------------------
# `env -i` so nothing from this shell (or a developer's Doppler session) can influence the
# result. Each arm gets its OWN GITHUB_ENV tempfile — a shared one would let arm N's export
# satisfy arm N+1's assertion, which is exactly the cross-contamination that makes a suite
# report success it never earned.
#
# The stubs VALIDATE their argv: `terraform` must be asked to `console`, and `doppler` must be
# invoked with the tf-var name transformer. A stub answering regardless of its arguments would
# let the step query the wrong thing and still go green.
run_arm() {
  local console_out="$1" console_rc="$2"
  ARM_ENV="$TMP/github_env.$RANDOM.$$"; : > "$ARM_ENV"
  local bin="$TMP/bin.$RANDOM.$$"; mkdir -p "$bin"

  printf '%s' "$console_out" > "$bin/console_out"
  printf '%s' "$console_rc"  > "$bin/console_rc"

  cat > "$bin/terraform" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "console" ]] || { echo "stub terraform: expected 'console', got '$1'" >&2; exit 64; }
cat "$(dirname "$0")/console_out"
exit "$(cat "$(dirname "$0")/console_rc")"
STUB
  cat > "$bin/doppler" <<'STUB'
#!/usr/bin/env bash
# `doppler run --name-transformer tf-var -- <cmd...>` — assert the shape, then exec the tail.
[[ "$1" == "run" ]] || { echo "stub doppler: expected 'run', got '$1'" >&2; exit 64; }
case " $* " in *" --name-transformer tf-var "*) : ;; *) echo "stub doppler: missing --name-transformer tf-var" >&2; exit 64 ;; esac
shift
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
[[ "$1" == "--" ]] || { echo "stub doppler: no -- separator" >&2; exit 64; }
shift
exec "$@"
STUB
  chmod +x "$bin/terraform" "$bin/doppler"

  ARM_OUT=$(env -i \
    PATH="$bin:/usr/bin:/bin" \
    HOME="$TMP" \
    GITHUB_ENV="$ARM_ENV" \
    CI_SSH_PUB="$TMP/fake.pub" \
    bash "$SCRIPT" 2>&1)
  # shellcheck disable=SC2034  # read by arms that assert on the step's exit status
  ARM_RC=$?
  ARM_EXPORT=$(sed -n "s/^${ENV_KEY}=//p" "$ARM_ENV")
}

# Synthesized fixture only — never a real rendered credential. This is the shape the template
# produces (a DOPPLER_TOKEN= assignment plus siblings); the token value is invented.
RENDERED=$'DOPPLER_TOKEN=dp.st.NOT_A_REAL_TOKEN_synthesized_for_test\nSENTRY_PROJECT_ID=123\n'
GOOD_B64=$(printf '%s' "$RENDERED" | base64 -w0)
GOOD_SHA=$(printf '%s' "$RENDERED" | sha256sum | awk '{print $1}')

# --- Arm 1: the happy path exports the REAL digest ------------------------------------------
run_arm "$GOOD_B64" 0
eq "valid render exports the digest of the rendered bytes" "$GOOD_SHA" "$ARM_EXPORT"
asserts=$((asserts + 1))
if grep -q 'tier-2 byte compare ACTIVE' <<<"$ARM_OUT"; then ok "valid render announces tier-2 ACTIVE"; else bad "no tier-2 announcement: $ARM_OUT"; fi

# --- Arm 2: THE #7140 RESIDUAL — `(sensitive value)` must NOT arm the gate -------------------
# The headline case. This is what shipped, and what a shape check certified as ACTIVE.
run_arm '(sensitive value)' 0
eq "(sensitive value) exports NOTHING" "" "$ARM_EXPORT"
asserts=$((asserts + 1))
if [[ "$ARM_EXPORT" == "$EMPTY_SHA" ]]; then
  bad "(sensitive value) exported sha256 of the EMPTY STRING — #7140 has regressed"
else
  ok "(sensitive value) did not export sha256(\"\") — the empty-digest oracle is dead"
fi
asserts=$((asserts + 1))
if grep -q '::warning::' <<<"$ARM_OUT"; then ok "(sensitive value) degrades LOUDLY with a ::warning::"; else bad "silent degrade — a weaker gate would be mistaken for a passing one"; fi

# --- Arm 3: terraform console fails outright ------------------------------------------------
run_arm '' 1
eq "a failed terraform console exports nothing" "" "$ARM_EXPORT"
asserts=$((asserts + 1))
if grep -q '::warning::' <<<"$ARM_OUT"; then ok "console failure degrades loudly"; else bad "console failure degraded silently"; fi

# --- Arm 4: empty output with a SUCCESS rc --------------------------------------------------
# The nastiest shape: rc=0 says "it worked", stdout says nothing. Must not become sha256("").
run_arm '' 0
eq "empty console output with rc=0 exports nothing" "" "$ARM_EXPORT"
asserts=$((asserts + 1))
if [[ "$ARM_EXPORT" == "$EMPTY_SHA" ]]; then bad "empty-but-successful output produced sha256(\"\")"; else ok "empty-but-successful output did not produce sha256(\"\")"; fi

# --- Arm 5: MARKER ABSENT — decodable base64 that is not the credential ----------------------
# Guards the CONTENT check specifically. This input decodes cleanly, so a decode-succeeded test
# would pass it; only requiring the template's own DOPPLER_TOKEN= marker rejects it.
NOMARKER_B64=$(printf 'SOME_OTHER_KEY=value\n' | base64 -w0)
run_arm "$NOMARKER_B64" 0
eq "decodable payload WITHOUT the DOPPLER_TOKEN= marker exports nothing" "" "$ARM_EXPORT"

# --- Arm 5b: the marker check is pinned to THE MARKER, not to any key in the fixture ---------
# Arm 5's positive fixture carries a CONFOUNDER: RENDERED holds SENTRY_PROJECT_ID= as well as
# DOPPLER_TOKEN=, and its negative holds SOME_OTHER_KEY=. So every mutation that swaps the
# grep for something present in the first and absent from the second survived — measured, all
# at 24/24 green: '^DOPPLER_TOKEN=' -> '^SENTRY_PROJECT_ID=', dropping the '^' anchor, and
# widening to 'TOKEN='. These two fixtures sit on the missing side of exactly those mutations.
SENTRY_ONLY_B64=$(printf 'SENTRY_PROJECT_ID=123\n' | base64 -w0)
run_arm "$SENTRY_ONLY_B64" 0
eq "a payload with only the SIBLING key exports nothing (the check is not keyed on it)" "" "$ARM_EXPORT"

# A commented-out marker is not a marker. Without the '^' anchor this decodes, matches, and arms
# the gate with a digest of the wrong bytes — re-creating #7140 in a new shape.
COMMENTED_B64=$(printf '#DOPPLER_TOKEN=dp.st.NOT_A_REAL_TOKEN_synthesized_for_test\n' | base64 -w0)
run_arm "$COMMENTED_B64" 0
eq "a COMMENTED-OUT marker does not arm the gate (the ^ anchor is load-bearing)" "" "$ARM_EXPORT"

# --- Arm 5c: console_rc is a real conjunct ---------------------------------------------------
# The guard is `[[ "$console_rc" -eq 0 && -n "$b64" ]]`. The fixture matrix never instantiated
# the one cell that discriminates it — valid, decodable output alongside a NON-ZERO rc — so
# dropping the rc conjunct entirely passed 24/24. A terraform console that prints usable output
# and still fails must not arm the gate.
run_arm "$GOOD_B64" 1
eq "a non-zero console rc exports nothing even when the output decodes" "" "$ARM_EXPORT"

# --- Arm 6: quoted output (terraform console emits a quoted string) -------------------------
# The step strips quotes before decoding; assert that survives, or every real run degrades.
run_arm "\"$GOOD_B64\"" 0
eq "quoted console output is unquoted before decoding" "$GOOD_SHA" "$ARM_EXPORT"

# --- Arm 7: ERREXIT — the step must degrade, not abort (5.2) --------------------------------
# GitHub runs `run:` blocks as `bash -e {0}`. The step's stated invariant is "degrades loudly,
# never blocks", so it must turn errexit OFF explicitly; adding only -u and pipefail leaves it
# ON. Re-run arm 3 (a failing console) under an errexit-on shell, mirroring CI: the step must
# still reach its warning and exit 0.
ARM_ENV="$TMP/github_env.errexit"; : > "$ARM_ENV"
bin="$TMP/bin.errexit"; mkdir -p "$bin"
printf '' > "$bin/console_out"; printf '1' > "$bin/console_rc"
cat > "$bin/terraform" <<'STUB'
#!/usr/bin/env bash
cat "$(dirname "$0")/console_out"; exit "$(cat "$(dirname "$0")/console_rc")"
STUB
cat > "$bin/doppler" <<'STUB'
#!/usr/bin/env bash
shift; while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done; shift; exec "$@"
STUB
chmod +x "$bin/terraform" "$bin/doppler"
E_OUT=$(env -i PATH="$bin:/usr/bin:/bin" HOME="$TMP" GITHUB_ENV="$ARM_ENV" CI_SSH_PUB="$TMP/fake.pub" \
  bash -e "$SCRIPT" 2>&1); E_RC=$?
eq "under CI's 'bash -e', a failing console still exits 0 (degrades, never blocks)" "0" "$E_RC"
asserts=$((asserts + 1))
if grep -q '::warning::' <<<"$E_OUT"; then ok "errexit arm still reaches its ::warning::"; else bad "errexit arm aborted before warning: $E_OUT"; fi
# And assert the mechanism, not just the outcome — so a future edit removing `set +e` while the
# body happens to have no failing command still reds here.
asserts=$((asserts + 1))
if grep -qE '^[[:space:]]*set \+e[[:space:]]*$' "$SCRIPT"; then
  ok "step explicitly disables errexit (set +e), rather than relying on every command succeeding"
else
  bad "step does not 'set +e'; GitHub supplies 'bash -e {0}', so its degrade-never-block invariant is not in force"
fi

# --- Secret masking (5.1) -------------------------------------------------------------------
# The repo is public and nonsensitive() strips Terraform's protection, so the decoded value is a
# live prd token. The mask must be registered BEFORE the decode/hash pipeline that consumes it —
# a mask emitted after a leak does not retroactively redact it.
# ANCHORED ON THE CODE CONSTRUCT, NOT THE BARE TOKEN. Both `::add-mask::` and `sha256sum` also
# appear in this step's own explanatory comments, so a bare `grep -n <token> | head -1` returns a
# COMMENT line and the ordering comparison becomes a comparison of prose positions. That is
# exactly the false-anchor class this repo has recorded repeatedly — and the first draft of this
# very assertion tripped it, reporting a mask at line 50 against a "use" at line 26 that was a
# sentence. A comment line begins with `#`, so requiring `echo "` and the real pipeline shape
# pins code and nothing else.
asserts=$((asserts + 1))
if grep -qE '^[[:space:]]*echo "::add-mask::' "$SCRIPT"; then
  ok "step masks the rendered base64 (repo is public; nonsensitive() strips Terraform's guard)"
  mask_line=$(grep -nE '^[[:space:]]*echo "::add-mask::' "$SCRIPT" | head -1 | cut -d: -f1)
  hash_line=$(grep -nE '^[[:space:]]*[^#].*base64 -d.*\|[[:space:]]*sha256sum' "$SCRIPT" | head -1 | cut -d: -f1)
  # A SECOND assertion is decided inside this branch; counted here, outside the `$( )` above.
  asserts=$((asserts + 1))
  if [[ -n "$mask_line" && -n "$hash_line" && "$mask_line" -lt "$hash_line" ]]; then
    ok "the mask is registered (line $mask_line) before the value is consumed (line $hash_line)"
  else
    bad "::add-mask:: at line ${mask_line:-?} is not before the hash pipeline at ${hash_line:-?}"
  fi
else
  bad "step does not ::add-mask:: the rendered base64 of a live prd token in a PUBLIC repo"
fi
# The mask must cover the base64 itself, not the digest — a digest is a confirmation oracle and
# is meant to be logged. Anchored on the echo for the same reason as above.
asserts=$((asserts + 1))
# shellcheck disable=SC2016
if grep -qE '^[[:space:]]*echo "::add-mask::\$b64"' "$SCRIPT"; then
  ok "the masked value is \$b64 (the base64), not the digest"
else
  bad "::add-mask:: does not name \$b64"
fi

# --- MIN_ASSERTS floor (5.5) ----------------------------------------------------------------
# A broken extraction, a renamed step, or an early `exit` would otherwise let this file report
# success having asserted almost nothing.
# Raised 22 -> 27 alongside the arms added above. The old value left 1 assertion of slack against
# 23 running, and that slack was exactly enough to DELETE Arm 5 — the arm the whole design rests
# on — while still printing "assertion floor met (22 >= 22)". Measured: removing Arm 5 in full
# reported 23 passed, 0 failed, rc 0. A floor with slack is a floor you can walk under.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never through bad(), and it no longer emits an
# ok() row of its own. A floor that reports by calling bad() feeds the same counters the exit
# status reads, so neutering bad() silences the rows AND the floor that exists to notice the
# silence. A floor enforced through the suspect cannot witness the suspect.
#
# RE-RATCHETED from a re-measured green run after that conversion: deleting the floor's own
# `ok "assertion floor met …"` row dropped the SUITE TOTAL 27 -> 26, but it did not move the
# value the floor reads. That row was counted AFTER this check, so `asserts` here was 26 before
# the conversion and is 26 after it. 26 is therefore still exactly zero-slack — measured, not
# inherited: `26 passed, 0 failed (26 assertions)`.
MIN_ASSERTS=26
if [[ "$asserts" -lt "$MIN_ASSERTS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$asserts" "$MIN_ASSERTS" >&2
  echo "digest-oracle-guard.test.sh: $pass passed, $fail failed ($asserts assertions)"
  exit 1
fi

# --- Accounting conservation ----------------------------------------------------------------
# The arm that actually catches a neutered verdict helper. The floor above catches "no assertions
# RAN"; it cannot catch "assertions ran and their verdicts were discarded", because `asserts`
# keeps its full value when bad() is a no-op. Every assertion records exactly one verdict, so
# pass+fail MUST equal asserts. Reported directly for the same reason as the floor.
if [[ $((pass + fail)) -ne "$asserts" ]]; then
  printf '\n[FATAL] accounting: pass+fail (%d) != asserts (%d).\n' \
    "$((pass + fail))" "$asserts" >&2
  if [[ $((pass + fail)) -lt "$asserts" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered ok()/bad() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `asserts=$((asserts + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "digest-oracle-guard.test.sh: $pass passed, $fail failed ($asserts assertions)"
  exit 1
fi

echo "---"
echo "digest-oracle-guard.test.sh: $pass passed, $fail failed ($asserts assertions)"
[[ "$fail" -eq 0 ]] || exit 1
echo "OK"
