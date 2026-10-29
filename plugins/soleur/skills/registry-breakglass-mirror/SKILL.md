---
name: registry-breakglass-mirror
description: "This skill should be used when the registry tunnel bridge is down and the zot store must be re-materialized from GHCR. Break-glass only."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# registry-breakglass-mirror

Re-materialize production's zot store (`10.0.1.30:5000`) from GHCR when the
Cloudflare Tunnel registry bridge is **down** — the one window in which
`registry-restore-from-ghcr.sh` (the luks-recut restore engine) cannot run,
because every CI path to zot traverses that bridge
(`.github/actions/cf-tunnel-registry-bridge/action.yml`).

This is a **break-glass** procedure. It is the documented, name-scoped exception
to the #9169 hosts-file ghcr deny (ADR-096 amendment 2026-10-28): a manual
operator/agent-invoked run, not a standing code path, not a host service, not a
standing credential.

## When to use

- The `registry.` tunnel ingress (or the tunnel itself) is down **and** the zot
  store must be (re)populated: post-restore backfill, a zot store that lost its
  pinned image set, or a release image that never made the mirror leg.
- Do **not** reach for it when the bridge is alive — the routine restore path is
  `registry-restore-from-ghcr.sh` over the tunnel, and the routine mirror is the
  release pipeline itself.
- Do **not** use it to "test" GHCR connectivity — it writes to the sole pull
  path production deploys read from.

## Connectivity matrix — reaching the mirror host

The mirror runs **on a private-net datacenter host**, never on the operator's
machine and never over a forwarded connection (see **The hard DO-NOT** below).

`MIRROR_HOST` is parameterized — default `web-1`; any `10.0.1.0/24` member works.
Since ADR-304, `web-2` is the tunnel-connector host and `web-1` is LUKS-pinned
and unreplaceable (#6964); prefer a fresh cattle host when one is up, and prefer
`web-1` when the alternative is the connector host mid-incident.

| Path | Reach | Precondition |
|------|-------|--------------|
| **Primary** | `ssh.soleur.ai` through the Cloudflare Tunnel (`cloudflared access ssh` ProxyCommand, as `deploy`) | the tunnel is alive — i.e., NOT the break-glass window itself, but fine for a degraded-registry store while SSH still converges |
| **Fallback** | direct SSH to the host's public address as `deploy` | the operator's **current egress IP** must be in the Hetzner firewall allow-list (`Doppler prd_terraform/ADMIN_IPS`) — run `soleur:admin-ip-refresh` FIRST when the IP may have rotated; this is an L3 dependency that precedes every SSH-layer assumption |

If neither path reaches the host, stop here: the fault is connectivity, not the
mirror. Do not widen the firewall beyond `admin-ip-refresh`'s documented
mutation.

## Credential sourcing (least privilege, exact forms)

| Credential | Source | Notes |
|------------|--------|-------|
| `DEPLOY_SSH_PRIVATE_KEY` | `doppler secrets get DEPLOY_SSH_PRIVATE_KEY -p soleur -c prd_terraform --plain` | write to a `0600` keyfile for the SSH legs |
| `ZOT_PUSH_USER` | `doppler secrets get ZOT_PUSH_USER -p soleur -c prd --plain` | root `prd` config, not `prd_terraform`; never "rotate ZOT_PUSH_* first" — `/etc/zot/htpasswd` is baked at registry boot |
| `ZOT_PUSH_TOKEN` | `doppler secrets get ZOT_PUSH_TOKEN -p soleur -c prd --plain` | second call — the multi-name form is an unverified CLI shape |
| `GHCR_TOKEN` | **operator-supplied at invocation** — a `read:packages` PAT the operator types or pastes | the Doppler `GHCR_READ_TOKEN` copy is **revoked BY DESIGN** (ADR-096 §5.5/B3 — no host reads GHCR); never reach for it |

Two `doppler secrets get` calls for `ZOT_PUSH_*` — one per secret, mirroring the
`scheduled-inngest-health.yml` credential pattern.

## The mirror host's GHCR exception (what the script does)

The web hosts sinkhole `ghcr.io`, `pkg-containers.githubusercontent.com`, and
`docker.pkg.github.com` to `0.0.0.0`/`::` in `/etc/hosts` (the #9169 accident
guard on name resolution — enumerated from
`apps/web-platform/infra/server.tf` `ghcr_deny_sh`). The script bypasses it with
**per-command `curl --resolve <name>:443:<ip>`** for the two names a pull needs —
`/etc/hosts` is never edited, TLS verification stays on (`--resolve` pins only
the dial address; SNI, the handshake, and CA verification still target the
hostname), and every pulled byte is verified at its sha256, so a wrong answer
cannot inject content. `pkg-containers.githubusercontent.com` MUST be resolved
too: GHCR blob GETs 307-redirect to it.

The IPs come from DNS-over-HTTPS at runtime (the host's own `getent` would
return the sinkhole), or from `GHCR_IP`/`PKGC_IP` env overrides when DoH is
unreachable.

## The hard DO-NOT

**Never upload blobs through a forwarded registry connection.** zot PATCH
uploads die mid-stream over `ssh -L` and registries do not resume upload
sessions — measured during the 2026-10-28 O2 recovery: ~1.1–2.4 GB over the
operator's residential uplink failed repeatedly (~250 KiB–1.5 MB/s, HTTP/2
PROTOCOL_ERROR drops, ~1 h+), while the datacenter-side fetch on web-1 finished
in ~3 minutes. The doctrine: **pull where the bandwidth is; push over the
private net.** An operator improvising `ssh -L 5000:10.0.1.30:5000` + `crane
copy` reopens exactly this failure mode — the skill exists so that is never the
path of least resistance.

## Cosign-signature mirroring is obligatory

`ci-deploy` cosign-verifies at deploy time and fetches the signature **from the
same registry it pulled the image from** (ADR-087). A mirrored image whose
signature is absent fails verification on the host — there is no
unsigned-mirror arm, and a missing signature is a hard failure, never a
warning. The signature rides the OCI referrers tag `sha256-<image-digest-hex>`
(the plan's `sha256-<hex>.sig` shorthand names this reference): GHCR serves it
as an OCI **index** whose *child* carries the `artifactType`
(`application/vnd.dev.sigstore.bundle.v0.3+json`) — the #7410 lesson. Reading
the tag as a plain manifest fail-closes a healthy signature; the script
mirrors the index structure and checks the child's `.subject.digest` binding.

## Procedure

1. **Stage credentials (operator side).** Source the four secrets per the table
   above. `GHCR_TOKEN` is supplied by the operator at invocation.
2. **Copy the engine to the host.** Copy
   [mirror-ghcr-to-zot.sh](./scripts/mirror-ghcr-to-zot.sh) via `scp` to the
   mirror host (`deploy@<MIRROR_HOST>` through whichever connectivity row is
   up).
3. **Dry-run first.** `mirror-ghcr-to-zot.sh --dry-run <repo> <ref>...` prints
   the plan — resolved refs, blob counts, declared bytes, signature presence,
   target — and pushes nothing.
4. **Mirror.** Run the script on the host with `GHCR_TOKEN`, `ZOT_PUSH_USER`,
   `ZOT_PUSH_TOKEN` in the environment. It pulls manifests+blobs via `curl
   --resolve`, assembles each ref into an OCI layout, `crane push`es to
   `10.0.1.30:5000/<repo>` (plain-HTTP private net — `--insecure`, the standing
   `hetzner -> zotRegistry` posture), mirrors the `sha256-<hex>` signature ref,
   then read-back-verifies every pushed ref with `crane validate --remote`
   (platform children) plus blob-presence (attestation/signature children) —
   never `crane digest` alone; a manifest can outlive its layers under zot
   gc+dedupe.
5. **Close out.** Exit `0` prints `mirror_summary ... result=ok`. Anything else
   is a non-zero exit with the failing ref named — do not treat the store as
   usable. Afterward, verify a host pull resolves the digest on the deploy
   path before declaring the window closed.

## Failure vocabulary

Name **only measured causes** (ADR-166). On this path the measured facts are the
http_code the pull leg observed and the crane error the push/verify leg
observed. The closed verdict vocabulary for the CI mirror path —
`live` / `stale` / `unverifiable` / `unmeasured` — lives in
[zot-mirror-diagnosis.sh](../../../../scripts/zot-mirror-diagnosis.sh); its rule
applies here too: no failure message may name a cause nothing measured (e.g.,
GHCR 404 means "absent **or not visible to this credential**", not "the image
is gone").

## Exit codes (the script's)

- `0` — every required reference pushed AND read-back-verified.
- `1` — usage/configuration error.
- `2` — GHCR/source leg failed (unreachable, 5xx, credential rejected, 404).
- `3` — sink (zot) unavailable; retryable.
- `4` — verification failed: the copy "succeeded" and the result is unusable
  (missing blob, digest mismatch, missing signature). NOT retryable.
- `5` — credential unusable (absent/empty, or rejected by the sink).
- `6` — unclassified; loudest arm, file it.
- `78` — refused to run under `bash -x` while a credential is set (#7797).

## Sharp Edges

- **`docker.pkg.github.com` is sinkholed too** and is deliberately never
  resolved — nothing on the GHCR pull path needs it.
- **`GHCR_TOKEN` is operator-supplied on purpose.** There is no zero-touch GHCR
  read path by construction (ADR-088 arm-b): the Doppler copy is revoked and
  stays revoked.
- **Digest refs push by digest** (`<repo>@sha256:<d>`); tag refs push by tag.
  zot keeps digest-pushed manifests digest-addressable — exactly what the
  pinned deploy refs need. Prefer passing a tag ref when the intended pull is
  `repo:tag`, a digest ref when it is `repo@sha256:`.
- **Do not edit `/etc/hosts`** "to make it easier" — the deny must stay in
  force after the mirror; per-command `--resolve` is the whole exception.
- **`crane` is fetched pinned** (v0.20.2 release tarball + sha256) when absent —
  github.com is not sinkholed.
- **Multiple refs in one run are fine** and each is verified independently; a
  later failure does not un-verify earlier successes — re-run the failing refs.

## Related

- [mirror-ghcr-to-zot.sh](./scripts/mirror-ghcr-to-zot.sh) — the engine (usage,
  env contract, exit codes in its header).
- `registry-restore-from-ghcr.sh` — the luks-recut restore engine this skill
  stands in for while the bridge is down (runs over the tunnel; its
  invariants — signature copy, `crane validate --remote`, credential hygiene —
  are carried, not the engine).
- [zot-mirror-diagnosis.sh](../../../../scripts/zot-mirror-diagnosis.sh) — the
  measured-cause vocabulary (`live`/`stale`/`unverifiable`/`unmeasured`).
- `soleur:admin-ip-refresh` — the direct-SSH fallback's firewall precondition.
- `soleur:cf-token-scope` — Cloudflare-token probe discipline reference.
- ADR-096 (the deny + its 2026-10-28 break-glass amendment), ADR-087 (cosign),
  ADR-166 (cause vocabulary), ADR-169 (restore authorization), ADR-304
  (connector placement). Learnings:
  `2026-09-28-an-ssh-drop-without-a-pty-is-sigpipe-and-my-cleanup-trap-read-it-as-success`,
  `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed`.
- Issue: #11424.
