# Decision challenges — feat-one-shot-8500-admin-merge-ready-script

Plan review (the #8500 plan) raised these Taste and User-Challenge findings in headless mode. They were not auto-applied. The operator's stated direction stays the default until someone acts on them.

## 1. Ship the PreToolUse hook for `gh pr merge --admin` now (User-Challenge)

- **Operator's direction:** the hook is out of scope unless it is trivial.
- **Challenge (CTO, devex):** the #8458 merge came from an agent acting on operator authorization *outside* any skill's text. Edits to skill prose do not reach that path; a hook does. A thin clone of `.claude/hooks/ship-net-issue-flow-gate.sh` would:
  - match `gh pr merge` together with `--admin`;
  - deny when `--match-head-commit <40-hex>` is missing;
  - otherwise run `admin-merge-ready.sh <PR> <sha>` and deny on a non-zero exit.
  At minimum, add a one-line hard rule to `AGENTS.md`.
- **Why it was not applied:** the nearest template is 213 lines plus a 378-line suite, which is not trivial under the brief. An `AGENTS.md` rule costs always-loaded budget and adds scope.
- **Cost if we're wrong:** another agent-side `--admin` merge that skips the script, which is the incident class this issue exists to close.
- **Proposed action:** a follow-up issue (filed at ship), prioritized above other #8500 follow-ups.

## 2. Move the merge retry loop into the script as `--merge` (Taste)

- **Challenge (CTO):** the 7-line merge block in `settle-then-admin-merge.md` is still copy-paste prose. The block it replaced had three defects.
- **Why it was not applied:** it would put a mutating action inside a read-only readiness check. The prose block was fixed instead: it stops on any non-zero exit, retries only the race, and exits 1 if no attempt lands.

## 3. Per-harness wiring in `plugins/soleur/lib/harness.ts` `pollInstructions()` (Taste)

- **Challenge (CTO):** the Grok and Devin wake patterns do not match `SOLEUR_ADMIN_MERGE_READY`, so a `--wait` run will not wake those harnesses on the verdict. The proposed fix is to add the marker to their match lists, add one bullet per harness, and add a `harness.test.ts` assertion.
- **Why it was not applied:** it is outside the brief, and harness parity tests widen the diff. This should be a follow-up.

## 4. Drop the one-shot / drain-prs wiring and the #8537 rebase step (Taste, DHH)

- **Challenge:** neither skill issues `--admin`, and the #8537 hunks do not overlap this change.
- **Why it was not applied:** the operator explicitly asked for both. The edits were reduced to one clause each, and the rebase is one step.
