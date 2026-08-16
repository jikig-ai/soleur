# Decision challenges — feat-one-shot-7104-apply-verify-repost-recovery

Recorded headless by `soleur:plan`. `ship` renders these into the PR body and files an
`action-required` issue. Each is a place where the plan **deviates from the operator's stated
direction**, or where a sign-off is outstanding. The operator's direction is the default; these
are surfaced for a decision, not applied silently.

> **All three items were put to the operator on 2026-08-12, before implementation began, and are
> DISCHARGED.** Dispositions are recorded inline below and in `session-state.md`. `ship` should
> render them as *resolved* — it must **not** file an `action-required` issue for UC1, UC2 or SO1.
> They are not to be re-litigated by a downstream reviewer.

---

## UC1 — The plan does not use `continue-on-error` on the verify step

**Operator's stated direction (issue #7104, "Suggested shape", point 1):**
> `continue-on-error: true` on the verify step; capture its `outcome`.

**What the plan does instead.** Keeps the verification fail-closed rather than adopting
`continue-on-error`. Points 2, 3 and 4 of the suggested shape are honoured as written.

> **SUPERSEDED IN MECHANISM, NOT IN CONCLUSION — read this before the reasoning below.**
> This section described the re-push as happening *inside* the verify step, with "the step's own
> exit code as the single terminal verdict" and point 3's final adjudication becoming "the final
> statement of the same step". That inline-latched-block design was **PRUNED** by plan R22.6 and is
> not what ships. What ships is the three-step split — sensing (`infra_config_gate`), adjudication
> and grading (`repush_plan`), actuation (`repush_apply`) — with the terminal verdict rendered by a
> SECOND invocation of the same verify artifact (`infra_config_gate_pass2`) and backstopped by an
> `always()` step. Boundedness is structural (a step cannot run twice in a job) rather than latched.
>
> The paragraphs below are retained because their REASONING is why `continue-on-error` was
> rejected, and that conclusion is unchanged and is now enforced by assertion (AC18). But the
> mechanism they describe in the present tense is not the shipped one, and this file is rendered
> into the PR body — so left uncorrected the PR would have asserted a design that contradicts
> ADR-189.

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

**DISPOSITION (operator, 2026-08-12): deviation ACCEPTED.** The verify step stays fail-closed by its
own exit code, with the bounded re-push performed inside it. Points 2, 3 and 4 of the issue's
suggested shape are honoured as written. `continue-on-error` must **not** appear on the verify step
(tasks 6.6); the seven downstream status-keyed conditions are left untouched.

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

**DISPOSITION (operator, 2026-08-12): SPLIT CONFIRMED — and both PRs ship in this run**, as two
sequential cycles: PR-A through full review/QA/ship first, then PR-B on top. Shipping PR-A alone
was explicitly rejected because it would leave the reported defect unfixed. Consequence for
`ship`: **`Closes #7104` attaches to PR-B, not PR-A.** PR-A references #7104 in prose only.

---

## SO1 — CPO sign-off is outstanding

`brand_survival_threshold: single-user incident` sets `requires_cpo_signoff: true`. The Product
domain was assessed **NONE** by both the semantic sweep and the mechanical UI-surface override —
there is no user-facing surface in this change — so no Product/UX gate ran. The sign-off
requirement comes from the threshold, not from a UI surface.

The threshold is set at `single-user incident` because the gate protects delivery of
`/etc/default/soleur-doppler-token` and `/etc/webhook/hooks.json` to a host the repo treats as
unreplaceable.

**CORRECTED at review — the citation that justified the threshold was inflated.** This read "and
#7095 records that a malformed credential there bricks the only no-SSH remediation channel."
#7095 records no such thing. Its title is *"prod has not deployed since 2026-07-29 — web-1's baked
Doppler token was revoked (11:19:30Z), so the zot gate goes dark and the pull falls through to an
unauthenticated GHCR fetch"*: a STALE credential serving STALE CODE, with the site UP throughout.
No host was bricked and none needed re-provisioning. The threshold still stands — this PR adds a
production write to the sole no-SSH channel for a host that genuinely cannot be re-provisioned
(cx33, 0/6 stock), which is sufficient on its own — but it must not rest on a precedent that does
not exist, because the inflation is precisely what carried the sign-off.

**What the operator is being asked.** Confirm the threshold and provide the sign-off, or downgrade
the threshold to `aggregate pattern` with a reason. `user-impact-reviewer` is invoked at review
time either way.

**DISPOSITION (operator, 2026-08-12): threshold CONFIRMED at `single-user incident`; sign-off
GRANTED.** `requires_cpo_signoff` is discharged — no outstanding sign-off remains.
`user-impact-reviewer` still runs at review time, as specified.

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

---

## PR-B attachment note (2026-08-13)

This is PR-B's copy of the record, placed on the PR-B branch so `ship` resolves it from
`specs/<branch>/`. **All three items above are DISCHARGED** — render them as *resolved* in the PR
body and file **no** `action-required` issue. Per UC2, **this** PR carries `Closes #7104`.
