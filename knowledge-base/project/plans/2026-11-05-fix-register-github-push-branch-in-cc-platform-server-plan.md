---
title: "Register the approval-gated github_push_branch tool in the cc platform server"
date: 2026-11-05
slug: register-github-push-branch-in-cc-platform-server
branch: feat-one-shot-11636-cc-github-push-branch
issue: 11636
lane: cross-domain
type: fix
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
refs: [11636, 11635, 9601]
closes: []
---

<!-- Spec lacks a valid lane: key (no spec.md exists for this one-shot branch) - defaulted to cross-domain (fail-closed). -->

# Register the approval-gated `github_push_branch` tool in the cc platform server

Ref #11636. Ref #11635. Epic Ref #9601 (agent security hardening). The PR closes nothing: `closingIssuesReferences` must be `[]`.

## Enhancement Summary

**Deepened on:** 2026-11-05
**Passes run:** plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow; named-panel CPO and CLO advisories; CTO rulings on 10 forks), sharp-edges verification pass (15 findings, all applied), deepen halts 4.6, 4.7, 4.8, 4.11, 4.12 (all pass; 4.9, 4.10, 4.13 not triggered: no UI file, no store or migration, no new autonomous task), `soleur:gdpr-gate` (no findings), verify-the-negative and post-edit self-audit sweeps, institutional-learnings search.

### Key improvements

1. Strict cc handler (`requireGrant`) so an allow that bypasses the gate cannot push; legacy runner byte-identical.
2. Fail-closed default-branch lookup, bounded flag read, distinct reasons, and a Sentry-visible outcome event (the log shipper drops info, so pino alone would have been dark).
3. Test plan corrected against the real code: literal expectations instead of a self-referential baseline, the mocks the cc-dispatcher suite needs, mutant-anchor protection for `approval-guard1-mutation.test.sh`, and isolation tests (sandbox hook matcher, cross-Query grants, cross-conversation consume).
4. Hard flip precondition recorded for the pre-existing `.git` hook and config exposure on the approved push (ADR flip-checklist item 9), plus the registration-policy statement for entitlement and repo.

### New considerations discovered

- The sandbox env drops the git token variables under open web egress, so the "no credential in the sandbox" claim is about what this tool adds, not about every path.
- The gate approves before the handler's protected-branch check, so a push to a protected branch consumes an approval and is then refused (pre-existing, recorded, not folded).
- The CTO asked for a tracking issue for the hook exposure; the brief forbids filing issues in this run, so the row in `decision-challenges.md` carries it for `soleur:ship` to file.

## Overview

Concierge sessions that hold the workspace web-egress grant run in the cc dispatcher
(`apps/web-platform/server/cc-dispatcher.ts`). Their sandbox has no way to push a branch, and the legacy runner's
push tool (`github_push_branch`, `server/github-tools.ts`) is not registered there. PR #12137 (Ref #11635) gave the
cc dispatcher the ADR-309 approval gate, one per-Query `ExecutionGrants` and a fail-closed switch, and deliberately
registered no approval-required tool. This plan registers exactly one: `github_push_branch`, closed over owner, repo,
installation id, workspace path and default branch the way `edit_c4_diagram` is, pushing through the existing
`server/push-branch.ts` so no credential enters the sandbox.

Registration is dark by construction: it needs the `approval-queue` flag (default off; flipping it is an operator
hold and this PR creates or flips nothing), the workspace web-egress grant, a non-`support` persona, and a connected
repo plus installation. With the flag off or unreadable the cc tool set, `platformToolNames` and
`registeredPlatformToolNames` are byte-identical to today. With it on, a push goes through the gate, the gate writes a
grant carrying the approved commit, and the handler pushes exactly that commit or refuses.

Design, in one paragraph. A new module `server/cc-github-push.ts` owns the registration decision (injectable flag
read, default-branch lookup, entitlement, persona, repo/installation) and returns the built tool plus a machine
reason. `server/github-tools.ts` gains an exported `buildGithubPushBranchTool` that `buildGithubTools` reuses (legacy
behaviour unchanged) and that takes a required `requireGrant` boolean, which cc sets so the handler refuses without a
gate-written grant even when the sticky `enforcing` bit never turned on. `cc-dispatcher.ts` hoists the one
`ExecutionGrants` above the tool build, hands the same object to the registrar and to the gate deps, merges the tool
into the single `soleur_platform` server, adds its FQN to the `canUseTool` `platformToolNames`, appends a short prompt
addendum, and publishes the registered FQN to a per-conversation Map that the warm-path unregistered-tool mirror
consults. `readCcMcpAllowlist` stops throwing for that one name; the census and sweep tests expect exactly this
registration. The ADR-309 addendum records the verified workspace-capture evidence, the allow-source pin and the
flag-flip preconditions.

## Research Reconciliation: Spec vs. Codebase

| Brief claim | Reality (verified on this branch) | Plan response |
|---|---|---|
| Grants created "~cc-dispatcher.ts:2902, after the tool block ~:2597-2650" | `const approvalGrants = new ExecutionGrants()` and `const connectedRepoSlug` sit after the whole c4 block (`const c4McpServers = readCcMcpAllowlist()` through `(c4McpServers as Record<string, unknown>).soleur_platform = platformServer`) and before `const ccDeps: CanUseToolDeps`; `createApprovalGateDeps({... grants: approvalGrants})` is inside `ccDeps`. Line numbers drift, so work from these anchors. | Hoist both consts above `const c4McpServers` (they depend only on `connectedOwner`/`connectedRepo`, set at 2167). |
| `activeWorkspaceId` is a const set once per factory call (~:1978) | Confirmed: `const activeWorkspaceId = activeWorkspace.workspaceId;` (right after the `resolveActiveWorkspace` call); the same id is passed to `fetchUserWorkspacePath`, `readCurrentRepoUrlResult`, `resolveInstallationId` and the gate (`workspaceId: activeWorkspaceId`). `workspacePath`, `connectedOwner`, `connectedRepo` are consts too. | Ruling 1 verified. Add the equality test plus a source pin that the binding is never reassigned. |
| Handler already refuses without a grant (github-tools.ts ~:194-202) | Only partly: `checkGrant` returns `legacy` when `grants.enforcing` is false, and the handler then pushes `HEAD` with `commitSha` undefined. `enforcing` turns true only when the gate runs. | Add `requireGrant` (CTO Fork 6): in cc a `legacy` result is refused as `grant_missing`. This also bounds the unverified "another allow source" residual. |
| `readCcMcpAllowlist` throws for every approval-required name | True (`isApprovalRequiredTool(fqn)` branch). It returns `{}` regardless of names, so the throw is a backstop, not a registration route. | Relax for the one name via an exported constant in `cc-github-push.ts`; every other required name and the denylist still throw. Registration never reads the env. |
| `test/approval/tools-census.test.ts` forbids any approval-required name in the cc sweep | True, and `gatedNotExempt` would also flag the push tool (gated, required, not exempt). | Sweep helper takes an allowed-set: required names must equal exactly `[push FQN]` when the push tool is built, and `[]` otherwise; gated-not-exempt excludes only that name. |
| `runner-census.test.ts` "cc imports none of the BUILDERS" | `cc-dispatcher.ts` will import `./cc-github-push` (which imports `github-tools`), not `github-tools` itself, so the import census keeps holding. | Keep it, add the positive pins: one `new ExecutionGrants()`, the same identifier passed to the gate deps AND the registrar. |
| `builder-grants-required.test.ts` derives builders by content | It maps every builder to the first interface declaring `grants`; a second builder in `github-tools.ts` would pair with the wrong interface. `approval-guard1-mutation.test.sh` pins exact anchors and failure strings in that file. | CTO Fork 7: pair by `Build<Rest>Opts`, inverse check, keep message strings; new interface spells `readonly grants: ExecutionGrants;` so the `\n  grants: ExecutionGrants;` anchor stays unique; run `--check-anchors`. |
| "Related deferred items" triggers (brief ruling 4) | They live in #11534: "next PR touching `server/approval/*`" (duplication and adapters) and "next real-SDK probe re-run" (probe static checker and mutation `detect` strings). | The PR adds no file under `server/approval/` (the one constant lives in `cc-github-push.ts`); the probe re-run fires the second trigger. PR body states both, items stay deferred. |

## Research Insights

**Premise validation (Phase 0.6).** #11636 is open; #11635 is open and its implementing PR #12137 is merged (the issue
stays open by instruction); #11637 and #11640 are cited by the issue and the decision-challenge issue and are open.
The collision pre-check reports one open PR naming #11636, #12188, which is this branch's own draft PR (empty body,
no files). The only foreign hits are other worktrees' test runners. Every cited file and symbol exists on this branch
(`server/github-tools.ts`, `server/push-branch.ts`, `server/approval/{gate,gate-flow,grants,tools,flag}.ts`,
`test/approval/{tools-census,runner-census,builder-grants-required}.test.ts`). The proposed mechanism (register a
gated tool behind the existing gate) matches ADR-309 §"Adding a gated tool" and its Addendum; no ADR rejects it, and the
Addendum names this exact PR as the one that must settle the pending-approval question and verify the workspace capture.

**Property List (Phase 0.6b).**

1. P1. A cc session can push a feature branch only after the workspace Owner approved that exact action.
2. P2. The commit pushed is the commit the Owner saw (grant carries `headSha`; `pushBranch` takes `commitSha`).
3. P3. The push tool adds no credential to the sandbox: the push runs in the dispatch process through `gitWithInstallationAuth`, whose askpass script is token-free and whose token lives only in the child process environment. (The existing in-sandbox `GIT_INSTALLATION_TOKEN`/askpass path for non-entitled sessions is separate and unchanged; under open web egress the sandbox env drops those variables, which is exactly why entitled sessions need this tool.)
4. P4. With the flag off, unreadable, or any other precondition false, the cc tool set is byte-identical to today.
5. P5. The tool is never registered without the gate dependency and the same grants object.
6. P6. The handler refuses without a gate-written grant, even if the gate never ran.
7. P7. Gate and handler cannot disagree about workspace, repo or workspace path.
8. P8. The user learns of a pending or denied push from the model, through the existing durable surfaces; no new card.
9. P9. Every other approval-required name, and the denylist, still cannot be promoted through `CC_MCP_ALLOWLIST`.
10. P10. The default branch cannot be pushed to because a lookup failed.

**Cut List (Phase 0.6b).**

- New in-chat approval card or inbox UI -> P8 -> the gate already emits the `approval_request` frame, writes the
  `approval_request` row and inbox item and sends push/email (ADR-309); brief ruling 2 forbids a new card.
- Per-turn grants in cc (rework of the grants lifetime) -> P1/P2 -> per-Query lifetime is already stricter and the
  ADR-309 Addendum scopes per-turn grants out until a builder reads grants; one builder now does, and `take` is one-shot.
- `createProtectedBranchResolver` reuse for the single default-branch string -> P10 -> it is session-memoised and returns
  `authoritative: false` instead of failing; a direct lookup with the same 3 s timeout is simpler (CTO Fork 1).
- Other gated tools in cc (`create_pull_request`, `github_trigger_workflow`, ...) -> none of the properties -> out of scope; they stay unregistered and throw.
- New flag, environment, migration, copy change -> operator holds / not needed.
- Re-resolving eligibility per dispatch on the warm path -> P4 -> replaced by publishing the registered set from the factory (CTO Fork 2).
- Setting `grants.enforcing = true` from the registrar instead of a `requireGrant` builder parameter (plan-review
  suggestion) -> P6 -> kept `requireGrant`: `enforcing` is runtime state written by a module other than the handler and
  its documented meaning is "the flag evaluated true in this Query" (ADR-309); a required boolean on the builder is a
  compile-time pin (a forgotten wiring does not compile) and leaves the legacy runner untouched. CTO Fork 6.
- Looking the default branch up inside the handler (plan-review suggestion, CTO Fork 1 option C) -> P10 -> rejected by
  the CTO: the tool would stay advertised while unable to run safely and a network failure would move into the
  model-visible path. Accepted cost: with the flag on, an entitled cold Query pays one bounded (3 s cap, warm token
  cache) request; flag-off and ineligible sessions pay nothing.
- Allow-source pin as a YAML-parsing scanner (plan-review: dominated by `requireGrant`) -> P1 -> shrunk to a minimal text
  scan (below, Guard 2); the strict handler is the safety property, the scan only keeps the ADR claim checkable.

**Institutional context.** ADR-309 (Addendum 2026-11-05, "Preconditions for the first PR that registers an
approval-required tool in cc"), ADR-305 (gated tools never enter `allowedTools`), ADR-311 (broker spike; this push
tool is the "quickest route" named in #11640), `#5388` c4 precedent (`resolveC4FlagEnabled`, fail closed, persona gate),
`#9558` (support never mints or writes). Deferred items: #11534 table rows quoted in the Research Reconciliation table.
No `knowledge-base/project/learnings` file covers cc grants or the push tool (searched for `ExecutionGrants`,
`approvalFailClosed`, `github_push_branch`, `resolveC4FlagEnabled`; one unrelated hit).

**Technical rulings (CTO agent, 2026-11-05).** Eight forks ruled and persisted in
`knowledge-base/project/specs/feat-one-shot-11636-cc-github-push-branch/decision-challenges.md`. Decisions used
below: fail-closed default-branch lookup (F1); factory-published registered set (F2); prompt addendum (F3);
plugin-tree allow-source pin (F4); `webEgressEntitled` grant boolean (F5); `requireGrant` (F6); registrar module and
per-builder interface pairing (F7); `fix(approval):` prefix (F8).

**Domain advisories (2026-11-05).** CPO: approved at product level; flip order is toggle copy, CLO check, dogfood on
the Owner workspace, wider rollout; the PR body must say nothing changes for users until the flag flips. CLO: no new
personal-data field, store or subprocessor; no Art. 30 trigger; the toggle copy ("can't push to git remotes", two strings in `components/settings/web-egress-toggle.tsx`; sweep with `push to git remotes`) becomes
inaccurate once the flag is on and the tool is registered, so it is a flip precondition, not a change in this PR.

## Open Code-Review Overlap

Checked the planned file list against open `code-review` issues (two-stage `gh --json` then `jq --arg`):
`server/cc-dispatcher.ts` is named by #3243 ("arch: decompose cc-dispatcher.ts into focused modules") and #3242
("tool_use WS event lacks raw name field"). No other planned file matches.

- #3243: **Acknowledge.** This PR adds one small module (`cc-github-push.ts`) instead of growing the dispatcher, which
  is in the direction of #3243, but a decomposition is its own cycle; the issue stays open.
- #3242: **Acknowledge.** Different concern (WS tool_use payload shape); untouched.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Concierge chat that pushes a commit to the user's connected
  GitHub repository without the workspace Owner's approval, or pushes a different commit than the one the approval card
  named (a branch on their repo carrying work they never reviewed), or a chat where the agent says a push happened
  when the gate actually held or denied it. With the flag off (the state at merge) none of this is reachable.
- **If this leaks, the user's workflow is exposed via:** the GitHub App installation token. It is minted and used in the
  dispatch process only (`gitWithInstallationAuth`); the failure to guard against is the token or a push capability
  reaching the sandbox or the model-visible tool result. The tool takes only `branch` and `force`; owner, repo,
  installation, workspace path and default branch are closed over, never model input.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one unapproved or wrong-commit push to one user's repository, by an agent
  the user trusted with web access, is a trust-breaking incident for the whole approval story, so the aggregate tier
  is not enough; `requires_cpo_signoff: true` is set and the CPO advisory above is the plan-time sign-off.

## Architecture Decision (ADR/C4)

Detected: first registration of an approval-required tool on a path that had none (a trust-boundary and invariant
change), and the closing of two UNVERIFIED items the ADR-309 Addendum carries. Both are deliverables of this plan.

### ADR

Amend ADR-309 with a new dated `## Addendum - 2026-11-05 (Ref #11636, epic Ref #9601)` (ordinal unchanged; status stays
`adopting`). Content, in order:

1. What registers, under which five conditions, and what a false condition leaves byte-identical.
2. Workspace-capture precondition: **verified** (replaces "UNVERIFIED"), with the evidence: `activeWorkspaceId` is a
   `const` assigned once; gate deps (`workspaceId`, `repoSlug`, `workspacePath`) and the tool closure (`owner`, `repo`,
   `workspacePath`) take the same bindings; the equality test and the never-reassigned source pin named by file.
3. Allow-source treatment (brief ruling 3, CTO Fork 4): the plugin-tree pin and what it does not see (SDK resolution
   order for an MCP allow rule from a skill stays UNVERIFIED beyond the source scan; `settingSources: []` itself is
   pinned by T7 in `cc-dispatcher-real-factory.test.ts`); the handler's `requireGrant` as the second line.
4. Where the Owner finds a pending approval (brief ruling 2): the existing durable surface (row, inbox item,
   push/email, the `approval_request` frame the gate already emits); the model-relayed static text and the addendum.
5. Default-branch fail-closed rule and its staleness window; `readCcMcpAllowlist` relaxation limited to one constant.
6. Flip preconditions added to the flag-flip checklist as item 8 (toggle copy reworded first; compliance-posture
   addendum for the new action type and the PA-38 `canonical_action` wording check; approval card and notification
   name commit, repo and branch; the "not switched on for any workspace Jikigai does not own" qualifier is kept).
   Mirror the item into the archived handover copy the checklist says to edit together
   (`knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md`).
7. Update the sentence "No cc tool builder reads a grant yet and the cc path registers no `APPROVAL_REQUIRED_TOOLS`
   member" by appending a pointer to this addendum (the earlier addendum stays; dated addenda are append-only).
8. Probe re-run (§"Adding a gated tool" item 6) result line, and the #11534 triggers evaluated.
9. Registration policy statement (CTO Fork 10): entitlement, repo and installation are captured at Query construction
   and are registration policy, not per-call authorization; every push needs a fresh Owner approval regardless; the
   idle reaper bounds a Query; a revoked egress grant leaves a tool whose push is server-side and still approval-gated;
   a disconnected repo or revoked installation fails at GitHub with an installation-token error and surfaces as a tool
   error; a repo reconnected to a different repo mid-Query still pushes to the captured `repoSlug`, which the approval
   card shows (`REPOSITORY`, `BRANCH`, `COMMIT` rows in `server/approval/render.ts`).
10. Flip-checklist **item 9, a hard precondition for the flag beyond the Jikigai canary** (CTO Fork 9): the approved push
    runs `git push` in the agent-writable workspace, in the dispatch process, with the installation token in the child
    environment. An agent-written `.git/hooks/pre-push`, or a `remote.*.pushurl` / `url.*.insteadOf` in `.git/config`,
    would run or redirect outside the sandbox on an Owner-approved, benign-looking push (the card shows repo, branch and
    commit, not hooks). Pre-existing (the legacy runner has it with the flag off) and recorded as UNVERIFIED in ADR-309;
    the cc registration widens who can reach it, so before wider enablement either verify with a live probe that the cc
    sandbox cannot write `.git/hooks` or `.git/config`, or harden `pushBranch` (`-c core.hooksPath=/dev/null` plus
    neutralising `url.*.insteadOf` / `remote.*.pushurl` through `GIT_CONFIG_COUNT` env entries). The cohort rule is a
    policy control, not a technical one; the item says so. Not folded into this PR (partial fix, edits the shared legacy
    push path); the tracking issue is filed by `soleur:ship` from the decision-challenges row (this run files none).
11. Negative-claim sweep (Phase 3.1): every sentence the registration falsifies is found by grep and updated or
    pointed forward: `closure-only` (comment above `approval: createApprovalGateDeps` in `cc-dispatcher.ts`),
    `registers no`, `no cc tool builder`, `until a builder reads grants`, `UNVERIFIED`, and the test titles "no
    approval-required tool is registered in cc" (`tools-census.test.ts`) and any equivalent in `runner-census.test.ts`.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`) at work time, before writing the conclusion. Pre-check
done at plan time: external human actor = the workspace Owner approver (already the `founder`/Owner access edge to
`approvalStore`, edge `webapp -> approvalStore` in `model.c4`); external system = GitHub (edge `engine -> github "Git operations and CI"`,
already carries the installation-token push) and the approval store (`webapp -> approvalStore`,
`engine -> approvalStore`); data store touched = `platform.infra.approvalStore` (already modeled and
included in `views.c4`). The `engine -> approvalStore` edge description says hosted sessions run the gated branch
in-process; that sentence is the one this change makes incomplete (the Concierge now reaches it too). Plan task:
extend that one edge description with the cc/Concierge clause (one sentence, no new element, no new edge, no
`views.c4` change), then run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and
`plugins/soleur/test/c4-count-parity.test.sh`. A "no further C4 impact" statement in the work notes must cite these
checks, not a keyword grep.

### Sequencing

The ADR addendum describes the target state with the status left `adopting`; nothing is deferred to a follow-up issue.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Eight forks ruled (see decision-challenges.md). Risks adopted into the plan: one grants object shared by
identity (test), `readCcMcpAllowlist` mixed-list and other-name throws (test), `platformToolNames` appended only from
the registration result (never a separate re-resolve), flag error as throw/timeout/undefined cases, support persona
with every other precondition true, legacy runner parity, write-rate estimate, one distinct reason per
non-registration, ADR recorded.

### Product (CPO)

**Status:** reviewed
**Assessment:** Approved at product level; no new UI is correct. Flow gaps recorded: a non-Owner requester needs the
"waiting on the Owner" wording (the existing deny text names the Owner and the saved request), SHA binding and
fail-closed on a moved HEAD (covered), no success claims on a non-pushed result (addendum test), requester-visible
outcome after the chat ends (existing inbox/notification path; not widened here). Copy drift is a hard flip
precondition (ADR item 6 above).

### Legal (CLO)

**Status:** reviewed
**Assessment:** `soleur:gdpr-gate` was run against this plan at deepen time (trigger: brand-survival threshold `single-user incident`): no Critical or Important finding (no schema, FK, vendor or special-category change). No new personal-data field, store or subprocessor; no new processing activity (a commit pushed to the
user's own repo). The toggle copy becomes inaccurate at flag-on: do not edit in this PR (operator hold), record as a
flip precondition. Compliance-posture addendum and PA-38 wording check are flip preconditions, not changes now.

## Observability

```yaml
liveness_signal:
  what: Sentry info-level outcome event (infoSilentFallback, feature cc-push-registration, tag reason, the c4-save-outcome precedent) emitted once per cold Query construction that reaches the registrar, plus a pino info line that stays on stdout (the log shipper keeps only warn and above, so the pino line is a local aid, not a shipped signal); fields registered, reason, flagEnabled, entitled, persona, hasRepo, hasInstallation, defaultBranchResolved
  cadence: once per cold cc Query construction (never per request or per tool call)
  alert_target: none for the outcome event (read as a rate in Sentry); the error-class reasons mirror to Sentry as issues (below)
  configured_in: apps/web-platform/server/cc-github-push.ts
error_reporting:
  destination: Sentry web-platform via reportSilentFallback (feature cc-dispatcher), ops cc-push-flag-resolve and cc-push-default-branch-resolve
  fail_loud: a push tool that silently vanishes shows as a Sentry issue with the op above, or as a cc-push-registration outcome event carrying the reason; handler refusals use the existing approval-grant-refused warn op (reason grant_missing, commit_mismatch, commit_unavailable)
failure_modes:
  - mode: approval-queue flag read throws or times out, so the push tool is not registered
    detection: sentry-correlation - the real flag seam (isApprovalQueueEnabled) swallows every read error and returns false, so in production this mode is observed through its existing debounced flagReadFailed op and shows as reason flag-off on the outcome event; the registrar's own try/catch (reportSilentFallback op cc-push-flag-resolve, reason flag-error) is a defensive net for a future seam change and is exercised by seam-only tests
    alert_route: Sentry issue on the web-platform project
  - mode: default-branch lookup fails or times out, so the push tool is not registered
    detection: sentry-correlation - reportSilentFallback op cc-push-default-branch-resolve (a new name: the op default-branch-resolve already belongs to server/resolve-protected-branches.ts with a different meaning); the outcome event carries reason default-branch-unresolved
    alert_route: Sentry issue on the web-platform project
  - mode: a push call reaches the handler with no gate-written grant (a wiring defect or an allow source outside the gate)
    detection: sentry-correlation - existing approval-grant-refused op fires on the requireGrant refusal path (reason grant_missing); test pins that it fires
    alert_route: existing approval alert routing (Sentry issue on the web-platform project)
  - mode: model reports success for a held or denied push
    detection: pino - gate logs allow/deny through logPermissionDecision; the prompt addendum plus a unit test on the addendum text; the only success text the handler returns is the compact JSON with pushed true
    alert_route: Sentry for gate errors; no automated detector for model prose (accepted, stated in the ADR addendum)
  - mode: warm turn false-positives as an unregistered-tool use
    detection: sentry-correlation - the existing cc-mcp-tier unregistered-tool-invoked mirror; the factory-published Map removes the false positive and a test pins that a registered push call on a warm turn does not mirror
    alert_route: Sentry issue (debounced per user)
logs:
  where: pino to stdout, shipped to Better Stack; Sentry for the two mirrored ops
  retention: Better Stack and Sentry plan retention (not changed by this PR)
discoverability_test:
  command: grep -o 'feature: "cc-push-registration"' apps/web-platform/server/cc-github-push.ts
  expected_output: feature: "cc-push-registration"
```

Affected-surface note (Phase 2.9.2): `cc-dispatcher.ts` is a named blind surface. The single registration event carries
every discriminating field (registered, reason, flagEnabled, entitled, persona, hasRepo, hasInstallation,
defaultBranchResolved), so one event separates all competing causes of "the tool is missing in this chat". The
decision runs in the dispatch process, not the sandbox, so no in-sandbox probe applies.

Write-rate estimate: identical proposals share one live row (`approval_request_live_uniq`); pushes with a different
branch or commit are different actions and each creates a row, bounded by the migration caps (5 pending per
conversation, 20 per workspace). Expected rate is a handful of rows per conversation at most; WAL impact negligible.

## Guard Contract

### Guard 1 - cc approval-tool registration sweep (derived)

**Property.** The cc registry function can register no approval-required tool other than `github_push_branch`, and
`github_push_branch` only through the gated registrar with the one grants object.

**Assembly.** Every path that can put a tool into the cc `soleur_platform` server or its `canUseTool` name list: the
single `createSdkMcpServer(` call fed by `soleurPlatformToolsForTests` (narration, c4, approval tools, crm); the
`platformToolNames` array in the `createCanUseTool` call; `readCcMcpAllowlist` (the env route, which returns `{}`);
`CC_REGISTERED_PLATFORM_TOOL_NAMES` and the per-conversation Map; a second MCP server or `pluginMcpServerNames`. The
chokepoint is the registry function plus the registrar; the sweep runs over BOTH crm-lead settings, with and without
the registrar's tools, and the source pins cover the non-registry routes.

**Mutation matrix.**

| # | Edit (must turn a named test RED) | Target |
|---|---|---|
| 1 | Register `email_send` (or any other required tool) next to the push tool in the registry | sweep: required set must equal exactly the push FQN |
| 2 | Registrar returns the tool when the flag is off, or when `webEgressEntitled` is false, or for persona `support` | registrar matrix tests (one row each; second row added after a compliant first) |
| 3 | Registrar throws away `grants` and builds the tool with a fresh `new ExecutionGrants()` | runner census (same identifier to gate and registrar) and identity test |
| 4 | Remove the push FQN from `platformToolNames` while the tool stays registered, or append it from a separate re-resolve | real-factory capture of the `createCanUseTool` args |
| 5 | `readCcMcpAllowlist` stops throwing for `email_send` after a compliant `github_push_branch` in the same env | allowlist test with mixed list in both orders |
| 6 | Sweep dispatch: make `registeredNames()` return `[]` | non-vacuity floor test (at least 10 names including the push tool) |
| 7 | Add a second `createSdkMcpServer(` call | existing structural pin |

**Harness rows.** Edit to the suite: change the allowed-set constant used by the sweep to include `email_send`, the
self-test must go RED (the sweep reports it). Must-PASS non-canonical input: a fake registry containing only
narration tools, and one containing narration plus the push tool, both pass with the right `required` set.

**Anchor.** The allowed-set constant lives in `server/cc-github-push.ts`; a weakening needs an edit to that file AND
the census test expectation, and the real-factory test independently asserts the registered names for flag on and off.
A one-diff weakening of both is reviewed by the CODEOWNERS path for `server/` and by the user-impact review.

### Guard 2 - allow-source pin over the platform plugin tree (minimal text scan)

**Property.** No platform-deployed plugin file can name an approval-required MCP tool, or the whole
`mcp__soleur_platform` server, in a position that pre-allows it ahead of `canUseTool`.

**Assembly.** Every `*.md` and `hooks.json` under `plugins/soleur/{skills,agents,commands,hooks}`, plus
`plugins/soleur/.mcp.json` and the `mcpServers` key of `plugins/soleur/.claude-plugin/plugin.json` when present,
discovered by walking the tree (never a hand-kept list), scanned as text: any line that contains an approval-required FQN, a bare
`mcp__soleur_platform` followed by `*` or end of token, or the server prefix inside an `allowed-tools:` / `tools:`
frontmatter line. A text scan (not a YAML parser) is deliberate: it over-reports (prose that names the tool inside
frontmatter is a hit) rather than under-reports, and it cannot be fooled by list-versus-string syntax. Current matches measured at plan time: 0 (the only `mcp__soleur_platform` mention in the plugin tree is prose in
`skills/plan/references/plan-sharp-edges.md`, outside the scanned frontmatter lines). Floor: the walk must see at
least 100 `skills/*/SKILL.md` files (106 tracked today), asserted per directory, so a walker that returns zero or one
root cannot read green. The scan is defence in depth: the strict handler (Guard 3) already
makes an out-of-gate allow inert for this tool.

**Mutation matrix.**

| # | Edit | Target |
|---|---|---|
| 1 | Add `mcp__soleur_platform__github_push_branch` to one skill's `allowed-tools` line | scan fails naming the file |
| 2 | Add `mcp__soleur_platform__*` as a second entry after a compliant first entry | scan fails (second member) |
| 3 | Make the walker return zero files | floor test fails (no "0 checked" green) |

**Harness rows.** Canary: a synthetic offending fixture directory must make the scanner report a violation. Must-PASS:
a fixture skill with an unrelated `mcp__plugin_x__tool` allow entry and prose elsewhere in the body passes.

**Anchor.** The approval-required FQNs are imported from `server/approval/tools.ts` (not restated), so adding a tool
there tightens the pin; the pin does not see SDK resolution order or a changed `settingSources` (stated in the ADR).

### Guard 3 - strict grant requirement in the push handler

**Property.** A cc push call never reaches `pushBranch` without a gate-written grant carrying the approved commit.

**Assembly.** The exported `buildGithubPushBranchTool` handler (the only place `checkGrant` is called for push), reached
by both builders (`buildGithubTools` passes `requireGrant: false`, the registrar passes `true`); the three grant
outcomes `refuse`, `legacy`, `granted`; the commit checks (`headSha` absent, `ApprovedCommitUnavailableError`).

**Mutation matrix.**

| # | Edit | Target |
|---|---|---|
| 1 | Drop the `requireGrant` branch so `legacy` falls through | test: enforcing false + requireGrant true => refused, `pushBranch` not called |
| 2 | Remove `reportGrantRefused` on the strict path | test: refusal is reported with reason grant_missing |
| 3 | Make `requireGrant` default to false / optional | `builder-grants-required` style type pin (field is required) |
| 4 | Remove the headSha-absent refusal after a compliant first assertion | existing PG1 mutant (`test/approval-guard1-mutation.test.sh`) |
| 5 | Legacy builder passes `requireGrant: true` | legacy-parity test (enforcing false, no grant => HEAD push as before) |

**Harness rows.** Edit to the suite: delete the strict-path assertion, the mutation battery row 1 must then survive
(proves the row is load-bearing, so add mutant rows to `approval-guard1-mutation.test.sh` (three, listed in 2.4) and run them with `--only`).
Must-PASS: a granted call with a valid 40-hex commit pushes exactly `<sha>:refs/heads/<branch>`.

**Anchor.** Grants are written only by the gate (`putGrant` after consume); the handler cannot mint one, and the model
has no handle. A weakening needs edits to the handler, the mutant table and the tests together.

## Implementation Phases

Process rules: tests first (`cq-write-failing-tests-before`); `apps/web-platform` uses vitest
(`cd apps/web-platform && npx vitest run <files>`); CI is the ship gate, do not await the slow local `--affected`
battery; never touch `dsar-export-allowlist.ts`; run the egress-token grep in the "Before push" step; run
`bash scripts/markdown-lint.sh --repo-sweep` before committing markdown.

### Phase 0 - Baseline (census tests FIRST)

- 0.1 `cd apps/web-platform && ls node_modules >/dev/null 2>&1 || npm ci` (deps are present in the worktree today).
- 0.2 Run and record green baseline: `npx vitest run test/approval/tools-census.test.ts test/approval/runner-census.test.ts test/approval/builder-grants-required.test.ts test/approval/cc-approval-fail-closed.test.ts test/approval/permission-callback-gated-branch.test.ts test/cc-mcp-tier-allowlist.test.ts test/build-allowed-tools-census.test.ts test/server/crm-lead-dispatch.test.ts test/cc-dispatcher-real-factory.test.ts test/github-tools-push-grant.test.ts`, then derive the full consumer list with `git grep -l "soleurPlatformToolsForTests\|readCcMcpAllowlist\|buildGithubTools" -- apps/web-platform/test apps/web-platform/scripts` and add any file not named here.
  The cc-dispatcher import is ~13 s cold; that is expected.
- 0.3 `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors` (baseline: all rows apply).

### Phase 1 - RED tests (write before code)

Order: write 1.7 first (the second exported builder is what forces the `builder-grants-required` pairing change, and
every anchor in `approval-guard1-mutation.test.sh` depends on it), then 1.2, 1.1, 1.3-1.6, 1.8.

1.1 `test/cc-github-push.test.ts` (new, no cc-dispatcher import): registrar matrix with injected seams. One test per
row (the flag throw, timeout and non-`true` value rows are one parameterized `it.each`, seam-only: the real seam never throws): all preconditions true
registers; flag off; flag throws; flag rejects after a timeout; flag returns undefined; `entitled` false; `entitled` true with no forwarder handle (CTO Fork 5); persona `support` with all else true;
no owner/repo; no installation; default-branch lookup throws; lookup times out; lookup returns an unsafe string.
Asserts the machine `reason`, that the lookup is NOT called when an earlier precondition is false (no extra round trip
on the dark path), that `flagEnabled` is read with the same `{userId, workspaceId}` identity as the gate, and that the
returned tool's `toolNames` is exactly `["mcp__soleur_platform__github_push_branch"]`.
One case runs the registrar with NO `isEnabled` override and `getRuntimeFlag` mocked true / false / throwing, so the production default path is exercised and not only the injected seam (learning 2026-07-17, test-only override seam).
1.2 `test/github-tools-push-grant.test.ts` (edit): add `buildGithubPushBranchTool` cases: `requireGrant: true`,
`enforcing: false`, no grant => refused, `pushBranch` not called, `approval-grant-refused` reported (reason
`grant_missing`); granted with a valid commit => `pushBranch` called with `commitSha` and the closed-over
owner/repo/workspacePath/defaultBranch; granted with no `headSha` => `commit_mismatch`; unavailable commit =>
`commit_unavailable`; `pushBranch` throwing after a granted `take` (non-fast-forward, network) => the isError text
`Error pushing branch: ...` is returned, the grant is spent, and an immediate second call is refused as `grant_missing`
(a retry needs a new approval); the handler never reads model-supplied `owner`/`repo` (the SDK `tool` stub is a passthrough in this file, so assert the handler's calls to `pushBranch`, and assert the schema passed to `tool()` has exactly the keys `branch` and `force`); and
legacy parity: `buildGithubTools` with `enforcing: false` and no grant still pushes `HEAD` as before.
1.3 `test/approval/cc-push-gate-flow.test.ts` (new): real `createCanUseTool` with `platformToolNames` containing the
push FQN, cc-shaped deps (`approvalFailClosed: true`) and a hand-built `ApprovalGateDeps` over the shared fixtures,
plus the real builder with `pushBranch` mocked. Only what is new for cc is asserted (the gate's own texts for expired,
consume-rejected and aborted verdicts are covered by `gate-flow*.test.ts` and are not repeated). Cases (acceptance 2,
3, 5): approved => allow, grant written with `headSha`, handler pushes exactly `<sha>:refs/heads/<branch>`; owner
denies => deny text equals `APPROVAL_REJECTED_DENY`; wait ends undecided => `APPROVAL_PENDING_DENY`; each of those deny messages contains no tool input (flag-off and unreadable-flag denies for this tool are already looped over every required tool in `cc-approval-fail-closed.test.ts`, which is cited, not repeated); the
`approval_request` frame is sent through the injected `sendToClient` and `onRequested` runs (existing durable surface,
no new card), including a non-Owner requester (`viewerRole` member: the read-only card is the one sent); the handler
invoked directly after a deny finds no grant and refuses. (HEAD moved after approval is covered at the handler in 1.2 and
by `push-branch-pinned`; zod-default hashing by `canonical.test.ts`.)
1.4 `test/approval/cc-allow-source-pin.test.ts` (new, about 40 lines): Guard 2 text scanner with the canary and
must-PASS fixtures and the file-count floor; imports `APPROVAL_REQUIRED_TOOLS`.
1.5 `test/approval/tools-census.test.ts` (edit): allowed-set aware sweep (Guard 1); the allowlist describe becomes: every
required short name except the grant-wired one throws (including mixed lists in both orders, and the denylist names);
the grant-wired name does not throw and `readCcMcpAllowlist` still returns `{}`; the sweep self-test gains the
"second required tool alongside the push tool" row; non-vacuity floor includes the push tool when built.
1.6 `test/approval/runner-census.test.ts` (edit): the cc test now pins exactly one `new ExecutionGrants()`, the same
identifier passed to `createApprovalGateDeps` AND to the registrar call (`grants: approvalGrants`), no other slice-1
literal registered, builders census unchanged (cc imports `./cc-github-push`, not `github-tools`), no non-test module under `server/` other than
`github-tools.ts` and `cc-github-push.ts` imports `buildGithubPushBranchTool` (importer set derived with `git grep -l`, not a
name list), and `const activeWorkspaceId =` appears exactly once in the comment-stripped dispatcher source (a `let`
re-declaration or reassignment is a `tsc` error; the pin has a mutant that changes it to `let` and must go red).
1.7 `test/approval/builder-grants-required.test.ts` (edit, CTO Fork 7): per-builder interface pairing, inverse check, plus an assertion that the push options interface declares a non-optional `requireGrant: boolean`,
`BUILDERS_FLOOR` stays 3 and the arrayContaining list gains `buildGithubPushBranchTool`; failure strings unchanged.
1.8 `test/cc-dispatcher-real-factory.test.ts` (edit): new describe "github_push_branch registration". Extra mocks this needs, listed so they are not discovered late: `@/server/push-branch` (`pushBranch` spy), a `createApprovalGateDeps` wrapper that forwards to the real function but injects a `headSha` seam (the real `gitHeadSha` would run git in the fixture's nonexistent workspace), `@/server/github-api` via `importOriginal` (the file-wide `github-app` mock exposes only three exports and `GitHubApiError`/`githubApiGet` must survive). Also re-run `cc-dispatcher-prefill-guard`, `cc-dispatcher-warm-presandbox-mkdir` and `cc-effective-installation` (they partially mock `github-app`). Mocks
`@/server/approval/flag` (`isApprovalQueueEnabled`) with a per-test switch and `@/server/github-api` default-branch
lookup. Cases: flag off/throws => `soleur_platform` tool names, the `createCanUseTool` `platformToolNames` and the system prompt
equal LITERAL expected values (the narration tools, and the exact prompt tail without the addendum; `vi.mock` is hoisted
file-wide, so a "baseline captured without the mock" would compare the new code with itself), and the grants and gate
deps are unchanged; flag on + entitled + repo + installation => tool present once, FQN in
`platformToolNames`, addendum present, `registeredPlatformToolNames` Map entry published; the object passed as
`grants` to `createApprovalGateDeps` IS the object the push handler checks (identity, spy on `createApprovalGateDeps`
and on `checkGrant`); **workspace-capture equality (brief ruling 1)**: capture the `createApprovalGateDeps` args
(`workspaceId`, `repoSlug`, `workspacePath`) and the push builder args (`owner`, `repo`, `workspacePath`), assert
`repoSlug === owner/repo`, `workspacePath` equal, `workspaceId` equals the id given to `fetchUserWorkspacePath` and
`readCurrentRepoUrlResult`; then flip `mockResolveActiveWorkspace` to another id after construction and assert the
handler still pushes with the closed-over values and `resolveServerDerived` still binds the original (a mid-Query switch
cannot split gate from handler); persona `support` with every else true => not registered; `webEgressEntitled` true
with `webEgress` undefined (forwarder degraded) => registered; a factory throw after registration drains the Map entry.
1.9 `test/build-allowed-tools-census.test.ts` (edit, decided from the grep): add the push FQN to the cc names list that is checked against `TOOL_TIER_MAP` and `EXPECTED_TOOL_TIERS`. `test/cc-mcp-tier-allowlist.test.ts` needs no edit (it asserts the base set excludes the c4 FQN; the same holds for push, add one assertion line).
1.10 `test/approval/cc-push-boundaries.test.ts` (new, small): (a) the push FQN does not match the sandbox PreToolUse hook matcher in `agent-runner-query-options.ts` (a hook allow resolves ahead of `canUseTool`), and a synthetic name that does match is detected, so the test cannot pass vacuously; (b) two `realSdkQueryFactory` invocations never share a grants object; (c) conversation B cannot consume conversation A's approved row (assert at the `consume_approval` call: `p_conversation` is part of the request, faked service client returns not-consumed for a different conversation); (d) registered on the cold build, flag turned off later, the next gated call is refused (`APPROVAL_UNAVAILABLE_DENY`, no card) - the load-bearing re-check.

### Phase 2 - Implementation

2.1 `server/github-tools.ts`: extract `buildGithubPushBranchTool(opts: BuildGithubPushBranchToolOpts)` returning the
single `tool(...)` with the existing handler body moved verbatim (keeps the Guard 1 mutation anchors unique), plus the
strict branch, added as a SEPARATE statement right after the untouched line
`if (grant.kind === "refuse") return grantRefusalResponse("grant_missing");` (mutant G1-X7 anchors that exact line, so it must stay byte-identical):
`if (grant.kind === "legacy" && requireGrant) { reportGrantRefused(toolName, "grant_missing"); return grantRefusalResponse("grant_missing"); }`.
Interface `BuildGithubPushBranchToolOpts` (installationId, owner, repo, defaultBranch, workspacePath, `readonly grants: ExecutionGrants;`, `requireGrant: boolean`) declared AFTER `BuildGithubToolsOpts`
(which keeps its own `grants: ExecutionGrants;` line). `buildGithubTools` calls the new builder with
`requireGrant: false`, so its tool list and behaviour are unchanged. Export `GITHUB_PUSH_BRANCH_TOOL_FQN`.
2.2 `server/cc-github-push.ts` (new): `CC_GRANT_WIRED_APPROVAL_TOOLS = [GITHUB_PUSH_BRANCH_TOOL_FQN] as const`;
`resolveCcGithubPushRegistration(args)` with injectable `isEnabled`, `lookupDefaultBranch`, builder; order of checks
cheapest first and the flag last: persona, owner/repo/installation, entitlement, flag, then the lookup. Returns
`{ registered, reason, tools, toolNames }`; `reason` in `registered | support-persona | no-repo-or-installation |
not-entitled | flag-off | flag-error | default-branch-unresolved`. The flag read is bounded (a 2 s `Promise.race`; a never-settling seam cannot hang the Query) and goes through `isApprovalQueueEnabled({userId, workspaceId})`
(the same function and identity as the gate), wrapped in try/catch + `reportSilentFallback` (op `cc-push-flag-resolve`, defensive: the real seam never throws);
any throw, `false`, or non-`true` value is not registered. Lookup: `githubApiGet(installationId, "/repos/o/r", {signal})`
with the 3 s `RESOLVE_TIMEOUT_MS` and a safe-name check; failure => `reportSilentFallback` op `cc-push-default-branch-resolve`
and not registered. One `infoSilentFallback` outcome event (feature `cc-push-registration`, tag `reason`) and one stdout pino line with the discriminating fields (the shipper drops info, so Sentry carries the signal). `grants` and
`workspaceId` are REQUIRED arguments (compile error if forgotten). The registrar loads `github-tools` with a lazy `await import("./github-tools")` only after every gate passed (keeps the heavy github graph out of every other cc-dispatcher test that partially mocks `github-app`, and out of the dark path). Prompt addendum constant `CC_PUSH_PROMPT_ADDENDUM`
(CTO Fork 3 wording).
2.3 `server/cc-dispatcher.ts`: (a) hoist `approvalGrants` and `connectedRepoSlug` above `const c4McpServers`
(the later declarations are deleted, comments updated; the grants comment keeps the per-Query lifetime text);
(b) call the registrar inside the existing `effectiveInstallationId !== null && owner && repo` block, after the c4
resolve, passing `grants: approvalGrants`, `workspacePath`, `workspaceId: activeWorkspaceId`, `webEgressEntitled`,
`persona`; (c) `soleurPlatformToolsForTests({... approvalTools})` gains an optional `approvalTools` list placed after
`c4Tools` (absent => identical output); (d) `platformToolNames` for `createCanUseTool` appends the registrar's
`toolNames` only; (e) append `CC_PUSH_PROMPT_ADDENDUM` to `effectiveSystemPrompt` only when registered, next to the c4
addendum; (f) publish the registered FQNs on EVERY cold build (an empty set deletes the key, so a stale entry from an unclean earlier build cannot survive a rebuild) to a new module Map `_ccRegisteredApprovalTools` keyed by
`makeAckPostureKey`, only after the registrar succeeded, drained at the three `_ccAutonomousAckPosture` drain sites
(close hook, factory-throw catch, test reset) and consulted by the `onToolUse` mirror predicate as a third source;
(g) `readCcMcpAllowlist`: the approval-required check skips names in `CC_GRANT_WIRED_APPROVAL_TOOLS`; comment and the
function doc updated (the denylist check stays first); the throw text "no cc tool builder is wired to execution grants" is
reworded to "this tool has no grant-wired cc builder" because it is no longer true for every approval-required name.
(h) the per-conversation Map entry is deleted at the START of every cold build and set only after the registrar returns.
2.4 `approval-guard1-mutation.test.sh`: run `--check-anchors` AFTER the 2.1 rewrite (not only at baseline; X7, ST4, ST7, PG1-PG3 all anchor in `github-tools.ts`); add three mutant rows (strict branch removed; strict report removed; `requireGrant` made optional) and run them with `--only`; update the per-file mutant count table only if the harness requires it.

### Phase 3 - Docs, ADR, C4

3.1 ADR-309 addendum and flip-checklist item 8 (content list under "Architecture Decision"), mirrored into the archived
handover copy. Run `bash scripts/markdown-lint.sh --repo-sweep` before committing.
3.2 C4: extend the `engine -> approvalStore` edge description by one clause (Concierge now reaches the gate and
registers the push tool, still dark), then the three C4 checks named above.

### Phase 4 - Verify and probe

4.1 Re-run all Phase 0/1 files green, plus every test that exercises the factory (`git grep -l "realSdkQueryFactory" -- apps/web-platform/test`; a new cold-start import broke a sibling suite that targeted runs missed, learning 2026-06-03), and sweep by claim subject for statements the registration falsifies (`git grep -n "cc-dispatcher\|no approval wiring\|registers no" -- apps/web-platform/test apps/web-platform/server`; learning 2026-11-05 on census blind spots such as `deps: ccDeps`); `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and the repo lint scripts that CI runs for
`apps/web-platform` (use `package.json` scripts; do not invent flags).
4.2 Real-SDK approval-gate probe (ADR-309 §"Adding a gated tool" item 6): `NODE_ENV=test doppler run -p soleur -c ci --
bun run apps/web-platform/scripts/dev-probe-approval-gate.ts` (ci config only, never prd; reads no GitHub, Supabase or
Resend credential; stubs inert). Record the `RESULT:` line and `PROVENANCE` in the ADR addendum. A `CANT-RUN` (for
example no key) is recorded as such, never as a pass. The probe's `REGISTRATION` line for `github_push_branch` keeps
printing `cc=no` (it calls `soleurPlatformToolsForTests` without `approvalTools`; registration is conditional) - state
that in the addendum; the probe's own static checker is a #11534 deferred item whose trigger (this re-run) fired.
4.3 Guard 1 table in `plugins/soleur/test/real-sdk-ask-probe-workflow.test.sh`: the plan adds NO import to
`permission-callback.ts`, so no row is added. Verify with `git diff --name-only origin/main...HEAD` against the
workflow's `on.push.paths`; if any covered file changed (for example `permission-callback.ts` gains an import during
work), add its table row and run `timeout 580 bash plugins/soleur/test/real-sdk-ask-probe-workflow.test.sh`.
4.4 Before push: `git diff origin/main...HEAD -U0 | grep '^+' | grep -E '\b112[0-9]{2}\b' | grep -v 11258` must print
nothing.

## Files to Edit

- `apps/web-platform/server/github-tools.ts` - extract `buildGithubPushBranchTool`, `requireGrant`, FQN export.
- `apps/web-platform/server/cc-dispatcher.ts` - hoist grants, registrar wiring, `soleurPlatformToolsForTests`, `platformToolNames`, addendum, Map, `readCcMcpAllowlist`.
- `apps/web-platform/test/approval/tools-census.test.ts`
- `apps/web-platform/test/approval/runner-census.test.ts`
- `apps/web-platform/test/approval/builder-grants-required.test.ts`
- `apps/web-platform/test/approval-guard1-mutation.test.sh` (anchors verified; two new rows)
- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`
- `apps/web-platform/test/github-tools-push-grant.test.ts`
- `apps/web-platform/test/build-allowed-tools-census.test.ts` (push FQN joins the cc names checked against the tier table)
- `apps/web-platform/test/cc-mcp-tier-allowlist.test.ts` (one assertion line: the base set excludes the push FQN)
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (one edge description)
- `knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md` (mirror checklist item 8)

## Files to Create

- `apps/web-platform/server/cc-github-push.ts`
- `apps/web-platform/test/cc-github-push.test.ts`
- `apps/web-platform/test/approval/cc-push-gate-flow.test.ts`
- `apps/web-platform/test/approval/cc-allow-source-pin.test.ts`
- `apps/web-platform/test/approval/cc-push-boundaries.test.ts`
- `knowledge-base/project/specs/feat-one-shot-11636-cc-github-push-branch/decision-challenges.md` (exists)
- `knowledge-base/project/specs/feat-one-shot-11636-cc-github-push-branch/tasks.md`

Not touched, by instruction: `server/dsar-export-allowlist.ts`, `docs/legal`, `plugins/soleur/docs`, `scripts/`, `.github/`,
`web-egress-toggle.tsx`, any migration, any flag or environment, `server/approval/*` (so the "next PR touching
`server/approval/*`" trigger of #11534 is not fired by an edit; tests under `test/approval/` are edited and the item
stays deferred regardless).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Register `github_push_branch` in the cc platform server." [brief] | Phase 2.1-2.3 | mapped |
| 2 | "pushes through the existing `server/push-branch.ts`, so no credential enters the sandbox" [brief] | Phase 2.1 (unchanged `pushBranch`), Guard 3 | mapped |
| 3 | "Hoist the one per-Query `ExecutionGrants` ... to BEFORE the tool build, and hand that same object to the push builder and to the gate deps" [brief] | Phase 2.3(a)(b), runner census, identity test | mapped |
| 4 | "Register only when ALL hold at Query construction: ..." [brief] | Phase 2.2, test 1.1 | mapped |
| 5 | "A flag-resolve error means NOT registered (fail closed ...)" [brief] | Phase 2.2, test 1.1 | mapped |
| 6 | "Flag off or unreadable: cc tool set and `registeredPlatformToolNames` byte-identical to before." [brief] | tests 1.8, Map design | mapped |
| 7 | "Relax the `readCcMcpAllowlist` throw for this one name only" [brief] | Phase 2.3(g), test 1.5 | mapped |
| 8 | "update the census and sweep tests ... to expect exactly this registration" [brief] | tests 1.5, 1.6, 1.7 | mapped |
| 9 | "Run the census tests FIRST" [brief] | Phase 0.2 | mapped |
| 10 | "Add a dated ADR-309 addendum and re-run the real-SDK ask probe" [brief] | Phase 3.1, 4.2, 4.3 | mapped |
| 11 | "Do NOT create or flip any flag or environment; do NOT change toggle copy, privacy copy or legal text; no migration." [brief] | Not-touched list, flip preconditions | mapped |
| 12 | "PR must carry a test that the gate's workspaceId, repoSlug and workspacePath equal the tool closure's values." [brief ruling 1] | test 1.8 | mapped |
| 13 | "The tool result must surface the gate's static wait/deny text" [brief ruling 2] | test 1.3 | mapped |
| 14 | "the PR either adds a pin/test or restates it as accepted with reason" [brief ruling 3] | Guard 2, test 1.4 | mapped |
| 15 | "record in the PR body that the trigger fired and the item stays deferred" [brief ruling 4] | Ship notes | mapped |
| 16 | "Deliver as ONE PR." [brief] | Split Assessment | mapped |
| 17 | "use `Ref #11636` and `Ref #11635` ONLY" [brief] | Ship notes | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `server/cc-github-push.ts` module | "Register only when ALL hold at Query construction" | asked (rows 4-5; module form ruled by CTO Fork 7) |
| `requireGrant` strict handler | "tool never registered without gate and grants" / "Handler refuses when grants absent" | asked (acceptance 1 and 3; ruled Fork 6) |
| Per-conversation Map for the warm path | "cc tool set and `registeredPlatformToolNames` byte-identical to before" | asked (row 6; ruled Fork 2) |
| Prompt addendum | "so the user learns of a pending or denied push from the model" | asked (ruling 2; ruled Fork 3) |
| Guard 2 allow-source pin | "the PR either adds a pin/test or restates it as accepted with reason" | asked (ruling 3; ruled Fork 4) |
| Fail-closed default-branch lookup | "closes over owner, repo, installation id, workspace path and default branch" | asked (default branch is named; failure behaviour ruled Fork 1) |
| C4 edge description extension | "Add a dated ADR-309 addendum" | inferred - justification: an architecture decision's C4 edge must not lag it (plan Phase 2.10); one sentence, no new element |
| Flip-checklist item 8 + archived handover mirror | "do NOT change toggle copy, privacy copy or legal text" | inferred - justification: the CPO/CLO advisories make the copy drift a flip precondition; recording it in the ADR is the only compliant way to carry it without changing the copy or filing an issue |
| Three mutation-battery rows | "Handler refuses when grants absent or commit mismatched" | inferred - justification: the existing Guard 1 battery pins the push handler's mutants; the new strict branch must be pinned the same way |
| Builder-grants test pairing change | "update the census and sweep tests" | asked (row 8; forced by the second builder) |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform/server`, `apps/web-platform/test`, `knowledge-base`
- Planned files: 20 (14 to edit, 6 to create, plus the plan file; recounted after Phase 0 fixes the consumer list) | Estimated changed lines: about 900 (about 250 source, about 550 tests, about 100 docs)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (lines only just over the threshold, driven by tests; the brief orders one PR and the
  pieces are mutually dependent: a registered tool without the strict handler and the sweep is exactly the hazard)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 Flag off, unreadable (throw, timeout, undefined) or any precondition false: the tool set is byte-identical (cost: one extra flag read and its latency on each cold Query for an entitled, non-support persona with a repo and installation); the cc `soleur_platform` tool names, `createCanUseTool` `platformToolNames`, system prompt and the `registeredPlatformToolNames` consulted by the mirror are deep-equal to the pre-change values (test 1.8); the lookup is not called.
- [ ] AC2 Flag on and all preconditions true: the tool is registered once; a push goes through the gate; the gate writes a grant carrying `headSha`; the handler pushes exactly `<sha>:refs/heads/<branch>` even if HEAD moved (test 1.3).
- [ ] AC3 The handler refuses when grants are absent (including `enforcing: false` with `requireGrant: true`) or the commit is missing or unavailable, and reports `approval-grant-refused` (tests 1.2, 1.3). The registrar cannot be called without `grants` (type) and the same object reaches the gate and the builder (tests 1.6, 1.8).
- [ ] AC4 The derived sweeps expect exactly this tool: the sweep returns `required == [push FQN]` when the registrar's tools are included and `[]` otherwise; any other required name, mixed env lists and denylist names still throw (test 1.5).
- [ ] AC5 Deny path and user-visible text: pending, rejected, expired, unavailable and aborted verdicts return the static texts, contain no tool input, and the durable surfaces (frame, row, notify) are exercised; the addendum test pins the no-success-claim wording (tests 1.3, 1.8).
- [ ] AC6 Workspace capture: gate `workspaceId`, `repoSlug`, `workspacePath` equal the tool closure's values; a mid-Query workspace switch does not split them; `activeWorkspaceId` is never reassigned (tests 1.6, 1.8).
- [ ] AC7 Allow-source pin green with canary and floor (test 1.4); ADR addendum states what it does not see.
- [ ] AC8 `builder-grants-required` and `approval-guard1-mutation.test.sh --check-anchors` green; three new mutant rows landed and killed (strict branch removed, strict report removed, `requireGrant` made optional).
- [ ] AC9 ADR-309 addendum dated 2026-11-05 with workspace capture marked **verified** with the evidence, probe result line, #11534 trigger statement, and flip-checklist item 8 (also in the archived handover copy); `bash scripts/markdown-lint.sh --repo-sweep` clean; C4 checks green after the one edge-description edit.
- [ ] AC10 Real-SDK approval-gate probe re-run and its `RESULT:` line recorded (a CANT-RUN is recorded as CANT-RUN).
- [ ] AC11 No file outside the lists above, the plan file and the files under `knowledge-base/project/specs/feat-one-shot-11636-cc-github-push-branch/`; no flag, environment, migration, toggle or legal text change; `closingIssuesReferences` is `[]`; the guarded grep from Phase 4.4 prints nothing.

### Post-merge (operator)

None. The flag flip, toggle-copy rewording, compliance-posture addendum and PA-38 check are operator holds recorded as flip preconditions; this PR does not schedule or perform them.

## Test Scenarios

1. Dark path: flag off => identical tool set and prompt; handler never built.
2. Happy path: Owner approves => push of the approved commit; card status `consumed`.
3. Owner denies => model receives `APPROVAL_REJECTED_DENY`; nothing pushed; re-asking is told not to retry.
4. Owner away => wait ends => `APPROVAL_PENDING_DENY`; the saved request is findable in the inbox; a byte-identical re-ask after approval consumes the live row and allows with a grant.
5. HEAD moves during the wait => the approved sha is pushed, not the new HEAD.
6. Another allow source hands the call to the handler => no grant => refused and reported.
7. `support` persona, no egress grant, no repo, no installation => not registered.
8. Default-branch lookup fails => not registered, Sentry event, never "main" fallback.
9. Warm turn: registered push call does not trip the unregistered-tool mirror; a cold build that threw leaves no Map entry.
10. `CC_MCP_ALLOWLIST=github_push_branch` => `{}`; `CC_MCP_ALLOWLIST=github_push_branch,email_send` => throws.

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6; this one is filled and `requires_cpo_signoff: true` is set.
- The guard-1 mutation anchors are exact-count textual anchors: keep `grants: ExecutionGrants;` (two-space indent) unique in `github-tools.ts` by spelling the new interface member `readonly grants: ExecutionGrants;`, and move (do not copy) the handler lines the PG1-PG3 mutants anchor on.
- `soleurPlatformToolsForTests` is imported by the approval-gate probe with a fixed argument shape; the new `approvalTools` parameter must stay optional.
- The cc-dispatcher import is slow (~13 s cold) in vitest; the registrar is deliberately importable alone so the matrix test is fast.
- The default branch is fixed at cold build (documented staleness window for a rename mid-session; cap by `rejectProtectedBranch` also blocking `main`/`master`).
- The prompt addendum is the only channel that tells the user about a held push; it is advisory to the model, so the ADR states there is no automated detector for model prose.
- Known residuals, all pre-existing in the legacy runner and recorded in the ADR addendum rather than fixed here
  (fixing them touches `server/approval/*`, whose #11534 trigger stays deferred): (a) the gate approves before the
  handler's protected-branch check, so an approval for a push to `main`, `master` or the default branch is consumed and
  the handler then refuses (the zod description and the deny text already tell the model not to target them); (b) a
  re-ask after HEAD moved is a new action (the hash binds `headSha`) and creates a second card, the first approval
  expiring unused; (c) a push that fails after the grant was taken needs a new approval; (d) the tool result does not
  state the pushed sha (changing the compact JSON would change the legacy output pinned by
  `github-tools-untrusted.test.ts`); (e) caps (5 pending per conversation, 20 per workspace) end in
  `APPROVAL_TOO_MANY_PENDING_DENY`, which the gate tests already cover.
- The one open observation (requester-visible outcome after the chat ends) rides the existing inbox/notification path and is not widened here.

## Ship Notes (for `soleur:ship`)

- Title `fix(approval): register github_push_branch in the cc platform server behind the approval gate (Ref #11636)`. Do not use `feat(`.
- Body: `Ref #11636`, `Ref #11635`, epic `Ref #9601` only; no `Closes`/`Fixes`/`Resolves`; confirm `closingIssuesReferences = []` after creation. Do not edit the epic body. File no issues; #11640 is the open decision-challenge issue.
- Body states: nothing changes for users until the operator flips `approval-queue`; the flip preconditions (toggle copy first, CLO check, dogfood on the Owner workspace, then wider); the #11534 triggers that fired (probe re-run: fired, item stays deferred; "next PR touching `server/approval/*`": not fired by an edit, item stays deferred); the probe `RESULT:` line.
- Avoid the words "soak", "stays 0", "stays zero" and "post-deploy verify" in the body (the sweepers key on them); no operator checklist in the ship message (`hr-ship-message-no-operator-checklist`).
- `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` on every commit.
