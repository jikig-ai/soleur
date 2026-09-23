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
# Only the PASSES side is read (by the floor). `FAILURES` is reset wholesale on the next
# line, so a failures counterpart would be a symmetry artifact implying a subtraction that
# does not exist.
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
  # The legacy arm's Tier-A reads. Keyed PER NAME so a test can make the read-only token
  # present or absent INDEPENDENTLY of the read/write one -- a stub answering the same for
  # both could not tell "prefers READONLY" from "reads whatever it is given".
  #
  # AND THE STUB AUTHENTICATES. The real `doppler` rejects a read with no DOPPLER_TOKEN,
  # and the step's `env:` block does not bind one -- so the legacy read is only reachable
  # because the arm prefixes `DOPPLER_TOKEN="$DP_LEGACY"` inline. A stub that answers
  # regardless of the token cannot see that prefix being dropped, and the first version of
  # this arm HAD dropped it: every read failed, `|| legacy_hcloud=""` turned the failure
  # into a value, and rows 1b/1c would have gone green over an arm that exported nothing.
  # The refusal text is shaped like Doppler's own so the arm's auth-vs-absence grep is
  # exercised against something it would actually meet.
  "secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c prd_terraform"|\
  "secrets get HCLOUD_TOKEN --plain -p soleur -c prd_terraform")
    if [[ "${DOPPLER_TOKEN:-}" != "${STUB_EXPECT_LEGACY_TOKEN:-dp.st.LEGACY-FIXTURE}" ]]; then
      echo "Doppler Error: Invalid Auth token (unauthorized)" >&2
      exit 1
    fi
    case "$args" in
      *HCLOUD_TOKEN_READONLY*) v="${STUB_HCLOUD_RO:-}" ;;
      *)                       v="${STUB_HCLOUD_RW:-}" ;;
    esac
    [[ -n "$v" ]] || exit 1
    printf '%s' "$v"; exit 0
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
    STUB_HCLOUD_RO="${STUB_HCLOUD_RO:-}" \
    STUB_HCLOUD_RW="${STUB_HCLOUD_RW:-}" \
    STUB_EXPECT_LEGACY_TOKEN="${STUB_EXPECT_LEGACY_TOKEN:-dp.st.LEGACY-FIXTURE}" \
    GITHUB_ENV="$case_dir/github_env" \
    GITHUB_OUTPUT="$case_dir/github_output" \
    bash --noprofile --norc -eo pipefail "$WORK/loader.sh" \
    > "$case_dir/stdout" 2> "$case_dir/stderr"
  LOADER_RC=$?
  set -e
  LOADER_DIR="$case_dir"
}

out_get() { grep -E "^$1=" "$LOADER_DIR/github_output" | tail -1 | cut -d= -f2- || true; }

# The KEYS a $GITHUB_ENV file actually defines, parsed the way Actions parses it: a
# `NAME<<DELIM` line opens a body that is DATA until the delimiter line, and a `NAME=` line
# outside a body is a key. A bare grep cannot tell the two apart, so it would report a
# contained value as an injection -- failing in the opposite direction from the defect and
# reading just as convincingly.
env_keys() {
  awk '
    pending != "" { if ($0 == pending) pending = ""; next }
    /^[A-Za-z_][A-Za-z0-9_]*<</ { k = $0; sub(/<<.*/, "", k); print k
                                  d = $0; sub(/^[^<]*<</, "", d); pending = d; next }
    /^[A-Za-z_][A-Za-z0-9_]*=/  { k = $0; sub(/=.*/, "", k); print k }
  ' "$LOADER_DIR/github_env"
}
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
    # The FOURTH metadata name. It has no fixture in the original row4 loop, and it is the
    # worst member to lose: exporting DOPPLER_TOKEN into $GITHUB_ENV repoints every later
    # `doppler run --preserve-env` in the job to authenticate as the TIER-B PRIVILEGED
    # token -- strictly worse than the DOPPLER_PROJECT leak the row was written for.
    # Dropping it from META_FILTER was a one-word edit that stayed green.
    DOPPLER_TOKEN: "dp.st.CARRIER-METADATA-NOT-A-SECRET",
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
# The legacy arm may read TIER A (that is its job — see row 1b), but it must never touch
# the PRIVILEGED project: a job with no Tier-B token has no business reaching for one, and
# a read there would mean the arm selection is not actually gating the privileged access.
grep -q 'secrets download' "$LOADER_DIR/calls" \
  && fail "row1: legacy arm read the privileged project" \
  || pass "row1: legacy arm never reads soleur-infra-privileged"

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
for k in DOPPLER_PROJECT DOPPLER_CONFIG DOPPLER_ENVIRONMENT DOPPLER_TOKEN; do
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
# SCOPED to the alias block. A file-wide `grep -F rw-key` is satisfied by the generic
# export loop's own TF_STATE_AWS_ACCESS_KEY_ID / TF_VAR_tf_state_aws_access_key_id lines,
# which carry that value three times before the alias is reached -- so the assertion held
# with the alias pointing at a literal, at the SECRET in the id slot, or at nothing of the
# sort. The heredoc body is the line immediately after the `KEY<<delim` header.
_alias_val() { awk -v k="$1" '$0 ~ "^"k"<<" {getline; print; exit}' "$LOADER_DIR/github_env"; }
[[ "$(_alias_val AWS_ACCESS_KEY_ID)" == "rw-key" ]] \
  && pass "row8b: the alias carries the Tier-B read/write KEY ID" \
  || fail "row8b: AWS_ACCESS_KEY_ID aliases $(_alias_val AWS_ACCESS_KEY_ID), want the Tier-B rw-key"
[[ "$(_alias_val AWS_SECRET_ACCESS_KEY)" == "rw-secret" ]] \
  && pass "row8b: the alias carries the Tier-B read/write SECRET" \
  || fail "row8b: AWS_SECRET_ACCESS_KEY aliases $(_alias_val AWS_SECRET_ACCESS_KEY), want the Tier-B rw-secret"
# ...and the two are not the SAME value. An alias that put the secret in the id slot
# satisfied every check above it, and is exactly the R7 defect wearing the fix's clothes.
[[ "$(_alias_val AWS_ACCESS_KEY_ID)" != "$(_alias_val AWS_SECRET_ACCESS_KEY)" ]] \
  && pass "row8b: the id and secret slots carry DIFFERENT values" \
  || fail "row8b: id and secret slots carry the same value"

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
# ROW 1b — THE LEGACY ARM MUST SUPPLY HCLOUD_TOKEN, not merely decline.
#
# Several Tier-B steps read `$HCLOUD_TOKEN` from the JOB environment rather than from
# inside a `doppler run` wrapper (the stock-preflight gates, the drift orphan sweep, the
# rung-2 hard reset, the root-key fingerprint attestation). Their own inline reads were
# removed because census row G1g forbids reading a Tier-B name from `prd_terraform`
# outside this action — so if the legacy arm exports nothing, every one of them aborts
# between merge and operator step O3. That is the outage their comments warn about, and
# it would falsify this PR's merge-safety claim.
# ======================================================================
STUB_HCLOUD_RO="ro-token" STUB_HCLOUD_RW="rw-token" run_loader "" "dp.st.LEGACY-FIXTURE" "" "{}"
[[ "$LOADER_RC" -eq 0 ]] && pass "row1b: legacy arm still exits 0" || fail "row1b: rc=$LOADER_RC"
if env_has "HCLOUD_TOKEN"; then
  pass "row1b: legacy arm exports HCLOUD_TOKEN"
else
  fail "row1b: legacy arm exported NO HCLOUD_TOKEN — every out-of-wrapper consumer aborts before O3"
fi
grep -qF -- "ro-token" "$LOADER_DIR/github_env" \
  && pass "row1b: prefers the READ-ONLY token when present" \
  || fail "row1b: exported value is not the read-only token"

# ROW 1c — the before-state fallback. Until operator step O5 mints HCLOUD_TOKEN_READONLY
# the read-only name does not exist, and the read/write token must still be supplied or
# the same outage occurs for the whole merge->O5 window.
STUB_HCLOUD_RO="" STUB_HCLOUD_RW="rw-token" run_loader "" "dp.st.LEGACY-FIXTURE" "" "{}"
grep -qF -- "rw-token" "$LOADER_DIR/github_env" \
  && pass "row1c: falls back to the read/write token before O5" \
  || fail "row1c: no fallback — merge->O5 window has no Hetzner token"

# ROW 1d — neither present: a WARNING, not a hard failure. A Tier-A job that never touches
# Hetzner is a legitimate caller, and every consumer already fail-closes loudly on an empty
# token while naming its own gate. Making this fatal would break those callers.
STUB_HCLOUD_RO="" STUB_HCLOUD_RW="" run_loader "" "dp.st.LEGACY-FIXTURE" "" "{}"
[[ "$LOADER_RC" -eq 0 ]] && pass "row1d: no Hetzner token is not fatal for a non-Hetzner caller" || fail "row1d: rc=$LOADER_RC"
said "hcloud_token=absent" && pass "row1d: names the condition" || fail "row1d: silent"
# ...and names it as an ABSENCE, never as an auth failure. The two send an operator to
# opposite places: "absent" is the expected state after O10 and needs no action, while a
# rejected token means the DOPPLER_TOKEN repo secret is broken. Conflating them is what
# sends someone to Doppler to add a key that is already there.
said "legacy_token_unauthorized" \
  && fail "row1d: reported an AUTH failure for an authenticated read with no key present" \
  || pass "row1d: does not misreport an absent key as an auth failure"
if env_has "HCLOUD_TOKEN"; then
  fail "row1d: exported an EMPTY HCLOUD_TOKEN — shadows nothing and hides the cause"
else
  pass "row1d: exports no empty HCLOUD_TOKEN"
fi

# ROW 1g — THE READ IS AUTHENTICATED, and an auth failure is reported AS one.
#
# This row exists because the defect it kills shipped: the arm's `doppler secrets get` had
# no `DOPPLER_TOKEN=` prefix while the Tier-B arm below it did, the step's `env:` binds no
# DOPPLER_TOKEN, and `2>/dev/null || legacy_hcloud=""` converted the resulting auth failure
# into an empty string. The arm then took its "no token available" branch and warned about
# a missing SECRET. Every symptom of the fix working was present; nothing was exported.
#
# Driving a WRONG token is the only way to separate the two: with the prefix present the
# arm meets Doppler's rejection and must say so; with the prefix deleted the read inherits
# whatever DOPPLER_TOKEN the job has (in the real action: none) and the distinction is
# unreachable.
STUB_EXPECT_LEGACY_TOKEN="dp.st.SOME-OTHER-TOKEN" STUB_HCLOUD_RO="ro-token" STUB_HCLOUD_RW="rw-token" \
  run_loader "" "dp.st.LEGACY-FIXTURE" "" "{}"
said "legacy_token_unauthorized" \
  && pass "row1g: a rejected Tier-A token is reported as an AUTH failure" \
  || fail "row1g: Doppler rejected the token and the arm did not say so — a broken credential reads as a missing secret"
if env_has "HCLOUD_TOKEN"; then
  fail "row1g: exported an HCLOUD_TOKEN from a read that was never authorized"
else
  pass "row1g: exports nothing when the read was refused"
fi
# NON-VACUITY CONTROL for 1e: the SAME fixture with the RIGHT token must export the value.
# Without this, an arm that never exports anything at all would pass both 1g assertions.
STUB_HCLOUD_RO="ro-token" STUB_HCLOUD_RW="rw-token" run_loader "" "dp.st.LEGACY-FIXTURE" "" "{}"
grep -qF -- "ro-token" "$LOADER_DIR/github_env" \
  && pass "row1g-control: the same fixture with the correct token DOES export" \
  || fail "row1g-control: the authenticated read exported nothing — 1g proved nothing"

# ROW 1f — $GITHUB_ENV INJECTION. The legacy value comes from `prd_terraform`, which the
# branch-nameable `DOPPLER_TOKEN_WRITE` repo secret can write until operator step O11. With
# a `K=V` export a value carrying a newline writes a SECOND line into $GITHUB_ENV, and
# Actions honours `BASH_ENV` / `LD_PRELOAD` in every later `run:` step — arbitrary code
# execution in a main-only job, from a branch, through the substitution path this action
# exists to close. The heredoc-delimiter form contains it.
STUB_HCLOUD_RO="$(printf 'tok\nBASH_ENV=/tmp/pwn')" STUB_HCLOUD_RW="" \
  run_loader "" "dp.st.LEGACY-FIXTURE" "" "{}"
if env_keys | grep -qx 'BASH_ENV'; then
  fail "row1f: a newline in the Tier-A value DEFINED a second GITHUB_ENV key (BASH_ENV) — branch-to-main code execution"
else
  pass "row1f: a newline in the Tier-A value defines no second GITHUB_ENV key"
fi
# Non-vacuity: the parser must be able to SEE a key, or the assertion above passes because
# it found nothing at all rather than because nothing was injected.
env_keys | grep -qx 'HCLOUD_TOKEN' \
  && pass "row1f: the env parser resolves the real key (the check is not vacuous)" \
  || fail "row1f: env parser found no keys — the injection assertion above proved nothing"
env_has "HCLOUD_TOKEN" && pass "row1f: the value is still exported (contained, not dropped)" \
  || fail "row1f: containment dropped the value"

# ROW 1e — the Tier-B arm must NOT make these Tier-A reads. In tier_b mode the value comes
# from the privileged project; reading prd_terraform there would re-introduce exactly the
# dependency this change removes, and the stub would record the call.
run_loader "dp.st.TIERB-FIXTURE" "dp.st.LEGACY-FIXTURE" "" "$(full_payload)"
grep -q 'secrets get HCLOUD_TOKEN' "$LOADER_DIR/calls" \
  && fail "row1e: tier_b arm read HCLOUD_TOKEN from prd_terraform" \
  || pass "row1e: tier_b arm makes no prd_terraform Hetzner read"

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
  # The expansion MUST happen in the INNER process. Written as
  # `-- printf '%s' "${SOLEUR_SENTINEL:-}"` the OUTER shell expands it first — where the
  # variable is unset — so `printf` receives an empty literal and SENT_A is "" regardless
  # of what --preserve-env does. That is not a weak assertion, it is an unsatisfiable one:
  # the row would take the `else` branch and report the precedence property BROKEN on every
  # authorized run. `sh -c` defers the expansion to the process `doppler run` execs.
  SENT_A="$(SOLEUR_SENTINEL=loader-value doppler run --preserve-env=SOLEUR_SENTINEL \
    -p soleur -c prd_terraform -- sh -c 'printf "%s" "${SOLEUR_SENTINEL:-}"' 2>/dev/null || echo UNAVAILABLE)"
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
# ---- LATE dispatch re-validation (the launder defence) --------------------
#
# The instrument self-test at the top is a POINT-IN-TIME sample: it proves the helpers
# worked once, before any row, and never looks again. One line inserted after it --
#
#     fail() { PASSES=$((PASSES + 1)); printf '[ok-LAUNDERED] %s\n' "$1"; }
#
# -- routes every subsequent failure into the PASS counter. The failures vanish, the
# floor below still reconciles because the inflation exactly replaces them, and the suite
# prints "N passed, 0 failed" over a SUT with its decision logic deleted. Measured: the
# whole META_FILTER removed plus that one line = green.
#
# So re-drive both helpers HERE, after every row, and require both counters to move. A
# laundered fail() increments PASSES instead of FAILURES and is caught by the second
# clause. Reported with printf + exit, never through the helpers under test.
_LATE_P="$PASSES"; _LATE_F="${#FAILURES[@]}"
pass "late dispatch re-validation: pass() still increments (EXPECTED)"
fail "late dispatch re-validation: fail() still records (EXPECTED — not a real failure)"
if [[ "$PASSES" -ne "$((_LATE_P + 1))" || "${#FAILURES[@]}" -ne "$((_LATE_F + 1))" ]]; then
  printf 'LATE DISPATCH RE-VALIDATION FAILED: pass() moved %s->%s (want +1), fail() moved %s->%s (want +1). The assertion machinery was neutered or laundered AFTER the opening self-test.\n' \
    "$_LATE_P" "$PASSES" "$_LATE_F" "${#FAILURES[@]}" >&2
  exit 2
fi
# Undo the two synthetic verdicts so the floor and the summary below count real rows only.
PASSES=$((PASSES - 1))
unset 'FAILURES[-1]'

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
MIN_ASSERTIONS=52
REAL=$((PASSES - SELFTEST_PASSES))
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY FLOOR: only %s real assertions ran, floor is %s — rows were skipped, truncated, or the assertion machinery was neutered.\n' "$REAL" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[[ "${#FAILURES[@]}" -eq 0 ]] || exit 1
exit 0
