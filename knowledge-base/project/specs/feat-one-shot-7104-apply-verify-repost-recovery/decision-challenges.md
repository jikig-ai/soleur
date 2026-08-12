# Decision challenges — feat-one-shot-7104-apply-verify-repost-recovery

Recorded headless by `soleur:plan`. `ship` renders these into the PR body and files an
`action-required` issue. Each is a place where the plan **deviates from the operator's stated
direction**, or where a sign-off is outstanding. The operator's direction is the default; these
are surfaced for a decision, not applied silently.

---

## UC1 — The plan does not use `continue-on-error` on the verify step

**Operator's stated direction (issue #7104, "Suggested shape", point 1):**
> `continue-on-error: true` on the verify step; capture its `outcome`.

**What the plan does instead.** Keeps the step fail-closed and performs the bounded one-shot
re-push *inside* it, so the step's own exit code stays the single terminal verdict. Points 2, 3
and 4 of the suggested shape are honoured as written; point 3's "final adjudication step" becomes
the final *statement* of the same step, and it is still the thing that fails closed.

**Why.** Two measured reasons.

1. **Seven downstream steps key off job status.** `Alert on a red infra-config gate (#7220)` is
   conditioned on `failure() && steps.infra_config_gate.outcome != 'success'`. Under
   `continue-on-error` the job stays nominally green at that point, so `failure()` is false and
   the P0 alert **goes dark** on a first-pass failure — the documented trap in
   `knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md`.
   Five further steps use bare `success()`; two of them **close GitHub issues** and one swaps the
   running container. Adopting `continue-on-error` means re-wiring all seven conditions, and each
   rewiring is a fresh opportunity for exactly the fail-open the issue exists to prevent. There is
   also a second-order defect: on a *recovered* run `steps.infra_config_gate.outcome` stays
   `failure` permanently, so any later unrelated step failure would fire the alert blaming the
   infra-config gate.
2. **The alternative split shape is not actually available.** GitHub steps default to
   `if: success()`, so a separate `Re-push` step placed after a failed verify is **skipped** and
   the job has already failed. Making it work requires either `continue-on-error` on pass 1 or
   making pass 1 exit 0 and stash a verdict — the same fail-open surface, but implicit rather than
   declared. The in-step shape is therefore forced, not merely preferred.

**What the operator is being asked.** Confirm the deviation, or direct that the suggested shape be
implemented with all seven downstream conditions re-wired. The plan's primary acceptance criterion
(the gate still fails closed) is met either way; the deviation is about which shape has the
smaller surface for getting it wrong.

---

## UC2 — Scope grew beyond the re-POST recovery, and the growth is not optional

The issue asks for a bounded re-push. Delivering only that would have shipped a recovery that
fires on the **wrong runs**. Three additional changes are therefore in scope, each fixing a live
defect that the recovery would otherwise amplify:

- **`DPF_REPLACED` gating** — three supported merge classes (`seccomp-bwrap.json`,
  `apparmor-soleur-bwrap.profile`, `server.tf`) fire this workflow without replacing
  `terraform_data.deploy_pipeline_fix`, so no push happens, no frame is published, and the #7220
  freshness pin reds the run today. Without this gate the new recovery would convert each of those
  false-reds into a full production re-push.
- **Saved-plan apply (`-out=` / apply the plan file)** — required to source `DPF_REPLACED`, and it
  closes a pre-existing TOCTOU where the `host_creates` destroy-guard adjudicates a plan that is
  then discarded and re-planned.
- **Host-vs-host freshness** — the recovery makes clock skew strictly worse (one spurious
  production write per run, permanently) unless both sides of the comparison come from the host's
  clock.

**What the operator is being asked.** Accept the larger scope in one PR, or direct a split. If
split, the natural cut line is after the discriminator work: PR-A ships `DPF_REPLACED` +
saved-plan + host-vs-host freshness (a bug fix for live false-reds, independently valuable), and
PR-B ships the bounded re-push on top. Shipping the re-push *first* is not an option.

---

## SO1 — CPO sign-off is outstanding

`brand_survival_threshold: single-user incident` sets `requires_cpo_signoff: true`. The Product
domain was assessed **NONE** by both the semantic sweep and the mechanical UI-surface override —
there is no user-facing surface in this change — so no Product/UX gate ran. The sign-off
requirement comes from the threshold, not from a UI surface.

The threshold is set at `single-user incident` because the gate protects delivery of
`/etc/default/soleur-doppler-token` and `/etc/webhook/hooks.json` to a host the repo treats as
unreplaceable, and #7095 records that a malformed credential there bricks the only no-SSH
remediation channel.

**What the operator is being asked.** Confirm the threshold and provide the sign-off, or downgrade
the threshold to `aggregate pattern` with a reason. `user-impact-reviewer` is invoked at review
time either way.

---

## Note — two advisory claims were rejected on measurement

Not challenges to the operator; recorded so they are not re-introduced by a later reader.

- An advisory asserted that **ADR-068 §Amendment already decides this exact shape** and should be
  cited as precedent. ADR-068 is the multi-host-workspaces / git-data lease-coordinator ADR; it has
  no `## Amendment` section, and both of its addenda concern the git-data host's instance type. No
  ADR in the corpus decides this. The ADR is therefore written, not cited.
- An advisory asserted that **a `server.tf` edit does not fire this workflow** because the paths
  filter's comment says `server.tf` is deliberately absent. The entry
  `- "apps/web-platform/infra/server.tf"` is present in the filter, three lines below that comment.
  The comment is false about the code beneath it — filed as a separate defect (plan R9.1).
