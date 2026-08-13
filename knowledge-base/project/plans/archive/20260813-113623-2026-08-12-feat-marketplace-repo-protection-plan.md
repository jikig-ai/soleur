---
title: "Protect jikig-ai/soleur-marketplace — ruleset, Terraform-owned manifest, reconcile trigger"
date: 2026-08-12
slug: feat-marketplace-repo-protection
branch: feat-marketplace-repo-protection
issue: 7493
closes: 7493
lane: cross-domain
type: feat
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan_revision: v2 (post six-reviewer panel + live bypass probe)
---

# Plan: Protect the marketplace repo

## Overview

`jikig-ai/soleur-marketplace` is the plugin's sole distribution channel and carries **zero**
rulesets, no branch protection, and one collaborator — verified live 2026-08-12. ADR-182 recorded
two controls as deferred-not-rejected; both deferral blockers are resolved against the live API.

Three arms:

- **A — a branch ruleset** requiring a PR *with one approval* on the default branch, plus deletion
  and force-push restrictions.
- **B — Terraform owns the manifest contents** via `github_repository_file`, sourced from a file in
  this monorepo under the CODEOWNERS-pinned `/infra/github/` path, **gated by a pre-merge CI check
  on that source file**.
- **C — a reconcile trigger**: the daily drift workflow dispatches the apply workflow after filing
  its evidence.

**v2 supersedes v1 after a six-reviewer panel and a live bypass probe.** v1 shipped a ruleset that
did not close the path it claimed to close, a verifier that read a CDN inside its own cache window,
and a reconcile loop that would have republished bad content daily while reporting green. Those are
corrected below; §Panel Corrections records what changed and why.

## Research Insights

### Premise Validation

| Premise | Verdict | Evidence |
|---|---|---|
| App has permission for a ruleset | ✅ | `soleur-ai`: `administration: write`, `repository_selection: all` |
| App has `contents: write` on the marketplace repo | ✅ | same App, org-wide |
| A ruleset would lock the sole maintainer out | ⚠️ **depends on `bypass_mode`** — see the probe below | measured, not reasoned |
| "Drift is auto-reconciled by the next apply" | ❌ **FALSE** | `apply-github-infra.yml` has no `schedule:`; triggers are `push: main` on `infra/github/*.tf`, `.terraform.lock.hcl`, `tests/scripts/lib/destroy-guard-filter.jq`, plus `workflow_dispatch` |
| #7471 is a PR | ❌ closed **issue** | `gh pr view 7471` → not a PR |

**Provider facts, resolved empirically at 6.12.1** (locked in `.terraform.lock.hcl`; Terraform
1.10.5 locally matches the workflow):

- `github_repository_file.overwrite_on_create`: `optional`, `computed=false`, **no schema default**.
- Create path at v6.12.1 (`github/resource_github_repository_file.go`): GETs first, and with
  `overwrite_on_create` true sets `opts.SHA = fileContent.SHA` before writing. **An existing
  byte-identical file takes an update-shaped path, not a 409.** No import needed.
- `github_repository_ruleset`: `repository` required; `rules` `min_items: 1, max_items: 1`;
  `deletion` / `non_fast_forward` are rules-level optional bools; `bypass_actors.actor_id` optional.
- `rules.pull_request.required_approving_review_count` is optional with **no default → 0**. This is
  the Optional-no-default class `repository-marketplace.tf` flags for bools, and it is the defect
  v1 shipped on an int.
- **`terraform validate` passes** on the proposed HCL.

### The three App write paths, enumerated in full

v1 enumerated only the `contents` column and built arm A's justification on it. Full set:

| App | `contents` | `pull_requests` | `administration` | `repository_selection` |
|---|---|---|---|---|
| `soleur-ai` (App 3261325) | write | write | **write** | all |
| `claude` | write | **write** | — | all |
| `entire` | write | **write** | read | all |

`pull_requests: write` is the column that decides whether arm A works. With
`required_approving_review_count = 0` and no CODEOWNERS in that repo, `claude` and `entire` can
branch → PR → self-merge. **A PR requirement alone is not a control here.**

### Live bypass probe (2026-08-12)

The lockout risk ADR-182 deferred on was settled by measurement, on the disposable
`jikig-ai/test-new-project` (zero code references), with the ruleset and all artifacts removed
afterward.

| Config | Founder merge | Founder direct-push | `claude` / `entire` |
|---|---|---|---|
| `count = 0` | ✅ | ❌ | ✅ **self-merge — v1's defect** |
| `count = 1`, human bypass `pull_request` | ❌ `REVIEW_REQUIRED`, *"base branch policy prohibits the merge"*; needs `--admin` | ❌ | ❌ |
| `count = 1`, human bypass **`always`** | ✅ | ✅ | ❌ |

`bypass_mode = "pull_request"` does **not** permit merging a PR that fails the approval rule — the
observed failure is a hard block with an `--admin` escape. `bypass_mode = "always"` restores full
access including direct push.

**Chosen: `count = 1` with human bypass actors at `always`.** It is the only configuration that
both closes the App path and preserves spec G5. It deviates from the sibling rulesets' `pull_request`
mode; that deviation is deliberate and must be commented in the `.tf`.

**Honest strength claim** (this replaces v1's overclaim): the ruleset raises the bar from *one App
acting alone* to *two Apps colluding* (`claude` opens, `entire` approves — both hold
`pull_requests: write`, and GitHub blocks self-approval). Neither holds `administration: write`, so
neither can use the `--admin` override. `deletion` and `non_fast_forward` are **unroutable-around**
for any non-bypassing actor and are the part of arm A that is unconditional.

### Property List

- **P1.** No actor outside the declared bypass set can modify the marketplace default branch without
  a PR carrying an approval; the branch cannot be deleted or force-pushed.
- **P2.** The manifest's content is reviewed **and validated** before it publishes.
- **P3.** A drift in the published manifest is corrected within the daily cycle, evidence first.
- **P4.** The unattended apply pipeline completes with A and B both live.
- **P5.** The sole maintainer retains a direct emergency path (spec G5).

### Cut List

| Mechanism | Property | Disposition |
|---|---|---|
| `terraform import` of the manifest file (a third `import_*` helper) | clean adoption | **CUT.** Provider source confirms `overwrite_on_create` handles the existing-file case via SHA. A third import id shape in the highest-blast-radius file is unjustified risk. |
| `terraform import` of the ruleset | adoption | **CUT — N/A.** Zero live rulesets. (`import_ruleset` hardcodes `soleur:$id` and could not express another repo — Sharp Edge for any future adoption.) |
| A `schedule:` on `apply-github-infra.yml` | P3 + ruleset reconcile | **CUT**, but the v1 rationale was wrong — see §Panel Corrections C3. Real reason: it reverts drift *before* the 06:37 check observes it, so the issue is never filed and the only notice of it disappears. Git history in the *other* repo is not a surfaced channel. |
| An allowlist of content finding keys | P3 | **CUT**, replaced by a **prefix denylist** — see FR8. |
| `required_approving_review_count = 0` (v1) | P1 | **CUT.** Measured not to close the App path. |
| Narrowing the `claude`/`entire` installations to selected repos | P1, directly | **Not cut — deferred to NG6.** It removes the threat rather than gating it, at zero Terraform cost, but it is not IaC-declared, drifts silently, and adds a step per new repo. Recorded so the next reader sees it was priced. |

## Panel Corrections (v1 → v2)

Six reviewers. Every item below is a v1 defect, not a refinement.

| # | v1 defect | v2 |
|---|---|---|
| C1 | Arm A's `pull_request` rule had no parameters → 0 approvals → did not close `claude`/`entire`. The headline justification was false. | `required_approving_review_count = 1`; human bypass at `always`; strength claim rewritten. |
| C2 | Denylist named one key; the workflow emits **two** GET-2 keys (`plugin_manifest_unresolvable` `:215`, `plugin_manifest_unparseable` `:217`). | Prefix denylist `plugin_manifest_` — closed under future GET-2 assertions, which is the whole reason a denylist was chosen. |
| C3 | NG5 justified by "Terraform reverts on the next apply" — contradicting this plan's own Premise Validation two sections earlier. | `scheduled-terraform-drift.yml:47` puts `infra/github` in its matrix and plans it (`workflow_dispatch`, Inngest-driven). Deferral stands; justification replaced. |
| C4 | Guard 1's probe read `GET /rulesets` — the **list** endpoint returns a summary with no `rules`, `bypass_actors`, or `conditions`. Three of four rows were unimplementable. | Two-hop: list → select by name → `GET /rulesets/{id}`. |
| C5 | The bypass comparison ignored the `0`-vs-`null` asymmetry — Terraform writes `0`, the API returns `null`. Would have gone **red on every apply**. | Normalize `0 → null` per the existing SE-1 convention (`ruleset-cla-required.tf:22`); expected set lives in `scripts/marketplace-ruleset-canonical-bypass-actors.json` beside its two siblings. |
| C6 | Published-artifact verifier fetched `raw.githubusercontent.com` inside the apply job. Measured `cache-control: max-age=300`, `source-age: 102`. **Vacuous on the first apply** (passes against the cached old copy) and flaky-red afterward. | Bounded ETag poll with cache-busting, or defer the diff to the next drift tick. |
| C7 | No pre-merge validation of the source file → a bad manifest merges, publishes, and arm C **republishes it daily forever** while Guard 3 reports `MANIFEST_IN_SYNC`. | New Phase 2: the content assertions run against the source file as a required CI check. |
| C8 | The drift **issue body** (`:309`, `:316-321`) — the artifact a non-technical founder reads mid-incident — still says the repo has "no CI, no required review and no CODEOWNERS" and tells them to edit the published file, now blocked and futile. Also the gate-override block `:21-27` and justification **(ii)** "`issues: write` … AND NOTHING ELSE". | All rewritten. v1 caught this class twice (FR12, C4 model) and missed the worst instance. |
| C9 | `liveness_signal` called the Sentry monitor "already wired". The composite declares three `required: true` inputs; the drift workflow passes **none**; Actions does not enforce `required` on composite inputs, so it warns and exits 0. **The check-in has never fired.** AC5 as written *forbade* the fix. | Forward the three secrets (sibling precedent `scheduled-terraform-drift.yml:1258-1260`); reword AC5 and gate-override (iii) — a Sentry ingest URL is not a product secret. |
| C10 | The A↔B "atomicity" framing. `bypass_actors` are attributes of the ruleset resource in the same POST, so **there is no ordering window** and `depends_on` would buy nothing. Not a deadlock either — a wrong bypass leaves a red run recoverable by a normal merge. | Reframed: the mitigation is AC4 + the bypass-set probe, not "one commit". |
| C11 | "Blast radius: the marketplace repo only" — false for arm C, which applies the **whole** `infra/github` root including this repo's merge-gate rulesets, triggered by an unauthenticated third-party URL read. | Stated, with the AP-021 deviation acknowledged. |
| C12 | Guard 2's predicate lived in an Actions `if:`. Expressions have no split/regex/iteration, so `contains()` cannot distinguish a mixed verdict from a GET-2-only one; and the named harness runs only the `check` step's bash, so rows 1–3 were undriveable. | Predicate computed in the `check` step → `dispatch_eligible` output; `if:` is trivial. |
| C13 | Guard 1's property claimed deletion/force-push protection that no assertion covered. | Both asserted; matrix rows added. |
| C14 | AC8 grepped a phrase that is **line-wrapped** in ADR-182 → returns 0 on an unmodified file. Vacuous. | Whitespace-normalized match plus a positive marker the edit introduces. |
| C15 | AC4 forbade the installation id anywhere in the file — blocking the very comment this repo's conventions require (`apply-github-infra.yml:251-262` spends 11 lines on exactly that distinction). | Scoped to the assignment: `actor_id\s*=\s*3261325` present, `actor_id\s*=\s*122413433`-shaped assignment absent. Prose free. |
| C16 | Destroying `github_repository_file` **deletes the published manifest**; there is no `keep_on_destroy`. `archive_on_destroy` protects the repo, not a file in it. `[ack-destroy]` silently upgraded from "remove a ruleset" to "unpublish the plugin". | Stated in Risks and in the FR12 comment. |
| C17 | `[skip-github-apply]` reads the same empty `HEAD_MSG` on dispatch, so the documented **kill switch is also inoperative** on every reconcile — the only brake is the daily cron. | Stated in failure_modes. |
| C18 | AC13 asserted an exact whole-root plan count — shared mutable state, `cq-ac-must-not-depend-on-concurrent-sessions`. | Asserts the two resources' actions, not a root-wide total. |
| C19 | Every pre-merge AC could pass with Phase 4 entirely unimplemented. The repo already documented this shape (`marketplace-drift-check.test.sh:350-354`). | Structural pre-merge ACs for the verifier steps. |
| C20 | AC16/AC17 filed as "automatic" required deliberately breaking production. | Moved to the guard test suite; AC17 was a duplicate of Guard 2.1. |

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Response |
|---|---|---|
| FR6: adopt via the import helpers | Zero live rulesets (pure create); `import_ruleset` hardcodes `soleur:$id`; provider handles the existing file via SHA | FR6 dropped |
| FR8: allowlist of content findings | 12 finding keys; a deleted/corrupt manifest is exactly what Terraform fixes; two GET-2 keys | Prefix denylist `plugin_manifest_` |
| Spec silent on ruleset verification | Post-apply verify is hardcoded to this repo's ruleset 14145388 | FR11 |
| Spec silent on `repository-marketplace.tf`'s comment | Its `OWNERSHIP BOUNDARY` block is falsified | FR12 |
| Spec silent on source-file validation | **Nothing validates the source** — `grep -rln "marketplace.json" .github/workflows/ scripts/ tests/` returns only the drift workflow, which reads the *published* URL | **FR14 (new)** — the C7 fix |
| Spec AC2 "an unprivileged direct push is rejected" | v1 asserted configuration, never behaviour | Now covered by the probe result + Guard 1; behaviour is measured, not asserted |
| Spec TR5 "`[ack-destroy]` exercised against the new resources" | No task in v1 | FR15 — a destroy-guard fixture, now load-bearing because of C16 |
| CODEOWNERS pins a workflow that does not exist | Confirmed: exactly **one** stale row of 59 | FR13, scoped |

## User-Brand Impact

**If this lands broken, the user experiences:** a wedged `apply-github-infra` pipeline; or a
published manifest that silently stops matching the source while checks report green; or — the C16
case — an *unpublished* manifest, breaking `marketplace add` for every new install.

**If this leaks, the user's workflow and credentials are exposed via:** the manifest repoint path.
An unreviewed push changes the plugin source; every installed user's next update materialises
attacker-controlled agent code executing locally with their `ANTHROPIC_API_KEY` and a
`GITHUB_TOKEN` carrying `issues: write`.

**Brand-survival threshold:** `single-user incident`. Carried from the brainstorm.
`requires_cpo_signoff: true`. **The trade-off requiring sign-off** (v1 hid this): after arm B, the
durable route to a manifest change is a monorepo PR + full CI + CODEOWNERS + apply + up to 300 s of
CDN. The founder retains a direct-push emergency path **only because** the human bypass actors are
set to `always` — that is what spec G5 rests on, and it is why the `always` deviation from the
sibling rulesets is not cosmetic.

## Implementation Phases

### Phase 1 — Manifest source of truth

1. Fetch the published manifest verbatim into `infra/github/soleur-marketplace-manifest.json`.
2. Leave `.claude-plugin/marketplace.json` in this monorepo untouched (legacy entry, #7489).

### Phase 2 — Pre-merge source validation (FR14 — the C7 fix)

3. Extract the manifest content assertions (no `version` key; `source.path`; `source.url`;
   `source.source == git-subdir`; no `ref`/`sha`/`commit`/`branch`/`tag` pin; exactly one entry;
   `entry.name == "soleur"`) into a script that runs against a **local file**.
4. Wire it as an always-run required check over `infra/github/soleur-marketplace-manifest.json`.
5. The drift workflow keeps the same assertions against the *published* artifact. They are not
   redundant: this one gates the **source**, that one gates **publication**. Name them individually
   rather than by count — the file's own header says "three" and there are more.

### Phase 3 — Ruleset + file resource (arms A and B)

6. `infra/github/ruleset-marketplace-pr-required.tf`:
   `repository = github_repository.soleur_marketplace.name` (a reference, not a literal — it
   supplies the dependency edge and survives a rename), `target = "branch"`,
   `enforcement = "active"`, `conditions.ref_name.include = ["~DEFAULT_BRANCH"]`.
7. `bypass_actors`: `OrganizationAdmin`/`0`/**`always`**, `RepositoryRole`/`5`/**`always`**,
   `Integration`/**`3261325`**/`always`. Comment the `always` deviation from the siblings and the
   probe result that motivated it, and the App-id-vs-installation-id distinction.
8. One `rules` block: `pull_request` with `required_approving_review_count = 1` (and the four
   remaining sub-fields set explicitly, since none has a default), plus `deletion = true` and
   `non_fast_forward = true`.
9. `github_repository_file.marketplace_manifest` — same `repository` reference,
   `branch = "main"`, `overwrite_on_create = true`, explicit commit metadata.
10. FR12 — rewrite `repository-marketplace.tf`'s `OWNERSHIP BOUNDARY` comment, including the C16
    warning that a destroy now unpublishes the manifest.

### Phase 4 — Publication trigger

11. Add `infra/github/soleur-marketplace-manifest.json` to `on.push.paths`. The `infra/github/*.tf`
    glob does not match a `.json` sibling; without this the manifest never publishes, silently.

### Phase 5 — Verifiers

12. Ruleset probe (C4): list → `select(.name == "Marketplace PR Required") | .id` →
    `GET /rulesets/{id}`. Assert `enforcement == "active"`; the `0→null`-normalized `bypass_actors`
    set equals `scripts/marketplace-ruleset-canonical-bypass-actors.json` (C5); a `.type ==
    "pull_request"` rule with `required_approving_review_count == 1`; `deletion` and
    `non_fast_forward` both present (C13); `conditions.ref_name.include == ["~DEFAULT_BRANCH"]`.
    Fail closed on an empty list or a name miss. Must live **inside** the existing verify step —
    `apply-github-infra.yml:355` traps and shreds the PEM on step exit, so no later step can mint a
    token.
13. Published-artifact verifier (C6): bounded ETag poll with `Cache-Control: no-cache`, ~5 min max,
    then fail. Raw `diff`, not `jq -S` — byte identity is the stated property and is achievable.

### Phase 6 — Reconcile trigger (arm C)

14. `permissions:` gains `actions: write`. Update gate-override justification **(ii)** — it says
    "`issues: write` … AND NOTHING ELSE" (C8).
15. Fix the Sentry heartbeat (C9): forward `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` /
    `SENTRY_PUBLIC_KEY`, and reword gate-override (iii) — these are not product secrets. Add a
    dispatch conjunct to the status expression so a failed dispatch cannot report `ok`.
16. The `check` step computes `dispatch_eligible=true|false` (C12): true iff ≥1 finding key does not
    match the `plugin_manifest_` prefix. Anchored key matching — `manifest_unparseable` is a proper
    substring of `plugin_manifest_unparseable`.
17. Dispatch step after the issue step, `if: steps.check.outcome == 'success' && steps.issue.outputs.delivered == '1' && steps.check.outputs.dispatch_eligible == 'true'`.
    **No `always()` / `!cancelled()`** — the implicit `success()` is load-bearing here and is the
    opposite of the convention two steps above. Use `set -euo pipefail` (not the `set +e` bracket —
    non-zero is a real error here), `GH_TOKEN`, `--ref main`, `--repo`, per
    `inngest-watchdog-restart-dispatch.yml:41-49`.
18. Verify the dispatched run actually started (spec TR2): `gh workflow run` exits 0 on
    *acceptance*. Poll for the run id and append it to the issue comment, linking detection to
    remediation.
19. Rewrite the issue body's stale claim and remediation steps (C8).

### Phase 7 — Guard tests

20. Guard 2 rows in `scripts/marketplace-drift-check.test.sh` (the harness runs the `check` step
    body, which is now where the predicate lives).
21. Guard 1 rows as fixture-driven assertions over recorded ruleset JSON — the live mutations cannot
    be driven in CI, and claiming otherwise is the ceremony the Guard Contract format exists to
    prevent.
22. FR15 — destroy-guard fixture for a `github_repository_file` replacement (delete+create trips
    `resource_deletes`), now load-bearing per C16.

### Phase 8 — Records

23. FR10 — amend ADR-182 (both alternatives shipped, preconditions recorded, the reconciliation
    claim corrected).
24. C4 model: rewrite `soleurMarketplace`'s description and the `github -> soleurMarketplace` edge
    label; add the authenticated **write** edge. `views.c4` already includes the element.
25. `infra/github/README.md`; FR13 CODEOWNERS one-liner; NG5 + NG6 tracking issues.

## Acceptance Criteria

### Pre-merge

- **AC1.** `terraform validate` passes on `infra/github/`.
- **AC2.** The source file is byte-identical to the published manifest at authoring time.
- **AC3.** `infra/github/soleur-marketplace-manifest.json` appears **inside** `on.push.paths` —
  `awk` the block, then grep (not a whole-file grep).
- **AC4.** `grep -cE 'actor_id\s*=\s*3261325'` ≥ 1 and `grep -cE 'actor_id\s*=\s*122213433'` == 0 in
  the ruleset file. Assignment-scoped; prose may explain the distinction (C15).
- **AC5.** `permissions:` gains `actions: write`. The workflow may additionally reference the three
  Sentry ingest secrets (C9) — it must reference no **product** secret.
- **AC6.** Phase 2's source-validation check is wired as an always-run required check, and fails on
  a fixture manifest carrying a `version` key.
- **AC7.** `.claude-plugin/marketplace.json` unmodified.
- **AC8.** ADR-182 amendment verified by whitespace-normalized match plus a positive marker the edit
  introduces (C14).
- **AC9.** `model.c4` no longer asserts "no CI, no review and no CODEOWNERS" as current state; the
  write edge exists; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC10.** `repository-marketplace.tf`'s ownership comment updated, including the C16 warning.
- **AC11.** The FR13 CODEOWNERS row resolves. **Scoped to that row** — not a repo-wide invariant.
- **AC12.** Structural: the ruleset probe and the published-artifact verifier both exist in
  `apply-github-infra.yml`, and the dispatch step exists in the drift workflow with the correct
  `if:` shape and no `always()`/`!cancelled()` (C19).
- **AC13.** `bash scripts/marketplace-drift-check.test.sh` passes, including all Guard 2 rows.
- **AC14.** `bash scripts/test-all.sh` green.

### Post-merge (automatic)

- **AC15.** The merge-triggered apply is green and its plan shows the two new resources as
  **creates with zero destroys** — asserted on those two resource addresses, not a whole-root total
  (C18).
- **AC16.** `GET /rulesets/{id}` returns `enforcement: active`, the three bypass actors
  (`0→null`-normalized), `required_approving_review_count: 1`, and both `deletion` and
  `non_fast_forward`.
- **AC17.** The published-artifact verifier reports byte-identity after its ETag poll settles.

## Guard Contract

### Guard 1 — Marketplace ruleset, and the probe that proves it

**Property.** No actor outside the three declared bypass entries can modify `refs/heads/main` on
`jikig-ai/soleur-marketplace` without a PR carrying one approval, and the branch cannot be deleted
or force-pushed.

**Assembly.** The chokepoint is GitHub's ruleset evaluation for that ref — structural, not a list.
The member set is every actor GitHub authenticates for a write there: org members, collaborators,
and every App installed org-wide with `contents: write` (2026-08-12: `soleur-ai`, `claude`,
`entire`). The red-driving mechanism reads the **live ruleset detail endpoint**, not the `.tf` and
not the list endpoint.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | `enforcement → "disabled"`, or ruleset deleted | RED — **own-dispatch row**: an empty list or name miss must fail, never report 0-checked-OK |
| 2 | A **4th** `bypass_actors` entry after three compliant ones | RED — **second-member row**; only full normalized-set equality catches it |
| 3 | `required_approving_review_count → 0` | RED — this is v1's shipped defect; "a `pull_request` rule exists" passes here |
| 4 | `deletion` or `non_fast_forward` → false | RED (C13) — every other assertion still passes while the property is false |
| 5 | `ref_name.include` → a nonexistent branch | RED — active and intact while quantifying over nothing |

### Guard 2 — The reconcile dispatch predicate

**Property.** A reconcile is dispatched for exactly those verdicts a Terraform apply can fix, and
never for those it cannot.

**Assembly.** The finding-key set emitted by the `check` step — open-ended by design. The chokepoint
is the `dispatch_eligible` computation **inside that step's bash**, which is what the named harness
executes. A `plugin_manifest_` prefix denylist is closed under future GET-2 assertions; matching is
anchored, because `manifest_unparseable` is a proper substring of `plugin_manifest_unparseable`.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Predicate forced true | RED — a GET-2-only verdict must not dispatch |
| 2 | Predicate forced false | RED — `version_key_present` must dispatch |
| 3 | Add a **new** `plugin_manifest_*` key | RED if implemented as a two-key denylist — **second-member row**, and the reason the prefix form is correct |
| 4 | Mixed verdict (`plugin_manifest_unresolvable` **and** `version_key_present`) | RED if it does not dispatch — the case an unanchored `contains()` gets wrong |
| 5 | Decision unobservable | RED — **own-dispatch row**; the suite must fail, not pass vacuously |
| 6 | Dispatch reordered before issue delivery, or given `always()` | RED — evidence must precede remediation |

### Guard 3 — Published-artifact verifier

**Property.** The bytes served at the canonical raw URL equal
`infra/github/soleur-marketplace-manifest.json` at `main`.

**Assembly.** The published artifact as an installer resolves it — **behind a 300 s Fastly cache**,
so the assembly includes the cache, and a single fetch does not observe it. Not Terraform state, not
the provider's `content` attribute.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Published bytes differ from source by any cause (source edited without the `paths:` trigger; `file` repointed; file deleted) | RED — one assertion, several causes; fail-closed on 404 |
| 2 | Verifier reads Terraform state instead of the artifact | RED — **own-dispatch row**; a state check passes while publication failed |
| 3 | Verifier does a single un-busted fetch | RED (C6) — it would pass against the cached copy on the first apply, which is the run it exists for |

### Guard 4 — Source-file validation (new, the C7 fix)

**Property.** A manifest source that violates the delivery contract cannot merge.

**Assembly.** Every path by which `infra/github/soleur-marketplace-manifest.json` reaches `main` —
i.e. the required check on the PR. Terraform publishes whatever merges, so this is the only gate
between an author and every installed user.

**Mutation matrix.**

| # | Mutation | Guard must |
|---|---|---|
| 1 | Source gains a `version` key | RED — the #7471 defect, and the case that would otherwise loop forever |
| 2 | `source.url` / `source.path` / `source.source` changed | RED |
| 3 | A second `plugins[]` entry appended | RED — **second-member row**; positional assertions miss appends |
| 4 | The check is wired non-blocking, or its file list is empty | RED — **own-dispatch row** |

## Infrastructure (IaC)

**Terraform changes.** New: `ruleset-marketplace-pr-required.tf`,
`github_repository_file.marketplace_manifest`, `soleur-marketplace-manifest.json`,
`scripts/marketplace-ruleset-canonical-bypass-actors.json`. Edited: `repository-marketplace.tf`,
`README.md`. Provider `~> 6.10` locked at 6.12.1; no new root, no backend change, no new secrets.

**Apply path.** Merge-triggered, no bootstrap. Both resources are creates.
`repository = github_repository.soleur_marketplace.name` supplies the ordering edge; per C10 there
is no ordering *window* to protect, since bypass actors ship inside the ruleset's own POST.

**Blast radius.** Arm A/B: the marketplace repo. **Arm C: the whole `infra/github` root**, including
this repo's merge-gate rulesets (C11) — the apply has no `-target`. Bounded by the destroy guard,
which fails closed because `HEAD_MSG` is empty on `workflow_dispatch`; note per C17 that the same
emptiness disables `[skip-github-apply]`, so the daily cron is the only brake.

**AP-021 deviation.** Dispatching on `manifest_fetch_failed` acts on an explicitly unmeasured state
(the check's own text: *"no body was read"*). Accepted: the apply is deterministic from `main`'s
`.tf` files and never consumes the fetched body, so a spurious reconcile is a no-op for the file.

## Observability

```yaml
liveness_signal:
  what: scheduled-marketplace-drift daily run + Sentry check-in
  cadence: daily 06:37 UTC
  alert_target: Sentry monitor slug scheduled-marketplace-drift
  configured_in: .github/workflows/scheduled-marketplace-drift.yml
  status: BROKEN ON MAIN — the composite's three required inputs are not forwarded, so the
    check-in has never delivered (C9). Repaired by Phase 6 step 15; until then this signal
    does not exist.

error_reporting:
  destination: GitHub issue labelled ci/marketplace-drift + action-required; Sentry check-in;
    red workflow run
  fail_loud: true

failure_modes:
  - mode: wrong bypass actor -> file write 422, ruleset created, run red
    detection: red merge-triggered run; and scheduled-terraform-drift plans infra/github
    alert_route: red run at merge time (the merger is watching)
  - mode: source edited without the paths trigger
    detection: Guard 3 ETag-polled published diff
    alert_route: red apply run; next daily check reports MISMATCH
  - mode: bad source merges and republishes daily (C7)
    detection: Guard 4 blocks it pre-merge; this mode should be unreachable after Phase 2
    alert_route: required check on the PR
  - mode: dispatch accepted but no run starts
    detection: Phase 6 step 18 run-id poll
    alert_route: ::error:: + job red + Sentry dispatch conjunct
  - mode: dispatched apply fails
    detection: no channel today — see NG7
    alert_route: NG7
  - mode: manifest unpublished by a destroy (C16)
    detection: Guard 3 404 -> fail closed
    alert_route: red run + daily MISMATCH

logs:
  where: GitHub Actions run logs (90 days); Sentry check-ins
  retention: GitHub default

discoverability_test:
  command: >-
    curl -fsS -H 'Cache-Control: no-cache'
    https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json
    > /tmp/pub.json && diff /tmp/pub.json infra/github/soleur-marketplace-manifest.json
    && echo MANIFEST_IN_SYNC
  expected_output: "MANIFEST_IN_SYNC"
```

Raw `diff`, not `jq -S` — byte identity is the property (C6/L1). Cache-busting header included; a
reader running this within 300 s of an apply may still see the cached copy, which is why the CI
verifier polls rather than fetching once.

## Encryption Posture

No persistent store is introduced; the managed artifact is a public manifest.

```yaml
at_rest:
  - store: .claude-plugin/marketplace.json (public repo)
    mechanism: none-required-public-artifact
    evidence: repo visibility public; content is a world-readable plugin pointer
    defends_against: nothing — confidentiality is not a property of this artifact
    does_not_defend: integrity, which is what arms A/B/C supply
    disclosed_as: public distribution manifest
    live_verification: the discoverability_test probe
in_transit:
  - connection: Terraform runner -> api.github.com (contents + rulesets)
    tls: TLS 1.2+; cert_verification: on
    does_not_defend: a compromised App private key — the trust root
    disclosed_as: existing GitHub App auth path
  - connection: drift runner -> api.github.com (workflow dispatch, NEW)
    tls: TLS 1.2+; cert_verification: on
    does_not_defend: >-
      NOT "nothing new" (v1's claim). actions:write permits dispatching ANY workflow in this
      repo, granted to the workflow explicitly designed around untrusted third-party input.
      The dispatch target is a literal and the token is repo-scoped, but the grant is broader
      than the use.
    disclosed_as: internal CI-to-CI dispatch
```

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Wrong bypass id → file write 422 | AC4 + the Guard 1 normalized-set probe. Not a deadlock (C10): red run, recoverable by a normal merge; the rulesets API is not gated by the ruleset. |
| A destroy unpublishes the manifest (C16) | Stated in the FR12 comment and here; FR15 destroy-guard fixture; `[ack-destroy]` is a deliberate one-line act. |
| Bypass comparison false-drifts every apply (C5) | `0→null` normalization per SE-1; canonical JSON beside its siblings. |
| Verifier vacuous behind the CDN (C6) | ETag poll with cache-busting. |
| Bad source republished forever (C7) | Guard 4 blocks it pre-merge. |
| Founder locked out | Measured: human bypass at `always` preserves direct push. The probe is the evidence. |
| Two Apps colluding to approve each other's PR | Residual, stated. `deletion`/`non_fast_forward` unaffected. NG6 removes it entirely if taken. |
| Arm C applies the whole root (C11) | Destroy guard fails closed; deterministic from `main`. |

## Non-Goals

- **NG1.** Retiring the legacy marketplace entry — #7489.
- **NG2.** CI/CODEOWNERS inside `soleur-marketplace` — arm B + Guard 4 make it unnecessary.
- **NG3.** A `schedule:` on the apply workflow — see Cut List.
- **NG4.** Generalising `import_ruleset`.
- **NG5.** Extending `audit-ruleset-bypass.sh` to the marketplace ruleset (337-line script,
  929-line suite, plus the Inngest function). **Justification (C3):**
  `scheduled-terraform-drift.yml:47` already plans `infra/github`, so a widened bypass, a disabled
  ruleset or a deletion surfaces as a plan diff there. Residual is timeliness, and the coupling
  caveat: that workflow is `workflow_dispatch`-only, Inngest-driven — the dependency the drift
  workflow's own gate-override §(i) refuses. **Trigger:** a second Terraform-managed ruleset outside
  `jikig-ai/soleur`, or one observed ruleset drift.
- **NG6.** Narrowing the `claude` / `entire` App installations to selected repositories. Removes the
  threat rather than gating it, at zero Terraform cost; rejected here because it is not IaC-declared,
  drifts silently, and adds a step per new repo. **File as a tracked issue** — it is the only option
  that fully closes the two-App collusion residual.
- **NG7.** An alert channel for a failed `apply-github-infra` run. Today nothing outside the
  workflow notifies; the merge path relies on the merger watching, which does not hold for arm C's
  dispatched runs. **File as a tracked issue**; `hr-observability-as-plan-quality-gate` applies.

## Domain Review

**Domains relevant:** Engineering, Legal, Product — carried from the brainstorm.

### Engineering
**Status:** reviewed. Six-reviewer panel run at plan time; 20 defects corrected (§Panel
Corrections). The bypass semantics that decide arm A's shape were measured on a disposable repo
rather than reasoned about, after two reviewers reached opposite conclusions from the same docs.

### Legal
**Status:** reviewed. No new processing surface, no personal data, no vendor terms.

### Product
**Status:** reviewed. Invisible when it works. The one user-visible failure mode it can introduce is
an unpublished or stale manifest breaking `marketplace add`; C16, Guard 3 and Guard 4 bound it.

### Product/UX Gate
Tier **NONE** — no UI-surface path in Files to Create/Edit.

## Files to Create

- `infra/github/ruleset-marketplace-pr-required.tf`
- `infra/github/soleur-marketplace-manifest.json`
- `scripts/marketplace-ruleset-canonical-bypass-actors.json`
- a source-validation script for Guard 4 (Phase 2)

## Files to Edit

- `infra/github/repository-marketplace.tf` (FR12 + C16)
- `infra/github/README.md`
- `.github/workflows/apply-github-infra.yml` (paths, both verifiers)
- `.github/workflows/scheduled-marketplace-drift.yml` (arm C, heartbeat repair, issue body,
  gate-override (ii)/(iii), predicate output)
- `.github/workflows/ci.yml` (Guard 4 required check)
- `scripts/marketplace-drift-check.test.sh`
- `tests/scripts/test-destroy-guard-counter.sh` + fixture (FR15)
- `knowledge-base/engineering/architecture/decisions/ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `.github/CODEOWNERS`

## Test Scenarios

Every scenario is *mutation → guard reddens*. Guard 1's rows run against recorded ruleset JSON
fixtures; the rest run in the existing harnesses.

1. `enforcement: disabled` → probe fails (G1.1)
2. Empty ruleset list → fail closed, not 0-checked-OK (G1.1)
3. 4th bypass actor → normalized-set equality fails (G1.2)
4. `required_approving_review_count: 0` → probe fails (G1.3 — v1's defect)
5. `deletion`/`non_fast_forward` cleared → probe fails (G1.4)
6. `ref_name.include` bogus → condition assertion fails (G1.5)
7. Bypass fixture with `actor_id: 0` vs API `null` → normalization makes them equal, no false drift (C5)
8. Predicate forced true, GET-2-only verdict → no dispatch expected (G2.1)
9. Predicate forced false, `version_key_present` → dispatch expected (G2.2)
10. New `plugin_manifest_*` key → prefix denylist holds, two-key list fails (G2.3)
11. Mixed verdict → must dispatch; unanchored `contains()` fails (G2.4)
12. Dispatch decision unobservable → suite fails (G2.5)
13. Dispatch given `always()` or moved before issue delivery → fails (G2.6)
14. Published ≠ source by any cause → diff fails, 404 fail-closed (G3.1)
15. Verifier reading state → rejected (G3.2)
16. Single un-busted fetch → passes against cache, must be rejected (G3.3)
17. Source with a `version` key → required check blocks the merge (G4.1)
18. `source.url`/`path`/`source` changed in source → blocked (G4.2)
19. Second `plugins[]` entry appended → blocked (G4.3)
20. Guard 4 wired non-blocking or empty file list → fails (G4.4)
21. `github_repository_file` replacement plan → `resource_deletes` trips the destroy guard (FR15/C16)

## Addendum — 2026-08-13 (#7493 review)

Appended rather than edited in place: the body above is the record of what was planned, and
several of its prescriptions turned out to be wrong or under-specified. Each correction below
names the plan text it supersedes.

**A1 — "bounded ETag poll" (§Implementation step 13, AC17, tasks 5.7, and the C6 row) was never
built, and should not have been prescribed.** The implementation is a cache-busted **body** poll:
`curl -H 'Cache-Control: no-cache' -H 'Pragma: no-cache'` into a temp file, `diff -u` against the
source, `sleep 15`, repeat. There is no `ETag` or `If-None-Match` anywhere in the repo. The
property the plan wanted — do not be satisfied by the CDN's cached copy — is met; the mechanism
named is not the one used. The prescription propagated into `infra/github/README.md` and into the
review brief before anyone read the code.

**A2 — the plan's Guard Contract had no row for the assembly that actually matters.** Every
guard was specified against its own artifact, and each one holds. What none of them covered:
the apply job had no ref guard, so a branch push plus a `workflow_dispatch` published arbitrary
manifest content through the App's own ruleset bypass — no PR, no approval, `marketplace-manifest-guard`
never invoked, and the marketplace repo never touched. The plan's threat model assumed writes
reach the published file *through* the marketplace repo. They do not have to.

**A3 — three guards were satisfiable by implementations that assert nothing**, none of which the
plan's mutation matrix could see, because the matrix specified mutations of the SUT and not of
the harness:
- Guard 4's only must-PASS fixture was the canonical file, and `ci.yml` validates the canonical
  against itself, so `diff "$1" canonical` scored 14/14 and passed CI with the #7471 `version`
  key restored.
- Guard 1's `mutate()` ran inside a command substitution, so a failed `jq` yielded an empty path
  and the RED row passed on the fail-closed branch — 16 of 18 rows green with it fully broken.
- No canonical↔`.tf` lockstep existed, so `required_approving_review_count = 0` plus a fourth
  bypass actor left all five suites green. Both sibling rulesets already had this gate.

**A4 — `~DEFAULT_BRANCH` needed a pinned default branch, which the plan did not identify.**
The ruleset's condition follows whatever the default branch is; nothing declared it. The pivot is
invisible to Guard 1 by construction.

**A5 — deferred, with the trigger stated.** Narrowing `actions: write` off the untrusted-input job
in `scheduled-marketplace-drift.yml` requires relocating `steps.dispatch.outcome`, which the Sentry
status expression reads — and that heartbeat was found in this same PR to have never delivered a
check-in. Re-topologising the plugin's only distribution alarm in the PR that repaired it is the
change most likely to break it unobserved, so it ships separately — tracked in #7520. Trigger: before any second
dispatch is added to that workflow, or on the next change to its permissions block.
