# Brainstorm: Declarative Required-Artifact Completion Floors Per Pipeline Phase

**Date:** 2026-11-16  
**Status:** In Review  
**Issue:** [#12527](https://github.com/jikig-ai/soleur/issues/12527) (Parent Epic [#12533](https://github.com/jikig-ai/soleur/issues/12533))  
**Branch:** `feat-12527-pipeline-phase-required-artifacts`  
**Draft PR:** [#12808](https://github.com/jikig-ai/soleur/pull/12808)  
**Author:** Antigravity / CTO / CPO / CLO / Soleur Agents  

---

## What We're Building

A deterministic, declarative completion floor system for Soleur's orchestration pipeline.

Currently, pipeline advancement relies on prose continuation gates (`## Work Phase Complete`), subagent narrative summaries (`## Session Summary`), and a terminal `<promise>DONE</promise>` marker. When an agent hallucinates completion or skips generating an artifact (e.g. exiting planning without an on-disk plan file, ending implementation without a commit, or claiming a PR is merged without verifying via the GitHub API), the omission propagates downstream unnoticed.

We are building a 4-layer verification system:
1. **TypeScript Single Source of Truth (`plugins/soleur/lib/completion-floors.ts`):** A declarative registry mapping pipeline phases (`plan`, `work`, `review`, `qa`, `ship`, `postmerge`) to verifiable required artifact checks.
2. **Portable Verification Runner (`plugins/soleur/scripts/completion-floor.sh`):** A lightweight, deterministic shell CLI that evaluates artifact presence and structural validity across all 7 supported harnesses (Claude Code, Grok Build, Devin CLI, Codex, OpenCode, Antigravity, Cursor).
3. **Continuation Gate Integration:** Machine-enforced pre-advance gates in `one-shot/SKILL.md`, `work/SKILL.md`, and `ship/SKILL.md` replacing hand-rolled checks.
4. **Bounded Self-Healing Retry (1 attempt):** When an artifact is missing at a floor check, the orchestrator injects an actionable diagnostic prompt naming the missing deliverable, giving the phase one chance to produce it before halting fail-closed.

---

## Why This Approach

### Alternatives Considered

1. **Option A (Chosen): Script-Backed Floor Gate + TypeScript SSoT Contract**
   - *Architecture:* Central TypeScript definition (`completion-floors.ts`) + portable shell verifier (`completion-floor.sh`).
   - *Pros:* Fully multi-harness compatible (Grok Build, Cloud Devin, and Codex lack Claude Code hooks; a shell runner works everywhere). Deterministic, fast (<100ms), fail-closed. Follows established Soleur patterns (`technical-ruling-gate.sh`, `pipeline-tally.sh`, ADR-324).
   - *Cons:* Requires updating continuation gates in skill markdown files.

2. **Option B (Rejected): Pragmatic Hardcoded Checks in `one-shot` Prose**
   - *Pros:* Minimal 1-day implementation.
   - *Cons:* Keeps checks ad-hoc, brittle, and scattered. Fails to establish a declarative contract for custom skills or future phases.

3. **Option C (Rejected): YAML Frontmatter in `SKILL.md` (`required_output:`)**
   - *Pros:* Syntactic mirror of HephaestusNG.
   - *Cons:* Broken on harnesses that do not parse frontmatter or invoke skills via slash commands (e.g. Grok Build, Cloud Devin). Brittle on dynamic timestamped or slugified filenames.

### Institutional Precedents & Learnings
- **#6325 / #6320 ([workflow-patterns/2026-07-11](file:///data/git-repositories/jikig-ai/soleur/knowledge-base/project/learnings/workflow-patterns/2026-07-11-grok-go-routes-one-shot-but-inlines-pipeline.md)):** Agents inline and skip phases if completion is ambiguous. Mechanical floors are essential.
- **#3937 ([learnings/2026-05-17](file:///data/git-repositories/jikig-ai/soleur/knowledge-base/project/learnings/2026-05-17-planning-subagent-exceeded-scope-and-summary-vs-disk-drift.md)):** Subagent narrative summaries are statements of intent, not fact. Floors must inspect filesystem reality.
- **#3827 ([learnings/2026-05-15](file:///data/git-repositories/jikig-ai/soleur/knowledge-base/project/learnings/2026-05-15-subagent-crash-recovery-via-on-disk-artifacts.md)):** Verify structural anchors (`## Acceptance Criteria`), not fragile headings like `## Overview`.
- **ADR-324 ([ADR-324](file:///data/git-repositories/jikig-ai/soleur/knowledge-base/engineering/architecture/decisions/ADR-324-review-scan-evidence-is-the-orchestrator-read.md)):** The orchestrator must execute a deterministic script and read its stdout receipt (`SOLEUR_*`), rejecting agent self-attestation.
- **Fail-Closed Rule ([learnings/2026-11-08](file:///data/git-repositories/jikig-ai/soleur/knowledge-base/project/learnings/2026-11-08-converting-changed-path-readers-moved-the-failure-to-newline-names-and-to-the-prose-that-calls-the-helper.md)):** Any script failure (exit 2/127) must fail closed (`unknown fires the gate`).

---

## Key Decisions

| Decision | Chosen Direction | Rationale |
|---|---|---|
| **Architecture** | Script-Backed Floor Gate (`completion-floor.sh` + `completion-floors.ts`) | Works identically across all 7 harnesses; portable and deterministic. |
| **Failure Disposition** | Bounded Self-Healing (1 Retry), then Fail-Closed Halt | Prevents premature pipeline death on transient skips while avoiding infinite token burns. |
| **Receipt Handling** | Ephemeral Runtime Gate (Stdout Markers) | Emits standard `SOLEUR_FLOOR_GATE` lines; avoids cluttering spec directories with ephemeral state files. |
| **Artifact Invariants** | Check structural anchors and git truth | `plan`: plan file exists with `## Acceptance Criteria` + `tasks.md` + zero out-of-scope edits.<br>`work`: commit count >= 1 + clean working tree.<br>`review`: open `code-review` issues == 0 + attestation trailers.<br>`ship`: `gh pr view` reports `state == "MERGED"`. |
| **Polymorphic Scope** | Doc-only & skip-aware predicates | Floor checks recognize docs-only changes (no test diff needed) and explicit `no-test-scenarios` markers for QA. |

---

## User-Brand Impact

- **Artifact:** Pipeline phase verification & checkpoint orchestrators (`plugins/soleur/skills/one-shot`, `plugins/soleur/lib/workflow-fidelity.ts`, `plugins/soleur/scripts/completion-floor.sh`).
- **Vector:** Pipeline advancing past incomplete phases claiming done without output artifacts, leading to unverified or phantom deployments/merges.
- **Threshold:** `single-user incident` (auto-tagged user-brand-critical per #5175).

---

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering
**Summary:** CTO recommends script-backed pre-advance floor gate (`completion-floor.sh`) coupled with TypeScript SSoT (`completion-floors.ts`). Emphasizes ADR-176 invariant (assert from concrete system truth, never secondary metadata), clean-room AGPL-3.0 isolation, and multi-harness parity.

### Product
**Summary:** CPO validates requirement from an autonomy trust standpoint: unverified completion claims destroy user confidence in CaaS execution. Recommends bounded self-healing retry prompts over abrupt halts, clear human-readable error messages, and robust handling of dynamic filenames.

### Legal
**Summary:** CLO confirms no user-facing legal document changes required (pure local orchestration check). Formulates mandatory clean-room protocol: zero ingestion/copying of HephaestusNG (AGPL-3.0) source, schemas, or tests (17 U.S.C. § 102(b)); mandatory clean-room PR provenance trailer on merge.

---

## Capability Gaps

None. The existing toolchain (TypeScript compiler, bash, git, GitHub CLI) provides all necessary capabilities.

---

## Clean-Room Provenance

Any implementation PR deriving from this brainstorm must carry the clean-room attestation trailer:

```text
Provenance: Independent clean-room re-implementation of declarative artifact completion floors.
Zero source code, AST schemas, prompts, or tests read, inspected, or copied from hmuhlestein/HephaestusNG (AGPL-3.0).
No AGPL notice applies.
```

---

## Open Questions & Next Steps

1. **Sub-step Coverage:** In Phase 1, start with core pipeline phases (`plan`, `work`, `review`, `qa`, `ship`). Can sub-step skills (`deepen-plan`, `compound`) be added in a follow-up?
2. **Next Step:** Proceed to spec creation in `knowledge-base/project/specs/feat-12527-pipeline-phase-required-artifacts/spec.md` and subsequent planning via `soleur:plan`.
