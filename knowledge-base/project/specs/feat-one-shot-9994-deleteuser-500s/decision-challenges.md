# Decision Challenges — feat-one-shot-9994-deleteuser-500s

Decisions surfaced during `soleur:plan` for #9994 (headless pipeline — no Agent tool
available in this harness, so technical rulings are recorded as `pending - assumed`
per `technical-ruling-delegation.md`).

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix shape: widen `tearDownTenantUser` sentinel + adopt in 5 defective suites (A) vs per-suite manual FK-reverse teardown (B) | technical | pending - assumed: A — the parity-guarded helper exists precisely for this and is already the canonical path; B is the proven drift source (helper docblock cites #5582, #4791; #9994 is the third recurrence). |
| Fold in `workspace_id` insert repairs (conversations + messages) in cc-dispatcher + conversations-rail — adjacent defect, same red leg, different root cause | technical | pending - assumed: fold in — the `supabase-dev` leg is the issue's named verification surface; it cannot go green while the 23502 failures stand. Fix is mechanical (`workspace_id: user.id`). |
| Fold in `dsar-export-cross-tenant` (best-effort swallow → strict helper path) | technical | pending - assumed: fold in — identical defect, same leg; the swallow only hides it and leaks users. |
| `brand_survival_threshold: single-user incident` + `requires_cpo_signoff: true` for a test-only diff | technical | pending - assumed: keep — the helper is a direct mirror of the Art-17 erasure cascade; a defective change could mask a real erasure regression. Same surface and threshold as the #5372 plan. CPO consult could not be spawned (no Agent tool); review-time `user-impact-reviewer` covers the seat. |
| Sentinel scope: `test/*.integration.test.ts` + `test/helpers/` only, `test/server/**` deferred to #10096 | technical | pending - assumed: scoped — including `test/server/**` now would enshrine a ~20-file allowlist and turn the guard into documentation of the defect rather than a bar against it. |
| Sentinel allowlist vs migrate the 4 working manual-FK-reverse suites to the helper | technical | pending - assumed: allowlist — their manual teardown is deliberate, documented (archive-release-slot's comment), and working; forcing migration inflates the diff for uniformity only. |

## Not Yet Specified candidates

(none — the plan's unknowns are implementation details, not product fog)
