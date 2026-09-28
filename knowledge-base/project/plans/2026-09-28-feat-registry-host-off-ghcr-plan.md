---
title: "feat: registry host and deploy verifier stop pulling from ghcr.io (#8714 step 5.3b-iii)"
date: 2026-09-28
slug: feat-registry-host-off-ghcr
branch: feat-8714-53biii-off-ghcr
issue: 8714
type: enhancement
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: registry host and deploy verifier stop pulling from ghcr.io (#8714 step 5.3b-iii)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Two production pulls still read ghcr.io anonymously. The first is the deploy verifier's
`COSIGN_IMAGE` (`apps/web-platform/infra/ci-deploy.sh`), which web hosts pull on every deploy
because `docker image prune -af` removes it. The second is the zot registry host's own zot image
(`zot_image_*` in `apps/web-platform/infra/zot-registry.tf`), which `cloud-init-registry.yml` pulls
at first boot by `docker run '${zot_image}'`.

Step 5.3b-iii of #8714 moves both off ghcr.io, pins them by digest, and proves the mirrored bytes
equal upstream. Only after that does it remove the ghcr.io dependency, as a deny on the registry
host.

- **Cosign:** re-sourced to `gcr.io/projectsigstore/cosign@sha256:57c0e93a…6870`. This is the
  Sigstore project's own registry, with the **same manifest digest**. The image ID is identical to
  the ghcr ref (measured below). No byte changes.
- **zot:** the registry cannot pull its own image from itself (the bootstrap paradox), and
  project-zot publishes images only on ghcr.io. So the exact upstream blobs are packaged as a
  reproducible OCI-layout plus docker-save tarball and published as a GitHub release asset on
  this public repo. The host fetches it at boot and checks the pinned tarball sha256 (T). It then
  `docker load`s it and refuses to start zot unless the loaded image ID is the upstream config
  digest C (classic store) or manifest digest D (containerd store). zot runs by that verified ID.
- **Deny:** before the fetch, the registry host sinkholes `ghcr.io` and
  `pkg-containers.githubusercontent.com` in `/etc/hosts`. The heartbeat reports `ghcr_blocked`,
  `zot_image_fetch` (plus the remapped `zot_image_digest`). `state_status=running` with
  `ghcr_blocked=1` is then a live proof that the host booted and served with ghcr.io unreachable.

**Delivery is split into two PRs**, because the asset must exist before the registry replace
fires. PR 1 (#9120) makes the dispatcher replace the host on every rendered `user_data` change,
including this one.

- **PR 2a (enabling):** the builder script, the `zot-image-mirror.yml` `publish` job, the docs
  prerelease filter, and the **cosign flip** (with the gcr.io failure-string classifier). Merging it
  publishes the release through the `push` trigger, and delivers ci-deploy.sh through
  `apply-deploy-pipeline-fix`. It touches no registry render input, so no replace fires.
- **PR 2b (consuming):** the tf pins T and C, the cloud-init sinkhole/fetch/verify, the heartbeat
  fields, preflight P6, the `rehearse` job, rule-audit, the ADR-096/169 amendments, C4 and the
  runbooks. Merging it fires the replace, gated by P6.

## Research Insights

**Premise validation.**

- #8714 is OPEN. The 5.3b-iii text reads "Mirror or re-source those two images first", with the
  egress cut after.
- #9071 (5.4) is OPEN. It is the merge-order blocker for both PRs.
- #7582 / PR #9120 (dispatcher render gate) is OPEN. It is required so that a merged pin change
  actually replaces the host.
- The cited paths exist on `origin/main`: `ci-deploy.sh:143` `readonly COSIGN_IMAGE=`,
  `zot-registry.tf` `zot_image_{arm64,amd64}`, and `cloud-init-registry.yml` `'${zot_image}'
  serve`.
- "GHCR egress allow" is **stale as a mechanism**. No explicit egress rule exists: hcloud firewalls
  carry inbound rules only, and host egress is open. The step reduces to "nothing needs ghcr.io,
  proven by an enforced deny".
- ADR corpus check: ADR-096 Alternatives row 6 rejects a *managed registry for our own images*
  (Docker Hub/ECR/GCP AR/Quay). Cosign-from-gcr.io is a third-party verifier image fetched from its
  publisher, byte-identical, digest-pinned. It is not our images moving to a managed registry. The
  ADR-096 amendment records the distinction.
- ADR-087's anonymous-config design, `{"auths":{},"credHelpers":{"ghcr.io":""}}`, is unaffected.
  gcr.io has no helper configured, so the pull is anonymous (measured).

**Property list.**

- P1: The registry host obtains and starts zot at first boot without contacting ghcr.io.
- P2: The web deploy verifier obtains cosign without contacting ghcr.io.
- P3: Image verification still runs and emits a verdict. `IMAGE_VERIFY_MODE` stays `warn`, and
  `IMAGE_VERIFY: ok` keeps appearing after the flip.
- P4: zot runs only from bytes proven equal to the upstream pin D, byte-for-byte to the published
  tarball and by content address after load.
- P5: A missing, tampered or unreachable asset refuses the zot launch, and the refusal reason
  is discoverable from Better Stack without SSH.
- P6: ghcr.io is unreachable from the registry host after first boot, and this is observable.
- P7: No replace fires before the asset exists.
- P8: No public surface (docs changelog/version) shows the mirror release.

**Cut list.**

- Mirroring cosign into our zot (C2) → P2 → cut. The verifier would need zot credentials inside
  ADR-087's anonymous config. gcr.io at the same digest buys P2 with zero new trust.
- On-host per-blob verification before load → P4 → cut. T (pinned tarball sha256) plus the
  post-load ID ∈ {C, D} content-address check already cover it: docker verifies layer diff_ids
  against C (classic) and blob digests against D (containerd).
- A separate mirror repo or R2 bucket → hosting → cut. The public repo's releases serve it, and
  github.com egress is already a boot dependency (the Doppler CLI download, `cloud-init-registry.yml`
  `releases/download`).
- An explicit Hetzner egress firewall rule → P6 → cut. hcloud firewalls here carry no egress rules,
  and an IP-based rule for GitHub-hosted ghcr.io would be brittle. The `/etc/hosts` sinkhole
  enforces it on the only host whose boot we are proving.
- Publishing from a `pull_request` run → P7 → cut. There is no precedent for `contents: write` on
  `pull_request` here (repo research). The two-PR split buys P7 with triggers already in use
  (`push` to main, `workflow_dispatch`).

**Measurements** (2026-09-28):

- **Cosign:** `gcr.io/projectsigstore/cosign@sha256:57c0e93a829ae213ab4273b5bd31bc24812043183040882d7cc215a12b5a6870`
  pulls anonymously with ADR-087's exact anon config. It runs `GitVersion: v3.1.1`. Its local image
  ID and RepoDigests show the ghcr and gcr refs are **one image**.
  Command: `DOCKER_CONFIG=<anon> docker run --rm gcr.io/projectsigstore/cosign@sha256:57c0… version`.
- **Who reads `COSIGN_IMAGE`:** only `verify_image_signature` (`ci-deploy.sh` docker run
  `"$COSIGN_IMAGE" verify --offline`). ci-deploy.test.sh Guard 2 pins it to exactly one site, and
  ci-deploy.test.sh defines the literal. The only other hit is a comment in
  `reusable-release.yml` about the v3.1.1 skew.
- **Upstream zot v2.1.20:** these are OCI manifest v1 images, 17 layers each.

  | Arch | Manifest D | Config C | Upstream size |
  |---|---|---|---|
  | amd64 | `95a837a0…4fd5` | `2d7fee5603dfd88b2b90cffd07e6b97e6d7ba5e3d6bd5472e66b23bd5ad59114` | 74,386,093 B |
  | arm64 | `56230c5a…7ff6` | `22462b7c31a805ea133fd6a17b2e92a663620029ec03b2e1d04aa1ae4d3c45cb` | 67,800,988 B |

- **Reproducible archive** (the prototype builder: curl the anonymous ghcr token, fetch the
  manifest and blobs, sha256-check each, then GNU tar 1.35 `--sort=name --mtime=@0 --owner=0
  --group=0 --numeric-owner --format=ustar`):
  - amd64 T = `05b171f2bd500dc84f532ef7736d1550ffaf7464f0d655c86b8238b443568cb2`, 74,424,320 B.
  - arm64 T = `641e29375bc3b9ce7cff464c7e6569487f25ed98d22085be1116fbfe50e8777e`, 67,829,760 B.
  - Two independent builds were `cmp`-identical.
- **Load behaviour:**
  - The local docker 29.7.2 uses the containerd snapshotter. Loading the archive gives
    `Id == sha256:95a837a0…` (D), and `zot --version` runs.
  - `docker:28-dind` uses the classic overlay2 store. The same archive gives `Id == sha256:2d7fee56…`
    (C), and it runs.
  - A short local name (`soleur-local/...`) is NOT resolvable by `docker image inspect` on the
    containerd store, because the containerd name is not normalized. A fully-qualified
    `localhost/soleur-mirror/zot-linux-<arch>:v2.1.20` works on both stores.
- **Egress:** no explicit GHCR egress rule exists anywhere (egress open).
- **72 h baseline:** 82× `IMAGE_VERIFY: ok` and 0 fails. The registry reports
  `zot_image_digest=95a837a0afac` ×100.
- **Budget:** the registry `user_data` is 18,024 B stored against the 32,768 B cap, leaving
  14,744 B of headroom (`bash apps/web-platform/infra/registry-userdata-budget.sh`).
- **Public release consumers:**
  - `apps/web-platform/server/release-notes.ts` filters `web-v*` and excludes prereleases.
  - `cron-weekly-release-digest.ts` excludes prereleases.
  - **`plugins/soleur/docs/_data/github.js` excludes drafts only.** It shows `releases[0].tag_name`
    as the docs version and renders all 30 releases into the changelog. PR 2a adds
    `!r.prerelease`.

**Institutional learnings applied:**

- `2026-07-14-cloud-init-templatefile-escaping…`: `$${}` and no `%{`. The fetch script body is
  written with brace-free `$VAR` forms and `{{.Id}}`, so it contains no `${`.
- `2026-07-07-cloud-init-user-data-cap-is-measured-on-the-gzipped-render`: the budget is re-run
  after edits.
- `2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself`: T is anchored to the upstream
  D by the reproducible rebuild in the publish job (see the Guard Contract).
- `2026-09-21-curl-retry-flags…`: the asset fetch uses bounded `--retry`, and the stubs model
  failure.
- PR #9120's learning (an offline render gate inherits every stub): the budget script must read
  the new tf literals rather than stub them.

**Related:** #8714, #9071, #9120/#7582, #6129 (WARN→ENFORCE), ADR-096, ADR-087, ADR-169.

**Repo conventions:** worktrees and no stash; the PR body carries `Ref #8714`; infra changes are
delivered only through workflows (registry-host-replace-dispatch → apply-web-platform-infra; web
hosts through apply-deploy-pipeline-fix).

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "remove the GHCR egress allow" | No explicit allow exists; egress is open | Replace with an enforced, observed `/etc/hosts` deny on the registry host, and file the web-host deny as a follow-up |
| "mirror into our zot" | The registry cannot bootstrap from itself | Use a GitHub release asset carrying the exact upstream blobs |
| zot on a non-ghcr registry | project-zot is only on ghcr.io (quay, ECR, Docker Hub, gitlab absent) | Same as above |

## Plan Review Revisions [Updated 2026-09-28]

A seven-seat panel reviewed the plan: DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow, CTO (devex) and CPO (sign-off). The changes below are applied, and the sections
below reflect them.

- **Cosign moves to PR 2a** (spec-flow, CTO). It does not depend on the asset. This decouples
  its `apply-deploy-pipeline-fix` delivery from the registry replace, and the AC-L3 clock starts
  at 2a's delivery.
- **Future bumps.**
  - A new gating preflight predicate **P6** in `scripts/registry-replace-preflight.sh` checks
    that the rendered asset URL's release asset exists and that GitHub's asset `digest` equals the
    pinned T. The dispatcher then cannot replace the host onto an unpublished asset, for this PR
    or any later bump (architecture P1).
  - The bump procedure is: dispatch `publish` on the bump branch
    (`gh workflow run zot-image-mirror.yml --ref <branch>`), pin T/C, then merge (CTO, spec-flow,
    architecture). Upstream D anchors the bytes, so a branch dispatch is safe.
- **C and T are anchored before merge.** `rehearse` runs the builder before the sinkhole and
  asserts that the rebuild equals the pinned T and that the tf C equals the upstream manifest's
  config digest (architecture P2). It runs on `ubuntu-24.04` (pinned, not `-latest`), so the GNU
  tar version is fixed (CTO).
- **amd64 only** (simplicity). The mirror publishes and pins amd64 only. A tf precondition
  refuses `registry_arch != "amd64"` with a message naming the missing mirror pins. The
  `zot_image_arm64` upstream record stays, because the staleness/rule-audit probes read it.
- **Heartbeat fields cut to `zot_image_fetch` and `ghcr_blocked`** (DHH, simplicity). There is no
  `zot_image_source`/`zot_image_id` and no legacy `@sha256:` arm, because the new script only runs
  on replaced hosts. `zot_image_digest` reports D12 iff the container's `.Image` is C or D (from
  `/etc/default/zot-image`), and `unknown` otherwise.
- **Tag derived:** `zot_mirror_release = "zot-image-${local.zot_version}"`. There is no
  hand-typed literal and no staleness row for it.
- **rule-audit:** only the asset-digest probe, via `gh api repos/.../releases/tags/<tag>` asset
  `digest` == T. There is no 75 MB download, and the gcr probe is cut (IMAGE_VERIFY_FAIL already
  pages).
- **Cosign test** asserts that the ref is not `ghcr.io` and is `@sha256:`-pinned. The digest is
  not permanently pinned (DHH).
- **ADR-087 note cut.** The ADR-096 amendment carries it. **ADR-169 gets an amendment**: asset
  availability becomes a replace precondition (P6) (architecture P2).
- **C4:** the edge label names "gcr.io (Google-hosted Sigstore publisher)" (architecture P3).
- **Sinkhole persistence:** runcmd appends to `/etc/hosts` AND to
  `/etc/cloud/templates/hosts.debian.tmpl` when it exists, so a `manage_etc_hosts: true` reboot
  keeps it. This is worded as a **name-resolution deny** (spec-flow).
- **Recovery path** (CPO, CTO, spec-flow). The runbook names it, and it is workflow-only with no
  SSH:
  - revert PR 2b; the dispatcher re-renders and replaces the host with the ghcr.io pull;
  - for `download_failed`, re-fire the replace dispatch;
  - for a deleted asset, re-dispatch `publish` (reproducible) and let P6 go green.

  `zot-image-*` releases are never deleted.
- **Publish:**
  - a `concurrency:` group, never cancelling;
  - the release title/body states "infrastructure mirror artifact — not a Soleur release" (CPO);
  - an existing asset is verified by content: download it, check index → D and every blob hash.
    This avoids tar-version coupling (CTO #4). The upload-missing arm is kept.
- **Rehearse** triggers are `pull_request` plus `workflow_dispatch` (DHH).
- **Kieran:**
  - The fetch is its own runcmd entry OUTSIDE `doppler run`, between the sinkhole and ZOTEOF, so
    the LUKS key and tokens never reach curl or docker load. It writes the verified ID to
    `/run/soleur/zot-image-id`. ZOTEOF reads that file and shape-checks it
    (`sha256:` + 64 hex), or exits.
  - `docker load` stdout goes to stderr (`>&2`).
  - curl uses `--proto =https --proto-redir =https`.
  - The heartbeat maps from the EXISTING `.Config.Image`, which is `sha256:<id>` when zot runs by
    ID. There is no new inspect field.
  - An absent state file reports `zot_image_fetch=not_run`. The LUKS gate refusing before the
    fetch then reads as a named verdict.
  - ci-deploy's `cosign_absent` classifier also matches gcr.io failure strings
    (`toomanyrequests|no such host|dial tcp|i/o timeout|TLS handshake timeout`), with test rows,
    so a gcr.io outage is reported as `cosign_absent`, not `verify_failed` (2a).

## Files to Create

**PR 2a:**

- `apps/web-platform/infra/zot-image-oci-archive.sh` — the builder, which reads D and the version
  from `zot-registry.tf` (`zot_image_amd64`).
  - `build <out.tar>`: fetches via the anonymous ghcr token, then verifies the manifest == D and
    every blob == its digest.
  - It writes `oci-layout`, an `index.json` that names `localhost/soleur-mirror/zot-linux-amd64:<ver>`,
    a `manifest.json` (legacy docker-load) and `blobs/`, as a deterministic ustar. It prints C, T
    and the byte count.
  - `verify <tar>`: a content check (index → D, all blobs hash). Publish uses it for an existing
    asset.
- `apps/web-platform/infra/zot-image-oci-archive.test.sh` — offline, with a stub curl serving a
  synthesized fixture. Rows:
  - tampered blob → refuse;
  - manifest ≠ D → refuse;
  - two builds are byte-identical;
  - `verify` refuses a tampered tar and passes a good one;
  - a different, valid layer count passes.
- `.github/workflows/zot-image-mirror.yml`:
  - `publish` job, `contents: write`, triggered by `push` main (paths: builder, workflow) and
    `workflow_dispatch`. It creates the prerelease `zot-image-<ver>` (`--latest=false`) if absent,
    uploads a missing asset, and runs `verify` against an existing one.
  - In 2b, `rehearse` is added (below).

**PR 2b:**

- `apps/web-platform/infra/zot-image-fetch.test.sh` — this runs the fetch script extracted from
  `cloud-init-registry.yml`, with stub `curl`/`docker` and a call log, and asserts on the
  rendered template (see Test Scenarios).

## Files to Edit

**PR 2a:**

- `apps/web-platform/infra/ci-deploy.sh` `readonly COSIGN_IMAGE=`: the gcr.io ref, same digest,
  with an updated comment. The `cosign_absent` classifier regex gains the gcr.io failure strings. `ci-deploy.test.sh`: the literal changes, and a row asserts the ref is
  not `ghcr.io` and is `@sha256:`-pinned.
- `plugins/soleur/docs/_data/github.js`: `!r.draft && !r.prerelease`.
  `plugins/soleur/test/plugin-version-fallback.test.ts`: a row where a prerelease newest is skipped
  for the version and the changelog.

**PR 2b:**

- `apps/web-platform/infra/zot-registry.tf`:
  - Locals: `zot_mirror_asset_sha256_amd64` (T) and `zot_config_digest_amd64` (C) as literals.
  - Derived: `zot_version` and `zot_manifest_digest` (regex over `local.zot_image_amd64`),
    `zot_mirror_release`, and `zot_mirror_asset_url`.
  - The templatefile map passes `zot_asset_url`, `zot_asset_sha256`, `zot_manifest_digest`,
    `zot_config_digest` and `zot_local_ref` (replacing `zot_image`).
  - A precondition requires `registry_arch == "amd64"`.
- `apps/web-platform/infra/cloud-init-registry.yml`:
  - write_files `/etc/default/zot-image` (the five templated values) and
    `/usr/local/bin/zot-image-fetch.sh` (a brace-free body; it writes
    `/var/lib/soleur/zot-image-fetch.state`, prints only the ID on stdout, and logs to stderr).
  - An early runcmd sinkhole entry covers `/etc/hosts` plus the cloud hosts template.
  - A new runcmd entry (outside Doppler, after the sinkhole and `systemctl enable --now docker`,
    before ZOTEOF) runs the fetch.
  - ZOTEOF reads `/run/soleur/zot-image-id` and shape-checks it; `docker run … "$ZOT_IMAGE_ID"`.
  - In the heartbeat, `zot_image_digest` is mapped from `.Config.Image`: `sha256:<C|D>` → D12, and
    anything else → `unknown`. `zot_image_fetch` (with `not_run` when the state file is absent)
    and `ghcr_blocked` go before `host=`.
- `apps/web-platform/infra/registry-userdata-budget.sh` and its test: read the new literals
  (missing → exit 2) and add a row.
- `scripts/registry-replace-preflight.sh` and its test: P6 (asset present and digest == T),
  GATING and fail-closed.
- `apps/web-platform/infra/registry-boot-guard.test.sh`: field enumeration.
- `.github/workflows/rule-audit.yml`: the asset-digest probe (one idempotent issue).
- `.github/workflows/zot-image-mirror.yml`: the `rehearse` job on `pull_request` (paths also
  include `zot-registry.tf` and `cloud-init-registry.yml`) and `workflow_dispatch`, on
  `ubuntu-24.04`:
  1. Build, then assert == T and C == the manifest config.
  2. For each store in the matrix: set the docker store, sinkhole, and assert that a ghcr.io
     connection fails.
  3. Render `/etc/default/zot-image` and the fetch script from the real template (the
     budget-script render), and run the fetch against the real URL.
  4. Start zot by ID and assert `/v2/` answers.
- `apps/web-platform/infra/zot-image.provenance.md`: the bump procedure, recovery, and never
  delete.
- `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`:
  - the `zot_image_fetch` verdicts → action;
  - the recovery path;
  - P6.
- ADR-096 amendment, ADR-169 amendment. C4 `model.c4` edges and descriptions.

## Open Code-Review Overlap

Checked at work time against `gh issue list --label code-review --state open` for every path
above. Dispositions are recorded in `tasks.md`.

## Implementation Phases

### Phase 2a — enabling PR (no render input touched)

1. RED: the builder test (script absent), the cosign row (ghcr literal) and the github.js row.
2. Write the builder until GREEN. Locally, T == `05b171f2…`.
3. Cosign flip; github.js filter; the `publish` workflow.
4. Suites: builder, ci-deploy.test.sh, plugin-version-fallback. actionlint.
5. Review, then ship. Hold the merge until #9071 is MERGED (operator instruction).
6. Post-merge:
   - `publish` succeeds, and both the asset `digest` and a downloaded sha256 equal T;
   - `apply-deploy-pipeline-fix` delivers ci-deploy.sh;
   - `scripts/followthroughs/cosign-verify-live-8037.sh` (or the Better Stack query) shows
     `IMAGE_VERIFY: ok` after delivery;
   - the docs build excludes `zot-image-*`.

### Phase 2b — consuming PR (from main after 2a and #9120 merge)

1. RED:
   - the fetch unit test;
   - the rendered-template test;
   - the budget row;
   - preflight P6;
   - the heartbeat rows.
2. tf locals, map and precondition; the budget script. Budget re-measured.
3. cloud-init: env file, fetch script, sinkhole, ZOTEOF wiring, heartbeat.
4. Preflight P6; the rehearse job; rule-audit.
5. Docs: ADR-096/169 amendments, C4, provenance, runbook.
6. Targeted suites, then push. `rehearse` (both stores), `infra-validation` and `test` must be
   green.
7. Before merging:
   - Predict that the dispatcher delivers and that P6 is CLEAR.
   - Confirm no apply-web-platform-infra.yml run is queued or in progress.
   - Arm auto-merge (never admin).
8. After merging:
   - Watch the dispatcher → apply run. An environment approval is reported to the orchestrator
     with the run URL.
   - Collect the Better Stack evidence.
   - Tick 5.3b-iii on #8714 with an evidence comment, and file the web-host deny follow-up.

## Infrastructure (IaC)

### Terraform changes

- `zot-registry.tf` gets locals only. There are no new resources, providers or sensitive
  variables. The asset URL, T, C and D are public, non-secret literals baked into `user_data`,
  the same class as `zot_image` today.

### Apply path

- (c) replace: the registry host is immutable (`hr-prod-host-config-change-immutable-redeploy`), and
  a `user_data` change reaches it only through replace. The route is
  registry-host-replace-dispatch.yml (the PR #9120 render gate) → apply-web-platform-infra.yml
  registry replace.
- Expected blast radius: the store volume survives the replace (ADR-169). zot is unavailable for
  the replace window (minutes), running web containers keep serving, and a deploy in that window
  waits or fails.
- The web-host change (ci-deploy.sh) goes through apply-deploy-pipeline-fix. There is no replace.

### Distinctness / drift safeguards

- The asset tag is immutable by policy: the publish job never clobbers, and rule-audit detects
  replacement or deletion of the asset.
- `zot_image_*` stays the upstream record, so D10/staleness/rule-audit consumers are unchanged.
- There is no dev/prd split for the registry host (single prd host).

### Vendor-tier reality check

- GitHub release assets on a public repo are free, with a 2 GiB/file limit (the assets are about
  75 MB).
- gcr.io anonymous pulls are rate-limited per IP. That is one pull per deploy per host, the same
  cadence as today's ghcr pull.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_ZOT_DISK heartbeat row from the registry host carrying state_status, zot_image_digest, zot_image_fetch, ghcr_blocked; and IMAGE_VERIFY ok/fail rows from web deploys
  cadence: registry heartbeat cron (existing zot-disk-heartbeat cadence) + first-boot runcmd emit; IMAGE_VERIFY once per deploy per host
  alert_target: existing Better Stack zot liveness heartbeat (absence alarm) and registry alarms; Sentry cosign_verify_event for verify failures
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (zot-disk-heartbeat.sh, zot-liveness-heartbeat), apps/web-platform/infra/ci-deploy.sh verify_image_signature
error_reporting:
  destination: Better Stack Logs (SOLEUR_ZOT_DISK, IMAGE_VERIFY rows) + Sentry (cosign_verify_event)
  fail_loud: a refused fetch never starts zot, so the liveness heartbeat goes absent (alarm) and the disk heartbeat carries zot_image_fetch=<refusal verdict>; a cosign pull failure emits IMAGE_VERIFY_FAIL result=cosign_absent to Better Stack and Sentry
failure_modes:
  - mode: release asset missing or unreachable at boot
    detection: zot_image_fetch=download_failed state_status=unknown in SOLEUR_ZOT_DISK; rule-audit asset probe
    alert_route: zot liveness heartbeat absence alarm + rule-audit issue
  - mode: asset bytes differ from pinned T (tamper or replaced asset)
    detection: zot_image_fetch=sha_mismatch; rule-audit asset sha probe
    alert_route: zot liveness heartbeat absence alarm + rule-audit issue
  - mode: loaded image ID not in {C, D}
    detection: zot_image_fetch=id_mismatch
    alert_route: zot liveness heartbeat absence alarm
  - mode: name-resolution deny not in effect (e.g. lost across a reboot)
    detection: ghcr_blocked=0 in SOLEUR_ZOT_DISK
    alert_route: none standing (nothing on the host needs ghcr.io; the deny is proof, not protection) — post-merge evidence gate AC-L2; persistence via the cloud hosts template
  - mode: replace dispatched onto an unpublished or altered asset
    detection: registry-replace-preflight.sh P6 (asset digest != pinned T or asset absent)
    alert_route: the dispatcher refuses the replace (red run, existing verdict route)
  - mode: gcr.io cosign pull fails on a web host
    detection: IMAGE_VERIFY_FAIL result=cosign_absent (Better Stack) + Sentry cosign_verify_event (classifier extended to gcr.io failure strings)
    alert_route: Sentry cosign_verify_event; standing enforcement is #6129 (WARN->ENFORCE)
logs:
  where: Better Stack Logs source for the registry host and web hosts; GitHub Actions logs for zot-image-mirror.yml
  retention: Better Stack plan retention; GitHub 90 days
discoverability_test:
  command: curl -sSIL -o /dev/null -w '%{http_code}' https://github.com/jikig-ai/soleur/releases/download/zot-image-v2.1.20/zot-linux-amd64-v2.1.20.oci.tar
  expected_output: "200"
```

## Encryption Posture

```yaml
at_rest:
  - store: GitHub release asset zot-image-v2.1.20 (public repo)
    mechanism: plaintext-exception
    evidence: the asset is a public, unmodified copy of a public upstream image; integrity (not confidentiality) is the property, enforced by the pinned sha256 T in zot-registry.tf and the post-load image ID check against upstream C/D
    defends_against: substitution of the zot image between publish and boot (sha256 T), and a wrong-content load (ID in {C, D})
    does_not_defend: availability — deletion of the asset refuses the boot (detected by rule-audit and the heartbeat); a compromise of upstream project-zot itself at digest D (same trust as today)
    disclosed_as: ADR-096 amendment 2026-09-28
    live_verification: post-merge SOLEUR_ZOT_DISK zot_image_fetch=ok zot_image_digest=95a837a0afac
  - store: registry host docker image store and /var/lib/soleur/zot-image-fetch.state (root disk)
    mechanism: plaintext-exception
    evidence: public image layers and a one-word verdict; no secret or personal data
    defends_against: n/a for confidentiality; integrity via content addressing
    does_not_defend: root on the host can alter them (same as today's pulled image)
    disclosed_as: this plan
    live_verification: zot_image_digest reported only when the running image ID is C or D
in_transit:
  - connection: registry host -> github.com release asset (and its redirect host)
    tls: HTTPS
    cert_verification: on
    does_not_defend: a compromised GitHub account publishing a different asset under the tag — the pinned T refuses it
    disclosed_as: ADR-096 amendment 2026-09-28
  - connection: web host dockerd -> gcr.io (cosign verifier image)
    tls: HTTPS
    cert_verification: on
    does_not_defend: registry-side substitution is refused by the @sha256 digest pin
    disclosed_as: ADR-096 amendment 2026-09-28
exception:
  justification: both plaintext-exception rows are public artifacts whose protected property is integrity, enforced by digest pins; there is nothing confidential to encrypt
  tracking_issue: "#8714"
  reevaluate_when: a private or non-public image is mirrored through this path
  expires_on: 2027-09-28
```

## Guard Contract

### Guard 1 — host fetch verifier (zot-image-fetch.sh + ZOTEOF wiring)

**Property.** zot starts only from an image whose tarball bytes equal the pinned T and whose
post-load image ID is the upstream config digest C or manifest digest D; every other outcome
refuses the launch and records a verdict.

**Assembly.** The chokepoint is the single `docker run … zot` in the ZOTEOF block. Its image
argument must be `"$ZOT_IMAGE_ID"`, which the fetch script produces. The fetch script's verdict
arms are config_invalid, download_failed, sha_mismatch, load_failed, id_mismatch and ok. The
rendered-template test asserts the whole rendered `user_data` has exactly one `docker run`
naming zot, and no `'${zot_image}'`/registry ref as its image.

**Mutation matrix.**

| # | Mutation (to the design) | Must red |
|---|---|---|
| M1 | drop the sha256 compare (always pass) | fetch test "sha mismatch refuses and never calls docker load" |
| M2 | accept any loaded ID | fetch test "ID not in {C,D} refuses, no stdout ID" |
| M3 | fetch exits 0 on curl failure (own dispatch) | fetch test "download failure refuses with verdict download_failed" |
| M4 | ZOTEOF reverts to `'${zot_image}'` / a registry ref | rendered-template test |
| M5 | REORDER: sinkhole entry moved after the fetch entry | rendered-template order test (sinkhole index < fetch-entry index < ZOTEOF docker run index) |
| M7 | fetch entry moved INSIDE the doppler-run ZOTEOF block | rendered-template test: the fetch invocation is not inside any `doppler run` entry |
| M6 | second member: accept C, and also a third digest appended to the allowed set | fetch test "C passes, D passes, a third id refuses" |

**Harness rows.** RED: a docker stub that ignores `load` but reports ID C must still red M1,
because the sha row asserts the stub's `load` was never invoked (via a call log). Must-PASS
non-canonical inputs: the classic-store ID (C) and the containerd-store ID (D), each alone.

**Anchor.** T and C live in `zot-registry.tf`. D is anchored OUTSIDE the commit: `rehearse` runs
on the PR, rebuilds the archive from upstream ghcr.io content for D, and fails if the rebuild ≠ T
or if C ≠ the manifest config. A PR that edits T and the asset together cannot pass without
reproducing the upstream bytes.

### Guard 2 — publish idempotency and reproducibility (zot-image-mirror.yml publish + builder)

**Property.** The asset published under `zot-image-<ver>` is byte-identical to the reproducible
rebuild from upstream D, and an existing asset is never overwritten.

**Assembly.** The builder's `build` path (the manifest == D check, the per-blob checks and the
deterministic tar) and the publish job's three arms: create, upload-missing, and
verify-existing.

**Mutation matrix.**

| # | Mutation | Must red |
|---|---|---|
| M1 | skip the per-blob sha check | builder test "tampered blob refuses" |
| M2 | drop `--sort=name`/`--mtime=@0` | builder test "two builds byte-identical with shuffled fixture mtimes/order" |
| M3 | publish uses `--clobber` or skips `verify` on an existing asset | builder test: `verify` of a tampered tar refuses; publish body calls `verify` on the existing-asset arm (anchored on the call form) |
| M4 | `verify` checks the index → D but not every blob (it stops after the first blob) | builder test: a tar with a good first blob and a tampered second blob refuses |

**Harness rows.** RED: a stub curl that serves the canonical fixture for every URL must red the
"manifest ≠ D" row. Must-PASS: a fixture with a different, but valid, layer count.

**Anchor.** Upstream D at ghcr.io.

### Guard 3 — replace preflight P6 (asset exists and matches the pin)

**Property.** The dispatcher never replaces the registry host unless the release asset that the
rendered `user_data` will fetch exists and its GitHub-reported `digest` equals the pinned T.

**Assembly.** `scripts/registry-replace-preflight.sh` is the single chokepoint before the dispatch,
because every automated and manual replace dispatch goes through its verdict. P6 reads the URL
and T from the same tf literals the render uses (the budget-script reader).

**Mutation matrix.**

| # | Mutation | Must red |
|---|---|---|
| M1 | P6 returns CLEAR when the API call fails (own dispatch) | preflight row "API error → refuse" |
| M2 | P6 compares against a hardcoded T instead of the tf literal | preflight row "tf T changed, asset digest old → refuse" |
| M3 | P6 checks presence only, not the digest | preflight row "digest ≠ T → refuse" |
| M4 | P6 made advisory (non-gating) | preflight row asserting a non-zero exit with `predicate=P6` |

**Harness rows.** RED: a stub gh that returns the matching digest for every tag must red M2
through the tf-changed row. Must-PASS: an asset list where the matching asset is not the first
entry.

**Anchor.** The asset digest is computed by GitHub, outside the repo. T is anchored to upstream D
by `rehearse`'s rebuild on the PR.

## Architecture Decision (ADR/C4)

### ADR

- Amend ADR-096: "Amendment 2026-09-28 (5.3b-iii)". It records:
  - the zot bootstrap source (a release asset from exact upstream blobs, pinned T, ID ∈ {C, D});
  - cosign from gcr.io at the same digest, and the distinction from Alternatives row 6;
  - the registry-host ghcr deny;
  - that web hosts still have no ghcr deny (follow-up);
  - that the ADR stays proposed until 5.6.
- Amend ADR-169: asset availability is a replace precondition (P6), and the release is the new
  boot dependency of the sole pull path.

### C4 views

- The three model files are read.
- Edges:
  - `hetzner -> ghcr` (the cosign verifier pull) is re-targeted to `sigstore`, and the label names
    "gcr.io (Google-hosted Sigstore publisher)".
  - `zotRegistry -> projectZot` is replaced by `zotRegistry -> github` (the release-asset fetch at
    boot) and `github -> projectZot` (the mirror workflow's pull).
  - `projectZot` and `ghcr` descriptions are updated.
  - The `views.c4` includes are unchanged (the elements already exist).
- Validation: `plugins/soleur/test/c4-count-parity.test.sh` and the `apps/web-platform/test/c4-*`
  tests.

### Sequencing

- ADR-096 stays proposed. 5.6 flips it.

## User-Brand Impact

- **If this lands broken, the user experiences:** a registry host that never starts zot after the
  replace. New deploys and fresh web boots cannot pull the app image, so a fix or a feature does
  not reach users. Running containers keep serving. A broken cosign pull makes every deploy log
  `IMAGE_VERIFY_FAIL result=cosign_absent` and ship unverified in warn mode.
- **If this leaks, the user's data / workflow / money is exposed via:** a substituted zot binary
  serving tampered app images to every web host. Cosign is in warn mode, so a tampered unsigned
  image would still deploy. This plan's guards (the pinned T, ID ∈ {C, D}, the upstream-anchored
  rebuild) exist to close that vector.
- **Brand-survival threshold:** single-user incident

CPO sign-off is required at plan time (see the Domain Review). `soleur:engineering:review:user-impact-reviewer`
runs at review time.

## Acceptance Criteria

### Pre-merge (PR 2a)

- [ ] AC-A1: `zot-image-oci-archive.test.sh` is green. `build amd64`/`build arm64` locally print
  T equal to the measurements above.
- [ ] AC-A2: `github.js` excludes prereleases; its test row is green.
- [ ] AC-A3: actionlint is clean. `test` is green on the PR head. The ci-deploy.test.sh cosign
  rows are green, including the gcr.io failure-string classifier rows.

### Post-merge (PR 2a)

- [ ] AC-A4: the merge push's `zot-image-mirror.yml` publish run succeeds. The amd64 asset's API
  `digest` and a downloaded sha256 both equal T. The release is a prerelease, not latest, and its
  title and body say it is an infrastructure mirror artifact.
- [ ] AC-A5: the docs data (`github.js` run against the live API) shows neither a version nor a
  changelog entry for `zot-image-*`.
- [ ] AC-A6: `apply-deploy-pipeline-fix` delivers ci-deploy.sh (run id recorded). The first
  post-delivery deploy logs `IMAGE_VERIFY: ok` with no `IMAGE_VERIFY_FAIL`, per Better Stack
  (`scripts/betterstack-query.sh --grep IMAGE_VERIFY`) since the delivery time.

### Pre-merge (PR 2b)

- [ ] AC-B1: the fetch test covers all six verdict rows and the M1–M6 rows. It is green, and each
  mutation is driven RED once and reported.
- [ ] AC-B2: rendered-template assertions:
  - zero non-comment `ghcr.io`;
  - the order is sinkhole < fetch < docker run;
  - one zot `docker run`, image `"$ZOT_IMAGE_ID"`.
- [ ] AC-B3: the budget script measures and stays under the cap. Headroom is reported.
- [ ] AC-B4: `rehearse` is green on the PR head for both `classic` and `containerd`. It fetched the
  real asset with ghcr.io denied and `/v2/` answered.
- [ ] AC-B6: `registry-replace-preflight` test rows for P6 (asset absent → refuse, digest ≠ T →
  refuse, digest == T → CLEAR) are green.
- [ ] AC-B5: staleness plus its mutation test,
  registry-boot-guard, registry-render-delta, the budget test, the verdict test and the C4 tests are
  green locally. `test` and `infra-validation` are green on the head.

### Post-merge (PR 2b)

- [ ] AC-L1: the dispatcher run on the merge push delivers. The registry replace run
  (apply-web-platform-infra.yml) concludes success, and its run id is recorded.
- [ ] AC-L2: Better Stack shows a SOLEUR_ZOT_DISK row with a NEW boot_id and all of:
  `state_status=running`, `zot_image_digest=95a837a0afac`, `zot_image_fetch=ok`,
  `ghcr_blocked=1`.
- [ ] AC-L3: P6 printed CLEAR on the dispatcher run. The runbook documents the recovery path
  (revert 2b → dispatcher replace; re-fire; re-publish) and it is reachable without SSH.
- [ ] AC-L4: #8714's 5.3b-iii box is ticked with an evidence comment. The web-host ghcr-deny
  follow-up is filed and listed on the `Filed:` line.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruling was obtained earlier in this session and is binding:

- cosign C1 (gcr.io, same digest); C2 (mirror into zot) rejected;
- zot from a pinned GitHub release asset with an on-host T check and ID ∈ {C, D};
- the ghcr sinkhole on the registry host with a probe field;
- a rehearsal with the deny;
- rule-audit probes;
- an ADR-096 amendment.

This plan refines the ruling in three ways: it accepts ID ∈ {C, D} for both docker stores, it
builds the asset from upstream blobs rather than `docker save`, and it splits delivery into 2a/2b
so the asset precedes the replace.

### Product/UX Gate

Not applicable. There is no UI surface. The only public-surface change is removing a
prerelease from the docs changelog feed.

Legal: not relevant. These are anonymous pulls of public images, and no personal data reaches a
new processor.

## Test Scenarios

- **Fetch script** (stubbed curl/docker with a call log):
  - ok with C;
  - ok with D;
  - sha mismatch (load never called);
  - download failure;
  - load failure;
  - id mismatch;
  - an env value that is not hex64 or not an https github.com URL → config_invalid;
  - a state file is written for every arm.
- **Rendered template:** order, the no-ghcr count, and the docker-run image argument.
- **Builder:** tamper, reproducibility, and manifest ≠ D.
- **Heartbeat:** extract `zot-disk-heartbeat.sh` and feed a stubbed `docker inspect`. The rows are
  an ID-ref C, an ID-ref D, a legacy `@sha256:` ref, a foreign ID, and a sinkhole
  present/absent/unresolvable. Assert the four fields and that `zot_last_err` stays last.
- **Live** (post-merge): AC-L1..L4.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6.
- The containerd image store does not normalize a short local image name. Always use a
  fully-qualified `localhost/…` name, or `docker image inspect` fails after a successful load.
- Accept both C and D. Which store the host uses depends on the docker.io 29.1.3 packaging default
  and is not asserted here.
- The fetch script body must stay free of `${` and `%{` (templatefile interpolations and
  directives). Use `$VAR` and `{{.Id}}`, and never `curl -w '%{…}'`: the discoverability probe
  uses that form, but it must not be copied into the template.
- Do not merge PR 2b while any apply-web-platform-infra.yml run is queued or in progress. Its
  merge fires the replace.
- Every push-triggered workflow whose `paths:` include a file PR 2b edits (`zot-registry.tf`,
  `cloud-init-registry.yml`) must be enumerated at work time. The intended route is the
  dispatcher, because `zot-registry.tf` is an auto-apply `OPERATOR_APPLIED_EXCLUSION`. The
  apply-web-platform-infra push arm must be shown not to reach `hcloud_server.registry`.
  (Sharp-edges catalogue: "enumerate EVERY workflow that can apply it".)
- PR 2a is a foundations PR, and its surfaces are all contract-free in production:
  - the builder has no host caller;
  - `publish` only writes a release;
  - the cosign flip is a behavior change on an already-live path, delivered and verified by
    AC-A6.
