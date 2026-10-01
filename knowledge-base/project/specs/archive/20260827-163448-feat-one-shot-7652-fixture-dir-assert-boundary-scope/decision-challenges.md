# Decision Challenges — feat-one-shot-7652-fixture-dir-assert-boundary-scope

Surfaced by `plan-review`, not auto-applied. Each entry challenges the operator's stated direction,
so per ADR-084 it is recorded here for the operator to decide rather than silently applied.

## UC-1 — Split #7652 into two PRs

**Operator's stated direction (the default).** One PR, closing #7652, carrying both instances the
issue filed together.

**What the reviewers said.** Three of eight consults independently recommended splitting: the
boundary widening (detection) and the operand/CWD work (prevention) are separable, and the plan
itself notes the boundary work is independently shippable.

**Why they argued for it.**
- The two halves have different risk profiles. Prevention introduces no new exposure; detection
  introduces the credential-disclosure surface (R2) and the false-accusation surface (R3). Those
  should not ride into main on the urgency of the fix they are not delivering.
- Review load: one PR would carry two mechanisms, three guard contracts and ~15 acceptance criteria.
  Nobody holds both halves in their head, so nobody reviews either.
- **The strongest argument, and it inverts the obvious order:** the boundary *is* the detector for
  this family. Landing it first means it is live and watching while the second PR edits fixture
  suites en masse — precisely the window in which a fixture change is most likely to write to the
  live repository. Bundling them means the detector arrives only after the riskiest editing is done.

**Recommended shape if accepted.** PR-A = the boundary (Phases 0 + 2), `Refs #7652`. PR-B = CWD
isolation, the residual assertion and the scanner (Phases 1 + 3 + 4), `Closes #7652`. Only PR-B
carries the closing keyword, so #7652 is not closed while half of it is unfixed.

**Why it was not applied.** It changes operator-stated scope, which is never a Mechanical class.
The plan is written so either path works: the phase order already puts the boundary first, and
Phase 0 step 7's observe-only full run is the gate on whether the boundary half is safe to ship
before the sites are fixed.

**Decision:** _resolved by the pipeline runner, 2026-08-26 — **keep one PR, boundary-first**._

This is a technical fork (`hr-technical-fork-is-not-an-operator-question`): the operator is
non-technical, the outcome they asked for — #7652 fixed — is identical either way, and the
reviewers' arguments are about detector sequencing and review load, neither of which is theirs to
weigh. Resolved here rather than escalated.

The split's strongest argument is accepted on its merits and satisfied by ordering rather than by
splitting. The window it protects — fixture suites being edited en masse while no detector watches
— is a **local working-tree** window, not a post-merge one: the mass edit happens in this worktree,
and `test-all.sh` runs from the working tree, not from `main`. So committing Phase 0 + 2 (the
boundary) before Phase 1 touches its first fixture puts the detector live exactly when it is
needed. Merging it to `main` first adds nothing to that protection.

What the single-PR path gives up is the review-load argument, which is real: two mechanisms, three
guard contracts, ~15 acceptance criteria in one diff. Mitigated by keeping the two halves in
separate commits so they can be reviewed independently, and by Phase 0 step 7's observe-only full
run gating the boundary half before any fixture is edited.

What it avoids is a second full review → QA → ship cycle, which the operator pays for in API
credit and which buys no additional safety given the local-window analysis above.


## UC-2 — the plugin-local-runner scope-out rests on the wrong precondition

**Recorded 2026-08-27, after the review panel.**

`plugins/soleur/test/fanout-suite-scope.test.sh` is a SHIPPED file that now does
`cp "$REPO_ROOT/scripts/lib/repo-write-boundary.sh"` — an UNSHIPPED path. That was scope-outed on
the stated ground that *"no shipped path executes them (there is no plugin-local runner)."*

**That precondition is false, and it was verified false rather than argued.**
`plugins/soleur/scripts/grok-pre-push-gate.sh` IS shipped and DOES `cd "$REPO_ROOT"` then
`bash scripts/test-all.sh`. What actually protects the delivered plugin is that its `REPO_ROOT`
resolves to the marketplace cache root, which contains no `scripts/` directory — so the invocation
fails to find the runner at all. That is a **path-resolution accident**, not the absence of a
runner, and it is a materially weaker precondition than the one recorded.

**Disposition: the scope-out stands, the reason is corrected.** The failure mode is unchanged and
fails CLOSED (`cp … || return 1` → `exit 2`), and the identical unshipped-dependency shape already
existed for `test-relevance-paths.sh` and `test-contention.sh`, so this adds no new class. What
changes is that the recorded justification now names the real protection, so a future reader who
relocates `grok-pre-push-gate.sh` or adds a `scripts/` directory to the shipped tree can see that
this assumption is what they are breaking.
