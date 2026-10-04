---
title: "security(infra): give the App-token release jobs a Doppler source holding only the soleur-infra App values (PR-2, the switch)"
date: 2026-10-03
slug: switch-app-token-release-jobs-to-infra-app-doppler-token
branch: feat-one-shot-9321-pr2-infra-app-token-switch
issue: 9321
type: security
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
closes: 9321
scope: "PR-2 of 2 (the switch). PR-1 (dormant container, bootstrap script, census Guard 7, ADR-241 D11 text, runbook section) is merged and its bootstrap has run."
---

## Overview

Second of two changes for issue 9321. The first change created the dormant Doppler project
`soleur-infra-app` and the generated bootstrap script; the bootstrap has since run, and the
environment secret `DOPPLER_TOKEN_INFRA_APP` now exists on the main-only `infra-privileged`
environment. This change makes the shared composite `mint-infra-app-token` read the App id and key from
`soleur-infra-app/prd` by default, makes the two unattended release jobs
(`build-inngest-bootstrap-image.yml::bump-cloud-init-pin`, `mint-inngest-bootstrap-tag.yml::mint`) pass
`secrets.DOPPLER_TOKEN_INFRA_APP`, and keeps the composite's third caller
(`apply-github-infra.yml::apply`, which already holds the whole Tier-B project for Terraform) on its
current source through one explicit, validated input. Their fixture suites, the census, the runbook,
ADR-241 D11, ADR-232 and the C4 edge are updated in the same change.

**Landing constraints (from the operator's brief).** The change edits `.github/workflows` and
`.github/actions`, so it is NOT admin-merged and the pipeline does not merge it: open it, get CI green,
leave it for the operator. No production write by the pipeline (no dispatch of a release workflow, no
Doppler or GitHub-secret write). The PR body carries `Closes #9321`. Out of scope: GHCR retirement and the
legal cluster (`cla.yml`, legal documents including the Article 30 register).

**Lane note.** No `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-03. **Passes used:** a five-agent plan review (simplicity, DHH, Kieran, architecture, spec-flow), a repo spike in a throwaway worktree, the plan skill's sharp-edges catalogue, and the mechanical halts (user-brand impact, observability, PAT-shaped variable, guard contract, scope check) all passing.

### Key improvements folded in

1. **Third-caller decision reversed after architecture and spec-flow review.** The first draft moved `apply-github-infra.yml` to the narrow token; two reviewers showed no security gain and a new coupling of the ruleset-repair apply to the second App-key copy. The plan now follows ADR-241 D11 as merged: a validated `doppler-project` input, default narrow.
2. **Kieran's CI-failure findings fixed:** the mint suite's exact `g3.wf:row-count` pin (39 -> 40), the compliant census BASE fixture needing a composite and callers, `g3_mut` only requiring one `BAD` (explicit per-row greps), the third read of another name needing its own G7f clause (M2b), and falsified C4 sentences on a second edge.
3. **Simplification applied:** Guard 2/3 harness extras and nine-row census matrix trimmed; the unneeded bump-script comment edit and the third-caller header comment edit dropped.
4. **Flow gaps closed:** a proof tracker with a decision tree, a Decide dry-run on the PR head, an ordered rollback, a cause-to-stage table, a `source=` field on the proof notice, and a merge-time hand-off block (rebase and re-measure the exact floors).
5. **Scope Check added** (it was missing); asks mapped, inferred items justified, single PR.

### Spike result (throwaway worktree at this branch's base, naive textual swap of the secret name, the step name and the project literal; nothing committed)

- Census: still 250 passed, 0 failed. No existing census row reacts to the switch, so G7f is purely additive.
- Mint suite: 24 failures, exactly the pins named in Phase 1.1: `doppler-check-exact`, `app-exact`, `step-order` (finds the verify step by name), the `w13` and `w18` mutation anchors, `h2-env-mapping`, `h1b-keyset-load-bearing`, and the composite section (`comp.scoped:*`, `comp.scope-mismatch:*`, `comp.exchange-refused:*`, `comp.transport-fail:annotated`, `comp.mut-project:landed`) because the stub refuses the new project. Bump suite: `g2.action:doppler-config`, S17, S18, S24, `g2m.control:clean`, the `verify-tier-a` and `bracket-tier-a` anchors, `h2-env-mapping`. Shape suite, tag-guard, mirror-only and cloud-init suites: unaffected.
- Conclusion: the plan's pin list is complete for the three suites; `step-order`, `h2-env-mapping` and `h1b-keyset-load-bearing` (mint) and `g2m.control:clean` and `h2-env-mapping` (bump) are name-dependent rows to carry in Phase 1.

### New considerations discovered

- Under the chosen design the third caller's `doppler-project: soleur-infra-privileged` line is load-bearing: without it the default narrow project plus the broad token would be refused by Doppler and every `infra/github` apply would stop at its mint step.
- A merge-time mint-workflow run is guaranteed (its own file is in its push `paths`); whether it is a `noop` depends on carrier drift on `main`, hence the dry-run and hand-off.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief / predecessor plan / ADR-241 D11 text) | Reality (measured 2026-10-03) | Plan response |
|---|---|---|
| Brief: the composite "must be switched" and only two workflows (`bump-cloud-init-pin`, `mint`) pass the secret | The composite has **three** callers. `apply-github-infra.yml::apply` also calls it (marketplace ruleset verify) with `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED`; `tests/scripts/test-apply-github-infra-mint-shape.sh` pins that. Its mint step runs BEFORE `terraform plan`/`apply`, so a mint that fails blocks every `infra/github` apply, including an emergency ruleset repair. Repointing the composite's fixed project alone would break that job | Third caller keeps its current source through an explicit input (Design Decision 1). This follows ADR-241 D11 as merged ("adds the source as an explicit input"); an earlier draft of this plan moved it to the narrow token instead and was reversed after architecture review (no security gain, new coupling of the ruleset-repair path to the second App-key copy) |
| Predecessor plan: "census G7d PR-2 half" | G7d's population is a different property (nothing mints or stores the narrow token anywhere branch-reachable) | A new row **G7f**, with its own presence entry (`G7_ROW_IDS`) and counted floors |
| Predecessor plan: the proof run needs the live App widened first | That prerequisite is done (the runbook's own step 5 says so) | No action |
| Brief: "the one-file bootstrap.sh fix is already cherry-picked" | Verified: `fix(bootstrap): treat Doppler's null token list as empty in the 9321 bootstrap` is on this branch ahead of `origin/main` | The PR diff shows that file in addition to this change; say so in the PR body |
| Brief: `DOPPLER_TOKEN_INFRA_APP` stored in `infra-privileged` | Names listing of the environment's secrets (names and timestamps only): `DOPPLER_TOKEN_INFRA_APP` present (updated 2026-10-03T19:57:28Z) alongside `DOPPLER_TOKEN_INFRA_PRIVILEGED` and `DOPPLER_TOKEN_WRITE`; a repository-level secret of that name does not exist (count 0). A listing proves the name exists, not that the token is unrevoked or that the copied values match the live App | Premise holds for existence only. Re-run both listings and the runbook's read-only verification reads (token listing of `soleur-infra-app/prd`, project-exists) immediately before marking the PR ready, with a timestamp in the PR body; the bootstrap's own `verify` stage is the stronger check and is named in the operator hand-off |
| Predecessor plan: "Merging PR-2 edits both workflows, which fires the mint job's push trigger" | True: the mint workflow's push `paths` include both workflow files, so a run fires at merge. Its `Decide` step (git only, no credential, `--dry-run` prints the verdict and exits 0 on both outcomes) compares the `cp`-staged carriers, the four baked pins and the Dockerfile heredoc against the newest MERGED tag; this change touches none of them, but the verdict also depends on any carrier drift already on `main` or landing before the merge. If it returns `would-mint` the run does a real mint with the new credential, publishes a tag and dispatches a build. `apply-github-infra.yml`'s own file is not in its `paths` | The dry-run is run on the PR head before marking ready and the `result=`/`reason=` lines pasted in the PR body; the operator re-runs it at merge time if `main` moved (hand-off note). The `would-mint` outcome is stated plainly in Landing Order (it succeeds and publishes, it is not merely "loud") |

## Research Insights

**Premise Validation.** Checked: issue 9321 is open with no closing PR; issues 8209 and 8609 (the
credential-tier work this narrows) are open; PR-1 and its bootstrap are merged (`soleur-infra-app`
declared in `apps/web-platform/infra/infra-app-project.tf`; census G7c/G7d/G7e and `ENV_SECRETS` already
carry the new name); the environment secret exists (listing above). Cited paths all exist on
`origin/main`: the composite, both release workflows, both fixture suites, the census suite, the runbook
and ADR-241 (D11 present, status `proposed`). Mechanism versus the ADR corpus: ADR-241 D3, D10 and D11
already decide the shape (project not config; explicit input for the third caller); nothing proposed here
sits in a rejected-alternatives table.

**Property List.**

- P1. The two release jobs hold a credential that reads only `GITHUB_INFRA_APP_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY`, and no step in either job names any other Tier-B secret.
- P2. The composite's default source is the narrow project; the only other source it accepts is the Tier-B project, named by an input validated against exactly those two literals; Doppler itself refuses a token used against the wrong project.
- P3. A missing, revoked or stale credential fails loud, with a stage-named message and a runbook pointer, before any tag, push or pull request (unchanged ordering; renamed steps).
- P4. No suite can be satisfied by a stub: the argv pin refuses a wrong or retired source, the step-shape pins refuse the old secret, and the census quantifies over the derived caller population rather than a hand list.
- P5. The recorded architecture (ADR-241 D11, ADR-232, runbook, C4) describes the post-switch state in the same change, with D11 moved to `adopting`.

**Cut List.**

- Moving the third caller to the narrow token -> no security property (its job already holds the whole Tier-B project for Terraform) and it couples the ruleset-repair apply to a second copy of the App key.
- A fallback "narrow token else broad token" in the composite -> keeps the broad token reachable (already rejected in D11).
- A new fixture suite -> rows go into the three existing suites, so no suite-shard or duration manifest is regenerated.
- Folding the new census property into G7d -> a separate row keeps each row's matrix about one property.
- Removing the `Verify DOPPLER_TOKEN_INFRA_APP present` steps -> both suites pin them by name; out of scope.
- A live read of the narrow token from CI before merge -> branch dispatch is refused (main-only environment), so only the first real run proves it.
- A scheduled equality probe of the two App-key copies -> rotation order plus the bootstrap's copy stage cover it (already a D11 non-goal).
- A comment-only edit to `bump-inngest-bootstrap-pin.sh` (it says the token is minted "from the Tier-B project") -> buys no property; left as is.
- Per-guard "test the tests" harness extras beyond one must-PASS fixture and the presence row (review simplification).

**Institutional learnings applied.**

- A census by name misses consumers that reference the thing another way (`2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id`): the same blind spot hid the composite's third caller from the brief; G7f derives its population from the census's own caller resolution and pins its size.
- A source census that checks an argument's name rather than its binding, and a closed file list, pass a guarded path (`2026-09-29-a-source-census-that-checks-the-arguments-name-not-its-binding-and-a-closed-file-list-both-let-guarded-egress-through`): G7f checks the validated project binding and enumerates composites and readers by resolution, not by path.
- Adding a second copy of a guarded literal disarms the guard on the first (`2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first`): the old project literal moves from "the one source" to "one of two allowed values"; every pin that carried it is rewritten in one diff.
- Tests pinned to exact step names: both release suites match `Verify DOPPLER_TOKEN_INFRA_PRIVILEGED present` by name; rename and pins move together or CI goes red.
- A Doppler-fetched secret is not auto-masked: the composite already masks the id and each PEM line; untouched.
- Counted floors (`CENSUS_ROWS`, `MUTANT_FLOOR`, `FLOOR`, each `MIN_ASSERTIONS`) are raised to the measured count with the final row set, never estimated, never lowered.

**Verified facts for the implementer (planning pass).**

- Composite mentions of the project: the `description:`, the `doppler-token` input description, the empty-input error, the two `doppler secrets get ... --project soleur-infra-privileged --config prd` reads, three `::error::` strings, and the final `::notice` line (its exact text is pinned by the mint suite's `comp.scoped:notice` row).
- Callers: `build-inngest-bootstrap-image.yml` (step `Mint soleur-infra App token (contents+pull_requests write on soleur)`, id `mint`), `mint-inngest-bootstrap-tag.yml` (id `app`), `apply-github-infra.yml` (id `mint`, installation `166065653`, `administration:write` on `soleur-marketplace`; the same job calls `./.github/actions/infra-credentials` with `doppler-token-infra-privileged:`, which is NOT touched).
- Old-literal pins to rewrite: `test-mint-inngest-bootstrap-tag.sh` (step-name `find`, `exact("doppler-check")`, `exact("app")`, the `no-tier-a` comment and message, mutation rows w13 / w16b / w18, the composite stub's project refusal and its `case` arms, `comp.scoped:doppler-argv`, `comp.scoped:notice`, the `--project` project-mutation block); `test-bump-inngest-bootstrap-pin.sh` (`check_action 'g2.action:doppler-config'`, S17, S18, S24 and its step-name list, rows `verify-tier-a`, `bracket-tier-a`, `script-env-extra-token`); `test-apply-github-infra-mint-shape.sh` (the `with` pins).
- Census: `ENV_SECRETS` already contains `DOPPLER_TOKEN_INFRA_APP`; the census resolves composite callers (`composite_callers`) and has `cmd_sites`, `step_sites`, `env_arms`; `G7_ROW_IDS="G7c G7d G7e"`, `CENSUS_ROWS=41`, `MUTANT_FLOOR=94`, `FLOOR=250`.
- Baselines run read-only in this worktree before any edit: census 250 passed in about 17 s; mint-tag suite 610 pass in about 57 s; shape suite 8 passed in about 1 s; bump-pin suite 578 pass. `python3 -c "import yaml"` works locally, so all four can be run after each edit; CI remains the gate.
- Workflow-file byte ceilings: the edits shorten or barely change each file; `plugins/soleur/test/workflow-file-size.test.ts` is unaffected.

## Design Decisions

**1. The composite gains one validated input; its default is the narrow project.**
New input `doppler-project` (optional; default `soleur-infra-app`). The run block rejects any value other
than exactly `soleur-infra-app` or `soleur-infra-privileged` BEFORE any Doppler call (stage-named error),
then reads both values with `--project "$DOPPLER_SOURCE" --config prd` in argv, so the fixture stub still
observes the source. The release jobs pass only `doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_APP }}`
and inherit the narrow default (a new caller that forgets the input also lands on the narrow source).
`apply-github-infra.yml` adds `doppler-project: soleur-infra-privileged` and keeps
`doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}`; dropping that line would default it to the
narrow project with the broad token, which Doppler refuses, and the shape suite pins it. The composite's
description is rewritten from "one identity and one source, neither an input" to "one identity; the source
is one of two named projects, default narrow, validated; a token is refused by Doppler for any project it is
not scoped to". Rationale for not moving the third caller: ADR-241 D11 as merged, and the review's blast-radius
finding (a stale narrow copy would block the apply that repairs repository rulesets).

**2. Composite edit otherwise textual.** Same steps, checks, masking, exact-grant verification and revoke.
The `::error::` strings name the source actually used (`${DOPPLER_SOURCE}/prd`). The two "not readable"
messages append a static pointer, "see runbook infra-credential-tiers-8209.md §Release-job App source",
whose cause-to-stage table (added in Phase 3) maps a missing environment secret, a rejected token and a
missing or stale copy to the right remedy; the composite cannot tell those causes apart (stderr is
suppressed) and does not guess. The `::notice` line gains a trailing `source=${DOPPLER_SOURCE}/prd` field (after a space) so a run
shows which source it read (this is the observable proof signal); the suite's pinned notice line and the
runbook's O4c wording are updated; no value is printed.

**3. Release workflows: rename, do not restructure.** In both jobs: the explanatory comments, the step name
`Verify DOPPLER_TOKEN_INFRA_APP present`, its `env` value, its `::error::` text and the composite's
`with: doppler-token`. Nothing else (the build workflow's probe-gate window belongs to an open code-review
issue on a different concern).

**4. A new census row, G7f, plus one per-job static row in each release suite.** The census row is the
repo-wide chokepoint over the derived caller population; the per-suite `no-broad-tier-b` row is the fast
local tripwire beside the existing `no-tier-a` row it copies.

**5. D11 flips to `adopting` here; `accepted` needs evidence for the callers that can be proven.** The proof
dispatch exercises the build job's caller only. The mint job's caller is exercised only on a real
`would-mint` (its credential steps are skipped on `noop`), and the third caller is unchanged in source and
token. D11's text says so; `accepted` is claimed on the build-job proof plus the static suites for the others.

## Implementation Phases

Tests first (`cq-write-failing-tests-before`): Phase 1 edits the suites so they fail against the unmodified
composite and workflows; Phase 2 makes them pass. Run each suite locally after each edit.

### Phase 1 - Tests and guards (RED against current main)

1.1 `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`

- Step-name `find`, `exact("doppler-check")` env, `exact("app")` `with`, the name-dependent rows `step-order`, `h2-env-mapping` and `h1b-keyset-load-bearing`, and the composite-section rows the stub drives (`comp.scoped:*`, `comp.scope-mismatch:*`, `comp.exchange-refused:*`, `comp.transport-fail:annotated`, `comp.mut-project:landed`) use `${{ secrets.DOPPLER_TOKEN_INFRA_APP }}` and the new step name (the `app` step's `with` has no `doppler-project` key: the exact key-set pin makes an added key a different step).
- Composite stub: accepts the project the run expects (a per-run expected-project argument; default narrow) and refuses all others; `comp.scoped:doppler-argv` expects the narrow project; add rows: `doppler-project: soleur-infra-privileged` reads that project and succeeds; an unlisted value (`soleur`) is refused before any Doppler call (`dcalls` 0, no curl call, no token output); the project-mutation block keeps its wrong-project (`soleur`) row and adds a row that flips the composite's DEFAULT to `soleur-infra-privileged` (the scoped default row must then refuse: the stub expects narrow).
- `comp.scoped:notice` equality gains the trailing `source=` field.
- `no-tier-a` comment/message: the job holds only `DOPPLER_TOKEN_INFRA_APP`. Add `no-broad-tier-b`: neither the job, the workflow `env`/`defaults`, nor any step references `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED` in dotted or bracket spelling (same serialised scan as `no-tier-a`).
- Mutation rows: w13, w16b, w18 keep their intent with the new secret name; add w19 (the mint step's `with: doppler-token` regresses to the broad secret; must red `app-exact` and `no-broad-tier-b`) and a bracket-spelling extra step (only `no-broad-tier-b` can see it).
- Update the exact pin `a_eq 'g3.wf:row-count' ... 39` (about line 1377): adding `no-broad-tier-b` to the workflow checker makes the reported row count 40, and CI fails otherwise. The bump suite is safe (its `END|N` count is self-reported).
- `g3_mut` only requires at least one `BAD`, so each new row that claims a specific red also asserts it with an explicit `grep -q '^BAD no-broad-tier-b '` (the existing `w16b_out` pattern); the bracket-spelling extra step carries `timeout-minutes` and an `if` so that `step-timeouts` does not also redden and "only `no-broad-tier-b`" is true.
- Reword the stale prose, which a grep for the old literal will not find: the comments near lines 1351 and 1357 and the stub's leading comment near lines 1482-1492.
- Raise `MIN_ASSERTIONS` (a `<` floor) to the measured green count.

1.2 `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`

- The name-dependent rows `g2m.control:clean` and `h2-env-mapping` follow the rename; `check_action 'g2.action:doppler-config'` needle -> the validated default (`soleur-infra-app`) as it appears in the composite; S17, S18, S24 (and its sorted step-name list) use the new secret and step name; add `S25:bump-no-broad-tier-b` beside S20.
- Rows `verify-tier-a`, `bracket-tier-a`, `script-env-extra-token` keep their anchors with the new secret name; add `mint-broad-tier-b` (S18, S25).
- S24 must test `DOPPLER_TOKEN_INFRA_APP` (it currently tests the substring `DOPPLER_TOKEN_INFRA_PRIVILEGED`); the `script-env-extra-token` mutation's replacement text must name `DOPPLER_TOKEN_INFRA_APP` so it keeps reddening S23 and S24.
- Raise `MIN_ASSERTIONS` (a `<` floor) to the measured green count.

1.3 `tests/scripts/test-apply-github-infra-mint-shape.sh`

- Add `mint:doppler-project` pinning `soleur-infra-privileged`; `mint:doppler-token` still pins the broad secret. New row `project-dropped` (removes the `doppler-project` line; must red `mint:doppler-project`; the anchor occurs exactly once). Raise `MIN_ASSERTIONS` from 8 to 9. The suite's header comment (the "from the Tier-B secret" wording) is reworded to name the explicit source.

1.4 `tests/scripts/test-infra-privileged-tier-census.sh` - add G7f (see Guard Contract). The control census must be GREEN on every row and the compliant base fixture has no composite and no caller today, so a `>= 1` floor would redden the control and every mutant would measure nothing: the BASE fixture (the heredocs around lines 1630-1900) gains a compliant composite (default `soleur-infra-app`, the two-literal allow-list, exactly the two pinned reads), a release-shaped caller (narrow shape) and a loader-calling caller (broad shape); M7 then deletes them. Re-measure every row that scans the fixture (G1a, G4e, G6n, G7c-e) against the enlarged base, and the control's row count against `CENSUS_ROWS`. Write the mutation fixtures first and measure each RED, then the check; add `G7f` to `G7_ROW_IDS`; raise `CENSUS_ROWS` (41 -> 42), `MUTANT_FLOOR` (the only exact one) and `FLOOR` (a `<` floor) to measured counts with dated comment lines in the file's style. Run the WHOLE census: the two release jobs now name `DOPPLER_TOKEN_INFRA_APP`; they are already members of the Tier-B population that G1b, G1c, G1d, G1f, G1g and G1h key on (both declare `infra-privileged`), so no membership changes, but the whole census is the check.

### Phase 2 - Production edits (GREEN)

2.1 `.github/actions/mint-infra-app-token/action.yml` per Design Decisions 1 and 2. After the edit the default literal `soleur-infra-app` and the allow-list literals appear as designed, and the old project literal appears only as the second allowed value.
2.2 `.github/workflows/build-inngest-bootstrap-image.yml` (job `bump-cloud-init-pin` only) and `.github/workflows/mint-inngest-bootstrap-tag.yml` (job `mint` plus its two header comments) per Design Decision 3. After the edit `DOPPLER_TOKEN_INFRA_PRIVILEGED` appears in neither file.
2.3 `.github/workflows/apply-github-infra.yml`: add `doppler-project: soleur-infra-privileged` to the mint step. Neither its header comment nor the mint step's comment names the source, so no comment edit is needed; the loader step and the `Verify required secrets present` step are untouched.

### Phase 3 - Architecture record, runbook, C4 (deliverables of this plan)

3.1 ADR-241: D11 text amended in place (the input is now built as described in Design Decision 1; the "two changes" italic note says the second has landed; the "Ordering with D10" paragraph gets a dated "satisfied once this change merges" note); the Status header bullet and the Statuses row move D11 to `adopting`; ONE new Amendment-log entry (2026-10-03) that also lists, in one place, the earlier dated statements it supersedes (those that name the broad token as the release jobs' composite source) instead of a marker at each sentence.
3.2 ADR-232: one dated marker at the 2026-09-30 amendment's "recorded deferral" sentence, pointing at ADR-241 D11; fix only sentences that are now false.
3.3 Runbook `infra-credential-tiers-8209.md`: the two release-job rows (token, source) and the third-caller dated note (it states the explicit `doppler-project` input); a dated follow-on note beside the two older notes saying the release jobs "reuse `DOPPLER_TOKEN_INFRA_PRIVILEGED`"; the "Do not run R-step 2 before the second change has merged" paragraph gets a dated "gate satisfied once merged" note; §Release-job App source: steps 4 and 5 reworded to the as-built state, a **cause-to-stage table** (environment secret missing -> `Verify ... present` fails, re-store via `mint-and-store-token`; token rejected or revoked -> `mint-and-store-token`; value missing or stale in `soleur-infra-app/prd` -> `copy-app-values`), the exact proof dispatch command (named, with the tag to use and its expected side effects: a real contents and pull_requests write token is minted; for an older tag no push or PR is expected), the proof-evidence list (run id, `head_sha` at or after the merge SHA, the `Verify DOPPLER_TOKEN_INFRA_APP present` step conclusion from `gh run view --json jobs`, the notice's `source=` field), and an **ordered rollback**: revert merged, a run green on the broad token, only then revoke the read token and delete the secret and the copies (revoking first breaks the release jobs); the revert also reverts the cherry-picked bootstrap fix, so the forward-fix alternative (re-run `mint-and-store-token`) is listed first for a stale or rejected token; rotation addendum: do not revoke the old read token while a release run is in flight (`gh run list` check), and copy drift is detected only at run time.
3.4 `inngest-server.md` recovery row that quotes `::error::DOPPLER_TOKEN_INFRA_PRIVILEGED is not available`.
3.5 `model.c4`: re-grep for `soleur-infra-privileged` and `DOPPLER_TOKEN_INFRA_PRIVILEGED` and edit every sentence that names the composite's or the release jobs' source falsely. Known spots: the `github -> doppler` edge near line 644 has TWO falsified sentences ("using the same DOPPLER_TOKEN_INFRA_PRIVILEGED. That token still reads the WHOLE project..." and "a recorded deferral"); the `github -> soleurMarketplace` edge near line 578 (mirrored in `model.likec4.json` near line 1833) says the composite reads the App values from the fixed Tier-B project with `DOPPLER_TOKEN_INFRA_PRIVILEGED` and "reads only the two GITHUB_INFRA_APP_* names from soleur-infra-privileged/prd"; that edge's caller is the third caller, so it now states the explicit `doppler-project` input. Add no digit-bearing cardinality. Regenerate `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`. Run `plugins/soleur/test/c4-count-parity.test.sh` and `c4-model-freshness.test.sh`.
3.6 After all doc edits, `git grep -n -e "DOPPLER_TOKEN_INFRA_PRIVILEGED is not available" -e "Verify DOPPLER_TOKEN_INFRA_PRIVILEGED present" -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!**/archive/**'` must return nothing (the plan files quote the retired phrases and are excluded, or the check is unsatisfiable by construction).

### Phase 4 - Verify and open the PR

4.1 Run locally: the three edited suites, the bump suite, the census, `plugins/soleur/test/c4-count-parity.test.sh`, `c4-model-freshness.test.sh`, `python3 scripts/lint-infra-no-human-steps.py` on every changed markdown file, and the `git grep` checks of Phase 2/3 (each excluding `knowledge-base/project/plans`, `knowledge-base/project/specs` and `archive/` paths). Run the discoverability probe from the Observability block once the composite is edited: it must print exactly `1`. Suites that only read the build workflow and do not read its token lines (`test-inngest-bootstrap-tag-guard.sh`, `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`, `cloud-init-inngest-bootstrap.test.sh`) are left to CI unless a changed file is one they read. Also run the Decide dry-run on the PR head (`bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run`, git only, no credential) and record its `result=` and `reason=` lines.
4.2 Create the post-merge proof tracker (a GitHub issue; milestone from the roadmap): "prove the narrow App source and flip ADR-241 D11 to accepted", with the exact dispatch command, the evidence list, and the decision tree (green -> flip D11; a stage-named failure -> re-run the named bootstrap stage and re-dispatch; no recovery -> ordered rollback). Link it from the PR body. `Closes #9321` closes the security issue; this tracker owns the proof.
4.3 PR body: its FIRST line answers "does merging this alone mutate production?" (no infrastructure apply, no web-platform release; at most a `noop` mint-workflow run unless the Decide dry-run says `would-mint`), then `Closes #9321`; the Landing-order statement; the names-and-counts evidence with its timestamp and the read-only verification reads; the `READY_FOR_PR2` report quoted from the task brief (the exact script line lives in the bootstrap session; the body says so); the dry-run result; the note that the diff also carries the already-cherry-picked bootstrap fix; the hand-off block (below); no `#N` of a closed issue; no `[skip-...]` kill-switch line.
4.4 Mark ready, wait for CI. **Do not merge, do not enable auto-merge, do not admin-merge**; this overrides the standard ship step because the change edits `.github/workflows` and `.github/actions` and the merge decision belongs to the repository owner.

**Operator hand-off block (goes in the PR body).** Before merging: rebase on `main` and re-run the suites that carry exact floors (census, mint-tag, bump, shape), because concurrent PRs edit them and the floors are exact; re-run the Decide dry-run if `main` moved; re-run the two listings and the bootstrap's read-only `verify` stage; then merge. After merging: run the proof dispatch from the tracker issue.

## Landing Order and What Merging Does

- Merging starts no Terraform apply (no `apps/web-platform/infra` file changes) and no web-platform release (no `apps/web-platform/**` path).
- The mint workflow's push run fires at merge (its own file is in its `paths`). If `Decide` returns `noop` (expected), no credential step runs. If it returns `would-mint`, the narrow credential is used for the first time: with the secret present the run SUCCEEDS and publishes a tag and a build dispatch; with it missing the `Verify` step fails before the tag. `apply-github-infra.yml` has no trigger on its own file.
- If the narrow secret were missing at the first release run, the `Verify DOPPLER_TOKEN_INFRA_APP present` step fails before the mint; both jobs mint before the tag and before the push, so nothing is tagged, pushed or opened and the existing Slack failure post fires. The build job has, however, already published its image by then (its mint sits in the later pin-bump job); recovery is re-running the named bootstrap stage and the job.
- A push to `main` that changes a carrier between this merge and the proof dispatch fires the mint job on the unproven credential; the failure mode is the same and acceptable.
- Rollback: ordered (revert merged, a green run on the broad token, then revoke and delete); see the runbook.

## Guard Contract

### Guard 1 - Census G7f (callers and the composite use only the two permitted source shapes)

**Property.** Every `mint-infra-app-token` call is exactly one of two shapes: the narrow shape (no `doppler-project` input; `doppler-token` is `secrets.DOPPLER_TOKEN_INFRA_APP`) or the broad shape (`doppler-project: soleur-infra-privileged`; `doppler-token` is `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED`) and the broad shape occurs only in a job that also calls the `infra-credentials` loader; the composite's `doppler-project` default is `soleur-infra-app` and its allow-list is exactly the two literals; and no command-position `doppler secrets get` of `GITHUB_INFRA_APP_ID` or `GITHUB_INFRA_APP_PRIVATE_KEY` exists outside the composite.

**Assembly.** The population is derived: (a) every `uses: ./.github/actions/mint-infra-app-token` step in every workflow, resolved by the census's own `composite_callers` mapping (three members today; exact pin on the live tree, `>= 1` on the fixture tree, so a fourth caller is a deliberate dated census edit and zero callers is itself a failure); (b) the composite file(s) found by that same resolution, parsed for the input's default and the validation `case` literals, and every command-position `doppler secrets get`, `secrets download` or `doppler run` inside them, which must be exactly the two pinned reads (this clause, not the App-value regex of (c), is what sees a third read of another name); (c) every command-position `doppler secrets get` of an App value in any workflow `run:` body or action file, scanned with `cmd_sites` (command position excludes comments), so a second reader or a second composite cannot escape by living in a new file. "Release job" means a job that calls the composite and does not call the loader; a release job that later adds the loader escapes the broad-shape restriction, which the row's comment states and the per-suite rows cover for the two named jobs. Token references are matched in dotted, bracket and whitespace spellings.

**Mutation matrix.** Each row is written and measured RED before the check exists:

| # | Mutation (fixture tree copy) | Must redden |
|---|---|---|
| M1 | the composite fixture's `doppler-project` default is flipped to `soleur-infra-privileged` | G7f |
| M2 | the composite fixture's allow-list gains a third literal (`soleur`) | G7f |
| M2b | the composite fixture gains a third read of a different name (`HCLOUD_TOKEN`) from the narrow project | G7f (clause (b)) |
| M3 | after a compliant first caller, add a SECOND caller job (no loader) using the broad shape (a check that stops at the first member is the defect) | G7f |
| M4 | one caller passes the Tier-A `${{ secrets.DOPPLER_TOKEN }}` | G7f |
| M5 | one caller's broad token is written in bracket spelling `secrets['DOPPLER_TOKEN_INFRA_PRIVILEGED']` with the narrow default | G7f |
| M6 | a NEW workflow step reads `GITHUB_INFRA_APP_PRIVATE_KEY` with `doppler secrets get` inline | G7f |
| M7 | empty fixture tree: no caller, no composite | G7f (the `>= 1` floor; "0 scanned" must not pass) |

**Harness rows.** H1: remove `G7f` from a copy of the control TSV; the existing `G7h2` presence row (now listing `G7f`) must go RED. H2 (must-PASS, not the canonical): a fixture whose composite mentions the broad project only in a comment, whose third-caller job calls the loader and the composite with the broad shape and `with:` keys in a different order, and whose release job uses the narrow shape, must stay GREEN, so a guard that rejects everything is also caught.

**Anchor.** The literals (the two project names, the default, the secret names, the caller count) live in the suite itself; weakening any of them edits the suite in the same diff, which review sees. The count pin alone survives a substitution that keeps the count, so it is paired with the per-member shape check (set identity by value, not only by count); there is no stored hash.

### Guard 2 - Per-suite `no-broad-tier-b` rows (the two release suites)

**Property.** Neither release job, nor the workflow-level `env`/`defaults`, references `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED` in any spelling.

**Assembly.** The whole parsed job plus workflow `env`/`defaults`, serialised and scanned (the `no-tier-a` scan shape), so an added step, an added `env` key or a workflow-level `env` is inside the window, not just the named steps.

**Mutation matrix.**

| # | Mutation | Must redden |
|---|---|---|
| M1 | the mint step's `doppler-token` regresses to the broad secret | the step's exact-shape row and `no-broad-tier-b` |
| M2 | the verify step's `env` regresses to the broad secret | the verify-exact row and `no-broad-tier-b` |
| M3 | after compliant steps, a new step whose `env` names the broad secret in bracket spelling | `no-broad-tier-b` only (the exact rows cannot see a new step) |

**Harness rows.** The real, compliant workflow (with the Tier-A secret absent and the narrow secret named in a comment) is the must-PASS case.

**Anchor.** Literals live in the suite; floors are exact `MIN_ASSERTIONS` counts raised with the rows.

### Guard 3 - Composite fixture stub (the argv pin and the input validation)

**Property.** The composite's two `doppler secrets get` calls reach Doppler with exactly the validated project and `--config prd`, the default is the narrow project, and an unlisted project is refused before any Doppler or GitHub call.

**Assembly.** The stub is the single place the argv is observed; every run of the composite in the suite (default, privileged, unlisted, failure paths, mutation copies) goes through it, and the project-mutation rows rewrite every occurrence of the project literal in a composite copy.

**Mutation matrix.**

| # | Mutation | Must redden |
|---|---|---|
| M1 | composite copy's default flipped to `soleur-infra-privileged` | the scoped default row (stub expects narrow): refused, no token output |
| M2 | composite copy's allow-list widened to accept `soleur` | the unlisted-value row (must be refused with zero Doppler calls) |
| M3 | composite copy drops `--config prd` from the SECOND read only (needs an nth-occurrence replacement helper; the existing project-mutation block replaces globally) | `comp.scoped:doppler-argv` equality |

**Harness rows.** The stub's accepted project is a heredoc literal today, so it is parametrised (an expected-project argument defaulting to narrow) to make this edit possible; setting it to the retired project for the default row is the harness edit: set it to the retired project for the default row and the scoped row must go RED. Must-PASS non-canonical: the `doppler-project: soleur-infra-privileged` run with the broad fixture token succeeds.

**Anchor.** The argv equality and the stub's accepted pair are literals in the suite.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-241 (D11 text, Status bullet, Statuses row `adopting`, one Amendment-log entry) and add one dated marker to ADR-232, as tasks of Phase 3. No new ordinal is taken, so no ordinal collision is possible.

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`) for the enumeration: (a) external human actors: none new; (b) external systems: Doppler, GitHub and the soleur-infra App are already modeled; the narrow project is a Doppler project, described in edge prose, not a separate element; (c) containers/data stores: none new at C4 altitude; (d) actor-to-surface relationships changed: none. Falsified statements are edited in Phase 3.5 (the two edges named there and any other sentence the re-grep finds), adding no derived cardinality; `c4-count-parity.test.sh` must stay green.

### Sequencing

D11 is authored as `adopting` here and flips to `accepted` at the proof dispatch (tracker issue).

## Observability

```yaml
liveness_signal:
  what: "Per release run, the composite's notice title=app-token (app=soleur-infra installation=166065653 permissions=... source=soleur-infra-app/prd) and a green Verify DOPPLER_TOKEN_INFRA_APP present step; the existing Slack failure posts of both release workflows; the apply-github-infra mint step on its own source"
  cadence: "per release run (mint on a carrier-changing push to main, build on dispatch), per infra/github apply"
  alert_target: "the existing Slack posts of build-inngest-bootstrap-image.yml and mint-inngest-bootstrap-tag.yml; the apply-github-infra failure path"
  configured_in: ".github/workflows/build-inngest-bootstrap-image.yml; .github/workflows/mint-inngest-bootstrap-tag.yml; .github/workflows/apply-github-infra.yml"
error_reporting:
  destination: "GitHub Actions run annotations plus the existing Slack posts; no secret value is ever in an annotation (the composite masks the id and each PEM line and prints only sanitised vendor message text)"
  fail_loud: "a missing environment secret fails the Verify step before the mint; an unreadable value fails with ::error::mint-infra-app-token: ... not readable from Doppler soleur-infra-app/prd plus a runbook pointer; an unlisted project fails before any Doppler call; both release jobs mint before the tag and before the push, so a credential failure publishes nothing"
failure_modes:
  - mode: "environment secret missing, revoked or rotated away"
    detection: "Verify DOPPLER_TOKEN_INFRA_APP present fails, or the composite reports not readable from soleur-infra-app/prd, before any publish"
    alert_route: "release workflow Slack failure post"
  - mode: "stale copy of the App key after a key rotation"
    detection: "composite: openssl rsa -check, or the installation-token exchange returns no token, with a stage-named message"
    alert_route: "release workflow Slack failure post"
  - mode: "a caller regresses to the broad token or an unlisted source (a later edit)"
    detection: "census G7f and the per-suite no-broad-tier-b rows on every PR"
    alert_route: "failing CI check on the PR"
logs:
  where: "GitHub Actions run logs of the three callers"
  retention: "90 days (Actions default)"
discoverability_test:
  command: "grep -cF -e 'default: soleur-infra-app' .github/actions/mint-infra-app-token/action.yml"
  expected_output: "1"
```

(The declared probe checks the committed wiring locally and without SSH; implementation must keep that
exact default line, with no second occurrence of it in a comment. Live evidence is the first release run's
`app-token` notice and its `source=` field, read with `gh run view`, which is not an allowlisted preflight
verb.)

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; the release path is internal. A defect here stalls the inngest-bootstrap release (a carrier-changing merge publishes no new image and opens no pin-bump PR, with a Slack post) or, if the third caller's input were mishandled, blocks the `infra/github` ruleset apply; no user-facing surface is touched.
**If this leaks, the user's workflow and repositories are exposed via:** the soleur-infra App private key (a second copy lives in `soleur-infra-app`) or the new read token. Today the two release jobs also hold a token that reaches `DOPPLER_TOKEN_TF`, a read/write Hetzner token and, once the runtime-key sequence runs, the path to the soleur-ai runtime key web-platform uses on every connected user's repositories. This change removes that reach from the two jobs; the third caller keeps it (it already holds the whole Tier-B project for Terraform); the App's own `administration:write` and `secrets:write` grant is unchanged and stated in D11.
**Brand-survival threshold:** single-user incident

CPO sign-off is carried from the issue's own User-Impact line and the predecessor plan's review; the operator's instruction to build this change is the product-owner acknowledgement. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Open Code-Review Overlap

Two open code-review issues name planned files. #8593 (the probe-gate window of `build-inngest-bootstrap-image.yml`): **Acknowledge** - a different concern; this change touches only the Doppler-token lines of the `bump-cloud-init-pin` job. #7098 (an audit of `run:` bodies whose `set` omits `-e`, names `apply-github-infra.yml`): **Acknowledge** - this change adds one `with:` value and a comment there, not a `run:` body.

## Files to Edit

- `.github/actions/mint-infra-app-token/action.yml`
- `.github/workflows/build-inngest-bootstrap-image.yml` (job `bump-cloud-init-pin` only)
- `.github/workflows/mint-inngest-bootstrap-tag.yml`
- `.github/workflows/apply-github-infra.yml` (mint step `with` only)
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`
- `tests/scripts/test-apply-github-infra-mint-shape.sh`
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `knowledge-base/engineering/architecture/decisions/ADR-232-inngest-bootstrap-pin-bumps-are-authored-by-the-publish-workflow.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` and the regenerated `model.likec4.json`

Path-glob check: every path above exists in `git ls-files`; the push-trigger filters of the three workflows were read (see Landing Order).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9321-pr2-infra-app-token-switch/tasks.md`
- The post-merge proof tracker (a GitHub issue, Phase 4.2; not a file)

**Explicitly NOT touched** (negative-scope acceptance): any `.tf` file or `apps/web-platform/**` path (it would start the apply and the web-platform release), `cla.yml`, any legal document, anything GHCR, the build workflow's probe-gate window and Dockerfile heredoc, the loader action, `bump-inngest-bootstrap-pin.sh`, the bootstrap script beyond the already-cherry-picked fix.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the composite .github/actions/mint-infra-app-token already exists on main (reads soleur-infra-privileged/prd with DOPPLER_TOKEN_INFRA_PRIVILEGED) and must be switched to read the App id and key from soleur-infra-app/prd using DOPPLER_TOKEN_INFRA_APP" [brief] | Design Decisions 1-2; Phase 2.1; Files to Edit entry for the composite | mapped |
| 2 | "build-inngest-bootstrap-image.yml job bump-cloud-init-pin and mint-inngest-bootstrap-tag.yml job mint pass secrets.DOPPLER_TOKEN_INFRA_APP through that composite" [brief] | Design Decision 3; Phase 2.2; the two workflow Files to Edit entries | mapped |
| 3 | "update their test suites (fixture suites that observe the Doppler argv, census rows, the runbook knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md)" [brief] | Phase 1.1-1.4; Guards 1-3; Phase 3.3; the three suite entries, the census entry and the runbook entry | mapped |
| 4 | "The PR body must carry \"Closes #9321\"." [brief] | Phase 4.3; Acceptance Criteria | mapped |
| 5 | "it must NOT be admin-merged: open it, get CI green, and leave it for the operator" [brief] | Phase 4.4; Landing constraints in the Overview | mapped |
| 6 | "no production writes; never print secret values; CI is the test gate; GHCR retirement and the legal cluster are out of scope" [brief] | Overview landing constraints; Non-Goals; Explicitly NOT touched | mapped |
| 7 | "Do not name closed issue numbers in #N form in anything you write unless they are open work targets." [brief] | Acceptance Criteria (PR body check); Phase 4.3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Composite edit (default source, validated input, messages, notice field) | asks 1 | asked |
| Release workflow renames (two jobs) | asks 2 | asked |
| Census row G7f and its fixtures | "census rows" (ask 3) | asked |
| Edits to the two release suites and the shape suite | "fixture suites that observe the Doppler argv" (ask 3) | asked |
| Per-suite `no-broad-tier-b` rows | "update their test suites" (ask 3) | asked |
| Runbook edits (Group-4 rows, cause-to-stage table, proof, rollback) | "the runbook knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md" (ask 3) | asked |
| `apply-github-infra.yml` one-line edit | - | inferred - justification: the composite has a third caller whose mint would fail once the default source changes; the line keeps its current source |
| Composite `doppler-project` input with a two-literal allow-list | - | inferred - justification: the mechanism that lets the third caller keep its source (ADR-241 D11 as merged names it) without a second composite |
| `::notice` `source=` field | - | inferred - justification: the proof run must show which source it read, otherwise a green run cannot discriminate narrow from broad |
| ADR-241 D11, ADR-232 and C4 edits | - | inferred - justification: plan Phase 2.10 makes the architecture record a deliverable of the change that falsifies it |
| `inngest-server.md` recovery row | - | inferred - justification: the row quotes the retired error text and would mislead recovery |
| Post-merge proof tracker issue | - | inferred - justification: `Closes #9321` ends the only tracker while the D11 `accepted` flip and the proof dispatch remain; an owner is required |
| Operator hand-off block and merge-time dry-run | "leave it for the operator" (ask 5) | asked |

### Split Assessment

- Subsystems touched: 3 - `.github`, `tests`, `knowledge-base`
- Planned files: 15 | Estimated changed lines: 600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (this PR)

- [ ] The discoverability probe from the Observability block prints exactly `1` on the edited tree, and the composite's `doppler-project` input defaults to `soleur-infra-app`, rejects any value other than the two permitted literals before any Doppler call, and both reads carry `--config prd`; the fixture stub's rows (default, privileged, unlisted) pass and the default-flip and widened-allow-list mutations are RED.
- [ ] The two release jobs pass `${{ secrets.DOPPLER_TOKEN_INFRA_APP }}` and no `doppler-project`; `DOPPLER_TOKEN_INFRA_PRIVILEGED` appears in neither release workflow; `apply-github-infra.yml`'s mint step passes `doppler-project: soleur-infra-privileged` with the broad token and the shape suite pins both.
- [ ] Both release suites and the shape suite are green, with the new rows measured RED under their mutations, and each `MIN_ASSERTIONS` equal to the measured green count.
- [ ] Census G7f present in `G7_ROW_IDS`; M1-M7 (with M2b), H1, H2 measured RED/GREEN as stated; `CENSUS_ROWS`, `MUTANT_FLOOR` and `FLOOR` raised to measured counts; the WHOLE census is green, including G1b/c/d/f/g/h.
- [ ] No carrier, pin or Dockerfile-heredoc line of the build workflow changed and the pasted Decide dry-run shows `noop`; `git diff --name-only origin/main...HEAD` lists no `.tf` file and no `apps/web-platform/**` path, and only files named under Files to Edit, Files to Create, the cherry-picked bootstrap fix, and files the pipeline itself writes (the plan, `tasks.md`, `session-state.md`, the regenerated `model.likec4.json`, and the generated knowledge-base index file if a hook rewrites it).
- [ ] ADR-241 D11 reads `adopting` (Status bullet and Statuses row) with one new Amendment-log entry; ADR-232 marker, runbook rows (including the cause-to-stage table, proof command, ordered rollback, rotation addendum), the recovery row and every false C4 edge sentence updated; `model.likec4.json` regenerated; `c4-count-parity` and `c4-model-freshness` green; `lint-infra-no-human-steps.py` green on every changed markdown file; the `git grep` residual checks are empty.
- [ ] The proof tracker issue exists and is linked from the PR body; the PR body carries `Closes #9321`, the evidence with its timestamp, the hand-off block, and no `#N` of a closed issue; CI is green; the PR is left unmerged (no auto-merge, no admin merge).

### Post-merge (operator-side; performed by neither CI nor this pipeline)

- [ ] The proof dispatch in the tracker issue is green through `Verify DOPPLER_TOKEN_INFRA_APP present` and the mint, its notice shows `source=soleur-infra-app/prd`, and D11 flips to `accepted` (evidence: run id, `head_sha` at or after the merge SHA, step conclusion).

## Domain Review

**Domains relevant:** engineering (CTO), legal (noted, out of scope)

### Engineering (CTO)

**Status:** reviewed (carried from the predecessor plan's CTO assessment and its 12-seat review, plus this plan's five-agent review). **Assessment:** project-not-config, operator-minted token, no secret in state; boundary stated honestly as least privilege by reference under a main-only policy. This plan adds the composite's third caller, resolved by an explicit validated input rather than a move.

### Legal (CLO)

**Status:** reviewed (scoping only). **Assessment:** no new processing activity or data category; the Article 30 register's mention of the Tier-B token is a legal document and out of scope by the operator's standing constraint.

### Product/UX Gate

**Tier:** none (no user-facing surface; no `components/**`, `app/**/page.tsx` or `layout.tsx` path).

## Test Scenarios

1. Composite fixture, default run: argv equals the two reads with `soleur-infra-app`; token output and notice (`source=` field) as pinned.
2. `doppler-project: soleur-infra-privileged` run: reads that project and succeeds; an unlisted value is refused with zero Doppler and zero curl calls.
3. Composite copy defaulting to the retired project, or accepting `soleur`, or dropping `--config` on the second read: each reddens its named row.
4. Real release workflows: step-shape rows green with the new secret and step name; each broad-secret mutation reddens the exact rows and `no-broad-tier-b`.
5. Marketplace-verify job: `mint:doppler-project` and `mint:doppler-token` pin the broad shape; dropping the project line reddens it.
6. Census G7f: M1-M7 and M2b RED; H2 must-PASS fixture GREEN; empty tree RED; live tree reports three callers; deleting G7f from a control copy reddens `G7h2`.
7. `c4-model-freshness` green after regeneration; `c4-count-parity` green.

## Risks and Mitigations

- **The composite's input widens its surface by one validated value.** The validation runs before any Doppler call, the default is the narrow project, and Doppler refuses a token used on a project it is not scoped to; census G7f pins the allow-list and the call shapes.
- **Suites pin step names and secret names exactly.** Renames and pins move in one diff; Phase 1 writes them first and confirms RED against current main.
- **Exact floors drift and concurrent PRs collide on them.** Floors (`MUTANT_FLOOR` exact; the others `<` floors) are raised to measured counts after the final row set; the hand-off block tells the operator to rebase and re-measure before merging; the C4 JSON is regenerated on conflict.
- **A merge-time release run** (Decide `would-mint`) uses the unproven credential; see Landing Order.
- **Stale copy after an App-key rotation** is detected only at run time (accepted, stated in D11); the rotation order and the bootstrap's copy stage keep the copies equal.
- **The runtime-key boundary stays nominal.** Unchanged by this work and stated in D11.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Move all three callers to the narrow token (no input) | No security gain for the third caller, and it couples the ruleset-repair apply to the second App-key copy; reverses D11 as merged (this was the first draft) |
| A sibling composite for the third caller | Duplicates the JWT recipe a third time (the composite exists to avoid that) |
| Fallback to the broad token when the narrow secret is empty | Keeps the broad token reachable; a silent downgrade is worse than a loud failure |
| Fold the new census property into G7d | Different property and population |
| Leave the proof flip to memory | A tracker issue with the command and a decision tree owns it |

## Non-Goals

GHCR retirement; the legal cluster (`cla.yml` allowlist, legal documents including the Article 30 register, which still names the Tier-B token); widening the live App's grant; moving or evicting the runtime key; any change to the other Tier-B consumers or to the infra-credentials loader; a release-scoped App (recorded in D11 as the structural follow-up); automatic reconciliation of the two App-key copies; a stale-copy detector in the third caller's job.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; it is filled above.
- Do not put a `[skip-...]` kill-switch line in the PR body; none is needed and a squash message would carry it.
- The discoverability probe and several suite anchors count exact strings (`default: soleur-infra-app` once in the composite; anchors that must occur exactly once). Put a short comment beside those lines saying a count is pinned, and do not repeat the strings in prose.
- The census is a census of spelled patterns; its header says what it does not cover. G7f derives its population but cannot prove every spelling.
- The compliant BASE fixture itself needs the composite and callers (Phase 1.4), not just each mutant copy; per-mutant copies would leave the control census red.
- Existing suite rows that mention `DOPPLER_TOKEN_INFRA_PRIVILEGED` for OTHER jobs (the loader callers) are unchanged.
- The mint suite pins the `::notice` line exactly; changing its format touches the suite row, the runbook's O4c wording and ADR-241's D5 evidence phrase together.
