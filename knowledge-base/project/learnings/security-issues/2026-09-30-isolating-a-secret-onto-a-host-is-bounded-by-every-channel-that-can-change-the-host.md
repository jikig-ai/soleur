---
title: Isolating a secret onto a host is bounded by every channel that can change that host
date: 2026-09-30
category: security-issues
module: web-platform/infra (ci-deploy, soleur-host-bootstrap, infra-credentials), ADR-241 D10
issue: 8609
pr: 9263
tags: [secret-custody, doppler, cosign, deploy-channel, review, plan-quality]
---

# Learning: isolating a secret onto a host is bounded by every channel that can change that host

## Problem

#8609 moved the soleur-ai runtime GitHub App private key out of Doppler `soleur/prd`, which any
branch workflow could read. The key went into an isolated project, `soleur-github-app`. The web host
got a read token, and the deploy script overlays only the key, only onto signed images, and only
after a canary `GET /app`. Plan, deepen, 13 plan-review agents, two CTO passes and green guard
batteries (Guards 6, 7 and 8) all approved it.

A 13-seat review of PR-A then showed that the host-side gate was defence in depth, not a boundary.
The host's **code**, **image** and **environment** could each still be changed with credentials a
branch can reach:

- **Code.** `/hooks/infra-config` is authenticated only by `WEBHOOK_DEPLOY_SECRET` (Tier A, in
  `soleur/prd_terraform`, and also stored as a GitHub secret). It accepts `ci_deploy_sh_b64`, so a
  branch could overwrite the very script that enforces the gate.
- **Image.**
  - `COSIGN_IDENTITY_REGEXP` accepted `reusable-release.yml@refs/tags/v…`, and no tag ruleset
    exists. A branch could also call `reusable-release.yml@main` and get the main identity.
  - The boot path trusted `/run/soleur-image-ref`, a digest resolved from a mutable tag.
  - The plan's own premise was false: the warn-mode `verify_failed` arm returned the digest with rc
    0. "`$VERIFIED_REF` is a `@sha256:` ref" therefore did not mean "verified".
- **Environment.** A `prd` writer could set `GIT_CONFIG_*` (core.fsmonitor) and run code next to the
  key. The name denylist missed that whole class.

## Solution

The CTO ruled that the PR merges only after it makes its own invariant true. The measures:

1. **Main-ref pin on the verify side:** `--certificate-github-workflow-ref=refs/heads/main` and
   `--certificate-github-workflow-repository`, with the tag arm dropped. Checks inside the signing
   workflow run code the branch controls, so only the verifier can hold the boundary.
2. **Boot record:** a verified-digest record on the host's persistent volume, which the boot overlay
   matches against the image ref.
3. **Environment classes:** a prefix-class refusal, with collisions checked against `prd` names only,
   and the probe run under `env -i` with an absolute `node`.
4. **Cache arm:** the local-cache arm fails closed.
5. **Unit environments:** `UnsetEnvironment=` on every unit that loads the credential file.

The deploy channel (#9294) and Tier-A write access to `prd` (#9295) became **closure gates** for
#8609, not merge gates. A key born before they close counts as taken, and needs one more rotation.

A second design defect came from the delivery mechanism. `deploy_pipeline_fix.triggers_replace`
hashed the token-bearing render. Every plan context that is not opted in (the drift job, Tier-A PR
plans) then computes a different trigger, so drift would be red forever after delivery, and the
PR-B strict flag would fail those plans outright. The fix: hash the KEYLESS render plus a committed
`github_app_runtime_token_generation=N` literal, carry the token only in the provisioner
`environment {}`, and deliver by a one-line PR that bumps N.

## Key Insight

The custody of a secret delivered to a host is the weakest of: the secret store, and **every channel
that can change the code, image or environment of the process that holds it**. Enumerate those
channels, and the credential tier of each, at plan time.

A predicate that accepts a value *shaped like* proof ("a digest ref") is not the proof. Trace which
arms produce that shape. Here a fail-open arm produced it too.

Anything that must be identical across plan contexts (a trigger, a hash, a computed name) must not
depend on a value only some contexts can see.

## Session Errors

1. **A session restart killed two writer agents mid-task, with about 1.7k lines uncommitted.**
   Recovery: a WIP checkpoint commit (typecheck hook excluded), then resuming both agents with their
   context intact. **Prevention:** in a fan-out, commit each agent's files as soon as it reports; for
   a long agent, checkpoint its partial tree before any wait longer than about 30 minutes.
2. **The Playwright MCP disconnected three times.** Recovery: the attempt was recorded once the
   operator reconnected and logged in. The gate was GitHub sudo-mode TOTP, which even the read-only
   settings page hits. **Prevention:** the plan's automation-status line now names that gate; attempt
   Playwright early in the session, before it is needed.
3. **`data-integrity-guardian` ended three times after 3–6 tool calls without a report.** Three
   other seats also ended without delivering their report through the hand-back. Recovery: re-ran
   the role on a `general-purpose` agent; asked the others to resend. **Prevention:** mandate
   write-to-file-first in every spawn prompt. After two empty endings, switch the agent type instead
   of resuming again.
4. **The unkept-promise Stop hook fired five times on closing text like "I'll check at ship".**
   Recovery: did the action in the same turn, or closed with `<stop>BLOCKED: …</stop>`.
   **Prevention:** end a turn only with done work or an explicit `<stop>` reason; never with a
   first-person promise.
5. **Hook denials:**
   - `pgrep -f` self-match;
   - `gh issue create` without `--milestone` or a filing exit;
   - `--body-file $F` given a variable instead of a literal path;
   - a `git stash list` chained into a command.

   Recovery: followed each hook's prescribed form. **Prevention:** already hook-enforced. Write
   issue bodies with the Write tool to a literal path first.
6. **The WIP commit was blocked by the web-platform typecheck hook on partial TypeScript.** Recovery:
   `LEFTHOOK_EXCLUDE` for that checkpoint only; the agent fixed the TypeScript. **Prevention:** a WIP
   checkpoint of another agent's partial work may exclude the typecheck hook, but never gitleaks.
7. **The plan's premise was false: the warn-mode `verify_failed` arm returned the digest with rc 0.**
   Recovery: both fail-open arms now return 3, with a Guard 7 row for it. **Prevention:** a plan
   sharp-edge bullet. When a gate keys on a value's SHAPE, trace every arm that emits that shape,
   fail-open arms first.
8. **Plan design gap: the key's enforcer could be overwritten through a branch-reachable deploy
   channel.** It was found only at review, by two seats converging. Recovery: CTO ruling; #9294 and
   #9295 became closure gates. **Prevention:** a plan sharp-edge bullet. A custody plan must list
   every channel that can change the holding process's code, image or environment, with the
   credential tier of each.
9. **`doppler_branch_config` does not exist in DopplerHQ/doppler 1.21.2.** Recovery: used
   `doppler_config` with a prefixed name (the precedent). **Prevention:** existing rule. Verify a
   resource type against the pinned provider schema before a plan prescribes it.
10. **Operator-script defects:** web-2 looked up as `web-2` instead of `soleur-web-2`; the status read
    ran without credentials; the Sentry timestamp's `Z` suffix was rejected with exit 64, so the
    count was always 0. Recovery: all fixed. **Prevention:** run every operator-script read once
    against a stub that rejects what the real tool rejects. An "always 0" result is an unrun
    instrument.
11. **A token-bearing trigger would have made the drift job red forever, and made PR-B's strict flag
    fail every plan that had not opted in.** Recovery: keyless trigger plus a generation literal,
    plus a non-secret delivered flag. **Prevention:** the Key Insight above. Measure the trigger in
    every plan context, as the fixing agent did with `terraform console`.
12. **Merging sibling #9264 cut user_data headroom to about 28 B in CI.** Recovery: moved the
    template's comment header into `server.tf`, leaving about 330 B. **Prevention:** re-measure
    budget tests after every main merge that touches cloud-init.
13. **Two merge conflicts on shared floors:** census `MUTANT_FLOOR`/`FLOOR`, the ci-deploy
    assertion floor, and `BASELINE_DECLARED_PROBES`. Recovery: combined both histories and set each
    floor from a fresh run. **Prevention:** existing practice. Never pick one side's literal; derive
    the value from the merged run.
14. **A report-only review seat wrote a temporary harness file into the repo tree.** It deleted the
    file itself. Recovery: none needed. **Prevention:** spawn prompts must name the sandbox path
    (`/var/tmp/<seat>-*`) explicitly.
15. **#8209 O10 was authorized but unsafe.** Two App-key consumers still minted from `prd_terraform`
    without a Tier-B environment. Recovery: held O10 and filed #9262. **Prevention:** before any
    irreversible eviction, enumerate every consumer of the evicted name, and check its environment
    binding against the census.
16. **I offered "close #8101 as superseded" before verifying its checklist.** The later check showed
    three hardening items still open. Recovery: closed it with an accurate mapping, and left the
    residuals on #8211. **Prevention:** verify a proposed disposition before offering it as a menu
    option.

## Tags

category: security-issues
module: web-platform/infra
