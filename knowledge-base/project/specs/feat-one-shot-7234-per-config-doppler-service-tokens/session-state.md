# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-03-fix-per-config-doppler-read-tokens-token-drift-plan.md
- Status: complete

### Errors
- Scratch tmpfs filled to 100% mid-session (another session's 2.6 GB dir plus ~1.2 GB of abandoned mutation-test scratch). One bash call lost its output. Recovered by removing stale `/tmp/{wlvmut,mainchk,mut4,big10.json}` dirs (7-10 h old, not project data); 1.3 GB freed and work resumed.
- Three plan claims about real code were false and were caught pre-ship, not shipped:
  - v1 asserted `CONFIG_NAMES` passes through `sort -u`; `check-cloudflare-token-drift.sh:569` is plain `sort`. This voided v1's central "misassembly cannot forge the count" argument.
  - v1 put `[ack-destroy]` in the PR body, but this repo is `squash_merge_commit_message: COMMIT_MESSAGES`, so it must live in a branch commit body or the apply HALTs.
  - v2 said the `doppler_service_account` grep returns 6 lines (it returns 8) and that `doppler me` appears nowhere in the repo (it is a live runbook command).
- The plan's own consumer sweep undercounted twice, so FR9 instructs `/work` to re-run the grep and treat its output — not the plan's count — as the checklist.

### Decisions
- Shape (operator-fixed, not re-litigated): 13 per-config `doppler_service_token`s under one `for_each`, published as one JSON-map Actions secret. Measured evidence voided ADR-164's rejection of this exact alternative: one secret and one `-target=` leg, not 13, and the service-account membership it was traded against obtains nothing.
- Mis-binding control set, cost-ordered. A service token ignores `-c`, so a bad `config =` reads one config 13 times and prints `13/13`. Primary control is static and pre-merge (assert `config = each.key`); `sort -u` at `:569` is mandatory; runtime self-identification is conditional on a Phase-0 measurement — building the safety property on an unmeasured credential capability is precisely the mistake that produced this issue.
- ADR-166 supersedes ADR-164 Decision 1 only — a new ADR keeps the record that a shape was chosen on measurement, shipped, and failed. Decision 2's "the inventory gates NOTHING" bullet IS falsified by deriving `for_each` from the inventory, so that bullet is amended in place rather than carried forward behind a pointer.
- The ratchet holds on four layers, not one. The naive "the floor is a literal" argument fails because F3 pins `floor == inventory count`. `FLOOR_HEADROOM=3` admits a 14->13 round trip, leaving the destroy guard as the only above-13 layer.
- `Ref #7159` / `Ref #7175`, never `Closes` — both close on a live scheduled run. A green CI run is explicitly insufficient: the failed swap was green while reading zero configs.

### Components Invoked
`soleur:plan` -> `soleur:deepen-plan`; `soleur:gdpr-gate` (Phase 2.7, zero findings); domain leader `cto`; scoped strong-model advisor consult (Phase 4.5); 5-agent plan-review panel escalated by the `single-user incident` threshold (`architecture-strategist`, `spec-flow-analyzer`, `kieran-rails-reviewer`, `dhh-rails-reviewer`, `code-simplicity-reviewer`); `learnings-researcher`; two `Explore` sweeps (consumer sweep, detector/ladder map); two deepen-plan implementation-realism passes (verify-the-negative, plan<->tasks consistency). Deepen-plan halt gates 4.6/4.7/4.8/4.9/4.10 all pass; 4.5's resource-shape trigger fired and is answered in the plan.
