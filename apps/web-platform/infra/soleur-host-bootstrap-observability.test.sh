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
#     (zero user_data — the 32,768-byte cap has only ~0.4 KB headroom)
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
WF="$DIR/../../../.github/workflows/apply-web-platform-infra.yml"

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
if grep -qE 'cosign' "$CI"; then
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
# Bare currently-tolerated commands keep their disposition (mount keeps || true; the
# cloudflared apt lines are NOT wrapped in a fresh set -e + exit 1 block).
if grep -qE 'mount /dev/disk/by-id/scsi-0HC_Volume_\* /mnt/data \|\| true' "$CI"; then
  ok "AC6b: volume mount retains '|| true' continuation (no inversion)"
else
  no "AC6b: the volume mount must keep '|| true' (do not invert survivable→fatal)"
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

# ── AC8 (lockstep, byte-equality): every emit message is a substring of the WF QUERY ──
QUERY_LINE=$(grep -nE "^\s*QUERY='" "$WF" | head -1 | cut -d: -f1 || true)
if [ -z "$QUERY_LINE" ]; then
  no "AC8: could not locate the QUERY line in $WF"
else
  QUERY=$(sed -n "${QUERY_LINE}p" "$WF")
  # The four canonical emit messages the query must surface (boot-death path).
  for msg in \
    "soleur-hostscript-seed failed" \
    "soleur-host-bootstrap failed" \
    "soleur-host-bootstrap complete" \
    "soleur-cloud-init boot stage"; do
    if printf '%s' "$QUERY" | grep -qF -- "$msg"; then
      ok "AC8: QUERY includes message \"$msg\""
    else
      no "AC8: workflow QUERY missing message \"$msg\" (lockstep drift re-opens the blind spot)"
    fi
  done
  # Bidirectional lockstep: each of the FOUR query literals must actually be emitted at its
  # source site (a rename of ANY emit — new OR legacy — would leave the QUERY listing a dead
  # string that matches nothing → dark query, uncaught). Covers both new and pre-existing.
  for pair in \
    "soleur-hostscript-seed failed:$CI" \
    "soleur-host-bootstrap failed:$BOOT" \
    "soleur-host-bootstrap complete:$BOOT" \
    "soleur-cloud-init boot stage:$BOOT"; do
    msg="${pair%%:*}"; src="${pair##*:}"
    if grep -qF -- "$msg" "$src"; then
      ok "AC8: message \"$msg\" is emitted in $(basename "$src")"
    else
      no "AC8: message \"$msg\" not found in $(basename "$src") (query would match nothing)"
    fi
  done
fi

# ── AC8b (EU data plane + always-run breadcrumb surface) ──
# The auto Sentry-read must hit the EU host (project is jikigai-eu / de.sentry.io);
# a US sentry.io query against an EU project returns empty.
if grep -qE 'https://de\.sentry\.io/api/0/projects/' "$WF"; then
  ok "AC8b: recreate workflow queries the EU Sentry host (de.sentry.io)"
else
  no "AC8b: workflow Sentry endpoint must be de.sentry.io (EU) — a US host returns empty"
fi
if grep -qE 'https://sentry\.io/api/0/projects/' "$WF"; then
  no "AC8b: workflow must NOT query the US sentry.io host (EU-resident project)"
else
  ok "AC8b: no US sentry.io endpoint remains"
fi
# The breadcrumb-trail surface must run on success too (green boot must show the probe fired).
if awk '/Surface fresh-host Sentry/{f=1} f&&/if: always\(\)/{print "y"; exit}' "$WF" | grep -q y; then
  ok "AC8b: fresh-host Sentry surface runs if: always() (green boot shows the probe fired)"
else
  no "AC8b: the Sentry surface step must be if: always() (spec-flow F4)"
fi

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

# ── AC13 (#6090 follow-up): the recreate auto-read sources its Sentry token from Doppler ──
# The GitHub repo secret SENTRY_AUTH_TOKEN is unset, so the surface step self-skipped. It must
# now fetch the token (+org+project) from Doppler prd_terraform like every other step in the job.
if grep -qE 'doppler secrets get SENTRY_AUTH_TOKEN .*-c prd_terraform' "$WF"; then
  ok "AC13: surface step resolves SENTRY_AUTH_TOKEN from Doppler prd_terraform (not the unset repo secret)"
else
  no "AC13: the fresh-host Sentry surface step must fetch SENTRY_AUTH_TOKEN via doppler -c prd_terraform"
fi

# ── AC14 (#6090 P2-1): the recreate asserts the baked DSN is non-empty before -replace ──
# The pre-extraction fresh-boot stages depend SOLELY on the baked ${sentry_dsn} (doppler isn't
# installed yet, so its fallback is dead). An empty SENTRY_DSN (var.sentry_dsn's TF default) would
# silently re-open the zero-emit blind spot. The recreate must fail loudly, not boot dark.
if grep -qE 'SENTRY_DSN is empty in Doppler prd_terraform' "$WF"; then
  ok "AC14: web-2-recreate asserts baked SENTRY_DSN non-empty before -replace (pre-extraction can't go dark)"
else
  no "AC14: the recreate must assert SENTRY_DSN is non-empty before -replace (empty baked DSN = silent pre-extraction blind spot)"
fi

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

# ── AC16 (#6090): the auto-read must NOT use the broken message: query ──
# The /projects/../events/ endpoint ignores `message:"x"` search (returns 0 for events that exist).
# The surface step must derive a client-side regex from QUERY and filter fetched events, NOT pass
# `query=${QUERY}` to the endpoint.
if grep -qF 'query=${QUERY}' "$WF"; then
  no "AC16: surface step still passes the broken message: query to the events endpoint (returns 0)"
else
  ok "AC16: surface step no longer passes the broken message: query to the endpoint"
fi
if grep -qF 'MSG_RE=' "$WF" && grep -qF 'test($re)' "$WF"; then
  ok "AC16: surface step filters recent events client-side via a regex derived from QUERY"
else
  no "AC16: surface step must derive MSG_RE from QUERY and filter events client-side (test(\$re))"
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

echo "=== soleur-host-bootstrap-observability: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
