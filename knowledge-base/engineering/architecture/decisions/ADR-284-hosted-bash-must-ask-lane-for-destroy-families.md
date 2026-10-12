---
title: Hosted Bash asks before default-branch force-push and delete, terraform destroy and gh ref or repository delete, through one must-ask lane in canUseTool
status: adopting
date: 2026-10-10
supersedes: none
issue: 9776
related: [9601, 9776, 9603, 9388, 9825]
related_adrs: [ADR-022, ADR-027, ADR-093, ADR-113, ADR-264, ADR-277]
tags: [security, hosted, permission-callback, autonomous-mode, destructive-commands, review-gate]
brand_survival_threshold: single-user incident
---

# ADR-284: Hosted Bash asks before default-branch force-push and delete, terraform destroy and gh ref or repository delete, through one must-ask lane in canUseTool

## Status

**Adopting — 2026-10-10 (#9776).** The record flips to `accepted` when the post-merge verification below has passed on dev and the
24 h and 7 d soak numbers are recorded in the ADR-277 addendum (CPO3-R1 stays open until then). The ordinal is provisional: it was
re-derived over `refs/remotes/origin/*` on 2026-10-10 and 282 (sole-copy LUKS volume protection) and 283 (git-data liveness
heartbeat) were already claimed on sibling branches, so this record took 284. `soleur:ship` re-derives it again.

**This record does not say the hosted gate is complete.** It records a lane that asks on common spellings of a short list of
commands, the spellings it does not recognise, and the conditions under which it is reverted or widened (CLO C8).

## Context

<!-- lint-infra-ignore start: ADR context prose describes the hazard (what an unattended session could destroy), not a procedure anyone runs -->
A hosted session whose workspace has `bash_autonomous = true` (the default for new workspaces, migration 099) auto-approves every
Bash command that survives `BLOCKED_BASH_PATTERNS`, after a one-time owner acknowledgement. That blocklist does not match
`terraform destroy`, `git push -f` or `rm -rf`. The plugin hook that would ask (ADR-277) is switched off in hosted sessions (ADR-277
D8, `AGENT_ENV_OVERRIDES`), and ADR-277's CPO third pass rated the resulting exposure a single-user incident: a founder's
autonomous session can erase the default branch's history on GitHub or tear down their infrastructure with no card shown, while the
product says their work is backed up.
<!-- lint-infra-ignore end -->

Three further facts shaped the design (all verified against `origin/main` at base):

1. `deriveBashCommandPrefix` maps a command whose second word is `push` to the prefix `git push` and a terraform command to its first
   token `terraform`, so a prior "Approve all" grant already auto-approves `git push --force origin main` and `terraform destroy`,
   in non-autonomous mode too.
2. A plugin-hook `ask` is delivered to the SDK permission flow, which then calls `canUseTool`; `canUseTool` returns `allow` for
   `autonomous-bypass`. A hook-only fix is therefore a no-op under autonomy unless `canUseTool` also reads the hook's reason.
3. The hosted agent holds `gh` and an unscoped GitHub App installation token as `GH_TOKEN` (`administration: write`;
   `api.github.com` is an entitled egress domain), so `gh api -X DELETE .../git/refs/heads/<default>` and `gh repo delete` are the same
   harm and are reachable (CPO4-R4).

## Considered Options

- **Option A — one must-ask lane inside the hosted `canUseTool`, backed by a pure TypeScript classifier (chosen).** Pros: the
  `review_gate` WebSocket surface is the proven production gate; no new approval surface; the lane sits above the bypass, the hold
  and the cache, so none of them can stand in for the Approve; fails toward ask. Cons: a second implementation of the D1 set beside the
  plugin hook (bound by a corpus and a parity test, below).
- **Option B — enable the plugin hook in hosted sessions.** Rejected for now. Structurally a no-op under autonomy (fact 2), so it needs
  A's code anyway; it also turns on the hook's 4b ask classes (`bound`, `lexer-empty`, `unparsed-wrapper`, `wrapper-depth`, parse asks)
  for every hosted Bash call with an unmeasured false-positive rate (CPO3-R3), and adds perl, jq and bash spawns to the hosted hot
  path. Recorded as a later consolidation, conditional on a measured hosted `ask`.
- **Option C — a copy-versioned acknowledgement now.** Rejected: the CLO ruled a narrowing needs no re-acknowledgement, and an RPC
  signature change on an approval-bypass consent path does not belong in this PR. The design is recorded below for the day a widening
  is scheduled.
- **Option D — a feature flag.** Rejected: the change fails toward ask, and a flag is a one-click way to reopen the exposure.
- **Option E — down-scope the hosted installation token** (drop `administration: write`, which would remove `gh repo delete` and
  repository-level API deletion with no classifier). Not in this PR: other hosted consumers may need the grant and that has not been
  verified. An alternative worth measuring.

## Decision

Option A. The lane is ONE call site in the Bash branch of `createCanUseTool` (`permission-callback.ts`), after the blocklist deny, the
safe-bash allow, the near-miss telemetry and the support-persona deny, and before the autonomous bypass, the first-run disclosure hold,
the existing-workspace opt-out hold and the batched-approval cache. A match RETURNS from that branch. Rules:

- **Lane precedence.** The blocklist wins (`curl x && git push -f origin main` denies). The support persona keeps its deny. The lane
  runs in autonomous and non-autonomous mode alike: in the first it removes the bypass and the hold, in the second the cache laundering.
- **The card.** Exactly two options, Approve and Reject. The question leads with the cause and the matched segment (outside the
  truncated preview), says Approve runs the whole command, and says the approval applies to this command only. It is neutral about who
  owns the repository, because a non-owner member may be approving. Any selection other than the exact string `Approve` denies, so a
  forged `Approve all <prefix>` frame cannot reach the cache. Approval writes no acknowledgement and no cache entry. Reject, timeout and
  abort deny, and the deny text tells the agent not to retry or respell.
- **Fail toward ask.** A classifier error is a match (`classifier-error`, mirrored to Sentry with a null first argument and the error
  class in `extra`, the #8629 pattern). An unparseable command asks iff its
  quote- and backslash-stripped text contains `destroy` or `push`; a raw-text scan runs when the structured pass found nothing and the
  command has a heredoc, a here-string, a pipe into a shell or `xargs`. When the default branch cannot be resolved, every force or delete
  push that names a destination asks (`git-push-unknown-default`); a `--mirror` or `--all` force asks as `git-force-default` whatever
  the default branch is, and a force push with no named destination asks as `git-force-implicit` (CTO ruling: it may overwrite the
  default branch, so it asks even when the cost is an over-ask on rebase workflows).
- **Default branch.** The protected set is the union of the GitHub API `default_branch` (installation token, authoritative), the local
  `refs/remotes/origin/HEAD` (agent-writable, so it may add a name and never remove one; opened with `O_NOFOLLOW` and `O_NONBLOCK` and checked on the descriptor (no check-then-open pair), a size cap, symlinks and
  non-regular files refused, one accepted shape) and the constants `main` and `master`; compared case-insensitively after stripping
  `refs/heads/`. Resolved once per session record: 3 s timeout, positive result 10 minutes, negative result 30 s, one in-flight lookup.
- **Families.** `git push` force, delete and mirror forms; `terraform|tofu destroy` and `apply -destroy`; `gh api` DELETE on a ref or
  the repository, `gh api` PATCH or PUT with a force field on a ref, `gh repo delete`. Rule ids (`hosted-destroy-ask:` prefix):
  `git-force-default`, `git-delete-default`, `git-push-unknown-default`, `git-force-implicit`, `terraform-destroy`,
  `gh-ref-delete-default`, `gh-repo-delete`, `fail-closed-keyword`, `raw-scan`, `classifier-error`.
- **For the git and terraform rules the classifier is a superset of the plugin hook's D1 set,** enforced by
  `destroy-ask-hook-parity.test.ts`, which runs the real hook with the kill switch unset over the stored corpus. Every ask the
  classifier gives that the hook does not (`--mirror`, an unresolved or API-resolved default, implicit destinations, brace and
  parameter-expansion destinations, `find -exec`, the raw scan, the `gh` family, `TF_CLI_ARGS`) carries a `hostedOnly` note. The
  hook's recursive-`rm` rows are outside this lane (a residual below) and carry a `parityExempt` note: the superset claim does not
  extend to them.
- **Second consumer.** The lane is a function list (`MUST_ASK_CLASSIFIERS`, one member today); ADR-264 (#9388) adds its must-ask
  class as the second member.
- **Deviation from the plan's wording: the lane returns early.** A match returns from the Bash branch instead of falling through to
  the generic gate, so that the autonomous bypass, the disclosure holds and the batch cache cannot stand in for the Approve; the
  generic gate's own approval handling is not reused.
- **No feature flag, no migration, no acknowledgement reset, no `TC_VERSION` change.** Rollback is `git revert` of the one commit
  unit (the copy and the lane revert together: the banner's assurance must never outlive the lane, CLO C1).

### Coverage by conversation type

| Conversation type | Lane applies | How it is asserted |
|---|---|---|
| cc-routed Concierge (`cc-dispatcher.ts`) | Yes | `permission-callback-destroy-ask.test.ts`; the factory-wiring test in `cc-dispatcher-real-factory.test.ts` |
| Legacy domain-leader runner (`agent-runner.ts`) | By design every non-safe Bash command reaches the generic gate (no `bashAutonomous`, no batch cache, no resolver); a destroy form gets the destroy card with the resolver unresolved. In production this took effect only with #10054: before it the SDK never called `canUseTool` for sandboxed Bash, so domain leaders ran Bash unprompted | `permission-callback-destroy-ask-error.test.ts` pins the call site |
| Support persona | Denied (with escalation) before the lane; no gate emitted | the lane suite's support row |
| Scheduled and Inngest agents | Outside `canUseTool`; the plugin hook is active there (ADR-277, "Server-side scheduled agents") | not asserted here |

### Runtime proof

The factory-wiring test proves the real `createCanUseTool` sits in the same SDK options object as the sandbox that carries
`autoAllowBashIfSandboxed`, that `permissions.allow` stays empty and that a destroy command reaches the review gate in an acked
autonomous workspace. **It does not prove that the real SDK calls `canUseTool` for sandboxed Bash:** the SDK is
mocked. The runtime proof is the real-SDK probe `apps/web-platform/scripts/dev-probe-destroy-ask.ts` (CLO C9).

**C9 result (2026-10-11, #10054).** Against the hosted path's real stack (SDK 0.3.284 and the Claude Code 2.1.284 binary bundled
in `@anthropic-ai/claude-agent-sdk-linux-x64`; the hosted path sets no `pathToClaudeCodeExecutable`, so the 2.1.293 copy the crons spawn
is not what it runs) and the production option builder, the probe **failed** at #9977: `canUseTool` was never called for sandboxed
Bash, so this lane, the safe-Bash allowlist, the autonomous toggle gate and the batch cache were all inert. When that began is
**not measured**: #3252 (closed 2026-05-05) shows Command Center Bash prompting on SDK 0.2.85 with both causes below already in the
code, so the start lies between 2026-05-05 and the SDK 0.3.284 bump (#9236, merged 2026-09-29); the 0.3.x line arrived with #5849 on
2026-07-01, an untested candidate. Two independent causes, either enough: `autoAllowBashIfSandboxed: true`, and the PreToolUse sandbox
hook returning an explicit `allow` for every Bash command (a hook allow resolves the permission before `canUseTool`). The forward fix
sets `autoAllowBashIfSandboxed: false` (the sandbox stays on) and makes the hook return no decision for Bash (`{ continue: true }`;
the sensitive-env deny stays). After the fix the same probe passes: the force-push to the default branch, `terraform destroy` and a
`bash -lc` variant each reach the Approve/Reject card and, answered Reject, leave the remote's default branch unchanged (the probe's
local `main` is made to diverge from the remote's, so a force-push that ran would move it); a plain push to a feature branch is not asked.

Consequences of Bash reaching `createCanUseTool` again, all of them the callback working as written:

- A non-autonomous workspace shows an Approve card for every command outside the safe allowlist; an unanswered card expires after
  5 minutes into a deny whose text tells the agent the command did not run and not to retry or respell it.
- `BLOCKED_BASH_PATTERNS` (curl, wget, nc, `sh -c`, sudo, eval) is live again for hosted Bash, including autonomous workspaces, so a
  plugin skill that relied on `curl` is denied.
- "Approve all `<prefix>`" now grants one simple command only: it is not offered for, and not honoured against, a compound command
  or a destroy-capable head (shells and interpreters, `rm`, infra CLIs, `git push` and the other state-rewriting git verbs), because
  a grant would turn any spelling the lane does not recognise into a silent run.
- Stacked cards (parallel Bash calls) keep the conversation `waiting_for_user` until the last one resolves.
- The hook still returns `allow` for the file tools, so their `canUseTool` branch is not reached; that is unchanged here and is a
  residual (the file-path deny lives in the hook and `disallowedTools`).
- A headless session with no connected client waits out the 5-minute gate and then denies; there is no strand.

Re-run the probe (`apps/web-platform/scripts/dev-probe-destroy-ask.ts`) after any SDK, CLI or sandbox-option bump: it is the only
check that exercises hook-then-`canUseTool` precedence against the real binary; nothing in CI does.

### Residuals (not recognised; named so the copy and the control page never imply otherwise)

Variable-built command names; aliases, including `git config alias.x '!git push -f'` and `git config remote.origin.push +HEAD:main`
followed by a plain push; `make`, `npm run` and script indirection, including Write then `bash ./x.sh`; `terragrunt` and `pulumi
destroy`; `git update-ref`; recursive `rm`; force-push to a non-default branch; deleting or force-moving a tag, and deleting a
branch-protection rule through the API; `gh repo sync --force`; an interpreter that runs git itself (`python -c`, `node -e`) where the
blocklist has no entry; a default branch that differs per remote; a destination hidden in a nested `${…:-$(…)}` substitution; GraphQL `deleteRef`, `deleteRepository` and `updateRef`
through `gh api graphql` (near-miss telemetry only; widening goes back to the CPO, CPO4-R1); other `gh ... delete` forms (near-miss
only); a plain `terraform apply` of a destroy plan; and **owner-only approval**: a non-owner member of the workspace can approve a card
(the same as every other gate today; the outcome line carries `approverRole` so the soak probe reports member approvals). Revisit
trigger for the last: the first workspace with more than one active member using autonomous mode. The default-branch lookup is a read
of the repository through the installation token and is not itself audited.

## Consequences

- **Easier.** A hosted autonomous session cannot run the recognised destroy forms without a per-command Approve; a prior `git push` or
  `terraform` batch grant no longer covers them, in autonomous and non-autonomous mode alike (disclosed in the PR body and the
  changelog, CPO4-R6). The hook consolidation later is a measured swap (the corpus and the parity test already bind the two).
- **Harder.** Two implementations of the D1 set exist until the consolidation; the corpus is the specification and changes to it are
  reviewed as such. A force-push to a feature branch asks when the default branch could not be resolved, and a force push with no
  named destination always asks (a rebase-and-force-push workflow meets the card on every push; the soak probe reports this share).
- **Reverting inside the soak window.** A revert removes the lane, and the copy with it. Acknowledgements written while the copy was
  live remain valid for the narrower claim they acknowledged, so the revert runbook supersedes (not edits) any acknowledgement row
  written during the window, as the C2 supersede step of PR #9792 does, before the copy is restored.
- **Revert and tune thresholds (CPO4-R5; the soak probe `scripts/followthroughs/hosted-destroy-ask-window-9776.sh` evaluates them).**
  Revert (not tune) if, in the first 24 h, any one rule id accounts for more than 25 percent of one workspace's hosted Bash calls with
  at least 20 hosted Bash calls from that workspace in the window (a floor, so one call in four is not a storm), or
  `destroy-classifier-error` is non-zero without a fix inside 24 h. Tune (do not revert) if `git-push-unknown-default` is more than 10
  percent of asks over 7 days (the default-branch lookup is then the defect) or the `fail-closed-keyword` plus `raw-scan` share of
  asks is more than 25 percent.
  **Measurability, stated plainly.** The ruled storm metric is a share of one workspace's hosted Bash CALLS. The per-call lines
  (`autonomous-bypass`, `user-approved`) are pino INFO and the app-container shipper keeps WARN and above only, so that denominator is
  not in the stored telemetry. The probe therefore measures a stand-in: the share of ONE REPO's asks that one rule accounts for, behind
  a floor of 20 asks in the window, evaluated for every repo that reaches the floor. It is a tripwire for "one rule is the whole ask
  stream", not the ruled metric, and the ruled metric is not measured anywhere (the Sentry events are capped per context, so they do
  not stand in for it). The probe also does not check the lane's liveness: a lane that stopped emitting reads as a quiet window, and
  the dev probe below is the liveness check. It exits 3 on an unparseable or truncated result and on outcome lines with no matching
  ask lines, and it reports the `git-force-implicit` share and the member approvals. The lane's own ask and outcome lines
  (`destroy-ask`, `destroy-ask-approved`, `destroy-ask-rejected`, `destroy-ask-expired`) are emitted at WARN so they ship; near-miss
  events are Sentry-only. The probe's decode of the stored shape was measured on live app-container rows (a pino WARN line is stored
  as `raw` = a JSON string whose `.message` is the pino object) but could not be measured on a `destroy-ask` row, which does not
  exist before the lane ships.
- **Widening trigger for a versioned acknowledgement (CPO4-R8).** Any change that widens what hosted autonomous mode may do without
  asking (relaxing the lane, adding a flag that bypasses it, enabling the hook's weaker modes) first requires the versioned
  acknowledgement. Smallest design, recorded so it is not re-litigated: one nullable `autonomous_disclosure_ack_version smallint` on
  `workspaces`, NULL read as v1 inside `get_workspace_autonomous_ack` (existing acknowledgements are grandfathered with no UPDATE);
  `set_workspace_autonomous_ack` becomes `(p_workspace_id uuid, p_version smallint DEFAULT NULL)` so the old build's one-argument call
  still resolves during the migrate-before-swap window; semantics are "minimum acceptable consent version", never "current copy
  version"; a stored version below the required minimum is treated exactly as a NULL acknowledgement (HOLD plus banner).
- **Legal.** The AUP 5.7 and T&C 3a.7 parenthetical "(and at the date of this version it does not)" goes stale in the user-favourable
  direction. It is deliberately not edited here (a Tier 2 T&C change forces every user to re-accept Terms). Revise it at the earliest of
  the next `TC_VERSION` bump, publication of #9603's hosted-coverage claim, the first arms-length workspace owner, or 2027-01-08; the
  verbatim replacement is in the CLO ruling and the tracking issue.
- **Post-merge verification (no destructive probe in prod).** On dev hosted with a throwaway repo and an acked autonomous workspace:
  `git push --force origin <default>`, `terraform destroy` and one `bash -lc` variant each produce the card, a pino
  `decision:"destroy-ask"` line and a Sentry `hosted-destroy-ask` event with the rule id and no command text; a non-owner member
  session gets the same card; a pre-granted `git push` batch grant is still gated; a plain `git push origin feat-x` shows no card.
  Data is pulled by API, never by dashboard.

## Cost Impacts

None. No new vendor, no infrastructure change; at most 32 `hosted-destroy-ask` and 32 near-miss Sentry events per conversation
context, plus the `destroy-classifier-error` and `default-branch-resolve` events, which are not capped per context (the resolver
bounds the second to one per 30 s per session record after a failure; a classifier error is a defect and should be rare). One
GitHub API read per session record, only on a force or delete push.

## NFR Impacts

None moved. Related: NFR-014 and the audit-logging posture are unchanged (telemetry is logs and Sentry only, zero database writes).

## Principle Alignment

- AP-020 (Untrusted input at the agent boundary): Aligned. The command is model-controlled input; the classifier is pure, bounded in
  size and depth, and fails toward ask on anything it cannot read. The local `origin/HEAD` is agent-writable and may only add names.
- AP-021 (Diagnostic honesty): Aligned. The card and the copy name only what the lane matched and what it does not recognise; the
  vocabulary guard test bans "blocks", "prevents", "protects", "safe to approve", "guaranteed" and "always" in reference to the lane.
- AP-023 (Anti-vacuity floors report directly): Aligned. The corpus, parity and mutation suites carry literal floors reported by
  `printf` and `exit`, not through the helpers they back-stop.
