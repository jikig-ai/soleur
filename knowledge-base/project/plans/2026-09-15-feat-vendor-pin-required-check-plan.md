---
title: "feat: make the vendor upstream-blob binding check a required merge gate"
type: feat
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 8203
branch: feat-one-shot-8203-vendor-pin-required-check
created: 2026-09-15
---

# feat: make the vendor upstream-blob binding check a required merge gate ✨

Make `vendor-pin-verify.yml`'s `verify-upstream-blobs` job — the CI enforcement
of the #8181 path+commit+blob binding on every vendored NOTICE bundle — a
**required** merge gate via the ADR-032 / #5585 always-run aggregator pattern
(`vendor-pin-required`), while keeping the bot-PR result **earned** on the
Inngest re-vendor path rather than fabricated.

## Overview

`verify-upstream-blobs` (`plugins/soleur/skills/gdpr-gate/scripts/
vendor-pin-integrity.sh --verify-upstream`) binds each NOTICE `upstream-blob-sha`
to the path at the pinned upstream commit. Its context is absent from both
`infra/github/ruleset-ci-required.tf` and `scripts/required-checks.txt`, so a PR
that breaks the binding merges with the check red — the exact `lint fixture
content` gap ADR-032 exists to close (#3886).

Two structural constraints make this more than a one-line ruleset edit:

1. The workflow is `pull_request.paths`-filtered. A required context never
   reported on unrelated PRs sits at "Expected — Waiting" forever. The
   sanctioned fix (#5585, ADR-032 amendment): drop the workflow-level `paths:`,
   move path detection into a cheap `detect-changes` job, gate the heavy job on
   its output, and register an always-run (`if: always()`) fail-closed
   aggregator job as the required context.
2. `scripts/required-checks.txt` is the SSOT the
   `bot-pr-with-synthetic-checks` composite action derives `CHECK_NAMES` from
   (#6049). Any name added there gets a fabricated green on GITHUB_TOKEN bot
   PRs — sound only when the bot's `ALLOWED_PATHS` cannot reach the guarded
   surface. Separately, the Inngest re-vendor cron posts synthetics from the
   hardcoded `SYNTHETIC_CHECK_NAMES` list (`_cron-safe-commit.ts`) — that list
   must NOT gain the new context, because re-vendor PRs are precisely the diffs
   this check exists to gate, and they earn the real result via real CI (their
   App-token pushes trigger `pull_request` workflows — verified on PR #8166,
   where `verify-upstream-blobs` ran SUCCESS).

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "Adding the context to `required-checks.txt` feeds the bot-PR synthetic-check fabrication … for the cron's own re-vendor PRs" | Partially stale. `required-checks.txt` feeds only the **GHA composite action** (`action.yml` derives `CHECK_NAMES` from it). The re-vendor PRs are produced by the Inngest `cron-content-vendor-drift` → `safeCommitAndPr`, which posts from the **separate, hardcoded, test-pinned** `SYNTHETIC_CHECK_NAMES` (7 names; `cron-safe-commit.test.ts:636`, `cron-content-vendor-drift.test.ts:158` et al. pin the verbatim list). Adding to the txt does not fabricate on re-vendor PRs; adding to `SYNTHETIC_CHECK_NAMES` would. | The txt entry is required for parity (composite-action bots need the synthetic — their PRs never trigger CI — and their `ALLOWED_PATHS = {weakness-digest.md, rule-metrics.json}` cannot reach `plugins/soleur/skills/*`, so that green is sound-by-unreachability). The **earned** arm is: leave `SYNTHETIC_CHECK_NAMES` untouched so re-vendor/attest PRs are gated by the real always-run check. |
| "The synthetic must either be excluded (non-15368 `integration_id`) or the composite action's Phase-4 must reproduce the verification" | A non-15368 `integration_id` would deadlock every GITHUB_TOKEN bot PR permanently — the composite action posts check-runs as GitHub Actions (15368), nothing else could ever satisfy such a context, and those PRs run no CI. Phase-4 reproduction is only load-bearing when `ALLOWED_PATHS ∩` guarded-surface is non-empty (the `credential-path-guard` case, ADR-139); here the intersection is empty. | Register at `integration_id = var.actions_integration_id` (15368). Document the derived unreachability + the two-direction tripwire in `required-checks.txt`, matching the `rule-body-lint` / `sentry-destroy-required` / `marketplace-manifest-guard` note pattern. Reproduction in Phase-4 becomes mandatory only if `ALLOWED_PATHS` ever gains a `plugins/soleur/skills/**` path — the note says so. |
| Workflow is `pull_request.paths`-filtered to the vendored tree | Confirmed (`vendor-pin-verify.yml:11-20`), and the filter is **narrower than the verified surface**: the job enumerates `plugins/soleur/skills/*/NOTICE` (schema-keyed enrollment, ADR-219), but `paths:` names only gdpr-gate + legal-generate. A third enrolled bundle would not re-trigger the gate under the inherited list. | detect-changes anchors keep the **literal per-bundle paths** (NOT a `skills/*/NOTICE` wildcard — `vendor-bundle-coverage.test.sh` TS4 greps literal `plugins/soleur/skills/<slug>/` prefixes in this file as the new-bundle enrollment alarm; a wildcard would satisfy it vacuously), plus the workflow file, the verdict script and its test (anti-bypass self-anchors, per the #5585 anchors-must-cover-verified-surface learning). |
| `verify-upstream-blobs` "is absent from the ruleset and required-checks.txt" | Confirmed: 23 `required_check` blocks in the `.tf` (22 × 15368 + CodeQL 57789), 23 rows in the canonical JSON, 22 CI names + 2 CLA names in the txt. `tests/scripts/test-audit-ruleset-bypass.sh` T-rsc-7 **pins `n == "23"`** — a count literal that must be bumped in the same PR or CI reds. | Add the 24th block / 24th canonical row / 23rd CI name; bump T-rsc-7 to `n == "24"` and extend its count-history comment. |

## Premise Validation (Phase 0.6)

- `#8181` CLOSED (fixed by PR #8185, MERGED); `#5585` CLOSED (the
  `tenant-integration-required` precedent — shape verified in
  `tenant-integration.yml` + `scripts/tenant-integration-gate-verdict.sh`);
  `#6049` CLOSED (CHECK_NAMES derivation + parity test verified live); `#8203`
  OPEN.
- Cited files all exist on this branch: `.github/workflows/vendor-pin-verify.yml`,
  `infra/github/ruleset-ci-required.tf`, `scripts/required-checks.txt`,
  `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md`.
- Proposed mechanism (always-run aggregator for a path-filtered required check)
  is the mechanism ADR-032's amendment **prescribes**, not one it rejected —
  confirmed against ADR-032 §Amendment-2026-06-29 and §Generalized contract clause.
- Stale-premise finding recorded in Research Reconciliation: the issue's
  fabrication-warning targets `required-checks.txt`, but the re-vendor PRs' real
  fabrication surface is `SYNTHETIC_CHECK_NAMES` — the plan names both.

## Mechanism Minimality (Phase 0.6b)

**Property list.**

- P1 — Every PR reports a context for the binding check (no
  "Expected — Waiting" deadlock on unrelated PRs).
- P2 — A PR that breaks the path+commit+blob binding cannot merge to `main`.
- P3 — Bot PRs are neither deadlocked nor fabricated-green over a surface they
  can actually modify; re-vendor PRs (which DO modify it) are gated by a real
  run.
- P4 — The gate is fail-closed: any unenumerated `needs.*.result` state (incl.
  `cancelled`, empty, future GitHub-added strings) fails.

**Mechanisms named by the issue → property → disposition.**

- Always-run fail-closed aggregator job → P1+P4 → KEEP (no existing mechanism
  posts the context on unrelated PRs).
- `required_check` in `ruleset-ci-required.tf` → P2 → KEEP.
- `required-checks.txt` entry + guard note → P3 for composite-action bots →
  KEEP (parity test makes it mandatory anyway).
- "Exclude the synthetic via non-15368 `integration_id`" → P3 → **CUT**: it
  would deadlock every GITHUB_TOKEN bot PR (the action posts as 15368; no CI
  runs on those PRs to satisfy a foreign-integration context).
- "Composite action Phase-4 reproduces the verification" → P3 → **CUT** for
  this change: `ALLOWED_PATHS ∩ {plugins/soleur/skills/**} = ∅` makes
  reproduction unnecessary today (sound-by-unreachability); it becomes
  mandatory only if ALLOWED_PATHS grows toward the vendored tree — recorded as
  the note's tripwire.
- Plan-invented: `SYNTHETIC_CHECK_NAMES` stays at 7 + comment → P3 for the
  Inngest path → KEEP (the earned arm).

## User-Brand Impact

**If this lands broken, the user experiences:** a vendored bundle — the
gdpr-gate PII-detection patterns or the legal-generate attorney-drafted
templates that produce user-facing legal documents — silently diverges from the
reviewed, pinned upstream content, because the one check that would catch it
was red-but-mergeable (or, in the failure direction this plan must not create,
a fabricated green on the cron's own re-vendor PR launders a bad bundle into
`main`).

**If this leaks, the user's [data / workflow / money] is exposed via:** a
weakened or tampered vendored compliance artifact reaching generated output —
e.g. a mis-bound PII pattern set degrading the gdpr-gate scan over a user's
data, or a legal template that no longer matches the vetted upstream blob —
with every repo signal reporting green.

**Brand-survival threshold:** single-user incident. (`requires_cpo_signoff:
true`; `user-impact-reviewer` runs at PR review. The vendored corpus IS
compliance surface — a wrong-but-green merge on it is a per-user legal
artifact, not a style defect.)

## Files to Create

- `scripts/vendor-pin-gate-verdict.sh` — fail-closed verdict for the
  `vendor-pin-required` aggregator. Allow-list: exit 0 iff
  `detect-changes.result == 'success'` AND `verify-upstream-blobs.result ∈
  {success, skipped}`; exit 1 otherwise. Mirrors
  `scripts/tenant-integration-gate-verdict.sh` /
  `scripts/sentry-destroy-gate-verdict.sh`, incl. the `skipped`-arm notice
  ("nothing was verified against this tree — first execution is post-merge")
  and the `cancelled` diagnostic arm.
- `tests/scripts/test-vendor-pin-gate-verdict.sh` — unit battery over every
  `needs.*.result` branch (mirrors
  `tests/scripts/test-sentry-destroy-gate-verdict.sh`).

## Files to Edit

**Definite:**

- `.github/workflows/vendor-pin-verify.yml` —
  (a) `on:` → `pull_request: { branches: [main] }` (drop `paths:`), `push:
  { branches: [main] }`, `merge_group:`, `workflow_dispatch:` — mirrors the
  #5585/#6589 trigger set so the required context can also report on a queue
  temp ref if the queue is ever re-adopted (ADR-032 generalized clause);
  (b) new `detect-changes` job emitting `vendor=true|false` — PR diffs against
  `origin/$BASE_REF` (`fetch-depth: 0`), non-PR events → `vendor=true`,
  `merge_group` → `vendor=false` (authoritative run already happened on the
  PR), a git/checkout error **fails the job** (never silently `vendor=false`);
  (c) `verify-upstream-blobs` gains `needs: detect-changes` + `if:
  needs.detect-changes.outputs.vendor == 'true'` — no other change to its
  steps (the schema-keyed NOTICE enumeration and `conforming == 0`
  anti-vacuity floor stay);
  (d) new `vendor-pin-required` job — `needs: [detect-changes,
  verify-upstream-blobs]`, `if: always()`, single `run:` step invoking the
  verdict script with both results passed via `env:` + quoted `"$VAR"`;
  (e) `concurrency: { group: vendor-pin-verify-${{ github.ref }},
  cancel-in-progress: false }` — same eviction reasoning as
  `tenant-integration.yml` (a displaced pending gate job concludes
  `cancelled` → fail-closed red).
  **detect-changes anchors (literal, per `vendor-bundle-coverage.test.sh`
  TS4's grep contract):** every conforming bundle's `plugins/soleur/skills/
  <slug>/NOTICE` + `plugins/soleur/skills/<slug>/references/` prefix (today:
  gdpr-gate, legal-generate), `plugins/soleur/skills/gdpr-gate/scripts/
  vendor-pin-integrity.sh`, `.../notice-frontmatter.sh`,
  `.github/workflows/vendor-pin-verify.yml`, `scripts/
  vendor-pin-gate-verdict.sh`, `tests/scripts/
  test-vendor-pin-gate-verdict.sh`.
- `infra/github/ruleset-ci-required.tf` — 24th `required_check` block:
  `context = "vendor-pin-required"`, `integration_id =
  var.actions_integration_id`; tier comment per file convention (#8203,
  aggregator precedent, bot-PR synthetic disposition); update the header's
  stale "the 20 `context` strings" to the real count (24) — the header's
  per-addition history lines get a `#8203` entry. Do NOT put a literal
  `context = "..."` token inside comments (T-rsc-9's comment-naive grep
  over-counts — the CLA file documents this failure as SE-3).
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — add
  `{ "context": "vendor-pin-required", "integration_id": 15368 }` (T-rsc-9
  enforces set-equality with the `.tf`; the parity test enforces
  15368-set-equality with `required-checks.txt`).
- `scripts/required-checks.txt` — add `vendor-pin-required` under the CI
  Required section with a guard note in the established shape: CONTENT-SCOPED;
  the composite-action synthetic is sound by **UNREACHABILITY** (re-derived:
  `ALLOWED_PATHS = {knowledge-base/project/weakness-digest.md,
  knowledge-base/project/rule-metrics.json}` ∩ `{plugins/soleur/skills/**}` =
  ∅); tripwire (A) — extending ALLOWED_PATHS to any vendored path first
  requires reproducing `vendor-pin-integrity.sh --verify-upstream` over the
  bot diff in the action's Phase-4 ceiling; tripwire (B) — **the Inngest
  re-vendor path must never satisfy this check synthetically**: do NOT add the
  name to `SYNTHETIC_CHECK_NAMES` in `_cron-safe-commit.ts`, because
  `cron-content-vendor-drift` PRs are the diffs this gate exists for and their
  App-token pushes run the real workflow (PR #8166 evidence).
- `tests/scripts/test-audit-ruleset-bypass.sh` — T-rsc-7: bump `n == "23"` →
  `"24"` (both the predicate and the report string) and extend the
  count-history comment (`bumped 23->24 by #8203`).
- `scripts/test-all.sh` — register `tests/scripts/test-vendor-pin-gate-verdict.sh`
  via `run_suite` beside the sibling verdict suites (~:2363-2371); nothing
  auto-discovers `tests/scripts/`.
- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` —
  comment-only edit at `SYNTHETIC_CHECK_NAMES` (:47-55): record that
  `vendor-pin-required` is deliberately absent — bot PRs whose `allowedPaths`
  intersect the vendored tree (only `cron-content-vendor-drift` today) earn
  the context from the real always-run workflow on their App-token-triggered
  CI, and adding it here would fabricate the binding check on exactly the
  PRs it gates.
- `knowledge-base/engineering/architecture/decisions/
  ADR-032-github-branch-protection-as-iac.md` — amendment per the ADR section
  below (count 23→24; second instance of the always-run-aggregator pattern;
  the Inngest-vs-composite-action synthetic distinction).
- `knowledge-base/engineering/policies/content-vendoring.md` — §:90 sentence
  update: the check is now the required `vendor-pin-required` gate wrapping
  `verify-upstream-blobs` (keeps the doc's enforcement description accurate).

**Verify-only / NO edit (verified at plan time):**

- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — `CHECK_NAMES`
  derives from `required-checks.txt` (#6049); the new synthetic is inherited
  automatically. Sound-by-unreachability documented in the txt note. NO
  Phase-4 reproduction required today (∅ intersection).
- `scripts/post-bot-statuses.sh` — Statuses API; does not satisfy rulesets.
  Confirm no live consumer needs the new context; do not add it otherwise.
- `scripts/create-ci-required-ruleset.sh` / `update-ci-required-ruleset.sh` —
  frozen one-shot migration artifacts; appending is wrong (T-rsc-8 keeps them
  referencing the canonical JSON, which DOES get the new row).
- `tests/scripts/test-destroy-guard-counter.sh` +
  `tests/scripts/fixtures/tfplan-*.json` — delete-only guards; an *add* stays
  green. `T-mq-1` (merge_queue stays reverted) is unaffected — we add a
  `required_check`, not a `merge_queue` rule.
- `SYNTHETIC_CHECK_NAMES` + its pinning tests — deliberate non-edit (see
  above); the pin is the guard.

## Open Code-Review Overlap

- `#7942` (mutation-battery `*.mutation.sh` naming in `plugins/soleur/test/`)
  touches `scripts/test-all.sh`, which this plan also edits (one `run_suite`
  line). **Acknowledge** — different concern; our new suite is a plain
  `test-*.sh` verdict battery under `tests/scripts/`, not a `plugins/` mutation
  battery, so the scope-out does not apply to it.
- `#3593` (extract post-synthetic-checks child composite, deferred per
  ADR-027) touches the composite action, which this plan reads but does not
  edit. **Acknowledge** — the deferred extraction does not interact with the
  derived-CHECK_NAMES change.

## Implementation Phases

### Phase 0 — Re-confirm the verified edit set (read-only)

1. Re-grep: `grep -c 'required_check {' infra/github/ruleset-ci-required.tf`
   == 23; `jq 'length'` the canonical JSON == 23; T-rsc-7 still asserts `23`;
   `SYNTHETIC_CHECK_NAMES` still 7 names and still test-pinned verbatim;
   `action.yml` still derives CHECK_NAMES from `required-checks.txt`.
2. Confirm `vendor-bundle-coverage.test.sh` TS4 still greps literal
  `<prefix>/` strings in `vendor-pin-verify.yml` — it is the reason the
  detect-changes anchors stay literal per-bundle rather than a
  `skills/*/NOTICE` wildcard.
3. Read `scripts/tenant-integration-gate-verdict.sh` +
   `scripts/sentry-destroy-gate-verdict.sh` and their test files as the
   copy-source for the new verdict pair.

### Phase 1 — Workflow restructure + verdict script (`vendor-pin-verify.yml`)

1. Write `scripts/vendor-pin-gate-verdict.sh` (fail-closed allow-list verdict,
   incl. the skipped-arm `::notice` + job-summary honesty line and the
   `cancelled` diagnostic arm) and
   `tests/scripts/test-vendor-pin-gate-verdict.sh` covering:
   (success, success)→pass; (success, skipped)→pass;
   (success, failure)→fail; (**detect failure** → verify skipped)→**fail**
   — the DROP-1 arm; (success, cancelled)→fail; (empty, *)→fail;
   (*, empty)→fail.
2. Edit the workflow per Files-to-Edit (a)–(e). `detect-changes` uses
   `set -uo pipefail`; `git diff --name-only "origin/${BASE_REF}...HEAD"`
   failure exits 1; anchor match via `grep -qE` on a grouped alternation of
   the literal anchor set. No `|| true` on the diff.
3. Register the new test in `scripts/test-all.sh` (the comment there states
   `tests/scripts/` is not auto-discovered).

### Phase 2 — Required-check registration (IaC + canonical + SSOT + count pin)

1. `ruleset-ci-required.tf`: add the `required_check` block with the tier
   comment; fix the stale header count.
2. `ci-required-ruleset-canonical-required-status-checks.json`: append the
   row (keep array order stable — append at end).
3. `required-checks.txt`: add the name + guard note (the tripwire paragraph
   must name both the composite-action ALLOWED_PATHS arm AND the
   `SYNTHETIC_CHECK_NAMES` exclusion arm — the file's existing entries only
   cover the first arm).
4. `test-audit-ruleset-bypass.sh` T-rsc-7: `23` → `24` + history comment.
5. `cd infra/github && terraform fmt && terraform validate` (no plan/apply —
   `prd_terraform` creds are absent in the worktree; the merge-triggered
   `apply-github-infra.yml` is the apply path, AC9).

### Phase 3 — Bot-synthetic disposition

1. Comment-only edit at `SYNTHETIC_CHECK_NAMES` (`_cron-safe-commit.ts`).
2. Run `bash scripts/lint-bot-synthetic-completeness.sh` — paste its full
   output into the PR body (the required-check Sharp Edge: enumerate every
   PR-creating workflow + disposition; today's audit shows the 2
   PR-creating workflows use App tokens and the composite action covers the
   GITHUB_TOKEN producers by derivation).
3. Re-run `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`
   — green iff txt ↔ canonical 15368-set parity holds after the edits.

### Phase 4 — ADR-032 amendment + policy doc

Amend ADR-032 and `content-vendoring.md` per the Architecture Decision
section / Files-to-Edit.

### Phase 5 — Verification (pre-merge)

`bash scripts/test-all.sh` (verdict suite + parity + T-rsc-7/9 + coverage);
`actionlint` on the workflow; `bash -n` on extracted `run:` snippets;
`terraform fmt -check` + `terraform validate`; the AC greps below.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `vendor-pin-verify.yml` carries no `paths:`/`paths-ignore:` under
  `on.pull_request` (or `on.push`); `on:` includes `merge_group:`;
  `actionlint` passes; extracted `run:` snippets pass `bash -n`.
- **AC2.** `detect-changes` emits `vendor=true` for a diff touching any anchor
  (including the workflow file itself and the verdict pair) and
  `vendor=false` for a diff touching none; non-PR events → `true`;
  `merge_group` → `false`; a `git diff` failure fails the job.
- **AC3.** `vendor-pin-required` uses job-level `if: always()` and asserts
  **inside a `run:` step** (never a job-level `if:` on results), reading BOTH
  `needs.detect-changes.result` and `needs.verify-upstream-blobs.result`.
  Allow-list predicate verified by
  `bash tests/scripts/test-vendor-pin-gate-verdict.sh` over every branch
  listed in Phase 1.1.
- **AC4.** `ruleset-ci-required.tf` contains `required_check` with `context =
  "vendor-pin-required"` and `integration_id = var.actions_integration_id`;
  `terraform fmt -check` + `terraform validate` pass; `grep -c
  'required_check {' infra/github/ruleset-ci-required.tf` returns **24**.
  Registration is via this `.tf` applied by `apply-github-infra.yml` — never
  `gh api`.
- **AC5.** `scripts/required-checks.txt`, the canonical JSON, and the `.tf`
  are in set-parity: `bash
  plugins/soleur/test/required-checks-canonical-parity.test.sh` exits 0 AND
  `bash tests/scripts/test-audit-ruleset-bypass.sh` exits 0 (T-rsc-7 now pins
  24). `SYNTHETIC_CHECK_NAMES` is **unchanged** — `grep -c 'vendor-pin'`
  against `_cron-safe-commit.ts`'s array returns 0, and the 7-entry pin tests
  stay green. Phase-3 lint output pasted in the PR body.
- **AC6.** `vendor-bundle-coverage.test.sh` stays green — literal
  `plugins/soleur/skills/<slug>/` anchors remain present in
  `vendor-pin-verify.yml` (inside `detect-changes`), so a future conforming
  NOTICE still turns the suite red until enrolled.
- **AC7.** This PR touches `vendor-pin-verify.yml` → `detect-changes` →
  `vendor=true` → `verify-upstream-blobs` runs for real and is green, and
  `vendor-pin-required` posts success — the introducing PR exercises the gate
  before it becomes required.
- **AC8.** ADR-032 amended (count + second-instance-of-pattern + the
  earned-vs-fabricated distinction across the two synthetic paths). PR body
  uses `Closes #8203`.

### Post-merge (verification, no operator provisioning)

- **AC9.** The merge-triggered `apply-github-infra.yml` run is green and the
  live ruleset (`gh api repos/jikig-ai/soleur/rulesets/14145388`) lists
  `vendor-pin-required` among required contexts.
- **AC10.** The first subsequent unrelated PR reports `vendor-pin-required`
  **success** with `verify-upstream-blobs` **skipped** and the skipped-arm
  notice present; the first subsequent `cron-content-vendor-drift` re-vendor
  or attest PR shows the context **earned by a real workflow run** (no
  synthetic for this name in its check-runs).
- **AC11.** Registration cutover does not permanently block pre-existing open
  PRs: under `strict_required_status_checks_policy = true` they show
  "Expected — Waiting" until rebased onto post-merge `main` (self-healing);
  confirm by rebasing one open PR.

## Infrastructure (IaC)

### Terraform changes

- `infra/github/ruleset-ci-required.tf` — one added `required_check` block in
  the existing `github_repository_ruleset.ci_required` resource. Provider:
  `integrations/github` (App-auth, soleur-ai installation). Backend: R2
  (`github/terraform.tfstate`). No new variable; no new provider.

### Apply path

Merge-triggered auto-apply via `apply-github-infra.yml` (`on.push.paths:
infra/github/*.tf`). The PR merge IS the authorization (ADR-031/032,
`hr-menu-option-ack-not-prod-write-auth`). In-place ruleset update — no
taint/replace, no downtime. Kill switch `[skip-github-apply]` available.

### Distinctness / drift safeguards

GitHub rulesets affect only this repo (no dev/prd split).
`strict_required_status_checks_policy = true` preserved. T-rsc-9 +
`required-checks-canonical-parity.test.sh` + the daily
`cron-ruleset-bypass-audit` keep `.tf` ↔ canonical ↔ live in lockstep; a
`merge_queue` rule re-addition stays blocked by T-mq-1. No
`lifecycle.ignore_changes` change.

### Vendor-tier reality check

N/A — GitHub rulesets carry no paid-tier gate for required-check count.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-032** (no new ADR — this is within its branch-protection-as-IaC
pattern and its 2026-06-29 amendment's own pattern). In-scope plan tasks
(Phase 4):

1. Required-check count → 24 wherever the ADR enumerates a current count;
   keep the historical #3886 `5→14` import figures as-is.
2. Record `vendor-pin-required` as the **second** instance of the always-run
   aggregator pattern (first conditionally-skipped-but-required precedent was
   `tenant-integration-required`), and the refinement this instance adds:
   the guarded surface is enrolled **schema-keyed** (`skills/*/NOTICE`), so
   detect-changes anchors are maintained as literal per-bundle paths in
   lockstep with `vendor-bundle-coverage.test.sh`, not as a wildcard.
3. Record the earned-vs-fabricated split the issue surfaced: the composite
   action's synthetic (GITHUB_TOKEN bots) is sound-by-unreachability, while
   the Inngest `SYNTHETIC_CHECK_NAMES` path is held OUT of the context because
   `cron-content-vendor-drift` PRs are the gate's reason to exist and earn it
   via real CI on App-token pushes.

### C4 views

**No C4 impact.** Checked `model.c4`, `views.c4`, `spec.c4`: the model's
GitHub element already carries the branch-protection/ruleset-as-IaC role and
the `github -> soleurMarketplace` ruleset edge; the vendored-content upstream
relationship is already modeled (`github` element's `#8122/ADR-219` clause —
"UPSTREAM CONTENT SOURCE for every schema-conforming vendored bundle … polled
by cron-content-vendor-drift"). No new external actor, external system, data
store, or access relationship is introduced — a required context is a
configuration detail of the already-modeled ruleset, not an architectural
element. Nothing to add or correct.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed (plan-time assessment; no brainstorm precedes this
one-shot path).
**Assessment:** Approach copies the proven `detect-changes` + always-run
aggregator idiom twice-shipped in this repo (#5585, #6589) — no new pattern.
Hardening is baked into ACs: fail-closed allow-list predicate, `run:`-step
assertion (never job-level `if:`), fail-closed `detect-changes`, IaC
registration, in-lockstep canonical/SSOT/count-pin updates. CLO/CPO assessed
low-relevance (no legal document content, no product surface change); the
`single-user incident` threshold is carried by the User-Brand Impact section
and `user-impact-reviewer` at review time.

### Product/UX Gate

Skipped — mechanical UI-surface scan of Files-to-Edit/Create (`.yml`, `.tf`,
`.txt`, `.json`, `.sh`, a comment-only `.ts`, `.md` docs) matches no
UI-surface term/glob. NONE.

## Observability

```yaml
liveness_signal:    # the required-check context itself — reported on every PR; a missing
                    # context reads "Expected — Waiting" and blocks merge (fail-visible).
                    # apply-github-infra.yml apply failures surface as a red run on main
                    # and via main-health-monitor.yml; the daily cron-ruleset-bypass-audit
                    # compares live ↔ canonical.
error_reporting:    # workflow-run failure on the PR + workflow_run surfacing via
                    # main-health-monitor; fail_loud: yes — the check failing IS the signal
failure_modes:
  - mode: detect-changes fails → verify skipped, gate reads detect=failure → red (fail-closed)
    detection: required check red on the PR
    alert_route: PR check rollup
  - mode: aggregator job renamed → context never reports → all PRs blocked "Expected — Waiting"
    detection: merge queue of red PRs; canonical-parity/T-rsc-9 still green (name drift is a
             live-vs-tf concern the daily audit catches)
    alert_route: daily ruleset audit + blocked-PR pileup
  - mode: fabricated green on a re-vendor PR (someone adds the name to SYNTHETIC_CHECK_NAMES)
    detection: 7-entry pin tests red at the first such edit
    alert_route: CI `test` check red
logs:               # GHA run logs for vendor-pin-verify.yml; retention = GitHub default
discoverability_test:
  command:          grep -c 'vendor-pin-required' infra/github/ruleset-ci-required.tf scripts/required-checks.txt scripts/ci-required-ruleset-canonical-required-status-checks.json
  expected_output:  each file reports >= 1 occurrence (3 lines of output, each "1" or more)
```

## Encryption Posture

Detection fired (`.tf` in Files-to-Edit) — resolution: **no persistent store,
no new cross-component/network connection.** `github_repository_ruleset` is a
configuration assertion on the GitHub API, not a data store; the apply rides
the existing `apply-github-infra.yml` → api.github.com TLS edge already
modeled in `model.c4`. No `at_rest`/`in_transit`/`exception` rows apply.

## GDPR / Compliance Gate

Threshold trigger (b) fires (`single-user incident`), but the diff touches no
regulated-data surface — no schema/migration/auth/API-route, no new processing
activity, no data movement, no new artifact distribution surface. The change
gates a check that itself protects vendored compliance content; it processes
no personal data. Determination: documented no-op.

## Guard Contract

### Guard 1 — `vendor-pin-required` aggregator gate

**Property.** Every `main`-targeted PR reports the `vendor-pin-required`
context, and it is green only when `detect-changes` ran successfully AND the
binding verification either ran green on the diff or was verifiably
unrequired — a PR that breaks the NOTICE path+commit+blob binding cannot
merge.

**Assembly.** The chokepoints the property quantifies over: (a) the workflow's
`on:` triggers — must include `pull_request` (unfiltered) + `merge_group` so a
context is always reportable; (b) the `detect-changes` anchor set — must cover
the whole verified surface (every enrolled bundle's NOTICE + references, the
two scripts, the workflow itself, the verdict pair); (c) the aggregator's
`needs:` + `if: always()` + in-`run:` allow-list predicate; (d) the
name-identity chain — job name `vendor-pin-required` == `.tf` `context` ==
canonical JSON row == `required-checks.txt` line (T-rsc-9 + the parity test
are the mechanical keepers of that chain); (e) the synthetic surface —
`required-checks.txt` feeds the composite action (unreachability-sound) and
`SYNTHETIC_CHECK_NAMES` must never carry the name.

**Mutation matrix (design-derived; each MUST drive the guard red).**

| # | Edit | Why it must red |
|---|---|---|
| M1 | Verdict script uses a deny-list (`!= 'failure'`) instead of the allow-list | `cancelled`/empty results green — verdict battery's cancelled/empty rows red |
| M2 | Aggregator drops the `detect-changes.result` conjunct | detect failure → verify `skipped` → gate greens an unmeasured tree — the DROP-1 battery row reds |
| M3 | `detect-changes` swallows a git-diff error (`|| true` → emits `vendor=false`) | the gate certifies "nothing to verify" on a tree it never measured — the diff-failure AC2 arm reds |
| M4 | Aggregator's `if: always()` removed / verdict moved to a job-level `if:` | on a `needs` failure the context never posts → "Expected — Waiting" blocks every PR (red-by-absence, the shape this guard exists to prevent) |
| M5 | Second-member row: a second enrolled bundle lands but its literal anchor is not added to detect-changes | `vendor-bundle-coverage.test.sh` TS4 reds — the census alarm, not the gate itself, is the enforcement; kept literal precisely so this row lives |
| M6 | `vendor-pin-required` added to `SYNTHETIC_CHECK_NAMES` | fabrication on the re-vendor PRs — the 7-entry pin tests red |

**Harness rows.**

| # | Edit / input | Expected |
|---|---|---|
| H1 | Corrupt the verdict test's expected mapping (mark (success,failure) as pass) | the suite must red on itself — no vacuous harness |
| H2 | Must-pass non-canonical input: `(detect=success, verify=skipped)` | PASS — the allowed non-green-path arm, exercised by every unrelated PR |
| H3 | Add `vendor-pin-required` to the canonical JSON but not `required-checks.txt` (or vice versa) | parity test reds — the name-chain guard |
| H4 | Add a 24th canonical row without bumping T-rsc-7's `23` | T-rsc-7 reds — the count literal catches the unintended add (and this PR's own bump is the acknowledgement) |

**Anchor.** The stored values the guard compares (context names across four
files) are all inside the commit — what keeps a weakening from passing is the
OUTSIDE state: the **live ruleset** (14145388), reconciled daily by
`cron-ruleset-bypass-audit` and re-applied by `apply-github-infra.yml` on
merge; and the **real upstream blob store**, which `verify-upstream-blobs`
queries at run time — a fabricated or skipped verdict cannot conjure a
matching `contents/<path>?ref=<pinned-commit>` SHA.

## Risks & Sharp Edges

- **R1 (fail-open via detect-changes failure — DROP-1).** If `detect-changes`
  fails, `verify-upstream-blobs` is `skipped`; a gate reading only the verify
  result would green a run where path-detection never ran. Mitigation: the
  verdict requires `detect-changes.result == 'success'` (Phase 1, AC3);
  `detect-changes` fails the job on any git error (never `|| true`).
- **R1b (fail-open via job-level skip).** A job-level `if:` skip reports no
  context → "Expected — Waiting" deadlock. Mitigation: `if: always()` +
  in-`run:` assertion (AC3).
- **R2 (anchor coverage ≠ inherited paths).** Once required, a green on the
  skipped arm is an authoritative certification, so anchors must cover the
  *verified* surface — but `vendor-bundle-coverage.test.sh` pins literal
  per-bundle prefixes, so the anchors enumerate the literal paths (both
  bundles' NOTICE + references + scripts + the workflow + verdict pair),
  NOT a `skills/*/NOTICE` wildcard. The coverage test is the census that
  forces the anchor list to grow with enrollment (Guard matrix M5).
- **R3 (fabrication split across two synthetic paths).** `required-checks.txt`
  feeds only the GHA composite action (sound by unreachability — ALLOWED_PATHS
  can't reach `plugins/soleur/skills/**`); the Inngest re-vendor path posts
  from `SYNTHETIC_CHECK_NAMES`, which stays at 7 so re-vendor PRs earn the
  real run. The txt guard note must name BOTH arms — copying only the
  ALLOWED_PATHS paragraph from a sibling entry would miss the second.
- **R4 (concurrency).** Add `concurrency` with `cancel-in-progress: false` —
  with `true`, a re-run race cancels the pending gate job on the head SHA →
  `cancelled` → fail-closed red blocks merge until re-run (the #7055
  eviction class). `false` costs at most a duplicate cheap run.
- **R5 (first-merge sequencing).** `strict_required_status_checks_policy =
  true`: open PRs must rebase onto post-merge `main` to gain the context —
  self-healing; the introducing PR itself is gated by the current 23-check
  ruleset and is unaffected (its own run exercises the new job via the
  workflow-file self-anchor, AC7).
- **R6 (count literals).** Two count-pinning sites must move in the same PR —
  T-rsc-7 (`n == "23"` → `"24"`) and the `.tf` header's stale "20 `context`
  strings" — or CI reds. The ADR-032 count sites move in Phase 4.
- **R7 (comment-naive greps).** T-rsc-9 extracts `context = "..."` by grep
  over the `.tf`; a literal `context = "vendor-pin-required"` inside a comment
  would over-count. Keep the token out of comments (the CLA file's SE-3 note).
- **SE.** A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. This plan's section is complete.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | PR touching no anchors | `detect-changes` → `vendor=false`; verify `skipped`; `vendor-pin-required` **success** + skipped-arm notice; no upstream API calls |
| T2 | PR touching `plugins/soleur/skills/<bundle>/references/**`, bindings intact | verify `success`; gate **success** |
| T3 | PR breaking a binding (NOTICE blob-sha vs path@pinned-commit mismatch) | verify `failure`; gate **failure**; merge blocked |
| T4 | push to `main` | `vendor=true`; verify runs on main (post-merge green signal) |
| T5 | PR editing only `vendor-pin-verify.yml` or the verdict pair | `vendor=true` (self-anchor); verify runs |
| T6 | `detect-changes` fails (git/checkout error) | verify `skipped`; gate reads `detect=failure` → **failure** (DROP-1) |
| T7 | GITHUB_TOKEN bot PR (weakness-miner / rule-metrics / main-health-monitor via composite action) | synthetic `vendor-pin-required` posts via derived CHECK_NAMES; sound-by-unreachability per the txt note |
| T8 | Inngest `cron-content-vendor-drift` re-vendor or attest PR | real workflow runs (App-token push); `vendor-pin-required` **earned**; no synthetic for this name |
| T9 | New conforming NOTICE enrolled without anchor update | `vendor-bundle-coverage.test.sh` TS4 reds — anchors forced to grow |

## Research Insights

### Relevant file paths

- `.github/workflows/vendor-pin-verify.yml` — the path-filtered workflow being
  restructured (`verify-upstream-blobs` job, lines 26-70).
- `.github/workflows/tenant-integration.yml:482-493` + `scripts/
  tenant-integration-gate-verdict.sh` + `tests/scripts/
  test-tenant-integration-gate-verdict.sh` — the #5585 aggregator precedent.
- `.github/workflows/apply-sentry-infra.yml:671-684` + `scripts/
  sentry-destroy-gate-verdict.sh` — the #6589 refinement (same shape).
- `infra/github/ruleset-ci-required.tf` — 23 `required_check` blocks today;
  `variables.tf:25-30` pins `actions_integration_id = 15368`.
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — 23
  rows; live-mirrored to the `.tf` by T-rsc-9 (post-#6049 it is NOT the
  dormant legacy the #5585 plan found — it must be edited).
- `scripts/required-checks.txt` — the SSOT; guard-note precedents at the
  `rule-body-lint` (unreachability), `credential-path-guard` (earned), and
  `marketplace-manifest-guard` (unreachability) entries.
- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — `CHECK_NAMES`
  derived from the txt (:294-308); `ALLOWED_PATHS` at :161.
- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts:47-55` —
  `SYNTHETIC_CHECK_NAMES` (7 names, verbatim test-pinned); synthetic posting
  at :756-786; merge ladder at :802+.
- `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts`
  — re-vendor PR route (:2152-2197, `allowedPaths` = `<skill>/NOTICE` +
  `<skill>/references/`) and attest route (:2541-2577, `allowedPaths` =
  `<skill>/NOTICE`), both `mergeMode: "direct"` + `SYNTHETIC_CHECK_NAMES`.
- `tests/scripts/test-audit-ruleset-bypass.sh` — T-rsc-7 count literal (:661),
  T-rsc-9 canonical↔tf set-equality (:674-697), T-mq-1 merge-queue kill-switch
  (:709-735).
- `plugins/soleur/test/vendor-bundle-coverage.test.sh` — TS4 (:124) greps
  literal `plugins/soleur/skills/<slug>/` in the workflow file: the enrollment
  census that forces literal anchors.
- `plugins/soleur/test/required-checks-canonical-parity.test.sh` — txt ↔
  canonical 15368-set parity + the action's derivation grep.
- `scripts/test-all.sh` SUITE_GLOBS (:78-87) — `plugins/soleur/test/*.test.sh`
  auto-registers; `tests/scripts/` needs an explicit `run_suite` (:2363+).

### Institutional learnings applied

- `2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md`
  — anchors cover the verified surface; combined with the coverage-test
  literal-grep contract this yields literal per-bundle anchors, not a wildcard.
- `2026-03-20-github-required-checks-skip-ci-synthetic-status.md` — required
  contexts need Check-Runs (15368), not Statuses.
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
  — the whole reason `if: always()` + in-`run:` verdict.
- `2026-04-03-github-ruleset-put-replaces-entire-payload.md` — ruleset writes
  are whole-list; IaC (not `gh api`) is the registration path.
- `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` —
  context name kept single-token (`vendor-pin-required`).
- ADR-139 — the `ALLOWED_PATHS ∩ SCAN_DIRS` reachability test is re-derived
  per gate, never inherited.

### Related issues / PRs

#8181 (binding check, closed by PR #8185), #8185 (the merged machinery PR),
#5585 + PR #5688 (aggregator precedent), #6049 (CHECK_NAMES derivation +
parity test), #6103/#6589/#6882/#7493/#7927 (the required-check addition
precedents incl. both synthetic dispositions), ADR-032, ADR-092, ADR-139,
ADR-219 (schema-keyed enrollment), #8122 (multi-bundle). Overlap: #7942,
#3593 (acknowledged, no fold-in).

### Empirical evidence gathered at plan time

- PR #8166 (`app/soleur-ai` re-vendor/attest PR): `statusCheckRollup` shows
  `verify-upstream-blobs` SUCCESS via the real `vendor-pin-verify` workflow —
  App-token PRs DO trigger `pull_request` workflows; the earned path exists.
- `lint-bot-synthetic-completeness.sh` output: the only 2 shell-level
  PR-creating workflows use App tokens; GITHUB_TOKEN producers route through
  the composite action's derived CHECK_NAMES.
- `gh issue list --label code-review` cross-referenced against every planned
  path — the two hits recorded in Open Code-Review Overlap.
