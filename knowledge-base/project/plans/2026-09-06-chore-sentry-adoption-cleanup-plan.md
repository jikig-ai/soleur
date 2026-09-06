---
title: "chore(sentry-infra): retire the 27 adoption blocks, settle the byok-cap fallthrough, and heartbeat the drift cron"
date: 2026-09-06
slug: chore-sentry-adoption-cleanup
branch: feat-one-shot-7826-sentry-adoption-cleanup
issue: 7826
closes: [7826, 7829, 7834]
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

## Scope change after plan review — #7836 is split out

**This plan covers #7826, #7829 and #7834 only.** #7836 (the inoperable R2 state-rollback runbook)
moves to its own PR, tracked by
`knowledge-base/project/plans/2026-09-06-chore-r2-rollback-runbook-repair-plan.md`.

Both review lenses converged on the split independently, and a third fact settled it: #7836 shares no
file, no gate and no failure mode with the other three, yet under the single-PR shape it inherited
their merge hold on PR 7866 — holding a **GDPR Art. 30 register correction** hostage to an unrelated
Sentry apply. Operator confirmed the split.

`ADR-031-sentry-as-iac.md` stays **here**, not in the #7836 PR: its false sentences are about the
adoption blocks (*"the root is not reproducible from zero until they are removed"*), which is #7826's
story, not R2's.

## Late Reconciliation — briefed claims that did not survive

In addition to the table under `## Research Insights`.

| Claim as briefed | Measured reality | Plan response |
|---|---|---|
| #7829: `NoOne` on `byok_cap_exceeded` may be a defect — "pages no one" | The **outcome** is real; the **defect** framing is not. It is a documented, deliberate severity split. | **No config change.** Record the verification in-file and on the issue. See §"#7829 resolves against the change". |
| The `NoOne` intent is documented "twice" in `issue-alerts.tf` | **Once.** The `NoOne`-semantics comment sits above `sentry_issue_alert.git_data_boot_warning` — a different rule, a different family, landed later (#7805). It documents the house pattern, not this rule's intent. #7829 already cites it. | The load-bearing evidence is the single Rule 1 / Rule 2 comment plus M3. Stated accurately below; AC6 must not repeat the mis-citation. |

### #7829 resolves against the change

The brief asked to verify the premise before editing. Two limbs, resolving differently:

- **Limb 1 — no ownership rule — TRUE.** M3: the ownership endpoint returns HTTP 200 with
  `"raw":null` and `"schema":null`, against a passing control probe on the project itself. So
  `target_type = "issue_owners"` resolves to nobody and `fallthrough_type` alone decides delivery.
- **Limb 2 — therefore a defect — FALSE.** The comment directly above the resource is one half of a
  numbered pair: *"Rule 1 — GDPR Art. 33 breach … **Highest urgency**: tight frequency + notify
  ActiveMembers fallthrough"* versus *"Rule 2 — BYOK delegation cap exceeded (hourly | daily).
  **Lower urgency**: wider frequency + quieter `NoOne` fallthrough."* The severity split is the
  design, stated at the resource, contrasted against the one rule of the pair that *is* meant to page.

Flipping to `ActiveMembers` would override a recorded decision and start paging the founder on every
spend-cap breach. **The deliverable is a verification record in two places** — the `.tf` (for the next
reader of the file) and a closing comment on #7829 (for the next triager, who will never open the
`.tf`). M3 is dated because it decays: adding a Sentry ownership rule later moots `NoOne` in the
other direction.

## User-Brand Impact

**If this lands broken, the user experiences:** a duplicated, destroyed or dark live Sentry paging
rule. The worst instance is `byok-art-33-breach`, which starts the GDPR Art. 33 72-hour notification
clock on a cross-tenant BYOK key leak. Two symmetric ways to get there: deleting an `import{}` for an
address that was never imported plans a **CREATE** colliding with the live rule; deleting a
`removed{}` whose forget never executed leaves an orphan state entry with no config and plans a
**DESTROY** of a live rule.

**If this leaks, the user's data is exposed via:** no new exposure surface. Net reduction — hardcoded
live Sentry instance ids leave the repository. No new store, credential, or egress path.

**Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true`;
`user-impact-reviewer` expected at review.

## Acceptance Criteria

### Pre-merge (PR)

**AC1 — the 27 adoption blocks are gone, and nothing else went with them.**
`grep -c '^import {' …/issue-alerts.tf` → `0`; `grep -c '^removed {' …` → `0`;
`grep -c '^resource "sentry_alert"' …` → **still 27**; `grep -c '^resource "sentry_issue_alert"' …`
→ **still 3**. The three counts that must not change are asserted alongside the two that must —
a residual-zero assertion alone certifies deletion, not correct deletion.

**AC2 — the deletion region is byte-anchored, and the anchor is the right block.**
Delete from the banner comment *"Forget the legacy addresses WITHOUT destroying the live objects."*
through EOF (including the blank line preceding the banner). **The new last line is the closing `}`
of `resource "sentry_alert" "zot_mirror_fallback_rate"`, which is itself the final resource block** —
nothing sits between it and the banner. `git diff --stat` shows deletions only in this region.
> Plan-review caught this AC naming *"`zot_mirror_fallback_rate`'s predecessor"*, which resolves to
> `workspaces_luks_drift` — i.e. it instructed deleting a live paging rule. AC1 and AC15 would have
> caught it, but the AC billed as byte-precise was off by one block.

**AC3 — no hardcoded live instance id survives.**
`grep -c 'var.sentry_org}/[0-9]' …/issue-alerts.tf` → `0`. This is the property #7826 exists to
restore (the root is rebuildable from empty state), distinct from AC1's block count.

**AC4 — every stale claim in the file header is corrected, not just the mechanism paragraph.**
Three separate falsehoods, all in scope:

1. the `ADOPTION MECHANISM` paragraph → past tense;
2. the sentence *"The 27 `import{}`/`removed{}` blocks stay in config until AC15-AC22 pass on `main`"*
   → removed (`grep -c 'stay in config until'` → `0`);
3. the opening enumeration *"27 of the 29 rules are now managed as `sentry_alert` … **Two** remain on
   the deprecated `sentry_issue_alert` … `auth-per-user-loop` and `sandbox-startup-failure`"* →
   corrected to **three** survivors, naming `git_data_boot_warning` as the third.
Assert the sentences the diff **adds**, not only the disappearance of the old ones. The replacement
must also record that each address's adopted live id now exists only in state and in the committed
capture — the `import{}` blocks were the last committed record of that mapping.

**AC5 — `terraform fmt -check -recursive`** passes over `apps/web-platform/infra/**`.

**AC6 — #7829's fallthrough is provably untouched, asserted on the DIFF's NON-COMMENT lines.**

```bash
git diff origin/main -- apps/web-platform/infra/sentry/issue-alerts.tf \
  | grep -E '^[+-]' | grep -vE '^[+-][[:space:]]*#' | grep -c 'fallthrough_type'
```

→ `0`. **Mutation-proven at implementation time:** `0` at baseline with AC7's comment present,
`2` under a `NoOne` → `ActiveMembers` flip, `0` again after a byte-identical restore.

> **Corrected during /work — the plan-review version of this AC was itself defeated by AC7.**
> The reviewed form omitted the comment filter and returned **2**, because AC7 *requires* a comment
> citing the Rule 1 / Rule 2 split and that split is literally about `fallthrough_type`. So the two
> ACs collided: satisfying AC7 reddened AC6 on a correct change. This is the same defect class one
> level up from the one plan review caught — a predicate that matches the TOKEN rather than the
> INVARIANT. The invariant is "no attribute ASSIGNMENT changed", and an assignment is not a comment,
> so the fix is to exclude comment lines rather than to weaken the assertion or drop the citation.
> A file-wide `grep -c 'fallthrough_type = "NoOne"'` is **defeated by this PR's own mandated comment**.
> It returns 3 today (one comment at the `git_data_boot_warning` semantics note, plus the two real
> values). AC6 requires adding a comment that quotes the literal → count becomes 4 → the AC reds on a
> correct change. Worse, the failure direction: flip line 531 to `ActiveMembers` **and** add the
> quoting comment and the count stays 3 — **the AC passes on a flipped live paging rule.** The diff
> assertion is the invariant; the count is a co-varying proxy.

**AC7 — the verification record is written where each audience will find it.**
(a) A comment above `resource "sentry_alert" "byok_cap_exceeded"` citing #7829, the **dated** M3
measurement — endpoint path, `"raw":null` / `"schema":null`, and the passing control probe on
`/projects/jikigai-eu/web-platform/` — and the Rule 1 / Rule 2 split. It must **not** cite the
line-150 comment, which belongs to `git_data_boot_warning`; a reader who follows that lands on a
different rule and re-files the issue anyway.
(b) A closing comment on **#7829** carrying the same M3 evidence verbatim and the verdict. The
`.tf` comment does not reach a GitHub triager, and `closes: 7829` would otherwise shut the issue with
a link to a PR titled about retiring adoption blocks.

**AC8 — the cron monitor exists, matches house style, and pins its firing window.**
`cron-monitors.tf` gains exactly one `sentry_cron_monitor "scheduled_sentry_alert_drift"` with
`name = "scheduled-sentry-alert-drift"`, `schedule = { crontab = "15 7 * * *" }` (matching
`cron-sentry-alert-drift.ts`), `timezone = "UTC"`, both thresholds `1`, attributes in the fixed order
the other 55 use. `grep -c '^resource "sentry_cron_monitor"'` → `56`.
**`checkin_margin_minutes` and `max_runtime_minutes` are pinned explicitly**, not defaulted: the
check-in arrives after Inngest dispatch latency + GHA queue + up to `timeout-minutes: 10`. Adopt the
dispatch-hybrid siblings' generosity (`scheduled_terraform_drift` 60/15; `main_health_monitor` 90/65)
rather than a value copied from a `schedule:`-driven monitor, which would page the founder on queue
jitter. Add a comment noting `max_runtime_minutes` is **inert** here — a single terminal heartbeat
sends no `in_progress` check-in, so runtime is not actually monitored.

**AC9 — the heartbeat step: allowlist status, and a backstop on the drift route.**
`scheduled-sentry-alert-drift.yml` ends its job in a step named exactly `Sentry check-in (final)`,
`if: always()`, `continue-on-error: true`, `uses: ./.github/actions/sentry-heartbeat`,
`monitor-slug: scheduled-sentry-alert-drift`, and a status expression that is an **allowlist of good
verdicts** — `clean` and `drift` → `ok`, everything else including an unset output → `error`.
**Plus the drift backstop:** when the verdict is `drift` **and** the drift-issue filer's own step
outcome is `failure`, the status is `error`, not `ok`.
> Without the backstop, mapping `drift → ok` removes the last net under a route that can fail
> silently. The workflow's own header documents the hazard (`gh issue create` hard-fails on a closed
> milestone). Monitor says OK, no issue exists, and the run is one red row in a `workflow_dispatch`
> tab nobody subscribes to — a real `byok-art-33-breach` drift reaching nobody, with the monitor now
> affirmatively certifying health.

**AC10 — the `(c2)` phantom-monitor test passes.** `scheduled-sentry-alert-drift` is added to
`NON_INNGEST_MONITORS` in `function-registry-count.test.ts` with the class rationale: the heartbeat is
posted by the **GHA runner**, not the Inngest app process; `cron-sentry-alert-drift.ts` only
dispatches and declares no `SENTRY_MONITOR_SLUG` — same class as `main-health-monitor` and
`scheduled-supabase-advisor-scan`. Record why declaring a `SENTRY_MONITOR_SLUG` in the dispatcher
would be **actively wrong**: that const is consumed by `postSentryHeartbeat` in the app process, so a
dispatcher check-in would satisfy the monitor on *"the dispatch was accepted"* — the exact failure
mode #7834 exists to catch, producing a guard that is green precisely when the thing it watches is
broken. Verified by the suite's own invocation, not a reconstruction of its inputs.

**AC11 — the parity suites pass.** `sentry-monitor-iac-parity.test.ts` green, including
`tf name-attr extraction is pinned to the resource count` (56/56) and
`every workflow heartbeat slug has a cron-monitor in cron-monitors.tf`.
> AC10's earlier draft asserted "no `name = "..."` may appear in the surrounding comment." That is a
> phantom — `iacMonitorNames()` matches `/^\s*name\s*=\s*"([a-z0-9-]+)"/gm` and a `#`-prefixed line
> cannot match. Dropped so the implementer does not chase it.

**AC12 — the two "no heartbeat" paragraphs are replaced with what is now true.**
`grep -ci 'NO SENTRY CRON HEARTBEAT' .github/workflows/scheduled-sentry-alert-drift.yml` → `0`; the
matching paragraph in `cron-sentry-alert-drift.ts` no longer says the workflow carries no heartbeat.
Both instead name the monitor slug and state what a missed check-in means — **and state the limit**:
the monitor proves *a run happened in the window*, not *the scheduled dispatch fired*. The function
declares both `{ cron: "15 7 * * *" }` and a manual-trigger event, so one manual run satisfies the
monitor for the day. Inherent to heartbeat monitors; stated rather than left as an implied guarantee.

**AC13 — ADR-031's retired claims are corrected in the same change.**
`ADR-031-sentry-as-iac.md` no longer asserts *"the root is not reproducible from zero until they are
removed"* or *"The blocks stay in config until the post-merge verification passes; removing them
earlier turns any un-imported address into a planned CREATE"*. Both become past tense with a dated
note citing #7826. Without this the canonical ADR for this subsystem is false the moment the PR
merges, defeating the plan's own Property 5.

**AC14 — the two sibling artifacts that assert the retired counts are corrected.**
(a) `apps/web-platform/infra/sentry/README.md` — *"root declares **27 `sentry_alert` + 2
`sentry_issue_alert`** resources"* → `3`. Note the file **already contradicts itself today**: its
line 5 says `27 + 3 (30 total)`. Fix the contradiction, do not merely re-state one side.
(b) `scripts/sentry-issue-alert-create-tripwire.sh` — the error text *"Only two sentry_issue_alert
resources may exist (auth_per_user_loop, sandbox_startup_failure)"* → three, naming
`git_data_boot_warning`. **Prose only: the guard itself is sound** — it gates on any `create` action
for the type, never on a count of two, so this is a stale message, not a live defect.

**AC15 — the combined plan shape is stated, matched, and non-vacuous.**
The PR body records the expected `plan_pr` output and the actual run matches. The assertion is that
the literal string `Plan: 1 to add, 0 to change, 0 to destroy` **is present in a `plan_pr` job that
actually ran** — not merely that `1 to change` is absent.
> `plan_pr` is gated `if: github.event_name == 'pull_request' && needs.detect-changes.outputs.sentry
> == 'true'` and hard-refuses on fork PRs. A **skipped** job emits no `Plan:` line at all, so an
> absence assertion reads "no plan ran" as "clean."
> And `1 to change` is **not diagnostic**: it is a whole-root aggregate, and the three surviving
> `sentry_issue_alert` resources refresh through Sentry's deprecated endpoint. Live drift on any one
> yields `1 to change`. On that signal, **identify the resource** — do not abort as a #7829 flip.
> AC6's diff assertion is what actually decides the #7829 question.

**AC16 — the create-side gate fires and passes for the right reason.**
`scripts/sentry-create-gate.sh` runs in `plan_pr` and passes because the single planned create is
explained by the added `+resource "sentry_cron_monitor"` block. The gate is **address-matched**, not
count-matched (`grep -qE "^\+[[:space:]]*resource[[:space:]]+\"${type}\"[[:space:]]+\"${name}\""`), so
a spurious `sentry_alert.*` create cannot be explained away by the monitor block. Record the gate's
own output line.

### Merge gate (operator-mandated)

**AC17 — the #7826 precondition, BOTH limbs, re-measured not inherited.**
Issue #7826 states the precondition as a conjunction. Both limbs are required:

- **Limb 1a — the `sentry_alert` side.** `terraform state list | grep -c '^sentry_alert\.'` → `27`,
  and the M2 address-set equality re-run (the 27 in state are the 27 whose blocks were deleted).
- **Limb 1b — the `sentry_issue_alert` side, which the earlier draft omitted.**
  `terraform state list | grep '^sentry_issue_alert\.'` returns **exactly**
  `auth_per_user_loop`, `git_data_boot_warning`, `sandbox_startup_failure` — and no address matching
  any of the 27 `removed{}` from-labels. This is the precondition for deleting a `removed{}`: if one
  forget did not execute, its address sits in state with no config block once the `removed{}` goes,
  and Terraform plans a **DESTROY of a live paging rule**. The earlier draft called the 27-address
  equality "the strongest form of the precondition." It is one of two.
- **Limb 2 — field-level live fidelity.** Run `scripts/sentry-alert-live-fidelity.sh` directly
  (read-only, one GET) and record its verdict. The earlier draft substituted state *shape* for this.
  They are different properties: address-set equality cannot see a rule that was imported but is
  muted, renamed, or monitor-unbound. Limb 2 is also the limb that **demonstrably never ran
  machine-verified** — the post-merge apply's fidelity probe was skipped under an implicit
  `success()`, and exists only as a hand-check recorded in another PR's body.

**AC18 — the verification path exists, and the hold has an exit.**
Restated, because the earlier draft named an event that cannot occur: `apply-sentry-infra.yml`'s
`push:` trigger is `paths:`-scoped to `apps/web-platform/infra/sentry/**` and
`tests/scripts/lib/destroy-guard-filter-sentry.jq`. **PR 7866 touches only
`.github/workflows/apply-sentry-infra.yml` — neither path — so merging it fires no apply on `main`
and the hold would never lift.**

Satisfied by **either**:

1. 7866 merged **AND** a `workflow_dispatch` of `apply-sentry-infra.yml` on `main` reports AC17 green
   with derived counts (27/3). *(AC17's own error text says "not a `workflow_dispatch`" — that is
   about the `[ack-destroy]` path and does not apply to a no-change verification run. Stated inline so
   the operator does not refuse the only available satisfier.)*
2. **Escape hatch, needing nothing from 7866:** `gh workflow run scheduled-sentry-alert-drift.yml`
   runs the same `sentry-alert-live-fidelity.sh` and reaches a `clean` verdict.

If neither is available, the merge is HELD **and** the operator is told with a named next action.
A hold with no exit is how a P2 cleanup becomes permanently deferred. The mechanism is explicit:
do not run `gh pr merge --auto` until one of the two is recorded — this AC is prose, nothing in CI
enforces it, and `wg-verified-work-ships-without-asking` otherwise arms auto-merge on green checks.

### Post-merge

**AC19 — the post-merge apply on `main` is green**, its AC17 step reporting 27/3 derived. If it reds,
roll forward — per the #7836 finding there is no state-restore path.

**AC20 — the monitor receives its first check-in** within `checkin_margin_minutes` of the next
07:15 UTC firing (the margin AC8 pins — without it this AC is not evaluable), verified by API read,
never by dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Guard Contract

### Guard 1 — `scheduled-sentry-alert-drift` dead-man's switch

**Property.** A `scheduled-sentry-alert-drift` run that was dispatched but never executed becomes
visible within the check-in margin, instead of being indistinguishable from a clean run.

**Assembly.** Not the set of files edited — the chokepoint is the **four-way** agreement that a
truthful check-in can arrive: (1) the heartbeat step is terminal in its job under `if: always()`, so
it runs on the drift path where an earlier step exits 1; (2) the `monitor-slug:` equals the `name` of
an **applied** `sentry_cron_monitor`; (3) the monitor name is reachable by the `(c2)` allowlist;
(4) **the step id referenced in the heartbeat's `status:` expression exists in the same job and
precedes the heartbeat.** Any one silently disables the guard; only (2) is asserted today.

**Mutation matrix.**

| # | Mutation | Must red | Why this row exists |
|---|---|---|---|
| 1 | Delete `sentry_cron_monitor.scheduled_sentry_alert_drift` | parity: *every workflow heartbeat slug has a cron-monitor* | The backing resource |
| 2 | Typo the workflow's `monitor-slug:` | same | Slug agreement, not mere presence |
| 3 | **Move** the heartbeat above the `probe` step | new terminality assertion | **Order/lifetime row.** A delete row cannot see this: `verdict` unset → `error` on every run including clean ones — a guard that is loud is still broken |
| 4 | Drop `if: always()` | new `if:` assertion | On the drift path the job is already failing, so a plain `if:` inherits `success()` and the step **skips** — a missed check-in for a run that did happen |
| 5 | **Rename `id: probe` to `id: fidelity_probe`** without updating the `status:` expression | new id-reference assertion | **Rows 3–4 both pass while the guard is fully broken**: position green, `always()` green, monitor green — and the expression resolves `error` daily forever. The invariant is the reference, not the position |
| 6 | Add a second workflow heartbeat slug with no monitor | parity | Guard must not stop at the first member |

**Harness rows.**

- **Suite mutation → RED:** stub the parity slug extractor to `() => []`; the anti-vacuity case
  `expect(slugs.length).toBeGreaterThanOrEqual(4)` must red.
- **Must-PASS non-canonical input:** `main-health-monitor.yml` — it carries
  `if: ${{ always() && !inputs.dry_run }}` and a heartbeat that is terminal in its job. It must PASS,
  proving the new assertions reject the defect rather than rejecting everything.
  > The earlier draft named `scheduled-terraform-drift` as this control. **That was false** — its
  > `Sentry check-in (final)` is followed by `Enforce token-drift result`, whose own comment claims
  > terminality. The plan had selected as its must-PASS control the one sibling its proposed
  > assertion falsifies.

**The new assertion, specified from a measured cohort audit — not left as a contingency.**
Keyed on `uses: ./.github/actions/sentry-heartbeat` (the string `sentry-heartbeat` alone pulls in two
prose-only false members: `apply-web-platform-infra.yml` and this workflow's own current header).
Audit of all 11 heartbeat steps across 10 workflows:

| Property | Cohort status | Assertion scope |
|---|---|---|
| `continue-on-error: true` | **11/11** | cohort-wide |
| `if:` **contains** `always()` | **11/11** | cohort-wide |
| `if:` **equals** `always()` | 8/11 — `main-health-monitor`, `scheduled-supabase-advisor-scan`, `workspaces-luks-verify` carry `always() && <extra>` | **not** assertable; use *contains* |
| heartbeat terminal in its job | not universal — `scheduled-terraform-drift` has a documented step after it | **scoped to this workflow only** |
| step named `Sentry check-in (final)` | 10/11 (`workspaces-luks-verify` uses `Sentry Crons check-in`) | **scoped to this workflow only** |

Written **job-scoped and multi-heartbeat-aware** from the start (`scheduled-terraform-drift` carries
three occurrences across jobs; `scheduled-inngest-health` has five steps after its heartbeat in a
different job). The earlier "narrow if siblings violate" contingency is **dropped**: narrowing would
have made the must-PASS harness row untestable, because a narrowed assertion never evaluates a
sibling.

## Infrastructure (IaC)

### Terraform changes

- `cron-monitors.tf` — **+1** `sentry_cron_monitor`. No new provider, version pin, variable or secret.
- `issue-alerts.tf` — deletions only (27 `import{}` + 27 `removed{}` + banner), plus the #7829 comment
  and the header corrections.

### Apply path

Auto-apply on merge via `apply-sentry-infra.yml` (`push: main`, paths-scoped). Expected blast radius
`1 to add, 0 to change, 0 to destroy`; no downtime — a cron monitor has no runtime coupling.

> The brief's stated reason for requiring a PR was wrong in detail while right in conclusion:
> `sentry-create-gate.sh` runs in **both** the `plan_pr` and `apply` jobs, so a dispatch does not
> bypass the create gate. The binding reason is that `plan_pr` is where a human reads the plan output
> before 27 blocks disappear.

### Distinctness / drift safeguards

The 27 `sentry_alert` resources keep `lifecycle { ignore_changes = [environment] }`; untouched.
`sentry-destroy-required` and `sentry-create-gate.sh` remain the merge-time gates. No `-target=`
change needed — `sentry_cron_monitor.*` is already in the applied set.

### Vendor-tier reality check

No tier gate — `sentry_cron_monitor` is already used 55 times.

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in for monitor slug `scheduled-sentry-alert-drift`
  cadence: daily, 15 7 * * * UTC (matches cron-sentry-alert-drift.ts)
  alert_target: Sentry missed-check-in issue (failure_issue_threshold = 1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (missed check-in) + the workflow's two GitHub-issue filers
  fail_loud: true — the status expression is an allowlist; an unset probe output
    resolves to `error`, never to `ok`
failure_modes:
  - mode: the Inngest dispatch is accepted but no GHA run happens
    detection: missed Sentry check-in (the gap #7834 closes; nothing detects it today)
    alert_route: Sentry monitor issue
  - mode: the run happens and the probe cannot reach Sentry (`unavailable`)
    detection: heartbeat posts `status=error` AND the probe-unavailable issue filer
    alert_route: Sentry monitor + GitHub issue
  - mode: the run happens and finds real drift (`drift`)
    detection: heartbeat posts `status=ok` (the job ran); the drift filer routes the finding
    alert_route: GitHub issue — deliberately NOT a monitor error, per the drift/error
      split scheduled-terraform-drift.yml documents
  - mode: drift is found AND the drift-issue filer itself fails
    detection: heartbeat posts `status=error` (AC9 backstop)
    alert_route: Sentry monitor — without this the finding reaches nobody while the
      monitor certifies health
  - mode: the heartbeat step cannot reach Sentry ingest (secret outage, or curl failure
      under the step's continue-on-error)
    detection: NO CHECK-IN IS POSTED — with failure_issue_threshold = 1 this opens a
      Sentry missed-check-in issue, indistinguishable from "the runner never ran"
    alert_route: Sentry monitor issue (a false positive, but a LOUD one)
    note: >-
      An earlier draft recorded this as "run log warning — deliberately does not red an
      otherwise-green probe". That is true of the GHA RUN STATUS and false of the SENTRY
      MONITOR, which is the actual guard. A `::warning::` in a workflow_dispatch run log
      is not a route. Corrected at plan review.
logs:
  where: GitHub Actions run log; Sentry Crons monitor history
  retention: GHA default (90d); Sentry per-plan
discoverability_test:
  command: >-
    grep -c 'scheduled-sentry-alert-drift' apps/web-platform/infra/sentry/cron-monitors.tf
    .github/workflows/scheduled-sentry-alert-drift.yml
  expected_output: both files report >= 1 (the slug agreement the guard rests on)
```

## Encryption Posture

Detection fires (`.tf` in Files to Edit). No new persistent store and no new cross-component
connection; posture is inherited.

```yaml
at_rest:
  - store: Terraform state for apps/web-platform/infra/sentry (existing)
    mechanism: R2 server-side encryption (provider-managed), unchanged here
    evidence: ADR-006 — note its versioning claim is corrected by the SPLIT-OUT #7836 PR;
      encryption at rest is a separate property and is not touched by either PR
    defends_against: at-rest disclosure from the provider's media
    does_not_defend: anyone holding the R2 credential; and there is NO point-in-time
      recovery, so a bad state write is not undoable from R2
    disclosed_as: ADR-006 Consequences (rewritten by the #7836 PR)
    live_verification: `list-objects-v2` control (rc=0) alongside `list-object-versions`
      (NotImplemented, rc=254)
in_transit:
  - connection: GHA runner -> Sentry ingest (heartbeat), NEW call site, existing endpoint
    tls: yes (https, curl default verification)
    cert_verification: on
    does_not_defend: slug and status are not secret; the DSN public key is public by design
    disclosed_as: existing sentry-heartbeat composite action contract
```

No `exception` block: no `plaintext-exception`, no `cert_verification: off`.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-031 (`ADR-031-sentry-as-iac.md`)** — in scope here (AC13). It is the canonical ADR for
this subsystem and two of its sentences become false at merge. Content anchors, per
`cq-cite-content-anchor-not-line-number`: *"the root is not reproducible from zero until they are
removed"* and *"The blocks stay in config until the post-merge verification passes"*.

No **new** ADR: the cron monitor is the 56th instance of an existing pattern — no new service,
boundary, or vendor. Consequently no ordinal to collide, and nothing for `/ship`'s ADR-ordinal gate
to re-verify.

**ADR-006 is amended by the split-out #7836 PR, not this one.**

### C4 views

**No C4 impact.** Checked against `model.c4`, `views.c4`, `spec.c4` **and** `c4-model.md` (the view
page, added to the checked set at plan review — it is where an ADR-006 claim would live; its line
*"All infrastructure provisioned via Terraform with R2 remote backend (ADR-006, ADR-019)"* never
claimed versioning and survives intact).

- **External human actors:** unchanged. The only human is the founder/operator, already modeled. The
  one change that *would* have touched this — #7829's fallthrough — is explicitly not being made.
- **External systems / vendors:** `sentry` and `cloudflare` are already declared `system` with
  `#external`. None added or removed.
- **Containers / data stores:** none added. `spec.c4` has no element kind at monitor granularity; none
  of the 55 existing monitors is individually modeled, correctly.
- **Access relationships:** unchanged. No ownership, tenancy, or recipient boundary moves; AC6
  asserts the paging recipient set is byte-identical.

Positively: the `sentry` element description says the cron monitors are *"one per scheduled
workflow"* — mildly false today, since `scheduled-sentry-alert-drift` has none. This PR **repairs**
that rather than falsifying it.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** approved the three load-bearing judgments — the deletion gate (with the `removed{}`
limb added, now AC17 limb 1b), the `NON_INNGEST_MONITORS` classification (stated more strongly than
the plan had it: declaring a `SENTRY_MONITOR_SLUG` in the dispatcher would be *actively wrong*), and
the merge hold (correct in intent, unsatisfiable as drafted — now AC18). Complexity small-to-medium;
no hot-path DB write; breaking-change surface correctly identified as the 27 live paging rules.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Edit` matches no UI path
(`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`); Product assessed NONE and the
mechanical override did not fire.

## Open Code-Review Overlap

**None.** All 63 open `code-review` issues checked against every path in `## Files to Edit` via the
two-stage `gh issue list --json` → standalone `jq --arg` form.

## Files to Edit

| File | Issue | Change |
|---|---|---|
| `apps/web-platform/infra/sentry/issue-alerts.tf` | #7826, #7829 | delete the trailing 27 `import{}` + 27 `removed{}` blocks and banner; correct three header claims (AC4); add the #7829 verification comment |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | #7834 | +1 `sentry_cron_monitor`, margins pinned |
| `.github/workflows/scheduled-sentry-alert-drift.yml` | #7834 | delete the `NO SENTRY CRON HEARTBEAT` paragraph; add the terminal heartbeat step with the drift backstop |
| `apps/web-platform/server/inngest/functions/cron-sentry-alert-drift.ts` | #7834 | update the no-heartbeat paragraph; state the manual-trigger limit |
| `apps/web-platform/test/server/inngest/function-registry-count.test.ts` | #7834 | `NON_INNGEST_MONITORS` entry + class rationale |
| `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` | #7834 | the new job-scoped assertions (Guard 1 rows 3–5) |
| `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` | #7826 | past-tense the two retired claims; dated note |
| `apps/web-platform/infra/sentry/README.md` | #7826 | `27 + 2` → `27 + 3`; resolve the file's existing self-contradiction |
| `scripts/sentry-issue-alert-create-tripwire.sh` | #7826 | error text: two → three, naming `git_data_boot_warning` (prose only; the guard is sound) |

**Files to Create:** none.

**Explicitly NOT edited:**

- `.github/workflows/apply-sentry-infra.yml` — owned by PR 7866; already carries the correct R2
  statement. Editing it conflicts and is unnecessary.
- `ADR-006`, `infra/github/README.md`, `knowledge-base/legal/article-30-register.md`, and the two
  `feat-terraform-state-mgmt` spec files — **the split-out #7836 PR**.
- `knowledge-base/project/specs/feat-one-shot-7650-phase2-sentry-alert-import/tasks.md` — a
  point-in-time migration record, carved out per the Cut List.

## Implementation Phases

**Phase 0 — measure before deleting, both limbs.** Re-run `terraform init -lockfile=readonly` +
`terraform state list`; derive AC17 limb 1a (27-address equality) **and** limb 1b (exactly the three
`sentry_issue_alert` survivors, no `removed{}` from-label present). Then run
`scripts/sentry-alert-live-fidelity.sh` for limb 2 and record its verdict.

> **Abort contract — load-bearing, and the earlier draft had none.** If any limb fails, #7826 is
> blocked and **#7829 and #7834 continue** (Phase 2 touches only a comment; Phase 3 touches other
> files entirely). On that path you MUST, in the same commit: strip `7826` from the plan frontmatter
> `closes:` **and** from the PR body, and post the Phase 0 measurement as a comment on #7826.
> Otherwise merging auto-closes #7826 with zero work done — destroying the only artifact recording
> that 27 blocks still pin hardcoded live ids and the root is not rebuildable from zero.
> The reduced AC set on that path is AC7–AC12 and AC15–AC16; AC1–AC6, AC13, AC14 and AC17–AC20 do not
> apply. **AC15 cannot discriminate this path** — the expected plan shape is `1 to add, 0 to change,
> 0 to destroy` either way — so the `closes:` edit is the only thing preventing a false close.

**Phase 1 — cohort audit (already performed at plan time; re-confirm).**
`grep -l 'uses: ./.github/actions/sentry-heartbeat' .github/workflows/*.yml`, then per job check
terminality and `if:` shape. The assertion is written pre-narrowed from this table, not discovered.

**Phase 2 — #7829 verification record.** The `.tf` comment (AC7a). No value changes. Lands before the
Phase 4 deletion so its surrounding context is stable. The #7829 issue comment (AC7b) is posted at
ship, when the PR number exists.

**Phase 3 — #7834, contract-first and test-first.** In order: the `sentry_cron_monitor` resource →
the `NON_INNGEST_MONITORS` entry → **the new parity assertions (written from the design, observed
RED against the not-yet-added step)** → the workflow heartbeat step + drift backstop → the two prose
paragraphs. Writing the assertion before the step it constrains is what lets it observe RED against
the real absence rather than only against a temporarily-mutated tree (`cq-write-failing-tests-before`).

**Phase 4 — #7826 deletion, last.** Delete the banner→EOF region, correct the three header claims,
amend ADR-031, fix the README and tripwire text, `terraform fmt`.

**Phase 5 — combined verification.** Affected suites, `terraform fmt -check -recursive`, and read
`plan_pr` against AC15.

## Test Scenarios

1. **Deletion is clean.** AC1's five counts hold; `git diff` shows no insertion in `issue-alerts.tf`
   beyond the #7829 comment and the header corrections.
2. **Plan shape matches.** `plan_pr` prints `Plan: 1 to add, 0 to change, 0 to destroy` **from a job
   that ran**. On `1 to change`, identify the resource — do not assume a #7829 flip.
3. **#7829 is provably untouched.** AC6's diff assertion returns `0`.
4. **Create gate passes for the stated reason**, address-matched to the added monitor block.
5. **Guard 1 row 3 (order).** Move the heartbeat above the probe; the terminality assertion reds.
6. **Guard 1 row 4 (`always()`).** Drop `if: always()`; the `if:` assertion reds.
7. **Guard 1 row 5 (id reference).** Rename `id: probe` without updating `status:`; the id-reference
   assertion reds. Rows 3 and 4 stay green — that is the point.
8. **Guard 1 row 1.** Delete the monitor resource; the workflow-slug-parity case reds.
9. **Harness anti-vacuity.** Stub the slug extractor to `[]`; the cohort-discovery case reds.
10. **Must-PASS non-canonical.** `main-health-monitor.yml` passes every assertion, old and new.
11. **First check-in** arrives within the pinned margin of the next 07:15 UTC firing, read by API.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| An `import{}` deletion becomes a live-colliding CREATE | AC17 limb 1a re-measured; AC15 `0 to change`; the address-matched create gate |
| A `removed{}` deletion becomes a DESTROY of a live rule | **AC17 limb 1b** — the limb the earlier draft omitted; plus `0 to destroy` and `sentry-destroy-required` |
| A rule is in state but muted/renamed/unbound — invisible to address-set equality | **AC17 limb 2** runs the field-level fidelity probe directly |
| PR 7866 stalls | AC18's escape hatch (`scheduled-sentry-alert-drift.yml` runs the same probe and needs nothing from 7866) |
| Phase 0 aborts and the PR silently closes #7826 anyway | The abort contract's mandatory `closes:` + PR-body strip and issue comment |
| Drift found but the issue filer fails | AC9's backstop posts `status=error` |
| A future edit renames `id: probe` and darks the guard | Guard 1 row 5's id-reference assertion |
| The adopted live-id mapping is lost with the `import{}` blocks | AC4 records that it now lives in state and the committed capture |

## Sharp Edges

- **A count is not an invariant when the change itself can move the count.** AC6 and AC12 both
  originally used file-wide residual-zero greps that this PR's own mandated additions would have
  moved — one of them passing on a flipped live paging rule. Assert the diff.
- **`terraform state push` is not exercised.** Documented in the #7836 PR; running it against a live
  root is the destructive act the ADR amendment says is unrecoverable.
- **`apply-sentry-infra.yml` is off-limits.** PR 7866 owns it. Any urge to also fix the AC17 constant
  here is a conflict with a sibling that already fixed it better.
- **A plan whose `## User-Brand Impact` is empty or placeholder fails `deepen-plan` Phase 4.6.**
