#!/usr/bin/env bash
# Test for the operator-digest provisioning bootstrap (#5085, plan §AC8).
#
# The script provisions the PRIVATE jikig-ai/operator-digest repo: it reads ANTHROPIC_API_KEY
# from Doppler and sets it as an Actions secret. The load-bearing safety properties are:
#   - the secret value is delivered to `gh secret set` via STDIN, never on argv (argv is visible
#     in `ps`, run logs, and shell history — an argv secret is a leak);
#   - an EMPTY Doppler value fails the run loudly, rather than silently setting an empty secret
#     (which would make every digest run fail the OIDC/synthesis step with a confusing error).
#
# It exercises the script's functions directly (the script guards `main` behind a BASH_SOURCE
# check, so sourcing it is side-effect-free) under mocked `gh` / `doppler` on PATH.
#
# Exit codes: 0 = all pass; 1 = an assertion failed; 2 = script missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION="${SCRIPT_DIR}/../skills/operator-digest/scripts/provision-operator-digest-repo.sh"

if [[ ! -r "$PROVISION" ]]; then
  echo "FAIL: provisioning script not found at ${PROVISION}" >&2
  echo "=== operator-digest-provision: 0 passed, 1 failed (script missing) ===" >&2
  exit 2
fi

pass=0
fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $1" >&2; }

tmproot="$(mktemp -d)"
trap 'rm -rf "$tmproot"' EXIT

# --- Structural: the secret reaches gh via stdin (a pipe), never via --body on argv ---
if grep -qE '\|[[:space:]]*gh secret set' "$PROVISION"; then ok; else
  bad "secret must be piped into 'gh secret set' (stdin), found no '| gh secret set'"; fi
if grep -E 'gh secret set' "$PROVISION" | grep -qE -- '--body'; then
  bad "'gh secret set' must NOT use --body (argv secret leak)"; else ok; fi

# --- Behavioral harness: a mock PATH that captures gh argv + stdin ---
make_mockbin() {  # <mockdir> <doppler-output>
  local dir="$1" doppler_out="$2"
  mkdir -p "$dir"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
# Capture argv and (for 'secret set') stdin, so the test can prove no argv leak.
printf '%s\n' "\$*" >> "${dir}/gh.argv"
if [[ "\$1" == "secret" && "\$2" == "set" ]]; then
  cat > "${dir}/gh.stdin"
fi
exit 0
EOF
  cat > "$dir/doppler" <<EOF
#!/usr/bin/env bash
printf '%s' '${doppler_out}'
exit 0
EOF
  chmod +x "$dir/gh" "$dir/doppler"
}

# --- Behavioral 1: EMPTY Doppler value → fetch_secret fails loud (non-zero) ---
empty_dir="${tmproot}/empty"
make_mockbin "$empty_dir" ""
rc=0
( PATH="${empty_dir}:$PATH"; source "$PROVISION"; fetch_secret ) >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then ok; else bad "fetch_secret must exit non-zero on an EMPTY Doppler value (got rc=$rc)"; fi

# --- Behavioral 2: non-empty Doppler value → fetch_secret succeeds (exit 0) ---
good_dir="${tmproot}/good"
make_mockbin "$good_dir" "sk-ant-FAKEVALUE"
rc=0
( PATH="${good_dir}:$PATH"; source "$PROVISION"; fetch_secret ) >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok; else bad "fetch_secret must exit 0 on a non-empty Doppler value (got rc=$rc)"; fi

# --- Behavioral 3: set_secret delivers the value via stdin, NOT argv ---
set_dir="${tmproot}/setsec"
make_mockbin "$set_dir" "irrelevant"
SENTINEL="STDIN-ONLY-SENTINEL-9f3a2b"
( PATH="${set_dir}:$PATH"; source "$PROVISION"; set_secret "$SENTINEL" ) >/dev/null 2>&1 || true
if [[ -f "${set_dir}/gh.stdin" ]] && grep -qF "$SENTINEL" "${set_dir}/gh.stdin"; then ok; else
  bad "set_secret must write the secret to gh's STDIN (sentinel not captured)"; fi
if [[ -f "${set_dir}/gh.argv" ]] && grep -qF "$SENTINEL" "${set_dir}/gh.argv"; then
  bad "secret value leaked onto gh argv (must be stdin-only)"; else ok; fi

echo "=== operator-digest-provision: ${pass} passed, ${fail} failed ===" >&2
[[ "$fail" == 0 ]]
