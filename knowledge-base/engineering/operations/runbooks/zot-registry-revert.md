---
title: Revert the zot pull-site flip to GHCR-primary
issue: "#6122"
adr: ADR-096
severity: P1 (deploy/boot path)
last_reviewed: 2026-07-07
---

# Revert the zot pull-site flip → GHCR-primary (#6122 / ADR-096)

The Phase-3 pull-site migration is **dark-launch gated**: every pull site (ci-deploy.sh
rolling deploy, soleur-host-bootstrap.sh + cloud-init.yml fresh boot) prefers the
self-hosted zot registry **only when `ZOT_REGISTRY_URL` is present in Doppler `prd` AND a
fast `/v2/` probe answers AND the pull login succeeds**. Any miss falls straight through to
the unchanged private-GHCR path. **This makes revert a Doppler flag flip — no code deploy,
no SSH, no host mutation.** GHCR remains dual-pushed + break-glass through the entire soak
(the interim classic PAT stays live until Phase 5.5), so the fallback registry is always
warm and current.

## When to revert

- The **fallback-rate alarm** fires (see below). Since #6285 it pages on the **first**
  matching event, not a spike: a `registry:"ghcr-fallback"` / `stage:"inngest_ghcr_fallback"` /
  `stage:"app_ghcr_fallback"` event means a host *tried* zot and failed — that deploy/boot took
  the slower fallback path and zot is degraded.
  > ⚠ **`stage:"app_ghcr_served"` (#6462) does NOT belong in that list — it means the opposite.**
  > Its dominant route is a `/v2/` **probe-miss**, where zot was **never attempted** and the GHCR
  > pull succeeded first try. Triaging it as "tried zot and failed" sends you down the pull path
  > when the fault is the probe. It shares the *next* bullet's semantics (zot unreachable), so
  > read it there. Distinguish by its sibling: `app_ghcr_served` **with** `app_ghcr_fallback` =
  > zot was tried and failed (this bullet); `app_ghcr_served` **without** it = the probe missed
  > (next bullet).
- zot host down / unreachable / R2-backed storage fault / cert/htpasswd rotation broke pull
  auth, and you want to stop hosts from attempting zot at all (each attempt adds a probe +
  a failed pull before falling back). A `stage:"app_ghcr_served"` event with **no**
  accompanying `stage:"app_ghcr_fallback"` is the fresh-boot form of this: the `/v2/` probe
  missed, so the boot never tried zot (#6416 / #6288 are the standing probe-miss trackers).
  > **RULE OUT THE PRIVATE NIC FIRST (#6415 / ADR-115).** "zot is unreachable" is exactly how
  > #6400 presented, and the cause was that the host held no `10.0.1.30` at all — zot itself was
  > healthy on `:5000`. Reverting to GHCR-primary here would **mask** that: it stops the failing
  > pulls, so the fleet looks fine while the registry stays broken. That is the 14-day shape.
  > One query, no SSH:
  > ```
  > doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  >   --since 3h --grep SOLEUR_PRIVATE_NIC --limit 20
  > ```
  > `nic_ok=false` ⇒ this is a NIC fault, **not** a zot fault: re-dispatch
  > `registry-host-replace` instead of reverting. A **down container gives connection
  > *refused*; an unconfigured NIC gives *timeout* + ping loss** — that distinguisher is what
  > made #6400 look like "zot mysteriously down".
- Any Phase-5 retirement step (5.3 fallback-branch removal) is discovered premature.

Note: a *single* transient `ghcr-fallback` is self-healing — the host already fell back to GHCR
and served correctly, so a one-blip page is **not** by itself a reason to revert. But since
#6285 the alarm pages on that blip **by design** (a per-group threshold above 0 is silently
unreachable on this signal's grouping — see the resource comment), so **do not dismiss the page
as noise**: triage it. Revert is for a *sustained* zot degradation. **If the noise is
`zot-gate-degraded (probe_unreachable)` pre-cutover, mute that Sentry ISSUE — never the rule**
(the rule also carries `ghcr-fallback`, the only no-SSH page gating the irreversible 5.5 PAT
revoke; a per-issue mute cannot pre-suppress it because `ghcr-fallback` mints a fresh group per
deploy). The real fix for `probe_unreachable` is the zot host, not the alarm.

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
caught in minutes, not at the next daily sweep. It is **already live** — apply-created and
armed today; `zot-gate-degraded` emits pre-flip, so there is nothing to arm at cutover:

- **Signal:** five warning tags. ⚠ They are NOT all `feature:supply-chain op:image-pull` — the
  prefix split is deliberate and the earlier "all `feature:supply-chain op:image-pull`" framing
  was wrong: only the `registry:` pair carries that prefix (ci-deploy.sh's jq payload writes
  `feature`/`op`), while every `stage:` query is **bare** because neither boot-path emitter
  writes those tags. Sentry tag matching is exact — a prefixed `stage:` query matches nothing.
  - `registry:"ghcr-fallback"` — a host *attempted* zot and the pull failed, then fell back
    (ci-deploy.sh `registry_pull_event`, rolling deploy);
  - `registry:"zot-gate-degraded"` — zot is CONFIGURED but the gate could not activate it
    (probe unreachable / pull creds absent / login failed), so the deploy used GHCR WITHOUT
    ever running a zot pull (ci-deploy.sh `zot_gate_degraded_event`). This catches the
    host-up-heartbeat-green-but-pull-cred-broken case the others miss.
  - `stage:"inngest_ghcr_fallback"` — a fresh-boot inngest pull attempted zot and fell back
    (cloud-init `soleur-boot-emit`). **Bare**, no prefix.
  - `stage:"app_ghcr_fallback"` — same, on the fresh-boot web/app path (cloud-init `_emit`).
    **Bare**.
  - `stage:"app_ghcr_served"` (#6462) — a fresh boot was served by GHCR *at all*. **Bare**, and
    the only one of the five that fires when zot was NEVER ATTEMPTED (the `/v2/` probe missed
    and the GHCR pull succeeded first try — the dominant path, previously invisible). Triage it
    by its sibling: **with** `app_ghcr_fallback` = zot tried and failed → chase the pull;
    **without** = the probe missed → chase the probe (#6416 / #6288).
- **The soak gate can now FAIL for three reasons, not one** (#6462). If you are here because
  `zot-soak-6122.sh` failed, read its message before assuming a fallback occurred:
  | Message | Means | Do |
  |---|---|---|
  | `FAIL: N fallback event(s)` | a host really was GHCR-served | this runbook — triage by signal, above |
  | `FAIL(no-freshboot-evidence)` | **zero fallbacks AND zero zot-served fresh boots** — the fleet is UNOBSERVED, not clean. `cloud-init.yml` is `ignore_changes`-pinned, so the beacon only ships on a rebuild | do NOT revert zot. Recreate a web host inside the window, or wait — the fleet recreates ~1.3×/day |
  | `FAIL(blocked)` / `FAIL(blocker-closed-but-condition-unmet)` | the soak's criteria hold, but #6500 (the dedicated inngest host: GHCR-only, fail-closed, invisible to these queries) is still open — or was closed while the code still shows no zot path | do NOT revert zot, and do NOT close #6500 to clear it. Fix the inngest host |
  Only the first row is a zot problem. The other two are the gate refusing to authorize an
  irreversible PAT revoke on evidence it does not have — that is the gate working.
- **Alert rule** — `sentry_issue_alert.zot_mirror_fallback_rate`, APPLY-CREATED and live now
  (it is **not** armed at cutover; `zot-gate-degraded` emits pre-flip today). It pages on the
  **first** event matching any of the FIVE signals: `registry:{"ghcr-fallback",
  "zot-gate-degraded"}` / `stage:{"inngest_ghcr_fallback", "app_ghcr_fallback",
  "app_ghcr_served"}`
  (`event_frequency count > 0 / 1h`, `filter_match = "any"`). Fire-on-first is required, not a
  preference: the count is per Sentry issue-group and `ghcr-fallback` mints a fresh group per
  deploy, so any threshold above 0 is unreachable on that signal (#6285). It also matches
  `zot-soak-6122.sh`, which FAILs the Phase-5 gate on >=1 fallback. A healthy post-cutover fleet
  emits ZERO.
- **On page:** confirm zot health, then run the Immediate revert above if the degradation is
  not resolving. Do not wait for the soak sweep.

All signals are Sentry/Better Stack events (no SSH, no dashboard eyeballing required —
`hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`). The zot host
itself has a `betteruptime_heartbeat.registry_prd` push heartbeat (`zot-registry.tf`) that
pages independently if zot stops pushing its liveness beat.
