---
title: Hosted Bash asks before default-branch force-push and delete, terraform destroy and gh ref or repository delete, through one must-ask lane in canUseTool
status: adopting
date: 2026-10-10
supersedes: none
issue: 9776
related: [9601, 9776, 9603, 9388, 9825, 10054, 10111]
related_adrs: [ADR-022, ADR-027, ADR-093, ADR-113, ADR-264, ADR-277]
tags: [security, hosted, permission-callback, autonomous-mode, destructive-commands, review-gate]
brand_survival_threshold: single-user incident
---

# ADR-284: Hosted Bash asks before default-branch force-push and delete, terraform destroy and gh ref or repository delete, through one must-ask lane in canUseTool

## Status

**Adopting — 2026-10-10 (#9776); still adopting on 2026-10-12 (#10054): arrival of the lane's lines in the production sinks is NOT
OBSERVED, a member approval has never been observed, and the 24 h and 7 d soak numbers are not recorded. Revisit at the first
multi-member workspace or the first external founder (follow-up #10111).** The record flips to `accepted` through the `## Flip
checklist` below, in a later separate PR once the soak windows (re-timed from the fix deploy) close on 2026-10-13T08:40Z and
2026-10-19T08:40Z, and the numbers are recorded in the ADR-277 addendum (CPO3-R1 stays open until then). The ordinal is provisional: it was
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

> **Superseded 2026-11-01 (#10111):** the last clause above ("nothing in CI does") is no longer true for the files in the scheduled
> workflow's push filter: a non-blocking scheduled workflow now runs the probe for them and weekly (see "Amendment 2026-11-01 (#10111,
> Part 1)" below). It stays true of `ci.yml`: no required or PR-gating check runs the probe. The run is host-only, and a change outside
> the filter is caught only by the weekly run.

> **Superseded 2026-10-12 (#10054):** the C9 paragraph above says when the gate went inert "is **not measured**", that the start lies
> between 2026-05-05 and the SDK 0.3.284 bump, and that the 0.3.x line arriving with #5849 was "an untested candidate". Measured since:
> the SDK version is not the discriminator (the pre-fix tree is inert on every pinned SDK, 0.2.80 to 0.3.284), each cause alone
> suffices, #3252 is not evidence that the gate worked, and the start remains a window from code history, not a date. See the
> post-mortem's "Window" section for the table and commands.

**C9 result, measured limbs (2026-10-12, #10054).** The limbs the dev-hosted observation was meant to cover were exercised against the
deployed SDK, bundled CLI and option builder, on the DEV HOST (host bwrap, `NODE_ENV=test`), not in the hosted container. Probe source
is the file as committed in `8c1d17e8e7` (this PR, after the review round; the run used the working tree whose probe file is byte-identical to
that commit), run 2026-10-12T11:04:46Z. Deployed build: `/health` reported `build_sha` `edb74743f0` (version 0.338.32); the lane and sandbox
files are identical to the fix commit `dfb9e2dba5` (`git log dfb9e2dba5..origin/main` over the SDK pin, lockfile, sandbox config, sandbox
hook, option builder, permission callback and lane files is empty). An earlier identical run (10:06:01Z, build `0dc19ef389`) preceded the
review-round hardening of the probe's selection and PASS rules. Output, verbatim (no paths):

```text
PROVENANCE sdk=0.3.284 cli=2.1.284 node=v26.3.0 bun=1.4.3
PROBE force-push-default canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=1 approveRejectOptions=true cardOk=true neutral=true sentryAskEvents=1 sentryOk=true
PROBE terraform-destroy canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=1 approveRejectOptions=true cardOk=true neutral=true sentryAskEvents=1 sentryOk=true
PROBE bash-lc-variant canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=1 approveRejectOptions=true cardOk=true neutral=true sentryAskEvents=1 sentryOk=true
PROBE control-plain-push canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=0 approveRejectOptions=false cardOk=true neutral=true sentryAskEvents=0 sentryOk=true
PROBE member-force-push-default canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=1 approveRejectOptions=true cardOk=true neutral=true sentryAskEvents=1 sentryOk=true
PROBE grant-live-control canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=0 approveRejectOptions=false cardOk=true neutral=true sentryAskEvents=0 sentryOk=true cacheAllowsBeforeRun=true
PROBE grant-force-push-default canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=1 approveRejectOptions=true cardOk=true neutral=true sentryAskEvents=1 sentryOk=true cacheAllowsBeforeRun=false
PROBE gh-repo-delete canUseToolCalls=[Bash] verdict=ok bashAttempted=true gateCalls=1 approveRejectOptions=true cardOk=true neutral=true sentryAskEvents=1 sentryOk=true
PROBE remote-refs-unchanged=true
RESULT: PASS (sdk=0.3.284 cli=2.1.284, cases-run=8)
```

(Each `PROBE` line also carries `sdk=0.3.284 cli=2.1.284`; omitted here for width.) What it shows: the force-push, `terraform destroy`, the
`bash -lc` variant and `gh repo delete` each reach the Approve/Reject card for an owner, and the force-push does for a non-owner member
(the card does not name an owner); a stale batch grant (`git push`) is present and the force-push is still gated, while a live grant for
a simple command (`npm run probe-noop`) is honoured in the same wiring, so the grant limb is not vacuous (since #10072 the cache refuses
destroy-capable heads by construction, which is why `cacheAllowsBeforeRun=false` for the force-push); the control push reaches
`canUseTool` and is not asked; and the throwaway remote's default branch is unchanged. Emission is asserted in-process for each ask: one
Sentry event with `feature=cc-permissions`, `op=hosted-destroy-ask`, a `hosted-destroy-ask:` rule id, a family, `extra.isOwner` equal to the
variant, and an envelope with neither the command text nor a branch name; `PROBE_DECODE_ONLY=1` (real pino lines from the production
logger, wrapped in the stored shape, through the soak probe's own decode) printed `verdict=ok` and `RESULT: DECODE-COMPAT-OK` (the wrapper
is hand-built: it proves the decoder reads the real pino object, not that Vector produces this wrapper).

Probe self-checks (exact outcomes): the pre-fix tree on SDK 0.3.284 FAILS with `canUseToolCalls=[]` and `bashAttempted=true` (the harness
can go red, and it reproduces #10054); a grant that is not live aborts `CANT-RUN:grant-not-live` (exit 3, no SDK call); a dispatch that
selects nothing prints no `PROBE` line and exits 3; a model that does not use Bash exits 3; a member case wired with `isOwner:true` FAILS
(exit 1); a second case with a widened card fails while the first stays ok (exit 1); a different grantable command passes with no card;
`PROBE_ONLY` with a typo or with `sandbox-engaged-control` and no `PROBE_PREFLIGHT` exits 3 (`unknown-or-unavailable-case`, `no-case-selected`)
before any model call; a case table that disagrees with the name list is `case-table-drift` and a default matrix of fewer than 8 cases is
`case-count-below-floor`, both exit 3 and never PASS. These offline guards were exercised by hand in the review round and have no committed
suite row (see #10111).

**Telemetry readout (self-pulled 2026-10-12, counts only), window T0 2026-10-12T08:40Z to about 09:47Z (about 1 h 7 min).** Better Stack
source 2457081: `logs_retention` 90 days; the shipper's `app_container_warn_filter` keeps pino level 40 and above (the lane's lines are
WARN) and every non-JSON line; positive controls: 103 app-container WARN-and-above rows in the last hour (hot arm AT THE TIME of the read; that hour has since moved to the archive arm, and a re-read gives about 102), 1536 in a window
3 to 1 days old (archive arm; the archive's newest row lagged about 80 minutes, so the hot arm carries the recent window); lane lines from
the app container in the window: 0 (one non-app row quoting the marker, from the Inngest host's journald, is excluded by field
isolation). Sentry (org events, prd): `hosted-destroy-ask`, `destroy-classifier-error`, `destroy-classifier-near-miss` and
`safe-bash-near-miss` all 0 in the window; controls: 69 events of any kind since T0 (including the fix build and the three builds
deployed after it), 9,651 events aged 8 to 30 days, and 0 `hosted-destroy-ask` over 30 days. **Reading: 0 natural asks in the first
hour; arrival of the lane's pino line and Sentry event in the production sinks is NOT OBSERVED.** The channel is live, so the zero is a
measured zero, but at founder-only volume it says nothing about the lane itself.

**Proposed equivalence, pending operator ratification (CLO advisory, internal, not external counsel).** The "post-merge verification on dev
hosted" below cannot be run (there is no dev account and no deployed dev hosted instance). It is proposed to be replaced by two limbs:
(a) card behaviour, the real-SDK probe above on the deployed SDK, bundled CLI and option builder, run on the DEV HOST (host bwrap), not in
the hosted container, so the container sandbox (the variable behind #10054) is not exercised and a PASS is not a sandbox witness;
(b) production arrival, which is NOT OBSERVED and stays open until one production arrival is recorded, pulled by API, or the OPERATOR
records an explicit acceptance of in-process emission plus channel liveness as the substitute (Flip checklist criteria 4 and 6); an agent
never records that acceptance. Limb (a) may be closed by ratified decision, which does not make it a dev-hosted
observation. The claim "the ask gate is verified in production" must not appear anywhere: the strongest true sentence is "the real-SDK
probe passes against the deployed SDK, CLI and option builder on the dev host; production telemetry arrival is not yet observed."

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

  > **Updated 2026-10-12 (#10054):** the soak probe now (1) reads APP-CONTAINER rows only (a bare marker grep also returned 36 rows in
  > 24h, 57 in 7d, from the Inngest host's journald copies of webhook payloads that quote the marker, which tripped SHAPE_DRIFT every
  > sweep); an unclassifiable (undecodable) marker-mentioning row still counts toward SHAPE_DRIFT; (2) on zero asks requires a liveness
  > read over the same window and both Better Stack arms (one UNION count: any app-container WARN row, one in the last 3 hours, and for
  > 7d rows on at least 6 calendar days), else exit 3; (3) exits 5 on a trailing 7d read with zero asks on a live channel, pointing at
  > this ADR's Flip checklist. The sentence above that the probe "does not check the lane's liveness" is REFINED, not
  > superseded (it checks the CHANNEL's liveness, still not the lane's), and "does not exist before the lane ships" is superseded: the lane
  > has been live since 2026-10-12T08:38Z with no stored row yet (0 natural asks in the first hour; see the telemetry readout).
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

  > **Superseded 2026-10-12 (#10054):** there is no dev account and no deployed dev hosted instance, so this verification cannot be run as
  > written. See "C9 result, measured limbs" and the proposed equivalence above (pending operator ratification).

## Flip checklist

`status` stays `adopting` until every criterion below holds, then a separate small PR flips it. Criteria (CPO and CLO, 2026-10-12):

1. The real-SDK probe prints `RESULT: PASS` on the build then deployed (SDK, bundled CLI, `build_sha` and UTC time recorded verbatim, paths
   redacted), covering owner, non-owner member, a stale batch grant with a live-grant control and the destroy families, with the control push
   reaching `canUseTool` and not asked.
2. Emission is proven in-process (pino line fields; Sentry tags and extra, no command text) and the real line decodes in the soak probe.
3. The 24 h window shows no revert-threshold trip and the 7 d window no tune-threshold trip, recorded as counts from explicit
   [T0, T0+24h] and [T0, T0+7d] reads (the sweeper's trailing windows start at 18:00Z and are alarms, not the measurement), with any count
   under 5 written "under 5", including "0 natural asks; the soak did not exercise the lane" when that is the measurement. Natural
   false-positive and abandon rates are recorded as "unmeasured, n=0" and CPO3-R3 stays open.
4. The channel is proven live over the same windows (allowlist, retention, archive arm, positive control rows). If zero natural asks
   persist, arrival of the pino line and the Sentry event in the production sinks is recorded as NOT OBSERVED, and the OPERATOR decides
   whether in-process emission plus channel liveness is accepted as the substitute or a production write (a synthetic ask) is authorised.
   Without a recorded arrival or that recorded acceptance, limb (b) of the proposed equivalence stays open and the audit stays NOT
   DISCHARGED: `accepted` is then not reachable.
5. No SDK, bundled-CLI, sandbox-option, hook or option-builder change landed between the fix deploy and the flip (check `git log
   dfb9e2dba5..origin/main` over `apps/web-platform/package*.json`, `server/agent-runner-sandbox-config.ts`, `server/sandbox-hook.ts`,
   `server/agent-runner-query-options.ts`, `server/permission-callback.ts` and `server/destroy-ask-*.ts`); otherwise re-run the probe on
   that build and re-time both directives from that deploy. sdk-bump-sandbox-gate.sh does NOT enforce this (it demands a commit
   attestation on a lockfile SDK change and cannot see the other files), so this check is a human step.
   > **Superseded 2026-11-01 (#10111):** "so this check is a human step" is narrowed. A non-blocking scheduled workflow (see
   > "Amendment 2026-11-01 (#10111, Part 1)") now re-runs the probe on pushes that touch the files in its filter and weekly, so a change
   > inside the filter is no longer left to memory. The human check of this criterion remains for everything outside the filter, and a
   > scheduled PASS runs repo head on a CI host: it does not discharge this criterion without a `build_sha` match against the deployed build.
6. The OPERATOR ratifies limb (a) of the proposed equivalence in the flip PR (and, per criterion 4, records the acceptance of the
   substitute for limb (b) unless a production arrival has been recorded), and the counsel-review audit disposition is updated by the
   CLO agent in the same PR to record both decisions.

**An agent running this checklist stops at criteria 4 and 6.** They are the operator's decisions: leave the flip PR in DRAFT, state which
criterion is open, and ask; never treat "in-process emission plus channel liveness" as accepted on the operator's behalf.

Commands (agent-runnable): the deployed build is `curl -s https://app.soleur.ai/health | jq -r .build_sha`; the probe is
`NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-destroy-ask.ts` (require `RESULT: PASS ... cases-run=8`;
it prints `PROVENANCE` and `sdk=`/`cli=` on every line, and `cli=` is the SDK package's declared version; ADR-284 records it with the deployed
`build_sha` and the UTC time); the explicit windows are `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since
2026-10-12T08:40:00Z --until 2026-10-19T08:40:00Z --grep destroy-ask --limit 5000` decoded and isolated to `CONTAINER_NAME ==
"soleur-web-platform"` exactly as the soak script does (the 24h window ends 2026-10-13T08:40:00Z), plus the Sentry events by `op:` over the same
bounds with a release control.

The flip PR's own work: record the final counts in the ADR-277 addendum; set `status: accepted` in the frontmatter and in `## Status`;
sweep `knowledge-base/INDEX.md`, the ADR-277 addendum, the counsel-review audit, the post-mortem and `knowledge-base/legal/` for
future-tense sentences about the lane; retire the soak probe family together as its header says (`hosted-destroy-ask-window-9776.sh`,
`-24h.sh`, `-7d.sh`, the `.test.sh`, the `run_suite` row in `scripts/test-all.sh`, the matching rows in `scripts/suite-shard-legs.tsv` and
`scripts/suite-durations.tsv`, both tracker directives, and the `PROBE_DECODE_ONLY` mode of `dev-probe-destroy-ask.ts`, which execs the soak
script: remove the mode or repoint it); then `git grep -n 'hosted-destroy-ask-window-9776'` must return nothing outside
`knowledge-base/` history; close #9776 and #9976 by hand (`gh issue close 9776 9976`) and REMOVE their `follow-through` label
(`gh issue edit <n> --remove-label follow-through`) so the closed-set sweep stops re-running the probe. Retiring the soak probe leaves
nothing that detects a lane re-inerted by a later change: the follow-up that does is #10111 (a scheduled real-SDK probe on SDK bump and a
synthetic canary), and until it exists criterion 5 above is the only guard.

> **Superseded 2026-11-01 (#10111):** the closing clause ("until it exists criterion 5 above is the only guard") is narrowed. The
> non-blocking scheduled real-SDK probe (Part 1 of #10111, see "Amendment 2026-11-01 (#10111, Part 1)") now detects a lane re-inerted by a
> change to the files in its filter, host-only; criterion 5's human check remains the guard for everything outside that filter. The
> synthetic hosted-ask canary (#10111 Part 2) is not built.

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

## Addendum (2026-10-29, #4672)

The Context phrase "no new approval surface" and the lane's memory-less posture (it "writes no acknowledgement and no cache entry") describe the Bash must-ask lane and are unchanged for it.
A separate, flag-gated mechanism now gives eight gated platform tools a durable, single-use, action-bound approval request in the gated branch of `canUseTool`; it does not alter or extend this lane's
behaviour (the lane still writes no acknowledgement and no cache entry). It is not isolated from the lane: both use the shared `holdForUser` lifecycle and the per-session `pendingGates` budget (5 pending cards,
Bash and platform together), so a pending approval wait counts against the same budget as a pending Bash card. The rationale, invariants and residual risk are recorded once in [ADR-309](./ADR-309-durable-action-bound-approval-requests.md).

## Amendment 2026-11-01 (#10111, Part 1)

Status stays `adopting`. This amendment records the automation of the real-SDK probe (Part 1 of #10111). It does not touch Flip
criteria 4 and 6, it records no operator decision, and it does not say the hosted gate is verified anywhere beyond the CI host:
**the real-SDK probe passes against SDK 0.3.284 and the CLI version the SDK declares (cli=2.1.284 on the measured run; the repo pins
@anthropic-ai/claude-code 2.1.293 and no pathToClaudeCodeExecutable is set, so which binary the hosted query spawns is not shown by this
probe), through the repo-head option builder, on a CI host with host bwrap; production telemetry arrival is not yet observed.** A pass
says nothing about the hosted container sandbox (the variable behind #10054).

**What shipped.** A non-required, non-blocking workflow `.github/workflows/scheduled-real-sdk-ask-probe.yml` runs
`apps/web-platform/scripts/dev-probe-destroy-ask.ts` on a direct `ubuntu-latest` runner with the CI-partitioned `ANTHROPIC_API_KEY` repo
secret (the `soleur-ci-eval` workspace, ADR-244; never the production key). It is not in the required-checks ruleset and must not be added
(CTO 2026-10-12, reaffirmed 2026-11-01: a nondeterministic paid call does not gate pull requests). The runner script
`apps/web-platform/scripts/real-sdk-ask-probe.sh` owns the exit-code mapping, the rerun policy and the issue dedupe so they are testable offline.

**Triggers.** A push to `main` that touches one of the files below, a weekly cron (Monday 09:17 UTC), `workflow_dispatch`, and a
same-repo `pull_request` limited to edits of the workflow, the probe, the runner script and `probe-budget.ts` (the self-test run;
fork pull requests and the Dependabot actor are excluded). A push that changes only the two package files early-exits when neither
`@anthropic-ai/claude-agent-sdk` nor `@anthropic-ai/claude-code` moved since the newest run of the workflow on `main` whose probe step
actually executed and ended in success or failure (a billing-skipped run or a not-run push is never a baseline; an API error, no qualifying
run or an unreadable baseline means the probe runs).
The push filter (`on.push.paths`) is:

- `apps/web-platform/package.json`
- `apps/web-platform/package-lock.json`
- `apps/web-platform/server/agent-runner-sandbox-config.ts`
- `apps/web-platform/server/sandbox-hook.ts`
- `apps/web-platform/server/agent-runner-query-options.ts`
- `apps/web-platform/server/permission-callback.ts`
- `apps/web-platform/server/destroy-ask-classifier.ts`
- `apps/web-platform/server/destroy-ask-lane.ts`
- `apps/web-platform/server/agent-env.ts`
- `apps/web-platform/scripts/dev-probe-destroy-ask.ts`
- `apps/web-platform/scripts/real-sdk-ask-probe.sh`
- `apps/web-platform/scripts/lib/probe-budget.ts`
- `plugins/soleur/hooks/**`
- `.github/workflows/scheduled-real-sdk-ask-probe.yml`

The probe's static import closure is 189 files (measured 2026-11-01), too many to filter on at about 25 runs a month, so the filter is
a narrow allowlist guarded by a depth-1 coverage test (a classification table of the direct imports of the probe and of
`permission-callback.ts`). That test proves consistency between the filter and the table, not integrity; review and the weekly run are
the integrity layer.

**Cost caps (CTO F3, within the existing CI key and the $100/month workspace cap, ADR-244).** The model is the production default (no
override). The probe prints a measured `costUsd` per case and a `TOTAL costUsd=` line. Hard cap $4 per run (a per-case
`maxBudgetUsd` of the run budget divided by the case count, plus a cumulative stop; a rerun spends only the remaining share of the same
$4, never a second $4; the harness-only `maxBudgetUsd` never enters the production option builder). The cap is soft by at most one
in-flight turn: the SDK checks `maxBudgetUsd` between turns, so a case can overshoot by the cost of the turn that was running when the
budget was crossed; a case that ends in an error or abort, or without a result frame, is recorded against the cap at its full per-case
share rather than at zero. Monthly ceiling $25. Measured on the first self-test run (run 41295302456 at head 075832071a): 8 cases PASS,
`TOTAL costUsd=0.5762`, probe step 36 s, job 1 min 40 s. That supersedes the planning estimate of $1.5 per run and puts the $25 ceiling
at about 43 runs a month. The review panel counted 50 commits to `main` touching the allowlist in 30 days (about 39 probe runs), which
puts steady state near the ceiling in a busy month, so the $2.50-per-run trigger stays and a monthly-spend check against the workspace
spend view is the named review point. Review trigger $2.50: a first measured cost above $2.50 per run, or a projected or
trailing 30-day spend above $25, switches to the reduced shape: the push filter narrows to a move of the two SDK package versions plus
`agent-runner-sandbox-config.ts` and `sandbox-hook.ts`, and the weekly cron and `workflow_dispatch` are kept. The reported cost is the
SDK's own estimate (`total_cost_usd`, "an estimate, not a billing statement"); compare it with the workspace spend view.

**Outcome mapping.** The runner reports a pass only when the probe exited 0, printed `RESULT: PASS`, ran at least 8 cases, printed at
least 8 case lines and `PROBE remote-refs-unchanged=true`. A failing verdict (exit 1) files the p1 "regression" issue. A run that could
not measure (CANT-RUN, a diagnostic, a crash without a result line, `CANT-RUN:budget-exceeded`, a setup failure with no outcome) is
rerun once on the remaining budget where that is meaningful (never when the first pass's spend could not be read), then files the p2 "blind" issue; it is never a pass and never a failure.
A billing-cap skip (`anthropic-preflight`) prints SKIPPED and warns; it is not a pass. A push that the runner decides not to run reports
`not-run` and files nothing. Both issue classes are deduped by exact title.
A green run never closes the regression issue (it may add one "subsequently passed" note per open regression issue); a human closes it. The blind issue closes
itself on a later pass. Every issue body, the job summary and the workflow name carry the host-only residual and "production arrival not
observed".

**Residuals.**

- **No heartbeat (CTO F4).** A schedule that never fires, or a disabled workflow, is not detected. The criterion-5 human check at flip time is the backstop.
- **Nondeterminism.** The call is a live model call; a run where the model does not use Bash is CANT-RUN (blind), not a result about the lane.
- **Path-set miss.** A change outside the filter that re-inerts the lane is caught only by the next weekly run (up to 7 days) and by the human check of Flip criterion 5.
- **Self-test posture.** The `pull_request` self-test runs the same-repo pull-request-head tree, including its `server/**` import closure and its `npm ci --ignore-scripts` install, with the CI key in the probe step's environment (the same posture as the `ci.yml` real-turn gates). Fork pull requests and the Dependabot actor are excluded; the blast radius is the `soleur-ci-eval` workspace.
- **Host-only.** The probe runs with host bwrap on a GitHub-hosted runner, not in the hosted container.
- **A scheduled pass does not discharge a Flip criterion.** A scheduled run executes repo head on a CI host, so a pass never discharges Flip criterion 1 or 5 without a `build_sha` match against the deployed build. The workflow reads the repo secret where the documented command above uses Doppler `ci`.
- **First measurement is a PR self-test.** The only run observed is the PR self-test run 41295302456 at head 075832071a (cost above); no push or scheduled run had been observed when this amendment was written.
- **Skipped-run streak.** A billing, spend-cap or 5xx skip stays green with only a `::warning::` annotation (accepted, CTO F4). The weekly run bounds how long a streak can hide a lane re-inert, and a skipped run never becomes the push baseline.
- **A single flaky FAIL opens the p1 immediately.** A run that prints a failing verdict files the regression issue without a confirming rerun. This is the conservative choice and is recorded as a tradeoff: a false p1 costs a human triage, a swallowed real FAIL costs the guard.
- **Inactivity auto-disable.** GitHub disables scheduled workflows after 60 days without repository activity. Acknowledged and moot for this repository, which sees `main` activity far more often than every 60 days; the no-heartbeat residual above still applies.
- **Production call-site wiring is unobserved.** The probe injects its own `canUseTool` and option wiring; the production call sites (`cc-dispatcher`, `agent-runner`, `soleur-go-runner`) are not exercised, so a regression in how they build or pass options is invisible to it.
- **Depth.** Imports below depth 1 of the probe and of `permission-callback.ts` are covered only by the weekly run. The depth-1 coverage test classifies direct imports only.
- **New lane files.** A new `destroy-ask-*.ts` file is not selected by the push filter until it is declared in it and in the coverage table.
- **Filter edges.** Plugin-hook helper files outside `plugins/soleur/hooks/**`, and the `anthropic-preflight` composite action, are outside the filter.
- **Runner allowlist parity.** The runner's own `in_run_allowlist` (the package-only early-exit) is now parity-tested against the push filter in the workflow suite, so the two lists cannot drift apart silently.

**Re-evaluation verdict (#10111, recorded 2026-11-01).**

| Re-eval criterion | Criterion (any one) | Verdict |
|---|---|---|
| Re-eval criterion 1 | Any SDK, bundled-CLI or sandbox-option bump lands | **Fired** (sandbox-option, hook and option-builder class). Evidence: `git log --oneline dfb9e2dba5..origin/main` over `agent-runner-sandbox-config.ts`, `sandbox-hook.ts`, `agent-runner-query-options.ts` and `permission-callback.ts` lists commits including ba483a9948 (changes `sandbox-hook.ts` and `permission-callback.ts`) and 8e1d13797a (changes `permission-callback.ts`); the SDK pin (0.3.284) and the Claude Code package (2.1.293) are unchanged. `sdk-bump-sandbox-gate.sh` cannot see this class. Flip criterion 5 is therefore unmet on `origin/main` at this date: the probe has to be re-run on the current build, and this amendment records no result of that re-run. |
| Re-eval criterion 2 | First workspace with more than one active member uses autonomous mode | Not measurable from the repository; not claimed. |
| Re-eval criterion 3 | First external founder | Not measurable from the repository; not claimed. |
| Re-eval criterion 4 | 7-day soak closes with zero natural asks and no accepted substitute | Not demonstrably fired. The soak window closed 2026-10-19T08:40Z, this record is still `adopting`, and no soak numbers are recorded here. The substitute is an operator decision (Flip criterion 4) and stays untouched. |

Criterion 1 alone justifies Part 1. It does not touch Part 2.

**Part 2 (not built).** The synthetic hosted-ask canary (a production write that would observe arrival of the lane's pino line and
Sentry event in the production sinks) is NOT built. It lives in #10111 under an `Operator-reserved:` hold. This amendment ships nothing
that emits into a production sink and records no operator authorisation or acceptance.
