---
title: "Three agents misstated the live-verify gate state, and one report never arrived"
date: 2026-10-16
category: workflow-issues
module: plugins/soleur/skills/brainstorm
tags: [brainstorm, subagents, live-verify, postmerge, premise-verification]
issue: 10449
pr: 10446
---

# Learning: re-derive the gate state from the workflow, not from the skill or a leader

## Problem

The brainstorm for "Soleur should do live verification itself" ran CPO, CTO, repo-research, learnings and CLO agents.
Their claims about the live-verify gate disagreed:

- CPO: the fail-closed gate "has since been relaxed" (report-only).
- CTO: report-only "until #5463 flips it to blocking".
- repo-research: CI is blocking, `postmerge/SKILL.md` is stale.

`gh issue view 5463` returned CLOSED, and `.github/workflows/web-platform-release.yml` ("Enforce live-verify gate")
shows `exit 1` on `BLOCK=1`, flipped 2026-06-18. Only repo-research was right. The CPO and CTO read the skill text
(`postmerge/SKILL.md` ~lines 239, 387-393, 593, 620), which still says REPORT-ONLY.

A second problem: the repo-research task notification carried no report text. The output file is a JSONL transcript and
must not be read directly. `SendMessage` to the agent id ("re-send your report as your reply") resumed it and returned the
full text.

## Key Insight

A skill's prose about a CI gate is a claim about CI, and goes stale when the gate flips. For any "is gate X blocking?"
premise, read the workflow's enforcing step (the `exit 1` line) and the closing issue's state. Do not accept a leader's
reading of the skill.

When a notification arrives without a result, resume the agent with `SendMessage` and ask for the report. Do not read the
transcript.

## Session Errors

1. **Repo-research notification arrived without report text.** Recovery: `SendMessage` re-request. Prevention: for any
   completed agent whose notification has no `<result>`, resume it with SendMessage immediately.
2. **CPO and CTO misstated the postmerge gate state (report-only).** Recovery: read `web-platform-release.yml` and
   `gh issue view 5463`. Prevention: spec FR6 in #10449 corrects `postmerge/SKILL.md`; the brainstorm skill already
   requires re-deriving a cited PR/issue state before it bounds options.
3. **Stop hook fired on closing prose that promised a next action ("I'll reconcile…").** Recovery: ended with a
   `Paused:` sentence naming what was awaited. Prevention: end an in-progress turn with the label sentence, not a promise.
4. **Session-start gates run as condensed fences, not the verbatim blocks.** Recovery: none needed, the verdicts matched
   (`SOLEUR_GIT_REPO_READY=true`, `not-local:no-devin-env`). Prevention: run the fences verbatim; the resolver comments
   say the copies are pinned byte-identical.
5. **Session started with CWD at the bare repo root (`is-bare-repository` true).** Recovery: brainstorm Phase 0 created
   the worktree and draft PR (#10446) before any file write. Prevention: none; the existing guard worked.
