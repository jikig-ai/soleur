---
title: "Durable agent-surface git-strand heal — gate dispatch readiness on the agent-context rev-parse signal (union) + un-blind the self-stop observability across all three gates"
type: fix
date: 2026-06-30
issue: 5733
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain  # no spec.md on the one-shot path → defaulted to cross-domain (fail-closed)
---

# Durable agent-surface git-strand heal (#5733)

## Overview

Concierge workspace `754ee124…` (the operator's own) still strands `/soleur:go` on
*"not a git repository"* **after** the prior fix (commit `190ab58a5`, merged
2026-06-30 14:32 UTC, deployed ~15:00 UTC). That commit shipped lstat-based
structural scaffolding (`probeGitWorktreeShape`, `isReadyGitWorkTree`,
`isStrandingFilePointer` in `git-worktree-validity.ts`) plus the
`reportAgentReadinessSelfStop` Sentry mirror, wired at all three dispatch gates.
**Those are on main — this PR does NOT re-ship them.** This PR closes the gap they
left:

1. All three readiness gates decide heal/spawn on a **cheap lstat structural
   proxy** (`isReadyGitWorkTree` = `dir-valid` OR non-escaping `file-pointer`).
   ADR-044's 2026-06-19 amendment chose that proxy *explicitly* as "deliberately
   WEAKER than `git rev-parse --is-inside-work-tree` but cheap enough to keep the
   AC7 zero-await hot path." For 754ee124 the proxy returns **ready**, so the heal
   is skipped, the agent spawns, and its in-bwrap `git rev-parse` strands. This is
   the textbook proxy-vs-invariant divergence (`2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`).
2. Because the gate is the lstat proxy, the `agent_readiness_self_stop` mirror is
   also silent (its firing condition is `!gitReady`, the same proxy) — zero
   `agent_readiness_self_stop` events exist in EU Sentry despite the confirmed
   strand. The observability is **blind precisely on the shape it was built to see.**
3. The mirror is wired at the **cold** path only. The two other gates (warm
   reprovision, Inngest reconcile-on-push) are observability-dark — and the
   reconcile path is the surface a prior session proved actually fires (26× on the
   affected workspace, zero actionable events; `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`).

**The durable fix:** gate the heal/spawn decision — and the self-stop emit — on the
agent's **own-context readiness verdict**, computed as a structural UNION
(`isStrandingFilePointer(shape) || !hostGitRevParse(workspacePath)`), at all three
gates, robust to *all* H2 realizations (escaping gitdir pointer, corrupt
`dir-valid`, invalid HEAD/objects). Preserve the never-destroy-populated invariant:
heal only provably-safe shapes; **emit-and-honest-block** the populated-corrupt dir.

PR body uses **Ref #5733** (not Closes) — operator-surface reproduction on 754ee124
is post-merge verification.

## Problem Statement / Motivation

`/soleur:go` Step 0.0 runs `git rev-parse --is-inside-work-tree` inside the agent's
Bash bwrap sandbox, which sets `denyRead:["/workspaces","/proc"]`
(`agent-runner-sandbox-config.ts:94`) and is jailed to `workspacePath`. A `.git`
whose `gitdir:` target resolves under the `/workspaces` **parent** is host-readable
but `denyRead` in-sandbox → `rev-parse` fails → the agent reasons over the prompt and
self-stops, emitting **no server-side event** (the self-stop is prompt-driven). The
server-side readiness gates approximate that signal with `lstat` only; the
approximation disagrees with the agent's real signal on 754ee124's shape, so the
strand both (a) survives the heal and (b) leaves no queryable trace.

The exact on-disk `.git` shape at `/workspaces/754ee124…` is **the one thing not
remotely observable** (because the observability is blind). Therefore the fix MUST
be robust to every realization and MUST un-blind the observability on all three
paths so the next strand surfaces the shape.

## Research Reconciliation — brief framing vs. codebase reality

| Brief / issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Gate the dispatch self-heal on git rev-parse — NOT lstat `isValidGitWorkTree`" | All 3 gates already use the lstat proxy `isReadyGitWorkTree` (`cc-dispatcher.ts:1810-1838`, `cc-reprovision.ts:123`, `workspace-reconcile-on-push.ts:357`). `probeGitWorktreeShape`/`isStrandingFilePointer`/`reportAgentReadinessSelfStop` already exist on main. | Delta is the gate **signal**, not the scaffolding: swap the lstat-proxy verdict for the agent-context UNION verdict at all 3 sites + the emit. |
| "the merged self-stop mirror does NOT fire on the real strand (host-side git rev-parse runs outside bwrap)" | The merged mirror does not run *any* rev-parse — host- or in-bwrap. It fires on `!gitReady` (the lstat proxy), which returns **ready** for 754ee124 → mirror silent. | Refined diagnosis: the mirror is blind because its gate is the lstat proxy. Fix fires it on the UNION verdict (`!agentReady`), carrying both `gitValid` (lstat) and the new `gitRevParseValid` so the proxy-vs-invariant divergence is itself the diagnostic. |
| "clone a SELF-CONTAINED .git into workspacePath before query() constructs; assert ordering structurally" | Cold factory already `await ensureWorkspaceRepoCloned` (`cc-dispatcher.ts:1963`) before `sdkQuery()` (`:2326`); `ensureWorkspaceRepoCloned` unlinks an escaping pointer (`:174`) + clones self-contained (`git clone --depth 1` → `rename(tmp/.git, ws/.git)` sentinel, `:352`). | Part B is largely satisfied. New work: a structural **await-before-query ordering test**; route the rev-parse-invalid case into the heal; preserve the destroy boundary (see CTO trap below). |
| (B) implies "rev-parse failure → reclone fixes it" | For a populated `dir-valid` that fails rev-parse, `ensureWorkspaceRepoCloned` **early-returns `"ok"` at `ensure-workspace-repo.ts:207`** (`isValidGitWorkTree` passes) → it NO-OPS, does not heal. | Make populated-corrupt an explicit **"unhealed-by-design, observed-and-honest-blocked"** row: emit the self-stop + surface `RepoNotReadyError` (no destroy, no spawn). Strand is prevented by NOT spawning, not by destroying un-pushed work. |
| "robust to all H2 realizations (file-pointer, escaping gitdir, invalid HEAD/objects)" | `isStrandingFilePointer` catches only the escaping FILE-pointer. A corrupt `dir-valid` (HEAD+objects present but broken) passes `isReadyGitWorkTree` as ready → no heal, no emit (SpecFlow P0-1). | The UNION's `!hostGitRevParse` arm catches genuine corruption (fails host-side too); the `isStrandingFilePointer` arm catches the escaping pointer (host-readable, sandbox-denied). Together = all realizations. |

## Proposed Solution — Technical Approach

### Architecture — the agent-context readiness UNION (adopted over bwrap-reproduction)

Introduce an **injected probe seam** (mirroring the existing `gitDirValid` /
`ensureWorkspaceRepoCloned` seams at `cc-dispatcher.ts:1877/1886`) that computes the
agent-equivalent readiness verdict:

```
agentReady(workspacePath) =
  NOT isStrandingFilePointer(probeGitWorktreeShape(workspacePath))   // escaping/unclassifiable pointer
  AND hostGitRevParse(workspacePath)                                  // genuine corruption / invalid HEAD-objects
```

- `hostGitRevParse` runs `git -C <workspacePath> rev-parse --is-inside-work-tree`
  with **`GIT_CEILING_DIRECTORIES=<parent-of-workspacePath>`** (load-bearing — without
  the ceiling, host `git` ascends to a parent `.git` and false-passes, exactly the
  jail the agent's sandbox enforces). Bounded `timeout`. Returns `false` on non-zero
  exit / spawn error / timeout (fail-closed-to-heal).
- **Why UNION, not a bwrap-reproducing probe (CTO Q3):** the *only* host/in-sandbox
  divergence for `--is-inside-work-tree` is the escaping pointer — already detected
  structurally and synchronously by `isStrandingFilePointer`. Reproducing the bwrap
  `denyRead` mount adds nothing a host `rev-parse` + the structural check don't
  already cover, costs the expensive namespace setup, and creates a silent-drift
  coupling to `agent-runner-sandbox-config.ts`. The union is equivalent detection
  with less machinery and no coupling.
- **Hot-path scoping (CTO Q2):** keep `isReadyGitWorkTree` (lstat) as the cheap
  pre-filter. Run the UNION subprocess **only when** lstat says ready **AND** the
  workspace is connected (`repoUrl`) **AND** DB-ready (`repoReadiness.ok`) — exactly
  the population where a false-ready causes a silent strand. Everything else
  (repo-less, lstat-not-ready, cloning/error) keeps the existing cheap routing.

### Heal / observe decision matrix (applied at ALL THREE gates)

For a connected + DB-ready workspace that passes the lstat pre-filter:

| On-disk shape | `agentReady` | Heal action | Self-stop emit | Spawn? |
|---|---|---|---|---|
| `dir-valid` + rev-parse OK | true | none (fast path) | no | yes |
| non-escaping in-workspace pointer + rev-parse OK | true | none | no | yes |
| escaping / unclassifiable `file-pointer` | false | `ensureWorkspaceRepoCloned` unlinks pointer (`:174`) + reclones self-contained; re-probe | **YES** (`gitRevParseValid=false`, `gitKind`) | yes iff re-probe ready |
| empty-corrupt `dir` (`isEmptyCorruptGitDir`) | false | `ensureWorkspaceRepoCloned` rm (`:236`) + reclone; re-probe | **YES** | yes iff re-probe ready |
| **populated `dir-valid` that fails host rev-parse (genuine corruption)** | false | **NONE — `ensureWorkspaceRepoCloned` no-ops at `:207`** | **YES** | **NO — honest-block (`RepoNotReadyError`), never destroy** |
| probe error / timeout | false (fail-closed) | route to heal; honest-block if not a provably-safe shape | **YES** | no |

The destroy authorizations stay exactly the two that exist today
(`ensure-workspace-repo.ts:174` pointer FILE, `:236` empty-corrupt) — **this PR adds
no third `rm`** (CTO write-boundary requirement; `hr-write-boundary-sentinel-sweep-all-write-sites`).

### Un-blinding the two dark gates (SpecFlow P0-2, P0-3)

- **WARM** (`cc-reprovision.ts reprovisionWorkspaceOnDispatch`): currently returns
  `"ok"` on a benign `ensureWorkspaceRepoCloned` skip without healing, then the
  caller spawns regardless. Change: compute `agentReady`; on `!agentReady` fire the
  self-stop; **re-probe readiness after the heal** and return a `"failed"`-class
  outcome (honest reclaim message, no spawn) if still not ready.
- **RECONCILE** (`workspace-reconcile-on-push.ts`): the benign-skip branch
  (`:384-398`) writes only a `kb_sync_history` audit row, no Sentry mirror — the
  exact dark surface of the prior incident. Change: fire `reportAgentReadinessSelfStop`
  on the `!agentReady` / unrecovered branch (including benign-skip) so the strand is
  queryable on the path that actually fires.

The self-stop emit is consistent across all three gates so the strand surfaces **no
matter which path the affected surface traverses** — directly answering the
wrong-layer learning.

### Observability event change (#5733 deliverable C)

`reportAgentReadinessSelfStop` (`repo-resolver-divergence.ts:128`) already
pseudonymizes (userId→`userIdHash` at the boundary, `activeWorkspaceIdHash`
pre-hashed, **no `installationId`/`repoUrl`/raw `gitdirTarget`**) — the privacy bar
is already met. Changes:

- **Add `gitRevParseValid: boolean`** (the authoritative agent-context verdict) to
  the args + `extra`. Keep `gitValid` (lstat) — when the two diverge, the event
  itself shows the proxy-vs-invariant trap shape.
- Type-widening of the args object → cross-consumer grep
  (`hr-type-widening-cross-consumer-grep`): consumers are `cc-dispatcher.ts:1823`
  (cold emit) + `test/server/repo-resolver-divergence.test.ts`; new emit sites in
  `cc-reprovision.ts` + `workspace-reconcile-on-push.ts`.
- Fingerprint stays `(op,userId,activeWorkspaceId,gitKind)` — acceptable (the emit
  now fires only on `!agentReady`, so a `dir-valid` in the fingerprint always means
  "dir-valid that rev-parse-failed").

## Implementation Phases (failing tests FIRST — `cq-write-failing-tests-before`)

### Phase 0 — Preconditions / verification (no code)
- Confirm `git rev-parse --is-inside-work-tree` exit semantics + that
  `GIT_CEILING_DIRECTORIES=<parent>` prevents parent-`.git` ascension, with a
  throwaway fixture (escaping-pointer dir, corrupt `dir-valid`, healthy clone). Pin
  the verified output in Research Insights.
- Confirm the injected-seam pattern by reading the existing seam wiring at
  `cc-dispatcher.ts:1877/1886` and the harness `test/helpers/cc-dispatcher-harness.ts`.
- Grep the type-widening consumers; grep `rm(` in `ensure-workspace-repo.ts` to
  re-confirm exactly two `.git` destroy sites (`:174`, `:236`).

### Phase 1 — Probe seam + failing tests (RED)
- Add `agentReadyGitWorkTree(workspacePath): Promise<boolean>` (UNION + ceiling +
  bounded timeout, fail-closed) to `git-worktree-validity.ts`. Inject it as a seam
  so the three gates are unit-testable without spawning git.
- Write failing tests in `test/server/` (collected by `test/**/*.test.ts`):
  escaping-pointer → false; corrupt `dir-valid` → false; healthy clone → true;
  non-escaping pointer → true; probe timeout → false.

### Phase 2 — Cold gate (cc-dispatcher) GREEN
- Replace the lstat-derived `gitReady` verdict at `:1810-1838` with `agentReady`
  (lstat pre-filtered). Fire the self-stop on `!agentReady` carrying `gitRevParseValid`.
- Populated-corrupt branch: honest-block (`RepoNotReadyError`) rather than spawn.
- Add the structural **await-before-query** ordering test (the clone await at
  `:1963` precedes `sdkQuery()` at `:2326`).

### Phase 3 — Warm gate (cc-reprovision) GREEN
- Compute `agentReady`; memoize a positive result per-workspace-per-process
  (invalidate on shape-change/disconnect) so steady-state warm turns pay lstat only.
- Re-probe after heal; honest "failed" outcome (no spawn) if still not ready; fire
  the self-stop.

### Phase 4 — Reconcile gate (workspace-reconcile-on-push) GREEN
- Gate on `agentReady`; fire the self-stop on the unrecovered / benign-skip branch.

### Phase 5 — Observability event widening + ADR-044 amendment
- Widen `reportAgentReadinessSelfStop` with `gitRevParseValid`; update all emit sites
  + tests.
- Amend ADR-044 (see Architecture Decision section).

### Phase 6 — Typecheck + full runner
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run` (the package's real runner;
  do NOT use `npm run -w` — the repo root declares no `workspaces`).

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| **Predicate-swap only** (`isReadyGitWorkTree` → richer lstat) without a real rev-parse | SpecFlow P0-1: still shape-specific; misses corrupt `dir-valid`. If 754ee124 is corrupt-dir not escaping-pointer, the fix lands and still strands. |
| **bwrap-reproducing probe** (run rev-parse under a hand-rolled `denyRead` mount) | CTO Q3: the only divergence (escaping pointer) is already caught by `isStrandingFilePointer`; reproduction adds the expensive namespace setup + a silent-drift coupling to `agent-runner-sandbox-config.ts` for zero extra coverage. |
| **Widen destroy to "rev-parse-invalid + has origin → reclone"** | CTO Q1: origin is canonical for the *base*, not the working tree; a populated `.git` may hold the only copy of un-pushed prior-turn work. Loses the brand-survival invariant. |
| **Unconditional rev-parse on every dispatch** | CTO Q2: lstat pre-filter + connected-gate + warm memoization keeps the common hot path lstat-only; rev-parse fires only on the lstat-ready-but-suspect transition. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's own Concierge
  (`/soleur:go` on workspace 754ee124…) keeps dead-ending on *"No Git Repository in
  Workspace" / "not a git repository"* with no recovery and no queryable signal — the
  product's primary surface is unusable for the affected user.
- **If this leaks, the user's workflow/data is exposed via:** the new self-stop event
  carries only `userIdHash` + `activeWorkspaceIdHash` + booleans/`gitKind` — **no**
  `installationId`/`repoUrl`/raw path/`gitdirTarget`. A regression that emitted raw
  identifiers would expose workspace↔repo linkage in Sentry. The destroy boundary is
  the other exposure vector: a false-heal that `rm`s a populated `.git` would destroy
  un-pushed work.
- **Brand-survival threshold:** `single-user incident` (one operator's primary surface
  is already down). → `requires_cpo_signoff: true`; `user-impact-reviewer` runs at
  review-time (enumerate the un-pushed-work-loss mode + the raw-identifier-leak mode).

## Observability

```yaml
liveness_signal:
  what:            "Sentry event `agent_readiness_self_stop` (own issue group), emitted by all 3 dispatch gates when agentReady=false on a connected+ready workspace"
  cadence:         per-dispatch (deduped per (op,userId,workspace,gitKind) per process)
  alert_target:    "Sentry issue (query-only / discoverability — no page, by design; auto-heals or honest-blocks same dispatch)"
  configured_in:   "apps/web-platform/server/repo-resolver-divergence.ts:128 (emit); cc-dispatcher.ts (cold), cc-reprovision.ts (warm), inngest/functions/workspace-reconcile-on-push.ts (reconcile)"
error_reporting:
  destination:     "Sentry web-platform (EU) via reportSilentFallback → captureException; SENTRY_DSN"
  fail_loud:       "agent_readiness_self_stop event with gitRevParseValid=false + gitKind names the strand shape; honest-block surfaces RepoNotReadyError to the user"
failure_modes:
  - mode:          "agent dispatched into a rev-parse-invalid worktree (the strand)"
    detection:     "agent_readiness_self_stop event count > 0 for the workspace (Sentry query, all 3 gates)"
    alert_route:   "operator Sentry triage (query-only; not paged — self-heals/honest-blocks)"
  - mode:          "false-heal destroys a populated .git"
    detection:     "no third rm authorization (asserted by write-boundary test); isEmptyCorruptGitDir/isStrandingFilePointer remain the only two"
    alert_route:   "CI test failure on the destroy-boundary assertion"
  - mode:          "probe subprocess error/timeout"
    detection:     "fail-closed-to-heal + honest-block; emit fires; no silent spawn"
    alert_route:   "Sentry agent_readiness_self_stop (probe-error path)"
logs:
  where:           "Sentry (events) + pino logger.error line via reportSilentFallback; Docker container stdout"
  retention:       "Sentry project retention (90d)"
discoverability_test:
  command:         "curl -s -H \"Authorization: Bearer $SENTRY_TOKEN\" \"https://sentry.io/api/0/projects/<org>/web-platform/events/?query=message:agent_readiness_self_stop\" | jq 'length'"
  expected_output: "0 in steady state; >0 (with gitKind + gitRevParseValid in extra) after a strand on ANY of the 3 gates — the signal that was previously dark"
```

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-044** (`knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`,
status `accepted`) with a new **Amendment 2026-06-30 — dispatch readiness gates on
the agent-context rev-parse verdict (union), superseding the lstat-proxy trade-off
for the connected case.** This is an in-scope plan deliverable
(`wg-architecture-decision-is-a-plan-deliverable`) — it reverses the 2026-06-19
amendment's explicit "deliberately WEAKER than `git rev-parse` … cheap enough to keep
the AC7 zero-await hot path" decision. The amendment must record: lstat fast-path
**retained** as the pre-filter; the UNION rev-parse confirm fires **only** on the
lstat-ready + connected + DB-ready transition; warm-path memoization; destroy
authorizations **unchanged** (populated-corrupt stays honest-blocked); and add the
union approach to `## Alternatives Considered` against the rejected bwrap-reproduction.
Author via the `architecture` skill / Edit (Concierge and the plugin terminal are
equally-trusted agent contexts that edit ADR files on the filesystem and commit).

### C4 views
**No C4 impact.** Read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`).
Enumerated against this change: external human actors — none added (the operator is
the existing `founder` actor, multi-Owner per ADR-038); external systems/vendors —
none added (no new webhook/API/store); containers/data-stores — none (logic stays in
the existing `api` and `claude` containers); access relationships — unchanged. The
fix tightens the **pre-condition on the existing `api -> claude "Spawns agent
sessions"` edge** (`model.c4:249`), not the topology — consistent with ADR-044's own
prior no-C4-impact amendments (2026-06-17b, 2026-06-18). No `.c4` edit; no element
description is falsified.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Verified against the code. (Q1 destroy-boundary — HIGH: do NOT widen
`rm`; heal only provably-safe shapes, emit-and-honest-block the populated-corrupt dir;
flagged the `ensure-workspace-repo.ts:207` no-op trap that makes (B) observability,
not auto-heal, for that shape.) (Q2 hot-path — MEDIUM: acceptable; lstat pre-filter +
connected-gate + warm memoization keeps the common path lstat-only.) (Q3 mechanism —
MEDIUM: adopt the structural UNION + `GIT_CEILING_DIRECTORIES`; drop bwrap-reproduction
to avoid sandbox-config coupling.) Flags folded into the plan: ADR-044 amendment is a
deliverable; write-boundary sweep asserts no third `rm`; probe must be an injected
seam (unit-testable); `user-impact-reviewer` + `observability-coverage-reviewer` apply
at review-time. Known residual (out of scope for #5733): a `dir-valid` `.git` with
`objects/info/alternates` pointing under `/workspaces` passes rev-parse both sides but
strands later on object access — not a rev-parse strand.

### Product/UX Gate
Not relevant — no UI surface. All edits under `apps/web-platform/server/`; no
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`. The mechanical UI-surface
override did not fire. Tier: NONE.

### GDPR / Compliance (Phase 2.7)
Considered. No regulated-data surface (no schema/migration/auth/API-route/`.sql`).
Trigger (b) fires (single-user-incident threshold), but the change is
privacy-**preserving**: the self-stop event already pseudonymizes and the new field
(`gitRevParseValid`) is a non-PII boolean; **no `installationId`/`repoUrl`/raw path**
is emitted. Constraint carried into ACs: the new field must NOT defeat the
boundary-rename (no raw identifiers). Full `/soleur:gdpr-gate` invocation not required
(no new PII surface).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** `agentReadyGitWorkTree` returns `false` for an escaping `file-pointer`,
      `false` for a corrupt `dir-valid` (host rev-parse fails), `true` for a healthy
      clone, `true` for a non-escaping in-workspace pointer with valid rev-parse,
      `false` (fail-closed) on probe timeout/spawn error — RED tests authored first.
- [ ] **AC2** `hostGitRevParse` runs with `GIT_CEILING_DIRECTORIES=<parent>`; a test
      proves it returns `false` for a workspace whose own `.git` is invalid even when
      a parent dir contains a valid `.git` (no false-pass via ascension).
- [ ] **AC3** All three gates (`cc-dispatcher` cold, `cc-reprovision` warm,
      `workspace-reconcile-on-push` reconcile) decide heal/spawn on `agentReady`, lstat
      pre-filtered + connected-gated. Verified by a grep that no gate's spawn decision
      reads `isReadyGitWorkTree` as the sole authority for a connected+ready workspace.
- [ ] **AC4** `reportAgentReadinessSelfStop` fires on `!agentReady` from **all three**
      gates (cold + warm + reconcile incl. benign-skip), carrying `gitRevParseValid`
      (new), `gitValid` (lstat), `gitKind`, `activeWorkspaceIdHash` — and **no**
      `installationId`/`repoUrl`/raw path/`gitdirTarget` (assert the `extra` keys).
- [ ] **AC5** WARM re-probes readiness after `ensureWorkspaceRepoCloned` and surfaces
      the honest reclaim outcome (no spawn) when still `!agentReady` — no spawn-regardless.
- [ ] **AC6** Populated-corrupt `dir-valid` → emit + `RepoNotReadyError` honest-block;
      **no destroy**. Write-boundary test asserts exactly two `.git` `rm` sites remain
      (`ensure-workspace-repo.ts:174`, `:236`); no third authorization added.
- [ ] **AC7** Structural ordering test: in the cold factory the `ensureWorkspaceRepoCloned`
      await (`:1963`) precedes `sdkQuery()` (`:2326`).
- [ ] **AC8** ADR-044 Amendment 2026-06-30 written (lstat pre-filter retained; union
      rev-parse confirm; warm memoization; destroy unchanged; union in Alternatives).
- [ ] **AC9** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes;
      `./node_modules/.bin/vitest run` green (the real runner — not `npm run -w`).

### Post-merge (operator / automatable)
- [ ] **AC10** Assert 754ee124's **actual on-disk `.git` shape** first (escaping
      pointer vs. corrupt dir vs. in-workspace pointer) so a green dispatch isn't a
      false-green for an unrelated reason (SpecFlow P0-4). Automatable via a read-only
      shape probe.
- [ ] **AC11** Exercise the path the live strand actually traverses — per the prior
      incident, **RECONCILE / WARM**, not only a fresh COLD `/soleur:go` — and confirm
      no strand + an `agent_readiness_self_stop` event is queryable (or absent because
      healed). Ref #5733; close the issue in a post-merge step (`gh issue close 5733`)
      after the operator-surface repro, not at merge.

## Test Scenarios

- Given an escaping gitdir `file-pointer` at the workspace root, when any of the 3
  gates evaluates readiness, then `agentReady=false` → heal (unlink+reclone) →
  self-stop emitted → re-probe ready → agent spawns into a healthy repo.
- Given a populated `dir-valid` `.git` that fails host `rev-parse`, when the cold gate
  evaluates, then self-stop emitted with `gitValid=true,gitRevParseValid=false` (the
  divergence) → honest-block `RepoNotReadyError` → **no spawn, no destroy**.
- Given a WARM dispatch whose `ensureWorkspaceRepoCloned` benign-skips without healing,
  when reprovision returns, then it re-probes, returns the honest "failed" outcome, and
  does not spawn (regression for SpecFlow P0-2).
- Given a RECONCILE benign-skip (repoUrl fails the allowlist) that did not heal, when
  the handler returns, then `agent_readiness_self_stop` is queryable (regression for
  P0-3 / the 26×-dark-fire incident).
- Given a healthy clone (`dir-valid` + rev-parse OK), when any gate evaluates, then no
  subprocess beyond the cheap lstat is paid on the warm steady state (memoized) — no
  hot-path regression.
- Given a repo-less Start-Fresh workspace (`git init`, no `repoUrl`, no origin), when
  the cold gate evaluates an absent or `dir-valid` `.git`, then it benign-skips / fast-
  paths and never destroys un-pushed init state (P2 edge).

## Open Code-Review Overlap

3 open code-review issues touch the edited files:
- **#3243** (`arch: decompose cc-dispatcher.ts into focused modules`) — **Acknowledge**:
  a structural refactor, different concern; this PR makes minimal in-place edits to the
  three gate blocks, not a decomposition. Remains open.
- **#3739** (`extract reportSilentFallbackWithUser helper — collapse 11-site duplication`)
  — **Acknowledge**: the new emit sites should follow the *existing*
  `reportAgentReadinessSelfStop` wrapper (which already routes through
  `reportSilentFallback`), so they do not add raw `withIsolationScope+setUser`
  duplication. Remains open.
- **#3242** (`tool_use WS event lacks raw name field`) — unrelated; no action.

**Merge-ordering note (#5783 docstring drift):** sibling open PR #5783 adds a +7-line
op-inventory docstring to `observability.ts` (multi-owner reconcile ops) and carries
`2026-06-30-sentry-op-inventory-docstring-drifts-when-sibling-op-added.md`. This PR's
self-stop emit lives in `repo-resolver-divergence.ts` (NOT `observability.ts`) and the
`agent-readiness-self-stop` op slug already exists — so this PR **should not edit
`observability.ts`'s inventory**, avoiding the drift. If review insists on inventorying
the op there, rebase after #5783 merges.

## Risks & Sharp Edges

- **The `ensure-workspace-repo.ts:207` no-op trap (CTO):** routing a populated-corrupt
  `dir-valid` into `ensureWorkspaceRepoCloned` does NOT heal it (early-returns `"ok"`).
  Anyone reading deliverable B as "rev-parse failure → reclone fixes it" is wrong for
  this shape — its value is observability + honest-block, not auto-heal. Encoded in AC6.
- **`GIT_CEILING_DIRECTORIES` is load-bearing:** without it host `git` ascends to a
  parent `.git` and false-passes, leaving the strand dark. Encoded in AC2.
- **Wrong-layer trap:** prior fixes landed at a gate the affected surface never
  traversed (zero `cc-dispatcher` events; reconcile fired 26×). This PR fires the
  self-stop from all three gates *and* AC11 exercises the live-traversed path — do not
  declare close on a COLD-only repro.
- **Type-widening sweep:** adding `gitRevParseValid` must update every consumer
  (`hr-type-widening-cross-consumer-grep`).
- **Known residual (out of scope):** `objects/info/alternates` under `/workspaces`
  passes rev-parse both sides but strands on object access — note it so #5733 isn't
  assumed to close it.
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan`
  Phase 4.6 — this one is filled (threshold `single-user incident`).

## Files to Edit

- `apps/web-platform/server/git-worktree-validity.ts` — add `agentReadyGitWorkTree` +
  `hostGitRevParse` (union, ceiling, bounded timeout, fail-closed).
- `apps/web-platform/server/cc-dispatcher.ts` — cold gate (`:1807-1838`, seam
  `:1886`): swap verdict to `agentReady`; emit `gitRevParseValid`; honest-block
  populated-corrupt.
- `apps/web-platform/server/cc-reprovision.ts` — warm gate (`:123`): `agentReady` +
  memoization; re-probe-after-heal honest fail; self-stop emit.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` —
  reconcile gate (`:357`, `:384-398`): `agentReady`; self-stop on unrecovered/benign-skip.
- `apps/web-platform/server/repo-resolver-divergence.ts` — widen
  `reportAgentReadinessSelfStop` with `gitRevParseValid` (`:128-162`).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`
  — Amendment 2026-06-30.

## Files to Create (tests)

- `apps/web-platform/test/server/agent-ready-git-worktree.test.ts` — probe unit tests
  (union, ceiling, fail-closed).
- Extend `apps/web-platform/test/cc-dispatcher-self-heal-observability.test.ts` +
  `apps/web-platform/test/helpers/cc-dispatcher-harness.ts` — three-gate emit/heal/honest-block
  + await-before-query ordering, via the injected seam.

## References

- Issue: Ref #5733. Prior fix commit: `190ab58a5` (#5734). Sibling: #5783.
- ADR-044 (`:715` 2026-06-19 amendment — the lstat-proxy trade-off this reverses).
- Sandbox SoT: `apps/web-platform/server/agent-runner-sandbox-config.ts:94`.
- Learnings: `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`,
  `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`,
  `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy.md`.
- Review-time agents (single-user threshold): `user-impact-reviewer`,
  `observability-coverage-reviewer`.
