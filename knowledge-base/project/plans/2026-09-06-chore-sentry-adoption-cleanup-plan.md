---
title: "chore(sentry-infra): retire the 27 adoption blocks, settle the byok-cap fallthrough, heartbeat the drift cron, and repair the R2 rollback runbook"
date: 2026-09-06
slug: chore-sentry-adoption-cleanup
branch: feat-one-shot-7826-sentry-adoption-cleanup
issue: 7826
closes: [7826, 7829, 7834, 7836]
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Four follow-ups left open by the Sentry Phase 2 alert-rule adoption (PR 7821, merged
2026-09-06) are settled in one change set.

The adoption paired every one of 27 rules with an `import {}` block and a
`removed { lifecycle { destroy = false } }` block in
`apps/web-platform/infra/sentry/issue-alerts.tf`. Those blocks did their job at apply
time and are now migration residue: each pins a hardcoded live instance id, so the root
no longer describes a configuration that can be built from an empty state. Retiring them
is the first change (#7826), and it is gated on live state still holding exactly the 27
adopted addresses — an un-imported address whose `import {}` is dropped becomes a CREATE
against a live paging rule.

The second change settles whether `byok-cap-exceeded` — the one rule of the 27 whose
`issue_owners` action falls through to `NoOne` rather than `ActiveMembers` — is a defect
or a deliberate severity split (#7829). The premise is verified before anything is
edited, and the outcome is written down either way.

The third change gives `scheduled-sentry-alert-drift` the cron monitor and heartbeat
every other scheduled workflow already has, so a cron that stops firing is visible rather
than silently absent (#7834).

The fourth repairs a runbook that cannot run: the documented Terraform state rollback
opens with an object-version listing the state bucket does not implement, which leaves
every root sharing that bucket with an inoperable recovery path (#7836). The measurement
is re-taken before the documentation is rewritten.

## Research Insights

### Premise Validation (Phase 0.6)

All four issues are OPEN (`gh issue view`, 2026-09-06). PR 7821 is `MERGED` at
`2026-09-06T14:38:19Z` and is the tip of `origin/main` (`72ebe67b7`). PR 7866 is `OPEN`,
not draft, `MERGEABLE`, and touches exactly one file — `.github/workflows/apply-sentry-infra.yml`
— which no part of this change may edit. Three premises supplied in the brief were measured
and did **not** survive; they are corrected in the reconciliation table below and must not be
restated anywhere in this plan's output.

### Live measurements taken for this plan

Every number below was produced by a command run on 2026-09-06, not carried from a document.

**M1 — live Terraform state, `apps/web-platform/infra/sentry`** (`terraform init -lockfile=readonly`
then `terraform state list`; the init left the committed `.terraform.lock.hcl` unmodified):

| type | count |
|---|---|
| `sentry_alert.` | **27** |
| `sentry_issue_alert.` | 3 |
| `sentry_cron_monitor.` | 55 |
| `sentry_uptime_monitor.` | 4 |
| `data.` | 2 |
| total | 91 |

**M2 — address-set equality.** The 27 `sentry_alert.<label>` addresses in state `diff` empty
against the 27 `resource "sentry_alert" "<label>"` labels in `issue-alerts.tf`. Exact 1:1, no
orphan in either direction. The three `sentry_issue_alert` addresses are exactly the three
still declared: `auth_per_user_loop`, `git_data_boot_warning`, `sandbox_startup_failure`.
This is the strongest form of #7826's precondition — not merely "27 are present" but "the 27
present are the 27 whose `import{}` blocks are being deleted".

**M3 — Sentry ownership rule for the target project.**
`GET https://jikigai-eu.sentry.io/api/0/projects/jikigai-eu/web-platform/ownership/` → HTTP 200,
body `{"raw":null,"fallthrough":true,"dateCreated":null,"lastUpdated":null,"isActive":true,`
`"autoAssignment":"Auto Assign to Issue Owner","codeownersAutoSync":true,"schema":null}`.
Control probe `GET .../projects/jikigai-eu/web-platform/` → HTTP 200 returning
`{"slug":"web-platform","id":"4511404943671376",...}`, so the null is a real absence and not a
wrong-project or auth artifact. **No ownership rule exists**, therefore `target_type = "issue_owners"`
resolves to nobody and `fallthrough_type` alone decides delivery.

**M4 — R2 object versioning, re-probe.** Credentials `doppler -p soleur -c prd_terraform`,
endpoint `https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com`, `aws-cli/2.13.21`:

- control `s3api list-objects-v2 --bucket soleur-terraform-state` → 200, six objects listed;
- `s3api list-object-versions --bucket soleur-terraform-state` → `An error occurred (NotImplemented) … ListObjectVersions not implemented`;
- `s3api head-object --key web-platform/sentry/terraform.tfstate` → 200;
- `s3api get-bucket-versioning` → `AccessDenied` (token scope; not decisive on its own, which is
  precisely why the control call matters).

The 2026-09-04 measurement recorded in #7836 **still holds**. This is a property of the bucket,
re-measured, not a vendor fact taken on trust.

**M5 — the six state objects, and the root count.** The bucket holds
`cla-evidence/`, `github/`, `telegram-bridge/`, `web-platform/rung2-rehearsal/`,
`web-platform/sentry/`, `web-platform/terraform.tfstate`. But
`git grep -ln 'soleur-terraform-state' -- '*.tf'` resolves to **five** roots — `telegram-bridge`
has no tracked source, having been removed in `dccc56dee` (#1586). The sixth object is an orphan
of a deleted root.

**M6 — `fallthrough_type` distribution in `issue-alerts.tf`.** 28 × `ActiveMembers`,
3 × `NoOne` — of which one is prose (a comment), one is `sentry_issue_alert.git_data_boot_warning`,
and one is `sentry_alert.byok_cap_exceeded`. Among the 27 adopted rules, `byok_cap_exceeded` is
indeed the only `NoOne`. Arithmetic closes: 26 + 2 = 28.

### Research Reconciliation — brief vs. codebase

| Claim as briefed | Measured reality | Plan response |
|---|---|---|
| "`sentry-create-gate.sh` runs only in the `plan_pr` job and the `apply` job has no create-side gate, so a `workflow_dispatch` would bypass it" | The gate runs in **both**: `apply-sentry-infra.yml` `plan_pr` (diff `origin/$BASE_REF...HEAD`) and `apply` (diff `HEAD~1 HEAD`, under the comment "Guard A(i) — the diff-matched create gate, ported from `plan_pr`"). The briefed sentence describes the state **before** that port. | The conclusion — ship through a PR — is kept, on *correct* grounds (below). The stale rationale is not repeated anywhere. |
| "ALL SIX ROOTS on `soleur-terraform-state`" | **Five** roots. `telegram-bridge` was deleted in #1586; only its state object survives. | #7836 scoped to five roots + a noted orphan object. |
| "`byok-cap-exceeded` … in a project whose sibling comment records that no ownership rule exists — i.e. a BYOK spend-cap breach may page nobody" | The ownership-rule limb is **true** (M3). The inference is not: the `NoOne` is documented design intent in two places, and `cap-exceeded` means the cap *held*. | #7829 re-scoped from "flip it" to "settle it with evidence" — see the decision below. |
| Sentry README: "this root declares **27 `sentry_alert` + 2 `sentry_issue_alert`**" | 3 `sentry_issue_alert` (M1). `git_data_boot_warning` landed in `0f39b7aa2` (#7805), an ancestor of the adoption commit. | In-scope doc correction. |
| `issue-alerts.tf` has 28 `destroy = false` but 27 `removed{}` blocks | The 28th is at line 27, **inside a comment** in the file header. No stray lifecycle guard is at risk. | No action; the header comment is rewritten anyway. |

### Property List (Phase 0.6b)

1. The Sentry root can be rebuilt from an empty state using only its committed `.tf` files.
2. Whoever must act on a BYOK cap-exceeded event is a written-down decision, not an accident.
3. A `scheduled-sentry-alert-drift` run that never happens is visible.
4. An operator following the documented state-recovery procedure executes commands that work.
5. Every live artifact asserting the retired mechanisms still exist is corrected in the same change.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why it is cut |
|---|---|---|
| A new guard counting `^import {` / `^removed {` in `issue-alerts.tf` | (1) | Nothing to protect: `sentry-adoption-plan-assert.sh` already self-skips post-adoption by design and names #7826 in its own header, and `sentry-create-gate.sh` already catches the one dangerous outcome (an unexplained create) on both PR and apply. A static counter would assert the absence of text, not the safety property. |
| A shared cross-root `ROLLBACK.md` | (4) | Four of five roots have no rollback section at all and two have no README. The false claim exists in exactly one README section plus one ADR; the ADR is the authority every backend comment defers to. One section + one ADR amendment covers it. |
| Promoting `sentry-forget-import-bijection.sh` to a direct workflow call | — | It carries a deliberate vacuity floor (`exit 1` on zero forgets **and** zero imports). It is safe only because it is reached solely through the self-skipping adoption assert. Wiring it directly would red every post-adoption plan permanently. Explicitly **not** done. |
| Editing the dated plans/brainstorms that carry the R2-versioning assumption | (5) | They are point-in-time records of what was believed on their date. The live surfaces (ADR, README, Art. 30 register, spec AC) are corrected instead; the residual-grep AC carves the dated artifacts out. |

### Value-Proposition Measurement (Phase 0.6c)

The combined change's justification is correctness and reproducibility, not cost or latency, so
Phase 0.6c has nothing to quantify. The one figure worth recording is blast radius rather than
saving: the plan is expected to be `1 to add, 0 to change, 0 to destroy`, against 27 live paging
rules that must not move.

### Guards and suites in the blast radius

| Artifact | What it asserts | Effect of this change |
|---|---|---|
| `scripts/sentry-adoption-plan-assert.sh` | AC2/AC10 — an adoption plan is exactly 27 forgets + 27 matching imports | Flips PASS → SKIP. Self-skipping by design; its header names #7826. **Keep the `27` argument at both call sites** — it is `${2:?}`, required, and the skip fires after argument parsing. |
| `scripts/sentry-forget-import-bijection.sh` | AC3 — forget/import sets pair 1:1 | Never reached post-adoption. Do not promote to a direct call. |
| `scripts/sentry-create-gate.sh` | Every planned create is explained by an added `+resource` block in the diff | **Fires** on this change (one create). Passes because the diff adds the monitor's resource block. Would fail on any create arising from a pure deletion — which is exactly the 27-collision signal. |
| `scripts/sentry-issue-alert-create-tripwire.sh` | No run ever creates a `sentry_issue_alert` | Unaffected. Its error text carries the stale "Only two sentry_issue_alert resources may exist" — in-scope prose fix. |
| `scripts/sentry-monitor-binding-gate.sh` | AC11 — every `sentry_alert` binds the expected issue-stream detector | Unaffected. |
| `tests/scripts/test-sentry-alert-adoption-guards.sh` | 32 tests over synthesized fixtures | Never reads `issue-alerts.tf`. Unaffected. |
| `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` | Every workflow `monitor-slug:` has a `sentry_cron_monitor` in `cron-monitors.tf`; and the `name`-attr count equals the resource count | **Satisfied by** adding the monitor. The second assertion means the new `name = "..."` must sit inside the resource block and no `name = "..."` may appear in the surrounding comment. |
| `apps/web-platform/test/server/inngest/function-registry-count.test.ts` test `(c2)` | Every `cron-monitors.tf` resource name maps to a registered Inngest cron slug **or** appears in `NON_INNGEST_MONITORS` | **Goes RED** unless `scheduled-sentry-alert-drift` is added to `NON_INNGEST_MONITORS`. This is the orphan-suite the change must not miss. |
| `.github/workflows/infra-validation.yml` `validate` | `terraform fmt -check -recursive` over `apps/*/infra/**` | Leave no doubled blank lines where the two banner comments are removed. |
| `.github/workflows/apply-sentry-infra.yml` AC17 | `terraform state list` shows 27 `sentry_alert` and a **hardcoded 2** `sentry_issue_alert` | Reality is 3 (M1), so this step reds on any `push: main` apply of this root. It is PR 7866's fix and **this change may not touch that file.** This is the mechanism behind the merge gate. |

### Institutional learnings that apply

- `knowledge-base/engineering/architecture/decisions/ADR-006-terraform-remote-backend-r2.md` — the
  authority for the state backend, and the source of the false versioning claim. Status `active`.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — canonical for the
  provider, the alert-rule semantics and the import-only posture. Its §834-841 asserts the root is
  "not reproducible from zero" while the blocks remain; that sentence becomes past tense here.
- `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` — the house pattern
  for documenting an R2 S3-API gap (`get-object-lock-configuration` → `NotImplemented`). The
  replacement text should read like this.
- `knowledge-base/project/learnings/2026-05-16-prose-contract-vs-executable-check-dimension-drift.md`
  — records why the existing runbook says "NOT `apply -refresh-only`": it reconciles state *from*
  the API, the wrong direction for a restore. That caveat must survive the rewrite.
- `knowledge-base/project/learnings/workflow-issues/2026-08-03-blanket-renumber-rewrote-other-work-and-a-count-certified-it.md`
  — a residual-zero count AC certifies the wrong property. Assert the sentences the diff *adds*, not
  only the disappearance of the old ones.
- `knowledge-base/project/learnings/best-practices/2026-06-03-path-rename-sweep-exclude-own-migration-artifacts.md`
  — carve this feature's own plan/spec artifacts out of any residual-zero AC.
- `knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md` — the one
  "restore state" gesture in the repo that actually works: `terraform state pull` to a local file,
  `terraform state push` to restore. It is a local backup, not an R2 object version.
- `knowledge-base/project/learnings/2026-03-21-terraform-state-r2-migration.md` and
  `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md`
  — `doppler run --name-transformer tf-var` rewrites `AWS_ACCESS_KEY_ID` to `TF_VAR_aws_access_key_id`
  and breaks backend auth. R2 credentials must be exported *outside* the transformer. Any command in
  the replacement runbook must obey this.

### Conventions carried from AGENTS.md / the codebase

- `cq-cite-content-anchor-not-line-number` — every citation in the finished artifacts anchors on
  quoted content, not a line number.
- `cq-assert-anchor-not-bare-token` and the AC input-scope rule — an AC claiming a CI gate is green
  must run that gate's own invocation, not a hand-enumerated reconstruction of its inputs.
- `hr-no-dashboard-eyeball-pull-data-yourself` — the ownership question was answered by an API call
  with a control probe, not by reading a dashboard.
- Sentry cron-monitor house style (`cron-monitors.tf`, 55 resources): attributes in the fixed order
  `organization`, `project`, `name`, `schedule = { crontab = … }`, `checkin_margin_minutes`,
  `max_runtime_minutes`, `failure_issue_threshold`, `recovery_threshold`, `timezone`; values aligned
  to the width of `failure_issue_threshold`; no `slug`, `schedule_type`, `owner` or `lifecycle`
  attribute is used anywhere in the file; `timezone = "UTC"` and both thresholds `1` on all 55.
- Heartbeat step house style (6 sibling workflows): step named exactly `Sentry check-in (final)`,
  last step in the job, `if: always()`, `continue-on-error: true`, and a status expression that is an
  **allowlist** of good verdicts mapping to `'ok'` with everything else — including an unset output —
  falling to `'error'`.
- Slug convention: the workflow filename minus `.yml`.

### Open code-review overlap

Checked all 63 open `code-review` issues against every path in `## Files to Edit` /
`## Files to Create` (two-stage `gh issue list --json` then standalone `jq --arg`). **None.**

*(Lane note: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` fail-closed
per the TR2 rule.)*

## Late Reconciliation — three more briefed claims that did not survive

These are in addition to the table under `## Research Insights`. All were measured after that table
was written, and each one changes the work rather than merely annotating it.

| Claim as briefed | Measured reality | Plan response |
|---|---|---|
| #7829: `NoOne` on `byok_cap_exceeded` may be a defect — "a BYOK spend-cap breach currently pages no one" | The **outcome** is real; the **defect** framing is not. `NoOne` here is a documented, deliberate severity split. | **No config change.** Record the verification in-file so it is not re-filed. See §"#7829 resolves against the change". |
| #7836: "**every** Terraform root in this repo has a rollback runbook that cannot run" | Exactly **one** root has a rollback section at all (`infra/github/README.md` §"Phase 5 — Rollback"). Four of five live roots have no rollback section; two have no README. | Scope the repair to that one README **plus ADR-006**, which is where the false capability claim actually originates. |
| #7836: `apply-sentry-infra.yml` carries the stale assumption | It carries the **correct** statement already (anchor: *"Nor is R2 a restore path."*, naming `NotImplemented`, the 2026-09-04 measurement, the passing control, and #7836). | **No edit.** It is the house precedent the replacement text should read like — and it is the one file this change set must not touch (PR 7866 owns it). |

### #7829 resolves against the change

The brief asked to verify the premise before editing. The premise has two limbs and they resolve
differently:

- **Limb 1 — no ownership rule — TRUE.** Measurement M3: the ownership endpoint returns HTTP 200
  with `"raw":null` and `"schema":null`, against a passing control probe on the project itself. So
  `target_type = "issue_owners"` resolves to nobody and `fallthrough_type` alone decides delivery.
- **Limb 2 — therefore this is a defect — FALSE.** `issue-alerts.tf` documents the exact opposite,
  twice, in prose written by the author of these rules:
  - At the `NoOne` semantics comment: *"`fallthrough_type = "NoOne"` is what makes this NON-paging:
    IssueOwners has no ownership rule on this project, so the fatal router's "ActiveMembers"
    fallthrough pages the solo founder. NoOne means it lands in the issue stream to be read, not
    pushed. **That is the whole severity split.**"*
  - Directly above the resource itself, as one half of a numbered pair: *"Rule 1 — GDPR Art. 33
    breach … **Highest urgency**: tight frequency + notify ActiveMembers fallthrough"* versus
    *"Rule 2 — BYOK delegation cap exceeded (hourly | daily). **Lower urgency**: wider frequency +
    quieter `NoOne` fallthrough."*

The file therefore already answers the issue's own step 2 ("Confirm intent"): the setting is
intentional, its rationale is recorded at the resource, and it is contrasted explicitly against the
one rule in the pair that *is* meant to page. Flipping it to `ActiveMembers` would override a
recorded design decision and start paging the founder on every spend-cap breach — a live paging
change made on a premise the codebase falsifies.

**Deliverable for #7829 is therefore a verification record, not a config change**: a short comment at
the resource citing #7829, M3, and the Rule 1 / Rule 2 split, so the next reader who notices the
`NoOne` outlier finds the answer instead of re-filing it. If the operator decides a spend-cap breach
*should* page, that is a new decision on a settled question, not this issue.

## User-Brand Impact

**If this lands broken, the user experiences:** a duplicated or missing live Sentry paging rule. The
worst instance is `byok-art-33-breach` — the rule that starts the GDPR Art. 33 72-hour notification
clock on a cross-tenant BYOK key leak. Removing an `import{}` for an address that was not actually
imported turns that address into a planned CREATE against the live object; the founder then has two
rules where one was reviewed, or a paging rule Terraform believes it owns and does not.

**If this leaks, the user's data is exposed via:** no new exposure surface. The change removes
hardcoded live Sentry instance ids from the repository (a small reduction), adds one cron monitor,
and rewrites two documentation surfaces. It introduces no new store, no new credential, and no new
egress path.

**Brand-survival threshold:** `single-user incident` — one founder losing Art. 33 paging is the
whole failure. `requires_cpo_signoff: true` is set in frontmatter accordingly, and
`user-impact-reviewer` is expected at review time.

## Acceptance Criteria

### Pre-merge (PR)

**AC1 — the 27 adoption blocks are gone, and nothing else went with them.**
`grep -c '^import {' apps/web-platform/infra/sentry/issue-alerts.tf` returns `0`;
`grep -c '^removed {' …` returns `0`;
`grep -c '^resource "sentry_alert"' …` still returns `27`;
`grep -c '^resource "sentry_issue_alert"' …` still returns `3`.
The three counts that must NOT change are asserted alongside the two that must, because a
residual-zero assertion alone certifies deletion, not correct deletion.

**AC2 — the deletion is exactly the trailing block, byte-anchored.** The file's last line is the
closing `}` of `resource "sentry_alert" "zot_mirror_fallback_rate"`'s predecessor block as it stands
before the banner, and `git diff --stat` on `issue-alerts.tf` shows deletions only (`0` insertions
other than the #7829 comment in AC6). The removed region begins at the banner comment
*"Forget the legacy addresses WITHOUT destroying the live objects."* and runs to EOF.

**AC3 — no hardcoded live instance id survives.**
`grep -c 'var.sentry_org}/[0-9]' apps/web-platform/infra/sentry/issue-alerts.tf` returns `0`.
This is the actual property #7826 exists to restore (the root is rebuildable from an empty state),
distinct from AC1's block count.

**AC4 — the file header no longer describes a mechanism that is gone.** The `ADOPTION MECHANISM`
paragraph is rewritten to past tense, and the sentence *"The 27 `import{}`/`removed{}` blocks stay in
config until AC15-AC22 pass on `main`"* is removed. `grep -c 'stay in config until' …` returns `0`,
and the replacement paragraph names #7826 and the date the blocks were retired. Assert the sentence
the diff **adds**, not only the disappearance of the old one.

**AC5 — `terraform fmt -check -recursive` passes** over `apps/web-platform/infra/**`, i.e. the
deletion left no doubled blank line where the two banner comments were.

**AC6 — #7829's verification is recorded at the resource.** A comment immediately above
`resource "sentry_alert" "byok_cap_exceeded"` cites #7829, the ownership-endpoint measurement (M3),
and the Rule 1 / Rule 2 severity split. `grep -c 'fallthrough_type = "NoOne"' …` still returns the
**same count as on `origin/main`** — this AC asserts the setting did **not** change.

**AC7 — the cron monitor exists and matches house style.**
`apps/web-platform/infra/sentry/cron-monitors.tf` gains exactly one
`resource "sentry_cron_monitor" "scheduled_sentry_alert_drift"` with
`name = "scheduled-sentry-alert-drift"`, `schedule = { crontab = "15 7 * * *" }` (matching the
Inngest trigger in `cron-sentry-alert-drift.ts`), `timezone = "UTC"`, both thresholds `1`, and
attributes in the fixed order the other 55 resources use. `grep -c '^resource "sentry_cron_monitor"'`
returns `56`.

**AC8 — the heartbeat step is the LAST step of the job, and its status is an allowlist.**
`.github/workflows/scheduled-sentry-alert-drift.yml` ends in a step named exactly
`Sentry check-in (final)` with `if: always()`, `continue-on-error: true`,
`uses: ./.github/actions/sentry-heartbeat`, `monitor-slug: scheduled-sentry-alert-drift`, and
`status: ${{ (steps.probe.outputs.verdict == 'clean' || steps.probe.outputs.verdict == 'drift') && 'ok' || 'error' }}`.
The expression is an **allowlist of good verdicts** — an unset output from a crashed probe falls to
`error`, which is the behaviour the sibling workflows' comments call load-bearing.

**AC9 — the `(c2)` phantom-monitor test passes.** `scheduled-sentry-alert-drift` is added to
`NON_INNGEST_MONITORS` in `apps/web-platform/test/server/inngest/function-registry-count.test.ts`
with a comment explaining the class: the heartbeat is posted by the **GHA runner**, not the Inngest
app process — `cron-sentry-alert-drift.ts` only dispatches and declares no `SENTRY_MONITOR_SLUG`,
exactly like `main-health-monitor` and `scheduled-supabase-advisor-scan`. Verified by running the
suite's own invocation, not a reconstruction of its inputs.

**AC10 — the parity suites pass unchanged in shape.**
`apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` passes, including
`tf name-attr extraction is pinned to the resource count` (56 names, 56 resources) and
`every workflow heartbeat slug has a cron-monitor in cron-monitors.tf`.

**AC11 — the two "no heartbeat" paragraphs are gone and replaced with what is now true.**
`grep -ci 'NO SENTRY CRON HEARTBEAT' .github/workflows/scheduled-sentry-alert-drift.yml` returns `0`;
a `grep` for the phrase *carries no sentry-heartbeat step* over
`apps/web-platform/server/inngest/functions/cron-sentry-alert-drift.ts`
returns `0`. Both files instead contain a sentence naming the monitor slug and what a missed
check-in now means. Assert the added sentences, not only the removals.

**AC12 — ADR-006's false capability claim is corrected.**
`knowledge-base/engineering/architecture/decisions/ADR-006-terraform-remote-backend-r2.md` no longer
asserts *"with bucket versioning"* in its `## Decision` or *"State loss eliminated via bucket
versioning"* in its `## Consequences`. Both are replaced with the measured posture and the gesture
that actually works. `grep -ci 'bucket versioning' <adr>` returns `0`, and the ADR gains an amendment
note dated 2026-09-06 citing #7836 and the `NotImplemented` measurement with its control.

**AC13 — the rollback runbook runs.** `infra/github/README.md` §"Phase 5 — Rollback" no longer
contains `list-object-versions` or `versionId`
(`grep -c 'list-object-versions\|versionId' infra/github/README.md` returns `0`). Steps 1–2 are
replaced by the take-a-snapshot-first gesture from the moved-block-wedge runbook
(`terraform state pull > …` before the risky apply; `terraform state push <file>` to restore), and
the existing step 3 caveat — *"NOT `apply -refresh-only`; the latter pulls state FROM the API and
would reconcile the rollback away"* — survives verbatim. The R2 credential constraint is stated: the
AWS keys must be exported **outside** `--name-transformer tf-var`, which would rewrite them to
`TF_VAR_aws_*` and silently break backend auth.

**AC14 — the runbook is honest about what was lost.** The replacement text states plainly that R2
provides **no** point-in-time recovery, so the snapshot is the operator's responsibility *before* the
apply — rather than implying a restore path that does not exist. It reads like the existing correct
precedent in `apply-sentry-infra.yml` (anchor: *"Nor is R2 a restore path."*).

**AC15 — the combined plan shape is stated and matched.** The PR body records the expected
`plan_pr` output — `1 to add` (the cron monitor), `0 to change`, `0 to destroy` — and the actual
`plan_pr` run matches it. **`0 to change` is the assertion that #7829 was not silently flipped.**
Any `to destroy` is an abort, not a discussion.

**AC16 — the create-side gate fires and passes for the right reason.**
`scripts/sentry-create-gate.sh` runs in the `plan_pr` job and passes because the single planned
create is explained by an added `+resource "sentry_cron_monitor"` block in the diff. Record the gate's
own output line, not a restatement of it.

### Merge gate (operator-mandated — blocks merge, does not block the PR)

**AC17 — live state still holds exactly 27 `sentry_alert` addresses** at merge time, re-measured
rather than carried from this plan (`terraform state list | grep -c '^sentry_alert\.'` → `27`), and
the 27 in state are the 27 whose blocks were deleted (the M2 address-set equality, re-run).

**AC18 — PR 7866 has merged AND the resulting apply on `main` is green.** Until then the merge is
**HELD** and the operator is told. Rationale: 7866 makes the AC17 workflow step derive its expected
counts from the `.tf` instead of a hardcoded `2`; while it is unmerged, every `push: main` apply reds
on a false alarm and the AC19/AC20 live-fidelity probe is **skipped** under an implicit `success()`.
Merging the 27-block removal into that state would leave the removal's own post-merge apply
unverifiable for a reason unrelated to the removal.

> **This AC depends on a concurrent session's PR and is therefore exempt from
> `cq-ac-must-not-depend-on-concurrent-sessions` only as a HOLD, never as a pass condition.** It can
> block the merge; it can never be marked satisfied by assumption.

### Post-merge

**AC19 — the post-merge apply on `main` is green**, and its AC17 step reports `27` / `3` derived (not
hardcoded). If it reds, roll forward — per AC12's own finding there is no state-restore path.

**AC20 — the monitor exists in Sentry and receives its first check-in** within one cron period
(next 07:15 UTC firing), verified by API read, not by dashboard eyeballing
(`hr-no-dashboard-eyeball-pull-data-yourself`).

## Guard Contract

### Guard 1 — `scheduled-sentry-alert-drift` dead-man's switch

**Property.** A `scheduled-sentry-alert-drift` run that was dispatched but never executed becomes
visible within the check-in margin, instead of being indistinguishable from a clean run.

**Assembly.** Not "the set of files I edited" — the chokepoint is the three-way agreement that a
check-in can arrive at all: (1) the heartbeat step must be the **terminal** step of the workflow's
only job under `if: always()`, so it runs on the drift path where an earlier step exits 1; (2) the
`monitor-slug:` in the workflow must equal the `name` of a `sentry_cron_monitor` that has **applied**
to Sentry; (3) the monitor name must be reachable by the `(c2)` allowlist or the suite reds. Any one
of the three silently disables the guard, and only (2) is currently asserted by an existing test.

**Mutation matrix** (each row MUST drive something RED):

| # | Mutation | Must red | Why this row exists |
|---|---|---|---|
| 1 | Delete `sentry_cron_monitor.scheduled_sentry_alert_drift` from `cron-monitors.tf` | `sentry-monitor-iac-parity` → *every workflow heartbeat slug has a cron-monitor* | The guard's backing resource |
| 2 | Typo the workflow's `monitor-slug:` to `scheduled-sentry-alert-drft` | same test | Slug agreement, not mere presence |
| 3 | **Move** the heartbeat step to before the `probe` step | new assertion (below) | **Order/lifetime row.** A delete-row cannot see this: `steps.probe.outputs.verdict` would be unset, the allowlist would resolve `error` on *every* run including clean ones, and the monitor would page continuously — a guard that is loud is still a broken guard |
| 4 | Drop `if: always()` from the heartbeat step | new assertion | On the drift path the job is already failing, so a plain-expression `if:` inherits `success()` and the step **skips** — producing a missed check-in for a run that did happen |
| 5 | Add a second workflow heartbeat slug with no monitor | `sentry-monitor-iac-parity` | Guard must not stop after the first member |

**Harness rows.**

- **Suite mutation → RED:** replace the parity test's slug extractor with `() => []`. The
  anti-vacuity case *"discovers the known workflow-heartbeat slug cohort"* must red — a suite that
  checks nothing must not report green.
- **Must-PASS non-canonical input:** an unrelated sibling (`scheduled-terraform-drift`, whose monitor
  is in `NON_INNGEST_MONITORS` and whose heartbeat is also terminal) must continue to PASS. This
  proves the new assertions reject the defect rather than rejecting everything.

**New assertion required by rows 3 and 4.** No existing test asserts heartbeat step **position** or
`if: always()` for any workflow. Add one to `sentry-monitor-iac-parity.test.ts`: for every
`.github/workflows/*.yml` containing a `sentry-heartbeat` step, that step is the last step of its job
and carries `if: always()` + `continue-on-error: true`. **Run it against the existing cohort first.**
If pre-existing siblings violate it, narrow the assertion to this workflow and file a scope-out for
the rest rather than widening this PR into a fleet fix.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — **+1** `sentry_cron_monitor` resource. No new
  provider, no new version pin, no new variable, no new secret.
- `apps/web-platform/infra/sentry/issue-alerts.tf` — deletions only (27 `import{}` + 27 `removed{}` +
  two banner comments), plus one comment addition for #7829.

### Apply path

Auto-apply on merge via `.github/workflows/apply-sentry-infra.yml` (`push: main`, `paths:`-scoped to
`apps/web-platform/infra/sentry/**`). **Not** a `workflow_dispatch` — and note the brief's stated
reason for that was wrong in detail while right in conclusion: `sentry-create-gate.sh` runs in
**both** the `plan_pr` and `apply` jobs (measured), so the create-side gate is not actually bypassed
by a dispatch. The binding reason to go through a PR is that `plan_pr` is where a human reads the
plan output before 27 blocks disappear.

Expected blast radius: `1 to add, 0 to change, 0 to destroy`. Downtime: none — a cron monitor is a
Sentry-side object with no runtime coupling.

### Distinctness / drift safeguards

- The 27 `sentry_alert` resources keep their `lifecycle { ignore_changes = [environment] }`; nothing
  in this change touches those blocks.
- `sentry-destroy-required` and `sentry-create-gate.sh` remain the merge-time gates. This change is
  precisely the class the create gate exists for, and it should show exactly one explained create.
- No `-target=` allow-list change is needed: `sentry_cron_monitor.*` is already in the applied set.

### Vendor-tier reality check

No tier gate applies — `sentry_cron_monitor` is already used 55 times on the current plan.

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in for monitor slug `scheduled-sentry-alert-drift`
  cadence: daily, 15 7 * * * UTC (matches the Inngest trigger in cron-sentry-alert-drift.ts)
  alert_target: Sentry missed-check-in issue (failure_issue_threshold = 1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (missed check-in) + the workflow's own two GitHub-issue filers
  fail_loud: true — the heartbeat's status expression is an allowlist; an unset probe
    output resolves to `error` rather than to `ok`
failure_modes:
  - mode: the Inngest dispatch is accepted but no GHA run happens
    detection: missed Sentry check-in (this is the gap #7834 closes; nothing detects it today)
    alert_route: Sentry monitor issue
  - mode: the run happens and the probe cannot reach Sentry (`unavailable`)
    detection: heartbeat posts `status=error` AND the existing probe-unavailable issue filer
    alert_route: Sentry monitor + GitHub issue
  - mode: the run happens and finds real drift (`drift`)
    detection: heartbeat posts `status=ok` (the job ran); the drift issue filer routes the finding
    alert_route: GitHub issue only — deliberately NOT a monitor error, per the
      drift/error split scheduled-terraform-drift.yml documents
  - mode: the heartbeat step itself cannot reach Sentry ingest
    detection: `::warning::` from the composite action, step-level `continue-on-error: true`
    alert_route: run log warning — deliberately does not red an otherwise-green probe
logs:
  where: GitHub Actions run log for scheduled-sentry-alert-drift; Sentry Crons monitor history
  retention: GHA default (90d); Sentry per-plan
discoverability_test:
  command: >-
    grep -c 'scheduled-sentry-alert-drift' apps/web-platform/infra/sentry/cron-monitors.tf
    .github/workflows/scheduled-sentry-alert-drift.yml
  expected_output: both files report >= 1 (the slug agreement the guard rests on)
```

## Encryption Posture

Detection fires (`.tf` files in Files to Edit). No new persistent store and no new cross-component
connection is introduced, so the posture is inherited rather than declared fresh:

```yaml
at_rest:
  - store: Terraform state for apps/web-platform/infra/sentry (existing)
    mechanism: R2 server-side encryption (provider-managed), unchanged by this PR
    evidence: ADR-006 as amended by AC12 — which is precisely this PR correcting the
      record that R2 offers object VERSIONING; encryption at rest is a separate property
      and is not touched here
    defends_against: at-rest disclosure from the storage provider's media
    does_not_defend: anyone holding the R2 credential; and — newly documented by AC12/AC14 —
      there is NO point-in-time recovery, so a bad state write is not undoable from R2
    disclosed_as: ADR-006 Consequences (rewritten by this PR)
    live_verification: `aws s3api list-objects-v2 --bucket soleur-terraform-state` (control,
      rc=0) alongside `list-object-versions` (NotImplemented, rc=254) — re-run at /work
in_transit:
  - connection: GHA runner -> Sentry ingest (heartbeat check-in), NEW call site, existing endpoint
    tls: yes (https, curl default verification)
    cert_verification: on
    does_not_defend: the monitor slug and status are not secret; the DSN public key is
      already a public-by-design credential
    disclosed_as: existing sentry-heartbeat composite action contract
```

No `exception` block: no `plaintext-exception` and no `cert_verification: off` in scope.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-006 (`ADR-006-terraform-remote-backend-r2.md`)** — in scope for this PR, not a follow-up.
This is the reversal case: the ADR's `## Decision` says the backend is *"Cloudflare R2 as remote
backend with bucket versioning"* and its `## Consequences` says *"State loss eliminated via bucket
versioning"*. Both are false and have been since the decision was taken — R2 does not implement the
S3 object-versioning API at all. Amend the `## Decision` to state the backend without the versioning
claim, rewrite the `## Consequences` line to the measured posture, and add a dated amendment note
citing #7836, the `NotImplemented` measurement, and the passing `list-objects-v2` control.

No **new** ADR is warranted: this corrects a recorded decision's factual basis; it does not make a
new architectural choice. (Consequently there is no ordinal to collide — the ADR-ordinal gate has
nothing to re-verify at ship.)

### C4 views

**No C4 impact — and here is what was checked**, against all three model files
(`model.c4`, `views.c4`, `spec.c4`), not a keyword grep:

- **External human actors:** none added or changed. The only human in the loop is the founder/operator,
  already modeled; the alert-recipient change that *would* have touched this (#7829's fallthrough)
  is explicitly NOT being made.
- **External systems / vendors:** Sentry and Cloudflare R2 are both already modeled as external
  systems. This PR adds no vendor and removes none. GitHub Actions is already modeled.
- **Containers / data stores:** none added. The cron monitor is an object inside the
  already-modeled Sentry system, at the same granularity as the 55 existing monitors — none of
  which are individually modeled, correctly.
- **Actor↔surface access relationships:** unchanged. No ownership, tenancy, or recipient boundary
  moves — AC6 asserts the paging recipient set is byte-identical.

No element description is falsified by this change.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** see `### Findings` below
**Assessment:** the change is infrastructure-and-documentation only, confined to one Terraform root
plus two documentation surfaces and two test allowlists. The load-bearing engineering judgments are
(a) that the 27-block deletion is gated on a re-measured live state rather than an inherited claim,
(b) that the new cron monitor is the `NON_INNGEST_MONITORS` class rather than a `SENTRY_MONITOR_SLUG`
producer, and (c) that #7829 resolves to no change.

### Product/UX Gate

Not applicable — the mechanical UI-surface scan over `## Files to Edit` / `## Files to Create`
matches no UI path (no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`), and the
change has no user-facing surface. Product assessed NONE by the semantic sweep and the mechanical
override did not fire.

## Open Code-Review Overlap

**None.** All 63 open `code-review` issues were checked against every path in `## Files to Edit`
using the two-stage `gh issue list --json` → standalone `jq --arg` form (single-stage `gh --jq`
with `--arg` does not forward the argument).

## Files to Edit

| File | Issue | Change |
|---|---|---|
| `apps/web-platform/infra/sentry/issue-alerts.tf` | #7826, #7829 | delete the trailing 27 `import{}` + 27 `removed{}` blocks and their two banner comments; rewrite the header's `ADOPTION MECHANISM` paragraph to past tense; add the #7829 verification comment above `byok_cap_exceeded` |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | #7834 | +1 `sentry_cron_monitor` resource in house style |
| `.github/workflows/scheduled-sentry-alert-drift.yml` | #7834 | delete the `NO SENTRY CRON HEARTBEAT` paragraph; append the terminal `Sentry check-in (final)` step |
| `apps/web-platform/server/inngest/functions/cron-sentry-alert-drift.ts` | #7834 | update the header paragraph that says the workflow carries no heartbeat |
| `apps/web-platform/test/server/inngest/function-registry-count.test.ts` | #7834 | add `scheduled-sentry-alert-drift` to `NON_INNGEST_MONITORS` with the class rationale |
| `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` | #7834 | add the heartbeat step-position + `if: always()` assertion (Guard 1 rows 3–4) |
| `knowledge-base/engineering/architecture/decisions/ADR-006-terraform-remote-backend-r2.md` | #7836 | amend `## Decision` + `## Consequences`; add dated amendment note |
| `infra/github/README.md` | #7836 | replace §"Phase 5 — Rollback" steps 1–2; preserve step 3's caveat |

**Files to Create:** none.

**Explicitly NOT edited:**

- `.github/workflows/apply-sentry-infra.yml` — owned by PR 7866 this session, and already carries the
  correct R2 statement. Editing it would conflict and is unnecessary.
- `knowledge-base/project/specs/feat-one-shot-7650-phase2-sentry-alert-import/tasks.md` — a
  point-in-time migration record; carved out per the Cut List and the
  "exclude own migration artifacts" rule.
- Dated plans and brainstorms carrying the old R2 assumption — same reason.

## Implementation Phases

**Phase 0 — re-measure before deleting anything.** Re-run the live-state probe: `terraform init
-lockfile=readonly` then `terraform state list`, and re-derive the M2 address-set equality (the 27
`sentry_alert.<label>` addresses in state `diff` empty against the 27 `resource` labels in the file).
Re-run the R2 versioning probe with its `list-objects-v2` control. **If the 27/27 equality does not
hold, stop** — the #7826 deletion is unsafe and only that issue is blocked; #7834 and #7836 continue.

**Phase 1 — #7836 (docs, no infra coupling).** Independent of everything else; do it first so a
Terraform surprise cannot strand it. Amend ADR-006, rewrite `infra/github/README.md` §Phase 5.

**Phase 2 — #7829 (verification record).** Add the comment above `byok_cap_exceeded`. No value
changes. This lands before the #7826 deletion so the comment's surrounding context is stable.

**Phase 3 — #7834 (the monitor + heartbeat), contract-first.** The `sentry_cron_monitor` resource
and the `NON_INNGEST_MONITORS` entry land **before** the workflow's heartbeat step, so the parity
suites never see a slug without a monitor. Then the workflow step, then the two prose paragraphs.
Then the new step-position assertion (Guard 1) — written from the design, before verifying it passes.

**Phase 4 — #7826 (the deletion), last.** Deleting the blocks is the only irreversible-feeling step
and the only one gated on Phase 0's measurement. Delete the trailing region, rewrite the header
paragraph, `terraform fmt`.

**Phase 5 — combined verification.** Run the affected suites, `terraform fmt -check -recursive`, and
read the `plan_pr` output against AC15's stated shape.

## Test Scenarios

1. **The deletion is clean.** After Phase 4, AC1's five counts hold and `git diff` shows no insertion
   in `issue-alerts.tf` other than the #7829 comment and the rewritten header paragraph.
2. **The plan shape is what was predicted.** `plan_pr` reports `1 to add, 0 to change, 0 to destroy`.
   A `1 to change` here means #7829 was flipped by accident and is an abort.
3. **The create gate passes for the stated reason.** `sentry-create-gate.sh` explains the single
   create by the added `+resource "sentry_cron_monitor"` block.
4. **Guard 1 row 3 (order).** Temporarily move the heartbeat step above the probe step; the new
   assertion reds. Restore.
5. **Guard 1 row 4 (`if: always()`).** Temporarily drop `if: always()`; the new assertion reds.
   Restore.
6. **Guard 1 row 1 (backing resource).** Temporarily delete the monitor resource; the parity test's
   *every workflow heartbeat slug has a cron-monitor* case reds. Restore.
7. **Harness anti-vacuity.** Stub the parity slug extractor to `() => []`; the cohort-discovery case
   reds.
8. **Must-PASS non-canonical.** `scheduled-terraform-drift` continues to pass every assertion,
   old and new.
9. **The rollback runbook is executable.** Every command in the rewritten §Phase 5 runs as written
   against the live bucket, read-only where possible (`terraform state pull` to a temp file is safe;
   `state push` is NOT exercised).
10. **The monitor receives its first check-in** at the next 07:15 UTC firing, read back by API.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| An address is un-imported and its `import{}` deletion becomes a live-colliding CREATE | Phase 0's M2 address-set equality is the gate, re-measured not inherited; AC15's `0 to change` and the create gate are the second and third nets |
| PR 7866 does not merge before this one is ready | AC18 HOLDS the merge and tells the operator. It is never marked satisfied by assumption |
| The new step-position assertion reds on pre-existing siblings | Planned for: narrow to this workflow and file a scope-out rather than widening this PR into a fleet fix |
| The `(c2)` classification is wrong and the monitor should declare a `SENTRY_MONITOR_SLUG` instead | The precedent comments for `main-health-monitor` and `scheduled-supabase-advisor-scan` state the class explicitly: the heartbeat is posted by the runner, not the app process. Same shape here |
| A reader later re-files #7829 | AC6's in-file comment is the mitigation — that is the whole deliverable for that issue |
| The rewritten runbook is itself wrong | AC13/AC14 require every command to be run as written; the `--name-transformer tf-var` credential trap is stated because it silently breaks backend auth |

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled above.
- **`terraform state push` is not in scope to test.** The rewritten runbook documents it; exercising
  it against a live root would be the exact destructive act the ADR amendment says is unrecoverable.
- **`apply-sentry-infra.yml` is off-limits this session.** PR 7866 owns it. Any urge to "also fix the
  AC17 constant here" is a merge conflict with a sibling that already fixed it better.
