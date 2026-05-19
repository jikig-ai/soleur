---
title: /goal Primitive as Operator Escape Hatch
date: 2026-05-15
status: captured
lane: cross-domain
brand_survival_threshold: single-user incident
related:
  - https://code.claude.com/docs/en/goal
  - knowledge-base/project/learnings/2026-03-23-action-completion-workflow-gap.md
  - knowledge-base/project/learnings/2026-03-18-ralph-loop-stuck-detection-hardening.md
  - plugins/soleur/hooks/stop-hook.sh
  - plugins/soleur/skills/one-shot/SKILL.md
---

# /goal Primitive as Operator Escape Hatch

## What We're Building

A documentation deliverable that positions Claude Code's `/goal` primitive (v2.1.139+) as Soleur's recommended escape hatch for **ad-hoc autonomous work that does not have a dedicated Soleur skill**.

Concretely:

- One markdown page at `plugins/soleur/docs/pages/goal-primitive.md` covering: when `/goal` is the right tool vs. existing Soleur skills, the transcript-only evaluator gotchas Soleur has already paid for, and 4–6 vetted condition recipes with built-in turn caps.
- A short "when to use `/goal`" paragraph in `plugins/soleur/AGENTS.md` so agents (not just operators) route correctly.
- A Claude Code min-version floor note (v2.1.139+) recorded in `plugins/soleur/.claude-plugin/plugin.json` description and/or `README.md` install instructions.

Zero new skill. Zero new wrapper code.

## Why This Approach

The brainstorm began with the framing "wire `/goal` into 6 Soleur autonomous skills (one-shot, test-fix-loop, drain-labeled-backlog, resolve-todo-parallel, resolve-pr-parallel, work)." Research falsified that premise:

1. **Soleur already has the equivalent of `/goal`, with more sophistication.** `plugins/soleur/hooks/stop-hook.sh` (316 lines, ralph-loop heritage) is a filesystem-semaphore Stop hook with Jaccard word-set similarity (≥80% over 3 turns), MD5 hash repetition (3-turn threshold), three-tier idle classifier, crash-orphan TTL, PPID scoping for parallel sessions, and a structured `<promise>DONE</promise>` completion marker read from `last_assistant_message`. `/goal` is a single fast-model judge reading raw transcript.
2. **`test-fix-loop` already uses exit codes** (`SKILL.md:48-104`). A deterministic gate is strictly cheaper and more reliable than a Haiku judge reading test output prose.
3. **`one-shot` already uses the `<promise>DONE</promise>` marker** (`SKILL.md:151`) — a structured signal beats a transcript judge.
4. **The "pseudo-handoff" failure class Soleur paid for 4× is exactly what a transcript-only evaluator reproduces.** Learnings record incidents where "Implementation complete", "and stop", "Announce to user", "next action:" all caused premature termination. A hard rule (`hr-when-a-workflow-concludes-with-an`) and constitution bans exist because of this. A `/goal` evaluator reading the same transcript would re-trigger the bug.
5. **`/goal` does add value, but for a different audience.** Operator-typed ad-hoc conditions ("CHANGELOG has entry for every PR merged this week"), headless-CI use (`claude -p "/goal …"`), and natural-language "until X" semantics for one-off work that doesn't warrant building a dedicated skill — these are real use cases Soleur does not currently address with first-class infrastructure.

The right deliverable is therefore not retrofit but **disambiguation**: a docs page that tells operators when `/goal` is the right primitive and gives them safe condition recipes.

## Key Decisions

| Decision | Rationale |
|---|---|
| **Do NOT retrofit /goal into one-shot, test-fix-loop, drain-labeled-backlog, resolve-todo-parallel, resolve-pr-parallel, work.** | Each already has a better-than-/goal completion mechanism (exit codes, `<promise>DONE</promise>`, CLI-output-empty, hash/Jaccard stuck detection). Adding /goal duplicates infra and reintroduces the transcript-pseudo-completion failure class. |
| **Position /goal as operator escape hatch for ad-hoc autonomous work outside dedicated skills.** | This is the actual value-add over Soleur's existing infrastructure: open-ended one-off loops, headless CI, conditions worth typing once but not worth a skill. |
| **Ship vetted condition recipes (4–6) with built-in turn caps.** | Runaway-spend mitigation. Recipes must (a) name a structured marker the evaluator can verify (exit code, `gh` empty result, file count) rather than fuzzy natural-language outcomes, and (b) always end with `or stop after N turns`. Default cap: 20. |
| **Declare CC min-version floor v2.1.139+ in plugin.json + install docs.** | Today no engines field is declared anywhere. Without a floor, the docs page would silently fail for operators on older CC. |
| **Add "when to use /goal" paragraph to plugins/soleur/AGENTS.md.** | So Soleur agents — not just operators — route correctly. Without this, agents will keep proposing /goal retrofit ideas like the one this brainstorm started with. |
| **Document the existing Stop hook + `<promise>DONE</promise>` mechanism as Soleur's first-party alternative.** | Operators must understand they have two layers: (1) Soleur's ralph-loop Stop hook (PID-scoped, hardened, runs automatically inside Soleur skills) and (2) `/goal` (session-scoped, single fast-model judge, manual). Don't hide that they coexist. |

## Non-Goals

- **No `soleur:goal` wrapper skill.** CC already provides `/goal`. Wrapping it just to inject a preamble adds maintenance for behavior the runtime supplies. Smallest blast radius wins.
- **No per-operator first-use ack persistence.** The recipe library + docs page is sufficient transparency. We do not need a session-state file to record "operator acknowledged /goal cost once."
- **No retrofit of any existing autonomous skill.** Including not even the cleanest-looking candidates (resolve-pr-parallel, drain-labeled-backlog) — their existing CLI-output completion checks are already verifiable end-states the skill enforces deterministically.
- **No engineering on Soleur's existing Stop hook in this scope.** The reviewer agent suggested porting `/goal`'s natural-language condition idea AS A feature of stop-hook.sh; that is a separate brainstorm, not this one.

## Open Questions

- **Skill-tool semantics of `/goal`.** The CTO assessment flagged "does `/goal` set the session goal when invoked via the Skill tool by a sub-skill, or only when typed by the operator at the top-level session?" as load-bearing. Even though we are NOT retrofitting, the docs page should answer this so operators know whether they can `/goal` from inside a Soleur skill they wrote, or only from the parent shell. A 30-minute spike is warranted before the docs page lands.
- **Recipe selection.** Tentative recipe targets, to refine in planning:
  1. Headless test gate: `npm test exits 0 in test/<path> or stop after 15 turns`
  2. Label-empty backlog: `gh issue list --label X is empty or stop after 30 turns`
  3. CHANGELOG drained: `CHANGELOG.md has an entry for every PR merged since YYYY-MM-DD or stop after 20 turns`
  4. Docs lint clean: `markdown-lint exits 0 across docs/ or stop after 10 turns`
  5. Module migration: `every call site of oldApi() has been replaced with newApi() AND tests pass or stop after 40 turns`
  6. Size budget: `every file in src/<dir> is under N LOC or stop after 25 turns`
- **Cross-link to existing infra.** Should the docs page render a side-by-side "Soleur skill vs. `/goal`" decision matrix? Decided yes in principle (helps disambiguation), exact format defers to plan.

## User-Brand Impact

- **Artifact at risk:** the operator's own Anthropic API budget (and indirectly, trust in Soleur after a runaway-spend incident).
- **Vector:** poorly-bounded `/goal` condition that the transcript-only evaluator never rules "yes" on. Loop continues turn after turn until the operator notices or hits Ctrl+C.
- **Threshold:** single-user incident. One operator burning a multi-hundred-dollar API spike on a Soleur-suggested condition pattern is enough to break the trust contract.
- **Mitigations baked into this brainstorm:**
  1. Every recipe ships with a hardcoded `or stop after N turns` clause.
  2. Docs page leads with the "transcript-only evaluator gotchas" section — operators see the runaway risk before they see the recipes.
  3. We point operators at Soleur's existing Stop hook + structured marker mechanism first; `/goal` is presented as the secondary option.
  4. Brand-survival threshold (`single-user incident`) is carried into the spec frontmatter for plan-time enforcement.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO). Marketing/Operations/Sales/Finance/Support not relevant — this is a developer-tool documentation deliverable with no external surface, no pricing, no support workflow.

### Engineering (CTO)

**Summary:** Originally recommended `test-fix-loop` as the pilot retrofit candidate. Learnings + repo research falsified this — `test-fix-loop` already has a deterministic exit-code gate that `/goal` would duplicate at higher cost. The CTO assessment's still-load-bearing contributions: (a) `/goal` should be treated as a circuit-breaker / turn-cap, never as primary done-detection; (b) the Skill-tool invocation semantics of `/goal` are an unverified load-bearing assumption and warrant a 30-min spike; (c) if anything is ever retrofit, hardcode condition templates per skill — never expose `--goal "<custom>"` to operators who will write conditions the evaluator can't verify. The escape-hatch framing inherits (a) and (c) implicitly: the recipe library IS the hardcoded-template set.

### Product (CPO)

**Summary:** Spend transparency is non-negotiable. The framing-gate Phase 0.1 flagged runaway spend as one of the three worst plausible operator-impact failure modes. CPO recommended: pre-flight banner before any autonomous loop, default turn cap, first-use ack. Under the escape-hatch framing, the recipes carry the cap in their text and the docs page IS the pre-flight banner — operators read it before typing `/goal`. First-use ack persistence was scoped out (Non-Goal) as redundant once recipes have caps baked in.

### Legal (CLO)

**Summary:** Under the current OSS distribution model (BSL 1.1, operator-supplied API key, no merchant-of-record relationship), Soleur has thin legal exposure for `/goal`-driven runaway spend. The BSL "AS IS" disclaimer (LICENSE lines 64–68) covers the chain-of-causation break, and the operator's direct Anthropic ToS relationship makes Soleur a tool, not a billing intermediary. Recommended action: add a one-line "this primitive runs autonomous turns against your Anthropic key" note in the README and the docs page — as norms hygiene, not legal compliance. Revisit when app.soleur.ai SaaS path goes live (different billing posture).

## Capability Gaps

None reported by domain leaders. The CTO assessment explicitly noted "`soleur:skill-creator` and existing skill conventions cover the retrofit work" — and the escape-hatch reframe needs even less: it's a docs page, an AGENTS.md paragraph, and a plugin.json field. No new agent, skill, hook, or script.
