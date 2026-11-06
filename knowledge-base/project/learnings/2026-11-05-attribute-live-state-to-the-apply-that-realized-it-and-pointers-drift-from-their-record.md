# Learning: attribute live state to the apply that realized it, and a record's pointers drift from the record

## Problem

A resume brief for the hosted-Bash follow-ups (#10455) named three top items: a plain-language failure message, a
runtime synthetic with a dead-man arm, and verifying the Slack wake path. Reading the merged PRs that cite the issue
in prose (`#10455 in:body`, state merged) and grepping the literal symptom string showed two were already shipped
(PRs #10546 and #10697, plus the masked-dir alert in #10892) and the issue's checklist had never been ticked. Only the
Slack wake path was open, and it was not a code change: the 2026-10-19 API reads could not tie a Logs alert to a
Slack channel, so the answer had to come from the Better Stack dashboard.

The dashboard read (an incident timeline for a Logs alert, plus the Incidents integrations page) closed the question,
and the follow-through was a docs PR (#12142) recording a dated result across four files. Review then found the new
prose wrong in five ways, all of them in claims the PR itself added.

## Solution

- Probe the premise before the pipeline: the one-shot open-issue collision probes (linked PRs, the prose-`Ref` body
  probe in both states, a literal grep of the symptom string in code) cost seconds and redirected a full
  plan, work, review and ship cycle onto the one item that was still open.
- Verify an alert-delivery fact where the system shows it. Better Stack keeps the Slack integration in the Incidents
  product (`incidents.betterstack.com/team/<id>/integrations`), in single-channel mode; an incident's own timeline
  (`.../incidents/<id>`) lists the Slack post next to each email send. The Telemetry alert editor's "who should we
  alert" control offers only the current team on the free tier, so there is no per-alert Slack target to inspect.
- Write the result as one canonical dated record and label each statement observed or inferred, then state the
  limits (a Slack post is not proof of a phone push; escalation policies stay gated off on the free tier).

## Key Insight

1. **Attribute a live-state fact to the apply that realized it, not to the commit that first wrote the line.** A
   pickaxe on `push = true` names the commit that added the flag to the source (#11260), but the Terraform file's own
   comments record that this apply was refused (HTTP 422, the fourth refusal of the series) and the live alert was
   created later by #11427. Two review seats disagreed on which number was right and both were half right. Neither
   citation was needed: the sentence only had to say that other Logs alerts also arm push, which the file shows.
   Cite the file and drop issue numbers that cannot be re-derived from it.
2. **One canonical record with N pointers drifts into N wordings, and every pointer drops a different caveat.** The
   first panel's top three findings (an overstated "done / verified" status, an ADR heading saying "observed" for
   all alerts, a pointer without "not a guaranteed page") were one cause: shortening the record at each site lost the
   observed-versus-inferred qualifier. Give pointers one fixed string that carries the single caveat that changes what
   a reader does next, and keep the scope words in one column only.
3. **A flag claim written as "unchanged" must name its population.** "Each alert's flags are still email-only" was
   true of the two alerts the runbook describes and false for three others that arm push, and it was copied from the
   plan without re-reading the Terraform. Scope the claim to the alerts it was measured on.
4. **A seat disagreement on a fact is settled by measurement, not by weighing the seats.** One `git log -S` plus the
   file's own comments resolved a contradiction that two agents each stated confidently.

## Session Errors

1. **The resume brief's headline items were stale (two of three already shipped; the issue checklist never ticked).**
   Recovery: the collision probes and merged-PR body reads before creating a worktree; the pipeline was re-pointed.
   **Prevention:** already covered (one-shot Step 0a.5 prose-`Ref` body probe; the resume-brief learning of
   2026-09-18). No new rule.
2. **`gh issue close 10477 --json state` failed** (`unknown flag`) while the comment had already posted; the issue
   stayed open. Recovery: re-ran without the flag and read the state back. **Prevention:** one-off; verify state with
   a separate read after a write.
3. **A scripted splice anchored on the first occurrence of a bold phrase that also appeared earlier in a pointer
   sentence the same batch had just added.** It replaced the wrong span in `canary-probe-set.md`; a later
   `count == 1` assertion on a different anchor aborted the batch. Recovery: `git restore --source=HEAD --worktree`
   (source named), re-ran with an anchor that includes the paragraph's own opening `\n\n**`. **Prevention:** assert
   `count == 1` on every anchor in a scripted edit before slicing from `index()`; an anchor phrase that your own batch
   introduces elsewhere is no longer unique (already stated in `work/SKILL.md`; not re-added).
4. **New prose shipped five unmeasured claims** (unscoped "Unchanged" flags, a wrong issue number for the arming
   change, an unrecorded "Current team" label, "done / verified" for one observed alert, a heading saying "observed"
   for all). Recovery: five review seats found them; the fixes were applied and re-verified. **Prevention:** run the
   falsifying command for every sentence a diff adds before writing it (already the standing rule in the
   work and review skills; this session is another instance).
5. **`git push -q | tail -2` reported `PUSH_RC=0` after a remote rejection.** The printed `[remote rejected]` line made
   the failure visible, and the re-run with the real exit code succeeded (transient). **Prevention:** capture the
   exit code of the command that matters on its own line (already a rule).
6. **A process-list check using `ps … | awk '… test-all.sh'` was blocked by the self-match guard hook.** Recovery:
   used `proc.sh list_runs`, which resolves ownership by cwd. **Prevention:** one-off; the guard worked as intended.
7. **Playwright: a guessed Telemetry URL returned 404, a dropdown click was intercepted by its overlay input, and
   leaving the unsaved alert editor raised a `beforeunload` dialog that made the next navigation hang for 60 s.**
   Recovery: read the nav links from the DOM; clicked the overlay's input; accepted the dialog with the dialog tool.
   **Prevention:** after opening an editor to read it, expect a `beforeunload` prompt on leave and handle it with
   `browser_handle_dialog` before navigating (recorded here and in the dashboard-reading notes above).
8. **The affected-gate selection preview produced no output for over 6 minutes (and 40 s again when re-measured)
   while a sibling worktree's full gate had held the runner for about 2.6 hours.** I could not attribute the delay:
   the runner's own comments say `--print-selection` takes no lock. Recovery: stopped my own run with `kill_mine`
   (foreign pids refused) and substituted the suites that read the touched runbooks, lint and markdownlint, disclosed
   in the review evidence. **Prevention:** unresolved and unmeasured; not filed because the cause is unknown.
   If it recurs, capture `--capacity` output and a `/proc/<pid>/wchan` read at the 60 s mark before filing.
9. **Two Stop-hook rejections for ending a turn on a forward-looking sentence ("I'll synthesize…") with the work
   not done.** Recovery: did the pending step, or ended with a `Paused:` sentence naming the external event.
   **Prevention:** already hook-enforced (`unkept-promise-hook.sh`); when waiting on background agents, state the wait
   as `Paused: <event>` rather than a commitment.
10. **The dedup ledger was persisted after the fixes were applied**, not before fix dispatch as the fix-round contract
    requires. Recovery: persisted it before the fix-round seats ran. **Prevention:** one-off ordering slip; the
    contract text is already explicit.

## Tags

category: workflow-issues
module: knowledge-base/engineering/operations (runbooks, ADR-218), review pipeline
