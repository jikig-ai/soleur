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
line_of() { { grep -nF -- "$2" "$1" 2>/dev/null | sed -n '1p' | cut -d: -f1; } || true; }

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
if printf '%s\n' "$HELPER" | grep -cE 'logger -t SOLEUR_FRESH_BOOT_READY' >/dev/null; then
  ok "S3a: emits the SOLEUR_FRESH_BOOT_READY journald breadcrumb via logger -t"
else
  no "S3a: helper must 'logger -t SOLEUR_FRESH_BOOT_READY' (local journald breadcrumb)"
fi
if printf '%s\n' "$HELPER" | grep -cE 'soleur-boot-emit' >/dev/null; then
  ok "S3b: emits to Sentry via the baked soleur-boot-emit (Vector-independent backup)"
else
  no "S3b: helper must call soleur-boot-emit (always-available Sentry channel)"
fi

# S4: Better Stack delivery is the DIRECT-CURL path (Vector-independent — a marker that shipped
# via Vector would vanish exactly when Vector is dark, defeating the dark-host diagnostic), and is
# best-effort: guarded on BOTH creds being present so an unprovisioned host degrades, never aborts.
# The curl is transport-confined (#7797): `--disable` first so ~/.curlrc is never parsed, and
# `--noproxy '*'` so a proxy env var cannot redirect the bearer.
if printf '%s\n' "$HELPER" | grep -cF "curl --disable --noproxy '*' -fsS" >/dev/null; then
  ok "S4a: Better Stack delivery uses direct, transport-confined curl -fsS (Vector-independent)"
else
  no "S4a: helper must post to Better Stack via curl --disable --noproxy '*' -fsS (not through Vector)"
fi
# S4d (#9597): the bearer is on curl's stdin config, not its argument list.
if printf '%s\n' "$HELPER" | grep -cF 'Authorization: Bearer' >/dev/null && ! printf '%s\n' "$HELPER" | grep -cF -e '-H "Authorization: Bearer' >/dev/null; then
  ok "S4d: the Better Stack bearer is sent on curl's stdin config channel, never as a -H argv header"
else
  no "S4d: the helper must send the bearer via 'printf header = ... | curl --config -', not -H \"Authorization: Bearer ...\""
fi
# S4d: the bearer goes only to the pinned destination, and the pin equals the Terraform literal
# the web host is rendered with (zot-registry.tf local.betterstack_logs_ingest_url).
TF_INGEST=$(sed -n 's/^[[:space:]]*betterstack_logs_ingest_url[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$DIR/zot-registry.tf" | sed -n '1p')
if [ -n "$TF_INGEST" ] \
  && printf '%s\n' "$HELPER" | grep -cxF "readonly INGEST_URL_PINNED=\"$TF_INGEST\"" >/dev/null \
  && printf '%s\n' "$HELPER" | grep -cF '[ "$INGEST_URL" = "$INGEST_URL_PINNED" ]' >/dev/null; then
  ok "S4d: Better Stack post is gated on the pinned destination ($TF_INGEST)"
else
  no "S4d: helper must pin INGEST_URL to zot-registry.tf's betterstack_logs_ingest_url (got '${TF_INGEST:-unparsed}')"
fi
if printf '%s\n' "$HELPER" | grep -cE 'BETTERSTACK_LOGS_TOKEN' >/dev/null && printf '%s\n' "$HELPER" | grep -cE 'BETTERSTACK_INGEST_URL' >/dev/null; then
  ok "S4b: reads BETTERSTACK_LOGS_TOKEN + BETTERSTACK_INGEST_URL from env"
else
  no "S4b: helper must read BETTERSTACK_LOGS_TOKEN and BETTERSTACK_INGEST_URL"
fi
# best-effort guard: the curl must be gated on non-empty creds (no hard failure when unprovisioned).
if printf '%s\n' "$HELPER" | grep -cE '\[ -n "\$(BS_?)?TOKEN' >/dev/null || printf '%s\n' "$HELPER" | grep -cE '\[ -n "\$TOKEN" \] && \[ -n "\$INGEST_URL" \]' >/dev/null; then
  ok "S4c: Better Stack post is gated on non-empty creds (best-effort, degrades gracefully)"
else
  no "S4c: the curl post must be guarded by a non-empty-creds test (best-effort)"
fi

# S5: the boot-window timeout is a QUANTIFIED integer (absence-detection deadline).
win_line="$(printf '%s\n' "$HELPER" | grep -oE 'SOLEUR_FRESH_BOOT_WINDOW_SECONDS=[0-9]+' | sed -n '1p')"
win_val="${win_line##*=}"
if printf '%s' "$win_val" | grep -cE '^[0-9]+$' >/dev/null && [ "${win_val:-0}" -ge 60 ]; then
  ok "S5: SOLEUR_FRESH_BOOT_WINDOW_SECONDS is a quantified integer ($win_val s)"
else
  no "S5: expected a quantified integer SOLEUR_FRESH_BOOT_WINDOW_SECONDS>=60 (got '${win_val:-}')"
fi

# S6: the emitted LINE carries the full readiness field set (parseable marker).
missing=""
for field in "SOLEUR_FRESH_BOOT_READY ready=" "stage=cloud_init_complete" "token=" "vector=" "volume=" "luks=" "luks_arm=" "escrow=" "boot_id=" "host=" "reason=" "boot_window_s="; do
  printf '%s\n' "$HELPER" | grep -cF -- >/dev/null "$field" || missing="$missing '$field'"
done
if [ -z "$missing" ]; then
  ok "S6: the marker LINE carries ready/stage/token/vector/volume/luks/luks_arm/escrow/boot_id/host/reason/boot_window_s"
else
  no "S6: marker LINE missing field(s):$missing"
fi

# S6b: the bootstrap splices the Terraform host name into the marker, and tolerates it unspliced.
if grep -qF 'sed -i "s|@@SOLEUR_HOST_NAME@@|${SOLEUR_HOST_NAME:-}|" /usr/local/bin/soleur-fresh-boot-ready' "$BOOT" && printf '%s\n' "$HELPER" | grep -qF "HOST='@@SOLEUR_HOST_NAME@@'"; then
  ok "S6b: the readiness marker carries the spliced Terraform host name sentinel and the bootstrap resolves it"
else
  no "S6b: the readiness marker must splice @@SOLEUR_HOST_NAME@@ (the verify leg joins on the exact Terraform name)"
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
if printf '%s\n' "$HELPER" | grep -cE 'doppler secrets get BETTERSTACK_LOGS_TOKEN' >/dev/null; then
  ok "S8a: baked helper sources BETTERSTACK_LOGS_TOKEN from Doppler (0 user_data, no hardcoded token)"
else
  no "S8a: helper must fetch BETTERSTACK_LOGS_TOKEN via 'doppler secrets get' (baked)"
fi
# the marker is observability, not a gate — the call site must not let it abort the runcmd.
ci_marker_region="$(awk '/soleur-fresh-boot-ready/{print} ' "$CI")"
if printf '%s\n' "$ci_marker_region" | grep -cE '\|\| true' >/dev/null; then
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
if printf '%s\n' "$HELPER" | grep -cE '(^|[^[:alnum:]])ssh ' >/dev/null; then
  no "S10: the fresh-boot readiness helper must not invoke ssh"
else
  ok "S10: no ssh in the fresh-boot readiness helper"
fi

# S11: the helper always exits 0 (pure observability marker — never poweroffs a running host).
if printf '%s\n' "$HELPER" | grep -cE '^exit 0$' >/dev/null; then
  ok "S11: helper ends 'exit 0' (observability marker, not a gate)"
else
  no "S11: helper must end with 'exit 0' (always-0 like soleur-boot-emit)"
fi

# ─────────────────────────────── (B) BEHAVIORAL ───────────────────────────────
# Run the extracted helper under stubbed commands + path seams. Each case flips ONE precondition
# and asserts the resulting ready=/reason= row AND the exact Sentry emit sequence (stage + level) —
# proving the decision is attributable to that field and that the page names it.
#
# Every stub REFUSES argv it was not taught (exit 64 + a REFUSED line the case then fails on): a helper
# that points findmnt/mountpoint at `/` or asks systemctl about `docker` is a wrong-target bug the stubs
# must not paper over.

FBR_SCR="$(mktemp -d -t fbr-scr.XXXXXXXX)"  # lint-trap-ownership: ok — one scratch root for the whole suite, removed by the EXIT trap below
trap 'rm -rf "${FBR_SCR:?}"' EXIT
PINNED_URL="$TF_INGEST"
BID="0123abcd-4567-89ab-cdef-0123456789ab"
MUTATION_ROWS=0

# run_helper — the engine. Sets R_ROW R_EMITS R_REFUSED R_ERR R_CURL (globals) and leaves the sandbox at
# $FBR_SCR/case for the detail-file assertions. FBR_HELPER overrides the helper text (mutation rows).
run_helper() {
  local sb="$FBR_SCR/case" cap helper_text
  rm -rf "${sb:?}"; mkdir -p "$sb/bin" "$sb/detail"
  cap="$sb/cap"; : > "$cap"
  helper_text="${FBR_HELPER-$HELPER}"
  cat > "$sb/bin/logger" <<STUB
#!/bin/sh
[ "\$#" -eq 3 ] && [ "\$1" = "-t" ] && [ "\$2" = "SOLEUR_FRESH_BOOT_READY" ] || { echo "REFUSED logger \$*" >> "$cap"; exit 64; }
printf '%s\n' "\$3" >> "$cap"
STUB
  cat > "$sb/bin/soleur-boot-emit" <<STUB
#!/bin/sh
[ "\$#" -eq 2 ] && case "\$2" in info|warning|fatal) : ;; *) false ;; esac || { echo "REFUSED soleur-boot-emit \$*" >> "$cap"; exit 64; }
echo "boot-emit \$1 \$2" >> "$cap"
STUB
  cat > "$sb/bin/mountpoint" <<'STUB'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = "-q" ] && [ "$2" = "/whatever" ] || { echo "REFUSED mountpoint $*" >> "$FBR_CAP"; exit 64; }
[ "${FBR_MOUNTED:-0}" = 1 ]
STUB
  cat > "$sb/bin/systemctl" <<'STUB'
#!/bin/sh
[ "$#" -eq 3 ] && [ "$1" = "is-active" ] && [ "$2" = "--quiet" ] && [ "$3" = "vector" ] || { echo "REFUSED systemctl $*" >> "$FBR_CAP"; exit 64; }
[ "${FBR_VECTOR_ACTIVE:-0}" = 1 ]
STUB
  cat > "$sb/bin/findmnt" <<'STUB'
#!/bin/sh
[ "$#" -eq 3 ] && [ "$1" = "-no" ] && [ "$2" = "SOURCE" ] && [ "$3" = "/whatever" ] || { echo "REFUSED findmnt $*" >> "$FBR_CAP"; exit 64; }
printf '%s\n' "${FBR_MOUNT_SRC:-/dev/sdb}"
STUB
  cat > "$sb/bin/hostname" <<'STUB'
#!/bin/sh
[ "$#" -eq 0 ] || { echo "REFUSED hostname $*" >> "$FBR_CAP"; exit 64; }
printf '%s\n' "${FBR_HOST-soleur-web-2}"
STUB
  cat > "$sb/bin/curl" <<'STUB'
#!/bin/sh
echo "curl $*" >> "$FBR_CAP"
case " $* " in *" --config - "*) cat >> "$FBR_CAP.stdin" ;; esac
exit "${FBR_CURL_RC:-0}"
STUB
  cat > "$sb/bin/doppler" <<'STUB'
#!/bin/sh
[ "$*" = "secrets get BETTERSTACK_LOGS_TOKEN --plain --project soleur --config prd" ] || { echo "REFUSED doppler $*" >> "$FBR_CAP"; exit 64; }
printf '%s' "${FBR_DOPPLER_TOKEN:-}"
STUB
  if [ "${FBR_VECTOR_BIN:-0}" = 1 ]; then printf '#!/bin/sh\nexit 0\n' > "$sb/bin/vector"; fi
  chmod +x "$sb/bin/"*
  local envfile="$sb/webhook-deploy" armfile="$sb/luks-arm" bootid="$sb/boot_id"
  if [ "${FBR_TOKEN:-0}" = 1 ]; then printf 'DOPPLER_TOKEN=dp.st.deadbeef\n' > "$envfile"; else : > "$envfile"; fi
  case "${FBR_ARM:-formatted}" in
    none) : > "$armfile" ;;
    RAW) printf '%s\n' "${FBR_ARM_RAW:-}" > "$armfile" ;;
    *) printf 'luks_arm=%s\nescrow=%s\n' "${FBR_ARM:-formatted}" "${FBR_ESCROW:-ok}" > "$armfile" ;;
  esac
  if [ "${FBR_BOOT_ID-0123ABCD-4567-89ab-cdef-0123456789AB}" != "" ]; then printf '%s\n' "${FBR_BOOT_ID-0123ABCD-4567-89ab-cdef-0123456789AB}" > "$bootid"; fi
  local bs_token="" bs_url=""
  if [ "${FBR_BS:-1}" = 1 ]; then bs_token=tok-synthetic; bs_url="${FBR_BS_URL-$PINNED_URL}"; fi
  [ -n "${FBR_BS_TOKEN-}" ] && bs_token="$FBR_BS_TOKEN"
  local body; body="$( [ -n "${FBR_SPLICE:-}" ] && printf '%s' "$helper_text" | sed "s|@@SOLEUR_HOST_NAME@@|$FBR_SPLICE|" || printf '%s' "$helper_text" )"
  ( cd "$sb" || exit 1
    PATH="$sb/bin:$PATH" FBR_CAP="$cap" \
    WEBHOOK_ENV_FILE="$envfile" WORKSPACES_MOUNT="/whatever" LUKS_MAPPER="/dev/mapper/workspaces" \
    LUKS_ARM_FILE="$armfile" BOOT_ID_FILE="$bootid" SOLEUR_STAGE_DETAIL_DIR="$sb/detail" \
    BETTERSTACK_LOGS_TOKEN="$bs_token" BETTERSTACK_INGEST_URL="$bs_url" \
    FBR_MOUNTED="${FBR_MOUNTED:-0}" FBR_VECTOR_ACTIVE="${FBR_VECTOR_ACTIVE:-0}" \
    FBR_MOUNT_SRC="$([ "${FBR_LUKS:-0}" = 1 ] && echo /dev/mapper/workspaces || echo /dev/sdb)" FBR_HOST="${FBR_HOST-soleur-web-2}" \
    sh -c "$body" >/dev/null 2>"$sb/stderr" )
  R_ROW="$(grep -F 'SOLEUR_FRESH_BOOT_READY' "$cap" | sed -n '1p')"
  R_EMITS="$(sed -n 's/^boot-emit \(.*\)$/\1/p' "$cap" | paste -sd';' -)"
  R_REFUSED="$(grep -F 'REFUSED ' "$cap" | paste -sd';' -)"
  R_CURL="$(grep -c '^curl ' "$cap" || true)"
  R_CURL_ARGV="$(grep '^curl ' "$cap" || true)"
  R_STDIN="$(cat "$cap.stdin" 2>/dev/null || true)"
  R_ERR="$(cat "$sb/stderr" 2>/dev/null)"
}

# detail_of <stage> -> the detail file the helper left for the emitter (empty when none).
detail_of() { cat "$FBR_SCR/case/detail/$1" 2>/dev/null; }

# verdict <label> <ok|no> <detail> — scored once; FBR_QUIET=1 (mutation rows) returns the verdict only.
verdict() {
  if [ "${FBR_QUIET:-0}" = 1 ]; then [ "$2" = ok ]; return; fi
  if [ "$2" = ok ]; then ok "B: $1"; else no "B: $1 — $3"; fi
}

# run_case <label> <row-substring> <expected-emit-sequence>
run_case() {
  local label="$1" expect="$2" emits="$3"
  run_helper
  if [ -n "$R_REFUSED" ]; then verdict "$label" no "a stub refused unexpected argv: $R_REFUSED"; return; fi
  if ! printf '%s' "$R_ROW" | grep -qF -- "$expect"; then verdict "$label" no "row: expected '$expect', got '${R_ROW:-<no marker emitted>}'"; return; fi
  if [ "$R_EMITS" != "$emits" ]; then verdict "$label" no "emits: expected '$emits', got '$R_EMITS'"; return; fi
  verdict "$label (row + emits '$emits')" ok ""
}

# --- The decision table (a healthy Better Stack channel: creds present, pinned URL, curl ok) ---
case_ready()   { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 run_case "all-satisfied" \
  "ready=1 stage=cloud_init_complete token=1 vector=1 volume=1 luks=1 luks_arm=formatted escrow=ok boot_id=$BID host=soleur-web-2 reason=none" "fresh_boot_ready info"; }
case_token()   { FBR_TOKEN=0 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 run_case "token-absent" \
  "ready=0 stage=cloud_init_complete token=0 vector=1 volume=1 luks=1 luks_arm=formatted escrow=ok boot_id=$BID host=soleur-web-2 reason=token" "fresh_boot_not_ready_token fatal"; }
case_vector()  { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=0 FBR_MOUNTED=1 FBR_LUKS=1 run_case "vector-inactive" \
  "ready=0 stage=cloud_init_complete token=1 vector=0 volume=1 luks=1 luks_arm=formatted escrow=ok boot_id=$BID host=soleur-web-2 reason=vector" "fresh_boot_not_ready_vector fatal"; }
case_volume()  { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=0 FBR_LUKS=1 run_case "volume-unmounted" \
  "ready=0 stage=cloud_init_complete token=1 vector=1 volume=0 luks=0 luks_arm=formatted escrow=ok boot_id=$BID host=soleur-web-2 reason=volume" "fresh_boot_not_ready_volume fatal"; }
# luks is GATED (#6931): a mounted volume that is NOT the mapper (the pre-fix plaintext state) is not ready.
case_luks()    { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=0 run_case "plaintext-mount-not-ready" \
  "ready=0 stage=cloud_init_complete token=1 vector=1 volume=1 luks=0 luks_arm=formatted escrow=ok boot_id=$BID host=soleur-web-2 reason=luks" "fresh_boot_not_ready_luks fatal"; }
case_noarm()   { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_ARM=none run_case "no-arm-file" \
  "luks=1 luks_arm=none escrow=none" "fresh_boot_ready info"; }
# A missing off-host header copy is REPORTED, not gated (it pages on its own and fences the soak marker).
case_escrow()  { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_ARM=opened FBR_ESCROW=missing run_case "escrow-missing-still-ready" \
  "ready=1 stage=cloud_init_complete token=1 vector=1 volume=1 luks=1 luks_arm=opened escrow=missing" "fresh_boot_ready info"; }
# An unreadable boot id is reported as unknown, never omitted and never invented.
case_bootid_unreadable() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_BOOT_ID='' run_case "boot-id-unreadable" \
  "boot_id=unknown host=soleur-web-2" "fresh_boot_ready info"; }
case_splice()  { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_HOST='os-name' FBR_SPLICE=soleur-web-2 run_case "spliced-host-wins" \
  "host=soleur-web-2 reason=none" "fresh_boot_ready info"; }
case_hostile() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_HOST='evil ready=1 x' run_case "hostile-hostname-bound" \
  "host=evilready1x reason=none" "fresh_boot_ready info"; }
# Reason PRECEDENCE with two unmet preconditions at once (every case above flips exactly one): the first
# failing field in token > vector > volume > luks order names the reason.
case_prec_tv() { FBR_TOKEN=0 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=0 FBR_MOUNTED=1 FBR_LUKS=1 run_case "token+vector unmet -> reason=token" \
  "token=0 vector=0 volume=1 luks=1 luks_arm=formatted escrow=ok boot_id=$BID host=soleur-web-2 reason=token" "fresh_boot_not_ready_token fatal"; }
case_prec_vv() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=0 FBR_MOUNTED=0 FBR_LUKS=1 run_case "vector+volume unmet -> reason=vector" \
  "token=1 vector=0 volume=0 luks=0 luks_arm=formatted escrow=ok boot_id=$BID host=soleur-web-2 reason=vector" "fresh_boot_not_ready_vector fatal"; }
# The boot id is CHARSET- and LENGTH-bound: non-hex noise is stripped, the rest lower-cased, 36 chars max.
case_bootid_bound() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 \
  FBR_BOOT_ID='ZZ0123ABCD-45;67-89ab-cdef-0123456789AB EXTRA tail' run_case "boot-id-charset-and-length-bound" \
  "boot_id=$BID host=soleur-web-2" "fresh_boot_ready info"; }
# The provisioner's result file is parsed against a CLOSED vocabulary: an off-vocabulary value reads none.
case_arm_vocab() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_ARM=RAW FBR_ARM_RAW=$'luks_arm=evil value\nescrow=fine' run_case "arm-file-off-vocabulary-reads-none" \
  "luks_arm=none escrow=none" "fresh_boot_ready info"; }

case_ready; case_token; case_vector; case_volume; case_luks; case_noarm; case_escrow
case_bootid_unreadable; case_splice; case_hostile
case_prec_tv; case_prec_vv; case_bootid_bound; case_arm_vocab

# The unreadable-boot-id case must also be SILENT on stderr (the redirect has to precede the `<`, else the
# shell reports the open failure before the 2>/dev/null applies).
case_bootid_silent() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_BOOT_ID='' run_helper
  if printf '%s' "$R_ERR" | grep -qF 'No such file'; then verdict "boot-id-unreadable is silent on stderr" no "stderr: $R_ERR"; else verdict "boot-id-unreadable is silent on stderr" ok ""; fi; }
case_bootid_silent

# --- The Better Stack channel: success, skipped (no token / no url / unpinned), failed ---
bs_check() { # <label> <expected-emits> <expected-curl-count> <expected-detail-regex-or-empty> [bearer-token-on-stdin]
  local label="$1" emits="$2" ncurl="$3" detre="$4" btok="${5:-}" det
  run_helper
  det="$(detail_of fresh_boot_ready_bs_egress)"
  if [ -n "$R_REFUSED" ]; then verdict "$label" no "a stub refused unexpected argv: $R_REFUSED"; return; fi
  if [ "$R_EMITS" != "$emits" ]; then verdict "$label" no "emits: expected '$emits', got '$R_EMITS'"; return; fi
  if [ "$R_CURL" != "$ncurl" ]; then verdict "$label" no "curl invocations: expected $ncurl, got $R_CURL"; return; fi
  if [ -z "$detre" ]; then
    if [ -n "$det" ]; then verdict "$label" no "a bs_egress detail was written on a healthy channel: $det"; return; fi
  elif ! printf '%s' "$det" | grep -qE "$detre"; then verdict "$label" no "detail: expected /$detre/, got '$det'"; return; fi
  if [ -n "$btok" ]; then
    # (#9597) the bearer rides curl's stdin config, never its argument list.
    case "$R_CURL_ARGV" in *"$btok"*) verdict "$label" no "the token is on curl's argv: $R_CURL_ARGV"; return ;; esac
    local want="" n=0
    while [ "$n" -lt "$ncurl" ]; do want="${want}${want:+
}header = \"Authorization: Bearer $btok\""; n=$((n + 1)); done
    if [ "$R_STDIN" != "$want" ]; then verdict "$label" no "stdin config: expected $ncurl exact bearer header line(s), got '$R_STDIN'"; return; fi
  fi
  verdict "$label (emits '$emits', curl x$ncurl)" ok ""
}
case_bs_ok()      { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 bs_check "bs: pinned post succeeds -> one curl, no warning, no detail" "fresh_boot_ready info" 1 "" tok-synthetic; }
case_bs_notoken() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_BS=0 bs_check "bs: no token -> skipped, WARNING stage + detail, no curl" "fresh_boot_ready_bs_egress warning;fresh_boot_ready info" 0 "^reason=no_token luks_arm=formatted escrow=ok boot_id=$BID$"; }
case_bs_nourl()   { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_BS_URL='' bs_check "bs: token but no ingest url -> skipped, WARNING stage + detail, no curl" "fresh_boot_ready_bs_egress warning;fresh_boot_ready info" 0 "^reason=no_url luks_arm=formatted escrow=ok boot_id=$BID$"; }
case_bs_unpinned() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_BS_URL='https://attacker.example/' bs_check "bs: unpinned url -> the bearer is NOT sent (no curl), WARNING stage + detail" "fresh_boot_ready_bs_egress warning;fresh_boot_ready info" 0 "^reason=unpinned_url luks_arm=formatted escrow=ok boot_id=$BID$"; }
case_bs_failed()  { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_CURL_RC=22 bs_check "bs: both POST attempts fail -> two curls, WARNING stage + detail" "fresh_boot_ready_bs_egress warning;fresh_boot_ready info" 2 "^reason=post_failed luks_arm=formatted escrow=ok boot_id=$BID$" tok-synthetic; }
# (#9597) A bound token that fails the shape check (space, or a newline carrying an injected config
# directive) is NEVER sent: no curl at all, the WARNING stage names bad_token_shape (not unpinned_url),
# and the marker still exits 0 with its Sentry emit.
case_bs_badshape()  { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_BS_TOKEN='tok with space' bs_check "bs: token fails the shape check (space) -> no curl, WARNING stage reason=bad_token_shape" "fresh_boot_ready_bs_egress warning;fresh_boot_ready info" 0 "^reason=bad_token_shape luks_arm=formatted escrow=ok boot_id=$BID$"; }
case_bs_badshape_nl() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_BS_TOKEN=$'tok\nurl = "https://attacker.example/"' bs_check "bs: token carrying an injected config line (newline) -> no curl, reason=bad_token_shape" "fresh_boot_ready_bs_egress warning;fresh_boot_ready info" 0 "^reason=bad_token_shape luks_arm=formatted escrow=ok boot_id=$BID$"; }
case_bs_ok; case_bs_notoken; case_bs_nourl; case_bs_unpinned; case_bs_failed; case_bs_badshape; case_bs_badshape_nl

# The Sentry twin carries the joinable fields itself, so a dead direct channel loses nothing.
case_detail_ready() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=1 FBR_ARM=opened FBR_ESCROW=missing run_helper
  if [ "$(detail_of fresh_boot_ready)" = "token=1 vector=1 volume=1 luks=1 luks_arm=opened escrow=missing boot_id=$BID" ]; then verdict "ready twin carries luks_arm/escrow/boot_id in its Sentry detail" ok ""; else verdict "ready twin carries luks_arm/escrow/boot_id in its Sentry detail" no "got '$(detail_of fresh_boot_ready)'"; fi; }
case_detail_notready() { FBR_TOKEN=1 FBR_VECTOR_BIN=1 FBR_VECTOR_ACTIVE=1 FBR_MOUNTED=1 FBR_LUKS=0 run_helper
  if [ "$(detail_of fresh_boot_not_ready_luks)" = "token=1 vector=1 volume=1 luks=0 luks_arm=formatted escrow=ok boot_id=$BID" ]; then verdict "not-ready page carries the whole field set in its Sentry detail" ok ""; else verdict "not-ready page carries the whole field set in its Sentry detail" no "got '$(detail_of fresh_boot_not_ready_luks)'"; fi; }
case_detail_ready; case_detail_notready

# --- DEFAULT-PATH CONTRACT. Every case above overrides the seams, so the production defaults were never
# compared to their producers: a drifted default reports `luks_arm=none escrow=none` forever, silently.
# helper_default <text> <VAR> -> the default of `${VAR:-<default>}` in the helper text.
helper_default() { printf '%s\n' "$1" | sed -n "s|.*\\\${$2:-\\([^}]*\\)}.*|\\1|p" | sed -n '1p'; }
PROV="$DIR/workspaces-luks-provision.sh"
case_defaults() {
  local text="${FBR_HELPER-$HELPER}" want_arm want_mapper want_boot got_arm got_mapper got_boot
  want_arm="$(sed -n 's|^RUN_DIR="\${ROOT}\(.*\)"$|\1|p' "$PROV" | sed -n '1p')$(sed -n 's|^ARM_FILE="\$RUN_DIR\(.*\)"$|\1|p' "$PROV" | sed -n '1p')"
  want_mapper="/dev/mapper/$(sed -n 's/^MAPPER_NAME=\([a-z]*\)$/\1/p' "$PROV" | sed -n '1p')"
  want_boot="$(sed -n 's|.*\${LUKS_MONITOR_BOOT_ID_FILE:-\([^}]*\)}.*|\1|p' "$DIR/luks-monitor.sh" | sed -n '1p')"
  got_arm="$(helper_default "$text" LUKS_ARM_FILE)"; got_mapper="$(helper_default "$text" LUKS_MAPPER)"; got_boot="$(helper_default "$text" BOOT_ID_FILE)"
  if [ -z "$want_arm" ] || [ "$want_arm" != "$got_arm" ]; then verdict "default LUKS_ARM_FILE equals the provisioner's ARM_FILE" no "helper '$got_arm' vs provisioner '$want_arm'"; return; fi
  if [ -z "$want_mapper" ] || [ "$want_mapper" != "$got_mapper" ]; then verdict "default LUKS_MAPPER equals the provisioner's MAPPER" no "helper '$got_mapper' vs provisioner '$want_mapper'"; return; fi
  if [ -z "$want_boot" ] || [ "$want_boot" != "$got_boot" ]; then verdict "default BOOT_ID_FILE equals luks-monitor's" no "helper '$got_boot' vs probe '$want_boot'"; return; fi
  verdict "default seams equal their producers (arm file $got_arm, mapper $got_mapper, boot id $got_boot)" ok ""
}
case_defaults

# --- MUTATION ROWS over the helper text. Each row: (1) the case is GREEN on the real helper (positive
# control), (2) the mutation LANDS (the text changed), (3) the same case turns RED on the mutant.
mut_row() { # <name> <case-fn> <from-literal> <to-literal>
  local name="$1" fn="$2" from="$3" to="$4" mutated
  MUTATION_ROWS=$((MUTATION_ROWS + 1))
  if ! FBR_QUIET=1 "$fn"; then no "M: $name — the control case $fn is not green on the real helper"; return; fi
  mutated="${HELPER/"$from"/"$to"}"
  if [ "$mutated" = "$HELPER" ]; then no "M: $name — the mutation did not land (text not found)"; return; fi
  if FBR_HELPER="$mutated" FBR_QUIET=1 "$fn"; then no "M: $name — the mutant SURVIVED $fn"; else ok "M: $name is caught by $fn"; fi
}
mut_row "not-ready Sentry emit removed" case_luks '  soleur-boot-emit "fresh_boot_not_ready_$REASON" fatal' '  :'
mut_row "not-ready severity fatal -> info" case_luks 'soleur-boot-emit "fresh_boot_not_ready_$REASON" fatal' 'soleur-boot-emit "fresh_boot_not_ready_$REASON" info'
mut_row "not-ready stage loses the reason" case_luks 'soleur-boot-emit "fresh_boot_not_ready_$REASON" fatal' 'soleur-boot-emit fresh_boot_not_ready fatal'
mut_row "ready path emits fatal" case_ready 'soleur-boot-emit fresh_boot_ready info' 'soleur-boot-emit fresh_boot_ready fatal'
mut_row "LUKS_ARM_FILE default drifted" case_defaults '/run/soleur/workspaces-luks-arm}' '/run/soleur/workspaces-luks-arm2}'
mut_row "LUKS_MAPPER default drifted" case_defaults ':-/dev/mapper/workspaces}' ':-/dev/mapper/workspace}'
mut_row "boot id charset bind dropped" case_bootid_bound " | tr -cd '0-9a-f-' | head -c 36)" " | head -c 36)"
mut_row "boot id length bind dropped" case_bootid_bound "| tr -cd '0-9a-f-' | head -c 36)" "| tr -cd '0-9a-f-')"
mut_row "boot id stderr redirect after the <" case_bootid_silent "tr 'A-F' 'a-f' 2>/dev/null < \"\${BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}\" |" "tr 'A-F' 'a-f' < \"\${BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}\" 2>/dev/null |"
mut_row "findmnt pointed at /" case_ready 'findmnt -no SOURCE "$WORKSPACES_MOUNT"' 'findmnt -no SOURCE /'
mut_row "mountpoint pointed at /" case_ready 'mountpoint -q "$WORKSPACES_MOUNT"' 'mountpoint -q /'
mut_row "vector probe asks about docker" case_ready 'systemctl is-active --quiet vector' 'systemctl is-active --quiet docker'
mut_row "reason precedence swapped (vector before token)" case_prec_tv 'elif [ "$T" != 1 ]; then REASON=token
elif [ "$V" != 1 ]; then REASON=vector' 'elif [ "$V" != 1 ]; then REASON=vector
elif [ "$T" != 1 ]; then REASON=token'
mut_row "luks_arm vocabulary widened to .*" case_arm_vocab '^luks_arm=\(formatted\|opened\|noop\)$' '^luks_arm=\(.*\)$'
mut_row "skipped post raises no warning stage" case_bs_notoken '  soleur-boot-emit fresh_boot_ready_bs_egress warning' '  :'
mut_row "skipped post leaves no detail" case_bs_notoken '  detail fresh_boot_ready_bs_egress "reason=$BS_WHY luks_arm=$ARM escrow=$ESC boot_id=$BOOT_ID"' '  :'
mut_row "failed post is not recorded" case_bs_failed 'BS_WHY=post_failed; ' ''
mut_row "bearer sent to any non-empty url" case_bs_unpinned 'if [ -n "$TOKEN" ] && [ "$INGEST_URL" = "$INGEST_URL_PINNED" ] && bearer_ok "$TOKEN"; then' 'if [ -n "$TOKEN" ] && [ -n "$INGEST_URL" ] && bearer_ok "$TOKEN"; then'
mut_row "token shape guard dropped (a malformed token reaches curl)" case_bs_badshape ' && bearer_ok "$TOKEN"; then
  post()' '; then
  post()'
_m_from="  post() { printf 'header = \"Authorization: Bearer %s\"\\n' \"\$TOKEN\" | curl --disable --noproxy '*' -fsS -m 10 --config - -H 'Content-Type: application/json'"
_m_to="  post() { curl --disable --noproxy '*' -fsS -m 10 -H \"Authorization: Bearer \$TOKEN\" -H 'Content-Type: application/json'"
mut_row "bearer back on curl's argv" case_bs_ok "$_m_from" "$_m_to"
mut_row "ready twin detail dropped" case_detail_ready '  detail fresh_boot_ready "token=$T vector=$V volume=$VOL luks=$LUKS luks_arm=$ARM escrow=$ESC boot_id=$BOOT_ID"' '  :'
mut_row "not-ready detail dropped" case_detail_notready '  detail "fresh_boot_not_ready_$REASON" "token=$T vector=$V volume=$VOL luks=$LUKS luks_arm=$ARM escrow=$ESC boot_id=$BOOT_ID"' '  :'
# HARMLESS variant: a comment-only edit must stay green (the harness is not just rejecting every change).
MUTATION_ROWS=$((MUTATION_ROWS + 1))
if FBR_HELPER="${HELPER/'READY=0; REASON=none'/'READY=0; REASON=none # harmless'}" FBR_QUIET=1 case_ready && [ "${HELPER/'READY=0; REASON=none'/'READY=0; REASON=none # harmless'}" != "$HELPER" ]; then ok "M: a comment-only edit stays green (harmless variant)"; else no "M: the harmless variant turned red or did not land"; fi

# Anti-vacuity: an exact floor on the assertions of this file. Deleting a case group, the mutation
# battery or the structural half leaves a lower count, which reds here.
EXPECTED_ASSERTIONS=68
total=$((pass + fail))
if [ "$total" -ne "$EXPECTED_ASSERTIONS" ]; then
  no "floor: ran $total assertions, expected exactly $EXPECTED_ASSERTIONS (a group of cases was deleted or added without moving the floor)"
fi
if [ "$MUTATION_ROWS" -ne 23 ]; then no "count: $MUTATION_ROWS mutation rows ran, expected exactly 23"; fi

echo "=== fresh-boot-ready: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
