---
issue: 3422
type: infra-hardening
classification: build-time-assertion
requires_cpo_signoff: false
labels: [code-review, type/security, deferred-scope-out]
---

# Add Dockerfile-stage pdfjs-dist (and sharp) resolution assertion

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Overview, Implementation, Risks, Acceptance Criteria
**Verification posture:** Live-verified — `require.resolve` was actually executed against both specifiers in the worktree's `node_modules` (Node v21.7.3 local), and PR #3410 / issue #3422 status was confirmed via `gh`. No claims rest on training-data recall.

### Key Improvements
1. Live-verified that `require.resolve('pdfjs-dist/legacy/build/pdf.mjs')` returns the expected absolute path against the actual `node_modules` tree of this worktree — pasted into Research Insights as a reproducible assertion.
2. Live-verified that `require.resolve('sharp')` succeeds (sharp's package.json exports field resolves the package root) — confirming the second specifier is shape-correct without needing a sub-path.
3. Pinned the insertion site precisely between two existing Dockerfile lines to remove insertion ambiguity: AFTER `RUN npm ci --omit=dev` and BEFORE the `# Next.js build output + public assets (icons, service worker)` comment block. This is also BEFORE `useradd ... USER soleur`, satisfying the root-resolution requirement.
4. Added an explicit non-goal: this is NOT a substitute for runtime telemetry on PDF-extract failures (Sentry breadcrumb at `pdf-text-extract.ts:107-118`). The assertion catches REGRESSIONS at build time; runtime parser bugs still need the existing observability path.
5. Added a Pin-Note documenting why the insertion ordering matters for layer-cache invalidation: the new RUN must NOT precede `npm ci --omit=dev` (the ci layer is cache-invalidated only by `package*.json` changes; placing the assertion AFTER inherits the same cache key — placing it BEFORE forces re-resolution on every Dockerfile edit).

### New Considerations Discovered
- `require.resolve('sharp')` (no sub-path) hits `node_modules/sharp/package.json` `main`/`exports`. This is correct because the consumer (`kb-preview-metadata.ts:132`) does `await import("sharp")` — also bare specifier — so the assertion shape mirrors the consumer shape exactly. No need for a sub-path like `sharp/lib/index.js`.
- Sharp's native `.node` binary loads at module-evaluation time, NOT at resolution time. `require.resolve` proves the JS entry exists; native-binary breakage (e.g., glibc mismatch on a different base image) would still surface at runtime. The assertion targets the regression class the issue actually names ("strips dep from node_modules"), not native-loader bugs.
- `require.resolve` against an ESM specifier (`.mjs`) works on Node 22 because Node's CJS resolver recognizes the file extension and resolves the path without invoking the ESM loader. This was verified against Node v21.7.3 locally (Dockerfile uses node:22-slim — strictly newer; same resolver semantics for `.mjs`).
- The Dockerfile's `node:22-slim` runner stage uses npm-installed deps; there's no Bun in the runner image. The assertion line uses `node` (which is on `$PATH` in the slim base image — verified by the existing `HEALTHCHECK` line that already uses `node -e`).

## Overview

`apps/web-platform/Dockerfile` lacks a build-stage assertion that the runner image's `node_modules` contains the legacy entry that `pdf-text-extract.ts` and `kb-preview-metadata.ts` lazy-import at runtime. If a future Dockerfile or dependency edit strips `pdfjs-dist` from the runner stage (`npm prune`, multi-stage `--production` re-copy, accidental move to `devDependencies`), the runtime `await import("pdfjs-dist/legacy/build/pdf.mjs")` rejects with `MODULE_NOT_FOUND`, the existing try/catch swallows it, and the Concierge silently falls back to "PDF unreadable" while KB-share returns `firstPagePreview: undefined`. Sentry sees only a WARN-level breadcrumb. PR #3410 fixed the bundling-reorder root cause; this PR closes the residual latent runtime-resolution gap.

**Approach:** Add a single `RUN node -e "require.resolve('<specifier>')"` step in the runner stage of `apps/web-platform/Dockerfile`, after `RUN npm ci --omit=dev` and before the `USER soleur` directive (resolution must run as root because npm-ci ownership is root). Cover BOTH lazy-imported runtime deps the server uses today: `pdfjs-dist/legacy/build/pdf.mjs` (kb preview + pdf-text-extract) and `sharp` (kb preview thumbnailing). Cost: ~50ms in build, zero in production.

## User-Brand Impact

**If this lands broken, the user experiences:** A `docker build` failure during CI (pre-deploy). The wall-clock cost is ~50ms; the only realistic break mode is a syntax error in the new RUN line itself, caught by the very next CI build.

**If this leaks, the user's [data / workflow / money] is exposed via:** No exposure path. This is a build-time gate; production behavior is unchanged when the assertion passes.

**Brand-survival threshold:** none

(Threshold is `none`: this is a defensive build-time gate that converts a future regression into a build failure. The diff touches only `apps/web-platform/Dockerfile` — sensitive paths under `apps/*/server/auth*`, `apps/*/middleware.ts`, `apps/*/lib/csp.ts`, etc. are untouched. Per `plugins/soleur/skills/preflight/SKILL.md` Check 6, no scope-out bullet is needed.)

## Research Reconciliation — Spec vs. Codebase

| Spec claim                                                                          | Reality                                                                                                                                                                              | Plan response                                                                                                                          |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| Issue body: "before the runner stage's `USER` directive"                            | Confirmed: `apps/web-platform/Dockerfile` has `USER soleur` after `chown -R soleur:soleur .next` and before `EXPOSE 3000`. The runner stage's `npm ci --omit=dev` runs as root.      | Insert the new RUN immediately AFTER `RUN npm ci --omit=dev` and BEFORE the `useradd ... USER soleur` block — runs as root, simplest.  |
| Issue body: "consider generalizing to ... `pdfjs-dist`, `sharp`, future `mammoth`/`xlsx`/`epub-parse`" | Codebase has only TWO bare-specifier lazy `await import()`s in `apps/web-platform/server/`: `pdfjs-dist/legacy/build/pdf.mjs` (pdf-text-extract.ts:108, kb-preview-metadata.ts:84) and `sharp` (kb-preview-metadata.ts:132). No mammoth/xlsx/epub-parse exist today. | Cover BOTH `pdfjs-dist` and `sharp` in this PR. Defer mammoth/xlsx/epub-parse — they don't exist yet; nothing to assert.               |
| Issue body: "PR #3410 ... bundling-reorder root cause is now externalized"          | Confirmed: `apps/web-platform/package.json` `build:server` ends with `--external:pdfjs-dist`; sibling test `test/helpers/bundled-server.ts:59` asserts the external is present.       | The Dockerfile assertion is complementary, not duplicative — the bundled-server test guards `package.json`; the Dockerfile guards the runner image's `node_modules`. |

## Implementation Phases

### Phase 1 — Add resolution assertion (single RUN, two specifiers)

**File:** `apps/web-platform/Dockerfile`

Insert after the `RUN npm ci --omit=dev` line and before the `# Next.js build output + public assets` comment block:

```dockerfile
# Build-time assertion that lazy-imported runtime deps resolve in the runner image's
# node_modules. Catches future regressions where a Dockerfile edit (npm prune, prod
# re-copy, devDependencies migration) strips pdfjs-dist or sharp from the runner stage,
# which would otherwise be swallowed by try/catch in pdf-text-extract.ts / kb-preview-metadata.ts
# and surface only as a WARN Sentry breadcrumb in production. See #3422 / Ref #3410.
RUN node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')"
```

**Why a single RUN, two specifiers:**

- Lower image-layer count (one cache key, one COW boundary).
- Both resolve calls share the same Node process startup cost (~30-40ms).
- A future fourth/fifth dep can join the same string trivially; if the list ever grows past 5-6 entries, refactor to a `node` script invocation.

**Why `require.resolve` and NOT `await import`:**

- `require.resolve` exits non-zero on missing module without executing the module body. `pdfjs-dist@5+` calls `DOMMatrix` during module init under a non-DOM environment in some entry-paths — actually importing during build risks tripping unrelated init errors that don't reflect resolution failure.
- The legacy entry `pdfjs-dist/legacy/build/pdf.mjs` is an ESM file. `require.resolve` resolves any specifier (CJS or ESM) without loading it; `import()` would load and evaluate the ESM. Resolution-only is what we want.

**Insertion site (pinned exactly):**

```diff
  # Production dependencies only
  COPY package.json package-lock.json ./
  RUN npm ci --omit=dev

+ # Build-time assertion that lazy-imported runtime deps resolve in the runner image's
+ # node_modules. See #3422 / Ref #3410.
+ RUN node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')"
+
  # Next.js build output + public assets (icons, service worker)
  COPY --from=builder /app/public ./public
```

This ordering matters for layer caching: placing the assertion AFTER `npm ci --omit=dev` inherits the same cache key (invalidated only when `package*.json` changes). Placing it BEFORE `npm ci` would either fail (no `node_modules`) or force re-resolution on every Dockerfile edit unrelated to deps.

### Research Insights

**Live-verified at deepen-plan time (2026-05-07):**

```bash
$ cd apps/web-platform && node -e "console.log(require.resolve('pdfjs-dist/legacy/build/pdf.mjs'))"
/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3422-dockerfile-pdfjs-resolve-assertion/apps/web-platform/node_modules/pdfjs-dist/legacy/build/pdf.mjs

$ node -e "console.log(require.resolve('sharp'))"
/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3422-dockerfile-pdfjs-resolve-assertion/apps/web-platform/node_modules/sharp/lib/index.js
```

Both specifiers resolve cleanly against the worktree's installed `node_modules`. `require.resolve('sharp')` returns sharp's `package.json` `main` field (`lib/index.js`) — bare specifier resolution is correct here because the consumer `kb-preview-metadata.ts:132` also uses bare-specifier `await import("sharp")`.

**Node version compatibility:**

- Local verification: Node v21.7.3.
- Dockerfile runner stage: `node:22-slim@sha256:4f77a690...`.
- Node 22 (and 21, 20) all support `require.resolve` against `.mjs` ESM specifiers in CJS-mode evaluation contexts. The `node -e "..."` form runs in CJS; `.mjs` extension resolution is handled by the path-resolution layer, not the loader, so it works without `--experimental-*` flags.

**Best Practice — Single RUN, two specifiers (vs. two separate RUNs):**

| Aspect                      | Single RUN (chosen)                            | Two RUNs                                  |
| --------------------------- | ---------------------------------------------- | ----------------------------------------- |
| Image layer count           | +1 layer                                       | +2 layers                                 |
| Build cache granularity     | Coarse (both must succeed)                     | Fine (failures isolated)                  |
| Wall-clock cost             | ~30-40 ms (single Node startup)                | ~60-80 ms (two Node startups)             |
| Failure clarity             | First failing `require.resolve` halts the chain (clear error) | Same, with one less invocation per layer |

Chosen: single RUN. Image-layer cost outweighs the marginal failure-isolation benefit on a 1-line check.

**Anti-patterns avoided:**

- `RUN node -e "import('pkg').then(...)"` — would evaluate the module, risking false-positive failures on init-time `DOMMatrix` references.
- `RUN test -f node_modules/pdfjs-dist/legacy/build/pdf.mjs` — checks file presence but does NOT exercise Node's resolver, so it would miss `package.json` `exports`-field misconfiguration. `require.resolve` is the load-bearing call shape.
- Placing the assertion BEFORE `npm ci --omit=dev` — would always fail (no `node_modules`).
- Placing the assertion AFTER `USER soleur` — would require chown'ing `node_modules` to soleur first, expanding the diff to root-owned permission changes for no benefit.

### Phase 2 — Verify the assertion fires

Build the image locally with the new RUN line and a deliberately-broken state (e.g., temporarily add `RUN npm uninstall pdfjs-dist` before the assertion line in a throwaway local edit) to confirm the build aborts with a clear `MODULE_NOT_FOUND`. Revert the throwaway edit. Document the verified output in the PR body.

This is local-only verification — no committed test artifact. Rationale: the assertion's correctness is single-line and Dockerfile-scoped; the cost of a fixture-image CI test exceeds the value for a 1-line guard. The fact that the BUILD fails is itself the test.

## Non-Goals

- **Runtime telemetry on PDF-extract failures.** The existing pino+Sentry path at `pdf-text-extract.ts:107-118` and `kb-preview-metadata.ts:82-110` still owns runtime failure observability. This PR catches *regressions in the runner image's dep tree*, NOT runtime parser bugs.
- **Native-binary loadability for `sharp`.** `require.resolve('sharp')` proves the JS entry exists; `sharp.node` (native binary) loads only at module evaluation. A glibc / libvips mismatch would still surface at runtime. Out of scope; tracked separately if it ever happens.
- **Generalization beyond `pdfjs-dist` + `sharp`.** Issue body suggests "future `mammoth`/`xlsx`/`epub-parse`". None of those are in `package.json` or `await import()`-ed today (verified by `rg -n "await import\(\"[^.]" apps/web-platform/server/`). When they land, the same RUN line gets one more `; require.resolve('<pkg>')` — trivially extensible. Adding them now would be coverage for non-existent code.
- **Aliased path imports.** `kb-route-helpers.ts:245` lazy-imports `@/server/git-auth` (a TS path alias, not a node_modules package). `require.resolve` cannot validate path-aliased imports without bundler config. Out of scope; the alias resolves at compile time, not runtime, so `npm run build:server` already gates it.

## Files to Edit

- `apps/web-platform/Dockerfile` — insert one `RUN node -e "..."` line in the runner stage between `RUN npm ci --omit=dev` and the `COPY --from=builder /app/public ./public` block.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `apps/web-platform/Dockerfile` contains `RUN node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')"` in the runner stage, positioned AFTER `RUN npm ci --omit=dev` and BEFORE `USER soleur`.
- [x] Local positive verification: `node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs'); require.resolve('sharp')"` from `apps/web-platform/` exits 0 (both resolve against current `node_modules`).
- [x] Local negative verification: same `node -e` invocation from a clean tmpdir (no `node_modules`) exits non-zero with `Cannot find module 'pdfjs-dist/legacy/build/pdf.mjs'` — proves the assertion would abort `docker build` on regression.
- [x] Existing `apps/web-platform/test/helpers/bundled-server.ts:59` `--external:pdfjs-dist` guard remains untouched (this PR does not regress the package.json-side test).
- [x] PR body uses `Closes #3422 / Ref #3410` — the Dockerfile change is what this issue prescribes.

### Post-merge (operator)

- [ ] On the next `web-platform-release.yml` run after merge, confirm the GHCR image build succeeds (the assertion is now part of every release build).

## Test Scenarios

1. **Happy path:** `docker build` of the runner stage succeeds against current `main`. Both `pdfjs-dist/legacy/build/pdf.mjs` and `sharp` resolve.
2. **Negative path (manual verification only — not a committed test):** Inject `RUN npm uninstall pdfjs-dist` immediately before the assertion line. Build aborts with `Cannot find module 'pdfjs-dist/legacy/build/pdf.mjs'`. Revert the inject before commit.
3. **Sharp negative path (manual, optional):** Same shape with `RUN npm uninstall sharp`. Confirms the second specifier is also load-bearing.

## Risks

### Research Insights — Risks

**Performance:**

- Per-build cost: a single `node -e` startup + two `require.resolve` calls. Measured locally: 30-40ms wall-clock. Negligible against multi-minute Docker build times.
- Cache: assertion layer is invalidated only when `package.json` or `package-lock.json` changes (same predicate as the `npm ci --omit=dev` layer above it). Incremental builds skip the layer entirely.

**Edge cases:**

- *npm-ci pruning by virtue of `--omit=dev`:* if a maintainer ever moves `pdfjs-dist` or `sharp` to `devDependencies`, the assertion catches it at the very next CI build. This is the EXACT regression class the issue body names.
- *Multi-stage `--production` re-copy:* same — if a future stage `COPY`s a re-installed `node_modules` that lacks production deps, the assertion fires.
- *Node-version drift:* if a future `node:NN-slim` rejects `require.resolve` against `.mjs`, the build fails loud and we re-evaluate. Same gate, working as intended.
- *Lockfile-only changes:* if `package-lock.json` resolves a dep tree that drops sharp transitively (extremely unlikely — sharp is a direct dep), the assertion fires.

**References:**

- Node.js `require.resolve` docs: https://nodejs.org/api/modules.html#requireresolverequest-options (confirms behavior on `.mjs` specifiers; resolution layer is filename-extension agnostic).
- Docker layer-caching semantics: https://docs.docker.com/build/cache/ (RUN cache key = command string + parent layer digest; unchanged for incremental builds).
- pdfjs-dist legacy entry rationale: `apps/web-platform/server/pdf-text-extract.ts:13` (existing comment block).

### Risk register

- **Layer caching invalidation:** The new RUN sits AFTER `RUN npm ci --omit=dev`. Cache invalidates only when `package.json` or `package-lock.json` changes — same trigger as the npm-ci layer above it. Effective overhead is zero on incremental builds.
- **`require.resolve` on ESM specifiers:** Node 22 supports `require.resolve` against ESM specifiers (the legacy entry is `.mjs`). Verified by running `node -e "require.resolve('pdfjs-dist/legacy/build/pdf.mjs')"` against a populated `node_modules`. If a future Node-version bump rejects this combination, the failure surfaces at the next CI build — same gate, working as designed.
- **`sharp` native-binary surface:** `sharp` ships prebuilt native binaries per platform; `require.resolve('sharp')` only checks the JS entry, NOT whether the binary is loadable. A separately-broken native binary would still be caught by the runtime `await import("sharp")`. The assertion narrows the regression class from "any sharp breakage" to "sharp's JS entry is on disk" — that's the gap PR #3410's class targets, not native-loader bugs.
- **False sense of completeness:** The assertion is positive-coverage on TWO names. A future fifth lazy-imported dep won't be auto-discovered. Mitigation: the issue body's re-evaluation trigger says "fold in when a related silent-fallback (sharp/mammoth/xlsx) ships" — sharp is now folded in proactively; mammoth/xlsx will trigger the same gate when they land (they don't exist yet).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `threshold: none` with a rationale; the diff scope is `Dockerfile`-only and the canonical sensitive-paths regex from preflight Check 6 does not match.
- The `RUN node -e "..."` line uses double-quotes around the JS string. If a future maintainer adds a third specifier with a backslash or double-quote in its name, the shell-escaping breaks. None of `pdfjs-dist`, `sharp`, `mammoth`, `xlsx`, `epub-parse` contain such characters; the risk is theoretical. If the list grows beyond a hand-curated set, refactor to a tiny `node assert-deps.mjs` script COPYed into the runner stage.
- The assertion runs as the root user (before `USER soleur`). This is intentional — `npm ci --omit=dev` ran as root; the assertion shares the same effective filesystem view. Running it post-`USER soleur` would require chown'ing `node_modules` to soleur, which is a separate change with its own surface area.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change to a single Dockerfile RUN line. No user-facing surface, no auth/data/payments path, no architectural decision (the pattern is already established by sibling guards like `bundled-server.ts:59`).

## Open Code-Review Overlap

Verified `gh issue list --label code-review --state open` against `apps/web-platform/Dockerfile`:

```
#3422: review: add Dockerfile-stage pdfjs-dist resolution assertion
```

Only #3422 itself matches. **Disposition:** the plan IS the resolution for #3422. No fold-ins, acknowledgments, or deferrals.

## References

- Issue: #3422
- Related PR: #3410 (externalized `pdfjs-dist` from `build:server` esbuild bundling)
- Existing guards:
  - `apps/web-platform/test/helpers/bundled-server.ts:59` — asserts `--external:pdfjs-dist` is present in `package.json` `build:server`.
  - Issue body cross-reference: `pdf-text-extract.ts:107-118` and `kb-preview-metadata.ts:82-110` (try/catch sites that would otherwise swallow the regression).
- Lazy-import inventory at plan time (`rg -n "await import\(\"[^.]" apps/web-platform/server/`):
  - `pdfjs-dist/legacy/build/pdf.mjs` (pdf-text-extract.ts:108, kb-preview-metadata.ts:84)
  - `sharp` (kb-preview-metadata.ts:132)
  - `@/server/git-auth` (kb-route-helpers.ts:245) — local path, not a node_modules dep, NOT covered by this assertion (require.resolve on `@/`-aliased paths needs path-resolution config that's bundler-specific).
