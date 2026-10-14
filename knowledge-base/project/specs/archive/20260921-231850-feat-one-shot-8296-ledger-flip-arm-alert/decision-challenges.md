# Decision Challenges — feat-one-shot-8296-ledger-flip-arm-alert

Raised during planning and plan-review, persisted rather than asked because this run is headless.
`soleur:ship` renders these into the PR body and files them as `action-required`.

## DC-1 — This ships as TWO PRs, not one

**Stated direction.** The tracker scoped one PR with two parts: flip the ledger, arm the alert.

**What changed it.** Only `apps/web-platform/infra/**` fires the production apply. In a single PR
the ledger's encryption claim and the Article 30 amendment land **at merge**, while the alert
unpauses only on the apply that follows — and only if that apply survives eight HALT counters
graded over the **whole** ~137-address allowlist, two of which (`plan_ok`, `undecidable_entries`)
are unbypassable and have nothing to do with this change. Every halt path leaves a published at-rest
claim live with the detector still paused. The plan's own rule is "the record may lag the detector;
it may never lead it", and one PR cannot enforce it.

**Resolution.** PR-1 carries the infra paths and arms the detector; PR-2 carries the records and
fires no apply at all, so it cannot halt. This makes the ordering structural and removes the need
for a revert rule entirely.

**What the operator may want to veto.** Two PRs instead of one, and #8296 closing only after PR-2.

## DC-2 — The arming mechanism, and the premise that dissolved the fork

**Stated direction.** "Check how the other infra vars carry environment-specific values before
choosing between changing the declared default and adding a tfvars entry."

**What was measured.** Half the menu does not exist: `git ls-files | grep -ic tfvars` → `0`, and no
workflow passes `-var-file`.

**The challenge.** `soleur:engineering:infra:terraform-architect`,
`soleur:engineering:review:dhh-rails-reviewer` and `soleur:engineering:review:code-simplicity-reviewer`
all argued for a third option the direction did not name: delete the variable and write
`paused = false` literally. Their shared premise was that keeping the expression permanently exempts
this alert from `heartbeat-live-reconcile`'s live-pause drift reporting, leaving the only detector
for "the store quietly went back to plaintext" unwatched.

**Resolution — the premise was removed at its source rather than the variable being deleted.**
`soleur:product:spec-flow-analyzer` found that `pausedIsLiteralFalse` has exactly one key, and that
teaching `parseLogsAlertBlocks` to resolve `!var.X` against the variable's declared default (~15
lines, Phase 3) restores twice-daily coverage on a runner that already exists. With the premise
gone, the plan keeps the declared-default flip: it stays inside the stated direction, keeps
ADR-218's recorded invariant true, and keeps a rollback re-pause a one-line value change rather than
a code change.

**What the operator may want to veto.** Keeping `var.inngest_luks_cutover_complete` at all. Three
reviewers would still delete it. The residual argument for deleting is that no `TF_VAR_` can
override a literal; the counter is that under Phase 3 a Doppler override becomes *visible* as drift
instead of silent, and Phase 0.1 reads for it before merge.

## DC-3 — `live_verification` stays `unavailable:`, and the coverage floor stays 1

**What the plan originally did.** Set the flipped row's `live_verification` to the bare literal
`available` and moved `live_coverage_floor` 1 → 2, citing ADR-141's "the row flips — and the floor
moves with it — in the commit recording an observed boot."

**The challenge.** `soleur:product:cpo` made this a blocking condition and
`soleur:engineering:review:architecture-strategist` reached it independently: the plan's own Cut
List and deferral D3 both say the probe emits `data_mount_devid`, which proves **which device**
backs `/mnt/data`, never that the device is `crypto_LUKS`. `available` is the exact token
`check_live_coverage_floor` counts, so moving it moves a published coverage claim on evidence that
does not support it — while `hcloud_volume.registry` is held at `unavailable:` for a *weaker* reason.

**Resolution.** Hold at `unavailable:` with the cipher-half gap named, and leave the floor at 1. The
repo's precedent is to under-claim. Deferral D3 records what would earn the flip: a probe row
carrying an explicit LUKS-type field, as `registry`'s `store_luks` does.

**What the operator may want to veto.** Under-claiming encryption coverage for a store that is, in
fact, encrypted.

## DC-4 — A retracted safety claim the operator should know about

Not a challenge to the operator's direction — a correction to something this plan previously
asserted as verified, recorded here because it changes how every infra merge in this repo should be
read.

The plan stated that "CODEOWNERS + branch protection on `main`" made the merge the authorization for
the production apply. **Measured: false.** `gh api repos/jikig-ai/soleur/branches/main/protection`
returns `404 Branch not protected`; the rulesets on `main` carry no `pull_request` rule, so there is
no required approving review and no code-owner requirement. The sentence was inherited verbatim from
`apply-web-platform-infra.yml`'s own comment, which has been wrong since PR #4220 removed the
reviewer gate.

PR-1 corrects that comment and restores a real ack: merge with `[skip-web-platform-apply]`, then
dispatch `apply_target=manual-rerun` with a reason. Deferral D8 tracks adding the missing rule.
