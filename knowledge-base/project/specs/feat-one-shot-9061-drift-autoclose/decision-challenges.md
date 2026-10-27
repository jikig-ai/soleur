---
branch: feat-one-shot-9061-drift-autoclose
date: 2026-10-27
---

# Decision Challenges — feat-one-shot-9061-drift-autoclose

The planning subagent had no Agent/Task tool, so it recorded `pending - assumed:`
defaults. The pipeline parent spawned `soleur:engineering:cto` (Rule interface)
on 2026-10-27 carrying all five rows; every ruling below is the CTO's verdict.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Close-gate mechanism for #9061 — fresh full-root plan vs comment-only (the issue offers both) | technical | Ruled by CTO agent, 2026-10-27: gate the auto-close step on a fresh in-workflow full-root `plan -detailed-exitcode` exit 0 (option a). The issue's own success sentence — "a close should mean a full-root plan now reads no changes" — is only literally true under (a); comment-only permanently deletes the self-healing close for a non-technical operator, re-creating the ADR-138 defect class. The invocation is byte-equivalent to the drift cron's (`scheduled-terraform-drift.yml:169-172`); every input already exists in the apply job. Dissent: the gate stays RED until #10678 lands and the inngest host-replace window executes — that is the gate working as designed; the PR body must say so. |
| `cloudflare_record.google_gws_recovery` reconciliation — add to config vs destroy | technical | Ruled by CTO agent, 2026-10-27: defer reconciliation to open PR #10678 (verified: it adds the record to `dns.tf` AND the merge-apply `-target=` — both halves in one vehicle); this PR must NOT carry the block (same-address conflict; config-without-apply-path would leave the record's creation unowned). If #10678 is abandoned, keep-vs-destroy is a production-mutating teardown outside this PR and outside the delegable set. Dissent: none on the engineering; residual risk is only #10678's timeline. |
| Disposition of #10835 / #10768 (duplicate drift issues) | technical | Ruled by CTO agent, 2026-10-27: leave both OPEN, post a residual-owner comment on each (inngest replace → host-replace window per #10966/epic #10390; gws record → #10678); PR body carries `Closes #9061` only. Close NEITHER as a duplicate — a hand close while drift stands re-creates the #8754 defect, and `Closes #10835/#10768` in the body would auto-close on merge, the exact defect this PR fixes. Dissent: a duplicate close would be defensible issue hygiene but is a one-line hand act, not this PR's deliverable. |
| Plan-failure handling in the new `drift_plan` step (exit ∉ {0,2}) | technical | Ruled by CTO agent, 2026-10-27: fail-closed per plan — record `exit_code`, emit `::error::`, do NOT fail the job (the bounded apply already ran and was verified; a failed diagnostic must not red a green apply). Fail-closed in both directions: a non-0 exit fails the close `if:`; a step that dies before writing the output leaves it empty, which `!= '0'`. `set +e` is load-bearing. Mirrors the cron's own semantics (`scheduled-terraform-drift.yml:189-195`). Dissent: exit 2 prints `::notice::` not `::error::` — correct (pending drift is information), and the step-summary `Plan:` line plus the autoclose script's per-issue notice covers it. |
| `requires_cpo_signoff: true` at the `single-user incident` threshold | technical | Ruled by CTO agent, 2026-10-27: defer the CPO sign-off to the post-plan-review/ship phase — implementation proceeds now; sign-off stays merge-blocking, deferred to a gate that can execute it, never waived. The change only tightens an existing authority (adds evidence, removes none; worst failure is fail-closed), and the defect is armed today — every verified apply retains false-close authority. Dissent: the deferral holds ONLY if the ship phase actually consumes `requires_cpo_signoff`; if no consult spawn exists downstream, the flag must merge-block by checklist — the caller must verify that consumption before relying on the deferral. |
