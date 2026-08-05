# zot registry image — pin provenance

Analysis of record for the `zot_image_amd64` / `zot_image_arm64` pins in `zot-registry.tf`.
Read by `zot-image-staleness.test.sh` (CI gate) and by the upstream-poll step in
`.github/workflows/rule-audit.yml` (detection). Mirrors the shape of
`cosign-trusted-root.provenance.md` so both sidecars share one parseable format.

**zot is the sole pull path** (ADR-096, 2026-07-30 amendment) with no fallback. A wrong pin
here does not degrade the fleet — it darks it. Treat every row below as load-bearing.

| Field | Value |
|---|---|
| Pinned version | **v2.1.20** |
| Upstream release date | 2026-08-04T17:51:30Z |
| Capture date (UTC) | **2026-08-05** |
| Superseded | v2.1.2 (2025-01-17) — 18 releases behind at time of bump (#7282) |

## Current pin

| Arch | Reference |
|---|---|
| amd64 | `ghcr.io/project-zot/zot-linux-amd64:v2.1.20@sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5` |
| arm64 | `ghcr.io/project-zot/zot-linux-arm64:v2.1.20@sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6` |

Resolved with, and re-verified at implementation time:

```bash
crane digest ghcr.io/project-zot/zot-linux-amd64:v2.1.20
crane digest ghcr.io/project-zot/zot-linux-arm64:v2.1.20
```

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
| amd64 | `ghcr.io/project-zot/zot-linux-amd64@sha256:073f30d99fbdbcd8869334231c9ca45c75e535e4bdc6e28cc8a1541abe7a3f71` (v2.1.2) | 2026-08-05 |
| arm64 | `ghcr.io/project-zot/zot-linux-arm64@sha256:c3fc47782d98b731d5928a24182b495e28cc92f9dcf1d5317f7dbd632e10bf30` (v2.1.2) | 2026-08-05 |

Recovery procedure: see the plan's `## Rollback`. In short — revert both locals to the
above, merge (inert by `OPERATOR_APPLIED_EXCLUSIONS`), re-fire `registry-host-replace`.
This works because cloud-init pulls zot from the **public upstream registry**, never from
our own zot, so a dark zot does not block its own replacement.

**Constraint on that path:** the revert needs a second successful host create, subject to
the same `stock_preflight_gate` that is ABORTing today. Firing the apply is effectively
one-way with no capacity reservation.

## Why v2.1.20, and why the floor is v2.1.19

Both cosign-path panic fixes the bump exists to pick up ship in **v2.1.19**, not v2.1.18:

- project-zot #4204 — `fix(meta): avoid panic on malformed cosign signature tag`
- project-zot #4213 — `fix(meta): guard GetReferrersInfo against a missing referrer entry`

This deployment exercises the cosign-signature path on every release, so v2.1.18 is
disqualified by the safety motivation itself.

The entire v2.1.19 → v2.1.20 delta is two commits: a zui version bump and an upstream-CI
pin. The zui bump is **inert here** — the rendered `config.json` has exactly four top-level
keys (`distSpecVersion`, `storage`, `http`, `log`) and **no `extensions` block**, so zot
never serves the UI. So v2.1.20 carries zero additional runtime surface over v2.1.19 while
being the current release.

**Do not fall back below v2.1.19.**

## Config-compatibility analysis (v2.1.2 → v2.1.20)

Done against upstream **source at the tags**, not release notes. The deployed config is
written by `cloud-init-registry.yml` at `- path: /etc/zot/config.json`. Anchors are
content, never line numbers.

| Config surface | Deployed shape | Upstream | Verdict |
|---|---|---|---|
| `distSpecVersion` | `"1.1.0"` | `pkg/cli/server/root.go` › `func updateDistSpecVersion` logs a WARN on mismatch then **overrides** `config.DistSpecVersion`. Never errors. | **SAFE, cannot fail.** A WARN does not trip the `zot_last_err` error/fatal tiers. |
| `storage.retention` | `{dryRun, delay, policies[{repositories, deleteReferrers, deleteUntagged, keepTags[]}]}` | `type RetentionPolicy` byte-identical **plus** a new `KeepUntagged *KeepUntaggedPolicy`. `KeepTagsPolicy` unchanged. | **SAFE — purely additive.** Untagged retention is inert here: `isUntaggedRetentionEnabledForPolicy` requires `KeepUntagged != nil`, and the deployed config has no `keepUntagged`. `deleteUntagged: true` keeps its old meaning. |
| `http.accessControl` | nested `accessControl.repositories["**"] = {policies[], defaultPolicy: []}` | `type AccessControlConfig { Repositories Repositories … }` | **SAFE — already on the new nested shape**, not the deprecated flat form. Added `Groups`, `Metrics`, CEL `compiledConditions` are all additive/optional. |
| `http.compat` | `["docker2s2"]` | `pkg/compat/compat.go` › `DockerManifestV2SchemaV2 = "docker2s2"` — unchanged | **SAFE.** Load-bearing: zot rejects Docker schema2 pushes without it. |
| `http.auth.htpasswd` | `{path: /etc/zot/htpasswd}`, baked with `htpasswd -Bbn` (bcrypt) | unchanged; v2.1.11 only *added* sha256/sha512 alongside bcrypt | **SAFE.** |
| log format | scraper matches `'"level":"(error\|fatal)"\|level:(error\|fatal)\|level=(error\|fatal)'` | v2.1.9 migrated zerolog → `log/slog` | **ALREADY ABSORBED** — all three shapes matched in one alternation (`cloud-init-registry.yml`, the `_zlogs` grep). Asserted at implementation time, not assumed. |

## Non-adoption decisions

Recorded so a future reader does not mistake absence for oversight:

- **`storage.FastRestart`** — new opt-in in v2.1.19, defaults `false`, top-level storage only. **NOT ADOPTED.** A separate change with its own soak.
- **`storage.retention.policies[].keepUntagged`** — new in v2.1.19. **NOT ADOPTED.** Adopting it would change what `deleteUntagged: true` means.

## Version-scoped claim register

These are **measurements**, not inferences. Re-deriving them from upstream source is not
re-verification — run the pinned image or downgrade the claim.

| Claim | Location | Status |
|---|---|---|
| GET `/v2/` answers 200 or 401, **never 403**, with this repo's exact `accessControl` | `ci-deploy.sh`, above `_docker_login_failure_class` | Re-measured against v2.1.20 — see `## Bump procedure` step 4. This measurement is what makes the `authz_denied` arm a tripwire rather than a live arm. |
| No sanctioned on-demand gc HTTP endpoint is exposed | `cloud-init-registry.yml`, config.json rationale block | Re-scoped to the pinned version. Non-adoption of an on-boot gc trigger is unchanged. |

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
   notes are not sufficient:
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
   exit 0.

Agent entry point:

```
/soleur:one-shot "refresh the zot pin provenance sidecar per apps/web-platform/infra/zot-image.provenance.md section 'Bump procedure'"
```
