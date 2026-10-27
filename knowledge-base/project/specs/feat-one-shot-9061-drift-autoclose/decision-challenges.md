---
branch: feat-one-shot-9061-drift-autoclose
date: 2026-10-27
---

# Decision Challenges — feat-one-shot-9061-drift-autoclose

No Agent/Task tool exists in this subagent context, so `soleur:engineering:cto`
rulings could not be spawned. Per the technical-ruling delegation contract each
technical row below carries `pending - assumed: <default>` and is surfaced for
the post-plan-review confirmation.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Close-gate mechanism for #9061 — fresh full-root plan vs comment-only (the issue offers both) | technical | pending - assumed: fresh full-root `plan -detailed-exitcode` gate (the issue's first option). Rationale: it preserves the self-healing close (a close literally means "a full-root plan now reads no changes"); the comment-only arm permanently deletes auto-close value. |
| `cloudflare_record.google_gws_recovery` reconciliation — add to config vs destroy | technical | pending - assumed: reconcile via already-open PR #10678 (it adds the record to `dns.tf` and the merge-apply `-target=` list); this PR does not duplicate the resource (same-address conflict). If #10678 is abandoned, keep-or-destroy is a separately authorized teardown outside this PR. |
| Disposition of #10835 / #10768 (duplicate drift issues) | technical | pending - assumed: both stay open; this PR comments on each naming the residual owners (inngest replace → host-replace window per #10966/epic #10390; gws record → #10678). PR body carries `Closes #9061` only. A premature hand close would re-create the #8754 defect. |
| Plan-failure handling in the new `drift_plan` step (exit ∉ {0,2}) | technical | pending - assumed: record `exit_code`, emit `::error::`, do NOT fail the job — the apply already ran and was verified; the close gate treats non-0 as not-clean (fail-closed). |
| `requires_cpo_signoff: true` at the `single-user incident` threshold — CPO consult could not be spawned (no Task tool) | technical | pending - assumed: sign-off deferred to the post-plan-review confirmation gate / ship phase; ADR-138 precedent makes the tier the safe default. |
