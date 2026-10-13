<!-- iac-routing-ack: plan-phase-2-8-reviewed (lockfile + guard-constant change; introduces no infrastructure) -->
---
title: "chore(deps): resolve root js-yaml and liquidjs audit advisories"
date: 2026-09-29
slug: chore-deps-resolve-root-js-yaml-and-liquidjs-audit-advisories
branch: feat-one-shot-8065-dep-audit-advisories
issue: 8065
closes: 8065
type: chore
lane: single-domain
brand_survival_threshold: none
labels: [type/security, type/chore, domain/engineering]
status: planned
---

# chore(deps): Resolve root js-yaml and liquidjs audit advisories 🔒

## Overview

Issue #8065 (filed 2026-09-11) reports two high-severity packages in the root
`package-lock.json` under `npm audit --json`: `js-yaml` (merge-key limits not
bounding CPU for empty merge sources) and `liquidjs` (resource-limit bypasses
in array filters; `strip_html` infinite loop).

**Half the issue is already resolved on `main`.** Dependabot PR #7970 (merged
2026-09-24) bumped `js-yaml` to `4.3.2` (top-level) and `3.15.2` (nested under
`gray-matter`) — exactly the `first_patched_version`s of
`GHSA-2883-xcg3-v3hh` (`>=4.0.0 <4.3.2` and `>=3.0.0 <3.15.2`). A live
`npm audit --json` run today flags **only `liquidjs`**; `js-yaml` no longer
appears. The residual js-yaml work is not a bump — it is the drain-guard
ratchet #7970 skipped (`scripts/assert-dependabot-drain.py` still floors
js-yaml at `4.3.1`/`3.15.1`, *below* the new advisory's patched versions, so a
regression to a still-vulnerable copy would pass the guard silently).

**The liquidjs half is a transitive-only bump.** `node_modules/liquidjs`
`10.27.0` is pulled solely by `@11ty/eleventy@3.1.5` (`"liquidjs":
"^10.25.0"`). Three open HIGH advisories
(`GHSA-g357-x5c3-c72p`, `GHSA-m7fp-h3p4-hr49`, `GHSA-4r6h-5v86-94p3`) are all
cleared by `first_patched_version` **10.27.2** (the strictest of the three);
`npm@11 update liquidjs` resolves to **10.29.0**, inside the declared range —
no `package.json` or `overrides` change is needed on the primary path.

### Premise Validation (Phase 0.6)

- **Issue #8065 OPEN, no closing PR** (`gh issue view 8065`). Labels:
  `priority/p2-medium`, `type/chore`, `domain/engineering`, `type/security`.
  Draft scaffold PR #9223 exists on this branch.
- **Cited premise partially stale — verified, not assumed.** The issue's
  js-yaml claim held on 2026-09-11 (installed copies were `4.3.1`/`3.15.1`);
  PR #7970 (`chore(deps): bump js-yaml`, merged 2026-09-24) already landed
  `4.3.2`/`3.15.2` in **both** the root and `apps/web-platform` lockfiles.
  `npm audit --json` today (2026-09-29, root): `total: 1`, `liquidjs` only.
  Plan response: the issue is *not* re-scoped — AC accepts "verify resolved"
  for js-yaml — but the guard ratchet for the advisory's *new* floors is this
  PR's job (see the 2026-09-29 ratchet learning).
- **Advisory records re-derived live** via `gh api
  "/advisories?ecosystem=npm&affects=<pkg>"` (2026-09-29):
  - `js-yaml` `GHSA-2883-xcg3-v3hh` (HIGH): two vulnerable ranges,
    `>=4.0.0 <4.3.2` **and** `>=3.0.0 <3.15.2` — installed `4.3.2` + `3.15.2`
    are exactly patched on both lines.
  - `liquidjs`: `GHSA-g357-x5c3-c72p` (`pop` filter `memoryLimit` bypass,
    `<=10.27.0`, patched 10.27.1), `GHSA-m7fp-h3p4-hr49` (`strip_html`
    infinite loop, `>=10.26.0 <10.27.1`, patched 10.27.1),
    `GHSA-4r6h-5v86-94p3` (`join` filter resource exhaustion, `<=10.27.1`,
    patched 10.27.2). No published advisory covers `>=10.27.2`; latest stable
    is `10.29.0` (`11.0.0-alpha.1` is a prerelease — not a target).
  - `liquidjs` exists in **only** the root lockfile — absent from
    `apps/web-platform`, `pencil-setup/scripts`, and `spike` lockfiles
    (verified by scanning `packages` keys in all four).
- **Dependabot state:** zero open Dependabot alerts
  (`gh api repos/:owner/:repo/dependabot/alerts?state=open` → `[]`) and zero
  open Dependabot PRs — these advisories arrived via the npm-audit feed, not
  Dependabot. No `Supersedes` line is needed; nothing to supersede.
- **npm@11 pin verified:** `.github/workflows/ci.yml` `lockfile-sync` job runs
  `npm install -g npm@11`, regenerates all **four** lockfiles
  (`apps/web-platform`, root, `pencil-setup/scripts`, `spike`), and
  `git diff --exit-code`s them. All `package-lock.json` writes go through
  `npx --yes npm@11 …`.
- **Worktree name-rewrite edge N/A:** root `package.json` carries
  `"name": "soleur"`, so npm cannot infer a worktree directory name into the
  lockfile (the 2026-05-27 learning applies only when `name` is absent —
  the `lockfile-sync` job's npm-pin comment block in ci.yml records that
  repair). Verify anyway: `git diff` on the lockfile's top-level `"name"`
  must be empty.
- **Target is the root lockfile, not `apps/web-platform`'s** — the task's
  premise check is confirmed: `liquidjs`/`js-yaml` here are root-manifest
  packages (the eleventy docs toolchain + `gray-matter`/`markdownlint-cli`
  chains); #9198 fixed the *other* manifests (`fast-uri`/`ip-address`).

### Property List / Cut List (Phase 0.6b)

**Properties this change must buy:**

1. `npm audit --json` on the root lockfile reports **zero** vulnerable
   packages (js-yaml verified resolved; liquidjs ≥ 10.27.2 installed).
2. A future regression to a *still-vulnerable* `js-yaml`/`liquidjs` version
   makes `scripts/assert-dependabot-drain.py` RED — the guard's floors encode
   the strictest `first_patched_version` per (manifest, package, major).
3. The docs toolchain still builds (`npm run docs:build` exercises the bumped
   eleventy/liquidjs install).

**Mechanisms the issue named vs. what already exists:**

| Mechanism | Property bought | Disposition |
|---|---|---|
| Bump js-yaml in root lockfile | Property 1 (js-yaml arm) | **Cut — already done by #7970.** Installed copies are exactly the patched versions; re-bumping is a no-op. The audit-confirm step replaces it. |
| `npx --yes npm@11 update liquidjs` | Property 1 (liquidjs arm) | **Adopted** — the documented npm@11 transitive-bump path (`work-lockfile-bumps.md` header). |
| `overrides.liquidjs` pin in root `package.json` | Same | **Fallback only** — single deduped node at a resolvable-in-range version; an override buys nothing `npm update` doesn't and persists as cleanup debt. Used only if `npm update` no-ops (2026-04-07 silent-no-op class). Adding it fires `cq-before-pushing-package-json-changes`. |
| Ratchet drain-guard `REQUIRED`/`FLOOR_ANCHORS` for js-yaml (3.x→3.15.2, 4.x→4.3.2, all manifests carrying those lines) | Property 2 (js-yaml arm) | **Adopted** — required by the guard's own header ("Add an anchor whenever an advisory forces a floor up") and the 2026-09-29 learning; #7970 left floors below GHSA-2883's patched versions. |
| Add `liquidjs` to `WATCHED_PACKAGES` + a `("root","liquidjs",10,"10.27.2")` row + `("liquidjs",10)` anchor | Property 2 (liquidjs arm) | **Adopted** — a remediated package not in the watched set has no regression floor at all; mirrors the #9198 ratchet shape. |
| Extend the test's FLOOR_ANCHORS source-grep spec list to the anchors this PR moves/adds (`js-yaml:3:3.15.2`, `js-yaml:4:4.3.2`, `liquidjs:10:10.27.2`) | Property 2 durability | **Adopted** — the test's own comment ("lowering a threshold AND its anchor together is a three-file edit") describes the intent; today only brace-expansion anchors are grep-pinned. |
| New CI guard / new audit workflow | Property 1 | **Cut** — `lockfile-sync` + `assert-dependabot-drain-live` (test-all.sh:3716) already cover this surface. |
| ADR / C4, IaC, Encryption sections | — | **Cut** — dependency bump: no architectural decision (Phase 2.10 skip condition), no infrastructure (Phase 2.8), no store/connection (Phase 2.11). |

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified 2026-09-29) | Plan response |
|---|---|---|
| "js-yaml … high-severity" in root lockfile | Resolved on `main` by #7970 (`4.3.2`/`3.15.2` = GHSA-2883's patched versions); absent from today's `npm audit` | Document as resolved-by-#7970 in the PR body; ratchet guard floors so the fix can't silently regress. |
| "liquidjs … high-severity" in root lockfile | Confirmed — `10.27.0` < strictest patched `10.27.2`; single copy under `@11ty/eleventy@3.1.5` | `npm@11 update liquidjs` → `10.29.0`. |
| "update affected root devDependencies **and applicable overrides**" | `overrides.js-yaml` is already `^4.3.2` and `gray-matter.js-yaml` `^3.15.1` resolves `3.15.2`; no liquidjs override needed on the primary path | **No `package.json` edit** — same disposition as #9198. Overrides stay as fallback documentation only. |

## Research Insights

**Relevant file paths (verified):**

- `package.json` — `devDependencies`: `@11ty/eleventy ^3.1.5`,
  `markdownlint-cli 0.49.1`, `markdown-it ^14.2.0`, `yaml ^2.8.2`;
  `overrides`: `js-yaml ^4.3.2`, `gray-matter.js-yaml ^3.15.1`,
  `brace-expansion ^1.1.16`, `markdownlint-cli.brace-expansion ^5.0.8`.
  `markdownlint-cli@0.49.1` declares `js-yaml ~5.2.1` but the top-level
  override resolves it to `4.3.2` (no nested copy) — deliberate; leave it.
- `package-lock.json` — `node_modules/liquidjs@10.27.0` (dev; sole consumer
  `node_modules/@11ty/eleventy`, `"liquidjs": "^10.25.0"`);
  `node_modules/js-yaml@4.3.2`;
  `node_modules/gray-matter/node_modules/js-yaml@3.15.2`.
- `scripts/assert-dependabot-drain.py` — `WATCHED_PACKAGES` (line ~37),
  `REQUIRED` (line ~50; root js-yaml rows at lines ~78–79, web-platform rows
  ~52–53), `FLOOR_ANCHORS` (line ~109), `MIN_ROWS`/`MIN_RESOLVED` = 20
  (lines ~219, ~227 — absolute floors; adding a row keeps them satisfied).
- `scripts/assert-dependabot-drain.test.sh` — `build_fixture` root fixture
  `rt = pkgs([...])` (~line 107) mirrors the `(manifest,pkg,major)` set — a
  new `("root","liquidjs",10,…)` row needs a `("liquidjs", 10)` fixture entry
  or the row resolves `(absent)`; the FLOOR_ANCHORS source-grep spec loop at
  ~line 222 currently pins only the three brace-expansion anchors.
- `.github/workflows/ci.yml` `lockfile-sync` (~line 538) — npm@11 pin +
  regenerate+diff over all four lockfiles.
- `scripts/test-all.sh` — registers the `scripts/assert-dependabot-drain-live`
  and `scripts/assert-dependabot-drain-unit` suites (grep anchor:
  `assert-dependabot-drain`); `scripts/lib/test-affected-paths.sh` and
  `scripts/suite-shard-legs.tsv` name the same suites for shard routing —
  suite names are unchanged by this plan, so no edit is needed there.
- `eleventy.config.js` — `INPUT = "plugins/soleur/docs"`; `docs:build` (`npx
  @11ty/eleventy`) loads liquidjs as a registered template engine — the build
  is the runtime regression surface for the bump.

- **Prior liquidjs remediation precedent:**
  `knowledge-base/project/plans/2026-05-27-fix-liquidjs-dependabot-vulnerabilities-plan.md`
  (`npm update liquidjs` inside eleventy's `^10.25.0`, lockfile-only, docs
  build as the consumer check) — same shape as this one; the drain-guard
  ratchet is the step that plan predates.
- **Adjacent stale comment noted, deliberately not edited:**
  `apps/web-platform/test/eslint-config.test.ts` "carries no blanket
  brace-expansion override" test carries a comment citing root's
  `"js-yaml": "^4.3.1"` — already stale today (actual `^4.3.2`), and a
  descriptive aside, not an assertion. Out of scope to keep the diff off the
  web-platform tree; flag at review if folded in.

**Institutional learnings applied:**

- `learnings/workflow-patterns/2026-09-29-dependabot-remediation-must-ratchet-drain-guard-floors.md`
  — the ratchet is part of the fix, in the same diff (this is why the js-yaml
  floors move even though the lockfile bump already landed).
- `work-lockfile-bumps.md` — `npx --yes npm@11 update <pkg>` + `npm ci
  --ignore-scripts`; ratchet directive; npm@11-only.
- `2026-04-07` npm-transitive-mechanics learning — `npm update` can silently
  no-op → Phase 3 asserts the resolved version, not the exit code; surgical
  3-field fallback documented below.
- `2026-05-27` worktree name-rewrite learning — N/A (`name` present) but the
  diff check is still prescribed.
- Idempotency-probe ordering (same 2026-09-29 learning, Session Errors #1):
  a `git diff --exit-code` idempotency check is meaningful only as
  before/after on the *regenerated* file or post-commit — the plan sequences
  it after the bump is staged/committed.

**Verified facts for the implementer (all probed live 2026-09-29):**

- `npm view liquidjs@10.29.0 dist.integrity` →
  `sha512-pCVOhs6FLAR8su3ItJ07diN26t6W5dHQRnmTMy8HPyTFuv1+oSCVJIGp5pGjfQyOZfh50KswvKtMTp6p4JEIdw==`
- `npm view liquidjs@10.27.2 dist.integrity` →
  `sha512-kvknfAEtOHjHkAAv7GxLEJh8ghpMQm3Fc4uWVyF7hERSTsSRsdC7saWs0p5aDG7GDcWsu5o+T4232O+8KZO55w==`
- `npm view @11ty/eleventy version` → `3.1.6` (installed `3.1.5`; bumping
  eleventy is NOT required — `^10.25.0` already admits `10.29.0`. Optional
  hygiene, deliberately out of scope to keep the diff surgical.)
- `npm audit --json` (root, pre-change): `{"high":1,"total":1}` — liquidjs
  only.
- Labels `type/security`, `type/chore`, `domain/engineering`, `dependencies`
  all exist.

**Assert-floors probe for Phase 3** (mirrors the #9198 plan's shape):

```bash
node -e '
const fs=require("fs");
const lock=JSON.parse(fs.readFileSync("package-lock.json","utf8"));
const cmp=(a,b)=>{const pa=a.split(".").map(Number),pb=b.split(".").map(Number);
  for(let i=0;i<3;i++){if((pa[i]||0)!==(pb[i]||0))return (pa[i]||0)-(pb[i]||0);}return 0;};
let bad=0;
for(const [k,v] of Object.entries(lock.packages||{})){
  if(/(^|\/)liquidjs$/.test(k) && cmp(v.version,"10.27.2")<0){console.log("VULN liquidjs",k,v.version);bad++;}
}
console.log(bad===0?"OK: no vulnerable liquidjs remains":"FAIL: "+bad+" vulnerable node(s)");
process.exit(bad?1:0);
'
```

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open` (2026-09-29)
and searched bodies for `package-lock.json`, `scripts/assert-dependabot-drain.py`,
`scripts/assert-dependabot-drain.test.sh`, `package.json`. One hit, #2963
("review: introduce Supabase typegen for ConversationPatch drift resistance"),
names `package.json` generically for an unrelated `apps/web-platform` concern —
acknowledged, not an overlap.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — both
  packages are devDependency-tree transitive (docs build toolchain). A bad
  resolution surfaces pre-merge as a red `lockfile-sync`, drain-guard, or
  docs-build check; no route, page, or runtime behavior changes. If the docs
  build itself broke post-merge, the soleur.ai docs site would fail to
  publish — caught by `deploy-docs.yml`/CI before deploy.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A —
  this PR *removes* exposure (DoS surface in the docs build toolchain's YAML
  and Liquid parsers). It introduces no new data surface.
- **Brand-survival threshold:** none.
  `threshold: none, reason: lockfile + guard-constant change with no runtime
  code change; no touched path matches the preflight Check-6 sensitive-path
  regex (no apps/web-platform server/api/infra/lib surface, no doppler file,
  no credential workflow), and the change is CI-gated pre-merge.`

## Implementation Phases

> **Golden constraint:** every `package-lock.json` write goes through
> **npm@11** (`npx --yes npm@11 …`). No `package.json` edits on the primary
> path — patched versions are reachable inside declared ranges
> (`liquidjs ^10.25.0` ← eleventy; `js-yaml` overrides already satisfied).

### Phase 1 — Bump `liquidjs` in the root lockfile (npm@11)

```bash
cd "$(git rev-parse --show-toplevel)"   # worktree root — package.json sits here
npx --yes npm@11 update liquidjs
```

Expected: `node_modules/liquidjs` `10.27.0 → 10.29.0` (latest inside
`^10.25.0`; `>=10.27.2` required). Verify the diff touches only the liquidjs
node(s) and that the lockfile `"name": "soleur"` field is unchanged
(`git diff package-lock.json | grep '"name"'` → empty).

**Fallback A (npm-update silent no-op, 2026-04-07 class):** surgical 3-field
edit of the `node_modules/liquidjs` entry — `version: "10.29.0"`,
`resolved: "https://registry.npmjs.org/liquidjs/-/liquidjs-10.29.0.tgz"`,
`integrity: "sha512-pCVOhs6FLAR8su3ItJ07diN26t6W5dHQRnmTMy8HPyTFuv1+oSCVJIGp5pGjfQyOZfh50KswvKtMTp6p4JEIdw=="` — then
`npx --yes npm@11 ci --ignore-scripts` (validates the sha against the
registry tarball).

**Fallback B (only if A can't hold — e.g. npm insists on re-resolving):**
add `"liquidjs": "^10.27.2"` to root `package.json` `overrides` and
`npx --yes npm@11 install --package-lock-only`. This makes `package.json` a
touched file — `cq-before-pushing-package-json-changes` then requires the
lockfile regenerated under npm@11 in the same commit; record in the PR body
that the override is temporary cleanup debt.

### Phase 2 — Ratchet `scripts/assert-dependabot-drain.py`

In `REQUIRED`: set the four js-yaml rows to GHSA-2883's strictest patched
versions — `("web-platform","js-yaml",3)` `3.15.1→"3.15.2"`,
`("web-platform","js-yaml",4)` `4.3.1→"4.3.2"`, `("root","js-yaml",3)`
`3.15.1→"3.15.2"`, `("root","js-yaml",4)` `4.3.1→"4.3.2"` — and add
`("root","liquidjs",10,"10.27.2")` (strictest patched of the three liquidjs
advisories). In `WATCHED_PACKAGES`: add `"liquidjs"`. In `FLOOR_ANCHORS`:
`("js-yaml",3)`→`"3.15.2"`, `("js-yaml",4)`→`"4.3.2"`, and add
`("liquidjs",10): "10.27.2"` (anchor keying is per (package,major) across
manifests — both js-yaml anchors now cover the root AND web-platform rows,
which is why all four rows must move together). Update the
`MIN_ROWS`/`MIN_RESOLVED` comments so their row arithmetic reflects 21 rows
(the floor values stay `20` — they are lower bounds, not exact counts).

In `scripts/assert-dependabot-drain.test.sh`: add `("liquidjs", 10)` to the
`rt` fixture package list in `build_fixture` (the fixture mirrors the
`(manifest,pkg,major)` set — the new row must resolve, not print `(absent)`),
and extend the FLOOR_ANCHORS source-grep `spec` list (~line 222) with
`"js-yaml:3:3.15.2" "js-yaml:4:4.3.2" "liquidjs:10:10.27.2"` so lowering these
anchors is the three-file edit the guard's design intends. No assertion-count
floor changes needed (`MIN_ASSERTIONS` floors passes, which grow
automatically).

### Phase 3 — Verify

```bash
npx --yes npm@11 ci --ignore-scripts          # prod-fidelity install, integrity-checked
npm audit --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["metadata"]["vulnerabilities"])'
# expect: {'info': 0, 'low': 0, 'moderate': 0, 'high': 0, 'critical': 0, 'total': 0}
npm run docs:build                            # exercises the bumped eleventy/liquidjs tree
python3 scripts/assert-dependabot-drain.py    # 21 rows, all OK
bash scripts/assert-dependabot-drain.test.sh  # mutation battery stays green
node -e '<assert-floors probe from Research Insights>'   # prints OK
```

Then idempotency (post-commit or as before/after on the regenerated file —
per the 2026-09-29 Session-Error learning): `npx --yes npm@11 install
--package-lock-only` produces no new `git diff` on `package-lock.json`;
`git status --short -- '**/package.json'` is empty (unless Fallback B fired).
Root checks: `bash scripts/test-all.sh` — run locally if machine contention
allows; the required `test` CI context is the backstop (precedent #9198
deferred the full battery to CI at operator direction — record whichever ran
in the PR body).

### Phase 4 — Ship

- One commit on `feat-one-shot-8065-dep-audit-advisories`: `package-lock.json`,
  `scripts/assert-dependabot-drain.py`, `scripts/assert-dependabot-drain.test.sh`.
- PR #9223 body: advisory table (GHSA → range → patched → resolved version),
  `Closes #8065`, labels `type/security` + `type/chore` + `domain/engineering`
  (+ `dependencies`), and a "js-yaml resolved by #7970; this PR ratchets the
  guard" note so reviewers don't hunt for a js-yaml lockfile diff.
- Mark ready → `gh pr merge --auto` per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

## Observability

Detection technically does not fire (no Files-to-Edit under
`apps/*/server|src|infra` or `plugins/*/scripts`, no new infra surface) — the
section is emitted for parity with the #9198 precedent and because the touched
guard IS this repo's observability surface for dependency drift.

```yaml
liveness_signal:
  what: "no new runtime surface — a transitive lockfile bump plus guard-constant updates add no service; the live signal is the drain guard + audit feed"
  cadence: per-PR (CI) + per-run (scripts/test-all.sh suite entries assert-dependabot-drain-live/-unit)
  alert_target: GitHub PR check failure
  configured_in: "scripts/test-all.sh:3716-3722 — existing suite registrations (this change adds no new monitor)"
error_reporting:
  destination: GitHub Actions CI (lockfile-sync + test suite) — a regression fails the PR check loudly; npm audit / GitHub advisory feed surfaces any residual vulnerable version
  fail_loud: true — CI checks are required; a red run blocks merge.
failure_modes:
  - mode: lockfile regenerated with wrong npm major (shape drift)
    detection: CI lockfile-sync job git diff --exit-code across all four lockfile dirs
    alert_route: PR check failure (blocks merge)
  - mode: liquidjs bump not actually reached (still <=10.27.1)
    detection: assert-floors node probe (Phase 3) + assert-dependabot-drain-live suite + npm audit in the AC
    alert_route: pre-merge Phase-3 gate
  - mode: drain-guard floor left below advisory patched version (silent re-admission class)
    detection: assert-dependabot-drain.test.sh mutation battery (lowered-floor arms) + FLOOR_ANCHORS source-grep specs
    alert_route: PR check failure (blocks merge)
  - mode: docs build regression from the liquidjs bump
    detection: npm run docs:build + deploy-docs pipeline
    alert_route: PR check failure / failed docs deploy run
logs:
  where: GitHub Actions run logs (per-PR)
  retention: GitHub default (Actions logs ~90 days)
discoverability_test:
  command: python3 scripts/assert-dependabot-drain.py
  expected_output: "drain assertion"
```

## Domain Review

**Domains relevant:** engineering

Engineering-only dependency-hygiene change: root lockfile + drain-guard
constants. No UI surface (mechanical override scan: no `components/**`,
`app/**/page.tsx`, or `app/**/layout.tsx` in Files to Edit/Create →
Product/UX Gate **NONE**), no infrastructure (Phase 2.8 — no new resource,
secret, vendor, or process), no regulated-data surface (Phase 2.7 — lockfiles
and a Python guard are not schema/auth/API/`.sql`; no (a)–(d) trigger: no new
LLM/external-API processing, threshold is `none`, no new cron, no new
artifact-distribution surface), no architectural decision (Phase 2.10 skip —
a dependency bump + guard ratchet cannot mislead an ADR/C4 reader), no
encryption posture change (Phase 2.11 skip — dep bump), no new guard
delivered (Phase 2.12 — the drain guard is *re-tuned*, not authored; its
existing mutation battery is the guard contract's mechanical enforcement and
is exercised by Phase 3).

**Degradation note (pipeline context):** this `soleur:plan` run executes as a
subagent without Task-spawn capability. The Phase-1 fan-out
(`repo-research-analyst`, `learnings-researcher`), Phase 1.5b
`functional-discovery`, Phase 2.5 domain-leader spawn, Phase 3
`spec-flow-analyzer`, Phase 4.5 advisor consult, and Plan Review's reviewer
panel all ran **inline** in this session against the same primary sources
(`gh api` advisory records, npm registry, lockfile/package.json inspection,
guard + test source reads, the #9198/#7970 git history, learnings corpus).
Coverage disclosure: `Reviewed-Coverage: sequential-fallback` — no
independent reviewer pass ran; the domain sweep was a single semantic pass by
the planner. Community Discovery (Phase 1.5) skipped: no uncovered stacks —
npm/Node/TypeScript are built-in-covered. Functional Overlap (1.5b):
inapplicable — this is repo-internal remediation of committed artifacts, not
functionality a community agent could cover; recorded here because the agent
could not be spawned.

### Engineering

**Status:** reviewed (inline — domain leader Task unavailable in subagent
context)
**Assessment:** Mechanical security chore on the docs-build dependency tree.
The load-bearing subtleties are (1) js-yaml needs no bump — only a guard
ratchet, (2) the drain guard's anchors key per (pkg,major) across manifests,
so the web-platform js-yaml rows must ratchet too even though this PR touches
no web-platform file otherwise, (3) the fixture in
`assert-dependabot-drain.test.sh` must mirror the new liquidjs row.

## Acceptance Criteria

### Pre-merge (PR #9223)

- [ ] `package-lock.json`: `node_modules/liquidjs` resolves `>= 10.27.2`
      (expected `10.29.0`); no `liquidjs < 10.27.2` node remains. Lockfile
      `"name"` field still `"soleur"`.
- [ ] `npm audit --json` on the root lockfile reports
      `{"high":0,"critical":0,"total":0}` — js-yaml AND liquidjs both absent
      (or any residual is documented in the PR body with its exact upstream
      constraint, per the issue AC).
- [ ] `scripts/assert-dependabot-drain.py` exits 0: js-yaml floors at
      `3.15.2`/`4.3.2` on both root and web-platform rows, a
      `("root","liquidjs",10,"10.27.2")` row resolves OK, `liquidjs` in
      `WATCHED_PACKAGES`, anchors `("js-yaml",3)=3.15.2`,
      `("js-yaml",4)=4.3.2`, `("liquidjs",10)=10.27.2`.
- [ ] `bash scripts/assert-dependabot-drain.test.sh` passes, including the
      liquidjs fixture entry and the three new anchor-grep specs.
- [ ] `npm run docs:build` succeeds.
- [ ] **No `package.json` modified** — `git diff --quiet origin/main...HEAD --
      '**/package.json'` (merge-base form, not the moving tip) and
      `git status --short -- '**/package.json'` empty (unless documented
      Fallback B fired; then the override + reason are in the PR body).
- [ ] lockfile-sync idempotency: `npx --yes npm@11 install --package-lock-only`
      produces no `git diff` on `package-lock.json` (evaluated post-bump per
      the baseline-ordering learning).
- [ ] `npx --yes npm@11 ci --ignore-scripts` clean (integrity validated).
- [ ] Root checks: `bash scripts/test-all.sh` passes locally OR the required
      `test` CI context passes on the PR (precedent: #9198 deferred the
      battery to CI under machine contention — PR body records which).
- [ ] PR body maps each advisory → patched floor → resolved version, states
      `Closes #8065`, and notes js-yaml was resolved by #7970 (this PR carries
      the guard ratchet, not the bump).

### Post-merge (automatic / verification-only)

- [ ] After merge, `npm ci --ignore-scripts && npm audit --json` on `main`'s
      root lockfile reports zero vulnerabilities.
- [ ] `python3 scripts/assert-dependabot-drain.py` on `main` stays green.

## Sharp Edges

- **npm@11 pin is load-bearing** — any other npm major produces a divergent
  lockfile shape and fails `lockfile-sync`. Always `npx --yes npm@11 …`.
- **`npm update` may silently no-op on a transitive copy** (2026-04-07
  learning) — a green exit code is not evidence. The Phase-3 version
  assertion is the proof; Fallback A is the surgical 3-field edit with the
  verified integrity sha above; never `npm install <pkg>@<ver> --no-save`
  (that flag blocks the lockfile write too).
- **Do not "fix" js-yaml again** — it is already at the patched versions
  (#7970). The risk here is a reviewer expecting a js-yaml lockfile diff that
  does not exist; the PR body must say so explicitly. The js-yaml work is the
  *floor ratchet*: `4.3.1`/`3.15.1` remain vulnerable to GHSA-2883 and would
  pass the guard today.
- **FLOOR_ANCHORS key per (package,major), not per manifest** — ratcheting
  the js-yaml anchors forces the *web-platform* rows to move too. Do not
  ratchet only the root rows; the anchor check iterates every matching row
  and would RED on the un-ratcheted sibling.
- **The test fixture mirrors the row set** — add `("liquidjs", 10)` to the
  `rt` fixture or the new REQUIRED row prints `(absent)`; harmless today
  (resolved-count floor is 20 < 21) but breaks the deliberate mirror and
  leaves the row untested-by-shape.
- **Do not bump `@11ty/eleventy` to `3.1.6` in this PR** — not needed for the
  advisories; keep the diff surgical. (`^10.25.0` already admits the fix.)
- **`npm update liquidjs` must not upgrade other packages** — verify the diff
  touches only liquidjs entries; if npm pulls unrelated bumps, reset and use
  Fallback A.
- **liquidjs prerelease exists** — `11.0.0-alpha.1` is published; `^10.25.0`
  cannot reach it, but do not force it via overrides: stay on the 10.x line.
- **The merge-base is the diff reference, not the tip** — "this PR does not
  modify `package.json`" is checked with `git diff origin/main...HEAD`; a
  sibling merge touching `package.json` on `main` would false-red the
  two-dot form.
- **Idempotency check ordering** — run the `--package-lock-only` diff check
  only after the bump is committed/staged (or snapshot before/after); a
  `git diff` against pre-bump HEAD always "fails" by design (2026-09-29
  Session-Error learning).
- **`gh` is not a Check-10 probe verb** — audit-confirmation uses `node` /
  `python3` probes; the Dependabot/alerts re-check (if any appear post-merge)
  is a human/AC step, not the discoverability probe.
- A plan whose `## User-Brand Impact` section is empty, placeholder, or omits
  the threshold fails `deepen-plan` Phase 4.6 — this plan's section is
  complete (threshold `none` + reason bullet).

## Test Scenarios

1. **Resolution correctness:** after Phase 1, `node_modules/liquidjs` in
   `package-lock.json` reads `10.29.0` (≥ `10.27.2`); assert-floors probe
   prints `OK`.
2. **Audit clean:** `npm audit --json` → `total: 0` (js-yaml absent because
   `4.3.2`/`3.15.2` are at GHSA-2883's patched versions; liquidjs absent
   because `10.29.0` > all three ranges' ceilings).
3. **Guard ratchet:** `python3 scripts/assert-dependabot-drain.py` prints 21
   rows OK; mutating a js-yaml row back to `4.3.1` or dropping the liquidjs
   row is caught by `assert-dependabot-drain.test.sh` arms/anchor greps.
4. **Docs build:** `npm run docs:build` completes — the real consumer of the
   bumped liquidjs (eleventy's template engine surface).
5. **CI fidelity:** `npx --yes npm@11 install --package-lock-only` is
   byte-stable post-commit; `npx --yes npm@11 ci --ignore-scripts` validates
   integrity against the registry.
6. **Root checks:** `bash scripts/test-all.sh` or the required `test` CI
   context green.

## Files to Edit

- `package-lock.json` — liquidjs node(s) only (npm@11-generated diff).
- `scripts/assert-dependabot-drain.py` — `WATCHED_PACKAGES`, four js-yaml
  `REQUIRED` rows, one new liquidjs `REQUIRED` row, `FLOOR_ANCHORS` (two
  ratchets + one addition), `MIN_ROWS`/`MIN_RESOLVED` comment arithmetic.
- `scripts/assert-dependabot-drain.test.sh` — `build_fixture` `rt` package
  list (+`("liquidjs", 10)`); FLOOR_ANCHORS spec loop (+3 specs).

## Files to Create

- None (planning artifacts aside).

## References

- Issue: #8065 · Draft PR: #9223 · Precedent PR: #9198 · js-yaml bump that
  resolved the first half: #7970
- `plugins/soleur/skills/work/references/work-lockfile-bumps.md`
- `knowledge-base/project/learnings/workflow-patterns/2026-09-29-dependabot-remediation-must-ratchet-drain-guard-floors.md`
- Advisories: GHSA-2883-xcg3-v3hh (js-yaml) · GHSA-g357-x5c3-c72p,
  GHSA-m7fp-h3p4-hr49, GHSA-4r6h-5v86-94p3 (liquidjs)
