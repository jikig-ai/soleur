---
title: Evaluate Graphify for Soleur — code base and knowledge base
date: 2026-08-03
type: brainstorm
status: decided — decline for KB (#4206); narrow code-axis probe on #5708
lane: cross-domain
brand_survival_threshold: single-user incident
external_tool: https://github.com/Graphify-Labs/graphify
supersedes_consideration_of: kb-search Stage 3 candidate set (#4206)
---

# Brainstorm: Adopt Graphify for Soleur?

## What We Evaluated

Whether **Graphify** (Graphify-Labs, Apache-2.0) should be adopted to improve Soleur
agent understanding, memory, search, and token efficiency — assessed separately for
the **code base** and the **knowledge base**.

The operator scoped this at Phase 1.2 as a **KB / Stage-3 bakeoff**: judge Graphify as
a candidate implementation for the OPEN, unbuilt `kb-search` Stage 3 (#4206) against
the harness and threshold Soleur already committed to, rather than by argument.

That framing turned out to be answerable **without running the bakeoff** — the
mechanism is disqualifying on inspection. See Key Decision 1.

## Verified Tool Facts (premise gate, Phase 1.0)

Probed directly from the repo API on 2026-08-03 — not README claims.

- **Apache-2.0**; `NOTICE` retains `LICENSE-MIT` for pre-relicense contributions.
- **v0.9.32 — pre-1.0.** 101k stars, 9.8k forks, **768 open issues**, pushed 2026-08-01.
- Python library + Claude Code skill + **MCP stdio server** (`serve.py`; optional
  `mcp`/`starlette` extras). Pipeline: `detect → extract → build_graph → cluster →
  analyze → report → export`; tree-sitter AST → NetworkX → Leiden. **No vector store.**
- Runtime deps are local-only (networkx, numpy, rapidfuzz, ~28 tree-sitter grammars).
  No telemetry dependency declared.
- Ships `benchmark.py` — "corpus vs subgraph token comparison".
- **`llm.py` is 143 KB and `google_workspace.py` exists** → LLM/cloud paths are present.
  Per the vendor's own `skill.md`, "zero LLM credits" holds for **code only**: docs,
  papers and images go through *semantic extraction* using **Gemini** when
  `GEMINI_API_KEY`/`GOOGLE_API_KEY` is set, "otherwise the host agent itself is the LLM."
- **PyPI distribution name is `graphifyy` (double-y), not `graphify`.**
- `graphify/skill.md` is ~40 KB, with ~16 harness-specific variants of similar size.
- Vendor BENCHMARKS.md (self-reported, vendor's own harness, judge Kimi K2.6):
  LOCOMO recall@10 0.497, LOCOMO QA 45.3%, LongMemEval-S 76%. **Treated as claims.**

## Decision

**Decline Graphify for the knowledge base. Run a narrow, time-boxed code-axis probe
under the existing #5708 track. Axis B (user repos) unchanged — stays deferred.**

| Surface | Verdict | Rationale |
|---|---|---|
| **Knowledge base** (#4206 Stage 3) | **Decline** | Its markdown path indexes headings, filenames and explicit links only — never paragraph text. A strictly smaller lexical surface than the grep arm that already plateaus at R@5(heavy) 0.297. Cannot clear the committed 0.4 gate. |
| **Code base** (Axis A, #5708) | **Probe, time-boxed** | This is Graphify's real competency (28 language extractors; `resolution.py` 115 KB, `engine.py` 257 KB) against ~3,200 Soleur code files. Its own `benchmark.py` measures the exact token delta that would justify or kill it. |
| **User repos** (Axis B, #5708) | **Unchanged — deferred** | All prior gates still apply; nothing in this evaluation moved them. |

## Why This Approach

The KB question is settled on **mechanism**, not on a measurement — which saves the
~50-minute / ~$2.68 bench run and, more importantly, produces a durable reason that
survives the next candidate tool. The code axis is where the tool's actual engineering
lives, and it already ships the instrument that would decide it.

## Key Decisions

**1. The KB decline rests on a verified mechanism, not a prediction.**
`graphify/extractors/markdown.py` is 194 lines. It emits a file node, one node per
`^#{1,6}` heading, `contains` edges for heading nesting, and `references` edges for
explicit links. It returns `input_tokens: 0` — deterministic precisely because it reads
no paragraph text. Measured against the live corpus:

| Signal | Measured (2026-08-03) |
|---|---|
| Learnings corpus | **2,084** `.md` files (2,079 excluding `archive/`) |
| Corpus composition | **~98.5% prose** — ~111,830 lines total, ~1.1k lines inside code blocks |
| Cross-doc relative `.md` links | **271**, spread over **122 files (5.9%)** |
| Wikilinks (`[[...]]`) | 753 |
| Top headings | `## Tags` ×920, `## Key Insight` ×788, `## Solution` ×677, `## Problem` ×527, `## Session Errors` ×354 |

~94% of learnings carry no outbound cross-doc link, and the heading population is
overwhelmingly a handful of repeated template strings. The graph would be sparse and
boilerplate-dominated.

The composition row is the decisive corroboration: the corpus is **~98.5% prose**, so
Graphify's 28 AST extractors have essentially nothing to parse, and the one extractor
that does run on `.md` is the heading-and-link parser that ignores prose. Both halves of
the tool miss the corpus.

**2. The lexical ceiling is why this is fatal, and it is already established.**
`2026-05-20-retrieval-diagnostic-findings.md` concluded the heavy-paraphrase ceiling is
a **property of keyword methods, not a corpus or gold-set artifact** — bare grep maxes
at R@5(heavy) 0.2966 while searching *full text*. Graphify's deterministic path searches
a strict subset of that (headings + filenames + links). It cannot beat a superset of its
own signal.

**3. The prose-capable path is LLM extraction — confirmed verbatim by the vendor, and it
inverts the token-efficiency goal.** `graphify/skill.md` states:

> "Code is extracted structurally (AST) with no LLM and no key at all — a code-only
> corpus … skips semantic extraction entirely … **Semantic extraction (only for docs,
> papers, and images) uses Gemini only if `GEMINI_API_KEY`/`GOOGLE_API_KEY` is already
> set; otherwise the host agent itself is the LLM.**"

Three consequences, all against adoption for the KB:

- The "$0 / deterministic / no-vector-store" property that makes Graphify attractive
  applies **only to code**. Our corpus is ~98.5% prose, so it sits entirely on the
  semantic path.
- **Token efficiency inverts.** With no Gemini key set, *the host agent is the LLM* —
  indexing 2,084 prose learnings bills semantic extraction to Soleur's own agent tokens.
  A tool adopted to reduce token cost would impose a large one-off, and recurring
  per-update, cost on exactly the corpus in question.
- **Egress becomes concrete, not hypothetical.** With a key set, the named third-party
  recipient is **Google/Gemini** — by design, for precisely our file types. That sharpens
  the CLO gate from "architecturally possible" to "documented default for this corpus".

It also repeats a failed experiment: Stage 2 already shipped an LLM pre-pass and
**regressed** heavy recall by −0.038 while adding cost.

**4. Graphify does NOT re-open the "no embeddings" brand objection.** The 2026-04-07
decision rejected RAG partly on the brand line "no vector DB, no embeddings". Graphify's
no-vector-store design is genuinely compatible with that constraint — it fails on
extraction depth, not on brand. Recording this so the next evaluation does not
re-litigate the wrong axis.

**5. The bench baseline is stale.** Committed metrics were taken on a **1,163**-file
corpus; the corpus is now **2,084** files. Any future Stage-3 evaluation must re-baseline
first, or it will compare against a corpus that no longer exists.

**6. Pre-commitment against a fourth loop (CPO).** This is the third evaluate-then-defer
cycle on this need (codebase-memory-mcp → pgvector → Graphify). This brainstorm
**terminates Graphify as a #4206 candidate**; #4206 proceeds to the embeddings ADR it
originally framed, or closes. No fourth candidate absent a user-side signal.

**7. The bakeoff path is cheap and reusable — recorded for the next candidate.**
`scripts/learning-retrieval-bench.sh` dispatches retrievers as shell functions
(`kbsearch_rank` / `grep_rank`, signature `(query, source_path, synced_paths_json) → rank`).
A third arm is added by defining one same-signature function and inserting it in the
Phase-3 dispatch loop. With `--cache-paraphrases`, a rerun makes **no Anthropic API calls
and costs nothing** — so re-benchmarking a future Stage-3 candidate is near-free once the
paraphrase cache exists. Note this constrains the candidate: it must expose a synchronous
ranked-path emitter. An MCP stdio server is *not* callable from that bash loop.

**8. Marketing consequence is independent of the build decision (CMO).**
`marketing-strategy.md` names the compounding knowledge base as moat #1 and rates memory
commoditization as an **existential** contingency. A 101k-star, free, multi-harness memory
layer is that trigger arriving early. Recommendation: demote "we remember" from stated
moat to table stakes on our own terms; the durable claim is the corpus and the
cross-domain loop, not the retrieval mechanism.

## Open Questions

1. **Code-axis probe design (blocking the probe, not this decision):** does Graphify's
   TypeScript/bash/SQL/Terraform extraction over ~3,200 Soleur files produce a token
   saving that survives index-maintenance cost across **19 live worktrees**?
   `watch.py` is single-working-tree; regeneration is per-tree and currently unbudgeted.
2. **Egress proof (CLO hard gate, if the probe runs):** `llm.py` and `google_workspace.py`
   make outbound architecturally real. Settle with a deny-all-egress netns run plus host
   packet capture — PASS = zero non-loopback packets **and** a successful run (a
   fail-closed run proves nothing).
3. **`graphifyy` pinning (CLO hard gate):** hash-pinned requirement, pinned index-url,
   and a CI assertion positive on both sides — `graphifyy==0.9.32` present **and**
   `graphify` absent from the resolved set.
4. **Does #4206 proceed to the embeddings ADR, or close?** Graphify is eliminated; the
   original ADR framing (OpenAI vs Voyage vs local bge/nomic) is untouched by this work.
5. **Is R@5(heavy) even the right gate?** (CPO) It is a synthetic query class; identity
   and light buckets are already materially better. The operator-visible outcome — fewer
   duplicate learnings, fewer repeats of documented mistakes — is unmeasured.

## User-Brand Impact

- **Artifact:** a third-party pre-1.0 graph indexer (`graphifyy` 0.9.32) reading Soleur's
  `knowledge-base/` and source tree on the operator's machine.
- **Vector:** confidential engineering, incident, and legal material — plus operator and
  team personal data present in the corpus — silently egressing to a third party via the
  optional LLM/Google code paths if the local-only assumption is wrong or regresses.
- **Threshold:** single-user incident.
- **Mitigation:** the decline removes the KB exposure entirely. If the code-axis probe
  runs, Open Questions 2 and 3 are hard gates before it touches real content.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO), Marketing (CMO).
Operations, Sales, Finance, Support assessed low-relevance — an internal tooling
adoption with no customer-facing, pipeline, or expense surface (no recurring vendor
cost: the OSS package is free and no hosted plan is proposed).

### Engineering (CTO)

**Summary:** Graphify's markdown path is a heading-and-link structural parser that never
reads paragraph text; on Soleur's 2,084 learnings it yields mostly-boilerplate heading
nodes and a near-disconnected graph, a strictly smaller lexical surface than the grep arm
already at R@5(heavy) ≈0.30, so it cannot plausibly clear the ≥0.4 gate — and its
prose-capable path requires the LLM pass Stage 2 already showed regresses recall.

### Product (CPO)

**Summary:** In scope only for Soleur's own knowledge base, never for user KBs; judge on
the existing harness against the pre-committed gate with no identity/light regression.
Whatever the result, this bakeoff must close out the #4206 line rather than open a fourth
evaluate-then-defer loop. Nothing broke in the 2.5 months the need went unserved — the
need is real but low-severity.

### Legal (CLO)

**Summary:** CLEAR-WITH-CONDITIONS — Apache-2.0 imposes no duties for local-only use
(NOTICE/attribution trigger only if we vendor or redistribute), but `llm.py` /
`google_workspace.py` make egress architecturally real and the knowledge base does
contain personal data, so a deny-all-egress packet-capture proof and `graphifyy`-vs-
`graphify` install pinning are hard gates before indexing.

### Marketing (CMO)

**Summary:** Adjacent infrastructure with a competing *claim*, not a competing product —
safe to adopt internally, but adoption should be paired with demoting "compounding
memory" from stated moat to table stakes, since `marketing-strategy.md` already rates
memory commoditization as an existential trigger and Graphify is that trigger arriving
early.

## Capability Gaps

None blocking. One recorded for the code-axis probe:

- **Multi-worktree index maintenance.** Graphify's `watch.py` tracks a single working
  tree; Soleur runs 19 live worktrees (`git worktree list`, 2026-08-03). Any code-axis
  adoption needs a per-tree regeneration story that does not exist today. Evidence:
  read `graphify/watch.py` module responsibilities in upstream `ARCHITECTURE.md`;
  worktree count from `git worktree list`.

## Session Errors

1. **Subagent counts diverged from direct measurement — direct values used.** The CTO
   reported 353 cross-doc links across 153 files (7.3%); direct measurement on the same
   corpus gave **271 across 122 files (5.9%)** (`grep -rhoE '\]\(\.{1,2}/[^)]+\.md\)'`).
   Both support the same conclusion; the measured values are recorded. Per
   `hr-…`/"a subagent's COUNT is a claim to re-derive".
2. **CPO quoted Stage-2 R@5 values (identity 0.802 / light 0.675) matching neither
   `learning-retrieval-metrics-2026-05-20.json` (0.775 / 0.636) nor the #4206 issue body
   (0.7528 / 0.5928).** The committed JSON is treated as authoritative. Three different
   number sets are in circulation for the same stage — a re-baseline (Key Decision 5)
   should collapse them.
3. **`extract.py` grep produced a false negative on the prose path.** Searching the
   264 KB `extract.py` for a markdown extractor returned nothing, which read as "no prose
   support". The extractor lives in `graphify/extractors/markdown.py`. Corrected before
   it reached the decision; recorded because the near-miss would have inverted Key
   Decision 4 (brand axis) into a wrong "no doc support at all" claim.
   **Prevention:** in a modular codebase, list the `extractors/`-style handler directory
   before concluding a per-type handler is absent from the monolithic dispatch file.
4. **An unverified inference briefly reached the document.** Key Decision 3 initially
   asserted the prose path "runs through `llm.py`" — an inference from a subagent finding
   plus the file's existence, not something measured. A subagent-cited path
   (`references/add-watch.md`) 404'd, so the quote it carried was never confirmed.
   Re-probed `graphify/skill.md` directly and found the vendor's own verbatim statement,
   which turned out to be **materially stronger and more specific** (Gemini, or the host
   agent as LLM). Corrected in place.
   **Prevention:** when a subagent's supporting citation fails to resolve, treat the
   claim it carried as unverified and re-probe from a path you have listed yourself —
   do not let the conclusion survive on the subagent's authority alone.
5. **The `graphifyy` PyPI naming trap was nearly missed.** It surfaced only from reading
   `pyproject.toml`'s `name =` field directly rather than the repo name or install docs.
   **Prevention:** for any Python tool adoption, read `[project].name` in `pyproject.toml`
   — the repo name is not the distribution name.
