# Tasks: untrusted-content framing for GitHub-sourced agent input (#10194, slices A and B)

Plan: `knowledge-base/project/plans/2026-10-25-feat-untrusted-content-github-surfaces-plan.md`

## Phase 1 — `github` source and six read tools

- 1.1 RED: write `apps/web-platform/test/github-tools-untrusted.test.ts` (six tools; error and stringify-failure paths bare `isError`; write tools unchanged)
- 1.2 Add `github` to `UntrustedSource`, `UNTRUSTED_PREAMBLES`, `FLAG_THRESHOLDS` (unused-comment) in `server/untrusted-content.ts`
- 1.3 Give `wrapToolHandler` an optional `source`; pass `"github"` from the six read tools in `server/github-tools.ts`
- 1.4 GREEN: run the new test and the existing `test/github-read-tools.test.ts`

## Phase 2 — leader prompts

- 2.1 RED: write `test/server/inngest/leader-prompts/untrusted-envelope.test.ts` (registry loop; hostile body; empty fallback; `promptVersion` `v1.1.0`)
- 2.2 Add `assembleEnvelopedPromptText` to `leader-prompts/prompt-assembly.ts` (returns `""` for empty content)
- 2.3 Run `rg "assemblePromptText\("`; switch `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`; record the `knowledge.kb_drift` decision
- 2.4 Bump `promptVersion` to `v1.1.0` on the changed classes
- 2.5 GREEN: new test plus `prompt-version-stability.test.ts` and `prompt-assembly-pii-scrub.test.ts`

## Phase 3 — cron system-prompt preamble

- 3.1 RED: write `test/server/inngest/cron-untrusted-preamble.test.ts` (both branches; prompt byte-identical; `/soleur:` prompt stays last; single `spawn(claudeBin` site)
- 3.2 Add `--append-system-prompt` and `UNTRUSTED_PREAMBLES.github` after `--strict-mcp-config` at the spawn site in `_cron-claude-eval-substrate.ts`
- 3.3 Update only the spawn-argv assertions that legitimately change (e.g. `cron-claude-eval-mcp-flags.test.ts`)
- 3.4 GREEN: new test plus the cron substrate and single-flight suites

## Phase 4 — subagent signal

- 4.1 RED: extend `test/untrusted-content-wiring.test.ts` (`agent_id` present, absent, no id key in log)
- 4.2 Add `subagent` to the classify log in `server/untrusted-content.ts`
- 4.3 Comment on #10195: dev canary procedure for `subagent=true`; PA-8 (c) amendment and `sessionId` hashing before enablement

## Phase 5 — records

- 5.1 Amend ADR-287 (Decision-section carve-out for unconditional static framing; Known limitations)
- 5.2 Edit `model.c4` API container description only if falsified; if edited, run C4 tests and `plugins/soleur/test/c4-count-parity.test.sh`
- 5.3 Comment on #11076: add hosted Concierge `gh` CLI output
- 5.4 Run mutation rows from both Guard Contracts once; keep those that are test cases
- 5.5 Draft the PR body (unconditional framing, revert rollback, `Ref` not `Closes`, no public claim, uncovered paths)

## Verification

- Typecheck, full affected vitest suites, `python3 scripts/lint-guard-contract.py` on the plan
- Review: `soleur:engineering:review:user-impact-reviewer` (single-user-incident threshold)
