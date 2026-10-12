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

- Start not measured; the SDK version is not the discriminator. The real-SDK probe, run on the pre-fix tree (commit c982f61b5a) under each SDK version the repo ever pinned for production (0.2.80, 0.2.85, 0.3.197, 0.3.284), two runs each with the sandbox-engaged control passing every time, never saw `canUseTool` called for sandboxed Bash. 0.2.80 and 0.2.85 had to run on claude-sonnet-4-5 because their CLIs reject the current default model (API 400), and the older versions were substituted into the pre-fix tree, not run as the builds that were live then. That tree already carries the hook's explicit `allow` (added 2026-04-15), which production lacked before that date, so the 0.2.80 row (production from 2026-03-27 to 2026-04-15) does not measure that era's production tree: for that era only cause 1 was present and it was measured alone only on 0.2.85 and 0.3.284. An earlier pin also existed: `^0.2.76` from 2026-03-18 (then `^0.2.80` on 2026-03-20) until the exact 0.2.80 pin of 2026-03-27 (#1182); it was never run, so the 2026-03-20 candidate falls in an era no probe covers. The earlier hypothesis that the 0.3.x bump caused it is refuted. Each cause alone suffices: with the PreToolUse hook removed (`autoAllowBashIfSandboxed: true` alone) the gate is inert on 0.2.85 and 0.3.284; with `autoAllowBashIfSandboxed: false` and the hook's explicit allow kept it is inert on 0.3.284 (inconclusive once on 0.2.85, where the model did not try Bash). The start therefore rests on code history, not measurement. `autoAllowBashIfSandboxed: true` first appears 2026-03-20 (#871, legacy runner; its first release run failed, so its deploy time is later and unmeasured). The hook's explicit allow for Bash arrived 2026-04-15 (#2284, deployed 12:40Z, same commit as the SDK 0.2.85 bump). The Command Center dispatcher bound the same sandbox config on 2026-04-27 (#2901, deployed 08:35Z; before that it made no real SDK calls), so 2026-03-20 governs the legacy agent-runner only and 2026-04-27 the Command Center path. One observation contradicts the inference and is unreconciled: #3252 (created and closed 2026-05-05) reported Command Center Bash prompting on `ls` and `pwd` while both causes were in the code, and its fix (#3277, merged the same day) changed the safe-Bash allowlist INSIDE `canUseTool`, i.e. the callback was reached for at least some read-only Bash that day. Possible explanations, none verified: the sandbox was not engaged in production that day (the auto-allow applies only when sandboxed), or a different surface. It is not evidence that the gate worked, and it contradicts the measured "never called" for that day; it stays unreconciled. We record a window, not a start date: the earliest dated candidate is 2026-03-20, inert on the production build is measured only for the SDK 0.3.284 period before the fix (in service from the first successful deploy of a build carrying it, 2026-09-30T00:11:12Z; the merge's own release runs skipped or failed their deploy), and it ended at the fix deploy on 2026-10-12 (deploy job finished 08:38:33Z).

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
  # verdict is read from the verdict= and canUseToolCalls= fields of the PROBE lines (a PROBE_ONLY run exits 4 by design):
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
- Terms: AUP 5.7 and T&C 3a.7 do not promise an ask. T&C 3a.7 does say Soleur "always blocks a fixed set of clearly-dangerous commands", and that blocklist lives in `canUseTool`, so it was not in force for hosted Bash while the gate was inert. Whether that sentence needs a correction is a legal decision for the operator (CLO), not edited here.

## Gap in what we can say

Hosted `autonomous-bypass` lines are INFO and are not shipped to a queryable sink, so we cannot enumerate from telemetry whether any hosted destroy-family command ran in the window. The only record is each user's own repository history and infrastructure state.

## Fix

`autoAllowBashIfSandboxed: false` (sandbox stays on) and the hook returns `{ continue: true }` (no decision) for Bash; the sensitive-env deny is unchanged. The real-SDK probe (`apps/web-platform/scripts/dev-probe-destroy-ask.ts`) passes: three destroy forms reach the Approve/Reject card and leave the default branch unchanged; the control push reaches `canUseTool` and is not asked. The three user-facing Bash gates (review card, first-run disclosure, opt-out) now share one hold helper that fails closed on expiry and keeps the conversation status correct for stacked cards; they were unreachable code until now.

## Draft user notice (operator publishes; not published by the agent; fill the bracketed dates before use)

> Soleur's hosted Concierge is meant to pause for your approval before a default-branch force-push, `terraform destroy` or repository
> deletion, and the "ask before every command" setting is meant to prompt for each command outside a short read-only allowlist. For a
> period ending **12 October 2026** (the fix reached production when its deployment finished at 08:38 UTC), those prompts, and the
> command blocklist that sits beside them, did not apply in hosted workspaces, and commands ran without asking. We reproduced this by
> direct testing of the code that was in service from **30 September 2026**. Our code history shows the two causes first appear on
> **20 March 2026** (one part of the product) and **27 April 2026** (Command Center), so your sessions may have been affected from those
> dates. We have not been able to establish a single start date, and we have not established that the prompts were inactive throughout.
> The sandbox and your repository's GitHub token scope stayed in force. The prompts are restored in the deployed build as of **12 October 2026**. If you relied
> on them, review your repository's push and branch-deletion history (GitHub: repository Activity, or `git reflog` on any clone) and your
> infrastructure state from 20 March 2026 onward, and tell us if anything unexpected happened.

Measured basis for the dates (CLO wording, 2026-10-12; it stays a DRAFT and the operator decides whether to publish and to whom): the
notice's "30 September 2026" is the first successful production deploy of a build carrying SDK 0.3.284 (2026-09-30T00:11:12Z); the earlier
sentence "no later than 29 Sep 2026" is withdrawn because it rested on the refuted SDK-bump reading. Do not claim a single start date, that
the SDK bump caused it, that the gate worked on 5 May (#3252), or that no user was affected or no destructive command ran.

## Action Items & Follow-ups

Every row cites #10054, which stays open as the tracker for them and closes when the last is done.

| Issue | Action | Status |
|---|---|---|
| #10054 | Operator: publish or decline the notice above (fill the bracketed dates) and add a breach-register row recording the decision (CLO). No Art. 33 clock is indicated. | open |
| #10054 | Bisect the SDK versions with the probe to bound when the gate went inert, then fill the notice's start date. | done 2026-10-12: every pinned SDK (0.2.80 to 0.3.284) is inert on the pre-fix tree; no single start date; the notice carries the CLO-worded range |
| #10054 | Re-run `apps/web-platform/scripts/dev-probe-destroy-ask.ts` against the deployed build and after any SDK, CLI or sandbox-option bump; record the two limbs of ADR-284's proposed equivalence (card behaviour; production arrival) before ADR-284 is accepted. | partly done 2026-10-12: probe PASS covers owner, non-owner member, a stale batch grant with a live-grant control and the `gh` family (ADR-284 C9 block); production sink arrival NOT OBSERVED; the dev-hosted equivalence awaits operator ratification; the soak windows close 2026-10-13T08:40Z and 2026-10-19T08:40Z |
| #10054 | Legal (CLO, ties to #9955): T&C 3a.7 says Soleur "always blocks a fixed set of clearly-dangerous commands"; that blocklist was not in force for hosted Bash while the gate was inert. Decide whether the sentence needs a correction; not edited here. | open |
| #10054 | Public-repo disclosure ordering: merging this PR publishes the inert-window records (window, dates, causes) before the operator has decided on the user notice and the breach-register row. Operator decision before merge. | open |
| #10054 | Legacy runner (`agent-runner.ts`, domain leaders): every non-safe Bash now asks and has no autonomous toggle or batch cache; wire those deps if that proves too noisy. | open |

The scheduled `soleur-eval` crons and the sandbox canary are not affected (they use their own permission setup).
