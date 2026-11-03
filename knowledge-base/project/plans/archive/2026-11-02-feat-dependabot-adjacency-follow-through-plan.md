---
title: "chore(deps): dependabot backlog adjacency — likec4 1.60 pin-train bump, drain-guard boundary machinery, issue bookkeeping"
type: chore
date: 2026-11-02
slug: feat-dependabot-adjacency-follow-through
branch: feat-one-shot-dependabot-adjacency
issue: 11696
closes: 11696
lane: cross-domain
---

# chore(deps): dependabot backlog adjacency follow-through

## Enhancement Summary

**Deepened on:** 2026-11-02
**Sections enhanced:** Files to Edit, Implementation Phases, Acceptance Criteria
**Research agents used:** in-process equivalents only — this run had no Task/agent-spawn tool, so the deepen fan-outs (skill-discovery, per-section research, review panel) were executed as sequential in-process verification: live `npm view`/`gh api`/`gh issue` calls, `lint-guard-contract.py`, the sharp-edges catalogue pass, and source reads of every implicated guard/test file.

### Key Improvements (folded in by the deepen pass)

1. `plugins/soleur/test/npm-publish-oidc.test.sh` added to PR-2 — its `npm11-step` probe regexes `npm@\^11` literally and its m4/m11 mutation variants name the string; repinning `npm@^11` without generalizing the probe would ship a RED suite.
2. `apps/web-platform/test/repo-wide-suites.ts` added to PR-2 — the new pin-table suite reads repo-root files and must register in `REPO_WIDE_SUITES` or `repo-wide-containment.test.ts` REDs.
3. AC6's floating-pin sweep regex verified live against the tree (matches exactly the five floating sites, no exact pin).
4. `cron-ux-audit.ts:343` identified as a THIRD `@playwright/mcp` resolution site (inline `"@playwright/mcp@0.0.75"`), making the 0.0.78/0.0.75 divergence structural (dev-proxy vs prod-cron), each pin carrying its own dated live measurement — recorded as a pending technical ruling instead of an uninformed sync.

### New Considerations Discovered

- Adding a `package-lock.json` under `packages/opencode-plugin/` would trip `assert-dependabot-drain.py`'s uncensused-lockfile census — declared-range evaluation chosen instead.
- `yaml: ^2.8.3` sits exactly at GHSA-48c2-rrv3-qjmp's first-patched version — a boundary case the pin-table's declared-range evaluation must treat as pass (minimum == floor).
- `technical-ruling-gate.sh --branch` flags surviving `pending - assumed` rows; the rows in `decision-challenges.md` are the sanctioned pre-CTO form (no Agent tool available in this run) and resolve at work/ship time when a fuller agent can spawn the ruling seats.

## Overview

Follow-through on the merged medium/low Dependabot batch (PR #11823, merged as
`e02f53a6`, release v3.376.4). The lockfile drain is verified complete on
`origin/main` — zero open Dependabot alerts out of 350 total, zero open
dependabot-authored PRs, and `npm audit --omit=dev` on
`apps/web-platform`'s committed lockfile reports `{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}`
— so the remaining work is adjacency in three parts:

1. **PR-1 — likec4 1.60.0 pin-train bump (#11696).** The six-site likec4 train is
   uniformly at `1.50.0` / `--before=2026-09-28`; `@likec4/core@1.60.0` declares
   native `zod: ^4.6.5`, which lets the load-bearing out-of-range
   `"@likec4/core": {"zod": "^4.6.6"}` override be dropped per its own removal
   condition.
2. **PR-2 — drain-guard boundary machinery (#11855 items 1–3).** Extend the
   vitest pin-parity pattern (`c4-likec4-version-pin.test.ts`,
   `dockerfile-vitest-version-pin.test.ts`) into a single pin-table guard that
   censuses every ad-hoc npm-resolution site and reconciles each pin against
   advisory floors; repin the four floating installs to exact versions; declare
   the intentionally-divergent `@playwright/mcp` pair; evaluate the three
   manifest-only `package.json` surfaces by declared range or carve-out. Item 4
   (a live advisory-feed catch-all) stays deferred — the issue itself marks it
   "different mechanism class … spike separately"; it gets its own tracking
   issue.
3. **Issue bookkeeping (no PR).** Close #10857 with the clean-audit evidence;
   refresh #11783 with current upstream state (fix still unreleased); Hono 2.x
   tracking confirmed absent — nothing to close.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verified state on origin/main (2026-11-02) |
|---|---|
| PR #11823 merged as `e02f53a6` | Confirmed — `gh pr view 11823` MERGED, mergeCommit `e02f53a6`, mergedAt 2026-11-02T16:27:45Z |
| Dependabot API: 0 open alerts / 0 open dependabot PRs | Confirmed — `gh api repos/{owner}/{repo}/dependabot/alerts` filtered `state=="open"` → 0; `gh pr list --author app/dependabot` → empty |
| `npm audit --omit=dev` clean | Confirmed — audit run against `origin/main`'s `apps/web-platform` manifest+lockfile in a scratch dir: all severity buckets 0 |
| #10857 next/sentry patched | Confirmed — lockfile resolves `next@16.4.3` (≥16.4.2 patch), `@sentry/nextjs@10.77.1` (≥10.75.2 floor) |
| #11696 actionable; "prior PR/session partially landed" | No partial landing — every pin site at `likec4@1.50.0 --before=2026-09-28`; `git log --grep=likec4` + `gh pr list --search likec4` show only merged historical work |
| #11783 blocked on upstream release | Still blocked — vercel/next.js **issue** #49587 is OPEN (it is an issue, not a PR); latest stable `v16.4.4` (released 2026-11-02) is an LTS-backport release whose changelog does not carry the fix; issue notes an announced November security release due ~2026-11-03 |
| #11855 deferred-scope filing | Confirmed OPEN with `code-review`, `deferred-scope-out`, `meta/machinery` labels; its four-cluster map verified against the live tree (see below) |
| Hono 2.x compat tracking issue | None open — `gh issue list --search hono` returns only #10857; lockfile has `@hono/node-server@2.1.5` (the evacuated-1.x retarget already landed, floor 2.1.3 in `assert-dependabot-drain.py`) |

Collision precheck (`collision-precheck.sh`): `prs=none` for all four issues.
Foreign `test-all.sh` processes owned by sibling worktrees `feat-prod-readiness-gap-analysis`
(pids 1404916, 1454474) and `feat-one-shot-11720-mut-skip-batch3` (pid 293124) are
running concurrently — different scopes, no file overlap expected, reported per
protocol.

### Verified live state used by this plan

- likec4 pin-train sites (complete sweep via `git grep 'likec4@1\.'` and `2026-09-28`):
  `apps/web-platform/Dockerfile:96`; `.github/workflows/ci.yml:1366,1586`;
  `.github/workflows/main-health-monitor.yml:199,380`;
  `plugins/soleur/scripts/render-c4-model.sh` (`LIKEC4_VERSION`/`LIKEC4_BEFORE`, lines 73–74);
  `plugins/soleur/lib/c4-from-components.ts` (`LIKEC4_VERSION`/`LIKEC4_BEFORE` consts, lines 38/44);
  `apps/web-platform/package.json` (`@likec4/core` + `@likec4/diagram` = `1.50.0`, plus the
  `"@likec4/core": {"zod": "^4.6.6"}` override); `apps/web-platform/package-lock.json`;
  `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regen).
  `plugins/soleur/scripts/generate-c4-from-components.ts` consumes the lib consts — no literal.
- **Bump consequence the issue's six-file list missed:** `apps/web-platform/server/c4-stage-sources.ts`
  embeds `LIKEC4_CONFIG_NAMES` (copied from likec4@1.50.0 `_chunks/src.mjs`),
  `LIKEC4_SOURCE_EXTENSIONS` + `LIKEC4_IGNORED_DIRS` (`_chunks/binary.mjs`). The
  `BIN`-gated acceptance test `c4-render-tenant-config.test.ts` re-reads the
  config-name list from the *installed* dist — a bump that changes those lists
  reds there. Re-derive the three consts against the 1.60.0 dist.
- `likec4@1.60.0` published `2026-10-15T10:39:41Z`; `@likec4/core@1.60.0` deps
  carry `zod: ^4.6.5`; `@likec4/diagram@1.60.0` carries `@likec4/core: 1.60.0`.
  Web-platform lockfile has exactly one zod copy: `node_modules/zod@4.6.6`.
  `--before` per BUMPING doc = day after publish → `2026-10-16` (≥3 days old ✓;
  `.npmrc` `min-release-age=3` satisfied).
- Ad-hoc npm-resolution census (from `lint-workflow-install-sites.sh`-style
  extraction plus the issue's map): Dockerfile globals
  `claude-code@2.1.293`, `likec4@1.50.0`, `vitest@4.1.12`, `npx playwright@1.61.0-alpha-…`;
  workflow installs `npm@11` (ci.yml:932), `npm@^11` (npm-publish.yml:51),
  `http-server@14` (ci.yml:2486 + deploy-docs.yml:174), `lefthook@2`
  (gdpr-gate-self-test.yml:104), `wrangler@4.124.0` (deploy-docs.yml:295),
  `playwright@1.60.0` (ci.yml:2486 + deploy-docs.yml:174),
  `@openai/codex@${CODEX_PIN}`=0.156.1, `@opencode/cli@${OPENCODE_PIN}`=2.0.32,
  `@anthropic-ai/claude-code@${CLI_VERSION}`=2.1.228, `bun@${BUN_VERSION}` (from `.bun-version`);
  `.mcp.json:7` + `plugins/soleur/.mcp.json:12` `npx @playwright/mcp@0.0.78`;
  `plugins/soleur/scripts/render-c4-model.sh:147` `npx likec4@${LIKEC4_VERSION}`;
  root `package.json` + `plugins/soleur/docs/package.json` `npx @11ty/eleventy` (unpinned — resolves repo-root lockfile copy);
  `cron-ux-audit.ts:343` inline `"@playwright/mcp@0.0.75"` prod-cron pin.
- **Floating (non-exact) pins today:** `npm@11`, `npm@^11`, `http-server@14`,
  `lefthook@2`. Current latest-in-major for repinning: `npm@11.21.1`,
  `http-server@14.1.1`, `lefthook@2.2.2`.
- `@playwright/mcp` divergence is **structural, not accidental**: 0.0.78 is the
  dev/operator surface through `playwright-mcp-redact-proxy.py` — the CLO
  attestation (`compliance-posture.md` #7980 row + `2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md`)
  records the argv-refusal enumeration "measured live" against 0.0.78; 0.0.75 is
  the prod cron pin (`cron-ux-audit.ts` + web-platform lockfile) where
  `--snapshot-mode none` acceptance and `.npmrc` min-release-age clearance were
  measured on 0.0.75. Converging either direction invalidates a dated live
  measurement — recorded as a pending technical ruling.
- Manifest-only `package.json` census (`git ls-files` with no sibling
  `package-lock.json`): exactly three — `packages/opencode-plugin/package.json`
  (`yaml: ^2.8.3`, published via `npm-publish.yml` OIDC trusted publishing),
  `plugins/soleur/docs/package.json` (no deps), `plugins/soleur/skills/code-to-prd/test/fixture/package.json`
  (test fixture, never installed — no install site references it).
  yaml advisories: GHSA-48c2-rrv3-qjmp (medium, `>=2.0.0 <2.8.3`, patched
  `2.8.3`) — `^2.8.3` minimum sits exactly at first-patched → clean at the
  declared-range floor today.
- Drain guard (`scripts/assert-dependabot-drain.py`, 561 lines): BOUNDARY
  docstring already discloses all three gap classes #11855 maps. `REQUIRED` has
  41 rows, `MIN_ROWS=41`, `MIN_RESOLVED=38`, `MIN_LOCKS=5`. Any NEW
  `package-lock.json` (e.g. one added under `packages/opencode-plugin/`) trips
  its `tracked_lockfiles()` census → the same diff must add the manifest to
  `LOCKS` (deciding for declared-range evaluation avoids this).
- `lint-workflow-install-sites.sh` extracts `npm install`/`npm i`/`npm ci`/`bun
  install` invocations from workflows + `*.sh` + templates and enforces
  `--ignore-scripts` — a *scripts-policy* property. It explicitly excludes
  `-g`/`--no-save` from clause 2, does not reach `.mcp.json`, Dockerfile,
  `*-in-image.sh`, `*.test.sh`, or manifest-only manifests — the surfaces this
  plan's guard must cover. Different property → new guard, not an edit.
- Learnings applied: `2026-11-02-dependabot-drain-must-sweep-install-surfaces-beyond-lockfiles`
  (PR #11823's own P1: a global-install pin outside lockfiles re-vendored a
  vulnerable `@vitest/mocker`); `2026-09-29-dependabot-remediation-must-ratchet-drain-guard-floors`;
  `2026-10-31-drain-guard-ratchet-fixture-and-get-vs-fail-loud` (fixture parity +
  fail-loud manifest checks); `2026-10-05-the-drain-was-born-broken-and-the-waiver-hid-it`;
  `2026-07-20-an-advisory-gate-is-not-a-weak-gate` (an advisory gate is a
  display — the pin-table must FAIL, not warn);
  `2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees`;
  `work-lockfile-bumps.md` (npm is single lockfile of record, ADR-191).

### Property List (Phase 0.6b)

1. The repo records that #10857's nine-entry audit is verified resolved →
   served by an issue action (close-with-evidence), no mechanism.
2. likec4 CLI/client/schema pins resolve 1.60.0 with a `--before` pair and the
   out-of-range zod override is gone → served by the standard BUMPING flow;
   `c4-likec4-version-pin.test.ts` + `c4-model-freshness.test.sh` already
   enforce it.
3. #11783 carries current upstream state → issue action; no mechanism (no
   stable release carries the fix).
4. Every ad-hoc npm-resolution site resolves a declared pin reconciled against
   advisory floors, and the divergence/manifest-only surfaces are declared not
   silent → **new mechanism required** (the pin-table guard). No existing
   mechanism buys this: drain guard reads lockfiles only;
   `lint-workflow-install-sites.sh` is a scripts-policy guard over a narrower
   assembly; the per-package pin tests cover one package each.
5. A catch-all for advisories on unwatched packages → deferred per the issue's
   own "spike separately" guidance; tracked by a new issue.

### Cut List (Phase 0.6b)

| Proposed mechanism | Property | Disposition |
|---|---|---|
| Vendor globals through a lockfile | Property 4 | **Cut** — globals are *deliberately* outside `package.json` to preserve lockfile parity (likec4/vitest precedent); vendoring contradicts ADR-191's single-lockfile design |
| Live advisory-feed reconcile (#11855 item 4) | Property 5 | **Deferred** — issue says "different mechanism class … spike separately"; a network-dependent gate changes the guard's failure modes |
| Extend `assert-dependabot-drain.py` with ad-hoc rows | Property 4 | **Cut** — that guard's substrate is lockfile `packages` maps; ad-hoc sites have no lockfile entries; a separate guard keeps each assembly honest |
| Extend `lint-workflow-install-sites.sh` | Property 4 | **Cut** — its property is `--ignore-scripts` policy and its assembly deliberately excludes `-g`/`--no-save`/`.mcp.json`/Dockerfile; welding floor-reconciliation onto it blurs both properties |

## Problem Statement / Motivation

The #11823 drain closed the lockfile-visible advisories and its review panel
proved the gap class the hard way: a `npm install -g vitest@4.1.11` in the
Dockerfile re-vendored a vulnerable `@vitest/mocker` inside the canary image
while every lockfile guard stayed green. The disclosure text now exists
(BOUNDARY docstrings), but disclosure is not enforcement — today nothing reds
when an ad-hoc site floats (`npm@11`, `http-server@14`, `lefthook@2`), when a
new `npx pkg@` line appears unrecorded, or when a declared pin falls below an
advisory floor. Meanwhile the one actionable dep-bump in the backlog (likec4
1.60) is the removal condition for a load-bearing out-of-range override, and
three bookkeeping items need correct dispositions.

## Proposed Solution

Two sequential PRs plus issue actions:

**PR-1 (Closes #11696, `semver:patch`):** the standard likec4 pin-train bump —
`1.50.0 → 1.60.0`, `--before=2026-09-28 → 2026-10-16` (day after the
2026-10-15 publish day, ≥3 days old), every site in one commit per BUMPING
LIKEC4; regenerate `package-lock.json` and `model.likec4.json`; drop the
`"@likec4/core": {"zod": "^4.6.6"}` override (its recorded removal condition —
native zod-4 in `@likec4/core@1.60.0` — is met); re-derive the three
`c4-stage-sources.ts` consts against the 1.60.0 dist.

**PR-2 (Ref #11855, `semver:patch`):** one new vitest guard
(`apps/web-platform/test/adhoc-npm-install-pin-table.test.ts`) holding a
committed pin-table — every ad-hoc npm-resolution site maps to a row naming
(site, package, pin|env-pin|carve-out, advisory floor, justification); the
census asserts coverage over Dockerfile `RUN` lines, every workflow `run:`
command, `*.sh` scripts, both `.mcp.json` files, manifest-only `package.json`
files, and in-file `npx`/`npm i -g` invocations including env-var pin forms
(`${CODEX_PIN}`-style, resolved against same-file literals). Floating sites get
repinned exact (`npm@11.21.1`, `http-server@14.1.1`, `lefthook@2.2.2`,
`npm@11.21.1` in npm-publish.yml); the two `@playwright/mcp` pins are declared
as intentionally divergent with attestation citations; the three manifest-only
manifests get declared-range rows (`yaml: ^2.8.3`) or carve-outs (docs scripts
resolving the repo-root lockfile copy; the code-to-prd fixture never installed).
BOUNDARY docstrings of `assert-dependabot-drain.py` and
`lint-workflow-install-sites.sh` gain a cross-reference line; ADR-191 gains a
dated addendum recording that the pin-table closes disclosed boundary items
1–2.

**Issue actions (Phase 3, no PR):** close #10857 citing the clean audit and
fixed versions; comment #11783 with the upstream state refresh (issue open,
v16.4.4 does not carry the fix, November security release announced);
file a `deferred-scope-out` tracking issue for #11855 item 4 then close #11855
with the disposition comment; confirm no Hono tracking issue exists (verified —
nothing to close).

## Implementation Phases

### Phase 1 — PR-1: likec4 1.60.0 pin-train bump (#11696)

1.1 Verify upstream pin semantics: `@likec4/core@1.60.0` and
`@likec4/diagram@1.60.0` dependency ranges (zod native `^4.6.5` confirmed
2026-11-02 via `npm view`).

1.2 Bump every pin site in one commit: `apps/web-platform/package.json`
(`@likec4/core`, `@likec4/diagram` → `1.60.0`; **delete** the
`"@likec4/core": {"zod": "^4.6.6"}` override — the `inngest` scoped override
stays, its residual is inngest's own vendored `zod/v3`); `Dockerfile:96`;
`ci.yml:1366,1586`; `main-health-monitor.yml:199,380`;
`render-c4-model.sh` `LIKEC4_VERSION`/`LIKEC4_BEFORE` (73–74 + header comment
"Pinned to likec4@1.50.0"); `lib/c4-from-components.ts` consts (38/44 +
comments); version-naming comments in `.npmrc`, `server/c4-render.ts`,
`server/c4-stage-sources.ts`.

1.3 Re-derive `LIKEC4_CONFIG_NAMES`, `LIKEC4_SOURCE_EXTENSIONS`,
`LIKEC4_IGNORED_DIRS` in `server/c4-stage-sources.ts` against the installed
1.60.0 dist (`_chunks/src.mjs`, `_chunks/binary.mjs`); update the copied-from
version comments regardless of whether the lists changed.

1.4 `cd apps/web-platform && npm install --package-lock-only`; verify
`git show :package-lock.json | head -3` keeps `name` (worktree rewrite trap,
learning 2026-05-27); `npm ci --ignore-scripts`.

1.5 Regenerate `knowledge-base/engineering/architecture/diagrams/model.likec4.json`
via `bash plugins/soleur/scripts/render-c4-model.sh`.

1.6 Drain + affected tests: `python3 scripts/assert-dependabot-drain.py`;
`npx vitest run test/c4-likec4-version-pin.test.ts test/c4-config-name-parity.test.ts test/c4-stage-sources.test.ts test/c4-render-tenant-config.test.ts`
(the `BIN`-gated arms need the real 1.60.0 binary); `bash plugins/soleur/test/c4-model-freshness.test.sh`;
`npm audit --omit=dev` still clean.

### Phase 2 — PR-2: ad-hoc npm pin-table guard (#11855 items 1–3)

2.1 Author the table + guard in
`apps/web-platform/test/adhoc-npm-install-pin-table.test.ts`. Table rows per
(site, package): every Dockerfile `RUN npm/npx` line; every workflow
`run:`-level `npm install -g`/`npm i -g`/`npm install --no-save`/`npx` site;
every `*.sh` ad-hoc install site; both `.mcp.json` npx specs; `cron-ux-audit.ts`
inline MCP spec; `npx @11ty/eleventy` script entries (declared
local-resolution carve-out); manifest-only manifests by declared range.
Env-var pins (`${CODEX_PIN}`, `${OPENCODE_PIN}`, `${CLI_VERSION}`,
`${BUN_VERSION}`, `${LIKEC4_VERSION}`/`${LIKEC4_BEFORE}`) resolve against their
same-file or named-file literal, never accepted opaquely.

2.2 Repin the four floating sites exact: `ci.yml:932` `npm@11` → `npm@11.21.1`;
`npm-publish.yml:51` `npm@^11` → `npm@11.21.1` (keeps the ≥11.5.1
trusted-publishing floor); `ci.yml:2486` + `deploy-docs.yml:174`
`http-server@14` → `http-server@14.1.1`; `gdpr-gate-self-test.yml:104`
`lefthook@2` → `lefthook@2.2.2`. Versions are current-latest-in-major as of
2026-11-02; work phase re-derives the literal at execution time.

2.3 Reconciliation semantics: each row's pin must be ≥ its declared advisory
floor (static per-(package, major) floor table mirroring the drain guard's
REQUIRED/FLOOR_ANCHORS split — floors cross-anchored in a second constant the
suite source-greps). Carve-out rows carry a non-empty justification; a row
with an empty justification REDs.

2.4 `.mcp.json` rows: both 0.0.78 pins declared exact; `cron-ux-audit.ts` +
web-platform lockfile 0.0.75 declared exact; the pair recorded as
intentionally divergent — each row's justification cites its attestation
anchor (compliance-posture #7980 row for 0.0.78; `cron-ux-audit.ts` comment +
playwright-mcp-version-pin parity for 0.0.75). The convergence decision is a
pending ruling (decision-challenges row); this plan changes no pin.

2.5 Manifest-only surfaces: `packages/opencode-plugin/package.json` →
declared-range row (`yaml: ^2.8.3`, floor `2.8.3` from GHSA-48c2-rrv3-qjmp);
`plugins/soleur/docs/package.json` + root `package.json` `npx @11ty/eleventy`
→ carve-out rows (resolves repo-root lockfile copy `@11ty/eleventy ^3.1.5`;
remote fallback only on missing local install);
`plugins/soleur/skills/code-to-prd/test/fixture/package.json` → carve-out
(test fixture, no install site). NO new `package-lock.json` — adding one trips
the drain guard's uncensused-lockfile check and buys nothing for a published
package whose consumers resolve their own tree.

2.6 Wiring and boundary cross-references: register the new suite in
`apps/web-platform/test/repo-wide-suites.ts` (`REPO_WIDE_SUITES` —
`repo-wide-containment.test.ts` REDs an unregistered repo-wide suite);
generalize `plugins/soleur/test/npm-publish-oidc.test.sh`'s `npm11-step`
probe (currently literal `npm@\^11`) to accept the exact `npm@11.x.y` pin
while keeping the ≥11.5.1 floor and the install-before-publish position
rule, updating the m4/m11 mutation variants in the same diff; one line each
in `assert-dependabot-drain.py`'s BOUNDARY docstring and
`lint-workflow-install-sites.sh`'s unreached-surfaces comment naming the
pin-table guard as the owner of ad-hoc pin reconciliation; dated ADR-191
addendum recording the closure of disclosed items 1–2.

2.7 Sequence note: PR-2 also edits `ci.yml`, which PR-1 touches — PR-2 rebases
on main after PR-1 merges (the overlap is two disjoint line regions).

### Phase 3 — Issue bookkeeping (no PR)

3.1 Close #10857 with a comment citing: `npm audit --omit=dev` on
`origin/main`'s lockfile reports 0 vulnerabilities in every severity bucket;
`next@16.4.3` (GHSA-2464-fhr4-w9xw + GHSA-673q-mjm6-r5xr + GHSA-p3m5-59mp-jv5r),
`@sentry/nextjs@10.77.1` (GHSA-mchm-gjx6-7h55), `vite@7.3.7`, `hono@4.13.14`,
`@hono/node-server@2.1.5`, `gray-matter@4.0.3`, `minimatch` 11.x consolidation,
`glob@14.0.2` — and the drain guard's REQUIRED rows as the standing
re-admission ratchet. The pre-close verification is re-run at execution time;
close only if all nine entries still resolve clean.

3.2 Comment on #11783 (leave open): upstream issue vercel/next.js#49587 still
OPEN as of 2026-11-02; `v16.4.4` (2026-11-02) is an LTS-backport release that
does not carry the fix; the upstream notes announce a November security
release due ~2026-11-03 — the next re-check target; `isBenignClientAbort`
stays in `server/crash-handlers.ts` meanwhile.

3.3 File a `deferred-scope-out` tracking issue for #11855 item 4 (live
advisory-feed reconcile over ~2000 unwatched resolved packages — a
network-dependent gate changes failure modes; spike separately), milestone
`Post-MVP / Later`; then close #11855 with a comment recording items 1–3
landed in PR-2 and item 4 forwarded to the new issue. Add
`gh issue edit 11855 --add-blocked-by` is NOT needed (the new issue is a
successor, not a blocker).

3.4 Hono 2.x: verified no open tracking issue (`gh issue list --search hono`
→ only #10857); `@hono/node-server@2.1.5` already landed — no action.

## Files to Edit

PR-1:

- `apps/web-platform/package.json` — `@likec4/core`/`@likec4/diagram` → `1.60.0`; delete `"@likec4/core": {"zod": "^4.6.6"}` override
- `apps/web-platform/package-lock.json` — regenerated (`npm install --package-lock-only`)
- `apps/web-platform/Dockerfile` — line 96 likec4 pin + `--before` date
- `.github/workflows/ci.yml` — lines 1366, 1586
- `.github/workflows/main-health-monitor.yml` — lines 199, 380
- `plugins/soleur/scripts/render-c4-model.sh` — `LIKEC4_VERSION`, `LIKEC4_BEFORE`, header comment
- `plugins/soleur/lib/c4-from-components.ts` — `LIKEC4_VERSION`, `LIKEC4_BEFORE` consts + comments
- `apps/web-platform/server/c4-stage-sources.ts` — re-derived `LIKEC4_CONFIG_NAMES`/`LIKEC4_SOURCE_EXTENSIONS`/`LIKEC4_IGNORED_DIRS` vs 1.60.0 dist; version comments
- `apps/web-platform/server/c4-render.ts` — likec4-version comment (~line 178)
- `apps/web-platform/.npmrc` — likec4-version comment (~line 15)
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` — regenerated artifact

PR-2:

- `.github/workflows/ci.yml` — `npm@11` → exact (line 932); `http-server@14` → exact (line 2486)
- `.github/workflows/npm-publish.yml` — `npm@^11` → exact (line 51)
- `.github/workflows/deploy-docs.yml` — `http-server@14` → exact (line 174)
- `.github/workflows/gdpr-gate-self-test.yml` — `lefthook@2` → exact (line 104)
- `scripts/assert-dependabot-drain.py` — BOUNDARY docstring cross-reference line
- `scripts/lint-workflow-install-sites.sh` — unreached-surfaces comment cross-reference line
- `knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md` — dated addendum
- `apps/web-platform/test/repo-wide-suites.ts` — register `test/adhoc-npm-install-pin-table.test.ts` in `REPO_WIDE_SUITES` (the suite reads repo-root files; `repo-wide-containment.test.ts` REDs an unregistered repo-wide suite)
- `plugins/soleur/test/npm-publish-oidc.test.sh` — the `npm11-step` probe regexes `npm@\^11` literally; generalize to accept the exact pin (`npm@11.x.y` ≥ 11.5.1 floor) while keeping the install-before-publish position rule, and update the m4/m11 mutation variants to match

## Files to Create

- `apps/web-platform/test/adhoc-npm-install-pin-table.test.ts` — the pin-table guard (census + exact-pin + floor reconciliation + carve-out declarations)

## Open Code-Review Overlap

One open scope-out touches these files: **#11855** (Dockerfile,
render-c4-model.sh, `.mcp.json`, `plugins/soleur/.mcp.json`,
`packages/opencode-plugin/package.json`, `scripts/assert-dependabot-drain.py`).
Disposition: **fold in** items 1–3 (pin-table + repins + declared divergences +
manifest-only evaluation); **defer** item 4 (feed-reconcile) to a new tracking
issue per the issue's own "spike separately" guidance. No other open
`code-review` issues touch the file list (97 open issues scanned via body
search on every planned path).

## Technical Considerations

- The likec4 `--before` pair is load-bearing: a version bump that forgets the
  date fails with ETARGET or floats the ~190-node transitive tree (#9300);
  BUMPING LIKEC4 in `render-c4-model.sh` is the runbook.
- `min-release-age=3` in `apps/web-platform/.npmrc` applies to exact pins —
  all new pins are ≥3 days old at plan time; the work phase re-verifies at
  execution (a same-day latest release would ETARGET, which is the floor
  working as designed — pick the previous minor then).
- The drain guard needs NO row changes for PR-1: likec4 is not a watched
  package and zod's `("web-platform","zod",4,"4.6.6")` floor is already met;
  the override's removal leaves `node_modules/zod@4.6.6` as the sole copy.
- The pin-table guard is fail-CLOSED (a `vitest` expectation suite that fails
  the run), not advisory — per learning
  `2026-07-20-an-advisory-gate-is-not-a-weak-gate`.
- The census's invocation-vs-mention discrimination matters: comments and
  `::error::` strings quoting install commands must not count as sites
  (mirrors `lint-workflow-install-sites.sh`'s awk discrimination and the
  `*.test.sh` fixture exclusion — the new suite's own fixtures carry violating
  text by design and live inside the test file, not scanned paths).
- No new autonomous-task surface is created (no workflow/cron/Inngest/timer) —
  Task Design gate does not fire.
- PR-1 touches user-visible rendering (`/dashboard/kb` C4 diagrams); breakage
  is caught by the c4-* vitest suite and `c4-model-freshness.test.sh` before
  merge, and is revertible.

## User-Brand Impact

- **If this lands broken, the user experiences:** the C4 diagram workspace at
  `/dashboard/kb` renders a stale or broken model (PR-1 likec4 schema skew),
  or CI/main-monitor legs fail on repinned toolchains (PR-2) — visible but
  revertible with no data exposure.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  new exposure vector — the change narrows supply-chain resolution surfaces;
  the worst case is a wrong-version tool executing a CI step, which runs
  inside CI's existing trust boundary.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** user-facing blast radius is a
  rendering defect caught pre-merge by the c4 suite; the sensitive-path
  regex's covered surfaces (`server/`, `app/api/`, infra, credential
  workflows) are untouched by the functional diff.

## Observability

```yaml
liveness_signal:
  what: the pin-table vitest + assert-dependabot-drain-live run inside scripts/test-all.sh on every PR and the main-health-monitor sweep
  cadence: per-PR + scheduled monitor
  alert_target: GitHub required-check failure / monitor issue filing
  configured_in: scripts/test-all.sh (assert-dependabot-drain-live registration; the new vitest file joins the existing apps/web-platform vitest glob)
error_reporting:
  destination: CI job log + GitHub check status on the PR
  fail_loud: "::error::"/vitest FAIL lines naming the offending site and floor; a silent 0-sites run is impossible (anti-vacuity floor)
failure_modes:
  - mode: ad-hoc install added without a table row
    detection: census-vs-table mismatch vitest assertion → PR check red
    alert_route: PR author via required check
  - mode: declared pin drifts below an advisory floor
    detection: floor-reconciliation assertion → PR check red
    alert_route: PR author via required check
  - mode: repinned toolchain version yanked upstream
    detection: npm install ETARGET in the affected workflow leg
    alert_route: workflow run failure on the PR
logs:
  where: GitHub Actions run logs for ci.yml / main-health-monitor.yml; vitest output in job log
  retention: GitHub default retention (~90 days)
discoverability_test:
  command: python3 scripts/assert-dependabot-drain.py
  expected_output: drain assertion
```

## Guard Contract

### Guard 1 — ad-hoc npm install pin-table

**Property.** Every ad-hoc npm-resolution site in the tracked tree resolves a
declared pin (exact literal, env-indirect literal, or justified carve-out)
that sits at or above its declared advisory floor — no floating or unrecorded
npm resolution reaches an unrecorded version.

**Assembly.** The chokepoint is the table↔census pair: rows enumerate
(site, package, pin-form, floor, justification); the census derives every
ad-hoc resolution site by `git ls-files` classes — Dockerfile `RUN` lines;
`.github/workflows/**` `run:` commands; `*.sh` scripts; `*.mcp.json`;
`package.json` files with no sibling `package-lock.json`; in-file
`npm install -g`/`npm i -g`/`--no-save`/`npx <spec>` invocations including
`${VAR}`-pinned forms resolved against same-file literals. Both directions are
asserted: every site has a row AND every row names a live site (stale rows
red too).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Change any tabled pin to a floating spec (`npm@11` → `npm@11` is the baseline; rewrite `npm install -g npm@11.21.1` back to `npm@11`) | RED |
| 2 | Add a new `run: npm install -g foo@1.2.3` step to a scanned workflow with no table row | RED |
| 3 | Break the census extractor so zero sites are found | RED (anti-vacuity site-count floor — dispatch row) |
| 4 | Set a row's floor above its pinned version (e.g. `npm` floor `99.0.0` vs pin `11.21.1`) | RED |
| 5 | Table only the first of two same-package sites (e.g. table ci.yml `npm@11.21.1` but not npm-publish.yml's) | RED — second-member row |
| 6 | Add `echo "npm install -g evil@0.0.1"` (mention, not invocation) to a workflow | PASS — invocation-vs-mention discrimination (must-PASS, non-canonical permitted input) |
| 7 | Give a carve-out row an empty justification | RED |
| 8 | Lower a floor in the row table without moving the cross-anchor constant | RED — anchor mismatch |
| 9 | A table row names a site that no longer exists (stale row after a site is deleted) | RED — row→site direction |
| 10 | The suite's own fixture text (violating commands inside `*.test.ts`) is enumerated as a site | PASS — fixture/scan-boundary exclusion holds |

**Anchor.** Floors live in the row table AND a separate `FLOOR_ANCHORS`-style
constant the mutation battery source-greps; lowering a floor requires editing
two places that disagree loudly, mirroring `assert-dependabot-drain.py`'s
proven pattern — a single-file consistency edit cannot silently weaken the
guard.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#10857 (security: patch vulnerable Web Platform runtime dependencies): next@16.4.3 and @sentry/nextjs@10.77.1 are already patched on main and npm audit is clean — VERIFY the full 9-entry finding is covered, then close with a comment citing the clean audit + fixed versions. Do NOT close if any entry still resolves vulnerable." [brief] | Phase 3.1 | mapped |
| 2 | "#11696 (likec4 1.60 pin-train bump): actionable. Run the standard in-range bump flow — update the pinned likec4 train, npm ci, drain guard + affected tests. Semver:patch. If a prior PR/session partially landed it, reconcile before bumping." [brief] | Phase 1 / PR-1 | mapped |
| 3 | "#11783 (next body-streams abort-listener): CHECK whether a stable next.js release shipped upstream containing vercel/next.js#49587. If stable shipped → bump, test, PR. If still unreleased → comment refresh with the latest upstream state, leave open." [brief] | Phase 3.2 (unreleased arm verified: issue OPEN, v16.4.4 carries no fix) | mapped |
| 4 | "#11855 (drain-guard boundary: npm-bearing surfaces outside assert-dependabot-drain.py's window): machinery/verification scope — ad-hoc npm install -g / --no-save / npx sites in Dockerfiles and workflows, .mcp.json Playwright MCP pin drift (0.0.78 vs locked 0.0.75), manifest-only packages/opencode-plugin yaml dep with no lockfile, catch-all advisory mechanism for unwatched packages. This was filed deliberately as deferred scope; evaluate whether to work it now or keep deferred." [brief] | Phase 2 / PR-2 (items 1–3) + Phase 3.3 (item 4 tracking issue) | mapped |
| 5 | "Hono 2.x compat tracking: confirm no open tracking issue remains (search returned none) — @hono/node-server 2.1.5 already landed; if an open issue exists, close it as resolved." [brief] | Phase 3.4 (verified none) | mapped |
| 6 | "verify each item's live state against main before acting; one PR per distinct scope where it produces real change; semver:patch labels; do not reopen the drained-batch scope (already merged)." [brief] | Premise Validation; two-PR split; phase notes | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| PR-1 likec4 pin-train bump + override drop | "Run the standard in-range bump flow — update the pinned likec4 train, npm ci, drain guard + affected tests" | asked |
| PR-2 pin-table guard (`adhoc-npm-install-pin-table.test.ts`) | "machinery/verification scope — ad-hoc npm install -g / --no-save / npx sites in Dockerfiles and workflows" | asked |
| Repin `npm@11`/`npm@^11`/`http-server@14`/`lefthook@2` exact | "ad-hoc npm install -g / --no-save / npx sites" — exact pins are the pin-table's declared-pin form | asked |
| `.mcp.json` divergent-pair declaration (no pin change) | ".mcp.json Playwright MCP pin drift (0.0.78 vs locked 0.0.75)" | asked — direction itself deferred to ruling |
| Manifest-only declared-range evaluation / carve-outs | "manifest-only packages/opencode-plugin yaml dep with no lockfile" | asked |
| Item-4 tracking issue (feed reconcile spike) | "catch-all advisory mechanism for unwatched packages" + deferral-tracking rule | inferred — justification: the ask enumerates the mechanism but the issue itself says "spike separately"; a deferral without a tracking issue is invisible |
| c4-stage-sources const re-derivation | "update the pinned likec4 train" | inferred — justification: consts copied from the 1.50.0 dist are part of the train the pin-parity tests bind; stale copies falsify the staged-source contract |
| ADR-191 addendum + BOUNDARY cross-references | — | inferred — justification: the recorded-boundary discipline (BOUNDARY docstrings) is what made #11855 reviewable; a new guard must update the maps it changes |
| Close #10857 / comment #11783 / close #11855 | asks 1, 3, 4 | asked |

### Split Assessment

- Subsystems touched: 6 — `apps/web-platform`, `plugins/soleur`, `.github/workflows`, `scripts`, `packages/opencode-plugin` (row only — no file edit), `knowledge-base`
- Planned files: 19 edit + 1 create | Estimated changed lines: ~350 (mostly lockfile + model.likec4.json regen churn)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: **split** — PR-1: likec4 pin-train (Files list block 1, `Closes #11696`); PR-2: pin-table machinery + repins (block 2 + new test file, `Ref #11855`). The seam is clean: PR-1 is a version bump, PR-2 is new guard machinery; only `ci.yml` overlaps and only across disjoint line regions.

## Domain Review

**Domains relevant:** Engineering (CTO — guard mechanism/devex), Legal (CLO — the `.mcp.json` 0.0.78 attested-control direction)

Note: agent spawning is unavailable in this planning subagent (no Task tool);
assessments below are the orchestrator's own evidence-based reads, and the two
technical/legal forks are persisted as pending rulings in
`knowledge-base/project/specs/feat-one-shot-dependabot-adjacency/decision-challenges.md`
rather than silently decided.

### Engineering

**Status:** reviewed (in-process — Task tool unavailable)
**Assessment:** The pin-table mechanism follows the repo's established
pin-parity precedent (likec4, vitest, playwright-mcp) and the
FLOOR_ANCHORS cross-anchor pattern from `assert-dependabot-drain.py`. The
vendoring alternative is cut — globals deliberately live outside
`package.json` for lockfile parity (ADR-191). One design fork recorded:
pin-table-with-carve-outs vs per-site bespoke pin tests — the table wins on
census (one enumeration covers new sites automatically; per-package tests each
hardcode their site list).

### Legal

**Status:** reviewed (in-process — Task tool unavailable)
**Assessment:** The `.mcp.json`/`cron` `@playwright/mcp` divergence sits on a
CLO-attested control (compliance-posture #7980 row — argv-refusals "measured
live" against 0.0.78; the 0.0.75 cron pin carries its own dated measurements
for `--snapshot-mode none` + min-release-age). This plan changes **no**
@playwright/mcp pin — it declares both with their attestation citations — so
no attestation is invalidated by the diff. The convergence question is a
pending ruling row.

### Product/UX Gate

**Tier:** none — no `## Files to Create`/`Edit` entry matches the UI-surface
glob superset (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`,
`*.njk`, etc.); `/dashboard/kb` rendering is affected only via the CLI version
that renders an existing artifact.
**Decision:** skipped — backend/tooling change.

## Acceptance Criteria

- [ ] AC1 — PR-1: `git grep 'likec4@1\.50\.0'` returns zero non-fixture, non-knowledge-base hits; every likec4 install line reads exactly `npm install -g likec4@1.60.0 --before=2026-10-16 --ignore-scripts` (the Dockerfile line carries the `RUN` prefix); `LIKEC4_VERSION="1.60.0"` and `LIKEC4_BEFORE="2026-10-16"` in both `render-c4-model.sh` and `lib/c4-from-components.ts`.
- [ ] AC2 — `apps/web-platform/package.json` carries `@likec4/core`/`@likec4/diagram` `1.60.0` and no `"@likec4/core"` override key; lockfile regenerates cleanly (`npm install --package-lock-only` diff lands, `name` field unchanged from origin/main).
- [ ] AC3 — `apps/web-platform/server/c4-stage-sources.ts` consts verified against the 1.60.0 dist (updated if the upstream lists changed; comments name 1.60.0 either way).
- [ ] AC4 — `python3 scripts/assert-dependabot-drain.py` exits 0; `npx vitest run test/c4-likec4-version-pin.test.ts` green; `bash plugins/soleur/test/c4-model-freshness.test.sh` green against the regenerated `model.likec4.json`; `npm audit --omit=dev` in apps/web-platform reports 0.
- [ ] AC5 — PR-2: `apps/web-platform/test/adhoc-npm-install-pin-table.test.ts` exists, is wired into the vitest suite, and is GREEN on the merged tree.
- [ ] AC6 — Every ad-hoc npm-resolution site in the census maps to a table row and every row names a live site; `git grep -nE 'npm (install|i)[^#]*@[\^~]?[0-9]+([^0-9.]|$)' -- '.github/workflows'` finds no remaining major-only install pin (verified at plan time: it matches exactly the five floating sites — `npm@11`, `npm@^11`, `http-server@14` ×2, `lefthook@2` — and no exact pin).
- [ ] AC7 — The `.mcp.json` `@playwright/mcp@0.0.78` pair and the 0.0.75 lockfile/cron pin are tabled as intentionally divergent with non-empty justifications citing their attestation anchors; no @playwright/mcp pin value changed.
- [ ] AC8 — `packages/opencode-plugin`, `plugins/soleur/docs`, and the code-to-prd fixture manifests each carry a table disposition (declared-range row or justified carve-out); no new `package-lock.json` added.
- [ ] AC9 — `assert-dependabot-drain.py` BOUNDARY docstring and `lint-workflow-install-sites.sh` unreached-surfaces comment each name the new guard; ADR-191 carries a dated addendum.
- [ ] AC10 — Mutation battery: the Guard-Contract matrix rows 1–10 each implemented as a suite arm (RED rows fail for the named reason; PASS rows stay green).
- [ ] AC11 — #10857 closed with the audit-evidence comment (re-verified clean at close time); #11783 carries the 2026-11-02 upstream-state comment and stays open; a `deferred-scope-out` tracking issue exists for #11855 item 4 and #11855 is closed with the disposition comment; both PRs carry `semver:patch` labels.

## Test Scenarios

- Given the pin-train at 1.60.0, when `c4-likec4-version-pin.test.ts` runs, then all sites assert equal (version, --before) pairs — `unit`
- Given a workflow gaining an untabled `npm install -g` site, when the pin-table suite runs, then the census-vs-table assertion fails naming the site — `unit` (guard mutation battery)
- Given a table row whose pin sits below its floor, when the suite runs, then the floor assertion fails naming package+site — `unit`
- Given the divergent @playwright/mcp pair, when the suite runs, then both rows pass (exact pins, justified divergence) while an unjustified divergence fixture fails — `unit`
- Given `npm audit --omit=dev` on the post-PR-1 lockfile, when it executes, then output reports 0 vulnerabilities — `integration`
- Given the regenerated `model.likec4.json`, when `c4-model-freshness.test.sh` byte-diffs it against a fresh 1.60.0 render, then identical — `integration`
- Given a same-day-published latest version for a repinned tool, when `npm install -g` runs under `.npmrc` `min-release-age=3`, then ETARGET is the designed failure and the prior minor is chosen — `integration`
- Given the code-to-prd fixture manifest, when the manifest-only census runs, then it maps to its carve-out row, not a declared-range row — `unit`

## Success Metrics

- Zero floating ad-hoc npm installs in the census (all exact or justified carve-out)
- Pin-table suite green with ≥10 mutation arms
- `npm audit --omit=dev` = 0 maintained; Dependabot alerts = 0 maintained
- #10857, #11696, #11855 closed; #11783 open with current state; item-4 tracking issue filed

## Dependencies & Risks

- **PR-1/PR-2 ordering:** `ci.yml` touched by both (disjoint line regions) — PR-2 rebases post-PR-1-merge.
- **likec4 1.60 schema drift:** the `BIN`-gated acceptance tests only run when the real binary is present — the Dockerfile/`npx` path must install 1.60.0 for the consts re-derivation to be verified, not assumed.
- **`.mcp.json` divergence ruling:** recording the pair as declared-divergent is the plan; if the pending ruling later converges, the table flips one row — cheap by design.
- **`npm@11.x.y` repin:** npm 10.x ignores `min-release-age` silently — the pin must stay on major 11 (asserted by a floor row ≥11.5.1, the trusted-publishing floor).
- **Foreign concurrent sessions:** three `test-all.sh` processes run under sibling worktrees (different scopes); lockfile regeneration in this worktree is independent, but a main-moving-fast re-verification is required at work time (brief's own rule).
- **model.likec4.json regen churn:** a 1.50→1.60 render may produce a large byte-diff; it is a generated artifact — the diff lands wholesale, reviewed by `c4-model-freshness` not by eye.

## References & Research

- BUMPING LIKEC4 runbook: `plugins/soleur/scripts/render-c4-model.sh` lines ~28–52
- Pin-parity precedents: `apps/web-platform/test/c4-likec4-version-pin.test.ts`, `apps/web-platform/test/dockerfile-vitest-version-pin.test.ts`, `apps/web-platform/test/playwright-mcp-version-pin.test.ts`
- Drain guard + BOUNDARY: `scripts/assert-dependabot-drain.py`; ADR-191 (`knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md`)
- Install-site policy guard + unreached-surfaces map: `scripts/lint-workflow-install-sites.sh` lines 32–66
- Attestations: `knowledge-base/legal/compliance-posture.md` (#7980 row); `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md`
- Learnings: `2026-11-02-dependabot-drain-must-sweep-install-surfaces-beyond-lockfiles.md`, `2026-09-29-dependabot-remediation-must-ratchet-drain-guard-floors.md`, `2026-10-31-drain-guard-ratchet-fixture-and-get-vs-fail-loud.md`, `2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`, `2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md`
- Upstream: vercel/next.js issue #49587 (OPEN); `v16.4.4` release notes (LTS backports, 2026-11-02)
- Related PRs/issues: #11823 (merged), #11691 (merged), #11772, #7084, #9300

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or
  `soleur:work`.
- `Spec lacks valid lane:` — no spec.md exists for this branch yet; `lane:
  cross-domain` is set fail-closed on this plan (TR2 default) pending the
  spec's own declaration.
- vercel/next.js#49587 is an **issue**, not a PR — `gh pr view` cannot resolve
  it; use `gh issue view ... --repo vercel/next.js`.
- The `.npmrc` `min-release-age=3` floor applies to exact pins: a pin chosen
  the same day it published fails ETARGET — the work phase picks
  latest-in-major that is ≥3 days old.
