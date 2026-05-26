---
title: npm run -w <path> silently fails when root package.json omits workspaces declaration; plan-time precondition gate must live-execute prescribed CLI commands
date: 2026-05-13
category: best-practices
tags: [plan, work, review, npm, workspaces, doppler, ops, sharp-edges, precondition]
severity: medium
status: closed
related_prs: [3711, 3751]
related_issues: [3711]
synced_to: []
---

# npm workspaces flag fails without root workspaces declaration — plan precondition gate must live-execute

## Problem

The PR-C #3711 plan (`knowledge-base/project/plans/2026-05-13-feat-ops-hash-user-id-cli-pa8-retention-pin-plan.md`) prescribed an operator invocation at lines 340-341:

```bash
doppler run -p soleur -c dev -- npm run -w apps/web-platform hash-user-id $(uuidgen)
```

The plan was reviewed by ≥3 agents at plan time. /work faithfully implemented from the plan, propagating the `-w apps/web-platform` form into:

- `apps/web-platform/scripts/hash-user-id.ts` header docstring (3 locations)
- `apps/web-platform/scripts/hash-user-id.ts` `fail()` stderr messages (2 locations)
- `knowledge-base/engineering/ops/runbooks/recover-userid-from-pino-stdout.md` Flow 1 step 2

The 5-test vitest suite passed because the tests invoke the script via `spawnSync("bun", [SCRIPT_PATH, ...])` directly — they bypass the npm wrapper entirely.

Review (8 agents + test-design + semgrep + gdpr-gate) caught it only because I live-executed the documented form during the review's CLI-Verification Check phase. Result:

```bash
$ npm run -w apps/web-platform hash-user-id -- "11111111-..."
npm ERR! No workspaces found:
npm ERR!   --workspace=apps/web-platform
```

Root cause: the repo root `package.json` (verified post-discovery) declares no `workspaces:` field. `npm run -w <path>` requires the invoking directory's `package.json` to declare workspaces; without that declaration, npm refuses to resolve the path. The sibling script `verify-stripe-prices.ts` is invoked correctly elsewhere in the codebase via `cd apps/web-platform && doppler run ... bun run scripts/verify-stripe-prices.ts` — a pattern the plan did not consult.

## Solution

PR #3751 commit `062a507d` switched all sites to the working form:

```bash
cd apps/web-platform
doppler run -p soleur -c prd -- npm run --silent hash-user-id -- "$UUID"
```

Verified live: returns deterministic 64-hex against the `test-pepper` fixture.

Two structural fixes applied in the same commit:

1. **CLI script header** now states explicitly: *"The repo root's package.json does not declare `workspaces:`, so `npm run -w apps/web-platform ...` from the root FAILS with 'No workspaces found' — do not use that form."* The header also explains the load-bearing `--` separator between npm-script name and positional argv.

2. **Runbook step 2** documents the cd-first invocation and pins the explicit `--` separator.

The plan file (lines 340-341) was NOT retroactively edited — the plan documents the decision history at the moment of authoring, and the review's correction lives in the runbook + script header (the operationally consulted artifacts).

## Key Insight

This is the same defect class as `2026-05-12-hyphenated-python-modules-and-plan-precondition-verification.md`:

- Plan prescribes a shell/import incantation.
- Multi-agent plan review echoes the prescription as obviously-correct.
- /work faithfully propagates the prescription into the codebase.
- The defect surfaces only when the prescribed command is **live-executed** — not at typecheck, not in the unit suite (which bypasses the wrapper layer), not in any static review pass.

The Python-hyphen learning (#3645) and this npm-workspaces learning (#3711) share the same shape: **toolchain-config preconditions are invisible at plan time and at static review**. The cheapest gate is to run the command itself.

Generalize: any plan that prescribes a shell-form invocation (`<tool> <subcommand> <args>` with non-trivial flag composition) must include the command as a verifiable precondition. The plan's `## Preconditions` (or equivalent) section should carry the exact one-liner that proves the form works in the target repo state. Plan reviewers reading "verified `npm run -w apps/web-platform hash-user-id` outputs 64-hex" treat the claim as load-bearing only if the plan also names the verification commit/run; otherwise it's a wish.

## Prevention

Three layers, in increasing strength:

1. **Plan-time live-execution (already mandated by `hr-plan-precondition` per prior learning).** Any prescribed shell command in a plan must be live-executed by the plan author or by `deepen-plan`'s research phase, and the verification output (or "verified at <date>") pinned in the plan body. Reword the plan's Integration Verification section to require: *each bullet's shell command was run; output captured*.

2. **Review-time CLI-Verification Check (already in `plugins/soleur/skills/review/SKILL.md` §4.5).** This is the gate that caught #3711. Strengthen the rule with this concrete coupling: when reviewing a PR that adds a new script under `apps/<workspace>/scripts/` AND documents an `npm run -w <workspace>` invocation, **the reviewer MUST grep the repo-root `package.json` for `"workspaces"` and refuse the documented form if absent**. The grep is one line; the false-negative cost is a runbook that returns "No workspaces found" the first time an operator follows it under pressure.

3. **Lint at commit time (deferred — out of scope for #3711).** A pre-commit hook could grep newly-added docs/scripts for `npm run -w <path>` and assert `jq '.workspaces' package.json` resolves non-null. Defer; the cost-of-filing exceeds the recurrence rate at this codebase size.

## Cross-references

- `knowledge-base/project/learnings/2026-05-12-hyphenated-python-modules-and-plan-precondition-verification.md` — analogous defect class (Python hyphen import); same plan-prescribed-broken-command shape.
- `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md` — broader pattern of plan-quoted preconditions aging out by /work start.
- `plugins/soleur/skills/review/SKILL.md` §4.5 — the CLI-Verification Check gate that caught this.
- `plugins/soleur/skills/plan/SKILL.md` — the surface that should grow the workspace-declaration precondition prompt.
- PR #3751 commit `062a507d` — inline review fixes.
- `apps/web-platform/scripts/verify-stripe-prices.ts` — the canonical sibling pattern (cd-first invocation) the plan should have consulted.

## Session Errors

- **Plan documented broken `npm run -w` form propagated into 5+ documentation sites before review caught it.** Recovery: live-executed the documented command during review's CLI-Verification phase, surfaced "No workspaces found", switched all sites to `cd apps/web-platform && npm run --silent <script> -- <args>`. Prevention: plan-time precondition gate must live-execute any prescribed shell command in the plan body; review's CLI-Verification Check must grep root `package.json` for `workspaces` declaration whenever `-w <path>` appears in the diff.
