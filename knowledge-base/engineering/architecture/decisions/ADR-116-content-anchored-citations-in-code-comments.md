---
title: Content-anchored citations in code comments — convention now, born-blocking gate only when it measures clean
status: accepted
date: 2026-07-16
related_adrs: [ADR-071, ADR-076, ADR-092]
related: [6517, 6479, 6456, 6529, 4270]
related_plans:
  - knowledge-base/project/plans/2026-07-16-feat-citation-rot-bare-token-gates-plan.md
related_specs:
  - knowledge-base/project/specs/feat-citation-rot-bare-token-gates/spec.md
brand_survival_threshold: single-user incident
---

# ADR-116: Content-anchored citations in code comments

## Context

Code comments in this repo cite `<file>:NNN`. In PR #6479 a `:151` citation shifted 35 lines
— moved by the same PR's own header expansion — and landed on a **decoy** line that also
echoed `TRANSIENT`, reading to the reviewer as confirmation. The citation rotted *inside the
commit that wrote it*, in a file whose own header already said *"anchored on EMIT NAMES, not
line numbers — line citations rot."*

**~360** such citations exist (measured 2026-07-16). The figure is cited with the command
that produces it rather than with a prose predicate, because **a prose predicate does not pin
a count** — it names a filter without fixing per-line vs per-match, unique vs all, or where
the comment marker must sit. Each is worth 10–30%.

```sh
git grep -hE '(//|#|--).*[[:alnum:]_/.-]+\.(ts|tsx|js|mjs|cjs|jsx|sh|bash|py|sql):[0-9]+' \
  -- '*.ts' '*.tsx' '*.js' '*.mjs' '*.cjs' '*.jsx' '*.sh' '*.bash' '*.py' '*.sql' | wc -l
```

Neighbouring predicates span **319–583**, and **every conclusion below is invariant across
that entire range** (Decision 4). Two known imprecisions, both immaterial today and both in
the conservative direction: it counts per *line* (360) not per *match* (367), and its `//`
alternative also matches `http://`, so a future URL containing a `.ts:NNN`-shaped tail would
inflate it — 0 of the 360 lines contain `https?://` as of 2026-07-16. That second one is
Decision 4's own root cause, latent here.

ADR-076 item 3 already mandates content-anchored citations (`<file> › <symbol>()`,
`<migration> › <table>.<object>`) — but **only for the domain-model register's**
facts/candidates, and its Alternatives row rejected line numbers for a *different* reason:
spurious diffs in the register on unrelated edits, not comment rot. No repo-wide decision
exists, so an engineer reading only the ADR corpus would read content-anchoring as a
register convention.

Issue #6517 proposed a mechanical gate. This ADR records what the convention is, and why the
gate is not yet built.

## Decision

1. **Code comments cite `<file> › <symbol>()`, never `<file>:NNN`** — generalizing ADR-076
   item 3 from the domain-model register to all code. Carried by the rule
   `cq-cite-content-anchor-not-line-number` (`AGENTS.rest.md`, injected on every code/infra
   session by the class-aware loader — which is exactly the session class that writes code
   comments).

2. **Three carve-outs, all load-bearing:**
   - **New citations only.** The ~360 existing are grandfathered permanently; no retroactive
     sweep.
   - **Markdown is exempt** — thousands of sites. No count is asserted: nothing here rests on
     the magnitude, and no stated predicate pins it (readings span 848–18,395). An archived
     plan's citation is a historical record, not a live claim; "validating" it is a category
     error.
   - **Where the cited file has no symbols (`.tf`, `.yml`, `.toml`), a line citation is
     permitted.** There is no anchor to prefer, and infra is exactly where citations
     concentrate. A ban without an available alternative forces a waiver on every infra
     citation.

3. **Any mechanical enforcement of (1) ships born-blocking**, never advisory-first.

4. **Enforcement is not yet built.** A v1 detector was specified, measured, and rejected:

   | Measurement | Result |
   |---|---|
   | Commits denied, last 300 on `main` | **50/300** (~1 in 6) |
   | Hits that are not citations | **73/128 (57%)** — `127.0.0.1:6379`, `10.0.1.30:5000`, `4.5:1`, `3.66:1` |
   | Denied commits containing zero true citations | **19/50** |
   | **`cee4e1f55`** — PR #6479's merge commit, **the PR that motivated this ADR**; `main`'s HEAD at replay time (2026-07-16), since superseded | **DENIED** (`inngest-host.tf:181`, `cloud-init.yml:408`, `server.tf:241`, +3) |

   Root cause: `http://` **is** the TS comment marker, so a DSN string literal such as
   `postgres://127.0.0.1:54322/db` denies a line containing no comment at all — the `//`
   opens a "comment" and the tail `127.0.0.1:54322` matches the citation shape. Class A's own defect rate is **~0.28%** (one
   rotted citation against ~360, and 0.17–0.31% across the whole 319–583 predicate range —
   the comparison does not depend on which predicate you pick); a detector with a 57% error
   rate is two orders of magnitude worse than the defect it guards — it **is** the
   false-certification class it exists to stop. A re-scoped gate ships only when it clears a replay AC: **≤3/300 denied on the last
   300 commits of `main`, with zero false denials.**

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Validate citation resolvability (#6517's original proposal) | A coordinate carries no content assertion, so no resolver knows what it *meant* to point at. The #6479 decoy — a 35-line intra-file shift onto a line still echoing the token — **passes** it. Measured 2026-07-16: **367 citation occurrences → 334 resolvable → 0 past-EOF**, reproduced by the command below (§ Measuring the resolvability figures). Past-EOF is the only rot a resolver detects; intra-file drift is the rot that happens. |
| Advisory-first with a calibration window (#6517's stated AC) | #4270's window is OPEN at 56 days against a stated "2 weeks", with zero findings logged organically. Advisory→blocking promotion has never once happened in this repo; the arm that did ship blocking (#4646 brand rules) was **born** blocking and skipped calibration. Advisory-first is the highest-probability path to a write-mostly artifact. |
| Amend ADR-076 instead of a new ADR | ADR-076's subject is the drift extractor; broadening it to all code comments would misrepresent that decision, and its line-number rejection was for extractor spurious-diffs — a different rationale. *Dissent recorded:* ADR-076 self-amends twice (#5871, #5872), so amendment-by-appending is an established convention. Operator decided for a new ADR. |
| Ban line citations everywhere, including `.tf`/`.yml` | No symbol anchor exists there, so the ban would force a waiver on every infra citation — and infra is where citations concentrate. Carve-out instead (Decision 2). |
| Build the gate now and fix false positives as they surface | It would deny ~1 commit in 6 on day one — including, at the time of measurement, `main`'s own HEAD — against a non-technical operator with no kill switch. Measure first (Decision 4). |
| **Scope the gate to citations serving as *evidence* on gates authorizing irreversible actions** | **Not rejected — the strongest candidate for PR B, recorded here because Decision 4's base-rate argument conceals it.** ~0.28% averages over a population whose stakes are wildly uneven, and the one citation that rotted sat in the highest-stakes position available: evidence on a gate authorizing an **irreversible GHCR PAT rotate-and-revoke** (#6479). In *that* population the observed defect rate is **1-in-1**, not 1-in-360. Scoping the gate there turns ~360 sites into a handful, which inverts the cost-benefit that holds the repo-wide gate: a small denominator with a 100% observed defect rate is exactly where a born-blocking gate pays for itself, and the false-positive blast radius shrinks with the scope. It needs a mechanical definition of "evidence on an irreversible gate" (the open problem — likely a marker at the citation site rather than an inferred property). **"Hold the repo-wide gate" is not "no mitigation"**; that elision is what left this un-enumerated until review. |

### Measuring the resolvability figures

The row above rejects #6517's original proposal on the strength of **0 past-EOF**, so that
figure gets a command for the same reason the denominator in § Context does — **a measurement
cited without the command that produces it decays into prose**, and the next reader cannot
check it. (Two independent resolvers disagreed on the neighbouring counts during review — 367
occurrences vs 368, 33 unresolved vs 32+2 — while agreeing on the 0. That disagreement *is*
the argument for publishing the command: it settles which predicate the numbers belong to.)

```sh
EXTS='ts|tsx|js|mjs|cjs|jsx|sh|bash|py|sql'
occ=0; res=0; unres=0; eof=0
while IFS= read -r hit; do
  occ=$((occ+1)); target=${hit%:*}; line=${hit##*:}
  f=$(git ls-files --full-name -- "$target" | head -1)
  if [ -z "$f" ] && [ "$(git ls-files --full-name -- "*/$target" | wc -l)" -eq 1 ]; then
    f=$(git ls-files --full-name -- "*/$target")
  fi
  [ -z "$f" ] && { unres=$((unres+1)); continue; }
  res=$((res+1))
  [ "$line" -gt "$(wc -l < "$f")" ] && eof=$((eof+1))
done < <(git grep -hoE "(//|#|--).*[[:alnum:]_/.-]+\.($EXTS):[0-9]+" \
    -- '*.ts' '*.tsx' '*.js' '*.mjs' '*.cjs' '*.jsx' '*.sh' '*.bash' '*.py' '*.sql' \
  | grep -oE "[[:alnum:]_/.-]+\.($EXTS):[0-9]+")
echo "occurrences=$occ resolved=$res unresolved=$unres past_eof=$eof"
# 2026-07-16: occurrences=367 resolved=334 unresolved=33 past_eof=0   (~26s)
```

*Resolution rule:* exact tracked path, else a **unique** `*/`-suffix match; anything else counts
unresolved (basename-ambiguous or untracked target). `unresolved` is not rot — it is the
resolver declining to guess, which is itself why a resolvability validator is weak here.

- **The convention is stated and unenforced** until a re-scoped gate clears its replay AC.
  This is deliberate, not an oversight: rung 2 — a session-injected `AGENTS.md` rule — was
  **never occupied** for this class. It lived only in learnings, which sit a `grep` away from
  where an author writes a citation, whereas `AGENTS.md` rules are injected by
  `session-rules-loader.sh` on every session of their change class (`rest` → code/infra).
  The escalation ladder is learning → rule → gate; #6517 argued
  for rung 3 on the premise that rung 2 had failed. It had never been tried.
- The ~360 existing citations are grandfathered permanently.
- Both new rules are prose-only and have **no emitter**, so their rule-metrics `fire_count`
  stays 0 forever and they join the 97-of-99 rules the unused-rule reporter lists.
  **Unmeasurable is not ineffective** — do not prune them on that basis.
- **The prune hazard is already handled structurally, better than prose would manage** —
  `rule-prune.sh` only emits a candidate when **`.first_seen != null`**, and
  `rule-metrics-aggregate.sh` defaults an event-less rule to `first_seen: null`. An
  emitter-less rule is therefore **unreachable as a prune candidate** by construction, not by
  convention. (It still *appears* in the `rules_unused_over_8w` report, which deliberately
  admits `first_seen == null` — appearing in that report and being prunable are different
  things, and conflating them is what makes the hazard look real.) The invariant is named
  here so a future refactor that drops the `first_seen != null` guard has to falsify a
  written claim rather than silently arm the prune path against every prose rule.
- If the gate is later built, **its surface is OPEN — this ADR does not decide it.** Two
  things *are* decided: it is **not** a PreToolUse hook (Claude-Code-only; this repo also
  supports Grok Build), and it is **not** an *advisory* CI job (a non-required check that
  "fails closed" fails closed onto nothing). What remains open is **lefthook `pre-commit`
  alone vs. lefthook + a load-bearing CI enforcer**:
  - The `gitleaks-staged` precedent is **two-surface**, and taking only its lefthook half
    would repeat the ADR-071 half-taking this ADR criticises. Its own files say so:
    `lefthook.yml` calls that half *"fast-feedback companion to the load-bearing CI gate …
    bypass with `git commit --no-verify` is intentionally possible"*, and `secret-scan.yml`
    calls itself *"the enforcer"*. `pre-commit` also fires on **none** of cherry-pick,
    rebase, or merge (which uses `pre-merge-commit`).
  - **Counter-evidence, weighed equally:** `main` currently has **no branch protection**
    (`gh api …/branches/main/protection` → 404), so no CI check here is truly *required* —
    a real point for the panel and against naively adding one.
  - **Routed to the `cto` agent at PR B start**, before AC-B1. See the plan's PR B §Surface
    and the P2-3 row in its Research Reconciliation. **Do not read this bullet as settling
    the surface** — an ADR outlives its plan, so the openness has to be recorded *here*, not
    only there.

  Whatever surface wins, it must carry what ADR-071 pairs with its own gate and v1 dropped:
  a named kill switch and a baseline — *"the agent — never the founder — owns gate
  maintenance, baseline refresh, and recovery."*
- The sibling class (`cq-assert-anchor-not-bare-token`) is the one that actually recurred
  **10× across #6456 and #6479** — but "all 10 are bare-token" is imprecise, and the
  precision matters. The accurate sub-attribution is **8 bare-token** (#6456 ×4, #6479 ×4)
  **+ 2 placement-vs-semantics** (#6479), summing to 10 of a common parent class: *vacuous
  assertions* — a guard that passes without pinning what it names. This **vindicates the
  rule's two-clause design** rather than complicating it: the *anchor* clause catches the 8,
  and the *mutation-test* clause catches the 2 (a misplaced assertion is still green when
  the guard is deleted). A one-clause rule would have caught 8 of 10. Its gate is deferred
  to #6529 for the same reason as Class A's — measure before arming.

## C4 impact

None. All three model files were read (`model.c4`, `views.c4`, `spec.c4`), not keyword-grepped.
A commit-time citation convention adds no external human actor (there is no correspondent,
sender, or recipient) and no external system or vendor. The only container it would ever touch
is `hooks = container "Hook Engine"`, which is already modeled as a **leaf** (components hang
off `plugin`, not `engine`), is included in `views.c4` as an element only, has no kind in
`spec.c4`, and whose description — *"Guards tool calls (blocks commits to main, rm -rf,
etc.)"* — already absorbs a future guard. No ownership or access relationship changes, and no
element description is falsified.
