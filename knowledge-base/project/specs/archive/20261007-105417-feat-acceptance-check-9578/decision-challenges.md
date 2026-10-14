# Decision challenges — founder acceptance check (#9578)

Recorded at plan time 2026-10-06 from plan-review (taste and user-challenge items the operator should see). Mechanical fixes were applied to the plan.

## Needs the operator's call

1. **Headless / one-shot reach (CTO, CPO; high, taste).** v1 never creates a check on a headless run, so the commonest autonomous path gets only a banner. The plan keeps it deferred (#9657). Alternative: pull a minimal pre-supplied block into v1.
2. **Brainstorm half of FR1 descoped (user-challenge).** The byte ceiling forces plan-only capture (#9658). The spec says brainstorm and plan.
3. **Step 10.5 reuse by wrapper vs extracting the sandbox into a script (architecture, taste).** The plan reuses the fence through a wrapper (subshell capture). Extraction is cleaner but conflicts with the pinned inline `BWRAP_ARGS` and the window-closure lint. Revisit if Phase 0.3 or Phase 3 shows the wrapper is brittle.
4. **macOS and no-bwrap founders (CTO, user-challenge).** Judgement checks only; an un-sandboxed consented run would contradict ADR-175's fail-closed posture and is not offered.
5. **Roadmap placement (CPO).** #9578 sits in "Post-MVP / Later" and roadmap.md does not mention it; the plan does not edit roadmap.md.
6. **#9577 coupling (CPO).** The homepage demo must not claim a founder check until this ships and #9620 is decided.

## Applied (so the operator can veto)

- Trust anchor: a plan block whose freeze or PR author is not the local operator never runs, in any mode: the command and its author are shown and the run fails (architecture P0, security; changed from show-before-run in the review round, item 10).
- Interpreter verbs only with pinned scripts (DHH P0). A `creates:` field was part of this and was cut in the review round (item 11).
- Output never committed (hash, rc, boolean only); retry cap, CONFIRMED-CHANGE and PASSED-WITHOUT-BASELINE dropped; the only override is interactive accept-anyway.
- Pass wording and the aggregate row name the commit tested and never read as a bare PASS (CPO).

## Added at the work phase

7. **The pass sentence once contained the word "safe" (resolved by rewrite).** The plan pinned a sentence ending "... does not confirm the work is correct, complete or safe ..." AND banned "verified", "proven" and "safe" in every founder-facing string. The CLO ruled the negation out; the sentence was rewritten ("It does not show that the work is correct or complete, or free of problems this check does not look for") and the test exemption was removed. No string contains the three words, with no exemption.
8. **A freeze that follows earlier branch commits outside `knowledge-base/` is a stop-and-ask, not a FAIL (as the plan says), so a pinned script committed on the branch before the freeze reads as an ordering violation.** A pinned script normally already lives on main (the tests land it there); a script created earlier on the same branch needs the founder's answer at ship. Kept per the plan; named here because it will surface for founders whose pinned script is new on the branch.
9. **Phase 0.3 dogfood result (does not trip the stop threshold).** 4 of 5 realistic checks are expressible as runnable commands, so the build proceeded. `node` and `bun` return rc 127 inside the sandbox on mise/asdf installs (PATH `/usr/local/bin:/usr/bin:/bin`, `/home` is a tmpfs), so those two interpreter verbs classify INVALID there; the capture reference tells the founder to prefer `python3` or `bash`.

## Addendum — 2026-10-06 (#9578, CLO wording review of the built text)

> **Supersedes the wording quoted above where it differs.** The CLO ruled the pass sentence's "complete or safe" negation out (no founder-facing string may contain "verified", "proven" or "safe", with no exemption), and edited the first-use notice (network access, public repository, no secrets), the no-sandbox sentences ("did not run on this computer, so nothing was checked"), the prompts for INVALID, UNTRUSTED, OVERRIDDEN and headless stops, and the roll-up lines. The authority is the `WORDING` constants in `plugins/soleur/skills/preflight/scripts/founder-check.py` (`pass`, `first-use`, `no-sandbox`, `no-sandbox-ask`, `invalid-ask`, `aggregate-judgement`, `overridden-line`, `nosandbox-continued`, `headless-stop`, `untrusted-ask`), pinned by `plugins/soleur/test/preflight-founder-check.test.ts`. Decision-challenge item 7 is resolved by rewrite, not by exemption.

## Addendum — 2026-10-06 (the 12-seat review round; supersedes items above where it differs)

10. **UNTRUSTED no longer prompts.** Item "Applied" above said a block whose freeze or PR author is not the local operator needs
    show-before-run interactively. It is now a FAIL that shows the command and its author and runs nothing (ADR-275 addendum, item 2).
    Operator's call if a founder-confirmed run of someone else's command is wanted after all; the cost is that the confirmation is
    the founder approving a command they did not write.
11. **`creates:` is cut** (the work can satisfy a path-exists check by writing the file); baselines of "the new file exists" are not
    supported and are judgement checks.
12. **No interactive continue when the sandbox is missing.** A block present with no sandbox stops the run in every mode.
13. **Disputed finding, kept as built:** `expected` rejects only substitution forms (`$(`, backtick, `${`, `<(`, `>(`) and control
    characters, not every shell-active token. Legitimate expected literals such as `<h1>` or `a|b` contain `<`, `>` and `|`, and the
    file-based interface never types `expected` into a shell word.

## Addendum — 2026-10-07 (second review round; supersedes items above where it differs)

14. **Re-freeze is interactive-only and loud.** `verify --mode` defaults to headless, which stops on a re-freeze; an interactive run shows
    the old and new text. Operator's call if an unattended re-freeze is ever wanted; the cost is that the agent that edits the check
    could then approve its own edit, which is the failure this feature exists to prevent.
15. **The baseline of a re-freeze is a report, not a must-fail test.** The work usually exists by then, so a pass is normal. The
    alternative (refuse a passing re-freeze) dead-ends every check that was corrected after the work was done.
16. **`approved_by` is now required and secret-scanned.** A founder's free-text answer is committed with the plan.
17. **Disputed, kept as built: `rejected-ask` prints a plain-language reason from a closed map and falls back to the record's detail**
    for an unknown code, rather than always printing the developer detail. A new refusal without a sentence is RED in the suite.
18. **Disputed, kept as built:** environmental BLOCK-REJECTED (verb gate unavailable, base unresolvable, not a repository, unreadable
    plan, internal error) offers retry and continue-anyway, not "change the check": the check is not the problem there.
