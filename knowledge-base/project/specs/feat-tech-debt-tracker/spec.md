---
title: Tech-Debt Ledger Lifecycle + /soleur:resolve-debt skill
date: 2026-05-12
issue: 2723
parent_issue: 2718
brainstorm: knowledge-base/project/brainstorms/2026-05-12-tech-debt-tracker-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
---

# Spec: Tech-Debt Ledger Lifecycle (Spec A of the tech-debt-tracker sequence)

## Problem Statement

The `knowledge-base/project/learnings/technical-debt/` directory contains 11 entries dated 2026-02-12 through 2026-03-03. **Zero of them have a resolution marker; zero have been closed via a linked issue or PR.** The ledger is write-mostly: `/soleur:compound` populates it reactively after fixes ship, then entries sit indefinitely. There is no skill, command, or workflow surface that surfaces open debt for triage, prioritization, or closure.

The follow-on consequence: any future automated scanner (the original framing of #2723) would compound the backlog rather than the knowledge. Adding upstream/scan tooling without a closure mechanic is the dominant failure mode of debt tools, per CTO assessment and learning `2026-02-09-plugin-staleness-audit-patterns.md`.

## Goals

1. Make existing ledger entries **triagable** — give the founder a one-skill surface that lists open debt sorted by severity + age.
2. Make ledger entries **closable** — record `status` transitions and the issue/PR that closed them.
3. Generate the **evidence** required to unblock Spec B (the deferred scanner): does the founder actually close entries when the surface exists?
4. Preserve the existing two frontmatter schemas as-is. Schema unification is a separate follow-up.

## Non-Goals

- Scanner / scan-mode / scheduled cron — deferred to Spec B (re-evaluation criteria in brainstorm doc).
- Trending dashboard, time-series JSON, executive reporting — deferred to Spec B.
- Schema unification of the two frontmatter shapes under `technical-debt/` — separate follow-up issue.
- Backfill of `linked_issue` for the existing 11 entries — `linked_issue` is optional; backfill only `status` (default `open`).
- Cost-of-delay framework (WSJF / RICE / ICE) selection — deferred to Spec B.
- App-developer-facing surface (Soleur cloud users tracking debt in their own repos) — Phase 8+ scope.
- Wholesale lift of upstream `alirezarezvani/claude-skills` reference content (taxonomy, frameworks, communication templates) — liftable later under NOTICE attribution when Spec B is built.

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Add `status: open\|resolved\|wont-fix` to the frontmatter of all 11 existing entries in `knowledge-base/project/learnings/technical-debt/*.md`. Default to `open` during backfill. Schema A (`module/problem_type/component/tags/severity`) and Schema B (`title/category/tags/severity`) both gain this field; both are preserved otherwise. |
| FR2 | Add optional `linked_issue: <number>` (GitHub issue number, integer, no `#` prefix in YAML) to the frontmatter contract. Required only when `status: resolved`. Optional when `status: wont-fix`. Forbidden when `status: open`. |
| FR3 | Create `/soleur:resolve-debt` skill at `plugins/soleur/skills/resolve-debt/SKILL.md`. Skill description follows the third-person convention (`This skill should be used when...`) and stays under 30 words for the routing-budget check. |
| FR4 | The skill MUST list open ledger entries sorted by `severity` desc (high > medium > low > unset), then by file `date` asc (oldest first) as tiebreaker. Output format: a markdown table with columns: file, date, severity, component (or category), short title. |
| FR5 | The skill MUST support a "close entry" interactive flow: operator selects an entry; skill prompts for status (`resolved` or `wont-fix`) and `linked_issue`; skill rewrites the entry's frontmatter idempotently; skill prints the diff and requests commit confirmation. |
| FR6 | The skill MUST support a "list only" non-interactive flow when invoked with `--list` (for piping into other skills / `/loop`). Output table only; no prompts. |
| FR7 | The skill MUST validate that `linked_issue` (when provided) corresponds to an existing GitHub issue via `gh issue view <N> --json state,title`. The operator may pass `--no-verify` to skip validation when offline; the skill records this in the commit message. |
| FR8 | The skill MUST be registered in `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` under the engineering category (matches `code-quality-analyst` adjacency). Without this registration the skill is invisible to the docs site (per `2026-02-19-growth-strategist-agent-skill-development.md`). |
| FR9 | `/soleur:compound` MUST learn to set `status: open` when it auto-creates a new entry under `learnings/technical-debt/`. The new entry's other fields remain unchanged. This is a one-line edit to the compound skill's technical-debt write path. |
| FR10 | Update `knowledge-base/project/learnings/technical-debt/` README (create if missing) to document the new frontmatter contract (status + linked_issue field, allowed values, when each is required/optional/forbidden). |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Frontmatter mutation uses Python + PyYAML (per `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md`); never awk/sed. Body MD5 verified unchanged after mutation. Re-run idempotent (no-op on already-migrated files). |
| TR2 | Skill description word-budget check passes: `bun test plugins/soleur/test/components.test.ts` green. Cumulative skill descriptions stay under 1,800 words (per #618 / plugin AGENTS.md). |
| TR3 | The `linked_issue: <N>` field MUST be stored as a YAML integer (`linked_issue: 2723`), not a string with `#` prefix. Existing frontmatter parsers in the repo (`learnings-researcher`, `kb-search` skill) assume integer for issue references. |
| TR4 | PR for this spec MUST include a `## Changelog` section and a `semver:minor` label (new skill = minor per plugins/soleur/AGENTS.md). README.md plugin component counts MUST be re-verified. |
| TR5 | Skill MUST stay flat at `plugins/soleur/skills/resolve-debt/SKILL.md`. No `references/` are required for Spec A; add references only if word-count overflow forces extraction. |
| TR6 | No git operations from within the skill except `git diff --cached` for the confirmation preview. The skill prints the diff and asks the operator to commit themselves; it does not call `git commit` or `git push` automatically. (Reason: ledger commits land on whatever branch the operator is on; auto-commit would risk wrong-branch writes.) |
| TR7 | `gh issue view <N>` calls MUST set a 5-second timeout and fall back to `--no-verify` mode on network failure with a logged warning. Operator can still mark resolved without round-trip when offline. |
| TR8 | `/soleur:compound` integration (FR9) MUST NOT bump the brainstorm-time word budget for compound's SKILL.md — the change is one literal-string addition to a frontmatter-emission path. |

## Acceptance Criteria

- All 11 existing `learnings/technical-debt/*.md` entries have `status: open` in frontmatter after backfill PR merges.
- `/soleur:resolve-debt` invocation (interactive) successfully transitions one entry from `open` → `resolved` with a `linked_issue`, mutates the file, and emits a diff for operator commit.
- `/soleur:resolve-debt --list` produces a deterministic, severity-sorted table on stdout.
- `bun test plugins/soleur/test/components.test.ts` passes (word-budget guardrail).
- `bun test plugins/soleur/test/` full suite passes.
- `/soleur:compound` integration: when compound auto-creates a new tech-debt entry, the new file has `status: open` in frontmatter.
- Docs site build green; new skill appears in the engineering category on the rendered site.

## Re-Evaluation Trigger for Spec B (deferred scanner)

After Spec A ships, re-open the scanner conversation **only** when ALL of the following hold:

1. ≥3 ledger entries reach `status: resolved` within 60 days post-Spec-A-merge (proves the close-loop works).
2. Cloud platform (roadmap T1) has shipped beta OR founder reports velocity drag traced to known-but-untracked debt in retro.
3. At least one ledger entry has a `linked_issue` whose closing PR title or body references the ledger entry path (proves the ledger informs decisions, not just hindsight bookkeeping).

If any trigger fails to materialize within 90 days post-Spec-A-merge, recommend **closing the scanner sub-issue as wont-fix-evidence-based** rather than keeping it open as backlog.

## Risks

- **Schema split persists.** Spec A explicitly defers unification. Risk: two schemas drift further. Mitigation: file the unification follow-up issue immediately on Spec A merge (Phase 3.6 step 7 deferred-tracking obligation).
- **Operator never invokes the skill.** Risk of orphaned skill (per `2026-02-09-plugin-staleness-audit-patterns.md`). Mitigation: the re-evaluation trigger above is itself the mitigation — if the skill is unused, Spec B gets killed, and Spec A's lifecycle field becomes a low-cost no-op rather than an active bug surface.
- **`gh issue view` flakiness.** Mitigated by FR7 + TR7 (timeout + offline fallback).

## Out-of-Scope Carry-Forward (for Spec B's future spec)

These are pinned here so the future Spec B inherits them without re-deriving:

- Path allowlist: `plugins/ apps/ packages/ knowledge-base/`.
- Path denylist: `terraform/ infra/ doppler/ supabase/migrations/ .env* **/secrets/** **/private/** .worktrees/ **/*.tfvars **/*.tfvars.json **/terraform.tfstate*`.
- Aggregate-only PR-body summaries (counts, never paths or snippets).
- 2-cycle dry-run gate before commit mode (output to `.soleur/tech-debt/` only for cycles 1-2).
- Weekly digest issue cap = 1/run (establishes `CAP_PER_RUN` convention for the repo).
- NOTICE attribution at `plugins/soleur/skills/<scanner-skill-name>/NOTICE` mirroring `plugins/soleur/skills/gdpr-gate/NOTICE` schema.
- Env-routed `${{ ... }}` expansion in scheduled workflow (no direct interpolation of scan output).
- Cron slot: Wed 11:00 UTC (verified free; avoids 9 Monday-UTC-morning contentions).
- Skill wraps `code-quality-analyst` + `pattern-recognition-specialist` + `semgrep-sast` in a new `mode: scan` parameter; no fork of smell-detection logic.

## Domain Review (carry-forward)

CPO, CLO, CTO sign-offs recorded in the brainstorm doc. Brand-survival threshold: `single-user incident`. The user-impact-reviewer agent is the load-bearing gate at PR review time.
