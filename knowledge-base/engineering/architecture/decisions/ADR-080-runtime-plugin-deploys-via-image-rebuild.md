# ADR-080: Runtime-plugin changes deploy via image rebuild, not host-direct re-seed

- **Status:** Adopting
- **Date:** 2026-07-02
- **Deciders:** Jean (operator), CPO sign-off (single-user-incident threshold), CTO agent (binding Option A vs B ruling), deepen-plan review (spec-flow-analyzer, architecture-strategist, code-simplicity-reviewer)
- **Relates to:** production-incident remediation (`worktree-manager.sh` stale-git-lock self-heal merged 2026-07-01 but the Concierge host mount kept running the pre-fix script until a coincidental `apps/web-platform/**` deploy the next morning); #3045 (`Dockerfile` plugin vendor+bake — the image-baked seed model, previously undocumented); `ADR-030-multi-tenant-deploy-substrate.md` (tenant credential aggregation — a distinct concern); `ADR-064-live-production-verification-harness.md` (the live-verify gate that correctly SKIPs on plugin-only merges); `ADR-078-graceful-cron-drain-before-container-swap.md` (the deploy path a runtime-plugin merge now traverses)

## Context

The Concierge agent runs plugin components (skills, hooks, agents, scripts,
commands, and the `AGENTS.md`/`CLAUDE.md` instruction files it reads) from
`/mnt/data/plugins/soleur`, a read-only bind-mount. That mount is **seeded from
the web-platform image's baked plugin tree**:

- `reusable-release.yml` "Vendor plugin into build context" copies `plugins/soleur`
  → `apps/web-platform/_plugin-vendored`; `apps/web-platform/Dockerfile`
  `COPY _plugin-vendored /opt/soleur/plugin` bakes the WHOLE tree.
- `apps/web-platform/infra/ci-deploy.sh` re-seeds the mount on **every** deploy:
  `docker create` → `find "$PLUGIN_MOUNT_DIR" -mindepth 1 -delete` → `docker cp
  <ephemeral>:/opt/soleur/plugin/. "$PLUGIN_MOUNT_DIR/"` → `.seed-complete`.

The **only** workflow that rebuilds the image and deploys is
`web-platform-release.yml`, historically triggered on `push` to `main` with
`paths: ['apps/web-platform/**']`. A plugins-only merge rebuilt no image, ran no
deploy, and never re-seeded — so a runtime-affecting plugin change reached prod
only by coincidence when an unrelated `apps/web-platform/**` change happened to
deploy. `version-bump-and-release.yml` (on `plugins/soleur/**`) only cuts a plugin
tag + GitHub Release; `deploy-docs.yml` only publishes GitHub Pages. Neither
touches the Concierge host mount. This is the 2026-07-01 incident: a merged fix
that silently never runs on the host.

A second, hidden gate compounds it. `reusable-release.yml`'s `check_changed` step
re-gates every build/deploy step on `git diff --name-only HEAD~1 -- "$PATH_FILTER"`
(historically `apps/web-platform/`). Widening only the outer `on.push.paths`
without widening this inner gate produces a green **no-op** — the workflow fires,
the inner gate returns `changed=false`, and the incident reproduces.

## Decision

**Option A — a runtime-plugin merge rebuilds and deploys the web-platform image;
the mount re-seeds from that fresh image, so image and host mount stay consistent
by construction.** The runtime-plugin surface is treated as part of the
web-platform deployable. No new host-write infrastructure, no new seed logic — a
widening of the pipeline's **two** change-detection gates, in two deliberately
different dialects:

1. **Outer gate** — `web-platform-release.yml` `on.push.paths`, GitHub-Actions
   glob dialect (supports `**` and `!`):
   ```yaml
   paths:
     - 'apps/web-platform/**'
     - 'plugins/soleur/**'
     - '!plugins/soleur/docs/**'
     - '!plugins/soleur/test/**'
   ```
2. **Inner gate** — `reusable-release.yml` `check_changed`, git-pathspec dialect
   (`:(exclude)` magic, NO `**`), run under `set -euo pipefail` + `set -f` +
   an explicit git rc check, with the widened `path_filter`:
   ```
   "apps/web-platform/ plugins/soleur/ :(exclude)plugins/soleur/docs/ :(exclude)plugins/soleur/test/"
   ```

**DENYLIST, not allowlist:** everything under `plugins/soleur/` deploys EXCEPT
`docs/` (deploys via `deploy-docs.yml`) and `test/` (does not affect the deployed
runtime). The incident IS "a runtime file class silently never deploys"; an
allowlist fails in exactly that direction for future runtime surfaces and already
has a concrete hole (`plugins/soleur/CLAUDE.md` → `@AGENTS.md` and `AGENTS.md`
are runtime instruction files an allowlist excludes). A denylist is
failure-mode-complete: new runtime dirs deploy by default.

**Invariant (guard the one latent hole):** the two excluded dirs are anchored at
top-level `plugins/soleur/{docs,test}/` only. This is safe today (verified:
`docs/` is Eleventy docs-site source, `test/` is `.test.ts`/`.test.sh` only, and
no runtime hook/skill/script sources anything from either). It stays safe ONLY as
long as those two top-level dirs remain **runtime-free** — a runtime helper ever
placed under top-level `docs/` or `test/` would silently NOT trigger a redeploy
(the incident class, re-opened). Keep runtime code out of them; put test-only
helpers under `plugins/soleur/skills/*/test/` (nested — not excluded, deploys by
default, harmless) rather than top-level `test/`.

## Why Option B (host-direct re-seed) is disqualified

Option B — a dedicated workflow that pushes the plugin tree straight to the host
mount without rebuilding the image — is not merely costlier, it is **worse than
the status quo**. The plugin tree is baked into the image (`Dockerfile`) and every
deploy re-seeds via `find -delete` + `docker cp` from that image. Under B, a
host-direct re-seed pushes plugin vN to the mount, then the next unrelated
`apps/web-platform` deploy re-seeds from an image that still bakes v(N-1) →
**wipes vN, silently restores the stale tree** — reproducing the incident
signature after the fix appeared to work. Any B mitigation ("also rebuild the
image") collapses B back into A. The `apply-deploy-pipeline-fix.yml` precedent
does NOT license B: it pushes host-resident files **not baked into any image**, so
it has no image-vs-host drift surface — the exact property B lacks.

## Fail-loud inner gate (load-bearing)

The pre-fix `CHANGED=$(git diff … | head -1)` swallowed every git error into
`changed=false` — a green no-op that reproduces the incident. The fix:

- `set -euo pipefail` + an explicit `if ! CHANGED=$(git diff …); then
  echo "::error::…"; exit 1; fi` — a git failure or bad pathspec now fails LOUD,
  never defaults to skip.
- `set -f` around the diff disables filesystem globbing so the space-separated
  pathspec tokens (incl. `:(exclude)` magic) reach git verbatim. An unquoted
  `**` token would be bash-glob-expanded before git sees it and silently miss
  newly-added files — so the inner dialect uses directory-prefix pathspecs with
  NO `**`. `$PATH_FILTER` is intentionally unquoted to word-split into multiple
  git pathspecs.
- The `force_run` short-circuit (for `workflow_dispatch`) is preserved.

The shared plugin caller (`version-bump-and-release.yml`) passes a single-token
`path_filter: "plugins/soleur/"` that word-splits to itself byte-unchanged, so it
is unaffected.

## Alternatives Considered

| Option | Verdict | Why |
|---|---|---|
| **A: image rebuild + gated deploy re-seeds the mount (this ADR)** | **Chosen** | Image and host mount consistent by construction; reuses the existing seed path with zero new infra; consistency is total; costs one gated image build + prod cutover per runtime-plugin PR |
| **B: host-direct re-seed (no image rebuild)** | **Rejected** | The next unrelated `apps/web-platform` deploy re-seeds from an image baking the stale tree → silently wipes the fix. Worse than status quo (fix appears to work, then reverts); adds a host-write ops surface. Any "also rebuild" mitigation is just A |
| **Allowlist filter** (glob specific runtime dirs) | **Rejected** | Fails in the incident's own direction (silent under-deploy) for future runtime surfaces; concrete hole for runtime `CLAUDE.md`/`AGENTS.md`. Denylist is fail-safe |
| **Widen only the outer `on.push.paths`** | **Rejected** | The inner `check_changed` gate re-keys on `path_filter`; leaving it narrow yields a green no-op that reproduces the incident. BOTH gates must widen |
| **New `extra_path_filter` input** (vs reusing `path_filter`) | **Rejected** | A nullable extra input risks an empty-quoted-pathspec match-all hazard; reusing the always-non-empty `path_filter` (dropping the quotes) is simpler and safe |
| **`**` globs in the inner git pathspec** | **Rejected** | Under `set -f`-off, bash filesystem-expands them and silently misses new files; the two gate dialects are deliberately different (Actions-glob outer, git-pathspec inner) |

## Trade-offs named

- **Dual-release co-fire.** A runtime-plugin merge now fires three workflows:
  `web-platform-release` (`web-v*` tag + deploy), `version-bump-and-release`
  (`v*` plugin tag + Release + Slack), and `deploy-docs` (GH Pages). Separate
  concurrency groups (`release-web-platform` vs `release-plugin`) and regex-isolated
  tag prefixes (`v` / `web-v`, #4082) → no collision or double-deploy, but TWO
  Releases + TWO Slack/email notifications per PR. Accepted for correctness;
  suppressing the plugin announcement for runtime merges is a follow-up.
- **Prod pipeline on plugin-only merges.** `migrate` + `verify-doppler-secrets`
  (under `DOPPLER_TOKEN_PRD`) now run on runtime-plugin merges — idempotent (no
  new migrations → no-op), but a runtime fix's delivery can now be
  fail-closed-blocked by unrelated prod drift. Correct trade-off (the image
  genuinely changed → a full deploy is right).
- **Denylist over-deploys on rare root-file edits** (`README.md`, `LICENSE`,
  `NOTICE`) → a harmless over-build. The incident class (silent under-deploy) is
  what we refuse to reintroduce.
- **`HEAD~1` squash-merge assumption.** The inner diff basis assumes squash-merge;
  a non-squash/multi-commit push could diff the wrong range. Residual risk called
  out; the push-range compare `${{ github.event.before }}...${{ github.sha }}` is
  the hardening path (do not alter the shared plugin caller's basis without
  re-verifying it).

## Observability (no-SSH)

The inner gate fails loud (`::error::` + non-zero exit) on any git error — a red
CI job pre-merge instead of a silent skip. Post-merge liveness: the
`web-platform-release` deploy job succeeds, `/hooks/deploy-status` reports
`exit_code=0` for the new tag, and `app.soleur.ai/health` `build_sha` equals the
merge SHA. A behavioral drift-guard
(`plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts`) runs the
byte-identical `check_changed` bash against synthesized diffs so a regression to
the swallow-into-`changed=false` form, a `**` token in the inner pathspec, or a
docs/test-only over-trigger fails the suite pre-merge.

## C4 impact

**None** — enumeration cited. The change is a CI trigger *condition* on the
already-modeled CI → image → host-deploy path (plugin system, skill loader,
`claude -> skillloader "Loads plugin"`, deploy infra, GitHub CI/CD in `model.c4`).
No new external actor, system, container, data store, or access relationship; C4
does not model workflow path-filters. This ADR is the canonical record for the
image-baked-plugin seed model (originated in #3045).

## Consequences

- A runtime-plugin merge to `main` now deterministically rebuilds and deploys the
  web-platform image, re-seeding the Concierge host mount — image and mount are
  consistent by construction.
- `docs/`-only and `test/`-only plugin merges do NOT rebuild the image (docs still
  publish via `deploy-docs.yml`).
- The inner change-detection gate can no longer silently default to skip on error.
- The `path_filter` reusable-workflow input is now a space-separated git-pathspec
  list (documented in its `description:`), consumed under `set -f`.

## Amendment (2026-07-02): fresh-host cloud-init bootstrap delivery (#5921)

This ADR's scope — *host-run assets are baked into the web-platform image and
`docker cp`-seeded* — extends to the **fresh-host cloud-init bootstrap** path.
The motivating bug (#5921): a fresh Hetzner web host (`hcloud_server.web["web-2"]`)
could not be provisioned because `server.tf` rendered 22 bootstrap scripts +
`hooks.json` as base64 into the cloud-init `templatefile()` map, blowing Hetzner's
**32,768-byte `user_data` cap** (rendered ~282 KB, ~8.6× over). gzip is
insufficient (measured 140,856 B). The fix bakes those assets into the image and
extracts them at boot — the same image-bake + `docker cp` model this ADR records.

**Two-path delivery contract (both install byte-identical content from the same
on-disk source files):**

- **Fresh host (cloud-init):** a minimal launcher runcmd pulls `var.image_name`,
  `docker cp`s `/opt/soleur/host-scripts/.` to a temp dir, verifies the combined
  `host_scripts_content_hash`, then runs the baked `soleur-host-bootstrap.sh`
  which installs each file with an authoritative mode + writes the fail-closed
  `/run/soleur-hostscripts.ok` sentinel. The install ceremony lives in the baked
  script (not inline) so it costs zero `user_data` bytes.
- **Running host (unchanged):** the SSH/webhook `terraform_data` provisioners
  (`deploy_pipeline_fix`, `infra_config_handler_bootstrap`, `journald_persistent`,
  `cron_egress_firewall`, …) still deliver the same files to `web-1`
  (`ignore_changes=[user_data]`), so a code merge is inert on the live host.

**Recorded decisions:**

1. **Scripts ride `var.image_name`, no separate pinned tag** — avoids the
   inngest-bootstrap-style pin-drift; the baked assets are version-coherent with
   the image by construction.
2. **`host_scripts_content_hash` boot integrity + image↔config coherence** —
   Terraform computes `sha256(join("", sort([filesha256(f) for f in
   local.host_script_files])))` at plan time; the boot recompute (`find … |
   sha256sum | sort | … | sha256sum`) must match before any baked code runs. A
   stale/mis-built/tampered image aborts the boot **loudly** — this converts the
   image-bake stale-image trap this ADR otherwise carries into a hard boot
   failure, not a silent old-script install.
3. **32,768-byte budget enforced** by `plugins/soleur/test/cloud-init-user-data-size.test.ts`
   (web sub-cap budget 30,500 B; measured ~29,256 B). AC11's live `terraform plan`
   is the byte-exact source of truth.
4. **GHCR is public / auth-free at boot** — no `docker login` in runcmd; the
   extraction pull is the first critical-path pull, hardened with a bounded
   `--retry` loop.
5. **Fail-closed** — cloud-init `runcmd` is NOT under a top-level `set -e`, so the
   sentinel gate on the terminal `docker run` (`poweroff -f` on absence) is the
   real fail-closed mechanism; a failed extraction can never bring the app up with
   an unconfigured egress firewall (#5046).

**Scope boundary — the git-data host uses a DISTINCT mechanism (gzip-first).** git-data
runs no docker and pulls no image, so this bake-and-extract mechanism does not apply.
Cumulative script growth across #5865 (provision wrapper), #5877 (remove wrapper), and
#5918 (transport-wrapper cutover) pushed its RAW `user_data` to ~41.7 KB — OVER the same
cap, with the over-cap threshold crossed at #5918.

**Resolved via `base64gzip()` (#5927, 2026-07-03).** The `user_data` expression in
`git-data.tf` is wrapped in Terraform's core `base64gzip()` builtin, which gzips the whole
rendered cloud-config and base64-encodes it. Measured: raw 41,662 B → `gzip -9` 16,447 B →
`base64gzip()` output **21,932 B**, which is the string Hetzner stores against the cap —
UNDER 32,768 with ~10.8 KB headroom. Zero content edits: the template and all 5 injected
scripts stay byte-identical; only the one expression changed.

- **Decode contract (source-confirmed, not a datasource gamble):** Hetzner does NOT accept
  binary user-data, so it base64-decodes the stored string before cloud-init sees it —
  cloud-init's `DataSourceHetzner.maybe_b64decode` (added ≥20.3, PR #448; Ubuntu 24.04 ships
  far newer). Chain: stored base64gzip string → base64-decode → raw gzip bytes (magic `1f 8b`)
  → cloud-init auto-gunzips → byte-identical `#cloud-config`. Because base64 is *mandatory* on
  Hetzner, `base64gzip()` is the intended path, not one option among several. (The web-host
  base64gzip figure in this ADR's history, 140,856 B, was a *size-rejection* measurement —
  web's payload is 4.3× over even gzipped, which is why web uses bake-and-extract; git-data's
  shell payload compresses far better.)
- **Verification status:** the size-guard test (`plugins/soleur/test/cloud-init-user-data-size.test.ts`)
  models the base64gzip'd size with REAL script content and asserts `< 32,768` (sub-cap budget
  28,000 B) — the pre-merge byte estimate. `terraform console` cannot yield a concrete number
  pre-provisioning (the map injects `hcloud_volume.git_data{,_luks}.id` + the Doppler service-
  token key, all `known after apply`). Byte-exact truth is #5887's first `terraform plan`; the
  empirical decode confirmation is #5887's first provisioning, where the web-host-driven
  readiness check (`git-data.tf:9-14`) fails **fail-closed** if cloud-init did not decode/run.
- **Security forward-note:** `base64gzip()` is a lossless *encoding*, NOT encryption. The scoped
  `prd_git_data` Doppler token remains recoverable from `terraform.tfstate` and the Hetzner API
  exactly as before — no new exposure vector. But any *future* control that scans tfstate or
  `terraform plan` output for secret literals must `base64 -d | gunzip` first, or it will be
  blind to the gzipped envelope. (No live regression: today's CI secret-scan is `gitleaks git`
  over committed source, where the token is only a TF reference.)

**Accretion advisory (non-blocking):** this is ADR-080's second stretch onto Hetzner 32 KB
`user_data` cap handling (a no-docker concern unrelated to image rebuild). A future
consolidation of "Hetzner user_data cap handling" into a small dedicated ADR that both the web
and git-data hosts reference could reduce accretion. Out of scope here.

### C4 impact (this amendment)

Adds one external system `ghcr` ("GitHub Container Registry") + one edge
`hetzner -> ghcr "Pulls app image + baked bootstrap scripts/hooks at boot"` to
`model.c4`, included in the L1/L2 views. The change makes the host↔image coupling
load-bearing for fresh-host bootstrap, which was previously unmodeled. (The base
ADR's "C4 impact: None" still holds for the CI-trigger decision; this amendment's
delivery-path change is what introduces the `ghcr` element.)
