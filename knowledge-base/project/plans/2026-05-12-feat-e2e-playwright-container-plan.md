---
plan_type: feat
classification: infrastructure
lane: single-domain
branch: feat-one-shot-e2e-playwright-container
requires_cpo_signoff: false
created: 2026-05-12
target_user_brand_impact_threshold: none
---

# feat: Run the `e2e` job in `ci.yml` inside the official Playwright container image

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
| Container does NOT ship bun | `docker run ... which bun` → not found. | Keep the `oven-sh/setup-bun@3d267786...` step verbatim. The action is a binary-download + PATH-setup; container-as-root makes it easier, not harder. |
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

      - name: Setup Bun
        # The Playwright container does NOT ship bun. setup-bun is a
        # binary-download + PATH-setup action; container-as-root makes
        # it easier, not harder (no sudo gymnastics).
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
2. Delete the `Setup Node.js` step (now redundant).
3. Delete the `Cache Playwright browsers` step.
4. Delete both `Install Playwright …` steps.
5. Keep all other steps byte-identical.

Run as a single commit; no intermediate state is shippable (the cache step's `id` is referenced by the install steps' `if:` conditions).

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

2. **`bun install` inside the container.** The Playwright Jammy image's userland is Ubuntu 22.04 + Node 24 + bash. `oven-sh/setup-bun@3d267786...` downloads the `bun` binary into a runner-owned path and prepends it to `PATH`. Container-as-root makes this easier (no sudo for PATH writes). PR #3654 already proved `oven-sh/setup-bun` works inside `mcr.microsoft.com/playwright:v1.60.0-jammy` (`critical-css-gate` uses `npm` not `bun`, but the action's mechanism is identical — binary download + PATH setup). If `setup-bun` fails on the v1.58.2 image specifically, revert the container migration on the `e2e` job and file a follow-up.

3. **Test-results artifact upload from inside the container.** `actions/upload-artifact@ea165f8d...` (v4.6.2) runs against `/__w/_temp` and `apps/web-platform/test-results/` via runner-mounted paths. PR #3654's plan documents that GHA action paths work inside containers (the runner mounts `/__w` into the container). The `playwright test` step writes to `apps/web-platform/test-results/` which is inside the checked-out repo, so the upload step sees the artifacts via the same mount. If artifact upload silently no-ops, the only symptom is missing artifacts on a real test failure — the gate itself still reports red, so the operator notices.

4. **Future Playwright version bumps require lockstep edits.** Tag (`v1.58.2-jammy`), digest (`sha256:4698...565`), and `apps/web-platform/package-lock.json`'s `"playwright": "1.58.2"` pin must move together. A bump touches three locations across two files; a partial bump silently drifts the npm package off the container's Chromium revision (exact-revision lookup → bin-not-found). Sharp Edge below names the grep that catches this.

5. **Container image deprecation.** Microsoft's Playwright image follows the upstream Playwright version. If `v1.58.2-jammy` becomes unavailable from `mcr.microsoft.com` (deprecation policy on old versions), the digest-pinned manifest still works as long as Microsoft keeps the manifest layers retained. Mitigation is to bump the web-platform Playwright version (out of scope for this PR); rollback is to revert this PR and run `actions/cache` + dual-install again until the bump lands.

6. **The container's Chromium revision and the lockfile's playwright pin can theoretically drift inside a single Microsoft image tag.** In practice, Microsoft tags `v<X.Y.Z>-jammy` with the matching Chromium for that Playwright version — `v1.58.2-jammy` ships Chromium 1208 (verified at plan-time: `/ms-playwright/chromium-1208/`). The digest pin is what hard-locks this. Re-resolving the tag is what would drift; the AC's digest grep is what prevents that.

## Sharp Edges

- The Playwright version (`1.58.2`) MUST appear in lockstep across THREE places: `apps/web-platform/package-lock.json` (`"playwright": "1.58.2"`), `.github/workflows/ci.yml` `e2e` block (image tag `v1.58.2-jammy`), and `.github/workflows/ci.yml` `e2e` block image digest. The plan's AC1 grep enforces the version match between the lockfile and the tag. Future PRs that bump the web-platform Playwright pin MUST also bump the container tag + digest. Without this lockstep, the npm package and the container's pre-installed Chromium drift off each other and Playwright's exact-revision browser-binary lookup fails with `Executable doesn't exist at /ms-playwright/chromium-<old-rev>/chrome-linux/chrome` — see `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`.

- The `e2e` job IS in the required_status_checks ruleset (`14145388`). DO NOT rename the job key. The Phase 2 edit keeps `e2e:` byte-identical. A future refactor that renames the job (e.g., `e2e-web-platform`, `web-platform-e2e`) MUST also update the ruleset via `gh api 'repos/jikig-ai/soleur/rulesets/14145388' --method PATCH ...` in the same PR, or all PR merges will block until an operator updates the ruleset manually. This is documented here so the next planner does not blunder into a `wg-after-merging-a-pr-that-adds-or-modifies` rule violation.

- `awk` section-scoped greps for verifying e2e-only invariants must use the form `awk '/^  e2e:/{f=1} f && /^  [a-z][a-z-]*:$/ && !/^  e2e:/{f=0} f' ci.yml`. The simpler `awk '/^  e2e:/,0'` form (from PR #3654 session error #2) is whole-file from `e2e` onward and matches every later job — `critical-css-gate` still contains all three forbidden patterns inside its existing `# Pre-merge variant of the deploy-docs critical-CSS gate.` comment block (none of them, actually — but the AC must be section-bounded to be load-bearing). The form here uses an explicit close-on-next-job pattern (`/^  [a-z][a-z-]*:$/ && !/^  e2e:/`).

- The current bare-runner job uses `actions/cache@5a3ec84eff668545956fd18022155c47e93e2684` (v4.2.3). The cache step is deleted whole; do NOT leave a commented-out remnant or a fallback `if:`-gated re-add. The whole point of PR #3654's structural fix is that the container OWNS the binary, not the cache. Mixing the two is a regression.

- When future maintainers bump the Playwright version, they should grep BOTH workflow files (`.github/workflows/ci.yml` AND `.github/workflows/deploy-docs.yml`) and BOTH version pins (the bare `v<X>-jammy` tag and the SHA digest). The two gates are intentionally independent (`critical-css-gate` on 1.60.0 from root, `e2e` on 1.58.2 from web-platform); a future "harmonize the versions" PR should bump web-platform's Playwright pin first (running the e2e suite against the new version), THEN this gate's container tag + digest, as a separate PR.

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none` with rationale.

- **`docker buildx imagetools inspect` reports a different digest than `docker manifest inspect`.** The first returns the multi-arch manifest-list digest (what we want for `container.image:`); the second can return a single-arch digest if your local Docker daemon's architecture is unique. Always use `buildx imagetools inspect` for the `container.image:` pin so amd64 and arm64 runners both resolve correctly.

## Test Strategy

This is a CI infrastructure change, so the "test" is the CI pipeline running green at the new wall-clock. No new unit tests, no new e2e tests — the existing `apps/web-platform/e2e/` suite continues to run, and its pass/fail signal IS the test for this PR.

**Pre-push local verification:**

1. Run all AC1–AC11 greps locally against the worktree's `.github/workflows/ci.yml`. All must pass.
2. `docker manifest inspect mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565` exits 0.
3. (Optional but cheap) Run the e2e suite locally inside the container:
   ```bash
   docker run --rm -v "$(pwd):/repo" -w /repo \
     mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565 \
     bash -c 'curl -fsSL https://bun.sh/install | bash && export PATH="$HOME/.bun/bin:$PATH" && bun install --frozen-lockfile && cd apps/web-platform && bun install --frozen-lockfile && npx playwright test --reporter=line'
   ```
   This exercises the exact in-container shape the workflow will run. If it passes locally, the workflow will pass on GHA.

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
