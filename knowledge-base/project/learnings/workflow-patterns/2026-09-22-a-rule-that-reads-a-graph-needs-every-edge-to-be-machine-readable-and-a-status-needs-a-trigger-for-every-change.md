---
title: A rule that reads a graph needs every edge machine-readable, and a status needs a trigger for every change
date: 2026-09-22
category: workflow-patterns
module: product-roadmap
tags: [product-roadmap, github-dependencies, frontier, prompt-injection, review-panel, board-status]
issue: 8292
pr: 8536
---

# Learning: a frontier over GitHub-native blocking edges

## Problem

Bundle 5 of the mattpocock/skills audit (#8292) gave `product-roadmap` a
"Not Yet Specified" fog section, out-of-scope-as-closed-issue, and a frontier
(open, no open native blocker, no assignee) read by `next --frontier`. Three
defects of one shape reached the review panel after a plan review, a deepen
pass and a 25-sentence constrained dry run:

1. **A prose edge on a graph-reading rule.** The first rules let a sharp issue
   whose blocker was still fog carry `Blocked by: <bullet text>` in its body.
   The frontier reads only native edges, so that issue reached the frontier as
   if ready — and graduating the bullet later left the prose dangling. Four
   seats (simplicity, quality, data-integrity, architecture) found it
   independently.
2. **A status mapping with no trigger for the change it maps.** Review mapped
   an open native `blockedBy` edge to the Kanban "Blocked" column in
   `set-board-status.sh`. `board-status-sync.yml` runs only on
   reopened/labeled/unlabeled issue events and PR events; nothing fires when
   an edge is added or a blocker closes, so a card moved to Blocked would stay
   Blocked after its blocker closed — worse than the old behaviour. The
   post-review coverage consult found it; the mapping was reverted.
3. **Attacker-authored text in a field-delimited line an agent relays.**
   `next --frontier` printed `CODEABLE|#N|title`. Issue titles are editable by
   their authors on a public repo, so a title with a newline forged a whole
   extra `CODEABLE|#9999|…` line and a second `Build it: /soleur:go #9999`
   line — bypassing both the label check and the frontier (security seat,
   reproduced).

## Solution

1. If a blocker is still fog, the blocked work is fog too: it stays in Not Yet
   Specified until the blocker can be filed. There are no prose edges on the
   graph the frontier reads.
2. Revert the board mapping. Making the board follow dependency changes needs
   new workflow triggers plus a recompute of each dependent on close — its own
   change, not a side effect of this one.
3. One jq `clean` definition replaces control characters, U+2028/U+2029 and
   `|` in every printed title; `filter_frontier` refuses a non-numeric
   `number`, a null `blockedBy` or a null `assignees` as a data error (exit 2)
   instead of reading them as "unblocked"; WAITING lines print
   `owner/repo#N` so a cross-repository blocker is not mistaken for a local
   issue.

Also measured and fixed: `gh api` expands `{owner}/{repo}` only in the
endpoint path, never inside a `-f` value (HTTP 422), so a search query must
resolve the repo name first (`gh repo view --json nameWithOwner`).

## Key Insight

When a mechanism reads a structure (a graph, a status set), audit the
**writers** of that structure, not just the reader: every way an edge can be
created must produce something the reader can see, and every state change the
mapping depends on must have a trigger. A reader that is correct over the data
it can see is still wrong if some writers produce data it cannot see.

## Session Errors

1. **PR #8284 (the audit's Tier 1 entry) is still open; `competitive-intelligence.md` on main has no mattpocock row** (forwarded from planning) — Recovery: no shipped file cites the entry; NOTICE's pinned SHA is the provenance anchor. **Prevention:** before citing an artifact as "landed via PR #N", run `gh pr view N --json state`.
2. **The issue body attributed the blocked-by staleness check to product-roadmap Phase 0.6; it is plan Phase 0.6** (forwarded) — Recovery: no shipped text repeats the attribution. **Prevention:** grep the named phase in the named file before repeating an issue's cross-reference.
3. **`/tmp` hit EDQUOT mid-review; every Bash call (even `true`) failed** — Recovery: the operator freed space; my sandboxes (≈3 MB) were removed. Most of the 13 GB was not mine, but my panel brief let agents build unbounded sandboxes (one per mutant) in the scratchpad with no cleanup. **Prevention:** brief sandboxes under `/var/tmp`, one reusable copy restored from a pristine backup per row, deleted before the agent returns (routed to `review/SKILL.md` Sharp Edges).
4. **SKILL.md prescribed `gh api search/issues -f q="repo:{owner}/{repo} …"`** — the placeholder is not expanded in `-f` (HTTP 422). Recovery: caught by a live read-only probe before commit; now resolves the repo name. **Prevention:** run every `gh` command a skill prescribes once, read-only, before committing it.
5. **Board Blocked mapping without a trigger** (above) — Recovery: reverted. **Prevention:** for any status mapping, list the state changes it depends on and name the workflow trigger that fires on each; if one has none, the mapping goes stale.
6. **The fake gh's SIGTERM mode signalled `$PPID`, the command-substitution subshell, not the script** — Recovery: walk up to the topmost ancestor whose cmdline is the module. **Prevention:** a fake that signals its caller must resolve the caller explicitly.
7. **"Exactly one Build it line" matched the (cleaned) title text too** — Recovery: anchor on `^  Build it:`. **Prevention:** anchor line-count assertions on line start.
8. **A NOTICE rewrite used `index()` on "MIT License (upstream)", which occurs three times** — Recovery: the exact-count assert refused the write; search from the Bundle 5 offset. **Prevention:** keep the `count == 1` assert on every scripted replacement.
9. **Lints on new code: capture-exit S1, trap-ownership rule (c) on both new `mktemp`s, shellcheck SC2097/SC2098/SC1007** — Recovery: fixed before commit. **Prevention:** run `lint-shell-capture-exit.py`, `lint-trap-tempfile-ownership.py` and `shellcheck -S warning` on every new `*.sh`/`*.test.sh` before its first commit.
10. **markdownlint MD049 in roadmap.md, and pre-existing MD022/MD032 in an old spec surfaced by touching it** — Recovery: fixed. **Prevention:** lint every touched markdown file, not only new text.
11. **`next --frontier | head` exits 2** (jq EPIPE converted by `|| return 2`) — Recovery: none needed; the skill runs the command unpiped. **Prevention:** read a CLI's rc from an unpiped run.
12. **tsc's rc was read through `| tail`** — Recovery: re-ran with `> log; rc=$?`. **Prevention:** never pipe a command whose exit code is the result.
13. **The Stop hook fired twice while waiting on agents** — Recovery: stated the blocker explicitly. **Prevention:** end a waiting turn with a `<stop>BLOCKED: …</stop>` line, not "I'll …".
14. **My self-run battery killed 10/10; the test-design seat then found 11 of 18 mutants surviving** (dispatch, fake-gh argv fidelity, output wording) — Recovery: floor + positive control, argv-exact fake, wording asserted; re-run 22/23 killed. **Prevention:** already in `review/SKILL.md` (count axes, not rows).
15. **The plan never considered title injection** — Recovery: `clean` + number type check. **Prevention:** routed to `plan-sharp-edges.md`.
16. **The plan-time dry run (25 sentences flagged) still missed the fog-blocker gap** — Recovery: fixed at review. **Prevention:** give a dry run at least one case per rule that crosses a lifecycle transition (graduation, removal, ruling-out), not only placement cases.

## Tags

category: workflow-patterns
module: product-roadmap
