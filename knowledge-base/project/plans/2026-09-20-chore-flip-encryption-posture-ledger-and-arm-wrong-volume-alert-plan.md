---
title: "Flip the encryption-posture ledger after the Inngest LUKS cutover is measured (#6894)"
date: 2026-09-20
slug: chore-flip-encryption-posture-ledger-and-arm-wrong-volume-alert
branch: feat-one-shot-8296-ledger-flip-arm-alert
issue: 8296
# Deliberately NOT `closes:`. The arm only takes effect on the apply, and the claim ships in a
# second PR behind it, so `Closes #8296` at merge would false-resolve. `Ref #8296`; the close is
# a post-apply step (AC-P8).
type: chore
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-20. **Review panel:** 7 agents (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, CTO, CPO) plus the earlier IaC-routing, CLO and
GDPR-gate passes. **Deepen passes:** precedent-diff and verify-the-negative.

### What review changed, not polished

1. **This became two PRs.** One PR cannot enforce the plan's own ordering rule — only
   `apps/web-platform/infra/**` fires the apply, so the encryption claim would land at merge and
   the detector minutes later, or never if the apply halted on unrelated drift.
2. **A safety claim was retracted.** The plan had asserted CODEOWNERS + branch protection made the
   merge the authorization. `main` has no `pull_request` rule at all. PR-1 now restores a real
   per-command ack and corrects the workflow comment the claim was inherited from.
3. **The mechanism fork dissolved instead of being decided.** Three reviewers argued for deleting
   the arming variable, all from one premise — a permanent reconciler exemption. The premise was
   removable in a parameter, so the variable stays and the coverage comes back.
4. **The bespoke arm-probe was cut and replaced.** It would have retired on its own first success
   (the sweeper closes on exit 0 and never re-litigates), and it measured the detector rather than
   the property — after a rollback the alert is unpaused and firing, so it would have passed while
   the claim was false.
5. **`live_verification` stays `unavailable:` and the floor stays 1.** The plan had claimed
   `available` while its own Cut List said the evidence did not support it.

### Defects found in this plan's own verification commands

Five AC commands would have false-failed a correct implementation, each measured rather than
reasoned: AC-4's diff-grep (returns `1`, because the sibling row carries the same `expires_on`),
AC-18/AC-19's absence greps (the register quotes the retired sentence inside its supersession
bracket, on the same table line), AC-20's diff-text limb, AC-22's unrestricted context lines, and
AC-27's `grep '^-'` (always matches `--- a/`). Two guard defects too: a `MUT_SKIP` floor of 14 would
have made every mutation row report RED over a dead battery, and a "lower the floor" mutation row
could not have reddened the guard at all.

### What the deepen passes caught

The precedent-diff found that `heartbeat-live-reconcile.ts` **already** resolves `.tf` variable
defaults and already threads them to the heartbeat and monitor paths — so Phase 3 is a parameter,
not a new parser, and the plan's stated premise was false. It also supplied four structural elements
the new probe must copy (`set -uo pipefail` never `-euo`; the exit-78 xtrace refusal; a non-optional
`--limit`; the ledger read after the measurement verdicts) and established that the multi-file
mutation harness has **no precedent in this repo**. The verify-the-negative pass confirmed 11 of 12
negative claims and contradicted one: the staging probe is obsolete, not permanently falsified.

## Overview

No `spec.md` exists for this branch, so `lane:` could not be carried forward and is defaulted to
`cross-domain` (TR2 fail-closed).

The additive Inngest Redis LUKS cutover (#8295, ADR-142) completed and was measured on 2026-09-20.
Two things follow, and **the order between them is the whole design**: the detector for "the store
quietly went back to plaintext" must be live BEFORE the record claims encryption. The record may
lag the detector; it may never lead it.

This ships as **two PRs**, because that ordering rule cannot be enforced inside one. Only
`apps/web-platform/infra/**` fires the production apply, so a single PR would publish the claim at
merge and arm the detector minutes later — or not at all, if the apply halts on unrelated drift.

- **PR-1 (detector).** Move `var.inngest_luks_cutover_complete` so
  `logtail_exploration_alert.inngest_luks_wrong_volume` unpauses; move the drift guard that pins its
  old value; teach the live-drift reconciler to resolve `!var.X` against its declared default so
  this alert stops being exempt from pause-drift reporting.
- **PR-2 (record).** Flip `hcloud_volume.inngest_redis_luks` to `mechanism: luks`, rewrite
  `hcloud_volume.inngest_redis` as a retained plaintext backstop, and bring the five other records
  that assert the pre-cutover world up to date. **None of PR-2's paths fire an apply**, so it cannot
  halt and cannot publish a claim into a world where the detector is still paused.

## Research Insights

### Premise Validation (Phase 0.6)

`#8296` OPEN; `#8295` (the cutover) CLOSED — the precondition this change is the follow-up to;
`#8285` (backstop retirement, expiry 2026-10-22) and `#6894` (the parent exception) OPEN. Both
ledger rows exist at the addresses named, carrying exactly the `reevaluate_when` text quoted to this
plan. `paused = !var.inngest_luks_cutover_complete` and `variable "inngest_luks_cutover_complete"`
both resolve.

**Three premises did NOT hold** and are corrected in `## Research Reconciliation`: the repo has no
tfvars mechanism; the documented arming route is un-runnable; and `main` has no review requirement,
so the merge is not an authorization.

### Property List (Phase 0.6b)

- **P1** The ledger's encryption claim names the volume that actually backs the store.
- **P2** The ledger does not claim encryption for the retained plaintext copy, and that copy's
  continued existence stays legible with an expiry.
- **P3** A silent return of the Inngest store to the plaintext volume produces a page.
- **P4** Every published at-rest claim derived from the ledger is true on the day it flips.
- **P5** The claim never outlives its detector — not at merge, not after a rollback, not after the
  tracker closes.

### Cut List (Phase 0.6b, as finally resolved)

- **CUT — a generalised "no line-number citations" gate over the ledger.** AC B3 is file-scoped to
  `inngest-host\.tf:[0-9]`. A generalised regex matches 4 rows / 7 coordinates today, three of them
  in `.tf` files where `AGENTS.rules.md` explicitly permits a line citation. Not this change's
  property.
- **CUT — raising `live_coverage_floor` from 1 to 2, and the bare literal `available` with it.**
  Measured both ways (floor 2 with the flip passes; without it fails), so it would not be vacuous —
  and it is still cut, because it is not *earned*. The probe emits `data_mount_devid`, which proves
  **which device** backs `/mnt/data`, never that the device is `crypto_LUKS`. `available` is
  the token `check_live_coverage_floor` counts, so moving it moves a published coverage claim on
  evidence that does not support it. `hcloud_volume.registry` is held at `unavailable:` for a
  *weaker* reason (emitter exists, never observed). The repo's precedent is to under-claim, and this
  plan follows it. (Blocking condition from the CPO review; independently reached by the
  architecture and per-mechanism reviews.)
- **CUT — the bespoke "is the alert armed?" probe.** Superseded: the reconciler fix below buys the
  same property on a runner that already exists. What survives is a different probe asserting a
  property nothing else covers — see `## Guard Contract` Guard 3.
- **NOT cut, after review — `paused = !var.inngest_luks_cutover_complete` stays an expression.**
  Three reviewers argued for collapsing it to a literal `false`, on the ground that the reconciler
  exempts expression-paused alerts from drift reporting. That premise is removable at its source:
  teaching `pausedIsLiteralFalse` to resolve `!var.X` against the declared default restores
  coverage without deleting the variable, keeps ADR-218's recorded invariant true, and keeps a
  re-pause during a sanctioned rollback a one-line revert. See `## Alternative Approaches`.

### What the lint actually enforces

- `scripts/lint-encryption-posture.py` — `check_luks_row` is a resolution gate, not a text check.
  Flipping to `luks` makes it resolve `device_binding.volume`/`.attachment` against the `*.tf`
  inventory, require the attachment to bind that volume, require a co-located `random_password` +
  `doppler_secret` pair in the attachment's file, resolve `device_binding.mapper` to a
  `cryptsetup luksFormat` + `luksOpen` apparatus under `apps/*/infra/`, and require fstab or
  `MAPPER=`/`MOUNT=` mount evidence. **Measured**: the exact intended shape dry-run against
  `--ledger <scratch copy>` reports `19 stores, 6 connections, 0 unledgered, 0 failing checks -> PASS`.
- `LIVE_VERIFICATION_RE = ^(available|unavailable:.+)$` — not free text. A citation cannot live in
  that field; the observed-cutover citation belongs in `evidence`.
- `check_live_coverage_floor` counts exact string equality `== "available"` across every store.
  Today: one row (`hcloud_volume.workspaces_luks`), floor 1. Unchanged by this plan.
- **Two blind spots, both measured, both the reason an AC asserts directly rather than trusting CI.**
  `check_at_rest` hands a `luks` row to `check_luks_row` and returns, so `check_exception_block`
  never runs on it — and the JSON schema lists `exception` among `at_rest`'s permitted properties
  (`additionalProperties: false`, `required: [mechanism, defends_against, does_not_defend,
  disclosed_as, live_verification]`). A stale `exception` block on a `luks` row is *valid* to both
  gates. Likewise `check_disclosed_as_not_encrypted` runs only on `plaintext-exception` rows.
- The `encryption-posture` CI job runs `--repo-sweep` and is **absent from
  `scripts/required-checks.txt`** (measured: 0 hits). It is advisory. So is the alert drift guard,
  under `infra-validation.yml`. Green CI does not prove these ran; they are run locally and pasted.

### AC B3 — found, and it is not a gate

`B3. grep -c 'inngest-host\.tf:[0-9]' scripts/encryption-posture-ledger.json returns 0`, from
`knowledge-base/project/plans/archive/20260918-170200-2026-09-02-infra-inngest-volume-recut-luks-plan.md`
(`## Acceptance Criteria` → `### Merge B (apparatus + gated target) — pre-merge`). A one-time,
pre-merge criterion. **No committed script, test or CI step greps the ledger for line-number-shaped
citations**; `AGENTS.rules.md` says of `cq-cite-content-anchor-not-line-number`: "Convention only;
no gate enforces it (ADR-116)." Still green (`0`), carried forward as AC-10, widened by exactly the
one file the flipped row cites.

### Terraform: how this repo carries an environment-specific value

- **No tfvars.** `git ls-files | grep -ic tfvars` → `0`, unbounded. No workflow passes `-var-file`.
  The runbook says the same in its own words.
- Two carriages exist: a Doppler `prd_terraform` secret surfaced as `TF_VAR_<lowercased>` by
  `--name-transformer tf-var`, and an in-repo declared default (`adopt_seo_config_entrypoint = true`,
  `web_colocate_inngest = false`, `betterstack_paid_tier = false`). A Doppler value **overrides** the
  declared default silently — Terraform puts `TF_VAR_*` above a default and emits no diagnostic for a
  declared variable. `variables.tf` records that hazard above `adopt_seo_config_entrypoint` and calls
  it "the fail-open shape".
- **The documented arming route is un-runnable, two independent ways.**
  `inngest-luks-cutover-6894.md` §5 step 2 ends with
  `gh workflow run apply-web-platform-infra.yml -f apply_target=main`: `main` is not among
  `apply_target`'s `choice` options (the escape hatch is `manual-rerun`), **and** the `reason` input
  is `required: true` and is omitted. Either alone fails at the API.
- **Unbounded consumer sweep**, excluding this change's own planning artifacts — which quote both
  strings and would otherwise count themselves (the self-grep-scope trap):
  `git grep -l 'inngest_luks_cutover_complete' -- . ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
  → **eight** files; the same sweep for `inngest_luks_cutover_complete=true` → exactly **two**
  carriers of the dead `-var` route (`betterstack-logs-alerts.tf`, `betterstack-log-query.md`).
  Without the exclusions the counts read 11 and 4. A third `-var` carrier was reported by the IaC
  review and does not hold: ADR-218 carries the `paused = !var…` expression, not the `-var` route.

### The guards that the ask did not name

`apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` asserts both
`paused = !var.inngest_luks_cutover_complete` and
`grep -A4 'variable "inngest_luks_cutover_complete"' "$VARS" | grep -qF 'default     = false'`
(five spaces — `terraform fmt` alignment against the 11-character `description` key, not incidental
whitespace). Measured baselines: **19 passed, floor 19**; under `MUT_SKIP`, **13 passed, floor 13**.

`plugins/soleur/lib/heartbeat-live-reconcile.ts` computes
`pausedIsLiteralFalse = pausedMatch === null || pausedMatch[1].trim() === "false"` and gates
`logs-alert-paused` on `l.paused && d.pausedIsLiteralFalse`. The exemption has **exactly one key**,
and its stated premise — "before the cutover the condition it watches is the correct state" —
expires at this change. `logs-alert-absent` is *not* gated on the flag, so absence is already caught;
only the pause arm is blind.

### Published claims derived from the ledger

`knowledge-base/legal/article-30-register.md` carries exactly **two** cells naming #8296 as their own
amending event (PA-21 §(f) and PA-22 §(f), both saying "This cell asserts no encryption until that
flip is made"), plus PA-13 §(e), whose "the apparatus is still inert until a reviewer-gated dispatch
runs (#8295)" the completed cutover falsified. All three are single markdown table lines, which
matters for how the ACs are written. Both ledger rows carry `disclosed_as: "not-publicly-claimed"`,
and a sweep of `docs/legal/**`, `plugins/soleur/docs/pages/**` and `compliance-posture.md` for
`inngest_redis` returns **zero hits** — so no published surface changes.

### Institutional learnings that bind this change

- `2026-07-24-formalizing-a-provisional-provider-attestation-honest-close-and-citation-not-probe.md`
  — a citation is not a live probe; `available` is a false claim unless a live probe verifies the
  property itself. This is what decides the Cut List's second entry.
- `2026-07-24-holding-a-live-overclaim-pending-infra-teardown-and-drain-can-mean-keep-open.md` — a
  retained plaintext residual keeps its umbrella issue OPEN and binds `reevaluate_when` to the
  teardown; do not file a new tracker for a bounded exception that has one (#8285).
- `2026-08-03-the-verification-i-shipped-could-not-fail-and-my-instrument-measured-the-wrong-machine.md`
  — never treat `rc=0` as evidence; read the property back. Applied twice here: the arm's criterion
  is the live `paused` field, and the ForceNew question is settled by a real plan against real state
  rather than by a schema dump that cannot express the answer.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` — a guard
  updated in the same change that moves the thing it guards needs fixtures off the boundary.
- `2026-06-09-restore-paused-framing-can-invert-risk-ordering.md` — the paused-state registry is
  ground truth; issue prose is a point-in-time narrative.
- `ADR-140` — the ledger row is the single join between what the code does and what is publicly
  claimed; evidence must be mechanically resolvable and never keyed by name similarity. That is the
  exact trap these two sibling rows present, and it is what broke an earlier draft of AC-4.
- <!-- lint-infra-ignore start: cites two learnings by filename and states a Terraform
     resolution-order fact; prescribes no step for anyone to run -->
  `ADR-065-operator-mint-tf-var-secret-before-iac-merge.md` and
  `workflow-patterns/2026-06-17-operator-mint-tf-var-must-sequence-before-auto-applied-iac.md` —
  every root variable is resolved before `-target` pruning, and the apply fires on merge of any
  `*.tf` change. A variable with a declared default cannot fail that resolution, which is why the
  default is the safe carriage.
  <!-- lint-infra-ignore end -->

### Measured gate baselines (green before any edit)

| Gate | Result |
| --- | --- |
| `apps/web-platform/infra/inngest-luks-cutover.test.sh` | 96 passed, 0 failed (floor 96) |
| `apps/web-platform/infra/inngest-redis-luks.test.sh` | 57 passed, 0 failed (floor 57) |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | 665 passed, 0 failed |
| `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` | 160/160, `unconditional=123 floor=123` |
| `tests/scripts/test-inngest-host-shape-gate.sh` | 79 passed, 0 failed (floor 79) |
| `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` | 19/19 floor 19; `MUT_SKIP` 13/13 floor 13 |
| `scripts/lint-encryption-posture.test.sh` | `PASS=45 FAIL=0 TOTAL=45` |
| `python3 scripts/lint-encryption-posture.py --repo-sweep` | 19 stores, 6 connections, 0 failing -> PASS |
| `plugins/soleur/test/c4-count-parity.test.sh` | `Passed: 10 Failed: 0` |
| `grep -c 'inngest-host\.tf:[0-9]' scripts/encryption-posture-ledger.json` | `0` |

## Open Code-Review Overlap

None. Every open `code-review`-labelled issue was fetched and each planned path matched against the
bodies with a standalone `jq --arg`; no issue body names any file in this change.

## Research Reconciliation — Ask vs. Codebase

| Claim | Measured reality | Plan response |
| --- | --- | --- |
| "Choose between changing the declared default and adding a tfvars entry." | `git ls-files \| grep -ic tfvars` → `0`. No `-var-file` anywhere. Half the menu does not exist. | Change the declared default. |
| The ask frames the unpausing apply as a separate production step authorized per-command after merge. | The `apply` job fires **on push to main** for `apps/web-platform/infra/**`, has **no `environment:` reviewer gate**, and runs `terraform apply -auto-approve`. | True as an intent, false as a mechanism. PR-1 restores it: merge with `[skip-web-platform-apply]`, then dispatch `apply_target=manual-rerun` — that dispatch **is** the per-command ack. |
| The plan's own earlier claim: "CODEOWNERS + branch protection on `main` is the load-bearing gate, so the merge is the authorization." | **False, measured.** `gh api repos/jikig-ai/soleur/branches/main/protection` → `404 Branch not protected`. The rulesets on `main` are two `required_status_checks`, `deletion`, `non_fast_forward` — **no `pull_request` rule**, so no required review and no code-owner requirement. CODEOWNERS only auto-requests. | Retracted. The sentence was inherited verbatim from the workflow's own comment, which has been wrong since #4220, and this plan asserted it as verified. Corrected here, and the workflow comment is corrected in PR-1 so it is not copied a third time. Deferral D8 tracks adding the rule. |
| "FIND whatever gate validates the ledger's schema and its AC B3 grep." | Schema + resolution gate found and run. **AC B3 is not a gate** — a one-time criterion from an archived plan, for a convention `AGENTS.rules.md` says nothing enforces. | Carried as AC-10, widened by one file. No generalised gate built. |
| The ask scopes this to two parts. | Five further records assert the pre-cutover world, and ADR-142's apparatus-scope item 8 instructs a reader to flip the **wrong row** — a booby trap for whoever reads it next. | Scope grows to two PRs and nine files. Each is a claim the flip falsifies, not a follow-up. |

## User-Brand Impact

**If this lands broken, the user experiences:** the ledger and the Article 30 register publish an
at-rest encryption claim over their in-flight Inngest job payloads — their prompts and the agent
output returned to them — while the store is, or silently returns to, the plaintext volume. The
durable shape of the failure is not the minutes between merge and apply; it is that the claim can
outlive its detector, three ways: the apply halts and nothing re-checks, a later apply or a
vendor-side pause re-pauses the alert, or a sanctioned `op=luks-rollback` puts the store back on the
plaintext volume and nothing in that path touches the record.

**If this leaks, the user's data is exposed via:** a seized, RMA'd or snapshot-imaged Hetzner block
volume — specifically `hcloud_volume.inngest_redis`, the RETAINED PLAINTEXT BACKSTOP, which holds a
full second copy of the same AOF until #8285 (expiry 2026-10-22), and whose bytes are reached by no
erasure path, including account deletion. The flip narrows the exposure to one volume; it does not
end it, and the record must not read as though it did.

**Brand-survival threshold:** single-user incident. The AOF is undifferentiated, so one seized
volume exposes every in-flight user's prompts at once, and one false limb in a regulator-facing
register is terminal on its first reading.

`requires_cpo_signoff: true` — granted conditionally, conditions folded in; see `## Domain Review`.

## Files to Edit

### PR-1 — the detector (fires the apply)

| File | Change |
| --- | --- |
| `apps/web-platform/infra/variables.tf` | `variable "inngest_luks_cutover_complete"`: `default     = false` → `default     = true`. **Five spaces before `=`** — `terraform fmt` alignment against the 11-char `description` key, and the byte the drift guard greps. Rewrite the comment above it to record the inverting event, its evidence, and the Doppler-override hazard. **Do not let `description` wrap to a second line and do not add a `validation {}` block**: either pushes `default` past `grep -A4`'s reach and silently kills both AC-11 and the guard assertion. |
| `apps/web-platform/infra/betterstack-logs-alerts.tf` | Comment-only: drop `terraform apply -var inngest_luks_cutover_complete=true  (or the tfvars entry)` — it names a mechanism that has never existed in this root. **`paused = !var.inngest_luks_cutover_complete` is unchanged.** |
| `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` | Invert the default assertion to `default     = true`; rewrite its `ok()` text (the current one states a rationale the cutover inverted); parameterise `mutate_red` to take a target file and fix its restore, per `## Guard Contract`; add two mutation rows; raise `_floor` 19 → 21. **`MUT_SKIP`'s floor stays 13.** |
| `plugins/soleur/lib/heartbeat-live-reconcile.ts` | Thread the **existing** `vars: InfraVariables` parameter into the logs-alert path — `parseLogsAlertBlocks(tfText, vars)` and `discoverLogsAlertsFromInfra(infraDir, vars = resolveInfraVariables(infraDir))` — then resolve `paused = !var.<name>` via `vars.get(name)` with `kind === "bool"`. **Do not write a new `variables.tf` reader.** Measured: `parseInfraVariables` / `listTfFiles` / `resolveInfraVariablesPerFile` / `resolveInfraVariables` already exist in this same file and already parse boolean defaults (`{ kind: "bool", value: raw === "true" }`), and `discoverHeartbeatsFromInfra` / `discoverMonitorsFromInfra` already take `vars` — `discoverLogsAlertsFromInfra` is the only one of the three that does not. Fail **closed**: an unresolvable variable stays an expression (exempt), which `resolveInfraVariablesPerFile` already gives for free by failing a file into `errors` rather than defaulting. |
| `plugins/soleur/test/heartbeat-live-reconcile.test.ts` | Guard 2's matrix. The existing `inngest_luks_wrong_volume` fixture's expectation inverts: a live pause on this alert is now reported. |
| `.github/workflows/apply-web-platform-infra.yml` | Comment-only: the `apply` job header claims CODEOWNERS + branch protection are the gate. Measured false. Correct it so it is not copied again. |

### PR-2 — the record (fires nothing)

| File | Change |
| --- | --- |
| `scripts/encryption-posture-ledger.json` | Flip `hcloud_volume.inngest_redis_luks` to `mechanism: luks`; **delete its `exception` block**; rewrite `evidence` / `defends_against` / `does_not_defend`; set `live_verification` to `unavailable:<cipher half unobserved>` (NOT `available` — see Cut List). Rewrite `hcloud_volume.inngest_redis` as a retained plaintext backstop with `expires_on` **untouched**, and add the rollback trigger to its `reevaluate_when`. `live_coverage_floor` stays `1`. |
| `knowledge-base/legal/article-30-register.md` | Dated in-cell amendments to PA-21 §(f), PA-22 §(f), PA-13 §(e), using the register's own `**[2026-09-20 AMENDMENT (#8296): …]**` / `**[Superseded 2026-09-20 (#8296): …]**` bracket convention. Each retains the "Two copies, bounded" fact and the EXPIRED clause, and says the alert goes live **on the apply**, never at merge. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `platform.infra.inngestRedis`'s description: replace `AT REST: STILL PLAINTEXT ext4 …` and `AT REST IS STILL PLAINTEXT AS OF THIS EDIT`, drop the already-stale `format = "ext4"` under `ignore_changes = [format]` citation, state the post-cutover shape. Element description is replaced, not annotated. |
| `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` | **Appended** amendment (the ADR's convention is "Appended, not edited"): record the observed cutover and correct apparatus-scope item 8, which instructs flipping `hcloud_volume.inngest_redis` to `luks` — the opposite of what the ADR's own 2026-09-18 amendment requires. Additions only. |
| `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` | Appended: "It ships PAUSED" is falsified at the arm. |
| `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` | §5 step 2: the dispatch is un-runnable two ways. Rewrite for the real carriage and route. §5 step 4's "#8296 … does not close itself" reflects that it now does, post-apply. |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | Second carrier of the dead `-var` route. |
| `scripts/followthroughs/inngest-luks-cutover-6894.sh` | Re-point its `NEXT (not automatic):` line at the one remaining open step (#8285) and update its `RETIREMENT:` line, which names a sibling this PR deletes. |
| `scripts/cutover-inngest.sh` | `op=luks-rollback` remounts the plaintext volume and sets `INNGEST_LUKS_CUTOVER=rolled-back`, and **makes no commit** — so after a sanctioned rollback the ledger and the register are false and nothing says so. Add a `NEXT (not automatic):` line on the rollback success path naming both files and the two anchors to revert, mirroring the cutover probe's existing shape. |

### PR-2 — files to create / delete

| File | Purpose |
| --- | --- |
| `scripts/followthroughs/inngest-luks-property-8296.sh` **(create)** | Asserts the **property**, not the detector. Reads the same probe rows the alert's SQL reads, via `scripts/betterstack-query.sh`, and cross-reads the ledger. Arms: `0 PASS` — the store is on the LUKS alias **and** the ledger reads `luks`; `1 FAIL` — the store is on the **plaintext** alias while the ledger claims `luks` (the rollback inversion: the record must be reverted); `3 CANNOT ESTABLISH` — **no probe rows in the window**, which also covers the dead-probe gap that `on_missing_data = "treat_as_zero"` leaves open. Four structural elements copied verbatim from `scripts/followthroughs/registry-luks-live-8386.sh` rather than reinvented: (a) `set -uo pipefail`, **never `-euo`** — all nine sibling probes use it, because the probe must continue past a failing command to classify *why* rather than aborting; (b) the `case "$-" in *x*)` xtrace-refusal block exiting **78** when `BETTERSTACK_QUERY_PASSWORD` is set (#7797) — eight of nine carry it, and this probe declares that secret; (c) `--limit "${SOLEUR_FT_LIMIT:-5000}"` on the query — **not optional**, the default silently reads only the newest ~8h20m; (d) the ledger read positioned **after** every measurement verdict, so its failure arm cannot precede them. `RETIREMENT:` uses the dominant colon-prose form (7 of 8) and names every reference site — its `.test.sh` sibling, any `run_suite` registration in `scripts/test-all.sh`, and the directive on #8285 — closing with "Nothing else references it" once verified. |
| `scripts/followthroughs/inngest-luks-property-8296.test.sh` **(create)** | Guard 3's harness. |
| `scripts/followthroughs/inngest-luks-staging-6894.sh` **(delete)** | Requires a `stage=staging_verify` row **and** a probe row still pinning the plaintext volume (`UNDISTURBED`). Post-cutover it exits 1 on every sweep, which the sweeper comments as a regression — a false daily regression comment on #6894 until that closes. **The rationale is "its question is obsolete", not "it can never pass again"**: an earlier draft said the cutover falsified both halves *permanently*, and that overclaims. Its PASS is driven by live host and Better Stack state through the FSM's durable `INNGEST_LUKS_ACTIVE_VOLUME_ID` pointer, not by the Terraform variable this change flips — and `scripts/cutover-inngest.sh op=luks-rollback` clears that pointer, while the staging block in `cloud-init-inngest.yml` re-arms on any boot when `MODE != pointer`. So a sanctioned rollback plus a reboot could legitimately make it exit 0 again. It is deleted because it asks a staging-era question the cutover has settled, and because leaving it running emits a false regression in the meantime — not because it is incapable of passing. |

**Not created:** a counsel-review audit file. `soleur:ship` Phase 5.5 **produces** it by invoking the
CLO agent, and the house filename is `<YYYY-MM>-counsel-review-<issue>.md` (all 11 existing files),
not a day-stamped one. Writing it here would hard-code the verdict of an agent that adjudicates at
ship time.

## Implementation Phases

### Phase 0 — settle what the later phases assume (PR-1, before any edit)

1. **Does a Doppler value override the new default?** A `TF_VAR_*` outranks a declared default with
   no Terraform diagnostic.
   `doppler secrets get INNGEST_LUKS_CUTOVER_COMPLETE -p soleur -c prd_terraform --plain --no-interactive`
   — single-secret read; never bare `doppler secrets`, which dumps the config. Not found → the
   default governs, proceed. `true` → already armed; make the edit anyway (it records an invisible
   arm) but do not use "plan shows 1 to change" as the criterion. Anything else → **do not merge
   into this**; resolving it is a Doppler write, a gated production command with its own ack.
2. **Is `paused` in-place-updatable or ForceNew on `betterstackhq/logtail v11.2.0`?** **Do not use a
   `terraform providers schema -json` probe** — measured: the dump is a well-formed 145 kB document
   in which `paused` appears as `{"type":"bool","optional":true,"computed":true}` and
   `force_new`/`requires_replace` appear **zero times**, because replacement is plan-time behaviour
   that the schema format does not serialise. The probe cannot fail and settles nothing. Settle it
   empirically instead: push the branch and read the **`plan` job in
   `.github/workflows/infra-validation.yml`**, which is `pull_request`-only, runs a full-root
   `terraform plan` against live prod state, and posts a sticky comment. Read it for (a) the verb on
   `logtail_exploration_alert.inngest_luks_wrong_volume` — `~ update in-place` or
   `-/+ must be replaced` — and (b) any destroy/replace/create at an address in the apply's
   `-target` list. That one read also answers "is the plan quiet", which Phase 5 needs.
3. **Which Better Stack credential is which?** `BETTERSTACK_API_TOKEN` is documented as the Uptime
   mgmt token in one place and the Telemetry mgmt token in another. AC-25 points at
   `telemetry.betterstack.com`. A 401 makes `jq -e` exit non-zero, indistinguishable from
   `paused: true`. Resolve before writing AC-25's command.

### Phase 1 — PR-1: arm the detector (P3)

1. `variables.tf`: `default     = false` → `default     = true`, with the comment rewritten.
2. `betterstack-logs-alerts.tf`: drop the dead `-var` route from the comment block. Leave `paused`.
3. `apply-web-platform-infra.yml`: correct the false authorization comment.

### Phase 2 — PR-1: move the guard with the world (P3)

1. Invert the default assertion to `default     = true` and rewrite its `ok()` string. Prefer
   `grep -Eq 'default[[:space:]]+= true'` over the fixed-width `grep -qF` so a future
   `terraform fmt` cannot silently disarm the assertion.
2. Parameterise the mutator and fix its restore — see `## Guard Contract` Guard 1 for the exact
   diff, including the pre-existing `trap` defect that this change is what makes dangerous.
3. Add mutation rows 7 and 8. Raise `_floor` 19 → 21. **Leave the `MUT_SKIP` floor at 13.**

### Phase 3 — PR-1: stop exempting this alert from drift reporting (P5)

**This is a parameter-threading change, not a new parser.** An earlier draft of this plan said "the
variable's default lives in a third file, `variables.tf`, which the parser does not read today —
adding that read is the change". That premise is **false, measured**: `heartbeat-live-reconcile.ts`
already exports `parseInfraVariables`, `listTfFiles`, `resolveInfraVariablesPerFile` and
`resolveInfraVariables`, which walk every `.tf` under `infraDir` and record boolean defaults as
`{ kind: "bool", value: raw === "true" }`. `discoverHeartbeatsFromInfra` and
`discoverMonitorsFromInfra` already accept `vars: InfraVariables = resolveInfraVariables(infraDir)`;
`discoverLogsAlertsFromInfra` is the lone sibling that does not, and `parseLogsAlertBlocks` takes
only the file text.

So the change is: give the logs-alert pair the same `vars` parameter its two siblings already carry,
and in `parseLogsAlertBlocks` resolve a `!var.<name>` expression through `vars.get(name)` when
`kind === "bool"`. Fail closed — an unresolved or non-bool variable leaves the alert an expression
(exempt), which is what `resolveInfraVariablesPerFile`'s `errors` arm already produces. Update the
paired fixture in `heartbeat-live-reconcile.test.ts`, whose expectation for this alert inverts. This
is what makes the durable un-arm visible, twice daily, on a runner that already exists — reusing a
tested helper rather than adding a second `.tf` reader that could drift from it.

### Phase 4 — PR-1: apply, and read the property back

Merge PR-1 with `[skip-web-platform-apply]` in the merge commit, then dispatch:

```
gh workflow run apply-web-platform-infra.yml \
  --ref main \
  -f apply_target=manual-rerun \
  -f reason='Arm logtail_exploration_alert.inngest_luks_wrong_volume after the 2026-09-20 Inngest Redis LUKS cutover (#8296)'
```

That dispatch is the per-command go-ahead `hr-menu-option-ack-not-prod-write-auth` requires, and it
is required **because** `main` carries no review rule — the merge is not an authorization here.
Then poll the run to a terminal conclusion and branch on it (Phase 5), rather than assuming.

### Phase 5 — PR-2: the record, only once the detector is live

Ledger first, then the five records, then the probe, then the deletions. PR-2 touches no
`apps/web-platform/infra/**` path, so it fires no apply and cannot halt.

1. `hcloud_volume.inngest_redis_luks` → `"mechanism": "luks"`, **`exception` block deleted** (the two
   `luks` exemplars carry the five `at_rest` fields and nothing else). `evidence` cites the observed
   cutover with content anchors only — the resource in `inngest-redis-luks.tf`, the terminal
   `SOLEUR_INNGEST_LUKS_CUTOVER` row (2026-09-20T15:29:10Z, `reason=cutover-complete`, `flag=done`,
   `phase=swapped`, `exit_code=0`, `k_freeze=1366`, `e_freeze=1355`), the post-cutover probe row
   (2026-09-20 15:36:40, `/dev/mapper/inngest-redis`, `scsi-0HC_Volume_106903269`, `redis_active`,
   1437 keys), and the apparatus (`cryptsetup luksFormat`/`luksOpen` resolving to mapper
   `inngest-redis`; `random_password` + `doppler_secret` in `inngest-redis-luks.tf`). **One evidence
   string, written once** — an earlier draft prescribed two different ones in two sections.
   `does_not_defend` must name the retained backstop: the one thing a reader can wrongly conclude
   from a `luks` row here is that the AOF exists only in encrypted form.
2. `live_verification` → `unavailable:` plus the reason — the probe proves device identity, not
   cipher; the cipher half is the statically-resolved apparatus `check_luks_row` verifies; flip to
   `available` in the commit that records a probe row carrying an explicit LUKS-type field, the way
   `hcloud_volume.registry`'s `store_luks` does (D3). `live_coverage_floor` stays `1`.
3. `hcloud_volume.inngest_redis`: keep `plaintext-exception`. Rewrite `evidence`,
   `live_verification` (the opposite claim — a probe row still pinning THIS volume post-cutover
   means the store came back), `exception.justification` and `exception.reevaluate_when`; set
   `reassessed_on` to `2026-09-20`; add the rollback trigger (`INNGEST_LUKS_CUTOVER=rolled-back`) to
   `reevaluate_when` so it is machine-readable rather than prose in a frontmatter field. **Leave
   `expires_on: 2026-10-22` exactly as it is** — the row's own `expires_on_not_extended` field says
   why, and after step 1 it is the sole carrier of hard expiry enforcement for the Inngest pair.
4. The five records, the two runbooks, and `cutover-inngest.sh`'s rollback NEXT line.
5. Create the property probe + its harness; enroll on **#8285** (OPEN, and already the
   `reevaluate_when` target) — never on #8296, which closes. Delete the staging probe.

## Acceptance Criteria

**`grep -c` exits 1 when it prints `0`.** Every "returns `0`" below asserts on **stdout**, not on
exit status; under `set -e` write `[ "$(grep -c … || true)" = 0 ]`.

### PR-1 — the detector

- [ ] **AC-11** `grep -A4 'variable "inngest_luks_cutover_complete"' apps/web-platform/infra/variables.tf | grep -Eq 'default[[:space:]]+= true'` exits 0.
- [ ] **AC-12** `grep -qF 'paused = !var.inngest_luks_cutover_complete' apps/web-platform/infra/betterstack-logs-alerts.tf` exits 0 — the expression form survived.
- [ ] **AC-13** `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` reports **`>= 21` passed, 0 failed, floor 21**. Phrased as `>=` because the floor is a `>=` count; an exact-string pin would read "22 assertions is a failure".
- [ ] **AC-14** `MUT_SKIP=1 bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` reports **13 passed, floor 13** — unchanged. **Load-bearing**: this change adds no non-mutation assertion, so raising the `MUT_SKIP` floor to 14 would make every inner run exit 1 on the FATAL floor check, `mutate_red` would read that as RED for *every* row including vacuous ones, and the outer run would print green over a dead battery.
- [ ] **AC-15** Mutation rows 7 and 8 are real: reverting `default     = true` to `false` in a scratch `variables.tf` reds the guard, and rewriting `paused` to a constant `false` reds it.
- [ ] **AC-16** `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts` green, **with the `inngest_luks_wrong_volume` fixture's expectation inverted** — a live pause on this alert is now a reported `logs-alert-paused`, not `[]`. A green run against the *old* fixture means the resolution never landed.
- [ ] **AC-17** Fail-closed: with a `!var.X` whose variable cannot be resolved, `pausedIsLiteralFalse` is `false` (exempt), never `true`.
- [ ] **AC-25** The live `paused` field is read back from the vendor, **as two assertions, not one**: (a) HTTP status is 200, (b) the payload's alert is unpaused. Non-200 is `3 CANNOT ESTABLISH` and must **not** be read as "paused" — a 401 from the wrong Better Stack token and a genuine pause are otherwise indistinguishable, and the latter triggers a revert of a true claim.
      ```
      code=$(curl --disable --noproxy "*" -sS --max-time 30 -o /tmp/bs.json -w '%{http_code}' \
        -H "Authorization: Bearer $BETTERSTACK_API_TOKEN" \
        https://telemetry.betterstack.com/api/v2/alerts)
      [ "$code" = 200 ] || exit 3
      jq -e '[.data[] | select(.attributes.name=="soleur-inngest-luks-wrong-volume-prd")]
             | length == 1 and (.[0].attributes.paused == false)' /tmp/bs.json
      ```
      `length == 1` is load-bearing: zero and two are both failures, and zero is what an
      unapplied resource looks like. The endpoint is not invented — ADR-218 names
      `GET telemetry.betterstack.com/api/v2/alerts`; the `curl` shape is the repo's own from the
      `app-database-readiness-alarm` runbook. **The response shape `.data[].attributes.paused` is
      resolved in Phase 0.3, not assumed here.**
- [ ] **AC-26** The apply is polled to a **terminal conclusion** before AC-25 is evaluated, with a
      stated bound: `gh run list --workflow=apply-web-platform-infra.yml --branch main` for the run
      this dispatch created. `success` → evaluate AC-25. `failure`/`cancelled` → the detector is not
      live; PR-2 does not proceed. Still running at the bound → treated as not live (fail-closed),
      never "assume it landed". Without this, AC-25 can read `paused: true` against a queued apply
      and condemn a correct change.
- [ ] **AC-34** All carriers of the dead arming route are gone: `grep -c 'or the tfvars entry' apps/web-platform/infra/betterstack-logs-alerts.tf` → `0`, and `betterstack-log-query.md` no longer names `-var inngest_luks_cutover_complete=true`. Measured: exactly two carriers, not three.
- [ ] **AC-36** `.github/workflows/apply-web-platform-infra.yml`'s `apply` job header no longer claims branch protection or CODEOWNERS is the gate.

### PR-2 — the record (may not start until AC-25 and AC-26 both hold)

- [ ] **AC-1** `jq -r '.stores[]|select(.store=="hcloud_volume.inngest_redis_luks")|.at_rest.mechanism' scripts/encryption-posture-ledger.json` → `luks`.
- [ ] **AC-2** `jq -e '.stores[]|select(.store=="hcloud_volume.inngest_redis_luks")|.at_rest|has("exception")|not' …` exits 0. **Neither gate can catch this**: `check_at_rest` early-returns on `luks` before `check_exception_block`, and the schema permits `exception` on `at_rest`.
- [ ] **AC-3** `… select(.store=="hcloud_volume.inngest_redis") | .at_rest.mechanism` → `plaintext-exception`. The backstop row did **not** flip.
- [ ] **AC-4** The backstop's expiry is unmoved — compare the **value** across revisions, never the diff text:
      ```
      Q='.stores[]|select(.store=="hcloud_volume.inngest_redis")|.at_rest.exception.expires_on'
      test "$(jq -r "$Q" scripts/encryption-posture-ledger.json)" \
         = "$(git show origin/main:scripts/encryption-posture-ledger.json | jq -r "$Q")"
      ```
      **A diff-text grep is rejected, and the reason is measured.** `git diff … | grep -c '^[-+].*expires_on.*2026-10-22'` expecting `0` returns **`1`** on a correct implementation, because the sibling `inngest_redis_luks` row carries the same date and Phase 5 step 1 deletes its whole `exception` block. That is the `workspaces`/`workspaces_luks` name-similarity trap ADR-140 names, landing on the two rows this plan is about.
- [ ] **AC-5** `… .at_rest.live_verification` on the flipped row starts `unavailable:` and names the cipher-half gap. It is **not** the bare literal `available`.
- [ ] **AC-6** `jq -r '.live_coverage_floor' …` → `1`, and `jq '[.stores[]|select(.at_rest.live_verification=="available")]|length' …` → `1`. Unchanged.
- [ ] **AC-7** The flipped row's `does_not_defend` contains `hcloud_volume.inngest_redis` — it names the retained plaintext copy.
- [ ] **AC-8** `python3 scripts/lint-encryption-posture.py --repo-sweep` prints `0 failing checks -> PASS`.
- [ ] **AC-9** `jq -r '… select(.store=="hcloud_volume.inngest_redis") | .at_rest.exception.reevaluate_when' …` contains `rolled-back` — the rollback trigger is machine-readable in the ledger, not prose in an audit frontmatter.
- [ ] **AC-10 (AC B3, widened by one file)** `grep -c -E '(inngest-host|inngest-redis-luks)\.tf:[0-9]' scripts/encryption-posture-ledger.json` → `0`.
- [ ] **AC-18** The register no longer ASSERTS the pre-cutover claim while still RECORDING it. A bare absence grep is rejected: the convention quotes the retired sentence inside a supersession bracket, **on the same physical table line**. Assert instead: `grep -c '\[Superseded 2026-09-20 (#8296)' …` ≥ `2`; `grep -c '\[2026-09-20 AMENDMENT (#8296)' …` ≥ `3`; and `grep -n 'This cell asserts no encryption until that flip is made' … | grep -vc 'Superseded 2026-09-20 (#8296)'` → `0`.
- [ ] **AC-19** Same shape, executable, for PA-13 §(e): `grep -n 'the apparatus is still inert until a reviewer-gated dispatch runs (#8295)' … | grep -vcE '\[(2026-09-20 AMENDMENT|Superseded 2026-09-20) \(#8296\)'` → `0`.
- [ ] **AC-20** Both bounding clauses survive: `grep -c 'TWO copies of the same AOF exist concurrently' …` → `2` and `grep -c 'reads as EXPIRED if that date passes with the backstop attached' …` → `2`. **No diff-text limb** — the clauses sit on the same physical lines as the amended cells, so any diff carries a `-`/`+` pair and a "must not appear in the diff" grep returns 2 on a correct edit.
- [ ] **AC-21** The register says the alert goes live **on the apply**, not at merge — assert the **presence** of the pinned phrase `the apply that follows` in each amended cell (≥ 1 per cell). A forbidden-phrasing grep is rejected: a tense blacklist passes "the detector is live", "monitoring is in place".
- [ ] **AC-22** `git diff origin/main -- knowledge-base/legal/article-30-register.md | grep '^+' | grep -nE '\.(tf|sh|yml|ts|conf):[0-9]+'` → nothing. Restricted to **added** lines: unrelated coordinates (`byok-lease.ts:248`, `:133`) sit inside `git diff`'s default 3-line context of the amended cells and would false-fail an unrestricted grep.
- [ ] **AC-23** `grep -c 'AT REST: STILL PLAINTEXT ext4' knowledge-base/engineering/architecture/diagrams/model.c4` → `0`, likewise `AT REST IS STILL PLAINTEXT AS OF THIS EDIT` and `ignore_changes = [format]`. **A bare absence grep IS correct here** — `model.c4` has no supersession convention; the element description is one string, replaced not annotated. If the implementer records the retired text anyway, flip this to AC-18's shape in the same edit.
- [ ] **AC-24** `bash plugins/soleur/test/c4-count-parity.test.sh` → `Passed: 10  Failed: 0`, and `bun test apps/web-platform/test/c4-code-syntax.test.ts apps/web-platform/test/c4-render.test.ts` green. **That gate cannot see the `inngestRedis` prose change** — it parity-checks only `github -> sentry` / `github -> resend` counts. AC-23 is what covers it.
- [ ] **AC-27** ADR-142 gained an appended 2026-09-20 amendment whose body contains both `apparatus scope item 8` **and** `hcloud_volume.inngest_redis_luks` (the phrase is absent from the ADR today — measured `0` — so this asserts the correction, not the status line), and `git diff --numstat origin/main -- <ADR-142 path>` shows **deletions `0`**. A `grep '^-'` limb is rejected: it always matches `--- a/<path>`.
- [ ] **AC-28** `grep -c 'apply_target=main' knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` → `0`, the replacement value appears in the workflow's `apply_target` options, and the corrected command supplies the `required: true` `reason` input.
- [ ] **AC-29** `scripts/followthroughs/inngest-luks-property-8296.sh` exists, is executable, carries a `RETIREMENT:` line naming its back-references, and `bash scripts/followthroughs/inngest-luks-property-8296.test.sh` is green.
- [ ] **AC-30** The directive is on **#8285**, verified remotely: `gh issue view 8285 --json body,labels` shows the `follow-through` label and `<!-- soleur:followthrough script=scripts/followthroughs/inngest-luks-property-8296.sh earliest=<merge+1d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`. Not #8296, which closes — the sweeper's closed path comments nothing on a non-1 exit and drops the issue entirely after `CLOSED_LOOKBACK_DAYS=14`.
- [ ] **AC-31** `test ! -e scripts/followthroughs/inngest-luks-staging-6894.sh`, and `scripts/followthroughs/inngest-luks-cutover-6894.sh`'s `RETIREMENT:` line no longer names it.
- [ ] **AC-32** `scripts/cutover-inngest.sh`'s `op=luks-rollback` success path prints a `NEXT (not automatic):` line naming `scripts/encryption-posture-ledger.json` and `knowledge-base/legal/article-30-register.md`.
- [ ] **AC-33** The dead-probe gap is either closed by a `betteruptime_heartbeat` sibling (shape authority: `betteruptime_heartbeat.workspaces_luks`, "DP-10", in `uptime-alerts.tf`) or carried as an OPEN issue whose number appears **inside the alert's own resource block**: `awk '/resource "logtail_exploration_alert" "inngest_luks_wrong_volume"/,/^}/' apps/web-platform/infra/betterstack-logs-alerts.tf | grep -c '#<N>'` ≥ 1. A file-scoped grep is rejected — that file already carries six other issue numbers. The probe's `3 CANNOT ESTABLISH` arm covers the gap in the meantime.
- [ ] **AC-35** `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0 — the form `ci.yml` runs. A hand-enumerated path list is pinned to a different input set.
- [ ] **AC-P8** `#8296` is closed **after** AC-25 and AC-26 hold and PR-2 has merged, by `gh issue close 8296`. The PR bodies say `Ref #8296`.
- [ ] **AC-37** Unchanged-gate floors hold: 96/96, 57/57, 665/665, 160/160, 79/79. None of the five reads the ledger, the variable's default, or the alert's paused state, so any movement is a real signal.

## Observability

```yaml
liveness_signal:
  what: >-
    the hourly SOLEUR_INNGEST_SERVER_PROBE row from host_role=dedicated, whose data_mount_devid
    field resolves the by-id alias of the device backing /mnt/data. Post-cutover that alias must
    be hcloud_volume.inngest_redis_luks's (scsi-0HC_Volume_106903269); anything else means the
    store is writing plaintext again.
  cadence: hourly; query_period 5400s covers one cadence plus slack
  alert_target: >-
    logtail_exploration_alert.inngest_luks_wrong_volume -> soleur-inngest-luks-wrong-volume-prd
    -> Better Stack incident, email = true, metadata.runbook -> inngest-luks-cutover-6894.md
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf
error_reporting:
  destination: >-
    Better Stack incident (email). Plus scheduled-followthrough-sweeper.yml, which on a non-zero
    exit POSTS A COMMENT headed "Sweeper run: ACTION REQUIRED" on the enrolled tracker and leaves
    it open, and on exit 1 REOPENS a closed one. It does NOT file an issue — an earlier draft of
    this section said it did.
  fail_loud: >-
    yes, structurally: the alert's SQL predicate is a NEGATION, so a row whose devid field is
    renamed, dropped or unreadable FIRES rather than going quiet.
failure_modes:
  - mode: the store is remounted on the plaintext backstop (on-host rollback, a boot taking the pre-cutover arm, a replace whose first boot resolved the plaintext volume)
    detection: the probe row's data_mount_devid stops matching the encrypted alias
    alert_route: logtail_exploration_alert.inngest_luks_wrong_volume (email)
  - mode: the probe emitter changes shape and the devid field is renamed or dropped
    detection: the negated predicate matches nothing and counts the row
    alert_route: same alert — the deliberate fail-loud arm
  - mode: the alert is re-paused after arming (a later apply, a Doppler value appearing, or a vendor-side pause — `paused` is optional+computed, so it can be changed outside Terraform)
    detection: heartbeat-live-reconcile now reports logs-alert-paused for this alert, because parseLogsAlertBlocks resolves !var.X against the declared default. Twice daily, on an existing runner. This is Phase 3 and it is why no bespoke arm-probe is needed
    alert_route: the reconciler's drift report
  - mode: a sanctioned op=luks-rollback puts the store back on the plaintext volume and no commit reverts the ledger or the register
    detection: scripts/followthroughs/inngest-luks-property-8296.sh exit 1 — it reads the store's actual alias and the ledger's claim together. The alert alone cannot see this: after a rollback the alert is unpaused and firing, so an "is it armed?" probe would report PASS while the claim is false
    alert_route: the sweeper reopens #8285 and comments ACTION REQUIRED
  - mode: the probe -> vector -> Better Stack path dies, so no rows arrive and on_missing_data = "treat_as_zero" reads absence as healthy
    detection: the same probe's 3 CANNOT ESTABLISH arm (no rows in the window). Partial: it reports, it does not page. The full fix is a dead-probe heartbeat, deferred as D1 with a dated trigger
    alert_route: the sweeper's comment
logs:
  where: >-
    Better Stack Logs, source id 2457081 (local.vector_prd_source_id), table
    t520508_soleur_inngest_vector_prd_3_logs as scripts/betterstack-query.sh defaults it
  retention: per the Better Stack plan recorded against the vendor row; not set by this change
discoverability_test:
  command: bash scripts/followthroughs/inngest-luks-property-8296.sh
  expected_output: "PASS"
  credentials_required: >-
    BETTERSTACK_QUERY_HOST/_USERNAME/_PASSWORD — the probe rows live in a private Better Stack Logs
    stream, there is no unauthenticated endpoint reporting which device backs /mnt/data, and the
    host has no SSH by design (hr-no-ssh-fallback-in-runbooks). All three are already wired into
    scheduled-followthrough-sweeper.yml.
```

A credential-free supplementary probe covers the record half only:
`python3 scripts/lint-encryption-posture.py --repo-sweep` prints `PASS`. It proves what the ledger
claims, never what the disk is doing.

### Soak Follow-Through Enrollment (Phase 2.9.1)

`scripts/followthroughs/inngest-luks-property-8296.sh`, enrolled on **#8285** with
`<!-- soleur:followthrough script=… earliest=<merge+1d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
and the `follow-through` label. No sweeper edit — all three secrets are already wired.

**Enrolled on #8285, never #8296, and the reason is structural.** The sweeper closes an open
tracker on exit 0 and thereafter refuses to re-litigate it; in closed mode only exit 1 reopens, a
non-1 non-zero logs "no action, no comment", and after `CLOSED_LOOKBACK_DAYS=14` the issue leaves
the query window entirely. A probe enrolled on the issue this change closes would have a maximum
useful life of 13 sweeps and a realistic one of zero. #8285 stays open until the backstop is
destroyed, which is exactly the window the claim needs watching.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis_luks
    mechanism: luks
    evidence: >-
      apps/web-platform/infra/inngest-redis-luks.tf, resource "hcloud_volume"
      "inngest_redis_luks"; the cryptsetup luksFormat + luksOpen apparatus resolving to mapper
      inngest-redis; key = random_password + doppler_secret co-located in inngest-redis-luks.tf.
      OBSERVED 2026-09-20: terminal SOLEUR_INNGEST_LUKS_CUTOVER row 15:29:10Z and the post-cutover
      probe row 15:36:40 pinning scsi-0HC_Volume_106903269 at /dev/mapper/inngest-redis. Content
      anchors only.
    defends_against: >-
      a seized, RMA'd or snapshot-imaged Hetzner block volume — the Inngest queue and run-state AOF
      are unreadable without the Doppler-held passphrase
    does_not_defend: >-
      a leaked credential, an app-layer read on the unlocked host, exfiltration through a
      compromised redis/inngest process — and, until #8285, the retained plaintext backstop
      hcloud_volume.inngest_redis, which holds a full second copy of this same AOF
    disclosed_as: not-publicly-claimed
    live_verification: >-
      unavailable:the hourly probe is runner-reachable and was OBSERVED post-cutover pinning this
      volume, but probe_schema=8 carries no crypto_LUKS type field — it proves WHICH device backs
      /mnt/data, not that the device is encrypted. The cipher half is the statically-resolved
      apparatus check_luks_row verifies. Flip to available in the commit recording a probe row with
      an explicit LUKS-type field, as hcloud_volume.registry's store_luks does; the floor moves with
      that flip, not this one. Tracked #6894 / D3.
  - store: hcloud_volume.inngest_redis
    mechanism: plaintext-exception
    evidence: >-
      apps/web-platform/infra/inngest-host.tf, resource "hcloud_volume" "inngest_redis" — retained,
      attached and intact after the additive cutover, by design
    defends_against: nothing at the volume layer
    does_not_defend: >-
      a seized or snapshot disk exposes a full second copy of the Inngest queue and run-state AOF —
      in-flight job payloads, i.e. user prompts and agent output — and no erasure path, including
      account deletion, reaches those bytes
    disclosed_as: not-publicly-claimed
    live_verification: >-
      unavailable:this row asserts the OPPOSITE of its sibling — a probe row whose data_mount_devid
      still pins THIS volume after the cutover means the store came back, which is what
      logtail_exploration_alert.inngest_luks_wrong_volume pages on
in_transit: unchanged — no new cross-component connection is introduced
exception:
  justification: >-
    retained plaintext backstop. The cutover is additive: the plaintext volume stays attached
    holding a copy of the same AOF, so a rollback is a mount move plus a reverse copy rather than a
    restore from a snapshot taken at an unknown moment
  tracking_issue: "#8285"
  reevaluate_when: >-
    the backstop is DETACHED and DESTROYED under #8285; ALSO on INNGEST_LUKS_CUTOVER=rolled-back,
    which inverts the sibling row's claim and requires reverting it and the Article 30 cells. It
    does not close on the cutover, which has already happened
  expires_on: "2026-10-22"
```

`expires_on` is **not** moved. Re-dating an at-rest exception forward buys plaintext time; the row's
own `expires_on_not_extended` field says so. Mechanical consequence: flipping the sibling to `luks`
removes that row from `check_exception_block` and with it *its* expiry, so hard expiry enforcement
survives only on the row that holds the plaintext bytes — which is why AC-4 pins the date by value
across revisions. And the enforcement is softer than it looks: `lint-encryption-posture.py` hard-fails
on a past `expires_on`, but its CI job is not a required check, so on 2026-10-23 the alarm reddens a
non-blocking job. Deferral D9 tracks that.

## Guard Contract

### Guard 1 — the wrong-volume alert drift guard (`apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`)

**Property.** The rule that detects the Inngest store returning to the plaintext volume is declared
armed, watches an alias derived from the resource rather than a literal, matches the devid field
with its key and a trailing space, negates the predicate so an unreadable row fires, and is
reachable by the apply that creates it.

**Assembly.** Four chokepoints, not "the assertions currently in the file": the
`logtail_exploration_alert.inngest_luks_wrong_volume` resource block and the `locals` block that
builds its alias and SQL (both in `betterstack-logs-alerts.tf`), the
`variable "inngest_luks_cutover_complete"` block in `variables.tf` — the arming value's only in-repo
carriage — and the `-target=` allowlist in `apply-web-platform-infra.yml`, without which the
resource is declared and never applied. The guard already reads all four files; what this change
adds is that `variables.tf` becomes a **mutation** target, which the harness cannot currently reach.

**Mutation matrix.** Rows 1-6 exist today and are re-run unchanged; they are tabulated rather than
summarised because the matrix is the contract, and a row named only in prose is a row the next
editor can drop without noticing.

| # | Edit | Must red because |
| --- | --- | --- |
| 1 | the alias becomes a literal id | a re-created volume leaves the rule watching a dead id and it goes quiet, which reads like health |
| 2 | the devid match loses its trailing space | `…_1234` is a prefix of `…_12345` |
| 3 | the negation flips to a positive match | the rule would fire on the RIGHT volume |
| 4 | the `host_role=dedicated` scope is dropped | web-1's rows would drive the alert |
| 5 | `paused` becomes a constant `true` | armed never |
| 6 | `query_period` shrinks below the probe cadence | "no rows" between emissions reads as healthy under `treat_as_zero` |
| **7** | `default     = true` reverts to `default     = false` in `variables.tf` | this is the post-cutover regression that matters: the alert disarms silently, the ledger keeps claiming `luks`, and every other row stays green. Row 5 does not cover it — row 5 mutates `$TF`; this chokepoint is `$VARS`. |
| **8** | `paused = !var.inngest_luks_cutover_complete` becomes a constant `false` | the expression is what lets a sanctioned rollback re-pause the rule with a one-line revert, and it is what ADR-218 records as this file's only variable-driven paused state. Row 5 pins the opposite constant; without this one only half the expression property is guarded. Measured sound: the existing `grep -qF` on the expression fails under this mutation. |

**Deliberately NOT added — a "lower the guard's own `_floor`" row.** It cannot red this guard, three
ways: `mutate_red` observes via `MUT_SKIP=1 bash "$SELF"`, which *overwrites* `_floor` with 13, so
the mutation is invisible; the check is `[ "$_ran" -lt "$_floor" ]`, so lowering a floor can only
make it pass; and `mutate_red` writes `$TF`, not `$SELF`, whose `REPO` is derived by `cd`-ing up
from `${BASH_SOURCE[0]}`. A row that cannot fail would make the guard permanently red on the
`mutation SURVIVED` arm. The anti-vacuity property it was reaching for is held instead by AC-14.

**No precedent; the pattern is novel.** A sweep of every mutation-battery suite in the repo
(`orphan-process-reaper-mutation.test.sh`, `ship-incident-pir-gate-mutation.test.sh`,
`lint-encryption-posture.test.sh`, `lint-legal-mirror-drift-baseline.test.sh`,
`lint-window-closure-assertion.test.sh`, `lint-legal-scope-block-placement.test.sh`) found the same
shape throughout: each mutator targets **one** fixed file and varies only the in-file span per row.
None takes a caller-supplied target or restores a second file. Reviewers should scrutinise the
parameterisation below as new surface rather than as an established convention — and the fact that
the existing `trap` restores nothing is itself evidence there was never a working two-file
precedent to lean on.

**Harness change — required, and it fixes a pre-existing defect this change makes dangerous.**

```bash
cp "$TF" "$MUT_DIR/pristine.tf"; cp "$VARS" "$MUT_DIR/pristine.vars.tf"
trap 'cp -f "$MUT_DIR/pristine.tf" "$TF" 2>/dev/null; cp -f "$MUT_DIR/pristine.vars.tf" "$VARS" 2>/dev/null; rm -rf "$MUT_DIR"' EXIT
```

- `mutate_red` takes a target: `mutate_red <label> <target> <pristine> <python-prog>`. A parameter,
  not a `mutate_red_vars` sibling — a sibling duplicates the restore logic, which is the part that
  must not drift.
- `assert_fixture_dir "$TF"` → `assert_fixture_dir "$target"`. Its P1b rationale applies identically
  to `$VARS`, which is built from the same `$REPO`; leaving it pinned to `$TF` guards the wrong file.
- Both restore sites — the anchor-drift `||` branch and the post-run `cp` — restore `$target`.
- **The `trap` currently restores nothing** (`trap 'rm -rf "$MUT_DIR"' EXIT` deletes the pristine
  copies). An interrupt mid-mutation today leaves `betterstack-logs-alerts.tf` mutated and destroys
  the only pristine copy. Extending the mutator to `$VARS` extends that to a file
  `apply-web-platform-infra.yml` reads on every push to `main`, so it is fixed here, with the copies
  taken before the trap is armed.
- `MUT_SKIP` re-entrancy is unaffected: the inner run re-reads both files from disk and skips the
  mutation block regardless of which was mutated.

**Harness rows** (hand-run meta-tests of the suite; they add no committed assertion, so the floor
does not move for them): **H1** — delete the new `$VARS` mutator's `assert` inside its python
program so the mutation silently no-ops; the suite must report
`mutation '…' did not land (anchor drifted)` and fail. **H2, must-PASS non-canonical** — a
`variables.tf` whose `default = true` uses different interior spacing must still PASS, because
Phase 2 step 1 replaces the fixed-width `grep -qF` with `grep -Eq 'default[[:space:]]+= true'`. That
is the fork decided rather than documented: a `terraform fmt` realignment must not silently disarm
the assertion.

**Floor arithmetic, measured.** 13 non-mutation assertions + 6 mutation rows = 19 today. Two new
mutation rows → **`_floor` 21**. The `MUT_SKIP` floor is the count of non-mutation assertions and
**stays 13** — this change inverts an existing assertion rather than adding one. AC-14 pins it.

**Anchor.** The guard compares stored expectations to files in the same commit, so one diff can edit
both. What must move outside the commit is the live `paused` field (AC-25) and the property probe's
reading of the store's actual alias (Guard 3). The drift guard alone proves consistency, not
integrity.

### Guard 2 — the live-pause exemption (`plugins/soleur/lib/heartbeat-live-reconcile.ts`)

**Property.** A logs alert whose declared `paused` is `!var.X` is treated as literal-false — and so
reported when it is live-paused — exactly when `X`'s declared default is `true`.

**Assembly.** Three chokepoints: `parseLogsAlertBlocks`, which decides `pausedIsLiteralFalse`; the
`l.paused && d.pausedIsLiteralFalse` gate in `reconcileLogsAlerts`; and `discoverLogsAlertsFromInfra`,
which is where the `vars` parameter has to arrive for the first to have anything to resolve against.
The resolver itself (`resolveInfraVariables`) is **not** a chokepoint of this change — it already
exists and is already exercised by the heartbeat and monitor paths, so a mutation of it would redden
their suites first. That is why mutation row 4 targets name-matching rather than the parse.

**Mutation matrix:**

| # | Edit | Must red because |
| --- | --- | --- |
| 1 | the `!var.X` resolution is removed | the exemption returns and a live-paused armed alert is reported by nothing — the state this guard exists for |
| 2 | resolution returns literal-false for *any* `!var.X`, ignoring the default | a deliberately-paused alert (default `false`) is reported as drift — a standing false page, which is how a real page gets muted |
| 3 | the variable cannot be resolved (missing file, renamed variable) and the parser returns literal-false | fail-open. It must stay exempt, never be treated as armed |
| 4 | the default is read from the wrong variable (name-prefix match rather than exact) | `inngest_luks_cutover_complete` and a hypothetical `inngest_luks_cutover_complete_v2` must not alias — the `workspaces`/`workspaces_luks` trap in a new place |

**Harness rows:** H1 — a must-PASS non-canonical: an alert declared `paused = false` literally
behaves exactly as before, so the change is additive rather than a rewrite of the existing arm.
H2 — the fixture's `variables.tf` stub is emptied; the suite must fail rather than silently fall
back to "expression, exempt" for the canonical case, or it is testing the fallback instead of the
feature.

**Anchor.** `logs-alert-absent` is already ungated on this flag, so the guard cannot be satisfied by
weakening absence detection. The integrity anchor is the live reconcile run itself, which reads
vendor state no repo edit can fake.

### Guard 3 — the property probe (`scripts/followthroughs/inngest-luks-property-8296.sh`)

**Property.** On any day while the backstop exists, the store is on the LUKS volume **and** the
ledger says so — or a human is told.

**Assembly.** Two chokepoints read in one run: the store's actual device, from the same probe rows
the alert's SQL reads, and the committed ledger row. Reading only the ledger certifies the repo
against itself; reading only the alert's *paused* state is the trap this probe was redesigned to
avoid — after a sanctioned rollback the alert is unpaused and firing, so an "is it armed?" probe
reports PASS while the claim is false.

**Mutation matrix:**

| # | Edit | Must red because |
| --- | --- | --- |
| 1 | the fixture's newest probe row pins the **plaintext** alias while the ledger reads `luks` | the rollback inversion — the one state nothing else in the repo reports |
| 2 | the fixture's ledger row reads `plaintext-exception` while the store is on the LUKS alias | the claim was withdrawn and the probe must not keep passing on the store alone |
| 3 | the fixture returns **no probe rows in the window** | must be `3 CANNOT ESTABLISH`, never `0` — `on_missing_data = "treat_as_zero"` already makes absence look healthy to the alert; a probe that repeats that mistake covers nothing |
| 4 | the fixture returns two rows, the newest on the LUKS alias and an older one on the plaintext alias | the verdict must be the newest row, not any row — an any-row match passes forever once one good row exists |
| 5 | the ledger read is moved *after* the probe's early return on a healthy store | an order mutation: the property is "both, in one run", and a probe that returns before reading the ledger satisfies every delete-shaped test while never observing the window it exists for |

**Harness rows:** H1 — malformed vendor JSON must give `3 CANNOT ESTABLISH`, never `0`. H2 —
must-PASS non-canonical: extra unrelated probe rows in the window pass, because the probe selects
the newest `host_role=dedicated` row rather than requiring a singleton response.

**Anchor.** The host's own emitted rows. Nothing in this repository can make Guard 3 pass by editing
a file — which is the property Guard 1 structurally cannot have.

## Alternative Approaches Considered

| Option | What it does | Verdict |
| --- | --- | --- |
| **A — declared default `false` → `true`, expression retained, plus the reconciler fix** (chosen) | The arming value is carried in git. `paused` stays `!var.X`, and `parseLogsAlertBlocks` learns to resolve it, so the alert re-enters live-pause drift reporting. | **Chosen.** It is inside the direction the tracker set, keeps ADR-218's recorded invariant true, keeps a rollback re-pause a one-line revert, and — because of the reconciler fix — costs nothing in coverage. |
| **B — `paused = false` literal, variable retired** | Collapses the indirection; no `TF_VAR_` can override a literal. | **Not chosen, and the reason changed during review.** Three reviewers argued for B on one premise: that the expression permanently exempts this alert from drift reporting. That premise is removable at its source for ~15 lines, which is Phase 3. With it removed, B's remaining benefit is the Doppler-override hazard — real, but answered by the Phase 0 read and by the fact that a Doppler value is now *visible* as drift rather than silent. B's costs are not zero: it deletes a variable ADR-218 records, and it makes a rollback re-pause a code change rather than a value change. |
| **C — Doppler `INNGEST_LUKS_CUTOVER_COMPLETE=true`** | The route the runbook documents today. | **Rejected.** The arm would live in a Doppler audit log and nowhere in the repo. Under Phase 3 it would at least be *visible* as drift, but it would still be a production write this session must not make, and the committed record would still read "paused". |
| **D — a tfvars entry** | The second option the tracker named. | **Not available.** Measured: no tfvars file exists in this repo and no workflow passes `-var-file`. |
| **E — one PR instead of two** | Everything in a single merge. | **Rejected on ordering.** Only `apps/web-platform/infra/**` fires the apply, so a single PR publishes the claim at merge and arms the detector minutes later — or never, if the apply halts. The split makes "the record may never lead the detector" structural instead of aspirational, and removes the need for a revert rule entirely. |

### Decision Challenges (headless — persisted, not asked)

Written to `knowledge-base/project/specs/feat-one-shot-8296-ledger-flip-arm-alert/decision-challenges.md`
for `soleur:ship` to render into the PR body and file as `action-required`. Both are recorded
because they were live disagreements among reviewers, not because they are unresolved here.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/variables.tf` — `inngest_luks_cutover_complete` default `false` → `true`.
Non-secret boolean; no provider added, no version pin moved, no sensitive variable introduced
(`hr-tf-variable-no-operator-mint-default` does not bite). `betterstack-logs-alerts.tf` — comment
only. No new resource, secret, vendor or persistent runtime process.

### Apply path

**The merge is NOT the authorization, and the plan's earlier claim that it was is retracted.**
Measured: `gh api repos/jikig-ai/soleur/branches/main/protection` returns `404 Branch not
protected`, and the rulesets on `main` are two `required_status_checks`, `deletion` and
`non_fast_forward` — **no `pull_request` rule**, therefore no required approving review and no
code-owner requirement. CODEOWNERS only auto-requests a reviewer. So the gate chain in front of an
unattended `terraform apply -auto-approve` over ~137 production addresses is CI status checks and a
CLA check, with no human structurally in the path. `hr-menu-option-ack-not-prod-write-auth` is
explicit that prior approvals do not extend to new commands — and here there is not even the prior
approval.

PR-1 therefore restores the ack rather than inheriting a false one: merge with
`[skip-web-platform-apply]` in the merge commit, then dispatch

```
gh workflow run apply-web-platform-infra.yml \
  --ref main \
  -f apply_target=manual-rerun \
  -f reason='Arm logtail_exploration_alert.inngest_luks_wrong_volume after the 2026-09-20 Inngest Redis LUKS cutover (#8296)'
```

which is a per-command go-ahead, shows the exact command, and supplies the `required: true` `reason`
the runbook's version omits. This is also the corrected form of
`inngest-luks-cutover-6894.md` §5 step 2, whose `apply_target=main` is not a valid `choice` option.

**Pre-merge, read-only, blocking:** the Doppler single-secret read (Phase 0.1).

**Verification comes from the world:** AC-26 polls the run to a terminal conclusion; AC-25 reads the
live `paused` field back, as an HTTP-status assertion and a payload assertion, so a 401 is
`CANNOT ESTABLISH` rather than "paused".

### Distinctness / drift safeguards

- **The apply grades the whole allowlist, not the two alert addresses.** `-target` narrows the
  *trigger*, never the *scope*. The blast radius of the merge is every drifted resource among ~137:
  `cloudflare_zone_dnssec`, ~28 `cloudflare_record.*` (apex A, MX, SPF/DKIM/DMARC), the firewall
  pair, ~30 Doppler secrets and service tokens, the GitHub Actions secret set, and the Cloudflare
  tunnel/Access path — DNS, mail deliverability, the SSH path and the prod secret surface.
  Materially larger than "an alerting posture", which is the case for reading the `plan` job's PR
  comment (Phase 0.2) rather than merging blind.
- **Destroy-guard counters: eight, not six.** The plan's earlier enumeration missed `plan_ok` and
  **`undecidable_entries`** — the latter counts entries at *any* address whose `.change.actions` is
  empty or not an array, HALTs above and outside the `destroy_count` sum so `[ack-destroy]` cannot
  reach it, and is provider-version-sensitive and address-agnostic. It is the most likely cause of
  "the merge landed, the apply halted, the claim is live, the alert is still paused" — and the PR
  split is what makes that harmless.
- **The `host_creates` reasoning is corrected.** The earlier claim — "`hcloud_server.web` is not in
  this path's target set" — is refuted by the filter's own comment: `-target` is transitive at the
  resource level and **two** allowlisted resources pull the whole `hcloud_server.web` map
  (`cloudflare_record.app` and `hcloud_firewall_attachment.web`). The conclusion survives — a bool
  default cannot cause a host create — but the correct statement is *unreachable from this edit,
  reachable from this plan*, which is why the plan must be read before merging.
  `luks_passphrase_rotations` is armed on this path and unbypassable, but
  `random_password.inngest_redis_luks` declares no `keepers` and its `doppler_secret` interpolates
  only TF-managed parents, so no variable change can force either.
- **Both escape hatches are unscoped.** `[ack-destroy]` acks `destroy_count` across the entire plan,
  not one address — so it is a strictly larger act than a benign alert replacement.
  `[skip-web-platform-apply]` skips the apply entirely, which in a single-PR world would mean "merge
  the claim, do not arm the detector". Under the split it is exactly the right token for PR-1, whose
  apply is then dispatched deliberately, and PR-2 carries no infra path at all.
- **`paused` is `optional: true, computed: true`.** A vendor-side pause is drift only the next apply
  corrects — which is precisely why Phase 3's reconciler fix, not a bespoke probe, is the control.

### Vendor-tier reality check

Better Stack free tier: `email = true`, `push`/`call`/`sms` and `critical_alert` false, routed
through `escalation_target { team_name = "Your team" }` because `var.betterstack_paid_tier` is
`false` — no `betteruptime_policy`, so there is no escalation chain behind the email. An unread
inbox is the whole failure mode for this detector; arming it does not change that. Timing parameters
are unchanged and tier-independent (`check_period = 300`, `query_period = 5400`,
`recovery_period = 10800`, `on_missing_data = "treat_as_zero"`). No Hetzner sizing decision is
involved. Prices reflect training data; verify at the provider's pricing page before any budget
decision.

## Architecture Decision (ADR/C4)

This change makes no new architectural decision — it records that ADR-142's has been realised. Three
recorded artifacts describe the pre-cutover world and two of them instruct a reader to do the wrong
thing, so the records move with the change.

### ADR

- **ADR-142** (`accepted`) — **append**, never edit; its convention is "Appended, not edited."
  Records the observed cutover and, load-bearingly, corrects apparatus-scope item 8, which reads
  "flip `hcloud_volume.inngest_redis` `mechanism` → `luks`" — the opposite of what the ADR's own
  2026-09-18 amendment and both ledger rows require. A reader who follows item 8 flips the backstop
  row and destroys the expiry clock #8285 depends on.
- **ADR-218** — append: "It ships PAUSED" is falsified at the arm. (It does **not** carry the dead
  `-var` route; that report was checked and did not hold.)
- **ADR-141** (`adopting`, blockers `[6894, 8386, 6897]`) — **not moved to accepted**, and its
  `live_coverage_floor` clause is **not** triggered by this change, because `live_verification`
  stays `unavailable:`. Its "the floor moves with it" sentence presupposes the flip to `available`
  is earned; D3 records what would earn it.
- **ADR-199**, **ADR-140** — untouched; ADR-199's empty-store route stays preserved as
  lapsed-not-forgotten in the backstop row's `reevaluate_when`, and this change is ADR-140 working
  as designed.

No new ADR ordinal is claimed, so there is no ordinal-collision exposure.

### C4 views

All three model files were read in full. **External human actors:** none added or changed.
**External systems/vendors:** none added — `betterstack` and `doppler` already carry the edges this
relies on. **Containers/data stores:** none added; neither AOF volume is its own element, an
asymmetry with `workspacesVolume`/`gitDataStore` that is pre-existing and neither created nor
depended on here. **Access relationships:** none change.

**One element description is falsified and is corrected here.**
`platform.infra.inngestRedis` contains, verbatim, `AT REST: STILL PLAINTEXT ext4` and
`AT REST IS STILL PLAINTEXT AS OF THIS EDIT`, plus a `format = "ext4"` under
`ignore_changes = [format]` citation the 2026-09-03 ledger correction already made stale. ADR-140's
own `## C4 impact` section is the governing precedent: otherwise the model carries the same
claim-vs-reality gap the ADR closes.

`views.c4` and `spec.c4` need no edit — the element is already in the `containers` include list, and
no element kind, tag or relationship kind is added.

**Cardinality check.** All six embedded counts in `model.c4` were enumerated. The two in the Better
Stack blast radius — the `4 monitors + 9 heartbeats = 13 objects` inventory line, which counts
`betteruptime_monitor`/`betteruptime_heartbeat` objects (a `logtail_exploration_alert` is neither),
and "the first, soleur-monitor-send-failed-prd", a historical ordinal — are **not** falsified, and
arming creates no new vendor object because the alert is already declared.
`plugins/soleur/test/c4-count-parity.test.sh` reports `Passed: 10  Failed: 0`. **That gate only
parity-checks `github -> sentry` and `github -> resend`**, so a green run is not evidence of
consistency with this change; AC-23 is.

**Not edited:** the `betterstack -> founder` edge, which enumerates paging surfaces and names no
Logs alert. That staleness predates this change — the first Logs alert was already unnamed — so it
is out of scope for P4 rather than a claim this flip falsifies.

## Domain Review

**Domains relevant:** engineering, legal, product.

### Engineering

**Status:** reviewed — `soleur:engineering:infra:terraform-architect` (IaC routing gate),
`soleur:engineering:review:architecture-strategist`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`,
`soleur:engineering:cto`.

**Assessment.** The panel changed the plan's shape, not just its details. Architecture refuted the
authorization claim against the live GitHub API and demanded the PR split; it also measured that the
prescribed ForceNew probe cannot answer its question, and corrected the `host_creates` reasoning and
the destroy-guard count. Kieran found that raising the `MUT_SKIP` floor would have shipped a green
guard over a dead battery, that mutation row 9 was unimplementable three ways, that the `mutate_red`
trap has never restored anything, and five AC commands that false-fail a correct implementation.
DHH and code-simplicity both argued the plan was over-built around a timid mechanism choice; their
shared premise — the permanent reconciler exemption — was removed at source instead, which is Phase
3. CTO found the compensating probe retires on its own first success, and found a live defect the
plan had missed: the staging follow-through is permanently falsified and posts a false regression
comment daily.

### Legal

**Status:** reviewed — `soleur:legal:clo`, plus `soleur:gdpr-gate`.

**Assessment.** The Article 30 amendment is a **deliverable**, on three independent grounds: the
standing attestation's `re_evaluation_triggers` fires at this commit, the cells name #8296 as their
own amending event, and the register is the Art. 30(1) record itself. CLO supplied the in-cell dated
bracket convention and draft text. DPIA: no. Art. 33/34: no — a controller-internal security-measure
transition is not an Art. 4(12) event, the copy was byte-proven identical before `swap_forward`, and
the source volume is retained. Controller/processor notification: no. `disclosed_as:
not-publicly-claimed` remains true after the flip — a sweep of `docs/legal/**` and
`compliance-posture.md` for the volume returns zero hits.

The GDPR gate returned **zero Critical and six Important**, and flagged that result as a finding:
its Critical tier keys on Art. 9 *column names*, so a Redis AOF of unbounded free-text user prompts
can never produce one. It also measured that **none of this change's paths matches the canonical
regex** behind `hr-gdpr-gate-on-regulated-data-surfaces`, so Phase 2.7 would not have auto-fired.
Both are deferred (D4). Ship hazard noted: `#7529` is an OPEN `compliance/critical` with no Active
Items row, so `soleur:ship` Phase 5.5 blocks if the PR body references it — decided here: do not
reference it.

### Product/UX Gate

**Tier:** none. No file in `## Files to Edit` or `## Files to Create` matches the UI-surface term
list or glob superset; the mechanical override does not fire.

### Product (CPO)

**Status:** reviewed. **Sign-off: GRANTED-CONDITIONAL**, and all conditions are folded in.

The earlier four (live vendor read-back with its output in the PR body; the revert/ordering rule;
the dead-probe gap closed or on the record at the resource site; the corrected User-Brand Impact
limb naming the *durable* un-arm) are satisfied — the ordering condition is satisfied structurally
by the PR split rather than by a revert rule. The **new blocking condition** was that the plan
contradicted itself on `live_verification`: its Cut List said bare `available` was unearned while
Phase 1 set it anyway and moved the coverage floor. Resolved in the direction CPO named: hold at
`unavailable:` and leave the floor at 1, consistent with how `hcloud_volume.registry` is held for a
weaker reason.

Two non-blocking recommendations are carried as D2 and D10.

**Agents invoked:** `soleur:engineering:infra:terraform-architect`,
`soleur:engineering:review:architecture-strategist`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`,
`soleur:product:spec-flow-analyzer`, `soleur:engineering:cto`, `soleur:product:cpo`,
`soleur:legal:clo`, `soleur:gdpr-gate`,
`soleur:engineering:research:repo-research-analyst`, `soleur:engineering:research:learnings-researcher`.
**Skipped specialists:** none. `soleur:marketing:cmo` and `soleur:product:design:ux-design-lead` were
not activated — the independent relevance read found no market/brand/user-copy language and no
UI-surface path.
**Pencil available:** N/A (no UI surface).

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | `lint-encryption-posture.py --ledger <edited>` after both row rewrites | `0 failing checks -> PASS`. Dry-run against the exact intended shape. |
| T2 | Flipped row with its `exception` block left in place | **Passes both gates** — `check_at_rest` early-returns on `luks`, and the schema permits `exception` on `at_rest`. AC-2 is the only thing that catches it. |
| T3 | `live_verification` set to `available: observed 2026-09-20` (with a suffix) | Schema failure — `^(available\|unavailable:.+)$`. The bare literal is the only accepted "available". |
| T4 | Ledger with floor 2 but the row left at `plaintext-exception` | `FAIL: live-coverage floor`. Recorded because it is why the floor move *would* have been a real guard — and it is still not taken, because the claim is unearned. |
| T5 | `bash …/inngest-luks-wrong-volume-alert.test.sh` after Phase 2 | `>= 21 passed, 0 failed, floor 21`. |
| T6 | `MUT_SKIP=1 bash …` after Phase 2 | **13 passed, floor 13.** A 14 here silently vacuates the whole battery. |
| T7 | Guard 1 row 7: revert `default` to `false` in a scratch `variables.tf` | Non-zero exit. |
| T8 | Guard 1 harness H1: the `$VARS` mutator's `assert` deleted | `mutation '…' did not land (anchor drifted)` and fail. |
| T9 | Guard 2 row 1: the `!var.X` resolution removed | `bun test heartbeat-live-reconcile.test.ts` red — a live-paused armed alert is reported by nothing. |
| T10 | Guard 2 row 3: the variable is unresolvable | Stays exempt (fail-closed), never treated as armed. |
| T11 | Guard 3 row 1: newest probe row pins the plaintext alias, ledger reads `luks` | exit 1 — the rollback inversion. |
| T12 | Guard 3 row 3: no probe rows in the window | exit 3 `CANNOT ESTABLISH`, never 0. |
| T13 | Guard 3 row 4: newest row LUKS, older row plaintext | PASS — the verdict is the newest row. |
| T14 | The five unchanged gates | 96/96, 57/57, 665/665, 160/160, 79/79. |
| T15 | `c4-count-parity` + the two c4 suites | Green — and blind to the `inngestRedis` prose change, which is AC-23's job. |
| T16 | `lint-infra-no-human-steps.py --changed --base origin/main` | Exits 0. |

## Risks & Sharp Edges

- **The lint cannot catch a half-done flip.** `check_at_rest` returns before `check_exception_block`
  and before `check_disclosed_as_not_encrypted` on a `luks` row, and the schema permits `exception`
  there. Three ACs exist only because of that.
- **`live_verification` is not free text**, and `available` with any suffix is a schema failure. The
  citation goes in `evidence`.
- **Do not re-date `expires_on`.** After the flip the backstop row is the sole carrier of hard
  expiry enforcement for the pair — and that enforcement runs in a job that is not a required check
  (D9).
- **A Doppler secret of the same name wins silently**, with no Terraform diagnostic. Phase 0.1 is
  blocking. Under Phase 3 such an override at least becomes *visible* as drift.
- **The apply grades the whole plan**, and two of the eight guard counters (`plan_ok`,
  `undecidable_entries`) are unbypassable and address-agnostic. The PR split is what makes an
  unrelated halt harmless.
- **`[ack-destroy]` is not address-scoped.** If `paused` turns out to be ForceNew, the "remedy" acks
  every destroy in the plan — strictly larger than the change. Phase 0.2 settles it before merge.
- **The sweeper is a one-shot latch, not a monitor.** Exit 0 closes the tracker and it is never
  re-litigated; in closed mode only exit 1 reopens; after 14 days the issue leaves the window. Any
  probe enrolled on an issue this change closes would be dead on arrival. Hence #8285.
- **A probe that asks "is the alert armed?" passes during a rollback**, because the alert is
  unpaused and firing. Guard 3 asks about the store instead.
- **Ship Phase 5.5 hazard:** `#7529` is OPEN `compliance/critical` with no Active Items row. Decided:
  do not reference it in either PR body.
- **Never reuse, reset or remove `.worktrees/luks-stage-8294`** — it belongs to the parent session.

## Deferred Capabilities

| # | Deferred | Why not here | Re-evaluation trigger |
| --- | --- | --- | --- |
| D1 | A dead-probe heartbeat for the wrong-volume alert (`on_missing_data = "treat_as_zero"` reads an absent row as healthy) | A new `betteruptime_heartbeat` is a new vendor object on the same commit that arms the detector. Guard 3's `3 CANNOT ESTABLISH` arm covers reporting in the meantime; AC-33 forbids silence | **2026-10-22** — a date, not an event. After the backstop is destroyed, a dead probe is the only remaining way a silent rollback goes unnoticed |
| D2 | Move #8285 out of "Post-MVP / Later" into Phase 4, matching its parent #6894 | One `gh issue edit --milestone` call, but a roadmap action rather than an engineering one | Immediately, by the operator. A dated truthfulness bound parked in an undated bucket is how a 2026-10-22 expiry becomes a 2027 plaintext volume |
| D3 | The probe emits no LUKS-type field, so the live half proves device identity and not cipher | A host-emitter change needing a boot to observe. `hcloud_volume.registry`'s `store_luks` is the shape authority | The next `inngest-bootstrap.sh` probe-schema bump. **This is what would earn bare `available` and the floor move** |
| D4 | The GDPR gate's canonical regex reaches no at-rest infrastructure declaration, nor the ledger, nor the Article 30 register; and its Critical tier is reachable only through Art. 9 column names | A regex widening affects every plan and every lefthook run | File with `domain/engineering` + `type/chore` + `priority/p2-medium`. **`compliance/improvement` does not exist** — measured via `gh label list`; do not prescribe a label that must be created |
| D5 | `check_disclosed_as_not_encrypted` never runs on a `luks` row | A control-flow change affecting all four existing `luks` rows | The next `lint-encryption-posture.py` change; those four rows are the regression set |
| D6 | Art. 17 erasure reaches neither AOF copy (`account-delete.ts` has no Redis step) | A CLO determination on processing scope, already tracked | CLO's call |
| D7 | The DPA template's at-rest enumeration omits the Inngest Redis AOF | Adding it now would be the overclaim, while the backstop is attached | After #8285 closes |
| D8 | `main` has no `pull_request` rule, so no infra merge has ever carried a required review | Adding a ruleset is its own change with repo-wide blast radius. Named here because this plan's earlier safety case rested on believing it existed | Before the next change that wants to argue a merge authorizes an apply |
| D9 | The `encryption-posture` CI job is not in `required-checks.txt`, so the ledger's own expiry alarm reddens a non-blocking job | Promoting a check is a ruleset change | Before 2026-10-22, with #6894 / #6897 / #8285 / #8386 reviewed as one batch — nine of ten ledger exceptions share that date and will go red together |
| D10 | No standing check reads a runbook's `gh workflow run` command against the workflow it names | ~35 lines, its own change. **Evidence, measured:** beyond the one this plan fixes, `www-redirect-alarm.md` omits the `required: true` `reason`; `cloudflare-service-token-rotation.md` and `oauth-probe-failure.md` omit required inputs; `registry-luks-recut-6929.md` omits a required `action`; `moved-block-wedge-cutover-5887.md` names two deleted enum values | File with the evidence above in the body, registered in `test-all.sh`'s `test-scripts` shard |
| D11 | The Article 30 register and `model.c4` restate at-rest posture as hand-written prose with no anchor back to a ledger store id — which is why a dozen ACs here are bespoke greps, two of which had to be rewritten mid-plan | A real extension of the `disclosed_as` anchor mechanism; ADR-worthy | Fold into D5's window. The case is that **#8285 moves the same six records again in about four weeks**, so the second occurrence is already on the calendar |
