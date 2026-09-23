---
title: "Cosign deploy-verify: host-net ephemeral verifier over private GHCR (no container-allowlist widening)"
status: active
date: 2026-07-04
---

# ADR-087: Cosign deploy-verify: host-net ephemeral verifier over private GHCR (no container-allowlist widening)

> **Note (2026-07-06, #6122):** the deploy-time cosign verifier topology decided here is
> **unaffected** and stays active. Only the *credential-provisioning* arm (how the host authenticates
> the private pull + `.sig` fetch, ADR-088 D1) is changing: ADR-088's App-token minter was proven
> infeasible (GHCR refuses App tokens), so #6122 migrates the registry off GHCR to self-hosted zot.
> When that lands, "GHCR" in this ADR becomes the zot endpoint and the mounted docker-config carries
> the zot OIDC bearer instead of a GHCR PAT — the `--network host` + pinned-trusted-root + offline
> verify shape is identical.
>
> **Superseded in part, 2026-09-23 (#8036 item 1c):** that landing is now done for the deploy
> path. The host-side GHCR read path is deleted, so the mounted docker-config carries the zot
> credential and nothing else; any `ghcr.io` entry is swept out of the deploy config on every
> deploy. The original note is kept verbatim above rather than reworded, because it is the dated
> record of what credential KIND this ADR expected in the verifier mount — a detail the
> superseding text does not carry.
>
> A measured consequence worth recording here, since it is this ADR's own failure mode:
> presenting a REVOKED credential is worse than presenting none. GHCR refuses an *authenticated*
> request bearing a revoked token where it would serve the same bytes anonymously, which is why
> the **public** Sigstore verifier-image pull returned `denied` and `IMAGE_VERIFY` reported
> `result=cosign_absent` 89 times out of 89 in the 7 days to 2026-09-22.

## Context

`apps/web-platform/infra/ci-deploy.sh` cosign-verifies the app image signature on
the running host at deploy time (`verify_image_signature`, WARN mode — never
blocks; the soak-gated WARN→ENFORCE flip is a separate future issue, #6129).
It runs the SHA-pinned distroless cosign container
(`ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a…` = v3.1.1) via `docker run --rm`.

Issue #6005 exists because the shipped verify (PR #5977) **cannot pass on the real
host**. Two facts, both confirmed by a live Phase-0 probe against the real pinned
v3.1.1 container:

1. **The app image is now PRIVATE** (`ghcr.io/jikig-ai/soleur-web-platform`,
   operator/CPO confirmed keep-private). The cosign container fetches the
   OCI-attached signature from the registry, and a `docker run` container inherits
   no host GHCR credential → `UNAUTHORIZED`. A scoped `read:packages` machine-account
   PAT into Doppler + host `docker login` is already decided (out of scope here).
2. **The container egress firewall (#5046, ADR-052) blocks both sigstore
   (fulcio/rekor/TUF) and ghcr.io** for anything on `docker0`. The firewall is
   `iifname "docker0" jump SOLEUR-EGRESS` — it is scoped to the FORWARD path of
   containers on the default bridge. **HOST egress (OUTPUT) is unrestricted** and is
   what pulls the app image from GHCR today (`cron-egress-nftables.sh` line 19-22:
   "Host OUTPUT … GHCR, apt … is never touched").

The plan's prescribed invocation (`cosign verify --offline=true
--new-bundle-format=false --trusted-root=<local> <digest>`) was **falsified** by the
probe: v3.1.1 has no `--new-bundle-format` and no non-deprecated `--offline`;
`--offline` is accepted-but-deprecated (removed in cosign v4) and, critically, does
**not** remove the registry round-trip — it only suppresses the online tlog/rekor
lookup. So even offline verification of the digest still needs a registry fetch for
the `.sig` referrer, and `docker pull` of the image does **not** pull that `.sig`.

The forcing tension: the verifier needs registry reach (ghcr.io) for the signature,
but reaching it from `docker0` requires either widening the shared container egress
allowlist or moving the verifier off `docker0`. The allowlist
(`cron-egress-allowlist.txt`) is a **grep-enumerated complete set** of hosts the
long-lived app container + its 4 in-container crons may dial ("Grep-enumerated from
runtime code, NOT intuited (sweep-class discipline)"). ghcr.io is dialed by **no**
runtime code — only by a deploy-time verify step.

## Considered Options

- **Design B — sandboxed bridge container + ghcr.io allowlist + deprecated `--offline`.**
  Single `docker run --rm <cosign> verify --offline --trusted-root=<root>
  --certificate-identity-regexp=… --certificate-oidc-issuer=… <digest>` on the
  default bridge; add `ghcr.io` to `cron-egress-allowlist.txt`; mount the deploy
  user's docker config so the container can auth the private `.sig` fetch.
  Pros: one invocation; minimal shell delta from today's code. Cons: **persistently
  widens the long-lived app+cron container's egress by one registry host for a
  deploy-time-only need**, violating the allowlist's sweep-enumerated-complete-set
  invariant (every compromised in-container cron gains ghcr.io as an egress option
  24/7); ships a deprecated flag.

- **Design C — host-side prefetch (`cosign save`) + fully-offline local verify
  (`--local-image --network none`).** Two invocations: `save` pulls image+sig to a
  local OCI layout, then `verify --local-image --trusted-root=<root> --network none`.
  Pros: the verify step is provably air-gapped (no credential, no network). Cons:
  the `save` step **still needs ghcr.io reach + the credential** (the `.sig` referrer
  is not host-pulled), so it does not eliminate either the ghcr reach or the
  credential-in-container — it only moves them to step 1. Net gain over a host-net
  single verify is marginal; cost is real (temp-dir lifecycle + cleanup trap + two
  `docker run`s + save-dir layout) for a WARN-only, single-user path.

- **Design B′ (chosen) — host-net ephemeral verifier + pinned trusted-root.** Single
  `docker run --rm --network host` cosign container. `--network host` puts the
  ephemeral verifier in the **host** network namespace, so its registry fetch is host
  OUTPUT (unrestricted, the exact path that already pulls the image from GHCR) — never
  FORWARD through `docker0`, so `iifname docker0` never matches and **no allowlist
  entry is needed**. Mount the host docker config (ro) for the private `.sig` fetch
  and the pinned `trusted_root.json` (ro) for the trust material. Pros: confines
  ghcr reachability to an ephemeral, SHA-pinned, single-command container instead of
  granting it persistently to the runtime container; no sweep-invariant violation;
  no sigstore egress dependency. Cons: `--network host` grants the ephemeral verifier
  full host-netns reach (bounded: `--rm`, pinned SHA, one `verify`, two ro mounts);
  retains the deprecated `--offline` under the frozen SHA (see Decision).

## Decision

> **The 2026-07-06 (#6122) header note that used to sit at the top of this file has MOVED HERE,
> as a decided fact rather than a forward-looking one — it described a migration that has since
> completed, and a reader met it before the Context that gives it meaning.** It read: the
> deploy-time cosign verifier topology decided here is unaffected and stays active; only the
> *credential-provisioning* arm (how the host authenticates the private pull + `.sig` fetch,
> ADR-088 D1) changes, because ADR-088's App-token minter was proven infeasible (GHCR refuses App
> tokens), so #6122 migrates the registry off GHCR to self-hosted zot — after which "GHCR" in
> this ADR means the zot endpoint, the mounted docker-config carries the zot credential instead
> of a GHCR PAT, and the `--network host` + pinned-trusted-root + offline verify shape is
> identical.
>
> **That substitution is now COMPLETE, in both halves, and #8036 1c (2026-09-23) finished it.**
> The mounted config carries the zot entry that `zot_gate_and_login` writes, and it no longer
> carries a GHCR one at all: the host-side GHCR login is deleted and `sweep_stale_registry_auth`
> removes any inline `ghcr.io` entry left on disk, once per deploy. Read every remaining "GHCR"
> in this ADR's Decision and Consequences as naming the zot endpoint.
>
> **ONE REQUIREMENT IS UNCHANGED AND MUST STAY VERBATIM:** the mounted config must carry an
> **inline** `auths.<registry>.auth` entry, **never** a `credsStore`/`credHelpers` indirection.
> The distroless cosign image ships no credential helper, so an indirection silently
> UNAUTHORIZEs the `.sig` fetch. This is registry-independent and survives every substitution
> above — it is a property of the verifier image, not of which registry is being talked to.
>
> **Naming caveat.** The script symbol holding that path is still `GHCR_DOCKER_CONFIG`
> (`${DOCKER_CONFIG}/config.json`). The name is a fossil after 1c: nothing GHCR-related is
> written there any more. The rename was weighed and CUT — it maps to no property, costs nine
> sites plus its test, and the only ADR clause that would have needed amending existed because
> of the rename. The symbol's header comment in `ci-deploy.sh` says the same thing; cite that
> comment, not this paragraph, when reading the code.

Adopt **Design B′**. `verify_image_signature` runs exactly one cosign container:

```
docker run --rm --network host \
  -v <host-docker-config.json>:/root/.docker/config.json:ro \
  -v <trusted_root.json>:/etc/cosign/trusted_root.json:ro \
  "$COSIGN_IMAGE" verify --offline \
    --trusted-root=/etc/cosign/trusted_root.json \
    --certificate-identity-regexp="$COSIGN_IDENTITY_REGEXP" \
    --certificate-oidc-issuer="$COSIGN_OIDC_ISSUER" \
    "$repo_digest"
```

- **Network: `--network host`.** This is the load-bearing choice. It routes the
  `.sig` fetch through unrestricted host egress (proven reachable — host dockerd
  already pulls the image from GHCR), so **`ghcr.io` is NOT added to
  `cron-egress-allowlist.txt`**. The egress-allowlist file is unchanged.
- **Credential: mount the host docker config read-only.** The PAT is already
  materialized on the host by the decided `docker login`. Caveat to honor at
  implementation: cosign's distroless image has no `docker-credential-*` helper, so
  the mounted config must carry an **inline** `auths."ghcr.io".auth` base64 entry, not
  a `credStore`/`credHelpers` indirection. If the host login uses a credential helper,
  materialize a purpose-built config.json (inline token from Doppler) for the mount,
  or point cosign at it via `DOCKER_CONFIG` / cosign registry flags. This is a
  correctness precondition, not an option.
- **Trust material: pinned `--trusted-root`.** Verification is deterministic against a
  version-controlled trust root — no dependency on live sigstore TUF/fulcio uptime on
  the deploy hot path. `trusted_root.json` provisioning is a shared prerequisite of any
  design (generate via `cosign trusted-root create` and vendor it to the host).
- **Retain `--offline` under the frozen SHA (reframed as intentional, not a crutch).**
  With host-net we *could* reach live rekor, but doing so adds latency + a sigstore-uptime
  dependency to every deploy. `--offline` deliberately uses the Rekor inclusion proof
  attached to the `.sig` (no live rekor call). Its deprecation is **inert**: the pinned
  cosign SHA (v3.1.1) freezes the flag's behavior; the "removed in v4" risk cannot bite
  until a deliberate, reviewed SHA bump. Record a `SOLEUR-DEBT:` marker at the invocation
  tying the migration to `--bundle` + `--trusted-root` to the cosign-SHA-bump trigger, so
  the next bump PR migrates the flag rather than discovering the break.

WARN semantics are unchanged: the function still returns 0 always in WARN mode, emits
the discriminating `cosign_verify_event` on failure, and echoes the verified digest
(TOCTOU-safe) on success.

> **Amendment reference (#6512, 2026-07-17):** this cosign-verify contract carries one documented
> exception. The `local-cache` reload tier added to `ci-deploy.sh` (ADR-079 `(#6512)` amendment)
> **skips re-verify** when it reuses the RUNNING container's image ID for a same-version seccomp
> reload — the reused bits are the exact @sha256 already live in production, so re-verifying is a
> no-op; the skip is made explicit via `cosign_verify_event` `verify_result=reused_local_reload`
> rather than falling through the WARN fail-open. See ADR-079 for the full rationale.

## Consequences

- **Easier:** verify can actually PASS on the real host (the #6005 goal) without
  touching the runtime egress boundary; the container allowlist keeps its
  sweep-enumerated-complete-set invariant; verification is deterministic (pinned
  trust root, no sigstore-uptime coupling); single invocation keeps the shell delta
  from today's code minimal.
- **Harder / accepted risks:** the ephemeral verify container runs with host-netns
  reach (bounded by `--rm` + pinned SHA + single command + two ro mounts — a
  well-understood, deploy-time-only exposure, materially smaller than a persistent
  runtime-container egress grant). The docker-config-must-be-inline caveat is a new
  provisioning constraint that must be verified on the host, else the `.sig` fetch
  silently `UNAUTHORIZED`s (WARN — non-blocking, but never passes). The deprecated
  `--offline` remains until the tracked SHA-bump migration.
- **Rejected — Design B:** persistently widening the shared container allowlist by
  ghcr.io for a deploy-time-only need is a standing blast-radius increase on the
  long-lived app+cron container and breaks the allowlist's documented
  grep-enumerated-from-runtime-code discipline. Avoiding it is a real, if bounded,
  security win — the decisive factor over B.
- **Rejected — Design C:** its only gain over B′ (an air-gapped verify step) does not
  eliminate the credential or the ghcr reach — the `save` step still needs both — so
  it buys defense-in-depth that is not justified by a WARN-only, single-user path
  today. C remains the right shape to revisit **at ENFORCE time**, when a provably
  air-gapped verify step earns its complexity.
- **Consequence note (2026-07-09, ADR-096 capacity-vs-retention amendment / #6247):** the
  zot `storage.retention` keep-set now **bounds** the previously-unbounded `sha256-.*`
  cosign sig-referrer tags at `mostRecentlyPushedCount` 50. This verify step fetches a
  kept image's `.sig` **by tag from the same registry it pulls the image**, so a mis-sized
  bound that pruned a kept image's sig would make verify `UNAUTHORIZED`/fail (WARN — non-
  blocking today; **blocking at the WARN→ENFORCE flip, #6129**). 50 is sized far above the
  true keep requirement (~12–18 sig-tags/repo) precisely so it never prunes a kept image's
  sig at current scale; `mostRecentlyPushedCount` is a push-ORDER heuristic that can evict
  out of order under the ADR-096 backfill/re-sign path, which is why the bound is generous.
  No change to this ADR's decision or topology.

## Cost Impacts

None. No new paid vendor or tier change. The `read:packages` machine-account PAT and
Doppler secret are already decided under #6005 and carry no incremental cost; GHCR
private-package storage/egress is within the existing GitHub plan.

## NFR Impacts

- Preserves the container-egress-containment posture (ADR-052 / #5046): the shared
  `@soleur_egress_allow` set is unchanged, so the "least-egress for the long-lived
  container" property is not degraded — the alternative (Design B) would have degraded
  it. No NFR-register row changes tier as a result of this decision; the net effect is
  "no regression to an existing security NFR that Design B would have moved backward."
- No latency NFR impact on the deploy path: `--offline` + pinned trusted-root avoids
  adding live sigstore round-trips.

## Principle Alignment

- **AP (least-privilege / minimize blast radius): Aligned** — confines ghcr.io
  reachability to an ephemeral deploy-time verifier rather than granting it
  persistently to the runtime container; leaves the sweep-enumerated allowlist intact.
- **AP (Doppler secrets): Aligned** — the GHCR PAT is sourced from Doppler and
  materialized to the host login; no secret is committed. The inline-auth config.json
  caveat keeps the credential on the host, mounted read-only into an ephemeral container.
- **AP (deterministic/pinned supply chain): Aligned** — SHA-pinned cosign + pinned
  trusted-root make verification reproducible and independent of sigstore uptime; the
  one deviation (deprecated `--offline`) is contained by the pin and tracked as debt.

## Amendment 2026-09-21 (#8036) — the verifier image is pulled anonymously

**What changed.** The verify `docker run` in `verify_image_signature()` now executes with the
docker CLI's `DOCKER_CONFIG` pointed at a fresh directory holding exactly
`{"auths":{},"credHelpers":{"ghcr.io":""}}`, and with `DOCKER_AUTH_CONFIG` unset. A bare
`{"auths":{}}` would not be enough: the CLI treats a config with no auth entries as unconfigured and
auto-detects a default credential store (`docker-credential-pass`/`secretservice` when on PATH),
which could still hand the pull a stored `ghcr.io` token. A non-empty `credHelpers` map disables
that detection, and the empty helper name resolves `ghcr.io` to the empty file store. The CLI resolves auths for the implicit `COSIGN_IMAGE` pull from its
own config, so the verifier **image** (`ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a…`, public) is
always pulled anonymously. The `-v "$GHCR_DOCKER_CONFIG:/root/.docker/config.json:ro"` mount is a
host-path bind resolved independently of the CLI's `DOCKER_CONFIG`, so the `.sig` referrer fetch
inside the container still authenticates to the registry the digest came from. The mounted
config's purpose therefore narrows to that `.sig` fetch alone. The Design B′ topology decided above
is unchanged.

**Why.** The implicit pull presented the deploy config's inline `ghcr.io` entry, a revoked classic
PAT. GHCR answers a revoked credential with DENIED where it serves the same public image
anonymously (measured 2026-09-21T07:49Z: `GET api.github.com/user` with the token → 401;
anonymous manifest HEAD on the pinned digest → 200). Every deploy classified that DENIED as
`IMAGE_VERIFY_FAIL result=cosign_absent`, so signature verification had not actually run for
seven weeks (#8037).

**A per-deploy dependency on public ghcr.io, stated.** `ci-deploy.sh` runs `docker image prune -af`
before the verify, and the verifier image has no live container, so it is pruned and re-pulled on
**every** deploy. It always was; the pull just used to fail. If the anonymous pull fails (a ghcr.io
outage or its anonymous rate limit), the run fails. It is classified `cosign_absent` only when
its stderr carries a pull error the classifier recognises (`manifest unknown`, `pull access
denied`, `no such image`); any other text reads `verify_failed`. The run passes `--quiet`, so the
cold pull's `Unable to find image … locally` progress line no longer reaches that classifier. Under WARN the deploy runs the digest unverified and Sentry receives
`cosign_verify_event`. Under ENFORCE it would block the deploy. **An ENFORCE flip must therefore
first decide whether to keep the verifier image locally** (excluded from the prune, or loaded from a
pinned tarball), and must cite the #8037 follow-through probe's PASS.

**Fallback.** If the isolated directory cannot be created or fails its content check, the verify
runs as before and `IMAGE_VERIFY_PREP: anon_config=unavailable` is logged. The #8037 probe grades a
verdict preceded by that line as action-required, so the fail-open cannot pass silently.

**Alternatives considered.**

- *Mint a new GHCR read credential for hosts.* Rejected: a host can only hold a personal
  credential (ADR-088 arm-b), which contradicts hr-github-app-auth-not-pat, and the verifier image
  needs no credential at all.
- *`docker logout ghcr.io` on relogin failure.* Deferred to #8036 1c (GHCR's fate on hosts): it
  changes the GHCR-fallback semantics, and the isolated config already buys the property.

**Status: CODE-DECLARED.** Merging applies `ci-deploy.sh` to the web host through the
`deploy_pipeline_fix` auto-apply; the amendment is LIVE only once a post-apply deploy logs
`IMAGE_VERIFY: ok`. The #8037 follow-through probe grades exactly that, per host.

## Amendment 2026-09-22 (#8037) — the verifier must be able to READ its mounted config

**What the record above got wrong.** The Decision's `-v <host-docker-config.json>:/root/.docker/config.json:ro`
mount, and the 2026-09-21 amendment's statement that "the `.sig` referrer fetch inside the container
still authenticates" because of it, were never true for the pinned image. They are kept as written.
This amendment corrects them, and it does not replace them.

**Measured 2026-09-22.**

- **The mount path was never read.** `ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a…` runs as uid
  65532 (`nonroot`, home `/home/nonroot` in the image's `/etc/passwd`). It sets neither `HOME` nor
  `DOCKER_CONFIG`, so cosign reads `/home/nonroot/.docker/config.json`. A config naming a nonexistent
  `credsStore: bogus` is ignored when mounted at `/root/.docker/config.json`. The same file is read,
  failing on `docker-credential-bogus`, when mounted at `/home/nonroot/.docker/config.json`.
- **The file is unreadable to that uid anyway.** `docker login` writes the deploy config `0600`, as
  the `deploy` user. Mounted at the right path, uid 65532 gets `open …: permission denied`.
- **Live consequence.** Once 1a let cosign start (#8456), the first deploy reported
  `IMAGE_VERIFY_FAIL: result=verify_failed … .sig: unexpected status code 401 Unauthorized` from zot.
  The `.sig` fetch had always gone out anonymous. That is the "has never succeeded" of #8037.

**Decision.** The verify `docker run` now passes `--user "$(id -u):$(id -g)"`, the owner of the `0600`
config (the trusted root is `0644`). It also passes `-e DOCKER_CONFIG=/cosign-docker`, with the deploy
config mounted `:ro` at `/cosign-docker/config.json`. The container's config location is therefore
explicit, and it no longer depends on the image's user or `HOME`. An offline `cosign verify` under
exactly these flags, with no `/etc/passwd` entry for the uid and so `HOME=/`, starts, reads the config,
queries the registry and returns a verdict, with no filesystem errors. Design B′'s topology (host
network, offline trusted root, ephemeral verifier) is unchanged.

**Guards.** `ci-deploy.test.sh` T-8037-1 asserts the property on the captured argv:

- exactly one user flag (`-u` or `--user`), and it is the invoking uid:gid
- exactly one `DOCKER_CONFIG` env in any form (`-e`, `--env`, `--env=`), whose value is where the deploy config is mounted, and no `--env-file`
- nothing mounted under `/root/.docker`

The EROFS relocation guard excludes the container-side `-e` as a whole line, so it cannot mask a real
re-point of the script's own `DOCKER_CONFIG`.

**Status: CODE-DECLARED.** It is LIVE once a post-apply deploy logs `IMAGE_VERIFY: ok`. The #8037
follow-through probe grades that per host.
