---
module: brainstorm
date: 2026-08-06
problem_type: best_practice
component: domain-leaders
tags: [brainstorm, domain-leaders, verification, subagent-claims, sync]
severity: medium
---

# When a leader says a generated artifact is insufficient, read the artifact

## Problem

A brainstorm asked whether `/soleur:sync` could generate a C4 architecture model
for a newly-onboarded project. That was the operator's headline ask.

The CTO domain leader returned a confident, well-reasoned **defer** verdict:

> `sync.md` detection is top-level-dir + index-file heuristics with exclusions.
> That yields **nodes only**. […] `views.c4` would render a bag of unconnected
> boxes into a file operators then hand-edit — worse than nothing. Edges need
> import-graph extraction […] JS/TS-only, so it would emit zero.

Every sentence of that is true about the mechanism it names. Accepting it would
have cut the operator's headline ask from the release.

## Root cause

The leader reasoned from the **generator's specification** — sync's
"Component Detection Heuristics" section — and never read what the generator had
actually **produced**.

Sync has two distinct steps, and the leader only saw one:

| Step | What it does | Output |
|---|---|---|
| Component Detection Heuristics | top-level dirs, index files, exclusions | node set only |
| **Project Analysis** | *"Data flow: How information moves between components"*, *"Dependencies: Internal and external dependencies per component"* | **edges** |

The second step's output was already sitting in the alpha tester's repo. One API
call refuted the verdict:

```bash
gh api repos/<owner>/<repo>/contents/knowledge-base/project/components/<name>.md \
  --jq '.content' | base64 -d | sed -n '/## Dependencies/,/^## /p'
```

Result, consistent across **5 of 5** component docs:

```text
database.md     → **Internal**: [web-server](web-server.md) …; [core-infra](core-infra.md) …
frontend-app.md → **Internal**: [web-server](web-server.md) for every byte of data
data-agents.md  → **Internal**: [core-infra](core-infra.md) …; [database](database.md) for schema
core-infra.md   → **Internal**: [database](database.md)
web-server.md   → **Internal**: [database](database.md) …
```

A consistent `[name](name.md)` link convention under a `## Dependencies`
heading. That is a parseable directed graph. The C4 producer's input is the
*generated component docs*, not the raw directory scan — and the feature was
feasible in v1 after all.

## Key insight

**File existence, generator specification, and generated content are three
separate claims.** The repo already has rules for the first two. This is the
third: when a subagent characterizes what a generated artifact *contains* —
"nodes only", "model-generated prose", "free-text", "no structure" — read the
artifact, not the code or spec that emits it.

The failure is asymmetric and therefore dangerous: a leader's verdict about
insufficiency **removes** scope. Nobody downstream re-checks a cut feature,
because a cut leaves no artifact to review. An over-claim gets caught at
implementation; an under-claim ships as a silently narrower product.

## Prevention

Before accepting a leader's "X is not derivable / not sufficient / yields only
Y" verdict about generated content:

1. Find one real instance of the artifact — ideally in the actual target repo,
   not a synthesized example.
2. Read the section the verdict is about.
3. Only then accept, refute, or narrow the verdict.

This is seconds of work and it guards the one direction the rest of the pipeline
cannot recover from.

## See Also

- [[2026-08-06-an-empty-worktree-is-not-an-abandoned-one]] — same session
- `knowledge-base/project/learnings/2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md`
  — reconciling fast-returning leader claims against slower research findings
- `knowledge-base/project/learnings/2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md`
  — the adjacent case: a leader naming a substrate that does not exist
