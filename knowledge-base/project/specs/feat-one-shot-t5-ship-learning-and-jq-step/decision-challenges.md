# Decision Challenges — feat-one-shot-t5-ship-learning-and-jq-step

Challenges raised against the operator's stated direction, per ADR-084. Both were surfaced to the
operator during the run and both were **resolved by the operator**, not taken on the plan's own
authority.

---

## §D1 — deliverable A's premise did not survive verification (User-Challenge)

**Operator's stated direction.** *"One file in `knowledge-base/project/learnings/`, closes the
workflow-gate obligation"* — a ship-phase learning capturing the T5 mutation-arm counted-skip work
merged as `45ea9f7e9`.

**Challenge.** The obligation was already discharged. That merge shipped **two** learning files of
its own:

```
$ git show --name-only --format='' 45ea9f7e9 | grep 'project/learnings/'
knowledge-base/project/learnings/2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md
knowledge-base/project/learnings/2026-08-19-i-hardened-my-verifier-twice-and-its-sample-was-still-a-sample.md
```

Writing a third file on the same material would create the drift hazard the 08-16 file names in its
own words: *"duplicating them would create two copies that can drift."* No outstanding-obligation
tracker exists in the repo, which is why the discharged state was not visible at brief time — a
gap filed separately under §D4.

**Resolution — operator upheld the challenge (2026-08-19).** Presented three options: re-scope,
drop deliverable A entirely, or write the T5 file as literally briefed. Operator chose **re-scope**.
The file's subject is the CI package-install-hang class — genuinely uncovered, and the class
deliverable B fixes. The T5-restatement fallback is retired and must not be taken by review.

**Deliberately not bundled.** The "obligation already discharged" meta-finding is carried here and
in the PR body, not in the learning file. Bundling two unrelated subjects breaks the corpus
convention of one narrative per file and makes neither discoverable.

---

## §D2 / §D3 — deliverable B widened, and replaced rather than deleted (User-Challenge)

**Operator's stated direction.** *"Delete the Install jq step... One line in
`skill-security-scan-pr-trailer.yml`"*, with the explicit pre-authorization *"unless the review
phase argues otherwise."*

**Challenge, two parts.**

**(a) A bare deletion would have been verified by nothing.** Every `jq` consumer in
`skill-security-scan-pr-trailer.yml` sits behind `if: steps.diff.outputs.no_new_skills == 'false'`.
This PR adds no SKILL or agent files, so all of them skip and the gate reports `success` having
never run `jq`. A green check on the deletion PR would have been indistinguishable from a green
check on a runner where `jq` had been removed. Replacing the step with an unconditional
`jq --version` assertion is what makes the green mean something — and it removes the file's only
unpinned supply-chain input, in a file whose other actions are SHA-pinned.

**(b) The case for staying narrow dissolved once (a) was established.** The original argument for
one file rested on blast radius — only `pr-trailer` is a required check. That establishes different
*urgency*, not different *correctness*. What silently propped it up was a verification asymmetry:
the narrow change looked self-verifying while widening looked post-merge-only. Since the narrow
change was not self-verifying either, the marginal verification cost of widening is exactly zero.
Leaving two known-defective copies also preserves a copy-source: the next `skill-security-scan-*`
workflow will be authored by copying one of them.

**Resolution — operator approved both (2026-08-19).** Presented against the alternatives of
"delete, `pr-trailer.yml` only" and "replace, `pr-trailer.yml` only". Operator chose **replace
across all three workflows**. The four `if:`-guarded `jq` call sites remain out of scope on any
reading.

---

## Not a challenge — recorded for completeness

**AC3 was amended at `/work`, not challenged.** It asked for `actionlint` to exit `0` on all three
workflows; `origin/main` already exits 1 with 11 pre-existing shellcheck findings in scan steps this
change does not touch, so no implementation could have satisfied it. Re-keyed onto "adds no new
finding" and verified: 11 at base, 11 at head, `diff` empty, none citing the new step. This is a
plan defect corrected inline, not a deviation from operator direction.

---

## Standing constraint

**This PR closes no issues.** 7572, 7574 and 7613 are context and must stay open. Verified against
the PR body *and* every commit message — this repo squash-merges, so a keyword in a commit body
auto-closes even with a clean PR body, and GitHub's parser is negation-blind.
