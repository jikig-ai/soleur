#!/usr/bin/env bash
set -euo pipefail
# A pipe into `grep -q` SIGPIPEs its producer on an early match and pipefail reads it as
# FALSE (#7024); _qgrep reads all of its input instead.
_qgrep() { grep "$@" >/dev/null; }

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
#      (#8651: the seed pull is zot-first now; the GHCR leg is attempted only after THIS login
#      succeeds, so login-before-pull is still the invariant for the GHCR leg.)
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
# #6122/#8651: the seed pull tries the resolved ref ($REF = the baked zot ref for a digest pin,
# else the GHCR $IMAGE_REF) in bounded `timeout 180 docker pull "$REF"` attempts.
pull_ln=$(grep -nE 'timeout 180 docker pull "\$REF"' "$CI" | head -1 | cut -d: -f1 || true)
if [ -n "$login_ln" ] && [ -n "$pull_ln" ] && [ "$login_ln" -lt "$pull_ln" ]; then
  ok "ghcr docker login (line $login_ln) precedes the seed pull (line $pull_ln)"
else
  no "ghcr login must precede the seed pull — login='$login_ln' pull='$pull_ln' (private image 401s anonymously)"
fi

# 1b. RETIRED by #8651 and now asserted ABSENT: the seed login must NOT read GHCR_READ_* from
# doppler. That read ran above the terminal `set -a` source, so it was tokenless since birth
# (#6985) — it could never have fetched anything — and the only value it could fetch is the
# revoked PAT (AP-016, GHCR_MINTER_DISABLED). The baked create-time value is the credential.
if grep -vE '^[[:space:]]*#' "$CI" | _qgrep -E 'doppler secrets get GHCR_READ_(USER|TOKEN)'; then
  no "seed login must not fetch GHCR_READ_{USER,TOKEN} via doppler (tokenless by construction, #6985/#8651)"
else
  ok "seed login reads no GHCR_READ_* from doppler (baked creds only, #8651)"
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

# 4. §1A RETIRED by #8651 and now asserted ABSENT. The re-fetch-on-baked-login-failure arm was
# dead twice over: tokenless (bare `.` source, #6985 — its reads always answered empty) and, even
# with a token, able to fetch only the revoked read PAT. Its successor property is stronger: the
# GHCR pull is attempted only after the baked login SUCCEEDS, so a dead credential fails at
# login, named in the fatal detail (`ghcr=[login=fail,pull=not-attempted]`), not as a 401 at pull.
if grep -vE '^[[:space:]]*#' "$CI" | _qgrep -E 'ghcr_login_ok_refetch|until R[UT]=.*doppler'; then
  no "the dead §1A Doppler re-fetch arm is back (tokenless by construction, #6985/#8651)"
else
  ok "no §1A Doppler re-fetch arm (retired by #8651)"
fi
# The GHCR PULL itself sits inside the `"$GL" = ok` block — a stray match elsewhere (the
# fallback emit's own line) must not satisfy this, so read the block's body.
gblk=$(awk '/^[[:space:]]*if \[ \$OK = 0 \] && \[ "\$GL" = ok \]; then$/ {f=1; next} f && /^[[:space:]]*fi$/ {exit} f' "$CI")
if printf '%s\n' "$gblk" | _qgrep -E 'timeout 180 docker pull "\$REF"' \
   && [ "$(grep -cE 'timeout 180 docker pull "\$REF"' "$CI")" = 2 ]; then
  ok "the GHCR pull sits inside the baked-GHCR-login gate (fail closed at login, #6500/#8651)"
else
  no "the GHCR seed pull must sit inside 'if [ \$OK = 0 ] && [ \"\$GL\" = ok ]; then … fi'"
fi

echo "=== cloud-init-ghcr-seed-login: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
