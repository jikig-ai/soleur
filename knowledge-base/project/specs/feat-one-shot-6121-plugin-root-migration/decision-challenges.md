# Decision Challenges — feat-one-shot-6121-plugin-root-migration

Headless-mode record (ADR-084). `ship` renders these into the PR body and files an `action-required` issue for operator review.

## Challenge 1 — Scope: migrate residual untrusted-exec families now, or defer?

**Operator's stated direction (default):** migrate the 14 `${CLAUDE_PLUGIN_ROOT}` families enumerated in #6121 §2; close #6121 when they + the coupling test are green.

**Deepen-plan reviewers (security-sentinel + spec-flow-analyzer) pushed to expand:** they grep-proved that additional agent-run families carry the *identical* untrusted-code-execution hole this `type/security` slice exists to close — notably `legal-generate:60` (runs the secret-**redaction gate** `redact-sentinel.sh` from a git-root anchor; executing the connected repo's untrusted copy defeats the very control that stops token leakage), `trigger-cron:40,43,47` (fires a prod-cron POST), `incident`, `skill-security-scan`, `skill-creator`, `plan`, `compound-capture`, and others. At `brand-survival threshold: single-user incident`, closing the ticket while ~15 identical-surface sites stay open closes the *issue* but not the *vulnerability class*.

**Plan decision (this session):**
- **Folded in** only the one indefensible case: `product-roadmap:29,39` — it invokes the *same* `roadmap-reconcile.sh` that migrated `brainstorm:119` calls, so leaving it is a cross-caller half-migration (zero marginal cost).
- **Fixed the false-passing completeness gate** (AC1 → broad grep) so a missed in-scope site can't ship green.
- **Deferred the genuinely-distinct families** to a P1 `type/security` follow-up issue with an **exhaustive, honestly-framed "surface remains OPEN"** statement + inline agent-vs-operator triage — rather than either unbounding this PR or silently under-documenting.

**For the operator to confirm/redirect:** is the P1 follow-up deferral acceptable, or should `legal-generate` (redaction gate) + `trigger-cron` (prod-cron) be pulled into THIS PR given the security stakes? The redaction-gate case in particular is a defensible "fold in now" if you prefer maximal closure over minimal scope.
