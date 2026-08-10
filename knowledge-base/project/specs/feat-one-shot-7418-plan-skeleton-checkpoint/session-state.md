# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-10-chore-plan-skeleton-checkpoint-before-research-fanout-plan.md`
- Status: complete (v2, after a 6-agent review panel returned 8 P0s against v1)

### Errors
- **v1 of the plan shipped a real, reproducible bug.** It proposed carrying state in `status:` read
  via the repo's line-anchored awk form. Three reviewers independently ran that reader against the
  plan file and got `planning` — sourced from a fenced YAML *example*, while the frontmatter had no
  such key. v2 mandates frontmatter-bounded parsing and ships the collision fixture as a regression test.
- **v1 asserted a precedent that was false by ~34x** ("`status:` already used across ~10 plans").
  Measured: 338 of 1531 plans, 44+ values, with `planning` and `complete` already taken. v2 abandons
  `status:` for a dedicated `pipeline_resume:` key.
- **First plan Write was blocked** by `.claude/hooks/iac-plan-write-guard.sh` because a Sharp Edge
  quoted the guard's own trigger tokens verbatim. Fixed by neutralizing the prose — *not* by taking
  the `iac-routing-ack` opt-out, which would have falsely asserted a real infra step was reviewed.
- **ADR-173 (v1's pick) is triple-claimed** on pushed branches. Re-derived to ADR-175 (verified free).
- Two self-inflicted tooling errors during planning: a budget one-liner over-matched (real figure is
  2400/2400, zero headroom), and `bunx vitest` was run against `plugins/soleur` tests, which use `bun test`.

### Decisions
- **Dedicated `pipeline_resume:` key, deleted at finalization** — presence is the boolean. Closes the
  338-plan `status:` collision, and makes merged/archived plans inert by construction, dissolving the
  `archive-kb`/`worktree-manager` hazards without editing them.
- **Completeness is conjunctive on both paths, and the table is total.** "Cursor absent ⇒ complete" is
  a negative assertion; absence has other causes. v1 hardened only the recovery branch, leaving the
  stub-to-`/work` path open on the success path.
- **Phase 1.7 now writes `## Research Insights`.** Without it the checkpoint bought a filename and
  nothing else for a stall *inside* the fan-out — the modal case.
- **Resume is bounded** (attempts cap, strict advance, terminal states); a designed `deepen-plan` HALT
  deletes the cursor, so a correct refusal does not replay as a crash.
- **Folded into this PR (superseding the earlier deferral):** the stale 1800→2400 budget figure (5 sites). Recorded in
  `decision-challenges.md`. The plan does **not** implement the literal `<!-- planning in progress -->`
  marker the issue specified — the operator's stated direction remains the default if they want it as written.

### Components Invoked
`soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`; agents: `repo-research-analyst`,
`learnings-researcher`, `functional-discovery`, `cto` (×2 — framing + devex), scoped advisor consult
(`model: fable`), `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`,
`architecture-strategist`, `spec-flow-analyzer`.

### Scope Verification
`git diff origin/main...HEAD --name-only` → only `knowledge-base/project/plans/` and
`knowledge-base/project/specs/` touched. No product-code breach.
