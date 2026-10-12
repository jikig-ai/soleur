---
title: "Hosted Bash approval prompts did not appear (SDK auto-allow pre-empted canUseTool)"
date: 2026-10-11
incident_pr: 10072
incident_window: "start not measured (earliest dated code candidates 2026-03-20 legacy runner and 2026-04-27 Command Center); the pre-fix tree is inert under every SDK version it was run with (0.2.80 to 0.3.284); the 0.3.284 build was in production from 2026-09-30T00:11Z; ended 2026-10-12T08:38:33Z"
recovery_at: "2026-10-12T08:38:33Z"
suspected_change: "autoAllowBashIfSandboxed true and the PreToolUse sandbox hook returning allow for Bash (each alone sufficient); the SDK version is not the discriminator"
brand_survival_threshold: single-user incident
status: fix-deployed-notice-and-register-decisions-pending
triggers:
  - real-SDK probe (CLO C9) failed against the shipped must-ask lane
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a - no personal-data compromise indicated; availability of an approval control, not exposure of data"
---

# Hosted Bash approval prompts did not appear (SDK auto-allow pre-empted `canUseTool`) — 2026-10-11

Tracking: #10054 (P0). Detected by the real-SDK C9 probe of ADR-284 after #9977 shipped. Fixed on `feat-9776-c9-dev-probe`; deployed 2026-10-12 (deploy job finished 08:38:33Z, run 38223902738).

## What happened

In hosted workspaces the Claude Agent SDK never called `canUseTool` for sandboxed Bash. Two independent causes, each enough on its own:

1. `autoAllowBashIfSandboxed: true` (`server/agent-runner-sandbox-config.ts`) auto-allows a sandboxed Bash call before the callback.
2. The PreToolUse sandbox hook (`server/sandbox-hook.ts`) returned an explicit `allow` for every Bash command; a hook allow resolves the permission before `canUseTool`.

Everything in the Bash section of `createCanUseTool` was therefore inert: the safe-Bash allowlist, the #9977 must-ask lane (default-branch force-push/delete, `terraform destroy`, `gh` ref/repo delete), the autonomous-mode toggle's gate and the batch-approval cache. The sandbox, the blocklist and the GitHub token scope were the remaining controls.

## Window (measured bounds; the start is not measured)

- Start not measured; the SDK version is not the discriminator. The real-SDK probe, run on the pre-fix tree (commit c982f61b5a) (`dfb9e2dba5^`) under each SDK version the repo pinned for production from 2026-03-27 (0.2.80, 0.2.85, 0.3.197, 0.3.284), two runs each with the sandbox-engaged control passing every time, never saw `canUseTool` called for sandboxed Bash. 0.2.80 and 0.2.85 had to run on claude-sonnet-4-5 because their CLIs reject the current default model (API 400), and the older versions were substituted into the pre-fix tree, not run as the builds that were live then. That tree already carries the hook's explicit `allow` (added 2026-04-15), which production lacked before that date, so the 0.2.80 row (production from 2026-03-27 to 2026-04-15) does not measure that era's production tree: for that era only cause 1 was present and it was measured alone only on 0.2.85 and 0.3.284. An earlier pin also existed: `^0.2.76` from 2026-03-18 (then `^0.2.80` on 2026-03-20) until the exact 0.2.80 pin of 2026-03-27 (#1182); it was never run, so the 2026-03-20 candidate falls in an era no probe covers. The earlier hypothesis that the 0.3.x bump caused it is refuted. Each cause alone suffices: with the PreToolUse hook removed (`autoAllowBashIfSandboxed: true` alone) the gate is inert on 0.2.85 and 0.3.284; with `autoAllowBashIfSandboxed: false` and the hook's explicit allow kept it is inert on 0.3.284 (inconclusive once on 0.2.85, where the model did not try Bash). The start therefore rests on code history, not measurement. `autoAllowBashIfSandboxed: true` first appears 2026-03-20 (#871, legacy runner; its first release run failed, so its deploy time is later and unmeasured). The hook's explicit allow for Bash arrived 2026-04-15 (#2284, deployed 12:40Z, same commit as the SDK 0.2.85 bump). The Command Center dispatcher bound the same sandbox config on 2026-04-27 (#2901, deployed 08:35Z; before that it made no real SDK calls), so 2026-03-20 governs the legacy agent-runner only and 2026-04-27 the Command Center path. One observation contradicts the inference and is unreconciled: #3252 (created and closed 2026-05-05) reported Command Center Bash prompting on `ls` and `pwd` while both causes were in the code, and its fix (#3277, merged the same day) changed the safe-Bash allowlist INSIDE `canUseTool`, i.e. the callback was reached for at least some read-only Bash that day. Possible explanations, none verified: the sandbox was not engaged in production that day (the auto-allow applies only when sandboxed), or a different surface. It is not evidence that the gate worked, and it contradicts the measured "never called" for that day; it stays unreconciled. We record a window, not a start date: the earliest dated candidate is 2026-03-20, inert is measured only on the pre-fix tree with SDK 0.3.284 substituted, on a developer host, not on the production build (the 0.3.284 build was in production from the first successful deploy of a build carrying it, 2026-09-30T00:11:12Z; the merge's own release runs skipped or failed their deploy), and it ended at the fix deploy on 2026-10-12 (deploy job finished 08:38:33Z).

  > **Superseded 2026-10-12 (#10054):** the bullet that stood here said the start lay between 2026-05-05 and the SDK 0.3.284 bump (#9236, merged 2026-09-29T22:02Z), that #3252 showed the gate working on SDK 0.2.85, and that the 0.3.x line arriving with #5849 on 2026-07-01 was an untested candidate. The probe measurement above refutes the SDK-version reading and #3252 is not evidence that the gate worked.

  | SDK (SDK-declared CLI version) | Pinned in production | Pre-fix tree, `PROBE_ONLY=force-push-default`, 2 runs each |
  |---|---|---|
  | 0.2.80 (2.1.80) | 2026-03-27 (#1182) | inert, inert (model claude-sonnet-4-5) |
  | 0.2.85 (2.1.85) | 2026-04-15 (#2284), deployed 12:40Z | inert, inert (model claude-sonnet-4-5); default model rejected, API 400 |
  | 0.3.197 (2.1.197) | 2026-07-01 (#5849), deployed 13:35Z | inert, inert |
  | 0.3.284 (2.1.284) | 2026-09-29 (#9236), first successful deploy 2026-09-30T00:11Z | inert, inert; control for the harness |

  No release-level (Tier 2) bisect was run: there is no measured boundary between adjacent pins to bisect, because every pin is inert.
  Copyable bisect commands (a scratch worktree of the pre-fix commit; the feature worktree's lockfile is never touched, and
  `sdk-bump-sandbox-gate.sh` would otherwise demand an acknowledgement):

  ```bash
  git worktree add --detach "$S/prefix" dfb9e2dba5^                      # PRE-FIX tree
  cp apps/web-platform/scripts/dev-probe-destroy-ask.ts "$S/prefix/apps/web-platform/scripts/"
  (cd "$S/prefix/apps/web-platform" && npm ci)
  # per SDK version V, inside the scratch tree only:
  npm install --no-save --no-package-lock --ignore-scripts @anthropic-ai/claude-agent-sdk@"$V"
  # verdict is read from the verdict= and canUseToolCalls= fields of the PROBE lines (a PROBE_ONLY run exits 4 when its cases are ok and 1 when a case FAILs, as on the pre-fix tree):
  PROBE_PREFLIGHT=1 PROBE_ONLY=sandbox-engaged-control,force-push-default NODE_ENV=test \
    doppler run -p soleur -c ci -- bun run scripts/dev-probe-destroy-ask.ts
  # 0.2.x CLIs reject the default model: a scratch-only edit passes `model: process.env.PROBE_MODEL` to the option builder.
  # single-cause diagnostics: PROBE_NOHOOK=1 PROBE_UNSAFE=1 (autoAllow alone), PROBE_SANDBOX=noauto (hook allow alone)
  ```

- The user-facing copy claiming an ask for destroy-family commands shipped with #9977 (merged 2026-10-11T10:25Z). The older line "with
  it off, it asks before every command" (from #4949, 2026-06-04) was false for as long as the gate was inert, and workspaces that chose
  "Ask me each time" also saw commands run without a prompt in that period.
- Still in force throughout: the sandbox (filesystem and network allowlists) and the GitHub token scope. NOT in force: every Bash check inside
  `canUseTool`, which includes the `BLOCKED_BASH_PATTERNS` blocklist (curl, wget, `sh -c`, sudo, eval) as well as the approval prompts.

  > **Superseded 2026-10-12 (#10054):** the "still in force throughout" assurance for the sandbox and the GitHub token scope has no production
  > evidence behind it: no in-container check was run, and the only supporting datum is a sandbox-engaged control on a developer host. It is
  > not verified in production and the user notice no longer asserts it.
- Terms: AUP 5.7 and T&C 3a.7 do not promise an ask. T&C 3a.7 does say Soleur "always blocks a fixed set of clearly-dangerous commands", and that blocklist lives in `canUseTool`, so it was not in force for hosted Bash while the gate was inert. Whether that sentence needs a correction is a legal decision for the operator (CLO), not edited here.

## Gap in what we can say

Hosted `autonomous-bypass` lines are INFO and are not shipped to a queryable sink, so we cannot enumerate from telemetry whether any hosted destroy-family command ran in the window. The only record is each user's own repository history and infrastructure state.

## Fix

`autoAllowBashIfSandboxed: false` (sandbox stays on) and the hook returns `{ continue: true }` (no decision) for Bash; the sensitive-env deny is unchanged. The real-SDK probe (`apps/web-platform/scripts/dev-probe-destroy-ask.ts`) passes: three destroy forms reach the Approve/Reject card and leave the default branch unchanged; the control push reaches `canUseTool` and is not asked. The three user-facing Bash gates (review card, first-run disclosure, opt-out) now share one hold helper that fails closed on expiry and keeps the conversation status correct for stacked cards; they were unreachable code until now.

## Draft user notice (operator publishes; not published by the agent; no bracketed dates remain, but the operator still decides whether, when and to whom)

> Soleur's hosted Concierge is meant to ask for your approval in two ways. First, before a default-branch force-push, `terraform destroy` or
> repository deletion. Second, before commands when you choose "Ask me each time", alongside a fixed blocklist of clearly dangerous commands
> (curl, wget, `sh -c`, sudo, eval).
>
> **What went wrong.** A fault in how hosted workspaces handled shell commands meant these checks were never run. In our tests, commands ran
> inside the sandbox with no approval prompt and no blocklist check. The fault ended when the fix finished deploying on 12 October 2026 at
> 08:38 UTC.
>
> **Which checks, and since when.** The prompts before force-push, `terraform destroy` and repository deletion were added in code merged on
> 11 October 2026. They did not work until the fix the next day. The "Ask me each time" prompts and the blocklist are older. Our code history
> shows the same fault was possible from 20 March 2026 (earlier agent runner) and from 27 April 2026 (Command Center). The "Ask me each time"
> setting itself was offered to users from 4 June 2026. We could not establish a start date, and we have not established that the checks were
> inactive throughout.
>
> **How we know.** We tested the code as it stood immediately before the fix, on a developer machine. We substituted each of the four Claude
> Agent SDK versions the product used from 27 March to 30 September 2026. No approval prompt appeared in any run. The March period before 27
> March was not tested. This is a test, not a record of what ran in production, and our logs cannot tell us whether any particular command ran
> in your workspace.
>
> **Where the fix stands.** The fix is deployed. In our test with the deployed SDK, the three destructive commands stop for your approval. We
> are still confirming this from live production use. We have not verified other safeguards inside production for this notice, so we say
> nothing about them here.
>
> **What you can do.** If you relied on these prompts, review your repository's push and branch-deletion history (GitHub repository Activity,
> or `git reflog` on any clone) and your infrastructure state from 20 March 2026 onward. Tell us if anything unexpected happened.

Wording by the CLO agent (2026-10-12, internal advisory, not external counsel); it replaces the earlier draft after the review round found
three problems (a testing claim about "the code in service from 30 September", an unqualified "restored", and a destroy-family claim that
predated the feature). Do not claim: a single start date; that the SDK bump caused it; that the gate worked on 5 May (#3252); that the
20 March to 27 March era was tested; that the destroy-family prompts were "missing" before 11 October; that the sandbox or the GitHub token
scope "stayed in force" (no in-container check was run); that production telemetry shows the prompts arriving (0 natural asks in the first
hour); that no user was affected or no destructive command ran; any statement that T&C 3a.7 was or was not breached. The word "restored" or
"in force in production" waits for a recorded production confirmation ("confirmed from production use on <date>").

> **Superseded 2026-10-12 (#10054):** the earlier "Measured basis for the dates" note named "30 September 2026" as the notice's date (the first
> successful production deploy of a build carrying SDK 0.3.284, 2026-09-30T00:11:12Z); that date no longer appears in the notice, and the
> earlier sentence "no later than 29 Sep 2026" stays withdrawn.

## Action Items & Follow-ups

Every row cites #10054, which stays open as the tracker for them and closes when the last is done.

| Issue | Action | Status |
|---|---|---|
| #10054 | Operator: publish or decline the notice above (fill the bracketed dates) and add a breach-register row recording the decision (CLO). No Art. 33 clock is indicated. | open |
| #10054 | Bisect the SDK versions with the probe to bound when the gate went inert, then fill the notice's start date. | done 2026-10-12: every pinned SDK (0.2.80 to 0.3.284) is inert on the pre-fix tree; no single start date; the notice carries the CLO-worded range |
| #10054 | Re-run `apps/web-platform/scripts/dev-probe-destroy-ask.ts` against the deployed build and after any SDK, CLI or sandbox-option bump; record the two limbs of ADR-284's proposed equivalence (card behaviour; production arrival) before ADR-284 is accepted. | partly done 2026-10-12: probe PASS covers owner, non-owner member, a stale batch grant with a live-grant control and the `gh` family (ADR-284 C9 block); production sink arrival NOT OBSERVED; the dev-hosted equivalence awaits operator ratification; the soak windows close 2026-10-13T08:40Z and 2026-10-19T08:40Z |
| #10054 | Legal (CLO, ties to #9955): T&C 3a.7 says Soleur "always blocks a fixed set of clearly-dangerous commands"; that blocklist was not in force for hosted Bash while the gate was inert. Decide whether the sentence needs a correction; not edited here. Tracked on #9955 (comment 2026-10-12); owner: CLO. | open |
| #10054 | Public-repo disclosure ordering: merging this PR publishes the inert-window records (window, dates, causes) before the operator has decided on the user notice and the breach-register row. Operator gate, listed in the PR #10101 body; owner: operator; due before merge. | open |
| #10054 | Legacy runner (`agent-runner.ts`, domain leaders): every non-safe Bash now asks and has no autonomous toggle or batch cache; wire those deps if that proves too noisy. | open |

The scheduled `soleur-eval` crons and the sandbox canary are not affected (they use their own permission setup).
