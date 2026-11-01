---
title: "chore(deps): drain the open Dependabot medium/low npm batch in one PR"
date: 2026-11-01
slug: chore-batch-dependabot-medium-low-drain
branch: feat-one-shot-dependabot-medium-low-batch
issue: 0
closes: []
type: fix
priority: medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore(deps): drain the open Dependabot medium/low npm batch in one PR

## Overview

Close the fifteen open Dependabot alerts against the repo's npm lockfiles in
one grouped-bump PR — the shape merged PRs #11646 (batch 8) and #11780
(critical/high batch) used: in-range transitive updates under `npm@11` where a
patched release exists on the installed major, scoped `overrides` for packages
whose advisories patch only a different major, and the ADR-191 drain-guard
ratchet (`scripts/assert-dependabot-drain.py` + `.test.sh`) extended in the
same PR (`plugins/soleur/skills/work/references/work-lockfile-bumps.md`:
"Ratchet the drain guard in the same PR").

The sixteenth alert the brief names — pip Pillow (alert #302) — was verified
`state: fixed` on the detail endpoint: `Pillow==13.0.0` already merged via
#11646. It is verification-only in this batch; no pip work remains.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

GitHub Dependabot reports fifteen open alerts, all medium/low severity, all
with a patched version available (verified 2026-11-01 via
`gh api repos/jikig-ai/soleur/dependabot/alerts?state=open` and per-GHSA
`gh api advisories/<id>`):

| Alert | Severity | Package | Advisory | Vulnerable range | Patched | Manifest |
|---|---|---|---|---|---|---|
| #284 | medium | `hono` | GHSA-5r4p-p66f-jhc7 — serveStatic double-decodes request path (middleware bypass) | `>=4.12.4 <4.13.11` | 4.13.11 | apps/web-platform |
| #292 | medium | `@vitest/mocker` | GHSA-xp26-3454-mjgp — Windows backslash traversal bypasses mocker allowlist fix | `>=4.1.11 <4.1.12` | 4.1.12 | apps/web-platform |
| #293 | medium | `@vitest/mocker` | GHSA-qxg6-89mg-rqv8 — code injection via unauthenticated manual-mock registration | `>=2.1.0-beta.7 <4.1.12` | 4.1.12 | apps/web-platform |
| #327 | medium | `ip-address` | GHSA-rxp7-6hxx-x8q5 — Address6 ReDoS (quadratic zone-id match) | `<=10.7.3` | 10.7.4 | apps/web-platform |
| #340 | medium | `ip-address` | GHSA-rxp7-6hxx-x8q5 | `<=10.7.3` | 10.7.4 | pencil-setup/scripts |
| #346 | low | `fast-uri` | GHSA-333x-w4r6-6crp — scheme injection via unescaped first-segment colon | `>=3.0.0 <3.1.9` | 3.1.9 | apps/web-platform |
| #347 | medium | `fast-uri` | GHSA-wjr9-j795-jxcr — host confusion via unchecked WHATWG host canonicalization | `>=3.1.3 <3.1.9` | 3.1.9 | apps/web-platform |
| #348 | low | `fast-uri` | GHSA-xhq7-xmqj-769h — improper path equivalence in relative-reference normalization | `>=3.0.0 <3.1.9` | 3.1.9 | apps/web-platform |
| #349 | medium | `fast-uri` | GHSA-w74x-v6f9-j3xg — URI scheme spoofing via percent-encoded scheme | `>=3.0.0 <3.1.9` | 3.1.9 | apps/web-platform |
| #367 | medium | `@hono/node-server` | GHSA-rmxm-3fg6-px4f — serveStatic double-decodes request path (middleware bypass) | `>=1.19.10 <2.1.3` | 2.1.3 | apps/web-platform |
| #373 | medium | `@hono/node-server` | GHSA-rmxm-3fg6-px4f | `>=1.19.10 <2.1.3` | 2.1.3 | pencil-setup/scripts |
| #374 | medium | `glob` | GHSA-3g3m-2fjr-6pw4 — AbortSignal cancellation bypass (post-timeout traversal) | `>=9.0.0 <=14.0.1` | 14.0.2 | apps/web-platform |
| #375 | medium | `minimatch` | GHSA-g3hv-75wg-m249 — globparts-amplification DoS | `<11.0.1` | 11.0.1 | apps/web-platform |
| #376 | medium | `minimatch` | GHSA-g3hv-75wg-m249 | `<11.0.1` | 11.0.1 | root |
| #377 | medium | `minimatch` | GHSA-g3hv-75wg-m249 | `<11.0.1` | 11.0.1 | pen-cli |

Brief-vs-reality corrections found during premise validation (Phase 0.6):

- **Pillow (alert #302) is already `state: fixed`.** The `state=open` list
  endpoint still returns it, but the detail endpoint shows `state: fixed`
  (`updated_at` 2026-10-30): `Pillow==13.0.0` merged in #11646, two days
  before this plan. No requirements.txt work remains; the batch verifies the
  fixed state and moves on. (The drain guard is npm-lockfile-scoped, so there
  is no pip-side row to ratchet.)
- **The hono 2.x migration is not needed.** The brief flagged the serveStatic
  alerts as possibly closable only via hono 2.x; GHSA-5r4p-p66f-jhc7 patches
  on the 4.x line at 4.13.11, and `@hono/node-server` patches at 2.1.3 —
  which the `@modelcontextprotocol/sdk` parent already sanctions
  (`"^1.19.9 || ^2.0.5"` dependency range). Dependabot's own open PR #11468
  proposes the identical `@hono/node-server` 1.19.17→2.1.5 bump in
  `apps/web-platform`; this batch supersedes it.
- **The roster-entry-gate "known main breakage" does not reproduce.**
  `npx vitest run test/cla-evidence/roster-entry-gate.test.ts` from
  `apps/web-platform` passes 23/23 on the current main tip
  (`3fd8ba5e70`, the branch merge-base). The earlier failure report appears
  stale or environment-specific; the work phase re-verifies and only fixes
  in a distinct commit if the suite is actually red.
- **minimatch has no patched release on any installed major.** GHSA-g3hv's
  range is `< 11.0.1` — unbounded below — and the versions list shows no
  backport (10.x tops at 10.2.6, 9.x and 3.x untouched). Every copy in the
  three flagged lockfiles is in range: web-platform carries minimatch@3.1.5,
  @9.0.9, @10.2.4/.5/.6; root carries @3.1.5 and @10.2.6; pen-cli carries
  @10.2.6 (exact-pinned by `@earendil-works/pi-coding-agent`). `npm update`
  cannot cross the parent constraints — npm `overrides` is the only
  resolution mechanism (the same mechanism the zod batch used for nested
  copies outside a declared range).
- **glob has no patched release on majors 9–13 either** — `>=9.0.0 <=14.0.1`
  patches only at 14.0.2. web-platform's two copies (10.5.0 under `rimraf`,
  13.0.6 under `@sentry/bundler-plugins`) both need scoped overrides; no
  released parent reaches glob 14 (rimraf@6.1.3 wants `^13.0.3`,
  bundler-plugins@11.10.0 wants `^13.0.6`).

## Research Insights

**Premise validation (Phase 0.6):** prior-batch plan and spec dir verified on
disk (`plans/archive/20261031-181546-…critical-high-fixes-plan.md`,
`specs/archive/20261031-181546-feat-one-shot-dependabot-critical-batch/`).
Draft PR #11823 verified OPEN/draft on this branch. Sibling PR #11814 verified
OPEN and non-overlapping (affected-index pairs; its file list touches none of
this batch's paths). Open Dependabot PR #11468 verified (`@hono/node-server`
1→2 in web-platform — superseded by this batch). All sixteen cited alerts
queried live: fifteen npm open, one pip already `fixed` (correction above).
Tracking issues verified open: #11783 (next body-streams upstream fix),
#11696 (likec4 1.60 pin-train), #10857 (umbrella security issue). ADR corpus
check: the governing decision is ADR-191 (npm single lockfile of record); the
batch + guard-ratchet mechanism is its own codified precedent, not a new
mechanism — no ADR conflict. `roster-entry-gate.test.ts` verified GREEN
23/23 (apps/web-platform CWD, vitest 4.1.11, 2026-11-01) — reported breakage
not reproducing.

**Property List (Phase 0.6b):** (1) every vulnerable package copy in the five
tracked npm lockfiles resolves to ≥ its `first_patched_version`; (2) the drain
assertion records the newly-cleared floors and newly-watched packages so a
regression re-reds; (3) the diff keeps the grouped-bump shape (manifest +
lockfile + guard tables only); (4) lint, typecheck, build, and the affected
test suites stay green under the forced re-resolutions; (5) the reported
main-red test is re-verified and fixed in a distinct commit iff still red.

**Cut List (Phase 0.6b):** nothing in the ask buys a property an existing
mechanism does not cover — `assert-dependabot-drain.py` IS the property-2
mechanism (extend, not invent) and `overrides` in package.json IS the
property-1 mechanism where ranges cannot move (the zod/undici precedent).
No new guard, workflow, or tool is added.

**File paths (from repo research):**

- `apps/web-platform/package.json` — `overrides` block currently carries
  `vite`, `ws`, `qs`, `@babel/core`, `protobufjs`, and the two scoped zod
  entries (`inngest`, `@likec4/core`) from the prior batch.
- `apps/web-platform/package-lock.json` — `hono@4.13.8` (via
  `@modelcontextprotocol/sdk` `^4.11.4`), `@hono/node-server@1.19.17` (via
  MCP SDK `^1.19.9 || ^2.0.5`), `ip-address@10.7.2` (via `express-rate-limit`
  `^10.2.0`), `fast-uri@3.1.8` (via four nested `ajv` copies `^3.0.1`),
  `@vitest/mocker@4.1.11` (via `vitest` dep `"4.1.11"` exact),
  `glob@10.5.0` (via `rimraf` `^10.3.7` ← `gaxios` ← `gcp-metadata`),
  `glob@13.0.6` (via `@sentry/bundler-plugins` `^13.0.6` ← `@sentry/nextjs`),
  `minimatch` ×5: `@3.1.5` (eslint-plugin-import/-jsx-a11y/-react `^3.1.2`,
  @eslint/config-array + @eslint/eslintrc + eslint `^3.1.5`),
  `@9.0.9` (`rimraf/node_modules/glob` `^9.0.4`), `@10.2.4/.5/.6`
  (typescript-estree, glob@13, readdir-glob — all `^10.2.2`).
- `package.json` (root) — `overrides` already carries the
  `markdownlint-cli`-scoped block (`brace-expansion`, `smol-toml`).
- `package-lock.json` (root) — `minimatch@3.1.5` (`@11ty/recursive-copy`
  `^3.1.5`), `minimatch@10.2.6` (`markdownlint-cli` `~10.2.5`).
- `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` —
  `@hono/node-server@1.19.17`, `ip-address@10.7.2` (same MCP SDK chain);
  `fast-uri@3.1.9`, `hono@4.13.14` already patched; no minimatch/glob/mocker.
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json` —
  `overrides` carries `undici: "8.12.2"`, `sharp: "0.35.5"` (the exact-pin
  precedent), single dep `@pen.dev/cli`.
- `pen-cli/package-lock.json` — `minimatch@10.2.6` (pi-coding-agent exact),
  `@hono/node-server@2.1.5`, `ip-address@10.7.5`, `fast-uri@3.1.9`,
  `hono@4.13.14` all already patched.
- `spike/package-lock.json` — none of the seven packages present.
- `plugins/soleur/skills/gemini-imagegen/requirements.txt` —
  `Pillow==13.0.0` already on main (alert #302 fixed).
- `scripts/assert-dependabot-drain.py` + `.test.sh` — the ADR-191
  reconciliation gate: `WATCHED_PACKAGES` (14), `REQUIRED` (36 rows),
  `FLOOR_ANCHORS` (18), `MIN_ROWS`/`MIN_RESOLVED` 36, `MIN_LOCKS` 5,
  `MUST_STAY_ABSENT`/`MIN_ABSENT`/`ABSENT_PATH_ANCHOR`; test.sh fixture
  mirrors the (manifest, pkg, major) set and source-greps floor + anchor
  specs; `MIN_ASSERTIONS=34`.
- `.github/workflows/ci.yml` `lockfile-sync` job — regenerates all five
  lockfiles under `npm@11` and `git diff --exit-code`s them.
- `scripts/test-all.sh:5565,5571` — registers `assert-dependabot-drain-live`
  and `assert-dependabot-drain-unit` suites.
- `plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` —
  the pen-cli engine contract probe (the undici-override row in the guard
  requires a green probe before touching that lockfile's pins).
- `apps/web-platform/eslint.config.mjs` — flat config importing
  `@eslint/js`, `@next/eslint-plugin-next`, `@typescript-eslint/*`,
  `globals`, `react-hooks` — imports NOTHING from `eslint-config-next` (the
  header comment documents this) and no `FlatCompat`.

**minimatch v11 compatibility audit (the override's safety case):**
v3's `module.exports` IS the callable; v9+ exports a namespace
(`{minimatch, Minimatch, match, ...}`). Every minimatch consumer whose code
actually loads in this repo's tooling uses the namespace form, which is
v11-compatible:

- `eslint` core: `require("minimatch").Minimatch` and `{ Minimatch }` —
  v11-safe.
- `@eslint/config-array@0.21.2` (loaded by every flat-config lint run): CJS
  dist does `require("minimatch").Minimatch` — v11-safe. Its ESM dist uses a
  default import that v11 does not provide, but eslint's own resolution picks
  the `require` condition (eslint core is CJS); the lint suite is the
  empirical gate.
- `@typescript-eslint/typescript-estree`, `readdir-glob`: namespace/`{
  minimatch }` imports — v11-safe.
- `@11ty/recursive-copy` (root): `require("minimatch").match` — v11-safe.
- `markdownlint-cli` (root): `import { minimatch }` + `new
  minimatch.Minimatch` — v11-safe.
- **Callable-v3 callers that are installed but never loaded:**
  `eslint-plugin-import` (`_interopRequireDefault(require('minimatch'))`
  then calls `.default`), `eslint-plugin-jsx-a11y`, `eslint-plugin-react`,
  and `@eslint/eslintrc`'s `override-tester` (`import minimatch from
  "minimatch"` — v11 ESM has no default export). These packages are only in
  the tree via the `eslint-config-next` devDep; the flat config imports none
  of them and no `FlatCompat` exists — their copies are lockfile-visible but
  runtime-inert (the exact shape of the `@likec4/core` zod-3 precedent).

**glob v14 compatibility:** rimraf calls `glob_1.glob`/`glob_1.globSync` and
`@sentry/bundler-plugins` calls `glob.glob` — all named exports retained in
v14; glob@14.0.2 itself depends on `minimatch ^11.0.0`, aligning with the
minimatch override.

**Institutional learnings applied:**

- `2026-04-07-npm-transitive-dep-security-update-mechanics.md` —
  `npm update <pkg>` does not reliably move a transitive even when in-range;
  `overrides` is the canonical forcing mechanism.
- `2026-09-29-dependabot-remediation-must-ratchet-drain-guard-floors.md` —
  `REQUIRED` + `FLOOR_ANCHORS` + test spec lists ratchet in the same diff.
- `2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md` — verify
  each lockfile's `"name"` field vs `origin/main` after regen.
- `2026-05-22-npm-version-pin-required-for-lockfile-sync-gate.md` — regen
  under `npm@11` (local: 11.20.0; CI pin matches).
- `work-lockfile-bumps.md` — canonical transitive form `npx --yes npm@11
  update <pkg>` + drain-guard ratchet in the same PR.
- ADR-191 — no `bun.lock`/`bunfig.toml [install]`; npm is the lockfile of
  record; `.npmrc` `min-release-age=3` honored (all targets verified ≥3 days
  old on 2026-11-01: minimatch 11.0.1 published 2026-10-27, glob 14.0.2
  2026-10-27, everything else older).

**External research (security topic — mandated):** all twelve GHSAs fetched
from the GitHub advisory API (`/advisories/<ghsa>` — ranges, patched
versions, CWEs quoted in the table). Dependabot alert detail endpoints
verified per-alert `vulnerable_version_range`, `first_patched_version`,
`relationship` (all transitive), `scope`. npm registry `versions`/`time`/
`dependencies` queried for every target version and every parent constraint
listed above; minimatch@11.0.1's CJS/ESM builds inspected directly
(`npm pack`) to establish the callable-vs-namespace API boundary.

**Community/functional discovery:** stacks are TypeScript/npm — covered by
built-in agents (no uncovered stack). Functional-overlap agent could not be
spawned in this harness; inline equivalent: the drain machinery is repo-owned
(`assert-dependabot-drain.py`), no community artifact applies.

## Proposed Solution

One PR, three edit groups, matching the #11646/#11780 grouped-bump shape.

### Group 1 — in-range transitive updates (`npm@11`)

Versions where the parent's declared range already admits the patched major:

- `cd apps/web-platform && npx --yes npm@11 update hono @hono/node-server
  ip-address fast-uri vitest` —
  `hono` → ≥4.13.11 (`^4.11.4` parent admits; resolves ~4.13.16),
  `@hono/node-server` → 2.1.5 (`^1.19.9 || ^2.0.5` parent admits the major
  crossing; this is what Dependabot's own #11468 does),
  `ip-address` → ≥10.7.4 (`^10.2.0` admits; resolves 10.7.5),
  `fast-uri` → ≥3.1.9 (`^3.0.1` admits; 3.1.9 is the latest 3.x),
  `vitest` → 4.1.12 (`^4.1.11` devDep admits; vitest@4.1.12 pins
  `@vitest/mocker@4.1.12` exactly — one bump clears both mocker alerts).
- `cd plugins/soleur/skills/pencil-setup/scripts && npx --yes npm@11 update
  @hono/node-server ip-address` — same MCP SDK chain → 2.1.5, 10.7.4+.
- Regenerate every lockfile with `npm install --package-lock-only` under
  `npm@11` afterwards — `lockfile-sync` regenerates all five and diffs, so
  an untouched-but-dirty lockfile still fails the PR.

### Group 2 — `overrides` for advisories with no patched release on the installed major

Following the zod (scoped) / undici (exact) precedents:

- `apps/web-platform/package.json` `overrides` +=
  `"rimraf": { "glob": "^14.0.2" }`,
  `"@sentry/bundler-plugins": { "glob": "^14.0.2" }` — scoped, matching the
  zod idiom; the glob advisory does NOT cover majors <9, so a blanket would
  over-reach a legitimately-fine older line.
  and `"minimatch": "^11.0.1"` — **blanket**, deliberately: GHSA-g3hv names
  EVERY version below 11.0.1 vulnerable, so there is no legitimately
  vulnerable-free old line to preserve; eight-plus parents pin <11 today and
  any future addition would reintroduce a copy the drain guard's
  completeness sweep would then have to catch after the fact.
- `package.json` (root) `overrides` += `"markdownlint-cli": { "minimatch":
  "^11.0.1" }`, `"@11ty/recursive-copy": { "minimatch": "^11.0.1" }` —
  scoped, matching that file's existing per-parent idiom.
- `pen-cli/package.json` `overrides` += `"minimatch": "11.0.1"` — exact
  pin, matching the `undici: "8.12.2"` precedent for the engine-pinned
  lockfile; the row comment follows the undici form ("drop the override when
  the engine's own range reaches it; bump only after a green
  `engine-contract-probe.sh`").

### Group 3 — drain-guard ratchet (`scripts/assert-dependabot-drain.py` + `.test.sh`)

- `WATCHED_PACKAGES` += `minimatch`, `glob`, `@vitest/mocker` (14→17).
- `REQUIRED` — retarget 2 rows and raise 9 floors, add 5 rows (36→41):
  - `("web-platform","@hono/node-server",1,"1.19.15")` →
    `("web-platform","@hono/node-server",2,"2.1.3")` — GHSA-rmxm has no
    patched 1.x; the line is evacuated, not patched.
  - `("pencil-setup","@hono/node-server",1,"1.19.15")` → same retarget.
  - Floor raises on the same major: web-platform+pencil-setup `hono` 4
    `4.12.34`→`4.13.11`, `ip-address` 10 `10.5.1`→`10.7.4`, `fast-uri` 3
    `3.1.7`→`3.1.9`; pen-cli `@hono/node-server` 2 `2.0.10`→`2.1.3`
    (installed 2.1.5 already satisfies).
  - New: `("web-platform","minimatch",11,"11.0.1")`,
    `("root","minimatch",11,"11.0.1")`,
    `("pen-cli","minimatch",11,"11.0.1")`,
    `("web-platform","glob",14,"14.0.2")`,
    `("web-platform","@vitest/mocker",4,"4.1.12")` — the completeness sweep
    leaves no smaller set once the packages are watched (each is the only
    major present after the batch).
- `FLOOR_ANCHORS` — update `("hono",4)→4.13.11`,
  `("ip-address",10)→10.7.4`, `("fast-uri",3)→3.1.9`,
  `("@hono/node-server",2)→2.1.3`; **delete** `("@hono/node-server",1)`
  with a comment (no patched 1.x exists; the anchor's own check REDs on an
  anchor no row covers, so the delete is deliberate and documented); add
  `("minimatch",11):"11.0.1"`, `("glob",14):"14.0.2"`,
  `("@vitest/mocker",4):"4.1.12"`, each commented with its GHSA.
- `MIN_ROWS` 36→41, `MIN_RESOLVED` 36→41 (comment updated in the same
  style).
- `scripts/assert-dependabot-drain.test.sh` — fixture mirrors gain
  `("minimatch",11)` on web-platform/root/pen-cli, `("glob",14)` and
  `("@vitest/mocker",4)` on web-platform, and the web-platform/pencil-setup
  `("@hono/node-server",1)` fixture entries move to `2`; floor specs
  `MIN_ROWS:36→41`, `MIN_RESOLVED:36→41`; the anchor spec list updates
  `"@hono/node-server:2:2.0.10"`→`"2.1.3"` and gains
  `"hono:4:4.13.11" "ip-address:10:10.7.4" "fast-uri:3:3.1.9"
  "minimatch:11:11.0.1" "glob:14:14.0.2" "@vitest/mocker:4:4.1.12"`; the
  two mutate-arm expected substrings `floor of 36`→`floor of 41`;
  `MIN_ASSERTIONS` ratchets by the new spec-arm count (34→40), set to the
  CURRENT arm count in the same commit per its own comment convention.

## Technical Considerations

- **The override's runtime-risk surface is measured, not assumed.** The
  planning audit (Research Insights) shows every loaded consumer uses the
  v11-safe namespace API; the callable-v3 callers are installed-but-unloaded
  (eslint-plugin-* via the vestigial `eslint-config-next` devDep,
  `@eslint/eslintrc`'s legacy path). The empirical gate is `npm run lint` +
  the vitest suite + `npm ci --ignore-scripts` — a break is CI-visible and
  the fallback is recorded in `decision-challenges.md` (scoped exclusion
  where eliminable; Dependabot `dismiss` with reason + tracking issue for
  any copy no compatible resolution can reach — the likec4/zod "residual
  condition tracked rather than hidden" precedent).
- **`npm update` vs `install --package-lock-only`:** a plain regen does NOT
  move copies whose installed version already satisfies the parent range
  (`npm-transitive-dep-security-update-mechanics` learning) — the targeted
  `npm update <pkg>` form is required for Group 1; overrides DO force
  re-resolution on the first regen.
- **`@hono/node-server` 1→2 is upstream-sanctioned** (`^1.19.9 || ^2.0.5`
  in the MCP SDK dependency range and Dependabot's own proposed PR), unlike
  the `@likec4/core` zod override which was outside any declared range.
  The serveStatic double-decode fix pairs with `hono@4.13.11` (same
  advisory class, CWE-174).
- **glob 14 compat:** consumers use named exports (`glob`, `globSync`)
  retained in v14; glob@14's own `minimatch ^11.0.0` dep composes with the
  blanket minimatch override. rimraf@5 stays (gaxios wants `^5.0.1`); only
  its glob subtree is retargeted.
- **`.npmrc` `min-release-age=3`:** verified per-version publish dates
  (Research Insights) — nothing under the floor.
- **npm@11 / worktree conventions:** local npm 11.20.0 matches the CI pin;
  every lockfile's `"name"` field verified byte-identical to `origin/main`
  post-regen (learning 2026-05-27).
- **pen-cli engine contract:** the `pi-coding-agent` exact pin makes the
  override the only path; `engine-contract-probe.sh` green is the
  acceptance gate (undici-precedent comment retained).
- **Merge-queue note:** one PR keeps the cost at one ~50-min cycle (same
  rationale as #11646/#11780).
- **Dependabot drift risk:** re-run the alerts query at work time; a fresh
  alert between plan and merge is absorbed or deferred per severity and
  noted in the PR body.
- **Pillow:** no action beyond verifying `Pillow==13.0.0` on the branch
  (already on main) and noting #302's fixed state in the PR body.

## Files to Edit

- `apps/web-platform/package.json` — `overrides` += the two scoped glob
  entries + the blanket minimatch entry
- `apps/web-platform/package-lock.json` — regenerated (Group 1 + Group 2)
- `package.json` (root) — `overrides` += the two scoped minimatch entries
- `package-lock.json` (root) — regenerated
- `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` —
  `@hono/node-server`→2.x, `ip-address`→10.7.4+ via `npm update`
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json` —
  `overrides` += `"minimatch": "11.0.1"`
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package-lock.json` —
  regenerated
- `spike/package-lock.json` — regenerated only if `npm install
  --package-lock-only` produces drift (expected no-op)
- `scripts/assert-dependabot-drain.py` — WATCHED_PACKAGES, REQUIRED
  retargets/raises/adds, FLOOR_ANCHORS updates/add/delete, MIN_ROWS/
  MIN_RESOLVED
- `scripts/assert-dependabot-drain.test.sh` — fixture entries, floor specs,
  anchor specs, mutate-arm substrings, MIN_ASSERTIONS

## Files to Create

None.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix ALL currently-open Dependabot alerts" | Groups 1–3 + AC-1/AC-2 census | mapped |
| 2 | "13 npm medium + 2 npm low alerts across four lockfiles: hono + @hono/node-server … @vitest/mocker … ip-address … fast-uri … glob … minimatch" | Groups 1–2 + alert table | mapped |
| 3 | "1 pip medium alert: Pillow (EPS load(scale) / Ghostscript decompression-bomb bypass) in plugins/soleur/skills/gemini-imagegen/requirements.txt" | Premise finding: already `state: fixed` (Pillow==13.0.0 on main via #11646); AC-11 verify-note | mapped |
| 4 | "Per ADR-191 the drain-guard ratchet is required in the same PR: extend scripts/assert-dependabot-drain.py … and scripts/assert-dependabot-drain.test.sh anchor+floor spec lists" | Group 3 + AC-3 | mapped |
| 5 | "KNOWN MAIN BREAKAGE to verify first and fix if still red … Verify it is actually red before fixing" | Research finding (green 23/23) + AC-12 re-verification | mapped |
| 6 | "where an alert's package is transitive-only, follow the prior batch's procedure (npx --yes npm@11 update <pkg> … lockfile-only edits where a parent can't move)" | Groups 1–2 procedure + Technical Considerations | mapped |
| 7 | "package-lock.json changes must keep npm@11 regeneration conventions" | AC-4 | mapped |
| 8 | "reuse its guard contract, Observability block, and ratchet procedure" | Plan structure + Guard Contract + Observability sections | mapped |
| 9 | "OUT OF SCOPE … the next body-streams classifier re-evaluation … the likec4 1.60 pin-train bump, the hono 2.x compat migration" | Non-Goals | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `apps/web-platform` + `pencil-setup` `npm update` set | "npx --yes npm@11 update <pkg> for transitive bumps" | asked |
| `overrides` entries in three package.jsons | "Fix ALL currently-open Dependabot alerts" / "lockfile-only edits where a parent can't move" | asked — the override IS the repo's lockfile-only forcing mechanism for range-bound parents (zod/undici precedent); no advisory in this batch patches the installed major for glob/minimatch |
| Five lockfile regenerations | "package-lock.json changes must keep npm@11 regeneration conventions" | asked |
| `scripts/assert-dependabot-drain.{py,test.sh}` edits | "extend scripts/assert-dependabot-drain.py (WATCHED_PACKAGES / REQUIRED rows / FLOOR_ANCHORS / MIN_* bounds …) and scripts/assert-dependabot-drain.test.sh anchor+floor spec lists" | asked |
| `spike/package-lock.json` regen-if-drift | — | inferred — justification: the `lockfile-sync` CI job regenerates all five lockfiles and `git diff --exit-code`s them; skipping a drifted one fails the PR |
| Supersede note for open Dependabot PR #11468 | — | inferred — justification: it bumps the same package in the same lockfile this batch resolves; left alone it lands a redundant/conflicting diff post-merge |
| roster-entry-gate re-verification | "Verify it is actually red before fixing" | asked |

### Split Assessment

- Subsystems touched: 4 — `apps`, `plugins`, `scripts`, repo-root manifests
- Planned files: 10 | Estimated changed lines: ~80 non-lockfile + lockfile diffs (lockfile churn excluded from judgment — mechanical)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines → the root count nominally meets one threshold
- Recommendation: single PR — the multi-root shape IS the deliverable (one grouped-bump PR per #11646/#11780 precedent; the merge queue merges one entry per ~50-min cycle, so splitting would multiply the cost the batch exists to avoid).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — dependency-batch/tooling change.
Product/UX gate: the Files-to-Edit/Create lists contain no UI-surface path
(no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`); the
mechanical UI-surface override does not fire. Tier: NONE.

## User-Brand Impact

- **If this lands broken, the user experiences:** worst case a dev-toolchain
  break (eslint/vitest red in CI under a forced re-resolution) or a degraded
  adapter/pen-cli path — all caught by the named suites before merge and
  reversible by reverting the PR; no user-data path is touched.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure vector — the diff adds no data path; it *removes* fifteen
  known advisory vectors (two middleware-bypass classes, a code-injection
  class, ReDoS/DoS classes).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** worst-case breakage is a
  revertible toolchain regression caught by lint/test/build gates pre-merge
  — not a data-loss or breach path, which is the `single-user incident` bar.
- *Scope-out override:* `threshold: none, reason: the touched paths are
  manifest/lockfile/guard-table files only — no auth, schema, secret, or
  migration surface is edited`

## Observability

```yaml
liveness_signal:
  what: "Dependabot drain assertion — scripts/assert-dependabot-drain.py exit 0 over the five tracked lockfiles"
  cadence: "every test-all.sh suite run (CI) + on-demand"
  alert_target: "CI check failure on the PR (lockfile-sync / test-all)"
  configured_in: "scripts/assert-dependabot-drain.py; scripts/test-all.sh run_suite entries ~line 5565"

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
  - mode: "a vulnerable copy lingers under an un-overridden parent"
    detection: "the new major-line rows resolve (absent)->(found) on regen and the completeness sweep names the uncovered major"
    alert_route: "required CI check red on the PR"
  - mode: "lockfile drifts from package.json (overrides not regenerated)"
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

**Property.** Every installed copy of `hono`, `@hono/node-server`,
`ip-address`, `fast-uri`, `minimatch`, `glob`, and `@vitest/mocker` in every
tracked lockfile resolves at or above the first_patched_version of the
advisories this batch clears, and a regression to a still-vulnerable version
fails the guard loudly.

**Assembly.** The structural chokepoints are unchanged and are what this
edit feeds: `WATCHED_PACKAGES` (the package set the completeness sweep
quantifies over — 14→17), `REQUIRED` (the per-(manifest, package,
major-line) floor rows — 36→41), `FLOOR_ANCHORS` (the anti-lowering
mirror), the `MIN_ROWS`/`MIN_RESOLVED`/`MIN_LOCKS` anti-vacuity floors, and
the completeness sweep itself, which derives every `(manifest,
watched-package, major)` tuple present in the five lockfiles at run time.
Members (individual rows) drift as advisories land; the property holds over
whatever the tree enumerates — including a NEW vulnerable copy arriving
under a parent nobody overrode.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Reintroduce `minimatch@10.2.6` under any manifest (a watched package on a watched major below its row's floor — the found-worst check) | RED |
| 2 | Delete `minimatch` from `WATCHED_PACKAGES` while its rows remain (the guard's own dispatch: declared-vs-watched drift check) | RED |
| 3 | Add a second vulnerable copy after a compliant first — `minimatch@3.1.5` nested under a new parent alongside a top-level `minimatch@11.0.1` (the check compares worst-found, not first-found) | RED |
| 4 | Lower `("glob",14)` floor to `"14.0.1"` — a real release on the right major but below the advisory floor (FLOOR_ANCHORS two-place check) | RED |
| 5 | Re-add `("@hono/node-server",1)` to FLOOR_ANCHORS after its evacuation with no covering row (the anchor-without-row check catches a retarget half-done) | RED |
| 6 | Suite-side: keep the new anchors in the .py but drop them from `assert-dependabot-drain.test.sh`'s spec list (the three-file-edit property lapses) and the suite reports the missing spec arms | RED |
| 7 | Must-PASS input: `minimatch@11.0.3` nested under a new parent — a version ABOVE the floor the override permits, differing from the canonical 11.0.1 | PASS |

**Anchor.** The floor values are anchored to the advisory feed's
`first_patched_version` (GHSA ids in the row comments), not to the resolved
tree — weakening a floor requires editing `REQUIRED`, `FLOOR_ANCHORS`, and
`assert-dependabot-drain.test.sh` together, a three-file consistency check.

## Enhancement Summary

Deepen-plan pass executed inline (no agent-spawn capability in this harness —
documented in `decision-challenges.md`): halt gates 4.6–4.13 verified
mechanically (User-Brand Impact present and non-placeholder with the
`threshold: none` scope-out; Observability fields valid — `python3` probe
verb allowlisted, <15s, literal `expected_output`, no ssh; no PAT-shaped
vars; no UI surface; dep-bump so Encryption/Task-Design conditional gates do
not fire; `lint-guard-contract.py` green on the Guard Contract — 1 guard
entry, structural assembly, 7-row mutation matrix incl. own-dispatch,
second-member, suite-side, must-PASS, and anchor-without-row arms; single
unfenced Scope Check with every ask mapped and the two `inferred` items
justified; no `status: BLOCKED`). Verify-the-negative sweep: the plan's
negative claims (`imports NOTHING from eslint-config-next`, no FlatCompat,
callable-v3 callers installed-but-unloaded, no patched release on installed
minimatch/glob majors, spike lockfile clean of all seven packages, no
`export default` in minimatch@11 ESM) were each grepped against the tree or
the packed tarball — all confirmed with citations in Research Insights.
Key finding already folded in: the brief's Pillow alert #302 is already
`state: fixed` on main (verification-only), and the hono serveStatic alert
does NOT require the 2.x compat migration — 4.13.11 patches the 4.x line.
PR/issue citations verified live via `gh` during premise validation.

## Open Code-Review Overlap

None. Queried 96 open `code-review`-label issues on 2026-11-01; no issue
body names any planned file path (`apps/web-platform/package.json`, the
four lockfiles, `scripts/assert-dependabot-drain.{py,test.sh}`,
`requirements.txt`, `pencil-setup`).

## Acceptance Criteria

- [ ] AC-1 Every `hono` copy ≥4.13.11, every `@hono/node-server` copy ≥2.1.3
  (and none on major 1), every `ip-address` copy ≥10.7.4, every `fast-uri`
  copy ≥3.1.9, every `@vitest/mocker` copy ≥4.1.12 in all five tracked
  lockfiles — verified by a census of every lockfile `packages` key, not a
  top-level grep (closes alerts #284, #292, #293, #327, #340, #346–#349,
  #367, #373).
- [ ] AC-2 Zero `minimatch` copy below 11.0.1 and zero `glob` copy in
  9.0.0–14.0.1 anywhere in the five lockfiles — same census form (closes
  alerts #374–#377).
- [ ] AC-3 `scripts/assert-dependabot-drain.py` carries the three new
  watched packages, the two retargeted + nine raised + five new REQUIRED
  rows (MIN_ROWS/MIN_RESOLVED = 41), the updated/added/dropped anchors;
  `python3 scripts/assert-dependabot-drain.py` exits 0 and
  `bash scripts/assert-dependabot-drain.test.sh` is green with
  MIN_ASSERTIONS ratcheted to the new arm count.
- [ ] AC-4 All five `package-lock.json` files regenerated under `npm@11`
  (`npx --yes npm@11`); each lockfile's `"name"` field is byte-identical to
  `origin/main` (worktree-drift guard, learning 2026-05-27).
- [ ] AC-5 `cd apps/web-platform && npm run lint` (or the repo's eslint
  invocation) is green under the blanket `minimatch@11` override — the
  `@eslint/config-array`/`eslintrc` compat canary.
- [ ] AC-6 `cd apps/web-platform && npx vitest run` is green for at minimum
  the vitest-mocker-dependent shard and a representative suite slice; the
  full `test:ci` in CI is the outer net.
- [ ] AC-7 `cd apps/web-platform && npm run typecheck` and `npm run build`
  are green.
- [ ] AC-8 `npm ci --ignore-scripts` reproduces cleanly from the committed
  `apps/web-platform/package-lock.json`.
- [ ] AC-9 `bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh`
  is green under the `minimatch@11.0.1` pin (the pen-cli override gate,
  undici precedent).
- [ ] AC-10 `bash scripts/lint-dual-lockfile.sh`,
  `bash scripts/verify-lockfile-guards.sh`, and
  `bash scripts/lint-workflow-install-sites.sh` all exit 0; no
  `bun.lock`/`bunfig.toml [install]` tracked (ADR-191).
- [ ] AC-11 PR body carries the #11646-shape table (bump / package /
  from→to / manifest / method) naming each of the fifteen npm alerts, a
  line noting alert #302 (Pillow) already `fixed` on main, a line noting
  open Dependabot PR #11468 is superseded, plus a `## Changelog` section.
- [ ] AC-12 `cd apps/web-platform && npx vitest run
  test/cla-evidence/roster-entry-gate.test.ts` is green (verified 23/23 in
  planning; if it reds at work time, the fix lands as a distinct commit in
  this branch per the brief).
- [ ] AC-13 No changes to `.ts`/`.tsx`/`next.config.ts`/`middleware.ts`
  source — the batch is manifest + lockfile + guard-table only. (If the
  override-compat fallback forces a devDep graph change — e.g. dropping the
  vestigial `eslint-config-next` — this AC is amended in the PR rather than
  silently violated.)

## Test Scenarios

- Given the lockfiles before the batch, when a census enumerates every
  `packages` key named `minimatch`/`glob` across all five lockfiles, then
  every resolved minimatch is ≥11.0.1 and no glob in 9.0.0–14.0.1 remains —
  `integration`.
- Given `apps/web-platform/package.json` overrides, when `npm ls glob
  minimatch` (or the census) runs, then `rimraf` and
  `@sentry/bundler-plugins` subtrees resolve `glob@14.0.2+` and every
  minimatch resolves `11.0.1+` — `integration`.
- Given the forced re-resolution, when `npm run lint` runs, then eslint
  loads `@eslint/config-array`'s CJS entry (`require("minimatch").Minimatch`
  under v11) and no `import minimatch` default-export link error surfaces —
  `integration`.
- Given the `minimatch@11.0.1` pen-cli pin, when
  `engine-contract-probe.sh` runs, then the engine contract holds —
  `integration`.
- Given `vitest@4.1.12`, when `npx vitest run` executes, then
  `@vitest/mocker@4.1.12` is the resolved copy and suites pass — `unit`.
- Given the new drain rows, when a lockfile is mutated to reintroduce
  `minimatch@10.2.6`, then `assert-dependabot-drain.py` exits 1 naming the
  row — `unit` (guard drivable red).
- Given `npm ci --ignore-scripts` in `apps/web-platform`, then install
  reproduces cleanly from the committed lockfile — `integration`.
- Given the `@hono/node-server@2.x` bump under MCP SDK's declared range,
  when `npm run build` + the MCP-dependent suites run, then the server
  transport path is green — `integration`.

## Success Metrics

- All fifteen cited npm Dependabot alerts transition to closed/fixed after
  merge (the drain assertion is the merge-time proof; the API state is the
  lagging mirror). Alert #302 stays `fixed`.
- Zero regressions in lint, typecheck, build, and the named vitest suites.
- `lockfile-sync` CI job green on the PR.

## Dependencies & Risks

- **Blanket minimatch@11 override breaking a LOADED call path:** the audit
  says every loaded consumer is namespace-safe and the callable callers are
  unloaded, but this is the batch's real gamble — mitigated by AC-5/AC-6/AC-7
  and the recorded fallback (scoped exclusion → dismiss+tracking issue) in
  `decision-challenges.md`.
- **glob 13/14 override under rimraf + @sentry/bundler-plugins:** named
  export surface verified; the sentry plugin's `glob.glob` sourcemap path
  only executes during sentry-sourcemap upload builds — the build AC covers
  it.
- **npm@11 shape skew:** local npm 11.20.0 verified; CI pins `npm@11`.
- **Merge-queue serialization:** one PR = one ~50-min cycle.
- **New alert drift between plan and merge:** re-run the alerts query at
  work time; absorb or defer per severity, and note in the PR body.
- **pen-cli override under the pinned engine:** exact pin follows the
  undici precedent; `engine-contract-probe.sh` green is the gate.

## Non-Goals

- The next body-streams classifier re-evaluation (#11783 — waits on an
  upstream released fix).
- The likec4 1.60 pin-train bump (#11696).
- The hono 2.x compat migration — not needed: GHSA-5r4p-p66f-jhc7 patches
  on the 4.x line at 4.13.11.
- Pillow / requirements.txt — alert #302 already `fixed` on main.
- PR #11814's affected-index scope.
- Any `.ts`/`.tsx`/`next.config.ts`/`middleware.ts` source change.
- New guards, workflows, or tools — the existing drain machinery is
  extended, not replaced.

## References & Research

- Grouped-bump precedents: PR #11646 (batch 8), PR #11780 (critical/high),
  PR #9198 (first drain + ratchet learning).
- Superseded Dependabot PR: #11468 (`@hono/node-server` 1→2 web-platform).
- Prior-batch plan: `knowledge-base/project/plans/archive/20261031-181546-2026-10-31-chore-batch-dependabot-critical-high-fixes-plan.md`;
  spec: `knowledge-base/project/specs/archive/20261031-181546-feat-one-shot-dependabot-critical-batch/`.
- Governing ADR: `knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md`.
- Guard contract: `scripts/assert-dependabot-drain.py`,
  `scripts/assert-dependabot-drain.test.sh`,
  `scripts/lint-dual-lockfile.sh`, `scripts/lint-workflow-install-sites.sh`,
  `scripts/verify-lockfile-guards.sh`, `scripts/test-all.sh` (suite
  registration ~line 5565).
- Canonical procedure: `plugins/soleur/skills/work/references/work-lockfile-bumps.md`.
- Learnings: `2026-04-07-npm-transitive-dep-security-update-mechanics.md`,
  `2026-09-29-dependabot-remediation-must-ratchet-drain-guard-floors.md`,
  `2026-05-22-npm-version-pin-required-for-lockfile-sync-gate.md`,
  `2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md`.
- Advisories: GHSA-5r4p-p66f-jhc7, GHSA-xp26-3454-mjgp, GHSA-qxg6-89mg-rqv8,
  GHSA-rxp7-6hxx-x8q5, GHSA-333x-w4r6-6crp, GHSA-wjr9-j795-jxcr,
  GHSA-xhq7-xmqj-769h, GHSA-w74x-v6f9-j3xg, GHSA-rmxm-3fg6-px4f,
  GHSA-3g3m-2fjr-6pw4, GHSA-g3hv-75wg-m249, GHSA-vx6w-vv9f-6gvg (fixed).
- Umbrella tracking issue: #10857; out-of-scope trackers: #11783, #11696.
