# Learning: a new refusal marker needs its telemetry arm, and a resumed agent that repeats one status line has stalled for good

## Problem

PR #9674 (slice S1 of the argv-credential sweep) converted four community scripts to refuse a
malformed credential before curl, printing one value-free line, `SOLEUR_CREDENTIAL_REFUSED
script=<name> reason=<r>`. Planning, work (three write-only agents), a green committed-tree gate run
and a 12-seat design and panel review all treated the marker as a new string. Only the
user-impact seat ran `git-lock-marker-telemetry.test.ts`, which walks every `SOLEUR_*` sentinel a plugin
skill script emits and fails when `MARKER_RE` has no arm for it: the required webplat shard would have
gone red on merge. The fix was one alternation arm; the review also falsified the sentence I wrote to
justify it ("a hosted `bsky-community.sh post` refusal reaches Better Stack/Sentry"): the extractor is
wired only into the agent PostToolUse hook, and the hosted content-publisher run carries the refusal in
its fallback issue body.

Separately, three agents stalled in a way the existing Sharp Edge ("a seat whose last block is a
`tool_use` has not delivered") does not name. A write-only fix agent returned the same stale status line
("Violation is RED (0, want 3). Now add test rows, then implement.") after its first run and after each
of two resumes, each resume costing one tool call; the agent-native seat returned nothing, then, respawned
with early-write instructions, wrote only a header. Both resumes and the respawn burned time without
recovering the work.

## Solution

- Registered the marker in `MARKER_RE` with a MIRRORED-NOT-PAGED comment that states what the extractor
  actually scans, and corrected the community skill's claim.
- Took over the stalled lint agent's remaining items by hand (its partial edits were on disk and
  recoverable with `git diff`); did the agent-native seat's three checks directly against the committed tree.
- Routed two bounded edits into definitions: the stall Sharp Edge in `review/SKILL.md` and a
  `plan-sharp-edges.md` bullet for new markers.

## Key Insight

A refusal or diagnostic marker is a member of a closed vocabulary, not a string: adding one has a
registration step in the telemetry extractor, and the check that proves it is a repo-wide drift guard no
selected-suite run references. Run it whenever a diff introduces a `SOLEUR_*` token. And when an agent
returns the same status line after a resume, the third resume is not information: read its partial work
with `git diff`, finish it yourself or respawn with a smaller brief.

## Session Errors

1. **The new marker was not registered in `MARKER_RE`** (found in review, P1). Recovery: added the arm.
   **Prevention:** `plan-sharp-edges.md` bullet: a diff that adds a `SOLEUR_*` marker to a plugin skill
   script must add its telemetry arm and run `git-lock-marker-telemetry.test.ts`.
2. **I wrote an unmeasured claim into a comment and a SKILL.md bullet** (hosted refusal "mirrored to telemetry").
   Recovery: reworded both after the pattern seat falsified it. **Prevention:** already a documented
   class (every causal claim a diff's prose adds needs its falsifying command); the command here was one
   grep of `MARKER_RE`'s consumers.
3. **A resumed fix agent stalled three times; the agent-native seat delivered nothing twice.** Recovery:
   took over by hand. **Prevention:** the review Sharp Edge now names the repeated-status-line signature.
4. **The Phase 4 driver script ran every check as `command not found` (rc 127)** because each `run` line had an
   extra label word. Recovery: noticed the uniform rc and fixed the helper call. **Prevention:** run a
   driver's first check alone before launching the batch.
5. **A scripted `str.replace` of the second driver silently did not land** (the anchor text had been rewritten by
   an earlier `sed`), so three extra checks never ran. Recovery: ran them directly. **Prevention:**
   assert the replacement count (`assert s.count(old) == 1`) in every scripted edit.
6. **I forgot to `git add` the regenerated baseline** (it stayed ` M` after the commit). Recovery: `git status`
   after the commit showed it; committed it separately. **Prevention:** run `git status --short` after every commit.
7. **Hook rejections:** `git stash list` (a habit) was blocked in my shell and in two agents; a markdownlint
   MD038 on my own backtick span. Recovery: removed both. **Prevention:** none needed beyond the hooks.
8. **`soleur:go`'s session-start `.mcp.json` restore ran against a dirty tracked file** (known bug #9622, fixed on
   main by #9655 after this session started), so a local uncommitted `.mcp.json` edit may have been
   overwritten. Recovery: none possible from here; disclosed to the operator. **Prevention:** already
   fixed on main; the session simply predated it.

## Tags

category: workflow-issues
module: review, plan, community-skill
