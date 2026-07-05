#!/usr/bin/env bash
set -euo pipefail

# Regression guard for the private-GHCR seed-pull fix.
#
# BUG (recurred once via #6005/#6011): the seed image became a PRIVATE GHCR package,
# but cloud-init.yml's early host-script seed-pull (`docker pull "$IMAGE_REF"`) ran
# ANONYMOUSLY — soleur-host-bootstrap.sh's ghcr_login runs LATER (post-extract). So
# every fresh host boot 401'd at stage=pull, cloud-init aborted, :9000 never bound,
# and web-2-recreate could never produce a working warm standby. Worse, the failure
# was invisible: the fatal Sentry emit sourced its DSN from `doppler secrets get`, so
# when doppler/pull was the broken stage the error report died silently too.
#
# Asserts, in cloud-init.yml:
#   1. a `docker login ghcr.io` (GHCR_READ credential) precedes the seed `docker pull`.
#   2. the seed-block fatal emit (on_err) prefers the BAKED ${sentry_dsn} so it fires
#      even when doppler is the broken stage.
#   3. server.tf passes sentry_dsn into the cloud-init templatefile AND variables.tf
#      declares it (a templatefile var referenced-but-not-passed fails the apply).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$DIR/cloud-init.yml"
SRV="$DIR/server.tf"
VARS="$DIR/variables.tf"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

# 1. login-before-seed-pull ordering.
# shellcheck disable=SC2016  # intentional: grep for the LITERAL $GHCR_USER/$IMAGE_REF in the YAML.
login_ln=$(grep -nE 'docker login ghcr\.io -u "\$GHCR_USER"' "$CI" | head -1 | cut -d: -f1 || true)
# shellcheck disable=SC2016
pull_ln=$(grep -nE 'until docker pull "\$IMAGE_REF"' "$CI" | head -1 | cut -d: -f1 || true)
if [ -n "$login_ln" ] && [ -n "$pull_ln" ] && [ "$login_ln" -lt "$pull_ln" ]; then
  ok "ghcr docker login (line $login_ln) precedes the seed pull (line $pull_ln)"
else
  no "ghcr login must precede the seed pull — login='$login_ln' pull='$pull_ln' (private image 401s anonymously)"
fi

# 1b. the login fetches the GHCR_READ credential (not a bare/anonymous attempt).
if grep -qE 'doppler secrets get GHCR_READ_USER' "$CI" && grep -qE 'doppler secrets get GHCR_READ_TOKEN' "$CI"; then
  ok "seed login fetches GHCR_READ_{USER,TOKEN} via doppler"
else
  no "seed login must fetch GHCR_READ_{USER,TOKEN} via doppler"
fi

# 2. the fatal emit prefers the baked DSN.
if grep -qE "DSN='\\\$\{sentry_dsn\}'" "$CI"; then
  ok "on_err fatal emit prefers baked \${sentry_dsn} (fires without doppler)"
else
  no "on_err must prefer baked \${sentry_dsn} so the failure signal survives a broken doppler stage"
fi

# 3. templatefile var wired end-to-end (referenced ⟹ must be passed ⟹ must be declared).
if grep -qE '\$\{sentry_dsn\}' "$CI"; then ok "cloud-init.yml references \${sentry_dsn}"; else no "cloud-init.yml must reference \${sentry_dsn}"; fi
if grep -qE '^\s*sentry_dsn\s*=\s*var\.sentry_dsn' "$SRV"; then ok "server.tf passes sentry_dsn to the templatefile"; else no "server.tf must pass sentry_dsn = var.sentry_dsn (else templatefile() fails)"; fi
if grep -qE 'variable "sentry_dsn"' "$VARS"; then ok "variables.tf declares variable \"sentry_dsn\""; else no "variables.tf must declare variable \"sentry_dsn\""; fi

echo "=== cloud-init-ghcr-seed-login: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
