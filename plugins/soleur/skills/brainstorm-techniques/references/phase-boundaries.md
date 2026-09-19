<!-- Adapted from mattpocock/skills/skills/engineering/ask-matt/PHASE-BOUNDARIES.md (MIT, Copyright (c) 2026 Matt Pocock). -->

# Phase Boundaries — choosing between Continue, `/clear`, handoff, subagent and `/compact`

A **phase** is a chunk of work inside a session: the brainstorm, the plan, the implementation, the
QA. The definition is deliberately fuzzy — a phase ends at the moment the work reads as *"that part
is done"*.

The **phase boundary** is the gap between two phases, and it is the only place this decision belongs.
Mid-phase there is nothing to decide: continue, or split off what is left into a subagent.
Compacting mid-phase makes the session lose the thread of the work it is in the middle of.

This is a reference, not a gate. It carries the reasoning; the always-loaded rule
`cm-when-proposing-to-clear-context-or` carries the obligation.

## The five options

| Option | What it does |
|---|---|
| **Continue** | Stay in this session. No context switch at all. |
| **`/clear`** | Empty the context window and start from nothing. The old session stays resumable. |
| **Handoff** | Write a portable resume prompt or markdown file and seed a session anywhere with it. |
| **Subagent** | Send the task to its own context window and get a report back. This session is untouched. |
| **`/compact`** | Compress this context and continue from the summary. |

## The tree

Work top to bottom at the boundary. **The first *yes* wins.** Do not score the options against each
other — ask the questions in order and stop at the first one that answers yes.

### 1. Can the work continue in this session?

Two things make the answer yes:

- The next phase needs this phase as a **primary source** — it wants the reasoning verbatim, not a
  summary of it. Brainstorm → plan and plan → work are the standard yeses.
- There is enough context window left for the next phase to fit.

**Rule this out first.** Continue costs nothing and loses nothing: it is the only option on the board
that does not convert a primary source into a secondary one. Every question below is paid for with
lossiness, so none of them is worth asking until this one is answered no.

### 2. Is everything in this session irrelevant to what comes next?

If the exploration, the decisions and the dead ends are all disposable — **`/clear`**. It is the
cheapest move after Continue: it takes no time and returns the whole window, and the cleared session
stays resumable.

The cost of getting this one wrong is one-way. Clear a *relevant* context and the **why** behind what
was built is gone; re-reading the diff does not give it back.

### 3. Does the work need to travel?

**Handoff** is narrow. It is needed only when the work is:

- moving to a **different harness** (Claude Code → Devin, Codex, Grok Build),
- moving to a **different directory, worktree or repository**,
- going to **another person**,
- or forking a side task found mid-phase without derailing what is in progress.

That list is the whole clause. What a handoff buys is **portability** — an artifact that travels. If
nothing is travelling, it is not needed. In this repo the handoff artifact is the copy-pasteable
resume prompt required by `cm-when-proposing-to-clear-context-or` and `wg-end-of-work-emit-resume-prompt`:
skill or command, plan path, branch, worktree path, PR number, issue number, one-line summary.

### 4. Can the task run unattended?

Is it scoped tightly enough to run with nobody steering it? Then send it to a **subagent** and leave
this session untouched. Read-and-report work is the standard case: a review agent reads the diff and
reports back, and nothing in this session has to change to let it. `cm-delegate-verbose-exploration-3-file`
already mandates this shape for verbose exploration, which is the most common instance.

### 5. Otherwise, `/compact`.

Relevant context, same harness, same directory, and the session must stay in the loop: this is where
the tree lands, and it lands here often. Pass an instruction with it (`/compact we are about to QA
this area`) so the summary keeps what the next phase needs.

**`/compact` is the default, not the first reach.** It sits last because the four questions above it
are each cheaper or more precise. The failure mode when a session starts here is a fresh context that
is confidently wrong about a decision the summary flattened.

## Why Continue is ruled out first: primary and secondary sources

Every option except **Continue** turns a **primary source** into a **secondary source** — the session
as it actually happened, replaced by a description of it. The trade always has the same shape:

| Source | Information | Noise | Room to move |
|---|---|---|---|
| Primary (Continue) | Full | High | Little |
| Secondary (`/compact`, handoff, `/clear`, subagent report) | Lossy | Low | Lots |

A secondary source is not a worse source — it is a *different* one. It has less noise and leaves more
window to work in, which is exactly why the lower branches of the tree exist. But it cannot be turned
back into a primary source, and the loss is invisible: a flattened summary reads as confident and
complete. That asymmetry is the whole reason question 1 comes first. Pay the lossiness only when
staying costs more than it saves.

## These are judgement calls

None of the five questions is objective; each has taste in it, and the same boundary can go two ways
on two different days. The value is in asking them **in order**, **at the boundary** rather than in
the middle of the work.
