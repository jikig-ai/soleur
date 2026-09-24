---
title: Revert the zot pull-site flip to GHCR-primary (RETRACTED — no host-side GHCR read path exists)
issue: "#6122"
adr: ADR-096
severity: P1 (deploy/boot path)
last_reviewed: 2026-09-24
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
> See "What to do instead" below. This document is kept, rather than deleted, because a
> reader who remembers this procedure needs to find the retraction, not a 404.
>
> **Amendment 2026-09-23 (#8036 1c) — A CREDENTIAL IS NO LONGER ENOUGH TO RE-ARM THIS.**
> The paragraph above used to say the revert "becomes correct again the moment a working
> non-personal GHCR pull credential or a second mirror exists". That is now false, and
> dangerously so: 1c **deleted the host-side GHCR read path from `ci-deploy.sh`** — the
> prelude login, the re-fetch/relogin helper, and the GHCR leg of the pull. There is no
> code left for a credential to authenticate. Restoring this procedure needs a **code
> change** (restoring a host-side pull path) *and* a credential, in that order. Minting a
> PAT and running the steps below would take production from "zot degraded" to "no pull
> path at all", with the deploy failing terminally at `image_pull_failed`.
>
> **Amendment 2026-09-24 (#8036 1d, PR #8708) — THE FRESH-BOOT PATH HAS NO GHCR LEG EITHER.**
> 1d deleted the fresh-boot GHCR login and GHCR pull from `cloud-init.yml`,
> `soleur-host-bootstrap.sh` and `cloud-init-inngest.yml`, and stopped passing the GHCR
> credential into any host's `user_data`. No pull path on any host (rolling deploy or fresh
> boot) can read GHCR. There is also **no toggle** left: fresh boots bake the zot endpoint and
> credential at create time (#8660) and never read `ZOT_REGISTRY_URL` from Doppler. A revert to
> GHCR now needs **code on every pull site plus a credential**, not a Doppler flag. This holds for
> the templates at merge, and for each host once it is replaced from them (web-1 keeps its
> first-boot `user_data` for its lifetime, but it never re-runs cloud-init).

The Phase-3 pull-site migration is **dark-launch gated**: every pull site (ci-deploy.sh
rolling deploy, soleur-host-bootstrap.sh + cloud-init.yml fresh boot) prefers the
self-hosted zot registry **only when `ZOT_REGISTRY_URL` is present in Doppler `prd` AND a
fast `/v2/` probe answers AND the pull login succeeds**. Any miss falls back to the
private-GHCR path — which, per the banner above, is now a path that fails.

> **Superseded 2026-09-23 (#8036 item 1c, PR #8600):** `ci-deploy.sh` has no GHCR leg any more.
> A gate miss on a rolling deploy now fails terminally at `image_pull_failed` (unless the
> same-version local-cache rescue applies). The GHCR fallback above survives only on the fresh-boot
> paths, where it presents a revoked credential; a fresh web boot currently fails (#8651, fix in
> PR #8660).
>
> **Superseded 2026-09-24 (#8036 item 1d, PR #8708):** the fresh-boot GHCR fallback is deleted too.
> A fresh boot pulls from zot only; a zot miss ends the boot and pages (`stage=pull` fatal on web,
> `stage=inngest_pull_fatal` fatal on the dedicated inngest host). #8651 is fixed (PR #8660): the
> web-2 replace in run 35951886838 booted zot-served (`stage=app_zot`, `fresh_boot_ready`).

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
nothing that gates the retirement was satisfied. (**Superseded 2026-09-24:** ADR-096's `## Status`
block now records the 2026-07-17 cutover and the 5.3a/5.3b split; #6122 and #6500 are still open.)

## Cutover record (#6122)

The cutover was not recorded when it happened. It was reconstructed on 2026-09-22 from Sentry
(90-day retention):

| Fact | Value | Evidence |
|---|---|---|
| First zot-served web pull | **2026-07-17T19:51:49Z** | earliest `feature:supply-chain op:image-pull registry:"zot" image:"web"` event; none earlier in retention |
| Soak window start (`START` in `zot-soak-6122.sh`) | **2026-07-17T19:45:00Z** | pinned a few minutes BEFORE the first zot pull, never after |
| Flag that performs the flip | `ZOT_REGISTRY_URL` in Doppler `soleur/prd` | managed as `doppler_secret` in `zot-registry.tf` since #6120 (2026-07-07) |
| GHCR became unusable | around 2026-07-29 | PAT revoked out-of-band, minter disabled (see the banner above; #7071) |

**Backfilled soak verdict, 2026-09-22: FAIL.** Run over `START`..now, the soak found six fallback
events. None can be dropped by moving `START` later: that is the documented false-PASS route.

| When (UTC) | Signal | Context |
|---|---|---|
| 2026-07-17 19:52:12, 20:11:39 | `zot-gate-degraded` ×2 | flip day, within 20 min of the first zot pull |
| 2026-07-26 16:51:40, 07-27 07:49:55, 07-27 11:05:35 | `app_ghcr_served` ×3 | web fresh boots served by GHCR, before GHCR died |
| 2026-09-22 07:01:49 | `inngest_ghcr_fallback` ×1 | inngest host booted before its private NIC was usable (#8539) |

Between 2026-07-27 11:05Z and 2026-09-22 07:01Z there were zero fallbacks. There have also been
**no web fresh boots since 2026-07-27**, so `stage:"app_zot"` has 0 events: a zot-served web
fresh boot has never been observed, only zot-served rolling deploys (392 pulls in 90 days).

> **Addendum 2026-09-24:** the record above runs to 2026-09-22. On 2026-09-23 a web-2 replace did
> boot fresh, and it booted dark at `stage=pull` (#8651, fix in PR #8660). So a *zot-served* web fresh
> boot is still unobserved, and a fresh web boot is currently known to fail.
>
> **Addendum 2026-09-24 (#8036 1d):** superseded the same day. After PR #8660 merged
> (2026-09-24T03:22:41Z), the web-2 replace in run 35951886838 booted zot-served
> (`stage=app_zot`, `ghcr_login=fail`, `fresh_boot_ready`): the first observed zot-served web fresh
> boot. The operator then re-armed the soak at `START=2026-09-24T03:22:41Z` (#6122). The table above
> is the pre-re-arm window's record and is not part of the new window.

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

> ⚠ **#8036 1c (2026-09-23) removed the `registry:"ghcr-fallback"` signal, and it did NOT remove
> the condition that signal reported — it removed the fallback.** The host-side GHCR read path is
> deleted, so a rolling deploy whose zot pull fails no longer falls back to a second registry: it
> tries the #6512 local-cache reload (same-version reloads only) and otherwise ends
> `image_pull_failed` with the old container still live. Everywhere below that names five signals,
> read FOUR; everywhere that says a host "fell back to GHCR and served correctly", read "the
> deploy failed and the previous release kept serving". The live degradation signals for the
> rolling path are now `registry:"zot-gate-degraded"`, `registry:"local-cache"` and
> `image_pull_failed`. The three fresh-boot `stage:` signals are UNCHANGED — cloud-init still has
> its GHCR fallback (that is 5.3b / #8036 1d).
>
> ⚠ **Superseded 2026-09-24 (#8036 1d, PR #8708): the fresh-boot signals changed too.** There is no
> fresh-boot fallback any more, so:
>
> - `stage:"app_ghcr_fallback"` and `stage:"app_ghcr_served"` are **retired**: no code emits them.
>   Zero rows is expected, not a new silence.
> - `stage:"inngest_ghcr_fallback"` is **renamed `stage:"inngest_pull_fatal"`** and raised to
>   **fatal**. It means the dedicated inngest host's zot pull failed and the boot **ended**: the
>   sole scheduler is dark until zot is fixed and the host is replaced again. It is not a
>   fallback. The gated colocated block in `cloud-init.yml` emits the same stage.
> - A **web** fresh-boot zot miss emits `soleur-hostscript-seed failed` at `stage=pull`, fatal,
>   paged by `web_terminal_boot_fatal`. The fatal detail reads
>   `nic=… zot=[login=,n=,cause=] pull_err: …` (no `ghcr=[…]` field any more).
>
> The triage bullets below that name the three old stages are the pre-1d record; read them
> through this note.

- **Since #8036 1d (2026-09-24), a fresh-boot page is a failed boot, not a slower one.** Triage:
  - `stage:"inngest_pull_fatal"` (paged by `zot-mirror-fallback-rate`): read the redacted pull
    tail on the independent channel first:
    `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep inngest_pull_fatal`.
    Its detail is `zot miss ep=… rc=… tail=…` (or `no zot endpoint baked`). Then rule out the
    private NIC (below), then repair zot (`apply_target=registry-host-replace`) or backfill the
    missing tag (`build-inngest-bootstrap-image.yml -f mirror_only=true`), then run
    `inngest-host-replace` again.
  - web `stage=pull` fatal (paged by `web_terminal_boot_fatal`): the host is web-2 or a new host
    (web-1 never re-runs cloud-init). Read `zot=[login=,n=,cause=]` in the detail:
    `cause=auth|unreach|manifest|timeout|unpinned|other`. `unpinned` means the dispatch passed a
    tag-only ref; fix the pin, never the registry. Every other cause is a zot or NIC fault, handled
    as below. The replace job's `fresh-host-boot-trail.sh` summary prints the same verdict.

- The **fallback-rate alarm** fires (see below). Since #6285 it pages on the **first**
  matching event, not a spike: a `stage:"inngest_ghcr_fallback"` / `stage:"app_ghcr_fallback"`
  event means a host *tried* zot and failed — that BOOT took the slower fallback path and zot is
  degraded. (The rolling-deploy member of this list, `registry:"ghcr-fallback"`, was retired with
  the fallback itself; see the banner above.) (**Superseded 2026-09-24, #8036 1d:** neither stage
  is emitted any more; the inngest one is now `stage:"inngest_pull_fatal"`, a terminal boot. See
  the bullet above.)
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
>
  > ```
  > doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  >   --since 3h --grep SOLEUR_PRIVATE_NIC --limit 20
  > ```
>
  > `nic_ok=false` ⇒ this is a NIC fault, **not** a zot fault: re-dispatch
  > `registry-host-replace` instead of reverting. A **down container gives connection
  > *refused*; an unconfigured NIC gives *timeout* + ping loss** — that distinguisher is what
  > made #6400 look like "zot mysteriously down".

- Any remaining Phase-5 retirement step (5.3b fresh-boot fallback removal) is discovered premature.
  (**Superseded 2026-09-24:** 5.3b-i, the fresh-boot fallback removal, is done by #8036 1d. What
  remains is 5.3b-iii (the GHCR egress allow) and 5.4 (the GHCR credential plumbing).)
  5.3a (the `ci-deploy.sh` GHCR read path) is already done and cannot be reverted by this runbook.

Note: a *single* transient fresh-boot `*_ghcr_fallback` is self-healing — that host fell back to
GHCR and booted correctly, so a one-blip page is **not** by itself a reason to revert. But since
#6285 the alarm pages on that blip **by design** (a per-group threshold above 0 is silently
unreachable on these signals' grouping — see the resource comment), so **do not dismiss the page
as noise**: triage it. Revert is for a *sustained* zot degradation.

> **Superseded 2026-09-24 (#8036 1d): this self-healing note no longer applies to fresh boots
> either.** A fresh-boot zot miss now ends the boot (`inngest_pull_fatal` or web `stage=pull`,
> both fatal). There is no GHCR to heal onto.

> **This self-healing note no longer extends to the rolling deploy.** Since #8036 1c there is no
> fallback on that path, so the rolling-deploy equivalent of a "one-blip fallback" is a FAILED
> DEPLOY (`image_pull_failed`, old container live) rather than a slower successful one. Treat a
> rolling-path page as a real outage of the release, not as a latency event.

**If the noise is `zot-gate-degraded (probe_unreachable)` pre-cutover, mute that Sentry ISSUE —
never the rule.** The claim that used to stand here — that the rule "also carries `ghcr-fallback`,
the only no-SSH page gating the irreversible 5.5 PAT revoke" — was retired with that signal in
#8036 1c, and it had already been spent: the PAT it was gating the revoke of has been revoked
since 2026-07-29. What the mute would now take with it is the three fresh-boot signals, which is
reason enough to keep muting the ISSUE rather than the rule. The real fix for `probe_unreachable`
is the zot host, not the alarm. (**Superseded 2026-09-24, #8036 1d:** the rule now carries one
other signal, not three: `stage:"inngest_pull_fatal"`, a terminal inngest boot. Muting the rule
would silence the page for a dark sole scheduler.)

## Immediate revert (≈30 s, no deploy) — unset the gate

> 🛑 **Superseded 2026-07-30 — do not run this to escape an outage.** See the banner at the
> top. The mechanism below still works exactly as described; what changed is the
> destination. It short-circuits pulls to GHCR, and GHCR can no longer serve them, so
> running this during a zot outage converts a degraded pull path into no pull path.
>
> **Since #8036 1c it is not valid for anything.** This section previously blessed one use
> — standing the zot pull path down once GHCR had a working credential — gated on an
> on-host `docker pull` check. Both halves are gone: there is no host-side GHCR read code
> for a credential to use, and the confirmation step required a shell on the host, which
> no repo tool provides and which `hr-no-ssh-fallback-in-runbooks` forbids as a runbook
> step. (1c also sweeps the deploy docker config's `ghcr.io` entry on every deploy, so the
> credential that check wanted to exercise is removed as a matter of course.)
>
> Do not run the commands below. They are retained only so the mechanism is documented for
> whoever restores a host-side pull path.

Removing `ZOT_REGISTRY_URL` from Doppler `prd` makes `zot_gate_and_login` /
the cloud-init + bootstrap gates short-circuit to GHCR on the **next** pull:

```bash
doppler secrets delete ZOT_REGISTRY_URL --project soleur --config prd --yes
# verify it is gone (empty output):
doppler secrets get ZOT_REGISTRY_URL --plain --project soleur --config prd 2>/dev/null || echo "unset ✓"
```

Effect, with no further action:

- **Rolling deploys** (`ci-deploy.sh`): the next `deploy` webhook resolves `ZOT_REGISTRY_URL`
  empty → `ZOT_ACTIVE=0`, which **since #8036 1c is TERMINAL**. There is no GHCR leg to fall
  through to. The only remaining tier is `_try_local_cache_reload`, and it applies **only** to a
  same-version `web` redeploy; an inngest deploy and every new-version deploy go straight to
  `image_pull_failed` (the OLD container stays live — downtime-safe, but nothing ships).
- **Fresh boots** (cloud-init/bootstrap): still resolve the URL empty → pull straight from GHCR
  (`/run/soleur-image-ref` = the GHCR ref). 1c did **not** touch the fresh-boot path — that is
  1d scope — so this bullet is still accurate, and it is now the ONLY one that is. The boot
  path's GHCR login uses the same PAT that has been revoked since 2026-07-29, so it fails too;
  it simply fails on a different code path.
  (**Superseded 2026-09-24, #8036 1d:** false now. Fresh boots bake the zot endpoint and
  credential at create time (#8660) and do not read `ZOT_REGISTRY_URL` from Doppler, and 1d
  deleted their GHCR login and GHCR pull. Unsetting the secret does not touch a fresh boot at
  all.)
- **Already-running containers** are untouched (the flip only affects *pulls*, and revert
  changes nothing about a container already running).

**The sweep is one-way and reverting the code does not undo it.** Since #8036 1c every deploy
removes any `ghcr.io` entry from the deploy docker config. Reverting the PR restores the code but
not the credential: the pre-1c prelude would re-run `docker login ghcr.io` with a PAT revoked
since 2026-07-29, a failed login writes no `auths` entry, and `GHCR_MINTER_DISABLED=true` means no
replacement can be minted. Plan on that being gone for good.

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

- **Signal (since #8036 1d, 2026-09-24): two tags.** `registry:"zot-gate-degraded"` (warning,
  rolling deploy) and `stage:"inngest_pull_fatal"` (fatal, dedicated-inngest fresh boot and the
  gated colocated block). The rule keeps the name `zot-mirror-fallback-rate` so the
  `alert-reference.json` keys stay stable, but its second member is **not a fallback**: it is a
  terminal boot. The list below is the pre-1d record, kept so a reader finding zero rows for a
  retired stage finds why.
- **Signal (pre-1d record):** five warning tags. ⚠ They are NOT all `feature:supply-chain op:image-pull` — the
  prefix split is deliberate and the earlier "all `feature:supply-chain op:image-pull`" framing
  was wrong: only the `registry:` pair carries that prefix (ci-deploy.sh's jq payload writes
  `feature`/`op`), while every `stage:` query is **bare** because neither boot-path emitter
  writes those tags. Sentry tag matching is exact — a prefixed `stage:` query matches nothing.
  - `registry:"ghcr-fallback"` — **RETIRED by #8036 1c (2026-09-23).** It meant "a host attempted
    zot, the pull failed, and it fell back". There is no fallback on the rolling-deploy path any
    more, so the emit site is deleted and this query is permanently empty. Its successor evidence
    is `registry:"local-cache"` (a same-version reload rescued from the host's own image store)
    and `image_pull_failed` (everything else). Listed rather than deleted so a reader finding
    zero rows does not read it as a new silence.
  - `registry:"zot-gate-degraded"` — zot is CONFIGURED but the gate could not activate it
    (probe unreachable / pull creds absent / login failed). Since #8036 1c there is no GHCR leg,
    so the deploy then fails terminally at `image_pull_failed` unless the same-version local-cache
    rescue applies (ci-deploy.sh `zot_gate_degraded_event`). This catches the
    host-up-heartbeat-green-but-pull-cred-broken case the others miss.
  - `stage:"inngest_ghcr_fallback"` — a fresh-boot inngest pull attempted zot and fell back
    (cloud-init `soleur-boot-emit`). **Bare**, no prefix. **Renamed by #8036 1d (2026-09-24)** to
    `stage:"inngest_pull_fatal"`, level fatal: there is no fallback, and the boot ends.
  - `stage:"app_ghcr_fallback"` — same, on the fresh-boot web/app path (cloud-init `_emit`).
    **Bare**. **RETIRED by #8036 1d (2026-09-24):** no emit site. A web fresh-boot zot miss is now
    the `stage=pull` fatal paged by `web_terminal_boot_fatal`.
  - `stage:"app_ghcr_served"` (#6462) — a fresh boot was served by GHCR *at all*. **Bare**, and
    the only one of the five that fires when zot was NEVER ATTEMPTED (the `/v2/` probe missed
    and the GHCR pull succeeded first try — the dominant path, previously invisible). Triage it
    by its sibling: **with** `app_ghcr_fallback` = zot tried and failed → chase the pull;
    **without** = the probe missed → chase the probe (#6416 / #6288). **RETIRED by #8036 1d
    (2026-09-24):** no emit site (the `/v2/` probe went in #8660, the GHCR arm in 1d).
- **The soak gate can now FAIL for four reasons, not one** (#6462, #6500). If you are here because
  `zot-soak-6122.sh` failed, read its message before assuming a fallback occurred:

  | Message | Means | Do |
  |---|---|---|
  | `FAIL: N fallback event(s)` | a host really was GHCR-served | this runbook — triage by signal, above |
  | `FAIL(no-freshboot-evidence)` | **zero fallbacks AND zero zot-served fresh boots** — the fleet is UNOBSERVED, not clean. `cloud-init.yml` is `ignore_changes`-pinned, so the beacon only ships on a rebuild | do NOT revert zot. Do NOT recreate a web host to generate evidence while #8651 is open: a fresh web boot currently fails. Wait for #8651 / PR #8660 (no web fresh boot has happened since 2026-07-27; see the Cutover record) |
  | `FAIL(no-inngest-freshboot-evidence)` | zero fallbacks, but the dedicated `soleur-inngest` host reported no zot-served fresh boot on Sentry in the window. Its reporting only exists on a host BUILT from the #6500 template | do NOT revert zot. If no replace has run in the window: dispatch `apply-web-platform-infra.yml` with `apply_target=inngest-host-replace` in an ADR-100 window (check `INNGEST_CUTOVER_FLIP` first). If one did: read `scripts/betterstack-query.sh --grep 'stage=inngest_zot' --grep sentry-emit-FAILED --grep SOLEUR_INNGEST_BOOT_TRACE_LOST` for the window before replacing again — `inngest_zot` plus `sentry-emit-FAILED` is a delivery fault (DSN or egress), not a missing boot |
  | `FAIL(blocked)` / `FAIL(blocker-closed-but-condition-unmet)` | the soak's criteria hold, but #6500 (the dedicated inngest host's zot-primary pull + Sentry reporting — the pre-#7462 "GHCR-only, invisible to these queries" description is superseded) is still open — or was closed while the code lacks the zot path or the Sentry call sites | do NOT revert zot, and do NOT close #6500 to clear it. Close it as completed only after an operator verifies the replaced host (`RESULT: PASS`) |

  Only the first row is a zot problem. The other two are the gate refusing to authorize an
  irreversible PAT revoke on evidence it does not have — that is the gate working.

  > **Amended 2026-09-24 (#8036 1d):** the soak was re-armed at `START=2026-09-24T03:22:41Z` (the
  > #8660 merge; operator decision on #6122) and enrolled on #6122 (earliest grade
  > 2026-10-01T03:22:41Z). Its FAIL set is now two queries, `gate-degraded` and
  > `inngest-pull-fatal`, so a `FAIL: N … event(s)` line means a rolling-deploy gate degrade or a
  > terminal inngest boot, not "a host was GHCR-served". A separate arm FAILs on any web
  > `stage:"pull" level:fatal` in the window. The soak now gates 5.6 and #6129; the PAT revoke
  > (5.5) is already done.

- **Alert rule** — `sentry_issue_alert.zot_mirror_fallback_rate`, APPLY-CREATED and live now
  (it is **not** armed at cutover; `zot-gate-degraded` emits pre-flip today). It pages on the
  **first** event matching any of the FOUR signals (five before #8036 1c):
  `registry:{"zot-gate-degraded"}` / `stage:{"inngest_ghcr_fallback", "app_ghcr_fallback",
  "app_ghcr_served"}`
  (`event_frequency count > 0 / 1h`, `filter_match = "any"`). (**Superseded 2026-09-24, #8036 1d:**
  TWO conditions now, `registry:{"zot-gate-degraded"}` / `stage:{"inngest_pull_fatal"}`; the
  three `stage:` values above have no emit site.) Fire-on-first is required, not a
  preference: the count is per Sentry issue-group, and the retired `ghcr-fallback` was the member
  that minted a fresh group per deploy, so any threshold above 0 was unreachable on it (#6285).
  The threshold stays at 0 for the survivors as well — a value above 0 is fleet-shape-dependent
  on every one of them. It also matches
  `zot-soak-6122.sh`, which FAILs the Phase-5 gate on >=1 fallback. A healthy post-cutover fleet
  emits ZERO.
- **On page:** confirm zot health and repair zot (`apply_target=registry-host-replace`, as above). Do NOT run the
  Immediate revert above: per the banner at the top, it removes the only working pull path and
  turns "zot degraded" into "no pull path at all". Do not wait for the soak sweep.

All signals are Sentry/Better Stack events (no SSH, no dashboard eyeballing required —
`hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`). The zot host
itself has a `betteruptime_heartbeat.registry_prd` push heartbeat (`zot-registry.tf`) that
pages independently if zot stops pushing its liveness beat.
