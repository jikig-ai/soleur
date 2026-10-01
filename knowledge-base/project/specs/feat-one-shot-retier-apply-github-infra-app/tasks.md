# Tasks: move apply-github-infra and entrypoint_audit off the evicted soleur-ai key

Plan: `knowledge-base/project/plans/2026-10-01-fix-retier-apply-github-infra-app-identity-plan.md`
(Ref #8209). UNTRUSTED-CI (`.github/workflows`), so the PR auto-merges only. The single production
action is the authorized post-merge no-op dispatch of `apply-github-infra.yml`.

## Phase 0: Tracking

- [ ] 0.1 File the P1 follow-up issue with the title, body, labels and milestone in plan Phase 0.1.
  The title must contain "Repository rule violations". The body must carry the `depends_on` /
  ordering requirement, the expected plan, and the production-apply authorization request. Record
  its number for the ADR, the README and the PR body.

## Phase 1: RED census (before code)

- [ ] 1.1 In `tests/scripts/test-infra-privileged-tier-census.sh`, row G4e:
  - change the live floor `>= 3` to an exact `== 1`;
  - pin the fixture tree to `== 1` as well (it has one reader, `appkey.yml`);
  - add the dated comment and the sunset note.
- [ ] 1.2 Add G4e's tier clause: no reading site may sit in a job whose `env_arms` intersect
  `TIER_B_ENVIRONMENTS`. Walk `doc["jobs"]` for the clause and treat composites as job-less.
- [ ] 1.3 Add mutants:
  - `g4-e3-second-reader`, which RED via the pin;
  - `g4-e4-tier-b-reader`, which gives `appkey.yml` `environment: infra-privileged` and a non-PR
    trigger and RED via the tier clause;
  - optionally `g4-e5`, which deletes the only read and REDs at 0 != 1.
- [ ] 1.4 Run the census. Confirm the live tree is RED with 3 sites and the tier clause names
  `apply-github-infra.yml` and `apply-web-platform-infra.yml` (AC7 evidence).

## Phase 2: Workflows (GREEN)

- [ ] 2.1 `apply-github-infra.yml`:
  - delete `Fetch GitHub App credentials from Doppler`;
  - add the `mint-infra-app-token` step (`id: mint`) before `Extract backend credentials`, with
    installation `166065653`, `{"administration":"write"}` and `soleur,soleur-marketplace`.
- [ ] 2.2 Rewrite the post-apply verify:
  - set `env: INSTALL_TOKEN: ${{ steps.mint.outputs.token }}`;
  - delete the JWT mint, the exchange and the PEM trap;
  - fail closed on an empty token;
  - keep the Steps 3–5 assertions;
  - rewrite the comments that are now false.
- [ ] 2.3 Add the final step `Revoke the soleur-infra token`
  (`if: always() && steps.mint.outputs.token != ''`) as a best-effort `DELETE /installation/token`.
- [ ] 2.4 Make the comment-only edits: the header `Auth:` bullet, the import-step installation scope
  note, and the verify-step comment.
- [ ] 2.5 `apply-web-platform-infra.yml::entrypoint_audit`:
  - delete the job-level `INSTALLATION_ID` env and the inline App mint;
  - rewrite the post line as `gh issue comment "$AUDIT_ISSUE" --body-file /tmp/audit-body.md`;
  - add `GH_TOKEN: ${{ github.token }}` to the step `env:`.
- [ ] 2.6 Re-run the census until it is green with every mutant RED. Set `MUTANT_FLOOR` (exact) and
  `FLOOR` to the measured counts, with dated notes. `CENSUS_ROWS` stays 38.
- [ ] 2.7 Run the other suites and checks:
  - `test-mint-inngest-bootstrap-tag.sh`;
  - `test-bump-inngest-bootstrap-pin.sh`;
  - `test-preapply-entrypoint-gate.sh`;
  - `plugins/soleur/test/workflow-file-size.test.ts`;
  - the workflow lints: actionlint, `lint-workflow-step-env-refs.py`,
    `lint-workflow-local-action-checkout.py`, `lint-workflow-issue-write-scope` and the SHA-pin lint.
- [ ] 2.8 Run the AC1 grep and the AC5 checks.

## Phase 3: Records

- [ ] 3.1 Add the ADR-241 dated section (2026-10-01). Leave the D5 Statuses row unedited.
- [ ] 3.2 Add one-line dated notes to `infra-credential-tiers-8209.md` (the Group-1
  `::entrypoint_audit` row, and the Group-2 `apply-github-infra::apply` row with the 422 remedy
  line). Add the same to `apply-web-platform-infra-job-rationale.md` §legacy-app-key-evicted.
- [ ] 3.3 Update `infra/github/README.md`: the Phase 0 auth paragraph, and the bypass-coupling known
  gap with its follow-up link.
- [ ] 3.4 Edit the `.github/actions/mint-infra-app-token/action.yml` `description:` (the inline-copy
  count, and apply-github-infra as a consumer).
- [ ] 3.5 Update the `model.c4` `github -> soleurMarketplace` edge (identity and reader count) and
  the `soleurMarketplace` element's known-gap clause. Then run `bash scripts/regenerate-c4-model.sh`,
  `c4-model-freshness.test.sh` and `c4-count-parity.test.sh`.

## Phase 4: Ship

- [ ] 4.1 Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`. At least one commit
  message carries a line that is exactly `[skip-web-platform-apply]` (AC3).
- [ ] 4.2 Run the AC8 merge-base path check; it must print nothing.
- [ ] 4.3 Write the PR body:
  - line one: "Does merging this alone mutate production? No", with the reason;
  - `Ref #8209`;
  - the follow-up link;
  - the AC7 RED evidence;
  - the `decision-challenges.md` DC-1.
- [ ] 4.4 Confirm the required checks are green by name on the exact head SHA, then auto-merge.

## Phase 5: Post-merge proof (authorized)

- [ ] 5.0 Run both prechecks:
  - the kill switch held: the merge commit carries the token, and the
    `apply-web-platform-infra` push run shows preflight `Kill switch detected` with `apply` skipped;
  - no drift: the push-filter diff `38d64df696..<merge-sha>` is empty.
- [ ] 5.1 Dispatch `apply-github-infra.yml` on `main`. Resolve the run id (filtered by actor and
  creation time) and arm a Monitor until-loop.
- [ ] 5.2 Verify AC12. Record the run URL on #8209 and in the ADR-241 note (a docs follow-up commit
  if the PR has merged).
- [ ] 5.3 Do not dispatch `entrypoint-audit`. Offer it to the operator as a separately authorized
  step.
