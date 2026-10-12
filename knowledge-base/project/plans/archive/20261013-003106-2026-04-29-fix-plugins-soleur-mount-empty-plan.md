---
title: "Fix /mnt/data/plugins/soleur empty-mount: silent no-op SDK plugin discovery"
issue: 3045
type: bug
classification: silent-fallback
requires_cpo_signoff: false
created: 2026-04-29
deepened: 2026-04-29
branch: feat-one-shot-3045-plugins-mount
worktree: .worktrees/feat-one-shot-3045-plugins-mount
---

# fix: populate /mnt/data/plugins/soleur on prod hosts (or remove the mount cleanly)

Closes #3045.

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** 8 (Overview, Hypotheses, Files to Edit, Files to Create, Acceptance Criteria, Test Scenarios, Sharp Edges, Alternatives)
**Research sources used:** repo grep (deploy/canary/sudoers semantics), institutional learning `2026-03-20-docker-nonroot-user-with-volume-mounts.md`, observability surface read (`reportSilentFallback`), server entry read (`server/index.ts`), open scope-out cross-check (#2608, #2955, #2962), code-grep verification (`PLUGIN_PATH` dead-code), the canary lifecycle in `ci-deploy.sh:255-394`.

### Key Improvements

1. **Sequencing fix surfaced.** The seed step MUST run *before* canary launch — not "before container start" generically. The canary launches at `ci-deploy.sh:255` with `-v /mnt/data/plugins/soleur:...:ro`; if seeded after canary launch, canary itself sees an empty mount and the Layer 3 verification (which itself depends on plugin-mount-shipped scripts per line 332) cannot fire. Plan now prescribes a `docker create` + `docker cp` + `docker rm` ephemeral-container pattern that runs **between `docker pull` and the canary `docker run`**.
2. **No sudo required.** Webhook runs as `User=deploy` with `ReadWritePaths=/mnt/data /var/lock` and cloud-init `chown -R deploy:deploy /mnt/data` at line 303 — `docker cp` invoked by deploy writes to the bind-mount source directly. Sudoers (`/etc/sudoers.d/deploy-chown`) only grants `chown 1001:1001 /mnt/data/workspaces` — narrowly scoped, do NOT widen.
3. **Use `docker create`, not `docker exec` on a running container.** During the canary deploy, the new image's container is the canary itself (port 3001). Spinning up an ephemeral copy-only container with `docker create --name soleur-plugin-seed "$IMAGE:$TAG"` avoids racing the canary's startup AND avoids needing the canary to be running before seeding. Tear-down via `docker rm soleur-plugin-seed`.
4. **Idempotent seed semantics.** `docker cp src/. dst/` overwrites file-by-file. To guarantee removal of stale entries from prior plugin versions, prescribe `rm -rf /mnt/data/plugins/soleur/{*,.[!.]*,..?*} 2>/dev/null || true` before the `docker cp`. Bracket glob handles both visible and dotfile entries (e.g., `.claude-plugin/`).
5. **Three-file lockstep matches prior learning.** `2026-03-20-docker-nonroot-user-with-volume-mounts.md` documented the Dockerfile + deploy-workflow + cloud-init three-file sync rule for non-root migrations. The same rule applies here for plugin seeding — and the plan already covers all three. Cite the learning directly so the reviewer recognizes the pattern.
6. **Convergence with #3033.** PR #3042 fixes #3033 (`apps` mount Layer 3 path); this PR fixes #3045 (`plugins` mount empty). Both touch `ci-deploy.sh` and `cloud-init.yml`. Coordination guidance moved to a top-level Sequencing section (was Sharp Edges only).
7. **`reportSilentFallback` signature and call site validated** against `apps/web-platform/server/observability.ts:82` — `feature` is required, `op` and `extra` are optional. Plan-prescribed call signature now matches exactly.
8. **Server entry wiring concretized.** `apps/web-platform/server/index.ts` is the entry (compiled to `dist/server/index.cjs`). The startup check fires inside `app.prepare().then(...)` callback after Sentry init (`import "../sentry.server.config"` is the first import). Plan now names the precise insertion point.

### New Considerations Discovered

- **Docker build-context constraint (LOAD-BEARING).** The release workflow uses `docker_context: "apps/web-platform"` (verified at `.github/workflows/web-platform-release.yml:36`), so a naive `COPY plugins/soleur /opt/soleur/plugin` in the Dockerfile would FAIL — `plugins/` is at the repo root, outside the build context. The deepen pass discovered this constraint and pivoted to a vendor-into-context pattern via a new optional `vendor_plugin` input on `reusable-release.yml`. This is the main architectural change between the original plan and the deepened plan.
- **`.dockerignore` allowlist gap.** `apps/web-platform/.dockerignore` excludes `*.md` to keep markdown out of the runtime image. But the plugin's `.md` files (skill SKILL.md, agent prompts) ARE the plugin behavior — they MUST ship. Plan now adds two `!_plugin-vendored/**` re-include lines so the vendored tree's markdown survives the existing exclusions.
- **The Layer 3 canary script (`canary-bundle-claim-check.sh`) is also mounted from the plugin path** per the comment at `ci-deploy.sh:332` ("the script is shipped via the read-only plugin mount"). So #3045's empty-mount fix unblocks #3033's Layer 3 visibility *and* the original SDK plugin discovery. Once both PRs land, Layer 3 actually runs against fresh plugin content for the first time since the canary system was introduced.
- **The bind-mount being `:ro` from the container's perspective does NOT prevent host-side writes** to the bind-mount source. Host writes propagate live to the container's view (this is a kernel bind-mount property, not Docker-specific). Re-seeding while a container holds `:ro` is safe; the running container will see new content on next `readFileSync`.
- **Cloud-init runcmd entries run under `/bin/sh` (= `dash`)**, NOT bash. The brace-expansion form `{*,.[!.]*,..?*}` is bash-only — using it in cloud-init silently produces wrong cleanup (dotfiles like `.claude-plugin/` survive). Plan now uses `find -mindepth 1 -delete` in cloud-init's seed block (POSIX-portable) and reserves the bash brace form for `ci-deploy.sh` (which has `#!/usr/bin/env bash`).
- **Sentry is already wired via `sentry.server.config`** as the first import in `server/index.ts`. The startup check can call `reportSilentFallback` immediately during `app.prepare().then(...)` without additional Sentry boot ordering.
- **Webhook runs as `User=deploy` with `ReadWritePaths=/mnt/data /var/lock`** (cloud-init line 173, 179) and cloud-init recursively chowns `/mnt/data` to deploy:deploy at provision (line 303). `docker cp` invoked by the deploy user can write to the bind-mount source without sudo. Sudoers grants only the narrow `chown 1001:1001 /mnt/data/workspaces` privilege — do NOT widen.

## Overview

Issue #3045 surfaced during #3033 verification: the bind mount
`/mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro` exists on every
prod host and is mounted into the canary + main containers, but **nothing
ever populates the source directory**. Cloud-init's runcmd `mkdir -p`
creates the directory empty; no terraform `provisioner`, no CI rsync, no
post-deploy hook, no Dockerfile `COPY` writes the plugin into it. The
runtime callers therefore see an empty directory on every read.

The downstream blast radius is larger than the issue body implies:

1. `apps/web-platform/server/workspace.ts:381` symlinks
   `<workspace>/plugins/soleur` → `/app/shared/plugins/soleur` (empty).
2. `apps/web-platform/server/agent-runner.ts:549` reads
   `<workspace>/plugins/soleur/.claude-plugin/plugin.json`. The file is
   missing because the mount is empty. The catch on line 554-566 treats
   ENOENT as "no plugin installed" and silently sets
   `pluginMcpServerNames = []`. ENOENT is **not** mirrored to Sentry
   (line 559: `if ((err)?.code !== "ENOENT")` — the `cq-silent-fallback`
   rule is intentionally skipped here because ENOENT was assumed to be
   "expected when no plugin").
3. `apps/web-platform/server/cc-dispatcher.ts:424` does the same lookup
   for cc-soleur-go (`pluginPath = path.join(workspacePath, "plugins",
   "soleur")`) and feeds the SDK an empty directory.
4. The Agent SDK launches with `pluginPath` pointing at an empty dir →
   **no Soleur skills, no Soleur agents, no Soleur MCP servers ever
   load in user-facing web-platform sessions**, despite the entire
   architecture being designed for that.

Issue #2608 ("plugin freshness rotation for running workspaces")
explicitly claims: *"'Latest' is tied to image deploy cadence — when
the container image updates, all running workspaces see the new plugin
on the next symlink dereference."* This is the documented design intent
— but the Dockerfile (`apps/web-platform/Dockerfile`) does **not**
COPY the plugin into the image. The intended mechanism was either never
implemented or lost in a refactor. The mount has been empty since the
web-platform MVP commit `5b8e2420` (PR closing #297) — months in
production.

This plan delivers the smallest, lowest-risk fix that closes the
investigation: **bake the plugin into the runtime image at build time
and populate the bind-mount source from the running container at deploy
time, with explicit verification that the mount source is non-empty
before the canary container launches.** Removing the mount is a viable
alternative but more invasive (changes ci-deploy.sh, cloud-init.yml, and
the canary flow simultaneously) — see Alternatives Considered.

## Research Reconciliation — Spec vs. Codebase

Issue #3045 paraphrases call-site line numbers and a callable surface.
Three reconciliations against the live codebase:

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| `cc-dispatcher.ts:387` is a mount caller | Line 387 is `fetchUserWorkspacePath`'s `await supabase()...` call. The real caller is **line 424**: `const pluginPath = path.join(workspacePath, "plugins", "soleur")`. | Plan addresses line 424 (and the symmetric line 542 in `agent-runner.ts`). |
| `agent-runner.ts:542` is the only caller in that file | Line 542 IS a real caller. But `agent-runner.ts:55-56` *also* declares `const PLUGIN_PATH = process.env.SOLEUR_PLUGIN_PATH || "/app/shared/plugins/soleur"` — and `grep -n "\bPLUGIN_PATH\b" apps/web-platform/server/agent-runner.ts` returns only the declaration site. The constant is **dead code**. | Phase 4 deletes the unused constant in the same PR (no behavior change; reduces code-grep noise for future investigations). |
| `workspace.ts:381-384` warns on failure rather than throwing → "best-effort no-op" | The warn is on `symlinkSync` *failure* (e.g., EEXIST race). The symlink itself **succeeds** because the target directory exists (cloud-init created it). The "no-op" framing is misleading: the symlink is created successfully and points at an empty directory. The failure mode is silent-empty, not warn-and-skip. | Phase 1 ADD a startup-time mount-populated assertion in `workspace.ts` (or a new `plugin-mount-check.ts`) that mirrors to Sentry on empty mount. |

## User-Brand Impact

**If this lands broken, the user experiences:** a Command Center session
that loads but where every Soleur skill (`/soleur:plan`, `/soleur:work`,
`/soleur:brainstorm`, etc.) is missing — the assistant returns "skill
not found" or silently degrades to a generic Claude session. This is
the **current production behavior** for every web-platform user (months
of empty mount); the fix restores the advertised feature surface.

**If this leaks, the user's data/workflow is exposed via:** N/A —
populating an empty read-only mount with public plugin content does
not expose user data. The `:ro` flag on the mount means a compromised
container cannot write back. The plugin source is the same content
already published to the Claude Code marketplace at
`marketplace.json` and `plugin.json` — no secrets are introduced.

**Brand-survival threshold:** none — capability gap, not a privacy or
data-loss surface. Threshold `none` justification: this PR populates
read-only public plugin content that is already in the open repo;
there is no auth/credentials/data/payments/user-resources surface
crossed, so per `plugins/soleur/skills/preflight/SKILL.md` Check 6 the
sensitive-path regex does not fire and no scope-out bullet is required.

## Hypotheses

(No SSH/network-connectivity trigger keywords matched in #3045 — Phase
1.4 network-outage checklist not required.)

The empty-mount root cause is a missing population step. Three plausible
mechanisms, listed in cost-asc order:

1. **Image-baked plugin (most aligned with #2608's documented intent).**
   `apps/web-platform/Dockerfile` `COPY plugins/soleur /opt/soleur/plugin`
   in the runner stage; cloud-init's first deploy seeds
   `/mnt/data/plugins/soleur` from the running container
   (`docker cp soleur-web-platform:/opt/soleur/plugin/. /mnt/data/plugins/soleur/`).
   Subsequent deploys re-seed via the same mechanism in `ci-deploy.sh`
   so plugin updates ride image deploys (matches the #2608 "latest is
   tied to image deploy cadence" contract).
2. **CI rsync from runner to host.** Add a deploy step that rsyncs
   `plugins/soleur/` from the GitHub Actions runner over SSH into
   `/mnt/data/plugins/soleur` before the container starts. Adds an
   SSH-write surface and a second source of truth (runner workspace ≠
   image content); rejected.
3. **Runtime fetch.** Container starts; on first request, fetches the
   plugin from R2 / GitHub. Adds a runtime network dependency and a
   bootstrap race; rejected.

**Chosen: Hypothesis 1.** It is the only one that honors #2608's
already-documented contract and keeps the source of truth in the
container image (single artifact, audited via the existing image SBOM).

## Files to Edit

- `.github/workflows/reusable-release.yml` — add a new optional input `vendor_plugin: bool` (default `false`) and a conditional step that runs BEFORE `docker/build-push-action` when `vendor_plugin == true`:

  ```yaml
  inputs:
    # ... existing inputs ...
    vendor_plugin:
      description: "Vendor plugins/soleur into <docker_context>/_plugin-vendored before build"
      required: false
      type: boolean
      default: false
  ```

  ```yaml
  - name: Vendor plugin into build context
    if: inputs.vendor_plugin == true && inputs.docker_image != ''
    run: |
      set -euo pipefail
      DEST="${{ inputs.docker_context }}/_plugin-vendored"
      rm -rf "$DEST"
      cp -r plugins/soleur "$DEST"
      # Drop test/docs trees that are not needed at runtime — keeps image small
      rm -rf "$DEST/test" "$DEST/docs/_site"
      echo "Vendored $(find "$DEST" -type f | wc -l) plugin files"
  ```

  Place between the existing `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY` step and the `Build and push Docker image` step. Step is idempotent (cleans destination first).

- `.github/workflows/web-platform-release.yml` (line 36 region) — pass `vendor_plugin: true` to the reusable workflow:

  ```yaml
  with:
    component: web-platform
    component_display: "Soleur Web Platform"
    path_filter: "apps/web-platform/"
    tag_prefix: "web-v"
    docker_image: "ghcr.io/jikig-ai/soleur-web-platform"
    docker_context: "apps/web-platform"
    vendor_plugin: true       # NEW (#3045)
    bump_type: ${{ inputs.bump_type || '' }}
    force_run: ${{ github.event_name == 'workflow_dispatch' }}
  ```

- `apps/web-platform/Dockerfile` (runner stage, after line 49) — add:

  ```dockerfile
  # Plugin baked at build time from the vendored copy in the build context (#3045).
  # Source tree is /workflow/plugins/soleur copied to apps/web-platform/_plugin-vendored
  # by reusable-release.yml's "Vendor plugin into build context" step.
  COPY _plugin-vendored /opt/soleur/plugin
  RUN chown -R 1001:1001 /opt/soleur
  ```

  Place BEFORE `USER soleur` (line 76). Mode bits inherit from source (644/755); world-readable suffices since the container reads the bind-mount under UID 1001 and the host bind-mount writer is the deploy user (different UID, but world-readable mode resolves it).

- `apps/web-platform/.dockerignore` — append two lines to ensure the vendored plugin tree is NOT excluded by the existing `*.md` rule:

  ```
  # Vendored plugin tree (#3045) — must ship with all .md content (SKILL.md, agent prompts)
  !_plugin-vendored
  !_plugin-vendored/**
  ```

  `.dockerignore` allowlist semantics: `!` re-includes paths that prior patterns excluded. Without these, the existing `*.md` line at the top would strip the plugin's skill/agent markdown content even though the directory is allowed.

- `.gitignore` (root) — add `apps/web-platform/_plugin-vendored/` so a developer's local `docker build` (which they may run manually for debugging) doesn't bloat git diffs. The vendor step is CI-only in normal flows, but local-dev parity matters for repro.

- Local-dev documentation (where the existing build commands live — likely `apps/web-platform/README.md`, `CONTRIBUTING.md`, or the project root README) — add a one-liner: "If building the web-platform image locally, first run `cp -r plugins/soleur apps/web-platform/_plugin-vendored` from the repo root." Defer to work-phase to locate the right doc anchor.

- `apps/web-platform/infra/cloud-init.yml` — after `docker pull ${image_name}` at line 347 and before the production `docker run -d` at line 366, add a seed block:

  ```yaml
  # Seed /mnt/data/plugins/soleur from the image's baked plugin tree (#3045).
  # Ephemeral container so we don't depend on a long-running container.
  # `docker cp src/.` copies *contents* (not the src dir itself) into dst.
  - |
    set -e
    docker create --name soleur-plugin-seed ${image_name}
    rm -rf /mnt/data/plugins/soleur/{*,.[!.]*,..?*} 2>/dev/null || true
    docker cp soleur-plugin-seed:/opt/soleur/plugin/. /mnt/data/plugins/soleur/
    docker rm soleur-plugin-seed
  ```

  The `set -e` confines the failure scope to just this step (cloud-init runcmd entries are otherwise newline-separated and continue on failure). `mkdir -p /mnt/data/plugins/soleur` at line 299 already runs earlier in the same runcmd block — the dir exists by the time this block fires.

- `apps/web-platform/infra/ci-deploy.sh` — after `docker pull` of the new image (insert between the existing pull step and `docker run -d --name soleur-web-platform-canary` at line 255). The deploy user owns `/mnt/data/plugins/soleur`, so no `sudo` is needed. The `set -e` at the script level (the existing `trap` at line 246 captures non-zero exits) means a failed seed step rolls the deploy back via `final_write_state 1 "plugin_seed_failed"`. New CI deploy path:

  ```bash
  echo "Seeding plugin mount from image..."
  if ! docker create --name soleur-plugin-seed "$IMAGE:$TAG" >/dev/null; then
    final_write_state 1 "plugin_seed_create_failed"
    exit 1
  fi
  rm -rf /mnt/data/plugins/soleur/{*,.[!.]*,..?*} 2>/dev/null || true
  if ! docker cp soleur-plugin-seed:/opt/soleur/plugin/. /mnt/data/plugins/soleur/; then
    docker rm soleur-plugin-seed >/dev/null 2>&1 || true
    final_write_state 1 "plugin_seed_copy_failed"
    exit 1
  fi
  docker rm soleur-plugin-seed >/dev/null
  ```

  Sequencing constraint: this MUST run before the canary `docker run` (line 255) so the canary itself sees a populated mount on first read.

- `apps/web-platform/server/agent-runner.ts` — delete lines 55-56 (`const PLUGIN_PATH = ...`). Verify with `grep -n '\bPLUGIN_PATH\b' apps/web-platform/` returns zero matches after the edit (the constant is unreferenced; deletion is mechanical dead-code removal). Do this in the same PR so future plan-grep on the symbol returns one obvious answer.

- `apps/web-platform/server/index.ts` — inside the `app.prepare().then(() => { ... })` callback at the existing top-level (line ~42), call `verifyPluginMountOnce()` from the new module before `setupWebSocket(server)`. This places the check after Sentry init (the file's first import is `../sentry.server.config`) but before the WebSocket loop is accepting connections — we want the Sentry event to fire even if subsequent server boot fails. Single line: `verifyPluginMountOnce();` (sync, fast — `readdirSync` on a small directory).

## Files to Create

- `apps/web-platform/server/plugin-mount-check.ts` — new module:

  ```ts
  import { existsSync, readdirSync } from "fs";
  import { join } from "path";
  import { reportSilentFallback } from "./observability";
  import { createChildLogger } from "./logger";

  const log = createChildLogger("plugin-mount");

  function getPluginPath(): string {
    return process.env.SOLEUR_PLUGIN_PATH || "/app/shared/plugins/soleur";
  }

  let _checked = false;

  /**
   * One-shot startup verification that the plugin bind-mount source has
   * been populated by the deploy script. Runs once per process; subsequent
   * calls are no-ops. Mirrors the empty-mount degraded condition to Sentry
   * via `reportSilentFallback` so a regression in the deploy seed step is
   * visible in dashboards instead of being a silent feature drop. See #3045.
   */
  export function verifyPluginMountOnce(): void {
    if (_checked) return;
    _checked = true;

    const pluginPath = getPluginPath();

    if (!existsSync(pluginPath)) {
      reportSilentFallback(null, {
        feature: "plugin-mount",
        op: "discovery",
        message: "plugin-mount path missing",
        extra: { path: pluginPath },
      });
      log.error({ path: pluginPath }, "Plugin mount path does not exist");
      return;
    }

    let entries: string[] = [];
    try {
      entries = readdirSync(pluginPath);
    } catch (err) {
      reportSilentFallback(err, {
        feature: "plugin-mount",
        op: "discovery",
        extra: { path: pluginPath },
      });
      log.error({ err, path: pluginPath }, "Plugin mount unreadable");
      return;
    }

    if (entries.length === 0) {
      reportSilentFallback(null, {
        feature: "plugin-mount",
        op: "discovery",
        message: "plugin-mount empty",
        extra: { path: pluginPath },
      });
      log.error({ path: pluginPath }, "Plugin mount is empty");
      return;
    }

    const manifest = join(pluginPath, ".claude-plugin", "plugin.json");
    if (!existsSync(manifest)) {
      reportSilentFallback(null, {
        feature: "plugin-mount",
        op: "discovery",
        message: "plugin-mount manifest missing",
        extra: { path: pluginPath, manifest },
      });
      log.error({ manifest }, "Plugin mount missing .claude-plugin/plugin.json");
      return;
    }

    log.info({ path: pluginPath, entries: entries.length }, "Plugin mount OK");
  }

  /** Test-only memoization reset. Not exported from server entry. */
  export function _resetForTesting(): void {
    _checked = false;
  }
  ```

  Three-state Sentry signal (path-missing / empty / manifest-missing) lets dashboards distinguish "Hetzner volume failed to attach" from "deploy seed step skipped" from "deploy ran but image didn't COPY the plugin." All three produce `feature: "plugin-mount", op: "discovery"`; the `message` and `extra.path/manifest` fields differentiate. Verified `reportSilentFallback` signature against `apps/web-platform/server/observability.ts:82` — `feature` required, `op`/`extra`/`message` optional.

- `apps/web-platform/test/plugin-mount-check.test.ts` — Vitest covering:
  - **Scenario A (path missing):** `SOLEUR_PLUGIN_PATH=/nonexistent` → `reportSilentFallback` mock called once with `feature: "plugin-mount", op: "discovery"`, message `"plugin-mount path missing"`.
  - **Scenario B (empty):** point at a temp dir created with `mkdirSync` and not populated → fires with message `"plugin-mount empty"`.
  - **Scenario C (manifest missing):** point at a temp dir with one stray file but no `.claude-plugin/plugin.json` → fires with `"plugin-mount manifest missing"`.
  - **Scenario D (populated):** create temp dir with `.claude-plugin/plugin.json` → no Sentry call, `log.info` fired.
  - **Scenario E (memoization):** call `verifyPluginMountOnce()` twice with empty dir → mock called exactly once.

  Use `vi.mock("./observability")` to spy on `reportSilentFallback`. Use `tmpdir()` + `randomUUID()` for fixture paths. Wire `_resetForTesting()` in `beforeEach`.

- `apps/web-platform/infra/test/cloud-init-plugin-seed.test.sh` — bash test in the existing `*.test.sh` pattern (sibling of `ci-deploy.test.sh`):

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"; docker rm -f soleur-plugin-seed-test >/dev/null 2>&1 || true' EXIT

  # Build a tiny image with a synthetic plugin tree
  cat > "$TMP/Dockerfile" <<'EOF'
  FROM busybox
  RUN mkdir -p /opt/soleur/plugin/.claude-plugin && \
      echo '{"name":"soleur-test"}' > /opt/soleur/plugin/.claude-plugin/plugin.json && \
      mkdir -p /opt/soleur/plugin/skills/test && \
      echo "stub" > /opt/soleur/plugin/skills/test/SKILL.md
  EOF
  docker build -t soleur-plugin-seed-test:fixture "$TMP" >/dev/null

  # Pre-populate the bind-mount target with stale content to verify cleanup
  TARGET="$TMP/mnt/data/plugins/soleur"
  mkdir -p "$TARGET"
  echo "stale" > "$TARGET/stale-file.txt"
  mkdir -p "$TARGET/.stale-dir"

  # Run the seed sequence (verbatim from ci-deploy.sh)
  docker create --name soleur-plugin-seed-test soleur-plugin-seed-test:fixture >/dev/null
  rm -rf "$TARGET"/{*,.[!.]*,..?*} 2>/dev/null || true
  docker cp soleur-plugin-seed-test:/opt/soleur/plugin/. "$TARGET/"
  docker rm soleur-plugin-seed-test >/dev/null

  # Assertions
  test -f "$TARGET/.claude-plugin/plugin.json" || { echo "FAIL: manifest missing"; exit 1; }
  test -f "$TARGET/skills/test/SKILL.md" || { echo "FAIL: skill stub missing"; exit 1; }
  test ! -e "$TARGET/stale-file.txt" || { echo "FAIL: stale file remained"; exit 1; }
  test ! -e "$TARGET/.stale-dir" || { echo "FAIL: stale dotdir remained"; exit 1; }
  echo "PASS: cloud-init-plugin-seed"
  ```

  Test must be runnable locally (Docker available) and via the `apps/web-platform/infra/ci-deploy.test.sh` harness. Skip if Docker is unavailable (CI runner without docker-in-docker) — emit `SKIP: docker not available` and exit 0.

## Open Code-Review Overlap

Two open scope-outs touch the modified files:

- **#2962** — *review: extract memoized getServiceClient() shared lazy singleton* (touches `agent-runner.ts`, `cc-dispatcher.ts`). **Disposition: Acknowledge.** Different concern (Supabase service-client memoization vs. plugin mount); refactor scope is orthogonal and would unnecessarily inflate this PR. The scope-out remains open.
- **#2955** — *arch: process-local state assumption needs ADR + startup guard* (touches `agent-runner.ts`, `cc-dispatcher.ts`). **Disposition: Acknowledge with reuse hint.** This plan adds a new process-local one-shot check (`verifyPluginMountOnce` memoization). When #2955's startup-guard architecture lands, the new check should be migrated to that pattern. Note in this PR's body so the reviewer of #2955 can fold it in.
- **#2608** — *ops: plugin freshness rotation for running workspaces* (parent design issue). **Disposition: Fold reference; do not fold scope.** This PR delivers the prerequisite #2608 assumed (image-baked plugin) but does NOT implement the rotation API #2608 describes. After this lands, #2608's re-evaluation criterion ("first time a plugin hotfix needs to land faster than container deploy permits") becomes meaningful for the first time. Add a comment on #2608 noting this dependency was unmet and is now met.

## Sequencing & Coordination

This PR and PR #3042 (#3033 fix) both modify `ci-deploy.sh` and `cloud-init.yml`. They are independent corrections to the same deploy flow but textually adjacent. Recommended sequencing:

1. **Land #3042 first** (#3033 Layer 3 mount fix) — adds an `apps` mount which is independent of plugin mount semantics.
2. **Rebase this PR on `main` after #3042 merges** — should be a clean rebase since the two PRs touch different lines of `ci-deploy.sh` (the canary `docker run` block at line 255 vs. the new pre-canary seed block this PR adds).
3. **If this PR lands first** instead, #3042 must rebase. Either order works; the earlier-merger does not need rebase.

**Composite verification (post both merges):** with both `apps` and `plugins` mounts populated, the Layer 3 canary should run for the first time since the canary system was introduced. Expect the first deploy after both land to take an extra ~15 seconds for the new probe and to either pass or surface a real Layer 3 finding (which would then be worked as a separate issue).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/Dockerfile` runner stage COPYs `_plugin-vendored` to `/opt/soleur/plugin` with `chown -R 1001:1001 /opt/soleur` BEFORE the `USER soleur` line; image build succeeds locally via `cd apps/web-platform && cp -r ../../plugins/soleur _plugin-vendored && docker build .` (the manual vendor step replicates what CI does).
- [x] `.github/workflows/reusable-release.yml` adds the `vendor_plugin` input (default false) and the conditional vendor step BEFORE `docker/build-push-action`; `web-platform-release.yml` passes `vendor_plugin: true`.
- [x] `apps/web-platform/.dockerignore` re-includes `_plugin-vendored/**` so plugin markdown content is NOT excluded by the existing `*.md` rule.
- [x] `.gitignore` includes `apps/web-platform/_plugin-vendored/` to prevent accidental commits of the vendored tree.
- [x] `cloud-init.yml` and `ci-deploy.sh` contain the seed block (`docker create` + `rm -rf`/`find -mindepth 1 -delete` + `docker cp` + `docker rm`) BEFORE the canary `docker run` block; the seed step exits 0 against a synthetic container (per `cloud-init-plugin-seed.test.sh`).
- [x] The `rm -rf /mnt/data/plugins/soleur/{*,.[!.]*,..?*}` glob is verified by `cloud-init-plugin-seed.test.sh` (test pre-populates target with both `.stale-dir` and `stale-file.txt`, asserts both are removed by the cleanup step).
- [x] `agent-runner.ts:55-56` `PLUGIN_PATH` constant is removed; `grep -rn '\bPLUGIN_PATH\b' apps/web-platform/` returns zero matches outside vendored/`node_modules`/`.next`.
- [x] `apps/web-platform/server/index.ts` calls `verifyPluginMountOnce()` inside `app.prepare().then(...)` before `setupWebSocket(server)`.
- [x] `apps/web-platform/test/plugin-mount-check.test.ts` covers all five scenarios (path-missing / empty / manifest-missing / populated / memoization) and passes under `npx vitest run test/plugin-mount-check.test.ts` (5/5 ✓).
- [x] `apps/web-platform/infra/cloud-init-plugin-seed.test.sh` passes against the synthetic-image fixture (PASS local; skips cleanly if Docker is unavailable). Note: located alongside the other `*.test.sh` files at `apps/web-platform/infra/`, not in a `test/` subdir, to match the existing convention (`ci-deploy.test.sh`, `disk-monitor.test.sh`).
- [x] `npx vitest run` in `apps/web-platform/` is green: 3018 passed | 11 skipped (3029) — no regression in adjacent suites.
- [x] `npx tsc --noEmit` clean (exit 0).
- [x] No new dependencies added.
- [x] Plan-derived globs verified at plan time: `git ls-files apps/web-platform/server | grep -E 'workspace\.ts$|agent-runner\.ts$|cc-dispatcher\.ts$|index\.ts$|observability\.ts$'` returns 5 matches.
- [x] `git ls-files apps/web-platform/infra | grep -E 'cloud-init\.yml$|ci-deploy\.sh$'` returns 2 matches.
- [x] PR body uses `Closes #3045` (population is automated end-to-end via image + ci-deploy — no operator-only step gates closure).
- [x] PR body cross-references #3033/#3042 in the Sequencing section so reviewers can confirm rebase order.

### Post-merge (operator)

- [ ] First deploy after merge: monitor `journalctl -u webhook -f` on `app.soleur.ai` and confirm the seed step prints `Seeding plugin mount from image...` and exits 0.
- [ ] SSH `app.soleur.ai` (deploy user) and run `ls /mnt/data/plugins/soleur/.claude-plugin/plugin.json` — must exist and be readable.
- [ ] `docker exec soleur-web-platform ls /app/shared/plugins/soleur/.claude-plugin/plugin.json` — must exist and be readable as UID 1001 (canary readability check).
- [ ] **Sentry:** in the 60 minutes following first post-merge deploy, confirm zero new `feature: "plugin-mount"` events. (Pre-merge baseline establishes the existing-empty-mount fire rate as the proof-of-fire signal — confirm at least one event was captured by the new code on a host that hasn't yet been re-deployed.)
- [ ] Run a Command Center session against `app.soleur.ai` and execute `/soleur:help` — output MUST list non-zero commands/skills (current behavior: empty list / "skill not found"). This is the user-facing acceptance.
- [ ] Comment on #2608 with: "PR #<this> delivered image-baked plugin (the prerequisite #2608 implicitly assumed). The 're-evaluation criterion' (plugin hotfix faster than container deploy) is now genuinely actionable since the bind-mount is populated and refresh is a single `docker cp` away."
- [ ] If this is the first deploy where Layer 3 canary actually executes (PR #3042 also merged), document the Layer 3 outcome in the deploy postmortem — pass or surface a real finding to triage separately.

## Test Scenarios

### Scenario A — Empty mount fires Sentry on boot (the load-bearing regression guard)

**Given** `/app/shared/plugins/soleur` is empty (mount source not seeded), **when** the server process starts, **then** `verifyPluginMountOnce` fires exactly one `reportSilentFallback` with `feature: "plugin-mount"`.

### Scenario B — Populated mount is silent

**Given** `/app/shared/plugins/soleur/.claude-plugin/plugin.json` exists and is readable, **when** the server starts, **then** `verifyPluginMountOnce` returns silently (no Sentry event, no error log).

### Scenario C — Idempotent re-seed across deploys

**Given** `/mnt/data/plugins/soleur` already contains stale plugin content from a prior deploy, **when** `ci-deploy.sh` runs the seed step against the new image, **then** the destination contains the new image's content and the operation exits 0 (no "destination not empty" failure).

### Scenario D — Permission compatibility with `:ro` mount and UID 1001

**Given** the mount is populated by `docker cp` (writes as deploy:deploy on host since the webhook runs `User=deploy`, NOT root), **when** the container starts with `-v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro` and runs as soleur UID 1001, **then** `readFileSync` from inside the container succeeds because `docker cp` preserves the source mode bits (which are 644/755 from the Dockerfile `chown -R 1001:1001 /opt/soleur` step) and `:ro` does not strip read permission. Test via `cloud-init-plugin-seed.test.sh` extended assertion: after seed, `stat -c '%a %U %G' /mnt/data/plugins/soleur/.claude-plugin/plugin.json` returns mode bits with at least the `4` bit set in the world position.

### Scenario E — Cloud-init shell portability

**Given** `cloud-init.yml` uses `- |` block scalars (executed by Ubuntu's `/bin/sh` = `dash`, no brace expansion), **when** the seed block runs at first boot, **then** the `find /mnt/data/plugins/soleur -mindepth 1 -delete` cleanup executes correctly (POSIX-portable). Negative test: a fixture that uses `{*,.[!.]*,..?*}` under `dash` would silently leave dotfiles. Add a shellcheck assertion in CI that catches `bash`-only constructs in cloud-init `- |` blocks.

### Scenario F — Sequencing under canary failure

**Given** the seed step succeeds but the canary fails downstream (e.g., bwrap sandbox check fails), **when** rollback fires, **then** the plugin mount remains populated with the new content (no automatic rollback of the bind-mount). This is acceptable: the prior production container still serves on port 80 and reads from the same mount; if the new content is incompatible with the old code, this would surface as a separate runtime issue. Document in the deploy runbook: a rolled-back deploy leaves the plugin mount at the *attempted* version, not the prior version. Operator may choose to re-run a `docker cp` from a known-good prior image if needed (out of scope for this PR; tracked under #2608's rotation work).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.
The plugin content is already public, plugin distribution does not
touch auth/credentials/data/payments. CTO is implicitly relevant
(Dockerfile + ci-deploy + cloud-init touch architecture) but the
change is a single-PR three-line fix to a documented design intent —
no domain-leader Task spawn is justified per Phase 0.5 brainstorm
gate (no new capability surface, no new vendor, no new data flow).

## Sharp Edges

- **Bash brace-glob with dotfiles.** `rm -rf /mnt/data/plugins/soleur/{*,.[!.]*,..?*}` is the canonical pattern to match all entries including dotfiles while excluding `.` and `..`. A naive `rm -rf /mnt/data/plugins/soleur/*` leaves `.claude-plugin/` (which is the plugin's load-bearing directory!) on the bind-mount source, producing stale-plus-fresh hybrid content. **Verify the glob matches before merging:** `bash -c 'set -- /tmp/test/{*,.[!.]*,..?*}; echo "$@"'` against a fixture with both `regular.txt` and `.dotfile`.

- **`docker cp` and trailing slashes — load-bearing.** `docker cp src/. dst/` copies *contents* of `src` into `dst`. `docker cp src dst` (no trailing `/.`) copies `src` *as a child* of `dst`, producing `dst/plugin/.claude-plugin/...` instead of `dst/.claude-plugin/...`. The mount is bound at `/app/shared/plugins/soleur` so the manifest must be at `${mount}/.claude-plugin/plugin.json`, not `${mount}/plugin/.claude-plugin/plugin.json`. The `cloud-init-plugin-seed.test.sh` fixture asserts the correct destination layout.

- **Read-only mount + host writes.** `:ro` flags apply to the container's view of the bind mount, NOT the host's view. Host-side writes to `/mnt/data/plugins/soleur` propagate live to the container's view (Linux kernel bind-mount property). Re-seeding while a container holds the mount `:ro` is safe and visible to the running container immediately. `existsSync` / `readFileSync` from inside the container will pick up new content on next call.

- **`docker create` is not `docker run`.** `docker create` instantiates a container without starting it — it never executes `CMD`, never opens sockets, never claims ports. We use `docker create` precisely because we don't want a running second instance of the new image during the canary deploy. Cleanup is `docker rm` (no `--force` needed since the container was never running).

- **Image-build context and `COPY plugins/soleur`.** The `Dockerfile` lives at `apps/web-platform/Dockerfile` but the build context is the **repo root** (per `web-platform-release.yml`). `COPY plugins/soleur /opt/soleur/plugin` therefore resolves correctly. Verify by checking the existing `web-platform-release.yml` build step uses `context: .` — if it uses `context: apps/web-platform/`, the COPY would fail and the plan must change to a multi-stage approach.

- **Symlink-traversal vs. bind-mount in `verifyPluginMountOnce`.** `existsSync` and `readdirSync` follow symlinks transparently, which is what we want here — `<workspace>/plugins/soleur` is a symlink in user workspaces, but the startup check looks at the source-of-truth path (`SOLEUR_PLUGIN_PATH` or `/app/shared/plugins/soleur`) which is the bind-mount target itself, not a symlink. No `realpathSync` needed.

- **`agent-runner.ts:559` ENOENT-skip is intentionally NOT promoted to Sentry.** The ENOENT path remains silent because per-user `plugin.json` reads happen on every session start; with the empty-mount fix in place, ENOENT is a transient condition (not steady-state). The new startup check (`verifyPluginMountOnce`) fires the Sentry signal exactly once per process boot — the right cardinality. Do NOT remove the catch in `agent-runner.ts`; do NOT add `reportSilentFallback` there. The two layers are complementary.

- **`Closes #3045` is correct, NOT `Ref #3045`.** The ops-remediation rule (`closes-vs-ref` for ops PRs) applies when the fix executes post-merge and the AC is operator-only. Here the fix lands in the image at merge time AND ci-deploy.sh seeds the mount on the next deploy automatically — no operator action gates closure. Standard `Closes #N` semantics apply.

- **`PLUGIN_PATH` dead-code removal pre-flight.** Before deleting `agent-runner.ts:55-56`, run `grep -rn '\bPLUGIN_PATH\b' apps/web-platform/server/` to re-verify zero usages (the symbol might be re-imported by a sibling change between plan-time and work-time). The grep is the load-bearing safety check, not the deletion itself.

- **User-Brand Impact threshold gate.** Section is present, threshold is `none` with non-empty reason, sensitive-path regex (`apps/web-platform/(server|supabase|...)`) DOES match the modified server-path files — but the change populates a public read-only mount (no auth/credentials/data/payments) so the `threshold: none, reason: ...` scope-out bullet is justified per preflight Check 6. Verified `## User-Brand Impact` block contains the required `If this lands broken / If this leaks / Brand-survival threshold` lines and the scope-out bullet.

- **Bash glob expansion under `set -e` in cloud-init.** Cloud-init runcmd entries are executed by `sh -c`, not `bash`. The brace expansion `{*,.[!.]*,..?*}` is a **bash extension**, NOT POSIX sh. The seed block uses an explicit `- |` multi-line entry which cloud-init runs as a single shell invocation under whatever shell is the entry's shebang (defaults to `/bin/sh`, which on Ubuntu is `dash` — no brace expansion). **Mitigation:** the seed block must start with `set -e` AND use `bash -c '...'` to wrap the brace-glob, OR use a shell-portable form: `find /mnt/data/plugins/soleur -mindepth 1 -delete`. The `find -delete` form is portable and equivalent. Plan-time choice: use `find -mindepth 1 -delete` in cloud-init's `- |` block; the bash-specific brace expansion stays only in `ci-deploy.sh` which is run as `bash` per its shebang.

  **Update prescribed cloud-init seed block:**

  ```yaml
  - |
    set -e
    docker create --name soleur-plugin-seed ${image_name}
    find /mnt/data/plugins/soleur -mindepth 1 -delete 2>/dev/null || true
    docker cp soleur-plugin-seed:/opt/soleur/plugin/. /mnt/data/plugins/soleur/
    docker rm soleur-plugin-seed
  ```

  **`ci-deploy.sh` keeps the bash brace-glob form** (its shebang is `#!/usr/bin/env bash` — verify before merging).

- **Verbatim string literal: `feature: "plugin-mount"`, `op: "discovery"`.** Used in (a) `plugin-mount-check.ts` (5 sites: 4 `reportSilentFallback` calls + 1 future regression-baseline note), (b) `plugin-mount-check.test.ts` (5 assertions), (c) Acceptance Criteria post-merge step ("Sentry: confirm zero `feature: \"plugin-mount\"` events"). Grep-confirm one canonical pair across all sites before merging — drift between code and tests is the highest-risk class for this plan per the deepen-plan quality checklist.

## Alternatives Considered

| Alternative | Pros | Cons | Verdict |
|---|---|---|---|
| Remove the mount entirely; rely on the image's `/opt/soleur/plugin` directly via a `SOLEUR_PLUGIN_PATH=/opt/soleur/plugin` env var; delete the bind-mount + symlink. | Simpler steady state; one source of truth (image only); honors #2608's "deploy cadence" contract trivially. | Breaks the rotation-without-redeploy story #2608 wants to preserve as a re-evaluation option. Larger blast radius (touches both apps and infra). Loses the per-host plugin-update surface that future hotfix automation may need. | Rejected. #2608 explicitly wants the bind-mount to remain so a future API endpoint can re-point/refresh it without a container redeploy. |
| Run `git clone` of the soleur repo at cloud-init time into `/mnt/data/plugins/soleur`. | No image change; no docker cp dance. | Adds a runtime auth dependency (GitHub token at provision time); tight coupling between host-bootstrap and a private-vs-public repo decision; provision-time network dependency. | Rejected. |
| GitHub Actions step rsyncs `plugins/soleur/` from the runner over SSH to the host before container start. | Decouples plugin version from image version (potential ops upside). | Adds an SSH-write surface; second source of truth (runner workspace ≠ image); `hr-all-infrastructure-provisioning-servers` rule prefers Terraform-style flows over SSH writes. | Rejected. Defer until #2608's rotation-API plan is written. |

## Out of Scope (Deferred)

- **Per-host plugin rotation API** — tracked by #2608. This PR is the
  prerequisite (image-baked plugin); the rotation surface itself is
  out-of-scope here. Re-evaluate per #2608's existing criterion.
- **Plugin-version pinning per workspace** — not requested by #3045.
  All workspaces continue to symlink to a single shared path.
- **Cleaning up legacy stale `/mnt/data/plugins/soleur` content on
  existing prod hosts** — `docker cp` overwrites in place; explicit
  cleanup is unnecessary. Re-seed is idempotent.

## Why this is filed separately from #3033

Per `wg-when-an-audit-identifies-pre-existing` — pre-existing issues
identified during investigation get tracked, not folded into the current
PR. The #3033 fix is scoped to the `apps` mount (Layer 3 canary script
visibility); the `plugins` mount is a separate (and possibly older)
configuration drift. Both share `ci-deploy.sh` and may textually
conflict at merge — see Sharp Edges.
