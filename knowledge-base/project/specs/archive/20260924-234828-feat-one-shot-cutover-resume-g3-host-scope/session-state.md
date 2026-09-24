# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-fix-cutover-resume-g3-current-host-scope-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Two plan edits refused by plan-write guard (literal Doppler write command in prose) — reworded.
- Follow-up filing blocked twice by filing gate (body file + Mandated-By line) — filed as #8767 on retry.

### Decisions
- Anchor on Hetzner server `created` timestamp (identity fields are identical across a replace); a row counts only if BOTH event time and Better Stack `dt` >= anchor (two-clock, AP-027/ADR-149).
- Fix inside the two shared liveness readers — covers op=resume G3, op=arm G3.7 H signal, LUKS G3 gate; flush-latch count left unscoped. DHH dissent recorded as DC-1.
- Hetzner read hardened per ADR-241 D4 (HCLOUD_TOKEN_READONLY → HCLOUD_TOKEN, masked, stdin, no body echo, fail-closed named warnings).
- Refusal names the cause via count breakdown; host <10 min old → "WAIT, do NOT replace".
- Plan-review cuts: post-count anchor re-read, two helpers, curl --retry/-f. ADR-225 §4 amendment + C4 github->hetzner edge.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; learnings-researcher, functional-discovery, dhh/kieran/simplicity/cto reviewers, security-sentinel, observability-coverage-reviewer, test-design-reviewer, architecture-strategist.

## Work Phase
- Status: complete
- RED c63789e8a2 (753/1, predecessor reads '2'); GREEN d99d26e8b3; coverage dc016b29b5 (871/0); docs 43efca634d.
- Mutation battery: 7/7 killed (either clock dropped, missing-ts default, floor 0 on anchor failure, token on argv, first-match server, unfloored LUKS).
- Live replay (read-only): anchor 1790276253 (2026-09-24T18:57:33Z); floor=0 `3677 3677 0 0 0`, floor=created `254 3677 3423 0 0`.
- Affected gate: stopped at 96/181 suites (0 real failures) under load 36/16 cores, ~30-50 min remaining incl. the infra runner. Operator chose to rely on CI (required `test` + infra-validation.yml) for the remainder. Directly-covering suites run locally: cutover-inngest-workflow 871/0, c4-code-syntax + c4-render 32/32, c4-count-parity, c4-model-freshness, lint-diagnosis-claims (1/1 baseline), lint-shell-trace-credential-refusal --changed OK, shellcheck (no new findings).
- Deviation from plan: one extra helper `_generation_scoped_count` (shared notice/warning emission for both readers) instead of duplicating it per reader.
