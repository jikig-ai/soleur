---
title: "Mechanical gates for citation-rot + bare-token body-grep"
date: 2026-07-16
status: draft
issue: 6517
pr: 6527
branch: feat-citation-rot-bare-token-gates
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-16-citation-rot-bare-token-gates-brainstorm.md
---

# Spec: mechanical gates for two "the check certifies the wrong thing" classes

## Problem Statement

Two failure classes, with **very different recurrence rates** — a distinction #6517's own
body blurs ("two failure classes have *each* recurred across multiple PRs") and which this
spec originally inherited:

- **Class B (vacuous assertions) recurred 10 times across two PRs in two days** — #6456: 4;
  #6479: 6 (four grep, two placement-vs-semantics) — despite being documented in a standing
  learning written the day before, from a different PR that hit it four times.
  **Sub-attribution matters:** the 10 are **8 bare-token + 2 placement**, not 10 bare-token.
  Placement ≠ bare-token, and the distinction is what justifies the rule carrying **two**
  clauses — the anchor clause catches the 8, the mutation-test clause catches the 2.
- **Class A (citation rot) recurred once**, against **~360** existing `file:NNN` citations —
  a **~0.28%** defect rate. The denominator is filter-dependent (319–583 across plausible
  predicates) and is stated with the command that reproduces it in ADR-116 § Context; every
  conclusion here holds across that whole range.

All ten recurrences are Class B. The corrected attribution is what reshaped this spec: the
common class gets the cheap session-injected rule (code/infra classes), and the rare class does **not** get an
expensive gate whose measured error rate (57% false hits) is two orders of magnitude worse
than the defect it guards. See ADR-116 and the plan's `## Plan Review Findings`.

**Class A — `file:NNN` citations rot inside the commit that writes them.** In PR #6479,
comments cited emitters at `:151`/`:159` — correct against `main`, then shifted 35 lines
by the same PR's own header expansion, landing on a **decoy** line that also echoed
`TRANSIENT`. The reviewer read a false confirmation. This happened in a file whose own
header says *"anchored on EMIT NAMES, not line numbers — line citations rot."*

**Class B — a body-grep / `indexOf` assertion anchored on a bare token that also appears
in a comment.** A body-grep sees comments, so `grep -q '<bare-word>'` over a source file
is satisfiable by prose. In #6479 a corroboration grep added to close one bypass was
itself bypassable by two comment lines.

Both classes produce a **false green**: a check reports the code is verified when it is
not. In #6479 the affected gate authorized an **irreversible** GHCR PAT rotate-and-revoke,
and three live false-PASS routes survived a 6-agent plan panel, a deepen pass, TDD, and a
6-agent review.

The disposition for a recurring documented class is a mechanical intervention — but the
one #6517 proposes is mis-shaped in three ways this spec corrects (see Non-Goals).

## Goals

> **Superseded in part by plan v2** (a 7-agent panel reversed v1). G1–G3 below are the
> corrected forms; the plan is authoritative where they still differ.

- **G1** Prevent *new* `file:NNN` citations from entering code comments at author-time,
  blocking from day one — **but only once the gate clears its replay AC** (`AC-B1`:
  ≤3/300 commits denied, zero false denials). v1's detector measured 50/300 at 57% false
  hits and would have denied `main`'s own HEAD, so G1 is **held**, not shipped. Rung 2 (the
  rule) ships now instead.
- **G2** Put the anchoring rule on the surface the author is actually looking at when
  writing a citation or an assertion. **Corrected:** that surface is `AGENTS.rest.md`, which
  is **not** always-loaded — it is **class-gated**. `session-rules-loader.sh` injects
  `CLASSES="core rest"` on code/infra sessions and `CLASSES="core docs-only"` on docs-only
  ones; only `AGENTS.md` + `AGENTS.core.md` are always-loaded (`lint-agents-rule-budget.py`,
  `B_ALWAYS`). The claim is *narrower* than v1's and still sufficient: the rule fires on
  exactly the session class that writes code comments and test assertions.
- **G3** ~~Make the Class B gate's promotion depend on rule-metrics fire counts.~~
  **Unachievable as written** — a prose-only rule has **no emitter**, so its `fire_count` is
  0 forever (ADR-116 § Consequences). **Corrected:** there is **no mechanical promotion
  trigger**, and saying so is the honest answer (plan Q2). The mechanism that demonstrably
  works is `/compound`, which caught this class twice in two days with no trigger at all.
- **G4** Add zero standing noise: no gate may fire on the grandfathered tree.

## Non-Goals

- **NG1 Not building a citation resolvability validator.** It cannot detect the #6479
  decoy (a 35-line intra-file shift onto a line that still echoed the token), and **0** of
  the 334 resolvable citations are past-EOF (re-verified 2026-07-16). Past-EOF is the only
  rot a resolver detects; intra-file drift is the rot that actually happens. Explicitly
  rejected — see brainstorm D1.
- **NG2 Not validating markdown citations.** Thousands of sites — and the exemption does not
  depend on the count, so none is asserted (an earlier draft's "6,529" was unreproducible;
  see ADR-116 § Decision 2). Archived plans and learnings are historical records, not live
  claims.
- **NG3 Not shipping advisory-first.** #6517's stated AC is overridden: #4270's calibration
  window is open at 56 days (4× its stated 2 weeks) with zero organic findings, and no
  advisory gate in this repo has ever been promoted to blocking.
- **NG4 Not building the Class B ts-morph gate in this scope.** Deferred to **#6529**; naive
  regex is ~95% false-positive. **Not** "deferred behind G3's trigger" — G3's trigger does
  not exist (see G3). The deferral is open-ended and honest: the next recurrence surfaces it
  via `/compound`, the way the last two surfaced.
- **NG5 Not retrofitting the ~360 existing citations.** Grandfathered permanently
  (ADR-116 § Context states the figure with the command that reproduces it).

## Functional Requirements

### Class A — born-blocking ban on new line citations (PR B — **HELD**)

> **Superseded by plan v2.** This section described a **PreToolUse hook**, which the review
> panel **reversed**: the hook is Claude-Code-only and this repo also supports Grok Build.
> **The surface is OPEN — an architecture fork routed to the `cto` agent at PR B start.** The
> section below is the corrected form; the plan's `## PR B` block is authoritative.
> **Nothing here ships until `AC-B1` passes.**

- **FR1** The linter (`scripts/lint-line-citations.sh`) rejects added diff lines introducing a
  `path:NNN`-shaped citation inside a comment. **Two things are decided:** it is **not** a
  PreToolUse hook (Claude-Code-only; this repo also supports Grok Build), and it is **not** an
  *advisory* CI job. **The surface itself is NOT decided** — `lefthook pre-commit` alone vs.
  lefthook + a load-bearing CI enforcer is an architecture fork routed to the `cto` agent
  (plan § Research Reconciliation, P2-3 row; plan § PR B "Surface: OPEN").
  **Bypass surface — four, not one.** An earlier draft of this FR stated only
  `git commit --no-verify` and dismissed it as "a bypass no agent has been observed using".
  That was wrong on both halves. `pre-commit` fires on **none** of:
  1. `git cherry-pick` — no `pre-commit` hook;
  2. `git rebase` — no `pre-commit` hook;
  3. `git merge` — runs `pre-merge-commit`, not `pre-commit`;
  4. `git commit --no-verify` — explicit skip.

  Three of those four are **ordinary agent operations**, so the "not observed" dismissal was
  unsupported. This is exactly why the `gitleaks-staged` precedent pairs its lefthook half
  (self-described *"fast-feedback only"*) with a CI **enforcer** — and why taking only the
  lefthook half would repeat v1's ADR-071 half-taking. Counter-evidence, weighed equally:
  `main` has **no branch protection**, so no CI check here is truly required. The `cto` agent
  resolves it; this FR does not.
- **FR1b** Cited-extension allowlist:
  `\.(ts|tsx|js|mjs|cjs|jsx|sh|bash|py|sql):[0-9]+(-[0-9]+)?` — this is what kills
  `127.0.0.1:6379`, `4.5:1`, and (deliberately) `.tf`/`.yml` targets, which have no symbol
  anchor to prefer.
- **FR1c** Strip `https?://` **before** comment-tail extraction. `http://` **is** the TS
  comment marker; without the strip, `postgres://u:p@127.0.0.1:54322/db` denies a line
  containing no comment at all. This single defect drove v1's 57% false-hit rate.
- **FR2** Scope is **added lines only** (`git diff -U0` `^+` lines). Existing citations
  never fire. **Caveat:** `git diff` has no move detection (`-M` is file-rename-only), so a
  refactor relocating a function republishes its comment as `^+`. Either implement move
  tolerance (a `+` line whose identical text exists in the pre-image is not new) or drop the
  move-scoped claim; G4 is not true until one of those lands.
- **FR2b** Diff base is `-a`-aware, reusing `brand-hex-commit-gate.sh`'s `NAME_REF` logic
  **including its quoted-arg strip**. Do not reimplement. *(This was v1's **FR7**. It is
  renumbered rather than left in place because v2's FR7 slot was reused for "Recovery is
  mandatory" — and a **reused number is exactly this spec's own subject**: any external
  citation of "v1 FR7" now silently resolves to a different requirement. No live consumer
  cites it, so the rot is latent; it is disclosed here rather than left for a reader to
  discover.)*
- **FR3** Markdown, JSON, and non-comment code are out of scope.
- **FR4** The denial message names **both** the content-anchor alternative
  (`<file> › <symbol>()`, per ADR-076 item 3) **and the waiver form** (FR5), plus the named
  kill switch (FR7) — not just the alternative.
- **FR5** An escape hatch waives a line: `# cite-line:allow # issue:#NNNN <reason>`,
  mirroring the `.gitleaks.toml` `# gitleaks:allow # issue:#NNN <reason>` convention
  (precedented; exercised in `canary-bundle-claim-check.test.sh` and
  `redaction-allowlist.test.ts`).
- **FR6** ~~The hook emits `emit_incident <rule_id> applied` telemetry.~~ **Dropped.** Do
  **not** copy `brand-hex-commit-gate.sh`'s hook-name emit: `rule-metrics-aggregate.sh`
  carves out only `te-*`, `gdpr-gate-*`, `context-reviewed-*`, and pencil ids, and **exits 5**
  on an unrecognised emitter — the orphan-gate trap.
- **FR7** **Recovery is mandatory** (ADR-071 pairs it with its gate; v1 dropped it): a named
  kill switch (`SOLEUR_CITE_LINE_EXT_RE=^$` ⇒ empty scope ⇒ allow), **named in the deny
  reason**, plus a baseline of pre-existing violations. *The agent — never the operator —
  owns gate maintenance, baseline refresh, and recovery.*

### Class B — the standing rule (PR A — **ships now**)

> **Sequencing corrected (plan v2):** this is the class that recurred 10×, so it ships
> **first**, in PR A, alongside `cq-cite-content-anchor-not-line-number` and ADR-116. v1 had
> it second behind the Class A gate — the inversion DHH flagged as the plan's P0.

- **FR8** A new rule `cq-assert-anchor-not-bare-token` is added to `AGENTS.rest.md` with
  a pointer row in the `AGENTS.md` Code Quality index, in the established one-line
  `- <text> [id: ...]. **Why:** #NNNN — <reason>.` format.
- **FR9** The rule requires: a body-grep / `indexOf` / `toContain` whose haystack is file
  content MUST anchor on `^\s*` or a call-form construct a comment cannot produce; and
  every new assertion MUST be mutation-tested before commit.
- **FR10** The rule cites #6479 and #6456 as the recurrence evidence.

## Technical Requirements

- **TR1** ~~Class A ships as a `.sh` + `.test.sh` pair in `.claude/hooks/`, registered in
  `.claude/settings.json` under `PreToolUse`/`Bash`.~~ **CORRECTED — reversed by the panel.**
  Class A ships as `scripts/lint-line-citations.sh` + a sibling `.test.sh`, registered as a
  **blocking `pre-commit` entry in `lefthook.yml`** (the `gitleaks-staged` shape). Rationale:
  a PreToolUse hook is Claude-Code-only and this repo also supports Grok Build; lefthook is
  harness-independent. **Registration trap:** `scripts/*.test.sh` is **not** in
  `test-all.sh`'s auto-discovery glob (which covers `scripts/lib/*.test.sh`) — the sibling
  suite needs an explicit `run_suite` line or it silently never gates.
- **TR2** Reuse `brand-hex-commit-gate.sh`'s awk hunk-header walker (newline-number →
  added-content) and its `-a`-aware diff-base logic. Do **not** reimplement.
- **TR3** No citation parser exists to reuse. `dm_register_code_citations()`
  (`scripts/lib/domain-model-lib.sh`) pairs file↔symbol with no line numbers — it is the
  philosophical precedent (anchor on symbols), not a code dependency.
- **TR4** ~~Deny via the `hookSpecificOutput.permissionDecision: "deny"` JSON contract,
  exit 0, per `.claude/hooks/README.md`.~~ **CORRECTED — that contract is PreToolUse-only.**
  A lefthook linter denies by **exiting non-zero** and printing the reason to stderr (the
  `gitleaks-staged --exit-code 1` shape). Corollary: with no JSON payload there is no
  `permissionDecision`, and `exit 2` (internal error) → **allow**, stated explicitly
  (`set -uo pipefail`, not `-e`).
- **TR5** Fixtures prove both directions: a `foo.ts:151`-bearing added line DENIES; a
  `foo.ts › emitBeacon()` added line ALLOWS; a grandfathered citation on an untouched line
  ALLOWS; a waived line ALLOWS.
- **TR6** ~~Per ADR-071, the gate must fail closed — if it cannot compute a diff it must
  FAIL, never silently SKIP.~~ **CORRECTED (spec fiction).** ADR-071's scope is the
  `constraint-scaffold` dependency-cruiser import-boundary gate in the *product codebase*
  ("the product-code instantiation of ADR-011 tier 1") — not a universal mandate. The
  sibling hook template `brand-hex-commit-gate.sh` is deliberately **fail-OPEN** on
  environment gaps ("Environment/tooling gaps must not block every commit"). A gate that
  fails closed on a missing git tree bricks every commit. Independently confirmed by
  architecture-strategist at plan review.
- **TR6b** The portable principle ADR-071 *does* carry: the gate must never **silently
  self-disable** ("an empty from-set while `use client` files exist is a hard error, not a
  silently-disabled rule"). A missing `jq` must fail loudly, not allow universally.
- **TR7** The Class A hook's own assertions must satisfy the Class B rule (anchor on
  syntax, not bare tokens) and be mutation-tested — the gate must not commit the class it
  guards against.

## Acceptance Criteria

- **AC1** A commit adding `// see foo.ts:151` to a `.ts` file is DENIED, with a message
  naming the content-anchor alternative. Fixture proves it.
- **AC2** A commit adding `// see foo.ts › emitBeacon()` is ALLOWED. Fixture proves it.
- **AC3** A commit touching a file that *already contains* a `file:NNN` citation, without
  adding one, is ALLOWED. Fixture proves grandfathering.
- **AC4** A line carrying `# cite-line:allow # issue:#NNNN <reason>` is ALLOWED.
- **AC5** Deleting the hook's core guard reddens its test suite (mutation-proven
  load-bearing, per the 2026-07-16 learning's prescription).
- **AC6** `cq-assert-anchor-not-bare-token` resolves in `AGENTS.md` and its body appears in
  `AGENTS.rest.md`; the session-rules-loader loads it for the `rest` change-class.
- **AC7** ~~`rule-metrics-aggregate.yml` records the new rule id (baseline fire count = 0 at
  ship).~~ **Dropped — it asserts a false expectation.** A prose-only rule has no emitter, so
  it is never *recorded* at all; asserting "fire count = 0" implies a counter exists that
  would move. It cannot (G3, ADR-116 § Consequences). **Unmeasurable ≠ ineffective.**

> **AC1–AC5 belong to PR B and are HELD.** They describe the detector's fixtures and are
> superseded by the plan's PR B block; **do not carry v1's detector AC set forward** — in that
> set, the self-scan AC contradicted the AC1 fixture family, since a `.sh`/`.py` fixture
> exercising the `#` path must literally contain `# see foo.sh:12`, which the self-scan then
> denies (plan § Research Reconciliation, "v1 AC7 vs AC1"). *That* self-scan AC is **not** this
> spec's AC7 — this spec's AC7 is the rule-metrics one struck directly above; the two AC sets
> are unrelated and share a number by coincidence.
> PR B's ACs are re-derived from scratch, and **AC-B1** (≤3/300 denied, zero false denials)
> gates all of them. PR A's real ACs are the plan's **AC1–AC10** — the three linters +
> `test-all.sh` (AC1–AC8), plus **AC9** (no bare denominator) and **AC10** (no moving
> reference in the present tense), both added at review. An earlier draft of this line said
> "AC1–AC8", silently dropping the two ACs that guard this PR's own subject.

## Sequencing

> **Reversed by plan v2.** v1 shipped the Class A gate first and the Class B rule second —
> the exact inversion DHH flagged as P0: *the 10× class shipped prose while the 1× class
> shipped nine artifacts*. The corrected order:

1. **PR A (both rules + ADR-116)** — **ships now.** Rung 2 — the session-injected prose rung
   — for *both* classes, which was **never occupied** for either. Docs/rules only.
2. **PR B (the Class A gate)** — **HELD.** Does not start until PR A merges, and does not
   ship until **AC-B1** (the replay) passes. v1's detector scored 50/300 denied at 57% false
   hits and would have denied `main`'s own HEAD. It may never ship — a gate that denies
   1-in-6 commits is worse than no gate.

The Class B ts-morph gate is a **deferred follow-up** (#6529). Its trigger is **not**
mechanical — see G3 and plan Q2; do not re-derive v1's day-0 grep.

## Open Questions — **Q2/Q3 resolved in plan v2; Q1 REOPENED at review**

1. ~~Hook-only vs hook + CI backstop.~~ **Partially resolved — and then REOPENED.**
   *Resolved:* not a PreToolUse hook (Claude-Code-only), and not an *advisory* CI job (*"a
   non-required check that fails closed fails closed onto nothing"*); the cascade deleted the
   standalone detector with it (one caller ⇒ inline it).
   **Still OPEN:** lefthook `pre-commit` **alone** vs. lefthook **+ a load-bearing CI
   enforcer**. An earlier draft of this line recorded "Resolved → neither … the surface is
   lefthook", which **settled in a docs PR an architecture fork the plan explicitly reserved
   for the `cto` agent** — see plan § Research Reconciliation (P2-3 row) and § PR B
   ("Surface: OPEN … Do not treat this bullet as decided"). The `gitleaks-staged` precedent
   invoked in support of lefthook is **two-surface** (its lefthook half is self-described
   *"fast-feedback only"*; CI *"is the enforcer"*), and `pre-commit` misses cherry-pick,
   rebase, and merge (FR1). Counter-evidence: `main` has no branch protection. Routed to
   `cto` at PR B start, before AC-B1.
2. ~~The concrete rule-metrics promotion threshold for the Class B gate.~~ **Resolved →
   there is no mechanical trigger, and that is the honest answer.** v1's proposed grep fires
   on day 0 against its own evidence, and nothing runs it. The demonstrated mechanism is
   `/compound`. See plan Q2 and G3.
3. ~~Whether the absent severity ladder on hook surfaces warrants an ADR.~~ **Resolved →
   ADR-116**, scoped to the citation convention rather than a general severity ladder.

*(The `tier1-scan.test.ts:654-678` citation in Q1's original text is itself a `file:NNN`
coordinate — retained verbatim as a historical record of the question as asked. Under
ADR-116 it is grandfathered, and markdown is exempt regardless.)*
