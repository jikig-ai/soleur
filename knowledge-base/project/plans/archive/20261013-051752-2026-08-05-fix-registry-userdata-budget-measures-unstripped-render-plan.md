---
title: "fix: registry-userdata-budget.sh measures a payload Terraform never stores"
type: fix
date: 2026-08-05
branch: feat-one-shot-7299-registry-userdata-over-cap
closes: 7299
lane: cross-domain
brand_survival_threshold: none
---

# fix: `registry-userdata-budget.sh` measures a payload Terraform never stores

## Overview

Issue #7299 reports that the registry host **cannot be re-provisioned** because its rendered
`user_data` is 3,636 B over Hetzner's 32,768 B cap, and proposes recovering ≥3,636 B by
extending `local.registry_rationale_strip`.

**The premise is false, and the proposed fix would be work on a defect that does not exist.**
The strip already exists, is already applied by `zot-registry.tf`, and already recovers ~27 kB.
The real production `user_data` is **9,408 B** — 23,360 B *under* cap. The registry host can be
re-provisioned today.

The actual defect is in the *measurement*: `apps/web-platform/infra/registry-userdata-budget.sh`
renders `templatefile(...)` **raw**, omitting the `replace(..., local.registry_rationale_strip, "")`
that `zot-registry.tf`'s `user_data = base64gzip(replace(templatefile(` applies before `base64gzip`. The script measures a payload that is
never stored on any host.

This plan fixes the measurer, closes the divergence that allowed it, and then re-decides the
issue's Part 2 (gate promotion) against the corrected facts.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Premise Validation

Every claim in the issue body was checked against the branch (fresh from `origin/main` @ `6720f2ae0`).

| Issue claim | Reality | Evidence |
|---|---|---|
| Registry `user_data` is 3,636 B over cap | **False for what is stored.** Stored (stripped) render is 9,408 B — **+23,360 B headroom** | measured below |
| "The registry host cannot be re-provisioned" | **Not for this reason.** `user_data` does not block it. See the precision note below | same |
| "hcloud would reject the CREATE after the DESTROY" | True *as a mechanism*, but not reachable — the payload fits | `zot-registry.tf` `user_data =` |
| Fix = extend `registry_rationale_strip` to recover ≥3,636 B | **Wrong target.** The strip exists (`zot-registry.tf` `registry_rationale_strip =`) and already recovers ~27,000 B | `zot-registry.tf` `registry_rationale_strip =` / `user_data =` |
| `registry-userdata-budget.sh` exits 1 | **True** — it is the *only* true claim, and it is a measurement bug | reproduced, EXIT=1 |
| Budget check is ADVISORY, "did not block the breaking merge" | Script is advisory (`continue-on-error: true`), but **there was no breaking merge** — the correct measurer is required and was green throughout | see below |
| `Infra Validation` has not run on `main` | True — it is `pull_request:`-only (`infra-validation.yml` `on: pull_request:`) | verified |

### Precision note — do not replace one false claim with another

"The registry host can be re-provisioned" is true **with respect to `user_data`**, which is the
claim #7299 makes and the only one this plan adjudicates. A *separate*, already-tracked constraint
does bear on registry re-provisioning: `model.c4` records that `soleur-registry` runs on
`cx23`, and the 2026-07-26 live stock probe found the entire `cx` and `cax` lines orderable in 0
of 3 EU DCs — so the host "runs fine but cannot be rebuilt on its current type" (#6460). The
registry-host-replace apply is tracked by #7287 and blocked on #7277/#7278/#6929 **plus Hetzner
stock** — never on a `user_data` breach.

That distinction matters for the incident framing in the issue: had an operator reached for
"re-provision the registry host" during the open zot crash-loop deploy block, the budget would not
have been what stopped them. This plan removes a false blocker from the record; it does not claim
the replace path is unobstructed.

### The measurement, both ways

Rendered offline with the script's own stub variable map and terraform's own `base64gzip`:

| render | raw | stored (`base64gzip`) | vs 32,768 B cap |
|---|---|---|---|
| unstripped — what `registry-userdata-budget.sh` measures | 74,682 B | 36,404 B | **−3,636 B** ❌ |
| stripped — what `zot-registry.tf` actually stores | 23,958 B | **9,408 B** | **+23,360 B** ✅ |

### Corroboration: a second, independent, *required* measurer is green

`plugins/soleur/test/cloud-init-user-data-size.test.ts` carries a full registry arm (#7278) that
**extracts** the strip expression from `zot-registry.tf` rather than restating it, asserts the strip
is applied inside the `hcloud_server.registry` block, and measures the stripped render. Its own
header comment states the strip takes the render "to ~9 KB" — matching the 9,408 B measured above.

- `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → **38 pass, 0 fail**.
- That test runs via `scripts/test-all.sh bun` → `bun test plugins/soleur/` (`test-all.sh` `run_suite "plugins/soleur"`).
- `test` **is** a required status check (`ruleset-ci-required.tf` `context = "test"`, live-verified
  against ruleset `14145388`).

So the registry `user_data` budget has been guarded by a **required, green, correct** check the
whole time. Nothing broke; nothing merged through a hole.

### Why the script is wrong, and why it shipped that way

`registry-userdata-budget.sh` was added by **PR #7283** (closing issue #7282) and landed in `6720f2ae0`. Its header claims:

> "Render `cloud-init-registry.yml` **exactly as `zot-registry.tf` does**, and measure the STORED
> user_data the way Hetzner measures it."

Both halves are false as written — `zot-registry.tf` strips, the script does not.

This was not an oversight in the dark. `infra-validation.yml`'s own job comment said it explicitly:

> "It cannot be a hard gate YET. The check is RED on `main` today (-2,032 B) and on this branch
> (~-3.6 kB), all of it rationale prose. **#7280's `local.registry_rationale_strip` strips comments
> BEFORE render and brings it to ~9.4 kB.**"

The author knew the strip was the resolution and shipped the job `continue-on-error: true` pending
#7280. **#7280 has since merged** (`d0295964f`) — the strip is live. The script was simply never
updated to apply it, so its advisory job has been reporting a phantom breach ever since.

`main` reading moved −2,032 B → −3,636 B when #7283 lengthened the pin, exactly as an unstripped
measurement would.

### The structural cause: a "ONE COPY" invariant that silently became false

`zot-registry.tf`'s strip rationale block asserted:

> "**ONE COPY.** `plugins/soleur/test/cloud-init-user-data-size.test.ts` EXTRACTS this expression
> from this file rather than restating it… git-data needed a dedicated parity suite to keep its two
> copies equal; **there is nothing here to keep equal.**"

That was true when written. PR #7283 added a *second* consumer of the render — the shell script —
which neither extracted the expression nor applied it. The invariant the comment relies on was
falsified by a later PR, and no control existed to notice: the git-data host has
`git-data-render-strip-parity.test.sh` for exactly this class; the registry host has no
`registry-render-strip-parity.test.sh`.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality | Plan response |
|---|---|---|
| Recover ≥3,636 B via `registry_rationale_strip` | Strip exists and already recovers ~27,000 B | **Drop.** No bytes need recovering. Fix the measurer instead |
| "Leave meaningful headroom, not +10 B" | Real headroom is +23,360 B (71% of cap free) | Satisfied already; AC asserts a floor to keep it true |
| Registry re-provision is blocked | It is not | Correct the record in the PR body and on the issue |
| Promote check advisory → required | The *correct* measurer is already required | **Descoped** — a required check on a paths-filtered workflow never reports on unrelated PRs. See Phase 3 and #7302 |
| `Infra Validation` should run on `main` push | True gap, but not the cause here | Adopt — for merge-skew, not for this bug |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — but a wrong
`registry-userdata-budget` reading is load-bearing on operator judgment during an incident. The
issue already caused a real cost: it recommended re-provisioning be treated as unavailable during
the open zot mirror crash-loop deploy block, which would have removed a genuinely-working recovery
move from consideration at the worst moment.

**If this leaks, the user's data/workflow/money is exposed via:** no exposure vector. The script
renders with stub credentials into a scratch dir, touches no state, and ships to no host.

- **Brand-survival threshold:** `none` — a CI measurement tool with no runtime, no persistence
  and no user-reachable surface. `threshold: none, reason: the change is confined to a local CI
  measurement script, a comment correction, and CI gate wiring; no product code, no data path, and
  no host payload changes.`

## Implementation Phases

### Phase 1 — Make the measurer measure what Terraform stores

Files: `apps/web-platform/infra/registry-userdata-budget.sh`

1. Extract `registry_rationale_strip` from `zot-registry.tf` — **never restate it**. Mirror the
   anchored-assignment parse the script already uses for `ZOT_IMAGE` and that the TS test uses for
   this same expression. Fail closed (`exit 2`) when the expression is absent, matches more than
   once, or is not a slash-delimited `(?m)`-anchored terraform regex literal.
2. Emit the extracted expression into the scratch `locals` block and wrap the render:
   `stripped = replace(local.rendered, local.registry_rationale_strip, "")`, then
   `stored = base64gzip(local.stripped)`.
3. Report **both** figures so a future reader can see the strip working rather than inferring it:
   raw rendered, stripped rendered, stored, cap, headroom. Extend the `--json` object with the
   stripped figure (additive — existing keys keep their meaning).
4. Correct the two false header claims (lines 3-4 and 21-26) to state that the render mirrors
   `zot-registry.tf` *including* the strip, and that the strip is extracted, not copied.

Expected result: `EXIT=0`, headroom `+23,360 B`.

### Phase 2 — Restore the "ONE COPY" invariant as an enforced fact

Files: `apps/web-platform/infra/zot-registry.tf`

The comment at `:383-386` is now false. Phase 1 makes it true again (the script extracts rather
than restates), so the correction is to **name the second extractor** rather than to weaken the
claim:

- Update the block to name both extractors — the TS test and `registry-userdata-budget.sh` — and
  keep the "nothing to keep equal" reasoning, which survives *because* both extract.
- Add the one-line reason the invariant is fragile: a future consumer that *restates* the
  expression re-opens exactly this defect.

**Decision: no `registry-render-strip-parity.test.sh`.** git-data needs a parity suite because it
genuinely has two *copies* (`modules/git-data-userdata/main.tf:49` and
`git-data-userdata-budget.sh:52`). After Phase 1 the registry has one declaration and two
extractors, so there is nothing to keep equal — a parity test would assert a tautology. The
enforcing control is instead the extractor's own fail-closed parse (Phase 1 step 1), which is
strictly stronger: it fails when the expression is missing or malformed, which a copy-comparator
cannot do.

### Phase 3 — Un-red the job; promotion to *required* is BLOCKED (the issue's Part 2, re-decided)

Files: `.github/workflows/infra-validation.yml`

**[Updated 2026-08-05 — descoped during implementation. The blast-radius assessment this phase
mandated is what descoped it; recording the finding rather than the original intent.]**

What was found:

- **No `infra-validation` job is a required check** — not even `infra-validate-required`, despite
  the name. Live ruleset `14145388` carries 21 contexts, none from this workflow.
- A required check must report a conclusion on **every** PR. `infra-validation.yml` is
  `paths:`-filtered, so on a docs-only PR **the workflow never triggers at all** and the context
  never reports — GitHub then holds the PR in `Expected` indefinitely. An `if: always()` job-level
  gate does **not** fix this: it only helps when the workflow runs. Requiring this context would
  deadlock every non-infra PR in the repo.
- The working pattern is `tenant-integration.yml`: **no** paths filter + `merge_group:` + an
  always-run aggregator (`tenant-integration-required`). Adopting it here means dropping this
  workflow's paths filter — which this workflow's own comment rejects as putting "an 8-minute
  docker build on every docs-only PR", **already tracked as #6480**.

Therefore, in this PR:

1. Remove `continue-on-error: true` from the `registry-userdata-budget` job. Its stated
   precondition ("gated on #7280 merging") is satisfied, and the check is now correct — so it
   fails the run for real instead of reporting a permanently-red status readers learned to skip.
2. Register the new drift-guard suite as a step in the same job.
3. Correct the stale rationale comment, which asserts a live breach that does not exist, and
   record why promotion is gated on #6480 rather than declined.
4. **Do NOT** touch `infra/github/ruleset-ci-required.tf`. Promotion is a separate work-stream
   blocked on #6480 — filed as a follow-up rather than forced here.

**Why descoping is the right call and not a narrowing of the ask.** The issue's premise for
promotion was "advisory, so it did not block the breaking merge". There was no breaking merge:
the budget has been guarded the whole time by the **required** `test` context via
`cloud-init-user-data-size.test.ts`, which extracts the same strip and has been green throughout.
Promotion is defense-in-depth on an already-required guard, and buying it costs a repo-wide CI
change with a merge-deadlock failure mode. Un-redding the check captures nearly all the value at
none of that risk.

### Phase 4 — Run `Infra Validation` on pushes to `main` (the issue's Part 2b)

Files: `.github/workflows/infra-validation.yml`

Adopt, with corrected reasoning. With Phase 3 in place a broken budget cannot merge through the
PR gate, so this is **not** the fix for #7299. It is worth doing for the case the PR gate
structurally cannot catch: two PRs each individually green whose *merge order* produces a state
neither one tested (precisely how #7283's pin bump interacted with an already-drifting
measurement), plus admin-bypass merges.

- Add a `push:` trigger on `main` with the same `paths:` set as the existing `pull_request:` block.
- Keep the path filter — an unfiltered `push:` puts the full infra matrix on every merge.
- The `plan` job must stay PR-only or remain credential-gated; do not widen anything that needs
  `prd_terraform` on a push event.

### Phase 5 — Correct the record

- PR body states the premise correction plainly: the registry was never un-reprovisionable.
- `Closes #7299` — the issue is genuinely resolved, just not by the route it proposed.
- Post a comment on #7299 recording the measured figures, so the "cannot be re-provisioned"
  claim is not left standing in the issue history for a future operator to find during an incident.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash apps/web-platform/infra/registry-userdata-budget.sh` exits **0**, and prints headroom
   ≥ 20,000 B. (Verified against the real script — not a re-derivation.)
2. The script's stored-byte figure equals the TS test's registry figure within 2%; both describe
   the same stripped render.
3. The strip is **extracted, never restated**. Two literal commands, because the naive one is
   wrong — it counts 2, since the script legitimately emits `registry_rationale_strip =
   ${STRIP_EXPR}` (a shell *reference*, which is the opposite of a restatement):

   ```bash
   # (a) exactly one real declaration, and it lives in a .tf:
   git grep -cE '^[[:space:]]*registry_rationale_strip[[:space:]]*=' -- \
     'apps/web-platform/infra/*.tf' | wc -l            # == 1  (zot-registry.tf)

   # (b) the script carries no slash-delimited copy of the regex body:
   grep -cE '"/\(\?m\)' apps/web-platform/infra/registry-userdata-budget.sh   # == 0
   ```

   Together these are the invariant: one declaration, and every consumer reaches it by reference.
4. Fail-closed proof: with `registry_rationale_strip` temporarily removed from a scratch copy of
   `zot-registry.tf`, the script exits **2** (not 0, not 1) with a named diagnostic.
5. `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → 38 pass, 0 fail (unchanged —
   this plan must not perturb the existing correct measurer).
6. `bash scripts/test-all.sh` is green (full suite; catches orphan infra suites).
7. `actionlint .github/workflows/infra-validation.yml` is clean, and every edited `run:` snippet
   parses under `bash -c`.
8. `terraform fmt -check apps/web-platform/infra/zot-registry.tf` is clean. *(Was "clean for
   `infra/github/`" — retargeted when Phase 3 descoped the ruleset edit; `infra/github/` is no
   longer touched, so asserting on it would be vacuous.)*
9. `infra/github/ruleset-ci-required.tf` is **unchanged** — the required-context set is not
   widened in this PR (see Phase 3). Verified by the file's absence from the diff.
10. No `continue-on-error:` remains on the `registry-userdata-budget` job.
11. `zot-registry.tf`'s strip comment names both extractors and contains no claim that is false
    at HEAD.
12. The new suite is discovered by the CI-registered infra runner:
    `grep -oE 'run: bash apps/web-platform/infra/[A-Za-z0-9._-]+\.test\.sh' .github/workflows/infra-validation.yml`
    includes `registry-userdata-budget.test.sh` (an unregistered infra suite never gates).

### Post-merge (automated)

13. `Infra Validation` appears in the workflow-run list for the merge commit — proving Phase 4's
    `push:` trigger fires and that `detect-changes` resolved a non-empty matrix on a push event
    (an empty one would be the silent-green failure Phase 4 exists to avoid). Self-verified via
    `gh run list --commit <sha>` + the run's `detect-changes` output. No operator step.

## Observability

```yaml
liveness_signal:
  what: registry-userdata-budget job conclusion on every infra PR and every main push
  cadence: per-PR + per-merge (post Phase 4)
  alert_target: PR path — GitHub check failure on the PR (NOT a required check, see Phase 3).
                main path — notify-main-failure job emails ops via notify-ops-email.
  configured_in: .github/workflows/infra-validation.yml
  note: the main path had NO consumer as first drafted. Verified at review: no workflow_run
        watcher names Infra Validation, no Slack/Discord hook, and GitHub's built-in
        failed-run email routes to the pushing actor — "frequently a GitHub App identity,
        i.e. nobody" (reusable-release.yml). A main-branch run nothing reads would have
        reproduced this PR's own defect one layer up, so the route is wired here rather
        than deferred.
error_reporting:
  destination: GitHub Actions job log + required-check status
  fail_loud: true — exit 2 on unmeasurable template or unextractable strip; exit 1 over cap.
             Never exits 0 on an unmeasurable render (existing fail-closed behavior retained).
failure_modes:
  - mode: strip expression removed or renamed in zot-registry.tf
    detection: script exit 2, named diagnostic
    alert_route: required check fails, merge blocked
  - mode: strip declared more than once (a copy reintroduced)
    detection: extractor asserts exactly-one assignment, exit 2
    alert_route: required check fails, merge blocked
  - mode: render genuinely grows past cap
    detection: script exit 1 with byte overage
    alert_route: required check fails, merge blocked
  - mode: budget regression merged via admin bypass or merge-skew
    detection: Phase 4 push-on-main run
    alert_route: failed workflow run on main
logs:
  where: GitHub Actions run logs
  retention: 90 days (repo default)
discoverability_test:
  command: bash apps/web-platform/infra/registry-userdata-budget.sh --json
  expected_output: "cap":32768
  # Matched as a substring of the command's stdout, so it must be a literal the JSON
  # actually contains — not a shape template. The cap is the one figure in that output
  # that is an invariant rather than a measurement, so it does not go stale when the
  # payload changes (measured 2026-08-06: stored 9408 B, headroom 23360 B).
```

No `ssh` anywhere in the verification path.

## Architecture Decision (ADR/C4)

**No new ADR.** The strip mechanism is already recorded (ADR-152, with the registry variant named
at ADR-152:229). This plan makes an existing measurer honor an existing decision and promotes a CI
gate — it neither creates nor reverses an architectural decision. A competent engineer reading the
current ADR corpus would not be misled about the system after this ships.

**C4 impact: one edge description, on the `github -> resend` edge.**

**[Corrected 2026-08-06 — this section read "No C4 impact" and was falsified by a fix added during
review.]** The original enumeration was accurate for the plan as written: (a) **external human
actors** — none; (b) **external systems/vendors** — none, Hetzner and GHCR already modeled and
untouched at runtime; (c) **containers/data stores** — none, the script uses a `mktemp -d` scratch
dir it deletes on trap; (d) **actor↔surface access relationships** — none.

Then review found the new push-on-main trigger had no consumer, and the fix added a
`notify-main-failure` job using `notify-ops-email`. That makes `infra-validation.yml` the **twelfth**
Resend emitter under `.github/`, where `model.c4`'s `github -> resend` edge says "one of eleven".
`plugins/soleur/test/c4-count-parity.test.sh` caught it — the derivation
(`grep -rlE 'api[.]resend[.]com|notify-ops-email' .github/workflows/ .github/actions/`) returned 12.
Verified mine: `git show origin/main:.github/workflows/infra-validation.yml` has zero emitter refs.

Corrected the clause to "twelve", naming the new emitter and why it exists, and regenerated
`model.likec4.json`. Worth recording as its own instance of this PR's thesis: a claim that was true
when written, falsified by a later change, caught only because a gate derived the number instead of
trusting the prose.

## Infrastructure (IaC)

**No IaC change.** `infra/github/ruleset-ci-required.tf` is NOT touched — Phase 3's promotion was
descoped during implementation, and AC9 asserts the file is absent from the diff. No new resource,
provider, secret, variable, host or service; no operator step, no SSH, no dashboard click.
*(This section previously said the ruleset "gains one `required_check` block", which contradicted
AC9 — the plan body was not swept when Phase 3 changed.)*

## Encryption Posture

**Skipped** — detection fires on the `.tf` glob, but the gate's own skip condition applies: this
plan introduces no persistent data store and no new cross-component or network connection. The
`zot-registry.tf` edit is comment-only, and no Terraform is modified at all (see Infrastructure).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI tooling and infrastructure-gate change. No user-facing
surface, so the Product/UX gate does not fire (no path in Files to Edit matches the UI-surface
term list or glob superset).

## GDPR / Compliance Gate

**Skipped** — no regulated-data surface. No schema, migration, auth flow, API route or `.sql` file
is touched; no LLM/external-API processing of operator data; brand-survival threshold is `none`;
no cron reads from `learnings/` or `specs/`; no new artifact distribution surface.

## Open Code-Review Overlap

**None.** Queried open `code-review`-labelled issues for each planned path
(`registry-userdata-budget.sh`, `zot-registry.tf`, `infra-validation.yml`,
`ruleset-ci-required.tf`) — zero matches.

## Files to Edit

- `apps/web-platform/infra/registry-userdata-budget.sh` — extract + apply the strip; fail-closed
  parse; report stripped figure; correct false header claims.
- `apps/web-platform/infra/zot-registry.tf` — comment only: name both extractors; the "ONE COPY"
  claim becomes true again.
- `.github/workflows/infra-validation.yml` — drop `continue-on-error`; register the drift-guard in
  `deploy-script-tests`; add `push:` on `main` with `github.event.before` as the diff base; correct
  the stale rationale blocks; re-derive `deploy-script-tests`'s timeout.
- `knowledge-base/engineering/architecture/decisions/ADR-096-*.md` — retract the byte cap as a
  live blocker, including in the rollback procedure.
- `knowledge-base/engineering/architecture/decisions/ADR-152-*.md` — mark the byte-exact-measurement
  gap closed.

*(`if: always()` + internal early-exit was the Phase 3 design; it was dropped with the promotion.
`infra/github/ruleset-ci-required.tf` is deliberately NOT edited — see Phase 3 and AC9.)*

## Files to Create

- `apps/web-platform/infra/registry-userdata-budget.test.sh` — the drift-guard suite (16 checks).
  *(This section said "None" until review; the file was created in Phase 1.)*

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Making a skipped job required deadlocks every docs-only PR | **Avoided by not promoting.** Phase 3 was descoped for exactly this reason; AC9 asserts the ruleset is unchanged. `if: always()` does not solve it — a paths-filtered workflow does not trigger at all on a docs-only PR |
| The gate measures a payload production does not store | The strip must be APPLIED, not merely declared: the script anchors on `user_data = base64gzip(replace(templatefile(` and exits 2 otherwise (review found this fail-open; ADR-152 had already recorded it as measured) |
| The measurement drifts optimistically small | A 4,000 B plausibility floor plus a `#cloud-config`-survives assertion. Every other numeric arm is a ceiling, and the fail-quiet direction is the one that strands the host |
| `push:` on `main` runs credential-needing jobs without `prd_terraform` | Phase 4 keeps `plan` PR-only/credential-gated; path filter retained |
| The extractor's regex drifts from the TS test's | Both parse the same anchored assignment shape; AC3 asserts exactly one assignment repo-wide, so a second copy fails the build rather than drifting silently |
| Stripping is unsafe (eats YAML, breaks `#cloud-config`) | Not re-litigated here — already covered by four green tests in `cloud-init-user-data-size.test.ts` ("removes ONLY comments", "preserves #cloud-config", "`#cloud-config` is the ONLY separator-less comment line"). This plan changes no strip semantics |
| The issue reporter's concern is dismissed wrongly | The one true claim (script exits 1) is fixed; the measurement is published in the PR body and on the issue so the correction is auditable, not asserted |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Extend `registry_rationale_strip` to recover 3,636 B (as the issue proposes) | **Rejected.** There are no bytes to recover; production is 71% under cap. Would have collapsed real rationale prose to fix a phantom breach |
| Delete `registry-userdata-budget.sh` — the TS test already covers it | **Rejected.** The script's terraform-native `base64gzip` is byte-exact where the TS test explicitly is not; that is real, distinct value |
| Add `registry-render-strip-parity.test.sh` mirroring git-data | **Rejected.** After Phase 1 there is one declaration and two extractors — nothing to keep equal. The fail-closed extractor is a strictly stronger control |
| Leave the job advisory | **Rejected.** Its stated precondition (#7280 merging) is satisfied; leaving it advisory keeps a permanently-red status normalised, which is how this defect hid |

## Test Scenarios

1. Run the script on this branch → exit 0, headroom ≥ 20,000 B.
2. Scratch-copy `zot-registry.tf` with the strip assignment deleted → script exits 2 with a named
   diagnostic (not 0, not 1).
3. Scratch-copy with the strip assignment duplicated → script exits 2.
4. Full `scripts/test-all.sh` green.
5. Sandbox-mutate `zot-registry.tf` to unwire `replace(` → script exits 2 (the strip is declared
   but not applied).
6. Sandbox-mutate the strip to `/(?m)^.*\n/` → script exits 2 on the plausibility floor rather
   than reporting maximum headroom.
7. Mutation-prove the suite: understate `stored_bytes`, swap `cap`, revert the strip application,
   and neuter the assertion dispatcher — each must red, against a green control.
   *(Scenario 5 previously asserted the budget job "reports a conclusion rather than skipping",
   which belonged to the descoped `if: always()` design.)*

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above.
- **A budget//measurement script and the Terraform that renders the real payload are two different
  programs.** A script header that says it renders "exactly as `<file>.tf` does" is a *claim to
  verify*, not a contract the code enforces. Diff the render expressions before trusting any
  size measurement — a measurement tool can be wrong in the fail-loud direction and still cost an
  incident's worth of operator judgment.
- **A permanently-red advisory check trains everyone to ignore it.** This job was shipped red on
  purpose with a documented plan to fix it; when the fix landed, nobody re-ran the reasoning. When
  shipping a knowingly-red gate, the un-redding must be an enforced follow-through, not a comment.
- **A "ONE COPY / nothing to keep equal" invariant asserted in a comment is falsifiable by any
  later PR.** `zot-registry.tf` correctly claimed it at the time; #7282 added a second consumer and
  the comment silently became false. If an invariant is load-bearing enough to write down, make the
  consumers *extract* rather than restate, so the invariant is enforced by construction.
