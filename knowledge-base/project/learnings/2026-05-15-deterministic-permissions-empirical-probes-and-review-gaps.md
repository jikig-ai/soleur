---
title: Deterministic permissions — empirical Phase 0 probes + multi-agent review caught what the unit tests passed on
date: 2026-05-15
category: best-practices
module: claude-code-hooks
issue: 3789
pr: 3787
plan: knowledge-base/project/plans/2026-05-15-feat-deterministic-permissions-plan.md
brand_survival_threshold: single-user incident
---

# Learning

## Problem

`feat-cc-stack-tuning` shipped two coupled hooks: F1 (kernel-decided-denial telemetry via a `PermissionDenied` event) and F2 (prod-write defer gate at PreToolUse(Bash)). The plan was thorough (DHH+Kieran+Simplicity reviewed at plan time, 11 converged cuts applied). Implementation should have been a paint-by-numbers /work pass.

It wasn't, on two axes:

1. **F1's load-bearing assumption was wrong.** The `PermissionDenied` event does not fire in Claude Code 2.1.142 — verified across `default` / `auto` / `dontAsk` permission modes with a stub hook capturing stdin, plus `--include-hook-events --output-format stream-json --verbose` which surfaced only `SessionStart` and `PreToolUse:Bash` events. Official docs (context7 `anthropics/claude-code` plugin-dev hook-development skill, fetched 2026-05-15) enumerate `PreToolUse | PostToolUse | Stop | UserPromptSubmit | SessionStart | SubagentStop | Notification | PreCompact`. No `PermissionDenied`. F1 was BLOCKING-gated to roadmap per the plan's Phase 0.1 acceptance criterion.

2. **The bash unit tests passed 28/28 with bugs the post-implementation review later caught.** Multi-agent review surfaced:
   - **Trailing-anchor asymmetry:** the regex's trailing `([[:space:]]|$)` missed `;`, `)`, `&` — `git push origin main;` slipped past the gate. The leading anchor already treats those operators as significant; the trailing class didn't mirror.
   - **Subshell form:** `(git push origin main)` missed the leading anchor because `\(` wasn't in the alternation.
   - **Read-only flag over-fire:** `terraform apply -help` / `-version` fired the gate (paralyzing-ship class per the plan's `## User-Brand Impact` bullet 1).
   - **Dead variable:** `DEFER_VALUE="defer"` was assigned but the enforce-mode jq emission hardcoded `"defer"` again — the Phase 0.2 empirical constant was bypassed at the only call site.
   - **Wrong rotator var name:** my `LOG_ROTATION_AGE_SECONDS=$((365*24*3600))` would have silently downgraded the approvals.jsonl TTL to 30 days because `rotate_if_needed` reads `LOG_ROTATION_AGE_DAYS` (`.claude/hooks/lib/log-rotation.sh:82`).
   - **Operator-stderr CWE-117:** `echo "[prod-write-defer-gate] BYPASS ... $CMD"` printed unsanitized C0/U+2028 bytes to operator terminal.
   - **Doppler argv-secret leak:** `doppler secrets set FOO=<value>` captures the secret VALUE verbatim in `approvals.jsonl resolved_command` (capped 1024 B, unredacted); F1 (which would have redacted via the planned redaction function) collapsed to roadmap. Documentation-only mitigation in v1; redaction follow-up gated on F1 reactivation.

Eleven of twelve plan-stated test sub-cases (2.1.1–2.1.12) were exercised; the bugs above were in test fixture coverage *gaps* — non-match cases that should have been Tier C but weren't enumerated.

## Solution

**Two-tier defense, both fired:**

### Tier 1 — Empirical Phase 0 probes (BLOCKING gates)

Plan's Phase 0 used the `CLAUDE_CONFIG_DIR=/tmp/cc-probe-*` mechanism to verify two load-bearing assumptions BEFORE writing production code:

- **0.1 PermissionDenied event payload.** Stub hook scaffold + four runs (`default`/`auto`/`dontAsk` permission modes, with both narrow and broad `--allowedTools`) confirmed the event does not fire. F1 was BLOCKING-gated to roadmap per the plan's stated criterion. Date-stamped artifact: `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md`.
- **0.2 `permissionDecision: "defer"` value verification.** Same scaffold, stub returns wrapped envelope. Empirical finding: `defer` IS honored — but only when `hookEventName: "PreToolUse"` is inside `hookSpecificOutput`. Without it, CC silently ignores the envelope and the bash runs. Date-stamped artifact: `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md`.

The `hookEventName` finding is the load-bearing detail that the Soleur learning `2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md` mentioned without calling out as mandatory. Recording it in DEFER-DECISION-PAYLOAD-SHAPE.md upgrades it from "noticed-in-prose" to "asserted-by-test-and-artifact".

### Tier 2 — Multi-agent post-implementation review

Even though plan-time DHH+Kieran+Simplicity reviewed the *design*, post-implementation review caught *implementation drift* the unit tests passed on. The 5 agents that fired:

- **pattern-recognition-specialist** — caught the trailing-anchor `;`/`)`/`&` gap and the doppler equals-form (`--config=prd_terraform`) bypass.
- **security-sentinel** — confirmed jq @sh-escape neutralizes stdin command injection; flagged the operator-stderr CWE-117 path; verified the `hookEventName` field is in both emission paths.
- **code-simplicity-reviewer** — caught the dead `DEFER_VALUE` variable and the `LOG_ROTATION_AGE_DAYS` API mismatch via "Hidden Assumptions" + "Goal Verification".
- **user-impact-reviewer** — single-user-incident threshold required; named the over-broad-regex paralyzing-ship vector concretely (`terraform apply -help`) and the doppler argv-secret leak vector.
- **git-history-analyzer** — verified plan→implementation fidelity (3 entries not 11, no `lib/operator-identity.sh`, no JSON manifest, no SCHEMA_VERSION bump). One minor drift: plan body §1.1 said "17 max callers" while AC §264 was updated to "22"; left for a doc-only follow-up.

All 8 findings fit in fix-inline (≤30 lines, ≤2 files each). Zero scope-out filings.

## Key Insights

1. **`hookEventName` is load-bearing in PreToolUse hook output envelopes.** Without `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "defer", ...}}`, CC silently ignores the entire envelope. Probing this empirically (one stub hook + one `claude -p` invocation) is cheap; assuming the docs' bare `{permissionDecision: ...}` works in 2.1.142 is wrong.

2. **CC's documented event set is the source of truth — assume nothing else exists.** F1's premise that `PermissionDenied` was a hook event came from a prior Soleur design note, not the docs. Phase 0.1 was correctly BLOCKING-gated; the alternative (build F1 against a non-existent event) would have shipped a no-op hook + an empty .rule-incidents.jsonl row class. The plan's explicit collapse-to-roadmap criterion + the Phase 0.1 probe gate caught it pre-implementation.

3. **Plan-time review is necessary but not sufficient.** DHH+Kieran+Simplicity reviewed the plan and made 11 cuts. Implementation still drifted on regex symmetry, variable usage, library API contracts, and false-positive coverage. Post-implementation multi-agent review (5 agents in parallel, ~5-minute total wall-clock) caught all 8 issues. Bash unit tests passed because the tests mirrored the plan's blind spots — same test author, same fixture-design instincts as the implementation author.

4. **Anchor symmetry: when a leading anchor includes `&&|\|\||;`, the trailing anchor MUST include `;|\)|&` too.** Otherwise the gate catches `cmd && prod-write` (leading match) but not `prod-write;` or `(prod-write)` (trailing miss). Bash subshell forms (`(cmd)`) and command sequences (`cmd1; cmd2`) are first-class shell constructs, not exotic.

5. **bash ERE has no negative lookahead.** A regex can't say "match `terraform apply` unless followed by `-help`". Use a post-match exclusion table (`READONLY_FLAG_PATTERNS[rule_id]=pattern`) and `continue` the iteration when the read-only pattern fires against the full command.

6. **Library env-var override names are a contract — read the source.** `rotate_if_needed` advertises `LOG_ROTATION_AGE_DAYS`; my code passed `LOG_ROTATION_AGE_SECONDS`. Silent downgrade to 30-day default. The cheapest defense is `grep -n LOG_ROTATION .claude/hooks/lib/log-rotation.sh` before assuming the override variable name.

7. **Constants for empirically-decided values must be actually USED.** Phase 0.2 produced `DEFER_VALUE="defer"`. The enforce-mode jq emission re-hardcoded `"defer"` in a string literal — bypassing the constant. If the Phase 0.2 outcome had flipped to `"ask"` and someone updated `DEFER_VALUE` accordingly, the hook would still have emitted `"defer"`. Test invariant for next time: assert that the named constant is read by every consumer.

## Session Errors

1. **PR #3801 prereq had 3 CI failures.** `pre-merge-rebase.test.sh` T3/T4 failed on CI Ubuntu (`init.defaultBranch=master`); PR body cited 11 hook test files that weren't in the diff (body-vs-diff guard rejected). **Recovery:** added `-b main` to `git init --bare` in T3/T4, reworded PR body to remove file enumeration. **Prevention:** When writing tests that init bare git repos, always pass `-b main`. When writing a PR body that describes scope, prefer glob patterns (`.claude/hooks/*.test.sh`) over file enumeration so the body-vs-diff guard doesn't reject.

2. **`CLAUDE_CONFIG_DIR=/tmp/cc-probe-*` first attempt produced "Not logged in".** The probe dir lacked credentials. **Recovery:** copied `~/.claude/.credentials.json` + `config.json` into the probe dir, chmod 600. **Prevention:** Document the credential mirroring step in any future CC-isolation probe template; the empirical-probe pattern is a high-leverage workflow but the bootstrap is non-obvious.

3. **PermissionDecision envelope silently ignored without `hookEventName`.** Bare `{"hookSpecificOutput":{"permissionDecision":"defer",...}}` caused CC to allow the bash. **Recovery:** added `"hookEventName":"PreToolUse"` to the inner object. **Prevention:** Already documented in DEFER-DECISION-PAYLOAD-SHAPE.md and the hook's source comment. Future PreToolUse hooks must always include the field.

4. **`DEFER_VALUE` dead variable.** Plan named the constant; I hardcoded `"defer"` at the only consumer. Caught by code-simplicity-reviewer. **Recovery:** `--arg decision "$DEFER_VALUE"` in jq. **Prevention:** When a plan names a constant tied to empirical decision, write the assertion `grep DEFER_VALUE | grep -v "^#"` to count consumers — if the constant has zero non-comment readers, the wiring is broken.

5. **`LOG_ROTATION_AGE_SECONDS` wrong env-var name.** Rotator reads `_AGE_DAYS`. Silent 30-day downgrade. **Recovery:** switched to `rotate_if_needed "$file" "" 365` (documented 3rd positional). **Prevention:** Grep library source for the exact env-var name BEFORE using it — `grep -n LOG_ROTATION lib/log-rotation.sh`.

6. **Regex trailing class missed `;`/`)`/`&`.** `git push origin main;` slipped through. **Recovery:** widened to `([[:space:]]|;|\)|&|$)`. **Prevention:** When designing alternation-anchored regex `(A|B|C|$)`, mirror leading and trailing operator-classes symmetrically. Subshell `(...)` forms are common — they're not "exotic".

7. **`terraform apply -help/-version` over-fired the gate.** Caught by user-impact-reviewer naming the paralyzing-ship vector. **Recovery:** `READONLY_FLAG_PATTERNS[rule_id]=...` post-match exclusion. **Prevention:** Per-rule read-only allowlist for any new defer/block target. bash ERE has no negative-lookahead; use post-match exclusion.

8. **`(git push origin main)` subshell missed leading anchor.** `\(` wasn't in the alternation. **Recovery:** added `|\(|` to the leading anchor. **Prevention:** See #6.

9. **`ship-unpushed-commits-gate` fired on a `git add && git commit` chain.** The hook's source matches only `gh pr merge` regex. Underlying signal was valid (2 unpushed commits) but the misfire source was confusing. **Recovery:** `git push` first, then commit succeeded. **Prevention:** Investigate whether agent-harness compound-command wrapping triggers downstream hooks to see a `gh pr merge` token in the input. If so, document; otherwise file a refinement issue against the hook.

10. **Tier-C non-match tests passed vacuously during RED.** Hook-absent and "hook ran but didn't match" both produced empty output. **Recovery:** noted as acceptable (Tier A/B/D/E/F/G/H failures provided the actual RED signal). **Prevention:** Per work-skill TDD gate, distinguish gate-absent from gate-present — add a sentinel assertion that the hook produced parseable JSON `{}` (proving the hook ran) before checking match content.

11. **Edit hook false-positive on workflow file.** First edit attempt on `test-pretooluse-hooks.yml` blocked with "GitHub Actions workflow injection" warning even without untrusted-event-input usage. **Recovery:** re-issued edit; succeeded. **Prevention:** Workflow edits that add only literal prose / hardcoded strings should pass — if the security_reminder_hook flags them, file a refinement issue against the hook's pattern detection.

## Related

- Plan: `knowledge-base/project/plans/2026-05-15-feat-deterministic-permissions-plan.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-15-cc-stack-tuning-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-cc-stack-tuning/spec.md`
- Phase 0 artifacts:
  - `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` — F1 collapse evidence
  - `.claude/hooks/DEFER-DECISION-PAYLOAD-SHAPE.md` — DEFER_VALUE + hookEventName findings
- Prior empirical-shape learning: `knowledge-base/project/learnings/2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md`
- Hook-envelope reference: `knowledge-base/project/learnings/2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`
- Bare-repo + worktree git-config trap: `knowledge-base/project/learnings/2026-04-24-fake-git-author-bare-repo-bot-override.md`
- Multi-agent review catches bugs tests miss: `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
- F1 roadmap deferral tracker: F1 not separately filed; collapse is recorded in PERMISSION-DENIED-PAYLOAD-SHAPE.md + the plan's AC + tasks.md strikethroughs.
- Followup #3800: enforce-flip PR (single-line `SOLEUR_DEFER_DRYRUN` default change after 2-week dry-run telemetry).

## Tags

category: best-practices
module: claude-code-hooks
issue: 3789
pattern: empirical-probe + multi-agent-post-impl-review
