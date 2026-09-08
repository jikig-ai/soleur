# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-08-fix-shell-git-env-scrub-and-hook-fault-diagnosis-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

None. Two MD018 markdownlint failures (lines opening with `#7849` / `#7942` parsed as headings)
were caught by the pre-commit hook and fixed during planning. `knowledge-base/INDEX.md` appears in
the diff as the `generate-kb-index` lefthook regeneration, not a hand edit. Scope verification
passed: `git diff origin/main...HEAD --name-only` listed only `knowledge-base/` paths.

### Decisions

- #7275's root cause is DEEPER than the issue states. `PIPESTATUS` does not survive the command
  substitution it is read after, so `jq_rc` is always 0, the `internal` arm is dead code, and every
  zero-output failure is labelled `unparseable`. The file's comment that "jq's exit code already
  makes the only distinction that matters" describes a discriminator the code never reads.
- Prescribed design: strip the return code BEFORE the split. The obvious alternative makes the
  happy path seven fields and renders the zero-field arm structurally unreachable, so every payload
  fault would be misreported as `internal` — the exact inverse of the defect.
- #7822's suggested fix was already adjudicated: the merged #7833 plan explicitly CUT the shell
  scrub wrapper and the file-scale lint; the sweep is tracked by #7849 with a named exit condition.
  Measured, the sweep is five files, not twenty-five. The issue's proposed six-name `env -u` list
  would REDUCE coverage against the nine-name list already deployed.
- Two pre-existing silent-disarm holes found by measurement: a JSON `null` root parses as success
  with all fields empty, and a valid envelope followed by trailing garbage yields a correct field
  count with rc 5.

### Collision re-probe (post-plan, per #7247)

The Step 0a.5 gate covered only the issues passed in (#7822, #7275). The plan's frontmatter
`closes:` added #7835 and #7942, so items 1-3 were re-run against both:

- #7835 — OPEN, no closing PR. Hit on merged #7805 is a citation (#7805 closes #7772); empty
  scope intersection. Cleared as genuine work; same defect class as #7822.
- #7942 — OPEN, zero PRs on any probe. Clean, but see scope decision below.
- #7849 — OPEN, has OPEN PR #7879 (closes #7849/#7853/#7854) with a live sibling worktree.
  Measured three-file overlap with this plan: `apps/web-platform/infra/workspaces-luks-loopback.test.sh`,
  `plugins/soleur/test/test-helpers.sh`, `scripts/test-all.sh`.

### Scope decision (operator-authorized)

Operator chose "Drop #7942, keep #7835". Effective scope: **#7822 + #7835 + #7275**.

- `closes:` narrowed to `7822, 7275, 7835`.
- #7942 dropped entirely; its existing trigger stands and it is picked up after #7879 lands.
- `workspaces-luks-loopback.test.sh` dropped from the sweep — #7879 owns it.
- `plugins/soleur/test/test-helpers.sh` and `scripts/test-all.sh` MUST NOT be modified.
  Sweep suites may SOURCE test-helpers.sh; they may not edit it.

### Out of scope (unchanged)

- ADR-194 deferred cleanup: `ssl = "full"` and the orphaned `scheduled-gh-pages-cert-state`
  monitor. Deferred until the rollback window closes.
- #7801 / `scripts/ship-incident-pir-gate.sh`: code fix merged in PR #7806 (prose `Ref`, so the
  issue stayed open). Residual is behavioural only — observe the Phase 5.5 Incident-PIR verdict at
  this run's own ship phase and report it on the issue.

### Components Invoked

soleur:plan, soleur:deepen-plan, soleur:engineering:cto, repo-research-analyst,
learnings-researcher, Explore, and a six-agent review panel (architecture-strategist,
test-design-reviewer, security-sentinel, code-simplicity-reviewer, git-history-analyzer,
user-impact-reviewer). Mechanical gates: lint-guard-contract.py, lint-infra-no-human-steps.py,
lint-agents-rule-budget.py, plus live probes of hook-input.sh, rule-metrics-aggregate.sh, and
jq/bash exit-code semantics.
