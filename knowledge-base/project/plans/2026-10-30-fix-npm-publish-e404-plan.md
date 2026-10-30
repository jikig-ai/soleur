---
title: "fix(ci): npm Publish fails E404 on every merge — @soleur/opencode not in registry"
type: fix
date: 2026-10-30
slug: fix-npm-publish-e404
branch: feat-one-shot-11585-npm-publish-e404
issue: 11585
closes: 11585
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix(ci): npm Publish fails E404 on every merge — @soleur/opencode not in registry

## Overview

The `npm Publish` GitHub Actions leg of the release pipeline has failed with
`npm error 404 Not Found - PUT https://registry.npmjs.org/@soleur%2fopencode` on
every merge to main since 2026-10-29T22:26 UTC (runs 40965877479, 40969956726,
40976620155, 40985871424, 40985979752, 40995751744), while the release leg
(Version Bump and Release) keeps succeeding. This plan restores the delivery leg
by replacing the long-lived `NPM_TOKEN` credential with npm OIDC trusted
publishing, per the ruling recorded in `decision-challenges.md` (T1).

## Problem Statement / Motivation

`npx @soleur/opencode install` is the documented public install path for the
OpenCode harness (README.md, plugins/soleur/README.md, docs
`getting-started.njk`, shipped PR #10723). Every release since 3.363.0
(2026-10-29T20:02Z) has failed to reach the registry, so the channel has served
a stale package to new installers for ~30 hours and counting. The leg fails
loudly — each run goes red — but nothing downstream blocks on it, so the
staleness accumulates silently.

**Root cause (evidence-based).** The issue's premise — "the `@soleur` scope is
not claimed/registered" — is disproven:

- `GET https://registry.npmjs.org/@soleur%2fopencode` returns **200** with
  maintainer `deruelle` (`jean.deruelle@jikigai.com`, matching
  `packages/opencode-plugin/package.json`) and `dist-tags.latest = 3.363.0`
  across ~60 published versions.
- Publishing **worked** through 3.363.0 (run 40944748535, 2026-10-29T20:02Z).
  The workflow file is unchanged since 2026-10-23 — nothing in the pipeline
  changed when the failures began.
- `gh secret list` shows `NPM_TOKEN` last updated **2026-10-22T21:55:54Z** and
  still present. The gap from secret-set to first E404 is **~7.0 days** —
  consistent with a short-lived granular access token expiring (or being
  revoked) npm-side.
- npm returns 404 (not 403) on `PUT` to an existing scoped package when the
  presented credential lacks publish rights — the registry masks
  authorization failures to avoid leaking package existence. E404 here is an
  **auth failure wearing a not-found costume**, not a missing package.

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Reality (verified 2026-10-30) | Plan response |
|---|---|---|
| "the `@soleur` scope is not claimed/registered on npmjs.org for the publishing token's account" | Scope claimed; package exists; `latest` 3.363.0; maintainer `deruelle` | The claim-the-scope fix arm is descoped as moot |
| "repoint the publish step at the intended registry" | npmjs.org IS the intended registry — the documented install path resolves there | Repointing (e.g., GitHub Packages) breaks `npx` for anonymous installers; rejected in ruling T1 |
| "remove the leg if npm delivery isn't a real channel" | npm delivery is a real, documented channel (#10723) with ~60 published versions | Remove-leg arm rejected in ruling T1 |

## Proposed Solution

Migrate `.github/workflows/npm-publish.yml` from token auth to **npm OIDC
trusted publishing** (GA since 2025-07-31): the `publish` job mints a
short-lived OIDC token, npm exchanges it for a publish credential bound to
`jikig-ai/soleur` + `npm-publish.yml`, and no long-lived secret exists to
expire. This deletes the entire credential-expiry failure class rather than
rotating back into it. Requires npm CLI >= 11.5.1 (Node 22 bundles 10.x, so the
job installs `npm@^11` explicitly) and a one-time trust entry on the package,
created by the maintainer with `npm trust github` — no dashboard click-through
needed.

`Ruled by CTO agent, 2026-10-30: adopt npm OIDC trusted publishing - see
knowledge-base/project/specs/feat-one-shot-11585-npm-publish-e404/decision-challenges.md
row T1 for the full rationale and rejected alternatives.`

## Technical Considerations

- **`.npmrc` cleanup is load-bearing.** `setup-node`'s `registry-url` writes
  `//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN}` into `.npmrc`. Left in
  place with the env var gone, the stale auth line can mask OIDC selection or
  fail the publish before the exchange (npm/cli#8976 documents the masked-error
  class). The fix removes `registry-url` and `NODE_AUTH_TOKEN` together; the
  default registry is already registry.npmjs.org.
- **npm CLI floor.** Trusted publishing needs CLI >= 11.5.1; `npm trust` needs
  >= 11.15.0. Node 22's bundled npm is 10.x, so a step installs `npm@^11`
  (in-major pin — deterministic, unlike `npm@latest`, and covers both floors).
  GitHub-hosted `ubuntu-latest` satisfies the runner requirement.
- **Provenance comes free** on OIDC publishes (no `--provenance` flag needed);
  the repo is public so the private-repo E422 edge case does not apply.
- **`npm view` skip-check stays** — it is an anonymous read and works
  identically with or without a credential.
- **Security posture improves** in two directions: no storable/leakable publish
  token, and the publish identity is bound to this exact repo+workflow — a
  token minted elsewhere can no longer publish the package once `NPM_TOKEN` is
  retired.
- **NFR impacts:** reliability (credential-expiry class removed), security
  (short-lived scoped credentials, provenance attestation). No hot-path or
  data-model impact; nfr-register unaffected.

## Research Insights

- **Premise Validation (Phase 0.6):** Issue #11585 verified OPEN (p1-high,
  type/bug, domain/engineering, meta/machinery). `.github/workflows/npm-publish.yml`
  and `packages/opencode-plugin/` exist on this branch. The issue's root-cause
  analysis is stale (see Research Reconciliation). Collision precheck: PR
  #11598 is THIS pipeline's own auto-draft on the same branch; the foreign
  `test-all.sh` proc in `.worktrees/feat-11556-required-check-time` is
  unrelated. Mechanism-vs-ADR sweep: no ADR covers npm publishing; the nearest
  credential precedent is ADR-241 (tiered secrets) — `NPM_TOKEN` is a plain repo
  secret, unmanaged by `infra/github/` Terraform (grep: zero hits).
- **Property List (Phase 0.6b):** P1 every merged release reaches the npm
  channel; P2 the publish credential cannot silently expire or revoke
  undiagnosed; P3 a publish failure is classifiable (auth vs scope vs
  registry); P4 the documented `npx @soleur/opencode install` path keeps
  working for anonymous users.
- **Cut List (Phase 0.6b):** claim-scope mechanism (property P1 — moot, scope
  already owned); repoint-registry (breaks P4 — GitHub Packages requires auth
  on public installs); remove-leg (violates P1/P4 — live documented channel);
  dedicated dead-leg monitor workflow (property "notice dead leg early" —
  covered by GitHub's run-failure notification; the 30-hour gap was triage
  latency, not missing signal; out of scope).
- **Key files:** `.github/workflows/npm-publish.yml:28-29` (job permissions),
  `:40` (`registry-url`), `:50-73` (publish step, `NODE_AUTH_TOKEN` at :53);
  `packages/opencode-plugin/package.json` (name/bin/files);
  `plugins/soleur/scripts/sync-npm-package.ts` (payload materializer, unchanged);
  `.github/workflows/reusable-release.yml:126` (repo's existing
  `id-token: write` OIDC precedent for cosign);
  `plugins/soleur/test/token-drift-workflow-causes.test.sh` (house convention:
  assert on PARSED workflow YAML, never grep — comments cannot survive
  `yaml.safe_load`); `scripts/test-all.sh` registers
  `plugins/soleur/test/*.test.sh` automatically; `scripts/regenerate-c4-model.sh`
  (c4-model-freshness gate).
- **Institutional learnings:** `2026-10-23-committing-generated-npm-payload-…`
  (payload must be materialized, never committed — unchanged here);
  `2026-05-04-schedule-once-template-missing-id-token.md` (omitting
  `id-token: write` fails every OIDC consumer — this plan's core edit);
  `cq-assert-anchor-not-bare-token` (YAML assertions on parsed fields only).
- **External docs:** npm trusted publishers —
  `https://docs.npmjs.com/trusted-publishers/` (requires npm CLI >= 11.5.1,
  Node >= 22.14.0, GitHub-hosted runner, `id-token: write`); `npm trust` CLI —
  `https://docs.npmjs.com/cli/v11/commands/npm-trust` (>= 11.15.0, `--file`,
  `--repo owner/repo`, `--allow-publish`); GitHub changelog GA 2025-07-31.
- **Related work:** PR #10723 (introduced the leg), #10927/#10930 (SIGPIPE fix,
  unrelated), issue #11585.

## Implementation Phases

### Phase 1: Workflow auth migration

- Edit `.github/workflows/npm-publish.yml`: add `id-token: write` to the
  `publish` job's `permissions:`; remove `registry-url` from `Setup Node` and
  `NODE_AUTH_TOKEN` from the publish step env; insert `npm install -g npm@^11`
  before the publish step; wrap `npm publish` in a failure arm that prints a
  one-line classification hint (E404 -> verify the npm trusted-publisher entry
  for jikig-ai/soleur + npm-publish.yml).

### Phase 2: Wiring guard + decision record

- Create `plugins/soleur/test/npm-publish-oidc.test.sh` asserting the OIDC
  wiring on the PARSED workflow YAML (Guard Contract below).
- Create `knowledge-base/engineering/architecture/decisions/ADR-309-npm-publish-oidc-trusted-publishing.md`
  (provisional ordinal — re-verify next-free against `origin/main` at ship
  time) with `status: adopting`.
- Edit `knowledge-base/engineering/architecture/diagrams/model.c4` (add
  `npmRegistry` external system + `github -> npmRegistry` publish edge) and
  `views.c4` (add `npmRegistry` to the context and containers include lists);
  run `bash scripts/regenerate-c4-model.sh`; run
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 3: Operator trust entry + end-to-end verification

- Operator (npm maintainer `deruelle`, npm >= 11.15.0, 2FA): `npm trust github
  @soleur/opencode --file npm-publish.yml --repo jikig-ai/soleur
  --allow-publish`; verify with `npm trust list @soleur/opencode`.
- `gh workflow run npm-publish.yml` on main; confirm run green and
  `npm view @soleur/opencode version` equals the newest `v*` tag.
- After the first green OIDC publish, operator deletes the `NPM_TOKEN` repo
  secret (may be deferred; the leg no longer reads it).

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| Claim the `@soleur` npm scope | Rejected — scope is already owned; package exists with ~60 versions (evidence in Problem Statement) |
| Repoint publish at GitHub Packages | Rejected — GH Packages requires auth even for public installs; breaks the documented `npx @soleur/opencode install` path |
| Remove the publish leg | Rejected — npm is a real, documented delivery channel (#10723); removing strands users on 3.363.0 and dead-ends the OpenCode launch arc |
| Rotate `NPM_TOKEN` (new granular token) | Rejected as primary — restores the leg but keeps the recurring expiry/rotation class that caused the incident; retained as fallback if the npm-side trust entry proves impossible (ruling T1 dissent) |
| **OIDC trusted publishing** | **Adopted (ruling T1)** — eliminates the long-lived credential; repo OIDC precedent exists; provenance free |

No backfill of the six skipped versions (3.363.1-3.364.3): npm has no
sequential-version requirement and `latest` moves to the newest tag (ruling
T2). A manual per-tag publish remains possible if ever needed.

## Files to Edit

- `.github/workflows/npm-publish.yml` — `id-token: write` permission; drop
  `registry-url` + `NODE_AUTH_TOKEN`; `npm install -g npm@^11` step; publish
  failure-classification arm.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `npmRegistry`
  `#external` system + `github -> npmRegistry` edge documenting the OIDC
  publish channel.
- `knowledge-base/engineering/architecture/diagrams/views.c4` — `npmRegistry`
  in the `context` and `containers` include lists (both endpoints must be
  listed for the edge to render — #7332 rule).
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` —
  regenerated by `scripts/regenerate-c4-model.sh` (c4-model-freshness gate).

## Files to Create

- `plugins/soleur/test/npm-publish-oidc.test.sh` — parsed-YAML wiring guard.
- `knowledge-base/engineering/architecture/decisions/ADR-309-npm-publish-oidc-trusted-publishing.md`
  — credential-boundary decision record (provisional ordinal).

## User-Brand Impact

- **If this lands broken, the user experiences:** `npx @soleur/opencode
  install` succeeding but delivering a stale package (registry `latest` stuck
  behind the current release), or — on total channel loss — a hard
  `Not Found` on the documented install path.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  user-data vector; the credential class is the exposure and OIDC removes it —
  there is no longer a long-lived publish token to exfiltrate or misuse, and
  the publish identity is repo+workflow-bound.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** harm is broad-but-mild (every new
  installer gets a stale plugin), not one severe user incident — the same
  channel-staleness shape, one tier below the feature spec's
  `single-user incident` because a stale-but-working install degrades rather
  than destroys.

## Observability

```yaml
liveness_signal:
  what: "npm Publish workflow run conclusion after each completed 'Version Bump and Release' run on main"
  cadence: "per-release (workflow_run trigger)"
  alert_target: "GitHub Actions failure notification to the operator"
  configured_in: ".github/workflows/npm-publish.yml"
error_reporting:
  destination: "GitHub Actions run log for the publish job"
  fail_loud: "npm error line + ##[error]Process completed with exit code 1 marks the run red; the new failure arm prints an E404-classification hint naming the trusted-publisher entry to check"
failure_modes:
  - mode: "OIDC exchange rejected (trust entry absent/mismatched: wrong repo, workflow filename, or environment)"
    detection: "run fails red on PUT with E401/E404 + the classification hint in the log"
    alert_route: "GitHub Actions failure notification"
  - mode: "npm CLI below 11.5.1 in the job (pin drift or install step removed)"
    detection: "ENEEDAUTH with no token configured; additionally caught by the wiring guard asserting the CLI-freshness step exists"
    alert_route: "GitHub Actions failure notification + PR-time test-all.sh red"
  - mode: "version already published for the resolved tag"
    detection: "benign — the npm view skip arm exits 0 before publish"
    alert_route: "none (no alert by design)"
logs:
  where: "GitHub Actions run logs for npm-publish.yml"
  retention: "GitHub-hosted default (~90 days)"
discoverability_test:
  command: "curl -s https://registry.npmjs.org/@soleur%2fopencode | jq -r .name"
  expected_output: "@soleur/opencode"
```

Detection-gap note: `main-health-monitor.yml` does not watch this workflow;
the loud red run + notification is the detection contract, and adding a
dedicated monitor is on the Cut List (existing signal was delivered — the gap
was triage latency).

## Infrastructure (IaC)

- **Terraform changes:** none possible or needed. No npm Terraform provider
  exists, and the `NPM_TOKEN` repo secret is operator-managed outside
  `infra/github/` (verified: zero Terraform references). The GitHub-side
  change is declarative YAML; the npm-side trust entry is created by the
  maintainer's `npm trust github` CLI call (npm >= 11.15.0) — a third-party,
  operator-owned credential surface with no IaC substrate (operator row T1a).
- **Apply path:** n/a — no Terraform apply. Ordering: the YAML can merge before
  the trust entry exists (the leg simply keeps failing E404 until it does);
  first green publish proves the boundary.
- **Host fan-out:** n/a — GitHub-hosted runner only (trusted publishing does
  not support self-hosted runners; not needed here).
- **Distinctness / drift safeguards:** single public package, no dev/prd
  split; the wiring guard prevents silent reversion to token auth.
- **Vendor-tier reality check:** trusted publishing is GA on the free tier —
  no paid-gate precondition.

## Architecture Decision (ADR/C4)

- **ADR:** create `ADR-309-npm-publish-oidc-trusted-publishing.md` (provisional
  ordinal — highest on main is ADR-308; re-verify next-free at ship time per
  the collision rule). One-line decision: CI publishes `@soleur/opencode` via
  npm OIDC trusted publishing bound to `jikig-ai/soleur` + `npm-publish.yml`;
  no long-lived npm credential exists in CI (`NPM_TOKEN` retired after the
  first green publish). Status `adopting`; flips to `accepted` when AC-8's
  green publish is observed — recorded in the ADR body, not deferred.
- **C4 views:** read `model.c4`/`views.c4`/`spec.c4` in full. Enumeration for
  this feature: (a) external human actors — OpenCode end users installing via
  `npx` are not modeled today (the OpenCode harness element itself is a
  recorded `DRIFT (2026-10-25)` gap assigned to a later change; the
  consumer-side install edge waits on it and is noted in the edge
  description); (b) external system — `registry.npmjs.org` is an unmodeled
  vendor the CI publishes to on every release: add `npmRegistry = system "npm
  registry (npmjs.org)"` `#external`; (c) containers/data-stores — none; (d)
  access relationship — add `github -> npmRegistry` describing the OIDC
  publish channel; include `npmRegistry` in the `context` and `containers`
  view include lists so the edge renders; regenerate `model.likec4.json` and
  run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- **Sequencing:** ADR authored in THIS PR describing the target state with
  `status: adopting`; no follow-up issue.

## Encryption Posture

No new persistent store and no new cross-component connection — the publish
edge to registry.npmjs.org exists already (HTTPS, cert verification on); only
its authentication mechanism changes (long-lived bearer token -> OIDC
exchange). Section skipped per Phase 2.11 detection.

## Guard Contract

### Guard 1 — npm-publish OIDC wiring pin (`plugins/soleur/test/npm-publish-oidc.test.sh`)

**Property.** The `publish` job of `.github/workflows/npm-publish.yml` always
carries `id-token: write` and never reintroduces a long-lived npm credential
(`NODE_AUTH_TOKEN` / `_authToken` wiring).

**Assembly.** The parsed YAML of `jobs.publish` — the `permissions` map, every
step's `env` map, and the ordered `run` bodies. `jobs.publish` is the sole
publish chokepoint (the file has one job); assertions read parsed fields via
`yaml.safe_load` so comments and dead text cannot satisfy them
(`cq-assert-anchor-not-bare-token` convention).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `id-token: write` from the job `permissions:` | RED |
| 2 | Re-add `NODE_AUTH_TOKEN` (or any `*_AUTH_TOKEN`/`_authToken` reference) to the publish step `env:` | RED |
| 3 | Point the test at a job name the file lacks (`jobs.release`) so it asserts "0 publish jobs checked" | RED — vacuous dispatch must fail |
| 4 | Delete the `npm install -g npm@^11` freshness step while keeping OIDC wiring | RED — the CLI floor is an independent second member |
| 5 | Feed the suite a file whose `jobs.publish` parses to a non-map (harness input corruption) | RED — never a silent pass |
| 6 | Keep `id-token: write` but add an unrelated permission (`issues: read`) | PASS — the guard must not reject a compliant superset |

**Anchor.** Same-repo comparison only; no external stored value. The pin lives
in `plugins/soleur/test/` where `test-all.sh` registers it — a diff that edits
both the workflow and the guard is the standard PR-review surface, not a
stored-hash bypass.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "The `npm Publish` workflow fails on every merge to main (5+ consecutive failures…)" [issue #11585 — declarative problem statement] | FR-1/Phase 1 + AC-8 green-publish verification | mapped |
| 2 | "claim the `@soleur` scope + grant the publish token access" [issue #11585, Suggested fix arm 1] | Phase 1 OIDC wiring + Phase 3 `npm trust github` step | mapped — the scope half is moot (already owned); the grant-access half is served by the trust entry |
| 3 | "repoint the publish step at the intended registry" [issue #11585, Suggested fix arm 2] | — | descoped — justification: registry.npmjs.org IS the intended registry; GitHub Packages requires auth on public installs and would break `npx @soleur/opencode install` (ruling T1) |
| 4 | "remove the leg if npm delivery isn't a real channel" [issue #11585, Suggested fix arm 3] | — | descoped — justification: npm delivery IS a real channel (documented `npx` install path, ~60 published versions); removal is a scope decision larger than the bug (ruling T1) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `.github/workflows/npm-publish.yml` OIDC edits | "grant the publish token access" | asked |
| `npm-publish-oidc.test.sh` wiring guard | — | inferred — justification: an auth-wiring revert re-deads the leg silently until the next release; the pin makes the contract PR-visible |
| ADR-309 decision record | — | inferred — justification: token→OIDC is a credential-boundary change; plan Phase 2.10 requires the ADR as a deliverable of this plan |
| `model.c4`/`views.c4`/`model.likec4.json` edits | — | inferred — justification: C4 completeness mandate — `registry.npmjs.org` is an external system the feature touches and the model carries zero npm elements |
| Operator `npm trust github` step | "grant the publish token access" | asked — the npm-side half of the same grant ask |

### Split Assessment

- Subsystems touched: 3 — `.github`, `plugins`, `knowledge-base`
- Planned files: 6 | Estimated changed lines: ~220
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed (inline — no Task tool on this harness; CTO Rule
interface applied against `agents/engineering/cto.md`)
**Assessment:** The failure is a publish-authentication fault npm masks as
E404. The mechanism fork (claim scope / repoint / remove / fix auth) was ruled
in `decision-challenges.md` T1: OIDC trusted publishing. Risks flagged:
`.npmrc` token-line cleanup (npm/cli#8976 masked-error class), npm CLI >=
11.5.1 floor (Node 22 bundles 10.x), trust-entry exactness (repo + workflow
filename, no environment). One capability gap noted: a dead-leg early-warning
monitor exists nowhere — recorded on the Cut List, not expanded.

### Operations

**Status:** reviewed (inline)
**Assessment:** Credential-lifecycle toil is the operational surface here —
OIDC retires a manually-provisioned, expiring vendor secret with zero
recurring cost. The one operator step (`npm trust github`, ~1 min, npm >=
11.15.0 + 2FA + maintainer login) is the unavoidable third-party act; no
vendor account, spend, or new service is introduced.

### Product/UX Gate

Tier: none — no user-facing surface; the mechanical UI-surface override does
not fire (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`
in Files to Create/Edit). Marketing assessed not-relevant: no new public claim
or content surface (channel restoration only — the #10723 CMO blind spot does
not apply to a fix that changes no copy). Legal assessed not-relevant:
BUSL-1.1 package already public; OIDC changes auth, not license surface.
Sales/Finance/Support: no overlap.

## Open Code-Review Overlap

None — queried open `code-review` issues against `.github/workflows/npm-publish.yml`,
`npm-publish`, `opencode-plugin`, `model.c4`, `views.c4`, `sync-npm-package`,
and `NPM_TOKEN`: zero body matches.

## Acceptance Criteria

<!-- founder-stated check: n/a — headless pipeline invocation -->

- [ ] AC-1: `jobs.publish.permissions` in `.github/workflows/npm-publish.yml`
  includes `id-token: write`, and the file contains no `NODE_AUTH_TOKEN` or
  `registry-url` token wiring.
- [ ] AC-2: A step installs `npm@^11` before `npm publish`, and `npm --version`
  in the job reports >= 11.5.1.
- [ ] AC-3: `plugins/soleur/test/npm-publish-oidc.test.sh` exists, is registered
  by `scripts/test-all.sh`'s `plugins/soleur/test/*.test.sh` glob, passes, and
  goes RED on each Guard-1 mutation-matrix row.
- [ ] AC-4: `bash scripts/regenerate-c4-model.sh` runs clean after the
  `npmRegistry` element + edge + view includes, and
  `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass.
- [ ] AC-5: `ADR-309-*.md` exists under
  `knowledge-base/engineering/architecture/decisions/` with `status: adopting`
  and an acceptance criterion pointing at the first green OIDC publish.
- [ ] AC-6 (operator): `npm trust list @soleur/opencode` shows a GitHub Actions
  trusted publisher for `jikig-ai/soleur` + `npm-publish.yml`.
- [ ] AC-7: A post-merge `gh workflow run npm-publish.yml` on main exits green
  and `npm view @soleur/opencode version` prints the newest `v*` tag's version.
- [ ] AC-8 (operator, after AC-7): `NPM_TOKEN` repo secret deleted, or a dated
  note left in the PR body deferring deletion — the workflow must not read it
  either way.

## Test Scenarios

- `unit` — Given the current workflow YAML, when the guard parses
  `jobs.publish`, then `id-token: write` is present in `permissions` and no
  step `env` references `NODE_AUTH_TOKEN` or writes `_authToken`.
- `unit` — Given the mutation matrix, when each listed edit is applied to a
  copy of the workflow, then the guard reports the expected RED/PASS.
- `unit` — Given `scripts/test-all.sh`'s registration globs, when the new test
  file lands under `plugins/soleur/test/`, then it appears in the runner's
  discovered set (no registration edit needed).
- `integration` — Given the merged workflow, when `gh workflow run
  npm-publish.yml` fires on main after the trust entry exists, then the run
  concludes `success` (exercises checkout -> sync -> version resolve -> OIDC
  exchange -> publish).
- `e2e` — `pyramid-justified: verifies the external registry end-state no lower
  layer can reach` — Given the green publish run, when
  `curl -s https://registry.npmjs.org/@soleur%2fopencode | jq -r '.["dist-tags"].latest'`
  runs, then it equals the newest `v*` git tag's version.
- `unit` — Regression: given the pre-fix workflow shape (token auth present,
  `id-token` absent), when Guard 1 runs against a fixture copy, then it
  reports RED — proving the suite would have caught the reversion.

## Success Metrics

- `npm Publish` run conclusion `success` on the next merge-to-main release.
- `dist-tags.latest` on npmjs.org equals the newest release tag within minutes
  of each release.
- Zero long-lived npm credentials in repo secrets after the cleanup AC.

## Dependencies & Risks

- **Operator availability** for the `npm trust github` step (AC-6) — the only
  blocking external dependency; the PR can merge first and the leg stays red
  until the entry exists, which is fail-safe.
- **Trust-entry exactness:** repo must be `jikig-ai/soleur`, filename
  `npm-publish.yml`, environment unset — a mismatch reproduces the same E404
  shape; AC-6/AC-7 verify.
- **`npm@^11` install** adds ~10-15 s per run and floats in-major; accepted
  for determinism over relying on the runner's bundled npm (the Node-24
  alternative couples the floor to image drift).
- **Provenance note:** OIDC publishes attach provenance attestations
  automatically; public repo so no private-repo restriction applies.
- **Pre-existing, out of scope:** `Node.js 20 is deprecated` annotations on
  `actions/checkout`/`setup-node`/`setup-bun` pins — flagged for a separate
  bump pass, not this fix.

## References & Research

- Issue: #11585; feature PR that introduced the leg: #10723; SIGPIPE fixes:
  #10927, #10930.
- Files: `.github/workflows/npm-publish.yml`,
  `packages/opencode-plugin/package.json`,
  `plugins/soleur/scripts/sync-npm-package.ts`,
  `.github/workflows/reusable-release.yml` (OIDC precedent),
  `plugins/soleur/test/token-drift-workflow-causes.test.sh` (YAML-parse
  assertion convention).
- npm docs: `https://docs.npmjs.com/trusted-publishers/`,
  `https://docs.npmjs.com/cli/v11/commands/npm-trust`; GitHub changelog:
  npm trusted publishing GA (2025-07-31); masked-E404 auth class:
  `https://github.com/npm/cli/issues/8976`.
- Learnings: `2026-10-23-committing-generated-npm-payload-…`,
  `2026-05-04-schedule-once-template-missing-id-token.md`.
- Rulings: `knowledge-base/project/specs/feat-one-shot-11585-npm-publish-e404/decision-challenges.md`
  rows T1, T1a, T2.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).
