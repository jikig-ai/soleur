#!/usr/bin/env bash
set -euo pipefail

# Observability probe guard for the web-2 fresh-boot blind spot (#6090).
#
# CONTEXT: web-2 never completes a fresh boot — cloud-init dies SILENTLY after the
# seed-extract, before :9000 binds. The #6076 seed-pull fix made the seed BLOCK
# observable (baked ${sentry_dsn} on_err); this PR extends that observability across
# the whole POST-seed sequence (bootstrap.sh completion + the untrapped downstream
# cloud-init region) so ONE recreate names the last-reached stage in Sentry.
#
# Load-bearing additions this guard protects:
#   - baked-DSN preference in bootstrap.sh emit path (survives a broken doppler stage)
#   - a single `bootstrap_complete` breadcrumb (distinguishes "died IN bootstrap" from
#     "bootstrap completed, died downstream")
#   - a baked `soleur-boot-emit` written by bootstrap.sh for the downstream region
#     (zero user_data cost; note the 32,768-byte cap applies to the base64gzip render, not
#     the raw file — `gzip -9 -c cloud-init.yml | base64 -w0 | wc -c` is ~17 KB, so there is
#     ~15 KB of real headroom post-#6090; the old "~0.4 KB" figure predates the gzip wrap)
#   - READINESS GATES (cloudflared_ready / webhook_bound) — the ONLY detector for an
#     async systemd-service death (enable returns 0, service never binds :9000)
#   - H3 fix: restore `set +e` after the extraction block so its `set -e` no longer
#     LEAKS into the bare downstream apt/cloudflared region (cloud-init runs runcmd as
#     ONE /bin/sh; the leak + disarmed trap = a silent whole-runcmd abort = the symptom)
#   - EU Sentry data-plane (de.sentry.io) in the recreate workflow's auto-read
#   - byte-equality lockstep of every emit `message` against the workflow QUERY

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$DIR/soleur-host-bootstrap.sh"
CI="$DIR/cloud-init.yml"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

# Deliberately-nonzero grep inside a command substitution must not trip `set -e`
# (accumulate-then-exit foot-gun): the trailing `|| true` keeps a no-match empty.
line_of() { { grep -nF -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1; } || true; }

# ── AC1 (B): cosign ENFORCE is not on the fresh-boot path (documentation guard) ──
# The default is warn; no repo site sets enforce outside a test; cosign verify is
# absent from cloud-init. (A regression that wired enforce into cloud-init would
# reintroduce the exact silent-abort class this PR investigates.)
if grep -qE 'IMAGE_VERIFY_MODE:-warn' "$DIR/ci-deploy.sh"; then
  ok "AC1: IMAGE_VERIFY_MODE default is warn (cosign ENFORCE not live)"
else
  no "AC1: expected IMAGE_VERIFY_MODE:-warn default in ci-deploy.sh"
fi
# #6122: match a cosign INVOCATION, not the word in a comment. cloud-init.yml's
# daemon.json block documents "cosign digest-pinning is the integrity guard, not TLS"
# (explaining why plain-HTTP zot is safe) — that comment is documentation, not a call.
# Exclude comment lines so the guard tracks the real invariant (no cosign VERIFY runs
# on the fresh-boot path — it lives only in ci-deploy.sh).
if grep -E 'cosign' "$CI" | grep -qvE '^[[:space:]]*#'; then
  no "AC1: cloud-init.yml must NOT invoke cosign (verify lives only in ci-deploy.sh)"
else
  ok "AC1: no cosign call in the fresh-boot cloud-init sequence"
fi

# ── AC2: cloud-init passes the baked DSN into the bootstrap invocation ──
# shellcheck disable=SC2016
if grep -qE "SOLEUR_SENTRY_DSN='\\\$\{sentry_dsn\}'" "$CI"; then
  ok "AC2: cloud-init passes SOLEUR_SENTRY_DSN='\${sentry_dsn}' to bootstrap"
else
  no "AC2: bootstrap invocation must pass SOLEUR_SENTRY_DSN='\${sentry_dsn}' (item A)"
fi

# ── AC3: bootstrap emit path prefers the baked DSN before any doppler fetch ──
# One shared _sentry_emit resolves DSN preferring SOLEUR_SENTRY_DSN; emit_fail and
# ghcr_login_warn both route through it.
if grep -qE '\$\{SOLEUR_SENTRY_DSN:-' "$BOOT"; then
  ok "AC3: bootstrap resolves DSN preferring \${SOLEUR_SENTRY_DSN:-<doppler>}"
else
  no "AC3: bootstrap must prefer \${SOLEUR_SENTRY_DSN:-...} before doppler secrets get"
fi
if grep -qE '_sentry_emit' "$BOOT"; then
  ok "AC3: shared _sentry_emit helper present"
  # The doppler-fallback PREFERENCE (the `DSN="${SOLEUR_SENTRY_DSN:-}"` assignment) must live
  # in exactly one place (_sentry_emit). Note: the baked soleur-boot-emit gets its DSN via a
  # separate sed-splice (`sed …${SOLEUR_SENTRY_DSN:-}…`), which is a value-bake, not a
  # doppler-preference — so it is deliberately excluded by anchoring on the assignment form.
  n_pref=$(grep -cE 'DSN="\$\{SOLEUR_SENTRY_DSN:-\}"' "$BOOT" || true)
  if [ "$n_pref" -eq 1 ]; then
    ok "AC3: doppler-fallback DSN preference lives in exactly one place ($n_pref)"
  else
    no "AC3: DSN preference assignment should appear once (found $n_pref) — factor into _sentry_emit"
  fi
else
  no "AC3: expected a shared _sentry_emit helper used by emit_fail + ghcr_login_warn"
fi

# ── AC4: bootstrap_complete breadcrumb precedes the sentinel ──
bc_ln=$(line_of "$BOOT" 'bootstrap_complete')
# Anchor on the actual sentinel WRITE (`: > …`), not the header comment that also
# names the sentinel path (line ~17).
sentinel_ln=$(line_of "$BOOT" ': > /run/soleur-hostscripts.ok')
if [ -n "$bc_ln" ] && [ -n "$sentinel_ln" ] && [ "$bc_ln" -lt "$sentinel_ln" ]; then
  ok "AC4: bootstrap_complete breadcrumb (line $bc_ln) precedes the sentinel (line $sentinel_ln)"
else
  no "AC4: a bootstrap_complete breadcrumb must precede /run/soleur-hostscripts.ok (bc=$bc_ln sentinel=$sentinel_ln)"
fi

# ── AC5 (fail-open — structural enclosure, NOT per-line || true) ──
# The emit boundary is centralized in _sentry_emit; assert it is enclosed in a
# ( set +e … ) || true subshell so no emit can trip set -e and brick the boot.
if awk '/_sentry_emit\(\)/{f=1} f&&/\( set \+e/{s=1} f&&s&&/\) \|\| true/{print "found"; exit}' "$BOOT" | grep -q found; then
  ok "AC5: _sentry_emit body is enclosed in ( set +e … ) || true (fail-open)"
else
  no "AC5: _sentry_emit must wrap its DSN-resolve+POST in ( set +e … ) || true"
fi
# emit_fail disarms the EXIT trap before emitting (so a slow curl cannot re-enter).
if awk '/^emit_fail\(\)/{f=1} f&&/trap - EXIT/{print "found"; exit}' "$BOOT" | grep -q found; then
  ok "AC5: emit_fail runs trap - EXIT before emitting"
else
  no "AC5: emit_fail must call trap - EXIT first"
fi

# ── H3 (candidate ROOT CAUSE): restore set +e after the extraction block ──
# cloud-init joins runcmd into ONE /bin/sh; the extraction block's `set -e` (never
# restored) LEAKED into the bare downstream apt/cloudflared commands with the on_err
# trap disarmed → a transient non-zero silently aborted the whole runcmd. The fix
# restores the "runcmd is NOT under a top-level set -e" invariant the terminal block
# already assumes.
if grep -qE 'set \+e.*H3' "$CI"; then
  ok "H3: set +e restored after the extraction block (leak scoped)"
else
  no "H3: expected a 'set +e  # H3 …' restoring errexit-off after the extraction block"
fi
# Non-vacuity: the set +e must appear AFTER the extraction's rm -rf "$SEED" and
# BEFORE the bare cloudflared apt install.
rm_ln=$(line_of "$CI" 'rm -rf "$SEED"')
h3_ln=$(grep -nE 'set \+e.*H3' "$CI" | head -1 | cut -d: -f1 || true)
apt_ln=$(line_of "$CI" 'apt-get install -y cloudflared')
if [ -n "$rm_ln" ] && [ -n "$h3_ln" ] && [ -n "$apt_ln" ] && [ "$rm_ln" -lt "$h3_ln" ] && [ "$h3_ln" -lt "$apt_ln" ]; then
  ok "H3: set +e (line $h3_ln) sits between extraction end ($rm_ln) and cloudflared apt ($apt_ln)"
else
  no "H3: set +e must sit after rm -rf \$SEED ($rm_ln) and before cloudflared apt ($apt_ln); h3=$h3_ln"
fi

# ── AC6 (readiness gates — the load-bearing async-death detector) ──
# The poll logic is BAKED (soleur-wait-ready, authored by bootstrap.sh → 0 user_data, the
# ~0.4 KB cap headroom forbids an inline loop); cloud-init carries only the call-sites, each
# `|| exit 1` so a never-ready service aborts the boot.
if grep -qE 'cat > /usr/local/bin/soleur-wait-ready' "$BOOT" \
   && grep -qE 'systemctl is-active --quiet "\$NAME"' "$BOOT" \
   && grep -qE 'soleur-boot-emit "\$STAGE" fatal' "$BOOT"; then
  ok "AC6: soleur-wait-ready baked with a bounded poll + fatal-on-timeout"
else
  no "AC6: bootstrap.sh must bake soleur-wait-ready (poll + soleur-boot-emit <stage> fatal + exit 1)"
fi
if grep -qE 'soleur-wait-ready service cloudflared cloudflared_ready \|\| exit 1' "$CI"; then
  ok "AC6: cloud-init calls the cloudflared_ready gate (|| exit 1 aborts boot on timeout)"
else
  no "AC6: cloud-init must call soleur-wait-ready service cloudflared cloudflared_ready || exit 1"
fi
# webhook_bound: the :9000 bind gate — the load-bearing detector for the primary symptom.
if grep -qE 'soleur-wait-ready port 9000 webhook_bound \|\| exit 1' "$CI"; then
  ok "AC6: cloud-init calls the webhook_bound :9000 gate (|| exit 1 aborts boot on timeout)"
else
  no "AC6: cloud-init must call soleur-wait-ready port 9000 webhook_bound || exit 1"
fi

# ── AC6b (no tolerance inversion + composite trap) ──
# Bare currently-tolerated commands keep their disposition (the /mnt/data mount stays survivable;
# the cloudflared apt lines are NOT wrapped in a fresh set -e + exit 1 block).
#
# #6604 RE-POINT (Q6/C10): the /mnt/data mount was pinned from the ambiguous scsi-0HC_Volume_*
# glob to the stable by-id device (once the LUKS volume attaches the glob binds the wrong device).
# The survivability this AC protects is NOT inverted — it is STRENGTHENED: it moved from the
# single runcmd `|| true` into `nofail` in the fstab line, which survives EVERY boot (not just the
# one runcmd pass), and the runcmd mount chain STILL ends non-fatal (`|| soleur-boot-emit … || true`,
# a pageable-but-survivable degrade). Assert (a) the bare-glob mount is GONE, (b) the mount is
# by-id-pinned and still ends `|| true`, (c) fstab carries `nofail`. Anchored on the pin construct
# + `nofail`, not a bare token (cq-assert-anchor-not-bare-token).
if grep -qE 'mount /dev/disk/by-id/scsi-0HC_Volume_\* /mnt/data' "$CI"; then
  no "AC6b: the ambiguous scsi-0HC_Volume_* glob mount for /mnt/data must be REMOVED (#6604 pin by-id)"
elif grep -qE 'mount /dev/disk/by-id/scsi-0HC_Volume_\$\{workspaces_volume_id\} /mnt/data \|\| soleur-boot-emit workspaces_mount fatal \|\| true' "$CI" \
  && grep -qE 'scsi-0HC_Volume_\$\{workspaces_volume_id\} /mnt/data ext4 defaults,nofail ' "$CI"; then
  ok "AC6b: /mnt/data mount pinned by-id + fstab nofail; survivability strengthened, not inverted"
else
  no "AC6b: /mnt/data mount must be by-id-pinned, end '|| true', and carry fstab 'nofail' (survivable, not fatal)"
fi
# plugin_seed + inngest keep a COMPOSITE trap that still calls cleanup.
n_comp=$(grep -cE "trap 'rc=\\\$\?; cleanup;" "$CI" || true)
if [ "${n_comp:-0}" -ge 2 ]; then
  ok "AC6b: plugin_seed + inngest use composite traps that still call cleanup ($n_comp)"
else
  no "AC6b: plugin_seed/inngest must use 'trap \"rc=\$?; cleanup; …\" EXIT' (found $n_comp, need >=2)"
fi

# ── AC7 (byte cap): the downstream emitter is written ONCE (baked), not duplicated ──
# soleur-boot-emit is authored by bootstrap.sh (baked → 0 user_data); cloud-init only
# CALLS it. A duplicated ~20-line emit body per block would blow the cap.
if grep -qE 'cat > /usr/local/bin/soleur-boot-emit' "$BOOT"; then
  ok "AC7: soleur-boot-emit is written once by bootstrap.sh (baked, 0 user_data body)"
else
  no "AC7: bootstrap.sh must author /usr/local/bin/soleur-boot-emit once (baked)"
fi
# cloud-init must NOT contain the emit body (no cat-of-emitter, no inline curl store).
if grep -qE 'cat > /usr/local/bin/soleur-boot-emit' "$CI"; then
  no "AC7: cloud-init must not re-author the emitter (bake it in bootstrap.sh instead)"
else
  ok "AC7: cloud-init.yml carries only soleur-boot-emit CALL sites (no duplicated body)"
fi

# ── CAPABILITY LOST 2026-07-20 (#6575) — carried forward, not dropped ──────────
# AC8 / AC8b / AC13 / AC14 / AC16 asserted against the `web_2_recreate` job in
# apply-web-platform-infra.yml. That job was deleted with the web-2 dispatch sweep,
# and it was the ONLY consumer of $WF in this file — so those five assertions had no
# subject left and were removed rather than left to pass vacuously.
#
# What they enforced was NEVER web-2-specific, and is NOT re-implemented anywhere yet:
#   AC14  `SENTRY_DSN` must be non-empty in Doppler prd_terraform BEFORE a host is
#         created. The pre-extraction boot stages depend SOLELY on the baked
#         ${sentry_dsn} (doppler is not installed yet, so its fallback is dead), so an
#         empty DSN means a fresh host boots DARK — no telemetry, no page, no signal.
#   AC8/AC8b/AC13/AC16  the fresh-host Sentry surfacing step: EU host (de.sentry.io),
#         `if: always()`, token from Doppler, client-side regex filter (the events
#         endpoint ignores `message:` queries and returns 0).
#
# There is no surviving automated host-create path to move them to — every route
# HALTs, and building one is #6730's scope. So the requirement is carried in two
# places instead: the operator pinned-image chain in the host_creates HALT, and
# ADR-128, which makes both a MUST for #6730's birth path. Re-add assertions here
# the moment that path exists.
# ------------------------------------------------------------------------------

# ── AC8c (transport parity for the BAKED emitter) ──
# The DSN-parse + store-endpoint transport now exists in THREE copies inside bootstrap.sh:
# _sentry_emit (6-space) and the baked soleur-boot-emit body (heredoc, different indent).
# cron-egress-enforce-probe.test.sh's parity guard only covers the 6-space copy, so a
# de.sentry.io-style DSN/endpoint migration could leave the baked copy stale → the whole
# downstream region goes dark with every other guard green. Assert each transport construct
# appears in BOTH copies (indentation-agnostic substring; >=2 occurrences in bootstrap.sh).
while IFS= read -r tline; do
  [ -z "$tline" ] && continue
  cnt=$(grep -cF -- "$tline" "$BOOT" || true)
  if [ "${cnt:-0}" -ge 2 ]; then
    ok "AC8c: transport shared by _sentry_emit + baked soleur-boot-emit: $(printf '%.38s' "$tline")…"
  else
    no "AC8c: transport drift — '$tline' appears ${cnt}× in bootstrap.sh (need >=2: both copies)"
  fi
done <<'TRANSPORT'
sed -E 's#https://([^@]+)@.*#\1#'
sed -E 's#https://[^@]+@([^/]+)/.*#\1#'
curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/"
X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY
TRANSPORT

# ── AC9 (stage-name coverage): the terminal healthy-boot breadcrumb is name-anchored ──
# The workflow summary advertises cloud_init_complete as the expected last-reached stage; a
# typo would pass every structural guard while making the healthy-boot signal unqueryable.
if grep -qE 'soleur-boot-emit cloud_init_complete info' "$CI"; then
  ok "AC9: terminal cloud_init_complete breadcrumb present (healthy-boot last-reached signal)"
else
  no "AC9: cloud-init must emit 'soleur-boot-emit cloud_init_complete info' after the egress probe"
fi

# ── AC10 (inngest trap disarmed): the composite trap must not linger into the terminal block ──
# Without a trailing `trap - EXIT`, the inngest composite trap stays armed through the
# trap-less terminal block and mislabels a doppler_download/docker_run failure as
# stage=inngest_bootstrap — defeating the "name the exact stage" deliverable.
if awk '/soleur-boot-emit inngest_bootstrap fatal/{f=1} f&&/trap - EXIT/{print "y"; exit}' "$CI" | grep -q y; then
  ok "AC10: inngest composite trap is disarmed (trap - EXIT) before the terminal block"
else
  no "AC10: inngest block must 'trap - EXIT' after its composite trap (else terminal failures mislabel)"
fi

# ── AC11 (webhook checksum fail-closed independent of the H3 set +e) ──
# The signed-release binary's sha256sum must abort on mismatch even though H3 restored
# set +e for the region (a mismatch must not install an unverified binary).
if awk '/sha256sum -c -/{if (/webhook_checksum|exit 1/) {print "y"; exit}}' "$CI" | grep -q y; then
  ok "AC11: webhook checksum is fail-closed (|| exit 1) independent of the H3 set +e"
else
  no "AC11: webhook 'sha256sum -c -' must be '|| { … fatal; exit 1; }' (H3 set +e un-gates it otherwise)"
fi

# ── AC12 (#6090 follow-up): the fatal-emit trap covers the PRE-extraction install region ──
# recreate 28805034101 died with ZERO emits + :9000 unbound while every post-extraction guard
# was green — because on_err was defined/armed only inside the extraction block, leaving the
# package-audit/doppler/docker install region (which runs under the leaked `set -e`) a blind
# spot. The fix moves on_err to the TOP of runcmd and bumps STAGE per install step. Guard that:
#   (a) on_err is armed BEFORE the doppler download (early coverage), and
#   (b) on_err is defined exactly ONCE (moved, not duplicated — no transport drift / no bytes).
armln=$(grep -nE '^\s*trap on_err EXIT' "$CI" | head -1 | cut -d: -f1 || true)
dopplerln=$(line_of "$CI" 'tar xzf /tmp/doppler.tar.gz')
if [ -n "$armln" ] && [ -n "$dopplerln" ] && [ "$armln" -lt "$dopplerln" ]; then
  ok "AC12: on_err trap armed (line $armln) BEFORE the doppler install ($dopplerln) — pre-extraction covered"
else
  no "AC12: 'trap on_err EXIT' must precede the doppler install (arm=$armln doppler=$dopplerln); the install region is the blind spot"
fi
n_onerr=$(grep -cE '^\s*on_err\(\) \{' "$CI" || true)
if [ "${n_onerr:-0}" -eq 1 ]; then
  ok "AC12: on_err defined exactly once in cloud-init ($n_onerr) — moved to the top, not duplicated"
else
  no "AC12: on_err must be defined exactly once (found $n_onerr) — a second copy drifts + burns user_data bytes"
fi
# Per-step stage names so the fatal points at the exact dying install command.
for st in doppler_dl docker_apt docker_restart; do
  if grep -qE "STAGE=$st\b" "$CI"; then
    ok "AC12: install region bumps STAGE=$st (fatal names the exact command)"
  else
    no "AC12: cloud-init must set STAGE=$st in the pre-extraction install region"
  fi
done


# ── AC15 (#6090): earliest bootcmd beacon + runcmd_start breadcrumb bracket a pre-runcmd death ──
# recreate 28812931362 (on the merged pre-extraction fix) was STILL fully dark — web-2 emits
# nothing, so the death is BEFORE the top-armed runcmd trap (the cloud-init packages:/config phase)
# or the host has no Sentry egress. A bootcmd beacon (runs before packages:) + a runcmd_start
# breadcrumb (curl guaranteed) bracket it: bootcmd-only = died in packages:; neither = no-egress.
if grep -qE '^bootcmd:' "$CI" && grep -qF 'stage":"bootcmd_start"' "$CI"; then
  ok "AC15: bootcmd beacon present (earliest pre-packages: boot signal)"
else
  no "AC15: cloud-init must emit a bootcmd_start beacon in a bootcmd: block (pre-runcmd bracket)"
fi
if grep -qF '_emit "soleur-cloud-init boot stage" runcmd_start info' "$CI"; then
  ok "AC15: runcmd_start breadcrumb present (curl-guaranteed control vs the best-effort bootcmd beacon)"
else
  no "AC15: cloud-init must emit a runcmd_start breadcrumb right after arming the trap"
fi
# The runcmd transport is written ONCE (_emit), reused by on_err + the breadcrumb (no drift/bytes).
n_emit_def=$(grep -cE '^\s*_emit\(\) \{' "$CI" || true)
if [ "${n_emit_def:-0}" -eq 1 ]; then
  ok "AC15: _emit transport helper defined once in runcmd ($n_emit_def) — shared by on_err + breadcrumb"
else
  no "AC15: _emit must be defined exactly once in cloud-init runcmd (found $n_emit_def)"
fi


# ── AC17 (#6090): package install moved from the opaque config phase into instrumented runcmd ──
# recreate 28819237402 localized web-2's death to the packages:/config phase (bootcmd_start fired,
# runcmd_start never did). apt now runs under the top-armed trap with named stages + timeouts so a
# HANG becomes a NAMED fatal (stage=apt_update/apt_install), and the cloud-config packages: block
# is removed (else the hang would remain in the opaque config phase).
if grep -qE 'STAGE=apt_update' "$CI" && grep -qE 'STAGE=apt_install' "$CI"; then
  ok "AC17: apt runs in instrumented runcmd with named stages (apt_update/apt_install)"
else
  no "AC17: cloud-init must set STAGE=apt_update + STAGE=apt_install in the runcmd apt block"
fi
if grep -qE '^packages:' "$CI"; then
  no "AC17: cloud-config packages: must be REMOVED (a config-phase hang would stay opaque) — install in runcmd"
else
  ok "AC17: no cloud-config packages: block (install moved to instrumented runcmd)"
fi
if grep -qE 'timeout [0-9]+ apt-get update' "$CI" && grep -qE 'timeout [0-9]+ apt-get install' "$CI"; then
  ok "AC17: apt update+install are timeout-wrapped (a HANG becomes a named fatal, not a ~640s poll timeout)"
else
  no "AC17: apt-get update/install must be timeout-wrapped so a hang trips the trap with a named stage"
fi
# Ordering: STAGE must be set BEFORE the hang-capable command (else the fatal mis-attributes), and
# the apt block must sit AFTER the trap arm (else no emit coverage). Guards a silent regression.
su_ln=$(grep -nE '^\s*STAGE=apt_update' "$CI" | head -1 | cut -d: -f1 || true)
auu_ln=$(grep -nE 'timeout [0-9]+ apt-get update' "$CI" | head -1 | cut -d: -f1 || true)
armln2=$(grep -nE '^\s*trap on_err EXIT' "$CI" | head -1 | cut -d: -f1 || true)
if [ -n "$su_ln" ] && [ -n "$auu_ln" ] && [ -n "$armln2" ] && [ "$armln2" -lt "$su_ln" ] && [ "$su_ln" -lt "$auu_ln" ]; then
  ok "AC17: trap-arm ($armln2) < STAGE=apt_update ($su_ln) < apt-get update ($auu_ln) — covered + correctly attributed"
else
  no "AC17: need trap-arm < STAGE=apt_update < apt-get update (arm=$armln2 stage=$su_ln update=$auu_ln)"
fi
# The cloudflare keyring must be fetched BEFORE the first apt-get update — the cloudflare source is
# active from boot (write_files), so an update before the key deterministically fails (missing
# signed-by keyring) and masks the real cause. (Anchor on the curl fetch, not the deb/signed-by line.)
cfk_ln=$(grep -nE 'curl.*cloudflare-main\.gpg' "$CI" | head -1 | cut -d: -f1 || true)
if [ -n "$cfk_ln" ] && [ -n "$auu_ln" ] && [ "$cfk_ln" -lt "$auu_ln" ]; then
  ok "AC17: cloudflare keyring fetched (line $cfk_ln) BEFORE apt-get update ($auu_ln) — no missing-key fatal"
else
  no "AC17: cloudflare-main.gpg must be curl-fetched before the first apt-get update (cfk=$cfk_ln update=$auu_ln)"
fi

# ── AC18 (#6090): ghcr_login/pull capture the host-side error into the emit `detail` tag ──
# recreate 28823498601 reached stage=pull (the private-GHCR seed-image pull). Off-host the token +
# image are valid (HTTP 200), so the failure is host-side and the silent login / bare-pull did not
# capture it. The login writes its outcome + the pull appends its stderr to /run/soleur-stage-detail,
# which _emit surfaces as a `detail` tag so the next recreate names the exact sub-cause.
if grep -qF '"detail":"%s"' "$CI" && grep -qF '/run/soleur-stage-detail' "$CI"; then
  ok "AC18: _emit includes a detail tag sourced from /run/soleur-stage-detail"
else
  no "AC18: _emit must include a detail tag from /run/soleur-stage-detail"
fi
if grep -qE 'ghcr_login_ok|ghcr_login_fail|ghcr_creds_missing' "$CI"; then
  ok "AC18: ghcr_login records its outcome (ok / fail+error / creds_missing) to the detail file"
else
  no "AC18: ghcr_login must write its outcome to /run/soleur-stage-detail"
fi
if grep -qF 'pull_err:' "$CI"; then
  ok "AC18: the pull loop appends the docker pull stderr on final failure (names the pull error)"
else
  no "AC18: the pull loop must capture the docker pull error into /run/soleur-stage-detail"
fi

# ── AC19 (#6090): ghcr_login prefers BAKED creds + hardens the doppler fallback ──
# recreate 28826611336 reached stage=pull with detail=ghcr_creds_missing user=n token=n: doppler
# answered EMPTY at the cold-boot instant, so docker login was skipped → anonymous private pull →
# 401 → boot aborts before :9000. Fix: bake ${ghcr_read_*} (like ${sentry_dsn}) preferred, with a
# HARDENED doppler fallback (timeout 45 + 3-try retry loop). server.tf must pass both vars in.
TF="$DIR/server.tf"
# (1) baked creds preferred (the assignment mirrors the ${sentry_dsn} bake; literal, not expanded)
bake_u=$'GHCR_USER=\'${ghcr_read_user}\''
bake_t=$'GHCR_TOKEN=\'${ghcr_read_token}\''
if grep -qF "$bake_u" "$CI" && grep -qF "$bake_t" "$CI"; then
  ok "AC19: ghcr_login prefers baked \${ghcr_read_user}/\${ghcr_read_token} (survives a cold-boot empty doppler)"
else
  no "AC19: ghcr_login must prefer baked \${ghcr_read_user}/\${ghcr_read_token} before falling back to doppler"
fi
# (2) hardened doppler fallback: timeout 45 + retry loop for BOTH vars, and NO stale timeout-15 form
if grep -qE 'until GHCR_USER=\$\(timeout 45 doppler[^)]*GHCR_READ_USER' "$CI" \
   && grep -qE 'until GHCR_TOKEN=\$\(timeout 45 doppler[^)]*GHCR_READ_TOKEN' "$CI"; then
  ok "AC19: doppler fallback hardened — timeout 45 + until-retry loop for both GHCR_READ_USER and GHCR_READ_TOKEN"
else
  no "AC19: doppler fallback must use 'until VAR=\$(timeout 45 doppler ... GHCR_READ_*)' retry loops"
fi
if grep -qE 'timeout 15 doppler secrets get GHCR_READ' "$CI"; then
  no "AC19: stale un-hardened 'timeout 15 doppler secrets get GHCR_READ_*' fetch still present — must be replaced"
else
  ok "AC19: no stale 'timeout 15 doppler secrets get GHCR_READ_*' fetch remains"
fi
# (3) server.tf passes both baked vars into the web-host cloud-init templatefile map
if grep -qE '^\s*ghcr_read_user\s*=\s*var\.ghcr_read_user' "$TF" \
   && grep -qE '^\s*ghcr_read_token\s*=\s*var\.ghcr_read_token' "$TF"; then
  ok "AC19: server.tf passes ghcr_read_user + ghcr_read_token into the web-host templatefile"
else
  no "AC19: server.tf web-host templatefile map must pass ghcr_read_user + ghcr_read_token (coupled to the cloud-init bake)"
fi

# ── AC20 (#6090): the app-pull GHCR login (ci-deploy ghcr_prelude_and_login) is baked too ──
# The seed-pull fix (AC19) got the host to webhook_bound, but the recreate still RED'd at
# ok_peer_fanout_degraded: ci-deploy's ghcr_prelude_and_login did a bare `doppler secrets get`
# for the app pull + cosign verify, empty on the cold host → docker login skipped → anonymous
# pull → cosign .sig 401 → verify_failed → app never binds :9000. Fix: cloud-init bakes
# /etc/default/soleur-ghcr-read; ghcr_prelude_and_login prefers it, hardened doppler fallback.
CD="$DIR/ci-deploy.sh"
# (1) cloud-init bakes the deploy-readable GHCR cred file with the interpolated vars
if grep -qF 'GHCR_READ_USER=%s\nGHCR_READ_TOKEN=%s' "$CI" \
   && grep -qF '/etc/default/soleur-ghcr-read' "$CI" \
   && grep -qE "'\\\$\{ghcr_read_user\}'[[:space:]]+'\\\$\{ghcr_read_token\}'" "$CI"; then
  ok "AC20: cloud-init bakes /etc/default/soleur-ghcr-read from \${ghcr_read_user}/\${ghcr_read_token}"
else
  no "AC20: cloud-init must bake /etc/default/soleur-ghcr-read with the interpolated GHCR read-creds"
fi
# (2) the baked file is protected like webhook-deploy (deploy:deploy 0600)
if grep -qE 'chmod 600 /etc/default/soleur-ghcr-read' "$CD" 2>/dev/null || grep -qE 'chmod 600 /etc/default/soleur-ghcr-read' "$CI"; then
  ok "AC20: baked GHCR cred file is chmod 600 (deploy-only)"
else
  no "AC20: /etc/default/soleur-ghcr-read must be chmod 600"
fi
# (3) ci-deploy ghcr_prelude_and_login PREFERS the baked file before Doppler
if grep -qF '/etc/default/soleur-ghcr-read' "$CD"; then
  ok "AC20: ci-deploy ghcr_prelude_and_login sources the baked /etc/default/soleur-ghcr-read"
else
  no "AC20: ci-deploy ghcr_prelude_and_login must prefer the baked /etc/default/soleur-ghcr-read"
fi
# (4) the Doppler fallback in ci-deploy is HARDENED (timeout 45 + retry) for both GHCR creds
if grep -qE 'until ghcr_user="?\$\(timeout 45 doppler[^)]*GHCR_READ_USER' "$CD" \
   && grep -qE 'until ghcr_token="?\$\(timeout 45 doppler[^)]*GHCR_READ_TOKEN' "$CD"; then
  ok "AC20: ci-deploy doppler fallback hardened — timeout 45 + until-retry for GHCR_READ_USER and GHCR_READ_TOKEN"
else
  no "AC20: ci-deploy ghcr_prelude_and_login must harden the doppler fallback (timeout 45 + until-retry) for both GHCR creds"
fi
# (5) token hygiene: baked file is deploy-owned + ci-deploy unsets the token from its env/children
if grep -qE 'chown deploy:deploy /etc/default/soleur-ghcr-read' "$CI" \
   && grep -qE 'unset GHCR_READ_TOKEN' "$CD"; then
  ok "AC20: baked file is chown deploy:deploy + ci-deploy unsets GHCR_READ_TOKEN (token not in child env)"
else
  no "AC20: /etc/default/soleur-ghcr-read must be chown deploy:deploy AND ci-deploy must unset GHCR_READ_TOKEN after sourcing"
fi

# ── AC21 (#6090): soleur-host-bootstrap's ghcr_login is baked too (3rd/final GHCR site) ──
# The seed pull (AC19) + app pull (AC20) bakes weren't enough: soleur-host-bootstrap.sh had a
# THIRD unhardened `timeout 15 doppler secrets get GHCR_READ_*` login for the inngest-bootstrap
# image pull. On a cold host it skipped docker login → anonymous inngest pull → /var/lib/inngest
# never created. (The "→ webhook.service 226/NAMESPACE → :9000 unbound → peer fan-out degraded"
# downstream is SEVERED as of #6090 — webhook.service now marks /var/lib/inngest `-`-optional; an
# absent dir no longer wedges the unit. This bake still matters when web_colocate_inngest is ON.)
# Fix: bootstrap prefers the baked /etc/default/soleur-ghcr-read, hardened doppler fallback.
if grep -qF '/etc/default/soleur-ghcr-read' "$BOOT"; then
  ok "AC21: soleur-host-bootstrap ghcr_login prefers the baked /etc/default/soleur-ghcr-read"
else
  no "AC21: soleur-host-bootstrap ghcr_login must prefer the baked /etc/default/soleur-ghcr-read"
fi
if grep -qE 'until GHCR_USER=\$\(timeout 45 doppler[^)]*GHCR_READ_USER' "$BOOT" \
   && grep -qE 'until GHCR_TOKEN=\$\(timeout 45 doppler[^)]*GHCR_READ_TOKEN' "$BOOT"; then
  ok "AC21: soleur-host-bootstrap doppler fallback hardened — timeout 45 + until-retry for both GHCR creds"
else
  no "AC21: soleur-host-bootstrap must harden the doppler fallback (timeout 45 + until-retry) for both GHCR creds"
fi
if grep -qE 'timeout 15 doppler secrets get GHCR_READ' "$BOOT"; then
  no "AC21: stale un-hardened 'timeout 15 doppler secrets get GHCR_READ_*' still present in soleur-host-bootstrap"
else
  ok "AC21: no stale 'timeout 15 doppler secrets get GHCR_READ_*' in soleur-host-bootstrap"
fi
# Pin the Sentry warning emits to the same AC (so a future fetch/emit reorder keeps them):
# both failure branches (credential_absent after retries, auth_denied on login reject) stay loud.
if grep -qF 'ghcr_login_warn credential_absent' "$BOOT" && grep -qF 'ghcr_login_warn auth_denied' "$BOOT"; then
  ok "AC21: bootstrap ghcr_login still emits ghcr_login_warn on both failure branches (no-SSH Sentry warning)"
else
  no "AC21: bootstrap ghcr_login must emit ghcr_login_warn credential_absent + auth_denied on failure"
fi

# ── AC22 (#6396): ungated web-host Vector install (decoupled from web_colocate_inngest) ──
# ADR-100 defaulted web_colocate_inngest=false, so a fresh web host installed NO Vector and
# shipped NO logs. The shipper is now baked into soleur-host-bootstrap.sh (authors
# /usr/local/bin/soleur-vector-install) and invoked fail-open at end-of-cloud-init.
DOCKERFILE="$DIR/../Dockerfile"
VECTOR_TF="$DIR/vector.tf"
VECTOR_TOML="$DIR/vector.toml"
# (1) bootstrap authors the installer exactly once (baked, 0 user_data body)
n_vi=$( (grep -cE 'cat > /usr/local/bin/soleur-vector-install <<' "$BOOT") || true )
if [ "$n_vi" = 1 ]; then
  ok "AC22: soleur-host-bootstrap authors /usr/local/bin/soleur-vector-install once (baked)"
else
  no "AC22: bootstrap must author /usr/local/bin/soleur-vector-install exactly once (found $n_vi)"
fi
# (2) cloud-init call site: fail-open + wall-clock-bounded, at end-of-chain. The outer `timeout`
#     MUST strictly exceed the helper's inner `curl --max-time N` — else a slow cold-boot tarball
#     fetch is SIGTERM-truncated into a silently-absent Better Stack source (perf review P2).
outer_to=$( (grep -oE "timeout [0-9]+ sh -c 'soleur-vector-install'" "$CI" | head -1 | grep -oE '[0-9]+') || true )
inner_ct=$( (grep -oE 'curl -fsSL --max-time [0-9]+' "$BOOT" | head -1 | grep -oE '[0-9]+$') || true )
if grep -qE "timeout [0-9]+ sh -c 'soleur-vector-install' \|\| true" "$CI" \
   && [ -n "$outer_to" ] && [ -n "$inner_ct" ] && [ "$outer_to" -gt "$inner_ct" ]; then
  ok "AC22: cloud-init Vector install is fail-open + timeout-bounded; outer timeout ${outer_to}s > inner curl ${inner_ct}s"
else
  no "AC22: ungated Vector install must be 'timeout N sh -c … || true' with outer N (${outer_to:-?}) > inner curl --max-time (${inner_ct:-?})"
fi
# (3) the call site is the LAST runcmd — AFTER the terminal cloud_init_complete breadcrumb
vi_ln=$( (grep -nE "timeout [0-9]+ sh -c 'soleur-vector-install'" "$CI" | head -1 | cut -d: -f1) || true )
cc_ln=$( (grep -nF 'soleur-boot-emit cloud_init_complete info' "$CI" | head -1 | cut -d: -f1) || true )
if [ -n "$vi_ln" ] && [ -n "$cc_ln" ] && [ "$vi_ln" -gt "$cc_ln" ]; then
  ok "AC22: Vector install runcmd (line $vi_ln) is AFTER cloud_init_complete (line $cc_ln) — end-of-chain"
else
  no "AC22: Vector install must be end-of-chain, after cloud_init_complete (vi=$vi_ln cc=$cc_ln)"
fi
# (4) web-host unit carries EnvironmentFile=/etc/default/webhook-deploy (the DOPPLER_TOKEN source
#     — spec-flow P0; NOT the inngest-only /etc/default/inngest-server), and NO After=inngest
if grep -qE 'EnvironmentFile=/etc/default/webhook-deploy' "$BOOT" \
   && ! awk '/cat > \/usr\/local\/bin\/soleur-vector-install/,/^VINEOF$/' "$BOOT" | grep -qF 'After=network-online.target inngest-server.service'; then
  ok "AC22: web-host vector.service uses EnvironmentFile=/etc/default/webhook-deploy (no inngest coupling)"
else
  no "AC22: web vector.service must carry EnvironmentFile=/etc/default/webhook-deploy (DOPPLER_TOKEN source) + no After=inngest-server.service"
fi
# (4b) ExecStart resolves doppler via `command -v` — NOT a hardcoded /usr/bin/doppler. On the web
#      host doppler is tarball-installed to /usr/local/bin (cloud-init), so a hardcoded /usr/bin
#      path is a 203/EXEC crash-loop → Vector never runs → silent absent source (code-quality P1).
#      Mirrors every sibling web-host unit (cron-egress-firewall.service etc.).
if awk '/cat > "\$UNIT" <</,/^UNITEOF$/' "$BOOT" | grep -qF 'ExecStart=/bin/sh -c ' \
   && awk '/cat > "\$UNIT" <</,/^UNITEOF$/' "$BOOT" | grep -qF 'command -v doppler' \
   && ! awk '/cat > "\$UNIT" <</,/^UNITEOF$/' "$BOOT" | grep -qE '^ExecStart=/usr/bin/doppler'; then
  ok "AC22: web vector.service ExecStart resolves doppler via 'command -v' (no hardcoded /usr/bin/doppler crash-loop)"
else
  no "AC22: web vector.service ExecStart must resolve doppler via 'command -v' (web host has doppler at /usr/local/bin, NOT /usr/bin)"
fi
# (4c) the helper skips when an inngest-OWNED vector.service already exists (deprecated
#      web_colocate_inngest=true host) — mutual exclusion enforced at runtime, not by runcmd order.
if awk '/cat > \/usr\/local\/bin\/soleur-vector-install/,/^VINEOF$/' "$BOOT" \
   | grep -qE "grep -q '/etc/default/inngest-server' \"\\\$UNIT\""; then
  ok "AC22: helper skips install when an inngest-owned vector.service is present (no clobber on colocate hosts)"
else
  no "AC22: soleur-vector-install must skip when /etc/systemd/system/vector.service is inngest-owned (colocate mutual-exclusion)"
fi
# (5) bootstrap stages vector.toml, rendering @@HOST_NAME@@ from the TF-injected SOLEUR_HOST_NAME
if grep -qE 's\|@@HOST_NAME@@\|\$\{SOLEUR_HOST_NAME:-\$\(hostname\)\}\|g' "$BOOT"; then
  ok "AC22: bootstrap renders @@HOST_NAME@@ → \${SOLEUR_HOST_NAME:-\$(hostname)} at staging"
else
  no "AC22: bootstrap must render @@HOST_NAME@@ from SOLEUR_HOST_NAME (per-host discriminator)"
fi
# (6) cloud-init passes SOLEUR_HOST_NAME='${host_name}' to the bootstrap invocation
if grep -qF "SOLEUR_HOST_NAME='\${host_name}'" "$CI"; then
  ok "AC22: cloud-init passes SOLEUR_HOST_NAME='\${host_name}' to bootstrap (TF per-host injection)"
else
  no "AC22: bootstrap invocation must pass SOLEUR_HOST_NAME='\${host_name}'"
fi
# (7) server.tf injects the per-host host_name templatefile var (distinct per host)
if grep -qE 'host_name\s*=\s*each\.key == "web-1" \? "soleur-web-platform" : "soleur-\$\{each\.key\}"' "$TF"; then
  ok "AC22: server.tf injects per-host host_name (web-1→soleur-web-platform, web-N→soleur-web-N)"
else
  no "AC22: server.tf templatefile map must inject a per-host host_name var"
fi
# (8) delivery lockstep: vector.toml in host_script_files AND baked by the Dockerfile COPY
if awk '/host_script_files = \[/,/^  \]/' "$TF" | grep -qF -- '"vector.toml"'; then
  ok "AC22: vector.toml is in server.tf host_script_files"
else
  no "AC22: vector.toml must be in server.tf host_script_files (baked-set membership)"
fi
if grep -qF '/app/infra/vector.toml' "$DOCKERFILE"; then
  ok "AC22: Dockerfile bakes /app/infra/vector.toml (lockstep with host_script_files)"
else
  no "AC22: Dockerfile COPY must include /app/infra/vector.toml (host_scripts_content_hash lockstep)"
fi
# (9) vector.toml carries the @@HOST_NAME@@ sentinel (both transforms), no bare inngest literal
n_hn=$( (grep -cF '.host_name = "@@HOST_NAME@@"' "$VECTOR_TOML") || true )
if [ "$n_hn" = 2 ] && ! grep -qF '.host_name = "soleur-inngest-prd"' "$VECTOR_TOML"; then
  ok "AC22: vector.toml carries @@HOST_NAME@@ at both host_name sites (no bare soleur-inngest-prd)"
else
  no "AC22: vector.toml must carry @@HOST_NAME@@ at both host_name sites (found $n_hn; no bare literal)"
fi
# (10) inngest path renders @@HOST_NAME@@ → soleur-inngest-prd (byte-identical to pre-#6396)
if grep -qF "sed -i 's|@@HOST_NAME@@|soleur-inngest-prd|g'" "$DIR/inngest-bootstrap.sh"; then
  ok "AC22: inngest-bootstrap renders @@HOST_NAME@@ → soleur-inngest-prd (host_name unchanged)"
else
  no "AC22: inngest-bootstrap must render @@HOST_NAME@@ → soleur-inngest-prd on its Vector config"
fi
# (11) version/sha drift guard: the baked installer's pin equals vector.tf locals, with each sha
#      BOUND TO ITS ARCH case-branch (an amd64↔arm64 sha swap must go RED — presence-anywhere
#      would silently pass while the runtime `got=VEC_SHA` check fails on the mis-bound arch;
#      test-design P2). vector.tf `_arm64` line does NOT satisfy the plain `vector_sha256=` awk.
tf_ver=$( (awk -F'"' '/vector_version[[:space:]]*=/ { print $2; exit }' "$VECTOR_TF") || true )
tf_sha=$( (awk -F'"' '/vector_sha256[[:space:]]*=/ { print $2; exit }' "$VECTOR_TF") || true )
tf_sha_arm=$( (awk -F'"' '/vector_sha256_arm64[[:space:]]*=/ { print $2; exit }' "$VECTOR_TF") || true )
if [ -n "$tf_ver" ] && grep -qF "VECTOR_VERSION=\"$tf_ver\"" "$BOOT" \
   && [ -n "$tf_sha" ] && grep -qE "x86_64-unknown-linux-musl\";[[:space:]]*VEC_SHA=\"$tf_sha\"" "$BOOT" \
   && [ -n "$tf_sha_arm" ] && grep -qE "aarch64-unknown-linux-musl\";[[:space:]]*VEC_SHA=\"$tf_sha_arm\"" "$BOOT"; then
  ok "AC22: baked pins match vector.tf, each sha bound to its arch branch (version=$tf_ver; amd64+arm64 sha256)"
else
  no "AC22: baked installer version/sha must equal vector.tf locals with amd64 sha on the x86_64 branch AND arm64 sha on the aarch64 branch"
fi
# (12) hardening-directive parity between the two hand-maintained vector.service heredocs (web in
#      soleur-host-bootstrap.sh, inngest in inngest-bootstrap.sh). A future hardening add to one
#      must propagate to the other — else a dropped ProtectSystem/sandbox line is a silent
#      regression (pattern-recognition P3). Only shared sandbox directives (the intended
#      divergences — After=/EnvironmentFile=/ExecStart — are excluded).
INNGEST_BS="$DIR/inngest-bootstrap.sh"
parity_ok=1
for d in 'Type=simple' 'Restart=on-failure' 'RestartSec=10' 'User=deploy' 'Group=deploy' \
         'SupplementaryGroups=systemd-journal' 'MemoryMax=256M' 'CPUQuota=50%' \
         'ProtectSystem=strict' 'ProtectHome=read-only' 'PrivateTmp=true' \
         'ReadWritePaths=/var/lib/vector' 'ReadOnlyPaths=/etc/vector' 'TimeoutStopSec=30' \
         'WantedBy=multi-user.target'; do
  if ! grep -qF "$d" "$BOOT" || ! grep -qF "$d" "$INNGEST_BS"; then
    parity_ok=0; no "AC22: vector.service hardening directive '$d' missing from web+inngest parity set"
  fi
done
[ "$parity_ok" = 1 ] && ok "AC22: web + inngest vector.service share all 15 sandbox/hardening directives (parity)"

# ── AC23 (#6396): terminal serving-block boot-emit trap (DC-2) ──
# The cloud-init terminal docker-run block had NO named soleur-boot-emit fatal trap: a doppler
# download exit 1 / docker run set -e abort reached only the SSH-only cloud-init-output.log.
# (1) composite EXIT trap armed with a mutable stage + TMPENV-safe cleanup (arm-time TMPENV unset)
# NOTE: cloud-init.yml escapes the shell `${TMPENV:-}` as `$${TMPENV:-}` so terraform's
# templatefile() renders it back to `${TMPENV:-}` on the host (else the render fails). Match the
# SOURCE form (`$$`).
if grep -qE "trap 'rc=\\\$\?; rm -f \"\\\$\\\$\{TMPENV:-\}\"; \[ \"\\\$rc\" = 0 \] \|\| soleur-boot-emit \"\\\$stage\" fatal' EXIT" "$CI"; then
  ok "AC23: terminal-block EXIT trap armed (rm -f \$\${TMPENV:-} + soleur-boot-emit \$stage fatal)"
else
  no "AC23: terminal block must arm 'trap rc=\$?; rm -f \${TMPENV:-}; [ \$rc = 0 ] || soleur-boot-emit \$stage fatal EXIT'"
fi
# (2) armed EARLY: stage=terminal_preamble appears BEFORE the hostscripts poweroff test
tp_ln=$( (grep -nF 'stage=terminal_preamble' "$CI" | head -1 | cut -d: -f1) || true )
hs_ln=$( (grep -nF 'refusing to start app' "$CI" | head -1 | cut -d: -f1) || true )
if [ -n "$tp_ln" ] && [ -n "$hs_ln" ] && [ "$tp_ln" -lt "$hs_ln" ]; then
  ok "AC23: stage=terminal_preamble armed (line $tp_ln) before the hostscripts poweroff (line $hs_ln)"
else
  no "AC23: trap must be armed (stage=terminal_preamble) before the hostscripts poweroff (tp=$tp_ln hs=$hs_ln)"
fi
# (3) explicit hostscripts_incomplete emit BEFORE the poweroff -f (poweroff bypasses the EXIT trap)
if grep -qE 'soleur-boot-emit hostscripts_incomplete fatal;.*poweroff -f' "$CI"; then
  ok "AC23: explicit soleur-boot-emit hostscripts_incomplete fatal precedes the hostscripts poweroff -f"
else
  no "AC23: the hostscripts test must emit hostscripts_incomplete fatal BEFORE its poweroff -f (poweroff skips the trap)"
fi
# (4) mutable stage advances through doppler_download and docker_run
if grep -qF 'stage=doppler_download' "$CI" && grep -qF 'stage=docker_run' "$CI"; then
  ok "AC23: mutable stage advances (doppler_download, docker_run)"
else
  no "AC23: the trap stage must advance through doppler_download + docker_run"
fi
# (5) disarm (trap - EXIT) AFTER docker_run/rm-TMPENV, BEFORE the self-emitting egress probe
dr_ln=$( (grep -nF 'stage=docker_run' "$CI" | head -1 | cut -d: -f1) || true )
# find the disarm that sits between docker_run and the egress probe
ep_ln=$( (grep -nF 'cron-egress-enforce-probe.sh' "$CI" | head -1 | cut -d: -f1) || true )
disarm_ln=$( (awk -v a="$dr_ln" -v b="$ep_ln" 'NR>a && NR<b && /^    trap - EXIT$/ {print NR; exit}' "$CI") || true )
if [ -n "$disarm_ln" ]; then
  ok "AC23: EXIT trap disarmed (line $disarm_ln) between docker_run and the self-emitting egress probe"
else
  no "AC23: the EXIT trap must be disarmed (trap - EXIT) after docker_run and before the egress probe (dr=$dr_ln ep=$ep_ln)"
fi
# (6) all four terminal stages the Sentry issue-alert filters on are EMITTED by this block.
#     Match the EMIT construct, not the bare token (every stage also appears in comment prose, so a
#     bare `grep -qF "$st"` false-passes even if the real emit were deleted — test-design P2).
#     terminal_preamble/doppler_download/docker_run are set via `stage=<x>` (the trap emits $stage);
#     hostscripts_incomplete is the explicit `soleur-boot-emit hostscripts_incomplete fatal`.
for st in terminal_preamble doppler_download docker_run; do
  if grep -qF "stage=$st" "$CI"; then
    ok "AC23: terminal stage '$st' is a real 'stage=' assignment (trap emits it; wired to the Sentry alert)"
  else
    no "AC23: terminal stage '$st' must be a real 'stage=$st' assignment (not comment prose)"
  fi
done
if grep -qF 'soleur-boot-emit hostscripts_incomplete fatal' "$CI"; then
  ok "AC23: terminal stage 'hostscripts_incomplete' is a real soleur-boot-emit call (wired to the Sentry alert)"
else
  no "AC23: 'hostscripts_incomplete' must be a real soleur-boot-emit call (not comment prose)"
fi

echo "=== soleur-host-bootstrap-observability: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
