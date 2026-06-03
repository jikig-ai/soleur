---
title: "CLA Assistant fails on bot commits authored by a login-less identity — fix the Docker global default, not the prompt-level local config"
date: 2026-06-03
category: integration-issues
tags: [cla, github-actions, bot-identity, dockerfile, git-config, cron, inngest]
pr: 4909
refs: [4907, 4899, 4870]
---

# Learning: CLA fails on bot commits whose author identity has no GitHub login

**Date:** 2026-06-03
**Context:** PR #4909 (fix) / symptom PR #4907 (stuck community-digest)
**Category:** integration-issues

## Problem

Every automated `cron-community-monitor` community-digest PR (e.g. PR #4907)
sat with a red `cla-check`. The standard remediation — comment "I have read the
CLA Document and I hereby sign the CLA" — **cannot work** here: the offending
digest commit was authored by `Soleur <soleur@localhost>`, an identity with
**no GitHub account**, so there is nothing to attach a CLA signature to.

`contributor-assistant/github-action` (the `cla-check` workflow) resolves
committers via GraphQL `commit.author.user.login`. `soleur@localhost` maps to
no contributor → it can never match the allowlist
(`dependabot[bot],github-actions[bot],renovate[bot],deruelle,claude[bot]`) →
permanent FAILURE on every digest until fixed.

## Root cause

Two layers, and the wrong one was assumed to be authoritative:

1. **`apps/web-platform/Dockerfile:137`** set the container's **global** git
   identity to `Soleur / soleur@localhost`. This is the *default* author for any
   commit made inside the sandbox that does not set its own local identity.
2. The cron prompt (`cron-community-monitor.ts:181-182`) *attempts* to override
   it with a repo-**local** `git config user.name "github-actions[bot]"`. But
   that is **free-text prose instruction to a spawned `claude`**, not
   deterministic code. When the model skips or reorders that step, the commit
   falls back to the Dockerfile global identity → CLA fails.

The failure is structural, not transient: it recurs whenever the prompt step
doesn't fire. Fixing the *prompt* would have been a band-aid on a
non-deterministic step.

## Solution

Make the **default** safe. Change the Dockerfile global identity to the
first-party GitHub Actions bot:

```dockerfile
RUN git config --global user.name "github-actions[bot]" \
    && git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"
```

`contributor-assistant/github-action` **hardcode-drops** committers whose
`databaseId === 41898282` (the GitHub Actions bot) *before* the allowlist
filter runs (`src/graphql.ts`: `filteredCommitters = committers.filter((c) => c.id !== 41898282)`).
The `41898282+...@users.noreply.github.com` noreply email resolves to that
account (`gh api /users/github-actions%5Bbot%5D` → `{"id":41898282,...,"type":"Bot"}`).
So a digest commit authored under this identity clears CLA **even when the
prompt's local `git config` step is skipped.** The prompt-level local config is
kept as defense-in-depth (12 sibling crons already use the same canonical
identity).

## Key insight

When an automated/bot commit needs to clear a CLA (or any author-identity gate),
the load-bearing question is **"what identity does the commit actually carry by
default?"** — not "what does the prompt/script intend to set?". A prompt-level
`git config` is only as reliable as the step firing; the **build-image global
default** is the deterministic floor. Set the floor to a CLA-clearing identity
and the prompt step becomes redundant-but-harmless rather than load-bearing.

Distinct from [[2026-04-27-cla-allowlist-graphql-vs-rest-bot-identity-surface]],
which covered *which login string to put in the allowlist*. This learning is
about the **author identity on the commit**, the upstream half of the same gate:
the allowlist is irrelevant if the committer has no resolvable GitHub login.

Non-regression note: the Concierge per-user/per-repo credentialing
(commit 9cd62804 / #4899) is unaffected — `push-branch.ts` sets its own *local*
identity (`Soleur Agent <agent@soleur.ai>`), and local config overrides global.

## Session Errors

1. **[plan phase] IaC-routing pre-write gate false-positive** on the literal
   token `doppler secrets set` inside GDPR-gate prose. Recovery: reworded to
   "no secret mutation." Prevention: when writing plan prose that *names* an
   infra command as a counter-example, avoid the bare command literal — describe
   the action ("no secret mutation") rather than quoting `doppler secrets set`.
2. **[plan phase] Worktree-write guard** blocked a write to the bare-root mirror.
   Recovery: redirected to the `.worktrees/...` path. Prevention: subagents must
   run `cd <worktree> && pwd` as the first tool call and write only under that
   path (the plan subagent's CWD-verification step exists for exactly this).
3. **[review phase] Deepened plan's sibling-site count was inconsistent** —
   prose "9", named list "7", table "11", actual `git grep -l` = **12**. Caught
   by two orthogonal review agents; fixed inline (commit `dc4c7269`). Prevention:
   already covered by [[2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts]]
   — any "N sibling sites" figure presented as live-verified MUST be the integer
   the canonical command returns at write time, copied verbatim, not paraphrased.
