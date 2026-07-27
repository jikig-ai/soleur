---
title: "An instrument that misreports its own coverage suppresses the signal that would fix it (#7008)"
date: 2026-07-27
issue: 7008
pr: 7006
category: investigation
tags: [agents-md, rules-loader, telemetry, governance, subagents, context-engineering]
related:
  - 6794
  - 3681
  - 2865
---

# Instrument self-misreporting, inert mechanisms, and subagent counts as claims

Captured while auditing Anthropic's Claude-5 context-engineering guidance against
Soleur's rules corpus (#7008, PR #7006).

## 1. A denominator bug hid a 2× footprint — in three places, not one

`.claude/hooks/session-rules-loader.sh:247` computes its total-rule denominator as:

```bash
TOTAL_RULES=$(grep -hE '^- .*\[id: ' "$REPO_ROOT"/AGENTS*.md | wc -l)
```

The glob `AGENTS*.md` matches the **index** (`AGENTS.md`, 101 pointers) *and* the three
**bodies** (53 + 6 + 42 = 101), counting every rule twice. The session stamp therefore
reads `loaded: core+docs-only+rest (101 of 202 rules)` — which parses at a glance as *half
the corpus* — when it is in fact **100% of a 101-rule corpus**.

This is the exact number an operator consults to ask "is progressive disclosure working?"
It answers reassuringly and wrongly.

**The same category error lives in at least two more places.** #6794
([[2026-07-22-rule-metrics-denominator-investigation]]) already identified `202 = 2 × 101`
in the *rule-metrics aggregator* and fixed it there — but the fix was scoped to where the
bug was found rather than swept for the computation shape. Running compound's own Phase 1.5
step 8 rubric today:

```bash
A=$(grep -h '^- ' AGENTS*.md | wc -l)   # → 202
```

So the third instance is in the governance rubric that is supposed to *police* the corpus.

**Generalisable:** when you find a denominator/scope bug, `grep` for the *computation
shape* across the repo before closing — not just the symptom you were handed. A glob that
spans an index and its expansion double-counts by construction, and the pattern
propagates by copy-paste between sibling tools.

## 2. A mechanism can be fully implemented, correct, tested — and structurally inert

Soleur's change-class rules loader has a brainstorm, a spec, a plan, unit tests, and a
learning titled "measured savings" behind it. It is not broken. Yet:

| Session class | Loads | Share of real PRs |
|---|---|---|
| multi-class | **all 3 sidecars, 43.5 KB** | 68% (80 PRs) / 72% (200 commits) |
| docs-only | core+docs, 26.2 KB | 20% / 17% |
| code/infra | core+rest, 40.2 KB | 10% / 9.5% |

Weighted mean saving: **~8.7%** — against the ~50% its own stamp implies. Clean-tree and
question-only sessions also fail open (`[[ -z "$CHANGES" ]]` → all classes), pushing the
realistic fail-open rate to 75–85%.

The cause is not a defect. **Soleur's own workflow gates mandate a learning/spec `.md`
alongside code in nearly every PR**, which makes almost every PR multi-class by
construction. The governance rules defeated the governance mechanism.

**Generalisable:** to check whether a progressive-disclosure / caching / routing mechanism
works, classify the last N *real historical inputs* through the mechanism's **own
predicate** — do not infer effectiveness from the mechanism's existence, its tests, or its
self-reported stats. Reuse the predicate rather than copying it, so the audit cannot drift
from the thing audited.

## 3. A subagent's COUNT is a claim to re-derive, not a fact to quote

Four count errors in one session, all confidently stated, none flagged as uncertain:

| Source | Claimed | Actual | Cause |
|---|---|---|---|
| orchestrator (me) | 202 rules, 50% loaded | 101, 100% | trusted the miscomputed stamp above |
| CPO | 103 retired ids | **58** | counted the file's total *lines*, not data rows |
| CPO | 116 shipped files w/ rule refs | **11** | broad rule-id mention vs. actual path reference |
| repo-research | 2,400 → reported 2,296 words | **2,400** | silently counted 91 of 95 skills |

The shape is consistent: a count taken from a file whose lines are **not all data rows**
(comments, blanks, headers), or from a glob that silently under/over-matches. Each was
refuted by one command.

**Generalisable:** re-derive any count that will bound a decision, ideally two ways
(grep the source *and* read the artifact that publishes it — the #6794 discipline). Treat
"N of M" from any tool as two separate claims: is N right, and is M measuring the same
population as N? In this session numerator and denominator were over *different scopes*,
which no single-number sanity check would have caught.

## 4. Agent reports on governance state need a landed-vs-proposed check

`learnings-researcher` returned confident recommendations to "land PR #2762" and "adopt
the discoverability litmus" — **both shipped in April, three months prior**. It read a
brainstorm whose frontmatter says `status: decided` as a live proposal.

Verification cost two commands: `ls scripts/retired-rule-ids.txt` (58 retirements on disk)
and a grep of the litmus text in `AGENTS.rest.md` (present, inside
`wg-every-session-error-must-produce-either`).

**Generalisable:** when an agent reports on the state of *governance artifacts*, check
frontmatter `status:` and the on-disk evidence before acting. A brainstorm marked
`decided` is a record of what shipped, not a proposal — and prior-art searches
preferentially surface the *proposal* document because it is longer and more keyword-dense
than the one-line change that implemented it.

## 5. `git log --merges` returns nothing in a squash-merge repo

The first fail-open measurement sampled `git log --merges -n 60` and got **zero** rows,
then divided by zero. Soleur squash-merges, so `main` has no merge commits; PR boundaries
are `--no-merges` commits.

**Generalisable:** before sampling "recent PRs" from git history, confirm the repo's merge
strategy. `--merges` and `--no-merges` are each empty-set-producing on the wrong strategy,
and an empty set plus an unguarded arithmetic expansion fails loudly only by luck.

## 6. The dividing line for applying external model-guidance to a rules corpus

The audit's substantive conclusion, worth preserving independently:

> Claude Code's system prompt described **the tool**; Soleur's rules describe **the world
> the tool acts on**.

Anthropic removed >80% of Claude Code's system prompt because it encoded *generic
behaviours* newer models perform by default. Soleur's judgment-expressible rules were
already removed by the discoverability litmus — **58 of 159 rules ever created (36%) are
retired**. What survives is predominantly **environment facts no model can infer at any
capability level**: Warp intercepts terminal escape sequences; `SENTRY_AUTH_TOKEN` 403s
where `SENTRY_IAC_AUTH_TOKEN` works; `dev` and `prd` must resolve to distinct Supabase
refs. A smarter model does not thereby learn that your Sentry token is misprovisioned.

Corroborating datum: the Opus 4.6→4.7 upgrade
(`knowledge-base/project/brainstorms/2026-04-16-model-upgrade-opus-4-7-brainstorm.md`)
retired **zero** rules as obsolete and added zero rules for model-specific failure modes.
Soleur has never observed model-version-dependent rule necessity.

Corollary for hook-enforced rules: their sidecar prose is redundant **as enforcement** (the
hook blocks the action) but load-bearing **as explanation** — the deny message cites the
rule id, so deleting the prose leaves the agent blocked without knowing why, and it routes
around the block. Trim to one line; never delete.

## Session Errors

1. **Asserted a 202-rule corpus and "50% loaded" in the routing brief and two subagent
   prompts.** Recovery: re-derived from source (`grep -c '^- \[id: ' AGENTS.md` = 101) and
   sent in-flight corrections to both agents. **Prevention:** §1 and §3 above — the
   instrument was wrong, and I quoted it instead of deriving it.
2. **Consumed 3-month-stale agent recommendations.** Recovery: verified against on-disk
   evidence before use. **Prevention:** §4 landed-vs-proposed check.
3. **Three subagent count errors (58/103, 11/116, 2400/2296).** Recovery: re-derived each
   directly. **Prevention:** §3.
4. **`git log --merges` returned 0 rows → division by zero.** Recovery: switched to
   `--no-merges`. **Prevention:** §5.
5. **Edit failed against a table row that did not exist** in the brainstorm doc.
   Recovery: re-read and appended after the correct anchor. One-off; the Edit tool failed
   loudly and cost one round-trip. No prevention warranted.
6. **Roadmap drift left unfixed** (`STALE_STATUS|phase 4|roadmap=56o/179c|milestone=72o/187c`).
   Deliberate: an unrelated roadmap edit does not belong in this PR. Fix path is
   `/soleur:trigger-cron cron/roadmap-review.manual-trigger`. Not an error — a recorded
   scope decision.

## Rule-promotion decision

**No AGENTS rule added.** `B_ALWAYS` is at `[WARN] 22900` against a 23,000 REJECT ceiling
(100 B headroom) and the longest rule body is **exactly at the 600 B per-rule cap**. Every
insight here is discoverable-with-evidence and therefore routes to this learning file per
the discoverability litmus in `wg-every-session-error-must-produce-either` — which is the
litmus working as designed on the very session that audited it.

---

## 7. A fix for a placebo can itself be a placebo — check the *reachability* of the predicate you are fixing

Plan v1 correctly caught that `scripts/rule-prune.sh` computes `is_he` for
`[hook-enforced]`/`[skill-enforced]` but never `continue`s, so the "exemption" only
decorates a breadcrumb string. It then proposed adding `[compliance-tier]` to that same
predicate and a real `continue`.

That fix could never have worked. `sanitized_prefix` is truncated to `RULE_PREFIX_LEN=50`
(`scripts/lib/rule-metrics-constants.sh:13`), and `[compliance-tier]` sits at **character
214 of a 349-character line**. A substring test against a 50-char prefix cannot match at
any point. The corollary is worse: the *existing* `is_he` has therefore always evaluated
0, making `rule-prune.sh:193`'s `($hook_enforced hook/skill-enforced)` a standing
tautology that has been reported as fact.

**Generalisable:** when fixing a predicate that "doesn't fire", verify the predicate's
**input can physically contain what it tests for** before changing the test. Truncation,
normalisation, case-folding, and field-extraction upstream all silently make a correct-looking
test unreachable. The tell is a fix that changes the *comparison* without ever inspecting
the *operand*.

Severity also moved on evidence, in the opposite direction from the initial framing:
`rule-prune.sh:15` states *"Neither mode edits AGENTS.md — humans retire rule text in a
separate PR"*, and 4 of the 5 `[compliance-tier]` rules are `hr-*`, already hard-skipped at
`:154-157`. The exposure was a bad *proposal* on one rule, not a deletion.

## 8. "Dead citation" is a claim about INTENT — three of four were load-bearing

Plan v1 flagged four rule-id citations that resolve to neither `AGENTS.md` nor
`retired-rule-ids.txt`, and proposed repairing all four. Three were legitimate, and each
proposed repair would have damaged a working file:

| Site | What it actually is | Damage the "fix" would have done |
|---|---|---|
| `plugins/soleur/skills/plan/SKILL.md:968` | **Narration** of PR #5349's descope inside a `**Why:**` clause | Renders the sentence unintelligible |
| `plugins/soleur/skills/deepen-plan/SKILL.md:775` | The **worked example of a fabricated id**, inside the checklist that teaches agents to detect fabricated ids. The line literally reads "(fabricated, never existed)" | Deletes the lesson; makes the prose false |
| `cq-pencil-collapse-auto-recover` (6 files) | A **deliberate tier-gate carve-out** — `scripts/rule-metrics-aggregate.sh:302-309` documents it in place: *"per `cq-agents-md-tier-gate`, the rule body lives in the hook header + pencil-setup SKILL (a Pencil-domain rule is tier-gated OUT of AGENTS.md)"*. It is also a live runtime key in `.claude/.rule-incidents.jsonl` | Removing the exclusion trips the aggregator's orphan gate; orphans emitted records |

Only `plugins/soleur/skills/ship/SKILL.md:770` was a genuine dead citation.

**Generalisable:** an unresolvable identifier is not automatically a defect. Before
"repairing" one, read the *surrounding sentence* and grep for an existing carve-out. Three
intents produce legitimately-unresolvable ids: **narration** (describing history),
**exemplification** (teaching what a bad id looks like), and **deliberate tier-gating**
(the body lives elsewhere by policy). A resolver lint that does not model all three is
net-negative — which is exactly why the proposed lint was deferred (~45 raw hits, ~30 of
them mandated test fixtures, plus `\b` matching `rf-worktrees` inside `block-rm-rf-worktrees`).

**Corollary on scope:** the same audit found the *real* orphan class is wider than the
spec knew — `.claude/hooks/durable-reminder-prefer-inngest.sh:6`,
`scripts/betterstack-query.sh:52`, `scripts/rule-prune.sh:17`, and a wrong-prefix citation
at `worktree-manager.sh:817`. Being wrong about which four does not mean there is nothing
there; it means the census was never run.

## 9. Session errors (plan phase)

7. **Proposed a fix that could not reach its target** (FR5). Recovery: architecture-strategist
   traced the truncation; verified independently. **Prevention:** §7.
8. **Proposed three repairs that would have damaged working files** (FR9). Recovery:
   code-simplicity + Kieran + spec-flow independently converged; verified each against
   source. **Prevention:** §8.
9. **Dropped two spec requirements silently.** Spec FR4 (skill descriptions 2,400 → ≤1,800
   words) and TR2 appeared in no plan phase, AC, or Non-Goal. Caught only by spec-flow.
   **Prevention:** when a plan claims to implement "N spec FRs", enumerate the spec's FR
   list and mark each implemented / deferred / out-of-scope — absence is invisible otherwise.
10. **Found a bug, wrote it in a learning, then omitted it from the plan.** The
    `compound/SKILL.md:257` doubled glob was measured during the brainstorm and recorded in
    §1 above, but never reached Files-to-Edit until CTO re-found it. **Prevention:** a
    finding recorded in a learning is not thereby scheduled; cross-check the learning's
    findings against the plan's work-list before the plan is final.
