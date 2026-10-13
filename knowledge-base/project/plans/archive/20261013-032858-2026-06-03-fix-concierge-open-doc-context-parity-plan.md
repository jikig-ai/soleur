---
title: "Fix Concierge open-document context parity (KB chat can't read the open doc / workspace files) + PIR follow-up cleanup"
type: fix
date: 2026-06-03
branch: feat-one-shot-concierge-doc-context-parity
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 Fix: Concierge cannot read the KB document the user has open (agent-native context parity) + PIR follow-up cleanup

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-03
**Gates passed:** 4.6 User-Brand Impact (present, threshold `single-user incident`), 4.7 Observability
(all 5 fields present, no SSH in `discoverability_test`), 4.8 PAT-shaped var halt (none), 4.9
UI-wireframe (no UI-surface file in Files-to-Edit/Create → skip). Cited rule IDs verified ACTIVE in
`AGENTS.rest.md`: `cq-write-failing-tests-before`, `cq-silent-fallback-must-mirror-to-sentry`,
`cq-test-fixtures-synthesized-only`. Cited code lines verified: `kb-chat-content.tsx:111`
(`type: "kb-viewer"`), `ws-handler.ts:1086/1106` (`if (context?.path && !warmCcQuery)`),
`ws-handler.ts:997` (`cc-pdf-resolver-skip` captureMessage). Issues #4849 (CLOSED) / #4854 (OPEN)
verified live — citation-only, not work targets.

> Note: the deepen-plan parallel research/review/skill sub-agents (Phase 2/3/4/5) could not be
> spawned — the Task tool is unavailable in this planning environment. The structural halt gates
> (4.6–4.9), precedent-diff (4.4), and verify-the-negative (4.45) passes were run inline below.
> Given `brand_survival_threshold: single-user incident`, /work SHOULD re-run deepen-plan (or
> ultrathink) where the substance reviewers (data-integrity-guardian, security-sentinel,
> architecture-strategist) are available — plan-review style agents cannot cover proxy-vs-invariant
> or workspace-isolation regressions.

### Key Improvements (over the as-planned draft)

1. **Root cause confirmed as a single workspace-source divergence (Phase 4.45 verify-the-negative).**
   Both the document resolver (`kb-document-resolver.ts:72-102` `fetchUserWorkspacePath` →
   `users.workspace_path`) AND the agent sandbox `cwd` (`cc-dispatcher.ts:978` `realSdkQueryFactory`
   Promise.all → same `fetchUserWorkspacePath`) read the SAME per-user source. The UI "Workspace
   ready" + file tree render from a different source. This is why failure 1 (doc not read) and
   failure 2 (no .git / not initialized) co-occur — they are one bug.
2. **Quote path (⌘⇧L) confirmed already wired** (`kb-chat-content.tsx:41` → `quoteRef` →
   `ChatSurface` `insertQuote`); the gap is the open-document BODY only. Plan scopes the doc-body
   fix and explicitly does NOT re-plumb the quote path.
3. **Injection wiring confirmed intact end-to-end** (resolver → `dispatchSoleurGoForConversation`
   `...documentArgs` → runner). The fix lives in workspace-source resolution, not the wiring.
4. **Security-gate precedent-diff (Phase 4.4):** the two read-containment gates
   (`knowledge-base/` prefix gate at `kb-document-resolver.ts:152`; `isPathInWorkspace` at `:193`)
   are the ONLY controls preventing cross-workspace / `.git/**` / `attachments/<otherConv>` reads
   via a Concierge `context.path`. Any workspace-path resolution change MUST preserve both — added
   to ACs and User-Brand Impact.

### New Considerations Discovered

- **Coordination risk with the in-flight git-workspace-plumbing branch.** The merged PR #4868 and
  the sibling plan `2026-06-03-fix-concierge-git-workspace-plumbing-per-user-repo-plan.md` both
  touch workspace-path / repo resolution for the Concierge. If both branches independently change
  how `fetchUserWorkspacePath` / the sandbox `cwd` resolves, they will conflict or double-fix. The
  /work phase MUST read that plan's Phase 0 outcome before editing the workspace resolver.
- **The `_workspacePathCache` per-process memo** (`kb-document-resolver.ts:70`) caches
  `users.workspace_path` for the user's lifetime. If the bug is "stale workspace_path", a fix that
  changes the SOURCE must also ensure the cache is keyed/invalidated correctly — the regression
  test already drains it via `_resetWorkspacePathCacheForTests`, but production cache staleness is
  a candidate failure mode to check in Phase 0.

## Overview

Two changes in one PR.

**PRIMARY (agent-native parity bug).** In the web-platform Knowledge Base UI, the Concierge
chat docks beside an OPEN KB document; the input placeholder promises document-grounded Q&A
("Ask about this document — ⌘⇧L to quote selection"). A user asked about follow-ups in an
open post-mortem and the Concierge replied that it could **not** see the document ("the document
didn't come through — no attachment or content arrived with your message") AND that "there's no
connected git repository available in this session… the workspace may not be fully initialized
yet" — **despite** the UI showing "Workspace ready" and a fully populated KB file tree.

Agent-native invariant: **anything a user can see, the agent must see.** The doc the agent
could not READ is itself a PIR about a silent WRITE-path context gap — same class, opposite
direction.

**SECONDARY (docs cleanup).** In
`knowledge-base/engineering/operations/post-mortems/chat-rls-workspace-id-outage-postmortem.md`,
the liveness-alert follow-up still reads "File as a monitoring follow-up" / "tracked as a
monitoring follow-up" with no issue number. It IS tracked: **#4849** (CLOSED — MVP Sentry
write-absence alert) and **#4854** (OPEN — deferred scheduled defense-in-depth probe). Update
the "Follow-ups" and "Action Items" sections to cite both so the liveness item is no longer
untracked-in-prose.

> Note: #4849 and #4854 are **contextual citations to insert as literal text** in the PIR. They
> are NOT work targets and MUST NOT be passed as work-item references (no `Closes`/`Ref` for
> them in the PR body).

This plan does research and design only for /work. **No code is written during planning.**

## Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
| --- | --- | --- |
| Issue #4849 (liveness alert, closed) | `gh issue view 4849 --json state,title` | **CLOSED** — "monitoring: alert on zero interactive message-saves per workspace (write-absence liveness)". Citation-only, not a work target. |
| Issue #4854 (scheduled probe, open) | `gh issue view 4854 --json state,title` | **OPEN** — "feat(monitoring): scheduled prod write-absence probe for interactive messages (defense-in-depth)". Citation-only, not a work target. |
| PIR file | `ls` | Exists (`...chat-rls-workspace-id-outage-postmortem.md`, 14 KB). "File as a monitoring follow-up" at line 153; "tracked as a monitoring follow-up" at line 161. |
| `kb-document-resolver.ts` `resolveConciergeDocumentContext` | `Read` | Exists. Robust server-side resolver (text inline ≤ 50 KB, PDF extract, workspace-validation, Sentry mirrors). |
| `leader-document-resolver.ts` (#3437) | `Read` | Exists. Sibling resolver for the leader path. |
| ws-handler `dispatchSoleurGoForConversation` | `Read` | Exists. Calls the resolver and threads `documentArgs` into `dispatchSoleurGo`. |
| PR #4868 (`feat-one-shot-concierge-git-credentials`) | `git log` / sibling plan | **MERGED** — injected per-workspace GH App installation token as `GH_TOKEN`. Adjacent but distinct work (git **push/auth**, not document **read**). See Research Reconciliation. |
| Sibling plan `2026-06-03-fix-concierge-git-workspace-plumbing-per-user-repo-plan.md` | `Read` | Exists. Covers the git/workspace-mount + credential half. This plan MUST not duplicate it; it scopes the **document-read parity** dimension. |

Premise holds. The bug is a **fix** (the injection wiring exists end-to-end), not a build —
the open-document body is failing to *reach* the resolver-readable workspace, OR the resolver is
returning empty because the per-user `users.workspace_path` it reads diverges from the workspace
the UI's file tree renders from. Both halves are the same workspace-source divergence.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the bug report) | Reality (confirmed in code) | Plan response |
| --- | --- | --- |
| "The open KB document is NOT injected into the chat request context" | The **client** never populates `context.content`: `kb-chat-content.tsx:109` builds `initialContext = { path, type: "kb-viewer" }` only. The **server** resolver (`resolveConciergeDocumentContext`) reads the file from `users.workspace_path` when `providedContent` is null. So injection depends entirely on the server-side workspace read succeeding. | Confirm whether the resolver returns empty (workspace path missing/unpopulated) vs. drops on the `knowledge-base/` prefix gate vs. `isPathInWorkspace` rejection. Fix at the failing layer. The `cc-pdf-resolver-skip` Sentry warning (`ws-handler.ts:996`) is the diagnostic anchor. |
| "Wire the open document + ⌘⇧L quoted selection through to the agent" | **Quote selection already reaches the request** as message text: `kb-chat-content.tsx:41` → `quoteRef` → `ChatSurface` `insertQuote` inserts a blockquote into the textarea; it is sent as normal `chat` content. The **open document body** is the gap, not the quote. | Scope the doc-body injection fix; record that the quote path already works (do NOT re-plumb it). Add a regression assertion that the open doc is present in assembled context regardless of quote. |
| "No connected git repository / workspace not fully initialized" — separate root cause or same? | **Same root cause.** The agent sandbox `cwd`/workspace AND the document resolver both derive from `fetchUserWorkspacePath(userId)` → `users.workspace_path` (`kb-document-resolver.ts:72-102`, `cc-dispatcher.ts:978`). If that path is unprovisioned or unpopulated, the agent sees no `.git`/no KB tree (failure 2) AND the resolver returns no body (failure 1). The "Workspace ready" UI + file tree render from a **different** workspace source (workspace-scoping divergence, cf. plans `2026-06-02-fix-workspace-scoping-leak*`). | Treat failures 1 and 2 as one workspace-source-divergence root cause. The fix makes the resolver + agent sandbox read the SAME workspace the UI file tree renders from. **Do NOT** re-implement git-credential plumbing — PR #4868 / the git-workspace-plumbing plan own that. |
| Injection wiring is missing | Wiring EXISTS: `dispatchSoleurGoForConversation` (ws-handler) → resolver → `dispatchSoleurGo` (`...documentArgs`) → runner system prompt. First-turn passes `pendingContext`; warm/turn-2+ rebuilds synthetic context from `session.contextPath` / `conversations.context_path`. | The fix is in the **workspace-source resolution**, not the wiring. Verify the wiring stays intact; the regression test asserts the assembled context carries the doc. |

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge keeps replying "the document didn't
come through" / "no connected git repository" while the UI shows "Workspace ready" with a full
file tree — the single most trust-destroying failure for an agent-native product (the agent is
blind to what the user is plainly looking at).

**If this leaks, the user's data is exposed via:** the resolver's `knowledge-base/` prefix gate
and `isPathInWorkspace` containment are the controls that stop a Concierge `context.path` from
reading `attachments/<otherConvId>/*`, `.git/**`, or another user's workspace. Any fix that
changes how the workspace path is resolved MUST preserve both gates — a per-user workspace
mis-resolution could cross-read another user's KB. (See `kb-document-resolver.ts:144-197`.)

**Brand-survival threshold:** single-user incident.

## Implementation Phases

### Phase 0 — Reproduce & localize the failing layer (no code)
- Reproduce against a connected workspace: open a KB doc, ask the Concierge about it; capture the
  `cc-pdf-resolver` / `cc-pdf-resolver-skip` breadcrumbs + the `concierge document context
  resolved` breadcrumb (`ws-handler.ts:976`) to see `documentKindResolved`, `documentContentBytes`,
  `documentExtractError`.
- Determine which of these is true for the reported case:
  - (a) `fetchUserWorkspacePath` throws / returns a path with no KB tree → resolver returns
    `{ artifactPath, documentKind }` with NO `documentContent` (workspace-source divergence).
  - (b) `context.path` does not start with `knowledge-base/` → resolver returns `{}` (prefix gate).
  - (c) `isPathInWorkspace` rejects (workspace path ≠ tree root) → resolver returns `{}`.
- Confirm the agent-sandbox `cwd` (`cc-dispatcher.ts` `realSdkQueryFactory`, `workspacePath` from
  `fetchUserWorkspacePath`) points at the SAME directory the UI file tree renders from. Identify
  the UI file-tree data source and diff the two workspace-path resolutions. **This diff is the
  root cause.** (Cross-reference plans `2026-06-02-fix-workspace-scoping-leak*` and
  `2026-06-03-fix-concierge-git-workspace-plumbing-per-user-repo-plan.md` — reuse, do not
  re-derive.)

### Phase 1 — RED: failing regression test (TDD, `cq-write-failing-tests-before`)
- Add a test asserting that an **open KB document is present in the assembled chat context** for
  the Concierge path. Co-locate with `apps/web-platform/test/cc-dispatcher-concierge-context.test.ts`
  (existing) or add `apps/web-platform/test/concierge-active-workspace-doc-parity.test.ts`.
  Path MUST match the vitest node glob `test/**/*.test.ts` (`vitest.config.ts:44`). Run with
  `./node_modules/.bin/vitest run <path>` (NOT `bun test` — `bunfig.toml` blocks bun discovery, #1469).
- The assertion drives through the resolver/dispatch boundary (deterministic, no LLM): given a
  user with a provisioned workspace containing a KB file at `knowledge-base/.../doc.md`, and a
  `start_session` with `context.path` set, the resolved `documentArgs.documentContent` (or the
  assembled system prompt) contains the doc body. Seed the workspace fixture (filesystem temp dir +
  `users.workspace_path` swap, draining `_resetWorkspacePathCacheForTests`).
- Test fixtures synthesized only (`cq-test-fixtures-synthesized-only`).

### Phase 2 — GREEN: align the resolver + agent workspace to the user-visible workspace
- Fix the workspace-source divergence found in Phase 0 so `fetchUserWorkspacePath` (resolver and
  agent-sandbox `cwd`) resolves to the same per-user workspace the UI file tree renders from.
  Exact shape depends on Phase 0 (e.g., the workspace-scoping resolver returning the active
  workspace, not a stale `users.workspace_path`). Reuse existing workspace-resolver helpers; do not
  fork a new path.
- Preserve the two security gates verbatim: the `knowledge-base/` prefix gate and
  `isPathInWorkspace` containment.
- Per `cq-silent-fallback-must-mirror-to-sentry`: any new degraded path (workspace unresolved)
  must mirror to Sentry (the resolver already does for `fetchUserWorkspacePath` failure).

### Phase 3 — Secondary docs cleanup (PIR follow-ups)
- In `chat-rls-workspace-id-outage-postmortem.md`, edit two lines:
  - **Follow-ups (line ~153):** replace "File as a monitoring follow-up." with a citation to
    **#4849 (closed)** and **#4854 (open)**, stating the liveness item is tracked (the MVP alert
    landed in #4849; the scheduled defense-in-depth probe is deferred under #4854).
  - **Action Items (line ~161):** replace "tracked as a monitoring follow-up" with the same #4849
    / #4854 citation.
- Literal-text citations only — do NOT add `Closes #4849`/`Closes #4854` anywhere.

## Files to Edit
- `apps/web-platform/server/kb-document-resolver.ts` AND/OR the workspace-source resolver feeding
  `fetchUserWorkspacePath` / agent-sandbox `cwd` (exact file determined by Phase 0; candidates:
  `apps/web-platform/server/workspace-resolver.ts`, `apps/web-platform/server/cc-dispatcher.ts`).
- `knowledge-base/engineering/operations/post-mortems/chat-rls-workspace-id-outage-postmortem.md`
  (PIR follow-ups + action items).

## Files to Create
- `apps/web-platform/test/concierge-active-workspace-doc-parity.test.ts` (or extend
  `cc-dispatcher-concierge-context.test.ts`) — open-doc-in-assembled-context regression.

## Open Code-Review Overlap

None recorded at plan-write time (Task tool unavailable to query `gh issue list --label
code-review` in-pipeline; /work MUST run the overlap query against the final Files-to-Edit list:
`gh issue list --label code-review --state open --json number,title,body --limit 200` then `jq`
per path).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] A failing-first test asserts an open KB document body appears in the Concierge's assembled
  chat context; it passes after the Phase 2 fix. Verify the test FAILS on `origin/main` and PASSES
  on the branch (`./node_modules/.bin/vitest run <path>`).
- [ ] Phase 0 root-cause note in the PR body names the exact workspace-source divergence (UI
  file-tree workspace vs `fetchUserWorkspacePath` workspace) and the line where they diverge.
- [ ] The `knowledge-base/` prefix gate and `isPathInWorkspace` containment are unchanged (grep
  confirms both still present in the resolver).
- [ ] PIR "Follow-ups" no longer contains "File as a monitoring follow-up"; the liveness bullet
  cites **#4849** (closed) and **#4854** (open). `grep -c 'File as a monitoring follow-up'
  <pir>` returns 0; `grep -c '#4849' <pir>` and `grep -c '#4854' <pir>` each ≥ 1.
- [ ] PIR "Action Items" no longer contains "tracked as a monitoring follow-up"; it cites #4849/#4854.
- [ ] PR body uses neither `Closes #4849` nor `Closes #4854` (citation-only).
- [ ] `tsc --noEmit` + the full web-platform vitest node project pass.

## Domain Review

**Domains relevant:** Engineering, Product.

(Domain leaders + Product/UX gate could not be spawned — Task tool unavailable in this planning
environment. Recorded for /work to run the BLOCKING Product gate if any UI-surface file lands in
Files-to-Edit; current Files-to-Edit are server + test + docs only — no `components/**/*.tsx`,
`app/**/page.tsx`, or `app/**/layout.tsx` — so the mechanical UI-surface override does NOT fire and
the Product gate is **NONE** by file-surface.)

### Product/UX Gate

**Tier:** none (no UI-surface file in Files-to-Edit; the fix is server-side workspace resolution).
The user-facing behavior change is "the Concierge now reads the open doc" — a backend fix surfaced
through existing UI; no new surface.

### Engineering

**Status:** reviewed (inline). **Assessment:** workspace-source divergence between the agent
sandbox / document resolver and the UI file-tree; fix must converge them while preserving the two
read-containment gates. Adjacent to (but distinct from) the merged git-credential work (#4868) and
the in-flight git-workspace-plumbing plan — coordinate to avoid double-resolving workspace paths.

## Infrastructure (IaC)

Skip — pure code + docs change against already-provisioned surfaces (no new server, secret, vendor,
cron, or persistent process). No `apps/<app>/infra/*.tf` change.

## Observability

```yaml
liveness_signal:
  what: "Concierge `concierge document context resolved` breadcrumb with documentContentBytes > 0 on open-doc turns"
  cadence: "per cold-Query Concierge dispatch with a context.path"
  alert_target: "Sentry (existing cc-pdf-resolver breadcrumb + cc-pdf-resolver-skip captureMessage)"
  configured_in: "apps/web-platform/server/ws-handler.ts emitConciergeDocumentResolutionBreadcrumb"
error_reporting:
  destination: "Sentry via reportSilentFallback / mirrorWithDebounce (feature: kb-concierge-context)"
  fail_loud: true
failure_modes:
  - mode: "workspace path unresolved/unpopulated → empty documentContent"
    detection: "cc-pdf-resolver-skip captureMessage (path provided, documentKind null) + documentContentBytes=0 breadcrumb"
    alert_route: "Sentry warning, tag feature=cc-pdf-resolver op=skip"
  - mode: "path-traversal / prefix-gate drop"
    detection: "resolver returns {} (documentKindResolved null) on a knowledge-base/ path"
    alert_route: "Sentry warning (same skip event)"
logs:
  where: "Sentry breadcrumbs (cc-pdf-resolver, cc-pdf-extractor) + pino server logs"
  retention: "Sentry default project retention"
discoverability_test:
  command: "./node_modules/.bin/vitest run apps/web-platform/test/concierge-active-workspace-doc-parity.test.ts"
  expected_output: "assertion: assembled context contains the open KB doc body; test passes"
```

## Test Scenarios
- Open KB text doc + ask → assembled context contains the doc body (regression test).
- Workspace path unresolved → resolver mirrors to Sentry and returns no body (degraded, fail-loud).
- Path outside `knowledge-base/` → resolver returns `{}` (gate preserved; no cross-read).
- PIR grep: "File as a monitoring follow-up" / "tracked as a monitoring follow-up" both gone;
  #4849 and #4854 both present.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO, or omits the
  threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold =
  single-user incident.)
- #4849 / #4854 are **citations**, not work targets — never `Closes`/`Ref` them in the PR body or
  pass them as work-item references.
- Do NOT re-plumb the quoted-selection (⌘⇧L) path — it already reaches the request as blockquote
  text via `quoteRef`/`insertQuote`. The gap is the open-document body only.
- Do NOT duplicate the git-credential / git-workspace-mount work owned by PR #4868 and the
  `2026-06-03-fix-concierge-git-workspace-plumbing-per-user-repo-plan.md` branch. This plan fixes
  the document-**read** workspace-source divergence; coordinate so both don't fork workspace-path
  resolution.
- Regression test path MUST match `test/**/*.test.ts` (vitest node glob) and run via vitest, not
  `bun test` (bunfig blocks bun discovery, #1469).
- This plan was authored without the Task-spawned research/review/deepen agents (tool unavailable
  in environment). /work SHOULD run the Open Code-Review Overlap query and, given
  `brand_survival_threshold: single-user incident`, invoke deepen-plan/ultrathink for the
  substance-level review (data-integrity-guardian + security-sentinel + architecture-strategist)
  that plan-review cannot provide.
