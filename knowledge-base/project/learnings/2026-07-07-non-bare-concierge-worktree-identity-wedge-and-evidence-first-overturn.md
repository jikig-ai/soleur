---
title: "The recurring worktree wedge was an identity-authority inversion, not a lock bug — and Concierge is non-bare"
date: 2026-07-07
category: bug-fixes
module: git-worktree
issue: 6184
tags: [git-worktree, concierge, identity, config-lock, evidence-first, adr-098, bot-attribution]
---

# Learning: the recurring Concierge worktree wedge was an identity-authority inversion

## Problem

`worktree-manager.sh create` had wedged the Concierge/agent-sandbox environment through **six** consecutive rounds of fixes (#5880 → #5907 → #5932 → #5934 → #6041 → #6071/#6108), each hardening the bare-repo `ensure_bare_config`/`atomic_git_config`/sweep path and each failing to stop the recurrence. The symptom was an unremovable `.git/config.lock` (EEXIST/RC=255) blocking every autonomous `/soleur:one-shot` and `/soleur:go` run.

## Root cause (telemetry-confirmed, overturned the hypothesis twice)

The wedge was **not** in the lock-handling machinery at all. Better Stack telemetry showed `.git/config.lock` is a `type=chardevice rdev=1:3` — a bound `/dev/null`, i.e. ADR-081's *deliberate* per-session bwrap RCE guard, not a filesystem residual. And `git worktree add` **succeeds**. The failure is the step after: `ensure_worktree_identity` was written for the **bare CLI dev repo** (where a repo-local CI-bot identity should be overridden by the operator's human `--global`), so it *forced global over local*. On the **non-bare Concierge workspace** the polarity is inverted — `--global` is the sandbox image's `github-actions[bot]` (Dockerfile), `--local` is the host-seeded workspace **owner** (`workspace.ts`) — so it tried to overwrite the correct owner with the bot via a raw `git config --local` write that EEXISTs on the masked lock. The abort was a plain-git `EEXIST`, **not** a `SOLEUR_GIT_LOCK_*` marker, which is exactly why six telemetry-blind rounds missed it.

## Key insights

1. **Evidence-first before fixing a recurring bug.** Two supplied hypotheses (the brief's `_config_lock_wedged` misclassification, then a sweep/`git worktree add` re-scope) were BOTH wrong. Pulling the actual `SOLEUR_GIT_LOCK_DIAG` line from telemetry + a local RC=255 reproduction is what found the real cause. A symptom that survives N rounds is a signal the *layer* is wrong — get the production signature before writing round N+1.

2. **The naive fix was actively harmful.** Routing the raw write through `atomic_git_config` (the "obvious" fix) would have *succeeded* — at silently misattributing the user's commits to `github-actions[bot]`. The wedge was accidentally protecting git authorship. A loud wedge can be preferable to a quiet wrong-write; check what a "successful" write would actually do.

3. **Identity authority is inverted between git surfaces — neither blanket rule is correct.** "Always force global" is wrong on non-bare Concierge (the #6184 wedge); "always respect local" is wrong on the bare CLI dev repo, which *frequently* carries an inherited `github-actions[bot]` local that worktrees inherit (the #2815 CLA-reject bug). The correct discriminator is **bot-shape** (`_identity_is_bot`: a `[bot]` marker in name/email): respect a present non-bot local, override a bot-shaped local from a human global, and *never write a bot-shaped global*. Two review agents (user-impact + architecture-strategist) independently caught that the first-cut "respect local" re-opened #2815 — cross-agent concurrence, not a single-agent false positive.

4. **Git-surface topology was tribal knowledge → six mis-targeted rounds.** Soleur runs git over three structurally different layouts: server-side **bare** git-data (`/mnt/git-data`, `git init --bare`), the **non-bare** agent workspace (`/workspaces/<id>`, `git clone --depth 1`, where worktree-manager runs), and local **bare+worktrees** dev. This was documented only as an inline comment and re-derivable only from server code. Making it a canonical, always-loaded fact (ADR-099 + AGENTS.core/rest caveats) is the durable root-of-recurrence fix. **An all-scripts audit against ADR-099 found zero other bugs of this class** (~20 files verified layout-correct; 2 low-severity latent surfaces tracked in #6191).

## Session Errors

- **Conflated local-dev-bare with Concierge-non-bare.** I ran `git rev-parse --is-bare-repository`, saw `true` on the *local dev* repo, and asserted "same layout as Concierge." Concierge's agent workspace is a non-bare clone. **Recovery:** user challenge → verified via `ensure-workspace-repo.ts`. **Prevention:** ADR-099 makes the three surfaces canonical; AGENTS.core/rest rules now carry the non-bare caveat so the always-loaded rules stop implying "everything is bare." (recurring → fixed-now-inline)
- **Acted on a supplied hypothesis without production evidence (twice).** **Recovery:** Better Stack telemetry + local repro overturned both. **Prevention:** the evidence-first mandate — for a bug that survived prior rounds, pull the live signature before designing the fix. (recurring → captured)
- **#4826 mislink poisoned one-shot routing.** The originating session burned two dispatches + a timed-out AskUserQuestion on the unrelated nav-rail issue #4826 that prior wedge PRs had mis-linked. **Recovery:** diagnosed the mislink; opened correct tracking #6184; corrected wedge-diagnosis citations. **Prevention:** go's Sharp Edges already warn on closed/mismatched `#N`; this reinforces scrubbing mislinked closing refs. (recurring → captured + corrected)
- **First-cut identity fix re-opened #2815.** The plan's "respect present local" blanket rule kept a bot-shaped local on the bare dev repo. **Recovery:** review caught it (2-agent concurrence); fixed with the bot-shape discriminator + T18/T19. **Prevention:** never substitute one blanket authority rule for its opposite — discriminate on the actual harm signal. (recurring → fixed-now-inline)
- **Called TaskCreate without loading its deferred schema.** **Recovery:** fell back to plan-checkbox tracking. **Prevention:** load deferred-tool schemas via ToolSearch before calling. (one-off)
- **Push rejected; needed `--force-with-lease`.** The Phase 0.5 rebase (required by the AGENTS.* collision gate) rewrote history vs the remote's initial draft-PR commit. **Recovery:** lease-guarded force-push on the feature branch (never main). **Prevention:** expected after a mandated rebase on one's own feature branch. (one-off)
- **Session/API limits cut off two subagents mid-run.** **Recovery:** resumed from committed artifacts (plan/tasks on disk; partial impl commit). **Prevention:** the pipeline's incremental-commit discipline made resume clean. (one-off, external)

## Tags
category: bug-fixes
module: git-worktree
