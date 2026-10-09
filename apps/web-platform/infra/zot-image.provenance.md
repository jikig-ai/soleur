# zot registry image — pin provenance

Analysis of record for the `zot_image_amd64` / `zot_image_arm64` pins in `zot-registry.tf`.
Read by `zot-image-staleness.test.sh` (CI gate) and by the upstream-poll step in
`.github/workflows/rule-audit.yml` (detection). Mirrors the shape of
`cosign-trusted-root.provenance.md` so both sidecars share one parseable format.

**zot is the sole pull path** (ADR-096, 2026-07-30 amendment) with no fallback. A wrong pin
here does not degrade the fleet — it darks it. Treat every row below as load-bearing.

| Field | Value |
|---|---|
| Pinned version | **v2.1.22** |
| Upstream release date | 2026-10-06T16:50:05Z |
| Capture date (UTC) | **2026-10-08** |
| Superseded | v2.1.20 (2026-08-04) — 128 commits and one breaking change (#4363) behind at time of bump (#9252) |

## Current pin

| Arch | Reference |
|---|---|
| amd64 | `ghcr.io/project-zot/zot-linux-amd64:v2.1.22@sha256:46f688dc26315a35a247e1784368829e66a67bf91de94c7d8d1645044fac1d5b` |
| arm64 | `ghcr.io/project-zot/zot-linux-arm64:v2.1.22@sha256:920e3e327a73513643c67d14f54092c45ece6d29660bff7e898107e00b49fa03` |

Resolved with, and re-verified at implementation time:

```bash
crane digest ghcr.io/project-zot/zot-linux-amd64:v2.1.22
crane digest ghcr.io/project-zot/zot-linux-arm64:v2.1.22
```

Boot asset for this pin (immutable, published from the #9252 branch): release `zot-image-v2.1.22-46f688dc2631`, T `126c18a4ac0643a3c0c80ba46503593f02f92750303d2728c7cc0012b7d1c599`, C `5a8db63c9fae93403c39376052e205c41a469dbd84b3d1ea37ee497cb08318ef`. The next bump rotates this triple into `## Previous known-good pin`.

**The tag is part of the reference on purpose.** It is what the upstream poll parses to
learn the pinned version, and what makes the cross-arch version-coherence check
expressible. Digest-pinning still provides the integrity guarantee; the tag is metadata.

## Previous known-good pin

**This is the rollback target.** The bump deliberately erases these digests from
`zot-registry.tf`, so without this section they survive only in git history — a
git-archaeology exercise under incident pressure on a host with no shell and no SSH.
Asserted by staleness check 8; rotate it on every bump.

| Arch | Reference | Superseded |
|---|---|---|
| amd64 | `ghcr.io/project-zot/zot-linux-amd64@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5` (v2.1.20) | 2026-10-08 |
| arm64 | `ghcr.io/project-zot/zot-linux-arm64@sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6` (v2.1.20) | 2026-10-08 |

The v2.1.20 boot asset (immutable, published; preflight P6 reads CLEAR for it): release `zot-image-v2.1.20-95a837a0afac`, T `05b171f2bd500dc84f532ef7736d1550ffaf7464f0d655c86b8238b443568cb2`, C `2d7fee5603dfd88b2b90cffd07e6b97e6d7ba5e3d6bd5472e66b23bd5ad59114`. Rolling back means reverting the four values (`zot_image_amd64`, `zot_image_arm64`, T, C) to these.

Recovery procedure (the whole procedure lives here, not in a plan that will be archived):

1. **Revert the squash-merge commit of the change that set the current pin, wholesale**
   (`git revert <sha>`). It returns, together: the four values in `zot-registry.tf`, this sidecar, the
   `zot vX.Y.Z` claim comments the staleness gate requires in `ci-deploy.test.sh` and
   `cloud-init-registry.yml`, and the three-name hosts-file deny at all seven sites. `ci-deploy.sh` is
   deliberately NOT a claim carrier (check 11): expect conflicts in `ci-deploy.sh`, `ci-deploy.test.sh`
   and this sidecar (later edits sit beside the reverted hunks), and NOT only there: a revert of that
   commit also reverts its non-conflicting hunks, which would put the fan-out signature back on curl's
   argv. So do not resolve hunk by hunk. Keep the CURRENT `ci-deploy.sh` wholesale
   (`git checkout HEAD -- apps/web-platform/infra/ci-deploy.sh`: its claim-free pointer comment, stdin-config
   curl call and environment-only signer are independent of the pin and must survive); keep the CURRENT
   `ci-deploy.test.sh` and change only its `zot v2.1.22` tokens to `zot v2.1.20`; take this sidecar's
   REVERTED side. The revert also re-adds the `ci-deploy.sh` row to
   `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` and
   `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv`: restore both from the pre-revert tree
   BEFORE committing the revert (`git checkout HEAD -- <both files>`; after the commit use
   `git checkout HEAD~1 -- <both files>` and amend), or the credential lint reports the entry as stale.
   Dry-run 2026-10-09 of this recipe: `zot-image-staleness.test.sh` exits 0 and
   `lint-shell-trace-credential-refusal.py` reports OK. A narrower edit of
   only the four values fails `zot-image-staleness.test.sh` (the sidecar, the followers and the
   previous-known-good block then disagree with the pin), and a partial revert of the deny breaks its
   byte-parity guard. The values being restored, in the tag-qualified form `zot_version` is derived
   from (the tag-less form above is only what staleness check 8 parses), are:
   `zot_image_amd64 = "ghcr.io/project-zot/zot-linux-amd64:v2.1.20@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5"`,
   `zot_image_arm64 = "ghcr.io/project-zot/zot-linux-arm64:v2.1.20@sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6"`,
   plus T and C from the boot-asset line above.
2. The revert's commit message BODY must carry `[skip-web-platform-apply]` and
   `[skip-deploy-fix-apply]`, each on its own line, or the merge-fired push applies SSH into web-1 and
   web-2. A bare `git revert` message carries neither. Always include both, even for a revert that
   seems to touch no trigger file: a `server.tf` edit reaches the web hosts' `triggers_replace` BY VALUE
   (`local.ghcr_deny_sh` and `local.ghcr_deny_assert_sh` feed `zot_consumer_probe_install` and
   `deploy_pipeline_fix_web2`), which a `git show --stat` file list will not show. The markers defer the
   web-host delivery of the revert, they do not drop it: the next unmarked push to a trigger path applies
   the reverted values to web-1 and web-2, so review that apply when it is sanctioned. The markers must
   be on their own lines in the SQUASH-MERGE body too (the push head commit is what the workflows read);
   verify it before merging.
3. Merge it. The merge fires `registry-host-replace-dispatch.yml`; do not dispatch a second replace
   (double destroy-first). The manual arm is for a refusal only, taken on an explicit operator go.
4. The v2.1.20 boot asset is immutable and published, so preflight P6 passes for it. Store
   compatibility in this direction is measured (see the config-compatibility table).

This works because the registry host boots from the pinned release asset (see `## Boot asset`),
which is independent of whatever the store holds.

**Constraint on that path:** the revert needs a second successful host create, subject to the
same `stock_preflight_gate`; there is no capacity reservation between the destroy and the create.

## Why v2.1.22, and why the floor is v2.1.19

Both cosign-path panic fixes the bump exists to pick up ship in **v2.1.19**, not v2.1.18:

- project-zot #4204 — `fix(meta): avoid panic on malformed cosign signature tag`
- project-zot #4213 — `fix(meta): guard GetReferrersInfo against a missing referrer entry`

This deployment exercises the cosign-signature path on every release, so v2.1.18 is
disqualified by the safety motivation itself.

The entire v2.1.19 → v2.1.20 delta is two commits: a zui version bump and an upstream-CI
pin. The zui bump is **inert here** — the rendered `config.json` has exactly four top-level
keys (`distSpecVersion`, `storage`, `http`, `log`) and **no `extensions` block**, so zot
never serves the UI. So v2.1.20 carried zero additional runtime surface over v2.1.19 when it
was pinned (#7282).

v2.1.20 → v2.1.22 (#9252) is 128 commits, not two. Read against this config on 2026-10-08:
the four source anchors are byte-identical (see the table below), one commit is marked
breaking (`fix(api)!` #4363, v2.1.21: blob HEAD and range reads become repo-local by default,
which applies because `storage.dedupe` is `true`), and the gc/dedupe/walk changes
(#4318, #4236, #4351, #4325, #4383) are covered by the soak after the replace, not by a unit
measurement. The floor stays v2.1.19: the cosign panic fixes are the reason for it and v2.1.22
carries them.

**Do not fall back below v2.1.19.**

## Config-compatibility analysis (v2.1.2 → v2.1.22)

Done against upstream **source at the tags**, not release notes. Re-diffed v2.1.20 → v2.1.22 on
2026-10-08 (#9252): every anchored block below is byte-identical between the two tags. The deployed config is
written by `cloud-init-registry.yml` at `- path: /etc/zot/config.json`. Anchors are
content, never line numbers.

| Config surface | Deployed shape | Upstream | Verdict |
|---|---|---|---|
| `distSpecVersion` | `"1.1.0"` | `pkg/cli/server/root.go` › `func updateDistSpecVersion` logs a WARN on mismatch then **overrides** `config.DistSpecVersion`. Never errors. | **SAFE, cannot fail.** A WARN does not trip the `zot_last_err` error/fatal tiers. |
| `storage.retention` | `{dryRun, delay, policies[{repositories, deleteReferrers, deleteUntagged, keepTags[]}]}` | `type RetentionPolicy` byte-identical **plus** a new `KeepUntagged *KeepUntaggedPolicy`. `KeepTagsPolicy` unchanged. | **SAFE — purely additive.** Untagged retention is inert here: `isUntaggedRetentionEnabledForPolicy` requires `KeepUntagged != nil`, and the deployed config has no `keepUntagged`. `deleteUntagged: true` keeps its old meaning. |
| `http.accessControl` | nested `accessControl.repositories["**"] = {policies[], defaultPolicy: []}` | `type AccessControlConfig { Repositories Repositories … }` | **SAFE — already on the new nested shape**, not the deprecated flat form. Added `Groups`, `Metrics`, CEL `compiledConditions` are all additive/optional. |
| `http.compat` | `["docker2s2"]` | `pkg/compat/compat.go` › `DockerManifestV2SchemaV2 = "docker2s2"` — unchanged | **SAFE.** Load-bearing: zot rejects Docker schema2 pushes without it. |
| `http.auth.htpasswd` | `{path: /etc/zot/htpasswd}`, baked with `htpasswd -Bbn` (bcrypt) | unchanged; v2.1.11 only *added* sha256/sha512 alongside bcrypt | **SAFE.** |
| `storage.dedupe` + blob reads | `dedupe: true` | `fix(api)!` #4363 (v2.1.21): `HEAD`/`GET` of a blob that exists only under ANOTHER repo is now 404. Measured 2026-10-08 against both pinned digests with this repo's exact config: same-repo `HEAD`/`GET` 200 on both; cross-repo `HEAD`/`GET` **200 on v2.1.20, 404 on v2.1.22**; `POST …/uploads/?mount=<digest>&from=<repo>` 201 on both and `HEAD` then 200. | **SAFE, with a cost.** CI pushes with `crane copy` from GHCR (a different registry, so no mount path), so a layer shared by two zot repos is uploaded again instead of skipped. Extra upload today: 0 B (the three release tags go to one repo, and the three zot repos share no base layer). Were the largest layer on record (703,724,542 B) ever shared, one re-upload needs at least 0.4 MB/s sustained to meet the 1800 s deadlines (ADR-190). `storage.hydrateBlobOnRead: true` would restore the old read, and is **NOT ADOPTED** (below). |
| store layout + metadata (upgrade AND rollback) | LUKS-backed ext4 store reattached across the replace; `storage.dedupe`, `gc`, `retention` as above | Measured 2026-10-08 (data-integrity review seat, prod config shape, shortened gc/retention delays, `lost+found` present): a store written by v2.1.20 was opened, gc'd and served by v2.1.22 with the same surviving tags and pullable images; then new tags and an overwritten `latest` were written by v2.1.22 and the same store was reopened by v2.1.20 and gc'd with every tag listed and every kept image pulled (including a hand-built Docker schema2 manifest through the `docker2s2` path). `CurrentVersion` in `pkg/meta/version/common.go` is unchanged (no metaDB migration); `cache.db` gains a method on the same bucket layout. | **SAFE both directions.** Not covered: real cosign referrers with a `subject`, multi-arch indexes, concurrent pushes. v2.1.22 logs `level:error` "failed to stat blob" lines (`checkCacheBlob`, `DedupeBlob`) when a client attempts a cross-repo `POST ?mount=` for a blob that is not there, observed in the review seat's pushes (the same call sites exist in v2.1.20, so which branch is reached, not the call site, differs; unmeasured) — `crane copy` GHCR to zot does not mount, so none are expected. |
| log format | scraper matches `'"level":"(error\|fatal)"\|level:(error\|fatal)\|level=(error\|fatal)'` | v2.1.9 migrated zerolog → `log/slog` | **ALREADY ABSORBED** — all three shapes matched in one alternation (`cloud-init-registry.yml`, the `_zlogs` grep). Asserted at implementation time, not assumed. Re-checked on v2.1.22: the `{"time":…,"level":"warn",…}` JSON shape is unchanged and a boot with this config emits zero error or fatal lines (the warn-level `config dist-spec version differs` for `distSpecVersion` 1.1.0 vs the supported 1.1.1 appears on v2.1.20 too, and is not adopted). |

## Non-adoption decisions

Recorded so a future reader does not mistake absence for oversight:

- **`storage.FastRestart`** — new opt-in in v2.1.19, defaults `false`, top-level storage only. **NOT ADOPTED.** A separate change with its own soak.
- **`storage.retention.policies[].keepUntagged`** — new in v2.1.19. **NOT ADOPTED.** Adopting it would change what `deleteUntagged: true` means.
- **`storage.hydrateBlobOnRead`** — the opt-in that restores cross-repo blob reads after #4363. **NOT ADOPTED** (decided 2026-10-08, #9252). Measured need: none. Same-repo reads, pushes and mounts are unchanged, and the only affected path is a re-upload of a layer shared between two zot repos, which costs 0 B today (see the dedupe row). Adopting it is a config JSON change (`registry-boot-guard.test.sh` byte-literal fragments) and its own decision.

## Version-scoped claim register

These are **measurements**, not inferences. Re-deriving them from upstream source is not
re-verification — run the pinned image or downgrade the claim.

**Trigger files carry no version-scoped claim.** `ci-deploy.sh` feeds `triggers_replace` of the web
hosts' SSH provisioners, so a `zot vX.Y.Z` token in it would make every bump redeliver the script to
both hosts for a comment. Staleness check 11 enforces zero claims there; check 7 covers the real
carriers (`ci-deploy.test.sh`, `cloud-init-registry.yml`).

| Claim | Location | Status |
|---|---|---|
| GET `/v2/` answers 200 or 401, **never 403**, with this repo's exact `accessControl` | `ci-deploy.test.sh`, the 401 fixture comment (the version-bearing claim); `ci-deploy.sh`, above `_docker_login_failure_class`, carries a pointer to this row and NO version | Re-measured against v2.1.22 on 2026-10-08 — see `## Bump procedure` step 4: anonymous 401, pull user 200, push user 200, wrong password 401 (dockerd stderr `failed with status: 401 Unauthorized`), a user with zero policies 200 on `/v2/` and 403 on a manifest read, zero 403 on `/v2/`. This measurement is what makes the `authz_denied` arm a tripwire rather than a live arm. |
| No sanctioned on-demand gc HTTP endpoint is exposed | `cloud-init-registry.yml`, config.json rationale block | Re-measured against v2.1.22 on 2026-10-08: `/v2/_zot/gc`, `/v2/_catalog/gc`, `/_zot/gc`, `/v2/_zot/ext/gc` all 404. Non-adoption of an on-boot gc trigger is unchanged. |
| With `readTimeout`/`writeTimeout` omitted, zot supplies 60000000000 ns for both | `cloud-init-registry.yml`, the `http.readTimeout` rationale block | Re-read against v2.1.22 on 2026-10-08 from the pinned digest's own boot config (`"ReadTimeout":60000000000`, `"WriteTimeout":60000000000`). |
| `reusable-release.yml` states zot's built-in ReadTimeout/WriteTimeout (60000000000 ns) | `.github/workflows/reusable-release.yml` | Unregistered (found by the #9252 bump; update at the next bump). True of v2.1.22 too (the row above); left alone because editing a workflow removes the agent admin-merge path. Staleness check 7 does not read it. |
| zot#4235 is fixed upstream (#4236, v2.1.21+) | `scripts/followthroughs/zot-fill-rate-7341.sh` | Unregistered (found by the #9252 bump). Reworded 2026-10-08; staleness check 7 does not read it. |

## Known coupling

`registry-boot-guard.test.sh` asserts the config JSON with byte-literal `grep -qF`
fragments (`'"gcInterval": "1h"'`, `'"delay": "2h"'`, `'"deleteReferrers": false'`, …).
**This bump changes no config JSON**, so those stay green — but any future schema migration
that reflows that JSON breaks them even when semantics are preserved. Check it on every
bump.

## Refresh recipe (capture date aged out, pin unchanged)

Use when staleness check 6 reddens but upstream has **not** moved: re-confirm the digests
still resolve, then re-stamp `Capture date (UTC)`.

```bash
crane digest ghcr.io/project-zot/zot-linux-amd64:$(grep -oE 'zot-linux-amd64:v[0-9.]+' zot-registry.tf | head -1 | cut -d: -f2)
```

**Do not re-stamp the date to clear a red gate without doing the work.** The date is an
attestation that the analysis above is current; typing today's date makes the backstop
permanently green while the analysis rots. If upstream HAS moved, use the bump procedure
below instead — it is a materially heavier procedure, not the same one.

## Bump procedure

The recipe above re-stamps a date. **This one re-does the analysis**, and it is what the
staleness gate's failure message points at. Do all of it, in order:

1. **Rotate `## Previous known-good pin`** to the pin you are about to replace — both
   arches, with today's date. Do this FIRST; it is the step that is easiest to forget and
   the one that matters during an incident.
2. **Resolve both digests** at the new tag with `crane digest` (both arches, never one).
   Update `## Current pin` and the two locals in `zot-registry.tf` together.
3. **Re-diff the four upstream source anchors** between the old and new tags — release
   notes are not sufficient. Then **scan the commits between the tags for `!:` or `BREAKING`
   subjects** (`gh api repos/project-zot/zot/compare/<old>...<new>`) and measure each one
   that touches a surface this config uses; the anchors alone missed #4363 (`dedupe: true`):
   - `func updateDistSpecVersion` (`pkg/cli/server/root.go`)
   - `type RetentionPolicy` (retention config shape)
   - `type AccessControlConfig` (authz config shape)
   - `DockerManifestV2SchemaV2` (`pkg/compat/compat.go`)
   Update the config-compatibility table with the verdict for each.
4. **Re-measure the two version-scoped claims** by running the pinned image locally with
   this repo's exact `config.json` + htpasswd:

   ```bash
   docker run --rm -v <cfg>:/etc/zot/config.json:ro <pinned-ref> serve /etc/zot/config.json
   curl -sS -o /dev/null -w '%{http_code}' http://localhost:5000/v2/
   ```

   Confirm 200-or-401, never 403. **If 403 appears, STOP** — the `authz_denied` arm becomes
   a live arm rather than a tripwire; downgrade the claim to `UNMEASURED` and file an issue
   rather than shipping a false comment.
5. **Re-check the `registry-boot-guard.test.sh` coupling** above if the config JSON moved.
6. **Re-stamp `Capture date (UTC)`** and run `bash zot-image-staleness.test.sh` — it must
   exit 0. A bump edits the claim comments in `ci-deploy.test.sh` and `cloud-init-registry.yml` and
   never `ci-deploy.sh` (check 11); if a bump seems to need an edit there, the claim has crept back.
7. **Publish the boot asset BEFORE the bump merges** (#8714 5.3b-iii). The registry host boots
   from a release asset, not from ghcr.io, so a merged pin with no asset refuses every replace
   (preflight P6). On the bump branch, run
   `gh workflow run zot-image-mirror.yml --ref <branch>`. The run's summary prints the
   published `T`, and its `rehearse` job then boots it. Pin `zot_mirror_asset_sha256_amd64` (T)
   and `zot_config_digest_amd64` (C, the manifest's `.config.digest`) in the `zot-mirror` block
   of `zot-registry.tf`. The PR's own `rehearse` run rebuilds from upstream D and must reproduce
   both. Upstream D anchors the bytes, so a branch dispatch is safe: it can only publish D's own
   blobs, under a tag that carries D's prefix.

Agent entry point:

```
/soleur:one-shot "refresh the zot pin provenance sidecar per apps/web-platform/infra/zot-image.provenance.md section 'Bump procedure'"
```

## Boot asset (release mirror, #8714 step 5.3b-iii)

The registry host no longer pulls the pin above. It boots from the release asset
`zot-image-<version>-<D12>` / `zot-linux-amd64-<version>.oci.tar`: upstream D's manifest and
blobs, packaged reproducibly by `zot-image-oci-archive.sh` and published by `zot-image-mirror.yml`.
The pins and the derivation live in the `zot-mirror` block of `zot-registry.tf`. The rationale is
ADR-096's amendment of 2026-09-28 (part 2).

- **Never delete or replace a `zot-image-*` release.** A registry replace fetches it by URL and
  refuses any bytes other than T. Releases here are immutable once published, so a deleted one
  cannot be re-created under the same tag: the only recovery is reverting the pin. A deleted one is
  named by rule-audit's asset probe and refused at the next replace by preflight P6.
- **Recovery.** It is workflow-only, with no SSH. Use the "zot boot image (#8714)" section of
  `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`: re-fire the
  replace, re-publish the asset, or revert the PR.
