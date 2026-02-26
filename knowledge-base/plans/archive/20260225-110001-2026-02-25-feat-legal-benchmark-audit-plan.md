---
title: "feat: Legal benchmark audit mode"
type: feat
date: 2026-02-25
---

# feat: Legal Benchmark Audit Mode

Related: #303 | Branch: `feat-legal-benchmark-audit`
Brainstorm: `knowledge-base/brainstorms/2026-02-25-legal-benchmark-audit-brainstorm.md`
Spec: `knowledge-base/specs/feat-legal-benchmark-audit/spec.md`

## Overview

Extend the `legal-compliance-auditor` agent and `legal-audit` skill with a benchmark mode that validates legal documents against a GDPR Art 13/14 regulatory disclosure checklist and compares clause coverage against peer SaaS policies (best-effort). No new agents or skills — purely additive changes to existing files.

## Problem Statement

All 7 legal documents are AI-generated drafts checked only for internal consistency and cross-document agreement. The existing auditor catches contradictions between documents but cannot answer: "Are we missing something that the regulation requires?" or "What do similar companies include that we don't?" These are different questions that need different checking strategies.

## Proposed Solution

When the user invokes `legal-audit benchmark`, the skill appends a benchmark trigger phrase to the Task prompt sent to the `legal-compliance-auditor` agent. The agent gains two new checking sections in its body instructions:

1. **Regulatory checklist section** — GDPR Art 13/14 enumerated disclosure requirements checked against each document. High-value, zero external dependencies.
2. **Peer comparison section** — fetch peer SaaS policies via WebFetch and compare structural coverage. Best-effort (WebFetch is documented as unreliable for legal content). The feature delivers clear value even if peer comparison produces sparse results.

### Key Design Decision: Regulatory > Peer

SpecFlow analysis and 3 institutional learnings confirm that WebFetch is unreliable for legal documents (PDFs, consent banners, summarization). Regulatory benchmarking is the primary value. Peer comparison is additive and best-effort.

### Resolved Open Questions from Brainstorm

1. **Peer selection criteria** — Resolved: peers are fully curated in the agent URL table, not agent-selected at runtime.
2. **WebFetch limitations** — Resolved: WebFetch first, report `[SKIPPED]` on failure, never silently omit.
3. **Rate of change** — Resolved: on-demand only. User runs `legal-audit benchmark` when they want to. No scheduling.
4. **Professional review gate** — Resolved: the existing "do not provide legal advice" sharp edge covers this. All output already carries the DRAFT advisory from the documents themselves.

## Technical Considerations

### WebFetch Reliability

Per learnings `2026-02-24-bsl-license-migration-pattern.md`, `2026-02-21-github-dpa-free-plan-scope-limitation.md`: WebFetch summarizes through a model, fails on PDFs, and returns consent banners for EU sites. The agent instructions define fallback behavior:

- WebFetch returns usable content -> compare
- WebFetch returns garbage/404/PDF landing page -> report `[SKIPPED]` as an INFO finding and continue
- Never silently omit a peer — always report success or skip

### Agent Instruction Size

Per learning `agent-prompt-sharp-edges-only.md`: only embed what the model would get wrong. Sharp edges to add:

- GDPR Art 13/14 enumerated disclosure checklist (specific items to check)
- WebFetch failure modes and fallback behavior
- Peer URL table (3 fetchable URLs only)
- Finding source labels (`[REGULATORY]`, `[PEER:<name>]`)
- The "benchmark mode" trigger phrase

Claude already knows general compliance, CCPA, ICO, CNIL requirements from training — no explicit checklists needed for those.

### Finding Source Labels

Benchmark findings add a source prefix to distinguish from standard findings:
- `[HIGH] [REGULATORY] Section > Issue > Recommendation`
- `[MEDIUM] [PEER:Basecamp] Section > Issue > Recommendation`

### Skill-to-Agent Interface

The skill passes "benchmark mode" by appending to the Phase 2 Task prompt. If the user's input includes the word `benchmark`, the skill appends: "Additionally, run benchmark mode: check against the GDPR Art 13/14 regulatory disclosure checklist and compare against peer SaaS policies." Otherwise, the standard audit prompt is sent unchanged.

The sub-command is detected from the `args` parameter when the skill is invoked via the Skill tool (e.g., `skill: "legal-audit", args: "benchmark"`), or from the user's natural language input when invoked directly.

### Version Bump Justification

MINOR bump (3.2.1 -> 3.3.0) because the `benchmark` sub-command adds user-facing capability to an existing skill, functionally equivalent to a new skill entry point.

## Acceptance Criteria

- [ ] `legal-audit benchmark` triggers enhanced audit (appends benchmark trigger to Task prompt)
- [ ] `legal-audit` (no sub-command) works exactly as before (FR6)
- [ ] Agent checks documents against GDPR Art 13/14 enumerated disclosure requirements
- [ ] Agent attempts to fetch peer policies via WebFetch with defined fallback on failure
- [ ] Peer URLs are curated in the agent body (3 fetchable URLs, not runtime-discovered)
- [ ] Findings include `[REGULATORY]` and `[PEER:<name>]` source labels
- [ ] Unfetchable peers reported as `[SKIPPED]` INFO findings (never silently omitted)
- [ ] Benchmark mode is additive (standard compliance + regulatory + peer)
- [ ] Benchmark findings are conversation-only (same output restriction as standard findings — never persisted to files)
- [ ] Standard summary includes GDPR Art 13/14 disclosure count and peer comparison stats
- [ ] CLO delegation table updated to mention benchmark mode
- [ ] Skill `description:` frontmatter updated to include benchmark trigger phrases for discoverability
- [ ] Agent description unchanged (no budget impact — all changes in body)
- [ ] Version bump to 3.3.0 across plugin.json, CHANGELOG.md, README.md
- [ ] Root README.md badge + bug report template updated
- [ ] plugin.json description string verified (counts unchanged — no new agents/skills)

## Test Scenarios

- Given a full set of 7 legal documents, when `legal-audit benchmark` is invoked, then the agent produces standard compliance findings PLUS regulatory benchmark findings PLUS peer comparison findings (or SKIPPED notes)
- Given a single legal document, when `legal-audit benchmark` is invoked, then regulatory checklist runs for that document type only and peer comparison fetches the relevant peer equivalent only
- Given WebFetch returns a consent banner for a peer URL, when the agent processes it, then it reports `[SKIPPED]` with the reason and continues to the next peer
- Given WebFetch fails or is skipped for all peers, when `legal-audit benchmark` completes, then the report includes regulatory findings plus SKIPPED/INFO peer notes, and the summary shows peer comparisons successful: 0
- Given `legal-audit` is invoked without the `benchmark` sub-command, when the audit completes, then no regulatory or peer findings appear (FR6)

## Files to Modify

### 1. `plugins/soleur/agents/legal/legal-compliance-auditor.md`

**Changes:**

Add two new sections after the existing `### 3. Output Restrictions`:

**`### 4. Regulatory Benchmark Mode`**

- Trigger: when the Task prompt includes "benchmark mode"
- GDPR Art 13/14 disclosure checklist (enumerated items to check)
- Finding format: `[SEVERITY] [REGULATORY] Section > Issue > Recommendation`
- Claude already knows CCPA, ICO, CNIL from training — only GDPR Art 13/14 needs an explicit checklist since those are the most specifically enumerated requirements

**`### 5. Peer Comparison Mode`**

- Curated peer URL table (fetchable URLs only):

| Document Type | Peer | URL |
|---|---|---|
| Terms & Conditions | Basecamp | `https://basecamp.com/about/policies/terms` |
| Privacy Policy | Basecamp | `https://basecamp.com/about/policies/privacy` |
| Acceptable Use Policy | GitHub | `https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies` |

Only Terms & Conditions, Privacy Policy, and Acceptable Use Policy have standalone peer equivalents. Skip peer comparison for all other document types with: `[INFO] [PEER] No standalone peer equivalent for <type>.`

- WebFetch first. If result is unusable, report `[INFO] [PEER:name] [SKIPPED] Could not retrieve — <reason>` and continue.
- Finding format: `[SEVERITY] [PEER:<name>] Section > Issue > Recommendation`

After the standard summary block, add one line for GDPR Art 13/14 disclosure coverage (X/13 present) and peer comparison stats (attempted/successful/skipped).

### 2. `plugins/soleur/skills/legal-audit/SKILL.md`

**Changes:**

In Phase 2, add a conditional: if the user's input includes the word `benchmark`, append to the Task prompt: "Additionally, run benchmark mode: check against the GDPR Art 13/14 regulatory disclosure checklist and compare against peer SaaS policies." Otherwise, send the standard audit prompt unchanged.

Update the skill `description:` frontmatter to include benchmark-related trigger phrases (e.g., "legal benchmark", "benchmark legal compliance", "regulatory checklist").

### 3. `plugins/soleur/agents/legal/clo.md`

**Changes:**

Update the delegation table:

```markdown
| legal-compliance-auditor | Audit existing documents for compliance gaps and cross-document consistency. For benchmarking against regulatory checklists and peer SaaS policies, suggest `legal-audit benchmark`. |
```

### 4. Version Triad

- `plugins/soleur/.claude-plugin/plugin.json` — version `3.2.1` -> `3.3.0`
- `plugins/soleur/CHANGELOG.md` — new `[3.3.0]` entry under `### Added`
- `plugins/soleur/README.md` — verify counts unchanged (no new agents/skills), verify tables accurate
- Root `README.md` — badge `3.2.1` -> `3.3.0`
- `.github/ISSUE_TEMPLATE/bug_report.yml` — placeholder `3.2.1` -> `3.3.0`
- `plugin.json` description string — verify counts unchanged

## Dependencies & Risks

| Risk | Severity | Mitigation |
|---|---|---|
| WebFetch returns unusable content for all peers | HIGH | Regulatory benchmarking works independently. Feature delivers value even with 0 successful peer fetches. |
| Agent prompt becomes too long | MEDIUM | Only sharp edges (checklist, 3-row URL table, failure modes). Measure before/after. |
| Peer URLs go stale over time | LOW | Agent reports `[SKIPPED]`. URLs updated in future patches. |

## References

### Internal
- `plugins/soleur/agents/legal/legal-compliance-auditor.md` — agent being extended
- `plugins/soleur/skills/legal-audit/SKILL.md` — skill being extended
- `plugins/soleur/agents/legal/clo.md` — delegation table update
- `knowledge-base/learnings/2026-02-20-dogfood-legal-agents-cross-document-consistency.md` — audit cycle patterns
- `knowledge-base/learnings/2026-02-24-bsl-license-migration-pattern.md` — WebFetch limitations
- `knowledge-base/learnings/agent-prompt-sharp-edges-only.md` — agent instruction design

### External
- GDPR Article 13: Information to be provided where personal data are collected from the data subject
- GDPR Article 14: Information to be provided where personal data have not been obtained from the data subject
- Basecamp open-source policies: `https://github.com/basecamp/policies`
