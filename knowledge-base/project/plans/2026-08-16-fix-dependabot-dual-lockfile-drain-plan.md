---
title: "fix(ci,deps): make the npm lockfile the single lockfile of record, then drain the Dependabot backlog"
date: 2026-08-16
slug: fix-dependabot-dual-lockfile-drain
branch: feat-one-shot-7084-dependabot-bunlock-alert-drain
issue: 7084
closes: 7084
type: fix
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed): no
> `knowledge-base/project/specs/feat-one-shot-7084-dependabot-bunlock-alert-drain/spec.md` exists.

## Enhancement Summary

**Deepened on:** 2026-08-16
**Halt gates passed:** 4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped variables,
4.9 UI-wireframe (no UI surface in Files to Create/Edit — `pwa-controls.tsx` is a telemetry edit to
an existing control, so tier NONE holds and no `.pen` is required), 4.10 Encryption Posture (no
store-class file, no new cross-component connection), 4.11 Guard Contract
(`lint-guard-contract.py` → 2 guard entries, exit 0). 4.5 network-outage and 4.55
downtime-and-cutover did not trigger.

**Reviewers applied:** Kieran (correctness), code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO, CPO, and a scoped `model: fable` consult. Every finding was applied to the
plan rather than noted; the `## Plan Review` section records the ones that reversed a decision.

### Verifications run in this pass

| Check | Result |
|---|---|
| Cited AGENTS rule IDs are **active** (not retired or fabricated) | 2/2 active |
| Cited issue/PR numbers resolve **and their titles match the claim** | 9/9 — notably #1327 is genuinely the `next lint` → ESLint blocker, and #1174 is genuinely the supply-chain hardening issue behind `minimumReleaseAge` |
| Prescribed labels exist | 5/5 (`action-required`, `decision-challenge`, `follow-through`, `type/security`, `dependencies`) |
| ADR ordinal re-derived from **freshly fetched** `origin/main` | `main` at ADR-186; ADR-191 stays provisional and is re-verified before merge |
| Knowledge-base citations resolve | all resolve except the ADR-191 file this plan creates |
| Acceptance criteria containing a repo-wide grep | none — no AC can match the plan file itself |
| Verify-the-negative sweep over the plan's absence claims | see below |

### Verify-the-negative sweep

Four absence claims were probed against the tree. Three confirmed outright (no composite action runs
an install; no workflow references `.bin/claude`; no `.npmrc` is tracked). The fourth —
*"the Dockerfile contains no bun"* — came back **CONTRADICTED at 6 hits** under an unbounded
`grep -ci`, and the investigation is worth keeping: all six are the substring `bun` inside
`bundle`/`bundled`, and the word-bounded `grep -ciowE` returns 0. The claim is true; the *check* was
wrong, in exactly the way the architecture review had already caught for the C4 `model.c4` claim one
section earlier. Both claims now cite the word-bounded command they actually ran. A plan that
documents a trap and then falls into it two sections later is the failure mode this sweep exists to
catch.

### Key improvements from the deepen pass

1. The verification discipline is now consistent: every absence claim in the plan cites the exact
   command that produced it, word-bounded where substring collisions are possible.
2. The two provisional facts most likely to drift — the ADR ordinal and the live alert set — are
   both marked as re-derived rather than fixed, with the re-derivation named.
3. **A production post-mortem was folded in after the pass had otherwise closed.** The
   `learnings-researcher` agent returned very late (its result arrived after the plan was already
   committed) carrying
   `knowledge-base/engineering/operations/post-mortems/sharp-devdep-blocks-prod-deploys-postmortem.md`:
   a Dependabot `sharp` bump across the `^0.34.x` → `^0.35.x` boundary previously caused npm to
   re-resolve the top-level copy as dev-only, after which `npm ci --omit=dev` in the Docker runner
   stage installed none and production deploys were skipped for 3h+. The fix is already on `main`
   (`dependencies.sharp: ^0.35.0`, lockfile `dev: false`), but **this plan regenerates that lockfile
   across eleven bumps** and nothing in it asserted the classification survives. Added AC13b, T21b, a
   risk row, and two sharp edges. Recorded here rather than absorbed silently, because the finding
   arrived by luck of timing — had the agent failed outright, the gap would have shipped.

## Overview

Two directories in this repository resolve one dependency set through two lockfiles each. In
`apps/web-platform` the production image installs from `package-lock.json` while ten CI install sites
install from `bun.lock` under a frozen flag; the repo root carries the same pair. Dependabot
maintains only the npm lockfiles, so any bump that moves a resolved version leaves the bun lockfile
stale and the frozen install fails a required check. The failure surfaces inside a test shard rather
than as a lockfile error, so the bump reads as the cause when the second lockfile is.

The divergence is not hypothetical. Both pairs are **already** out of sync on `main`, which means CI
today validates a dependency graph that production does not ship.

This plan makes the npm lockfile the single lockfile of record in both directories, removes the bun
lockfiles, and adds a guard so a second lockfile cannot silently return. It then uses that fix to
drain the open Dependabot alert backlog, resolve the stalled Dependabot pull-request queue, and
triage the open code-scanning alerts.

## Research Insights

### Premise validation (Phase 0.6)

| Cited premise | Verified how | Verdict |
|---|---|---|
| Issue #7084 open, not already fixed | `gh issue view 7084` → `state: OPEN`, `closedByPullRequestsReferences: []` | HOLDS |
| `apps/web-platform/{bun.lock,package-lock.json,bunfig.toml,Dockerfile}` exist | direct stat | HOLDS |
| 39 open Dependabot alerts | live `gh api …/dependabot/alerts --paginate` | HOLDS — exactly 39 |
| 9 open Dependabot PRs (7503…7237) | live `gh pr list --author app/dependabot` | HOLDS — exactly those 9 |
| 3 open CodeQL alerts 214/213/203 | live `gh api …/code-scanning/alerts` | HOLDS — exact paths and rules |
| "`minimumReleaseAge` is configured in `bunfig.toml` only" | read both `bunfig.toml`; no `.npmrc` exists (`git ls-files \| grep .npmrc` → empty) | HOLDS |
| **`apps/web-platform` is *the* dual-lockfile directory** | `git ls-files \| grep -E '(bun\.lock\|package-lock\.json)$'` | **INCOMPLETE — the repo ROOT carries the same pair** |
| Implied: a `.github/dependabot.yml` exists to configure | `.github/` listing (only `dependency-review.yml`) | **FALSE — no `dependabot.yml` exists** |
| `sharp → 0.35.0` and `postcss → 8.5.23` are reachable | lockfile + registry probe | **FALSE for both** — top-level copies already patched; only `next`-nested copies are vulnerable |
| OTel bump "sits on the request-instrumentation path" | `server/inngest/client.ts:83-87` registers only Sentry/log middleware; no `NodeSDK` init anywhere | **FALSE — OTel is never initialized.** Hygiene, not risk reduction |

### Mechanism minimality (Phase 0.6b)

**Property list** — what this work must actually buy:

- **P1.** A Dependabot-shaped bump to a `package.json` in either dual directory reaches green required
  checks with no hand regeneration of any lockfile.
- **P2.** CI resolves the **same dependency versions** the production image installs. (Deliberately
  *not* "installs identically" — see P2 note below.)
- **P3.** A supply-chain release-age floor still applies to the resolver that actually picks versions.
- **P4.** The open Dependabot alerts are remediated by upgrade, never by dismissal.
- **P5.** The stalled Dependabot PRs reach a terminal state under one consistent strategy.
- **P6.** The open CodeQL alerts are resolved, or dismissed with a recorded reason and a compensating
  control.
- **P7.** The dual-lockfile divergence cannot silently return.

**P2 note.** CI installs with `--ignore-scripts` and production does not. That is intentional and
behavior-preserving: `apps/web-platform/package.json` declares no `trustedDependencies`, so bun runs
**zero** install scripts in CI today. Ten packages in that lockfile carry `hasInstallScript: true`
(`@anthropic-ai/claude-code`, `@sentry/cli`, `esbuild` ×2, `protobufjs`, `unrs-resolver`, `fsevents`
×3, `next/node_modules/sharp`). A plain `npm ci` would newly execute all of them in every CI job,
including `@sentry/cli`'s network binary download — a new egress path and a new supply-chain
execution surface on untrusted-PR workflows. P2 is therefore about resolved **versions**, which is
what the divergence actually breaks.

**Cut list** — mechanisms considered and removed before any were researched or built:

| Mechanism | Property it would buy | Why it is cut |
|---|---|---|
| Direction 1 — regenerate `bun.lock` on Dependabot branches and push | P1 only | Needs `pull_request_target` or a GitHub App token (Dependabot PRs get a read-only `GITHUB_TOKEN`, no secrets), and pushing detaches the PR from Dependabot's management. Leaves both resolvers in place, so the lockfiles stay free to diverge — and measurably already have. |
| Direction 3 — a version-parity gate as the remedy | P7 only | **Fails the acceptance bar**: the PR stays red and still needs a human regeneration. |
| **A cross-lockfile version-parity engine at all** | P7 | **Cut entirely.** Once both bun lockfiles are deleted there is nothing to compare. This dissolves a JSONC parser (`bun.lock` is not plain-`jq` parseable), a two-key-shape extractor, an allowlist, and a stale-allowlist failure mode. Measured: the root pair alone has **7 top-level version drifts** (`acorn`, `acorn-walk`, `brace-expansion`, `linkify-it`, `minipass`, `picomatch`, `yaml`), so a parity gate would have been RED on day one — the same defect that disqualified direction 3. |
| `package-ecosystem: bun` in a new `.github/dependabot.yml` | P1 | **Cannot work.** Dependabot's bun support (GA Feb 2025) covers *version* updates only; security updates are explicitly unsupported, and every alert here is a security update. |
| Move the floor to Dependabot's `cooldown:` | P3 | **Cannot work.** `cooldown` applies only to routine version updates, not security updates. The floor must live with the resolver. |
| A new dedicated CI job + required check for the guard | P7 | `lockfile-sync` is *already* a required check and already hosts a lockfile gate. Folding in avoids touching all four required-check mirror files. |

### Value-proposition measurement (Phase 0.6c)

The issue asserts direction 2 "costs bun's install speed in CI". Measured against live CI run
`31809323780` (latest successful `ci.yml` on `main`):

| Job | Step | Seconds |
|---|---|---|
| `test-webplat (1/2)` | Cache bun install (apps/web-platform) | 25 |
| `test-webplat (1/2)` | `bun install --frozen-lockfile` | 0 |
| `test-webplat (2/2)` | Cache bun install | 22 |
| `test-webplat (2/2)` | `bun install --frozen-lockfile` | 0 |
| `web-platform-build` | `npm ci` (**cached** — `setup-node` with `cache: npm` + `cache-dependency-path`, ci.yml:578-580) | 30 |
| `e2e` | `bun install --frozen-lockfile` (apps/web-platform, container) | 13 |
| `e2e` | Install `unzip` (exists only to satisfy `setup-bun`) | 10 |

**Honest conclusion: the change is roughly cost-neutral to slightly worse per job, and the plan does
not claim a speedup.** The current shape (0s install behind a 22-25s cache restore) is *not*
preserved, because `npm ci` deletes `node_modules` unconditionally before installing — so the four
`actions/cache` blocks that cache `node_modules` become dead weight.

**Correction to an earlier draft of this table, recorded because it changes the arithmetic:** the
30s `web-platform-build` figure is a **cached** `npm ci`, not an uncached one. `ci.yml:576-580`
already configures `actions/setup-node` with `cache: npm` and
`cache-dependency-path: apps/web-platform/package-lock.json`. So 30s is the *warm* number for the
largest install in the repo, and it is the realistic per-job expectation for the converted
web-platform sites rather than an upper bound to be improved on. Root's install is far smaller.
Offsetting savings: `e2e` drops both its 10s `unzip` step and its `setup-bun` step, and
`--ignore-scripts` removes install-script work bun was already skipping.

The repository is public and all jobs run on GitHub-hosted standard runners, so the regression is
wall-clock minutes, not spend. The trade is CI minutes against the integrity of the only signal a
non-technical operator can read.

### The divergence is real and already shipped

Measured directly against the committed lockfiles on this branch:

| Package | npm lockfile | bun lockfile |
|---|---|---|
| `apps/web-platform` `@opentelemetry/propagator-jaeger` | 2.8.0 | **2.7.1** (a full generation behind) |
| `apps/web-platform` `postcss` (nested) | deduped to hoisted 8.5.23 | **extra 8.5.10** copies retained |
| `apps/web-platform` `nanoid` (nested) | hoisted 3.3.16 only | **extra 3.3.11** in three places |
| root `acorn` / `acorn-walk` | 8.15.0 / 8.3.4 | **8.16.0 / 8.3.5** |
| root `brace-expansion` | 1.1.13 | **1.1.12** |
| root `linkify-it` / `minipass` | 5.0.2 / 7.1.2 | **5.0.1 / 7.1.3** |
| root `picomatch` / `yaml` | 4.0.4 / 2.8.3 | **4.0.3 / 2.8.2** |

Seven top-level drifts at root, plus nested-shape divergence, plus the web-platform drifts. This is
the load-bearing finding: CI does not merely risk testing a different graph than production ships —
**it already does**, in both directories. That reframes the change from a Dependabot-ergonomics fix
to a correctness fix.

### Decisive external facts (cited)

- **Dependabot + bun:** the `bun` ecosystem is supported for *version* updates only
  ([GitHub Changelog, 2025-02-13](https://github.blog/changelog/2025-02-13-dependabot-version-updates-now-support-the-bun-package-manager-ga/));
  security updates are listed as future work. A `bun.lock` is invisible to Dependabot security
  scanning. **Retaining the npm lockfile preserves security coverage; dropping the bun lockfile costs
  none.** This is the core rationale.
- **Dependabot `cooldown`** exists ([changelog, 2025-07-01](https://github.blog/changelog/2025-07-01-dependabot-supports-configuration-of-a-minimum-package-age/))
  but applies only to routine version updates.
- **`npm ci`** requires a lockfile in sync with `package.json` and deletes `node_modules` first
  ([npm docs](https://docs.npmjs.com/cli/v11/commands/npm-ci)).
- **`npm` release-age floor:** `npm@11` supports `--min-release-age <days>` and the `.npmrc` key
  `min-release-age`. Verified locally — `npx --yes npm@11 install --help` prints
  `[--before <date>|--min-release-age <days>]`; `npm@11 config get min-release-age` returns `null`.
  **Unit differs from bun: npm takes DAYS, bun takes SECONDS** (`259200` = 3 days).
- **The floor does not fight the regenerate-and-diff gate** — measured empirically against npm
  11.12.1, not inferred: (a) `npm ci` does not enforce `min-release-age` (rc=0 with
  `min-release-age=99999` against a satisfied lock); (b) the Dockerfile COPYs only
  `package.json package-lock.json`, never `.npmrc`, so production is doubly unaffected;
  (c) `npm install --package-lock-only` against a lock that already satisfies `package.json` is a
  no-op and does not re-resolve — which is exactly the Dependabot shape. The floor engages only on a
  genuine re-resolution. **No escape hatch is needed.**
- **`ServiceWorker.postMessage()` takes no `targetOrigin` argument** (unlike `window.postMessage`),
  and only same-origin clients within scope can obtain a `ServiceWorker` handle for a registration.

### Repo facts that constrain the design

- **`lockfile-sync` is a REQUIRED check**, declared in three places:
  `scripts/required-checks.txt` (the SSOT), `infra/github/ruleset-ci-required.tf`, and
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
  `.github/actions/bot-pr-with-synthetic-checks/action.yml` is a **consumer, not a mirror** — it
  derives `CHECK_NAMES` from `required-checks.txt`. Folding the guards into the existing job avoids
  touching any of them.
- **`apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` already states this plan's thesis** in its
  own header: *"package-lock is deploy-authoritative … NOT bun.lock which only feeds CI bun
  test/typecheck."* This plan generalizes to the whole graph what ADR-079 established for two
  packages. Section 1 (PARITY) and the `bunlock_version()` helper become dead and are removed;
  Section 2 (the `sdk-bump-verified:` ack) is unaffected and stays blocking.
- **`preflight` Check 3 "Lockfile Consistency"** is a diff-file-list check that never opens either
  lockfile — a branch touching both while leaving them at different versions passes it clean.
- **Nine of the converting workflows set up bun but not Node**, so `npm ci` there would run under
  `ubuntu-latest`'s stock Node/npm rather than Node 22 (production). Each needs `actions/setup-node`.
- **`playwright` and `@playwright/test` resolve to 1.58.2 in both lockfiles**, matching the
  `mcr.microsoft.com/playwright:v1.58.2-jammy` container tag — no browser-binary mismatch. Converting
  `e2e` deletes both the `unzip` workaround and `setup-bun`.
- **`sharp` parity holds.** Top-level `sharp@0.35.3` is identical in both lockfiles and uses prebuilt
  `@img/sharp-*` optional dependencies with no install script. The only sharp carrying
  `hasInstallScript` is `next/node_modules/sharp`, which under `--ignore-scripts` stays unbuilt —
  exactly its state today under bun.
- **Root `package-lock.json` `name` is corrupted** to `"fix-security-override-bumps-ws-jsyaml-babel"`
  (a worktree name) and root `package.json` declares no `name`, so any root `npm install` in a
  worktree rewrites it. Root becomes npm-authoritative here, so this trap must be closed.
- **`apps/web-platform/package.json` carries an `overrides` block** (`brace-expansion ^5.0.6`, `vite`,
  `ws`, `qs`, `@babel/core`, `protobufjs`) — the established lever for forcing transitive versions.
- **Test placement:** `apps/web-platform` runs vitest only (`bunfig.toml` sets
  `[test] pathIgnorePatterns = ["**"]`), collecting `test/**/*.test.ts` and `test/**/*.test.tsx`.
  Bash guard suites must be registered with a `run_suite` call in `scripts/test-all.sh` — an
  orphan-suite linter in `ci.yml` fails an unregistered suite.
- **`hr-github-api-endpoints-with-enum`** — code-scanning `dismissed_reason` values are
  space-separated (`"false positive"`, `"used in tests"`); handle HTTP 422.
- **`constitution.md:111`** — a dismissed alert must be tracked as a resolved issue with the
  dismissal reason recorded in a comment.
- **`codeql-to-issues.yml`** files an issue per open critical/high alert; its `close-orphans` job
  closes `type/security` issues once the referenced alerts read `dismissed` or `fixed`.
- **`c4-count-parity.test.sh`** parity-gates cron-monitor and component counts. This plan adds no
  scheduled workflow and no plugin component.

### Product context (from CPO assessment)

No external user is on the hosted PWA today — alpha tester #1 is on the self-hosted CLI, not
`app.soleur.ai`. Phase 4 exit criteria put ten founders on it. This is therefore the cheapest
available window to take CI and dependency risk on `apps/web-platform`: the cost of getting it wrong
today is a founder-dogfood incident, not a customer incident, and that window closes as recruitment
scales.

### Applicable institutional learnings

- `learnings/best-practices/2026-07-01-bun-lock-minimum-release-age-blocks-sdk-toolchain-bump.md` —
  the 3-day bun floor blocked toolchain bumps. Deleting `bun.lock` retires that trap for
  web-platform; the npm equivalent was measured not to reproduce it (see above).
- `learnings/2026-05-22-npm-version-pin-required-for-lockfile-sync-gate.md` — why `lockfile-sync`
  pins `npm@11`. That pin is now doubly load-bearing: `min-release-age` requires npm 11, and
  `actions/setup-node@v4.4.0` with Node 22 ships npm 10.9.x, which silently ignores the key.
- `learnings/workflow-patterns/2026-05-19-dependabot-prs-need-bun-lock-resync-and-override-dedup.md`
  — the documented supersede workflow that Part 3 follows.
- `learnings/workflow-patterns/2026-07-18-plan-prescribed-bun-update-for-transitive-bump-is-banned.md`
  — `bun update` for a transitive bump was caught and reverted at work time.
- `learnings/2026-05-27-npm-update-rewrites-lockfile-name-in-worktrees.md` — the root-lockfile `name`
  rewrite trap, live in this repo right now.
- `learnings/2026-04-03-lockfile-sync-ci-check-pattern.md` — the regenerate-and-diff pattern extended
  here. Canonical regeneration command: **`npx --yes npm@11 install --package-lock-only`**, never
  local npm — `npm install --package-lock-only` uses the same Arborist resolver as `npm ci`, which is
  what gives the gate detection parity.
- `knowledge-base/engineering/operations/post-mortems/sharp-devdep-blocks-prod-deploys-postmortem.md`
  — **the highest-value late finding of the research pass, and a live hazard for Phase 3.** A
  Dependabot bump moved `sharp` `^0.34.5` → `^0.35.0`; because `next` declares `sharp` as an
  `optionalDependency` at `^0.34.3`, `0.35.x` no longer satisfied it and npm re-resolved the
  top-level copy as **dev-only** (`"dev": true`). `npm ci --omit=dev` in the Docker runner stage then
  installed no `sharp` at all, failing the build and skipping the deploy for 3h+. The fix — promoting
  `sharp` to `dependencies` explicitly — is already on `main` (verified: `dependencies.sharp` is
  `^0.35.0`, and the lockfile records `dev: false, optional: false`). The hazard is that **this plan
  regenerates that lockfile across eleven bumps**, and nothing in it asserted the classification
  survives. See AC13b and T21b.

### Anti-vacuity precedent

The repo's established shape is *count the scanned set and assert a floor*, e.g. the actionlint hang
guard in `ci.yml`:

```bash
count=$(find .github/workflows -maxdepth 1 -name '*.yml' | wc -l)
if [ "$count" -lt 40 ]; then
  echo "::error::actionlint hang guard found only ${count} workflow files..."
  exit 1
fi
```

`scripts/marketplace-manifest-validate.sh` adds the complementary half: reject a missing, empty, or
absent argument before processing, and print a count on success. The new guard adopts both.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Codebase reality | Plan response |
|---|---|---|
| `apps/web-platform` is the dual-lockfile directory | The repo **root** carries the same pair, with 7 measured top-level drifts. `pencil-setup/scripts/` and `spike/` are npm-only. | Convert **both** directories in this PR. See Alternatives for why this is cheaper than the alternative, not more expensive. |
| "CI's `test-webplat` and `e2e` shards install from `bun.lock`" | **Ten** web-platform install sites across **nine** workflows, plus **four** root sites. `e2e` alone installs twice (root and web-platform). | `## Files to Edit` enumerates all of them, derived from `git grep`. |
| Companion finding: the release-age floor is bun-only, so resolvers disagree | Under the chosen direction there is only one resolver, so "resolvers agree" holds by construction. The live question is whether the floor's protection survives. | Port to `.npmrc` `min-release-age=3` (days, not seconds) in both directories. |
| Fix by configuring Dependabot for bun | No `.github/dependabot.yml` exists, and bun security updates are unsupported. | Cut. A separate, explicit defer decision covers whether to create the file at all. |
| `sharp` → 0.35.0 | Top-level `sharp` is **already 0.35.3**. Only `node_modules/next/node_modules/sharp@0.34.5` is vulnerable, held by `next@15.5.22`'s `optionalDependencies.sharp: "^0.34.3"`. `next@15.5.23` still declares `^0.34.3`; only `next@16` widens it. | **Blocked.** Leave alert 144 open with the *reachability* reason, plus a compensating control. |
| `postcss` → 8.5.23 | Top-level `postcss` is **already 8.5.23**. `next@15.5.22` pins postcss to the exact string `8.4.31`, satisfying all three alerts' ranges. | **Blocked.** Leave 161/162/170 open with the same reasoning. |
| Residual alerts read as a benign tail | Actual severities are **3 high + 1 medium** (161 high, 162 high, 170 medium, 144 high). | Record true severities so the disposition is auditable. |
| `@opentelemetry/propagator-jaeger` sits on the request path | **OTel is never initialized.** No `NodeSDK` anywhere; it arrives transitively via `inngest@3.54.2` whose OTel middleware is opt-in and not enabled (`server/inngest/client.ts:83-87`). | Bump is hygiene. Drop the runtime-smoke-test risk framing; do not spend attention here. |
| CodeQL 203 (`js/missing-origin-check`) should be fixed | `ServiceWorker.postMessage()` has no `targetOrigin`; only same-origin in-scope clients can reach the handler; the worst-case effect is `skipWaiting()` — exactly what the user's own button does. `event.origin` on `ExtendableMessageEvent` is not uniformly populated, so a naive check can brick updates for every iOS PWA user. No existing test *executes* the handler. | **Reversed: dismiss with a recorded reason plus a compensating regression assertion.** See Phase 5. |
| CodeQL 213/214 are shell-injection risks | Both pass the env-derived absolute path as **argv** to `bash -c script name arg`, read as a quoted `"$1"`; the script text is constant. Exploitation presupposes control of the checkout path. | Remove the `bash -c` inline-script sink where it does not defeat the tests' load-bearing "execute, don't match" property. |

## Open Code-Review Overlap

**None.** Checked 64 open `code-review` issues (`gh issue list --label code-review --state open
--limit 200`) against every path in `## Files to Edit` and `## Files to Create` via a standalone
`jq --arg` containment query. No open scope-out names any file this plan touches.

## User-Brand Impact

**If this lands broken, the user experiences:** an "Update available" pill in the web app that does
nothing when clicked. `handleReload()` in `components/pwa/pwa-controls.tsx` calls
`postSkipWaiting(waiting)` and nothing else; the reload happens only via a separate `controllerchange`
listener in `lib/pwa/sw-update.ts`. If the worker never activates, there is no error, no state change,
and no feedback — the user clicks Reload repeatedly and stays pinned on a cache-first stale app shell.
The `?sw-reset` kill switch exists but requires knowing a URL parameter no founder would discover
unaided. With approximately one hosted user, this is a 100%-of-users incident.

**If this leaks, the user's data is exposed via:** a supply-chain compromise reaching the production
image. Two vectors are in scope here: removing bun's `minimumReleaseAge` floor without replacing it
would re-open a 3-day window in which a freshly-published malicious version of any transitive
dependency could be resolved into `package-lock.json` and installed by `npm ci` in the runtime image;
and the ten install-script packages in that lockfile — including `@sentry/cli`'s network binary
download — reaching CI execution on untrusted fork-PR code.

**That second vector is not hypothetical and not introduced by this plan: it is live today.**
`ci.yml:587` (`web-platform-build`) runs a bare `npm ci` in `apps/web-platform`, `ci.yml` triggers on
`pull_request`, and a fork PR controls `apps/web-platform/package.json`. All ten scripts already
execute there on untrusted code. An earlier draft of this plan described `--ignore-scripts` as
*preventing a new* risk while leaving that live instance untouched — the framing was backwards, and
correcting it turns a defensive flag into an actual remediation.

**Brand-survival threshold:** `single-user incident`

Consequences: `requires_cpo_signoff: true` is set and CPO sign-off is recorded in `## Domain Review`;
`user-impact-reviewer` is invoked at review time (the second of the two required sign-offs);
plan-review escalates to include `architecture-strategist` and `spec-flow-analyzer`.

## Alternative Approaches Considered

The acceptance bar is decisive: *a Dependabot-shaped bump to `apps/web-platform/package.json` reaches
green required checks without a human hand-regenerating a lockfile.*

| Direction | Meets the bar? | Assessment |
|---|---|---|
| **1 — regenerate `bun.lock` on Dependabot branches and push** | Yes | Rejected. Needs `pull_request_target` (trusted code with secrets against untrusted PR content) or a GitHub App token, because Dependabot PRs receive a read-only `GITHUB_TOKEN` with no secrets. Pushing detaches the PR from Dependabot's management. Leaves both resolvers in place, so the lockfiles remain free to diverge — and measurably already have, in both directories. Highest complexity, largest security surface, treats the symptom. |
| **2 — the npm lockfile becomes the single lockfile of record** | **Yes** | **Chosen.** |
| **3 — keep both, add a version-parity gate** | **No** | Rejected as the remedy. It converts an opaque frozen-lockfile error into a clear "regenerate bun.lock" one — a real diagnostic gain — but the PR stays red and still needs a human regeneration, which is exactly what the bar forbids. It would also be RED on day one against the measured drift. |
| **2b — drop `package-lock.json` and let bun be authoritative** | Yes | Rejected, recorded because it is the symmetric option. `package-lock.json` is what the production image installs and the only lockfile Dependabot security-scans. Dropping it would make the entire dependency tree invisible to security alerting — alert-hiding rather than remediation. |
| **2c — convert `apps/web-platform` only, allowlist root with a parity gate** | Partially | Rejected after measurement. The root pair has **7 top-level version drifts**, so the parity arm would ship RED on day one — the identical defect that disqualified direction 3. Shipping a gate known to be red is not an option, and downgrading it to a bare exemption would leave root's Dependabot PRs still born red. |

**Why direction 2, applied to both directories.** Four reasons converge:

1. **It is the only direction that meets the bar** without a token escalation or a PR-detachment side
   effect.
2. **It fixes a live correctness defect.** Both pairs are already divergent on `main`. Deleting the
   second lockfile is the only direction that makes a green CI run mean what everyone assumes.
3. **It is free in security coverage.** The npm lockfile is the one Dependabot security-scans and the
   one production installs; the bun lockfile is scanned by nothing.
4. **Converting root removes more work than it adds.** It is 122 top-level dev-dependency packages,
   and root already has npm consumers (`critical-css-gate`, `deploy-docs.yml`). Converting deletes the
   need for a JSONC `bun.lock` parser, a two-key-shape extractor, an allowlist mechanism, and the
   surgical `bun.lock` resync that Part 3 would otherwise require for the root bumps. The guard
   collapses to a single existence invariant.

Bun is **not** removed from the repo. It remains the test runner and script runtime
(`bun test plugins/soleur/`, `scripts/test-all.sh bun`, `bun scripts/*.ts`). Only the *install* path
changes. Install tool and test runner are independent concerns, and npm's hoisted `node_modules`
layout is what bun already expects.

**Deferred with an explicit decision: creating `.github/dependabot.yml`.** There is none today, so
Dependabot emits security-advisory PRs only. Adding `package-ecosystem: npm` entries would enable
scheduled *version* updates — a new, ongoing PR stream and a separate operational decision that no
property in the Property List requires. This plan therefore does **not** create the file, and says so
in the PR body so no reader assumes "Dependabot fix" meant "Dependabot configured." A follow-up issue
carries the decision with re-evaluation criteria.

## Implementation Phases

### Phase 0 — Preconditions

0.1 Re-query and snapshot live state into the branch spec directory: open Dependabot alerts, open
    Dependabot PRs, open CodeQL alerts. The numbers here are a 2026-08-16 reading.
0.2 Re-derive the install-site inventory **repo-wide**, never scoped to `.github/workflows/`:
    `git grep -nE '(bun install|npm ci)' -- ':!knowledge-base' ':!*.md'`. An earlier draft scoped this
    grep to the workflows directory and thereby reproduced its own blind spot by construction — two
    live install sites sit outside it (`plugins/soleur/scripts/grok-fidelity-gate.sh:28` and
    `apps/web-platform/.github/workflows/constraint-gates.yml:54`), and both feed required checks.
    The inventory must cover five syntactic forms (`working-directory:`, a `cd` inside `run:`,
    `npm ci --prefix <dir>`, a bare repo-root install, and `run: |` blocks) **and** three location
    classes: repo-root workflows, nested `apps/*/.github/workflows/`, and plain shell scripts under
    `scripts/` and `plugins/`.
0.2b **Measure the release-age floor against global exact pins before adopting it at root.** Root-cwd
    commands include `npm install -g likec4@1.50.0` (`ci.yml:766`, `main-health-monitor.yml:252`),
    `npm install -g "@anthropic-ai/claude-code@${CLI_VERSION}"`
    (`scheduled-marketplace-drift.yml:204`), and `npm install --no-save playwright@1.60.0`
    (`ci.yml:980`, `deploy-docs.yml:126`). A root `.npmrc` applies to all of them. On the PR that
    bumps `CLI_VERSION` to a freshly published release — exactly what `/soleur:model-launch-review`
    does on every Anthropic model launch — an exact pin younger than the floor resolves to *no
    matching version*. Run `npm install -g <pkg>@<version-published-today>` under
    `min-release-age=3` and record the result. **Decision rule:** if it fails, do not create the root
    `.npmrc`; scope the floor to `apps/web-platform`, `pencil-setup/scripts`, and `spike`, and record
    root's exemption and its reason in ADR-191.
0.3 Confirm `npx --yes npm@11 install --help | grep -- '--min-release-age'` prints a line.
0.4 Re-derive the next free ADR ordinal across **all** `origin/*` refs (measured 2026-08-16 across 67
    refs: `main` at ADR-186, ADR-187–190 claimed on unmerged branches, so **ADR-191 is provisional**).
0.5 Record baseline CI timings for every job being converted, to feed Phase 6.1's budgeted delta.
0.6 Confirm `apps/web-platform/next.config.ts` declares **no `images` key at all** — verified
    2026-08-16. This is the invariant that makes the sharp deferral safe, and it is deliberately
    wider than `images.remotePatterns`: `images.domains` (the deprecated Next 15 equivalent, still
    functional) and a custom `images.loader` each revive the advisory's reachability while a
    `remotePatterns`-keyed check stays green.
0.7 **Publish the alert arithmetic** (see the reconciliation table in Phase 3). Emit the full
    39-alert → package → target → expected-disposition mapping into the branch spec directory. The
    residual count is a *derived* number; until the mapping is written down, "4 remain" is a
    prediction rather than a result, and every later verification asserts against it.

### Phase 1 — RED: guards and tests that fail on today's tree

Written before the fix, derived from the design rather than the implementation.

1.1 Create two guard scripts, deliberately split so each one's anti-vacuity floor is obviously
    matched to its own enumeration: `scripts/lint-dual-lockfile.sh` (Guard 1, scans tracked files)
    and `scripts/lint-workflow-install-sites.sh` (Guard 2, scans workflow YAML). A single script
    hosting both would fail the name test for half its job. Create a `.test.sh` for each and register
    both with `run_suite` calls in `scripts/test-all.sh`.
1.2 Guard 1 is RED on the current tree — both `apps/web-platform/bun.lock` and root `bun.lock` exist,
    and both `bunfig.toml` files declare `[install]`. Capture as pre-fix evidence.
1.3 Guard 2 is RED on the current tree at fourteen `bun install` sites. Capture as pre-fix evidence.
1.4 Add the `next.config.ts` **no-`images`-key** regression assertion (CPO condition 3).
1.5 Add the service-worker handler-scope assertion (CPO condition 1): the `message` handler's sole
    effect remains `skipWaiting`.
1.6 Build the fixture corpus for both mutation matrices, including the must-PASS non-canonical inputs.

### Phase 2 — GREEN: the npm lockfile becomes the single lockfile of record

**2.0 — Graph-switch proof (blocking precondition).** Today's green CI is evidence about the **bun**
dependency graph. The two graphs are measurably divergent, so a green `main` is *zero* evidence that
the suite passes on the graph this plan switches to. Push a scratch branch carrying **only** the
install-site conversion — no lockfile deletion, no `bunfig`/`.npmrc` change, no version bumps — and
drive the full required-check matrix green against `package-lock.json`'s *exact current pins*. This
isolates three otherwise-confounded failure causes: runner/flag change, graph change, version bump.

If the scratch matrix is **red**, stop and re-scope. Recorded fallback: split delivery into a
mechanical graph-switch PR and a separate bumps PR, rather than reverting the architecture decision
because a shard failure could not be attributed.

Staging note: commits are ordered per §2.10 below, but that ordering buys **no CI-level safety** on
its own — this repository squash-merges, so intermediate commits never run CI independently. §2.0 is
the real staging mechanism and the honest answer to CPO condition 6.

2.1 Convert the **sixteen** `bun install` sites to `npm ci --ignore-scripts`. Fourteen live under
    `.github/workflows/`; the remaining two are the ones a workflows-scoped grep cannot see:

    - **`plugins/soleur/scripts/grok-fidelity-gate.sh:28`** — a bare root `bun install
      --frozen-lockfile` under `set -euo pipefail`, invoked from `ci.yml:790` in the **required**
      `grok-fidelity` check. A deleted root `bun.lock` makes it exit non-zero and fails that check.
      It needs root `yaml` for `plugins/soleur/lib/agent-registry.ts`; npm hoisting is equivalent.
    - **`apps/web-platform/.github/workflows/constraint-gates.yml:54`** — see 2.1b.

2.1b **The constraint-gates byte-parity triad must move in one commit.** Three files carry the
    identical install line and are diffed byte-for-byte by
    `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` (checks 3-4), which runs in the
    `test-scripts` shard feeding the synthetic `test` required check:

    - `.github/workflows/constraint-gates.yml:62`
    - `apps/web-platform/.github/workflows/constraint-gates.yml:54`
    - `plugins/soleur/skills/constraint-scaffold/references/constraint-gates-workflow.template:54`

    Converting only the first turns `test-scripts` red.

2.1c **Decide the tenant-template boundary explicitly.**
    `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template:87` emits
    `bun install --frozen-lockfile --ignore-scripts` into *customer* repos, and `parity.test.sh`
    deliberately exempts Stage A from body-diffing, so nothing catches it either way. Tenant repos are
    not this repo and may legitimately stay bun-based — but that is a product-surface decision, and
    leaving it unmade is the failure. Record the choice in ADR-191.

    **`--ignore-scripts` on the converted sites is behavior-preserving:**

    `apps/web-platform/package.json` declares no `trustedDependencies`, so bun runs zero install
    scripts today. Empirically confirmed against a bun-installed tree — a live model of the post-change
    CI state: `./node_modules/.bin/esbuild --version` and `sentry-cli --version` both work without
    their postinstalls (platform-optional packages), `protobufjs`'s postinstall is a pure stderr
    warning, `unrs-resolver`'s is a *check*, and `@anthropic-ai/claude-code`'s shim already reports
    `native binary not installed … --ignore-scripts` today. `npm ci --ignore-scripts` reproduces the
    current state exactly.

2.2 **Also add `--ignore-scripts` to the four pre-existing bare `npm ci` sites** — `ci.yml:587`
    (`web-platform-build`), `ci.yml:954` (`critical-css-gate`, root), `deploy-docs.yml:67` (root),
    and `scheduled-realtime-probe.yml:50` (`npm ci --prefix apps/web-platform`). These are **not** a
    scope addition for tidiness; `ci.yml` triggers on `pull_request`, a fork PR controls
    `apps/web-platform/package.json`, and `web-platform-build` therefore already executes all ten
    `hasInstallScript` packages — including `@sentry/cli`'s network binary download — on untrusted
    code today. This is a **live** arbitrary-execution and egress path, not one this plan would
    introduce.

    `web-platform-build` runs `next build` immediately after its install, so this is the one site
    where `--ignore-scripts` carries functional risk. Phase 2.0's scratch matrix is where that is
    determined: if `next build` fails, enumerate exactly which of the ten packages it needs and add
    an explicit `npm rebuild <pkg>` with a comment naming why — do not drop the flag and do not leave
    the package set unnamed. Total install-site inventory after this phase: **eighteen**.

2.3 Add `actions/setup-node` with `node-version: 22`, `cache: npm`, and `cache-dependency-path` to
    the **eight** workflows that install with bun but pin no Node: `cla-evidence`,
    `constraint-gates`, `fix-constraints-stage-a`, `rls-authz-fuzz`, `scheduled-terraform-drift`,
    `tenant-integration`, `validate-vector-config`, `web-platform-release`. (`ci.yml` and
    `main-health-monitor.yml` already have `setup-node`. The `e2e` job deliberately does not — it
    runs in the Playwright container whose comment records *"Image ships Node 24 (no
    actions/setup-node needed)"* — and it keeps that container Node.)

2.4 **Delete all four `actions/cache` blocks** rather than re-pointing them (`ci.yml:638`,
    `ci.yml:684`, `rls-authz-fuzz.yml:98`, `tenant-integration.yml:152`). `npm ci` deletes
    `node_modules` unconditionally, so caching it is worse than useless, and the repo already has the
    right pattern: `web-platform-build` uses `setup-node`'s `cache: npm` +
    `cache-dependency-path` (`ci.yml:576-580`). Phase 2.3 adds `setup-node` to eight workflows
    anyway, so the caching comes with it — one convention, four fewer blocks, no hand-rolled
    `actions/cache` on `~/.npm`.

2.5 Remove `setup-bun` and the `e2e` job's `unzip` install from jobs that no longer run bun. Leave
    `setup-bun` intact wherever the job still *runs* bun (`bun test`, `bun scripts/*.ts`) — Guard 2's
    third property enforces this rather than leaving it to a hand check across eight workflows. In
    particular **do not strip `setup-bun` from `test-scripts`**:
    `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh:93` asserts
    `check_runtime "bun" 'oven-sh/setup-bun'` for that job.

2.6 **Retire every reader of `bun.lock` BEFORE deleting it — but retire only the bun half.**

    Readers: Section 1 of `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` and its
    `bunlock_version()` helper (`:78`, section at `:87`), the corresponding
    `sdk-bump-sandbox-gate.test.sh` fixtures, and the four `hashFiles('…bun.lock')` cache keys
    (`ci.yml:644`, `ci.yml:690`, `rls-authz-fuzz.yml:104`, `tenant-integration.yml:158`) that Phase
    2.4 removes with their blocks. `sdk-bump-sandbox-gate.sh` is invoked by the **`lockfile-sync`
    required check itself**, so deleting `bun.lock` first would turn red the very check this plan
    folds its guards into.

    **Do not delete Section 1 wholesale — that would reopen the exact silent-green class ADR-079
    exists to close.** Section 2's bump detection is
    `[[ -n "$base_v" && -n "$head_v" && "$head_v" != "$base_v" ]]` (`:131`), which short-circuits to
    green on an **empty** `head_v`. The only thing catching an empty `head_v` today is Section 1's
    `[[ -z "$pv" ]]` arm at `:91`, which errors when an SDK package is absent from the
    deploy-authoritative lockfile. Retire only `bunlock_version()`, the `BUN_LOCK` /
    `SDK_GATE_BUN_LOCK` variables, the `[[ -z "$bv" ]]` arm at `:96`, and the `bv` comparison.
    **Keep the `[[ -z "$pv" ]]` arm**, rename the section PARITY → **PRESENCE**, and add a mutation
    row proving that a package absent from `package-lock.json` drives the gate RED. Update the stale
    ADR-079 rejected-alternative and the `ci.yml:454` comment.

2.7 Delete `apps/web-platform/bun.lock` and root `bun.lock`.

2.8 Remove the `[install]` block from both `bunfig.toml` files; keep both `[test]` blocks byte-for-byte
    (independently load-bearing for vitest/happy-dom isolation, #1469). Add `.npmrc` with
    `min-release-age=3` to `apps/web-platform`, `plugins/soleur/skills/pencil-setup/scripts`, and
    `spike` — one file per directory, because npm reads `./.npmrc` from the install cwd and does
    **not** traverse to a parent (measured: with `min-release-age=7` in a parent,
    `npm config get min-release-age` from the child returns `null` under npm 11.12.1). Phase 3.2
    actively bumps `pencil-setup/scripts`, so leaving it floorless would apply the supply-chain policy
    to two of four directories while the plan claims P3. **Root's `.npmrc` is conditional on Phase
    0.2b's measurement** — root-cwd global exact pins would break under the floor.

    Also add `.npmrc` to `apps/web-platform/.dockerignore`. An earlier draft claimed as measured fact
    that *"the Dockerfile COPYs only `package.json package-lock.json`, never `.npmrc`"* — that is
    **false**: `apps/web-platform/Dockerfile:10` is `COPY . .` and `.dockerignore` excludes
    `node_modules` and `.env*` but not `.npmrc`. The conclusion survives on different grounds — the
    deps-stage `npm ci` at `:5` precedes `COPY . .`, and no dependency-resolving npm command runs
    after it — but that is an unguarded invariant, so the `.dockerignore` entry makes it explicit.

    Each `.npmrc` carries a comment recording the seconds→days unit change, issue #1174, and that the
    key is load-bearing on `lockfile-sync`'s existing `npm@11` pin (npm 10.x silently ignores it).

2.8b **Sweep the agent-facing prose that would otherwise resurrect `bun.lock`.** Guard 1 catches a
    recreated file; it cannot catch a skill instructing the next agent to create one. Six surfaces:
    `plugins/soleur/skills/drain-prs/SKILL.md:92` (prescribes
    `bun install && bun install --frozen-lockfile  # bun.lock — must exit 0` as the deps-PR recipe),
    `model-launch-review/SKILL.md:121-126`, `work/SKILL.md:680`, `plan/SKILL.md:1119`,
    `knowledge-base/project/constitution.md:178,182` (names `trustedDependencies` +
    `minimumReleaseAge` as active controls), and
    `knowledge-base/engineering/architecture/nfr-register.md:365-367` (cites `bun.lockb`). Sweeping
    these is what makes P7 hold behaviorally rather than only mechanically.

2.8c **Fix `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:1544`.** Its per-app branch
    (`:1566-1580`) already detects the lockfile and falls back to `npm ci --prefix`; the **root**
    branch does not. Without this, every worktree created by `/soleur:one-shot`, `/work`, or `/ship`
    prints "Warning: bun install failed" and ships with no root `node_modules`, breaking
    `bun test plugins/soleur/` and the pre-push hook on every fresh worktree — self-inflicted on the
    very next feature, including any follow-up to this one.

2.8d **Decide `AGENTS.rules.md:118` explicitly.** `cq-before-pushing-package-json-changes` says both
    lockfiles are regenerated "if both exist". The clause is self-disarming, so leaving it is *safe*,
    but it leaves misleading guidance loaded every turn. Editing a rule **body** is human-gated by the
    per-change hash-bound WORM ack of AP-017 / ADR-092, enforced by the always-run `rule-body-lint`
    required check — so this is a budgeted decision, not a drive-by edit. Record the choice either way.

2.9 Add a `name` to root `package.json` and repair root `package-lock.json`'s `name`.

2.10 **Then** extend `lockfile-sync` to cover root's `package-lock.json` and invoke both guards, so no
    new required check is created. This must come **after** 2.9: root `package.json` has no `name`
    today, so extending the regenerate-and-diff gate to root before repairing it would rewrite `name`
    to the checkout directory, produce a non-empty diff, and fail the gate on its own introduction
    commit.

**Phase 2 commit order:** 2.1 → 2.2 → 2.3 → 2.4 → 2.5 → **2.6 (retire readers)** → 2.7 (delete
lockfiles) → 2.8 → 2.9 → 2.10. The invariant: *every reader of an artifact is retired before the
artifact is deleted, and every gate is repaired before its scope is widened.*

### Phase 3 — Drain the alert backlog

Phase 2 is a precondition: without it every web-platform and root remediation lands red.

**Alert reconciliation — the 39 → 4 arithmetic, published.** Resolve per package to the highest
required version, never per alert.

| Package | Manifest | Alert IDs | Count | Target | Disposition |
|---|---|---|---|---|---|
| `brace-expansion` | web-platform | 126, 166, 168 | 3 | 5.0.9 (via `overrides`) | cleared |
| `brace-expansion` | root | 127 | 1 | 1.1.16 (via new root `overrides`) | cleared |
| `fast-uri` | web-platform | 142, 145, 171 | 3 | 3.1.5 | cleared |
| `fast-uri` | pencil-setup | 177 | 1 | 3.1.5 | cleared |
| `hono` | web-platform | 181, 186, 188, 189 | 4 | 4.12.34+ | cleared |
| `hono` | pencil-setup | 185, 187, 190, 191 | 4 | 4.12.34+ | cleared |
| `@hono/node-server` | web-platform | 197 | 1 | 1.19.15+ (stay 1.x) | cleared |
| `@hono/node-server` | pencil-setup | 198 | 1 | 1.19.15+ (stay 1.x) | cleared |
| `ip-address` | web-platform | 178, 179, 180 | 3 | 10.3.1+ | cleared |
| `ip-address` | pencil-setup | 182, 183, 184 | 3 | 10.3.1+ | cleared |
| `js-yaml` | web-platform | 192, 193 | 2 | 4.3.1 and 3.15.1 | cleared |
| `js-yaml` | root | 195, 196 | 2 | 4.3.1 and 3.15.1 (3.x needs `overrides`) | cleared |
| `nanoid` | web-platform | 199 | 1 | 3.3.18 | cleared |
| `@opentelemetry/propagator-jaeger` | web-platform | 143 | 1 | 2.9.0 via a 3-package chain | cleared |
| `undici` | web-platform | 172, 173, 174, 175, 176 | 5 | 7.29.0 (stay 7.x) | cleared |
| **`postcss`** | web-platform | **161, 162, 170** | **3** | 8.5.23 | **BLOCKED** — `next` pins exact `8.4.31` |
| **`sharp`** | web-platform | **144** | **1** | 0.35.0 | **BLOCKED** — `next` pins `^0.34.3` |

**35 cleared + 4 blocked = 39.** The residual is derived, not asserted. If the live re-query at
Phase 0.1 returns a different set, this table is regenerated first and the residual expectation moves
with it.

3.1 `apps/web-platform`: `nanoid` 3.3.18, `js-yaml` 3.15.1 + 4.3.1, `hono` 4.12.34+,
    `@hono/node-server` 1.19.15+, `ip-address` 10.3.1+, `fast-uri` 3.1.5, `undici` 7.29.0,
    `brace-expansion` 5.0.9 via the existing `overrides` entry, and the `@opentelemetry` chain
    (`sdk-node` 0.219→0.220, `auto-instrumentations-node` 0.77→0.78) to reach `propagator-jaeger`
    2.9.0.
3.2 `plugins/soleur/skills/pencil-setup/scripts`: `hono`, `@hono/node-server`, `ip-address`,
    `fast-uri`. Already npm-only; unaffected by Phase 2.
3.3 Root: `js-yaml` 3.15.1 + 4.3.1, `brace-expansion` 1.1.16. **Root `package.json` declares no
    `overrides` block**, and the vulnerable `js-yaml` 3.x copy is nested under `gray-matter` while
    `brace-expansion` 1.x is nested under `minimatch` — neither is reachable without one. Add an
    `overrides` block to root `package.json`, mirroring the established web-platform lever. No
    `bun.lock` resync is needed: Phase 2.7 deleted it. `bun update <pkg>` and bare `bun update` remain
    banned in executable files.
3.4 Leave alerts 144 (sharp, **high**) and 161/162/170 (postcss: **high, high, medium**) open, never
    dismissed. Record the *reachability* reason, not "blocked behind next 16":
    - Both packages exist twice. Top-level copies are already patched (`sharp@0.35.3`,
      `postcss@8.5.23`); only the `next`-nested copies are vulnerable.
    - The user-upload path (`app/api/workspace/logo/route.ts:86,117`, which calls `sharp(...)` on
      attacker-supplied bytes) imports the **patched top-level** sharp.
    - The only `next/image` call site renders a first-party static asset
      (`app/(public)/invite/[token]/page.tsx:68`), and `next.config.ts` declares no `images`
      configuration, so the optimizer cannot fetch a remote or user-supplied URL.
    - **Recorded residual, not claimed closed:** a same-origin proxy route would reach the nested
      decoder without any `images` config — `<Image src="/api/workspace/logo/…">` is a *local* src
      that Next's optimizer fetches and decodes itself. `logo_url` currently has zero consumers and
      the route exposes only `POST`/`DELETE`, so the path does not exist today. It is also partly
      mitigated: the stored object is re-encoded to WebP by the **patched top-level** sharp before
      storage, so the optimizer would decode server-canonicalized bytes rather than raw attacker
      input. This residual is stated in the deferral note and in the follow-up issue rather than
      being papered over by a guard that only watches the config key.

### Phase 4 — Resolve the stalled Dependabot PR queue

4.1 Strategy: **close all nine as superseded**, applied consistently. Each is subsumed by a Phase 3
    bump at an equal-or-higher version, as measured 2026-08-16.
4.2 Implement the sweep as an idempotent script, not prose: skip PRs already closed, record which
    succeeded so a partial failure is resumable, and never double-comment.
4.3 **Re-verify subsumption immediately before each close.** Dependabot rebases open PRs; if a new
    advisory has moved one of the nine to a *higher* target than Phase 3 delivered, closing it as
    "superseded" would silently drop a real security bump. Read each PR's current target version and
    assert `delivered >= target`; on failure, do not close — escalate.
4.4 **Expect Dependabot to self-close most of them.** After the consolidated PR merges, Dependabot
    rebases and closes any PR whose dependency is already at or above the required version — with
    **no comment naming a superseding PR**. That is the *success* path, so the completion criterion is
    "all nine closed, each either carrying our supersede comment or self-closed by Dependabot after
    the delivered version satisfied it", not "all nine carry our comment".

### Phase 5 — Code-scanning alerts

5.1 **Alert 203 — dismiss as a false positive** (CPO condition 1, reversing this plan's earlier
    default). Recorded reason: `ServiceWorker.postMessage()` accepts no `targetOrigin`, so there is
    nothing to tighten at the send site; only same-origin in-scope clients can obtain a handle to this
    registration; and the handler's worst-case effect is `self.skipWaiting()` — precisely what the
    user's own Reload button does, with no read, no write, and no privilege change. Against that, a
    wrong check is a silent, feedback-free update lockout, and `event.origin` on
    `ExtendableMessageEvent` is not uniformly populated across browsers, so a naive predicate can
    brick updates for every iOS PWA user.

    Sequencing matters and is easy to get wrong: alert 203 is **medium** severity, and
    `.github/workflows/codeql-to-issues.yml` files tracking issues only for **critical/high** — so
    there is probably **no existing issue to comment on**. Create the tracking issue explicitly,
    record the dismissal reason in a comment on it per the constitution's dismissed-alert rule, and
    apply the `keep-open` marker that `close-orphans` honors **before** dismissing, or that job will
    close the issue on its next daily run for the very reason the plan just satisfied.

    The Phase 1.5 handler-scope assertion is the compensating control: if the handler ever gains a
    real capability, the test fails and forces the origin-check conversation on the diff where it can
    actually be reasoned about.

5.2 **Add telemetry to the PWA update-accept path** (CPO condition 2). Today `lib/pwa/sw-update.ts`
    and `components/pwa/pwa-controls.tsx` contain no Sentry and no logger, so a broken update flow is
    invisible to operator and team alike. A Reload click producing no `controllerchange` within a
    bounded interval must report to Sentry, **and a Sentry alert rule must exist for that event** — an
    event nobody is paged on is a log, not observability.

    **Recorded honestly: this mechanism buys none of P1–P7.** It addresses a pre-existing defect that
    predates this branch, and nothing else in this plan touches `public/sw.js` or the update path. It
    is carried because CPO condition 2 is blocking at the `single-user incident` threshold, and it is
    the plan's only non-property mechanism. The fallback if it grows is to split it to its own issue.
    Fold its coverage into the existing 189-line `apps/web-platform/test/pwa/sw-update.test.ts`, which
    already builds the `makeContainer(controller)` / `fire("controllerchange")` harness — a new file
    would re-derive ~40 lines of scaffolding for one behavior.

5.3 **Alerts 213 and 214 — fix.** Remove the `bash -c` inline-script sink by writing the harness
    script to a temp file and invoking `bash <file> <path>`, keeping the path in argv. The rewrite
    must preserve `plan-skeleton-checkpoint.test.ts`'s load-bearing property — it *executes* the
    skill's own prescribed reader rather than pattern-matching it, and `extractReaderSnippet` requires
    exactly one matching bash block. If that property cannot be preserved, dismiss with
    `"used in tests"` and record the justification.

### Phase 6 — Verify and report

6.1 Re-measure converted-job install timings from a real run; report the delta against Phase 0.5
    **against an explicit budget**: if aggregate added wall clock across the converted jobs exceeds
    **+5 minutes** per full CI run, record it as a finding and tune the `setup-node` caches rather
    than leaving an open-ended cost question. CI cost is the most likely trigger for a "revert it"
    reaction even when the change is correct.
6.2 Dispatch each converted scheduled workflow post-merge (`gh workflow run`) — the low-traffic paths
    never run on the PR itself.
6.3 **Verify the alert drain in-session, not via a scheduled probe.** Re-query
    `gh api repos/:owner/:repo/dependabot/alerts --paginate`, polling with backoff to absorb
    Dependabot's post-merge rescan latency, and report the actual open set against Phase 0.7's derived
    expectation, itemized by alert ID.

    **A scheduled follow-through probe was designed and then cut, and the reason is recorded so it is
    not reintroduced:** `scheduled-followthrough-sweeper.yml` runs with `permissions: contents: read`
    + `issues: write` and `GH_TOKEN: secrets.GITHUB_TOKEN`. The Dependabot alerts REST API is not
    readable by `GITHUB_TOKEN`, and **no workflow `permissions:` key grants it** — it needs a GitHub
    App installation token. The `secrets=` directive clause only *exports an already-existing* env var
    into the sweeper's `env -i` sandbox; it provisions nothing. So the probe would have failed on line
    one, and it would have failed **silently**: a failing probe posts a `FAIL` comment, applies no
    label, reaches no digest query, and is then auto-closed `not planned` at 30 business days by
    `cron-follow-through-monitor.ts` Guard C — after which the sweeper's `stateReason != COMPLETED`
    filter drops it permanently. Provisioning a new App credential is also an operator step, which the
    brief forbids. In-session verification has none of these properties and runs sooner.
6.4 **Assert the drain inline as well**, from the regenerated lockfiles: no vulnerable copy of any
    cleared package remains. This is deterministic, available at merge time, and independent of
    Dependabot's rescan — the alert count is a lagging mirror of this same fact.
6.5 File the follow-up issues. Each carries **both** `action-required` **and** `decision-challenge`,
    matching the only working pattern in the repo (`ship/SKILL.md:1465`), and names a concrete
    milestone.
6.6 **Operator surface.** The digest reads merged-PR **titles and labels** and `action-required`
    **issue titles** — it never fetches a PR body. Every operator-facing promise must route through
    one of those two or be struck. Concretely: write the PR *title* as the plain-language consequence,
    and put the business-consequence sentence in the *title* of the `action-required` follow-up issue.

## Files to Create

| Path | Purpose |
|---|---|
| `scripts/lint-dual-lockfile.sh` + `.test.sh` | Guard 1. Scans tracked files. |
| `scripts/lint-workflow-install-sites.sh` + `.test.sh` | Guard 2. Scans workflow YAML. Split from Guard 1 so each floor matches its own enumeration. |
| `.npmrc` in root, `apps/web-platform`, `plugins/soleur/skills/pencil-setup/scripts`, `spike` | `min-release-age=3`. Four files because npm does not traverse to a parent `.npmrc` (measured). |
| `knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md` | The decision. Ordinal provisional. |
| `apps/web-platform/test/next-config-images-absent.test.ts` | CPO condition 3 control. No existing test reads `next.config.ts`, so a new file is warranted. |
| `scripts/close-superseded-dependabot-prs.sh` | Idempotent, resumable Phase 4 sweep with pre-close subsumption re-verification. |

## Files to Edit

Derived from a **repo-wide** `git grep`, not from the issue body and not from a
`.github/workflows/`-scoped search. **Twenty live install sites**: sixteen converting from bun, four
pre-existing bare `npm ci`. Two of the sixteen sit outside `.github/workflows/` entirely.

**Web-platform bun sites (10, across 9 workflows):** `ci.yml:649` (`test-webplat`), `ci.yml:906`
(`e2e`), `cla-evidence.yml:89`, `constraint-gates.yml:62`, `fix-constraints-stage-a.yml:78`
(already `--ignore-scripts`), `main-health-monitor.yml:203`, `rls-authz-fuzz.yml:110`,
`tenant-integration.yml:164`, `validate-vector-config.yml:62`, `web-platform-release.yml:971`.

**Root bun sites (4):** `ci.yml:695` (`test-bun`), `ci.yml:903` (`e2e` root install),
`main-health-monitor.yml:200`, `scheduled-terraform-drift.yml:1326`.

**Bun sites outside `.github/workflows/` (2) — the ones a workflows-scoped grep cannot see:**
`plugins/soleur/scripts/grok-fidelity-gate.sh:28` (root install, feeds the **required**
`grok-fidelity` check) and `apps/web-platform/.github/workflows/constraint-gates.yml:54` (nested
workflow, byte-parity-diffed against two siblings).

**Pre-existing bare `npm ci` sites (4):** `ci.yml:587` (`web-platform-build`), `ci.yml:954`
(`critical-css-gate`), `deploy-docs.yml:67`, `scheduled-realtime-probe.yml:50` (`--prefix` form).

| Path | Change |
|---|---|
| `apps/web-platform/bun.lock`, `bun.lock` | **Deleted** (after Phase 2.6 retires their readers). |
| `apps/web-platform/bunfig.toml`, `bunfig.toml` | Drop `[install]`; keep `[test]` byte-for-byte. |
| `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` | Retire Section 1 (`:87`) and `bunlock_version()` (`:78`). |
| `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh` | Drop the parity fixtures. |
| `.github/workflows/ci.yml` (`lockfile-sync`) | Cover root's lockfile; invoke both guards; update error text. |
| `scripts/test-all.sh` | `run_suite` registration for both new suites. |
| `apps/web-platform/package.json` | `overrides.brace-expansion` → `^5.0.9`; OTel chain bumps. |
| `package.json` (root) | Add `name`; add an `overrides` block for `js-yaml` and `brace-expansion`. |
| `apps/web-platform/package-lock.json`, `package-lock.json` (root), `plugins/soleur/skills/pencil-setup/scripts/package-lock.json` | Regenerated under `npm@11`; root `name` repaired. |
| `apps/web-platform/lib/pwa/sw-update.ts`, `components/pwa/pwa-controls.tsx` | Update-accept telemetry. |
| `apps/web-platform/test/pwa/sw-update.test.ts` | Telemetry coverage folded in — the harness already exists here. |
| `apps/web-platform/test/pwa/sw-source.test.ts` | Handler-scope regression assertion. |
| `plugins/soleur/test/plan-skeleton-checkpoint.test.ts`, `workflow-fidelity.test.ts` | Remove the `bash -c` inline-script sink. |
| `knowledge-base/engineering/architecture/decisions/ADR-079-*.md` | Amend: parity arm retired. |
| `plugins/soleur/skills/preflight/SKILL.md` | Check 3 reflects the single-lockfile invariant. |
| `plugins/soleur/skills/work/references/work-lockfile-bumps.md` | Bun procedure no longer applies here. |
| `.github/workflows/validate-vector-config.yml` | Its comment at `:59` claims *"bun install is fast (~5s) against bun.lock"* — false once converted. |
| `plugins/soleur/scripts/grok-fidelity-gate.sh` | Root install site feeding a required check. |
| `apps/web-platform/.github/workflows/constraint-gates.yml` | Nested workflow install site. |
| `plugins/soleur/skills/constraint-scaffold/references/constraint-gates-workflow.template` | Third member of the byte-parity triad; must move in the same commit. |
| `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template` | Tenant-facing; decision recorded per Phase 2.1c. |
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Root branch needs the lockfile detection its per-app branch already has. |
| `apps/web-platform/.dockerignore` | Add `.npmrc`. |
| `plugins/soleur/skills/drain-prs/SKILL.md`, `model-launch-review/SKILL.md`, `work/SKILL.md`, `plan/SKILL.md` | Prose that would instruct the next agent to recreate `bun.lock`. |
| `knowledge-base/project/constitution.md`, `knowledge-base/engineering/architecture/nfr-register.md` | Name bun-side supply-chain controls that no longer exist. |
| `knowledge-base/engineering/architecture/decisions/ADR-058-*.md`, `ADR-074-*.md`, `ADR-137-*.md` | Amendments per the ADR table. |
| `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` | Comment repeating ADR-058's now-false both-lockfiles claim. |

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-191 — "npm is the single lockfile of record; bun is runtime and test-runner only."**
Ordinal **provisional**: measured 2026-08-16 across all 67 `origin/*` refs, `main` is at ADR-186 and
187–190 are claimed on unmerged branches. Re-derive immediately before merge; on renumber, sweep the
plan, the ACs, and the ADR body in one edit.

**The ADR's core decision is the boundary claim — "install tool and test runner are independent
concerns" — and the lockfile rule is its consequence.** An earlier draft framed it the other way
round, which buried the durable part.

**The rule must be artifact-relative and strictly ordered.** "The authoritative lockfile is the one
the production artifact installs from **and** that Dependabot security-scans" is a conjunction with
no tie-break, and it fails four stress tests: the repo root has *no* production artifact, so the
first conjunct is undefined at the very directory this plan spends its scope argument on;
`plugins/soleur/skills/pencil-setup/scripts/` has a *different* production (it ships to customers'
self-hosted CLIs), so "the production artifact" silently means "the web-platform image"; the
conjuncts can contradict if anything ever ships from a bun runtime; and the second conjunct is a
**vendor-roadmap fact**, not an architectural property — the plan's own citation calls bun security
updates "future work", so the discriminator evaporates when GitHub ships them while the conclusion
should still hold. State it instead as:

> A directory has **exactly one** lockfile of record. It is the lockfile that the artifact leaving
> this repository *from that directory* installs from. Where no artifact leaves the repository from
> that directory, it is the lockfile the repository's security scanner reads. Two lockfiles in one
> directory is a defect independent of which one wins.

That decides root, `spike/`, and `pencil-setup/scripts/` unambiguously and survives Dependabot
gaining bun support. Add an explicit re-evaluation trigger: *if GitHub ships bun security updates,
re-derive — the conclusion likely stands on the artifact clause alone.*

**Record the asymmetric `--ignore-scripts` posture in the ADR, not only in the guard contract.**
Guard 2 clause 2 encodes the *what*; only the ADR can carry the *why*, and the why is
counter-intuitive enough that the next reviewer will otherwise "harmonize" the flag: behavior
preservation is relative *to bun*, and `web-platform-build` is the **only** CI job that exercises
production install semantics at all (no PR-time job builds the Dockerfile; those are post-merge).
Also record: CI resolves the same *versions* production installs but deliberately does not execute
install scripts, while the production `Dockerfile` does; the per-directory `.npmrc` floor and root's
conditional exemption (Phase 0.2b); and the tenant-template decision from Phase 2.1c.

Consider an accompanying row in
`knowledge-base/engineering/architecture/principles-register.md` — it currently has no principle
covering lockfile, supply-chain, or dependency-acquisition posture.

**Amend ADR-079.** Its bun.lock↔package-lock parity contract for the two `@anthropic-ai` SDK packages
loses its precondition. Record as a supersession — the failure mode the parity arm guarded no longer
exists — not a weakening. The `sdk-bump-verified:` ack arm is unaffected and stays blocking, and per
Phase 2.6 the section's **presence** arm is retained (renamed PARITY → PRESENCE), because Section 2
short-circuits to green on an empty resolved version and that arm is its only catch.

**Four more ADRs are touched and were missed by an earlier draft:**

| ADR | Anchor | Action |
|---|---|---|
| **ADR-058** | *"the newest stable release clearing the repo's bun `minimum-release-age` supply-chain floor (3 days) so both lockfiles resolve it"* | Amend — both halves become false. The drift guard itself is safe (`playwright-mcp-version-pin.test.ts` reads `package-lock.json` only); the prose is not. Also update the source comment in `server/inngest/functions/cron-ux-audit.ts`. |
| **ADR-074** | Decision names the installer directly: *"Runs `bun install --frozen-lockfile --ignore-scripts` … in the PR context with no write token"* | Amend. The invariant (write token never co-locates with untrusted execution) survives; the literal text does not. |
| **ADR-137** | *"Zero new dependency keeps `bunfig.toml` `minimumReleaseAge` and the supply-chain surface untouched"* | Amend — the rationale goes stale once `[install]` is removed. |
| **ADR-050**, **ADR-032** | ADR-050 independently established *"`package-lock.json` is what prod `npm ci` requires"*; ADR-032 makes `lockfile-sync` a Tier-2 required check | **Cite as reinforcing**, do not amend. ADR-032 is why widening `lockfile-sync` is a change to a branch-protection-required gate. |

Note also that **ADR-033 invariant I4 is factually stale** (it describes a postinstall that "downloads
the platform-native binary" and a `createRequire(...).resolve(...)` resolution path; neither matches
claude-code 2.1.219 nor the real `resolveClaudeBin()`). Not this plan's job to fix, but this plan's
`--ignore-scripts` reasoning rests on I4's mechanism, so cite the correction rather than inheriting it.

### C4 views

**No C4 impact.** Cited against a full read of all three model files (`model.c4` 691 lines,
`views.c4`, `spec.c4`), not a keyword grep:

- **External human actors — all four enumerated:** `founder`, `emailSender`, `betaContact`,
  `contributor`. No bot or Dependabot actor exists; `contributor` is explicitly a human PR author.
- **External systems — all 21 enumerated.** `github` is one node described as *"Source control,
  CI/CD, issue tracking, and releases"*, already covering the CI surface touched here. The npm
  registry, Bun, Dependabot, and CodeQL are **not modeled**: the model represents the *outbound*
  supply chain (build → sign → publish → hosts pull, via `ghcr`, `zotRegistry`, `projectZot`,
  `sigstore`) and not the *inbound* dependency-acquisition half this change lives in.
- **Containers / data stores:** no CI, job, workflow, build-pipeline, or web-platform-image element
  exists at any level; the image appears only as payload text inside edge descriptions.
- **Access relationships:** `contributor → github`, `engine → github` ("Git operations and CI"),
  `constraintscaffold → webapp`, and the release edges are all written tool-agnostically; none is
  keyed to an install tool.
- **Description correctness:** `grep -iowE` (word-bounded) over all 691 lines of `model.c4` returns
  **zero** hits for `bun|npm|yarn|pnpm|lockfile|package-lock|dependabot|codeql|node_modules`. The
  unbounded `grep -io` form returns 6, all `bun` inside `bundle` (lines 563, 568, 569, 573, 574,
  577) — recorded because a conclusion must cite the command actually run, not a tighter one.

Two adjacent claims hold and are re-verified at implementation time: `publicResolvers` asserts the
Dockerfile installs only `ca-certificates, git, bubblewrap, socat, qpdf, jq` (an apt list; the
Dockerfile installs and invokes no bun — `grep -ciowE 'bun' apps/web-platform/Dockerfile` returns
**0**, while the unbounded `grep -ci 'bun'` returns 6, every one of them the substring inside
`bundle`/`bundled`. The word-bounded form is the command the claim cites, for the same reason it is
cited for `model.c4`), and `zotRegistry`/`projectZot` assert *"no bot manages that pin"*
(Renovate- and zot-scoped; this plan creates no `dependabot.yml`). Run
`apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` regardless.

## Guard Contract

### Guard 1 — single lockfile of record (`scripts/lint-dual-lockfile.sh`)

**Property.** No tracked `bun.lock` exists anywhere in the repository, and neither `bunfig.toml`
declares an `[install]` section.

Deliberately **stronger than "no directory carries both"**, because the erosion path is concrete:
bun remains installed as the test runner, so a developer's habitual `bun install` silently recreates
`bun.lock` and a routine commit resurrects the split this plan exists to remove — after which
Dependabot bumps fail with the same opaque frozen-lockfile error again. The existence form also
removes the ambiguity about a bun-only directory, which a co-location property leaves undecided. The
paired `[install]` assertion closes the other half: a reintroduced `minimumReleaseAge` signals that
`bun install` is a supported path again.

**Assembly.** The chokepoint is the tracked-file set enumerated at run time from `git ls-files` —
never a hardcoded directory list. The guard asserts zero matches for `bun.lock`, zero `[install]`
sections across all tracked `bunfig.toml`, and independently enumerates `package-lock.json`
directories to anchor its floor.

**Anti-vacuity floors on the `package-lock.json` enumeration (≥4 — verified 2026-08-16: root,
`apps/web-platform`, `plugins/soleur/skills/pencil-setup/scripts`, `spike`), never on the `bun.lock`
enumeration.** After this change the latter is legitimately empty, so a floor there would be
unsatisfiable — and a guard whose success condition is "I found zero of the thing I search for" is
indistinguishable from a guard whose search is broken. The floor must sit on a set that is non-empty
in the passing state.

**Mutation matrix.** Each row must drive the guard RED.

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Restore `apps/web-platform/bun.lock` | The core regression. **RED on today's tree — the pre-fix failing test.** |
| 2 | Restore root `bun.lock` | Root-specific pre-fix evidence; root conversion is the contested scope decision. |
| 3 | Break the guard's dispatch so the `package-lock.json` enumeration is empty | Anti-vacuity. Must fail against the floor and print the scanned count, never report "0 violations" and exit 0. |
| 4 | Add a **third** `bun.lock` (`spike/bun.lock`) while both known directories stay clean | Whole-set quantification. A check that passes because member one is clean is an instance of the class this guard exists to catch. |
| 5 | Add a `bun.lock` in a directory with **no** `package-lock.json` | RED — the shape a stray `bun install` in a new directory produces. Under the existence property this verdict is unambiguous. |
| 6 | Reintroduce `[install]` with `minimumReleaseAge` into either `bunfig.toml` | RED. The precondition for the whole defect returning. |
| 7 | Lower the floor constant below the real `package-lock.json` directory count | The floor must be asserted, not decorative. |
| 8 | Remove an `@anthropic-ai` SDK package from `apps/web-platform/package-lock.json` | The retained `sdk-bump-sandbox-gate.sh` PRESENCE arm (`[[ -z "$pv" ]]`) must drive RED. Without this row, retiring the bun half could silently take the empty-`head_v` catch with it and reopen the #5849 silent-green class. |

**Harness rows** — these target the suite, not the guard.

| # | Input | Expected |
|---|---|---|
| H1 | Delete or neuter an assertion inside `lint-dual-lockfile.test.sh` | Suite RED, via an asserted floor on its own executed-assertion count. |
| H2 | **Must-PASS:** `plugins/soleur/skills/pencil-setup/scripts/` (npm-only, never dual) | PASS. Without a must-PASS row, a guard that rejects everything scores full marks on every RED row. |
| H3 | **Must-PASS:** the post-fix tree, where zero `bun.lock` files exist | PASS **and** report a non-zero scanned-directory count, proving the clean state is distinguishable from a broken enumeration. |

### Guard 2 — workflow install sites (`scripts/lint-workflow-install-sites.sh`)

**Property.** Three clauses, deliberately separated because they have different scopes:

1. **Universal:** no workflow step installs a directory carrying a `package-lock.json` by running
   `bun install`.
2. **Universal:** every workflow install step over a `package-lock.json` directory runs
   `npm ci --ignore-scripts`. All eighteen sites carry the flag after Phase 2.2 — the four
   pre-existing bare `npm ci` sites are converted too, because `web-platform-build` already executes
   ten install-script packages on fork-PR code today.
3. **Universal:** any workflow step invoking `bun ` is preceded by a `setup-bun` step in the same
   job. Phase 2.5 removes `setup-bun` from jobs that no longer install with bun, by hand, across
   eight workflows including the required `test` and `e2e` checks; this clause is what makes that
   safe rather than a judgment call.

**Assembly.** Enumerated at run time from `git ls-files`, spanning **three location classes**, not
one glob:

1. every `*.yml` under **any** `.github/workflows/` path — repo-root *and* nested, because
   `apps/web-platform/.github/workflows/constraint-gates.yml:54` is a live install site that a
   repo-root glob provably misses;
2. `scripts/**/*.sh` and `plugins/**/*.sh` — because
   `plugins/soleur/scripts/grok-fidelity-gate.sh:28` is a live install site feeding the **required**
   `grok-fidelity` check;
3. `plugins/soleur/skills/constraint-scaffold/references/*.template` — the emitted-workflow templates
   that `parity.test.sh` byte-diffs against class 1.

A `.github/workflows/*.yml`-only assembly was the guard's original shape and it would have reported
**GREEN with two live `bun install` sites remaining** — precisely the false-green it exists to
prevent. The scan classifies by **`run:` command**, not raw string (`git grep -n 'bun install'` over
the workflow directory returns 22 lines of which only 14 are invocations), and handles all five
syntactic forms; the `npm ci --prefix <dir>` form at `scheduled-realtime-probe.yml:50` is the one an
extractor keyed only on `working-directory:` silently misses.

**Boundary, stated explicitly and asserted:** composite actions under `.github/actions/**` and the
production `Dockerfile` are out of scope — the Dockerfile deliberately runs `npm ci` *without*
`--ignore-scripts`, and clause 2 must not be read as governing it.

**Two anti-vacuity floors, because the file enumeration and the step extraction fail independently:**
≥40 workflow files (mirroring the actionlint hang guard, against 74 today) **and** ≥20 matched install
steps (16 converting bun sites + 4 pre-existing npm sites). Without the second, a broken step-matching
regex scans 74 files, matches nothing, and exits 0 green — the file-count floor cannot see it.

**Mutation matrix.**

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Reintroduce `bun install` for a `package-lock.json` directory | The regression. **RED on today's tree at sixteen sites.** |
| 2 | Add a **second** offending site after the first is compliant | Whole-set quantification. |
| 3 | Drop `--ignore-scripts` from any of the twenty sites | Load-bearing for the untrusted-PR posture, not cosmetic. |
| 4 | Match on the raw string `bun install` instead of on `run:` commands | RED against a correct post-conversion tree (22 raw matches, 14 invocations). A false-RED guard gets disabled, so this protects the guard's own credibility. |
| 5 | Rewrite a site into the `npm ci --prefix <dir>` form | Must still be seen. An extractor keyed only on `working-directory:` misses it — and one such site exists today. |
| 6 | Remove `setup-bun` from a job that still runs `bun test` | Clause 3. This is the hand-edit Phase 2.5 makes across eight workflows. |
| 7 | Break the step-matching regex so zero install steps are matched | The ≥18 step floor fails, rather than the file-count floor passing over an empty match set. |
| 8 | Point the workflow glob at a directory that matches nothing | The ≥40 file floor fails. |
| 9 | Reintroduce `bun install` in `apps/web-platform/.github/workflows/` or in a `plugins/**/*.sh` script | RED. A repo-root-workflows-only assembly misses both, and both feed required checks — this row is the one that would have caught the guard's original scope defect. |

**Harness rows.**

| # | Input | Expected |
|---|---|---|
| H1 | Neuter an assertion in `lint-workflow-install-sites.test.sh` | Suite RED via its executed-assertion floor. |
| H2 | **Must-PASS:** a workflow with no install step at all | PASS — the guard must not require every workflow to install something. |
| H3 | **Must-PASS:** the production `Dockerfile`'s bare `npm ci` | PASS / out of scope, proving the stated boundary is implemented rather than merely described. |

## Observability

```yaml
liveness_signal:
  what: the `lockfile-sync` required check, which now also runs both guards
  cadence: every pull request and every push to main
  alert_target: GitHub required-check failure, blocking merge
  configured_in: .github/workflows/ci.yml (job `lockfile-sync`)
error_reporting:
  destination: GitHub Actions annotations (`::error::`) plus non-zero exit; Sentry for the PWA update path
  fail_loud: true — both guards print their scanned-set counts on success, so a vacuous run is
    distinguishable from a clean one
failure_modes:
  - mode: a bun lockfile or a bunfig [install] section reappears
    detection: Guard 1, whole-tree scan with a floor on the package-lock enumeration
    alert_route: lockfile-sync required check fails, naming the file and the remedy
  - mode: an install site regresses to `bun install`, drops `--ignore-scripts`, or moves to a
      syntactic form the extractor cannot see
    detection: Guard 2 clauses 1-2, with both a file-count and a matched-step floor
    alert_route: lockfile-sync required check fails, naming the file and job
  - mode: `setup-bun` removed from a job that still runs bun
    detection: Guard 2 clause 3
    alert_route: lockfile-sync required check fails
  - mode: either guard scans nothing (broken glob, broken regex, empty enumeration)
    detection: the three anti-vacuity floors (package-lock dirs >= 4, workflow files >= 40,
      matched install steps >= 18)
    alert_route: guard exits non-zero rather than reporting zero violations
  - mode: a user accepts a PWA update and the worker never activates
    detection: a Reload click producing no `controllerchange` within a bounded interval
    alert_route: Sentry event from apps/web-platform/lib/pwa/sw-update.ts, with a Sentry alert rule
      created in the same PR — an event nobody is paged on is a log
  - mode: the service-worker message handler gains a capability beyond skipWaiting, invalidating the
      alert-203 dismissal
    detection: apps/web-platform/test/pwa/sw-source.test.ts handler-scope assertion.
      KNOWN-WEAK, stated here so the caveat travels with the claim: this suite asserts the handler's
      SOURCE TEXT and never executes it, so a behavioral change can pass it green. It is a proxy for
      a behavioral invariant and it is the compensating control for a CodeQL dismissal. Closing it
      properly needs an e2e that installs a v2 worker and verifies the reload
    alert_route: vitest failure in the `test` required check
  - mode: any `images` config (remotePatterns, domains, or a custom loader) is introduced, arming the
      deferred sharp advisory
    detection: apps/web-platform/test/next-config-images-absent.test.ts
    alert_route: vitest failure in the `test` required check, whose message names advisory 144, the
      nested-sharp reachability argument, and the follow-up issue to reopen the decision on.
      KNOWN-INCOMPLETE: the invariant is "no attacker-controlled bytes reach the next-nested sharp
      decoder", and the config key is a proxy for it. Next serves same-origin relative `src` values
      through /_next/image with NO images config at all, so a proxy route reaches the decoder while
      this stays green. Paired second assertion: `app/(public)/invite/[token]/page.tsx` remains the
      SOLE `next/image` call site — a cheap, checkable stand-in for the real invariant
  - mode: the supply-chain release-age floor silently evaporates — an `.npmrc` deleted, or
      `lockfile-sync`'s `npm install -g npm@11` pin regressing (npm 10.x ignores the key entirely)
    detection: a step in `lockfile-sync` asserting `npm --version` starts with `11` AND
      `npm config get min-release-age` returns `3` in each floored directory
    alert_route: lockfile-sync required check fails. This asserts the invariant itself rather than a
      proxy for it — P3 previously had no failure-mode row at all, and AC7 checks the file's content
      only once, at merge
  - mode: a cleared package remains vulnerable after the drain
    detection: Phase 6.4's inline lockfile assertion, plus Phase 6.3's in-session alert re-query
    alert_route: pre-merge failure (inline) and an itemized in-session report (API)
logs:
  where: GitHub Actions run logs for `lockfile-sync`; Sentry
  retention: GitHub Actions default retention; Sentry project retention
discoverability_test:
  command: bash scripts/lint-dual-lockfile.sh && bash scripts/lint-workflow-install-sites.sh
  expected_output: >-
    "lint-dual-lockfile: OK — N package-lock directories scanned (N >= 4), 0 tracked bun.lock,
    0 bunfig [install] sections" then "lint-workflow-install-sites: OK — W workflow files scanned
    (W >= 40), M install steps matched (M >= 18), 0 violations". Counts are asserted as floors, never
    as literals, so a fifth package-lock directory does not stale the probe.
```

Both probes' first token is `bash` and both targets are repo-relative scripts committed in this PR,
satisfying the preflight Check 10 execution boundary. No credentials are required and neither command
contains `ssh`.

**No scheduled follow-through probe is enrolled**, and the reason is recorded in Phase 6.3 so it is
not reintroduced: the sweeper cannot authenticate against the Dependabot alerts API, and a failing
probe there self-erases after 30 business days without ever reaching a human.

## Acceptance Criteria

Numbering is left stable across plan-review revisions so review references stay valid; several
criteria cut at review are simply absent rather than renumbered.

### Pre-merge (PR)

- **AC2** Guard invocation, not a hand-enumerated path list: both guards exit 0 and report scanned-set
  counts meeting all three floors.
- **AC3** Both guards are RED on the pre-fix tree, evidenced by the Phase 1.2/1.3 captured output.
- **AC4** Every mutation-matrix row (Guard 1 rows 1–7, Guard 2 rows 1–8) drives its guard RED, and
  every harness row (Guard 1 H1–H3, Guard 2 H1–H3) behaves as specified. Verified by the two
  `.test.sh` suites, each printing an executed-assertion count.
- **AC7** All four `.npmrc` files contain `min-release-age=3`; neither `bunfig.toml` contains an
  `[install]` section; both `[test]` blocks are byte-identical to their pre-change content.
- **AC7b** The Phase 2.0 graph-switch proof ran and its scratch branch reached a **green full
  required-check matrix** with install sites converted and lockfiles, `bunfig`, `.npmrc`, and package
  versions all untouched. The run URL is recorded in the PR body.
- **AC7c** **The acceptance bar is verified end to end.** A synthetic Dependabot-shaped branch — a
  transitive-only `package-lock.json` edit, authored by npm as Dependabot would author it rather than
  regenerated locally — opens a draft PR and reaches a green **full required-check set**, with the
  result recorded. This is the plan's decisive claim and the only step that tests it. It specifically
  exercises the open question that a local no-op measurement cannot: whether a Dependabot-authored
  lockfile byte-survives regeneration by the `npm@11` pinned in `lockfile-sync`, which after Phase
  2.10 sits directly on the Dependabot path.
- **AC8** No new required check: the three declaring files (`scripts/required-checks.txt`,
  `infra/github/ruleset-ci-required.tf`,
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`) are unmodified, and
  `.github/actions/bot-pr-with-synthetic-checks/action.yml` still derives `CHECK_NAMES` from
  `required-checks.txt`.
- **AC9** The eight workflows lacking a Node pin now set `actions/setup-node` with `node-version: 22`,
  `cache: npm`, and `cache-dependency-path`; `e2e` retains its container Node 24, and `test-scripts`
  retains `setup-bun`. Enforced by Guard 2's assembly rather than by eyeball.
- **AC9b** All three members of the constraint-gates byte-parity triad moved in the same commit, and
  `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` passes.
- **AC9c** `sdk-bump-sandbox-gate.sh` retains its `[[ -z "$pv" ]]` presence arm; Guard 1 mutation row 8
  proves an SDK package absent from `package-lock.json` still drives the gate RED.
- **AC9d** Phase 0.2b's global-exact-pin measurement is recorded, and root's `.npmrc` exists only if
  that measurement passed. If it did not, root's exemption and its reason are recorded in ADR-191.
- **AC10** All four `actions/cache` blocks are deleted and no cache block caches `node_modules`.
- **AC12** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and `bash scripts/test-all.sh`
  both pass **against a `node_modules` produced by a clean `npm ci --ignore-scripts`** — not against a
  locally-populated tree, which would pass while CI breaks.
- **AC13** No bumped package landed on a major past its target (`undici` 7.x, `@hono/node-server` 1.x,
  `js-yaml` 3.15.1 and 4.3.1, `nanoid` 3.3.x), **and** no vulnerable copy of any package marked
  *cleared* in the Phase 3 reconciliation table remains in any regenerated lockfile. Asserted per
  package, itemized against that table.
- **AC13b** In the regenerated `apps/web-platform/package-lock.json`, `node_modules/sharp` still
  records `dev: false` and `optional: false`, and `dependencies.sharp` in `package.json` is still an
  explicit entry — not inherited from `next`'s `optionalDependencies`. This is the direct
  post-mortem regression check: a Dependabot `sharp` bump previously re-resolved the top-level copy as
  dev-only, `npm ci --omit=dev` at `Dockerfile:158` then installed none, and production deploys were
  skipped for 3h+. `tsc` and the vitest suite are both blind to it, and so is `docker build` in the
  deps stage — only the `--omit=dev` runner stage reveals it.
- **AC14** No **executable** file added or modified by this PR (`.sh`, `.yml`, `.ts`, `.mjs`) contains
  `bun update`. Scoped to executables because this plan file and ADR-191 legitimately quote the banned
  command as their own prohibition — an unscoped grep would be unsatisfiable by construction.
- **AC15** ADR-079 carries the parity-arm amendment, and ADR-191 states the decision rule as an
  ordered test that decides the root case as well as the web-platform case. (The ordinal itself is
  already enforced by the `adr-ordinals` required check.)
- **AC16** Root `package.json` declares a `name` and an `overrides` block reaching the nested
  `js-yaml` 3.x and `brace-expansion` 1.x copies; root `package-lock.json`'s `name` matches.
- **AC17** The `next.config.ts` no-`images`-key assertion exists and passes, and its failure message
  names advisory 144, the nested-sharp reachability argument, and the follow-up issue. Recorded as the
  audit contract for a deliberately-deferred high-severity advisory, not as a gate.
- **AC18** The service-worker handler-scope assertion exists and passes.
- **AC19** The PWA update-accept path reports to Sentry when a Reload click produces no
  `controllerchange` within the bounded interval, a Sentry alert rule exists for that event, and
  coverage is folded into the existing `sw-update.test.ts`.
- **AC20** The PR **title** states the plain-language consequence (the digest reads titles, never
  bodies). The PR body carries: the written option rationale; the explicit decision not to create
  `.github/dependabot.yml`, with its reason; the four alerts left open with reachability evidence,
  true severities (3 high + 1 medium), and the recorded same-origin-proxy residual; and the alert-203
  dismissal justification.

### Post-merge (automated, no human step)

- **AC21** Phase 6.3's in-session re-query reports the actual open alert set, itemized by alert ID,
  against Phase 0.7's derived expectation of 4 (161, 162, 170, 144). A mismatch is reported as a
  finding with the delta named — never rounded to "as expected".
- **AC22** All nine Dependabot PRs (7503, 7368, 7367, 7294, 7292, 7245, 7239, 7238, 7237) are
  `CLOSED`, each either carrying our supersede comment **or** self-closed by Dependabot after the
  delivered version satisfied it. The sweep is idempotent and resumable, and re-verified subsumption
  immediately before each close.
- **AC23** CodeQL alerts 214 and 213 read `fixed` or `dismissed`; alert 203 reads `dismissed` with a
  space-separated `dismissed_reason`, and a tracking issue exists carrying the reason in a comment
  with the `keep-open` marker applied **before** the dismissal. (Alert 203 is medium, so
  `codeql-to-issues.yml` will not have filed one — it is created explicitly.)
- **AC24** Each converted scheduled workflow has been dispatched once (`gh workflow run`) and
  succeeded.
- **AC25** Follow-up issues exist, each carrying **both** `action-required` and `decision-challenge`
  and naming a concrete milestone: (a) the `next` 15.x → 16.x major that would clear the four residual
  alerts, linking **#1327** (`next lint` → ESLint CLI) as an explicit blocker and recording the
  same-origin-proxy residual; (b) whether to create `.github/dependabot.yml`. Both labels are
  required: `action-required` alone is escalate-only and never auto-closed, while
  `decision-challenge` alone is invisible to the digest's query *and* on a 30-day auto-close timer.
- **AC26** Converted-job timings are re-measured and reported against the +5-minute budget.

## Test Scenarios

| # | Scenario | Expectation |
|---|---|---|
| T1 | Restore `apps/web-platform/bun.lock` | Guard 1 RED |
| T2 | Restore root `bun.lock` | Guard 1 RED |
| T3 | Empty Guard 1's package-lock enumeration | RED via the floor, not exit 0 |
| T4 | Add `spike/bun.lock` while both known directories are clean | RED — whole-set quantification |
| T5 | Add a `bun.lock` in a directory with no `package-lock.json` | RED |
| T6 | Reintroduce `[install]` into either `bunfig.toml` | RED |
| T7 | npm-only directory (`pencil-setup/scripts`) | PASS |
| T8 | Post-fix tree, zero `bun.lock` | PASS **with** a non-zero scanned count |
| T9 | Reintroduce `bun install` at any of the eighteen sites | Guard 2 RED |
| T10 | Drop `--ignore-scripts` from any site | Guard 2 RED |
| T11 | Rewrite a site to `npm ci --prefix <dir>` | Still seen by Guard 2 |
| T12 | Remove `setup-bun` from a job still running `bun test` | Guard 2 clause 3 RED |
| T13 | Break the step-matching regex | Matched-step floor RED |
| T14 | The production `Dockerfile`'s bare `npm ci` | PASS / out of scope |
| T15 | Simulated Dependabot bump through the converted install path | `npm ci --ignore-scripts` exits 0 |
| T16 | Same bump against the **pre-fix** path with a stale `bun.lock` | `bun install --frozen-lockfile` exits non-zero with "lockfile had changes, but lockfile is frozen" — documents the defect |
| T17 | A **Dependabot-authored** lockfile regenerated by `lockfile-sync`'s `npm@11` | Byte-identical, so the gate stays green on the Dependabot path |
| T18 | `npm ci --ignore-scripts` then `next build` in `web-platform-build` | Exits 0, or the required `npm rebuild <pkg>` set is enumerated |
| T19 | `npm ci --ignore-scripts` in the Playwright container | Exits 0; `npx playwright test` resolves the pinned 1.58.2 binary; browsers are not re-downloaded |
| T20 | `npm ci --ignore-scripts` over untrusted PR-head code | None of the ten install-script packages executes |
| T21 | Production image build after the bumps | `docker build` succeeds; `sharp` native binaries resolve |
| T21b | `npm ci --omit=dev` against the regenerated lockfile, then resolve `sharp` | Resolves. Mirrors `Dockerfile:158` — the runner stage is the only place the dev-only mis-resolution surfaces |
| T22 | `next.config.ts` gains `images.remotePatterns` | Assertion RED |
| T23 | `next.config.ts` gains `images.domains` or a custom `images.loader` | Assertion RED — the widened form has no hole a narrow check would leave |
| T24 | The service-worker `message` handler gains an effect beyond `skipWaiting` | Assertion RED |
| T25 | Reload click produces no `controllerchange` within the interval | A Sentry event is emitted and the alert rule fires |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The dependency graph silently changes under every test shard.** A green `main` is evidence about the *bun* graph; the two are measurably divergent, so it is zero evidence the suite passes on `package-lock.json`'s pins. Folding conversion, deletion, and eleven bumps together makes any red shard un-bisectable across three causes, and an un-attributable failure most likely ends in reverting the architecture decision. | Phase 2.0's scratch-branch graph-switch proof is a blocking precondition (AC7b), with a recorded two-PR fallback if it goes red. |
| **The plan's decisive claim is the one thing easiest to leave untested.** T15 tests one command in one job, not the acceptance bar. | AC7c opens a synthetic Dependabot-shaped draft PR and records the full required-check result set. |
| **`lockfile-sync` becomes the new failure point on the Dependabot path.** The no-op measurement was taken against a *locally regenerated* lock — the one case guaranteed to round-trip. A Dependabot-authored lockfile is written by Dependabot's npm, not the pinned `npm@11`. | T17 and AC7c exercise exactly this. |
| **A live fork-PR execution path, mis-framed as hypothetical.** `web-platform-build` runs bare `npm ci` on `pull_request` over fork-controlled `package.json`, so all ten install-script packages already execute on untrusted code. | Phase 2.2 converts the four pre-existing npm sites too, and Guard 2 clause 2 quantifies over all eighteen. |
| **`--ignore-scripts` could break `next build`.** It is behavior-preserving relative to bun, but not relative to a site that already ran scripts. | Phase 2.0's scratch matrix is where this is determined; if it breaks, the required `npm rebuild` package set is enumerated rather than the flag dropped (T18). |
| **Deleting `bun.lock` before its readers are retired turns `lockfile-sync` red on its own commit.** | Phase 2.6 retires all readers first — the gate script's PARITY arm and the four `hashFiles` cache keys — with the ordering invariant stated. |
| **Extending `lockfile-sync` to root before repairing root's `name` fails the gate on its own introduction commit.** | Phase 2.9 precedes 2.10. |
| **Root's bumps have no lever.** Root `package.json` declares no `overrides`, and the vulnerable `js-yaml` 3.x and `brace-expansion` 1.x copies are nested. | Phase 3.3 adds one (AC16). |
| **The verification journey cannot work as a scheduled probe.** `GITHUB_TOKEN` cannot read the Dependabot alerts API, no `permissions:` key grants it, `secrets=` provisions nothing, and a failing probe self-erases at 30 business days. | The probe is cut. Verification is in-session (Phase 6.3) plus an inline lockfile assertion (Phase 6.4, AC13) that is deterministic and available at merge. |
| **The operator sees nothing.** The digest reads merged-PR titles/labels and `action-required` issue titles — never PR bodies. An earlier draft put the business consequence in the PR body and labelled follow-ups `decision-challenge` *instead of* `action-required`, which is invisible in both digest blocks and on a 30-day auto-close timer — a mitigation strictly worse than the risk it addressed. | Phase 6.6 and AC20/AC25: consequence in the PR **title**; both labels on every follow-up. |
| **Dependabot self-closes rebased PRs without a comment**, so a criterion demanding our comment on all nine fails on the *success* path. | AC22 accepts either disposition and requires pre-close subsumption re-verification (Phase 4.3). |
| **The sharp deferral's guard watches one door.** A same-origin proxy route reaches the nested decoder with no `images` config at all. | Recorded as an explicit residual in Phase 3.4 and in the follow-up issue, with the WebP re-encoding noted as partial mitigation — not papered over by widening a guard that cannot see it. |
| **Regenerating the lockfile could silently re-classify `sharp` as dev-only.** `next` declares `sharp` as an `optionalDependency` at `^0.34.3` while the repo pins `^0.35.0` in `dependencies`; a previous Dependabot bump across exactly this boundary caused npm to resolve the top-level copy `"dev": true`, after which `npm ci --omit=dev` (`Dockerfile:158`) installed no `sharp` and production deploys were skipped for 3h+. This plan regenerates that lockfile across eleven bumps. | AC13b asserts `dev: false` / `optional: false` and the explicit `dependencies.sharp` entry survive regeneration; T21b runs `npm ci --omit=dev` and resolves `sharp`, mirroring the runner stage where the fault actually appears. The plan does not bump `sharp` itself, so the risk is regeneration side-effect, not version movement. |
| **Retired risk, recorded so it is not reintroduced:** the ported release-age floor was feared to fight `lockfile-sync`'s regenerate-and-diff. | Measured false against npm 11.12.1: `npm ci` does not enforce the floor; the Dockerfile never COPYs `.npmrc`; `--package-lock-only` against a satisfied lock is a no-op. |
| **Retired risk:** the OTel chain bump was framed as touching the request path. | Measured false — OTel is never initialized; inngest's OTel middleware is opt-in and not enabled. Hygiene only. |

## Sharp Edges

- **`bun.lock` is not plain-`jq` parseable** (verified: `jq -e 'type'` fails; 4 trailing commas). This
  plan sidesteps it by deleting both bun lockfiles — that dissolution is a feature of the chosen
  direction, not incidental.
- **npm's release-age flag takes DAYS; bun's takes SECONDS.** Porting `259200` verbatim sets a
  259200-day floor and resolves nothing. The correct value is `3`.
- **npm does not traverse to a parent `.npmrc`** (measured under 11.12.1). A single root file cannot
  cover `apps/web-platform`; each install cwd needs its own.
- **`min-release-age` requires npm 11.** `actions/setup-node@v4.4.0` with Node 22 ships npm 10.9.x,
  which silently ignores the key. This matters only for `npm install` (not `npm ci`) — today just
  `lockfile-sync`, which already pins `npm@11`. That pin is now load-bearing for the supply-chain
  floor as well as for lockfile-shape determinism.
- **`npm ci` deletes `node_modules` unconditionally**, so caching it costs restore time and is then
  discarded. Use `setup-node`'s `cache: npm`, the pattern `web-platform-build` already uses.
- **`--ignore-scripts` is behavior-preserving only relative to bun.** Applied to a site that already
  ran `npm ci`, it is a real behavior change — which is exactly why the four pre-existing sites are
  converted deliberately, with `next build` verified, rather than swept in silently.
- **`npm run -w apps/web-platform <script>` does not work here** — root `package.json` declares no
  `workspaces`. Use `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **`apps/web-platform` test files must match vitest's `include:` globs** (`test/**/*.test.ts` or
  `.test.tsx`); `bunfig.toml` sets `[test] pathIgnorePatterns = ["**"]` so `bun test` finds nothing
  there by design.
- **New bash guard suites must be registered in `scripts/test-all.sh`** with a `run_suite` call; an
  orphan-suite linter fails an unregistered suite.
- **`plan-skeleton-checkpoint.test.ts` requires exactly one `bash` block in `plan/SKILL.md` matching
  both `^branch:` and `awk`** — `extractReaderSnippet` throws on any other count. The CodeQL rewrite
  must preserve the test's execute-don't-match property, which is the entire reason the test exists.
- **`ServiceWorker.postMessage()` has no `targetOrigin` parameter.** Reasoning about this handler as
  if it were `window.postMessage` is the trap that makes CodeQL 203 look actionable. `event.origin` on
  `ExtendableMessageEvent` is also not uniformly populated, so any future origin check must fail
  **open** on the `SKIP_WAITING` path and be verified on real iOS Safari.
- **`sw-source.test.ts` asserts source text, never executes it.** A behavioral change to the service
  worker can pass the whole suite green. Any future work there needs an e2e test that installs a v2
  worker and verifies the reload.
- **`decision-challenge` alone is a self-destruct label.** It is invisible to the digest's query and
  auto-closes after 30 days of non-bot inactivity. Always pair it with `action-required`, which is
  escalate-only and never auto-closed.
- **The operator digest never reads PR bodies.** Anything that must reach the operator goes in a PR
  *title* or an `action-required` issue *title*.
- **Dependabot alerts do not clear at merge**, and the alerts API is not readable by `GITHUB_TOKEN` —
  which is why verification is in-session rather than a scheduled probe.
- **A `sharp` that is not explicitly in `dependencies` is a production outage waiting to happen.**
  `next` holds it as an `optionalDependency` at `^0.34.3`; the repo pins `^0.35.0`. When those
  disagree, npm can resolve the top-level copy dev-only, and the only surface that reveals it is
  `npm ci --omit=dev` in the Docker runner stage — not `tsc`, not vitest, not the deps-stage build.
- **Regenerate `package-lock.json` with `npx --yes npm@11 install --package-lock-only`, never local
  npm.** npm 10 and npm 11 disagree on `"dev": true` flags for optional transitive packages
  (`@img/sharp-*`, `fsevents`), which is the same class of defect as the bullet above and the reason
  `lockfile-sync` pins the major.
- **Do not take `latest` for any bumped package.** Latest is a major past the target for `undici`
  (8.10.0), `@hono/node-server` (2.1.1), `js-yaml` (5.3.0), and `nanoid` (6.0.1). `bun update <pkg>`
  and bare `bun update` remain banned in executable files.

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Verdict *proceed with option 2, with four required corrections*, all folded in. The
"npm is authoritative" rationale was judged sound and **already codified** —
`sdk-bump-sandbox-gate.sh`'s header states *"package-lock is deploy-authoritative … NOT bun.lock which
only feeds CI bun test/typecheck"* — so this plan generalizes to the whole graph what ADR-079
established for two packages. Corrections: (1) `npm ci` would newly execute ten install-script
packages that bun runs zero of, so `--ignore-scripts` is required at every converted site; (2) `npm
ci` deletes `node_modules`, so the cache blocks are dead weight and the timing claim must be stated as
neutral-to-slightly-worse; (3) workflows pinning bun but not Node need `actions/setup-node`; (4) the
proposed allowlist-plus-parity treatment of root **fails RED on day one** against 7 measured drifts,
so root converts in the same PR — which also deletes the need for a `bun.lock` parser entirely. The
release-age concern was tested empirically and retired. Folding the guards into `lockfile-sync` was
explicitly endorsed. Flagged as a missing decision: whether to create `.github/dependabot.yml` — now
recorded as an explicit defer. Sizing: medium (days).

### Product/UX Gate

**Tier:** none | **Decision:** reviewed | **Agents invoked:** cpo | **Skipped specialists:** none |
**Pencil available:** N/A (no UI surface)

No file in `## Files to Create` or `## Files to Edit` matches the UI-surface term list or glob
superset — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` is created, and the
`pwa-controls.tsx` edit adds telemetry to an existing control rather than a new interactive surface.
The mechanical override does not fire. CPO was invoked independently under Phase 2.6 Step 3 because
the declared `single-user incident` threshold requires plan-time product sign-off regardless of tier.

### Product (CPO) — plan-time sign-off

**Status:** reviewed. **Verdict: APPROVE WITH CONDITIONS.** All seven conditions folded in.

Timing judged optimal — no external user is on the hosted PWA today (alpha tester #1 is on the
self-hosted CLI); Phase 4 exit criteria put ten founders on it, so the cost of getting this wrong
today is a founder-dogfood incident rather than a customer one. Risk of acting now LOW, of deferring
past recruitment HIGH. The CI-parity fix was assessed as the strategic prize — larger than the alert
drain, which is hygiene — because the green check is the operator's entire safety net, and a check
that does not test what ships is a false-confidence machine, strictly worse than no check for a solo
founder who must trust the signal.

Conditions and where each landed: (1) dismiss alert 203 rather than implementing the origin check,
with a handler-scope regression assertion → Phase 5.1, AC18, AC23. (2) Add PWA update-accept telemetry
→ Phase 5.2, AC19. (3) Guard the residual-deferral invariant → Phase 1.4, AC17, T22/T23. (4) Record
the correct deferral reason and true severities → Phase 3.4, AC20. (5) Milestone the next-16 follow-up
out of Post-MVP/Later, linking #1327 → AC25. (6) Stage the CI switch → Phase 2.0 and AC24; deviation
recorded, since a full split across PRs is unavailable (`bun install --frozen-lockfile` against a
deleted `bun.lock` fails, so conversion must precede deletion within one PR). (7) Route the
operator-facing outcome → Phase 6.5/6.6, AC20, AC25.

Non-blocking note: the plan overstated OTel risk (dead code, never initialized); that attention is
redirected to conditions 1 and 2. CPO sign-off is one of two required at this threshold;
`user-impact-reviewer` supplies the second at review time.

## Plan Review

Five reviewers plus a scoped strong-model consult ran against the draft. Findings applied rather than
noted, with the highest-value corrections recorded here because each reversed a decision the plan had
already made.

- **Strong-model consult** — today's green CI is evidence about the *bun* graph only, so converting
  install sites silently changes the graph under every shard. Produced Phase 2.0 and AC7b. Also
  established that the commit ordering buys no CI-level safety under squash-merge, and that
  `--ignore-scripts` is not behavior-preserving at sites already running `npm ci`.
- **Kieran (correctness)** — found the P0 the other reviewers missed: `web-platform-build` runs bare
  `npm ci` on `pull_request` over fork-controlled `package.json`, so the install-script execution the
  plan framed as a *new* risk is **live today**. Also: Phase 2.7 must precede the deletion (the gate
  script reads `bun.lock`); 2.9 must precede 2.10; the install-site count was 14 not 15 and the root
  count 4 not 5; `web-platform-build` *does* have `cache: npm` configured, falsifying a
  stated-as-measured claim; eight workflows lack a Node pin, not nine; the required-check list has
  three declaring files, not four; and the C4 "zero hits" claim reproduced only with `grep -iowE`.
- **Simplicity** — measured that npm does not traverse to a parent `.npmrc` (so four files are
  required, not one), that a telemetry test host already exists, and that no test reads
  `next.config.ts`. Cut seven LARP acceptance criteria, folded AC9/AC10 into Guard 2's assembly, and
  established that the `images.remotePatterns` assertion was a proxy narrower than its property.
- **Spec-flow** — walked seven journeys and found six terminating where nothing is listening. Killed
  the scheduled follow-through probe with three independent facts (`GITHUB_TOKEN` cannot read the
  alerts API; no `permissions:` key grants it; a failing probe self-erases at 30 business days).
  Established that the digest never reads PR bodies and that `decision-challenge` alone is both
  invisible and self-closing — making the plan's own operator mitigation worse than the risk. Also
  surfaced that the 39→4 arithmetic was asserted rather than published (now Phase 0.7 and the Phase 3
  reconciliation table), and that Dependabot self-closes rebased PRs without a comment.
- **Architecture** — the most consequential pass. Found that the install-site inventory was
  *provably* incomplete and that Phase 0.2's re-derivation command reproduced the blind spot by
  construction: `plugins/soleur/scripts/grok-fidelity-gate.sh:28` (root install feeding the required
  `grok-fidelity` check) and `apps/web-platform/.github/workflows/constraint-gates.yml:54` (one of a
  byte-parity triad) both sit outside `.github/workflows/`, so Guard 2's original assembly would have
  reported GREEN with two live `bun install` sites remaining. Also established that retiring the SDK
  gate's Section 1 wholesale would reopen the #5849 silent-green class, because Section 2
  short-circuits on an empty resolved version and Section 1's `[[ -z "$pv" ]]` arm is its only catch;
  that the release-age floor was never measured against root-cwd global exact pins, which a model-launch
  PR hits directly; that the "Dockerfile never COPYs `.npmrc`" claim is literally false
  (`Dockerfile:10` is `COPY . .`); that four further ADRs are touched; that six agent-facing prose
  surfaces would instruct the next agent to recreate `bun.lock`; and that `worktree-manager.sh`'s root
  branch would break every new worktree. It also verified empirically, against this bun-installed
  tree, that none of the ten install-script packages needs its postinstall in CI — which is the
  strongest available evidence for the `--ignore-scripts` decision.
