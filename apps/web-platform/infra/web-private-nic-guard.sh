#!/usr/bin/env bash
set -u
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
ip_present=false
if [ "$PROBE_OK" = true ] && "$IP_BIN" -4 -o addr show 2>/dev/null | grep -qwF -- "$EXPECTED_IP"; then ip_present=true; fi
# (2) Bounded wait — the attach can land AFTER boot (the registry guard's H2). Only runs when the
# IP is already absent. ~30 x 2s.
if [ "$ip_present" = false ] && [ "$PROBE_OK" = true ]; then
  for i in $(seq 1 30); do
    sleep 2
    if "$IP_BIN" -4 -o addr show 2>/dev/null | grep -qwF -- "$EXPECTED_IP"; then ip_present=true; break; fi
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
  printf '%s\n' "$IMDS_BODY" | grep -qE "^[[:space:]]*-?[[:space:]]*ip:[[:space:]]*$EXPECTED_IP[[:space:]]*$" && IMDS_HAS_EXPECTED=true
fi
printf '%s' "$IMDS_NETS" | grep -qE '^[0-9]+$' || IMDS_NETS=0
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
if [ -n "$TOKEN" ] && [ -n "$INGEST_URL" ]; then
  post() { curl -fsS -m 10 -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$INGEST_URL" --data-raw "{\"message\":\"$LINE\"}" >/dev/null 2>&1; }
  post || post || echo "[nic] SOLEUR_PRIVATE_NIC egress to Better Stack Logs FAILED: $LINE" >&2
else
  echo "[nic] WARN: BETTERSTACK_LOGS_TOKEN/BETTERSTACK_INGEST_URL unset (run under 'doppler run --project soleur --config prd', source /etc/default/web-private-nic-guard) — SOLEUR_PRIVATE_NIC not shipped: $LINE" >&2
fi
# (7) Liveness heartbeat — ping the dedicated web_nic_guard beat on EVERY healthy run so the fault-
# emitter is observable-when-healthy (a SOLEUR_PRIVATE_NIC emit that never fires is indistinguishable
# from "guard dead"). Ping ONLY when nic_ok — a NIC-broken host must let the beat lapse so absence
# alarms. Independent unit/failure-domain from the zot beat (folding would re-introduce OR-masking).
URL="${WEB_NIC_GUARD_URL:-}"
if [ "$NIC_OK" = true ] && [ -n "$URL" ]; then
  curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null || curl -fsS -m 10 -o /dev/null "$URL" 2>/dev/null || echo "[nic] WARN: web_nic_guard heartbeat ping FAILED (nic_ok=true, url_present=yes)" >&2
fi
# NO reboot. The web-host variant terminates here by design.
exit 0
