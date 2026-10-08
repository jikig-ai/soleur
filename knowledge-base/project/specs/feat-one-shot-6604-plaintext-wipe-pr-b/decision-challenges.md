# Decision challenges — feat-one-shot-6604-plaintext-wipe-pr-b

Recorded headless by `soleur:plan` (one-shot pipeline). `soleur:ship` renders these into the PR body
and files them as an `action-required` issue. The brief's direction is the default until the
operator decides otherwise.

## UC-1 (User-Challenge): `Closes #6604` at final merge

- **Brief said:** the final PR body carries `Closes #6604` and `Closes #6588` (`Ref` while draft).
- **Challenge:** #6604 carries the `follow-through` label. `.claude/hooks/pre-merge-auto-close-scan.sh`
  denies a close keyword against an OPEN `follow-through` issue, because closing it makes the daily
  sweeper skip it. The sweeper (`scripts/followthroughs/workspaces-luks-soak-6604.sh`) is #6604's
  designed closer: it passes on ADR-119 `accepted` plus a clean 7-day drift window plus a live
  heartbeat span. `Closes #6604` would need `SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1`, which skips the soak.
- **Recommendation:** final body `Ref #6604` + `Closes #6588`. The sweeper closes #6604 on its first
  run that is after the merge and at least 7 days after the last `op:workspaces-luks-drift` event.
- **Cost of the brief's direction:** an ack-env bypass of a merge gate, and a soak that never
  re-runs. **Cost of the recommendation:** #6604 closes days after the merge instead of at it.
- **Concurred by:** CPO (plan-time sign-off).

## UC-2 (User-Challenge): Terraform protection of the sole-copy LUKS volume, in this PR

- **Brief said:** decide the delete-protection question for volume `106443278` and record it in the
  PR body (the archived §E offered `delete_protection = true` or a recut-gate refusal).
- **Decision taken:** both `prevent_destroy = true` and `delete_protection = true` on
  `hcloud_volume.workspaces_luks` in this PR (plan D1). The CTO showed the volume is in the SSH stage's
  push-apply closure, so config protection is delivered (one in-place update at the post-merge
  `manual-rerun` apply) rather than drifting, and `prevent_destroy` refuses every destroy path,
  including the recut `-replace`, which #6931 had deferred only because of that collision.
- **Why surfaced:** it supersedes #6931's recorded deferral of `prevent_destroy` and makes the
  `workspaces-luks-recut` dispatch arm plan-fail for the live volume. Revert path: drop the two lines.

## T-1 (Taste): kept the `CONFIRM_WIPE` tombstone (DHH would delete it)

- DHH and code-simplicity argued nothing can deliver `CONFIRM_WIPE` once the workflow wiring is gone.
  CTO and spec-flow judged the six-line refusal worth keeping (no fall-through to the L3 cutover body;
  `assert_mode_exclusive` and T4h-c unchanged). Kept, with its guard trimmed to four rows.

## T-2 (Taste): no watchdog for a long-disabled push-apply workflow

- SpecFlow proposed a detector for `apply-web-platform-infra.yml` / `apply-deploy-pipeline-fix.yml`
  sitting `disabled_manually` for more than 24 h. Not built: plan D6 makes PR B merge-ready before D, so
  the pause is hours long by construction, and `scheduled-terraform-drift.yml` already reports every
  unapplied merge. Offered as a follow-up if the operator wants a mechanical alarm.

## T-3 (Taste): kept the `blocked` label and the device-capability fields

- Code-simplicity: no tool reads a `blocked` label. Kept as the operator-visible mark the CPO asked
  for; the draft state is the mechanical block.
- DHH: drop `hdr_sha256`, `discard_*`, `io_max`, `scheduler` from the destruction record. Kept: the
  CLO-approved field set of the PR A template requires them.
