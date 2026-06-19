---
title: "fix: Concierge corrupt-worktree dispatch — revalidate & re-clone (.git validity, not mere presence)"
date: 2026-06-19
type: fix
branch: feat-one-shot-corrupt-worktree-revalidate-reclone
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: single-domain
status: draft
adr_refs:
  - knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md
---

# 🐛 fix: Concierge spawns a repo-less agent for a FULLY-CONNECTED workspace whose on-disk `.git` is corrupt

## Enhancement Summary

**Deepened on:** 2026-06-19
**Review agents:** architecture-strategist, data-integrity-guardian, observability-coverage-reviewer (single-user-incident threshold → substance-level triad)

The deepen-plan review materially reshaped the design. The plan-v1 "rename
`gitDirExists`→`gitDirValid`, no logic change" framing was **wrong** and would
have shipped three serious defects. Key corrections folded in:

1. **TWO distinct probes, not one inverted seam.** The fast-path gate uses a
   synchronous structural check; the destructive `rm` is gated on a **positive
   empty-`.git` fingerprint** (NOT the negation of the validity probe); the
   recovery-path discriminator uses a `git rev-parse` subprocess (off the hot
   path). This closes the catastrophic data-loss vectors below.
2. **The null-install divergence gates stay on TRUE ABSENCE.** Inverting them to
   "invalid" silently re-routed a corrupt-`.git` + null-install workspace to the
   wrong op (`connected-null-install-at-dispatch`) with no removal/re-clone.
3. **rm is concurrency-guarded** (serialized via `withWorkspacePermissionLock`)
   so a racing loser cannot delete the winner's freshly-valid `.git`.
4. **The corrupt path does NOT route through `failHonestly`'s `setRepoStatus`
   member-write** without an explicit membership-write posture decision.
5. **The emit is wired to a NEW call site** (the corrupt branch has no
   `reportDivergence` today); failure-mode alert routes corrected; emit is
   **warn-on-detect / page-on-unrecovered** to avoid paging a self-healed fault.
6. **The operator's real `.git` shape on `754ee124` MUST be inspected** at /work
   Phase 0 — the structural check under-detects populated-but-broken `.git`, so
   AC13 needs a concrete pre-check, not an either-way assertion.

## Deepen-Plan Review Findings (P0/P1 — folded into the design below)

| # | Sev | Source | Finding → Resolution |
| --- | --- | --- | --- |
| F1 | **P0** | arch + data-integrity + obsv | Seam inversion is NOT a no-op at the null-install divergence gates (`repo-readiness-self-heal.ts:170`, `:194-197`): a corrupt `.git` + null install would trip `connected-null-install-at-dispatch` (wrong op, no rm). **Resolution:** keep those gates on a distinct `gitAbsent` (true absence) probe; introduce `gitInvalid` separately for the graft branches. Per-site analysis in Phase 2, not a rename sweep. |
| F2 | **P1 (worst-case)** | data-integrity | `rm` triggered by the *negation* of an `existsSync`-based probe destroys real commits on a transient EACCES/EIO blip, and rm's a valid gitdir-file (worktree/submodule) `.git`. **Resolution:** trigger `rm` ONLY on a POSITIVE empty-`.git` fingerprint (`.git` is a directory AND HEAD absent AND objects absent); distinguish ENOENT from EACCES (do NOT rm on EACCES); treat a `.git` *file* as non-removable. |
| F3 | **P1** | arch + data-integrity | remove-before-clone is a SECOND `.git` writer the sentinel never guarded; racer B can rm racer A's freshly-valid `.git`. **Resolution:** serialize the rm+reclone for the corrupt case under `withWorkspacePermissionLock(workspacePath, …)` (the escape hatch named at ensure-workspace-repo.ts:204 for exactly this premise change). |
| F4 | **P0** | arch | corrupt→`failHonestly` calls `setRepoStatus(error)`, reintroducing the member-write hazard `failConnectionUnresolved` was built to avoid (a member can flip a team workspace to `error`). **Resolution:** state the membership-write posture explicitly; for the corrupt-on-team case prefer emit-only (no `setRepoStatus`) unless the dispatching member is an Owner. |
| F5 | **P1** | obsv | The named emit site `graftReadyButGitAbsent` has NO `reportDivergence` today; the corrupt case (install non-null) never reaches the existing emit sites (they require install null). The §Observability failure-mode routes were wrong (`failHonestly` emits `feature=cc-dispatcher op=repo-readiness-self-heal`, NOT `op=self-heal-failed`). **Resolution:** add an explicit `reportDivergence("corrupt-worktree-at-dispatch", …)` at the new corrupt branch; correct the failure-mode routes; VERIFY `op=repo-readiness-self-heal` is under a paging alert (else the unrecovered failure is queryable but UN-paged). |
| F6 | **P1** | obsv + data-integrity | Structural check under-detects populated-but-broken `.git` (HEAD+objects present but packfile truncated / HEAD dangling) — `/soleur:go` Step 0.0 `rev-parse` still fatals, and AC5 never fires → silent. AC13 is unfalsifiable. **Resolution:** the recovery-path discriminator uses `git rev-parse --is-inside-work-tree` (off the hot path, allowed by AC7); inspect `754ee124`'s real `.git` at /work Phase 0; AC13 gets a concrete pre-check. |
| F7 | **P1** | obsv | emit-on-detection pages even when the re-clone self-heals (and the §Observability discoverability_test even says post-heal returns zero events — a contradiction). **Resolution:** emit at **warn** on detection (breadcrumb, search-only); reserve the **paging** event for the unrecovered branch. Carry `extra.recovered: true|false` so healed vs unhealed are triageable. |
| F8 | **P2** | obsv | The "reverse-guard" op-contract assertion is NET-NEW (not already present); the existing test only checks forward direction. **Resolution:** specify the mechanism (regex-parse the `RepoResolverDivergenceOp` union members; assert each ∈ `OPS ∪ EXCLUDED`; seed `EXCLUDED = []`). |
| F9 | **P2** | obsv | `discoverability_test.command` is prose, not executable. **Resolution:** make it a runnable `doppler run … scripts/sentry-issue.sh --search …` command (corrected in §Observability). |

## Overview

The cold Concierge dispatch (`apps/web-platform/server/cc-dispatcher.ts`) decides
whether a workspace needs repo self-heal using a **presence-only** check —
`existsSync(path.join(workspacePath, ".git"))` — at three gates:

1. `cc-dispatcher.ts:1783` — `needsSelfHeal = !repoReadiness.ok || !existsSync(<ws>/.git)`
2. `cc-dispatcher.ts:1823` — the `gitDirExists` seam wired into
   `repo-readiness-self-heal.ts` (`(p) => existsSync(path.join(p, ".git"))`)
3. `ensure-workspace-repo.ts:142` and `:239` — the idempotent `.git`-present
   early-returns inside `ensureWorkspaceRepoCloned` / `realGraftRepoClone`

A directory named `.git` that **exists but is not a valid git work tree** (a
partial/interrupted clone, or a leftover from a failed atomic-rename) reads
`true` from `existsSync`, so `needsSelfHeal` is `false`, the self-heal/graft is
**skipped entirely**, no clone is attempted, no error is set, **no Sentry signal
is emitted** (silent by construction), and the agent spawns into a corrupt repo.
`/soleur:go` Step 0.0 then runs `git rev-parse --is-inside-work-tree`, which
returns false / exit 128, and reports **"no git repository"**.

This is the **third distinct gap** in the ADR-044 dispatch-readiness lineage,
NOT a re-occurrence of either prior fix:

| Gap | Fixed | Distinguishing condition |
| --- | --- | --- |
| Null-install divergence (`connected-null-install-at-dispatch`) | 2026-06-18 | install resolves **NULL** at dispatch |
| Ready-but-`.git`-**gone** graft (Bug 2) | 2026-06-18 | `.git` is **cleanly absent** (`existsSync` false) |
| **Corrupt `.git` at dispatch (THIS PR)** | — | `.git` **exists but is invalid** (`existsSync` true, `rev-parse` false) |

The residual is already encoded as a passing test asserting the un-recovered
behavior: `cc-dispatch-repo-self-heal.test.ts:388` —
`"stale/corrupt .git (existsSync true, not a valid work tree) → documented residual: NOT auto-recovered"`.

**Fix:** replace the presence-only `.git` check with a worktree-**VALIDITY**
check everywhere it gates recovery; on an invalid `.git`, **remove** the corrupt
`.git` before re-cloning, then fail honestly (`RepoNotReadyError`) if still
invalid; emit a new **queryable + paging** Sentry op
`corrupt-worktree-at-dispatch` (routed through the existing feature-only
`repo_resolver_divergence` alert); flip the residual test RED→GREEN; preserve
the AC7 zero-await fast path for a VALID `.git`.

**Scope:** TS-only. No migration. No new infrastructure. No new vendor. No
regulated-data surface. No UI surface.

## Live Diagnosis (verified this session against prod Supabase)

- operator user id `52af49c2-d68e-477b-ba76-129e41807c7c`
- `user_session_state.current_workspace_id = 754ee124-706a-4f21-a4f4-e828257b0380`
  (the ACTIVE workspace)
- operator owns TWO "My Workspace" rows — solo `52af49c2` (`id == userId`) and
  `754ee124`. **BOTH** fully connected: `repo_url=https://github.com/jikig-ai/soleur`,
  `repo_status='ready'`, `github_installation_id=122213433` (NON-null),
  `repo_error` null.
- Sentry (org `jikigai-eu`): ZERO `repo_resolver_divergence` and ZERO
  `repo-readiness-self-heal` events in 24h → the failure is silent by
  construction (the `ready` fast-path never reaches a mirror, and the
  presence-only check fast-paths a corrupt `.git`).

**Root cause by elimination (all confirmed against live state):**
- install resolves NON-null + `repoUrl` present ⇒ NOT the divergence path.
- `repo_error` null + the agent WAS spawned (it ran Step 0.0 and failed) ⇒ the
  graft did not fail honestly.
- a cleanly-absent `.git` would re-clone-and-succeed (Bug 2 graft) or set
  `repo_error` ⇒ `.git` is NOT cleanly absent.
- ∴ the on-disk `.git` at `/workspaces/754ee124` **EXISTS but is
  INVALID/corrupt**, and the presence-only check treats it as healthy.

## Premise Validation (Phase 0.6)

All cited artifacts verified to exist on this branch / `origin/main`:

| Cited artifact | Status |
| --- | --- |
| `cc-dispatcher.ts:1783` `needsSelfHeal = !repoReadiness.ok \|\| !existsSync(<ws>/.git)` | **Confirmed** verbatim |
| `cc-dispatcher.ts:1823` `gitDirExists: (p) => existsSync(path.join(p, ".git"))` | **Confirmed** verbatim |
| `ensure-workspace-repo.ts:142` `.git`-present early return | **Confirmed** (`if (existsSync(join(workspacePath, ".git"))) return "ok";`) |
| `ensure-workspace-repo.ts:239` graft `.git`-sentinel re-check | **Confirmed** (`if (existsSync(join(workspacePath, ".git"))) return;`) |
| `cc-dispatch-repo-self-heal.test.ts:388` residual test | **Confirmed** verbatim title |
| `repo-resolver-divergence.ts` op union (3 ops) | **Confirmed** |
| `sentry-repo-resolver-divergence-alert-op-contract.test.ts` feature-only invariant | **Confirmed** (line ~69, `not.toMatch(/key\s*=\s*"op"/)`) |
| `go.md:24` Step 0.0 uses `git rev-parse --is-inside-work-tree` | **Confirmed** |
| ADR-044 Amendment 2026-06-18 `### Consequence — dispatch readiness MUST be (repo_status-ok AND physical .git present)` | **Confirmed** (ADR line 552) |
| Issue 4826 | NOT the work target (unrelated P3 nav-rail feature; the bug merely surfaced in a conversation titled "Fix Issue 4826"). Do NOT cite `Closes #4826`. |

No stale premises. The fix extends — does not contradict — the 2026-06-18
ready-clone remediation: it tightens the `.git`-presence sentinel that 2026-06-18
introduced into a `.git`-**validity** sentinel at the same three gates.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
| --- | --- | --- |
| "presence-only check at 3 gates" | Confirmed: cc-dispatcher:1783, the `:1823` seam, ensure-workspace-repo:142 + :239 | All 4 sites in `## Files to Edit` |
| "`gitDirExists` seam" | The seam is **synchronous** `(workspacePath: string) => boolean` (`RepoSelfHealSeams.gitDirExists`); injected as `vi.fn()` in tests; used at 5 sites incl. 2 null-install divergence gates that require TRUE ABSENCE | **(F1)** rename to `gitDirValid` (structural, sync) for the graft branches BUT keep a distinct `gitAbsent` seam for the null-install gates (:170,:194-197) — inverting them to "invalid" mis-routes corrupt+null-install. Per-site, not a sweep |
| "rm -rf the corrupt .git before re-clone" | `ensureWorkspaceRepoCloned:142` early-returns "ok" when `.git` exists; `rm` from `node:fs/promises` already imported (ensure-workspace-repo.ts:2, used at :244); `withWorkspacePermissionLock` exists (workspace-permission-lock.ts:53) | **(F2/F3)** rm fires ONLY on the POSITIVE empty-`.git` fingerprint (dir + HEAD ENOENT + objects ENOENT), NOT the negation of validity; run under `withWorkspacePermissionLock`; a populated-broken / EACCES / gitdir-file `.git` is honest-blocked, NOT rm'd |
| "reuse `reportRepoResolverDivergence` with a new op" | The Sentry alert (`issue-alerts.tf:568`) filters **feature-only** (`feature == "repo-resolver-divergence"`, no `op` filter); op-contract test lists 3 expected ops at line ~33 | Add `"corrupt-worktree-at-dispatch"` to the union + the op-contract `OPS` array. **ZERO Terraform change** — the feature-only filter auto-routes the new op (assert via the existing AC6 invariant) |
| "Start-Fresh `.git` must not be blown away" (ensure-workspace-repo.ts:115-120) | A Start-Fresh `.git` is a **valid** git work tree with no `origin` — `rev-parse --is-inside-work-tree` returns **true**, and a structural check (`.git/HEAD` + `.git/objects`) passes | The validity probe **preserves** Start-Fresh: it is valid, so it is NOT classified corrupt and NOT re-cloned. Load-bearing sharp edge (see Sharp Edges) |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator's own dogfood
workspace stays end-to-end unusable — every Concierge message spawns an agent
that reports "no git repository" at `/soleur:go` Step 0.0 and cannot branch /
commit / open a PR. The product is fully connected in the UI (repo shows
"ready") yet does nothing, with no error surfaced.

**If this leaks, the user's data/workflow is exposed via:** N/A — this is a
recovery/observability fix; no new data egress, no new persisted field, no new
external call. The only new emit is a fingerprint-deduped Sentry breadcrumb
carrying the two workspace ids + pseudonymized `userIdHash` (ADR-029), never
`repoUrl`/`installationId`/raw-userId (same shape as the existing divergence ops).

**Brand-survival threshold:** single-user incident — the operator's own workspace
is currently unusable. Post-deploy, the operator's next Concierge message MUST
self-heal (remove the corrupt `.git`, re-clone, spawn into a valid worktree) OR
fail honestly with a queryable Sentry signal — never silently re-spawn repo-less.

> CPO sign-off required at plan time before `/work` begins (threshold =
> single-user incident). `user-impact-reviewer` is invoked at review time.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — validity, not presence, at all gates.** The presence-only
  `existsSync(<ws>/.git)` check is replaced by a worktree-VALIDITY check at: (a)
  `cc-dispatcher.ts:1783` `needsSelfHeal`, (b) the `cc-dispatcher.ts:1823` seam
  wiring, (c) `ensure-workspace-repo.ts:142` early-return, (d)
  `ensure-workspace-repo.ts:239` graft sentinel re-check. Verify: `git grep -n
  'existsSync(\(path\.\)\?join([^)]*".git")' -- apps/web-platform/server/cc-dispatcher.ts apps/web-platform/server/ensure-workspace-repo.ts apps/web-platform/server/repo-readiness-self-heal.ts`
  returns ZERO raw presence-only `.git` gates (the validity helper is the only
  caller; `askpassDir`/`gitDir` non-gate uses at cc-dispatcher:2135 are exempt
  and use a different path — see AC1-note).
- [x] **AC1-note** — the cc-dispatcher:2135 `existsSync(gitDir)` (askpass dir
  resolution) is NOT a recovery gate and is OUT of scope; the grep predicate or
  its exclusion must not false-flag it.
- [x] **AC2 — corrupt `.git` is needs-recovery (install NON-null path).** Given a
  connected (`installationId` **non-null** + `repoUrl` + `repo_status='ready'`)
  workspace whose `.git` is invalid (fast-path structural check fails),
  `resolveRepoReadinessWithSelfHeal` does NOT fast-path `{ ok: true }`; it routes
  to the corrupt-worktree graft branch (a sibling of `graftReadyButGitAbsent`).
  **F1:** the null-install divergence gates (`repo-readiness-self-heal.ts:170`,
  `:194-197`) MUST continue to test TRUE ABSENCE (`gitAbsent`), so a corrupt
  `.git` + null install does NOT incorrectly emit `connected-null-install-at-dispatch`.
- [x] **AC3 — remove-before-reclone on a POSITIVE empty-`.git` fingerprint
  (F2/F3).** The destructive `rm` fires ONLY when the corruption fingerprint is
  positively matched: `.git` exists AND is a **directory** AND `.git/HEAD` is
  ENOENT AND `.git/objects` is ENOENT. It MUST NOT fire on the *negation* of the
  validity probe (an EACCES/EIO blip, or a `.git`-as-FILE gitdir/worktree, must
  NOT be removed). On the fingerprint match, the rm+reclone runs **serialized
  under `withWorkspacePermissionLock(workspacePath, …)`** so a racer cannot
  delete a winner's freshly-valid `.git`. After re-clone, if the worktree is
  still invalid, fail honestly (`RepoNotReadyError`) — never spawn. If the rm
  itself fails (EACCES/EBUSY), emit + fail honestly (do NOT loop).
- [x] **AC4 — Start-Fresh preserved.** A VALID `.git` with no `origin` (Start-
  Fresh) is classified valid → NOT re-cloned, NOT removed. Regression test
  asserts a workspace with a valid `.git` (HEAD + objects present) fast-paths
  `{ ok: true }` with zero clone calls.
- [x] **AC5 — new observability op, wired to a NEW call site (F5/F7).** A
  corrupt-`.git` detection at dispatch emits
  `seams.reportDivergence("corrupt-worktree-at-dispatch", userId, workspaceId)`
  from a NEW call inside the corrupt-worktree graft branch (the existing emit
  sites at `:199`/`:304` require `installationId === null` and are never reached
  by the install-non-null corrupt case). Deduped once per
  `(op, userId, workspaceId)` fingerprint. Emit at **warn/breadcrumb on
  detection** (search-only); the **paging** event is the unrecovered branch.
  Carry `extra.recovered: true|false` (or a distinct recovered-op) so a
  self-healed corruption is triageable separately from an unrecovered one (F7).
  `"corrupt-worktree-at-dispatch"` is added to the `RepoResolverDivergenceOp`
  union (`repo-resolver-divergence.ts:27`) AND to the `OPS` array in the alert
  op-contract test (line ~33).
- [x] **AC6 — feature-only alert auto-covers the new op (no Terraform change).**
  `sentry-repo-resolver-divergence-alert-op-contract.test.ts` still passes: the
  alert block contains `value = "repo-resolver-divergence"` and NO `key = "op"`
  filter. The op-contract test additionally asserts the **reverse guard** (every
  op in the emitter's union appears in `OPS` OR an explicit excluded list) so a
  future op cannot be silently dropped (per learning
  `2026-06-04-revert-fallback-must-preserve-alert-emit-and-op-scoped-alert-needs-reverse-guard.md`).
- [x] **AC7 — zero-await fast path preserved.** A VALID `.git` (the common case)
  triggers NO DB/JWT round-trip and NO re-clone. The fast-path validity gate runs
  ONLY when `.git` exists, is SYNCHRONOUS (no `await`, no subprocess on the hot
  path — a cheap structural fs check: ~2-3 `existsSync` syscalls, not the single
  one of plan-v1; the comment at repo-readiness-self-heal.ts:125-149 is updated to
  reflect the multi-stat cost), and is evaluated FIRST (short-circuit `||`) so
  `getFreshTenantClient` stays off the hot path. The deeper `git rev-parse`
  discriminator (F6) is reserved for the RECOVERY decision only (after the fast
  path has already routed a structurally-suspect workspace off the hot path) —
  never on a valid-`.git` dispatch. The existing AC7 fast-path test
  (cc-dispatch-repo-self-heal.test.ts ~line 65) still asserts zero seam calls.
- [x] **AC8 — residual test flipped RED→GREEN.** The test at
  `cc-dispatch-repo-self-heal.test.ts:388` is FLIPPED: an invalid `.git`
  (`existsSync` true, validity false) + connected + ready now asserts the corrupt
  `.git` is removed, re-clone is attempted, and the result is either `{ ok: true }`
  (valid worktree lands) OR an honest `{ ok: false }` block — NOT a silent
  `{ ok: true }` over a corrupt tree. (Flip the existing assertion as RED per
  learning `2026-06-01-behavior-reversal-fix-flip-existing-test-as-red.md`; keep
  the sibling valid-`.git` fast-path test as the scoped-unchanged slice.)
- [x] **AC9 — regression test for the new op (recovered + unrecovered).** A test
  asserts the corrupt-worktree path calls
  `reportDivergence`/`reportRepoResolverDivergence` with
  `op: "corrupt-worktree-at-dispatch"` on BOTH the recovered branch
  (`extra.recovered=true`, warn) and the unrecovered branch
  (`extra.recovered=false`, paging) — mirrors the existing
  `connected-null-install-at-dispatch` test in `repo-resolver-divergence.test.ts`,
  including the dedupe-by-fingerprint assertion.
- [x] **AC10 — typecheck + tests green.** `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` passes; `cd apps/web-platform &&
  ./node_modules/.bin/vitest run test/server/cc-dispatch-repo-self-heal.test.ts
  test/server/repo-resolver-divergence.test.ts
  test/sentry-repo-resolver-divergence-alert-op-contract.test.ts` passes (plus
  the new `test/server/git-worktree-validity.test.ts` if the helper is created).
- [x] **AC11 — ADR-044 amended.** A dated amendment extends the dispatch-
  readiness lineage from "physical `.git` present" to "on-disk worktree VALIDITY
  (not mere `.git` presence)", with a `### C4 edge note` confirming no `.c4` model
  edit (same enumeration as the 2026-06-18 amendment — GitHub `#external`,
  `founder` actor, `supabase` store granularity all already cover this path).
- [x] **AC12 — duplicate-workspace concern flagged, NOT fixed.** The plan / a
  follow-up issue records that the operator has TWO connected "My Workspace" rows
  for one account as a possible separate concern; this PR does NOT touch
  duplicate-workspace creation.
- [x] **AC14 — membership-write posture for corrupt-on-team (F4).** The
  corrupt-worktree recovery-failure path does NOT blindly call
  `setRepoStatus(error)` (which a removed/transient member could use to corrupt a
  team workspace's `repo_status` for its Owners). The plan states the posture
  explicitly: prefer emit-only on the corrupt-on-team-workspace failure unless
  the dispatching member is verified an Owner — mirroring the lines-284-298
  reasoning in `failConnectionUnresolved`. A test covers a member-triggered
  corrupt-`.git` recovery failure NOT writing the owner's `repo_status`.
- [x] **AC15 — real `.git` shape inspected (F6).** /work Phase 0 inspects the
  actual on-disk `.git` of workspace `754ee124` (read-only) to confirm it matches
  the empty-`.git` fingerprint the fast-path structural check detects. If it is
  populated-but-broken, the recovery-path `rev-parse` discriminator (not the
  structural check) is the one that must classify it corrupt — the structural
  check alone would NOT fix the operator's incident.

### Post-merge (operator)

- [ ] **AC13 — operator dogfood self-heal.** After deploy, the operator's next
  Concierge message on workspace `754ee124` self-heals (positively-fingerprinted
  corrupt `.git` removed under lock, re-cloned, spawns into a valid worktree) OR
  fails honestly with a **paging** Sentry event on the unrecovered branch.
  Automation: `web-platform-release.yml` restarts the container on merge to main
  touching `apps/web-platform/**`; the self-heal fires on the next cold dispatch —
  no separate operator step. **Concrete verification (F6/F7):** (a) a warn-level
  `corrupt-worktree-at-dispatch` breadcrumb is queryable for the detection
  (recovered or not); (b) if recovered, the operator's Concierge message now
  branches/commits successfully (the headline symptom is gone); (c) if NOT
  recovered, a paging event fired. `Ref` the tracking issue, do NOT
  `Closes`-auto-close before the self-heal is observed. Sentry query:
  `doppler run -p soleur -c prd -- scripts/sentry-issue.sh --search
  'feature:repo-resolver-divergence op:corrupt-worktree-at-dispatch'` (no SSH).

## Implementation Phases

### Phase 0 — Preconditions (RED grounding + real-state inspection)

- Read all edit sites + the residual test + the op-contract test (mapped in this
  plan). Test runner: `apps/web-platform` uses **vitest** (`vitest.config.ts
  include: test/**/*.test.ts`); `bunfig.toml` blocks bun test. Single-file cmd:
  `./node_modules/.bin/vitest run <path>` from `apps/web-platform`.
- **F6/AC15 — inspect the real `.git`.** Read-only inspect workspace `754ee124`'s
  on-disk `.git` (via the supabase MCP for the path + an ops read, or the deploy
  webhook — NO SSH) to confirm it matches the empty-`.git` fingerprint vs being
  populated-but-broken. This decides whether the fast-path structural check
  ALONE fixes the incident or whether the recovery-path `rev-parse` discriminator
  is load-bearing.
- **F4 — confirm the membership-write posture.** Re-read `failConnectionUnresolved`
  (repo-readiness-self-heal.ts:284-318) and `failHonestly` (:263-282) so the
  corrupt-failure posture (emit-only vs `setRepoStatus`) is decided before coding.
- Re-run the Phase 1.7.5 code-review overlap check against the final file list.

### Phase 1 — Two probes (RED test first)

Design the validity logic as **two distinct probes** (F1/F2/F6), NOT one inverted
seam:

1. **`isValidGitWorkTree(workspacePath): boolean`** (synchronous, fast-path
   gate). Structural check: `.git` exists AND (`.git` is a directory → `.git/HEAD`
   exists AND `.git/objects` exists) OR (`.git` is a FILE → treat as VALID; a
   `gitdir:` file is a real linked-worktree/submodule tree — F2). A bare
   `mkdir .git` (residual fixture) has neither HEAD nor objects → invalid. A
   Start-Fresh `git init` (HEAD + objects present) → valid → preserved (AC4).
   This is the seam replacement (renamed `gitDirExists`→`gitDirValid`) used on the
   hot path.
2. **`isEmptyCorruptGitDir(workspacePath): boolean`** (synchronous, the POSITIVE
   rm-trigger fingerprint — F2). True ONLY when: `.git` exists AND is a
   **directory** (NOT a file) AND `.git/HEAD` is ENOENT AND `.git/objects` is
   ENOENT. Uses `lstatSync`/`statSync` with explicit ENOENT-vs-EACCES handling —
   an EACCES/EIO on a populated `.git` returns false (do NOT rm). This is the ONLY
   gate that authorizes the destructive `rm`.
3. **Recovery-path discriminator (F6):** for a workspace that the fast-path
   flagged structurally-suspect AND that does NOT match the empty-corrupt
   fingerprint (i.e. populated-but-possibly-broken), the recovery decision MAY run
   `git rev-parse --is-inside-work-tree` (subprocess, OFF the hot path — allowed by
   AC7). If `rev-parse` says invalid, the corruption is real but the empty
   fingerprint did not match → fail honestly + emit (do NOT rm a populated `.git`
   blind; the safe action is honest-block, not destroy). deepen-plan/work decides
   whether to extend the rm to a `rev-parse`-confirmed populated-corrupt case
   under the lock, or to honest-block it.
4. RED: flip `cc-dispatch-repo-self-heal.test.ts:388` to assert recovery (AC8).
   Run it; confirm it FAILS against current code.

### Phase 2 — Rewire the gates (PER-SITE, not a rename sweep — F1)

1. **The seam** (`cc-dispatcher.ts:1823`): wire `gitDirValid: (p) =>
   isValidGitWorkTree(p)`. Rename `gitDirExists`→`gitDirValid` in
   `RepoSelfHealSeams` (`repo-readiness-self-heal.ts:106`), the test `makeSeams`
   default + per-test injections. **F1 — the null-install divergence gates need a
   SEPARATE absence probe.** The branches at `:170` and `:194-197`
   (`connected-null-install-at-dispatch`) currently require `gitAbsent`. They MUST
   keep testing TRUE ABSENCE — add a distinct `gitAbsent` seam (or inline
   `existsSync(<ws>/.git) === false`) for those two sites, so a corrupt-`.git` +
   null-install workspace does NOT trip the credential-divergence op. The graft
   branches (`:173`, `:177`/`graftReadyButGitAbsent`, `:185`) use `gitDirValid ===
   false`. Analyze each of the (now 5+) call sites individually; do NOT assume a
   blanket "no logic change".
2. **`needsSelfHeal`** (`cc-dispatcher.ts:1783`):
   `!isValidGitWorkTree(workspacePath)` replacing `!existsSync(<ws>/.git)`. Keep
   the short-circuit `||` ordering so the JWT round-trip stays off the valid hot
   path (AC7).
3. **Corrupt graft branch** (`repo-readiness-self-heal.ts`, install NON-null):
   add a corrupt-worktree branch (sibling of `graftReadyButGitAbsent`) that, on a
   ready+connected+invalid-`.git` workspace, (a) emits
   `reportDivergence("corrupt-worktree-at-dispatch", …)` at warn (F5/F7), then (b)
   runs the rm+reclone. F4: on recovery FAILURE, decide emit-only vs
   `setRepoStatus` per the membership posture (AC14) — do NOT reflexively call
   `failHonestly`'s `setRepoStatus` for a corrupt-on-team workspace.
4. **`ensureWorkspaceRepoCloned`** (`ensure-workspace-repo.ts:142`): the
   `.git`-present early-return becomes a `.git`-**valid** early-return
   (`isValidGitWorkTree` → return "ok"). When `.git` exists, is NOT valid, AND
   matches the empty-corrupt fingerprint (`isEmptyCorruptGitDir`), REMOVE it
   **under `withWorkspacePermissionLock(workspacePath, …)`** (F3) and fall through
   to clone. When `.git` exists, is not valid, but does NOT match the fingerprint
   (populated-but-broken, or EACCES, or a gitdir-file) → do NOT rm; return
   "failed" so the caller honest-blocks (F2/F6). Preserve the Start-Fresh /
   valid-clone no-op (AC4).
5. **`realGraftRepoClone` sentinel re-check** (`ensure-workspace-repo.ts:239`):
   tighten the pre-rename `if (existsSync(<ws>/.git)) return;` to "if a VALID
   `.git` now exists, the winner already grafted → return". Because the rm is now
   serialized under `withWorkspacePermissionLock` (Phase 2.4), the loser observes
   a valid `.git` inside the lock and no-ops — it never rm's the winner's result
   (F3).

### Phase 3 — Observability op

1. Add `"corrupt-worktree-at-dispatch"` to `RepoResolverDivergenceOp`
   (`repo-resolver-divergence.ts:27`) with a doc-comment distinguishing it from
   `connected-null-install-at-dispatch` (install is NON-null here; the failure is
   on-disk corruption, not credential).
2. **F5 — add the NEW emit call** inside the corrupt graft branch (Phase 2.3) —
   the existing `reportDivergence` sites (`:199`,`:304`) require install null and
   are never reached here. Emit at **warn/breadcrumb on detection** (F7) with
   `extra.recovered` set after the re-clone resolves (or a distinct
   `corrupt-worktree-recovered` warn-op vs the page-level unrecovered signal).
   The **paging** event is the unrecovered branch. Production-wired via the
   injected `reportDivergence` seam (cc-dispatcher:1832).
3. **F5 — verify paging coverage of the unrecovered path.** Confirm
   `feature=cc-dispatcher op=repo-readiness-self-heal` (the `failHonestly` emit)
   is actually under a paging alert; if NOT, route the unrecovered corrupt failure
   through `reportRepoResolverDivergence` (feature-only paging alert) instead, so
   the honest-block is paged, not merely queryable.
4. Add `"corrupt-worktree-at-dispatch"` to the `OPS` array in
   `sentry-repo-resolver-divergence-alert-op-contract.test.ts` (~line 33) + add
   the **net-new reverse-guard** (F8): regex-parse the `RepoResolverDivergenceOp`
   union members from `repo-resolver-divergence.ts`; assert each ∈ `OPS ∪
   EXCLUDED`; seed `EXCLUDED = []` with a comment that any future EXCLUDED op
   needs a non-paging justification.

### Phase 4 — Tests (GREEN)

1. Make the flipped residual test (AC8) pass — empty-corrupt `.git` is rm'd under
   lock + re-cloned (or honest-blocks); never silent `{ ok:true }`.
2. Add the safety-regression suite (F2/F3/F4/F6): valid-`.git` fast-path (AC4,
   zero seam calls); Start-Fresh `.git` preserved; `.git`-FILE (gitdir) preserved;
   transient-EACCES on populated `.git` NOT rm'd; populated-broken `.git`
   honest-blocked NOT rm'd; two-racer corrupt case serialized (at most one rm +
   clone); member-triggered corrupt failure does NOT write the owner's
   `repo_status`; corrupt+null-install does NOT emit `connected-null-install-at-dispatch`.
3. Add the new-op regression (AC9) in `repo-resolver-divergence.test.ts`
   mirroring `connected-null-install-at-dispatch` — BOTH the recovered branch
   (`extra.recovered=true`, warn) and the unrecovered branch
   (`extra.recovered=false`, paging), op string, feature tag, dedupe.
4. Run AC10 (tsc + the three named test files + the new
   `git-worktree-validity.test.ts` if created).

### Phase 5 — ADR-044 amendment (AC11)

Append `## Amendment 2026-06-19 — dispatch readiness is on-disk worktree VALIDITY
(not mere .git presence)` extending the 2026-06-18 lineage. State: the
2026-06-18 amendment made readiness `repo_status-ok AND physical .git present`;
this amendment tightens "physical .git present" to "**valid** git work tree".
**Be precise (F6):** the fast-path gate uses a SYNCHRONOUS structural proxy
(`.git` dir with HEAD+objects, or a `.git`-FILE gitdir) — explicitly WEAKER than
`git rev-parse --is-inside-work-tree`, chosen to keep the AC7 zero-await hot path.
The destructive re-clone is authorized only by a POSITIVE empty-`.git`
fingerprint; a populated-but-broken `.git` (which the structural proxy passes but
`rev-parse` would fail) is caught by the off-hot-path recovery `rev-parse`
discriminator and honest-blocked, NOT rm'd. `/soleur:go` Step 0.0 still runs the
authoritative `rev-parse`. Include the new Sentry op (warn-on-detect /
page-on-unrecovered) and a `### C4 edge note` (no `.c4` edit — same enumeration as
2026-06-18: GitHub `#external`, `founder` actor covers Owner/Member, `supabase`
store granularity).

### Phase 6 — Duplicate-workspace flag (AC12)

File a tracking issue: "operator has TWO connected 'My Workspace' rows for one
account (`52af49c2` solo + `754ee124`), both `repo_url=jikig-ai/soleur`,
`installation_id=122213433`, `repo_status=ready` — possible duplicate-workspace-
creation concern, separate from corrupt-worktree dispatch." Do NOT fix here.

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — `needsSelfHeal` (:1783) +
  `gitDirValid` + the NEW `gitAbsent` seam wiring (:1823, F1); rename seam usage.
- `apps/web-platform/server/repo-readiness-self-heal.ts` — rename
  `gitDirExists`→`gitDirValid` in `RepoSelfHealSeams` (:106); ADD a distinct
  `gitAbsent` seam for the null-install divergence gates (:170, :194-197 — F1);
  use `gitDirValid === false` only on the graft branches (:173, :177, :185);
  add the corrupt-worktree graft branch + the NEW `reportDivergence` emit
  (Phase 2.3/3.2, F5/F7); the corrupt-failure membership-write posture (F4);
  update comments (the fast-path doc-comment at :125-149, F-AC7 multi-stat cost).
- `apps/web-platform/server/ensure-workspace-repo.ts` — `.git`-present →
  `.git`-valid early-return (:142); POSITIVE-fingerprint rm under
  `withWorkspacePermissionLock` (F2/F3); honest-block (return "failed") for
  populated-broken / EACCES / gitdir-file (F2/F6); validity-aware graft sentinel
  re-check (:239). (`rm` already imported at :2; add `lstatSync`/`statSync` from
  `node:fs` + `withWorkspacePermissionLock` from `@/server/workspace-permission-lock`.)
- `apps/web-platform/server/repo-resolver-divergence.ts` — add the new op to the
  union (:27); the `extra.recovered` field shape (F7).
- `apps/web-platform/server/git-worktree-validity.ts` — **(new)** the two
  synchronous helpers `isValidGitWorkTree` + `isEmptyCorruptGitDir` (F2), and the
  off-hot-path `revParseInsideWorkTree` recovery discriminator (F6) wrapping
  `execFile` from `git-auth.ts` convention (NO installation token needed — it is
  a local read-only `rev-parse`).
- `apps/web-platform/test/server/cc-dispatch-repo-self-heal.test.ts` — flip the
  residual test (:388); rename seam in `makeSeams` (:31) + add `gitAbsent` default
  + per-test injections; add the fast-path/Start-Fresh/gitdir-file/EACCES/
  populated-broken/race/member-write/recovered/unrecovered regressions.
- `apps/web-platform/test/server/repo-resolver-divergence.test.ts` — new-op
  regression test (recovered + unrecovered, dedupe).
- `apps/web-platform/test/sentry-repo-resolver-divergence-alert-op-contract.test.ts`
  — add the new op to `OPS` (~:33) + the NET-NEW reverse-guard (F8).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`
  — dated amendment (AC11).

## Files to Create

- `apps/web-platform/server/git-worktree-validity.ts` — the validity + empty-
  fingerprint + rev-parse-recovery helpers (F2/F6).
- (knowledge-base) plan + spec `tasks.md` (this lifecycle).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` cross-checked against the
edited file paths returned no overlap at plan time — re-verify in /work Phase 0
per Phase 1.7.5.)

## Design Decision — THREE probes (structural fast-path + positive-fingerprint rm + rev-parse recovery)

Deepen-plan review (F1/F2/F6) established that a single inverted seam is unsafe.
The design uses three probes with distinct roles:

1. **Fast-path gate — `isValidGitWorkTree` (synchronous structural).** Replaces
   the `gitDirExists` seam on the hot path. `.git` dir with HEAD + objects = valid;
   `.git` FILE (gitdir/worktree) = valid; bare/empty `.git` = invalid. The seam
   stays SYNCHRONOUS `(path) => boolean` — widening to `Promise<boolean>` for a
   `rev-parse` subprocess would add an await to the AC7 hot path and invite the
   sync-contract-to-async-proxy hazard. Cost rises from 1 to ~2-3
   `existsSync`/`stat` syscalls, negligible per dispatch.
2. **rm authorization — `isEmptyCorruptGitDir` (synchronous, POSITIVE
   fingerprint).** The destructive `rm` fires ONLY on this positive match (`.git`
   is a directory AND HEAD ENOENT AND objects ENOENT), with explicit ENOENT-vs-
   EACCES handling. F2 safety pivot: an EACCES blip on a populated `.git`, or a
   gitdir-FILE `.git`, does NOT match, so it is never rm'd. NEVER trigger rm on the
   negation of the validity probe.
3. **Recovery discriminator — `git rev-parse --is-inside-work-tree` (subprocess,
   OFF hot path, F6).** For a structurally-suspect but NOT-empty-fingerprint
   `.git` (populated-but-possibly-broken), the recovery decision may run
   `rev-parse` to confirm corruption. A populated-corrupt `.git` is honest-blocked
   (+ emit), NOT blindly rm'd. This matches go.md Step 0.0's exact probe.

**Why not rm a populated-corrupt `.git`?** A `.git` with HEAD+objects present but
a truncated packfile could still hold recoverable un-pushed commits; the safe
action is honest-block + page. The empty-fingerprint rm is provably safe (no
objects = no commits to lose).

deepen-plan Phase 4.4 precedent-diff: there is **no existing git-validity helper**
in `apps/web-platform/server/` (the `rev-parse` callers — session-sync.ts:224,
workspace-sync.ts:231, inflight-checkpoint.ts:378, _cron-safe-commit.ts — assume a
valid `.git` and crash on corruption). The novel helper is justified. The
`withWorkspacePermissionLock` serialization primitive (F3) is the established
escape hatch named at ensure-workspace-repo.ts:204 for exactly the "premise
changed, now there is a destructive op" case the rm introduces.

## Risks & Mitigations

- **Blowing away a repo with un-pushed commits (CATASTROPHIC, F2).** The single
  worst case. Mitigations, layered: (a) the rm is gated on a POSITIVE empty-`.git`
  fingerprint (`isEmptyCorruptGitDir`), never the negation of the validity probe —
  an empty `.git` has no objects = no commits to lose; (b) a Start-Fresh `.git`
  (HEAD + objects) is classified VALID and never touched; (c) an EACCES/EIO blip
  on a populated `.git` returns false from the fingerprint (ENOENT-vs-EACCES
  handling) so a transient unreadable repo is NOT rm'd; (d) a `.git` FILE
  (gitdir/worktree/submodule) is classified VALID and never rm'd; (e) a
  populated-but-broken `.git` is honest-blocked, NOT rm'd. AC3/AC4 + dedicated
  regression tests for Start-Fresh, gitdir-file, and the empty fingerprint.
- **Concurrency: rm is a second `.git` writer (F3).** A racing loser could rm the
  winner's freshly-valid `.git`. Mitigation: the rm+reclone for the corrupt case
  runs serialized under `withWorkspacePermissionLock(workspacePath, …)` (the
  premise-change escape hatch at ensure-workspace-repo.ts:204); the loser observes
  a valid `.git` inside the lock and no-ops. The existing graft-race test models
  only the absent case (no rm) — a NEW corrupt-case race test is required (do NOT
  rely on the absent-case test).
- **Member-write hazard on corrupt-on-team failure (F4).** A removed/transient
  member's corrupt-`.git` recovery failure must NOT flip a team workspace's
  `repo_status` to `error` for its Owners. Mitigation: emit-only on the
  corrupt-on-team failure unless the dispatching member is a verified Owner
  (mirrors `failConnectionUnresolved` lines 284-298). AC14 + a member-triggered
  test.
- **Operator's real corruption may be populated-but-broken (F6).** The fast-path
  structural check under-detects HEAD+objects-present-but-broken `.git`.
  Mitigation: inspect `754ee124`'s real `.git` at /work Phase 0 (AC15); the
  recovery-path `rev-parse` discriminator covers the populated-broken case;
  AC13 has a concrete symptom-gone check, not an either-way assertion.
- **Self-healed corruption pages the operator (F7).** Mitigation: warn-on-detect
  / page-on-unrecovered; `extra.recovered` distinguishes the two.
- **Silent re-emit storm.** Mitigated by the existing `(op, userId, claim)`
  fingerprint dedupe in `reportRepoResolverDivergence` — the new op inherits it.
- **AC7 regression (subprocess on hot path).** Mitigated by the synchronous
  structural fast-path gate (subprocess reserved for the off-hot-path recovery
  decision); the existing zero-seam-call fast-path test guards it.

## Hypotheses

Not an SSH/network class — skip the network-outage checklist (no trigger
keywords).

## Domain Review

**Domains relevant:** Product (CPO sign-off — single-user-incident threshold)

### Product/UX Gate

**Tier:** none (no UI surface — no `components/**`, `app/**/page.tsx`, or
`app/**/layout.tsx` in Files to Edit; this is a server-side recovery/observability
fix). The Product relevance is solely the CPO sign-off mandated by the
single-user-incident threshold, not a UI review.
**Decision:** auto-accepted (pipeline) for UX; CPO sign-off required per §User-Brand Impact.
**Agents invoked:** none (no UI surface).
**Skipped specialists:** none — no UI feature, so `ux-design-lead` is N/A.
**Pencil available:** N/A (no UI surface).

#### Findings

CTO/architecture concern (carried into Risks): the validity-probe must preserve
Start-Fresh and remain synchronous on the hot path. No CLO/CTO re-sign at plan
phase (single-product-owner ack only).

## Architecture Decision (ADR/C4)

This change **extends an existing ADR** (ADR-044's 2026-06-18 dispatch-readiness
amendment) — detection fires (resolver/dispatch trust-boundary change: what
"ready" means on disk). Per `wg-architecture-decision-is-a-plan-deliverable`,
the ADR amendment is an in-scope deliverable of THIS plan (Phase 5 / AC11), NOT a
follow-up.

### ADR

Amend `ADR-044-workspace-repo-ownership.md` (Phase 5). New decision content:
dispatch readiness = `repo_status-ok AND on-disk worktree VALIDITY` (tightening
"physical .git present" → "valid git work tree"); corrupt `.git` is needs-
recovery, removed before re-clone, fail-honest if still invalid; new Sentry op
`corrupt-worktree-at-dispatch`.

### C4 views

**No `.c4` model edit.** Read of all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`)
required at /work to confirm — but the enumeration is identical to the 2026-06-18
amendment's `### C4 edge note`: external actors = GitHub (`github` `#external`,
webhook/clone sender); external systems = GitHub App clone subsumed by `github`;
actors = workspace Owner + Member both covered by the existing `founder` actor
("Workspaces may have MULTIPLE Owners"); stores = `/workspaces` volume +
`workspaces.repo_status`/`repo_error` are below the model's `supabase`-element
granularity. The corrupt-worktree path adds NO new actor, system, store, or
access-relationship — it tightens the on-disk validity semantics of an already-
modeled dispatch edge. AC11 records this enumeration in the amendment's `### C4
edge note`.

### Sequencing

Single atomic PR — no soak-gated migration; no split.

## Observability

```yaml
liveness_signal:
  what: corrupt-worktree-at-dispatch breadcrumb (warn on detection) on the repo_resolver_divergence feature; extra.recovered distinguishes healed vs unhealed
  cadence: per cold dispatch into a connected workspace whose .git is structurally invalid (deduped per (op,userId,workspaceId), once per process)
  alert_target: Sentry issue-alert "repo-resolver-divergence" (feature-only filter, IssueOwners/ActiveMembers email)
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (resource sentry_issue_alert.repo_resolver_divergence, NO change; feature-only auto-covers the new op)
error_reporting:
  destination: Sentry (via reportRepoResolverDivergence then reportSilentFallback emit boundary, userId to userIdHash)
  fail_loud: yes - the previously-SILENT corrupt-.git detection now emits; the UNRECOVERED branch pages (F5/F7)
failure_modes:
  - mode: corrupt .git detected at dispatch (warn, search-only)
    detection: isValidGitWorkTree(workspacePath) === false while .git exists; install non-null
    alert_route: repo_resolver_divergence breadcrumb (op=corrupt-worktree-at-dispatch, extra.recovered set after re-clone)
  - mode: corrupt .git removed + re-clone SUCCEEDS (self-healed)
    detection: ensureWorkspaceRepoCloned returns "ok" after rm
    alert_route: warn breadcrumb only (extra.recovered=true) - NOT paged (F7)
  - mode: re-clone after corrupt-.git removal still fails (UNRECOVERED)
    detection: ensureWorkspaceRepoCloned returns "failed" after rm
    alert_route: PAGING event via reportRepoResolverDivergence (op=corrupt-worktree-at-dispatch, extra.recovered=false) - feature-only alert pages. F5 - do NOT rely on failHonestly's reportSilentFallback(feature=cc-dispatcher op=repo-readiness-self-heal) for paging unless verified under a paging alert
  - mode: populated-but-broken .git (rev-parse false, empty-fingerprint false)
    detection: recovery-path git rev-parse --is-inside-work-tree false
    alert_route: honest-block + PAGING corrupt-worktree-at-dispatch (NOT rm'd; F6)
logs:
  where: Sentry (breadcrumbs/issues); pino structured logs at the reportSilentFallback boundary
  retention: Sentry project default (jikigai-eu / web-platform)
discoverability_test:
  command: 'doppler run -p soleur -c prd -- scripts/sentry-issue.sh --search "feature:repo-resolver-divergence op:corrupt-worktree-at-dispatch"'
  expected_output: 'a warn-level breadcrumb (extra.recovered=true) when the corrupt .git self-healed, or a paging event (extra.recovered=false) when the re-clone failed; the op-contract test additionally asserts the op is alert-covered'
```

> **F9 caveat:** confirm `scripts/sentry-issue.sh` exists / accepts `--search`
> at /work Phase 0 (per the CLI-verification gate); if the repo's Sentry-read
> runbook uses a different invocation, substitute the canonical one. The
> load-bearing property is "queryable without SSH", not the exact script name.

## GDPR / Compliance

Skip — no regulated-data surface (no schema/migration/auth-flow/API-route/.sql
change). The new Sentry breadcrumb carries only pseudonymized `userIdHash`
(ADR-029) + two workspace ids, identical to the existing divergence ops; it is
not new processing of regulated data.

## Infrastructure (IaC)

Skip — no new infrastructure. The Sentry alert
(`issue-alerts.tf:sentry_issue_alert.repo_resolver_divergence`) is feature-only
and requires NO change; the new op routes through it automatically (AC6). Pure
code change against an already-provisioned surface.

## Test Scenarios

| Scenario | Setup | Expected |
| --- | --- | --- |
| Empty-corrupt `.git` (bare `mkdir .git`) + connected + ready | the flipped residual test | fingerprint match → rm under lock, re-clone; `{ok:true}` on success or honest `{ok:false}` block; NEVER silent `{ok:true}` over corrupt tree |
| Valid `.git` (HEAD + objects) + ready | fast-path | `{ok:true}`, zero clone/lock/setStatus calls (AC7) |
| Start-Fresh `.git` (valid, no origin) | `git init` work tree | classified valid → NOT removed, NOT re-cloned (AC4) |
| `.git` FILE (gitdir/worktree) | `.git` is a file | classified valid → NOT removed (F2) |
| Populated-but-broken `.git` (HEAD+objects present, rev-parse false) | recovery-path discriminator | honest-block + PAGING emit; NOT rm'd (F6) |
| Transient EACCES on populated `.git` | stat throws EACCES | empty-fingerprint false → NOT rm'd (F2) |
| Corrupt `.git` + install NULL | null-install gate | routes `connected-null-install-at-dispatch` (true-absence preserved? NO — corrupt is not absent → must NOT trip null-install op; routes corrupt path or honest-block) (F1) |
| `.git` cleanly absent + ready (Bug 2) | existing graft test | unchanged — lock-free graft re-clones |
| Two racers + corrupt `.git` | concurrent dispatch | serialized under lock; loser observes valid `.git`, no-ops; at most one rm + clone (F3) |
| Member-triggered corrupt recovery failure | non-Owner member | no `setRepoStatus(error)` write to the owner's row (F4) |
| corrupt-worktree emit (recovered) | re-clone ok | warn breadcrumb `extra.recovered=true`, NOT paged (F7) |
| corrupt-worktree emit (unrecovered) | re-clone failed | PAGING emit `extra.recovered=false` (F5/F7) |
| op-contract | the alert test | new op in `OPS`; feature-only invariant holds; net-new reverse-guard passes (F8) |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO,
  or omits the threshold will fail `deepen-plan` Phase 4.6 — this plan fills it.
- **Start-Fresh `.git` must survive the validity probe.** A Start-Fresh workspace
  has a valid `.git` with no `origin` by design (ensure-workspace-repo.ts:115-120).
  The validity check MUST classify it valid (HEAD + objects present) so it is
  never removed/re-cloned — re-cloning would clobber a Start-Fresh workspace.
  This is the single highest-risk regression; AC4 + a dedicated test enforce it.
- **The seam inversion is NOT a no-op — analyze each call site (F1).** The
  null-install divergence gates (`repo-readiness-self-heal.ts:170`, `:194-197`)
  require TRUE ABSENCE and MUST keep a distinct `gitAbsent` probe — inverting them
  to "invalid" silently routes a corrupt-`.git` + null-install workspace to the
  `connected-null-install-at-dispatch` op (wrong op, no removal). Only the graft
  branches use `gitDirValid === false`. Per-site analysis, never a blanket rename.
- **rm is gated on a POSITIVE fingerprint, never the negation of the probe (F2).**
  `existsSync`/`stat` returning false collapses ENOENT with EACCES/EIO; triggering
  rm on "not valid" would destroy a populated `.git` on a transient blip, or rm a
  valid gitdir-FILE worktree. The rm fires ONLY on the empty-`.git` fingerprint
  (`.git` dir AND HEAD ENOENT AND objects ENOENT). A populated-but-broken `.git`
  is honest-blocked, NOT rm'd.
- **remove-before-clone is a second `.git` writer — serialize it (F3).** The
  existing graft sentinel guards the `rename`, NOT a new destructive `rm`. A
  racing loser can rm the winner's freshly-valid `.git`. Run the corrupt-case
  rm+reclone under `withWorkspacePermissionLock(workspacePath, …)` (the
  premise-change escape hatch at ensure-workspace-repo.ts:204). The absent-case
  graft-race test does NOT exercise the destructive window — write a new one.
- **corrupt-on-team failure must not member-write `repo_status` (F4).** Do NOT
  route the corrupt recovery failure through `failHonestly`'s `setRepoStatus`
  without the membership-write posture decision — a removed member could corrupt a
  team workspace's readiness for its Owners (the exact hazard
  `failConnectionUnresolved` lines 284-298 exist to avoid).
- **Do NOT op-scope the Sentry alert.** The alert is feature-only by design
  (AC6); adding an `op` filter to "be specific" would silently dark this and
  every future op. The op-contract test's `not.toMatch(/key\s*=\s*"op"/)`
  invariant must stay green.
- **Issue 4826 is NOT the work target.** Do not `Closes #4826`; it is an
  unrelated P3 nav-rail feature. Use `Ref` to the duplicate-workspace tracking
  issue if any, never auto-close.
- **Duplicate-workspace is out of scope.** Flag it (AC12 / Phase 6); do not fix
  it here.
