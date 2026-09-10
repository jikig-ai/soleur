# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-07-fix-fixture-env-ledger-ancestry-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Collision gate: re-probed after planning. Plan `closes: [7849, 7853, 7854]` — identical to the
  invoked set, so no plan-discovered target needed a second Step 0a.5 pass. PR #7840 was surfaced
  by the `linked:issue` and body probes for all three and dismissed on evidence: its
  `closingIssuesReferences` is `[7833]`, and these three were filed BY that session as
  `deferred-scope-out` follow-ups.

### Errors
Two recoverable, both resolved before the phase returned:
- First plan Write blocked by `iac-plan-write-guard.sh` (the Phase 2.8 skip section quoted the
  literal detection tokens). Rewritten, `iac-routing-ack` marker added.
- Two commits blocked by `markdown-lint` (code-span spacing, table/list blank lines, code-block
  style). All fixed. No aborts.

### Decisions
- **#7854 — Option 1, chosen on measurement, not preference.** The hook runs as a *child* of its
  suite, so the two `/proc` walks start one process apart; Option 2 as filed (match the traversal
  limit) leaves the origins different and cannot fix it. The suite now gates on the hook's own
  `outcome != "applied"` — it has eleven decline reasons, so gating on the single
  `claude_pid_not_found` string would fail the commit gate for the documented opt-out.
- **#7853 write-boundary — one containment mechanism, not the three the issue suggested.** The
  chokepoints that would have exported a test marker already export `INCIDENTS_REPO_ROOT` directly,
  so the `incidents.sh` tripwire (issue suggestion 3) was cut. This also keeps test-awareness out of
  production hook code. Three reviewers converged on it independently.
- **#7853 aggregator orphan gate — one predicate plus a retirement lookup replaces nine exemption
  stanzas, and ONE exact exemption survives.** (Corrected: the original wording said "one predicate",
  which measurement falsified — see measurements.md Correction. `cq-pencil-collapse-auto-recover` is
  tier-gated out of AGENTS.md, never retired, and live.) All 105 AGENTS
  ids carry a section prefix, so the gate asks "does this claim to be a corpus rule?" rather than
  maintaining a list. The registry + drift lint the first draft proposed were killed. The issue
  understated this arm 22x: 23 orphans, 22 with live emitters, not one.
- **#7849 — the named set only; the residual sweep stays deferred.** Phase 2 converts the issue
  body's enumerated "neither converted nor waived" set. The ~60 remaining shell + TS fixture sites
  are deferral #4 with this plan's full enumeration attached — the enumeration was the expensive
  part and is done. This preserves the issue's own argument that a ~50-file mechanical diff
  guarantees a rubber-stamp review.
- **Deepen-plan reversed one of the review panel's cuts on measurement (D-1).** The `git_fixture`
  wrapper's stated justification was false — a repo-local `commit.gpgsign=true` survives the config
  globals. The replacement (`GIT_CONFIG_COUNT`/`KEY_0`/`VALUE_0`) is better than both and closes a
  latent gap in the existing TS helper.
- **DC-1 resolved, not escalated.** The CTO/DHH proposal to split the aggregator arm into its own PR
  was reclassified under `hr-technical-fork-is-not-an-operator-question` — a revert-unit boundary is
  an engineering fork. Kept as one PR because the cut reduced that arm to a single jq predicate.
- **Review panel net effect:** five mechanisms cut (~530 LoC), two suites added for acceptance
  criteria and guard rows that had no producer.

### Components Invoked
`gh issue view` x3 (+ comments) - `soleur:plan` - `soleur:engineering:cto` - `Explore` x3 (incidents
sweep, fixture enumeration, verify-the-negative) - `soleur:engineering:research:learnings-researcher`
- `soleur:plan-review` -> `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer` - scoped strong-model consult (`fable`) -
`soleur:gdpr-gate` (sandboxed) - `soleur:deepen-plan` - `lint-guard-contract.py`,
`lint-infra-no-human-steps.py`, `markdownlint-cli`
