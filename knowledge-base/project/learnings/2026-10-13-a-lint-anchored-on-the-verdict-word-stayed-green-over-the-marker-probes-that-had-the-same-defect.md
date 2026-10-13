# Learning: a lint anchored on `RESULT:` stayed green over the marker probes that had the same defect, and "same code, two tokens" is the cheapest way to prove a visibility bug

## Problem

The daily follow-through sweeper reported `FAIL: 10 push run(s) were elided with no activation on record` on the ADR-276 S2 tracker (#9818) every day from 2026-10-11, although the operator had posted `S2-ACTIVATED: 2026-10-11T09:48:17Z` on that tracker. The S2 and S3 soak probes (`ci-push-dedupe-soak-9512.sh`, `ci-draft-light-soak-9728.sh`) trusted a marker comment by `author_association IN (OWNER, MEMBER, COLLABORATOR)`. That field is computed against the READING token, so under the sweeper's `GITHUB_TOKEN` a private org member reads as `CONTRIBUTOR` and the marker was dropped. The repo had fixed this exact defect once for `RESULT:` verdict probes (#6617, #8389: `scripts/lib/trusted-verdict.sh`, trust from the collaborator permission endpoint) and wrote a lint for it (rule 4 of `scripts/lint-followthrough-varq-ban.sh`). The soak probes were written afterwards and passed that lint.

Three things made it survive:

1. **The lint's anchor was the verdict word.** Rule 4 fires on "reads issue comments AND branches on `RESULT:`". A marker probe branches on `S2-ACTIVATED:`, never on `RESULT:`, so it was invisible to the rule that existed to catch it. The rule's own header says the property is the ABSENCE of the right mechanism, yet its trigger was a spelling of one family of consumers.
2. **The sibling was live but masked.** The S3 probe carried the identical filter. Its daily sweeper comment FAILed earlier, on an unrelated stalled PR (#9707), so its marker-dependent FAIL never rendered. A defect that sits behind another failure is not a defect that is absent.
3. **Review did not catch it.** The two PRs that introduced the filters (#9808, #9885) merged with zero formal reviews and no mention of the lib; there is no code-owner enforcement on the probe files (CODEOWNERS binds them, no ruleset requires the review).

## Solution

- Give the trust decision one chokepoint with two views. `trusted_verdict_comments` (`{t,b}` per trusted comment, `t` = `createdAt`) joins `trusted_verdict_bodies`, both projections of `_trusted_verdict_core`; marker probes keep the per-comment time their ordering needs (S3's CONFIRMED-before-ACTIVATED) and an unreadable trust decision stays rc 2, never "no marker".
- Widen the lint on BOTH axes. Rule 5 bans the spelling (`author_association`, `authorAssociation`) on executable lines with its own counter, floor and regex canary; rule 4's anchor now includes the `S<n>-...` soak markers, and its lib-call denominator accepts the new view so migrating a probe does not shrink the corpus the floor counts.
- Check the projection, not just the read. The S3 probe's `jq -r '.b'` had no failure check: an empty projection after a jq failure erases every marker and reproduces the very false FAIL being fixed.

## Key Insight

- **A lint's trigger must be the property, not the first consumer family that motivated it.** If the rule says "no comment may decide an exit code without the trusted lib", anchor it on the decision (a marker or verdict branch of ANY family), then add a spelling ban for the known-bad mechanism as a second, independent net. Each net needs its own non-vacuous counter: a bare `find | wc -l` is byte-identical to the counters of rules whose floors fire first, so its own floor is unreachable, and a pattern that is quietly neutered counts files happily; a regex canary that must match both spellings is what notices.
- **"Same code, same repo state, two tokens" is the fastest proof of a token-visibility bug.** Running the unmodified probe locally under the operator token returned `NOT YET: 82 elided run(s)` while the sweeper token returned the false FAIL. No setting changed, nothing was posted, and the diff between the two readings is the defect. The sweeper's own run log is the second witness: a run that reaches a probe's "no verdict yet" arm rather than its resolution-failure arm shows the permission endpoint answered under `GITHUB_TOKEN`.
- **A masked sibling is still live.** When a defect is found in one probe, grep the whole class (`git grep -niE 'author_?association' scripts/followthroughs`), then check WHY the sibling has not reported it before treating it as latent.
- **A mirrored mutation tree is part of the test.** Once the probes source the lib by relative path, a lone mutant copy in a temp dir resolves nothing, every helper call returns 127, `|| fail_api` turns every row red, and every mutant reads as "caught". Build the tree with the lib symlinked, then prove it with an identity copy (zero reds across the row set) and a copy with the symlink removed (at least one red).

## Session Errors

- A python edit script written as a shell heredoc (`<<'EOF'`) embedded test fixtures that themselves used `cat <<'EOF'`, so the shell ended the script at the first fixture terminator and executed the rest of the text as commands (every write was refused because the fixture directory variable was empty, so nothing landed). Prevention: when generated text contains heredocs, write it to a file first and have the script read the file, or use a terminator that cannot occur in the payload.

## Tags
category: workflow-issues
module: followthroughs, scripts/lib/trusted-verdict.sh, scripts/lint-followthrough-varq-ban.sh
