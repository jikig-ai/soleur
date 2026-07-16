---
title: "PR #6527 review findings — all 4 P1 + all 5 P2 resolved"
date: 2026-07-16
pr: 6527
issue: 6517
status: resolved
resolved_at: 2026-07-16
---

# PR #6527 (PR A) — review findings

5 agents ran (`non-code` class + `user-impact-reviewer` at the `single-user incident`
threshold). **All 4 P1 and all 5 P2 findings are now RESOLVED** — see `## Resolution` below.
The original findings are preserved verbatim as the record of what was found.

## Resolution (2026-07-16, `/work`)

| Finding | Disposition |
|---|---|
| **P1-1** denominator | **Resolved, but NOT as prescribed — see the deviation below.** |
| **P1-2** spec specifies the reversed surface | Resolved. `spec.md` swept to plan v2: FR1 → lefthook `pre-commit` (+ new FR1b/FR1c/FR2b), TR1/TR4 struck and corrected, G1–G3 corrected, Sequencing inverted (PR A first), AC1–AC5 marked HELD, AC7 dropped, Open Questions 1–3 marked resolved. |
| **P1-3** "always-loaded" is false | Resolved. `spec.md` G2 and `tasks.md` header now state the **class-gated** truth (`core rest` on code/infra; `core docs-only` otherwise) and argue rung 2 at its real, narrower strength. |
| **P1-4** User-Brand Impact | Resolved. Third bullet added naming PR A's own vector — *an ADR or rule body that misstates its own enforcement or load reach* — citing **P1-3 and P2-1** as its two pre-merge instances. |
| **P2-1** missing carve-out clause | Resolved. `Convention only; no gate enforces it (#6529).` appended to `cq-assert-anchor-not-bare-token`. |
| **P2-2** sub-attribution | Resolved. **8 bare-token + 2 placement = 10 vacuous assertions** in the rule body, ADR-116 § Consequences, plan Overview, and spec — framed as *vindicating* the two-clause design (anchor clause → the 8; mutation clause → the 2). |
| **P2-3** cherry-pick/rebase/merge ungated | **Resolved by answering it, and it surfaced something larger.** The `gitleaks-staged` precedent PR B cites is a **two-surface** pattern — both files say so (`lefthook.yml`: *"fast-feedback companion to the load-bearing CI gate"*; `secret-scan.yml`: *"this workflow is the enforcer"*). PR B kept only the **non-enforcing** half, repeating v1's ADR-071 half-taking. `pre-commit` fires on none of cherry-pick / rebase / merge (`pre-merge-commit`), nor under `--no-verify`. Recorded as a new Research Reconciliation row + PR B's **surface bullet reopened**; routed to the `cto` agent at PR B start. Counter-evidence recorded too: `main` has **no branch protection**, so no CI check is truly required. |
| **P2-4** PR body | Owned by `/ship`: `Ref #6517`, never `Closes` (PR B outstanding on the same issue). |
| **P2-5** mitigation mis-located | Resolved. Recorded in ADR-116 § Alternatives as **PR B's strongest candidate** (not rejected) + the plan's Risks row: content-anchor **only citations that are evidence on gates authorizing irreversible actions**. The ~0.28% base rate averages over uneven stakes — the one rotted citation sat on an irreversible GHCR PAT revoke, where the rate is **1-in-1**. Scoping there turns ~360 sites into a handful and inverts the cost-benefit. Open problem: a mechanical definition of "evidence on an irreversible gate". |
| **P3** prune hazard | Adopted. ADR-116 § Consequences now cites the **`first_seen != null`** invariant by name (verified: `rule-prune.sh` requires it; `rule-metrics-aggregate.sh` defaults an event-less rule to `null`), and distinguishes *appearing in `rules_unused_over_8w`* from *being prunable*. |

### P1-1 deviation: `403` is not reproducible, so it was not adopted

The finding prescribed sweeping the 7 residual sites to **403 + the stated predicate**. That
prescription was **not** followed, with operator approval, because **403 could not be
reproduced by its own stated predicate**.

18 faithful readings of *"a line in a code file (`ts,tsx,js,mjs,cjs,jsx,sh,bash,py,sql`)
bearing a comment marker AND citing `<path>.<src-ext>:<N>`"* returned:

> 319, 322, 358, 373, 419, 433, 477, 478, 583 — **never 403.**

(The nearest neighbours *bracket* it: 419 and 433. The `477`/`478` readings land within ~2 of
the review's own "475 (unique)", so the methodologies are close — they differ only in details
the prose leaves free: per-line vs per-match, unique vs all, whether the citation must follow
the marker, and whether markers are language-correct. Each is worth ±10–30%.)

**Why this mattered more than a number.** P1-1's own prescription — quoting this PR's
learning — is *"require the filter be stated with the number"*. This session is the
counter-example: the filter **was** stated, and it still did not pin the count. **A prose
predicate is itself a bare-token assertion** — it names a referent without fixing it. Writing
an unreproducible `403` into a PR whose thesis is *"a check must not certify the wrong
thing"* would have shipped the indicted defect, in the artifact indicting it.

**What shipped instead:** the figure is stated **with the command that reproduces it**
(ADR-116 § Context), never with a description of one — the same fix the rule itself
prescribes for citations (anchor on content, not on a coordinate). **~360** today.

**Why nobody caught it, and why that is reassuring rather than alarming:** the conclusion is
**invariant across the entire 319–583 range** (0.17–0.31%, vs the detector's 57%). Nothing
ever depended on the precision — which is exactly why false precision survived a 5-agent
panel unchallenged. Related: the `~0.5%` arithmetic was overstated and is corrected to
**~0.28%**. (An earlier version of this line sized the overstatement as "~2×, since
1/403 = 0.248%" — deriving the correction basis from the very number this document declares
unreproducible, twenty lines above. Against the **adopted** ~360 the overstatement is
**1.80×**. Caught at re-review by `code-quality-analyst`.)

**Also corrected while sweeping:** the `0 past-EOF` claim — the load-bearing one, since it
rejects the resolvability validator — was **re-verified and holds exactly** (334 resolvable,
0 past-EOF). Its companions were not: `386 unique / 330 resolvable` → **320 / 334**. And the
public **#6517 body** was published with `~369` + the wrong `~0.5%`; both corrected there.

---

## Original findings (verbatim — the record of what was found)

The PR's *deliverables* are sound and verified — ADR-116, both rule bodies (558 B / **595 B**
as-shipped; this line said "534 B" while asserting *verification* over it — an unanchored
figure inside the sentence claiming it was checked, caught at re-review),
tagless pointers, `B_ALWAYS=22900/23000`, all three linters exit 0, `test-all.sh` 178/178,
diff purely additive (0 removed lines), 0 secret matches. The P1s are all in the **planning
artifacts**, and every one of them is this PR shipping the defect it indicts.

## P1-1 — the denominator is unlabelled and filter-dependent (`pr-introduced`)

**Found by:** code-quality-analyst.

The grandfathered population is stated as **369** in some places and **386** in others,
across ADR-116, plan, spec, learning, `AGENTS.rest.md` — **neither states its predicate**.
The reviewer could not reconcile them (measured 367 / 415 / 442 / 497 depending on filter).
Re-measured in-session: **568** (any cited ext) / **475** (unique) / **403** (canonical).

The number is entirely predicate-dependent. This PR's own learning, Session Error #3,
prescribes the fix it violates: *"require the filter be stated with the number ('N sites,
where site = `<predicate>`')."*

**Canonical figure to adopt (measured 2026-07-16, rebased tree):**

> **403** — where *site* = a line in a code file (`ts,tsx,js,mjs,cjs,jsx,sh,bash,py,sql`)
> bearing a comment marker AND citing `<path>.<src-ext>:<N>` whose `<src-ext>` is itself a
> source extension (i.e. a symbol anchor could exist). This predicate matches the rule's
> scope exactly.

**Also fix the arithmetic:** `~0.5% defect rate` is wrong — 1/403 = **0.248%**. Consistently
~2× overstated. (Conclusion survives: "two orders of magnitude worse than the defect" holds.)

**Residual sites still carrying an unlabelled `386` (7 sites / 4 files):**
`ADR-116` (Alternatives row), `plan` (`0/386` in the ADR quote-block), `spec` (NG1, NG5),
`learning` (×3, incl. "grandfathers the 386").

**Do NOT rewrite** the plan's `555 vs 369` row — that is a *historical* record of what
Kieran measured against v1's then-claimed figure. A sweep already corrupted it once to
"555 vs 403" and it has been restored.

## P1-2 — spec.md still specifies the surface the panel REVERSED (`pr-introduced`)

**Found by:** code-quality-analyst.

`spec.md` is a **new file** in this diff. Only its 10× attribution and TR6 were corrected;
everything else the 7-agent panel reversed survives as a live requirement:

- **FR1 / TR1 / TR4** — "a **PreToolUse** hook … registered in `.claude/settings.json` under
  `PreToolUse`/`Bash`". Plan Q1 reversed this: **lefthook `pre-commit`**, *not* PreToolUse
  (the hook is Claude-Code-only; the repo supports Grok Build).
- **Sequencing** — "PR 1 (Class A) — hours. Ships first; unblocks immediately." Plan: PR B is
  **held** behind AC-B1.
- **G3** — "promotion depend[s] on rule-metrics fire counts." ADR-116 §Consequences proves a
  prose rule has no emitter ⇒ `fire_count: 0` forever. G3 is unachievable as written.
- **G2** — "Put the anchoring rule on the always-loaded surface (AGENTS.md)". False; see P1-3.

**Fix:** sweep spec.md to match plan v2, or mark the FR/TR/G sections superseded by the plan.
A spec contradicting its own plan on the reversed decision is how v1's error re-enters.

## P1-3 — "always-loaded" is false, and was load-bearing (`pr-introduced`)

**Found by:** user-impact-reviewer + pattern-recognition-specialist (independently).

`AGENTS.rest.md` is **not** always-loaded. Ground truth:
- `lint-agents-rule-budget.py:6` — `B_ALWAYS = AGENTS.md + AGENTS.core.md` **only**.
- `session-rules-loader.sh:188` — a docs-only session loads `CLASSES="core docs-only"`;
  `:190` — code/infra loads `CLASSES="core rest"`.

So `rest` is **class-gated**: injected on code/infra sessions, never on docs-only. The claim
was load-bearing for the ADR's central "rung 2 was never tried" argument, and the plan
**contradicted itself** (Files-to-Edit correctly said "not always-loaded" while Risks claimed
"injected every session").

**The corrected argument is still strong, just narrower:** the rule fires on exactly the
session class that writes code comments and test assertions. Argue it at that strength.

**Fixed:** ADR-116 (×3 sites, by pattern-recognition), plan Overview / Risks / §117.
**Residual:** `spec.md:56` (G2), `tasks.md:17`.

## P1-4 — User-Brand Impact describes a gate this PR does not ship (`pr-introduced`)

**Found by:** user-impact-reviewer.

Both clauses enumerate a **gate's** failure. PR A ships no gate. Its artifact is an ADR + rule
bodies *asserting an enforcement posture*; its real vector is **a reader concluding protection
exists**. P1-3 is that vector having already fired, pre-merge, uncaught by the section.

**Fix:** add a third bullet naming PR A's own artifact — *"an ADR or rule body that misstates
its own enforcement or load reach"* — and cite P1-3 as its first instance.

## P2s (open)

- **P2-1** (user-impact) — `cq-assert-anchor-not-bare-token` lacks the *"Convention only; no
  gate enforces it"* clause that Class A's body carries. It sits two lines below
  `cq-test-fixtures-synthesized-only`, which carries `[hook-enforced: …]`; a reader infers
  enforcement from the asymmetry. Append `Convention only; no gate enforces it (#6529).`
- **P2-2** (git-history) — recurrence **sub**-attribution. "All 10 are Class B" is imprecise:
  #6479's six are *"four grep, two placement-vs-semantics"*, and placement ≠ bare-token. Correct
  figure: **8 bare-token + 2 placement = 10 vacuous-assertion**. This *vindicates* the rule's
  two-clause design (anchor clause → the 8; mutation-test clause → the 2). Fix in ADR-116
  §Consequences, plan Overview, spec.
- **P2-3** (code-quality) — `## Plan Review Findings` credits spec-flow-analyzer with
  "cherry-pick/rebase/merge ungated" but no Research Reconciliation row or PR B response answers
  it. It is live: lefthook `pre-commit` genuinely does not fire on rebase/merge. (Partially
  fixed inline by the agent — verify.)
- **P2-4** (security) — PR body is still the draft stub with no `#6517` reference. `/ship` owns
  the body; it MUST use `Ref #6517`, never `Closes` (PR B is outstanding on the same issue).
- **P2-5** (user-impact, FINDING 4) — mitigation mis-located. Holding the repo-wide gate is
  correct, but "hold the gate" ≠ "no mitigation". Un-enumerated cheaper control: content-anchor
  **only citations serving as evidence on gates authorizing irreversible actions**. That scopes
  403 → a handful, where the observed defect rate is 1-in-1. File or scope-out with a reason.

## P3s (no action)

- Budget headroom: 22,900/23,000, ~100 B left. Next two rules hit the ceiling. `pre-existing`,
  symmetric, warned by the linter. Worth a retirement pass on `AGENTS.core.md`.
- Prune hazard is **already handled structurally** (better than ADR-116's prose says):
  `rule-prune.sh:68-71` requires `first_seen != null`, and the aggregator defaults an
  event-less rule to `first_seen: null` — so an emitter-less rule is unreachable as a prune
  candidate. Suggest ADR-116 cite the `first_seen != null` invariant by name.
- `status: accepted` on ADR-116 is correct — an ADR records a decision, not an implementation
  (code-quality explicitly retracted this attack).

## Verified clean (no action)

- Self-reference check **passes**: the markdown exemption is *explicitly stated* in the rule
  body (`AGENTS.rest.md`), not assumed — and a docs-only session loads `core docs-only`, so the
  rule cannot even fire on this PR's own class.
- Tagless pointers correct: 0 of 101 index pointers carry bracket tags.
- `→ rest` is the correct class (loader :190, `HAS_CODE||HAS_INFRA` → `core rest`).
- Ids never used before (`git log --all -S`); immutable-safe.
- `cee4e1f55` **is** PR #6479's merge commit (verified).
- ADR-076 / ADR-071 / ADR-092 characterizations all accurate.
- No guardrail weakened: diff is purely additive, 0 removed lines; no ack needed (`cq-*` is
  outside `GATED_PREFIX_RE = ^(hr|wg)-`).
