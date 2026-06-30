---
title: "fix(concierge): gate dispatch self-heal on agent-context rev-parse + un-blind the readiness self-stop (#5733)"
type: fix
date: 2026-06-30
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5733
pr_link_keyword: Ref
---

# fix(concierge): gate dispatch self-heal on the agent's-own-context `git rev-parse`, not the lstat proxy (#5733)

## Overview

Concierge workspace `754ee124…` still strands `/soleur:go` on "not a git repository"
**after** the prior fix (commit `190ab58a5`, merged 2026-06-30 14:32 UTC, deployed
~15:00 UTC). That prior fix is on `main` and is **NOT re-shipped here**: it landed the
lstat-structural scaffolding in `git-worktree-validity.ts` (`probeGitWorktreeShape`,
`isReadyGitWorkTree`, `isStrandingFilePointer`), the `reportAgentReadinessSelfStop`
Sentry mirror (`repo-resolver-divergence.ts:128`), N-co-owner tolerance, and the
ADR-044 amendment.

This PR closes the gap those left. **The gap is a proxy-vs-invariant divergence:** all
three dispatch gates (cold `cc-dispatcher.ts`, warm `cc-reprovision.ts`, reconcile
`workspace-reconcile-on-push.ts`) decide readiness from the **cheap lstat proxy**
`isReadyGitWorkTree` (a `dir-valid` = `.git` dir with `HEAD`+`objects`, OR a
non-escaping file-pointer). For `754ee124`'s on-disk shape the lstat proxy returns
**ready** — so the heal is skipped **and** the `reportAgentReadinessSelfStop` mirror
(gated on `!gitReady`, COLD-only) stays **silent** — yet the agent's IN-BWRAP
`git rev-parse --is-inside-work-tree` (the agent's Bash runs under
`agent-runner-sandbox-config.ts:94` `denyRead:["/workspaces"]`) strands. The result is
the dark surface all prior fixes missed: a workspace the DB and the lstat probe both
call "ready" whose agent-context git signal says "no repository," with zero queryable
server event.

The durable fix has three deliverables (all server-side TypeScript under
`apps/web-platform/server`, **failing tests first**):

- **(A) Gate the self-heal on the agent's-own readiness verdict, not the lstat proxy** —
  a structural **UNION** `isStrandingFilePointer(shape) || !hostRevParse(workspacePath)`
  (host `git rev-parse --is-inside-work-tree` with `GIT_CEILING_DIRECTORIES` set to the
  workspace parent so host discovery matches the agent's sandbox jail). Swept across
  **all three** call sites per `hr-write-boundary-sentinel-sweep-all-write-sites`.
- **(B) Heal to a SELF-CONTAINED `.git` before `query()`** — only for the provably-safe
  shapes (escaping pointer, empty-corrupt); the populated-corrupt `dir-valid` is
  **observed-and-honest-blocked, never destroyed** (preserve the ADR-044 never-destroy
  invariant). No third `rm` authorization is added.
- **(C) Un-blind the observability** — fire `reportAgentReadinessSelfStop` on the
  rev-parse-invalid verdict (carry a new `gitRevParseValid` field alongside the
  existing lstat `gitValid`, so the event surfaces the proxy-vs-invariant divergence)
  from **whichever of the three gates executes**, including the benign-skip branch.

PR body uses **Ref #5733** (not `Closes`): operator-surface reproduction on `754ee124`
is post-merge verification per the ops-remediation `Ref`-not-`Closes` convention.

## Problem Statement / Motivation

`/soleur:go` Step 0.0 runs the authoritative `git rev-parse --is-inside-work-tree`
**inside** the agent's bwrap sandbox, where only `workspacePath` is mounted and the
`/workspaces` parent is `denyRead` (learning
`2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`). The server-side
dispatch gates decide whether to self-heal **before** that — but they decide from a
cheap lstat structural probe (ADR-044's 2026-06-19 amendment chose it as "deliberately
WEAKER than `git rev-parse --is-inside-work-tree` but cheap enough to keep the AC7
zero-await hot path"). The proxy and the invariant **diverge** on `754ee124`: lstat
says ready, the agent's rev-parse strands. Because the gate keys on the proxy, both the
heal and the self-stop emit are silent.

This is the recurring "the fixed code path the affected surface never executes" failure:
the prior session shipped two `cc-dispatcher` fixes the operator's surface never ran
(zero `cc-dispatcher` Sentry events while the real path was the Inngest
`workspace-reconcile-on-push` function firing 26×) — learning
`2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`.
The fix therefore (a) sweeps **all three** gates and (b) makes the self-stop fire from
**all three**, so whichever path `754ee124` traverses, it heals (or honest-blocks) and
emits.

## Proposed Solution

Introduce one injected readiness verdict — `agentReadyGitWorkTree(workspacePath)` — that
returns the **agent-equivalent** answer the in-bwrap rev-parse would give, computed as a
structural UNION:

```
ready  ⇔  NOT isStrandingFilePointer(probeGitWorktreeShape(ws))   // escaping pointer fails in-sandbox
          AND hostRevParse(ws) === ok                              // corruption fails host-side too
```

- The **escaping pointer** is host-readable but `denyRead` in-sandbox → a plain host
  rev-parse would false-pass, so `isStrandingFilePointer` (already on `main`) covers it
  structurally.
- **Genuine corruption** (broken HEAD/index/objects, `dir-invalid`) fails rev-parse
  host-side too (sandbox-independent) → the host `git rev-parse` covers it.
- `hostRevParse` MUST run `git -C <workspacePath> rev-parse --is-inside-work-tree` with
  `GIT_CEILING_DIRECTORIES=<dirname(workspacePath)>` so host discovery cannot ascend to
  a parent `.git` and spuriously report inside-work-tree=true (the agent's sandbox is
  jailed to `workspacePath`; the host probe must replicate that jail).

The verdict drives **both** the heal-routing decision **and** the self-stop emit
(`gitRevParseValid = verdict`). lstat `isReadyGitWorkTree` is retained as the cheap
**pre-filter**: the rev-parse subprocess runs **only** when lstat says ready AND the
workspace is connected (`repoUrl`) + DB-ready — exactly the population where a false-ready
silently strands. Not-connected / repo-less / lstat-not-ready paths skip the subprocess
(lstat already routes them).

The probe is an **injected seam** (mirroring the existing `gitDirValid` /
`ensureWorkspaceRepoCloned` seams at `cc-dispatcher.ts:1877/:1886`) so the three gates
are unit-testable without spawning real git.

## Research Reconciliation — Brief vs. Codebase

| Brief framing (pre-investigation) | Codebase reality (verified this session) | Plan response |
|---|---|---|
| "The prior fix gated the heal on lstat; add the rev-parse gate." | `probeGitWorktreeShape` + `isReadyGitWorkTree` + `reportAgentReadinessSelfStop` are **already wired** at cold `cc-dispatcher:1807-1838`, warm `cc-reprovision:123`, reconcile `workspace-reconcile-on-push:357`. The delta is **swapping the lstat proxy for the agent-equivalent verdict**, not adding the scaffolding. | Deliverable A is a gate-predicate swap + seam injection across 3 sites, not a greenfield build. |
| "Emit the self-stop read in the agent's OWN bwrap context (reuse the dispatch readiness-gate result)." | The self-stop already exists and already pseudonymizes (`userIdHash` boundary rename, `activeWorkspaceIdHash` pre-hash, no `installationId`/`repoUrl`/raw `gitdirTarget`). It fires only from COLD on `!gitReady` (lstat). | Deliverable C: fire on the rev-parse verdict; add `gitRevParseValid`; emit from **all three** gates (WARM + RECONCILE currently dark). Privacy bar is already met — reuse the existing pseudonymization. |
| "Run rev-parse in the agent's own bwrap context." | CTO Q3: the ONLY host/in-sandbox divergence for `--is-inside-work-tree` is the escaping pointer, already caught structurally by `isStrandingFilePointer`. Reproducing the bwrap mount adds machinery + a silent-drift coupling to `agent-runner-sandbox-config.ts`. | **Refine the mechanism** to the structural UNION (host rev-parse + `GIT_CEILING_DIRECTORIES` + `isStrandingFilePointer`). Equivalent detection, cheaper, no sandbox-config coupling. Documented as a deliberate refinement of the brief. |
| "Clone a self-contained `.git` so the strand auto-heals." | CTO Q1 + ADR-044 2026-06-19: a **populated-corrupt** `dir-valid` routed into `ensureWorkspaceRepoCloned` **no-ops** (early-returns `"ok"` at `ensure-workspace-repo.ts:207` because `isValidGitWorkTree` passes). Destroying a populated `.git` would violate the never-destroy-unpushed-commits invariant. | Heal only provably-safe shapes (escaping pointer `:174`, empty-corrupt `:236`). Populated-corrupt = **observed-and-honest-blocked** (no spawn), explicitly **unhealed-by-design**. |
| H2 confirmed; shape is "file-pointer, escaping gitdir, or invalid HEAD/objects." | spec-flow P0: the **exact** shape of `754ee124` is unconfirmed (the observability that would tell us is the thing being fixed). If it is a corrupt-dir (not an escaping pointer), a COLD-only verification is a **false green**. | Verification MUST assert the actual on-disk shape FIRST, then exercise the path the strand traverses (RECONCILE/WARM per the 26× incident), not only a fresh COLD dispatch. |

## Technical Considerations

- **Architecture impact:** reverses ADR-044's 2026-06-19 "zero-await hot path" trade-off
  for the connected+ready case → **ADR-044 amendment is an in-scope deliverable** (see
  Architecture Decision section). No C4 impact (pre-condition tightening on the existing
  `api -> claude "Spawns agent sessions"` edge).
- **Performance:** one `git rev-parse` (~10–50ms) only on the lstat-ready + connected
  transition. Negligible vs. agent spawn / bwrap setup / model latency. WARM path
  **memoizes** a positive verdict per-workspace-per-process (the strand is a persistent
  on-disk shape, not a per-turn transient); invalidate on shape-change/disconnect so
  steady-state warm turns pay lstat only.
- **Security / privacy:** the self-stop event already pseudonymizes; the new
  `gitRevParseValid` is a boolean (non-PII). No `installationId`/`repoUrl`/raw
  `gitdirTarget` is added.
- **NFR:** assess hot-path latency + observability-coverage NFRs
  (`knowledge-base/engineering/architecture/nfr-register.md`).

### Attack Surface Enumeration (destroy-boundary — the `rm` sweep)

Per `hr-write-boundary-sentinel-sweep-all-write-sites`, every `.git` write/destroy site:

- `ensure-workspace-repo.ts:174` — `rm(.git, {force})` (single FILE, non-recursive) —
  authorized ONLY by `isStrandingFilePointer` (a stale pointer file; nothing to lose).
- `ensure-workspace-repo.ts:236` — `rm(.git, {recursive, force})` — authorized ONLY by
  the positive `isEmptyCorruptGitDir` fingerprint (HEAD+objects both ENOENT; no commits).
- `ensure-workspace-repo.ts:352` — `rename(tmp/.git, ws/.git)` — the all-or-nothing
  clone success sentinel (self-contained `.git`).
- `ensure-workspace-repo.ts:354` — `rm(tmp, {recursive})` — temp cleanup.

**AC:** this PR adds **NO third `rm` authorization**. The rev-parse verdict drives the
GATE and the OBSERVABILITY only; destroy authorization stays the two existing positive
fingerprints. A populated-corrupt `dir-valid` is honest-blocked, never `rm`'d.

## User-Brand Impact

- **If this lands broken, the user experiences:** `/soleur:go` dead-ends with
  "No Git Repository in Workspace" / agent self-stop ("not a git repository") on a
  workspace the dashboard shows as connected+ready — the Concierge is unusable for that
  user, with no error the operator can see or act on.
- **If this leaks, the user's data/workflow is exposed via:** N/A — the change reduces
  exposure (the self-stop event pseudonymizes userId and omits installationId/repoUrl);
  the only new field is a boolean.
- **Brand-survival threshold:** `single-user incident` — one stranded workspace
  (the operator's own, `754ee124`) renders the product's headline surface dead. A
  false-heal that destroyed a populated `.git` would additionally lose un-pushed
  prior-turn work (the destroy-boundary the plan protects).

CPO sign-off required at plan time before `/work` (`requires_cpo_signoff: true`);
`user-impact-reviewer` runs at review-time (enumerate the strand-without-signal mode AND
the un-pushed-work-loss mode Q1 protects). Deepen-plan triad (architecture-strategist +
data-integrity-guardian + security-sentinel) is mandated at this threshold.

## Observability

```yaml
liveness_signal:
  what: "Sentry event `agent_readiness_self_stop` (own issue group) — fires server-side the moment any of the 3 dispatch gates computes a rev-parse-invalid verdict for a connected+DB-ready workspace"
  cadence: "per dispatch/reconcile that hits a rev-parse-invalid workspace (process-local fingerprint dedupe by op:userId:workspace:gitKind)"
  alert_target: "Sentry issue (query-only / discoverability — NO sentry_issue_alert page, by design: the safe shapes auto-heal same-dispatch)"
  configured_in: "apps/web-platform/server/repo-resolver-divergence.ts:128 (reportAgentReadinessSelfStop); emitted from cc-dispatcher.ts (cold), cc-reprovision.ts (warm), inngest/functions/workspace-reconcile-on-push.ts (reconcile)"
error_reporting:
  destination: "Sentry web-platform (EU) via reportSilentFallback -> captureException"
  fail_loud: "the agent_readiness_self_stop event (gitRevParseValid:false) appears in Sentry; for the honest-block populated-corrupt case the user also gets a RepoNotReadyError message instead of a silent agent self-stop"
failure_modes:
  - mode: "connected+ready workspace whose agent-context rev-parse fails (escaping pointer / corrupt dir / in-workspace denyRead'd pointer)"
    detection: "agent_readiness_self_stop event with gitRevParseValid:false + gitKind (queryable; not operator-eyeball)"
    alert_route: "Sentry discoverability query (the jq-count post-deploy check)"
  - mode: "WARM/RECONCILE benign-skip no-op-heal (ensureWorkspaceRepoCloned returns ok without healing — e.g. repoUrl fails the https allowlist)"
    detection: "post-heal re-probe fails -> agent_readiness_self_stop fires on the warm + reconcile gates (previously only an audit row / decorative breadcrumb)"
    alert_route: "Sentry issue group agent_readiness_self_stop"
  - mode: "rev-parse probe subprocess spawn-failure / timeout"
    detection: "reportSilentFallback op rev-parse-probe-error; verdict fails CLOSED (treat as not-ready -> heal/honest-block), bounded retry, never fail-open into a spawn"
    alert_route: "Sentry issue group (reuses reportSilentFallback)"
logs:
  where: "Sentry (captureException) + pino server logs (reportSilentFallback mirrors both)"
  retention: "Sentry project retention (EU web-platform)"
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" 'https://sentry.io/api/0/projects/<org>/<web-platform>/events/?query=agent_readiness_self_stop' | jq 'length'"
  expected_output: "0 for a healthy fleet; >=1 (with gitRevParseValid:false + gitKind) whenever a connected workspace is stranding — the signal that was previously dark"
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-044** (`knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`) —
new `## Amendment 2026-06-30 — dispatch readiness gates on the agent's-own-context rev-parse verdict (supersedes the 2026-06-19 lstat-proxy trade-off for connected+ready)`.
Record the new shape via `/soleur:architecture`:
- lstat `isReadyGitWorkTree` retained as the cheap **pre-filter** / repo-less fast path;
- on the **lstat-ready + connected + DB-ready** transition, readiness keys on the
  agent-equivalent UNION verdict (`isStrandingFilePointer || !hostRevParse` with
  `GIT_CEILING_DIRECTORIES`); the 2026-06-19 "zero-await hot path" claim is narrowed to
  the not-connected / lstat-not-ready common case;
- destroy authorization is **unchanged** (the two positive fingerprints); populated-corrupt
  is observed-and-honest-blocked;
- WARM memoizes the positive verdict per-process;
- the `agent_readiness_self_stop` self-stop now fires from all three gates.
- **Sequencing:** the decision is true on merge (no soak gate) — status `accepted`.

### C4 views

**No C4 impact.** Verified against all three `.c4` files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Checked
enumeration: external human actors — none added (no new correspondent/recipient); external
systems/vendors — none added (GitHub clone edge unchanged); containers/data-stores — none
added; access relationships — unchanged. The fix tightens the **pre-condition** on the
existing `api -> claude "Spawns agent sessions"` edge (`model.c4:249`), internal to the
`api` and `claude` containers — the same "no C4 impact" class as ADR-044's prior
amendments (2026-06-17b / 2026-06-18). Run `apps/web-platform/test/c4-code-syntax.test.ts`
+ `c4-render.test.ts` only if a `.c4` edit is made (none expected).

## Domain Review

**Domains relevant:** Engineering (CTO). Product/UX: NONE (no UI surface — all changes
under `apps/web-platform/server/`; mechanical UI-surface override did not fire — no
`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). Legal/Finance/Marketing/Sales/
Ops/Support: not relevant (server-side reliability/observability fix).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Verified all load-bearing facts against code. (Q1 destroy-boundary —
HIGH) rev-parse drives the gate + observability but **must not** widen destroy
authorization; "origin = canonical" is false for the working tree (un-pushed prior-turn
commits may be the only copy); heal only provably-safe shapes, emit-and-honest-block the
populated-corrupt dir; note the trap that routing populated-corrupt into
`ensureWorkspaceRepoCloned` **no-ops** (`:207` early-return) so its value is observability,
not auto-heal. (Q2 hot-path — MED) acceptable; lstat pre-filter + warm per-process
memoization; cold/reconcile add freely. (Q3 mechanism — MED) **prefer the structural
UNION over bwrap-reproduction** (equivalent signal, no `agent-runner-sandbox-config.ts`
drift coupling); the host probe **must** set `GIT_CEILING_DIRECTORIES` or it false-passes
on a parent `.git`. Flags: ADR-044 amendment is a deliverable; write-boundary sweep
(`rm` at `:174`/`:236`, add no third); probe must be an **injected seam** (else the
failing-tests-first deliverable can't unit-test the gates); `user-impact-reviewer` +
`observability-coverage-reviewer` apply at review-time. Known-residual (out of scope):
a `dir-valid` `.git` with `objects/info/alternates` pointing under `/workspaces` passes
rev-parse both sides but strands on object access — not a rev-parse strand; flag, don't
claim #5733 closes it.

### SpecFlow (control-flow completeness)

**Status:** reviewed — gaps folded into Acceptance Criteria / Test Scenarios.
- **P0** shape-uncertainty: the proxy catches only the escaping-pointer shape; verification
  must assert `754ee124`'s actual on-disk shape first, then exercise the strand's real
  path (RECONCILE/WARM), not only COLD (false-green risk).
- **P0** WARM + RECONCILE are observability-dark (self-stop is COLD-only) and have
  benign-skip no-op-heal dead-ends that spawn/leave the strand with zero signal → wire the
  self-stop into all three including the benign-skip branch.
- **P0** WARM spawns regardless of heal result → re-probe readiness post-heal and fail
  honestly (no spawn into a still-invalid tree).
- **P1** probe-error must be fail-closed-to-heal-with-honest-block + bounded retry.
- **P1** WARM ignores `repo_status` (mid-`cloning` race) → confirm `claim_repo_clone_lock`
  serializes; surface `RepoNotReadyError` if it loses the race.
- **P2** repo-less Start-Fresh (`git init`, no origin, absent `.git`) must benign-skip,
  never clobber un-pushed init state.

**Brainstorm-recommended specialists:** none (one-shot path, no brainstorm).
**Agents invoked:** cto, spec-flow-analyzer.
**Skipped specialists:** none.

## GDPR / Compliance

Considered (single-user-incident threshold trigger (b)). No regulated-data schema/auth/API
surface is touched. The only telemetry change adds a boolean (`gitRevParseValid`) to an
event that **already** pseudonymizes (`userIdHash` boundary rename, `activeWorkspaceIdHash`
pre-hash) and omits `installationId`/`repoUrl`/raw `gitdirTarget`. **Constraint (AC):** the
new field MUST reuse the existing pseudonymization boundary and add no raw identifier. No
`/soleur:gdpr-gate` critical finding expected; advisory-only.

## Infrastructure (IaC)

Skip — no new infrastructure. Pure code change against the already-provisioned
`apps/web-platform/server` surface (no new server, secret, vendor, cron, or persistent
runtime process).

## Implementation Phases

### Phase 0 — Preconditions (read-only; verify before any edit)
- Read the three gates + the seams; confirm anchors: `cc-dispatcher.ts:1807-1838`
  (cold emit+gate), `:1877/:1886` (seam injection point), `:1963`→`:2326`
  (await `ensureWorkspaceRepoCloned` before `sdkQuery`); `cc-reprovision.ts:123`;
  `workspace-reconcile-on-push.ts:357`.
- Confirm `git rev-parse --is-inside-work-tree` exit semantics + that
  `GIT_CEILING_DIRECTORIES=<parent>` stops parent-`.git` ascent (test locally on a fixture:
  a `.git`-less dir nested under a real repo must report NOT-inside with the ceiling set).
- Confirm `claim_repo_clone_lock` serializes the WARM mid-`cloning` race (P1).
- `git grep` all consumers of `reportAgentReadinessSelfStop` args (type-widening sweep,
  `hr-type-widening-cross-consumer-grep`): `cc-dispatcher.ts:1822`,
  `test/server/repo-resolver-divergence.test.ts:198-219`.

### Phase 1 — Failing tests first (RED)
- `test/server/git-worktree-validity.test.ts` (or a new sibling): `agentReadyGitWorkTree`
  / `hostRevParse` seam returns the UNION verdict for each shape: escaping pointer →
  not-ready; non-escaping in-workspace pointer + valid dir → ready; `dir-invalid` →
  not-ready; populated-corrupt `dir-valid` (HEAD+objects present, rev-parse fails) →
  not-ready; probe-error → fail-closed not-ready. Assert `GIT_CEILING_DIRECTORIES`
  prevents parent-`.git` false-pass.
- `test/cc-dispatcher-self-heal-observability.test.ts` + `test/helpers/cc-dispatcher-harness.ts`:
  cold path fires `agent_readiness_self_stop` with `gitRevParseValid:false` when the
  injected probe says not-ready though lstat says ready; populated-corrupt → emit +
  honest-block (no spawn, no `rm`).
- `test/cc-reprovision-git-discriminator.test.ts`: WARM re-probes post-heal, fails
  honestly + emits the self-stop on a benign-skip no-op-heal (P0); memoized positive
  verdict skips the subprocess on steady-state turns.
- New `test/server/workspace-reconcile-self-stop.test.ts`: RECONCILE emits the self-stop
  (incl. benign-skip branch), not just an audit row / decorative breadcrumb.
- Destroy-boundary test: populated-corrupt `dir-valid` is NEVER `rm`'d (assert no call to
  the `:236` recursive rm; honest-block instead).

### Phase 2 — Implement the agent-equivalent verdict + seam (GREEN, deliverable A)
- Add `agentReadyGitWorkTree(workspacePath)` / `hostRevParse` to `git-worktree-validity.ts`
  (UNION; `GIT_CEILING_DIRECTORIES`; fail-closed; bounded retry). Export as an injectable
  seam.
- Cold `cc-dispatcher.ts`: run the verdict only when lstat-ready + `repoUrl` + DB-ready;
  feed it to `gitReady`/`needsSelfHeal` and the seam at `:1886`.
- Warm `cc-reprovision.ts`: lstat pre-filter → verdict (memoized) → route to heal; re-probe
  post-heal; honest-fail if still not ready (no spawn-regardless).
- Reconcile `workspace-reconcile-on-push.ts`: verdict (connected-gated, unconditional
  subprocess — background).

### Phase 3 — Heal-routing + honest-block (GREEN, deliverable B)
- Ensure provably-safe shapes route into `ensureWorkspaceRepoCloned` (escaping pointer
  already unlinks+reclones); populated-corrupt routes to honest-block (`RepoNotReadyError`),
  NOT to the no-op clone. Assert the await-before-`query()` ordering structurally
  (`ensureWorkspaceRepoCloned` at `:1963` precedes `sdkQuery` at `:2326`). Add **no** new
  `rm`.

### Phase 4 — Un-blind observability (GREEN, deliverable C)
- Widen `reportAgentReadinessSelfStop` args with `gitRevParseValid` (keep lstat `gitValid`
  for divergence visibility); fire on `!gitRevParseValid` from all three gates incl.
  benign-skip. Update the cross-consumer call sites + tests from the Phase 0 sweep.

### Phase 5 — ADR-044 amendment + verify
- Amend ADR-044 via `/soleur:architecture` (section above). No `.c4` edit.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; run the package vitest
  (`./node_modules/.bin/vitest run test/server/... test/cc-...`).

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Run `git rev-parse` inside a bwrap mount reproducing `denyRead:["/workspaces"]` | CTO Q3: the only host/in-sandbox divergence is the escaping pointer, already caught by `isStrandingFilePointer`; bwrap adds namespace-setup cost + a silent-drift coupling to `agent-runner-sandbox-config.ts`. UNION is equivalent + cheaper. |
| Plain host `git rev-parse` without `isStrandingFilePointer` | Host can read the escaping pointer → false-pass → the dominant live shape stays dark. |
| Plain host `git rev-parse` without `GIT_CEILING_DIRECTORIES` | Host ascends to a parent `.git` → spurious inside-work-tree=true → strand stays dark. |
| Destructively re-clone any rev-parse-invalid `.git` (incl. populated-corrupt) | Violates ADR-044 never-destroy-unpushed-commits invariant; an in-sandbox-only failure on a populated dir is a mount artifact, not corruption (CTO Q1). |
| Flip `gitValid` lstat→rev-parse (drop the lstat field) | Keeping both surfaces the exact proxy-vs-invariant divergence in one event — strictly more diagnostic. |
| COLD-only self-stop + COLD-only verification | spec-flow P0: the live surface fired 26× on RECONCILE; COLD-only is a false-green. |

## Acceptance Criteria

### Functional Requirements (pre-merge)
- [ ] `agentReadyGitWorkTree` returns the UNION verdict (`!isStrandingFilePointer && hostRevParse-ok`) for all shapes; `hostRevParse` sets `GIT_CEILING_DIRECTORIES=<parent>` (test proves a nested `.git`-less dir under a parent repo reports NOT-inside). `git-worktree-validity.ts`.
- [ ] All three gates (`cc-dispatcher.ts` cold, `cc-reprovision.ts:123` warm, `workspace-reconcile-on-push.ts:357` reconcile) decide heal-routing on the verdict via an **injected seam**, with lstat as the connected+ready pre-filter. (`hr-write-boundary-sentinel-sweep-all-write-sites`.)
- [ ] WARM re-probes readiness AFTER `ensureWorkspaceRepoCloned` and fails honestly (no spawn into a still-invalid tree); positive verdict memoized per-workspace-per-process, invalidated on shape-change/disconnect.
- [ ] `reportAgentReadinessSelfStop` fires on `!gitRevParseValid` from all three gates **including the benign-skip no-op-heal branch**; event carries `gitRevParseValid` + lstat `gitValid` + `gitKind` + `activeWorkspaceIdHash`; NO `installationId`/`repoUrl`/raw `gitdirTarget`; `userId`→`userIdHash` at the boundary. Cross-consumer type-widening sweep complete.
- [ ] Populated-corrupt `dir-valid` is observed-and-honest-blocked (`RepoNotReadyError`), NEVER `rm`'d; provably-safe shapes (escaping pointer, empty-corrupt) heal to a self-contained `.git` awaited before `sdkQuery()`. **No third `rm` authorization** added (sweep: `:174`, `:236` only).
- [ ] Probe error (spawn-fail/timeout) is fail-closed-to-heal-with-honest-block + bounded retry; never fail-open into a spawn.
- [ ] ADR-044 amended (2026-06-30 section); no `.c4` edit. `tsc --noEmit` clean; package vitest green.

### Non-Functional Requirements
- [ ] rev-parse subprocess runs only on the lstat-ready + connected transition; WARM steady-state pays lstat only (memoization). NFR-register latency assessment noted.
- [ ] Self-stop event is query-only (no `sentry_issue_alert`), pseudonymized.

### Post-merge (operator / automatable — `Ref #5733`, NOT `Closes`)
- [ ] **Assert the on-disk shape FIRST:** determine `754ee124`'s actual `.git` shape (escaping pointer vs corrupt dir vs in-workspace pointer) — read it before declaring success (spec-flow P0; avoids false-green).
- [ ] Dispatch `/soleur:go` on `754ee124` and confirm no strand on the path the live surface traverses (RECONCILE/WARM per the 26× incident — not only a fresh COLD dispatch).
- [ ] Confirm `agent_readiness_self_stop` (with `gitRevParseValid:false` + `gitKind`) is queryable in Sentry for a synthetic/known strand — proving the previously-dark surface now emits. Then `gh issue close 5733`.

## Test Scenarios

### Regression (the bug)
- Given a connected+DB-ready workspace whose lstat shape is `dir-valid`/non-escaping-pointer but whose agent-context rev-parse strands, when a COLD/WARM/RECONCILE dispatch occurs, then the verdict is not-ready → heal (safe shape) or honest-block (populated-corrupt) AND `agent_readiness_self_stop` fires with `gitRevParseValid:false`.

### Edge cases
- Given a repo-less Start-Fresh workspace (`git init`, no origin, no `repoUrl`), when dispatched, then verdict skips the subprocess (not connected), no self-stop, no clobber of un-pushed init state (P2).
- Given a workspace mid-`cloning`, when a WARM dispatch arrives, then `claim_repo_clone_lock` serializes; no double-clone; `RepoNotReadyError` if the race is lost (P1).
- Given an in-workspace pointer under a `denyRead`'d subpath, when dispatched, then host rev-parse strands → verdict not-ready (the proxy alone would false-skip; P1).
- Given the probe subprocess fails/times out, when dispatched, then fail-closed-to-heal-with-honest-block, bounded retry, never fail-open.

### Integration verification (`/soleur:qa`, post-merge)
- **Sentry query:** `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" 'https://sentry.io/api/0/projects/<org>/<web-platform>/events/?query=agent_readiness_self_stop' | jq 'length'` — expect `>=1` on a known strand, `0` on a healthy fleet.

## Open Code-Review Overlap

3 open code-review issues touch the edited files — dispositions:
- **#3243** (`arch: decompose cc-dispatcher.ts into focused modules`) — **Acknowledge.** Different concern (module decomposition); this PR makes a minimal predicate-swap + seam-injection in place. Folding the decomposition in would balloon scope on a brand-survival fix. Remains open.
- **#3739** (`extract reportSilentFallbackWithUser helper — collapse 11-site duplication`) — **Acknowledge.** The new self-stop emits route through the existing `reportSilentFallback`/`reportAgentReadinessSelfStop` (already pseudonymizing); use the current pattern. The helper-extraction refactor is orthogonal. Remains open.
- **#3242** (`tool_use WS event lacks raw name field`) — not in scope (different surface).

### Sibling PR merge-ordering (#5783)
PR #5783 (OPEN, `closes #5591`) edits `apps/web-platform/server/observability.ts` (+7,
documenting multi-owner reconcile ops) and carries learning
`2026-06-30-sentry-op-inventory-docstring-drifts-when-sibling-op-added.md`. **This PR's
emit lives in `repo-resolver-divergence.ts` (`reportAgentReadinessSelfStop`), NOT
`observability.ts`** — so no hard conflict is expected. The `agent-readiness-self-stop`
op slug already exists on `main` (added by `190ab58a5`), so no new op-inventory entry is
required. **Guidance:** do NOT add an op-inventory entry to `observability.ts` in this PR;
if review insists on documenting the firing change there, rebase after #5783 merges to
inherit its inventory block and avoid the docstring drift the sibling learning describes.

## Files to Edit

- `apps/web-platform/server/git-worktree-validity.ts` — add `agentReadyGitWorkTree` / `hostRevParse` UNION seam (`GIT_CEILING_DIRECTORIES`, fail-closed, bounded retry).
- `apps/web-platform/server/cc-dispatcher.ts` — cold gate (`:1807-1838`) + seam (`:1886`): verdict-driven `gitReady`/`needsSelfHeal`; emit `gitRevParseValid`.
- `apps/web-platform/server/cc-reprovision.ts` — warm gate (`:123`): verdict + memoization + post-heal re-probe + honest-fail + self-stop emit.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — reconcile gate (`:357`): verdict + self-stop emit (incl. benign-skip).
- `apps/web-platform/server/repo-resolver-divergence.ts` — `reportAgentReadinessSelfStop` (`:128`): add `gitRevParseValid` field (keep lstat `gitValid`).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — Amendment 2026-06-30.
- (Verify, likely no change) `apps/web-platform/server/ensure-workspace-repo.ts` — confirm populated-corrupt honest-blocks; no new `rm`.

## Files to Create

- `apps/web-platform/test/server/workspace-reconcile-self-stop.test.ts` — RECONCILE self-stop incl. benign-skip.
- (Extend, not create) `test/server/git-worktree-validity.test.ts`, `test/cc-dispatcher-self-heal-observability.test.ts`, `test/helpers/cc-dispatcher-harness.ts`, `test/cc-reprovision-git-discriminator.test.ts`, `test/server/repo-resolver-divergence.test.ts`.

## Dependencies & Risks

- **Wrong-layer risk (P0):** if `754ee124`'s shape is a corrupt-dir not an escaping pointer, only the rev-parse arm (not `isStrandingFilePointer`) catches it — the UNION covers both, but verification MUST assert the shape + exercise the real path (RECONCILE/WARM) or risk a false-green (`2026-06-30-verify-the-fixed-code-path-actually-executes...`).
- **Proxy-vs-invariant (the core bug):** never re-introduce a verification/gate that asserts the lstat proxy in place of the rev-parse invariant (`2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`).
- **Known-residual (out of scope):** a `dir-valid` `.git` with `objects/info/alternates` escaping under `/workspaces` passes rev-parse both sides but strands on object access — flag in the ADR; #5733 does not close it.
- **Hot-path latency:** mitigated by lstat pre-filter + warm memoization; assert no subprocess on the steady-state warm turn.

## References & Research

### Internal
- `apps/web-platform/server/git-worktree-validity.ts` (probe/verdict), `cc-dispatcher.ts:1807-1963/2326`, `cc-reprovision.ts:123`, `inngest/functions/workspace-reconcile-on-push.ts:357`, `repo-resolver-divergence.ts:128`, `agent-runner-sandbox-config.ts:94`, `ensure-workspace-repo.ts:169-174/207/236/352`.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` (Amendment 2026-06-19, lines 715-764).
- Learnings: `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`, `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`, `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`.
- Post-mortems: `concierge-corrupt-worktree-validity-strand-postmortem.md`, `concierge-strand-reconcile-cannot-reclone-postmortem.md`, `concierge-warm-dispatch-reclaim-strand-postmortem.md`.

### Related Work
- Prior fix: commit `190ab58a5` (#5734). Sibling open PR: #5783 (#5591). Issue: #5733 (Ref, not Closes).
