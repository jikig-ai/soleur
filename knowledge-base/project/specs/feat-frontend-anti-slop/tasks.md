---
feature: frontend-anti-slop
plan: knowledge-base/project/plans/2026-05-21-feat-frontend-anti-slop-skill-plan.md
spec: knowledge-base/project/specs/feat-frontend-anti-slop/spec.md
lane: cross-domain
related_issue: 4264
draft_pr: 4265
branch: feat-frontend-anti-slop
worktree: .worktrees/feat-frontend-anti-slop
created: 2026-05-21
---

# Tasks: frontend-anti-slop (v1)

Derived from plan. Phases are dependency-ordered; do not reorder without re-deriving.

## Phase 0 — Preconditions (verify-only, no edits)

- [ ] 0.1 — `bun test plugins/soleur/test/components.test.ts 2>&1 | grep -E "fail|pass"` returns `0 fail` (canonical budget baseline).
- [ ] 0.2 — `find . -maxdepth 5 -type d -name "pr-review-toolkit" 2>/dev/null` returns empty (confirms external; route via `soleur:review`).
- [ ] 0.3 — `grep -n "selector" plugins/soleur/skills/ux-audit/references/finding.schema.json` shows current regex `^[A-Za-z0-9_\-/]*$` (regex-relaxation is well-defined).
- [ ] 0.4 — Open Code-Review Overlap query per plan §"Open Code-Review Overlap" — fold / acknowledge / defer for each match.
- [ ] 0.5 — `bun run /tmp/scan-probe.ts apps/web-platform/components/ui/gold-button.tsx` (any quick grep) confirms ≥ 1 gradient/inline-style pattern exists (calibration-baseline assumption holds). If absent, swap fixture file.

## Phase 1 — Port Hallmark rule subset (Tier 1 + Tier 2 documented)

- [ ] 1.1 — Fetch `references/slop-test.md` from Hallmark via `gh api repos/Nutlope/hallmark/contents/references/slop-test.md --jq .content | base64 -d > /tmp/hallmark-slop-test.md`.
- [ ] 1.2 — Classify each gate as Tier 1 (ship v1) / Tier 2 (deferred v1.5) / drop. Validate against plan §"v1 Tier 1 Gate List" binding 15-row table.
- [ ] 1.3 — Fetch + adapt `references/anti-patterns.md` to React/Tailwind JSX examples; drop page-shaped patterns.
- [ ] 1.4 — Write `plugins/soleur/skills/frontend-anti-slop/references/slop-rules.md` with both Tier 1 (active) and Tier 2 (`defer: v1.5` flag) rows.
- [ ] 1.5 — Write `plugins/soleur/skills/frontend-anti-slop/references/anti-patterns.md`.
- [ ] 1.6 — Add `<!-- Adapted from Hallmark (MIT) — see /LICENSES/hallmark.MIT.txt -->` header at top of each new reference file.

## Phase 2 — Schema + dedup extension (contract change, BEFORE Phase 3 consumer)

- [ ] 2.1 — `plugins/soleur/skills/ux-audit/references/finding.schema.json:24-27` — relax `selector` regex to `^[A-Za-z0-9_./#:\-]*$`.
- [ ] 2.2 — `:33-39` — add `"anti-slop"` to `properties.category.enum`.
- [ ] 2.3 — `plugins/soleur/skills/ux-audit/scripts/dedup-hash.ts:21-27` — add `"anti-slop"` to `FINDING_CATEGORIES` tuple. (No `computeFindingHash` branching, no `Finding` interface additions.)
- [ ] 2.4 — `plugins/soleur/test/ux-audit/category-drift.test.ts:11-17` — add `"anti-slop"` to `EXPECTED` tuple.
- [ ] 2.5 — `:40` — bump length pin 5→6.
- [ ] 2.6 — `:64-67` — update canonical phrase to `"real-estate | ia | consistency | responsive | comprehension | anti-slop"`.
- [ ] 2.7 — `plugins/soleur/test/ux-audit/finding-schema.test.ts` — add positive fixture: `category: "anti-slop"`, `selector: "apps/web-platform/components/ui/gold-button.tsx#GRADIENT-TEXT"`. Add fixture asserting `selector` with `#` is now accepted (regex-relaxation verification).
- [ ] 2.8 — `plugins/soleur/skills/ux-audit/SKILL.md:48` — list 6 categories in `FINDING_CATEGORIES` prose. Description: +≤ 3 words noting source-code finding source.
- [ ] 2.9 — `plugins/soleur/agents/product/design/ux-design-lead.md` — "5-category rubric" → "6-category rubric"; add anti-slop entry to `### Output contract` JSON example.
- [ ] 2.10 — `bash scripts/test-all.sh` exits 0 (schema is internally consistent before scanner consumes it).

## Phase 3 — Tier 1 scanner script (consumer)

- [ ] 3.1 — Write `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts`. Shebang `#!/usr/bin/env bun`. Header docblock per `bot-fixture.ts` convention.
- [ ] 3.2 — CLI: `tier1-scan.ts [--paths <globs>] [--dry-run|--json] [--rule <id>]`. Default paths from `git diff --name-only --cached --diff-filter=AMR -- 'apps/web-platform/{app,components}/**/*.{tsx,jsx,css}'`.
- [ ] 3.3 — Parser for `references/slop-rules.md` (markdown table → in-memory rules); filter to `tier === 1`.
- [ ] 3.4 — Per-rule scan via ripgrep patterns (no `ts-morph` — gates requiring AST are deferred to v1.5).
- [ ] 3.5 — Emit findings as JSON: `selector = "<file>#<rule_id>"`, `category = "anti-slop"`, `route = ""`.
- [ ] 3.6 — Dry-run: pretty-print to stdout. `--json`: emit JSON array.
- [ ] 3.7 — Manual sanity: `bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts apps/web-platform/components/ui/gold-button.tsx --json` returns JSON array length ≥ 1.

## Phase 4 — Scanner tests + calibration baseline

- [ ] 4.1 — Write `plugins/soleur/test/frontend-anti-slop/tier1-scan.test.ts` (mirrored location, NOT colocated; imports from `../../skills/frontend-anti-slop/scripts/tier1-scan`).
- [ ] 4.2 — Inline fixtures: 5 representative Tier 1 rules × pos + neg = 10 fixtures (GRADIENT-TEXT, GENERIC-DISPLAY-FONT, TRANSITION-ALL, UNIFORM-HOVER-SCALE, PLACEHOLDER-NAMES).
- [ ] 4.3 — Calibration baseline test: scanner on `apps/web-platform/components/ui/gold-button.tsx` → ≥ 1 finding with `category === "anti-slop"` and selector matching `/.+#[A-Z][A-Z0-9-]*$/`.
- [ ] 4.4 — `bash scripts/test-all.sh` exits 0.

## Phase 5 — Sibling-trim (description budget)

- [ ] 5.1 — Edit `plugins/soleur/skills/pencil-setup/SKILL.md` — description: trim 9 words per plan §"Sibling-Trim Sub-Plan" table.
- [ ] 5.2 — Edit `plugins/soleur/skills/test-fix-loop/SKILL.md` — trim 9 words.
- [ ] 5.3 — Edit `plugins/soleur/skills/campaign-calendar/SKILL.md` — trim 9 words.
- [ ] 5.4 — `bun test plugins/soleur/test/components.test.ts` exits 0 (target ≤ 1840 words including new skill at ~22).
- [ ] 5.5 — If FAIL at 5.4: trim `rclone` SKILL.md (33w → 25, -8) per plan §"Sibling-Trim Sub-Plan" fallback note.

## Phase 6 — SKILL.md + review hook + attribution (combined)

- [ ] 6.1 — Write `plugins/soleur/skills/frontend-anti-slop/SKILL.md`. Frontmatter: name, description ≤ 22 words ("Audits React/Next.js source for adapted Hallmark anti-AI-slop patterns via deterministic Tailwind/JSX scanner."), version. Body: invocation patterns, scope rules, calibration mode, link to references + LICENSES + NOTICE. No "Powered by Together AI" footer.
- [ ] 6.2 — Edit `plugins/soleur/skills/review/SKILL.md` — add `### Anti-slop Scanner Hook` stanza after gdpr-gate (line ~266). Trigger: frontend-file diff. Action: `bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts --paths $CHANGED_FILES --json` → pretty-print findings inline.
- [ ] 6.3 — Append Nutlope/hallmark stanza to `plugins/soleur/NOTICE` (mirror `alirezarezvani/claude-skills` block at NOTICE:23+).
- [ ] 6.4 — Create `LICENSES/hallmark.MIT.txt`: verbatim upstream MIT + Soleur provenance footer (mirror `LICENSES/skill-security-auditor.MIT.txt`).
- [ ] 6.5 — `grep -rnE 'utm_(source|medium|campaign)|Powered by Together AI' plugins/soleur/skills/frontend-anti-slop/ LICENSES/hallmark.MIT.txt plugins/soleur/NOTICE` returns ZERO matches.

## Phase 7 — Metadata sync (mechanical)

- [ ] 7.1 — `bash scripts/sync-readme-counts.sh` — updates skill count (73→74) in both READMEs.
- [ ] 7.2 — `bash scripts/sync-readme-counts.sh --check` exits 0.
- [ ] 7.3 — Edit `plugins/soleur/docs/_data/skills.js:11` — bump `Last verified:` date to 2026-05-21; add `frontend-anti-slop` to `code-review` category bucket.

## Phase 8 — Final verification + PR-ready

- [ ] 8.1 — `bash scripts/test-all.sh` exits 0.
- [ ] 8.2 — All Pre-merge ACs from plan §"Acceptance Criteria > Pre-merge (PR)" pass.
- [ ] 8.3 — `gh pr ready 4265` — flip draft to ready (or keep draft and let ship skill flip).
- [ ] 8.4 — File post-merge follow-up issue per plan §"Acceptance Criteria > Post-merge (operator)": "Calibration window for frontend-anti-slop v1 — log ≥ 20 findings, compute FP rate, decide v1.5 promotion path." Milestone: Post-MVP / Later.

## Phase 9 — Post-merge (operator, deferred work)

- [ ] 9.1 — Manual smoke: `/soleur:frontend-anti-slop --paths apps/web-platform/components/ui/ --dry-run` on fresh checkout; spot-check findings.
- [ ] 9.2 — 2-week dogfood window: capture findings in follow-up issue thread; compute FP rate. **NOT a /work task** — operator cadence over 2 weeks post-merge.
- [ ] 9.3 — At end of window: file v1.5 promotion issue per FP rate outcome.

---

## Deferred to v1.5 (do not implement in this PR)

- Tier 2 LLM-judgment reviewer agent (`plugins/soleur/agents/engineering/review/anti-slop-reviewer.md`).
- `references/genres.md` (4 condensed genre descriptions for Tier 2 context).
- 3 gates requiring ts-morph: CARD-IN-CARD, MISSING-FOCUS-VISIBLE-ACTIVE-DISABLED, ANIM-WITHOUT-REDUCED-MOTION.
- `--label <hash> <fp|tp>` flag for structured FP-rate labeling.
- Auto-filing via ux-audit pipeline (drop `dry_run=true` default).
- Default-on PR gate (further deferred to v2).

These are documented in plan §"v1.5 Roadmap" — pick up when calibration signal unlocks.
