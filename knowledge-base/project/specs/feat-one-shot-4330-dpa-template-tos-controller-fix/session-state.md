# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-4330-dpa-template-tos-controller-fix/knowledge-base/project/plans/2026-05-22-feat-dpa-template-tos-controller-fix-4330-plan.md
- Status: complete

### Errors
None blocking. Three findings surfaced and corrected inline during deepening:
1. ToS section number drift in Phase 4 — plan body initially cited ToS §13 (Liability) + §17 (Governing Law); correct values are §11.2 + §15.1+§15.2 per live read of `docs/legal/terms-and-conditions.md:287-300,353-365`.
2. Broken learning citation — `2026-04-24-ops-remediation-pr-body-uses-ref-not-closes.md` does not exist on disk; replaced with canonical AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to` + real-existing learning `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md`.
3. AC8 TC_VERSION justification was wrong direction — `tc-version-bump-policy.md:75-77` says Tier 2 DOES require a PATCH bump; the bump does NOT fire here because the SHA guardrail at `check-tc-document-sha.sh:112,187` is scoped to ToS canonical only and this PR doesn't touch ToS. AC8 rewritten with correct two-step justification.

### Decisions
- **Directional ambiguity gate (Direction A vs B) is load-bearing** — issue body's proposed fix (flip ToS §3b.1) would regress PR #4225/#4289/#4328's deliberate Workspace-Owner-as-controller architecture. Plan defaults to Direction B (preserve ToS, add clarifying clause to DPD §2.1b(a)) with /work Phase 0 ACK gate; Direction A requires CLO+CPO panel re-spawn.
- **DPA sub-processor schedule excludes Anthropic from main Schedule 2** — operator runtime is BYOK per DPD §2.3(o); Anthropic appears in a separate "Customer-provisioned sub-processors (BYOK)" subsection with Anthropic Commercial Terms §C "authorized users" framing. Deviates from issue body's enumeration but matches deliberate architecture.
- **Sub-processor notice window adopts 30-day notice + 30-day objection** — conservative midpoint between Vercel's 5-day and Linear's 15+10-day; matches EDPB Art. 28 best-practice survey + enterprise procurement expectations.
- **Template includes Schedule 4 (TOMs, 17 sections)** as separate annex from Schedule 2 (sub-processors) per Vercel's Annex II precedent; satisfies SCC Annex II requirement.
- **Counsel review skipped at this PR** per Soleur-as-tenant-zero posture (#4081/#4066/#4213/#4289 precedent); external counsel re-review fires at first publish trigger event.
- **Brand-survival threshold = `single-user incident`** inherited from parent #4289; `requires_cpo_signoff: true` at plan time; `user-impact-reviewer` invoked at review time.

### Components Invoked
- Skill: `soleur:plan` (created the initial plan)
- Skill: `soleur:deepen-plan` (deepened with research)
- Phase 4.6 (User-Brand Impact halt): PASS
- Phase 4.7 (Observability gate): SKIPPED — pure-docs PR
- Phase 4.8 (PAT-shaped variable halt): PASS
- WebFetch: Vercel DPA + Linear DPA + Notion
- WebSearch: GDPR Art. 28 best practices 2026 + sub-processor notification windows + SCCs Module 2
- Bash live verification: 6 PR/issue numbers, 12 cited file paths, 4 cited learning paths, 5 AGENTS.md rule IDs, 5 GitHub labels, ToS §11/§15 numbering, DPD §2.1b/§2.3(u)/§4.2 footer carve-out
