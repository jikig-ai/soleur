---
title: Mandatory UX Wireframes + Stale-Claim Hardening
date: 2026-06-02
topic: mandatory-ux-wireframes-and-stale-claim-hardening
status: decided
lane: cross-domain
brand_survival_threshold: none
related_issues: [4819, 4817]
---

# Brainstorm: Mandatory UX Wireframes + Stale-Claim Hardening

Two coupled hardening changes to the soleur brainstorm/plan workflow, bundled in one PR
(#4817) because they edit the same files (AGENTS.md sidecars, brainstorm SKILL.md, plan
SKILL.md) and both came out of the same session failure.

## What We're Building

### Feature A — Mandatory UX wireframes for UI features

ux-design-lead `.pen` wireframes become a **required, non-skippable deliverable** for any
feature touching a new or changed UI surface — not an auto-spawned-but-skippable step and
not a menu option. The workflow may end a UI feature's design phase in exactly **two**
terminal states: **(1) a `.pen` artifact committed**, or **(2) a hard-block with a single
`PENCIL_CLI_KEY` / Node-22 instruction**. "Skipped" is removed as a permitted outcome.

- **Auto-install, then block** (operator's chosen policy, now verified feasible): when the
  Pencil MCP tools aren't connected, run `pencil-setup --auto` (which does
  `npm install --prefix ~/.local @pencil.dev/cli`, no sudo; headless Skia renderer, no
  display server), with auth via `PENCIL_CLI_KEY` from Doppler. Hard-block **only** when
  auth is genuinely unsatisfiable (no key + no interactive login) or Node < 22.9.0.
- **No non-Pencil fallback.** Headless `.pen` authoring works, so a Markdown/ASCII fallback
  would re-introduce the exact silent-skip / split-pipeline class we're killing. Invariant
  is **real `.pen` always**.
- **Trigger = any new OR changed UI surface** (new/modified pages, components, modals,
  banners, nav/layout, flows). Excludes pure copy/style tweaks and backend-only work.

### Feature B — Stale-claim hardening

Prevent the orchestrator from asserting unverified claims about repo capabilities — the
failure that happened in this very session (I claimed "pencil-setup only registers, can't
install" and baked "Pencil is GUI-only" into a CTO agent prompt; both false). Four
mechanisms:

1. **Subagent-prompt premise rule** (hard rule): a limiting/negative factual premise about
   repo state injected into a subagent prompt ("X is GUI-only", "Y doesn't exist", "Z only
   does W") MUST be grep/read-verified before spawn, OR phrased as a question for the agent
   to verify — never asserted. Unverified premises bias the agent and are invisible to the user.
2. **Verify-before-assert + hedge-word tell** (hard rule): grep the source before asserting
   what a repo tool/script/skill/flag does or doesn't do. The tell is hedge language about
   repo state — `only / doesn't / can't / no longer / to my knowledge / I believe / likely`.
3. **Extend premise-validation phases**: broaden brainstorm Phase 0.6/1.1 + plan Phase 0.6
   from "validate *cited* references" to also cover "the orchestrator's own option-bounding
   capability claims".
4. **Learning file** capturing this incident.

## Why This Approach

- The current behavior is a silent-skip masquerading as success. Research found **9 distinct
  skip sites**; the most dangerous on the autonomous path is plan Phase 2.5 `SKILL.md:321`
  (BLOCKING ux-design-lead self-stop is *recorded to `Skipped specialists:` and proceeds*),
  because **one-shot skips brainstorm entirely** — plan Phase 2.5 is the sole producer there.
- A UX-gate mandate **already exists** as constitution lines 147 + 177; line 177 is a demoted
  workflow gate (`ex-wg-for-user-facing-pages-with-a-product-ux`). Promoting it back to a real
  AGENTS.md `wg-*` (loaded every turn, scanner/hook-enforceable, telemetried) is the
  lowest-drift move — it re-activates an intentional rule rather than inventing a new one.
- Feature B exists because the repo's extensive premise-validation machinery is **artifact-
  scoped** (issue bodies, specs, plans, cited PRs) and **phase-scoped**. It has no coverage
  for the orchestrator's *own* spontaneous capability assertions or for premises embedded in
  subagent prompts — exactly the two surfaces that failed this session.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Wireframe outcome states | Exactly two: `.pen` committed OR hard-block | Removes "skip" branch; gate asserts artifact-on-disk, not "specialist ran" (proxy-vs-invariant) |
| Pencil-unavailable policy | Auto-install (`pencil-setup --auto`) → block only if auth/Node unsatisfiable | Operator choice; verified feasible via `check_deps.sh:441` + Doppler `PENCIL_CLI_KEY` |
| Non-Pencil fallback | None | Headless `.pen` authoring works; fallback would split the design pipeline + reabsorb silent-skip risk |
| UI-surface trigger | Any new/changed UI surface (excl. copy/style/backend) | Catches redesigns (e.g. nav-rail); shared term-list reference, plan keeps its mechanical glob as superset |
| Detection unification | Shared term-list reference cited by both skills; plan keeps file-glob escalation | CTO: brainstorm has no file list yet (prose stage); don't collapse into one fn |
| Enforcement layers | brainstorm 3.55 (producer) + plan 2.5 (producer *and* verifier) + deepen-plan halt + AGENTS.md `wg-*` (governance/telemetry) | Defense-in-depth mirroring the User-Brand-Impact 4.6 / observability 4.7 halt pattern |
| one-shot path | plan Phase 2.5 must GENERATE wireframes, not just verify | one-shot never runs brainstorm; plan is sole producer |
| AGENTS gate | Promote constitution line 177 `ex-wg-...` to a live `wg-*` (additive new ID; old ID immutable) | `cq-rule-ids-are-immutable`; re-activates intentional rule |
| Stale-claim: subagent-prompt premises | Verify-before-spawn or phrase-as-question (hard rule) | The exact failure this session; biases agent + invisible to user |
| Stale-claim: verify-before-assert | Grep before capability claims; hedge words are the trigger (hard rule) | Generalizes paraphrase-without-verification from artifacts to orchestrator's own claims |
| `PENCIL_CLI_KEY` provisioning | Source from Doppler; ensure provisioned so block ~never fires | Keeps a non-technical user from dead-ending |

## Open Questions

1. **`PENCIL_CLI_KEY` Doppler config + scope.** SKILL.md:108 reads it from `soleur/dev`; CTO
   suggested `prd`. Which config, and is the key actually provisioned today? (If absent, the
   hard-block fires in practice — decide in plan; likely a provisioning task.)
2. **AGENTS gate placement / loader-class fit.** A wireframe `wg-*` must fire on the trigger
   file classes (UI source under `apps/*` = code; plan/spec docs = docs-only). Verify the
   chosen sidecar (`AGENTS.core.md` vs `rest`) loads on those classes (per the loader-class-fit
   Sharp Edge) before freezing placement.
3. **Empirical headless authoring in *this* runner.** Headless `.pen` authoring is documented
   to work; confirm ux-design-lead can actually drive `mcp__pencil__*` after `--auto` in a
   fresh session as a /work Phase 0 precondition.
4. **Hedge-word rule false positives.** The verify-before-assert "tell" must not fire on
   non-repo claims (general programming facts). Scope it to claims about *this repo's* artifacts.

## Domain Assessments

**Assessed:** Engineering, Product (operator-decided)

### Engineering (CTO)

**Summary:** Feasible, medium complexity (days). Headless auto-install is real (`@pencil.dev/cli`,
npm `--prefix ~/.local`, no sudo, no display server); the only block is auth (`PENCIL_CLI_KEY`)
or Node < 22.9.0, so "auto-install then block" does NOT degrade to "always block". Recommended
shape: real `.pen` always (no fallback), gate asserts **artifact-on-disk** (not "specialist ran"),
enforced across brainstorm (producer) + plan 2.5 (producer+verifier, the sole producer on the
one-shot path) + deepen-plan halt + a new AGENTS.md `wg-*`. The one structural rule that prevents
the most likely failure (silent skip masquerading as success): the gate may emit only
`.pen committed` or `hard-block` — "skipped" is not a permitted outcome for a UI feature.

**Premise-correction note:** the first CTO pass was spawned with a false premise ("Pencil is
GUI-only"). It self-corrected on finding the headless adapter; a corrected re-spawn confirmed
the no-fallback conclusion. This incident is the direct motivation for Feature B.

### Product (operator-decided)

**Summary:** The operator (target users non-technical) decided wireframes are mandatory for any
new/changed UI surface and rejected a non-Pencil fallback in favor of auto-install-then-block.
No CPO spawn — the product question was decided directly.

## Capability Gaps

| Gap | Domain | Why needed (evidence) |
|---|---|---|
| `PENCIL_CLI_KEY` may not be provisioned in Doppler | Operations | `check_deps.sh:402` skips the headless tier when `pencil status` auth fails; SKILL.md:108 reads the key from Doppler. If unprovisioned, the hard-block fires for real. Verify + provision in plan. |
| No CI/Docker/zero-credential headless Pencil path | Engineering | Research: `git grep pencil` over `.github/workflows/` + `Dockerfile*` → zero matches. Fully-autonomous CI wireframing needs the key pre-injected; scope decision for plan. |

## User-Brand Impact

**If this lands broken, the user experiences:** a UI feature that ships with no wireframe (silent
skip persists) — or, conversely, a brainstorm that hard-blocks and dead-ends a non-technical user
when `PENCIL_CLI_KEY` isn't provisioned.

**If this leaks:** N/A — no user data, credentials (beyond the design-tool key, which is a
service credential sourced from Doppler, never committed), or PII surface.

**Brand-survival threshold:** none. This is a workflow/docs-class change touching SKILL.md +
AGENTS.md sidecars, no sensitive runtime path. (Per plan Phase 2.6: threshold=none reason — pure
orchestration/docs change; the only credential, `PENCIL_CLI_KEY`, is read-only from Doppler.)

## Next Steps

1. Spec via `skill: soleur:plan` (this worktree). Decide Open Questions #1 (Doppler config) and
   #2 (loader-class fit) in the plan.
2. The plan itself is a UI-discussing-but-orchestration-implementing change → Product/UX Gate
   tier NONE (no recursion).
