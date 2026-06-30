---
title: "fix: agent-readiness absent-.git strand heal/block + observable backstop + per-workspace ready-clone (Ref #5733)"
date: 2026-06-30
issue: 5733
branch: feat-one-shot-5733-founder-resolve-multiworkspace-clone
lane: cross-domain  # no spec.md present → defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: bug
status: draft
---

# fix: agent-readiness absent-`.git` strand — heal/block + observable backstop + per-workspace ready-clone (Ref #5733)

## Enhancement Summary

**Deepened on:** 2026-06-30
**Hard gates:** 4.6 User-Brand (PASS, single-user incident), 4.7 Observability
(PASS, 5 fields, no-ssh), 4.8 PAT-shape (PASS), 4.9 UI-wireframe (PASS — no UI
surface).

### Key Improvements
1. **Prod-verified root-cause reclassification** (Research Reconciliation): the
   loud founder-ambiguity Sentry issue (1901 lifetime, **0/24h, stopped 06-29**) is
   a separate, already-repo-scoped, non-`repo_last_synced_at`-writing webhook path
   — NOT the freeze cause. The freeze cause is the absent-`.git` strand being
   unhealed + unobservable. Prevents a wrong-layer re-fix.
2. **D2 call-site ordering analysis** (Deepen Findings, load-bearing): traced
   heal/gate ordering across cold (post-heal, unconditional → THE fix), warm
   (gate skipped for absent), reconcile (pre-heal, non-spawn → must NOT emit). Phase
   2 + AC5 + tasks scoped accordingly.
3. **D1 cross-consumer blast-radius** (5+ consumers) → recommend reducing D1 to
   the regression test only (YAGNI; D2 already honest-blocks).

### New Considerations Discovered
- The per-installation founder collapse the argument framed does **not exist** in
  the ready-clone path (it resolves per-active-workspace-id) — deliverable 1
  reframed from "fix founder collapse" to "lock per-workspace invariant + tighten".
- `754ee124` is NOT solo (4 members, 2 owners; jean co-owns both) — the fix is
  workspace-shape-agnostic.

## Overview

Workspace `754ee124` (→ `jikig-ai/soleur`) strands `/soleur:go` at Step 0.0: the
agent dispatches into `/workspaces/754ee124` whose on-disk `.git` is **ABSENT**
(no repo on disk at all — NOT the corrupt/`.git`-present class the just-merged
77e77c3 fix targeted), the agent's in-bwrap `git rev-parse` reports no work tree,
and the agent self-stops with the honest "your workspace isn't ready" message —
**emitting ZERO server-side Sentry events** (prod-confirmed: 0 events for
`754ee124` / `agent_readiness_self_stop`). `repo_last_synced_at` is frozen at
2026-06-29 because the only writer is the agent's own in-workspace `git pull/push`
(`session-sync.ts`), which never runs when the repo never lands.

This plan delivers three server-side TypeScript fixes (no DDL):

1. **Absent-`.git` is a strand, not "ready."** Harden the shared
   `evaluateAgentReadiness` gate (added in 77e77c3) so an **absent** (and
   **dir-invalid**) `.git` at the post-self-heal dispatch gate emits
   `agent_readiness_self_stop` and **honest-blocks** (RepoNotReadyError) instead
   of greenlighting a doomed agent spawn.
2. **The in-sandbox backstop must catch the empty-output form.** Fix
   `isInSandboxRevParseStrand` (C2 detector) to recognise the **stderr-suppressed
   empty output** that `go.md` Step 0.0 actually produces
   (`git rev-parse --is-inside-work-tree 2>/dev/null || true` → empty stdout,
   suppressed stderr), so the strand is queryable for ANY on-disk shape.
3. **Per-workspace ready-clone — regression LOCK (test-only).** The ready-clone
   path already resolves repo/install/CWD per-active-workspace-id (NOT a
   per-installation founder — see Research Reconciliation); add a regression test
   proving two connected workspaces sharing one installation each resolve + clone
   independently. (The originally-scoped `ensureWorkspaceRepoCloned` benign-skip
   behaviour change was DROPPED after deepen review — D2 already covers the outcome
   and the change had a 5-consumer blast radius. See Phase 3 / Deepen Findings.)

**Brand-survival threshold: single-user incident.** A single user whose repo
silently fails to land is told to "reconnect" (an action that doesn't fix it) and
is permanently stranded with no operator signal. CPO sign-off required at plan
time; `user-impact-reviewer` runs at review.

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge replies "Your
workspace isn't ready yet — its repository is still being set up…" on every
attempt forever, with no path to recovery (the repo never re-lands and the
operator gets no signal to intervene).

**If this leaks, the user's data/workflow is exposed via:** N/A — the diff adds
no new data egress. All new observability reuses the existing ADR-029
pseudonymization boundary (`userId → userIdHash`, pre-hashed `activeWorkspaceIdHash`
for solo workspaces, NEVER the raw `workspacePath`/`gitdirTarget`). The new
`gitKind:"absent"` tag is a low-cardinality enum with no PII.

**Brand-survival threshold:** single-user incident.

## Research Reconciliation — Spec vs. Codebase

The issue/argument framing ("ambiguous founder for >1 solo workspace per
installation collapses the ready-clone") is the **loud signal**, but prod forensics
+ end-to-end code tracing reclassify it. This table is load-bearing — building the
fix on the original framing would target a path that is already fixed and never
executes on the affected surface (per
`knowledge-base/project/learnings/2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`).

| Claim (argument/issue) | Reality (traced + prod-verified) | Plan response |
|---|---|---|
| "Founder-resolution can't disambiguate two solo workspaces on one installation → ready-clone never lands the 2nd repo." | The **ready-clone/dispatch** path resolves repo (`getCurrentRepoUrl`, by `workspaces.id`), installation (`resolveInstallationId` → `resolve_workspace_installation_id` RPC, per-workspace-id, membership-checked) and CWD (`fetchUserWorkspacePath` → `<root>/<activeWorkspaceId>`) ALL keyed on the **unified active-workspace-id** (`cc-dispatcher.ts:1551-1618`). The #4767 clone-target divergence is already fixed. There is **no per-installation founder collapse** anywhere in the clone/sync path. | Do NOT add founder disambiguation to the clone path. Instead **lock the per-workspace invariant** with a regression test (two connected workspaces, one installation, each clones independently) and reframe deliverable 1 to "harden + prove per-workspace clone." |
| "~1901 Sentry events on the founder-ambiguity issue is the current cause." | Sentry `WEB-PLATFORM-3M` ("ambiguous founder for installation (>1 solo workspaces)", `op:founder-ambiguous`) = **1901 lifetime, 0 in the last 24h, last seen 2026-06-29T10:44:18Z**. It is on the **non-push webhook attribution path** (`resolveSoloFounderForInstallation` ← `POST /api/webhooks/github`), which is **already repo-scoped on main** (`resolve-founder-for-installation.ts:104-108` `.eq("repo_url", repoUrl)`) and **does not write `repo_last_synced_at`**. The error STOPPED on 06-29 — it is a separate, already-mitigated bug, not the freeze cause. | Document as a separate already-fixed issue. Do NOT re-fix it. The freeze cause is the absent-repo strand (rows below). |
| "Installation 122213433 hosts TWO **solo** workspaces." | Prod: `52af49c2`→chatte is genuinely solo (1 owner member, `user_id==id`). `754ee124`→soleur is **NOT solo** — 4 members, 2 owners (`754ee124/owner` AND `52af49c2/owner`; user `52af49c2`/jean co-owns both). | The fix is workspace-shape-agnostic (absent `.git` strand applies to solo AND team). The regression test covers a solo + a co-owned workspace on one installation. |
| `evaluateAgentReadiness` (77e77c3) handles the strand. | It runs the host `rev-parse` confirm **only for `dir-valid`** (`git-worktree-validity.ts:409`: `if (probeGitWorktreeShape(...).kind !== "dir-valid") return "ready"`). An **absent** `.git` returns `"ready"` → doomed spawn. | **Deliverable 2** — widen the gate to treat `absent`/`dir-invalid` as a confirmed strand → emit + block. |
| The C2 in-sandbox backstop catches the strand. | `isInSandboxRevParseStrand` (`tool-labels.ts:42-45`) matches only `not a git repository`, `^fatal:`, or `false`. `go.md` Step 0.0 (`commands/go.md:24`) runs `git rev-parse … 2>/dev/null \|\| true` → **empty output** → detector returns `false`. Strand unobservable (0 prod events — confirmed). | **Deliverable 3** — match the empty/whitespace (no-`true`) output form. |

**Premise Validation note:** Issue #5733 is OPEN (`type/bug`, `priority/p1-high`,
`domain/engineering`, `follow-through`). Commit 77e77c3 is on main and targets the
dir-valid-corrupt slice (verified — NOT this bug). The cited learning
`2026-06-18-multi-workspace-per-installation-breaks-founder-resolve-and-ready-clone.md`
documents Bug 1 (webhook repo-scope, shipped) + Bug 2 (`ready`-but-`.git`-absent
self-heal in `repo-readiness-self-heal.ts` + migration 113, **both shipped** —
verified present). This plan is the **gate + observability** layer that Bug 2's
self-heal does NOT cover: the dispatch gate that runs AFTER the self-heal and the
in-sandbox backstop.

## Root Cause (traced to call sites)

`repo_last_synced_at` advances ONLY via `session-sync.ts` after the agent's
in-workspace `git pull/push` (per-workspace-id, `workspace-repo-mirror.ts:63`).
`cron-workspace-sync-health.ts:232` (the only periodic re-clone) scans
`repo_status='ready' AND github_installation_id IS NULL` — so a **connected**
workspace (non-null install, like both affected rows) has **no periodic re-clone
backstop**; it relies on (a) a push webhook reconcile, or (b) a **cold** dispatch
self-heal. When `754ee124`'s `.git` is reclaimed (sandbox/host) and the
`ensureWorkspaceRepoCloned` self-heal fails or benign-skips, the repo stays absent.
At that point the cold-path dispatch gate (`cc-dispatcher.ts:2010`) calls
`evaluateAgentReadiness`, which returns `"ready"` for the `absent` shape
(deliverable-2 gap) and spawns the agent. The agent runs `go.md` Step 0.0 with
suppressed stderr, strands, and the C2 backstop misses the empty output
(deliverable-3 gap) → **silent forever**. No agent sync → `repo_last_synced_at`
frozen.

## Implementation Phases (TDD — failing tests FIRST per `cq-write-failing-tests-before`)

### Phase 0 — Preconditions (no code)
1. Confirm `apps/web-platform/test/` vitest discovery globs include the new test
   paths (`vitest.config.ts` `include:` → `test/**/*.test.ts`). All new tests live
   directly under `test/`.
2. Typecheck baseline green: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Phase 1 — Deliverable 3 (C2 detector): RED → GREEN
- **RED:** extend `test/` coverage for `isInSandboxRevParseStrand` (new file
  `test/in-sandbox-revparse-strand.test.ts`, or extend an existing tool-labels
  test): assert that the **exact go.md Step 0.0 command**
  (`git rev-parse --is-bare-repository 2>/dev/null || true; git rev-parse --is-inside-work-tree 2>/dev/null || true`)
  with **empty output** returns `true` (strand). Assert the **healthy** compound
  output (`"false\ntrue"`) returns `false`. Assert a **bare-repo** output
  (`"true\nfalse"`) returns `false` (contains `true` → not a strand, matches
  go.md's "if neither prints true"). Keep the existing `not a git repository` /
  `fatal:` / `false` cases green.
- **GREEN (verdict REPLACEMENT, net LOC down — simplicity review):** in
  `server/tool-labels.ts:35-46`, **collapse** the four existing branches
  (`not a git repository` / `=== true` / `^fatal:` / `=== false`) into a single
  negation — they are all dead under it:
  ```ts
  if (!isWorkTreeProbe) return false;
  return !/(^|\s)true(\s|$)/i.test(output);  // strand iff no standalone `true`
  ```
  Keep the `isWorkTreeProbe` command-regex guard. **Reviewer disagreement
  resolved:** simplicity-review says keep the loose `--is-inside-work-tree` token
  and reject pinning the compound string (brittle to go.md whitespace edits);
  architecture-review notes the loose `[\s\S]*` guard lets a LARGER non-probe
  command that merely *contains* the tokens but yields empty output false-positive
  a strand **emit** (observability noise, not user-blocking). **Resolution:** keep
  the negation + REJECT pinning the exact compound string, BUT tighten
  `isWorkTreeProbe` so the command IS the probe (anchor: the rev-parse work-tree
  probe is the command's operative content — e.g. each statement is a
  `git … rev-parse … --is-inside-work-tree`/`--is-bare-repository`), not merely
  contains the tokens inside an unrelated script. Add a NEGATIVE test: a larger
  non-probe command embedding the tokens with empty output → NOT a strand.
  Fail-direction on the strand side stays safe (a coincidental standalone `true`
  → false-NEGATIVE/missed emit, never a false block — D2 + host confirm protect
  the user).

### Phase 2 — Deliverable 2 (absent-`.git` strand gate): RED → GREEN
- **RED:** new `test/agent-readiness-absent-git.test.ts`: with an injected probe
  + a temp workspace whose `.git` is **absent**, assert `evaluateAgentReadiness`
  returns `"block"` AND `reportAgentReadinessSelfStop` fired with
  `gitKind:"absent"`, `gitRevParseValid:false`, `source:"host-pre-heal"`. Add a
  `dir-invalid` case (same outcome). Assert `dir-valid`+`worktree` still returns
  `"ready"` (no regression) and the `inconclusive`×2 fail-open path is unchanged.
- **GREEN:** in `server/git-worktree-validity.ts:401-433`, replace the
  `kind !== "dir-valid" return "ready"` early-return with shape-aware routing:
  - `dir-valid` → run the host `rev-parse` confirm (unchanged).
  - `absent` / `dir-invalid` → emit `reportAgentReadinessSelfStop({ gitKind, gitRevParseValid:false, source:"host-pre-heal" })` and return `"block"`. **Rationale (architecture-review corrected):** ONLY on the COLD path has the self-heal already run before this gate (post-heal); absent-at-cold-gate is a true terminal strand → honest-block + emit. Do NOT re-attempt a destructive heal here.
  - `file-pointer` (escaping/in-workspace) → unchanged (`"ready"`; the lstat verdict + `ensureWorkspaceRepoCloned` own the pointer heal).
  - Preserve the `!connected || !dbReady → "ready"` guard.
- **Surface scoping (architecture P1 — LOAD-BEARING, prevents soak-signal
  pollution):** the shared helper has caller-position-dependent heal ordering
  (cold = post-heal; warm = gate only runs when `isReadyGitWorkTree`; reconcile =
  PRE-heal, then heals via `||` regardless). An unconditional absent→emit would
  fire a FALSE-POSITIVE `agent_readiness_self_stop` on EVERY push-reconcile of a
  connected workspace whose `.git` is transiently absent **even when the next
  line re-clones it successfully** — conflating "stranded forever" with "absent,
  recovered normally" in the exact AC10/7-day-soak signal. **Implement** by
  threading the heal-relationship into `AgentReadinessContext` (e.g.
  `phase: "post-heal" | "pre-heal"`): emit the absent self-stop ONLY when the
  verdict is terminal (`post-heal`, i.e. cold). On reconcile (`pre-heal`) the
  absent shape returns `block` WITHOUT an emit (or simply is not consulted —
  reconcile already routes absent to re-clone via `!isReadyGitWorkTree`); warm
  never reaches the gate for absent. This replaces the incorrect "self-heal
  already ran upstream" framing the first draft applied uniformly.
- Caller note: the cold (`cc-dispatcher.ts:2010`), warm (`cc-reprovision.ts:130`),
  and reconcile (`workspace-reconcile-on-push.ts:372`) call sites already map
  `"block"` → honest RepoNotReadyError / "failed" / skip.

### Phase 3 — Deliverable 1 (per-workspace clone invariant): TEST-ONLY
**Reduced to test-only — BOTH reviewers (simplicity + architecture) converged:**
the `ensure-workspace-repo.ts` benign-skip→`"failed"` behaviour change is dropped.
It is redundant with D2 (a connected+absent workspace that benign-skips already
hits the D2 cold gate → `kind==absent` → honest-block + emit, no code change to
`ensure-workspace-repo.ts` needed) AND carries a 5-consumer blast radius for a
rare corrupt-DB edge (the url passed the connect-time allowlist). The per-workspace
clone path is already correct (Research Reconciliation); D1 is a regression LOCK,
not a fix.
- **RED:** new `test/ready-clone-per-workspace.test.ts`: two workspace ids sharing
  ONE installation id but DIFFERENT repo_urls. **Must exercise the REAL
  workspace-id keying** in at least one resolver (do NOT stub all three of
  `resolveInstallationId` / `getCurrentRepoUrl` / `fetchUserWorkspacePath` — that
  tests mock wiring, a tautology, and should be dropped if it cannot drive real
  resolution). Assert each workspace resolves its OWN repo_url + CWD and invokes
  `ensureWorkspaceRepoCloned(workspacePath=<id>, repoUrl=<own>)` independently — no
  founder collapse, no `>1`. One installation, two ids, two repo_urls is enough —
  no elaborate multi-installation fixtures.
- **No `ensure-workspace-repo.ts` edit.** (If the team later wants
  defense-in-depth layer-attribution there, the minimal form is a one-line
  `return existsSync(join(workspacePath, ".git")) ? "ok" : "failed";` at the
  malformed-url branch — NOT the two-part `connected AND absent` conditional, since
  by line 252 `connected` is already guaranteed. Out of scope for this PR.)

### Phase 4 — Full-suite + typecheck gate
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/in-sandbox-revparse-strand.test.ts test/agent-readiness-absent-git.test.ts test/ready-clone-per-workspace.test.ts test/ensure-workspace-repo.test.ts test/tool-labels.test.ts test/cc-dispatcher-self-heal-observability.test.ts`
- Then the broader affected suites (`cc-dispatcher*`, `repo-readiness*`,
  `cc-reprovision*`, `workspace-reconcile*`) to catch the orphan/exhaustiveness
  suites the targeted run misses.

## Files to Edit
- `apps/web-platform/server/tool-labels.ts` — D3: collapse `isInSandboxRevParseStrand` to the no-`true` negation (verdict replacement) + anchor the command guard.
- `apps/web-platform/server/git-worktree-validity.ts` — D2: `evaluateAgentReadiness` absent/dir-invalid → emit + block; add `phase: "post-heal" | "pre-heal"` to `AgentReadinessContext` so the absent emit fires only on a terminal (post-heal) verdict.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — pass `phase:"pre-heal"` so reconcile-absent does NOT emit a false-positive self-stop (architecture P1).
- `apps/web-platform/server/cc-dispatcher.ts` — pass `phase:"post-heal"` at the cold gate (`:2010`).
- `apps/web-platform/server/cc-reprovision.ts` — pass `phase` at the warm gate (`:145`); warm never reaches it for absent, so either value is correct — use `post-heal` for consistency.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amend the dispatch-readiness consequence (§ line 552) to record: gate fires for `absent`/`dir-invalid` (not only `dir-valid`), the per-path heal ordering (cold post-heal emits; reconcile pre-heal heals-without-emit; warm gate-skipped for absent), + the in-sandbox empty-output backstop.
- (D1 behavior change to `ensure-workspace-repo.ts` DROPPED — see Phase 3.)

## Files to Create
- `apps/web-platform/test/in-sandbox-revparse-strand.test.ts`
- `apps/web-platform/test/agent-readiness-absent-git.test.ts`
- `apps/web-platform/test/ready-clone-per-workspace.test.ts`
- (`apps/web-platform/test/ensure-workspace-repo.test.ts` runs in Phase 4 as an unchanged regression suite — NOT modified, since the D1 behaviour change was dropped.)

No new migration (all columns exist; `repo_error` shipped in mig 110/113). No new
infrastructure.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `isInSandboxRevParseStrand("…rev-parse --is-inside-work-tree…", "")` returns `true`; the healthy compound output `"false\ntrue"` returns `false`; bare-repo `"true\nfalse"` returns `false`. (vitest)
- [ ] AC2: `evaluateAgentReadiness` returns `"block"` and fires `reportAgentReadinessSelfStop({gitKind:"absent", gitRevParseValid:false, source:"host-pre-heal"})` for an absent `.git` (connected+dbReady); same for `dir-invalid`; `dir-valid`+`worktree` still returns `"ready"`; `inconclusive`×2 still fails-open `"ready"`. (vitest)
- [ ] AC3: two connected workspaces sharing one installation id with distinct repo_urls each resolve their OWN repo_url + CWD and each invoke `ensureWorkspaceRepoCloned` independently (no `>1`/collapse) — exercising REAL workspace-id resolution, not all-three-stubbed mock wiring. (vitest)
- [ ] AC4: (D1 behavior change DROPPED — no `ensure-workspace-repo.ts` assertion; D2 covers the connected+absent outcome at the cold gate.)
- [ ] AC5: **cold** (`phase:post-heal`)-absent emits `agent_readiness_self_stop` + maps `"block"` → honest RepoNotReadyError (no spawn); **reconcile** (`phase:pre-heal`)-absent does NOT emit a self-stop and the workspace is re-cloned via `!isReadyGitWorkTree`; **warm**-absent routes to heal (never reaches the gate). (vitest, 3 call-site assertions — the reconcile no-emit assertion is the architecture-P1 soak-signal-pollution guard.)
- [ ] AC6: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] AC7: targeted + affected vitest suites pass (Phase 4 list).
- [ ] AC8: ADR-044 dispatch-readiness consequence amended to cover absent/dir-invalid + empty-output backstop.
- [ ] AC9: PR body uses **`Ref #5733`** (NOT `Closes`) — closure is gated on the post-deploy soak below.

### Post-merge (operator / automated)
- [ ] AC10: After deploy, the next dispatch into a connected+absent workspace produces a queryable `agent_readiness_self_stop` event (`source:host-pre-heal` OR `source:in-sandbox-backstop`, `gitKind:absent`). Verify via Sentry issue search (no SSH). Soak: see Follow-Through Enrollment.

## Observability

```yaml
liveness_signal:
  what: "agent_readiness_self_stop Sentry events (gitKind:absent | source:in-sandbox-backstop) — strand is now observable"
  cadence: per dispatch into an absent/invalid-.git workspace
  alert_target: "Sentry issue (query-only discoverability, no page — auto-heals or honest-blocks)"
  configured_in: "server/repo-resolver-divergence.ts (reportAgentReadinessSelfStop); searchable via tags source/gitKind/gitRevParseValid"
error_reporting:
  destination: Sentry via reportSilentFallback (ADR-029 pseudonymization boundary)
  fail_loud: true  # honest RepoNotReadyError to the user + Sentry event; never silent spawn
failure_modes:
  - mode: "absent .git at dispatch gate"
    detection: "evaluateAgentReadiness probeGitWorktreeShape kind==absent → emit + block"
    alert_route: "agent_readiness_self_stop (gitKind:absent, source:host-pre-heal)"
  - mode: "in-sandbox Step 0.0 empty rev-parse output"
    detection: "isInSandboxRevParseStrand empty/no-true output"
    alert_route: "agent_readiness_self_stop (source:in-sandbox-backstop)"
  - mode: "connected+absent clone cannot proceed (malformed url / clone fail)"
    detection: "ensureWorkspaceRepoCloned returns failed → RepoNotReadyError"
    alert_route: "ensure-workspace-repo Sentry op + honest user message"
logs:
  where: Sentry (reportSilentFallback) + pino structured logs (createChildLogger)
  retention: existing Sentry/Better Stack retention (unchanged)
discoverability_test:
  command: "Sentry issue search: query='agent_readiness_self_stop gitKind:absent' statsPeriod=7d (REST API, no ssh)"
  expected_output: ">=1 event after a real absent-.git dispatch post-deploy; 0 before deploy"
```

### Soak Follow-Through Enrollment
An existing **operator-confirm** followthrough already covers "754ee124 strand
healed": `scripts/followthroughs/concierge-strand-754ee124-5733.sh` (reads the
operator's `RESULT: PASS/FAIL` comment on #5733). KEEP it. This plan adds a
distinct **mechanical observability soak** for the net-new capability (the strand
is now queryable, not just healed):
- New script: `scripts/followthroughs/agent-readiness-absent-strand-observable-5733.sh`
  — exit 0 when, for 7 days post-deploy, the `agent_readiness_self_stop` Sentry
  signal is reachable (a real absent-`.git` dispatch produces an event with
  `gitKind:absent` OR `source:in-sandbox-backstop`) AND no silent recurrence on
  `754ee124`. Mirror `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`;
  `start=` pinned strictly after deploy. (Mechanical/Sentry-rate, distinct from the
  operator-confirm script above.)
- Tracker directive on #5733: `<!-- soleur:followthrough script=agent-readiness-absent-strand-observable-5733.sh earliest=<deploy+7d> secrets=SENTRY_AUTH_TOKEN -->` (the `follow-through` label is already on #5733).
- `SENTRY_AUTH_TOKEN` is already wired in `.github/workflows/scheduled-followthrough-sweeper.yml` (used by `reconcile-ff-only-sentry-4977.sh` / `ac8-founder-ambiguous-soak-5673.sh`); confirm at /work.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-044** (`status: accepted`) — its dispatch-readiness consequence
(§ "dispatch readiness MUST be (repo_status-ok AND physical `.git` present)",
line 552) currently describes the `ready`-but-`.git`-gone re-clone (Bug 2). Extend
the `## Decision` + `## Consequences` to record that the **shared dispatch
readiness gate (`evaluateAgentReadiness`) treats `absent`/`dir-invalid` as a
confirmed strand → honest-block + emit** (not only the `dir-valid`-corrupt slice),
and that the **agent's in-sandbox Step 0.0 empty (`2>/dev/null`-suppressed) output
is a strand signal** (the C2 backstop). This is an amendment, not a new ADR — the
ownership model is unchanged.

### C4 views
Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
during /work. Expected conclusion: **no C4 impact** — this fix changes the dispatch
readiness *verdict logic* and *observability*, not actors/systems/data-stores/access
relationships. The actors (operator/member, GitHub App installation), the
Concierge dispatch container, and the workspace data store are all already modeled
(ADR-044 connection edge is workspace-owned). The /work step MUST cite the
specific actors/systems/relationships checked (operator→Concierge dispatch,
Concierge→workspace `.git`, GitHub-App-install→workspace) and found already-modeled
before writing "no C4 impact"; if any is missing, add the `.c4` element/edge +
`views.c4 include` and run the c4 validation tests.

### Sequencing
Single atomic PR (TS-only, no migration). The post-deploy soak (AC10) is the only
time-gated criterion → handled by Follow-Through Enrollment, NOT a deferred issue.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** reviewed (plan-author sweep; deepen-plan domain agents run next per pipeline).
**Assessment:** Server-side dispatch-readiness + observability hardening on a
`single-user incident` brand-survival surface. Cross-cutting concerns: the gate
change affects 3 call sites (cold/warm/reconcile) that already consume the
`"block"` verdict — verify each. The C2 detector change risks false-positives on
unrelated `rev-parse` commands — bounded by the `isWorkTreeProbe` command guard
(deepen-plan to settle whether to tighten to the go.md compound shape). No new
data egress; reuses ADR-029 pseudonymization. CPO sign-off required (threshold).

### Product/UX Gate
**Mechanical UI-surface override:** Files to Edit/Create contain NO
`components/**`, `app/**/page.tsx`, `app/**/layout.tsx` — Product NONE. The only
user-facing surface is the existing honest RepoNotReadyError copy (unchanged
strings). No wireframe required.

## GDPR / Compliance
No regulated-data surface added (no schema/migration/auth/API-route change; no new
processing activity). New observability stays within the existing ADR-029
pseudonymization boundary. **Skip** — no Article 30 / lawful-basis trigger.

## Open Code-Review Overlap
None found touching `tool-labels.ts`, `git-worktree-validity.ts`,
`ensure-workspace-repo.ts` (verify with the `gh issue list --label code-review`
two-stage jq query at /work; record result).

## Test Scenarios
1. Absent `.git`, connected, dbReady → gate blocks + emits (no spawn).
2. dir-invalid `.git`, connected → gate blocks + emits.
3. dir-valid + host rev-parse `worktree` → ready (no regression).
4. dir-valid + `not-a-worktree` → blocks (existing 77e77c3 behaviour, no regression).
5. Inconclusive×2 → fail-open ready (no regression).
6. go.md Step 0.0 empty output → in-sandbox backstop emits.
7. Healthy compound `"false\ntrue"` → backstop does NOT fire.
8. Two workspaces, one installation, distinct repo_urls → each clones its own repo (real resolution, not all-stubbed).
9. Reconcile-absent (`phase:pre-heal`) → re-cloned via `!isReadyGitWorkTree`, NO self-stop emit (soak-signal guard).
10. D3 negative: a non-probe command embedding the rev-parse tokens with empty output → NOT a strand.

## Deepen Findings (2026-06-30)

### D2 call-site ordering — the load-bearing scoping (traced)
`evaluateAgentReadiness` is the SHARED helper across 3 callers with DIFFERENT
heal-ordering — the absent→`block`+emit change must be scoped accordingly:

| Caller | Gate call shape | absent reaches gate? | Correct behaviour for absent |
|---|---|---|---|
| **Cold** `cc-dispatcher.ts:2010` | **unconditional, POST-heal** (`ensureWorkspaceRepoCloned` ran at :1987) | YES | absent = heal already failed → **emit + `block`** (honest RepoNotReadyError). THE load-bearing fix — today this returns `"ready"` → doomed spawn. |
| **Warm** `cc-reprovision.ts:130` | gate called **only inside `if (isReadyGitWorkTree)`** | NO — absent routes straight to `ensureWorkspaceRepoCloned` heal | D2 is a **no-op** for warm-absent (no change needed; verify the test asserts warm-absent still heals, not blocks). |
| **Reconcile** `workspace-reconcile-on-push.ts:372` | **unconditional, PRE-heal**, then heals via `if (!isReadyGitWorkTree \|\| block)` | YES | reconcile is a **non-spawn sync surface** that heals absent anyway → a self-stop emit here is a **pre-heal false-"strand"**. **Do NOT fire the absent self-stop on this path.** |

**Refinement to Phase 2 (load-bearing):** make the absent/dir-invalid →
`block`+emit a property of the **agent-dispatch surfaces only**. Two acceptable
implementations (deepen/`work` to pick the simpler): (i) add an explicit
`emitStrandOnAbsent: boolean` (or `surface: "dispatch" | "reconcile"`) param to
`evaluateAgentReadiness`, default dispatch=emit, reconcile=no-emit; OR (ii) keep
`evaluateAgentReadiness`'s NEW absent→block+emit, and have the **reconcile caller
continue to route absent through its existing `!isReadyGitWorkTree` heal WITHOUT
consulting the gate's verdict for absent** (i.e. reconcile only needs the gate for
the `dir-valid`-corrupt confirm — its net-new coverage — and must not surface a
strand for a shape it heals one line later). The cold path keeps the
unconditional emit+block. Add a Phase-2 test asserting **reconcile-absent does NOT
emit `agent_readiness_self_stop`** (it heals) while **cold-absent DOES**.

### D1 cross-consumer blast radius (`hr-type-widening-cross-consumer-grep`)
`ensureWorkspaceRepoCloned`'s return value is consumed by **5+ call sites**:
`agent-runner.ts:1167` (legacy startAgentSession), `cc-dispatcher.ts:1987` (cold),
`cc-reprovision.ts:165` (warm), `workspace-reconcile-on-push.ts:379` (reconcile),
and `repo-readiness-self-heal.ts:250/276/311`. Flipping the connected+absent+
malformed-url case from `"ok"` → `"failed"` propagates to ALL of them. **Decision
for deepen/`work`:** because **D2 already honest-blocks absent at the cold gate**
(the user-facing strand fix), D1's behaviour change is largely redundant — strongly
consider **reducing D1 to the regression test only** (lock the per-workspace
invariant) and DROPPING the `ensure-workspace-repo.ts` benign-skip→failed edit,
unless the 5-consumer sweep proves every caller already treats `"failed"` for that
narrow case correctly. The malformed-url case is also rare (the url passed the
connect-time allowlist) — YAGNI favours test-only D1.

### Precedent-diff (no novel pattern)
The emit/block/fail-open shape mirrors the existing 77e77c3 `dir-valid`-corrupt
path (same `reportAgentReadinessSelfStop` + `RepoNotReadyError` precedent at
`cc-dispatcher.ts:2017`, `cc-reprovision.ts:144`, `workspace-reconcile-on-push.ts:386`).
No new SQL/lock/atomic-write pattern. D3's empty-output detector reuses the
existing `isWorkTreeProbe` command-guard precedent.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan`
  Phase 4.6 — this one is filled (threshold: single-user incident).
- **Do NOT re-fix the founder-ambiguity webhook path** — it is already repo-scoped
  on main and stopped 2026-06-29; re-fixing it targets a path that does not
  execute on the affected surface (the recurring wrong-layer trap).
- The C2 detector empty-output rule must keep the `isWorkTreeProbe` command guard
  or it false-positives any command with empty output. Verify the healthy compound
  `"false\ntrue"` case stays non-strand (contains `true`).
- Test paths MUST live directly under `apps/web-platform/test/` (vitest `include:`
  glob) — a co-located `server/*.test.ts` is silently never run.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT
  `npm run -w`); tests run via `./node_modules/.bin/vitest run <path>` (NOT `bun test`).
- PR body: `Ref #5733`, never `Closes` (closure gated on the 7-day soak).
