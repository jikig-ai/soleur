# Decision challenges: feat-one-shot-9927-drift-delete-recipes

Headless plan run (2026-10-15). Every row below is a technical fork ruled by the CTO agent per
`hr-technical-fork-is-not-an-operator-question`; none drops or changes the operator's stated scope, so there is no
operator-facing User-Challenge. Rows are recorded so `ship` can render them into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Remedy prose in both orphan-issue bodies (rung-2 and inngest) once the DELETE call is gone | technical-fork | Ruled by CTO agent, 2026-10-15: point at the `teardown_only` dispatch, label the surviving bash fence READ-ONLY (add a `# READ-ONLY:` comment inside it), state that reclaiming a survivor is an owner-authorised action (the owner tells an agent session to reclaim the listed ids) and not a command pasted from an issue body, and invent no new workflow or console step - rationale: every clause stays true with the DELETE gone and names no path that does not exist. The inngest filer makes no claim about what its teardown arm verifies because that was not confirmed. |
| Keep the `TOKEN="$(doppler secrets get HCLOUD_TOKEN ...)"` line in the fence | technical-fork | Ruled by CTO agent, 2026-10-15: keep it unchanged - rationale: the read-only list loop needs a token; swapping to `HCLOUD_TOKEN_READONLY` with no fallback is a separate hardening (carried by the no-fallback loader in #9927), not item 8c. Optional follow-up only after confirming the secret is minted in `prd_terraform`. |
| `doppler configs delete` / `doppler environments delete` one-liners at the end of the two bodies | technical-fork | Ruled by CTO agent, 2026-10-15: reword to non-runnable prose in this PR and include them in the regression assertion - rationale: same pasted-destroy class on the same lines, and the rung-2 scratch config holds a live GIT_DATA_LUKS_KEY, so removing the Hetzner recipe while leaving a runnable delete beside it is incoherent. The new prose must not spell the command, or the assertion fires on its own text. |
| ADR-282 residual bullet naming "the drift workflow's runnable DELETE recipes" | technical-fork | Ruled by CTO agent, 2026-10-15: edit in this PR as a minimal erratum (status stays accepted): the parenthetical becomes "the drift workflow's issue bodies printed runnable DELETE recipes until #9927 item 8c removed them" - rationale: the clause turns false on merge and the ADR is the cited source; a factual correction is not a decision change. |
| Runbook `inngest-provision-rehearsal.md` "or reclaim by API - the filed issue prints the exact calls." | technical-fork | Ruled by CTO agent, 2026-10-15: reword in this PR to say the filed issue lists stranded objects read-only with ids and that reclaiming them is an owner-authorised action; `git-data-rung2-rehearsal.md` line ~406 stays untouched because it is still true - rationale: the old text points at calls that no longer exist. |
| Home and shape of the regression assertion | technical-fork | Ruled by CTO agent, 2026-10-15: extend `plugins/soleur/test/token-drift-workflow-causes.test.sh` (no new file; not `terraform-drift-step-order.test.sh`, which is about ordering) with an all-steps YAML helper (the two filers share the step name, so `step_get name:` cannot reach both), a step-scoped Hetzner write-verb check, a whole-workflow Doppler destroy check, a positive anti-vacuity row (exactly two filers, each keeping the read-only label_selector loop) and a sandbox mutation row (control GREEN, injected `-X DELETE` RED, injected `doppler configs delete` RED); bump the anti-vacuity floor to the realized count (~65) in the guard, its FATAL message and its comment together - rationale: that suite already owns the filer assertions and follows the no-raw-grep rule. |

## Not Yet Specified candidates

None.
