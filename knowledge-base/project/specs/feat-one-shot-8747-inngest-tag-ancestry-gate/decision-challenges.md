# Decision challenges — feat-one-shot-8747-inngest-tag-ancestry-gate

Recorded headless during `soleur:plan` (one-shot). Each item is taste or user-challenge; the plan follows the operator's stated direction by default.

## 1. User-Challenge — strict commit ancestry vs. the de-facto tagging practice

- **Operator direction:** refuse any `vinngest-v*` tag whose commit is not reachable from `origin/main` (#8747).
- **Finding:** 16 of the last 16 tags (`v1.1.26`–`v1.1.39`) were cut on PR-branch commits. Squash-merge makes those commits unreachable forever. GuardA (#7695) drove this practice, because tagging the PR commit was the only way to get a carrier-changing PR green before merge.
- **Plan default (the operator's direction):** implement strict ancestry. The new flow is merge first, then tag the squash-merge commit on main, then publish, then auto-bump.
- **Cost:** main's GuardA is red from the merge until someone tags main (`main-health-monitor` may file `ci/main-broken`). Pre-merge candidate images are gone (#8781). A tag cut out of habit on a PR branch turns AC6 red repo-wide until it is deleted (#8782 fixes this).
- **Alternative the operator may prefer:** a content-coherence invariant instead of commit ancestry. It would accept a tag whose baked carriers are byte-identical to main's at bump time. That keeps in-PR tagging possible, but it cannot stop a publish of unmerged code.

## 2. Taste — fold a minimal #4326 (auto-mint the tag on a carrier-changing push to main) into this PR

- CTO and the advisor consult both flagged the longer red window on main. #4326 closes that window without anyone having to act.
- **Plan default:** keep it separate. It needs a new tag-minting workflow authenticated with an App token (tags pushed with `GITHUB_TOKEN` do not trigger workflows), version computation, and its own tests and ADR. The plan comments on #4326 to raise it.

## 3. Taste — GuardA as a warning (not a failure) on `pull_request` runs whose own diff changes a baked carrier

- This came from the CTO. It removes the red that is now expected on every carrier-changing PR, and it stays failing on main.
- **Plan default:** not in this PR. It weakens a guard with an anti-vacuity inventory. The better fix is #4326 plus #6766 sequencing: GuardA must not become a required check before auto-minting exists, or every carrier-changing PR deadlocks.
