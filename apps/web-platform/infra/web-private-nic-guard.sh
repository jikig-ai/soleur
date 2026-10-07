#!/usr/bin/env bash
set -u
# Refuse to run under xtrace (#7797): this guard handles a Better Stack bearer token and a secret
# heartbeat URL (WEB_NIC_GUARD_URL), so tracing would print them. Unconditional on purpose: it is not
# keyed on a credential name, which no name rule can see for the heartbeat URL. It tests the STATE
# (`$-`), so `bash -x`, SHELLOPTS=xtrace and a BASH_ENV `set -x` are all caught. The guard therefore
# cannot be traced on-host by design: read its stderr via `journalctl -t web-nic-guard` (shipped to
# Better Stack by Vector), and run web-private-nic-guard.test.sh to observe it against stubs.
# LIMIT: this covers the script's own commands. The unit's ExecStart wrapper expands the secret
# heartbeat URL in an inner `bash -c` before this check can run (tracked as #9639).
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
# --- #6438 §3 / ADR (web-host variant): private-NIC self-report, NO self-converge ------------
# Web-host port of soleur-private-nic-guard.sh (cloud-init-registry.yml). It DIVERGES from the
# registry guard in ONE deliberate way: it NEVER reboots. ADR-115's two normative reboot-blockers
# earn the registry ONE host's self-reboot authority; on a web host a reboot would power-off the
# SOLE live origin (apply-web-platform-infra.yml:878), so the web variant is detect + emit + alarm
# ONLY. Everything else (probe resolution, local-fact trigger, IMDS corroboration as telemetry,
# emit-always) is preserved so the two guards read as one family.
#
# CONFIG IS ENV, NOT TEMPLATE. Unlike the registry guard (baked via cloud-init templatefile, so its
# ${private_ip}/${betterstack_ingest_url} are TF interpolations), this ONE file is delivered BOTH
# ways — an SSH `terraform_data` provisioner ships it to the unrebuildable web-1, and cloud-init
# bakes it verbatim (as a templatefile VARIABLE, not inline) for future hosts (#6459). So it reads
# every per-host value from /etc/default/web-private-nic-guard (EXPECTED_IP, BETTERSTACK_INGEST_URL)
# + the doppler-run env (BETTERSTACK_LOGS_TOKEN, WEB_NIC_GUARD_URL). No TF `$${...}` escaping —
# plain bash — so the byte-identical file survives both delivery routes with zero drift.
#
# Registry-specific machinery is INTENTIONALLY ABSENT: the zot store-mount self-heal + `docker
# restart zot` (registry §3) has no analogue on a web host, and the reboot budget/counter existed
# only to bound a converge action this variant does not take.
#
# SOLEUR_NIC_TEST_ROOT is the ONLY FS-read seam (mirrors the registry guard's): it re-roots reads so
# web-private-nic-guard.test.sh can execute this exact body against synthesized fixtures without
# root. The cron/boot invocation NEVER sets it; unset (production) it resolves to the real FS.
EXPECTED_IP="${EXPECTED_IP:-}"
R="${SOLEUR_NIC_TEST_ROOT:-}"
if [ -z "$EXPECTED_IP" ]; then
  echo "[nic] FATAL: EXPECTED_IP unset (source /etc/default/web-private-nic-guard) — cannot assert the private NIC without the expected address." >&2
  exit 1
fi
# (0) PROBE RESOLUTION — load-bearing, and the reason this guard declares its own PATH. `ip` lives
# in /usr/sbin, which is NOT on cron's default PATH (/usr/bin:/bin). Resolve explicitly and FAIL
# SAFE: a missing probe means we have NO local fact — "the probe never ran" must never be conflated
# with "the IP is absent". (The registry guard's reboot gate made this fatal; here it only governs
# the emitted converged_by classification, but the doctrine — never assert absence on zero evidence
# — is preserved.)
IP_BIN=$(command -v ip 2>/dev/null || true)
PROBE_OK=true; [ -n "$IP_BIN" ] && [ -x "$IP_BIN" ] || PROBE_OK=false
# (1) Trigger predicate — the LOCAL FACT ALONE. IMDS is telemetry and corroboration, NEVER the
# trigger. -w + -F: exact word, fixed string — so 10.0.1.1 can never match inside 10.0.1.10, and
# dots are not treated as regex wildcards.
# The grep predicates in this script read the whole stream (grep -c, count discarded) so a producer never takes
# EPIPE. It sets no pipefail today; this keeps the exit status identical if one is added or inherited via
# SHELLOPTS. See the header of .claude/hooks/grep-q-pipe-guard.test.sh.
ip_present=false
if [ "$PROBE_OK" = true ] && "$IP_BIN" -4 -o addr show 2>/dev/null | grep -cwF -- "$EXPECTED_IP" >/dev/null; then ip_present=true; fi
# (2) Bounded wait — the attach can land AFTER boot (the registry guard's H2). Only runs when the
# IP is already absent. ~30 x 2s.
if [ "$ip_present" = false ] && [ "$PROBE_OK" = true ]; then
  for i in $(seq 1 30); do
    sleep 2
    if "$IP_BIN" -4 -o addr show 2>/dev/null | grep -cwF -- "$EXPECTED_IP" >/dev/null; then ip_present=true; break; fi
  done
fi
# (3) Facts (pure reads).
UPTIME_S=$(awk '{printf "%d", $1}' "$R/proc/uptime" 2>/dev/null); [ -n "$UPTIME_S" ] || UPTIME_S=0
BOOT_ID=$(cat "$R/proc/sys/kernel/random/boot_id" 2>/dev/null); [ -n "$BOOT_ID" ] || BOOT_ID=unknown
# (4) Diagnose via IMDS. EXIT-CODE-NEUTRALIZED: a nonzero curl exit is a VALID data outcome (it is
# literally the IMDS-blip hypothesis), so it must never abort the script or read as an error.
IMDS_RC=0
IMDS_BODY=$(curl -sf -m 5 http://169.254.169.254/hetzner/v1/metadata/private-networks 2>/dev/null) || IMDS_RC=$?
IMDS_NETS=0
IMDS_HAS_EXPECTED=false
if [ "$IMDS_RC" -eq 0 ] && [ -n "$IMDS_BODY" ]; then
  IMDS_NETS=$(printf '%s\n' "$IMDS_BODY" | grep -cE '^[[:space:]]*network_id:' || true)
  # Corroborate on the EXPECTED ADDRESS, not merely "some network is attached" — a drifted
  # EXPECTED_IP would otherwise be corroborated by an unrelated attach. The `-?` is load-bearing:
  # IMDS returns a YAML LIST, so the address line is `- ip: <addr>` on the first key of each entry.
  printf '%s\n' "$IMDS_BODY" | grep -cE "^[[:space:]]*-?[[:space:]]*ip:[[:space:]]*$EXPECTED_IP[[:space:]]*$" >/dev/null && IMDS_HAS_EXPECTED=true
fi
printf '%s' "$IMDS_NETS" | grep -cE '^[0-9]+$' >/dev/null || IMDS_NETS=0
# (5) Classify — NO converge action. converged_by records what the registry guard WOULD have done,
# so the two telemetry streams stay comparable, but nic-absent terminates at `detect-only` here:
# the web host never power-cycles the sole origin. imds_has_expected feeds the emit for H1/H2/third-
# mode discrimination even though it drives no action.
NIC_OK=false
CONVERGED_BY=none
if [ "$PROBE_OK" != true ]; then
  CONVERGED_BY=probe-fault
elif [ "$ip_present" = true ]; then
  NIC_OK=true
  CONVERGED_BY=already
else
  # NIC absent. On the registry this is where a bounded reboot fires; on a web host it does NOT.
  # Emit the fault and alarm — the operator/HA path (#6459) owns remediation, not this guard.
  CONVERGED_BY=detect-only
fi
# (6) Emit ALWAYS — success AND failure. The field set discriminates every competing hypothesis in
# ONE event (imds_rc!=0 -> IMDS blip; imds_rc=0 && imds_nets=0 -> structural attach race;
# imds_nets>0 && !already -> attach landed, guest never configured it). zot_last_err is LAST and
# free-text (the registry parse lib strips the literal ` zot_last_err=` tail to bound the trusted
# region), carrying the host's actual v4 addresses — exactly what to read when nic_ok=false.
# `reboot_count=0` is emitted as a CONSTANT so the field set stays schema-identical to the registry
# guard's while making the no-reboot invariant self-evident in every web-host beat.
NIC_ADDRS=$(ip -4 -o addr show 2>/dev/null | awk '{print $2":"$4}' | tr '\n' ' ' | tail -c 200 | LC_ALL=C tr -cd '\40-\176' | tr -d '"\\'); [ -n "$NIC_ADDRS" ] || NIC_ADDRS=none
LINE="SOLEUR_PRIVATE_NIC nic_ok=$NIC_OK converged_by=$CONVERGED_BY imds_rc=$IMDS_RC imds_nets=$IMDS_NETS imds_has_expected=$IMDS_HAS_EXPECTED reboot_count=0 zot_store_mounted=n/a uptime_s=$UPTIME_S boot_id=$BOOT_ID zot_last_err=$NIC_ADDRS"
TOKEN="${BETTERSTACK_LOGS_TOKEN:-}"
INGEST_URL="${BETTERSTACK_INGEST_URL:-}"
# The bearer token goes ONLY to this one Better Stack source. Equals local.betterstack_logs_ingest_url
# in zot-registry.tf (and INGEST_URL_PINNED in soleur-host-bootstrap.sh); web-private-nic-guard.test.sh
# reads the .tf at test time and reds on drift, and betterstack-ingest-parity.test.sh counts every copy.
# readonly + a plain literal: an exported INGEST_URL_PINNED is overwritten here.
readonly INGEST_URL_PINNED="https://s2457081.eu-fsn-3.betterstackdata.com/"
# The token is spliced into curl CONFIG grammar below, so a value holding a quote, backslash or newline
# would add directives (`url =`, `header =`, `next`). Real Better Stack tokens are plain alphanumerics:
# anything else is refused rather than escaped.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
# SHIP_REFUSED=true when this run could not even attempt to report (token or URL unset, URL unpinned, token
# malformed). The heartbeat below is then withheld: a guard that cannot report must not claim health, so the
# beat lapses and the absence alarm names the guard. A POST that was ATTEMPTED and failed (Better Stack down)
# does not set it: that is an outage of the destination, and the beat's own network path fails with it.
SHIP_REFUSED=false
if [ -n "$TOKEN" ] && ! _bearer_ok "$TOKEN"; then
  SHIP_REFUSED=true
  echo "[nic] bad_token: BETTERSTACK_LOGS_TOKEN has characters outside the token alphabet; refusing to build a curl config from it — SOLEUR_PRIVATE_NIC not shipped: $LINE" >&2
elif [ -n "$TOKEN" ] && [ "$INGEST_URL" = "$INGEST_URL_PINNED" ]; then
  # --disable first (skip ~/.curlrc) and --noproxy '*' (ignore proxy env vars): the bearer must not
  # leave through a config file or a proxy the environment names.
  # The bearer rides a stdin config (`--config -`), never the argument list: argv is readable by every
  # local user in /proc/<pid>/cmdline and `ps` (lint Rule E, sweep #7843).
  post() { curl --disable --noproxy '*' -fsS -m 10 -H 'Content-Type: application/json' --config - "$INGEST_URL" --data-raw "{\"message\":\"$LINE\"}" < <(printf 'header = "Authorization: Bearer %s"\n' "$TOKEN") >/dev/null 2>&1; }
  post || post || echo "[nic] SOLEUR_PRIVATE_NIC egress to Better Stack Logs FAILED: $LINE" >&2
elif [ -n "$TOKEN" ] && [ -n "$INGEST_URL" ]; then
  SHIP_REFUSED=true
  echo "[nic] unpinned_url: refusing to send the Better Stack token to an unpinned destination — SOLEUR_PRIVATE_NIC not shipped: $LINE" >&2
else
  SHIP_REFUSED=true
  echo "[nic] WARN: BETTERSTACK_LOGS_TOKEN/BETTERSTACK_INGEST_URL unset (run under 'doppler run --project soleur --config prd', source /etc/default/web-private-nic-guard) — SOLEUR_PRIVATE_NIC not shipped: $LINE" >&2
fi
# (7) Liveness heartbeat — ping the dedicated web_nic_guard beat on EVERY healthy run so the fault-
# emitter is observable-when-healthy (a SOLEUR_PRIVATE_NIC emit that never fires is indistinguishable
# from "guard dead"). Ping ONLY when nic_ok AND the guard could report (not SHIP_REFUSED) — a NIC-broken
# host, or a guard that cannot ship, must let the beat lapse so absence alarms. Decode a missing beat by
# reading the guard's stderr in Better Stack (`bad_token` / `unpinned_url` / `WARN` vs `nic_ok=false`). Independent unit/failure-domain from the zot beat (folding would re-introduce OR-masking).
URL="${WEB_NIC_GUARD_URL:-}"
# The ping URL is itself the secret and still rides curl's argv (tracked as #9639); the flags confine it.
beat() { curl --disable --noproxy '*' -fsS -m 10 -o /dev/null "$URL" 2>/dev/null; }
if [ "$NIC_OK" = true ] && [ "$SHIP_REFUSED" = false ] && [ -n "$URL" ]; then
  beat || beat || echo "[nic] WARN: web_nic_guard heartbeat ping FAILED (nic_ok=true, url_present=yes)" >&2
fi
# NO reboot. The web-host variant terminates here by design.
exit 0
