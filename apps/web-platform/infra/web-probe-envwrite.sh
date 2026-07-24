#!/usr/bin/env bash
# web-probe-envwrite.sh — fresh-boot env-file writer for the 3 web-host probes (#6459 Phase 2.2).
#
# CONTEXT: the private-NIC guard (#6438 §3), zot-consumer probe (#6438 §1) and git-data
# reachability probe (#6548) each read a per-host /etc/default/web-<probe> EnvironmentFile that
# carries EXPECTED_IP / endpoints / the per-host Doppler URL-var NAME + the read-scoped web_probes
# DOPPLER_TOKEN. On the pet web-1 those files are written by the terraform_data.*_install SSH
# remote-exec `printf`s (server.tf). A FRESH cattle host (web-2) never receives those SSH
# provisioners, so the env files came up ABSENT and the probe units failed to start — the #6459
# silent-boot gap. This baked script closes it: cloud-init invokes it once with the per-host values
# (token + expected IP + host key + endpoints) and it writes all 3 env files.
#
# PARITY: the KEY SET written here MUST equal the SSH remote-exec printf key set for the same dest
# (guarded byte-key-wise by fresh-boot-parity.test.sh §12). The SSH provisioners are RETAINED for
# web-1 running-host rotation until Phase 5; this ADDS fresh-boot coverage, it does not remove SSH.
#
# SECURITY: the read-scoped web_probes token adds ZERO marginal exposure — the host user_data
# already carries the strictly-stronger full-prd DOPPLER_TOKEN (server.tf:211 / webhook-deploy).
# umask 0137 closes the sub-ms TOCTOU between create-at-default-umask and chmod 600 (the file holds
# a live prd read token), mirroring the SSH remote-exec's own `( umask 0137 && printf … )` shape.
set -euo pipefail

# Fail LOUD on any unset required input — no silent Doppler/env fallback (fresh-boot readiness
# contract; 2026-04-03-doppler-not-installed-env-fallback-outage). A missing value here means the
# render/wiring is broken; a probe env file half-written from empty vars is worse than none.
: "${SOLEUR_WEB_PROBES_TOKEN:?web-probe-envwrite: SOLEUR_WEB_PROBES_TOKEN unset}"
: "${SOLEUR_EXPECTED_IP:?web-probe-envwrite: SOLEUR_EXPECTED_IP unset}"
: "${SOLEUR_BETTERSTACK_INGEST_URL:?web-probe-envwrite: SOLEUR_BETTERSTACK_INGEST_URL unset}"
: "${SOLEUR_HOST_KEY:?web-probe-envwrite: SOLEUR_HOST_KEY unset}"
: "${SOLEUR_ZOT_ENDPOINT:?web-probe-envwrite: SOLEUR_ZOT_ENDPOINT unset}"
: "${SOLEUR_ZOT_PROBE_REPO:?web-probe-envwrite: SOLEUR_ZOT_PROBE_REPO unset}"

# HOST_UPPER mirrors the SSH provisioner's `upper(replace(each.key, "-", "_"))` (server.tf) — so
# "web-1" → "WEB_1", "web-2" → "WEB_2". This names the per-host Better Stack heartbeat URL var
# (WEB_NIC_GUARD_URL_WEB_2, WEB_ZOT_CONSUMER_URL_WEB_2) that doppler run injects at unit start; the
# unit's ${!KEY} indirect expansion resolves it under the generic name the host-agnostic script reads.
HOST_UPPER="$(printf '%s' "$SOLEUR_HOST_KEY" | tr 'a-z-' 'A-Z_')"

# git-data uses ONE shared beat today (single-host; masking moot, C3) → the KEY is unsuffixed. The
# endpoint literal mirrors git-data.tf's SSH transport (10.0.1.20:22), matching the SSH remote-exec.
GIT_DATA_ENDPOINT="10.0.1.20:22"

# Each env file: umask 0137 subshell so it is NEVER created world/group-readable (it holds a live
# prd read token), then chmod 600 — byte-key-identical to the retained SSH remote-exec printf.
( umask 0137 && printf 'EXPECTED_IP=%s\nBETTERSTACK_INGEST_URL=%s\nWEB_NIC_GUARD_URL_KEY=%s\nDOPPLER_TOKEN=%s\nDOPPLER_ENABLE_VERSION_CHECK=false\n' "$SOLEUR_EXPECTED_IP" "$SOLEUR_BETTERSTACK_INGEST_URL" "WEB_NIC_GUARD_URL_${HOST_UPPER}" "$SOLEUR_WEB_PROBES_TOKEN" > /etc/default/web-private-nic-guard )
chmod 600 /etc/default/web-private-nic-guard

( umask 0137 && printf 'ZOT_ENDPOINT=%s\nZOT_PROBE_REPO=%s\nWEB_ZOT_CONSUMER_URL_KEY=%s\nDOPPLER_TOKEN=%s\nDOPPLER_ENABLE_VERSION_CHECK=false\n' "$SOLEUR_ZOT_ENDPOINT" "$SOLEUR_ZOT_PROBE_REPO" "WEB_ZOT_CONSUMER_URL_${HOST_UPPER}" "$SOLEUR_WEB_PROBES_TOKEN" > /etc/default/web-zot-consumer-probe )
chmod 600 /etc/default/web-zot-consumer-probe

( umask 0137 && printf 'GIT_DATA_ENDPOINT=%s\nGIT_DATA_HEARTBEAT_URL_KEY=%s\nDOPPLER_TOKEN=%s\nDOPPLER_ENABLE_VERSION_CHECK=false\n' "$GIT_DATA_ENDPOINT" 'GIT_DATA_HEARTBEAT_URL' "$SOLEUR_WEB_PROBES_TOKEN" > /etc/default/web-git-data-probe )
chmod 600 /etc/default/web-git-data-probe
