# Decision Challenges — feat-one-shot-6617-6488-retire-doublefire-drop-dark-tables

Surfaced during planning (2026-09-19), headless. Per ADR-084 these are **not** applied silently; `soleur:ship` renders them into the PR body and files them as `action-required`.

## DC-1 (User-Challenge) — split the P7 verdict-filter fix into its own prior PR

**Operator's stated direction:** "Batch two nightly-FAIL follow-through issues in one PR: #6617 and #6488." The plan honours that and carries the `authorAssociation` fix with it.

**The challenge (advisor consult, ADR-083, concurred by the session):** the replacement filter is a durable change to the anti-forgery control #7448 added, on a public repo, and it carries one unmeasured question (does `GET /repos/{owner}/{repo}/collaborators/{login}/permission` return 200 under an installation token scoped `contents: read, issues: write`?) whose fallback is a different architecture (a CODEOWNERS-derived trusted set). Landing it as a small prior PR — using #6617's private-membership comment as the live fixture while that issue is still open — would keep the drop PR's dispatch sequence off a GitHub API permission question.

**Why the plan does not apply it:** the operator asked for one PR, and the A1/A2 commit split already isolates the risk — the P7 change lands in A1, is proven or falsified by the first dispatch, and its fallback lands in the same commit before anything is deleted. The fixture argument also cuts the other way: #6617 must still be open for the fixture to exist, and this PR is what closes it.

**What would change the answer:** the permission endpoint 403ing under `GITHUB_TOKEN` in Phase 2 step 2 AND the CODEOWNERS fallback needing more than a few lines. In that case, split it.

## DC-2 (User-Challenge) — publish the operator's GitHub org membership

**The cause of #6617's permanent red is that `jikig-ai` membership for `deruelle` is private** (`GET orgs/jikig-ai/public_members/deruelle` → 404), so `GITHUB_TOKEN` renders the operator's comments as `CONTRIBUTOR` and every `authorAssociation`-filtered probe drops the verdict. One `PUT /orgs/jikig-ai/public_members/deruelle` would make all four existing filters work with no code change.

**Not applied, and not recommended as the fix:** profile visibility is the operator's personal choice, not an engineering lever, and a code fix that does not depend on it is both cheap and more robust (a future contributor with private membership hits the same wall). Recorded so the option is visible rather than silently foreclosed.

**Operator action if desired:** none required by this PR either way.
