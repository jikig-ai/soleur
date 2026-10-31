---
title: "sandbox: post-incident follow-ups from the hosted Bash outage"
date: 2026-10-31
slug: fix-hosted-bash-outage-followups
branch: feat-hosted-bash-outage-followups
issue: 10455
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# sandbox: post-incident follow-ups from the hosted Bash outage

## Overview

Sequence the still-open follow-ups of tracker #10455 into five PRs, ordered by user impact. Every PR uses `Ref #10455` (never `Closes`). The request listed 14 unchecked items; most had already shipped (synthetic #10697, smoke and AF_UNIX variant #10546, routed alerts #10892), so this plan covers only the genuine remainder. Decided earlier: no user outreach and no affected-user count (#10477, operator, 2026-10-31); #5941 closes as superseded by #10453/#10546.

| PR | Scope | Gate |
|---|---|---|
| 1a | Cross-tenant read channel: measure what a sibling tenant can read of persisted CLI output under the real CLI, mask or relocate it, file-tool arm | none; unblocked. A red result triggers the stop rule below |
| 1b | Fix the `op=tenant-deny` emit and its alert, coupling test, records | after 1a is merged or its result is recorded |
| 2 | Promote `sdk_bash_smoke` to the blocking rollback lane | merge/ship needs operator authorization (rollback lane) |
| 3 | Plain-language Bash-failure message, classify other helper steps | none; lands before PR 2 touches the same alert filter |
| 4 | Verify the Slack wake path for Better Stack and Sentry alerts | investigation first; a PR only if a gap is found |

PR 1a and 1b are specified in full. PRs 2-4 are specified to phase level with anchors; each gets its own `/work` and `/review`.

## Research Insights

**Premise Validation (2026-10-31, `origin/main` d1fa52f922; worktree up to date).** Held: #10455, #10548, #11085, #8629 are OPEN; the masked-dir precedent (#10892) exists (emit `agent-runner-sandbox-config.ts:537-556`, rule `infra/sentry/issue-alerts.tf:1754-1807`, reference `infra/sentry/alert-reference.json:1883-1930`). Collision pre-check: no open PR names #10455 (the only hit was an unrelated `test-all.sh` run in another worktree). Stale: the tracker's "other `op=tenant-deny` site near line 641" is a `log.info` (`:636-674`), not an emit; only `:567` needs a fix.

**Property List.** (P1) a sibling tenant's Bash cannot read another tenant's persisted CLI output; (P2) a missing deny root reaches a human without a dashboard; (P3) a deploy whose Bash is broken rolls back by itself; (P4) a user whose Bash fails sees a plain sentence; (P5) the alerts above wake the operator, not only email them.

**Cut List.** (1) A standalone measurement script: G2 (`test/sandbox-wrapped-command-runtime.test.ts:293-330`) already searches `/tmp`, `$TMPDIR`, `$HOME` from a sibling sandbox, so the measurement extends it. (2) Spec FR3 "derive the deny set from `agentEnv`": the deny set is constant by design (`agent-runner-sandbox-config.ts:438-439`, `:509-513`; literal arrays pinned in `test/agent-sandbox-tenant-deny.test.ts:76-220`); replaced by a coupling assertion (PR 1b). (3) Review cuts applied: the bespoke vitest for the new discoverability script, the dedicated coupling-test file, the shared key constant (the test scans the helpers' source for `env.<KEY>` reads instead), and the duplicate recording of the measurement in three places (ADR addendum is the one record, plus a one-line breach-register row).

**Institutional learnings applied.** `2026-09-23-the-alert-i-was-told-paged-routed-to-nobody.md` (an `Error` first argument drops the tagged capture, #8629); `security-issues/2026-10-18-a-fix-that-removes-a-block-must-re-derive-what-the-block-was-bounding-...md` (prove cross-tenant isolation with a two-session test; a green canary is a claim); `2026-10-08-file-tool-tier-outside-bwrap-isolation-boundary-is-the-cli-process.md` (Read/Glob/Grep run outside bwrap); `2026-09-23-arming-an-advisory-gate-turns-its-soft-defaults-into-bypasses.md` (PR 2); `best-practices/2026-06-17-report-only-ci-deploy-gate-topology-denominator-stream-redaction.md`.

## Research Reconciliation — Spec vs. Codebase

| Spec / tracker claim | Reality | Plan response |
|---|---|---|
| FR3: derive deny set from `agentEnv` | `buildAgentSandboxConfig` (`:447`) takes no env; `peerMessagingSocketDirs`/`sessionTranscriptDirs` default to `process.env` and return the UNION of every base the CLI could use (`:405-434`). `agentEnv` adds only a per-tenant `CLAUDE_CODE_TMPDIR` (`/tmp/.cs/<sha16>`), already denied via `AGENT_SESSION_TMP_ROOT` (`:625`). `CLAUDE_CONFIG_DIR`/`XDG_RUNTIME_DIR` are not in `agentEnv` (`agent-env.ts:37-53`). | Keep the constant deny set; assert coverage against a config built under matching stubbed env (PR 1b). |
| "Other `op=tenant-deny` site near 641" | `log.info`, no Sentry path | No change; the copied op-contract test must be scoped to `reportSilentFallback` calls or it trips on `:641`. |
| "Other persisted CLI output is reachable" | `~/.claude/{history.jsonl,debug,todos,tasks,shell-snapshots}` are not in `denyRead`; only the outer wrap masks them (the `HOME_SESSION_DIRS` list in `agent-outer-wrap.ts`), gated on `AGENT_OUTER_WRAP=1` (`outerWrapEnabled`). Production events show `outer_wrap=false`. `HOME` is allowlisted and `agentEnv.HOME ?? "/home/soleur"` implies one shared home. `history.jsonl` is one file for every tenant's prompts, and `denyRead` takes directories only (a file becomes `--tmpfs` and fails the spawn). | Measured in PR 1a (see AC and ADR-075 addendum 2026-10-31): prompt, tool output and an exported credential are not readable by a sibling; session metadata, a peer key file, shell snapshots and the account state file ARE. `history.jsonl`, `debug/`, `todos/`, `tasks/` were not produced by the SDK print mode: **unmeasured, not safe**. CTO ruling: documented residual, no relocation; triggers recorded in the addendum. |
| G2 can find the prompt/tool-result needle | `runBash` hardcodes `prompt: "run it"`; `findNeedle` only parses `.output` files for `grpc_proxy=`; the stub drives one Bash call, which writes neither `todos` nor `tasks`; `debug` needs `--debug`; `history.jsonl` is probably not written in print mode. | PR 1a drives the real vendored CLI and enumerates what it persisted by diffing the tree (below). |

## Implementation Phases

### PR 1a — cross-tenant read channel

**Stop rule (red branch). CTO ruling 2026-10-31: the measured residual (session metadata incl. the sibling's workspace identifier, a peer key file, shell snapshots, account state) is a documented residual, not a red result requiring relocation; the CLO determination is provisional (reachability only) and the production-HOME census is an operator-authorised action, not run here.** If the measurement finds any tenant-persisted content readable from a sibling sandbox: (1) freeze merge of PR 1b and later PRs that depend on the result; (2) route to `soleur:legal:clo` the same day (Art. 32 finding; the CLO decides whether Art. 33 applies and sizes the historic exposure window: production has run `outer_wrap=false` on a shared `/home/soleur` since the first deploy of the affected build); (3) interim containment is the fix itself, so PR 1a is the fastest path and is not blocked behind alert work; (4) ship the mask or relocation behind a flag with a rollback. Independent of red or green, a counts-only, metadata-only census of the production HOME for `history.jsonl`, `debug/`, `todos/` and `tasks/` is owed before any statement to users; the CLO authorises the method and the operator must authorise production access; this plan does not run it. The purge of already-persisted shared data is an irreversible data operation: it needs the CLO's sizing first and your explicit authorization at execution time; it is not run by this plan. A green result is only accepted when Phase 1's non-vacuity ACs hold.

**Phase 1 — Measure (RED first, under the real CLI).** Extend G2 (`test/sandbox-wrapped-command-runtime.test.ts`). Run session A under the real vendored CLI (2.1.284) in the production posture (`outer_wrap=false`, shared HOME), with a per-run synthesized needle in the user prompt (parameterize the hardcoded `prompt: "run it"` in `runBash`) and one in a tool result. Enumerate what A persisted by diffing `$HOME`, `${AGENT_SESSION_TMP_ROOT}` and `/tmp` before and after (no hand-planted file counts as a measurement). Then session B searches the same surface in one pass (`grep -rIlF -e needle1 -e needle2 -e needle3`) and the test prints `NEEDLE_PATHS` per needle class. Non-vacuity, per needle: a CONTROL arm shows the needle at a named path in A's persisted tree on the host before B's zero-hit result counts; a class A never persisted is reported `not_exercisable`, never green. Record wall time; keep it in the existing G2 job (no new CI job). `describe.skipIf(!SANDBOX_OK)` stays, and the AC requires the run log to show G2 executed, not skipped.

**Phase 1a — File-tool arm.** Read, Grep and Glob run in the CLI process outside bwrap, so `denyRead` does not apply to them; containment is `createSandboxHook` (`isPathInWorkspace` realpath check, `patternEscapesWorkspace`). Add an arm that issues Read/Grep/Glob (absolute and `../` patterns) at `$HOME/.claude/history.jsonl`, plus a workspace symlink pointing to it, through the real hook, and confirm the hook matcher covers subagent (Task) tools and the Notebook tools.

**Phase 1b — Conditional fix (only if Phase 1 or 1a is red).** Structural fix: relocate the CLI's mutable state to a per-tenant base by setting `CLAUDE_CONFIG_DIR` under the existing `claudeTmpDir` (`/tmp/.cs/<sha16>/...`), emitted from `buildAgentEnv`. Not HOME: `~/.cache`, `~/.config/gh` and similar stay put. Three decisions to settle with evidence before coding: (a) auth: with `CLAUDE_CONFIG_DIR` set, `.claude.json` and `.credentials.json` move with it; auth rides the env token, so verify the shared `.credentials.json` is absent, and that no subscription refresh writes to it (a shared copy is itself a cross-tenant hazard); (b) `settings.json` and plugins: the platform plugin is passed by path, seed `settings.json` read-only per tenant; (c) session resume: `/tmp/.cs` does not survive a restart, so keep `projects/` on the persistent volume under a per-tenant subpath, or state the loss. Every `buildAgentEnv` consumer must receive the same key (legacy runner, `cc-dispatcher`, the SDK spawn path). Gate behind a runtime flag, and add `CLAUDE_CONFIG_DIR` to the `sdk_wrapper_shim_prodtuple` smoke tuple before PR 2 makes the smoke blocking. Mask additions to `denyRead` are used only for directories the measurement names; never pre-written.

### PR 1b — alert, coupling, records

**Phase 2 — Fix the `op=tenant-deny` emit.** In `agent-runner-sandbox-config.ts:566-572` change `reportSilentFallback(new Error(...), ...)` to the masked-dir shape (`:548-555`): first argument `null`, constant message, a `dir_kind`-style tag (`volume` vs `worktree`), `extra: { code: "tenant_deny_root_missing", denyRoot, workspace }`. Add `sentry_alert "tenant_deny_root_missing"` to `infra/sentry/issue-alerts.tf` (feature eq `agent-sandbox`, op eq `tenant-deny`, email to issue owners, a `frequency_minutes` value not already used by a sibling rule: 39 is taken by the masked-dir rule) and its `alert-reference.json` entry (new key). Fold the op-contract assertions into `test/agent-sandbox-tenant-deny.test.ts`, scoped to `reportSilentFallback` calls so the `log.info` at `:641` is not matched. Add `scripts/tenant-deny-alert-discoverability.sh` (repo root; prints `TENANT_DENY_ALERT_PATH_OK`), copied from `scripts/masked-dir-alert-discoverability.sh`; no separate vitest. This is the second copy: a third alert triggers extraction into one parameterized script (recorded here, not as a new issue). Post-merge: confirm the Sentry apply workflow succeeded and the rule is live.

**Phase 3 — Coupling assertion.** In the same deny test file, build a real `agentEnv` with `buildAgentEnv`, build the sandbox config under matching stubbed `process.env`, and assert every directory returned by `peerMessagingSocketDirs`/`sessionTranscriptDirs` is under a path in `denyRead`; and assert, by scanning those helpers' source for `env\.\w+` reads, that every key they read is in the key set the test lists (a new derivation key breaks the test). If PR 1a relocated state, the assertion also covers `CLAUDE_CONFIG_DIR`.

**Phase 4 — Records.** One ADR-075 addendum (measurement result, constant deny set retained, relocation if shipped, the coupling assertion). One breach-register row for #10445 (negative determination: commands never executed, no exposure mechanism identified; never "no data affected"); if PR 1a was red, a second row for the cross-tenant finding as the CLO directs. One comment on #10455.

### PR 2 — promote the smoke to blocking
Start from the soak verdict (`scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh`; 2026-10-30: 179 consecutive passes, 10 days, coverage `sdk_wrapper_shim_prodtuple`). Owed before editing, each a numeric pass/fail: the alert-flap review (rows of `faithful_canary_sandbox_broken` versus real failed verdicts, pulled with `scripts/betterstack-query.sh`; block promotion if any non-real flap in the soak) and the canary `memory.peak` under 80% of 1536m with zero `oom_kill`. Then in `infra/ci-deploy.sh` remove `|| true` at `:5477`, route `sdk_bash_smoke_failed` into the `DEPLOY_ROLLBACK` lane next to `:5416`/`:5674`, keep `smoke_infra_error` non-rolling-back. Rollback bound: one rollback only; if the rollback target is also red, freeze deploys and page (no loop). Add a `deploy_rolled_back_sdk_bash` alert BEFORE deleting `faithful_canary_sandbox_broken` in `infra/betterstack-logs-alerts.tf`, so no signal gap. A forced-red run in staging precedes merge. Audit every lenient branch of the smoke for a bypass once it blocks. Merge needs operator authorization.

### PR 3 — plain-language Bash-failure message (before PR 2)
First task: locate the client row that renders the tool error (not yet located). Build on `classifyBashSandboxFailure` (`sandbox-startup-classifier.ts:267`, called from `cc-dispatcher.ts:395`). Map only classified sandbox-setup failures to one plain sentence. Because a sandbox-setup failure is deterministic, retrying the same command fails again: the copy says so and points to a new session or support, retry is text only (a Retry button would re-trigger `wg-ui-feature-requires-pen-wireframe`). Raw text stays behind the existing details disclosure; genuine command errors are not swallowed. Classify the remaining helper steps (`prctl`, `seccomp` EPERM) in the classifier and the Better Stack filter, with real-shaped fixtures and an AC that the alert fires for each newly classified class. PR 3 lands before PR 2 because both edit the same alert filter.

### PR 4 — Slack wake path
Investigation first: read ADR-260 and `var.betterstack_paid_tier`; ADR-260 covers Better Stack to Slack for DB-outage paging, while Sentry rules (masked-dir, tenant-deny, agent-auth) are a different integration. For each sandbox alert record whether a test page reaches Slack, with the evidence command. A PR only if a gap is found; otherwise record the result on #10455. Until then, the PR 1b rule is email-only and the plan says so in its PR body.

## Files to Edit / Create
**PR 1a:** `apps/web-platform/test/sandbox-wrapped-command-runtime.test.ts`, `test/sandbox-hook.test.ts`; `apps/web-platform/server/sandbox-hook.ts`, `permission-callback.ts`, `tool-path-checker.ts`, `sandbox.ts` (hook fix); ADR-075 addendum; `knowledge-base/legal/` determination, breach-register row and supersede markers (CLO ruling). Phase 1b files (`agent-env.ts`, `agent-runner-query-options.ts`, the dispatcher spawn path) are NOT touched: relocation was ruled out.
**PR 1b:** `apps/web-platform/server/agent-runner-sandbox-config.ts`; `apps/web-platform/infra/sentry/issue-alerts.tf`, `alert-reference.json`; `apps/web-platform/test/agent-sandbox-tenant-deny.test.ts`; create `scripts/tenant-deny-alert-discoverability.sh`; `knowledge-base/legal/breach-register.md`; ADR-075 addendum.
**PR 2/3/4:** per sections above.

## Open Code-Review Overlap
None (no open `code-review` issue names `agent-runner-sandbox-config.ts`, `agent-env.ts`, `ci-deploy.sh`, `sandbox-startup-classifier.ts` or `infra/sentry/issue-alerts.tf`).

## Architecture Decision (ADR/C4)
### ADR
Amend ADR-075 (one addendum, PR 1b): measurement outcome, constant deny set retained, relocation if shipped, coupling assertion. PR 2 adds an ADR-079 addendum when the smoke blocks.
### C4 views
No C4 impact. Checked against `model.c4`/`views.c4`/`spec.c4`: external human actors (tenant end user, operator) unchanged; external systems (Sentry, Better Stack) already modeled with no new edge; no new container or data store; actor-to-surface access relationships unchanged (a relocated config dir stays inside the existing agent-session boundary). Run `plugins/soleur/test/c4-count-parity.test.sh` green before shipping.

## Domain Review
**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm; plan-review panel run 2026-10-31).
### Engineering
**Status:** reviewed. CTO: PR order, measurement-first, parked items with triggers. Plan-review panel (DHH, Kieran, simplicity, architecture, spec-flow, CTO devex) applied; see Review Disposition.
### Product
**Status:** reviewed. CPO: PR 3 is the best user-facing item; copy-only on the existing error row.
### Legal
**Status:** reviewed. CLO: no Art. 33/34 duty for the outage; a reachable cross-tenant leak found by PR 1a is a separate Art. 32 finding routed to the CLO.
### Product/UX Gate
**Tier:** none (copy-only change to an existing row; no new component or page file).

## User-Brand Impact
**If this lands broken, the user experiences:** a Bash failure again showing the raw `apply-seccomp` text (PR 2/3 regression), or a sibling tenant able to read their prompts or tool output from a shared home directory (PR 1a).
**If this leaks, the user's workflow data is exposed via:** persisted CLI output readable from another tenant's sandbox or through the unsandboxed file tools. Measured readable today: session metadata (including the other tenant's workspace identifier), a peer key file, shell snapshots, the account state file. Not measured: `history.jsonl`, `debug`, `todos`, `tasks`, and the production HOME.
**Brand-survival threshold:** single-user incident

## Observability
```yaml
liveness_signal:
  what: Sentry issue-alert rule tenant_deny_root_missing (feature agent-sandbox, op tenant-deny) plus the existing runtime synthetic heartbeats web_bash_synthetic[web-1|web-2]
  cadence: rule evaluates on event; synthetic every 15 min
  alert_target: email to issue owners (Sentry); Better Stack heartbeat incident
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf, infra Better Stack heartbeats
error_reporting:
  destination: Sentry captureMessage with tags feature=agent-sandbox, op=tenant-deny (null first argument, so the pino mirror does not pre-capture it)
  fail_loud: yes, production-only gate retained for expected-present roots
failure_modes:
  - mode: volume or worktree tenant deny root missing in production
    detection: reportSilentFallback(null, ...) with extra.code tenant_deny_root_missing
    alert_route: Sentry rule tenant_deny_root_missing, email (Slack wake path is PR 4)
  - mode: sibling tenant can read persisted CLI output
    detection: G2 persisted-output arm in CI (pre-merge); no runtime detector exists, named as a residual in the ADR-075 addendum
    alert_route: CI red
  - mode: smoke red on both the new and the rollback release (PR 2)
    detection: deploy_rolled_back_sdk_bash alert, then deploys frozen
    alert_route: Better Stack page
logs:
  where: Sentry plus the pino error line from reportSilentFallback
  retention: Sentry project retention
discoverability_test:
  command: bash scripts/tenant-deny-alert-discoverability.sh
  expected_output: TENANT_DENY_ALERT_PATH_OK
```

## Guard Contract
### Guard 1 — cross-tenant persisted-output test (G2 extension, PR 1a)
**Property.** Among the classes the real CLI produced in the measured mode (credential, prompt text, tool output), none is readable from a sibling tenant's sandbox or through the file tools. Classes the mode did not produce are unmeasured, and the readable session metadata is a pinned, documented residual.
**Assembly.** The surface is everything B can read, not a list of file names: `/tmp`, `$TMPDIR`, `$HOME`, `AGENT_SESSION_TMP_ROOT`, searched by content over the whole tree, plus the file-tool path (Read/Grep/Glob through `createSandboxHook`). The chokepoint is `buildAgentSandboxConfig`, shared by the legacy runner and the cc-soleur-go factory; the test runs under the production posture (`outer_wrap=false`).
**Mutation matrix.**
| # | Edit | Must go RED because |
|---|---|---|
| 1 | Remove `AGENT_SESSION_TMP_ROOT` from `denyRead` | the per-tenant temp base becomes readable by B |
| 2 | Add a second persisted needle location under `$HOME` after a compliant first | each needle is checked, not the first hit |
| 3 | Delete the needle write in A's prompt | the CONTROL arm (needle visible at a named path on the host) must fail, so a zero-hit result is never green by silence |
| 4 | Start B's search before A has persisted (remove the persisted-marker wait) | the test must wait on the marker, not a timer |
**Harness rows.** RED: make the search target an empty directory and the test must report `not_exercisable`/vacuous. Must-PASS: a needle in B's own tmp (B can read its own) is found, a shape that is not the canonical sibling leak.
**Anchor.** Needle values are generated per run on the host and never stored in the deny list, so one diff cannot edit both sides.
### Guard 2 — tenant-deny alert path and coupling (PR 1b)
**Property.** A missing tenant deny root in production reaches a human, and every directory the CLI can derive from the env it is spawned with is covered by `denyRead`.
**Assembly.** Emit site, `sentry_alert` block, `alert-reference.json` key, discoverability script; and the helpers' env reads plus the config's `denyRead`.
**Mutation matrix.**
| # | Edit | Must go RED because |
|---|---|---|
| 1 | Change the first argument back to `new Error(...)` | the contract assertion requires `null` |
| 2 | Comment out the rule block | the discoverability script strips comments before matching |
| 3 | Add a second `reportSilentFallback` with another op literal after a compliant one | the assertion covers every emit |
| 4 | Make a helper read a new `env.NEWKEY` | the source scan finds a key outside the test's list |
**Harness rows.** RED: remove `enabled = true` from the rule. Must-PASS: the rule with reordered attributes and extra whitespace.
**Anchor.** `alert-reference.json` is checked independently by `scripts/sentry-alert-reference-gate.sh`; the allowlist is pinned by `agent-env.test.ts:40,156`.
Matrix rows are executed once at PR time unless a row is already a permanent assertion above; no permanent mutation-test framework is added.

## Test Scenarios
- A tenant prompt needle and tool-result needle persisted by the real CLI are absent from every path B can read, and the CONTROL arm proves each was written (Guard 1).
- Read/Grep/Glob at `$HOME/.claude/history.jsonl` and a symlink to it are refused by the hook.
- `NODE_ENV=production` with a missing volume root emits one tagged Sentry message with a `null` first argument.
- A helper reading a new env key breaks the coupling assertion.
- PR 2: a forced red `sdk_bash_smoke` in staging rolls back once; a red rollback target freezes deploys and pages; `smoke_infra_error` does not roll back.
- PR 3: a classified helper line renders the plain sentence; `ls: Permission denied` does not; the alert fires for each newly classified helper class.

## Acceptance Criteria
- [x] PR 1a: G2 ran (CI sets `C4_BWRAP_REQUIRED=1`, so the sandbox suite cannot silently skip there; local runs 2026-10-31 passed, ~96 s) and the prompt and tool-output classes each have a persisted host path proven by the real CLI, with zero sibling hits and a canary proving the search can find them. The exported-env class was cut: it is not independent of the tool-output class. The readable shared-HOME state is pinned (required members readable, nothing outside required + optional), A's recorded messaging socket path is not visible from the sibling's mount view, and no readable file holds a credential or marker. `history.jsonl`, `debug/`, `todos/`, `tasks/` are unmeasured; the production HOME was not inspected.
- [x] PR 1a: file-tool arm: `test/sandbox-hook.test.ts` refuses Read/Grep/Glob/LS/NotebookRead/NotebookEdit on shared-HOME paths by absolute path, literal `../` escape, leading `~`, prefix-sibling directory, a symlink file planted in the workspace, and an in-workspace decoy in one path field with the escaping path in another (the last two found real holes in the hook, fixed in `tool-path-checker.ts`/`sandbox.ts`, and each row fails on the old code). NOT covered: a symlinked DIRECTORY reached by a relative Glob pattern (the pattern check is syntactic), and Task/subagent matcher coverage. Both are recorded in the ADR-075 addendum.
- [ ] PR 1b: the `tenant-deny` emit passes `null` first; the Sentry rule, reference entry and contract assertion exist; `bash scripts/tenant-deny-alert-discoverability.sh` prints `TENANT_DENY_ALERT_PATH_OK`; the Sentry apply workflow succeeded on the merge commit.
- [ ] PR 1b: the coupling assertion passes and each Guard Contract row was shown to turn its guard red once.
- [ ] PR 1b: ADR-075 addendum and breach-register row added; breach-register row never says "no data affected".
- [ ] PR 2: flap review and `memory.peak`/`oom_kill` meet their numeric gates; `|| true` removed; one-rollback bound with freeze-and-page; `deploy_rolled_back_sdk_bash` exists before the old alert is deleted; staging forced-red run recorded.
- [ ] PR 3: classified helper failure shows the plain sentence with non-transient copy; raw text behind details; no swallowed command errors; alert fires per newly classified class.
- [ ] PR 4: per sandbox alert, either a test page was received in Slack, or an issue exists with an owner and a date.
- [ ] All PR bodies use `Ref #10455`, none use `Closes`.

## Review Disposition (plan-review panel, 2026-10-31)
Applied (mechanical): real-CLI measurement with before/after tree diff and CONTROL arm per needle; G2-skip AC; file-tool arm; stop rule for a red result; relocation design (`CLAUDE_CONFIG_DIR` under the tenant base, three open decisions); PR 1 split into 1a/1b; smoke tuple gets the new key before PR 2; PR 3 before PR 2; PR 2 rollback bound, numeric gates and replacement alert; non-transient copy and alert AC for PR 3; PR 4 AC; op-contract scoped to `reportSilentFallback`; free `frequency_minutes`; paths at repo root; Guard 2 and 3 merged into one; vitest for the new script, the dedicated coupling file and the shared key constant cut; records collapsed to one ADR addendum plus one breach-register row.
Surfaced to the operator (scope or irreversible): keep PR 4 as a PR slot versus fold into a tracker comment; the purge of already-persisted shared data.

## PR 1a Review Disposition (2026-10-31, 7 seats; missing by design for a test-only diff: performance, data integrity, agent-native, git history)
Applied: hook now judges every path field and refuses a leading `~` (security P1 x2, each new row fails on the old code); canary positive control for the sibling's marker search (test-design P1); realized reachability probe for A's socket path (architecture P1); pin relaxed to required + optional and uncapped in depth, `-a` instead of `-I` (test-design P2s); env marker cut as redundant with tool output, recording-only code cut (simplicity); relative-escape row made literal; prefix-sibling and positive-control rows; ADR-075 addendum and CLO records landed in this PR (architecture P2, user-impact P1); over-claims reworded (user-impact P1). Open, recorded in the ADR-075 addendum: a symlinked directory reached through a relative Glob pattern; Task/subagent hook coverage; the production-HOME census (operator-authorised).

## Scope Check
### Ask Mapping
| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "measure sibling-reachable persisted CLI output" [brief] | PR 1a Phase 1 / 1a / 1b | mapped |
| 2 | "fix the op=tenant-deny emit" [brief] | PR 1b Phase 2 | mapped |
| 3 | "derive deny set from agentEnv" [brief] | PR 1b Phase 3 | mapped — reframed as a coupling assertion, justification: the deny set is constant by design (Cut List) |
| 4 | "Plan covers PRs 1-4 sequenced per the brainstorm" [brief] | PR 2, PR 3, PR 4 | mapped |
| 5 | "a plain-language message when Bash fails" [request] | PR 3 | mapped |
| 6 | "verifying the Slack wake path for the new Better Stack alerts" [request] | PR 4 | mapped |
### Plan-Item Provenance
| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Breach-register row | — | inferred — justification: CLO housekeeping ruling from the brainstorm, one line |
| ADR-075 addendum | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; one addendum, no separate records |
| Flap review and `memory.peak` gates (PR 2) | — | inferred — justification: CTO ruling lists them as owed before promotion; now numeric |
| File-tool arm, relocation design (PR 1a) | — | inferred — justification: architecture review showed the measurement is incomplete without them |
### Split Assessment
- Subsystems touched (all PRs): 4 — `apps/web-platform/server`, `apps/web-platform/infra`, `apps/web-platform/test`, `knowledge-base`
- Planned files: ~12 across PRs | Estimated changed lines: ~500
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — five PR slots as above (1a, 1b, 3, 2, 4 in landing order).

## Sharp Edges
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this one carries the threshold.
- A measurement that plants its own needle measures the stub, not the CLI; accept only needles the real CLI persisted, proven by the CONTROL arm.
- `reportSilentFallback` with an `Error` first argument drops the tagged capture (#8629); every new emit uses `null`.
- Do not edit the deny list from the tracker's hand list of filenames; only paths named by the PR 1a measurement.
- PR 2 changes the rollback lane: do not merge without operator authorization.
