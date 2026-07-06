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
#     (zero user_data — the 32,768-byte cap has ~1.4 KB headroom)
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
# ~1.4 KB cap headroom forbids an inline loop); cloud-init carries only the call-sites, each
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
  # And each message literal must actually be emitted somewhere in the sources.
  for pair in "soleur-host-bootstrap complete:$BOOT" "soleur-cloud-init boot stage:$BOOT"; do
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

echo "=== soleur-host-bootstrap-observability: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
