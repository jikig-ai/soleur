---
title: Revert the zot pull-site flip to GHCR-primary
issue: "#6122"
adr: ADR-096
severity: P1 (deploy/boot path)
last_reviewed: 2026-07-30
---

# Revert the zot pull-site flip → GHCR-primary (#6122 / ADR-096)

> ## 🛑 STOP — this revert no longer works (verified 2026-07-30)
>
> **Do not run the procedure below to escape a zot outage. It will make the outage worse.**
>
> This runbook was written when GHCR was a warm break-glass registry, and the whole revert
> rests on that. It no longer is. GHCR's read credential is a **revoked** classic PAT
> (`GET api.github.com/user` → **401**) and the pull-token minter is **disabled**
> (`GHCR_MINTER_DISABLED=true`; minting → **403 `DENIED`**). Unsetting `ZOT_REGISTRY_URL`
> today does not move hosts onto a working fallback — it moves them onto a registry that
> **cannot authenticate at all**, turning "zot is degraded" into "nothing can pull".
>
> ADR-088 arm-b explains why this is structural rather than a lapsed chore: a GitHub App
> installation token can `docker login` to GHCR but is **DENIED** `docker pull` of a
> private repo-linked package, so there is no zero-touch GHCR pull credential to restore —
> only a personal one.
>
> **If zot is down, the failure is a zot/registry-host problem and must be fixed as one.**
> See "What to do instead" below. This document is kept, rather than deleted, because the
> revert becomes correct again the moment a working non-personal GHCR pull credential or a
> second mirror exists — and because a reader who remembers this procedure needs to find
> the retraction, not a 404.

The Phase-3 pull-site migration is **dark-launch gated**: every pull site (ci-deploy.sh
rolling deploy, soleur-host-bootstrap.sh + cloud-init.yml fresh boot) prefers the
self-hosted zot registry **only when `ZOT_REGISTRY_URL` is present in Doppler `prd` AND a
fast `/v2/` probe answers AND the pull login succeeds**. Any miss falls back to the
private-GHCR path — which, per the banner above, is now a path that fails.

**Historical note (what this paragraph used to say).** It described revert as a safe
Doppler flag flip because "GHCR remains dual-pushed + break-glass through the entire soak
(the interim classic PAT stays live until Phase 5.5)". Both halves have since changed:
**the PAT was revoked OUT-OF-BAND — Phase 5.5 has NOT run.** The *dual-push* is still live,
so GHCR still receives every image — but receiving is not serving, and nothing can read
them back.

**Corrected 2026-07-30.** This paragraph previously said "Phase 5.5 happened". It did not,
and saying so told a future reader the retirement completed and its guards discharged.
ADR-096 at HEAD still says the cutover has not happened, that the soak "remains necessary
but not sufficient to authorize 5.3–5.5", and that the ADR stays *Adopting*; #6122 and
#6500 are both still OPEN, and the `zot-soak-6122` follow-through explicitly refuses to
exit 0 while #6500 is open. The credential was lost, not retired — which is worse, because
nothing that gates the retirement was satisfied.

## What to do instead when zot is unreachable

The pull path has no second source, so the fix is always to restore zot rather than to
route around it:

1. **Is it the CI-side bridge or the host-side path?** They are different transports and
   different credentials, and only the second one affects running production.
   - CI → zot goes over the CF Tunnel with the `REGISTRY_PUSH_ACCESS_TOKEN_*` Access
     service token. Symptom: releases fail at the zot mirror step.
   - Host → zot goes over the private NIC (10.0.1.10 → 10.0.1.30:5000) with `ZOT_PULL_*`
     and no tunnel at all. Symptom: deploys fail `image_pull_failed`.
2. **Read the release job's own token verdict first — do not re-rank hypotheses by hand.**
   Since #7242 the failing release step reports what it MEASURED. Open the run and read
   `verdict=` (it is also in the ops email):

   | `verdict` | What it means | What to do |
   |---|---|---|
   | `live` | The job presented these exact credentials to `registry.soleur.ai` and Cloudflare Access **admitted** them. | Rotation is ruled OUT by measurement. Go to step 3. |
   | `stale` | A **measured** DEAD count. | Rotate — see below. |
   | `unverifiable` | The credential could not be graded; the message names the cause. | **Do NOT rotate.** Follow the cause. |
   | `unmeasured` | The preflight did not run. | Run the detector yourself, below. |

   This replaces the sentence that used to sit here — *"the measured cause of the
   2026-07-29 outage, and the single most likely explanation"*. It was measured for
   **that** incident and then read as a standing fact, which is how 2026-08-03 spent its
   diagnostic budget rotating a credential the job had already verified live.

   ```bash
   doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh
   ```

   Any `DEAD` row means a token was rotated and the new value never reached Doppler.
   Terraform will not fix it — the `doppler_secret` resources carry
   `lifecycle { ignore_changes = [value] }`, so `terraform apply` reports "No changes"
   while the stale value keeps being served. Set the live value in **every config the
   detector names**: Doppler branch configs do **not** inherit values from the `prd` root
   config, so setting root alone leaves every other stale copy in place and looks completely
   successful. (The detector's own header records the 2026-08-02 measurement behind this;
   the count is not re-derivable from a default run, which reads one config — so treat the
   detector's output, not a remembered number, as the list of configs to fix.) The script itself calls the old "branch configs inherit it" advice
   `FALSIFIED`; that correction had never been propagated back here.
3. **Is the zot host itself healthy?** Two recurring causes, and disk-full is only one:
   - **Disk-full** — see `SOLEUR_ZOT_DISK` / the Better Stack `registry_disk_prd` source.
   - **A crash-restart loop** — the same `SOLEUR_ZOT_DISK` marker carries `zot_restarts`,
     `exit_code`, `zot_oom_kills` (cumulative) and `oom_kills_5m` (windowed). There is no
     bare `oom_kills` field — grepping for one substring-matches the cumulative counter and
     silently relabels it. A climbing `zot_restarts` means pushes are straddling a
     restart: a `docker login` plus a three-tag `crane copy` takes tens of seconds, so at a
     few restarts per minute the tunnel's origin dial fails mid-push. On 2026-08-03 this
     blocked three releases while the credential was fine and the read path was healthy.
     Re-run once the count has **plateaued** — `scripts/followthroughs/zot-restart-plateau-6288.sh`
     is the prober (0 = plateau holds, 1 = still climbing, 2 = could not tell).
4. **If an image is missing from zot but present in GHCR**, backfill it rather than
   reverting. This does not depend on GHCR being readable **by the production hosts** —
   but it DOES need GHCR readable by whoever runs `crane`, because GHCR is the copy's
   *source*. The revoked `GHCR_READ_TOKEN` cannot do this. Run it from a context that
   already holds a working GHCR read credential — in practice a CI job, whose
   `${{ github.token }}` can read the org's own packages — or re-run the release, which
   performs the same copy as part of the mirror step.

   Bring up the bridge first, on the port the probe section above uses. `127.0.0.1:5000`
   is the port the CI action binds inside its own runner; a local bridge is `15000`:

   ```bash
   cloudflared access tcp --hostname registry.soleur.ai --url 127.0.0.1:15000 &
   crane copy ghcr.io/jikig-ai/soleur-web-platform:vX.Y.Z 127.0.0.1:15000/jikig-ai/soleur-web-platform:vX.Y.Z
   cosign sign --yes 127.0.0.1:15000/jikig-ai/soleur-web-platform@sha256:<digest>
   ```

   (Corrected 2026-07-30: this block previously claimed independence from GHCR
   readability while sourcing from GHCR, and used `:5000` two paragraphs after the probe
   section established `:15000` for a local bridge.)

   The `cosign sign` is not optional: a bare `crane copy` does not write the signature
   referrer, and the host hard-fails verification on an unsigned image.
5. **To ship past a broken release pipeline entirely**, use `apply-deploy-pipeline-fix.yml`.

## Probing `registry.soleur.ai` — the trap that cost an incident

A plain HTTPS `GET https://registry.soleur.ai/v2/` returns **HTTP 200 with an empty body**
when it is working correctly. **That is not a health check and its 200 does not mean the
registry is up.**

The tunnel ingress for that hostname is `service: tcp://10.0.1.30:5000` — a **TCP-mode**
ingress, consumable only via `cloudflared access tcp`. A plain GET is not the WebSocket
upgrade that stream requires, so nothing is ever proxied to the origin and Cloudflare
answers by itself. The response says exactly one thing: whether **CF Access accepted your
credentials** (200 = accepted, 403 = refused). It says nothing whatsoever about zot.

On 2026-07-29 that empty 200 was read as "Cloudflare is answering without a working
origin", which sent the investigation to look for a missing private-net route — a
hypothesis later refuted — and consumed the incident's entire diagnostic budget while the
actual cause (a CF Access service token rotated 3 minutes before the release, never
propagated to Doppler) sat unexamined.

**The correct origin probe** bridges the stream first, then speaks HTTP over it:

```bash
cloudflared access tcp --hostname registry.soleur.ai --url 127.0.0.1:15000 &
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:15000/v2/
# 401 (or 200) = zot itself answered — the origin is UP *at this instant*.
# A 'websocket: bad handshake' from cloudflared = the tunnel could not complete an ORIGIN
# DIAL. That is NOT diagnostic of an edge refusal. At least three things produce it:
#   - the tcp:// vs http:// ingress misconfiguration (#6122)
#   - Cloudflare Access actually refusing the credential
#   - the origin being down, or RESTARTING  <- 2026-08-03, with Access admitting every request
```

> **This sentence used to read "= the EDGE rejected you, which is the stale-Access-token
> shape, not an origin problem."** It was false, and it is the single line that most
> directly produced the 2026-08-03 misdirection: a crash-looping origin generated bad
> handshakes while Cloudflare Access admitted the request every time. Do not restore it.

**A single sample cannot clear the origin.** The probe above tells you about one instant.
An origin restarting a few times a minute answers healthily between restarts, which is
exactly the signature that defeats a one-shot health check — so a `401` here is compatible
with a push that fails seconds later. Pair it with the `zot_restarts` series (step 3).

A `401` here is a **healthy** result: it is zot's own auth challenge
(`Www-Authenticate: Basic realm=…`), which proves the request reached the origin.

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

> 🛑 **Superseded 2026-07-30 — do not run this to escape an outage.** See the banner at the
> top. The mechanism below still works exactly as described; what changed is the
> destination. It short-circuits pulls to GHCR, and GHCR can no longer serve them, so
> running this during a zot outage converts a degraded pull path into no pull path.
>
> It remains valid for one thing: **deliberately standing the zot pull path down** when
> GHCR has been given a working pull credential again (see ADR-096's amendment for the
> testable condition). Confirm that first — `docker pull` a private tag with the host's
> GHCR credential and see it succeed — then use this.

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
