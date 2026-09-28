---
title: "feat: Inngest execution placement — keep execution on web-1, codify a drift-guarded placement rule (ADR-033 amendment)"
type: feat
date: 2026-09-28
slug: feat-inngest-execution-host-placement-rule
branch: feat-one-shot-7230-inngest-execution-split
issue: 7230
closes: 7230
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# feat: Inngest execution placement: a codified, drift-guarded rule (#7230)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this
branch.

## Enhancement Summary

**Deepened on:** 2026-09-28

**Sections enhanced:** 9. These are Research Insights, Proposed Solution (decision constraint and
class definitions), Architecture Decision (ADR-100 item and C4 re-sourcing), Implementation Phases
0–2, Files to Edit, Guard Contract (all four guards), Acceptance Criteria, Risks and Deferrals.

**Agents used:**

- `soleur:engineering:review:architecture-strategist`
- `soleur:engineering:review:test-design-reviewer`
- a mechanical verify-the-negative and attribution sweep
- direct SDK source reads of `inngest@3.54.2`

**Halt gates cleared:** 4.6 (User-Brand Impact), 4.7 (Observability, probe verb `grep` allowed),
4.8 (no PAT shapes) and 4.11 (`lint-guard-contract.py`: 4 entries, green). The 4.5, 4.55, 4.9
and 4.10 gates are not triggered.

### Key Improvements

1. **The guards now work on the real tree.**
   - The walker gets a required `fs` seam that includes `listFiles`.
   - `stopAt` is dropped: the walk descends through the definers, which closes the hole where an
     allowlisted helper calls an imported pinning module.
   - Non-literal import arguments are recorded, so the `cron-ux-audit.ts` exemption is exact:
     `{ botFixturePath: 2, botSigninPath: 1 }`, not "3 × botFixturePath".
2. **Vacuous and ambient rows were replaced.**
   - Every fixture is synthesized.
   - The anti-vacuity floors sit inside the helpers.
   - Suite-edit rows that could not be executed tests were rewritten as executable ones.
   - Namespace, `require` and type-only shapes are covered.
3. **The architecture is coherent across ADRs.**
   - ADR-100 sub-decision 1 gets a serve-URL note.
   - ADR-248's #7230 reversal trigger is re-pointed to #9137.
   - The target constraint is stated: one app id means one serve URL, so placement-aware
     execution needs per-class app ids or function-aware ingress.
   - The `volume-bound` definition is tightened to the sole-copy LUKS holder.
   - The `host-affine` stickiness and clone-root/GC co-location rule is stated.
4. **The C4 model is honest.** Three edges that attribute function effects to the Inngest server
   host are re-sourced to `api`. `model.likec4.json` regeneration and `c4-model-freshness` are
   added to verification.

### New Considerations Discovered

- **Two sanctioned Inngest-scheduled watchers exist:** `cron-inngest-config-drift` and
  `cron-inngest-cron-watchdog`. The corollary is restated as "a verifier whose own run is the
  only signal of total loss of its subject must not be executed by that subject", and Guard 3's
  property is narrowed to match.
- **`scheduled-prod-version-drift` is also native-`schedule:`-only**, so it is best-effort per
  #8495.
- **The encryption-posture ledger misattributes step outputs** to the private `sdk_url` link and
  does not model the Cloudflare step-call leg. Filed as **#9139**; it is out of scope here.
- **The SDK registers 72 functions, not 70**, because of two `onFailure` handlers. The `-failure`
  functions inherit their parent's class.
- **The verification sweep corrected three claims:**
  - "every function imports `_cron-shared`": in fact every cron does, and a few event functions do
    not;
  - "`cron-bash-allowlist-hook.mjs` is never imported": it is imported via
    `cron-filing-deny-marker.ts`;
  - the #4886 "revert" wording.
  - It also confirmed about 90 other claims, all 15 issue/PR citations, and all 8 rule ids.

## Overview

The dedicated Inngest host (ADR-100) moved only the **scheduler** off web-1. Every one of the 70
functions that `app/api/inngest/route.ts` serves still **executes** on web-1. The Inngest server
calls steps at the registered serve URL, `https://app.soleur.ai/api/inngest`, and
`cloudflare_record.app` points only at web-1. This plan settles #7230's architecture question
through the CTO ruling:

- **Decision: option (c) now.** Execution stays on the one step-executing host.
- **Option (b), a separate deployable, is rejected.**
- **Option (a), a worker on the Inngest host, is demoted to a fallback.** The designated target is
  placement-aware execution at the ADR-143 Phase-3 flip, tracked in **#9137**.

This PR makes that decision **mechanical and drift-guarded**. A new client-free leaf,
`server/inngest/execution-placement.ts`, puts every served function in one of three classes:
`portable`, `host-affine` or `volume-bound`. Four vitest guards bind the rule to the code:

- **Guard 1 (manifest set identity):** the manifest covers exactly the served set.
- **Guard 2 (portable boundary):** a `portable` function cannot reach a host-local dependency.
- **Guard 3 (anti-circularity):** ADR-033's anti-circularity corollary is re-verified by a check
  that can go red.
- **Guard 4 (serve-URL anchor):** there is one `serve()` registry, and its production serve URL is
  exactly `https://app.soleur.ai`.

Guard 4 is an AST tightening of the existing, regex-loose guard (g). Together with
`lb-weight-gate.test.sh` Condition C, which pins `app` to web-1, it makes "every function executes
on web-1" a checked claim. It replaced a broader "single registry" guard that was cut at plan
review (see `## Plan Review Revisions`).

The decision is recorded as an ADR-033 amendment, which also corrects the "pinned by `sdk_url`"
imprecision. It comes with one-line cross-updates in ADR-030, ADR-143 and ADR-248 and a `model.c4`
edge edit.

**No production write by the pipeline, no infra edit, no workflow edit, no runtime behaviour
change.** Nothing at runtime imports the new leaf. Every file under `apps/web-platform/infra/**`
is deliberately untouched, because `apply-web-platform-infra.yml` fires a production
`terraform apply` on any push to `main` under that path.

Merging does cut the standard web-platform release of a behaviourally identical image, as every
`apps/web-platform/**` PR does. See the first bullet under `## Sharp Edges`.

## Research Insights

### Premise Validation (Phase 0.6)

- **#7230**: open, not closed by any PR. The one linked PR (#8691, merged 2026-09-24) closes #8495
  and only cites #7230 (Lead-verified; not re-derived).
- **Backlog siblings**: #8562, #7463 and #7308 are all open and do not overlap this plan: #8562 is
  inngest-host boot, #7463/#7308 are the CLI pin. #8495 is closed.
- **Cited artifacts exist on origin/main (9926a1e82c)**: `apps/web-platform/infra/inngest-host.tf`
  (the `sdk_url` comment is now at ~L349, not L272), `apps/web-platform/app/api/inngest/route.ts`,
  `apps/web-platform/test/server/inngest/function-registry-count.test.ts`, and ADR-030, 033, 100,
  119, 143, 243 and 248.
- **STALE premise 1: execution is not bound by `sdk_url`.** The issue and ADR-033's corollary say
  execution is pinned "by the single `sdk_url` callback". Per #8611/ADR-243 that URL is only the
  **registration poll**. The Inngest server calls steps at the **registered serve URL**:
  `route.ts` pins `serve({ serveHost: "https://app.soleur.ai", servePath: "/api/inngest" })`, and
  that request goes through Cloudflare to `cloudflare_record.app` (`apps/web-platform/infra/dns.tf`).
  The record's `content = hcloud_server.web["web-1"].ipv4_address` is a single proxied A record.
  The binding really lives in route.ts `SERVE_HOST` plus `dns.tf` `cloudflare_record.app`. The
  `model.c4` edge `inngest -> api` and the header comment in `function-registry-count.test.ts`
  already say this. ADR-033's corollary and ADR-248's failure-domain table ("via `sdk_url`") do not.
- **STALE premise 2: "34 of 53 spawn claude-code".** Measured now, route.ts serves **70**
  functions: 55 `cron-*.ts` plus 15 event/oneshot/settle. **18** of them spawn Claude through
  `spawnClaudeEval`, which matches ADR-243 §3's "all 18".
- **Mechanism vs ADR corpus**: option (a), a second SDK worker, is not rejected in any ADR.
  ADR-100 rejected multi-*scheduler* shapes, not multi-*worker* ones. ADR-243 §2 and the `dns.tf`
  header comment make "one step-executing host" load-bearing for every Claude-spawning function.
  ADR-248's reversal trigger fires only if execution is decoupled from web-1.

### Property List (Phase 0.6b)

- **P1**: For any served Inngest function, a reviewer can find mechanically which host it executes
  on today, and which hosts it could legally execute on.
- **P2**: That answer is drift-guarded in the required `test` CI context. Adding a host-local
  dependency to a function declared host-free fails CI, and so does fanning the step-execution
  URL out to a second host without revisiting the rule.
- **P3**: ADR-033's anti-circularity corollary is re-verified against the current topology by a
  check that can go red, not just restated.
- **P4**: The null option (c) is costed against (a) and (b) in the decision record, with explicit
  triggers for re-opening it.
- **P5**: The PR merges with zero production writes and no `.github/workflows/*` edit.

### Cut List (Phase 0.6b)

- **"Point `sdk_url` at the inngest host"** → no property. It is also the wrong knob: `sdk_url`
  is the registration poll, not the execution binding.
- **Per-file `EXECUTION_HOST` constant in each `cron-*.ts`** → P1. A central manifest keyed by the
  route.ts identifier covers event functions too, and one file can serve two functions
  (`agent-on-spawn-requested.ts` exports two). Carrier chosen in Implementation Phase 1.
- **Import-closure (module-reachability) classifier** → P2. It is useless today. All but about 5 served functions reach `_cron-shared.ts` (all 55 crons
  import it directly), and that module mixes workspace-root and deploy-lease helpers with generic
  ones (`postSentryHeartbeat`, `mintInstallationToken`), so reachability marks about 65 of 70 as
  pinned. The exceptions, per the deepen-pass sweep, are `cfo-on-payment-failed`,
  `github-on-event` and `oneshot-gdpr-gate-50d-eval`, which do not reach it even transitively;
  `workspace-reconcile-on-push` and `agent-on-spawn-requested` do not import it directly. **Call-site** detection replaces it (Guard 2).
- **Count floor on "portable" functions** → P2. A stored `>= N` floor survives substitution and
  certifies itself. Set identity (Guard 1) replaces it.
- **Second SDK worker / subset registry / new appId in this PR** → P5 forbids it: it needs host
  config on the inngest host, which is an immutable redeploy. It is deferred to a tracked
  follow-up (see Deferrals).

### Measured classification (plan time)

Script: `node <scratchpad>/classify.mjs apps/web-platform`. It parses the route.ts `serve()`
array, resolves each identifier's module and greps the module's own source for pinning call
sites.

| Class (proposed) | Count | Evidence marker (own source) | Members (route.ts identifiers) |
|---|---|---|---|
| Claude spawn (process-local single-flight, ADR-243 §2) | 18 | `spawnClaudeEval(` / `spawnSimple(` / `resolveClaudeBin(` | cronAgentNativeAudit, cronArchitectureDiagramSync, cronBugFixer, cronCampaignCalendar, cronCommunityMonitor, cronCompetitiveAnalysis, cronContentGenerator, cronDailyTriage, cronFollowThroughMonitor, cronGrowthAudit, cronGrowthExecution, cronLegalAudit, cronRoadmapReview, cronSeoAeoAudit, cronUxAudit, eventShipMerge, oneshotF2DeferGateReview, oneshotRecheck4217Calibration |
| Ephemeral workspace / deploy lease / git+bash spawn on `CRON_WORKSPACE_ROOT` (= `/workspaces`, the `/mnt/data` volume) | 9 | `setupEphemeralWorkspace` / `resolveCronWorkspaceRoot` / `node:child_process` | cronContentPublisher, cronCompoundPromote, cronContentVendorDrift, cronGithubCidrRefresh, cronRulePrune, cronStrategyReview, cronWeeklyAnalytics, cronSkillFreshness, cronWorkspaceGc |
| User-workspace data (sole-copy volume, ADR-119) via `server/workspace.ts`-class modules | 4 | `child_process` in closure through workspace modules | cronWorkspaceSyncHealth, workspaceReconcileOnPush, agentOnSpawnRequested, agentOnSpawnSettle |
| No host-local marker | 39 | none | GHA dispatchers (11 via `const WORKFLOW_FILE = "…yml"`), API/HTTP probes, watchdog, event handlers |

The 39 "no marker" functions still need prd secrets: the GitHub App key, the Supabase service
role, Sentry and others. They are host-free, not secret-free.

### Relevant files (content anchors)

- `apps/web-platform/app/api/inngest/route.ts`: `const SERVE_HOST`, the `serve({ … functions: [ … ] })` array (70 entries).
- `apps/web-platform/server/inngest/client.ts`: `id: "soleur-runtime"`, the single Inngest app.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts`: `resolveCronWorkspaceRoot`, `resolveDeployLeasePath`, `deployLeaseAgeMsIfFresh`, `deferDeployOnFinalAttempt`, `warnIfCronWorkspaceLowOnDisk` (the pinning definers). Every cron imports this module; a few event functions do not.
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`: `spawnClaudeEval`, `spawnSimple`, `resolveClaudeBin`, `setupEphemeralWorkspace`.
- `apps/web-platform/infra/dns.tf`: `resource "cloudflare_record" "app"`, whose header says "Single step-executing host is load-bearing". **Read-only for this plan.**
- `apps/web-platform/server/watchdog-dispatch-table.ts`: `WATCHDOG_DISPATCH_TABLE` (ADR-248 rows: `scheduled-inngest-health.yml`, `scheduled-zot-restart-loop.yml`). It is import-free by design.
- `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts`: "Guard 2 (static half)", a fail-closed TypeScript-parser import walker (`resolveSpecifier`, `specifiersOf`, `walk`). This plan reuses it.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts`: guards (a)–(g). Its `NON_INNGEST_MONITORS` comments already document the anti-circularity set.
- `knowledge-base/engineering/architecture/decisions/ADR-033-…-child-process-spawn.md`: the anti-circularity corollary (Considered Options, Option C, second sub-bullet) and `## Amendment — 2026-09-23 (#8611, ADR-243)` (the amendment heading shape).
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`: `## Updates / amendment log`.
- `knowledge-base/engineering/architecture/decisions/ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md`: `### Failure domains` and `## Reversal triggers`.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: edge `inngest -> api "Invokes function steps at the registered serve URL …"`.

### Institutional learnings applied

- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: every guard here gets a mutation matrix that includes an own-dispatch row. This is the Guard Contract below.
- `best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`: no stored count floors. Set identity against route.ts is used instead, and route.ts is independently required by the existing guard (a).
- `2026-05-16-adr-amendment-required-when-reversing-…`: the ADR-033 corollary text is corrected in the same PR that re-verifies it.
- `2026-07-03-dark-launch-pr-must-exclude-operator-prerequisite-infra.md`: this supports scoping infra out entirely rather than shipping inert infra.
- `2026-06-16-adr-c4-update-is-a-plan-deliverable-not-a-deferred-issue.md`: the ADR amendment and the C4 edge edit are in this PR.

### Inngest SDK facts (verified against the installed `inngest@3.54.2`, deepen pass)

From `apps/web-platform/node_modules/inngest/components/InngestFunction.js`:

```js
id(prefix) { return [prefix, this.opts.id].filter(Boolean).join("-"); }
get absoluteId() { return this.id(this.client.id); }          // "<appId>-<fnId>"
static failureSuffix = "-failure";
// when onFailure is set:
const id = `${fn.id}${InngestFunction.failureSuffix}`;         // "<fnId>-failure"
triggers: [{ event: internalEvents.FunctionFailed,
             expression: `event.data.function_id == '${fnId}'` }]
```

These back three claims in the plan:

- **Function identity is app-scoped.** A function moved to a second app id (option (a)) gets a
  new absolute id.
- **`onFailure` handlers are separate registered functions.** They bind to their parent by the
  parent's absolute id, so they must share the parent's host. That is the "inherit the parent's
  class" rule.
- **The served count is 72, not 70.** Two functions (`agent-on-spawn-requested`,
  `cron-gh-pages-cert-reissue`) define `onFailure`, so the SDK registers 72 while route.ts serves
  70.

### Functional overlap (Phase 1.5b)

No community skill or agent covers execution placement (claude-plugins.dev, claudepluginhub,
Anthropic marketplace). Nothing was installed.

### External research decision (Phase 1.6)

Skipped. Local context is strong, and the decision turns on this repo's topology, not on vendor
behavior. The one vendor question (multi-app function-ID namespacing for option (a)) belongs to
the deferred follow-up and is recorded there as a research item.

### CLAUDE.md / AGENTS conventions in force

`hr-prod-host-config-change-immutable-redeploy`, `hr-all-infrastructure-provisioning-servers`,
`wg-architecture-decision-is-a-plan-deliverable`, `cq-cite-content-anchor-not-line-number`,
`cq-assert-anchor-not-bare-token`, `wg-when-deferring-a-capability-create-a`,
`hr-observability-as-plan-quality-gate`.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #7230 / ADR text) | Reality on origin/main 9926a1e82c | Plan response |
|---|---|---|
| Execution is pinned to web-1 "by the single `sdk_url` callback" (ADR-033 corollary, ADR-248 failure-domain table) | `sdk_url` is the registration poll (#8611/ADR-243). Steps are called at the registered `serveHost` `https://app.soleur.ai/api/inngest`. That goes through Cloudflare to `cloudflare_record.app`, and `dns.tf` points it only at web-1. | Correct the wording in ADR-033 and ADR-248 in this PR. The amendment names the real binding: route.ts `SERVE_HOST` plus `dns.tf` `cloudflare_record.app`. |
| "34 of 53 cron functions spawn claude-code" | 70 functions are served (55 `cron-*.ts` plus 15 event functions). 18 spawn Claude via `spawnClaudeEval`; 8 more use ephemeral clones, git or bash spawns. | Replace the count in ADR-033 with a pointer to the manifest. The ADR carries no counts, so there is no parity drift. |
| `function-registry-count.test.ts` is "the natural home" for the guard | That file is already 329 lines covering a different property (registration and Sentry parity). | The guards go in a sibling file, `execution-placement.test.ts`, and `function-registry-count.test.ts` gets a cross-reference comment next to guard (a). |
| A "second SDK worker on the inngest host" is option (a) | The Inngest host provisions no Node runtime (`grep -ci node apps/web-platform/infra/cloud-init-inngest.yml` → 0) and has an isolated `soleur-inngest` Doppler project (ADR-100). Same-app-id `--sdk-url`s collapse route-once (ADR-100 Decision 1), so a worker needs a new app id, which means new function IDs. | Option (a) is demoted to a fallback with its constraints written into #9137. The primary target is Phase-3 placement-aware execution. |
| "The DNS half of single-host execution is unguarded" (planner's first draft) | `apps/web-platform/infra/lb-weight-gate.test.sh` Condition C (C.1a/b/c) already asserts that `cloudflare_record.app` means web-1 only, with exactly one `app` record and no web-2 reference. | Guard 4, the serve-URL anchor, keeps only the app side; the ADR cites Condition C for the DNS side. Condition C is **not edited**, because an edit under `infra/**` fires the production apply workflow on merge. |

## Problem Statement

Three things are wrong today, and none of them is "execution is on web-1".

1. **The placement of a function is unknowable except by reading its imports.** Nothing records
   which functions *could* run elsewhere. The ADR-143 Phase-3 flip will need that answer the day
   web-2 gets serving weight: ADR-243 §2 and the `dns.tf` header say so. The one statement of it
   in #7230 is already wrong (34 vs 18).
2. **The anti-circularity corollary is prose only.** No check stops a future `cron-*.ts` from
   dispatching `workspaces-luks-verify.yml` (or an ADR-248 watchdog workflow) and re-creating the
   exact silence-read-as-health defect #6808 documented. The ADR-248 clock test forbids the *clock*
   from importing Inngest. Nothing forbids *Inngest* from dispatching the watchers.
3. **Two ADRs misstate the binding** ("via `sdk_url`"). A future engineer who "fixes" execution by
   repointing `sdk_url` changes nothing about where steps run.

## Proposed Solution

### Decision (CTO ruling, recorded in the ADR-033 amendment)

| Option | Ruling | Why |
|---|---|---|
| **(c) keep execution on the one step-executing host (web-1)** | **Adopt now** | Existing mechanisms already deliver most of (a)'s benefits. Anti-circularity is served by the GHA-native schedule and the ADR-248 clock on both web hosts. Restart coupling is absorbed by Inngest retries plus the ADR-078 drain lease. A web-1 outage is a product outage that Better Stack already pages. It also needs no production write. |
| **Placement-aware execution at the ADR-143 Phase-3 flip** | **Designated target (#9137)** | `portable` functions run on any web host, `host-affine` functions stick to one host, and `volume-bound` functions stay on the sole-copy LUKS volume holder. Losing web-1 then no longer drops portable work, and the singleton control plane is untouched. |
| **(a) second SDK worker on the Inngest host** | **Fallback only (#9137)**, for a verifier that must survive the loss of *every* web host | It would put a Node worker and prd secrets on the deliberately minimal singleton control-plane host, turning ADR-100 SEC-H3's *indirect* exposure into direct secret read. It adds a second deploy target and version-skew surface, and a new app id means new function IDs, with a double-fire-or-gap migration. |
| **(b) separate cron deployable** | **Reject** | It duplicates the build, deploy and version-drift pipelines for small functions. The importability boundary it offers is delivered inside one deployable by the client-free leaf pattern (`cron-manifest.ts`) plus Guard 2. |

**Re-open triggers**, stated in the amendment and in #9137: (1) the ADR-143 Phase-3 flip is
scheduled; (2) a new host-state verifier appears that neither the GHA-native schedule nor the
ADR-248 clock can serve; (3) a measured incident in which losing web-1 dropped `portable` work
with user impact.

**Constraint on the target (deepen pass, architecture review P1-2).** A serve URL belongs to an app
id, and it is last-writer-wins per app id (ADR-100 finding 1). So a single-app-id deployment cannot
give `host-affine` or `volume-bound` functions a different URL than `portable` ones.

Placement-aware execution therefore needs one of two things:

- **per-class app ids**, which means new function ids, the same migration cost the table charges
  against (a); or
- **an ingress layer that routes a step request by its function id**, for example host affinity
  on `/api/inngest` keyed by the `fnId` query parameter.

This does not change the ruling, because both costs sit in #9137 and neither is paid here. But the
amendment must state it so the table stays consistent.

### The placement rule (three classes)

| Class | Meaning | Future host constraint | Marker (Guard 2 derives `portable` must have none) |
|---|---|---|---|
| `portable` | No host-local dependency. It still needs prd secrets: host-free, **not** secret-free. | Any host holding the secrets. | none |
| `host-affine` | Needs exactly one host with the app image: the Claude spawn (`spawnClaudeEval`, whose single-flight guard is process-local, ADR-243 §2), an ephemeral clone on `CRON_WORKSPACE_ROOT`, the ADR-078 deploy lease, or a child process. | Exactly one app host, **sticky per run**: every step and retry of a run must reach the same process, including within ADR-243's 2 h `SETTLED_TTL_MS`. That host's `CRON_WORKSPACE_ROOT` must be the host-mounted `/mnt/data/workspaces`, so the deploy lease stays visible to `ci-deploy.sh`, and `cron-workspace-gc` must also run there. | pinning-definer imports outside the allowlist; `child_process`; volume path or env |
| `volume-bound` | Touches user workspaces, meaning it reads `WORKSPACES_ROOT` or reaches `server/workspace.ts`/`server/workspace-resolver.ts`. | Only the host holding the ADR-119 **sole-copy LUKS** workspaces volume, `hcloud_volume.workspaces_luks` (web-1 today). Not merely a host with a `/mnt/data`: `hcloud_volume.workspaces` is `for_each = var.web_hosts`, so every web host has one. | same as above |

- **Ephemeral cron clones are `host-affine`, not `volume-bound`.** They sit on `/mnt/data` for disk
  capacity, not for data (CTO Q2).
- **`cron-workspace-gc` is `volume-bound`.** It sweeps `/workspaces` directly, which is the user-data
  volume (#4882; #4886's `.cron` subdir isolation was later reverted, per the file header).
  - It is **also** the garbage collector for every `host-affine` clone root.
  - Three single-host classes cannot express "the GC runs wherever `host-affine` producers run".
    Moving producers to another host without a per-host GC leaks clones there until the volume
    fills (the 2026-06-02 ENOSPC freeze), and it hides the deploy lease from `ci-deploy.sh`.
  - The amendment states this co-location constraint, the gc row's `reason` repeats it, and it is
    posted to #9137 (per-host GC, the ADR-248 fleet rule, is the likely shape).
- **Known gaps the guard cannot detect.** Guard 2 cannot see process-local module state (for
  example a `globalThis` single-flight map) or loopback/private-IP HTTP calls. The ADR records both.
  Guard 2 enforces only the `portable` boundary. Over-pinning is safe and is not guarded. The
  `host-affine`/`volume-bound` split is declared and reviewed, and becomes enforced when a
  placement-aware registry consumes it (#9137).

**Initial classification.** These counts were measured by a regex walker at plan time, and they
are provisional. At work time the rows are generated from the real TS-AST walker's discovery pass
(Phase 2), and Guard 2 is the arbiter:

- **`host-affine` (26):** the 18 Claude spawners in the Research Insights table, plus
  cron-content-publisher, cron-compound-promote, cron-content-vendor-drift,
  cron-github-cidr-refresh, cron-rule-prune, cron-strategy-review, cron-weekly-analytics and
  cron-skill-freshness.
- **`volume-bound` (7):** cron-workspace-sync-health, workspace-reconcile-on-push,
  agent-on-spawn-requested's two functions, cron-workspace-gc, and two conservative pins:
  cfo-on-payment-failed and github-on-event. Those two reach `server/workspace-resolver.ts` through
  their import closure. The plan-time measurement ran with the two definer modules excluded.
- **`portable` (37):** everything else.

The manifest is keyed by the **Inngest function id**, extracted from
`createFunction({ id: … })`, not by the route.ts identifier. The id is the identity that survives a
move, and it matches the `EXPECTED_CRON_FUNCTIONS` convention.

### The guards (full contracts in `## Guard Contract`)

- **Guard 1: manifest set identity.** The `EXECUTION_PLACEMENT` keys equal the function ids of the
  route.ts-served set.
- **Guard 2: portable boundary.** A `portable` function reaches no host-local dependency.
  - The two pinning-definer modules, `_cron-shared.ts` and `_cron-claude-eval-substrate.ts`, are
    judged by a **default-deny allowlist of named exports**, `PORTABLE_SAFE_SHARED_EXPORTS`,
    wherever in the closure they are imported.
  - The allowlist is seeded with the 14 names the portable set imports today: `REPO_OWNER`,
    `REPO_NAME`, `mintInstallationToken`, `postSentryHeartbeat`, `redactToken`, `isFinalAttempt`,
    `postDiscordWebhook`, `postAnthropicMessage`, `getAnthropicAdminReport`, `AnthropicApiError`,
    `ANTHROPIC_AUTH_FAILURE_RE`, `ANTHROPIC_CREDIT_EXHAUSTED_RE`, `AUDIT_SELF_REPORT_BODY_PREFIX`
    and `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`.
  - Each allowlisted export's **own declaration** is also scanned in its definer. The scan follows
    same-file top-level references transitively and fails if it reaches a pinning seed. So
    editing an allowlisted helper to pin cannot pass silently (advisor finding).
  - Every other module in the closure is scanned for `child_process`, the `/workspaces` and
    `/mnt/data` literals, and the `WORKSPACES_ROOT`/`CRON_WORKSPACE_ROOT` env reads.
- **Guard 3: anti-circularity.** No served-function closure module, and no non-test `.ts` or
  `.mjs` module under `server/inngest/`, carries a **string literal** containing the stem of a
  forbidden workflow. The `.mjs` covers `cron-bash-allowlist-hook.mjs`. It is also imported, via
  `server/cron-filing-deny-marker.ts` from the substrate, but the directory scan covers it
  regardless of how it is reached.
  - The forbidden set is `WATCHDOG_DISPATCH_TABLE` (imported, not copied) plus
    `HOST_STATE_VERIFIER_WORKFLOWS` (`workspaces-luks-verify.yml`,
    `scheduled-prod-version-drift.yml`).
  - Every forbidden member must exist under `.github/workflows/`.

- **Guard 4: serve-URL anchor.** Exactly one module imports `serve` from any `inngest/<adapter>`
  (`app/api/inngest/route.ts`). The production branch of `SERVE_HOST` is the string literal
  `"https://app.soleur.ai"`, and `serveHost` references it. This is checked by AST, because guard
  (g)'s regex is satisfied by the literal appearing anywhere later in the file.

**Where things live.** The leaf holds **only** placement data: the `ExecutionPlacement` type and
`EXECUTION_PLACEMENT`. It is the thing #9137's placement-aware registry will import.

Guard configuration lives in the test file, `test/server/inngest/execution-placement.test.ts`:
`PORTABLE_SAFE_SHARED_EXPORTS`, `HOST_STATE_VERIFIER_WORKFLOWS`, and the pure guard helpers that
take a `readFile` seam. Keeping `HOST_STATE_VERIFIER_WORKFLOWS` out of `server/inngest/` also means
Guard 3 cannot collide with its own forbidden-stem list (advisor finding). Every mutation-matrix
row runs as an in-memory synthesized fixture (`cq-test-fixtures-synthesized-only`). The same
helpers also run once, unmutated, against the real tree.

**Failure messages name the fix** (CTO devex):

- **Guard 1:** the leaf path plus a paste-ready row stub. For a non-literal id: "use a string
  literal or a same-file const".
- **Guard 2:** the offending function id and the marker with its module. The remedy: re-class to
  the tightest class the marker implies, never widen the allowlist.
- **Guard 3:** the forbidden stem, its source (watchdog table or verifier list), and a pointer to
  #6808 and the ADR-033 corollary.

## Architecture Decision (ADR/C4)

### ADR

Amend, do not create; there is no new ordinal. **Cite full filenames**: ADR-033 and ADR-030 each
have sibling files with the same number.

1. `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
   - Append `## Amendment — 2026-09-28 (#7230): execution placement`, in the shape of the existing
     `## Amendment — 2026-09-23 (#8611, ADR-243)`. It carries:
     - the decision table;
     - the three classes;
     - the rule that each served function has one class in `server/inngest/execution-placement.ts`;
     - a pointer, not a restatement: "enforced by `test/server/inngest/execution-placement.test.ts`";
     - single-host execution is enforced by Guard 4 plus guard (g) for the serve URL, and by
       `lb-weight-gate.test.sh` Condition C for `app` → web-1. Condition C is path-filtered to
       `infra/**`, which is the only way `app` can change;
     - one plain sentence: the Guard 2 allowlist is seeded from what the code imports today, and
       adding to it is an architecture change;
     - `onFailure` handlers (`<id>-failure`) inherit their parent's class;
     - the re-open triggers and the #9137 pointer;
     - the known gaps:
       - process-local module state;
       - private-IP or loopback HTTP calls;
       - a forbidden workflow named by a template-literal assembly;
       - a dispatch by numeric workflow id;
     - a **re-derived corollary table** for the current topology, covering each verifier's subject,
       trigger, and whether it survives total loss of its subject. The rows are
       `workspaces-luks-verify` (web-1; GHA `schedule:`, best-effort per #8495, see #9138),
       `scheduled-inngest-health` and `scheduled-zot-restart-loop` (the ADR-248 clock on both web
       hosts plus a fallback `schedule:`; this survives only while at least two web hosts are
       deployed, per ADR-248 reversal trigger 3), and `scheduled-prod-version-drift` (GHA-native
       `schedule:` only, best-effort per #8495).
     - **Sanctioned Inngest-scheduled watchers** (architecture review P1-5):
       `cron-inngest-config-drift` (dispatches `inngest-config-drift.yml`) and
       `cron-inngest-cron-watchdog`. They watch Inngest from inside Inngest, which is legitimate
       because their run is **not** the only signal of the substrate's total loss;
       `scheduled-inngest-health` covers that. The corollary is stated as: "a verifier whose own
       run is the only signal of total loss of its subject must not be executed by that subject".
     - It **must not** describe native `schedule:` as reliable.
   - In place, in the corollary sub-bullet: replace "pinned to web-1 by the single `sdk_url`
     callback" and the `sdk_url = …` clause with the serve-URL binding, and replace
     "~34 of 53 cron functions spawn `claude-code` (I1)" with a pointer to the manifest. Mark it
     `[corrected 2026-09-28, #7230]`.
   - In ``### Registration checklist (a NEW `cron-*` claude-eval function)`` (the heading contains
     backticks), which is a 7-row table:
     - add row 8: `server/inngest/execution-placement.ts` | `EXECUTION_PLACEMENT` row with the tightest class the function's markers imply (Guard 2 rejects a wrong `portable`) | `execution-placement.test.ts` Guard 1;
     - change "touches **seven** gated locations" to **eight**, with a `Revised 2026-09-28 — #7230` note appended to its bracketed revision line.
2. `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`:
   add a one-line `## Updates / amendment log` entry pointing to the ADR-033 amendment.
3. `knowledge-base/engineering/architecture/decisions/ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md`:
   - In the `### Failure domains` row "web-1 app container (also Inngest's execution host, via
     `sdk_url`)", replace `via \`sdk_url\`` with "via the `app.soleur.ai` serve URL".
   - Under `## Reversal triggers`, re-point "Inngest function execution is decoupled from web-1
     (#7230)" to **#9137**, because this PR closes #7230 while the decoupling itself moves to
     #9137. No "trigger not fired" note: a non-event needs no entry (plan review).
4. `knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md`:
   add one line to `## Amendment — 2026-09-23 (#8611, ADR-243)`: the Phase-3 flip must honour the
   execution placement classes (ADR-033 amendment, #7230, #9137).
5. `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`
   (architecture review P1-1): add a dated one-line note under Decision sub-item 1 ("Fan-out
   mechanism — single stable `--sdk-url`, VIP at N>1").
   - The note says that **step** fan-out is governed by the registered `serveHost` plus
     `cloudflare_record.app` and the ADR-033 #7230 placement classes, not by `--sdk-url`, which is
     the registration poll (#8611).
   - Otherwise a Phase-3 implementer following ADR-100 would put a VIP behind `--sdk-url` and
     change nothing about where steps run.
   - The note leaves the rest of ADR-100 unchanged.

### C4 views

All three files were read: `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`
and `spec.c4`.

**Actors and systems checked:**

- `inngest` (container "Inngest Server", dedicated host), `api` (container "API Routes"),
  `hetzner` (web hosts), `github` (the GHA dispatch target), `inngestPostgres` and `inngestRedis`.
  All are modelled already.
- No new external actor, system or store. The change adds no element.

**Relationships changed** (architecture review, C4 finding):

- The `inngest -> api "Invokes function steps at the registered serve URL …"` edge prose gains two
  statements:
  - every function executes on the one step-executing host, web-1 (`cloudflare_record.app`), with
    per-function placement classes defined by the ADR-033 amendment (#7230);
  - the dedicated host's `--sdk-url` (`http://10.0.1.10:3000/api/inngest`) is the registration
    poll only, not the step path.
- **Three mis-sourced edges are re-sourced from `inngest` to `api`.** Each effect is performed by
  an Inngest **function**, which executes on web-1, not by the Inngest server host. Leaving them on
  `inngest` contradicts ADR-100's isolated `soleur-inngest` secret set, which the decision table's
  SEC-H3 argument relies on.
  - `inngest -> supabase "Email-triage claim/finalize writes (email-on-received)"`;
  - `inngest -> github "Mints packages:read installation token every 20 min (ADR-088)"`
    (`cron-ghcr-token-minter`);
  - `inngest -> doppler "Writes GHCR_READ_TOKEN …"`.
  - Each moved edge's prose gains "(Inngest-fired function, executed on web-1)". The edge text is
    otherwise unchanged, including any numbers.
  - Before editing, `grep -n` `views.c4` for any view that includes these edges by source. After
    editing, the c4 render test confirms that every view still resolves.
- The edit adds **no numeric counts**, so it does not move `c4-count-parity`.
- Validate with `apps/web-platform/test/c4-code-syntax.test.ts`,
  `apps/web-platform/test/c4-render.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

Everything lands in this PR. The ADR describes the **current** state (option (c)), not a target
state. The target state is #9137.

## Implementation Phases

### Phase 0: Extract the import walker (refactor, behaviour-preserving)

- Move `resolveSpecifier`, `specifiersOf` and `walk` from
  `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts` ("Guard 2 (static half)") into
  `apps/web-platform/test/helpers/ts-import-graph.ts`. Keep the fail-closed semantics: an
  unresolved local specifier or a non-literal dynamic import is a problem.
- Inject the filesystem as `fs = { readFile, exists, listFiles, appRoot }` (Kieran P0, test-design
  P1-4).
  - The seam is a **required** parameter on every new helper, so a nested call that forgets it
    fails to type-check rather than silently reading the real tree.
  - Only the clock test's existing call keeps a default: `readFileSync` / `existsSync` / a real
    directory listing / `APP_ROOT`.
  - `rel()` takes `appRoot` from `fs`, so fixture failure messages are readable.
  - `listFiles` exists so that Guard 3's directory scan and Guard 4's file enumeration do their
    extension and test-file filtering **inside** the helper. Fixtures exercise that filtering too.
- Add two additive options. Both are off by default, so the clock guard is unchanged:
  - `elideTypeOnlySpecifiers?: boolean`: drop an import edge whose every named specifier is
    `type`-qualified (`import { type X }`), as TS does. This lets a type-only import of
    `workspace-resolver` types avoid spuriously pinning a function (advisor finding). Guard 2's
    named-binding check (i) separately skips each individual `type` specifier on a mixed import.
  - `recordDynamicImportArgs?: boolean`: record a non-literal `import()`/`require()` as
    `{ file, argText }` instead of the bare `"<non-literal-dynamic-import>"` marker. Guard 3's
    exemption can then be keyed by argument identifier (test-design P0-1).
- **No `stopAt`.** An earlier draft stopped the walk at the definer modules, but that left their own
  imports unscanned (test-design P0-3). The walk now descends through definers. Guard 2 exempts
  only the definers' **own source text** from its marker scan, and judges what may be imported
  from them by named binding.
- Point the clock test at the helper. Its assertions and in-file fixtures stay unchanged.
- **Equivalence evidence, not just a count** (advisor; test-design P2-11).
  - While both walkers exist, run the old and the new walker over the clock entry **and every
    served function module** (about 71 entries).
  - Write each sorted reach set and problems list to a scratch file and `diff` them. They must
    be identical.
  - Paste the `diff` summary (empty) and the clock test's before/after pass counts into the PR
    body. The plan-time baseline is 63 passed.

### Phase 1 (RED): Write the guard suite

- Create `apps/web-platform/test/server/inngest/execution-placement.test.ts`. It holds the guard
  config, `PORTABLE_SAFE_SHARED_EXPORTS` and `HOST_STATE_VERIFIER_WORKFLOWS`, plus pure helper
  functions over a `readFile(path) => string | null` seam:
  - `servedFunctions(routeSrc, readFile)` returns `{ ident, module, id }[]`, fail-closed.
  - `derivePinning(fn, readFile)` returns the markers found. Guard 2 uses it, and so does the
    Phase-2 discovery pass.
  - `portableViolations(...)`
  - `circularityViolations(...)`
- The suite runs each guard over the real tree and over every mutation-matrix and harness row as
  an in-memory synthesized fixture.
- Import only the leaf and `server/watchdog-dispatch-table.ts`, which are both import-free, so no
  `NEXT_PHASE` hoist is needed.
- Run it: RED, because the leaf is missing.

### Phase 2 (GREEN): Generate, then write, the manifest leaf

- **Discovery first** (advisor finding). Run `derivePinning` over all served functions as a
  throwaway pass, for example a temporary `it.only` that prints JSON. The derived marker set per
  function, not the plan's regex estimate, seeds the rows:
  - no marker → `portable`;
  - a `WORKSPACES_ROOT` read, or reaching `server/workspace.ts` or `server/workspace-resolver.ts`
    → `volume-bound`. The bare `/workspaces` literal is ambiguous, because `CRON_WORKSPACE_ROOT`
    and `WORKSPACES_ROOT` share the value, so it does not decide this alone;
  - any other marker → `host-affine`.
  Where the plan's tables disagree with the discovery output, the discovery output wins; note
  each divergence in the PR body.
- Create `apps/web-platform/server/inngest/execution-placement.ts`. It is client-free and
  import-free, with a header modelled on `cron-manifest.ts`. It exports:
  - `ExecutionPlacement = "portable" | "host-affine" | "volume-bound"`
  - `EXECUTION_PLACEMENT: Readonly<Record<string, { placement: ExecutionPlacement; reason: string }>>`,
    with one row per served function, keyed by function id. Each non-`portable` reason names its
    marker.
- **Never** add a pinning export to the allowlist to make a row pass. Re-class tighter instead.
- Run it: GREEN.

### Phase 3: Cross-reference in the registry test

- In `apps/web-platform/test/server/inngest/function-registry-count.test.ts`, next to the
  `// UPDATE this number when adding/removing Inngest functions.` comment, add
  "and add an `EXECUTION_PLACEMENT` row with the tightest class (execution-placement.test.ts,
  Guard 1)".
- This is class-neutral and covers event functions too (CTO devex). It is a comment only; no
  assertion changes.

### Phase 4: ADR amendments

Apply the ADR edits in `## Architecture Decision (ADR/C4)` → `### ADR`, items 1–4.

### Phase 5: C4

- Apply the `model.c4` edge-prose edit.
- Run the c4 syntax and render tests, plus `c4-count-parity`.

### Phase 6: Verify (targeted, not the local affected gate)

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run \
  test/server/inngest/execution-placement.test.ts \
  test/server/inngest/function-registry-count.test.ts \
  test/server/watchdog-dispatch-clock.test.ts \
  test/c4-code-syntax.test.ts test/c4-render.test.ts
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit   # the leaf and helpers are typed
bash plugins/soleur/test/c4-count-parity.test.sh           # from the repo root
bash plugins/soleur/test/c4-model-freshness.test.sh        # regenerated model.likec4.json matches
npx markdownlint-cli2 <every edited .md>                    # ADRs, plan, tasks
```

After that, rely on CI (the required `test` context).

## Files to Create

- `apps/web-platform/server/inngest/execution-placement.ts`: the client-free placement leaf,
  holding placement data only.
- `apps/web-platform/test/server/inngest/execution-placement.test.ts`: Guards 1–3, the guard
  config and the pure helpers, run on the real tree and on the synthesized fixtures.
- `apps/web-platform/test/helpers/ts-import-graph.ts`: the walker extracted from the clock test.
  It has two consumers: the clock test and this suite.

## Files to Edit

- `apps/web-platform/test/server/watchdog-dispatch-clock.test.ts`: import the walker from the
  helper; no assertion change.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts`: a cross-reference
  comment only.
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
- `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`
- `knowledge-base/engineering/architecture/decisions/ADR-248-watchdog-dispatch-clock-runs-in-the-web-server.md`
- `knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md`
- `knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md`: the one-line sub-decision-1 note.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the `inngest -> api` edge
  description, plus the three re-sourced edges (`-> supabase`, `-> github`, `-> doppler`).
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json`: **regenerated, never
  hand-edited**. The lefthook `c4-model-regenerate` step runs `bash scripts/regenerate-c4-model.sh`
  and re-stages it whenever a `.c4` file is staged. It is a committed product that the web-platform
  C4 viewer fetches, and `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs it in CI.
  Review `c4-model.md`'s `## Notes` for staleness when the hook prints its advisory.

**Explicitly NOT edited:**

- `apps/web-platform/infra/**`. That includes `lb-weight-gate.test.sh`, `dns.tf` and
  `inngest-host.tf`, because `apply-web-platform-infra.yml` runs a production apply on any merge
  touching `apps/web-platform/infra/**`.
- `.github/workflows/*`, which would make this an UNTRUSTED-CI PR.
- `app/api/inngest/route.ts`, since there is no runtime change.

## Open Code-Review Overlap

1 open scope-out touches these files: **#8595** (monitor registry guard gaps: stale
`NON_INNGEST_MONITORS` entries and no cadence parity), in `function-registry-count.test.ts`.

- **Disposition: Acknowledge.** This plan adds only a comment to that file and a new sibling test.
  #8595's reverse-direction staleness check and cadence parity are a different property (monitor
  parity, not execution placement). It keeps its own re-evaluation date, 2026-10-06. Folding it in
  would widen this PR into Sentry-monitor parity with no shared mechanism.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Point `sdk_url` at the Inngest host | Wrong knob: `sdk_url` is the registration poll, and steps run at the serve URL. |
| Per-file `EXECUTION_HOST` constant in each `cron-*.ts` | Several files define more than one function (`agent-on-spawn-requested.ts`), event functions are not `cron-*.ts`, and a future subset `serve()` filters on one central table. |
| Import-reachability classifier | `_cron-shared.ts` mixes pinning and generic helpers, so reachability marks all 70 as pinned. Call-site plus named-import detection is required. |
| Denylist of pinning helpers (planner's first G2) | A new pinning helper added to `_cron-shared.ts` would pass silently. Replaced by a default-deny allowlist (CTO Q3). |
| A TS-side assertion on `dns.tf` `app` → web-1 | It duplicates `lb-weight-gate.test.sh` Condition C. Cut (CTO Q4). |
| Begin (a) dark in this PR | No inert form exists: a Node runtime and secrets on the host is a production change (CTO Q1). |
| Fold #9138 (luks-verify schedule reliability) in | Different defect: it is about how the corollary is carried out, not about placement. It also likely edits `server/watchdog-dispatch-table.ts` plus the workflow, which means a workflow PR. |

## Deferrals (tracked)

- **#9137**: placement-aware execution at the Phase-3 flip, plus the constraints for fallback (a).
  Milestone Post-MVP / Later.
- **#9138**: `workspaces-luks-verify` fires only on native GHA `schedule:`; evaluate ADR-248 clock
  membership. Milestone Post-MVP / Later.
- **#9139** (found in the deepen pass): `scripts/encryption-posture-ledger.json` attributes step
  outputs to the private `sdk_url` link and does not model the Cloudflare serve-URL step-call leg.
  It is out of scope here because this PR edits no ledger, infra or legal surface.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The leaf is imported by no
  runtime module, and route.ts, the infra and the workflows are unchanged, so no request, cron or
  event path executes differently. The worst case is developer-facing: a false-RED guard blocks an
  unrelated PR that adds an Inngest function.
- **If this leaks, the user's data / workflow / money is exposed via:** no new exposure vector. The
  PR adds no secret, credential, route or network edge. The latent risk it *reduces* is future: a
  Phase-3 flip that moves a `volume-bound` function (such as `cron-workspace-sync-health`) to a host
  without `/mnt/data` would break one user's workspace sync. The declared classes plus Guard 2 are
  the mechanism that prevents it.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches apps/web-platform/server/ only by adding a data-only leaf (execution-placement.ts) that no runtime module imports, so no user-facing request, cron or event path changes behaviour.`

## Observability

```yaml
liveness_signal:
  what: "the required `test` CI check (vitest `unit` project, include test/**/*.test.ts) running execution-placement.test.ts Guards 1-4 on every PR and every push to main"
  cadence: "per push / per PR"
  alert_target: "red required check blocks merge; a red main is filed by the existing main-health-monitor executor (Sentry monitor main-health-monitor)"
  configured_in: "apps/web-platform/vitest.config.ts (unit project include) + apps/web-platform/test/server/inngest/execution-placement.test.ts"

error_reporting:
  destination: "CI job log + GitHub check annotation (no runtime path exists, so no Sentry event)"
  fail_loud: "vitest failure naming the offending function id, the marker and the fix, e.g. `portable cron-oauth-probe reaches child_process via server/x.ts; re-class host-affine`"

failure_modes:
  - mode: "a new served function has no EXECUTION_PLACEMENT row"
    detection: "Guard 1 set-identity diff (missing ids listed with a paste-ready row stub)"
    alert_route: "red required `test` check on the PR"
  - mode: "a portable function (or an allowlisted definer export it uses) gains a host-local dependency"
    detection: "Guard 2 (default-deny definer allowlist + allowlisted-declaration scan + closure marker scan)"
    alert_route: "red required `test` check on the PR"
  - mode: "an Inngest-executed module names a substrate/host-state verifier workflow"
    detection: "Guard 3"
    alert_route: "red required `test` check on the PR"
  - mode: "the production serve URL moves off https://app.soleur.ai, or a second serve() registry appears"
    detection: "Guard 4 (AST, tighter than the regex of function-registry-count guard (g))"
    alert_route: "red required `test` check on the PR"
  - mode: "a guard silently checks nothing (vacuous)"
    detection: "own-dispatch rows: non-Identifier serve() array elements fail closed; route.ts array identifiers must equal the bindings route.ts imports from server/inngest/functions/*; every portable closure must reach at least one @/server module; the synthesized positive fixtures must fire"
    alert_route: "red required `test` check"
  - mode: "`app` fanned out to a second host (DNS half)"
    detection: "lb-weight-gate.test.sh Condition C, run by infra-validation.yml, which is path-filtered to infra/** changes (not a per-PR required check); the change it guards is itself an infra/** edit, so the filter fires exactly when needed"
    alert_route: "red infra-validation check on that infra PR"

logs:
  where: "GitHub Actions job logs for the `test` workflow run"
  retention: "90 days (GitHub Actions default)"

discoverability_test:
  command: grep -o -m1 "export const EXECUTION_PLACEMENT" apps/web-platform/server/inngest/execution-placement.ts
  expected_output: "export const EXECUTION_PLACEMENT"
```

## Guard Contract

All guards live in `apps/web-platform/test/server/inngest/execution-placement.test.ts`. Every row
below is an executed test case over an in-memory **synthesized** fixture. Fixtures use synthetic
ids and module names, never copies of real files (`cq-test-fixtures-synthesized-only`). They are
fed through the required `fs = { readFile, exists, listFiles, appRoot }` seam that Phase 0 adds.

Each guard helper is one pure function, and it is called identically by the real-tree test and the
fixture tests. The only difference is the `fs` passed in, so the two paths cannot diverge. No row
mutates a tracked file.

### Guard 1 — Placement manifest covers exactly the served set

**Property.** Every function served by the one `serve()` registry has exactly one
`EXECUTION_PLACEMENT` row, keyed by its Inngest function id and carrying a valid class and a
non-empty reason. Every row names a served function.

**Assembly.** The chokepoint is the `functions: [ … ]` array of the `serve()` call in
`app/api/inngest/route.ts`, the only registry (Guard 4 makes that true). The array is read by TS
AST, and every element must be an `Identifier`: a spread, call or other expression fails closed.

The resolution chain is:

1. each array identifier;
2. its import binding in route.ts;
3. the resolved module;
4. `export const <ident> = inngest.createFunction(<first arg>)`. The first argument is unwrapped
   through `AsExpression`, `SatisfiesExpression` and `ParenthesizedExpression`;
   `agent-on-spawn-requested.ts` wraps both of its configs in
   `as unknown as Parameters<typeof inngest.createFunction>[0]`.
5. The `id` property is read from that object literal. It is a string literal or a same-file
   `const X = "<literal>"`. Three such consts exist today: `REQUESTED_FUNCTION_ID`, `FN_ID` in
   `cron-gh-pages-cert-reissue.ts`, and `FUNCTION_NAME` in `cron-weekly-release-digest.ts`.

Anything unresolved is an offender, never a skip.

Independent cross-check: the array identifiers must equal the set of bindings route.ts imports
from `@/server/inngest/functions/*`.

`onFailure` handlers are not rows. The SDK registers them as `<id>-failure` functions, which
inherit their parent's class, and the leaf header says so.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture manifest lacks the row for served synthetic id `cron-alpha` (including the degenerate `{}` manifest) | RED (missing: cron-alpha, with a paste-ready row stub) |
| 2 | Add a row `cron-does-not-exist` | RED (stale row) |
| 3 | Own dispatch: fixture route.ts whose array contains `...extraFns` (a spread) | RED (non-Identifier element, fail-closed) |
| 4 | Own dispatch: fixture route.ts that imports `cronFoo` from `@/server/inngest/functions/cron-foo` but omits it from the array | RED (imported-bindings cross-check) |
| 5 | Second member: fixture serves two new functions and only the FIRST has a row | RED naming the second |
| 6 | Fixture changes one id to `id: makeId()` (non-literal) | RED ("use a string literal or a same-file const") |
| 7 | Set one row's placement to `"anywhere"` or its reason to `""` | RED |

**Harness rows:**

| # | Suite edit / input | Expected |
|---|---|---|
| H1 | Must-PASS non-canonical: the served set and the manifest listed in **different orders**, with ids containing digits (`oneshot-4217-x`) | PASS (set identity, order-free) |
| H2 | Must-PASS non-canonical: a fixture module defining TWO served functions, both configs wrapped `as unknown as Parameters<…>[0]`, one id via a same-file `const` (the `agent-on-spawn-requested.ts` shape), both with rows | PASS |

**Anchor.** The served set is not stored. It is derived at test time from route.ts and
cross-checked against route.ts's own imports. The existing guard (a) is a stored count (70), so it
is **not** an independent anchor, and guard (b) covers only `cron-*.ts` files. The honest anchor is
that removing a function from route.ts is a runtime change visible in review. For crons, it also
reds guard (b); for event functions, only the named assertions (a2) and (a3) cover it.

### Guard 2 — The portable boundary

**Property.** No function declared `portable` can reach a host-local dependency: a Claude spawn,
an ephemeral clone, the deploy lease, a child process, the workspaces volume path or env, or any
export of a pinning-definer module outside `PORTABLE_SAFE_SHARED_EXPORTS`, including through an
allowlisted export's own body.

**Assembly.** For each `portable` row, Guard 1's resolution gives the function's module. From that
module, the extracted TS-AST walker (`test/helpers/ts-import-graph.ts`) follows every non-type
static import, `export … from`, `require()` and `import()`. It fails closed on unresolved or
non-literal specifiers, and it runs with `elideTypeOnlySpecifiers`. The walk **descends through**
the two definer modules, `_cron-shared.ts` and `_cron-claude-eval-substrate.ts`, so their own
imports are scanned too; only the definers' own source text is exempt from the (ii) marker scan.
The helper returns `{ offenders, checkedCount, closureSizes }`, and the anti-vacuity floor lives
**inside** the helper: every checked closure must have more than 1 module and reach at least one
`@/server/*` module, otherwise it is an offender.

There are four chokepoints, and all four are checked:

- **(i) Every edge into a definer, from any module in the closure**, is judged by its named
  bindings, using the original name (`propertyName`) when aliased. Each individual `type`
  specifier on a mixed import is skipped.
  - A re-export `export { x } from "./_cron-shared"` counts as importing `x`.
  - A name outside the allowlist is an offender.
  - So is a namespace, default or `export *` import of a definer, or a `require()`/`import()` of
    one.
- **(ii) Every module in the closure, except the two definers' own source text**, is an offender if it:
  - imports `child_process` or `node:child_process` (static or dynamic);
  - contains a string literal starting with `/workspaces` or `/mnt/data`;
  - has a property access `process.env.WORKSPACES_ROOT` or `process.env.CRON_WORKSPACE_ROOT`.
- **(iii) Each allowlisted export's own declaration in its definer.** Its free identifiers are
  followed through same-file top-level declarations, transitively. It is an offender if the path
  reaches:
  - a non-allowlisted export of the definer;
  - a binding imported from `child_process`;
  - a `/workspaces` or `/mnt/data` literal;
  - a workspace env read.
  - An identifier bound to an import from another module is not followed here. Because the walk
    descends through the definers, that module is already scanned by (ii).
  - This runs once per allowlisted name, independent of which function uses it.
- **(iv) Type-only imports** are erased and skipped: whole-clause imports by the walker option,
  individual specifiers by (i).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `import { spawnClaudeEval } from "./_cron-claude-eval-substrate"` to a portable fixture | RED |
| 2 | Add `resolveCronWorkspaceRoot` to a portable fixture's `_cron-shared` import | RED (not allowlisted) |
| 3 | Own dispatch: the fixture resolver returns `null` ("bare package, skip") for every `@/` specifier, so the walk silently drops edges | RED via the in-helper floor (closure of size 1, no `@/server/*` reached) |
| 4 | Second member: two portable fixtures, the first clean, the second importing `child_process` through a helper two hops away | RED naming the second |
| 5 | Alias: `import { resolveCronWorkspaceRoot as r } from "./_cron-shared"` | RED (original name checked) |
| 6 | Allowlisted export imports a pinning helper: fixture `_cron-shared.ts`'s allowlisted `postSentryHeartbeat` calls `runGit()`, imported from `@/server/git-helper`, which imports `node:child_process` | RED via (ii), because the walk descends through the definer (test-design P0-3) |
| 7 | Namespace: `import * as shared from "./_cron-shared"`, and separately `await import("./_cron-shared")`, in a portable fixture | RED (both) |
| 8 | `await import("node:child_process")` in a helper that a portable fixture reaches | RED |
| 9 | A closure module reads `process.env.WORKSPACES_ROOT` | RED |
| 10 | Allowlisted-body pin: edit the fixture `_cron-shared.ts` so allowlisted `postSentryHeartbeat` calls a same-file helper that calls `resolveCronWorkspaceRoot()` | RED (chokepoint (iii), found transitively) |
| 11 | Re-export bypass: a helper does `export { resolveCronWorkspaceRoot } from "./_cron-shared"`, and a portable fixture imports it from the helper | RED |

**Harness rows:**

| # | Suite edit / input | Expected |
|---|---|---|
| H1 | Fixture manifest with **zero** `portable` rows | RED: the helper returns `checkedCount`; the real-tree test asserts `checkedCount === <number of portable rows> > 0`, and this fixture's `checkedCount === 0` trips the same assertion |
| H2 | Must-PASS non-canonical: a portable fixture importing `{ postSentryHeartbeat as beat, REPO_OWNER, type HandlerArgs }` from `_cron-shared`, and `import { type SpawnResult }` from the substrate | PASS |
| H3 | Must-PASS: a `host-affine` fixture importing `spawnClaudeEval` (over-pinning is not guarded) | PASS |

**Anchor.** There is no external anchor. A weakening needs a visible diff to
`PORTABLE_SAFE_SHARED_EXPORTS`, in the test file, or a row flip to `portable`, in the leaf. The
ADR-033 amendment declares either one an architecture change.

Accepted limitation: the guard proves consistency between the declared class and the code, not
the correctness of the allowlist. The ADR records what it cannot detect: process-local module
state, and private-IP HTTP calls.

### Guard 3 — Anti-circularity re-verification

**Property.** No Inngest-executed code can name, and therefore dispatch by filename, an
**external-only verifier**: a workflow whose own run is the only signal of the total loss of its
subject, where that subject is Inngest's scheduler or execution host or something they depend on.
Those workflows are every `WATCHDOG_DISPATCH_TABLE` workflow plus `HOST_STATE_VERIFIER_WORKFLOWS`.

Inngest-scheduled watchers whose subject's total loss is covered elsewhere are **sanctioned** and
deliberately not in the set. Today these are `cron-inngest-config-drift` → `inngest-config-drift.yml`
and `cron-inngest-cron-watchdog`; `scheduled-inngest-health` covers total loss.

**Assembly.** The forbidden set is built from two sources:

- `WATCHDOG_DISPATCH_TABLE.map(r => r.workflowFile)`, imported from the import-free
  `server/watchdog-dispatch-table.ts`, not copied;
- `HOST_STATE_VERIFIER_WORKFLOWS`, declared in the **test file**, so the stems never sit under
  `server/inngest/` and the guard cannot collide with its own list.

Entries are matched by **stem** (the basename minus `.yml`). The scanned set is the union of:

- **(i)** every non-test `.ts` and `.mjs` module under `apps/web-platform/server/inngest/`. The
  `.mjs` covers `cron-bash-allowlist-hook.mjs`, which is spawned by path as a Claude hook and also
  imported via `server/cron-filing-deny-marker.ts`. The directory scan makes coverage independent
  of whether the walker resolves the `.mjs` edge.
- **(ii)** the transitive closure of every served function, so a dispatch helper outside
  `server/inngest/` is covered.

The directory scan in (i) enumerates files with `fs.listFiles`, and the extension and test-file
filtering happens inside the helper.

The closure walk is fail-closed. It carries one **exact exemption**:

- `cron-ux-audit.ts` has 3 non-literal `await import(/* turbopackIgnore: true */ …)` calls:
  2 with `botFixturePath` and 1 with `botSigninPath` (test-design P0-1).
- The exemption is keyed by file and **per-argument-identifier count**, `{ botFixturePath: 2,
  botSigninPath: 1 }`, read from `recordDynamicImportArgs`, with a reason string.
- Any other non-literal import anywhere is still a problem.

Only string-literal nodes count: `StringLiteral`, `NoSubstitutionTemplateLiteral`, and template
head, middle and tail text. Comments are excluded by the AST. Every forbidden member must exist at
`.github/workflows/<file>`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A synthesized served dispatcher `cron-dispatch-x.ts` with `const WORKFLOW_FILE = "workspaces-luks-verify.yml"` | RED |
| 2 | Add a fixture helper `server/github/dispatch-luks.ts` containing `"workspaces-luks-verify"` and reached from a served fixture cron | RED (closure coverage outside `server/inngest/`) |
| 3 | Own dispatch: the forbidden set is empty (a fixture table `[]` plus an empty verifier list) | RED: the forbidden set must be non-empty and every member must resolve to an existing workflow file; the synthesized positive fixture (row 1) must fire |
| 4 | Second member: add a second row to a fixture `WATCHDOG_DISPATCH_TABLE` (workflow X) and a fixture cron naming X | RED (the set is derived from the table) |
| 5 | The verifier list names a workflow absent from the fixture repo's `.github/workflows/` (checked through `fs.exists` under the fixture `appRoot`) | RED (stale entry) |
| 6 | Exemption is exact: in the fixture `cron-ux-audit.ts`, (a) add a 3rd `import(botFixturePath)`, (b) swap one `botSigninPath` for `x`, which keeps the total at 3, or (c) add one `import(x)` in another file | RED (all three) |
| 7 | A `.mjs` fixture under `server/inngest/` naming a forbidden stem | RED |

**Harness rows:**

| # | Suite edit / input | Expected |
|---|---|---|
| H1 | Must-PASS non-canonical: a cron fixture with a `//` comment and a `/** */` block mentioning `workspaces-luks-verify` | PASS (comments excluded) |
| H2 | Must-PASS: a `*.test.ts` fixture under `server/inngest/`, listed by `fs.listFiles`, containing `"scheduled-inngest-health.yml"` | PASS (the helper filters test files; the fixture really lists the file, so this row is not vacuous) |

**Anchor.** The watchdog half of the forbidden set is anchored in `server/watchdog-dispatch-table.ts`,
whose rows `sentry-monitor-iac-parity.test.ts` independently validates (a non-empty `eligibility`
string per ADR-248). Removing a row there is an ADR-248 change, not a change to this guard.

Known limitations, recorded in the ADR:

- a name assembled across template parts, such as `` `workspaces-luks-${x}.yml` ``;
- a dispatch by **numeric workflow id**, where no filename appears at all;
- code loaded by a runtime-computed path: the exempted `cron-ux-audit.ts` imports
  `plugins/soleur/skills/ux-audit/scripts/bot-{fixture,signin}.ts` via
  `join(getPluginPath(), …)`, which is outside the walked closure.

### Guard 4 — Single step-executing host (serve-URL anchor)

**Property.** The production serve URL of the only `serve()` registry is exactly
`https://app.soleur.ai`. With Condition C pinning `app` to web-1, that makes every served function
execute on web-1.

This guard exists because Kieran's review showed that existing guard (g)'s regex
(`const SERVE_HOST … NODE_ENV === "production" … "https://app.soleur.ai"`, joined by `[\s\S]*`) is
satisfied by the literal appearing **anywhere later** in route.ts, a comment included. It is a
slimmed replacement for the cut "single registry" guard.

**Assembly.** The walk covers every non-test `.ts` and `.tsx` file under `apps/web-platform/app/`,
`apps/web-platform/server/` and `apps/web-platform/lib/`. Using the TS AST, it checks:

- **(i)** the set of modules that reach a `serve` adapter equals {`app/api/inngest/route.ts`}. A
  module reaches one by importing `serve` from any `inngest/<adapter>` specifier (aliased or
  not), or by importing the adapter module as a namespace, default or `require()` (value imports
  only; `import type` is ignored);
- **(ii)** in route.ts, `const SERVE_HOST` is a conditional whose `NODE_ENV === "production"`
  branch is the **string literal** `"https://app.soleur.ai"`;
- **(iii)** the `serve({ … })` call's `serveHost` property references `SERVE_HOST`.

It fails closed if any of the three is not found.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the production branch literal to `"https://worker.soleur.ai"`, while a comment still contains `https://app.soleur.ai` | RED (guard (g) would stay green) |
| 2 | Own dispatch: rename `SERVE_HOST` (declaration not found) | RED (fail-closed) |
| 3 | Second member: add a fixture `app/api/inngest-infra/route.ts` with `import { serve as s } from "inngest/express"` | RED |
| 4 | Replace `serveHost: SERVE_HOST` with `serveHost: process.env.X` | RED |
| 5 | Namespace bypass: `import * as i from "inngest/next"; i.serve(…)`, and separately `const { serve } = require("inngest/next")`, in a fixture module | RED (both) |

**Harness rows:**

| # | Suite edit / input | Expected |
|---|---|---|
| H1 | Must-PASS non-canonical: the production literal reached through a parenthesized conditional `(NODE_ENV === "production" ? "https://app.soleur.ai" : undefined)` | PASS |
| H2 | Must-PASS: a module with `import type { serve } from "inngest/next"` and a comment containing `serve(` | PASS (type-only import, and a comment) |

**Anchor.** The DNS half is outside this test: `lb-weight-gate.test.sh` Condition C, run by the
path-filtered `infra-validation.yml`. The serve literal is protected by this AST check plus the
existing (g), and a change to either shows as a diff to route.ts, the runtime file.

## Plan Review Revisions

Panel: `soleur:engineering:review:dhh-rails-reviewer`,
`soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer`, and `soleur:engineering:cto` (devex lens).
The Step 4.5 advisor consult was folded in as well.

**Applied (mechanical):**

- **R1 (Kieran P0):** the anti-circularity closure walk would never pass on the real tree
  (`cron-ux-audit.ts`, 3 non-literal imports). It now has an exact exemption with mutation row 6.
  The deepen pass corrected the count to 2 `botFixturePath` plus 1 `botSigninPath`.
- **R2 (Kieran P0):** Phase 0 injects the `{ readFile, exists, appRoot }` seam. Without it, no
  synthesized row could run.
- **R3 (Kieran P1):** Guard 1 unwraps `as` / `satisfies` / parenthesized configs, resolves all
  three const ids, fails closed on non-Identifier array elements, and cross-checks against the
  route.ts imports. The circular own-dispatch row is replaced.
- **R4 (Kieran P1-5):** Guard 2's own-dispatch row returns `"unresolved"`, and the anti-vacuity
  floor is "every portable closure has more than 1 module and reaches `@/server/*`". The false
  anchor claim is corrected.
- **R5 (Kieran P1-6 + advisor):** allowlisted-export body scan (chokepoint (iii)), with mutation
  row 10.
- **R6 (Kieran P2-8):** definer edges are judged from every closure module; `require`/`import()`
  of a definer is an offender, and `export … from` counts as an import (row 11).
- **R7 (Kieran P1-7):** guard (g)'s regex is satisfied by the literal anywhere later in route.ts,
  so Guard 4 checks the production `SERVE_HOST` literal by AST.
- **R8 (DHH + simplicity + CTO devex, all three):** the broad "single registry" guard is cut.
  - Its only unique value (a second `serve` import) folds into slim Guard 4.
  - The `new Inngest(` client-count check and its roots-list harness row are gone.
- **R9 (advisor + simplicity):** `PORTABLE_SAFE_SHARED_EXPORTS` and `HOST_STATE_VERIFIER_WORKFLOWS`
  move into the test file.
  - This dissolves the self-collision where the guard's own stem list sat under
    `server/inngest/`.
  - The leaf is now placement data only, and the "leaf imports nothing" row is dropped.
- **R10 (simplicity):** the guard helpers are inlined into the test file, which is their only
  consumer.
- **R11 (advisor):** the rows are generated from a discovery pass of the real walker (Phase 2), and
  `elideTypeOnlySpecifiers` avoids spurious pins.
- **R12 (advisor):** walker equivalence is shown by a reach-set `diff`, not only a pass count.
- **R13 (DHH + simplicity):** ADR-248's "trigger not fired" note is dropped. The ADR-033 amendment
  points to the test file instead of restating the guards.
- **R14 (CTO devex):** the checklist row is class-neutral and the count becomes "eight". Failure
  messages name the fix, and that is now an AC.
- **R15 (Kieran P2):**
  - `onFailure` inheritance rule;
  - numeric-workflow-id gap recorded;
  - checklist heading quoted with backticks;
  - Condition C described as path-filtered.
- **R16 (CTO devex P2):** sidecar consolidation and the re-audit of conservative pins are posted
  to #9137.

**Taste, kept as the CTO ruled, and persisted to `knowledge-base/project/specs/feat-one-shot-7230-inngest-execution-split/decision-challenges.md`:**

- **T1:** keep three classes rather than `portable`/`pinned` (DHH, simplicity).
- **T2:** key by function id rather than the route.ts identifier (simplicity).
- **T3:** keep the full mutation matrices rather than one RED plus one PASS row (DHH).
- **T4:** keep the ADR-030 pointer, the C4 edge edit and the registry-test comment (simplicity
  would cut them).
- **T5:** split `_cron-shared.ts` into pinned and generic modules (DHH). This is a runtime import
  change and is noted for #9137.

**Considered and rejected:** DHH P1-5 would have moved the manifest and Guards 1–2 wholesale into
#9137. That would drop the "mechanical, drift-guarded rule" #7230 asks for, which is
operator-requested scope. Keeping it follows the operator's direction.

## Acceptance Criteria

- [x] `apps/web-platform/server/inngest/execution-placement.ts` exists and has zero import
      declarations. It exports `EXECUTION_PLACEMENT`, keyed by function id, with one row per
      served function, each in one of `portable`, `host-affine` or `volume-bound` and each with a
      non-empty `reason`. It exports **only** the type and `EXECUTION_PLACEMENT`: the guard
      config lives in the test file.
- [x] `execution-placement.test.ts` implements Guards 1–4. Every mutation-matrix row and harness row
      in `## Guard Contract` is an executed test case: each RED row is asserted RED against a
      synthesized fixture, and each must-PASS row is asserted PASS.
- [x] At least one RED row per guard asserts that the failure message **names the fix**: a row
      stub, the re-class instruction, the #6808 pointer, or the serve-URL literal (CTO devex).
- [x] All four guards are green on the real tree.
      `./node_modules/.bin/vitest run test/server/inngest/execution-placement.test.ts` passes,
      with the portable and served counts printed in the test names or messages.
- [x] Walker extraction is equivalent: `watchdog-dispatch-clock.test.ts` passes (plan-time
      baseline on 9926a1e82c: **63 passed**), and the Phase-0 `diff` of the pre- and
      post-extraction `walk(CLOCK)` reach and problems sets is empty. The PR body records both.
- [x] `function-registry-count.test.ts` passes unchanged except for the one cross-reference comment.
- [x] The ADR-033 file
      `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` carries
      `## Amendment — 2026-09-28 (#7230): execution placement`. It includes the decision table,
      the three classes, a pointer to `execution-placement.test.ts` (not a restatement of the
      guards), Guard 4 plus (g) plus Condition C as the single-host enforcement, the re-open
      triggers (#9137), the four known gaps and the re-derived corollary table (citing #9138).
      Registration-checklist row 8 is present and the count reads **eight**.
- [x] The stale binding claim is gone from the ADR-033 file:
      `grep -c 'pinned to web-1 by the single \`sdk_url\` callback'` returns `0` (it is `1` on
      origin/main), and `grep -c '34 of 53'` returns `0`. The amendment explains the correction
      without re-quoting either phrase.
- [x] ADR-030 (`ADR-030-inngest-as-durable-trigger-layer.md`) has the log line. ADR-248's
      failure-domain row no longer says "via `sdk_url`", and its #7230 reversal trigger points to
      #9137. ADR-143's #8611 amendment has the placement line. ADR-100's sub-decision 1 carries
      the serve-URL note.
- [x] The `model.c4` `inngest -> api` edge names the single step-executing host, the placement
      rule and the registration-only role of `--sdk-url`. The three function-effect edges are
      sourced from `api`, and `grep -cE '^\s*inngest -> (supabase|github|doppler) '` on
      `model.c4` returns `0`. `model.likec4.json` is regenerated. The c4 syntax and render tests and `c4-count-parity.test.sh` pass.
- [x] `git diff --name-only origin/main...HEAD` lists **no** path under `apps/web-platform/infra/`,
      **no** path under `.github/workflows/`, and not `apps/web-platform/app/api/inngest/route.ts`.
- [ ] The PR body says `Closes #7230` and links #9137 and #9138. Its first line is the
      merge-consequence statement from `## Sharp Edges`.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruling adopted (c) now and rejected (b). Option (a) is demoted to a
fallback; the target is Phase-3 placement-aware execution (#9137). The ruling kept three classes
with CTO naming (`volume-bound`, `host-affine`, `portable`), used a central manifest leaf keyed by
function id, and inverted Guard 2 to a default-deny allowlist. It cut the TS duplicate of the DNS
assertion (Condition C already covers it) and kept the anti-circularity guard (now Guard 3) with
the watchdog set imported. It chose amend-not-create, with full filenames, plus ADR-248 and
ADR-143 one-liners. The luks-verify schedule reliability is out of scope (#9138). Complexity is
small, and the risk is low.

A second CTO pass at plan review (devex lens) found no drift from the ruling. Its P1s (a
class-neutral checklist row, failure messages that name the fix) are applied. It found the merge's
standard web-platform release acceptable under "no production writes".

No other domain is implicated. This is internal test, doc and architecture work with no product,
marketing, legal, finance, sales, support or operations surface. No UI file is in the Files lists,
so the Product/UX gate is NONE.

## Test Scenarios

- Given the real tree, when the suite runs, then Guards 1–4 pass and the portable-checked count
  equals the number of `portable` rows (> 0).
- Given each mutation-matrix row as a synthesized fixture, when its guard runs, then it reports
  RED with a message naming the offending id, module or workflow.
- Given each must-PASS harness row, when its guard runs, then it passes.
- Given the walker extraction, when `watchdog-dispatch-clock.test.ts` runs, then it passes, and
  the walker's reach and problems sets for the clock entry are identical to the pre-extraction
  sets.
- Given the real tree, when Guard 3 walks every served closure, then the only tolerated
  non-literal dynamic imports are the exempted `{ botFixturePath: 2, botSigninPath: 1 }` imports in
  `cron-ux-audit.ts`.
- Regression: given a future PR adding `cron-foo.ts` to route.ts without a manifest row, then CI
  is red at Guard 1, and the ADR-033 registration checklist names the fix.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Guard 2 flags a function the plan classed `portable` | Re-classify it to the tightest class its marker implies (over-pinning is safe). Never widen the allowlist to pass. |
| Walker extraction subtly changes the clock guard | A reach-set `diff` before and after is an AC, not just a pass count. Every new option (`elideTypeOnlySpecifiers`, `recordDynamicImportArgs`, the `fs` seam) defaults to today's behaviour. |
| The fail-closed walker cannot pass on the real tree | Measured at plan review: only `cron-ux-audit.ts`'s 3 dynamic imports (2 `botFixturePath` and 1 `botSigninPath`) are non-literal. Guard 3 exempts exactly those, and Guard 2 never walks them because that function is `host-affine`. |
| Guard false-positives slow future cron PRs | Failure messages name the exact fix (add a row, or re-class). The ADR-033 registration checklist gains the step. |
| The `inngest@4` upgrade (#8628) changes the SDK surface Guards 1 and 4 parse (`inngest/<adapter>` `serve`, `createFunction(config, …)`, `onFailure` → `-failure`) | Guard 1 and Guard 4 fail closed rather than silently passing, so the upgrade PR sees a red suite and updates the extractor. The SDK facts are pinned in `## Research Insights` against 3.54.2. |
| Two ADRs keep contradictory "via `sdk_url`" prose | Both are corrected in this PR, and an AC greps ADR-033. |
| Someone "fixes" #7230 later by repointing `sdk_url` | The ADR amendment states the binding explicitly, and Guard 4 plus Condition C trip on any real change. |

## Sharp Edges

- **Does merging THIS alone mutate production? Only through the ordinary release path.** The diff
  touches no path under `apply-web-platform-infra.yml` `on.push.paths`. But
  `web-platform-release.yml` fires on any push to main under `apps/web-platform/**`, **including
  `test/**`**, and its inner `check_changed` pathspec is `apps/web-platform/`. So merging cuts the
  standard release (tag, image, deploy) of a **behaviourally identical** image, because no
  runtime module imports the leaf. That is the same consequence as every web-platform PR. It is
  CI's release, not a production write performed by the pipeline agent, and no dispatch, apply or
  manual tag push is involved.
  - **PR-body first line (required):** "Merge consequence: the standard web-platform release
    (behaviourally identical image); no infra apply, no workflow change, no runtime behaviour
    change."
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  deepen-plan or `soleur:work`.
- **Do not touch `apps/web-platform/infra/**`**, not even a comment in `lb-weight-gate.test.sh`.
  The `apply-web-platform-infra.yml` `on.push.paths` glob `apps/web-platform/infra/**` turns any
  such merge into a production apply, which violates this PR's no-production-write constraint.
- `ADR-033-*` and `ADR-030-*` are ambiguous globs, with three and two files. Always use the full
  filename in edits, ACs and greps.
- The manifest is keyed by **function id**, not the route.ts identifier. Three ids are same-file
  const references (`REQUESTED_FUNCTION_ID`, `FN_ID`, `FUNCTION_NAME`). Both configs in
  `agent-on-spawn-requested.ts` are wrapped in `as unknown as …`. All must be resolved, not
  skipped.
- The SDK registers 72 functions, not 70, because two `onFailure` handlers become `*-failure`
  functions. Do not "fix" the manifest to 72; the leaf header states the inheritance rule.
- Do not add counts to `model.c4` prose. `c4-count-parity` gates the cardinalities embedded there.

## References

- Issue #7230; follow-ups #9137 and #9138; related #6808, #8495, #8611, #8691, #4882, #5159, #5182,
  #8595.
- ADR-030, ADR-033, ADR-100 (Decision 1 route-once; SEC-H3), ADR-119, ADR-143 (D2 and the #8611
  amendment), ADR-243 §2, ADR-248.
- `apps/web-platform/server/inngest/cron-manifest.ts`: the client-free leaf pattern.
- `apps/web-platform/infra/lb-weight-gate.test.sh` Condition C: the DNS half of single-host
  execution.
