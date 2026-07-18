---
title: "Mechanical gates for citation-rot + bare-token body-grep"
date: 2026-07-16
type: feat
issue: 6517
pr: 6527
branch: feat-citation-rot-bare-token-gates
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-07-16-citation-rot-bare-token-gates-brainstorm.md
spec: knowledge-base/project/specs/feat-citation-rot-bare-token-gates/spec.md
adr: ADR-116 (provisional ordinal — re-verify at ship)
plan_version: 2 (v1 reversed by a 7-agent review panel — see ## Plan Review Findings)
---

# Plan: mechanical gates for two "the check certifies the wrong thing" classes

## Overview

**PR A — ship now.** ADR-116 + the two AGENTS.md rules. This is **rung 2** (the
session-injected prose rung (code/infra classes)) for *both* classes — the rung that was **never occupied** for
either.

**PR B — held, re-scoped.** The Class A citation gate (**rung 3**). v1's detector was
measured net-negative and does not ship until a replay AC proves otherwise.

### Why the shape changed (v1 → v2)

v1 pointed a hook + CI job + detector + two test suites + an ADR at **Class A**, justified
by "10× recurrence in two days." **The 10 recurrences are all Class B.** Verified:
#6456's four were "vacuous assertions"; #6479's six were "four grep, two
placement-vs-semantics."

**Sub-attribution (P2-2), because it changes the rule's shape:** "all 10 are bare-token" is
imprecise. It is **8 bare-token** (#6456 ×4, #6479 ×4) **+ 2 placement-vs-semantics**
(#6479) — 10 instances of the parent class *vacuous assertion*, not 10 bare-token hits.
Placement ≠ bare-token. This **vindicates the two-clause rule**: the *anchor* clause catches
the 8, the *mutation-test* clause catches the 2. A one-clause rule catches 8 of 10.

Class A (citation rot) recurred **once**, against **~360** existing
citations — a **~0.28%** defect rate (the denominator is filter-dependent: 319–583 across
plausible predicates, stated with its reproducing command in ADR-116 § Context; the
conclusion holds across the whole range). v1 armed the rare class and shipped prose for the common
one. The `10×` figure was propagated into the brainstorm, spec, plan, learning, **and the
#6517 issue body** — all corrected.

v1's detector was then measured and fails on its own terms:

| Measurement | Result |
|---|---|
| Commits denied, last 300 on `main` (CTO replay) | **50/300** (~1 in 6) |
| Hits that are **not** citations | **73/128 (57%)** — `127.0.0.1:6379`, `10.0.1.30:5000`, `4.5:1`, `3.66:1` |
| Denied commits containing **zero** true citations | **19/50** |
| **`cee4e1f55`** — PR #6479's merge commit, **the PR that motivated this issue**; it was `main`'s HEAD when the CTO replayed the detector on 2026-07-16 | **DENIED** (`inngest-host.tf:181`, `cloud-init.yml:408`, `server.tf:241`, +3) |
| Hits from the plan's own spec vs the plan's then-claimed count (Kieran) | **555 vs 369** — the spec and its own measurement disagreed by 50%. (Historical: 369 was v1's unlabelled figure. Superseded — see the denominator row in Research Reconciliation. Do not rewrite this number; it records what Kieran measured against.) |

**Root cause (Kieran):** `http://` **is** the TS comment marker. `const D =
"postgres://u:p@127.0.0.1:54322/db"` → tail after `//` → matches `127.0.0.1:54322` →
**denies a line containing no comment at all.**

A gate whose error rate is two orders of magnitude worse than the defect it prevents **is
the class it exists to stop**. It certifies the wrong thing.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured) | Plan response |
|---|---|---|
| **v1 + spec + issue #6517:** "the class recurred 10× across two PRs" | **All 10 are Class B.** #6456: 4 vacuous assertions. #6479: "four grep, two placement-vs-semantics." Class A = **1** instance / ~360 citations. | Class A is the *rare* class. It gets rung 2 now; rung 3 only if a replay proves the detector is net-positive. Corrected in brainstorm, spec, learning, and the #6517 body. |
| **The denominator itself** (`369`, then `386`, then `403` — each unlabelled) | **Filter-dependent and, as stated, unreproducible.** 18 faithful readings of the review's own canonical predicate ("a line in a code file bearing a comment marker AND citing `<path>.<src-ext>:<N>`") returned 319 / 322 / 358 / 373 / 419 / 433 / 477 / 583 — **never 403**. A prose predicate leaves per-line-vs-per-match, unique-vs-all, and marker position free; each is worth ±10–30%. | Cite the figure **with the command that reproduces it** (ADR-116 § Context), never with a description of one. **~360** today. The conclusion is invariant across 319–583 (0.17–0.31%), which is *why* the false precision survived a 5-agent panel — nothing depended on it. Same defect as the citation rot this PR indicts, one level up: prose names a referent without pinning it. |
| **v1 Q1:** "CI is the only cross-harness enforcement" | **False.** `lefthook.yml` has a `pre-commit:` stage running **blocking** linters harness-independently (`gitleaks-staged`, `--exit-code 1`; `lint-fixture-content`). It fires for Warp, Grok Build, scripts — any `git commit`. | **Q1 re-decided.** PR B targets **lefthook**, not a PreToolUse hook + CI job. One surface. Trade-off recorded below. |
| **v2's own Q1:** "`gitleaks-staged` is the exact precedent" for a lefthook-only surface (P2-3) | **Half-true, and the half matters.** The gitleaks precedent is a **two-surface** pattern and says so in both files: `lefthook.yml` — *"fast-feedback companion to the load-bearing CI gate at `.github/workflows/secret-scan.yml`. Bypass with `git commit --no-verify` is intentionally possible — CI re-scans on every PR."* `secret-scan.yml` — *"Load-bearing CI gate. The lefthook `gitleaks-staged` command is fast-feedback only; **this workflow is the enforcer**."* PR B cites the precedent and keeps only its **non-enforcing** half. That is structurally the same error this table already indicts v1 for: taking ADR-071's non-required half and dropping its recovery half. It also answers **spec-flow's unanswered P0** — `pre-commit` does not fire on cherry-pick, rebase, or `merge` (which uses `pre-merge-commit`), so a lefthook-only gate is bypassed by three ordinary operations *plus* `--no-verify`; in the precedent, CI is what closes all four. | **Recorded, not decided — PR B is HELD and this is its design-of-record, not PR A's.** Resolve at PR B start, before AC-B1. **The panel's CI critique is not refuted by this:** it killed an *advisory, non-required* CI job (*"fails closed onto nothing"*), which is a different artifact from a load-bearing one. **Counter-evidence that must be weighed:** `main` currently has **no branch protection at all** (`gh api …/branches/main/protection` → 404 *Branch not protected*), so *no* check in this repo is literally "required" — which is a genuine point for the panel and against a naive "just add CI". This is an **architecture fork** (which enforcement surface, and whether a non-required CI job is worth anything here); route it to the `cto` agent at PR B start rather than settling it in a docs PR. |
| **v1 Q2:** trigger = `git log --since=<ship-date> … grep vacuous-assertion` | **Fires on day 0.** spec-flow ran it: returns the *two learnings that motivated this plan*, both dated the ship date. `--since` is commit date; `--name-only` re-fires on any later touch. **Nothing runs it** — no cron, no owner. | **Q2 re-decided (honestly): there is no mechanical trigger.** Claiming one that fires day 0 is worse than claiming none. See Q2 below. |
| **v1 spec TR6:** "fail closed per ADR-071" | **Fiction** (independently confirmed by architecture-strategist). ADR-071 §Decision scopes itself to "the product codebase… the product-code instantiation of ADR-011 tier 1." `brand-hex-commit-gate.sh` is deliberately fail-**open**. | TR6 corrected. **TR6b** is the portable principle: never *silently self-disable*. |
| **v1:** cites ADR-071 as precedent for a non-required check | **Misread, twice** (architecture-strategist). ADR-071 says promotion is *blocked only on #5778*, and #5791 is *satisfied by ADR-074*. A tracked temporary state pending promotion — **not** an endorsement of non-required. | Removed as precedent. It is a scope constraint, not a licence. |
| **v1:** took ADR-071's non-required half | **Dropped its recovery half.** ADR-071 pairs the gate with *"The agent — never the founder — owns gate maintenance, baseline refresh, and recovery"* + zero-touch auto-recovery (ADR-074), and **baselines** pre-existing violations rather than hard-breaking. | PR B MUST ship a named kill switch + a baseline. See PR B §Recovery. |
| **v1 D6:** "rule-metrics = promotion trigger" | `rules_unused_over_8w: 97/99`; only **3** rules ever fired, all `applied_count: 1` from hardcoded `emit_incident` calls. A prose rule has **no emitter** ⇒ `fire_count: 0` forever. | Split: a hook-enforced rule emits (valid signal); a prose-only rule cannot. Class B's rule is prose-only **by design** — that is a property, not a defect. |
| **v1:** "orphan gate carve-out only for `te-*`" | **Inaccurate.** `rule-metrics-aggregate.sh` carves out `te-*`, `gdpr-gate-*`, `context-reviewed-*`, and pencil ids ("emitted by their hooks by design"), and exits **5**. | Corrected. The hook→AGENTS-id coupling is a **choice** (the rule is a wanted deliverable), **not** a constraint. v1's "FORCES" claim withdrawn. |
| **v1:** "Class A is diff-scoped **and move-scoped**" | **Move-scoping was never built.** `git diff -U0` has no move detection; `-M` is file-rename-only. A refactor relocating a function republishes its comment as `^+` ⇒ **denies content the author didn't write**. | PR B must either implement move-tolerance or drop the claim. G4/AC3 were false as written. |
| **v1:** pointer ≈54 B each | **108 B** for pointer 1 (Kieran) — the `[hook-enforced: …]` tag. **Zero** existing AGENTS.md pointers carry bracket tags. | Tag dropped from the pointer (moved to the body). Two pointers = **105 B including newlines** (55 + 48 + 2; an earlier draft said "111 B + newlines" — re-measured at review as `wc -c` AGENTS.md branch-minus-`origin/main`) ⇒ **measured B_ALWAYS = 22900 / 23000** (linter, exit 0; **100 B** headroom, and 22795 + 105 = 22900 reconciles). |
| **v1 AC7 vs AC1** | **Contradictory** (Kieran). The detector cannot distinguish a heredoc from a comment; any `.sh`/`.py` fixture exercising the `#` path must literally be `# see foo.sh:12`, which AC7's self-scan denies. "Fixtures in strings, never comments" is **unsound**. | PR B: build fixture markers by concatenation (`H='#'`) or scope fixtures to `//`. |
| **Verified sound, no action** | `git commit` trigger regex, `-a`-aware `NAME_REF` + quoted-arg strip, awk hunk-walker, the `mapfile -z`/ugrep note (all `brand-hex-commit-gate.sh`); `GATED_PREFIX_RE = ^(hr|wg)-` ⇒ `cq-*` needs no ack; pointer shape; bodies ≤ 600 (as-shipped: **558 B / 595 B** — 492/443 were v1's shorter drafts; **534** was this row's own stale figure, predating the P2-1 carve-out clause and P2-2 sub-attribution and caught at review. The 595 leaves **5 B** of headroom, so re-measure rather than retype); Task 1.7's orphan-suite finding (`test-all.sh` globs `scripts/lib/*.test.sh`, not `scripts/*.test.sh`). | Carried into PR B. |
| **Waiver precedent** (code-simplicity claimed "zero precedent repo-wide") | **False.** `.gitleaks.toml`: *"Waivers: line-level `# gitleaks:allow # issue:#NNN <reason>`"*; exercised in `canary-bundle-claim-check.test.sh`, `redaction-allowlist.test.ts`, `secret-scan.yml`. | Finding rejected with evidence. The form is precedented. (The `issue:#N` requirement is stricter than gitleaks, which only conventionalizes it — see PR B.) |

## Resolved Open Questions

**Q1 — surface → `lefthook` pre-commit. Not a PreToolUse hook, not a CI job.**
v1 shipped hook + informational CI and justified it with "hook fails open, CI fails closed."
Both simplification reviewers killed it: *"A non-required check that fails closed fails
closed onto nothing"* (DHH); *"the plan kills advisory-first citing #4270, then ships an
advisory surface"* (code-simplicity). Both panels firing one scope ⇒ delete. The cascade
deletes the standalone detector too (one caller ⇒ inline it), which dissolves Task 1.7's
orphan-suite trap entirely.
Then spec-flow refuted the premise that survived: **lefthook already runs blocking linters
at pre-commit, harness-independently.** That is the surface — it covers Claude Code, Grok
Build, Warp, and scripts, and `gitleaks-staged` is the exact precedent.
**Stated trade-off:** lefthook is bypassable by `git commit --no-verify`; PreToolUse is not
(that is precisely why `brand-hex-commit-gate.sh` chose PreToolUse). We accept
`--no-verify` bypass in exchange for harness independence — the Grok gap is a real
population, `--no-verify` by an agent is not an observed one. Revisit if it becomes one.

**Q2 — Class B promotion trigger → there is none, and that is the honest answer.**
v1's grep fires on day 0 on its own evidence. The mechanism that *demonstrably* works is
the one that caught the class **twice in two days with no trigger at all**: `/compound`
produces a learning when the class recurs. #6529 stays open with the evidence recorded; the
next recurrence surfaces it the same way the last two did. **Do not invent a trigger that
fires immediately** — that is the same false-green this whole issue is about.

**Q3 — ADR-116, new (not an ADR-076 amendment).**
Panel split 2-1; the majority carries the sharper reason (architecture-strategist):
ADR-076 item 3 is register-scoped and its Alternatives row rejects line numbers for
**extractor spurious-diff**, not comment rot — a different rationale. DHH's dissent (ADR-076
already self-amends twice, #5871/#5872) is recorded and was **operator-decided** in favour
of a new ADR. Ordinal 116 verified free (115 is max).

## Architecture Decision (ADR/C4)

### ADR — create ADR-116 (PR A)

Ordinal **provisional**; `/ship` re-verifies against `origin/main`. **If renumbered, sweep
this plan + `tasks.md` + every AC naming the ordinal in the same edit** (#5990's failure).

> **ADR-116: Content-anchored citations in code comments.**
> **Status:** accepted. **Decision:** (1) Code comments cite `<file> › <symbol>()`, never
> `<file>:NNN` — generalizing ADR-076 item 3 from the domain-model register to all code.
> (2) Any mechanical enforcement of (1) ships **born-blocking**, never advisory-first.
> (3) Enforcement is **not yet built** — the v1 detector measured 50/300 commits denied at
> 57% false hits and is held pending a replay gate (this repo's own HEAD would have been
> denied). The convention stands as a session-injected rule (code/infra classes)
> (`cq-cite-content-anchor-not-line-number`) in the interim.
> **Alternatives Considered:** *Validate resolvability* — rejected: a coordinate carries no
> content assertion; the #6479 decoy passes it; 0 past-EOF of 334 resolvable. *Advisory-first* —
> rejected: #4270 open 56d vs a 2wk window, 0 organic findings, 0 advisory→blocking
> promotions ever. *Amend ADR-076* — rejected: its subject is the drift extractor and its
> line-number rejection was for spurious diffs, not comment rot.
> **Consequences:** the convention is stated and unenforced until the gate clears its
> replay AC; the ~360 existing citations are grandfathered permanently (figure stated with
> its reproducing command — a prose predicate does not pin a count).
> **Related:** ADR-076 (register precedent), ADR-071 (gate tiers + the agent-owns-recovery
> contract), ADR-092 (rule-body ack gate).
> **C4 impact:** none — see below (mirror ADR-076's `## C4 impact` section).

### C4 views

**No C4 impact.** All three model files read (not a keyword grep); independently confirmed
by architecture-strategist.

- **External human actors:** none — a commit-time convention has no external correspondent.
- **External systems / vendors:** none.
- **Containers / data stores:** `hooks = container "Hook Engine"` (`model.c4`) — already
  modeled, a **leaf** (components hang off `plugin`, not `engine`); `views.c4` includes
  `platform.engine.hooks` as an element only; `spec.c4` defines no hook kind. Its
  description ("blocks commits to main, rm -rf, etc.") absorbs a new guard.
- **Access relationships:** none change. No element description is falsified.

## User-Brand Impact

Carried forward from the brainstorm (Phase 0.1, #5175), **plus a third bullet added at
review — the first two enumerate a *gate's* failure modes, and PR A ships no gate.**

- **If this lands broken, the user experiences:** a gate that reports green while the defect
  it certifies is present (#6479: three false-PASS routes to `exit 0` on a gate authorizing
  an irreversible GHCR PAT revoke). **v2 adds the inverse:** a gate that reports *red* on
  correct work — measured at 1-in-6 commits — which is why PR B is held.
- **If this leaks:** n/a — no user data. The exposure is *trust*.
- **PR A's own vector — a reader concluding protection exists that does not.** PR A's
  artifact is an ADR + two rule bodies *asserting a posture*. There is no gate to misfire,
  only a claim to be believed. The user experience is an engineer who reads "the rule is
  loaded", "no gate enforces this", or "we measured it" and calibrates their own vigilance to
  a statement that is false.

  **The artifact makes THREE classes of claim, and each is a distinct vector.** An earlier
  draft of this bullet named only the first two — and the third is exactly where the next
  defect was found, which is the argument for enumerating by *reader-role* rather than by
  artifact:
  1. **Enforcement reach** — "is this gated?" *Fired: **P2-1**, where
     `cq-assert-anchor-not-bare-token` shipped without the "Convention only; no gate enforces
     it" clause its sibling carries, two lines below a rule tagged `[hook-enforced: …]`. A
     reader infers enforcement from the asymmetry.*
  2. **Load reach** — "will I actually see this rule?" *Fired: **P1-3**, where the ADR and
     plan claimed `AGENTS.rest.md` is always-loaded. It is **class-gated**; docs-only sessions
     never load it. The claim was load-bearing for the ADR's central "rung 2 was never tried"
     argument.*
  3. **Measured evidence** — "was this actually checked?" The reader here is deciding whether
     to *rebuild a rejected alternative*, not whether to trust a gate — a different role, and
     the one the two-class enumeration could not see. *Fired repeatedly at re-review:* the
     resolvability pair (`320 unique / 334 resolvable` — arithmetically impossible as stated,
     and carrying no command while §Context published one for `~360`); the `534 B` body size
     asserted *inside a sentence claiming verification*; `~6,529` markdown sites,
     unreproducible, two bullets from the paragraph naming that defect; and `1/403 = 0.248%`,
     deriving a correction basis from the number the same document calls unreproducible.

  **Not one of these was caught by a gate** — every one was caught by a reviewer reading the
  artifact against the code, or re-running a command the artifact asserted had been run. That
  is the honest statement of PR A's protection level, and it is why the rules ship as
  convention (rung 2) rather than as a claim of enforcement.
- **Brand-survival threshold:** `single-user incident`.

**CPO sign-off:** carried forward from brainstorm Phase 0.5; its findings reshaped both
classes. `user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm).
See v1 history for the leader assessments — unchanged by this revision.

**Product/UX Gate:** not applicable. Mechanical UI-surface scan of Files to Create/Edit
returns no hit (all `.sh`/`.md`/`.json`/`.yml` under `scripts/`, `.claude/`, `.github/`,
`knowledge-base/`). Tier **NONE**.

**GDPR / Compliance Gate (2.7):** explicitly not invoked, not a silent skip. Canonical regex
does not match. Trigger (b) fires mechanically but is signal-free under #5175 (every plan
declares the threshold). The CLO assessed this exact scope at brainstorm Phase 0.5:
definitive "no regulated-data surface; nothing to review, nothing to attest." (a)/(c)/(d)
do not fire.

## Plan Review Findings (7 agents; v1 reversed)

| Reviewer | Verdict on v1 |
|---|---|
| **DHH** | P0: class inversion — the 10× class ships prose, the 1× class ships nine artifacts. Cut the CI job ("a printer"), cut PR 2's pointer, amend ADR-076. |
| **code-simplicity** | P0: delete the CI job (self-refuting advisory surface) + cascade-delete the standalone detector. Declines to cut ADR-116. |
| **architecture-strategist** | Confirms fail-open. P0: v1 took ADR-071's non-required half and **dropped its recovery half** — no kill switch, no baseline. P1: ADR-071 misread as precedent. |
| **spec-flow-analyzer** | P0: **lefthook** refutes Q1's premise. P0: invariant never asserted (jq-absent silent allow; cherry-pick/rebase/merge ungated). P1: move-scoping unbuilt. P1: Q2's trigger fires day 0. |
| **CTO (devex)** | P0 (empirical): 50/300 denied, 57% false, `main`'s HEAD denied. P0: no content-anchor exists for `.yml`/`.tf` where citations concentrate. Recommends ship rule+ADR, hold the gate. |
| **Kieran** | P0: `http://` is the comment marker — 555 hits vs 403 claimed. P0: AC7 contradicts the AC1 fixture family. P1: pointer 108 B not 54 B. P1: CI base two-dot vs merge-base. |
| **cpo** | Carried forward from brainstorm Phase 0.5. |

**Operator decisions (User-Challenge, ADR-084 5-line frame):** re-scope + re-measure PR B;
new ADR-116; keep the Class B AGENTS.md pointer.

## Files to Create (PR A)

- `knowledge-base/engineering/architecture/decisions/ADR-116-content-anchored-citations-in-code-comments.md`

## Files to Edit (PR A)

- `AGENTS.md` — two Code Quality pointers, **no bracket tags** (~102 B total).
- `AGENTS.rest.md` — two rule bodies. **Class-gated, not always-loaded** (only `AGENTS.md` +
  `AGENTS.core.md` are). ≤600 B each — **as-shipped 558 / 595** (492/443 were v1 drafts;
  the 595 has only **5 B** of headroom, so re-measure after any edit rather than retyping).
- `knowledge-base/project/specs/feat-citation-rot-bare-token-gates/spec.md` — swept to v2:
  the 10× attribution + TR6, **plus** FR1/TR1/TR4 (the reversed PreToolUse surface), G1–G3,
  Sequencing, the AC block, and the Open Questions.
- `knowledge-base/project/brainstorms/2026-07-16-…-brainstorm.md` — correct the 10×
  attribution + the citation-count figures.
- `knowledge-base/project/learnings/2026-07-16-advisory-first-precedent-…md` — correct the
  10× attribution; **Session Errors #3's prevention rewritten** (a prose predicate does not
  pin a count — the finding this PR's own denominator produced).
- `knowledge-base/project/specs/feat-citation-rot-bare-token-gates/review-findings.md` —
  record the resolution of all 4 P1 + 5 P2, incl. the P1-1 deviation.
- **`#6517` issue body** (`gh issue edit`) — it published `~369` + a wrong `~0.5%`.

No SKILL.md `description:` edit ⇒ Phase 1.8 skipped.

## Open Code-Review Overlap

**None** — verified: `gh issue list --label code-review --state open` returned no body
containing any path above.

## Implementation Phases

### PR A — rung 2 for both classes + the ADR (ship now)

**Task A.1 — ADR-116** via `/soleur:architecture`, including its `## C4 impact` section.

**Task A.2 — `cq-cite-content-anchor-not-line-number`** (Class A convention; prose-only).
Pointer: `- [id: cq-cite-content-anchor-not-line-number] → rest`.
Body in `AGENTS.rest.md` (**as-shipped, 558 B** — synced from the file, not retyped):
> Code comments MUST cite `<file> › <symbol>()`, never `<file>:NNN` — a coordinate carries no claim, so it rots silently (one rotted 35 lines inside its own commit onto a decoy that still echoed the token) [id: cq-cite-content-anchor-not-line-number]. Applies to NEW citations in code comments; the ~360 existing are grandfathered, markdown is exempt, and where no symbol exists (`.tf`/`.yml`/`.toml`) a line citation is permitted — no anchor to prefer. Convention only; no gate enforces it (ADR-116). **Why:** #6479 — the decoy read as confirmation.

**Task A.3 — `cq-assert-anchor-not-bare-token`** (Class B; the 10× class — 8 bare-token + 2
placement, see Overview).
Pointer: `- [id: cq-assert-anchor-not-bare-token] → rest`. Body (**as-shipped, 595 B** — 5 B
under the 600 B ceiling; the P2-1 carve-out clause pushed it to 657 and the linter caught it):
> A body-grep/`indexOf`/`toContain` over FILE CONTENT MUST anchor on `^\s*` or a call-form a comment cannot produce — never a bare token that also appears in a comment (a body-grep sees comments, so prose satisfies it) [id: cq-assert-anchor-not-bare-token]. Narrowing the scope is not the fix; anchor on syntax. Mutation-test every new assertion — if deleting the guard leaves the suite green, it pins nothing. Convention only; no gate enforces it (#6529). **Why:** 10 vacuous assertions in 2 days — 8 bare-token (#6456 ×4, #6479 ×4) + 2 placement (#6479), caught by the mutation clause.

> **These quote-blocks are a rot surface.** They duplicate `AGENTS.rest.md` verbatim, so any
> body edit must re-sync them in the same commit — the plan is a *record*, but a quoted body
> that drifts from the shipped one is a live false claim. They were already stale once (this
> PR's own P2-1/P2-2 edits); re-synced by reading the file, not by retyping.

**Task A.4 — correct the 10× attribution** in spec, brainstorm, learning, and the **#6517
issue body** (`gh issue edit`). The figure is Class B's; Class A recurred once.

**Task A.5 — verify:** `lint-agents-rule-budget.py` (exit 0, B_ALWAYS < 23000);
`lint-rule-ids.py` (pointer↔body residency); `lint-rule-bodies.py --check --base $(git
merge-base origin/main HEAD)` (exit 0, no ack — `cq-*` ungated).

**Task A.6 — comment on #6529** recording that its trigger is **not** mechanical (Q2), with
the day-0 evidence, so the next author does not re-derive a broken grep.

### PR B — the Class A gate (HELD; do not start until PR A merges)

Design of record, gated on **AC-B1** (the replay). Every item below is a v2 correction:

- **Surface: OPEN — the one item below that is *not* settled.** v2 decided `lefthook.yml`
  `pre-commit` → `scripts/lint-line-citations.sh` (the `gitleaks-staged` shape), **not** a
  PreToolUse hook and **not** a CI job. That is right about the PreToolUse hook (Claude-Code-
  only; the repo supports Grok Build) and right to kill v1's *advisory* CI job. But the
  `gitleaks-staged` precedent it invokes is a **two-surface** pattern — its own files call
  the lefthook half *"fast-feedback only"* and CI *"the enforcer"* — and `pre-commit` does
  not fire on **cherry-pick, rebase, or merge** (spec-flow's unanswered P0), nor under
  `--no-verify`. Taking only the non-enforcing half repeats v1's ADR-071 half-taking.
  **Counter-evidence:** `main` has **no branch protection**, so no CI check is truly
  required — the panel's *"fails closed onto nothing"* may hold here. **Action: route the
  surface decision to the `cto` agent at PR B start, before AC-B1** (`## Research
  Reconciliation`, P2-3 row). Do not treat this bullet as decided.
- **Cited-extension allowlist:** `\.(ts|tsx|js|mjs|cjs|jsx|sh|bash|py|sql):[0-9]+(-[0-9]+)?`
  — kills `127.0.0.1:6379`, `4.5:1`, and `.tf`/`.yml` targets in one edit (the last
  deliberately: no symbol anchor exists there, per Task A.2's body).
- **URL guard:** strip `https?://` **before** comment-tail extraction, else `//` in a DSN
  reads as a comment marker (Kieran P0).
- **Move tolerance:** a `+` line whose identical text exists in the pre-image is not "new"
  — or drop the move-scoped claim. Required before G4/AC3 are true.
- **Recovery (ADR-071's dropped half):** a named kill switch (`SOLEUR_CITE_LINE_EXT_RE=^$`
  ⇒ empty scope ⇒ allow), **named in the deny reason**, plus a baseline of pre-existing
  violations. The agent — never the operator — owns recovery.
- **Deny reason names the waiver** (`cite-line:allow # issue:#N`), not just the alternative.
- **Fixtures** build comment markers by concatenation (`H='#'`) so AC-B1 and the fixture
  family do not contradict (Kieran P0).
- **Explicit-fail on missing `jq`** — never a silent universal allow (TR6b).
- Detector inlined into one caller; `exit 2` (internal error) → allow, stated explicitly.
- **Sweep the rule body in the same PR.** `cq-cite-content-anchor-not-line-number` ships
  the clause *"Convention only; no gate enforces it (ADR-116)"* — false the moment PR B
  lands. PR B MUST delete that clause and ADR-116 §Consequences' "stated and unenforced"
  paragraph in its own diff, or the rule rots exactly like the citation it
  bans. **Both rule bodies** carry a *"Convention only; no gate enforces it"* clause
  (`cq-cite-content-anchor-not-line-number` → ADR-116; `cq-assert-anchor-not-bare-token` →
  #6529); whichever gate lands must delete its own clause in the same diff.
- **The `pre-commit` blind spot is now answered, not merely flagged** — see the P2-3 row in
  `## Research Reconciliation`: `pre-commit` does not fire on cherry-pick, rebase, or merge
  (`pre-merge-commit`), which is precisely why the gitleaks precedent pairs it with a CI
  enforcer. It folds into the **open surface decision** above; resolve both together at PR B
  start, before AC-B1.

**AC-B1 (the gate on the gate):** replay the detector over the last 300 commits of `main`.
**Ship only if** denied ≤ **3/300** AND every denial contains a true citation with an
available content anchor. Record the measured numbers in the PR body. v1 scored **50/300 at
57% false** — this AC is what v1 lacked.

## Acceptance Criteria

### Pre-merge (PR A)

- **AC1** `cq-cite-content-anchor-not-line-number` and `cq-assert-anchor-not-bare-token`
  each resolve: pointer in `AGENTS.md`, body in `AGENTS.rest.md`; `lint-rule-ids.py` exits 0.
- **AC2** Neither pointer carries a bracket tag (`grep -E '^\- \[id: cq-(cite-content|assert-anchor)[^]]*\] →' AGENTS.md`
  matches exactly 2 lines, each ending `→ rest`).
- **AC3** `lint-agents-rule-budget.py` exits 0 and reports `B_ALWAYS < 23000`.
- **AC4** `lint-rule-bodies.py --check --base $(git merge-base origin/main HEAD)` exits 0
  with no ack required.
- **AC5** `ADR-116-*.md` exists, `status: accepted`, and contains a `## C4 impact` section.
- **AC6** No artifact still attributes 10 recurrences to Class A: `grep -rn '10×\|10x' `
  over the spec, brainstorm, learning, and plan returns only Class-B-attributed uses.
- **AC7** `gh issue view 6517` body no longer claims Class A recurred 10×.
- **AC9** (added at review) **No live artifact states the citation denominator as a bare
  number.** Every live use of the figure is `~360` *and* is accompanied by — or points at
  (ADR-116 § Context) — the `git grep … | wc -l` command that reproduces it. Historical
  records are exempt and must survive verbatim: the plan's `555 vs 369` row, its Kieran
  `555 vs 403 claimed` row, and the learning's `52 vs 386` + `555 hits vs the 403 I claimed`.
  **Why an AC and not a sweep:** the number had already been swept three times (`369` → `386`
  → `403`) and re-rotted each time, because a sweep replaces a value while the *defect* is
  the absent command.
- **AC10** (added at review) **No artifact asserts a moving reference in the present tense.**
  `cee4e1f55` is described as *"`main`'s HEAD at replay time"*, never *"`main`'s current
  HEAD"* — it was already false when found (main is 7+ commits ahead). Same defect class the
  ADR bans, in the ADR's own evidence table.

  **Both ACs verify with a scoped, structurally-anchored grep — not a bare token:**

  ```sh
  FILES=$(git diff --name-only origin/main...HEAD | grep -v 'brainstorm/SKILL.md')
  grep -nE '^\|.*current HEAD' $FILES /dev/null              # AC10 — must return nothing
  grep -nE '(against|the) (386|403|369) (existing|citations)' $FILES /dev/null  # AC9 — likewise
  ```

  **AC10 took THREE drafts, and the first two are the point.** Draft 1 grepped a bare
  `"current HEAD"` over all of `knowledge-base/` and false-FAILED on four unrelated plans
  (`git revert HEAD` guidance, a RED-state note, a `checkout -B` caveat, a tag-target note) —
  a bare-token grep over prose, the exact defect `cq-assert-anchor-not-bare-token` bans,
  committed *inside the AC that verifies that rule*. Draft 2 anchored on the phrase
  (`` `main`'s current HEAD ``) and scoped to the diff — and **still returned 2 hits**, both
  this plan and the learning *quoting the construct while documenting the fix*.

  **The generalisable finding — a self-documenting grep cannot anchor on its own pattern.**
  Anchoring *harder* does not help: any pattern precise enough to match the assertion also
  matches the prose (and the regex literal) that describes the assertion. The escape is to
  anchor on **structure the documentation cannot have**. The assertion lives in a markdown
  **table row**, so `^\|` pins it; prose, code fences, and the AC's own regex literal all
  start otherwise. Mutation-tested in both directions: the real assertion form injected as a
  table row goes **RED (1 hit)**; the real tree, the documenting prose, the learning's prose,
  and this very code block all stay **GREEN (0)**. *"Narrowing the scope is not the fix;
  anchor on syntax"* — here it needed both, and then it needed the syntax to be one the
  documentation could not produce.
- **AC8** `bash scripts/test-all.sh` green.

### Pre-merge (PR B — held)

- **AC-B1** the 300-commit replay clears ≤3/300 with zero false denials (above).
- Remaining ACs re-derived when PR B starts. **Do not carry v1's AC set forward** — AC7
  contradicted AC1, and AC9 was shard-dependent.

### Post-merge (operator)

**None.** Every step is automatable in-session.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **PR A ships convention with no enforcement** — exactly the "prose failed" posture #6517 indicts. | Accepted, and it is the *point*: rung 2 was never occupied for either class. Learnings live a `grep` away; these rule bodies are **session-injected by `session-rules-loader.sh` on code/infra-class sessions** (`CLASSES="core rest"`, loader :190) — i.e. exactly the class that writes code comments and test assertions. That is the cheapest untried rung. **Corrected at review:** an earlier draft of this row claimed "injected every session", contradicting this plan's own Files-to-Edit line ("`AGENTS.rest.md` — not always-loaded"). Only `AGENTS.md` + `AGENTS.core.md` are always-loaded (`lint-agents-rule-budget.py:6`); a docs-only session loads `core docs-only` (loader :188) and never sees `rest`. The rung-2 argument is *narrower* than first stated and is argued here at its real strength. |
| **The recurrence signal is post-hoc, not preventive.** | If the class recurs after PR A, `/compound` records it — as it did twice (#6456, #6479). But both catches were **after merge**, after the rotted citation had already confirmed a decision. It records recurrence; it does not prevent it. Q2 says plainly there is no mechanical trigger; this row must not re-inflate that into "a real signal". The honest claim: the loop closes on *recording*, not *detection*. |
| **Class B's rule is structurally unmeasurable** (`fire_count: 0` forever; joins 97/99 "unused"). | Recorded in ADR-116 + the rule's `**Why:**`. *Unmeasurable ≠ ineffective* — conflating them is the inverse of the rule-metrics error this session already caught. If `/soleur:sync rule-prune` ever acts on the 97, it proposes deleting rules that were never measurable — a reporter defect. Note for a future issue. |
| **PR B may never ship** (held behind AC-B1). | Acceptable **for the repo-wide gate** — one that denies 1-in-6 commits is worse than no gate. #6529 tracks the Class B gate; the Class A gate is tracked by this plan + ADR-116 §Consequences. **But "hold the gate" ≠ "no mitigation" (P2-5), and this row said so by omission.** The un-enumerated cheaper control: content-anchor **only citations serving as evidence on gates authorizing irreversible actions**. The ~0.28% base rate averages over wildly uneven stakes — the single rotted citation sat on a gate authorizing an irreversible GHCR PAT revoke, where the observed rate is **1-in-1**. That scoping turns ~360 sites into a handful and inverts the cost-benefit holding the repo-wide gate. Recorded in ADR-116 § Alternatives as PR B's strongest candidate; open problem is a mechanical definition of "evidence on an irreversible gate". |
| **ADR-116 ordinal collision.** | `/ship` re-verifies; on renumber sweep plan + tasks + ACs in the same edit (#5990). |
| **`brand-hex-commit-gate.sh` has the same orphan-emit bug** (emits its own name). | Pre-existing, unexercised (never fired). Different subsystem — out of scope, do not bundle. Noted so the next author does not copy it. |

## Test Strategy

PR A is docs/rules only — verification is the three linters + `test-all.sh`. PR B: bash
`.test.sh` (`bats` is **not** installed — verified via `command -v`), fixtures synthesized
only (`cq-test-fixtures-synthesized-only`), every assertion mutation-tested and anchored on
syntax — i.e. **PR B's own tests must satisfy PR A's `cq-assert-anchor-not-bare-token`**.

## Deferred (filed — not in scope)

- **#6529** — the Class B ts-morph gate (~71 files). Trigger is **not** mechanical (Q2).
- **#6530** — verify learnings asserting a standing rule cite one that resolves.
