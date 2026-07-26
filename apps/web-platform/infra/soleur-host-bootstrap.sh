#!/bin/sh
# Fresh-host bootstrap installer (#5921).
#
# WHY THIS IS A BAKED SCRIPT, NOT INLINE CLOUD-INIT: the 22 host scripts + hooks.json were
# removed from cloud-init.yml write_files: because as base64 blobs they blew Hetzner's
# 32,768-byte user_data cap. Baking them fixed most of it, but the install/verify/assert
# ceremony was ~90 lines of inline runcmd that ALSO counts toward user_data. Moving that
# ceremony here (baked into ${image_name}) costs zero user_data bytes.
#
# TRUST MODEL: cloud-init.yml's minimal launcher `docker cp`s /opt/soleur/host-scripts/. to
# a temp dir, recomputes the combined content-hash, compares it to the Terraform-computed
# host_scripts_content_hash, and ONLY THEN runs this script. So this script (itself part of
# the hashed set) executes only when every baked asset is proven intact — a stale, mis-built
# or tampered image aborts the boot before this runs.
#
# FAIL-CLOSED: runcmd is NOT under a top-level `set -e`, so the real gate is the
# /run/soleur-hostscripts.ok sentinel written LAST here — the terminal `docker run` block
# refuses to start (poweroff -f) if it is absent. On ANY failure the EXIT trap emits a
# discriminating Sentry event (SSH-free root-cause signal) then exits non-zero so no
# sentinel is written and the host stays visibly absent to the Better Stack uptime check.
#
# Args:  $1 = extracted seed dir (contains the baked host-scripts).
# Env:   WEBHOOK_DEPLOY_SECRET (injected into the baked hooks.json.tmpl at boot).
set -e

SEED="$1"
STAGE=install
FAILED_FILE=""
HOST_ID=$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) | tr -d '"' )

# Best-effort SSH-free discriminating signal (SECONDARY; the PRIMARY detector is the
# provision-armed Better Stack absence check).
#
# _sentry_emit is the SINGLE fail-open DSN-resolve + POST boundary (#6090): it prefers
# the BAKED ${SOLEUR_SENTRY_DSN} (passed by cloud-init's bootstrap invocation) over a
# `doppler secrets get` fetch, so a fatal emit fires even when doppler is itself the
# broken boot stage — the exact blind spot #6076 closed for the seed block, extended
# here to the bootstrap block. Everything runs inside a ( set +e … ) || true subshell so
# a curl/DNS hiccup can never trip `set -e` and brick the boot. The caller assembles the
# complete Sentry JSON body (message/level/tags) and passes it as $1.
_sentry_emit() {
  ( set +e
    . /etc/default/webhook-deploy 2>/dev/null || true
    DSN="${SOLEUR_SENTRY_DSN:-}"
    [ -n "$DSN" ] || DSN=$(timeout 15 doppler secrets get SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || timeout 15 doppler secrets get NEXT_PUBLIC_SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || true)
    # Transport stays BYTE-IDENTICAL to cron-egress-enforce-probe.sh (its
    # cron-egress-enforce-probe.test.sh "Sentry TRANSPORT parity" drift guard asserts these
    # exact lines + indentation appear in both) — a DSN/endpoint migration must move together.
    if [ -n "$DSN" ]; then
      KEY=$(printf '%s' "$DSN" | sed -E 's#https://([^@]+)@.*#\1#')
      SHOST=$(printf '%s' "$DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
      PROJ=$(printf '%s' "$DSN" | sed -E 's#.*/([0-9]+)$#\1#')
      curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/" \
        -H 'Content-Type: application/json' \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY" \
        -d "$1" >/dev/null 2>&1 || true
    fi ) || true
}

emit_fail() {
  trap - EXIT
  _sentry_emit "$(printf '{"message":"soleur-host-bootstrap failed","level":"fatal","tags":{"stage":"%s","failed_file":"%s","host_id":"%s"}}' "$STAGE" "$FAILED_FILE" "$HOST_ID")"
  exit 1
}
trap emit_fail EXIT

# Per-file install with AUTHORITATIVE modes (scripts 0755, units/allowlists 0644, all
# root:root). NEVER a preserve-mode copy — a firewall SCRIPT at 0644 is non-executable →
# open container egress (#5046).
for f in ci-deploy.sh ci-deploy-wrapper.sh cat-deploy-state.sh canary-bundle-claim-check.sh \
         disk-monitor.sh resource-monitor.sh container-restart-monitor.sh \
         infra-config-apply.sh cat-infra-config-state.sh \
         cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
         cron-egress-postapply-assert.sh cron-egress-enforce-probe.sh \
         orphan-reaper.sh \
         web-private-nic-guard.sh web-zot-consumer-probe.sh web-git-data-probe.sh \
         web-probe-envwrite.sh; do
  FAILED_FILE="$f"; install -D -m 0755 -o root -g root "$SEED/$f" "/usr/local/bin/$f"
done
# The pinned root-run escalation helper installs WITHOUT the .sh suffix (its sudoers grant +
# ci-deploy.sh reference /usr/local/bin/infra-config-install).
FAILED_FILE=infra-config-install
install -D -m 0755 -o root -g root "$SEED/infra-config-install.sh" /usr/local/bin/infra-config-install
for f in container-restart-monitor.service container-restart-monitor.timer \
         cron-egress-firewall.service cron-egress-resolve.service cron-egress-resolve.timer \
         cron-egress-alarm@.service \
         orphan-reaper.service orphan-reaper.timer bwrap-userns-sysctl.service \
         web-private-nic-guard.service web-private-nic-guard.timer \
         web-zot-consumer-probe.service web-zot-consumer-probe.timer \
         web-git-data-probe.service web-git-data-probe.timer; do
  FAILED_FILE="$f"; install -D -m 0644 -o root -g root "$SEED/$f" "/etc/systemd/system/$f"
done
for f in cron-egress-allowlist.txt cron-egress-allowlist-cidr.txt; do
  FAILED_FILE="$f"; install -D -m 0644 -o root -g root "$SEED/$f" "/etc/soleur/$f"
done
# Pinned cosign trusted root (#6005) — public trust material mounted :ro into the
# ephemeral cosign verifier by ci-deploy.sh (ADR-087). 0644 root:root; dockerd (root)
# reads the mount source, so deploy-user readability is not required.
FAILED_FILE=cosign-trusted-root.json
install -D -m 0644 -o root -g root "$SEED/cosign-trusted-root.json" /etc/soleur/cosign-trusted-root.json
# journald persistent+bounded drop-in (baked #5921). Installed here (post-extraction) and
# applied below — before the terminal app container (--log-driver journald) starts. Was
# previously an inline write_files: base64 blob (2.4 KB), the single biggest remaining
# user_data expansion; baking it keeps the rendered user_data comfortably under the cap. The
# running-host copy is still delivered byte-identically by terraform_data.journald_persistent.
FAILED_FILE=journald-soleur.conf
install -D -m 0644 -o root -g root "$SEED/journald-soleur.conf" /etc/systemd/journald.conf.d/00-soleur.conf

# Container-sandbox security-control profiles (#6629). Their only prior delivery was the
# SSH provisioners (terraform_data.docker_seccomp_config / apparmor_bwrap_profile), which
# reach RUNNING hosts only — a FRESH host came up with neither, so the terminal docker run
# ran the tenant sandbox unenforced (seccomp_profile_host_present=false). Installed here
# (post-extraction, hash-verified) and apparmor-loaded BEFORE the terminal docker run so its
# --security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json + apparmor=soleur-bwrap
# succeed on a cold host. FAIL-CLOSED: apparmor_parser -r runs under the top-level set -e +
# emit_fail trap, so a load failure aborts the boot with a named stage (no sentinel → the
# terminal docker run block poweroffs). 0644 root:root; dockerd (root) reads both.
STAGE=sandbox_profiles
FAILED_FILE=seccomp-bwrap.json
install -D -m 0644 -o root -g root "$SEED/seccomp-bwrap.json" /etc/docker/seccomp-profiles/soleur-bwrap.json
FAILED_FILE=apparmor-soleur-bwrap.profile
install -D -m 0644 -o root -g root "$SEED/apparmor-soleur-bwrap.profile" /etc/apparmor.d/soleur-bwrap
FAILED_FILE=apparmor-load
apparmor_parser -r /etc/apparmor.d/soleur-bwrap
# (#6459 Phase 2.2) bwrap unprivileged-userns sysctl drop-in — the SSH-only half of
# docker_seccomp_config, now on the fresh-boot path. Install the belt-and-braces drop-in here; the
# boot-persistent bwrap-userns-sysctl.service (baked unit, enabled `--now` by cloud-init BEFORE the
# terminal docker run) is the load-bearing re-assert. Without it, bwrap can't mount /proc and every
# Bash tool call in a cron spawn fails (#1557 / #4927 / #4928).
FAILED_FILE=99-bwrap-userns.conf
install -D -m 0644 -o root -g root "$SEED/99-bwrap-userns.conf" /etc/sysctl.d/99-bwrap-userns.conf

# hooks.json: the baked hooks.json.tmpl carries the Terraform token literally; inject the
# small webhook_deploy_secret at boot (jsonencode-equivalent via python3 json.dumps —
# python3 is a cloud-init dependency, always present), validate the JSON, then mirror the SSH
# bridge's post-write checks (server.tf infra_config_handler_bootstrap).
STAGE=hooks
FAILED_FILE=hooks.json
install -D -m 0640 -o root -g deploy /dev/null /etc/webhook/hooks.json
# NOTE: json.dumps defaults to ensure_ascii=True (\uXXXX-escapes non-ASCII), whereas the
# running-host SSH path renders hooks.json via Terraform jsonencode() (raw UTF-8). For the
# generated ASCII webhook_deploy_secret these produce byte-identical output; a non-ASCII
# secret would diverge cosmetically (HMAC is unaffected — only the decoded secret matters).
python3 - "$SEED/hooks.json.tmpl" /etc/webhook/hooks.json <<'PYEOF'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
secret = os.environ["WEBHOOK_DEPLOY_SECRET"]
data = open(src).read().replace("${jsonencode(webhook_deploy_secret)}", json.dumps(secret))
json.loads(data)  # abort (non-zero) if the injected result is not valid JSON
open(dst, "w").write(data)
PYEOF
chown root:deploy /etc/webhook/hooks.json
chmod 0640 /etc/webhook/hooks.json
grep -q infra-config-status /etc/webhook/hooks.json
grep -q cat_infra_config_state_sh_b64 /etc/webhook/hooks.json

# Per-file assertions: scripts executable, units + allowlists present, and the sudo-NOPASSWD
# escalation helper is exactly mode 755 (a group/other-writable root target would be a
# privilege-escalation surface).
STAGE=assert
for f in ci-deploy.sh ci-deploy-wrapper.sh cat-deploy-state.sh canary-bundle-claim-check.sh \
         disk-monitor.sh resource-monitor.sh container-restart-monitor.sh \
         infra-config-apply.sh cat-infra-config-state.sh \
         cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
         cron-egress-postapply-assert.sh cron-egress-enforce-probe.sh; do
  FAILED_FILE="$f"; test -x "/usr/local/bin/$f"
done
FAILED_FILE=infra-config-install
test -x /usr/local/bin/infra-config-install
[ "$(stat -c %a /usr/local/bin/infra-config-install)" = 755 ]
for f in container-restart-monitor.service container-restart-monitor.timer \
         cron-egress-firewall.service cron-egress-resolve.service cron-egress-resolve.timer \
         cron-egress-alarm@.service; do
  FAILED_FILE="$f"; test -f "/etc/systemd/system/$f"
done
FAILED_FILE=cron-egress-allowlist.txt; test -f /etc/soleur/cron-egress-allowlist.txt
FAILED_FILE=cron-egress-allowlist-cidr.txt; test -f /etc/soleur/cron-egress-allowlist-cidr.txt
FAILED_FILE=cosign-trusted-root.json; test -f /etc/soleur/cosign-trusted-root.json
FAILED_FILE=journald-soleur.conf; test -f /etc/systemd/journald.conf.d/00-soleur.conf
# (#6629) sandbox profiles present on-host AND the AppArmor profile is kernel-loaded — the
# terminal docker run's --security-opt apparmor=soleur-bwrap fails-to-create the container
# if the profile is not loaded, so assert the load here to fail with a NAMED stage instead.
FAILED_FILE=seccomp-bwrap.json; test -f /etc/docker/seccomp-profiles/soleur-bwrap.json
FAILED_FILE=apparmor-soleur-bwrap.profile; test -f /etc/apparmor.d/soleur-bwrap
FAILED_FILE=apparmor-loaded; aa-status 2>/dev/null | grep -qE '^[[:space:]]+soleur-bwrap$'

STAGE=reload
systemctl daemon-reload

# Make systemd-journald persistent + bounded (moved here from the early runcmd, #5921). Safe
# ordering: the only --log-driver journald consumer is the terminal app container, which
# starts after this; `journalctl --flush` migrates the early boot's volatile journal into the
# now-persistent store so nothing is lost. Mirrors terraform_data.journald_persistent.
STAGE=journald
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald
journalctl --flush

# #6005: authenticate the host docker daemon to the now-PRIVATE GHCR packages so the
# fresh-boot inngest-bootstrap `docker pull` (later in cloud-init runcmd) succeeds. Lives
# HERE (baked → zero user_data cost; user_data is within ~1 KB of the 32,768-byte cap).
# Best-effort: a missing/rotated credential must NOT poweroff the host — the subshell +
# `|| true` keeps it clear of `set -e` + the emit_fail trap; the inngest pull is the hard
# gate. Token fetched at boot via the ambient DOPPLER_TOKEN — NEVER templatefile-
# interpolated (that would leak it into Hetzner metadata + cloud-init-output.log).
STAGE=ghcr_login
( set +e
  . /etc/default/webhook-deploy 2>/dev/null || true
  # Non-fatal, no-SSH CAUSE signal for a fresh-boot login failure (observability-
  # coverage-reviewer P1). The block is deliberately OUTSIDE the emit_fail EXIT trap
  # (a rotated credential must not poweroff the host), so a failure would otherwise
  # only reach the SSH-only cloud-init-output.log — and Vector (Layer 3) is not yet
  # installed at this boot stage, so journald cannot ship it either. Emit a WARNING
  # Sentry event (tag stage=ghcr_login) directly, mirroring emit_fail's DSN parse,
  # SCRUBBED to a classification (never the raw docker stderr / auth header).
  ghcr_login_warn() {
    # Routes through the shared _sentry_emit boundary (#6090) — same baked-DSN
    # preference + fail-open subshell as emit_fail; only the body differs.
    _sentry_emit "$(printf '{"message":"fresh-boot GHCR docker login failed","level":"warning","logger":"soleur-host-bootstrap","tags":{"feature":"supply-chain","op":"image-pull","stage":"ghcr_login","pull_result":"%s","host_id":"%s"}}' "$1" "$HOST_ID")"
  }
  # (#6090) Prefer the BAKED creds (cloud-init writes /etc/default/soleur-ghcr-read early in
  # runcmd, deploy:deploy 0600) so the inngest-bootstrap + app image pulls authenticate on a
  # cold host even when Doppler answers EMPTY at the boot instant — the same failure class the
  # cloud-init ghcr_login (#6090) and the ci-deploy prelude (#6161) already bake against. An
  # empty fetch here skipped docker login → anonymous inngest pull → /var/lib/inngest never
  # created. (The old downstream "→ webhook.service 226/NAMESPACE → :9000 never binds → peer
  # fan-out degrades" chain is SEVERED as of #6090: webhook.service now marks /var/lib/inngest
  # `-`-optional, so an absent dir no longer wedges the unit. This baked-creds path still matters
  # when web_colocate_inngest is ON — the inngest pull itself needs auth.) Hardened Doppler
  # fallback (timeout 45 + 3-try retry).
  GHCR_USER=""; GHCR_TOKEN=""
  if [ -r /etc/default/soleur-ghcr-read ]; then
    # shellcheck disable=SC1091
    . /etc/default/soleur-ghcr-read 2>/dev/null || true
    GHCR_USER="${GHCR_READ_USER:-}"; GHCR_TOKEN="${GHCR_READ_TOKEN:-}"
    unset GHCR_READ_TOKEN   # keep the token out of this process env + its children
  fi
  [ -n "$GHCR_USER" ] || { n=0; until GHCR_USER=$(timeout 45 doppler secrets get GHCR_READ_USER --plain --project soleur --config prd 2>/dev/null); [ -n "$GHCR_USER" ]; do n=$((n+1)); [ "$n" -ge 3 ] && break; sleep 5; done; }
  [ -n "$GHCR_TOKEN" ] || { n=0; until GHCR_TOKEN=$(timeout 45 doppler secrets get GHCR_READ_TOKEN --plain --project soleur --config prd 2>/dev/null); [ -n "$GHCR_TOKEN" ]; do n=$((n+1)); [ "$n" -ge 3 ] && break; sleep 5; done; }
  if [ -n "$GHCR_USER" ] && [ -n "$GHCR_TOKEN" ]; then
    if printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin >/dev/null 2>&1; then
      echo "soleur-host-bootstrap: docker login ghcr.io ok"
    else
      echo "soleur-host-bootstrap: docker login ghcr.io FAILED (private pull may fail-closed)"
      ghcr_login_warn auth_denied
    fi
  else
    echo "soleur-host-bootstrap: GHCR_READ_{USER,TOKEN} not both present — skipping docker login"
    ghcr_login_warn credential_absent
  fi
  # #6122/ADR-096: ALSO authenticate to the self-hosted zot registry so the downstream
  # cloud-init inngest-bootstrap + app pulls can prefer zot. Strict dark-launch: only when
  # ZOT_REGISTRY_URL is present in Doppler prd (absent until the operator provisions (1.8) +
  # backfills (1.9) → a true no-op, and an unset URL emits NO beacon so a pre-provisioning
  # boot never pages). Same fail-open shape; the login writes a zot auths entry into the
  # host docker config that the later pulls reuse.
  zot_login_warn() {
    _sentry_emit "$(printf '{"message":"fresh-boot zot docker login failed","level":"warning","logger":"soleur-host-bootstrap","tags":{"feature":"supply-chain","op":"image-pull","stage":"zot_login","pull_result":"%s","host_id":"%s"}}' "$1" "$HOST_ID")"
  }
  ZOT_URL=$(timeout 15 doppler secrets get ZOT_REGISTRY_URL --plain --project soleur --config prd 2>/dev/null || true)
  if [ -n "$ZOT_URL" ]; then
    ZOT_USER=$(timeout 15 doppler secrets get ZOT_PULL_USER --plain --project soleur --config prd 2>/dev/null || true)
    ZOT_TOKEN=$(timeout 15 doppler secrets get ZOT_PULL_TOKEN --plain --project soleur --config prd 2>/dev/null || true)
    if [ -n "$ZOT_USER" ] && [ -n "$ZOT_TOKEN" ]; then
      if printf '%s' "$ZOT_TOKEN" | docker login "$ZOT_URL" -u "$ZOT_USER" --password-stdin >/dev/null 2>&1; then
        echo "soleur-host-bootstrap: docker login $ZOT_URL ok (zot-primary)"
      else
        echo "soleur-host-bootstrap: docker login $ZOT_URL FAILED (will fall back to GHCR)"
        zot_login_warn auth_denied
      fi
    else
      echo "soleur-host-bootstrap: ZOT_PULL_{USER,TOKEN} not both present — skipping zot login"
      zot_login_warn credential_absent
    fi
  else
    echo "soleur-host-bootstrap: ZOT_REGISTRY_URL unset — skipping zot login (dark)"
  fi ) || true

# Author the shared post-bootstrap Sentry emitter + readiness poller (#6090) for the
# DOWNSTREAM cloud-init region (cloudflared → webhook → app-run), which today carries NO
# Sentry trap at all — the deeper blind spot beyond the bootstrap block. Baked HERE (0
# user_data; the rendered cloud-init has only ~0.4 KB headroom under the 32,768-byte cap,
# so a per-block emit body is infeasible). The baked ${SOLEUR_SENTRY_DSN} is spliced in via
# a placeholder + sed (avoids per-`$` heredoc escaping); a non-`/` delimiter tolerates the
# DSN URL. FAIL-CLOSED authoring (runs under the top-level set -e + emit_fail trap): a write
# miss emits a NAMED stage=boot_emit fatal and aborts, NOT a later anonymous abort at the
# fail-closed readiness gates (`soleur-wait-ready … || exit 1`) with no signal. The install
# loop above already proved /usr/local/bin writable, so this won't spuriously fire.
STAGE=boot_emit; FAILED_FILE=soleur-boot-emit
cat > /usr/local/bin/soleur-boot-emit <<'EMITEOF'
#!/bin/sh
# Fail-open Sentry breadcrumb/fatal emitter for the cloud-init post-bootstrap region
# (#6090). usage: soleur-boot-emit <stage> [info|warning|fatal]. Always returns 0.
( set +e
  STAGE="$1"; LEVEL="$2"; [ -n "$LEVEL" ] || LEVEL=info
  HOST_ID=$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) | tr -d '"' )
  # (#6969) host_name attribution. Baked from the TF-injected SOLEUR_HOST_NAME via a second
  # sentinel splice; falls back to the kernel hostname. Attributing the web-2 dark boot
  # required a separate Hetzner API lookup to turn host_id=155488316 into a name — friction at
  # exactly the wrong moment on a Sentry project shared with web-1 traffic.
  HOST_NAME='@@SOLEUR_HOST_NAME@@'
  [ -n "$HOST_NAME" ] || HOST_NAME=$(hostname)
  DSN='@@SOLEUR_SENTRY_DSN@@'
  [ -n "$DSN" ] || exit 0
  KEY=$(printf '%s' "$DSN" | sed -E 's#https://([^@]+)@.*#\1#')
  SHOST=$(printf '%s' "$DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
  PROJ=$(printf '%s' "$DSN" | sed -E 's#.*/([0-9]+)$#\1#')
  # (#6969) per-stage detail channel: /run/soleur-stage-detail.d/<stage>, and NOTHING else.
  # A detail written for one stage can never surface under another.
  #
  # There is deliberately NO fallback to the legacy single-buffer /run/soleur-stage-detail.
  # An earlier revision of this PR added one "for compatibility", which silently made all nine
  # soleur-boot-emit stages read a SHARED buffer holding another stage's content (the ghcr
  # login/pull errors written by cloud-init). None of those stages has a legacy producer, so the
  # fallback bought nothing and cost cross-stage contamination — and a plausible WRONG cause is
  # worse than an empty one. The legacy buffer and its five producers are untouched; the inline
  # `_emit` in cloud-init.yml still reads it exactly as before.
  DDIR="${SOLEUR_STAGE_DETAIL_DIR:-/run/soleur-stage-detail.d}"
  SRC="$DDIR/$STAGE"
  # Sanitizer order is load-bearing (ADR-147). The preamble drop comes FIRST: the Doppler CLI
  # writes two `Using DOPPLER_* from the environment` lines (173 B measured on the pinned
  # v3.75.3) ahead of the real error, so a leading-bytes cap would ship pure noise and truncate
  # the cause away. Newline folding is a correctness requirement, not tidiness — newlines are
  # documented as impermissible in Sentry tag values and captured stderr is multi-line by
  # nature. The printable-ASCII pass runs AFTER the cap so a byte-wise cut can never emit a
  # partial multi-byte sequence.
  # Credential redaction lives HERE, in the emitter, because the emitter is the single choke
  # point every producer flows through — the per-stage files, the legacy buffer, and any
  # producer added later. Putting it only in the doppler helper (where it started) left the
  # `docker_run` stderr path with no redactor at all, and that path carries the stderr of the
  # one command handed the entire prd secret set.
  #   - dp\.[A-Za-z0-9_.-]* is greedy over DOTS: a config-scoped Doppler service token is
  #     dp.st.<config>.<entropy>, i.e. FOUR segments. A class excluding `.` stops at the second
  #     dot and redacts the CONFIG NAME while preserving the entropy.
  #   - URI userinfo and Bearer cover credential shapes the dp. rule cannot see.
  #   - The PEM sentinel truncates at the header: key material is multi-line, and the newline
  #     fold below would otherwise splice it onto one line inside the cap.
  ESC=$(printf '\033')
  DETAIL=$(LC_ALL=C sed -e '/^Using /d' -e "s/${ESC}\\[[0-9;]*[a-zA-Z]//g" "$SRC" 2>/dev/null \
    | LC_ALL=C sed -e 's/dp\.\(st\|pt\|sa\|ct\|scim\|audit\)\.[A-Za-z0-9._-]\{10,\}/dp.REDACTED/g' \
                -e 's/gh[pousr]_[A-Za-z0-9]\{20,\}/REDACTED_GH/g' \
                -e 's#://[A-Za-z0-9._%+-]\{1,\}:[^@/[:space:]]\{1,\}@#://REDACTED@#g' \
                -e 's/[Bb]earer[[:space:]]\{1,\}[A-Za-z0-9._~+/=-]\{8,\}/Bearer REDACTED/g' \
                -e 's/-----BEGIN [A-Z ]*PRIVATE KEY-----.*/[PRIVATE KEY REDACTED]/' \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' \
    | LC_ALL=C tr -d '"\\' \
    | LC_ALL=C tr '\011\012\015' '   ' \
    | LC_ALL=C sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | tail -c 180 \
    | LC_ALL=C tr -cd '\040-\176')
  BODY=$(printf '{"message":"soleur-cloud-init boot stage","level":"%s","tags":{"stage":"%s","host_id":"%s","region":"cloud-init","host_name":"%s","detail":"%s"}}' "$LEVEL" "$STAGE" "$HOST_ID" "$HOST_NAME" "$DETAIL")
  curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/" \
    -H 'Content-Type: application/json' \
    -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY" \
    -d "$BODY" >/dev/null 2>&1 || true
) || true
exit 0
EMITEOF
sed -i "s|@@SOLEUR_SENTRY_DSN@@|${SOLEUR_SENTRY_DSN:-}|" /usr/local/bin/soleur-boot-emit
# (#6969) second splice, same non-`/` delimiter idiom + the same ${SOLEUR_HOST_NAME:-$(hostname)}
# fallback vector.toml already uses. A residual @@ would ship host_name=@@SOLEUR_HOST_NAME@@ on
# every event, silently — asserted below.
sed -i "s|@@SOLEUR_HOST_NAME@@|${SOLEUR_HOST_NAME:-}|" /usr/local/bin/soleur-boot-emit
# chmod BEFORE the sentinel assertion. The assertion aborts the boot on a residual sentinel, and
# the terminal block's own `hostscripts_incomplete` fatal is emitted BY this binary — so aborting
# while it is still mode 0644 means the abort itself cannot be reported, and the host poweroffs
# unpaged. Make it executable first, then assert.
chmod 0755 /usr/local/bin/soleur-boot-emit
# `if`, NOT `grep -q ... && { false; }`: the latter is an AND-OR list whose own exit status is
# the statement's, so a CLEAN file (grep exits 1) would abort the boot under set -e. An `if`
# condition is set -e-exempt in both dash and bash.
if grep -q '@@' /usr/local/bin/soleur-boot-emit; then
  STAGE=boot_emit_sentinel; FAILED_FILE=soleur-boot-emit; false
fi
# (#6969) the per-stage detail directory must exist before the terminal block's `docker run`
# redirects its stderr into it. /run is tmpfs and this bootstrap runs in an earlier runcmd item
# of the same boot, so the directory is guaranteed present by the time the terminal block runs.
mkdir -p /run/soleur-stage-detail.d
# Bounded readiness poll (#6090, H4) — baked (0 user_data; only ~0.4 KB cap headroom, so the
# poll body cannot live inline). systemd enable commands
# return 0 the instant a unit launches, NOT when it connects/binds; this polls the real
# invariant so an ASYNC death (the primary "cloudflared never comes up / :9000 never binds"
# symptom) becomes a NAMED fatal instead of a silent green-and-broken boot. Callers do
# `|| exit 1` to abort the boot on timeout — a never-ready service SHOULD fail it.
cat > /usr/local/bin/soleur-wait-ready <<'WAITEOF'
#!/bin/sh
# usage: soleur-wait-ready service <unit> <stage> | soleur-wait-ready port <port> <stage>
KIND="$1"; NAME="$2"; STAGE="$3"; n=0
while :; do
  case "$KIND" in
    service) systemctl is-active --quiet "$NAME" && break ;;
    port) { ss -ltn 2>/dev/null | grep -q ":$NAME" || curl -s -o /dev/null --max-time 3 "http://localhost:$NAME/" 2>/dev/null; } && break ;;
  esac
  n=$((n+1)); [ "$n" -ge 30 ] && { soleur-boot-emit "$STAGE" fatal; exit 1; }; sleep 2
done
soleur-boot-emit "$STAGE" info
WAITEOF
chmod 0755 /usr/local/bin/soleur-wait-ready

# (#6969) Bounded, self-reporting Doppler secrets download for the cloud-init terminal block.
# Baked (0 user_data; only ~0.5 KB of gzipped cap headroom remains, so this body cannot live
# inline). Authored as a heredoc like soleur-boot-emit — NOT via the `install -D "$SEED/$f"`
# loop above, which only handles files that come from the seed tarball; a seed file would force
# edits to local.host_script_files, the image bake and the coherence preflight.
#
# Replaces a single unbounded attempt whose stderr and exit code were discarded. That call was
# the ONLY unbounded Doppler invocation in cloud-init.yml (11 siblings are timeout-wrapped), so
# a hang emitted nothing at all and the channel was structurally blind to the leading
# hypothesis' most common shape.
STAGE=doppler_download_helper; FAILED_FILE=soleur-doppler-download
cat > /usr/local/bin/soleur-doppler-download <<'DDLEOF'
#!/bin/sh
# usage: soleur-doppler-download <target-env-file>
#
# STDOUT IS RESERVED FOR THE SECRET PAYLOAD. `--format docker` writes the entire prd secret set
# to stdout, and the caller feeds the target file to `docker run --env-file`. Every diagnostic
# here goes to stderr or to the per-stage detail files; a stray stdout write would corrupt the
# env file and misattribute the resulting fatal to stage=docker_run. Never `2>&1`, never `&>`.
set -u
OUT="$1"
DDIR="${SOLEUR_STAGE_DETAIL_DIR:-/run/soleur-stage-detail.d}"
ATTEMPTS="${SOLEUR_DOPPLER_ATTEMPTS:-3}"
# 20 s, not 45 s. Measured against the live prd config (129 secrets): 0.27-0.33 s per download,
# so 20 s is ~60x headroom on the success path while bounding the FAILURE path far more tightly.
# The budget matters: soleur-host-bootstrap.sh's own 900 s fresh-boot derivation sums to exactly
# 900 with no slack term AND does not include this stage at all (the pre-#6969 call was unbounded
# and implicitly costed at 0). Overshooting 900 s converts a DIAGNOSABLE fatal verdict into an
# undiagnosable `timeout` — the retry degrading the very channel it rides on — and also trips the
# Better Stack absence alert that uses the same window as its grace period.
TMO="${SOLEUR_DOPPLER_TIMEOUT:-20}"
B1="${SOLEUR_DOPPLER_BACKOFF_1:-5}"
B2="${SOLEUR_DOPPLER_BACKOFF_2:-10}"
# Worst case: 3 x (20 s + 5 s SIGKILL grace) + 5 s + 10 s backoff + 2 x 12 s bounded emit = 114 s.
EMIT_TMO="${SOLEUR_DOPPLER_EMIT_TIMEOUT:-12}"
# Mode at CREATION, not chmod-after: the buffers hold scrubbed, capped process stderr on a
# root-owned tmpfs, and there is no window in which they should be world-readable. Not
# `mkdir -p -m`: with -p the mode applies only to the deepest component (SC2174), which is
# misleading here even though /run always exists. The chmod is the idempotent belt.
[ -d "$DDIR" ] || mkdir -m 700 "$DDIR" 2>/dev/null || true
chmod 700 "$DDIR" 2>/dev/null || true
# /run, not /tmp. The host's /tmp is NOT a tmpfs (the only --tmpfs is the CONTAINER flag in
# cloud-init.yml and there is no host `mounts:` entry), so a /tmp buffer would put UNSCRUBBED
# stderr on the unencrypted root disk, where `rm -f` unlinks without erasing the blocks. /run is
# systemd tmpfs — RAM-backed, never touches a block device, gone at power-off.
# The dir is a seam (default = the real host path) only so the suite can run unprivileged; /run
# is root-only, and the tests must not need root to exercise the failure paths.
ERRDIR="${SOLEUR_DOPPLER_ERRDIR:-/run}"
ERRF=$(mktemp "$ERRDIR/doppler-err.XXXXXX") || {
  # Even this path must leave the trap a cause to emit. Without it the terminal fatal ships an
  # EMPTY detail, which is byte-for-byte the #6969 symptom this helper exists to end.
  printf 'doppler_download rc=70 cond=mktemp_failed attempts=0' > "$DDIR/doppler_download" 2>/dev/null || true
  exit 70
}
chmod 600 "$ERRF" 2>/dev/null || true
# This helper is a SEPARATE PROCESS from the cloud-init terminal block, so that block's EXIT
# trap cannot see $ERRF. The helper owns its own cleanup.
trap 'rm -f "$ERRF"' EXIT INT TERM HUP
rc=0
n=1
while :; do
  : > "$ERRF"
  # -k 5: plain `timeout` sends SIGTERM and then waits FOREVER for a child that ignores it. The
  # Doppler CLI is Go and installs its own handlers, so without -k a TERM-ignoring hang is still
  # unbounded — the exact structural blindness this bound exists to remove.
  NO_COLOR=1 timeout -k 5 "$TMO" doppler secrets download --no-file --format docker \
    --project soleur --config prd > "$OUT" 2>"$ERRF" && rc=0 || rc=$?
  # rc=0 is NOT sufficient. `doppler` can exit 0 having written nothing, and
  # `docker run --env-file <empty>` then STARTS the container: the host reaches
  # cloud_init_complete, the gate reports "booted clean", and it is serving with zero prd
  # secrets. A green-and-secretless host is strictly worse than a dark one, so treat an empty
  # payload as a distinct named failure rather than success.
  if [ "$rc" = 0 ] && [ ! -s "$OUT" ]; then
    rc=71
    printf 'doppler exited 0 but wrote an EMPTY secret payload\n' > "$ERRF"
  fi
  [ "$rc" = 0 ] && exit 0
  # Scrub BEFORE any write. The "stderr does not echo the token" measurement is pinned to CLI
  # v3.75.3 and CLI-version behaviour is itself a live hypothesis, so this is defence in depth.
  # The preamble drop and the cap happen here too: the emitter re-caps at 180, and capping a
  # preamble-laden string there would tail away the actual cause.
  SCRUB=$(LC_ALL=C sed -e '/^Using /d' -e 's/dp\.\(st\|pt\|sa\|ct\|scim\|audit\)\.[A-Za-z0-9._-]\{10,\}/dp.REDACTED/g' "$ERRF" 2>/dev/null \
    | LC_ALL=C tr '\011\012\015' '   ' | tail -c 100)
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then COND=timeout
  elif [ "$rc" = 71 ]; then COND=empty_payload
  else COND=error; fi
  # Ordering is load-bearing: capture rc -> scrub -> write the detail -> emit -> increment ->
  # exhaust-check -> sleep. `n=$((n+1))` resets $?, and emitting after the exhaust-check would
  # lose the final attempt's breadcrumb.
  if [ "$n" -lt "$ATTEMPTS" ]; then
    # stage=doppler_retry, never `doppler_download_attempt`: the latter string-PREFIXES the
    # alert-filtered stage, which would make the op-contract anti-rename test vacuous. The
    # alert has no level filter and its shared group is perpetually hot, so a warning reusing a
    # filtered stage name would page the founder on a healthy boot.
    printf 'doppler_retry rc=%s cond=%s attempt=%s/%s %s' "$rc" "$COND" "$n" "$ATTEMPTS" "$SCRUB" > "$DDIR/doppler_retry"
    # BOUNDED. The emitter's transport is `curl -m 10 --retry 3`, and -m is PER TRANSFER, so
    # --retry multiplies it: one emit's worst case is ~47 s, not 10 s. Worse, the emit is slowest
    # exactly when it is called — the faults that fail the Doppler fetch (no resolver, no route,
    # egress drop) are the same ones that make the Sentry POST time out rather than fail fast.
    # Unbounded, two in-loop emits added ~94 s of failure-correlated latency to the boot window.
    timeout "$EMIT_TMO" soleur-boot-emit doppler_retry warning || true
  fi
  n=$((n+1))
  [ "$n" -gt "$ATTEMPTS" ] && break
  if [ "$n" = 2 ]; then sleep "$B1"; else sleep "$B2"; fi
done
# The terminal block's trap emits stage=doppler_download and reads THIS file. Writing it before
# returning non-zero is what keeps the headline fatal from shipping an empty detail — an empty
# detail is byte-for-byte the #6969 symptom this helper exists to end.
printf 'doppler_download rc=%s cond=%s attempts=%s %s' "$rc" "$COND" "$ATTEMPTS" "$SCRUB" > "$DDIR/doppler_download"
exit "$rc"
DDLEOF
chmod 0755 /usr/local/bin/soleur-doppler-download

# (#6969) Existence assertions for the two HEREDOC-authored helpers. These MUST sit AFTER both
# heredocs: the `test -x` loop far above covers only SEED-installed files, which are installed
# before it runs, whereas these two are authored here. An earlier revision of this PR put these
# assertions in that upstream `STAGE=assert` block — where, under the file's top-level `set -e`,
# they asserted files that did not exist yet and would have aborted EVERY fresh boot before the
# emitter was ever written. The suite missed it because the assertion only grepped that the
# `test -x` line and the `cat >` line co-existed, not that they were ordered.
# Why assert at all: the install loop's `test -x` sweep does not cover heredoc-authored files, so
# a truncated heredoc would still let the boot write /run/soleur-hostscripts.ok and the terminal
# block would then die `command not found` (127) with no attributable stage.
STAGE=assert_baked
FAILED_FILE=soleur-boot-emit
test -x /usr/local/bin/soleur-boot-emit
FAILED_FILE=soleur-doppler-download
test -x /usr/local/bin/soleur-doppler-download

# Bounded private-NIC wait (#6441, ADR-114 I1) — baked (0 user_data; the call site is the
# only inline cost). DELIBERATELY fail-OPEN, unlike its fail-CLOSED neighbour
# soleur-wait-ready directly above — the two gate the same cloudflared step a few lines
# apart, so the asymmetry needs stating or it reads as an inconsistency:
#
#   - soleur-wait-ready runs AFTER the unit exists. A never-ready cloudflared is a TERMINAL
#     condition, so its `|| exit 1` caller contract is defensible.
#   - soleur-wait-nic runs BEFORE the unit exists, on a condition that provably SELF-HEALS:
#     cloudflared dials its ingress origin per CONNECTION, not at process start, so a
#     connector that registered NIC-less begins serving the instant the attach lands — no
#     restart, no operator action. Aborting here would destroy the recovery channel to
#     prevent a condition that resolves itself.
#
# And aborting is not a small cost: runcmd is ONE /bin/sh and is once-per-instance, so an
# `exit 1` does not skip a step — it terminates cloudflared install, the webhook binary, the
# :9000 readiness gate, the disk/resource monitors and the container egress firewall, for the
# life of that instance (CF-5). A NIC that converges at minute 11 would then be irrelevant.
# No reboot either: web-1 is the SOLE live origin, and ADR-115's converge-by-reboot grant is
# registry-host-scoped by explicit normative blocker, not class-wide (CF-6).
STAGE=wait_nic; FAILED_FILE=soleur-wait-nic
cat > /usr/local/bin/soleur-wait-nic <<'NICEOF'
#!/bin/sh
# usage: soleur-wait-nic <expected-ip>
# ALWAYS exits 0. Emits EXACTLY ONE event, from three mutually-exclusive arms. Never aborts
# the boot, never reboots. The emit is the ONLY evidence this gate ran: a fresh cloud-init
# boot is a blind surface (no SSH, no shell), so an arm that emitted nothing would be
# indistinguishable from a gate that never shipped.
EXPECTED="$1"
# (0) ARGUMENT GUARD — load-bearing, and the direction that matters. `grep -qwF -- ""` matches
# EVERY line, so an empty argument would make the first probe succeed and emit
# private_nic_ready: positive evidence that a check passed which was never performed. That is
# strictly worse than the fail-open this helper is designed for, and it inverts the #6415
# doctrine below (asserting PRESENCE on zero evidence). var.web_hosts validates private_ip
# against ^10\.0\.1\.[0-9]{1,3}$, but that defence lives in another file behind a templatefile
# map — "works today, fails silently on a future host" is the shape this repo keeps getting
# bitten by, so the helper defends itself. Mirrors web-private-nic-guard.sh's own EXPECTED_IP
# check, which is terminal there; here it takes the probe-fault arm to preserve exit 0.
[ -n "$EXPECTED" ] || { soleur-boot-emit private_nic_probe_fault warning; exit 0; }
# (1) PROBE RESOLUTION FIRST, and short-circuit before the wait. An unresolvable probe is ZERO
# EVIDENCE — it must never be conflated with "the address is absent" (#6415), hence a THIRD arm
# rather than folding probe-fault into the timeout arm. Short-circuiting also avoids spending
# the full 60 s budget on a missing binary. `ip` is the one that actually motivates this (it
# lives in /usr/sbin, absent from some minimal PATHs) but grep is checked too: without it the
# match can never succeed, and reporting THAT as "the address is absent" is the same mislabel.
IP_BIN=$(command -v ip 2>/dev/null || true)
GREP_BIN=$(command -v grep 2>/dev/null || true)
PROBE_OK=true
[ -n "$IP_BIN" ] && [ -x "$IP_BIN" ] || PROBE_OK=false
[ -n "$GREP_BIN" ] && [ -x "$GREP_BIN" ] || PROBE_OK=false
if [ "$PROBE_OK" != true ]; then
  soleur-boot-emit private_nic_probe_fault warning
  exit 0
fi
# (2) Probe. The probe's EXIT is captured separately from the match result, because a pipeline
# reports only grep's status: `ip … 2>/dev/null | grep -qwF` makes an `ip` that RUNS AND FAILS
# (netlink denied, truncated image) indistinguishable from one that ran and found nothing —
# reporting "could not measure" as "absent", the #6415 mislabel arriving through a second door.
# probe_ran records whether the instrument EVER worked; the fault arm fires only if it never did
# (so a transient failure that later recovers is not misreported).
# -w + -F + --: exact word, fixed string, end-of-options — so 10.0.1.1 can never match inside
# 10.0.1.10 and the dots are not regex wildcards. Mirrors web-private-nic-guard.sh.
# (No pipefail is set in this helper, so grep's exit governs the match.)
nic_ok=false
probe_ran=false
if OUT=$("$IP_BIN" -4 -o addr show 2>/dev/null); then
  probe_ran=true
  printf '%s\n' "$OUT" | grep -qwF -- "$EXPECTED" && nic_ok=true
fi
# (3) Bounded wait — 30 x 2 s = 60 s. Spent BEFORE `cloudflared service install`, so this budget
# is SEQUENTIAL with the downstream cloudflared_ready gate's own ~60 s budget rather than nested
# inside it. A POSIX counter rather than `for i in $(seq 1 30)`: an unresolvable `seq` yields an
# EMPTY word list, so the loop body would run ZERO times and the helper would report a 60 s
# timeout it never waited — a no-op that looks like it ran. One fewer binary to depend on, and
# the loop variable was unused anyway.
if [ "$nic_ok" = false ]; then
  n=0
  while [ "$n" -lt 30 ]; do
    n=$((n + 1))
    sleep 2
    if OUT=$("$IP_BIN" -4 -o addr show 2>/dev/null); then
      probe_ran=true
      printf '%s\n' "$OUT" | grep -qwF -- "$EXPECTED" && { nic_ok=true; break; }
    fi
  done
fi
# (4) Exactly one event, mutually exclusive and total.
if [ "$nic_ok" = true ]; then
  soleur-boot-emit private_nic_ready info
elif [ "$probe_ran" = false ]; then
  soleur-boot-emit private_nic_probe_fault warning
else
  soleur-boot-emit private_nic_timeout warning
fi
exit 0
NICEOF
chmod 0755 /usr/local/bin/soleur-wait-nic

# Completion breadcrumb (#6090): the SINGLE signal distinguishing "died IN bootstrap"
# (emit_fail names a bootstrap stage) from "bootstrap COMPLETED, died downstream" (this
# breadcrumb present + a later cloud-init stage fatal). Fail-open via _sentry_emit.
STAGE=bootstrap_complete
_sentry_emit "$(printf '{"message":"soleur-host-bootstrap complete","level":"info","tags":{"stage":"bootstrap_complete","host_id":"%s","region":"bootstrap"}}' "$HOST_ID")"

# ---------------------------------------------------------------------------
# Vector observability shipper — UNGATED web-host path (#6396). ADR-100 moved
# scheduling off the web host (web_colocate_inngest default false), so a fresh
# web host installs NO Vector via the inngest path and ships NO logs. This
# decouples the shipper: stage the baked config here (SEED is rm -rf'd after
# bootstrap), then author /usr/local/bin/soleur-vector-install for the ungated,
# fail-open, timeout-bounded end-of-cloud-init run (AFTER the app binds :80/:3000,
# so observing the boot can NEVER break serving). Same journald/host_metrics data
# class already ships from the inngest source — no new processor.
#
# The STAGING below is under `set -e` + emit_fail ON PURPOSE: vector.toml is a
# hash-verified baked file (host_scripts_content_hash gate), so its absence is a
# coherence violation (fail-closed, like every other baked asset). The RUNTIME
# install (binary download, unit start) is where fail-open lives — see the helper.
STAGE=vector_stage; FAILED_FILE=vector.toml
mkdir -p /opt/soleur /etc/vector
# Persist the shared config with @@HOST_NAME@@ resolved to THIS host's TF-injected server
# name (SOLEUR_HOST_NAME, passed by cloud-init). Distinct per host so web-1/web-2 do not
# collapse into one host_name in the shared Better Stack source 2457081.
sed "s|@@HOST_NAME@@|${SOLEUR_HOST_NAME:-$(hostname)}|g" "$SEED/vector.toml" > /opt/soleur/vector.toml

STAGE=vector_install_author; FAILED_FILE=soleur-vector-install
cat > /usr/local/bin/soleur-vector-install <<'VINEOF'
#!/bin/sh
# Fail-open Vector installer for the ungated web-host path (#6396). Invoked once at
# end-of-cloud-init as `timeout 60 sh -c 'soleur-vector-install' || true`, AFTER the app
# container binds :80/:3000. Vector is observability, NEVER serving-critical: EVERY step
# here is swallowed (the outer ( set +e … ) || true), so a slow/failed fetch or unit start
# can never wedge the boot. Idempotent: version-pinned + sha-verified + skip-on-match.
( set +e
  # Pin MUST stay in lockstep with vector.tf locals (vector_version / vector_sha256[_arm64]);
  # soleur-host-bootstrap-observability.test.sh AC22 asserts byte-identity vs vector.tf.
  VECTOR_VERSION="0.43.1"
  case "$(uname -m)" in
    x86_64|amd64)  VEC_TRIPLE="x86_64-unknown-linux-musl";  VEC_SHA="8a3cc62d18ec88bb8433159d1d3455d3c77fefff73ce46d4f8cc464e100f65f1" ;;
    aarch64|arm64) VEC_TRIPLE="aarch64-unknown-linux-musl"; VEC_SHA="365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6" ;;
    *) echo "soleur-vector-install: unsupported arch $(uname -m); skipping" >&2; exit 0 ;;
  esac
  BIN=/usr/local/bin/vector
  VERFILE=/var/lib/vector/version
  CFG=/etc/vector/vector.toml
  UNIT=/etc/systemd/system/vector.service

  # #6396: on a (deprecated) web_colocate_inngest=true host the inngest path already installed +
  # started an inngest-OWNED vector.service (host_name=soleur-inngest-prd,
  # EnvironmentFile=/etc/default/inngest-server). Do NOT clobber it — the two Vector paths are
  # made mutually exclusive by THIS runtime guard, not by runcmd ordering (a template gate can't
  # negate the string-"false" rollback value cleanly). Default hosts (colocate=false) have no
  # such unit, so the web install proceeds.
  if [ -f "$UNIT" ] && grep -q '/etc/default/inngest-server' "$UNIT" 2>/dev/null; then
    echo "soleur-vector-install: inngest-owned vector.service present; skipping web install" >&2
    exit 0
  fi

  [ -f /opt/soleur/vector.toml ] || { echo "soleur-vector-install: staged config missing; skipping" >&2; exit 0; }
  mkdir -p /etc/vector /var/lib/vector
  install -m 0644 /opt/soleur/vector.toml "$CFG"
  chown -R deploy:deploy /var/lib/vector 2>/dev/null || true

  cur=""; [ -f "$VERFILE" ] && cur="$(cat "$VERFILE" 2>/dev/null)"
  if [ "$cur" != "$VECTOR_VERSION" ] || [ ! -x "$BIN" ]; then
    tmp="$(mktemp -d)" || exit 0
    url="https://packages.timber.io/vector/${VECTOR_VERSION}/vector-${VECTOR_VERSION}-${VEC_TRIPLE}.tar.gz"
    if curl -fsSL --max-time 120 -o "$tmp/v.tgz" "$url"; then
      got="$(sha256sum "$tmp/v.tgz" | awk '{print $1}')"
      if [ "$got" = "$VEC_SHA" ]; then
        if tar -xzf "$tmp/v.tgz" -C "$tmp" && install -m 0755 "$tmp/vector-${VEC_TRIPLE}/bin/vector" "$BIN"; then
          printf '%s\n' "$VECTOR_VERSION" > "$VERFILE"
        fi
      else
        echo "soleur-vector-install: sha mismatch (exp $VEC_SHA got $got); skipping" >&2
      fi
    fi
    rm -rf "$tmp"
  fi
  [ -x "$BIN" ] || { echo "soleur-vector-install: vector binary absent; skipping unit" >&2; exit 0; }

  # Web-host unit — DOPPLER_TOKEN comes from /etc/default/webhook-deploy (present on EVERY web
  # host), NOT /etc/default/inngest-server (inngest-only). Without it `doppler run` has no token
  # → Vector never starts → fail-open masks it → silent absent host_name source (spec-flow P0).
  # Project is always `soleur` for a web host (dev!=prd; web reads --config prd).
  # doppler is resolved via `command -v` (NOT a hardcoded /usr/bin/doppler): on the web host the
  # doppler CLI is tarball-installed to /usr/local/bin (cloud-init.yml), NOT /usr/bin — every
  # sibling web-host unit (cron-egress-firewall.service etc.) uses this same resolution to avoid
  # a 203/EXEC crash-loop. Fail-open else-branch: if doppler/token is somehow absent, exec vector
  # directly (it starts but the Better Stack sink 401s — ships nothing — rather than crash-looping).
  cat > "$UNIT" <<'UNITEOF'
[Unit]
Description=Vector observability shipper (journald + host_metrics -> Better Stack Logs)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/webhook-deploy
ExecStart=/bin/sh -c 'D="$(command -v doppler || true)"; if [ -n "$D" ] && [ -n "$DOPPLER_TOKEN" ]; then exec "$D" run --project soleur --config prd -- /usr/local/bin/vector --config /etc/vector/vector.toml; else exec /usr/local/bin/vector --config /etc/vector/vector.toml; fi'
Restart=on-failure
RestartSec=10
User=deploy
Group=deploy
SupplementaryGroups=systemd-journal
MemoryMax=256M
CPUQuota=50%
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=true
ReadWritePaths=/var/lib/vector
ReadOnlyPaths=/etc/vector
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNITEOF
  systemctl daemon-reload 2>/dev/null || true
  # enable + restart --no-block (NOT enable --now: --now no-ops on an already-running unit and
  # keeps a stale config; --no-block keeps the fail-open install off the serving-latency path).
  systemctl enable vector.service 2>/dev/null || true
  systemctl restart --no-block vector.service 2>/dev/null || true
) || true
exit 0
VINEOF
chmod 0755 /usr/local/bin/soleur-vector-install

# #6604 — bake the STRUCTURAL fail-closed /mnt/data mapper gate for the FUTURE fresh-host path.
# ACKNOWLEDGED DEAD ON WEB-1 (ADR-119 §(e)): cx33 is unrebuildable in all 3 EU DCs, so web-1 never
# re-creates and cloud-init never re-runs — the LIVE gate is delivered to web-1 over the cutover
# channel (workspaces-cutover.sh). This baked helper is the fresh-host analogue: it makes
# "container running ⇒ /mnt/data is the LUKS mapper" hold BY CONSTRUCTION across the dockerd
# `--restart unless-stopped` reboot resurrection (C2), where a pre-`docker run` shell gate catches
# nothing. Kept MINIMAL per DP-10 (crypttab + RequiresMountsFor + chattr +i, no gold-plating); the
# full fresh-host LUKS provisioning (keyscript wiring, luksFormat-on-birth) is a tracked deferral —
# it cannot be exercised until a fresh host is actually born, and web-1 never will be.
STAGE=luks_structural_gate_author; FAILED_FILE=soleur-luks-structural-gate
cat > /usr/local/bin/soleur-luks-structural-gate <<'LUKSGATEEOF'
#!/bin/sh
# Idempotent structural fail-closed gate: /mnt/data MUST be the LUKS mapper before the app
# container can start. Safe no-op on a host with no LUKS volume attached (today's plaintext
# fresh host) — it only arms once /dev/mapper/workspaces exists.
set -eu
MOUNT=/mnt/data
MAPPER=/dev/mapper/workspaces
# 1. crypttab: name the mapper so systemd opens it at boot (keyfile wiring is the deferred half).
if [ ! -e /etc/crypttab ] || ! grep -q '^workspaces[[:space:]]' /etc/crypttab; then
  echo 'workspaces  /dev/disk/by-label/workspaces_luks  none  luks,nofail' >> /etc/crypttab
fi
# 2. chattr +i the ROOT-DISK mountpoint inode so, if the mapper mount is absent, Docker's implicit
#    bind-mount mkdir gets EPERM and the container REFUSES to start (an outage, not a silent
#    plaintext write to the root disk — the #5274 data-stranding mode). Only immutabilize the bare
#    (unmounted) mountpoint; never the live mapper mount.
mkdir -p "$MOUNT"
if ! mountpoint -q "$MOUNT"; then
  chattr +i "$MOUNT" 2>/dev/null || true
fi
# 3. RequiresMountsFor drop-in: the app container unit must order after the /mnt/data mount so it
#    can never start before the mapper is mounted (survives the --restart resurrection — C2).
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/10-workspaces-luks-mount.conf <<'DROPIN'
[Unit]
RequiresMountsFor=/mnt/data
DROPIN
systemctl daemon-reload 2>/dev/null || true
: "$MAPPER"  # referenced for documentation; the crypttab name is the load-bearing binding
LUKSGATEEOF
chmod 0755 /usr/local/bin/soleur-luks-structural-gate

# ── Fresh-boot readiness marker (#6459 / #6538 dark-host fix) ──────────────────────────────────
# Author /usr/local/bin/soleur-fresh-boot-ready: a one-shot, Vector-INDEPENDENT readiness marker
# invoked as the LAST first-boot cloud-init item (AFTER the app binds and soleur-vector-install).
# Baked here → 0 user_data cost. Its ABSENCE past its own boot-window = the host booted dark.
STAGE=fresh_boot_ready_author; FAILED_FILE=soleur-fresh-boot-ready
cat > /usr/local/bin/soleur-fresh-boot-ready <<'FRESHREADYEOF'
#!/bin/sh
# SOLEUR_FRESH_BOOT_READY — one-shot fresh-boot readiness marker (#6459 / #6538 dark-host fix).
# Runs as the LAST first-boot cloud-init item, AFTER the app binds :80/:3000 and soleur-vector-install.
# Dual-channel + Vector-INDEPENDENT so absence/not-ready stays observable when Vector is the thing
# that broke (a marker shipped THROUGH Vector would vanish exactly when a dark Vector is the fault):
#   1. curl            → Better Stack Logs (direct, best-effort; the discoverability-test read path)
#   2. soleur-boot-emit → baked-DSN Sentry (always available)
#   3. logger -t       → local journald breadcrumb (on-host `journalctl -t SOLEUR_FRESH_BOOT_READY`)
# OBSERVABILITY marker, NOT a gate: always exits 0 (the app is already up; a poweroff here is worse
# than a loud ready=0). Absence past SOLEUR_FRESH_BOOT_WINDOW_SECONDS = the host booted dark.
set -u
# Absence-detection deadline (seconds). Derivation — worst-case bounded first-boot span:
# soleur-wait-ready x2 (webhook :9000 + cloudflared) 120s + soleur-wait-nic <=120s + `timeout 180`
# vector install 180s + image-pull budget (web+app+plugin-seed) ~300s + apt/docker install ~120s +
# Hetzner create->runcmd overhead ~60s ~= 900s. The Phase-3 Better Stack absence alert
# (web-probe.tf) uses this as its grace window — keep the emit and any alert period in lockstep.
SOLEUR_FRESH_BOOT_WINDOW_SECONDS=900
# Path seams (defaults = the real host paths; overridable so the unit test can drive each branch).
WEBHOOK_ENV_FILE="${WEBHOOK_ENV_FILE:-/etc/default/webhook-deploy}"
WORKSPACES_MOUNT="${WORKSPACES_MOUNT:-/mnt/data}"
LUKS_MAPPER="${LUKS_MAPPER:-/dev/mapper/workspaces}"
# token: the Doppler token actually reached the host — fail LOUD (reason=token), never a silent env
# fallback (2026-04-03 doppler-not-installed-env-fallback-outage).
if [ -s "$WEBHOOK_ENV_FILE" ] && grep -q '^DOPPLER_TOKEN=..*' "$WEBHOOK_ENV_FILE" 2>/dev/null; then T=1; else T=0; fi
# vector: the ungated Vector installed AND its unit is active — vector=0 IS the #6538 dark signal.
if command -v vector >/dev/null 2>&1 && systemctl is-active --quiet vector 2>/dev/null; then V=1; else V=0; fi
# volume: the workspace volume is mounted; luks=1 iff the LUKS mapper backs it. luks= is REPORTED,
# not gated — both hosts are plaintext today: web-1 until its per-host ADR-119 cutover, and web-2's
# for_each volume is KNOWINGLY plaintext-but-empty pre-flip (ADR-143 R3 / workspaces-luks.tf:169-197)
# — its guest-side fresh-boot LUKS path is DEFERRED to #6931, NOT "LUKS-from-birth". A future Phase
# tightens luks=1 to gated once #6931 lands.
if mountpoint -q "$WORKSPACES_MOUNT" 2>/dev/null; then VOL=1; else VOL=0; fi
if [ -e "$LUKS_MAPPER" ]; then LUKS=1; else LUKS=0; fi
READY=0; REASON=none
if [ "$T" = 1 ] && [ "$V" = 1 ] && [ "$VOL" = 1 ]; then
  READY=1
elif [ "$T" != 1 ]; then REASON=token
elif [ "$V" != 1 ]; then REASON=vector
else REASON=volume
fi
LINE="SOLEUR_FRESH_BOOT_READY ready=$READY stage=cloud_init_complete token=$T vector=$V volume=$VOL luks=$LUKS reason=$REASON boot_window_s=$SOLEUR_FRESH_BOOT_WINDOW_SECONDS"
# (3) local journald breadcrumb — free, no Better Stack quota (deliberately NOT in the Vector
# SYSLOG_IDENTIFIER allowlist; Better Stack delivery is the direct curl below, not via Vector).
logger -t SOLEUR_FRESH_BOOT_READY "$LINE" 2>/dev/null || true
# (1) Better Stack Logs direct-curl — best-effort, gated on BOTH creds (an unprovisioned host
# degrades to Sentry-only, never aborts). Double-post mirrors web-private-nic-guard.
# Token: prefer an injected env var, else fetch from Doppler HERE (baked -> 0 user_data; mirrors the
# soleur-boot-emit baked-DSN + doppler-fallback shape). `|| true` so a doppler hiccup never aborts.
TOKEN="${BETTERSTACK_LOGS_TOKEN:-}"
[ -n "$TOKEN" ] || TOKEN=$(doppler secrets get BETTERSTACK_LOGS_TOKEN --plain --project soleur --config prd 2>/dev/null || true)
INGEST_URL="${BETTERSTACK_INGEST_URL:-}"
if [ -n "$TOKEN" ] && [ -n "$INGEST_URL" ]; then
  post() { curl -fsS -m 10 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$INGEST_URL" --data-raw "{\"message\":\"$LINE\"}" >/dev/null 2>&1; }
  post || post || echo "[fresh-boot-ready] Better Stack egress FAILED: $LINE" >&2
fi
# (2) Sentry — always. ready -> info breadcrumb; not-ready -> fatal (the stage names the unmet field).
if [ "$READY" = 1 ]; then
  soleur-boot-emit fresh_boot_ready info
else
  soleur-boot-emit "fresh_boot_not_ready_$REASON" fatal
fi
exit 0
FRESHREADYEOF
chmod 0755 /usr/local/bin/soleur-fresh-boot-ready

# Sentinel LAST: extraction + install proven complete. The terminal `docker run` block gates
# on this file; without it the host poweroffs (fail-closed) instead of serving with an
# unconfigured egress firewall / missing deploy scripts.
trap - EXIT
: > /run/soleur-hostscripts.ok
