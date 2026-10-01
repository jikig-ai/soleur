# Learning: a cited sentence is only as good as its paragraph's subject, and "verified" needs the subject quoted

## Problem

PR #9303 deleted the obsolete `cron-gh-pages-cert-state` routine (PR A of two; the disabled Sentry
monitor follows in #9304 because the two-PR rule forbids unrouting and deleting in one apply). The
ADR-194 addendum I wrote said the deletion was fine because "this ADR says deleting it later is fine".
That sentence exists in ADR-194 (line 373), but it sits in a paragraph about the **certificate-reissue**
routine. For cert-state the real support is the "What gets deleted" list (line 307) and Consequence 2,
"detection deliberately retired, not replaced" (line 522).

A ten-seat review split on it: architecture and code-quality read the paragraph and flagged it, while the
git-history seat, asked to verify the addendum's claims, reported "VERIFIED" and quoted the same sentence.
The quote was real and the claim was not supported by it.

Two smaller instances of the same class shipped in the same branch: a test-header comment saying the
disk-io cron's issue handling "is the shared `_cron-shared` plumbing" (only the heartbeat and token mint
are; issue search, file and close are inline Octokit), and the plan's `discoverability_test` probe string
not matching the reason string that shipped (the literal command returned 0, expected 1).

## Solution

- Re-cited the addendum on the lines that actually support it and added the one thing the old sentence
  hid: re-arming is now a `git revert` of the PR, not a boolean flip.
- Replaced the false comment with a claim that needs no sibling check ("not re-tested here").
- Ran the plan's own literal commands at QA: AC1 returned seven files, not six, so the AC was amended
  with the reason instead of quietly loosened; the probe string was corrected and re-run.
- Settled two competing review findings by measurement, not by counting seats: the deleted function had
  no cron trigger at the commit where the #6178 soak population was taken, and 52 function files carried
  one, equal to `POPULATION_SIZE=52`. That dissolved both architecture P2s and a planned post-deploy probe.

## Key Insight

A verification is a claim about a *relationship* (this sentence supports that conclusion), and a seat that
confirms the quote has confirmed only that the text exists. When a record cites a source sentence, the
check is: name the **subject of the sentence's own paragraph** and say whether it is the thing being
justified. The same discipline applies to the probes a plan prescribes: a `discoverability_test` or an AC
command that was never executed is a claim about a command, not evidence.

Convergence is not the tie-breaker when seats disagree about a fact. One cheap measurement (two `git show`
commands and a count) settled in seconds what a vote could not, and it removed a verification step that
would otherwise have been scheduled for after the deploy.

## Session Errors

1. **The brief's file list and monitor counts were partly wrong** (`issue-alerts.tf` has no reference to the monitor; live counts are 60/16/44, not 55/11/44). Recovery: planning re-derived both against the tree. **Prevention:** re-derive every count and file list in a task brief from the tree before dispatching it (covered by the plan-quoted-numbers rule).
2. **A plan write was denied over a single phrase, and filing the PR B tracker needed a `Mandated-By` line.** Recovery: reworded; added the line. **Prevention:** none needed, the guards worked as designed.
3. **The first `git push` was rejected after my own rebase** (remote held only my pre-rebase commits). Recovery: read the rc, verified the remote-only commits were mine, used `--force-with-lease` pinned to the remote sha. **Prevention:** after a rebase, expect a non-fast-forward and verify remote-only commits before a pinned lease, never a bare force.
4. **A `run_in_background` poll was denied by the `background-poll-prefer-monitor` hook.** Recovery: used the Monitor tool. **Prevention:** already hook-enforced (`hr-monitor-not-run-in-background-for-polling`).
5. **`gh api` refused to print a CI job log containing escape sequences.** Recovery: `--allow-escape-sequences`, then strip ANSI. **Prevention:** one-off tool friction; pipe job logs through an ANSI strip from the start.
6. **My ADR addendum cited the reissue routine's sentence as support for deleting cert-state, and the git-history seat confirmed it.** Recovery: re-cited on lines 307 and 522. **Prevention:** when citing a doc sentence, quote the subject of its paragraph; when asking a seat to verify a citation, ask it to quote that subject, not only the sentence.
7. **I wrote "shared `_cron-shared` plumbing" in a test header without grepping the imports.** Recovery: replaced with a claim that needs no sibling check. **Prevention:** a comment that asserts sharing needs the import grep that shows it.
8. **A sweep for the stale "3 target functions" was keyed on phrasing and missed one site.** Recovery: code-quality and pattern seats found it; fixed and the prose made count-free. **Prevention:** grep the claim's subject (the list being counted), not its wording; or remove the number.
9. **The plan's `discoverability_test` returned 0 (expected 1) and AC1 said six files where the command returns seven.** Recovery: corrected the probe, amended AC1 with the reason, re-ran both literally at QA. **Prevention:** routed to `plan-sharp-edges.md`: run every literal command the plan prescribes once before finalizing it.
10. **A soak-probe P2 rested on "probably was never in the population".** Recovery: two `git show` commands and a count showed it was not. **Prevention:** before scheduling a post-deploy verification, check whether git history already answers it.

## Tags
category: workflow-issues
module: inngest cron removal, sentry monitors, review process
