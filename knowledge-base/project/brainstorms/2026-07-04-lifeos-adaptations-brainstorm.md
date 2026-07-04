---
last_updated: 2026-07-04
convention: pai-freshness-v1
status: research-capture
lane: cross-domain
brand_survival_threshold: single-user incident
---

# LifeOS → Soleur: Adaptable Mechanisms (Research Capture)

**Date:** 2026-07-04
**Source:** [danielmiessler/LifeOS](https://github.com/danielmiessler/LifeOS) (aka PAI — Personal AI Infrastructure), 16.3k⭐, MIT.
**Prompt:** "Not the same category as Soleur, but research it for good ideas/mechanisms to adapt/reuse."

## TL;DR

LifeOS is a different *product* (a personal life-OS that hill-climbs a user's "current state → ideal state / TELOS") but a near-identical *substrate*: a single self-contained Claude Code skill bundling ~49 skills, hooks, agents, a background daemon (Pulse, :31337), a 7-phase "Algorithm" (OBSERVE→THINK→PLAN→BUILD→EXECUTE→VERIFY→LEARN), and a file-system knowledge base. Because the machinery overlaps with Soleur so heavily, four of its mechanisms transfer cleanly. Operator selected **all four** (2026-07-04) to take forward.

## What We're Evaluating (4 candidates, ranked by ROI-per-effort)

### #2 — Freshness convention (`pai-freshness-v1`) — RECOMMENDED FIRST

**LifeOS mechanism.** Every file that loads into context at session start carries frontmatter with two *distinct* timestamps:
- `last_updated` — most recent *write* (any author, incl. auto-bumps from migrations/generators).
- `last_reviewed` — most recent *human review* of the content. Auto-writes do **not** bump it; only a principal-driven review flow (`bumpReviewedTimestamp`) does.

The staleness signal (A–F grade, statusline `FRESH` line, `most_stale` ranking) is computed from `last_reviewed`, **not** `last_updated` — "the signal we care about is: has a human looked at the source?" Grade = `reviewed_age_days : threshold_days` (A ≤25% … F >100% or never reviewed); overall = GPA-style mean. TELOS.md additionally carries per-H2 HTML-comment markers so sections drift independently. Derived files carry `derived_from:` + `generator:` and inherit freshness from their source.

**Soleur fit (strong, low cost).** Soleur's single largest failure class is **stale premises** — the brainstorm skill alone carries *dozens* of ad-hoc "grep before you trust this claim" rules (premise probes, ADR-deferral re-verification, PR-state re-checks). `roadmap.md` already uses `last_updated`/`last_reviewed` (Phase 0.25 syncs it). Generalizing one convention across AGENTS.md, `constitution.md`, plans, and learnings — with the crucial updated-vs-reviewed split and an A–F surface in the session-start preamble — turns scattered manual vigilance into a first-class signal. Complements, does not replace, the per-claim probes.

### #1 — The Router (effort/model classification) — RECOMMENDED SECOND

**LifeOS mechanism.** A named subsystem ("does it help decide *how* to handle a prompt?") with four stages:
1. **Classify** (`hooks/EffortRouter.hook.ts`, a `UserPromptSubmit` hook): 3-stage cascade — (A) deterministic fast-paths at 0ms (explicit `/e1`–`/e5`, praise/ack → MINIMAL, hard-ALGORITHM phrase triggers), (B) 60s SHA-256 decision cache, (C) an Opus-`high` classifier call. **NATIVE vs ALGORITHM is decided by whether the ideal state is pre-articulable in one line — not by complexity/length.** Fail-safe biases **up** (under-escalation is the failure mode).
2. **Route effort** → a *level* (`max`/`high`/`medium`/`low`), never a model name. Keystone pins (Advisor=`max`, classifier=`high`). **Core-System Override: domain beats tier** — editing core (Algorithm/hooks/system-prompt/skills) routes `max` regardless of tier.
3. **Select model** (`TOOLS/models.ts`): `EFFORT_MODEL` binds the 4 levels to the lineup (max=Fable, high=Opus, medium=Sonnet, low=Haiku). **Two edit points for the whole lineup** — `EFFORT_MODEL` (lineup change) + `CURRENT` (version release). A model entering/leaving/moving rungs is a one-line change.
4. **Dispatch** the resolved model as the per-call `model` param on `Agent(...)` / Workflow `agent(...)`. Works around the harness limit that the *main loop's* model is fixed at turn start — the dynamic range lives in the *dispatched agents*.

**Soleur fit (medium cost, real gain).** `/soleur:go` routes *intent→skill* but nothing routes *effort→model*; Soleur agents mostly inherit the parent model. Soleur's `Workflow`/`Agent` tools already accept per-call `model`/`effort`. A tier→model table + the two-edit-point pattern would (a) give genuine dynamic range (Haiku grunt-work vs. Opus/Fable for hard synthesis), and (b) collapse today's `model-launch-review` churn to a one-liner. The Core-System Override maps onto Soleur's own "core changes have outsized blast radius" instinct.

### #3 — Typed-item autonomic memory — MOST AMBITIOUS / MOST AGENT-NATIVE

**LifeOS mechanism.** Every memory item has a **type** (memory / idea / knowledge / proposal) *and* a **tier** (permission). "**Type is data, tier is permission**" — orthogonal, never collapsed. Four mutation tiers (`MutationTier.ts`, code-only allowlist, **default-deny** on everything not enumerated):
- **A** — auto set-overwrite (hot-layer memory, loads every prompt; cap 48×256 chars).
- **B** — logged-append with `tier-b-writes.jsonl` audit row per write (projects, contacts, knowledge graph, ideas).
- **C** — propose-only: queued + surfaced for human `yes/no/edit` approval (identity, writing-style, definitions, resume).
- **D** — untouchable by the memory system (`.env`, settings, hooks, code, system prompt).

A **background reviewer** reads recent conversation on a turn cadence and emits typed items; **≥0.70 confidence auto-applies**, 0.40–0.69 goes to an approval queue (Telegram in LifeOS), <0.40 discouraged. Proposals carry a `target_kind` discriminator validated against a closed allowlist. A 22-check `MemoryHealthCheck` + per-turn `🧠 MEMORY:` status line ("silence-by-default is explicitly rejected").

**Soleur fit (high cost, high payoff).** Soleur memory (`/compound`, learnings, AGENTS.md, MEMORY.md) is **manually** captured. The tier model — default-deny write allowlist with per-tier escalating friction — is squarely in Soleur's boundary-obsessed culture (`hr-write-boundary-sentinel-sweep`, `hr-write-boundary-sentinel-sweep-all-write-sites`). Autonomic capture with confidence-gated auto-apply-vs-approve is the genuinely agent-native version of `/compound`. Biggest lift; sequence last.

### #4 — System/User boundary (4 zones) — FITS PLUGIN + MULTI-TENANT

**LifeOS mechanism.** Every file falls into exactly one zone: **SYSTEM** (public-by-construction, zero user references, placeholders only) / **USER** (private, mounted via symlink/submodule, never inspected by release) / **INTERFACE** (the typed contract by which SYSTEM reads USER — `PaiConfig.ts` schema in SYSTEM, values in USER) / **RUNTIME-STATE** (ephemeral, gitignored). "**Publishable by construction rather than by scrub.**" **Exactly four allowed access patterns** (typed `PaiConfig.load()`, path computed from config, startup @-imports, HTTP/IPC via the daemon) — any fifth is a boundary violation. Enforced at **three layers**: write-time hook (`SystemFileGuard`), PR-time Action (`DenyListCheck`), release-time gates (14-gate `ShadowRelease`).

**Soleur fit (medium–high cost).** Maps 1:1 onto Soleur's plugin distribution + multi-tenant provisioning + the "never write CC memory; commit to the repo" rule. `plugins/soleur/` ≈ SYSTEM; tenant data ≈ USER; a typed config loader as the *only* cross-zone channel is a cleaner contract than today's ad-hoc reads. Three-layer enforcement mirrors Soleur's existing write-boundary hard rules.

## Bonus (fold in cheaply, not a standalone feature)

**Eval "3-Question Test"** for LLM-judge criteria: (1) would two independent judges agree >85%? (2) could the target game it without genuinely improving? (3) does the user actually care? + anti-criteria ("must NOT…"). A direct, low-cost quality upgrade to Soleur's existing `eval-harness` (promptfoo). Recommend folding into the eval-harness skill docs rather than a separate track.

## Explicitly Not Recommended

- **Pulse Next.js observability dashboard** (per-domain pages, knowledge/memory graphs). Soleur culture is *anti-eyeball* (`hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-as-plan-quality-gate`). Borrow only the per-domain *digest* structure for `operator-digest`, not a live dashboard.
- **Cross-vendor E4/E5 audits** (GPT-5.5 "Forge" pinned for vendor diversity). Philosophically interesting adversarial check, but cuts against Soleur's all-Claude, "default to latest Claude" grain; large lift for uncertain payoff. Park.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | 4 separate features, not one mega-spec | Distinct domains, efforts, and blast radii; a combined spec would be unreviewable. |
| Tracking | 1 umbrella issue + 4 child issues | Nothing deferred to the operator; each child carries re-eval criteria. |
| Sequencing | #2 → #1 → #4 → #3 | ROI-per-effort; #2 is cheapest and hits the worst failure class; #3 is largest and depends on tier/boundary groundwork. |
| Eval 3-Q test | Fold into `eval-harness` docs | Too small for its own track. |
| Dashboard / cross-vendor | Park | Against Soleur's anti-eyeball + all-Claude grain. |

## Open Questions (resolve at per-feature brainstorm time)

- **#2 Freshness:** Which files are "constitutional" for Soleur (AGENTS.md core/docs/rest sidecars? constitution.md? active plans? learnings?) and what are their per-file staleness thresholds? Where does the A–F grade surface — session-start preamble line, or a `/soleur` skill?
- **#1 Router:** Can a `UserPromptSubmit` hook set dispatched-agent models without fighting `/soleur:go`'s existing skill-routing? Is the classifier an extra model call worth its latency on every prompt, or fast-path-only to start? How does the tier→model table coexist with `model-launch-review`?
- **#3 Memory:** What is Soleur's tier-D untouchable set? Does the background reviewer run as a Stop-chain hook, and where does the approval queue surface (no Telegram — operator digest? a PR? a `/soleur` skill)?
- **#4 Boundary:** Is the SYSTEM/USER split already latent in `plugins/soleur/` vs `knowledge-base/project/` vs tenant provisioning outputs? What's the minimal typed-config INTERFACE?

## User-Brand Impact

- **Artifact:** the four candidate mechanisms (freshness convention, effort/model router, typed-memory write path, system/user boundary enforcement) — all touch how Soleur *decides* and *persists*, so each carries brand risk when built.
- **Vector:** a mis-scoped autonomic memory write or a boundary-enforcement gap could silently persist wrong/private data into a shipped artifact or a tenant's context — a single-user trust breach.
- **Threshold:** `single-user incident` (auto, per #5175).

## Domain Assessments

**Assessed:** (deferred to per-feature brainstorms — this is a research-capture doc, not a single-feature brainstorm.)

Each of the four child features will run its own Phase 0.5 domain-leader assessment at brainstorm time. CTO is relevant to all four; CPO to #1/#3 (capability surface); Legal/Ops to #3/#4 (data persistence + tenant boundary).
