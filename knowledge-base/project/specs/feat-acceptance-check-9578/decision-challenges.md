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

- Trust anchor: a plan block whose freeze or PR author is not the local operator never runs headless and needs show-before-run interactively (architecture P0, security).
- Interpreter verbs only with pinned scripts; `creates:` only with non-interpreter verbs (DHH P0).
- Output never committed (hash, rc, boolean only); retry cap, CONFIRMED-CHANGE and PASSED-WITHOUT-BASELINE dropped; the only override is interactive accept-anyway.
- Pass wording and the aggregate row name the commit tested and never read as a bare PASS (CPO).

## Added at the work phase

7. **The pinned pass sentence contains the word "safe" (wording conflict inside the plan, for the CLO).** The plan pins the pass sentence ("... does not confirm the work is correct, complete or safe ...") AND says no output string may contain "verified", "proven" or "safe". Both cannot hold literally. Kept: the sentence exactly as the plan wrote it (it is the legal-reviewed text, and dropping "or safe" would weaken the disclaimer), with the ban tested as "no string *claims* verified, proven or safe" — the one negation inside the pass sentence is the single exempt phrase in `preflight-founder-check.test.ts`. Alternative: drop "or safe" from the sentence. The CLO wording review (plan Phase 6.4) should settle it.
8. **A freeze that follows earlier branch commits outside `knowledge-base/` is a stop-and-ask, not a FAIL (as the plan says), so a pinned script committed on the branch before the freeze reads as an ordering violation.** A pinned script normally already lives on main (the tests land it there); a script created earlier on the same branch needs the founder's answer at ship. Kept per the plan; named here because it will surface for founders whose pinned script is new on the branch.
9. **Phase 0.3 dogfood result (does not trip the stop threshold).** 4 of 5 realistic checks are expressible as runnable commands, so the build proceeded. `node` and `bun` return rc 127 inside the sandbox on mise/asdf installs (PATH `/usr/local/bin:/usr/bin:/bin`, `/home` is a tmpfs), so those two interpreter verbs classify INVALID there; the capture reference tells the founder to prefer `python3` or `bash`.
