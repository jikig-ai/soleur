---
title: Snapshot/Mutation Infra Requires Secret-Scanning Floor In Main First
date: 2026-05-04
category: security-issues
module: testing-infrastructure
related:
  - issue: 3121
  - issue: 3130
  - brainstorm: knowledge-base/project/brainstorms/2026-05-04-behavior-harness-uplift-brainstorm.md
  - prior: knowledge-base/project/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md
tags:
  - public-repo
  - secret-leak
  - irreversible
  - snapshot-tests
  - mutation-testing
  - brainstorm-slicing
  - user-brand-critical
---

# Snapshot/Mutation Infra Requires Secret-Scanning Floor In Main First

## Problem

The Theme A harness audit (PR #3119) bundled four sub-scopes into issue #3121: A1 mutation testing pilot, A2 golden/snapshot fixtures, A3 ATDD trigger hardening, A4 architectural fitness functions. CTO and CPO both made strong cases for shipping different sub-scopes first (CTO: A4-lite for lowest blast radius; CPO: A3-only for highest user-protective leverage). Neither initially foregrounded the irreversible failure mode the operator's user-impact framing surfaced: **on a public repository (`github.com/jikig-ai/soleur`, Apache-2.0), a single snapshot file or mutation report committed to `main` history that contains real credential material is structurally unrecoverable** — `git filter-repo` is the only remediation and it breaks every fork and clone.

CLO's assessment exposed the gap: the repo today has zero secret-scanning infrastructure (CodeQL is SAST for code paths, not fixture content). Snapshot frameworks (Jest `__snapshots__/`, vitest equivalents, Stryker mutation reports under `reports/mutation/`) serialize whatever the test produced, including response headers (`authorization: Bearer …`), error payloads echoing JWTs, BYOK fragments in config dumps, Supabase service-role keys leaked through error stacks. Once committed to `main`, the keys live in `git log` permanently.

This generalizes beyond the immediate brainstorm: any future work that introduces a new file class capable of capturing runtime data (snapshots, mutation reports, request fixtures, replay logs, trajectory dumps for Theme D) inherits the same constraint.

## Solution

**Land the safety floor before the convention.** Two distinct failures the floor prevents that the convention itself does not:

1. **Snapshot framework default behavior:** any test that captures real data to `__snapshots__/` files is a one-way commit. Without scanning at commit-time and merge-time, the floor cannot be retrofitted post-leak.
2. **Mutation testing fan-out:** Stryker re-runs the test suite N times with mutated source. If any test loads `.env`, calls Doppler with a real token, or fetches against a real Supabase project, that credential and any returned data fans out into Stryker's HTML report (often committed or uploaded as artifact), per-mutant test stdout, snapshot diffs when goldens are involved, and the mutation log itself. **One unsafe test × N mutants = N exfiltration events.**

**Specific structural mitigations identified by domain agents (#3121 and follow-ups capture the implementation):**

- **`gitleaks` integrated into `pre-commit` AND `pull_request`** — both gates required; lefthook prevents local commit, CI prevents merge. Snapshot-scoped rule pack (`__goldens__/**`, `**/*.snap`, `tests/fixtures/**`, `reports/mutation/**`).
- **Synthesized-fixtures-only AGENTS.md rule** (`cq-test-fixtures-synthesized-only`) tagged `[hook-enforced: secret-scan.yml + lefthook gitleaks + lefthook fixture-content-lint]`.
- **`.gitignore` for mutation report dirs** (`reports/mutation/`, `.stryker-tmp/`, `mutants/`) before A1 ever runs.
- **For A1 specifically:** `env -i` runner sandbox (clears environment, explicit allowlist `PATH`, `HOME`, `NODE_ENV=test`) so Doppler/secret env never enters the Stryker process. Static gate in lefthook: `rg -l 'process\.env\.(SUPABASE|STRIPE|BYOK|DOPPLER|ANTHROPIC|OPENAI)' <test-glob>` MUST return zero before mutation step runs.
- **Convention-level defenses against approval-fatigue bypass:** `__goldens__/` directory (NOT `__snapshots__/`) breaks `-u` muscle memory; regen requires `GOLDEN_REGEN=1` env var (not a CLI flag, defeats scripted bypass); commits touching `__goldens__/` require a `Golden-Updated-By:` trailer with non-empty reason.

## Key Insight

There are two distinct insights here that compound:

**(1) Structural ordering invariant for public repos.** When introducing test infrastructure that captures and serializes runtime data (snapshots, mutation reports, fixtures, replay logs), the secret-scanning floor MUST land in `main` before any file the framework would write. Once a single such file exists in history, the floor is no longer load-bearing — the breach is already irreversible. This is symmetric with the broader pattern that public-repo secret leaks are one-way doors (`2026-02-10-api-key-leaked-in-git-history-cleanup.md` covered the cleanup side).

**(2) Brainstorm slicing under `USER_BRAND_CRITICAL=true` should foreground the irreversible failure mode, even when domain leaders recommend higher-velocity slices.** CTO's "lowest risk, three config files" and CPO's "highest user-protective leverage" framings were both technically correct but optimized on velocity/leverage axes. The CLO-flagged secret-leak vector was on the *irreversibility* axis — different category. The correct sequencing question under user-brand-critical is not "what gives the most value first?" but "what failure mode, once experienced, cannot be undone?" That mode goes first regardless of velocity cost. The user-impact framing question (`hr-weigh-every-decision-against-target-user-impact`) is the existing enforcement layer for this; this learning records that **the answer to the framing question should drive slice ordering, not just plan content.**

## Session Errors

- **Silent telemetry source.** First `emit_incident` invocation used `source .claude/hooks/lib/incidents.sh 2>/dev/null && ...` — output suppressed any source failure. Verified post-hoc via `.claude/.rule-incidents.jsonl` that the emission did succeed, but the silent-stderr pattern violates `hr-when-a-command-exits-non-zero-or-prints` in spirit. **Recovery:** confirmed via log file. **Prevention:** drop `2>/dev/null` on hook-library sources; let stderr surface so a missing/broken hook script fails loudly.
- **Spec-template lookup detour (~30s).** Searched `plugins/soleur/skills/spec-templates/` for separate template files; only `SKILL.md` exists with the template inline. **Prevention:** spec-templates SKILL.md is fully self-contained — read SKILL.md first; don't search for sibling files.
- **`hr-new-skills-agents-or-user-facing` telemetry skipped.** Brainstorm SKILL.md Phase 0.5 instructs unconditional `emit_incident hr-new-skills-agents-or-user-facing applied` during domain processing, but the rule itself is conditional ("when adding new skills/agents/user-facing capabilities"). This brainstorm is internal CI infra — rule does not apply. Made a judgment call to skip; the skill's instruction wording creates ambiguity. **Prevention:** brainstorm SKILL.md Phase 0.5 should clarify either (a) emit unconditionally because the *gate was reached*, regardless of whether the rule applies, or (b) emit only when the rule applies. Pick one and document it. Filed as candidate skill edit during route-to-definition below.

## Cross-References

- Issue #3121 — repurposed as the umbrella + first-PR (A2 + safety floor)
- Issue #3130 — A1 mutation pilot, blocked by #3121 + #3120
- Issue #3120 — Theme D harness eval suite (independent track)
- Source brainstorm — `knowledge-base/project/brainstorms/2026-05-04-harness-engineering-review-brainstorm.md`
- Slice brainstorm — `knowledge-base/project/brainstorms/2026-05-04-behavior-harness-uplift-brainstorm.md`
- Spec — `knowledge-base/project/specs/feat-behavior-harness-uplift/spec.md`
- Prior leak-cleanup learning — `knowledge-base/project/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md`
