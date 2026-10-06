#!/usr/bin/env bash
# Tests the WEB-host private-NIC self-report guard (#6438 §3, AC4, web-private-nic-guard.sh).
# This guard is the registry converger's web-host port with ONE deliberate divergence: it
# NEVER reboots (a reboot would power-off the sole live origin, apply-web-platform-infra.yml
# :878). So this suite is mostly negative space — proving the guard DETECTS + EMITS + pings
# the liveness beat, but NEVER mutates.
#
# UNLIKE registry private-nic-guard.test.sh (which RENDERS the guard out of a Terraform
# templatefile — un-indent -> substitute TF vars -> un-escape `$${`), this guard is ENV-DRIVEN
# PLAIN BASH delivered byte-identically by BOTH routes (SSH provisioner + cloud-init variable),
# so we EXECUTE THE REAL .sh DIRECTLY against synthesized fixtures + PATH stubs. Env seams:
# EXPECTED_IP, BETTERSTACK_INGEST_URL, BETTERSTACK_LOGS_TOKEN, WEB_NIC_GUARD_URL, and the
# SOLEUR_NIC_TEST_ROOT FS-read re-root (cq-test-fixtures-synthesized-only).
#
# AC4 (the load-bearing one) has TWO parts:
#   (i) BEHAVIORAL: a `reboot` PATH stub records every invocation; every fixture asserts the
#       trace stays empty AND the emit fired (so "no reboot" can never pass because the script
#       died early). The heartbeat ping fires ONLY when nic_ok=true (T1 is the positive control;
#       a broken NIC must let the beat lapse so absence alarms).
#  (ii) STRUCTURAL, anchored on SYNTAX not a bare `grep reboot`: the emit carries a CONSTANT
#       `reboot_count=0` and the header COMMENTS mention reboot, so a token grep false-fails a
#       correct detect-only port. We assert on a COMMENT-STRIPPED view that the reboot INVOCATION
#       PATH is absent (no standalone `reboot` line, no CONVERGED_BY=reboot, no DO_REBOOT, no
#       $REBOOT_BIN / REBOOT_CAP) — and MUTATION-test each negative so it is provably non-vacuous.
#
# Pure bash + PATH stubs — no docker, network, doppler, or root.
#
# Run: bash apps/web-platform/infra/web-private-nic-guard.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/web-private-nic-guard.sh"
TEST_IP="10.0.1.10"   # web-1's private address (var.web_hosts[web-1].private_ip); never a literal in the SUT.

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Resolved BEFORE any fixture strips PATH (the hide-ip arm runs on a stripped PATH).
TIMEOUT_BIN="$(command -v timeout || true)"
# Absolute paths, resolved once: the hide-ip arm (T3) runs on a stripped PATH that has no `env`.
ENV_BIN="$(command -v env || true)"
BASH_BIN="$(command -v bash || true)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# The ONE pinned Better Stack source URL, read from its single source at test time (never retyped),
# with the same sed fresh-boot-ready.test.sh S4d uses. The guard now refuses any other destination.
PINNED_URL="$(sed -n 's/^[[:space:]]*betterstack_logs_ingest_url[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$SCRIPT_DIR/zot-registry.tf" | sed -n '1p')"

echo "=== web-host private-NIC self-report guard (#6438 §3, AC4) tests ==="
assert "web-private-nic-guard.sh exists" "[[ -f '$SUT' ]]"
assert "SUT is syntactically valid bash" "bash -n '$SUT'"
assert "the timeout binary is available (bounds the stubbed-sleep spin)" "[[ -x '$TIMEOUT_BIN' ]]"

# --- PATH stubs --------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"

# `ip` serves the trigger predicate (`-4 -o addr show`) and the emit's NIC_ADDRS tail.
cat > "$BIN/ip" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "${STUB_IP_OUT:-}"
EOS

# `curl` serves three callers: the IMDS probe (private-networks), the Better Stack POST
# (--data-raw), and the liveness heartbeat ping (WEB_NIC_GUARD_URL, the only other curl).
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# Log argv FIRST (before the IMDS early exit), one argument per line (printf, never echo: -n is a
# valid curl flag; the payload and the Bearer header both contain spaces), calls split by a marker.
if [[ -n "${STUB_ARGV:-}" ]]; then
  printf '%s\n' '--CALL--' >> "$STUB_ARGV"
  for a in "$@"; do printf '%s\n' "$a" >> "$STUB_ARGV"; done
fi
# A bearer fed on stdin (`--config -`) never reaches argv; record what arrives there so the suite can
# prove the header is delivered, not merely absent from argv.
prev=""
for a in "$@"; do
  if [[ "$prev" == "--config" && "$a" == "-" && -n "${STUB_STDIN:-}" ]]; then cat >> "$STUB_STDIN"; fi
  prev="$a"
done
for a in "$@"; do
  case "$a" in
    *private-networks*) printf '%s' "${STUB_IMDS_BODY:-}"; exit "${STUB_IMDS_RC:-0}";;
  esac
done
is_post=false
for a in "$@"; do [[ "$a" == "--data-raw" ]] && is_post=true; done
if $is_post; then
  prev=""
  for a in "$@"; do [[ "$prev" == "--data-raw" ]] && printf '%s\n' "$a" >> "$STUB_EMIT"; prev="$a"; done
  exit "${STUB_POST_RC:-0}"
fi
# Otherwise this is the heartbeat ping — record its URL (the last positional).
url=""; for a in "$@"; do url="$a"; done
printf '%s\n' "$url" >> "$STUB_PING"
exit "${STUB_PING_RC:-0}"
EOS

# A reboot stub that RECORDS every call. A correct web-host guard never invokes it, so the
# trace must stay empty in every fixture — the behavioral half of AC4.
cat > "$BIN/reboot" <<'EOS'
#!/usr/bin/env bash
echo "reboot $*" >> "$STUB_TRACE"
EOS

# Stub sleep so the absent-IP fixtures' bounded wait (~30x2s) runs instantly. With sleep
# stubbed a lost wait-bound becomes an infinite TIGHT SPIN, so run_guard wraps with `timeout`.
cat > "$BIN/sleep" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS

chmod +x "$BIN"/*

# --- Fixture harness ---------------------------------------------------------------------
# run_guard <ip_present:true|false> <imds_rc> <imds_has_expected:true|false> [hide_ip:true|false]
# Optional per-run knobs, reset after every run so nothing leaks between rows:
#   SUT_UNDER_TEST  script to execute (default $SUT)
#   LAUNCH_FLAGS    bash flags (e.g. -x)
#   EXTRA_ENV       NAME=value words handed to `env` AFTER the defaults (so they override). Nothing that
#                   varies is exported in the test shell.
# Results: RC OUT ERR EMIT PING TRACE, and ARGV_FILE (the stub curl's per-argument log).
SUT_UNDER_TEST=""
LAUNCH_FLAGS=()
EXTRA_ENV=()
run_guard() {
  local ip_present="$1" imds_rc="$2" imds_expected="$3" hide_ip="${4:-false}"
  local root="$TMP/root.$$.$RANDOM"
  rm -rf "$root"; mkdir -p "$root/proc/sys/kernel/random"
  printf '99999.00 0.00\n' > "$root/proc/uptime"
  printf 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n' > "$root/proc/sys/kernel/random/boot_id"

  # Synthesized `ip -4 -o addr show`. Public eth0 is ALWAYS present (the #6400 shape: the host
  # is reachable/green while the private NIC is missing). enp7s0 carries EXPECTED_IP iff present.
  if [[ "$ip_present" == true ]]; then
    export STUB_IP_OUT="1: lo    inet 127.0.0.1/8 scope host lo
2: eth0    inet 203.0.113.10/32 scope global eth0
3: enp7s0    inet ${TEST_IP}/32 scope global enp7s0"
  else
    export STUB_IP_OUT="1: lo    inet 127.0.0.1/8 scope host lo
2: eth0    inet 203.0.113.10/32 scope global eth0"
  fi

  # Synthesized Hetzner IMDS private-networks YAML (`- ip:` then a 2-space `network_id:`).
  STUB_IMDS_BODY=""
  if [[ "$imds_expected" == true ]]; then
    STUB_IMDS_BODY="- ip: ${TEST_IP}
  network_id: 1001
  network_name: soleur-private
"
  fi
  export STUB_IMDS_BODY STUB_IMDS_RC="$imds_rc"
  export STUB_EMIT="$root/emit"; : > "$STUB_EMIT"
  export STUB_PING="$root/ping"; : > "$STUB_PING"
  export STUB_TRACE="$root/trace"; : > "$STUB_TRACE"
  export STUB_ARGV="$root/argv"; : > "$STUB_ARGV"
  ARGV_FILE="$STUB_ARGV"
  export STUB_STDIN="$root/stdin"; : > "$STUB_STDIN"
  STDIN_FILE="$STUB_STDIN"

  # hide_ip models the probe-fault class: `ip` unresolvable (lives in /usr/sbin, off cron's
  # default PATH) while curl still resolves. The stripped PATH is used ALONE so the real
  # /usr/sbin/ip cannot leak in and mask the fault.
  local run_path="$BIN:$PATH"
  if [[ "$hide_ip" == true ]]; then
    local nobin="$root/nobin"; mkdir -p "$nobin"
    local b p
    for b in curl reboot sleep; do cp "$BIN/$b" "$nobin/$b"; done
    for b in bash awk grep cat sed head cut tr tail seq; do
      p="$(command -v "$b" 2>/dev/null || true)"; [[ -n "$p" ]] && ln -sf "$p" "$nobin/$b" 2>/dev/null || true
    done
    run_path="$nobin"
  fi

  local sut="${SUT_UNDER_TEST:-$SUT}"
  "$ENV_BIN" PATH="$run_path" EXPECTED_IP="$TEST_IP" SOLEUR_NIC_TEST_ROOT="$root" \
    BETTERSTACK_LOGS_TOKEN=synthetic-token BETTERSTACK_INGEST_URL="$PINNED_URL" \
    WEB_NIC_GUARD_URL="https://synthetic.invalid/beat/web-nic-guard" \
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
    "$TIMEOUT_BIN" 10 "$BASH_BIN" ${LAUNCH_FLAGS[@]+"${LAUNCH_FLAGS[@]}"} "$sut" >"$root/out" 2>"$root/err"
  RC=$?
  SUT_UNDER_TEST=""; LAUNCH_FLAGS=(); EXTRA_ENV=()

  # shellcheck disable=SC2034  # consumed by assert() conditions via eval
  OUT="$(cat "$root/out" 2>/dev/null || true)"
  # shellcheck disable=SC2034
  ERR="$(cat "$root/err" 2>/dev/null || true)"
  # shellcheck disable=SC2034
  EMIT="$(cat "$root/emit" 2>/dev/null || true)"
  # shellcheck disable=SC2034
  PING="$(cat "$root/ping" 2>/dev/null || true)"
  # shellcheck disable=SC2034
  TRACE="$(cat "$root/trace" 2>/dev/null || true)"
}

# transport_audit — walk the stub curl's RECORDED argv (so a later-added call site is judged
# automatically). Sets TA_POST / TA_PING (call counts) and TA_BAD (calls that are neither
# `--disable`-first nor carry `--noproxy` immediately followed by `*`). The IMDS probe carries no
# credential and is exempt BY NAME (it contains `private-networks`).
TA_POST=0; TA_PING=0; TA_BAD=0
_ta_flush() {
  [[ ${#TA_CALL[@]} -gt 0 ]] || return 0
  local a i kind=ping
  for a in "${TA_CALL[@]}"; do
    case "$a" in *private-networks*) TA_CALL=(); return 0;; esac
    [[ "$a" == "--data-raw" ]] && kind=post
  done
  [[ "$kind" == post ]] && TA_POST=$((TA_POST + 1)) || TA_PING=$((TA_PING + 1))
  local ok=true has_np=false
  [[ "${TA_CALL[0]}" == "--disable" ]] || ok=false
  for ((i = 0; i < ${#TA_CALL[@]} - 1; i++)); do
    [[ "${TA_CALL[i]}" == "--noproxy" && "${TA_CALL[i+1]}" == "*" ]] && has_np=true
  done
  [[ "$has_np" == true ]] || ok=false
  [[ "$ok" == true ]] || TA_BAD=$((TA_BAD + 1))
  TA_CALL=()
}
transport_audit() {
  TA_POST=0; TA_PING=0; TA_BAD=0; TA_CALL=()
  local line
  while IFS= read -r line; do
    if [[ "$line" == "--CALL--" ]]; then _ta_flush; else TA_CALL+=("$line"); fi
  done < "$ARGV_FILE"
  _ta_flush
}

field() { printf '%s' "$EMIT" | grep -oE "$1=[^ \"]+" | sed -n '1p' | cut -d= -f2; }

# --- BEHAVIORAL: T1 ip present => nic_ok, converged_by=already, heartbeat PINGED ----------
# T1 is the POSITIVE CONTROL for the whole ping suite: it proves the ping stub + mechanism are
# live, so every "NOT pinged" below means something.
echo "--- behavioral: T1 ip present => already, ping fires ---"
run_guard true 0 true
assert "T1 emits an event" "[[ -n \"\$EMIT\" ]]"
assert "T1 nic_ok=true" "[[ \"\$(field nic_ok)\" == true ]]"
assert "T1 converged_by=already" "[[ \"\$(field converged_by)\" == already ]]"
assert "T1 heartbeat PINGED (nic_ok=true)" "grep -q 'web-nic-guard' <<<\"\$PING\""
assert "T1 NO reboot invoked" "[[ -z \"\$TRACE\" ]]"
assert "T1 emit carries the CONSTANT reboot_count=0" "grep -qE '(^| )reboot_count=0( |\")' <<<\"\$EMIT\""

# --- BEHAVIORAL: T2 ip absent + IMDS corroborates => detect-only, NO reboot, NO ping ------
echo "--- behavioral: T2 ip absent, IMDS corroborates => detect-only ---"
run_guard false 0 true
assert "T2 emits an event" "[[ -n \"\$EMIT\" ]]"
assert "T2 nic_ok=false" "[[ \"\$(field nic_ok)\" == false ]]"
assert "T2 converged_by=detect-only (NOT reboot — web host never power-cycles the sole origin)" \
  "[[ \"\$(field converged_by)\" == detect-only ]]"
assert "T2 NO reboot invoked" "[[ -z \"\$TRACE\" ]]"
assert "T2 heartbeat NOT pinged (broken NIC must let the beat lapse)" "[[ -z \"\$PING\" ]]"
assert "T2 imds_has_expected=true is carried for discrimination" "[[ \"\$(field imds_has_expected)\" == true ]]"

# --- BEHAVIORAL: T3 ip probe unresolvable => probe-fault, NO reboot, NO ping --------------
echo "--- behavioral: T3 ip binary absent => probe-fault ---"
run_guard false 0 true true
assert "T3 emits an event (the fault is observable off-box)" "[[ -n \"\$EMIT\" ]]"
assert "T3 converged_by=probe-fault (zero evidence, not a NIC diagnosis)" \
  "[[ \"\$(field converged_by)\" == probe-fault ]]"
assert "T3 nic_ok=false" "[[ \"\$(field nic_ok)\" == false ]]"
assert "T3 NO reboot invoked" "[[ -z \"\$TRACE\" ]]"
assert "T3 heartbeat NOT pinged" "[[ -z \"\$PING\" ]]"

# --- BEHAVIORAL: emit field contract (full set, always) ----------------------------------
echo "--- behavioral: emit field contract ---"
run_guard true 0 true
assert "emit marker is SOLEUR_PRIVATE_NIC" "grep -q 'SOLEUR_PRIVATE_NIC' <<<\"\$EMIT\""
for f in nic_ok converged_by imds_rc imds_nets imds_has_expected reboot_count zot_store_mounted uptime_s boot_id zot_last_err; do
  assert "emit carries $f" "grep -qE '(^| )$f=' <<<\"\$EMIT\""
done
assert "emit's reboot_count is the CONSTANT 0 (no-reboot invariant self-evident in every beat)" \
  "[[ \"\$(field reboot_count)\" == 0 ]]"

# --- AC4 STRUCTURAL: the reboot INVOCATION PATH is absent (comment-stripped view) ---------
# Anchored on SYNTAX, not a token grep: the header comments mention reboot and the emit carries
# `reboot_count=0`, so a bare `grep reboot` on the RAW file false-fails a correct port. Strip
# full-line `#` comments first, then assert on the code that remains.
echo "--- AC4 structural: no reboot invocation path (comment-stripped) ---"
STRIPPED="$(grep -vE '^[[:space:]]*#' "$SUT")"
assert "the stripped view is non-empty (comment-strip did not nuke the script)" "[[ -n \"\$STRIPPED\" ]]"
assert "the stripped view still carries the emit line (strip kept the code)" \
  "grep -q 'SOLEUR_PRIVATE_NIC' <<<\"\$STRIPPED\""
# Document WHY the strip is required: the RAW file DOES contain the token 'reboot' (in comments +
# reboot_count=0), so a naive `grep reboot == absent` would false-fail this correct detect-only port.
assert "rationale: the RAW file contains the token 'reboot' (why a bare grep false-fails)" \
  "grep -q 'reboot' '$SUT'"

assert "AC4: no standalone 'reboot' command line" \
  "! grep -qE '^[[:space:]]*reboot([[:space:]]|\$)' <<<\"\$STRIPPED\""
assert "AC4: no CONVERGED_BY=reboot execution path" \
  "! grep -q 'CONVERGED_BY=reboot' <<<\"\$STRIPPED\""
assert "AC4: no DO_REBOOT gate" \
  "! grep -q 'DO_REBOOT' <<<\"\$STRIPPED\""
assert "AC4: no \$REBOOT_BIN resolution" \
  "! grep -q 'REBOOT_BIN' <<<\"\$STRIPPED\""
assert "AC4: no REBOOT_CAP budget (the registry's reboot machinery is intentionally absent)" \
  "! grep -q 'REBOOT_CAP' <<<\"\$STRIPPED\""

# --- AC4 MUTATION CONTROLS: prove each negative assert above can FAIL (non-vacuity) -------
# Each control appends the offending construct to the stripped view and shows the SAME predicate
# the negative assert uses WOULD then match — so the negative assert is meaningful, not vacuous.
echo "--- AC4 mutation controls: each negative assert is provably non-vacuous ---"
assert "MUT: a standalone 'reboot' line is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'reboot' | grep -cE '^[[:space:]]*reboot([[:space:]]|\$)' >/dev/null"
assert "MUT: 'CONVERGED_BY=reboot' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'CONVERGED_BY=reboot' | grep -c 'CONVERGED_BY=reboot' >/dev/null"
assert "MUT: 'DO_REBOOT' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'if [ \"\$DO_REBOOT\" = true ]; then' | grep -c 'DO_REBOOT' >/dev/null"
assert "MUT: '\$REBOOT_BIN' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'REBOOT_BIN=\$(command -v reboot)' | grep -c 'REBOOT_BIN' >/dev/null"
assert "MUT: 'REBOOT_CAP' is detected by the predicate" \
  "printf '%s\n' \"\$STRIPPED\" 'REBOOT_CAP=2' | grep -c 'REBOOT_CAP' >/dev/null"
# And prove the standalone-reboot predicate does NOT fire on the emit's `reboot_count=0` (the exact
# false-positive the anchoring defends against) — so the negative asserts pass for the RIGHT reason.
assert "MUT: the predicate does NOT mis-fire on the emit's 'reboot_count=0'" \
  "! printf '%s\n' 'LINE=\"SOLEUR_PRIVATE_NIC reboot_count=0 boot_id=x\"' | grep -cE '^[[:space:]]*reboot([[:space:]]|\$)' >/dev/null"

# --- static drift-guard: doppler-auth unit-start contract (#6438 §3 unit-start fix) -------
# The guard runs `doppler run` as ROOT. Without Environment=HOME=/root the doppler CLI dies
# "$HOME is not defined" BEFORE it exec's the guard; without a DOPPLER_TOKEN in the per-host
# env file it cannot authenticate. Both gaps made the unit fail to start on web-1. Assert both,
# and that the fix does not re-open the #6536 /tmp/.doppler ownership clash surface.
echo "--- static: doppler-auth unit-start contract ---"
SVC="$SCRIPT_DIR/web-private-nic-guard.service"
SERVER_TF="$SCRIPT_DIR/server.tf"
assert "nic-guard .service sets Environment=HOME=/root (else doppler: \$HOME is not defined)" \
  "grep -qE '^Environment=HOME=/root\$' '$SVC'"
assert "nic-guard .service does NOT source webhook-deploy (deploy-owned; imports /tmp/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c 'webhook-deploy' >/dev/null"
assert "nic-guard .service does NOT set DOPPLER_CONFIG_DIR (root doppler uses /root/.doppler)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c 'DOPPLER_CONFIG_DIR' >/dev/null"
assert "nic-guard .service does NOT reference /tmp/.doppler (#6536 clash surface)" \
  "! grep -vE '^[[:space:]]*#' '$SVC' | grep -c '/tmp/.doppler' >/dev/null"
assert "nic-guard .service is root-run (no User=deploy without PrivateTmp=true)" \
  "! grep -qE '^User=deploy' '$SVC' || grep -cE '^PrivateTmp=true' >/dev/null '$SVC'"
# Anchor on the token VALUE wiring (web_probes.key), not just the literal (test-design review).
assert "server.tf private_nic_guard_install writes DOPPLER_TOKEN=<web_probes.key> into /etc/default/web-private-nic-guard" \
  "grep -qE 'DOPPLER_TOKEN=%s.*web_probes\\.key.*/etc/default/web-private-nic-guard' '$SERVER_TF'"

# ============================================================================================
# --- #7797 hardening: xtrace refusal, curl transport confinement, ingest-URL pin ------------
# Three properties of the credential handling (plan 2026-10-06-fix-credential-harden-...):
#   X1  the guard never runs a command that expands a credential while shell tracing is on
#   X2  every credentialed curl is `--disable`-first and carries `--noproxy '*'`
#   X3  the bearer token only ever goes to the one pinned Better Stack source URL
# No row below uses a pipe-fed `grep -q` (that shape is ratcheted by grep-q-pipe-guard.test.sh).
# ============================================================================================
echo "--- #7797 hardening: preconditions ---"
assert "PINNED_URL was read from zot-registry.tf (non-empty, https://)" "[[ \"\$PINNED_URL\" == https://* ]]"
assert "env / bash resolved by absolute path" "[[ -x '$ENV_BIN' && -x '$BASH_BIN' ]]"
PIN_HOST="${PINNED_URL#https://}"; PIN_HOST="${PIN_HOST%/}"
SYNTH_TOKEN="SYNTH-TOKEN-7797"
SYNTH_BEAT="https://synthetic.invalid/beat/SYNTH-BEAT-7797"
printf 'set -x\n' > "$TMP/xt.env"

# --- X1: xtrace refusal, three launch forms (two of them carry no `-x` token) --------------
echo "--- X1: the guard refuses to run under xtrace ---"
for form in bash-x SHELLOPTS BASH_ENV; do
  EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN="$SYNTH_TOKEN" WEB_NIC_GUARD_URL="$SYNTH_BEAT")
  case "$form" in
    bash-x)   LAUNCH_FLAGS=(-x) ;;
    SHELLOPTS) EXTRA_ENV+=(SHELLOPTS=xtrace) ;;
    BASH_ENV) EXTRA_ENV+=(BASH_ENV="$TMP/xt.env") ;;
  esac
  run_guard true 0 true
  assert "X1[$form] exits 78 (got rc=$RC; first stderr line: $(printf '%s' "$ERR" | sed -n '1p'))" "[[ \"\$RC\" -eq 78 ]]"
  assert "X1[$form] a NON-'+' stderr line carries the refusal message" \
    "[[ \"\$(grep -v '^+' <<<\"\$ERR\" | grep -c 'refusing to run under xtrace' || true)\" -ge 1 ]]"
  assert "X1[$form] neither stream carries the token or the heartbeat URL" \
    "[[ \"\$OUT\$ERR\" != *SYNTH-TOKEN-7797* && \"\$OUT\$ERR\" != *SYNTH-BEAT-7797* ]]"
  assert "X1[$form] nothing was emitted, pinged or sent (the stub curl is on PATH)" \
    "[[ -z \"\$EMIT\" && -z \"\$PING\" && ! -s \"\$ARGV_FILE\" ]]"
done
# X1b: unconditional — no credential and no EXPECTED_IP still refuses (the lint accepts a
# conditional `${TOKEN:+x}` refusal for this file, so this row is the only guard of that property).
x1b_rc=0
"$ENV_BIN" -i PATH="$BIN:/usr/bin:/bin" "$TIMEOUT_BIN" 10 "$BASH_BIN" -x "$SUT" >/dev/null 2>&1 || x1b_rc=$?
assert "X1b: bash -x with no credential and no EXPECTED_IP still exits 78 (got $x1b_rc)" "[[ \"\$x1b_rc\" -eq 78 ]]"
run_guard true 0 true
assert "X1c: the untraced healthy run is not refused (positive control)" "[[ \"\$RC\" -eq 0 && -n \"\$EMIT\" ]]"

# --- X2: transport confinement over the stub's RECORDED argv --------------------------------
echo "--- X2: every credentialed curl is --disable-first with --noproxy '*' ---"
run_guard true 0 true;                              transport_audit; X2_HEALTHY_POST=$TA_POST; X2_HEALTHY_PING=$TA_PING; X2_BAD=$TA_BAD
EXTRA_ENV=(STUB_POST_RC=1); run_guard true 0 true;  transport_audit; X2_POSTFAIL_POST=$TA_POST; X2_BAD=$((X2_BAD + TA_BAD))
EXTRA_ENV=(STUB_PING_RC=1); run_guard true 0 true;  transport_audit; X2_PINGFAIL_PING=$TA_PING; X2_BAD=$((X2_BAD + TA_BAD))
assert "X2 floors: a healthy run issues >=1 POST and >=1 ping (the walk is not vacuous)" \
  "[[ \"\$X2_HEALTHY_POST\" -ge 1 && \"\$X2_HEALTHY_PING\" -ge 1 ]]"
assert "X2 floors: the failing runs reach the fallback copies (>=2 POST, >=2 ping)" \
  "[[ \"\$X2_POSTFAIL_POST\" -ge 2 && \"\$X2_PINGFAIL_PING\" -ge 2 ]]"
assert "X2: no credentialed curl is missing --disable-first or --noproxy '*' (bad calls=$X2_BAD)" "[[ \"\$X2_BAD\" -eq 0 ]]"

# --- X3: the bearer goes only to the pinned URL ---------------------------------------------
echo "--- X3: ingest-URL pin ---"
EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN=OTHER-TOKEN-7797 EXPECTED_IP=10.0.1.11)
run_guard true 0 true; transport_audit
assert "X3 pinned URL (other token, other EXPECTED_IP): exactly one POST, to the pinned URL" \
  "[[ \"\$TA_POST\" -eq 1 && \"\$(grep -cxF -- \"\$PINNED_URL\" \"\$ARGV_FILE\")\" -eq 1 ]]"
EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN=)
run_guard true 0 true; transport_audit
assert "X3 pinned URL but no token: zero POSTs" "[[ \"\$TA_POST\" -eq 0 ]]"
x3=0
for url in "https://evil.invalid/ingest" "http://$PIN_HOST/" "${PINNED_URL%/}" \
           "https://$PIN_HOST@evil.invalid/" "https://evil.invalid/?x=$PIN_HOST/"; do
  x3=$((x3 + 1))
  EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN="$SYNTH_TOKEN" BETTERSTACK_INGEST_URL="$url")
  run_guard true 0 true; transport_audit
  assert "X3 refused[$x3] $url: zero POSTs" "[[ \"\$TA_POST\" -eq 0 ]]"
  assert "X3 refused[$x3]: the token is in no recorded argv" "[[ \"\$(grep -c -- \"\$SYNTH_TOKEN\" \"\$ARGV_FILE\")\" -eq 0 ]]"
  assert "X3 refused[$x3]: stderr names unpinned_url, rc 0, heartbeat still pings" \
    "[[ \"\$ERR\" == *unpinned_url* && \"\$RC\" -eq 0 && -n \"\$PING\" ]]"
done
# X3b: the pin cannot be redirected through the environment.
EXTRA_ENV=(INGEST_URL_PINNED=https://evil.invalid/ BETTERSTACK_INGEST_URL=https://evil.invalid/)
run_guard true 0 true; transport_audit
assert "X3b INGEST_URL_PINNED and BETTERSTACK_INGEST_URL both evil: zero POSTs" "[[ \"\$TA_POST\" -eq 0 ]]"
EXTRA_ENV=(INGEST_URL_PINNED=https://evil.invalid/)
run_guard true 0 true; transport_audit
assert "X3b evil INGEST_URL_PINNED with the real pinned URL still POSTs to the real pinned URL (positive control)" \
  "[[ \"\$TA_POST\" -eq 1 && \"\$(grep -cxF -- \"\$PINNED_URL\" \"\$ARGV_FILE\")\" -eq 1 ]]"
# X3c: the literal equals its single source byte-for-byte and cannot expand.
PIN_LITERAL="$(sed -n 's/^readonly INGEST_URL_PINNED="\(.*\)"$/\1/p' "$SUT" | sed -n '1p')"
assert "X3c the readonly literal equals zot-registry.tf betterstack_logs_ingest_url byte-for-byte" \
  "[[ -n \"\$PIN_LITERAL\" && \"\$PIN_LITERAL\" == \"\$PINNED_URL\" ]]"
assert "X3c the literal carries no \$ and no backtick (nothing the environment can expand)" \
  "[[ -n \"\$PIN_LITERAL\" && \"\$PIN_LITERAL\" != *'\$'* && \"\$PIN_LITERAL\" != *'\`'* ]]"

# --- X5: the bearer travels on stdin config, never on argv (Rule E, sweep #7843) -------------
echo "--- X5: bearer on stdin config, not argv ---"
EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN="$SYNTH_TOKEN")
run_guard true 0 true; transport_audit
assert "X5 a pinned POST happened (the argv scan below is not vacuous)" "[[ \"\$TA_POST\" -ge 1 ]]"
assert "X5 the token is in NO recorded argv (not readable from /proc/<pid>/cmdline)" \
  "[[ \"\$(grep -c -- \"\$SYNTH_TOKEN\" \"\$ARGV_FILE\")\" -eq 0 ]]"
assert "X5 the bearer header arrives on the stdin config of the POST" \
  "[[ \"\$(grep -cxF -- \"header = \\\"Authorization: Bearer \$SYNTH_TOKEN\\\"\" \"\$STDIN_FILE\")\" -ge 1 ]]"

# --- X4: drawdown — the grandfathering entries are gone --------------------------------------
echo "--- X4: not baselined (the repo-wide lint run now guards this file from regrowth) ---"
for bl in lint-shell-trace-credential-refusal.baseline.txt lint-shell-trace-credential-refusal-d.baseline.txt; do
  assert "X4 apps/web-platform/infra/web-private-nic-guard.sh is absent from $bl" \
    "[[ \"\$(grep -cxF 'apps/web-platform/infra/web-private-nic-guard.sh' '$REPO_ROOT/scripts/$bl')\" -eq 0 ]]"
done
assert "X4 non-vacuity: the baseline file is readable and non-empty" \
  "[[ -s '$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.baseline.txt' ]]"

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
