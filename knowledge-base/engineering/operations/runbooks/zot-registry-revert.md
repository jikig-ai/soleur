---
title: Revert the zot pull-site flip to GHCR-primary
issue: "#6122"
adr: ADR-093
severity: P1 (deploy/boot path)
last_reviewed: 2026-07-07
---

# Revert the zot pull-site flip → GHCR-primary (#6122 / ADR-093)

The Phase-3 pull-site migration is **dark-launch gated**: every pull site (ci-deploy.sh
rolling deploy, soleur-host-bootstrap.sh + cloud-init.yml fresh boot) prefers the
self-hosted zot registry **only when `ZOT_REGISTRY_URL` is present in Doppler `prd` AND a
fast `/v2/` probe answers AND the pull login succeeds**. Any miss falls straight through to
the unchanged private-GHCR path. **This makes revert a Doppler flag flip — no code deploy,
no SSH, no host mutation.** GHCR remains dual-pushed + break-glass through the entire soak
(the interim classic PAT stays live until Phase 5.5), so the fallback registry is always
warm and current.

## When to revert

- The **fallback-rate alarm** fires (see below): a spike of `registry:"ghcr-fallback"` /
  `stage:"inngest_ghcr_fallback"` events means hosts are *trying* zot and failing — every
  such deploy/boot took the slower fallback path and zot is degraded.
- zot host down / unreachable / R2-backed storage fault / cert/htpasswd rotation broke pull
  auth, and you want to stop hosts from attempting zot at all (each attempt adds a probe +
  a failed pull before falling back).
- Any Phase-5 retirement step (5.3 fallback-branch removal) is discovered premature.

Note: a *single* transient `ghcr-fallback` is self-healing — the host already fell back to
GHCR and served correctly. Revert is for a *sustained* zot degradation, not one blip.

## Immediate revert (≈30 s, no deploy) — unset the gate

Removing `ZOT_REGISTRY_URL` from Doppler `prd` makes `zot_gate_and_login` /
the cloud-init + bootstrap gates short-circuit to GHCR on the **next** pull:

```bash
doppler secrets delete ZOT_REGISTRY_URL --project soleur --config prd --yes
# verify it is gone (empty output):
doppler secrets get ZOT_REGISTRY_URL --plain --project soleur --config prd 2>/dev/null || echo "unset ✓"
```

Effect, with no further action:
- **Rolling deploys** (`ci-deploy.sh`): the next `deploy` webhook resolves `ZOT_REGISTRY_URL`
  empty → `ZOT_ACTIVE=0` → the unchanged private-GHCR pull. No fallback attempt, no probe.
- **Fresh boots** (cloud-init/bootstrap): the seed/app/inngest blocks resolve the URL empty →
  pull straight from GHCR (`/run/soleur-image-ref` = the GHCR ref).
- **Already-running containers** are untouched (the flip only affects *pulls*, and revert
  changes nothing about a container already running).

Re-arm later by re-adding the secret (the Terraform `doppler_secret.zot_registry_url` will
re-create it on the next operator apply, or set it manually):

```bash
doppler secrets set ZOT_REGISTRY_URL "10.0.1.30:5000" --project soleur --config prd
```

## What you do NOT need to touch

- **`terraform_data.registry_insecure_config` / daemon.json `insecure-registries`** — leaving
  `10.0.1.30:5000` allowlisted is harmless once nothing pulls from zot (docker only consults
  it on a plain-HTTP pull *to* that host). Do NOT `systemctl restart docker` to remove it —
  a restart bounces every running container. It is inert after the gate is unset.
- **cosign trust** — unchanged by the migration (same pinned root + identity regexp); GHCR
  pulls verify exactly as before.

## Fallback-rate alarm (distinct from the soak-close gate)

The soak gate (`scripts/followthroughs/zot-soak-6122.sh`) is a **7-day cumulative** close
condition. The fallback-rate alarm is a **real-time page** so a live zot degradation is
caught in minutes, not at the next daily sweep. Arm it in Sentry at cutover (it targets
events that do not exist pre-flip):

- **Signal:** three warning tags, all `feature:supply-chain op:image-pull`:
  - `registry:"ghcr-fallback"` — a host *attempted* zot and the pull failed, then fell back
    (ci-deploy.sh `registry_pull_event`, rolling deploy);
  - `stage:"inngest_ghcr_fallback"` — same, on the fresh-boot inngest path (cloud-init
    `soleur-boot-emit`);
  - `registry:"zot-gate-degraded"` — zot is CONFIGURED but the gate could not activate it
    (probe unreachable / pull creds absent / login failed), so the deploy used GHCR WITHOUT
    ever running a zot pull (ci-deploy.sh `zot_gate_degraded_event`). This catches the
    host-up-heartbeat-green-but-pull-cred-broken case the other two miss.
- **Alert rule (Sentry issue/metric alert):** notify (page) when the count of events matching
  `registry:"ghcr-fallback" OR stage:"inngest_ghcr_fallback" OR registry:"zot-gate-degraded"`
  exceeds **X = 3 events in Y = 1 hour**. A healthy post-cutover fleet emits ZERO; a low
  threshold is intentional — any sustained fallback/degradation means zot cannot serve and
  every affected host paid the fallback cost (or silently reverted to GHCR).
- **On page:** confirm zot health, then run the Immediate revert above if the degradation is
  not resolving. Do not wait for the soak sweep.

All signals are Sentry/Better Stack events (no SSH, no dashboard eyeballing required —
`hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`). The zot host
itself has a `betteruptime_heartbeat.registry_prd` push heartbeat (`zot-registry.tf`) that
pages independently if zot stops pushing its liveness beat.
