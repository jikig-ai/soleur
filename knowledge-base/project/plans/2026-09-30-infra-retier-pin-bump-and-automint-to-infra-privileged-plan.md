---
title: "infra: re-tier the inngest-bootstrap pin-bump and auto-mint App-token consumers to infra-privileged (#8209 O10 prerequisite)"
date: 2026-09-30
slug: infra-retier-pin-bump-and-automint-to-infra-privileged
branch: feat-one-shot-9262-retier-infra-privileged
issue: 9262
closes: 9262
type: security
priority: p1-high
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# infra: re-tier the inngest-bootstrap pin-bump and auto-mint App-token consumers to infra-privileged

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-30
**Sections enhanced:** Overview (merge side effects), Proposed Solution §1/§2/§4, Implementation
Phases 0/6/8, Operator Sequence O4c, Observability, Guard Contract, User-Brand Impact, Deferrals,
Acceptance Criteria, Test Scenarios, Risks.
**Agents used:** security-sentinel, architecture-strategist, spec-flow-analyzer,
test-design-reviewer, observability-coverage-reviewer, a verify-the-negative sweep (all 8 negative
claims confirmed), plus the earlier plan-review panel (DHH, Kieran, code-simplicity), CTO, CLO and
the scoped advisor consult. All deepen-plan halt gates (4.6 user-brand, 4.7 observability, 4.8 PAT,
4.11 guard contract) pass; 4.5/4.55/4.9/4.10 do not trigger.

### Key Improvements

1. The composite reads Doppler with explicit `--project soleur-infra-privileged --config prd` in
   argv, so a Tier-A (config-bound) token is refused by Doppler itself, and the test stub can
   assert the project it was asked for (the env-var form was unobservable by the harness).
2. Merge-time preconditions: no queued/in-progress run of either workflow (in-flight runs would load
   the deleted composite path) and no open `soleur/inngest-pin-*` branch or PR (AC5 moved from
   "ready" time to merge time).
3. O4c probe made precise (preconditions, the writes it performs, read-only verification by API)
   and the O10 verify cell re-targeted at a post-eviction re-probe.
4. A `mirror_only` build never arms auto-merge on the pin PR (the build re-signs whatever the tag
   resolves to; security review P0), with the pre-existing build-job supply-chain issues filed as a
   tracked security deferral rather than widened into this PR.
5. Test rows made falsifiable: key-set check that tolerates `name`/`timeout-minutes`, a
   one-composite-step-per-job count row, a job-wide Tier-A token regex, a PR-author stub flag, and a
   bump-side mutation harness.

### New Considerations Discovered

- Sibling PR #9263 stores `GITHUB_APP_RUNTIME_DOPPLER_TOKEN` in `soleur-infra-privileged/prd`; once
  it merges, the whole-project token these two jobs hold can read the path to the soleur-ai runtime
  key. Stated in User-Brand Impact; the narrower-source deferral now triggers on #9263's merge.
- `web-platform-release` (fired by this merge) cuts a `web-v` release and swaps containers on web-1 —
  a routine deploy, but a host write, so the merge-side-effects line says so.
- The `gh pr list` author filter has never matched an App author (`app/<slug>`); fixed here.

## Overview

Two GitHub Actions jobs still mint a GitHub App installation token from the Tier-A Doppler config
`soleur/prd_terraform` (via the repo secret `DOPPLER_TOKEN`) and declare no `environment:`:

- `build-inngest-bootstrap-image.yml` job `bump-cloud-init-pin` (opens the cloud-init pin-bump PR);
- `mint-inngest-bootstrap-tag.yml` job `mint` (dispatches the image build after auto-minting a tag).

#8209 step O10 overwrites `GITHUB_APP_PRIVATE_KEY` in `prd_terraform` with the sentinel
`EVICTED_SEE_ADR_241`. The shared composite `.github/actions/mint-soleur-ai-app-token` refuses that
sentinel with `verdict=legacy_app_key_evicted`, so running O10 today would fail every inngest pin
bump and every auto-mint. The #8209 ledger records O10 as **held** on exactly this (issue comment
2026-09-30T07:44Z: "After it merges and one pin-bump dispatch goes green on Tier B, O10 runs").

This PR moves both jobs onto the main-only `infra-privileged` tier, following the direction already
recorded in the #8209 plan (Phase 4 item 4) and in the C4 model's pin-bump edge: *mint as the
dedicated `soleur-infra` App from the Tier-B Doppler project, and bind the consumer jobs to
`environment: infra-privileged`.* It also closes the three gaps that direction did not see
(measured below): the `soleur-infra` App lacks the two scopes these jobs need, the build workflow's
`push: tags` trigger would be refused by a main-only environment, and the census that is supposed
to catch an un-tiered App-key consumer never saw these two.

No production write happens in this PR's pipeline. The one step that lives outside the repo
(widening the `soleur-infra` App's permissions, which no API can do) is added to the canonical #8209
Operator Sequence as step **O4c**, ahead of O10.

**Does merging this PR alone mutate production? Yes, through four push-triggered workflows; none
writes a credential:** (1) `web-platform-release.yml` (path `apps/web-platform/**`, reached by the CLA
allowlist test and the App manifest) cuts a routine `web-v` release whose `workflow_run` deploy swaps
the containers on web-1, with no application-code change;
(2) `apply-web-platform-infra.yml` (path `apps/web-platform/infra/**`, reached by the App manifest)
runs its push apply — the manifest is read by no Terraform file (`git grep app-manifest -- '*.tf'`
finds only comments), so the plan is expected to be empty, exactly as PR #9202's manifest-only merge
applied green on 2026-09-29; (3) `mint-inngest-bootstrap-tag.yml` (its `paths:` list both edited
workflows) runs once, decides `noop` (no carrier, pin or Dockerfile-heredoc change), and so performs
no credential step — its only effect is the first live admission of the job to `infra-privileged`
from `main`; (4) `infra-validation.yml` push checks. Unfiltered workflows (`ci.yml`, secret scan)
also run and only read. This paragraph becomes the PR body's first line.

## Research Reconciliation — Spec vs. Codebase

| Claim (source) | Reality (measured) | Plan response |
|---|---|---|
| #9262 body describes the work | Body is only `Mandated-By: wg-when-an-audit-identifies-pre-existing` | Scope derived from the #8209 runbook consumer inventory (Group 4 rows), the O10-hold comment on #8209, ADR-232 §7/§8 and the C4 pin-bump edge |
| #8209 plan item 4 / C4 edge: "its mint composite gains name inputs so it can mint as the infra App from the Tier-B project" | Live `soleur-infra` installation 166065653 grants `actions:read, administration:write, contents:write, environments:write, metadata:read, secrets:write` — **no `pull_requests`, `actions` only read** (`gh api /orgs/jikig-ai/installations`, 2026-09-30). The bump opens/merges PRs (`gh pr create`, `gh pr merge --auto`); the mint dispatches a workflow (needs `actions:write`) | Add `pull_requests: write` and `actions: write` to `apps/web-platform/infra/github-infra-app-manifest.json` (codify, as PR #9202 did for `actions: read`) and add runbook step **O4c** to widen the live App before O10 |
| "Name inputs" on the composite (a parameterized reader serving both identities) | After this PR the composite has **no** `soleur-ai` consumer. Census row G4e counts steps with a **literal** `doppler secrets get GITHUB_APP_PRIVATE_KEY` and floors the live count at 4 (`app_key_sites`, `>= 4`); keeping a dead `soleur-ai` arm only to hold that floor is a distorted composite | The composite becomes Tier-B-only and is renamed to `.github/actions/mint-infra-app-token`; it reads `GITHUB_INFRA_APP_ID` / `GITHUB_INFRA_APP_PRIVATE_KEY` from `soleur-infra-privileged`/`prd`; G4e's floor moves 4 → 3 with a dated rationale (the population legitimately shrank) |
| Runbook: bump job "push, workflow_dispatch; an infra-privileged binding" is the plan | `build-inngest-bootstrap-image.yml` triggers on `push: tags: vinngest-v*.*.*` and `workflow_dispatch`. A tag-push run's ref is `refs/tags/…`; `infra-privileged`'s only deployment policy is `{name: main, type: branch}` (measured), so GitHub refuses the bump job on a tag push. ADR-232 §8 "After #8209": "Removing `push: tags` from the build (alternative A5) is a prerequisite of #8209" | Remove the `push: tags` trigger. Measured: the last four builds (v1.1.41–v1.1.44, 2026-09-29/30) were all `workflow_dispatch` from `main` (auto-mint); the last tag-push build was v1.1.40 on 2026-09-25 |
| Census header: "keyed on what a job REFERENCES … a new Tier-B job cannot escape the rule by omission" | Tier-B classification is `names_env_secret` (references to `DOPPLER_TOKEN_INFRA_PRIVILEGED` / `DOPPLER_TOKEN_WRITE` / `DOPPLER_TOKEN_GIT_DATA_ROOT`) or a state write. An App-key consumer holding only `secrets.DOPPLER_TOKEN` is classified Tier A — which is how both jobs escaped G1b while the runbook listed them as Tier-B-without-environment | No new census row (plan review): once both jobs pass `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED` they classify Tier B and the existing G1b/G1c require the main-only environment; and the renamed composite reads a fixed Tier-B project, so a consumer handing it the Tier-A `DOPPLER_TOKEN` (scoped to `soleur/prd_terraform`, per `.github/actions/infra-credentials/action.yml` input docs) fails closed at the Doppler read |
| Identity is load-bearing only in the token | `bump-inngest-bootstrap-pin.sh` hardcodes `BOT_NAME='soleur-ai[bot]'` / `BOT_EMAIL='273333864+soleur-ai[bot]@…'` for the commit identity, the bot-tip force-push check, the PR-author filter and the supersede sweep. `cla.yml` allowlists `soleur-ai[bot]` and `apps/web-platform/test/cla-evidence/allowlist.test.ts` pins the exact set | Switch `BOT_NAME`/`BOT_EMAIL` in place to `soleur-infra[bot]` (bot user id **335404629**, measured `gh api /users/soleur-infra%5Bbot%5D`). No legacy read-side set: measured 0 open `soleur/inngest-pin-*` PRs and 0 such remote branches (2026-09-30), and pin PRs auto-merge; a pre-merge AC re-checks it. Add `soleur-infra[bot]` to the CLA allowlist and its pin test |
| Repo research: "infra-privileged likely carries required reviewers" | `gh api repos/jikig-ai/soleur/environments/infra-privileged` → `protection_rules: [branch_policy]`, no reviewers; secrets `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN_WRITE` | Unattended auto-mint and pin bump do not wait on an approval |

## Research Insights

**Premise Validation.** #9262 is OPEN (labels p1-high, domain/engineering, type/security). PR #9301
is an OPEN draft with no files. #8209 is OPEN; its ledger shows O0, O1, O1b, O2, O3, O4, O4b, O5,
O5b, O6, O7, O8 done and O10 held on these two consumers (comment 2026-09-30T07:44Z). Every cited
path exists on this branch (`git ls-files`). The mechanism "bind to `infra-privileged` + mint as
`soleur-infra`" is the *recorded* direction (#8209 plan item 4; C4 `github -> soleurMarketplace`
edge), not a rejected alternative; ADR-232's alternatives table records the one relevant rejection
(`GITHUB_TOKEN` for the dispatch — DC1, "not adopted because the operator's direction names the App
token"). ADR-232 §7 forbids a `vinngest-v*` tag deployment policy. Stale premise found: the recorded
direction assumed the infra App could open PRs and dispatch workflows; it cannot (measured).

**Property List** (Phase 0.6b).

- P1. After O10, both jobs still obtain a working GitHub App installation token.
- P2. That token's key is reachable only from `main` (a GitHub environment secret on a main-only
  environment), never from a branch.
- P3. A run on a non-`main` ref (branch dispatch, hand-pushed tag) reaches no Tier-B credential.
- P4. The pin-bump PR still fires `pull_request` (required checks run) and can auto-merge; the build
  dispatch still starts exactly one build.
- P5. A future App-token consumer cannot silently mint from a Tier-A credential (census catches it).
- P6. Merging in either order relative to the App-permission step never publishes a partial state
  (no tag without a build, no PR without checks).
- P7. Recorded architecture (ADR-232, ADR-241, C4, runbooks) matches the shipped behaviour.

**Cut List.**

- A closed `app: soleur-ai|soleur-infra` enum on the composite → cut (advisor consult). Its
  `soleur-ai` arm would have zero consumers and exist only to keep census G4e's literal-read floor
  at 4; the rollback lever it offered is `git revert` of this PR (P1 needs one identity).
- Use `.github/actions/infra-credentials` in these jobs → cut. It is Terraform-shaped (state-key
  pair checks, TF_VAR export, anti-vacuity floor over the whole project) and would export every
  Tier-B key into a job that needs one App key. The composite already takes a Doppler token (P1/P2).
- A new dedicated least-privilege App for the pin bump → cut. A Tier-B compromise already yields
  the `soleur-infra` key, whose `administration:write` dominates the two scopes added here; a
  separate App buys no reduction in the Tier-B threat model and adds an App creation step.
- A `dry_run` input on the build workflow for a post-merge probe → cut. A `mirror_only` dispatch of
  the current max tag already runs the bump job end-to-end on `main` (mint + exact-scope check +
  resolve) and ends `result=noop` without a push or PR (P4 probe covered; O4c uses it).
- A repo-variable selector for "which identity" → cut. P6 already holds without it (Proposed
  Solution §3: credentials are minted before any write, so a missing scope fails before anything is
  published).
- A new census row G1j over composite consumers → cut (plan review, DHH + simplicity). P5 holds by
  construction: the composite reads a fixed Tier-B project (a Tier-A token fails closed at the
  Doppler read), refuses empty scope inputs, and any consumer passing the Tier-B token is classified
  Tier B, so G1b/G1c already demand the main-only environment. Inline JWT recipes stay G4e's.
- A legacy `soleur-ai[bot]` read-side recognition set → cut (plan review). Its population is empty
  (0 open pin PRs, 0 remote pin branches, measured); a pre-merge AC re-checks it.
- Step-scoping guard rows for `DOPPLER_TOKEN_INFRA_PRIVILEGED` (CTO concern 1) → cut as guards,
  kept as a written rule (plan review, simplicity: every other Tier-B job's loader writes all Tier-B
  keys to `$GITHUB_ENV`; the exact-dict rows already pin where the token appears in the verify and
  mint steps). Recorded as DC-5.

**Measured facts** (all read-only, 2026-09-30):

- `soleur-infra` App id 5118911, installation 166065653 (`repository_selection: selected`),
  permissions as in the reconciliation table. `soleur-ai` installation 122213433 on jikig-ai has
  `repository_selection: all` and `pull_requests:write`, `actions:write`.
- `soleur-infra[bot]` user id 335404629; `soleur-ai[bot]` 273333864.
- `infra-privileged` environment: custom branch policies, one policy `main` (type `branch`), no
  reviewers; environment secrets `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN_WRITE`.
- Rulesets on the default branch: `CI Required`, `CLA Required` (required status checks; bypass
  OrganizationAdmin / repo-admin role in `pull_request` mode, one Integration id 1236702 `always` on
  CLA), `Force Push Prevention`. No rule keys on the pin-bump author.
- Last six pin-bump PRs (#8745…#9288) authored by `app/soleur-ai`, all auto-merged.
- Only two consumers of the composite exist (`git grep "uses: ./.github/actions/mint-soleur-ai-app-token"`).
- Push path filters: `web-platform-release.yml` `apps/web-platform/**`; `apply-web-platform-infra.yml`
  `apps/web-platform/infra/**`; `infra-validation.yml` `apps/*/infra/**`; the mint workflow lists
  both edited workflow files. PR #9202 (manifest-only) push apply: 2026-09-29T12:36Z `success`.
- Workflow sizes: build 78,869 B, mint 10,058 B — far under the 490,000 B gate
  (`plugins/soleur/test/workflow-file-size.test.ts`).
- GitHub docs (fetched 2026-09-30): the REST Apps API has no endpoint that edits an App
  registration's permissions (docs.github.com/en/rest/apps/apps lists 14 endpoints, none a PATCH of
  permissions); `GITHUB_TOKEN`-triggered events create no workflow run except `workflow_dispatch` /
  `repository_dispatch`, and a `GITHUB_TOKEN`-opened PR's runs start in an approval-required state
  (docs.github.com/en/actions/…/triggering-a-workflow) — so the bump still needs an App token;
  environment secrets are available to a job only after the environment's rules pass.

**Relevant files.**

- `.github/workflows/build-inngest-bootstrap-image.yml` — `on:` block (the `push: tags` trigger),
  job `bump-cloud-init-pin` (steps `Install Doppler CLI`, `Verify DOPPLER_TOKEN present`,
  `Mint soleur-ai App token`, `Bump the cloud-init pin`).
- `.github/workflows/mint-inngest-bootstrap-tag.yml` — job `mint` (steps `Verify DOPPLER_TOKEN
  present`, `Mint soleur-ai App token (actions:write on soleur)`, `Dispatch build`); header comment
  "#8209 must bind this job to its main-only environment".
- `.github/actions/mint-soleur-ai-app-token/action.yml` — step `Mint installation token` (the
  literal `doppler secrets get GITHUB_APP_PRIVATE_KEY`, the sentinel refusal, the scope check).
- `.github/scripts/bump-inngest-bootstrap-pin.sh` — `BOT_NAME` / `BOT_EMAIL` and their read-side
  uses (tip-author `case`, `gh pr list` author filter, supersede sweep); header comment naming the
  composite.
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — Guard 2 `check_block 'g2.bump:*'` rows
  (`g2.bump:doppler-token-verify`, `g2.bump:mint-action`, `g2.bump:installation-id` `122213433`), the
  identity fixtures, `MIN_ASSERTIONS=487`.
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` — `COMPOSITE=` path constant, Guard 3
  `exact("doppler-check", …)` and `exact("app", …)` rows, the `comp:*` behavioural rows that execute
  the composite's run block, `MIN_ASSERTIONS=545`.
- `tests/scripts/test-infra-privileged-tier-census.sh` — G1b/G1c (Tier-B jobs need a Tier-B
  environment), G4e (App-key readers refuse the sentinel; floor 4), `CENSUS_ROWS=23`, mutation floor
  (95 ran at #6604 step 7).
- `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` — asserts jobs are exactly
  `build` + `bump-cloud-init-pin` and the bump job carries no job-level `if:` / `continue-on-error:`
  (both still hold; `environment:` is neither).
- `apps/web-platform/infra/github-infra-app-manifest.json`, `.github/workflows/cla.yml`
  (`allowlist:`), `apps/web-platform/test/cla-evidence/allowlist.test.ts`
  (`SAMPLE_CLA_YML_ALLOWLIST`, exact-set pin).
- Docs: ADR-232 (§1 title, §3, §4, §8, "After #8209", Alternatives), ADR-241 (D5), C4
  `knowledge-base/engineering/architecture/diagrams/model.c4` edge `github -> soleurMarketplace`,
  runbooks `infra-credential-tiers-8209.md` (Group 4 rows, `environment:` coverage list, Operator
  Sequence, order constraints), `inngest-server.md` (§Bootstrap-image release hand-tag block) and
  `apply-web-platform-infra-job-rationale.md` ("Four consumers read this name" → three).

**Institutional learnings applied.**

- `knowledge-base/project/learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`
  — the Tier-B source is the separate *project* `soleur-infra-privileged`, never a `prd_*` branch
  config.
- `knowledge-base/project/learnings/2026-05-25-app-jwt-inline-mint-for-workflow-gh-api-administration-read.md`
  — keep the one composite recipe; do not add another inline copy.
- `knowledge-base/project/learnings/2026-05-31-tag-driven-dispatch-invariant-and-checkout-refspec-tag-locality.md`
  — the build's tag validation/resolution stays inline; unchanged here.
- `knowledge-base/project/learnings/2026-03-16-github-actions-workflow-dispatch-permissions.md` —
  dispatch needs `actions:write` on whatever token sends it (here: the infra App token).
- `knowledge-base/project/learnings/2026-02-26-cla-system-implementation-and-gdpr-compliance.md` — a
  new bot identity must be on the CLA allowlist or its PRs never pass `CLA Required`.
- Guard-writing learnings cited by plan Phase 2.12 (vacuous-guard class, harness rows, dispatch
  floor) shape the Guard Contract below.

**CLAUDE.md / AGENTS.md conventions.** `hr-github-app-auth-not-pat` (App tokens only);
`cq-write-failing-tests-before` (RED rows first); `hr-type-widening-cross-consumer-grep` (the
composite is consumed by exactly two callers — both edited); UNTRUSTED-CI for workflow edits (no
admin-merge, no auto-merge); the local test battery is skipped in favour of targeted ratchets, CI is
the gate. The diff adds no systemd start/restart line under `apps/web-platform/infra/`, so
`ci-deploy.test.sh` is not required.

**Functional overlap.** Community registries: no skill/agent covers this (functional-discovery,
2026-09-30).

## Proposed Solution

### 1. Composite: Tier-B-only, renamed (`.github/actions/mint-infra-app-token/action.yml`)

`git mv .github/actions/mint-soleur-ai-app-token .github/actions/mint-infra-app-token`, then:

- Reads **literal** `GITHUB_INFRA_APP_ID` and `GITHUB_INFRA_APP_PRIVATE_KEY` with the project and
  config in **argv** — `doppler secrets get GITHUB_INFRA_APP_PRIVATE_KEY --plain --project
  soleur-infra-privileged --config prd` — never through `DOPPLER_PROJECT`/`DOPPLER_CONFIG` env
  (deepen: a Doppler service token is bound to one config, so a Tier-A `prd_terraform` token asked
  for this project is refused by Doppler itself, even if someone later copied the names into a
  Tier-A config; and argv is what the test stub can observe — the harness sets those env vars
  itself, so an env-var form would let a composite reverted to `soleur` pass). The composite has one
  identity and one source; neither is an input.
- Inputs: `doppler-token` (required), `installation-id` (required), `permissions` (required,
  non-empty JSON object), `repositories` (required, non-empty). Composite `required: true` is not
  enforced by the runner, so each is checked in shell before any Doppler read; an empty
  `permissions` is refused because an unscoped token of this App carries `administration:write`
  and `secrets:write`.
- Keeps: per-line PEM masking, `openssl rsa -check`, the JWT recipe, the **exact-grant check**
  (granted permissions must equal the request plus `metadata:read`; repository selection must equal
  the request).
- Drops: the `EVICTED_SEE_ADR_241` refusal (the composite never reads `prd_terraform`); census G4e's
  population loses this site.
- New: on a failed exchange, print GitHub's `.message` (never the token or JWT), first stripping CR,
  LF, U+2028/U+2029, DEL and `::` so vendor text cannot forge a second workflow command (security
  review); no runbook pointer (it would go stale once O4c is done — plan review). On success, emit
  `::notice title=app-token::app=soleur-infra installation=<id> permissions=<granted>` — the per-run
  evidence O4c verifies.

### 2. `build-inngest-bootstrap-image.yml`

- Remove `push: tags: ['vinngest-v*.*.*']` (ADR-232 A5). `workflow_dispatch` stays as the only
  trigger; header comment rewritten: every build is dispatched from `main` (auto-mint or the
  runbook's one-line dispatch). The build job's inline resolver keeps its `push` arm (dead but
  harmless and covered by `test-inngest-bootstrap-tag-guard.sh` `resolve:push-*`); its comment notes
  the trigger is gone. No carrier `cp` line, pin read or Dockerfile heredoc is touched (that is what
  keeps the merge-triggered mint run at `noop`).
- Job `bump-cloud-init-pin`: add `environment: infra-privileged` (no job-level `if:`; the
  environment's branch policy is the refusal for non-`main` dispatches, and the mirror-only suite
  forbids a job-level `if:`). Replace `Verify DOPPLER_TOKEN present` with a check of
  `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED`. The mint step becomes:

  ```yaml
  - name: Mint soleur-infra App token (contents+pull_requests write on soleur)
    id: mint
    uses: ./.github/actions/mint-infra-app-token
    with:
      doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
      installation-id: "166065653"
      permissions: '{"contents":"write","pull_requests":"write"}'
      repositories: soleur
  ```

  Today's mint is **unscoped** (full soleur-ai grant); scoping is mandatory on the infra App.
- The bump step gains `--mirror-only "${{ inputs.mirror_only }}"` (normalized to `true`/`false` in the
  script) and the script **never arms auto-merge** when it is `true`: it opens or updates the PR held,
  with a body line saying a `mirror_only` backfill cannot attest provenance (deepen, security P0: the
  build's cosign step re-resolves `crane digest $IMAGE:$TAG` and signs whatever the tag points at, and
  `mirror_only` skips the ancestry refusal, so a digest pushed to the tag by branch-run YAML could
  otherwise be signed and auto-merged under `main`'s identity). The remaining build-job supply-chain
  gaps are pre-existing and filed as a security deferral (Deferrals).
- Comments that become false are edited (the header's "Triggered on `vinngest-vX.Y.Z` tag pushes",
  the resolver comment "a tag push runs the copy in the TAGGED commit"); code outside the `on:` block
  and the bump job is not touched.

### 3. `mint-inngest-bootstrap-tag.yml`

- Job `mint`: add `environment: infra-privileged`; keep `if: github.ref == 'refs/heads/main'` as the
  accident gate (the header comment's "NO `environment:` … #8209 must bind this job" is rewritten to
  describe the binding). Replace the `DOPPLER_TOKEN` check with `DOPPLER_TOKEN_INFRA_PRIVILEGED`. The
  App step becomes `uses: ./.github/actions/mint-infra-app-token` with
  `doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}`, `installation-id: "166065653"`,
  `permissions: '{"actions":"write"}'`, `repositories: soleur`.
- Unchanged, and load-bearing for P6: every credential step runs after `Decide` and **before**
  `Create tag`. A missing `actions:write` on the infra App fails at the App step, so nothing is
  tagged and the next push or `gh workflow run mint-inngest-bootstrap-tag.yml --ref main` re-decides.

### 4. `bump-inngest-bootstrap-pin.sh` identity

- `BOT_NAME='soleur-infra[bot]'`, `BOT_EMAIL='335404629+soleur-infra[bot]@users.noreply.github.com'`,
  switched in place for the commit identity and the two **commits-API** checks (bot-tip `case`,
  supersede sweep), which read `.author.login` / `.commit.author.email` from
  `gh api repos/…/commits/<sha>` and see the `<slug>[bot]` form. No legacy set (Cut List).
- **Pre-existing bug fixed in passing (plan review, Kieran P1):** the two `gh pr list` author filters
  (`PR_URL=` / `PR_NUM=` and their re-list twins, `jq … .author.login == $bot`) compare against
  `BOT_NAME`, but `gh pr list --json author` reports an App author as `app/<slug>` (measured above:
  every pin PR lists as `app/soleur-ai`). So the "reuse the open PR" path has never matched in
  production — a re-run for the same target falls to `gh pr create`, which fails on the existing
  branch PR, and the filtered re-list finds nothing, ending `die pr`. The test stub's `pr_json` emits
  `soleur-ai[bot]`, which hid it. Add `BOT_PR_LOGIN='app/soleur-infra'` for those filters (only that
  form — `gh` never reports `<slug>[bot]` there; measured live: `{"is_bot":true,"login":"app/soleur-ai"}`),
  and make the stub emit the `app/…` form.
- If a `soleur-ai[bot]` pin branch exists at switch time (AC5 says it will not), the script's
  `branch-has-manual-commits` path prints a `::warning::` and exits 0: the job is green and nothing
  posts to Slack. What surfaces it is the pin drift guard staying red on `main`, which the
  main-health monitor escalates to a `ci/main-broken` issue (the warning text says so).
- User-facing strings that say "reset the tip to a soleur-ai[bot] commit" become an action a human
  can take: "close the PR and delete the branch, then dispatch the build once from `main` with
  `mirror_only=true`" (spec-flow); the header comment names the renamed composite.
- The two `die` messages that still promise "that tag push runs its own publish and bump" (the
  `--signed-commit` argument check and the "pin above every merged tag" refusal) become "then
  dispatch the build once from `main`" — true after `push: tags` is removed (spec-flow).
- New `--mirror-only <true|false|''>` argument (see §2): when `true`, auto-merge is never armed.

### 5. Identity plumbing

- `apps/web-platform/infra/github-infra-app-manifest.json`: `"actions": "write"`,
  `"pull_requests": "write"`; description names the two non-Terraform consumers. (No Terraform
  resource or REST endpoint manages an App registration's permissions; the manifest is the committed
  source of truth, exactly as PR #9202 codified `actions: read`.)
- `.github/workflows/cla.yml` allowlist += `soleur-infra[bot]` (login-based; a comment names the bot
  id 335404629 and the required noreply author email, mirroring the #5520 note for `soleur-ai[bot]`).
  `allowlist.test.ts` `SAMPLE_CLA_YML_ALLOWLIST` and its expected array updated in the same edit (the
  test pins the exact set by design: "adding or removing a bypass must be a deliberate two-file
  edit"). `build-bypass.ts` reads `cla.yml` at run time, so bypass evidence for the new login is
  recorded automatically (CLO).

### 6. Census (`tests/scripts/test-infra-privileged-tier-census.sh`)

- G4e floor `4 → 3` with the census's dated-rationale comment style (`# 4 -> 3 (#9262): the mint
  composite no longer reads GITHUB_APP_PRIVATE_KEY; it mints the Tier-B soleur-infra identity from a
  fixed Tier-B project`). G4e's property ("every reader refuses the sentinel") is unchanged over the
  three remaining inline readers.
- No new row. G1b/G1c pick up both jobs automatically once they reference
  `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED` (their `IPT_TIERB=` list grows by two); `CENSUS_ROWS`
  stays 23.

## Implementation Phases

**Phase 0 — RED first (tests before code).**

Shared helpers (deepen, test-design review), used by both suites: `norm_env(job)` returns the
environment name for either the scalar or the `{name: …}` mapping form (as the census's `env_arms`
does); `keyset_ok(step, want)` is `set(step) - {"name", "timeout-minutes"} == {k for k, v in want.items() if v is not None}`
(the live steps carry `name` and `timeout-minutes`, and `exact()`'s `want` uses `None` for "absent",
so a naive `set(step) == set(want)` is RED on the correct tree); `one_minter(job)` asserts exactly one
step whose `uses` ends in `mint-infra-app-token` (`find()` returns the first match, so an exact row
alone cannot see a second minter); `no_tier_a(job)` asserts `not re.search(r"secrets\.DOPPLER_TOKEN(?![A-Za-z0-9_])", yaml.safe_dump(job))`.

1. `test-bump-inngest-bootstrap-pin.sh` Guard 2, in the parsed jobs-dict block
   (`bump = jobs.get("bump-cloud-init-pin")`), using the mint suite's exact-dict pattern (plan review:
   one structural row per step instead of several text greps): `norm_env(bump) == "infra-privileged"`;
   the verify step is exactly `{env: {DOPPLER_TOKEN_CHECK: "${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}"}}`
   plus its unchanged `run`; the mint step is exactly `{id: mint, uses: ./.github/actions/mint-infra-app-token,
   with: {doppler-token: "${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}", installation-id: "166065653",
   permissions: '{"contents":"write","pull_requests":"write"}', repositories: soleur}}`; both also pass
   `keyset_ok`; plus `one_minter(bump)` and `no_tier_a(bump)`. The bump step's `run` passes
   `--mirror-only`. Retire the text rows these replace (`g2.bump:doppler-token-verify`,
   `g2.bump:mint-action`, `g2.bump:installation-id`). Add `g2.bump-job:parsed` (the jobs-dict lookup
   found the job), since `g2.bump-job:exists` guards only the text slice. Add an `S`-prefixed trigger
   row (the g2b loop drops other key shapes) asserting `set(norm(on)) == {"workflow_dispatch"}` where
   `on = doc.get("on", doc.get(True))` and `norm` handles the string, list and mapping forms (copy the
   mint suite's handling); never `"push" not in on`, which passes when the lookup misses. Update the
   composite rows: `ACTION=` → the renamed path; `g2.action:doppler-config` `prd_terraform` →
   `--project soleur-infra-privileged`; `g2.action:app-id` → `GITHUB_INFRA_APP_ID`;
   `g2.action:app-key` → `GITHUB_INFRA_APP_PRIVATE_KEY`.
   **Bump-side mutation harness** (none exists today): copy the workflow to a temp file, apply each
   Guard 1 mutation scoped to the `bump-cloud-init-pin` block, require a clean run on the unmodified
   copy first, then require the named row RED — the same shape as the mint suite's `g3_mut`.
2. Same suite, identity: the commit-identity rows and the `BOT_EMAIL` fixture constants expect
   `soleur-infra[bot]` / `335404629+soleur-infra[bot]@users.noreply.github.com`; the bot-tip and
   supersede fixtures push/author as the new bot; the human-tip rows stay RED-on-human; update the
   literal sweep at the `for lit in 'soleur-ai[bot]' …` row to the new constants. The `pr_json` stub
   emits the `app/<slug>` author form (switching it alone turns `g1.existing` and `g1.collide` RED on
   the unfixed script — that is the regression proof) and gains an `|author=<login>` flag, so the
   author check is tested separately from `isCrossRepository`: new rows assert a same-repo PR authored
   by `app/soleur-ai` and one by a human are **not** reused. New row `g1.mirror-only-held`: with
   `--mirror-only true`, a would-arm run leaves auto-merge unarmed and says why in the PR body. The
   reworded recovery messages are asserted by their new text. Raise `MIN_ASSERTIONS` to the new green
   count.
3. `test-mint-inngest-bootstrap-tag.sh`: `COMPOSITE=` → the renamed path; the verify-step finder
   (matched by step name) follows the renamed step `Verify DOPPLER_TOKEN_INFRA_PRIVILEGED present`;
   `exact()` gains the `keyset_ok` half; `one_minter(mint)` and `no_tier_a(mint)` rows; any row pinning
   the script's "soleur-ai App token" wording follows the script edit; Guard 3
   `exact("doppler-check", …)` expects `DOPPLER_TOKEN_INFRA_PRIVILEGED`; the App-step finder keys on
   `endswith("mint-infra-app-token")` and `exact("app", …)` expects the new `with:` mapping; new job
   row `norm_env(mint) == "infra-privileged"` and `if` unchanged. `comp:*` harness changes first:
   `run_comp` takes the token, installation id, permissions and repositories as parameters (they are
   hardcoded today, so the empty-input rows cannot be written without this), runs the block under
   `env -u DOPPLER_PROJECT -u DOPPLER_CONFIG`, and the `doppler` stub appends its argv to a
   `DOPPLER_LOG` and exits 1 unless the argv carries exactly `--project soleur-infra-privileged
   --config prd`. Then the rows: each empty required input is fatal with zero `DOPPLER_LOG` lines and
   zero curl calls; Doppler is asked for exactly `GITHUB_INFRA_APP_ID` and
   `GITHUB_INFRA_APP_PRIVATE_KEY` with that project/config; a grant wider or narrower than the request
   is refused; a failed exchange prints GitHub's `.message` with CR/LF and `::` stripped (fixture
   message containing `\n::notice::`); a success prints the `app-token` notice. Existing rows that
   encode the old optional-scope contract flip deliberately: `comp.default:*` (empty permissions and
   repositories → unscoped mint, rc 0) and `comp.repos-only:*` (empty permissions) now assert refusal
   with no curl call; `comp.default:unchecked` is retired with them. Remove any row that asserted the
   sentinel refusal inside the composite. Add a `g3_mut` row that changes the composite's project to
   `soleur` and requires the argv row RED. Raise `MIN_ASSERTIONS`.
4. Census: G4e floor 4 → 3 with its dated rationale; confirm the live `IPT_TIERB=` list now names
   both jobs and G1b/G1c stay green. `CENSUS_ROWS` unchanged by this PR.
5. `allowlist.test.ts`: expected set includes `soleur-infra[bot]`.

Run each suite and confirm the new rows are RED for the right reason before Phase 1.

**Phase 1 — composite** (Proposed Solution §1).

**Phase 2 — workflows** (§2, §3). Byte check: `wc -c` both files and
`bun test plugins/soleur/test/workflow-file-size.test.ts`; `actionlint` on the two edited workflow
files (not on the composite — actionlint validates workflows only).

**Phase 3 — bump script identity** (§4).

**Phase 4 — manifest + CLA allowlist** (§5).

**Phase 5 — census** (§6: G4e floor only).

**Phase 6 — recorded architecture and runbooks.**

1. ADR-232 amendment (dated 2026-09-30, #9262). Sections, each enumerated by the architecture
   review against the ADR text: the **H1 title** ("authenticated as the `soleur-ai` App" → the
   `soleur-infra` App); §3 heading and body, including its scope parenthetical ("the publish path of a
   hand-pushed tag", "keeps the tag's `push: tags` run silent"); §4 commit identity (`soleur-infra[bot]
   <335404629+…>`; PR-author filters match `app/soleur-infra`); §7's hand-pushed tag-ref caveat and
   the build-refusal line "A tag push runs the tagged commit's YAML"; §8's Tag bullet rationale
   ("`push: tags` trigger stays silent" → there is no tag trigger) and Dispatch bullet (the
   `soleur-infra` App token scoped to `actions:write`); Residual R1's "Before/After #8209" text;
   "After #8209" (`push: tags` removed — A5 adopted in #9262; a hand-pushed tag starts nothing; the
   manual fallback is `gh workflow run mint-inngest-bootstrap-tag.yml --ref main`, or hand-tag then
   `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<tag>` once); the Alternatives
   rows "`GITHUB_TOKEN` writes", "create the tag with the App token and let `push: tags` build it",
   "App-token tag AND a dispatch" and A5 (adopted); the Consequences bullet on the `soleur-ai` write
   surface (installation 122213433, "dispatch by the App"); the Verification section's composite path;
   and a note that a `mirror_only` build never arms auto-merge.
2. ADR-241 amendment: D2 — the list of what `infra-privileged` serves gains the auto-mint and the pin
   bump. D5 — `soleur-infra` also carries `pull_requests:write` and `actions:write` for those two
   consumers; its permissions are no longer purely "derived from the resource types Terraform
   manages", and the sentence says so. Statuses table: D5's flip condition gains "and O4c's evidence
   (AC15)", so D5 cannot reach `accepted` without the new scopes ever being exercised.
3. C4 `model.c4`: edge `github -> soleurMarketplace` — replace the pin-bump/dispatch identity prose
   (soleur-ai, `prd_terraform`, installation 122213433, `soleur-ai[bot]`, the composite's old path,
   "gains name inputs", "dispatches the build from main as the soleur-ai App", and "both App-token
   fallbacks refuse … `legacy_app_key_evicted`", which the composite no longer does) with the shipped
   shape, and edit its `technology` string ("not the soleur-ai App token"). Edge `github -> doppler` —
   it says Tier-B values load only through `infra-credentials` and that `infra-privileged` serves
   apply and drift; add the composite's single-key read and the two new consumers. Regenerate
   `model.likec4.json` with `bash plugins/soleur/scripts/render-c4-model.sh` (likec4@1.50.0, the
   CI-pinned version) and run `plugins/soleur/test/c4-model-freshness.test.sh`,
   `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`,
   `apps/web-platform/test/c4-render.test.ts`.
4. `infra-credential-tiers-8209.md`: Group 4 rows for both jobs (environment `infra-privileged`,
   credential `DOPPLER_TOKEN_INFRA_PRIVILEGED` → `mint-infra-app-token`, scoped tokens, triggers:
   build now `workflow_dispatch` only); remove both from the "declare no `environment:`" list; add
   both workflows to the "`infra-privileged` … referenced by" list; add Operator Sequence row **O4c**
   (below), annotated "added by #9262" because the section header says it is verbatim from the
   2026-09-22 plan; add "O4c precedes O10" to Order constraints and "#9262 merged, O4c" to O10's
   precondition list; replace O10's verify limb "the pin bump [is] green" (it tests nothing unless a
   build happens to run) with "re-run O4c's `mirror_only` probe after the sentinel is set; its bump
   job is green with the `app-token` notice"; add the chain "#9262 merge → O4c → O10 → #8609 R-step 1"
   (#9263 gates R-step 1 on O10); note that O13's App-key delete concerns only the `soleur-ai` key
   `prd_terraform` held and is unaffected by this PR, and that a new token in
   `soleur-infra-privileged` (#9263's) must be reconciled with O13(c)'s exactly-`gha-infra-privileged`
   check.
5. `inngest-server.md` §Bootstrap-image release: the hand-tag block's "Today this fires … through
   `push: tags` … Once #8209 removes `push: tags`" becomes present tense: a hand-pushed tag starts
   nothing; confirm no build run exists, then dispatch once. The #8747 recovery block ("That push
   runs its own publish and bump") gets the same correction: after re-tagging, dispatch the build
   once from `main`.
6. `apply-web-platform-infra-job-rationale.md`: "Four consumers read this name" → three (the
   composite left the population in #9262; G4e floor 3).
7. `.github/scripts/mint-inngest-bootstrap-tag.sh`: the credential-contract comment and the
   `missing-credential` message say "soleur-ai App token" → "soleur-infra App token" (wording only).
   The two workflow step names that say "Mint soleur-ai App token" are renamed with them.

**Phase 7 — targeted verification** (CI is the gate; run only the suites this diff touches):
`bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh`,
`bash .github/scripts/test/test-mint-inngest-bootstrap-tag.sh`,
`bash tests/scripts/test-infra-privileged-tier-census.sh`,
`bash apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`,
`bash .github/scripts/test/test-inngest-bootstrap-tag-guard.sh`,
`bash .github/actions/infra-credentials/infra-credentials.test.sh` (unchanged file; regression only),
`cd apps/web-platform && ./node_modules/.bin/vitest run test/cla-evidence/allowlist.test.ts`, the four
C4 checks above, `bun test plugins/soleur/test/workflow-file-size.test.ts`,
`actionlint .github/workflows/build-inngest-bootstrap-image.yml .github/workflows/mint-inngest-bootstrap-tag.yml`,
`python3 scripts/lint-guard-contract.py` on this plan,
`python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own form), and
the AC11 residual sweeps.

**Phase 8 — ship.** Mark PR #9301 ready with `Closes #9262` and `Refs #8209` in the body; the body's
first line is the merge-side-effects answer from the Overview; UNTRUSTED-CI (workflow edits): no
admin-merge, no auto-merge queued; leave for operator review and stop. The PR body carries a
**merge-time checklist as commands** (the PR may wait days for review, so a ready-time check goes
stale — spec-flow): `gh run list -R jikig-ai/soleur --workflow build-inngest-bootstrap-image.yml
--status in_progress` and `--status queued` (and the same for `mint-inngest-bootstrap-tag.yml`) print
nothing, because an in-flight run's bump or mint job checks out `main` after the merge and would load
the deleted composite path ("action not found"; "re-run failed jobs" replays the old YAML and fails
again — recovery is a `mirror_only=true` dispatch from `main`, never a rebuild, which would move the
digest); and the AC5 commands print nothing / `0`.

## Files to Edit

- `.github/actions/mint-soleur-ai-app-token/action.yml` → moved to `.github/actions/mint-infra-app-token/action.yml` (`git mv`, then edited)
- `.github/workflows/build-inngest-bootstrap-image.yml`
- `.github/workflows/mint-inngest-bootstrap-tag.yml`
- `.github/scripts/bump-inngest-bootstrap-pin.sh`
- `.github/scripts/mint-inngest-bootstrap-tag.sh` (comment + one message string)
- `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`
- `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`
- `tests/scripts/test-infra-privileged-tier-census.sh`
- `apps/web-platform/infra/github-infra-app-manifest.json`
- `.github/workflows/cla.yml`
- `apps/web-platform/test/cla-evidence/allowlist.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-232-inngest-bootstrap-pin-bumps-are-authored-by-the-publish-workflow.md`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated, never hand-edited)
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`

## Files to Create

- None beyond the `git mv` above (census fixtures are generated inside the suite's temp tree, as the
  existing ones are). The pipeline also writes `knowledge-base/project/specs/feat-one-shot-9262-retier-infra-privileged/`
  artifacts (tasks, session state, decision-challenges).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| β — keep the `soleur-ai[bot]` identity: mint a fresh `soleur-ai` private key (App settings, no API) into `soleur-infra-privileged/prd` under new names | Smallest code diff (no bot-identity, CLA or script change, no `web-platform-release` side effect) but keeps a key of an App installed org-wide on jikig-ai **and** on two outside installations (ADR-241 Context item 4) in CI — the shape #8209 DC-4 marked non-recommended. Also turns O13's two-key fingerprint comparison (U2) into a three-key one. Recorded in decision-challenges.md as the fallback if the CLA allowlist edit is judged out of scope |
| Copy the `prd_terraform` soleur-ai key into Tier B | That key was branch-reachable from O0 to O10 and O13 deletes it (R5); a Tier-B copy would break at O13 |
| Copy the `prd` runtime soleur-ai key into Tier B | Already branch-reachable (R1); a copy adds no protection and silently breaks the pin bump when R1 rotates the runtime key |
| Dispatch the build with the mint job's `GITHUB_TOKEN` (`actions: write`), no App at all | Mechanically sufficient (ADR-232 DC1) and would avoid granting the infra App `actions:write`, but the recorded direction names the App token; kept as a taste item in decision-challenges.md |
| Admit tag-ref runs to `infra-privileged` via a `vinngest-v*` tag policy | Forbidden by ADR-232 §7: runs branch-written YAML with Tier-B secrets before any ancestry check |
| Keep `push: tags` and let the bump job be refused on tag pushes | A hand-pushed tag would publish an image, then the run goes red at the environment gate with no Slack (the failure step is inside the refused job), leaving `main`'s pin drift guard red |
| Keep the composite name and add a closed `app:` enum with a legacy `soleur-ai` arm | The legacy arm has no consumer and would exist only to hold census G4e's literal floor at 4 (advisor consult) |
| Free-form `app-id-name` / `private-key-name` inputs (the literal #8209 wording) | Admits any name and still drops the composite out of G4e's literal population; a single fixed identity is simpler and fails closed |
| A `dry_run` input on the build workflow | A `mirror_only` dispatch already exercises the bump job on `main` with no push/PR |

## Infrastructure (IaC)

### Terraform changes

None. The `infra-privileged` environment, its `main` policy, the Doppler project
`soleur-infra-privileged` and environment `prd` are already Terraform-declared (#8209 O0,
`apps/web-platform/infra/infra-privileged-environment.tf`). The Tier-B values the two jobs read
(`GITHUB_INFRA_APP_ID`, `GITHUB_INFRA_APP_PRIVATE_KEY`) were populated at O2 and the environment
secret `DOPPLER_TOKEN_INFRA_PRIVILEGED` at O3 (measured present).

### Apply path

No apply is prescribed. The merge-triggered push apply of `apply-web-platform-infra.yml` (manifest
path) is expected to plan empty (Overview). The only live change is the `soleur-infra` App
registration's permissions, which is not a Terraform-manageable resource (the `integrations/github`
provider has no App-registration resource) and has no REST endpoint (GitHub REST Apps reference,
fetched 2026-09-30). The committed manifest `apps/web-platform/infra/github-infra-app-manifest.json`
is its source of truth; the live change is runbook step O4c. `automation-status: UNVERIFIED —
soleur:work MUST NOT attempt it (constraint 2026-09-30: no production writes in this pipeline); O4c's
automation route is Playwright MCP against the App's permission settings and the org installation's
permission-review page in an admin-authenticated browser session, with the org-admin approval of the
permission request as the expected human gate.`

### Distinctness / drift safeguards

- Drift between the manifest and the live App is detectable read-only:
  `gh api /apps/soleur-infra --jq .permissions` vs `jq .default_permissions` of the manifest. O4c's
  verify cell uses exactly this comparison.
- Order safety (P6): a missing scope fails at the mint step, which runs before any tag, push or PR,
  and the composite's exact-grant check names the missing permission.

### Vendor-tier reality check

GitHub Apps: no tier gate. An App permission increase takes effect for an installation only after
the installation owner accepts it; until then tokens requesting the new scope are refused (the
failure mode above).

### Operator Sequence addition (canonical copy lands in `infra-credential-tiers-8209.md`)

| # | Step | Exact command(s) | Verify (read-only) | Rollback |
|---|---|---|---|---|
| O4c | Widen the `soleur-infra` App to the committed manifest (adds `actions: write`, `pull_requests: write`) and accept the change on the jikig-ai installation; then prove the re-tiered consumers on Tier B. Preconditions: O1, O3. **Recommended before merging #9262** (merging first is safe — releases fail at the mint step with nothing published until this step is done). Probe precondition: the pin drift guard is green on `main` (AC6 of `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`, which asserts the cloud-init pin equals the semver-max `vinngest-v*` tag merged into `main`), otherwise the probe opens a real (held) pin PR. A separate check, that no mint is pending: `git fetch --tags origin && bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` prints `result=noop` (otherwise an auto-mint's build and bump are due and would overlap the probe) | App settings → Permissions (Actions: Read and write; Pull requests: Read and write) → Save; org → Installed GitHub Apps → soleur-infra → accept (`automation-status: UNVERIFIED` — Playwright route in §Apply path). After #9262 merges: `gh workflow run build-inngest-bootstrap-image.yml -R jikig-ai/soleur --ref main -f ref=<current max vinngest tag> -f mirror_only=true`. **Writes it performs:** a digest-preserving crane re-copy of the existing GHCR manifest to zot (idempotent), a cosign signature on that digest, and a deployment record on `infra-privileged`; no PR (pin already at max; `--mirror-only` would hold one anyway) | `gh api /orgs/jikig-ai/installations --jq '.installations[]\|select(.app_slug=="soleur-infra")\|.permissions'` shows `actions:"write"` and `pull_requests:"write"`; `gh run view <id> -R jikig-ai/soleur --log \| grep 'app=soleur-infra installation=166065653'` finds the `app-token` notice in the `bump-cloud-init-pin` job, `gh run view <id> -R jikig-ai/soleur --json jobs --jq '.jobs[]\|select(.name=="bump-cloud-init-pin")\|.conclusion'` prints `success`, and the bump ends `result=noop`. If the build job goes red for a zot/tunnel reason the bump is skipped and the probe proved nothing — re-run after the registry is healthy. The mint job's admission: `gh run list -R jikig-ai/soleur --workflow mint-inngest-bootstrap-tag.yml --event push --branch main -L1 --json headSha,conclusion` shows #9262's merge SHA and `success`; its token path is proven end to end by the next real auto-mint's notice | Revert the two permissions in App settings; the jobs then fail at the mint step with nothing published. Code rollback: `git revert` of #9262 works until O10, and between O10 and O13 only together with O10's own rollback (drop the `prd_terraform` override); after O13 it is fix-forward only (restore the App permissions, or rotate the `soleur-infra` key in `soleur-infra-privileged/prd` — which every Tier-B Terraform root also uses). If the App token path is dead, the pin fallback is a pin PR written by a human (a human author passes CLA) |

## Architecture Decision (ADR/C4)

### ADR

- **Amend ADR-232** (§1 title, §3, §4, §8, "After #8209", Alternatives row A5): the pin bump and the
  build dispatch authenticate as the `soleur-infra` App from the Tier-B project on the main-only
  `infra-privileged` environment; the bump authors as `soleur-infra[bot]`; `push: tags` is removed.
- **Amend ADR-241 D5**: the dedicated infra App also serves the two inngest-release App-token
  consumers and carries `pull_requests:write` + `actions:write` for them.
- No new ADR ordinal (both are amendments), so no ordinal-collision risk.

### C4 views

All three model files were read (`model.c4`, `views.c4`, `spec.c4`). Enumeration:

- (a) External human actors: none new (the pin bump and auto-mint are unattended).
- (b) External systems: GitHub (`github`), Doppler (`doppler`), GHCR/zot — all already modeled; no
  new vendor.
- (c) Containers/data stores: none touched.
- (d) Relationships whose **description** the change falsifies: `github -> soleurMarketplace`
  (model.c4, the edge that documents the github-internal pin-bump write: names the soleur-ai App,
  `prd_terraform`, installation 122213433, `soleur-ai[bot]`, the composite's old path, and
  "dispatches the build from main as the soleur-ai App") — **edited in this PR** (Phase 6 item 3).
  `github -> doppler` (Tier-B edge) already describes the `soleur-infra-privileged` project read and
  stays correct. `views.c4` carries only a NOTE comment on the pin-bump write-back (no identity
  claim) — unchanged.
- Cardinalities: the edit changes no count embedded in edge prose; `c4-count-parity.test.sh` must
  stay green (run in Phase 7).

### Sequencing

The ADR text describes the shipped code. The runtime property (both consumers green on Tier B)
becomes true at O4c; ADR-241's Statuses table already gates D5's `accepted` on post-operator
verification, so no status flips here.

## Observability

```yaml
liveness_signal:
  what: "Each auto-mint and each pin bump is a GitHub Actions run; on success the mint composite emits a ::notice titled app-token naming app=soleur-infra and the installation id, and the bump job summary carries result=noop|opened|existing"
  cadence: "per qualifying push to main (mint) and per dispatched build (bump)"
  alert_target: "Slack #releases via SLACK_RELEASES_WEBHOOK_URL (both jobs' existing failure steps), plus the pin drift guard (deploy-script-tests) on main"
  configured_in: ".github/workflows/mint-inngest-bootstrap-tag.yml (step Post to Slack (auto-mint failure)); .github/workflows/build-inngest-bootstrap-image.yml (step Post to Slack (pin-bump failure)); .github/actions/mint-infra-app-token/action.yml (the app-token notice)"

error_reporting:
  destination: "GitHub Actions run annotations + Slack #releases; no Sentry surface (CI-only code path)"
  fail_loud: "::error:: from the composite naming GitHub's refusal message (sanitized) or the grant mismatch, in the workflow run log; the job fails and its Slack failure step posts"

failure_modes:
  - mode: "soleur-infra App lacks actions:write or pull_requests:write (O4c not done)"
    detection: "mint step fails with the composite ::error:: carrying GitHub's permission message before any tag/push/PR"
    alert_route: "Slack #releases (existing failure steps)"
  - mode: "a non-main dispatch reaches the bump job, or a hand-pushed tag is never built"
    detection: "workflow run log: GitHub refuses the infra-privileged environment (branch policy main only) before any step runs, so the job's own Slack step cannot fire; a hand-pushed tag starts no run at all after push: tags is removed"
    alert_route: "pin drift guard red on main (deploy-script-tests, run by main-health-monitor, which escalates to a ci/main-broken issue); recovery is one dispatch from main"
  - mode: "the infra-privileged environment or its main policy drifted but still admits main"
    detection: "scheduled-terraform-drift.yml drift-check plans github_repository_environment.infra_privileged and its main policy; a non-empty plan files an infra-drift issue"
    alert_route: "infra-drift GitHub issue (scheduled-terraform-drift.yml)"
  - mode: "the environment refuses a main run (deployment policy or environment deleted or changed to exclude main)"
    detection: "the drift-check job declares environment infra-privileged too, so it is refused as well and files nothing; what catches it is the missed check-in of the Sentry cron monitor scheduled-terraform-drift (apps/web-platform/infra/sentry/cron-monitors.tf, checkin_margin_minutes 60). For the mint job a refused run is otherwise silent (no tag, so AC6 stays green); the bump job's refusal leaves AC6 red on main"
    alert_route: "Sentry monitor + infra-drift issue"
  - mode: "exact-grant mismatch (GitHub granted more or less than the request)"
    detection: "composite ::error:: 'differ from the requested' in the workflow run log; no token output"
    alert_route: "Slack #releases (the job's failure step)"
  - mode: "a legacy or human-tipped soleur/inngest-pin-* branch at identity-switch time"
    detection: "bump script ::warning:: branch-has-manual-commits in the workflow run log; the job exits 0"
    alert_route: "pin drift guard red on main, then main-health-monitor, then a ci/main-broken issue (no Slack: the job is green)"
  - mode: "mirror_only PR held awaiting human merge (a mirror_only run never arms auto-merge and disarms one an earlier run armed)"
    detection: "the bump job's step summary line 'auto-merge: withheld … mirror_only=true', and the AC6 pin drift guard (apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh) red on main until the PR merges"
    alert_route: "main-health-monitor, then a ci/main-broken issue"
  - mode: "DOPPLER_TOKEN_INFRA_PRIVILEGED missing or revoked"
    detection: "the Verify DOPPLER_TOKEN_INFRA_PRIVILEGED present step fails, or the composite's Doppler read fails with a named ::error::"
    alert_route: "Slack #releases"
  - mode: "a future workflow mints an App token through the composite from a Tier-A token or unscoped"
    detection: "the composite refuses empty scope inputs, and a Tier-A token cannot read soleur-infra-privileged, so the step fails with a named ::error:: on its first run; a consumer passing the Tier-B token without an environment is caught by census G1b on the PR"
    alert_route: "required CI on the PR (G1b), else Slack via the job's failure step"

logs:
  where: "GitHub Actions run logs for mint-inngest-bootstrap-tag.yml and build-inngest-bootstrap-image.yml"
  retention: "90 days (GitHub Actions default log retention)"

discoverability_test:
  command: "curl -fsS --max-time 10 'https://api.github.com/repos/jikig-ai/soleur/actions/workflows/mint-inngest-bootstrap-tag.yml/runs?per_page=1'"
  expected_output: "success"
```

## Guard Contract

### Guard 1 — job-shape pins for the two re-tiered jobs

**Property.** `bump-cloud-init-pin` and `mint` each declare `environment: infra-privileged`, verify
and pass only `secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED`, mint through `mint-infra-app-token` with an
exact scoped permission set on `repositories: soleur`, and the build workflow's only trigger is
`workflow_dispatch`.

**Assembly.** Two suites, one per workflow, both reading the PyYAML-parsed job (the chokepoint is the
parsed mapping, not a text slice): `test-bump-inngest-bootstrap-pin.sh` Guard 2 (jobs-dict block) and
`test-mint-inngest-bootstrap-tag.sh` Guard 3 each compare the verify and mint steps to an **exact**
dict **and** its key set (`keyset_ok`), with job-wide `one_minter` and `no_tier_a` rows, so an extra
key, a second minter, a second token or a widened value is a different job. The trigger row reads the
parsed `on:` mapping via `doc.get("on", doc.get(True))` (PyYAML maps bare `on` to `True`) and
normalizes string/list/mapping forms. The composite's own contract is pinned by the `comp:*` rows
through the `doppler` stub's argv log.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove `environment: infra-privileged` from the bump job | bump job-env row RED |
| 2 | mint job `with.doppler-token` → `${{ secrets.DOPPLER_TOKEN }}` | `app-exact` RED |
| 3 | bump `permissions` widened to add `"administration":"write"` | bump mint-step exact row RED |
| 4 | re-add `push: tags: ['vinngest-v*.*.*']` to the build workflow | trigger row RED |
| 5 | add a second, otherwise-compliant mint step to the bump job that passes `secrets.DOPPLER_TOKEN` (a second member after a compliant first) | `one_minter(bump)` and `no_tier_a(bump)` RED (the exact row alone stays green — `find()` returns the first match) |
| 6 | mint job `environment` moved to a non-Tier-B name (`production`) | job-env row RED (and census G1c RED) |
| 7 | add `continue-on-error: true` to the mint job's App step | `app-exact` RED (key-set half) |
| 8 | change the composite's Doppler project argv to `soleur` | composite argv row RED (the stub exits 1 on any other project) |
| 9 | drop `--mirror-only` from the bump step, or make the script arm auto-merge under it | `g1.mirror-only-held` RED |

**Harness rows.**

- H1: point the jobs-dict lookup at a job name that does not exist — the new `g2.bump-job:parsed`
  row and the `MIN_ASSERTIONS` floor go RED rather than the exact rows passing vacuously on an empty
  dict.
- H1b: drop the key-set half of `exact()` — mutation row 7 (above) must then stay green, proving the
  half is load-bearing; restore it.
- H1c: before any bump-side mutation, the unmodified workflow copy must run clean through the new
  bump-side harness (instrument control); a mutation applied to a copy that was already red proves
  nothing.
- H2 (must-PASS, non-canonical): environment written in mapping form
  `environment: {name: infra-privileged}` passes the job-env row, because every env row goes through
  `norm_env` (as the census's `env_arms` does).

**Anchor.** Same-repo constants, so one diff can edit both the workflow and its pin; the anchors
outside the commit are operator review of UNTRUSTED-CI paths (no auto-merge), the census (an
independent suite whose G1b/G1c assert the environment set), and O4c's live evidence (the
`app-token` notice in a `main` run), which a branch cannot produce.

## User-Brand Impact

- **If this lands broken, the user experiences:** a delay in fixes to the inngest control plane
  (background jobs) reaching production — a carrier-changing merge would not auto-mint/publish, or
  its pin-bump PR would not open, until the failure (posted to Slack #releases) is fixed. Running
  hosts keep their current pinned image; nothing user-facing breaks at merge.
- **If this leaks, the user's data / workflow is exposed via:** the `soleur-infra` App key (already
  Tier B since O2) gaining `pull_requests:write` and `actions:write` on `soleur` / `soleur-marketplace`.
  Its existing `administration:write` + `contents:write` already dominate those scopes, so the
  exposure class does not change; the change *removes* a branch-reachable App-key consumer path
  (`prd_terraform` via a repo secret). One widening to state plainly (architecture review): the two
  jobs hold `DOPPLER_TOKEN_INFRA_PRIVILEGED`, which reads the **whole** Tier-B project; once sibling
  PR #9263 stores `GITHUB_APP_RUNTIME_DOPPLER_TOKEN` there, these jobs can read the path to the
  soleur-ai runtime key without naming it. Bounded by the main-only boundary (still nominal until
  #8609 R1 closes); the structural fix is the narrower-source deferral, now triggered by #9263's
  merge.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: CI-only credential re-tiering that moves two jobs from a branch-reachable to a main-only credential; no user data path, and the widened App scopes are dominated by scopes the same Tier-B key already holds.`

## Review & Consult Provenance

- Scoped advisor consult (plan Step 4.5): cut the dead `soleur-ai` enum arm (adopted: composite made
  Tier-B-only and renamed); make O4c verifiable (adopted: installations read + `mirror_only` probe);
  a `dry_run` input (cut: `mirror_only` covers it).
- Domain leaders: CTO (α confirmed; concerns folded into the Engineering assessment), CLO (no
  blocker; Art. 30 follow-up deferred).
- Plan review, 3-agent eng panel (threshold `none`): DHH, Kieran, code-simplicity. Applied as
  mechanical: cut G1j; cut the legacy read-side identity set; exact-dict + key-set rows instead of
  text greps; drop the runbook pointer from the composite; the `app/<slug>` PR-author bug; the
  missed suite rows (`ACTION=`, `g2.action:*`, verify-step finder); AC3 as the mint script's own
  `--dry-run`; the #8747 runbook block and the mint script's wording; internal contradictions; the
  AC11 pathspec. Rejected: DHH's `discoverability_test` change (the curl output was measured to
  contain `"conclusion": "success"`; `gh` is not on preflight's probe-verb allowlist); deleting the
  build resolver's dead `push` arm (byte-parity-tested inline logic; only comments that become false
  are edited). Surfaced, not applied: code-simplicity's `GITHUB_TOKEN` dispatch (User-Challenge,
  DC-2); step-scoping guard rows (taste, DC-5).
- Deepen-plan (2026-09-30): security-sentinel (P0 `mirror_only` re-sign → `--mirror-only` withholds
  auto-merge, rest deferred as pre-existing; argv project binding; message sanitizing),
  architecture-strategist (#9263 exposure note; O10 verify limb; runbook/ADR/C4 completeness),
  spec-flow-analyzer (in-flight runs and AC5 at merge time; stale `die` messages; O4c preconditions
  and writes; rollback nuance; the web-1 deploy), test-design-reviewer (key-set formula,
  `one_minter`/`no_tier_a`, argv-observable stub, trigger normalization, PR-author stub flag,
  bump-side harness), observability-coverage-reviewer (refusal and grant-mismatch failure modes;
  environment drift detected by the drift-check; probe moved to the mint workflow), verify-the-negative
  sweep (8/8 confirmed). Not adopted: a separate notifier job for environment refusals (the mirror-only
  suite forbids a third build job; policy drift is already caught by `scheduled-terraform-drift.yml`).
- The named CEO/design/devex panel was not re-spawned: no UI surface, no product/market language, and
  the CTO devex pass had already run in Phase 2.5 on the same plan.

## Open Code-Review Overlap

1 open scope-out mentions a touched file's workflow name:

- #8593 (review: #6793 probe gate window narrower than the silent-truncation property) — mentions
  `build-inngest-bootstrap-image.yml` only as an executor of `.github/scripts/`; its concern is the
  unbounded-`gh`-enumeration detector in `plugins/soleur/test/components.test.ts`. **Acknowledge:**
  different concern; this plan adds no `gh … list` call (the bump script's existing `gh pr list`
  carries `--limit 200`).

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO: choose α (mint as `soleur-infra` from Tier B). β would put a key of the org-wide
`soleur-ai` App (`repository_selection: all`, two outside installations) into CI; α adds nothing to
the blast radius because `soleur-infra`'s `administration:write` already covers the two new scopes.
Read-side identity switch verified safe: only `cla.yml` and `bump-inngest-bootstrap-pin.sh` key on
`soleur-ai[bot]`; no workflow `if:`, ruleset or PR-author query depends on the pin-bump author; the
CLA ruleset's bypass integration 1236702 is not `soleur-ai` (App id 3261325), so the allowlist is
already the path those PRs take. Auto-merge by a different App does not change ordering. Amend the
ADRs, no new ADR. Concerns folded in: (1) `DOPPLER_TOKEN_INFRA_PRIVILEGED` reads the whole Tier-B
project, so it should appear only in the verify step's `env:` and the composite's `with:` — never job-
or workflow-level `env:` or `GITHUB_ENV`; the exact-dict rows pin those two steps, a dedicated
absence guard was cut at plan review (DC-5), and a narrower App-key-only Doppler source is a deferral. (2) After O10 the rollback is fix-forward (App permissions / key), not a revert — O4c's
rollback cell says so, and O10's precondition names exactly what O4c proved (the bump's mint on Tier
B; `actions:write` only by the installations read until the first real auto-mint). (3) Splitting
`Decide` into an environment-less job (fewer environment admissions per carrier-path push) — recorded
as a taste item in decision-challenges.md, not adopted. (4) The literal-read census concern is moot
after the enum was cut; G4e's floor moves with a rationale. (5) No automated manifest drift check —
acceptable; O4c's read-only comparison covers it.

### Legal

**Status:** reviewed
**Assessment:** CLO: nothing blocks the PR. `soleur-infra[bot]` is an org-owned App producing
scripted commits, so no contributor rights are involved (same reasoning that allowlisted
`soleur-ai[bot]`); the login match needs the `335404629+soleur-infra[bot]@users.noreply.github.com`
author email, which `BOT_EMAIL` uses; add a `cla.yml` comment like the #5520 one. `build-bypass.ts`
reads `cla.yml` at run time, so bypass evidence for the new login is recorded automatically; the only
required evidence-side change is the exact-set pin in `allowlist.test.ts`. No personal data, no new
processing activity, no Article 30 row. Follow-up (separate issue, not this PR): Processing Activity
12's security-measures cell item (1) in `knowledge-base/legal/article-30-register.md` says the infra
App "is scoped to the resource types these roots actually manage"; widening it for pin-bump PRs and
build dispatch makes that sentence inaccurate — fix in-cell with a Superseded marker, worded to take
effect at O4c.

## Deferrals

- Article 30 register PA-12 item (1) wording (CLO follow-up above) — legal cluster, out of scope for
  this PR by operator constraint. Tracking issue to be filed at ship (`domain/legal`), re-evaluate
  when O4c runs.
- A narrower Doppler source for the two App-token jobs (CTO concern 1): a config or project holding
  only `GITHUB_INFRA_APP_ID` / `GITHUB_INFRA_APP_PRIVATE_KEY`, so the unattended jobs stop holding a
  token that can read the whole Tier-B project. Needs a new Doppler container plus an operator-minted
  read token (a new operator step), so it is not folded into the O10 critical path. Tracking issue to
  be filed at ship (`domain/engineering`, `type/security`), blocked-by #8209; re-evaluate when #9263
  merges (it adds `GITHUB_APP_RUNTIME_DOPPLER_TOKEN` to the same project — architecture review).
- Pre-existing build-job supply-chain gaps in `build-inngest-bootstrap-image.yml` (security review;
  not introduced by this PR, and GHCR retirement — ADR-096 5.3–5.5 — is out of scope): the cosign step
  signs the digest re-resolved from the tag rather than the digest the build pushed; a branch-run
  build job (workflow-level `packages: write`, `DOPPLER_TOKEN_PRD`, `id-token: write`) can push to an
  existing tag; `uses: ./.github/actions/…` composites in the build job resolve from the checked-out
  tag tree, so an off-main tag's composite runs in a `main`-ref run under `mirror_only`; and any repo
  writer's `main` dispatch is admitted to the Tier-B bump job (no reviewers). This PR's mitigation is
  `--mirror-only` withholding auto-merge. Tracking issue to be filed at ship (`type/security`,
  `domain/engineering`, `priority/p1-high`) naming the fixes proposed in review: sign the push-captured
  digest, `cosign verify --certificate-identity …@refs/heads/main` in the bump job, check out the tag
  tree to a subpath so `./` composites come from `main`, and consider arming auto-merge only when
  `github.triggering_actor` is the auto-mint App.

## Acceptance Criteria

### Pre-merge (this PR)

- [ ] AC1 — `build-inngest-bootstrap-image.yml` job `bump-cloud-init-pin` declares
  `environment: infra-privileged` and references no Tier-A `secrets.DOPPLER_TOKEN`; its mint step
  uses `./.github/actions/mint-infra-app-token` with
  `doppler-token: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}`, `installation-id: "166065653"`,
  `permissions: '{"contents":"write","pull_requests":"write"}'`, `repositories: soleur` (Guard 2 rows
  green; `test-bump-inngest-bootstrap-pin.sh`).
- [ ] AC2 — `mint-inngest-bootstrap-tag.yml` job `mint` declares `environment: infra-privileged`,
  keeps `if: github.ref == 'refs/heads/main'`, and its App step uses the renamed composite with the
  Tier-B token, `installation-id: "166065653"`, `permissions: '{"actions":"write"}'`,
  `repositories: soleur`; every credential step still precedes `Create tag`
  (`test-mint-inngest-bootstrap-tag.sh` Guard 3 exact rows green).
- [ ] AC3 — `build-inngest-bootstrap-image.yml`'s parsed `on:` has exactly one key,
  `workflow_dispatch` (trigger row green), and on the final branch tree (after `git fetch --tags
  origin`) `bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run` prints `result=noop` — so
  the merge-triggered mint run mints nothing (measured on the pre-change tree 2026-09-30:
  `base=v1.1.44 reason=unchanged result=noop`).
- [ ] AC4 — the renamed composite refuses an empty `doppler-token`, `installation-id`,
  `permissions` or `repositories` before any Doppler call (zero `DOPPLER_LOG` lines); asks Doppler
  for exactly `GITHUB_INFRA_APP_ID` / `GITHUB_INFRA_APP_PRIVATE_KEY` with `--project
  soleur-infra-privileged --config prd` in argv (the stub refuses anything else, with
  `DOPPLER_PROJECT`/`DOPPLER_CONFIG` unset); refuses a grant that differs from the request; prints
  GitHub's message with CR/LF/`::` stripped on a failed exchange; prints the `app-token` notice on
  success (`comp:*` rows in `test-mint-inngest-bootstrap-tag.sh`).
- [ ] AC5 — `bump-inngest-bootstrap-pin.sh` authors as `soleur-infra[bot]
  <335404629+soleur-infra[bot]@users.noreply.github.com>`, reuses an open pin PR whose author lists as
  `app/soleur-infra` and does not reuse one authored by `app/soleur-ai` or a human (the
  `|author=` stub rows), never arms auto-merge under `--mirror-only true` (`g1.mirror-only-held`),
  and still never force-pushes a human tip (identity
  rows in `test-bump-inngest-bootstrap-pin.sh`). **At merge time** (a merge-time checklist command
  in the PR body, not a ready-time check — the PR may wait days for review), `git ls-remote --heads
  origin 'soleur/inngest-pin-*'` prints nothing and `gh pr list --state open --search
  "head:soleur/inngest-pin" --json number --jq length` prints `0` (no legacy-authored pin branch the
  in-place switch would treat as human); if one exists, close the PR and delete the branch first.
- [ ] AC6 — `bash tests/scripts/test-infra-privileged-tier-census.sh` is green; its stderr
  `IPT_TIERB=` line names both `build-inngest-bootstrap-image.yml::bump-cloud-init-pin` and
  `mint-inngest-bootstrap-tag.yml::mint`; G4e reports `[3 reading steps]` against floor 3 with the
  dated rationale; `CENSUS_ROWS` is unchanged by this PR (sibling #9263 raises it; re-measure after
  any rebase).
- [ ] AC7 — `github-infra-app-manifest.json` `default_permissions` include `"actions": "write"` and
  `"pull_requests": "write"` (`jq -r '.default_permissions.actions, .default_permissions.pull_requests' apps/web-platform/infra/github-infra-app-manifest.json`
  prints `write` twice).
- [ ] AC8 — `cla.yml` allowlist contains `soleur-infra[bot]` with the bot-id/email comment, and
  `allowlist.test.ts` passes with the updated exact set.
- [ ] AC9 — ADR-232 and ADR-241 amended as in Phase 6; C4 `model.c4` edge updated and
  `model.likec4.json` regenerated; `c4-model-freshness`, `c4-count-parity`, `c4-code-syntax`,
  `c4-render` green.
- [ ] AC10 — `infra-credential-tiers-8209.md` carries O4c (row, order constraint "O4c precedes O10",
  O10 precondition list) and updated Group 4 rows; neither job appears in the "declare no
  `environment:`" list; `inngest-server.md` hand-tag block is present tense;
  `apply-web-platform-infra-job-rationale.md` says three consumers.
- [ ] AC11 — the residual sweep `git grep -n "mint-soleur-ai-app-token" -- .github apps tests scripts plugins`
  prints nothing (docs may say "renamed from"); `git grep -n "runs its own publish" -- .github` prints
  nothing; `git grep -n "mint-soleur-ai-app-token" -- knowledge-base/engineering`
  hits only lines that also contain `renamed`; `grep -n -E 'secrets\.DOPPLER_TOKEN([^_A-Za-z0-9]|$)' .github/workflows/build-inngest-bootstrap-image.yml .github/workflows/mint-inngest-bootstrap-tag.yml`
  prints nothing.
- [ ] AC12 — workflow-file-size gate green; `actionlint` clean on the two workflows;
  `python3 scripts/lint-guard-contract.py` passes on this plan;
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes.
- [ ] AC13 — PR #9301 marked ready with `Closes #9262` and `Refs #8209`; its first body line states
  the merge side effects; not admin-merged; no auto-merge queued (UNTRUSTED-CI).

### Post-merge (runbook O4c — not this pipeline)

- [ ] AC14 — `soleur-infra` installation permissions include `actions: write` and
  `pull_requests: write` (read-only `gh api /orgs/jikig-ai/installations` check in O4c).
- [ ] AC15 — one `main`-dispatched build's `bump-cloud-init-pin` job is green under environment
  `infra-privileged` with the `app-token` notice naming `app=soleur-infra` — the evidence #8209's
  O10 hold names as its release condition.

## Test Scenarios

1. Auto-mint on a carrier-changing push to `main`, O4c done: mint job runs under `infra-privileged`,
   mints `soleur-infra` scoped to `actions:write`, tags with `GITHUB_TOKEN`, dispatches once; build
   runs from `main`; bump mints `soleur-infra` scoped to contents+pull_requests, opens a
   `soleur-infra[bot]` PR, required checks run, CLA passes via allowlist, auto-merge arms.
2. Same push, O4c **not** done: mint fails at the App step with GitHub's permission message; no tag
   exists; Slack posts "FAILED before any tag was created". After O4c,
   `gh workflow run mint-inngest-bootstrap-tag.yml --ref main` mints and publishes.
3. `mirror_only` dispatch from `main` of the current max tag: bump mints (proves Tier-B path) and
   ends `result=noop`.
4. `gh workflow run build-inngest-bootstrap-image.yml --ref some-branch -f ref=<tag>`: build job runs
   (Tier A, unchanged), bump job refused by the environment branch policy; no Tier-B secret is
   materialized.
5. A hand-pushed `vinngest-v*` tag: no run starts; the runbook's dispatch-once line publishes it.
6. A legacy `soleur-ai[bot]` pin branch exists at switch time (AC5 says it will not): the bump prints
   a `branch-has-manual-commits` warning and exits 0 (job green, no Slack); it never overwrites the
   branch, and the pin drift guard stays red on `main` until the branch is deleted (main-health
   monitor escalation).
9. Same-target re-run with an open pin PR (author listed as `app/soleur-infra`): the bump comments on
   and reuses it instead of dying at `gh pr create` (the pre-existing bug this PR fixes).
10. A `mirror_only` dispatch whose target needs a bump: the PR opens held, never auto-merged, and its
    body says a backfill cannot attest provenance.
11. A build dispatched before this PR merges whose bump job starts after it: "action not found" on
    the deleted composite path; recovery is a `mirror_only=true` dispatch from `main` (the merge-time
    checklist makes this case not arise).
7. After O10 (sentinel in `prd_terraform`): both jobs unaffected (they no longer read it).
8. The merge of this PR itself: the mint workflow's push run is admitted to `infra-privileged`,
   decides `noop`, runs no credential step.

## Risks & Sharp Edges

- **O4c before O10, always; ideally before this merge.** Between merge and O4c, a carrier-changing
  merge does not publish; it fails loudly and safely (credentials precede every write). This is why
  O4c is ordered before O10 and verified by a `main` run, not by reading the App settings alone.
- **The first real mint after O4c is the first live exercise of `actions:write` on the infra App.**
  O4c's `mirror_only` dispatch proves the key, installation and the contents/pull_requests grant; the
  `actions:write` grant is proven by the installations API read and by the first real mint's notice.
- **CLA allowlist is legal-adjacent.** "The legal cluster" is out of scope for this PR. The edit adds
  an internal automation login to a login-based allowlist (the same mechanism already used for
  `soleur-ai[bot]`, `claude[bot]`); the CLO found no blocker. It is recorded in decision-challenges.md
  with fallback β if it is read as inside the legal cluster.
- **Composite `required:` is not enforced by the runner** — hence the explicit empty-input refusals.
- **G4e's floor moves down.** The population legitimately shrinks (the composite no longer reads the
  evictable key at all — it reads a fixed Tier-B project), and the lowering carries a dated
  rationale; the three inline readers stay under G4e.
- **`environment:` creates a deployment record per run** (every qualifying push's mint job). Same as
  the existing push-apply jobs on `infra-privileged`; no reviewer, so no wait.
- **In-flight runs at merge time load the deleted composite path.** Both jobs check out `main`, so a
  run dispatched before the merge fails after it; the merge-time checklist (Phase 8) requires no
  queued or in-progress run of either workflow.
- **Sibling PR #9263 (#8609 PR-A, open draft) edits five of the same files:** ADR-241, `model.c4`,
  `model.likec4.json`, `infra-credential-tiers-8209.md` and the census. Whichever merges second
  rebases; `model.likec4.json` is always regenerated after the rebase, never hand-merged, and the
  census floors are re-measured on the rebased tree.
- **Merging triggers a routine `web-platform-release` and an expected-empty infra push apply** (see
  Overview). Neither is a new risk class, and both precedents exist (#9202).
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Filled above.
