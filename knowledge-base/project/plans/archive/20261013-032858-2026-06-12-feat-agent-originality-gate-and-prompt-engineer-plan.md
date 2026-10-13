---
lane: cross-domain
brand_survival_threshold: none
---

# feat: Agent-originality CI gate + Prompt Engineer agent (agency-agents Patterns A + C)

## Enhancement Summary

**Deepened on:** 2026-06-12
**Sections enhanced:** Research Reconciliation, Files to Create, Acceptance Criteria, Risks
**Passes run:** verify-the-negative (5 load-bearing claims, all CONFIRM), calibration re-probe, precedent grounding (test-shape vs components.test.ts), halt gates 4.6/4.7/4.8/4.9 (all pass)

### Key Improvements
1. **Calibration empirically re-verified** (reproduced exactly): over the 66 `discoverAgents()` bodies — **0 pairs ≥ 50% (FAIL default → check PASSES today)**, **exactly 1 pair ≥ 40%** (the 41.66% `agent-finder`↔`functional-discovery` pair), **exactly 1 pair ≥ 30% (WARN default → that pair logs)**. This is the written justification for FAIL=50/WARN=30.
2. **All five negative/premise claims CONFIRMED** by an independent grep pass (see Research Insights): no CI agent-budget gate; CI auto-discovers the new test; count denominators 66/67; docs auto-derive; no existing agent owns prompt authoring.
3. **No test-all.sh edit, no docs-data edit, no python3 dep** — confirmed against `scripts/test-all.sh:174`, `bunfig.toml:18`, `agents.js`/`stats.js`.

### New Considerations Discovered
- With FAIL=50/WARN=30, the WARN log on every run is exactly one line (the 41.66% pair). Acceptable and informative; do not suppress it — it is the living calibration record.
- The four deepen-plan halt gates (User-Brand Impact, Observability, PAT-shaped, UI-wireframe) all pass: threshold `none` with no sensitive-path match; `## Observability` declared N/A; no PAT-shaped vars; no UI surface / `.pen` required.

## Overview

Port two patterns from the peer audit of `msitarzewski/agency-agents` (MIT) into Soleur, in **one PR** (`semver:minor` — adds an agent), with a `## Changelog` section:

- **Pattern A** — a CI test (`plugins/soleur/test/agent-originality.test.ts`) that flags near-duplicate agent **bodies** using 8-word shingle Jaccard similarity. Re-implemented in Bun/TS from the upstream methodology (`scripts/check-agent-originality.sh`, MIT, python3) — **no python3 dependency added**.
- **Pattern C** — a new engineering agent `plugins/soleur/agents/engineering/prompt-engineer.md` that helps author, optimize, and test prompts/agent/skill definitions. Soleur-compliant (terse routing-only description, no `<example>`/`<commentary>`, `model: inherit`), NOT the upstream persona/emoji/`vibe:` style.

The audit's Tier-1 entry for `competitive-intelligence.md` is **deliberately out of scope** (scope = A + C only); the PR body must say so.

### Source attribution (methodology only; MIT)
- Pattern A re-implements: `msitarzewski/agency-agents/scripts/check-agent-originality.sh` (MIT).
- Pattern C draws inspiration from: `msitarzewski/agency-agents/engineering/engineering-prompt-engineer.md` (MIT) — style intentionally NOT copied.
Both new files carry an MIT attribution comment at the top referencing the upstream path.

## Research Reconciliation — Spec vs. Codebase

The task description makes several premise claims. Every one was verified against the worktree; **two are materially inaccurate and reshape the plan**.

| Premise claim (from ARGUMENTS) | Reality (verified) | Plan response |
|---|---|---|
| "consistent with how Soleur already gates the agent DESCRIPTION token budget" / "ADD an originality assertion there [components.test.ts]" | `plugins/soleur/test/components.test.ts` gates the **SKILL** description cumulative word budget (1800-word cap, `SKILL_DESCRIPTION_WORD_BUDGET`). It does **NOT** gate the **agent** description budget in CI at all. The agent budget (`grep -h 'description:' agents/**/*.md \| wc -w` < ~2500) is a **manual checklist item** in `plugins/soleur/AGENTS.md`, currently **already over** at ~2731 words. There is no CI enforcement of agent descriptions beyond per-agent presence/no-`<example>`/valid-model. | Create a **sibling file** `agent-originality.test.ts` (the task's preferred option, now firmly justified). Do NOT bolt onto the skill-budget block. Note in the PR body that the "existing agent budget gate" framing was imprecise — the precedent is the *skill* budget test's shape (cumulative assertion over discovered components), which the new test mirrors. |
| "the roster grows past ~68 agents" / "Update README counts (68)" | `discoverAgents()` returns **66** (excludes `operations/references/service-deep-links.md` + READMEs). Total `.md` files under `agents/` = **67** (README "67 agents" counts all files incl. the reference agent). After adding `prompt-engineer.md`: total files **68**, `discoverAgents()` = **67**. | README counts go **67 → 68** (file-count semantics). Engineering domain header `### Engineering (30) → (31)`. `discoverAgents()`-based test sees 67. See "Count semantics" below — getting this right matters; the two numbers (66/67 vs 67/68) are different denominators. |
| FAIL ≥ 40% "must PASS against the current roster"; "real baseline ~1.5%" | **The current roster has a pair at 41.66%** (`engineering/discovery/agent-finder.md` ↔ `engineering/discovery/functional-discovery.md`) on entity-neutralized 8-word-shingle Jaccard — **above the proposed 40% FAIL line.** Next-highest pair is 15.72% (`coo`↔`cco`). This is a legitimately-distinct pair (find-agents-for-stack-gap vs check-functional-overlap) that shares `/plan`-spawned community-registry scaffolding (Input/Output/registry-query boilerplate), NOT a find-replace re-skin. | A naive FAIL≥40% port **fails CI on day one**. Resolve with **written-justification calibration**: set `FAIL = 50%` default (still well below a true re-skin's ~90%+ and comfortably above this legitimate 41.66% structural-overlap pair), `WARN = 30%`. Make both env-overridable. Document the 41.66% pair inline in the test file AND in the PR body as the calibration evidence. Do NOT lower below the observed pair without justification — this IS the justification. (Investigated: not a duplicate; the two agents have distinct purposes + distinct disambiguation descriptions.) |
| upstream's heavy proper-noun ENTITY neutralization | Soleur is not a multi-market localization library — confirmed. The 41.66% measurement used only minimal neutralization (lowercase + strip punctuation to spaces). | Keep neutralization **minimal**: lowercase + collapse non-alphanumeric to whitespace. Drop the upstream country/platform entity table. Document this deviation in a comment (task-mandated). |

### Count semantics (load-bearing — two different denominators)
- **File-count (README prose + tables):** all `.md` under `agents/` = **67 today → 68** after the add. The three manual edit sites: `README.md:5`, `README.md:14`, `plugins/soleur/README.md:43`. Plus engineering domain header `plugins/soleur/README.md:85` `(30)→(31)` and a new agent row.
- **`discoverAgents()` (the new test's input):** **66 today → 67** after the add. The test asserts on whatever `discoverAgents()` returns; no count literal is hardcoded in the test.
- **Auto-derived (NO manual edit):** `plugins/soleur/docs/_data/agents.js` (`walkAgents`) and `plugins/soleur/docs/_data/stats.js` (`countMdFilesRecursive`) both walk the filesystem → landing-page stats update automatically. Verify post-edit, do not hand-edit.

## User-Brand Impact

**If this lands broken, the user experiences:** a red CI check on the next agent-adding PR (Pattern A false-positive), or a hallucinated/low-quality prompt-engineer agent surfacing in routing. Both are developer-facing, internal to the Soleur plugin repo — no end-user (founder-operator) production surface is touched. No runtime code, no migration, no data path.

**If this leaks, the user's data is exposed via:** N/A — no data surface. The test reads only repo-committed agent markdown; the agent is a prompt-authoring helper with no data access beyond a normal agent session.

**Brand-survival threshold:** none — internal plugin tooling + a new agent definition; no user-facing artifact, no regulated-data surface, no infrastructure. (Sensitive-path check: diff touches `plugins/soleur/test/**`, `plugins/soleur/agents/**`, `*.md` docs only — none match the preflight Check 6 sensitive-path regex; threshold `none` with reason recorded here satisfies the scope-out requirement.)

## Files to Create

1. **`plugins/soleur/test/agent-originality.test.ts`** — Bun/TS test. Top-of-file MIT attribution comment referencing `msitarzewski/agency-agents/scripts/check-agent-originality.sh (MIT)` + a comment documenting the minimal-neutralization deviation and the 41.66% calibration rationale. Imports `discoverAgents`, `parseComponent` from `./helpers`. Logic:
   - `neutralize(s)`: `s.toLowerCase().replace(/[^a-z0-9\s]+/g, " ")` (minimal set; upstream entity table intentionally dropped — comment).
   - `shingles(text, n=8)`: tokenize neutralized text on whitespace, build a `Set` of n-word joined windows.
   - `jaccard(a, b)`: `|a∩b| / |a∪b|`, returns 0 if either set empty.
   - Thresholds: `const FAIL = Number(process.env.AGENT_ORIGINALITY_FAIL ?? 50) / 100;` `const WARN = Number(process.env.AGENT_ORIGINALITY_WARN ?? 30) / 100;` (env-overridable, task-permitted "if trivial").
   - For every unordered pair of `discoverAgents()` bodies (strip frontmatter via `parseComponent().body`): compute Jaccard. `console.warn` each pair ≥ WARN (WARN logged, per task). One `expect(...)` assertion that **fails** if any pair ≥ FAIL, with a message naming the offending pair + score.
   - Guard: skip pairs where either body has < `n` tokens (degenerate; Jaccard would be 0 anyway).
   - Keep it O(n²) over ~67 bodies — trivially fast (probe ran in well under the 384ms full components suite).

2. **`plugins/soleur/agents/engineering/prompt-engineer.md`** — new agent. Top-of-body MIT attribution comment referencing the upstream `engineering/engineering-prompt-engineer.md` path. Frontmatter:
   - `name: prompt-engineer` (matches filename)
   - `model: inherit`
   - `description:` 1–3 sentences, routing-only, with a disambiguation clause. NO `<example>`/`<commentary>`. Draft:
     > "Use this agent to author, optimize, and test prompts and agent/skill definitions — defining expected output format and success criteria, writing happy/edge/failure test cases, and removing vague qualifiers. Use the skill-creator skill for SKILL.md scaffolding/packaging and best-practices-researcher for external prompt-engineering research; use this agent to engineer the prompt content itself."
   - Body (terse, outcome-focused, matching `agents/engineering/review/*.md` shape): sections covering (1) define expected output format + success criteria before writing; (2) ship prompt test cases (happy / edge / failure); (3) version prompts like code; (4) avoid vague qualifiers; (5) ground assumed knowledge. Plus a short "Boundaries / what NOT to do" close (don't scaffold packaging — that's skill-creator; don't do external research — that's the researchers).

## Files to Edit

1. **`README.md`** — line 5 (`67 agents` → `68 agents`) and line 14 (`**67 agents**` → `**68 agents**`). Verify these are the only `67`-as-agent-count occurrences (grep confirmed: exactly these two + the plugins README line).
2. **`plugins/soleur/README.md`** —
   - line 43 `| Agents | 67 |` → `| Agents | 68 |`.
   - line 85 `### Engineering (30)` → `### Engineering (31)`.
   - Add a new row to the **top-level Engineering table** (the one currently holding only `cto`, lines 87–90), e.g. `| `prompt-engineer` | Author, optimize, and test prompts and agent/skill definitions; ship happy/edge/failure prompt test cases |`. (prompt-engineer is a top-level engineering agent like `cto`, not in a sub-category — so it does NOT go under Review/Research/etc.)
3. **Reciprocal disambiguation** (per AGENTS.md Agent Compliance Checklist: "add disambiguation sentences to agents with overlapping scope, both directions"):
   - The strongest overlap is with the **skill-creator skill** (a skill, not an agent) and **best-practices-researcher** (external research vs prompt authoring). skill-creator is a skill; per checklist scope, add a one-line disambiguation pointer in the prompt-engineer description (done above). For the agent side: add a reciprocal clause to **`best-practices-researcher.md`** description only if its scope genuinely collides ("…use prompt-engineer to author/test prompt content; use this agent for external best-practices research"). **Decision deferred to deepen-plan Phase 4.4 precedent check** — confirm via word-budget headroom whether the reciprocal clause fits; if the agent-description budget (already ~2731, over the soft 2500 target) makes adding words risky, prefer the leanest possible reciprocal (≤8 words) or document that the one-directional pointer in prompt-engineer's own description suffices because no existing agent's *primary* purpose is prompt authoring. Note: the soft 2500 target is already exceeded and is NOT CI-gated, so a small overage is acceptable but should be acknowledged in the PR body.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `plugins/soleur/test/agent-originality.test.ts` exists, has the MIT-attribution + deviation comment, and **passes** via `bun test plugins/soleur/test/agent-originality.test.ts` against the current roster (no pair ≥ FAIL=50%).
- [ ] The test logs (does not fail on) the 41.66% `agent-finder`↔`functional-discovery` pair at WARN, and the test comment + PR body document this pair as the calibration baseline.
- [ ] Thresholds are env-overridable (`AGENT_ORIGINALITY_FAIL`, `AGENT_ORIGINALITY_WARN`); verify by running with `AGENT_ORIGINALITY_FAIL=40 bun test …/agent-originality.test.ts` and confirming it **fails** (proving the 41.66% pair would trip a 40% bar — evidence for the calibration).
- [ ] `plugins/soleur/agents/engineering/prompt-engineer.md` exists with `name: prompt-engineer`, `model: inherit`, routing-only description with a disambiguation clause, no `<example>`/`<commentary>`, MIT attribution comment, non-empty body.
- [ ] `bun test plugins/soleur/test/components.test.ts` is **green** (new agent passes frontmatter/model/kebab/no-example/non-empty-body checks; SKILL budget untouched).
- [ ] `bun test plugins/soleur/` is green (this is exactly what CI's `bun` shard runs — auto-discovers the new test; no `test-all.sh` wiring needed).
- [ ] README counts updated: `README.md` (2 sites) and `plugins/soleur/README.md` (Agents count + Engineering `(31)` + new row). Verify no stale `67`-as-agent-count remains: `grep -rn '67 agent\|Agents | 67\|Engineering (30)' README.md plugins/soleur/README.md` returns nothing.
- [ ] Agent description token budget acknowledged: run `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w`; record before/after in PR body. (Already ~2731; not CI-gated. The add should be ≤ ~40 words.)
- [ ] PR has `semver:minor` label + `## Changelog` section + the note: "lands Patterns A + C from the agency-agents peer audit; the audit's Tier-1 `competitive-intelligence.md` entry was deliberately NOT included (scope = A + C only)."
- [ ] `plugin.json` version and `marketplace.json` version are **unchanged**.

### Post-merge (operator)
- [ ] None. CI auto-discovers the test; docs stats auto-derive; version bump is handled by `version-bump-and-release.yml` on merge. (Automation-feasibility gate: nothing operator-only.)

## Test Scenarios
1. **Originality test green on current roster** — passes at FAIL=50%.
2. **Originality test red on a synthesized re-skin** — (manual, ephemeral, NOT committed) copy an existing agent body, swap a noun, confirm Jaccard ≈ >90% trips FAIL. Validates the gate actually catches re-skins. Do not commit the fixture.
3. **Env override** — `AGENT_ORIGINALITY_FAIL=40` makes the suite red (proves 41.66% pair is the calibration boundary).
4. **components.test.ts** — new agent satisfies all frontmatter conventions.
5. **CI shard** — `bun test plugins/soleur/` discovers and runs the new file (matches `test-all.sh` `run_suite "plugins/soleur" bun test plugins/soleur/`).

## Research Insights (deepen-plan, verified 2026-06-12)

**Calibration probe (reproduced):** Re-running the entity-neutralized 8-word-shingle Jaccard over the 66 `discoverAgents()` bodies with minimal neutralization (`toLowerCase().replace(/[^a-z0-9\s]+/g," ")`):
- pairs ≥ 50% (FAIL default): **0** → the gate passes against the current roster.
- pairs ≥ 40%: **1** → the `engineering/discovery/agent-finder.md` ↔ `engineering/discovery/functional-discovery.md` pair at 41.66% (proves a 40% FAIL bar would be red today).
- pairs ≥ 30% (WARN default): **1** → same pair logs at WARN; no other pair is near.
This is the written justification the task requires for not lowering FAIL to 40%.

**Verify-the-negative pass (all CONFIRM, citations):**
1. No CI agent-description budget gate — `components.test.ts:144-173` gates only the SKILL cumulative budget (`SKILL_DESCRIPTION_WORD_BUDGET`); the Agent-frontmatter block (`:22-62`) checks presence/no-`<example>`/valid-model only. The new test is a *sibling* file mirroring the skill-budget *shape*, not bolted onto it.
2. CI auto-discovers the new test — `scripts/test-all.sh:174` runs `run_suite "plugins/soleur" bun test plugins/soleur/`; `bunfig.toml:18` `pathIgnorePatterns = [".worktrees/**", "apps/web-platform/**"]` does not exclude `plugins/soleur/test/`. **No `test-all.sh` edit needed.**
3. Count denominators — `helpers.ts:9-13` filters `/references/` + `README*`; `discoverAgents()` = 66 (→67), total `.md` files = 67 (→68).
4. Counts auto-derive — `agents.js` `walkAgents()` and `stats.js` `countMdFilesRecursive()` walk the filesystem; no hardcoded count. Only manual edits: `README.md:5`, `README.md:14`, `plugins/soleur/README.md:43` (Agents count) + `:85` (`### Engineering (30)→(31)`) + a new agent row.
5. No existing agent owns prompt authoring — no agent description under `agents/` matches author/optimize/test-prompts; `skill-creator` and `heal-skill` are **skills** (`skills/.../SKILL.md`), not agents — so the disambiguation pointer in prompt-engineer's own description is one-directional by necessity (a skill cannot carry an agent-style reciprocal clause in the same registry). Reciprocal agent-side clause (best-practices-researcher) is optional/lean per Files-to-Edit item 3.

**Precedent-diff (Phase 4.4):** Pattern A's test shape has a direct in-repo precedent — the cumulative-assertion-over-discovered-components form of `components.test.ts` "Skill description budget" block. The new test reuses `discoverAgents`/`parseComponent` from `helpers.ts` (same import surface). No SQL/scheduled-job/lock/atomic-write patterns are introduced (those Phase 4.4 precedent classes are not-applicable). No novel pattern requiring reviewer scrutiny.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal plugin tooling (a CI test) plus a new engineering-domain agent definition. No UI surface (Files-to-Create/Edit are `*.test.ts`, `*.md` agent + README only — no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). No regulated-data surface, no infrastructure, no LLM-on-operator-data processing. GDPR gate (2.7), IaC gate (2.8), Observability gate (2.9) all skip silently (no code-class file under `apps/*/server|src|infra`, `plugins/*/scripts/`; the new `.test.ts` is a test, not a server/script surface, and introduces no error path / log / failure mode requiring a `## Observability` declaration).

## Observability

N/A — pure test + agent-markdown change. No new server code, route, cron, Inngest function, or infrastructure surface. The "liveness signal" for Pattern A is the CI check itself (red = a near-duplicate agent landed); discoverability is `bun test plugins/soleur/` with no SSH.

## Risks & Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6 — this plan's threshold is `none` with a recorded reason (sensitive-path scope-out), satisfying preflight Check 6.
- **41.66% calibration is the crux.** If a reviewer pushes for FAIL=40%, the answer is: the only pair above 40% is a legitimately-distinct pair sharing scaffolding, not a re-skin; lowering to 40% gives a permanent red check with no real duplicate to fix. 50% sits above the legitimate-overlap ceiling (15.72% next-highest after the 41.66% outlier) and well below a true re-skin (≈90%+).
- **Count denominator trap:** `discoverAgents()` (66/67) ≠ file-count (67/68). The test never hardcodes a count; only README prose uses file-count. Do not "fix" one to match the other.
- **Agent description budget is NOT CI-gated** (only the SKILL budget is). Don't waste effort trimming sibling agent descriptions to fit a phantom gate; do acknowledge the soft 2500-word target is already exceeded (~2731) in the PR body so it's an informed deviation.
- Verify the new test is picked up by the `bun` shard, not the `scripts` shard — it's a `.test.ts` under `plugins/soleur/`, caught by `run_suite "plugins/soleur" bun test plugins/soleur/`. No `scripts/test-all.sh` edit required (confirm by reading the suite list; do NOT add a redundant `run_suite` line).
- Do NOT commit any synthesized re-skin fixture used in Test Scenario 2 — `cq-test-fixtures-synthesized-only` permits synthetic fixtures, but a committed near-duplicate agent would trip the very gate being added.
