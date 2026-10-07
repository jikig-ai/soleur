# Learning: subagent counts and "all CI" scope claims did not survive one re-derivation (#9677 brainstorm)

## Problem

Brainstorm for #9677 (Docker prune and `/var/tmp` scratch on worktree cleanup). Three agent claims entered the first draft of the brainstorm doc and failed a single re-derivation:

- repo-research: "3,984 quarantine entries" — `find -mindepth 1` gives 21,549 (2,103 + 19,446); top-level is 1 per root.
- repo-research: "191 `docker build` lines" — a pathspec-bounded grep outside `knowledge-base`/`*.md` gives ~42, and one of the two `--label` hits is a test assertion, not a build.
- CTO: "every `docker build` is in CI" — `plugins/soleur/skills/deploy/scripts/deploy.sh` and two infra test scripts build images on the dev host. The conclusion (nothing stamps a worktree label) held; the supporting sentence did not.

Also: the issue's measured 131 marked / 128 dead-owner dirs were 71 / 66 by brainstorm time (operator cleaned up in between), and the learnings-researcher returned generic, partly off-target entries that were not used.

## Solution

Re-derived each count with a second method before it entered the doc, corrected the doc, kept the conclusion only where the evidence still supported it.

## Key Insight

A subagent's count and its "all X are Y" scope claim are both claims. The scope claim is the quieter one: its conclusion often survives while the sentence carrying it is false, so it reads as corroborated. Re-run the grep whose result the sentence summarises.

## Session Errors

- **Repo-research quarantine count (3,984) and docker-build count (191) were unreproducible** — Recovery: re-derived with `find -mindepth 1` and a bounded `git grep` — Prevention: already covered by brainstorm Phase 1.1 "a subagent's COUNT is a claim to re-derive"; no new rule.
- **CTO "all docker builds are CI" overstated** — Recovery: grepped `plugins/soleur`, `scripts`, `apps/web-platform` — Prevention: same rule; add the scope-claim variant ("all X are Y") to that bullet only if it recurs.
- **Issue measurements went stale within hours (131 → 71 marked dirs)** — Recovery: re-measured at brainstorm time and recorded both — Prevention: covered by Phase 1.0.5 premise validation.
- **Playwright MCP failed to connect at session start** — one-off; not needed for this task.

## Tags

category: workflow-patterns
module: brainstorm
