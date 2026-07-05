---
feature: 5989-context-queries
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-05-feat-declarative-context-injection-context-queries-plan.md
issue: 5989
pr: 6035
adr: ADR-086
---

# Tasks — declarative context-injection (`context_queries`)

Design (post 6-agent plan-review): **pointer-only** lazy `PostToolUse:Skill` hook. See plan for full rationale.

## Phase 0 — Preconditions (verify against installed state)
- [ ] 0.1 Composition spike: register a throwaway 2nd `PostToolUse:Skill` hook in the **exact ship shape** (sibling matcher block), invoke a skill, verify (a) both it + phase-surface reach the model (concat vs last-writer-wins) and (b) per-hook vs aggregate 10K cap. If last-writer-wins → ship a NEW dedicated single-emitter hook (do NOT graft into phase-surface); record tradeoff in ADR.
- [ ] 0.2 Confirm `knowledge-base/marketing/brand-guide.md` git-tracked (36 KB → pointer path).
- [ ] 0.3 Surface probe: do web-agent Concierge sessions emit `PostToolUse:Skill`? (grep `apps/web-platform/server/` `options.hooks` + ADR-070). Record CLI-first vs CLI-intrinsic.
- [ ] 0.4 Read templates: `phase-surface-hint.sh`(+`.test.sh`), `pencil-collapse-guard.sh:42-59`, `scripts/generate-kb-index.sh` frontmatter idiom (`c==1` @138-141, block-start @176, continuation @144).

## Phase 1 — Hook `.claude/hooks/skill-context-queries.sh`
- [ ] 1.1 Skeleton: `set -uo pipefail`, `set -e` off, `trap 'exit 0' ERR`, exit-0-every-path; kill-switch `SOLEUR_DISABLE_CONTEXT_QUERIES=1`; test seam `CONTEXT_QUERIES_REPO_ROOT`; stable repo-root resolution.
- [ ] 1.2 Read `tool_input.skill` via `jq -r`; `${SKILL#soleur:}` anchored strip; reject `!~ ^[a-z0-9-]+$` → exit 0.
- [ ] 1.3 Resolve `plugins/soleur/skills/<name>/SKILL.md`; realpath-contain under skills dir; regular non-symlink file → else exit 0.
- [ ] 1.4 **Fast-path:** `grep -q '^context_queries:' "$SKILLMD"` → else exit 0 emitting nothing (no jq/git/glob work).
- [ ] 1.5 Parse `context_queries` by **reusing the full `generate-kb-index.sh` idiom** (inline `[a,b]` + block + quote-strip). Prefer extracting `.claude/hooks/lib/parse-frontmatter-list.sh` shared by both callers. Present-but-unparseable → skip note (never silent).
- [ ] 1.6 Per query: require `knowledge-base/` prefix; reject `..`/absolute; realpath + trailing-sep containment; reject symlink (`[[ -L ]]`); `git -C "$repo_root" ls-files --error-unmatch` (guarded → skip+continue on fail).
- [ ] 1.7 Globs: nullglob, **sort matches**, cap `MAX_GLOB`; dedup paths.
- [ ] 1.8 Emit Read-directive naming resolved artifacts + skip note (only when ≥1 declared query fails; nothing when 0 declared); envelope via `jq -n --arg`.

## Phase 2 — Register
- [ ] 2.1 Add hook to `.claude/settings.json` under a sibling `Skill` PostToolUse matcher block (per 0.1).

## Phase 3 — Pilot
- [ ] 3.1 Add `context_queries: [knowledge-base/marketing/brand-guide.md]` (block form) to `plugins/soleur/skills/frontend-design/SKILL.md` frontmatter.

## Phase 4 — Tests `.claude/hooks/skill-context-queries.test.sh`
- [ ] 4.1 Throwaway `git init` fixture repo with committed fixtures; `CONTEXT_QUERIES_REPO_ROOT` seam.
- [ ] 4.2 Behavior + negative tests: Scenarios 1-14 (AC1-AC7, AC13).
- [ ] 4.3 Consistency test: real `frontend-design` context_queries parses ≥1 → git-tracked file (AC14).

## Phase 5 — ADR + C4
- [ ] 5.1 Author `ADR-086` via `/soleur:architecture` (headline timing invariant; alternatives; pointer-not-inline; `## Consequences` consumer constraints: content-trust≠path-trust + must-present=literal-path; surface split; 0.1 fallback; AP-006).
- [ ] 5.2 Edit `model.c4`: add `hooks -> kb` edge; correct Hook-Engine description (already-falsified debt). Leave `model.c4:41` web api unedited.
- [ ] 5.3 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Verify
- [ ] 6.1 `skill-context-queries.test.sh` green; `components.test.ts` green; C4 tests green.
- [ ] 6.2 `skill-security-scan` on the hook → LOW-RISK/REVIEW (TR5).
- [ ] 6.3 PR review routed through `security-sentinel` + `observability-coverage-reviewer`.

## Ship (deferrals to file)
- [ ] Web-platform in-process parity issue (with user-facing symptom + 0.3 finding).
- [ ] Inline guaranteed-presence delivery (only if #5990 proves Read insufficient).
