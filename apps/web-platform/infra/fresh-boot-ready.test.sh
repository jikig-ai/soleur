#!/usr/bin/env bash
set -uo pipefail

# Fresh-boot readiness marker guard (#6459 / #6538 dark-host fix).
#
# CONTEXT: a fresh web host can complete cloud-init but boot SILENTLY unhealthy (Vector never
# ships, the workspace volume never mounts, the Doppler token never landed) — the #6538
# dark-host class. Phase 1 of feat-web-active-active-iac adds `soleur-fresh-boot-ready`: a
# one-shot, dual-channel readiness marker emitted as the LAST first-boot cloud-init item, AFTER
# the app binds and `soleur-vector-install` runs. Its ABSENCE past a quantified boot-window =
# the host booted dark.
#
# This guard has two halves:
#   (A) STRUCTURAL drift-guards over the AUTHORED helper (soleur-host-bootstrap.sh, baked into
#       the image = 0 user_data), its cloud-init call site, and the server.tf templatefile wiring.
#   (B) BEHAVIORAL: extract the baked helper body and RUN it under stubbed commands + path seams
#       to prove the ready=1 / ready=0-reason=<field> decision actually distinguishes each unmet
#       precondition (a static grep alone would be vacuous — the fixture-cardinality rule).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$DIR/soleur-host-bootstrap.sh"
CI="$DIR/cloud-init.yml"
SRV="$DIR/server.tf"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

# Deliberately-nonzero grep in a command substitution must not trip anything: read FILES directly,
# never `producer | grep -q` (SIGPIPE early-match fail-open under pipefail — 2026-07-18 learning).
# `line_of <file> <literal>` → first 1-indexed line number of an exact-substring match, or empty.
line_of() { { grep -nF -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1; } || true; }

# ─────────────────────────────── (A) STRUCTURAL ───────────────────────────────

# S1: the helper is authored exactly ONCE, baked (cat > /usr/local/bin, not inline user_data).
authored=$({ grep -cE "cat > /usr/local/bin/soleur-fresh-boot-ready <<'" "$BOOT"; } || echo 0)
if [ "$authored" = 1 ]; then
  ok "S1: soleur-host-bootstrap.sh authors soleur-fresh-boot-ready once (baked)"
else
  no "S1: expected exactly 1 baked authoring of soleur-fresh-boot-ready in bootstrap.sh (got $authored)"
fi

# S2: it is made executable.
if grep -qE 'chmod 0755 /usr/local/bin/soleur-fresh-boot-ready' "$BOOT"; then
  ok "S2: soleur-fresh-boot-ready is chmod 0755"
else
  no "S2: missing 'chmod 0755 /usr/local/bin/soleur-fresh-boot-ready'"
fi

# Extract the baked helper body once for the structural field checks + the behavioral run.
HELPER="$(awk "/cat > \/usr\/local\/bin\/soleur-fresh-boot-ready <<'FRESHREADYEOF'/{f=1;next} f&&/^FRESHREADYEOF\$/{f=0} f{print}" "$BOOT")"
if [ -n "$HELPER" ]; then
  ok "S0: extracted the soleur-fresh-boot-ready heredoc body"
else
  no "S0: could not extract the soleur-fresh-boot-ready heredoc body (delimiter FRESHREADYEOF?)"
fi

# S3: DUAL-CHANNEL emit — a local journald breadcrumb (logger) AND a Sentry event (soleur-boot-emit).
if printf '%s\n' "$HELPER" | grep -qE 'logger -t SOLEUR_FRESH_BOOT_READY'; then
  ok "S3a: emits the SOLEUR_FRESH_BOOT_READY journald breadcrumb via logger -t"
else
  no "S3a: helper must 'logger -t SOLEUR_FRESH_BOOT_READY' (local journald breadcrumb)"
fi
if printf '%s\n' "$HELPER" | grep -qE 'soleur-boot-emit'; then
  ok "S3b: emits to Sentry via the baked soleur-boot-emit (Vector-independent backup)"
else
  no "S3b: helper must call soleur-boot-emit (always-available Sentry channel)"
fi

# S4: Better Stack delivery is the DIRECT-CURL path (Vector-independent — a marker that shipped
# via Vector would vanish exactly when Vector is dark, defeating the dark-host diagnostic), and is
# best-effort: guarded on BOTH creds being present so an unprovisioned host degrades, never aborts.
if printf '%s\n' "$HELPER" | grep -qE 'curl -fsS'; then
  ok "S4a: Better Stack delivery uses direct curl -fsS (Vector-independent)"
else
  no "S4a: helper must post to Better Stack via curl -fsS (not through Vector)"
fi
if printf '%s\n' "$HELPER" | grep -qE 'BETTERSTACK_LOGS_TOKEN' && printf '%s\n' "$HELPER" | grep -qE 'BETTERSTACK_INGEST_URL'; then
  ok "S4b: reads BETTERSTACK_LOGS_TOKEN + BETTERSTACK_INGEST_URL from env"
else
  no "S4b: helper must read BETTERSTACK_LOGS_TOKEN and BETTERSTACK_INGEST_URL"
fi
# best-effort guard: the curl must be gated on non-empty creds (no hard failure when unprovisioned).
if printf '%s\n' "$HELPER" | grep -qE '\[ -n "\$(BS_?)?TOKEN' || printf '%s\n' "$HELPER" | grep -qE '\[ -n "\$TOKEN" \] && \[ -n "\$INGEST_URL" \]'; then
  ok "S4c: Better Stack post is gated on non-empty creds (best-effort, degrades gracefully)"
else
  no "S4c: the curl post must be guarded by a non-empty-creds test (best-effort)"
fi

# S5: the boot-window timeout is a QUANTIFIED integer (absence-detection deadline).
win_line="$(printf '%s\n' "$HELPER" | grep -oE 'SOLEUR_FRESH_BOOT_WINDOW_SECONDS=[0-9]+' | head -1)"
win_val="${win_line##*=}"
if printf '%s' "$win_val" | grep -qE '^[0-9]+$' && [ "${win_val:-0}" -ge 60 ]; then
  ok "S5: SOLEUR_FRESH_BOOT_WINDOW_SECONDS is a quantified integer ($win_val s)"
else
  no "S5: expected a quantified integer SOLEUR_FRESH_BOOT_WINDOW_SECONDS>=60 (got '${win_val:-}')"
fi

# S6: the emitted LINE carries the full readiness field set (parseable marker).
missing=""
for field in "SOLEUR_FRESH_BOOT_READY ready=" "stage=cloud_init_complete" "token=" "vector=" "volume=" "luks=" "reason=" "boot_window_s="; do
  printf '%s\n' "$HELPER" | grep -qF -- "$field" || missing="$missing '$field'"
done
if [ -z "$missing" ]; then
  ok "S6: the marker LINE carries ready/stage/token/vector/volume/luks/reason/boot_window_s"
else
  no "S6: marker LINE missing field(s):$missing"
fi

# S7: call site invokes the marker, and it is AFTER soleur-vector-install (so vector= is truthful).
if grep -qE 'soleur-fresh-boot-ready' "$CI"; then
  ok "S7a: cloud-init.yml invokes soleur-fresh-boot-ready"
  ln_marker="$(line_of "$CI" 'soleur-fresh-boot-ready')"
  ln_vector="$(line_of "$CI" 'soleur-vector-install')"
  if [ -n "$ln_marker" ] && [ -n "$ln_vector" ] && [ "$ln_marker" -gt "$ln_vector" ]; then
    ok "S7b: marker call (line $ln_marker) runs AFTER soleur-vector-install (line $ln_vector)"
  else
    no "S7b: marker call must run AFTER soleur-vector-install (marker=$ln_marker vector=$ln_vector)"
  fi
else
  no "S7a: cloud-init.yml must invoke soleur-fresh-boot-ready"
fi

# S8: the token is fetched from Doppler INSIDE the baked helper (0 user_data, no hardcoded token),
# and the call site never aborts the boot.
if printf '%s\n' "$HELPER" | grep -qE 'doppler secrets get BETTERSTACK_LOGS_TOKEN'; then
  ok "S8a: baked helper sources BETTERSTACK_LOGS_TOKEN from Doppler (0 user_data, no hardcoded token)"
else
  no "S8a: helper must fetch BETTERSTACK_LOGS_TOKEN via 'doppler secrets get' (baked)"
fi
# the marker is observability, not a gate — the call site must not let it abort the runcmd.
ci_marker_region="$(awk '/soleur-fresh-boot-ready/{print} ' "$CI")"
if printf '%s\n' "$ci_marker_region" | grep -qE '\|\| true'; then
  ok "S8b: marker invocation is '|| true' (never aborts the boot)"
else
  no "S8b: the soleur-fresh-boot-ready call site must be suffixed '|| true'"
fi

# S9: server.tf passes betterstack_ingest_url into the cloud-init templatefile map.
if grep -qE 'betterstack_ingest_url[[:space:]]*=[[:space:]]*local\.betterstack_logs_ingest_url' "$SRV"; then
  ok "S9: server.tf wires betterstack_ingest_url = local.betterstack_logs_ingest_url into cloud-init"
else
  no "S9: server.tf must pass betterstack_ingest_url = local.betterstack_logs_ingest_url to templatefile()"
fi

# S10: NO ssh anywhere in the new readiness surface (discoverability_test has NO ssh — plan 1.2).
if printf '%s\n' "$HELPER" | grep -qE '(^|[^[:alnum:]])ssh '; then
  no "S10: the fresh-boot readiness helper must not invoke ssh"
else
  ok "S10: no ssh in the fresh-boot readiness helper"
fi

# S11: the helper always exits 0 (pure observability marker — never poweroffs a running host).
if printf '%s\n' "$HELPER" | grep -qE '^exit 0$'; then
  ok "S11: helper ends 'exit 0' (observability marker, not a gate)"
else
  no "S11: helper must end with 'exit 0' (always-0 like soleur-boot-emit)"
fi

# ─────────────────────────────── (B) BEHAVIORAL ───────────────────────────────
# Run the extracted helper under stubbed commands + path seams. Each case flips ONE precondition
# and asserts the resulting ready=/reason= — proving the decision is attributable to that field.

run_case() { # run_case <label> <expect-substring> <env-assignments...>
  local label="$1"; local expect="$2"; shift 2
  local sb; sb="$(mktemp -d -t fbr-case.XXXXXXXX)"
  local cap="$sb/logger.out"
  # stub bin dir on PATH
  mkdir -p "$sb/bin"
  # logger stub: capture the emitted LINE (our canonical observation).
  cat > "$sb/bin/logger" <<STUB
#!/bin/sh
# drop the '-t <tag>' prefix; record the message body
while [ "\$1" = "-t" ] || [ "\$1" = "-p" ]; do shift 2; done
printf '%s\n' "\$*" >> "$cap"
STUB
  # soleur-boot-emit stub: record it fired (Sentry channel), always 0.
  printf '#!/bin/sh\nprintf "boot-emit %%s\\n" "$*" >> "%s"\nexit 0\n' "$cap" > "$sb/bin/soleur-boot-emit"
  # mountpoint stub: 0 iff FBR_MOUNTED=1
  printf '#!/bin/sh\n[ "${FBR_MOUNTED:-0}" = 1 ]\n' > "$sb/bin/mountpoint"
  # systemctl stub: is-active vector → 0 iff FBR_VECTOR_ACTIVE=1
  printf '#!/bin/sh\n[ "${FBR_VECTOR_ACTIVE:-0}" = 1 ]\n' > "$sb/bin/systemctl"
  # curl stub: no-op success (creds are left unset in behavioral cases, so it should not run)
  printf '#!/bin/sh\nexit 0\n' > "$sb/bin/curl"
  # doppler stub: the helper's token fallback runs when BETTERSTACK_LOGS_TOKEN is unset; return empty.
  printf '#!/bin/sh\nexit 0\n' > "$sb/bin/doppler"
  # vector binary presence toggled by FBR_VECTOR_BIN
  if [ "${FBR_VECTOR_BIN:-0}" = 1 ]; then printf '#!/bin/sh\nexit 0\n' > "$sb/bin/vector"; fi
  chmod +x "$sb/bin/"*
  # seams: webhook env file + luks mapper path (absolute in prod, redirected here)
  local envfile="$sb/webhook-deploy"; local mapper="$sb/mapper-absent"
  [ "${FBR_TOKEN:-0}" = 1 ] && printf 'DOPPLER_TOKEN=dp.st.deadbeef\n' > "$envfile" || : > "$envfile"
  [ "${FBR_LUKS:-0}" = 1 ] && { mapper="$sb/mapper-present"; : > "$mapper"; }
  # run the extracted helper with the seams + stub PATH
  ( cd "$sb"
    PATH="$sb/bin:$PATH" \
    WEBHOOK_ENV_FILE="$envfile" WORKSPACES_MOUNT="/whatever" LUKS_MAPPER="$mapper" \
    FBR_MOUNTED="${FBR_MOUNTED:-0}" FBR_VECTOR_ACTIVE="${FBR_VECTOR_ACTIVE:-0}" \
    sh -c "$HELPER" >/dev/null 2>&1 )
  local got; got="$(cat "$cap" 2>/dev/null | grep -F 'SOLEUR_FRESH_BOOT_READY' | head -1)"
  if printf '%s' "$got" | grep -qF -- "$expect"; then
    ok "B: $label → '$expect'"
  else
    no "B: $label → expected '$expect', got: ${got:-<no marker emitted>}"
  fi
  rm -rf "$sb"
}

# B1: everything satisfied → ready=1 reason=none
FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 \
  run_case "all-satisfied" "ready=1 stage=cloud_init_complete token=1 vector=1 volume=1 luks=1 reason=none"
# B2: token absent → ready=0 reason=token   (differs from B1 ONLY in FBR_TOKEN — attributable)
FBR_TOKEN=0 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 \
  run_case "token-absent" "ready=0 stage=cloud_init_complete token=0 vector=1 volume=1 luks=1 reason=token"
# B3: vector inactive → ready=0 reason=vector (the #6538 dark-host signal)
FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=0 FBR_MOUNTED=1 FBR_LUKS=1 \
  run_case "vector-inactive" "ready=0 stage=cloud_init_complete token=1 vector=0 volume=1 luks=1 reason=vector"
# B4: volume unmounted → ready=0 reason=volume
FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=0 FBR_LUKS=1 \
  run_case "volume-unmounted" "ready=0 stage=cloud_init_complete token=1 vector=1 volume=0 luks=1 reason=volume"
# B5: LUKS mapper absent is REPORTED (luks=0) but does NOT gate readiness (web-1 plaintext today).
FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=0 \
  run_case "luks-absent-still-ready" "ready=1 stage=cloud_init_complete token=1 vector=1 volume=1 luks=0 reason=none"

echo "=== fresh-boot-ready: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
