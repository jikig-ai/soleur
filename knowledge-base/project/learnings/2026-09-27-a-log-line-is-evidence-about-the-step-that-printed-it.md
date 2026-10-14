---
title: A log line is evidence about the step that printed it
date: 2026-09-27
category: workflow-issues
module: ADR-237 acceptance, git-data-cutover.yml evidence
tags: [evidence, workflow-logs, adr, host-key-pinning, inherited-framing]
pr: 9036
---

# Learning: a log line is evidence about the step that printed it

## Problem

Flipping ADR-237 (SSH host keys are pinned) to `accepted` needed evidence that a strict
`git-data-cutover.yml` dry run read `role=git-data-auth verdict=ok` with both hops pinned. I grepped
run 36119817656's log for `strict|pinned|verdict` and wrote `ssh-strict: true` into the ADR addendum as
proof the run was strict. That line sits in the `with:` block of the run's `actions/checkout` step — it
is checkout's default input for git-over-SSH clones, and this run cloned over HTTPS. The real controls
(`StrictHostKeyChecking yes` in the bridge's `WEB_HOST_SSH` and the `gd-ssh-config` step, each with
`GlobalKnownHostsFile /dev/null`) were in the same log. Both review seats caught it independently.

Second, the prose said the run exited 5 "because the store had already been cut over". That framing came
from the session's own summary of the operator's queue ("#5274 cutover G2–G4 done"). The script defines
`already_cut_over` as git-data serving the LUKS mapper at `/mnt/git-data` from boot (ADR-239, PR1 of
#8211), delivered by a replace; no data moved and the store has never held a repository.

## Solution

Cite the controls by the step that applies them, not by a matching token: the addendum now names
`StrictHostKeyChecking yes` in `WEB_HOST_SSH` / `gd-ssh-config`, labels `git_data_pin=present` as the
CI precheck's Doppler read (which matches the pin by construction, so it proves nothing on its own),
and states `already_cut_over` in the script's own terms with the replace run id.

## Key Insight

A grep hit in a CI log is a claim about the STEP whose group contains it, and GitHub Actions logs every
step's `with:` block — so a keyword can appear inside an unrelated action's default inputs. Before citing
a log line, read which `##[group]Run …` it sits under. And a sentence carried from the session's own
framing is an inherited claim like any other: define the term from the code that emits it.

## Session Errors

1. **Cited `ssh-strict: true` (actions/checkout input) as host-key evidence.** — Recovery: replaced with
   the actual `StrictHostKeyChecking yes` controls after both review seats flagged it. — Prevention:
   `plan-sharp-edges.md` bullet: attribute every cited log line to its `##[group]Run` step.
2. **Propagated "the store was cut over" from session framing into ADR prose.** — Recovery: restated
   `already_cut_over` per `git-data-cutover.sh` and cited replace run 36118115758. — Prevention: covered by
   the existing inherited-sentence rule (compound Phase 0.5); name the command that defines the term.
3. **MD032 in a hand-written `session-state.md`** (heading directly followed by a list). — Recovery: blank
   line inserted. — Prevention: one-off; run markdownlint on every hand-written KB file before commit.
4. **A Phase 7 poll block extracted raw from `ship/SKILL.md` ran with its plugin-root token unsubstituted**,
   so BEHIND auto-sync was disabled until re-armed. — Recovery: re-armed with
   `export CLAUDE_PLUGIN_ROOT=<plugin root>`. — Prevention: when running a SKILL.md fence standalone,
   export `CLAUDE_PLUGIN_ROOT` first; the fence's own precondition line reports it, so read its first event.
5. **`rename-guard` false positive on PR #8878** from sync merges (first-parent diff paired main's deleted
   workflow with main's unrelated new spec at 5% similarity). — Recovery: rebuilt the branch as one linear
   commit on `main` with an identical tree, no override. — Prevention: already tracked (#9028, #8348,
   #8575); instance added to #9028.
6. **Ended a turn on a first-person promise instead of the action** (stop hook fired). — Recovery: took the
   action or stated the block. — Prevention: already hook-enforced (`unkept-promise-hook.sh`).
