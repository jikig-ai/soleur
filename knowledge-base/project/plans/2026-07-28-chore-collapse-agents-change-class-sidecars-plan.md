---
title: Collapse the AGENTS change-class sidecar split into a single always-loaded corpus (ADR-150)
date: 2026-07-28
type: chore
issue: 7012
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-150 (provisional — re-verify next-free ordinal at ship)
---

# Collapse the AGENTS change-class sidecar split (ADR-150)

## Enhancement Summary

**Deepened on:** 2026-07-28
**Gates cleared:** 4.6 User-Brand Impact · 4.7 Observability · 4.8 PAT-shaped ·
4.9 UI-wireframe (no UI surface) · 4.10 Encryption Posture (disposition
recorded, not skipped) · 4.55 Downtime (no serving surface)

### Key improvements over the issue's framing

1. **Separated the two mechanisms the issue conflates.** The −82.5 % per-turn win
   comes from index/body separation, not from change-class conditionality.
   Collapse must preserve the former and retire only the latter (Overview, SE-3).
2. **Corrected "retires `session-rules-loader.sh`" to "retires the classifier".**
   The hook has eight jobs; seven survive, including SOC 2 evidence and the only
   SessionStart read of the tmpfs alarm (Correction 1, SE-9).
3. **Measured the merge instead of projecting it.** Simulated read-only:
   `AGENTS.rules.md` = 37,292 B stripped, **101/101 rules preserved**, new
   `B_ALWAYS` = **42,425 B** — **1,255 B smaller** than what 70 % of sessions
   already load today.
4. **Pre-ran the real lints against the merged corpus.** Exactly two
   `lint-rule-ids.py` failures (both core-pinning, 45 + 5 ids) and a fail-closed
   `exit 2` from the budget lint. This turns Phase 3 from guesswork into a
   checklist with known expected output.
5. **Found the migration's blind spot (SE-1)** — the ADR-092 weakening gate goes
   *vacuous* across the file move — and designed AC4 (body-hash identity) as the
   compensating positive proof.

### Corrections forced by the review panel (3 agents, 4 P0s)

6. **P0 — the compensating control covered 73 % of the corpus.**
   `lint-rule-bodies.py` gates only `^(hr|wg)-`, so its manifest holds **74**
   entries, not 101. The old AC4 ("100 of 101 byte-identical") described an
   artifact that does not exist, and nominated a `cq-*` rule as its exception —
   a rule the gate never sees. Rewritten as AC3: an all-101 hash snapshot with
   `GATED_PREFIX_RE` disabled, and **zero** WORM acks (SE-8's ack claim was
   false).
7. **P0 — a deployed cron fails open and could resurrect `AGENTS.core.md`.**
   Between merge and redeploy, `cron-compound-promote` reads the absent file as
   `""`, invents ~35 kB of phantom headroom, disables its own overflow guard, and
   may auto-PR rules into a file no loader reads. New Phase 8.
8. **P0 — the thresholds are mirrored at 13 pinned sites**, three of which live in
   the file being deleted, and two of which are live production constants. Phase 6
   would have wedged pre-commit. New Phase 6.1.
9. **P0 — phases are not commits.** Four `lefthook.yml` jobs name the sidecars in
   glob *and* argv; every boundary inside Phases 1–4 is non-committable. New
   "Commit topology" preamble.
10. **Honesty fix — the break-even argument was confounded.** The −939 B/turn
    arrow saving is available today with the split intact, so it is not a collapse
    win. The decision now rests explicitly on correctness (E1/E3/E4/E5), not bytes.
11. **The residual-sweep AC was structurally blind.** Its `--include` list
    excluded `.md`/`.txt`/`.json` (where most references live) and its regex
    missed the **brace form** — the spelling actually used in `ci.yml` and eight
    other files. Corrected sweep: **65 files, 355 hits** (the paren-only form
    found ~60). ACs cut 18 → 9.

### New considerations discovered

- The "23,000-byte harness ceiling" is not a harness limit; the phrase exists
  only inside the lint's own warning string (Correction 2).
- Four **soundness arguments** (not mere filename mentions) are keyed to the
  sidecar path set and would become false if left stale (Correction 3).
- A live Inngest cron (`cron-compound-promote.ts`) is coupled to
  `AGENTS.core.md` (Correction 4).
- ADR-140 records a hard rule the split *prevented from being written*; collapse
  unblocks it (E4).
- No ADR ever owned the split — it shipped under a spec. ADR-150 supersedes a
  spec and amends seven ADRs.
- Two files share the ADR-027 ordinal; only the `active` one is in scope.

## Overview

Issue #7012 asks a single question: **keep or collapse** the three-way
`AGENTS.{core,docs,rest}.md` change-class sidecar split. The deliverable is an
ADR produced via `/soleur:architecture create` (**shape: rich**) plus the
implementation the decision mandates.

**Decision: option (c) — collapse.** But the honest scope is narrower and
sharper than the issue body states, and the correction is the main value of this
plan:

> **The thing being retired is the CLASSIFIER, not the hook, and not the
> index/body separation.**

The split bundles two independent mechanisms that the issue conflates:

| Mechanism | What it buys | Verdict |
|---|---|---|
| **Index/body separation** — `AGENTS.md` is a slug-only pointer index re-rendered every turn; rule bodies are injected once at SessionStart | The measured **−82.5 % per-turn** win recorded for PR #3496 (24,618 B → 4,303 B per turn) | **KEEP.** Untouched by this plan. |
| **Change-class conditionality** — which of three bodies get injected, chosen by a regex classifier over the diff | 8.2–8.9 % of session-start bytes, and **negative for the majority class since day one** | **RETIRE.** |

Collapsing the three bodies into one always-loaded `AGENTS.rules.md` removes the
conditionality while preserving the per-turn win in full. It additionally
*shrinks* the per-turn cost, because the `→ core|docs-only|rest` arrow can be
dropped from all 101 pointer lines (**−939 B per turn**).

## Premise Validation

| Cited premise | Probe | Result |
|---|---|---|
| #7012 open, deferred from #7008 | `gh issue view` | HOLDS. #7008 CLOSED, #7012 OPEN. |
| Loader still branches on change-class | Read `.claude/hooks/session-rules-loader.sh` | HOLDS. `DOCS_RE` at the classifier block; `CLASSES="core"` default; four-arm `elif` chain. |
| Option (a) fall-through drops `AGENTS.docs.md` | Read the class-selection block | **CONFIRMED.** With `CHANGES` non-empty and `HAS_DOCS=HAS_CODE=HAS_INFRA=0`, `-z "$CHANGES"` is false, `>1` is false, and both single-class arms are false → `CLASSES` keeps its `core` default. `AGENTS.docs.md` is silently dropped. |
| #7013 (B_FAILOPEN) open | `gh issue view 7013` | OPEN. Its body already states 43,513 B "would REJECT immediately and wedge every commit". |
| Two prior incidents #3681, #3808 | learnings-researcher | HOLD. Both are class-fit silent-drops; see Evidence. |
| **Not cited by the issue but load-bearing:** #6138, #3792 | `gh issue list` | Both OPEN, both premised on the split. See Consequences. |

## Research Reconciliation — issue claims vs. measured

Every number below was **re-derived against this worktree**, not quoted.

| Issue #7012 claim | Measured | Verdict |
|---|---|---|
| 68 % of 80 squashed PRs multi-class | **70.0 %** (56/80) | Confirmed, +2 pp |
| 72 % of 200 commits multi-class | **72.0 %** (144/200) | Exact |
| All-three payload 43,513 B | **43,680 B** loaded (6,072 + 16,828 + 3,266 + 17,514) | +167 B drift |
| Weighted mean saving ~3,782 B / 8.7 % | **3,870 B / 8.9 %** (N=80); **3,599 B / 8.2 %** (N=200) | Confirmed within ~5 % |
| `B_ALWAYS` = 22,900 | **22,900** (lint authority); 22,973 raw `wc -c` | Both right, different measures — the lint strips `AGENTS.core.md` frontmatter (ADR-094). Cite the lint. |
| "Collapsing retires `session-rules-loader.sh` + 2 test files" | **FALSE — see below** | **Corrected** |

### Correction 1 — the loader is multi-purpose and must survive

`session-rules-loader.sh` does **eight** things. Only the first dies:

1. change-class classification + conditional sidecar concatenation → **DIES**
2. frontmatter strip before injection (ADR-094 `last_reviewed`/`review_cadence` on `AGENTS.core.md`) → **survives**
3. over-strip guard (governance-blackout detector) → **survives**
4. symlink rejection (prompt-injection defense) → **survives**
5. missing-sidecar fail-safe re-walk → **simplifies** to one file
6. rules stamp `(N of M rules)` → **survives**, simplified
7. `[session-context]` snapshot — branch / dirty / worktree / MCP roster (#5319) → **unrelated, survives untouched**
8. slim 3-field per-session manifest, **SOC 2 CC6.1/CC7.2 evidence** → **survives**, but see the `change_class` decision in Phase 4.3
9. **tmpfs-guard alarm block** — reads `TMPFS_GUARD_ALARM_FILE` / `TMPFS_GUARD_HEARTBEAT_FILE` and appends `TMPFS_ALARM_BLOCK` at the **end** of the envelope → **unrelated, survives untouched, and its position is load-bearing** (SE-9)

Deleting the hook would drop SOC 2 evidence collection and the session-context
block. The 803-line + 89-line test files are likewise **retargeted, not
deleted** — only the five `assert_class` classifier cases die.

Two further findings **independently confirm** that deleting the hook would be
wrong, and that keeping hook-based injection (rather than an `@`-import) is the
right shape:

- **The hook is the only SessionStart reader of the tmpfs alarm.**
  `scripts/tmpfs-guard.test.sh` Arm 20 asserts `TMPFS_GUARD_ALARM_FILE` /
  `TMPFS_GUARD_HEARTBEAT_FILE` defaults match between `tmpfs-guard.sh` and
  `session-rules-loader.sh`, warning that a one-sided edit *"silently disables the
  only channel by which the alarm reaches a human — the dead-channel class #6991
  exists to fix"*. Deleting the loader would look like a two-sided edit and
  actually be a one-sided kill. **Reducing the hook keeps this channel alive.**
- **ADR-094 explicitly forbids the `@`-import shape.** Its rejected-alternatives
  entry reads: *"Frontmatter on the `AGENTS.md` index → `AGENTS.md` loads raw via
  the harness `@`-import every session (unstrippable) — the YAML would leak into
  context. Frontmatter lives on `AGENTS.core.md` only."* A hook-injected,
  frontmatter-stripped `AGENTS.rules.md` satisfies ADR-094 unchanged; option
  (c-iii) would violate it. **This is the decisive reason (c-iii) is deferred,
  not chosen.**

### Correction 3 — four soundness arguments are keyed to the sidecar path set

These are not filename references; they are **security/soundness arguments whose
premise is the exact path set** `AGENTS.{core,docs,rest}.md`. Changing the paths
without updating the prose leaves a stale — and now false — safety claim:

- `.github/actions/bot-pr-with-synthetic-checks/action.yml` — the Phase-4
  preflight note argues bot PRs are safe *"ONLY because no
  `AGENTS.{core,docs,rest}.md` path is in ALLOWED_PATHS"*.
- `scripts/required-checks.txt` — the `rule-body-lint` fabricated-green soundness
  note rests on the same unreachability claim.
- `infra/github/ruleset-ci-required.tf` — required-check comments naming the
  rule-body-lint scope.
- `.github/workflows/ci.yml` — the `rule-body-lint` required job comment.

### Correction 4 — a DEPLOYED cron is coupled to `AGENTS.core.md` and fails OPEN

`apps/web-platform/server/inngest/functions/cron-compound-promote.ts` is a **live
Inngest cron running from a deployed build**, not a repo-resident script. It is
the single most dangerous item in this migration, because it fails open by
design and its failure mode is exactly the one this ADR exists to retire:

- `:548-550` — `existsSync(agentsCorePath) ? await readFile(...) : ""`. After
  merge and **before the web-platform redeploy**, the deployed build reads the
  now-absent `AGENTS.core.md` as `""`.
- `alwaysLoadedNow` then collapses from ~40 kB to ~5 kB, so the clustering prompt
  at `:557` tells the model it has ~35 kB of **phantom headroom**.
- The post-apply overflow guard at `:709` (`postBytes > MAX_ALWAYS_LOADED_BYTES`)
  compares against that falsely-low number and **never fires**.
- `TARGET_ALLOW_RE` (`:183`) still matches `^AGENTS\.core\.md$`, so the cron can
  open an auto-PR that **resurrects `AGENTS.core.md`** and writes new rules into a
  file no loader reads — a self-inflicted governance blackout (E3 class).

`scripts/compound-promote.sh:169` has the same `[[ -f … ]] &&` fail-open shape.
Both carry production threshold constants (`MAX_ALWAYS_LOADED_BYTES = 23000`,
`PROPOSE_ALWAYS_LOADED_BUDGET = 20000`) that Phase 6 must move in lockstep.
**This needs a rollout step, not just a source edit — see Phase 8.**

### Correction 2 — the "harness ceiling" is not a harness limit

`B_ALWAYS_REJECT = 23000` is described in the lint's WARN string as "the
23000-byte harness ceiling". That phrase appears **only in that string**. There
is no external Claude Code limit behind it. The lint's own comment derives it as
*"the 89-line pointer index plus the 40 `hr-*` + 1 compliance-tier bodies that
`lint-rule-ids.py` PINS to core … so 23000 = floor + small headroom"* — i.e. a
**self-imposed budget floored on what cannot be demoted**, raised 22000 → 23000
in #4599 precisely because the floor had risen above the old number.

Decisive empirical check: **70 % of sessions already inject 43,680 B today** —
1.9× the "ceiling" — with no recorded harness failure. The ceiling has been
gating the *minority* path. #7013 states the same conclusion: *"The gate
measures 53 % of reality."*

## Evidence for collapse

**E1 — the conditionality never delivered a byte saving.** PR #3496's own
measured table:

| Session class | Pre-split | Post-split | Δ |
|---|---|---|---|
| docs-only | 24,618 B | 23,842 B | **−3.2 %** |
| code/infra | 24,618 B | 26,773 B | **+8.8 %** |
| mixed (fail-closed) | 24,618 B | 28,767 B | **+16.9 %** |

Two of three classes were *worse* at first turn from day one. The mixed class
was 40 % then; it is **70–72 % now**. The conditionality has been a net
first-turn cost for the majority of sessions for its entire life.

**E2 — the byte cost of collapse is small, and must not be overstated as a win.**
Figures use the **measured merge simulation** (see "Measured merge", below).

- Collapse costs **+2,344 B once** per session (42,425 vs today's 40,081 weighted
  mean, N=200).
- Against the **majority path** — the 70–72 % of sessions that already load all
  three sidecars — the merged corpus is **1,255 B smaller** (42,425 vs 43,680),
  because deduplicating the three files' repeated `## <SECTION>` headings
  recovers more than the merge adds.

> **Honesty correction (caught at review).** An earlier draft also credited
> collapse with the **−939 B per turn** from dropping the class arrow, and
> concluded "net cheaper, break-even ≈ 2.5 turns". That is **confounded**. The
> arrow's captured class is never consumed semantically anywhere in the repo —
> `POINTER_LINE_RE`'s group is used only as a boolean discriminator, and actual
> residency is derived from *file membership*. The arrow is already-redundant
> display metadata that could be deleted **today, with the split intact**.
>
> The honest statement, which is what ADR-150 must record: **collapse costs
> ≈ +2,344 B per session against the weighted mean (and saves 1,255 B on the
> majority path), and buys the elimination of a silent-drop class. The −939 B/turn
> arrow removal is an orthogonal cleanup that collapse merely makes free.**

The decision therefore rests on **E1, E3, E4, E5 — correctness arguments** — not
on byte savings. The bytes are merely small enough not to object.

Every Soleur pipeline session runs dozens to hundreds of turns, so collapse is
**net cheaper**, not merely cheap enough. *Robustness:* if the prompt cache makes
per-turn re-render free, this argument weakens — but so does the 82.5 % claim
that justified the split, symmetrically. **Collapse wins under both accounting
models.** (Flag for deepen-plan: the per-turn re-render model is a recorded
claim, not one this plan re-measured.)

**E3 — two production incidents, both class-fit silent-drops.**
- **#3681** — `wg-plan-prescribed-skills-must-run-inline` demoted core→rest. `/work` runs on docs-only PRs; `rest` does not load there. Caught by a reviewer, not a gate.
- **#3808** — `cq-skill-description-budget-headroom` placed in `rest`; SKILL.md edits are docs-only. The rule would have been a silent no-op **on its own trigger**.

Both shipped green through `lint-rule-ids.py`, `lint-agents-rule-budget.py`, and
CI. The failure mode is the worst a governance system has: **appears enforced,
is absent.**

**E4 — the split has blocked governance from being written.** ADR-140 records a
hard rule that could not land, for two reasons *both created by the split*:
budget headroom (~100 B) **and** — quoting ADR-140 — *"**Loader-class
infeasibility (decisive):** this rule's trigger surface spans `*.tf` (→ infra →
core + rest) **and** `plugins/*/skills/*/SKILL.md` (→ docs-only → core +
docs-only). A rule that must fire on both can only live in `AGENTS.core.md`,
which has zero room; placing it in `rest` would make it a silent no-op on its own
`docs-only` trigger."*

**E5 — the class-fit verification tax is permanent and shipped.** Prose exists in
`plan`, `deepen-plan`, `compound`, `brainstorm`, `ship` SKILL.md and
`plugins/soleur/AGENTS.md` for no purpose but preventing E3. `plan/SKILL.md`
carries a `<!-- mirror: deepen-plan/SKILL.md loader-class-fit bullet — keep in
sync -->` marker: a hand-maintained duplication whose only job is to sustain the
mechanism this ADR retires.

## Options considered (for the ADR's Considered Options)

- **(a) Exclude `knowledge-base/**` from `DOCS_RE`** — **REJECTED, unsafe.**
  Confirmed by reading the class-selection block: a KB-only changeset falls
  through to the `core` default and silently drops `AGENTS.docs.md`, which holds
  exactly the rules that fire on KB edits (`cq-rule-ids-are-immutable`,
  `cq-agents-md-tier-gate`, `cq-agents-md-why-single-line`,
  `cq-skill-description-budget-headroom`, `wg-ui-feature-requires-pen-wireframe`).
  That reproduces #3681. Making (a) safe needs per-rule trigger-class
  declarations linted against the classifier — i.e. **building more of the
  mechanism whose cost is the problem.**
- **(b) Relax the inflow rules that force the `.md`** — **REJECTED.** Those rules
  are the compounding-knowledge moat. Do not degrade the asset to rescue the
  optimizer.
- **(c) Collapse to one always-loaded corpus** — **CHOSEN.**
- **(c-ii) Collapse everything back into a single `AGENTS.md`** — **REJECTED.**
  Would destroy the index/body separation and revert the per-turn cost to
  ~43 kB/turn. This is the failure mode the ADR must explicitly warn against.
- **(c-iii) Replace hook injection with an `@AGENTS.rules.md` @-import** —
  **DEFERRED, not chosen.** Attractive (harness-native, zero injection code) but
  ADR-094 frontmatter would leak raw into context, and it drops the symlink and
  over-strip defenses. Record as a future simplification contingent on moving
  freshness metadata out of frontmatter.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-150** (provisional ordinal — highest on `origin/main` is ADR-149;
`check-adr-ordinals.sh` passes; **re-verify at ship** per the ordinal-collision
gate, and if renumbered, sweep this plan + `tasks.md` for the old ordinal).

- Path: `knowledge-base/engineering/architecture/decisions/ADR-150-agents-rule-corpus-is-unconditionally-loaded.md`
- Shape: **rich** (8 sections) — must be passed explicitly, since pipeline mode
  defaults to terse. Triggers hit: **#1 cross-cutting code surface** (~60 files)
  and **#5 teeth-bearing alternatives** (a/b/c-ii/c-iii with load-bearing
  rejection rationale).
- Produced via `/soleur:architecture create`.

**There is no predecessor ADR to supersede.** The split shipped in #3493/#3496
under a *spec* (`knowledge-base/project/specs/feat-agents-md-change-class-loader/`),
never an ADR. ADR-150 therefore supersedes **a spec** and touches seven ADRs — but the
weight is uneven: **4 substantive amendments** (092, 094, 140, 116), **1
one-sentence factual fix** (070), **2 token swaps** (139, 027), and **1 no-op**
(086). Stating that split keeps the perceived governance cost honest:

| ADR | Coupling | Required action |
|---|---|---|
| **ADR-092** (body-weakening gate) | **Decision depends on the split.** Its scope is *"body lines across all three sidecars"*, and it names a **"cross-sidecar decoy (last-file-wins)"** threat class that **ceases to exist** under one corpus. | Substantive amendment + paired deletion of the collision detector in `lint-rule-bodies.py` and its test. |
| **ADR-094** (freshness clock) | **Decision names `AGENTS.core.md` specifically** — "bring `AGENTS.core.md` under the clock, funded by a frontmatter-strip". | Amend to `AGENTS.rules.md`; the strip contract itself is preserved. |
| **ADR-140** (encryption posture) | Its **"loader-class infeasibility (decisive)"** rejection rationale is **voided** — only the byte-budget half survives. | Amend the rejected-alternatives row; flag that the blocked `hr-*` rule is now writable. |
| **ADR-116** (content-anchored citations) | Reach argument stated in loader terms (*"`AGENTS.rest.md`, injected on every code/infra session"*). | Restate reach as unconditional. |
| **ADR-070** (phase tool scoping) | Cites the loader as **prior art** justifying phase-scoping; its fail-open "mirrors `session-rules-loader.sh`". | Update both citations; Decision stands. |
| **ADR-139** | Table row names the sidecar path set. | Path-set update. |
| **ADR-086** | Names the loader only as a *rejected* option and a hard-boundary rationale. | Add a superseding note; **do not rewrite its Decision.** |

### C4 views

**No C4 impact — enumeration cited.** All three model files were read
(`model.c4` 558 L, `views.c4` 62 L, `spec.c4` 54 L):

- **External human actors:** none added or changed (operator/founder unchanged).
- **External systems / vendors:** none — this is a repo-local file + hook change.
- **Containers / data stores:** the model has a `Hook Engine` container whose
  description enumerates *"phase-surface hints (ADR-070) and declarative skill
  context_queries (ADR-086)"* — it **never mentioned the rules loader**, so
  removing the classifier falsifies no description. `AGENTS.*.md` are repo files,
  not modeled data stores. Grep for `rules-loader|AGENTS|SessionStart` across all
  three `.c4` files returns **zero hits**.
- **Actor↔surface access relationships:** none change.

Optional follow-up (out of scope): the `Hook Engine` description is *incomplete*
— it omits the rules loader entirely. Pre-existing.

## Implementation Phases

### Commit topology (read this first — the phases are NOT commits)

The phases below are **work ordering**, not commit boundaries. The repo is
**non-committable** at every boundary inside Phases 1–4, because `lefthook.yml`
names the three sidecars in the **glob and the argv** of four pre-commit jobs
(`rule-ids-lint`, `agents-compound-sync`, `enforcement-tags-lint`,
`rule-budget-lint`). Concretely:

- A **Phase-1-only** commit stages three deletions that match those globs; all
  four jobs then run with argv pointing at files that no longer exist
  (`lint-agents-rule-budget.py` hard-errors `ERROR: AGENTS.core.md missing`;
  `lint_union` emits `ERROR: … not found`).
- A **Phase-2-only** commit strips the arrow while `POINTER_LINE_RE` still
  *requires* it → every pointer line reads as a body → 101 orphan-body errors.
- Phase 6's constants must move too: `B_ALWAYS_REJECT = 23000` hard-`[REJECT]`s a
  42.4 kB corpus.

> **Phases 1, 2, 3, 4, and 6 are ONE atomic commit.** Phase 5 (prose) and Phase 7
> (citations) may be separate commits. Phase 8 (ADR + issue disposition) is
> separate. Within the big commit, land the ADR-092 collision-detector deletion
> (Phase 3.2) as its **own** commit if you can keep the tree green — it is a
> safety-net removal and deserves a reviewable standalone diff.

Phase order still matters *within* that commit: build the corpus before
retargeting consumers, and never leave `SIDECARS` pointing at a file the same
commit deleted (SE-1).

### Phase 0 — Preconditions & baseline capture
1. `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>&1` — record the `[WARN]`/`[OK]` verdict verbatim (`2>&1` load-bearing: verdicts go to stderr).
2. `python3 scripts/lint-rule-bodies.py --write` then **snapshot `.claude/rule-body-hashes.txt`** to a scratch path. This is the **body-identity baseline** for AC4.
3. Record the 101 rule ids in `AGENTS.md` pointer order.
4. `bash scripts/test-all.sh` baseline (or the AGENTS-scoped suites) so pre-existing reds are known.

### Phase 1 — Build the merged corpus (same commit as 2, 3, 4, 6)
1. Create `AGENTS.rules.md` by **section-wise union** of `AGENTS.core.md` +
   `AGENTS.docs.md` + `AGENTS.rest.md`. Concatenation is **wrong** — the three
   files each carry `## Workflow Gates` / `## Code Quality` headings and duplicate
   `## <SECTION>` headings break the `SECTIONS`-oracle parse shared by
   `lint-rule-bodies.py`, `lint-agents-enforcement-tags.py`, and
   `lint-agents-rule-budget.py`.
2. Within each section, order rule bodies to match `AGENTS.md` pointer order.
3. Carry `AGENTS.core.md`'s ADR-094 frontmatter (`last_reviewed`,
   `review_cadence`, `owner`) onto `AGENTS.rules.md` **verbatim**.
4. New H1: `# AGENTS Rules — the whole corpus, loaded every session`.
5. `git rm` the three sidecars **with `-M` rename detection preserved** where git
   allows (core → rules is the natural rename).

**Invariant:** rule **ids** and rule **body text** are untouched
(`cq-rule-ids-are-immutable`). This is a file move + heading merge, nothing else.

#### Pre-validation already performed at plan time (read-only, in scratch)

The merge was **simulated and run against the real lints** before this plan was
frozen. The implementer should expect exactly these results, and treat any
deviation as a signal that the merge diverged from the simulation:

| Check | Result | Meaning |
|---|---|---|
| Merged corpus rule-line count | **101** | Lossless — equals the pointer count exactly |
| `lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` | **exit 2**, `ERROR: AGENTS.core.md missing — refusing to compute B_ALWAYS` | The lint **fails closed** on the literal filename. Phase 3.3 is a hard prerequisite — the budget cannot even be measured until `ALWAYS_LOADED` is retargeted. |
| `lint-rule-ids.py … AGENTS.md AGENTS.rules.md` | **exit 1, exactly 2 error lines** | Both are the core-pinning checks: `[compliance-tier] rule(s) outside AGENTS.core.md` (**5** ids) and `hr-* rule(s) outside AGENTS.core.md` (**45** ids). |
| Pointer / orphan / union errors | **zero** | The arrow-stripped index and the merged bodies satisfy `lint_union` cleanly. |

The last two rows **empirically confirm SE-4**: the only `lint-rule-ids.py`
failures are the two checks Phase 3.1 deletes, and they fail for all 50
pinned ids at once — precisely because the pin has become meaningless. *Caveat:
the pointer-shape regex may be exercised on a code path this simulation did not
reach; re-verify at /work rather than assuming zero pointer errors.*

### Phase 2 — Retarget the pointer index
1. Strip ` → core` / ` → docs-only` / ` → rest` from all **101** pointer lines in
   `AGENTS.md` (−939 B per turn).
2. Update the AGENTS.md preamble (it currently reads *"bodies in
   `AGENTS.{core,docs,rest}.md`, injected per change-class by the SessionStart
   hook (multi-class/empty → all, fail-closed)"*) to describe unconditional
   loading.

### Phase 3 — Lints (contract owners; must move with the corpus)
1. **`scripts/lint-rule-ids.py`** — pointer regex drops the
   `→ (core|docs-only|rest)` arm; retarget the file list. **Delete** the
   `hr-*`-must-live-in-core and `[compliance-tier]`-must-live-in-core checks:
   with one corpus they become **structurally unfailable**. Do not leave a
   vacuous green gate (repo precedent: "close six vacuity holes review proved
   were shipping green"). Record in the ADR that the invariant they enforced
   ("`hr-*` always loads") is now **true by construction**.
2. **`scripts/lint-rule-bodies.py`** — `SIDECARS = ("AGENTS.rules.md",)`; second
   copy of the pointer-arrow regex loses its class arm; **delete the
   cross-sidecar collision detector** in `build_body_map()` and its head/base
   fail-closed error paths — the "cross-sidecar decoy" threat class is
   structurally impossible with one corpus (paired ADR-092 amendment).
   ⚠️ See Sharp Edge SE-1.
3. **`scripts/lint-agents-rule-budget.py`** — `ALWAYS_LOADED = ("AGENTS.md",
   "AGENTS.rules.md")`; re-baseline `B_ALWAYS_WARN` / `B_ALWAYS_REJECT` per
   Phase 6; rewrite the remediation string (the "demote a `wg-*` to
   `AGENTS.rest.md`" rung no longer exists).
4. **`scripts/lint-agents-compound-sync.sh`** — ⚠️ **SE-8.** It hardcodes
   `AGENTS.docs.md` as the site of the warn/critical/per-rule-cap sentinel, and
   the sentinel line itself lives in `AGENTS.docs.md` (the `<!-- rule-threshold:
   115 -->` marker inside `cq-agents-md-why-single-line`). The sentinel and its
   reader **must move in the same commit** or pre-commit wedges.
5. **`scripts/lint-agents-enforcement-tags.py`**, `scripts/_agents_md_sections.py`,
   `scripts/compound-promote.sh` (its `AGENTS_CORE` const + proposer prompt +
   `target_path MUST be one of` allow-list), `scripts/kb-drift-walker.sh`
   (`SOURCES` array) — retarget file lists.
   *`scripts/rule-metrics-aggregate.sh` parses `AGENTS.md` only — **no edit
   needed**.*
6. **`lefthook.yml`** — four glob blocks name the three sidecars; collapse to
   `AGENTS.md` + `AGENTS.rules.md`.
7. **`scripts/test-all.sh`** — the two live-lint invocations pass all four files.
8. **Production code:** `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
   — `TARGET_ALLOW_RE`, `measureFileStrippedBytes(…, "AGENTS.core.md")`, the
   `join(repoRoot, "AGENTS.core.md")` read, the proposer prompt, and the
   `cluster.target_path === "AGENTS.core.md" && diffRemovesHardRule(…)` guard.
   Plus its three test files.

### Phase 4 — Reduce the hook
1. Delete from `.claude/hooks/session-rules-loader.sh`: `DOCS_RE`/`CODE_RE`/`INFRA_RE`,
   the `HAS_*` loop, the `CLASSES` selection chain, the class loop, the
   `LOADER_FAIL_CLOSED` escape hatch, and the `HINT` line that documents it.
2. **Keep**: frontmatter strip, over-strip guard, symlink rejection, single-file
   fail-safe, stamp, `[session-context]` snapshot, SOC 2 manifest, **and the
   tmpfs-guard alarm block** (job #9 — omitted from an earlier draft's Keep list,
   which would have licensed an implementer to drop it; SE-9).
2a. ⚠️ **The envelope has a positional line contract.** `OUT_BODY` is
   STAMP(1) / HINT(2) / manifest(3) / `[session-context]`(4-6) / bodies, and the
   tmpfs block is appended **last**. Three test arms assert this by line number
   (`sed -n '4p'/'5p'/'6p'`, a `sed -n '7p'`, and the tmpfs arm's `al4/al5/al6`),
   plus a `head -3` stamp-byte budget. **Deleting the HINT line shifts everything
   up by one and reds all of them.** Either keep a one-line placeholder or move
   the offsets to 3-5 **and** update all four assertions in the same commit.
3. Stamp becomes `[rules-loader] loaded: 101 of 101 rules`. **Not vacuous** — the
   numerator still detects a truncated or corrupt corpus, which is the
   governance-blackout signal. State this in the ADR so review does not flag it.
   ⚠️ Test 27 (`docs-only class → numerator < denominator`) is **class-dependent
   but is not one of the five `assert_class` cases**. Under one corpus the
   numerator always equals the denominator on the happy path, so **retarget it to
   a truncated-corpus fixture** rather than deleting it — it is the arm that
   proves the numerator is not vacuous, which this very step promises to defend.
3a. **Decide the SOC 2 manifest's `change_class` field.** The hook writes
   `{timestamp, change_class, rule_ids_loaded}` where the value is `$CLASSES`,
   which Phase 4.1 deletes. The 3-field shape is pinned in two places: an exact
   key-set assertion in `session-rules-loader.test.sh` and the "three fields"
   prose in `.claude/hooks/README.md`. This is a **schema change to a CC6.1/CC7.2
   evidence record** — the very surface `## User-Brand Impact` names. **Decision:
   pin the value to the constant `"all"`** rather than dropping the key: it keeps
   the evidence schema stable for any historical-manifest reader, keeps the test's
   key-set assertion green, and honestly states that every session now loads the
   whole corpus. Update the README prose to match.
4. Consider renaming the hook to reflect its real job. **Deferred** — a rename
   touches `.claude/settings.json`, `hookeventname-coverage.test.sh`, ADR-070,
   ADR-086, ADR-116 and buys nothing this PR needs. Keep the filename.
5. **Delete** `tests/scripts/test_classifier_regex_parity.sh` and
   `tools/migration/classify-rules.sh` — both exist solely to assert
   classifier-regex parity. Unwire from `scripts/test-all.sh:338`.
   `tools/migration/split-sidecars.sh` is the one-shot migration script for the
   split being retired — delete.
6. Retarget `.claude/hooks/session-rules-loader.test.sh` (803 L): delete the five
   `assert_class` cases; retarget Test 27 per 4.3; fix the positional offsets per
   4.2a; **keep** manifest, session-context, symlink, over-strip, stamp-byte,
   tmpfs-alarm, and path-traversal coverage.
   **`session-rules-loader-headless.test.sh` needs NO edit** — verified: its
   "classifier" is the `HEADLESS_MODE` boolean
   (`[[ ! -t 0 ]] && [[ -n "${CLAUDECODE:-}" ]]`), not the change-class
   classifier. It contains zero change-class references.

### Phase 5 — Teaching surfaces (the class-fit tax)

**Delete entirely (100 % class-fit prose, ~6.7 kB of shipped instruction):**
- `plugins/soleur/skills/plan/SKILL.md` — the `<!-- mirror: … -->` marker, the
  loader-class-fit bullet (~1,311 chars), and the `core→rest` demotion bullet
  (~1,154 chars).
- `plugins/soleur/skills/deepen-plan/SKILL.md` — the twin marker and its verbatim
  checklist twin (~1,190 chars).
- `plugins/soleur/skills/compound/SKILL.md` — the demotion rung of the shrink
  ladder (~470 chars). **The ladder loses one of its rungs; say so in the ADR.**
- `plugins/soleur/AGENTS.md` — the dedicated 6-line paragraph explaining that
  `AGENTS.*.md` are change-class sidecars, not plugin components.
- `.claude/hooks/README.md` — the entire `## Change-class loader (#3493)` section
  (~56 lines), **except** the manifest/SOC-2 and SessionStart-hook-design Sharp
  Edges subsections, which describe surviving behavior and must be **retained and
  retargeted**.

**Rewrite (mixed — the budget mandate survives, the class model does not):**
- `plan/SKILL.md` B_ALWAYS-headroom bullet — keep the "measure before adding a
  rule" mandate and the `2>&1` discipline; drop the four-file arg list and the
  "prescribe a `wg-*`→rest demotion" escape valve.
- `compound/SKILL.md` — the B_TOTAL-vs-B_ALWAYS mental model ("*cross-class
  sidecars add to first-turn cost when their class fires*") is now false;
  `B_TOTAL == B_ALWAYS`. Also the four-file linter invocations and the `#7008`
  double-count caveat, which becomes obsolete.
- `brainstorm/SKILL.md` — the count-discipline lesson is generic and survives, but
  its lead exemplar is the loader's own `(101 of 202 rules)` denominator bug.
  Retag as historical or swap the example.

**Pointer-only updates:** `ship/SKILL.md`,
`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`,
`knowledge-base/project/constitution.md`,
`knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md`,
`knowledge-base/kb-tags.txt` (retire the `agents-md-sidecar*`,
`loader-class-fit`, `session-rules-loader` facets or mark historical).

**User-visible block strings** (these render to the operator, so stale text is
operator-facing): `.claude/hooks/no-memory-write.sh` (+ its test asserting
`"Source: AGENTS.core.md"`), `.claude/hooks/background-poll-prefer-monitor.sh`,
`.claude/hooks/iac-plan-write-guard.sh`.

**No edit:** `review/SKILL.md`, `knowledge-base/engineering/grok-onboarding.md`,
`knowledge-base/INDEX.md` (see Files to Edit).

**Do not** simply delete the budget check — `B_ALWAYS` still exists and still
gates; only its *composition* and *remediation ladder* change.

### Phase 6 — Re-baseline the budget, honestly

**Measured merge (simulated read-only at plan time — re-verify at /work):**

| Quantity | Value |
|---|---|
| `AGENTS.rules.md` raw | **37,365 B** |
| `AGENTS.rules.md` frontmatter-stripped (what the lint measures) | **37,292 B** |
| Rule lines in the merged corpus | **101** — lossless, matches the pointer count exactly |
| `AGENTS.md` with class arrows stripped | **5,133 B** |
| **New `B_ALWAYS`** | **42,425 B** |
| vs today's all-three payload (43,680 B) | **−1,255 B** |
| vs today's weighted mean (40,081 B) | **+2,344 B (+5.8 %)** |

Merged section order (7 sections, deduplicated): Hard Rules · Workflow Gates ·
Compliance Tier · Passive Domain Routing · Communication · Code Quality ·
Review & Feedback.

Set `B_ALWAYS_WARN` / `B_ALWAYS_REJECT` above the measured 42,425 B with a stated
margin. **Do not present the margin as derived** — Correction 2 attacks `23000`
precisely for being an unprincipled "floor + small headroom" number, and
inventing new percentages repeats the sin. Write one honest sentence: *"a ratchet
against unreviewed growth, not an external limit; the margin is a judgment
call."* Record that the shrink ladder has lost its demotion rung and now offers
only **trim prose / retire a rule** — and that per #6794 the rule-retirement rung
is not currently actionable either (SE-7).

#### 6.1 ⚠️ The thresholds are mirrored at THIRTEEN pinned sites

`scripts/lint-agents-compound-sync.sh` treats `lint-agents-rule-budget.py` as the
authority and **hard-fails at pre-commit** on any site that disagrees. Its
`SITES` table pins:

| File | Anchor | Symbol |
|---|---|---|
| `cron-compound-promote.ts` | `^const MAX_ALWAYS_LOADED_BYTES = (\d+);` | REJECT |
| `cron-compound-promote.ts` | `^const PROPOSE_ALWAYS_LOADED_BUDGET = (\d+);` | WARN |
| `scripts/compound-promote.sh` | `^ALWAYS_LOADED_CAP=(\d+)` | REJECT |
| `scripts/compound-promote.sh` | `^PROPOSE_ALWAYS_LOADED_BUDGET=(\d+)` | WARN |
| `AGENTS.docs.md` | `(\d+) warn` · `(\d+) critical` · `cap at ~(\d+) bytes` | ×3 |
| `plan/SKILL.md` | `(\d+)-byte critical cap` · `per-rule (\d+)-byte cap` | ×2 |
| `compound/SKILL.md` | `cap per-rule length at ~(\d+)` | PER_RULE_CAP |
| `grok-fidelity-gate.sh` | `B_ALWAYS <= (\d+)` | REJECT |
| `compound-promote-runbook.md` | `B_ALWAYS >= (\d+)` · `reject above .(\d+).` | ×2 |

Three consequences the plan must handle:

1. **Three rows name `AGENTS.docs.md`**, which this PR deletes. Those rows must be
   repointed at `AGENTS.rules.md` — and the sentinel-bearing rule body
   (`cq-agents-md-why-single-line`) must carry the new literals. It has only
   **6 bytes of headroom** against `PER_RULE_CAP = 600` (594 B today), so the
   rewrite must be net-shorter (SE-12).
2. **Phase 5's prose rewrites can wedge the gate.** If a rewrite drops the exact
   phrasing an anchor matches, the gate errors *"no match … extraction is
   vacuous, refusing to pass"*. `plan/SKILL.md`, `compound/SKILL.md`, and
   `compound-promote-runbook.md` are edited in Phase 5 **and** are threshold
   sites. Keep the anchor phrasings intact.
3. **`MAX_ALWAYS_LOADED_BYTES` is a live production guard, not a mirror.**
   Raising it ~23,000 → ~46,000 genuinely loosens the deployed cron's post-apply
   overflow check. This needs its own one-line rationale in the ADR — "the
   measurement got honest" does **not** cover it, because the cron measures
   `AGENTS.md + core` only, never the whole corpus. State plainly that the guard
   is being re-scoped to the new always-loaded quantity.

> **Framing for review:** the number rises because the *measurement got honest*,
> not because the budget got loose.

### Phase 7 — Citations, ownership, cross-refs
0. **Update the four path-set soundness arguments (Correction 3)** — these are
   safety claims, not filename mentions. Leaving them stale ships a false claim:
   `.github/actions/bot-pr-with-synthetic-checks/action.yml` (ALLOWED_PATHS
   unreachability), `scripts/required-checks.txt` (fabricated-green note),
   `infra/github/ruleset-ci-required.tf`, `.github/workflows/ci.yml`
   (`rule-body-lint` scope comment).
1. `.github/CODEOWNERS` — three sidecar lines → one `AGENTS.rules.md`.
2. Sweep `AGENTS.core.md <rule-id>` **comment citations** in
   `infra/github/main.tf`, `infra/github/variables.tf`,
   `apps/web-platform/infra/main.tf`, `infra/github/README.md`. **These are
   comments only — no Terraform resource keys on the filenames, so no
   `terraform apply` is required.** (Verified: the only `.tf` hits are prose
   citing `hr-github-app-auth-not-pat`.)
3. Amend ADR-094; add cross-references in ADR-070, ADR-086, ADR-092, ADR-116,
   ADR-139, ADR-140 where they name the sidecars.
   ⚠️ **Two files share the ADR-027 ordinal** (tolerated by
   `check-adr-ordinals.sh` because one is `status: superseded`). The sidecar
   reference is in **`ADR-027-stateless-self-modifying-cron.md`** (`status:
   active`), **not** `ADR-027-process-local-state-for-runners.md` (superseded,
   zero sidecar hits). Edit the active one only.
4. `apps/web-platform/**` test/source references; `plugins/soleur/test/*.test.ts`;
   `.github/workflows/review-reminder.yml` + `scripts/review-reminder-liveness.test.sh`
   (`required_paths=("AGENTS.core.md")` → `AGENTS.rules.md`);
   `.github/actions/bot-pr-with-synthetic-checks/action.yml`;
   `.github/workflows/apply-github-infra.yml`;
   `.github/scripts/test/test-check-pr-body-vs-diff.sh`;
   `.claude/hooks/{background-poll-prefer-monitor,iac-plan-write-guard,no-memory-write}.sh`
   + `no-memory-write.test.sh`; `plugins/soleur/scripts/grok-fidelity-gate.sh`;
   `scripts/lint-infra-no-human-steps.py`; `scripts/lib/frontmatter-strip/SPEC.md`;
   `scripts/lib/rule-line-regex-parity.test.sh`; `scripts/tmpfs-guard.test.sh`;
   `knowledge-base/kb-tags.txt`; `tests/scripts/test_lint_rule_ids.py`;
   `tests/scripts/test_lint_rule_bodies.py`; `tests/scripts/test-kb-drift-walker.sh`;
   `scripts/lint-agents-*.test.sh`; `scripts/compound-promote.test.sh`.

> **Do NOT sweep** `knowledge-base/project/{plans,specs,brainstorms,learnings}/**`
> or any `**/archive/**` — those are point-in-time records that must keep the old
> paths (same carve-out as the path-rename-sweep rule). This plan and its
> `tasks.md` are themselves excluded from any residual-zero AC.

### Phase 8 — Deployed-cron rollout (Correction 4)

The `compound-promote` Inngest cron runs from a **deployed** build. Source edits
in Phase 3.8 do not take effect until the web-platform redeploy, and in the gap
the deployed build fails open (Correction 4). Required steps:

1. **Before merge:** check for an in-flight compound-promote auto-PR
   (`gh pr list --search 'compound-promote in:title' --state open`). If one
   exists, let it merge or close it first — it will conflict on a deleted file
   and its target path is about to become invalid.
2. **At merge:** the `web-platform-release.yml` pipeline redeploys on any merge
   touching `apps/web-platform/**`, and Phase 3.8 edits that path — so the
   redeploy is automatic. **Verify it ran**, do not assume.
3. **Harden the fail-open** in the same edit: change the two
   `existsSync(...) ? readFile(...) : ""` sites so a missing corpus is a **loud
   failure**, not a 0-byte reading. A governance instrument that under-reports its
   own input is the exact defect class #7008 fixed in the loader's stamp.
4. **Retarget `TARGET_ALLOW_RE`** so `AGENTS.core.md` is no longer an allowed
   write target — otherwise the cron can resurrect a file no loader reads.
5. Apply the same fail-open hardening to `scripts/compound-promote.sh`.

### Phase 9 — Issue disposition
- **#7013** (B_FAILOPEN reporting) — **close as obsolete.** `B_FAILOPEN` exists
  only because the loader can fail open across three sidecars. One corpus, no
  fail-open. **Do NOT implement it here** (per scope).
- **#6138** (shrink `B_ALWAYS` below 22 k) — **close / re-scope.** Its whole
  remediation ladder is "demote `wg-*` core→rest", which no longer exists, and
  its target is now unreachable by construction.
- **#3792** (path-scoped `AGENTS.<lang>.md` files) — **close as superseded.** Its
  re-evaluation criteria require *"clear ROI on path-glob extension vs. the
  current change-class classifier"*; the measured 8.2–8.9 % is evidence against
  that ROI, and it is explicitly premised on extending the classifier.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-150-agents-rule-corpus-is-unconditionally-loaded.md`
- `AGENTS.rules.md`
- `knowledge-base/project/specs/feat-one-shot-7012-agents-sidecar-collapse-adr/tasks.md`

## Files to Delete

- `AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md`
- `tests/scripts/test_classifier_regex_parity.sh`
- `tools/migration/classify-rules.sh`, `tools/migration/split-sidecars.sh`

## Files to Edit

`AGENTS.md` · `.claude/hooks/session-rules-loader.sh` ·
`.claude/hooks/session-rules-loader.test.sh` ·
`.claude/hooks/README.md` ·
`.claude/hooks/{background-poll-prefer-monitor,iac-plan-write-guard,no-memory-write}.sh` ·
`.claude/hooks/no-memory-write.test.sh` · `.claude/hooks/hookeventname-coverage.test.sh` ·
`lefthook.yml` · `.github/CODEOWNERS` ·
`scripts/lint-rule-ids.py` · `scripts/lint-rule-bodies.py` ·
`scripts/lint-agents-rule-budget.py` · `scripts/lint-agents-enforcement-tags.py` ·
`scripts/_agents_md_sections.py` · `scripts/lint-agents-compound-sync.sh` ·
`scripts/compound-promote.sh` ·
`scripts/kb-drift-walker.sh` · `scripts/lint-infra-no-human-steps.py` ·
`scripts/test-all.sh` · `scripts/review-reminder-liveness.test.sh` ·
`scripts/lib/frontmatter-strip/SPEC.md` ·
`scripts/{lint-agents-rule-budget,lint-agents-compound-sync,lint-agents-enforcement-tags,compound-promote}.test.sh` ·
`tests/scripts/{test_lint_rule_ids.py,test_lint_rule_bodies.py,test-kb-drift-walker.sh}` ·
`plugins/soleur/skills/{plan,deepen-plan,compound,brainstorm,ship}/SKILL.md` ·
`plugins/soleur/AGENTS.md` ·
`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` ·
`plugins/soleur/scripts/grok-fidelity-gate.sh` ·
`plugins/soleur/test/{workflow-fidelity,observability-schema-parity,mandatory-wireframes-hardening,ship-undeferred-operator-step-gate}.test.ts` ·
`apps/web-platform/server/inngest/functions/cron-compound-promote.ts` ·
`apps/web-platform/test/server/inngest/{cron-compound-promote,rule-body-gate-recursion-invariant}.test.ts` ·
`apps/web-platform/test/server/internal/kb-drift-ingest-route.test.ts` ·
`apps/web-platform/infra/main.tf` · `infra/github/{main.tf,variables.tf,README.md}` ·
`.github/workflows/{review-reminder,apply-github-infra}.yml` ·
`.github/actions/bot-pr-with-synthetic-checks/action.yml` ·
`.github/scripts/test/test-check-pr-body-vs-diff.sh` ·
`knowledge-base/project/constitution.md` ·
`knowledge-base/kb-tags.txt` ·
`knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` ·
`knowledge-base/engineering/architecture/decisions/{ADR-027,ADR-070,ADR-086,ADR-092,ADR-094,ADR-116,ADR-140}*.md`

Additionally (from the second, independent inventory pass):
`scripts/required-checks.txt` · `infra/github/ruleset-ci-required.tf` ·
`.github/workflows/ci.yml` · `scripts/rule-metrics-aggregate.test.sh` ·
`scripts/lint-agents-compound-sync.sh` (sentinel site table) ·
`knowledge-base/project/specs/feat-agents-md-change-class-loader/{spec,tasks}.md`
(mark superseded — do **not** rewrite; it is a historical record) ·
`knowledge-base/engineering/architecture/decisions/ADR-139*.md`

**No edit needed** (verified, listed to prevent a sweeper churning them). These
were removed from the edit list above at review — an earlier draft listed each in
**both** places:

- `scripts/rule-metrics-aggregate.sh` — parses `AGENTS.md` only, zero sidecar refs
- `plugins/soleur/skills/review/SKILL.md` — its one `docs-only` hit is unrelated prose about legal-disclosure review
- `knowledge-base/engineering/grok-onboarding.md` — zero hits
- `knowledge-base/INDEX.md` — hits are auto-generated learning titles
- `plugins/soleur/hooks/hooks.json` — no loader registration
- `.claude/hooks/session-rules-loader-headless.test.sh` — its "classifier" is the `HEADLESS_MODE` boolean
- `.claude/rule-weakening-acks.txt` — **zero acks required** (SE-8); do not append
- `scripts/retired-rule-ids.txt`, `.claude/rule-body-hashes.txt` — path-independent and unchanged (see Rollback)
- `scripts/lib/rule-line-regex-parity.test.sh` — pins only `^- .*\[id: `; the class arrow is not in its parity set
- `scripts/tmpfs-guard.test.sh` — references the hook **by path only**, and Phase 4 keeps the filename (it is a regression check, not a migration target)
- `.github/scripts/test/test-no-at-mention-credfile-footgun.sh` — globs `AGENTS.*.md`, auto-follows
- all three `.c4` files · `model.c4`'s `skillloader` container (that is the **plugin** loader — a different thing; do not touch)

**Authoritative inventory command** (the AC6 sweep — run this at /work rather than
trusting the list above, which is a floor):

```bash
git grep -lE 'AGENTS\.(\{core,docs,rest\}|core|docs|rest)\.md' -- . \
  ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' \
  ':!knowledge-base/project/brainstorms' ':!knowledge-base/project/learnings' \
  ':!**/archive/**'
```

Measured at plan time: **65 files, 355 hits.** An earlier paren-only regex
(`AGENTS\.\(core\|docs\|rest\)\.md`) reported ~60 files — it silently missed the
**brace form** `AGENTS.{core,docs,rest}.md`, which is the spelling actually used
in `ci.yml`, `required-checks.txt`, `ruleset-ci-required.tf`,
`bot-pr-with-synthetic-checks/action.yml`, `no-memory-write.sh`,
`kb-drift-walker.sh`, `lint-rule-bodies.py`, `AGENTS.md` itself, and three ADRs.
**ADR-070 and ADR-139 entered this plan only because a human spotted them** — the
mechanical sweep missed both. A third form, `AGENTS.{md,core.md,docs.md,rest.md}`,
also exists.

## Acceptance Criteria — Pre-merge (PR)

Nine criteria. Earlier drafts carried eighteen; the cuts are recorded under
"Cut ACs" below so a reviewer can see they were considered, not overlooked.

- **AC1** `AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md` do not exist; `AGENTS.rules.md` does, and contains exactly **101** `^- …[id: …]` rule lines (lossless merge; matches the plan-time simulation).
- **AC2** `python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.rules.md` exits 0. Pointer↔body stays **1:1 at 101**. *(Subsumes the old AC6: once the arrow arm is dropped from `POINTER_LINE_RE`, an arrow-bearing line stops matching and the count breaks.)*
- **AC3 (load-bearing — the compensating control for SE-1)** **Full-corpus body identity.** `lint-rule-bodies.py`'s committed manifest covers only **74** rules — `GATED_PREFIX_RE = ^(hr|wg)-` — so it proves nothing about the **27** `cq-*`/`rf-*`/`pdr-*`/`cm-*` bodies. Since SE-1 knowingly blinds the ADR-092 gate for exactly one commit, the compensating proof must cover **all 101**:
  1. At Phase 0, run a throwaway script that reuses `lint-rule-bodies.py`'s own body-parse + normalization with `GATED_PREFIX_RE` **disabled**, emitting an ordered `(id → sha256(normalized body))` snapshot over all 101 rules.
  2. Re-run post-merge and diff.
  3. **Every id whose hash changes must be enumerated at Phase 0 and justified** — do not hardcode a count. Expected: only `cq-agents-md-why-single-line` (its body states the retired architecture) and possibly `cq-agents-md-tier-gate`.
  4. The 74-entry manifest comparison remains a subordinate check.
  > **Do not** budget a WORM ack for `cq-agents-md-why-single-line`: it is `cq-*`, so `lint-rule-bodies.py` never sees it and no ack is possible or required. Acks are only needed if an `hr-*`/`wg-*` body changes — which it should not.
- **AC4** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` exits 0 with `[OK]`.
- **AC5** `bash scripts/lint-agents-compound-sync.sh` exits 0 — i.e. **all 13 threshold-mirror sites** agree with the new constants (Phase 6). This is the AC that catches a partial threshold rollout.
- **AC6** Residual-reference sweep returns zero. Both spellings, all text types, with the historical-record carve-out:
  ```bash
  git grep -nE 'AGENTS\.(\{core,docs,rest\}|core|docs|rest)\.md' -- . \
    ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' \
    ':!knowledge-base/project/brainstorms' ':!knowledge-base/project/learnings' \
    ':!**/archive/**'
  ```
  `git grep` is used deliberately: it is tracked-files-only (no `node_modules` prune needed) and type-agnostic (the old `--include` list silently excluded `.md`/`.txt`/`.json`, which is where most residual references live). *(Subsumes the old AC14 — the brace form is now covered by the same alternation.)*
- **AC7** `grep -c 'LOADER_FAIL_CLOSED\|DOCS_RE\|CODE_RE\|INFRA_RE' .claude/hooks/session-rules-loader.sh` returns **0**, and the manifest/session-context/tmpfs-alarm test cases **still exist** in `session-rules-loader.test.sh` (a deleted assertion passes a green suite silently).
- **AC8** `bash scripts/test-all.sh` green, with the classifier-parity suite unwired and no other suite newly red vs. the Phase-0 baseline.
- **AC9** `ADR-150-*.md` exists and `bash scripts/check-adr-ordinals.sh` passes, with no ordinal collision against a freshly-fetched `origin/main`.

**Cut ACs (considered, deliberately dropped):** ordered-id-list equality (cosmetic, and unsatisfiable as-is — see SE-11); "threshold comment contains four facts" (unfalsifiable by command); arrow-count grep (subsumed by AC2); separate `tmpfs-guard.test.sh` and compound-sync invocations (both already inside `test-all.sh`); "ADR is rich shape / names options / records dispositions" (prose paraphrase no gate checks); `Closes #7012` (a standing repo gate, `wg-use-closes-n-in-pr-body-not-title-to`); "settings.json still registers SessionStart" (asserts the absence of a change nobody proposed — SE-10 prose covers it).

## Sharp Edges

- **SE-1 (blocking if unhandled) — the ADR-092 weakening gate goes blind across this migration.**
  `lint-rule-bodies.py:391` builds its base-side map as
  `{name: _git_show(root, base, name) for name in SIDECARS}` using the
  **head-side** `SIDECARS` constant. Once Phase 3 sets
  `SIDECARS = ("AGENTS.rules.md",)`, `git show <base>:AGENTS.rules.md` returns
  `None` → base map **empty** → zero changes/deletions detected → the gate passes
  **vacuously**. It will *not* block, but it is *not checking* either.
  Conversely, flipping the file move and the `SIDECARS` edit into different
  commits makes every `hr-*`/`wg-*` body read as `DELETED` and demands ~74 WORM
  ack lines.
  **Resolution: keep the file move and the `SIDECARS` edit in the SAME commit,
  and satisfy AC4** — the body-hash identity proof is what actually verifies no
  rule was weakened in transit. Call this out explicitly in the PR body so review
  does not mistake the vacuous pass for a real one.

- **SE-2 — section-wise union, not concatenation.** The three sidecars carry
  overlapping `## <SECTION>` headings. Naive `cat` produces duplicate headings,
  which corrupts the shared `SECTIONS`-oracle parse used by three separate lints.

- **SE-3 — do not collapse the index into the body.** Merging `AGENTS.md` itself
  into the corpus reverts the −82.5 % per-turn win and is the one variant of
  "collapse" that makes things worse. The ADR must say so in as many words.

- **SE-4 — `lint-rule-ids.py`'s core-pinning checks must be deleted, not
  retargeted.** Retargeting them to `AGENTS.rules.md` yields a check that cannot
  fail. The repo has an explicit anti-vacuity posture.

- **SE-5 — ADR-094 frontmatter must ride along.** `AGENTS.core.md` carries
  `last_reviewed`/`review_cadence`/`owner`, and
  `.github/workflows/review-reminder.yml` + `scripts/review-reminder-liveness.test.sh`
  assert `required_paths=("AGENTS.core.md")`. Dropping the frontmatter or missing
  the workflow retarget silently darks the freshness tripwire.

- **SE-6 — the `.tf` hits are prose, but NOT all of them are comments.**
  *(Corrected at review — an earlier draft claimed "all hits are comments"; that
  is false.)* Two of three are `#` comments (`infra/github/main.tf`,
  `apps/web-platform/infra/main.tf`). The third,
  **`infra/github/variables.tf`, is a Terraform `description` ATTRIBUTE** — real
  configuration that lands in plan output. The conclusion survives (variable
  descriptions are metadata; **no `apply` is required** and the Phase 2.8 IaC gate
  does not fire), but the premise does not. Consequence:
  `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json` has that description
  **baked into it** and is consumed by `tests/scripts/test-destroy-guard-counter.sh`.
  **Decision: leave the fixture as a point-in-time capture and say so in the PR
  body** — it is a recorded baseline of a past plan, not a live assertion about
  current prose. Re-capturing it would churn an unrelated destroy-guard baseline.

- **SE-7 — rule telemetry cannot justify retirements.** Per #6794, the
  `rules_unused_over_8w` metric is a per-worktree fragmentation under-count. Do
  **not** use it to trim the corpus as part of this PR.

- **SE-8 — the compound-sync coupling is in the SITES table, not the sentinel
  reader.** *(Mechanism corrected at review.)* The sentinel **reader** is
  location-tolerant: it globs `"$ROOT"/AGENTS*.md` and breaks on first match, so
  it auto-follows to `AGENTS.rules.md` with **no functional edit**. What is
  actually hardcoded is the `SITES` table's three `AGENTS.docs.md|…` rows —
  see Phase 6.1. The rule body `cq-agents-md-why-single-line` still must be
  rewritten (it states the retired architecture and carries the threshold
  literals), but **it needs NO ADR-092 WORM ack**: it is a `cq-*` rule and
  `lint-rule-bodies.py` gates only `^(hr|wg)-`. **The correct ack count for this
  migration is ZERO.** Verified: no `hr-*`/`wg-*` body mentions the sidecars at
  all, so `.claude/rule-weakening-acks.txt` should not be edited.

- **SE-11 — AC "ordered id equality" was cut because it is unsatisfiable.**
  `AGENTS.core.md` has a `## Compliance Tier` section (holding
  `cq-pg-security-definer-search-path-pin-pg-temp`) that **`AGENTS.md` does not
  have** — the index carries only 6 sections and files that pointer under
  `## Code Quality`. So no section-wise union can make the corpus's rule order
  equal the index's. Satisfying it would require either adding
  `## Compliance Tier` to the index or relocating that body — both violate
  Phase 1's "file move + heading merge, nothing else" invariant. **Decision:
  preserve the asymmetry, and do not assert order.** If a reviewer wants
  diff-reviewability, add the index section in a separate follow-up.

- **SE-12 — `cq-agents-md-why-single-line` has 6 bytes of headroom.** It is
  **594 B** against `PER_RULE_CAP = 600`, and its rewrite must simultaneously
  describe the new architecture **and** carry the threshold literals the
  compound-sync `SITES` anchors match (Phase 6.1). It should fit — the new
  architecture description is shorter — but a `PER_RULE_CAP` reject here is a
  confusing mid-migration failure.

- **SE-13 — dropping the arrow creates two NEW vacuity holes of the SE-4 class.**
  With the arrow gone from `POINTER_LINE_RE`, the "pointer line found inside a
  sidecar" check in `lint-rule-ids.py` becomes structurally unreachable, and the
  defensive pointer filter in `lint-rule-bodies.py` becomes a no-op. Verified
  currently safe (`grep -c '^- \[id:'` returns 0 across all three sidecars, so no
  body line is pointer-shaped). SE-4 commits this plan to deleting unfailable
  checks rather than leaving them green — **apply that same disposition to these
  two, or record explicitly why they survive.**

- **SE-14 — grep-based ACs invert under `set -e`.** `grep` exits **1** when
  nothing matches, so a "returns zero hits" success case is a non-zero exit and
  reads as a failure inside a `run:` block or a checklist runner. Every
  residual-sweep AC in this plan is written as `! git grep -q …` or with an
  explicit count assertion for that reason. Repo precedent:
  `knowledge-base/project/learnings/2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md`.
  `git grep` also keeps the sweep tracked-files-only, satisfying
  `hr-never-run-commands-with-unbounded-output` (a bare `grep -rn … .` would
  descend into a multi-GB `node_modules`).

- **SE-9 — the hook is the only SessionStart reader of the tmpfs alarm.** This is
  why Phase 4 *reduces* rather than deletes. `scripts/tmpfs-guard.test.sh` Arm 20
  pins the alarm/heartbeat filename defaults across `tmpfs-guard.sh` and the
  loader; deleting the loader silently kills *"the only channel by which the
  alarm reaches a human"* (#6991 dead-channel class). Any reviewer who proposes
  full deletion must be pointed here.

- **SE-10 — `.gitignore` and `SessionStart` stay.** Because the hook survives,
  `/.claude/.session-manifests/` is **not** orphaned and
  `.claude/settings.json`'s `SessionStart` block stays populated. Do not "clean
  up" either.

## User-Brand Impact

**If this lands broken, the user experiences:** an agent session that boots with
part of the rule corpus missing — the governance-blackout mode. Concretely: a
`hr-*` compliance-tier rule absent from context while every lint reports green,
so the agent takes a prohibited action (writes to `main`, provisions
infrastructure by hand, pastes a secret) with no guardrail firing.

**If this leaks, the user's workflow is exposed via:** the SOC 2 per-session
manifest (`.claude/.session-manifests/`) or the `[session-context]` snapshot
being dropped in the hook reduction — removing the CC6.1/CC7.2 evidence trail
that records which rules were in context for a given session.

- **Brand-survival threshold:** `single-user incident` — same threshold CPO
  assigned to PR #3496, for the same reason: this is the mechanism that decides
  which governance rules exist in the agent's context. `requires_cpo_signoff:
  true`. `user-impact-reviewer` MUST run at review time.

## Observability

```yaml
liveness_signal:
  what: "[rules-loader] loaded: N of N rules" SessionStart stamp (numerator==denominator is the assertion; never hardcode 101 — it breaks the day rule 102 lands)
  cadence: every session start (startup|resume|clear|compact)
  alert_target: operator-visible stamp in the session transcript
  configured_in: .claude/hooks/session-rules-loader.sh
error_reporting:
  destination: stamp suffix (fail-safe note / over-strip WARN) + non-empty additionalContext guarantee
  fail_loud: true — numerator < 101 is the governance-blackout signal
failure_modes:
  - mode: corpus file missing or unreadable
    detection: stamp shows fail-safe note; retained loader test asserts it
    alert_route: operator stamp at session start
  - mode: frontmatter over-strip drops rule bodies
    detection: over-strip guard re-injects RAW and stamps "WARN: frontmatter over-strip"
    alert_route: operator stamp
  - mode: corpus truncated / partially written
    detection: RULE_COUNT < TOTAL_RULES in the stamp
    alert_route: operator stamp
  - mode: SOC 2 manifest not written
    detection: retained manifest test case in session-rules-loader.test.sh
    alert_route: CI (test-all.sh)
logs:
  where: .claude/.session-manifests/<session_id>.json (3-field, per session)
  retention: local, gitignored; SOC 2 CC6.1/CC7.2 evidence
discoverability_test:
  command: bash scripts/rules-loader-stamp-probe.sh
  expected_output: "OK"
  # The pipeline lives in the script, not here, because `/soleur:preflight`
  # Check 10 EXECUTES this command and refuses any shell-active token — pipes
  # included. The earlier one-liner form (printf | hook | sed | awk) was correct
  # and un-runnable by its own verifier, which is a probe nobody runs. Verified:
  # OK on 101/101, MISMATCH on a truncated 3/101 corpus, MISMATCH on a missing
  # corpus (the loader's 0-of-N blackout stamp).
  # Deliberately NOT `grep -cE 'loaded: ([0-9]+) of \1 rules'`: ERE
  # backreferences are non-POSIX and the operator's grep may be ugrep, which
  # rejects `\1` outright. The script never hardcodes the count either — the
  # denominator comes from the loader's expected set, so it survives rule 102.
```

No `ssh` anywhere. Soak/follow-through enrollment: **not applicable** — no
time-gated close criterion.

## Encryption Posture

**Not applicable — trigger fired mechanically, disposition recorded rather than
skipped silently.**

The deepen-plan Phase 4.10 detector matches `\.tf$` against the Files-to-Edit
list, and this plan does edit three `.tf` files. **Those edits are comment text
only** (prose citing `hr-github-app-auth-not-pat` — verified in Correction 3 /
SE-6): no resource, no provider, no variable, no state, no `terraform apply`.

- `at_rest`: **no new persistent store.** The only artifacts written are
  `AGENTS.rules.md` (a tracked repo file) and the pre-existing, gitignored
  `.claude/.session-manifests/` (unchanged in shape, location, and content — see
  SE-10).
- `in_transit`: **no new cross-component or network connection.** The corpus
  moves from disk into the local agent's context via the existing SessionStart
  hook; no socket, no egress, no new trust boundary.
- `exception`: none required.

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** to be reviewed at plan-review / deepen-plan.
**Assessment:** Sole affected domain. This is a repo-internal governance-mechanism
change with no product surface, no vendor, no cost, and no user-facing UI. The
architectural weight sits in ADR-150 and in SE-1.

Product/UX Gate: **NONE** — no path in `## Files to Create` or `## Files to Edit`
matches a UI-surface glob (`components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`). The mechanical UI-surface override does not fire.

GDPR gate (2.7): **skipped** — no regulated-data surface; no schema, migration,
auth flow, or API route. The SOC 2 manifest is pre-existing and unchanged in
shape.

IaC gate (2.8): **skipped** — verified no new infrastructure; the only `.tf` hits
are comment citations (SE-6).

Encryption posture gate (2.11): **skipped** — no persistent store, no new
cross-component connection.

Skill-description budget (1.8): **skipped** — Phase 5 edits SKILL.md *bodies*, no
`description:` frontmatter changes.

## Open Code-Review Overlap

One match across 61 open `code-review` issues:

- **#4133** — *follow-through(#4116): Schema parity test for `## Observability`
  block* — mentions `AGENTS.core.md` only as the home of the observability rule.
  **Disposition: acknowledge.** Different concern (observability schema parity,
  not corpus structure). Phase 7's citation sweep will keep its referenced path
  accurate; the issue stays open.

No open code-review issue touches `session-rules-loader`,
`lint-agents-rule-budget.py`, or `lint-rule-ids.py`.

## Rollback

- **Revert is clean.** `.claude/rule-body-hashes.txt` is keyed `<sha256>  <id>`
  with **no file path**, so it is path-independent: a `git revert` restores a
  consistent state with zero manifest churn. Because no `hr-*`/`wg-*` body
  changes (AC3), the manifest should be **byte-identical before and after** —
  do **not** re-run `--write` outside the Phase-0 baseline. A regenerated
  manifest appearing in the diff is an unexplained change to a CODEOWNERS-gated
  file and will be challenged at review.
- **Mid-migration `main` is safe** *provided* the commit topology above is
  honoured — a squash merge yields one atomic state. If it lands as eight
  commits, every intermediate SHA has a wedged pre-commit for anyone who
  branches or bisects from it.
- **The dangerous concurrent writer is automated, not human.** A human sibling PR
  touching `AGENTS.core.md` hits a delete/modify conflict on rebase — noisy but
  safe. `cron-compound-promote` opens PRs against `AGENTS.core.md` on a schedule;
  Phase 8.1 is the mitigation.
- `scripts/retired-rule-ids.txt` is **untouched** — no rule is retired; ids are
  immutable and this is a pure move.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A rule body is altered during the merge | AC4 body-hash identity proof (101/101 unchanged) |
| Weakening gate passes vacuously across the migration | SE-1: same-commit `SIDECARS` flip + AC4 as the real check; disclosed in the PR body |
| Reviewer reads the threshold raise as budget looseness | Phase 6 comment states the four derivation facts; the honest delta is **+5.8 %** vs the weighted mean and **−1,255 B** vs the majority path — not +85 % |
| Blast-radius list is incomplete | AC7 residual-zero grep over code/config extensions, with the plans/specs/archive carve-out |
| Freshness tripwire darks | SE-5: frontmatter rides along; `review-reminder.yml` + its liveness test retargeted |
| The per-turn accounting model is a recorded claim, not re-measured | Flagged in E2; conclusion holds under both models — route to deepen-plan for a measurement attempt |

## Deferred (do NOT implement here)

- **#7013 B_FAILOPEN reporting** — premise retired; close as obsolete.
- **#6138 shrink `B_ALWAYS` below 22 k** — target unreachable by construction; close / re-scope.
- **#3792 path-scoped AGENTS files** — superseded; close.
- **(c-iii) `@AGENTS.rules.md` @-import** — needs freshness metadata moved out of frontmatter first.
- Hook rename to match its reduced role.
- Any rule retirement (blocked on #6794 telemetry fragmentation, SE-7).
