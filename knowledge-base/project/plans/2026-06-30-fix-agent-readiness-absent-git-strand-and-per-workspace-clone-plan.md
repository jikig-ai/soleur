---
title: "fix: in-process dispatch-time repo re-clone (D0) + absent-.git strand heal/block + observable backstop (Ref #5733)"
date: 2026-06-30
issue: 5733
branch: feat-one-shot-5733-founder-resolve-multiworkspace-clone
lane: cross-domain  # no spec.md present → defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: bug
status: draft
---

# fix: in-process dispatch-time repo re-clone (D0) + absent-`.git` strand heal/block + observable backstop (Ref #5733)

## Enhancement Summary

**Deepened on:** 2026-06-30 (re-deepened after operator course-correction — the
fix must actually RE-LAND the repo, not just honest-block).
**Hard gates:** 4.6 User-Brand (PASS, single-user incident), 4.7 Observability
(PASS, 5 fields, no-ssh), 4.8 PAT-shape (PASS), 4.9 UI-wireframe (PASS — no UI
surface).

### Key Improvements
1. **D0 — the actual unblock (operator-mandated).** Observability + honest-block
   alone leaves the operator stranded forever. D0 adds an **in-process,
   dispatch-time guaranteed re-clone** into the agent's OWN `workspacePath`
   (same process → same filesystem the agent reads), keyed on the workspace's own
   `(github_installation_id, repo_url)` (founder/membership-independent), acting on
   **disk reality not the `repo_status='ready'` DB flag**, with **LOUD failure**
   (a distinct `repo_clone_failed` Sentry event + `repo_error` write + honest-block)
   — never a benign-skip, never swallowed.
2. **Prod-forensic root cause (2× live passes):** reconcile-on-push FIRES and
   selects 754ee124 on every push (45 events/48h, latest today 14:44, op
   `ownerless-reconcile`) yet `ensureWorkspaceRepoCloned` produces ZERO telemetry,
   the `.git` stays absent, `repo_status='ready'`/`repo_error=null`, and the
   operator reports **`/api/repo/setup` reconnect has NEVER landed the repo**. So
   the clone path itself is broken for this workspace — either (a) it writes to a
   different process/container/`WORKSPACES_ROOT` mount than the agent reads, or (b)
   it silently fails while the DB shows ready. D0's in-process + loud design is
   robust to BOTH.
3. **The owner-canary drift (#5591):** the workspace's `owner` member rows are
   workspace-IDs (754ee124 self + 52af49c2/chatte), not resolvable user accounts —
   so any heal that resolves a *founder user* to clone on-behalf-of finds nobody.
   D0 clones from the workspace's OWN install column, never founder resolution.

### New Considerations Discovered
- The loud founder-ambiguity Sentry issue (1901 lifetime, **stopped 06-29**) is a
  separate already-fixed webhook path — NOT the freeze cause (Research Reconciliation).
- `754ee124` is NOT solo (4 members, 2 owners) and its real-user accounts are
  `member`-role — so a membership-resolved install can come back NULL on a member
  dispatch (a benign-skip path D0 must close).

## Overview

Workspace `754ee124` (→ `jikig-ai/soleur`) strands `/soleur:go` at Step 0.0: the
agent dispatches into `/workspaces/754ee124` whose on-disk `.git` is **ABSENT**
(no repo on disk — NOT the corrupt/`.git`-present class the just-merged 77e77c3 fix
targeted), the agent's in-bwrap `git rev-parse` reports no work tree, and the agent
self-stops with the honest "your workspace isn't ready" message — **emitting ZERO
server-side Sentry events**. `repo_last_synced_at` is frozen at 2026-06-29 because
the only writer is the agent's own in-workspace `git pull/push`
(`session-sync.ts`), which never runs when the repo never lands. Live forensics +
the operator confirm **every re-clone mechanism (reconcile-on-push AND
`/api/repo/setup` reconnect) has failed to land the repo on the agent's disk.**

This plan delivers four server-side TypeScript fixes (no DDL):

0. **D0 (PRIMARY — the actual unblock).** **HARDEN the EXISTING in-process cold
   self-heal** (`cc-dispatcher.ts:1987` already runs `ensureWorkspaceRepoCloned`
   in-process, before `query()`, into the agent's own `workspacePath` — this is the
   right SITE; do NOT add a second clone path). The gap is that its install comes
   from the *dispatching user's* membership-resolved path which returns **NULL for a
   `member`-role user** → silent benign-skip. D0 fixes that site to: if `.git` is
   absent at `workspacePathForWorkspaceId(activeWorkspaceId)`, clone using the
   workspace's own
   `(github_installation_id, repo_url)` (server-derived, founder/membership-
   independent) and a credential helper (`gitWithInstallationAuth`, token via
   `GIT_ASKPASS` env, never in URL/stderr per `session-sync.ts`/ensure-workspace-repo
   precedent). Do NOT trust `repo_status='ready'` over the on-disk reality; do NOT
   benign-skip. On ANY clone failure (non-zero exit / stderr), emit a **distinct
   loud `repo_clone_failed`** Sentry event (sanitized — no token), write
   `repo_error`, and honest-block — never swallow, never mark ready. This lands the
   repo where the agent reads it regardless of divergence (a) or silent-failure (b);
   if it genuinely can't clone, the next attempt surfaces the real error.
1. **D2 (now the FALLBACK).** Harden `evaluateAgentReadiness` so an **absent**
   (and **dir-invalid**) `.git` — i.e. D0's clone genuinely failed — emits
   `agent_readiness_self_stop` and **honest-blocks** instead of greenlighting a
   doomed agent spawn.
2. **D3.** Fix `isInSandboxRevParseStrand` (C2 detector) to recognise the
   **stderr-suppressed empty output** that `go.md` Step 0.0 produces, so the strand
   is queryable for ANY on-disk shape.
3. **D1.** Per-workspace clone regression test — now load-bearing as the
   **founder/membership-INDEPENDENCE** proof (a member/co-owner/canary-drifted
   workspace still clones from its own columns), not merely a lock.

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

## Root Cause — Phase-0 forensic findings (2× live prod passes)

**The re-clone never lands on the agent's filesystem; the DB stays a false `ready`.**

- **Reconcile fires + selects 754ee124 on every push, but no clone telemetry.**
  Sentry `WEB-PLATFORM-B` "owner-less workspace reconciled" — 423 lifetime, **45 in
  48h, latest today 2026-06-30T14:44**, tags `inngest.fn_id=workspace-reconcile-on-push`,
  `workspaceId=754ee124`, `installationId=122213433`, `fullName=jikig-ai/soleur`,
  real `headSha`. Code-confirmed: the owner-less branch is a non-paging warn
  (`workspace-reconcile-on-push.ts:340`) with **no short-circuit** — execution
  reaches the clone gate at `:378`. Yet `feature=ensure-workspace-repo` (ops
  `clone`/`corrupt-worktree-block`/`gitdir-pointer-rm`/`validate-repo-url`) has
  **ZERO events**. A successful clone is silent (pino only); a failed clone emits
  `op:clone`. Zero events ⇒ the reconcile clone either succeeded on a filesystem
  the agent does not read, or the gate found the worker's `.git` valid (sync path).
- **`repo_status='ready'`, `repo_error=null`** for 754ee124 (and 52af49c2/chatte),
  `repo_last_synced_at` frozen 2026-06-29 — a false `ready` that no failure path
  flips (reconcile's F4 team-posture never writes `error`).
- **Owner-canary drift (#5591):** the `owner` member rows for 754ee124 are
  workspace-IDs (754ee124 self + 52af49c2/chatte), not real user accounts; the only
  real-user IDs are `member`-role. Founder/owner resolution finds nobody.
- **Operator fact:** `/api/repo/setup` reconnect (wipe-and-reclone) has **NEVER**
  landed the repo. ⇒ the clone path itself is broken for this workspace —
  either **(a)** it writes to a different process/container/`WORKSPACES_ROOT` mount
  than the agent reads, or **(b)** it silently fails while the DB shows ready.

**Why prior in-process self-heals don't save it:** the cold self-heal
(`graftReadyButGitAbsent`) and warm (`cc-reprovision`) clone using the *dispatching
user's* membership-resolved install (`resolveInstallationId`/`resolveEffective…`),
which can return **NULL for a `member`-role user** → `ensureWorkspaceRepoCloned`
benign-skips at `ensure-workspace-repo.ts:152` (`installationId===null → return "ok"`,
silent, no clone). And the post-heal gate (`cc-dispatcher.ts:2010`,
`evaluateAgentReadiness`) returns `"ready"` for the resulting `absent` shape
(deliverable-2 gap) → doomed spawn → `go.md` Step 0.0 strands → C2 misses the empty
output (deliverable-3 gap) → **silent forever**.

**D0 closes this at the only place guaranteed same-FS-as-agent:** an in-process
clone into the agent's own `workspacePath`, keyed on the workspace's own columns
(never the user's membership-resolved install, never founder), loud on failure.

> **Phase-0 /work verification (NOT a blocker; design is robust to both):** confirm
> whether the Inngest reconcile worker and the WS-dispatch share one `/workspaces`
> (single replica/mount) or diverge (multi-replica / per-replica local disk). A
> follow-up read-only forensic (`server_name` variance across the 754ee124 reconcile
> events; `kb_sync_history` ok/error rows) is in flight; record its verdict but do
> not gate D0 on it — D0's in-process placement lands the repo either way.

## Implementation Phases (TDD — failing tests FIRST per `cq-write-failing-tests-before`)

### Phase 0 — Preconditions (no code)
1. Confirm `apps/web-platform/test/` vitest discovery globs include the new test
   paths (`vitest.config.ts` `include:` → `test/**/*.test.ts`). All new tests live
   directly under `test/`.
2. Typecheck baseline green: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
3. Read the precedents D0 reuses: `ensure-workspace-repo.ts:148-356` (the existing
   in-process clone — `gitWithInstallationAuth`, `--depth 1`, `--`-guard,
   github-https allowlist, atomic `.git`-last rename), `session-sync.ts`
   credential helper, and the workspace-install service-read path
   (`resolve_workspace_installation_id` RPC — confirm whether it returns the
   install for a `member`-role caller, not only owners; if owner-only, D0 reads the
   install via the service-role workspaces column instead).

### Phase 1 — Deliverable D0 (PRIMARY — in-process dispatch-time re-clone): RED → GREEN
The reliable lander. Place it in `cc-dispatcher`'s cold factory, in the SAME
process that constructs the agent sandbox (so the clone target == the agent's read
path by construction: both are `workspacePathForWorkspaceId(activeWorkspaceId)` =
`<WORKSPACES_ROOT>/<id>`).
- **RED:** `test/dispatch-inprocess-reclone.test.ts` — with an injected clone seam +
  a temp workspace whose `.git` is absent and a connected workspace row
  (`github_installation_id` + `repo_url` on the workspace's OWN row):
  - asserts the clone is invoked with the workspace's OWN install + repo_url (NOT
    the dispatching user's membership-resolved install) and targets exactly
    `workspacePath`;
  - asserts that when `resolveInstallationId` (the user/membership path) returns
    NULL but the workspace's own column is non-null, the clone STILL runs (closes
    the member-null benign-skip);
  - asserts that `repo_status='ready'` does NOT short-circuit the clone when `.git`
    is absent on disk (disk reality wins);
  - asserts that on clone FAILURE a distinct `repo_clone_failed` event fires (with
    a SANITIZED reason — assert the token never appears) AND `repo_error` is written
    AND the dispatch honest-blocks (RepoNotReadyError) — never returns ready;
  - asserts an **id-shape guard**: `activeWorkspaceId` must match the UUID shape
    before it is interpolated into the clone path (no path traversal / injection).
- **GREEN (harden the EXISTING site — do NOT add a second clone call):** the cold
  path ALREADY calls `ensureWorkspaceRepoCloned` in-process at `cc-dispatcher.ts:1987`
  (and `resolveRepoReadinessWithSelfHeal`/`graftReadyButGitAbsent` before it). D0
  modifies THAT path — it must not introduce a duplicate clone. Changes:
  1. resolve the install from the **workspace's own `github_installation_id`**
     (server-derived service read) when the user/membership resolution is null, so a
     connected workspace always has a non-null install to clone with;
  2. promote the silent `op:clone` `reportSilentFallback` to (or add alongside it)
     a **distinct loud `repo_clone_failed`** event so a real clone failure is a
     first-class queryable signal (today a *success* is silent and a *failure* shares
     the generic `op:clone` — D0 needs a dedicated failure op for the discoverability
     query + alert);
  3. on failure, write `repo_error` via `set_repo_status(error, <sanitized reason>)`
     so the DB stops lying `ready` and the gate reads an honest reason next dispatch.
  Token handling unchanged from precedent (env `GIT_ASKPASS`, never URL/argv/stderr;
  `--`-guard; github-https allowlist). NO new migration.
- **Warm/reconcile parity (in-scope for D0):** apply the same "clone from the
  workspace's own install column, never the membership-null" rule to `cc-reprovision`
  (warm) so a warm-turn member dispatch also lands the repo. (Reconcile already
  passes the push-event install; D0 does not change it, but un-blinds its outcome —
  see Observability.)

### Phase 2 — Deliverable D3 (C2 detector): RED → GREEN
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

### Phase 3 — Deliverable D2 (absent-`.git` strand gate, FALLBACK when D0 fails): RED → GREEN
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

### Phase 4 — Deliverable D1 (founder/membership-INDEPENDENT clone): TEST-ONLY
Now load-bearing as the **founder-independence proof** for D0 (not merely a lock).
The `ensure-workspace-repo.ts` benign-skip→`"failed"` behaviour change stays DROPPED
(D0 + D2 cover the outcome; 5-consumer blast radius).
- **RED:** `test/ready-clone-per-workspace.test.ts`: (a) two workspace ids sharing
  ONE installation id but DIFFERENT repo_urls each resolve their OWN repo_url + CWD
  and clone independently (no collapse, no `>1`); (b) the **founder-independence**
  case: a workspace whose `owner` member rows are workspace-IDs (the #5591 canary
  drift) AND whose dispatching user is `member`-role STILL clones — because D0
  resolves the install from the workspace's OWN `github_installation_id` column, not
  from owner/founder resolution or the membership-null user path. **Must exercise
  REAL workspace-id keying** in at least one resolver (not all-three-stubbed, a
  tautology). One installation, two ids is enough.

### Phase 5 — Full-suite + typecheck gate
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/dispatch-inprocess-reclone.test.ts test/in-sandbox-revparse-strand.test.ts test/agent-readiness-absent-git.test.ts test/ready-clone-per-workspace.test.ts test/ensure-workspace-repo.test.ts test/tool-labels.test.ts test/cc-dispatcher-self-heal-observability.test.ts test/cc-reprovision.test.ts`
- Then the broader affected suites (`cc-dispatcher*`, `repo-readiness*`,
  `cc-reprovision*`, `workspace-reconcile*`) to catch the orphan/exhaustiveness
  suites the targeted run misses.

## Files to Edit
- `apps/web-platform/server/cc-dispatcher.ts` — **D0 (primary):** in-process guaranteed re-clone before `query()` (cold path) keyed on the workspace's own install column, loud `repo_clone_failed` on failure + `repo_error` write + honest-block; id-shape guard. Also pass D2's `phase:"post-heal"` at the gate (`:2010`).
- `apps/web-platform/server/ensure-workspace-repo.ts` — **D0:** thread the workspace's-own-install fallback so a `member`-null user install does not benign-skip a CONNECTED workspace (resolve the install from the workspace column when the passed `installationId` is null); add the distinct `repo_clone_failed` loud-failure emit (today `op:clone` is generic + a *success* is silent).
- `apps/web-platform/server/cc-reprovision.ts` — **D0:** warm-turn parity — clone from the workspace's own install column (not the membership-null user path); pass D2 `phase`.
- `apps/web-platform/server/repo-readiness-self-heal.ts` — **D0:** `graftReadyButGitAbsent` resolves the install from the workspace's own column when the threaded install is null (closes the member-null silent benign-skip on the cold/warm heal).
- `apps/web-platform/server/tool-labels.ts` — D3: collapse `isInSandboxRevParseStrand` to the no-`true` negation (verdict replacement) + anchor the command guard.
- `apps/web-platform/server/git-worktree-validity.ts` — D2: `evaluateAgentReadiness` absent/dir-invalid → emit + block; add `phase: "post-heal" | "pre-heal"` to `AgentReadinessContext` so the absent emit fires only on a terminal (post-heal) verdict.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — pass `phase:"pre-heal"` (reconcile-absent heals without a false-positive self-stop). (Reconcile clone unchanged; its outcome is now un-blinded via the D0 `repo_clone_failed` emit inside `ensureWorkspaceRepoCloned`.)
- `apps/web-platform/server/repo-resolver-divergence.ts` (or a sibling emit module) — add the `repo_clone_failed` reporter (distinct op/issue-group; sanitized reason; ADR-029 pseudonymization).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amend the dispatch-readiness consequence (§ line 552): add D0 (in-process re-clone from the workspace's own install column is the authoritative same-FS lander), gate fires for `absent`/`dir-invalid`, per-path heal ordering, in-sandbox empty-output backstop.

## Files to Create
- `apps/web-platform/test/dispatch-inprocess-reclone.test.ts` — D0.
- `apps/web-platform/test/in-sandbox-revparse-strand.test.ts` — D3.
- `apps/web-platform/test/agent-readiness-absent-git.test.ts` — D2.
- `apps/web-platform/test/ready-clone-per-workspace.test.ts` — D1.
- (`apps/web-platform/test/ensure-workspace-repo.test.ts` extended for the D0 install-from-workspace-column + loud-failure behaviour; runs in Phase 5.)

No new migration (all columns exist; `repo_error` shipped in mig 110/113). No new
infrastructure.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC0a (D0 — lands the repo):** for a connected workspace (own `github_installation_id` + `repo_url`) with `.git` ABSENT, the cold dispatch performs an in-process clone into exactly `workspacePath`; on success `.git` is present at the agent's read path before `query()` constructs. (vitest, injected clone seam)
- [ ] **AC0b (D0 — founder/membership independence):** when `resolveInstallationId` (user/membership) returns NULL but the workspace's own install column is non-null, the clone STILL runs (no benign-skip). (vitest)
- [ ] **AC0c (D0 — disk reality over DB):** `repo_status='ready'` does NOT short-circuit the clone when `.git` is absent on disk. (vitest)
- [ ] **AC0d (D0 — LOUD failure, no swallow):** on clone failure a distinct `repo_clone_failed` Sentry event fires with a SANITIZED reason (assert the installation token NEVER appears in the event), `repo_error` is written, and the dispatch honest-blocks (RepoNotReadyError) — never returns ready. (vitest)
- [ ] **AC0e (D0 — id-shape guard):** a non-UUID `activeWorkspaceId` is rejected before path interpolation (no traversal). (vitest)
- [ ] AC1: `isInSandboxRevParseStrand("…rev-parse --is-inside-work-tree…", "")` returns `true`; healthy `"false\ntrue"` → `false`; bare-repo `"true\nfalse"` → `false`; a non-probe command embedding the tokens with empty output → `false`. (vitest)
- [ ] AC2: `evaluateAgentReadiness` returns `"block"` + fires `reportAgentReadinessSelfStop({gitKind:"absent",…,source:"host-pre-heal"})` for absent (post-heal/cold); same for `dir-invalid`; `dir-valid`+`worktree`→`"ready"`; `inconclusive`×2→`"ready"`. (vitest)
- [ ] AC3: two connected workspaces, one installation, distinct repo_urls each resolve their OWN repo_url + CWD and clone independently (no collapse) — REAL workspace-id resolution, not all-stubbed; PLUS the founder-independence case (canary-drifted owner rows + member dispatcher still clones from the workspace's own column). (vitest)
- [ ] AC5: **cold** (`phase:post-heal`)-absent (after D0's clone genuinely failed) emits `agent_readiness_self_stop` + honest RepoNotReadyError; **reconcile** (`phase:pre-heal`)-absent does NOT emit a self-stop (heals via `!isReadyGitWorkTree`); **warm**-absent routes to heal. (vitest, 3 call-site assertions)
- [ ] AC6: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] AC7: targeted + affected vitest suites pass (Phase 5 list).
- [ ] AC8: ADR-044 dispatch-readiness consequence amended (D0 in-process re-clone + absent/dir-invalid gate + empty-output backstop).
- [ ] AC9: PR body uses **`Ref #5733`** (NOT `Closes`) — closure is gated on the post-deploy soak below.

### Post-merge (operator / automated)
- [ ] AC10a (D0 lands the repo — the operator-facing success): after deploy, a dispatch into 754ee124 lands `.git` and `repo_last_synced_at` advances past 2026-06-29 (PostgREST read, no SSH); OR a `repo_clone_failed` Sentry event names the real clone error (no more silent strand). Soak: Follow-Through Enrollment.
- [ ] AC10b: a genuine absent-`.git` strand (D0 clone failed) is queryable as `agent_readiness_self_stop` (`gitKind:absent`) / `repo_clone_failed`. Verify via Sentry (no SSH).
- [ ] AC10c (/work Phase-0): record the FS-divergence verdict (single vs multi-replica `/workspaces`); if multi-replica, file a follow-up for a same-container periodic backstop (D0's in-process dispatch heal already covers the interactive path).

## Observability

```yaml
liveness_signal:
  what: "repo_last_synced_at advances for 754ee124 after deploy (the agent now lands the repo + syncs) — primary D0 success signal; plus repo_clone_failed / agent_readiness_self_stop Sentry events make every failure queryable"
  cadence: per cold dispatch into an absent-.git connected workspace
  alert_target: "Sentry issue repo_clone_failed (PAGES — a genuine clone failure is operator-actionable); agent_readiness_self_stop (query-only discoverability)"
  configured_in: "server/repo-resolver-divergence.ts (reportAgentReadinessSelfStop + new repo_clone_failed reporter); searchable via tags op/gitKind/source"
error_reporting:
  destination: Sentry via reportSilentFallback (ADR-029 pseudonymization boundary; token NEVER in the event — sanitized stderr only)
  fail_loud: true  # D0 clone failure → distinct repo_clone_failed event + repo_error write + honest RepoNotReadyError; never silent, never marks ready
failure_modes:
  - mode: "D0 in-process clone fails (token/network/entitlement)"
    detection: "cc-dispatcher D0 clone returns failed → distinct repo_clone_failed emit + set_repo_status(error)"
    alert_route: "Sentry repo_clone_failed (paging) + repo_error read back by the gate"
  - mode: "absent .git STILL at dispatch gate (D0 clone genuinely failed)"
    detection: "evaluateAgentReadiness probeGitWorktreeShape kind==absent → emit + block"
    alert_route: "agent_readiness_self_stop (gitKind:absent, source:host-pre-heal)"
  - mode: "in-sandbox Step 0.0 empty rev-parse output"
    detection: "isInSandboxRevParseStrand empty/no-true output"
    alert_route: "agent_readiness_self_stop (source:in-sandbox-backstop)"
  - mode: "member-null install on a connected workspace (the prior silent benign-skip)"
    detection: "D0 resolves install from the workspace's own column; if still null → connected-null-install-at-dispatch emit"
    alert_route: "repo_resolver_divergence (connected-null-install-at-dispatch)"
logs:
  where: Sentry (reportSilentFallback) + pino structured logs (createChildLogger)
  retention: existing Sentry/Better Stack retention (unchanged)
discoverability_test:
  command: "PostgREST: GET /rest/v1/workspaces?id=eq.754ee124…&select=repo_last_synced_at,repo_status,repo_error (read-only, no ssh); AND Sentry search 'repo_clone_failed' statsPeriod=7d"
  expected_output: "repo_last_synced_at advances past 2026-06-29 after a post-deploy dispatch (repo landed); OR a repo_clone_failed event names the real clone error (no more silent strand)"
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
the `## Decision` + `## Consequences` to record:
- **D0 (the authoritative lander):** the repo re-clone that the agent depends on
  MUST run **in the same process that constructs the agent sandbox** (cc-dispatcher
  cold path), cloning into the agent's own `workspacePath`, keyed on the
  **workspace's own `github_installation_id`** (never the dispatching user's
  membership-resolved install, never founder/owner resolution — the #5591
  owner-canary drift makes founder resolution unusable). Out-of-process re-clones
  (Inngest reconcile, cron) are best-effort backstops only — they are not
  guaranteed to share the agent's filesystem.
- The DB `repo_status` is NOT authoritative over on-disk reality: an absent `.git`
  is re-cloned regardless of a stale `ready`; a genuine clone failure writes
  `repo_error` and surfaces a distinct `repo_clone_failed` signal.
- The shared gate (`evaluateAgentReadiness`) treats `absent`/`dir-invalid` as a
  confirmed strand → honest-block + emit (fallback when D0's clone fails), and the
  agent's in-sandbox Step 0.0 empty (`2>/dev/null`) output is a strand signal (C2).
Amendment, not a new ADR — the ownership model is unchanged.

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

**Domains relevant:** Engineering (CTO), Security (D0 is a new clone write-path with
a private-repo installation token), Data-integrity (D0 writes `repo_error` / acts on
the `repo_status` vs disk divergence).

### Engineering (CTO)
**Status:** reviewed (plan-author sweep + architecture/simplicity agents; data-integrity + security agents run in this re-deepen).
**Assessment:** D0 adds an in-process clone WRITE path at dispatch time on a
`single-user incident` surface. Cross-cutting concerns the review agents must cover:
(1) **Security** — the install token rides `GIT_ASKPASS` env (never URL/argv/stderr,
per `ensure-workspace-repo.ts`/`git-auth.ts` precedent); the `repo_clone_failed`
event must carry a SANITIZED reason (no token); `repo_url` is github-https-allowlisted
+ `--`-guarded; `activeWorkspaceId` is UUID-shape-guarded before path interpolation
(no traversal); the workspace-install service read is keyed on a server-derived
workspace id, never request-supplied. (2) **Data-integrity** — D0 writes
`repo_error` + flips a false `ready` to `error` on failure; confirm this does not
clobber a legitimate concurrent connect/disconnect (reuse the existing
`set_repo_status` RPC + the clone's `.git`-sentinel atomic rename; no new lock).
(3) reading the workspace's own `github_installation_id` requires service-role (the
column is REVOKE'd from `authenticated`) — confirm the read path is allowlisted
(mirror `resolve_workspace_installation_id`'s SECURITY DEFINER membership-check, or
the service-role workspaces read used by reconcile). (4) D2 gate `phase`-scoping +
C2 false-positive bound as before. CPO sign-off required (threshold).

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
