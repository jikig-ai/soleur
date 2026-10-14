# Resume prompt — #6808 scheduled LUKS verify + alarm

Paste the block below into a fresh session. Every path and command in it was verified to
resolve on 2026-08-03 at HEAD `1a124584c` (`wg-end-of-work-emit-resume-prompt` — a remembered
path is not a measured one).

---

```
/soleur:go feat-one-shot-6808-luks-verify-schedule — PR #7196 · resume mid-implementation

cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6808-luks-verify-schedule

Resume the one-shot pipeline for #6808. Planning is COMPLETE; implementation is at Phase 1.1 of 5.

STATE
- Branch feat-one-shot-6808-luks-verify-schedule, draft PR #7196, HEAD 1a124584c, pushed, tree clean.
- Plan (1677 lines, deepen-gated):
  knowledge-base/project/plans/2026-08-03-feat-luks-verify-scheduled-with-alarm-plan.md
- Tasks:   knowledge-base/project/specs/feat-one-shot-6808-luks-verify-schedule/tasks.md
- Context: knowledge-base/project/specs/feat-one-shot-6808-luks-verify-schedule/session-state.md
- Read the plan's "Implementation Phases" section (line ~1214) and follow it. Phase order is
  load-bearing: the classification contract must exist before anything consumes it.

DONE (commit 1a124584c)
- Phase 1.0: added ".github/workflows/workspaces-luks-verify.yml" to infra-validation.yml paths:.
- Phase 1.0b: registered workspaces-luks-verify-workflow.test.sh as an explicit step.
- Verified: run-registered-suites.sh --list enumerates it (86 of 88); actionlint rc=0.

EXPECTED RED — do not misread as a regression
apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh is REGISTERED but NOT YET
WRITTEN, so `bash apps/web-platform/infra/run-registered-suites.sh` fails on the missing file.
That is Phase 1.1's starting state. Writing that suite is the next task, and per the plan it
MUST fail before the Phase 2 workflow change lands — a suite that passes pre-change tests nothing.

NEXT: Phase 1.1 — write the workflow suite
Mirror apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh (same-feature precedent).
Parse the workflow with PyYAML, never grep for structure. EXECUTE the extracted `id: reassert`
run: body under `bash -e` with ssh/curl/tar/doppler stubbed on PATH, driving every fixture row in
plan Phase 1.1 step 3 (12 rows: pass / drift / readiness x3 / unavailable x5 / two schedule-seed
rows). Then execute the alarm body with a stubbed `gh`. Assert the WRAPPER as YAML objects, not
just the shell. MIN_ASSERTIONS floor >= 40.

THEN: Phases 2-5 per the plan
2 workflow (schedule + reason-first classifier + emit_class at EVERY exit + seed refusal + alarm +
  ops-email + Sentry check-in), 3 Sentry monitor + expenses, 4 docs truth-maintenance, 5 verify.

NON-NEGOTIABLES (carried from the operator brief; do not let these erode)
1. Schedule and alarm land TOGETHER. A cron without a working alarm is strictly worse than today's
   dispatch-only state, because it also makes people believe the surface is monitored.
2. The alarm `if:` must be reachable on failing runs. Mirror scheduled-zot-restart-loop.yml: capture
   rc as DATA (out="$(...)"; rc=$?) into a step output, let the step succeed, gate on
   steps.<id>.outputs.*. GitHub ANDs an implicit success() into any `if:` with no status function.
3. Classification is reason-first, rc-second. An rc-first classifier fires a p0 type/security legal
   alarm for mapper_path_override_refused, which is a config fault.
4. The scheduled path is read-only. Prove empirically that an empty seed_workspace_count does not
   abort under `set -u` and that no WORKSPACES_COUNT= append reaches the ssh stub.
5. Do NOT edit published docs/legal/*. The Article 30 register + counsel audit edits are sanctioned.
6. Prove the failure branch can fire — a guard whose failure path was never exercised pins nothing.
   Prefer a committed fixture; if you mutate, assert the mutation landed (diff -q vs a pristine
   backup, never vs HEAD — the tree is legitimately dirty mid-work).
7. Route dynamic values through env: in run: steps, never ${{ }} interpolation — the alarm files
   issues containing probe output.

GATE COMMANDS (all verified to resolve at 1a124584c)
  bash apps/web-platform/infra/run-registered-suites.sh          # infra set, derived from infra-validation.yml
  bash apps/web-platform/infra/run-registered-suites.sh --list   # confirm a new suite is actually registered
  bash scripts/test-all.sh                                       # repo MINUS apps/web-platform/infra/ — both are required
  bash scripts/lint-workflows.sh                                 # actionlint; rc=0 with pre-existing findings (#7042)
  bash scripts/check-adr-ordinals.sh
Note: test-all.sh does NOT cover apps/web-platform/infra/. This diff touches it, so BOTH runners
are required. Read the runner preamble/epilogue for LOW_TMP_HEADROOM / SIBLING_RUN_DETECTED banners
before trusting or distrusting a result.

SHARP EDGE — ADR-033 is ambiguous
THREE ADR-033 files exist on main (pre-existing grandfathered ordinal collision):
  ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md   <- the plan's target
  ADR-033-per-tenant-scope-grants.md
  ADR-033-runtime-jwt-signing-substrate.md
Phase 4.1 amends the FIRST one (2026-06-02 scope note, anti-circularity addendum). No new ordinal.

OPEN OPERATOR STEERS (proceed with the plan's answers if unanswered)
- Cadence: plan chose daily `41 4 * * *`, justified on the readyz/inventory dimension having zero
  host-side coverage. Weekly still clears the 30-day decay window with 4x margin.
- The Sentry cron monitor adds ~$0.78/mo PAYG (one seat) -> knowledge-base/operations/expenses.md,
  required by wg-record-recurring-vendor-expense-before-ready before PR-ready.

WHY THIS EXISTS
workspaces-luks-verify is dispatch-only, and while #6808 keeps WORKSPACES_LUKS_HEARTBEAT_URL
unwired it is the ONLY automatic verification that web-1's /mnt/data is still on the LUKS mapper.
The published privacy/GDPR/DPD documents now assert that verification in the present tense (merged
2026-08-02), and the counsel attestation records a 30-day claim_decay_trigger: if no successful run
lands in any trailing 30-day window while that wording stands, it must be re-tensed or withdrawn.
Use `Ref #6808`, NOT `Closes` — this satisfies only the "schedule exists" half of that issue's
recorded closure condition; the heartbeat stays unwired.

Finish through /soleur:ship (merged PR), then /soleur:postmerge.
```
