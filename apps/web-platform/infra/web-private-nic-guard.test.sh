#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables consumed by assert() conditions via eval
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
CASES=0   # moved by the assert() WRAPPER, never inside the verdict helpers (accounting identity at the bottom)
# Verdict helpers: they move only the verdict counters.
_pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
_fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; echo "        condition: $2"; }
assert() {
  local desc="$1" cond="$2"
  CASES=$((CASES + 1))
  if eval "$cond"; then _pass "$desc"; else _fail "$desc" "$cond"; fi
}
# Instrument self-test (report-only via printf + exit, never through assert): drive assert() once on a
# false and once on a true condition and require the matching verdict counter to move. An always-pass
# assert (`eval ... || true`) leaves every row green, so only this can see it.
_selftest_assert() {
  local p0=$PASS f0=$FAIL c0=$CASES
  assert "selftest: a false condition" "false" >/dev/null
  if [[ "$FAIL" -ne $((f0 + 1)) || "$PASS" -ne "$p0" ]]; then
    printf '[FATAL] instrument self-test: assert() did not record a FAIL for a false condition\n' >&2
    exit 1
  fi
  assert "selftest: a true condition" "true" >/dev/null
  if [[ "$PASS" -ne $((p0 + 1)) || "$FAIL" -ne $((f0 + 1)) ]]; then
    printf '[FATAL] instrument self-test: assert() did not record a PASS for a true condition\n' >&2
    exit 1
  fi
  PASS=$p0; FAIL=$f0; CASES=$c0
}
_selftest_assert

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Resolved BEFORE any fixture strips PATH (the hide-ip arm runs on a stripped PATH).
TIMEOUT_BIN="$(command -v timeout || true)"
# Absolute paths, resolved once: the hide-ip arm (T3) runs on a stripped PATH that has no `env`.
ENV_BIN="$(command -v env || true)"
BASH_BIN="$(command -v bash || true)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# The ONE pinned Better Stack source URL, read from its single source at test time (never retyped). The
# sed is fresh-boot-ready.test.sh S4d's form: first double-quoted value after the key.
PINNED_URL="$(sed -n 's/^[[:space:]]*betterstack_logs_ingest_url[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' "$SCRIPT_DIR/zot-registry.tf" | sed -n '1p')"

echo "=== web-host private-NIC self-report guard (#6438 §3, AC4) tests ==="
assert "web-private-nic-guard.sh exists" "[[ -f '$SUT' ]]"
assert "SUT is syntactically valid bash" "bash -n '$SUT'"
assert "the timeout binary is available (bounds the stubbed-sleep spin)" "[[ -x '$TIMEOUT_BIN' ]]"

# --- PATH stubs --------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"

# `ip` serves the trigger predicate (`-4 -o addr show`) and the emit's NIC_ADDRS tail.
# With STUB_IP_COUNTER set (pass-2 rows W-5, W-5b, W-5c, W-5d, W-7) it counts its own invocations in that file and answers the
# address-absent shape until call number STUB_IP_APPEAR_AT; unset, it is the plain fixed-output stub.
cat > "$BIN/ip" <<'EOS'
#!/usr/bin/env bash
if [[ -n "${STUB_IP_COUNTER:-}" ]]; then
  n=$(( $(cat "$STUB_IP_COUNTER" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$STUB_IP_COUNTER"
  if [[ "$n" -lt "${STUB_IP_APPEAR_AT:-2}" ]]; then printf '%s\n' "2: eth0    inet 203.0.113.10/32 scope global eth0"; exit 0; fi
fi
printf '%s\n' "${STUB_IP_OUT:-}"
EOS

# `curl` serves three callers: the IMDS probe (private-networks), the Better Stack POST
# (--data-raw), and the liveness heartbeat ping (WEB_NIC_GUARD_URL on its stdin config, the only other curl).
cat > "$BIN/curl" <<'EOS'
#!/usr/bin/env bash
# Log argv FIRST (before the IMDS early exit), one argument per line (printf, never echo: -n is a
# valid curl flag; the payload and the Bearer header both contain spaces), calls split by a marker.
if [[ -n "${STUB_ARGV:-}" ]]; then
  printf '%s\n' '--CALL--' >> "$STUB_ARGV"
  for a in "$@"; do printf '%s\n' "$a" >> "$STUB_ARGV"; done
fi
# A bearer fed on stdin (`--config -`) never reaches argv. Record, PER CALL, the call kind and whatever
# arrives on stdin, so the suite can prove the header is delivered to the pinned POST and to nothing else.
kind=ping; prev=""
for a in "$@"; do
  case "$a" in *private-networks*) kind=imds ;; --data-raw) [[ "$kind" == imds ]] || kind=post ;; esac
done
# stdin is read ONCE: a pipe or process substitution is consumed by its first reader, so the capture is held
# in cfg_in and then fanned out to the stdin record (STUB_STDIN) and, for the ping kind, to the parsed URL.
cfg_in=""
for a in "$@"; do
  if [[ "$prev" == "--config" && "$a" == "-" ]]; then cfg_in=$(cat); fi
  prev="$a"
done
if [[ -n "${STUB_STDIN:-}" ]]; then
  printf 'CALL %s\n' "$kind" >> "$STUB_STDIN"
  [[ -n "$cfg_in" ]] && printf '%s\n' "$cfg_in" >> "$STUB_STDIN"
fi
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
# Otherwise this is the heartbeat ping. The URL never rides argv any more: it is the value of the
# `url = "..."` line on the stdin config. A call whose stdin lost that line records an EMPTY line, which the
# suite reads as "no URL" (T1 and the healthy-run row go RED; the negative rows are backed by TA_PING).
url=$(printf '%s\n' "$cfg_in" | sed -n 's/^url = "\(.*\)"$/\1/p' | sed -n '1p')
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
#   FIXED_ROOT      basename of a root under $TMP to reuse (not wiped) so state under $TMP/$FIXED_ROOT/run survives between runs
#   LAUNCH_FLAGS    bash flags (e.g. -x)
#   EXTRA_ENV       NAME=value words handed to `env` AFTER the defaults (so they override). Nothing that
#                   varies is exported in the test shell.
# Results: RC OUT ERR EMIT PING TRACE, and ARGV_FILE (the stub curl's per-argument log).
SUT_UNDER_TEST=""
FIXED_ROOT=""   # BASENAME of a root under $TMP reused across runs (the refusal limiter's stamp lives under it); default is a fresh root per run
LAUNCH_FLAGS=()
EXTRA_ENV=()
run_guard() {
  local ip_present="$1" imds_rc="$2" imds_expected="$3" hide_ip="${4:-false}"
  local root="$TMP/${FIXED_ROOT:-root.$$.$RANDOM}"
  [[ -n "$FIXED_ROOT" ]] || rm -rf "$root"
  mkdir -p "$root/proc/sys/kernel/random" "$root/run"
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
  # shellcheck disable=SC2034  # consumed by assert() conditions via eval
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
  "$ENV_BIN" -u BASH_ENV -u SHELLOPTS -u STUB_POST_RC -u STUB_PING_RC -u INGEST_URL_PINNED \
    PATH="$run_path" EXPECTED_IP="$TEST_IP" SOLEUR_NIC_TEST_ROOT="$root" \
    BETTERSTACK_LOGS_TOKEN=synthetic-token BETTERSTACK_INGEST_URL="$PINNED_URL" \
    WEB_NIC_GUARD_URL="https://synthetic.invalid/beat/web-nic-guard" \
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
    "$TIMEOUT_BIN" 10 "$BASH_BIN" ${LAUNCH_FLAGS[@]+"${LAUNCH_FLAGS[@]}"} "$sut" >"$root/out" 2>"$root/err"
  RC=$?
  SUT_UNDER_TEST=""; FIXED_ROOT=""; LAUNCH_FLAGS=(); EXTRA_ENV=()

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
  # Every run is audited, not only the fixtures that remembered to ask (X2 used to cover three of them).
  transport_audit
  ALL_TA_BAD=$((ALL_TA_BAD + TA_BAD)); ALL_BEARER_BAD=$((ALL_BEARER_BAD + TA_BEARER_BAD))
}

# transport_audit — walk the stub curl's RECORDED argv (so a later-added call site is judged
# automatically). Sets TA_POST / TA_PING (call counts) and TA_BAD (calls that are neither
# `--disable`-first nor carry `--noproxy` immediately followed by `*`). The IMDS probe carries no
# credential and is exempt BY NAME (it contains `private-networks`).
IMDS_URL="http://169.254.169.254/hetzner/v1/metadata/private-networks"
TA_POST=0; TA_PING=0; TA_BAD=0; TA_BEARER_BAD=0; ALL_TA_BAD=0; ALL_BEARER_BAD=0
_ta_flush() {
  [[ ${#TA_CALL[@]} -gt 0 ]] || return 0
  local a i kind=ping
  for a in "${TA_CALL[@]}"; do
    case "$a" in *private-networks*) kind=imds ;; --data-raw) [[ "$kind" == imds ]] || kind=post ;; esac
  done
  case "$kind" in post) TA_POST=$((TA_POST + 1)) ;; ping) TA_PING=$((TA_PING + 1)) ;; esac
  # GOLDEN argv per call class (an allowlist, not a deny-list of two flags): any added option such as
  # -k, --location-trusted, --proxy or --resolve changes the shape and is a bad call. The IMDS probe is
  # exempt from the credential flags BY EXACT URL (a call that merely contains `private-networks` is not),
  # and must still match its own golden argv.
  local ok=true
  local -a want=(--disable --noproxy '*' -gfsS -m 10 -o /dev/null --config -); local n_tail=0
  case "$kind" in
    post) want=(--disable --noproxy '*' -fsS -m 10 -H 'Content-Type: application/json' --config -); n_tail=3 ;;
    imds) want=(-sf -m 5); n_tail=1 ;;
  esac
  [[ ${#TA_CALL[@]} -eq $(( ${#want[@]} + n_tail )) ]] || ok=false
  for ((i = 0; i < ${#want[@]}; i++)); do [[ "${TA_CALL[i]:-}" == "${want[i]}" ]] || ok=false; done
  if [[ "$kind" == post ]]; then
    [[ "${TA_CALL[${#want[@]}]:-}" == "$PINNED_URL" ]] || ok=false
    [[ "${TA_CALL[$(( ${#want[@]} + 1 ))]:-}" == "--data-raw" ]] || ok=false
  elif [[ "$kind" == imds ]]; then
    [[ "${TA_CALL[${#want[@]}]:-}" == "$IMDS_URL" ]] || ok=false
  fi
  [[ "$ok" == true ]] || TA_BAD=$((TA_BAD + 1))
  TA_CALL=()
}
transport_audit() {
  TA_POST=0; TA_PING=0; TA_BAD=0; TA_BEARER_BAD=0; TA_CALL=()
  local line
  while IFS= read -r line; do
    if [[ "$line" == "--CALL--" ]]; then _ta_flush; else TA_CALL+=("$line"); fi
  done < "$ARGV_FILE"
  _ta_flush
  # Stdin GOLDEN per call class: a POST's stdin is exactly ONE `header = "Authorization: Bearer <token>"`
  # line (no `url =`, `proxy =`, `insecure`, `data =` or any second directive); a heartbeat PING's stdin is
  # exactly ONE `url = "https://..."` line in the guard's permitted alphabet (no `header =`, `proxy =`, `next`
  # or any second directive); the IMDS probe's stdin is empty. `missing` counts POSTs and pings without
  # their line, `extra` counts anything beyond it.
  local miss extra
  read -r miss extra < <(awk '
    function flush() { if (k == "") return
      if (k == "post" || k == "ping") { if (n == 0) miss++; else { if (n > 1) extra += n - 1; if (!ok1) extra++ } } else extra += n
      k = ""; n = 0; ok1 = 0 }
    /^CALL / { flush(); k = $2; n = 0; ok1 = 0; next }
    { if (k != "") { n++; if (n == 1 && ((k == "post" && $0 ~ /^header = "Authorization: Bearer [A-Za-z0-9._~+\/=-]+"$/) || (k == "ping" && $0 ~ /^url = "https:\/\/[A-Za-z0-9._~:\/?&=%+-]+"$/))) ok1 = 1 } }
    END { flush(); printf "%d %d\n", miss + 0, extra + 0 }' "$STDIN_FILE")
  # Fail CLOSED: an awk that errors leaves both empty, which must not read as "no bad calls". Also require that
  # the stdin walk saw as many calls as the argv walk did (a control that the walk looked at anything).
  local n_stdin n_argv
  n_stdin=$(grep -c '^CALL ' "$STDIN_FILE" || true); n_argv=$(grep -c '^--CALL--$' "$ARGV_FILE" || true)
  if [[ ! "$miss" =~ ^[0-9]+$ || ! "$extra" =~ ^[0-9]+$ || "$n_stdin" != "$n_argv" ]]; then miss=1; extra=1; fi
  TA_BEARER_BAD=$((miss + extra))
}

field() { printf '%s' "$EMIT" | grep -oE "$1=[^ \"]+" | sed -n '1p' | cut -d= -f2; }
# no_beat — the heartbeat was NOT sent, judged on three independent witnesses: the parsed URL (PING), the
# argv call count (TA_PING, independent of the stdin parse, so a stub that lost the stdin cannot make this
# vacuous) and the recorded stdin (no `url =` line reached any curl).
no_beat() { [[ -z "$PING" && "$TA_PING" -eq 0 ]] && ! grep -q '^url = ' "$STDIN_FILE"; }

# --- BEHAVIORAL: T1 ip present => nic_ok, converged_by=already, heartbeat PINGED ----------
# T1 is the POSITIVE CONTROL for the whole ping suite: it proves the ping stub + mechanism are
# live, so every "NOT pinged" below means something.
echo "--- behavioral: T1 ip present => already, ping fires ---"
run_guard true 0 true
assert "T1 emits an event" "[[ -n \"\$EMIT\" ]]"
assert "T1 nic_ok=true" "[[ \"\$(field nic_ok)\" == true ]]"
assert "T1 converged_by=already" "[[ \"\$(field converged_by)\" == already ]]"
assert "T1 heartbeat PINGED (nic_ok=true)" "grep -q 'web-nic-guard' <<<\"\$PING\""
assert "T1 the stub parsed the beat URL from curl's stdin config (non-empty, exact, one ping): a stub that lost the stdin cannot pass T1/X1 vacuously" \
  "[[ \"\$PING\" == 'https://synthetic.invalid/beat/web-nic-guard' && \"\$TA_PING\" -eq 1 ]]"
assert "T1 the beat URL is on stdin only: absent from every recorded argv word" "! grep -qF 'synthetic.invalid' \"\$ARGV_FILE\""
assert "T1 the stdin record holds exactly one url line for the one ping" "[[ \"\$(grep -c '^url = ' \"\$STDIN_FILE\" || true)\" -eq 1 ]]"
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
assert "T2 heartbeat NOT pinged (broken NIC must let the beat lapse)" "no_beat"
assert "T2 imds_has_expected=true is carried for discrimination" "[[ \"\$(field imds_has_expected)\" == true ]]"

# --- BEHAVIORAL: T3 ip probe unresolvable => probe-fault, NO reboot, NO ping --------------
echo "--- behavioral: T3 ip binary absent => probe-fault ---"
run_guard false 0 true true
assert "T3 emits an event (the fault is observable off-box)" "[[ -n \"\$EMIT\" ]]"
assert "T3 converged_by=probe-fault (zero evidence, not a NIC diagnosis)" \
  "[[ \"\$(field converged_by)\" == probe-fault ]]"
assert "T3 nic_ok=false" "[[ \"\$(field nic_ok)\" == false ]]"
assert "T3 NO reboot invoked" "[[ -z \"\$TRACE\" ]]"
assert "T3 heartbeat NOT pinged" "no_beat"

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
    "[[ -z \"\$EMIT\" && ! -s \"\$ARGV_FILE\" ]] && no_beat"
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
X2_POSTFAIL_BEAT=no; [[ -n "$PING" && "$TA_PING" -ge 1 ]] && X2_POSTFAIL_BEAT=yes
EXTRA_ENV=(STUB_PING_RC=1); run_guard true 0 true;  transport_audit; X2_PINGFAIL_PING=$TA_PING; X2_BAD=$((X2_BAD + TA_BAD))
assert "X2 floors: a healthy run issues >=1 POST and >=1 ping (the walk is not vacuous)" \
  "[[ \"\$X2_HEALTHY_POST\" -ge 1 && \"\$X2_HEALTHY_PING\" -ge 1 ]]"
assert "X2 floors: the failing runs reach the fallback copies (>=2 POST, >=2 ping)" \
  "[[ \"\$X2_POSTFAIL_POST\" -ge 2 && \"\$X2_PINGFAIL_PING\" -ge 2 ]]"
assert "X2 a POST that was ATTEMPTED and failed still beats (an outage of the destination is not a refusal)" "[[ \"\$X2_POSTFAIL_BEAT\" == yes ]]"
assert "X2: no credentialed curl is missing --disable-first or --noproxy '*' (bad calls=$X2_BAD)" "[[ \"\$X2_BAD\" -eq 0 ]]"

# --- X3: the bearer goes only to the pinned URL ---------------------------------------------
echo "--- X3: ingest-URL pin ---"
EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN=OTHER-TOKEN-7797 EXPECTED_IP=10.0.1.11)
run_guard true 0 true; transport_audit
assert "X3 pinned URL (other token, other EXPECTED_IP): exactly one POST, to the pinned URL" \
  "[[ \"\$TA_POST\" -eq 1 && \"\$(grep -cxF -- \"\$PINNED_URL\" \"\$ARGV_FILE\")\" -eq 1 ]]"
EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN=)
run_guard true 0 true; transport_audit
assert "X3 pinned URL but no token: zero POSTs, and the heartbeat is withheld (cannot report)" "[[ \"\$TA_POST\" -eq 0 ]] && no_beat"
EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN="$SYNTH_TOKEN" BETTERSTACK_INGEST_URL=)
run_guard true 0 true; transport_audit
assert "X3 token but no ingest URL: zero POSTs, WARN on stderr, and the heartbeat is withheld" "[[ \"\$TA_POST\" -eq 0 && \"\$ERR\" == *WARN* ]] && no_beat"
x3=0
for url in "https://evil.invalid/ingest" "http://$PIN_HOST/" "${PINNED_URL%/}" \
           "https://$PIN_HOST@evil.invalid/" "https://evil.invalid/?x=$PIN_HOST/" \
           "${PINNED_URL}x" "${PINNED_URL}?q=1" "https://$(printf '%s' "$PIN_HOST" | tr a-z A-Z)/"; do
  x3=$((x3 + 1))
  EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN="$SYNTH_TOKEN" BETTERSTACK_INGEST_URL="$url")
  run_guard true 0 true; transport_audit
  assert "X3 refused[$x3] $url: zero POSTs" "[[ \"\$TA_POST\" -eq 0 ]]"
  assert "X3 refused[$x3]: the token is in no recorded argv" "[[ \"\$(grep -c -- \"\$SYNTH_TOKEN\" \"\$ARGV_FILE\")\" -eq 0 ]]"
  assert "X3 refused[$x3]: stderr names unpinned_url and rc is 0" "[[ \"\$ERR\" == *unpinned_url* && \"\$RC\" -eq 0 ]]"
  assert "X3 refused[$x3]: the heartbeat is WITHHELD (a guard that cannot report must not claim health)" "no_beat"
  assert "X3 refused[$x3]: no curl was handed an Authorization header on stdin" "[[ \"\$(grep -c Authorization \"\$STDIN_FILE\")\" -eq 0 ]]"
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
# shellcheck disable=SC2034  # consumed by assert() conditions via eval
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
assert "X5 no recorded argv carries an Authorization header at all" "[[ \"\$(grep -ci authorization \"\$ARGV_FILE\")\" -eq 0 ]]"
assert "X5 the token is in NO recorded argv (not readable from /proc/<pid>/cmdline)" \
  "[[ \"\$(grep -c -- \"\$SYNTH_TOKEN\" \"\$ARGV_FILE\")\" -eq 0 ]]"
assert "X5 the bearer header arrives on the stdin config of the POST" \
  "[[ \"\$(grep -cxF -- \"header = \\\"Authorization: Bearer \$SYNTH_TOKEN\\\"\" \"\$STDIN_FILE\")\" -ge 1 ]]"

# --- X6: a token that would add curl-config directives is refused, never escaped -------------
echo "--- X6: token-shape guard (one forbidden character at a time) ---"
x6=0
for bad in 'Aa"b' 'Aa b' $'Aa\nb' 'Aa\b' 'Aa;b' $'SYNTH"quote\nurl = "https://evil.invalid/"'; do
  x6=$((x6 + 1))
  EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN="$bad")
  run_guard true 0 true; transport_audit
  assert "X6[$x6] a token with a forbidden character makes zero POSTs and names bad_token" "[[ \"\$TA_POST\" -eq 0 && \"\$ERR\" == *bad_token* ]]"
  assert "X6[$x6] nothing reached curl stdin" "[[ \"\$(grep -c Authorization \"\$STDIN_FILE\")\" -eq 0 ]]"
  assert "X6[$x6] the heartbeat is withheld" "no_beat"
  assert "X6[$x6] the token value is not echoed to stderr" "[[ \"\$ERR\" != *\"\$bad\"* ]]"
done
EXTRA_ENV=(BETTERSTACK_LOGS_TOKEN="Aa0._~+/=-9")
run_guard true 0 true; transport_audit
assert "X6 a token using every permitted punctuation character still POSTs (positive control)" "[[ \"\$TA_POST\" -eq 1 ]]"

# --- X4: drawdown — the grandfathering entries are gone --------------------------------------
echo "--- X4: not baselined (the repo-wide lint run now guards this file from regrowth) ---"
for bl in lint-shell-trace-credential-refusal.baseline.txt lint-shell-trace-credential-refusal-d.baseline.txt; do
  assert "X4 apps/web-platform/infra/web-private-nic-guard.sh is absent from $bl" \
    "[[ \"\$(grep -cxF 'apps/web-platform/infra/web-private-nic-guard.sh' '$REPO_ROOT/scripts/$bl')\" -eq 0 ]]"
done
assert "X4 apps/web-platform/infra/web-private-nic-guard.sh is absent from the Rule E baseline (path<TAB>count)" \
  "[[ \"\$(grep -c '^apps/web-platform/infra/web-private-nic-guard.sh	' '$REPO_ROOT/scripts/lint-shell-trace-credential-refusal-e.baseline.txt')\" -eq 0 ]]"
assert "X4 non-vacuity: the baseline file is readable and non-empty" \
  "[[ -s '$REPO_ROOT/scripts/lint-shell-trace-credential-refusal.baseline.txt' ]]"

# --- pass 2 (#9217): converted predicates keep their discrimination -------------------------------
# The happy path (canonical address, canonical IMDS body) is satisfiable by an always-true grep. These rows put a
# near-miss through each converted predicate, observe the wait loop's success arm, and pin stdout cleanliness.
# Row ids keep the plan's numbering (W-3 was cut at plan review; W-5b and W-7 were added by review).
echo "--- pass 2 (#9217): converted predicates keep their discrimination ---"
run_guard true 0 true
assert "W-6 healthy run writes nothing to stdout (every converted predicate discards the count it reads)" "[[ -z \"\$OUT\" ]]"
EXTRA_ENV=(EXPECTED_IP=10.0.1.1 "STUB_IP_OUT=3: enp7s0    inet 10.0.1.10/32 scope global enp7s0")
run_guard false 0 true
assert "W-1 -w near-miss: 10.0.1.1 is not found inside 10.0.1.10 (nic_ok=false)" "[[ \"\$(field nic_ok)\" == false ]]"
assert "W-1 -w near-miss: classified detect-only, not already" "[[ \"\$(field converged_by)\" == detect-only ]]"
assert "W-6 absent-start run (wait loop reached) writes nothing to stdout" "[[ -z \"\$OUT\" ]]"
EXTRA_ENV=("STUB_IP_OUT=3: enp7s0    inet 10a0b1c10/32 scope global enp7s0")
run_guard false 0 true
assert "W-2 -F literal: dots are not wildcards (10a0b1c10 is not 10.0.1.10)" "[[ \"\$(field nic_ok)\" == false && \"\$(field converged_by)\" == detect-only ]]"
EXTRA_ENV=("STUB_IMDS_BODY=- ip: ${TEST_IP}0"$'\n  network_id: 1001')
run_guard true 0 true
assert "W-4 IMDS near-miss: an address with a longer tail does not corroborate (imds_has_expected=false)" "[[ \"\$(field imds_has_expected)\" == false ]]"
assert "W-4 the network_id line is still counted (imds_nets=1 pins the numeric value)" "[[ \"\$(field imds_nets)\" == 1 ]]"
EXTRA_ENV=("STUB_IMDS_BODY=- ip: 10.0.1.99"$'\n  network_id: 1001\n- ip: '"${TEST_IP}"$'\n  network_id: 1002')
run_guard true 0 true
assert "W-4b the expected address in the SECOND IMDS entry still corroborates, and both network_id lines are counted (a first-entry-only reader would miss it)" \
  "[[ \"\$(field imds_has_expected)\" == true && \"\$(field imds_nets)\" == 2 ]]"
# The address sits mid-list with a docker0 line after it, as on a real host, so a last-line-only reader
# (tail -1) cannot find it at the trigger or in the wait loop.
MID_IP_OUT=$'1: lo    inet 127.0.0.1/8 scope host lo\n3: enp7s0    inet '"${TEST_IP}"$'/32 scope global enp7s0\n4: docker0    inet 172.17.0.1/16 scope global docker0'
W5_CTR="$TMP/ip-calls.w5"; printf '0' > "$W5_CTR"
EXTRA_ENV=("STUB_IP_COUNTER=$W5_CTR" STUB_IP_APPEAR_AT=2 "STUB_IP_OUT=$MID_IP_OUT")
run_guard true 0 true
assert "W-5 the address appearing on the second probe is found by the wait loop (nic_ok=true, already)" \
  "[[ \"\$(field nic_ok)\" == true && \"\$(field converged_by)\" == already ]]"
# The count is trigger + ONE wait-loop iteration + the emit's single NIC_ADDRS call (a lost break would make 32).
assert "W-5 exactly three ip calls: the trigger, one wait-loop iteration, the emit" \
  "[[ \"\$(cat '$W5_CTR')\" -eq 3 ]]"
W5B_CTR="$TMP/ip-calls.w5b"; printf '0' > "$W5B_CTR"
EXTRA_ENV=("STUB_IP_COUNTER=$W5B_CTR" STUB_IP_APPEAR_AT=3 "STUB_IP_OUT=$MID_IP_OUT")
run_guard true 0 true
assert "W-5b the address appearing on the THIRD probe is still found: the wait loop retries (nic_ok=true, already)" \
  "[[ \"\$(field nic_ok)\" == true && \"\$(field converged_by)\" == already ]]"
W5C_CTR="$TMP/ip-calls.w5c"; printf '0' > "$W5C_CTR"
EXTRA_ENV=("STUB_IP_COUNTER=$W5C_CTR" STUB_IP_APPEAR_AT=31 "STUB_IP_OUT=$MID_IP_OUT")
run_guard true 0 true
assert "W-5c an address appearing on the LAST wait-loop probe is still found (nic_ok=true) after 32 ip calls: the loop bound is not shortened" \
  "[[ \"\$(field nic_ok)\" == true && \"\$(cat '$W5C_CTR')\" -eq 32 ]]"
W5D_CTR="$TMP/ip-calls.w5d"; printf '0' > "$W5D_CTR"
EXTRA_ENV=("STUB_IP_COUNTER=$W5D_CTR" STUB_IP_APPEAR_AT=32 "STUB_IP_OUT=$MID_IP_OUT")
run_guard true 0 true
assert "W-5d an address appearing one probe AFTER the loop ends is not found (detect-only, still 32 ip calls): the loop bound is not lengthened" \
  "[[ \"\$(field nic_ok)\" == false && \"\$(field converged_by)\" == detect-only && \"\$(cat '$W5D_CTR')\" -eq 32 ]]"
W7_CTR="$TMP/ip-calls.w7"; printf '0' > "$W7_CTR"
EXTRA_ENV=("STUB_IP_COUNTER=$W7_CTR" STUB_IP_APPEAR_AT=1 "STUB_IP_OUT=$MID_IP_OUT")
run_guard true 0 true
assert "W-7 an address present at the first probe is found by the trigger itself (nic_ok=true, already)" \
  "[[ \"\$(field nic_ok)\" == true && \"\$(field converged_by)\" == already ]]"
assert "W-7 exactly two ip calls: the trigger and the emit, so the wait loop did not run" \
  "[[ \"\$(cat '$W7_CTR')\" -eq 2 ]]"

# --- #9757 / ADR-280 (argv-bearer sweep PR C): the heartbeat URL rides curl's stdin config, never argv ----
# The beat URL is itself the credential (its path is the secret). Before this change it was the last
# positional of `beat()`, readable by every local user in /proc/<pid>/cmdline. It now reaches curl as one
# `url = "..."` line on `--config -`, after a shape judgement; a refused value makes ZERO requests, logs one
# value-free SOLEUR_CREDENTIAL_REFUSED marker per hour (own stamp under SOLEUR_NIC_TEST_ROOT/run), withholds
# the beat (so absence alarms) and leaves the Better Stack POST and the exit status alone.
echo "--- heartbeat URL transport: stdin config, per-attempt, positive controls ---"
HB_GOOD="https://synthetic.invalid/beat/web-nic-guard"
run_guard true 0 true
assert "HB healthy run: exactly one ping call and exactly one stdin url line (the stub saw the stdin)" \
  "[[ \"\$TA_PING\" -eq 1 && \"\$(grep -c '^url = ' \"\$STDIN_FILE\" || true)\" -eq 1 && \"\$PING\" == \"\$HB_GOOD\" ]]"
assert "HB healthy run: no marker, no WARN, nothing on stdout, exit 0" \
  "[[ \"\$ERR\" != *SOLEUR_CREDENTIAL_REFUSED* && \"\$ERR\" != *WARN* && -z \"\$OUT\" && \"\$RC\" -eq 0 ]]"
HB_PUNCT="https://synthetic.invalid/beat/A.b_c~d:9?x=1&y=%2B+z-Q"
EXTRA_ENV=("WEB_NIC_GUARD_URL=$HB_PUNCT")
run_guard true 0 true
assert "HB a different token using every permitted punctuation class beats once, on stdin only, unrefused (positive control)" \
  "[[ \"\$PING\" == \"\$HB_PUNCT\" && \"\$TA_PING\" -eq 1 && \"\$ERR\" != *SOLEUR_CREDENTIAL_REFUSED* ]] && ! grep -qF 'A.b_c' \"\$ARGV_FILE\""
EXTRA_ENV=(STUB_PING_RC=1)
run_guard true 0 true
assert "HB per-attempt: a failing first ping gives two ping calls, each with its OWN stdin url line (the second did not read EOF)" \
  "[[ \"\$TA_PING\" -eq 2 && \"\$(grep -c '^url = ' \"\$STDIN_FILE\" || true)\" -eq 2 && \"\$(grep '^url = ' \"\$STDIN_FILE\" | sort -u | wc -l)\" -eq 1 ]]"
assert "HB per-attempt: both attempts failing is a WARN with exit 0, never a refusal" \
  "[[ \"\$ERR\" == *'heartbeat ping FAILED'* && \"\$ERR\" != *SOLEUR_CREDENTIAL_REFUSED* && \"\$RC\" -eq 0 ]]"
assert "HB per-attempt: every ping used the golden argv with a zero tail (ALL transport rows stay clean)" "[[ \"\$TA_BAD\" -eq 0 ]]"
EXTRA_ENV=(WEB_NIC_GUARD_URL=)
run_guard true 0 true
assert "HB empty URL: no ping, no marker (the pre-existing absent-URL arm is not a refusal)" "no_beat && [[ \"\$ERR\" != *SOLEUR_CREDENTIAL_REFUSED* ]]"

# The hostile and malformed values are defined ONCE; ONE defect per row (the good URL plus one bad thing).
echo "--- heartbeat URL shape guard: one defect per row, zero pings, one marker, POST unaffected ---"
HB_LABELS=(empty-rest http-scheme uppercase-scheme leading-space trailing-space double-quote single-quote backslash newline-smuggled-url-directive carriage-return tab semicolon dollar backtick at-sign hash)
HB_VALUES=(
  "https://"
  "http://synthetic.invalid/beat/web-nic-guard"
  "HTTPS://synthetic.invalid/beat/web-nic-guard"
  " ${HB_GOOD}"
  "${HB_GOOD} "
  "${HB_GOOD}\""
  "${HB_GOOD}'"
  "${HB_GOOD}\\x"
  "${HB_GOOD}"$'\nurl = "https://evil.invalid/"'
  "${HB_GOOD}"$'\r'
  "${HB_GOOD}"$'\t'
  "${HB_GOOD};x"
  "${HB_GOOD}\$x"
  "${HB_GOOD}\`x"
  "https://u@synthetic.invalid/beat/web-nic-guard"
  "${HB_GOOD}#x"
)
HB_REASONS=(token_shape token_shape token_shape token_shape token_shape token_shape token_shape token_shape control_char control_char control_char token_shape token_shape token_shape token_shape token_shape)
assert "HB hostile list: 16 values, 16 labels, 16 reasons (the list is defined once and loops below)" \
  "[[ \"\${#HB_VALUES[@]}\" -eq 16 && \"\${#HB_LABELS[@]}\" -eq 16 && \"\${#HB_REASONS[@]}\" -eq 16 ]]"
assert "HB hostile list: the labels are exactly the sixteen defects named by the plan, in order" \
  "[[ \"\${HB_LABELS[*]}\" == 'empty-rest http-scheme uppercase-scheme leading-space trailing-space double-quote single-quote backslash newline-smuggled-url-directive carriage-return tab semicolon dollar backtick at-sign hash' ]]"
assert "HB hostile list: every value is distinct and none equals the good URL" \
  "[[ \"\$(printf '%s\\0' \"\${HB_VALUES[@]}\" | tr '\\0' '\\n' | wc -l)\" -ge 16 ]] && ! printf '%s\\0' \"\${HB_VALUES[@]}\" | grep -qzxF -- \"\$HB_GOOD\""
assert "HB hostile list: exactly three control-character reasons (newline, CR, tab), thirteen token-shape" \
  "[[ \"\$(printf '%s\\n' \"\${HB_REASONS[@]}\" | grep -c '^control_char\$' || true)\" -eq 3 && \"\$(printf '%s\\n' \"\${HB_REASONS[@]}\" | grep -c '^token_shape\$' || true)\" -eq 13 ]]"
assert "HB hostile list: the content carries the bytes it names (quote, apostrophe, backslash, newline, CR, tab, ;, \$, backtick, @, #)" \
  "[[ \"\${HB_VALUES[5]}\" == *'\"' && \"\${HB_VALUES[6]}\" == *\"'\" && \"\${HB_VALUES[7]}\" == *'\\'* && \"\${HB_VALUES[8]}\" == *\$'\\n'* && \"\${HB_VALUES[9]}\" == *\$'\\r' && \"\${HB_VALUES[10]}\" == *\$'\\t' && \"\${HB_VALUES[11]}\" == *';'* && \"\${HB_VALUES[12]}\" == *'\$'* && \"\${HB_VALUES[13]}\" == *'\`'* && \"\${HB_VALUES[14]}\" == *'@'* && \"\${HB_VALUES[15]}\" == *'#'* && \"\${HB_VALUES[3]}\" == ' '* && \"\${HB_VALUES[4]}\" == *' ' && \"\${HB_VALUES[0]}\" == 'https://' ]]"
for ((hi = 0; hi < ${#HB_VALUES[@]}; hi++)); do
  hl="${HB_LABELS[hi]}"; hv="${HB_VALUES[hi]}"; hr="${HB_REASONS[hi]}"
  EXTRA_ENV=("WEB_NIC_GUARD_URL=$hv")
  run_guard true 0 true
  assert "HB refused[$hl]: zero ping calls, no stdin url line, the beat is withheld (argv count, parsed URL and stdin all agree)" "no_beat"
  assert "HB refused[$hl]: exactly one marker with reason=$hr and the variable name" \
    "[[ \"\$(grep -c SOLEUR_CREDENTIAL_REFUSED <<<\"\$ERR\" || true)\" -eq 1 ]] && grep -qxF 'SOLEUR_CREDENTIAL_REFUSED script=web-private-nic-guard reason=$hr var=WEB_NIC_GUARD_URL' <<<\"\$ERR\""
  assert "HB refused[$hl]: the Better Stack POST is unaffected (one POST, the emit fired) and the exit is 0" \
    "[[ \"\$TA_POST\" -eq 1 && -n \"\$EMIT\" && \"\$RC\" -eq 0 ]]"
  assert "HB refused[$hl]: the value is echoed to neither stream, and the host is not either" \
    "[[ \"\$OUT\$ERR\" != *\"\$hv\"* && \"\$OUT\$ERR\" != *synthetic.invalid* && \"\$OUT\$ERR\" != *evil.invalid* ]]"
  assert "HB refused[$hl]: no credentialed curl was malformed and the bearer stayed on the POST (ALL_* verdicts hold per run)" "[[ \"\$TA_BAD\" -eq 0 && \"\$TA_BEARER_BAD\" -eq 0 ]]"
done
# A refusal is a property of a beat that WOULD have been sent: a broken NIC (or a guard that cannot report)
# already withholds it, so the judgement never runs and no marker is filed for a beat nobody attempted.
EXTRA_ENV=("WEB_NIC_GUARD_URL=${HB_GOOD}\"")
run_guard false 0 true
assert "HB a hostile URL on a broken NIC: no ping and no marker (the existing predicate is unchanged)" "no_beat && [[ \"\$ERR\" != *SOLEUR_CREDENTIAL_REFUSED* ]]"
EXTRA_ENV=("WEB_NIC_GUARD_URL=${HB_GOOD}\"" BETTERSTACK_LOGS_TOKEN=)
run_guard true 0 true
assert "HB a hostile URL when the guard cannot report: no ping and no marker (SHIP_REFUSED already withholds)" "no_beat && [[ \"\$ERR\" != *SOLEUR_CREDENTIAL_REFUSED* ]]"

# Refusal limiter: its OWN stamp under SOLEUR_NIC_TEST_ROOT/run, 3600 s, future-dated or garbage = emit and
# rewrite, unwritable = fail OPEN. FIXED_ROOT keeps the stamp across runs; markers are counted per run.
echo "--- heartbeat URL refusal limiter: own stamp, one marker per window ---"
HB_BAD="${HB_GOOD}\""
STAMP_NAME="web-private-nic-guard.refusal"
lim_run() {  # <root path under $TMP> -> leaves LIM_MARKERS (markers on this run's stderr)
  FIXED_ROOT="${1#"$TMP"/}"; EXTRA_ENV=("WEB_NIC_GUARD_URL=$HB_BAD")
  run_guard true 0 true
  LIM_MARKERS=$(grep -c SOLEUR_CREDENTIAL_REFUSED <<<"$ERR" || true)
}
LIM1="$TMP/lim1"; rm -rf "$LIM1"; mkdir -p "$LIM1"
lim_total=0; lim_pings=0; lim_posts=0; lim_first=""
for _ in 1 2 3 4; do
  lim_run "$LIM1"
  lim_total=$((lim_total + LIM_MARKERS)); lim_pings=$((lim_pings + TA_PING)); lim_posts=$((lim_posts + TA_POST))
  [[ -n "$lim_first" ]] || lim_first=$LIM_MARKERS
done
assert "HB limiter: four refused runs inside one window log exactly one marker (the first run), never a second" \
  "[[ \"\$lim_total\" -eq 1 && \"\$lim_first\" -eq 1 ]]"
assert "HB limiter: the suppressed runs still made zero pings and still POSTed (the limiter silences the marker, nothing else)" \
  "[[ \"\$lim_pings\" -eq 0 && \"\$lim_posts\" -eq 4 ]]"
assert "HB limiter: the stamp is one numeric epoch written under the test root" \
  "[[ \"\$(cat '$LIM1/run/$STAMP_NAME')\" =~ ^[0-9]{10}\$ ]]"
assert "HB limiter: the suppressed runs also withheld the WARN (marker and WARN sit inside the limiter together)" \
  "[[ \"\$ERR\" != *'heartbeat URL refused'* ]]"

lim_seed() {  # <root path under $TMP> <age seconds | literal> -> seeds the refusal stamp
  local v="$2" stamp
  mkdir -p "$TMP/${1#"$TMP"/}/run"; stamp="$TMP/${1#"$TMP"/}/run/$STAMP_NAME"
  if [[ "$v" =~ ^-?[0-9]+$ ]]; then printf '%s\n' "$(( $(date +%s) - v ))" > "$stamp"; else printf '%s\n' "$v" > "$stamp"; fi
}
LIM2="$TMP/lim2"; rm -rf "$LIM2"; lim_seed "$LIM2" 2000; LIM2_SEED=$(cat "$LIM2/run/$STAMP_NAME")
lim_run "$LIM2"
assert "HB limiter: a stamp aged 2000 s suppresses (the window is 3600 s, not the 1800 s of the zot canary)" \
  "[[ \"\$LIM_MARKERS\" -eq 0 && \"\$(cat '$LIM2/run/$STAMP_NAME')\" == \"\$LIM2_SEED\" ]]"
assert "HB limiter: the suppressed run still withheld the beat" "no_beat"
LIM3="$TMP/lim3"; rm -rf "$LIM3"; lim_seed "$LIM3" 3700; LIM3_SEED=$(cat "$LIM3/run/$STAMP_NAME")
lim_run "$LIM3"
assert "HB limiter: a stamp aged 3700 s re-emits one marker and the stamp is rewritten to now" \
  "[[ \"\$LIM_MARKERS\" -eq 1 && \"\$(cat '$LIM3/run/$STAMP_NAME')\" != \"\$LIM3_SEED\" && \$(( \$(date +%s) - \$(cat '$LIM3/run/$STAMP_NAME') )) -lt 60 ]]"
LIM4="$TMP/lim4"; rm -rf "$LIM4"; lim_seed "$LIM4" -100000; LIM4_SEED=$(cat "$LIM4/run/$STAMP_NAME")
lim_run "$LIM4"
assert "HB limiter: a future-dated stamp is read as 'emit' and rewritten (a clock step must not mute the marker for good)" \
  "[[ \"\$LIM_MARKERS\" -eq 1 && \"\$(cat '$LIM4/run/$STAMP_NAME')\" != \"\$LIM4_SEED\" && \$(( \$(date +%s) - \$(cat '$LIM4/run/$STAMP_NAME') )) -lt 60 ]]"
LIM5="$TMP/lim5"; rm -rf "$LIM5"; lim_seed "$LIM5" "not-an-epoch"
lim_run "$LIM5"
assert "HB limiter: a garbage stamp is read as 'emit' and rewritten to a numeric epoch" \
  "[[ \"\$LIM_MARKERS\" -eq 1 && \"\$(cat '$LIM5/run/$STAMP_NAME')\" =~ ^[0-9]{10}\$ ]]"
LIM5B="$TMP/lim5b"; rm -rf "$LIM5B"; lim_seed "$LIM5B" "99999999999999999999"
lim_run "$LIM5B"
assert "HB limiter: an over-long numeric stamp is read as 'emit' (no arithmetic overflow suppresses the marker)" \
  "[[ \"\$LIM_MARKERS\" -eq 1 && \"\$(cat '$LIM5B/run/$STAMP_NAME')\" =~ ^[0-9]{10}\$ ]]"
LIM6="$TMP/lim6"; rm -rf "$LIM6"; mkdir -p "$LIM6/run"
for other in web-zot-consumer-probe.refusal inngest-consumer-probe.refusal web-zot-consumer-probe web-private-nic-guard.dark web-private-nic-guard; do
  printf '%s\n' "$(date +%s)" > "$LIM6/run/$other"
done
LIM6_BEFORE=$(cat "$LIM6"/run/* | md5sum | cut -d' ' -f1)
lim_run "$LIM6"
assert "HB limiter: fresh stamps of other scripts or limiters do NOT suppress this marker (the refusal stamp is its own file)" "[[ \"\$LIM_MARKERS\" -eq 1 ]]"
LIM6_AFTER=$(cd "$LIM6/run" && cat $(ls | grep -vxF "$STAMP_NAME") | md5sum | cut -d' ' -f1)
assert "HB limiter: the run wrote only its own stamp (one new file) and left every other stamp byte-identical" \
  "[[ \"\$(ls '$LIM6/run' | wc -l)\" -eq 6 && -f '$LIM6/run/$STAMP_NAME' && \"\$LIM6_AFTER\" == \"\$LIM6_BEFORE\" ]]"
LIM7="$TMP/lim7"; rm -rf "$LIM7"; mkdir -p "$LIM7/run/$STAMP_NAME"
lim_run "$LIM7"; lim7_first=$LIM_MARKERS; lim7_rc=$RC; lim7_err_noise=$(grep -c -e 'Is a directory' -e 'Permission denied' <<<"$ERR" || true)
lim_run "$LIM7"; lim7_second=$LIM_MARKERS
assert "HB limiter: an unwritable stamp path fails OPEN (a marker on every run, loud rather than silent)" \
  "[[ \"\$lim7_first\" -eq 1 && \"\$lim7_second\" -eq 1 ]]"
assert "HB limiter: the unwritable stamp costs no exit status and leaks no shell error text" \
  "[[ \"\$lim7_rc\" -eq 0 && \"\$RC\" -eq 0 && \"\$lim7_err_noise\" -eq 0 ]]"
LIM8="$TMP/lim8"; rm -rf "$LIM8"; mkdir -p "$LIM8"
FIXED_ROOT="${LIM8#"$TMP"/}"; EXTRA_ENV=("WEB_NIC_GUARD_URL=$HB_BAD"); run_guard true 0 true
assert "HB limiter: the stamp lives under SOLEUR_NIC_TEST_ROOT (nothing leaked to the real /run in a test)" \
  "[[ -f '$LIM8/run/$STAMP_NAME' ]]"

# --- static: the shape of the converted transport -----------------------------------------------------
echo "--- static: one guarded stdin config line, class before it, no argv URL ---"
HB_CLASS='[!A-Za-z0-9._~:/?\&=%+-]'
assert "static: the guard class literal appears exactly once in the file (non-comment code)" \
  "[[ \"\$(grep -cF -- \"\$HB_CLASS\" <<<\"\$STRIPPED\" || true)\" -eq 1 ]]"
assert "static: exactly one stdin config line carries a url = \" directive" \
  "[[ \"\$(grep -cF 'url = \"' <<<\"\$STRIPPED\" || true)\" -eq 1 ]]"
assert "static: the class literal sits on a line BEFORE the url config line" \
  "[[ \"\$(grep -nF -- \"\$HB_CLASS\" '$SUT' | sed -n '1p' | cut -d: -f1)\" -lt \"\$(grep -nF 'url = \"' '$SUT' | sed -n '1p' | cut -d: -f1)\" ]]"
assert "static: the beat curl is the --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config - form" \
  "grep -qF -- \"curl --disable --noproxy '*' -gfsS -m 10 -o /dev/null --config -\" <<<\"\$STRIPPED\""
assert "static: no code line carrying a curl word names the heartbeat URL variable (the one transport line takes it via printf on stdin)" \
  "[[ \"\$(grep -E 'curl' <<<\"\$STRIPPED\" | grep -E '\\\$\\{?URL\\}?\\b' | grep -vF 'printf' | wc -l)\" -eq 0 ]]"
assert "static: _hb_url_ok is called before the transport and the transport is called twice (the || fallback)" \
  "grep -qF '_hb_url_ok \"\$URL\"' <<<\"\$STRIPPED\" && [[ \"\$(grep -cF '_hb_curl ||' <<<\"\$STRIPPED\" || true)\" -ge 1 ]]"
assert "static: the comment no longer claims the URL rides argv, and still names #9639 for the unit expansion" \
  "! grep -qF \"still rides curl's argv\" '$SUT' && grep -qF '#9639' '$SUT'"
assert "static: no set -e was added (a failed beat or refusal must never change the exit status)" \
  "! grep -qE '^[[:space:]]*set -[a-z]*e' <<<\"\$STRIPPED\""

# --- every run, one verdict ------------------------------------------------------------------
assert "no run anywhere issued a curl missing --disable-first or --noproxy '*' (ALL_TA_BAD=$ALL_TA_BAD)" "[[ \"\$ALL_TA_BAD\" -eq 0 ]]"
assert "in no run did the bearer reach anything but the pinned POST, once per POST (ALL_BEARER_BAD=$ALL_BEARER_BAD)" "[[ \"\$ALL_BEARER_BAD\" -eq 0 ]]"

# Accounting identity, then the anti-vacuity floor. Reported by printf + exit, never through assert() or the
# verdict helpers they backstop (ADR-193); the case counter moves in assert(), not in _pass/_fail.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting identity: PASS(%d) + FAIL(%d) != CASES(%d). An assertion recorded no verdict or more than one.\n' "$PASS" "$FAIL" "$CASES" >&2
  exit 1
fi
MIN_CASES=289
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  printf '[FATAL] anti-vacuity floor: only %d assertions ran; floor is %d\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
