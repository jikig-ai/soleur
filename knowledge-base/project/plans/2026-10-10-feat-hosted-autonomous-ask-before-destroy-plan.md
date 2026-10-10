---
title: "feat(hosted): ask before default-branch force-push and terraform destroy in autonomous mode"
date: 2026-10-10
slug: feat-hosted-autonomous-ask-before-destroy
branch: feat-9776-hosted-autonomous-ask
issue: 9776
type: feat
lane: cross-domain
priority: p1-high
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
labels: [compliance/critical]
---

# feat(hosted): ask before default-branch force-push and terraform destroy in autonomous mode

Issue #9776, epic #9601. Binding rulings are on disk beside this plan in
`knowledge-base/project/specs/feat-9776-hosted-autonomous-ask/`: `cto-ruling.md`, `cpo-signoff.md`, `clo-ruling.md`.
This plan implements them; it does not re-open them.

## Overview

A hosted session whose workspace has `bash_autonomous = true` auto-approves every Bash command that survives
`BLOCKED_BASH_PATTERNS`. That includes a force-push over (or deletion of) the connected repository's default branch and
`terraform|tofu destroy`. The plugin guard that would ask is switched off in hosted sessions (ADR-277 D8).

The ruled design (CTO, option C): one **must-ask lane** inside the hosted `canUseTool`, backed by a pure TypeScript
classifier, placed above the autonomous bypass, the disclosure hold and the batched-approval cache. A match is sent to the
existing review-gate with exactly two options (Approve, Reject). The plugin hook stays off in hosted sessions; turning it on
is recorded as a later consolidation. The consent copy stops saying the exposure is unchecked and gains one hedged
assurance; the legal text is deliberately not touched (CLO). No migration, no acknowledgement reset, no Terms
re-acceptance, no feature flag.

## Research Reconciliation — Spec vs. Codebase

| Claim in the brief or issue | Reality (verified on `origin/main` 8e69bd5f4b) | Plan response |
|---|---|---|
| "a copy-versioned acknowledgement so no bulk reset or deploy-order window is needed again" (brief, recommended) | CLO Q2 (2026-10 audit) rules a narrowing needs no re-ack; this PR only narrows. CTO RULING 2: out of scope, separate PR, no issue now. | Not built. Smallest design and the widening trigger are recorded in ADR-284 (CPO4-R8). |
| "Route the AUP/Terms parenthetical to CLO; bump `TC_VERSION` only if the policy says so" (brief) | CLO ruling 3: leave AUP 5.7, T&C 3a.7/10.4 and both mirrors untouched; deleting the parenthetical is Tier 2 and forces every user to re-accept Terms. Verbatim replacement text is drafted for the next bump. | No legal-doc edit, `TC_VERSION` stays 2.6.0. One tracking issue with a dated trigger is filed before merge (CLO C6). |
| "the addendum still lists CPO3-R2 as open (closed by #9792)" (brief) | CPO4-R7 says CPO3-R2 closes through the CLO-signed copy. #9792 added the exposure statement; this PR's copy supersedes it. | ADR-277 addendum records both: opened by the CPO third pass, satisfied by #9792, superseded by this PR's copy. |
| Issue size "380 lines / 6 files" | CTO estimate: about 250 lines classifier, 80 resolver, 60 wiring, about 700 lines of tests and corpus, about 14 files. | Sized below (wc -l of touched files measured at work time, per `wg` filing rules). |
| `gh repo delete` / `gh api` ref deletion treated as residuals (CTO) | Verified from code: the hosted agent gets `gh` plus an unscoped GitHub App installation token as `GH_TOKEN` (`cc-dispatcher.ts` `generateInstallationToken` called with no `permissions`; `agent-env.ts` injects `GH_TOKEN`); the App manifest grants `administration: write`; `api.github.com` is in `ENTITLED_EGRESS_DOMAINS`. | CPO4-R4 resolves to "reachable": `gh` ref-delete, forced ref update and repository delete become one more classifier family in THIS PR (rule ids below). CLO re-evaluation trigger noted. |
| Banner copy is LOCKED (2026-10-08) | Locked by the prior counsel review; the CLO ruling supplies replacement bytes. | Unlock, apply byte-for-byte, re-lock with updated tests. |

## Research Insights

**Premise validation (Phase 0.6).** #9776 is OPEN with no closing PR; #9792 and #9778 merged. Cited code exists on `origin/main`:
`BLOCKED_BASH_PATTERNS` and the `autonomous-bypass` branch in `permission-callback.ts`, `SOLEUR_DISABLE_DESTRUCTIVE_GUARD` in
`agent-env.ts`, migrations 099 and 159. ADR-corpus check: the mechanism "enable the plugin hook in hosted" is not a rejected
alternative anywhere; ADR-277 D8 and its open follow-up name it as deferred pending a measured hosted `ask` path. CTO grep also
found ADR-264 (#9388), which needs the same lane shape; the lane is built as a function list so it becomes the second consumer.

**Property list (Phase 0.6b).**
1. A hosted Bash command that force-pushes over, deletes or mirror-pushes a protected branch, or runs terraform/tofu destroy,
   is never executed without an explicit per-command Approve.
2. No earlier grant (autonomous bypass, first-run acknowledgement, batched "Approve all") can stand in for that Approve.
3. When the classifier cannot decide, it asks rather than allows.
4. Every ask is observable without reading the command text.
5. The in-product copy never promises more than the lane does.

**Cut list.** Feature flag (the change fails toward ask; a flag is a one-click way to reopen the exposure): cut. Versioned
acknowledgement and schema change: cut (CLO Q2). Enabling the plugin hook in hosted: cut (needs this lane anyway, adds unmeasured ask
classes). Per-command network call or `git` spawn for the default branch: cut (resolved once per session record). Owner-only
approval authz: cut (recorded residual).

**Learnings applied** (from `knowledge-base/project/learnings/`): `2026-03-20-canuse-tool-sandbox-defense-in-depth.md` (keep
`allow: []`, `settingSources: []`, so a bypass can never become an allow rule), `2026-03-20-canusertool-caching-verification.md`
(gate tests must exercise the API-key path or they pass vacuously: drives AC-14), `2026-05-16-adr-amendment-required-when-reversing-and-destroy-guard-empty-string-bypass.md`
(a destroy guard fed by a failed pipe passes silently: classifier exceptions ask), `2026-09-27-my-segmenter-split-on-characters-the-shell-reads-as-one-command.md`
(split at nesting depth 0 only), `2026-09-28-every-guard-was-narrower-than-its-name-and-my-battery-mutated-only-whole-chokepoints.md`
(mutate each narrowing predicate, assert each mutant landed), `2026-05-25-pr1-of-sequenced-legal-disclosures-needs-temporal-qualifiers.md`
(why the legal parenthetical gets a dated deadline), `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` (approving a card is not an acknowledgement).

**Repo map.** Bash branch order today (`permission-callback.ts`, `createCanUseTool`): empty-command deny, `isBashCommandBlocked`
deny, `isBashCommandSafe` allow, safe-bash near-miss telemetry, support-persona deny, `if (deps.bashAutonomous)` {first-run
hold, `autonomous-bypass` allow}, existing-workspace opt-out hold, `bashApprovalCache.allow`, review-gate.
`deriveBashCommandPrefix` (`permission-callback-bash-batch.ts`) maps any `git push ...` to the prefix `git push` and any
terraform command to `terraform`, so a prior "Approve all" grant already auto-approves `git push --force origin main` and
`terraform destroy` today, in non-autonomous mode too. `default_branch` is already fetched by `agent-runner.ts` through
`githubApiGet` for the push tool but is not threaded into `canUseTool`; `workspace-sync.ts` reads `refs/remotes/origin/HEAD`
locally. Review-gate round trip: `review_gate` frame, `abortableReviewGate`, `ReviewGateCard`, `review_gate_response`,
`resolveCcBashGate` in `cc-dispatcher.ts`; the gate times out after 5 minutes and denies.

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder's autonomous Concierge session force-pushes over their repository's
  default branch (erasing its history on GitHub) or tears down their infrastructure with no card ever shown; or, from the
  over-ask side, a Reject-only-looking card storm on routine pushes that teaches them to click Approve without reading.
- **If this leaks, the user's workflow is exposed via:** telemetry for each ask. Pino and Sentry carry rule id, family, repo
  owner/name (pino only), owner/ack state; a raw command, redacted preview, branch or refspec in a log or Sentry tag would expose
  credentials embedded in a command line (class of #8532). The preview exists only in the card and the unchanged offline-notify path.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one founder losing a default branch's history or a production stack, after the product
  said the work is backed up and dangerous commands are blocked, is a single-user incident (CPO third pass T12); `aggregate pattern`
  would require waiting for several.

`requires_cpo_signoff: true` is satisfied at plan time by `cpo-signoff.md` (APPROVED WITH CONDITIONS CPO4-R1..R8). Review time:
`soleur:engineering:review:user-impact-reviewer` and `security-sentinel` against the diff.

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-284** (ordinal provisional: CTO found 282 free at base; re-derive over `refs/remotes/origin/*` at ship time and sweep
  this plan, `tasks.md` and ACs for the old ordinal if renumbered; 278-280 are claimed by other branches) via
  `soleur:architecture create "Hosted Bash must-ask lane in canUseTool for destroy families"`. Content: lane precedence over
  bypass, hold and cache; fail-toward-ask; default-branch union rule; the superset-of-hook corpus binding; ADR-264/#9388 as the
  second consumer; a coverage table by conversation type (cc-routed, legacy runner, support, scheduled/Inngest); residual list
  (variable-built names, aliases including `git config alias.x '!git push -f'` and `git config remote.origin.push +HEAD:main` followed by a
  plain push, `make`/`npm run`/script indirection including Write then `bash ./x.sh`, terragrunt/pulumi, `git update-ref`, recursive `rm`,
  force-push to non-default branches, GraphQL `deleteRef`/`deleteRepository`/`updateRef`, non-owner approval); CPO4-R5 revert/tune thresholds; CPO4-R8 widening trigger
  for the versioned acknowledgement; the CLO parenthetical follow-up.
- **Amend ADR-277** (addendum, not supersede): D8 stands (hook off in hosted); replace "hosted Bash is not gated for these
  commands in the default mode" with a pointer to ADR-284; update the "Enabling the guard in hosted sessions" follow-up (recorded
  as the later consolidation, conditional on a measured hosted ask); mark CPO3-R2 per Research Reconciliation; keep CPO3-R1 open
  until post-merge verification passes (CPO4-R7); record the verify-migrations finding: `verify-migrations` is skipped on every
  `workflow_run` deploy where `migrate` succeeds, cause inferred from the job expressions and unconfirmed, tracked as #9825.
- **Amend ADR-093** one sentence (2026-10-07 amendment says hosted Bash is unguarded for these commands). Update the comment in
  `agent-env.ts` that points at D8.

### C4 views
Read all three model files before editing (completeness mandate). Elements and relationships checked: external human actor
(Workspace Owner / member approving a card: already modelled as the founder actor and the review-gate surface); external system
(GitHub API default-branch read: edge already present for the push tool; no new vendor); container/data store (none touched: zero
DB writes); actor-to-surface access (unchanged: members already approve any non-autonomous gate). Result: **no new element, no new
relationship.** Confirm the existing GitHub-API edge originates from a component that the permission path belongs to (if it comes only from
the push tool, one edge is new and is added), and check the principles register for an applicable AP entry. Edit the description text
wherever the hosted-posture claim appears in `model.c4`: the destructive-command-guard element ("HOSTED POSTURE DIFFERS ... not gated"),
the engine/hooks element (near line 110) and the plugin element (near line 164, "not hosted founders"); sweep all three, find them by
`git grep -n "hosted" -- knowledge-base/engineering/architecture/diagrams/model.c4` rather than by line number. Then regenerate `model.likec4.json` with `plugins/soleur/scripts/render-c4-model.sh`, and run
`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (no counts move;
the run is the evidence). `views.c4` and `spec.c4` are unchanged.

### Sequencing
Authored now, describing the shipped state; CPO3-R1 stays open until the post-merge measurement passes.

## Implementation Phases

Order follows `cq-write-failing-tests-before`: RED first.

### Phase 0 — RED (tests and corpus)
- `apps/web-platform/test/fixtures/destroy-ask-corpus.json`: rows `{cmd, expect: "ask"|"pass", rule, protected, hookAsks, note}`. A row per
  spelling in AC-1 and AC-2; the precision rows (CTO list); `hostedOnly` notes on `--mirror`, `git-push-unknown-default` and raw-scan rows.
- `test/destroy-ask-classifier.test.ts` (corpus plus unit), `test/permission-callback-destroy-ask.test.ts` (lane; sibling of
  `permission-callback-autonomous.test.ts`), `test/resolve-protected-branches.test.ts`, `test/destroy-ask-hook-parity.test.ts`
  (runs the real hook with the kill switch unset over every `hookAsks: true` row), and AC-14 in the style of
  `test/cc-dispatcher-bash-gate.test.ts`. Confirm each is RED for the right reason before Phase 1.

### Phase 1 — classifier (`apps/web-platform/server/destroy-ask-classifier.ts`, new)
Pure, no I/O: `classifyDestroyFamily(command, resolveProtected): Promise<DestroyMatch | null>`; `resolveProtected` is awaited only
after a force, delete or mirror push is found. Recognition per `cto-ruling.md` ("What the classifier must recognise"), plus the
CPO4-R4 `gh` family:

- `gh api` with method `DELETE` (spellings `-X DELETE`, `-XDELETE`, `--method DELETE`, `--method=DELETE`, case-insensitive) or `PATCH`/`PUT`
  with a force field, on `repos/<o>/<r>/git/refs/heads/<protected>` or a glob/variable path; `gh api -X DELETE repos/<o>/<r>` (repository
  delete); `gh repo delete`. Protected-branch comparison reuses the same union rule. Rule ids `hosted-destroy-ask:gh-ref-delete-default`
  and `hosted-destroy-ask:gh-repo-delete`.
- Keyword-only near-miss telemetry (no ask) for `gh` plus `delete`, and for `gh api graphql` / `--input` commands containing `deleteRef`,
  `updateRef`, `deleteRepository` (CPO4-R4). GraphQL mutations are a named residual in ADR-284 until the CPO widens scope (CPO4-R1); see
  "Decisions held for the operator" below.
- Implicit-destination force pushes (`git push -f`, `... origin HEAD`, `... .`, bare `--force-with-lease`) ask, with their own sub-rule id
  `hosted-destroy-ask:git-force-implicit` so the R5 tuning can isolate them (telemetry only; behaviour is as ruled).
- Unparseable command: ask iff the quote- and backslash-stripped, case-folded text contains `destroy` or `push` (the CTO rule; `gh`+`delete`
  stays near-miss only, CPO4-R1 scope lock). Any thrown error is a match plus `destroy-classifier-error`.
- `MUST_ASK_CLASSIFIERS` is a one-member function list (ADR-264/#9388 adds the second later); no further abstraction.

### Phase 2 — resolver, lane, wiring, telemetry
- `apps/web-platform/server/resolve-protected-branches.ts` (new, the only I/O): union of GitHub API `default_branch` (installation
  token, `authoritative = true`), local `refs/remotes/origin/HEAD` (agent-writable: adds names only), and `main`/`master`. 3 s
  timeout; positive result memoised per session record with a 10-minute TTL (a default-branch rename must not stay stale for a whole
  session), negative result cached 30 s. The local read is hardened: `lstat` and refuse symlinks and non-regular files, cap the size, and
  accept only `^ref: refs/remotes/origin/<safe-charset>$`. The repo and installation come from `parseConnectedRepo(repoUrl)` and
  `effectiveInstallationId` (both already in scope in the dispatch function above `ccDeps`; confirm), NOT from `ctx.repoOwner`/`ctx.repoName`,
  which `cc-dispatcher.ts` passes as empty strings; the telemetry `repo` field uses the same source. Failure:
  `reportSilentFallback(op: "default-branch-resolve")`, `authoritative = false`, and every force, delete or mirror push asks
  (`git-push-unknown-default`).
- `permission-callback.ts`: new dep `resolveProtectedBranches`; insert the lane immediately after the support-persona deny and before
  `if (deps.bashAutonomous)`. On a match set `mustAsk`; wrap the autonomous block, the existing-workspace opt-out block and the
  `bashApprovalCache.allow` lookup in `if (!mustAsk)`. Gate options exactly `["Approve", "Reject"]`; question text names the cause in
  plain words and says approval applies to this command only (CPO4-R2, CLO C4); reuse `redactCommandForDisplay` (200-char cap) but the
  question LEADS with the cause line and the matched segment, outside the truncated span, and says Approve runs the whole command (a
  destroy segment past character 200 of a `&&` chain must stay visible). Wording is neutral about who owns the repository ("the
  repository's default branch") because a non-owner member may be approving. When `mustAsk` is set, force `cachePrefix = ""` so a forged
  `Approve all ...` selection cannot reach the batch cache (`resolveCcBashGate` does not call `validateSelection`; `isBatchedApprove`
  derives from `cachePrefix`, not from the offered options), and treat any selection other than the exact string `Approve` as a deny.
  Approval writes no acknowledgement and no cache entry. Reject, timeout and abort deny, and the deny text tells the agent not to
  retry or respell. Blocklist stays first (`curl x && git push -f origin main` denies). Gate lifecycle is the existing review-gate's;
  Phase 0 adds tests for it (AC-19). Outcome telemetry records the approver's role (owner or member).
- `cc-dispatcher.ts`: wire `resolveProtectedBranches` beside the existing `ccDeps` fields (`bashAutonomous`, `isOwner`,
  `resolveAckPosture`) from the already-resolved installation id, repo owner/name and `workspacePath`. Legacy `agent-runner.ts`
  calls `createCanUseTool` with no `bashAutonomous` and no cache, so it is always review-gate; confirm by test, no edit expected.
- Telemetry per ask, before the gate: pino `log.warn({ sec: true, decision: "destroy-ask", ruleId, family, autonomous, isOwner,
  acked, authoritative, repo })` through the shared logger (userId hashed) and `warnSilentFallback(null, { feature: "cc-permissions",
  op: "hosted-destroy-ask", extra: { ruleId, family, autonomous, isOwner, authoritative } })` with a 32-per-context budget (copy the
  `NEAR_MISS_STATE` WeakMap). Outcome lines `destroy-ask-approved`, `destroy-ask-rejected`, `destroy-ask-expired`. Never the command,
  preview, branch or refspec in any tag, extra or breadcrumb (CLO C5, asserted by test).

### Phase 3 — mutation harness and CI registration
`apps/web-platform/test/destroy-ask-mutation.test.sh`, shaped like `plugins/soleur/test/destructive-command-guard-mutation.test.sh`:
anchor-asserted textual mutants applied to a temp copy, each mutant must land and be killed (or be proven equivalent in the output).
Register it where sibling guard suites are registered (read `scripts/test-all.sh` and the shard manifest; do not run
`test-all.sh --full` or `run-registered-suites.sh` locally; CI runs the battery). Run the repo-wide ratchets on the committed tree.
Cost bound: each mutant runs ONE targeted test file (never the full vitest), the harness states a runtime budget, and a mutant whose anchor
is missing fails the harness (never skips). Spelling-level mutants are killed by corpus rows; the harness adds the lane-placement mutants,
the forged-selection mutant, and the exemption rows. Tool precondition: the hook-parity test and any hook-driven row need `bash`, `perl` and
`jq`; confirm they exist on the CI shard that runs `apps/web-platform` tests and make a missing tool a hard failure, not a skip.

### Phase 4 — copy (CLO bytes, same build)
Apply `clo-ruling.md` sections 1 and 2 byte-for-byte to `AUTONOMOUS_DISCLOSURE_COPY` (banner) and the confirm paragraph in
`bash-autonomous-toggle.tsx`; update the LOCKED-copy tests (`autonomous-disclosure-banner.test.tsx`, `bash-autonomous-toggle.test.tsx`,
`auto-run-chip.test.tsx` if it asserts the copy) with the same bytes; the tests must not assert absence of "without asking" or
"terraform destroy" (the new copy contains both legitimately); add the vocabulary guard test (CLO C3: no "blocks", "prevents",
"protects", "safe to approve", "guaranteed", "always" referring to the lane in banner, toggle or card). `ReviewGateCard` is not edited:
the card text is the server-built question string. If the work phase finds the card needs a component change, STOP: the wireframe
gate (`wg-ui-feature-requires-pen-wireframe`) then applies.
Create `knowledge-base/legal/audits/2026-10-counsel-review-9776-ask-gate.md` (CLO ruling section 6 spec) and add the conditional
supersede marker under the "Until a stricter check ships" row of `2026-10-counsel-review-9776.md`.

### Phase 5 — ADR and C4
ADR-284 create, ADR-277 and ADR-093 addenda, `agent-env.ts` comment, `model.c4` description plus regenerated `model.likec4.json`.
ADRs and C4 text must not say the hosted gate is complete (CLO C8).

### Phase 6 — post-deploy soak enrollment (CPO4-R5, R7; plan Phase 2.9.1)
The 24 h revert thresholds and the 7-day measurement are time-gated close criteria for CPO3-R1 and for #9603. Deliverable:
`scripts/followthroughs/hosted-destroy-ask-window-9776.sh`, notify-only like `image-cve-scan-window-9826.sh` (exit codes 2, 3 or 5,
never 0 or 1, never closes anything): queries Better Stack through `scripts/betterstack-query.sh` for per-rule `destroy-ask` counts and
outcomes, prints the R5 percentages, and exits 3 when a revert or tune threshold is tripped. Tracker is #9776 itself with the
`<!-- soleur:followthrough ... -->` directive and the `follow-through` label; wire any new `secrets=` into
`.github/workflows/scheduled-followthrough-sweeper.yml`. Read `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` first.
The probe takes a `--window 24h|7d` argument and is enrolled twice (earliest deploy + 1 d and deploy + 7 d), because the 24 h revert rule
cannot be evaluated by a 7-day directive. The 25 percent rule carries a minimum-call floor (at least 20 hosted Bash calls from that
workspace in the window) so 1 call in 4 is not a storm; the floor is recorded in ADR-284 with the thresholds.

## Files to Create
- `apps/web-platform/server/destroy-ask-classifier.ts`
- `apps/web-platform/server/resolve-protected-branches.ts`
- `apps/web-platform/test/fixtures/destroy-ask-corpus.json`
- `apps/web-platform/test/destroy-ask-classifier.test.ts`
- `apps/web-platform/test/permission-callback-destroy-ask.test.ts`
- `apps/web-platform/test/destroy-ask-hook-parity.test.ts`
- `apps/web-platform/test/resolve-protected-branches.test.ts`
- `apps/web-platform/test/destroy-ask-mutation.test.sh`
- `scripts/followthroughs/hosted-destroy-ask-window-9776.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md` (ordinal provisional)
- `knowledge-base/legal/audits/2026-10-counsel-review-9776-ask-gate.md`

## Files to Edit
- `apps/web-platform/server/permission-callback.ts`
- `apps/web-platform/server/cc-dispatcher.ts` (wiring only; see Open Code-Review Overlap)
- `apps/web-platform/server/agent-env.ts` (comment only; no override change)
- `apps/web-platform/components/chat/autonomous-disclosure-banner.tsx` (copy constant only)
- `apps/web-platform/components/settings/bash-autonomous-toggle.tsx` (copy paragraph only)
- `apps/web-platform/test/components/chat/autonomous-disclosure-banner.test.tsx`, `test/components/settings/bash-autonomous-toggle.test.tsx`, `test/components/chat/auto-run-chip.test.tsx` (if it asserts the copy)
- `apps/web-platform/test/cc-dispatcher-bash-gate.test.ts` (AC-14)
- `knowledge-base/engineering/architecture/decisions/ADR-277-plugin-destructive-command-guard.md`, `ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` and the regenerated `model.likec4.json`
- `knowledge-base/legal/audits/2026-10-counsel-review-9776.md` (conditional supersede marker only)
- Test-battery registration file(s) found in Phase 3 (`scripts/test-all.sh` and the shard manifest, if that is where guard suites register)

Globs verified before use: every path above that already exists was listed from the worktree in this session (`ls`/`grep`); new paths sit
beside siblings of the same shape (`permission-callback-autonomous.test.ts`, `image-cve-scan-window-9826.sh`).

## Open Code-Review Overlap

Two open code-review issues name `apps/web-platform/server/cc-dispatcher.ts`: #3243 (decompose cc-dispatcher into focused modules) and
#3242 (tool_use WS event lacks a raw name field). **Acknowledge** both: this PR adds one dep wiring beside existing fields and does not
touch the decomposition or the tool_use event; folding either in would enlarge a single-user-incident PR. No other planned file matches.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "hosted autonomous mode must ASK before default-branch force-push/delete and terraform\|tofu destroy" | Phases 1-2, AC-1..AC-9 | mapped |
| 2 | "Route the design fork (extend the hosted gate in apps/web-platform/server/permission-callback.ts vs enable the plugin hook in hosted sessions) to soleur:engineering:cto for a binding ruling" | `cto-ruling.md`, Architecture Decision | mapped |
| 3 | "a copy-versioned acknowledgement so no bulk reset or deploy-order window is needed again" | Research Reconciliation row 1, Non-Goals | descoped — justification: CTO RULING 2 and CLO Q2 (narrowing needs no re-ack); trigger recorded in ADR-284 |
| 4 | "Revise banner/toggle copy in the same PR" | Phase 4, AC-11 | mapped |
| 5 | "Route the AUP/Terms \"(and at the date of this version it does not)\" parenthetical to soleur:legal:clo" | `clo-ruling.md`, Non-Goals, tracking issue (C6) | mapped |
| 6 | "bump TC_VERSION only if knowledge-base/legal/tc-version-bump-policy.md says so" | CLO ruling 3; AC-12 asserts empty legal diff | mapped |
| 7 | "## User-Brand Impact, compliance/critical label, review panel (security-sentinel, user-impact-reviewer, data-integrity-guardian if a migration), CLO audit for legal text" | User-Brand Impact, frontmatter label, Ship gates, Phase 4 audit file; data-integrity-guardian not spawned (no migration) | mapped |
| 8 | "ASK the operator with the exact effects listed before merging" | Production Effects of Merge, Ship gates | mapped |
| 9 | "the addendum still lists CPO3-R2 as open (closed by #9792); record the verify-migrations finding (now issue #9825)" | Phase 5, ADR-277 addendum | mapped |
| 10 | "report the plan to the operator before building anything that touches hosted production behaviour" | This plan is the report; nothing built | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Classifier, resolver, lane, wiring | asks 1, 2 | asked |
| `gh` ref-delete and repo-delete family | "make hosted autonomous mode ask for the D1 destroy families" is the CPO's rule; the brief's ask 1 plus CPO4-R4 reachability evidence | inferred — justification: CPO4-R4 makes it a merge blocker when reachable, and it is (cc-dispatcher unscoped token); without it the approved copy would imply coverage it lacks |
| Hook-parity and mutation tests | CTO AC-9 and AC-10 in `cto-ruling.md`, requested by ask 2 | ruled |
| Follow-through probe (Phase 6) | — | inferred — justification: CPO4-R5/R7 time-gated close criteria must be automated or the tracker rots (plan Phase 2.9.1) |
| ADR-284, ADR-277/093 addenda, `model.c4` | ask 9 and the CTO ruling | asked |
| Audit file and supersede marker | ask 5 and 7 | asked |

### Split Assessment
- Subsystems touched: 4 — `apps/web-platform/server`, `apps/web-platform/components`, `knowledge-base/engineering/architecture`, `knowledge-base/legal`
- Planned files: about 25 | Estimated changed lines: about 1,100 (CTO estimate)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — over on two. Recommendation: **single PR**. Splitting copy
  from lane would ship the "pauses to ask" assurance without the lane (CLO C1 forbids), and splitting tests from lane violates RED-first.
  ADR-284, the ADR-277/093 addenda and the legal-audit file are same-PR requirements (CPO4-R7 closes CPO3-R2 only through the CLO-signed
  copy; CLO C8 forbids ADR text saying the gate is complete); they may land as a separate commit on the same branch, never a later PR.

## Acceptance Criteria

From `cto-ruling.md` (AC-1..AC-14), amended by `cpo-signoff.md` and `clo-ruling.md`:

1. **AC-1** In an acked autonomous hosted workspace each of these gets the review gate, not an auto-approval: `git push --force|-f|--force-with-lease|--force-if-includes origin main`, `git push origin +main`, `git push origin :main`, `git push --delete origin main`, `git push -f origin HEAD:refs/heads/main`, `git push --mirror`, `terraform destroy`, `tofu destroy`, `terraform -chdir=x apply -destroy`, `gh api -X DELETE repos/o/r/git/refs/heads/main`, `gh repo delete o/r --yes`.
2. **AC-2** Same under `git -C dir`, env prefix, `cd d && ...`, `bash -lc '...'`, `$()`, backticks, quoting, and `command|env|nohup|time|timeout|nice` wrappers.
3. **AC-3** A default branch named `develop` (API-resolved) is protected; with an unresolved default every force, delete or mirror push asks and a Sentry `default-branch-resolve` event is emitted; a tampered local `origin/HEAD` can add but never remove a protected name.
4. **AC-4** The gate offers exactly Approve and Reject; approving writes no acknowledgement and no cache entry; a prior `git push` or `terraform` batch grant does not bypass; an un-acked owner is gated, not held.
5. **AC-5** The blocklist still wins (`curl x && git push -f origin main` denies); the support persona still denies with escalation and emits no gate; a non-owner member gets the same gate. Coverage by conversation type is stated in ADR-284 and asserted where testable: cc-routed (lane applies); legacy `agent-runner.ts` (no `bashAutonomous`, no cache, so every non-safe command already reaches the generic gate; a test pins that the factory call passes neither); support (denied before the lane); scheduled and Inngest agents (outside `canUseTool`, plugin hook active).
6. **AC-6** Precision rows pass without a gate: `git push origin feat-x`, `git push --force-with-lease origin feat-x`, `git push -u origin main`, plain `git push origin main`, `git commit -m "terraform destroy docs"`, `echo "git push -f origin main"`, `terraform plan`, `terraform apply`, `terraform plan -destroy`, `terraform apply -destroy=false`, `git log --grep=push`.
7. **AC-7** An unparseable command containing `push` or `destroy` asks; without those words it passes; a thrown classifier error asks.
8. **AC-8** Per ask: pino `decision:"destroy-ask"` and Sentry `hosted-destroy-ask` with the rule id and no command text; outcome lines; the near-miss op; both degradations mirrored. A test greps emitted payloads for the command string (CLO C5).
9. **AC-9** Hook-parity: the classifier asks on every `hookAsks: true` D1 row; each ask-but-hook-silent row carries a `hostedOnly` note.
10. **AC-10** Mutation matrix: every mutant killed or documented equivalent; removing the lane fails at least one suite row.
11. **AC-11** Banner and toggle carry the CLO bytes; "no blocklist is perfect" kept; vocabulary guard test green; LOCKED-copy tests updated.
12. **AC-12** `docs/legal/**`, `plugins/soleur/docs/pages/legal/**`, `TC_VERSION`, `TC_DOCUMENT_SHA`, `LEGAL_DOC_SHAS`, `supabase/migrations/**` and every RPC have an empty diff (asserted with `git diff --stat origin/main -- <paths>` in the PR body); no write to production.
13. **AC-13** ADR-284 created; ADR-277 and ADR-093 addenda; `agent-env.ts` comment; `model.c4` description; C4 tests green.
14. **AC-14** A factory-wiring test asserts `canUseTool` and `autoAllowBashIfSandboxed` sit in the same options object handed to the SDK and that `permissions.allow` stays empty. It does NOT claim runtime proof: the existing gate test mocks the SDK, and whether the real SDK still calls `canUseTool` under `autoAllowBashIfSandboxed` rests on the #3252 behaviour. The runtime proof is the post-deploy dev probe (CLO C9), stated as such in ADR-284; a gate test must use the API-key path or it passes vacuously.
15. **AC-15** Reject, timeout and abort deny, and the deny text instructs the agent not to retry or respell (CPO4-R2).
16. **AC-16** The R5 thresholds (revert at more than 25 percent of one workspace's hosted Bash calls from one rule in 24 h, or `destroy-classifier-error` non-zero past 24 h; tune on `git-push-unknown-default` above 10 percent of asks over 7 days or fail-closed-keyword plus raw-scan above 25 percent) are written into ADR-284 before merge.
17. **AC-17** The tracking issue for the legal parenthetical (CLO C6) exists, linked from the PR body and the audit; the follow-through probe and tracker directive exist (Phase 6).
18. **AC-18** PR body AND the changelog entry state: no `TC_VERSION` bump, no re-acceptance, no acknowledgement reset, and that a previously granted "Approve all git push" or "terraform" no longer covers the destroy forms (CPO4-R6).
19. **AC-19** Gate lifecycle, each a test: a late Approve after expiry is ignored and the card renders as expired; a WS disconnect mid-card leaves the gate pending and the card is replayed on reconnect (or the plan records the existing behaviour if replay does not exist); offline-notify fires for this card; a container restart orphaning a pending gate denies the command rather than running it; two cards back to back and a destroy card alongside a different pending gate resolve independently by `gateId` (approving A never releases B).
20. **AC-20** Card visibility: with a destroy segment placed at character 250 of a `&&` chain, the question text still names the matched segment and the family; the question says Approve runs the whole command; a forged `Approve all <prefix>` selection denies and writes no cache entry.
21. **AC-21** Un-acked owner whose first command is a destroy command: the card appears (not the disclosure hold); approving it writes no acknowledgement; the next benign command is then held by the existing first-run disclosure.
22. **AC-22** Corpus rows for the implicit-destination forms (`git push -f`, `git push -f origin HEAD`, `git push --force-with-lease`, `... .`) assert ask with rule `git-force-implicit`; for every `ask` row `isBashCommandSafe(cmd) === false` (CTO invariant); `gh` spellings (`-X DELETE`, `-XDELETE`, `--method DELETE`, `--method=DELETE`, `--input`) each have a row; GraphQL `deleteRef`/`deleteRepository` rows assert a near-miss event and NO ask.
23. **AC-23** Resolver hardening: a symlink, FIFO, oversize or malformed `origin/HEAD` is ignored (adds no name, no throw); a positive result expires after the TTL; the resolver reads repo and installation from the dispatch scope, never from the empty `ctx.repoOwner`.

## Guard Contract

### Guard 1 — hosted must-ask lane

**Property.** No hosted Bash command that force-pushes over, deletes or mirror-pushes a protected branch, or runs terraform/tofu destroy or a `gh` ref or repository delete, reaches execution without an Approve from the acting session user.

**Assembly.** The chokepoint is the Bash branch of `createCanUseTool` in `permission-callback.ts`; every route that could execute a command without a card flows through one of five in-file routes: the `isBashCommandSafe` allow, the `autonomous-bypass` allow, the first-run disclosure-hold release, the existing-workspace opt-out release and the `bashApprovalCache.allow` lookup; plus two outside this chokepoint, the SDK-side `autoAllowBashIfSandboxed` and `permissions.allow` (kept empty). The lane sits AFTER the safe-bash allow and must precede the other four in-file routes; the safe-bash route is closed by the corpus invariant that every ask row is not safe-bash (AC-22); the two SDK-side routes are pinned by AC-14 and the `allow: []` test. A fifth path is a forged gate selection, closed by forcing `cachePrefix = ""` and denying any selection other than `Approve` (AC-20). Command shapes the property quantifies over: every spelling in the corpus, every wrapper and nesting form, and the unparseable fail-closed arm. Two call sites build `canUseTool` (`cc-dispatcher.ts` and legacy `agent-runner.ts`); the second has no bypass or cache and is pinned by a test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Move the lane after the `autonomous-bypass` allow (and, as separate mutants, after the disclosure hold and after the cache lookup) | RED |
| 2 | Make the classifier dispatch return `null` for every input, or have the corpus loader read zero rows (a lane reporting "0 checked" and passing) | RED |
| 3 | After a compliant first spelling, drop the second member: remove each force spelling in turn (`-f`, `--force`, `--force-with-lease`, `--force-if-includes`, cluster, `+ref`), each delete spelling, `--mirror`/`--all`, `gh api` DELETE, `gh repo delete`, `tofu`, `-chdir=`, `apply -destroy` | RED |
| 4 | Restore "Approve all" in the gate options; let `mustAsk` skip `verifyAutonomousAck`; stop forcing `cachePrefix = ""` (forged `Approve all` selection must deny) | RED |
| 5 | Make `authoritative = false` stop asking; drop the API-resolved name; let local `origin/HEAD` remove a name | RED |
| 6 | Let the support persona reach the gate; let the blocklist run after the lane (`curl x && git push -f origin main` must deny) | RED |
| 7 | Remove the `-destroy=false` and `plan -destroy` exemptions' counterpart: make them ask | RED (must-pass rows) |

**Harness rows.** (a) Edit the mutation harness so a mutant fails to apply (anchor missing): the harness must fail, not skip. (b) Edit the corpus runner to ignore `expect: "pass"` rows: the precision rows must redden it. (c) A must-PASS input that is not the canonical: a `git push --force-with-lease origin feat-x` with a protected set that excludes `feat-x`. (d) Hook-parity with the hook given an empty corpus: the test must fail on a floor, not pass vacuously.

**Anchor.** The corpus is stored data compared to the hook's behaviour: the parity test runs the real hook, so a weakening of the corpus alone cannot pass; the row-count floor is a literal (`MIN_ASSERTS`) plus set identity of rule ids; the merge-base diff of `destroy-ask-corpus.json` is reviewed by the panel. The mutation harness uses anchor-asserted mutants, so a refactor that moves the lane fails the harness rather than silently skipping it.

### Guard 2 — copy vocabulary and telemetry hygiene

**Property.** No banner, toggle or card text claims the lane blocks, prevents or protects, and no emitted log or Sentry payload carries the command text.

**Assembly.** Banner constant, toggle paragraph, the server-built card question, the deny text; and every pino, `warnSilentFallback` and `reportSilentFallback` call in the lane, the classifier and the resolver (the full set is enumerated by `git grep -n "destroy-ask\|default-branch-resolve\|destroy-classifier"` in the test).

**Home.** Guard 2 lives in `test/permission-callback-destroy-ask.test.ts` (telemetry payload grep and card text) and the two copy tests (vocabulary); its mutants run in the Phase 3 harness alongside Guard 1's. Rows 4 and the floor are the same assertion: the scanned string list must be non-empty and name each source.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Insert "blocks" or "protects" into the toggle paragraph | RED |
| 2 | Put `command` into a Sentry `extra` in one of the lane's calls | RED |
| 3 | Add a second telemetry call site that logs the redacted preview | RED |
| 4 | Make the vocabulary test scan zero strings (empty source list) | RED |

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Binding ruling C (lane now, hook consolidation later); no migration, no flag; ADR-284 plus ADR-277 addendum; C4 description edit only. `cto-ruling.md`.

### Product (CPO)
**Status:** reviewed
**Assessment:** APPROVED WITH CONDITIONS CPO4-R1..R8; merge blocked until R3 (CLO copy sign-off) and R4 (gh residual fact check, now resolved to in-scope). `cpo-signoff.md`.

### Legal (CLO)
**Status:** reviewed
**Assessment:** Copy bytes drafted; legal text untouched; existing acknowledgements stay valid; no GDPR register change; conditions C1-C9; DISCHARGED if they hold. `clo-ruling.md`.

### Product/UX Gate
**Tier:** none
**Decision:** reviewed (excluded surface)
**Agents invoked:** none (domain leaders above)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings
The edited files match the UI-surface glob (`components/**/*.tsx`), but the change is a copy-constant and paragraph edit with no structural or layout change, which `ui-surface-terms.md` excludes ("Pure copy or style tweaks"). No new component, no new page, no flow change; the card is a server-built string through the unchanged `ReviewGateCard`. Phase 4 contains a stop condition: if the card needs a component change, the wireframe gate applies. Copy review is by the CLO (verbatim) rather than the copywriter.

## Observability

```yaml
liveness_signal:
  what: "Pino decision:destroy-ask lines (Better Stack) and Sentry hosted-destroy-ask events, emitted once per ask; absence of the stream after deploy plus a dev probe means the lane is not live"
  cadence: "per ask; verified by the dev probe after deploy and the 24 h and 7 d soak probe"
  alert_target: "Sentry issue for classifier-error and default-branch-resolve; the R5 revert and tune thresholds exit 3 from the follow-through probe on tracker 9776"
  configured_in: "apps/web-platform/server/permission-callback.ts (lane), apps/web-platform/server/resolve-protected-branches.ts, scripts/followthroughs/hosted-destroy-ask-window-9776.sh"
error_reporting:
  destination: "Sentry web-platform via warnSilentFallback/reportSilentFallback (feature cc-permissions), plus Better Stack through the shared pino logger"
  fail_loud: "op destroy-classifier-error and op default-branch-resolve events; a thrown classifier error also forces the ask, so the failure is a card, never a silent allow"
failure_modes:
  - mode: "Default-branch lookup fails (API outage, no installation)"
    detection: "Sentry op default-branch-resolve; ask rate for git-push-unknown-default in the probe"
    alert_route: "Sentry issue; probe tune threshold above 10 percent of asks over 7 days"
  - mode: "Classifier throws on a command shape"
    detection: "Sentry op destroy-classifier-error"
    alert_route: "Sentry issue; revert if non-zero past 24 h (CPO4-R5)"
  - mode: "Ask storm from one rule (false-positive class)"
    detection: "per-rule counts from the Better Stack query in the probe"
    alert_route: "probe exit 3 on tracker 9776; revert above 25 percent of one workspace's hosted Bash calls in 24 h"
  - mode: "A destructive spelling is missed"
    detection: "Sentry op destroy-classifier-near-miss (keyword present, no match) and the gh plus delete near-miss"
    alert_route: "Sentry issue; CLO re-evaluation trigger"
logs:
  where: "Better Stack (pino WARN and above) and Sentry"
  retention: "Better Stack 90 days per Privacy Policy 5.14; Sentry per project retention"
discoverability_test:
  command: git grep -l hosted-destroy-ask -- apps/web-platform/server/permission-callback.ts
  expected_output: permission-callback.ts
  credentials_required: "Better Stack query token (Doppler prd_terraform) — the per-rule ask counts live only in the private Better Stack sink, so no unauthenticated probe verifies the runtime stream; the static command above proves the emitter is wired in code"
```

Write-frequency estimate: zero database writes; Sentry at most 32 events per conversation context.

## Test Scenarios

Corpus-driven (AC-1, AC-2, AC-6, AC-7); lane ordering (AC-4, AC-5, mutation matrix rows 1, 4, 6); cache laundering (grant `git push`, then
`git push --force origin main` still gates; grant `terraform`, then `terraform destroy` still gates); un-acked owner (gated, not held; approving is
not an acknowledgement); default-branch resolver (API name, tampered `origin/HEAD`, failure); telemetry hygiene (CLO C5); copy vocabulary (CLO C3); AC-14 real factory.

## Non-Goals

- Versioned acknowledgement (trigger: any change that widens what hosted autonomous mode may do without asking; design in ADR-284; CPO4-R8). No issue filed now.
- Legal text edits and `TC_VERSION` (CLO ruling 3). Deferred with a dated trigger and a tracking issue (CLO C6): revise the AUP 5.7 and T&C 3a.7 parenthetical at the earliest of the next `TC_VERSION` bump, publication of #9603's hosted-coverage claim, the first arms-length workspace owner, 2027-01-08.
- Enabling the plugin hook in hosted sessions (D8 stands; later consolidation conditional on a measured hosted `ask`).
- Residuals recorded in ADR-284: variable-built command names, aliases, scripts written then run, terragrunt/pulumi, `git update-ref`, recursive `rm`, force-push to non-default branches, owner-only approval.
- #9825 (verify-migrations skip) is recorded in the ADR-277 addendum only; its fix is its own work.
- CPO3-R3 (ask-rate measurement of the 4b classes on real transcripts) and #9603 (control page) are separate items.

## Decisions held for the operator (plan-review taste and user-challenge findings, NOT applied)

Applied above: every mechanical finding. The following change scope or product behaviour and are surfaced, not decided:

1. **Cut or keep the Phase 6 follow-through probe** (simplicity, DHH: the CPO needs the numbers recorded, not an automated evaluator; a by-hand
   Better Stack query at 24 h and 7 d would do). Plan default: keep, with the two windows and the call-count floor, because an unautomated
   tracker is the failure mode `plan` Phase 2.9.1 exists to prevent.
2. **GraphQL equivalents of the `gh` family** (`gh api graphql` `deleteRef`, `deleteRepository`, `updateRef` with force): same token, same
   harm. Plan default: near-miss telemetry and a named ADR-284 residual only, because CPO4-R1 sends any widening back to the CPO. The CPO
   needs to say whether they join the classifier in this PR.
3. **Down-scope the hosted installation token** (DHH: the token is minted unscoped, so it carries `administration: write`; dropping it
   would remove `gh repo delete` and repo-level API deletion with no classifier). Plan default: not in this PR (other hosted consumers may
   need it; not verified); recorded in ADR-284 as an alternative worth measuring.
4. **Per-turn auto-deny after a Reject** (spec-flow: a retrying agent produces a card per respelling and inflates the R5 numerator).
   Plan default: not built; the deny text tells the agent not to retry (CPO4-R2). Revisit if the telemetry shows retry loops.
5. **Card sentence "this is not the autonomous-mode acknowledgement"** for the un-acked owner (spec-flow). Plan default: not added, because
   card wording beyond CLO C4 is the CLO's; AC-21 pins the behaviour.
6. **Pre-authorised revert if the post-deploy dev probe (CLO C9) fails** (spec-flow, user-challenge touching CLO C1's one-unit rule): the
   banner assurance reaches production in the same build as the lane and is verified after merge. Plan default: a failed probe means an
   immediate revert PR (copy and lane together), decided by the operator at that moment.
7. **Trim the mutation matrix** (simplicity, DHH): keep as ruled; only the cost bound was applied.
8. **Drop the 30 s negative resolver cache** (simplicity): kept, it is in the CTO ruling.

## Production Effects of Merge (for the operator go-ahead)

No migration, no database write, no acknowledgement reset, no `TC_VERSION` change, no Terms re-acceptance, no `bash_autonomous` write, no env, Doppler or Terraform change. Observable effects: (1) hosted sessions ask on the destroy families and the `gh` ref and repository delete forms; (2) "Approve all" is no longer offered for them and an earlier `git push` or `terraform` grant no longer covers them, in autonomous and non-autonomous mode; (3) a rare extra GitHub API read per session record, only on a force or delete push; (4) banner and settings-toggle copy change for every viewer, already-acknowledged owners stay acknowledged; (5) new Sentry and Better Stack events. Rollback is `git revert` plus a normal redeploy. The operator is asked for an explicit go-ahead before the merge is armed even though no production write is involved, because the brief requires it.

Separate open item, not part of this PR: the C2 follow-through from PR #9792 (a scoped re-run of the supersede UPDATE after the new build served, under an explicit go-ahead). Its status is not recorded in the PR or the repo.

## Ship gates (this PR)

`## User-Brand Impact` present; `compliance/critical` label; issue-filing: one issue (CLO C6) filed with `--milestone "Post-MVP / Later"`, a literal absolute `--body-file`, and `User-Impact:` plus `Fix-Size:` lines, and the net-issue-flow override block with one justification (the PR closes none; it carries `Ref #9776`); review panel: security-sentinel, user-impact-reviewer, architecture-strategist, observability-coverage-reviewer, test-design-reviewer, code-simplicity-reviewer, pattern-recognition-specialist (data-integrity-guardian is not spawned: no migration); CLO attestation against C1-C9 using the new audit file; reassign #9776 from "Post-MVP / Later" to the active phase milestone when the PR opens (CPO4-R7); emit-review-trailer pushed before arming merge; post-deploy steps gated on `deploy-arm.sh find <sha>` returning `DEPLOY=success` and `served <sha>` returning `CONTAINS`; post-merge dev verification (CLO C9, CPO measurement 1) with data pulled by API.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one carries all four lines.
- `BLOCKED_BASH_PATTERNS` does not match `bash -lc` or `zsh|dash|ksh -c`; the classifier unwraps those itself and the corpus has rows for them. Do not widen the blocklist in this PR (CPO4-R1).
- **Ordinal changed at work time (2026-10-10):** the plan and the three rulings were written against ADR-282; over `refs/remotes/origin/*` 282 (sole-copy LUKS) and 283 (git-data liveness heartbeat) are claimed on sibling branches, so the record is ADR-284. The rulings in this directory keep their original wording (dated, binding records) and read as ADR-284. The plan, tasks and code comments are swept.
- The ADR-284 ordinal is provisional; re-derive over `refs/remotes/origin/*` at ship time and sweep this plan, `tasks.md` and the ACs for the old number.
- Scanner ratchets (fixture-relative-assert, guard-vacuity-floor, lint-shell-capture-exit, and the rest) walk `git ls-files`: run them on the committed tree.
- The new copy contains "without asking" and "terraform destroy"; the old LOCKED tests that asserted those strings must be rewritten, not deleted, and the vocabulary guard test must not reintroduce the assumption.
- Rule ids carry no section prefix (`hosted-destroy-ask:*`, ADR-205 namespace) and never include command text.
