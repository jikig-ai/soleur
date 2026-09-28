---
title: "feat: auto-mint the vinngest-v* tag when a push to main changes a baked inngest-bootstrap carrier"
date: 2026-09-27
slug: feat-auto-mint-vinngest-tag-on-carrier-change
branch: feat-one-shot-4326-vinngest-auto-mint
issue: 4326
closes: 4326
type: feat
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# feat: auto-mint the vinngest-v* tag when a push to main changes a baked inngest-bootstrap carrier

## Enhancement Summary

**Deepened on:** 2026-09-27. The plan-review round (DHH, Kieran, code-simplicity, CTO devex) was
followed by a deepen round (security-sentinel, architecture-strategist, test-design-reviewer,
observability-coverage-reviewer, git-history-analyzer, and a verify-the-negative/self-audit
sweep).

### Key improvements

1. **Credential isolation (security P1-1, P1-2).**
   - The tag and the dispatch are separate steps and processes, and each sees only its own token.
   - The App token is minted only after the tag succeeds, and is scoped to `actions:write` on
     `soleur` through reinstated composite inputs (Phase 2b).
2. **Cut after both review panels fired on it.** The runs-list self-heal and the dispatch retry are
   gone: the runs list lags the dispatch, so either mechanism could double-build a tag. Recovery is
   one printed `gh workflow run` line, plus the runbook recovery table.
3. **The fake `gh` replays real GitHub contracts** (test-design P0).
   - It returns multi-line bodies and a real `git mktag` tag object.
   - It gives 422 semantics and real `gh` exit behaviour.
   - Assertions check annotated-tag identity rather than tag counts.
   - The fixture conventions are named.
4. **ADR-232 amendment content made precise** (architecture P1).
   - The title's "never `GITHUB_TOKEN`" is scoped to PR authoring, and the least-scope sentence is
     corrected.
   - After #8209, the manual fallback is `gh workflow run mint-inngest-bootstrap-tag.yml`, not a
     hand-tag.
   - The two-in-flight bump hold is recorded as R12.
5. **Observability.**
   - New failure modes for a `decide` fatal and for Slack being unset.
   - The partial coverage of a missed run is stated honestly, with follow-up #9082.
   - The dry-run exit-code and stdout contract is set for preflight Check 10.

### New considerations discovered

- The tag write and dispatch pass no gate that inspects the image's *content*. The human tagging
  step was, in practice, a second content approval, and that step is now gone (User-Brand Impact).
- The evidence cited for R1 is weaker than first stated.
- An attribution fix: `wg-` rather than `hr-` on the deferral rule.

## Overview

Since #8775 (ADR-232 §7), a `vinngest-v*` tag must sit on a commit reachable from `main`, so a PR
that edits a file baked into the `soleur-inngest-bootstrap` image can only be tagged after it
merges. Until someone cuts that tag, `main`'s Guard A row in `deploy-script-tests` stays red. This
plan closes that window in CI: a workflow on `main` detects that the image inputs changed relative
to the newest merged tag, allocates the next version above every existing `vinngest-v*` tag, and
creates the annotated tag with the `soleur-ai` GitHub App installation token so the existing
publish-and-bump pipeline runs unattended.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

- **#4326** is OPEN (`deferred-automation`, p3). Its body predates #8747: it describes a 24h
  operator tagging window. The 2026-09-24 comment on it (written with #8775) supersedes that body. It
  recommends minting the tag on `main` and then **dispatching** `build-inngest-bootstrap-image.yml`
  from `main` with `inputs.ref=<new tag>`.
- **#6766** is OPEN. Its 2026-09-24 comment carries an ordering warning: if GuardA becomes a
  required check before #4326 lands, every carrier-changing PR deadlocks. It also says that #4326
  *alone* does not remove the PR-side red (see Research Reconciliation).
- **#8775** is MERGED (ancestry refusal). **#9049** is MERGED: it selects the pin target from tags
  merged into `main`, and it closed issue #8782. Both premises in the ask hold on `origin/main`
  (`1c2f76ae8c`).
- The selector on this worktree resolves `v1.1.40`. `main` pins `v1.1.40`. All 13 carriers are
  byte-identical between `vinngest-v1.1.40` and `HEAD` (measured:
  `git diff --quiet vinngest-v1.1.40 HEAD -- <each cp path>` prints nothing). The **first** run of
  the new workflow, which this PR's own merge triggers, must therefore end `result=noop`.
- **App-token capability, verified rather than assumed**
  (`hr-verify-repo-capability-claim-before-assert`). The repo does NOT use
  `actions/create-github-app-token`; `grep -rln create-github-app-token .github/workflows` returns
  nothing. It mints through the in-house composite `.github/actions/mint-soleur-ai-app-token`
  (App-JWT → `/app/installations/122213433/access_tokens`). Today its only consumer is
  `bump-cloud-init-pin`. Measured with `gh api /orgs/jikig-ai/installations` (read-only), the
  `soleur-ai` installation 122213433 holds `actions:write`, `contents:write`,
  `pull_requests:write`, `administration:write`, `secrets:write`, and **no `workflows`**. The
  composite's doc comment lists only `contents:write + pull_requests:write`, so it understates the
  grant. The App can therefore do both things: create a tag (which fires `push: tags`) and dispatch
  a workflow.
- No tag ruleset exists (`gh api repos/jikig-ai/soleur/rulesets` lists four branch rulesets). Every
  existing `vinngest-v*` tag was cut by a human (`git for-each-ref refs/tags --format='%(taggername)'`),
  so nothing in this repo has ever created a tag from CI.

### Property List (Phase 0.6b)

- **P1.** When a push to `main` changes what the bootstrap image would contain, a
  `vinngest-vX.Y.Z` tag lands on that commit and the image is published, with no human action.
- **P2.** The version sorts above EVERY existing `vinngest-v*` tag, whether on or off `main`
  (ADR-232 §7 "Version allocation").
- **P3.** No write uses a PAT (`hr-github-app-auth-not-pat`). The write that starts the build runs
  as the `soleur-ai` App installation.
- **P4.** A push that does not change the image mints nothing. That includes the pin-bump PR's own
  merge, which must not cause a loop.
- **P5.** Exactly one publish runs per minted tag, from `main`'s copy of the workflow. This is what
  lets #8209 later bind the bump job to a main-only environment (ADR-232 §7, model.c4
  `github -> soleurMarketplace`).
- **P6.** Every failure is loud: a stage-named `::error::`, a Slack post, and the existing
  AC6/Guard A backstop on `main`.
- **P7.** GuardA (`deploy-script-tests`) does not become a required check before P1 exists, and the
  residual PR-side prerequisite is tracked.

### Cut List (Phase 0.6b)

- *Scheduled reconciler cron* (#4326 option c) → P1 → cut. The decision is tag-vs-HEAD, so a
  `push` trigger alone self-heals: any later qualifying push re-evaluates. ADR-232 already rejected
  a cron reconciler for the same drift-window reason.
- *A new `vinngest-version-bump` release workflow with its own cadence* (#4326 option b) → P1/P2 →
  cut. It duplicates the existing tag→build→bump chain; one minting job in front of that chain is
  enough.
- *Push-diff (`before..after`) change detection* → P1/P4 → cut in favour of comparing against the
  merged-max tag. Two things make the diff approach lose events: a dropped run (concurrency
  replaces a pending run) and the paths filter skipping a >3,000-file push. The tag comparison
  covers both, because the next run compares against the tag and not against the previous push.
- *A new App or a PAT* → P3 → cut. The existing `soleur-ai` installation already holds
  `actions:write`.
- *Plan-review round-1 cuts* (DHH, simplicity and Kieran).
  - *Runs-list self-heal and dispatch retry* → P1/P6 → cut. A green `noop` re-run is disclosed
    (R11), and the lookup races the dispatch (see A10).
  - *Non-main refusal STEP* → cut. Deepen-plan (security, architecture) corrected the reason:
    a branch `workflow_dispatch` runs that branch's YAML, so `ref: main` does not help. A job-level
    `if: github.ref == 'refs/heads/main'` stops an accidental branch dispatch, but not a malicious
    one; the real control is #8209's main-only environment.
  - *Composite token scope-down* was cut in round 1 (A12), then **reinstated at deepen-plan**
    (security P1-2). An unscoped `administration:write`/`secrets:write` token for one
    `actions:write` call is a security finding, not a YAGNI one.
  - *Separate carrier-set comparison* → folded into the blob comparison over the union.
- *Post-dispatch polling for the build run* → P6 → cut. A 204 from the dispatch API is the
  acceptance signal. The build and bump jobs already post to Slack on failure, and AC6 on `main` is
  the backstop.

### Relevant files (cited by content anchor)

- `.github/workflows/build-inngest-bootstrap-image.yml`:
  - `on: push: tags: ['vinngest-v*.*.*']` + `workflow_dispatch: inputs.ref`.
  - `Validate dispatch ref`: the inline regex.
  - `Refuse a commit that is not on main (#8747)`.
  - The `cat > "$BUILD_DIR/Dockerfile" <<DOCKERFILE` recipe.
  - `Read pinned inngest-cli + vector versions + SHAs from *.tf`: the four image-input pins.
  - Job `bump-cloud-init-pin`: runs the composite mint and then `bump-inngest-bootstrap-pin.sh`.
- `.github/scripts/bump-inngest-bootstrap-pin.sh` has five patterns to reuse:
  - the xtrace refusal block ("xtrace refusal (#7797)");
  - the `GIT_TRACE*` scrub;
  - the stage-named `die`, `emit_result` and `summary` helpers;
  - the shallow and walk-stderr refusals ("ancestry (history visibility)");
  - the **AC6-identical 3-line selector** ("AC6-IDENTICAL PIPELINE").
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`:
  - `Guard 2: workflow shape + selector byte-equality`, the `g2.sel:*` rows. This is the parity
    method to reuse.
  - A fixture bare origin, PATH-shimmed `gh`/`crane` and real `git`.
  - `MIN_ASSERTIONS` anti-vacuity floor.
- `.github/scripts/test/run-all.sh` globs `test-*.sh` and has a `MIN_SUITES=13` floor, which must be
  raised to 14. CI runs it from `pr-quality-guards.yml`.
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, Guard A ("Guard A (#7695) —
  carrier coherence"):
  - The carrier set comes from the `cp apps/web-platform/infra/<file>` staging lines (`GA_CP_PATHS`).
  - The `cp`/`COPY` cardinality is cross-checked.
  - The section has an exact-count anti-vacuity row (`expected 11`).
- `.github/actions/mint-soleur-ai-app-token/action.yml` is the composite App-token mint. It
  refuses the `EVICTED_SEE_ADR_241` sentinel.
- `tests/scripts/test-infra-privileged-tier-census.sh` scans every workflow and composite. A job is
  Tier B when it names an environment secret. The new job names none, and the composite already
  satisfies G4e, so the census stays green. Run it anyway.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` has the Group 4
  "App-token minters" table. A new consumer needs a row there.
- `knowledge-base/engineering/architecture/diagrams/model.c4`, edge `github -> soleurMarketplace`:
  its prose ends "the compatible shape is dispatching the build from main (#4326)". This PR makes
  that true for auto-minted tags, so the prose must change.
- `.github/workflows/infra-validation.yml` has run `deploy-script-tests` on `push` to `main` since
  #7299, on the `apps/*/infra/**` paths. `main-health-monitor.yml` runs the drift guard on `main`
  and files `ci/main-broken`. Both are the backstop for P6.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`, §"Bootstrap-image release
  (tag → build → deploy → verify)", step 1 and "Carrier-changing PR flow": these become the
  manual *fallback*.

### Institutional learnings applied

- `2026-09-27-git-tag-merged-fails-open-and-an-equality-guard-covers-only-its-slice.md`:
  `--merged` fails OPEN on a shallow graft or a missing object. Refuse both before resolving, and
  pin how the selected value is *consumed*, not only the selector lines.
- `2026-03-19-git-tag-sort-shallow-clone-semver.md` → allocation needs every tag: use
  `fetch-depth: 0` + `fetch-tags: true` + `git ls-remote --tags origin`.
- `2026-05-31-tag-driven-dispatch-invariant-and-checkout-refspec-tag-locality.md` → the build's
  dispatch arm checks out the fully-qualified `refs/tags/<ref>` and validates inline; the mint must
  pass a strictly-validated name.
- `2026-05-25-app-jwt-inline-mint-for-workflow-gh-api-administration-read.md` → reuse the
  composite, never a fifth inline copy.
- `2026-03-16-github-actions-workflow-dispatch-permissions.md` → a dispatch needs `actions: write`.
  Here the App token carries it, so the job's `GITHUB_TOKEN` does not need it.
- `2026-06-18-inngest-bootstrap-release-tag-then-dispatch-deploy.md` → the tag must be annotated.
  A build does not deploy, and deploy stays out of scope.
- `2026-05-20-hr-tagged-build-workflow-needs-initial-tag-push-...md`: the tag-triggered build
  already has tags. This PR adds no new tag-triggered workflow, so there is no seed-tag duty. The
  new workflow is push-to-main, and its first run is this PR's own merge.

### External facts (docs.github.com, via best-practices research)

- Events caused by `GITHUB_TOKEN` create no workflow runs, except `workflow_dispatch` and
  `repository_dispatch` (docs: "GITHUB_TOKEN"). An App installation token is not subject to that
  suppression.
- `POST /repos/{o}/{r}/actions/workflows/{id}/dispatches` needs the `actions: write` repository
  permission ("Permissions required for GitHub Apps").
- Concurrency: "At most one job or workflow run can be `pending` in the concurrency group. When a
  new … run is queued, any existing `pending` … run in the same group is canceled." Intermediate
  runs can therefore be dropped, and the tag-vs-HEAD decision is what makes that safe.
- Paths filter: if the diff has more than 3,000 files and the matching files are not among the first
  3,000, the workflow does not run. A push of more than 1,000 commits always runs.
- **UNCONFIRMED:** whether GitHub refuses to create a *tag ref* on an existing commit whose tree
  contains changed `.github/workflows/*` files when the token lacks `workflows` permission. The
  known refusal is documented only for pushes that create or update workflow files. This is a
  residual risk; see Risks R1.

### CLAUDE.md / AGENTS conventions in force

- `hr-github-app-auth-not-pat`.
- `hr-no-ssh-fallback-in-runbooks`.
- `hr-observability-as-plan-quality-gate`.
- `cq-write-failing-tests-before`: the fixture suite is written first.
- `wg-architecture-decision-is-a-plan-deliverable`: the ADR-232 amendment and the model.c4 edit
  ship in this PR.
- `cq-cite-content-anchor-not-line-number`.
- `wg-when-deferring-a-capability-create-a`: the GuardA PR-context exemption gets an issue (#9081).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / ask) | Reality on `origin/main` | Plan response |
|---|---|---|
| #4326 body: "Operator must tag within 24h … option (a) push + paths-filter, (b) release workflow, (c) cron" | #8775 made in-PR tags impossible (§7). The 2026-09-24 comment recommends *mint on main, then dispatch from main*. | Option (a) with the dispatch shape. (b) and (c) are cut (Cut List). |
| Ask: "grep the workflows for create-github-app-token" | No workflow uses it. The repo's pattern is the composite `mint-soleur-ai-app-token`. | Reuse the composite; add optional scope-down inputs (Phase 2b, reinstated at deepen-plan). |
| Ask: "the mint has to use an App installation token, OR dispatch the build explicitly" | The App holds both `contents:write` and `actions:write`. An App-created tag fires `push: tags`, so a dispatch on top of it builds the same tag twice. | Dispatch from `main` with the App token. The tag is created with the job's `GITHUB_TOKEN`, *because* that event is silent. See Alternatives A1–A3 and the decision challenge. |
| #6766 comment: "#4326 closes the deadlock" (implied) | #4326 closes the **main-side** window only. On a carrier-changing PR, GuardA still compares the pinned tag to the PR's HEAD and reds, by construction. | GuardA stays advisory. **#9081** (filed at plan time) tracks a GuardA PR-context exemption, plus moving the AC6 anchor to `origin/${GITHUB_BASE_REF}` (the ADR-232 Alternatives "Re-evaluate when #6766/#6480…" row). It is *blocked by* #4326 and *blocking* #6766. |
| "Carrier" = a file baked into the image | Guard A's carriers are the 13 `cp`-staged files. The image also depends on the 4 binary pins (`inngest_cli_version/sha256`, `vector_version/sha256`) and on the Dockerfile recipe in the workflow. | The mint's image-input set = carriers ∪ pins ∪ recipe. A pin or recipe change must also ship (runbook: "bumped `inngest_cli_version`" requires a release). |

## Proposed Solution

A new workflow, `.github/workflows/mint-inngest-bootstrap-tag.yml`, runs on `push` to `main` and
on `workflow_dispatch`. The push trigger is paths-filtered to the image's source tree; the
dispatch trigger is a catch-up for a push the filter skipped. It drives a new script,
`.github/scripts/mint-inngest-bootstrap-tag.sh`, which is fixture-tested out of band like the bump
script. A workflow cannot be dispatch-tested from a branch, so the YAML stays a thin driver.

```text
push to main (paths: apps/web-platform/infra/**, the build workflow, this workflow, this script)
  └─ mint job (concurrency inngest-bootstrap-automint, cancel-in-progress: false)
      1. checkout ref: main (the tip), fetch-depth 0, fetch-tags, persist-credentials false
      2. script --dry-run          → result=noop|would-mint     (git only, NO credential)
      3. [would-mint] script --tag → decide → allocate → tag    (env: MINT_TAG_TOKEN only)
      4. [tag ok]  Doppler CLI + mint-soleur-ai-app-token (scoped: actions:write, repo soleur)
      5. [tag ok]  script --dispatch <tag>                      (env: MINT_DISPATCH_TOKEN only, once)
      6. [failure()] Slack (SLACK_RELEASES_WEBHOOK_URL, payload built with jq)
  └─ build-inngest-bootstrap-image.yml  (workflow_dispatch, ref=main, inputs.ref=vinngest-vN)
      build (checks out refs/tags/vinngest-vN, ancestry on-main ✓) → bump-cloud-init-pin → pin PR
```

**Decision rule (stage `decide`).** Let BASE be the semver-max `vinngest-v*` tag merged into HEAD,
chosen by the AC6-identical 3-line selector. Mint iff HEAD would build different image inputs than
BASE. That is the case when any of these holds:

- (a) a carrier differs between BASE and HEAD. The carrier set is the union of the `cp` staging
  lines in BASE's build workflow and in HEAD's, extracted with Guard A's line. A carrier missing on
  either side counts as a difference, so an added or removed carrier is caught as well.
- (b) any of the four image pins differs: `inngest_cli_version` and `inngest_cli_sha256` in
  `inngest.tf`, `vector_version` and `vector_sha256` in `vector.tf`. They are extracted with the
  build step's own `grep -E` patterns.
- (c) the Dockerfile heredoc block differs.

**HEAD-side extraction is fail-closed.** An extractor that finds nothing would compare equal and
silently noop, so each of these is fatal at `decide`:

- HEAD's carrier set is empty.
- HEAD's `cp` staging count differs from its `COPY` count, or the two name different files. This
  mirrors Guard A's cardinality rows. A carrier staged from outside `apps/web-platform/infra/`
  would be invisible both to the extractor and to the paths filter (spec-flow G7).
- The heredoc extraction does not find **exactly one** block. The block starts at the
  `cat > "$BUILD_DIR/Dockerfile" <<DOCKERFILE` line and ends at the first following line matching
  `^[[:space:]]*DOCKERFILE$`. A bare "DOCKERFILE" in a comment must not match.
- `inngest_cli_version` or `inngest_cli_sha256` is empty on HEAD.

The two vector pins may legally be empty, because the build treats empty as "skip Vector". They are
compared as-is, empty included. `vector_sha256_arm64` is excluded because it is not baked into the
image (spec-flow G8). When BASE's own extraction is empty, because an old tag had a different
layout, the result is a *mint*, not a fatal.

The build step's inputs outside the heredoc are NOT compared. These are the `curl …linux_amd64…`
download URL and the `docker build` flags. This is residual R9.

**Why BASE and not the push's `before` SHA.** Comparing against a tag is idempotent. Three things
are corrected by the next qualifying push or by a `workflow_dispatch`: a dropped run (concurrency
replaced a pending one), a push the paths filter skipped, and a mint that failed before creating
its tag. A bump-PR merge only changes `cloud-init*.yml`, which is not an image input, so it
decides `noop` (P4: no loop). HEAD already tagged, or HEAD's content equal to BASE's, also decides
`noop`.

**Allocation (stage `allocate`, P2).** ALL is the output of
`git ls-remote --tags origin 'refs/tags/vinngest-v*'`, the authoritative remote view. The `^{}`
peel lines are stripped first (spec-flow G10).

- The maximum is taken over the numeric `X.Y.Z` prefix of every name matching
  `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+`. Suffixed names count (`-rc1`, `.4`), so NEXT sorts above
  every existing name.
- NEXT = `vX.Y.(Z+1)`.
- Assert that NEXT is absent from ALL and that `sort -V` ranks NEXT last.
- Refuse (`stage=allocate`) any tag whose version component has more than 6 digits, since
  `Z+1` must not overflow on a crafted remote tag. NEXT must match
  `^vinngest-v[0-9]+\.[0-9]+\.[0-9]+$` before any POST (security P2-4).
- No merged tag at all (the resolve selector is empty) → `result=would-mint reason=no-base`.
  Every input then counts as changed. This is not an error (observability P2).

An off-main `v1.1.50` above a merged `v1.1.40` gives NEXT `v1.1.51`, while BASE stays `v1.1.40`.

**Tag (stage `tag`).** Create an annotated tag over REST with the job's `GITHUB_TOKEN`
(`permissions: contents: write`). GitHub fires no workflow from a `GITHUB_TOKEN` event, so no
`push: tags` build starts.

1. Re-read `git ls-remote --tags origin 'refs/tags/vinngest-v*'`. If any strict `vinngest-vX.Y.Z`
   tag already peels to HEAD, a human or a concurrent run tagged this commit. End with
   `result=noop reason=concurrent-tag` and create nothing. Two tags on one commit would mean two
   builds.
2. `POST /git/tags` with `{tag, message, object: HEAD, type: commit, tagger: github-actions[bot]}`.
   The message names the run URL, the HEAD SHA, the `changed=` reasons and `#4326`. The body is
   built with `jq -n --arg` and piped to `gh api … --input -` (the repo's REST ref precedent is
   `fix-constraints-stage-b.yml`, "Draft follow-up PR" block). It is never string-built. The tag
   object SHA is read from the response with `jq -r .sha`, not with `grep`: the response carries a
   second `sha` under `.object`, which is the commit (test-design P0-1).
3. `POST /git/refs` with `{ref: "refs/tags/<name>", sha: <tag-object-sha>}`.

Any 422 is fatal (`stage=tag`); a re-run re-decides from a fresh re-read. A response body that
mentions the `workflows` permission is fatal with `reason=workflows-permission`, so residual R1 is
distinguishable from a name race. Error output prints a `reason=` class plus the response body's
byte length, never raw body bytes (observability + security P2-5). Afterwards, verify that `git ls-remote origin refs/tags/<name>^{}`
peels to HEAD.

**Dispatch (stage `dispatch`, a separate step and process: `--dispatch <tag>`).** Re-validate
`<tag>` against the strict regex and require that it peels to a commit on `origin/main`. Then call
`POST /actions/workflows/build-inngest-bootstrap-image.yml/dispatches` exactly **once**, with the
App token and the body `{ref: "main", inputs: {ref: "<name>"}}`. There is no retry. A retry after
a lost 2xx could start a second build of the same tag and move its digest; the plan review
(Kieran, simplicity, DHH) cut both the retry and a runs-list self-heal, because the runs list lags
the dispatch.

On failure the stage is fatal. The `::error::` line and the Slack post carry the exact,
agent-runnable remediation: `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<name>`.
They never suggest deleting or reusing the tag, which is now the merged max. The runbook's recovery
table repeats this.

On a later run, `noop` prints `::notice::base=<BASE>`, naming the tag it compared against. The
`inngest-server.md` recovery table tells the reader to check that BASE has a build run. A green
re-run therefore reads as "compared against BASE", never as "published" (the CTO/advisor
recovery concern, met without a racy lookup).

**Result contract.** Exactly one terminal line: `result=noop|would-mint|tagged|dispatched|error`.

- `--tag` ends `tagged` and `--dispatch` ends `dispatched`.
- The line goes to **stdout**, because preflight Check 10 discards stderr.
- `--dry-run` exits 0 on both `noop` and `would-mint`.
- Writes to `GITHUB_OUTPUT` and `GITHUB_STEP_SUMMARY` use the bump's `[[ -n "${GITHUB_OUTPUT:-}" ]]`
  guard, because both are unset in the sandbox.
- Only fixed-vocabulary values reach `GITHUB_OUTPUT`: `result` and the validated `tag`.
- Also emitted: `base=`, `changed=`, `reason=`, and a `$GITHUB_STEP_SUMMARY` block. The `noop`
  summary prints each comparison made (carriers, pins, recipe), so a skipped pin or recipe check is
  visible (observability P1).
- Every `::error::`/`::notice::` payload has `%`, `\r` and `\n` percent-encoded.
- Fatals are stage-named: `args|ancestry|resolve|decide|allocate|tag|dispatch`.

## Technical Approach

### Implementation Phases

**Phase 0: tests first (`cq-write-failing-tests-before`).** Write
`.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` from the Guard Contract matrices below.
The harness mirrors the bump suite:

- a real `git` working clone, plus a bare fixture origin;
- a synthesized minimal build workflow carrying the `cp`, `COPY`, `DOCKERFILE` and pin-read
  shapes;
- a synthesized `inngest.tf` and `vector.tf`;
- a PATH-shimmed `gh` that replays the real REST contracts.

The fake `gh` replays the real contracts (test-design P0-1):

- `POST git/tags` creates a real tag object in the bare origin with `git mktag`, and returns the
  documented multi-line pretty-printed body. That body carries both the tag's `sha` and
  `object.sha`.
- `POST git/refs` runs `update-ref` in the bare origin with the posted SHA as-is. It answers 422
  `Reference already exists` on a collision, derived from the origin's state rather than a flag,
  and 422 `Object does not exist` for an unknown SHA.
- The dispatch POST prints nothing and exits 0 for a 204.
- On an error it exits 1, with the body on stdout and `gh: … (HTTP 422)` on stderr, as real `gh`
  does.
- The `workflows`-permission message is **synthesized**, because GitHub's verbatim text is
  unverified. That row tests the classifier on the fake's wording, and a negative control proves
  that a plain 422 does not yield `reason=workflows-permission`.

Fixture conventions (plugins/soleur/AGENTS.md "Test Fixture Conventions"):

- Source `plugins/soleur/test/lib/git-fixture-env.sh`, as the bump suite does. It scrubs an
  inherited `GIT_DIR`/`GIT_INDEX_FILE` and arms the `rc=97` tripwire, and the scrub must also reach
  the spawned mint script.
- Copy the canonical `assert_fixture_dir`.
- Set `MIN_ASSERTIONS` to the green run's exact count.

Every row asserts all of these:

- exactly one `result=` line, with the matching `reason=`/`stage=`;
- the exit code;
- the `gh` call log;
- the origin tag set, and for a created tag: `cat-file -t` gives `tag`, it peels to HEAD, and its
  tagger and message are right. A lightweight tag must fail.

This is what makes even `noop` rows go RED against the `exit 0` stub.

Script-mutation rows follow three rules:

- each runs the unmutated temp copy as a positive control;
- each checks that the edit landed inside the target function;
- only rc 1 counts as caught, while rc 2 or 127 is reported as a broken instrument.

Raise `MIN_SUITES` in `run-all.sh` from 13 to 14. Every row goes RED against a stub script
(`exit 0`) before Phase 1.

**Phase 1: the script** (`.github/scripts/mint-inngest-bootstrap-tag.sh`).

- Preamble copied from the bump script's pattern. The xtrace refusal must be the FIRST
  statement after `set` (`lint-shell-trace-credential-refusal` Rule A); it triggers when either
  credential env var is set. Then `LC_ALL=C` and the `GIT_TRACE*` + `GIT_CURL_VERBOSE` unset
  (never `=0`). Also unset `GH_DEBUG` and `DEBUG`, since `gh` debug output can echo headers
  (security P2-6).
- Stages in the order `args → ancestry → resolve → decide → [allocate → tag → dispatch]`. The
  ancestry stage runs the two history-visibility refusals copied from the bump: a shallow checkout,
  and stderr from the `--merged` walk. There is **no** "HEAD reachable from `origin/main`" check.
  The workflow checks out `ref: main`, so the check could never fire there, and it would break
  `--dry-run` on a feature branch (Kieran P0-2).
- The selector block is copied byte-for-byte from the bump, modulo name, dir operand and
  indentation. The carrier extractor line is copied from Guard A's `GA_CP_PATHS` line. The pin
  `grep -E` patterns are copied from the build step.
- Credential inputs come from env: `MINT_TAG_TOKEN` holds `github.token` and reaches only the
  `--tag` step. `MINT_DISPATCH_TOKEN` holds the App token and reaches only the `--dispatch` step,
  which is minted after the tag succeeds (security P1-1).
  - Both names match the lint's `_TOKEN` expansion signal, so
    `lint-shell-trace-credential-refusal.py` actually scans this file (Kieran P0-1).
  - The script copies its one token into a local variable and `unset`s the env var first thing,
    then passes it per call as `GH_TOKEN="$tok" gh api`.
  - The correct claim is "never exported beyond its own step, never in a URL". `ls-remote` needs no
    credential because the repo is public, and a token-in-remote-URL form is forbidden.
- Test seams: `MINT_REPO_DIR` and `MINT_REPO` (the `owner/name` used in API paths).
- Three modes, each one step:
  - `--dry-run` runs only through `decide`, uses no network and needs no credential. It is the
    discoverability probe. It prints `tags=local`, reminding the reader to run
    `git fetch --tags origin` first on a laptop (CTO devex).
  - `--tag` runs decide, allocate and tag, and ends `result=tagged tag=<name>`.
  - `--dispatch <tag>` runs dispatch only.

**Phase 2: the workflow** (`.github/workflows/mint-inngest-bootstrap-tag.yml`).

- Triggers:
  - `on.push`: `branches: [main]` with the `paths` set above.
  - `on.workflow_dispatch`: no inputs.
- Top-level `permissions: contents: read`.
- One job, `mint`, gated `if: github.ref == 'refs/heads/main'` (security P2-3, architecture P2-5).
  It has `permissions: contents: write` and `timeout-minutes: 10`. The job needs no `actions`
  permission, because the dispatch uses the App token.
- `concurrency: {group: inngest-bootstrap-automint, cancel-in-progress: false}`.
- Pinned SHAs: reuse the exact `actions/checkout`, `DopplerHQ/cli-action` and composite pins
  from the build workflow. The composite is used unchanged, with `installation-id: "122213433"`.
- Steps:
  1. Checkout `ref: main`, the tip at run start rather than `github.sha`. Queued runs are not
     guaranteed to start in order, and a pending run for an older SHA can replace a newer one
     (spec-flow G1). Tagging the tip is always correct, because the tip holds every earlier change.
     A `workflow_dispatch` from a branch also lands on `main`'s tree.
  2. `Decide` (`--dry-run`), which writes `result` to `GITHUB_OUTPUT`.
  3. `Create tag` (`--tag`, if `result` is `would-mint`, env `MINT_TAG_TOKEN: ${{ github.token }}`),
     which writes the validated `tag` to `GITHUB_OUTPUT`.
  4. `Verify DOPPLER_TOKEN present`, Doppler CLI, and App mint. These run if step 3 produced a
     `tag`. The composite gets `permissions: '{"actions":"write"}'` and `repositories: soleur`.
  5. `Dispatch build` (`--dispatch "$TAG"`, env `MINT_DISPATCH_TOKEN` only).
  6. Slack `if: failure()` with `continue-on-error: true`. The payload is built with `jq`, the
     message is plain `curl`, and no third-party action is involved. An unset webhook emits
     `::warning::SLACK_RELEASES_WEBHOOK_URL unset`, as the build workflow does.

  Steps 3 and 5 each set `timeout-minutes: 5`, so a hang lands as a failure rather than a cancel
  (the bump's lesson).

**Phase 2b: the composite scope-down, reinstated at deepen-plan**
(`.github/actions/mint-soleur-ai-app-token/action.yml`).

- Add two optional inputs, `permissions` (a JSON object string) and `repositories` (a comma list).
- When either is non-empty, build the access-token body with `jq`, for example
  `{"repositories":["soleur"],"permissions":{"actions":"write"}}`. `repositories` must be a JSON
  array (Kieran P2-9).
- When both are empty, curl is invoked with **no `-d` at all**, byte-identical to today, so the
  bump job is unchanged.
- A small case in the new suite (or a sibling test) exercises the body-building shell with curl
  shimmed, and asserts both arms.
- Correct the stale "contents:write + pull_requests:write" doc comment to the measured grant.
- *Coordination:* #8209 plans "name inputs" on this composite. The new inputs are additive.

**Phase 3: the build workflow's comments only**
(`.github/workflows/build-inngest-bootstrap-image.yml`).

- The header and `workflow_dispatch` comment now say that dispatch is also the *first* publish of
  an auto-minted tag. The rebuild caution still holds for existing tags.
- The ADR-232 §7 tag-push caveat does not apply to auto-minted tags, because they are dispatched
  from `main`.
- No edit may land inside the `DOCKERFILE` heredoc or the pin-read step. Otherwise this PR's own
  merge would decide `would-mint` (AC5).

**Phase 4: architecture and docs.**

- ADR-232 amendment (§8 + Alternatives + Consequences + Verification). Architecture review
  requires these:
  - Scope the title's "never `GITHUB_TOKEN`" to the PR-authoring write. The `GITHUB_TOKEN writes`
    alternatives row gains a note that event suppression is *wanted* for the tag write.
  - Correct the Consequences "least-scope… PR-mediated" sentence. The App grant is measured, not
    least-scope, and the dispatch is not PR-mediated.
  - Record residuals R1, R6, R9, R10 and R12.
  - Record the #8798 dependency: §8 assumes strict ancestry. Content-equality would re-admit in-PR
    tags and a duplicate publish.
  - Record the #8781 constraint: candidate names must fall outside `refs/tags/vinngest-v*`.
  - Record the #8209 line. After #8209, the manual fallback is
    `gh workflow run mint-inngest-bootstrap-tag.yml --ref main`, not a hand-tag, because any
    human-created tag fires `push: tags`. A5 (drop `push: tags`) is a prerequisite of #8209.
- `model.c4` edge prose. Split "It is NOT a push-to-main job… runs on the vinngest-v* TAG ref" into
  the auto-minted case (runs from `main`) and the manual case (runs on the tag ref). Keep the
  addition to one sentence.
- The `infra-credential-tiers-8209.md` Group-4 row.
- `inngest-server.md` §Bootstrap-image release:
  - Step 1 becomes "automatic". The primary manual fallback is
    `gh workflow run mint-inngest-bootstrap-tag.yml --ref main`, which is idempotent and builds
    once. Hand-tagging is reserved for R1 (`reason=workflows-permission`), and only when no
    `vinngest-v*` tag already points at the merge commit (`git ls-remote`).
  - A **recovery table** keyed on `result=`/`reason=`/stage:

    | Signal | Action |
    |---|---|
    | `decide` fatal | Fix the extractor drift in the mint script |
    | `reason=workflows-permission` | Hand-tag the merge commit |
    | `dispatch` | Run the `gh workflow run … -f ref=<name>` line printed by the step; never hand-tag or delete |
    | A build or bump failure | Re-run that build run |
    | R12: a bump PR held with signed≠target | `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<max> -f mirror_only=true` (digest-preserving; re-arms auto-merge) |
    | `result=noop` but BASE has no build run | The dispatch was lost: run the `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<BASE>` line |
    | R8, an off-main BASE | Delete that tag per §7 |

- `main-health-monitor.yml`: the "13 fixture suites behind run-all.sh" text becomes 14
  (Kieran P2-8).

**Phase 5: coordination** (#6766). Done at the plan stage (2026-09-27); `soleur:work` only
re-verifies it (AC11).

- Filed **#9081**, the GuardA PR-context exemption plus the AC6 base-ref anchor. It is blocked by
  #4326 and blocks #6766. Its labels include `deferred-automation` and `meta/machinery`.
- #6766 is now blocked by #4326 and #9081.
- Posted a comment on #6766 stating the residual (issuecomment-5858268556).

## Files to Create

- `.github/workflows/mint-inngest-bootstrap-tag.yml`
- `.github/scripts/mint-inngest-bootstrap-tag.sh`
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`

## Files to Edit

- `.github/scripts/test/run-all.sh`: `MIN_SUITES=13` becomes 14, and the comment history line.
- `.github/actions/mint-soleur-ai-app-token/action.yml`: the optional `permissions` and
  `repositories` inputs (Phase 2b), plus the corrected grant doc comment.
- `.github/workflows/build-inngest-bootstrap-image.yml`: comments only. Nothing changes inside
  the `DOCKERFILE` heredoc or the pin-read step.
- `.github/workflows/main-health-monitor.yml`: the issue-body prose "the 13 fixture suites behind
  `.github/scripts/test/run-all.sh`" becomes 14.
- `knowledge-base/engineering/architecture/decisions/ADR-232-inngest-bootstrap-pin-bumps-are-authored-by-the-publish-workflow.md`:
  the amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the `github -> soleurMarketplace`
  edge prose.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`: a Group 4 row.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`: §Bootstrap-image release.

**Nothing under `apps/web-platform/infra/**` is edited.** This PR's merge therefore does not fire
`apply-web-platform-infra.yml`. If implementation ends up touching that tree, the PR body MUST say
instead that the paths-triggered apply fires on merge and is expected to be a no-op. It must never
say it does not fire.

## Alternative Approaches Considered

| # | Alternative | Why not |
|---|---|---|
| A1 | Create the tag with the App token and let `push: tags` build it (no dispatch) | It works, since an App-token event does trigger. But the run then executes on the TAG ref. #8209's main-only environment for the Tier-B bump job would refuse it, and a tag-pattern policy is forbidden (ADR-232 §7). ADR-232 §7 and the model.c4 edge both name "dispatch the build from main (#4326)" as the compatible shape, so A1 would force a redo when #8209 lands. |
| A2 | Create the tag with the App token AND dispatch | The App-created tag fires `push: tags`, so two runs build the same tag. The second rebuild MOVES the GHCR digest (non-reproducible `docker build`), the exact hazard the dispatch arm's CAUTION describes. |
| A3 | `GITHUB_TOKEN` for both the tag and the dispatch (no App) | Mechanically sufficient: `workflow_dispatch` is exempt from the suppression, and its run's ref is `main`, so P5 holds. The CTO review recommends it: no Doppler step, no App-key consumer to re-tier at #8209 step O10, no composite change. NOT adopted, because the operator's direction names the App installation token, and a stated direction stays the default under ADR-084. Recorded in `decision-challenges.md` as a User-Challenge. The switch is mechanical: delete the Doppler and App-mint steps and Phase 2b, and give the job `actions: write`. |
| A4 | Skip auto-minted tags inside the build's push path, by checking `github.actor` or the tag message, then dispatch | It adds a gate job to the publish workflow, keyed on an undocumented actor format (research Q7 unconfirmed). One more failure surface for no gain over A-chosen. |
| A5 | Remove `push: tags` from the build and dispatch every build | It changes the manual release flow and the runbook. It belongs with #8209, which must retire tag-ref bump runs anyway. |
| A6 | Push-diff detection (`before..after`) | It loses events: pending-run replacement, the >3,000-file paths skip, and failed runs. A tag-vs-HEAD comparison self-heals. |
| A7 | Scheduled reconciler | ADR-232 already rejected it: a bounded drift window and an always-on surface. |
| A8 | Carriers only, not pins or recipe | An `inngest_cli_version` bump or an `alpine` bump would merge and never ship. Guard A cannot see either one. |
| A9 | Whole-file diff of `inngest.tf`, `vector.tf` and the build workflow (DHH) | Unrelated Terraform edits to `inngest.tf` are frequent, so each one would mint a spurious release and open a spurious bump PR. This PR's own comment edit to the build workflow would also mint on merge. Pin and heredoc extraction costs about 10 lines. |
| A10 | Self-heal via a runs-list lookup keyed on a `run-name` and a tag trailer, plus a dispatch retry (review round 1) | Cut in plan review. Both panels fired on it (simplicity: no listed property; Kieran: the runs list lags a dispatch, so the lookup itself can double-build). The recovery is one agent-runnable `gh workflow run` line, printed by the failure and listed in the runbook table. |
| A11 | Roll back the tag when the dispatch fails (DHH) | After a lost 2xx, the build may already have checked the tag out. Deleting the tag then burns a name that GHCR may hold, which is the name-reuse hazard in §7. |
| A12 | Scope the App token down to `actions:write` through new composite inputs | Dropped in plan review, then **reinstated at deepen-plan** (security P1-2): the unscoped token carries `administration:write` and `secrets:write` for one `actions:write` call. It is Phase 2b. DC1 (A3) would remove the App token entirely. |

**Chosen:** App-token **dispatch** from `main`, with the tag created by `GITHUB_TOKEN`, because its
event suppression guarantees exactly one build (P5).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-232** rather than write a new ADR. ADR-232 owns this pipeline, holds the §7
version-allocation rule, and its Consequences already name #4326 as the step that closes the
window. The amendment:

- **§8 (new): "Auto-mint on `main`".**
  - The decision rule: BASE = merged-max, inputs = carriers ∪ pins ∪ recipe.
  - Allocation over all tags, by numeric prefix.
  - The tag is created by `GITHUB_TOKEN` because it is event-silent.
  - The dispatch is made from `main` by the `soleur-ai` App, once, with no retry.
  - Stage-named fatals.
  - The residuals: R1 (the `workflows`-permission question), R6 (a future tag ruleset needs a
    bypass), R9 (build-step inputs outside the heredoc), R10 (the dispatch runs `main`'s YAML at
    dispatch time).
  - The post-merge live-verification plan.
  - The #8209 line: the manual tag-push fallback must become create-then-dispatch when #8209 binds
    the bump job to a main-only environment.
- **Alternatives:** the rows A1–A12, in condensed form.
- **Consequences:**
  - The 2026-09-24 window ("until someone tags `main`") shrinks to one mint + build + bump cycle.
  - A third repository-write surface for CI: a tag create by `GITHUB_TOKEN`, and a dispatch by the
    App.
  - The manual tag push remains the fallback path, and still runs on the tag ref.
- **Amendment log:** a 2026-09-27 (#4326) entry.
- **Verification:** the new suite's rows.
- **#6766 prerequisites.** The existing Alternatives row "Re-evaluate when #6766/#6480 makes
  `deploy-script-tests` required" gains the new issue as the named prerequisite (GuardA PR-context
  exemption + AC6 base-ref anchor).

### C4 views

All three model files were read for this plan. `model.c4` and `views.c4` are searched for
`inngest`, `vinngest`, `soleur-ai`, `bump` and `github`, and `spec.c4` for element kinds.

- **External actors:** none new. No human is added. The operator's manual tagging becomes a
  fallback.
- **External systems:** GitHub (`github`) and GHCR (`ghcr`) are already modeled. No new vendor.
- **Containers / stores:** none new. The tag lives in the GitHub repository, which is already
  modeled.
- **Relationships:** the new write is github-internal. Self-relations cannot be expressed in this
  DSL (ADR-232 Verification). ADR-232 therefore documented the bump write on the
  `github -> soleurMarketplace` App-write edge, and this PR follows that precedent:
  - Append one sentence to that edge's prose. On a push to `main` that changes the image inputs,
    `mint-inngest-bootstrap-tag.yml` creates the `vinngest-v*` tag with `GITHUB_TOKEN` and
    dispatches the build from `main` as the `soleur-ai` App.
  - Rewrite the trailing clause "the compatible shape is dispatching the build from main (#4326)"
    to say that auto-minted tags now build from `main`, while a manual tag push still runs on the
    tag ref.
- **Cardinalities:** the change adds no Sentry heartbeat, monitor slug or Resend emitter, so
  `c4-count-parity` clauses do not move. The verification is a green
  `bash plugins/soleur/test/c4-count-parity.test.sh`, plus `scripts/regenerate-c4-model.sh` +
  `plugins/soleur/test/c4-model-freshness.test.sh` and the `c4-code-syntax` and `c4-render`
  tests.

### Sequencing

This is not a soak-gated decision. The ADR amendment is true as of merge, because the first
post-merge run (this PR's merge) exercises `decide → noop` live. The *mint* arm's first live proof
is the next carrier-changing merge, and it is recorded as an event-gated post-merge AC (AC14). This
is the same "end-to-end proof deferred by construction" consequence ADR-232 records.

## User-Brand Impact

- **If this lands broken, the user experiences:** no immediate breakage. A broken mint leaves the
  dedicated Inngest host's *next* provisioning on an older bootstrap image, which is today's manual
  state. The one user-facing path is a wrong tag: the pin bump would move fresh provisioning to an
  image built from the wrong commit. The ancestry gate (#8747), the revision-label binding and the
  mirror-gated auto-merge (ADR-232 §5, §7) still stand between a tag and a host. A deploy to the
  live host stays a separate `deploy-inngest-image.yml` dispatch.
- **If this leaks, the user's workflow is exposed via:** two credentials in the job's log.
  - The `soleur-ai` App installation token, scoped to `actions:write` on `soleur` (Phase 2b). It
    exists only in the dispatch step and is live for up to an hour. DC1/A3 would remove it.
  - The job's `GITHUB_TOKEN` with `contents:write`, which could push refs until the job ends.

  The xtrace refusal, the `GIT_TRACE*` unset and the per-call `GH_TOKEN=` binding (never in a URL)
  keep both out of logs. No user data is read or written.
- **Brand-survival threshold:** `none`
- `threshold: none, reason:` a CI-only tag and dispatch. No user data or live host is touched, and a
  live-host deploy remains a separate dispatch.
- **What changes for review (security P2-7).** The ancestry and mirror gates check *where* a tag
  sits, not *what* the image contains. Until now, a human tagging the merge commit acted in
  practice as a second approval of the image's bytes. After this change, anything merged to `main`
  that changes an image input becomes a published image and an auto-merged pin bump with no human
  step. The PR review of the carrier change is now the only content review. Verified: no `main`
  ruleset bypass actor lets unreviewed commits land. `CI Required` bypass is OrganizationAdmin and
  RepositoryRole 5 in `pull_request` mode only; `soleur-ai` is not a bypass actor.

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions run of mint-inngest-bootstrap-tag.yml, one per qualifying push to main; its step summary carries the terminal result= line"
  cadence: "per push to main touching apps/web-platform/infra/** or the build/mint workflow or the mint script; plus workflow_dispatch"
  alert_target: "Slack releases channel via SLACK_RELEASES_WEBHOOK_URL on failure()"
  configured_in: ".github/workflows/mint-inngest-bootstrap-tag.yml (Slack step, if: failure())"

error_reporting:
  destination: "GitHub Actions ::error:: annotation named by stage (args|ancestry|resolve|decide|allocate|tag|dispatch) plus the Slack post"
  fail_loud: "::error::<stage>: line, result=error, and a red run"

failure_modes:
  - mode: "dispatch fails after the tag was created"
    detection: "::error::dispatch + Slack, whose message carries the exact gh workflow run remediation (runbook recovery table); AC6 on main is the backstop"
    alert_route: "Slack releases channel (layer: GitHub Actions annotation + Slack webhook)"
  - mode: "tag creation refused for missing workflows permission (R1)"
    detection: "::error::tag reason=workflows-permission + Slack"
    alert_route: "Slack releases channel (layer: GitHub Actions annotation + Slack webhook)"
  - mode: "mint never ran (paths filter skipped a >3,000-file push, startup_failure, or the run was dropped): PARTIAL coverage"
    detection: "carrier changes only: the Guard A + AC6 drift guard in infra-validation.yml deploy-script-tests on push to main and in main-health-monitor.yml. A pin- or recipe-only change is NOT detected; tracked as R13 / #9082"
    alert_route: "ci/main-broken GitHub issue (layer: GitHub Actions CI check + main-health-monitor issue filing)"
  - mode: "decide fatal (extractor drift after a build-workflow refactor)"
    detection: "::error::decide + Slack"
    alert_route: "Slack releases channel (layer: GitHub Actions annotation + Slack webhook)"
  - mode: "SLACK_RELEASES_WEBHOOK_URL unset or the post fails, so a red run is unseen"
    detection: "::warning::SLACK_RELEASES_WEBHOOK_URL unset on the run; nothing else watches this workflow's conclusion yet (tracked in #9082)"
    alert_route: "none beyond the GitHub Actions run status (layer: GitHub Actions run log) — accepted residual R13"
  - mode: "build or bump fails after a successful auto-mint dispatch"
    detection: "build-inngest-bootstrap-image.yml's own publish-refused / mirror-degraded / pin-bump-failure Slack steps"
    alert_route: "Slack releases channel (layer: publish workflow)"
  - mode: "App key evicted from prd_terraform (#8209 O10) before this job is re-tiered"
    detection: "composite refuses with verdict=legacy_app_key_evicted; the job fails; Slack"
    alert_route: "Slack releases channel (layer: composite action annotation)"

logs:
  where: "GitHub Actions run logs and $GITHUB_STEP_SUMMARY of mint-inngest-bootstrap-tag.yml"
  retention: "GitHub Actions log retention for this repository (90-day default)"

discoverability_test:
  command: bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run
  expected_output: "result=noop or result=would-mint"
```

## Guard Contract

### Guard 1 — image-input drift decision

**Property.** `decide` returns would-mint exactly when HEAD's image inputs differ from BASE's. The
inputs are the carriers, the four image pins and the Dockerfile recipe block. It fails closed when
HEAD's own extraction is empty or incoherent.

**Assembly.** Both BASE and HEAD pass through one chokepoint: the `decide` function in
`.github/scripts/mint-inngest-bootstrap-tag.sh`. It reads four sources at each ref:

- the `cp apps/web-platform/infra/…` staging lines and the `COPY` lines of
  `.github/workflows/build-inngest-bootstrap-image.yml`;
- that workflow's single `DOCKERFILE` heredoc;
- the pin-read `grep -E` patterns applied to `apps/web-platform/infra/inngest.tf` and `vector.tf`;
- the carrier blobs, compared over the union of both sets.

The members can drift: a new carrier or a new pin. The staging and `COPY` lines are structural,
and a cardinality refusal protects them.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change only the LAST carrier (after 12 unchanged) | would-mint (RED if noop) |
| 2 | Hollow the comparator to always report "same" (guard's own dispatch; the instrument self-test pair must move, as in Guard A) | suite RED |
| 3 | Add a second changed input after a compliant first: carriers identical, and ONE pin changed. The row is table-driven over all four pins, one case each (test-design P1-6) | would-mint for each |
| 3b | Change only the FIRST carrier, the twin of row 1 | would-mint |
| 4 | Rename the staging prefix so the extractor finds 0 carriers on HEAD | fatal `decide`, not noop |
| 5 | Add a `cp` from outside `apps/web-platform/infra/` with its `COPY` | fatal `decide` (cardinality) |
| 6 | Change `FROM alpine:3.20` inside the heredoc | would-mint |
| 7 | Change only cloud-init pins (a bump-PR merge), must-PASS | noop |
| 8 | A comment-only edit to the build workflow outside the heredoc, including a comment that says `DOCKERFILE`, must-PASS | exactly one block; noop |

**Harness rows.** Replacing the script with `exit 0` reds the suite: the tag-count assertions
expect exactly one tag in the bare origin. The non-canonical must-PASS is a carrier change plus an
unrelated `.tf` edit in one commit, which yields exactly one tag.

### Guard 2 — version allocation above every tag

**Property.** NEXT sorts strictly above every existing `vinngest-v*` name on the remote, suffixed
names included. NEXT is absent from that set, and no second tag is ever created on a commit that
already carries one.

**Assembly.** `allocate` reads the output of `git ls-remote --tags origin 'refs/tags/vinngest-v*'`,
strips the `^{}` peel lines, applies the numeric-prefix regex and `sort -V`, and increments the
patch. The pre-create re-read in `tag` consults the same source.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | An off-main `v1.1.50` present ONLY on the remote (absent from the local clone) with merged max `v1.1.40` | NEXT `v1.1.51` |
| 2 | Replace `ls-remote` with the local `git tag --list` (the guard's own source) | row 1 RED |
| 3 | `v1.9.0` and `v1.10.0` both exist (swap `sort -V` → `sort`) | NEXT `v1.10.1`, lexical sort RED |
| 4 | `vinngest-v1.2.0-rc1` exists above `v1.1.40` | NEXT `v1.2.1` |
| 5 | Remove the `^{}` strip, with an annotated suffixed tag fixture | RED |
| 6 | REORDER: move the pre-create re-read after `POST /git/refs`. Built as a human tag on HEAD present ONLY in the bare origin, absent from the local clone the selector reads (test-design P0-2) | `noop reason=concurrent-tag` and zero POSTs; the reordered form sends POSTs, RED |
| 8 | A remote tag `vinngest-v1.1.9999999` (7 digits) | fatal `allocate`, zero POSTs |
| 7 | 422 "Reference already exists" | fatal `tag`, exactly one `git/refs` POST |

**Harness rows.** A shim `gh` that ignores the ref body leaves the tag-name assertion RED. The
must-PASS is a repo whose only tags are strict and merged, which yields max+1.

### Guard 3 — writer/checker parity and credential shape

**Property.** The mint script's copies of shared logic are byte-identical to their authorities,
modulo variable name, dir operand and indentation:

- the merged-tag selector, against the bump script and AC6;
- the carrier extractor, against Guard A's `GA_CP_PATHS` line;
- the pin `grep -E` patterns, against the build step.

Beyond byte parity, three shape properties hold:

- The mint workflow's `paths:` globs cover every `cp` source.
- The tag write is bound only to `github.token`, in its own step, and the App token only to the
  dispatch step.
- The checkout is `ref: main` and the job is main-gated.
- No PAT-named secret is referenced.

Every failure prints the authority file and each copy that must change with it, plus a diff (CTO
devex).

**Assembly.** Five files:

- `.github/scripts/mint-inngest-bootstrap-tag.sh`;
- `.github/scripts/bump-inngest-bootstrap-pin.sh`, whose "AC6-IDENTICAL PIPELINE" block is the
  authority;
- `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, Guard A;
- `.github/workflows/build-inngest-bootstrap-image.yml`, the pin-read step;
- `.github/workflows/mint-inngest-bootstrap-tag.yml`: the `paths:` globs, the job `if:`, the
  checkout `ref:`, and the env of the `Create tag` and `Dispatch build` steps.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the mint selector's `sort -V` to `sort` | RED |
| 2 | Edit Guard A's `cp` regex only | RED |
| 3 | The parity extractor finds 0 selector blocks in the mint script (the guard's own dispatch) | RED, not a vacuous pass |
| 4 | Add a second staged `cp` whose path no `paths:` glob covers, after a covered first | RED |
| 5 | Bind `MINT_TAG_TOKEN` to the App-mint output (would fire `push: tags`, a double build) | RED |
| 6 | Reference any `secrets.*PAT*` / `*_PAT` name | RED |
| 7 | Give the `Create tag` step `MINT_DISPATCH_TOKEN`, or the `Dispatch build` step `MINT_TAG_TOKEN` (the credential-isolation property) | RED |
| 8 | Change the checkout to `ref: ${{ github.sha }}`, or drop the job's `if: github.ref == 'refs/heads/main'` (spec-flow G1 at workflow level) | RED |

## Risks

- **R1: tag creation refused for missing `workflows` permission.** Unconfirmed; probability
  low-to-medium. The documented refusal covers pushes that bring in commits changing workflow
  files. A REST ref to a commit already on `main` brings in none, and the bump's App-token branch
  pushes already succeed without `workflows`. If the refusal happens it is loud
  (`reason=workflows-permission`) and atomic, since no tag is created. The fallback is today's
  manual runbook tag, which fires `push: tags` normally, so it cannot cause a double build. The
  exposure is highest for carrier-*adding* PRs, which edit the build workflow. A spike was not run:
  a tag write is a production write, which this session may not perform. The first qualifying merge
  is the live proof (AC14). Caveat from architecture review: the bump's App-token branch pushes
  do NOT settle R1, because those commits never touch workflow files. The evidence is only the
  documented scope of the refusal.
- **R2: the App key moves (#8209 step O10).** The mint's App step then fails with
  `verdict=legacy_app_key_evicted`, exactly as the bump does. The `infra-credential-tiers-8209.md`
  row makes #8209 re-tier this job alongside the bump. Because this is a push-to-main job, an
  `infra-privileged` binding works. DC1 offers removing this dependency entirely.
- **R3: a double build moves the digest.** The design closes every entry point:
  - `GITHUB_TOKEN` tag creation fires no `push: tags` build.
  - The pre-create re-read of the remote tags catches a concurrent tag.
  - The dispatch is sent exactly once, with no retry and no automatic re-dispatch.
  - Serialized concurrency keeps two mint runs apart.
- **R4: `main` goes red between a carrier merge and the bump merge.** The window shrinks from
  "until a human tags" to one mint+build+bump cycle. `main-health-monitor` may still file
  `ci/main-broken` inside it; that signal is truthful (ADR-232 Consequences).
- **R5: over-mint on a recipe comment edit** inside the heredoc. Benign: one build and one bump PR.
- **R6: a future tag ruleset on `vinngest-v*`** would need a bypass for the GitHub Actions
  integration. This is recorded in the ADR amendment.
- **R7: GuardA becomes a required check.** A carrier-changing PR still reds GuardA on the PR itself.
  Making `deploy-script-tests` required before the PR-context exemption lands deadlocks every such
  PR. The exemption is filed as #9081, which blocks #6766 (AC11).
- **R8: an off-main tag reaches `main` through a merge commit.** It becomes BASE with no image, and
  the mint decides `noop`. This is ADR-232 §7's documented residual; the remedy is deleting the tag.
  It stays out of scope here, and AC6 on `main` is the signal.
- **R9: build-step inputs outside the heredoc are not compared** (Kieran P2-5): the `curl` download
  URL and the `docker build` flags. Changing either without touching the heredoc or the pins does
  not mint; Guard A does not see it either. This is accepted and recorded in the ADR; a future
  change may compare the whole `Build + verify + push` step with comments stripped.
- **R10: the dispatch runs `main`'s workflow copy at dispatch time** (Kieran P2-6). If `main` moves
  between the checkout and the dispatch, version N gets a build recipe from a commit it does not
  contain. This is accepted and recorded in the ADR. The window is seconds, and the next qualifying
  push re-decides.
- **R12: two auto-mints in flight can leave a bump PR held** (architecture P1-3). Builds run in
  parallel, because their concurrency group is per tag. `inngest-pin-bump` keeps only one pending
  job, so v42's later bump can cancel v43's pending one. The survivor then targets v43 with
  signed≠target, so auto-merge is withheld (ADR-232 §5), and the cancelled job posts no Slack.
  Recovery is a digest-preserving
  `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<max> -f mirror_only=true`,
  which is in the runbook table. Accepted and recorded in the ADR; two carrier merges within one
  build cycle are rare.
- **R13: partial observability for a missed run** (observability P1). A skipped or dropped mint for
  a pin- or recipe-only change is not caught by Guard A. Nothing yet watches this workflow's
  conclusion if Slack is unset. Tracked as **#9082** (blocked by #4326).
- **R11: after a failed dispatch, a later run is green `noop`.** The tag then sits unbuilt. The
  failed run is red and posts to Slack with the exact `gh workflow run` line. `noop` prints
  `base=<BASE>`, the runbook table covers the case, and AC6 on `main` is the backstop. The
  alternative (A10) was cut because its lookup could itself double-build.

## Gates evaluated and not triggered

- **GDPR (2.7):** no regulated-data surface. The tag and its message carry only commit SHAs, a run
  URL and input reasons.
- **IaC (2.8):** no server, secret, vendor or DNS change. The workflow reuses the existing
  `DOPPLER_TOKEN` and `SLACK_RELEASES_WEBHOOK_URL` repository secrets.
- **Encryption posture (2.11):** no new store or cross-component connection. The GitHub REST API
  and GHCR edges already exist.
- **Skill description budget (1.8):** no SKILL.md is edited.

## Open Code-Review Overlap

None. Checked 86 open `code-review` issues against every Files to Create/Edit path; no body
references any of them.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed, twice: the Phase 2.5 domain sweep and the plan-review devex seat.

**Assessment:** The design is sound, and ADR-232 is the right ADR to amend. The CTO's
recommendations and their dispositions:

- **A3 (`GITHUB_TOKEN` for both writes).** Recommended twice, and DHH and simplicity concur. It is
  not auto-adopted, because the operator's direction names the App token. It is recorded as DC1.
- **R1 made distinct.** Adopted as `reason=workflows-permission`.
- **Recovery ergonomics.** Addressed by the runbook recovery table and the fallback rule that
  hand-tagging applies only when no tag already points at the commit.
- **GHCR-based self-heal.** Rejected, as was the narrower runs-list variant (A10): both can start
  a second build of a tag.
- **Manual-tag race.** Handled by the pre-create `ls-remote` re-read.
- **Future tag ruleset.** Recorded as R6.
- **Parity messages.** Every Guard 3 failure names the authority file and the copies that must
  change with it.
- **`--dry-run` hint.** It prints `tags=local`.
- **Deepen-plan (2026-09-27).** The security and architecture seats independently endorsed A3 on
  credential-tier grounds, and it stays DC1. Security P1-2 reinstated the composite scope-down
  (Phase 2b) for as long as the App path is kept.
- **#8209 fallback line.** Added to the ADR amendment.

### Product/UX Gate

Not relevant: no UI surface. The mechanical UI-surface override does not fire; no Files entry
matches the UI term list.

## Test Scenarios

The suite `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` covers five groups:

- Guards 1–3: every mutation-matrix and harness row above that is an input fixture. The rows that
  mutate the script or a sibling file run as mutate-a-temp-copy cases, the same method the bump
  suite's `g2.sel:*` rows use.
- Flow rows from spec-flow (a)–(m):
  - the bump-merge noop (a);
  - the non-carrier infra push (b);
  - the tip carrying changed carriers while an older SHA triggered the run, which must tag the tip
    (c/G1);
  - a concurrent human tag on HEAD, which must end `noop reason=concurrent-tag` (d/G2);
  - a failed dispatch, which must be fatal with the `gh workflow run` remediation, make exactly
    one POST, and never delete the tag (e);
  - an off-main max tag (g);
  - a carrier added and a carrier removed (i);
  - an `inngest_cli_version` bump, and empty vector pins on both sides, which must `noop` (j/G8);
  - a revert to older content, which must mint a higher version (l);
  - a suffixed tag (m).
- Ancestry refusals copied from the bump: a shallow checkout, and stderr from the `--merged` walk.
- The xtrace refusal: `bash -x` with either `MINT_*_TOKEN` set exits non-zero before any traced
  command. The `GIT_TRACE` unset.
- `--dry-run` on a non-main HEAD: it works and makes no network call. The shim fails the test on
  any `gh` invocation, and `origin` points at a nonexistent path, so a stray `ls-remote` also fails
  (test-design P2-8). It exits 0 on `would-mint`, and the no-merged-tag case yields
  `would-mint reason=no-base`.
- xtrace: seed a canary token value and assert it never appears in stderr or stdout (test-design
  P2-9).
- Composite scope-down (Phase 2b): with curl shimmed, empty inputs send no `-d`, and set inputs send
  exactly `{"repositories":["soleur"],"permissions":{"actions":"write"}}`.
- `--dispatch` with a tag that fails the strict regex, or that is not on `origin/main`, is fatal
  with zero POSTs.

## Acceptance Criteria

Plan ACs are numbered AC1–AC15. Elsewhere, "the AC6 drift guard" means the AC6 row of
`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, not this plan's AC6.

### Pre-merge (PR)

- [ ] **AC1.** `bash .github/scripts/test/test-mint-inngest-bootstrap-tag.sh` exits 0 with its
  anti-vacuity floor met. `bash .github/scripts/test/run-all.sh` exits 0 with
  `MIN_SUITES=14` (`.github/scripts/test/run-all.sh`, "Minimum-suite floor").
- [ ] **AC2.** Three checks show the suite is not vacuous:
  - replacing the script with `exit 0` reds the suite;
  - Guard 1's comparator instrument self-test is present;
  - Guard 3 row 3 (zero selector blocks found) is RED rather than passing.

  These are implemented as suite cases, not as a separate meta-harness.
- [ ] **AC3.** `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` and
  `bash tests/scripts/test-infra-privileged-tier-census.sh` both exit 0.
- [ ] **AC4.** `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
  (the `ci.yml` form) exits 0 and lists the new script among the files it scanned. A negative
  control (a temp copy with the xtrace preamble deleted) makes the lint exit 1, which proves the
  `MINT_*_TOKEN` names put the file in scope. `actionlint`, in the repo's `lint-workflows` form, is
  clean on both workflows.
- [ ] **AC5.** This PR's own merge cannot mint, which is the Standing-check-safe form. On this
  branch, `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` prints a `changed=` list
  that names no path in `git diff --name-only origin/main...HEAD`; it is empty whenever the branch
  sees no untagged carrier change from `main`. The suite's Guard 1 row 8 (a comment-only
  build-workflow edit decides `noop`) is the deterministic half, independent of what else has
  merged to `main`.
- [ ] **AC6.** `git diff --quiet origin/main...HEAD -- apps/web-platform/infra` exits 0. If it does
  not, the PR body must say that `apply-web-platform-infra.yml` fires on merge (no-op expected).
- [ ] **AC7.** ADR-232 carries §8 "Auto-mint on `main`" and an `## Amendment 2026-09-27 (#4326)`
  section. `grep -c 'Amendment 2026-09-27 (#4326)'` on the ADR is at least 1.
- [ ] **AC8.** The `model.c4` `github -> soleurMarketplace` prose names
  `mint-inngest-bootstrap-tag.yml` and no longer says only that dispatch from `main` is a future
  shape. These all pass:
  - `bash plugins/soleur/test/c4-count-parity.test.sh`;
  - `bash plugins/soleur/test/c4-model-freshness.test.sh`, after `scripts/regenerate-c4-model.sh`
    if the freshness test demands it;
  - the `c4-code-syntax` and `c4-render` tests under `apps/web-platform/test/`, via that package's
    vitest.
- [ ] **AC9.** `grep -c mint-inngest-bootstrap-tag` is at least 1 in both
  `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` and
  `knowledge-base/engineering/operations/runbooks/inngest-server.md`.
  - `inngest-server.md` carries the recovery table keyed on `result=`/`reason=`/stage.
  - Its step 1 reads as automatic, with hand-tagging only when no tag points at the commit.
  - It prescribes no SSH.
- [ ] **AC10.** `grep -c '14 fixture suites' .github/workflows/main-health-monitor.yml` is at least
  1, and `grep -c '13 fixture suites'` on the same file is 0.
- [ ] **AC11.** Coordination with #6766 (done at plan time; re-verify).
  - `gh issue view 9081 --json blockedBy,blocking`, read with standalone `jq`, lists #4326 and
    #6766.
  - `gh issue view 6766 --json blockedBy` lists #4326.
  - #6766 carries a comment stating the residual.
- [ ] **AC12.** The PR body uses `Closes #4326` and `Ref #6766, #9081, #9082`. It states DC1 via ship's
  decision-challenges rendering, and its infra-apply claim is consistent with AC6.

- [ ] **AC15.** Composite scope-down: the suite's composite case passes (empty inputs send no `-d`;
  set inputs send the exact JSON body). `git diff origin/main...HEAD --
  .github/actions/mint-soleur-ai-app-token/action.yml` shows no change to the default-path `curl`
  invocation line.

### Post-merge (automated verification, event-gated)

- [ ] **AC13.** The merge of this PR triggers one `mint-inngest-bootstrap-tag.yml` run, which
  concludes `success`, and its log contains `result=noop`. `soleur:ship` post-merge verifies this
  with
  `gh run list --workflow mint-inngest-bootstrap-tag.yml --commit <merge-sha> --event push --json conclusion,databaseId`
  and `gh run view <id> --log`.
- [ ] **AC14.** The first carrier-changing merge after this one produces, with no human step:
  - a `vinngest-v*` tag tagged by `github-actions[bot]`;
  - a successful `build-inngest-bootstrap-image.yml` run from the `workflow_dispatch` event
    carrying that `ref` input;
  - a merged `soleur/inngest-pin-v*` bump PR.

  This is the live proof of P1 and of R1. It is recorded in ADR-232 §Verification as pending until
  observed. The mint's own Slack step, or the `reason=workflows-permission` verdict, is the signal
  if it fails.
