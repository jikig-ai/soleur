# Decision challenges — feat-one-shot-7716-7717-7718-supabase-followups

Raised during planning, in a headless run, so surfaced here rather than asked. Per ADR-084,
the operator's stated direction is the default and each of these is recorded, not applied.
`ship` renders this file into the PR body and files it as an `action-required` issue.

---

## DC-1 — CPO recommends shipping the statutory workstream (#7717) as its own PR

**Operator's stated direction.** One `/soleur:one-shot` over `#7716, #7717, #7718` — three
follow-ups from one merged PR, drained together.

**What the challenge is.** The CPO domain leader recommends splitting `knowledge-base/legal/**`
out as a standalone PR that ships first, and gives four reasons in descending strength:

1. **The plan's own rebuttal dissolves the reason to bundle.** The plan keeps the legal work
   in this PR on the ground that the review panel is composed by *label* — `compliance/critical`
   pulls CLO, CPO and `user-impact-reviewer` — rather than by file type. That is correct, and
   it travels to a standalone legal PR just as well. So bundling buys zero review-quality
   benefit while keeping every coupling cost.
2. **Divergent rollback shape** — the argument neither #7717 nor this plan raised, and the
   strongest one. The register's amendment contract is additive-only dated brackets under
   `status: draft-requires-counsel-review`; in a legal artifact a revert is itself a recorded
   event. The engineering half promotes a linter into the required `test` aggregator for the
   first time. If that reds after merge and someone reaches for `git revert`, **reverting an
   engineering failure silently retracts a statutory record.**
3. **A concurrent editor on the same file.** #7670 is open, edits `article-30-register.md`
   PA-7/PA-1, and carries its own boundary forbidding side-effect rewrites. One register, an
   additive-only contract, two in-flight edits.
4. **Priority and milestone mismatch.** #7717 is `priority/p1-high` in *Phase 4: Validate +
   Scale* (due 2026-05-01, overdue). #7716 is `p3-low` and #7718 `p2-medium`, both Post-MVP.
   Bundling makes the P1 inherit their schedule. Shared provenance is not a coupling.

**What the plan first proposed, and why it does not work.** The draft kept all three issues in
one PR and mitigated the rollback argument by making Phase 1 a self-contained first commit,
"independently revertable without touching the engineering commits". **That mitigation is
false on this repo's merge path, and the review caught it.** `ship` queues
`gh pr merge <number> --squash --auto`, and `origin/main`'s history carries no per-PR merge
commits — a squash collapses all seven phases into a single commit on `main`. There is no
independently revertable statutory commit. Reason 2 above therefore stands unmitigated: a
revert of a red orphan-linter promotion would retract an Art. 33(5) statutory record, in a
repo whose register amendment contract makes a revert itself a recorded event.

**What the plan does instead.** Keeps all three issues in this PR, per the operator's stated
direction — splitting operator-requested scope is never a decision this pipeline makes on its
own — while recording plainly that the coupling is real and unmitigated rather than claiming a
mitigation that the merge path does not support. Phase 1 remains a separate commit for
*readability* of the statutory diff, which is a genuine benefit; it is no longer offered as a
rollback boundary, because it is not one.

**What the operator would need to decide.** Whether to accept an unmitigated revert coupling
between a statutory record and a CI-guard promotion, or to re-scope this branch to #7717 alone
and carry #7716 + #7718 to a follow-on PR (this plan's engineering design is complete and would
transfer intact). **Two independent reviewers reached the same recommendation**, and the second
one falsified the mitigation the first had been offered.

**RESOLVED 2026-09-03 — operator chose the split.** Asked directly, before `/work` spent any
implementation budget, the operator selected *"Split #7717 into its own PR"*: this branch
re-scopes to W6 alone and ships first (it is the overdue P1), and #7716 + #7718 + #6489 follow in
a second PR built from this same plan, whose engineering design transfers intact.

Both reviewers are therefore upheld. The unmitigated coupling in reason 2 is dissolved rather
than accepted: the statutory record and the CI-guard promotion no longer share a squash commit,
so a revert of either cannot retract the other. Reason 3's concurrent-editor race with #7670 on
`article-30-register.md` narrows to one PR touching the register, and Phase 0.10 was added to
re-read it against #7670's head before editing. Reason 4's schedule inheritance disappears with
the bundle.

Scope ownership is recorded in the plan's §Scope table; this branch's `tasks.md` carries the
in-scope list only, and Phases 2–6 are preserved verbatim in that file's §Deferred to the follow-on PR section.

---

## DC-2 — CTO reframes what the ADR is actually about

**Plan's position.** ADR-200 (provisional) records the C4 `supabaseMgmtApi` addition, with the
promotion route as supporting detail.

**Challenge.** The CTO holds that the consequential decision is the promotion route itself:
this PR establishes a precedent that a **content-scoped gate may ride the already-required
`test` aggregator instead of minting a public-ABI status context**. That precedent — and the
widened ALLOWED_PATHS trigger condition it depends on — is what a future author needs from the
record; the C4 element is a one-line diff.

**Disposition.** Accepted into the plan (the ADR's primary subject is now the promotion route).
Recorded here because it changes what the plan told the operator it was deciding.

---

## DC-3 — the deprecated-endpoint waiver never expires, and becomes load-bearing on merge

**What the challenge is.** `scripts/lint-supabase-deprecated-endpoints.sh` compares its waiver
field only against the literal `NONE`; there is no date arithmetic anywhere in the script. The
`advisors/security|WAIVED-2026-08-26` waiver therefore never lapses. While the guard was
advisory that was tolerable. Once it is merge-blocking, a deprecated vendor path is permanently
exempt from a merge gate with no mechanism that will ever revisit it.

**Why the plan does not add an expiry.** A hard expiry would red CI on a date certain and force
a migration the vendor has not made possible — `advisors/*` has no successor endpoint and no
announced sunset. The archived migration plan rejected exactly this for exactly this reason.

**Consequence the operator should see.** The deferred spec-diff poller (#7716 part 2) is now
the **only** mechanism that would ever surface a successor or a sunset date for this waiver. It
is designed and unbuilt. Its tracking issue is filed by this plan and says so.
