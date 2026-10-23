# Learning: fix-round agents reported "green" on their own files and broke three repo-global gates

## Problem

PR #10892 (masked-dir alert, probe mask creation, apt fixture) went through a 13-seat review panel with no P1, then a
fix round of three parallel implementer agents on disjoint files. Each agent reported its own suites green. The
combined tree then failed three gates none of them had run:

- `scripts/guard-vacuity-floor.test.sh`: the apt agent rewrote its suite's floor from `-lt 25` to `-ne 30`; the
  meta-guard's floor detector parses only `-lt|-le|-ge`, so the file left the promoted set (`no-longer-floor-bearing`).
- `test/repo-wide-containment.test.ts`: the code agent added a vitest file that reads `scripts/` (outside
  `apps/web-platform`) without registering it in `test/repo-wide-suites.ts`.
- `test/sandbox-wrapped-command-runtime.test.ts:151`: a source-pin of the old body of `maskedDirs()` in the probe,
  which the same agent refactored to call `transcriptDir(home)`.

The gates were found by the fix-round panel (two seats ran suites nobody had touched) and by the combined-tree affected
gate, not by the implementers. Two more things went stale between plan and merge: a sibling PR took the "free"
`frequency_minutes = 38` and a sibling README count (the second `origin/main` merge conflicted in the Sentry README and
silently collided on 38).

## Solution

- Fixed each (split the floor into `-lt 36` plus a separate exact `-gt 36`; registered the vitest file; repinned the
  source literal), moved the rule to `frequency_minutes = 39`, recomputed the README counts after the merge, and
  re-ran each failing suite directly.
- The affected gate itself gave no verdict twice: it queued behind sibling worktree runs at load 15-20 until its budget
  expired and ran 0 suites (`budget-deferred`). The direct runs of the named suites were the evidence.

## Key Insight

An implementer's "suite green" is a statement about the files it was given. The repo-global ratchets (vacuity floors,
suite-registration censuses, source-pins on a literal another file defines) reference nothing the implementer edited, so
no file-based test selection finds them. Delegating fixes by file scope makes this worse: the three agents' scopes were
disjoint, and the breakage lived in the seams between them. Two cheap mechanical moves close it: (1) brief fix agents
that editing a floor, a suite registration, or a literal another test pins means running that ratchet by name; (2) the
lead runs the combined-tree gate (or at least `guard-vacuity-floor`, `repo-wide-containment` and a `git grep` of every
changed literal across `test/`) BEFORE spawning the fix-round panel, so the panel reviews a tree that already passes.

## Session Errors

1. **Forwarded plan-phase errors** (apt researcher slow, GitHub TLS timeouts, a plan-edit hook rejecting a line containing
   a forbidden verb, no `spec.md` so `lane:` defaulted). Recovery: retries / reword. **Prevention:** none beyond existing
   rules; all transient or already handled.
2. **`pkill -f` blocked by the self-match hook** while stopping my own queued gate run. Recovery: `source proc.sh;
   kill_mine`. **Prevention:** use `kill_mine <pattern>` for ownership-checked kills; never `pkill -f` from the Bash tool.
3. **`gh issue create` refused twice by the filing gate** (no user-visible consequence; then `Fix-Size: 40 lines / 2 files`
   is inside the inline threshold). Also my `printf >> body.md` in the same Bash call never ran because the hook denied the
   whole command. Recovery: posted the item as a comment on the existing tracker (#10455) instead of a new issue.
   **Prevention:** write a body file in its own call before the filing call; a deferral that fits the inline threshold is
   a comment on the tracker, not an issue.
4. **A Bash command whose text contained a heredoc mentioning a commit was refused by the commit-target hook.** Recovery:
   wrote the file with the Write tool. **Prevention:** write multi-line briefs with Write, not a heredoc in a Bash call
   that also contains git verbs.
5. **Two merge conflicts with `origin/main` found only at panel-spawn time** (ADR-188 append, then the Sentry README plus a
   silent `frequency_minutes` collision). Recovery: resolved both; moved the rule to 39. **Prevention:** the unique-value
   pick (frequency, migration number, ADR ordinal) is provisional until the last merge of `origin/main`; recheck the
   taken-list after every merge (added to the Sentry README convention).
6. **Fix-round commits broke three repo-global gates** (above). Recovery: fixed each and re-ran it by name.
   **Prevention:** brief fix agents on the ratchets by name and run the combined-tree gate before the fix-round panel
   (added to `review/references/risk-tier-and-fix-rounds.md`, "Briefing fix agents and seats").
7. **The affected gate returned `budget-deferred` (0 suites run) twice under sibling load, and one killed run left an
   `AFFECTED_RC=1` that was not a verdict.** Recovery: ran the named suites directly and read their rc files.
   **Prevention:** `ran=- of=-` is no verdict; read the rc file, never the monitor event or the notification exit code
   (the background-notification "exit code 0" was the last `sed`, not the suite).
8. **An agent reported "RED-first not shown"** for tests written together with fixes. Recovery: it proved each guard by
   reverting in a sandbox. **Prevention:** none new; the mutation-proof is the accepted substitute and the report said so.

## Tags
category: workflow-issues
module: soleur:work / soleur:review fix rounds
