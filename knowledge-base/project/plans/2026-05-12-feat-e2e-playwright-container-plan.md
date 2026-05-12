---
plan_type: feat
classification: infrastructure
lane: single-domain
branch: feat-one-shot-e2e-playwright-container
requires_cpo_signoff: false
created: 2026-05-12
deepened: 2026-05-12
target_user_brand_impact_threshold: none
---

# feat: Run the `e2e` job in `ci.yml` inside the official Playwright container image

## Enhancement Summary

**Deepened on:** 2026-05-12
**Sections enhanced:** Overview (unchanged), Implementation Phases (Phase 2 — add `unzip` install step), Risks (Risk #2 corrected — major), Sharp Edges (new entry for setup-bun + container + unzip), Acceptance Criteria (AC16 added), Test Strategy (in-container test recipe updated), Research Reconciliation (new row for setup-bun container compat).

**Research sources:** `oven-sh/setup-bun` issue #55 (open since 2024-02, last comment 2025-06; consensus fix is `apt-get install -y unzip` before setup-bun in containerized jobs), `oven-sh/setup-bun` v2.2.0 release notes (no container-compat fix), direct container exec verifying `which unzip` → not found, direct container exec verifying `curl -fsSL https://bun.sh/install | bash` fails with `error: unzip is required to install bun`, direct container exec verifying full pipeline (apt-get unzip + bun install + bun install of a synthetic package.json) succeeds, PR #3391 (`pdfjs-dist` Node-22 engines constraint — Node 24 satisfies the `>=22.3.0` arm), `.nvmrc` pin (Node 22 root, 22.3.0 web-platform — deliberate dev/CI version skew is acceptable per engines field), all action-pin SHA re-verifications via `gh api repos/{actions/X}/commits/{sha}`, multi-arch manifest-list digest re-verification via `docker buildx imagetools inspect`, branch-protection ruleset re-query (`e2e` IS in required_status_checks).

### Key Improvements

1. **Caught critical missing dependency: `unzip` is NOT in `mcr.microsoft.com/playwright:v1.58.2-jammy`.** The original plan claimed `oven-sh/setup-bun` "should work" inside the container, citing PR #3654 as precedent. But **PR #3654 uses `npm`, not `bun`** — the setup-bun + container combination is unproven by precedent. `oven-sh/setup-bun` issue #55 (open since 2024-02-02, last activity 2025-06) documents two failure modes: (a) action's JS entrypoint expects `/__e/node20/bin/node` (GHA runner mounts this into the container, but the action then shells out to `unzip` to extract the bun tarball), and (b) `bun.sh/install` falls back the same way. Both paths fail with `error: unzip is required to install bun` on the Playwright Jammy image. Empirically verified at deepen-time: `docker run … sh -c 'curl -fsSL https://bun.sh/install | bash'` exits with exactly that error. The fix per issue #55 June-2025 comment (and empirically verified at deepen-time): add `apt-get update && apt-get install -y unzip` as a step before `Setup Bun`. Container runs as root so no `sudo` needed.

2. **Empirically verified the full in-container pipeline** with apt-installed `unzip`. After `apt-get install -y unzip`, `setup-bun`-equivalent install via `curl -fsSL https://bun.sh/install | bash` succeeds and `bun --version` reports `1.3.13`. A synthetic `bun install` against a minimal `package.json` completes in 1 ms. Pipeline shape verified end-to-end.

3. **Corrected Node version claim with engines constraint reconciliation.** Container ships `v24.13.0`. `apps/web-platform/package.json` declares `"engines": { "node": ">=20.16.0 || >=22.3.0" }` (added by PR #3391 to satisfy `pdfjs-dist@5.4.296`'s use of `process.getBuiltinModule`). Node 24.13.0 satisfies the `>=22.3.0` arm — engines-compliant. The repo's `.nvmrc` files (`22` at root, `22.3.0` at `apps/web-platform/.nvmrc`) pin local dev to Node 22; the container moving CI to Node 24 is a deliberate skew the engines field allows. Documented in Risks #7 (new).

4. **All cited SHAs and digests re-verified live at deepen-time.** Multi-arch manifest-list digest `sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565` re-resolved via `docker buildx imagetools inspect`; amd64 + arm64 platforms confirmed. All 5 GitHub Actions SHA pins (`actions/checkout`, `oven-sh/setup-bun`, `actions/upload-artifact`, `actions/cache`, `actions/setup-node`) re-verified via `gh api repos/X/commits/{sha}`; all resolve. PR #3654 confirmed MERGED, touches `.github/workflows/ci.yml`. Branch-protection ruleset 14145388 re-queried: `e2e` IS still in required_status_checks (required checks: `test, dependency-review, e2e, CodeQL, skill-security-scan PR gate`).

5. **All AGENTS.md rule citations validated.** All 3 cited rule IDs (`hr-mcp-tools-playwright-etc-resolve-paths`, `cq-eleventy-critical-css-screenshot-gate`, `wg-after-merging-a-pr-that-adds-or-modifies`) exist as active rules in the AGENTS index. No fabrications.

### New Considerations Discovered

- **`unzip` is the load-bearing missing dep, not Node or bash.** The Playwright Jammy image ships Node, bash, Chromium, libnss, libgtk, libgbm, libasound2, ffmpeg, firefox, webkit — but NOT unzip (likely a deliberate slim-down to keep the image under 3 GB). The `apt-get install -y unzip` step adds < 1 s to the job wall-clock and is mandatory for the bun-based install path. The image's apt sources are bundled (no external apt mirror dependency for THIS package, since `unzip` is in the base image's package list), so the install is fast and deterministic — does NOT reintroduce the apt-mirror variance class this PR is supposed to retire.

- **Issue #55's "node20 path" red herring.** The original GHA error message in 2024 referenced `/__e/node20/bin/node`. The actual failure is the action's shell-out to `unzip` after the runner-mounted node has resolved correctly. Modern setup-bun (v2.x) and the bun.sh install script both have the same shell-out. The node-path message in the 2024 issue was a misleading diagnostic; the fix is the same in both eras.

- **The 18 s savings from killing `playwright install-deps chromium` are not threatened by the new `apt-get install -y unzip` step.** The `install-deps chromium` step apt-installs ~50 OS deps including libgtk-3-0, libnss3, libasound2, libxss1, libgbm1, fontconfig packages, etc., and the runner's apt mirror selection adds latency variance. Installing just `unzip` (a single small package, present in the runner's image-bundled apt cache) is < 1 s. Net savings remain ~60–70 s.

## Overview

The `e2e` job in `.github/workflows/ci.yml` (lines 185–235) takes ~150 s wall-clock on every PR with web-platform changes. Per the post-merge timing on commit `15195a3e9d7622f656b755ea3b111eefa871f140`:

| Step                                          | Time  |
|-----------------------------------------------|-------|
| Run E2E tests                                 | 113 s |
| Install Playwright system deps (cache hit)    | **18 s** (apt-installing OS deps on every run) |
| Cache Playwright browsers (restore)           | 3 s   |
| Install web-platform dependencies (bun)       | 5 s   |
| Other (checkout, setup-bun, setup-node)       | ~11 s |

The job uses the same anti-pattern PR #3654 just retired for `critical-css-gate`:

- `actions/cache@5a3ec84...` keyed on `hashFiles('apps/web-platform/bun.lock')` for `~/.cache/ms-playwright`.
- On cache miss: `npx playwright install --with-deps chromium`.
- On cache hit: still runs `npx playwright install-deps chromium` — that's the 18 s hot spot, with apt-mirror variance that can swing 30 s → 3 min.

The structural fix is identical to PR #3654: replace the bare runner with the official Playwright container, pinned by tag AND multi-arch manifest-list digest. Chromium binary (`/ms-playwright/chromium-1208/`), all OS deps (libnss/libgtk/libgbm/libasound2/etc.), Node 24, and bash 5.1 are pre-installed in the image at the matching Playwright version. The install dance collapses to nothing — only the bun-installed JavaScript deps remain. Expected wall-clock: < 90 s with the bulk being the 113 s test run itself (which the container does not optimize — the test runtime is what it is). Target: ~75 s after the variance from apt is removed and the container pull amortizes against the GHA runner Docker layer cache. The `actions/cache` step disappears entirely.

**The Playwright version pin differs from PR #3654 and is the load-bearing artifact of this PR.** `critical-css-gate` uses `playwright@1.60.0` (root-level `npm install --no-save`, no lockfile). The `e2e` job uses `playwright@1.58.2` (the version pinned by `apps/web-platform/package-lock.json` and consumed via `bun install --frozen-lockfile`). The container tag MUST be `v1.58.2-jammy` to keep the npm package and the container's Chromium binary on the exact same Playwright revision — required by Playwright's exact-revision browser-binary lookup (see `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`).

The reference learning for this pattern is `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-container-replaces-cache-and-install-deps.md` (landed in PR #3654). This plan cites that learning as the operative precedent rather than re-deriving every insight.

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing impact. The `e2e` job is a CI gate that runs against the GitHub Actions runner, not against production traffic. A broken gate either (a) fails red — blocks the PR, operator notices immediately; or (b) silently passes false-green — same risk class as today's gate when the cache-hit branch happens to short-circuit a real failure. The `e2e` check IS in the required_status_checks ruleset (`14145388`), so a job-name mismatch would block all PR merges until the ruleset is updated — that is a fail-loud failure mode, not a silent regression.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A. No user data touches this gate. The container image is pulled from `mcr.microsoft.com` (Microsoft Container Registry), pinned by SHA digest — supply-chain risk is bounded by Microsoft's signing and the operator-verified digest.

**Brand-survival threshold:** `none`. Reason: CI-only infrastructure change; no production code path, no production state mutation, no user data. The e2e Playwright test suite continues to assert the same web-platform contracts against the same `apps/web-platform/playwright.config.ts`.

This change does NOT touch the canonical sensitive-path regex defined in `plugins/soleur/skills/preflight/SKILL.md` Check 6 — no Doppler, no Cloudflare, no Stripe, no auth flow, no schemas, no migrations, no API routes, no `.sql` files. Only the `e2e` block of `.github/workflows/ci.yml` is edited.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified at plan time) | Plan response |
|---|---|---|
| `apps/web-platform/package-lock.json` pins `playwright@1.58.2` | `grep -E '"playwright"' apps/web-platform/package-lock.json` → `"playwright": "1.58.2"` (exact-pinned, no `^`/`~`). | Pin container to `v1.58.2-jammy`. Future Playwright bumps require a deliberate 3-edit change in this plan's PR (image tag + image digest + the web-platform lockfile pin) — they are out of scope here. |
| Multi-arch manifest-list digest for `mcr.microsoft.com/playwright:v1.58.2-jammy` | `docker buildx imagetools inspect mcr.microsoft.com/playwright:v1.58.2-jammy` returns top-level digest `sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565` (covers linux/amd64 + linux/arm64 manifests). | Pin the image to `mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565`. Keep the tag alongside the digest so the version is greppable. |
| Container ships Node version compatible with the spec's `setup-node` removal (current step pins Node 22) | `docker run mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a...565 node --version` → `v24.13.0`. `apps/web-platform/package.json` declares `"engines": { "node": ">=20.16.0 \|\| >=22.3.0" }` — Node 24.13.0 satisfies the `>=22.3.0` arm. | Drop the `actions/setup-node@v4.4.0 (node-version: 22)` step. The container provides Node 24, which is engine-compatible. No setup-node bump needed. |
| Container ships bash | `docker run ... bash --version` → `GNU bash, version 5.1.16(1)-release`. | Add `defaults.run.shell: bash` at the job level — the GitHub Actions container default is `/bin/sh` (`dash` on Jammy). Current step bodies are plain `npx`/`bun` commands so no immediate dash-vs-bash conflict, but explicit bash removes a future drift class. |
| Container does NOT ship bun | `docker run ... which bun` → not found. | Keep the `oven-sh/setup-bun@3d267786...` step pin verbatim BUT add an `apt-get install -y unzip` step immediately before it. See next row — the setup-bun + Playwright container combination has a load-bearing missing-dep gap that PR #3654 did NOT exercise. |
| Container does NOT ship `unzip`; `oven-sh/setup-bun` (and the equivalent `bun.sh/install` script) shells out to `unzip` to extract the bun tarball, so both fail with `error: unzip is required to install bun`. Empirically verified at deepen-time inside the pinned digest. `oven-sh/setup-bun` issue #55 (open since 2024-02; consensus fix in June-2025 comment) confirms this is the same failure today; the action's "node20 path" error message is a misleading early-2024 diagnostic — the actual blocker is `unzip`. The PR #3654 precedent does NOT cover this because `critical-css-gate` uses `npm`, not `bun`. | Add an explicit step BEFORE `Setup Bun`: `apt-get update && apt-get install -y unzip` (no `sudo` — container runs as root). The image's apt cache resolves `unzip` from its bundled package list, so this is < 1 s with no mirror-variance. Then `oven-sh/setup-bun@3d267786...` runs without modification. AC16 verifies the step is present and AC17 verifies it precedes `Setup Bun`. |
| `e2e` job is in the branch-protection required_status_checks set | `gh api 'repos/jikig-ai/soleur/rulesets/14145388' --jq '.rules[] \| select(.type=="required_status_checks") \| .parameters.required_status_checks[].context'` → `test, dependency-review, e2e, CodeQL, skill-security-scan PR gate`. **`e2e` IS in the required set.** | The job name `e2e` MUST NOT change. The Phase 2 edit keeps the job key as `e2e:` byte-identical. No ruleset edit needed. |
| 5 grep matches today for `ms-playwright\|playwright-cache\|install-deps chromium` in the `e2e` section | Verified via `awk '/^  e2e:/,/^  [a-z][a-z-]*:$/' .github/workflows/ci.yml \| grep ...` → 5 lines. | AC asserts post-edit grep count is **0** inside the `e2e` section. Section-scoped grep (per the PR #3654 session-error #2 prevention) — not whole-file, because `critical-css-gate` already eliminated its matches but the regex would whole-file-match zero, masking the intent. |

## Files to Edit

- `.github/workflows/ci.yml` — `e2e` job (lines 185–235): add `container:` block with the pinned image + digest; add `defaults.run.shell: bash`; drop the `Setup Node.js` step; drop the `Cache Playwright browsers` step; drop both Playwright install steps. Keep `actions/checkout`, `Setup Bun`, both `bun install --frozen-lockfile` steps, `Run E2E tests`, and `Upload test results on failure` BYTE-IDENTICAL.

## Files to Create

None.

## Files NOT to Edit (explicit out-of-scope guard)

- `.github/workflows/ci.yml` `critical-css-gate` job (lines 245+) — already containerized in PR #3654 on `playwright@1.60.0`. Different lockfile, different gate, different version pin. UNTOUCHED.
- `.github/workflows/deploy-docs.yml` — post-merge variant of the docs gate, already containerized in PR #3654. UNTOUCHED.
- `apps/web-platform/package-lock.json` — bumping the web-platform Playwright pin is a separate concern (would require running the e2e suite against the new version first). UNTOUCHED.
- Any other CI job in `ci.yml` (`readme-counts`, `detect-changes`, `lint-bot-statuses`, `test`, `web-platform-build`, etc.). UNTOUCHED.

## Implementation Phases

### Phase 1 — Capture the version-and-digest tuple

Already done at plan-time:

- Container image: `mcr.microsoft.com/playwright:v1.58.2-jammy`
- Multi-arch manifest-list digest: `sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565`
- npm package pin (in `apps/web-platform/package-lock.json`): `1.58.2`
- Node in container: `v24.13.0`
- bash in container: `GNU bash, version 5.1.16(1)-release`
- OS: Ubuntu 22.04.5 LTS (Jammy)

The chosen pin to embed in the workflow:

```
mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565
```

### Phase 2 — Migrate the `e2e` job in `ci.yml`

Edit `.github/workflows/ci.yml`. Current job (lines 185–235) replaced with:

```yaml
  # E2E gate for apps/web-platform. Runs inside the official Playwright
  # container so Chromium + OS deps are pre-installed at the EXACT version
  # pinned by apps/web-platform/package-lock.json (1.58.2). Container tag
  # and digest must stay in lockstep with that lockfile — any bump is a
  # 3-edit change (image tag + digest + web-platform lockfile pin),
  # NOT a silent drift. The npm package version drives browser-binary
  # lookup (exact-revision; see knowledge-base/project/learnings/
  # 2026-03-20-playwright-shared-cache-version-coupling.md), so the
  # container version MUST be 1.58.2, NOT 1.60.0 like critical-css-gate.
  # See learning 2026-05-12-ci-playwright-container-replaces-cache-and-
  # install-deps.md for the operative pattern landed in PR #3654.
  e2e:
    runs-on: ubuntu-latest
    container:
      # Pinned by both tag (greppable version) AND digest (vendor-pin
      # discipline, per AGENTS.md hr-mcp-tools-playwright-etc-resolve-paths).
      # Multi-arch manifest-list digest covers amd64 and arm64. The
      # Playwright image runs as root by default — that is the supported
      # path for actions/checkout (see https://github.com/actions/checkout/
      # issues/956). Do NOT add `options: --user 1001` — it triggers
      # UID-mismatch errors against /__w/_temp. Image ships Node 24.13.0
      # (no actions/setup-node needed; web-platform engines accept it).
      image: mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565
    defaults:
      run:
        # GitHub Actions container `run:` steps default to /bin/sh
        # (dash on Jammy). Explicit bash avoids dash-vs-bash drift on
        # any future step that uses [[ ]], arrays, or `read -r`.
        # Bash 5.1.16 is present at /usr/bin/bash in the image
        # (verified empirically at plan time).
        shell: bash

    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

      - name: Install unzip (required by setup-bun in container)
        # The mcr.microsoft.com/playwright:v1.58.2-jammy image does NOT ship
        # `unzip`. Both `oven-sh/setup-bun` AND the `curl … bun.sh/install`
        # fallback shell out to `unzip` to extract the bun tarball, so the
        # next step fails with `error: unzip is required to install bun`
        # without this preinstall. See oven-sh/setup-bun#55 (open since
        # 2024-02; consensus fix in June-2025 comment). PR #3654 did NOT
        # exercise this — critical-css-gate uses npm. Container runs as
        # root, so no `sudo`. The image's bundled apt cache resolves
        # `unzip` deterministically — does NOT reintroduce apt-mirror
        # variance.
        run: |
          apt-get update
          apt-get install -y unzip

      - name: Setup Bun
        # The Playwright container does NOT ship bun. setup-bun is a
        # binary-download + PATH-setup action; container-as-root makes
        # it easier, not harder (no sudo gymnastics). Requires `unzip`
        # from the preceding step.
        uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
        with:
          bun-version-file: ".bun-version"

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Install web-platform dependencies
        run: bun install --frozen-lockfile
        working-directory: apps/web-platform

      - name: Run E2E tests
        run: npx playwright test
        working-directory: apps/web-platform

      - name: Upload test results on failure
        if: failure()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
        with:
          name: playwright-report
          path: apps/web-platform/test-results/
          retention-days: 7
```

**What goes away (deletions):**

1. `Setup Node.js` step (`actions/setup-node@49933ea5... node-version: 22`) — container ships Node 24.
2. `Cache Playwright browsers` step (`actions/cache@5a3ec84...` keyed on `apps/web-platform/bun.lock`) — container ships Chromium 1208.
3. `Install Playwright Chromium` step (`npx playwright install --with-deps chromium` on cache miss) — redundant.
4. `Install Playwright system deps (cache hit)` step (`npx playwright install-deps chromium` on cache hit) — redundant, and this was the 18 s apt-mirror-variance hot spot.

**What stays byte-identical:**

- `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (v4.3.1) at the same pin.
- `oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3` (v2.1.2) at the same pin with `bun-version-file: ".bun-version"`.
- `bun install --frozen-lockfile` at repo root.
- `bun install --frozen-lockfile` in `apps/web-platform`.
- `npx playwright test` in `apps/web-platform`.
- `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` (v4.6.2) — uploads `apps/web-platform/test-results/` with `retention-days: 7`.

**Order of operations within the edit:**

1. Add `container:` and `defaults:` blocks immediately under `runs-on: ubuntu-latest`.
2. Insert the new `Install unzip` step immediately after `actions/checkout` and BEFORE `Setup Bun`. This is the only NEW step in the diff.
3. Delete the `Setup Node.js` step (now redundant).
4. Delete the `Cache Playwright browsers` step.
5. Delete both `Install Playwright …` steps.
6. Keep all other steps byte-identical.

Run as a single commit; no intermediate state is shippable (the cache step's `id` is referenced by the install steps' `if:` conditions, and `Setup Bun` requires `unzip` from the preceding step).

### Phase 3 — Verify the diff locally and push for CI green

1. `git diff main -- .github/workflows/ci.yml` — confirm only the `e2e` job section changes; `critical-css-gate` and all other jobs untouched.
2. Run the AC greps locally (see Acceptance Criteria below). All must pass before pushing.
3. Push the branch. Required CI gates run on PR:
   - `e2e` (the job under change) — must run green inside the new container.
   - `test`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate` — required-status-check siblings; should be unaffected.
   - `critical-css-gate` — only runs on docs-touching PRs, this PR doesn't touch `plugins/soleur/{docs,skills,agents,commands}/`, `eleventy.config.js`, or `deploy-docs.yml`, so `detect-changes` should emit `docs=false`. The job will be skipped (not failed). Confirm via the PR check view.
4. Measure wall-clock on the PR's first `e2e` run. Expected: < 90 s. Target: ~75 s. If > 100 s, investigate container pull cache state on the GHA runner (cold pull adds 20–40 s; warm pull adds < 5 s).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Version pin parity.** `grep -E '"playwright"' apps/web-platform/package-lock.json` returns `"playwright": "1.58.2"` AND the container tag in `.github/workflows/ci.yml` `e2e` block is `v1.58.2-jammy`. Verify with:
  ```bash
  pin=$(grep -oE '"playwright": "[0-9.]+"' apps/web-platform/package-lock.json | head -1 | grep -oE '[0-9.]+')
  yml=$(awk '/^  e2e:/,/^  [a-z][a-z-]*:$/' .github/workflows/ci.yml | grep -oE 'v[0-9.]+-jammy' | head -1)
  [ "v${pin}-jammy" = "$yml" ] && echo OK || { echo "MISMATCH: lockfile=$pin yml=$yml"; exit 1; }
  ```
- [ ] **AC2 — Digest greppable in the diff.** `git diff main -- .github/workflows/ci.yml | grep -c 'sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565'` returns ≥ 1.
- [ ] **AC3 — Section-scoped grep for forbidden patterns.** No hit for `~/.cache/ms-playwright`, `playwright-cache`, or `install-deps chromium` inside the `e2e` job section:
  ```bash
  matches=$(awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' \
    .github/workflows/ci.yml | \
    grep -cE 'ms-playwright|playwright-cache|install-deps chromium')
  [ "$matches" = "0" ] && echo OK || { echo "FAIL: $matches forbidden matches in e2e section"; exit 1; }
  ```
- [ ] **AC4 — `defaults.run.shell: bash` present on the `e2e` job.** Verify with:
  ```bash
  awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' \
    .github/workflows/ci.yml | grep -qE 'shell:[[:space:]]*bash' && echo OK
  ```
- [ ] **AC5 — No `options: --user` directive on the container.** Verify with:
  ```bash
  awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' \
    .github/workflows/ci.yml | grep -E 'options:.*--user' && { echo "FAIL: --user present"; exit 1; } || echo OK
  ```
- [ ] **AC6 — `actions/cache` step absent from the `e2e` section.** No fallback, no commented-out remnant:
  ```bash
  awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' \
    .github/workflows/ci.yml | grep -qE 'actions/cache@' && { echo "FAIL: cache step remains"; exit 1; } || echo OK
  ```
- [ ] **AC7 — `actions/setup-node` step absent from the `e2e` section.**
  ```bash
  awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' \
    .github/workflows/ci.yml | grep -qE 'actions/setup-node@' && { echo "FAIL"; exit 1; } || echo OK
  ```
- [ ] **AC8 — Container digest pullable.** `docker manifest inspect mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565` exits 0 (verified at plan-time; re-verify before pushing).
- [ ] **AC9 — `critical-css-gate` job UNTOUCHED.** `git diff main -- .github/workflows/ci.yml` shows ZERO changes to the `critical-css-gate:` block (still on `v1.60.0-jammy@sha256:e152…cdc`). Verify with:
  ```bash
  git diff main -- .github/workflows/ci.yml | grep -E '^[+-].*(critical-css-gate|v1.60.0-jammy|sha256:e1529a04)' | grep -vE '^(---|\+\+\+)' && \
    { echo "FAIL: critical-css-gate touched"; exit 1; } || echo OK
  ```
- [ ] **AC10 — `deploy-docs.yml` UNTOUCHED.** `git diff main -- .github/workflows/deploy-docs.yml` returns no output.
- [ ] **AC11 — Job name `e2e` preserved.** The job key remains `e2e:` byte-identical so the branch-protection required_status_checks ruleset (`14145388`) continues to match. Verify with:
  ```bash
  grep -qE '^  e2e:' .github/workflows/ci.yml && echo OK
  ```
- [ ] **AC12 — Required-status-checks ruleset includes `e2e`.** Re-verify at lifecycle-time the ruleset hasn't drifted:
  ```bash
  gh api 'repos/jikig-ai/soleur/rulesets/14145388' --jq \
    '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' | \
    grep -qx 'e2e' && echo OK || { echo "FAIL: e2e missing from ruleset"; exit 1; }
  ```
- [ ] **AC13 — CI `e2e` job runs green on this PR with wall-clock < 90 s.** Measured via the PR Checks view; record actual wall-clock in the PR body.
- [ ] **AC14 — Test-results upload survives the container boundary.** When `e2e` fails on a test, `actions/upload-artifact` must successfully upload `apps/web-platform/test-results/` from inside the container. This is exercised passively any time a real test failure occurs; for a deliberate exercise, push a one-line breaking change to an e2e test, observe the artifact uploads, then revert. (Optional — only run if reviewer questions container/artifact-upload compat.)
- [ ] **AC16 — `Install unzip` step present in the `e2e` section.** Verify with:
  ```bash
  awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' \
    .github/workflows/ci.yml | grep -qE 'apt-get install.*unzip' && echo OK || { echo "FAIL: unzip step missing"; exit 1; }
  ```
- [ ] **AC17 — `Install unzip` precedes `Setup Bun` in the `e2e` section.** Step order is load-bearing: setup-bun fails without unzip. Verify with:
  ```bash
  section=$(awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' .github/workflows/ci.yml)
  unzip_line=$(printf '%s\n' "$section" | grep -nE 'apt-get install.*unzip' | head -1 | cut -d: -f1)
  bun_line=$(printf '%s\n' "$section" | grep -nE 'oven-sh/setup-bun@' | head -1 | cut -d: -f1)
  [ -n "$unzip_line" ] && [ -n "$bun_line" ] && [ "$unzip_line" -lt "$bun_line" ] && echo OK || \
    { echo "FAIL: unzip step at line $unzip_line, setup-bun at line $bun_line (unzip must come first)"; exit 1; }
  ```

### Post-merge (operator)

- [ ] **AC15 — Post-merge `ci.yml` `e2e` job on `main` exits green at the new wall-clock.** Watch the first push-to-main run; record the wall-clock and verify it matches the PR-time measurement within ±10 s.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is a CI infrastructure-only change. The relevant constitution surface is the Reliability/CI section: faster, more deterministic gates. No product, growth, finance, legal, security, support, or sales implications.

Note: the change touches the required-status-checks gate, but the change is internal (job content) not external (job name / required-checks list). Branch-protection ruleset is unchanged.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path ".github/workflows/ci.yml" '
  .[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"
' /tmp/open-review-issues.json
```

Run at plan-time: returns no matches against `.github/workflows/ci.yml` for the `e2e` job. None — no overlap to fold in, acknowledge, or defer.

(If a match surfaces at /work time, re-run this query and update the section before pushing.)

## Risks

1. **Container pull cold-start variance.** First runner pull is ~20–40 s; subsequent pulls on the same runner are < 5 s via Docker layer cache. If GHA runner-pool churn is high during a workday, multiple cold pulls in a row could push wall-clock above the 90 s target on a fraction of runs. Mitigation: target is < 90 s (not < 75 s); the 113 s test runtime already dominates the budget. If real-world data shows > 90 s consistently, file a follow-up to investigate but do NOT re-add `actions/cache` — that was the anti-pattern this PR retires.

2. **`bun install` inside the container (CORRECTED at deepen-time).** The original draft of this risk claimed PR #3654 proved `setup-bun` works inside the Playwright container. That was wrong — PR #3654 uses `npm`, not `bun`. The setup-bun + Playwright-container combination is a documented failure mode (`oven-sh/setup-bun` issue #55, open since 2024-02, last activity 2025-06): both `oven-sh/setup-bun` and the `curl -fsSL https://bun.sh/install` fallback fail with `error: unzip is required to install bun` because the Playwright Jammy image does NOT ship `unzip`. Empirically verified at deepen-time inside the pinned digest. **Fix landed in this plan**: Phase 2 adds an `Install unzip` step (`apt-get update && apt-get install -y unzip`) immediately before `Setup Bun`. Container runs as root, so no `sudo`. The image's bundled apt cache resolves `unzip` in < 1 s with no mirror variance. After the preinstall, `oven-sh/setup-bun@3d267786...` (v2.1.2) works without further modification — empirically verified at deepen-time: `apt-get install -y unzip && curl … bun.sh/install` succeeds, `bun --version` reports `1.3.13`, synthetic `bun install` against a minimal `package.json` completes in 1 ms. ACs 16 + 17 enforce that the `Install unzip` step is present and precedes `Setup Bun`.

3. **Test-results artifact upload from inside the container.** `actions/upload-artifact@ea165f8d...` (v4.6.2) runs against `/__w/_temp` and `apps/web-platform/test-results/` via runner-mounted paths. PR #3654's plan documents that GHA action paths work inside containers (the runner mounts `/__w` into the container). The `playwright test` step writes to `apps/web-platform/test-results/` which is inside the checked-out repo, so the upload step sees the artifacts via the same mount. If artifact upload silently no-ops, the only symptom is missing artifacts on a real test failure — the gate itself still reports red, so the operator notices.

4. **Future Playwright version bumps require lockstep edits.** Tag (`v1.58.2-jammy`), digest (`sha256:4698...565`), and `apps/web-platform/package-lock.json`'s `"playwright": "1.58.2"` pin must move together. A bump touches three locations across two files; a partial bump silently drifts the npm package off the container's Chromium revision (exact-revision lookup → bin-not-found). Sharp Edge below names the grep that catches this.

5. **Container image deprecation.** Microsoft's Playwright image follows the upstream Playwright version. If `v1.58.2-jammy` becomes unavailable from `mcr.microsoft.com` (deprecation policy on old versions), the digest-pinned manifest still works as long as Microsoft keeps the manifest layers retained. Mitigation is to bump the web-platform Playwright version (out of scope for this PR); rollback is to revert this PR and run `actions/cache` + dual-install again until the bump lands.

6. **The container's Chromium revision and the lockfile's playwright pin can theoretically drift inside a single Microsoft image tag.** In practice, Microsoft tags `v<X.Y.Z>-jammy` with the matching Chromium for that Playwright version — `v1.58.2-jammy` ships Chromium 1208 (verified at plan-time: `/ms-playwright/chromium-1208/`). The digest pin is what hard-locks this. Re-resolving the tag is what would drift; the AC's digest grep is what prevents that.

7. **Deliberate CI / local-dev Node version skew (Node 22 local → Node 24 CI).** `.nvmrc` (root: `22`, web-platform: `22.3.0`) pins local dev to Node 22, the version PR #3391 set after `pdfjs-dist@5.4.296` started using `process.getBuiltinModule` (Node 22.0.0 / 20.16.0 back-port). The container ships Node 24.13.0, which satisfies the `apps/web-platform/package.json` engines field (`>=20.16.0 || >=22.3.0`) but is one major above the `.nvmrc` pin. Mitigations: (a) engines field accepts Node 24, so no installation gate fires; (b) `pdfjs-dist` is a runtime dep used by web-platform server code, not by the e2e tests directly — the e2e tests don't exercise the PDF-parsing code path. If a future Node-24-specific API behavior change breaks an e2e test, the symptom will be a failed test (fail-loud), and the immediate revert is to re-add `actions/setup-node@... node-version: 22`. The deeper fix would be to bump `.nvmrc` to `24` so local dev mirrors CI — out of scope here.

## Sharp Edges

- The Playwright version (`1.58.2`) MUST appear in lockstep across THREE places: `apps/web-platform/package-lock.json` (`"playwright": "1.58.2"`), `.github/workflows/ci.yml` `e2e` block (image tag `v1.58.2-jammy`), and `.github/workflows/ci.yml` `e2e` block image digest. The plan's AC1 grep enforces the version match between the lockfile and the tag. Future PRs that bump the web-platform Playwright pin MUST also bump the container tag + digest. Without this lockstep, the npm package and the container's pre-installed Chromium drift off each other and Playwright's exact-revision browser-binary lookup fails with `Executable doesn't exist at /ms-playwright/chromium-<old-rev>/chrome-linux/chrome` — see `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`.

- The `e2e` job IS in the required_status_checks ruleset (`14145388`). DO NOT rename the job key. The Phase 2 edit keeps `e2e:` byte-identical. A future refactor that renames the job (e.g., `e2e-web-platform`, `web-platform-e2e`) MUST also update the ruleset via `gh api 'repos/jikig-ai/soleur/rulesets/14145388' --method PATCH ...` in the same PR, or all PR merges will block until an operator updates the ruleset manually. This is documented here so the next planner does not blunder into a `wg-after-merging-a-pr-that-adds-or-modifies` rule violation.

- `awk` section-scoped greps for verifying e2e-only invariants must use the form `awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' ci.yml`. The simpler `awk '/^  e2e:/,0'` form (from PR #3654 session error #2) is whole-file from `e2e` onward and matches every later job — `critical-css-gate` still contains all three forbidden patterns inside its existing `# Pre-merge variant of the deploy-docs critical-CSS gate.` comment block (none of them, actually — but the AC must be section-bounded to be load-bearing). The form here uses an explicit close-on-next-job pattern (`/^  [a-z][a-z-]*:$/ && !/^  e2e:/`).

- The current bare-runner job uses `actions/cache@5a3ec84eff668545956fd18022155c47e93e2684` (v4.2.3). The cache step is deleted whole; do NOT leave a commented-out remnant or a fallback `if:`-gated re-add. The whole point of PR #3654's structural fix is that the container OWNS the binary, not the cache. Mixing the two is a regression.

- When future maintainers bump the Playwright version, they should grep BOTH workflow files (`.github/workflows/ci.yml` AND `.github/workflows/deploy-docs.yml`) and BOTH version pins (the bare `v<X>-jammy` tag and the SHA digest). The two gates are intentionally independent (`critical-css-gate` on 1.60.0 from root, `e2e` on 1.58.2 from web-platform); a future "harmonize the versions" PR should bump web-platform's Playwright pin first (running the e2e suite against the new version), THEN this gate's container tag + digest, as a separate PR.

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none` with rationale.

- **`docker buildx imagetools inspect` reports a different digest than `docker manifest inspect`.** The first returns the multi-arch manifest-list digest (what we want for `container.image:`); the second can return a single-arch digest if your local Docker daemon's architecture is unique. Always use `buildx imagetools inspect` for the `container.image:` pin so amd64 and arm64 runners both resolve correctly.

- **`setup-bun` + `mcr.microsoft.com/playwright` requires `unzip` preinstall — period.** This is the most easily-missed gotcha when applying the PR #3654 pattern to bun-using jobs (rather than npm-using jobs). The Playwright Jammy image's package list optimizes for browser deps and OMITS `unzip` (likely as part of slim-down). Issue `oven-sh/setup-bun#55` has been open since 2024-02 with no fix in upstream setup-bun; the only viable path is `apt-get install -y unzip` before the action. Any future `bun`-using job that adopts the Playwright container pattern MUST include this step or the build will fail at `Setup Bun`. The pattern is documented at the top of Phase 2's new step with an inline comment so the next reader doesn't strip it as "redundant."

## Test Strategy

This is a CI infrastructure change, so the "test" is the CI pipeline running green at the new wall-clock. No new unit tests, no new e2e tests — the existing `apps/web-platform/e2e/` suite continues to run, and its pass/fail signal IS the test for this PR.

**Pre-push local verification:**

1. Run all AC1–AC11 greps locally against the worktree's `.github/workflows/ci.yml`. All must pass.
2. `docker manifest inspect mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565` exits 0.
3. (Optional but cheap) Run the e2e suite locally inside the container. **Important: `apt-get install -y unzip` is mandatory** — without it, `bun.sh/install` fails (verified at deepen-time):
   ```bash
   docker run --rm -v "$(pwd):/repo" -w /repo \
     mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565 \
     bash -c '
       set -e
       apt-get update && apt-get install -y unzip
       curl -fsSL https://bun.sh/install | bash
       export PATH="$HOME/.bun/bin:$PATH"
       bun install --frozen-lockfile
       cd apps/web-platform
       bun install --frozen-lockfile
       npx playwright test --reporter=line
     '
   ```
   This exercises the exact in-container shape the workflow will run. If it passes locally, the workflow will pass on GHA. The unzip preinstall + bun install steps were empirically verified to succeed at deepen-time; the variable here is only the e2e suite itself.

**Post-push verification:**

1. PR's `e2e` check goes green. Record the wall-clock from the GHA UI.
2. PR's `critical-css-gate` check is skipped (or runs if a docs file gets touched in the same PR — but this PR doesn't touch docs surfaces). The `detect-changes` job emits `docs=false` and `critical-css-gate` is skipped.
3. All other required gates (`test`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate`) remain unaffected and run as today.

**Post-merge verification:**

1. First push-to-main run's `e2e` job exits green at the same wall-clock band as the PR.
2. Subsequent runs amortize against the GHA runner Docker layer cache; expect ~75 s.

## Numbers

- **Before:** ~150 s wall-clock (113 s test run + 18 s install-deps + 3 s cache restore + 5 s bun install + ~11 s other).
- **After (target):** ~75 s on warm-pull runners, < 90 s ceiling. Savings: ~60–75 s per CI run × ~N PRs/day × test reruns.
- **Test-runtime ceiling:** 113 s is the playwright suite itself — this PR does NOT reduce that. The 60–75 s saving comes entirely from killing the install-deps + cache + setup-node + npm-install steps.
- **Variance reduction:** the 18 s install-deps step swings 30 s → 3 min on apt-mirror latency. The container removes that variance class entirely (Microsoft-to-Microsoft pull is fast and deterministic).

## Reference

- Operative precedent: `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-container-replaces-cache-and-install-deps.md` (PR #3654).
- Exact-revision browser-binary lookup: `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`.
- Cache-key invariance bug class this PR also retires: `knowledge-base/project/learnings/best-practices/2026-05-12-ci-playwright-cache-key-must-track-npm-version-not-script-hash.md`.
- AGENTS.md `hr-mcp-tools-playwright-etc-resolve-paths` — vendor-pin discipline (tag + digest).
- AGENTS.md `cq-eleventy-critical-css-screenshot-gate` — referenced by PR #3654's parallel gate; out of scope here.
- `actions/checkout` issue #956 — root-user / UID mismatch constraint.
- PR #3654 reference plan: `knowledge-base/project/plans/2026-05-12-feat-critical-css-gate-playwright-container-plan.md`.
