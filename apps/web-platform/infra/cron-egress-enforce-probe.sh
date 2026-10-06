#!/usr/bin/env bash
# Fresh-host POST-CONTAINER egress-enforcement probe (#5933 item 3).
#
# WHY THIS EXISTS SEPARATELY FROM cron-egress-postapply-assert.sh:
# The sibling post-apply assertion (cron-egress-postapply-assert.sh) is run by the
# web-1 SSH provisioner (terraform_data.cron_egress_firewall, server.tf) and on a
# FRESH host it SKIPS the container probes ("soleur-web-platform not running —
# enforcement probes SKIPPED (fresh-host bootstrap)"), deferring proof to "the next
# apply after deploy". On the cloud-init-only web-2 path there IS no SSH re-apply, so
# that proof never lands — a non-enforcing (inert) container-egress ruleset would serve
# silently. `nft -f` exits 0 on an inert ruleset; only a REAL in-container positive+
# negative probe proves enforcement (#5046 threat). This probe runs at boot AFTER the
# app container starts (invoked from cloud-init.yml's terminal block) and is NOT
# skippable — the container IS up when it runs.
#
# FAIL-CLOSED: on ANY failure this script emits a discriminating Sentry event (SSH-free
# root-cause signal, mirroring soleur-host-bootstrap.sh's emit_fail envelope + a
# probe_result tag that names WHICH hypothesis fired) then exits non-zero. The cloud-init
# caller `poweroff -f`s on that non-zero exit, so a host whose container egress is not
# provably enforcing NEVER stays up serving (an open exfil path is worse than an absent
# host — the absence is what the per-host uptime detector, #5933 item 1, pages on). A
# `trap emit_fail EXIT` (disarmed on the clean-success path) also catches an UNANTICIPATED
# errexit abort so it still emits a signal (probe_result=unknown) instead of going dark.
#
# set -e FIRST (same rationale as cron-egress-postapply-assert.sh): a bare `bash script.sh`
# is one shell with no implicit errexit. The enforcement probes capture the curl exit code
# explicitly (`|| rc=$?`) so errexit does not abort before the exit-code discrimination.
set -e

CONTAINER=soleur-web-platform
STAGE=egress-enforce
PROBE_RESULT=unknown
# Strip `"` and `\` (JSON-structural) then any non-printable (newlines/control) BEFORE the
# value is interpolated into the Sentry JSON body — instance-id/hostname is cloud-metadata,
# not attacker-controlled, but a stray backslash/newline would corrupt the event envelope.
HOST_ID=$( (cat /var/lib/cloud/data/instance-id 2>/dev/null || hostname) | tr -d '"\\' | tr -cd '[:print:]' )

# Best-effort SSH-free discriminating signal, byte-compatible (TRANSPORT lines) with the
# soleur-host-bootstrap.sh emit_fail envelope (tags: stage / failed_file / host_id) plus
# a probe_result tag that discriminates ALL competing root-cause hypotheses in ONE event
# (#5933 §2.9.2 blind-surface): negative_fail (under-enforcing = the exfil hole),
# negative_inconclusive (could not prove DROP → fail-closed), positive_fail (over-blocking),
# structure_fail (unit/chain missing), container_absent. DSN via the on-host Doppler token
# written to /etc/default/webhook-deploy. Never fatal. Disarms the EXIT trap first so an
# explicit `emit_fail; exit 1` does not re-fire it, and a clean exit does not emit.
emit_fail() {
  trap - EXIT
  ( set +e
    . /etc/default/webhook-deploy 2>/dev/null || true
    DSN=$(timeout 15 doppler secrets get SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || timeout 15 doppler secrets get NEXT_PUBLIC_SENTRY_DSN --plain --project soleur --config prd 2>/dev/null \
          || true)
    if [ -n "$DSN" ]; then
      KEY=$(printf '%s' "$DSN" | sed -E 's#https://([^@]+)@.*#\1#')
      SHOST=$(printf '%s' "$DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
      PROJ=$(printf '%s' "$DSN" | sed -E 's#.*/([0-9]+)$#\1#')
      BODY=$(printf '{"message":"soleur egress-enforce probe failed","level":"fatal","tags":{"stage":"%s","failed_file":"cron-egress-enforce-probe.sh","host_id":"%s","probe_result":"%s"}}' "$STAGE" "$HOST_ID" "$PROBE_RESULT")
      curl -m 10 --retry 3 -sf -X POST "https://$SHOST/api/$PROJ/store/" \
        -H 'Content-Type: application/json' \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$KEY" \
        -d "$BODY" >/dev/null 2>&1 || true
    fi ) || true
}
trap emit_fail EXIT

# 1. Container readiness — bounded wait (the container starts moments before this runs;
#    a missing container is itself a failure, not a skip, on this path).
N=0
until docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; do
  N=$((N + 1))
  if [ "$N" -ge 30 ]; then
    PROBE_RESULT=container_absent
    echo "ASSERT-FAILED: container-absent ($CONTAINER not running within readiness window)"
    emit_fail
    exit 1
  fi
  sleep 2
done

# 2. Structure — the egress chain must be wired and the loader unit active BEFORE trusting
#    the behavioral probes (a missing jump would make the negative probe pass for the wrong
#    reason). `nft`/`systemctl` failures here mean the firewall never came up.
if ! nft list chain ip filter DOCKER-USER 2>/dev/null | grep -q 'jump SOLEUR-EGRESS'; then
  PROBE_RESULT=structure_fail
  echo 'ASSERT-FAILED: docker-user-jump (SOLEUR-EGRESS jump absent from DOCKER-USER)'
  emit_fail
  exit 1
fi
if ! systemctl is-active cron-egress-firewall.service >/dev/null 2>&1; then
  PROBE_RESULT=structure_fail
  echo 'ASSERT-FAILED: firewall-not-active (cron-egress-firewall.service not active)'
  emit_fail
  exit 1
fi

# 3. ENFORCEMENT — the only proof an inert ruleset cannot fake.
#    positive: an allowlisted host is reachable FROM INSIDE the container. `--retry 3` so a
#    transient api.github.com/DNS hiccup at cold boot does not trigger a DESTRUCTIVE
#    poweroff (this is an availability call — retrying does NOT weaken the security property).
if ! docker exec "$CONTAINER" curl -s -o /dev/null --max-time 20 --retry 3 https://api.github.com; then
  PROBE_RESULT=positive_fail
  echo 'ASSERT-FAILED: egress-probe-positive (allowlisted host unreachable from container — over-blocking)'
  emit_fail
  exit 1
fi
echo egress-probe-positive-ok

#    negative: a NON-allowlisted host must be DROPPED. The loader's default rule is nftables
#    `drop` (silent discard), so an ENFORCING ruleset makes the connect hang until --max-time
#    → curl exit 28 (timeout). Discriminate exit codes so ONLY exit 28 counts as "enforcing":
#      - exit 0  → reachable → ruleset is INERT (the exfil hole)      → fail-closed poweroff
#      - exit 28 → timed out → dropped by the firewall (enforcing)    → healthy pass
#      - other   → DNS(6)/refused(7)/docker-exec-infra(125/126)/…     → INCONCLUSIVE, cannot
#                  prove a DROP → fail-closed (an inert ruleset coincident with a transient
#                  example.com failure must NOT slip through as a silent pass).
#    Single-shot on purpose (NO --retry): a retry could mask a real open path.
neg_rc=0
docker exec "$CONTAINER" curl -s -o /dev/null --max-time 8 https://example.com || neg_rc=$?
if [ "$neg_rc" -eq 0 ]; then
  PROBE_RESULT=negative_fail
  echo 'ASSERT-FAILED: egress-probe-negative (ruleset INERT — non-allowlisted host reachable from container)'
  emit_fail
  exit 1
elif [ "$neg_rc" -ne 28 ]; then
  PROBE_RESULT=negative_inconclusive
  echo "ASSERT-FAILED: egress-probe-negative-inconclusive (curl exit $neg_rc != 28/timeout — cannot prove DROP; fail-closed)"
  emit_fail
  exit 1
fi
echo egress-probe-negative-ok

PROBE_RESULT=ok
trap - EXIT   # disarm: a clean success must NOT emit a fatal event
echo egress-enforce-ok
