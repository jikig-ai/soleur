# Learning: an absence pin measures its scan window, not the property it names

## Problem

PR for #11258 shipped a test that pins "no agent-reachable surface over the egress audit summary exists" and an ADR amendment
saying the test is "designed to fail first when a surface is added". The thirteen-seat panel found the pin scanned four
directories, three extensions and non-test names only, so a `.js` tool file, a `hooks/` module, a test-named production file, a
symlinked directory or a neutral-named module reading the rollup table with a service-role client all left it green. The prose
claimed the property; the predicate checked a subset (the same shape as the 2026-09-23 learning on predicates narrower than
their prose).

## Solution

- Invert the default: scan every top-level app directory except a short exclusion list, so a new directory is covered unless
  someone names it excluded. Refuse symlinks. Add an arm for the sink's other name (the table), and an arm that fails when
  production code imports a module the scan does not read (test-named files, excluded directories).
- Anti-vacuity by named members and per-directory minimums, not "non-empty"; drive the composed predicate with synthetic
  must-trip rows; a last test that fails if any arm was skipped or emptied.
- Mutation-test the guard on a sandbox copy: 31 injected mutants across two batteries, control green first. The battery found
  its own bug (a reset removed a directory before the row that needed it), so a SURVIVED row is re-run before it is believed.
- Make the ADR list what the pin cannot see, with the compensating control stated at its real scope (the service-role gate
  covers two trees and two identifiers, per file).

## Key Insight

A guard test is a statement about a window. Write the window's complement into the record ("what the pin does not see") in the
same PR, and take the window default from the tree (everything except a reasoned exclusion list) rather than from what you
happened to look at.

## Session Errors

- **Cited "DPIA addendum 13.4: operator signs off the C6 wording" from a seat report without opening the section** — Recovery:
  the verification pass read 13.4 (it covers CLO sign-off and publication order) and the citation was corrected — Prevention:
  open the cited section before writing a citation into a public record; a subagent's paraphrase is a pointer, not a source.
- **Held-number scrub printed a hit but the chained commit and push ran anyway** — Recovery: a follow-up commit removed the line;
  the net branch diff and every commit message are clean; disclosed in the Review-Evidence comment — Prevention: make the scrub a
  gate (`HITS=$(...|wc -l); [ "$HITS" = 0 ] && git push`), never an echo before the push.
- **Fan-out launched through the Workflow tool without the user asking for a workflow** — Recovery: stopped at once and re-run as
  ordinary agents — Prevention: that tool is opt-in by the user's own words; the review fan-out uses the Agent tool.
- **Two seats contradicted each other on whether plugin code runs in-process with a service-role key** — Recovery: read
  `cron-ux-audit.ts` (it `import()`s the bot scripts into the server process; the spawned child has a scrubbed env) —
  Prevention: adjudicate seat disagreements against the source before editing prose.
- **Mutation battery row reported SURVIVED because the previous reset had removed its directory** — Recovery: re-ran the row —
  Prevention: re-run any survivor in isolation before counting it.
- **`git commit` hook-blocked because the shell cwd was the main checkout at evaluation time** — Recovery: cd in a separate call
  first — Prevention: start commit commands from the worktree cwd.
- **A fixture string `"../../docs/x"` in the test made the repo-wide containment census count it as escaping the app, so required `test-webplat` went red in CI** — Recovery: changed the fixture to a single-level `../docs/x` — Prevention: the local targeted run must include `test/repo-wide-containment.test.ts` whenever a new test under `apps/web-platform/test/` contains a `../` run; a file-selected test set cannot see a repo-global census.
- **A review seat ran `git fetch` against a no-git-write brief** — Recovery: harmless (moves a remote-tracking ref); disclosed —
  Prevention: say "no git commands that touch refs, including fetch" in seat briefs.

## Tags

category: test-design
module: apps/web-platform/test/egress-audit-agent-surface-absence.test.ts, ADR-288
