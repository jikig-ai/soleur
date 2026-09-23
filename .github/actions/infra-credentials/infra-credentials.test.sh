#!/usr/bin/env bash
# #8209 / ADR-239 — executable test for the tiered credential loader.
#
# WHAT THIS PINS, and why a static grep could not.
#
# The loader is a `run:` body inside a composite action. A grep-shaped assertion over
# that YAML pins its SPELLING; it cannot pin what any arm DECIDES. So this suite
# EXTRACTS the body with PyYAML and EXECUTES it under the runner's own shell
# (`bash --noprofile --norc -eo pipefail`, which is what GitHub gives a `run:` block
# with no `shell:` key) against a stubbed `doppler`. Running it under a bare `bash`
# would make the whole `set -e` defect class structurally invisible.
#
# The stub REFUSES a call it was not told to expect (exit 64). A stub that answers the
# same fixture regardless of `-p`/`-c` puts the seam above everything the loader is
# supposed to get right: it cannot tell "asked soleur-infra-privileged/prd" from "asked
# soleur/prd_terraform", so the mis-binding ADR-168 exists to catch would ship green.
set -euo pipefail

# A direct invocation inherits the machine-global 4 GiB /tmp tmpfs; test-all.sh and
# run-registered-suites.sh default this to /var/tmp and a direct run does not.
export TMPDIR="${TMPDIR:-/var/tmp}"

SUITE="$(basename "$0")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_YML="$HERE/action.yml"

PASSES=0
FAILURES=()

pass() { PASSES=$((PASSES + 1)); printf '[ok] %s\n' "$1"; }
fail() { FAILURES+=("$1"); printf '[FAIL] %s\n' "$1"; }

# Canonical fixture-root guard, copied BYTE-FOR-BYTE from
# plugins/soleur/test/test-helpers.sh. `fixture-dir-operand-assert.test.sh` compares the
# inline definition against that source and reds on drift -- my first version was a
# two-arm paraphrase that checked only absoluteness, which passes the cases it thought of
# and misses `..`, `/proc`, `/` and the empty string. That is the whole reason the ratchet
# compares bytes rather than behaviour.
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

# ---- Instrument self-test -------------------------------------------------
#
# Drive BOTH helpers once each and refuse to continue unless BOTH counters moved.
# Without this, an edit that makes `fail()` take the pass branch reports a clean run
# having asserted nothing — and the anti-vacuity floor below would not notice, because
# it counts what these helpers increment.
pass "instrument self-test: pass() increments"
fail "instrument self-test: fail() records (EXPECTED — not a real failure)"
if [[ "$PASSES" -ne 1 || "${#FAILURES[@]}" -ne 1 ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: passes=%s failures=%s (expected 1/1)\n' \
    "$PASSES" "${#FAILURES[@]}" >&2
  exit 2
fi
SELFTEST_PASSES=1
SELFTEST_FAILURES=1
FAILURES=()

# ---- Extract the run: body ------------------------------------------------
WORK="$(mktemp -d "${TMPDIR%/}/infra-credentials-test.XXXXXXXX")"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

rc=0
python3 - "$ACTION_YML" "$WORK/loader.sh" <<'PY' || rc=$?
import sys, yaml
action = yaml.safe_load(open(sys.argv[1]))
steps = action["runs"]["steps"]
body = None
for s in steps:
    if s.get("id") == "load":
        body = s["run"]
        break
if body is None:
    print("EXTRACTION FOUND NO STEP WITH id: load", file=sys.stderr)
    sys.exit(3)
# Refuse a truncated extraction. A program that parses and answers is worse than an
# absent one: it produces a verdict about the SUT from an instrument that is broken.
for marker in ("PRIV_BUCKET=", "META_FILTER=", "git_data_root_state_pair_half_set",
               "privileged_source_missing", "MIN_EXPORTED="):
    if marker not in body:
        print(f"EXTRACTION LOST A DEFINING CONSTRUCT: {marker!r}", file=sys.stderr)
        sys.exit(3)
open(sys.argv[2], "w").write(body)
PY
if [[ "$rc" -ne 0 ]]; then
  printf 'CANNOT EXTRACT LOADER BODY (rc=%s) — every row below would be void.\n' "$rc" >&2
  exit 2
fi

# ---- The stub ------------------------------------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/doppler" <<'STUB'
#!/usr/bin/env bash
# Fail CLOSED on anything we were not told to expect. `exit 64` is EX_USAGE.
set -u
args="$*"
echo "doppler $args" >> "${STUB_CALLS:?}"

case "$args" in
  "secrets download --no-file --format json -p soleur-infra-privileged -c prd")
    if [[ "${STUB_DOWNLOAD_RC:-0}" != "0" ]]; then exit "${STUB_DOWNLOAD_RC}"; fi
    cat "${STUB_PAYLOAD:?}"
    exit 0
    ;;
esac

echo "STUB-MISS: doppler $args" >&2
exit 64
STUB
chmod +x "$WORK/bin/doppler"

# Resolve the real binaries to ABSOLUTE paths BEFORE mutating PATH, or the stub dir at
# the front makes anything invoked by name re-enter this shim.
REAL_JQ="$(command -v jq)"
REAL_OPENSSL="$(command -v openssl)"
[[ -x "$REAL_JQ" && -x "$REAL_OPENSSL" ]] || { echo "need jq and openssl" >&2; exit 2; }

# ---- Harness -------------------------------------------------------------
#
# Runs the extracted body under the RUNNER's shell, not ours.
run_loader() {
  local infra="$1" legacy="$2" migrated="$3" payload_json="$4" download_rc="${5:-0}"
  local case_dir; case_dir="$(mktemp -d "$WORK/case.XXXXXXXX")"
  assert_fixture_dir "$case_dir"
  printf '%s' "$payload_json" > "$case_dir/payload.json"
  : > "$case_dir/calls"
  : > "$case_dir/github_env"
  : > "$case_dir/github_output"

  set +e
  env -i \
    PATH="$WORK/bin:$(dirname "$REAL_JQ"):$(dirname "$REAL_OPENSSL"):/usr/bin:/bin" \
    HOME="$case_dir" \
    DP_INFRA="$infra" \
    DP_LEGACY="$legacy" \
    GIT_DATA_ROOT_STATE_MIGRATED="$migrated" \
    STUB_CALLS="$case_dir/calls" \
    STUB_PAYLOAD="$case_dir/payload.json" \
    STUB_DOWNLOAD_RC="$download_rc" \
    GITHUB_ENV="$case_dir/github_env" \
    GITHUB_OUTPUT="$case_dir/github_output" \
    bash --noprofile --norc -eo pipefail "$WORK/loader.sh" \
    > "$case_dir/stdout" 2> "$case_dir/stderr"
  LOADER_RC=$?
  set -e
  LOADER_DIR="$case_dir"
}

out_get() { grep -E "^$1=" "$LOADER_DIR/github_output" | tail -1 | cut -d= -f2- || true; }
env_has() { grep -qE "^$1<<" "$LOADER_DIR/github_env"; }
said()    { grep -qF -- "$1" "$LOADER_DIR/stdout"; }

# A realistic payload: the metadata keys Doppler always injects, a multi-line PEM, and
# the git-data state pair.
# The PEM fixture is SYNTHESIZED and split across concatenation. A contiguous
# `-----BEGIN RSA PRIVATE KEY-----` literal matches gitleaks' `private-key` rule and
# GitHub Push Protection even when the bytes are obviously fake, so the source holds no
# such literal while the runtime value keeps the multi-line shape the test needs. Same
# treatment as every other secret-shaped fixture in this repo.
PEM_B="-----BEGIN RSA PRIVATE"" KEY-----"
PEM_E="-----END RSA PRIVATE"" KEY-----"
PEM="${PEM_B}"$'\nQUJDREVG\nR0hJSktM\n'"${PEM_E}"
full_payload() {
  "$REAL_JQ" -n --arg pem "$PEM" '{
    DOPPLER_PROJECT: "soleur-infra-privileged",
    DOPPLER_CONFIG: "prd",
    DOPPLER_ENVIRONMENT: "prd",
    DOPPLER_TOKEN_TF: "dp.pt.FIXTURE-NOT-A-REAL-TOKEN",
    HCLOUD_TOKEN: "hcloud-fixture",
    CF_API_TOKEN_R2: "cf-fixture",
    GITHUB_INFRA_APP_ID: "999999",
    GITHUB_INFRA_APP_INSTALLATION_ID: "888888",
    GITHUB_INFRA_APP_PRIVATE_KEY: $pem,
    TF_STATE_AWS_ACCESS_KEY_ID: "rw-key",
    TF_STATE_AWS_SECRET_ACCESS_KEY: "rw-secret",
    GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID: "gd-key",
    GIT_DATA_ROOT_STATE_AWS_SECRET_ACCESS_KEY: "gd-secret"
  }'
}

# ======================================================================
# ROW 1 — legacy arm: no Tier-B token, legacy token present.
# ======================================================================
run_loader "" "dp.st.LEGACY-FIXTURE" "" "{}"
[[ "$LOADER_RC" -eq 0 ]] && pass "row1: legacy arm exits 0" || fail "row1: legacy arm rc=$LOADER_RC"
[[ "$(out_get source)" == "legacy" ]] && pass "row1: source=legacy" || fail "row1: source=$(out_get source)"
[[ "$(out_get git_data_root_state_bucket)" == "soleur-terraform-state" ]] \
  && pass "row1: legacy bucket" || fail "row1: bucket=$(out_get git_data_root_state_bucket)"
said "privileged_source_missing" && pass "row1: names the verdict" || fail "row1: no verdict word"
# The legacy arm must not call Doppler at all — it only decides.
[[ ! -s "$LOADER_DIR/calls" ]] && pass "row1: makes no Doppler call" || fail "row1: called Doppler"

# ======================================================================
# ROW 2 — neither token: fail CLOSED, and say why.
# ======================================================================
run_loader "" "" "" "{}"
[[ "$LOADER_RC" -ne 0 ]] && pass "row2: no credential source is a refusal" || fail "row2: exited 0"
said "no_credential_source" && pass "row2: names the verdict" || fail "row2: no verdict word"

# ======================================================================
# ROW 3 — Tier-B happy path.
# ======================================================================
run_loader "dp.st.TIERB-FIXTURE" "dp.st.LEGACY-FIXTURE" "" "$(full_payload)"
[[ "$LOADER_RC" -eq 0 ]] && pass "row3: tier_b arm exits 0" || fail "row3: rc=$LOADER_RC stderr=$(cat "$LOADER_DIR/stderr")"
[[ "$(out_get source)" == "tier_b" ]] && pass "row3: source=tier_b" || fail "row3: source=$(out_get source)"
env_has "HCLOUD_TOKEN"    && pass "row3: exports the plain name"  || fail "row3: no plain HCLOUD_TOKEN"
env_has "TF_VAR_hcloud_token" && pass "row3: exports the TF_VAR_ form" || fail "row3: no TF_VAR_hcloud_token"
# The PEM must survive intact: a `printf 'K=V\n'` export truncates at the first newline
# and the provider then reports an unparseable key.
grep -qF -- "$PEM_E" "$LOADER_DIR/github_env" \
  && pass "row3: multi-line PEM exported whole" || fail "row3: PEM truncated"
[[ "$(out_get git_data_root_state_bucket)" == "soleur-terraform-state-privileged" ]] \
  && pass "row3: privileged bucket when the pair is present" \
  || fail "row3: bucket=$(out_get git_data_root_state_bucket)"

# ======================================================================
# ROW 4 — THE METADATA FILTER. Doppler always injects DOPPLER_PROJECT /
# DOPPLER_CONFIG / DOPPLER_ENVIRONMENT. Exporting them would repoint every LATER
# `doppler run` in the job at the carrier project, so the job would read
# soleur-infra-privileged/prd and find none of the names it expects. A whole-job
# failure from a loader that reported success.
# ======================================================================
run_loader "dp.st.TIERB-FIXTURE" "" "" "$(full_payload)"
for k in DOPPLER_PROJECT DOPPLER_CONFIG DOPPLER_ENVIRONMENT; do
  if env_has "$k"; then fail "row4: leaked $k into GITHUB_ENV (would repoint every later doppler run)"
  else pass "row4: filtered $k"; fi
done
env_has "TF_VAR_doppler_token_tf" && pass "row4: a real DOPPLER_-prefixed SECRET is kept" \
  || fail "row4: filter was too greedy — DOPPLER_TOKEN_TF is a real secret, not metadata"

# ======================================================================
# ROW 5 — the mis-bound-token case. ADR-168: a service token errors loudly on a
# project/config mismatch. The loader must fail closed, not fall back to legacy.
# ======================================================================
run_loader "dp.st.TIERB-FIXTURE" "dp.st.LEGACY-FIXTURE" "" "{}" 1
[[ "$LOADER_RC" -ne 0 ]] && pass "row5: a failed privileged read is a refusal" || fail "row5: exited 0"
said "privileged_read_failed" && pass "row5: names the verdict" || fail "row5: no verdict word"
[[ "$(out_get source)" != "legacy" ]] && pass "row5: does NOT silently degrade to legacy" \
  || fail "row5: degraded to legacy — a Tier-B job would use Tier-A credentials"

# ======================================================================
# ROW 6 — the all-or-none state key pair.
# ======================================================================
HALF="$("$REAL_JQ" -n '{HCLOUD_TOKEN:"x", GIT_DATA_ROOT_STATE_AWS_ACCESS_KEY_ID:"only-the-id"}')"
run_loader "dp.st.TIERB-FIXTURE" "" "" "$HALF"
[[ "$LOADER_RC" -ne 0 ]] && pass "row6: half-set pair is a refusal" || fail "row6: exited 0"
said "git_data_root_state_pair_half_set" && pass "row6: names the verdict" || fail "row6: no verdict word"

# ======================================================================
# ROW 7 — the post-migration latch. With GIT_DATA_ROOT_STATE_MIGRATED=1 and no pair,
# the legacy bucket is STALE: a run that initialized against it would read and write a
# state object the operator is about to delete.
# ======================================================================
NOPAIR="$("$REAL_JQ" -n '{HCLOUD_TOKEN:"x"}')"
run_loader "dp.st.TIERB-FIXTURE" "" "1" "$NOPAIR"
[[ "$LOADER_RC" -ne 0 ]] && pass "row7: legacy bucket after migration is a refusal" || fail "row7: exited 0"
said "git_data_root_state_legacy_after_migration" && pass "row7: names the verdict" || fail "row7: no verdict word"
# Before the latch the SAME input is fine — this is the pair that makes row 7 a test of
# the latch rather than of the missing pair.
run_loader "dp.st.TIERB-FIXTURE" "" "" "$NOPAIR"
[[ "$LOADER_RC" -eq 0 ]] && pass "row7b: same input WITHOUT the latch is accepted" || fail "row7b: rc=$LOADER_RC"
[[ "$(out_get git_data_root_state_bucket)" == "soleur-terraform-state" ]] \
  && pass "row7b: falls back to the legacy bucket pre-migration" || fail "row7b: wrong bucket"

# ======================================================================
# ROW 8 — the anti-vacuity floor. An empty project exports nothing, and a Tier-B job
# that exported nothing falls through to its own `doppler run` and looks EXACTLY like a
# healthy Tier-B run.
# ======================================================================
run_loader "dp.st.TIERB-FIXTURE" "" "" "$("$REAL_JQ" -n '{DOPPLER_PROJECT:"p",DOPPLER_CONFIG:"c"}')"
[[ "$LOADER_RC" -ne 0 ]] && pass "row8: metadata-only payload is a refusal" || fail "row8: exited 0"
said "privileged_empty" && pass "row8: names the verdict" || fail "row8: no verdict word"

# ======================================================================
# ROW 8b — the R7 backend alias. The R2 backend reads AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY; after operator step O5b the prd_terraform pair under those names
# is READ-ONLY, so a Tier-B apply that used it could not write state. The read/write pair
# lives in Tier B as TF_STATE_AWS_*, and the loader aliases it onto the plain names so the
# 44 extract sites need only `${AWS_ACCESS_KEY_ID:-<legacy read>}`.
# ======================================================================
run_loader "dp.st.TIERB-FIXTURE" "" "" "$(full_payload)"
env_has "AWS_ACCESS_KEY_ID"     && pass "row8b: aliases the backend key id"     || fail "row8b: no AWS_ACCESS_KEY_ID"
env_has "AWS_SECRET_ACCESS_KEY" && pass "row8b: aliases the backend secret"     || fail "row8b: no AWS_SECRET_ACCESS_KEY"
# The alias must carry the TIER-B value, not the Tier-A one -- an alias pointing at the
# wrong pair is the R7 defect with the appearance of the fix.
grep -qE '^AWS_ACCESS_KEY_ID<<' "$LOADER_DIR/github_env" \
  && grep -qF -- "rw-key" "$LOADER_DIR/github_env" \
  && pass "row8b: the alias carries the Tier-B read/write value" \
  || fail "row8b: alias present but not the Tier-B value"

# ROW 8c — half-set backend pair is a refusal, same reason as the git-data pair.
HALFTF="$("$REAL_JQ" -n '{HCLOUD_TOKEN:"x", TF_STATE_AWS_ACCESS_KEY_ID:"only-the-id"}')"
run_loader "dp.st.TIERB-FIXTURE" "" "" "$HALFTF"
[[ "$LOADER_RC" -ne 0 ]] && pass "row8c: half-set backend pair is a refusal" || fail "row8c: exited 0"
said "tf_state_key_pair_half_set" && pass "row8c: names the verdict" || fail "row8c: no verdict word"

# ROW 8d — NO Tier-B state pair: the loader must NOT alias, so the extract steps' legacy
# fallback is what supplies the backend. Without this row, an alias that fired
# unconditionally (exporting an empty AWS_ACCESS_KEY_ID) would look identical to success
# and would SHADOW the legacy read at every one of the 44 sites.
run_loader "dp.st.TIERB-FIXTURE" "" "" "$("$REAL_JQ" -n '{HCLOUD_TOKEN:"x"}')"
if env_has "AWS_ACCESS_KEY_ID"; then
  fail "row8d: aliased AWS_ACCESS_KEY_ID with no Tier-B pair — an empty alias shadows the legacy fallback at every extract site"
else
  pass "row8d: no alias without a Tier-B pair (legacy fallback stays reachable)"
fi

# ======================================================================
# ROW 9 — the --preserve-env SENTINEL. This is the executable proof of the precedence
# property Guard 2 asserts statically: without the flag, a value planted in a
# Tier-A-writable config SHADOWS the loader's value, which is exactly the substitution
# attack `DOPPLER_TOKEN_WRITE` makes possible until operator step O11.
#
# Gated on a real Doppler CLI: this measures VENDOR behaviour, so a stub would only
# measure our belief about it.
# ======================================================================
if command -v doppler > /dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
  SENT_A="$(SOLEUR_SENTINEL=loader-value doppler run --preserve-env=SOLEUR_SENTINEL \
    -p soleur -c prd_terraform -- printf '%s' "${SOLEUR_SENTINEL:-}" 2>/dev/null || echo UNAVAILABLE)"
  if [[ "$SENT_A" == "loader-value" ]]; then
    pass "row9: --preserve-env keeps the environment value (vendor-measured)"
  elif [[ "$SENT_A" == "UNAVAILABLE" ]]; then
    printf '[skip] row9: doppler present but the sentinel run was not authorized\n'
  else
    fail "row9: --preserve-env did NOT keep the environment value (got %s) — Tier-B precedence is not real" "$SENT_A"
  fi
else
  printf '[skip] row9: no authorized Doppler CLI; the static Guard 2 census row still covers this\n'
fi

# ---- Verdict --------------------------------------------------------------
#
# Failures print FIRST, then the floor. The floor must enforce ITSELF -- a direct printf
# and its own `exit 1`, never a `FAILURES+=(...)` that the verdict block below reads.
#
# That was a real defect here, and guard-vacuity-floor.test.sh named it exactly: its
# mutant slices the `if` plus the CONTIGUOUS simple assignments above it, zeroes every
# counter, and runs THAT. A floor whose body only appends to an array exits 0 in that
# slice, because the verdict block that reads the array is not in it -- so the floor is
# "enforced THROUGH the machinery it guards" and a one-line edit disarming every assertion
# disarms the floor too. ADR-193.
printf '\n%s: %s passed, %s failed\n' "$SUITE" "$((PASSES - 1))" "${#FAILURES[@]}"
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  printf '  - %s\n' "${FAILURES[@]}"
fi

# BOTH operands are literals on the lines IMMEDIATELY above the `if`. The subtrahend was
# `SELFTEST_PASSES`, bound ~200 lines up at the instrument self-test -- and a name bound
# further up is UNBOUND in the mutant slice, so the mutant dies at `set -u` and the floor
# scores CONSTRUCTION FAILURE rather than FIRES. The literal is safe because the self-test
# already asserts `PASSES == 1` at that point and aborts otherwise.
SELFTEST_PASSES=1
MIN_ASSERTIONS=34
REAL=$((PASSES - SELFTEST_PASSES))
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s real assertions ran, floor is %s — rows were skipped, truncated, or the assertion machinery was neutered.\n' "$REAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[[ "${#FAILURES[@]}" -eq 0 ]] || exit 1
exit 0
