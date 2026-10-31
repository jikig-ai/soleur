---
title: "chore(deps): batch critical and high Dependabot alerts into one PR"
date: 2026-10-31
slug: chore-batch-dependabot-critical-high-fixes
branch: feat-one-shot-dependabot-critical-batch
issue: 0
closes: []
type: fix
priority: high
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore(deps): batch critical and high Dependabot alerts into one PR

## Overview

Close the eight open critical/high Dependabot alerts against the repo's npm
lockfiles in one grouped-bump PR — the same shape merged PR #11646 used for the
medium/low drain (one PR, because the merge queue merges one entry per ~50-min
cycle and each alert costs a cycle).

Direct bumps in `apps/web-platform`: `next` `~16.3.8` → `~16.4.1` and
`@sentry/nextjs` `^10.59.0` → `^10.75.2`. Transitive bumps via lockfile
regeneration under `npm@11`: `body-parser` 2.3.0 → ≥2.4.0, and every `zod` copy
to ≥4.6.6 — including the nested `zod@3.25.76` copies under `inngest` and
`@likec4/core` (cleared by scoped npm `overrides`, not the pin alone) and the
`zod@4.3.6` copies in `spike/` and `plugins/soleur/skills/pencil-setup/scripts/`.
The drained advisories are ratcheted into `scripts/assert-dependabot-drain.py`
(`WATCHED_PACKAGES` + `REQUIRED` + `FLOOR_ANCHORS` + row-count floors) and its
test, per the ADR-191 convention codified in
`plugins/soleur/skills/work/references/work-lockfile-bumps.md` ("Ratchet the
drain guard in the same PR").

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

GitHub Dependabot reports eight open alerts at critical or high severity with a
patched version available (verified 2026-10-31 via
`gh api repos/jikig-ai/soleur/dependabot/alerts`):

| Alert | Severity | Package | Advisory | Vulnerable range | Patched | Manifest |
|---|---|---|---|---|---|---|
| #325 | critical | `next` | GHSA-2464-fhr4-w9xw — unauthenticated RCE in Image Optimization API when SVG files are used | `>=16.0.0 <=16.4.0` | 16.4.1 | apps/web-platform |
| #328 | critical | `next` | GHSA-673q-mjm6-r5xr — unauthenticated RCE in `use cache` functions returning typed arrays | `>=16.0.0 <=16.4.0` | 16.4.1 | apps/web-platform |
| #326 | critical | `@sentry/nextjs` | GHSA-mchm-gjx6-7h55 — middleware bypass via tunnel route | `>=10.0.0-alpha.0 <10.75.2` | 10.75.2 | apps/web-platform |
| #324 | high | `next` | GHSA-p3m5-59mp-jv5r — DoS in App Router Server Actions | `>=16.0.0 <=16.4.0` | 16.4.1 | apps/web-platform |
| #344 | high | `body-parser` | GHSA-27r3-jxmh-p828 — DoS via trailing bytes after compressed body | `>=2.0.0 <2.4.0` | 2.4.0 | apps/web-platform |
| #341 | high | `zod` | GHSA-mrhx-c7xc-m3w5 (CVE-2023-54404) — memory exhaustion on oversized constrained collections | `<4.6.6` | 4.6.6 | apps/web-platform |
| #342 | high | `zod` | GHSA-mrhx-c7xc-m3w5 | `<4.6.6` | 4.6.6 | pencil-setup/scripts |
| #343 | high | `zod` | GHSA-mrhx-c7xc-m3w5 | `<4.6.6` | 4.6.6 | spike |

Brief-vs-reality corrections found during premise validation (Phase 0.6):

- The brief framed the three zod alerts as "possibly stale — zod is already at
  4.6.6". They are **not** stale: the vulnerable range is `< 4.6.6` with **no
  lower bound** (verified against the advisory record), and
  `apps/web-platform/package-lock.json` still contains two `zod@3.25.76` nested
  copies — `node_modules/@likec4/core/node_modules/zod` (required by
  `@likec4/core@1.50.0`, range `^3.25.76`) and
  `node_modules/inngest/node_modules/zod` (required by `inngest@4.26.0`, range
  `^3.25.0`) — plus `zod@4.3.6` in the `spike/` and
  `pencil-setup/scripts` lockfiles. All are in range; the alerts stay open
  until every copy is gone or ≥4.6.6.
- Alert #324 is **high**, not critical as the brief grouped it — the batch
  scope (critical + high) is unchanged.
- `pen-cli`'s lockfile is already clean (`zod@4.6.7`, `body-parser@2.4.0`);
  the root lockfile contains none of the four packages.

## Research Insights

**Premise validation (Phase 0.6):** PR #11646 verified `MERGED` 2026-10-30 (the
grouped-bump precedent; its body is the PR-shape template). PR #11468 verified
`OPEN` (`@hono/node-server` 1.x→2.x — explicitly out of scope). All eight cited
alerts verified `open` via the Dependabot API with the ranges/patched versions
in the table above. ADR corpus check: the governing decision is ADR-191 (npm
single lockfile of record); the batch mechanism itself is established precedent,
not a new mechanism — no ADR conflict. Collision check: the only open
Dependabot PR is #11468 (out-of-scope package); no open PR touches
next/sentry/zod/body-parser.

**Property List (Phase 0.6b):** (1) every vulnerable package copy in tracked
lockfiles resolves to ≥ its `first_patched_version`; (2) the drain assertion
records the newly-cleared floors so a regression re-reds; (3) the diff keeps the
grouped-bump shape (manifest + lockfile + guard tables only); (4) build,
typecheck, and the affected test suites stay green.

**Cut List (Phase 0.6b):** nothing in the ask buys a property an existing
mechanism does not cover — `assert-dependabot-drain.py` IS the property-2
mechanism (extend, not invent). No new guard, workflow, or tool is added.

**File paths (from repo research):**

- `apps/web-platform/package.json` — `"next": "~16.3.8"` (line ~55),
  `"@sentry/nextjs": "^10.59.0"` (line ~43), `"overrides"` block (line ~114,
  currently: vite, ws, qs, @babel/core, protobufjs).
- `apps/web-platform/package-lock.json` — `node_modules/next@16.3.8`,
  `node_modules/@sentry/nextjs@10.59.0`, `node_modules/body-parser@2.3.0`
  (required by `express@5.2.1` peer, range `^2.2.1` — admits 2.4.0),
  `node_modules/zod@4.6.6`, nested `zod@3.25.76` ×2.
- `spike/package-lock.json` — `node_modules/zod@4.3.6` (transitive via
  `@anthropic-ai/claude-agent-sdk`, range `^4.0.0` — regen reaches 4.6.7).
- `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` —
  `node_modules/zod@4.3.6` (direct dep `^4.0.0` — regen reaches 4.6.7).
- `scripts/assert-dependabot-drain.py` + `scripts/assert-dependabot-drain.test.sh`
  — the ADR-191 reconciliation gate: `WATCHED_PACKAGES` set, `REQUIRED`
  (manifest, package, major, floor) rows, `FLOOR_ANCHORS`, `MIN_ROWS` /
  `MIN_RESOLVED` / `MIN_LOCKS` floors, `MUST_STAY_ABSENT` discharge ratchets.
  Completeness sweep requires a row for **every major line of every watched
  package present in any of the five lockfiles** — so watching the four new
  packages forces nine rows (see Phase 3).
- `.github/workflows/ci.yml` `lockfile-sync` job — regenerates all five
  lockfiles with `npm@11` and `git diff --exit-code`s them; runs
  `lint-dual-lockfile.sh` + `lint-workflow-install-sites.sh`.
- `apps/web-platform/test/c4-likec4-version-pin.test.ts` — pins `likec4` CLI ==
  `@likec4/core`/`@likec4/diagram` version across **six** files (Dockerfile,
  ci.yml, main-health-monitor.yml, render-c4-model.sh,
  generate-c4-from-components.ts, lib/c4-from-components.ts). This is why the
  @likec4 bump is the expensive fallback (see Technical Considerations).
- `apps/web-platform/test/next-config-image-optimizer-scope.test.ts` — asserts
  the `images.localPatterns` restriction in `next.config.ts`.

**Institutional learnings applied:**

- `2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md` — after any
  npm lockfile mutation in a worktree, verify each lockfile's `"name"` field
  matches `origin/main`. (All five package.jsons carry `name`, so the drift is
  not expected — the AC still verifies.)
- `2026-05-22-npm-version-pin-required-for-lockfile-sync-gate.md` — regen must
  run under `npm@11` (the CI gate's pin); local npm is 11.20.0.
- `plugins/soleur/skills/work/references/work-lockfile-bumps.md` — canonical
  transitive bump: `npx --yes npm@11 update <pkg>`; drain-guard ratchet in the
  same PR.
- ADR-191 — no `bun.lock`/`bunfig.toml [install]` may reappear; npm is the
  lockfile of record.

**External research (security topic — mandated):**

- Next.js 16.4.1 release notes ([vercel/next.js releases](https://github.com/vercel/next.js/releases)):
  security patch carrying the two critical + one high fixes. Next.js 16.4
  ([blog](https://nextjs.org/blog/next-16-4)) recommends Cache Components but
  keeps them **opt-in** (default in Next 17) — no `'use cache'` directives or
  `'use server'` Server Actions exist in this codebase (grepped). A DepDelta
  diff flags internal refactors (WorkStore/App-render execution-mode removal,
  PPR code-path removal) — none are public-API changes this codebase touches;
  `next build` + `tsc --noEmit` on `next.config.ts` (which uses `NextConfig`
  types) is the verification.
- GHSA-mchm-gjx6-7h55 ([advisory](https://github.com/getsentry/sentry-javascript/security/advisories/GHSA-mchm-gjx6-7h55)):
  exploitable only when `tunnelRoute` is set AND the app builds with webpack AND
  a route resolves under the tunnel path AND middleware is the sole authz. This
  repo sets **no** `tunnelRoute` (grepped `next.config.ts`,
  `instrumentation.ts`, `sentry.*.config.ts`) — the middleware skip is never
  installed, so the alert is not currently exploitable, but the bump is still
  required to close it.
- `images.localPatterns: [{ pathname: "/icons/**" }]` is already restricted
  (no `dangerouslyAllowSVG`) — the Image-Optimization RCE path is additionally
  belted, but the bump is the actual fix.
- zod-3 → 4 compatibility evidence for the two nested-copy parents:
  `inngest@4.26.2` (latest) still bundles `zod ^3.25.0` but its
  **peerDependencies accept `^3.25.0 || ^4.0.0`** — upstream sanctions zod 4,
  so a scoped override is a supported configuration.
  `@likec4/core` moved to `zod ^4` natively only at 1.55.0+ (`^4.6.5` at
  1.60.0); at 1.50.0 its bundled dep `^3.25.76` has **no** peer declaration —
  a scoped override there is outside the package's declared range (see the
  decision-challenges fork in Technical Considerations).

**Community/functional discovery:** stacks are TypeScript/npm — covered by
built-in agents (no uncovered stack). Functional-overlap agent could not be
spawned in this harness; inline equivalent: the drain machinery is repo-owned
(`assert-dependabot-drain.py`), no community artifact applies.

## Proposed Solution

One PR, three edit groups, matching the #11646 grouped-bump shape:

### Group 1 — `apps/web-platform/package.json` (direct pins + overrides)

- `"next": "~16.3.8"` → `"~16.4.1"` (tilde kept: same pinning convention as the
  current `~16.3.8`, admits 16.4.x patches only).
- `"@sentry/nextjs": "^10.59.0"` → `"^10.75.2"`.
- `overrides` — add two **scoped** entries that eliminate the zod-3 copies:
  `"inngest": { "zod": "^4.6.6" }` and `"@likec4/core": { "zod": "^4.6.6" }`.
  Scoped (not a blanket `"zod"`) so each entry documents which parent forced it
  and so a future package legitimately on zod 3 is not silently dragged.

### Group 2 — lockfile regeneration (npm@11)

- `apps/web-platform`: `npx --yes npm@11 install --package-lock-only` (resolves
  the new pins + overrides), then `npx --yes npm@11 update body-parser
  --package-lock-only` if the transitive copy still reads <2.4.0 (canonical
  transitive form per `work-lockfile-bumps.md`; express's `^2.2.1` admits it).
- `spike/`: `npx --yes npm@11 update zod` (transitive under
  `@anthropic-ai/claude-agent-sdk` `^4.0.0`).
- `plugins/soleur/skills/pencil-setup/scripts/`: `npx --yes npm@11 update zod`
  (direct `^4.0.0` — updates within range, package.json unchanged).
- Root + `pen-cli`: regenerate as well — the `lockfile-sync` job regenerates
  ALL FIVE and diffs, so an untouched-but-dirty lockfile still fails.
- Post-regen verification against all five lockfiles: every `next` ≥16.4.1,
  `@sentry/nextjs` ≥10.75.2, `body-parser` ≥2.4.0, and **zero** `zod` <4.6.6
  (no `*/node_modules/zod` 3.x entry remains); every `"name"` field unchanged
  vs `origin/main` (worktree-drift guard).

### Group 3 — drain-guard ratchet (`scripts/assert-dependabot-drain.py` + test)

Following the established convention ("add an anchor whenever an advisory
forces a floor up"; the guard's own docstring requires a row per installed
major of each watched package):

- `WATCHED_PACKAGES` += `next`, `@sentry/nextjs`, `body-parser`, `zod`.
- `REQUIRED` += nine rows — the completeness sweep leaves no smaller set:
  `("web-platform","next",16,"16.4.1")`,
  `("web-platform","@sentry/nextjs",10,"10.75.2")`,
  `("web-platform","body-parser",2,"2.4.0")`,
  `("web-platform","zod",4,"4.6.6")`,
  `("pencil-setup","body-parser",2,"2.4.0")`,
  `("pencil-setup","zod",4,"4.6.6")`,
  `("pen-cli","body-parser",2,"2.4.0")`,
  `("pen-cli","zod",4,"4.6.6")`,
  `("spike","zod",4,"4.6.6")`.
  (`pen-cli`/`pencil-setup` `body-parser`+`zod` rows are forced by the
  completeness sweep — those copies are already patched but are installed
  majors of newly-watched packages.)
- `FLOOR_ANCHORS` += `("next",16):"16.4.1"`,
  `("@sentry/nextjs",10):"10.75.2"`, `("body-parser",2):"2.4.0"`,
  `("zod",4):"4.6.6"` — each commented with its GHSA.
- `MIN_ROWS` 27→36, `MIN_RESOLVED` 27→36 (comment updated in the same style).
- `scripts/assert-dependabot-drain.test.sh` — extend the anchor spec list with
  `"next:16:16.4.1" "@sentry/nextjs:10:10.75.2" "body-parser:2:2.4.0"
  "zod:4:4.6.6"` and the floor spec list `MIN_ROWS:27→36`,
  `MIN_RESOLVED:27→36` so the three-file-edit property holds for the new
  anchors.

## Technical Considerations

- **Next 16.3.8 → 16.4.1 breaking-change check (brief requirement).** The
  advisories are fixed in 16.4.1; the 16.4 feature surface (Cache Components
  recommendation, Instant Navigation) is opt-in — the codebase sets no
  `cacheComponents`/`use cache`/`use server` and only uses
  `experimental.serverActions.allowedOrigins`, `proxyClientMaxBodySize`,
  `staleTimes`, `distDir`, `images.localPatterns`, `serverExternalPackages`,
  `env`, `headers`. `next.config.ts` is typechecked against `NextConfig` —
  a renamed/removed key fails `npm run typecheck`; runtime config drift fails
  `npm run build`. The image-optimizer scope test and e2e are the second net.
- **Sentry advisory reachability:** not exploitable here (no `tunnelRoute`,
  and webpack-vs-Turbopack condition aside, the skip never installs). Still
  bump — the alert does not close otherwise.
- **Decision fork — `@likec4/core`'s zod-3 copy.** Option A (default, recorded
  `pending - assumed` in `decision-challenges.md`): scoped override — 2 lines,
  no declared-range for likec4 but verified by the ~19 `c4-*` test files +
  typecheck + build; if red, escalate. Option B (fallback): bump the
  `@likec4/core`+`@likec4/diagram` pair to 1.60.0 — native `zod ^4.6.5`, but it
  drags the six-file `likec4` CLI pin-train (Dockerfile, ci.yml,
  main-health-monitor.yml, render-c4-model.sh,
  generate-c4-from-components.ts, lib/c4-from-components.ts) plus ~10 minor
  versions of renderer changes into a security batch. Rejected as default:
  blast radius out of proportion to the fix; likec4 bumps are deliberately
  staged events (the pin test documents a BUMPING procedure for a reason). If
  Option A ships, a follow-up issue tracks the likec4 1.60 bump on its own
  schedule.
- **`inngest` zod override is upstream-sanctioned** (peer range includes
  `^4.0.0`); its bundled `^3.25.0` is the conservative pin, not a compat
  boundary. inngest 4.26.2 latest still bundles zod 3 — no upgrade path exists.
- **`.npmrc` `min-release-age=3`** (apps/web-platform, spike, pencil-setup):
  all target versions are ≥9 days old (next 16.4.1: 2026-10-14; body-parser
  2.4.0: 2026-10-22; zod 4.6.7: 2026-10-12; @sentry/nextjs 10.75.2: 2026-09-22)
  — the floor does not block the regen.
- **`npm update` vs `install --package-lock-only`:** a plain regen does NOT
  move `body-parser@2.3.0` (2.3.0 satisfies express's `^2.2.1`) — the targeted
  `npm update body-parser` is required. Overrides DO force re-resolution of
  their subtrees on the first `install --package-lock-only`.
- **Merge-queue note:** same rationale as #11646 — batching avoids one
  ~50-min queue cycle per alert.
- **ADR-191 hygiene:** no `bun.lock`, no `bunfig.toml [install]`, all regen
  under `npm@11` matching the `lockfile-sync` job's pin.

## Files to Edit

- `apps/web-platform/package.json` — next/@sentry pins + two scoped `overrides` entries
- `apps/web-platform/package-lock.json` — regenerated
- `spike/package-lock.json` — regenerated (zod → ≥4.6.6)
- `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` — regenerated (zod → ≥4.6.6)
- `scripts/assert-dependabot-drain.py` — WATCHED_PACKAGES, 9 REQUIRED rows, 4 FLOOR_ANCHORS, MIN_ROWS/MIN_RESOLVED
- `scripts/assert-dependabot-drain.test.sh` — anchor + floor spec lists
- `package-lock.json` (root) and `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package-lock.json` — regenerated only if `npm install --package-lock-only` produces drift vs the committed file (the lockfile-sync gate diffs all five; expected no-op)

## Files to Create

None. (Conditional fallback only — if the likec4 override proves incompatible:
`apps/web-platform/package.json` likec4 pair to 1.60.0 + the six-file CLI
pin-train listed under Technical Considerations.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "bump `next` from ~16.3.8 to 16.4.1 (fixes 3 critical advisories … Dependabot alerts #324, #325, #328)" | Group 1 pin + AC-1 | mapped |
| 2 | "`@sentry/nextjs` from ^10.59.0 to 10.75.2 (fixes critical middleware-bypass-via-tunnel-route advisory, alert #326)" | Group 1 pin + AC-2 | mapped |
| 3 | "regenerate the lockfile(s) so the transitive `body-parser` reaches >=2.4.0 (high DoS alert #344)" | Group 2 + AC-3 | mapped |
| 4 | "Verify whether the 3 zod memory-exhaustion alerts (#341, #342, #343) are already resolved … if a transitive zod below 4.6.6 remains in any lockfile, include it" | Group 1 overrides + Group 2 + AC-4 (finding: NOT stale — nested 3.25.76 + two 4.3.6 copies exist) | mapped |
| 5 | "Keep the batch scoped to critical+high severities with a patched version available; out of scope: PR #11468 …, medium/low alerts, pip alerts" | Non-Goals | mapped |
| 6 | "Verify after the bump that `next build` / typecheck and the affected test suites pass … check the changelog for breaking changes in this codebase's usage" | Phase 4 verification + AC-6/7/8 + Technical Considerations | mapped |
| 7 | "same grouped-bump shape as merged PR #11646" | Proposed Solution + PR-body AC | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `apps/web-platform/package.json` next pin | "bump `next` from ~16.3.8 to 16.4.1" | asked |
| `apps/web-platform/package.json` @sentry/nextjs pin | "`@sentry/nextjs` from ^10.59.0 to 10.75.2" | asked |
| `apps/web-platform/package.json` scoped zod overrides | "if a transitive zod below 4.6.6 remains in any lockfile, include it" | asked |
| Three lockfile regenerations | "regenerate the lockfile(s)" / "include it" | asked |
| `scripts/assert-dependabot-drain.py` + test updates | — | inferred — justification: the ADR-191 drain-guard contract (`work-lockfile-bumps.md`: "Ratchet the drain guard in the same PR") requires recording newly-cleared floors or a regression to a still-vulnerable version passes the guard silently |
| root + pen-cli lockfile regen | — | inferred — justification: the `lockfile-sync` CI job regenerates all five lockfiles and `git diff --exit-code`s them; skipping a drifted one fails the PR |
| Verification phase (typecheck/build/vitest) | "Verify after the bump that `next build` / typecheck and the affected test suites pass" | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `spike`, `plugins/soleur`, `scripts`
- Planned files: ≤8 | Estimated changed lines: ~60 non-lockfile + lockfile diffs (lockfile churn excluded from judgment — mechanical)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines → the root count nominally meets one threshold
- Recommendation: single PR — the multi-root shape IS the deliverable (one grouped-bump PR per #11646 precedent; the merge queue merges one entry per ~50-min cycle, so splitting would multiply the cost the batch exists to avoid). Non-lockfile diff stays ~60 lines across 4 files.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — dependency-batch/infra-tooling change.
Product/UX gate: the Files-to-Edit list contains no UI-surface path (no
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`); the mechanical
UI-surface override does not fire. Tier: NONE.

## User-Brand Impact

- **If this lands broken, the user experiences:** a degraded product surface,
  worst case being the C4 knowledge-base diagram workspace failing to render
  (if the `@likec4/core` zod-4 override is incompatible) or background jobs
  silently stopping (if the `inngest` zod-4 override regresses) — both
  reversible by reverting the PR, neither destroying user data.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure vector — the diff adds no data path; it *removes* eight known
  CVE vectors (two unauthenticated RCEs among them).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** worst-case breakage is a degraded,
  revertible feature surface caught by the c4-*/inngest suites before merge —
  not a data-loss or breach path, which is the `single-user incident` bar.
- *Scope-out override:* `threshold: none, reason: the touched paths are
  manifest/lockfile/guard-table files only — no auth, schema, secret, or
  migration surface is edited`

## Observability

```yaml
liveness_signal:
  what: "Dependabot drain assertion — scripts/assert-dependabot-drain.py exit 0 over the five tracked lockfiles"
  cadence: "every test-all.sh suite run (CI) + on-demand"
  alert_target: "CI check failure on the PR (lockfile-sync / test-all)"
  configured_in: "scripts/assert-dependabot-drain.py; scripts/test-all.sh run_suite entries ~line 5564"

error_reporting:
  destination: "CI job log (lockfile-sync job; test-all suite output)"
  fail_loud: "stdout: 'DRAIN ASSERTION FAILED:' + '*** VULNERABLE ***' row, exit 1"

failure_modes:
  - mode: "a still-vulnerable copy ships (floor not met)"
    detection: "assert-dependabot-drain.py prints the offending (manifest, package@version) row and exits 1"
    alert_route: "required CI check red on the PR"
  - mode: "a watched package gains an uncovered major line"
    detection: "completeness sweep row: '<manifest>: <pkg>@<ver> is present on major line N, which no row covers'"
    alert_route: "required CI check red on the PR"
  - mode: "lockfile drifts from package.json"
    detection: "lockfile-sync job regenerates and git-diff-fails"
    alert_route: "required CI check red on the PR"

logs:
  where: "GitHub Actions job logs (ci.yml lockfile-sync; test-all suite)"
  retention: "GitHub default run retention"

discoverability_test:
  command: "python3 scripts/assert-dependabot-drain.py"
  expected_output: "drain assertion"
```

## Guard Contract

### Guard 1 — Dependabot-drain ratchet extension (`scripts/assert-dependabot-drain.py`)

**Property.** Every installed copy of `next`, `@sentry/nextjs`, `body-parser`, and `zod` in every tracked lockfile resolves at or above the first_patched_version of the advisories this batch clears, and a regression to a still-vulnerable version fails the guard loudly.

**Assembly.** The structural chokepoints are: `WATCHED_PACKAGES` (the package set the completeness sweep quantifies over), `REQUIRED` (the per-(manifest, package, major-line) floor rows the resolver evaluates), `FLOOR_ANCHORS` (the anti-lowering mirror), and the `MIN_ROWS`/`MIN_RESOLVED` floors (the anti-vacuity dispatch). Members (individual rows) drift as advisories land; the property holds over whatever the five tracked lockfiles enumerate at run time — the sweep itself finds every `(manifest, watched-package, major)` tuple present.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Reintroduce `node_modules/inngest/node_modules/zod@3.25.76` in `apps/web-platform/package-lock.json` (row X holds: package present on a watched major) and the `("web-platform","zod",4,"4.6.6")` row's found-worst check | RED |
| 2 | Delete `zod` from `WATCHED_PACKAGES` while the nine new rows remain (the guard's own dispatch: declared-vs-watched drift check) | RED |
| 3 | Add a second vulnerable copy after a compliant first — a `zod@3.25.76` entry under a new parent alongside the still-present `zod@4.6.6` top-level (the check must compare worst-found, not first-found) | RED |
| 4 | Lower `("zod",4)` floor to `"4.0.1"` — a real patch level on the right major but below the advisory floor (FLOOR_ANCHORS two-place check) | RED |
| 5 | Suite-side: drop the new anchor specs from `assert-dependabot-drain.test.sh`'s spec list while keeping the anchors (the three-file-edit property lapses) and `bash scripts/assert-dependabot-drain.test.sh` must report the missing spec arms | RED |
| 6 | Must-PASS input: `zod@4.6.7` nested under `@likec4/core` (a version ABOVE the floor — the override's permitted resolution, differing from the canonical top-level 4.6.6) | PASS |

**Anchor.** The floor values are anchored to the advisory feed's `first_patched_version` (GHSA ids in the row comments), not to the resolved tree — weakening the floor requires editing `REQUIRED`, `FLOOR_ANCHORS`, and `assert-dependabot-drain.test.sh` together, a three-file consistency check.

## Enhancement Summary

Deepen-plan pass executed inline (no agent-spawn capability in this harness —
documented in `decision-challenges.md`): halt gates 4.6–4.13 verified (User-Brand
Impact present and non-placeholder; Observability fields valid — `python3`
probe verb allowlisted, <15s, literal `expected_output`; no PAT-shaped vars; no
UI surface; dep-bump so Encryption/Task-Design conditional gates do not fire;
single unfenced Scope Check with every ask mapped and the two `inferred` items
justified; Guard Contract added for the drain-table extension). Verify-the-
negative sweep: the plan's negative claims (`no tunnelRoute configured`, `no
'use cache'/'use server' directives`, `zero zod <4.6.6 after batch`) were each
grepped against the tree — all confirmed with citations in Research Insights.
Key finding already folded in: the zod alerts are NOT stale — two nested
`zod@3.25.76` copies (`inngest`, `@likec4/core`) plus `zod@4.3.6` in `spike/`
and `pencil-setup/scripts` keep alerts #341–#343 open; the plan clears them via
scoped overrides + regen, with the likec4-1.60 pin-train as documented fallback.

## Open Code-Review Overlap

None. Queried 98 open `code-review`-label issues on 2026-10-31; no issue body
names any planned file path (`apps/web-platform/package.json`, the four
lockfiles, `scripts/assert-dependabot-drain.{py,test.sh}`,
`apps/web-platform/next.config.ts`). Keyword hits on "zod"/"dependabot"
(#3374, #3242, #7218) are unrelated concerns.

## Acceptance Criteria

- [ ] AC-1 `apps/web-platform/package.json` pins `next` to `~16.4.1` and the lockfile resolves `node_modules/next` ≥ 16.4.1 (closes alerts #324, #325, #328).
- [ ] AC-2 `@sentry/nextjs` pinned `^10.75.2`, lockfile ≥ 10.75.2 (closes alert #326).
- [ ] AC-3 Every `body-parser` entry in all five tracked lockfiles is ≥ 2.4.0 (closes alert #344).
- [ ] AC-4 Every `zod` entry in all five tracked lockfiles is ≥ 4.6.6 — zero `*/node_modules/zod` copies on the 3.x line remain anywhere (closes alerts #341, #342, #343). Verified by a census of every lockfile `packages` key naming `zod`, not by grepping top-level only.
- [ ] AC-5 `scripts/assert-dependabot-drain.py` carries the four new packages in `WATCHED_PACKAGES`, the nine `REQUIRED` rows, the four `FLOOR_ANCHORS`, `MIN_ROWS`/`MIN_RESOLVED` at 36; `python3 scripts/assert-dependabot-drain.py` exits 0 and `bash scripts/assert-dependabot-drain.test.sh` is green.
- [ ] AC-6 `cd apps/web-platform && npm run typecheck` (`tsc --noEmit`) is green under next 16.4.1 — validates `next.config.ts` key set against `NextConfig`.
- [ ] AC-7 `cd apps/web-platform && npm run build` (`next build`) is green.
- [ ] AC-8 `cd apps/web-platform && npx vitest run` is green for at minimum: `test/next-config-image-optimizer-scope.test.ts`, the `test/c4-*.test.*` files (likec4-on-zod-4 verification), `test/server/inngest/**` + `test/helpers/inngest-step-harness.test.ts` (inngest-on-zod-4 verification), and `test/sentry-*.test.ts`.
- [ ] AC-9 All five `package-lock.json` files regenerated under `npm@11` (`npx --yes npm@11`); each lockfile's `"name"` field is byte-identical to `origin/main` (worktree-drift guard, learning 2026-05-27).
- [ ] AC-10 `bash scripts/lint-dual-lockfile.sh`, `bash scripts/verify-lockfile-guards.sh`, and `bash scripts/lint-workflow-install-sites.sh` all exit 0; no `bun.lock`/`bun.lockb`/`bunfig.toml [install]` tracked (ADR-191).
- [ ] AC-11 PR body carries the #11646-shape table (bump / package / from→to / manifest / method) naming each of the eight alerts, plus a `## Changelog` section.
- [ ] AC-12 No changes to `apps/web-platform/next.config.ts`, `middleware.ts`, or any `.ts`/`.tsx` source — the batch is manifest + lockfile + guard-table only. (If the likec4 fallback fires, this AC is amended rather than silently violated.)

## Test Scenarios

- Given the lockfile before the batch, when `python3 -c` enumerates every `packages` key named `zod` across all five lockfiles, then every resolved version is ≥4.6.6 and none has major 3 — `integration`.
- Given `apps/web-platform/package.json` overrides, when `npm ls zod` (or the lockfile census) runs, then `inngest` and `@likec4/core` subtrees resolve `zod@4.6.6+` — `integration`.
- Given next@16.4.1 installed, when `npm run typecheck` runs, then `next.config.ts` compiles against `NextConfig` with no unknown-key errors — `unit`.
- Given the merged `withSentryConfig` config, when `npx vitest run test/next-config-image-optimizer-scope.test.ts`, then `images.localPatterns` still restricts the optimizer to `/icons/**` — `unit`.
- Given the zod-4 override under `@likec4/core`, when `npx vitest run test/c4-*.test.*` runs, then the C4 model parse/render suite is green (this is the override-compat canary; a RED here escalates to the likec4-1.60 fallback) — `unit`.
- Given the zod-4 override under `inngest`, when `npx vitest run test/server/inngest test/helpers/inngest-step-harness.test.ts`, then the step-harness and middleware suites are green — `unit`.
- Given the new drain rows, when a lockfile is mutated to reintroduce `zod@3.25.76`, then `assert-dependabot-drain.py` exits 1 naming the row — `unit` (guard must be drivable red).
- Given `npm ci --ignore-scripts` in `apps/web-platform`, then install reproduces cleanly from the committed lockfile — `integration`.

## Success Metrics

- All eight cited Dependabot alerts transition to auto-dismissed/closed after merge (the drain assertion is the merge-time proof; the API state is the lagging mirror).
- Zero regressions in `npm run typecheck`, `npm run build`, and the named vitest suites.
- `lockfile-sync` CI job green on the PR.

## Dependencies & Risks

- **zod-4-under-likec4-1.50 compat (the one real gamble):** mitigated by the
  c4-* suite + escalation path to the likec4 1.60 pin-train; recorded as a
  `pending - assumed` technical row in
  `knowledge-base/project/specs/feat-one-shot-dependabot-critical-batch/decision-challenges.md`.
- **npm@11 shape skew:** local npm is 11.20.0 (verified); CI pins `npm@11` —
  same major, matching the lockfile-sync gate's own pin. Worktree `name`-drift
  verified per AC-9.
- **Merge-queue serialization:** one PR keeps the cost at one ~50-min cycle.
- **Risk that Dependabot re-lists a NEW alert between plan and merge** (e.g. a
  fresh next 16.4.x advisory): re-run the alerts query at work time; absorb or
  defer per severity, and note in the PR body.

## Non-Goals

- PR #11468 (`@hono/node-server` 1.x→2.x — needs a real compat fix, not a bump).
- Medium/low Dependabot alerts; pip-ecosystem alerts.
- likec4 1.60 pin-train bump (fallback only; follow-up issue if the override ships).
- Any `.ts`/`.tsx`/`next.config.ts`/`middleware.ts` source change.

## References & Research

- Grouped-bump precedent: PR #11646 (`chore(deps): batch 8 dependabot bumps into one PR`, merged 2026-10-30).
- Out-of-scope sibling: PR #11468 (`@hono/node-server` major).
- Governing ADR: `knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md`.
- Guard contract: `scripts/assert-dependabot-drain.py`, `scripts/assert-dependabot-drain.test.sh`, `scripts/lint-dual-lockfile.sh`, `scripts/lint-workflow-install-sites.sh`, `scripts/verify-lockfile-guards.sh`.
- Canonical procedure: `plugins/soleur/skills/work/references/work-lockfile-bumps.md`.
- Learnings: `2026-05-22-npm-version-pin-required-for-lockfile-sync-gate.md`, `2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md`.
- Advisories: GHSA-2464-fhr4-w9xw, GHSA-673q-mjm6-r5xr, GHSA-p3m5-59mp-jv5r, GHSA-mchm-gjx6-7h55, GHSA-27r3-jxmh-p828, GHSA-mrhx-c7xc-m3w5.
- [Next.js 16.4 announcement](https://nextjs.org/blog/next-16-4); [GHSA-mchm-gjx6-7h55 advisory](https://github.com/getsentry/sentry-javascript/security/advisories/GHSA-mchm-gjx6-7h55).
