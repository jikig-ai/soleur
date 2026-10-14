# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-05-fix-bot-synthetic-check-names-drift-plan.md
- Status: complete

### Errors
- One non-blocking false positive: IaC-routing PreToolUse hook flagged "install"/"out-of-band" framing; resolved with `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out (only infra change routes through infra/github/*.tf). No other errors.

### Decisions
- Root cause is three-layer drift: action's hardcoded CHECK_NAMES (6) + scripts/required-checks.txt (8) stale vs 17-check live "CI Required" ruleset. Fix: complete required-checks.txt (SSOT), make action read it (kill hardcode), add file-vs-file parity test. Synthesizable set defined by integration_id == 15368.
- New discovery: `adr-ordinals` is live-required but absent from infra/github/ruleset-ci-required.tf and canonical JSON — latent bug where next terraform apply would silently remove it. Reconciled in same PR (no-op apply).
- Secret-safety (single-user-incident threshold): Tier 2 mandatory. Action reproduces both gitleaks + `lint fixture content` gates over its own diff with an enumerated safe-surface allowlist (naive "markdown under knowledge-base/" predicate would void the ceiling).
- Two P1 implementability bugs caught + fixed in plan: parser's `${line%%#*}` truncates `waiver discipline (issue:#NNN trailer)`; `adr-ordinals` breaks hardcoded "16" count in test-audit-ruleset-bypass.sh:634 + .tf prose (bump to 17).
- Scope trimmed: cut gitleaks-install extraction in favor of 3rd pinned install + pin-parity assertion. ADR-032 amended (not new ADR); no C4 impact.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Research agents: repo-research-analyst, learnings-researcher
- deepen-plan review agents: security-sentinel, architecture-strategist, code-simplicity-reviewer
- deepen-plan halt gates 4.6, 4.7, 4.8, 4.9, 4.55 — all passed
