---
title: "The social variants restated the fact-checked post more loosely"
date: 2026-09-25
category: content
module: marketing/distribution
tags: [content, fact-check, social-distribute, blog]
issue: 8548
---

# Learning: the social variants restated the fact-checked post more loosely

## Problem

The #8548 founder post was fact-checked claim by claim (18/19 PASS on the first
pass, the one FAIL fixed) and passed a copywriter voice pass. The distribution
file was then written from that post by `soleur:social-distribute`. Its
LinkedIn Personal, LinkedIn Company, IndieHackers and tweet-4 variants each
compressed the post's story paragraph into one hook sentence ("Even my AI team
fell into this", "our own roadmap planning ran into the same problem", "I
learned this the hard way"). Each one turned two side-by-side facts (the roadmap
planner picked the wrong priority; it could see only a quarter of the current
plan) into a cause-and-effect claim that the AI failure WAS a parked-vs-forgotten
mix-up. PR #8536 records two unrelated defects, and the plan explicitly forbade
the causal reading. The quality reviewer rated both LinkedIn lines High; those
sections post automatically.

## Solution

Reframe every variant as "My own AI team had blind spots too", keep the two
defects side by side, and replace "reads the whole plan" with "reads all of it"
(the post only claims a quarter of the *current* plan). Add the Pocock credit to
the channels that present the four places as the fix (Reddit, LinkedIn Personal).

## Key Insight

A fact-check certifies the text it was given. A derivative written afterwards
(social variants, a meta description, a PR summary) is new prose, and compression
pushes it toward exactly the causal and universal claims the source was careful
to avoid, because a hook sentence has no room for "side by side". Run the
fact-check (or a sentence-by-sentence diff against the checked source) on every
derivative that publishes automatically, not only on the source.

## Session Errors

1. **Tracking issue refused twice by the filing gate (planning phase).** Recovery: moved to founder decision DC-1. **Prevention:** none needed; the gate worked as designed (inline-threshold work is not filed).
2. **`mktemp` failed because the scratchpad directory did not exist (planning phase).** Recovery: created it. **Prevention:** one-off.
3. **Brief carried two wrong facts** ("a quarter of our plan" was a quarter of the current phase; the two defects were separate, not causal). Recovery: plan-phase fact-check corrected both (DC-6). **Prevention:** already covered; the plan phase fact-checks brief facts before drafting.
4. **Playwright MCP failed to connect.** Recovery: not needed for this content PR. **Prevention:** one-off environment state.
5. **The loaded content-writer and social-distribute SKILL.md were stale bare-root copies** (no Phase 2.4 jargon scan, no §5.5 Hacker News skip; `skills/content-writer/scripts/` absent at the bare root, so the skill's own `${CLAUDE_PLUGIN_ROOT}` scan command would have failed). Recovery: read the worktree copies and ran the worktree's scan script. **Prevention:** when a plan relies on a skill phase the loaded copy does not have, grep the worktree's `plugins/soleur/skills/<name>/SKILL.md` before concluding the phase is absent; the bare checkout lags main by however many merges since its last sync.
6. **A scripted distribution edit aborted on anchor count 5 vs expected 2.** Recovery: section-scoped insertion (Reddit and LinkedIn Personal only). **Prevention:** already covered; the `assert count == n` before writing is what caught it, with nothing written.
7. **Distribution variants overstated the post (cause and effect, "whole plan").** Recovery: review fixes in c08b2039b0. **Prevention:** social-distribute Important Guidelines now requires fact-checking automated-channel variants against the checked source.
8. **Tweet label counts were hand-computed wrong and the first Bluesky draft was 323/300.** Recovery: recomputed labels from the text; trimmed Bluesky to 295. **Prevention:** same social-distribute bullet: compute every count from the final text, and Bluesky's 300 includes the URL.
9. **Local affected gate queued behind a sibling worktree and was stopped twice.** Recovery: operator chose to rely on CI's required `test` context (ADR-183); targeted suites (110/0), link validation, docs build, jargon scan and distribution lint had already run. **Prevention:** covered by existing guidance (`test-all.sh --capacity`; the full battery is CI's job).

## Tags

category: content
module: marketing/distribution
