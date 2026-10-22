# Ruled by CTO agent, 2026-10-18: PR #10376 (PR-0 of G1, #9294), round 4, three forks

Condensed by the lead from the agent's hand-back (the agent's own file write is a short copy). Read-only investigation; no gate run, no production touched.

## Facts verified by command

- `.github/CODEOWNERS` has a fallback `* @deruelle` and no row for `tests/scripts/trio-baseline.tsv` or ADR-241. Its header says branch protection requiring CODEOWNERS review is a separate repo-admin follow-up, so it is advisory today.
- Rulesets: CI Required (status checks and merge queue), CLA Required, Force Push Prevention. The Copilot review ruleset is disabled. No ruleset has a `pull_request` rule and `main` has no classic branch protection. CI Required and CLA Required carry an OrganizationAdmin bypass.
- Collaborators: one admin and one non-admin. 175 of the last 200 commits on `origin/main` are authored as the owner, so agent work lands under the owner's identity.
- The suite is 3096 lines; the baseline is 112 rows (86 `tier-a`, all dated 2026-11-30, 26 `sink`).
- #10352 is merged (`c896321ce0`); the branch already contains it and both ADR-241 amendments.
- #10458 (PR-1a) touches only `ci-deploy.sh` and its test; its body says merging it is a production apply.
- `git-data-cutover.yml` reaches `ci-deploy.sh` through `dispatch-web-redeploy/track.sh`.

## Fork 1: self-attested lanes (`Allow:`, `Re-date:`, `Reclass:`)

Acceptable as built; no mechanical control in PR-0.

- The suite catches accidental or agent-authored drift. It is not a defence against the author of a PR, who also controls that PR's copy of the suite. The lanes make a widening a named, dated, greppable ADR line instead of a silent edit, and give a legitimate slip a path that does not tempt anyone to weaken the suite.
- A CODEOWNERS row changes nothing while no rule requires code-owner review.
- A required-review ruleset now would block every merge (agents commit as the owner, no self-approval) or be a no-op under the admin bypass.
- Removing `Re-date:`/`Reclass:` moves the same edits into suite constants, which is less visible.
- ADR-241 already states that the lines are self-attested and that "reviewed" is an owner practice, not a gate.

Follow-up (one issue, milestoned to the G1 final PR). Trigger, whichever comes first: a second human with write access merges to `main`; the CODEOWNERS branch-protection follow-up (#3121) is actioned; the final G1 PR. Then, in one change: CODEOWNERS rows for the baseline, the suite and ADR-241, plus a required-code-owner-review rule. Owner residual: whether to turn on required review (changes the merge workflow for all work; needs a second reviewer identity).

## Fork 2: over-built

Uphold the earlier ruling. No cuts, no floor change.

- `tier-b` and `sink` are different proofs; merging them deletes the check that a `tier-b` row without the Tier-B environment is RED.
- The per-row expiry lets PR-2 to PR-4 retire groups on their own dates; the strict date handling and the event table (blocking only on PRs, never on a main push or `ci_not_green`) are what keep the date from stopping tenant deploys.
- `Re-date:`/`Reclass:` are about 63 lines of 3096.
- The 201 mutants each guard a gap a reviewer found; the guard gates a credential able to replace `ci-deploy.sh` on the host.

Discipline: freeze the suite's semantics at this PR. Growth only from a defect found in review or a PR-2 to PR-4 row the plan already names. The `tier-a` machinery is deleted when the final G1 PR reaches zero `tier-a`, `FALLBACK:*` and `ALIAS:*` rows. Owner residual: none.

## Fork 3: sequencing

1. #10352 is merged. PR-2 edits `git-data-cutover.yml` and must be rebased on current `main`.
2. PR-0 (#10376) first: docs, tests and baseline, no deploy effect; the ratchet and the five `@allow` lines live there.
3. PR-1a (#10458) may merge before the rehearsal dispatch only as a normal release and only if: it is deployed through one normal release and the post-deploy check confirms the hosts run the new `ci-deploy.sh`; the `or` render is not yet merged; the owner has not yet named the rehearsal dispatch; no git-data flip or wipe run is in flight. Otherwise it waits until after the wipe (plan D-1). The same rule covers the rest of PR-1 (`hooks.json.tmpl` `or` render, loader narrow mode, `deploy-channel` Terraform).
4. #10352 made the separated wipe need no flip and no soak; the 2026-11-04 date binds `flip_chained` only. The cutover jobs still redeploy through `track.sh` to `ci-deploy.sh`, so the "nothing lands after the rehearsal dispatch" cutoff stays binding for any unit touching `ci-deploy.sh`, the webhook secret or `git-data-cutover.yml`. State which variant is rehearsed in the PR-1a body.
5. PR-2 comes after PR-0 and the PR-1 slices it needs. Preconditions: rebased on `main` including #10352; `deploy_service_token_ids` default equals the live token id; the offline plan fixture shows 0 add, 0 destroy, 1 in-place change; the owner-run hash-equal copy of the trio into `soleur-infra-privileged/prd` is done and a canary reads `source=tier_b`. It must be merged and green before the rehearsal dispatch or wait until after the wipe.

Owner residual: the calendar date of the rehearsal dispatch (and so whether PR-1a and PR-2 go before or after it); authorizing any merge or apply of PR-1a and PR-2; naming the owner-run copy and rotation commands.
