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
