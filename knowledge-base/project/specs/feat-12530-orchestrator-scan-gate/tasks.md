# Tasks: orchestrator-side security scan gate

Derived from `knowledge-base/project/plans/2026-11-10-feat-orchestrator-security-scan-gate-plan.md`. The suite is the check for command order and for the receipt. Taste and user-challenge items from plan review stay out.

## Phase 1: Setup

- [ ] 1.1 Re-run the all-refs `git ls-tree` probe of `knowledge-base/engineering/architecture/decisions/` across `refs/remotes/origin` immediately before creating the ADR file. Record the free ordinal in the work notes. A check of `origin/main` alone does not answer it. The acceptance criteria do not assert that the remote is free.
- [ ] 1.2 Write `plugins/soleur/skills/review/test/review-scan-gate.test.sh` before the script, modeled on `plugins/soleur/skills/review/test/ensure-semgrep.test.sh`. Stub `semgrep` and `shellcheck` on `PATH`. No network. The suite fails while the script is absent.
  - [ ] 1.2.1 Cover every RED row in Guard 1, including any review seat spawned before the script, a shell-only list whose shellcheck binary is not executed, a forged `Ran 99 rules` body with no semgrep summary, and a fix-round whose skill passes `origin/main...HEAD` instead of the fix range.
  - [ ] 1.2.2 Cover the PASS rows: docs-only `skip`, stderr `Ran 1 rule on 2 files` with both targets scanned, and one `test/` source file whose copied `paths.scanned` entry maps back to the original target.
  - [ ] 1.2.3 Assert command order in `plugins/soleur/skills/review/SKILL.md` and the agent files. A review model that skips the script is still a suite failure.

## Phase 2: Core Implementation

- [ ] 2.1 Add `plugins/soleur/skills/review/scripts/review-scan-gate.sh`. Emit the status with `echo "` so `SENTINEL_RE` sees `SOLEUR_REVIEW_SCAN_GATE`.
  - [ ] 2.1.1 `files` is the classified source-and-shell target count. A lockfile or a deletion does not increment it.
  - [ ] 2.1.2 Continue the phase only on a parsed `ok` or `skip`. `--probe` prints `SOLEUR_REVIEW_SCAN_GATE probe`, exits 0, and is not a scan.
  - [ ] 2.1.3 `ok` on semgrep or mixed requires semgrep's own summary, singular `Ran N rule` or plural `Ran N rules`, with N greater than zero, and `paths.scanned` mapped back to the source targets the invocation was given.
  - [ ] 2.1.4 `ok` on shellcheck requires shellcheck to have run with every shell target on its argv. A missing binary or an unread target is `refuse`. `rules=0` is legal only after that execution.
  - [ ] 2.1.5 Hardcode the semgrep config list from the repo root. Do not add a runtime branch for `p/js` or `p/ts`. A missing config refuses via exit 7 and no summary. One `EIO_BACKEND=posix semgrep -j 1` retry, then `refuse`. Call `ensure-semgrep.sh` only on the semgrep path.
  - [ ] 2.1.6 Findings stay `<file>:<line> <rule-id>` and do not stop the phase. A temp file, if any, lives outside the worktree and is unlinked before every return.
- [ ] 2.2 In the same change as the first status echo, add `SOLEUR_REVIEW_SCAN_GATE` to `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts`. MIRRORED-NOT-PAGED comment names the agent PostToolUse hook. Do not add the marker to `WEDGE_RE`.
- [ ] 2.3 Replace text in `plugins/soleur/skills/review/SKILL.md`. Do not append. Post-edit size stays at or under 475921 bytes. Do not change `description:`.
  - [ ] 2.3.1 Retire the step-14 recipe and the paragraph that begins "The registry slugs are `p/javascript` / `p/typescript`" and tells the reviewer to trust semgrep's own summary and to run shellcheck.
  - [ ] 2.3.2 The skill runs the script before every seat, including the design-validity pass and `--fix-round`, and passes the path list for the range under review. The shellcheck seat named by `fix-round-seats.sh` has no agent file. The skill tells that seat to quote the receipt and not invoke shellcheck.
  - [ ] 2.3.3 Do not spend bytes on a sentence that a `review.workflow.js` run is not a review verdict. Do not wire `review.workflow.js`.
- [ ] 2.4 Change the canonical `plugins/soleur/agents/engineering/review/semgrep-sast.md` description and body so the seat reports the receipt and does not run semgrep. Update `security-sentinel.md` so a zero-finding SAST claim requires the `ok` receipt. Update the cursor and opencode description sentences only.
- [ ] 2.5 After the canonical description change, run `cd plugins/soleur && bun run scripts/sync-grok-agent-compat.ts`. Commit the generated `plugins/soleur/.claude-plugin/agents.manifest.json` and `.grok/agents/soleur-engineering-review-semgrep-sast.md`. Do not hand-edit them.
- [ ] 2.6 Create the ADR at the ordinal the fresh probe found free. Decision: the receipt is the only evidence the review SAST scan ran. `prepush-secret-scan.sh` stays a separate scan. `scripts/check-adr-ordinals.sh` exits 0, and this change cites that one file.

## Phase 3: Testing

- [ ] 3.1 `plugins/soleur/skills/review/test/review-scan-gate.test.sh` fails on every RED row and passes the docs-only skip row, the singular summary fixture, and the mapped `test/` fixture.
- [ ] 3.2 `apps/web-platform/test/git-lock-marker-telemetry.test.ts` passes.
- [ ] 3.3 `scripts/check-adr-ordinals.sh` exits 0. `scripts/lint-skill-body-budget.py` accepts the review skill. `python3 scripts/lint-guard-contract.py` accepts the plan.
- [ ] 3.4 Run `plugins/soleur/test/fixture-relative-assert.test.sh`, `plugins/soleur/test/fixture-dir-operand-assert.test.sh`, and `python3 scripts/lint-shell-capture-exit.py` on the new suite before its first commit.
- [ ] 3.5 Do not start `scripts/test-all.sh` while a foreign run holds the shared lock. The fast checks above are this change's local proof. CI's required test check is the full battery while that lock is contended.

Do not edit `ensure-semgrep.sh`, `prepush-secret-scan.sh`, `review.workflow.js`, `roadmap.md`, or `plugins/soleur/test/skill-body-budget.json`.
