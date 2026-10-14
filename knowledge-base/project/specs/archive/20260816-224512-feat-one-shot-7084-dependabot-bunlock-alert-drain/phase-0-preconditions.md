# Phase 0 — Preconditions (measured 2026-08-16)

Every number below is a live re-derivation, not a copy of the plan's snapshot. Where a measurement
contradicts the plan, the contradiction is stated rather than smoothed over.

## 0.1 Live state

| Surface | Plan snapshot | Live 2026-08-16 | Delta |
|---|---|---|---|
| Open Dependabot alerts | 39 | **39** | none |
| Open Dependabot PRs | 9 | **10** | **+1 — PR 7571 is new** |
| Open CodeQL alerts | 3 (214, 213, 203) | **3** (214, 213, 203) | none |

Alert distribution by package (live): hono 8, ip-address 6, undici 5, js-yaml 4, fast-uri 4,
brace-expansion 4, postcss 3, @hono/node-server 2, sharp 1, nanoid 1,
@opentelemetry/propagator-jaeger 1. This matches the Phase 3 reconciliation table exactly, so the
39 → 35 cleared + 4 blocked arithmetic stands unchanged.

**PR 7571** (`chore(deps): bump @hono/node-server from 1.19.13 to 1.19.17 in
/plugins/soleur/skills/pencil-setup/scripts`, opened 2026-08-16T12:53:07Z) appeared between the
plan's snapshot and Phase 0. It is subsumed by the same Phase 3.2 `@hono/node-server` bump that
subsumes PR 7503, so it joins the sweep. **The Phase 4 queue is ten PRs, not nine**, and AC22's
enumeration is amended accordingly. Baseline captured at `alerts-baseline.tsv`.

## 0.2 Install-site inventory (repo-wide)

Re-derived with `git grep -nE '(bun install|npm ci)' -- ':!knowledge-base' ':!*.md'`. The plan's
enumeration is confirmed: sixteen converting `bun install` sites (fourteen under
`.github/workflows/`, plus `plugins/soleur/scripts/grok-fidelity-gate.sh:28` and
`apps/web-platform/.github/workflows/constraint-gates.yml:54`) and four pre-existing bare `npm ci`
sites. Twenty live install sites total.

## 0.2b Release-age floor vs global exact pins — **root is exempt**

The plan's decision rule: if an exact pin younger than the floor fails to resolve, do not create the
root `.npmrc`.

Measured against npm 11.12.1, capturing the real exit code rather than a pipeline's:

```
npm install -g likec4@1.50.0 --min-release-age=3650 --dry-run   → rc=1
  npm error code ETARGET
  npm error notarget No matching version found for likec4@1.50.0 with a date before 8/18/2016
npm install -g likec4@1.50.0 --min-release-age=3    --dry-run   → rc=0 (control: pin older than floor)
```

The floor **does** apply to exact pins, so a root `.npmrc` would break
`npm install -g "@anthropic-ai/claude-code@${CLI_VERSION}"` on precisely the PR that bumps
`CLI_VERSION` to a same-day release — which is what `/soleur:model-launch-review` does on every
Anthropic model launch. It would equally break `likec4@1.50.0` and `playwright@1.60.0` on the day
either is repinned to a fresh release.

**Decision: no root `.npmrc`.** The floor is scoped to `apps/web-platform`,
`plugins/soleur/skills/pencil-setup/scripts`, and `spike` — **three** files, not four. Root's
exemption and this reason are recorded in ADR-191. AC7's "all four `.npmrc` files" reads **three**;
AC9d is the governing criterion and it anticipated this branch.

## 0.2b(ii) Correction — the plan's parent-traversal evidence was unsound

The plan cites: *"measured: with `min-release-age=7` in a parent, `npm config get min-release-age`
from the child returns `null` under npm 11.12.1."*

**The conclusion is right; that probe does not establish it.** `npm config get min-release-age`
returns `null` in the directory that *owns* the `.npmrc` as well — even with a `package.json`
present — so it cannot distinguish "not inherited" from "not visible to this probe at all". Read
literally it would also prove the floor never works anywhere, which the 0.2b measurement above
falsifies.

Re-measured behaviorally, which does establish it:

```
parent/.npmrc = min-release-age=3650
  cd parent && npm install likec4@1.50.0 --dry-run  → rc=1, ETARGET      (floor honored)
  cd parent/child && npm install likec4@1.50.0 …    → rc=0, no ETARGET   (floor NOT inherited)
```

npm reads `./.npmrc` from the install cwd and does not traverse to a parent. One `.npmrc` per
install directory is therefore required, as the plan concluded.

## 0.3 npm@11 supports the flag

`npx --yes npm@11 install --help` prints `[--before <date>|--min-release-age <days>]` and
`--min-release-age`. Confirmed.

## 0.4 ADR ordinal

Across all 67 `origin/*` refs: `main` is at **ADR-186**; ADR-187–190 are claimed on unmerged
branches. **ADR-191 is free** and remains this plan's ordinal. Re-derive again immediately before
merge — the `adr-ordinals` required check enforces it.

## 0.6 `next.config.ts` declares no `images` key

`grep -nE 'images' apps/web-platform/next.config.ts` returns nothing. The invariant behind the
deliberate sharp/postcss deferral holds, and the Phase 1.4 assertion is written against the absence
of the whole key rather than `images.remotePatterns`.

## 0.7 Derived residual

35 cleared + 4 blocked = 39. The expected post-drain open set is **{161, 162, 170 (postcss),
144 (sharp)}** — 3 high + 1 medium. Phase 6.3 asserts the live set against exactly this, itemized by
alert ID, and reports any delta as a finding rather than rounding it to "as expected".
