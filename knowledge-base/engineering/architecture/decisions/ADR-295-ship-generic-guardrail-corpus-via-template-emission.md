---
title: Ship the generic guardrail corpus via template emission into user-repo hooks + CI
status: active
date: 2026-10-21
amends: none
supersedes: none
issue: 10404
related: [10397, 5765, 5770, 5777]
related_adrs: [ADR-071, ADR-074]
brand_survival_threshold: single-user incident
---

# ADR-295: Ship the generic guardrail corpus via template emission into user-repo hooks + CI

## Status

Active — 2026-10-21 (#10404, epic #10397 child 7).

## Context

Soleur applies ~55 non-test hooks and ~46 lint scripts to itself but shipped none of the generic fraction to plugin users. `constraint-scaffold` (ADR-071) proved a skill can generate a deterministic gate into a user repo's CI; this decision extends that pattern from one gate to a curated corpus.

## Decision

- **Dual-surface delivery.** `verification-scaffold` emits per-guard templates into `.claude/hooks/` + `.claude/settings.json` (agent surface) and repo-root `.github/workflows/verification-gates.yml` (CI floor, because subdir workflows are dormant).
- **Advisory-first mode contract.** `--mode advisory` is default; the mode flips only the decision verb (warn/ask/non-blocking vs deny/failing), never the detection predicate — promotion is a one-line flip after ≥1 observed clean run.
- **Templates, not vendored copies.** Every corpus member carries Soleur couplings; templates are self-contained single files (`SOLEUR_*`→`VERIFICATION_*` rename; `@DEFAULT_BRANCHES@` placeholder stamped per target). The sole near-verbatim emit is `precommit-guard.sh` + `wrapper-boundary.sh`, byte-pinned by `test/manifest.test.sh` against the rename-normalized canonical source.
- **guards.tsv is the machine manifest** the generator iterates; `references/guardrail-audit.md` is its human co-versioned twin — the manifest test drives the corpus census from `git ls-files` so a new unclassified member reds CI.
- **Bite-proof before docs.** A TMPDIR-detached-worktree pass→inject→fail→revert→pass runs per installed guard before the doc block and state file are written; the trap restores the tree on any failure after the first write.

## Consequences

v1 guards: `secret-scan`, `commit-on-main`, `block-stash`, `orphan-test`. Adding a guard is one guards.tsv row + template + audit row. `block-rm-rf` evaluated and held at v2 (the generic-value arm is coupled to lib machinery; the self-contained `.worktrees/` arm guards a Soleur layout convention). ADR-071/074 are precedent, not superseded.
